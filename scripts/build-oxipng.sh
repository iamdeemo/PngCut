#!/bin/bash

# Builds the exact oxipng version bundled by FFPNG. The checkout is kept under
# .build so repeatable builds do not depend on a globally installed oxipng.
set -euo pipefail

readonly VERSION="v10.2.0"
readonly REPOSITORY="https://github.com/oxipng/oxipng.git"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly CHECKOUT_DIRECTORY="${PROJECT_DIRECTORY}/.build/oxipng"
readonly LOCK_DIRECTORY="${PROJECT_DIRECTORY}/.build/oxipng-build.lock"
readonly RESOURCE_DIRECTORY="${PROJECT_DIRECTORY}/FFPNG/Resources/oxipng"
readonly ARM_TARGET="aarch64-apple-darwin"
readonly INTEL_TARGET="x86_64-apple-darwin"

require_clean_checkout() {
    if [[ -n "$(git -C "${CHECKOUT_DIRECTORY}" status --porcelain)" ]]; then
        echo "Refusing to replace local changes in ${CHECKOUT_DIRECTORY}." >&2
        exit 1
    fi
}

acquire_build_lock() {
    mkdir -p "$(dirname "${LOCK_DIRECTORY}")"
    if ! mkdir "${LOCK_DIRECTORY}" 2>/dev/null; then
        echo "Another oxipng build is already running (or left ${LOCK_DIRECTORY})." >&2
        exit 1
    fi
    trap 'rmdir "${LOCK_DIRECTORY}"' EXIT
    trap 'exit 1' HUP INT TERM
}

prepare_checkout() {
    if [[ -e "${CHECKOUT_DIRECTORY}" && ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        echo "${CHECKOUT_DIRECTORY} exists but is not an oxipng Git checkout." >&2
        exit 1
    fi

    if [[ ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        mkdir -p "$(dirname "${CHECKOUT_DIRECTORY}")"
        git clone --depth 1 --branch "${VERSION}" "${REPOSITORY}" "${CHECKOUT_DIRECTORY}"
    else
        require_clean_checkout
        git -C "${CHECKOUT_DIRECTORY}" fetch --depth 1 origin "refs/tags/${VERSION}:refs/tags/${VERSION}"
        git -C "${CHECKOUT_DIRECTORY}" checkout --detach "${VERSION}"
    fi

    local resolved_version
    resolved_version="$(git -C "${CHECKOUT_DIRECTORY}" describe --exact-match --tags HEAD 2>/dev/null || true)"
    if [[ "${resolved_version}" != "${VERSION}" ]]; then
        echo "Expected oxipng ${VERSION}, got ${resolved_version:-an untagged revision}." >&2
        exit 1
    fi
}

build_target() {
    local target="$1"
    rustup target add "${target}"
    cargo build \
        --manifest-path "${CHECKOUT_DIRECTORY}/Cargo.toml" \
        --release \
        --target "${target}"
}

copy_binary() {
    local target="$1"
    local destination="$2"
    install -m 755 "${CHECKOUT_DIRECTORY}/target/${target}/release/oxipng" "${RESOURCE_DIRECTORY}/${destination}"
}

acquire_build_lock
prepare_checkout
build_target "${ARM_TARGET}"
build_target "${INTEL_TARGET}"

mkdir -p "${RESOURCE_DIRECTORY}"
copy_binary "${ARM_TARGET}" "oxipng-arm64"
copy_binary "${INTEL_TARGET}" "oxipng-x86_64"
install -m 644 "${CHECKOUT_DIRECTORY}/LICENSE" "${RESOURCE_DIRECTORY}/LICENSE-oxipng"

echo "Built oxipng ${VERSION}:"
file "${RESOURCE_DIRECTORY}/oxipng-arm64" "${RESOURCE_DIRECTORY}/oxipng-x86_64"
