#!/usr/bin/env bash
# Native Fedora script-engine test only; no image build, DRM or user-drive writes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ "${1:-}" == --install-tools ]]; then
  dnf -y install gcc plymouth plymouth-plugin-script plymouth-scripts python3-pillow
fi
python3 "$ROOT/scripts/audit-boot-animation.py" --art
plugin=$(find /usr/lib64/plymouth /usr/lib/plymouth -name script.so -print -quit 2>/dev/null || true)
[[ -n "$plugin" && -f "$plugin" ]]
# Audit all hook names against the installed plugin, rather than trusting stubs.
python3 - "$ROOT" "$plugin" <<'PY'
from pathlib import Path
import re
import sys
root, plugin = map(Path, sys.argv[1:])
data = plugin.read_bytes()
for name in set(re.findall(r'Plymouth\.(Set\w+)\(', (root/'assets/boot/crimson-apollo/crimson-apollo.script').read_text())):
    assert name.encode() + b'\0' in data, f'Unsupported native callback: {name}'
PY
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cc -Wall -Wextra -Werror "$ROOT/scripts/audit-plymouth-native.c" -ldl -o "$work/audit"
for dimensions in '320 200' '640 480' '1024 640' '1920 1080' '2560 1600'; do
  # Intentional split of this fixed, locally declared dimension pair.
  "$work/audit" "$plugin" "$ROOT/assets/boot/crimson-apollo" $dimensions
done
