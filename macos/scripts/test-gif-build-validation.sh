#!/bin/bash

# Regression checks for GIF engine provenance, Mach-O validation, and DMG
# release validation wiring. The arm64e object is intentionally temporary: it
# proves that an architecture-family substring match is not sufficient.
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly BUILD_DIRECTORY="${PROJECT_DIRECTORY}/.build"
readonly GIFSICLE_BUILDER="${SCRIPT_DIRECTORY}/build-gifsicle.sh"
readonly GIFSKI_BUILDER="${SCRIPT_DIRECTORY}/build-gifski.sh"
readonly RELEASE_CHECKER="${SCRIPT_DIRECTORY}/check-release-content.sh"
readonly DMG_BUILDER="${SCRIPT_DIRECTORY}/create-dmg.sh"
readonly VALIDATION_HELPERS="${SCRIPT_DIRECTORY}/macos-binary-validation.sh"
readonly GIFSICLE_ARM64="${PROJECT_DIRECTORY}/PngCut/Resources/gifsicle/gifsicle-arm64"
readonly GIFSICLE_X86_64="${PROJECT_DIRECTORY}/PngCut/Resources/gifsicle/gifsicle-x86_64"
readonly GIFSKI_ARM64="${PROJECT_DIRECTORY}/PngCut/Resources/gifski/gifski-arm64"
readonly GIFSKI_X86_64="${PROJECT_DIRECTORY}/PngCut/Resources/gifski/gifski-x86_64"
readonly GIFSICLE_REVISION="a08e0f6686d467bb8b9e4715b1f1835f12984fb0"
readonly GIFSKI_TAG_OBJECT="072a09c2364a07266bf05d7bfa7361bcc28381e0"
readonly GIFSKI_SOURCE_REVISION="1060eab4500a20f27e2fa3ab7e85473d0e921cbd"
readonly NOTICES_FILE="${PROJECT_DIRECTORY}/THIRD_PARTY_NOTICES.md"

failures=0
fixture_directory=""

record_failure() {
    echo "GIF build validation test failed: $*" >&2
    failures=$((failures + 1))
}

expect_fixed_text() {
    local file_path="$1"
    local expected_text="$2"
    rg -F -q "${expected_text}" "${file_path}" || record_failure "${file_path##*/} is missing: ${expected_text}"
}

line_number() {
    rg -n -F "$1" "$2" | head -1 | cut -d: -f1
}

test_dmg_validation_wiring() {
    local verify_line
    local release_check_line
    local publish_line
    verify_line="$(line_number 'hdiutil verify "${TEMPORARY_DMG}"' "${DMG_BUILDER}" || true)"
    release_check_line="$(line_number '"${RELEASE_CONTENT_CHECK}" --dmg "${TEMPORARY_DMG}"' "${DMG_BUILDER}" || true)"
    publish_line="$(line_number 'mv -f "${TEMPORARY_DMG}" "${OUTPUT_DMG}"' "${DMG_BUILDER}" || true)"
    if [[ -z "${verify_line}" || -z "${release_check_line}" || -z "${publish_line}" ]]; then
        record_failure "create-dmg.sh must verify the temporary DMG, inspect it, then publish it"
    elif (( verify_line >= release_check_line || release_check_line >= publish_line )); then
        record_failure "create-dmg.sh runs release validation outside the verified temporary-DMG window"
    fi
}

