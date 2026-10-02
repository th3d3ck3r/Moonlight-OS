#!/usr/bin/env bash
# Apply the same media-key config used by new images to the running original USB.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (( EUID != 0 )); then
  exec sudo bash "$0" "$@"
fi
id moonlight >/dev/null
command -v brightnessctl >/dev/null
command -v wpctl >/dev/null
# Avoid optional Openbox desktop/session dependencies.
dnf -y --setopt=install_weak_deps=False install openbox xprop python3
install -d -o moonlight -g moonlight /home/moonlight/.config/openbox
config=/home/moonlight/.config/openbox/rc.xml
if [[ -f "$config" ]]; then
  cp -p "$config" "$config.before-moonlight-$(date +%s)"
fi
python3 - "$ROOT/config/moonlight-os.ks" "$config" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
ks = Path(sys.argv[1]).read_text()
xml = ks.split("<<'OPENBOX'\n", 1)[1].split('\nOPENBOX', 1)[0] + '\n'
ET.fromstring(xml)
Path(sys.argv[2]).write_text(xml)
PY
chown moonlight:moonlight "$config"
install -m 0755 "$ROOT/scripts/media-keys.py" /usr/local/bin/moonlight-media-keys
python3 - "$ROOT/config/moonlight-os.ks" <<'UNITPY'
from pathlib import Path
import sys
ks = Path(sys.argv[1]).read_text()
unit = ks.split("<<'MEDIAUNIT'\n", 1)[1].split('\nMEDIAUNIT', 1)[0] + '\n'
Path('/etc/systemd/system/moonlight-media-keys.service').write_text(unit)
UNITPY
systemctl daemon-reload
systemctl enable --now moonlight-media-keys.service
sudo -u moonlight env DISPLAY=:0 XAUTHORITY=/home/moonlight/.Xauthority openbox --reconfigure
printf '%s\n' 'Media-key configuration installed. Return to tty1 and test brightness and volume.'
printf '%s\n' 'Test in CocoOS first, then during a stream. Use Fn if the key sends F1/F2 rather than a brightness symbol.'
