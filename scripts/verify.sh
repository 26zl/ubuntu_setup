#!/usr/bin/env bash
# Read-only check of the security posture this repo sets up. Changes nothing;
# prints ✓/! per item and exits 1 if anything failed. Installed as `verify-setup`.
set -u

TEAL='\033[38;2;136;192;208m'
RED='\033[38;2;191;97;106m'
RESET='\033[0m'
fail=0
ok()      { echo -e "  ${TEAL}✓${RESET} $1"; }
bad()     { echo -e "  ${RED}!${RESET} $1"; fail=1; }
note()    { echo -e "  ${TEAL}·${RESET} $1"; }
section() { echo -e "\n${TEAL}━━━ $1 ━━━${RESET}"; }
check()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
# shellcheck disable=SC2329  # invoked through the eval strings below
sysctl_is() { [ "$(sysctl -n "$1" 2>/dev/null)" = "$2" ]; }
# shellcheck disable=SC2329
audio_power_save() { # legacy HDA driver: power_save=1; SOF (sof-audio-pci-*): runtime PM on the controller
    local p d; p=$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null)
    [ "$p" = 1 ] && return 0
    for d in /sys/bus/pci/drivers/sof-audio-pci-*/0000:*; do [ "$(cat "$d/power/control" 2>/dev/null)" = auto ] && return 0; done
    return 1
}
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
export PATH="$HOME/.local/bin:$PATH"

section "Boot and disk"
check "Secure Boot enabled"        "mokutil --sb-state | grep -q enabled"
check "root on LUKS2"              "lsblk -o FSTYPE,FSVER | grep -q 'crypto_LUKS *2'"
check "TPM 2.0 present"            "[ -c /dev/tpmrm0 ]"
check "kernel: slab_nomerge (after reboot)"      "grep -qw slab_nomerge /proc/cmdline"
check "kernel: page_alloc.shuffle=1"             "grep -qw page_alloc.shuffle=1 /proc/cmdline"
check "kernel: vsyscall=none"                    "grep -qw vsyscall=none /proc/cmdline"
check "kernel: no crashkernel reservation (after reboot)" "! grep -q 'crashkernel=' /proc/cmdline"
check "GRUB drop-in installed"     "[ -f /etc/default/grub.d/99-hardening.cfg ]"
check "TRIM passes through LUKS (after reboot)" "[ \"\$(lsblk -Dno DISC-GRAN \$(findmnt -no SOURCE /) | head -1 | tr -d ' ')\" != 0B ]"

section "Windows disk"
winpart=$(lsblk -rno NAME,FSTYPE 2>/dev/null | awk '$2 == "BitLocker" {print $1; exit}')
if [ -n "$winpart" ]; then
    check "BitLocker disk hidden from udisks (Files/Disks)" "udevadm info -q property /dev/$winpart | grep -q '^UDISKS_IGNORE=1'"
    check "RTC kept in local time for Windows" "[ \"\$(timedatectl show -p LocalRTC --value)\" = yes ]"
    check "GRUB: os-prober off (Windows boots from the firmware menu)" "grep -qs '^GRUB_DISABLE_OS_PROBER=true' /etc/default/grub.d/99-no-os-prober.cfg"
    check "GRUB upgrades leave the UEFI boot order alone" "debconf-show grub-efi-amd64 2>/dev/null | grep -q 'grub2/update_nvram: false'"
fi

section "sysctl"
for kv in kernel.kptr_restrict=2 kernel.dmesg_restrict=1 kernel.sysrq=4 kernel.kexec_load_disabled=1 \
          kernel.unprivileged_bpf_disabled=1 kernel.yama.ptrace_scope=1 fs.suid_dumpable=0 \
          dev.tty.ldisc_autoload=0 fs.protected_fifos=2 fs.protected_regular=2 net.ipv4.tcp_syncookies=1 \
          net.ipv4.conf.all.accept_redirects=0 net.ipv4.conf.all.send_redirects=0 \
          net.ipv4.conf.all.rp_filter=2 net.ipv6.conf.all.use_tempaddr=2 kernel.oops_limit=100 \
          net.ipv4.conf.all.log_martians=1; do
    check "$kv" "sysctl_is ${kv%=*} ${kv#*=}"
done
check "modules blocked: dccp sctp rds tipc firewire" "grep -q 'install dccp /bin/false' /etc/modprobe.d/99-disable-modules.conf"

