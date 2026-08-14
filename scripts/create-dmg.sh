#!/bin/bash

# Builds pngcut as an intentionally unsigned, unnotarized release and packages
# it in a compressed DMG. All paths are relative to this script so the command
# works from any current directory:
#   ./scripts/create-dmg.sh
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly PROJECT_FILE="${PROJECT_DIRECTORY}/FFPNG.xcodeproj"
readonly DERIVED_DATA_DIRECTORY="${PROJECT_DIRECTORY}/.build/DerivedData-Release"
readonly PRODUCT_DIRECTORY="${DERIVED_DATA_DIRECTORY}/Build/Products/Release"
readonly APPLICATION_PATH="${PRODUCT_DIRECTORY}/pngcut.app"
readonly DISTRIBUTION_DIRECTORY="${PROJECT_DIRECTORY}/dist"

cleanup() {
    if [[ -n "${STAGING_DIRECTORY:-}" && -d "${STAGING_DIRECTORY}" ]]; then
        rm -rf "${STAGING_DIRECTORY}"
    fi
    if [[ -n "${TEMPORARY_DMG:-}" && -e "${TEMPORARY_DMG}" ]]; then
        rm -f "${TEMPORARY_DMG}"
    fi
    if [[ -n "${TEMPORARY_DMG_DIRECTORY:-}" && -d "${TEMPORARY_DMG_DIRECTORY}" ]]; then
        rmdir "${TEMPORARY_DMG_DIRECTORY}" 2>/dev/null || true
    fi
}
trap cleanup EXIT HUP INT TERM

mkdir -p "${DISTRIBUTION_DIRECTORY}"

xcodebuild \
    -project "${PROJECT_FILE}" \
    -scheme FFPNG \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA_DIRECTORY}" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -d "${APPLICATION_PATH}" ]]; then
    echo "Expected Release app was not produced at ${APPLICATION_PATH}." >&2
    exit 1
fi

readonly VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APPLICATION_PATH}/Contents/Info.plist")"
readonly OUTPUT_DMG="${DISTRIBUTION_DIRECTORY}/pngcut-${VERSION}.dmg"
STAGING_DIRECTORY="$(mktemp -d "${PROJECT_DIRECTORY}/.build/ffpng-dmg.XXXXXX")"
TEMPORARY_DMG_DIRECTORY="$(mktemp -d "${DISTRIBUTION_DIRECTORY}/.ffpng-dmg.XXXXXX")"
TEMPORARY_DMG="${TEMPORARY_DMG_DIRECTORY}/pngcut-${VERSION}.dmg"

ditto "${APPLICATION_PATH}" "${STAGING_DIRECTORY}/pngcut.app"
ln -s /Applications "${STAGING_DIRECTORY}/Applications"

hdiutil create \
    -volname pngcut \
    -srcfolder "${STAGING_DIRECTORY}" \
    -noatomic \
    -format UDZO \
    -ov \
    "${TEMPORARY_DMG}"
hdiutil verify "${TEMPORARY_DMG}"
mv -f "${TEMPORARY_DMG}" "${OUTPUT_DMG}"
TEMPORARY_DMG=""
rmdir "${TEMPORARY_DMG_DIRECTORY}"
TEMPORARY_DMG_DIRECTORY=""

echo "Created unsigned, unnotarized DMG: ${OUTPUT_DMG}"
shasum -a 256 "${OUTPUT_DMG}"
