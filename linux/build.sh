#!/bin/bash
# Steps 1-3 of Start Here on Linux, without questions: the compiler, your game files + title update, the build of
# ttt2.exe. Each step is skipped when it's done already, so it's also what an update runs. linux/install.sh asks for
# what this needs; by hand:
#
#   TTT2_ISO=<disc image or game folder> TTT2_TU=<title update file> linux/build.sh
#
# Microsoft's C++ runtime and Windows SDK are only downloaded once data/toolchain/ms-license-accepted exists (the
# installer asks). Progress: "# ..." lines; everything else in data/logs/build.log.
source "$(dirname "$0")/common.sh"
set -eo pipefail
# (Never from inside the build folder, which may be made anew below: Steam starts the game, and so an update, there.
# Steam's overlay library is for the game, not for the tools.)
cd "$INSTALL"
unset LD_PRELOAD
log="$LOGS/build.log"
: > "$log"
exec 3>&1 >>"$log" 2>&1
step() { echo "# $*" >&3; echo; echo "== $*"; }
fail() { echo "# Failed: $*" >&3; echo "FAILED: $*"; exit 1; }
# (A failed build never leaves the player without a game: the ttt2.exe that worked is put aside before a relink and
# put back if the build fails, with the DLLs it was built with, which are only replaced after a build that worked.)
last_good="$BUILD/ttt2.exe.last-good"
on_exit() {
    local rc=$?
    if [ $rc -ne 0 ]; then
        [ ! -f "$BUILD/ttt2.exe" ] && [ -f "$last_good" ] && mv -f "$last_good" "$BUILD/ttt2.exe"
        echo "# Failed (details: $log)" >&3
    fi
    exit $rc
}
trap on_exit EXIT
check() { [ "$(sha256 "$1")" = "$2" ] || fail "$(basename "$1") is not the file this build was made for (it must be TTT2 4E4D0859 with title update 0.0.3.2)."; }

# The pinned tools (the Windows package pins the same compiler and Microsoft libraries, rex/tools/toolchain.ps1).
fetch() {   # <url> <file> <sha256>
    [ -f "$2" ] && [ "$(sha256 "$2")" = "$3" ] && return
    curl -fsSL --retry 3 --retry-all-errors -o "$2.part" "$1"
    [ "$(sha256 "$2.part")" = "$3" ] || { rm -f "$2.part"; fail "the download of $1 doesn't match its pinned SHA-256"; }
    mv "$2.part" "$2"
}
mkdir -p "$TC/downloads"
if [ ! -x "$TC/llvm/bin/clang++" ]; then
    step 'Downloading the compiler (LLVM 20.1.8, about 2 GB: a few minutes)'
    fetch https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-Linux-X64.tar.xz \
        "$TC/downloads/llvm.tar.xz" 1ead36b3dfcb774b57be530df42bec70ab2d239fbce9889447c7a29a4ddc1ae6
    step 'Unpacking the compiler'
    rm -rf "$TC/llvm" && mkdir -p "$TC/llvm"
    tar xf "$TC/downloads/llvm.tar.xz" -C "$TC/llvm" --strip-components=1
    rm "$TC/downloads/llvm.tar.xz"
fi
if [ ! -x "$TC/cmake/bin/cmake" ]; then
    step 'Downloading CMake 3.31.8'
    fetch https://github.com/Kitware/CMake/releases/download/v3.31.8/cmake-3.31.8-linux-x86_64.tar.gz \
        "$TC/downloads/cmake.tar.gz" 630615d8e98ac33eba7fbe472626dff5c899c85af3c024585ae109166a6909d0
    rm -rf "$TC/cmake" && mkdir -p "$TC/cmake"
    tar xzf "$TC/downloads/cmake.tar.gz" -C "$TC/cmake" --strip-components=1
    rm "$TC/downloads/cmake.tar.gz"
fi
if [ ! -x "$TC/ninja/ninja" ]; then
    fetch https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-linux.zip \
        "$TC/downloads/ninja.zip" 6f98805688d19672bd699fbbfa2c2cf0fc054ac3df1f0e6a47664d963d530255
    mkdir -p "$TC/ninja" && python3 -I -m zipfile -e "$TC/downloads/ninja.zip" "$TC/ninja" && chmod +x "$TC/ninja/ninja"
    rm "$TC/downloads/ninja.zip"
