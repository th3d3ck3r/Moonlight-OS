#!/usr/bin/env python3
"""On-demand local controls. Fixed argument vectors; no shell or background polling."""
import json
import os
import re
from pathlib import Path
import subprocess


def command(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=12, env=dict(os.environ, LC_ALL='C', LANG='C'))
    if result.returncode:
        raise RuntimeError('The hardware did not accept this operation.')
    return result.stdout


def sinks(text):
    result, active, audio = [], False, False
    for line in text.splitlines():
        clean = re.sub(r'[│├└─┬┼]', '', line).strip()
        if clean in ('Audio', 'Video', 'Settings'):
            audio = clean == 'Audio'
            active = False
            continue
        if audio and clean.startswith('Sinks:'):
            active = True; continue
        if active and re.match(r'[A-Za-z]+:', clean):
            active = False
        if active:
            match = re.match(r'(\*)?\s*(\d+)\.\s+(.+)', clean)
            if match:
                result.append(dict(id=match[2], name=re.sub(r'\s+\[.*$', '', match[3]), default=bool(match[1])))
    return result[:32]


def brightness_devices(root=Path('/sys/class')):
    result = {}
    for kind, directory in [('screen', root/'backlight'), ('keyboard', root/'leds')]:
        if not directory.exists():
            continue
        for device in sorted(directory.iterdir()):
            if kind == 'keyboard' and 'kbd_backlight' not in device.name:
                continue
            if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_:.-]{0,80}', device.name):
                continue
            try:
                maximum = int((device/'max_brightness').read_text())
                current = int((device/'brightness').read_text())
                if maximum > 0:
                    result[kind] = dict(device=device.name, percent=round(100*current/maximum))
                    break
            except (OSError, ValueError):
                pass
    return result


def snapshot():
    release = {}
    try:
        for line in Path('/etc/moonlight-os-release').read_text().splitlines():
            key, _, value = line.partition('=')
            if key in ('NAME', 'VERSION', 'TARGET', 'FEDORA'):
                release[key] = value.strip().strip('"')[:128]
    except OSError:
        pass
    state = dict(brightness=brightness_devices(), sinks=[], volume=None, muted=False,
                 os=release, kernel=os.uname().release)
    try:
        value = command(['wpctl', 'get-volume', '@DEFAULT_AUDIO_SINK@'])
        match = re.search(r'Volume:\s+([0-9.]+)', value)
        if match:
            state['volume'] = min(100, round(float(match[1])*100))
            state['muted'] = '[MUTED]' in value
        state['sinks'] = sinks(command(['wpctl', 'status', '-n']))
    except (RuntimeError, subprocess.SubprocessError, OSError):
        pass
    state.update(wifi_enabled=None, bluetooth_enabled=None, pointers=[], displays=[], idle_seconds=None)
    try:
        state['wifi_enabled'] = command(['nmcli', 'radio', 'wifi']).strip() == 'enabled'
    except (RuntimeError, subprocess.SubprocessError, OSError):
        pass
    try:
        value = command(['bluetoothctl', 'show'])
        if 'Powered:' in value:
            state['bluetooth_enabled'] = bool(re.search(r'Powered:\s+yes', value))
    except (RuntimeError, subprocess.SubprocessError, OSError):
        pass
    try:
        state['displays'] = displays(command(['xrandr', '--query']))
    except (RuntimeError, subprocess.SubprocessError, OSError):
        pass
    try:
        for line in command(['xinput', 'list', '--short']).splitlines():
            match = re.search(r'(.+?)\s+id=(\d+).*slave\s+pointer', line)
            if not match or 'XTEST' in line:
                continue
            identity = match[2]
            props = command(['xinput', 'list-props', identity])
            item = dict(id=identity, name=re.sub(r'^[^A-Za-z0-9]+', '', match[1]).strip()[:80])
            for key, prop in [('speed','libinput Accel Speed'), ('natural','libinput Natural Scrolling Enabled'), ('tap','libinput Tapping Enabled')]:
                value = re.search(re.escape(prop)+r' \(\d+\):\s*(-?[\d.]+)', props)
                if value:
                    item[key] = float(value[1])
            if len(item)>2:
                state['pointers'].append(item)
            if len(state['pointers'])>=8:
                break
    except (RuntimeError, subprocess.SubprocessError, OSError):
        pass
    return state


def displays(text):
    result, output = [], None
    for line in text.splitlines():
        connected = re.match(r'^(\S+) connected', line)
        if connected:
            output = connected[1]
        elif line and not line[0].isspace():
            output = None
        mode = re.match(r'^\s+(\d{3,5}x\d{3,5})\s+(.+)', line)
        if not output or not mode or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}', output):
            continue
        for rate in mode[2].split():
            clean = rate.strip('*+')
            if re.fullmatch(r'\d{1,3}(?:\.\d{1,3})?', clean):
                result.append(dict(id=output+'/'+mode[1]+'/'+clean, name=output+' · '+mode[1]+' @ '+clean+' Hz', output=output, mode=mode[1], rate=clean, current='*' in rate))
    return result[:64]