section "Network"
check "ufw enabled at boot"        "grep -q '^ENABLED=yes' /etc/ufw/ufw.conf"
check "ufw active"                 "systemctl is-active ufw"
check "ufw default: deny incoming" "grep -q '^DEFAULT_INPUT_POLICY=\"DROP\"' /etc/default/ufw"
check "resolved: DNS-over-TLS opportunistic" "resolvectl status 2>/dev/null | head -3 | grep -q '+DNSOverTLS\|DNSOverTLS=opportunistic' || grep -q '^DNSOverTLS=opportunistic' /etc/systemd/resolved.conf.d/hardening.conf"
check "resolved: LLMNR off"        "resolvectl status | head -3 | grep -q -- '-LLMNR'"
check "resolved: mDNS off"         "resolvectl status | head -3 | grep -q -- '-mDNS'"
check "resolved: Quad9 fallback"   "grep -q 'dns.quad9.net' /etc/systemd/resolved.conf.d/hardening.conf"
check "NM: random MAC while scanning"     "grep -q 'wifi.scan-rand-mac-address=yes' /etc/NetworkManager/conf.d/99-privacy.conf"
check "NM: stable per-network MAC"        "grep -q 'wifi.cloned-mac-address=stable' /etc/NetworkManager/conf.d/99-privacy.conf"
check "NM: no hostname in DHCP"           "grep -q 'ipv4.dhcp-send-hostname=no' /etc/NetworkManager/conf.d/99-privacy.conf"
check "avahi-daemon disabled"      "! systemctl is-enabled avahi-daemon.service 2>/dev/null | grep -q '^enabled'"
check "cups-browsed disabled"      "! systemctl is-enabled cups-browsed.service 2>/dev/null | grep -q '^enabled'"
check "no sshd listening"          "! ss -tlnp | grep -q ':22 '"

section "Telemetry and crash reporting"
check "apport disabled"            "grep -q '^enabled=0' /etc/default/apport"
check "whoopsie not installed"     "! dpkg-query -W -f='\${Status}' whoopsie 2>/dev/null | grep -q 'ok installed'"
check "kdump-tools not installed"  "! dpkg-query -W -f='\${Status}' kdump-tools 2>/dev/null | grep -q 'ok installed'"
check "wsdd (WS-Discovery) not installed" "! dpkg-query -W -f='\${Status}' wsdd 2>/dev/null | grep -q 'ok installed'"
check "motd-news timer disabled"   "! systemctl is-enabled motd-news.timer 2>/dev/null | grep -q '^enabled'"
check "Pro apt news off"           "pro config show apt_news 2>/dev/null | grep -qi false"
check "ubuntu-insights consent off" "! grep -rq 'consent_state = true' \$HOME/.config/ubuntu-insights/ 2>/dev/null"
check "GNOME: report-technical-problems off" "[ \"\$(gsettings get org.gnome.desktop.privacy report-technical-problems)\" = false ]"
check "GNOME: location off"        "[ \"\$(gsettings get org.gnome.system.location enabled)\" = false ]"
check "Firefox policies installed" "[ -f /etc/firefox/policies/policies.json ]"
check "Chrome policies installed"  "[ -f /etc/opt/chrome/policies/managed/privacy.json ]"
check "unattended security upgrades on" "grep -q 'Unattended-Upgrade \"1\"' /etc/apt/apt.conf.d/20auto-upgrades"
check "ClamAV signature timer enabled" "systemctl is-enabled clamav-freshclam-once.timer 2>/dev/null | grep -q '^enabled'"

section "Sandboxing"
check "AppArmor enforcing"         "aa-enabled"
check "unprivileged userns restricted (Ubuntu default)" "sysctl_is kernel.apparmor_restrict_unprivileged_userns 1"
check "bubblewrap works (Claude Code / Flatpak)" "bwrap --ro-bind / / --dev /dev --proc /proc --unshare-all --die-with-parent true"
check "socat installed (Claude Code sandbox proxy)" "command -v socat"
# `snap get system` needs root; snapd's system-info endpoint is readable by any user
check "snap prompting on"          "curl -s --unix-socket /run/snapd.socket http://localhost/v2/system-info | jq -e '.result.features[\"apparmor-prompting\"].enabled == true'"
check "Flathub remote"             "flatpak remotes 2>/dev/null | grep -q flathub"

section "Virtualization and containers"
check "KVM available"              "[ -c /dev/kvm ]"
check "user in libvirt group"      "id -nG | grep -qw libvirt"
check "user in kvm group"          "id -nG | grep -qw kvm"
check "user in wireshark group"    "id -nG | grep -qw wireshark"
# the read-only socket is world-accessible, so this works before the libvirt group applies
check "libvirt default network active" "virsh -c qemu:///system --readonly net-info default 2>/dev/null | grep -q 'Active:.*yes'"
check "libvirt default storage pool" "virsh -c qemu:///system --readonly pool-info default 2>/dev/null | grep -q 'State:.*running'"
check "podman rootless works"      "podman info --format '{{.Host.Security.Rootless}}' | grep -q true"
if sudo -n true 2>/dev/null; then
    check "ufw libvirt rules present"  "sudo -n ufw status | grep -q virbr0"
