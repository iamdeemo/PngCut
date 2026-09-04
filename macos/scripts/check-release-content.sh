#!/bin/bash

# Verifies the release documentation and, with --dmg, the packaged payload.
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly REPOSITORY_ROOT="$(cd "${PROJECT_DIRECTORY}/.." && pwd)"
readonly LICENSE_FILE="${REPOSITORY_ROOT}/LICENSE"
readonly README_FILE="${REPOSITORY_ROOT}/README.md"
readonly NOTICES_FILE="${PROJECT_DIRECTORY}/THIRD_PARTY_NOTICES.md"
readonly PNGQUANT_LICENSE="${PROJECT_DIRECTORY}/PngCut/Resources/pngquant/LICENSE-pngquant"
readonly GIFSICLE_RESOURCE_DIRECTORY="${PROJECT_DIRECTORY}/PngCut/Resources/gifsicle"
readonly GIFSKI_RESOURCE_DIRECTORY="${PROJECT_DIRECTORY}/PngCut/Resources/gifski"
readonly CONTRACT_MANIFEST="${REPOSITORY_ROOT}/shared/contracts/v1/engine-manifest.json"

# shellcheck source=/dev/null
source "${SCRIPT_DIRECTORY}/macos-binary-validation.sh"

fail() {
    echo "release-content check failed: $*" >&2
    exit 1
}

command -v lipo >/dev/null || fail "missing required release tool: lipo"

[[ -f "${LICENSE_FILE}" ]] || fail "missing GPL v3 LICENSE"
[[ -f "${README_FILE}" ]] || fail "missing README.md"
[[ -f "${NOTICES_FILE}" ]] || fail "missing THIRD_PARTY_NOTICES.md"
[[ -f "${CONTRACT_MANIFEST}" ]] || fail "missing shared engine manifest"
for resource in \
    "${GIFSICLE_RESOURCE_DIRECTORY}/gifsicle-arm64" \
    "${GIFSICLE_RESOURCE_DIRECTORY}/gifsicle-x86_64" \
    "${GIFSICLE_RESOURCE_DIRECTORY}/LICENSE-gifsicle" \
    "${GIFSKI_RESOURCE_DIRECTORY}/gifski-arm64" \
    "${GIFSKI_RESOURCE_DIRECTORY}/gifski-x86_64" \
    "${GIFSKI_RESOURCE_DIRECTORY}/LICENSE-gifski"; do
    [[ -f "${resource}" ]] || fail "missing GIF engine resource: ${resource#"${PROJECT_DIRECTORY}/"}"
done
for executable in \
    "${GIFSICLE_RESOURCE_DIRECTORY}/gifsicle-arm64" \
    "${GIFSICLE_RESOURCE_DIRECTORY}/gifsicle-x86_64" \
    "${GIFSKI_RESOURCE_DIRECTORY}/gifski-arm64" \
    "${GIFSKI_RESOURCE_DIRECTORY}/gifski-x86_64"; do
    [[ -x "${executable}" ]] || fail "GIF engine resource is not executable: ${executable#"${PROJECT_DIRECTORY}/"}"
done
for engine in gifsicle gifski; do
    validate_thin_macos_architecture arm64 "${PROJECT_DIRECTORY}/PngCut/Resources/${engine}/${engine}-arm64" || fail "${engine} arm64 resource has the wrong architecture"
    validate_thin_macos_architecture x86_64 "${PROJECT_DIRECTORY}/PngCut/Resources/${engine}/${engine}-x86_64" || fail "${engine} x86_64 resource has the wrong architecture"
done

manifest_value() {
    local engine_key="$1"
    local field_key="$2"
    plutil -extract "engines.${engine_key}.${field_key}" raw "${CONTRACT_MANIFEST}"
}

[[ "$(manifest_value oxipng version)" == "10.2.0" ]] || fail "unexpected oxipng manifest version"
[[ "$(manifest_value pngquant version)" == "3.0.3" ]] || fail "unexpected pngquant manifest version"
[[ "$(manifest_value mozjpeg version)" == "4.1.5" ]] || fail "unexpected MozJPEG manifest version"

