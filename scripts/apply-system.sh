#!/usr/bin/env bash
# Ubuntu 26.04 GNOME. System half of the setup: baseline snapshot, third-party
# repos, packages, debloat, system/ files, services, firewall, virtualization.
# Hardware-specific steps (Intel GPU packages, the Windows-disk rule) are
# detected, never assumed. Idempotent: re-run after editing anything in system/.
#
#   sudo bash scripts/apply-system.sh                 # default groups
#   sudo bash scripts/apply-system.sh --groups all    # + docker
#   sudo bash scripts/apply-system.sh --dry-run       # print the plan, change nothing
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TEAL='\033[38;2;136;192;208m'
RED='\033[38;2;191;97;106m'
RESET='\033[0m'
ok()      { echo -e "  ${TEAL}✓${RESET} $1"; }
info()    { echo -e "  ${TEAL}→${RESET} $1"; }
warn()    { echo -e "  ${RED}!${RESET} $1"; }
section() { echo -e "\n${TEAL}━━━ $1 ━━━${RESET}"; }

GROUPS_WANTED="base,desktop,dev,virt,security,vpn,media,tools"
DRY=0
SNAPSHOT=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --groups) shift; GROUPS_WANTED="${1:-}"; [ -n "$GROUPS_WANTED" ] || { echo "--groups needs a list, e.g. base,dev or all" >&2; exit 2; } ;;
        --dry-run) DRY=1 ;;
        --no-snapshot) SNAPSHOT=0 ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ "$GROUPS_WANTED" = all ] && GROUPS_WANTED="base,desktop,dev,virt,security,vpn,media,tools,docker"

exec 3>&1  # the dry-run plan goes to the terminal even where a command's output is discarded
run() { if [ "$DRY" -eq 1 ]; then echo "  [dry] $*" >&3; else "$@"; fi; }
# debconf_set "pkg question type value" — never `echo | run …`: in a dry run the
# reader exits without reading and echo can die of SIGPIPE (exit 141 under pipefail)
debconf_set() { if [ "$DRY" -eq 1 ]; then echo "  [dry] debconf-set-selections: $1"; else echo "$1" | debconf-set-selections; fi; }

if [ "$EUID" -ne 0 ] && [ "$DRY" -eq 0 ]; then
    echo "This script needs root. Re-run: sudo bash scripts/apply-system.sh" >&2
    exit 1
fi
# the invoking user gets the libvirt/kvm/wireshark groups; pkexec sets PKEXEC_UID
TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] && [ -n "${PKEXEC_UID:-}" ]; then TARGET_USER="$(id -nu "$PKEXEC_UID")"; fi
if [ -z "$TARGET_USER" ] && [ "$DRY" -eq 1 ]; then TARGET_USER="${USER:-$(id -un)}"; fi
# a dry run may come from root (CI runs it in a container); a real run may not
if [ -z "$TARGET_USER" ] || { [ "$TARGET_USER" = root ] && [ "$DRY" -eq 0 ]; }; then
    echo "Run this through sudo or pkexec from your normal user, not from a root shell." >&2
    exit 1
fi

. /etc/os-release
if [ "${ID:-}" != ubuntu ] || [ "${VERSION_ID:-}" != 26.04 ]; then
    echo "Written for Ubuntu 26.04; this is ${PRETTY_NAME:-unknown}. Stopping." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# deploy SRC DST [MODE] — install only when the content differs; returns 1 when unchanged
deploy() {
    local src=$1 dst=$2 mode=${3:-0644}
    if cmp -s "$src" "$dst"; then return 1; fi
    run install -D -m "$mode" "$src" "$dst" || { warn "install failed: $dst"; return 2; }
    ok "$dst"
}

# unit_exists NAME — true when systemd knows the unit (installed package)
# (pipelines end in a full read, never `grep -q`: with pipefail an early exit turns into SIGPIPE = failure)
unit_exists() { systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep . >/dev/null; }
# installed NAME — true when the package is installed (not just left over)
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep 'install ok installed' >/dev/null; }

