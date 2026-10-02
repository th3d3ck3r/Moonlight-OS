#!/usr/bin/env python3
"""Regenerate the offline Kickstart payload after editing native theme assets."""
from pathlib import Path
import argparse
import base64
root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--write', action='store_true', help='update the generated payload; default checks only')
args = parser.parse_args()
p = root / 'config/moonlight-os.ks'
s = p.read_text()
start = s.index('# BEGIN GENERATED CRIMSON APOLLO PAYLOAD\n')
end = s.index('chmod 0644 /usr/share/plymouth/themes/crimson-apollo/*\n', start)
payload = '# BEGIN GENERATED CRIMSON APOLLO PAYLOAD\ninstall -d -m 0755 /usr/share/plymouth/themes/crimson-apollo\n'
for name, marker in [('background.png','APOLLO_BACKGROUND'), ('apollo.png','APOLLO_APOLLO'),
                     ('crimson-apollo.plymouth','APOLLO_THEME'), ('crimson-apollo.script','APOLLO_SCRIPT')]:
    path = root / 'assets/boot/crimson-apollo' / name
    command = 'base64 -d' if name.endswith('.png') else 'cat'
    data = base64.encodebytes(path.read_bytes()).decode() if name.endswith('.png') else path.read_text()
    payload += f"{command} > /usr/share/plymouth/themes/crimson-apollo/{name} <<'{marker}'\n{data}{marker}\n"
updated = s[:start] + payload + s[end:]
if args.write:
    p.write_text(updated)
else:
    assert updated == s, 'Theme payload is stale: run scripts/sync-boot-theme.py --write'
print('Offline Plymouth payload synchronized.')
