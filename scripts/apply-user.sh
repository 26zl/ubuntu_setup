#!/usr/bin/env bash
# User half of the setup: dotfile symlinks, Nerd Fonts, Homebrew + mise
# toolchains, user flatpaks, the nvim and vscode_config repos, GNOME settings,
# git identity. Idempotent; a real file in the way is kept as *.bak-<timestamp>.
#
#   bash scripts/apply-user.sh             # as your normal user, never sudo
#   bash scripts/apply-user.sh --dry-run   # print the plan, change nothing
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO="$PWD"

TEAL='\033[38;2;136;192;208m'
RED='\033[38;2;191;97;106m'
RESET='\033[0m'
ok()      { echo -e "  ${TEAL}✓${RESET} $1"; }
info()    { echo -e "  ${TEAL}→${RESET} $1"; }
warn()    { echo -e "  ${RED}!${RESET} $1"; }
section() { echo -e "\n${TEAL}━━━ $1 ━━━${RESET}"; }

DRY=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
run() { if [ "$DRY" -eq 1 ]; then echo "  [dry] $*"; else "$@"; fi; }

if [ "$EUID" -eq 0 ]; then
    echo "ERROR: run without sudo, as your normal user." >&2
    exit 1
fi
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
export PATH="$HOME/.local/bin:$PATH"
STAMP=$(date +%Y%m%d-%H%M%S)

# link SRC DST — symlink into the repo; a real file at DST is kept as DST.bak-<stamp>
link() {
    local src="$REPO/$1" dst=$2
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$src" ]; then return 0; fi
    run mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then run mv "$dst" "$dst.bak-$STAMP"; info "kept $dst as $dst.bak-$STAMP"; fi
    run ln -sfn "$src" "$dst"
    ok "$dst -> $1"
}

# fetch URL SHA256 DEST — pinned download
fetch() {
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$1" -o "$3"
    echo "$2  $3" | sha256sum -c --quiet - || { echo "checksum mismatch: $1" >&2; exit 1; }
}

section "Dotfiles"
link configs/fish/config.fish        "$HOME/.config/fish/config.fish"
link configs/kitty/kitty.conf        "$HOME/.config/kitty/kitty.conf"
link configs/starship/starship.toml  "$HOME/.config/starship.toml"
link configs/fastfetch/config.jsonc  "$HOME/.config/fastfetch/config.jsonc"
link configs/git/config              "$HOME/.config/git/config"
link configs/git/ignore              "$HOME/.config/git/ignore"
link configs/mise/config.toml        "$HOME/.config/mise/config.toml"
link configs/containers/registries.conf "$HOME/.config/containers/registries.conf"
link configs/xdg-terminals.list      "$HOME/.config/xdg-terminals.list"
link configs/bash/bashrc             "$HOME/.config/bash/bashrc"
[ -d "$HOME/.ssh" ] || run mkdir -p "$HOME/.ssh"
[ "$(stat -c %a "$HOME/.ssh" 2>/dev/null)" = 700 ] || run chmod 700 "$HOME/.ssh"
link configs/ssh/config              "$HOME/.ssh/config"
[ "$(stat -c %a "$REPO/configs/ssh/config")" = 600 ] || run chmod 600 "$REPO/configs/ssh/config"
link configs/bin/kali                "$HOME/.local/bin/kali"
link scripts/sysinfo.sh              "$HOME/.local/bin/sysinfo"
link scripts/verify.sh               "$HOME/.local/bin/verify-setup"
# ~/.bashrc keeps Ubuntu's defaults and sources the additions
if ! grep -qF '.config/bash/bashrc' "$HOME/.bashrc" 2>/dev/null; then
    if [ "$DRY" -eq 1 ]; then
        echo "  [dry] append the source line to $HOME/.bashrc"
    else
        printf '\n# ubuntu_setup additions\n[ -f ~/.config/bash/bashrc ] && . ~/.config/bash/bashrc\n' >> "$HOME/.bashrc"
    fi
    ok "$HOME/.bashrc sources ~/.config/bash/bashrc"
