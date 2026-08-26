#!/bin/bash

# Verifies the release documentation and, with --dmg, the packaged payload.
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly LICENSE_FILE="${PROJECT_DIRECTORY}/LICENSE"
readonly README_FILE="${PROJECT_DIRECTORY}/README.md"
readonly NOTICES_FILE="${PROJECT_DIRECTORY}/THIRD_PARTY_NOTICES.md"
readonly PNGQUANT_LICENSE="${PROJECT_DIRECTORY}/PngCut/Resources/pngquant/LICENSE-pngquant"

fail() {
    echo "release-content check failed: $*" >&2
    exit 1
}

[[ -f "${LICENSE_FILE}" ]] || fail "missing GPL v3 LICENSE"
[[ -f "${README_FILE}" ]] || fail "missing README.md"
[[ -f "${NOTICES_FILE}" ]] || fail "missing THIRD_PARTY_NOTICES.md"

# pngquant's bundled upstream notice contains a verbatim GPL v3 copy. Compare
# the project license with that canonical section to detect truncation or edits.
expected_gpl="$(mktemp)"
trap 'rm -f "${expected_gpl}"' EXIT
awk '
    /^[[:space:]]*GNU GENERAL PUBLIC LICENSE$/ { in_gpl = 1 }
    in_gpl && /^- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -/ { exit }
    in_gpl { print }
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
    'PNG' 'JPG/JPEG' 'oxipng 10.2.0' 'pngquant 3.0.3' 'MozJPEG v4.1.5' \
    '完全离线' 'GPL v3'; do
    rg -F -q "${required}" "${README_FILE}" "${NOTICES_FILE}" || fail "missing required release content: ${required}"
done

for required in \
    'oxipng 10.2.0' 'MIT' 'Resources/oxipng/LICENSE-oxipng' \
    'pngquant 3.0.3' 'GPL v3' 'Resources/pngquant/LICENSE-pngquant' \
    'MozJPEG v4.1.5' 'Resources/mozjpeg/LICENSE-mozjpeg' \
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
        'mozjpeg/mozjpeg-helper-arm64' 'mozjpeg/mozjpeg-helper-x86_64'; do
        [[ -f "${actual_mount_point}/PngCut.app/Contents/Resources/${resource}" ]] || fail "DMG missing engine resource: ${resource}"
    done
    file "${actual_mount_point}/PngCut.app/Contents/MacOS/pngcut" | rg -q 'arm64.*x86_64|x86_64.*arm64' || fail "DMG app is not universal"
    for engine in oxipng pngquant; do
        file "${actual_mount_point}/PngCut.app/Contents/Resources/${engine}/${engine}-arm64" | rg -q 'arm64' || fail "${engine} arm64 resource has the wrong architecture"
        file "${actual_mount_point}/PngCut.app/Contents/Resources/${engine}/${engine}-x86_64" | rg -q 'x86_64' || fail "${engine} x86_64 resource has the wrong architecture"
    done
    file "${actual_mount_point}/PngCut.app/Contents/Resources/mozjpeg/mozjpeg-helper-arm64" | rg -q 'arm64' || fail "MozJPEG arm64 resource has the wrong architecture"
    file "${actual_mount_point}/PngCut.app/Contents/Resources/mozjpeg/mozjpeg-helper-x86_64" | rg -q 'x86_64' || fail "MozJPEG x86_64 resource has the wrong architecture"
    detach
fi

echo "release-content check passed"
