# Contributing

This is the setup for one laptop, published so that others can reuse the
parts that fit theirs. Fixes, better hardware detection and corrections to
the documentation are welcome; changes that only suit another machine belong
in your own fork (the README's "Adapt it to your machine" lists where to cut).

## Conventions every change keeps

- Every script is idempotent and has `--dry-run`, which prints the plan and
  changes nothing. `apply-system.sh` runs as root and deploys `system/` files
  through `deploy()`; `apply-user.sh` never uses sudo and symlinks `configs/`
  files, keeping a real file in the way as `*.bak-<stamp>`.
- Every direct download is pinned by SHA-256, repository keys by SHA-256 or
  fingerprint; git clones and the Kali image follow upstream, and the README
  says so.
- Every file lands at one documented path, and nothing names a user, hostname
  or disk. Detection beats assumption: check the hardware, then act.
- A new control gets a check in `scripts/verify.sh`, a row in the README's
  tables and the reasoning in `docs/DESIGN.md`.
- Bash with four-space indentation (`.editorconfig`), ShellCheck clean at
  `--severity=warning` with the repository's `.shellcheckrc`. shfmt is not
  used in CI.

## Checks

CI runs three workflows on every branch and pull request; run the same
locally before opening a pull request:

```bash
shellcheck --severity=warning scripts/*.sh configs/bin/kali configs/bash/bashrc
for f in scripts/*.sh configs/bin/kali; do bash -n "$f"; done
bash scripts/apply-user.sh --dry-run
fish --no-execute configs/fish/config.fish
```

`validate.yml` also checks that no private IP address is hardcoded, that every
TOML and JSON file parses, that every `system/` file is referenced by
`apply-system.sh` and every `configs/` file by `apply-user.sh`, and, in an
`ubuntu:26.04` container, dry-runs the system half with `--groups all` and
resolves every package in `packages/apt.txt` against the vendor repositories;
it runs weekly as well to catch renamed packages. `secret-scan.yml` runs
Gitleaks over the history.

## Testing a real run

`--dry-run` on both halves first. For a real run use a disposable Ubuntu 26.04
install or VM, never a machine you cannot reinstall; `apply-system.sh` takes a
Timeshift snapshot before changing anything unless `--no-snapshot` is given.
Re-run the half you changed, then `verify-setup` must pass. Dual-boot steps
only trigger when a BitLocker volume is present, so test them on such a
machine or leave them out of your claims.

## Commits and pull requests

- Branch from `main`, one topic per pull request.
- Commit subjects are imperative and say what changed; the body explains why,
  including what went wrong on the hardware when that is the reason. There is
  no prefix convention.
- Add a line under `Unreleased` in `CHANGELOG.md`.
- CI must be green. The maintainer reviews and merges.

## Versions

A tag `vYYYY.MM.DD` marks a state that was applied to the laptop and verified
with `verify-setup`. Tags are annotated with a one-line summary and get a
dated section in `CHANGELOG.md`; there are no GitHub releases. Security
problems go through [SECURITY.md](SECURITY.md).
