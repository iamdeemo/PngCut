#!/bin/bash

# Builds the pinned Gifsicle release for each macOS architecture. Autotools
# work happens in disposable build copies so the pinned vendor checkout stays
# clean and can be reused safely.
set -euo pipefail

readonly REPOSITORY="https://github.com/kohler/gifsicle.git"
readonly VERSION="v1.96"
readonly EXPECTED_REVISION="a08e0f6686d467bb8b9e4715b1f1835f12984fb0"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly CHECKOUT_DIRECTORY="${PROJECT_DIRECTORY}/.build/gifsicle"
readonly LOCK_DIRECTORY="${PROJECT_DIRECTORY}/.build/gifsicle-build.lock"
readonly RESOURCE_DIRECTORY="${PROJECT_DIRECTORY}/PngCut/Resources/gifsicle"

require_tool() {
    command -v "$1" >/dev/null || { echo "Missing required build tool: $1" >&2; exit 1; }
}

require_clean_vendor_checkout() {
    if [[ -n "$(git -C "${CHECKOUT_DIRECTORY}" status --porcelain)" ]]; then
        echo "Refusing to replace local changes in ${CHECKOUT_DIRECTORY}." >&2
        exit 1
    fi
}

acquire_build_lock() {
    mkdir -p "$(dirname "${LOCK_DIRECTORY}")"
    if ! mkdir "${LOCK_DIRECTORY}" 2>/dev/null; then
        echo "Another Gifsicle build is already running (or left ${LOCK_DIRECTORY})." >&2
        exit 1
    fi
    trap 'rmdir "${LOCK_DIRECTORY}"' EXIT
    trap 'exit 1' HUP INT TERM
}

prepare_checkout() {
    if [[ -e "${CHECKOUT_DIRECTORY}" && ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        echo "${CHECKOUT_DIRECTORY} exists but is not a Gifsicle Git checkout." >&2
        exit 1
    fi
    if [[ ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        mkdir -p "$(dirname "${CHECKOUT_DIRECTORY}")"
        git clone --depth 1 --no-checkout "${REPOSITORY}" "${CHECKOUT_DIRECTORY}"
    else
        require_clean_vendor_checkout
    fi

    git -C "${CHECKOUT_DIRECTORY}" fetch --depth 1 origin "+refs/tags/${VERSION}:refs/tags/${VERSION}"
    git -C "${CHECKOUT_DIRECTORY}" cat-file -e "${EXPECTED_REVISION}^{commit}" || {
        echo "Gifsicle ${VERSION} did not provide expected revision ${EXPECTED_REVISION}." >&2
        exit 1
    }
    git -C "${CHECKOUT_DIRECTORY}" checkout --detach "${EXPECTED_REVISION}"

    local resolved_version
    local resolved_revision
    local tag_revision
    resolved_version="$(git -C "${CHECKOUT_DIRECTORY}" describe --exact-match --tags HEAD 2>/dev/null || true)"
    if [[ "${resolved_version}" != "${VERSION}" ]]; then
        echo "Expected Gifsicle ${VERSION}, got ${resolved_version:-an untagged revision}." >&2
        exit 1
    fi
    resolved_revision="$(git -C "${CHECKOUT_DIRECTORY}" rev-parse HEAD)"
    tag_revision="$(git -C "${CHECKOUT_DIRECTORY}" rev-parse "refs/tags/${VERSION}^{}")"
    if [[ "${resolved_revision}" != "${EXPECTED_REVISION}" || "${tag_revision}" != "${EXPECTED_REVISION}" ]]; then
        echo "Gifsicle ${VERSION} did not resolve to ${EXPECTED_REVISION}." >&2
        exit 1
    fi
}

prepare_build_tree() {
    local architecture="$1"
    local build_directory="${PROJECT_DIRECTORY}/.build/gifsicle-${architecture}"
    rm -rf "${build_directory}"
    mkdir -p "${build_directory}"
    git -C "${CHECKOUT_DIRECTORY}" archive HEAD | tar -x -C "${build_directory}"
    printf '%s\n' "${build_directory}"
}

build_target() {
    local architecture="$1"
    local build_directory
    build_directory="$(prepare_build_tree "${architecture}")"
    (
        cd "${build_directory}"
        autoreconf -fi
        export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
        export MACOSX_DEPLOYMENT_TARGET=13.0
        CC="$(xcrun --sdk macosx --find clang) -arch ${architecture}" \
            ./configure --disable-gifview --disable-gifdiff
        make gifsicle
    )
    install -m 755 "${build_directory}/src/gifsicle" "${RESOURCE_DIRECTORY}/gifsicle-${architecture}"
}

validate_architecture() {
    local architecture="$1"
    validate_thin_macos_architecture "${architecture}" "${RESOURCE_DIRECTORY}/gifsicle-${architecture}"
    validate_macos_minos_at_most 13.0 "${RESOURCE_DIRECTORY}/gifsicle-${architecture}"
}

require_tool git
require_tool autoreconf
require_tool make
require_tool xcrun
require_tool file
require_tool lipo
require_tool otool
# shellcheck source=/dev/null
source "${SCRIPT_DIRECTORY}/macos-binary-validation.sh"
acquire_build_lock
prepare_checkout
mkdir -p "${RESOURCE_DIRECTORY}"
build_target arm64
build_target x86_64
install -m 644 "${CHECKOUT_DIRECTORY}/COPYING" "${RESOURCE_DIRECTORY}/LICENSE-gifsicle"
validate_architecture arm64
validate_architecture x86_64

echo "Built Gifsicle ${VERSION}:"
file "${RESOURCE_DIRECTORY}/gifsicle-arm64" "${RESOURCE_DIRECTORY}/gifsicle-x86_64"
