#!/usr/bin/env bash
set -euxo pipefail

export WINE_VERSION="${WINE_VERSION:-}"
if [ -z "${WINE_VERSION}" ]; then
    echo "ERROR: WINE_VERSION must be set (e.g. 11.4)"
    exit 1
fi

mkdir -p "${XDG_CACHE_HOME:-${HOME}/.cache}"/ccache
mkdir -p "${HOME}"/.ccache

JOB_COUNT=$(($(getconf _NPROCESSORS_ONLN) + 2))
REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PATCH_DIR="${REPO_ROOT}/patches/${WINE_VERSION}"
BUILD_DIR="${HOME}/build_wine"
BUILD_NAME="${WINE_VERSION}"

export BOOTSTRAP_X64="${BOOTSTRAP_X64:-/opt/chroots/bionic64_chroot}"
export BOOTSTRAP_X32="${BOOTSTRAP_X32:-/opt/chroots/bionic32_chroot}"

if [ ! -d "${PATCH_DIR}" ]; then
    echo "ERROR: Patch directory not found: ${PATCH_DIR}"
    exit 1
fi

# Determine Wine source URL path (stable vs development)
if [ "$(echo "${WINE_VERSION}" | cut -d "." -f2 | cut -c1)" = "0" ]; then
    WINE_URL_VERSION="$(echo "${WINE_VERSION}" | cut -d "." -f 1).0"
else
    WINE_URL_VERSION="$(echo "${WINE_VERSION}" | cut --d "." -f 1).x"
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "=== Downloading Wine ${WINE_VERSION} ==="
wget -nv "https://dl.winehq.org/wine/source/${WINE_URL_VERSION}/wine-${WINE_VERSION}.tar.xz"
tar xf "wine-${WINE_VERSION}.tar.xz"
mv "wine-${WINE_VERSION}" wine

echo "=== Applying CSP patches ==="
for patch in "${PATCH_DIR}"/*.patch; do
    if [ -f "${patch}" ]; then
        echo "  Applying: $(basename "${patch}")"
        patch -d wine -Np1 < "${patch}"
    fi
done

cd wine || exit 1
echo "=== Preparing Wine source ==="
dlls/winevulkan/make_vulkan
tools/make_requests
tools/make_specfiles
autoreconf -f
cd "${BUILD_DIR}" || exit 1

if ! command -v bwrap 1>/dev/null; then
    echo "ERROR: bubblewrap is not installed!"
    exit 1
fi

if [ ! -d "${BOOTSTRAP_X64}" ] || [ ! -d "${BOOTSTRAP_X32}" ]; then
    echo "ERROR: Bootstraps not found at ${BOOTSTRAP_X64} and/or ${BOOTSTRAP_X32}"
    echo "Run create-ubuntu-bootstraps.sh first (as root)."
    exit 1
fi

build_with_bwrap () {
    if [ "${1}" = "32" ]; then
        BOOTSTRAP_PATH="${BOOTSTRAP_X32}"
    else
        BOOTSTRAP_PATH="${BOOTSTRAP_X64}"
    fi
    if [ "${1}" = "32" ] || [ "${1}" = "64" ]; then
        shift
    fi


    bwrap --ro-bind "${BOOTSTRAP_PATH}" / --dev /dev --ro-bind /sys /sys \
		  --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
		  --tmpfs /mnt --tmpfs /media --bind "${BUILD_DIR}" "${BUILD_DIR}" \
		  --bind-try "${${XDG_CACHE_HOME:-${HOME}/.cache}}"/ccache "${${XDG_CACHE_HOME:-${HOME}/.cache}}"/ccache \
		  --bind-try "${HOME}"/.ccache "${HOME}"/.ccache \
          --setenv PATH "/opt/mingw/x86_64/bin:/opt/mingw/i686/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin" \
		  "$@"
}

BWRAP64="build_with_bwrap 64"
BWRAP32="build_with_bwrap 32"

export WINE_BUILD_OPTIONS="--without-oss --disable-winemenubuilder --disable-tests"

export CROSSCC_X64="x86_64-w64-mingw32-gcc"
export CROSSCXX_X64="x86_64-w64-mingw32-g++"
export CROSSCC_X32="i686-w64-mingw32-gcc"
export CROSSCXX_X32="i686-w64-mingw32-g++"

export CFLAGS_X64="-march=x86-64 -msse3 -mfpmath=sse -O3"
export CFLAGS_X32="-march=i686 -msse2 -mfpmath=sse -O3"
export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"

echo "=== Building Wine 64-bit ==="
export CROSSCC="${CROSSCC_X64}"
export CROSSCXX="${CROSSCXX_X64}"
export CFLAGS="${CFLAGS_X64}"
export CXXFLAGS="${CFLAGS_X64}"

mkdir "${BUILD_DIR}"/build64
cd "${BUILD_DIR}"/build64 || exit
${BWRAP64} "${BUILD_DIR}"/wine/configure --enable-win64 ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}"/wine-"${BUILD_NAME}"-amd64
${BWRAP64} make -j"${JOB_COUNT}" install

echo "=== Building 32-bit tools ==="
export CROSSCC="${CROSSCC_X32}"
export CROSSCXX="${CROSSCXX_X32}"
export CFLAGS="${CFLAGS_X32}"
export CXXFLAGS="${CFLAGS_X32}"

mkdir "${BUILD_DIR}"/build32-tools
cd "${BUILD_DIR}"/build32-tools || exit
PKG_CONFIG_LIBDIR="/usr/local/lib/pkgconfig:/usr/local/lib/i386-linux-gnu/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
    ${BWRAP32} "${BUILD_DIR}"/wine/configure ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}"/wine-"${BUILD_NAME}"-x86
${BWRAP32} make -j"${JOB_COUNT}" install

echo "=== Building 32-bit Wine (targeting 64-bit) ==="
export CFLAGS="${CFLAGS_X64}"
export CXXFLAGS="${CFLAGS_X64}"

mkdir "${BUILD_DIR}"/build32
cd "${BUILD_DIR}"/build32 || exit
PKG_CONFIG_LIBDIR="/usr/local/lib/pkgconfig:/usr/local/lib/i386-linux-gnu/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
    ${BWRAP32} "${BUILD_DIR}"/wine/configure --with-wine64="${BUILD_DIR}"/build64 --with-wine-tools="${BUILD_DIR}"/build32-tools \
    ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}"/wine-"${BUILD_NAME}"-amd64
${BWRAP32} make -j"${JOB_COUNT}" install

echo "=== Packaging ==="
cd "${BUILD_DIR}" || exit
export XZ_OPT="-9 -T 0"

for build in wine-"${BUILD_NAME}"-amd64 wine-"${BUILD_NAME}"-x86; do
    if [ -d "${build}" ]; then
        tarname="wine-csp-${WINE_VERSION}-${build##*-}.tar.xz"
        echo "  Creating ${tarname}..."
        tar -Jcf "${REPO_ROOT}/${tarname}" "${build}"
    fi
done

rm -rf "${BUILD_DIR}"

echo "=== Build complete ==="
ls -la "${REPO_ROOT}"/wine-csp-*.tar.xz
