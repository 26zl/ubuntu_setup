#!/usr/bin/env bash
# GNOME 50 settings: Nord-ish look, Nerd Font terminals running fish, privacy
# toggles, Norwegian formats, a floating dock with four favourites, kitty on
# Super+Return. Every key is checked against the installed schemas first, so a
# renamed key warns instead of failing.
#   bash scripts/apply-gnome.sh [--dry-run]     # as your user, from the desktop
set -euo pipefail

TEAL='\033[38;2;136;192;208m'
RED='\033[38;2;191;97;106m'
RESET='\033[0m'
ok()   { echo -e "  ${TEAL}✓${RESET} $1"; }
warn() { echo -e "  ${RED}!${RESET} $1"; }

DRY=0
case "${1:-}" in
    --dry-run) DRY=1 ;;
    "") ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
esac

command -v gsettings >/dev/null || { warn "gsettings not found (no GNOME here); nothing to do"; exit 0; }
[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || { warn "no session bus; run this from the desktop session"; exit 0; }

# gset SCHEMA[:PATH] KEY VALUE
gset() {
    if gsettings writable "$1" "$2" >/dev/null 2>&1; then
        if [ "$DRY" -eq 1 ]; then
            echo "  [dry] gsettings set $1 $2 $3"
        else
            gsettings set "$1" "$2" "$3" && ok "$1 $2 = $3"
        fi
    else
        warn "unknown key, skipped: $1 $2"
    fi
}

# look
gset org.gnome.desktop.interface color-scheme "'prefer-dark'"
gset org.gnome.desktop.interface accent-color "'blue'"          # Nord frost; Yaru follows the accent
gset org.gnome.desktop.interface monospace-font-name "'JetBrainsMono Nerd Font 11'"
gset org.gnome.desktop.interface clock-show-weekday true
gset org.gnome.desktop.interface show-battery-percentage true
gset org.gnome.desktop.calendar show-weekdate true
gset org.gnome.desktop.wm.preferences focus-mode "'click'"
gset org.gnome.mutter center-new-windows true
# Nordzy icons and cursor when apply-user.sh has installed them (per user; the
# lock screen keeps Yaru's cursor, GDM does not read ~/.local)
[ -f "$HOME/.local/share/icons/Nordzy-dark/index.theme" ] && gset org.gnome.desktop.interface icon-theme "'Nordzy-dark'"
[ -f "$HOME/.local/share/icons/Nordzy-cursors/index.theme" ] && gset org.gnome.desktop.interface cursor-theme "'Nordzy-cursors'"

# privacy
gset org.gnome.desktop.privacy report-technical-problems false
gset org.gnome.desktop.privacy send-software-usage-stats false
gset org.gnome.desktop.privacy remove-old-temp-files true
gset org.gnome.desktop.privacy remove-old-trash-files true
gset org.gnome.desktop.privacy old-files-age "uint32 30"
gset org.gnome.desktop.privacy recent-files-max-age 30
gset org.gnome.desktop.notifications show-in-lock-screen false
gset org.gnome.desktop.screensaver lock-enabled true
gset org.gnome.desktop.screensaver lock-delay "uint32 0"
gset org.gnome.desktop.session idle-delay "uint32 300"
gset org.gnome.system.location enabled false
# the snap-store search provider sends every overview search term to the Snap
# Store and the web-search provider adds a Google row (with Canonical's
# affiliate tag) to every search; disabled-extensions overrides the ones the
# ubuntu session mode enables
gset org.gnome.shell disabled-extensions "['snapd-search-provider@canonical.com', 'web-search-provider@ubuntu.com']"
# Caffeine, once apply-user.sh has installed it: appended to the enabled list
# so the extensions the session already runs stay on
if [ -f "$HOME/.local/share/gnome-shell/extensions/caffeine@patapon.info/metadata.json" ]; then
    enabled=$(gsettings get org.gnome.shell enabled-extensions)
    case "$enabled" in
        *"'caffeine@patapon.info'"*) ok "Caffeine enabled" ;;
        "@as []"|"[]") gset org.gnome.shell enabled-extensions "['caffeine@patapon.info']" ;;
        *) gset org.gnome.shell enabled-extensions "${enabled%]}, 'caffeine@patapon.info']" ;;
    esac
