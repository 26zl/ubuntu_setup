# Ubuntu 26.04 GNOME — ThinkPad E14 Gen 7 Setup

[![ShellCheck](https://github.com/26zl/ubuntu_setup/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/26zl/ubuntu_setup/actions/workflows/shellcheck.yml)
[![Secret Scan](https://github.com/26zl/ubuntu_setup/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/26zl/ubuntu_setup/actions/workflows/secret-scan.yml)
[![Validate](https://github.com/26zl/ubuntu_setup/actions/workflows/validate.yml/badge.svg)](https://github.com/26zl/ubuntu_setup/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04%20LTS-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![GNOME](https://img.shields.io/badge/GNOME-50-4A86CF?logo=gnome&logoColor=white)](https://www.gnome.org/)
[![Wayland](https://img.shields.io/badge/Wayland-native-orange?logo=wayland&logoColor=white)](https://wayland.freedesktop.org/)

Post-install setup for Ubuntu 26.04 LTS with GNOME 50 on a Lenovo ThinkPad E14
Gen 7: security and privacy hardening, KVM + rootless Podman with Kali in a
container, a full-stack toolchain and Nord dotfiles. Every script is idempotent
and has `--dry-run`, every download is pinned by SHA-256, and every file lands
at one documented path. The reasoning behind each choice, the trade-offs and
the sources are in [docs/DESIGN.md](docs/DESIGN.md).

## Hardware

- Intel Core Ultra 7 255H (Arrow Lake-H), Intel Arc 140T (VA-API + OpenCL), 64 GB RAM
- 2× NVMe: Ubuntu on LUKS2 + LVM, Windows 11 with BitLocker on the other disk (never touched)
- UEFI, Secure Boot on, TPM 2.0, GRUB · Wi-Fi AX211 · ELAN fingerprint (libfprint) · UVC camera
- Known limit: the headphone jack is silent on this model ([sof#10478](https://github.com/thesofproject/sof/issues/10478)); speakers and microphone work

## Quick start

A fresh Ubuntu 26.04 desktop (LUKS, Secure Boot on), a user in `sudo`, internet.
Optional, used when present: Homebrew on Linux, a `gh auth login` session, Ubuntu Pro.

```bash
sudo apt update && sudo apt full-upgrade -y && sudo reboot

git clone https://github.com/26zl/ubuntu_setup.git ~/ubuntu-setup
cd ~/ubuntu-setup
bash scripts/ubuntu-setup.sh --dry-run    # prints the plan, changes nothing
bash scripts/ubuntu-setup.sh              # asks for sudo once; --groups all adds Docker
```

Log out and in (groups, snap prompting), reboot once (kernel parameters, TRIM),
then run `verify-setup`. After editing anything, re-run the half it belongs to:
`sudo bash scripts/apply-system.sh` or `bash scripts/apply-user.sh`.

## What it does

### System half — `sudo bash scripts/apply-system.sh [--groups a,b|all] [--dry-run] [--no-snapshot]`

| Step | Detail |
| --- | --- |
| Snapshot | Timeshift rsync snapshot of `/` before anything changes; daily ×3, weekly ×2 afterwards |
| Repos | VS Code, Mullvad, Tailscale, Chrome as deb822 `.sources` with `Signed-By` keyrings; keys pinned by SHA-256, Chrome's by fingerprint |
| Packages | `packages/apt.txt`, grouped: `base desktop dev virt security vpn media tools` by default, `docker` opt-in. Every name is checked against apt before one install call |
| Debloat | Purged: kdump-tools, whoopsie, cloud-init, wsdd. Off: apport, avahi, cups-browsed, ModemManager, motd-news, Pro apt news |
| ClamAV | `clamav-freshclam-once.timer` enabled: daily signature updates, scanning on demand |
| Hardening | sysctl (`system/99-hardening.conf`), kernel parameters (`slab_nomerge init_on_alloc=1 page_alloc.shuffle=1 vsyscall=none`), blocked modules (dccp sctp rds tipc firewire), resolved (DNS-over-TLS opportunistic, DNSSEC allow-downgrade, LLMNR and mDNS off, Quad9 fallback), NetworkManager (random MAC while scanning, stable per-network MAC, no DHCP hostname), no core dumps, journal capped at 1G, sudo `use_pty` + 10 min timeout, unattended-upgrades runs on battery too and removes unused dependencies |
| Browsers | Firefox and Chrome policies: telemetry, Studies, Pocket, sponsored content, metrics and background mode off |
| Firewall | ufw: deny incoming, allow outgoing, deny routed; VMs on `virbr0` reach the host's DNS/DHCP only and are NATed out; nothing is opened on `tailscale0` |
| Virtualization | libvirt default network active and autostarting, user in libvirt/kvm/wireshark, rootless Podman with the docker shim, Flathub; with `docker`: Docker Engine with published ports bound to 127.0.0.1, and the `podman-docker` shim's leftover `DOCKER_HOST` hook purged so `docker` really talks to the engine |
| Storage | `discard` added to `/etc/crypttab` so the weekly `fstrim` reaches the SSD through LUKS |
| Windows disk, dual boot | udev rule hides the BitLocker disk from Files and Disks, matched by GPT UUID; RTC kept in local time, Windows dropped from the GRUB menu (`system/99-no-os-prober.cfg`), GRUB upgrades leave the UEFI boot order alone |
| Locale, terminal, snaps | `nb_NO.UTF-8` generated, kitty as `x-terminal-emulator`, snap app-permission prompting on |

### User half — `bash scripts/apply-user.sh [--dry-run]` (never sudo)

Symlinks every `configs/` file (a real file in the way is kept as
`*.bak-<stamp>`), installs Nerd Fonts and the Nordzy icons and cursor from
pinned releases, seeds the btop theme, installs the Homebrew formulae
(`packages/brew.txt`: gh, mise, yazi, sops, atuin, carapace) when brew exists,
mise runtimes (Node LTS, uv), rustup stable, the Podman user socket and the Kali
image, the battery charge limit (75–80 %), Flatpak Discord, the Caffeine and
notification-focus GNOME extensions, the `26zl/nvim` and `26zl/vscode_config`
repos, GNOME settings through `apply-gnome.sh` (dark Nord look, privacy toggles,
`nb_NO` formats, floating dock with eight favourites, kitty on Super+Return) and
the git identity from the gh account (`setup-github.sh`).

## Adapt it to your machine

Detected, not assumed: the Intel VA-API/OpenCL packages only with an Intel GPU,
the Windows-disk rule only when a BitLocker volume exists, the libvirt/kvm/
wireshark groups only when they exist, favourites only for installed apps, the
battery limit only where the hardware has one, Ptyxis' profile id read at run
time. Nothing names a user, hostname or disk.

Opinionated — what to change, and where:

| What | Where |
| --- | --- |
| Editor configs: `26zl/nvim` is cloned to `~/.config/nvim` (an existing config is kept as `.bak-<stamp>`), `26zl/vscode_config` to `~/.local/share/vscode_config` | `scripts/apply-user.sh`, sections "Neovim config" and "VS Code config": point them at your repos or delete them |
| Norwegian formats (`nb_NO.UTF-8`; the keyboard layout is left as installed) | `scripts/apply-system.sh` "Locale and terminal" (`locale-gen`) and `scripts/apply-gnome.sh` "region" |
| The dock favourites (kitty, Chrome, Files, Discord, VS Code, Text Editor, App Center, Settings) | `scripts/apply-gnome.sh`, the `for alts in …` list |
| The Nord look, kitty + fish, Nerd Fonts, Nordzy icons and cursor | `scripts/apply-gnome.sh` "look", `scripts/apply-user.sh` "Nerd Fonts" and "Nordzy", the files in `configs/` |
| Tools: `packages/apt.txt` groups, `packages/brew.txt`, `packages/flatpak.txt` | pick groups at run time (`--groups base,desktop,dev`) instead of editing. The vendor repos are added whatever groups you pick |
| `verify-setup` expects all of the above (the nvim remote, Discord, Nordzy, the btop theme, `nb_NO`) | `scripts/verify.sh`: adjust the checks for what you changed, or they report `!` |
| Hardening values (`system/99-hardening.conf`, `99-hardening.cfg`, `99-disable-modules.conf`) | `kptr_restrict=2` and `unprivileged_bpf_disabled=1` stop `perf` and `bpftrace` for non-root; loosen them if you need those |
| Dual-boot steps (local-time RTC, no os-prober, UEFI boot order untouched) | run only when a BitLocker volume is found: `scripts/apply-system.sh` "Windows disk" |
| Firewall: VMs and the tailnet reach no host service | `sudo ufw allow in on virbr0 to any port 3000` or `... on tailscale0 ...` per service; the rules are in `scripts/apply-system.sh` "Firewall" |

Things that cost a feature on other hardware or networks: ModemManager is
disabled (no WWAN here — keep it if you have mobile broadband: the unit list in
`apply-system.sh` "Debloat"); avahi and cups-browsed are disabled (add printers
by address); `system/nm-privacy.conf` gives Wi-Fi a per-network MAC, so a
network with MAC registration needs the cloned address registered; the shell
configs alias `cat` to `bat` and `ls` to `eza`.

## Daily use

| Command | What |
| --- | --- |
| `verify-setup` | read-only check of everything above; exit 1 on any failure |
| `sysinfo` | temperatures, load, RAM, disk wear, battery, VPN state, failed units; prints no addresses |
| `bash scripts/update.sh` | apt, snap, flatpak, brew, mise, rustup, the editor configs, firmware check |
| `kali` · `kali persist` · `kali rm` | Kali Linux shell in rootless Podman, `~/pentest` mounted at `/work` |
| `bash scripts/new-windows-vm.sh <Win11.iso>` | Windows 11 guest: UEFI + Secure Boot, swtpm TPM 2.0, virtio, q35, SPICE. `--prepare` first, `--dry-run` shows the command |
| `sudo lynis audit system` · `sudo debsums -s` | hardening audit and package integrity |
| `clamscan -r --infected ~/Downloads` | on-demand malware scan |

## Dual boot with Windows

- Boot Windows from the firmware boot menu (F12), never from GRUB: chainloading
  changes the measured boot path and BitLocker asks for the recovery key.
  `apply-system.sh` therefore drops the Windows entry from GRUB
  (`system/99-no-os-prober.cfg`) and sets `grub2/update_nvram=false`, so the
  `grub-install` of every GRUB or shim upgrade leaves the UEFI boot order
  (Windows first) alone.
- Clock: Ubuntu keeps the RTC in local time so Windows never drifts after an
  Ubuntu session (`apply-system.sh` runs `timedatectl set-local-rtc 1` while
  NTP is in sync, so the RTC is rewritten from the correct system clock).
  Ubuntu warns that this mode is not fully supported: around a DST change it
  can be an hour off for one boot until NTP corrects it.
- Firmware: the R30 BIOS for the 21SX is not on LVFS
  ([fwupd/firmware-lenovo#603](https://github.com/fwupd/firmware-lenovo/issues/603)),
  so update the BIOS from Windows. Decline `UEFI dbx` updates in Ubuntu: they
  change PCR 7 and BitLocker asks for its recovery key.
- The battery charge limit lives in the embedded controller and applies to
  Windows too. The Windows disk is hidden from Files and Disks; root can still
  mount it by hand.

## Repository layout

```text
├── configs/     user dotfiles, symlinked by apply-user.sh (fish, kitty, starship, git, ssh, mise, bin/kali, the notification-focus GNOME extension, …)
├── system/      files deployed to /etc by apply-system.sh (sysctl, GRUB, modprobe, resolved, NetworkManager, sudo, journald, browser policies, apt sources)
├── packages/    apt.txt (grouped), brew.txt, flatpak.txt
├── scripts/     ubuntu-setup.sh, apply-system.sh, apply-user.sh, apply-gnome.sh, verify.sh, sysinfo.sh, update.sh, setup-github.sh, new-windows-vm.sh
└── docs/        DESIGN.md — reasoning, trade-offs, sources
```

## License

MIT — see [LICENSE](LICENSE).