test_architecture_rejection() {
    if [[ ! -f "${VALIDATION_HELPERS}" ]]; then
        record_failure "missing reusable macOS binary validation helper"
        return
    fi

    # shellcheck source=/dev/null
    source "${VALIDATION_HELPERS}"
    mkdir -p "${BUILD_DIRECTORY}"
    fixture_directory="$(mktemp -d "${BUILD_DIRECTORY}/gif-arch-validation.XXXXXX")"
    xcrun --sdk macosx clang -arch arm64 -c -x c /dev/null -o "${fixture_directory}/arm64.o"
    xcrun --sdk macosx clang -arch arm64e -c -x c /dev/null -o "${fixture_directory}/arm64e.o"

    for expected_and_binary in \
        "arm64:${GIFSICLE_ARM64}" "x86_64:${GIFSICLE_X86_64}" \
        "arm64:${GIFSKI_ARM64}" "x86_64:${GIFSKI_X86_64}"; do
        expected_architecture="${expected_and_binary%%:*}"
        binary_path="${expected_and_binary#*:}"
        if ! validate_thin_macos_architecture "${expected_architecture}" "${binary_path}"; then
            record_failure "real ${expected_architecture} binary was rejected: ${binary_path}"
        fi
    done

    if validate_thin_macos_architecture arm64 "${fixture_directory}/arm64e.o" >/dev/null 2>&1; then
        record_failure "arm64e fixture was accepted as arm64"
    fi

    if ! validate_macos_minos_at_most 13.0 "${GIFSICLE_ARM64}" || \
       ! validate_macos_minos_at_most 13.0 "${GIFSICLE_X86_64}"; then
        record_failure "Gifsicle resources do not have minos 13.0 or lower"
    fi
}

test_static_build_contract() {
    expect_fixed_text "${GIFSICLE_BUILDER}" "readonly EXPECTED_REVISION=\"${GIFSICLE_REVISION}\""
    expect_fixed_text "${GIFSKI_BUILDER}" "readonly EXPECTED_TAG_OBJECT=\"${GIFSKI_TAG_OBJECT}\""
    expect_fixed_text "${GIFSKI_BUILDER}" "readonly EXPECTED_SOURCE_REVISION=\"${GIFSKI_SOURCE_REVISION}\""
    expect_fixed_text "${GIFSICLE_BUILDER}" 'checkout --detach "${EXPECTED_REVISION}"'
    expect_fixed_text "${GIFSKI_BUILDER}" 'checkout --detach "${EXPECTED_SOURCE_REVISION}"'
    expect_fixed_text "${GIFSICLE_BUILDER}" 'git -C "${CHECKOUT_DIRECTORY}" rev-parse HEAD'
    expect_fixed_text "${GIFSKI_BUILDER}" 'git -C "${CHECKOUT_DIRECTORY}" rev-parse HEAD'
    expect_fixed_text "${GIFSKI_BUILDER}" 'git -C "${CHECKOUT_DIRECTORY}" rev-parse "refs/tags/${VERSION}"'
    expect_fixed_text "${GIFSKI_BUILDER}" 'git -C "${CHECKOUT_DIRECTORY}" rev-parse "refs/tags/${VERSION}^{}"'
    expect_fixed_text "${NOTICES_FILE}" "${GIFSKI_TAG_OBJECT}"
    expect_fixed_text "${NOTICES_FILE}" "${GIFSKI_SOURCE_REVISION}"
    expect_fixed_text "${GIFSICLE_BUILDER}" 'export MACOSX_DEPLOYMENT_TARGET=13.0'
    expect_fixed_text "${GIFSICLE_BUILDER}" 'validate_thin_macos_architecture'
    expect_fixed_text "${GIFSKI_BUILDER}" 'validate_thin_macos_architecture'
    expect_fixed_text "${RELEASE_CHECKER}" 'validate_thin_macos_architecture'
    expect_fixed_text "${RELEASE_CHECKER}" 'command -v lipo >/dev/null || fail "missing required release tool: lipo"'
    expect_fixed_text "${VALIDATION_HELPERS}" 'lipo -archs'
    expect_fixed_text "${VALIDATION_HELPERS}" 'validate_macos_minos_at_most'
}

cleanup() {
    if [[ -n "${fixture_directory}" && -d "${fixture_directory}" ]]; then
        rm -rf "${fixture_directory}"
    fi
}
trap cleanup EXIT HUP INT TERM

test_dmg_validation_wiring
test_architecture_rejection
test_static_build_contract

if (( failures > 0 )); then
    exit 1
fi

echo "GIF build validation test passed"
