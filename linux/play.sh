#!/bin/bash
# Starts TTT2: what the Steam shortcut runs. First the updates (linux/update.sh: a new release from the original
# repo is downloaded, checked and built, with a progress window), then the game with the same switches as Start Here's
# "Play TTT2" on Windows (rex/setup-steps.ps1 Get-PlaySwitches + rex/run-windows.ps1), through Proton.
#
#   linux/play.sh             online (the default, as on Windows)
#   linux/play.sh --offline   without the online switches
#   linux/play.sh --name      asks for your name again
# Anything else goes to the game, e.g. --log_level=debug.
#
# Settings: rex/userdata/launcher-settings.txt, the same keys as on Windows (display=borderless|fullscreen|
# windowed-<W>x<H>, tearing=, online=false, keyboard=false, vibration=true, nointro=false, logupload=false,
# crashlog=false, autoupdate=false). Your profile (online identity, saves, name): data/profile.
source "$(dirname "$0")/common.sh"
exe="$BUILD/ttt2.exe"
userdata="$REX/userdata"
settings="$userdata/launcher-settings.txt"

winpath() { echo "Z:${1//\//\\}"; }
setting() { [ -f "$settings" ] && tr -d '\r' < "$settings" | grep -qx "$1"; }
setting_value() { [ -f "$settings" ] && tr -d '\r' < "$settings" | sed -n "s/^$1=//p" | tail -1 | tr 'A-Z' 'a-z'; }

offline=0
askname=0
pass=()
for a in "$@"; do
    case "$a" in
        --offline) offline=1 ;;
        --name) askname=1 ;;
        *) pass+=("$a") ;;
    esac
done

# Updates first (not when "autoupdate=false"; a failed check or download keeps the current build).
new=""
setting autoupdate=false || new="$("$LINUX_DIR/update.sh" --check)"
if [ -n "$new" ]; then
    if ! with_progress "Installing ${new#update * } (a few minutes)..." "$LINUX_DIR/update.sh"; then
        error_box "The update didn't work, so the current version starts. Details: $LOGS/update.log"
    fi
fi
if [ ! -f "$exe" ]; then
    with_progress 'Building the game...' "$LINUX_DIR/build.sh" ||
        { error_box "The game couldn't be built. Run linux/install.sh in a terminal, or see $LOGS/build.log"; exit 1; }
fi

mkdir -p "$userdata/cache" "$PROFILE"

# The player's name: 1 to 15 letters, digits and spaces (the game shows "User" for anything else).
namefile="$PROFILE/player-name.txt"
name="$( [ -f "$namefile" ] && tr -d '\r\n' < "$namefile" || true)"
while [ "$askname" = 1 ] || ! [[ "$name" =~ ^[A-Za-z0-9\ ]{1,15}$ ]]; do
    askname=0
    prompt='Your name in the game (1 to 15 letters, digits and spaces):'
    if gui; then
        name="$(zenity --entry --title=BlueSpark --text="$prompt" --entry-text="$name" 2>/dev/null)" || exit 0
    elif [ -t 0 ]; then
        read -r -p "$prompt " name
    else
        exit 1
    fi
    name="$(echo "$name" | sed 's/^ *//; s/ *$//')"
    [[ "$name" =~ ^[A-Za-z0-9\ ]{1,15}$ ]] && printf '%s' "$name" > "$namefile"
done

# The render targets seen on other PCs, for a first start (run-windows.ps1).
rt="$userdata/cache/render_targets_4E4D0859.txt"
[ -f "$rt" ] || cp "$REX/render-targets-seed.txt" "$rt"

# Controller mappings: the community list, then the player's own lines (they win).
mappings="$REX/gamecontrollerdb.txt"
if [ -f "$userdata/my-controllers.txt" ]; then
    cat "$REX/gamecontrollerdb.txt" "$userdata/my-controllers.txt" > "$userdata/cache/gamecontrollerdb.txt"
    mappings="$userdata/cache/gamecontrollerdb.txt"
fi

# The switches Start Here's Play gives the game (Get-PlaySwitches).
sw=(--latency_log=true --gpu_work_log_ms=8 --ttt2_hang_dump=true --ttt2_window_report=true --audio_stats=true
    --ttt2_xmsg_trace=true --ttt2_file_trace=true --ttt2_crash_dump=true)
sw+=(--ttt2_training=true --ttt2_training_dummy=true --ttt2_status_record=true --ttt2_training_easy_slow=true
     --ttt2_training_rewind=3 --ttt2_training_replay=true --ttt2_match_setup=true --ttt2_match_setup_profiles=true
     "--ttt2_training_settings=$(winpath "$userdata/training-settings.txt")")
if [ "$offline" = 0 ] && ! setting online=false; then
    sw+=(--live_signin=true --ttt2_live_net=true --ttt2_fight_splice=3)
    setting logupload=false || sw+=(--ttt2_log_autoupload=true)
    setting crashlog=false && sw+=(--ttt2_log_autoupload_crash=false)
    sw+=("--ttt2_live_gamertag=$name")
fi
keyboard=true
setting keyboard=false && keyboard=false
sw+=(--mnk_mode=false "--ttt2_keyboard=$keyboard" "--ttt2_keyboard_file=$(winpath "$userdata/keyboard.txt")")
release="$(sed -n 's/^name=//p' "$REX/package-info.txt" | tr -d '\r')"
sw+=("--ttt2_release_name=${release:-Release}")
setting vibration=true && sw+=(--ttt2_vibration=true)
setting nointro=false || sw+=(--ttt2_no_intro=true)

# The display (run-windows.ps1): borderless by default.
display="$(setting_value display)"; display="${display:-borderless}"
tearing="$(setting_value tearing)"; [ "$tearing" = true ] || tearing=false
[ "$display" = windowed ] && display=windowed-1920x1080
if [[ "$display" =~ ^windowed-([0-9]+)x([0-9]+)$ ]]; then
    sw+=(--fullscreen=false --fullscreen_exclusive=false "--window_pixel_width=${BASH_REMATCH[1]}"
         "--window_pixel_height=${BASH_REMATCH[2]}")
    tearing=false
else
    sw+=(--fullscreen=true "--fullscreen_exclusive=$([ "$display" = fullscreen ] && echo true || echo false)")
fi
sw+=("--present_tearing=$tearing")

args=("--game_data_root=$(winpath "$INSTALL/game")" "--update_data_root=$(winpath "$INSTALL/update")"
      "--user_data_root=$(winpath "$userdata")" "--profile_data_root=$(winpath "$PROFILE")"
      "--hid_mappings_file=$(winpath "$mappings")" "--user_name=$name" "${sw[@]}" "${pass[@]}")
printf '%q ' "$exe" "${args[@]}" > "$userdata/last-launch.txt"

cd "$BUILD"
exec "$LINUX_DIR/proton-env.sh" "$exe" "${args[@]}"