fi
if [ ! -f "$TC/msvc/Windows Kits/10/Lib/10.0.26100/um/x64/kernel32.lib" ]; then
    [ -f "$TC/ms-license-accepted" ] || fail "Microsoft's license for its C++ runtime and Windows SDK isn't accepted yet: run linux/install.sh."
    step "Downloading Microsoft's C++ runtime and Windows SDK (from Microsoft, about 85 MB)"
    if [ ! -x "$TC/xwin/xwin" ]; then
        fetch https://github.com/Jake-Shadle/xwin/releases/download/0.10.0/xwin-0.10.0-x86_64-unknown-linux-musl.tar.gz \
            "$TC/downloads/xwin.tar.gz" d870eb4b2f390878af6da1ccd3cf321d22fcb72720984853b4be732ae597fc88
        mkdir -p "$TC/xwin" && tar xzf "$TC/downloads/xwin.tar.gz" -C "$TC/xwin" --strip-components=1
        rm "$TC/downloads/xwin.tar.gz"
    fi
    # (Three tries: a network hiccup mid-way is common; xwin keeps what it already downloaded in its cache.)
    for try in 1 2 3; do
        "$TC/xwin/xwin" --accept-license --log-level warn --cache-dir "$TC/xwin-cache" --arch x86_64 \
            --crt-version 14.44.17.14 --sdk-version 10.0.26100 splat --preserve-ms-arch-notation --use-winsysroot-style \
            --output "$TC/msvc" && break
        [ "$try" = 3 ] && fail "Microsoft's download didn't work (no internet?). Try again later."
        sleep 5
    done
    rm -rf "$TC/xwin-cache"
fi
export PATH="$TC/cmake/bin:$TC/ninja:$TC/llvm/bin:$PATH"

# Every tool must start here, before anything is changed. This runs on the desktop (the installer) and inside Steam's
# flatpak sandbox (an update started from Steam), whose libraries differ and change with their own updates.
# LLVM's linker (lld) is linked against libxml2.so.2, which it only uses to merge manifest files (never done here):
# where the system has none (Steam's runtime since October 2026 has libxml2.so.16), linux/lib/libxml2-stub stands in.
if ! "$TC/llvm/bin/lld-link" --version >/dev/null 2>&1; then
    export LD_LIBRARY_PATH="$LINUX_DIR/lib/libxml2-stub${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    echo "lld: libxml2.so.2 missing here, using linux/lib/libxml2-stub"
fi
for tool in "$TC/llvm/bin/clang --version" "$TC/llvm/bin/lld-link --version" "$TC/llvm/bin/llvm-rc /?" \
            "$TC/llvm/bin/llvm-lib /?" "$TC/cmake/bin/cmake --version" "$TC/ninja/ninja --version"; do
    $tool >/dev/null 2>&1 || { $tool 2>&1 | head -3; fail "$(basename "${tool%% *}") doesn't start here (details: $log)"; }
done

# --- your game files --------------------------------------------------------------------------------------------
xex=""
for x in "$INSTALL/game/Default.xex" "$INSTALL/game/default.xex"; do [ -f "$x" ] && xex="$x"; done
if [ -z "$xex" ]; then
    src="$TTT2_ISO"
    [ -n "$src" ] || fail "No game files yet: run linux/install.sh (it asks for your disc image)."
    if [ -d "$src" ]; then
        step 'Copying your game files'
        mkdir -p "$INSTALL/game" && cp -r "$src"/. "$INSTALL/game/"
    else
        step 'Unpacking your disc image (about 8 GB)'
        python3 -I "$LINUX_DIR/tools/xiso_extract.py" "$src" "$INSTALL/game"
    fi
    for x in "$INSTALL/game/Default.xex" "$INSTALL/game/default.xex"; do [ -f "$x" ] && xex="$x"; done
    [ -n "$xex" ] || fail "There's no default.xex in your game files."
fi
check "$xex" e74e57de3e205517e5447cacdba68624544fbd313ddb8c5f174b8e3ff43283d8
[ "$(ls "$INSTALL"/game/data*.bin | wc -l)" -ge 20 ] || fail "Not all data*.bin files are in $INSTALL/game."

if [ ! -f "$INSTALL/update/data100.bin" ]; then
    [ -n "$TTT2_TU" ] || fail "No title update yet: run linux/install.sh (it asks for it)."
    step 'Extracting your title update'
    rm -rf "$REX/out/title-update"
    python3 -I "$INSTALL/recomp/tools/stfs_extract.py" "$TTT2_TU" "$REX/out/title-update"
    for n in Default.xexp data100.bin data100.ofs; do
        [ -f "$REX/out/title-update/$n" ] || fail "That file isn't TTT2's title update (it has no $n)."
    done
    mkdir -p "$INSTALL/update" && cp "$REX/out/title-update/"{Default.xexp,data100.bin,data100.ofs} "$INSTALL/update/"
fi
check "$INSTALL/update/Default.xexp" c413fdfb2ba547e93fd16fa571c047f9914c5194526ddfa37c481ac84376f0e9
check "$INSTALL/update/data100.bin" 3c9ca28bea95423da1e2d667fea941b620d33433e375e11a5782939c34b9fc4d
check "$INSTALL/update/data100.ofs" e2985f8a45d404ca525696edd7cdf1df7678efcee2af1a9e78f3e7cdd6474fce

