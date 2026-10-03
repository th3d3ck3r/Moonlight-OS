#!/usr/bin/env python3
"""Keep the offline installer payload byte-identical to reviewed helper sources."""
import argparse
import base64
import textwrap
from pathlib import Path

root = Path(__file__).resolve().parents[1]
ks = root / 'config/moonlight-os.ks'
pairs = {
    'STREAMING_TUNE': 'scripts/streaming-tune.py',
    'WIFIMENU': 'scripts/wifi-menu.sh',
    'ECLIPSE_UPDATER': 'scripts/eclipseos-update.py',
    'ECLIPSE_UPDATE_MENU': 'scripts/update-menu.sh',
    'ECLIPSE_UPDATE_BASE': 'updates/base.json',
    'ECLIPSE_UPDATE_RECOVERY': 'updates/eclipseos-update-recovery.service',
    'VIBEMIS_PATCH_B64': 'patches/vibemis-crimson.patch',
    'CONTROLCENTER': 'scripts/control-center.py',
    'SYSTEMCONTROLS': 'scripts/system-controls.py',
    'BTMENU': 'scripts/bluetooth-menu.py',
    'FRONTENDS_LOCK': 'SOURCES.lock',
    'FRONTENDS_INSTALL': 'scripts/install-frontends.sh',
    'FRONTENDS_LAUNCH': 'scripts/frontend-launch.sh',
    'FRONTENDS_SELECT': 'scripts/frontend-select.sh',
}
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
text = ks.read_text()
for marker, source in pairs.items():
    start = text.index("<<'" + marker + "'\n") + len(marker) + 5
    end = text.index('\n' + marker + '\n', start) + 1
    payload = (root / source).read_text()
    if marker == 'VIBEMIS_PATCH_B64':
        payload = '\n'.join(textwrap.wrap(base64.b64encode((root / source).read_bytes()).decode(), 76)) + '\n'
    if args.check:
        assert text[start:end] == payload, f'{source} differs from its installed payload'
    else:
        text = text[:start] + payload + text[end:]
if not args.check:
    ks.write_text(text)
print('Frontend and Bluetooth payloads match their sources.')
