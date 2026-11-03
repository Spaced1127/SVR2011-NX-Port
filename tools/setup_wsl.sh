#!/usr/bin/env bash
# Prepare a WSL2/Linux machine for the SVR2011-NX build.
#
#   sudo tools/setup_wsl.sh --system   apt packages + devkitPro
#   tools/setup_wsl.sh --user          portlibs + NVK + host code generator
#   tools/setup_wsl.sh --check         report what is missing
#
# The release builder (tools/build_release.ps1) runs both modes. The build
# itself never needs root: portlibs and NVK go to a user-writable prefix.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
PORTLIBS_PREFIX="${PORTLIBS_PREFIX:-${DEVKITPRO}/portlibs/switch}"
NVK_DIR="${NVK_DIR:-${REPO_ROOT}/third_party/nvk}"
JOBS="${JOBS:-$(nproc)}"
MODE="${1:---check}"

APT_PACKAGES=(
  build-essential cmake ninja-build clang lld git python3
  pkg-config curl ca-certificates xz-utils
  libexpat1-dev zlib1g-dev libzstd-dev
  libx11-xcb-dev libxcb1-dev libxcb-icccm4-dev libxcb-image0-dev
  libxcb-keysyms1-dev libxcb-randr0-dev libxcb-render-util0-dev
  libxcb-shape0-dev libxcb-xfixes0-dev libxcb-xinerama0-dev
  libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev libwayland-dev
)

have_devkitpro() {
  [[ -x "${DEVKITPRO}/devkitA64/bin/aarch64-none-elf-g++" ]] &&
    [[ -f "${DEVKITPRO}/cmake/Switch.cmake" ]] &&
    [[ -d "${DEVKITPRO}/libnx/include" ]] &&
    [[ -x "${DEVKITPRO}/tools/bin/elf2nro" ]]
}

have_rexglue() {
  local candidate
  for candidate in "${REPO_ROOT}"/sdk/out/*/rexglue "${REPO_ROOT}"/out/host/rexglue; do
    [[ -x "${candidate}" ]] && return 0
  done
  return 1
}

check_all() {
  local missing=0
  for tool in git cmake ninja clang clang++ python3 make gcc g++ pkg-config; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "missing tool: ${tool}"
      missing=1
    fi
  done
  if ! have_devkitpro; then
    echo "missing devkitPro Switch toolchain at ${DEVKITPRO}"
    echo "  install it from https://devkitpro.org/wiki/Getting_Started"
    missing=1
  fi
  for lib in libz.a libexpat.a libzstd.a; do
    [[ -f "${PORTLIBS_PREFIX}/lib/${lib}" ]] || { echo "missing portlib: ${PORTLIBS_PREFIX}/lib/${lib}"; missing=1; }
  done
  [[ -f "${NVK_DIR}/extracted/lib/libvulkan.a" ]] ||
    { echo "missing NVK: ${NVK_DIR}/extracted/lib/libvulkan.a"; missing=1; }
  if ! have_rexglue; then
    echo "missing host code generator (rexglue)"
    missing=1
  fi
  if [[ "${missing}" -eq 0 ]]; then
    echo "all build prerequisites are present"
    return 0
  fi
  return 1
}

install_system() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: --system must run as root (use: sudo tools/setup_wsl.sh --system)" >&2
    exit 1
  fi

  echo "== apt packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq "${APT_PACKAGES[@]}"

  if have_devkitpro; then
    echo "== devkitPro already installed at ${DEVKITPRO}"
    return 0
  fi

  echo "== devkitPro"
  echo "devkitPro's Switch toolchain was not found at ${DEVKITPRO}."
  echo "Trying the official installer..."
  local installer=/tmp/install-devkitpro-pacman
  if curl -fsSL https://apt.devkitpro.org/install-devkitpro-pacman -o "${installer}"; then
    bash "${installer}" || true
  else
    echo "  the installer could not be downloaded (the site may be blocked)." >&2
  fi

  if command -v dkp-pacman >/dev/null 2>&1; then
    dkp-pacman -S --noconfirm --needed switch-dev switch-tools || true
  fi

  if have_devkitpro; then
    echo "== devkitPro installed at ${DEVKITPRO}"
    return 0
  fi

  cat >&2 <<EOF

error: devkitPro is still missing.

Install it from https://devkitpro.org/wiki/Getting_Started, then rerun:

    sudo tools/setup_wsl.sh --system

The Switch packages needed are devkitA64, libnx and switch-tools
(elf2nro/nacptool), normally the "switch-dev" package group.
EOF
  exit 1
}

install_user() {
  cd "${REPO_ROOT}"
  if ! have_devkitpro; then
    echo "error: devkitPro missing at ${DEVKITPRO}; run: sudo tools/setup_wsl.sh --system" >&2
    exit 1
  fi

  mkdir -p "${PORTLIBS_PREFIX}/lib" "${PORTLIBS_PREFIX}/include"
  if [[ ! -f "${PORTLIBS_PREFIX}/lib/libz.a" ||
        ! -f "${PORTLIBS_PREFIX}/lib/libexpat.a" ||
        ! -f "${PORTLIBS_PREFIX}/lib/libzstd.a" ]]; then
    echo "== portlibs (zlib, Expat, Zstandard)"
    DEVKITPRO="${DEVKITPRO}" PORTLIBS_PREFIX="${PORTLIBS_PREFIX}" JOBS="${JOBS}" \
      bash tools/build_portlibs.sh
  else
    echo "== portlibs already built in ${PORTLIBS_PREFIX}"
  fi

  if [[ ! -f "${NVK_DIR}/extracted/lib/libvulkan.a" ]]; then
    echo "== NVK"
    python3 tools/fetch_nvk.py --dest "${NVK_DIR}/extracted"
  else
    echo "== NVK already present in ${NVK_DIR}/extracted"
  fi

  if ! have_rexglue; then
    echo "== host code generator"
    DEVKITPRO="${DEVKITPRO}" PORTLIBS_PREFIX="${PORTLIBS_PREFIX}" JOBS="${JOBS}" \
      bash tools/build_switch.sh --host
  else
    echo "== host code generator already built"
  fi

  echo
  echo "ready:"
  echo "  DEVKITPRO=${DEVKITPRO}"
  echo "  PORTLIBS_PREFIX=${PORTLIBS_PREFIX}"
  echo "  NVK_DIR=${NVK_DIR}"
}

case "${MODE}" in
  --system)
    install_system
    ;;
  --user)
    install_user
    ;;
  --check)
    check_all
    ;;
  *)
    echo "usage: $0 [--system|--user|--check]" >&2
    exit 2
    ;;
esac