section "Preflight"
info "user: $TARGET_USER  groups: $GROUPS_WANTED  dry-run: $DRY"
run apt-get update -q
ok "apt index refreshed"

section "Baseline snapshot (Timeshift)"
# a full rsync snapshot of / (home excluded by Timeshift's default config) before
# anything else changes, so the fresh install stays one restore away
run apt-get install "${APT_OPTS[@]}" timeshift
rootdev=$(findmnt -no SOURCE /)
if [ "$SNAPSHOT" -eq 1 ] && [ "$DRY" -eq 0 ]; then
    # config first: the swap file and VM/container images must never be copied
    # into a snapshot; daily ×3 + weekly ×2 via Timeshift's cron entry
    mkdir -p /etc/timeshift
    python3 - <<'PY'
import json, pathlib
p = pathlib.Path("/etc/timeshift/timeshift.json")
cfg = json.loads(p.read_text()) if p.exists() else {}
cfg.update({"schedule_daily": "true", "count_daily": "3",
            "schedule_weekly": "true", "count_weekly": "2",
            "schedule_monthly": "false", "schedule_boot": "false", "schedule_hourly": "false"})
excl = cfg.setdefault("exclude", [])
for e in ["/swap.img", "/var/lib/libvirt/images/***", "/var/lib/containers/***",
          "/var/cache/apt/archives/***", "/var/lib/snapd/cache/***"]:
    if e not in excl:
        excl.append(e)
p.write_text(json.dumps(cfg, indent=2) + "\n")
PY
    ok "timeshift.json: excludes swap file, VM and container images; daily ×3, weekly ×2"
    if [ -d /timeshift/snapshots ] && [ -n "$(ls -A /timeshift/snapshots 2>/dev/null)" ]; then
        ok "snapshots already exist ($(find /timeshift/snapshots -mindepth 1 -maxdepth 1 | wc -l)); not creating another baseline"
    else
        timeshift --create --rsync --snapshot-device "$rootdev" --scripted \
            --comments "baseline before ubuntu_setup" >/dev/null
        ok "baseline snapshot created on $rootdev (sudo timeshift --list)"
    fi
else
    info "snapshot skipped"
fi

section "Third-party repositories"
# keys pinned by SHA-256 (verified against the vendors' published fingerprints:
# Microsoft BC52…29CF, Mullvad A119…8DDF, Tailscale 2596…5868)
fetch() { # url sha256 dest
    local tmp; tmp=$(mktemp)
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$1" -o "$tmp"
    echo "$2  $tmp" | sha256sum -c --quiet - || { rm -f "$tmp"; echo "checksum mismatch: $1" >&2; exit 1; }
    run install -D -m 0644 "$tmp" "$3"; rm -f "$tmp"
}
run install -d -m 0755 /etc/apt/keyrings
sources_changed=0
[ -f /etc/apt/keyrings/microsoft.asc ] || fetch https://packages.microsoft.com/keys/microsoft.asc \
    2fa9c05d591a1582a9aba276272478c262e95ad00acf60eaee1644d93941e3c6 /etc/apt/keyrings/microsoft.asc
[ -f /etc/apt/keyrings/mullvad-keyring.asc ] || fetch https://repository.mullvad.net/deb/mullvad-keyring.asc \
    67cee5d3e6d566c121c2c812d594ba673aaf73e6a679ab6d254f03e8210c49d1 /etc/apt/keyrings/mullvad-keyring.asc
[ -f /etc/apt/keyrings/tailscale-archive-keyring.gpg ] || fetch https://pkgs.tailscale.com/stable/ubuntu/resolute.noarmor.gpg \
    3e03dacf222698c60b8e2f990b809ca1b3e104de127767864284e6c228f1fb39 /etc/apt/keyrings/tailscale-archive-keyring.gpg
