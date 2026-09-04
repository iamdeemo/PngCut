#!/bin/bash

# Source-only helpers for validating the architecture and deployment target of
# bundled macOS Mach-O executables. Keep the architecture comparison exact:
# arm64e is not an arm64 binary for release compatibility purposes.

validate_thin_macos_architecture() {
    local expected_architecture="$1"
    local binary_path="$2"
    local actual_architectures

    command -v lipo >/dev/null || {
        echo "Missing required build tool: lipo" >&2
        return 1
    }
    [[ -f "${binary_path}" ]] || {
        echo "Missing Mach-O binary: ${binary_path}" >&2
        return 1
    }
    actual_architectures="$(lipo -archs "${binary_path}" 2>/dev/null)" || {
        echo "Could not determine Mach-O architecture: ${binary_path}" >&2
        return 1
    }
    if [[ "${actual_architectures}" != "${expected_architecture}" ]]; then
        echo "Expected thin ${expected_architecture} Mach-O, got ${actual_architectures}: ${binary_path}" >&2
        return 1
    fi
}

macos_minos() {
    local binary_path="$1"

    command -v otool >/dev/null || {
        echo "Missing required build tool: otool" >&2
        return 1
    }
    otool -l "${binary_path}" | awk '
        $1 == "cmd" {
            command = $2
            is_macos_build_version = 0
            next
        }
        command == "LC_BUILD_VERSION" && $1 == "platform" {
            is_macos_build_version = ($2 == "macos" || $2 == "1")
            next
        }
        command == "LC_BUILD_VERSION" && is_macos_build_version && $1 == "minos" {
            print $2
            exit
        }
        command == "LC_VERSION_MIN_MACOSX" && $1 == "version" {
            print $2
            exit
        }
    '
}

validate_macos_minos_at_most() {
    local maximum_version="$1"
    local binary_path="$2"
    local actual_version

    [[ -f "${binary_path}" ]] || {
        echo "Missing Mach-O binary: ${binary_path}" >&2
        return 1
    }
    actual_version="$(macos_minos "${binary_path}")"
    [[ -n "${actual_version}" ]] || {
        echo "Could not determine macOS minos: ${binary_path}" >&2
        return 1
    }
    if ! awk -v actual="${actual_version}" -v maximum="${maximum_version}" '
        BEGIN {
            split(actual, actual_parts, ".")
            split(maximum, maximum_parts, ".")
            for (part = 1; part <= 3; part++) {
                actual_value = (part in actual_parts) ? actual_parts[part] + 0 : 0
                maximum_value = (part in maximum_parts) ? maximum_parts[part] + 0 : 0
                if (actual_value < maximum_value) exit 0
                if (actual_value > maximum_value) exit 1
            }
            exit 0
        }
    '; then
        echo "Expected macOS minos ${maximum_version} or lower, got ${actual_version}: ${binary_path}" >&2
        return 1
    fi
}
