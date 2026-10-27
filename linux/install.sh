#!/bin/bash
# BlueSpark (TTT2) for Linux: the installer. One command in a terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/weise25/BlueSpark-linux/main/linux/install.sh | bash
#
# It puts everything in ~/Games/BlueSpark (or $BLUESPARK_DIR), downloads the newest official package from the original
# project, asks for your disc image and title update, builds the game and adds it to Steam. Run it again any time:
# it skips what's done.
set -eo pipefail
REPO="${BLUESPARK_REPO:-weise25/BlueSpark-linux}"

# --- started by itself (curl | bash): the scripts fetched into the install folder first ------------------------------
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ ! -f "$here/common.sh" ] || [ ! -f "$here/install.sh" ]; then
    dir="${BLUESPARK_DIR:-$HOME/Games/BlueSpark}"
    echo "BlueSpark for Linux: installing into $dir"
    mkdir -p "$dir/linux"
    raw="https://raw.githubusercontent.com/$REPO/main/linux"
    curl -fsSL -o "$dir/linux/files.txt" "$raw/files.txt"
    while read -r f; do
        [ -n "$f" ] || continue
        case "$f" in /*|*..*) echo "Bad file name in files.txt: $f" >&2; exit 1 ;; esac
        mkdir -p "$dir/linux/$(dirname "$f")"
        curl -fsSL -o "$dir/linux/$f" "$raw/$f"
    done < "$dir/linux/files.txt"
    chmod +x "$dir/linux/"*.sh
    exec bash "$dir/linux/install.sh" "$@" < /dev/tty
fi

source "$here/common.sh"
[ -t 0 ] || exec < /dev/tty
bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

bold "BlueSpark (Tekken Tag Tournament 2) for Linux"
echo "Folder: $INSTALL"

# --- Steam and Proton ---------------------------------------------------------------------------------------------
if have_flatpak_steam; then
    steam_cmd=(flatpak run com.valvesoftware.Steam)
    # (Steam's sandbox has to see this folder: the game runs inside it.)
    flatpak override --user --filesystem="$INSTALL" com.valvesoftware.Steam
elif command -v steam >/dev/null; then
    steam_cmd=(steam)
else
    die "Steam isn't installed. Install Steam (for example from your software center / Flathub), start it once, log in, and run this again."
fi
[ -d "$(steam_root)/userdata" ] || die "Start Steam once and log in, then run this again."
if ! proton="$(find_proton)"; then
    die "No Proton found. Install GE-Proton: open ProtonUp-Qt (from your software center), add the newest GE-Proton for Steam, and run this again. (Or in Steam: install \"Proton Experimental\" from the library's Tools.)"
fi
echo "Proton: $(basename "$proton")"

# --- the official package (the original project's newest release) ---------------------------------------------------
if [ ! -f "$REX/prebuilt/manifest.txt" ]; then
    bold "Downloading the newest BlueSpark release (about 50 MB)"
    TTT2_NO_SELF_UPDATE=1 "$LINUX_DIR/update.sh" | sed 's/^# /  /' || true
    [ -f "$REX/prebuilt/manifest.txt" ] || die "The download didn't work. Details: $LOGS/update.log"
fi
echo "Package: $(sed -n 's/^name=//p' "$REX/package-info.txt" | tr -d '\r')"

# --- your game files ------------------------------------------------------------------------------------------------
pick_file() {   # <title> <filter description>; prints the chosen path
    if [ -n "$DISPLAY$WAYLAND_DISPLAY" ] && command -v kdialog >/dev/null; then
        kdialog --title "$1" --getopenfilename "$HOME" 2>/dev/null && return
    elif [ -n "$DISPLAY$WAYLAND_DISPLAY" ] && command -v zenity >/dev/null; then
        zenity --file-selection --title="$1" 2>/dev/null && return
    fi
    local p
    read -r -p "Drag the file into this window (or type its path), then press Enter: " p
    p="${p%\'}"; p="${p#\'}"; p="${p%\"}"; p="${p#\"}"
    echo "$p"
}
find_candidates() {   # <find -name pattern> <min size>
    find "$INSTALL" "$HOME/Downloads" "$HOME/Games" "$HOME/Documents" "$HOME/Dokumente" "$HOME/Desktop" "$HOME" \
        -maxdepth 3 -type f -iname "$1" -size "$2" 2>/dev/null | grep -v "/data/\|/\.local/\|/\.var/" | sort -u | head -5
}

iso=""
if [ ! -f "$INSTALL/game/Default.xex" ] && [ ! -f "$INSTALL/game/default.xex" ]; then
    bold "Your Tekken Tag Tournament 2 disc image (Xbox 360, .iso)"
    mapfile -t found < <(find_candidates '*.iso' +6G)
    for c in "${found[@]}"; do
        if ask_yes "Use $c?"; then iso="$c"; break; fi
    done
    while [ -z "$iso" ] || [ ! -e "$iso" ]; do
        echo "Choose your disc image (.iso), or your game folder's default.xex."
        iso="$(pick_file 'Your TTT2 disc image (.iso)')"
        [ -z "$iso" ] && die "No disc image chosen."
        case "$iso" in *.xex|*.XEX) iso="$(dirname "$iso")" ;; esac
    done
fi
tu=""
if [ ! -f "$INSTALL/update/data100.bin" ]; then
    bold "Your title update (a file named like TU_174Q22P_0000008000000.00000000000O2, about 3 MB)"
    mapfile -t found < <(find_candidates 'TU_*' +1M)
    for c in "${found[@]}"; do
        if ask_yes "Use $c?"; then tu="$c"; break; fi
    done
    while [ -z "$tu" ] || [ ! -f "$tu" ]; do
        echo "Choose your title update file."
        tu="$(pick_file 'Your TTT2 title update (TU_...)')"
        [ -z "$tu" ] && die "No title update chosen."
    done
fi

# --- Microsoft's license (as Start Here's "Install tools" asks on Windows) -----------------------------------------
mkdir -p "$TC"
if [ ! -f "$TC/ms-license-accepted" ]; then
    bold "Microsoft's C++ libraries"
    echo "Building the game needs Microsoft's C++ runtime and Windows SDK, downloaded from Microsoft (about 85 MB)."
    echo "License: https://visualstudio.microsoft.com/license-terms/vs2022-ga-diagnosticbuildtools/"
    ask_yes "Do you accept Microsoft's license?" || die "Without them the game can't be built."
    date -Is > "$TC/ms-license-accepted"
fi

# --- the build ----------------------------------------------------------------------------------------------------
bold "Building the game (the first time: about 2 GB of downloads and 5-10 minutes)"
TTT2_ISO="$iso" TTT2_TU="$tu" "$LINUX_DIR/build.sh" | sed 's/^# /  /' ||
    die "The build failed. Details: $LOGS/build.log"

# --- your name ----------------------------------------------------------------------------------------------------
mkdir -p "$PROFILE"
if [ ! -s "$PROFILE/player-name.txt" ]; then
    bold "Your name in the game"
    while :; do
        read -r -p "1 to 15 letters, digits and spaces: " name
        name="$(echo "$name" | sed 's/^ *//; s/ *$//')"
        [[ "$name" =~ ^[A-Za-z0-9\ ]{1,15}$ ]] && { printf '%s' "$name" > "$PROFILE/player-name.txt"; break; }
    done
