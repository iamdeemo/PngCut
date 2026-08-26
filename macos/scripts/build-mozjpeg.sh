#!/bin/bash

# Builds static MozJPEG-backed helper binaries for both macOS architectures.
set -euo pipefail

readonly VERSION="v4.1.5"
readonly REPOSITORY="https://github.com/mozilla/mozjpeg.git"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly CHECKOUT_DIRECTORY="${PROJECT_DIRECTORY}/.build/mozjpeg"
readonly LOCK_DIRECTORY="${PROJECT_DIRECTORY}/.build/mozjpeg-build.lock"
readonly RESOURCE_DIRECTORY="${PROJECT_DIRECTORY}/PngCut/Resources/mozjpeg"
readonly HELPER_SOURCE="${RESOURCE_DIRECTORY}/mozjpeg-helper.c"

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
        echo "Another MozJPEG build is already running (or left ${LOCK_DIRECTORY})." >&2
        exit 1
    fi
    trap 'rmdir "${LOCK_DIRECTORY}"' EXIT
    trap 'exit 1' HUP INT TERM
}

prepare_checkout() {
    if [[ -e "${CHECKOUT_DIRECTORY}" && ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        echo "${CHECKOUT_DIRECTORY} exists but is not a MozJPEG Git checkout." >&2
        exit 1
    fi
    if [[ ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        mkdir -p "$(dirname "${CHECKOUT_DIRECTORY}")"
        git clone --depth 1 --branch "${VERSION}" "${REPOSITORY}" "${CHECKOUT_DIRECTORY}"
    else
        require_clean_vendor_checkout
        git -C "${CHECKOUT_DIRECTORY}" fetch --depth 1 origin "refs/tags/${VERSION}:refs/tags/${VERSION}"
        git -C "${CHECKOUT_DIRECTORY}" checkout --detach "${VERSION}"
    fi
    local resolved_version
    resolved_version="$(git -C "${CHECKOUT_DIRECTORY}" describe --exact-match --tags HEAD 2>/dev/null || true)"
    if [[ "${resolved_version}" != "${VERSION}" ]]; then
        echo "Expected MozJPEG ${VERSION}, got ${resolved_version:-an untagged revision}." >&2
        exit 1
    fi
}

build_target() {
    local architecture="$1"
    local build_directory="${PROJECT_DIRECTORY}/.build/mozjpeg-${architecture}"
    cmake -S "${CHECKOUT_DIRECTORY}" -B "${build_directory}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_OSX_ARCHITECTURES="${architecture}" \
        -DENABLE_SHARED=FALSE \
        -DWITH_TURBOJPEG=FALSE
    # The helper links only MozJPEG's static libjpeg. Building just this target
    # avoids host libpng linkage in cjpeg, which is irrelevant to JPEG input.
    cmake --build "${build_directory}" --config Release --target jpeg-static
    xcrun --sdk macosx clang -arch "${architecture}" -O2 -Wall -Wextra -Werror \
        -I "${CHECKOUT_DIRECTORY}" -I "${build_directory}" "${HELPER_SOURCE}" "${build_directory}/libjpeg.a" \
        -o "${RESOURCE_DIRECTORY}/mozjpeg-helper-${architecture}"
    chmod 755 "${RESOURCE_DIRECTORY}/mozjpeg-helper-${architecture}"
}

require_tool git
require_tool cmake
require_tool xcrun
[[ -f "${HELPER_SOURCE}" ]] || { echo "Missing MozJPEG helper source: ${HELPER_SOURCE}" >&2; exit 1; }
acquire_build_lock
prepare_checkout
mkdir -p "${RESOURCE_DIRECTORY}"
build_target arm64
build_target x86_64
install -m 644 "${CHECKOUT_DIRECTORY}/LICENSE.md" "${RESOURCE_DIRECTORY}/LICENSE-mozjpeg"

echo "Built MozJPEG ${VERSION} helpers:"
file "${RESOURCE_DIRECTORY}/mozjpeg-helper-arm64" "${RESOURCE_DIRECTORY}/mozjpeg-helper-x86_64"
