#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
TARGET_DIR="${HOME}/.grok"
TARGET_SCRIPT="${TARGET_DIR}/statusline.sh"

if [ -f "${TARGET_SCRIPT}" ]; then
    cp "${TARGET_SCRIPT}" "${SCRIPT_DIR}/statusline.sh"
    echo "✓ Synced ${TARGET_SCRIPT} -> ${SCRIPT_DIR}/statusline.sh"
else
    echo "Notice: ${TARGET_SCRIPT} does not exist yet."
fi