deploy system/vscode.sources    /etc/apt/sources.list.d/vscode.sources    && sources_changed=1 || true
deploy system/mullvad.sources   /etc/apt/sources.list.d/mullvad.sources   && sources_changed=1 || true
deploy system/tailscale.sources /etc/apt/sources.list.d/tailscale.sources && sources_changed=1 || true
# Google Chrome: the key file rotates subkeys, so it is verified by primary
# fingerprint instead of file hash; skipped when a Chrome repo already exists
# (the package manages its own file from then on)
fetch_key_fpr() { # url fingerprint dest
    local tmp; tmp=$(mktemp)
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$1" -o "$tmp"
    if gpg --show-keys --with-colons --with-fingerprint "$tmp" 2>/dev/null | awk -F: '/^fpr/ {print $10}' | grep -x "$2" >/dev/null; then
        run install -D -m 0644 "$tmp" "$3"; rm -f "$tmp"
    else
        rm -f "$tmp"; echo "fingerprint mismatch: $1" >&2; exit 1
    fi
}
if ! grep -rqs 'dl.google.com/linux/chrome' /etc/apt/sources.list.d/; then
    [ -f /etc/apt/keyrings/google-chrome.asc ] || fetch_key_fpr https://dl.google.com/linux/linux_signing_key.pub \
        EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 /etc/apt/keyrings/google-chrome.asc
    deploy system/google-chrome.sources /etc/apt/sources.list.d/google-chrome.sources && sources_changed=1 || true
fi
# the code package would otherwise add a second copy of its repo
debconf_set "code code/add-microsoft-repo boolean false"
if [ "$sources_changed" -eq 1 ]; then run apt-get update -q; fi
ok "VS Code, Mullvad, Tailscale, Chrome (deb822, Signed-By keyrings)"