fi

# --- Steam --------------------------------------------------------------------------------------------------------
bold "Adding the game to Steam"
if steam_running; then
    echo "Steam has to close for a moment (it would undo the change otherwise)."
    ask_yes "Close Steam now?" || die "Not added to Steam. Run this again when Steam is closed: the game is built."
    "${steam_cmd[@]}" -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 60); do steam_running || break; sleep 1; done
    steam_running && die "Steam didn't close. Close it yourself and run this again."
    sleep 2
fi
python3 -I "$LINUX_DIR/tools/steam_shortcut.py" --steam "$(steam_root)" --name "Tekken Tag Tournament 2 (BlueSpark)" \
    --exe "$LINUX_DIR/play.sh" --start-dir "$LINUX_DIR" --icon "$REX/assets/gamerpic.png" \
    --hero "$REX/assets/splash/bluespark-1920x1080.jpg" --header "$REX/assets/splash/bluespark-1920x1080.jpg"
nohup "${steam_cmd[@]}" >/dev/null 2>&1 &

bold "Done!"
echo "In Steam: \"Tekken Tag Tournament 2 (BlueSpark)\". Press Play. Updates install by themselves when you start it."
echo "Settings (window, keyboard, online, ...): $REX/userdata/launcher-settings.txt"
echo "If something goes wrong, the logs are in $LOGS and $BUILD/logs."
