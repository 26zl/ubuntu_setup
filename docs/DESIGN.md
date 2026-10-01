# Design notes

Why each part of the setup is the way it is. The README says what the scripts
do; this file keeps the reasoning, the trade-offs and the sources.

Sibling repos, same conventions: [nixos-config](https://github.com/26zl/nixos-config)
(ThinkPad T14, the hardening values come from there),
[fedora-44-kde-setup](https://github.com/26zl/fedora-44-kde-setup),
[nvim](https://github.com/26zl/nvim), [vscode_config](https://github.com/26zl/vscode_config).

## Baseline snapshot (Timeshift)

`apply-system.sh` installs Timeshift first and takes an rsync snapshot of `/`
(home excluded) on the root volume before anything else changes, then schedules
daily ×3 and weekly ×2. Restore from the Timeshift GUI or a live USB.

```bash
sudo timeshift --list
sudo timeshift --create --comments "before X"
```

## Third-party repositories

VS Code, Mullvad, Tailscale and Chrome come from their vendors' apt repos as
deb822 `.sources` files with `Signed-By` keyrings. Three keys are downloaded
once and pinned by SHA-256 in `apply-system.sh`, cross-checked against the
vendors' published fingerprints (Microsoft `BC52…29CF`, Mullvad `A119…8DDF`,
Tailscale `2596…5868`). Google's key file rotates subkeys, so it is verified by
its primary fingerprint (`EB4C…4796`) instead, and the repo file is only written
when no Chrome repo exists yet (the package manages its own afterwards).
Mullvad's `stable` suite is release-independent (there is no `resolute` suite);
Tailscale has one.

## Packages

`packages/apt.txt` is grouped; every name is checked against apt before the
single install call, so a renamed package fails loudly instead of aborting the
run halfway.

| Group | What |
| --- | --- |
| `base` | fish, starship, kitty, fastfetch, Neovim 0.11, fzf, ripgrep, fd, bat, eza, zoxide, delta, lazygit, tealdeer, direnv, btop, jq/yq, diagnostics (lm-sensors, smartmontools, nvme-cli, powertop, iperf3, dnsutils, mtr), bubblewrap + socat, timeshift |
| `desktop` | KeePassXC, Flatpak, Google Chrome (own repo), gnome-sushi (Space preview in Files), Intel VA-API (non-free driver) + OpenCL when an Intel GPU is present |
| `dev` | build-essential, cmake, Python 3.14 dev + pipx, sqlite3/psql/redis clients, httpie, mkcert, shellcheck, shfmt, VS Code, Go 1.26, rustup, OpenJDK 21 |
| `virt` | QEMU/KVM, libvirt, virt-manager, OVMF, swtpm (Windows 11 guests), virtiofsd, Podman + compose + docker shim, buildah, skopeo |
| `security` | nmap, tcpdump, Wireshark, ffuf, gobuster, sqlmap, nikto, hydra, john, hashcat, binwalk, exiftool, hexyl, yara, lynis, debsums, ClamAV, apparmor-utils, age, wireguard-tools |
| `vpn` | Mullvad VPN, Tailscale |
| `media` | VLC, GIMP, OBS Studio (apt reuses the Qt/GTK libraries already installed; the Flathub builds would add three runtimes, ~2 GB) |
| `tools` | general quick tools: ffmpeg, ImageMagick, pandoc, poppler-utils, qrencode + zbar, moreutils, pv, parallel, entr, fdupes, trash-cli, sshfs, cifs-utils, testdisk, speedtest-cli, testssl.sh, magic-wormhole, hyperfine, tokei |
| `docker` | opt-in (`--groups all`): docker.io + compose v2 — a root daemon and a root-equivalent group. `system/docker-daemon.json` binds published ports to 127.0.0.1 by default because Docker's own firewall rules are evaluated before ufw's; ask for `0.0.0.0:80:80` explicitly to expose a port. On this laptop it is installed. |

Homebrew (`packages/brew.txt`) adds only what apt lacks or ships too old: gh
2.101 (apt has 2.46), mise, yazi, sops, atuin (apt has 18.8), carapace. Flatpak
(`packages/flatpak.txt`) carries the sandboxed desktop apps, installed per user
without root: Discord.

## Debloat

| Removed / disabled | Why |
| --- | --- |
| `kdump-tools` (purged) | reserved 1 GB of RAM for a crash kernel; `crashkernel=` leaves the command line |
| `whoopsie` (purged), apport (`enabled=0`) | crash uploads to Canonical; apport has a long local-privesc history |
| `cloud-init` (purged) | already disabled by `/etc/cloud/cloud-init.disabled`; only added boot units |
| `avahi-daemon` | no mDNS announcements of the hostname on untrusted networks; add printers by address |
| `cups-browsed` | auto-created print queues from the network; the CVE-2024-47176 family |
| `ModemManager` | no WWAN in this model |
| `wsdd` (purged) | spawned by gvfs for "Windows Network"; multicasts WS-Discovery probes on every interface, VPN and bridges included. SMB shares by address keep working |
| `motd-news.timer`, Pro `apt_news` | daily fetch of motd.ubuntu.com with release, kernel, CPU and uptime in the User-Agent; the apt hook pulled the same feed on every apt run |
| snap-store search provider (GNOME) | sent every overview search term to the Snap Store |
| web-search provider (GNOME) | a Google row (Canonical affiliate tag) on every overview search |

Kept on purpose: Ubuntu Pro (free personal: ESM + Livepatch), `unattended-upgrades`
(security only), `power-profiles-daemon` (TLP would conflict; `thermald` stays
installed but exits on DYTC ThinkPads, see "Laptop and power"), GNOME Boxes snap,
Chrome (telemetry off by policy).

## sysctl hardening (`system/99-hardening.conf`)

The desktop-safe subset from `nixos-config/hardening.nix`, tuned to not break
libvirt, Podman, Mullvad or dev tooling. Ubuntu 26.04 already ships several of
these; they are repeated so the file is the complete policy.

| Key | Value | Purpose |
| --- | --- | --- |
| `kernel.kptr_restrict` | 2 | hide kernel pointers even from root (set 1 for perf/bpftrace) |
| `kernel.sysrq` | 4 | magic SysRq: keyboard-control functions only |
| `kernel.kexec_load_disabled` | 1 | no runtime kernel replacement (Secure Boot bypass) |
| `kernel.unprivileged_bpf_disabled` | 1 | one-way until reboot (Ubuntu's 2 lets root re-enable) |
| `net.core.bpf_jit_harden` | 2 | JIT spraying protection |
| `kernel.oops_limit` | 100 | panic instead of letting an exploit retry forever |
| `vm.mmap_rnd_bits` | 32 | maximum mmap ASLR entropy |
| `kernel.yama.ptrace_scope` | 1 | parent-child only; gdb/strace via sudo |
| `fs.suid_dumpable` | 0 | no setuid core dumps |
| `dev.tty.ldisc_autoload` | 0 | no autoloaded TTY line disciplines |
| `fs.protected_{symlinks,hardlinks,fifos,regular}` | 1/1/2/2 | world-writable dir races |
| `net.ipv4.tcp_syncookies`, `tcp_rfc1337` | 1 | SYN flood, TIME-WAIT assassination |
| `net.ipv4.conf.*.rp_filter` | 2 | loose: strict breaks Mullvad's policy routing and container return traffic |
| `*.accept_redirects`, `*.secure_redirects`, `*.send_redirects`, `*.accept_source_route` | 0 | never legitimate on a workstation |
| `net.ipv4.conf.*.log_martians` | 1 | log impossible source addresses |
| `net.ipv6.conf.*.use_tempaddr` | 2 | IPv6 privacy addresses |

`system/99-disable-modules.conf` blocks `dccp sctp rds tipc firewire-core
firewire-ohci` with `install … /bin/false` (a blacklist only stops autoload).

## Kernel parameters (`system/99-hardening.cfg`)

`slab_nomerge init_on_alloc=1 page_alloc.shuffle=1 vsyscall=none` — appended to
`GRUB_CMDLINE_LINUX_DEFAULT` through `/etc/default/grub.d/`, applied by
`update-grub`, live after a reboot. Same set as the NixOS ThinkPad. Ubuntu's
kernel already builds with `init_on_alloc` on; it is spelled out so the command
line documents itself. `crashkernel=` disappears with `kdump-tools`.

## DNS and network privacy

`system/resolved-hardening.conf`: no forced global resolver (`DNS=`/`Domains=~.`
would leak past the VPN and bypass the home network's own resolver), Quad9 as
`FallbackDNS` only, `DNSOverTLS=opportunistic`, `DNSSEC=allow-downgrade`, LLMNR
and mDNS resolution off (Responder-class LAN spoofing). Mullvad manages DNS while
the tunnel is up.

`system/nm-privacy.conf`: random MAC while scanning, a stable per-network MAC
when connected (same address every time on one SSID, so static DHCP leases keep
working; a different one on every other network), no hostname in DHCP requests
(a random MAC is pointless if the hostname still identifies the device), IPv6
privacy extensions. Takes effect when Wi-Fi reconnects; the home router will see
a new MAC once.

## Firewall (ufw)

Deny incoming, allow outgoing, deny routed, logging low, enabled at boot. The
only inbound exception is `virbr0`, and only for what libvirt guests need from
the host: DNS (53 tcp/udp) and DHCP (67 udp) to the host's dnsmasq. Forwarding
in and out of `virbr0` is allowed so the NAT works (without the `route allow`
rules VMs have no network). A dev server on the host is not reachable from a
VM unless opened by hand (`sudo ufw allow in on virbr0 to any port 3000`).
`tailscale0` gets no rule: Tailscale SSH, Taildrop and `tailscale serve` are
handled inside tailscaled and need none, and neither the NixOS nor the Fedora
config trusts that interface. Open a service to the tailnet per port
(`sudo ufw allow in on tailscale0 to any port 3000`). Re-runs delete the broad
`allow in on virbr0` / `tailscale0` rules that earlier versions of the script
added. Nothing else listens: no sshd, and the WS-Discovery responder (`wsdd`)
that gvfs started on UDP 3702 is purged.

## Telemetry, crash reporting, browsers

Ubuntu's own opt-outs are verified rather than assumed: `ubuntu-insights`
consent files off, GNOME "Send error reports" off, location services off,
`motd-news` and Pro's `apt_news` off (`system/motd-news`,
`pro config set apt_news=false`); `esm-cache.service` stays, Pro needs it.
Firefox (snap) reads `/etc/firefox/policies/policies.json`: telemetry, Studies,
Pocket and sponsored content off, strict tracking protection. Chrome gets the
managed-policy equivalent (metrics, URL-keyed data collection, background mode
off) — Chrome shows "managed by your organization" for any policy, that is
expected.

## Locale and the Windows disk

English UI, Norwegian formats: `nb_NO.UTF-8` is generated and GNOME's region
(`org.gnome.system.locale region`) set to it, so dates, paper size and units are
Norwegian while `LANG` stays `en_US.UTF-8`. Keyboard layout stays `no`.

**Windows disk** — `apply-system.sh` generates
`/etc/udev/rules.d/99-hide-windows-disk.rules`: every partition of the disk
that carries the BitLocker volume gets `UDISKS_IGNORE=1`, matched by the GPT
UUID (stable across nvme0/nvme1 renumbering). Files and Disks no longer list
it, nothing auto-mounts and no unlock prompt appears; root can still mount it
by hand. The dock shows no drive icons either (`show-mounts false`).

**Dual boot** — three more steps run only when that BitLocker volume is found.
The hardware clock is kept in local time (`timedatectl set-local-rtc 1`):
Windows reads the RTC as local time and its own time sync at boot is
unreliable, so Ubuntu is the side that gives in — the same choice as
`time.hardwareClockInLocalTime` in the NixOS config, while the Fedora desktop
takes the other route (registry key `RealTimeIsUniversal`, which has to survive
every Windows reinstall). The switch is made without `--adjust-system-clock`:
the system clock is NTP-synced and correct, so the RTC is rewritten from it;
the flag would do the opposite and set the system clock wrong by the UTC offset
until NTP catches up. Ubuntu warns that a local-time RTC is "not fully
supported": around a DST change one boot can be an hour off until NTP corrects
it. `system/99-no-os-prober.cfg` drops the Windows entry from GRUB: Windows is
booted from the firmware menu (F12), never chainloaded, because chainloading
changes the measured boot path and BitLocker asks for the recovery key. And
`grub2/update_nvram` is set to `false` in debconf, so the `grub-install` that
every GRUB or shim upgrade runs no longer moves "ubuntu" to the top of the UEFI
boot order (Windows stays first, as set in the firmware). Decline `UEFI dbx`
updates in fwupd for the same PCR 7 reason; Windows Update applies them and
suspends BitLocker itself.

## Laptop and power

Battery and plugged-in use are both covered by what Ubuntu ships, verified
rather than replaced:

- **power-profiles-daemon 0.30** stays on `balanced` and is battery-aware
  (`powerprofilesctl query-battery-aware`): the Intel p-state energy
  preference is `balance_performance` on the charger and `balance_power` on
  battery, and the ThinkPad platform profile (DYTC) follows the same profile.
  Pick `performance` from the top bar for sustained builds on the charger;
  GNOME drops to `power-saver` on its own below 20 % battery.
- **thermald exits on purpose** on ThinkPads with DYTC ("Thermald can't run on
  this platform"): the firmware manages thermals through the platform profile.
  TLP is not installed, it would fight power-profiles-daemon.
- **intel-lpmd** was evaluated and left out: its CPU table (v0.1.0) covers
  Arrow Lake-U (model 0xb5) only; this is Arrow Lake-H (0xc5) and the daemon
  refuses to start without `--ignore-platform-check`.
- **Battery charge limit 75–80 %** (Settings → Power → Battery charge limit,
  or `busctl call org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_BAT0 org.freedesktop.UPower.Device EnableChargeThreshold b true`).
  UPower stores the choice in `/var/lib/upower/charging-threshold-status` and
  re-applies it at boot. Turn it off before a long day away from the charger.
  The threshold lives in the embedded controller, so it applies to Windows too.
- **Caffeine** (GNOME extension, GPL-2.0) keeps the machine awake from Quick
  Settings, indefinitely or on a timer, the PowerToys Awake of GNOME. Pinned
  extensions.gnome.org build of v60 with a SHA-256 check, installed per user by
  `apply-user.sh` and added to `enabled-extensions` by `apply-gnome.sh`; it
  loads at the next login. Closing the lid still suspends; for that,
  `systemd-inhibit --what=handle-lid-switch:idle:sleep <command>`.
- Wi-Fi power saving (NetworkManager default), HDA codec power save and USB
  autosuspend are on by default; PCIe ASPM stays at the firmware default.
  `sudo powertop` measures, but `--auto-tune` is deliberately not applied:
  forcing runtime PM on every device is what breaks USB dongles and audio.
- GNOME: dim and blank after 5 min, suspend after 15 min on battery, never on
  the charger; `verify-setup` has a Power section for all of this.
- Fingerprint: the ELAN reader is supported by libfprint (`fprintd-list $USER`
  shows the device). Enrol in Settings → System → Users → Fingerprint Login;
  Ubuntu enables `pam_fprintd` for login, sudo and the lock screen at the first
  enrolment. Nothing can be scripted here, the finger has to be present.
- Firmware: `fwupdmgr refresh && fwupdmgr get-updates` (`update.sh` checks). The
  R30 BIOS for the 21SX is not on LVFS ([fwupd/firmware-lenovo#603](https://github.com/fwupd/firmware-lenovo/issues/603),
  open), so BIOS updates come from Windows. Decline `UEFI dbx` updates offered
  in Ubuntu: they change PCR 7 and BitLocker on the Windows disk asks for its
  recovery key; Windows Update applies `dbx` with BitLocker suspended.
- Suspend is s2idle only; hibernation is not configured (8 GB swap file, 64 GB RAM).

## SSD: TRIM through LUKS

Ubuntu's LVM-on-LUKS layout writes `/etc/crypttab` without the `discard`
option, so `fstrim.timer` runs weekly but never reaches the SSD: `lsblk -D`
shows `0B` on the crypt device and the logical volume. `apply-system.sh` adds
`luks,discard`, rebuilds the initramfs, and the next boot passes discards
through. Trade-off: TRIM reveals which blocks of the encrypted volume are
unused (cryptsetup FAQ 5.19); the installer's own default LUKS layouts accept
that for SSD longevity. To enable it immediately instead of after a reboot:
`sudo cryptsetup --allow-discards --persistent refresh dm_crypt-0` (asks for
the passphrase).

## Security tooling

### Auditing

```bash
sudo lynis audit system        # hardening index 64 on this laptop, no warnings
sudo debsums -s                # package files that differ from dpkg's checksums
```

Lynis suggestions that must not be applied here: `rp_filter=1` (breaks Mullvad
and container return traffic), `kernel.modules_disabled=1` (blocks USB and
libvirt modules), `net.ipv4.conf.all.forwarding=0` (libvirt's NAT needs it),
`kernel.sysrq=0` (4 keeps the keyboard-control keys), disabling USB storage, a
GRUB password (Ubuntu's `10_linux` generates no `--unrestricted` entries, so the
password would be asked at every boot; LUKS already protects the data), auditd
and process accounting (a daemon nobody reads is not a control), `hidepid` on
/proc (breaks GNOME's process views), password ageing, login banners and umask
027 (server controls). `sysctl` keys ufw overrides at start (`log_martians`)
are corrected in `/etc/ufw/sysctl.conf` by `apply-system.sh`.

Lynis' "purge old/removed packages" is reported by `apply-system.sh` but never
done automatically: purging `grub-pc`'s leftover deletes `/etc/default/grub`,
which `grub-efi-amd64` owns (restore with
`sudo cp /usr/share/grub/default/grub /etc/default/grub && sudo update-grub`).

**Ubuntu Pro's USG and FIPS toggles stay off**: USG applies CIS/DISA-STIG
server profiles that remove or break desktop components, and FIPS 140-2 pins a
certified but older crypto stack and kernel. Neither is meant for a laptop.

### Malware scanning

`clamav` + `clamav-freshclam`, with `clamav-freshclam-once.timer` enabled by
`apply-system.sh`: the package enables neither the daemon nor the timer, so the
signatures shipped at install time would silently go stale (the timer runs
daily with `Persistent=true`, a missed run is caught up at the next boot). No
`clamd`: on-access scanning costs throughput on every file read. Scan on demand:

```bash
clamscan -r --infected ~/Downloads
```

### Sandboxing and mandatory access control

AppArmor is enforcing with Ubuntu's user-namespace restriction on; `bubblewrap`
works through Ubuntu's `bwrap-userns-restrict` profile, which is what Flatpak
and the Claude Code sandbox need. Snap app permissions prompting (Ubuntu's
Security Center) is enabled: snaps ask before reading home or removable media.
Firejail is deliberately not used: SUID, its own privilege-escalation CVEs, and
Flatpak/snap already cover the GUI applications.

### Claude Code sandbox

`bubblewrap` and `socat` are installed and `bwrap` already works under Ubuntu's
AppArmor profile. Enable per session with `/sandbox`, or merge the `sandbox`
block from `configs/claude/settings.sandbox.json` into `~/.claude/settings.json`:
writes limited to the project, network through an allow-listed proxy; `podman`,
`docker`, `virsh` and `kali` are excluded and go through the normal permission
prompt, as does anything else that has to run outside the sandbox
(`allowUnsandboxedCommands: true`, `autoAllowBashIfSandboxed: false` — nothing
is auto-approved). `~/.ssh`, `~/.gnupg`, the gh config and the keyring are
unreadable inside it.

### Kali in a container

The host keeps a small classic toolkit (nmap, tcpdump, Wireshark, ffuf, gobuster,
sqlmap, nikto, hydra, john, hashcat, binwalk, exiftool, yara). Everything heavier
runs in Kali under rootless Podman (`kali`, `kali persist`, `kali rm`; `~/pentest`
mounted at `/work`). `NET_RAW` is granted so nmap and tcpdump work inside;
rootless networking still applies, so raw SYN scans of the LAN are best run from
the host. For the full 670-tool set with an authorization-gated MCP server, use
[cybersec-toolkit](https://github.com/26zl/cybersec-toolkit) (`--profile
lightweight`); its Kata VM sandbox needs Docker with a Kata runtime and is not
part of this setup. hashcat uses the Arc GPU through `intel-opencl-icd`: `hashcat -I`.

### Disk, crypto, VPN, firmware

LUKS2 + LVM, Secure Boot, TPM 2.0 (present, not used for auto-unlock — a
passphrase at boot is the stronger default on a laptop). `age`, `sops`, GnuPG,
KeePassXC. `mullvad-vpn` (sign in with the account number; kill switch and DNS
are the app's), `tailscale up` for the tailnet, `wireguard-tools` for raw
tunnels. `fwupd` for firmware, `mokutil --sb-state` for Secure Boot.

## Virtualization and containers

- **KVM + libvirt + virt-manager**: the default NAT network is active and
  autostarts; OVMF and swtpm are installed so Windows 11 guests (TPM 2.0 + UEFI)
  work; `virtiofsd` for host folder sharing. User in `libvirt` and `kvm`.
- **Rootless Podman** (`podman`, `podman-compose`): `podman.socket` runs as your
  user and the shell exports `DOCKER_HOST` to it for compose files and
  testcontainers as long as no real Docker daemon is present. With the `docker`
  group installed, `docker` is Docker Engine (root daemon, ports on localhost by
  default) and Podman stays for rootless work and the `kali` helper. The Kali
  base image is pulled during setup so `kali` starts instantly. `docker.io`
  replaces the `podman-docker` shim, but a removed package keeps its conffiles:
  its `/etc/profile.d/podman-docker.sh` kept exporting `DOCKER_HOST=<podman
  socket>` into every login shell and the GNOME session, so `docker` quietly
  talked to Podman (found 2026-09-27: `docker run -p 8080:80` showed up as
  Podman's `rootlessport` on `*:8080`). The package is purged by name, and the
  shell configs drop a stale value when the engine's socket exists.
- **Windows 11 guest**: `scripts/new-windows-vm.sh <Windows.iso>` creates the
  `default` storage pool if missing, uploads the Windows ISO and the virtio
  driver ISO into it, and runs `virt-install` with UEFI + Secure Boot, an
  emulated TPM 2.0 (swtpm), virtio disk and network, q35 and SPICE. Download
  the Windows 11 ISO yourself from https://www.microsoft.com/software-download/windows11
  (the page needs a browser); during setup load the virtio storage driver from
  the second CD (`viostor\w11\amd64`), then install the guest tools from it.
  The virtio-win ISO is pinned to a release directory
  (`archive-virtio/virtio-win-0.1.302-1/`) and its SHA-256, checked before the
  upload and on every re-run; the `stable-virtio/` alias redirects to plain
  http (which `--proto '=https'` refuses) and moves between versions. The
  project publishes MD5 sums for its RPMs only, so the hash was taken from the
  ISO itself on 2026-09-27; a new upstream release means updating the
  `VIRTIO_*` lines in the script.
- **GNOME Boxes** (snap) stays for quick throwaway VMs.
- **Flatpak** with Flathub for sandboxed GUI apps.

## Development

- **Editor**: [26zl/nvim](https://github.com/26zl/nvim) cloned to `~/.config/nvim`
  (plugins synced headless during setup). **VS Code** from Microsoft's repo with
  [26zl/vscode_config](https://github.com/26zl/vscode_config) cloned to
  `~/.local/share/vscode_config`; its `install.sh` symlinks `settings.json` and
  installs the `sysadmin` role, the `core`, `k8s` and `ops` extension groups
  (publisher allow-list, delayed updates, telemetry off);
  `VSCODE_ROLE=cybersec` or `fullstack` picks another role.
- **Runtimes**: Node LTS and `uv` through `mise` (`mise use -g node@22` to pin;
  `corepack enable` for pnpm/yarn); Go 1.26 and OpenJDK 21 from apt; Rust via
  `rustup` (`stable`, minimal profile + rustfmt + clippy); Python 3.14 + `uv`.
- **Git**: identity from the GitHub account with the noreply address
  (`setup-github.sh`), `gh` credential helper, delta pager, `zdiff3`, histogram
  diff, autosetup remote. No commit signing.
- **Local services**: run databases in Podman; clients (`psql`, `redis-cli`,
  `sqlite3`) and `mkcert` (local TLS) are on the host.

## Terminal and desktop

- **kitty** (Nord, `background_opacity 0.95`, `shell fish`, tab bar at the
  top) on `Super+Return` and as `x-terminal-emulator`; stock key bindings
  (`Ctrl+A` is the shell's beginning-of-line, select all in Ptyxis is
  `Ctrl+Shift+A`, kitty has no select-all); **Ptyxis** (Ubuntu's default, `Ctrl+Alt+T`) gets
  the same Nord palette, font and fish.
- **fish** is the interactive shell everywhere; **bash stays the login shell**
  (Ubuntu's `~/.bashrc` is untouched and sources `~/.config/bash/bashrc`, which
  hands interactive sessions such as VS Code and SSH over to fish).
- **Fonts**: JetBrainsMono Nerd Font (terminals, GNOME monospace) and MesloLGLDZ
  Nerd Font (VS Code), nerd-fonts v3.5.1, SHA-256 pinned, installed to
  `~/.local/share/fonts`.
- **Starship** Nord prompt, **fastfetch** Nord config, `eza`/`bat`/`fd`/`fzf`/
  `zoxide`/`delta`/`lazygit`/`yazi` (`ya` cd-on-exit), `direnv`, `mise`, `tldr`.
  **atuin** takes Ctrl+R (history with directory, exit code and duration; the Up
  arrow and its AI key stay off, sync only after `atuin login`), and
  **carapace** completes the commands fish and bash have no completer for.
  Ubuntu names `bat` and `fd` `batcat`/`fdfind`; `apply-user.sh` links the
  upstream names into `~/.local/bin` so the configs and nvim's Telescope work.
- **GNOME 50**: `apply-gnome.sh` validates every key against the installed
  schemas before setting it. Look: dark, `blue` accent (Nord frost — Yaru
  follows the accent), Nerd Font monospace, weekday in the clock, battery
  percentage, week numbers. Privacy: old temp/trash files removed after 30 days,
  no notifications on the lock screen, lock immediately, 5 min idle, location
  off, snap-store search provider off. Region `nb_NO.UTF-8`. Touchpad: tap to
  click, natural scrolling.
- **Dock**: Ubuntu's dash-to-dock as a floating dock at the bottom (no panel
  mode, auto-hide under overlapping windows, hover the bottom edge to show), no
  drive or trash icons, and eight favourites: kitty, Chrome, Files, Discord,
  VS Code, Text Editor, App Center, Settings (an entry is set only when its
  `.desktop` file exists, flatpak exports included). Everything else lives in
  the app grid (Super).
- **Clicking a notification opens its app** through an extension of our own,
  `configs/gnome-shell/notification-focus@26zl.github.com`, linked by
  `apply-user.sh` and enabled by `apply-gnome.sh`. GNOME Shell 50 does not raise
  an app when its notification is clicked. It sends the app an activation
  token and the app has to raise its own window with it. Many apps never do,
  for example libnotify through the notification portal (Flatpak and snap
  apps such as Discord, Firefox and Thunderbird: the Freedesktop 26.08
  runtime's libnotify does not read the portal's `activation-token`),
  terminals and scripts. Those apps stay behind and the cursor spins
  until the token expires after 15 s. The extension gives the app 0.6 s to
  raise itself and otherwise raises the app's most recent window. It also
  grants focus requests from the clicked app for 5 s, which covers apps that
  raise themselves without a valid token. It then completes the unused token,
  which stops the busy cursor: right away for a single-window app, after 2 s
  for a multi-window app, so Chrome can still use the token to pick the right
  window. Apps that are not running are not launched, because the click may
  already be starting them. One fix for every app instead of per-app
  overrides. About 150 lines of our own code, with no third-party extension.
- **Nord icons and cursor**: the same Nordzy set as the NixOS ThinkPad,
  installed per user from pinned releases with SHA-256 checks (Nordzy-icon 1.8.7
  `Nordzy-dark`, Nordzy-cursors v2.4.0) into `~/.local/share/icons`; GDM and the
  lock screen keep Yaru's cursor because they do not read `~/.local`. `btop`
  uses its bundled Nord theme (`configs/btop/btop.conf`, copied because btop
  rewrites its config). New windows open centred (`center-new-windows`).

## Deliberately not done

- **USBGuard / USB lockdown** and **auditd** — same call as the NixOS ThinkPad:
  a USB lockdown that blocks the next keyboard, and a daemon nobody reads, are
  not controls. GNOME's `usb-protection` keys are left at their defaults.
- **TPM auto-unlock of LUKS** — a passphrase at boot is the stronger default on
  a laptop; PCR-bound unlock without a PIN trades it for convenience.
- **Forced global DNS** — see DNS above; it would bypass the VPN and the home
  resolver.
- **zram** — 64 GB of RAM; the 8 GB swap file is enough.
- **Docker Engine** — opt-in only; rootless Podman with the docker shim covers
  the workflows without a root daemon.
- **TLP** — conflicts with power-profiles-daemon, which is right for Arrow Lake.
- **GNOME extensions beyond Ubuntu's** — each is JavaScript inside the shell
  process.
- **Removing GRUB's Windows entry** — one command in the README's dual-boot
  section; the hidden menu already boots Ubuntu directly.
- **Burp Suite, Metasploit and the rest of the heavy pentest set** — they run
  in the Kali container (`kali persist`, then `apt install` inside); the host
  keeps only the small classic toolkit and the general `tools` group.
- **SSH key** — generate one yourself with a passphrase:
  `ssh-keygen -t ed25519 -a 100` then `gh ssh-key add ~/.ssh/id_ed25519.pub`.
- **Dolby speaker tuning** — this model's Conexant SN6140 codec is not in
  [mister2d/thinkpad-linux-audio](https://github.com/mister2d/thinkpad-linux-audio);
  [speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects)
  can build a PipeWire filter-chain (no EasyEffects, `lsp-plugins-lv2` at run
  time) from Lenovo's audio package `r31sj19w` if it carries a
  `DEV_1F87_SUBSYS_17AA5134` tuning: `python3 tools/fetch_driver/get_lenovo_dax_xml.py --dry-run`
  answers that without changing anything. Left as an experiment.

## Reviewed and not copied

The most-starred Ubuntu/GNOME setup repositories were read against this one:
[omakub](https://github.com/omacom/omakub) (8k), [linutil](https://github.com/ChrisTitusTech/linutil)
(5k), [konstruktoid/hardening](https://github.com/konstruktoid/hardening) (1.9k),
[lockdown.sh](https://github.com/dolegi/lockdown.sh),
[franckferman/ubuntu-post-install](https://github.com/franckferman/ubuntu-post-install).
Taken from them: `wsdd` and motd-news removal, TRIM through LUKS, btop's Nord
theme, `center-new-windows`, `gnome-sushi`. Not taken, with the reason: seven
GNOME extensions and Alacritty/LazyVim (omakub); zram, auto-cpufreq and snap
removal (linutil); disabling bluetooth, thunderbolt, usb-storage and the
camera modules, `/tmp` noexec, `hidepid`, `lockdown=confidentiality`, faillock
and the blanket purge of removed packages (konstruktoid, lockdown.sh: server
baselines, the last one deletes `/etc/default/grub` here); USBGuard, firejail,
the `performance` profile with suspend off, masking CUPS (franckferman).

## Sources & credits

| Source | Used for |
| --- | --- |
| [26zl/nixos-config](https://github.com/26zl/nixos-config) `hardening.nix` | sysctl, kernel parameters, module blacklist, MAC privacy, resolved |
| [26zl/fedora-44-kde-setup](https://github.com/26zl/fedora-44-kde-setup) | repo layout, `apply-system.sh` pattern, resolved config, Firefox policies, journald limits |
| [Madaidan's Linux hardening guide](https://madaidans-insecurities.github.io/guides/linux-hardening.html) | the sysctl and boot parameter rationale |
| [Ubuntu snap prompting](https://ubuntu.com/core/docs/apparmor-prompting) / Security Center | snap app permissions |
| [Claude Code sandboxing](https://code.claude.com/docs/en/sandboxing) | `configs/claude/settings.sandbox.json` |
| [nerd-fonts v3.5.1](https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.5.1) | fonts and their SHA-256 |
| [Nordzy-icon 1.8.7](https://github.com/MolassesLover/Nordzy-icon), [Nordzy-cursors v2.4.0](https://github.com/guillaumeboehm/Nordzy-cursors) | icon and cursor theme |
| [Caffeine v60](https://github.com/eonpatapon/gnome-shell-extension-caffeine) ([extensions.gnome.org](https://extensions.gnome.org/extension/517/caffeine/)) | keep-awake toggle and its SHA-256 |
| [omakub](https://github.com/omacom/omakub), [konstruktoid/hardening](https://github.com/konstruktoid/hardening), [linutil](https://github.com/ChrisTitusTech/linutil) | btop theme and GNOME keys; motd-news, wsdd; TRIM |
| [lockdown.sh](https://github.com/dolegi/lockdown.sh), [franckferman/ubuntu-post-install](https://github.com/franckferman/ubuntu-post-install), [webpro/awesome-dotfiles](https://github.com/webpro/awesome-dotfiles) | reviewed, nothing copied (see above) |
| [26zl/nvim](https://github.com/26zl/nvim), [26zl/vscode_config](https://github.com/26zl/vscode_config), [26zl/cybersec-toolkit](https://github.com/26zl/cybersec-toolkit) | editor configs; the opt-in security toolkit |
| Vendor apt repos: [VS Code](https://code.visualstudio.com/docs/setup/linux), [Mullvad](https://mullvad.net/en/download/vpn/linux), [Tailscale](https://tailscale.com/kb/1275/install-ubuntu-2404), [Google Chrome](https://www.google.com/linuxrepositories/) | deb822 sources and the signing keys (fingerprints above) |
| [Flathub](https://flathub.org) (`com.discordapp.Discord`), [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux), [mise](https://mise.jdx.dev), [rustup](https://rustup.rs) | Discord; gh, mise, yazi, sops, atuin, carapace; Node and uv; Rust |
| [Kali Linux image](https://hub.docker.com/r/kalilinux/kali-rolling) | the `kali` helper's base image |
| [virtio-win](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/) (Fedora), [virt-install](https://virt-manager.org) | Windows 11 guest drivers and the VM definition |
| [cryptsetup FAQ 5.19](https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions) | the TRIM-through-LUKS trade-off |
| [power-profiles-daemon](https://gitlab.freedesktop.org/upower/power-profiles-daemon), [UPower](https://upower.freedesktop.org) | battery-aware profiles, charge limit |
| [Ubuntu Pro USG/FIPS](https://ubuntu.com/security/certifications/docs/usg), [Lynis](https://cisofy.com/lynis/), [Timeshift](https://github.com/linuxmint/timeshift) | left off; audit; snapshots |
| [speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects), [thinkpad-linux-audio](https://github.com/mister2d/thinkpad-linux-audio) | the speaker-tuning experiment |
