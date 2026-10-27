# Cross-compiles the Windows ttt2.exe on Linux with the pinned LLVM 20.1.8 and xwin's MSVC CRT / Windows SDK,
# the same compiler and Microsoft libraries rex\tools\toolchain.ps1 uses on Windows (linux/build.sh downloads them).
get_filename_component(TTT2_TOOLCHAIN "${CMAKE_CURRENT_LIST_DIR}/../data/toolchain" ABSOLUTE)
set(TTT2_MSVC "${TTT2_TOOLCHAIN}/msvc")

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

set(CMAKE_C_COMPILER "${TTT2_TOOLCHAIN}/llvm/bin/clang")
set(CMAKE_CXX_COMPILER "${TTT2_TOOLCHAIN}/llvm/bin/clang++")
set(CMAKE_RC_COMPILER "${TTT2_TOOLCHAIN}/llvm/bin/llvm-rc")
set(CMAKE_LINKER "${TTT2_TOOLCHAIN}/llvm/bin/lld-link")
set(CMAKE_AR "${TTT2_TOOLCHAIN}/llvm/bin/llvm-lib")
set(CMAKE_MT "${TTT2_TOOLCHAIN}/llvm/bin/llvm-mt")
set(CMAKE_C_COMPILER_TARGET x86_64-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET x86_64-pc-windows-msvc)

set(_sysroot "-Xmicrosoft-windows-sys-root \"${TTT2_MSVC}\" -Xmicrosoft-visualc-tools-version 14.44.17.14 -Xmicrosoft-windows-sdk-version 10.0.26100")
set(CMAKE_C_FLAGS_INIT "${_sysroot}")
set(CMAKE_CXX_FLAGS_INIT "${_sysroot}")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_sysroot} -fuse-ld=lld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_sysroot} -fuse-ld=lld")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
