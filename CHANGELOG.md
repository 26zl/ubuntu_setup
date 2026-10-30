# Changelog

Notable changes to this setup, in the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
format. A version is a dated tag (`vYYYY.MM.DD`) marking a state that was
applied to the laptop and verified with `verify-setup`; there are no GitHub
releases, and `main` is what a fresh install runs.

## [Unreleased]

### Added

- `system/99-panic.conf`: hard and soft lockups panic, and the machine reboots
  10 s later with the crash log in EFI pstore; `verify-setup` checks the
  settings, the pstore backend and that no crash report is waiting.
- The libvirt `default` storage pool is created at `/var/lib/libvirt/images`,
  so `verify-setup` passes right after a fresh setup instead of waiting for the
  first virt-manager start.

### Changed

- snapd's experimental AppArmor prompting is turned off until Ubuntu ships a
  kernel without the use-after-free in its notification listener.
- `.gitattributes` keeps every file LF, also in Windows checkouts; the validate
  and secret-scan workflows run on every branch.
- The README says to install Homebrew first and to run `setup-github.sh` at
  the end.

### Fixed

- The daily ClamAV signature update is retried every ten minutes, at most four
  times, when it runs before the network is up; `verify-setup` checks that the
  signatures are less than three days old.
- `apply-system.sh` adds `discard` to every crypttab entry that lacks it,
  `update.sh` keeps going when the vscode_config pull fails, `verify.sh` no
  longer reports "no pending updates" when fwupdmgr is missing, and the fish
  config passes pattern and string to `string match` in the right order.

## [v2026.10.03] - 2026-10-03

Production review: unattended upgrades also run on battery, script fixes
across both halves, CI hardening (timeouts, read-only tokens, https-only key
fetches), and atuin, carapace, Caffeine, raise-on-click for notifications,
eight dock favourites and per-host ssh includes added.

## [v2026.09.27] - 2026-09-27

First tagged state, applied to the ThinkPad E14 Gen 7 and verified: the
system and user halves, `verify-setup`, `sysinfo`, the Kali container, the
hardening files and the Nord dotfiles.

[Unreleased]: https://github.com/26zl/ubuntu_setup/compare/v2026.10.03...HEAD
[v2026.10.03]: https://github.com/26zl/ubuntu_setup/compare/v2026.09.27...v2026.10.03
[v2026.09.27]: https://github.com/26zl/ubuntu_setup/releases/tag/v2026.09.27
