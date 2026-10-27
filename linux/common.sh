# Shared by the Linux scripts (sourced). Everything lives in the install folder, the parent of linux/:
#   <install>/            the official package (rex/, recomp/, source/, gamedata/, ...), from the original repo's feed
#   <install>/linux/      these scripts (from the BlueSpark-linux fork)
#   <install>/game/       your game files (from your disc image), <install>/update/ your title update's files
#   <install>/data/       the compiler (toolchain/), Proton's prefix (proton/), your profile (profile/), logs (logs/)
# One folder, so that Steam's flatpak sandbox sees it all at the same path.

LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$(dirname "$LINUX_DIR")"
REX="$INSTALL/rex"
DATA="$INSTALL/data"
TC="$DATA/toolchain"
LOGS="$DATA/logs"
PROFILE="$DATA/profile"
BUILD="$REX/out/build/win-amd64-release"

# The original project's update feed (the one Start Here reads on Windows) and this fork (the Linux scripts).
FEED_URL="https://raw.githubusercontent.com/avim2/BlueSpark/main/latest.json"
FEED_BASE="https://raw.githubusercontent.com/avim2/BlueSpark/main/"
LINUX_REPO="$(tr -d '\r\n' < "$LINUX_DIR/repo.txt" 2>/dev/null)"
LINUX_REPO="${LINUX_REPO:-weise25/BlueSpark-linux}"
LINUX_RAW="https://raw.githubusercontent.com/$LINUX_REPO/main"

mkdir -p "$LOGS"

in_steam_sandbox() { [ "$FLATPAK_ID" = com.valvesoftware.Steam ]; }
have_flatpak_steam() { command -v flatpak >/dev/null && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; }

# Steam's own folder, as seen from where this runs.
steam_root() {
    local d
    if ! in_steam_sandbox && have_flatpak_steam; then
        echo "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; return
    fi
    for d in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"; do
        [ -d "$d/steamapps" ] && { readlink -f "$d"; return; }
    done
    echo "$HOME/.local/share/Steam"
}

# The Proton to run the game with: $TTT2_PROTON (a folder name or path); else a GE-Proton with hardware FMA (its
# ucrtbase.dll computes fma() with the CPU's instruction, and ttt2.exe calls fma() for the Xbox CPU's fused
# multiply-adds); else the newest GE-Proton; else Valve's Proton Experimental or newest Proton.
find_proton() {
    local root tools p
    root="$(steam_root)"
    tools="$root/compatibilitytools.d"
    if [ -n "$TTT2_PROTON" ]; then
        for p in "$TTT2_PROTON" "$tools/$TTT2_PROTON" "$root/steamapps/common/$TTT2_PROTON"; do
            [ -f "$p/proton" ] && { echo "$p"; return; }
        done
    fi
    for p in "$tools"/*/; do
        p="${p%/}"
        [ -f "$p/proton" ] && grep -qi 'fma' "$p/version" 2>/dev/null && { echo "$p"; return; }
    done
    p="$(ls -d "$tools"/GE-Proton* 2>/dev/null | sort -V | tail -1)"
    [ -n "$p" ] && [ -f "$p/proton" ] && { echo "$p"; return; }
    p="$root/steamapps/common/Proton - Experimental"
    [ -f "$p/proton" ] && { echo "$p"; return; }
    p="$(ls -d "$root/steamapps/common/Proton "[0-9]* 2>/dev/null | sort -V | tail -1)"
    [ -n "$p" ] && [ -f "$p/proton" ] && { echo "$p"; return; }
    return 1
}

steam_running() { pgrep -x steam >/dev/null || pgrep -f 'ubuntu12_32/steam' >/dev/null; }

# --- messages: a window when there's a desktop and no terminal (started from Steam), else the terminal --------------
gui() { [ ! -t 1 ] && [ -n "$DISPLAY$WAYLAND_DISPLAY" ] && command -v zenity >/dev/null; }
say() { echo "$*"; }
info_box() {
    if gui; then zenity --info --title=BlueSpark --width=420 --text="$1" 2>/dev/null; else echo; echo "$1"; fi
}
error_box() {
    if gui; then zenity --error --title=BlueSpark --width=480 --text="$1" 2>/dev/null; else echo; echo "ERROR: $1" >&2; fi
}
ask_yes() {
    if gui; then zenity --question --title=BlueSpark --width=420 --text="$1" 2>/dev/null; return; fi
    local a; read -r -p "$1 [y/N] " a; [ "$a" = y ] || [ "$a" = Y ] || [ "$a" = j ] || [ "$a" = J ]
}
# Runs "$@" with its "# text" lines shown: a progress window from Steam, the terminal otherwise.
with_progress() {
    local title="$1"; shift
    if gui; then
        set -o pipefail
        "$@" 2>&1 | grep --line-buffered '^#' |
            zenity --progress --pulsate --auto-close --no-cancel --title=BlueSpark --width=460 --text="$title" 2>/dev/null
        local rc=$?
        set +o pipefail
        return $rc
    fi
    "$@"
}

sha256() { sha256sum "$1" | cut -d' ' -f1; }
