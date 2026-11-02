#!/usr/bin/env bash
# Build the small third-party libraries NVK needs for devkitA64:
# zlib, Expat and Zstandard.
#
#   sudo tools/build_portlibs.sh
#
# Defaults to $DEVKITPRO/portlibs/switch. Set PORTLIBS_PREFIX to install
# somewhere else (then pass CMAKE_PREFIX_PATH to the CMake configure).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
CROSS="${DEVKITPRO}/devkitA64/bin/aarch64-none-elf-"
PREFIX="${PORTLIBS_PREFIX:-${DEVKITPRO}/portlibs/switch}"
WORK="${PORTLIBS_BUILD_DIR:-${REPO_ROOT}/out/portlibs-src}"
JOBS="${JOBS:-$(nproc)}"

ZLIB_VERSION="v1.3.1"
EXPAT_VERSION="2.7.1"
ZSTD_VERSION="v1.5.7"

for tool in "${CROSS}gcc" "${CROSS}ar" "${CROSS}ranlib"; do
  if [[ ! -x "${tool}" ]]; then
    echo "error: missing ${tool}" >&2
    echo "Set DEVKITPRO to your devkitPro installation." >&2
    exit 1
  fi
done

mkdir -p "${WORK}" "${PREFIX}/lib" "${PREFIX}/include"

echo "== zlib ${ZLIB_VERSION}"
if [[ ! -f "${PREFIX}/lib/libz.a" ]]; then
  rm -rf "${WORK}/zlib"
  git clone --depth 1 --branch "${ZLIB_VERSION}" https://github.com/madler/zlib.git "${WORK}/zlib"
  (
    cd "${WORK}/zlib"
    CHOST=aarch64-none-elf \
    CC="${CROSS}gcc" AR="${CROSS}ar" RANLIB="${CROSS}ranlib" \
    CFLAGS="-O2 -fPIC" \
    ./configure --static --prefix="${PREFIX}"
    make -j"${JOBS}"
    make install
  )
else
  echo "already installed: ${PREFIX}/lib/libz.a"
fi

echo "== Expat ${EXPAT_VERSION}"
if [[ ! -f "${PREFIX}/lib/libexpat.a" ]]; then
  rm -rf "${WORK}/expat-${EXPAT_VERSION}"
  curl -fsSL "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}/expat-${EXPAT_VERSION}.tar.gz" \
    | tar -xz -C "${WORK}"
  (
    cd "${WORK}/expat-${EXPAT_VERSION}"
    ./configure \
      --host=aarch64-none-elf \
      --build="$(gcc -dumpmachine)" \
      --prefix="${PREFIX}" \
      --disable-shared \
      --without-xmlwf \
      --without-docbook \
      --without-examples \
      --without-tests
    make -j"${JOBS}"
    make install
  )
else
  echo "already installed: ${PREFIX}/lib/libexpat.a"
fi

echo "== Zstandard ${ZSTD_VERSION}"
if [[ ! -f "${PREFIX}/lib/libzstd.a" ]]; then
  rm -rf "${WORK}/zstd"
  git clone --depth 1 --branch "${ZSTD_VERSION}" https://github.com/facebook/zstd.git "${WORK}/zstd"
  (
    cd "${WORK}/zstd"
    make -C lib -j"${JOBS}" libzstd.a \
      CC="${CROSS}gcc" AR="${CROSS}ar" RANLIB="${CROSS}ranlib" \
      CFLAGS="-O2 -fPIC"
    cp lib/libzstd.a "${PREFIX}/lib/"
    cp lib/zstd.h lib/zstd_errors.h lib/zdict.h "${PREFIX}/include/"
  )
else
  echo "already installed: ${PREFIX}/lib/libzstd.a"
fi

echo
echo "done: ${PREFIX}"
ls -l "${PREFIX}/lib" | sed -n '1,20p'
