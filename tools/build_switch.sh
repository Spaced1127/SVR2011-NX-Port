#!/usr/bin/env bash
# SVR2011-NX build helper (WSL2/Linux).
#
#   tools/build_switch.sh --host      build the host code generator
#   tools/build_switch.sh --codegen   build the host tool and generate the game C++
#   tools/build_switch.sh --switch    build the NRO (requires the Switch target)
#
# Environment:
#   DEVKITPRO=/opt/devkitpro
#   REXGLUE_SWITCH_NVK_SDK=/path/to/mesa-sdk/opt/devkitpro/portlibs/switch
#   PLUME_DIR=$REPO_ROOT/third_party/plume
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
REXSDK_DIR="${REXSDK_DIR:-${REPO_ROOT}/sdk}"
PLUME_DIR="${PLUME_DIR:-${REPO_ROOT}/third_party/plume}"
NVK_SDK="${REXGLUE_SWITCH_NVK_SDK:-}"
JOBS="${JOBS:-$(nproc)}"
MODE="${1:---switch}"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: missing $1" >&2; exit 1; }
}

need git
need cmake
need ninja
need python3

ensure_thirdparty() {
  if [[ ! -d "${REXSDK_DIR}/thirdparty/fmt" ]]; then
    echo "== fetching ReXGlue third-party sources"
    python3 "${REPO_ROOT}/tools/fetch_thirdparty.py"
  fi
}

build_host() {
  ensure_thirdparty
  echo "== host code generator"
  cmake -S "${REXSDK_DIR}" -B "${REPO_ROOT}/out/host" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS="-march=x86-64-v2" \
    -DCMAKE_CXX_FLAGS="-march=x86-64-v2" \
    -DREXGLUE_USE_VULKAN=ON
  cmake --build "${REPO_ROOT}/out/host" --target rexglue -j "${JOBS}"
}

rexglue_bin() {
  local candidate
  for candidate in \
    "${REPO_ROOT}/sdk/out/linux-amd64/rexglue" \
    "${REPO_ROOT}/sdk/out/win-amd64/rexglue.exe" \
    "${REPO_ROOT}/out/host/rexglue" \
    "${REPO_ROOT}/out/host/rexglue.exe"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  echo "error: rexglue not found; run tools/build_switch.sh --host first" >&2
  exit 1
}

generate() {
  if [[ ! -f "${REPO_ROOT}/port/assets/default.xex" ]]; then
    echo "error: put your own default.xex in port/assets/default.xex" >&2
    exit 1
  fi
  echo "== codegen"
  (
    cd "${REPO_ROOT}/port"
    "$(rexglue_bin)" codegen svr2011_manifest.toml
  )
}

build_switch() {
  if [[ ! -f "${REPO_ROOT}/port/CMakeLists.txt" ]]; then
    echo "error: port/CMakeLists.txt missing" >&2
    exit 1
  fi
  if ! grep -q 'REXGLUE_PLATFORM_SWITCH' "${REPO_ROOT}/port/CMakeLists.txt"; then
    echo "error: the Switch target is not wired into port/CMakeLists.txt yet." >&2
    echo "See docs/PORTING_PLAN.md phase 3." >&2
    exit 1
  fi
  if [[ -z "${NVK_SDK}" || ! -f "${NVK_SDK}/lib/libvulkan.a" ]]; then
    echo "error: set REXGLUE_SWITCH_NVK_SDK to a mesa-switch portlibs/switch folder" >&2
    echo "       containing lib/libvulkan.a" >&2
    exit 1
  fi
  ensure_thirdparty
  echo "== Switch configure"
  cmake -S "${REPO_ROOT}/port" -B "${REPO_ROOT}/out/switch" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${DEVKITPRO}/cmake/Switch.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DREXSDK_DIR="${REXSDK_DIR}" \
    -DPLUME_DIR="${PLUME_DIR}" \
    -DREXGLUE_SWITCH_NVK_SDK="${NVK_SDK}" \
    -DREXGLUE_PLATFORM_SWITCH=ON \
    -DPLUME_PLATFORM_SWITCH=ON \
    -DPLUME_BUILD_EXAMPLES=OFF \
    -DPLUME_SWITCH_DEVKITPRO="${DEVKITPRO}" \
    -DPLUME_SWITCH_NVK_LIBRARY="${NVK_SDK}/lib/libvulkan.a" \
    -DCMAKE_PREFIX_PATH="${DEVKITPRO}/portlibs/switch"
  cmake --build "${REPO_ROOT}/out/switch" -j "${JOBS}"
}

case "${MODE}" in
  --host)
    build_host
    ;;
  --codegen)
    build_host
    generate
    ;;
  --switch)
    build_host
    generate
    build_switch
    ;;
  *)
    echo "usage: $0 [--host|--codegen|--switch]" >&2
    exit 2
    ;;
esac

echo "done: ${MODE}"