def percent(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{1,3}', value) or not 0 <= int(value) <= 100:
        raise ValueError('Choose a value from 0 to 100.')
    return int(value)


def execute(request, state, answer=None):
    action, value = request.get('action'), request.get('id', '')
    if action == 'center-list':
        pass
    elif action == 'center-volume':
        command(['wpctl', 'set-volume', '-l', '1', '@DEFAULT_AUDIO_SINK@', str(percent(value))+'%'])
    elif action == 'center-mute':
        command(['wpctl', 'set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle'])
    elif action == 'center-output':
        if not any(item['id'] == value for item in state.get('sinks', [])):
            raise ValueError('Select an available audio output.')
        command(['wpctl', 'set-default', value])
    elif action in ('center-screen', 'center-keyboard'):
        kind = action.split('-')[1]
        device = state.get('brightness', {}).get(kind)
        if not device:
            raise ValueError('This brightness control is unavailable.')
        level = percent(value)
        if kind == 'screen':
            level = max(5, level)
        command(['sudo', 'brightnessctl', '-d', device['device'], 'set', str(level)+'%'])
    elif action in ('center-reboot', 'center-poweroff'):
        if request.get('confirm') is not True:
            raise ValueError('Confirm the power operation first.')
        command(['sudo', 'systemctl', action.split('-')[1]])
    elif action in ('center-wifi-radio', 'center-bt-radio'):
        if value not in ('on', 'off'):
            raise ValueError('Choose on or off.')
        command(['nmcli','radio','wifi',value] if action=='center-wifi-radio' else ['bluetoothctl','power',value])
    elif action == 'center-airpods':
        if value not in ('low-latency','quality'):
            raise ValueError('Choose a supported audio preference.')
        command(['airpods-mode', value])
    elif action == 'center-test-sound':
        command(['speaker-test','-t','sine','-f','440','-l','1','-P','1','-c','2','-p','50000'])
    elif action == 'center-idle':
        if value not in ('0','300','600','1800'):
            raise ValueError('Choose a supported idle timeout.')
        if value=='0':
            command(['xset','s','off']); command(['xset','-dpms'])
        else:
            command(['xset','s','blank']); command(['xset','s',value]); command(['xset','+dpms']); command(['xset','dpms','0','0',value])
    elif action in ('center-pointer-speed','center-pointer-natural','center-pointer-tap'):
        identity, separator, setting = value.partition(':')
        pointer=next((p for p in state.get('pointers',[]) if p['id']==identity),None)
        key=action.rsplit('-',1)[1]
        if not separator or not pointer or key not in pointer:
            raise ValueError('Select a supported pointer control.')
        if key=='speed':
            if not re.fullmatch(r'-?(?:0(?:\.\d{1,2})?|1(?:\.0{1,2})?)',setting):
                raise ValueError('Pointer speed must be between -1 and 1.')
        elif setting not in ('0','1'):
            raise ValueError('Choose on or off.')
        prop={'speed':'libinput Accel Speed','natural':'libinput Natural Scrolling Enabled','tap':'libinput Tapping Enabled'}[key]
        command(['xinput','set-prop',identity,prop,setting])
    elif action == 'center-display':
        selected=next((p for p in state.get('displays',[]) if p['id']==value),None)
        previous=next((p for p in state.get('displays',[]) if selected and p['output']==selected['output'] and p['current']),None)
        if not selected or not previous or answer is None:
            raise ValueError('Select an available mode with a known rollback mode.')
        def apply(mode):
            command(['xrandr','--output',mode['output'],'--mode',mode['mode'],'--rate',mode['rate']])
        accepted=False
        try:
            apply(selected)
            accepted=answer('Keep this display mode? Type yes within 15 seconds; otherwise it reverts.', timeout=15).strip().lower()=='yes'
        finally:
            if not accepted:
                apply(previous)
        if not accepted:
            return dict(state=snapshot(),status='Display mode reverted.')
    elif action == 'center-frontend':
        if value not in ('vibemis','artemis','pegasus','moonlight','cocoos'):
            raise ValueError('Select an available frontend.')
        command(['sudo','-n','moonlight-os-client',value])
        return dict(state=snapshot(),status='Frontend saved. End any stream and reboot to apply it.')
    elif action == 'center-restart-frontend':
        if request.get('confirm') is not True:
            raise ValueError('Confirm restarting the frontend.')
        # Queue recovery after this request returns; restarting tty1 preserves tty2.
        command(['sudo','-n','systemd-run','--on-active=2','--collect','systemctl','restart','getty@tty1.service'])
    elif action == 'center-report':
        report = dict(kernel=os.uname().release, brightness_devices=list(brightness_devices()),
                      render_nodes=[p.name for p in Path('/dev/dri').glob('renderD*')],
                      audio_available=state.get('volume') is not None)
        folder = Path.home()/'.local/state/moonlight-os'
        folder.mkdir(parents=True, exist_ok=True, mode=0o700)
        target = folder/'eclipse-diagnostics.json'
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, 'w') as file:
            json.dump(report, file, indent=2)
        return dict(state=snapshot(), status='Redacted report saved to '+str(target))
    else:
        raise ValueError('Unsupported control-center action.')
    return dict(state=snapshot(), status='Ready')
