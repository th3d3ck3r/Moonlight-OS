#!/usr/bin/env python3
"""Verify the exact offline Kickstart theme payload and bounded native assets."""
from pathlib import Path
import base64
import hashlib
import re
import sys
root = Path(__file__).resolve().parent.parent
ks = (root / 'config/moonlight-os.ks').read_text()
assets = root / 'assets/boot/crimson-apollo'
for name in ('background.png', 'apollo.png', 'crimson-apollo.plymouth', 'crimson-apollo.script'):
    marker = {'background.png': 'APOLLO_BACKGROUND', 'apollo.png': 'APOLLO_APOLLO',
              'crimson-apollo.plymouth': 'APOLLO_THEME', 'crimson-apollo.script': 'APOLLO_SCRIPT'}[name]
    assert ks.count("<<'" + marker + "'") == 1
    data = ks.split("<<'" + marker + "'\n", 1)[1].split('\n' + marker + '\n', 1)[0] + '\n'
    embedded = base64.b64decode(data) if name.endswith('.png') else data.encode()
    assert embedded == (assets / name).read_bytes(), f'Kickstart payload differs: {name}'
    assert len(embedded) < 150_000
script = (assets / 'crimson-apollo.script').read_text()
for image in re.findall(r'Image\("([^"]+)"\)', script):
    assert (assets / image).is_file()
assert 'Plymouth.SetRefreshRate(20)' in script
assert 'j < bullets && j < 32' in script
assert 'j < 4096 && count < 8' in script
for required in ('rhgb plymouth.ignore-serial-consoles', 'plymouth-plugin-script',
                 'add_dracutmodules+=" plymouth "', 'sudo timeout 3 plymouth quit',
                 'After=plymouth-quit.service', 'dracut --force --kver "$KVER"'):
    assert required in ks, required
# Check all preview frames and native padding when Pillow is available.
if '--art' in sys.argv:
    from PIL import Image
    ship = Image.open(assets / 'apollo.png')
    assert ship.size == (128, 128) and ship.mode == 'RGBA'
    for degrees in range(0, 360, 5):
        rotated = ship.rotate(degrees)
        bbox = rotated.getbbox()
        assert bbox and min(bbox[:2]) > 0 and max(bbox[2:]) < 128
    preview = Image.open(assets / 'preview.gif')
    assert preview.n_frames == 72
    digests = set()
    duration = 0
    for i in range(preview.n_frames):
        preview.seek(i)
        assert preview.size == (800, 500)
        duration += preview.info['duration']
        digests.add(hashlib.sha256(preview.convert('RGB').tobytes()).digest())
    assert len(digests) == 72 and duration == 7200
print('Boot animation offline payload / integration audit passed.')