fi
# Ubuntu renames two binaries; the configs (and nvim's Telescope) expect the upstream names
[ -x /usr/bin/batcat ] && [ ! -e "$HOME/.local/bin/bat" ] && run ln -s /usr/bin/batcat "$HOME/.local/bin/bat" && ok "$HOME/.local/bin/bat -> batcat"
[ -x /usr/bin/fdfind ] && [ ! -e "$HOME/.local/bin/fd" ]  && run ln -s /usr/bin/fdfind "$HOME/.local/bin/fd"  && ok "$HOME/.local/bin/fd -> fdfind"
# settings.sandbox.json is a reference block, not linked: see docs/DESIGN.md "Claude Code sandbox"

section "Nerd Fonts"
# pinned to nerd-fonts v3.5.1; checksums from the release's SHA-256.txt
fontdir="$HOME/.local/share/fonts"
install_font() { # DIR ARCHIVE SHA256 PATTERN
    if [ "$DRY" -eq 1 ]; then echo "  [dry] download nerd-fonts v3.5.1 $2 -> $fontdir/$1"; return 0; fi
    local dl; dl=$(mktemp -d)
    fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/$2" "$3" "$dl/$2"
    mkdir -p "$fontdir/$1"
    tar -xf "$dl/$2" -C "$fontdir/$1" --wildcards "$4"
    rm -rf "$dl"
}
if [ ! -f "$fontdir/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf" ]; then
    install_font JetBrainsMono JetBrainsMono.tar.xz 04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf 'JetBrainsMonoNerdFont-*.ttf'
    ok "JetBrainsMono Nerd Font (terminal)"
fi
if [ ! -f "$fontdir/Meslo/MesloLGLDZNerdFont-Regular.ttf" ]; then
    install_font Meslo Meslo.tar.xz 6b6624632dc6873dfb7681c3f818e7c01ab601ab707690b6440933bbe57e2b11 'MesloLGLDZNerdFont-*.ttf'
    ok "MesloLGLDZ Nerd Font (VS Code)"
fi
run fc-cache -f && ok "font cache refreshed"

section "Nordzy icons and cursor (Nord)"
# pinned releases; per-user install under ~/.local/share/icons
icondir="$HOME/.local/share/icons"
install_theme() { # NAME URL SHA256
    if [ -f "$icondir/$1/index.theme" ]; then ok "$1 present"; return 0; fi
    if [ "$DRY" -eq 1 ]; then echo "  [dry] download $2 -> $icondir/$1"; return 0; fi
    local dl; dl=$(mktemp -d)
    fetch "$2" "$3" "$dl/theme.tar.gz"
    mkdir -p "$icondir"
    tar -xzf "$dl/theme.tar.gz" -C "$icondir"
    rm -rf "$dl"
    gtk-update-icon-cache -f -q "$icondir/$1" 2>/dev/null || true
    ok "$1 installed"
}
install_theme Nordzy-dark https://github.com/MolassesLover/Nordzy-icon/releases/download/1.8.7/Nordzy-dark.tar.gz \
    ad752b5ce70577408431734fc8004f928a00027a8fce6dd131ae2d0c3dc82069
install_theme Nordzy-cursors https://github.com/guillaumeboehm/Nordzy-cursors/releases/download/v2.4.0/Nordzy-cursors.tar.gz \
    3451c1221d58562a5eb647c45f3f7b5e2bbfe0aacf10d9cbc899bc36e5239e5a

section "btop"
# copied, not linked: btop rewrites its config on exit
if [ -f "$HOME/.config/btop/btop.conf" ]; then
    ok "btop.conf present"
else
    run mkdir -p "$HOME/.config/btop"
    run cp configs/btop/btop.conf "$HOME/.config/btop/btop.conf"
    ok "btop.conf seeded (Nord theme)"
fi

section "Homebrew formulae"
if command -v brew >/dev/null; then
    mapfile -t formulae < <(grep -vE '^\s*(#|$)' packages/brew.txt)
    installed=$(brew list --formula 2>/dev/null)
    todo=()
    for f in "${formulae[@]}"; do grep -qx "$f" <<<"$installed" || todo+=("$f"); done
    if [ "${#todo[@]}" -gt 0 ]; then run env HOMEBREW_NO_AUTO_UPDATE=1 brew install -q "${todo[@]}"; fi
    ok "brew: ${formulae[*]}"