else
    note "ufw libvirt rules: needs sudo to read (sudo ufw status | grep virbr0)"
fi

section "Power"
check "power profile: balanced (PPD adapts EPP on battery vs AC)" "[ \"\$(powerprofilesctl get)\" = balanced ]"
check "PPD battery-aware on"       "powerprofilesctl query-battery-aware | grep -q True"
if [ -f /sys/class/power_supply/BAT0/charge_control_end_threshold ]; then
    check "battery charge limit on (stop at $(cat /sys/class/power_supply/BAT0/charge_control_end_threshold)%)" "[ \"\$(cat /sys/class/power_supply/BAT0/charge_control_end_threshold)\" -lt 100 ]"
fi
check "Wi-Fi power save on"        "iw dev \$(iw dev | awk '/Interface/{print \$2; exit}') get power_save | grep -q on"
check "audio power save (HDA power_save=1 or SOF runtime PM)" audio_power_save
check "Caffeine enabled"           "gsettings get org.gnome.shell enabled-extensions | grep -q caffeine@patapon.info"
check "notification-focus enabled" "gsettings get org.gnome.shell enabled-extensions | grep -q notification-focus@26zl.github.com"
check "GNOME: suspend on battery after idle" "[ \"\$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout)\" != 0 ]"

section "Snapshots and updates"
check "Timeshift baseline snapshot" "[ -n \"\$(ls -A /timeshift/snapshots 2>/dev/null)\" ]"
if pro status 2>/dev/null | grep -q 'not attached'; then
    note "Ubuntu Pro not attached (optional, free for personal use: esm-apps ships the patched kitty/lazygit/gobuster builds)"
else
    check "Ubuntu Pro: livepatch/esm" "pro status 2>/dev/null | grep -Eq 'livepatch +yes +enabled'"
fi
check "firmware: no pending updates" "! fwupdmgr get-updates 2>/dev/null | grep -q 'Update available'"

section "Dotfiles and tools"
for f in ~/.config/fish/config.fish ~/.config/kitty/kitty.conf ~/.config/starship.toml ~/.config/git/config ~/.ssh/config ~/.config/mise/config.toml; do
    check "$f linked" "[ -L $f ]"
done
check "JetBrainsMono Nerd Font"    "fc-list | grep -q 'JetBrainsMonoNerdFont-Regular'"
check "MesloLGLDZ Nerd Font"       "fc-list | grep -q 'MesloLGLDZNerdFont-Regular'"
for c in fish kitty starship eza bat fd zoxide atuin carapace delta lazygit nvim code mise gh podman virt-manager nmap wireshark kali; do
    check "$c on PATH" "command -v $c"
done
check "nvim config is 26zl/nvim"   "git -C ~/.config/nvim remote get-url origin | grep -q 26zl/nvim"
check "VS Code settings linked"    "[ -L ~/.config/Code/User/settings.json ]"
check "Discord (flatpak, user)"    "flatpak info --user com.discordapp.Discord"
for c in vlc gimp obs ffmpeg magick pandoc pdftotext wormhole testssl hyperfine sushi; do
    check "$c on PATH" "command -v $c"
done
if command -v docker >/dev/null && [ -S /var/run/docker.sock ]; then
    check "docker daemon reachable"  "docker info"
    check "docker ports bind to 127.0.0.1" "grep -q '127.0.0.1' /etc/docker/daemon.json"
    check "docker CLI reaches the engine (no podman-docker profile hook, DOCKER_HOST not Podman)" "[ ! -e /etc/profile.d/podman-docker.sh ] && [[ \${DOCKER_HOST:-} != */podman/podman.sock ]]"
fi
check "kali image present"         "podman image exists docker.io/kalilinux/kali-rolling"
check "dock: bottom, floating"     "[ \"\$(gsettings get org.gnome.shell.extensions.dash-to-dock dock-position)\" = \"'BOTTOM'\" ] && [ \"\$(gsettings get org.gnome.shell.extensions.dash-to-dock extend-height)\" = false ]"
check "Nordzy icons and cursor"    "[ \"\$(gsettings get org.gnome.desktop.interface icon-theme)\" = \"'Nordzy-dark'\" ] && [ \"\$(gsettings get org.gnome.desktop.interface cursor-theme)\" = \"'Nordzy-cursors'\" ]"
check "btop Nord theme"            "grep -q 'color_theme = \"nord\"' ~/.config/btop/btop.conf"
check "git identity set"           "[ -n \"\$(git config --global user.email)\" ]"
check "nb_NO formats"              "[ \"\$(gsettings get org.gnome.system.locale region)\" = \"'nb_NO.UTF-8'\" ]"

echo
[ "$fail" -eq 0 ] && ok "all checks passed" || bad "some checks failed (see above)"
exit "$fail"
