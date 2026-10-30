# Security policy

These scripts harden a laptop and run half of their work as root, so a bug
here can leave a machine less safe than its owner believes. Reports are
welcome; please send anything exploitable privately.

## What to report

- A control that does not do what the README or `docs/DESIGN.md` claims: a
  sysctl, kernel parameter, blocked module, resolved or NetworkManager
  setting, firewall rule, browser policy or sudo setting in `system/` or
  `scripts/apply-system.sh` that is silently ineffective, or that a later
  Ubuntu change undid.
- A download that is not verified as documented: a repository key or release
  asset accepted without its pinned SHA-256 or fingerprint, or a way to make
  the scripts fetch something else.
- `apply-system.sh` or `apply-user.sh` writing outside the documented paths,
  touching the Windows disk, changing the UEFI boot order or the measured boot
  path, or doing in `--dry-run` anything but printing.
- `verify-setup` reporting a tick for a control that is not in place.
- A secret, address or other personal data committed to the repository or
  its history.

Vulnerabilities in Ubuntu packages, the vendor repositories (VS Code,
Mullvad, Tailscale, Chrome), Homebrew formulae or the Kali image belong
upstream; unattended-upgrades and `scripts/update.sh` are how this setup picks
up their fixes.

## How to report

Use GitHub private vulnerability reporting:
[open a draft security advisory](https://github.com/26zl/ubuntu_setup/security/advisories/new).
Do not open a public issue for something exploitable. Ordinary bugs go in a
normal [issue](https://github.com/26zl/ubuntu_setup/issues).

Include the Ubuntu release, the commit you ran, the command and flags, and how
to verify the problem, for example a `sysctl`, `ufw status verbose` or
`resolvectl status` excerpt. Leave hostnames, addresses and account names out;
`sysinfo` prints none, and neither should a report.

## Supported versions

`main` is the supported version. Tags (`vYYYY.MM.DD`) mark states that were
applied to the laptop and verified; they receive no separate fixes. Update a
machine with `git pull` and re-run the half the fix belongs to
(`sudo bash scripts/apply-system.sh` or `bash scripts/apply-user.sh`), then
`verify-setup`.

## What to expect

One person maintains this repository for their own laptop, so there is no
guaranteed response time; reports are read and answered as soon as possible.
A confirmed problem is fixed on `main` with a `verify.sh` check where one is
possible, recorded in `CHANGELOG.md`, and the advisory is published
afterwards, crediting you if you want that.