fi

# region: English UI, Norwegian formats (needs nb_NO.UTF-8 from apply-system.sh)
if locale -a 2>/dev/null | grep -i '^nb_NO.utf8$' >/dev/null; then
    gset org.gnome.system.locale region "'nb_NO.UTF-8'"
else
    warn "nb_NO.UTF-8 not generated; region left unchanged"
fi

# laptop
gset org.gnome.desktop.peripherals.touchpad tap-to-click true
gset org.gnome.desktop.peripherals.touchpad natural-scroll true
gset org.gnome.settings-daemon.plugins.power power-button-action "'interactive'"

# terminals: Ptyxis (Ubuntu's default) gets the Nord palette, the Nerd Font and fish
gset org.gnome.Ptyxis use-system-font false
gset org.gnome.Ptyxis font-name "'JetBrainsMono Nerd Font 11'"
gset org.gnome.Ptyxis interface-style "'dark'"
uuid=$(gsettings get org.gnome.Ptyxis default-profile-uuid 2>/dev/null | tr -d "'")
if [ -n "$uuid" ]; then
    profile="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$uuid/"
    gset "$profile" palette "'nord'"
    if [ -x /usr/bin/fish ]; then
        gset "$profile" use-custom-command true
        gset "$profile" custom-command "'/usr/bin/fish'"
    fi
fi
# Ptyxis keeps its stock shortcuts: select all is Ctrl+Shift+A, so Ctrl+A stays
# the shell's beginning-of-line
gset org.gnome.Ptyxis.Shortcuts select-all "'<ctrl><shift>a'"
# Super+Return opens kitty (Ctrl+Alt+T keeps opening the GNOME default terminal)
if [ -x /usr/bin/kitty ]; then
    kb="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kitty/"
    current=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | sed 's/^@as //')
    merged=$(python3 -c "import ast,sys; l=ast.literal_eval(sys.argv[1]); p=sys.argv[2]; l.append(p) if p not in l else None; print(l)" "$current" "$kb")
    gset org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$merged"
    gset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$kb" name "'Terminal (kitty)'"
    gset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$kb" command "'kitty'"
    gset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$kb" binding "'<Super>Return'"
fi

# dock: floating at the bottom, only the apps in daily use
gset org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
gset org.gnome.shell.extensions.dash-to-dock extend-height false     # floating dash, not a full-width panel
gset org.gnome.shell.extensions.dash-to-dock dock-fixed false        # hides under an overlapping window; hover the edge to show
gset org.gnome.shell.extensions.dash-to-dock intellihide true
gset org.gnome.shell.extensions.dash-to-dock autohide true
gset org.gnome.shell.extensions.dash-to-dock show-mounts false       # no drive icons in the dock
gset org.gnome.shell.extensions.dash-to-dock show-trash false
gset org.gnome.shell.extensions.dash-to-dock show-show-apps-button true
gset org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 48
# favourites: the first existing alternative per app (a|b), flatpak exports included;
# App Center is the snap-store snap, whose entry keeps the old snap-store_ name;
# VS Code renamed its entry to com.microsoft.VSCode.desktop in 2026, Chrome's
# visible entry is still google-chrome.desktop (com.google.Chrome is NoDisplay)
favs=()
for alts in kitty.desktop google-chrome.desktop org.gnome.Nautilus.desktop com.discordapp.Discord.desktop \
            "com.microsoft.VSCode.desktop|code.desktop" org.gnome.TextEditor.desktop \
            "snap-store_snap-store.desktop|app-center_app-center.desktop" org.gnome.Settings.desktop; do
    IFS='|' read -ra names <<<"$alts"
    for d in "${names[@]}"; do
        found=0
        for dir in /usr/share/applications /var/lib/snapd/desktop/applications \
                   /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications" \
                   "$HOME/.local/share/applications"; do
            [ -f "$dir/$d" ] && { favs+=("'$d'"); found=1; break; }
        done
        [ "$found" -eq 1 ] && break
    done
done
if [ "${#favs[@]}" -gt 0 ]; then
    gset org.gnome.shell favorite-apps "[$(IFS=,; echo "${favs[*]}")]"
fi
