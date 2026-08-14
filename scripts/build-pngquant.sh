#!/bin/bash

# Builds the exact pngquant revision bundled by FFPNG without relying on a
# globally installed pngquant.
set -euo pipefail

readonly VERSION="3.0.3"
readonly REPOSITORY="https://github.com/kornelski/pngquant.git"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly CHECKOUT_DIRECTORY="${PROJECT_DIRECTORY}/.build/pngquant"
readonly LOCK_DIRECTORY="${PROJECT_DIRECTORY}/.build/pngquant-build.lock"
readonly RESOURCE_DIRECTORY="${PROJECT_DIRECTORY}/FFPNG/Resources/pngquant"
readonly ARM_TARGET="aarch64-apple-darwin"
readonly INTEL_TARGET="x86_64-apple-darwin"

require_tool() {
    command -v "$1" >/dev/null || { echo "Missing required build tool: $1" >&2; exit 1; }
}

require_clean_vendor_checkout() {
    # Cargo creates this untracked resolver lock because pngquant 3.0.3 did
    # not ship one. It is a build by-product, not a vendor-source edit.
    local dirty
    dirty="$(git -C "${CHECKOUT_DIRECTORY}" status --porcelain | grep -v '^?? Cargo.lock$' || true)"
    if [[ -n "${dirty}" ]]; then
        echo "Refusing to replace local changes in ${CHECKOUT_DIRECTORY}." >&2
        exit 1
    fi
}

acquire_build_lock() {
    mkdir -p "$(dirname "${LOCK_DIRECTORY}")"
    if ! mkdir "${LOCK_DIRECTORY}" 2>/dev/null; then
        echo "Another pngquant build is already running (or left ${LOCK_DIRECTORY})." >&2
        exit 1
    fi
    trap 'rmdir "${LOCK_DIRECTORY}"' EXIT
    trap 'exit 1' HUP INT TERM
}

prepare_checkout() {
    if [[ -e "${CHECKOUT_DIRECTORY}" && ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        echo "${CHECKOUT_DIRECTORY} exists but is not a pngquant Git checkout." >&2
        exit 1
    fi
    if [[ ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        mkdir -p "$(dirname "${CHECKOUT_DIRECTORY}")"
        git clone --depth 1 --branch "${VERSION}" --recurse-submodules "${REPOSITORY}" "${CHECKOUT_DIRECTORY}"
    else
        require_clean_vendor_checkout
        git -C "${CHECKOUT_DIRECTORY}" fetch --depth 1 origin "refs/tags/${VERSION}:refs/tags/${VERSION}"
        git -C "${CHECKOUT_DIRECTORY}" checkout --detach "${VERSION}"
    fi
    local resolved_version
    resolved_version="$(git -C "${CHECKOUT_DIRECTORY}" describe --exact-match --tags HEAD 2>/dev/null || true)"
    if [[ "${resolved_version}" != "${VERSION}" ]]; then
        echo "Expected pngquant ${VERSION}, got ${resolved_version:-an untagged revision}." >&2
        exit 1
    fi
    git -C "${CHECKOUT_DIRECTORY}" submodule update --init --recursive
}

build_target() {
    local target="$1"
    rustup target add "${target}"
    cargo build --manifest-path "${CHECKOUT_DIRECTORY}/Cargo.toml" --release --target "${target}"
    install -m 755 "${CHECKOUT_DIRECTORY}/target/${target}/release/pngquant" "${RESOURCE_DIRECTORY}/pngquant-${2}"
}

require_tool git
require_tool cargo
require_tool rustup
acquire_build_lock
prepare_checkout
mkdir -p "${RESOURCE_DIRECTORY}"
build_target "${ARM_TARGET}" "arm64"
build_target "${INTEL_TARGET}" "x86_64"
install -m 644 "${CHECKOUT_DIRECTORY}/COPYRIGHT" "${RESOURCE_DIRECTORY}/LICENSE-pngquant"

echo "Built pngquant ${VERSION}:"
file "${RESOURCE_DIRECTORY}/pngquant-arm64" "${RESOURCE_DIRECTORY}/pngquant-x86_64"