else
    warn "Homebrew not installed; skipping gh/mise/yazi/sops (https://brew.sh — optional; apt's gh 2.46 works too)"
fi

section "Toolchains"
if command -v mise >/dev/null; then
    run mise install -q && ok "mise: $(mise ls --current 2>/dev/null | awk '{print $1"@"$2}' | tr '\n' ' ')"
else
    warn "mise missing; Node/uv not installed (apt nodejs is the fallback)"
fi
if command -v rustup >/dev/null; then
    if ! rustup toolchain list 2>/dev/null | grep '^stable' >/dev/null; then
        run rustup set profile minimal
        run rustup default stable
        run rustup component add rustfmt clippy || true
    fi
    ok "rustup: $(rustup run stable rustc --version 2>/dev/null || echo 'stable (pending)')"
fi
command -v go   >/dev/null && ok "go: $(go version | awk '{print $3}')"
command -v java >/dev/null && ok "java: $(java -version 2>&1 | head -1)"

section "Containers (rootless Podman)"
if command -v podman >/dev/null; then
    run systemctl --user enable --now podman.socket && ok "podman.socket (DOCKER_HOST for compose/testcontainers)"
    if [ "$DRY" -eq 0 ]; then
        if podman info >/dev/null 2>&1; then ok "podman info OK (rootless)"; else warn "podman info failed — log out and in, then re-check"; fi
    fi
    # the Kali base image (~120 MB) so `kali` starts without a first-run download
    if podman image exists docker.io/kalilinux/kali-rolling 2>/dev/null; then
        ok "kali-rolling image present"
    elif run podman pull -q docker.io/kalilinux/kali-rolling; then
        ok "kali-rolling image pulled"
    else
        warn "kali-rolling image not pulled (offline?); kali pulls it on first use"
    fi
fi

section "Laptop"
# battery charge limit (ThinkPad 75-80 %): UPower stores the choice and
# re-applies it at boot; Settings -> Power -> Battery charge limit toggles it
bat=/sys/class/power_supply/BAT0
if [ -f "$bat/charge_control_end_threshold" ]; then
    if [ "$(cat "$bat/charge_control_end_threshold")" -lt 100 ]; then
        ok "battery charge limit on (stops at $(cat "$bat/charge_control_end_threshold") %)"
    elif run busctl call org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_BAT0 \
            org.freedesktop.UPower.Device EnableChargeThreshold b true >/dev/null 2>&1; then
        ok "battery charge limit enabled (stops at $(cat "$bat/charge_control_end_threshold") %)"
    else
        warn "could not enable the battery charge limit; use Settings -> Power"
    fi
else
    info "no battery charge thresholds on this machine"
fi

# Caffeine (GPL-2.0, github.com/eonpatapon/gnome-shell-extension-caffeine) keeps
# the machine awake from Quick Settings, like PowerToys Awake. Pinned
# extensions.gnome.org build of v60 (GNOME 45-50); apply-gnome.sh enables it.
caffeine="$HOME/.local/share/gnome-shell/extensions/caffeine@patapon.info"
if [ -f "$caffeine/metadata.json" ]; then
    ok "Caffeine present"
elif ! command -v gnome-extensions >/dev/null; then
    info "gnome-extensions not found; skipping Caffeine"
elif [ "$DRY" -eq 1 ]; then
    echo "  [dry] install Caffeine v60 from extensions.gnome.org"
else
    dl=$(mktemp -d)
    fetch "https://extensions.gnome.org/download-extension/caffeine@patapon.info.shell-extension.zip?version_tag=69851" \
        dd2b5962ebad4e957390522e5df539764828011032360743e77cc5940ebac955 "$dl/caffeine.zip"
    gnome-extensions install --force "$dl/caffeine.zip" && ok "Caffeine installed (loads at the next login)"
    rm -rf "$dl"
