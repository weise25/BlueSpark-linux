#!/bin/bash
# Runs a Windows program of this package with Proton (common.sh, find_proton). With Steam as a flatpak it runs inside
# Steam's sandbox, which brings the 32-bit libraries and the runtime Proton needs. Proton's prefix: <install>/data/proton.
#
#   linux/proton-env.sh <program.exe> [args...]          through Proton (DXVK / vkd3d-proton: the game); needs Steam running
#   linux/proton-env.sh --wine <program.exe> [args...]   Proton's wine alone, same prefix (console tools: rexglue.exe)
source "$(dirname "$0")/common.sh"

if [ "$1" != "--inside" ] && ! in_steam_sandbox && have_flatpak_steam; then
    if [ "$1" != "--wine" ] && ! steam_running; then
        echo "# Starting Steam (Proton needs it)"
        flatpak run com.valvesoftware.Steam -silent >/dev/null 2>&1 &
        for _ in $(seq 90); do steam_running && break; sleep 1; done
        sleep 8
    fi
    exec flatpak run --filesystem="$INSTALL" --env=TTT2_PROTON="$TTT2_PROTON" --env=WINEDEBUG="${WINEDEBUG:--all}" \
        --env=PROTON_LOG="${PROTON_LOG:-0}" --command="$LINUX_DIR/proton-env.sh" com.valvesoftware.Steam --inside "$@"
fi
[ "$1" = "--inside" ] && shift

proton="$(find_proton)" || {
    echo "No Proton found. Install GE-Proton with ProtonUp-Qt (or Proton Experimental in Steam) and try again." >&2
    exit 1
}

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$(steam_root)"
export STEAM_COMPAT_DATA_PATH="$DATA/proton"
export SteamAppId="${SteamAppId:-0}" SteamGameId="${SteamGameId:-0}"
export WINEDEBUG="${WINEDEBUG:--all}"
mkdir -p "$STEAM_COMPAT_DATA_PATH"

if [ "$1" = "--wine" ]; then
    shift
    if [ ! -d "$STEAM_COMPAT_DATA_PATH/pfx/drive_c/windows" ]; then
        # (The prefix made by Proton itself, so it has DXVK and vkd3d-proton; Proton's launcher may stop after that
        # when Steam isn't running, which is fine here.)
        python3 "$proton/proton" run wineboot -u >/dev/null 2>&1 || true
    fi
    export WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx" WINEDLLOVERRIDES="mscoree,mshtml="
    exec "$proton/files/bin/wine" "$@"
fi
exec python3 "$proton/proton" waitforexitandrun "$@"