winpath() { echo "Z:${1//\//\\}"; }
if [ ! -f "$INSTALL/gamedata/default_tu.xex" ] || [ "$(sha256 "$INSTALL/gamedata/default_tu.xex")" != 5ab29622d2dfb123dca5894e5a9d7f21dc88bb52367056830edd09dfaf162146 ]; then
    step 'Applying the title update to default.xex'
    # (The package's source/xexpatch, built as the Windows tool it is and run with Proton's wine: no compiler for
    # Linux programs needed.)
    s="$INSTALL/source/xexpatch/XenonRecomp"; w="$REX/out/xexpatch"
    rm -rf "$w" && mkdir -p "$w"
    cl=(clang-cl /nologo /O2 /MT /DNOMINMAX /D_CRT_SECURE_NO_WARNINGS -fuse-ld=lld /winsysroot "$TC/msvc"
        /I"$s/XenonUtils" /I"$s/thirdparty/libmspack/libmspack/mspack" /I"$s/thirdparty/tiny-AES-c" /I"$s/thirdparty/TinySHA1")
    (cd "$w" && "${cl[@]}" /c "$s/thirdparty/libmspack/libmspack/mspack/lzxd.c" "$s/thirdparty/tiny-AES-c/aes.c" &&
        "${cl[@]}" /c /EHsc /std:c++20 -w "$s"/XenonUtils/{xex_patcher,xex,image,memory_mapped_file}.cpp \
            "$INSTALL/source/xexpatch/xexpatch.cpp" &&
        "${cl[@]}" /Fexexpatch.exe ./*.obj)
    mkdir -p "$INSTALL/gamedata"
    "$LINUX_DIR/proton-env.sh" --wine "$w/xexpatch.exe" "$(winpath "$xex")" "$(winpath "$INSTALL/update/Default.xexp")" \
        "$(winpath "$INSTALL/gamedata/default_tu.xex")"
fi
check "$INSTALL/gamedata/default_tu.xex" 5ab29622d2dfb123dca5894e5a9d7f21dc88bb52367056830edd09dfaf162146
cp -f "$INSTALL/gamedata/default_tu.xex" "$INSTALL/game/default_tu.xex"

# --- the build (rex/build-windows.ps1's prebuilt path) --------------------------------------------------------------
manifest="$REX/prebuilt/manifest.txt"
[ -f "$manifest" ] || fail "The package isn't here (no rex/prebuilt/manifest.txt): run linux/install.sh."
[ "$(sha256 "$REX/prebuilt/sdk/bin/rexglue.exe" | tr a-f A-F)" = "$(sed -n 's/^codegen.rexglue=//p' "$manifest" | tr -d '\r')" ] ||
    fail "rex/prebuilt/sdk/bin/rexglue.exe is not this release's: the package is damaged."
# (A new package: relinked; its translation made anew when the translation's inputs changed.)
if [ -f "$BUILD/prebuilt-manifest.txt" ] && ! cmp -s "$BUILD/prebuilt-manifest.txt" "$manifest"; then
    [ -f "$BUILD/ttt2.exe" ] && mv -f "$BUILD/ttt2.exe" "$last_good"
    if [ "$(grep '^codegen\.' "$BUILD/prebuilt-manifest.txt")" != "$(grep '^codegen\.' "$manifest")" ]; then
        rm -rf "$REX/generated/default"
    fi
fi
# (A build folder made for another install folder, one moved or copied here: configured anew.)
if [ -f "$BUILD/CMakeCache.txt" ] && ! grep -qxF "CMAKE_HOME_DIRECTORY:INTERNAL=$REX" "$BUILD/CMakeCache.txt"; then
    rm -rf "$BUILD"
fi
step 'Configuring the game'
cmake -G Ninja -S "$REX" -B "$BUILD" -DCMAKE_TOOLCHAIN_FILE="$LINUX_DIR/windows-cross.cmake" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MAKE_PROGRAM="$TC/ninja/ninja" -Drexglue_DIR="$LINUX_DIR/cmake-shim/rexglue" \
    -DCMAKE_PREFIX_PATH="$REX/prebuilt/sdk" -DCMAKE_TRY_COMPILE_CONFIGURATION=Release -DTTT2_PREBUILT=ON -DTTT2_OURS_LIB=OFF
if [ ! -f "$REX/generated/default/sources.cmake" ]; then
    step "Translating the game's code (about 2 minutes)"
    cmake --build "$BUILD" --target ttt2_codegen
    cmake "$BUILD"
fi
# The library was made for one translation of the game: this PC's must be the same (the condition for playing online).
want="$(sed -n 's/^codegen.partition=//p' "$manifest" | tr -d '\r')"
got="$(sed 's/\r$//' "$REX/generated/default/codegen.partition.json" | sha256sum | cut -d' ' -f1)"
[ "$got" = "$want" ] || fail "The translation didn't match this release (your game files or the package are not the expected ones)."
step 'Building the game (a few minutes the first time)'
cmake --build "$BUILD"
cp -f "$REX/prebuilt/sdk/bin/"*.dll "$BUILD/"
# Every hooked sub_X must come from ttt2_ours, by the link map (build-windows.ps1's check).
missing=0
for h in $(sed -n 's/^hooks=//p' "$manifest" | tr -d '\r'); do
    grep -qE "[[:space:]]$h[[:space:]].*ttt2_ours" "$BUILD/ttt2.map" || missing=$((missing + 1))
done
[ "$missing" = 0 ] || { rm -f "$BUILD/ttt2.exe"; fail "the link dropped $missing hooks"; }
cp -f "$manifest" "$BUILD/prebuilt-manifest.txt"
rm -f "$last_good"
step 'Done'
