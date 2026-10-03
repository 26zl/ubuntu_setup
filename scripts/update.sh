#!/usr/bin/env bash
# Update everything this setup installed: apt, snap, flatpak, Homebrew, mise
# runtimes, rustup, the nvim and vscode_config repos, firmware metadata.
# Run as your normal user; sudo is called where needed.
set -euo pipefail

TEAL='\033[38;2;136;192;208m'
RESET='\033[0m'
section() { echo -e "\n${TEAL}━━━ $1 ━━━${RESET}"; }
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
export PATH="$HOME/.local/bin:$PATH"

section "apt"
sudo apt-get update -q
sudo apt-get full-upgrade -y -q
sudo apt-get autoremove --purge -y -q

section "snap / flatpak"
sudo snap refresh || echo "  snap refresh incomplete (an app is running?)"
command -v flatpak >/dev/null && flatpak update -y --noninteractive

section "Homebrew"
if command -v brew >/dev/null; then brew update -q && brew upgrade -q && brew cleanup -q; fi

section "Toolchains"
command -v mise >/dev/null && mise upgrade -q
command -v rustup >/dev/null && rustup update

section "Editor configs"
if [ -d ~/.config/nvim/.git ]; then
    git -C ~/.config/nvim pull -q --ff-only && nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || true
fi
# The clone settings.json links to, wherever it lives.
vcdir="$(dirname "$(readlink -f ~/.config/Code/User/settings.json 2>/dev/null || echo /nonexistent/x)")"
if [ -d "$vcdir/.git" ]; then
    git -C "$vcdir" pull -q --autostash --ff-only || echo "  vscode_config not updated (git -C $vcdir status)"
fi

section "Firmware"
fwupdmgr refresh --force >/dev/null 2>&1 || true
fwupdmgr get-updates 2>/dev/null || echo "  no firmware updates"

section "Done"
[ -f /var/run/reboot-required ] && echo "  reboot required" || echo "  no reboot required"
