#!/bin/bash

# Regression check for DMG inspection cleanup. It verifies both the device-based
# cleanup contract and that a real inspection leaves this particular DMG detached.
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly CHECK_SCRIPT="${SCRIPT_DIRECTORY}/check-release-content.sh"
readonly DMG_PATH="${1:-${PROJECT_DIRECTORY}/dist/PngCut-1.0.dmg}"

fail() {
    echo "DMG cleanup check failed: $*" >&2
    exit 1
}

is_attached() {
    hdiutil info | rg -F -q "${DMG_PATH}"
}

[[ -f "${DMG_PATH}" ]] || fail "missing DMG: ${DMG_PATH}"
is_attached && fail "DMG is already attached; detach it before running this check"

rg -F -q 'attach -readonly -nobrowse -mountpoint "${mount_directory}" -plist' "${CHECK_SCRIPT}" || fail "inspection must request an attach plist"
rg -F -q 'ATTACHED_DEVICE' "${CHECK_SCRIPT}" || fail "inspection must retain the attached disk device"
rg -F -q 'hdiutil detach "${ATTACHED_DEVICE}"' "${CHECK_SCRIPT}" || fail "inspection must detach the attached disk device"
if rg -F -q 'hdiutil detach "${mount_directory}"' "${CHECK_SCRIPT}"; then
    fail "inspection must not detach only its requested mount directory"
fi

"${CHECK_SCRIPT}" --dmg "${DMG_PATH}"
is_attached && fail "DMG remains attached after release-content inspection"

if RELEASE_CONTENT_TEST_FAIL_AFTER_ATTACH=1 "${CHECK_SCRIPT}" --dmg "${DMG_PATH}"; then
    fail "post-attach failure probe unexpectedly passed"
fi
is_attached && fail "DMG remains attached after a post-attach inspection failure"

echo "DMG cleanup check passed"
