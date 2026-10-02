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

# Exercise the seven media-key actions against recording tools; no real device writes.
import xml.etree.ElementTree as ET
xml = ks.split("<<'OPENBOX'\n", 1)[1].split("\nOPENBOX", 1)[0]
ns = {"o": "http://openbox.org/3.4/rc"}
bindings = ET.fromstring(xml).findall("o:keyboard/o:keybind", ns)
assert len(bindings) == 7
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    for name in ("brightnessctl", "wpctl"):
        tool = base / name
        tool.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$KEY_LOG"\n')
        tool.chmod(0o755)
    sudo = base / "sudo"
    sudo.write_text('#!/bin/bash\nexec "$@"\n')
    sudo.chmod(0o755)
    log = base / "log"
    env = dict(os.environ, PATH=str(base) + ':' + os.environ['PATH'], KEY_LOG=str(log))
    for binding in bindings:
        command = binding.find("o:action/o:command", ns).text
        subprocess.run(['bash', '-c', command], env=env, check=True)
    actions = log.read_text().splitlines()
    assert '-d acpi_video0 set +5%' in actions
    assert '-d acpi_video0 set 5%-' in actions
    assert 'set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+' in actions
    assert 'set-volume @DEFAULT_AUDIO_SINK@ 5%-' in actions
    assert 'set-mute @DEFAULT_AUDIO_SINK@ toggle' in actions
    assert '-d spi::kbd_backlight set +10%' in actions
    assert '-d spi::kbd_backlight set 10%-' in actions
print('All seven media-key command actions passed')
