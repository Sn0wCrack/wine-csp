#!/usr/bin/env bash
set -euo pipefail

WINE_VERSION="${WINE_VERSION:-}"
if [ -z "${WINE_VERSION}" ]; then
    echo "ERROR: WINE_VERSION must be set (e.g. 11.4)"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG_FILE="${REPO_ROOT}/configs/${WINE_VERSION}.cfg"
PATCH_DIR="${REPO_ROOT}/patches/${WINE_VERSION}"
BUILD_DIR="${HOME}/wine-csp-build"
WINE_TKG_REPO_DIR="${BUILD_DIR}/wine-tkg-git"
WINE_TKG_DIR="${WINE_TKG_REPO_DIR}/wine-tkg-git"

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}"
    exit 1
fi

if [ ! -d "${PATCH_DIR}" ]; then
    echo "ERROR: Patch directory not found: ${PATCH_DIR}"
    exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "=== Cloning wine-tkg-git ==="
git clone --depth=1 https://github.com/Frogging-Family/wine-tkg-git.git "${WINE_TKG_REPO_DIR}"

echo "=== Installing config ==="
cp "${CONFIG_FILE}" "${WINE_TKG_DIR}/customization.cfg"

echo "=== Installing user patches ==="
USERPATCHES_DIR="${WINE_TKG_DIR}/wine-tkg-userpatches"
mkdir -p "${USERPATCHES_DIR}"
for patch in "${PATCH_DIR}"/*.patch; do
    if [ -f "${patch}" ]; then
        name="$(basename "${patch}" .patch).mypatch"
        ln -sf "${patch}" "${USERPATCHES_DIR}/${name}"
        echo "  Linked: ${name}"
    fi
done

echo "=== Building Wine ${WINE_VERSION} ==="
cd "${WINE_TKG_DIR}"
./non-makepkg-build.sh

echo "=== Packaging ==="
NON_MAKEPKG_DIR="${WINE_TKG_DIR}/non-makepkg-builds"
if [ -d "${NON_MAKEPKG_DIR}" ]; then
    cd "${NON_MAKEPKG_DIR}"
    for builddir in wine-tkg-git-*; do
        if [ -d "${builddir}" ]; then
            arch="amd64"
            if echo "${builddir}" | grep -q "x86$"; then
                arch="x86"
            fi
            tarname="wine-csp-${WINE_VERSION}-${arch}.tar.xz"
            echo "  Creating ${tarname}..."
            tar -Jcf "${REPO_ROOT}/${tarname}" "${builddir}"
        fi
    done
    for tarball in *.tar.xz; do
        if [ -f "${tarball}" ]; then
            arch="amd64"
            if echo "${tarball}" | grep -q "x86"; then
                arch="x86"
            fi
            newname="wine-csp-${WINE_VERSION}-${arch}.tar.xz"
            cp "${tarball}" "${REPO_ROOT}/${newname}"
            echo "  Copied: ${newname}"
        fi
    done
fi

echo "=== Build complete ==="
ls -la "${REPO_ROOT}"/wine-csp-*.tar.xz 2>/dev/null || echo "No tarballs found in ${REPO_ROOT}"
