#!/bin/bash
# Builds libxml2.so.2 (the stand-in, xml_stub.c) with the pinned LLVM 20.1.8. Its linker, lld, needs a libxml2.so.2 to
# start, so this runs where the system has one; the result is kept in the repository beside its source.
#
#   linux/lib/libxml2-stub/build.sh <LLVM's bin folder>
set -e
here="$(cd "$(dirname "$0")" && pwd)"
llvm="${1:?the LLVM bin folder}"
"$llvm/clang" --target=x86_64-linux-gnu -O2 -fPIC -fno-stack-protector -ffreestanding -nostdlib -shared \
    -fuse-ld=lld -Wl,-soname,libxml2.so.2 -Wl,--version-script="$here/libxml2.map" -Wl,--hash-style=both \
    -Wl,-z,noexecstack -Wl,--build-id=sha1 -o "$here/libxml2.so.2" "$here/xml_stub.c"
sha256sum "$here/libxml2.so.2"
