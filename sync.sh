#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
TARGET_DIR="${HOME}/.grok"
TARGET_SCRIPT="${TARGET_DIR}/statusline.sh"
TARGET_CONFIG="${TARGET_DIR}/config.toml"

# 1. Sync statusline script
if [ -f "${TARGET_SCRIPT}" ]; then
    cp "${TARGET_SCRIPT}" "${SCRIPT_DIR}/statusline.sh"
    echo "✓ Synced ${TARGET_SCRIPT} -> ${SCRIPT_DIR}/statusline.sh"
fi

# 2. Sync and redact config.toml
if [ -f "${TARGET_CONFIG}" ]; then
    python3 -c '
import re, sys, os

src = sys.argv[1]
dst = sys.argv[2]
home = os.path.expanduser("~")

with open(src, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
for line in lines:
    # Redact raw API keys
    if re.search(r"api_key\s*=\s*[\"'"'"']sk-", line):
        line = re.sub(r"[\"'"'"']sk-[^\"'"'"']+[\"'"'"']", "\"${AIGO_API_KEY}\"", line)
    # Portable path replacement for home dir
    line = line.replace(home, "${HOME}")
    out.append(line)

with open(dst, "w", encoding="utf-8") as f:
    f.writelines(out)
' "${TARGET_CONFIG}" "${SCRIPT_DIR}/config.toml"
    echo "✓ Synced and sanitized ${TARGET_CONFIG} -> ${SCRIPT_DIR}/config.toml"
fi