section "Packages"
# wireshark: dumpcap setuid so members of the wireshark group can capture
debconf_set "wireshark-common wireshark-common/install-setuid boolean true"
mapfile -t wanted < <(awk -v groups=",$GROUPS_WANTED," '
    /^\[/ { g=$0; gsub(/[][]/, "", g); active = index(groups, "," g ",") > 0; next }
    /^[[:space:]]*(#|$)/ { next }
    active { print $1 }' packages/apt.txt)
# one apt-cache call for the whole list: a package prints "name:" then an
# indented Candidate line; unknown names print nothing
mapfile -t avail < <(apt-cache policy "${wanted[@]}" 2>/dev/null | awk '/^[^ ]/ {pkg=$1; sub(":$", "", pkg)} /^ *Candidate:/ && $2 != "(none)" {print pkg}')
pkgs=(); missing=()
for p in "${wanted[@]}"; do
    if printf '%s\n' "${avail[@]}" | grep -x "$p" >/dev/null; then pkgs+=("$p"); else missing+=("$p"); fi
done
[ "${#missing[@]}" -eq 0 ] || warn "not in any enabled repo, skipped: ${missing[*]}"
# docker.io ships /usr/bin/docker itself and conflicts with the podman shim; once
# the engine is installed, apt would resolve that conflict by removing docker.io
if [[ ",$GROUPS_WANTED," == *,docker,* ]] || installed docker.io; then
    kept=(); for p in "${pkgs[@]}"; do [ "$p" = podman-docker ] || kept+=("$p"); done; pkgs=("${kept[@]}")
    info "podman-docker left out (conflicts with docker.io)"
fi
# Intel VA-API / OpenCL packages only make sense with an Intel GPU
if command -v lspci >/dev/null && ! lspci -nn -d ::0300 2>/dev/null | grep '\[8086:' >/dev/null; then
    kept=(); for p in "${pkgs[@]}"; do case "$p" in intel-media-va-driver-non-free|intel-opencl-icd) ;; *) kept+=("$p") ;; esac; done; pkgs=("${kept[@]}")
    info "no Intel GPU found: intel-media-va-driver-non-free and intel-opencl-icd left out"
fi
info "${#pkgs[@]} packages requested"
run apt-get install "${APT_OPTS[@]}" "${pkgs[@]}"
ok "packages installed"

section "Debloat"
# kdump-tools reserves 1 GB of RAM for a crash kernel nobody reads on a laptop;
# whoopsie uploads crash reports to Canonical; cloud-init is already disabled by
# /etc/cloud/cloud-init.disabled and only adds boot units; wsdd is spawned by
# gvfs for "Windows Network" and multicasts WS-Discovery probes on every
# interface (SMB shares by address keep working)
purge=()
for p in kdump-tools whoopsie cloud-init wsdd; do
    installed "$p" && purge+=("$p")
done
if [ "${#purge[@]}" -gt 0 ]; then
    run apt-get purge "${APT_OPTS[@]}" "${purge[@]}"
    ok "purged: ${purge[*]}"
else
    ok "nothing to purge"
fi
run apt-get autoremove --purge "${APT_OPTS[@]}"
# packages removed but not purged are reported, never purged automatically:
# grub-pc's leftover shares /etc/default/grub with grub-efi-amd64 and purging it
# deletes the live file
mapfile -t rc < <(dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null | awk '$4 == "config-files" {print $1}')
[ "${#rc[@]}" -eq 0 ] || info "removed but not purged (check shared conffiles before: dpkg --purge): ${rc[*]}"
# apport: local crash collection with a long privilege-escalation history; the
# GNOME "report problems" toggle already sends nothing
if grep -q '^enabled=1' /etc/default/apport 2>/dev/null; then
    run sed -i 's/^enabled=1/enabled=0/' /etc/default/apport
    ok "/etc/default/apport enabled=0"
fi
# motd-news fetches motd.ubuntu.com daily with release/kernel/CPU/uptime in the
# User-Agent; Pro's apt_news pulls the same feed on every apt run
deploy system/motd-news /etc/default/motd-news || true
if command -v pro >/dev/null && pro config show apt_news 2>/dev/null | grep True >/dev/null; then
    run pro config set apt_news=false && ok "pro: apt_news=false"
fi
for u in apport.service avahi-daemon.socket avahi-daemon.service cups-browsed.service ModemManager.service motd-news.timer; do
    unit_exists "$u" || continue
    if [ "$(systemctl is-enabled "$u" 2>/dev/null)" != disabled ] || systemctl is-active --quiet "$u"; then
        if run systemctl disable --now "$u" >/dev/null 2>&1; then ok "disabled $u"; else warn "could not disable $u"; fi
    fi
done
info "avahi: no mDNS announcements on untrusted networks (add printers by address); cups-browsed: CVE-2024-47176 class; ModemManager: no WWAN in this model"

section "ClamAV signatures"
# the package enables neither the freshclam daemon nor its daily timer, so the
# signatures shipped at install time would silently go stale
if unit_exists clamav-freshclam-once.timer; then
    if [ "$(systemctl is-enabled clamav-freshclam-once.timer 2>/dev/null)" != enabled ]; then
        run systemctl enable --now clamav-freshclam-once.timer >/dev/null 2>&1 && ok "clamav-freshclam-once.timer enabled (daily, catches up after downtime)"
    else
        ok "clamav-freshclam-once.timer enabled"
    fi
fi

section "Kernel and network hardening (system/)"
if deploy system/99-hardening.conf /etc/sysctl.d/99-hardening.conf; then run sysctl --system -q >/dev/null || warn "a sysctl key was rejected: sysctl --system"; fi
# ufw applies its own sysctl file after boot and would reset log_martians to 0
if grep -q '^net/ipv4/conf/\(all\|default\)/log_martians=0' /etc/ufw/sysctl.conf 2>/dev/null; then
    run sed -i 's#^\(net/ipv4/conf/\(all\|default\)/log_martians\)=0#\1=1#' /etc/ufw/sysctl.conf
    run sysctl -q -w net.ipv4.conf.all.log_martians=1 net.ipv4.conf.default.log_martians=1
    ok "/etc/ufw/sysctl.conf: log_martians=1 (no longer overrides the sysctl.d value)"
fi
deploy system/99-disable-modules.conf /etc/modprobe.d/99-disable-modules.conf && reboot_needed=1 || true
if deploy system/99-hardening.cfg /etc/default/grub.d/99-hardening.cfg; then run update-grub >/dev/null 2>&1 || warn "update-grub failed; run it by hand"; reboot_needed=1; fi
# a restart drops the per-link DNS a VPN or Tailscale set, so only restart on change
if deploy system/resolved-hardening.conf /etc/systemd/resolved.conf.d/hardening.conf; then run systemctl restart systemd-resolved; fi
if deploy system/nm-privacy.conf /etc/NetworkManager/conf.d/99-privacy.conf; then run nmcli general reload conf >/dev/null 2>&1 || true; info "MAC/hostname privacy applies when Wi-Fi reconnects"; fi
deploy system/coredump-none.conf /etc/systemd/coredump.conf.d/none.conf || true
if deploy system/journald-limits.conf /etc/systemd/journald.conf.d/limits.conf; then run systemctl restart systemd-journald; fi
if visudo -cf system/sudo-hardening >/dev/null; then
    deploy system/sudo-hardening /etc/sudoers.d/10-hardening 0440 || true
else
    warn "system/sudo-hardening failed visudo -c; not installed"
fi
deploy system/apt-unattended-local.conf /etc/apt/apt.conf.d/52unattended-upgrades-local || true
if deploy system/apt-daily-upgrade-battery.conf /etc/systemd/system/apt-daily-upgrade.service.d/battery.conf; then run systemctl daemon-reload; fi
ok "sysctl, modprobe, GRUB, resolved, NetworkManager, coredump, journald, sudo, unattended-upgrades"

section "Browser policies"
# the Firefox snap reads /etc/firefox/policies through its etc-firefox interface
deploy system/firefox-policies.json /etc/firefox/policies/policies.json || true
deploy system/chrome-policies.json /etc/opt/chrome/policies/managed/privacy.json || true
ok "Firefox: telemetry, Studies, Pocket, sponsored content off; Chrome: metrics and background mode off"

section "Firewall (ufw)"
# no `ufw reset`: re-runs must keep rules added by hand; ufw skips duplicates
run ufw default deny incoming
run ufw default allow outgoing
run ufw default deny routed
# drop any blanket allow-in rule on virbr0/tailscale0 before the narrower rules
# go in (`ufw status` omits IN without --verbose; the delete removes the v6 twin)
ufw_has() { ufw status 2>/dev/null | grep -E "$1" >/dev/null; }
ufw_has '^Anywhere on virbr0 +ALLOW( IN)? +Anywhere' && run ufw delete allow in on virbr0
ufw_has '^Anywhere on tailscale0 +ALLOW( IN)? +Anywhere' && run ufw delete allow in on tailscale0
# libvirt NAT: guests reach the host's dnsmasq only (DNS 53, DHCP 67) and are
# forwarded out; a dev server on the host stays closed to VMs unless opened by
# hand (ufw allow in on virbr0 to any port 3000)
run ufw allow in on virbr0 to any port 53 proto tcp comment 'libvirt guests -> host DNS'
run ufw allow in on virbr0 to any port 53 proto udp comment 'libvirt guests -> host DNS'
run ufw allow in on virbr0 to any port 67 proto udp comment 'libvirt guests -> host DHCP'
run ufw route allow in on virbr0 comment 'libvirt NAT'
run ufw route allow out on virbr0 comment 'libvirt NAT'
# tailscale0: nothing opened (as in the NixOS and Fedora configs). Tailscale SSH,
# Taildrop and `tailscale serve` live inside tailscaled and need no rule; open a
# service to the tailnet per port: ufw allow in on tailscale0 to any port 3000
run ufw logging low
run ufw --force enable
ok "deny incoming, allow outgoing; VMs reach host DNS/DHCP only; nothing open on tailscale0; enabled at boot"

section "Virtualization and containers"
if [[ ",$GROUPS_WANTED," == *,virt,* ]]; then
    for g in libvirt kvm wireshark; do
        getent group "$g" >/dev/null && ! id -nG "$TARGET_USER" | grep -w "$g" >/dev/null && { run usermod -aG "$g" "$TARGET_USER"; ok "$TARGET_USER added to $g"; }
    done
    if [ "$DRY" -eq 0 ]; then
        if virsh -c qemu:///system net-info default >/dev/null 2>&1; then
            virsh -c qemu:///system net-autostart default >/dev/null 2>&1 || true
            if virsh -c qemu:///system net-info default | grep 'Active:.*yes' >/dev/null \
               || virsh -c qemu:///system net-start default >/dev/null 2>&1; then
                ok "libvirt default NAT network active + autostart"
            else
                warn "libvirt default network did not start: virsh -c qemu:///system net-start default"
            fi
        else
            warn "libvirt default network not found (is libvirt-daemon-system installed?)"
        fi
    fi
    # silence podman-docker's "Emulate Docker CLI using podman" banner
    run touch /etc/containers/nodocker
    ok "podman: rootless, docker CLI shim"
fi
if [[ ",$GROUPS_WANTED," == *,docker,* ]]; then
    getent group docker >/dev/null && ! id -nG "$TARGET_USER" | grep -w docker >/dev/null && { run usermod -aG docker "$TARGET_USER"; warn "$TARGET_USER added to docker (root-equivalent)"; }
    # published ports stay on localhost unless asked for explicitly: Docker's own
    # nftables rules are evaluated before ufw's and would expose them otherwise
    if deploy system/docker-daemon.json /etc/docker/daemon.json; then
        unit_exists docker.service && run systemctl restart docker
    fi
    ok "docker: daemon.json (ports bind to 127.0.0.1 by default, live-restore)"
fi
# a removed podman-docker leaves /etc/profile.d/podman-docker.sh pointing
# DOCKER_HOST at Podman; purge it by name (its only conffiles are the two
# profile.d hooks, so this is not the blanket rc purge avoided above)
if installed docker.io && dpkg-query -W -f='${Status}' podman-docker 2>/dev/null | grep 'config-files' >/dev/null; then
    run dpkg --purge podman-docker
    ok "podman-docker leftovers purged (its profile.d hook sent docker to Podman); log out and in"
fi
if command -v flatpak >/dev/null; then
    run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
        && ok "Flathub remote" || warn "Flathub remote not added (offline?)"
fi

section "Storage (TRIM through LUKS)"
# Ubuntu's LVM-on-LUKS layout ships crypttab without `discard`, so the weekly
# fstrim never reaches the SSD (lsblk -D shows 0B on the crypt device). TRIM
# reveals which blocks of the encrypted volume are free; the installer's own
# default layouts accept that trade for SSD life and performance.
# only the entries that lack it, so a LUKS device added later gets it too
if grep -E '^[^#].*\bluks\b' /etc/crypttab 2>/dev/null | grep -vE '\bdiscard\b' | grep . >/dev/null; then
    run sed -i -E '/^[^#]/ { /\bdiscard\b/! s/^(([^[:space:]]+[[:space:]]+){3}[^[:space:]]*)\bluks\b/\1luks,discard/ }' /etc/crypttab
    run update-initramfs -u >/dev/null 2>&1 || warn "update-initramfs failed; run it by hand"
    reboot_needed=1
    ok "/etc/crypttab: discard added (active after reboot, then fstrim.timer works)"
else
    ok "discards pass through LUKS already (or no LUKS)"
fi

section "Windows disk"
# The disk that carries the BitLocker volume is hidden from udisks: no entry in
# Files or Disks, no auto-mount, no unlock prompt (root can still mount it by
# hand). Matched by GPT UUID, which every partition inherits, so nvme0/nvme1
# renumbering between boots does not matter. Ubuntu already hides the EFI and
# recovery partitions by type; this covers the whole disk.
windisk=$(lsblk -rno PKNAME,FSTYPE 2>/dev/null | awk '$2 == "BitLocker" {print $1; exit}')
if [ -n "$windisk" ]; then
    ptuuid=$(lsblk -dno PTUUID "/dev/$windisk")
    tmp=$(mktemp)
    printf '# ubuntu_setup: hide the Windows (BitLocker) disk from udisks/Files/Disks\nSUBSYSTEM=="block", ENV{ID_PART_TABLE_UUID}=="%s", ENV{UDISKS_IGNORE}="1"\n' "$ptuuid" > "$tmp"
    if deploy "$tmp" /etc/udev/rules.d/99-hide-windows-disk.rules; then
        run udevadm control --reload-rules
        run udevadm trigger --subsystem-match=block --action=change
    fi
    rm -f "$tmp"
    ok "/dev/$windisk (GPT $ptuuid) hidden from Files and Disks"
    # dual boot with that Windows
    # 1. RTC in local time, as Windows expects. No --adjust-system-clock: the RTC
    #    is written from the NTP-synced system clock, the flag would do the
    #    reverse. timedatectl's warning is expected (an hour off for one boot
    #    around a DST change).
    if [ "$(timedatectl show -p LocalRTC --value 2>/dev/null)" != yes ]; then
        if run timedatectl set-local-rtc 1 2>/dev/null; then ok "RTC kept in local time (timedatectl set-local-rtc 1)"; else warn "timedatectl set-local-rtc 1 failed"; fi
    fi
    # 2. No Windows entry in GRUB: Windows boots from the firmware menu (F12);
    #    chainloading it from GRUB changes the measured boot path and BitLocker
    #    asks for the recovery key
    if deploy system/99-no-os-prober.cfg /etc/default/grub.d/99-no-os-prober.cfg; then
        run update-grub >/dev/null 2>&1 || warn "update-grub failed; run it by hand"
    fi
    # 3. UEFI boot order stays as set in the firmware (Windows first here): the
    #    grub-install that every GRUB/shim upgrade runs would otherwise move
    #    "ubuntu" back to the top of BootOrder
    if ! debconf-show grub-efi-amd64 2>/dev/null | grep -F 'grub2/update_nvram: false' >/dev/null; then
        debconf_set "grub-efi-amd64 grub2/update_nvram boolean false"
        ok "grub-efi-amd64: update_nvram=false (GRUB upgrades leave the UEFI boot order alone)"
    fi
else
    info "no BitLocker volume on this machine; nothing to hide"
fi

section "Locale and terminal"
# Norwegian formats (dates, paper, units) with an English UI: GNOME reads the
# region from gsettings (apply-gnome.sh); the locale must exist first
if ! locale -a 2>/dev/null | grep -i '^nb_NO.utf8$' >/dev/null; then
    run locale-gen nb_NO.UTF-8 >/dev/null && ok "nb_NO.UTF-8 generated" || warn "locale-gen nb_NO.UTF-8 failed"
fi
if [ -x /usr/bin/kitty ] && update-alternatives --query x-terminal-emulator 2>/dev/null | grep '^Value: /usr/bin/kitty' >/dev/null; then
    :
elif [ -x /usr/bin/kitty ]; then
    if run update-alternatives --set x-terminal-emulator /usr/bin/kitty >/dev/null 2>&1; then ok "x-terminal-emulator -> kitty"; else warn "kitty is not registered as an x-terminal-emulator alternative"; fi
fi

section "Snap app permissions (prompting)"
# Ubuntu's Security Center: snaps ask before reading home / removable media
state=$(snap get system experimental.apparmor-prompting 2>/dev/null || echo unset)
if [ "$state" = true ]; then
    ok "AppArmor prompting already on"
elif run snap set system experimental.apparmor-prompting=true 2>/dev/null; then
    ok "AppArmor prompting enabled (log out and in once)"
else
    warn "snapd refused experimental.apparmor-prompting on this system; enable it in Security Center"
fi

section "Done"
ok "System half applied for $TARGET_USER."
if [ "${reboot_needed:-0}" -eq 1 ]; then
    warn "Reboot needed: kernel parameters / module policy take effect on the next boot."
fi
info "Groups (libvirt, kvm, wireshark) apply after logging out and in."
info "Next: bash scripts/apply-user.sh  (as $TARGET_USER, no sudo)"
