#!/bin/bash

# The pngquant source tag does not ship Cargo.lock. Keep the reviewed resolver
# lock in this project and require the vendor checkout to match it exactly.
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INPUT_LOCKFILE="${SCRIPT_DIRECTORY}/pngquant-3.0.3-Cargo.lock"
readonly VENDOR_LOCKFILE="${SCRIPT_DIRECTORY}/../.build/pngquant/Cargo.lock"

[[ -f "${INPUT_LOCKFILE}" ]] || { echo "Missing reviewed pngquant lockfile: ${INPUT_LOCKFILE}" >&2; exit 1; }
[[ -f "${VENDOR_LOCKFILE}" ]] || { echo "Missing pngquant vendor lockfile: ${VENDOR_LOCKFILE}" >&2; exit 1; }
cmp -s "${INPUT_LOCKFILE}" "${VENDOR_LOCKFILE}" || {
    echo "pngquant vendor Cargo.lock differs from the reviewed lockfile." >&2
    exit 1
}
