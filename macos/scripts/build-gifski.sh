#!/bin/bash

# Builds the pinned Gifski release for each macOS architecture without relying
# on a globally installed encoder.
set -euo pipefail

readonly REPOSITORY="https://github.com/ImageOptim/gifski.git"
readonly VERSION="1.34.0"
readonly EXPECTED_TAG_OBJECT="072a09c2364a07266bf05d7bfa7361bcc28381e0"
readonly EXPECTED_SOURCE_REVISION="1060eab4500a20f27e2fa3ab7e85473d0e921cbd"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly CHECKOUT_DIRECTORY="${PROJECT_DIRECTORY}/.build/gifski"
readonly LOCK_DIRECTORY="${PROJECT_DIRECTORY}/.build/gifski-build.lock"
readonly RESOURCE_DIRECTORY="${PROJECT_DIRECTORY}/PngCut/Resources/gifski"
readonly ARM_TARGET="aarch64-apple-darwin"
readonly INTEL_TARGET="x86_64-apple-darwin"

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
        echo "Another Gifski build is already running (or left ${LOCK_DIRECTORY})." >&2
        exit 1
    fi
    trap 'rmdir "${LOCK_DIRECTORY}"' EXIT
    trap 'exit 1' HUP INT TERM
}

prepare_checkout() {
    if [[ -e "${CHECKOUT_DIRECTORY}" && ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        echo "${CHECKOUT_DIRECTORY} exists but is not a Gifski Git checkout." >&2
        exit 1
    fi
    if [[ ! -d "${CHECKOUT_DIRECTORY}/.git" ]]; then
        mkdir -p "$(dirname "${CHECKOUT_DIRECTORY}")"
        git clone --depth 1 --no-checkout "${REPOSITORY}" "${CHECKOUT_DIRECTORY}"
    else
        require_clean_vendor_checkout
    fi

    git -C "${CHECKOUT_DIRECTORY}" fetch --depth 1 origin "+refs/tags/${VERSION}:refs/tags/${VERSION}"
    git -C "${CHECKOUT_DIRECTORY}" cat-file -e "${EXPECTED_SOURCE_REVISION}^{commit}" || {
        echo "Gifski ${VERSION} did not provide expected source revision ${EXPECTED_SOURCE_REVISION}." >&2
        exit 1
    }
    git -C "${CHECKOUT_DIRECTORY}" checkout --detach "${EXPECTED_SOURCE_REVISION}"

    local resolved_version
    local resolved_revision
    local tag_object
    local tag_revision
    resolved_version="$(git -C "${CHECKOUT_DIRECTORY}" describe --exact-match --tags HEAD 2>/dev/null || true)"
    if [[ "${resolved_version}" != "${VERSION}" ]]; then
        echo "Expected Gifski ${VERSION}, got ${resolved_version:-an untagged revision}." >&2
        exit 1
    fi
    resolved_revision="$(git -C "${CHECKOUT_DIRECTORY}" rev-parse HEAD)"
    tag_object="$(git -C "${CHECKOUT_DIRECTORY}" rev-parse "refs/tags/${VERSION}")"
    tag_revision="$(git -C "${CHECKOUT_DIRECTORY}" rev-parse "refs/tags/${VERSION}^{}")"
    if [[ "${resolved_revision}" != "${EXPECTED_SOURCE_REVISION}" || "${tag_object}" != "${EXPECTED_TAG_OBJECT}" || "${tag_revision}" != "${EXPECTED_SOURCE_REVISION}" ]]; then
        echo "Gifski ${VERSION} tag/source provenance did not resolve to the pinned revisions." >&2
        exit 1
    fi
}

build_target() {
    local target="$1"
    local architecture="$2"
    rustup target add "${target}"
    cargo build --manifest-path "${CHECKOUT_DIRECTORY}/Cargo.toml" --release --locked --target "${target}"
    install -m 755 "${CHECKOUT_DIRECTORY}/target/${target}/release/gifski" "${RESOURCE_DIRECTORY}/gifski-${architecture}"
}

validate_architecture() {
    local architecture="$1"
    validate_thin_macos_architecture "${architecture}" "${RESOURCE_DIRECTORY}/gifski-${architecture}"
}

require_tool git
require_tool cargo
require_tool rustup
require_tool file
require_tool lipo
# shellcheck source=/dev/null
source "${SCRIPT_DIRECTORY}/macos-binary-validation.sh"
acquire_build_lock
prepare_checkout
mkdir -p "${RESOURCE_DIRECTORY}"
build_target "${ARM_TARGET}" arm64
build_target "${INTEL_TARGET}" x86_64
install -m 644 "${CHECKOUT_DIRECTORY}/LICENSE" "${RESOURCE_DIRECTORY}/LICENSE-gifski"
validate_architecture arm64
validate_architecture x86_64

echo "Built Gifski ${VERSION}:"
file "${RESOURCE_DIRECTORY}/gifski-arm64" "${RESOURCE_DIRECTORY}/gifski-x86_64"