# pngquant's bundled upstream notice contains a verbatim GPL v3 copy. Compare
# the project license with that canonical section to detect truncation or edits.
expected_gpl="$(mktemp)"
trap 'rm -f "${expected_gpl}"' EXIT
awk '
    /^[[:space:]]*GNU GENERAL PUBLIC LICENSE$/ { in_gpl = 1 }
    in_gpl && /^- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -/ { exit }
    in_gpl && /^$/ { blank_lines += 1; next }
    in_gpl {
        while (blank_lines > 0) {
            print ""
            blank_lines -= 1
        }
        print
    }
' "${PNGQUANT_LICENSE}" > "${expected_gpl}"
cmp -s "${LICENSE_FILE}" "${expected_gpl}" || fail "LICENSE is not the unmodified GPL v3 text"

if rg -n -i 'Tinify|API Key|apiKey' "${README_FILE}" "${NOTICES_FILE}"; then
    fail "obsolete online-service wording remains"
fi

if rg -n -i '保留[[:space:]]*(所有|全部)?[[:space:]]*(JPEG[[:space:]]*)?(元数据|metadata)|保留.*(所有|全部).*(元数据|metadata)' "${README_FILE}"; then
    fail "README overstates MozJPEG metadata preservation"
fi
for required in \
    '兼容的 APP1/APP2 元数据标记' 'EXIF' 'ICC' 'COM、APP13 及其他标记可能不保留'; do
    rg -F -q "${required}" "${README_FILE}" || fail "README is missing precise MozJPEG metadata policy: ${required}"
done

for required in \
    'PNG' 'JPG/JPEG' 'GIF' 'PNG 序列' \
    'oxipng 10.2.0' 'pngquant 3.0.3' 'MozJPEG v4.1.5' 'Gifsicle 1.96' 'Gifski 1.34.0' \
    '完全离线' 'GPL v3'; do
    rg -F -q "${required}" "${README_FILE}" "${NOTICES_FILE}" || fail "missing required release content: ${required}"
done

for required in \
    'oxipng 10.2.0' 'MIT' 'Resources/oxipng/LICENSE-oxipng' \
    'pngquant 3.0.3' 'GPL v3' 'Resources/pngquant/LICENSE-pngquant' \
    'MozJPEG v4.1.5' 'Resources/mozjpeg/LICENSE-mozjpeg' \
    'Gifsicle 1.96' 'GPL-2.0-only' 'Resources/gifsicle/LICENSE-gifsicle' \
    'Gifski 1.34.0' 'AGPL-3.0-or-later' 'Resources/gifski/LICENSE-gifski' \
    '本项目' 'GPL v3'; do
    rg -F -q "${required}" "${NOTICES_FILE}" || fail "missing third-party notice: ${required}"
done