fi

section "Flatpak apps (packages/flatpak.txt)"
if command -v flatpak >/dev/null; then
    # user installs need no root and no polkit prompt; the system remote stays for later
    run flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    mapfile -t apps < <(grep -vE '^\s*(#|$)' packages/flatpak.txt)
    for app in "${apps[@]}"; do
        if flatpak info --user "$app" >/dev/null 2>&1; then
            ok "$app already installed"
        elif run flatpak install --user -y --noninteractive flathub "$app"; then
            ok "$app installed (user)"
        else
            warn "$app did not install (offline?); re-run later"
        fi
    done
else
    warn "flatpak not installed; run apply-system.sh first"
fi

section "Neovim config (github.com/26zl/nvim)"
nvdir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [ -d "$nvdir/.git" ] && git -C "$nvdir" remote get-url origin 2>/dev/null | grep '26zl/nvim' >/dev/null; then
    run git -C "$nvdir" fetch -q origin main && run git -C "$nvdir" merge -q --ff-only FETCH_HEAD && ok "nvim config up to date"
else
    [ -e "$nvdir" ] && { run mv "$nvdir" "$nvdir.bak-$STAMP"; info "kept $nvdir as $nvdir.bak-$STAMP"; }
    run git clone -q https://github.com/26zl/nvim "$nvdir" && ok "cloned to $nvdir"
fi
if command -v nvim >/dev/null; then
    # plugins from lazy-lock.json now instead of on the first interactive start
    if [ "$DRY" -eq 1 ]; then
        echo "  [dry] nvim --headless '+Lazy! sync' +qa"
    elif timeout 600 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1; then
        ok "plugins synced (lazy.nvim)"
    else
        warn "headless plugin sync did not finish; open nvim once"
    fi
fi

section "VS Code config (github.com/26zl/vscode_config)"
# Reuse the clone settings.json already links to, so a moved clone stays put.
vclink="$(readlink -f "$HOME/.config/Code/User/settings.json" 2>/dev/null || true)"
vcdir="${vclink%/settings.json}"
[ -d "$vcdir/.git" ] || vcdir="$HOME/.local/share/vscode_config"
if [ -d "$vcdir/.git" ]; then
    run git -C "$vcdir" pull -q --autostash --ff-only && ok "vscode_config up to date"
else
    run git clone -q https://github.com/26zl/vscode_config "$vcdir" && ok "cloned to $vcdir"
fi
# VSCODE_ROLE picks another vscode_config role: cybersec or fullstack.
vcrole="${VSCODE_ROLE:-sysadmin}"
if ! command -v code >/dev/null; then
    warn "code not installed; run apply-system.sh first"
elif [ "$DRY" -eq 1 ]; then
    echo "  [dry] $vcdir/install.sh --role $vcrole"
elif (cd "$vcdir" && ./install.sh --role "$vcrole" >/tmp/vscode-install.log 2>&1); then
    ok "settings linked + extensions: role $vcrole"
else
    warn "extension install failed (see /tmp/vscode-install.log); linking settings only"
    (cd "$vcdir" && ./install.sh --no-ext >/dev/null 2>&1) && ok "settings linked"
fi

section "GNOME"
if command -v gsettings >/dev/null && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    if [ "$DRY" -eq 1 ]; then bash scripts/apply-gnome.sh --dry-run; else bash scripts/apply-gnome.sh; fi
else
    warn "no desktop session bus here; run from the desktop: bash scripts/apply-gnome.sh"
fi

section "GitHub"
if [ "$DRY" -eq 1 ]; then
    echo "  [dry] scripts/setup-github.sh (git identity from the gh account)"
elif command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    bash scripts/setup-github.sh
else
    info "gh not authenticated — run: bash scripts/setup-github.sh"
fi

section "Done"
ok "User half applied."
info "Open a new terminal (kitty runs fish; bash keeps Ubuntu's defaults + the additions)."
info "Claude Code sandbox: /sandbox in claude, or merge configs/claude/settings.sandbox.json (see docs/DESIGN.md)."
