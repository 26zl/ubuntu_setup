#!/usr/bin/env bash
# Ubuntu 26.04 GNOME. Whole setup in one go: the system half under sudo, then
# the user half. Run as regular user — sudo is called where needed:
#   bash scripts/ubuntu-setup.sh [--groups all] [--dry-run]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ "$EUID" -eq 0 ]; then
    echo "Run as your normal user; the script calls sudo itself." >&2
    exit 1
fi
user_args=()
case " $* " in *" --dry-run "*) user_args=(--dry-run) ;; esac
sudo -v
sudo bash scripts/apply-system.sh "$@"
bash scripts/apply-user.sh "${user_args[@]}"
echo
echo "Log out and in (group membership, snap prompting), then reboot once for the kernel parameters."
echo "Check the result any time with: verify-setup"
