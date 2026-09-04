#!/bin/bash

# Exercises the MozJPEG helper's metadata and input-size safety boundaries.
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly HELPER="${PROJECT_DIRECTORY}/PngCut/Resources/mozjpeg/mozjpeg-helper-arm64"
readonly FIXTURE_DIRECTORY="$(mktemp -d)"
readonly SOURCE="${FIXTURE_DIRECTORY}/source.jpg"
readonly HELPER_SOURCE="${PROJECT_DIRECTORY}/PngCut/Resources/mozjpeg/mozjpeg-helper.c"
readonly MOZJPEG_SOURCE_DIRECTORY="${PROJECT_DIRECTORY}/.build/mozjpeg"
readonly MOZJPEG_BUILD_DIRECTORY="${PROJECT_DIRECTORY}/.build/mozjpeg-arm64"

sips -s format jpeg "${PROJECT_DIRECTORY}/PngCut/Resources/AppIcon.icns" --out "${SOURCE}" >/dev/null

make_oversized_marker_fixture() {
    local marker="$1"
    local destination="$2"
    {
        case "${marker}" in
            APP1) printf '\377\330\377\341\377\377' ;;
            APP2) printf '\377\330\377\342\377\377' ;;
            *) echo "Unknown JPEG marker fixture: ${marker}" >&2; exit 1 ;;
        esac
        dd if=/dev/zero bs=65533 count=1 2>/dev/null
        dd if="${SOURCE}" bs=1 skip=2 2>/dev/null
    } > "${destination}"
}

expect_rejected() {
    local label="$1"
    local input="$2"
    local output="${FIXTURE_DIRECTORY}/${label// /-}.jpg"
    if "${HELPER}" --quality 75 --output "${output}" --preserve-metadata "${input}"; then
        echo "MozJPEG helper accepted ${label}." >&2
        exit 1
    fi
    echo "PASS: ${label} rejected"
}

readonly OVERSIZED_APP1="${FIXTURE_DIRECTORY}/oversized-app1.jpg"
readonly OVERSIZED_APP2="${FIXTURE_DIRECTORY}/oversized-app2.jpg"
readonly OVERSIZED_INPUT="${FIXTURE_DIRECTORY}/oversized-input.jpg"
make_oversized_marker_fixture APP1 "${OVERSIZED_APP1}"
make_oversized_marker_fixture APP2 "${OVERSIZED_APP2}"
dd if="${SOURCE}" of="${OVERSIZED_INPUT}" bs=1m 2>/dev/null
dd if=/dev/zero bs=1m count=65 2>/dev/null >> "${OVERSIZED_INPUT}"

expect_rejected "oversized APP1 metadata" "${OVERSIZED_APP1}"
expect_rejected "oversized APP2 metadata" "${OVERSIZED_APP2}"
expect_rejected "input larger than 64 MiB" "${OVERSIZED_INPUT}"

readonly NORMAL_OUTPUT="${FIXTURE_DIRECTORY}/normal-output.jpg"
"${HELPER}" --quality 75 --output "${NORMAL_OUTPUT}" --preserve-metadata "${SOURCE}"
source_profile="$(sips -g profile "${SOURCE}" | awk -F ': ' '/profile:/{print $2}')"
output_profile="$(sips -g profile "${NORMAL_OUTPUT}" | awk -F ': ' '/profile:/{print $2}')"
[[ -n "${source_profile}" && "${source_profile}" == "${output_profile}" ]] || {
    echo "MozJPEG helper did not preserve the ICC profile." >&2
    exit 1
}
file "${SOURCE}" | grep -q 'Exif Standard'
file "${NORMAL_OUTPUT}" | grep -q 'Exif Standard'
echo "PASS: normal JPEG preserves EXIF and ICC"

# The boundary checks existed before this expanded test, so this opt-in proof
# compiles a temporary helper with the marker rejection branch disabled. The
# oversized APP2 fixture must then be accepted, proving the fixture would have
# caught that regression without changing the production helper.
if [[ "${PNGCUT_RUN_MOZJPEG_MUTATION_TEST:-0}" == "1" ]]; then
    readonly MUTATED_SOURCE="${FIXTURE_DIRECTORY}/mozjpeg-helper-without-marker-limit.c"
    readonly MUTATED_HELPER="${FIXTURE_DIRECTORY}/mozjpeg-helper-without-marker-limit"
    sed 's/if (marker->original_length > MAX_SAVED_MARKER_BYTES) {/if (0) {/' "${HELPER_SOURCE}" > "${MUTATED_SOURCE}"
    xcrun --sdk macosx clang -arch arm64 -O2 -Wall -Wextra -Werror \
        -I "${MOZJPEG_SOURCE_DIRECTORY}" -I "${MOZJPEG_BUILD_DIRECTORY}" \
        "${MUTATED_SOURCE}" "${MOZJPEG_BUILD_DIRECTORY}/libjpeg.a" -o "${MUTATED_HELPER}"
    if ! "${MUTATED_HELPER}" --quality 75 --output "${FIXTURE_DIRECTORY}/mutation-output.jpg" --preserve-metadata "${OVERSIZED_APP2}"; then
        echo "Mutation proof failed: the helper without marker rejection still rejected APP2." >&2
        exit 1
    fi
    echo "PASS: mutation proof accepted oversized APP2 without the rejection branch"
fi
