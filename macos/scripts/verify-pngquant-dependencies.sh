#!/bin/bash

# Fails packaging verification when pngquant references a dylib unavailable on
# a clean macOS installation. @rpath dependencies are allowed only when the
# matching dylib is present in the app resource payload.
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RESOURCE_DIRECTORY="${SCRIPT_DIRECTORY}/../PngCut/Resources/pngquant"

verify_binary() {
    local binary="$1"
    local dependency
    local dependency_path
    local dependency_name
    local invalid=0

    while IFS= read -r dependency; do
        dependency="${dependency#"${dependency%%[![:space:]]*}"}"
        dependency_path="${dependency%% (*}"
        case "${dependency_path}" in
            /usr/lib/*|/System/Library/*) ;;
            @rpath/*)
                dependency_name="${dependency_path##*/}"
                if ! find "${RESOURCE_DIRECTORY}" -type f -name "${dependency_name}" -print -quit | grep -q .; then
                    echo "Unbundled @rpath dependency in ${binary}: ${dependency_path}" >&2
                    invalid=1
                fi
                ;;
            *)
                echo "Non-system dylib dependency in ${binary}: ${dependency_path}" >&2
                invalid=1
                ;;
        esac
    done < <(otool -L "${binary}" | tail -n +2)

    return "${invalid}"
}

verify_binary "${RESOURCE_DIRECTORY}/pngquant-arm64"
verify_binary "${RESOURCE_DIRECTORY}/pngquant-x86_64"