if [[ "${1:-}" == "--dmg" ]]; then
    dmg_path="${2:-}"
    [[ -f "${dmg_path}" ]] || fail "missing DMG: ${dmg_path:-<not supplied>}"
    hdiutil verify "${dmg_path}"

    mount_directory="$(mktemp -d)"
    attach_plist="$(mktemp)"
    ATTACHED_DEVICE=""
    actual_mount_point=""
    detach() {
        if [[ -n "${ATTACHED_DEVICE}" ]]; then
            if ! hdiutil detach "${ATTACHED_DEVICE}" -quiet; then
                echo "release-content check cleanup failed: could not detach ${ATTACHED_DEVICE}" >&2
                return 1
            fi
            ATTACHED_DEVICE=""
        fi
        rmdir "${mount_directory}" 2>/dev/null || true
    }
    cleanup_dmg_inspection() {
        local exit_status=$?
        local cleanup_status=0
        set +e
        detach || cleanup_status=1
        rm -f "${attach_plist}" "${expected_gpl}"
        if [[ "${exit_status}" -eq 0 && "${cleanup_status}" -ne 0 ]]; then
            return "${cleanup_status}"
        fi
        return "${exit_status}"
    }
    trap cleanup_dmg_inspection EXIT
    hdiutil attach -readonly -nobrowse -mountpoint "${mount_directory}" -plist "${dmg_path}" > "${attach_plist}"

    entity_index=0
    fallback_device=""
    while true; do
        entity_device="$(/usr/libexec/PlistBuddy -c "Print :system-entities:${entity_index}:dev-entry" "${attach_plist}" 2>/dev/null || true)"
        entity_mount_point="$(/usr/libexec/PlistBuddy -c "Print :system-entities:${entity_index}:mount-point" "${attach_plist}" 2>/dev/null || true)"
        [[ -n "${entity_device}${entity_mount_point}" ]] || break

        if [[ -z "${fallback_device}" && "${entity_device}" =~ ^/dev/disk[0-9]+s[0-9]+$ ]]; then
            fallback_device="$(sed -E 's/s[0-9]+$//' <<< "${entity_device}")"
        fi
        if [[ -z "${ATTACHED_DEVICE}" && "${entity_device}" =~ ^/dev/disk[0-9]+$ ]]; then
            ATTACHED_DEVICE="${entity_device}"
        fi
        if [[ -n "${entity_mount_point}" ]]; then
            actual_mount_point="${entity_mount_point}"
        fi
        entity_index=$((entity_index + 1))
    done
    ATTACHED_DEVICE="${ATTACHED_DEVICE:-${fallback_device}}"
    [[ -n "${ATTACHED_DEVICE}" ]] || fail "DMG attach plist did not identify a disk device"
    [[ -n "${actual_mount_point}" ]] || fail "DMG attach plist did not identify a mount point"
    [[ "${RELEASE_CONTENT_TEST_FAIL_AFTER_ATTACH:-}" != "1" ]] || fail "test-only post-attach failure"
    [[ -d "${actual_mount_point}/PngCut.app" ]] || fail "DMG does not contain PngCut.app"
    [[ -L "${actual_mount_point}/Applications" ]] || fail "DMG does not contain Applications link"
    for resource in \
        'oxipng/oxipng-arm64' 'oxipng/oxipng-x86_64' \
        'pngquant/pngquant-arm64' 'pngquant/pngquant-x86_64' \
        'mozjpeg/mozjpeg-helper-arm64' 'mozjpeg/mozjpeg-helper-x86_64' \
        'gifsicle/gifsicle-arm64' 'gifsicle/gifsicle-x86_64' \
        'gifski/gifski-arm64' 'gifski/gifski-x86_64'; do
        [[ -f "${actual_mount_point}/PngCut.app/Contents/Resources/${resource}" ]] || fail "DMG missing engine resource: ${resource}"
    done
    app_architectures="$(lipo -archs "${actual_mount_point}/PngCut.app/Contents/MacOS/pngcut")"
    [[ "${app_architectures}" == "arm64 x86_64" || "${app_architectures}" == "x86_64 arm64" ]] || fail "DMG app is not universal"
    for engine in oxipng pngquant gifsicle gifski; do
        validate_thin_macos_architecture arm64 "${actual_mount_point}/PngCut.app/Contents/Resources/${engine}/${engine}-arm64" || fail "${engine} arm64 resource has the wrong architecture"
        validate_thin_macos_architecture x86_64 "${actual_mount_point}/PngCut.app/Contents/Resources/${engine}/${engine}-x86_64" || fail "${engine} x86_64 resource has the wrong architecture"
    done
    validate_thin_macos_architecture arm64 "${actual_mount_point}/PngCut.app/Contents/Resources/mozjpeg/mozjpeg-helper-arm64" || fail "MozJPEG arm64 resource has the wrong architecture"
    validate_thin_macos_architecture x86_64 "${actual_mount_point}/PngCut.app/Contents/Resources/mozjpeg/mozjpeg-helper-x86_64" || fail "MozJPEG x86_64 resource has the wrong architecture"
    detach
fi

echo "release-content check passed"
