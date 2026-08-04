#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bridge_root="${repo_root}/WineIntegration/bridge"
build_root="${bridge_root}/build"
wine_executable=${YAAGL_WINE_EXECUTABLE:-"${HOME}/Library/Application Support/Yaagl OS/wine/bin/wine"}
selftest_prefix=${BETTERGI_WINE_SELFTEST_PREFIX:-"${HOME}/Library/Caches/betterGI-mac/wine-bridge-selftest-prefix"}

if [[ ! -x ${wine_executable} ]]; then
  printf 'YAAgl Wine executable not found: %s\n' "${wine_executable}" >&2
  exit 2
fi

cmake_arguments=(
  -S "${bridge_root}"
  -B "${build_root}"
  -DCMAKE_BUILD_TYPE=Release
)
expected_toolchain=${bridge_root}/toolchains/mingw-x86_64.cmake
if [[ -f "${build_root}/CMakeCache.txt" ]] &&
   ! grep -Fq "CMAKE_TOOLCHAIN_FILE:FILEPATH=${expected_toolchain}" "${build_root}/CMakeCache.txt"; then
  printf 'Removing bridge build directory configured for a different toolchain: %s\n' "${build_root}" >&2
  rm -rf -- "${build_root}"
fi
cmake_arguments+=(
  -DCMAKE_TOOLCHAIN_FILE=toolchains/mingw-x86_64.cmake
)
cmake "${cmake_arguments[@]}"
cmake --build "${build_root}"

bridge_executable="${build_root}/BetterGIWineInputBridge.exe"
file "${bridge_executable}" | grep -q 'PE32+ executable.*x86-64'

mkdir -p "${selftest_prefix}"
WINEPREFIX="${selftest_prefix}" WINEDEBUG=-all \
  "${wine_executable}" "${bridge_executable}" --self-test

python3 \
  "${bridge_root}/tests/protocol_test.py" \
  "${wine_executable}" \
  "${selftest_prefix}" \
  "${bridge_executable}"
