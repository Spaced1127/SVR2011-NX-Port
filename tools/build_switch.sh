#!/usr/bin/env bash
# SVR2011-NX build helper (WSL2/Linux).
#
#   tools/build_switch.sh --host      build the host code generator
#   tools/build_switch.sh --codegen   build the host tool and generate the game C++
#   tools/build_switch.sh --nro       generate (if needed) and build the NRO
#   tools/build_switch.sh --switch    build the host tool, generate and build the NRO
#
# Environment:
#   DEVKITPRO=/opt/devkitpro
#   PORTLIBS_PREFIX=$DEVKITPRO/portlibs/switch
#   REXGLUE_SWITCH_NVK_SDK=/path/to/nvk/extracted
#   PLUME_DIR=$REPO_ROOT/third_party/plume
#   SVR2011_XEX=/path/to/the/user's/default.xex (copied to port/assets/default.xex)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
PORTLIBS_PREFIX="${PORTLIBS_PREFIX:-${DEVKITPRO}/portlibs/switch}"
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
  return 1
}

# The generated C++ is a derivative of the user's default.xex. Regenerating it
# on every build is slow, so record the XEX and manifest hashes and skip when
# they are unchanged. A different XEX or manifest regenerates it.
generate() {
  local xex="${SVR2011_XEX:-${REPO_ROOT}/port/assets/default.xex}"
  local dest="${REPO_ROOT}/port/assets/default.xex"
  if [[ ! -f "${xex}" ]]; then
    echo "error: default.xex not found: ${xex}" >&2
    echo "       put your own game executable at port/assets/default.xex" >&2
    exit 1
  fi
  if [[ "$(cd "$(dirname "${xex}")" && pwd)/$(basename "${xex}")" != "${dest}" ]]; then
    echo "== using game executable: ${xex}"
    cp -f "${xex}" "${dest}"
  fi

  local stamp="${REPO_ROOT}/port/generated/.xex-sha256"
  local manifest="${REPO_ROOT}/port/svr2011_manifest.toml"
  local hash
  hash="$(sha256sum "${dest}" "${manifest}" | sha256sum | cut -d' ' -f1)"
  if [[ -f "${stamp}" && "$(cat "${stamp}")" == "${hash}" && -n "$(ls -A "${REPO_ROOT}/port/generated/default" 2>/dev/null)" ]]; then
    echo "== codegen: already generated for this default.xex"
    return 0
  fi

  echo "== codegen"
  (
    cd "${REPO_ROOT}/port"
    "$(rexglue_bin)" codegen svr2011_manifest.toml
  )
  mkdir -p "${REPO_ROOT}/port/generated"
  printf '%s\n' "${hash}" > "${stamp}"
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
    -DREXGLUE_ENABLE_TRACY=OFF \
    -DPLUME_PLATFORM_SWITCH=ON \
    -DPLUME_BUILD_EXAMPLES=OFF \
    -DPLUME_DEKO3D=ON \
    -DPLUME_SWITCH_UAM_DIR="${REPO_ROOT}/third_party/uam" \
    -DPLUME_SWITCH_DEVKITPRO="${DEVKITPRO}" \
    -DPLUME_SWITCH_NVK_LIBRARY="${NVK_SDK}/lib/libvulkan.a" \
    -DCMAKE_PREFIX_PATH="${PORTLIBS_PREFIX}"
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
  --nro)
    if ! rexglue_bin >/dev/null; then
      build_host
    fi
    generate
    build_switch
    ;;
  --switch)
    build_host
    generate
    build_switch
    ;;
  *)
    echo "usage: $0 [--host|--codegen|--nro|--switch]" >&2
    exit 2
    ;;
esac

echo "done: ${MODE}"
