#!/bin/bash
# rexglue.exe (the code translator) through GE-Proton's wine in the Steam flatpak; run from rex/ by the build.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
# (Absolute Linux paths as Wine's Z: paths: rexglue reads "/var/..." as a Windows-style switch.)
args=()
for a in "$@"; do
    if [[ "$a" == /* ]]; then args+=("Z:$a"); else args+=("$a"); fi
done
"$here/proton-env.sh" --wine "$repo/rex/prebuilt/sdk/bin/rexglue.exe" "${args[@]}" || exit $?
# (The depfile names Windows paths, Z:/...: ninja needs the Linux ones.)
[ -f "$repo/rex/generated/default/codegen.d" ] && sed -i 's|Z:/|/|g' "$repo/rex/generated/default/codegen.d"
exit 0
