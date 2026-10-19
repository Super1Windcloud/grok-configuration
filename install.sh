#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
TARGET_DIR="${HOME}/.grok"
TARGET_SCRIPT="${TARGET_DIR}/statusline.sh"
TARGET_CONFIG="${TARGET_DIR}/config.toml"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
    esac
done

echo "==> Deploying Grok Build statusline..."

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] Would install ${SCRIPT_DIR}/statusline.sh -> ${TARGET_SCRIPT}"
    echo "[DRY-RUN] Would update [ui.status_line] in ${TARGET_CONFIG}"
    exit 0
fi

mkdir -p "${TARGET_DIR}"

# 1. Install statusline script
cp "${SCRIPT_DIR}/statusline.sh" "${TARGET_SCRIPT}"
chmod +x "${TARGET_SCRIPT}"
echo "✓ Installed statusline script: ${TARGET_SCRIPT}"

# 2. Update config.toml
if [ -f "${TARGET_CONFIG}" ]; then
    # Check if [ui.status_line] is already set to command
    if grep -q 'type = "command"' "${TARGET_CONFIG}" 2>/dev/null && grep -q 'statusline\.sh' "${TARGET_CONFIG}" 2>/dev/null; then
        echo "✓ ${TARGET_CONFIG} already configured with custom statusline command."
    else
        BACKUP="${TARGET_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
        cp "${TARGET_CONFIG}" "${BACKUP}"
        echo "✓ Backed up config to ${BACKUP}"

        # If [ui.status_line] exists, replace the section or instruct user
        python3 -c '
import re, sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

pattern = r"\[ui\.status_line\][^\[]*"
replacement = """[ui.status_line]
type = "command"
command = "~/.grok/statusline.sh"

"""

if re.search(pattern, content):
    new_content = re.sub(pattern, replacement, content, count=1)
else:
    new_content = content + "\n" + replacement

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
' "${TARGET_CONFIG}"
        echo "✓ Updated [ui.status_line] in ${TARGET_CONFIG}"
    fi
else
    cat << 'EOF' > "${TARGET_CONFIG}"
[ui.status_line]
type = "command"
command = "~/.grok/statusline.sh"
EOF
    echo "✓ Created ${TARGET_CONFIG} with statusline command"
fi

echo "==> Verification: Testing statusline execution..."
echo '{"cwd": "'"${PWD}"'", "model": {"display_name": "Grok 4.7"}}' | "${TARGET_SCRIPT}"
echo "==> Done! Statusline is ready for Grok Build."
