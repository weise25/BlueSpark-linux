#!/bin/bash
# Keeps the install up to date, as Start Here does on Windows:
#  1. the Linux scripts, from the BlueSpark-linux fork (linux/VERSION and linux/files.txt there);
#  2. the game package, from the original repo's feed (latest.json): a newer release is downloaded, its size and
#     SHA-256 checked against the feed, its signature and file list checked as Start Here does
#     (linux/tools/package_check.py), and copied over this folder (rex/userdata, gamedata/, rex/out/ and this
#     folder's own game/, update/, data/, linux/ never touched);
#  3. then linux/build.sh relinks the game.
#
#   linux/update.sh            checks, updates, builds
#   linux/update.sh --check    prints "update <release> <name>" when the feed has a newer release, else nothing
# Progress: "# ..." lines. No network: nothing to do, exit 0.
source "$(dirname "$0")/common.sh"
set -eo pipefail
log="$LOGS/update.log"
exec 3>&1 >>"$log" 2>&1
echo "== $(date -Is) update.sh $*"
step() { echo "# $*" >&3; echo "== $*"; }
fail() { echo "# Failed: $*" >&3; echo "FAILED: $*"; exit 1; }

local_patch() { sed -n 's/^patch=//p' "$REX/package-info.txt" 2>/dev/null | tr -d '\r' || true; }
local_track() { sed -n 's/^track=//p' "$REX/package-info.txt" 2>/dev/null | tr -d '\r' || true; }
feed_field() { python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2],""); print(v)' "$1" "$2"; }

feed="$LOGS/latest.json"
curl -fsS --max-time 10 -o "$feed.part" "$FEED_URL" || { echo "No feed (offline?)"; exit 0; }
mv "$feed.part" "$feed"
release="$(feed_field "$feed" release)"
name="$(feed_field "$feed" name)"
have="$(local_patch)"; have="${have:-0}"

mine="$(tr -d '\r\n' < "$LINUX_DIR/VERSION" 2>/dev/null || echo 0)"
theirs="$(curl -fsS --max-time 10 "$LINUX_RAW/linux/VERSION" | tr -d '\r\n' || true)"
scripts_new() { [ -n "$theirs" ] && [ "$theirs" -gt "$mine" ] 2>/dev/null; }

if [ "$1" = "--check" ]; then
    if [ -n "$release" ] && [ "$release" -gt "$have" ]; then echo "update $release $name" >&3
    elif scripts_new; then echo "update scripts the Linux scripts" >&3
    fi
    exit 0
fi

# 1. The Linux scripts (a newer linux/VERSION in the fork): every file in its files.txt, then this script again.
if [ -z "$TTT2_NO_SELF_UPDATE" ]; then
    if scripts_new; then
        step "Updating the Linux scripts ($mine -> $theirs)"
        tmp="$DATA/linux-update"
        rm -rf "$tmp" && mkdir -p "$tmp"
        curl -fsS --max-time 30 -o "$tmp/files.txt" "$LINUX_RAW/linux/files.txt"
        while read -r f; do
            [ -n "$f" ] || continue
            case "$f" in /*|*..*) fail "bad file name in files.txt: $f" ;; esac
            mkdir -p "$tmp/$(dirname "$f")"
            curl -fsS --max-time 60 -o "$tmp/$f" "$LINUX_RAW/linux/$f"
        done < "$tmp/files.txt"
        cp -r "$tmp"/. "$LINUX_DIR/"
        chmod +x "$LINUX_DIR"/*.sh
        rm -rf "$tmp"
        exec 1>&3 2>&1
        TTT2_NO_SELF_UPDATE=1 exec "$LINUX_DIR/update.sh" "$@"
    fi
fi

# 2. The game package.
if [ -n "$release" ] && [ "$release" -gt "$have" ]; then
    track="$(local_track)"
    if [ -n "$track" ] && [ "$track" != release ]; then
        echo "This is a $track package: it doesn't update from the public feed."
    else
        step "Downloading $name (Release $release)"
        zip_rel="$(feed_field "$feed" zip)"
        case "$zip_rel" in http*) url="$zip_rel" ;; *) url="$FEED_BASE$zip_rel" ;; esac
        work="$DATA/update-download"
        rm -rf "$work" && mkdir -p "$work"
        zip="$work/package.zip"
        curl -fsSL --retry 3 --retry-all-errors -o "$zip" "$url"
        [ "$(stat -c %s "$zip")" = "$(feed_field "$feed" size)" ] || fail "the download's size isn't the feed's: the current build is kept"
        [ "$(sha256 "$zip")" = "$(feed_field "$feed" sha256 | tr A-F a-f)" ] || fail "the download's SHA-256 isn't the feed's: the current build is kept"
        step 'Checking the package (signature)'
        said="$(python3 -I "$LINUX_DIR/tools/package_check.py" "$zip")" || fail "$said The current build is kept."
        echo "$said"
        set -- $said
        [ -z "$track" ] || [ "$2" = "$track" ] || fail "the feed's zip is a $2 package, this folder a $track one"
        step 'Installing the update'
        python3 -I - "$zip" "$INSTALL" <<'EOF'
import os, shutil, sys, zipfile
# The package's top folder copied over the install (Start Here's Copy-Over): nothing deleted, these never touched.
NEVER = ('rex/userdata', 'gamedata', 'rex/out', 'rex/game-folder.txt')
OURS = ('linux', 'data', 'game', 'update')
zip_path, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_path) as z:
    for i in z.infolist():
        parts = i.filename.replace('\\', '/').split('/', 1)
        if len(parts) < 2 or not parts[1] or i.filename.endswith('/'):
            continue
        rel = parts[1]
        if any(rel == n or rel.startswith(n + '/') for n in NEVER) or rel.split('/', 1)[0] in OURS:
            continue
        target = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with z.open(i) as src, open(target + '.part', 'wb') as out:
            shutil.copyfileobj(src, out)
        os.replace(target + '.part', target)
print('installed')
EOF
        rm -rf "$work"
        echo "Updated to Release $release"
    fi
fi

# 3. The build (relinks after an update; nothing to do when it's current).
if [ -f "$INSTALL/update/data100.bin" ]; then
    "$LINUX_DIR/build.sh" >&3 || fail "the build failed (details: $LOGS/build.log)"
fi
