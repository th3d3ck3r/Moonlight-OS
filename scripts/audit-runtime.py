#!/usr/bin/env python3
"""Exercise GPU selection and decode validation without physical GPU access."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
ks = (root / 'config/moonlight-os.ks').read_text()
verify = ks.split("<<'VERIFY'\n", 1)[1].split('\nVERIFY', 1)[0]
gpu = verify[verify.index('# DRM card numbering'):verify.index('\ncommand -v vulkaninfo')]

with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    drm = base / 'sys/drm'
    dev = base / 'dev/dri'
    drm.mkdir(parents=True)
    dev.mkdir(parents=True)
    for index, driver in ((0, 'simpledrm'), (1, 'i915'), (2, 'other')):
        card = drm / f'card{index}'
        (card / 'device/drm').mkdir(parents=True)
        target = base / 'drivers' / driver
        target.mkdir(parents=True)
        (card / 'device/driver').symlink_to(target)
        (dev / f'card{index}').touch()
    # Deliberately use renderD129 to detect a hidden renderD128 assumption.
    (drm / 'card1/device/drm/renderD129').touch()
    (dev / 'renderD129').touch()
    binary = base / 'bin'
    binary.mkdir()
    vainfo = binary / 'vainfo'
    vainfo.write_text('''#!/bin/bash
[[ "$*" == *renderD129* ]] || exit 90
case "$VA_CASE" in
  decode) printf 'VAProfileH264High : VAEntrypointVLD\\nVAProfileHEVCMain10 : VAEntrypointVLD\\n' ;;
  encode) printf 'VAProfileH264High : VAEntrypointEncSlice\\nVAProfileHEVCMain : VAEntrypointEncSlice\\n' ;;
  error) printf 'VAProfileH264High : VAEntrypointVLD\\nVAProfileHEVCMain : VAEntrypointVLD\\n'; exit 1 ;;
esac
''')
    vainfo.chmod(0o755)
    body = gpu.replace('/sys/class/drm', str(drm)).replace('/dev/dri', str(dev))
    shell = '''set -u
ok=0; bad=0
pass(){ ok=$((ok+1)); }
fail(){ bad=$((bad+1)); }
''' + body + '''
printf 'RESULT %s %s %d %d\\n' "$(basename "$intel_card")" "$(basename "$render_node")" "$ok" "$bad"
'''
    for case, counts in (('decode', '5 0'), ('encode', '3 2'), ('error', '3 3')):
        env = dict(os.environ, PATH=str(binary) + ':' + os.environ['PATH'], VA_CASE=case)
        out = subprocess.check_output(['bash', '-c', shell], env=env, text=True)
        assert f'RESULT card1 renderD129 {counts}' in out, out
        print(f'GPU fixture passed: {case}')
    # Check all generated Bash helpers individually, not just the enclosing post.
    import re
    for match in re.finditer(r"cat > ([^\n]+) <<'([A-Z][A-Z0-9_]*)'\n", ks):
        marker = match[2]
        content = ks[match.end():].split('\n' + marker, 1)[0]
        if content.startswith('#!/usr/bin/env bash'):
            subprocess.run(['bash', '-n'], input=content, text=True, check=True)
    print('Generated Bash helpers passed syntax checks')

# Exercise actual Linux media events, including releases and mute repeat suppression.
import runpy
from unittest.mock import patch
media = runpy.run_path(str(root / 'scripts/media-keys.py'))
assert len(media['ACTIONS']) == 7
embedded = ks.split("<<'MEDIAKEYS'\n", 1)[1].split('\nMEDIAKEYS', 1)[0] + '\n'
assert embedded == (root / 'scripts/media-keys.py').read_text()
calls = []
with patch('subprocess.run', side_effect=lambda args, **kwargs: calls.append(args)):
    for code in media['ACTIONS']:
        for value in (0, 1, 2):
            event = media['EVENT'].pack(0, 0, 1, code, value)
            _, _, kind, actual_code, actual_value = media['EVENT'].unpack(event)
            media['dispatch'](kind, actual_code, actual_value)
    media['dispatch'](1, 30, 1)  # Ordinary A key must not run anything.
    media['dispatch'](0, 115, 1)  # Non-key event must not run anything.
assert len(calls) == 13
assert calls.count(['wpctl', 'set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle']) == 1
assert ['wpctl', 'set-volume', '-l', '1', '@DEFAULT_AUDIO_SINK@', '5%+'] in calls
assert ['sudo', 'brightnessctl', '-d', 'spi::kbd_backlight', 'set', '+10%'] in calls
assert ['sudo', 'brightnessctl', '-d', 'acpi_video0', 'set', '5%-'] in calls
print('All seven Linux media-key actions, releases and repeats passed')
