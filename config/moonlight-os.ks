#version=DEVEL
shutdown
lang en_US.UTF-8
keyboard us
timezone America/New_York --utc
selinux --enforcing
firewall --enabled --service=mdns
network --bootproto=dhcp --device=link --activate --onboot=yes --hostname=moonlight-os

url --mirrorlist="https://mirrors.fedoraproject.org/metalink?repo=fedora-44&arch=x86_64"
repo --name=updates --mirrorlist="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f44&arch=x86_64"
repo --name=rpmfusion-free --baseurl="https://download1.rpmfusion.org/free/fedora/releases/44/Everything/x86_64/os/"
repo --name=rpmfusion-free-updates --baseurl="https://download1.rpmfusion.org/free/fedora/updates/44/x86_64/"
repo --name=rpmfusion-nonfree --baseurl="https://download1.rpmfusion.org/nonfree/fedora/releases/44/Everything/x86_64/os/"
repo --name=rpmfusion-nonfree-updates --baseurl="https://download1.rpmfusion.org/nonfree/fedora/updates/44/x86_64/"

zerombr
clearpart --all --initlabel --disklabel=gpt
part /boot/efi --fstype=efi --size=512
part /boot --fstype=ext4 --size=1024
part / --fstype=xfs --size=11000 --grow
bootloader --timeout=1 --append="quiet rhgb plymouth.ignore-serial-consoles rd.driver.pre=i915 mem_sleep_default=s2idle pcie_port_pm=off console=tty0 console=ttyS0,115200n8 systemd.show_status=true"

rootpw --lock
user --name=moonlight --groups=wheel,video,input,audio --lock

%packages --excludedocs
@core
plymouth
plymouth-scripts
plymouth-plugin-script
plymouth-plugin-label
dejavu-sans-fonts
kernel
kernel-core
kernel-modules
kernel-modules-extra
linux-firmware
microcode_ctl
sudo
bash-completion
firewalld
NetworkManager
NetworkManager-wifi
NetworkManager-tui
wpa_supplicant
iw
wireless-regdb
bluez
bluez-libs
steam-devices
joystick-support
evtest
pipewire
pipewire-pulseaudio
wireplumber
alsa-utils
xorg-x11-server-Xorg
xorg-x11-xinit
xorg-x11-xauth
openbox
python3
python3-pexpect
python3-dbus
glibc-langpack-en
unzip
file
gstreamer1
gstreamer1-plugins-base
xorg-x11-drv-libinput
libinput-utils
xinput
xrandr
xset
xprop
mesa-demos
glx-utils
vulkan-tools
brightnessctl
upower
thermald
linuxconsoletools
mesa-dri-drivers
mesa-libGL
mesa-libEGL
mesa-vulkan-drivers
libdrm
libva
libva-utils
libva-intel-driver
intel-media-driver
ffmpeg-libs
sdl2-compat
SDL2_ttf
opus
libplacebo
qt6-qtbase-gui
qt6-qtdeclarative
qt6-qtsvg
qt6-qtwebsockets
qt6-qtmultimedia
pciutils
usbutils
ethtool
iproute
procps-ng
util-linux
cloud-utils-growpart
xfsprogs
zram-generator-defaults
openssh-server
rsync
curl
ca-certificates
git
make
gcc
gcc-c++
patch
dkms
kernel-devel
kernel-headers
kmod
pkgconf-pkg-config
openssl
openssl-devel
wget1-wget
xz
sdl2-compat-devel
SDL2_ttf-devel
ffmpeg-devel
libva-devel
libvdpau-devel
opus-devel
pulseaudio-libs-devel
alsa-lib-devel
libdrm-devel
libX11-devel
mesa-libEGL-devel
mesa-libGL-devel
libplacebo-devel
qt6-qtbase-devel
qt6-qtsvg-devel
qt6-qtdeclarative-devel
qt6-qtwebsockets-devel
qt6-qtmultimedia-devel
%end

%post --erroronfail --log=/root/moonlight-os-post.log
set -euxo pipefail

install -d -m 0755 /usr/local/libexec/moonlight-os /usr/local/share/moonlight-os

cat > /etc/moonlight-os-release <<'META'
NAME="EclipseOS"
VERSION="0.3-dev"
TARGET="MacBookPro14,1"
HOST_TARGET="Vibepollo/Sunshine"
FEDORA="44"
META

# Fedora 44 base media contains a known-broken igt-gpu-tools 2.2 build
# requiring libproc2.so.0. Install the fixed/current package from updates here.
dnf -y --refresh install igt-gpu-tools
command -v intel_gpu_top >/dev/null
rpm -q igt-gpu-tools

install -d /etc/NetworkManager/conf.d /etc/modprobe.d
cat > /etc/NetworkManager/conf.d/99-moonlight-wifi.conf <<'NM'
[connection]
wifi.powersave=2
NM
cat > /etc/modprobe.d/brcmfmac-moonlight.conf <<'BRCM'
options brcmfmac roamoff=1
BRCM

sed -ri 's/^#?AutoEnable=.*/AutoEnable=true/' /etc/bluetooth/main.conf || true
systemctl enable bluetooth.service NetworkManager.service firewalld.service thermald.service
systemctl disable sshd.service || true

# DualSense / PlayStation controller support (USB + Bluetooth).
install -d /etc/modules-load.d
printf 'hid_playstation\n' > /etc/modules-load.d/moonlight-dualsense.conf

cat > /usr/local/bin/dualsense-check <<'DUALCHECK'
#!/usr/bin/env bash
set -u
echo "EclipseOS DualSense check"
modprobe hid_playstation 2>/dev/null || true
if lsusb 2>/dev/null | grep -Eqi '054c:0ce6|Sony.*(DualSense|Wireless Controller)'; then
  echo "[OK] DualSense detected over USB"
elif bluetoothctl devices 2>/dev/null | grep -Eqi 'DualSense|Wireless Controller'; then
  echo "[OK] DualSense known to Bluetooth"
else
  echo "[INFO] No DualSense currently detected"
fi
modinfo hid_playstation >/dev/null 2>&1 && echo "[OK] hid-playstation available" || echo "[FAIL] hid-playstation missing"
command -v evtest >/dev/null 2>&1 && echo "[OK] evtest installed" || echo "[FAIL] evtest missing"
DUALCHECK
chmod 0755 /usr/local/bin/dualsense-check

cat > /usr/local/bin/dualsense-pair <<'DUALPAIR'
#!/usr/bin/env bash
exec /usr/local/bin/moonlight-bluetooth --pair
DUALPAIR
chmod 0755 /usr/local/bin/dualsense-pair

# Recovery/debug consoles use the EclipseOS black + red theme.
cat > /etc/profile.d/00-moonlight-red-terminal.sh <<'THEME'
# EclipseOS console theme: black background, red foreground.
if [[ $- == *i* ]]; then
  case "${TERM:-}" in
    linux)
      setterm --foreground red --background black --clear all 2>/dev/null || true
      ;;
    xterm*|screen*|tmux*)
      printf '\033[40m\033[31m'
      ;;
  esac
  PS1='\[\e[31m\]\u@\h:\w\$ \[\e[31m\]'
  export LESS='-R'
fi
THEME
chmod 0644 /etc/profile.d/00-moonlight-red-terminal.sh

# AirPods Pro 2 are playback-only on EclipseOS.
# Disable HSP/HFP entirely and let WirePlumber choose A2DP profiles by latency.
install -d -m 0755 /home/moonlight/.config/wireplumber/wireplumber.conf.d
cat > /home/moonlight/.config/wireplumber/wireplumber.conf.d/51-moonlight-airpods.conf <<'WPCONF'
monitor.bluez.properties = {
  override.bluez5.roles = [ a2dp_sink ]
  override.bluez5.codecs = [ sbc sbc_xq aac ]
  bluez5.enable-sbc-xq = true
}
monitor.bluez.rules = [
  {
    matches = [
      { device.name = "~bluez_card.*" }
    ]
    actions = {
      update-props = {
        bluez5.auto-connect = [ a2dp_sink ]
      }
    }
  }
]
wireplumber.profiles = {
  main = {
    monitor.bluez.seat-monitoring = disabled
  }
}
wireplumber.settings = {
  bluetooth.autoswitch-to-headset-profile = false
  bluetooth.profile-preference = "latency"
}
WPCONF
chown -R moonlight:moonlight /home/moonlight/.config

# Initialize the confirmed SPI keyboard LED; systemd may restore its saved state afterward.
install -d /etc/udev/rules.d
cat > /etc/udev/rules.d/90-moonlight-keyboard-backlight.rules <<'KBDRULE'
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="spi::kbd_backlight", ATTR{brightness}="128"
KBDRULE

# MacBookPro14,1 X11 input defaults: clickfinger right-click, tap-to-click, natural scrolling.
install -d -m 0755 /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/40-moonlight-macbook-input.conf <<'XINPUTCONF'
Section "InputClass"
    Identifier "EclipseOS Apple SPI Touchpad"
    MatchProduct "Apple SPI Touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "ClickMethod" "clickfinger"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
EndSection
XINPUTCONF

# DualSense USB exposes an ALSA audio card (speaker/mic/headset jack).
# Disable only that audio card by Sony VID/PID; hid-playstation remains active.
cat > /home/moonlight/.config/wireplumber/wireplumber.conf.d/52-disable-dualsense-audio.conf <<'DSAUDIO'
monitor.alsa.rules = [
  {
    matches = [
      {
        device.bus = "usb"
        device.vendor.id = 1356
        device.product.id = 3302
      }
    ]
    actions = {
      update-props = {
        device.disabled = true
      }
    }
  }
]
DSAUDIO
chown moonlight:moonlight /home/moonlight/.config/wireplumber/wireplumber.conf.d/52-disable-dualsense-audio.conf

cat > /usr/local/bin/airpods-mode <<'AIRMODE'
#!/usr/bin/env bash
set -euo pipefail
CONF="$HOME/.config/wireplumber/wireplumber.conf.d/51-moonlight-airpods.conf"

case "${1:-status}" in
  low-latency|latency)
    sed -i 's/bluetooth.profile-preference = "quality"/bluetooth.profile-preference = "latency"/' "$CONF"
    echo "AirPods Pro 2: LOW LATENCY mode selected."
    ;;
  quality)
    sed -i 's/bluetooth.profile-preference = "latency"/bluetooth.profile-preference = "quality"/' "$CONF"
    echo "AirPods Pro 2: QUALITY mode selected."
    ;;
  status)
    mode=$(grep -o 'bluetooth.profile-preference = "[^"]*"' "$CONF" 2>/dev/null | cut -d'"' -f2 || true)
    echo "AirPods Pro 2 mode: ${mode:-unknown}"
    echo "Microphone/headset profiles: disabled"
    exit 0
    ;;
  *)
    echo "usage: airpods-mode {low-latency|quality|status}" >&2
    exit 2
    ;;
esac

systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
AIRMODE
chmod 0755 /usr/local/bin/airpods-mode

cat > /usr/local/bin/airpods-pair <<'AIRPAIR'
#!/usr/bin/env bash
exec /usr/local/bin/moonlight-bluetooth --pair --airpods
AIRPAIR
chmod 0755 /usr/local/bin/airpods-pair

cat > /usr/local/bin/moonlight-wifi <<'WIFIMENU'
#!/usr/bin/env bash
set -u
while true; do
  clear
  printf '\033[40m\033[31m'
  active=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1; exit}')
  cat <<EOF
WI-FI
=====

Active: ${active:-none}

  1) Connect / change Wi-Fi
  2) Prefer 5 GHz on active Wi-Fi (recommended for Moonlight + Bluetooth)
  3) Automatic Wi-Fi band
  4) Show Wi-Fi status
  0) Back

EOF
  printf 'Choose: '
  read -r choice
  case "$choice" in
    1) nmtui-connect ;;
    2)
      active=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
      if [[ -n "$active" ]]; then
        sudo nmcli connection modify "$active" 802-11-wireless.band a
        sudo nmcli connection down "$active" || true
        sudo nmcli connection up "$active" || true
        echo "5 GHz preferred for $active."
      else
        echo "Connect to Wi-Fi first."
      fi
      read -r -p "Press Enter..." _
      ;;
    3)
      active=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
      if [[ -n "$active" ]]; then
        sudo nmcli connection modify "$active" 802-11-wireless.band ""
        echo "Automatic band selection restored."
      else
        echo "No active Wi-Fi connection."
      fi
      read -r -p "Press Enter..." _
      ;;
    4)
      nmcli device wifi list
      echo
      iw dev 2>/dev/null || true
      read -r -p "Press Enter..." _
      ;;
    0) exit 0 ;;
  esac
done
WIFIMENU
chmod 0755 /usr/local/bin/moonlight-wifi

mkdir -p /usr/local/libexec/moonlight-os
cat > /usr/local/libexec/moonlight-os/control-center.py <<'CONTROLCENTER'
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
        command(['xset','s',value]); command(['xset','dpms','0','0',value])
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
CONTROLCENTER
chmod 0755 /usr/local/libexec/moonlight-os/control-center.py
cat > /usr/local/libexec/moonlight-os/system-controls.py <<'SYSTEMCONTROLS'
#!/usr/bin/env python3
"""Private JSON pipe for Vibemis Wi-Fi/BlueZ controls; no passwords in argv/logs."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import signal
import select
import subprocess
import sys
import time
from pathlib import Path
import pexpect


def emit(**event):
    print(json.dumps(event, ensure_ascii=True), file=sys.__stdout__, flush=True)


def read():
    line = sys.stdin.readline(65537)
    if not line or len(line) > 65536:
        raise EOFError()
    value = json.loads(line)
    if not isinstance(value, dict):
        raise ValueError('Invalid request')
    return value


def answer(prompt, timeout=90):
    emit(prompt=prompt)
    if not select.select([sys.stdin], [], [], timeout)[0]:
        raise RuntimeError('Confirmation timed out.')
    value = read()
    if value.get('action') != 'answer':
        raise EOFError()
    text = value.get('value', '')
    if not isinstance(text, str) or len(text) > 4096 or any(c in text for c in '\r\n\x00'):
        raise ValueError('Invalid response')
    return text


def run(argv):
    env = dict(os.environ, LC_ALL='C', LANG='C')
    result = subprocess.run(argv, env=env, text=True, encoding='utf-8', errors='replace',
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    if result.returncode:
        raise RuntimeError('The system could not complete this operation. Check the adapter and try again.')
    return result.stdout


def fields(line):
    parts, text, escaped = [], '', False
    for char in line:
        if escaped:
            text += char; escaped = False
        elif char == '\\':
            escaped = True
        elif char == ':':
            parts.append(text); text = ''
        else:
            text += char
    parts.append(text)
    return parts


def wifi_rows(text):
    result, seen = [], set()
    for line in text.splitlines():
        row = fields(line)
        if len(row) != 6:
            continue
        active, name, address, strength, security, device = row
        if not re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', address):
            continue
        if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.:-]{0,31}', device):
            continue
        identity = device + '/' + address.upper()
        if identity in seen or not name:
            continue
        seen.add(identity)
        result.append(dict(id=identity, name=name, address=address.upper(), device=device,
                           detail=f'{strength}% · {security or "Open"}', connected=active == '*'))
        if len(result) == 64:
            break
    return result


class Controls:
    def __init__(self):
        source = os.environ.get('MOONLIGHT_BT_HELPER', '/usr/local/bin/moonlight-bluetooth')
        loader = importlib.machinery.SourceFileLoader('moonlight_bt_controls', source)
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.bt = importlib.util.module_from_spec(spec); loader.exec_module(self.bt)
        self.agent = None
        self.items = []
        self.mode = None
        self.wifi_child = None
        self.center_state = {}

    def wifi_list(self, scan=False):
        self.mode = "wifi"
        self.items = wifi_rows(run(['nmcli', '-t', '--escape', 'yes', '-f',
                                   'IN-USE,SSID,BSSID,SIGNAL,SECURITY,DEVICE', 'device', 'wifi', 'list',
                                   '--rescan', 'yes' if scan else 'no']))
        return self.items

    def selected(self, value):
        return next((item for item in self.items if item['id'] == value), None)

    def wifi_connect(self, item):
        env = dict(os.environ, LC_ALL='C', LANG='C')
        self.wifi_child = pexpect.spawn('nmcli', ['--ask', 'device', 'wifi', 'connect',
                                       item['address'], 'ifname', item['device']], env=env,
                                       encoding='utf-8', codec_errors='replace', echo=False, timeout=40)
        child = self.wifi_child
        try:
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                event = child.expect([r'Password[^\r\n]*:', r'successfully activated', pexpect.EOF, pexpect.TIMEOUT], timeout=40)
                if event == 0:
                    child.sendline(answer('Wi-Fi password for ' + item['name']))
                elif event == 1:
                    child.expect(pexpect.EOF, timeout=5)
                    return
                else:
                    raise RuntimeError('Wi-Fi connection failed. Check the password or use tty2 for advanced/enterprise networks.')
            raise RuntimeError('Wi-Fi connection timed out.')
        finally:
            if child.isalive():
                child.terminate(force=True)
            self.wifi_child = None

    def bt_list(self):
        self.mode = 'bt'
        self.items = self.bt.backend().rows()
        return dict(items=self.items,status=('Bluetooth radio is off. Enable it in System Controls.' if not self.bt.backend().powered else 'Ready' if self.items else 'No devices found. Put the device in pairing mode and scan.'))

    def bt_scan(self):
        self.mode = 'bt'
        def progress(rows, status):
            self.items = rows
            emit(items=rows, status=status)
        self.items = self.bt.backend().scan(progress)
        return dict(items=self.items,status='Scan complete' if self.items else 'No devices found. Check pairing mode and retry.')

    def execute(self, request):
        action = request.get('action')
        if isinstance(action, str) and action.startswith('center-'):
            import importlib.util
            source = Path(__file__).with_name('control-center.py')
            spec = importlib.util.spec_from_file_location('eclipse_control_center', source)
            module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
            result = module.execute(request, self.center_state, answer=answer)
            self.center_state = result['state']
            return result
        if action in ('wifi-list', 'wifi-scan'):
            return self.wifi_list(action == 'wifi-scan')
        if action in ('bt-list', 'bt-scan'):
            return self.bt_list() if action == 'bt-list' else self.bt_scan()
        if not isinstance(action, str) or not action.startswith(str(self.mode) + '-'):
            raise ValueError('Select a listed network or device first.')
        item = self.selected(request.get('id'))
        if item is None:
            raise ValueError('Select a listed network or device first.')
        if action == 'wifi-connect':
            self.wifi_connect(item)
            return self.wifi_list()
        if action == 'wifi-disconnect':
            run(['nmcli', 'device', 'disconnect', item['device']])
            return self.wifi_list()
        if action == 'bt-connect':
            self.bt.ready()
            if self.agent is None:
                self.agent = self.bt.Agent()
            if self.bt.properties(item['address']).get('Paired') != 'yes':
                emit(status='Pairing… respond to any confirmation prompt')
                if not self.agent.pair(item['address'], answer=answer):
                    raise RuntimeError('Pairing was not completed. No saved bond was removed.')
                if self.bt.properties(item['address']).get('Paired') != 'yes':
                    raise RuntimeError('Pairing was not saved. Put the device back in pairing mode.')
            emit(status='Connecting and checking device services…')
            if not self.bt.connect(item['address']):
                raise RuntimeError('The device did not connect. Wake it and retry.')
        elif action == 'bt-disconnect':
            self.bt.backend().operate(item['address'], 'disconnect')
            if self.bt.properties(item['address']).get('Connected') == 'yes':
                raise RuntimeError('The device is still connected.')
        elif action == 'bt-forget':
            if request.get('confirm') is not True:
                raise ValueError('Forgetting a device requires confirmation.')
            self.bt.backend().operate(item['address'], 'forget')
            if any(row['address'] == item['address'] for row in self.bt.backend().rows()):
                raise RuntimeError('The device could not be forgotten.')
        else:
            raise ValueError('Unsupported operation')
        return self.bt_list()

    def close(self):
        if getattr(self.bt, '_backend', None) is not None:
            self.bt.backend().close()
        if self.wifi_child is not None and self.wifi_child.isalive():
            self.wifi_child.terminate(force=True)
        if self.agent is not None:
            self.agent.close(); self.agent = None


def main():
    controls = Controls()
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(SystemExit()))
    try:
        while True:
            try:
                request = read()
                # Legacy helper presentation never enters the JSON/credential pipe.
                with contextlib.redirect_stdout(io.StringIO()):
                    items = controls.execute(request)
                emit(**items, done=True) if isinstance(items, dict) else emit(items=items, status='Ready' if items else 'No devices found. Check pairing mode and scan again.', done=True)
            except (EOFError, KeyboardInterrupt):
                break
            except (ImportError, RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError, pexpect.ExceptionPexpect) as error:
                emit(error=str(error) if isinstance(error, (RuntimeError, ValueError)) else 'The operation failed. Retry or use the diagnostic shell.', done=True)
    finally:
        controls.close()


if __name__ == '__main__':
    main()
SYSTEMCONTROLS
chmod 0755 /usr/local/libexec/moonlight-os/system-controls.py

cat > /usr/local/bin/moonlight-bluetooth <<'BTMENU'
#!/usr/bin/env python3
"""Guided BlueZ pairing with one live agent; never filter by controller brand."""
import argparse
import re
import subprocess
import time
import pexpect
from pathlib import Path

ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
MAC = r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'


def clean(text):
    return ANSI.sub('', text).replace('\r', '')


def ctl(*args):
    result = subprocess.run(['bluetoothctl', '--timeout', '12', *args],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=16)
    return clean(result.stdout)


def valid_mac(address):
    if not re.fullmatch(MAC, address):
        raise ValueError('Invalid Bluetooth address')
    return address.upper()


def properties(address):
    props = backend().device(address)[1]
    return {key: 'yes' if props.get(key) else 'no' for key in ('Paired', 'Trusted', 'Connected')}


class BlueZ:
    """One system-bus connection and one bulk snapshot, never N CLI timeouts."""
    def __init__(self, bus=None):
        import dbus
        self.dbus = dbus
        self.bus = bus or dbus.SystemBus(private=True)
        self.scanning = False
        self.adapter = None

    def interface(self, path, name):
        return self.dbus.Interface(self.bus.get_object('org.bluez', path, introspect=False), name)

    def objects(self):
        try:
            return self.interface('/', 'org.freedesktop.DBus.ObjectManager').GetManagedObjects(timeout=5)
        except self.dbus.DBusException as error:
            raise RuntimeError('Bluetooth service unavailable: ' + error.get_dbus_name()) from None

    def rows(self):
        result = []
        objects=self.objects()
        adapters=[interfaces['org.bluez.Adapter1'] for interfaces in objects.values() if 'org.bluez.Adapter1' in interfaces]
        if not adapters:
            raise RuntimeError('No Bluetooth adapter found. Check Adapter status in the recovery console.')
        self.powered=any(p.get('Powered') for p in adapters)
        for path, interfaces in objects.items():
            p = interfaces.get('org.bluez.Device1')
            if not p or not re.fullmatch(MAC, str(p.get('Address', ''))):
                continue
            result.append(dict(id=str(p['Address']).upper(), address=str(p['Address']).upper(),
                               name=str(p.get('Alias') or p.get('Name') or p['Address'])[:80],
                               detail='Paired' if p.get('Paired') else 'Not paired',
                               paired=bool(p.get('Paired')), trusted=bool(p.get('Trusted')),
                               connected=bool(p.get('Connected')), ready=bool(p.get('ServicesResolved'))))
        return sorted(result, key=lambda item: (not item['connected'], not item['paired'], item['name']))[:64]

    def device(self, address):
        address = valid_mac(address)
        for path, interfaces in self.objects().items():
            props = interfaces.get('org.bluez.Device1', {})
            if str(props.get('Address', '')).upper() == address:
                return str(path), props
        raise ValueError('Device is no longer available. Scan again.')

    def prepare(self):
        subprocess.run(['sudo', '-n', 'systemctl', 'start', 'bluetooth.service'], check=True, timeout=8)
        subprocess.run(['sudo', '-n', 'rfkill', 'unblock', 'bluetooth'], check=True, timeout=5)
        adapters = [(str(path), p['org.bluez.Adapter1']) for path, p in self.objects().items() if 'org.bluez.Adapter1' in p]
        if not adapters:
            raise RuntimeError('No Bluetooth adapter found. Check Adapter status in the recovery console.')
        self.adapter = next((path for path, p in adapters if p.get('Powered')), adapters[0][0])
        props = self.interface(self.adapter, 'org.freedesktop.DBus.Properties')
        try:
            for key in ('Powered', 'Pairable'):
                props.Set('org.bluez.Adapter1', key, self.dbus.Boolean(True), timeout=5)
        except self.dbus.DBusException as error:
            raise RuntimeError('Bluetooth radio unavailable: '+error.get_dbus_name()) from None

    def scan(self, progress=None, seconds=10):
        self.prepare()
        adapter = self.interface(self.adapter, 'org.bluez.Adapter1')
        try:
            adapter.StartDiscovery(timeout=5); self.scanning = True
        except self.dbus.DBusException as error:
            raise RuntimeError('Discovery failed: '+error.get_dbus_name()) from None
        try:
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                rows = self.rows()
                if progress:
                    progress(rows, 'Scanning Bluetooth… %d device(s)' % len(rows))
                time.sleep(min(1, max(0, deadline-time.monotonic())))
            return self.rows()
        finally:
            self.stop_scan()

    def stop_scan(self):
        if self.scanning:
            self.scanning = False
            try:
                self.interface(self.adapter, 'org.bluez.Adapter1').StopDiscovery(timeout=3)
            except self.dbus.DBusException:
                pass

    def operate(self, address, action):
        path, _ = self.device(address)
        try:
            if action == 'forget':
                adapter = str(self.objects()[path]['org.bluez.Device1']['Adapter'])
                self.interface(adapter, 'org.bluez.Adapter1').RemoveDevice(path, timeout=5)
            else:
                if action == 'connect':
                    self.interface(path, 'org.freedesktop.DBus.Properties').Set('org.bluez.Device1', 'Trusted', self.dbus.Boolean(True), timeout=5)
                if action != 'connect' or not self.device(address)[1].get('Connected'):
                    getattr(self.interface(path, 'org.bluez.Device1'), 'Connect' if action == 'connect' else 'Disconnect')(timeout=20 if action == 'connect' else 5)
        except self.dbus.DBusException as error:
            raise RuntimeError('Bluetooth %s failed: %s. Wake the device and retry.' % (action, error.get_dbus_name())) from None

    def close(self):
        self.stop_scan()
        self.bus.close()


_backend = None
def backend():
    global _backend
    if _backend is None:
        _backend = BlueZ()
    return _backend


def devices(text):
    # Names are presentation only; commands always use the separately validated MAC.
    return [(m.group(1).upper(), m.group(2).strip()) for m in
            re.finditer(r'^Device (' + MAC + r') (.+)$', clean(text), re.M)]


class Agent:
    def __init__(self, executable='bluetoothctl'):
        self.child = pexpect.spawn(executable, ['--agent', 'KeyboardDisplay'], encoding='utf-8',
                                   codec_errors='replace', timeout=12, echo=False)
        try:
            self.child.expect(r'Agent registered|Agent is already registered')
            self.child.sendline('default-agent')
            self.child.expect('Default agent request successful')
        except pexpect.ExceptionPexpect:
            self.child.terminate(force=True)
            raise

    def pair(self, address, answer=input):
        self.child.sendline('pair ' + valid_mac(address))
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            event = self.child.expect([
                'Pairing successful', r'Failed to pair:[^\r\n]*',
                r'\[agent\][^\r\n]*[:?]', pexpect.EOF, pexpect.TIMEOUT,
            ], timeout=max(1, deadline - time.monotonic()))
            if event == 0:
                return True
            if event == 1:
                print(clean(self.child.after))
                return False
            if event == 2:
                prompt = clean(self.child.after)
                response = answer(prompt + ' ').strip()
                # BlueZ validates PIN/passkey format; never log input or cache it.
                self.child.sendline(response)
                continue
            print('Pairing timed out or the Bluetooth agent stopped. Put the device back in pairing mode.')
            return False
        return False

    def close(self):
        if self.child.isalive():
            self.child.sendline('quit')
            try:
                self.child.expect(pexpect.EOF, timeout=3)
            except pexpect.TIMEOUT:
                self.child.terminate(force=True)


def select_device(items, ask=input):
    if not items:
        print('No devices found. Check pairing mode, then scan again.')
        return None
    for i, (address, name) in enumerate(items, 1):
        print(f'  {i}) {name} [{address}]')
    value = ask('Device number (Enter cancels): ').strip()
    if value.isdecimal() and 1 <= int(value) <= len(items):
        return items[int(value) - 1][0]
    return None


def ready():
    backend().prepare()


def connect(address):
    backend().operate(address, 'connect')
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        _, state = backend().device(address)
        if state.get('Connected') and state.get('Trusted') and state.get('ServicesResolved'):
            controller=state.get('Icon')=='input-gaming'
            nodes=[] if controller else [True]
            if controller:
                for path in Path('/sys/class/input').glob('event*/device/uniq'):
                    try:
                        if path.read_text(errors='replace').strip().upper()==address.upper(): nodes.append(path)
                    except OSError:
                        continue
            if nodes:
                print('Connected, trusted and services ready'+('; controller input present.' if controller else '.')); return True
        time.sleep(.5)
    print('Pairing is saved, but connection/services are not ready. Wake the device and use Reconnect.')
    return False


def pair_device(airpods=False):
    ready()
    print('Put the device in pairing mode. Examples:')
    print('  PS4: SHARE + PS; PS5: CREATE + PS; Xbox: pairing button; Switch Pro: SYNC.')
    print('  AirPods: open the case and activate its setup control until the light flashes white.')
    print('Controllers, headphones, keyboards and mice all appear in the same list.')
    agent = Agent()
    try:
        print('Scanning for 10 seconds…')
        rows = backend().scan(lambda rows, status: print(status, flush=True))
        address = select_device([(item['address'], item['name']) for item in rows])
        if not address:
            return False
        if properties(address).get('Paired') != 'yes':
            if not agent.pair(address) or properties(address).get('Paired') != 'yes':
                print('Pairing was not completed. No bond was removed automatically.')
                return False
        if not connect(address):
            return False
        if airpods:
            subprocess.run(['airpods-mode', 'low-latency'], check=True)
        print('Pairing saved. Test input/audio; connection alone does not prove every device feature.')
        return True
    finally:
        backend().stop_scan()
        agent.close()


def saved():
    return [(item['address'], item['name']) for item in backend().rows() if item['paired']]


def status():
    print(ctl('show'))
    subprocess.run(['rfkill'])
    subprocess.run(['sudo', 'journalctl', '-u', 'bluetooth.service', '-n', '15', '--no-pager'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pair', action='store_true')
    parser.add_argument('--airpods', action='store_true')
    args = parser.parse_args()
    if args.pair:
        return 0 if pair_device(args.airpods) else 1
    while True:
        print('\033[40m\033[1;31m\nBLUETOOTH • CONTROLLERS & AUDIO\033[0;31m')
        print('1) Scan & pair any device\n2) Reconnect saved device\n3) Disconnect device\n4) Forget device\n5) AirPods audio mode\n6) Adapter status & errors\n0) Back')
        choice = input('Choose: ').strip()
        try:
            if choice == '0':
                return 0
            if choice == '1':
                pair_device()
            elif choice in ('2', '3', '4'):
                ready()
                address = select_device(saved())
                if address:
                    if choice == '2':
                        agent = Agent()
                        try:
                            connect(address)
                        finally:
                            agent.close()
                    elif choice == '3':
                        backend().operate(address, 'disconnect')
                    elif input('Forget this device and its saved pairing? Type yes: ').strip().lower() == 'yes':
                        backend().operate(address, 'forget')
            elif choice == '5':
                mode = input('1) Low latency  2) Quality: ').strip()
                if mode in ('1', '2'):
                    subprocess.run(['airpods-mode', 'low-latency' if mode == '1' else 'quality'], check=True)
            elif choice == '6':
                status()
        except (RuntimeError, subprocess.SubprocessError, pexpect.ExceptionPexpect) as error:
            print(f'Bluetooth error: {error}')
        input('Press Enter to continue...')


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, EOFError):
        print('\nCancelled.')
        raise SystemExit(130)
    except (RuntimeError, subprocess.SubprocessError, pexpect.ExceptionPexpect) as error:
        print(f'Bluetooth error: {error}')
        raise SystemExit(1)
BTMENU
chmod 0755 /usr/local/bin/moonlight-bluetooth

cat > /usr/local/bin/moonlight-settings <<'SETMENU'
#!/usr/bin/env bash
set -u
while true; do
  clear
  printf '\033[40m\033[31m'
  mode=$(airpods-mode status 2>/dev/null | head -1 | sed 's/^AirPods Pro 2 mode: //' || true)
  cat <<EOF
EclipseOS SETTINGS
=====================

  1) Wi-Fi
  2) Bluetooth
  3) AirPods Pro 2 -> LOW LATENCY
  4) AirPods Pro 2 -> QUALITY
  5) Audio status
  6) Hardware diagnostics
  7) Use CocoOS
  8) Use vanilla Moonlight
  9) Select any frontend
  9) Audio mixer (save on exit)

  AirPods mode: ${mode:-unknown}

  0) Exit to red diagnostic shell

EOF
  printf 'Choose: '
  read -r choice
  case "$choice" in
    1) moonlight-wifi ;;
    2) moonlight-bluetooth ;;
    3) airpods-mode low-latency; read -r -p "Press Enter..." _ ;;
    4) airpods-mode quality; read -r -p "Press Enter..." _ ;;
    5) wpctl status; read -r -p "Press Enter..." _ ;;
    6) sudo moonlight-os-verify; read -r -p "Press Enter..." _ ;;
    7) sudo moonlight-os-client cocoos; read -r -p "Press Enter..." _ ;;
    8) sudo moonlight-os-client moonlight; read -r -p "Press Enter..." _ ;;
    9) moonlight-frontend-select; read -r -p "Press Enter..." _ ;;
    9) moonlight-audio ;;
    0) exit 0 ;;
  esac
done
SETMENU
chmod 0755 /usr/local/bin/moonlight-settings

cd /usr/local/src
git clone --recursive https://github.com/Djingerr/CocoOS.git cocoos
cd cocoos
git checkout --detach 8c22132f1ce4146c0d6bff812f6fc8f724fe0101
git submodule update --init --recursive
# Embedded console labels in this source pin are French, independent of LANG.
cat > /usr/local/share/moonlight-os/patch-cocoos-english.py <<'COCO_ENGLISH'
#!/usr/bin/env python3
"""Translate the pinned CocoOS console without changing behavior or host data."""
import json
from pathlib import Path
import re
import sys

TRANSLATIONS = {'Options du flux': 'Stream options', 'Confirmer : oublier %1 ?': 'Forget %1?', 'Oublier ce PC': 'Forget this PC', 'Fermer': 'Close', 'Changer': 'Change', 'Le lancement a échoué': 'Launch failed', 'Annuler': 'Cancel', 'Confirmer': 'Confirm', 'Valider': 'Confirm', 'Liaison avec %1': 'Pair with %1', 'votre PC': 'your PC', 'Saisissez le code à 6 chiffres affiché sur votre PC.': 'Enter the six-digit code shown on your PC.', 'Vérification…': 'Verifying…', 'Chiffre': 'Digit', 'Case': 'Position', 'Un jeu est déjà en cours': 'A game is already running', '%1 est en cours sur votre PC. Le fermer et lancer %2 ? Toute progression non sauvegardée sera perdue.': '%1 is running on your PC. Close it and launch %2? Unsaved progress will be lost.', 'Fermer et jouer': 'Close and play', 'Préparation de %1': 'Preparing %1', 'Reprise de %1': 'Resuming %1', 'Lancement de %1': 'Launching %1', 'Ouverture du flux %1': 'Starting stream %1', "Start + Select + L1 + R1 : revenir à l'accueil": 'Start + Select + L1 + R1: return home', 'Natif %1×%2': 'Native %1×%2', 'Désactivé': 'Off', 'Activé': 'On', 'Activés': 'On', 'Coupés': 'Off', 'Résolution': 'Resolution', 'Images par seconde': 'Frame rate', 'Débit': 'Bitrate', 'Sons': 'UI sounds', 'Recherche…': 'Searching…', 'Recherche de votre PC': 'Searching for your PC', 'Chargement de vos jeux': 'Loading your games', "Vérifiez qu'il est allumé et sur le même réseau que la console.": 'Make sure your PC is on and connected to the same network.', 'Saisissez ce code sur votre PC. La console se connectera ensuite toute seule.': 'Enter this code on your PC. The console will connect automatically.', 'La liaison a échoué. Nouvelle tentative dans un instant…': 'Pairing failed. Retrying shortly…', 'En attente de votre PC…': 'Waiting for your PC…', 'Mettre à jour': 'Update', 'Mise à jour de %1 sur le PC': 'Updating %1 on your PC', 'Mise à jour sur le PC': 'Updating on your PC', 'Code expiré — relancez la liaison depuis le PC.': 'Code expired. Start pairing again from your PC.', 'Code incorrect — réessayez.': 'Incorrect code. Try again.', 'Mise à jour requise': 'Update required', "Ce jeu doit être mis à jour (%1) avant d'y jouer.": 'Update this game (%1) before playing.', "Ce jeu doit être mis à jour avant d'y jouer.": 'Update this game before playing.', 'connexion…': 'connecting…', 'Reprendre': 'Resume', 'Jouer': 'Play', 'Aucun host joignable': 'No reachable host', 'Aucun appairage en cours': 'No pairing in progress', 'Certificat du host inattendu (appairage compromis ?)': 'Unexpected host certificate. Pairing may be compromised.', 'non appairé au host': 'Not paired with the host'}

def main():
    root = Path(sys.argv[1])
    files = sorted((root / "app/gui/console").rglob("*.qml"))
    files += sorted((root / "app/gui/console/backend").glob("*.cpp"))
    found = set()
    changes = []
    # Replace only complete string literals, never comments or identifiers.
    literal = re.compile(r'"(?:[^"\\]|\\.)*"')
    for path in files:
        original = path.read_text()
        def translate(match):
            value = json.loads(match.group())
            if value not in TRANSLATIONS:
                return match.group()
            found.add(value)
            replacement = TRANSLATIONS[value]
            assert re.findall(r"%[0-9]+", value) == re.findall(r"%[0-9]+", replacement)
            return json.dumps(replacement, ensure_ascii=False)
        updated = literal.sub(translate, original)
        if updated != original:
            changes.append((path, updated))
    missing = set(TRANSLATIONS) - found
    if missing:
        raise SystemExit("Pinned CocoOS strings changed: " + repr(sorted(missing)))
    for path, updated in changes:
        path.write_text(updated)
    print(f"Translated {len(found)} console strings in {len(changes)} files")

if __name__ == "__main__":
    main()
COCO_ENGLISH
python3 /usr/local/share/moonlight-os/patch-cocoos-english.py /usr/local/src/cocoos
qmake6 "CONFIG+=embedded" moonlight-qt.pro
make release -j2
install -m 0755 app/moonlight /usr/local/libexec/moonlight-os/cocoos
strip /usr/local/libexec/moonlight-os/cocoos || true

cd /usr/local/src
git clone --recursive https://github.com/moonlight-stream/moonlight-qt.git moonlight-qt
cd moonlight-qt
git checkout --detach 8369d1a0e11b999d4d1598f62ca5f6dea49602fb
git submodule update --init --recursive
qmake6 moonlight-qt.pro
make release -j2
install -m 0755 app/moonlight /usr/local/libexec/moonlight-os/moonlight
strip /usr/local/libexec/moonlight-os/moonlight || true

cd /usr/local/src
git clone https://github.com/davidjo/snd_hda_macbookpro.git snd_hda_macbookpro
cd snd_hda_macbookpro
git checkout --detach 89b22ff90b86468b186706861dd18663562defa7

KVER="$(ls -1 /usr/lib/modules | sort -V | tail -1)"
[[ -n "$KVER" ]]
if [[ ! -d "/usr/src/kernels/$KVER" ]]; then
  dnf -y install "kernel-devel-$KVER"
fi

rm -rf /usr/src/snd_hda_macbookpro-1.0
mkdir -p /usr/src/snd_hda_macbookpro-1.0
cp -a . /usr/src/snd_hda_macbookpro-1.0/
chmod +x /usr/src/snd_hda_macbookpro-1.0/install.cirrus.driver.sh

# Fedora 44/GCC16: add compatibility flags to the driver's own quoted
# KBUILD_EXTRA_CFLAGS so its nested kernel make preserves them correctly.
sed -i 's/-Wno-unused-function"/-Wno-unused-function -Wno-error -Wno-incompatible-pointer-types"/' \
  /usr/src/snd_hda_macbookpro-1.0/Makefile
grep -q 'Wno-incompatible-pointer-types' /usr/src/snd_hda_macbookpro-1.0/Makefile

cat > /usr/src/snd_hda_macbookpro-1.0/dkms.conf <<'DKMSCONF'
PACKAGE_NAME="snd_hda_macbookpro"
PACKAGE_VERSION="1.0"
PRE_BUILD="install.cirrus.driver.sh -k $kernelver --dkms"
MAKE="make KERNELRELEASE=${kernelver}"
BUILT_MODULE_NAME[0]="snd-hda-codec-cs8409"
BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus"
DEST_MODULE_LOCATION[0]="/updates/codecs/cirrus"
AUTOINSTALL="yes"
DKMSCONF

dkms remove -m snd_hda_macbookpro -v 1.0 --all 2>/dev/null || true
dkms add -m snd_hda_macbookpro -v 1.0
if ! dkms install -m snd_hda_macbookpro -v 1.0 -k "$KVER" --force --verbose; then
  echo "===== snd_hda_macbookpro DKMS make.log =====" >&2
  cat "/var/lib/dkms/snd_hda_macbookpro/1.0/build/make.log" >&2 2>/dev/null || true
  exit 1
fi
depmod -a "$KVER"

# BEGIN GENERATED CRIMSON APOLLO PAYLOAD
install -d -m 0755 /usr/share/plymouth/themes/crimson-apollo
base64 -d > /usr/share/plymouth/themes/crimson-apollo/background.png <<'APOLLO_BACKGROUND'
iVBORw0KGgoAAAANSUhEUgAABAAAAAKACAYAAAACfQphAAAACXBIWXMAAA7DAAAOwwHHb6hkAAAA
GXRFWHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAIABJREFUeJzs3Xec3Ad95//3zO7O
rraqy7IlWbZxww1XqgM2YEwzODQDB0lIIwnHweVHQsovCSmEkE6SS7n75S4hByG5owaw6R0bXHDv
WLZ639Vq+87M74+15I52V9qZ1X6fz8cDNLM7M/sZWY+H9HnNd75T6ujoqgcAAABY0MrNHgAAAACY
ewIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIA
AAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAA
FIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAA
AAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAA
AAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUg
AAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAA
AEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEAB
CAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAA
AABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQ
AAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIA
AAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAA
FIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAA
AAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAA
AAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUg
AAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAA
AEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEAB
CAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABtDZ7
AADgyGttbU1vd3f6evvS0V5JW1slHe3taW+vpNJWSaXSlkpbJePj4wfvM1mtZnxi6vrY2FgGh4Yy
NDycoaHhDI0MZ3h4uFlPBwA4AgQAADhKdXR05JiVK7N65cosX7osi3t709fbm96e3vT2dKdcKqWj
3JLWUjnlUimtpakD/9rKU79O1GpJksl6LdV6PdV6LaO1amr1+pP+vFqtlv1Dw9m1Z3d27d6dXXv2
ZOee3dm5a3f2DvSnWq025okDALNS6ujoevK/5QGAeaOnuyvr167L6lWrcszKVTlh9bFZt3xlelor
6WmrpKe1LT2tlSxqbU1HS2s6yi1pSyn10fHUx8aSyVrqtWrGR8cyODqSwdHh9I+OZmhyImPlZKw+
FQMm6vVMlkupt5ZTbm9P+6JFKXdUMlkuZaJWy0StmpHqZCYevv0B1Wo1D27amH/86EczOTnZjN8i
AOAQHAEAAPNQT3dXTli3Picdf3wuPOW0nHrsmiyrLMrS9o4sa+9IV0tbkqQ+Op7awGDq/ftTG96T
+shIRvcP5eYd23Lrji354WB/Ng4P5qHhwWwcGcyusZFZzVOpVNK1aFF6e3qzfOnSrFi2LMse/nXV
suVpb23NmtXHpq2tTQAAgHnKEQAAMA+USqUcv2Ztznv6GXn+mefk6cetyaqOrhzT0ZVKS0uSpL5v
f2r9g6ntG0ytf3/q+/ZnbGQ4t/bvzPf3bM8Ne7bnzn27s2FoX6pPcRj/XM2+uK8v1epk9g3ub9jP
BQBmRgAAgCYpl8tZd9yavPDc83PZeRfltJXHZG1nT1pKpdST1IdGUtu5J7U9/ant7E9tZCQTtVq+
v3tbvrp9Y763Z0tu7t+VsapX3AGAQ/MWAABosBPWrs0bLr4kl597YU5euiLdrZUk9dQnJ1PbsiPj
23altnN36mMTSZLtI8P5wrYH8tXtD+WbOzdlcGKiuU9gjtTrSanU7CkAYOESAACgARZ1dOT1z7o4
Vz3/hTnn+PXpaq0k9aQ+MZHqpq2pbduV6o7dqU9Wk3o9/RNj+eLWDfnM5vvzlW0PZfJxJ91biCz/
ADC3BAAAmEPnPO3k/NwLX5rLz70wyzu7kiT1ai3VTdtT3bg1tV17ktrUu/HGatVcveWBfGTDHfnm
jk0NfR8/ALDwCQAAcISVSqW86ZkX5+df+sqcuf7EtDz80nZ9cCjVTdtSfXBL6uMTmToEILlvsD//
8sAd+bcH78ru8dmdpR8A4FAEAAA4QtpaW/Pzl7wkv3D5K7JmxTFJ6kmtlurGbak9uDnV/n3JwRf1
67lu19b89d035otbN8Rr/QDAXBMAAOAw9bZ35P99+Wty1QtfnN6evqkvTk6m+uDmVH+4MfXRsakF
v55M1Gr51KZ78t/u/kFuH9jVzLEBgIIRAABgltpbWvKuF7w073z1a9OzuC/1epLx8VQ3bE71gY2p
j08mqaeepFar57Ob78/7b/tufrh/oMmTAwBFJAAAwAy1t7Tk3c95Ud7x6temd+XyJEl9bCKT921I
9cEtSbWaAy/515L8x8b78oHbr819g/3NHBsAKDgBAABm4LWnPyMfeNNPZeX6dUmSerWa6gObMnnf
Q8nExNSNHl7+b9yzPb9x0zdzw55tTZsXAOAAAQAApuHsJSvzode+Jec+99kptbQk9XqqW3dm8s77
Ux8ezcGz+9WTLSOD+YNbv5v/8+DdTu4HAMwbAgAA/Ah9be35o0tfkTe84lVpWdyTJKnt7s/k7fel
NjD48K2m1vyJai0fuuv6fOiuGzJSnWzSxAAAT04AAICn8PJ1J+cvr3pbVpxxSkrlcuqT1VTv/mGq
GzanXjvw2v7Ur7fu3Zl3ff/LubV/Z/MGBgD4EQQAAHiclR1d+avLrszlL3tpSl2dSZLatl2ZvO2e
qY/0O3hcfz0jkxP5g1uvzf93382p1h3wDwDMXwIAADzKq48/JX/1hp9M3xmnJuVy6mPjmbzz/tQ2
TZ3I79HL/x39u/OL112TOwZ2N21eAIDpEgAAIEl3W1ve/8wX560//pqUVyxNktS278rEzXcn4+NJ
Hln+66nnv99zc373lm9nvFZt1sgAADMiAABQeBcsW51/vOKNOf45z0ypo5J6rZbq/RtTvWdDUq8l
eWT53zE6lLdfe02+tWNT8wYGAJgFAQCAQvuJp52VP379W9Nx+klJSqkPjWTipjtS7x/MgRP8HVj+
v7drS37mu5/PtpGhps0LADBbAgAAhdTR0po/vuiFecsVV6a8dlVST6qbt2fytnuTick8fvn/5/tv
za/f9A2H/AMARy0BAIDCWd/dl3++9MqcfekLUl7el9Trmbz3oVTveeDhvf+R5X+iVst7bvhKPvLA
Hc0cGQDgsAkAABTKBctX5yMvfX1WPfeilLo7k8lqJm66M7Xtu56w/O+fmMjPXvu5fHnrg02dGQDg
SBAAACiMV6x9Wv7h5Vel+6Jzkkpr6sNjmbj+ttT3DT5h+d86sj9v/uZnclv/zqbOTDPUk5SaPQQA
HHECAACF8POnnZs/eOEVqVx4dtJaTn1gcGr5Hxl7wvJ/R//uvOEbn8z2USf7KybLPwALkwAAwIJW
SvL75z8/v3Dxi9N67ulJSzm1nXsycf3tSbX6hOX/1v4ded3XPpk946PNHBsA4IgTAABYsEpJ/vD8
S/Jzz39RWp9xelIupbZjTyauvy2p1Z6w/F+3a2ve/K1PZd/4eDPHBgCYEwIAAAtSS6mUv3zmi/Om
574grc84LSmVUtuyMxM/uPNJl/9v79icN3/r0xmenGjq3AAAc0UAAGDBaS2X89+f+9K86qLnTr3y
X0pqm7Zn4ua7prb9xy3/N+7Zlrd82/IPACxsAgAAC0opyZ9ceGlede5FaT3ntKnlf+O2TNxy95Mu
/7f178pV3/hU9k9Y/gGAha3c7AEA4EgpJfnghZfmLec9O63nnTn1nv9tu59y+b9735687uufSP/4
WDPHBgBoCAEAgAXj989/ft529kVpveCsqY/629WfiRtvf9Llf/voUN74jU9n99hIU2cGAGgUAQCA
BeGdT78gbz/7mWl91jNSam9Lfd9Qxm948rP9j1Qn8xPf+mw2De9r6swAAI0kAABw1Lti3cn5zbOf
m5ZzTk9pUXvqQ6OZ+N7NycTkE5b/Wr2et3/3mty4Z1tTZwYAaDQnAQTgqHbesmPy18+8LOVSKRka
Tr2jkonv35r66PgTlv8k+Z2bv5XPb7m/afMCADRLqaOjq97sIQBgNtZ39+ULl12Vpe2Lpr5Qr+fg
X2pPsvx/YuM9+fnvXt3gKQEA5gdvAQDgqLSopTX/+LyXT3v5v3ffnvzy9V9u8JQAAPOHAADAUemP
L7w0Zy9ZOXXlEMv/vvGxvOXbn8n+iYkGTwkAMH8IAAAcdX7u1GfkqhOePnXlEMt/Us97bvxqfjg4
0NAZAQDmGwEAgKPKhctX533P+LGpK9NY/v/9wbvyiYfuaeiMAADzkQAAwFGjq60tf/Osl6StXJ7W
8v/Q0EDee+PXGz4nAMB8JAAAcNT4o/MvyYk9i6e1/Nfq9fzidV/M4MR4w+cEAJiPBAAAjgqvWPu0
qff9T2P5T5L/ce8t+d6urY0dEgBgHhMAAJj3jlnUnb985ounvfxvHhrMB27/bmOHBACY5wQAAOa9
P7rgBelrrTzp8v+I+sFf3nvT133kHwDA4wgAAMxrr1x7cl5+3ElPufzXH329nnz8obtzzZYHGjoj
AMDRQAAAYN7qrVTy/vN+bNrL/8jkeH7vVof+AwA8GQEAgHnrd865OMcs6p66cojlP6nnL+66MZuH
Bxs6IwDA0UIAAGBeOnPxirz5xDOmrkxj+d88PJi/u/cHDZ0RAOBoIgAAMC/9wXnPT7lUmtbyX0/y
u7d8NyOTTvwHAPBUBAAA5p0r1p6c56w8btrL/139e/KpTfc2ekwAgKOKAADAvNLe0pLffsZzp738
p5780e3XpVZ//McCAgDwaAIAAPPKT5x0VtZ19mW6y/+t/Tvz+S33N3pMAICjjgAAwLzR0dKad5x2
fqa7/CfJB2+/Ll77BwA4NAEAgHnjp592dlYv6jp4/VDL/50Du/PFrRsaOCEAwNFLAABgXuhqbcs7
Tj//4PVDLf9JPX9/7w+8+g8AME0CAADzwk+edFaWty9KMr3lf9foSD6x0Zn/AQCmSwAAoOnayuX8
zCnnJJne8p968j/uuyWj1ckGTwoAcPQSAABoulevPSVrOnumvfxP1Gr5yIY7Gz8oAMBRTAAAoOl+
4bRzp738J8nVWx/I9tGhxg4JAHCUEwAAaKrnrVyTM/tWZLrLfz3Jvzxwe2OHBABYAAQAAJrqrSed
lZks/w/tH8g3dmxq7JAAAAuAAABA0yypdOSlx54wdWUay3/q9fzbQ3enVvfhfwAAMyUAANA0V60/
Pe0tLdNe/pPkM5vva/CUAAALgwAAQNO86cSnz2j5v3Ngd+7et7fBUwIALAwCAABNcf6yY3Jqz9JM
d/lPkk9vur+RIwIALCgCAABNceXaUzKT5T/15DNbHP4PADBbAgAADVculfLKNSfOaPnfMDSQ+wb7
GzkmAMCCIgAA0HDPXL46xyzqnvbyX089X9r2YGOHBABYYAQAABrulWtOntHynyRf3bGxgRMCACw8
AgAADfeS1esfvjS95X90cjLf2bmlgRMCACw8AgAADXVa39Ks6ezJdJf/1JPr92zPSHWiwZMCACws
AgAADXXJyuMzk+U/Sb63x6v/AACHSwAAoKFeuHrdjJb/pJ7rd29v3IAAAAuUAABAw3S2tuWiZauT
TH/5r9XquWGvAAAAcLgEAAAa5rylq9Jebpn28p96ctfg3uybGG/soAAAC5AAAEDDXLRs9YyW/3qS
W/p3NHRGAICFSgAAoGEuXHbMjJb/pJ47B/Y0dEYAgIVKAACgIcqlUs5fsuqRL0xj+U89uXNwd0Pn
BABYqAQAABri5J4l6W2rTF2Z5vKfxBEAAABHiAAAQEOcvXjF1IUZLP+7x0eza3ykoXMCACxUAgAA
DXF639IZLf9J8uDQQENnBABYyAQAABri9J5lM1r+6/V6HhoebOiMAAALmQAAQEM8vW/Z1IVpLv9J
snF4X+MGBABY4AQAAObc4rb2rOzonNHynyQbh/c3bkgAgAVOAABgzq3v6pvx8p96smVEAAAAOFIE
AADm3LqunocvTX/5T+rZNTbaqBEBABY8AQCAObe2szczXf6TpH9CAAAAOFIEAADm3NrOnhkv//V6
slcAAAA4YgQAAObcmkXdM17+J2q17J+YaNyQAAALnAAAwJxb3rEoM1n+k2R/dfzRNwcA4DAJAADM
uSVt7TNa/pN6xmvVBk0HAFAMAgAAc25p26KDl6ez/CfJeFUAAAA4kgQAAOZUe7klXa2tSaa//Kee
jNdqjRoRAKAQBAAA5lRfW3uSmS3/9cRbAAAAjjABAIA51dXaOuPl//EnDAQA4PAJAADMqbZyyyNX
ZrD8t5X9FQUAcCT51xUAc6pSejgAzPCV/4oAAABwRPnXFQBzqq1cntVh/22lUqNGBAAoBAEAgDk1
9Ur+DN/zX6+n8ui3DgAAcNgEAAAaYibLfz1JV0tbA6cDAFj4BAAA5tR4rTbj5T9JKqVyulpbGzQl
AMDCJwAAMKfGatWHL01/+T9QDBa3dTRiRACAQhAAAJhTk/VqZrP8J8lSAQAA4IgRAACYU+O12tSF
GS7/9XqypK3SkBkBAIpAAABgTg1PTs5q+U/qOaajq0FTAgAsfAIAAHOqf2IsU8cAzGz5T5K1Hd2N
GBEAoBAEAADm1HitmqHJ8Rkv/6knaxYJABRR/dA3AYBZEAAAmHN7x0cfufIUy38et/wnyVoBgEIq
NXsAABYoAQCAObd3fGzqwo9Y/uuPW/6TurcAAAAcQQIAAHNu19jIjJf/ej1Z1d6ZxW3tjRsUAGAB
EwAAmHMbR/bPePk/4JSuxXM/IABAAQgAAMy5TSODUxdmuPynXs/pPQIAAMCRIAAAMOc2jgzOavlP
klO7ljRiRACABU8AAGDObRre/8iVGSz/SXJGz9K5Hg8AoBAEAADm3IMH3wIws+W/Xk9O716SRS2t
jRgTAGBBEwAAmHP9E2PZNjo84+U/qaetVM7ZPcsaMygAwAImAADQEHcM7p66MIPl/8DtL+hbMfcD
AgAscAIAAA1x1/69s1r+k3rOEwAAAA6bAABAQ9y1b+/Dl2a2/NeTXNC7Mm0lf2UBABwO/5oCoCHu
2L8ns1n+U096WttyXt/yBk0KALAwCQAANMS9+/vTPzH+yBemufwf+OILlh7bgCkBABYuAQCAhqgn
ual/58NXZrb8J8nzlxzXgCmhOR5zZAwAzBEBAICGuX5gx6yW/9STU7oXZ3V7Z4MmhcYqlZo9AQBF
IAAA0DDX928/eHkmy389SSn1XL58XWMGBQBYgAQAABrm5n27M1arznj5P3Dh5SvWNnBaAICFRQAA
oGFGqpO5bu+OzGb5T5Jn9K7Imo7uRo0LALCgCAAANNTXd2+aujDD5X/qaj2XL1vTiDEBABYcAQCA
hvr6ni2zWv7rD5888MpVJzRmUJhjpTjzHwCNJQAA0FD3DQ1k4+jgrJb/JDm1c3HO6VnWiFFhTtUf
c3gLAMw9AQCAhvvSrs2zWv4PVIM3HHNSA6YEAFhYBAAAGu6zOzY8fGnmy3+SvHzZunS3ts71mDBn
WksO/weg8QQAABruxoGd2Ty6f+rKDJf/ej3pbGnJq1esb8isMBeqdYf/A9B4AgAADVdPcvWuh2a1
/B+4/LbVp6bFq6gchVpLJe/+B6ApBAAAmuKz2x+a9fKferK2ozuXLjmuEaPCEdVR8vYVAJpDAACg
KX4wuCv3DPXPavmf+qWenz721AZMCkdOuVTK/tpEs8cAoKAEAACa5t+23n/w8kyX/9ST83qW5Vwf
CchRZFlLpdkjAFBgAgAATfOJ7Q9krFad1fJ/wDvXnNGASeHwlVPKvupks8cAoMAEAACapn9yLF/Y
tfGRL8xw+U+9nuf2rcpFvSvmflg4TOsqXRmrV5s9BgAFJgAA0FQf3Xrf1IVZLP8Hvv2uNWfO/aBw
GFpKpUxa/gFoMgEAgKa6bmBHbhncndku/6kn5/csy/P6VjVmYJiF09t7s2lipNljAFBwAgAATfc/
N9+dZHbL/4Fv/tq6c9JaKs39sDBDHeVyJh99ngsAaBIBAICm+/yujdk0OpTZLv+pJyct6s1rV5zQ
kHlhJp7ZuSL3jA82ewwAEAAAaL7Jei3/tOWeqSuzWP4PfOfda85In49ZYx5Z2lLJaG0yNUcAADAP
CAAAzAsf235/do+PJpnd8p960tdSyS8dd3qjRoZDekH3qtw4srfZYwBAEgEAgHliuDqZv99816yX
/wPevOLEnNG5pAETw492RkdftkwMZ6Jea/YoAJBEAABgHvnItvuyfexRZ0qf4fKfej3lUil/sP68
tJb8FUfzdJTLubhrRW7w6j8A84h/HQEwb4zVqvmHLXdOXZnF8n/g6qmdvXnbqpPnfmB4Cpd1H5vr
R/Z69R+AeUUAAGBe+dj2B/LQyP4ks1v+D3zvF1efmhM7uhsxMjzGCZXurG/rzk0je5o9CgA8hgAA
wLwyXqvmjx68+bCW/yRpL7fkgydckDZvBaCBOkotubJ3Ta7evyVVZ/4HYJ7xryIA5p0v7t2cb/dv
z2yX/6lv1fP0RYvzn4/1qQA0zit712RXdTz3jO1r9igA8AQCAADz0h8+9INM1uuzXv4PeNvKp+WZ
PcvnelzIeYuW5vSO3lw9uKXZowDAkxIAAJiX7h3el49tf+Cwlv/Up/6i+8Pjz8vS1va5HZhCW9Ha
nst7js11w7uzY3K02eMAwJMSAACYt/5s0y3ZNj486+U/mbrtqtZF+dP1F6SlVJrjiSmiSqmc1/et
z3BtMl8b2tbscQDgKQkAAMxb+6uT+Z0NNz3yhVks/wduc1H3srx79dPncFqKqJTk1X1rs7y1PZ8f
3JKxmo/9A2D+EgAAmNe+1r811+zdfFjL/4Hb/+SKk3JZ37FzPjPF8ZzOlTm9vS+3je7N3U78B8A8
JwAAMO/93oM/SH91/OFrs1v+D3j/2mfk7M4lczgtRXFKe28u7VmV4fpkrh7c2uxxAOCQBAAA5r1d
E6P5zQduyuEs/1Nfr6ej3JK/PuGirK10zvncLFyrWxflNX3rUk7y2YHNGapNNnskADgkAQCAo8KX
+jfn/+588OD12Sz/By4vaankr9ZflN6WtjmemoVocUslb1pyQiqlUr4/vDt3jA00eyQAmBYBAICj
xvs33ZINo/sPa/k/cOsT27vz58dfkPZyy9wPzoLRWWrJmxafkO5yS3ZXx/Ol/c76D8DRQwAA4Kgx
XJ3Mex64PhP1h8+0Psvl/8BNLuhalr9Yd34qJX8dcmjt5XLevPSErGitZKJey//pfyjjdWf9B+Do
0dLaWvmdZg8BANO1Y2I0/dWxPL/3mBzO8n/g+pr2rjytoydf2rft0acXgMdoK5XzpsUnZG1bZ+pJ
Pje4JfeODzZ7LACYEQEAgKPObcP9WV3pyGmdiw9r+T9weX2lO6sri/KNfTtEAJ6gtVTOVYvX54RK
V+pJbhzek68P7Wj2WAAwY455BOCo9Hubbs3tw/0PX5v98n/gdAKvWHxcfn/tM9Lq7QA8SqVUzhsX
r89JDy//2yZGcs1+H/kHwNHJv3IAOCqN1ap59wPfz57J0cNe/g987bK+1fng2vOcGJAkSUepJW9Z
ckJOfHj531+dzMcGHnrkHBQAcJQRAAA4am0eH87b778uw7XJw17+D9zv4p6V+eO156VDBCi0rnJr
fnLpiVnz8Hv+J2q1fGzgwQxUx5s9GgDMmgAAwFHt9pH+vOehG1OtTb0qezjL/9Tt63lW9/L83fpn
Zmlre0OeA/PL0pZKfmrJ07KqtSP1TP15+fjApmyeGG72aABwWJwEEICj3oax/RmpVfOcnhVJDm/5
P3B9eVtHLu1blev270p/daIxT4SmW9PWlbcuOTF9La0H/1xcs39Lbhnd2+zRAOCwCQAALAg3D+9N
Z7k153QtOezl/8Cl7pa2vKTv2NwxMpCtEyONeSI0zVkdi/OGxcenvVw++OfiW8M78q2hnc0eDQCO
CAEAgAXj2v07s7SlPWd0Lk5yeMv/ge9VSi15Sd+xmajXcsvIgU8dYCEpp5QX9RyTF/ccm5bSI38u
vje8J190xn8AFhABAIAF5VuDO7KyrSOnLeo97OX/wG1LpeSC7mVZ196V6/bvzqSzwC8YnaWWXLVk
fc7uWJLSo/7b3zy6N58b3Nzs8QDgiBIAAFhwvrV/R9a3d+ekjp7DXv4ffb8TKj15dveK3DC8O/uc
F+Cot6atKz+x5MSsaluUR/+3v21sIJ/et+ngf3cAWCgEAAAWnHqSr+7blpWtHTltUd+jVvgnX/6f
+L0D15/4FoIlrZW8YvFxGalXc8fIwFw+DeYHPqWYAAAgAElEQVRIKcmzOpfnNX3rHv64x0eW/1tG
+/OpfZtSs/4DsAAJAAAsSPUk3xjcnu5yW87qXPzIq/xPsvxPfW96nxyQJC2lci7qXp6TOrpzw9Ce
jHlLwFGjr6WSNy1en/M7l6VUKuXRy//3R/bks4Ne+Qdg4RIAAFjQrt2/Mx3llpzdueSILP/1R913
XaUrL+5bnY3jw9k07jPi57NSknMXLckb+07Istb2J7zl41vDO5zwD4AFr9TR0SV0A7DgvXHZ+vyX
Y05LOaUjsvzX648NCV8b3J4Pbbsr/dXxOX0ezNySlkpe2bsmJ1W6n3C+h1q9ni/s35rvDe9u6owA
0AgCAACF8fyeVfndNeeko9xyRJf/A/fbNzmRv91xT760b6vDyOeBckp5dtfyXNK1Km2l8hOW//Fa
LZ/YtzF3j+1r6pwA0CgCAACF8vRFi/Mn687LktbKEV3+H/1Yd48O5G923JM7nSSwaU6sdOelPcdm
ZWtHkid+0sP+6mQ+2r8hWydHmjckADSYAABA4axuW5Q/XHtuTunoTXJkl/8D96sl+ebgjvzDjnuz
c3J07p4Mj7GstZIXdR+bMzp6H/Xf8rHL/5aJ4fz7wMYMeLsGAAUjAABQSJVyS/7rqtPyyiVrjvjy
X3/UYw3VJvPJvQ/l43s3Zqg2OWfPp+h6y235se5VOX/R0rSU8pTL/y0j/fns4OZM+OQGAApIAACg
0F61ZG3edcxpaU05yZFd/h/9teFaNZ8d2JR/27MhQ9XqHD6jYukst+Z5XSvyrM7laS2Vk9SfdPmf
qNdyzeDW3DCyp2mzAkCzCQAAFN5pHX357ePOznGVRUmO/PJ/8H71ZLA2kU/t3ZzPDWzKvurE3D2p
BW5xSyXP7VqR8xYtSaXU8sir/E+y/O+cHMvHBzZmm/f7A1BwAgAAJGkvt+TnV5yc1yxdN2fL/6O/
Nl6v5puDO/J/9z6UjePDc/KcFqLVrYvy3K4VOatjccqlUpL8yOX/5tH+fG7f5ow75B8ABAAAeLSL
e1bmPavPSE+5NcncLP+Pfqxa6rl+aE++uG9rbhjenWrdX8uP11oq58yOvlzQuSwntHU99giNh///
8cv/cH0yn9m3KXeN+og/ADhAAACAx1nSUsnbV56SF/etTjJ3y//jH2t3dSxfGdieLw9uy/YJh6uv
bluU8xcty3mdS9Jeaknq9Wkt//eMDeQ/9m3JYM1bLADg0QQAAHgKz+pekf+y6tSsaOuY8+X/kcea
+srG8eF8Z//OfHP/9mybKM7HCC5tac/pHb05d9GSHNvWmeTh36tpLP/7ahP53L4tuWtsoMFTA8DR
QQAAgB+hq6Ulb1t2cl6x+LiUS6WGLP+Pvl8t9dw9si/fH9qdm0f25qHxoSP/JJuolGRNW1dObe/N
0zv6cmzbokd+rzK95b+aeq4b3p2vDW3LWM17/QHgqQgAADAN6yqd+bmVp+SirmUNW/6f7LF2T47m
B8N7c/Pw3tw9ti8DR+EnCSxuqeTESndO7ejNKe096Sy1PvH3KtNb/u8f359rBrdk+2RxjpIAgNkS
AABgBs7tWppfWHFK1lW6Gr78H7xf/ZFFeOvEaO4d25d7Rgfzw/HBbB4fyeQ8OuN9W6mcY1oX5fj2
zqxv6876Sld6WyrJU/y+THf5310dz5cGt+YOh/sDwLQJAAAwQ62lcl7cuzpvXrY+S1vbkzRn+X/C
/er1TNbr2TIxkk0Tw3lofCjbJ0aya3IsOyfHMlybPDK/AU+iu9yapS3tWdZayYrWjhzb1plj2hZl
WWtbSvVHPq7vMbPPYvkfqE7kO0M78/2RPfMqdADA0UAAAIBZOhAC3rRsfZa0VJI0d/l/ssc68PPr
SYZrk9k9OZaB6kT21yYzWJ3MUG08Q7XJTNTrqaae0Vo1qSfVJC0P36+zpSVJKZVSKZ2l1nSWW9Pd
MvVrT7k1S8qVtJdbnrjEP+65HM7yP1ybyLf278q1I7ss/gAwSwIAABymjnJLXtK7OlcsWZuVrR3z
cvl/zP1m9FiPfS5P9lgHZ3/8/Y7A8r+nOpZrh3fl+uE9mbD4A8BhEQAA4AgppZQLu5fltUvW5dT2
Xst/nuR+01z+t06O5DtDO3PLaH9qBx4MADgsAgAAzIEzFi3OS3qPzTO7l6VSKlv+H/VYT3q/ej0T
9VpuGxvI9cO7s2GBfdwhAMwHAgAAzKHOcmue17MyL+ldnfWVLsv/k9xvx8RobhzZkxtG9szpiQoB
oOgEAABokJPae/Lc7hV5dvfyLD9wroCCLv97q+O5dbQ/twzvzZbJkaf+TQMAjhgBAAAarJTk5I7e
PLt7ec5ftDQr2xYlWfjL/67Jsdw5NpBbRvqzaWLo4NcBgMYQAACgyVa2LcpZi/py1qLFOatjSTrK
Ux/Ad7Qv/xO1WjaMD+XescHcNz6YzRPDM/ydAQCOJAEAAOaRtlI5J7Z355T23pzS0ZOTO3rTVW49
Kpb/odpkNozvz4bxoWwY359NEyOZ9NF9ADBvCAAAMI+VkhxbWZS1bV1ZW+nKmrbOrK10ZklrpanL
/97qWLaMj2Tb5Ei2TEz9b+fkqMP6AWAeEwAA4Ci0qNSSlW0dWdbanuWt7Vne0pFlrZX0tLSlq9yW
rnJLFpVbksx8+R+uVbO/Npmh6kT21yaze3I8u6tj2TM5lj3V8eypjmWkVm3k0wUAjgABAAAWqJZS
KV3l1lRKLSmnno5Sa5KkUi4nScZqU4fnj9YnU08pY7VqhuqTqdX90wAAFiIBAAAAAAqg3OwBAAAA
gLknAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUg
AAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAA
AEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEAB
CAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAA
AABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQ
AAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIA
AAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAA
FIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAA
AAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAAAAUgAAAAAEABCAAAAABQAAIAAAAAFIAAAAAA
AAUgAAAAAEABtDZ7AACYC29645tSLk+/c4+PjeXf/s+/z/rnrV69Os//sefnwvMvyPLly9Pb25eh
of3Ztm1bbrjpxnz5K1/Jjh3bZ/SYL3rhi3LMMcckST76rx9NtVqd9XwH9PR051VXvDpJ8sMf3p/v
fPe7077vq1/16nR3dz/p9wYHB7PhwQdz5513ZHx8fNbzrVq1Kle84hU5++xzsnLFylQq7dm9e1e2
79iRDQ9uyHe+853cededqdVq037M5cuW5/LLL5/RHBs3bszXv/H1mY4PAPNaqaOjq97sIQDgSNtw
3wOpVCrTvn1/f3+efvYZM/45xx57bN7zy+/Ja3/8NWlpaXnK201OTuYLX/pi3v+B9+eHP/zhtB77
Yx/511z8vIuTJCc87cSMjY/NeL7HO37d8fnut74z9fj//m959y+/e9r3ve4712btmrU/8jYDAwP5
8P/+cP7sL/48o6Oj037sSqWS9/7Kr+Zn3vYzaW390a9P7O3fm9df9Ybcfsft03rs8849P//xqU9P
e5YkufoLV+dtP/PTM7oPAMx3jgAAYEGbnJzM0NDQIW83sG9gxo99/nkX5H/94z9m2dJlB3/WDTfe
mNvvuD379g2kq6sna9euycXPvThdXZ152eUvzYsufWHWP+2EGf+s+WRycjKbt2w+eL3SVsmqVatS
LpfT19eXd/ziO3Lx8y7O6656XfbvP/TvfalUyn/7q7/Jy176siTJ+Ph4rr3u2tx7333ZtWtXOjsX
5cQTTsxFF16YFStWZsniJenpefIjEQ5lbGw0o6OHDinDQ8OzenwAmM8EAAAWtFtvuyUvv+KVR/xx
Tz3llHzsIx9NZ2dnkqlX0z/wwQ9k+/YnHubfXmnPlVdemV9+13/Ncccdd8RnabTt27fn2c97zmO+
1l5pzyUvuCQfeP/7s3Llqpxz9jn5lf/nV/Nbv/Nbh3y8l730ZQeX/zvvuis//bNvy4YHH3zC7Vpa
WnLJCy7JG173+oyPT85q9n/8X/8zv/cHvz+r+wLA0c5JAAFghiqVSv7hb//h4PL/R3/8wbz7l9/9
pMt/koyNj+VfP/avueTFl+Rzn/9cI0dtmLHxsVz9havzn37irQffn/+mq944rbdhvObHX3Pw8i/9
51980uU/SarVar705S/lZ9/+c7nxphuOzOAAUCACAADM0JWvenVOPvnkJMlXvvqVfOivPzSt++3f
P5SfffvPzeVoTXfb7bcdfG9+Z2dnTj/t9EPe52knnpQk2b1nd+66++45nQ8AikwAAIAZ+qmf/KmD
l//0z/889fr0z6c7k9serR59ksOlS5ce8vYtD5/0r6e7J21tbXM2FwAUnQAAADPQ19eXM884M0ny
4EMP5qYf3NjkieafZcuWH7w8PHzokwA+8MBUMKhUKvnJt751zuYCgKJzEkAAFrSWltb09fUd8nZj
Y2PT+ti6c59xbsrlqX5+442W/8fr6urMWWeelWTqaIf77z/0Rx5+4pOfzKWXXJoked9v/26e99yL
8/FPfiLf/s53smvXziM6X6XSPq0/D8PDw5mYmDiiPxsAmk0AAGBBO/uss3PnrXcc8nZ/9hd/lj/5
sz895O1WLH/k1e1Nmzcd1mwLTUdHR/78T/48fX29SZLrvve97Nq965D3+/gnP54XXnppXv2qVydJ
XvyiF+fFL3pxkuShjQ/lpptuyvev/34+f83V2bp162HN+NM/9bb89E+97ZC3e8Obrso3v/XNw/pZ
ADDfCAAAMAOLFz/y6vF0PuN+Ieru7skv/cIvHbze0dGRE084Ic99znOycuWqJMnY2Gje9/u/O63H
q9fr+aV3viPXfe+6vOMX3/GYj0pct3Zd1q1dl1dd8aq877ffl//47H/kfb//u9m2bduRfVIAUAAC
AAAL2n333Zff+K3fPOTtNm58aFqPNz7+yGHhRT1hXV9fb37j1379Kb+/devWvOu/vis33/yDaT9m
vV7PP334n/NPH/7nnHnGmXnhpS/Ms5/1rJx11llZsnhJkqSlpSWvuuJVefaznpUff91r8sMHHpjx
7P/x2f/Ih//3vxzydrfeduuMHxsA5jsBAIAFbXD/viN6KPfe/v6Dl/t6e4/Y4x5NxsfHc9fddx28
XqtWM7BvXx7YsCHXXndtrrnmmoyNj8368W+7/bbcdvtt+cu/+suUSqWcdeZZedUVV+RtP/W2tFfa
s3LlqvzVX34oL7/ilTN+7I2bNjq0H4DCEgAAYAYefOiRIwVOPfXUJk7SPDt37szlL39pQ35WvV7P
LbfekltuvSWf/NSn8ulPfirtlfac+4zzcs7Z5+TmW25uyBwAsBD4GEAAmIHbb78tQ0PDSZJzn3Fe
Ojo6mjxRcdx62635+Mc/fvD62Wef3cRpAODoIwAAwAxMTk7mS1/+YpKkp6c7r3rlFU2eqFjuvvee
g5c7OzubOAkAHH0EAACYob/9+787ePnXfvW9B09SNx3Hrzt+LkYqjNWrjjl4efeu3U2cBACOPgIA
AMzQLbfekg//y4eTJCtXrspHPvwvWbZ02SHv97LLX5qrP/v5uR7vqPOzP/Ozj/nov6eyatWqvO51
r0sydW6Aa6+7dq5HA4AFxUkAAVjQ+vqW5BUvf8W0bvuNb349+/YNTuu2v/W+38npp5+WC86/MOec
84x882vfyN/+/d/lc1d/Lvfff//B2y1dsjSXvOCSvPUtb8mFF1w4q+eQJC972csyMTHxI29Tq1bz
uauPvsDw+te+Lr/x3l/PV772lXzik5/Mdd/7Xnbs2H7w+z093bnsRS/Jr/7Kr2TpkqVJkk9/5tPZ
tHnTjH/WiSecNK0/D5MTE7n6C9fM+PEBYD4TAABY0E484YT8w9/+/bRu+8LLXph9++469A2TjI2N
5vVvvCp/+sE/yZWvvjKLFy/Or/3qe/Nrv/rejI2PZe+event7X3C+9S/+rWvzvg5JMnffOivpzXT
CSefNKvHb7ZKpZLLL7s8l192eZJkYGBf+gf2Zsnipent7XnMbW+86Yb86q+/d1Y/5yWXXZaXXHbZ
IW83MDCQq896+qx+BgDMV94CAACzNDo6ml965zty5WuvzJe/8uWMjo4mSdor7TnmmGMOLv9j42P5
/DWfzxvedFXe/Nb/1MyR56V3vuud+cM/+kC+9/3vp1qtJkn6+npz/LrjH7P833vvvfnt9/1Wrnzt
a7Jv375mjQsAR61SR0dXvdlDAMBC0N7ekTPPODMrli/LkqVLMzAwkC1bt+bOO+7I2PhYs8c7KvT0
dOekk07Occcem8WLF2doaCgDAwO56+67snXr1maPBwBHNQEAAAAACsBbAAAAAKAABAAAAAAoAAEA
AAAACkAAAAAAgAIQAAAAAKAABAAAAAAoAAEAAAAACkAAAAAAgAIQAAAAAKAABAAAAAAoAAEAAAAA
CkAAAAAAgAIQAAAAAKAABAAAAAAoAAEAAAAACkAAAAAAgAIQAAAAAKAABAAAAAAoAAEAAAAACkAA
AAAAgAIQAAAAAKAABAAAAAAoAAEAAAAACkAAAICjQKlUyvKly7Ooo+Pg17o6u7Jk8ZImTgUAHE1a
mz0AACxkr3/1a9PT3f2k37vplh/kxlt+MK3HaWlpye+89zfzsU/8e7753W8nSV5+2Utz2imn5Xc/
+PtHbN7ZOvuMM/PM8y/KyhUrk3qyfeeOXHv9dbntztufcNuuzq5c+mMvyInrT0xfT2+Ghvdnx66d
ufWO2/ODW29uwvQAUAwCAADMoTNOOz1tbW25/4EfHvHH3rRlU2q12hF/3JkolUp58+vemGf9/+3d
V3BUV57H8V9L3WqFVrcyEooECZHBYBwAm2gwxpjkAGN7HGtyzdTM1M48TNXu21ZN7dbOTp6dgD1O
OIDBNsHGYIPBRCEhARISCEkgFFBstVKr1b0Pwm16JIJZWHt8vp8qqnzvOfd/7m0ezP3dc8+dPkNl
FeU6cPiQJGn82LH69tPPa9/BT7V+45sKBAKSJJfTpZ/98CeyWq06WHBYxa3NcjqcysnK0YOLHiAA
AADgFiIAAADgFqs5f05/ffmFm17300MHbnrNL2re7Lm6c/oMbdr6rj78eGdw/849u7R4wSItve9+
Xaiv0+59n0iS7pg2Q85Yp/79v36p2roLIbUcV5gpAQAAbg4CAAAAviKmTJykOTPvVVpqqvr7+3Wh
rk5bP9yuyqqzQ/afM3O2MjMy9dLrr0qSkpOS9OiKR7RtxzZNnzpdk8ZPUFhYmIpPHNemrZvV3d0T
PHba5Kmad88cJcYnyh/wq6WtVR/t+VgFxwqDfUZkj9Di+QuVnZklSaqsqtTmbe+pobFRkmS1WnXf
vPmqPletnbt3DTq/93d+oKkTJ2nRvIX6ZP8++f1+JSclqq+vTxfq6wb193g8N/7jAQCAa2IRQAAA
vgLmzp6j5554Rl3dnXpj0wa9sektna+rVWpK6hWPSUkephHZI4Pb9ohI5efm6ck1Tyg6Olqvv/2m
dny0U9On3qbnn3hWFotFkpQ3OldPrX1SldVVeumNV/TahjdUcuK4XK64YK383Dz98NvfU8AfuHQ+
G+SMderH3/2h4i71y87IVEx0jIqOlwSn+F8uEAjo2PESOWOdyhieIUlqaGyUzWbTkoWLFGm335Tf
DgAAXB9mAAAAcIvljcrVv/38F4P2v/jayzpbXaWY6BgtW/yACo4Vat0rLwbbi0qKb2i85pZmvfDq
34M35R2eDn1zzRMak5unsvJTyhs5Wm3tbdrwztvBY0pOHg/+t8Vi0cPLV6vi9Gn96cW/BOucKDuh
f/2XX2jOrHu0acs7SkxICo53JU3NA21JCQmqOV+jPfv3auK4Cbp/wWItmnefzl84r9OVZ1RYckxn
q6tu6HoBAMD1IQAAAOAWa21r04EjBwftb3e7JUljRufKZrPp4727b8p4RwoLQp7IFxwr1OOPrFV2
RrbKyk+poemi4lxxevihVTpYcFjnas+F9E9OTNSw5BTtP3RAifGJIbXP1Z5XRlq6JMlqDZckefu8
VzyXXm+vJCncOvBPDq/Xq1/98Tcam5evCWPHa2ROjubOnqN598zVJ/v36fW337wpvwEAABiMAAAA
gFvsYvNF7bhsgbx/5HQ6JUktra03Zby29vaQbb/fL3eHWwnxA1P3jxQWaFhyimbfNVP3zpytzq5O
FZUc03vvb1OHp0Mup0uStPyBZVr+wLJB9esa6iVJHZfe2U+MT7jiuXzW1uHpCO4LBAI6eapUJ0+V
Shr4MsDjj6zR7LtmqvhkiUpPld3opQMAgKsgAAAA4EvW0zOwOF+sw6F2d/s1el9bVFTUoH3R0dHy
dA7csAcCAb33/lZt3bFdGcMzND5/nObOvlfDU9P0n7/7b/X0DjzR/9srL+roZYsC/qOzNVXy+/3K
ycoJrvL/j0bmjFB/f7+qa2quWKfd3a6339ussT/O14isHAIAAABuERYBBADgS1ZZfVaBQECTxk+8
KfXyc/NCtkdk58geYdeF+vqQ/X6/XzXna7Ttw+3auXuXcrJyZA23qq6+Tl3d3ZoycfJVx/F4PCo6
XqzbJk1RZnrGoPaczGxNGj9RR4qOqrunW5JkDR/62UN0VLQkydvXd93XCQAAvhhmAAAAcIu5nC5N
nTRl0P7W1lZVnatW48WLOlJYoIVz5svT6dHRY0Xq9/uUnZktBQIqqyj/QuNNmThFZ6urVVB0VMlJ
SVq76jG1trUGF/q7d+ZsdXV3q+J0hdo73EpMSNCEseNU11AvX79PkrRtx3atWrZCrUuXac++vWrv
cCvO5dLYvHz19PTocGGBJOmtzRuVk5ml7z//HW3e+l5wWv/4/HF6aMlStbS1aOO7m4LntvqhFYqO
itaRogLVNdTL6+1Tdmamli95SH19fSoqKbqh3xgAAFwbAQAAALdYZnqGnn38qUH7DxcWqOq1lyRJ
r254XT29vVr54HI9sny1JKm316tXN6z/wuO9u/1dLbh3ntauflSSdLGpSX9c92d5vQNT+yMi7Hpw
8dKQz/DVnK8J+QLBR3t3KxDw6/6FizX/nnnB/c0tzdr47ubgtrvDrf/47a+0atkKPbJiVfAJv8/n
U2HJMW18d5M6uzqD/U+frdT8e+bq+Sc//yyhJNXW1ekPf/uf4FcDAADAzWeJjIwZ/OFeAADwpbDb
I5SUkKz+fp+aW1vU9wWmxGcMz9DPf/RT/fpPv1NF5WmlpgyTLFJ9Q0PIKv+SFBYWpoT4eEVFRqnd
7Za7wz1kzbCwMKUkJSs83KoOT8cV+31+7gNfDWhqaVZv75W/DhAVGak4V5wsFota29qCrwgAAIBb
hxkAAAB8hfT2elVbV/t/rhMIBIKr9Q/F7/df19N2v9+v+saG6xpz4Nzrrqtvd0+PunuufH4AAODm
YxFAAAAAAAAMwCsAAAB8TURFRik/b4wqKk/L4/F82acDAAC+YggAAAAAAAAwAK8AAAAAAABgAAIA
AAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAA
AxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAA
AAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYg
AAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAA
ADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAA
AAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABg
AAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAA
AAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAE
AAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAA
AAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAA
AAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAM
QAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGMD6ZZ8AAAD/36zhVt01
dbp8/f3aX3g4pC01OUW52SPV0NSo8qrKG6qfMWy4ls2/T79/9YUbOn7+XbMkSTv3772h4y83MW+s
4pyuK7afqCjT5PwJslnD9cG+3UP2iSy3vH4AAAvmSURBVLTbNWnMOKUkJCvCZlVTW6uOniiWp6sz
2GfmbTMUFjbwXMHX71Nre5uqas+pp7c3pNaE3HxlpKYpOjJKnd1dKi4vU11j/XVdy+LZc9XV3aM9
R/YParPIokn54zQ8ZZii7JHydHfqWNlJNTRdvK7aAACYgBkAAADjWK3hWjRrjhbPnqPM1PSQtjkz
7taCu2dr/OgxN1zfZgu/6k33tURHxig6MuaGj7+cI8ahBFecElxxys0eqfl3zgpuJ7jiZLPZFB0Z
qejIqCvWSHQlKC9nlLp7u9TU1qrc7BH6wRPPyumIDfZZcPdsjcrKUYIrTllp6Zp/1z362XPf16xp
d4TUun3iFEnSxdYWxURF6ztrntTYUXnXdS0xUdGKjoocutEizZg0VX6/XxdbW+RyOPW9tU9rVFbO
ddUGAMAEzAAAABir/OwZTR03QefqayVJUfZI5WaP1JmaqkF9E+Pi5XTEyu3pUHNb66D2qMgopSYl
6WJLy5BjWSwWxTtdcsTEqLG5adCT8aFYrValD0uVp7MzOGZYWJjiYp1q63DL7/cH+0ba7bJZbero
9ITUuHyGw5SxE5SWnKzNO7cPOV54WLjSU1Pl9XrV0NSkgAKSpNrGOr38zlvBfnsLDuonT39b40bn
6kDR0eD+Q8VHdfJ0eXB77Kg8rXlgudyeDhWfOilJWrdxfciYAUnTJ0xS6ZnPjwuzhCne5ZTTEauW
9na1d7iHPF+LLIp3udTV062e3l79+Y2XQ3+/cKumT5gc/Pt0OmLV6+2RxRKutOQUNTRdVFdP95C1
AQD4OiIAAAAYq7D0uFYuXKKte3bK5/Npcv44nampkrfPG9Lv6ZVr5HQ41NHpUXJCohqam/Ty5rfk
6/dJGphmv3zBEjU0NcoRE6Oz56pDjnc6YvXkQ6sVEWFXh8ejYUlJemfXB8Gb4qHEu5z67tqn1dnV
pdSkJJ06e0YbPtiiQCCgp1c+ph2f7gk5ftV9S9Xc1qLtn3x0Q7+FI8ah76x5Un39PiXFJ+pMTZXW
b9k0ZN/w8HCFh4ers+vqN8+lZ8p1vKJMd06edsVrtUdEqKv78zqJcXH6xrKHZbfZ1NLerqT4eG3d
vVMl5aWDzmHFwiWKj3WFhBOXi4iIUFPr54HMN1c8qtr6CxqdPUKerk7tOrBPZZUVV70GAAC+TggA
AADGamlvV93Fixo7Mlcl5aWaOn6iPjrwqSbkhk7/3/DBe3J7OiQNPFV+7uG1mjZ+og4WFyrKHqmH
5i/W2zu26HhFmaxWq55dvSbk+AfnLtD5hnpt3rldgUBAGanD9dSKR1V5rjrkPfrLjcrM0e9fXaeG
5iY5omP0/cef0YTcfJWUl+pwyTHdPnFq8Kba6YhV3oiR+vXfd93wbzEiI1t/eG2dmlpb5HTE6sdP
fUvpKWmqbawL9rlv1r1yRDuUMSxNRaXHdaLi1DXr1jbUa8yI0SH7puSPV05GlpITEtXr9WrLxx8G
21YuXKq6xnpt+GCL/H6/wixhioiICDk+0m7X2qUr1dXTrXVvr5fP5wu2TZ8wWZmpwzUsKVkdnR7t
OhC6jkL6sDT9+qW/XNcMDAAAvm5YAwAAYLTCk8W6bfwkDUtKlsvhVHnVmUF9PF2dyh+Zq7un3q67
pk5Xn8+ntJRUSVJORpa8fV4dryiTJPl8Ph0uLgoea7PalD8yT6erzyoteZiGp6TK7/erq6dbmWnp
g8b6zOmaKjU0NwXHLzlVqvyRAzfSBSeOKTM1TckJiZKkaeMnqbr2/JCvJlyv0zWVwaflbk+Hmlqb
lZSQENKn3e1Wm7td3b09GpGZpZjo6GvW7fX2ymoND9nX1dOt1ktT+9OSU4LXERvjUHZ6hnbu/yT4
eoM/4FdPb0/wWFesU889/Ljqmxr1+tbNITf/ktTZ3aVWd7vaOtxKH5ampPjQayg4UczNPwDAWAQA
AACjnThdpszUdM2ZcbeOlZ0Iea9eGngP/1uPPqGZt82QzWqTt69X3j6vIu12SZIjOnrQU/zL38N3
OmJksVh0x+RpWjRrTvBPa3ubAoHQsS43uGanHNEOSQM3uSdOn9L0CZNlsVg0bfwkHS4pGqrMdevu
Dp3O39fvk9UaOlHwYHGhdh3Yq7+8+Yr6+/t1z/Q7r1k33uWSpzP0WsqrKrX78Kd6Y9s7OlxSpGXz
FkmSnDEDiwq6PZ5BdT6TlZauuFinDhUXKhAIDGovPVOhjw99qvVbNqmkvFRL5y4Iab/SjAsAAEzA
KwAAAKP1evtUeuaUpo6bqN+8/NdB7Vlpw+WKdeqXf/6d/Jdu2DNT04M3x26PR05HrCwWS/CG1HXZ
FwDaPR75A35t/2SXahvqBtW/ElesM2Q7zumUu7MjuH2ouFDfWLZKVbW1stlsOnnZInq3WiAQUFNL
ixwxV/9SgdVq1fjR+To1xKyKzzReesVBkto62iVJCS6XGluah+xfUl6qjs5OPffwN7Ru4/qrfubv
YkuzJuTmDzp3AABMxQwAAIDxtu3Zpd++sm7Im8n+fr9s1ojgdPf0lDSNv2yNgKraalksluDn7SLt
dt05eVqw3efz6VRlhRbNmqso++efsMtIHR6cRTCUkZlZyho+8IpAYlycJuaN0/HysmB79YXzcns8
Wr5gkY6eKFZ/f/8NXv21ZaamK8EVF9wekZGpsaPG6Mw/LHYYYYtQpD1SCa445Y8cradXPqYIm00f
H/xU0kCokZWWLovFIkmKc7o0c9rtqrxUp7O7S2WVp3XfrLmKsEUEa8bGOELG2Xf0kD46sFfPrFoT
fBUjwRWnjGHDZZEluH3H5GmDzhEAAJMxAwAAYLyunu4rfg6u5kKtTp2t0I+++S25PW75+vtVfKpU
9ksL0/V6+/TGtnf02JKHNPO2O2SzhutY2QlNmzA5WGPDB9u0cuES/fTZ76nd4x54baCzU3/b8Jqk
od9HLz1ToQfnLJTNFiGXI1YHjhXo1NnTIX2OlBTqgbkLdeT4/236/7WkpaTo/tnz5A9IYRbJH5D2
Fx1SQcmxkH6rFy2VJPV6vWppb9Pp6kq98s6G4G8bZbdr7YMrFWWPlLfPp0h7hErPVIR8lnDzzu16
5P5l+tnzP5Db41ZsTIzeen/LoNX6DxYXqs/n0zMrH9XfN78lBaQnlq9WhM0mn69fERE2HS8v09bd
HwoAAAywREbGMBcOAIBriI1xyGa1qrW9XQEN/l9nWFiY4p1OuTs71dfXN2QNa7hVcU6nurqvHDhc
ziKLEuJc8nR1qdfrHdS+cOY9Sh82XC9sXP/FL+gLCg8Pl8sRK38gILenY9BaCdfLIoscMTGyR0So
vaNDfb6hf6tIe4Qc0Y6r9hlU22JRbIxDETab2jrcgxYIBADAdAQAAAD8k4l3xSlneIaWzl2kV997
S2dqmOYOAACujTUAAAD4J5OVlq5xo8do6+4d3PwDAIDrxgwAAAAAAAAMwAwAAAAAAAAMQAAAAAAA
AIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIA
AAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAA
AxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAA
AAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYg
AAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAA
ADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAA
AAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABg
AAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGOB/AYp3
rrl3bkmTAAAAAElFTkSuQmCC
APOLLO_BACKGROUND
base64 -d > /usr/share/plymouth/themes/crimson-apollo/apollo.png <<'APOLLO_APOLLO'
iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAACXBIWXMAAA7DAAAOwwHHb6hkAAAA
GXRFWHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAABX5JREFUeJzt3T2PI1kVxvHnOfXm
13Hb3b1DtAEaktVG7EhICCQmJEZqAjIIlm+x2m/BSoQgwYiccEFICKGBCE3CimATGPrF7bHbdrmq
7kMwCLQboH3pXaM65/cJ6kh/2/feupIpCcEvO/YDhOOKAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyL
AJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyL
AJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyL
AJyLAJyLAJyLAJyLAJyLAJzLj/0AX7Y/PX5cPCy/mt/ZNH9tvzYA+OdgmsZp3b44/K1969mz5tjP
+GVi7/827t137YNf/3VySIfRsCgqtV2VZEVmyNrUGgDklqcuoTOmhnlW75qmLq3cPvru1zZ45510
7BG+SL0N4DdPnuRf2b4+q/J20jWaJKRRQQ4kq2BtmTrL80wEgLajLEstUn4gU91Ie4Nts4Kbus03
/xh9uPrO+++3x57pi9DLAK6+9aPp6rA9gTST2RRMU4pjSSOQA0glaTmZDAAkS1JqQR4g7UluRd1B
tmZKa5ArWbZ69IefvTz2bPetdwE8/+bFojzYnHl2wpROAM068IFRE4JjAMMEDAAW0KsAQEuAGgP2
AHaC7pK4yaCXAFcyu1Xb3R7KtHzj909vjjrgPetVAB9++wdz7rpFY1gkZguym1M8SdIJwAckJ4TG
AoaSShIZAEjoSB4I7ATeSdoAemnkrahbKVuaupuUcFMOs5vXf/fz5bFnvS+9CeDvj98e3abNeVF1
p5nsNCGdErZQ0oLkHNBJkmYgpwRGAAaCcgAg2ALYC9hCWhu5AngraUnjjZBuDHbdMV03dXa9tcnl
W8/e2x534vvRm23gXVqOR5WNDp0mQprC+ADATOQc1ALAwsC5pBOQUwAjAwsAENAA2FJakxyKKACZ
IBDsALZK6SCoHlXdrqiXYwARwP+L529elOWkrJq2GzDDICUMDRpKHBMYA3gAYSZgQXIhYD558o3B
2Q+/BwC4+umvsPntH/ckKwEGIYFoCasl7EhtEzCkcdC0HKAsq+dvXpRv/OXp4biTf369OAmcD+Z5
lilLVG5QTlousCBSAaqCUIkYChglYFo8PB2cv32BbDZBNpvg/MffR/HwdJCAqYCRiCGEClRFpEJg
QVpuUJ6oPMuUzQfzXnx4ehHAZ9KPpc/n1osAlvtl23XsTGwT2EqpJdQI1kCsQdQUdgS2BqybF9f7
y5/8Et1qg261xuV7v0Dz4npvwJrAlsIORA2xFqwh1EipTWBrYtt17Jb7ZS8OhnqzC/jg6xfnRWVn
h07nGXgm4xnB06R0RnIBYEHhI4tAAh9ZBOLVIvBWxBLAjaQbo10JumbSVQddlRkvmzpdPfrz08tj
zntfevE7BgBjm9/d1ptRUXUbyiohlQBzihlBAEpJakDuCKwADNLHt4HkVtLa8GobCGEJYgXoJc3W
ZNps62y7tdndUYe9R735BgBeHQQddt3C4iDoE+tVAEAcBX9avQsAiJdBn0YvAwDidfAn1dsA/iMu
hPxP/Q/gY/57JazOX9tX/74SVqdxquJKWPCnFyeB4bOLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyL
AJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyL
AJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyLAJyL
AJyLAJyLAJyLAJyLAJyLAJz7F1Bh98pqraTMAAAAAElFTkSuQmCC
APOLLO_APOLLO
cat > /usr/share/plymouth/themes/crimson-apollo/crimson-apollo.plymouth <<'APOLLO_THEME'
[Plymouth Theme]
Name=EclipseOS Eclipse
Description=Minimal black and crimson eclipse with a subtle orbital light
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/crimson-apollo
ScriptFile=/usr/share/plymouth/themes/crimson-apollo/crimson-apollo.script
APOLLO_THEME
cat > /usr/share/plymouth/themes/crimson-apollo/crimson-apollo.script <<'APOLLO_SCRIPT'
# EclipseOS Eclipse boot theme. Internal paths stay compatible.
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

pi = 3.141592653589793;
scale = 1; background = NULL; back = NULL; origin_x = 0; origin_y = 0;
base_ship = NULL; rotated = []; ship = NULL; dots = []; dot_image = [];
angle = 0; status = "normal";
fun layout_callback() {
scale = Window.GetWidth() / 1024;
if (Window.GetHeight() / 640 < scale) scale = Window.GetHeight() / 640;
if (scale > 2) scale = 2;
background = Image("background.png").Scale(1024 * scale, 640 * scale);
back = Sprite(background);
back.SetPosition(Window.GetX() + (Window.GetWidth() - background.GetWidth()) / 2,
                 Window.GetY() + (Window.GetHeight() - background.GetHeight()) / 2, -100);
origin_x = Window.GetX() + (Window.GetWidth() - 1024 * scale) / 2;
origin_y = Window.GetY() + (Window.GetHeight() - 640 * scale) / 2;
base_ship = Image("apollo.png").Scale(128 * scale, 128 * scale);
# Cache small rotations once; no frame-sized image decoding in the refresh loop.
for (i = 0; i < 72; i++) rotated[i] = base_ship.Rotate((i / 72) * 2 * pi + pi);
ship = Sprite(rotated[0]);
ship.SetZ(10);

for (i = 0; i < 3; i++) {
    dot_image[i] = Image.Text(".", 0.93, 0.32, 0.45);
    dots[i] = Sprite(dot_image[i]);
    dots[i].SetPosition(origin_x + (494 + i * 15) * scale, origin_y + 602 * scale, 20);
}

}
layout_callback();
Plymouth.SetRefreshRate(20);

fun refresh_callback() {
    if (status != "normal") {
        ship.SetOpacity(0);
        return;
    }
    ship.SetOpacity(1);
    # 20 callbacks/second, approximately one 7.2-second orbit.
    angle += 2 * pi / 144;
    if (angle >= 2 * pi) angle -= 2 * pi;
    index = Math.Int(angle * 72 / (2 * pi)) % 72;
    ship.SetImage(rotated[index]);
    ship.SetPosition(origin_x + (512 + 115 * Math.Cos(angle)) * scale - rotated[index].GetWidth() / 2,
                     origin_y + (248 + 115 * Math.Sin(angle)) * scale - rotated[index].GetHeight() / 2, 10);
    for (i = 0; i < 3; i++) {
        if (Math.Int(angle * 9 / (2 * pi)) % 3 == i) dots[i].SetOpacity(1);
        else dots[i].SetOpacity(0.25);
    }
}
Plymouth.SetRefreshFunction(refresh_callback);

# Prompts use a clear black screen, independent of the decorative composition.
# Wrap complete words before measuring UTF-8 text; cap work for untrusted messages.
prompt_lines = [];
answer_sprite = Sprite();
message = ""; active_prompt = ""; active_answer = "";
fun fit_text(text, red, green, blue) {
    image = Image.Text(text, red, green, blue);
    factor = 1;
    if (image.GetWidth() > Window.GetWidth() * 0.9) factor = Window.GetWidth() * 0.9 / image.GetWidth();
    if (image.GetHeight() * factor > Window.GetHeight() * 0.06) factor = Window.GetHeight() * 0.06 / image.GetHeight();
    if (factor < 1) image = image.Scale(image.GetWidth() * factor, image.GetHeight() * factor);
    return image;
}
fun hide_prompt() {
    for (j = 0; j < 8; j++) if (prompt_lines[j]) prompt_lines[j].SetOpacity(0);
    answer_sprite.SetOpacity(0);
}
fun set_art(opacity) {
    back.SetOpacity(opacity);
    ship.SetOpacity(opacity);
    for (j = 0; j < 3; j++) dots[j].SetOpacity(opacity);
}
fun show_prompt(prompt, answer) {
    active_prompt = prompt; active_answer = answer;
    hide_prompt();
    set_art(0);
    available = Window.GetWidth() * 0.9;
    line = "";
    word = "";
    count = 0;
    for (j = 0; j < 4096 && count < 8; j++) {
        char = prompt.CharAt(j);
        if (char != " " && char != "\n" && char != "") { word += char; continue; }
        candidate = line + word;
        if (line != "" && Image.Text(candidate, 1, 1, 1).GetWidth() > available) {
            image = fit_text(line, 1, 1, 1);
            prompt_lines[count] = Sprite(image);
            prompt_lines[count].SetPosition(Window.GetX() + (Window.GetWidth() - image.GetWidth()) / 2,
                Window.GetY() + Window.GetHeight() * 0.2 + count * Window.GetHeight() * 0.065, 100);
            count++;
            line = "";
        }
        line += word + " ";
        word = "";
        if (char == "" || char == "\n") {
            image = fit_text(line, 1, 1, 1);
            prompt_lines[count] = Sprite(image);
            prompt_lines[count].SetPosition(Window.GetX() + (Window.GetWidth() - image.GetWidth()) / 2,
                Window.GetY() + Window.GetHeight() * 0.2 + count * Window.GetHeight() * 0.065, 100);
            count++;
            line = "";
            if (char == "") break;
        }
    }
    answer_image = fit_text(answer, 1, 0.3, 0.4);
    answer_sprite.SetImage(answer_image);
    answer_sprite.SetPosition(Window.GetX() + (Window.GetWidth() - answer_image.GetWidth()) / 2,
                              Window.GetY() + Window.GetHeight() * 0.8, 100);
    answer_sprite.SetOpacity(1);
}
fun display_password_callback(prompt, bullets) {
    status = "password";
    masked = "";
    for (j = 0; j < bullets && j < 32; j++) masked += "*";
    show_prompt(prompt, masked);
}
fun display_question_callback(prompt, entry) { status = "question"; show_prompt(prompt, entry); }
fun display_normal_callback() {
    status = "normal";
    active_prompt = ""; active_answer = "";
    hide_prompt();
    set_art(1);
    if (message != "") { status = "message"; show_prompt(message, ""); }
}
fun message_callback(text) {
    message = text;
    if (status == "normal" || status == "message") { status = "message"; show_prompt(text, ""); }
}
fun hide_message_callback(text) {
    if (text != message) return;
    message = "";
    if (status == "message") display_normal_callback();
}
Plymouth.SetDisplayPasswordFunction(display_password_callback);
Plymouth.SetDisplayQuestionFunction(display_question_callback);
Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayMessageFunction(message_callback);
Plymouth.SetHideMessageFunction(hide_message_callback);

fun hotplug_callback() {
    layout_callback();
    if (status != "normal") show_prompt(active_prompt, active_answer);
}
Plymouth.SetDisplayHotplugFunction(hotplug_callback);
APOLLO_SCRIPT
chmod 0644 /usr/share/plymouth/themes/crimson-apollo/*
# Record the stock choice for a later reversible recovery; do not rebuild twice.
plymouth-set-default-theme > /etc/moonlight-plymouth-previous-theme
plymouth-set-default-theme crimson-apollo
cat > /etc/dracut.conf.d/90-moonlight-plymouth.conf <<'APOLLO_DRACUT'
add_dracutmodules+=" plymouth "
install_items+=" /usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf "
APOLLO_DRACUT
# Rebuild only the installed, pinned kernel after DKMS and theme installation.
test "$KVER" = "6.19.10-300.fc44.x86_64"
dracut --force --kver "$KVER" "/boot/initramfs-$KVER.img"
# END GENERATED CRIMSON APOLLO PAYLOAD
# A failed splash must not hold Getty behind an unlimited quit-wait service.
for unit in plymouth-quit.service plymouth-quit-wait.service; do
  install -d "/etc/systemd/system/$unit.d"
  cat > "/etc/systemd/system/$unit.d/moonlight-timeout.conf" <<'APOLLO_TIMEOUT'
[Service]
TimeoutStartSec=5
APOLLO_TIMEOUT
done

# BEGIN FRONTEND INTEGRATION
cat > /usr/local/share/moonlight-os/FRONTENDS.lock <<'FRONTENDS_LOCK'
# Build inputs pinned 2026-10-01
FEDORA_RELEASE=44
FEDORA_COMPOSE=1.7
FEDORA_ISO=Fedora-Everything-netinst-x86_64-44-1.7.iso
FEDORA_ISO_SHA256=bd285201494dd0ba09b54d05ac707de1401668b8512a573edb5922dcf9d7067e
FEDORA_ISO_URL=https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-44-1.7.iso

COCOOS_REPO=https://github.com/Djingerr/CocoOS.git
COCOOS_COMMIT=8c22132f1ce4146c0d6bff812f6fc8f724fe0101

MOONLIGHT_REPO=https://github.com/moonlight-stream/moonlight-qt.git
MOONLIGHT_COMMIT=8369d1a0e11b999d4d1598f62ca5f6dea49602fb

AUDIO_REPO=https://github.com/davidjo/snd_hda_macbookpro.git
AUDIO_COMMIT=89b22ff90b86468b186706861dd18663562defa7

# Kernel installed by pinned Fedora 44 Everything netinst 44-1.7 media during image build.
INSTALLER_KERNEL=6.19.10-300.fc44.x86_64

# Optional frontends pinned 2026-10-02; never resolve mutable "latest" during build.
VIBEMIS_VERSION=0.5.0
VIBEMIS_REPO=https://github.com/navyas321/vibemis.git
VIBEMIS_COMMIT=c3032fc8ee56188a91c1f5a3a8aeae6cf36fb6de
ARTEMIS_REPO=https://github.com/wjbeckett/artemis.git
ARTEMIS_COMMIT=afe2de7f2b24a2f6161f5672e8aa38450fa793ef
PEGASUS_VERSION=alpha16-106-g83fd27f4
PEGASUS_URL=https://github.com/mmatyas/pegasus-frontend/releases/download/continuous/pegasus-fe_alpha16-106-g83fd27f4_x11-static.zip
PEGASUS_SHA256=85842b658796a67aeaefd2eeef8d3ee1999c675661bf443fa34e999e394bc550

# Reviewed EclipseOS Vibemis theme/status patch.
VIBEMIS_PATCH_SHA256=2d356058e76e20e2f176ce48c1a6351ec9f65c134bc44e6c3aad022d5d04947b
FRONTENDS_LOCK
base64 -d > /usr/local/share/moonlight-os/vibemis-crimson.patch <<'VIBEMIS_PATCH_B64'
ZGlmZiAtLWdpdCBhL2FwcC9hcHAucHJvIGIvYXBwL2FwcC5wcm8KaW5kZXggYzE4ODZhNC4uYzg2
M2MzMyAxMDA2NDQKLS0tIGEvYXBwL2FwcC5wcm8KKysrIGIvYXBwL2FwcC5wcm8KQEAgLTU3OSwx
MSArNTc5LDExIEBAIHVuaXg6IW1hY3g6IHsKICAgICAjIFZpYmVtaXMgbWFyayBpbnN0ZWFkIG9m
IGEgZ2VuZXJpYyBpY29uLiBUaGUgLmRlc2t0b3AgSWNvbj0ga2V5IGlzCiAgICAgIyAidmliZW1p
cyIsIHdoaWNoIG1hdGNoZXMgdGhlc2UgZmlsZXMnIGJhc2VuYW1lLiBXZSBzaGlwIHJlYWwgUE5H
cyBhdAogICAgICMgMTI4LzI1Ni81MTIgKHRoZXJlIGlzIG5vIHZlY3RvciBtYXN0ZXIgZm9yIHRo
ZSByYXN0ZXIgYnJhbmQgbWFyaykuCi0gICAgaWNvbjEyOC5maWxlcyA9IHJlcy9pY29ucy9oaWNv
bG9yLzEyOHgxMjgvYXBwcy92aWJlbWlzLnBuZworICAgIGljb24xMjguZmlsZXMgPSByZXMvaWNv
bnMvaGljb2xvci8xMjh4MTI4L2FwcHMvZWNsaXBzZS5wbmcKICAgICBpY29uMTI4LnBhdGggPSAk
JFBSRUZJWC8kJERBVEFESVIvaWNvbnMvaGljb2xvci8xMjh4MTI4L2FwcHMvCi0gICAgaWNvbjI1
Ni5maWxlcyA9IHJlcy9pY29ucy9oaWNvbG9yLzI1NngyNTYvYXBwcy92aWJlbWlzLnBuZworICAg
IGljb24yNTYuZmlsZXMgPSByZXMvaWNvbnMvaGljb2xvci8yNTZ4MjU2L2FwcHMvZWNsaXBzZS5w
bmcKICAgICBpY29uMjU2LnBhdGggPSAkJFBSRUZJWC8kJERBVEFESVIvaWNvbnMvaGljb2xvci8y
NTZ4MjU2L2FwcHMvCi0gICAgaWNvbjUxMi5maWxlcyA9IHJlcy9pY29ucy9oaWNvbG9yLzUxMng1
MTIvYXBwcy92aWJlbWlzLnBuZworICAgIGljb241MTIuZmlsZXMgPSByZXMvaWNvbnMvaGljb2xv
ci81MTJ4NTEyL2FwcHMvZWNsaXBzZS5wbmcKICAgICBpY29uNTEyLnBhdGggPSAkJFBSRUZJWC8k
JERBVEFESVIvaWNvbnMvaGljb2xvci81MTJ4NTEyL2FwcHMvCiAKICAgICBhcHBzdHJlYW0uZmls
ZXMgPSBkZXBsb3kvbGludXgvY29tLnZpYmVtaXMuVmliZW1pcy5hcHBkYXRhLnhtbApAQCAtNjMx
LDMgKzYzMSwyMCBAQCBtYWN4IHsKICMgY291bnRzKSBvciB0aGUgc21hcnQtYnVpbGQgY2hlY2sg
c2tpcHMgdGhlIHJlbGVhc2UuCiBWRVJTSU9OID0gIiQkY2F0KHZlcnNpb24udHh0KSIKIERFRklO
RVMgKz0gVkVSU0lPTl9TVFI9XFxcIiQkY2F0KHZlcnNpb24udHh0KVxcXCIKKworIyBFY2xpcHNl
T1Mgb3B0aW9uYWwgbGF1bmNoZXIgc3RhdHVzIGFuZCBob3N0IHN0YXRzLgorU09VUkNFUyArPSBt
b29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcAorSEVBREVSUyArPSBtb29ubGlnaHRvcy9jcmlt
c29uc3RhdHVzLmgKKworIyBDb21waWxlIHRoZSBhcHBsaWFuY2Utb3duZWQgdXBkYXRlciwgbm90
IHRoZSB1cHN0cmVhbSBmZWVkL0FwcEltYWdlIGluc3RhbGxlci4KK1NPVVJDRVMgLT0gYmFja2Vu
ZC9hdXRvdXBkYXRlY2hlY2tlci5jcHAKK1NPVVJDRVMgKz0gbW9vbmxpZ2h0b3MvbWFuYWdlZHVw
ZGF0ZXMuY3BwCisKK1NPVVJDRVMgKz0gbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuY3BwCitI
RUFERVJTICs9IG1vb25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmgKKworU09VUkNFUyArPSBtb29u
bGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwCitIRUFERVJTICs9IG1vb25saWdodG9zL2VjbGlw
c2Vwcm9maWxlcy5oCisKK1NPVVJDRVMgKz0gbW9vbmxpZ2h0b3MvbG9jYWxoYXJkd2FyZS5jcHAK
K0hFQURFUlMgKz0gbW9vbmxpZ2h0b3MvbG9jYWxoYXJkd2FyZS5oCmRpZmYgLS1naXQgYS9hcHAv
YmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5oIGIvYXBwL2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNr
ZXIuaAppbmRleCA1ZWI5OGNiLi43YmFlYTk4IDEwMDY0NAotLS0gYS9hcHAvYmFja2VuZC9hdXRv
dXBkYXRlY2hlY2tlci5oCisrKyBiL2FwcC9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgKQEAg
LTI5LDYgKzI5LDkgQEAgY2xhc3MgQXV0b1VwZGF0ZUNoZWNrZXIgOiBwdWJsaWMgUU9iamVjdAog
ewogICAgIFFfT0JKRUNUCiAKKyAgICAvLyBUaGlzIGN1c3RvbWl6ZWQgYXBwbGlhbmNlIGlzIHVw
ZGF0ZWQgd2l0aCBFY2xpcHNlT1MsIG5ldmVyIHVwc3RyZWFtIEFwcEltYWdlcy4KKyAgICBRX1BS
T1BFUlRZKGJvb2wgb3NNYW5hZ2VkIFJFQUQgb3NNYW5hZ2VkIENPTlNUQU5UKQorCiAgICAgLy8g
QSBzdHJpY3RseS1uZXdlciBidWlsZCBleGlzdHMgb24gdGhlIGNoYW5uZWwg4oCUIHBvd2VycyB0
aGUgdG9vbGJhciBiYW5uZXIuCiAgICAgUV9QUk9QRVJUWShib29sIHVwZGF0ZUF2YWlsYWJsZSBS
RUFEIHVwZGF0ZUF2YWlsYWJsZSBOT1RJRlkgc3RhdGVDaGFuZ2VkKQogICAgIC8vIFRoZSBjaGFu
bmVsJ3MgbmV3ZXN0IGJ1aWxkIGRpZmZlcnMgZnJvbSB0aGUgcnVubmluZyBvbmUgKG1heSBiZSBv
bGRlciDigJQKQEAgLTUxLDYgKzU0LDcgQEAgY2xhc3MgQXV0b1VwZGF0ZUNoZWNrZXIgOiBwdWJs
aWMgUU9iamVjdAogCiBwdWJsaWM6CiAgICAgZXhwbGljaXQgQXV0b1VwZGF0ZUNoZWNrZXIoUU9i
amVjdCAqcGFyZW50ID0gbnVsbHB0cik7CisgICAgYm9vbCBvc01hbmFnZWQoKSBjb25zdCB7IHJl
dHVybiB0cnVlOyB9CiAKICAgICAvLyBMYXVuY2gtdGltZSBlbnRyeSBwb2ludDogcXVpZXQgY2hl
Y2sgbm93LCB0aGVuIGEgcGVyaW9kaWMgcmUtY2hlY2sgZXZlcnkKICAgICAvLyBSRUNIRUNLX0lO
VEVSVkFMX01TIChhIGxhdW5jaC1vbmx5IGNoZWNrIGtlcHQgdXNlcnMgYmxpbmQgdG8gYW55dGhp
bmcKZGlmZiAtLWdpdCBhL2FwcC9kZXBsb3kvbGludXgvY29tLnZpYmVtaXMuVmliZW1pcy5kZXNr
dG9wIGIvYXBwL2RlcGxveS9saW51eC9jb20udmliZW1pcy5WaWJlbWlzLmRlc2t0b3AKaW5kZXgg
MzRiOGZhZS4uMDM5ODg2OCAxMDA2NDQKLS0tIGEvYXBwL2RlcGxveS9saW51eC9jb20udmliZW1p
cy5WaWJlbWlzLmRlc2t0b3AKKysrIGIvYXBwL2RlcGxveS9saW51eC9jb20udmliZW1pcy5WaWJl
bWlzLmRlc2t0b3AKQEAgLTEsOCArMSw4IEBACiBbRGVza3RvcCBFbnRyeV0KLU5hbWU9VmliZW1p
cwotQ29tbWVudD1MaW51eC1mb2N1c2VkIFZpYmVtaXMgUXQgZm9yayB0dW5lZCBmb3IgcGFpcmlu
ZyB3aXRoIFZpYmVwb2xsby4gU3RyZWFtcyBnYW1lcyBhbmQgYXBwbGljYXRpb25zIGZyb20gYSBT
dW5zaGluZSAvIEFwb2xsbyAvIFZpYmVwb2xsbyBob3N0LgorTmFtZT1FY2xpcHNlCitDb21tZW50
PUVjbGlwc2Ug4oCUIHRoZSBFY2xpcHNlT1MgZnJvbnRlbmQuIFN0cmVhbXMgZ2FtZXMgYW5kIGFw
cGxpY2F0aW9ucyBmcm9tIGEgU3Vuc2hpbmUgLyBBcG9sbG8gLyBWaWJlcG9sbG8gaG9zdC4KIEV4
ZWM9dmliZW1pcwotSWNvbj12aWJlbWlzCitJY29uPWVjbGlwc2UKIFN0YXJ0dXBXTUNsYXNzPWNv
bS52aWJlbWlzLlZpYmVtaXMKIFRlcm1pbmFsPWZhbHNlCiBUeXBlPUFwcGxpY2F0aW9uCmRpZmYg
LS1naXQgYS9hcHAvZ3VpL0FwcFZpZXcucW1sIGIvYXBwL2d1aS9BcHBWaWV3LnFtbAppbmRleCA2
M2Y2NDVkLi4zODNhZGI3IDEwMDY0NAotLS0gYS9hcHAvZ3VpL0FwcFZpZXcucW1sCisrKyBiL2Fw
cC9ndWkvQXBwVmlldy5xbWwKQEAgLTExLDYgKzExLDcgQEAgaW1wb3J0IENvbXB1dGVyTWFuYWdl
ciAxLjAKIGltcG9ydCBTZGxHYW1lcGFkS2V5TmF2aWdhdGlvbiAxLjAKIAogQ2VudGVyZWRHcmlk
VmlldyB7CisgICAgcHJvcGVydHkgdmFyIGNyaW1zb25Ib3N0OiAoe30pCiAgICAgcHJvcGVydHkg
aW50IGNvbXB1dGVySW5kZXgKICAgICBwcm9wZXJ0eSBBcHBNb2RlbCBhcHBNb2RlbCA6IGNyZWF0
ZU1vZGVsKCkKICAgICBwcm9wZXJ0eSBib29sIGFjdGl2YXRlZApkaWZmIC0tZ2l0IGEvYXBwL2d1
aS9BdXRvUmVzaXppbmdDb21ib0JveC5xbWwgYi9hcHAvZ3VpL0F1dG9SZXNpemluZ0NvbWJvQm94
LnFtbAppbmRleCA1M2FmY2FmLi5mMTIzOTMyIDEwMDY0NAotLS0gYS9hcHAvZ3VpL0F1dG9SZXNp
emluZ0NvbWJvQm94LnFtbAorKysgYi9hcHAvZ3VpL0F1dG9SZXNpemluZ0NvbWJvQm94LnFtbApA
QCAtMSw1ICsxLDYgQEAKIGltcG9ydCBRdFF1aWNrIDIuOQogaW1wb3J0IFF0UXVpY2suQ29udHJv
bHMgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKIAogaW1wb3J0IFNkbEdhbWVwYWRL
ZXlOYXZpZ2F0aW9uIDEuMAogaW1wb3J0IFN5c3RlbVByb3BlcnRpZXMgMS4wCkBAIC05Miw3ICs5
Myw3IEBAIENvbWJvQm94IHsKICAgICAgICAgLy8gT3ZlcnJpZGUgdGhlIHBvcHVwIGNvbG9yIHRv
IGltcHJvdmUgY29udHJhc3Qgd2l0aCB0aGUgb3ZlcnJpZGRlbgogICAgICAgICAvLyBNYXRlcmlh
bCAyIGJhY2tncm91bmQgY29sb3Igc2V0IGluIG1haW4ucW1sLgogICAgICAgICBpZiAoU3lzdGVt
UHJvcGVydGllcy51c2VzTWF0ZXJpYWwzVGhlbWUpIHsKLSAgICAgICAgICAgIHBvcHVwLmJhY2tn
cm91bmQuY29sb3IgPSAiIzQyNDI0MiIKKyAgICAgICAgICAgIHBvcHVwLmJhY2tncm91bmQuY29s
b3IgPSBRdC5iaW5kaW5nKGZ1bmN0aW9uKCkgeyByZXR1cm4gVmJUb2tlbnMuYmdFbGV2MiB9KQog
ICAgICAgICB9CiAgICAgfQogCmRpZmYgLS1naXQgYS9hcHAvZ3VpL0NyaW1zb25TdGF0dXNEaWFs
b2cucW1sIGIvYXBwL2d1aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbApuZXcgZmlsZSBtb2RlIDEw
MDY0NAppbmRleCAwMDAwMDAwLi42ODcwZjljCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9D
cmltc29uU3RhdHVzRGlhbG9nLnFtbApAQCAtMCwwICsxLDkwIEBACitpbXBvcnQgUXRRdWljayAy
LjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAx
LjMKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVtaXMu
UmVkZXNpZ24gMS4wCitpbXBvcnQgQ3JpbXNvblN0YXR1cyAxLjAKKworTmF2aWdhYmxlRGlhbG9n
IHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9wZXJ0eSBzdHJpbmcga2luZDogImhvc3QiCisgICAg
d2lkdGg6IE1hdGgubWluKDYyMCwgcGFyZW50LndpZHRoIC0gMzIpCisgICAgaGVpZ2h0OiBNYXRo
Lm1pbihraW5kID09PSAiaG9zdCIgPyA2NTAgOiAyODAsIHBhcmVudC5oZWlnaHQgLSAzMikKKyAg
ICB0aXRsZToga2luZCA9PT0gImhvc3QiID8gcXNUcigiVmliZXBvbGxvIOKAoiBIb3N0IGhhcmR3
YXJlIikgOiBraW5kID09PSAibmV0d29yayIgPyBxc1RyKCJOZXR3b3JrIHN0YXR1cyIpIDogcXNU
cigiQmF0dGVyeSBzdGF0dXMiKQorICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLkNsb3NlCisg
ICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYWNj
ZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgeyBjb2xvcjog
VmJUb2tlbnMuYmdFbGV2OyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0RpYWxvZzsgYm9yZGVyLmNv
bG9yOiBWYlRva2Vucy5zdHJva2U7IGJvcmRlci53aWR0aDogMSB9CisgICAgb25PcGVuZWQ6IHsK
KyAgICAgICAgdXJsSW5wdXQudGV4dCA9IENyaW1zb25TdGF0dXMuZW5kcG9pbnQKKyAgICAgICAg
cGluSW5wdXQudGV4dCA9IENyaW1zb25TdGF0dXMuZmluZ2VycHJpbnQKKyAgICAgICAgdG9rZW5J
bnB1dC50ZXh0ID0gIiIKKyAgICAgICAgQ3JpbXNvblN0YXR1cy5zZXRWaXNpYmxlKGtpbmQgPT09
ICJob3N0IikKKyAgICB9CisgICAgb25DbG9zZWQ6IHsgQ3JpbXNvblN0YXR1cy5zZXRWaXNpYmxl
KGZhbHNlKTsgdG9rZW5JbnB1dC50ZXh0ID0gIiI7IHN0YWNrVmlldy5mb3JjZUFjdGl2ZUZvY3Vz
KCkgfQorICAgIGZ1bmN0aW9uIG1ldHJpYyhrZXksIHN1ZmZpeCkgeworICAgICAgICB2YXIgbiA9
IENyaW1zb25TdGF0dXMuc3RhdHNba2V5XQorICAgICAgICByZXR1cm4gbiA9PT0gdW5kZWZpbmVk
ID8gcXNUcigiTi9BIikgOiBOdW1iZXIobikudG9GaXhlZCgxKSArIHN1ZmZpeAorICAgIH0KKyAg
ICBmdW5jdGlvbiBtZW1vcnkocHJlZml4KSB7CisgICAgICAgIHZhciBzID0gQ3JpbXNvblN0YXR1
cy5zdGF0cworICAgICAgICByZXR1cm4gc1twcmVmaXggKyAiX3VzZWRfYnl0ZXMiXSA9PT0gdW5k
ZWZpbmVkIHx8ICFzW3ByZWZpeCArICJfdG90YWxfYnl0ZXMiXSA/IHFzVHIoIk4vQSIpCisgICAg
ICAgICAgICAgOiAoc1twcmVmaXggKyAiX3VzZWRfYnl0ZXMiXSAvIDEwNzM3NDE4MjQpLnRvRml4
ZWQoMSkgKyAiIC8gIiArIChzW3ByZWZpeCArICJfdG90YWxfYnl0ZXMiXSAvIDEwNzM3NDE4MjQp
LnRvRml4ZWQoMSkgKyAiIEdpQiIKKyAgICB9CisgICAgY29udGVudEl0ZW06IFNjcm9sbFZpZXcg
eworICAgICAgICBjbGlwOiB0cnVlCisgICAgICAgIGNvbnRlbnRXaWR0aDogYXZhaWxhYmxlV2lk
dGgKKyAgICAgICAgQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAgIHdpZHRoOiBwYW5lbC5hdmFp
bGFibGVXaWR0aAorICAgICAgICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCisgICAgICAg
ICAgICBMYWJlbCB7CisgICAgICAgICAgICAgICAgdmlzaWJsZTogcGFuZWwua2luZCAhPT0gImhv
c3QiCisgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRl
eHQuV3JhcAorICAgICAgICAgICAgICAgIHRleHQ6IHBhbmVsLmtpbmQgPT09ICJuZXR3b3JrIiA/
IChDcmltc29uU3RhdHVzLmxvY2FsLm5ldHdvcmsgKyAoQ3JpbXNvblN0YXR1cy5sb2NhbC53aWZp
U2lnbmFsID49IDAgPyAiIOKAoiAiICsgQ3JpbXNvblN0YXR1cy5sb2NhbC53aWZpU2lnbmFsICsg
IiUgc2lnbmFsIiA6ICIiKSArICJcbiIgKyBxc1RyKCJBY3RpdmUgbGluayBzdGF0dXM7IGludGVy
bmV0IGFjY2VzcyBpcyBub3QgYXNzdW1lZC4iKSkKKyAgICAgICAgICAgICAgICAgICAgOiAoQ3Jp
bXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAwID8gQ3JpbXNvblN0YXR1cy5sb2Nh
bC5iYXR0ZXJ5UGVyY2VudCArICIlIOKAoiAiIDogIiIpICsgQ3JpbXNvblN0YXR1cy5sb2NhbC5i
YXR0ZXJ5U3RhdGUKKyAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5w
aXhlbFNpemU6IFZiVG9rZW5zLnR5cGVCb2R5CisgICAgICAgICAgICB9CisgICAgICAgICAgICBM
YWJlbCB7CisgICAgICAgICAgICAgICAgdmlzaWJsZTogcGFuZWwua2luZCA9PT0gImhvc3QiCisg
ICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3Jh
cAorICAgICAgICAgICAgICAgIHRleHQ6IENyaW1zb25TdGF0dXMuc3RhdHVzCisgICAgICAgICAg
ICAgICAgY29sb3I6IFZiVG9rZW5zLnRleHREaW0KKyAgICAgICAgICAgIH0KKyAgICAgICAgICAg
IFJlcGVhdGVyIHsKKyAgICAgICAgICAgICAgICBtb2RlbDogcGFuZWwua2luZCA9PT0gImhvc3Qi
ID8gWworICAgICAgICAgICAgICAgICAgICBbcXNUcigiQ1BVIiksIHBhbmVsLm1ldHJpYygiY3B1
X3BlcmNlbnQiLCAiJSIpLCBwYW5lbC5tZXRyaWMoImNwdV90ZW1wX2MiLCAiIMKwQyIpXSwKKyAg
ICAgICAgICAgICAgICAgICAgW3FzVHIoIlJBTSIpLCBwYW5lbC5tZW1vcnkoInJhbSIpLCBwYW5l
bC5tZXRyaWMoInJhbV9wZXJjZW50IiwgIiUiKV0sCisgICAgICAgICAgICAgICAgICAgIFtxc1Ry
KCJHUFUiKSwgcGFuZWwubWV0cmljKCJncHVfcGVyY2VudCIsICIlIiksIHBhbmVsLm1ldHJpYygi
Z3B1X3RlbXBfYyIsICIgwrBDIildLAorICAgICAgICAgICAgICAgICAgICBbcXNUcigiVlJBTSIp
LCBwYW5lbC5tZW1vcnkoInZyYW0iKSwgcGFuZWwubWV0cmljKCJ2cmFtX3BlcmNlbnQiLCAiJSIp
XSwKKyAgICAgICAgICAgICAgICAgICAgW3FzVHIoIkdQVSBlbmNvZGVyIiksIHBhbmVsLm1ldHJp
YygiZ3B1X2VuY29kZXJfcGVyY2VudCIsICIlIiksICIiXSwKKyAgICAgICAgICAgICAgICAgICAg
W3FzVHIoIkhvc3QgbmV0d29yayIpLCBwYW5lbC5tZXRyaWMoIm5ldF9yeF9icHMiLCAiIEIvcyBS
WCIpLCBwYW5lbC5tZXRyaWMoIm5ldF90eF9icHMiLCAiIEIvcyBUWCIpXQorICAgICAgICAgICAg
ICAgIF0gOiBbXQorICAgICAgICAgICAgICAgIGRlbGVnYXRlOiBSZWN0YW5nbGUgeworICAgICAg
ICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBpbXBsaWNpdEhlaWdodDogNTgK
KyAgICAgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLmJnV2luZG93OyByYWRpdXM6IFZi
VG9rZW5zLnJhZGl1c0NvbnRyb2wKKyAgICAgICAgICAgICAgICAgICAgYm9yZGVyLmNvbG9yOiBW
YlRva2Vucy5zdHJva2U7IGJvcmRlci53aWR0aDogMQorICAgICAgICAgICAgICAgICAgICBSb3dM
YXlvdXQgeworICAgICAgICAgICAgICAgICAgICAgICAgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGFu
Y2hvcnMubWFyZ2luczogMTIKKyAgICAgICAgICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDog
bW9kZWxEYXRhWzBdOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbTsgTGF5b3V0LnByZWZlcnJlZFdp
ZHRoOiAxMTUgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBtb2RlbERh
dGFbMV07IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlIH0KKyAg
ICAgICAgICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogbW9kZWxEYXRhWzJdOyBjb2xvcjog
VmJUb2tlbnMuYWNjZW50IH0KKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAg
IH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIEdyb3VwQm94IHsKKyAgICAgICAgICAgICAg
ICB2aXNpYmxlOiBwYW5lbC5raW5kID09PSAiaG9zdCIKKyAgICAgICAgICAgICAgICB0aXRsZTog
cXNUcigiQ29uZmlndXJlIGhvc3Qgc3RhdHMiKQorICAgICAgICAgICAgICAgIExheW91dC5maWxs
V2lkdGg6IHRydWUKKyAgICAgICAgICAgICAgICBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAg
ICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7
IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIo
IlNlbGVjdCBhIGhvc3QgZmlyc3QuIEVuYWJsZSByZWFsdGltZSBzdGF0cyBpbiBWaWJlcG9sbG8g
YW5kIGNyZWF0ZSBhIHJlYWQtb25seSB0b2tlbiBmb3IgR0VUIC9hcGkvaG9zdC9zdGF0cy4gR2Ft
ZVN0cmVhbSBwYWlyaW5nIGRvZXMgbm90IGdyYW50IHRoaXMgYWNjZXNzLiIpOyBjb2xvcjogVmJU
b2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICAgICAgICAgIFRleHRGaWVsZCB7IGlkOiB1cmxJ
bnB1dDsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgcGxhY2Vob2xkZXJUZXh0OiBxc1RyKCJIVFRQ
UyBob3N0IFVSTCwgZS5nLiBodHRwczovLzE5Mi4xNjguMS4xMDo0Nzk5MCIpOyBzZWxlY3RCeU1v
dXNlOiB0cnVlIH0KKyAgICAgICAgICAgICAgICAgICAgVGV4dEZpZWxkIHsgaWQ6IHRva2VuSW5w
dXQ7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHBsYWNlaG9sZGVyVGV4dDogcXNUcigiUmVhZC1v
bmx5IEFQSSB0b2tlbiAoYmxhbmsga2VlcHMgc2F2ZWQgdG9rZW4pIik7IGVjaG9Nb2RlOiBUZXh0
SW5wdXQuUGFzc3dvcmQ7IHNlbGVjdEJ5TW91c2U6IHRydWUgfQorICAgICAgICAgICAgICAgICAg
ICBUZXh0RmllbGQgeyBpZDogcGluSW5wdXQ7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHBsYWNl
aG9sZGVyVGV4dDogcXNUcigiU0hBLTI1NiBjZXJ0aWZpY2F0ZSBmaW5nZXJwcmludCBmb3IgYSBz
ZWxmLXNpZ25lZCBob3N0Iik7IHNlbGVjdEJ5TW91c2U6IHRydWUgfQorICAgICAgICAgICAgICAg
ICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7
IHRleHQ6IHFzVHIoIlZlcmlmeSBhIHNlbGYtc2lnbmVkIGNlcnRpZmljYXRlJ3MgU0hBLTI1NiBm
aW5nZXJwcmludCBvbiB0aGUgaG9zdCBiZWZvcmUgc2F2aW5nIGl0LiBUb2tlbiBpcyBzdG9yZWQg
cHJpdmF0ZWx5IG9uIHRoaXMgVVNCOyBpdCBpcyBub3QgZW5jcnlwdGVkLiBVbnN1cHBvcnRlZCBv
ciBtaXNzaW5nIHNlbnNvcnMgc2hvdyBOL0EuIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0K
KyAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsgdGV4dDogcXNUcigiU2F2ZSAmIGNvbm5lY3Qi
KTsgb25DbGlja2VkOiB7IGlmIChDcmltc29uU3RhdHVzLmNvbmZpZ3VyZSh1cmxJbnB1dC50ZXh0
LCB0b2tlbklucHV0LnRleHQsIHBpbklucHV0LnRleHQpKSB0b2tlbklucHV0LnRleHQgPSAiIiB9
IH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9Cit9
CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0VjbGlwc2VBYm91dERpYWxvZy5xbWwgYi9hcHAvZ3VpL0Vj
bGlwc2VBYm91dERpYWxvZy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4u
M2FiNzgwNQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNsaXBzZUFib3V0RGlhbG9nLnFt
bApAQCAtMCwwICsxLDM0IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNv
bnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBRdFF1aWNrLkNv
bnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitOYXZpZ2Fi
bGVEaWFsb2cgeworICAgIGlkOiBwYW5lbAorICAgIHByb3BlcnR5IHZhciBpbmZvOiAoe30pCisg
ICAgd2lkdGg6IE1hdGgubWluKDUyMCxwYXJlbnQud2lkdGgtMzIpCisgICAgdGl0bGU6IHFzVHIo
IkFib3V0IEVjbGlwc2UiKQorICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLkNsb3NlCisgICAg
TWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYWNjZW50
OiBWYlRva2Vucy5hY2NlbnQKKyAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgeyByYWRpdXM6IFZi
VG9rZW5zLnJhZGl1c0RpYWxvZzsgY29sb3I6IFZiVG9rZW5zLmJnRWxldjsgYm9yZGVyLmNvbG9y
OiBWYlRva2Vucy5zdHJva2UKKyAgICAgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy5maWxsOiBwYXJl
bnQ7IGNvbG9yOiAidHJhbnNwYXJlbnQiOyBncmFkaWVudDogR3JhZGllbnQgeyBHcmFkaWVudFN0
b3AgeyBwb3NpdGlvbjogMDsgY29sb3I6IFF0LnJnYmEoMSwxLDEsMC4wMzUpIH0gR3JhZGllbnRT
dG9wIHsgcG9zaXRpb246IDE7IGNvbG9yOiAidHJhbnNwYXJlbnQiIH0gfSB9CisgICAgfQorICAg
IGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5z
cGFjZTMKKyAgICAgICAgSW1hZ2UgeyBzb3VyY2U6ICJxcmM6L3Jlcy9lY2xpcHNlLWljb24uc3Zn
Ijsgc291cmNlU2l6ZS53aWR0aDogOTY7IHNvdXJjZVNpemUuaGVpZ2h0OiA5NjsgTGF5b3V0LmFs
aWdubWVudDogUXQuQWxpZ25IQ2VudGVyOyBMYXlvdXQucHJlZmVycmVkV2lkdGg6IDk2OyBMYXlv
dXQucHJlZmVycmVkSGVpZ2h0OiA5NiB9CisgICAgICAgIExhYmVsIHsgdGV4dDogIkVDTElQU0Ui
OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5
OyBmb250LnBpeGVsU2l6ZTogMjQ7IGZvbnQubGV0dGVyU3BhY2luZzogNDsgTGF5b3V0LmFsaWdu
bWVudDogUXQuQWxpZ25IQ2VudGVyIH0KKyAgICAgICAgTGFiZWwgeyB0ZXh0OiBxc1RyKCJNYWRl
IGJ5IFRoM0QzY2szciIpOyBjb2xvcjogVmJUb2tlbnMuYWNjZW50OyBMYXlvdXQuYWxpZ25tZW50
OiBRdC5BbGlnbkhDZW50ZXIgfQorICAgICAgICBMYWJlbCB7CisgICAgICAgICAgICBMYXlvdXQu
ZmlsbFdpZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRl
eHQuV3JhcDsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0KKyAgICAgICAgICAgIHRleHQ6IHFzVHIo
Ik9TOiAlMSAlMlxuVGFyZ2V0OiAlM1xuRmVkb3JhOiAlNFxuS2VybmVsOiAlNVxuRWNsaXBzZSBm
cm9udGVuZDogJTYg4oCiIGN1c3RvbWl6ZWQiKQorICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVs
LmluZm8ub3MgfHwge30pLk5BTUUgfHwgIkVjbGlwc2VPUyIpCisgICAgICAgICAgICAgICAgLmFy
ZygocGFuZWwuaW5mby5vcyB8fCB7fSkuVkVSU0lPTiB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQor
ICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3MgfHwge30pLlRBUkdFVCB8fCBxc1Ry
KCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3MgfHwg
e30pLkZFRE9SQSB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIC5hcmco
cGFuZWwuaW5mby5rZXJuZWwgfHwgcXNUcigiVW5hdmFpbGFibGUiKSkKKyAgICAgICAgICAgICAg
ICAuYXJnKFF0LmFwcGxpY2F0aW9uLnZlcnNpb24gfHwgIjAuNS4wIikKKyAgICAgICAgfQorICAg
ICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7
IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltOyB0ZXh0OiBxc1RyKCJBIGxpZ2h0d2VpZ2h0IEVjbGlw
c2VPUyBmcm9udGVuZC4gQmFzZWQgb24gVmliZW1pcyBhbmQgTW9vbmxpZ2h0OyBvcmlnaW5hbCBv
cGVuLXNvdXJjZSBjcmVkaXRzIGFuZCBsaWNlbnNlcyByZW1haW4gYXZhaWxhYmxlIGluIFNldHRp
bmdzLiBVcGRhdGVzIGFyZSBtYW5hZ2VkIGJ5IEVjbGlwc2VPUy4iKSB9CisgICAgfQorfQpkaWZm
IC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlQWN0aW9uQnV0dG9uLnFtbCBiL2FwcC9ndWkvRWNsaXBz
ZUFjdGlvbkJ1dHRvbi5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uOGFk
NWM5NAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5xbWwK
QEAgLTAsMCArMSwzNSBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250
cm9scyAyLjUKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFF0UXVpY2suQ29u
dHJvbHMuaW1wbCAyLjUKK0J1dHRvbiB7CisgICAgaWQ6IGJ1dHRvbgorICAgIHRvcEluc2V0OiAw
OyBib3R0b21JbnNldDogMDsgbGVmdEluc2V0OiAwOyByaWdodEluc2V0OiAwCisgICAgcHJvcGVy
dHkgc3RyaW5nIGljb25Tb3VyY2U6ICIiCisgICAgaW1wbGljaXRIZWlnaHQ6IE1hdGgubWF4KDQ0
LGNvbnRlbnRJdGVtLmltcGxpY2l0SGVpZ2h0ICsgMjApCisgICAgaW1wbGljaXRXaWR0aDogTWF0
aC5tYXgoMTAwLCBjb250ZW50SXRlbS5pbXBsaWNpdFdpZHRoICsgMjgpCisgICAgcGFkZGluZzog
MTIKKyAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKKyAgICBmb250LnBpeGVsU2l6
ZTogVmJUb2tlbnMudHlwZUxhYmVsCisgICAgQWNjZXNzaWJsZS5uYW1lOiB0ZXh0CisgICAgYWN0
aXZlRm9jdXNPblRhYjogdHJ1ZQorICAgIEtleXMub25SZXR1cm5QcmVzc2VkOiBpZiAoZW5hYmxl
ZCkgY2xpY2tlZCgpCisgICAgS2V5cy5vbkVudGVyUHJlc3NlZDogaWYgKGVuYWJsZWQpIGNsaWNr
ZWQoKQorICAgIEtleXMub25SaWdodFByZXNzZWQ6IG5leHRJdGVtSW5Gb2N1c0NoYWluKHRydWUp
LmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgS2V5cy5vbkxlZnRQcmVzc2VkOiBu
ZXh0SXRlbUluRm9jdXNDaGFpbihmYWxzZSkuZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykK
KyAgICBLZXlzLm9uRG93blByZXNzZWQ6IG5leHRJdGVtSW5Gb2N1c0NoYWluKHRydWUpLmZvcmNl
QWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgS2V5cy5vblVwUHJlc3NlZDogbmV4dEl0ZW1J
bkZvY3VzQ2hhaW4oZmFsc2UpLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgYmFj
a2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDb250
cm9sCisgICAgICAgIGNvbG9yOiBidXR0b24uZG93biA/IFZiVG9rZW5zLmJnRWxldjIgOiBidXR0
b24uaG92ZXJlZCA/IFZiVG9rZW5zLmJnRWxldjIgOiBWYlRva2Vucy5iZ1dpbmRvdworICAgICAg
ICBib3JkZXIud2lkdGg6IGJ1dHRvbi5hY3RpdmVGb2N1cyA/IDIgOiAxCisgICAgICAgIGJvcmRl
ci5jb2xvcjogYnV0dG9uLmFjdGl2ZUZvY3VzIHx8IGJ1dHRvbi5ob3ZlcmVkID8gVmJUb2tlbnMu
YWNjZW50IDogVmJUb2tlbnMuc3Ryb2tlCisgICAgICAgIG9wYWNpdHk6IGJ1dHRvbi5lbmFibGVk
ID8gMSA6IDAuNQorICAgIH0KKyAgICBjb250ZW50SXRlbTogUm93IHsKKyAgICAgICAgc3BhY2lu
ZzogOAorICAgICAgICBvcGFjaXR5OiBidXR0b24uZW5hYmxlZCA/IDEgOiAwLjUKKyAgICAgICAg
SWNvbkltYWdlIHsgY29sb3I6IFZiVG9rZW5zLmFjY2VudDsgdmlzaWJsZTogYnV0dG9uLmljb25T
b3VyY2UgIT09ICIiOyBzb3VyY2U6IGJ1dHRvbi5pY29uU291cmNlOyB3aWR0aDogdmlzaWJsZSA/
IDIwIDogMDsgaGVpZ2h0OiAyMDsgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRp
Y2FsQ2VudGVyIH0KKyAgICAgICAgTGFiZWwgeyB0ZXh0OiBidXR0b24udGV4dDsgdGV4dEZvcm1h
dDogVGV4dC5QbGFpblRleHQ7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBmb250OiBidXR0b24uZm9u
dDsgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVyIH0KKyAgICB9
Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0VjbGlwc2VDb21ib0JveC5xbWwgYi9hcHAvZ3VpL0Vj
bGlwc2VDb21ib0JveC5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMzFi
OWM3OQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNsaXBzZUNvbWJvQm94LnFtbApAQCAt
MCwwICsxLDI4IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xz
IDIuNQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1p
cy5SZWRlc2lnbiAxLjAKK0NvbWJvQm94IHsKKyAgICBpZDogY29udHJvbAorICAgIHRvcEluc2V0
OiAwOyBib3R0b21JbnNldDogMDsgbGVmdEluc2V0OiAwOyByaWdodEluc2V0OiAwCisgICAgaW1w
bGljaXRIZWlnaHQ6IE1hdGgubWF4KDQ0LCBmb250LnBpeGVsU2l6ZSArIDI0KQorICAgIGZvbnQu
ZmFtaWx5OiBWYlRva2Vucy5mb250Qm9keQorICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50
eXBlTGFiZWwKKyAgICBNYXRlcmlhbC5hY2NlbnQ6IFZiVG9rZW5zLmFjY2VudAorICAgIGxlZnRQ
YWRkaW5nOiAxMjsgcmlnaHRQYWRkaW5nOiAzNgorICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7
IGNvbG9yOiBWYlRva2Vucy5iZ0VsZXY7IHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ29udHJvbDsg
Ym9yZGVyLmNvbG9yOiBjb250cm9sLmFjdGl2ZUZvY3VzID8gVmJUb2tlbnMuYWNjZW50IDogVmJU
b2tlbnMuc3Ryb2tlOyBib3JkZXIud2lkdGg6IGNvbnRyb2wuYWN0aXZlRm9jdXMgPyAyIDogMTsg
b3BhY2l0eTogY29udHJvbC5lbmFibGVkID8gMSA6IC41IH0KKyAgICBjb250ZW50SXRlbTogTGFi
ZWwgeyB0ZXh0OiBjb250cm9sLmRpc3BsYXlUZXh0OyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4
dDsgZm9udDogY29udHJvbC5mb250OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgdmVydGljYWxBbGln
bm1lbnQ6IFRleHQuQWxpZ25WQ2VudGVyOyBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0OyBvcGFjaXR5
OiBjb250cm9sLmVuYWJsZWQgPyAxIDogLjUgfQorICAgIGRlbGVnYXRlOiBJdGVtRGVsZWdhdGUg
eworICAgICAgICB3aWR0aDogY29udHJvbC53aWR0aAorICAgICAgICBpbXBsaWNpdEhlaWdodDog
TWF0aC5tYXgoNDQsY29udHJvbC5mb250LnBpeGVsU2l6ZSsyNCkKKyAgICAgICAgaGlnaGxpZ2h0
ZWQ6IGNvbnRyb2wuaGlnaGxpZ2h0ZWRJbmRleCA9PT0gaW5kZXgKKyAgICAgICAgY29udGVudEl0
ZW06IExhYmVsIHsgdGV4dDogY29udHJvbC50ZXh0QXQoaW5kZXgpOyB0ZXh0Rm9ybWF0OlRleHQu
UGxhaW5UZXh0OyBmb250OmNvbnRyb2wuZm9udDsgY29sb3I6VmJUb2tlbnMudGV4dDsgZWxpZGU6
VGV4dC5FbGlkZVJpZ2h0IH0KKyAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsgY29sb3I6
IHBhcmVudC5oaWdobGlnaHRlZCA/IFZiVG9rZW5zLmJnRWxldjIgOiBWYlRva2Vucy5iZ0VsZXY7
IHJhZGl1czpWYlRva2Vucy5yYWRpdXNDb250cm9sOyBib3JkZXIuY29sb3I6cGFyZW50LmhpZ2hs
aWdodGVkP1ZiVG9rZW5zLmFjY2VudDoidHJhbnNwYXJlbnQiIH0KKyAgICB9CisgICAgcG9wdXA6
IFBvcHVwIHsKKyAgICAgICAgeTogY29udHJvbC5oZWlnaHQgKyA0OyB3aWR0aDpjb250cm9sLndp
ZHRoOyBwYWRkaW5nOjYKKyAgICAgICAgaW1wbGljaXRIZWlnaHQ6IE1hdGgubWluKGNvbnRlbnRJ
dGVtLmltcGxpY2l0SGVpZ2h0ICsgMTIsMzIwKQorICAgICAgICBiYWNrZ3JvdW5kOlJlY3Rhbmds
ZSB7IGNvbG9yOlZiVG9rZW5zLmJnRWxldjtyYWRpdXM6VmJUb2tlbnMucmFkaXVzQ29udHJvbDti
b3JkZXIuY29sb3I6VmJUb2tlbnMuc3Ryb2tlIH0KKyAgICAgICAgY29udGVudEl0ZW06TGlzdFZp
ZXcgeyBjbGlwOnRydWU7aW1wbGljaXRIZWlnaHQ6Y29udGVudEhlaWdodDttb2RlbDpjb250cm9s
LnBvcHVwLnZpc2libGU/Y29udHJvbC5kZWxlZ2F0ZU1vZGVsOm51bGw7Y3VycmVudEluZGV4OmNv
bnRyb2wuaGlnaGxpZ2h0ZWRJbmRleDtTY3JvbGxJbmRpY2F0b3IudmVydGljYWw6U2Nyb2xsSW5k
aWNhdG9yIHt9IH0KKyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0VjbGlwc2VDb250cm9s
Q2VudGVyLnFtbCBiL2FwcC9ndWkvRWNsaXBzZUNvbnRyb2xDZW50ZXIucW1sCm5ldyBmaWxlIG1v
ZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmQ5YzVkNTQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAv
Z3VpL0VjbGlwc2VDb250cm9sQ2VudGVyLnFtbApAQCAtMCwwICsxLDE2MyBAQAoraW1wb3J0IFF0
UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkxh
eW91dHMgMS4zCitpbXBvcnQgUXRRdWljay5Db250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9ydCBW
aWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFN5c3RlbUNvbnRyb2xzIDEuMAoraW1wb3J0IENy
aW1zb25TdGF0dXMgMS4wCitpbXBvcnQgU3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCitpbXBvcnQg
RWNsaXBzZVByb2ZpbGVzIDEuMAorCitEcmF3ZXIgeworICAgIGlkOiBwYW5lbAorICAgIGVkZ2U6
IFF0LlJpZ2h0RWRnZQorICAgIHdpZHRoOiBNYXRoLm1pbig1NjAsIHBhcmVudC53aWR0aCAtIDI0
KQorICAgIGhlaWdodDogcGFyZW50LmhlaWdodAorICAgIG1vZGFsOiB0cnVlCisgICAgZW50ZXI6
IFRyYW5zaXRpb24geyBOdW1iZXJBbmltYXRpb24geyBwcm9wZXJ0eTogInBvc2l0aW9uIjsgZnJv
bTogMDsgdG86IDE7IGR1cmF0aW9uOiBWYlRva2Vucy5zaGVldEluTXMgfSB9CisgICAgZXhpdDog
VHJhbnNpdGlvbiB7IE51bWJlckFuaW1hdGlvbiB7IHByb3BlcnR5OiAicG9zaXRpb24iOyBmcm9t
OiAxOyB0bzogMDsgZHVyYXRpb246IFZiVG9rZW5zLnNoZWV0SW5NcyB9IH0KKyAgICBwcm9wZXJ0
eSB2YXIgaG9zdDogKHt9KQorICAgIHByb3BlcnR5IGJvb2wgY2FuV2FrZTogZmFsc2UKKyAgICBw
cm9wZXJ0eSBib29sIGNhbk1hbmFnZTogZmFsc2UKKyAgICBwcm9wZXJ0eSBzdHJpbmcgbmV4dFBh
bmVsOiAiIgorICAgIHByb3BlcnR5IHN0cmluZyBtZXNzYWdlOiAiIgorICAgIHByb3BlcnR5IHZh
ciBzYXZlZE5hbWVzOiBbXQorICAgIHByb3BlcnR5IHN0cmluZyBwb3dlckFjdGlvbjogIiIKKyAg
ICBzaWduYWwgbmF2aWdhdGVSZXF1ZXN0ZWQoc3RyaW5nIGRlc3RpbmF0aW9uKQorICAgIHNpZ25h
bCB3YWtlUmVxdWVzdGVkKCkKKyAgICBNYXRlcmlhbC50aGVtZTogTWF0ZXJpYWwuRGFyaworICAg
IE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFsLmFjY2Vu
dDogVmJUb2tlbnMuYWNjZW50CisgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsgY29sb3I6IFZi
VG9rZW5zLmJnRWxldjsgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UKKyAgICAgICAgUmVj
dGFuZ2xlIHsgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGNvbG9yOiAidHJhbnNwYXJlbnQiOyBncmFk
aWVudDogR3JhZGllbnQgeyBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjogMDsgY29sb3I6IFF0LnJn
YmEoMSwxLDEsMC4wMzUpIH0gR3JhZGllbnRTdG9wIHsgcG9zaXRpb246IDE7IGNvbG9yOiAidHJh
bnNwYXJlbnQiIH0gfSB9CisgICAgfQorICAgIGZ1bmN0aW9uIGRlZmVyKGRlc3RpbmF0aW9uKSB7
IG5leHRQYW5lbCA9IGRlc3RpbmF0aW9uOyBjbG9zZSgpIH0KKyAgICBmdW5jdGlvbiBhcHBseSh2
YWx1ZXMpIHsKKyAgICAgICAgaWYgKCF2YWx1ZXMud2lkdGgpIHsgbWVzc2FnZSA9IHFzVHIoIlNh
dmUgdGhpcyBwcm9maWxlIGZpcnN0LiIpOyByZXR1cm4gfQorICAgICAgICBTdHJlYW1pbmdQcmVm
ZXJlbmNlcy53aWR0aCA9IHZhbHVlcy53aWR0aAorICAgICAgICBTdHJlYW1pbmdQcmVmZXJlbmNl
cy5oZWlnaHQgPSB2YWx1ZXMuaGVpZ2h0CisgICAgICAgIFN0cmVhbWluZ1ByZWZlcmVuY2VzLmZw
cyA9IHZhbHVlcy5mcHMKKyAgICAgICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMuYml0cmF0ZUticHMg
PSB2YWx1ZXMuYml0cmF0ZUticHMKKyAgICAgICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMuc2F2ZSgp
CisgICAgICAgIG1lc3NhZ2UgPSBxc1RyKCJQcm9maWxlIGFwcGxpZWQgZm9yIHRoZSBuZXh0IHN0
cmVhbS4iKQorICAgIH0KKyAgICBvbk9wZW5lZDogeyBtZXNzYWdlID0gIiI7IFN5c3RlbUNvbnRy
b2xzLm9wZW4oImNlbnRlciIpOyBwcm9maWxlTmFtZS50ZXh0ID0gIkdhbWluZyI7IHNhdmVkTmFt
ZXMgPSBFY2xpcHNlUHJvZmlsZXMubmFtZXMoaG9zdC5pZCB8fCAiIikgfQorICAgIG9uQ2xvc2Vk
OiB7CisgICAgICAgIHBvd2VyRGlhbG9nLmNsb3NlKCk7IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCk7
IHN0YWNrVmlldy5mb3JjZUFjdGl2ZUZvY3VzKCkKKyAgICAgICAgaWYgKG5leHRQYW5lbCAhPT0g
IiIpIHsgdmFyIGRlc3RpbmF0aW9uID0gbmV4dFBhbmVsOyBuZXh0UGFuZWwgPSAiIjsgbmF2aWdh
dGVSZXF1ZXN0ZWQoZGVzdGluYXRpb24pIH0KKyAgICB9CisgICAgY29udGVudEl0ZW06IENvbHVt
bkxheW91dCB7CisgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50OyBhbmNob3JzLm1hcmdpbnM6
IDIwOyBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICAgICAgUm93TGF5b3V0IHsKKyAgICAg
ICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgIExhYmVsIHsgdGV4dDog
cXNUcigiRWNsaXBzZSDigKIgQ29udHJvbCBjZW50ZXIiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7
IGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250RGlzcGxheTsgZm9udC5waXhlbFNpemU6IFZiVG9r
ZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlIH0KKyAgICAgICAgICAgIEVjbGlw
c2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJDbG9zZSIpOyBvbkNsaWNrZWQ6IHBhbmVsLmNs
b3NlKCkgfQorICAgICAgICB9CisgICAgICAgIFNjcm9sbFZpZXcgeworICAgICAgICAgICAgTGF5
b3V0LmZpbGxXaWR0aDogdHJ1ZTsgTGF5b3V0LmZpbGxIZWlnaHQ6IHRydWUKKyAgICAgICAgICAg
IGNsaXA6IHRydWU7IGNvbnRlbnRXaWR0aDogYXZhaWxhYmxlV2lkdGgKKyAgICAgICAgICAgIENv
bHVtbkxheW91dCB7CisgICAgICAgICAgICAgICAgd2lkdGg6IHBhcmVudC53aWR0aDsgc3BhY2lu
ZzogVmJUb2tlbnMuc3BhY2UzCisgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3Jh
cDsgdGV4dDogQ3JpbXNvblN0YXR1cy5sb2NhbC5uZXR3b3JrIHx8IHFzVHIoIk5ldHdvcmsgdW5h
dmFpbGFibGUiKTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgICAgIExh
YmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4dDogQ3JpbXNvblN0YXR1cy5sb2NhbC5i
YXR0ZXJ5UGVyY2VudCA+PSAwID8gcXNUcigiQmF0dGVyeSAlMSUg4oCiICUyIikuYXJnKENyaW1z
b25TdGF0dXMubG9jYWwuYmF0dGVyeVBlcmNlbnQpLmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLmJh
dHRlcnlTdGF0ZSkgOiBxc1RyKCJCYXR0ZXJ5IHVuYXZhaWxhYmxlIik7IGNvbG9yOiBWYlRva2Vu
cy50ZXh0RGltOyB3cmFwTW9kZTogVGV4dC5XcmFwIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlv
dXQgeworICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNU
cigiV2ktRmkiKTsgaWNvblNvdXJjZTogInFyYzovcmVzL2NyaW1zb24tbmV0d29yay5zdmciOyBv
bkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJ3aWZpIikgfQorICAgICAgICAgICAgICAgICAgICBFY2xp
cHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiQmx1ZXRvb3RoIik7IGljb25Tb3VyY2U6ICJx
cmM6L3Jlcy9jcmltc29uLWJsdWV0b290aC5zdmciOyBvbkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJi
dCIpIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBx
c1RyKCJBdWRpbyIpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAg
ICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAgICAgICBMYXlvdXQuZmls
bFdpZHRoOiB0cnVlCisgICAgICAgICAgICAgICAgICAgIFNsaWRlciB7CisgICAgICAgICAgICAg
ICAgICAgICAgICBpZDogdm9sdW1lU2xpZGVyCisgICAgICAgICAgICAgICAgICAgICAgICBMYXlv
dXQuZmlsbFdpZHRoOiB0cnVlOyBmcm9tOiAwOyB0bzogMTAwOyBzdGVwU2l6ZTogMQorICAgICAg
ICAgICAgICAgICAgICAgICAgdmFsdWU6IFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSA9PT0g
dW5kZWZpbmVkIHx8IFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSA9PT0gbnVsbCA/IDAgOiBT
eXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUKKyAgICAgICAgICAgICAgICAgICAgICAgIGVuYWJs
ZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5ICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSAh
PT0gdW5kZWZpbmVkICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSAhPT0gbnVsbAorICAg
ICAgICAgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJTcGVha2VyIHZvbHVt
ZSIpCisgICAgICAgICAgICAgICAgICAgICAgICBvbk1vdmVkOiBpZiAoIXByZXNzZWQgJiYgZW5h
YmxlZCkgU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLXZvbHVtZSIsIFN0cmluZyhNYXRo
LnJvdW5kKHZhbHVlKSkpCisgICAgICAgICAgICAgICAgICAgICAgICBvblByZXNzZWRDaGFuZ2Vk
OiBpZiAoIXByZXNzZWQgJiYgZW5hYmxlZCkgU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVy
LXZvbHVtZSIsIFN0cmluZyhNYXRoLnJvdW5kKHZhbHVlKSkpCisgICAgICAgICAgICAgICAgICAg
IH0KKyAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyBpZDogdm9sdW1lUmVhZG91dDsgdGV4dDog
TWF0aC5yb3VuZCh2b2x1bWVTbGlkZXIudmFsdWUpKyIlIjsgY29sb3I6IFZiVG9rZW5zLnRleHQg
fQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogU3lzdGVt
Q29udHJvbHMuc3RhdGUubXV0ZWQgPyBxc1RyKCJVbm11dGUiKSA6IHFzVHIoIk11dGUiKTsgZW5h
YmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3kgJiYgU3lzdGVtQ29udHJvbHMuc3RhdGUudm9sdW1l
ICE9PSBudWxsICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSAhPT0gdW5kZWZpbmVkOyBv
bkNsaWNrZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci1tdXRlIikgfQorICAgICAg
ICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBFY2xpcHNlQ29tYm9Cb3ggeworICAgICAgICAg
ICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisgICAgICAgICAgICAgICAgICAgIG1v
ZGVsOiBTeXN0ZW1Db250cm9scy5zdGF0ZS5zaW5rcyB8fCBbXTsgdGV4dFJvbGU6ICJuYW1lIgor
ICAgICAgICAgICAgICAgICAgICBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBjb3Vu
dCA+IDAKKyAgICAgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJBdWRpbyBv
dXRwdXQiKQorICAgICAgICAgICAgICAgICAgICBjdXJyZW50SW5kZXg6IHsgdmFyIGxpc3QgPSBT
eXN0ZW1Db250cm9scy5zdGF0ZS5zaW5rcyB8fCBbXTsgZm9yICh2YXIgaT0wO2k8bGlzdC5sZW5n
dGg7aSsrKSBpZiAobGlzdFtpXS5kZWZhdWx0KSByZXR1cm4gaTsgcmV0dXJuIC0xIH0KKyAgICAg
ICAgICAgICAgICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgdGV4dDogcGFyZW50LmRpc3BsYXlU
ZXh0OyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IHZl
cnRpY2FsQWxpZ25tZW50OiBUZXh0LkFsaWduVkNlbnRlcjsgZWxpZGU6IFRleHQuRWxpZGVSaWdo
dCB9CisgICAgICAgICAgICAgICAgICAgIGRlbGVnYXRlOiBJdGVtRGVsZWdhdGUgeyB3aWR0aDog
cGFyZW50LndpZHRoOyBjb250ZW50SXRlbTogTGFiZWwgeyB0ZXh0OiBtb2RlbERhdGEubmFtZTsg
dGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBlbGlkZTog
VGV4dC5FbGlkZVJpZ2h0IH0gfQorICAgICAgICAgICAgICAgICAgICBvbkFjdGl2YXRlZDogU3lz
dGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLW91dHB1dCIsIG1vZGVsW2luZGV4XS5pZCkKKyAg
ICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgUmVwZWF0ZXIgeworICAgICAgICAgICAg
ICAgICAgICBtb2RlbDogW3traW5kOiJzY3JlZW4iLGxhYmVsOnFzVHIoIlNjcmVlbiBicmlnaHRu
ZXNzIil9LHtraW5kOiJrZXlib2FyZCIsbGFiZWw6cXNUcigiS2V5Ym9hcmQgYnJpZ2h0bmVzcyIp
fV0KKyAgICAgICAgICAgICAgICAgICAgZGVsZWdhdGU6IENvbHVtbkxheW91dCB7CisgICAgICAg
ICAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisgICAgICAgICAgICAgICAg
ICAgICAgICBwcm9wZXJ0eSB2YXIgaGFyZHdhcmU6IChTeXN0ZW1Db250cm9scy5zdGF0ZS5icmln
aHRuZXNzIHx8IHt9KVttb2RlbERhdGEua2luZF0KKyAgICAgICAgICAgICAgICAgICAgICAgIExh
YmVsIHsgdGV4dDogbW9kZWxEYXRhLmxhYmVsICsgKGhhcmR3YXJlID8gIiDigKIgIiArIGhhcmR3
YXJlLnBlcmNlbnQgKyAiJSIgOiAiIOKAoiAiICsgcXNUcigiVW5hdmFpbGFibGUiKSk7IGNvbG9y
OiBWYlRva2Vucy50ZXh0IH0KKyAgICAgICAgICAgICAgICAgICAgICAgIFNsaWRlciB7CisgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgZnJvbTogbW9k
ZWxEYXRhLmtpbmQgPT09ICJzY3JlZW4iID8gNSA6IDA7IHRvOiAxMDA7IHN0ZXBTaXplOiAxCisg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgdmFsdWU6IGhhcmR3YXJlID8gaGFyZHdhcmUucGVy
Y2VudCA6IDA7IGVuYWJsZWQ6ICEhaGFyZHdhcmUgJiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3kKKyAg
ICAgICAgICAgICAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IG1vZGVsRGF0YS5sYWJl
bAorICAgICAgICAgICAgICAgICAgICAgICAgICAgIG9uTW92ZWQ6IGlmICghcHJlc3NlZCAmJiBl
bmFibGVkKSBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItIittb2RlbERhdGEua2luZCwg
U3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSkKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICBv
blByZXNzZWRDaGFuZ2VkOiBpZiAoIXByZXNzZWQgJiYgZW5hYmxlZCkgU3lzdGVtQ29udHJvbHMu
cmVxdWVzdCgiY2VudGVyLSIrbW9kZWxEYXRhLmtpbmQsIFN0cmluZyhNYXRoLnJvdW5kKHZhbHVl
KSkpCisgICAgICAgICAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgICAgIH0KKyAg
ICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRl
eHQ6IHFzVHIoIlJlZnJlc2ggY29udHJvbHMiKTsgZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1
c3k7IG9uQ2xpY2tlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLWxpc3QiKSB9Cisg
ICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBxc1RyKCJIb3N0Iik7IGNvbG9yOiBWYlRva2Vu
cy50ZXh0OyBmb250LmJvbGQ6IHRydWUgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0
LmZpbGxXaWR0aDogdHJ1ZTsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHdyYXBNb2RlOiBU
ZXh0LldyYXA7IHRleHQ6IHBhbmVsLmhvc3QudXJsIHx8IHFzVHIoIlNlbGVjdCBhIGhvc3QgaW4g
dGhlIGxhdW5jaGVyLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICAg
ICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7
IHRleHQ6IHFzVHIoIkhvc3Qgc3RhdHMiKTsgZW5hYmxlZDogISFwYW5lbC5ob3N0LmlkOyBpY29u
U291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1ob3N0LnN2ZyI7IG9uQ2xpY2tlZDogcGFuZWwuZGVm
ZXIoImhvc3QiKSB9CisgICAgICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0
ZXh0OiBxc1RyKCJXYWtlIGhvc3QiKTsgZW5hYmxlZDogISFwYW5lbC5ob3N0LmlkICYmIHBhbmVs
LmNhbldha2U7IG9uQ2xpY2tlZDogeyBwYW5lbC53YWtlUmVxdWVzdGVkKCk7IHBhbmVsLm1lc3Nh
Z2UgPSBxc1RyKCJXYWtlIHJlcXVlc3Qgc2VudDsgdGhlIGhvc3QgbXVzdCBzdXBwb3J0IFdha2Ut
b24tTEFOLiIpIH0gfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBFY2xpcHNl
QWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiT3BlbiBob3N0IG1hbmFnZW1lbnQiKTsgZW5hYmxl
ZDogISFwYW5lbC5ob3N0LnVybCAmJiBwYW5lbC5jYW5NYW5hZ2U7IG9uQ2xpY2tlZDogcGFuZWwu
ZGVmZXIoIm1hbmFnZW1lbnQiKSB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBxc1Ry
KCJTdHJlYW0gcHJvZmlsZXMiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQuYm9sZDogdHJ1
ZSB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFw
TW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBwYW5lbC5ob3N0LmlkID8gcXNUcigiU2F2ZWQgZm9yIHRo
ZSBzZWxlY3RlZCBob3N0LiBBcHBseSBiZWZvcmUgc3RhcnRpbmcgYSBzdHJlYW0uIikgOiBxc1Ry
KCJHbG9iYWwgcHJvZmlsZXMuIEFwcGx5IGJlZm9yZSBzdGFydGluZyBhIHN0cmVhbS4iKTsgY29s
b3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgICAgIEVjbGlwc2VDb21ib0JveCB7
IExheW91dC5maWxsV2lkdGg6IHRydWU7IG1vZGVsOiBwYW5lbC5zYXZlZE5hbWVzOyB2aXNpYmxl
OiBjb3VudCA+IDA7IEFjY2Vzc2libGUubmFtZTogcXNUcigiU2F2ZWQgcHJvZmlsZXMiKTsgb25B
Y3RpdmF0ZWQ6IHByb2ZpbGVOYW1lLnRleHQgPSBtb2RlbFtpbmRleF0gfQorICAgICAgICAgICAg
ICAgIFRleHRGaWVsZCB7IGlkOiBwcm9maWxlTmFtZTsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsg
bWF4aW11bUxlbmd0aDogNDg7IHBsYWNlaG9sZGVyVGV4dDogcXNUcigiUHJvZmlsZSBuYW1lIik7
IEFjY2Vzc2libGUubmFtZTogcXNUcigiUHJvZmlsZSBuYW1lIikgfQorICAgICAgICAgICAgICAg
IFJvd0xheW91dCB7CisgICAgICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0
ZXh0OiBxc1RyKCJTYXZlIGN1cnJlbnQiKTsgb25DbGlja2VkOiB7IHBhbmVsLm1lc3NhZ2UgPSBF
Y2xpcHNlUHJvZmlsZXMuc2F2ZShwYW5lbC5ob3N0LmlkIHx8ICIiLCBwcm9maWxlTmFtZS50ZXh0
LCB7d2lkdGg6U3RyZWFtaW5nUHJlZmVyZW5jZXMud2lkdGgsaGVpZ2h0OlN0cmVhbWluZ1ByZWZl
cmVuY2VzLmhlaWdodCxmcHM6U3RyZWFtaW5nUHJlZmVyZW5jZXMuZnBzLGJpdHJhdGVLYnBzOlN0
cmVhbWluZ1ByZWZlcmVuY2VzLmJpdHJhdGVLYnBzfSkgPyBxc1RyKCJQcm9maWxlIHNhdmVkLiIp
IDogcXNUcigiUHJvZmlsZSBjb3VsZCBub3QgYmUgc2F2ZWQuIik7IHBhbmVsLnNhdmVkTmFtZXMg
PSBFY2xpcHNlUHJvZmlsZXMubmFtZXMocGFuZWwuaG9zdC5pZCB8fCAiIikgfSB9CisgICAgICAg
ICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJBcHBseSBzYXZl
ZCIpOyBvbkNsaWNrZWQ6IHBhbmVsLmFwcGx5KEVjbGlwc2VQcm9maWxlcy5sb2FkKHBhbmVsLmhv
c3QuaWQgfHwgIiIsIHByb2ZpbGVOYW1lLnRleHQpKSB9CisgICAgICAgICAgICAgICAgfQorICAg
ICAgICAgICAgICAgIFJvd0xheW91dCB7CisgICAgICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rp
b25CdXR0b24geyB0ZXh0OiBxc1RyKCJEZXNrdG9wIHByZXNldCIpOyBvbkNsaWNrZWQ6IHBhbmVs
LmFwcGx5KHt3aWR0aDoxMjgwLGhlaWdodDo4MDAsZnBzOjYwLGJpdHJhdGVLYnBzOjE1MDAwfSkg
fQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigi
TG93IGJhbmR3aWR0aCIpOyBvbkNsaWNrZWQ6IHBhbmVsLmFwcGx5KHt3aWR0aDoxMjgwLGhlaWdo
dDo3MjAsZnBzOjMwLGJpdHJhdGVLYnBzOjUwMDB9KSB9CisgICAgICAgICAgICAgICAgfQorICAg
ICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogcXNUcigiQXBwZWFyYW5jZSAmIGFjY2Vzc2liaWxp
dHkiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQuYm9sZDogdHJ1ZSB9CisgICAgICAgICAg
ICAgICAgRWNsaXBzZUNvbWJvQm94IHsKKyAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxX
aWR0aDogdHJ1ZTsgbW9kZWw6IFtxc1RyKCJUZXh0IDEwMCUiKSxxc1RyKCJUZXh0IDExMCUiKSxx
c1RyKCJUZXh0IDEyNSUiKV0KKyAgICAgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBx
c1RyKCJUZXh0IHNpemUiKQorICAgICAgICAgICAgICAgICAgICBjdXJyZW50SW5kZXg6IEVjbGlw
c2VQcm9maWxlcy50ZXh0U2NhbGUgPT09IDEyNSA/IDIgOiBFY2xpcHNlUHJvZmlsZXMudGV4dFNj
YWxlID09PSAxMTAgPyAxIDogMAorICAgICAgICAgICAgICAgICAgICBvbkFjdGl2YXRlZDogRWNs
aXBzZVByb2ZpbGVzLnRleHRTY2FsZSA9IFsxMDAsMTEwLDEyNV1baW5kZXhdCisgICAgICAgICAg
ICAgICAgfQorICAgICAgICAgICAgICAgIFN3aXRjaCB7IHRleHQ6IHFzVHIoIlJlZHVjZSBtb3Rp
b24iKTsgY2hlY2tlZDogRWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb247IG9uVG9nZ2xlZDog
RWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb24gPSBjaGVja2VkIH0KKyAgICAgICAgICAgICAg
ICBTd2l0Y2ggeyB0ZXh0OiBxc1RyKCJIaWdoZXIgY29udHJhc3QiKTsgY2hlY2tlZDogRWNsaXBz
ZVByb2ZpbGVzLmhpZ2hDb250cmFzdDsgb25Ub2dnbGVkOiBFY2xpcHNlUHJvZmlsZXMuaGlnaENv
bnRyYXN0ID0gY2hlY2tlZCB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBxc1RyKCJU
b29scyAmIHJlY292ZXJ5Iik7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmJvbGQ6IHRydWUg
fQorICAgICAgICAgICAgICAgIFJvd0xheW91dCB7CisgICAgICAgICAgICAgICAgICAgIEVjbGlw
c2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJBbGwgc2V0dGluZ3MiKTsgaWNvblNvdXJjZTog
InFyYzovcmVzL3NldHRpbmdzLnN2ZyI7IG9uQ2xpY2tlZDogcGFuZWwuZGVmZXIoInNldHRpbmdz
IikgfQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNU
cigiU3VwcG9ydCByZXBvcnQiKTsgZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xp
Y2tlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLXJlcG9ydCIpIH0KKyAgICAgICAg
ICAgICAgICB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVl
OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJSZWNvdmVyeTogQ3RybCtBbHQrRjIg
b3BlbnMgdGhlIGRpYWdub3N0aWMgY29uc29sZS4gTWFjIGJyaWdodG5lc3MsIGtleWJvYXJkLWxp
Z2h0IGFuZCB2b2x1bWUga2V5cyByZW1haW4gYXZhaWxhYmxlLiIpOyBjb2xvcjogVmJUb2tlbnMu
dGV4dERpbSB9CisgICAgICAgICAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgICAgICAg
ICAgUmVwZWF0ZXIgeworICAgICAgICAgICAgICAgICAgICAgICAgbW9kZWw6IFt7YWN0aW9uOiJy
ZWJvb3QiLGxhYmVsOnFzVHIoIlJlc3RhcnQiKX0se2FjdGlvbjoicG93ZXJvZmYiLGxhYmVsOnFz
VHIoIlNodXQgZG93biIpfV0KKyAgICAgICAgICAgICAgICAgICAgICAgIGRlbGVnYXRlOiBFY2xp
cHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogbW9kZWxEYXRhLmxhYmVsOyBpY29uU291cmNlOiAicXJj
Oi9yZXMvZWNsaXBzZS1wb3dlci5zdmciOyBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeTsg
b25DbGlja2VkOiB7IHBhbmVsLnBvd2VyQWN0aW9uID0gbW9kZWxEYXRhLmFjdGlvbjsgcG93ZXJE
aWFsb2cub3BlbigpIH0gfQorICAgICAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAg
fQorICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJBYm91
dCBFY2xpcHNlIik7IGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6IHBh
bmVsLmRlZmVyKCJhYm91dCIpIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxs
V2lkdGg6IHRydWU7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB3cmFwTW9kZTogVGV4dC5X
cmFwOyB0ZXh0OiBwYW5lbC5tZXNzYWdlIHx8IFN5c3RlbUNvbnRyb2xzLnN0YXR1czsgY29sb3I6
IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgICAgIEJ1c3lJbmRpY2F0b3IgeyBydW5u
aW5nOiBTeXN0ZW1Db250cm9scy5idXN5OyB2aXNpYmxlOiBydW5uaW5nOyBMYXlvdXQuYWxpZ25t
ZW50OiBRdC5BbGlnbkhDZW50ZXIgfQorICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQor
ICAgIE5hdmlnYWJsZURpYWxvZyB7CisgICAgICAgIGlkOiBwb3dlckRpYWxvZworICAgICAgICB3
aWR0aDogTWF0aC5taW4oNDQwLCBwYW5lbC53aWR0aCAtIDMyKQorICAgICAgICB0aXRsZTogcGFu
ZWwucG93ZXJBY3Rpb24gPT09ICJyZWJvb3QiID8gcXNUcigiUmVzdGFydCBFY2xpcHNlT1M/Iikg
OiBxc1RyKCJTaHV0IGRvd24gRWNsaXBzZU9TPyIpCisgICAgICAgIHN0YW5kYXJkQnV0dG9uczog
RGlhbG9nLlllcyB8IERpYWxvZy5ObworICAgICAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRv
a2Vucy5iZ0VsZXYKKyAgICAgICAgb25BY2NlcHRlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgi
Y2VudGVyLSIrcGFuZWwucG93ZXJBY3Rpb24sIiIsdHJ1ZSkKKyAgICAgICAgY29udGVudEl0ZW06
IExhYmVsIHsgdGV4dDogcXNUcigiVGhpcyBlbmRzIHRoZSBjdXJyZW50IGxvY2FsIHNlc3Npb24u
Iik7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0KKyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3Vp
L0VjbGlwc2VIYXJkd2FyZU1vbml0b3IucW1sIGIvYXBwL2d1aS9FY2xpcHNlSGFyZHdhcmVNb25p
dG9yLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5iZTM0MWEwCi0tLSAv
ZGV2L251bGwKKysrIGIvYXBwL2d1aS9FY2xpcHNlSGFyZHdhcmVNb25pdG9yLnFtbApAQCAtMCww
ICsxLDc2IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIu
NQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEu
MAoraW1wb3J0IExvY2FsSGFyZHdhcmUgMS4wCisKK0NvbHVtbkxheW91dCB7CisgICAgaWQ6IG1v
bml0b3IKKyAgICBvYmplY3ROYW1lOiJoYXJkd2FyZU1vbml0b3IiCisgICAgcHJvcGVydHkgYm9v
bCBhY3RpdmU6IGZhbHNlCisgICAgQ29tcG9uZW50Lm9uQ29tcGxldGVkOiBpZihhY3RpdmUpIExv
Y2FsSGFyZHdhcmUuc2V0QWN0aXZlKHRydWUpCisgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQor
ICAgIG9uQWN0aXZlQ2hhbmdlZDogTG9jYWxIYXJkd2FyZS5zZXRBY3RpdmUoYWN0aXZlKQorICAg
IENvbXBvbmVudC5vbkRlc3RydWN0aW9uOiBMb2NhbEhhcmR3YXJlLnNldEFjdGl2ZShmYWxzZSkK
KyAgICBmdW5jdGlvbiByZWFkaW5nKGtleSwgc3VmZml4LCBkaWdpdHMpIHsgdmFyIHY9TG9jYWxI
YXJkd2FyZS5yZWFkaW5nc1trZXldOyByZXR1cm4gdiA9PT0gdW5kZWZpbmVkID8gcXNUcigiVW5h
dmFpbGFibGUiKSA6IE51bWJlcih2KS50b0ZpeGVkKGRpZ2l0cyA9PT0gdW5kZWZpbmVkID8gMSA6
IGRpZ2l0cykrKHN1ZmZpeCB8fCAiIikgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tl
bnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OiBxc1Ry
KCJMT0NBTCBNQUMg4oCiIEhhcmR3YXJlIG1vbml0b3IiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7
IGZvbnQuYm9sZDogdHJ1ZSB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250
Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6
IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIkxvY2FsIHJlYWRpbmdzIGFy
ZSBpbmRlcGVuZGVudCBvZiBzdHJlYW0gYW5kIGhvc3Qgc3RhdGlzdGljcy4gTWlzc2luZyBzZW5z
b3JzIHNob3cgVW5hdmFpbGFibGU7IGZpcnN0IENQVS9uZXR3b3JrIHJhdGVzIG5lZWQgYSBzZWNv
bmQgc2FtcGxlLiBJbnRlbCBHUFUgc2hhcmVkIG1lbW9yeSBpcyBzeXN0ZW0gUkFNLiIpOyBjb2xv
cjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgR3JpZExheW91dCB7CisgICAgICAgIExheW91dC5m
aWxsV2lkdGg6IHRydWU7IGNvbHVtbnM6IHdpZHRoID49IDYyMCA/IDIgOiAxOyBjb2x1bW5TcGFj
aW5nOiBWYlRva2Vucy5zcGFjZTM7IHJvd1NwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMworICAgICAg
ICBSZXBlYXRlciB7CisgICAgICAgICAgICBtb2RlbDogWworICAgICAgICAgICAgICAgIHtsYWJl
bDpxc1RyKCJDUFUiKSwga2V5OiJjcHVQZXJjZW50IixzdWZmaXg6IiUifSwge2xhYmVsOnFzVHIo
IkNQVSBjbG9jayIpLGtleToiY3B1TUh6IixzdWZmaXg6IiBNSHoifSwKKyAgICAgICAgICAgICAg
ICB7bGFiZWw6cXNUcigiTWVtb3J5IHVzZWQiKSxrZXk6Im1lbW9yeVVzZWRHaUIiLHN1ZmZpeDoi
IEdpQiJ9LHtsYWJlbDpxc1RyKCJNZW1vcnkgdG90YWwiKSxrZXk6Im1lbW9yeVRvdGFsR2lCIixz
dWZmaXg6IiBHaUIifSwKKyAgICAgICAgICAgICAgICB7bGFiZWw6cXNUcigiQ1BVIHRlbXBlcmF0
dXJlIiksa2V5OiJ0ZW1wZXJhdHVyZUMiLHN1ZmZpeDoiIMKwQyJ9LHtsYWJlbDpxc1RyKCJGYW4i
KSxrZXk6ImZhblJQTSIsc3VmZml4OiIgUlBNIn0sCisgICAgICAgICAgICAgICAge2xhYmVsOnFz
VHIoIkdQVSBidXN5Iiksa2V5OiJncHVQZXJjZW50IixzdWZmaXg6IiUifSx7bGFiZWw6cXNUcigi
RWNsaXBzZSB2aWRlbyBlbmdpbmUiKSxrZXk6InZpZGVvUGVyY2VudCIsc3VmZml4OiIlIn0se2xh
YmVsOnFzVHIoIlN3YXAgdXNlZCIpLGtleToic3dhcFVzZWRNaUIiLHN1ZmZpeDoiIE1pQiJ9LAor
ICAgICAgICAgICAgICAgIHtsYWJlbDpxc1RyKCJOZXR3b3JrIGRvd25sb2FkIiksa2V5OiJyZWNl
aXZlTWlCIixzdWZmaXg6IiBNaUIvcyJ9LHtsYWJlbDpxc1RyKCJOZXR3b3JrIHVwbG9hZCIpLGtl
eToidHJhbnNtaXRNaUIiLHN1ZmZpeDoiIE1pQi9zIn0sCisgICAgICAgICAgICAgICAge2xhYmVs
OnFzVHIoIlN0b3JhZ2UgcmVhZHMiKSxrZXk6ImRpc2tSZWFkTWlCIixzdWZmaXg6IiBNaUIvcyJ9
LHtsYWJlbDpxc1RyKCJTdG9yYWdlIHdyaXRlcyIpLGtleToiZGlza1dyaXRlTWlCIixzdWZmaXg6
IiBNaUIvcyJ9LAorICAgICAgICAgICAgICAgIHtsYWJlbDpxc1RyKCJVU0Ivcm9vdCBmcmVlIiks
a2V5OiJzdG9yYWdlRnJlZUdpQiIsc3VmZml4OiIgR2lCIn0se2xhYmVsOnFzVHIoIkJhdHRlcnki
KSxrZXk6ImJhdHRlcnlQZXJjZW50IixzdWZmaXg6IiUifQorICAgICAgICAgICAgXQorICAgICAg
ICAgICAgZGVsZWdhdGU6IFJlY3RhbmdsZSB7CisgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxX
aWR0aDogdHJ1ZTsgaW1wbGljaXRIZWlnaHQ6IDg0OyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0Nh
cmQ7IGNvbG9yOiBWYlRva2Vucy5iZ0VsZXY7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tl
CisgICAgICAgICAgICAgICAgQ29sdW1uIHsgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGFuY2hvcnMu
bWFyZ2luczogMTI7IHNwYWNpbmc6IDYKKyAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0
OiBtb2RlbERhdGEubGFiZWw7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltOyBmb250LnBpeGVsU2l6
ZTogVmJUb2tlbnMudHlwZUJvZHkgfQorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6
IG1vbml0b3IucmVhZGluZyhtb2RlbERhdGEua2V5LG1vZGVsRGF0YS5zdWZmaXgpOyBjb2xvcjog
VmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlOyBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMu
dHlwZUJvZHkgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQor
ICAgIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBp
eGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigiUmVjZW50IENQVSBhbmQgUkFN
IHVzYWdlIOKAoiB1cCB0byA2MCBzYW1wbGVzIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0K
KyAgICBDYW52YXMgeworICAgICAgICBpZDogZ3JhcGg7IExheW91dC5maWxsV2lkdGg6IHRydWU7
IGltcGxpY2l0SGVpZ2h0OiAxMDAKKyAgICAgICAgb25QYWludDogeworICAgICAgICAgICAgdmFy
IGM9Z2V0Q29udGV4dCgiMmQiKTsgYy5jbGVhclJlY3QoMCwwLHdpZHRoLGhlaWdodCk7IGMuZmls
bFN0eWxlPVZiVG9rZW5zLmJnRWxldjsgYy5maWxsUmVjdCgwLDAsd2lkdGgsaGVpZ2h0KQorICAg
ICAgICAgICAgdmFyIGtleXM9WyJjcHVQZXJjZW50IiwibWVtb3J5UGVyY2VudCJdLCBjb2xvcnM9
W1ZiVG9rZW5zLmFjY2VudCxWYlRva2Vucy50ZXh0RGltXSwgaD1Mb2NhbEhhcmR3YXJlLmhpc3Rv
cnkKKyAgICAgICAgICAgIGZvcih2YXIgaz0wO2s8a2V5cy5sZW5ndGg7aysrKSB7IGMuc3Ryb2tl
U3R5bGU9Y29sb3JzW2tdOyBjLmxpbmVXaWR0aD0yOyBjLmJlZ2luUGF0aCgpOyB2YXIgc3RhcnRl
ZD1mYWxzZQorICAgICAgICAgICAgICAgIGZvcih2YXIgaT0wO2k8aC5sZW5ndGg7aSsrKSB7IHZh
ciB2PWhbaV1ba2V5c1trXV07IGlmKHY9PT11bmRlZmluZWQpIHsgc3RhcnRlZD1mYWxzZTsgY29u
dGludWUgfQorICAgICAgICAgICAgICAgICAgICB2YXIgeD13aWR0aCppLzU5LCB5PWhlaWdodC00
LShoZWlnaHQtOCkqTWF0aC5tYXgoMCxNYXRoLm1pbigxMDAsdikpLzEwMAorICAgICAgICAgICAg
ICAgICAgICBpZighc3RhcnRlZCkgYy5tb3ZlVG8oeCx5KTsgZWxzZSBjLmxpbmVUbyh4LHkpOyBz
dGFydGVkPXRydWUgfQorICAgICAgICAgICAgICAgIGMuc3Ryb2tlKCkgfQorICAgICAgICB9Cisg
ICAgICAgIENvbm5lY3Rpb25zIHsgdGFyZ2V0OiBMb2NhbEhhcmR3YXJlOyBmdW5jdGlvbiBvbkNo
YW5nZWQoKSB7IGdyYXBoLnJlcXVlc3RQYWludCgpIH0gfQorICAgIH0KKyAgICBDaGVja0JveCB7
IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50
eXBlQm9keTsgdGV4dDogcXNUcigiU2hvdyBsb2NhbCBoYXJkd2FyZSBvdmVybGF5IGR1cmluZyBz
dHJlYW1pbmciKTsgY2hlY2tlZDogTG9jYWxIYXJkd2FyZS5vdmVybGF5OyBvblRvZ2dsZWQ6IExv
Y2FsSGFyZHdhcmUub3ZlcmxheT1jaGVja2VkIH0KKyAgICBDaGVja0JveCB7IGZvbnQuZmFtaWx5
OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4
dDogcXNUcigiRGV0YWlsZWQgbG9jYWwgb3ZlcmxheSIpOyBjaGVja2VkOiBMb2NhbEhhcmR3YXJl
LmRldGFpbGVkOyBvblRvZ2dsZWQ6IExvY2FsSGFyZHdhcmUuZGV0YWlsZWQ9Y2hlY2tlZCB9Cisg
ICAgQ2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNp
emU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6IHFzVHIoIkRldGFpbGVkIHN0cmVhbSBzdGF0aXN0
aWNzIik7IGNoZWNrZWQ6IExvY2FsSGFyZHdhcmUuc3RyZWFtRGV0YWlsZWQ7IG9uVG9nZ2xlZDog
TG9jYWxIYXJkd2FyZS5zdHJlYW1EZXRhaWxlZD1jaGVja2VkIH0KKyAgICBSb3dMYXlvdXQgewor
ICAgICAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVs
U2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigiTG9jYWwgb3ZlcmxheSBjb3JuZXIi
KTsgY29sb3I6IFZiVG9rZW5zLnRleHQgfQorICAgICAgICBFY2xpcHNlQ29tYm9Cb3ggeyBMYXlv
dXQuZmlsbFdpZHRoOnRydWU7IG1vZGVsOltxc1RyKCJUb3AgbGVmdCIpLHFzVHIoIlRvcCByaWdo
dCIpLHFzVHIoIkJvdHRvbSBsZWZ0IikscXNUcigiQm90dG9tIHJpZ2h0IildOyBjdXJyZW50SW5k
ZXg6TG9jYWxIYXJkd2FyZS5wb3NpdGlvbjsgb25BY3RpdmF0ZWQ6TG9jYWxIYXJkd2FyZS5wb3Np
dGlvbj1pbmRleCB9CisgICAgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9u
dEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRo
OnRydWU7IHdyYXBNb2RlOlRleHQuV3JhcDsgdGV4dDpxc1RyKCJJZiBib3RoIG92ZXJsYXlzIHVz
ZSB0aGUgc2FtZSBjb3JuZXIsIExvY2FsIE1hYyBtb3ZlcyB0byB0aGUgb3Bwb3NpdGUgaG9yaXpv
bnRhbCBjb3JuZXIuIFN0cmVhbWluZyBzaG9ydGN1dHM6IEN0cmwrQWx0K1NoaWZ0K1MgZm9yIHN0
cmVhbSBzdGF0czsgQ3RybCtBbHQrU2hpZnQrSCBmb3IgbG9jYWwgaGFyZHdhcmUuIFN0cmVhbSB0
ZXh0IHNpemUgYW5kIGNvcm5lciByZW1haW4gaW4gVmlkZW8gc2V0dGluZ3MuIik7IGNvbG9yOlZi
VG9rZW5zLnRleHREaW0gfQorICAgIFJvd0xheW91dCB7CisgICAgICAgIExhYmVsIHsgZm9udC5m
YW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5
OyB0ZXh0OnFzVHIoIlBhbmVsIG9wYWNpdHkiKTsgY29sb3I6VmJUb2tlbnMudGV4dCB9CisgICAg
ICAgIFNsaWRlciB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgZnJvbTo0MDt0bzoxMDA7c3RlcFNp
emU6NTt2YWx1ZTpMb2NhbEhhcmR3YXJlLm9wYWNpdHk7IG9uTW92ZWQ6TG9jYWxIYXJkd2FyZS5v
cGFjaXR5PU1hdGgucm91bmQodmFsdWUpIH0KKyAgICB9CisgICAgUm93TGF5b3V0IHsKKyAgICAg
ICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6
VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiUmVmcmVzaCBpbnRlcnZhbCIpO2NvbG9yOlZi
VG9rZW5zLnRleHQgfQorICAgICAgICBFY2xpcHNlQ29tYm9Cb3ggeyBMYXlvdXQuZmlsbFdpZHRo
OnRydWU7IG1vZGVsOlsiMSBzZWNvbmQiLCIyIHNlY29uZHMiLCI1IHNlY29uZHMiXTsgY3VycmVu
dEluZGV4OkxvY2FsSGFyZHdhcmUucmVmcmVzaFNlY29uZHM9PT0xPzA6TG9jYWxIYXJkd2FyZS5y
ZWZyZXNoU2Vjb25kcz09PTU/MjoxOyBvbkFjdGl2YXRlZDpMb2NhbEhhcmR3YXJlLnJlZnJlc2hT
ZWNvbmRzPVsxLDIsNV1baW5kZXhdIH0KKyAgICB9CisgICAgRmxvdyB7CisgICAgICAgIExheW91
dC5maWxsV2lkdGg6dHJ1ZQorICAgICAgICBSZXBlYXRlciB7IG1vZGVsOlsiY3B1IiwibWVtb3J5
IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3JrIiwiYmF0dGVyeSIsInN0b3JhZ2UiXQorICAg
ICAgICAgICAgZGVsZWdhdGU6Q2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9k
eTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6bW9kZWxEYXRhOyBjaGVj
a2VkOkxvY2FsSGFyZHdhcmUuZmllbGRzLmluZGV4T2YobW9kZWxEYXRhKT49MDsgb25Ub2dnbGVk
Ont2YXIgZj1Mb2NhbEhhcmR3YXJlLmZpZWxkcy5zbGljZSgpO3ZhciBpPWYuaW5kZXhPZihtb2Rl
bERhdGEpO2lmKGNoZWNrZWQmJmk8MClmLnB1c2gobW9kZWxEYXRhKTtpZighY2hlY2tlZCYmaT49
MClmLnNwbGljZShpLDEpO0xvY2FsSGFyZHdhcmUuZmllbGRzPWZ9IH0KKyAgICAgICAgfQorICAg
IH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVs
U2l6ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRl
eHQuV3JhcDt0ZXh0OnFzVHIoIkVjbGlwc2UgdmlkZW8tZW5naW5lIGFjdGl2aXR5IHVzZXMgdGhp
cyBwcm9jZXNz4oCZcyBEUk0gY291bnRlcnMgd2hlbiBleHBvc2VkLiBJdCBpcyBub3Qgd2hvbGUt
c3lzdGVtIEdQVSBsb2FkLiBQZXItcHJvY2VzcyBHUFUgbWVtb3J5IGlzIHVuYXZhaWxhYmxlLiBT
dG9yYWdlIHJhdGVzIHJlZmxlY3QgdGhlIGFjdGl2ZSByb290IGRldmljZSB3aGVuIGFjY2Vzc2li
bGUuIE5vIHByaXZpbGVnZWQgR1BVIHByb2ZpbGVyIHJ1bnMgY29udGludW91c2x5LiIpO2NvbG9y
OlZiVG9rZW5zLnRleHREaW0gfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlU3lzdGVt
U2V0dGluZ3MucW1sIGIvYXBwL2d1aS9FY2xpcHNlU3lzdGVtU2V0dGluZ3MucW1sCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjVkMmJiYzkKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvZ3VpL0VjbGlwc2VTeXN0ZW1TZXR0aW5ncy5xbWwKQEAgLTAsMCArMSw4MyBAQAoraW1wb3J0
IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNr
LkxheW91dHMgMS4zCitpbXBvcnQgUXRRdWljay5Db250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9y
dCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFN5c3RlbUNvbnRyb2xzIDEuMAoraW1wb3J0
IExvY2FsSGFyZHdhcmUgMS4wCisKK0NvbHVtbkxheW91dCB7CisgICAgaWQ6IHN5c3RlbQorICAg
IHByb3BlcnR5IGJvb2wgYWN0aXZlOiBmYWxzZQorICAgIHByb3BlcnR5IHN0cmluZyBwb3dlckFj
dGlvbjogIiIKKyAgICBwcm9wZXJ0eSB2YXIgcG9pbnRlcjogcG9pbnRlckNob2ljZS5jdXJyZW50
SW5kZXggPj0gMCA/IChTeXN0ZW1Db250cm9scy5zdGF0ZS5wb2ludGVycyB8fCBbXSlbcG9pbnRl
ckNob2ljZS5jdXJyZW50SW5kZXhdIHx8ICh7fSkgOiAoe30pCisgICAgc3BhY2luZzogVmJUb2tl
bnMuc3BhY2UzCisgICAgb25BY3RpdmVDaGFuZ2VkOiB7IGlmKGFjdGl2ZSkgU3lzdGVtQ29udHJv
bHMub3BlbigiY2VudGVyIik7IGVsc2UgU3lzdGVtQ29udHJvbHMuY2xvc2UoKSB9CisgICAgQ29t
cG9uZW50Lm9uRGVzdHJ1Y3Rpb246IHsgaWYoYWN0aXZlKSBTeXN0ZW1Db250cm9scy5jbG9zZSgp
IH0KKyAgICBmdW5jdGlvbiByZXF1ZXN0KGFjdGlvbix2YWx1ZSkgeyBTeXN0ZW1Db250cm9scy5y
ZXF1ZXN0KCJjZW50ZXItIithY3Rpb24sdmFsdWUgfHwgIiIpIH0KKyAgICBmdW5jdGlvbiBzaG93
Q29ubmVjdGlvbnMoa2luZCkgeyBTeXN0ZW1Db250cm9scy5jbG9zZSgpOyBjb25uZWN0aW9ucy5r
aW5kPWtpbmQ7IGNvbm5lY3Rpb25zLm9wZW4oKSB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpW
YlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91
dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7dGV4dDpxc1RyKCJFY2xpcHNlT1Mg
4oCiIFN5c3RlbSBDb250cm9scyIpO2NvbG9yOlZiVG9rZW5zLnRleHQ7Zm9udC5ib2xkOnRydWUg
fQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxT
aXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4
dC5XcmFwO3RleHQ6U3lzdGVtQ29udHJvbHMuc3RhdHVzO2NvbG9yOlZiVG9rZW5zLnRleHREaW07
dGV4dEZvcm1hdDpUZXh0LlBsYWluVGV4dCB9CisgICAgQnVzeUluZGljYXRvciB7IHJ1bm5pbmc6
c3lzdGVtLmFjdGl2ZSAmJiBTeXN0ZW1Db250cm9scy5idXN5O3Zpc2libGU6cnVubmluZztMYXlv
dXQuYWxpZ25tZW50OlF0LkFsaWduSENlbnRlciB9CisgICAgUm93TGF5b3V0IHsKKyAgICAgICAg
TGF5b3V0LmZpbGxXaWR0aDp0cnVlCisgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0
OnFzVHIoIldpLUZpIG5ldHdvcmtzIik7aWNvblNvdXJjZToicXJjOi9yZXMvY3JpbXNvbi1uZXR3
b3JrLnN2ZyI7b25DbGlja2VkOnN5c3RlbS5zaG93Q29ubmVjdGlvbnMoIndpZmkiKSB9CisgICAg
ICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIkJsdWV0b290aCBkZXZpY2VzIik7
aWNvblNvdXJjZToicXJjOi9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnIjtvbkNsaWNrZWQ6c3lz
dGVtLnNob3dDb25uZWN0aW9ucygiYnQiKSB9CisgICAgfQorICAgIFJvd0xheW91dCB7CisgICAg
ICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxT
aXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIldpLUZpIHJhZGlvIik7Y2hlY2tlZDpT
eXN0ZW1Db250cm9scy5zdGF0ZS53aWZpX2VuYWJsZWQ9PT10cnVlO2VuYWJsZWQ6IVN5c3RlbUNv
bnRyb2xzLmJ1c3kgJiYgU3lzdGVtQ29udHJvbHMuc3RhdGUud2lmaV9lbmFibGVkIT09bnVsbCAm
JiBTeXN0ZW1Db250cm9scy5zdGF0ZS53aWZpX2VuYWJsZWQhPT11bmRlZmluZWQ7b25Ub2dnbGVk
OnN5c3RlbS5yZXF1ZXN0KCJ3aWZpLXJhZGlvIixjaGVja2VkPyJvbiI6Im9mZiIpIH0KKyAgICAg
ICAgQ2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNp
emU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiQmx1ZXRvb3RoIHJhZGlvIik7Y2hlY2tl
ZDpTeXN0ZW1Db250cm9scy5zdGF0ZS5ibHVldG9vdGhfZW5hYmxlZD09PXRydWU7ZW5hYmxlZDoh
U3lzdGVtQ29udHJvbHMuYnVzeSAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS5ibHVldG9vdGhfZW5h
YmxlZCE9PW51bGwgJiYgU3lzdGVtQ29udHJvbHMuc3RhdGUuYmx1ZXRvb3RoX2VuYWJsZWQhPT11
bmRlZmluZWQ7b25Ub2dnbGVkOnN5c3RlbS5yZXF1ZXN0KCJidC1yYWRpbyIsY2hlY2tlZD8ib24i
OiJvZmYiKSB9CisgICAgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJv
ZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIkF1ZGlvIGFu
ZCBicmlnaHRuZXNzIik7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LmJvbGQ6dHJ1ZSB9CisgICAg
Um93TGF5b3V0IHsKKyAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDp0cnVlCisgICAgICAgIFNsaWRl
ciB7IGlkOnZvbHVtZTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7ZnJvbTowO3RvOjEwMDtzdGVwU2l6
ZToxO3ZhbHVlOlN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSB8fCAwO2VuYWJsZWQ6IVN5c3Rl
bUNvbnRyb2xzLmJ1c3kgJiYgU3lzdGVtQ29udHJvbHMuc3RhdGUudm9sdW1lIT09bnVsbCAmJiBT
eXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUhPT11bmRlZmluZWQ7QWNjZXNzaWJsZS5uYW1lOnFz
VHIoIlNwZWFrZXIgdm9sdW1lIik7b25QcmVzc2VkQ2hhbmdlZDppZighcHJlc3NlZCYmZW5hYmxl
ZClzeXN0ZW0ucmVxdWVzdCgidm9sdW1lIixTdHJpbmcoTWF0aC5yb3VuZCh2YWx1ZSkpKTtvbk1v
dmVkOmlmKCFwcmVzc2VkJiZlbmFibGVkKXN5c3RlbS5yZXF1ZXN0KCJ2b2x1bWUiLFN0cmluZyhN
YXRoLnJvdW5kKHZhbHVlKSkpIH0KKyAgICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vu
cy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6TWF0aC5y
b3VuZCh2b2x1bWUudmFsdWUpKyIlIjtjb2xvcjpWYlRva2Vucy50ZXh0IH0KKyAgICAgICAgRWNs
aXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6U3lzdGVtQ29udHJvbHMuc3RhdGUubXV0ZWQ/cXNUcigi
VW5tdXRlIik6cXNUcigiTXV0ZSIpO2VuYWJsZWQ6dm9sdW1lLmVuYWJsZWQ7b25DbGlja2VkOnN5
c3RlbS5yZXF1ZXN0KCJtdXRlIikgfQorICAgIH0KKyAgICBFY2xpcHNlQ29tYm9Cb3ggeyBMYXlv
dXQuZmlsbFdpZHRoOnRydWU7bW9kZWw6U3lzdGVtQ29udHJvbHMuc3RhdGUuc2lua3MgfHwgW107
dGV4dFJvbGU6Im5hbWUiO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3kgJiYgY291bnQ+MDtB
Y2Nlc3NpYmxlLm5hbWU6cXNUcigiQXVkaW8gb3V0cHV0Iik7Y3VycmVudEluZGV4Ont2YXIgYT1T
eXN0ZW1Db250cm9scy5zdGF0ZS5zaW5rcyB8fCBbXTtmb3IodmFyIGk9MDtpPGEubGVuZ3RoO2kr
KylpZihhW2ldLmRlZmF1bHQpcmV0dXJuIGk7cmV0dXJuIC0xfQorICAgICAgICBvbkFjdGl2YXRl
ZDpzeXN0ZW0ucmVxdWVzdCgib3V0cHV0Iixtb2RlbFtpbmRleF0uaWQpIH0KKyAgICBSb3dMYXlv
dXQgeworICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpxc1RyKCJUZXN0IHNvdW5k
Iik7ZW5hYmxlZDp2b2x1bWUuZW5hYmxlZDtvbkNsaWNrZWQ6c3lzdGVtLnJlcXVlc3QoInRlc3Qt
c291bmQiKSB9CisgICAgICAgIEVjbGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1
ZTsgbW9kZWw6W3FzVHIoIkFpclBvZHM6IExvdyBsYXRlbmN5IikscXNUcigiQWlyUG9kczogUXVh
bGl0eSIpXTtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5O29uQWN0aXZhdGVkOnN5c3RlbS5y
ZXF1ZXN0KCJhaXJwb2RzIixpbmRleD09PTA/Imxvdy1sYXRlbmN5IjoicXVhbGl0eSIpIH0KKyAg
ICB9CisgICAgUmVwZWF0ZXIgeworICAgICAgICBtb2RlbDpbe2tpbmQ6InNjcmVlbiIsbGFiZWw6
cXNUcigiU2NyZWVuIGJyaWdodG5lc3MiKX0se2tpbmQ6ImtleWJvYXJkIixsYWJlbDpxc1RyKCJL
ZXlib2FyZCBsaWdodGluZyIpfV0KKyAgICAgICAgZGVsZWdhdGU6Q29sdW1uTGF5b3V0IHsKKyAg
ICAgICAgICAgIExheW91dC5maWxsV2lkdGg6dHJ1ZQorICAgICAgICAgICAgcHJvcGVydHkgdmFy
IGhhcmR3YXJlOihTeXN0ZW1Db250cm9scy5zdGF0ZS5icmlnaHRuZXNzIHx8IHt9KVttb2RlbERh
dGEua2luZF0KKyAgICAgICAgICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJv
ZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0Om1vZGVsRGF0YS5sYWJl
bCsoaGFyZHdhcmU/IiDigKIgIitoYXJkd2FyZS5wZXJjZW50KyIlIjoiIOKAoiAiK3FzVHIoIlVu
YXZhaWxhYmxlIikpO2NvbG9yOlZiVG9rZW5zLnRleHQgfQorICAgICAgICAgICAgU2xpZGVyIHsg
TGF5b3V0LmZpbGxXaWR0aDp0cnVlO2Zyb206bW9kZWxEYXRhLmtpbmQ9PT0ic2NyZWVuIj81OjA7
dG86MTAwO3N0ZXBTaXplOjE7ZW5hYmxlZDohIWhhcmR3YXJlJiYhU3lzdGVtQ29udHJvbHMuYnVz
eTt2YWx1ZTpoYXJkd2FyZT9oYXJkd2FyZS5wZXJjZW50OjA7QWNjZXNzaWJsZS5uYW1lOm1vZGVs
RGF0YS5sYWJlbDtvblByZXNzZWRDaGFuZ2VkOmlmKCFwcmVzc2VkJiZlbmFibGVkKXN5c3RlbS5y
ZXF1ZXN0KG1vZGVsRGF0YS5raW5kLFN0cmluZyhNYXRoLnJvdW5kKHZhbHVlKSkpO29uTW92ZWQ6
aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3QobW9kZWxEYXRhLmtpbmQsU3RyaW5n
KE1hdGgucm91bmQodmFsdWUpKSkgfQorICAgICAgICB9CisgICAgfQorICAgIExhYmVsIHsgZm9u
dC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVC
b2R5OyB0ZXh0OnFzVHIoIkRpc3BsYXkgYW5kIGlkbGUgYmxhbmtpbmciKTtjb2xvcjpWYlRva2Vu
cy50ZXh0O2ZvbnQuYm9sZDp0cnVlIH0KKyAgICBFY2xpcHNlQ29tYm9Cb3ggeyBpZDptb2RlQ2hv
aWNlO0xheW91dC5maWxsV2lkdGg6dHJ1ZTttb2RlbDpTeXN0ZW1Db250cm9scy5zdGF0ZS5kaXNw
bGF5cyB8fCBbXTt0ZXh0Um9sZToibmFtZSI7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeSAm
JiBjb3VudD4wO0FjY2Vzc2libGUubmFtZTpxc1RyKCJEaXNwbGF5IHJlc29sdXRpb24gYW5kIHJl
ZnJlc2ggcmF0ZSIpO2N1cnJlbnRJbmRleDp7dmFyIGE9U3lzdGVtQ29udHJvbHMuc3RhdGUuZGlz
cGxheXMgfHwgW107Zm9yKHZhciBpPTA7aTxhLmxlbmd0aDtpKyspaWYoYVtpXS5jdXJyZW50KXJl
dHVybiBpO3JldHVybiAtMX0gfQorICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIo
IkFwcGx5IGRpc3BsYXkgbW9kZSDigKIgMTUtc2Vjb25kIHJvbGxiYWNrIik7ZW5hYmxlZDptb2Rl
Q2hvaWNlLmVuYWJsZWQmJm1vZGVDaG9pY2UuY3VycmVudEluZGV4Pj0wO29uQ2xpY2tlZDpzeXN0
ZW0ucmVxdWVzdCgiZGlzcGxheSIsbW9kZUNob2ljZS5tb2RlbFttb2RlQ2hvaWNlLmN1cnJlbnRJ
bmRleF0uaWQpIH0KKyAgICBFY2xpcHNlQ29tYm9Cb3ggeyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7
IG1vZGVsOltxc1RyKCJOZXZlciBibGFuayIpLHFzVHIoIkJsYW5rIGFmdGVyIDUgbWludXRlcyIp
LHFzVHIoIkJsYW5rIGFmdGVyIDEwIG1pbnV0ZXMiKSxxc1RyKCJCbGFuayBhZnRlciAzMCBtaW51
dGVzIildO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25BY3RpdmF0ZWQ6c3lzdGVtLnJl
cXVlc3QoImlkbGUiLFsiMCIsIjMwMCIsIjYwMCIsIjE4MDAiXVtpbmRleF0pIH0KKyAgICBMYWJl
bCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vu
cy50eXBlQm9keTsgdGV4dDpxc1RyKCJQb2ludGVyIGFuZCB0cmFja3BhZCIpO2NvbG9yOlZiVG9r
ZW5zLnRleHQ7Zm9udC5ib2xkOnRydWUgfQorICAgIEVjbGlwc2VDb21ib0JveCB7IGlkOnBvaW50
ZXJDaG9pY2U7TGF5b3V0LmZpbGxXaWR0aDp0cnVlO21vZGVsOlN5c3RlbUNvbnRyb2xzLnN0YXRl
LnBvaW50ZXJzIHx8IFtdO3RleHRSb2xlOiJuYW1lIjtlbmFibGVkOmNvdW50PjAmJiFTeXN0ZW1D
b250cm9scy5idXN5O0FjY2Vzc2libGUubmFtZTpxc1RyKCJQb2ludGVyIGRldmljZSIpIH0KKyAg
ICBTbGlkZXIgeyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7ZnJvbTotMTt0bzoxO3N0ZXBTaXplOi4w
NTt2YWx1ZTpzeXN0ZW0ucG9pbnRlci5zcGVlZCB8fCAwO2VuYWJsZWQ6c3lzdGVtLnBvaW50ZXIu
c3BlZWQhPT11bmRlZmluZWQmJiFTeXN0ZW1Db250cm9scy5idXN5O0FjY2Vzc2libGUubmFtZTpx
c1RyKCJQb2ludGVyIGFjY2VsZXJhdGlvbiBzcGVlZCIpO29uUHJlc3NlZENoYW5nZWQ6aWYoIXBy
ZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3QoInBvaW50ZXItc3BlZWQiLHN5c3RlbS5wb2lu
dGVyLmlkKyI6Iit2YWx1ZS50b0ZpeGVkKDIpKTtvbk1vdmVkOmlmKCFwcmVzc2VkJiZlbmFibGVk
KXN5c3RlbS5yZXF1ZXN0KCJwb2ludGVyLXNwZWVkIixzeXN0ZW0ucG9pbnRlci5pZCsiOiIrdmFs
dWUudG9GaXhlZCgyKSkgfQorICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9u
dEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIk5hdHVy
YWwgc2Nyb2xsaW5nIik7Y2hlY2tlZDpzeXN0ZW0ucG9pbnRlci5uYXR1cmFsPT09MTtlbmFibGVk
OnN5c3RlbS5wb2ludGVyLm5hdHVyYWwhPT11bmRlZmluZWQmJiFTeXN0ZW1Db250cm9scy5idXN5
O29uVG9nZ2xlZDpzeXN0ZW0ucmVxdWVzdCgicG9pbnRlci1uYXR1cmFsIixzeXN0ZW0ucG9pbnRl
ci5pZCsiOiIrKGNoZWNrZWQ/IjEiOiIwIikpIH0KKyAgICBDaGVja0JveCB7IGZvbnQuZmFtaWx5
OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4
dDpxc1RyKCJUYXAgdG8gY2xpY2siKTtjaGVja2VkOnN5c3RlbS5wb2ludGVyLnRhcD09PTE7ZW5h
YmxlZDpzeXN0ZW0ucG9pbnRlci50YXAhPT11bmRlZmluZWQmJiFTeXN0ZW1Db250cm9scy5idXN5
O29uVG9nZ2xlZDpzeXN0ZW0ucmVxdWVzdCgicG9pbnRlci10YXAiLHN5c3RlbS5wb2ludGVyLmlk
KyI6IisoY2hlY2tlZD8iMSI6IjAiKSkgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tl
bnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmls
bFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5XcmFwO3RleHQ6cXNUcigiUG9pbnRlciBhbmQgYmxh
bmtpbmcgY2hhbmdlcyBjdXJyZW50bHkgYXBwbHkgdG8gdGhpcyBYMTEgc2Vzc2lvbi4gVW5zdXBw
b3J0ZWQgZGV2aWNlIGNvbnRyb2xzIGFyZSBkaXNhYmxlZC4gRGlzcGxheSBjaGFuZ2VzIHJldmVy
dCB1bmxlc3MgY29uZmlybWVkLiIpO2NvbG9yOlZiVG9rZW5zLnRleHREaW0gfQorICAgIExhYmVs
IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5z
LnR5cGVCb2R5OyB0ZXh0OnFzVHIoIlJlY292ZXJ5IGFuZCBwb3dlciIpO2NvbG9yOlZiVG9rZW5z
LnRleHQ7Zm9udC5ib2xkOnRydWUgfQorICAgIEVjbGlwc2VDb21ib0JveCB7IGlkOmZyb250ZW5k
O21vZGVsOlsiRWNsaXBzZSIsIkFydGVtaXMiLCJQZWdhc3VzIiwiTW9vbmxpZ2h0IiwiQ29jb09T
Il07QWNjZXNzaWJsZS5uYW1lOnFzVHIoIkZyb250ZW5kIGZvciBuZXh0IGJvb3QiKSB9CisgICAg
RWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiU2F2ZSBmcm9udGVuZCBmb3IgbmV4dCBi
b290Iik7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeTtvbkNsaWNrZWQ6c3lzdGVtLnJlcXVl
c3QoImZyb250ZW5kIixbInZpYmVtaXMiLCJhcnRlbWlzIiwicGVnYXN1cyIsIm1vb25saWdodCIs
ImNvY29vcyJdW2Zyb250ZW5kLmN1cnJlbnRJbmRleF0pIH0KKyAgICBGbG93IHsKKyAgICAgICAg
TGF5b3V0LmZpbGxXaWR0aDp0cnVlO3NwYWNpbmc6VmJUb2tlbnMuc3BhY2UyCisgICAgICAgIFJl
cGVhdGVyIHsgbW9kZWw6W3tuYW1lOnFzVHIoIlJlc3RhcnQgZnJvbnRlbmQiKSxhY3Rpb246InJl
c3RhcnQtZnJvbnRlbmQifSx7bmFtZTpxc1RyKCJSZXN0YXJ0IEVjbGlwc2VPUyIpLGFjdGlvbjoi
cmVib290In0se25hbWU6cXNUcigiU2h1dCBkb3duIiksYWN0aW9uOiJwb3dlcm9mZiJ9XQorICAg
ICAgICAgICAgZGVsZWdhdGU6RWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6bW9kZWxEYXRhLm5h
bWU7aWNvblNvdXJjZToicXJjOi9yZXMvZWNsaXBzZS1wb3dlci5zdmciO2VuYWJsZWQ6IVN5c3Rl
bUNvbnRyb2xzLmJ1c3k7b25DbGlja2VkOntzeXN0ZW0ucG93ZXJBY3Rpb249bW9kZWxEYXRhLmFj
dGlvbjtwb3dlci5vcGVuKCl9IH0KKyAgICAgICAgfQorICAgICAgICBFY2xpcHNlQWN0aW9uQnV0
dG9uIHsgdGV4dDpxc1RyKCJSZWRhY3RlZCBzdXBwb3J0IHJlcG9ydCIpO2VuYWJsZWQ6IVN5c3Rl
bUNvbnRyb2xzLmJ1c3k7b25DbGlja2VkOnN5c3RlbS5yZXF1ZXN0KCJyZXBvcnQiKSB9CisgICAg
ICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIlJlZnJlc2ggY29udHJvbHMiKTtl
bmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5O29uQ2xpY2tlZDpzeXN0ZW0ucmVxdWVzdCgibGlz
dCIpIH0KKyAgICB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsg
Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6dHJ1ZTt3
cmFwTW9kZTpUZXh0LldyYXA7dGV4dDpxc1RyKCJTdXNwZW5kIGFuZCBsaWQgcHJlc2V0cyBhd2Fp
dCBwaHlzaWNhbCB2YWxpZGF0aW9uLiBSZWNvdmVyeSBjb25zb2xlOiBDb250cm9sICsgT3B0aW9u
ICsgRjIgKEZuIGlmIG5lZWRlZCkuIik7Y29sb3I6VmJUb2tlbnMudGV4dERpbSB9CisgICAgRWNs
aXBzZUhhcmR3YXJlTW9uaXRvciB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTthY3RpdmU6c3lzdGVt
LmFjdGl2ZSB9CisgICAgU3lzdGVtQ29ubmVjdGlvbnNEaWFsb2cgeyBpZDpjb25uZWN0aW9ucztw
YXJlbnQ6T3ZlcmxheS5vdmVybGF5O29uQ2xvc2VkOmlmKHN5c3RlbS5hY3RpdmUpcmVzdW1lLnJl
c3RhcnQoKSB9CisgICAgVGltZXIgeyBpZDpyZXN1bWU7aW50ZXJ2YWw6NjAwO29uVHJpZ2dlcmVk
OmlmKHN5c3RlbS5hY3RpdmUpU3lzdGVtQ29udHJvbHMub3BlbigiY2VudGVyIikgfQorICAgIE5h
dmlnYWJsZURpYWxvZyB7IGlkOnBvd2VyO3BhcmVudDpPdmVybGF5Lm92ZXJsYXk7d2lkdGg6TWF0
aC5taW4oNDQwLHBhcmVudC53aWR0aC0zMik7dGl0bGU6cXNUcigiQ29uZmlybSBzeXN0ZW0gYWN0
aW9uIik7c3RhbmRhcmRCdXR0b25zOkRpYWxvZy5ZZXN8RGlhbG9nLk5vO2JhY2tncm91bmQ6UmVj
dGFuZ2xle2NvbG9yOlZiVG9rZW5zLmJnRWxldjtyYWRpdXM6VmJUb2tlbnMucmFkaXVzRGlhbG9n
O2JvcmRlci5jb2xvcjpWYlRva2Vucy5zdHJva2V9CisgICAgICAgIG9uQWNjZXB0ZWQ6U3lzdGVt
Q29udHJvbHMucmVxdWVzdCgiY2VudGVyLSIrc3lzdGVtLnBvd2VyQWN0aW9uLCIiLHRydWUpO2Nv
bnRlbnRJdGVtOkxhYmVse3dyYXBNb2RlOlRleHQuV3JhcDt0ZXh0OnFzVHIoIlByb2NlZWQgd2l0
aCAlMT8gQWN0aXZlIHN0cmVhbWluZyB3aWxsIGVuZC4iKS5hcmcoc3lzdGVtLnBvd2VyQWN0aW9u
KTtjb2xvcjpWYlRva2Vucy50ZXh0fSB9CisgICAgTmF2aWdhYmxlRGlhbG9nIHsgaWQ6Y29uZmly
bWF0aW9uO3BhcmVudDpPdmVybGF5Lm92ZXJsYXk7d2lkdGg6TWF0aC5taW4oNDgwLHBhcmVudC53
aWR0aC0zMik7dGl0bGU6cXNUcigiS2VlcCBkaXNwbGF5IG1vZGU/Iik7c3RhbmRhcmRCdXR0b25z
OkRpYWxvZy5ZZXN8RGlhbG9nLk5vO2Nsb3NlUG9saWN5OlBvcHVwLk5vQXV0b0Nsb3NlO2JhY2tn
cm91bmQ6UmVjdGFuZ2xle2NvbG9yOlZiVG9rZW5zLmJnRWxldjtyYWRpdXM6VmJUb2tlbnMucmFk
aXVzRGlhbG9nO2JvcmRlci5jb2xvcjpWYlRva2Vucy5zdHJva2V9CisgICAgICAgIG9uQWNjZXB0
ZWQ6U3lzdGVtQ29udHJvbHMuYW5zd2VyKCJ5ZXMiKTtvblJlamVjdGVkOlN5c3RlbUNvbnRyb2xz
LmFuc3dlcigibm8iKTtjb250ZW50SXRlbTpMYWJlbHt3cmFwTW9kZTpUZXh0LldyYXA7dGV4dDpT
eXN0ZW1Db250cm9scy5wcm9tcHQ7Y29sb3I6VmJUb2tlbnMudGV4dH0gfQorICAgIENvbm5lY3Rp
b25zIHsgdGFyZ2V0OlN5c3RlbUNvbnRyb2xzO2Z1bmN0aW9uIG9uQ2hhbmdlZCgpe2lmKHN5c3Rl
bS5hY3RpdmUmJlN5c3RlbUNvbnRyb2xzLnByb21wdC5sZW5ndGg+MCYmIWNvbm5lY3Rpb25zLm9w
ZW5lZCljb25maXJtYXRpb24ub3BlbigpO2lmKCFTeXN0ZW1Db250cm9scy5idXN5KWNvbmZpcm1h
dGlvbi5jbG9zZSgpfSB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1BjVmlldy5xbWwgYi9hcHAv
Z3VpL1BjVmlldy5xbWwKaW5kZXggZjBlNzM5YS4uZjRkMDEyYiAxMDA2NDQKLS0tIGEvYXBwL2d1
aS9QY1ZpZXcucW1sCisrKyBiL2FwcC9ndWkvUGNWaWV3LnFtbApAQCAtNDQ0LDcgKzQ0NCw3IEBA
IENlbnRlcmVkR3JpZFZpZXcgewogICAgICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogbW9k
ZWwub25saW5lICYmIG1vZGVsLnBhaXJlZCwKICAgICAgICAgICAgICAgICAgICAgICAgIHRyaWdn
ZXI6IGZ1bmN0aW9uKCkgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHZhciBjb21wb25l
bnQgPSBRdC5jcmVhdGVDb21wb25lbnQoIkFwcFZpZXcucW1sIikKLSAgICAgICAgICAgICAgICAg
ICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3
LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgIm9iamVjdE5hbWUiOiBtb2RlbC5uYW1lLCAic2hv
d0hpZGRlbkdhbWVzIjogdHJ1ZSwgImhvc3RPbmxpbmUiOiBtb2RlbC5vbmxpbmUsICJob3N0VHlw
ZSI6IG1vZGVsLmhvc3RUeXBlLCAiaG9zdFRyYW5zcG9ydCI6IG1vZGVsLnRyYW5zcG9ydH0pCisg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgdmFyIGFwcFZpZXcgPSBjb21wb25lbnQuY3JlYXRl
T2JqZWN0KHN0YWNrVmlldywgeyJjb21wdXRlckluZGV4IjogaW5kZXgsICJjcmltc29uSG9zdCI6
IGNvbXB1dGVyTW9kZWwuY3JpbXNvbkhvc3QoaW5kZXgpLCAib2JqZWN0TmFtZSI6IG1vZGVsLm5h
bWUsICJzaG93SGlkZGVuR2FtZXMiOiB0cnVlLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwg
Imhvc3RUeXBlIjogbW9kZWwuaG9zdFR5cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNw
b3J0fSkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdGFja1ZpZXcucHVzaChhcHBWaWV3
KQogICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICB9LApAQCAt
NTM1LDcgKzUzNSw3IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgICAgICAgICAgICAgIGVsc2Ug
aWYgKG1vZGVsLnBhaXJlZCkgewogICAgICAgICAgICAgICAgICAgICAvLyBnbyB0byBnYW1lIHZp
ZXcKICAgICAgICAgICAgICAgICAgICAgdmFyIGNvbXBvbmVudCA9IFF0LmNyZWF0ZUNvbXBvbmVu
dCgiQXBwVmlldy5xbWwiKQotICAgICAgICAgICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBv
bmVudC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgIm9i
amVjdE5hbWUiOiBtb2RlbC5uYW1lLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhvc3RU
eXBlIjogbW9kZWwuaG9zdFR5cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0fSkK
KyAgICAgICAgICAgICAgICAgICAgdmFyIGFwcFZpZXcgPSBjb21wb25lbnQuY3JlYXRlT2JqZWN0
KHN0YWNrVmlldywgeyJjb21wdXRlckluZGV4IjogaW5kZXgsICJjcmltc29uSG9zdCI6IGNvbXB1
dGVyTW9kZWwuY3JpbXNvbkhvc3QoaW5kZXgpLCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUsICJo
b3N0T25saW5lIjogbW9kZWwub25saW5lLCAiaG9zdFR5cGUiOiBtb2RlbC5ob3N0VHlwZSwgImhv
c3RUcmFuc3BvcnQiOiBtb2RlbC50cmFuc3BvcnR9KQogICAgICAgICAgICAgICAgICAgICBzdGFj
a1ZpZXcucHVzaChhcHBWaWV3KQogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICBl
bHNlIHsKZGlmZiAtLWdpdCBhL2FwcC9ndWkvUXVpY2tNZW51LnFtbCBiL2FwcC9ndWkvUXVpY2tN
ZW51LnFtbAppbmRleCBiMDMzZDI2Li4wZDk3OTRkIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1F1aWNr
TWVudS5xbWwKKysrIGIvYXBwL2d1aS9RdWlja01lbnUucW1sCkBAIC00NDksNyArNDQ5LDcgQEAg
UmVjdGFuZ2xlIHsKICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlF1aXQgZ2FtZSIpCiAgICAgICAg
ICAgICBpY29uOiAicG93ZXIiCiAgICAgICAgICAgICBhY3Rpb246ICJxdWl0IgotICAgICAgICAg
ICAgZGVzY3JpcHRpb246IHFzVHIoIlF1aXQgdGhlIGdhbWUgb24gdGhlIGhvc3QgYW5kIHJldHVy
biB0byBWaWJlbWlzIikKKyAgICAgICAgICAgIGRlc2NyaXB0aW9uOiBxc1RyKCJRdWl0IHRoZSBn
YW1lIG9uIHRoZSBob3N0IGFuZCByZXR1cm4gdG8gRWNsaXBzZSIpCiAgICAgICAgIH0KICAgICAg
ICAgTGlzdEVsZW1lbnQgewogICAgICAgICAgICAgdGV4dDogcXNUcigiU2VydmVyIGNvbW1hbmRz
IikKZGlmZiAtLWdpdCBhL2FwcC9ndWkvU2V0dGluZ3NWaWV3LnFtbCBiL2FwcC9ndWkvU2V0dGlu
Z3NWaWV3LnFtbAppbmRleCA0OTRlMzViLi45MGJhM2M2IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1Nl
dHRpbmdzVmlldy5xbWwKKysrIGIvYXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sCkBAIC0zNDYsMTIg
KzM0NiwxMyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgeyBpY29uOiAiZ2FtZXBhZCIs
ICAgbGFiZWw6IHFzVHIoIklucHV0ICYgZ2FtZXBhZCIpIH0sCiAgICAgICAgICAgICAgICAgICAg
IHsgaWNvbjogInN0cmVhbWluZyIsIGxhYmVsOiBxc1RyKCJTdHJlYW1pbmciKSB9LAogICAgICAg
ICAgICAgICAgICAgICB7IGljb246ICJhcHBzIiwgICAgICBsYWJlbDogcXNUcigiQXBwICYgVUki
KSB9LAotICAgICAgICAgICAgICAgICAgICB7IGljb246ICJhZHZhbmNlZCIsICBsYWJlbDogcXNU
cigiQWR2YW5jZWQiKSB9CisgICAgICAgICAgICAgICAgICAgIHsgaWNvbjogImFkdmFuY2VkIiwg
IGxhYmVsOiBxc1RyKCJBZHZhbmNlZCIpIH0sCisgICAgICAgICAgICAgICAgICAgIHsgaWNvbjog
ImFkdmFuY2VkIiwgbGFiZWw6IHFzVHIoIlN5c3RlbSBDb250cm9scyIpIH0KICAgICAgICAgICAg
ICAgICBdCiAgICAgICAgICAgICAgICAgZGVsZWdhdGU6IEJ1dHRvbiB7CiAgICAgICAgICAgICAg
ICAgICAgIGlkOiBjYXRCdXR0b24KICAgICAgICAgICAgICAgICAgICAgd2lkdGg6IHNpZGViYXJD
b2x1bW4ud2lkdGgKLSAgICAgICAgICAgICAgICAgICAgaGVpZ2h0OiA1OAorICAgICAgICAgICAg
ICAgICAgICBoZWlnaHQ6IE1hdGgubWluKDU4LE1hdGgubWF4KDQ0LChzaWRlYmFyLmhlaWdodC02
NC0oc2lkZWJhclJlcGVhdGVyLmNvdW50LTEpKlZiVG9rZW5zLnNwYWNlMikvc2lkZWJhclJlcGVh
dGVyLmNvdW50KSkKICAgICAgICAgICAgICAgICAgICAgcGFkZGluZzogMAogICAgICAgICAgICAg
ICAgICAgICBsZWZ0UGFkZGluZzogVmJUb2tlbnMuc3BhY2U0CiAgICAgICAgICAgICAgICAgICAg
IHJpZ2h0UGFkZGluZzogVmJUb2tlbnMuc3BhY2U0CkBAIC01NzEsNiArNTcyLDEyIEBAIEl0ZW0g
ewogICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLnRleHQKICAgICAgICAgfQogCisgICAgICAg
IEVjbGlwc2VTeXN0ZW1TZXR0aW5ncyB7CisgICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRo
IC0gKHBhcmVudC5sZWZ0UGFkZGluZyArIHBhcmVudC5yaWdodFBhZGRpbmcpCisgICAgICAgICAg
ICB2aXNpYmxlOiBzZXR0aW5nc1BhZ2UuY2F0ZWdvcnkgPT09IDYKKyAgICAgICAgICAgIGFjdGl2
ZTogc2V0dGluZ3NQYWdlLnZpc2libGUgJiYgdmlzaWJsZQorICAgICAgICB9CisKICAgICAgICAg
Ly8gLS0tLSBMaXZlIHN0cmVhbSBzdW1tYXJ5IGxpbmUgKHJlZGVzaWduKSwgcmVsb2NhdGVkIGhl
cmUgKHdhcyBpbnNpZGUgQmFzaWMKICAgICAgICAgLy8gU2V0dGluZ3MpIHNvIGl0IHNpdHMgZGly
ZWN0bHkgdW5kZXIgdGhlICJWaWRlbyIgdGl0bGUgbGlrZSB0aGUgZGVzaWduLgogICAgICAgICAv
LyBOdW1iZXJzIHJlbmRlciBpbiBhY2NlbnQ7IHRoZSByZXN0IHN0YXlzIGRpbS4gQ29udGVudC9i
aW5kaW5ncyB1bmNoYW5nZWQuCkBAIC0xNjgxLDcgKzE2ODgsNyBAQCBJdGVtIHsKICAgICAgICAg
ICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29s
VGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBo
b3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiV2hlbiB0aGUg
bmV0d29yayBjYW4ndCBzdXN0YWluIHRoZSBjb25maWd1cmVkIGJpdHJhdGUgYW5kIHRoZSBzdHJl
YW0gY29sbGFwc2VzLCBWaWJlbWlzIGF1dG9tYXRpY2FsbHkgcmVjb25uZWN0cyBhdCBhIGxvd2Vy
IGJpdHJhdGUgdW50aWwgdGhlIHN0cmVhbSBpcyB1c2FibGUuIFlvdXIgc2F2ZWQgYml0cmF0ZSBz
ZXR0aW5nIGlzIG5ldmVyIGNoYW5nZWQuIikKKyAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50
ZXh0OiBxc1RyKCJXaGVuIHRoZSBuZXR3b3JrIGNhbid0IHN1c3RhaW4gdGhlIGNvbmZpZ3VyZWQg
Yml0cmF0ZSBhbmQgdGhlIHN0cmVhbSBjb2xsYXBzZXMsIEVjbGlwc2UgYXV0b21hdGljYWxseSBy
ZWNvbm5lY3RzIGF0IGEgbG93ZXIgYml0cmF0ZSB1bnRpbCB0aGUgc3RyZWFtIGlzIHVzYWJsZS4g
WW91ciBzYXZlZCBiaXRyYXRlIHNldHRpbmcgaXMgbmV2ZXIgY2hhbmdlZC4iKQogICAgICAgICAg
ICAgICAgIH0KIAogICAgICAgICAgICAgICAgIC8vIFZpYmVtaXMgKHBlcmYgZ3VpZGFuY2UpOiBh
ZHZpc2Ugd2hlbiB0aGUgYml0cmF0ZSBpcyBzZXQgd2VsbCBhYm92ZSB0aGUgcmVjb21tZW5kZWQK
QEAgLTI0ODIsNyArMjQ4OSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICBUb29sVGlw
LmRlbGF5OiAxMDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGltZW91dDogNTAwMAog
ICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKLSAgICAgICAgICAg
ICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJJZiBhIHN0cmVhbSBlbmRzIHVuZXhwZWN0ZWRs
eSAoYSBuZXR3b3JrIGJsaXAgb3IgdGhlIGhvc3Qgd2FraW5nKSwgVmliZW1pcyB3aWxsIHRyeSB0
byByZWNvbm5lY3QgYXV0b21hdGljYWxseS4iKQorICAgICAgICAgICAgICAgICAgICBUb29sVGlw
LnRleHQ6IHFzVHIoIklmIGEgc3RyZWFtIGVuZHMgdW5leHBlY3RlZGx5IChhIG5ldHdvcmsgYmxp
cCBvciB0aGUgaG9zdCB3YWtpbmcpLCBFY2xpcHNlIHdpbGwgdHJ5IHRvIHJlY29ubmVjdCBhdXRv
bWF0aWNhbGx5LiIpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgfQogICAgICAgICB9
CkBAIC0yNTQ2LDcgKzI1NTMsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICBzcGFjaW5nOiBW
YlRva2Vucy5zcGFjZTMKIAogICAgICAgICAgICAgICAgIFZiU2VjdGlvbkhlYWRlciB7Ci0gICAg
ICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMgU3RyZWFtaW5nIEVuaGFuY2VtZW50
cyIpCisgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkVjbGlwc2UgU3RyZWFtaW5nIEVu
aGFuY2VtZW50cyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgTGFiZWwg
ewpAQCAtMjc3Niw3ICsyNzgzLDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBWYlRvZ2ds
ZVJvdyB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiBtdXRlT25Gb2N1c0xvc3NDaGVjawotICAg
ICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJNdXRlIGF1ZGlvIHN0cmVhbSB3aGVuIFZpYmVt
aXMgaXMgbm90IHRoZSBhY3RpdmUgd2luZG93IikKKyAgICAgICAgICAgICAgICAgICAgdGV4dDog
cXNUcigiTXV0ZSBhdWRpbyBzdHJlYW0gd2hlbiBFY2xpcHNlIGlzIG5vdCB0aGUgYWN0aXZlIHdp
bmRvdyIpCiAgICAgICAgICAgICAgICAgICAgIHZpc2libGU6IFN5c3RlbVByb3BlcnRpZXMuaGFz
RGVza3RvcEVudmlyb25tZW50CiAgICAgICAgICAgICAgICAgICAgIGNoZWNrZWQ6IFN0cmVhbWlu
Z1ByZWZlcmVuY2VzLm11dGVPbkZvY3VzTG9zcwogICAgICAgICAgICAgICAgICAgICBvbkNoZWNr
ZWRDaGFuZ2VkOiB7CkBAIC0yNzg2LDcgKzI3OTMsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAg
ICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRp
bWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVk
Ci0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiTXV0ZXMgVmliZW1pcydz
IGF1ZGlvIHdoZW4geW91IEFsdCtUYWIgb3V0IG9mIHRoZSBzdHJlYW0gb3IgY2xpY2sgb24gYSBk
aWZmZXJlbnQgd2luZG93LiIpCisgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNU
cigiTXV0ZXMgRWNsaXBzZSdzIGF1ZGlvIHdoZW4geW91IEFsdCtUYWIgb3V0IG9mIHRoZSBzdHJl
YW0gb3IgY2xpY2sgb24gYSBkaWZmZXJlbnQgd2luZG93LiIpCiAgICAgICAgICAgICAgICAgfQog
ICAgICAgICAgICAgfQogICAgICAgICB9CkBAIC0yOTcxLDcgKzI5NzgsNyBAQCBJdGVtIHsKICAg
ICAgICAgICAgICAgICAgICAgICAgIGlmIChTdHJlYW1pbmdQcmVmZXJlbmNlcy5sYW5ndWFnZSAh
PT0gbmV3X2xhbmd1YWdlKSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgU3RyZWFtaW5n
UHJlZmVyZW5jZXMubGFuZ3VhZ2UgPSBsYW5ndWFnZUxpc3RNb2RlbC5nZXQoY3VycmVudEluZGV4
KS52YWwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiAoIVN0cmVhbWluZ1ByZWZlcmVu
Y2VzLnJldHJhbnNsYXRlKCkpIHsKLSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVG9v
bFRpcC5zaG93KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQgVmliZW1pcyBmb3IgdGhpcyBjaGFuZ2Ug
dG8gdGFrZSBlZmZlY3QiKSwgNTAwMCkKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
VG9vbFRpcC5zaG93KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQgRWNsaXBzZSBmb3IgdGhpcyBjaGFu
Z2UgdG8gdGFrZSBlZmZlY3QiKSwgNTAwMCkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9
CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZWxzZSB7CiAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgIC8vIEZvcmNlIHRoZSBiYWNrIG9wZXJhdGlvbiB0byBwb3AgYW55IEFwcFZp
ZXcgcGFnZXMgdGhhdCBleGlzdC4KQEAgLTMwNTUsMTQgKzMwNjIsMjYgQEAgSXRlbSB7CiAgICAg
ICAgICAgICAgICAgICAgIHRleHRSb2xlOiAidGV4dCIKICAgICAgICAgICAgICAgICAgICAgaG92
ZXJFbmFibGVkOiB0cnVlCiAgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBMaXN0TW9kZWwgewot
ICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJUZWFsIChk
ZWZhdWx0KSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDog
cXNUcigiVGVhbCIpIH0KICAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4
dDogcXNUcigiSW5kaWdvIikgfQogICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQg
eyB0ZXh0OiBxc1RyKCJHcmVlbiIpIH0KICAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVt
ZW50IHsgdGV4dDogcXNUcigiQW1iZXIiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0
RWxlbWVudCB7IHRleHQ6IHFzVHIoIkNyaW1zb24gKGRlZmF1bHQpIikgfQorICAgICAgICAgICAg
ICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJSZWQiKSB9CisgICAgICAgICAg
ICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIk9yYW5nZSIpIH0KKyAgICAg
ICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiR29sZCIpIH0KKyAg
ICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiTGltZSIpIH0K
KyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiTWludCIp
IH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiQ3lh
biIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigi
Qmx1ZSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNU
cigiVmlvbGV0IikgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0
OiBxc1RyKCJQaW5rIikgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0
ZXh0OiBxc1RyKCJTaWx2ZXIiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVu
dCB7IHRleHQ6IHFzVHIoIlJvc2UiKSB9CiAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAg
ICAgICAgICAgICAgQ29tcG9uZW50Lm9uQ29tcGxldGVkOiBjdXJyZW50SW5kZXggPSBTdHJlYW1p
bmdQcmVmZXJlbmNlcy51aUFjY2VudEluZGV4CiAgICAgICAgICAgICAgICAgICAgIG9uQWN0aXZh
dGVkOiBTdHJlYW1pbmdQcmVmZXJlbmNlcy51aUFjY2VudEluZGV4ID0gY3VycmVudEluZGV4Ci0g
ICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiVGhlIGFjY2VudCBjb2xvciB1
c2VkIGFjcm9zcyB0aGUgcmVkZXNpZ25lZCBVSS4iKQorICAgICAgICAgICAgICAgICAgICBUb29s
VGlwLnRleHQ6IHFzVHIoIlRoZSBhY2NlbnQgY29sb3IgdXNlZCB0aHJvdWdob3V0IEVjbGlwc2Uu
IikKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAg
ICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKICAgICAgICAgICAgICAgICB9CkBAIC0z
MTQ3LDcgKzMxNjYsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAu
ZGVsYXk6IDEwMDAKICAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGltZW91dDogNTAw
MAogICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAg
ICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlNhdmUgYWxsIFZpYmVtaXMg
c2V0dGluZ3MgdG8gfi92aWJlbWlzLXNldHRpbmdzLmluaSBmb3IgYmFja3VwIG9yIHRvIGNvcHkg
dG8gYW5vdGhlciBkZXZpY2UuIikKKyAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4
dDogcXNUcigiU2F2ZSBhbGwgRWNsaXBzZSBzZXR0aW5ncyB0byB+L3ZpYmVtaXMtc2V0dGluZ3Mu
aW5pIGZvciBiYWNrdXAgb3IgdG8gY29weSB0byBhbm90aGVyIGRldmljZS4iKQogICAgICAgICAg
ICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsKQEAgLTM0MDIsNyAr
MzQyMSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDEw
MDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAogICAgICAg
ICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlRoaXMgZW5hYmxlcyB0aGUgY2FwdHVy
ZSBvZiBzeXN0ZW0td2lkZSBrZXlib2FyZCBzaG9ydGN1dHMgbGlrZSBBbHQrVGFiIHRoYXQgd291
bGQgbm9ybWFsbHkgYmUgaGFuZGxlZCBieSB0aGUgY2xpZW50IE9TIHdoaWxlIHN0cmVhbWluZy4i
KSArICJcblxuIiArCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcXNUcigiTk9U
RTogQ2VydGFpbiBrZXlib2FyZCBzaG9ydGN1dHMgbGlrZSBDdHJsK0FsdCtEZWwgb24gV2luZG93
cyBjYW5ub3QgYmUgaW50ZXJjZXB0ZWQgYnkgYW55IGFwcGxpY2F0aW9uLCBpbmNsdWRpbmcgVmli
ZW1pcy4iKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHFzVHIoIk5PVEU6IENl
cnRhaW4ga2V5Ym9hcmQgc2hvcnRjdXRzIGxpa2UgQ3RybCtBbHQrRGVsIG9uIFdpbmRvd3MgY2Fu
bm90IGJlIGludGVyY2VwdGVkIGJ5IGFueSBhcHBsaWNhdGlvbiwgaW5jbHVkaW5nIEVjbGlwc2Uu
IikKICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICBBdXRvUmVzaXppbmdDb21i
b0JveCB7CkBAIC0zNjQzLDcgKzM2NjIsNyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgIFZi
VG9nZ2xlUm93IHsKICAgICAgICAgICAgICAgICAgICAgaWQ6IGJhY2tncm91bmRHYW1lcGFkQ2hl
Y2sKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiUHJvY2VzcyBnYW1lcGFkIGlucHV0
IHdoZW4gVmliZW1pcyBpcyBpbiB0aGUgYmFja2dyb3VuZCIpCisgICAgICAgICAgICAgICAgICAg
IHRleHQ6IHFzVHIoIlByb2Nlc3MgZ2FtZXBhZCBpbnB1dCB3aGVuIEVjbGlwc2UgaXMgaW4gdGhl
IGJhY2tncm91bmQiKQogICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBTeXN0ZW1Qcm9wZXJ0
aWVzLmhhc0Rlc2t0b3BFbnZpcm9ubWVudAogICAgICAgICAgICAgICAgICAgICBjaGVja2VkOiBT
dHJlYW1pbmdQcmVmZXJlbmNlcy5iYWNrZ3JvdW5kR2FtZXBhZAogICAgICAgICAgICAgICAgICAg
ICBvbkNoZWNrZWRDaGFuZ2VkOiB7CkBAIC0zNjUzLDcgKzM2NzIsNyBAQCBJdGVtIHsKICAgICAg
ICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBU
b29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxl
OiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiQWxsb3dz
IFZpYmVtaXMgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0cyBldmVuIGlmIGl0J3Mgbm90IHRoZSBj
dXJyZW50IHdpbmRvdyBpbiBmb2N1cyIpCisgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4
dDogcXNUcigiQWxsb3dzIEVjbGlwc2UgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0cyBldmVuIGlm
IGl0J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBmb2N1cyIpCiAgICAgICAgICAgICAgICAg
fQogCiAgICAgICAgICAgICAgICAgVmJUb2dnbGVSb3cgewpAQCAtMzcyNCw3ICszNzQzLDcgQEAg
SXRlbSB7CiAgICAgICAgICAgICAgICAgTGFiZWwgewogICAgICAgICAgICAgICAgICAgICB3aWR0
aDogcGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsVGl0
bGUKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiU29mdHdhcmUgdXBkYXRlcyIpCisg
ICAgICAgICAgICAgICAgICAgIHRleHQ6IEF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZCA/IHFz
VHIoIkVjbGlwc2VPUyB1cGRhdGVzIikgOiBxc1RyKCJTb2Z0d2FyZSB1cGRhdGVzIikKICAgICAg
ICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVMYWJlbAogICAgICAg
ICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKICAgICAgICAgICAg
ICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtMzczMyw2ICszNzUyLDcgQEAgSXRlbSB7
CiAKICAgICAgICAgICAgICAgICBBdXRvUmVzaXppbmdDb21ib0JveCB7CiAgICAgICAgICAgICAg
ICAgICAgIGlkOiB1cGRhdGVDaGFubmVsQ29tYm9Cb3gKKyAgICAgICAgICAgICAgICAgICAgdmlz
aWJsZTogIUF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZAogICAgICAgICAgICAgICAgICAgICB0
ZXh0Um9sZTogInRleHQiCiAgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBMaXN0TW9kZWwgewog
ICAgICAgICAgICAgICAgICAgICAgICAgaWQ6IHVwZGF0ZUNoYW5uZWxMaXN0TW9kZWwKQEAgLTM3
ODcsNiArMzgwNyw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAvLyBpbnN0YWxsIGlu
IGZsaWdodCBhdCBhIHRpbWUpLCBzbyBidXR0b25zIHN0YXkgZW5hYmxlZC4KICAgICAgICAgICAg
ICAgICAgICAgQnV0dG9uIHsKICAgICAgICAgICAgICAgICAgICAgICAgIGlkOiBjaGVja1VwZGF0
ZXNCdXR0b24KKyAgICAgICAgICAgICAgICAgICAgICAgIHZpc2libGU6ICFBdXRvVXBkYXRlQ2hl
Y2tlci5vc01hbmFnZWQKICAgICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkNoZWNr
IGZvciB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogewogICAg
ICAgICAgICAgICAgICAgICAgICAgICAgIEF1dG9VcGRhdGVDaGVja2VyLmNoZWNrTm93KCkKQEAg
LTM4MDQsOCArMzgyNSw4IEBAIEl0ZW0gewogCiAgICAgICAgICAgICAgICAgICAgIEJ1dHRvbiB7
CiAgICAgICAgICAgICAgICAgICAgICAgICBpZDogdmlld1JlbGVhc2VCdXR0b24KLSAgICAgICAg
ICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpZXcgcmVsZWFzZSIpCi0gICAgICAgICAgICAg
ICAgICAgICAgICB2aXNpYmxlOiBBdXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2YWlsYWJsZQorICAg
ICAgICAgICAgICAgICAgICAgICAgdGV4dDogQXV0b1VwZGF0ZUNoZWNrZXIub3NNYW5hZ2VkID8g
cXNUcigiRWNsaXBzZU9TIHJlbGVhc2VzIikgOiBxc1RyKCJWaWV3IHJlbGVhc2UiKQorICAgICAg
ICAgICAgICAgICAgICAgICAgdmlzaWJsZTogKEF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZCB8
fCBBdXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2YWlsYWJsZSkKICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICYmIEF1dG9VcGRhdGVDaGVja2VyLnJlbGVhc2VVcmwgIT09ICIiCiAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAmJiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dz
ZXIKICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogewpAQCAtMzg0Miw3ICszODYz
LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCiAK
ICAgICAgICAgICAgICAgICBWYlNlY3Rpb25IZWFkZXIgewotICAgICAgICAgICAgICAgICAgICB0
ZXh0OiBxc1RyKCJWaWJlbWlzIEZlYXR1cmVzIikKKyAgICAgICAgICAgICAgICAgICAgdGV4dDog
cXNUcigiRWNsaXBzZSBGZWF0dXJlcyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAg
ICAgICAgQ2xpcGJvYXJkU2V0dGluZ3MgewpAQCAtMzk0Nyw3ICszOTY4LDcgQEAgSXRlbSB7CiAg
ICAgICAgICAgICAgICAgUmVwZWF0ZXIgewogICAgICAgICAgICAgICAgICAgICB3aWR0aDogcGFy
ZW50LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBbCi0gICAgICAgICAgICAgICAg
ICAgICAgICB7IGs6IHFzVHIoIlZpYmVtaXMgdmVyc2lvbiIpLCB2OiBTeXN0ZW1Qcm9wZXJ0aWVz
LnZlcnNpb25TdHJpbmcgfSwKKyAgICAgICAgICAgICAgICAgICAgICAgIHsgazogcXNUcigiRWNs
aXBzZSB2ZXJzaW9uIiksIHY6IFN5c3RlbVByb3BlcnRpZXMudmVyc2lvblN0cmluZyB9LAogICAg
ICAgICAgICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJBcmNoaXRlY3R1cmUiKSwgICAgdjogU3lz
dGVtUHJvcGVydGllcy5mcmllbmRseU5hdGl2ZUFyY2hOYW1lIH0sCiAgICAgICAgICAgICAgICAg
ICAgICAgICB7IGs6IHFzVHIoIlN0ZWFtT1MgLyBnYW1lc2NvcGUiKSwgdjogU3lzdGVtUHJvcGVy
dGllcy5pc1N0ZWFtRGVjayA/IHFzVHIoIlllcyIpIDogcXNUcigiTm8iKSB9LAogICAgICAgICAg
ICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJEaXNwbGF5IHNlcnZlciIpLCAgdjogU3lzdGVtUHJv
cGVydGllcy5pc1J1bm5pbmdXYXlsYW5kID8gKFN5c3RlbVByb3BlcnRpZXMuaXNSdW5uaW5nWFdh
eWxhbmQgPyAiWFdheWxhbmQiIDogIldheWxhbmQiKSA6ICJYMTEiIH0sCkBAIC00MDEzLDcgKzQw
MzQsNyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgIExhYmVsIHsKICAgICAgICAgICAgICAg
ICAgICAgd2lkdGg6IHBhcmVudC53aWR0aAotICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1Ry
KCJWaWJlbWlzICUxIikuYXJnKFN5c3RlbVByb3BlcnRpZXMudmVyc2lvblN0cmluZykKKyAgICAg
ICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSAlMSIpLmFyZyhTeXN0ZW1Qcm9wZXJ0
aWVzLnZlcnNpb25TdHJpbmcpCiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBW
YlRva2Vucy50eXBlQm9keQogICAgICAgICAgICAgICAgICAgICBmb250LmJvbGQ6IHRydWUKICAg
ICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtNDA1OCw3ICs0MDc5LDcg
QEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBMYWJlbCB7CiAgICAgICAgICAgICAgICAgICAg
IHdpZHRoOiBwYXJlbnQud2lkdGgKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmli
ZW1pcyBpcyB0aGUgTGludXgvU3RlYW1PUyBjbGllbnQgZm9yIEFwb2xsbyAmIFN1bnNoaW5lIGhv
c3RzLiBUaGVzZSBvcGVuIGluIHlvdXIgYnJvd3Nlci4iKQorICAgICAgICAgICAgICAgICAgICB0
ZXh0OiBxc1RyKCJFY2xpcHNlIGlzIHRoZSBMaW51eC9TdGVhbU9TIGNsaWVudCBmb3IgQXBvbGxv
ICYgU3Vuc2hpbmUgaG9zdHMuIFRoZXNlIG9wZW4gaW4geW91ciBicm93c2VyLiIpCiAgICAgICAg
ICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQ2FwdGlvbgogICAgICAg
ICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKICAgICAgICAgICAg
ICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtNDA2Niw3ICs0MDg3LDcgQEAgSXRlbSB7
CiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgQnV0dG9uIHsKLSAgICAgICAg
ICAgICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBvbiBHaXRIdWIiKQorICAgICAgICAgICAg
ICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIG9uIEdpdEh1YiIpCiAgICAgICAgICAgICAgICAg
ICAgIG9uQ2xpY2tlZDogU3lzdGVtUHJvcGVydGllcy5vcGVuVXJsKCJodHRwczovL2dpdGh1Yi5j
b20vbmF2eWFzMzIxL3ZpYmVtaXMiKQogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAg
ICBCdXR0b24gewpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9TeXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5x
bWwgYi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9nLnFtbApuZXcgZmlsZSBtb2RlIDEw
MDY0NAppbmRleCAwMDAwMDAwLi5mMTFkMTI0Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9T
eXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwKQEAgLTAsMCArMSwxMTAgQEAKK2ltcG9ydCBRdFF1
aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlv
dXRzIDEuMworaW1wb3J0IFF0UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmli
ZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBTeXN0ZW1Db250cm9scyAxLjAKKworTmF2aWdhYmxl
RGlhbG9nIHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9wZXJ0eSBzdHJpbmcga2luZDogIndpZmki
CisgICAgcHJvcGVydHkgdmFyIHNlbGVjdGVkOiAoe30pCisgICAgd2lkdGg6IE1hdGgubWluKDYy
MCwgcGFyZW50LndpZHRoIC0gMzIpCisgICAgaGVpZ2h0OiBNYXRoLm1pbig1NjAsIHBhcmVudC5o
ZWlnaHQgLSAzMikKKyAgICB0aXRsZToga2luZCA9PT0gIndpZmkiID8gcXNUcigiV2ktRmkgbmV0
d29ya3MiKSA6IHFzVHIoIkJsdWV0b290aCBkZXZpY2VzIikKKyAgICBzdGFuZGFyZEJ1dHRvbnM6
IERpYWxvZy5DbG9zZQorICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgor
ICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAgYmFja2dyb3VuZDogUmVj
dGFuZ2xlIHsgY29sb3I6IFZiVG9rZW5zLmJnRWxldjsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNE
aWFsb2c7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlIH0KKyAgICBvbk9wZW5lZDogeyBz
ZWxlY3RlZCA9ICh7fSk7IFN5c3RlbUNvbnRyb2xzLm9wZW4oa2luZCkgfQorICAgIG9uQ2xvc2Vk
OiB7IGNyZWRlbnRpYWwuY2xvc2UoKTsgc2VjcmV0LnRleHQgPSAiIjsgZm9yZ2V0LmNsb3NlKCk7
IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCkgfQorICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQg
eworICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICAgICAgUm93TGF5b3V0IHsK
KyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgIExhYmVsIHsg
TGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dEZvcm1hdDog
VGV4dC5QbGFpblRleHQ7IHRleHQ6IFN5c3RlbUNvbnRyb2xzLnN0YXR1czsgY29sb3I6IFZiVG9r
ZW5zLnRleHREaW0gfQorICAgICAgICAgICAgQnVzeUluZGljYXRvciB7IHJ1bm5pbmc6IFN5c3Rl
bUNvbnRyb2xzLmJ1c3k7IHZpc2libGU6IHJ1bm5pbmc7IGltcGxpY2l0V2lkdGg6IDMyOyBpbXBs
aWNpdEhlaWdodDogMzIgfQorICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IGlkOiBz
Y2FuQnV0dG9uOyB0ZXh0OiBxc1RyKCJTY2FuIik7IGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5i
dXN5OyBvbkNsaWNrZWQ6IHsgcGFuZWwuc2VsZWN0ZWQgPSAoe30pOyBTeXN0ZW1Db250cm9scy5y
ZXF1ZXN0KHBhbmVsLmtpbmQgKyAiLXNjYW4iKSB9IH0KKyAgICAgICAgfQorICAgICAgICBFY2xp
cHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiQ2FuY2VsIG9wZXJhdGlvbiIpOyB2aXNpYmxl
OiBTeXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6IHsgU3lzdGVtQ29udHJvbHMuY2xvc2Uo
KTsgcGFuZWwuc2VsZWN0ZWQ9KHt9KTsgcmVvcGVuLnJlc3RhcnQoKSB9IH0KKyAgICAgICAgVGlt
ZXIgeyBpZDogcmVvcGVuOyBpbnRlcnZhbDogNjAwOyBvblRyaWdnZXJlZDogaWYocGFuZWwub3Bl
bmVkKSBTeXN0ZW1Db250cm9scy5vcGVuKHBhbmVsLmtpbmQpIH0KKyAgICAgICAgVGltZXIgeyBp
bnRlcnZhbDo1MDAwOyByZXBlYXQ6dHJ1ZTsgcnVubmluZzpwYW5lbC5vcGVuZWQgJiYgcGFuZWwu
a2luZD09PSJidCIgJiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3kgJiYgIWNyZWRlbnRpYWwub3BlbmVk
OyBvblRyaWdnZXJlZDpTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJidC1saXN0IikgfQorICAgICAg
ICBMYWJlbCB7CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTog
VGV4dC5XcmFwOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbQorICAgICAgICAgICAgdGV4dDogcGFu
ZWwua2luZCA9PT0gIndpZmkiID8gcXNUcigiU2VsZWN0IGEgbmV0d29yaywgdGhlbiBDb25uZWN0
LiBBZHZhbmNlZCBvciBoaWRkZW4gbmV0d29ya3MgYXJlIGF2YWlsYWJsZSBpbiB0aGUgZGlhZ25v
c3RpYyBzaGVsbC4iKSA6IHFzVHIoIlB1dCB5b3VyIGNvbnRyb2xsZXIgb3IgaGVhZHBob25lcyBp
biBwYWlyaW5nIG1vZGUsIHRoZW4gU2Nhbi4gRGV2aWNlcyBhcHBlYXIgZHVyaW5nIHNjYW5uaW5n
LiBTYXZlZCBkZXZpY2VzIGFyZSBsaXN0ZWQgd2l0aG91dCBzY2FubmluZy4iKQorICAgICAgICB9
CisgICAgICAgIExpc3RWaWV3IHsKKyAgICAgICAgICAgIGlkOiBkZXZpY2VzCisgICAgICAgICAg
ICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBMYXlvdXQuZmlsbEhlaWdodDogdHJ1ZQorICAgICAg
ICAgICAgY2xpcDogdHJ1ZTsgc3BhY2luZzogNDsgbW9kZWw6IFN5c3RlbUNvbnRyb2xzLml0ZW1z
CisgICAgICAgICAgICBTY3JvbGxCYXIudmVydGljYWw6IFNjcm9sbEJhciB7fQorICAgICAgICAg
ICAgZGVsZWdhdGU6IEl0ZW1EZWxlZ2F0ZSB7CisgICAgICAgICAgICAgICAgd2lkdGg6IGRldmlj
ZXMud2lkdGgKKyAgICAgICAgICAgICAgICBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeQor
ICAgICAgICAgICAgICAgIGhpZ2hsaWdodGVkOiBwYW5lbC5zZWxlY3RlZC5pZCA9PT0gbW9kZWxE
YXRhLmlkCisgICAgICAgICAgICAgICAgYWN0aXZlRm9jdXNPblRhYjogdHJ1ZQorICAgICAgICAg
ICAgICAgIEtleXMub25SZXR1cm5QcmVzc2VkOiBpZiAoZW5hYmxlZCkgY2xpY2tlZCgpCisgICAg
ICAgICAgICAgICAgS2V5cy5vbkVudGVyUHJlc3NlZDogaWYgKGVuYWJsZWQpIGNsaWNrZWQoKQor
ICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogeyBpZiAoaW5kZXggKyAxIDwgZGV2
aWNlcy5jb3VudCkgeyBkZXZpY2VzLmluY3JlbWVudEN1cnJlbnRJbmRleCgpOyBpZiAoZGV2aWNl
cy5jdXJyZW50SXRlbSkgZGV2aWNlcy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRh
YkZvY3VzKSB9IGVsc2UgaWYgKGNvbm5lY3RCdXR0b24uZW5hYmxlZCkgY29ubmVjdEJ1dHRvbi5m
b3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKTsgZWxzZSBzY2FuQnV0dG9uLmZvcmNlQWN0aXZl
Rm9jdXMoUXQuVGFiRm9jdXMpIH0KKyAgICAgICAgICAgICAgICBLZXlzLm9uVXBQcmVzc2VkOiB7
IGlmIChpbmRleCA+IDApIHsgZGV2aWNlcy5kZWNyZW1lbnRDdXJyZW50SW5kZXgoKTsgaWYgKGRl
dmljZXMuY3VycmVudEl0ZW0pIGRldmljZXMuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhR
dC5UYWJGb2N1cykgfSBlbHNlIHNjYW5CdXR0b24uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1
cykgfQorICAgICAgICAgICAgICAgIGNvbnRlbnRJdGVtOiBMYWJlbCB7CisgICAgICAgICAgICAg
ICAgICAgIHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0
OyBjb2xvcjogVmJUb2tlbnMudGV4dAorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBtb2RlbERh
dGEubmFtZSArICIgwrcgIiArIG1vZGVsRGF0YS5kZXRhaWwgKyAobW9kZWxEYXRhLmNvbm5lY3Rl
ZCA/ICIgwrcgIiArIHFzVHIoIkNvbm5lY3RlZCIpIDogIiIpCisgICAgICAgICAgICAgICAgfQor
ICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBwYW5lbC5zZWxlY3RlZCA9IG1vZGVsRGF0YTsg
ZGV2aWNlcy5jdXJyZW50SW5kZXggPSBpbmRleCB9CisgICAgICAgICAgICB9CisgICAgICAgIH0K
KyAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUK
KyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBj
b25uZWN0QnV0dG9uCisgICAgICAgICAgICAgICAgdGV4dDogcGFuZWwua2luZCA9PT0gIndpZmki
ID8gcXNUcigiQ29ubmVjdCIpIDogcXNUcigiUGFpciAvIENvbm5lY3QiKQorICAgICAgICAgICAg
ICAgIGVuYWJsZWQ6ICEhcGFuZWwuc2VsZWN0ZWQuaWQgJiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3kK
KyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QocGFuZWwu
a2luZCArICItY29ubmVjdCIsIHBhbmVsLnNlbGVjdGVkLmlkKQorICAgICAgICAgICAgfQorICAg
ICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7CisgICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiRGlzY29ubmVjdCIpOyBlbmFibGVkOiAhIXBhbmVsLnNlbGVjdGVkLmlkICYmIHBhbmVsLnNl
bGVjdGVkLmNvbm5lY3RlZCAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAgICAgICAgICAg
IG9uQ2xpY2tlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdChwYW5lbC5raW5kICsgIi1kaXNjb25u
ZWN0IiwgcGFuZWwuc2VsZWN0ZWQuaWQpCisgICAgICAgICAgICB9CisgICAgICAgICAgICBFY2xp
cHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiRm9yZ2V0Iik7IHZpc2libGU6IHBhbmVsLmtp
bmQgPT09ICJidCI7IGVuYWJsZWQ6ICEhcGFuZWwuc2VsZWN0ZWQuaWQgJiYgIVN5c3RlbUNvbnRy
b2xzLmJ1c3k7IG9uQ2xpY2tlZDogZm9yZ2V0Lm9wZW4oKSB9CisgICAgICAgIH0KKyAgICB9Cisg
ICAgQ29ubmVjdGlvbnMgeworICAgICAgICB0YXJnZXQ6IFN5c3RlbUNvbnRyb2xzCisgICAgICAg
IGZ1bmN0aW9uIG9uQ2hhbmdlZCgpIHsKKyAgICAgICAgICAgIGlmIChTeXN0ZW1Db250cm9scy5w
cm9tcHQubGVuZ3RoID4gMCAmJiBwYW5lbC5vcGVuZWQgJiYgIWNyZWRlbnRpYWwub3BlbmVkKSBj
cmVkZW50aWFsLm9wZW4oKQorICAgICAgICAgICAgaWYgKCFTeXN0ZW1Db250cm9scy5idXN5KSB7
CisgICAgICAgICAgICAgICAgY3JlZGVudGlhbC5jbG9zZSgpOyBzZWNyZXQudGV4dCA9ICIiCisg
ICAgICAgICAgICAgICAgdmFyIGlkID0gcGFuZWwuc2VsZWN0ZWQuaWQKKyAgICAgICAgICAgICAg
ICBwYW5lbC5zZWxlY3RlZCA9ICh7fSkKKyAgICAgICAgICAgICAgICBmb3IgKHZhciBpID0gMDsg
aSA8IFN5c3RlbUNvbnRyb2xzLml0ZW1zLmxlbmd0aDsgaSsrKQorICAgICAgICAgICAgICAgICAg
ICBpZiAoU3lzdGVtQ29udHJvbHMuaXRlbXNbaV0uaWQgPT09IGlkKSBwYW5lbC5zZWxlY3RlZCA9
IFN5c3RlbUNvbnRyb2xzLml0ZW1zW2ldCisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9
CisgICAgTmF2aWdhYmxlRGlhbG9nIHsKKyAgICAgICAgaWQ6IGNyZWRlbnRpYWwKKyAgICAgICAg
dGl0bGU6IHFzVHIoIkNvbm5lY3Rpb24gYXV0aGVudGljYXRpb24iKQorICAgICAgICB3aWR0aDog
TWF0aC5taW4oNDgwLCBwYW5lbC53aWR0aCkKKyAgICAgICAgY2xvc2VQb2xpY3k6IFBvcHVwLk5v
QXV0b0Nsb3NlCisgICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLk9rIHwgRGlhbG9nLkNh
bmNlbAorICAgICAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAg
ICAgb25PcGVuZWQ6IHsgc2VjcmV0LnRleHQgPSAiIjsgc2VjcmV0LmZvcmNlQWN0aXZlRm9jdXMo
KSB9CisgICAgICAgIG9uQWNjZXB0ZWQ6IHsgU3lzdGVtQ29udHJvbHMuYW5zd2VyKHNlY3JldC50
ZXh0KTsgc2VjcmV0LnRleHQgPSAiIiB9CisgICAgICAgIG9uUmVqZWN0ZWQ6IHsgc2VjcmV0LnRl
eHQgPSAiIjsgU3lzdGVtQ29udHJvbHMuY2xvc2UoKTsgcmVvcGVuLnJlc3RhcnQoKSB9CisgICAg
ICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgTGFiZWwgeyBMYXlv
dXQuZmlsbFdpZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6
IFRleHQuV3JhcDsgdGV4dDogU3lzdGVtQ29udHJvbHMucHJvbXB0OyBjb2xvcjogVmJUb2tlbnMu
dGV4dCB9CisgICAgICAgICAgICBUZXh0RmllbGQgeyBpZDogc2VjcmV0OyBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyBlY2hvTW9kZTogVGV4dElucHV0LlBhc3N3b3JkOyBtYXhpbXVtTGVuZ3RoOiA0
MDk2OyBzZWxlY3RCeU1vdXNlOiB0cnVlOyBvbkFjY2VwdGVkOiBjcmVkZW50aWFsLmFjY2VwdCgp
IH0KKyAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6
IFRleHQuV3JhcDsgdGV4dDogcXNUcigiRW50ZXIgdGhlIHJlcXVlc3RlZCBwYXNzd29yZCBvciBQ
SU4uIEZvciBhIHllcy9ubyBjb25maXJtYXRpb24sIHR5cGUgeWVzIG9yIG5vLiIpOyBjb2xvcjog
VmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgIH0KKyAgICB9CisgICAgTmF2aWdhYmxlRGlhbG9n
IHsKKyAgICAgICAgaWQ6IGZvcmdldAorICAgICAgICB0aXRsZTogcXNUcigiRm9yZ2V0IEJsdWV0
b290aCBkZXZpY2U/IikKKyAgICAgICAgd2lkdGg6IE1hdGgubWluKDQ4MCwgcGFuZWwud2lkdGgp
CisgICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLlllcyB8IERpYWxvZy5ObworICAgICAg
ICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAgICAgb25BY2NlcHRl
ZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiYnQtZm9yZ2V0IiwgcGFuZWwuc2VsZWN0ZWQuaWQs
IHRydWUpCisgICAgICAgIGNvbnRlbnRJdGVtOiBMYWJlbCB7IHRleHRGb3JtYXQ6IFRleHQuUGxh
aW5UZXh0OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJSZW1vdmUgdGhlIHNhdmVk
IHBhaXJpbmcgZm9yICUxPyBZb3Ugd2lsbCBuZWVkIHRvIHBhaXIgaXQgYWdhaW4uIikuYXJnKHBh
bmVsLnNlbGVjdGVkLm5hbWUgfHwgIiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dCB9CisgICAgfQor
fQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9UaGVtZS5xbWwgYi9hcHAvZ3VpL1RoZW1lLnFtbAppbmRl
eCBmYjkxYzg1Li41N2M5Zjg0IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1RoZW1lLnFtbAorKysgYi9h
cHAvZ3VpL1RoZW1lLnFtbApAQCAtMTEsMjAgKzExLDIwIEBAIGltcG9ydCBWaWJlbWlzLlJlZGVz
aWduIDEuMAogUXRPYmplY3QgewogICAgIC8vIC0tLS0gQ29sb3IgLS0tLQogICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAgICAgIFZiVG9rZW5zLmFjY2VudCAgLy8gQkwtMjA3
Nzogc2luZ2xlIHNvdXJjZSBvZiB0cnV0aCAoVmJUb2tlbnMgYnJhbmQgYWNjZW50LCBkZWZhdWx0
ICMwMENDQ0MpCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDogIiMw
MEEzQTMiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmFja2dyb3VuZDogICAgIiMzMDMw
MzAiICAvLyBhcHAgcm9vdAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZhY2U6ICAg
ICAgICIjMkQyRDJEIiAgLy8gcmFpc2VkIHN1cmZhY2VzIC8gb3ZlcmxheXMKLSAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBzdXJmYWNlQWx0OiAgICAiIzQyNDI0MiIgIC8vIHBvcHVwcyAvIGNv
bWJvIGRyb3Bkb3ducwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJvcmRlcjogICAgICAg
ICIjNDQ0NDQ0IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRQcmltYXJ5OiAgICIj
RkZGRkZGIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRTZWNvbmRhcnk6ICIjQ0ND
Q0NDIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRUZXJ0aWFyeTogICIjQUFBQUFB
IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHREaXNhYmxlZDogICIjNzc3Nzc3Igot
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1Y2Nlc3M6ICAgICAgICIjNENBRjUwIgotICAg
IHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHdhcm5pbmc6ICAgICAgICIjRTBBMDMwIiAgLy8gdGhl
IHNpbmdsZSBhbWJlcgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGVycm9yOiAgICAgICAg
ICIjRjQ0MzM2IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGluZm86ICAgICAgICAgICIj
ODBBMEMwIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHNjcmltOiAgICAgICAgICIjRDAw
MDAwMDAiCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDogVmJUb2tl
bnMuYWNjZW50UHJlc3NlZAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJhY2tncm91bmQ6
ICAgIFZiVG9rZW5zLmJnV2luZG93ICAvLyBhcHAgcm9vdAorICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIHN1cmZhY2U6ICAgICAgIFZiVG9rZW5zLmJnRWxldiAgLy8gcmFpc2VkIHN1cmZhY2Vz
IC8gb3ZlcmxheXMKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdXJmYWNlQWx0OiAgICBW
YlRva2Vucy5iZ0VsZXYyICAvLyBwb3B1cHMgLyBjb21ibyBkcm9wZG93bnMKKyAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBib3JkZXI6ICAgICAgICBWYlRva2Vucy5zdHJva2UKKyAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0UHJpbWFyeTogICBWYlRva2Vucy50ZXh0UHJpbWFyeQor
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRTZWNvbmRhcnk6IFZiVG9rZW5zLnRleHRT
ZWNvbmRhcnkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0VGVydGlhcnk6ICBWYlRv
a2Vucy50ZXh0VGVydGlhcnkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0RGlzYWJs
ZWQ6ICBWYlRva2Vucy50ZXh0RGlzYWJsZWQKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBz
dWNjZXNzOiAgICAgICBWYlRva2Vucy5zdGF0dXNTdWNjZXNzCisgICAgcmVhZG9ubHkgcHJvcGVy
dHkgY29sb3Igd2FybmluZzogICAgICAgVmJUb2tlbnMuc3RhdHVzV2FybmluZyAgLy8gdGhlIHNp
bmdsZSBhbWJlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGVycm9yOiAgICAgICAgIFZi
VG9rZW5zLnN0YXR1c0RhbmdlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGluZm86ICAg
ICAgICAgIFZiVG9rZW5zLnN0YXR1c0luZm8KKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBz
Y3JpbTogICAgICAgICBWYlRva2Vucy5kaWFsb2dTY3JpbQogCiAgICAgLy8gLS0tLSBUeXBvZ3Jh
cGh5IChwb2ludFNpemU7IHBhaXIgd2l0aCBib2xkIHdoZXJlIG5vdGVkIGluIERFU0lHTl9TWVNU
RU0ubWQpIC0tLS0KICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgZm9udERpc3BsYXk6IDI0ICAv
LyBvdmVybGF5L1F1aWNrIE1lbnUgdGl0bGUgKGJvbGQpCmRpZmYgLS1naXQgYS9hcHAvZ3VpL1Zi
Q2FyZC5xbWwgYi9hcHAvZ3VpL1ZiQ2FyZC5xbWwKaW5kZXggMzdmMmUzMi4uMWU5MGEwMiAxMDA2
NDQKLS0tIGEvYXBwL2d1aS9WYkNhcmQucW1sCisrKyBiL2FwcC9ndWkvVmJDYXJkLnFtbApAQCAt
MjcsNyArMjcsNyBAQCBJdGVtIHsKICAgICAgICAgYm9yZGVyLndpZHRoOiAxCiAgICAgICAgIGJv
cmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlCiAgICAgICAgIG9wYWNpdHk6IGNhcmQuY29udGVu
dE9wYWNpdHkKLSAgICAgICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xvckFuaW1hdGlvbiB7IGR1
cmF0aW9uOiAxMjAgfSB9CisgICAgICAgIEJlaGF2aW9yIG9uIGNvbG9yIHsgQ29sb3JBbmltYXRp
b24geyBkdXJhdGlvbjogVmJUb2tlbnMubW90aW9uRW5hYmxlZCA/IDEyMCA6IDAgfSB9CiAgICAg
fQogCiAgICAgSXRlbSB7CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1ZiU3RhdHVzUGlsbC5xbWwgYi9h
cHAvZ3VpL1ZiU3RhdHVzUGlsbC5xbWwKaW5kZXggODljNDc3MC4uYzcyOGYwNSAxMDA2NDQKLS0t
IGEvYXBwL2d1aS9WYlN0YXR1c1BpbGwucW1sCisrKyBiL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFt
bApAQCAtMjQsNyArMjQsNyBAQCBSZWN0YW5nbGUgewogICAgICAgICAgICAgY29sb3I6IHBpbGwu
b25saW5lID8gVmJUb2tlbnMuc3RhdHVzT25saW5lIDogVmJUb2tlbnMuc3RhdHVzT2ZmbGluZQog
ICAgICAgICAgICAgLy8gUHVsc2Ugb25seSB3aGVuIG9ubGluZS4KICAgICAgICAgICAgIFNlcXVl
bnRpYWxBbmltYXRpb24gb24gb3BhY2l0eSB7Ci0gICAgICAgICAgICAgICAgcnVubmluZzogcGls
bC5vbmxpbmUKKyAgICAgICAgICAgICAgICBydW5uaW5nOiBwaWxsLm9ubGluZSAmJiBWYlRva2Vu
cy5tb3Rpb25FbmFibGVkCiAgICAgICAgICAgICAgICAgbG9vcHM6IEFuaW1hdGlvbi5JbmZpbml0
ZQogICAgICAgICAgICAgICAgIE51bWJlckFuaW1hdGlvbiB7IGZyb206IDEuMDsgdG86IDAuNDU7
IGR1cmF0aW9uOiBWYlRva2Vucy5vbmxpbmVQdWxzZU1zIC8gMjsgZWFzaW5nLnR5cGU6IEVhc2lu
Zy5Jbk91dFNpbmUgfQogICAgICAgICAgICAgICAgIE51bWJlckFuaW1hdGlvbiB7IGZyb206IDAu
NDU7IHRvOiAxLjA7IGR1cmF0aW9uOiBWYlRva2Vucy5vbmxpbmVQdWxzZU1zIC8gMjsgZWFzaW5n
LnR5cGU6IEVhc2luZy5Jbk91dFNpbmUgfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9WYlRva2Vucy5x
bWwgYi9hcHAvZ3VpL1ZiVG9rZW5zLnFtbAppbmRleCA1MmEzNGRlLi5jYmY3OTg1IDEwMDY0NAot
LS0gYS9hcHAvZ3VpL1ZiVG9rZW5zLnFtbAorKysgYi9hcHAvZ3VpL1ZiVG9rZW5zLnFtbApAQCAt
MSw2ICsxLDcgQEAKIHByYWdtYSBTaW5nbGV0b24KIGltcG9ydCBRdFF1aWNrIDIuOQogaW1wb3J0
IFN0cmVhbWluZ1ByZWZlcmVuY2VzIDEuMAoraW1wb3J0IEVjbGlwc2VQcm9maWxlcyAxLjAKIAog
Ly8gVmliZW1pcyByZWRlc2lnbiBkZXNpZ24gdG9rZW5zLgogLy8gRGFyayB0aGVtZSBvbmx5LiBD
YW52YXMgMTkyMHgxMjAwIChMZWdpb24gR28gUyksCkBAIC05LDQzICsxMCw0NCBAQCBpbXBvcnQg
U3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCiBRdE9iamVjdCB7CiAgICAgaWQ6IHQKIAorICAgIHJl
YWRvbmx5IHByb3BlcnR5IHJlYWwgdGV4dFNjYWxlOiBFY2xpcHNlUHJvZmlsZXMudGV4dFNjYWxl
IC8gMTAwCisgICAgcmVhZG9ubHkgcHJvcGVydHkgYm9vbCBtb3Rpb25FbmFibGVkOiAhRWNsaXBz
ZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb24KKwogICAgIC8vIC0tLS0gQ29sb3IgLS0tLQotICAgIHJl
YWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnQXBwOiAgICAgICAgIiMwODA5MEIiICAvLyBvdXRlcm1v
c3QgYXBwIGJnIGJlaGluZCB0aGUgcm91bmRlZCB3aW5kb3cKLSAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciBiZ1dpbmRvdzogICAgICIjMEUxMDEzIiAgLy8gbWFpbiBzY3JlZW4gYmFja2dyb3Vu
ZAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxldjogICAgICAgIiMxNTE4MUQiICAv
LyBjYXJkcywgcGFuZWxzLCBkaWFsb2dzLCBzaWRlYmFyIHJvd3MKLSAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBiZ0VsZXYyOiAgICAgICIjMUIxRjI2IiAgLy8gZm9jdXNlZC9zZWxlY3RlZCBz
dXJmYWNlIGZpbGwsIGNoaXBzCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdGb290ZXI6
ICAgICAiIzBCMEQxMCIgIC8vIGJvdHRvbSBnYW1lcGFkIGhpbnQgYmFyCi0gICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3Igc3Ryb2tlOiAgICAgICBRdC5yZ2JhKDEsIDEsIDEsIDAuMDgpICAvLyBk
ZWZhdWx0IDFweCBjYXJkIGJvcmRlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnQXBw
OiAgICAgICAgIiMwNjA2MDciICAvLyBvdXRlcm1vc3QgYXBwIGJnIGJlaGluZCB0aGUgcm91bmRl
ZCB3aW5kb3cKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ1dpbmRvdzogICAgICIjMEIw
QjBFIiAgLy8gbWFpbiBzY3JlZW4gYmFja2dyb3VuZAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIGJnRWxldjogICAgICAgIiMxNTExMTUiICAvLyBjYXJkcywgcGFuZWxzLCBkaWFsb2dzLCBz
aWRlYmFyIHJvd3MKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0VsZXYyOiAgICAgICIj
MjExNzFDIiAgLy8gZm9jdXNlZC9zZWxlY3RlZCBzdXJmYWNlIGZpbGwsIGNoaXBzCisgICAgcmVh
ZG9ubHkgcHJvcGVydHkgY29sb3IgYmdGb290ZXI6ICAgICAiIzA5MDgwQiIgIC8vIGJvdHRvbSBn
YW1lcGFkIGhpbnQgYmFyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Ryb2tlOiAgICAg
ICBRdC5yZ2JhKDEsIDEsIDEsIEVjbGlwc2VQcm9maWxlcy5oaWdoQ29udHJhc3QgPyAwLjI1IDog
MC4wOCkgIC8vIGRlZmF1bHQgMXB4IGNhcmQgYm9yZGVyCiAgICAgcmVhZG9ubHkgcHJvcGVydHkg
Y29sb3Igc3Ryb2tlU29mdDogICBRdC5yZ2JhKDEsIDEsIDEsIDAuMDYpICAvLyBoZWFkZXIvZm9v
dGVyIGRpdmlkZXJzCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dDogICAgICAgICAi
I0VDRUVGMSIgIC8vIHByaW1hcnkgdGV4dAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRl
eHREaW06ICAgICAgIiM5OEExQUIiICAvLyBzZWNvbmRhcnkgLyBsYWJlbCB0ZXh0CisgICAgcmVh
ZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpbTogICAgICAoRWNsaXBzZVByb2ZpbGVzLmhpZ2hD
b250cmFzdCA/ICIjRDNENURDIiA6ICIjOThBMUFCIikgIC8vIHNlY29uZGFyeSAvIGxhYmVsIHRl
eHQKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0TXV0ZTogICAgICIjQjlDMEM4IiAg
Ly8gdGVydGlhcnkgLyBpbmFjdGl2ZSBpdGVtIGxhYmVscwogCi0gICAgLy8gQWNjZW50IGlzIHN3
YXBwYWJsZSDigJQgb25lIG9mIHRoZSA0IGN1cmF0ZWQgdmFsdWVzLiBJbmRleCAwIGlzIHRoZSBW
aWJlbWlzIGJyYW5kCi0gICAgLy8gdGVhbCAjMDBDQ0NDIChCTC0yMDc3KTogdGhlIHNpbmdsZSBj
YW5vbmljYWwgYWNjZW50IHRoYXQgVGhlbWUucW1sICsgYWxsIGxpdGVyYWxzIG5vdwotICAgIC8v
IHJlc29sdmUgdGhyb3VnaCwgYW5kIHRoZSBhbmNob3IgZm9yIHRoZSBQMy4xNy9QMy4xOCBkZXNp
Z24gd29yay4KLSAgICByZWFkb25seSBwcm9wZXJ0eSB2YXIgYWNjZW50T3B0aW9uczogIFsiIzAw
Q0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1OTgiLCAiI0YwQTg2OCJdCisgICAgLy8gUHJlc2VydmUg
bGVnYWN5IGluZGljZXMgMC4uMzsgYXBwZW5kIGNvbG9ycyBhbmQgZGVmYXVsdCBuZXcgcHJlZmVy
ZW5jZXMgdG8gY3JpbXNvbi4KKyAgICByZWFkb25seSBwcm9wZXJ0eSB2YXIgYWNjZW50T3B0aW9u
czogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1OTgiLCAiI0YwQTg2OCIsICIjREMzNjU4
IiwgIiNGMjVENjQiLCAiI0Y1ODM0NyIsICIjRjFCQzQ1IiwgIiNCN0RDNjMiLCAiIzYzQ0NBRSIs
ICIjNjNDNEVEIiwgIiM2QzlGRkYiLCAiI0FEODVGNSIsICIjRTk3NkJDIiwgIiNDQUQwREEiLCAi
I0Q5OTVBQyJdCiAgICAgLy8gQm91bmQgdG8gdGhlIHNhdmVkIHByZWZlcmVuY2UgKFNldHRpbmdz
ID4gYWNjZW50IHBpY2tlcik7IHBlcnNpc3RzIGFjcm9zcyByZXN0YXJ0cy4KICAgICBwcm9wZXJ0
eSBpbnQgYWNjZW50SW5kZXg6IFN0cmVhbWluZ1ByZWZlcmVuY2VzLnVpQWNjZW50SW5kZXgKLSAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnQ6ICAgICAgIGFjY2VudE9wdGlvbnNbYWNj
ZW50SW5kZXhdCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50SGk6ICAgICAiIzZB
RERFNyIgIC8vIGFjY2VudCBncmFkaWVudCBsaWdodCBzdG9wIC8gbGluayBob3ZlcgorICAgIHJl
YWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAgICAgYWNjZW50T3B0aW9uc1tNYXRoLm1h
eCgwLCBNYXRoLm1pbihhY2NlbnRPcHRpb25zLmxlbmd0aCAtIDEsIGFjY2VudEluZGV4KSldCisg
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50SGk6ICAgICBRdC5saWdodGVyKGFjY2Vu
dCwgMS4xOCkgIC8vIGFjY2VudCBncmFkaWVudCBsaWdodCBzdG9wIC8gbGluayBob3ZlcgogCiAg
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3RhdHVzT25saW5lOiAgIiMzRUQ1OTgiICAvLyBv
bmxpbmUgZG90LCBSRVNVTUUgYmFkZ2UKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdGF0
dXNPZmZsaW5lOiAiIzVBNjI2QyIgIC8vIG9mZmxpbmUgZG90IC8gZ3JleWVkIG1vbml0b3IKICAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNEYW5nZXI6ICAiI0YyNkQ2RCIgIC8vIGRl
c3RydWN0aXZlIChEZWxldGUgUEMpCiAKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0
T25BY2NlbnQ6ICIjMDgwOTBCIiAgLy8gdGV4dCBvbiBhbiBhY2NlbnQtZmlsbGVkIGJ1dHRvbgor
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRPbkFjY2VudDogIiMwNjA2MDciICAvLyB0
ZXh0IG9uIGFuIGFjY2VudC1maWxsZWQgYnV0dG9uCiAKICAgICAvLyAtLS0tIFR5cG9ncmFwaHkg
KGZhbWlsaWVzICsgc2l6ZXM7IHdlaWdodHMgcGVyIHRoZSB0eXBlIHNjYWxlKSAtLS0tCiAgICAg
cmVhZG9ubHkgcHJvcGVydHkgc3RyaW5nIGZvbnREaXNwbGF5OiAiU29yYSIgICAgIC8vIHRpdGxl
cywgY2FyZCBuYW1lcywgd29yZG1hcmssIGFsbC1jYXBzIGxhYmVscwogICAgIHJlYWRvbmx5IHBy
b3BlcnR5IHN0cmluZyBmb250Qm9keTogICAgIk1hbnJvcGUiICAvLyBib2R5ICsgVUkgdGV4dAot
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2NyZWVuVGl0bGU6ICAzNAotICAgIHJlYWRv
bmx5IHByb3BlcnR5IGludCBzaXplU2VjdGlvblRpdGxlOiAyOAotICAgIHJlYWRvbmx5IHByb3Bl
cnR5IGludCBzaXplQ2FyZE5hbWU6ICAgICAyNwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBz
aXplQm9keTogICAgICAgICAxNgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplTGFiZWw6
ICAgICAgICAxNAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplQmFkZ2U6ICAgICAgICAx
MwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplV29yZG1hcms6ICAgICAyMQorICAgIHJl
YWRvbmx5IHByb3BlcnR5IGludCBzaXplU2NyZWVuVGl0bGU6ICBNYXRoLnJvdW5kKDM0ICogdGV4
dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2VjdGlvblRpdGxlOiBNYXRo
LnJvdW5kKDI4ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplQ2Fy
ZE5hbWU6ICAgICBNYXRoLnJvdW5kKDI3ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3Bl
cnR5IGludCBzaXplQm9keTogICAgICAgICBNYXRoLnJvdW5kKDE2ICogdGV4dFNjYWxlKQorICAg
IHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplTGFiZWw6ICAgICAgICBNYXRoLnJvdW5kKDE0ICog
dGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplQmFkZ2U6ICAgICAgICBN
YXRoLnJvdW5kKDEzICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXpl
V29yZG1hcms6ICAgICBNYXRoLnJvdW5kKDIxICogdGV4dFNjYWxlKQogICAgIHJlYWRvbmx5IHBy
b3BlcnR5IHJlYWwgd29yZG1hcmtTcGFjaW5nOiAzLjAKICAgICByZWFkb25seSBwcm9wZXJ0eSBy
ZWFsIGJhZGdlU3BhY2luZzogICAgMS4yCiAKQEAgLTgzLDcgKzg1LDcgQEAgUXRPYmplY3Qgewog
ICAgIC8vIC0tLS0gTW90aW9uIChtcykgLS0tLQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBv
bmxpbmVQdWxzZU1zOiAyNDAwICAgLy8gb3BhY2l0eSAxIC0+IDAuNDUgLT4gMSwgaW5maW5pdGUK
ICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgY2FyZXRCbGlua01zOiAgMTAwMCAgIC8vIEFkZC1Q
QyBpbnB1dCBjYXJldAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaGVldEluTXM6ICAgICAy
MjAgICAgLy8gc2lkZS1zaGVldCBzbGlkZS1pbgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBz
aGVldEluTXM6ICAgICBtb3Rpb25FbmFibGVkID8gMjIwIDogMCAgICAvLyBzaWRlLXNoZWV0IHNs
aWRlLWluCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZGlhbG9nU2NyaW06IFF0LnJnYmEo
NC8yNTUsIDUvMjU1LCA3LzI1NSwgMC43MikKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBz
aGVldFNjcmltOiAgUXQucmdiYSg0LzI1NSwgNS8yNTUsIDcvMjU1LCAwLjYwKQogCkBAIC0xMTks
NyArMTIxLDcgQEAgUXRPYmplY3QgewogICAgIC8vIHRleHRPbkFjY2VudCAoIzA4MDkwQikgaXMg
ZGVmaW5lZCBpbiB0aGUgYmFzZSBibG9jayBhYm92ZSDigJQgdGV4dCBvbiBhbiBhY2NlbnQgZmls
bC4KIAogICAgIC8vIC0tLS0gSW50ZXJhY3RpdmUgc3RhdGVzOiBub3JtYWwgLyBob3ZlciAvIGZv
Y3VzIC8gcHJlc3NlZCAvIGRpc2FibGVkIC0tLS0KLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xv
ciBhY2NlbnRQcmVzc2VkOiAgICAgICIjMDBBM0EzIiAvLyBwcmVzc2VkIGFjY2VudGVkIGNvbnRy
b2wgKG1hdGNoZXMgbGVnYWN5IFRoZW1lLmFjY2VudFByZXNzZWQpCisgICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDogICAgICBRdC5kYXJrZXIoYWNjZW50LCAxLjE4KSAv
LyBwcmVzc2VkIGFjY2VudGVkIGNvbnRyb2wgKG1hdGNoZXMgbGVnYWN5IFRoZW1lLmFjY2VudFBy
ZXNzZWQpCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW50ZXJhY3RpdmVIb3ZlcjogICBi
Z0VsZXYyICAgIC8vIHJvdyAvIGxpc3QtaXRlbSAvIGljb24tYnV0dG9uIGhvdmVyIGZpbGwKICAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZUZvY3VzOiAgIGZvY3VzZWRGaWxs
Ly8gZm9jdXNlZCBmaWxsICg9IGJnRWxldjIpIOKAlCBwYWlyIHdpdGggdGhlIGZvY3VzIHJpbmcK
ICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZVByZXNzZWQ6IGJnRWxldiAg
ICAgLy8gcHJlc3NlZCBuZXV0cmFsIGZpbGwgKHJlY2VkZXMgdW5kZXIgdGhlIHByZXNzKQpkaWZm
IC0tZ2l0IGEvYXBwL2d1aS9WYldlbGNvbWVTaGVldC5xbWwgYi9hcHAvZ3VpL1ZiV2VsY29tZVNo
ZWV0LnFtbAppbmRleCAxNzMxMTliLi40MzgzY2IwIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiV2Vs
Y29tZVNoZWV0LnFtbAorKysgYi9hcHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFtbApAQCAtMTA4LDE0
ICsxMDgsMTMgQEAgTmF2aWdhYmxlRGlhbG9nIHsKICAgICAgICAgICAgIHNwYWNpbmc6IFZiVG9r
ZW5zLnNwYWNlMiAgLy8gOAogICAgICAgICAgICAgUm93TGF5b3V0IHsKICAgICAgICAgICAgICAg
ICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTIKLSAgICAgICAgICAgICAgICBSZWN0YW5nbGUgewot
ICAgICAgICAgICAgICAgICAgICB3aWR0aDogMTM7IGhlaWdodDogMTMKLSAgICAgICAgICAgICAg
ICAgICAgY29sb3I6IFZiVG9rZW5zLmFjY2VudAotICAgICAgICAgICAgICAgICAgICByb3RhdGlv
bjogNDUKKyAgICAgICAgICAgICAgICBJbWFnZSB7CisgICAgICAgICAgICAgICAgICAgIHNvdXJj
ZTogInFyYzovcmVzL2VjbGlwc2UtaWNvbi5zdmciCisgICAgICAgICAgICAgICAgICAgIExheW91
dC5wcmVmZXJyZWRXaWR0aDogMjg7IExheW91dC5wcmVmZXJyZWRIZWlnaHQ6IDI4CiAgICAgICAg
ICAgICAgICAgICAgIExheW91dC5hbGlnbm1lbnQ6IFF0LkFsaWduVkNlbnRlcgogICAgICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgICAgICBUZXh0IHsKLSAgICAgICAgICAgICAgICAgICAgdGV4
dDogIlZJQkVNSVMiCisgICAgICAgICAgICAgICAgICAgIHRleHQ6ICJFQ0xJUFNFIgogICAgICAg
ICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udERpc3BsYXkKICAgICAgICAg
ICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZvbnQuRXh0cmFCb2xkCiAgICAgICAgICAgICAgICAg
ICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy5zaXplV29yZG1hcmsgICAgICAvLyAyMQpAQCAt
MTI1LDcgKzEyNCw3IEBAIE5hdmlnYWJsZURpYWxvZyB7CiAgICAgICAgICAgICAgICAgfQogICAg
ICAgICAgICAgfQogICAgICAgICAgICAgVGV4dCB7Ci0gICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiV2VsY29tZSB0byBWaWJlbWlzIikKKyAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJXZWxj
b21lIHRvIEVjbGlwc2UiKQogICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5m
b250RGlzcGxheQogICAgICAgICAgICAgICAgIGZvbnQud2VpZ2h0OiBGb250LkJvbGQKICAgICAg
ICAgICAgICAgICBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZURpc3BsYXkgICAgICAgICAg
IC8vIDM0CkBAIC0xOTUsNyArMTk0LDcgQEAgTmF2aWdhYmxlRGlhbG9nIHsKICAgICAgICAgICAg
IEluZm9Sb3cgewogICAgICAgICAgICAgICAgIGdseXBoOiAiYXBwcyIKICAgICAgICAgICAgICAg
ICB0aXRsZTogcXNUcigiQWRkIHRvIFN0ZWFtIikKLSAgICAgICAgICAgICAgICBzdWI6IHFzVHIo
Ik9uIFN0ZWFtIERlY2sgLyBTdGVhbU9TLCBhZGQgVmliZW1pcyB0byBTdGVhbSBmcm9tIERlc2t0
b3AgTW9kZSBzbyBpdCBhcHBlYXJzIGluIEdhbWUgTW9kZS4iKQorICAgICAgICAgICAgICAgIHN1
YjogcXNUcigiT24gU3RlYW0gRGVjayAvIFN0ZWFtT1MsIGFkZCBFY2xpcHNlIHRvIFN0ZWFtIGZy
b20gRGVza3RvcCBNb2RlIHNvIGl0IGFwcGVhcnMgaW4gR2FtZSBNb2RlLiIpCiAgICAgICAgICAg
ICB9CiAKICAgICAgICAgICAgIC8vIDMpIFNldHRpbmdzLgpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9j
b21wdXRlcm1vZGVsLmNwcCBiL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5jcHAKaW5kZXggNjNjNzEx
NS4uMmQ0ODdmZiAxMDA2NDQKLS0tIGEvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmNwcAorKysgYi9h
cHAvZ3VpL2NvbXB1dGVybW9kZWwuY3BwCkBAIC0xLDMgKzEsNCBAQAorI2luY2x1ZGUgPFFVcmw+
CiAjaW5jbHVkZSAiY29tcHV0ZXJtb2RlbC5oIgogI2luY2x1ZGUgImJhY2tlbmQvc2VydmVycGVy
bWlzc2lvbnMuaCIKICNpbmNsdWRlICJzZXR0aW5ncy92aWJlbWlzc2V0dGluZ3MuaCIKQEAgLTQy
MCwzICs0MjEsMTMgQEAgdm9pZCBDb21wdXRlck1vZGVsOjpoYW5kbGVDb21wdXRlclN0YXRlQ2hh
bmdlZChOdkNvbXB1dGVyKiBjb21wdXRlcikKIH0KIAogI2luY2x1ZGUgImNvbXB1dGVybW9kZWwu
bW9jIgorCitRVmFyaWFudE1hcCBDb21wdXRlck1vZGVsOjpjcmltc29uSG9zdChpbnQgaW5kZXgp
IGNvbnN0Cit7CisgICAgaWYgKGluZGV4IDwgMCB8fCBpbmRleCA+PSBtX0NvbXB1dGVycy5jb3Vu
dCgpKSByZXR1cm4ge307CisgICAgYXV0byBjb21wdXRlciA9IG1fQ29tcHV0ZXJzW2luZGV4XTsK
KyAgICBRUmVhZExvY2tlciBsb2NrKCZjb21wdXRlci0+bG9jayk7CisgICAgUVVybCB1cmw7IHVy
bC5zZXRTY2hlbWUoImh0dHBzIik7IHVybC5zZXRIb3N0KGNvbXB1dGVyLT5hY3RpdmVBZGRyZXNz
LmFkZHJlc3MoKSk7CisgICAgdXJsLnNldFBvcnQoY29tcHV0ZXItPmFjdGl2ZUFkZHJlc3MucG9y
dCgpID4gMCA/IGNvbXB1dGVyLT5hY3RpdmVBZGRyZXNzLnBvcnQoKSArIDEgOiA0Nzk5MCk7Cisg
ICAgcmV0dXJuIHt7ImlkIiwgY29tcHV0ZXItPnV1aWR9LCB7InVybCIsIHVybC50b1N0cmluZygp
fX07Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuaCBiL2FwcC9ndWkvY29t
cHV0ZXJtb2RlbC5oCmluZGV4IDZlY2FlMzAuLjJlZTczYzEgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkv
Y29tcHV0ZXJtb2RlbC5oCisrKyBiL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5oCkBAIC00Myw2ICs0
Myw4IEBAIHB1YmxpYzoKIAogICAgIHZpcnR1YWwgUUhhc2g8aW50LCBRQnl0ZUFycmF5PiByb2xl
TmFtZXMoKSBjb25zdCBvdmVycmlkZTsKIAorICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50TWFwIGNy
aW1zb25Ib3N0KGludCBjb21wdXRlckluZGV4KSBjb25zdDsKKwogICAgIFFfSU5WT0tBQkxFIHZv
aWQgZGVsZXRlQ29tcHV0ZXIoaW50IGNvbXB1dGVySW5kZXgpOwogCiAgICAgUV9JTlZPS0FCTEUg
UVN0cmluZyBnZW5lcmF0ZVBpblN0cmluZygpOwpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9tYWluLnFt
bCBiL2FwcC9ndWkvbWFpbi5xbWwKaW5kZXggOWJjZTUxMC4uODQ4ZmMxNCAxMDA2NDQKLS0tIGEv
YXBwL2d1aS9tYWluLnFtbAorKysgYi9hcHAvZ3VpL21haW4ucW1sCkBAIC0xMiw4ICsxMiwyNSBA
QCBpbXBvcnQgU3lzdGVtUHJvcGVydGllcyAxLjAKIGltcG9ydCBTZGxHYW1lcGFkS2V5TmF2aWdh
dGlvbiAxLjAKIGltcG9ydCBVaVNvdW5kTWFuYWdlciAxLjAKIGltcG9ydCBUaGVtZSAxLjAKK2lt
cG9ydCBDcmltc29uU3RhdHVzIDEuMAoraW1wb3J0IFN5c3RlbUNvbnRyb2xzIDEuMAogCiBBcHBs
aWNhdGlvbldpbmRvdyB7CisgICAgTWF0ZXJpYWwudGhlbWU6IE1hdGVyaWFsLkRhcmsKKyAgICBN
YXRlcmlhbC5hY2NlbnQ6IFZiVG9rZW5zLmFjY2VudAorICAgIE1hdGVyaWFsLnByaW1hcnk6IFZi
VG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnV2luZG93
CisgICAgTWF0ZXJpYWwuZm9yZWdyb3VuZDogVmJUb2tlbnMudGV4dAorICAgIGNvbG9yOiBWYlRv
a2Vucy5iZ0FwcAorICAgIHBhbGV0dGUud2luZG93OiBWYlRva2Vucy5iZ1dpbmRvdworICAgIHBh
bGV0dGUud2luZG93VGV4dDogVmJUb2tlbnMudGV4dAorICAgIHBhbGV0dGUuYmFzZTogVmJUb2tl
bnMuYmdBcHAKKyAgICBwYWxldHRlLmFsdGVybmF0ZUJhc2U6IFZiVG9rZW5zLmJnRWxldgorICAg
IHBhbGV0dGUudGV4dDogVmJUb2tlbnMudGV4dAorICAgIHBhbGV0dGUuYnV0dG9uOiBWYlRva2Vu
cy5iZ0VsZXYKKyAgICBwYWxldHRlLmJ1dHRvblRleHQ6IFZiVG9rZW5zLnRleHQKKyAgICBwYWxl
dHRlLmhpZ2hsaWdodDogVmJUb2tlbnMuYWNjZW50CisgICAgcGFsZXR0ZS5oaWdobGlnaHRlZFRl
eHQ6IFZiVG9rZW5zLnRleHRPbkFjY2VudAogICAgIHByb3BlcnR5IGJvb2wgcG9sbGluZ0FjdGl2
ZTogZmFsc2UKIAogICAgIC8vIFNldCBieSBTZXR0aW5nc1ZpZXcgdG8gZm9yY2UgdGhlIGJhY2sg
b3BlcmF0aW9uIHRvIHBvcCBhbGwKQEAgLTQ2LDE0ICs2MywxMyBAQCBBcHBsaWNhdGlvbldpbmRv
dyB7CiAgICAgICAgIC8vIGluIG9yZGVyIHRvIGltcHJvdmUgY29udHJhc3QgYmV0d2VlbiBHRkUn
cyBwbGFjZWhvbGRlciBib3ggYXJ0CiAgICAgICAgIC8vIGFuZCB0aGUgYmFja2dyb3VuZCBvZiB0
aGUgYXBwIGdyaWQuCiAgICAgICAgIGlmIChTeXN0ZW1Qcm9wZXJ0aWVzLnVzZXNNYXRlcmlhbDNU
aGVtZSkgewotICAgICAgICAgICAgTWF0ZXJpYWwuYmFja2dyb3VuZCA9IFRoZW1lLmJhY2tncm91
bmQKKyAgICAgICAgICAgIC8vIFRoZW1lIHJlbWFpbnMgYSBsaXZlIGJpbmRpbmcgdG8gdGhlIHNo
YXJlZCBwYWxldHRlLgogICAgICAgICB9CiAKICAgICAgICAgLy8gQnJpZGdlIHRoZSBNYXRlcmlh
bCBzdHlsZSB0byB0aGUgVmliZW1pcyBkZXNpZ24gdG9rZW5zIHNvIHRoZQogICAgICAgICAvLyBN
YXRlcmlhbC1zdHlsZWQgcGFnZXMgKENvbXB1dGVycyBncmlkLCBBcHAgZ3JpZCwgZGlhbG9ncykg
c2hhcmUgdGhlIHNhbWUKICAgICAgICAgLy8gYWNjZW50L2JhY2tncm91bmQgc3lzdGVtIGFzIHRo
ZSB0b2tlbi1uYXRpdmUgcGFnZXMuIFNlZSBkb2NzL0RFU0lHTl9TWVNURU0ubWQuCi0gICAgICAg
IE1hdGVyaWFsLnRoZW1lID0gTWF0ZXJpYWwuRGFyawotICAgICAgICBNYXRlcmlhbC5hY2NlbnQg
PSBUaGVtZS5hY2NlbnQKKyAgICAgICAgLy8gTWF0ZXJpYWwgdGhlbWUvYWNjZW50IGFyZSBib3Vu
ZCBhdCB0aGUgcm9vdCwgaW5jbHVkaW5nIGFmdGVyIGNoYW5nZXMuCiAKICAgICAgICAgU2RsR2Ft
ZXBhZEtleU5hdmlnYXRpb24uZW5hYmxlKCkKICAgICB9CkBAIC0yNjcsNiArMjgzLDI1IEBAIEFw
cGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgfQogICAgIH0KIAorICAgIENyaW1zb25TdGF0dXNE
aWFsb2cgeyBpZDogY3JpbXNvblBhbmVsIH0KKyAgICBTeXN0ZW1Db25uZWN0aW9uc0RpYWxvZyB7
IGlkOiBjb25uZWN0aW9uUGFuZWwgfQorICAgIEVjbGlwc2VBYm91dERpYWxvZyB7IGlkOiBlY2xp
cHNlQWJvdXQgfQorICAgIEVjbGlwc2VDb250cm9sQ2VudGVyIHsKKyAgICAgICAgaWQ6IGVjbGlw
c2VDZW50ZXIKKyAgICAgICAgY2FuTWFuYWdlOiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIK
KyAgICAgICAgY2FuV2FrZTogdG9vbEJhci5vblBjVmlldworICAgICAgICBvbldha2VSZXF1ZXN0
ZWQ6IHsKKyAgICAgICAgICAgIGlmICh0b29sQmFyLm9uUGNWaWV3KSBzdGFja1ZpZXcuY3VycmVu
dEl0ZW0uY29tcHV0ZXJNb2RlbC53YWtlQ29tcHV0ZXIoc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmN1
cnJlbnRJbmRleCkKKyAgICAgICAgfQorICAgICAgICBvbk5hdmlnYXRlUmVxdWVzdGVkOiB7Cisg
ICAgICAgICAgICBpZiAoZGVzdGluYXRpb24gPT09ICJ3aWZpIiB8fCBkZXN0aW5hdGlvbiA9PT0g
ImJ0IikgeyBjb25uZWN0aW9uUGFuZWwua2luZCA9IGRlc3RpbmF0aW9uOyBjb25uZWN0aW9uUGFu
ZWwub3BlbigpIH0KKyAgICAgICAgICAgIGVsc2UgaWYgKGRlc3RpbmF0aW9uID09PSAic2V0dGlu
Z3MiKSBuYXZpZ2F0ZVRvKCJxcmM6L2d1aS9TZXR0aW5nc1ZpZXcucW1sIiwgIlNldHRpbmdzVmll
dyIpCisgICAgICAgICAgICBlbHNlIGlmIChkZXN0aW5hdGlvbiA9PT0gImhvc3QiKSB7IENyaW1z
b25TdGF0dXMuc2VsZWN0SG9zdChlY2xpcHNlQ2VudGVyLmhvc3QuaWQgfHwgIiIsIGVjbGlwc2VD
ZW50ZXIuaG9zdC51cmwgfHwgIiIpOyBjcmltc29uUGFuZWwua2luZCA9ICJob3N0IjsgY3JpbXNv
blBhbmVsLm9wZW4oKSB9CisgICAgICAgICAgICBlbHNlIGlmIChkZXN0aW5hdGlvbiA9PT0gImFi
b3V0IikgeyBlY2xpcHNlQWJvdXQuaW5mbyA9IFN5c3RlbUNvbnRyb2xzLnN0YXRlOyBlY2xpcHNl
QWJvdXQub3BlbigpIH0KKyAgICAgICAgICAgIGVsc2UgaWYgKGRlc3RpbmF0aW9uID09PSAibWFu
YWdlbWVudCIgJiYgU3lzdGVtUHJvcGVydGllcy5oYXNCcm93c2VyKSBTeXN0ZW1Qcm9wZXJ0aWVz
Lm9wZW5VcmwoZWNsaXBzZUNlbnRlci5ob3N0LnVybCkKKyAgICAgICAgfQorICAgIH0KKwogICAg
IGhlYWRlcjogVG9vbEJhciB7CiAgICAgICAgIGlkOiB0b29sQmFyCiAgICAgICAgIC8vIFJlZGVz
aWduOiBFVkVSWSByZWRlc2lnbmVkIGxhdW5jaGVyIHNjcmVlbiAoQ29tcHV0ZXJzLCBBcHAgZ3Jp
ZCwgU2V0dGluZ3MsIEhlbHApCkBAIC0zMzgsMjAgKzM3MywxOSBAQCBBcHBsaWNhdGlvbldpbmRv
dyB7CiAgICAgICAgIC8vIFZJQkVNSVMgd29yZG1hcmsgKGRpYW1vbmQgKyB3b3JkbWFyayksIHNo
b3duIG9uIHRoZSBDb21wdXRlcnMgc2NyZWVuIGluIHBsYWNlIG9mIGEgdGl0bGUsCiAgICAgICAg
IC8vIG1hdGNoaW5nIHRoZSBkZXNpZ24gaGVhZGVyLiBMZWZ0LWFsaWduZWQgYXQgdGhlIEhUTUwn
cyA0MHB4IHBhZGRpbmcuCiAgICAgICAgIFJvdyB7Ci0gICAgICAgICAgICB2aXNpYmxlOiB0b29s
QmFyLm9uUGNWaWV3CisgICAgICAgICAgICB2aXNpYmxlOiB0b29sQmFyLm9uUGNWaWV3ICYmIHRv
b2xCYXIud2lkdGggPiA4MjAKICAgICAgICAgICAgIGFuY2hvcnMubGVmdDogcGFyZW50LmxlZnQK
ICAgICAgICAgICAgIGFuY2hvcnMubGVmdE1hcmdpbjogNDAKICAgICAgICAgICAgIGFuY2hvcnMu
dmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlcgogICAgICAgICAgICAgc3BhY2lu
ZzogMTEKLSAgICAgICAgICAgIFJlY3RhbmdsZSB7CisgICAgICAgICAgICBJbWFnZSB7CiAgICAg
ICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVy
Ci0gICAgICAgICAgICAgICAgd2lkdGg6IDEzOyBoZWlnaHQ6IDEzCi0gICAgICAgICAgICAgICAg
Y29sb3I6IFZiVG9rZW5zLmFjY2VudAotICAgICAgICAgICAgICAgIHJvdGF0aW9uOiA0NQorICAg
ICAgICAgICAgICAgIHdpZHRoOiAyODsgaGVpZ2h0OiAyOAorICAgICAgICAgICAgICAgIHNvdXJj
ZTogInFyYzovcmVzL2VjbGlwc2UtaWNvbi5zdmciCiAgICAgICAgICAgICB9CiAgICAgICAgICAg
ICBUZXh0IHsKICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQu
dmVydGljYWxDZW50ZXIKLSAgICAgICAgICAgICAgICB0ZXh0OiAiVklCRU1JUyIKKyAgICAgICAg
ICAgICAgICB0ZXh0OiAiRUNMSVBTRSIKICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJU
b2tlbnMuZm9udERpc3BsYXkKICAgICAgICAgICAgICAgICBmb250LndlaWdodDogRm9udC5FeHRy
YUJvbGQKICAgICAgICAgICAgICAgICBmb250LnBpeGVsU2l6ZTogMjEKQEAgLTM2NSw3ICszOTks
NyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgICAgICAvLyBIaWRkZW4gb24gQ29tcHV0
ZXJzICh0aGUgd29yZG1hcmsgc3RhbmRzIGluKSBhbmQgb24gdGhlIEFwcCBncmlkICh3aGljaCBz
aG93cyBhCiAgICAgICAgICAgICAvLyBsZWZ0LWFsaWduZWQgaG9zdCArIHN0YXR1cyBibG9jayBp
bnN0ZWFkKS4gT24gU2V0dGluZ3MvSGVscCBpdCBzaG93cyB0aGUgc2NyZWVuIG5hbWU7CiAgICAg
ICAgICAgICAvLyB0aGUgc3RyZWFtaW5nIHNlZ3VlcyBrZWVwIHRoZWlyIGRlZmF1bHQgb2JqZWN0
TmFtZSB0aXRsZS4KLSAgICAgICAgICAgIHZpc2libGU6ICF0b29sQmFyLm9uUGNWaWV3ICYmICF0
b29sQmFyLm9uQXBwVmlldyAmJiB0b29sQmFyLndpZHRoID4gNzAwCisgICAgICAgICAgICB2aXNp
YmxlOiAhdG9vbEJhci5vblBjVmlldyAmJiAhdG9vbEJhci5vbkFwcFZpZXcgJiYgdG9vbEJhci53
aWR0aCA+IDgyMAogICAgICAgICAgICAgYW5jaG9ycy5maWxsOiBwYXJlbnQKICAgICAgICAgICAg
IHRleHQ6IHRvb2xCYXIub25TZXR0aW5ncyA/IHFzVHIoIlNldHRpbmdzIikKICAgICAgICAgICAg
ICAgICA6IHRvb2xCYXIub25IZWxwID8gcXNUcigiSGVscCIpCkBAIC00ODcsNiArNTIxLDU0IEBA
IEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAK
KyAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBu
ZXR3b3JrU3RhdHVzQnV0dG9uCisgICAgICAgICAgICAgICAgaWNvblNvdXJjZTogInFyYzovcmVz
L2NyaW1zb24tbmV0d29yay5zdmciCisgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBx
c1RyKCJXaS1GaSBzZXR0aW5ncyIpCisgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBo
b3ZlcmVkCisgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJOZXR3b3JrOiAlMSIp
LmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLm5ldHdvcmsgfHwgcXNUcigiVW5hdmFpbGFibGUiKSkK
KyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsgY29ubmVjdGlvblBhbmVsLmtpbmQgPSAid2lm
aSI7IGNvbm5lY3Rpb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3du
UHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9j
dXMpCisgICAgICAgICAgICAgICAgUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgICAgICAgICAgYW5j
aG9ycy5yaWdodDogcGFyZW50LnJpZ2h0OyBhbmNob3JzLmJvdHRvbTogcGFyZW50LmJvdHRvbTsg
YW5jaG9ycy5tYXJnaW5zOiA1CisgICAgICAgICAgICAgICAgICAgIHdpZHRoOiA4OyBoZWlnaHQ6
IDg7IHJhZGl1czogNAorICAgICAgICAgICAgICAgICAgICBjb2xvcjogQ3JpbXNvblN0YXR1cy5s
b2NhbC5jb25uZWN0ZWQgPyBWYlRva2Vucy5zdGF0dXNPbmxpbmUgOiBWYlRva2Vucy5zdGF0dXNP
ZmZsaW5lCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgfQorICAgICAgICAgICAgTmF2
aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IGJsdWV0b290aFNldHRpbmdz
QnV0dG9uCisgICAgICAgICAgICAgICAgaWNvblNvdXJjZTogInFyYzovcmVzL2NyaW1zb24tYmx1
ZXRvb3RoLnN2ZyIKKyAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIkJsdWV0
b290aCBzZXR0aW5ncyIpCisgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVk
CisgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJQYWlyIGNvbnRyb2xsZXJzIGFu
ZCBoZWFkcGhvbmVzIikKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsgY29ubmVjdGlvblBh
bmVsLmtpbmQgPSAiYnQiOyBjb25uZWN0aW9uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAgICAg
ICBLZXlzLm9uRG93blByZXNzZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZv
Y3VzKFF0LlRhYkZvY3VzKQorICAgICAgICAgICAgfQorICAgICAgICAgICAgTmF2aWdhYmxlVG9v
bEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IGJhdHRlcnlTdGF0dXNCdXR0b24KKyAgICAg
ICAgICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1iYXR0ZXJ5LnN2ZyIKKyAg
ICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIkJhdHRlcnkgc3RhdHVzIikKKyAg
ICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBU
b29sVGlwLnRleHQ6IENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVBlcmNlbnQgPj0gMCA/IHFz
VHIoIkJhdHRlcnk6ICUxJSDigKIgJTIiKS5hcmcoQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5
UGVyY2VudCkuYXJnKENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVN0YXRlKSA6IHFzVHIoIkJh
dHRlcnkgdW5hdmFpbGFibGUiKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBjcmltc29u
UGFuZWwua2luZCA9ICJiYXR0ZXJ5IjsgY3JpbXNvblBhbmVsLm9wZW4oKSB9CisgICAgICAgICAg
ICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1ZpZXcuY3VycmVudEl0ZW0uZm9yY2VBY3Rp
dmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIE5hdmlnYWJs
ZVRvb2xCdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBob3N0SGFyZHdhcmVCdXR0b24KKyAg
ICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1ob3N0LnN2ZyIKKyAg
ICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIlZpYmVwb2xsbyBob3N0IGhhcmR3
YXJlIHN0YXRzIikKKyAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAg
ICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIkhvc3QgQ1BVLCBSQU0sIEdQVSBhbmQg
dGVtcGVyYXR1cmVzIikKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsKKyAgICAgICAgICAg
ICAgICAgICAgdmFyIGl0ZW0gPSBzdGFja1ZpZXcuY3VycmVudEl0ZW0KKyAgICAgICAgICAgICAg
ICAgICAgdmFyIGhvc3QgPSB0b29sQmFyLm9uQXBwVmlldyA/IGl0ZW0uY3JpbXNvbkhvc3QKKyAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgOiAodG9vbEJhci5vblBjVmlldyA/IGl0ZW0uY29t
cHV0ZXJNb2RlbC5jcmltc29uSG9zdChpdGVtLmN1cnJlbnRJbmRleCkgOiB7fSkKKyAgICAgICAg
ICAgICAgICAgICAgQ3JpbXNvblN0YXR1cy5zZWxlY3RIb3N0KGhvc3QuaWQgfHwgIiIsIGhvc3Qu
dXJsIHx8ICIiKQorICAgICAgICAgICAgICAgICAgICBjcmltc29uUGFuZWwua2luZCA9ICJob3N0
IjsgY3JpbXNvblBhbmVsLm9wZW4oKQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAg
ICBLZXlzLm9uRG93blByZXNzZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZv
Y3VzKFF0LlRhYkZvY3VzKQorICAgICAgICAgICAgfQorCiAgICAgICAgICAgICBOYXZpZ2FibGVU
b29sQnV0dG9uIHsKICAgICAgICAgICAgICAgICBpZDogZGlzY29yZEJ1dHRvbgogICAgICAgICAg
ICAgICAgIHZpc2libGU6IGZhbHNlIC8vIFRlbXBvcmFyaWx5IGRpc2FibGVkIGZvciBWaWJlbWlz
CkBAIC01NjQsNyArNjQ2LDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICAgICAgICAg
IC8vIGFuIGluc3RhbGwgZmFpbHVyZSBmYWxscyBiYWNrIHRvIHRoZSByZWxlYXNlIHBhZ2Ugb24g
aXRzIG93bi4KICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IEF1dG9VcGRhdGVDaGVja2Vy
Lmluc3RhbGxpbmcKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgID8gcXNUcigiRG93bmxv
YWRpbmcgdXBkYXRl4oCmIikKLSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDogcXNUcigi
VXBkYXRlIGF2YWlsYWJsZSBmb3IgVmliZW1pczogVmVyc2lvbiAlMSDigJQgdGFwIHRvIGluc3Rh
bGwiKS5hcmcoQXV0b1VwZGF0ZUNoZWNrZXIuYXZhaWxhYmxlVmVyc2lvbikKKyAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgIDogcXNUcigiVXBkYXRlIGF2YWlsYWJsZSBmb3IgRWNsaXBzZTog
VmVyc2lvbiAlMSDigJQgdGFwIHRvIGluc3RhbGwiKS5hcmcoQXV0b1VwZGF0ZUNoZWNrZXIuYXZh
aWxhYmxlVmVyc2lvbikKIAogICAgICAgICAgICAgICAgIC8vIFN0cmljdGx5LW5ld2VyIGJ1aWxk
cyBvbmx5IChhIGNoYW5uZWwtc3dpdGNoIGRvd25ncmFkZSBvZmZlcgogICAgICAgICAgICAgICAg
IC8vIGxpdmVzIGluIFNldHRpbmdzLCBub3Qgb24gdGhlIHRvb2xiYXIpLgpAQCAtNjQ2LDYgKzcy
OCwyMSBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgICAgICAgICAgfQogICAgICAgICAg
ICAgfQogCisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAgICAg
ICBpZDogZWNsaXBzZUNlbnRlckJ1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJx
cmM6L3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZyIKKyAgICAgICAgICAgICAgICBBY2Nlc3NpYmxl
Lm5hbWU6IHFzVHIoIkVjbGlwc2UgY29udHJvbCBjZW50ZXIiKQorICAgICAgICAgICAgICAgIFRv
b2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNU
cigiQ29udHJvbCBjZW50ZXIg4oCiIEN0cmwrU2hpZnQrQyIpCisgICAgICAgICAgICAgICAgb25D
bGlja2VkOiB7CisgICAgICAgICAgICAgICAgICAgIHZhciBpdGVtID0gc3RhY2tWaWV3LmN1cnJl
bnRJdGVtCisgICAgICAgICAgICAgICAgICAgIGVjbGlwc2VDZW50ZXIuaG9zdCA9IHRvb2xCYXIu
b25BcHBWaWV3ID8gaXRlbS5jcmltc29uSG9zdCA6ICh0b29sQmFyLm9uUGNWaWV3ID8gaXRlbS5j
b21wdXRlck1vZGVsLmNyaW1zb25Ib3N0KGl0ZW0uY3VycmVudEluZGV4KSA6IHt9KQorICAgICAg
ICAgICAgICAgICAgICBlY2xpcHNlQ2VudGVyLm9wZW4oKQorICAgICAgICAgICAgICAgIH0KKyAg
ICAgICAgICAgICAgICBLZXlzLm9uRG93blByZXNzZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRlbS5m
b3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgICAgICAgICAgICAgIFNob3J0Y3V0IHsg
c2VxdWVuY2U6ICJDdHJsK1NoaWZ0K0MiOyBlbmFibGVkOiB0b29sQmFyLm9uUGNWaWV3IHx8IHRv
b2xCYXIub25BcHBWaWV3OyBvbkFjdGl2YXRlZDogZWNsaXBzZUNlbnRlckJ1dHRvbi5jbGlja2Vk
KCkgfQorICAgICAgICAgICAgfQorCiAgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsK
ICAgICAgICAgICAgICAgICBpZDogc2V0dGluZ3NCdXR0b24KIApAQCAtNjczLDcgKzc3MCw3IEBA
IEFwcGxpY2F0aW9uV2luZG93IHsKIAogICAgIEVycm9yTWVzc2FnZURpYWxvZyB7CiAgICAgICAg
IGlkOiBub0h3RGVjb2RlckRpYWxvZwotICAgICAgICB0ZXh0OiBxc1RyKCJObyBmdW5jdGlvbmlu
ZyBoYXJkd2FyZSBhY2NlbGVyYXRlZCB2aWRlbyBkZWNvZGVyIHdhcyBkZXRlY3RlZCBieSBWaWJl
bWlzLiAiICsKKyAgICAgICAgdGV4dDogcXNUcigiTm8gZnVuY3Rpb25pbmcgaGFyZHdhcmUgYWNj
ZWxlcmF0ZWQgdmlkZW8gZGVjb2RlciB3YXMgZGV0ZWN0ZWQgYnkgRWNsaXBzZS4gIiArCiAgICAg
ICAgICAgICAgICAgICAgIllvdXIgc3RyZWFtaW5nIHBlcmZvcm1hbmNlIG1heSBiZSBzZXZlcmVs
eSBkZWdyYWRlZCBpbiB0aGlzIGNvbmZpZ3VyYXRpb24uIikKICAgICAgICAgaGVscFRleHQ6IHFz
VHIoIkNsaWNrIHRoZSBIZWxwIGJ1dHRvbiBmb3IgbW9yZSBpbmZvcm1hdGlvbiBvbiBzb2x2aW5n
IHRoaXMgcHJvYmxlbS4iKQogICAgICAgICBoZWxwVXJsOiAiaHR0cHM6Ly9naXRodWIuY29tL25h
dnlhczMyMS92aWJlbWlzIgpAQCAtNjkwLDcgKzc4Nyw3IEBAIEFwcGxpY2F0aW9uV2luZG93IHsK
ICAgICBOYXZpZ2FibGVNZXNzYWdlRGlhbG9nIHsKICAgICAgICAgaWQ6IHdvdzY0RGlhbG9nCiAg
ICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLk9rIHwgRGlhbG9nLkNhbmNlbAotICAgICAg
ICB0ZXh0OiBxc1RyKCJUaGlzIHZlcnNpb24gb2YgVmliZW1pcyBpc24ndCBvcHRpbWl6ZWQgZm9y
IHlvdXIgUEMuIFBsZWFzZSBkb3dubG9hZCB0aGUgJyUxJyB2ZXJzaW9uIG9mIFZpYmVtaXMgZm9y
IHRoZSBiZXN0IHN0cmVhbWluZyBwZXJmb3JtYW5jZS4iKS5hcmcoU3lzdGVtUHJvcGVydGllcy5m
cmllbmRseU5hdGl2ZUFyY2hOYW1lKQorICAgICAgICB0ZXh0OiBxc1RyKCJUaGlzIHZlcnNpb24g
b2YgRWNsaXBzZSBpc24ndCBvcHRpbWl6ZWQgZm9yIHlvdXIgUEMuIFBsZWFzZSBkb3dubG9hZCB0
aGUgJyUxJyB2ZXJzaW9uIG9mIEVjbGlwc2UgZm9yIHRoZSBiZXN0IHN0cmVhbWluZyBwZXJmb3Jt
YW5jZS4iKS5hcmcoU3lzdGVtUHJvcGVydGllcy5mcmllbmRseU5hdGl2ZUFyY2hOYW1lKQogICAg
ICAgICBvbkFjY2VwdGVkOiB7CiAgICAgICAgICAgICBTeXN0ZW1Qcm9wZXJ0aWVzLm9wZW5Vcmwo
Imh0dHBzOi8vZ2l0aHViLmNvbS9uYXZ5YXMzMjEvdmliZW1pcy9yZWxlYXNlcyIpOwogICAgICAg
ICB9CkBAIC02OTksNyArNzk2LDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgIEVycm9yTWVz
c2FnZURpYWxvZyB7CiAgICAgICAgIGlkOiB1bm1hcHBlZEdhbWVwYWREaWFsb2cKICAgICAgICAg
cHJvcGVydHkgc3RyaW5nIHVubWFwcGVkR2FtZXBhZHMgOiAiIgotICAgICAgICB0ZXh0OiBxc1Ry
KCJWaWJlbWlzIGRldGVjdGVkIGdhbWVwYWRzIHdpdGhvdXQgYSBtYXBwaW5nOiIpICsgIlxuIiAr
IHVubWFwcGVkR2FtZXBhZHMKKyAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBkZXRlY3RlZCBn
YW1lcGFkcyB3aXRob3V0IGEgbWFwcGluZzoiKSArICJcbiIgKyB1bm1hcHBlZEdhbWVwYWRzCiAg
ICAgICAgIGhlbHBUZXh0U2VwYXJhdG9yOiAiXG5cbiIKICAgICAgICAgaGVscFRleHQ6IHFzVHIo
IkNsaWNrIHRoZSBIZWxwIGJ1dHRvbiBmb3IgaW5mb3JtYXRpb24gb24gaG93IHRvIG1hcCB5b3Vy
IGdhbWVwYWRzLiIpCiAgICAgICAgIGhlbHBVcmw6ICJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFz
MzIxL3ZpYmVtaXMiCmRpZmYgLS1naXQgYS9hcHAvbWFpbi5jcHAgYi9hcHAvbWFpbi5jcHAKaW5k
ZXggMjkyMjI3Ny4uM2VjOTRkYiAxMDA2NDQKLS0tIGEvYXBwL21haW4uY3BwCisrKyBiL2FwcC9t
YWluLmNwcApAQCAtODY5LDYgKzg2OSw3IEBAIGludCBtYWluKGludCBhcmdjLCBjaGFyICphcmd2
W10pCiAgICAgfQ0KIA0KICAgICBRR3VpQXBwbGljYXRpb24gYXBwKGFyZ2MsIGFyZ3YpOw0KKyAg
ICBRR3VpQXBwbGljYXRpb246OnNldEFwcGxpY2F0aW9uRGlzcGxheU5hbWUoIkVjbGlwc2UiKTsK
IA0KICAgICAvLyBWaWJlbWlzOiB0aGUgUXQgUXVpY2sgQ29udHJvbHMgTWF0ZXJpYWwgc3R5bGUg
cmVuZGVycyBidXR0b24gdGV4dCBpbiBBTEwgQ0FQUyBieSBkZWZhdWx0DQogICAgIC8vIChlLmcu
IHRoZSBiaXRyYXRlICJVU0UgREVGQVVMVCAoMzAgTUJQUykiIGJ1dHRvbiksIHdoaWNoIGxvb2tz
IG9mZi4gRm9yY2UgbWl4ZWQgY2FzZSBmb3IgdGhlDQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdo
dG9zL2NyaW1zb25zdGF0dXMuY3BwIGIvYXBwL21vb25saWdodG9zL2NyaW1zb25zdGF0dXMuY3Bw
Cm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmRhZmNhMmUKLS0tIC9kZXYvbnVs
bAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5jcHAKQEAgLTAsMCArMSwyMjIg
QEAKKyNpbmNsdWRlICJjcmltc29uc3RhdHVzLmgiCisjaW5jbHVkZSA8UURhdGVUaW1lPgorI2lu
Y2x1ZGUgPFFEaXI+CisjaW5jbHVkZSA8UUZpbGU+CisjaW5jbHVkZSA8UUpzb25Eb2N1bWVudD4K
KyNpbmNsdWRlIDxRSnNvbk9iamVjdD4KKyNpbmNsdWRlIDxRTmV0d29ya0ludGVyZmFjZT4KKyNp
bmNsdWRlIDxRTmV0d29ya1JlcXVlc3Q+CisjaW5jbHVkZSA8UVNhdmVGaWxlPgorI2luY2x1ZGUg
PFFTc2xDZXJ0aWZpY2F0ZT4KKyNpbmNsdWRlIDxRU3NsRXJyb3I+CisjaW5jbHVkZSA8UVN0YW5k
YXJkUGF0aHM+CisjaW5jbHVkZSA8UUNyeXB0b2dyYXBoaWNIYXNoPgorI2luY2x1ZGUgPFFVcmw+
CisjaW5jbHVkZSA8Y21hdGg+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNsdWRlIDxRQ29y
ZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUgPG1lbW9yeT4KKyNpbmNsdWRlIDxRUmVndWxhckV4cHJl
c3Npb24+CisjaW5jbHVkZSA8UUZpbGVJbmZvPgorI2luY2x1ZGUgPFFTc2xDb25maWd1cmF0aW9u
PgorCituYW1lc3BhY2UgeworUVN0cmluZyByZWFkKGNvbnN0IFFTdHJpbmcmIHBhdGgpIHsKKyAg
ICBRRmlsZSBmKHBhdGgpOyByZXR1cm4gZi5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpID8gUVN0
cmluZzo6ZnJvbVV0ZjgoZi5yZWFkQWxsKCkpLnRyaW1tZWQoKSA6IFFTdHJpbmcoKTsKK30KK2Nv
bnN0IGF1dG8gdXNlck9ubHkgPSBRRmlsZURldmljZTo6UmVhZE93bmVyIHwgUUZpbGVEZXZpY2U6
OldyaXRlT3duZXI7Cit9CitDcmltc29uU3RhdHVzOjpDcmltc29uU3RhdHVzKFFPYmplY3QqIHBh
cmVudCkgOiBRT2JqZWN0KHBhcmVudCkgeworICAgIGNvbm5lY3QoJm1fbG9jYWxUaW1lciwgJlFU
aW1lcjo6dGltZW91dCwgdGhpcywgJkNyaW1zb25TdGF0dXM6OnJlZnJlc2hMb2NhbCk7CisgICAg
Y29ubmVjdCgmbV9zdGF0c1RpbWVyLCAmUVRpbWVyOjp0aW1lb3V0LCB0aGlzLCAmQ3JpbXNvblN0
YXR1czo6cmVmcmVzaCk7CisgICAgY29ubmVjdCgmbV93aWZpLCAmUVByb2Nlc3M6OmZpbmlzaGVk
LCB0aGlzLCBbdGhpc10oaW50IGV4aXQsIFFQcm9jZXNzOjpFeGl0U3RhdHVzKSB7CisgICAgICAg
IGlmIChleGl0ID09IDApIHsKKyAgICAgICAgICAgIGNvbnN0IGF1dG8gbGluZXMgPSBRU3RyaW5n
Ojpmcm9tVXRmOChtX3dpZmkucmVhZEFsbFN0YW5kYXJkT3V0cHV0KCkpLnNwbGl0KCdcbicpOwor
ICAgICAgICAgICAgZm9yIChjb25zdCBhdXRvJiBsaW5lIDogbGluZXMpIHsKKyAgICAgICAgICAg
ICAgICBpZiAoIWxpbmUuc3RhcnRzV2l0aCgieWVzOiIpKSBjb250aW51ZTsKKyAgICAgICAgICAg
ICAgICBpbnQgc2VwYXJhdG9yID0gbGluZS5pbmRleE9mKCc6JywgNCk7IGJvb2wgb2sgPSBmYWxz
ZTsKKyAgICAgICAgICAgICAgICBpbnQgc2lnbmFsID0gbGluZS5taWQoNCwgc2VwYXJhdG9yIC0g
NCkudG9JbnQoJm9rKTsKKyAgICAgICAgICAgICAgICBpZiAob2sgJiYgc2lnbmFsID49IDAgJiYg
c2lnbmFsIDw9IDEwMCkgbV9sb2NhbFsid2lmaVNpZ25hbCJdID0gc2lnbmFsOworICAgICAgICAg
ICAgICAgIGlmIChzZXBhcmF0b3IgPj0gMCkgbV9sb2NhbFsibmV0d29yayJdID0gdHIoIldpLUZp
OiAlMSIpLmFyZyhsaW5lLm1pZChzZXBhcmF0b3IgKyAxKSk7CisgICAgICAgICAgICAgICAgYnJl
YWs7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBlbWl0IGxvY2FsQ2hhbmdlZCgpOworICAg
ICAgICB9CisgICAgfSk7CisgICAgbV9sb2NhbFRpbWVyLnN0YXJ0KDEwMDAwKTsgbV9zdGF0c1Rp
bWVyLnNldEludGVydmFsKDIwMDApOyByZWZyZXNoTG9jYWwoKTsKK30KK0NyaW1zb25TdGF0dXM6
On5Dcmltc29uU3RhdHVzKCkgeworICAgIG1fc3RhdHNUaW1lci5zdG9wKCk7IG1fbG9jYWxUaW1l
ci5zdG9wKCk7IGNhbmNlbCgpOworICAgIGlmIChtX3dpZmkuc3RhdGUoKSAhPSBRUHJvY2Vzczo6
Tm90UnVubmluZykgeyBtX3dpZmkua2lsbCgpOyBtX3dpZmkud2FpdEZvckZpbmlzaGVkKDUwMCk7
IH0KK30KK1FTdHJpbmcgQ3JpbXNvblN0YXR1czo6Y29uZmlnRmlsZSgpIGNvbnN0IHsKKyAgICBy
ZXR1cm4gUVN0YW5kYXJkUGF0aHM6OndyaXRhYmxlTG9jYXRpb24oUVN0YW5kYXJkUGF0aHM6OkFw
cENvbmZpZ0xvY2F0aW9uKSArICIvY3JpbXNvbi1ob3N0cy5qc29uIjsKK30KK1FTdHJpbmcgQ3Jp
bXNvblN0YXR1czo6bm9ybWFsaXplZFBpbihRU3RyaW5nIHBpbikgeworICAgIHBpbi5yZW1vdmUo
JzonKTsgcGluLnJlbW92ZSgnICcpOyByZXR1cm4gcGluLnRvTG93ZXIoKTsKK30KK2Jvb2wgQ3Jp
bXNvblN0YXR1czo6dmFsaWRFbmRwb2ludChjb25zdCBRU3RyaW5nJiB2YWx1ZSkgeworICAgIFFV
cmwgdSh2YWx1ZSwgUVVybDo6U3RyaWN0TW9kZSk7CisgICAgcmV0dXJuIHUuaXNWYWxpZCgpICYm
IHUuc2NoZW1lKCkgPT0gImh0dHBzIiAmJiAhdS5ob3N0KCkuaXNFbXB0eSgpICYmCisgICAgICAg
IHUudXNlckluZm8oKS5pc0VtcHR5KCkgJiYgdS5xdWVyeSgpLmlzRW1wdHkoKSAmJiB1LmZyYWdt
ZW50KCkuaXNFbXB0eSgpICYmCisgICAgICAgICh1LnBhdGgoKS5pc0VtcHR5KCkgfHwgdS5wYXRo
KCkgPT0gIi8iKSAmJiB1LnBvcnQoNDc5OTApID4gMDsKK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6
Y2FuY2VsKCkgeworICAgIGlmIChtX3JlcGx5KSB7IGRpc2Nvbm5lY3QobV9yZXBseSwgbnVsbHB0
ciwgdGhpcywgbnVsbHB0cik7IG1fcmVwbHktPmFib3J0KCk7IG1fcmVwbHktPmRlbGV0ZUxhdGVy
KCk7IG1fcmVwbHkgPSBudWxscHRyOyB9Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OnNlbGVjdEhv
c3QoUVN0cmluZyBpZCwgUVN0cmluZyBzdWdnZXN0ZWRVcmwpIHsKKyAgICBpZiAoaWQgPT0gbV9o
b3N0KSByZXR1cm47CisgICAgY2FuY2VsKCk7IG1fbmV0d29yay5jbGVhckNvbm5lY3Rpb25DYWNo
ZSgpOyBtX2hvc3QgPSBpZDsgbV90b2tlbi5jbGVhcigpOyBtX3Bpbi5jbGVhcigpOworICAgIG1f
ZW5kcG9pbnQgPSB2YWxpZEVuZHBvaW50KHN1Z2dlc3RlZFVybCkgPyBzdWdnZXN0ZWRVcmwgOiBR
U3RyaW5nKCk7CisgICAgUUZpbGUgZihjb25maWdGaWxlKCkpOworICAgIGlmIChmLm9wZW4oUUlP
RGV2aWNlOjpSZWFkT25seSkpIHsKKyAgICAgICAgYXV0byBjID0gUUpzb25Eb2N1bWVudDo6ZnJv
bUpzb24oZi5yZWFkQWxsKCkpLm9iamVjdCgpLnZhbHVlKGlkKS50b09iamVjdCgpOworICAgICAg
ICBpZiAodmFsaWRFbmRwb2ludChjLnZhbHVlKCJ1cmwiKS50b1N0cmluZygpKSkgeworICAgICAg
ICAgICAgbV9lbmRwb2ludCA9IGMudmFsdWUoInVybCIpLnRvU3RyaW5nKCk7IG1fdG9rZW4gPSBj
LnZhbHVlKCJ0b2tlbiIpLnRvU3RyaW5nKCk7IG1fcGluID0gYy52YWx1ZSgicGluIikudG9TdHJp
bmcoKTsKKyAgICAgICAgfQorICAgIH0KKyAgICBtX3N0YXRzLmNsZWFyKCk7IG1fc3RhdHVzID0g
aWQuaXNFbXB0eSgpID8gdHIoIkNob29zZSBhIGhvc3QgdG8gdmlldyBoYXJkd2FyZSBzdGF0cyIp
IDogdHIoIkNvbmZpZ3VyZSBhIFZpYmVwb2xsbyByZWFkLW9ubHkgc3RhdHMgdG9rZW4iKTsKKyAg
ICBlbWl0IGNvbmZpZ0NoYW5nZWQoKTsgZW1pdCBzdGF0c0NoYW5nZWQoKTsgaWYgKG1fdmlzaWJs
ZSkgcmVmcmVzaCgpOworfQorYm9vbCBDcmltc29uU3RhdHVzOjpjb25maWd1cmUoUVN0cmluZyB1
cmwsIFFTdHJpbmcgdG9rZW4sIFFTdHJpbmcgcGluKSB7CisgICAgcGluID0gbm9ybWFsaXplZFBp
bihwaW4pOworICAgIGlmIChtX2hvc3QuaXNFbXB0eSgpIHx8ICF2YWxpZEVuZHBvaW50KHVybCkg
fHwgKCFwaW4uaXNFbXB0eSgpICYmCisgICAgICAgIChwaW4uc2l6ZSgpICE9IDY0IHx8IHBpbi5j
b250YWlucyhRUmVndWxhckV4cHJlc3Npb24oIlteMC05YS1mXSIpKSkpKSB7CisgICAgICAgIGZh
aWwodHIoIlVzZSBhbiBIVFRQUyBob3N0IFVSTCBhbmQgYW4gb3B0aW9uYWwgNjQtZGlnaXQgU0hB
LTI1NiBjZXJ0aWZpY2F0ZSBmaW5nZXJwcmludCIpKTsgcmV0dXJuIGZhbHNlOworICAgIH0KKyAg
ICAvLyBBIGJsYW5rIHRva2VuIGtlZXBzIHRoZSBvbGQgdG9rZW4gb25seSBmb3IgdGhlIHNhbWUg
ZW5kcG9pbnQuCisgICAgaWYgKHRva2VuLmlzRW1wdHkoKSAmJiBRVXJsKHVybCkgPT0gUVVybCht
X2VuZHBvaW50KSkgdG9rZW4gPSBtX3Rva2VuOworICAgIGlmICh0b2tlbi5pc0VtcHR5KCkgfHwg
dG9rZW4uY29udGFpbnMoJ1xyJykgfHwgdG9rZW4uY29udGFpbnMoJ1xuJykgfHwgdG9rZW4uc2l6
ZSgpID4gNDA5NikgeworICAgICAgICBmYWlsKHRyKCJBIHJlYWQtb25seSBWaWJlcG9sbG8gQVBJ
IHRva2VuIGlzIHJlcXVpcmVkIikpOyByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIFFGaWxlIGYo
Y29uZmlnRmlsZSgpKTsgUUpzb25PYmplY3QgYWxsOworICAgIGlmIChmLm9wZW4oUUlPRGV2aWNl
OjpSZWFkT25seSkpIGFsbCA9IFFKc29uRG9jdW1lbnQ6OmZyb21Kc29uKGYucmVhZEFsbCgpKS5v
YmplY3QoKTsKKyAgICBhbGxbbV9ob3N0XSA9IFFKc29uT2JqZWN0e3sidXJsIiwgdXJsfSwgeyJ0
b2tlbiIsIHRva2VufSwgeyJwaW4iLCBwaW59fTsKKyAgICBRRGlyKCkubWtwYXRoKFFGaWxlSW5m
byhjb25maWdGaWxlKCkpLmFic29sdXRlUGF0aCgpKTsKKyAgICBRU2F2ZUZpbGUgb3V0KGNvbmZp
Z0ZpbGUoKSk7CisgICAgaWYgKCFvdXQub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkgfHwgIW91
dC5zZXRQZXJtaXNzaW9ucyh1c2VyT25seSkgfHwKKyAgICAgICAgb3V0LndyaXRlKFFKc29uRG9j
dW1lbnQoYWxsKS50b0pzb24oKSkgPCAwIHx8ICFvdXQuY29tbWl0KCkpIHsKKyAgICAgICAgZmFp
bCh0cigiQ291bGQgbm90IHNhdmUgaG9zdCBhY2Nlc3Mgc2V0dGluZ3MiKSk7IHJldHVybiBmYWxz
ZTsKKyAgICB9CisgICAgY2FuY2VsKCk7IG1fbmV0d29yay5jbGVhckNvbm5lY3Rpb25DYWNoZSgp
OyBtX2VuZHBvaW50ID0gdXJsOyBtX3Rva2VuID0gdG9rZW47IG1fcGluID0gcGluOworICAgIG1f
c3RhdHNUaW1lci5zZXRJbnRlcnZhbCgyMDAwKTsKKyAgICBtX3N0YXRzLmNsZWFyKCk7IG1fc3Rh
dHVzID0gdHIoIkNvbm5lY3RpbmcgdG8gaG9zdCBzdGF0c+KApiIpOworICAgIGVtaXQgY29uZmln
Q2hhbmdlZCgpOyBlbWl0IHN0YXRzQ2hhbmdlZCgpOyByZWZyZXNoKCk7IHJldHVybiB0cnVlOwor
fQordm9pZCBDcmltc29uU3RhdHVzOjpzZXRWaXNpYmxlKGJvb2wgdmlzaWJsZSkgeworICAgIG1f
dmlzaWJsZSA9IHZpc2libGU7CisgICAgaWYgKHZpc2libGUpIHsgcmVmcmVzaExvY2FsKCk7IG1f
c3RhdHNUaW1lci5zdGFydCgpOyByZWZyZXNoKCk7IH0KKyAgICBlbHNlIHsgbV9zdGF0c1RpbWVy
LnN0b3AoKTsgY2FuY2VsKCk7IH0KK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6ZmFpbChRU3RyaW5n
IG1lc3NhZ2UpIHsKKyAgICBtX3N0YXRzLmNsZWFyKCk7IG1fc3RhdHVzID0gbWVzc2FnZTsKKyAg
ICBtX3N0YXRzVGltZXIuc2V0SW50ZXJ2YWwocU1pbigzMDAwMCwgcU1heCg0MDAwLCBtX3N0YXRz
VGltZXIuaW50ZXJ2YWwoKSAqIDIpKSk7CisgICAgZW1pdCBzdGF0c0NoYW5nZWQoKTsKK30KK1FW
YXJpYW50TWFwIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoY29uc3QgUUJ5dGVBcnJheSYgYnl0
ZXMsIFFTdHJpbmcqIGVycm9yKSB7CisgICAgaWYgKGJ5dGVzLnNpemUoKSA+IDY1NTM2KSB7ICpl
cnJvciA9ICJPdmVyc2l6ZWQgaG9zdCBzdGF0cyByZXNwb25zZSI7IHJldHVybiB7fTsgfQorICAg
IFFKc29uUGFyc2VFcnJvciBlOyBhdXRvIGRvYyA9IFFKc29uRG9jdW1lbnQ6OmZyb21Kc29uKGJ5
dGVzLCAmZSk7CisgICAgaWYgKGUuZXJyb3IgIT0gUUpzb25QYXJzZUVycm9yOjpOb0Vycm9yIHx8
ICFkb2MuaXNPYmplY3QoKSkgeyAqZXJyb3IgPSAiSW52YWxpZCBob3N0IHN0YXRzIHJlc3BvbnNl
IjsgcmV0dXJuIHt9OyB9CisgICAgYXV0byBvYmogPSBkb2Mub2JqZWN0KCk7IFFWYXJpYW50TWFw
IHJlc3VsdDsKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBrZXlzID0geyJjcHVfcGVyY2VudCIsImNw
dV90ZW1wX2MiLCJyYW1fdXNlZF9ieXRlcyIsInJhbV90b3RhbF9ieXRlcyIsInJhbV9wZXJjZW50
IiwKKyAgICAgICAgImdwdV9wZXJjZW50IiwiZ3B1X2VuY29kZXJfcGVyY2VudCIsImdwdV90ZW1w
X2MiLCJ2cmFtX3VzZWRfYnl0ZXMiLCJ2cmFtX3RvdGFsX2J5dGVzIiwidnJhbV9wZXJjZW50Iiwi
bmV0X3J4X2JwcyIsIm5ldF90eF9icHMifTsKKyAgICBib29sIHJlY29nbml6ZWQgPSBmYWxzZTsK
KyAgICBmb3IgKGNvbnN0IGF1dG8mIGtleSA6IGtleXMpIHsKKyAgICAgICAgYXV0byB2ID0gb2Jq
LnZhbHVlKGtleSk7IHJlY29nbml6ZWQgfD0gb2JqLmNvbnRhaW5zKGtleSk7CisgICAgICAgIGRv
dWJsZSBuID0gdi50b0RvdWJsZSgtMSk7CisgICAgICAgIGlmICghdi5pc0RvdWJsZSgpIHx8ICFz
dGQ6OmlzZmluaXRlKG4pIHx8IG4gPCAwIHx8IChrZXkuZW5kc1dpdGgoInBlcmNlbnQiKSAmJiBu
ID4gMTAwKSkgY29udGludWU7CisgICAgICAgIHJlc3VsdFtrZXldID0gbjsKKyAgICB9CisgICAg
Zm9yIChjb25zdCBhdXRvJiBwcmVmaXggOiB7UVN0cmluZygicmFtIiksIFFTdHJpbmcoInZyYW0i
KX0pIHsKKyAgICAgICAgZG91YmxlIHRvdGFsID0gcmVzdWx0LnZhbHVlKHByZWZpeCArICJfdG90
YWxfYnl0ZXMiKS50b0RvdWJsZSgpOworICAgICAgICBpZiAodG90YWwgPD0gMCkgeyByZXN1bHQu
cmVtb3ZlKHByZWZpeCArICJfcGVyY2VudCIpOyByZXN1bHQucmVtb3ZlKHByZWZpeCArICJfdXNl
ZF9ieXRlcyIpOyB9CisgICAgICAgIGVsc2UgaWYgKHJlc3VsdC5jb250YWlucyhwcmVmaXggKyAi
X3VzZWRfYnl0ZXMiKSkgeworICAgICAgICAgICAgZG91YmxlIHVzZWQgPSBxTWluKHJlc3VsdC52
YWx1ZShwcmVmaXggKyAiX3VzZWRfYnl0ZXMiKS50b0RvdWJsZSgpLCB0b3RhbCk7CisgICAgICAg
ICAgICByZXN1bHRbcHJlZml4ICsgIl91c2VkX2J5dGVzIl0gPSB1c2VkOyByZXN1bHRbcHJlZml4
ICsgIl9wZXJjZW50Il0gPSB1c2VkICogMTAwIC8gdG90YWw7CisgICAgICAgIH0KKyAgICB9Cisg
ICAgaWYgKCFyZWNvZ25pemVkKSB7ICplcnJvciA9ICJIb3N0IGRvZXMgbm90IGV4cG9zZSB0aGUg
ZXhwZWN0ZWQgVmliZXBvbGxvIHN0YXRzIGZpZWxkcyI7IHJldHVybiB7fTsgfQorICAgIGVycm9y
LT5jbGVhcigpOyByZXR1cm4gcmVzdWx0OworfQordm9pZCBDcmltc29uU3RhdHVzOjpyZWZyZXNo
KCkgeworICAgIGlmICghbV92aXNpYmxlIHx8IG1fcmVwbHkgfHwgIWNvbmZpZ3VyZWQoKSkgcmV0
dXJuOworICAgIFFVcmwgdXJsKG1fZW5kcG9pbnQpOyB1cmwuc2V0UGF0aCgiL2FwaS9ob3N0L3N0
YXRzIik7CisgICAgUU5ldHdvcmtSZXF1ZXN0IHJlcSh1cmwpOworICAgIHJlcS5zZXRBdHRyaWJ1
dGUoUU5ldHdvcmtSZXF1ZXN0OjpSZWRpcmVjdFBvbGljeUF0dHJpYnV0ZSwgUU5ldHdvcmtSZXF1
ZXN0OjpNYW51YWxSZWRpcmVjdFBvbGljeSk7CisgICAgcmVxLnNldFRyYW5zZmVyVGltZW91dCgz
MDAwKTsKKyAgICByZXEuc2V0UmF3SGVhZGVyKCJBdXRob3JpemF0aW9uIiwgIkJlYXJlciAiICsg
bV90b2tlbi50b1V0ZjgoKSk7CisgICAgcmVxLnNldFJhd0hlYWRlcigiQWNjZXB0IiwgImFwcGxp
Y2F0aW9uL2pzb24iKTsKKyAgICBhdXRvIHJlcGx5ID0gbV9uZXR3b3JrLmdldChyZXEpOyByZXBs
eS0+c2V0UmVhZEJ1ZmZlclNpemUoNjU1MzYpOyBtX3JlcGx5ID0gcmVwbHk7CisgICAgYXV0byBk
YXRhID0gc3RkOjptYWtlX3NoYXJlZDxRQnl0ZUFycmF5PigpOworICAgIGF1dG8gaW52YWxpZFBp
biA9IHN0ZDo6bWFrZV9zaGFyZWQ8Ym9vbD4oZmFsc2UpOworICAgIGF1dG8gb3ZlcnNpemVkID0g
c3RkOjptYWtlX3NoYXJlZDxib29sPihmYWxzZSk7CisgICAgYXV0byBjZXJ0TWF0Y2hlcyA9IFt0
aGlzLCByZXBseV0geworICAgICAgICByZXR1cm4gbm9ybWFsaXplZFBpbihRU3RyaW5nOjpmcm9t
TGF0aW4xKHJlcGx5LT5zc2xDb25maWd1cmF0aW9uKCkucGVlckNlcnRpZmljYXRlKCkuZGlnZXN0
KFFDcnlwdG9ncmFwaGljSGFzaDo6U2hhMjU2KS50b0hleCgpKSkgPT0gbV9waW47CisgICAgfTsK
KyAgICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtSZXBseTo6ZW5jcnlwdGVkLCB0aGlzLCBbdGhp
cywgcmVwbHksIGNlcnRNYXRjaGVzLCBpbnZhbGlkUGluXSB7CisgICAgICAgIGlmICghbV9waW4u
aXNFbXB0eSgpICYmICFjZXJ0TWF0Y2hlcygpKSB7ICppbnZhbGlkUGluID0gdHJ1ZTsgcmVwbHkt
PmFib3J0KCk7IH0KKyAgICB9KTsKKyAgICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtSZXBseTo6
c3NsRXJyb3JzLCB0aGlzLCBbdGhpcywgcmVwbHksIGNlcnRNYXRjaGVzXShjb25zdCBRTGlzdDxR
U3NsRXJyb3I+JiBlcnJvcnMpIHsKKyAgICAgICAgaWYgKG1fcGluLmlzRW1wdHkoKSB8fCAhY2Vy
dE1hdGNoZXMoKSkgcmV0dXJuOworICAgICAgICBmb3IgKGNvbnN0IGF1dG8mIGUgOiBlcnJvcnMp
IHsKKyAgICAgICAgICAgIGlmIChlLmVycm9yKCkgIT0gUVNzbEVycm9yOjpTZWxmU2lnbmVkQ2Vy
dGlmaWNhdGUgJiYgZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6U2VsZlNpZ25lZENlcnRpZmljYXRl
SW5DaGFpbiAmJgorICAgICAgICAgICAgICAgIGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6OkNlcnRp
ZmljYXRlVW50cnVzdGVkICYmIGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6Okhvc3ROYW1lTWlzbWF0
Y2gpIHJldHVybjsKKyAgICAgICAgfQorICAgICAgICByZXBseS0+aWdub3JlU3NsRXJyb3JzKGVy
cm9ycyk7IC8vIE9ubHkgdGhpcyBleHBsaWNpdGx5IHBpbm5lZCBob3N0IGNlcnRpZmljYXRlLgor
ICAgIH0pOworICAgIGNvbm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5OjpyZWFkeVJlYWQsIHRo
aXMsIFtyZXBseSwgZGF0YSwgb3ZlcnNpemVkXSB7CisgICAgICAgIGlmICgqb3ZlcnNpemVkIHx8
IHJlcGx5LT5pc0ZpbmlzaGVkKCkpIHJldHVybjsKKyAgICAgICAgaWYgKGRhdGEtPnNpemUoKSAr
IHJlcGx5LT5ieXRlc0F2YWlsYWJsZSgpID4gNjU1MzYpIHsgKm92ZXJzaXplZCA9IHRydWU7IHJl
cGx5LT5hYm9ydCgpOyByZXR1cm47IH0KKyAgICAgICAgZGF0YS0+YXBwZW5kKHJlcGx5LT5yZWFk
QWxsKCkpOworICAgIH0pOworICAgIGNvbm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5OjpmaW5p
c2hlZCwgdGhpcywgW3RoaXMsIHJlcGx5LCBkYXRhLCBpbnZhbGlkUGluLCBvdmVyc2l6ZWRdIHsK
KyAgICAgICAgbV9yZXBseSA9IG51bGxwdHI7CisgICAgICAgIGludCBzdGF0dXMgPSByZXBseS0+
YXR0cmlidXRlKFFOZXR3b3JrUmVxdWVzdDo6SHR0cFN0YXR1c0NvZGVBdHRyaWJ1dGUpLnRvSW50
KCk7CisgICAgICAgIGlmICgqb3ZlcnNpemVkKSBmYWlsKHRyKCJIb3N0IHN0YXRzIHJlc3BvbnNl
IGV4Y2VlZGVkIHRoZSBzaXplIGxpbWl0IikpOworICAgICAgICBlbHNlIGlmICgqaW52YWxpZFBp
bikgZmFpbCh0cigiSG9zdCBjZXJ0aWZpY2F0ZSBjaGFuZ2VkOyB2ZXJpZnkgdGhlIHNhdmVkIGZp
bmdlcnByaW50IikpOworICAgICAgICBlbHNlIGlmIChzdGF0dXMgPT0gNDAxIHx8IHN0YXR1cyA9
PSA0MDMpIGZhaWwodHIoIkhvc3Qgc3RhdHMgYWNjZXNzIGRlbmllZDogY2hlY2sgdGhlIHJlYWQt
b25seSB0b2tlbiIpKTsKKyAgICAgICAgZWxzZSBpZiAoc3RhdHVzID09IDQwNCkgZmFpbCh0cigi
VGhpcyBob3N0IGRvZXMgbm90IHByb3ZpZGUgVmliZXBvbGxvIGhhcmR3YXJlIHN0YXRzIikpOwor
ICAgICAgICBlbHNlIGlmIChyZXBseS0+ZXJyb3IoKSA9PSBRTmV0d29ya1JlcGx5OjpTc2xIYW5k
c2hha2VGYWlsZWRFcnJvcikgZmFpbCh0cigiVmVyaWZ5IHRoZSBob3N0IGNlcnRpZmljYXRlIGZp
bmdlcnByaW50IGluIENvbmZpZ3VyZSIpKTsKKyAgICAgICAgZWxzZSBpZiAocmVwbHktPmVycm9y
KCkgIT0gUU5ldHdvcmtSZXBseTo6Tm9FcnJvciB8fCBzdGF0dXMgIT0gMjAwKSBmYWlsKHRyKCJI
b3N0IHN0YXRzIHVuYXZhaWxhYmxlOiBjaGVjayBjb25uZWN0aW9uIGFuZCByZWFsdGltZSBzdGF0
cyBzZXR0aW5nIikpOworICAgICAgICBlbHNlIHsKKyAgICAgICAgICAgIGRhdGEtPmFwcGVuZChy
ZXBseS0+cmVhZEFsbCgpKTsgUVN0cmluZyBlcnJvcjsKKyAgICAgICAgICAgIGF1dG8gcGFyc2Vk
ID0gcGFyc2VTdGF0cygqZGF0YSwgJmVycm9yKTsKKyAgICAgICAgICAgIGlmICghZXJyb3IuaXNF
bXB0eSgpKSBmYWlsKGVycm9yKTsKKyAgICAgICAgICAgIGVsc2UgeyBtX3N0YXRzVGltZXIuc2V0
SW50ZXJ2YWwoMjAwMCk7IG1fc3RhdHMgPSBwYXJzZWQ7IG1fc3RhdHVzID0gdHIoIkhPU1Qg4oCi
IHJlY2VpdmVkICUxIikuYXJnKFFEYXRlVGltZTo6Y3VycmVudERhdGVUaW1lKCkudG9TdHJpbmco
ImhoOm1tOnNzIikpOyBlbWl0IHN0YXRzQ2hhbmdlZCgpOyB9CisgICAgICAgIH0KKyAgICAgICAg
cmVwbHktPmRlbGV0ZUxhdGVyKCk7CisgICAgfSk7CisgICAgLy8gQWJzb2x1dGUgcmVxdWVzdCBi
b3VuZCBldmVuIGlmIGEgcGVlciBrZWVwcyBzZW5kaW5nIG9jY2FzaW9uYWwgYnl0ZXMuCisgICAg
UVRpbWVyOjpzaW5nbGVTaG90KDM1MDAsIHJlcGx5LCBbcmVwbHldIHsgaWYgKCFyZXBseS0+aXNG
aW5pc2hlZCgpKSByZXBseS0+YWJvcnQoKTsgfSk7Cit9CitRVmFyaWFudE1hcCBDcmltc29uU3Rh
dHVzOjpyZWFkTG9jYWwoY29uc3QgUVN0cmluZyYgcm9vdCkgeworICAgIFFWYXJpYW50TWFwIG91
dDsgUVN0cmluZ0xpc3QgbmV0d29ya3M7CisgICAgZm9yIChjb25zdCBhdXRvJiBuYW1lIDogUURp
cihyb290ICsgIi9jbGFzcy9uZXQiKS5lbnRyeUxpc3QoUURpcjo6RGlycyB8IFFEaXI6Ok5vRG90
QW5kRG90RG90KSkgeworICAgICAgICBpZiAobmFtZSA9PSAibG8iIHx8IHJlYWQocm9vdCArICIv
Y2xhc3MvbmV0LyIgKyBuYW1lICsgIi9vcGVyc3RhdGUiKSAhPSAidXAiKSBjb250aW51ZTsKKyAg
ICAgICAgbmV0d29ya3MgPDwgbmFtZTsKKyAgICB9CisgICAgb3V0WyJjb25uZWN0ZWQiXSA9ICFu
ZXR3b3Jrcy5pc0VtcHR5KCk7IG91dFsibmV0d29yayJdID0gbmV0d29ya3MuaXNFbXB0eSgpID8g
dHIoIk5vIGFjdGl2ZSBuZXR3b3JrIGxpbmsiKSA6IG5ldHdvcmtzLmpvaW4oIiwgIik7CisgICAg
Ly8gTGluayBzdGF0dXMgaXMgaW50ZW50aW9uYWxseSBub3QgcHJlc2VudGVkIGFzIGludGVybmV0
IHJlYWNoYWJpbGl0eS4KKyAgICBvdXRbImJhdHRlcnlQZXJjZW50Il0gPSAtMTsgb3V0WyJiYXR0
ZXJ5U3RhdGUiXSA9IHRyKCJCYXR0ZXJ5IHVuYXZhaWxhYmxlIik7CisgICAgZm9yIChjb25zdCBh
dXRvJiBuYW1lIDogUURpcihyb290ICsgIi9jbGFzcy9wb3dlcl9zdXBwbHkiKS5lbnRyeUxpc3Qo
UURpcjo6RGlycyB8IFFEaXI6Ok5vRG90QW5kRG90RG90KSkgeworICAgICAgICBjb25zdCBhdXRv
IGJhc2UgPSByb290ICsgIi9jbGFzcy9wb3dlcl9zdXBwbHkvIiArIG5hbWUgKyAiLyI7CisgICAg
ICAgIGlmIChyZWFkKGJhc2UgKyAidHlwZSIpICE9ICJCYXR0ZXJ5IiB8fCByZWFkKGJhc2UgKyAi
cHJlc2VudCIpID09ICIwIikgY29udGludWU7CisgICAgICAgIGJvb2wgb2s7IGludCBjYXAgPSBy
ZWFkKGJhc2UgKyAiY2FwYWNpdHkiKS50b0ludCgmb2spOworICAgICAgICBpZiAob2sgJiYgY2Fw
ID49IDAgJiYgY2FwIDw9IDEwMCkgb3V0WyJiYXR0ZXJ5UGVyY2VudCJdID0gY2FwOworICAgICAg
ICBjb25zdCBhdXRvIHN0YXRlID0gcmVhZChiYXNlICsgInN0YXR1cyIpOyBvdXRbImJhdHRlcnlT
dGF0ZSJdID0gc3RhdGUuaXNFbXB0eSgpID8gdHIoIlVua25vd24iKSA6IHN0YXRlOyBicmVhazsK
KyAgICB9CisgICAgcmV0dXJuIG91dDsKK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6cmVmcmVzaExv
Y2FsKCkgeworICAgIG1fbG9jYWwgPSByZWFkTG9jYWwoKTsgbV9sb2NhbFsid2lmaVNpZ25hbCJd
ID0gLTE7IGVtaXQgbG9jYWxDaGFuZ2VkKCk7CisgICAgaWYgKG1fd2lmaS5zdGF0ZSgpID09IFFQ
cm9jZXNzOjpOb3RSdW5uaW5nKSB7CisgICAgICAgIG1fd2lmaS5zdGFydCgibm1jbGkiLCB7Ii10
IiwgIi0tZXNjYXBlIiwgIm5vIiwgIi1mIiwgIkFDVElWRSxTSUdOQUwsU1NJRCIsICJkZXZpY2Ui
LCAid2lmaSIsICJsaXN0IiwgIi0tcmVzY2FuIiwgIm5vIn0pOworICAgICAgICBRVGltZXI6OnNp
bmdsZVNob3QoMjAwMCwgJm1fd2lmaSwgW3RoaXNdIHsgaWYgKG1fd2lmaS5zdGF0ZSgpICE9IFFQ
cm9jZXNzOjpOb3RSdW5uaW5nKSBtX3dpZmkua2lsbCgpOyB9KTsKKyAgICB9Cit9CisKK3N0YXRp
YyB2b2lkIHJlZ2lzdGVyQ3JpbXNvblN0YXR1cygpIHsKKyAgICBxbWxSZWdpc3RlclNpbmdsZXRv
blR5cGU8Q3JpbXNvblN0YXR1cz4oIkNyaW1zb25TdGF0dXMiLCAxLCAwLCAiQ3JpbXNvblN0YXR1
cyIsCisgICAgICAgIFtdKFFRbWxFbmdpbmUqLCBRSlNFbmdpbmUqKSAtPiBRT2JqZWN0KiB7IHJl
dHVybiBuZXcgQ3JpbXNvblN0YXR1cygpOyB9KTsKK30KK1FfQ09SRUFQUF9TVEFSVFVQX0ZVTkNU
SU9OKHJlZ2lzdGVyQ3JpbXNvblN0YXR1cykKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9j
cmltc29uc3RhdHVzLmggYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5oCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjJkYWMwZDEKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5oCkBAIC0wLDAgKzEsNTIgQEAKKyNwcmFnbWEg
b25jZQorI2luY2x1ZGUgPFFPYmplY3Q+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CisjaW5jbHVk
ZSA8UVRpbWVyPgorI2luY2x1ZGUgPFFOZXR3b3JrQWNjZXNzTWFuYWdlcj4KKyNpbmNsdWRlIDxR
UG9pbnRlcj4KKyNpbmNsdWRlIDxRTmV0d29ya1JlcGx5PgorI2luY2x1ZGUgPFFQcm9jZXNzPgor
CisvLyBPcHRpb25hbCBsYXVuY2hlciBzdGF0dXMuIE5ldmVyIHBhcnRpY2lwYXRlcyBpbiB0aGUg
c3RyZWFtaW5nL2RlY29kZXIgcGF0aC4KK2NsYXNzIENyaW1zb25TdGF0dXMgOiBwdWJsaWMgUU9i
amVjdCB7CisgICAgUV9PQkpFQ1QKKyAgICBRX1BST1BFUlRZKFFWYXJpYW50TWFwIGxvY2FsIFJF
QUQgbG9jYWwgTk9USUZZIGxvY2FsQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFWYXJpYW50TWFw
IHN0YXRzIFJFQUQgc3RhdHMgTk9USUZZIHN0YXRzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFT
dHJpbmcgc3RhdHVzIFJFQUQgc3RhdHVzIE5PVElGWSBzdGF0c0NoYW5nZWQpCisgICAgUV9QUk9Q
RVJUWShRU3RyaW5nIGVuZHBvaW50IFJFQUQgZW5kcG9pbnQgTk9USUZZIGNvbmZpZ0NoYW5nZWQp
CisgICAgUV9QUk9QRVJUWShRU3RyaW5nIGZpbmdlcnByaW50IFJFQUQgZmluZ2VycHJpbnQgTk9U
SUZZIGNvbmZpZ0NoYW5nZWQpCisgICAgUV9QUk9QRVJUWShib29sIGNvbmZpZ3VyZWQgUkVBRCBj
b25maWd1cmVkIE5PVElGWSBjb25maWdDaGFuZ2VkKQorcHVibGljOgorICAgIGV4cGxpY2l0IENy
aW1zb25TdGF0dXMoUU9iamVjdCogcGFyZW50ID0gbnVsbHB0cik7CisgICAgfkNyaW1zb25TdGF0
dXMoKSBvdmVycmlkZTsKKyAgICBRVmFyaWFudE1hcCBsb2NhbCgpIGNvbnN0IHsgcmV0dXJuIG1f
bG9jYWw7IH0KKyAgICBRVmFyaWFudE1hcCBzdGF0cygpIGNvbnN0IHsgcmV0dXJuIG1fc3RhdHM7
IH0KKyAgICBRU3RyaW5nIHN0YXR1cygpIGNvbnN0IHsgcmV0dXJuIG1fc3RhdHVzOyB9CisgICAg
UVN0cmluZyBlbmRwb2ludCgpIGNvbnN0IHsgcmV0dXJuIG1fZW5kcG9pbnQ7IH0KKyAgICBRU3Ry
aW5nIGZpbmdlcnByaW50KCkgY29uc3QgeyByZXR1cm4gbV9waW47IH0KKyAgICBib29sIGNvbmZp
Z3VyZWQoKSBjb25zdCB7IHJldHVybiAhbV9lbmRwb2ludC5pc0VtcHR5KCkgJiYgIW1fdG9rZW4u
aXNFbXB0eSgpOyB9CisgICAgUV9JTlZPS0FCTEUgdm9pZCBzZWxlY3RIb3N0KFFTdHJpbmcgaWQs
IFFTdHJpbmcgc3VnZ2VzdGVkVXJsKTsKKyAgICBRX0lOVk9LQUJMRSBib29sIGNvbmZpZ3VyZShR
U3RyaW5nIHVybCwgUVN0cmluZyB0b2tlbiwgUVN0cmluZyBwaW4pOworICAgIFFfSU5WT0tBQkxF
IHZvaWQgc2V0VmlzaWJsZShib29sIHZpc2libGUpOworICAgIFFfSU5WT0tBQkxFIHZvaWQgcmVm
cmVzaCgpOworICAgIHN0YXRpYyBRVmFyaWFudE1hcCBwYXJzZVN0YXRzKGNvbnN0IFFCeXRlQXJy
YXkmIGJ5dGVzLCBRU3RyaW5nKiBlcnJvcik7CisgICAgc3RhdGljIGJvb2wgdmFsaWRFbmRwb2lu
dChjb25zdCBRU3RyaW5nJiB1cmwpOworICAgIHN0YXRpYyBRU3RyaW5nIG5vcm1hbGl6ZWRQaW4o
UVN0cmluZyBwaW4pOworICAgIHN0YXRpYyBRVmFyaWFudE1hcCByZWFkTG9jYWwoY29uc3QgUVN0
cmluZyYgc3lzUm9vdCA9ICIvc3lzIik7CitzaWduYWxzOgorICAgIHZvaWQgbG9jYWxDaGFuZ2Vk
KCk7CisgICAgdm9pZCBzdGF0c0NoYW5nZWQoKTsKKyAgICB2b2lkIGNvbmZpZ0NoYW5nZWQoKTsK
K3ByaXZhdGU6CisgICAgdm9pZCByZWZyZXNoTG9jYWwoKTsKKyAgICB2b2lkIGZhaWwoUVN0cmlu
ZyBtZXNzYWdlKTsKKyAgICB2b2lkIGNhbmNlbCgpOworICAgIFFTdHJpbmcgY29uZmlnRmlsZSgp
IGNvbnN0OworICAgIFFTdHJpbmcgbV9ob3N0LCBtX2VuZHBvaW50LCBtX3Rva2VuLCBtX3Bpbiwg
bV9zdGF0dXMgPSAiQ2hvb3NlIGEgaG9zdCB0byB2aWV3IGhhcmR3YXJlIHN0YXRzIjsKKyAgICBR
VmFyaWFudE1hcCBtX2xvY2FsLCBtX3N0YXRzOworICAgIFFUaW1lciBtX2xvY2FsVGltZXIsIG1f
c3RhdHNUaW1lcjsKKyAgICBRUHJvY2VzcyBtX3dpZmk7CisgICAgUU5ldHdvcmtBY2Nlc3NNYW5h
Z2VyIG1fbmV0d29yazsKKyAgICBRUG9pbnRlcjxRTmV0d29ya1JlcGx5PiBtX3JlcGx5OworICAg
IGJvb2wgbV92aXNpYmxlID0gZmFsc2U7Cit9OwpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9z
L2VjbGlwc2Vwcm9maWxlcy5jcHAgYi9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmNw
cApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5hNjNkNTJkCi0tLSAvZGV2L251
bGwKKysrIGIvYXBwL21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5jcHAKQEAgLTAsMCArMSw0
MSBAQAorI2luY2x1ZGUgImVjbGlwc2Vwcm9maWxlcy5oIgorI2luY2x1ZGUgPFFDcnlwdG9ncmFw
aGljSGFzaD4KKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUgPFFRbWxFbmdp
bmU+CitRU3RyaW5nIEVjbGlwc2VQcm9maWxlczo6a2V5KFFTdHJpbmcgaG9zdCwgUVN0cmluZyBu
YW1lKSB7CisgICAgcmV0dXJuICJlY2xpcHNlL3Byb2ZpbGVzLyIgKyBRU3RyaW5nOjpmcm9tTGF0
aW4xKFFDcnlwdG9ncmFwaGljSGFzaDo6aGFzaChob3N0LnRvVXRmOCgpLCBRQ3J5cHRvZ3JhcGhp
Y0hhc2g6OlNoYTI1NikudG9IZXgoKSkgKyAiLyIgKyBRU3RyaW5nOjpmcm9tTGF0aW4xKFFDcnlw
dG9ncmFwaGljSGFzaDo6aGFzaChuYW1lLnRyaW1tZWQoKS50b1V0ZjgoKSwgUUNyeXB0b2dyYXBo
aWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpOworfQorYm9vbCBFY2xpcHNlUHJvZmlsZXM6OnZhbGlk
KGNvbnN0IFFWYXJpYW50TWFwJiB2YWx1ZXMpIHsKKyAgICBjb25zdCBRTWFwPFFTdHJpbmcsUVBh
aXI8aW50LGludD4+IHJhbmdlcyA9IHt7IndpZHRoIix7MzIwLDc2ODB9fSwgeyJoZWlnaHQiLHsy
MDAsNDMyMH19LCB7ImZwcyIsezEsMjQwfX0sIHsiYml0cmF0ZUticHMiLHs1MDAsMTUwMDAwfX19
OworICAgIGlmICh2YWx1ZXMuc2l6ZSgpICE9IHJhbmdlcy5zaXplKCkpIHJldHVybiBmYWxzZTsK
KyAgICBmb3IgKGF1dG8gaSA9IHJhbmdlcy5iZWdpbigpOyBpICE9IHJhbmdlcy5lbmQoKTsgKytp
KSB7CisgICAgICAgIGJvb2wgb2s7IGF1dG8gbiA9IHZhbHVlcy52YWx1ZShpLmtleSgpKS50b0lu
dCgmb2spOworICAgICAgICBpZiAoIW9rIHx8IG4gPCBpLnZhbHVlKCkuZmlyc3QgfHwgbiA+IGku
dmFsdWUoKS5zZWNvbmQpIHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgcmV0dXJuIHRydWU7Cit9
Citib29sIEVjbGlwc2VQcm9maWxlczo6c2F2ZShRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSwg
UVZhcmlhbnRNYXAgdmFsdWVzKSB7CisgICAgbmFtZSA9IG5hbWUudHJpbW1lZCgpOworICAgIGlm
IChob3N0LnNpemUoKSA+IDI1NiB8fCBuYW1lLmlzRW1wdHkoKSB8fCBuYW1lLnNpemUoKSA+IDQ4
IHx8ICF2YWxpZCh2YWx1ZXMpKSByZXR1cm4gZmFsc2U7CisgICAgaWYgKCFuYW1lcyhob3N0KS5j
b250YWlucyhuYW1lKSAmJiBuYW1lcyhob3N0KS5zaXplKCkgPj0gMzIpIHJldHVybiBmYWxzZTsK
KyAgICBRU2V0dGluZ3Mgc2V0dGluZ3M7IHNldHRpbmdzLnNldFZhbHVlKGtleShob3N0LG5hbWUp
KyIvbmFtZSIsbmFtZSk7IHNldHRpbmdzLnNldFZhbHVlKGtleShob3N0LG5hbWUpKyIvdmFsdWVz
Iix2YWx1ZXMpOyBzZXR0aW5ncy5zeW5jKCk7CisgICAgcmV0dXJuIHNldHRpbmdzLnN0YXR1cygp
ID09IFFTZXR0aW5nczo6Tm9FcnJvcjsKK30KK1FWYXJpYW50TWFwIEVjbGlwc2VQcm9maWxlczo6
bG9hZChRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSkgeworICAgIFFTZXR0aW5ncyBzZXR0aW5n
czsgYXV0byB2YWx1ZSA9IHNldHRpbmdzLnZhbHVlKGtleShob3N0LG5hbWUpKyIvdmFsdWVzIiku
dG9NYXAoKTsKKyAgICByZXR1cm4gdmFsaWQodmFsdWUpID8gdmFsdWUgOiBRVmFyaWFudE1hcCgp
OworfQorYm9vbCBFY2xpcHNlUHJvZmlsZXM6OnJlbW92ZShRU3RyaW5nIGhvc3QsIFFTdHJpbmcg
bmFtZSwgYm9vbCBjb25maXJtZWQpIHsKKyAgICBpZiAoIWNvbmZpcm1lZCkgcmV0dXJuIGZhbHNl
OworICAgIFFTZXR0aW5ncyBzZXR0aW5nczsgc2V0dGluZ3MucmVtb3ZlKGtleShob3N0LG5hbWUp
KTsgc2V0dGluZ3Muc3luYygpOyByZXR1cm4gc2V0dGluZ3Muc3RhdHVzKCkgPT0gUVNldHRpbmdz
OjpOb0Vycm9yOworfQorUVN0cmluZ0xpc3QgRWNsaXBzZVByb2ZpbGVzOjpuYW1lcyhRU3RyaW5n
IGhvc3QpIHsKKyAgICBRU2V0dGluZ3Mgc2V0dGluZ3M7IHNldHRpbmdzLmJlZ2luR3JvdXAoa2V5
KGhvc3QsICIiKS5zZWN0aW9uKCcvJywwLC0yKSk7CisgICAgUVN0cmluZ0xpc3QgcmVzdWx0Owor
ICAgIGZvciAoY29uc3QgYXV0byYgY2hpbGQgOiBzZXR0aW5ncy5jaGlsZEdyb3VwcygpKSB7IGF1
dG8gbmFtZSA9IHNldHRpbmdzLnZhbHVlKGNoaWxkKyIvbmFtZSIpLnRvU3RyaW5nKCk7IGlmICgh
bmFtZS5pc0VtcHR5KCkpIHJlc3VsdC5hcHBlbmQobmFtZSk7IH0KKyAgICByZXN1bHQuc29ydCgp
OyByZXR1cm4gcmVzdWx0OworfQorc3RhdGljIHZvaWQgcmVnaXN0ZXJFY2xpcHNlUHJvZmlsZXMo
KSB7CisgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlPEVjbGlwc2VQcm9maWxlcz4oIkVjbGlw
c2VQcm9maWxlcyIsMSwwLCJFY2xpcHNlUHJvZmlsZXMiLFtdKFFRbWxFbmdpbmUqLFFKU0VuZ2lu
ZSopIC0+IFFPYmplY3QqIHsgcmV0dXJuIG5ldyBFY2xpcHNlUHJvZmlsZXMoKTsgfSk7Cit9CitR
X0NPUkVBUFBfU1RBUlRVUF9GVU5DVElPTihyZWdpc3RlckVjbGlwc2VQcm9maWxlcykKZGlmZiAt
LWdpdCBhL2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuaCBiL2FwcC9tb29ubGlnaHRv
cy9lY2xpcHNlcHJvZmlsZXMuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5k
Mzk4Mzg3Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxl
cy5oCkBAIC0wLDAgKzEsMjcgQEAKKyNwcmFnbWEgb25jZQorI2luY2x1ZGUgPFFPYmplY3Q+Cisj
aW5jbHVkZSA8UVZhcmlhbnRNYXA+CisjaW5jbHVkZSA8UVNldHRpbmdzPgorY2xhc3MgRWNsaXBz
ZVByb2ZpbGVzIDogcHVibGljIFFPYmplY3QgeworICAgIFFfT0JKRUNUCisgICAgUV9QUk9QRVJU
WShpbnQgdGV4dFNjYWxlIFJFQUQgdGV4dFNjYWxlIFdSSVRFIHNldFRleHRTY2FsZSBOT1RJRlkg
YXBwZWFyYW5jZUNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShib29sIHJlZHVjZWRNb3Rpb24gUkVB
RCByZWR1Y2VkTW90aW9uIFdSSVRFIHNldFJlZHVjZWRNb3Rpb24gTk9USUZZIGFwcGVhcmFuY2VD
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBoaWdoQ29udHJhc3QgUkVBRCBoaWdoQ29udHJh
c3QgV1JJVEUgc2V0SGlnaENvbnRyYXN0IE5PVElGWSBhcHBlYXJhbmNlQ2hhbmdlZCkKK3B1Ymxp
YzoKKyAgICBleHBsaWNpdCBFY2xpcHNlUHJvZmlsZXMoUU9iamVjdCogcGFyZW50ID0gbnVsbHB0
cikgOiBRT2JqZWN0KHBhcmVudCkge30KKyAgICBpbnQgdGV4dFNjYWxlKCkgY29uc3QgeyByZXR1
cm4gcUJvdW5kKDEwMCxRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS90ZXh0U2NhbGUiLDEwMCku
dG9JbnQoKSwxMjUpOyB9CisgICAgYm9vbCByZWR1Y2VkTW90aW9uKCkgY29uc3QgeyByZXR1cm4g
UVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvcmVkdWNlZE1vdGlvbiIsZmFsc2UpLnRvQm9vbCgp
OyB9CisgICAgYm9vbCBoaWdoQ29udHJhc3QoKSBjb25zdCB7IHJldHVybiBRU2V0dGluZ3MoKS52
YWx1ZSgiZWNsaXBzZS9oaWdoQ29udHJhc3QiLGZhbHNlKS50b0Jvb2woKTsgfQorICAgIHZvaWQg
c2V0VGV4dFNjYWxlKGludCB2YWx1ZSkgeyBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS90
ZXh0U2NhbGUiLHFCb3VuZCgxMDAsdmFsdWUsMTI1KSk7IGVtaXQgYXBwZWFyYW5jZUNoYW5nZWQo
KTsgfQorICAgIHZvaWQgc2V0UmVkdWNlZE1vdGlvbihib29sIHZhbHVlKSB7IFFTZXR0aW5ncygp
LnNldFZhbHVlKCJlY2xpcHNlL3JlZHVjZWRNb3Rpb24iLHZhbHVlKTsgZW1pdCBhcHBlYXJhbmNl
Q2hhbmdlZCgpOyB9CisgICAgdm9pZCBzZXRIaWdoQ29udHJhc3QoYm9vbCB2YWx1ZSkgeyBRU2V0
dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS9oaWdoQ29udHJhc3QiLHZhbHVlKTsgZW1pdCBhcHBl
YXJhbmNlQ2hhbmdlZCgpOyB9CisgICAgUV9JTlZPS0FCTEUgYm9vbCBzYXZlKFFTdHJpbmcgaG9z
dCwgUVN0cmluZyBuYW1lLCBRVmFyaWFudE1hcCB2YWx1ZXMpOworICAgIFFfSU5WT0tBQkxFIFFW
YXJpYW50TWFwIGxvYWQoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUpOworICAgIFFfSU5WT0tB
QkxFIGJvb2wgcmVtb3ZlKFFTdHJpbmcgaG9zdCwgUVN0cmluZyBuYW1lLCBib29sIGNvbmZpcm1l
ZCk7CisgICAgUV9JTlZPS0FCTEUgUVN0cmluZ0xpc3QgbmFtZXMoUVN0cmluZyBob3N0KTsKKyAg
ICBzdGF0aWMgYm9vbCB2YWxpZChjb25zdCBRVmFyaWFudE1hcCYgdmFsdWVzKTsKK3NpZ25hbHM6
CisgICAgdm9pZCBhcHBlYXJhbmNlQ2hhbmdlZCgpOworcHJpdmF0ZToKKyAgICBzdGF0aWMgUVN0
cmluZyBrZXkoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUpOworfTsKZGlmZiAtLWdpdCBhL2Fw
cC9tb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9sb2NhbGhh
cmR3YXJlLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi40MTNjYzYxCi0t
LSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuY3BwCkBAIC0w
LDAgKzEsMTIzIEBACisjaW5jbHVkZSAibG9jYWxoYXJkd2FyZS5oIgorI2luY2x1ZGUgPFF0TWF0
aD4KKyNpbmNsdWRlIDxRRmlsZT4KKyNpbmNsdWRlIDxRRGlyPgorI2luY2x1ZGUgPFFTZXQ+Cisj
aW5jbHVkZSA8UVN0b3JhZ2VJbmZvPgorI2luY2x1ZGUgPFFGaWxlSW5mbz4KKyNpbmNsdWRlIDxR
RWxhcHNlZFRpbWVyPgorI2luY2x1ZGUgPFFNdXRleD4KKyNpbmNsdWRlIDxRTXV0ZXhMb2NrZXI+
CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgorI2lu
Y2x1ZGUgPFFSZWd1bGFyRXhwcmVzc2lvbj4KKworc3RhdGljIFFTdHJpbmcgcmVhZChjb25zdCBR
U3RyaW5nJiBwYXRoKSB7IFFGaWxlIGYocGF0aCk7IHJldHVybiBmLm9wZW4oUUlPRGV2aWNlOjpS
ZWFkT25seSkgPyBRU3RyaW5nOjpmcm9tVXRmOChmLnJlYWQoMzI3NjgpKS50cmltbWVkKCkgOiBR
U3RyaW5nKCk7IH0KK3N0YXRpYyBkb3VibGUgbnVtYmVyKGNvbnN0IFFTdHJpbmcmIHBhdGgpIHsg
Ym9vbCBvazsgZG91YmxlIG49cmVhZChwYXRoKS50b0RvdWJsZSgmb2spOyByZXR1cm4gb2sgJiYg
cUlzRmluaXRlKG4pID8gbiA6IC0xOyB9CitMb2NhbEhhcmR3YXJlOjpMb2NhbEhhcmR3YXJlKFFP
YmplY3QqIHBhcmVudCk6UU9iamVjdChwYXJlbnQpIHsgbV90aW1lci5zZXRJbnRlcnZhbChyZWZy
ZXNoU2Vjb25kcygpKjEwMDApOyBjb25uZWN0KCZtX3RpbWVyLCZRVGltZXI6OnRpbWVvdXQsdGhp
cywmTG9jYWxIYXJkd2FyZTo6cmVmcmVzaCk7IH0KK3ZvaWQgTG9jYWxIYXJkd2FyZTo6c2V0QWN0
aXZlKGJvb2wgYWN0aXZlKSB7IGlmIChhY3RpdmUpIHsgcmVmcmVzaCgpOyBtX3RpbWVyLnN0YXJ0
KCk7IH0gZWxzZSBtX3RpbWVyLnN0b3AoKTsgfQordm9pZCBMb2NhbEhhcmR3YXJlOjpyZWZyZXNo
KCkgeyBtX3JlYWRpbmdzPXNhbXBsZSgpOyBtX2hpc3RvcnkuYXBwZW5kKG1fcmVhZGluZ3MpOyB3
aGlsZShtX2hpc3Rvcnkuc2l6ZSgpPjYwKSBtX2hpc3RvcnkucmVtb3ZlRmlyc3QoKTsgZW1pdCBj
aGFuZ2VkKCk7IH0KK3ZvaWQgTG9jYWxIYXJkd2FyZTo6c2V0RmllbGRzKFFTdHJpbmdMaXN0IHYp
IHsgUVN0cmluZ0xpc3QgY2xlYW47IGZvcihjb25zdCBRU3RyaW5nJiBrZXk6UVN0cmluZ0xpc3R7
ImNwdSIsIm1lbW9yeSIsInRlbXBlcmF0dXJlIiwiZ3B1IiwibmV0d29yayIsImJhdHRlcnkiLCJz
dG9yYWdlIn0pIGlmKHYuY29udGFpbnMoa2V5KSkgY2xlYW4uYXBwZW5kKGtleSk7IHNhdmUoImxv
Y2FsRmllbGRzIixjbGVhbik7IH0KKworUVZhcmlhbnRNYXAgTG9jYWxIYXJkd2FyZTo6c2FtcGxl
KGNvbnN0IFFTdHJpbmcmIHJvb3QpIHsKKyAgICAvLyBTaGFyZWQgY2FjaGU6IFNldHRpbmdzIGFu
ZCB0aGUgZGVjb2RlciByZXVzZSBvbmUgYm91bmRlZCwgcmVhZC1vbmx5IHNhbXBsZS4KKyAgICBz
dGF0aWMgUU11dGV4IG11dGV4OyBRTXV0ZXhMb2NrZXIgbG9ja2VyKCZtdXRleCk7CisgICAgc3Rh
dGljIFFFbGFwc2VkVGltZXIgY2xvY2s7IGlmKCFjbG9jay5pc1ZhbGlkKCkpIGNsb2NrLnN0YXJ0
KCk7CisgICAgc3RhdGljIFFNYXA8UVN0cmluZyxRVmFyaWFudE1hcD4gcHJldmlvdXMsIGNhY2hl
ZDsKKyAgICBzdGF0aWMgUU1hcDxRU3RyaW5nLHFpbnQ2ND4gbGFzdDsKKyAgICBxaW50NjQgbm93
PWNsb2NrLmVsYXBzZWQoKTsKKyAgICBpbnQgaW50ZXJ2YWw9cUJvdW5kKDEsUVNldHRpbmdzKCku
dmFsdWUoImVjbGlwc2UvaGFyZHdhcmVSZWZyZXNoIiwyKS50b0ludCgpLDUpKjEwMDA7CisgICAg
aWYoY2FjaGVkLmNvbnRhaW5zKHJvb3QpICYmIG5vdy1sYXN0LnZhbHVlKHJvb3QpPGludGVydmFs
KSByZXR1cm4gY2FjaGVkLnZhbHVlKHJvb3QpOworICAgIFFWYXJpYW50TWFwIHJlc3VsdCwgY291
bnRlcnM7CisgICAgYXV0byBvbGQ9cHJldmlvdXMudmFsdWUocm9vdCk7IGRvdWJsZSBzZWNvbmRz
PShub3ctbGFzdC52YWx1ZShyb290KSkvMTAwMC4wOworICAgIGF1dG8gc3RhdD1yZWFkKHJvb3Qr
Ii9wcm9jL3N0YXQiKS5zZWN0aW9uKCdcbicsMCwwKS5zaW1wbGlmaWVkKCkuc3BsaXQoJyAnKTsK
KyAgICBpZihzdGF0LnNpemUoKT49OSAmJiBzdGF0WzBdPT0iY3B1IikgeworICAgICAgICBxdWlu
dDY0IHRvdGFsPTA7IGZvcihpbnQgaT0xO2k8PTg7aSsrKSB0b3RhbCs9c3RhdFtpXS50b1VMb25n
TG9uZygpOworICAgICAgICBxdWludDY0IGlkbGU9c3RhdFs0XS50b1VMb25nTG9uZygpK3N0YXRb
NV0udG9VTG9uZ0xvbmcoKTsKKyAgICAgICAgY291bnRlcnNbInRvdGFsIl09dG90YWw7IGNvdW50
ZXJzWyJpZGxlIl09aWRsZTsKKyAgICAgICAgcXVpbnQ2NCBiZWZvcmU9b2xkLnZhbHVlKCJ0b3Rh
bCIpLnRvVUxvbmdMb25nKCk7CisgICAgICAgIGlmKG9sZC5jb250YWlucygidG90YWwiKSAmJiB0
b3RhbD5iZWZvcmUgJiYgaWRsZT49b2xkLnZhbHVlKCJpZGxlIikudG9VTG9uZ0xvbmcoKSkgcmVz
dWx0WyJjcHVQZXJjZW50Il09cUJvdW5kKDAuMCwxMDAuMCooMS4wLWRvdWJsZShpZGxlLW9sZFsi
aWRsZSJdLnRvVUxvbmdMb25nKCkpL2RvdWJsZSh0b3RhbC1iZWZvcmUpKSwxMDAuMCk7CisgICAg
fQorICAgIFFNYXA8UVN0cmluZyxxdWludDY0PiBtZW1vcnk7CisgICAgZm9yKGNvbnN0IFFTdHJp
bmcmIGxpbmU6cmVhZChyb290KyIvcHJvYy9tZW1pbmZvIikuc3BsaXQoJ1xuJykpIHsgYXV0byBw
YXJ0cz1saW5lLnNpbXBsaWZpZWQoKS5zcGxpdCgnICcpOyBpZihwYXJ0cy5zaXplKCk+PTIpIG1l
bW9yeVtwYXJ0c1swXV09cGFydHNbMV0udG9VTG9uZ0xvbmcoKSoxMDI0OyB9CisgICAgcXVpbnQ2
NCB0b3RhbD1tZW1vcnkudmFsdWUoIk1lbVRvdGFsOiIpLCBhdmFpbGFibGU9bWVtb3J5LnZhbHVl
KCJNZW1BdmFpbGFibGU6Iik7CisgICAgaWYodG90YWwgJiYgYXZhaWxhYmxlPD10b3RhbCAmJiBt
ZW1vcnkuY29udGFpbnMoIk1lbUF2YWlsYWJsZToiKSkgeyByZXN1bHRbIm1lbW9yeVVzZWRHaUIi
XT1kb3VibGUodG90YWwtYXZhaWxhYmxlKS8oMTAyNCoxMDI0KjEwMjQpOyByZXN1bHRbIm1lbW9y
eVRvdGFsR2lCIl09ZG91YmxlKHRvdGFsKS8oMTAyNCoxMDI0KjEwMjQpOyByZXN1bHRbIm1lbW9y
eVBlcmNlbnQiXT0xMDAuMCoodG90YWwtYXZhaWxhYmxlKS90b3RhbDsgfQorICAgIGlmKG1lbW9y
eS5jb250YWlucygiU3dhcFRvdGFsOiIpKSByZXN1bHRbInN3YXBVc2VkTWlCIl09ZG91YmxlKG1l
bW9yeS52YWx1ZSgiU3dhcFRvdGFsOiIpLXFNaW4obWVtb3J5LnZhbHVlKCJTd2FwVG90YWw6Iiks
bWVtb3J5LnZhbHVlKCJTd2FwRnJlZToiKSkpLygxMDI0KjEwMjQpOworICAgIGRvdWJsZSBmcmVx
dWVuY3k9bnVtYmVyKHJvb3QrIi9zeXMvZGV2aWNlcy9zeXN0ZW0vY3B1L2NwdTAvY3B1ZnJlcS9z
Y2FsaW5nX2N1cl9mcmVxIik7IGlmKGZyZXF1ZW5jeT4wKSByZXN1bHRbImNwdU1IeiJdPWZyZXF1
ZW5jeS8xMDAwOworICAgIGRvdWJsZSB0ZW1wZXJhdHVyZT0tMSwgZmFuPS0xOworICAgIFFEaXIg
aHcocm9vdCsiL3N5cy9jbGFzcy9od21vbiIpOworICAgIGZvcihjb25zdCBRU3RyaW5nJiBkZXZp
Y2U6aHcuZW50cnlMaXN0KFFEaXI6OkRpcnN8UURpcjo6Tm9Eb3RBbmREb3REb3QpKSB7CisgICAg
ICAgIFFEaXIgc2Vuc29ycyhody5maWxlUGF0aChkZXZpY2UpKTsgUVN0cmluZyBuYW1lPXJlYWQo
c2Vuc29ycy5maWxlUGF0aCgibmFtZSIpKTsKKyAgICAgICAgZm9yKGNvbnN0IFFTdHJpbmcmIGZp
bGU6c2Vuc29ycy5lbnRyeUxpc3QoeyJ0ZW1wKl9pbnB1dCIsImZhbipfaW5wdXQifSxRRGlyOjpG
aWxlcykpIHsKKyAgICAgICAgICAgIGRvdWJsZSB2YWx1ZT1udW1iZXIoc2Vuc29ycy5maWxlUGF0
aChmaWxlKSk7CisgICAgICAgICAgICBpZihmaWxlLnN0YXJ0c1dpdGgoInRlbXAiKSAmJiAobmFt
ZT09ImNvcmV0ZW1wIiB8fCBuYW1lPT0iazEwdGVtcCIpICYmIHZhbHVlPj0wICYmIHZhbHVlPD0x
NTAwMDApIHRlbXBlcmF0dXJlPXFNYXgodGVtcGVyYXR1cmUsdmFsdWUvMTAwMCk7CisgICAgICAg
ICAgICBpZihmaWxlLnN0YXJ0c1dpdGgoImZhbiIpICYmIHZhbHVlPj0wICYmIHZhbHVlPDMwMDAw
KSBmYW49cU1heChmYW4sdmFsdWUpOworICAgICAgICB9CisgICAgfQorICAgIGlmKHRlbXBlcmF0
dXJlPj0wKSByZXN1bHRbInRlbXBlcmF0dXJlQyJdPXRlbXBlcmF0dXJlOworICAgIGlmKGZhbj49
MCkgcmVzdWx0WyJmYW5SUE0iXT1mYW47CisgICAgUURpciBkcm0ocm9vdCsiL3N5cy9jbGFzcy9k
cm0iKTsKKyAgICBmb3IoY29uc3QgUVN0cmluZyYgY2FyZDpkcm0uZW50cnlMaXN0KHsiY2FyZFsw
LTldKiJ9LFFEaXI6OkRpcnN8UURpcjo6Tm9Eb3RBbmREb3REb3QpKSB7IGRvdWJsZSBidXN5PW51
bWJlcihkcm0uZmlsZVBhdGgoY2FyZCsiL2RldmljZS9ncHVfYnVzeV9wZXJjZW50IikpOyBpZihi
dXN5Pj0wICYmIGJ1c3k8PTEwMCkgeyByZXN1bHRbImdwdVBlcmNlbnQiXT1idXN5OyBicmVhazsg
fSB9CisgICAgLy8gRFJNIGZkaW5mbyBpcyB1bnByaXZpbGVnZWQsIHJlYWQtb25seSBhbmQgc2Nv
cGVkIHRvIHRoaXMgRWNsaXBzZSBwcm9jZXNzLgorICAgIC8vIERlZHVwbGljYXRlIGRlc2NyaXB0
b3JzIGJlbG9uZ2luZyB0byB0aGUgc2FtZSBEUk0gY2xpZW50OyBuZXZlciBjYWxsIHRoaXMgc3lz
dGVtLXdpZGUgR1BVIGxvYWQuCisgICAgcXVpbnQ2NCB2aWRlbz0wOyBib29sIGhhc1ZpZGVvPWZh
bHNlOyBRU2V0PFFTdHJpbmc+IGNsaWVudHM7CisgICAgUURpciBkZXNjcmlwdG9ycyhyb290KyIv
cHJvYy9zZWxmL2ZkaW5mbyIpOworICAgIGludCBpbnNwZWN0ZWQ9MDsKKyAgICBmb3IoY29uc3Qg
UVN0cmluZyYgZmlsZTpkZXNjcmlwdG9ycy5lbnRyeUxpc3QoUURpcjo6RmlsZXMpKSB7CisgICAg
ICAgIGlmKCsraW5zcGVjdGVkPjI1NikgYnJlYWs7CisgICAgICAgIFFTdHJpbmcgaW5mbz1yZWFk
KGRlc2NyaXB0b3JzLmZpbGVQYXRoKGZpbGUpKTsKKyAgICAgICAgYXV0byBjbGllbnQ9UVJlZ3Vs
YXJFeHByZXNzaW9uKCJkcm0tY2xpZW50LWlkOlxccyooXFxkKykiKS5tYXRjaChpbmZvKTsKKyAg
ICAgICAgaWYoIWNsaWVudC5oYXNNYXRjaCgpIHx8IGNsaWVudHMuY29udGFpbnMoY2xpZW50LmNh
cHR1cmVkKDEpKSkgY29udGludWU7CisgICAgICAgIGNsaWVudHMuaW5zZXJ0KGNsaWVudC5jYXB0
dXJlZCgxKSk7CisgICAgICAgIGF1dG8gZW5naW5lcz1RUmVndWxhckV4cHJlc3Npb24oImRybS1l
bmdpbmUtdmlkZW8oPzpcXGQrKT86XFxzKihcXGQrKVxccytucyIpLmdsb2JhbE1hdGNoKGluZm8p
OworICAgICAgICB3aGlsZShlbmdpbmVzLmhhc05leHQoKSkgeyB2aWRlbys9ZW5naW5lcy5uZXh0
KCkuY2FwdHVyZWQoMSkudG9VTG9uZ0xvbmcoKTsgaGFzVmlkZW89dHJ1ZTsgfQorICAgIH0KKyAg
ICBpZihoYXNWaWRlbykgeworICAgICAgICBjb3VudGVyc1sidmlkZW8iXT12aWRlbzsKKyAgICAg
ICAgaWYob2xkLmNvbnRhaW5zKCJ2aWRlbyIpICYmIHNlY29uZHM+MCAmJiB2aWRlbz49b2xkLnZh
bHVlKCJ2aWRlbyIpLnRvVUxvbmdMb25nKCkpIHJlc3VsdFsidmlkZW9QZXJjZW50Il09cUJvdW5k
KDAuMCxkb3VibGUodmlkZW8tb2xkWyJ2aWRlbyJdLnRvVUxvbmdMb25nKCkpL3NlY29uZHMvMTAw
MDAwMDAuMCwxMDAuMCk7CisgICAgfQorICAgIFFTdHJpbmcgbmljOworICAgIGZvcihjb25zdCBR
U3RyaW5nJiBsaW5lOnJlYWQocm9vdCsiL3Byb2MvbmV0L3JvdXRlIikuc3BsaXQoJ1xuJykpIHsg
YXV0byBwPWxpbmUuc2ltcGxpZmllZCgpLnNwbGl0KCcgJyk7IGlmKHAuc2l6ZSgpPjMgJiYgcFsx
XT09IjAwMDAwMDAwIikgeyBuaWM9cFswXTsgYnJlYWs7IH0gfQorICAgIGZvcihjb25zdCBRU3Ry
aW5nJiBsaW5lOnJlYWQocm9vdCsiL3Byb2MvbmV0L2RldiIpLnNwbGl0KCdcbicpKSB7CisgICAg
ICAgIGlmKGxpbmUuc2VjdGlvbignOicsMCwwKS50cmltbWVkKCkhPW5pYyB8fCBuaWMuaXNFbXB0
eSgpKSBjb250aW51ZTsKKyAgICAgICAgYXV0byBwPWxpbmUuc2VjdGlvbignOicsMSkuc2ltcGxp
ZmllZCgpLnNwbGl0KCcgJyk7IGlmKHAuc2l6ZSgpPDE2KSBjb250aW51ZTsKKyAgICAgICAgcXVp
bnQ2NCByeD1wWzBdLnRvVUxvbmdMb25nKCksIHR4PXBbOF0udG9VTG9uZ0xvbmcoKTsgY291bnRl
cnNbInJ4Il09cng7IGNvdW50ZXJzWyJ0eCJdPXR4OyBjb3VudGVyc1sibmljIl09bmljOworICAg
ICAgICBpZihzZWNvbmRzPjAgJiYgb2xkLnZhbHVlKCJuaWMiKS50b1N0cmluZygpPT1uaWMgJiYg
cng+PW9sZC52YWx1ZSgicngiKS50b1VMb25nTG9uZygpICYmIHR4Pj1vbGQudmFsdWUoInR4Iiku
dG9VTG9uZ0xvbmcoKSkgeyByZXN1bHRbInJlY2VpdmVNaUIiXT1kb3VibGUocngtb2xkWyJyeCJd
LnRvVUxvbmdMb25nKCkpL3NlY29uZHMvKDEwMjQqMTAyNCk7IHJlc3VsdFsidHJhbnNtaXRNaUIi
XT1kb3VibGUodHgtb2xkWyJ0eCJdLnRvVUxvbmdMb25nKCkpL3NlY29uZHMvKDEwMjQqMTAyNCk7
IH0KKyAgICB9CisgICAgUURpciBwb3dlcihyb290KyIvc3lzL2NsYXNzL3Bvd2VyX3N1cHBseSIp
OworICAgIGZvcihjb25zdCBRU3RyaW5nJiBuYW1lOnBvd2VyLmVudHJ5TGlzdChRRGlyOjpEaXJz
fFFEaXI6Ok5vRG90QW5kRG90RG90KSkgeworICAgICAgICBRU3RyaW5nIHBhdGg9cG93ZXIuZmls
ZVBhdGgobmFtZSk7IGlmKHJlYWQocGF0aCsiL3R5cGUiKSE9IkJhdHRlcnkiKSBjb250aW51ZTsK
KyAgICAgICAgZG91YmxlIHBlcmNlbnQ9bnVtYmVyKHBhdGgrIi9jYXBhY2l0eSIpOyBpZihwZXJj
ZW50Pj0wICYmIHBlcmNlbnQ8PTEwMCkgcmVzdWx0WyJiYXR0ZXJ5UGVyY2VudCJdPXBlcmNlbnQ7
CisgICAgICAgIHJlc3VsdFsiYmF0dGVyeVN0YXRlIl09cmVhZChwYXRoKyIvc3RhdHVzIikubGVm
dCgzMik7IGRvdWJsZSB3YXR0cz1udW1iZXIocGF0aCsiL3Bvd2VyX25vdyIpOyBpZih3YXR0cz49
MCkgcmVzdWx0WyJiYXR0ZXJ5V2F0dHMiXT13YXR0cy8xMDAwMDAwOyBicmVhazsKKyAgICB9Cisg
ICAgaWYocm9vdC5pc0VtcHR5KCkpIHsgUVN0b3JhZ2VJbmZvIGRpc2s9UVN0b3JhZ2VJbmZvOjpy
b290KCk7IGlmKGRpc2suaXNWYWxpZCgpICYmIGRpc2suaXNSZWFkeSgpICYmIGRpc2suYnl0ZXNU
b3RhbCgpPjApIHsgcmVzdWx0WyJzdG9yYWdlVG90YWxHaUIiXT1kb3VibGUoZGlzay5ieXRlc1Rv
dGFsKCkpLygxMDI0KjEwMjQqMTAyNCk7IHJlc3VsdFsic3RvcmFnZUZyZWVHaUIiXT1kb3VibGUo
ZGlzay5ieXRlc0F2YWlsYWJsZSgpKS8oMTAyNCoxMDI0KjEwMjQpOyB9IH0KKyAgICBpZihyb290
LmlzRW1wdHkoKSkgeworICAgICAgICBRU3RyaW5nIGRldmljZT1RRmlsZUluZm8oUVN0cmluZzo6
ZnJvbVV0ZjgoUVN0b3JhZ2VJbmZvOjpyb290KCkuZGV2aWNlKCkpKS5jYW5vbmljYWxGaWxlUGF0
aCgpLnNlY3Rpb24oJy8nLC0xKTsKKyAgICAgICAgYXV0byBpbz1yZWFkKCIvc3lzL2NsYXNzL2Js
b2NrLyIrZGV2aWNlKyIvc3RhdCIpLnNpbXBsaWZpZWQoKS5zcGxpdCgnICcpOworICAgICAgICBp
ZighZGV2aWNlLmlzRW1wdHkoKSAmJiBpby5zaXplKCk+PTcpIHsKKyAgICAgICAgICAgIHF1aW50
NjQgcmVhZHM9aW9bMl0udG9VTG9uZ0xvbmcoKSx3cml0ZXM9aW9bNl0udG9VTG9uZ0xvbmcoKTsK
KyAgICAgICAgICAgIGNvdW50ZXJzWyJkaXNrIl09ZGV2aWNlO2NvdW50ZXJzWyJyZWFkcyJdPXJl
YWRzO2NvdW50ZXJzWyJ3cml0ZXMiXT13cml0ZXM7CisgICAgICAgICAgICBpZihzZWNvbmRzPjAg
JiYgb2xkLnZhbHVlKCJkaXNrIikudG9TdHJpbmcoKT09ZGV2aWNlICYmIHJlYWRzPj1vbGQudmFs
dWUoInJlYWRzIikudG9VTG9uZ0xvbmcoKSAmJiB3cml0ZXM+PW9sZC52YWx1ZSgid3JpdGVzIiku
dG9VTG9uZ0xvbmcoKSkgeworICAgICAgICAgICAgICAgIHJlc3VsdFsiZGlza1JlYWRNaUIiXT1k
b3VibGUocmVhZHMtb2xkWyJyZWFkcyJdLnRvVUxvbmdMb25nKCkpKjUxMi9zZWNvbmRzLygxMDI0
KjEwMjQpOworICAgICAgICAgICAgICAgIHJlc3VsdFsiZGlza1dyaXRlTWlCIl09ZG91YmxlKHdy
aXRlcy1vbGRbIndyaXRlcyJdLnRvVUxvbmdMb25nKCkpKjUxMi9zZWNvbmRzLygxMDI0KjEwMjQp
OworICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQorICAgIHByZXZpb3VzW3Jvb3RdPWNv
dW50ZXJzOyBsYXN0W3Jvb3RdPW5vdzsgY2FjaGVkW3Jvb3RdPXJlc3VsdDsgcmV0dXJuIHJlc3Vs
dDsKK30KKworUVN0cmluZyBMb2NhbEhhcmR3YXJlOjpvdmVybGF5VGV4dCgpIHsKKyAgICBhdXRv
IHI9c2FtcGxlKCk7IFFTZXR0aW5ncyBzOyBhdXRvIGZpZWxkcz1zLnZhbHVlKCJlY2xpcHNlL2xv
Y2FsRmllbGRzIixRU3RyaW5nTGlzdHsiY3B1IiwibWVtb3J5IiwidGVtcGVyYXR1cmUiLCJncHUi
LCJuZXR3b3JrIiwiYmF0dGVyeSJ9KS50b1N0cmluZ0xpc3QoKTsgYm9vbCBkZXRhaWw9cy52YWx1
ZSgiZWNsaXBzZS9sb2NhbERldGFpbGVkIixmYWxzZSkudG9Cb29sKCk7CisgICAgUVN0cmluZ0xp
c3QgbGluZXN7IkVjbGlwc2VPUyB8IExPQ0FMIE1BQyJ9OworICAgIGF1dG8gdmFsdWU9WyZyXShR
U3RyaW5nIGtleSxRU3RyaW5nIHN1ZmZpeCxpbnQgcHJlY2lzaW9uPTEpIHsgcmV0dXJuIHIuY29u
dGFpbnMoa2V5KSA/IFFTdHJpbmc6Om51bWJlcihyW2tleV0udG9Eb3VibGUoKSwnZicscHJlY2lz
aW9uKStzdWZmaXggOiBRU3RyaW5nKCJVbmF2YWlsYWJsZSIpOyB9OworICAgIGlmKGZpZWxkcy5j
b250YWlucygiY3B1IikpIHsgbGluZXM8PCJDUFUgICIrdmFsdWUoImNwdVBlcmNlbnQiLCIlIik7
IGlmKGRldGFpbCkgbGluZXM8PCJDUFUgY2xvY2sgICIrdmFsdWUoImNwdU1IeiIsIiBNSHoiLDAp
OyB9CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJtZW1vcnkiKSkgeyBsaW5lczw8IlJBTSAgIit2
YWx1ZSgibWVtb3J5VXNlZEdpQiIsIiBHaUIiKSsiIC8gIit2YWx1ZSgibWVtb3J5VG90YWxHaUIi
LCIgR2lCIik7IGlmKGRldGFpbCkgbGluZXM8PCJTd2FwICAiK3ZhbHVlKCJzd2FwVXNlZE1pQiIs
IiBNaUIiKTsgfQorICAgIGlmKGZpZWxkcy5jb250YWlucygidGVtcGVyYXR1cmUiKSkgeyBsaW5l
czw8IkNQVSB0ZW1wZXJhdHVyZSAgIit2YWx1ZSgidGVtcGVyYXR1cmVDIiwiIEMiKTsgaWYoZGV0
YWlsKSBsaW5lczw8IkZhbiAgIit2YWx1ZSgiZmFuUlBNIiwiIFJQTSIsMCk7IH0KKyAgICBpZihm
aWVsZHMuY29udGFpbnMoImdwdSIpKSB7IGxpbmVzPDwiR1BVIGJ1c3kgICIrdmFsdWUoImdwdVBl
cmNlbnQiLCIlIik7IGxpbmVzPDwiRWNsaXBzZSB2aWRlbyBlbmdpbmUgICIrdmFsdWUoInZpZGVv
UGVyY2VudCIsIiUiKTsgfQorICAgIGlmKGZpZWxkcy5jb250YWlucygibmV0d29yayIpKSBsaW5l
czw8Ik5ldHdvcmsgIGRvd24gIit2YWx1ZSgicmVjZWl2ZU1pQiIsIiBNaUIvcyIpKyIgfCB1cCAi
K3ZhbHVlKCJ0cmFuc21pdE1pQiIsIiBNaUIvcyIpOworICAgIGlmKGZpZWxkcy5jb250YWlucygi
YmF0dGVyeSIpKSB7IGxpbmVzPDwiQmF0dGVyeSAgIit2YWx1ZSgiYmF0dGVyeVBlcmNlbnQiLCIl
IiwwKTsgaWYoZGV0YWlsKSBsaW5lczw8IkJhdHRlcnkgcG93ZXIgICIrdmFsdWUoImJhdHRlcnlX
YXR0cyIsIiBXIik7IH0KKyAgICBpZihmaWVsZHMuY29udGFpbnMoInN0b3JhZ2UiKSkgeyBsaW5l
czw8IlVTQi9yb290IGZyZWUgICIrdmFsdWUoInN0b3JhZ2VGcmVlR2lCIiwiIEdpQiIpOyBpZihk
ZXRhaWwpIGxpbmVzPDwiUm9vdCBJL08gIHJlYWQgIit2YWx1ZSgiZGlza1JlYWRNaUIiLCIgTWlC
L3MiKSsiIHwgd3JpdGUgIit2YWx1ZSgiZGlza1dyaXRlTWlCIiwiIE1pQi9zIik7IH0KKyAgICBy
ZXR1cm4gbGluZXMuam9pbignXG4nKTsKK30KK3N0YXRpYyB2b2lkIHJlZ2lzdGVyTG9jYWxIYXJk
d2FyZSgpIHsgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlPExvY2FsSGFyZHdhcmU+KCJMb2NhbEhh
cmR3YXJlIiwxLDAsIkxvY2FsSGFyZHdhcmUiLFtdKFFRbWxFbmdpbmUqLFFKU0VuZ2luZSopLT5R
T2JqZWN0KntyZXR1cm4gbmV3IExvY2FsSGFyZHdhcmUoKTt9KTsgfQorUV9DT1JFQVBQX1NUQVJU
VVBfRlVOQ1RJT04ocmVnaXN0ZXJMb2NhbEhhcmR3YXJlKQpkaWZmIC0tZ2l0IGEvYXBwL21vb25s
aWdodG9zL2xvY2FsaGFyZHdhcmUuaCBiL2FwcC9tb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmgK
bmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMzExZmVhOAotLS0gL2Rldi9udWxs
CisrKyBiL2FwcC9tb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmgKQEAgLTAsMCArMSw0OSBAQAor
I3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4K
KyNpbmNsdWRlIDxRVmFyaWFudExpc3Q+CisjaW5jbHVkZSA8UVRpbWVyPgorI2luY2x1ZGUgPFFT
ZXR0aW5ncz4KKworY2xhc3MgTG9jYWxIYXJkd2FyZSA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBR
X09CSkVDVAorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgcmVhZGluZ3MgUkVBRCByZWFkaW5n
cyBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFWYXJpYW50TGlzdCBoaXN0b3J5IFJF
QUQgaGlzdG9yeSBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgb3ZlcmxheSBS
RUFEIG92ZXJsYXkgV1JJVEUgc2V0T3ZlcmxheSBOT1RJRlkgcHJlZmVyZW5jZXNDaGFuZ2VkKQor
ICAgIFFfUFJPUEVSVFkoYm9vbCBkZXRhaWxlZCBSRUFEIGRldGFpbGVkIFdSSVRFIHNldERldGFp
bGVkIE5PVElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCisgICAgUV9QUk9QRVJUWShib29sIHN0cmVh
bURldGFpbGVkIFJFQUQgc3RyZWFtRGV0YWlsZWQgV1JJVEUgc2V0U3RyZWFtRGV0YWlsZWQgTk9U
SUZZIHByZWZlcmVuY2VzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGludCBwb3NpdGlvbiBSRUFE
IHBvc2l0aW9uIFdSSVRFIHNldFBvc2l0aW9uIE5PVElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCisg
ICAgUV9QUk9QRVJUWShpbnQgb3BhY2l0eSBSRUFEIG9wYWNpdHkgV1JJVEUgc2V0T3BhY2l0eSBO
T1RJRlkgcHJlZmVyZW5jZXNDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoaW50IHJlZnJlc2hTZWNv
bmRzIFJFQUQgcmVmcmVzaFNlY29uZHMgV1JJVEUgc2V0UmVmcmVzaFNlY29uZHMgTk9USUZZIHBy
ZWZlcmVuY2VzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmdMaXN0IGZpZWxkcyBSRUFE
IGZpZWxkcyBXUklURSBzZXRGaWVsZHMgTk9USUZZIHByZWZlcmVuY2VzQ2hhbmdlZCkKK3B1Ymxp
YzoKKyAgICBleHBsaWNpdCBMb2NhbEhhcmR3YXJlKFFPYmplY3QqIHBhcmVudD1udWxscHRyKTsK
KyAgICBRVmFyaWFudE1hcCByZWFkaW5ncygpIGNvbnN0IHsgcmV0dXJuIG1fcmVhZGluZ3M7IH0K
KyAgICBRVmFyaWFudExpc3QgaGlzdG9yeSgpIGNvbnN0IHsgcmV0dXJuIG1faGlzdG9yeTsgfQor
ICAgIGJvb2wgb3ZlcmxheSgpIGNvbnN0IHsgcmV0dXJuIFFTZXR0aW5ncygpLnZhbHVlKCJlY2xp
cHNlL2xvY2FsT3ZlcmxheSIsZmFsc2UpLnRvQm9vbCgpOyB9CisgICAgYm9vbCBkZXRhaWxlZCgp
IGNvbnN0IHsgcmV0dXJuIFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2FsRGV0YWlsZWQi
LGZhbHNlKS50b0Jvb2woKTsgfQorICAgIGJvb2wgc3RyZWFtRGV0YWlsZWQoKSBjb25zdCB7IHJl
dHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9zdHJlYW1EZXRhaWxlZCIsdHJ1ZSkudG9C
b29sKCk7IH0KKyAgICBpbnQgcG9zaXRpb24oKSBjb25zdCB7IHJldHVybiBxQm91bmQoMCxRU2V0
dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9sb2NhbFBvc2l0aW9uIiwxKS50b0ludCgpLDMpOyB9Cisg
ICAgaW50IG9wYWNpdHkoKSBjb25zdCB7IHJldHVybiBxQm91bmQoNDAsUVNldHRpbmdzKCkudmFs
dWUoImVjbGlwc2Uvb3ZlcmxheU9wYWNpdHkiLDg1KS50b0ludCgpLDEwMCk7IH0KKyAgICBpbnQg
cmVmcmVzaFNlY29uZHMoKSBjb25zdCB7IHJldHVybiBxQm91bmQoMSxRU2V0dGluZ3MoKS52YWx1
ZSgiZWNsaXBzZS9oYXJkd2FyZVJlZnJlc2giLDIpLnRvSW50KCksNSk7IH0KKyAgICBRU3RyaW5n
TGlzdCBmaWVsZHMoKSBjb25zdCB7IHJldHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9s
b2NhbEZpZWxkcyIsUVN0cmluZ0xpc3R7ImNwdSIsIm1lbW9yeSIsInRlbXBlcmF0dXJlIiwiZ3B1
IiwibmV0d29yayIsImJhdHRlcnkifSkudG9TdHJpbmdMaXN0KCk7IH0KKyAgICB2b2lkIHNldE92
ZXJsYXkoYm9vbCB2KSB7IHNhdmUoImxvY2FsT3ZlcmxheSIsdik7IH0KKyAgICB2b2lkIHNldERl
dGFpbGVkKGJvb2wgdikgeyBzYXZlKCJsb2NhbERldGFpbGVkIix2KTsgfQorICAgIHZvaWQgc2V0
U3RyZWFtRGV0YWlsZWQoYm9vbCB2KSB7IHNhdmUoInN0cmVhbURldGFpbGVkIix2KTsgfQorICAg
IHZvaWQgc2V0UG9zaXRpb24oaW50IHYpIHsgc2F2ZSgibG9jYWxQb3NpdGlvbiIscUJvdW5kKDAs
diwzKSk7IH0KKyAgICB2b2lkIHNldE9wYWNpdHkoaW50IHYpIHsgc2F2ZSgib3ZlcmxheU9wYWNp
dHkiLHFCb3VuZCg0MCx2LDEwMCkpOyB9CisgICAgdm9pZCBzZXRSZWZyZXNoU2Vjb25kcyhpbnQg
dikgeyBzYXZlKCJoYXJkd2FyZVJlZnJlc2giLHFCb3VuZCgxLHYsNSkpOyBtX3RpbWVyLnNldElu
dGVydmFsKHJlZnJlc2hTZWNvbmRzKCkqMTAwMCk7IH0KKyAgICB2b2lkIHNldEZpZWxkcyhRU3Ry
aW5nTGlzdCB2KTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIHNldEFjdGl2ZShib29sIGFjdGl2ZSk7
CisgICAgc3RhdGljIFFWYXJpYW50TWFwIHNhbXBsZShjb25zdCBRU3RyaW5nJiByb290PVFTdHJp
bmcoKSk7CisgICAgc3RhdGljIFFTdHJpbmcgb3ZlcmxheVRleHQoKTsKK3NpZ25hbHM6CisgICAg
dm9pZCBjaGFuZ2VkKCk7CisgICAgdm9pZCBwcmVmZXJlbmNlc0NoYW5nZWQoKTsKK3ByaXZhdGU6
CisgICAgdm9pZCByZWZyZXNoKCk7CisgICAgdm9pZCBzYXZlKFFTdHJpbmcga2V5LCBRVmFyaWFu
dCB2YWx1ZSkgeyBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS8iK2tleSx2YWx1ZSk7IGVt
aXQgcHJlZmVyZW5jZXNDaGFuZ2VkKCk7IH0KKyAgICBRVGltZXIgbV90aW1lcjsKKyAgICBRVmFy
aWFudE1hcCBtX3JlYWRpbmdzOworICAgIFFWYXJpYW50TGlzdCBtX2hpc3Rvcnk7Cit9OwpkaWZm
IC0tZ2l0IGEvYXBwL21vb25saWdodG9zL21hbmFnZWR1cGRhdGVzLmNwcCBiL2FwcC9tb29ubGln
aHRvcy9tYW5hZ2VkdXBkYXRlcy5jcHAKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAw
MC4uMmJmY2JmZAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9tYW5hZ2VkdXBk
YXRlcy5jcHAKQEAgLTAsMCArMSwxMzIgQEAKKy8vIEVjbGlwc2VPUyBvd25zIHRoaXMgY3VzdG9t
aXplZCBuYXRpdmUgY2xpZW50LiBObyBmZWVkIHJlcXVlc3RzLCBhc3NldAorLy8gZG93bmxvYWRz
LCBzd2FwcyBvciByZWxhdW5jaGVzIGFyZSBjb21waWxlZCBpbnRvIHRoaXMgdXBkYXRlIGltcGxl
bWVudGF0aW9uLgorI2luY2x1ZGUgIi4uL2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaCIKKyNp
bmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUgPFFKc29uT2JqZWN0PgorCitzdGF0
aWMgUVN0cmluZyBzdHJpcEJ1aWxkTWV0YWRhdGEoY29uc3QgUVN0cmluZyYgdmVyc2lvbikKK3sK
KyAgICBpbnQgcGx1c0lkeCA9IHZlcnNpb24uaW5kZXhPZignKycpOworICAgIHJldHVybiBwbHVz
SWR4ID49IDAgPyB2ZXJzaW9uLmxlZnQocGx1c0lkeCkgOiB2ZXJzaW9uOworfQorCitzdGF0aWMg
Ym9vbCBpc051bWVyaWNJZGVudGlmaWVyKGNvbnN0IFFTdHJpbmcmIHMpCit7CisgICAgaWYgKHMu
aXNFbXB0eSgpKSB7CisgICAgICAgIHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgZm9yIChjb25z
dCBRQ2hhciYgYyA6IHMpIHsKKyAgICAgICAgaWYgKCFjLmlzRGlnaXQoKSkgeworICAgICAgICAg
ICAgcmV0dXJuIGZhbHNlOworICAgICAgICB9CisgICAgfQorICAgIHJldHVybiB0cnVlOworfQor
CitpbnQgQXV0b1VwZGF0ZUNoZWNrZXI6OmNvbXBhcmVTZW1hbnRpY1ZlcnNpb25zKGNvbnN0IFFT
dHJpbmcmIHYxLCBjb25zdCBRU3RyaW5nJiB2MikKK3sKKyAgICBRU3RyaW5nIHMxID0gc3RyaXBC
dWlsZE1ldGFkYXRhKHYxKTsKKyAgICBRU3RyaW5nIHMyID0gc3RyaXBCdWlsZE1ldGFkYXRhKHYy
KTsKKworICAgIGludCBkYXNoMSA9IHMxLmluZGV4T2YoJy0nKTsKKyAgICBpbnQgZGFzaDIgPSBz
Mi5pbmRleE9mKCctJyk7CisgICAgUVN0cmluZyBiYXNlMSA9IGRhc2gxID49IDAgPyBzMS5sZWZ0
KGRhc2gxKSA6IHMxOworICAgIFFTdHJpbmcgYmFzZTIgPSBkYXNoMiA+PSAwID8gczIubGVmdChk
YXNoMikgOiBzMjsKKyAgICBRU3RyaW5nIHByZTEgPSBkYXNoMSA+PSAwID8gczEubWlkKGRhc2gx
ICsgMSkgOiBRU3RyaW5nKCk7CisgICAgUVN0cmluZyBwcmUyID0gZGFzaDIgPj0gMCA/IHMyLm1p
ZChkYXNoMiArIDEpIDogUVN0cmluZygpOworCisgICAgLy8gTnVtZXJpYyBiYXNlIHZlcnNpb25z
IGNvbXBhcmUgZmlyc3QgKDAuNC4wLWJldGEuMDAxID4gMC4zLjApCisgICAgY29uc3QgUVN0cmlu
Z0xpc3QgYmFzZVBhcnRzMSA9IGJhc2UxLnNwbGl0KCcuJyk7CisgICAgY29uc3QgUVN0cmluZ0xp
c3QgYmFzZVBhcnRzMiA9IGJhc2UyLnNwbGl0KCcuJyk7CisgICAgZm9yIChpbnQgaSA9IDA7IGkg
PCBxTWF4KGJhc2VQYXJ0czEuY291bnQoKSwgYmFzZVBhcnRzMi5jb3VudCgpKTsgaSsrKSB7Cisg
ICAgICAgIHFsb25nbG9uZyBiMSA9IGkgPCBiYXNlUGFydHMxLmNvdW50KCkgPyBiYXNlUGFydHMx
W2ldLnRvTG9uZ0xvbmcoKSA6IDA7CisgICAgICAgIHFsb25nbG9uZyBiMiA9IGkgPCBiYXNlUGFy
dHMyLmNvdW50KCkgPyBiYXNlUGFydHMyW2ldLnRvTG9uZ0xvbmcoKSA6IDA7CisgICAgICAgIGlm
IChiMSAhPSBiMikgeworICAgICAgICAgICAgcmV0dXJuIGIxIDwgYjIgPyAtMSA6IDE7CisgICAg
ICAgIH0KKyAgICB9CisKKyAgICAvLyBFcXVhbCBiYXNlOiBhIHJlbGVhc2Ugd2l0aCBubyBwcmVy
ZWxlYXNlIHN1ZmZpeCBvdXRyYW5rcyBhbnkgcHJlcmVsZWFzZQorICAgIGlmIChwcmUxLmlzRW1w
dHkoKSAhPSBwcmUyLmlzRW1wdHkoKSkgeworICAgICAgICByZXR1cm4gcHJlMS5pc0VtcHR5KCkg
PyAxIDogLTE7CisgICAgfQorICAgIGlmIChwcmUxLmlzRW1wdHkoKSkgeworICAgICAgICByZXR1
cm4gMDsKKyAgICB9CisKKyAgICAvLyBUd28gcHJlcmVsZWFzZXM6IGNvbXBhcmUgZG90LXNlcGFy
YXRlZCBpZGVudGlmaWVycyBsZWZ0IHRvIHJpZ2h0LgorICAgIC8vIE51bWVyaWMgaWRlbnRpZmll
cnMgY29tcGFyZSBudW1lcmljYWxseSAobGVhZGluZyB6ZXJvcyB0b2xlcmF0ZWQg4oCUIG91cgor
ICAgIC8vIENJIHplcm8tcGFkcyBjb3VudGVycyksIGFscGhhbnVtZXJpYyBvbmVzIGxleGljYWxs
eSBpbiBBU0NJSSBvcmRlciwgYW5kCisgICAgLy8gbnVtZXJpYyBhbHdheXMgcmFua3MgYmVsb3cg
YWxwaGFudW1lcmljLiBUaGlzIGlzIHdoYXQgb3JkZXJzCisgICAgLy8gImFscGhhIiA8ICJiZXRh
IiA8ICJyYyIgYXQgYW4gZXF1YWwgYmFzZSDigJQgdGhlIHByb3BlcnR5IHRoZSBwcmV2aW91cwor
ICAgIC8vIGltcGxlbWVudGF0aW9uIGxhY2tlZCAoaXQgc2tpcHBlZCB0aGUgd29yZHMgYW5kIGNv
bXBhcmVkIG9ubHkgbnVtYmVycywKKyAgICAvLyBzbyAwLjMuMC1iZXRhLjAwOCB3cm9uZ2x5IG91
dHJhbmtlZCAwLjMuMC1yYy4wMDIpLgorICAgIGNvbnN0IFFTdHJpbmdMaXN0IGlkczEgPSBwcmUx
LnNwbGl0KCcuJyk7CisgICAgY29uc3QgUVN0cmluZ0xpc3QgaWRzMiA9IHByZTIuc3BsaXQoJy4n
KTsKKyAgICBmb3IgKGludCBpID0gMDsgaSA8IHFNYXgoaWRzMS5jb3VudCgpLCBpZHMyLmNvdW50
KCkpOyBpKyspIHsKKyAgICAgICAgaWYgKGkgPj0gaWRzMS5jb3VudCgpKSB7CisgICAgICAgICAg
ICAvLyBFcXVhbCBwcmVmaXgsIGZld2VyIGZpZWxkcyA9IGxvd2VyIHByZWNlZGVuY2UgKMKnMTEu
NC40KQorICAgICAgICAgICAgcmV0dXJuIC0xOworICAgICAgICB9CisgICAgICAgIGlmIChpID49
IGlkczIuY291bnQoKSkgeworICAgICAgICAgICAgcmV0dXJuIDE7CisgICAgICAgIH0KKyAgICAg
ICAgYm9vbCBudW0xID0gaXNOdW1lcmljSWRlbnRpZmllcihpZHMxW2ldKTsKKyAgICAgICAgYm9v
bCBudW0yID0gaXNOdW1lcmljSWRlbnRpZmllcihpZHMyW2ldKTsKKyAgICAgICAgaWYgKG51bTEg
JiYgbnVtMikgeworICAgICAgICAgICAgcWxvbmdsb25nIHAxID0gaWRzMVtpXS50b0xvbmdMb25n
KCk7CisgICAgICAgICAgICBxbG9uZ2xvbmcgcDIgPSBpZHMyW2ldLnRvTG9uZ0xvbmcoKTsKKyAg
ICAgICAgICAgIGlmIChwMSAhPSBwMikgeworICAgICAgICAgICAgICAgIHJldHVybiBwMSA8IHAy
ID8gLTEgOiAxOworICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgICAgIGVsc2UgaWYgKG51
bTEgIT0gbnVtMikgeworICAgICAgICAgICAgLy8gTnVtZXJpYyBpZGVudGlmaWVycyByYW5rIGJl
bG93IGFscGhhbnVtZXJpYyBvbmVzICjCpzExLjQuMykKKyAgICAgICAgICAgIHJldHVybiBudW0x
ID8gLTEgOiAxOworICAgICAgICB9CisgICAgICAgIGVsc2UgeworICAgICAgICAgICAgaW50IGNt
cCA9IFFTdHJpbmc6OmNvbXBhcmUoaWRzMVtpXSwgaWRzMltpXSk7CisgICAgICAgICAgICBpZiAo
Y21wICE9IDApIHsKKyAgICAgICAgICAgICAgICByZXR1cm4gY21wIDwgMCA/IC0xIDogMTsKKyAg
ICAgICAgICAgIH0KKyAgICAgICAgfQorICAgIH0KKyAgICByZXR1cm4gMDsKK30KKworQXV0b1Vw
ZGF0ZUNoZWNrZXI6OkF1dG9VcGRhdGVDaGVja2VyKFFPYmplY3QqIHBhcmVudCkgOgorICAgIFFP
YmplY3QocGFyZW50KSwgbV9DaGVja0luRmxpZ2h0KGZhbHNlKSwgbV9DaGVja0lzTWFudWFsKGZh
bHNlKSwKKyAgICBtX1VwZGF0ZUF2YWlsYWJsZShmYWxzZSksIG1fT2ZmZXJBdmFpbGFibGUoZmFs
c2UpLCBtX0luc3RhbGxpbmcoZmFsc2UpCit7CisgICAgY2xlYXJPZmZlcigpOworICAgIHNldFN0
YXR1cyh0cigiJTEuIFVwZGF0ZXMgYXJlIG1hbmFnZWQgYnkgRWNsaXBzZU9TLiBHZXQgdGhlIG1h
dGNoaW5nIE9TIGltYWdlIGZyb20gJTI7IHVwc3RyZWFtIFZpYmVtaXMgdXBkYXRlcyBhcmUgZGlz
YWJsZWQuIikuYXJnKGN1cnJlbnRWZXJzaW9uKCksIG1fUmVsZWFzZVVybCkpOworfQorUVN0cmlu
ZyBBdXRvVXBkYXRlQ2hlY2tlcjo6Y3VycmVudFZlcnNpb24oKSBjb25zdAoreworICAgIHJldHVy
biB0cigiRWNsaXBzZSAlMSDCtyBFY2xpcHNlT1MgY3VzdG9taXplZCIpLmFyZyhRQ29yZUFwcGxp
Y2F0aW9uOjphcHBsaWNhdGlvblZlcnNpb24oKSk7Cit9Cit2b2lkIEF1dG9VcGRhdGVDaGVja2Vy
OjpjbGVhck9mZmVyKCkKK3sKKyAgICBtX1VwZGF0ZUF2YWlsYWJsZSA9IGZhbHNlOyBtX09mZmVy
QXZhaWxhYmxlID0gZmFsc2U7CisgICAgbV9PZmZlclZlcnNpb24uY2xlYXIoKTsgbV9Bc3NldFVy
bC5jbGVhcigpOyBtX09mZmVyVGllciA9IC0xOworICAgIG1fUmVsZWFzZVVybCA9IFFTdHJpbmdM
aXRlcmFsKCJodHRwczovL2dpdGh1Yi5jb20vdGgzZDNjazNyL01vb25saWdodC1PUy9yZWxlYXNl
cyIpOworfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6c2V0U3RhdHVzKGNvbnN0IFFTdHJpbmcm
IG1lc3NhZ2UpCit7CisgICAgaWYgKG1fU3RhdHVzTWVzc2FnZSAhPSBtZXNzYWdlKSB7IG1fU3Rh
dHVzTWVzc2FnZSA9IG1lc3NhZ2U7IGVtaXQgc3RhdGVDaGFuZ2VkKCk7IH0KK30KK3ZvaWQgQXV0
b1VwZGF0ZUNoZWNrZXI6OnN0YXJ0KCkgeyAvKiBObyB0aW1lciBhbmQgbm8gYmFja2dyb3VuZCB1
cGRhdGUgcmVxdWVzdHMuICovIH0KK2Jvb2wgQXV0b1VwZGF0ZUNoZWNrZXI6OmNhbkluc3RhbGxV
cGRhdGVzKCkgY29uc3QgeyByZXR1cm4gZmFsc2U7IH0KK2Jvb2wgQXV0b1VwZGF0ZUNoZWNrZXI6
OmNhbkluc3RhbGwoKSBjb25zdCB7IHJldHVybiBmYWxzZTsgfQordm9pZCBBdXRvVXBkYXRlQ2hl
Y2tlcjo6Y2hhbm5lbENoYW5nZWQoKSB7IGNoZWNrTm93KCk7IH0KK3ZvaWQgQXV0b1VwZGF0ZUNo
ZWNrZXI6OmNoZWNrTm93KCkKK3sKKyAgICBjbGVhck9mZmVyKCk7CisgICAgc2V0U3RhdHVzKHRy
KCJVcGRhdGVzIGFyZSBtYW5hZ2VkIGJ5IEVjbGlwc2VPUy4gRG93bmxvYWQgdGhlIG1hdGNoaW5n
IE9TIGltYWdlIGZyb20gJTEuIFRoaXMgY2xpZW50IG5ldmVyIGluc3RhbGxzIHVwc3RyZWFtIFZp
YmVtaXMgcmVsZWFzZXMuIikuYXJnKG1fUmVsZWFzZVVybCkpOworICAgIGVtaXQgc3RhdGVDaGFu
Z2VkKCk7IGVtaXQgY2hlY2tDb21wbGV0ZWQodHJ1ZSwgZmFsc2UpOworfQordm9pZCBBdXRvVXBk
YXRlQ2hlY2tlcjo6aW5zdGFsbCgpCit7CisgICAgY2hlY2tOb3coKTsKKyAgICBlbWl0IGluc3Rh
bGxGYWlsZWQodHIoIlN0YW5kYWxvbmUgVmliZW1pcyBpbnN0YWxsYXRpb24gaXMgZGlzYWJsZWQg
aW4gRWNsaXBzZU9TLiIpLCBtX1JlbGVhc2VVcmwpOworfQpkaWZmIC0tZ2l0IGEvYXBwL21vb25s
aWdodG9zL292ZXJsYXlzdHlsZS5oIGIvYXBwL21vb25saWdodG9zL292ZXJsYXlzdHlsZS5oCm5l
dyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmNlMzBmYWYKLS0tIC9kZXYvbnVsbAor
KysgYi9hcHAvbW9vbmxpZ2h0b3Mvb3ZlcmxheXN0eWxlLmgKQEAgLTAsMCArMSwyMCBAQAorI3By
YWdtYSBvbmNlCisjaW5jbHVkZSA8UUltYWdlPgorI2luY2x1ZGUgPFFQYWludGVyPgorI2luY2x1
ZGUgPFFDb2xvcj4KK25hbWVzcGFjZSBFY2xpcHNlT3ZlcmxheVN0eWxlIHsKK2lubGluZSBRQ29s
b3IgYWNjZW50KGludCBpbmRleCkgeworICAgIGNvbnN0IGNoYXIqIGNvbG9yc1tdPXsiIzAwQ0ND
QyIsIiM3QzhDRjgiLCIjM0VENTk4IiwiI0YwQTg2OCIsIiNEQzM2NTgiLCIjRjI1RDY0IiwiI0Y1
ODM0NyIsIiNGMUJDNDUiLCIjQjdEQzYzIiwiIzYzQ0NBRSIsIiM2M0M0RUQiLCIjNkM5RkZGIiwi
I0FEODVGNSIsIiNFOTc2QkMiLCIjQ0FEMERBIiwiI0Q5OTVBQyJ9OworICAgIHJldHVybiBRQ29s
b3IoY29sb3JzW3FCb3VuZCgwLGluZGV4LDE1KV0pOworfQoraW5saW5lIFFJbWFnZSBwYW5lbChR
U2l6ZSBzaXplLGludCBhY2NlbnRJbmRleCxpbnQgb3BhY2l0eSkgeworICAgIGlmKHNpemUud2lk
dGgoKTwzMiB8fCBzaXplLmhlaWdodCgpPDMyIHx8IHNpemUud2lkdGgoKT4yMDQ4IHx8IHNpemUu
aGVpZ2h0KCk+NDA5NikgcmV0dXJuIHt9OworICAgIFFJbWFnZSBpbWFnZShzaXplLFFJbWFnZTo6
Rm9ybWF0X1JHQkE4ODg4KTsgaW1hZ2UuZmlsbChRdDo6dHJhbnNwYXJlbnQpOworICAgIFFQYWlu
dGVyIHBhaW50ZXIoJmltYWdlKTsgcGFpbnRlci5zZXRSZW5kZXJIaW50KFFQYWludGVyOjpBbnRp
YWxpYXNpbmcpOworICAgIFFDb2xvciBiZygiIzE1MTExNSIpOyBiZy5zZXRBbHBoYShxQm91bmQo
NDAsb3BhY2l0eSwxMDApKjI1NS8xMDApOworICAgIHBhaW50ZXIuc2V0QnJ1c2goYmcpOyBwYWlu
dGVyLnNldFBlbihRUGVuKGFjY2VudChhY2NlbnRJbmRleCksMSkpOworICAgIHBhaW50ZXIuZHJh
d1JvdW5kZWRSZWN0KFFSZWN0RigxLDEsaW1hZ2Uud2lkdGgoKS0yLGltYWdlLmhlaWdodCgpLTIp
LDEyLDEyKTsKKyAgICBwYWludGVyLnNldFBlbihRUGVuKGFjY2VudChhY2NlbnRJbmRleCksMykp
OyBwYWludGVyLmRyYXdMaW5lKDE1LDgsaW1hZ2Uud2lkdGgoKS0xNSw4KTsKKyAgICByZXR1cm4g
aW1hZ2U7Cit9Cit9CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMu
Y3BwIGIvYXBwL21vb25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmNwcApuZXcgZmlsZSBtb2RlIDEw
MDY0NAppbmRleCAwMDAwMDAwLi4zZWUzZmY5Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25s
aWdodG9zL3N5c3RlbWNvbnRyb2xzLmNwcApAQCAtMCwwICsxLDgyIEBACisjaW5jbHVkZSAic3lz
dGVtY29udHJvbHMuaCIKKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUgPFFK
c29uRG9jdW1lbnQ+CisjaW5jbHVkZSA8UUpzb25PYmplY3Q+CisjaW5jbHVkZSA8UUpzb25BcnJh
eT4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFGaWxlSW5mbz4KK1N5c3RlbUNv
bnRyb2xzOjpTeXN0ZW1Db250cm9scyhRT2JqZWN0KiBwYXJlbnQpIDogUU9iamVjdChwYXJlbnQp
IHsKKyAgICBtX3RpbWVvdXQuc2V0U2luZ2xlU2hvdCh0cnVlKTsKKyAgICBjb25uZWN0KCZtX3Rp
bWVvdXQsICZRVGltZXI6OnRpbWVvdXQsIHRoaXMsIFt0aGlzXSB7IGZhaWwodHIoIk9wZXJhdGlv
biB0aW1lZCBvdXQuIFJldHJ5IG9yIHVzZSB0aGUgZGlhZ25vc3RpYyBzaGVsbC4iKSk7IH0pOwor
ICAgIGNvbm5lY3QoJm1fcHJvY2VzcywgJlFQcm9jZXNzOjpzdGFydGVkLCB0aGlzLCBbdGhpc10g
eyByZXF1ZXN0KG1fbW9kZSArICItbGlzdCIpOyB9KTsKKyAgICBjb25uZWN0KCZtX3Byb2Nlc3Ms
ICZRUHJvY2Vzczo6cmVhZHlSZWFkU3RhbmRhcmRFcnJvciwgdGhpcywgW3RoaXNdIHsgbV9wcm9j
ZXNzLnJlYWRBbGxTdGFuZGFyZEVycm9yKCk7IH0pOworICAgIGNvbm5lY3QoJm1fcHJvY2Vzcywg
JlFQcm9jZXNzOjpyZWFkeVJlYWRTdGFuZGFyZE91dHB1dCwgdGhpcywgW3RoaXNdIHsKKyAgICAg
ICAgbV9idWZmZXIgKz0gbV9wcm9jZXNzLnJlYWRBbGxTdGFuZGFyZE91dHB1dCgpOworICAgICAg
ICBpZiAobV9idWZmZXIuc2l6ZSgpID4gNjU1MzYpIHsgZmFpbCh0cigiSW52YWxpZCBzeXN0ZW0g
cmVzcG9uc2UuIikpOyByZXR1cm47IH0KKyAgICAgICAgd2hpbGUgKG1fYnVmZmVyLmNvbnRhaW5z
KCdcbicpKSB7CisgICAgICAgICAgICBpbnQgZW5kID0gbV9idWZmZXIuaW5kZXhPZignXG4nKTsK
KyAgICAgICAgICAgIFFKc29uUGFyc2VFcnJvciBlcnJvcjsKKyAgICAgICAgICAgIGF1dG8gZG9j
dW1lbnQgPSBRSnNvbkRvY3VtZW50Ojpmcm9tSnNvbihtX2J1ZmZlci5sZWZ0KGVuZCksICZlcnJv
cik7CisgICAgICAgICAgICBtX2J1ZmZlci5yZW1vdmUoMCwgZW5kICsgMSk7CisgICAgICAgICAg
ICBpZiAoZXJyb3IuZXJyb3IgIT0gUUpzb25QYXJzZUVycm9yOjpOb0Vycm9yIHx8ICFkb2N1bWVu
dC5pc09iamVjdCgpKSB7IGZhaWwodHIoIkludmFsaWQgc3lzdGVtIHJlc3BvbnNlLiIpKTsgcmV0
dXJuOyB9CisgICAgICAgICAgICBhdXRvIHZhbHVlID0gZG9jdW1lbnQub2JqZWN0KCk7CisgICAg
ICAgICAgICBpZiAodmFsdWUuY29udGFpbnMoInByb21wdCIpKSB7CisgICAgICAgICAgICAgICAg
bV9wcm9tcHQgPSB2YWx1ZS52YWx1ZSgicHJvbXB0IikudG9TdHJpbmcoKS5sZWZ0KDEwMjQpOwor
ICAgICAgICAgICAgICAgIG1fdGltZW91dC5zdGFydCgxMjAwMDApOworICAgICAgICAgICAgfQor
ICAgICAgICAgICAgaWYgKHZhbHVlLmNvbnRhaW5zKCJpdGVtcyIpKSB7CisgICAgICAgICAgICAg
ICAgYXV0byBlbnRyaWVzID0gdmFsdWUudmFsdWUoIml0ZW1zIikudG9BcnJheSgpOworICAgICAg
ICAgICAgICAgIGlmIChlbnRyaWVzLnNpemUoKSA+IDY0KSB7IGZhaWwodHIoIkludmFsaWQgZGV2
aWNlIGxpc3QuIikpOyByZXR1cm47IH0KKyAgICAgICAgICAgICAgICBtX2l0ZW1zID0gZW50cmll
cy50b1ZhcmlhbnRMaXN0KCk7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBpZiAodmFsdWUu
dmFsdWUoInN0YXRlIikuaXNPYmplY3QoKSkgbV9zdGF0ZSA9IHZhbHVlLnZhbHVlKCJzdGF0ZSIp
LnRvT2JqZWN0KCkudG9WYXJpYW50TWFwKCk7CisgICAgICAgICAgICBpZih2YWx1ZS5jb250YWlu
cygic3RhdHVzIikpIG1fc3RhdHVzPXZhbHVlLnZhbHVlKCJzdGF0dXMiKS50b1N0cmluZygpLmxl
ZnQoMTAyNCk7CisgICAgICAgICAgICBpZih2YWx1ZS5jb250YWlucygiZXJyb3IiKSkgbV9zdGF0
dXM9dmFsdWUudmFsdWUoImVycm9yIikudG9TdHJpbmcoKS5sZWZ0KDEwMjQpOworICAgICAgICAg
ICAgaWYgKHZhbHVlLnZhbHVlKCJkb25lIikudG9Cb29sKCkpIHsgbV90aW1lb3V0LnN0b3AoKTsg
bV9idXN5PWZhbHNlOyBtX3Byb21wdC5jbGVhcigpOyB9CisgICAgICAgICAgICBlbWl0IGNoYW5n
ZWQoKTsKKyAgICAgICAgfQorICAgIH0pOworICAgIGNvbm5lY3QoJm1fcHJvY2VzcywgJlFQcm9j
ZXNzOjplcnJvck9jY3VycmVkLCB0aGlzLCBbdGhpc10oUVByb2Nlc3M6OlByb2Nlc3NFcnJvcikg
eworICAgICAgICBpZiAoIW1fbW9kZS5pc0VtcHR5KCkpIGZhaWwodHIoIlN5c3RlbSBjb250cm9s
cyBhcmUgdW5hdmFpbGFibGUuIFVzZSB0aGUgZGlhZ25vc3RpYyBzaGVsbC4iKSk7CisgICAgfSk7
CisgICAgY29ubmVjdCgmbV9wcm9jZXNzLCBRT3ZlcmxvYWQ8aW50LFFQcm9jZXNzOjpFeGl0U3Rh
dHVzPjo6b2YoJlFQcm9jZXNzOjpmaW5pc2hlZCksIHRoaXMsIFt0aGlzXShpbnQsIFFQcm9jZXNz
OjpFeGl0U3RhdHVzKSB7CisgICAgICAgIGlmICghbV9tb2RlLmlzRW1wdHkoKSkgeyBtX3RpbWVv
dXQuc3RvcCgpOyBtX2J1c3kgPSBmYWxzZTsgbV9wcm9tcHQuY2xlYXIoKTsgbV9zdGF0dXMgPSB0
cigiU3lzdGVtIGhlbHBlciBzdG9wcGVkLiBDbG9zZSBhbmQgcmVvcGVuIHRoaXMgcGFuZWwuIik7
IGVtaXQgY2hhbmdlZCgpOyB9CisgICAgfSk7Cit9CitTeXN0ZW1Db250cm9sczo6flN5c3RlbUNv
bnRyb2xzKCkgeyBjbG9zZSgpOyBpZiAoIW1fcHJvY2Vzcy53YWl0Rm9yRmluaXNoZWQoNTAwKSkg
eyBtX3Byb2Nlc3Mua2lsbCgpOyBtX3Byb2Nlc3Mud2FpdEZvckZpbmlzaGVkKDUwMCk7IH0gfQor
dm9pZCBTeXN0ZW1Db250cm9sczo6c2VuZChjb25zdCBRSnNvbk9iamVjdCYgdmFsdWUpIHsgbV9w
cm9jZXNzLndyaXRlKFFKc29uRG9jdW1lbnQodmFsdWUpLnRvSnNvbihRSnNvbkRvY3VtZW50OjpD
b21wYWN0KSArICdcbicpOyB9Cit2b2lkIFN5c3RlbUNvbnRyb2xzOjpvcGVuKFFTdHJpbmcgbW9k
ZSkgeworICAgIGlmIChtb2RlICE9ICJ3aWZpIiAmJiBtb2RlICE9ICJidCIgJiYgbW9kZSAhPSAi
Y2VudGVyIikgcmV0dXJuOworICAgIGNsb3NlKCk7CisgICAgaWYgKG1fcHJvY2Vzcy5zdGF0ZSgp
ICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSB7IG1fcHJvY2Vzcy5raWxsKCk7IG1fcHJvY2Vzcy53
YWl0Rm9yRmluaXNoZWQoNTAwKTsgfQorICAgIG1fbW9kZSA9IG1vZGU7IG1faXRlbXMuY2xlYXIo
KTsgbV9zdGF0ZS5jbGVhcigpOyBtX2J1ZmZlci5jbGVhcigpOyBtX3N0YXR1cyA9IHRyKCJMb2Fk
aW5n4oCmIik7IGVtaXQgY2hhbmdlZCgpOworICAgIFFTdHJpbmcgaGVscGVyID0gIi91c3IvbG9j
YWwvbGliZXhlYy9tb29ubGlnaHQtb3Mvc3lzdGVtLWNvbnRyb2xzLnB5IjsKKyNpZmRlZiBNT09O
TElHSFRfQ09OVFJPTFNfVEVTVAorICAgIGhlbHBlciA9IHFFbnZpcm9ubWVudFZhcmlhYmxlKCJN
T09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIsIGhlbHBlcik7CisjZW5kaWYKKyAgICBtX3Byb2Nl
c3Muc3RhcnQoInB5dGhvbjMiLCB7aGVscGVyfSk7Cit9Cit2b2lkIFN5c3RlbUNvbnRyb2xzOjpy
ZXF1ZXN0KFFTdHJpbmcgYWN0aW9uLCBRU3RyaW5nIGlkLCBib29sIGNvbmZpcm0pIHsKKyAgICBp
ZiAobV9idXN5IHx8IG1fcHJvY2Vzcy5zdGF0ZSgpICE9IFFQcm9jZXNzOjpSdW5uaW5nIHx8ICFh
Y3Rpb24uc3RhcnRzV2l0aChtX21vZGUgKyAiLSIpKSByZXR1cm47CisgICAgY29uc3QgUVN0cmlu
Z0xpc3QgYWxsb3dlZCA9IHsid2lmaS1saXN0IiwgIndpZmktc2NhbiIsICJ3aWZpLWNvbm5lY3Qi
LCAid2lmaS1kaXNjb25uZWN0IiwgImJ0LWxpc3QiLCAiYnQtc2NhbiIsICJidC1jb25uZWN0Iiwg
ImJ0LWRpc2Nvbm5lY3QiLCAiYnQtZm9yZ2V0IiwgImNlbnRlci13aWZpLXJhZGlvIiwgImNlbnRl
ci1idC1yYWRpbyIsICJjZW50ZXItYWlycG9kcyIsICJjZW50ZXItdGVzdC1zb3VuZCIsICJjZW50
ZXItaWRsZSIsICJjZW50ZXItcG9pbnRlci1zcGVlZCIsICJjZW50ZXItcG9pbnRlci1uYXR1cmFs
IiwgImNlbnRlci1wb2ludGVyLXRhcCIsICJjZW50ZXItZGlzcGxheSIsICJjZW50ZXItZnJvbnRl
bmQiLCAiY2VudGVyLXJlc3RhcnQtZnJvbnRlbmQiLCAiY2VudGVyLWxpc3QiLCAiY2VudGVyLXZv
bHVtZSIsICJjZW50ZXItbXV0ZSIsICJjZW50ZXItb3V0cHV0IiwgImNlbnRlci1zY3JlZW4iLCAi
Y2VudGVyLWtleWJvYXJkIiwgImNlbnRlci1yZWJvb3QiLCAiY2VudGVyLXBvd2Vyb2ZmIiwgImNl
bnRlci1zdXNwZW5kIiwgImNlbnRlci1yZXBvcnQifTsKKyAgICBpZiAoIWFsbG93ZWQuY29udGFp
bnMoYWN0aW9uKSkgcmV0dXJuOworICAgIG1fYnVzeSA9IHRydWU7IG1fcHJvbXB0LmNsZWFyKCk7
IG1fc3RhdHVzID0gYWN0aW9uLmVuZHNXaXRoKCJzY2FuIikgPyB0cigiU3RhcnRpbmcgc2NhbuKA
piIpIDogdHIoIldvcmtpbmfigKYiKTsgbV90aW1lb3V0LnN0YXJ0KGFjdGlvbi5lbmRzV2l0aCgi
c2NhbiIpID8gMzAwMDAgOiAxMDAwMDApOworICAgIHNlbmQoe3siYWN0aW9uIiwgYWN0aW9ufSwg
eyJpZCIsIGlkfSwgeyJjb25maXJtIiwgY29uZmlybX19KTsgZW1pdCBjaGFuZ2VkKCk7Cit9Cit2
b2lkIFN5c3RlbUNvbnRyb2xzOjphbnN3ZXIoUVN0cmluZyB2YWx1ZSkgeworICAgIGlmICghbV9i
dXN5IHx8IG1fcHJvbXB0LmlzRW1wdHkoKSB8fCB2YWx1ZS5zaXplKCkgPiA0MDk2IHx8IHZhbHVl
LmNvbnRhaW5zKCdcbicpIHx8IHZhbHVlLmNvbnRhaW5zKCdccicpIHx8IHZhbHVlLmNvbnRhaW5z
KFFDaGFyKDApKSkgcmV0dXJuOworICAgIHNlbmQoe3siYWN0aW9uIiwgImFuc3dlciJ9LCB7InZh
bHVlIiwgdmFsdWV9fSk7IG1fcHJvbXB0LmNsZWFyKCk7IG1fdGltZW91dC5zdGFydCgxMjAwMDAp
OyBlbWl0IGNoYW5nZWQoKTsKK30KK3ZvaWQgU3lzdGVtQ29udHJvbHM6OmNsb3NlKCkgeworICAg
IG1fbW9kZS5jbGVhcigpOyBtX3RpbWVvdXQuc3RvcCgpOyBtX2J1c3kgPSBmYWxzZTsgbV9wcm9t
cHQuY2xlYXIoKTsgbV9idWZmZXIuY2xlYXIoKTsKKyAgICBpZiAobV9wcm9jZXNzLnN0YXRlKCkg
IT0gUVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIHsKKyAgICAgICAgbV9wcm9jZXNzLnRlcm1pbmF0ZSgp
OworICAgICAgICBRVGltZXI6OnNpbmdsZVNob3QoNDAwMCwgdGhpcywgW3RoaXNdIHsgaWYgKG1f
bW9kZS5pc0VtcHR5KCkgJiYgbV9wcm9jZXNzLnN0YXRlKCkgIT0gUVByb2Nlc3M6Ok5vdFJ1bm5p
bmcpIG1fcHJvY2Vzcy5raWxsKCk7IH0pOworICAgIH0KKyAgICBlbWl0IGNoYW5nZWQoKTsKK30K
K3ZvaWQgU3lzdGVtQ29udHJvbHM6OmZhaWwoUVN0cmluZyBtZXNzYWdlKSB7IGNsb3NlKCk7IG1f
c3RhdHVzID0gbWVzc2FnZTsgZW1pdCBjaGFuZ2VkKCk7IH0KK3N0YXRpYyB2b2lkIHJlZ2lzdGVy
U3lzdGVtQ29udHJvbHMoKSB7CisgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlPFN5c3RlbUNv
bnRyb2xzPigiU3lzdGVtQ29udHJvbHMiLCAxLCAwLCAiU3lzdGVtQ29udHJvbHMiLCBbXShRUW1s
RW5naW5lKiwgUUpTRW5naW5lKikgLT4gUU9iamVjdCogeyByZXR1cm4gbmV3IFN5c3RlbUNvbnRy
b2xzKCk7IH0pOworfQorUV9DT1JFQVBQX1NUQVJUVVBfRlVOQ1RJT04ocmVnaXN0ZXJTeXN0ZW1D
b250cm9scykKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5oIGIv
YXBwL21vb25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmgKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5k
ZXggMDAwMDAwMC4uMThlOWRlYgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9z
eXN0ZW1jb250cm9scy5oCkBAIC0wLDAgKzEsMzkgQEAKKyNwcmFnbWEgb25jZQorI2luY2x1ZGUg
PFFPYmplY3Q+CisjaW5jbHVkZSA8UUpzb25PYmplY3Q+CisjaW5jbHVkZSA8UVByb2Nlc3M+Cisj
aW5jbHVkZSA8UVRpbWVyPgorI2luY2x1ZGUgPFFWYXJpYW50TGlzdD4KKyNpbmNsdWRlIDxRVmFy
aWFudE1hcD4KK2NsYXNzIFN5c3RlbUNvbnRyb2xzIDogcHVibGljIFFPYmplY3QgeworICAgIFFf
T0JKRUNUCisgICAgUV9QUk9QRVJUWShRVmFyaWFudE1hcCBzdGF0ZSBSRUFEIHN0YXRlIE5PVElG
WSBjaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRMaXN0IGl0ZW1zIFJFQUQgaXRlbXMg
Tk9USUZZIGNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShRU3RyaW5nIHN0YXR1cyBSRUFEIHN0YXR1
cyBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgcHJvbXB0IFJFQUQgcHJv
bXB0IE5PVElGWSBjaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBidXN5IFJFQUQgYnVzeSBO
T1RJRlkgY2hhbmdlZCkKK3B1YmxpYzoKKyAgICBleHBsaWNpdCBTeXN0ZW1Db250cm9scyhRT2Jq
ZWN0KiBwYXJlbnQgPSBudWxscHRyKTsKKyAgICB+U3lzdGVtQ29udHJvbHMoKTsKKyAgICBRVmFy
aWFudE1hcCBzdGF0ZSgpIGNvbnN0IHsgcmV0dXJuIG1fc3RhdGU7IH0KKyAgICBRVmFyaWFudExp
c3QgaXRlbXMoKSBjb25zdCB7IHJldHVybiBtX2l0ZW1zOyB9CisgICAgUVN0cmluZyBzdGF0dXMo
KSBjb25zdCB7IHJldHVybiBtX3N0YXR1czsgfQorICAgIFFTdHJpbmcgcHJvbXB0KCkgY29uc3Qg
eyByZXR1cm4gbV9wcm9tcHQ7IH0KKyAgICBib29sIGJ1c3koKSBjb25zdCB7IHJldHVybiBtX2J1
c3k7IH0KKyAgICBRX0lOVk9LQUJMRSB2b2lkIG9wZW4oUVN0cmluZyBtb2RlKTsKKyAgICBRX0lO
Vk9LQUJMRSB2b2lkIHJlcXVlc3QoUVN0cmluZyBhY3Rpb24sIFFTdHJpbmcgaWQgPSBRU3RyaW5n
KCksIGJvb2wgY29uZmlybSA9IGZhbHNlKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIGFuc3dlcihR
U3RyaW5nIHZhbHVlKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIGNsb3NlKCk7CitzaWduYWxzOgor
ICAgIHZvaWQgY2hhbmdlZCgpOworcHJpdmF0ZToKKyAgICB2b2lkIHNlbmQoY29uc3QgUUpzb25P
YmplY3QmIHZhbHVlKTsKKyAgICB2b2lkIGZhaWwoUVN0cmluZyBtZXNzYWdlKTsKKyAgICBRUHJv
Y2VzcyBtX3Byb2Nlc3M7CisgICAgUVRpbWVyIG1fdGltZW91dDsKKyAgICBRQnl0ZUFycmF5IG1f
YnVmZmVyOworICAgIFFWYXJpYW50TGlzdCBtX2l0ZW1zOworICAgIFFWYXJpYW50TWFwIG1fc3Rh
dGU7CisgICAgUVN0cmluZyBtX21vZGUsIG1fc3RhdHVzLCBtX3Byb21wdDsKKyAgICBib29sIG1f
YnVzeSA9IGZhbHNlOworfTsKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJu
ZXNzLnFtbCBiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbApuZXcgZmlsZSBtb2Rl
IDEwMDY0NAppbmRleCAwMDAwMDAwLi5iZjkwOTYxCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21v
b25saWdodG9zL3Rlc3RzL0hhcm5lc3MucW1sCkBAIC0wLDAgKzEsMjYgQEAKK2ltcG9ydCBRdFF1
aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5Db250
cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFN0
cmVhbWluZ1ByZWZlcmVuY2VzIDEuMAoraW1wb3J0IEVjbGlwc2VQcm9maWxlcyAxLjAKK2ltcG9y
dCAiLi4vLi4vZ3VpIgorQXBwbGljYXRpb25XaW5kb3cgeworICAgIE1hdGVyaWFsLnRoZW1lOiBN
YXRlcmlhbC5EYXJrCisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBN
YXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ1dpbmRvdworICAgIE1hdGVyaWFsLmZvcmVn
cm91bmQ6IFZiVG9rZW5zLnRleHQKKyAgICBjb2xvcjogVmJUb2tlbnMuYmdBcHAKKyAgICB3aWR0
aDogMTI4MDsgaGVpZ2h0OiA4MDA7IHZpc2libGU6IHRydWUKKyAgICBmdW5jdGlvbiBjaG9vc2VT
Y2FsZSh2YWx1ZSkgeyBFY2xpcHNlUHJvZmlsZXMudGV4dFNjYWxlPXZhbHVlIH0KKyAgICBmdW5j
dGlvbiBjaG9vc2VBY2NlbnQoaSkgeyBTdHJlYW1pbmdQcmVmZXJlbmNlcy51aUFjY2VudEluZGV4
ID0gaSB9CisgICAgSXRlbSB7IGlkOiBzdGFja1ZpZXcgfQorICAgIFF0T2JqZWN0IHsgb2JqZWN0
TmFtZTogInRlc3RTdGF0ZSI7IHByb3BlcnR5IGNvbG9yIGFjY2VudDogVmJUb2tlbnMuYWNjZW50
OyBwcm9wZXJ0eSBjb2xvciBwcmVzc2VkOiBWYlRva2Vucy5hY2NlbnRQcmVzc2VkIH0KKyAgICBD
cmltc29uU3RhdHVzRGlhbG9nIHsgb2JqZWN0TmFtZTogInRlc3RQYW5lbCIgfQorICAgIFN5c3Rl
bUNvbm5lY3Rpb25zRGlhbG9nIHsgb2JqZWN0TmFtZTogImNvbm5lY3Rpb25zUGFuZWwiIH0KKyAg
ICBFY2xpcHNlQ29udHJvbENlbnRlciB7IG9iamVjdE5hbWU6ICJjb250cm9sQ2VudGVyIiB9Cisg
ICAgU2Nyb2xsVmlldyB7IGlkOnN5c3RlbVNjcm9sbDsgb2JqZWN0TmFtZToic3lzdGVtU2Nyb2xs
Ijtjb250ZW50V2lkdGg6YXZhaWxhYmxlV2lkdGg7IGFuY2hvcnMuZmlsbDpwYXJlbnQ7IGFuY2hv
cnMubWFyZ2luczoyNDsgdmlzaWJsZTpzeXN0ZW1QYW5lbC5hY3RpdmUKKyAgICAgICAgRWNsaXBz
ZVN5c3RlbVNldHRpbmdzIHsgaWQ6c3lzdGVtUGFuZWw7b2JqZWN0TmFtZToic3lzdGVtU2V0dGlu
Z3MiO3dpZHRoOnN5c3RlbVNjcm9sbC5hdmFpbGFibGVXaWR0aDthY3RpdmU6ZmFsc2UgfQorICAg
IH0KKyAgICBFY2xpcHNlQWJvdXREaWFsb2cgeyBvYmplY3ROYW1lOiAiYWJvdXRFY2xpcHNlIiB9
Cit9CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sIGIv
YXBwL21vb25saWdodG9zL3Rlc3RzL1ByZWZlcmVuY2VzLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwLi45OTZlNWFjCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdo
dG9zL3Rlc3RzL1ByZWZlcmVuY2VzLnFtbApAQCAtMCwwICsxLDMgQEAKK3ByYWdtYSBTaW5nbGV0
b24KK2ltcG9ydCBRdFF1aWNrIDIuOQorUXRPYmplY3QgeyBwcm9wZXJ0eSBpbnQgdWlBY2NlbnRJ
bmRleDogNDsgcHJvcGVydHkgYm9vbCB1aVNob3dIaW50czogdHJ1ZTsgcHJvcGVydHkgaW50IHdp
ZHRoOiAxOTIwOyBwcm9wZXJ0eSBpbnQgaGVpZ2h0OiAxMDgwOyBwcm9wZXJ0eSBpbnQgZnBzOiA2
MDsgcHJvcGVydHkgaW50IGJpdHJhdGVLYnBzOiAyMDAwMDsgZnVuY3Rpb24gc2F2ZSgpIHt9IH0K
ZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24uY3BwIGIvYXBw
L21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAKbmV3IGZpbGUgbW9kZSAxMDA2NDQK
aW5kZXggMDAwMDAwMC4uMjMxMGM3MwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRv
cy90ZXN0cy90ZXN0LWNyaW1zb24uY3BwCkBAIC0wLDAgKzEsMzU1IEBACisjaW5jbHVkZSA8UXRU
ZXN0PgorI2luY2x1ZGUgPFFUZW1wb3JhcnlEaXI+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNp
bmNsdWRlIDxRUW1sQ29tcG9uZW50PgorI2luY2x1ZGUgPFFRbWxDb250ZXh0PgorI2luY2x1ZGUg
PFFRdWlja1N0eWxlPgorI2luY2x1ZGUgPFFRdWlja1dpbmRvdz4KKyNpbmNsdWRlIDxRUXVpY2tJ
dGVtPgorI2luY2x1ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFJbWFnZVJlYWRlcj4KKyNpbmNsdWRl
IDxRVGNwU2VydmVyPgorI2luY2x1ZGUgPFFTc2xTb2NrZXQ+CisjaW5jbHVkZSA8UVNzbEtleT4K
KyNpbmNsdWRlIDxRU3NsQ2VydGlmaWNhdGU+CisjaW5jbHVkZSA8UUNyeXB0b2dyYXBoaWNIYXNo
PgorI2luY2x1ZGUgPG1lbW9yeT4KKyNpbmNsdWRlIDxRU3RhbmRhcmRQYXRocz4KKyNpbmNsdWRl
IDxRRGlyPgorI2luY2x1ZGUgPFFGaWxlSW5mbz4KKyNpbmNsdWRlICIuLi9jcmltc29uc3RhdHVz
LmgiCisjaW5jbHVkZSAiLi4vc3lzdGVtY29udHJvbHMuaCIKKyNpbmNsdWRlICIuLi9lY2xpcHNl
cHJvZmlsZXMuaCIKKyNpbmNsdWRlICIuLi9sb2NhbGhhcmR3YXJlLmgiCisjaW5jbHVkZSAiLi4v
b3ZlcmxheXN0eWxlLmgiCisjaW5jbHVkZSAiLi4vLi4vYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tl
ci5oIgorCitjbGFzcyBUbHNGaXh0dXJlIDogcHVibGljIFFUY3BTZXJ2ZXIgeworcHVibGljOgor
ICAgIFFCeXRlQXJyYXkgYm9keSA9IFIiKHsiY3B1X3BlcmNlbnQiOjM3LjUsInJhbV91c2VkX2J5
dGVzIjo1MCwicmFtX3RvdGFsX2J5dGVzIjoxMDB9KSI7CisgICAgaW50IGNvZGUgPSAyMDAsIHJl
cXVlc3RzID0gMDsKKyAgICBib29sIHJlc3BvbmQgPSB0cnVlOworICAgIFFCeXRlQXJyYXkgYXV0
aG9yaXphdGlvbjsKKyAgICBRU3NsQ2VydGlmaWNhdGUgY2VydDsKKyAgICBRU3NsS2V5IGtleTsK
KyAgICBUbHNGaXh0dXJlKCkgeworICAgICAgICBRRmlsZSBjKHFFbnZpcm9ubWVudFZhcmlhYmxl
KCJDUklNU09OX1RFU1RfQ0VSVCIpKTsgYy5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpOyBjZXJ0
ID0gUVNzbENlcnRpZmljYXRlKGMucmVhZEFsbCgpKTsKKyAgICAgICAgUUZpbGUgayhxRW52aXJv
bm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9URVNUX0tFWSIpKTsgay5vcGVuKFFJT0RldmljZTo6UmVh
ZE9ubHkpOyBrZXkgPSBRU3NsS2V5KGsucmVhZEFsbCgpLCBRU3NsOjpSc2EpOworICAgICAgICBs
aXN0ZW4oUUhvc3RBZGRyZXNzOjpMb2NhbEhvc3QpOworICAgIH0KKyAgICB2b2lkIGluY29taW5n
Q29ubmVjdGlvbihxaW50cHRyIGRlc2NyaXB0b3IpIG92ZXJyaWRlIHsKKyAgICAgICAgYXV0byBz
b2NrZXQgPSBuZXcgUVNzbFNvY2tldCh0aGlzKTsKKyAgICAgICAgc29ja2V0LT5zZXRMb2NhbENl
cnRpZmljYXRlKGNlcnQpOyBzb2NrZXQtPnNldFByaXZhdGVLZXkoa2V5KTsgc29ja2V0LT5zZXRQ
ZWVyVmVyaWZ5TW9kZShRU3NsU29ja2V0OjpWZXJpZnlOb25lKTsKKyAgICAgICAgc29ja2V0LT5z
ZXRTb2NrZXREZXNjcmlwdG9yKGRlc2NyaXB0b3IpOworICAgICAgICBhdXRvIGlucHV0ID0gc3Rk
OjptYWtlX3NoYXJlZDxRQnl0ZUFycmF5PigpOworICAgICAgICBjb25uZWN0KHNvY2tldCwgJlFT
c2xTb2NrZXQ6OnJlYWR5UmVhZCwgdGhpcywgW3RoaXMsIHNvY2tldCwgaW5wdXRdIHsKKyAgICAg
ICAgICAgIGlucHV0LT5hcHBlbmQoc29ja2V0LT5yZWFkQWxsKCkpOworICAgICAgICAgICAgaWYg
KCFpbnB1dC0+Y29udGFpbnMoIlxyXG5cclxuIikpIHJldHVybjsKKyAgICAgICAgICAgICsrcmVx
dWVzdHM7IGF1dGhvcml6YXRpb24gPSAqaW5wdXQ7CisgICAgICAgICAgICBpZiAocmVzcG9uZCkg
eworICAgICAgICAgICAgICAgIFFCeXRlQXJyYXkgaGVhZGVyID0gIkhUVFAvMS4xICIgKyBRQnl0
ZUFycmF5OjpudW1iZXIoY29kZSkgKyAiIEZpeHR1cmVcclxuQ29udGVudC1UeXBlOiBhcHBsaWNh
dGlvbi9qc29uXHJcbkNvbm5lY3Rpb246IGNsb3NlXHJcbkNvbnRlbnQtTGVuZ3RoOiAiICsgUUJ5
dGVBcnJheTo6bnVtYmVyKGJvZHkuc2l6ZSgpKSArICJcclxuIjsKKyAgICAgICAgICAgICAgICBp
ZiAoY29kZSA9PSAzMDIpIGhlYWRlciArPSAiTG9jYXRpb246IGh0dHBzOi8vMTI3LjAuMC4yOjEy
MzQ1L1xyXG4iOworICAgICAgICAgICAgICAgIHNvY2tldC0+d3JpdGUoaGVhZGVyICsgIlxyXG4i
ICsgYm9keSk7IHNvY2tldC0+ZGlzY29ubmVjdEZyb21Ib3N0KCk7CisgICAgICAgICAgICB9Cisg
ICAgICAgICAgICBpbnB1dC0+Y2xlYXIoKTsKKyAgICAgICAgfSk7CisgICAgICAgIGNvbm5lY3Qo
c29ja2V0LCAmUVNzbFNvY2tldDo6ZGlzY29ubmVjdGVkLCBzb2NrZXQsICZRT2JqZWN0OjpkZWxl
dGVMYXRlcik7CisgICAgICAgIHNvY2tldC0+c3RhcnRTZXJ2ZXJFbmNyeXB0aW9uKCk7CisgICAg
fQorfTsKKworY2xhc3MgQ3JpbXNvblRlc3QgOiBwdWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpF
Q1QKK3ByaXZhdGUgc2xvdHM6CisgICAgdm9pZCBpbml0VGVzdENhc2UoKSB7CisgICAgICAgIFFD
b3JlQXBwbGljYXRpb246OnNldE9yZ2FuaXphdGlvbk5hbWUoIkVjbGlwc2VPUyBUZXN0Iik7Cisg
ICAgICAgIFFDb3JlQXBwbGljYXRpb246OnNldEFwcGxpY2F0aW9uTmFtZSgiRWNsaXBzZUZpeHR1
cmUiKTsKKyAgICAgICAgUVNldHRpbmdzOjpzZXREZWZhdWx0Rm9ybWF0KFFTZXR0aW5nczo6SW5p
Rm9ybWF0KTsKKyAgICB9CisgICAgdm9pZCBob3N0UHJvZmlsZXNSZW1haW5Jc29sYXRlZCgpIHsK
KyAgICAgICAgRWNsaXBzZVByb2ZpbGVzIHByb2ZpbGVzOworICAgICAgICBRVmFyaWFudE1hcCB2
YWx1ZXN7eyJ3aWR0aCIsMTI4MH0seyJoZWlnaHQiLDgwMH0seyJmcHMiLDYwfSx7ImJpdHJhdGVL
YnBzIiwxNTAwMH19OworICAgICAgICBRVkVSSUZZKHByb2ZpbGVzLnNhdmUoImZpeHR1cmUtaG9z
dC1hIiwiRGVza3RvcCIsdmFsdWVzKSk7CisgICAgICAgIFFDT01QQVJFKHByb2ZpbGVzLmxvYWQo
ImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIpLHZhbHVlcyk7CisgICAgICAgIFFWRVJJRlkocHJv
ZmlsZXMubG9hZCgiZml4dHVyZS1ob3N0LWIiLCJEZXNrdG9wIikuaXNFbXB0eSgpKTsKKyAgICAg
ICAgUVZFUklGWShwcm9maWxlcy5uYW1lcygiZml4dHVyZS1ob3N0LWEiKS5jb250YWlucygiRGVz
a3RvcCIpKTsKKyAgICAgICAgUVZFUklGWSghcHJvZmlsZXMucmVtb3ZlKCJmaXh0dXJlLWhvc3Qt
YSIsIkRlc2t0b3AiLGZhbHNlKSk7CisgICAgICAgIHZhbHVlc1siZnBzIl0gPSAwOyBRVkVSSUZZ
KCFwcm9maWxlcy5zYXZlKCJmaXh0dXJlLWhvc3QtYSIsIkJhZCIsdmFsdWVzKSk7CisgICAgICAg
IFFWRVJJRlkocHJvZmlsZXMucmVtb3ZlKCJmaXh0dXJlLWhvc3QtYSIsIkRlc2t0b3AiLHRydWUp
KTsKKyAgICAgICAgUVZFUklGWShwcm9maWxlcy5sb2FkKCJmaXh0dXJlLWhvc3QtYSIsIkRlc2t0
b3AiKS5pc0VtcHR5KCkpOworICAgIH0KKyAgICB2b2lkIHN5c3RlbUNvbnRyb2xzUHJpdmF0ZVBp
cGUoKSB7CisgICAgICAgIFFUZW1wb3JhcnlEaXIgZGlyOyBRVkVSSUZZKGRpci5pc1ZhbGlkKCkp
OworICAgICAgICBRRmlsZSBzY3JpcHQoZGlyLmZpbGVQYXRoKCJmaXh0dXJlLnB5IikpOyBRVkVS
SUZZKHNjcmlwdC5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7CisgICAgICAgIHNjcmlwdC53
cml0ZShSIlBZKGltcG9ydCBqc29uLHN5cworZm9yIGxpbmUgaW4gc3lzLnN0ZGluOgorICAgIHZh
bHVlPWpzb24ubG9hZHMobGluZSkKKyAgICBhY3Rpb249dmFsdWVbJ2FjdGlvbiddCisgICAgaWYg
YWN0aW9uPT0nd2lmaS1jb25uZWN0JzoKKyAgICAgICAgcHJpbnQoanNvbi5kdW1wcyh7J3Byb21w
dCc6J1dpLUZpIHBhc3N3b3JkJ30pLGZsdXNoPVRydWUpCisgICAgICAgIHJlcGx5PWpzb24ubG9h
ZHMoc3lzLnN0ZGluLnJlYWRsaW5lKCkpCisgICAgICAgIGFzc2VydCByZXBseT09eydhY3Rpb24n
OidhbnN3ZXInLCd2YWx1ZSc6J3NlY3JldC12YWx1ZSd9CisgICAgcHJpbnQoanNvbi5kdW1wcyh7
J2l0ZW1zJzpbeydpZCc6J3dsYW4wL0FBOkJCOkNDOkREOkVFOkZGJywnbmFtZSc6JzxiPlBsYWlu
IFNTSUQ8L2I+JywnZGV0YWlsJzonODAlIFdQQTInLCdjb25uZWN0ZWQnOmFjdGlvbj09J3dpZmkt
Y29ubmVjdCd9XSwnc3RhdHVzJzonUmVhZHknLCdkb25lJzpUcnVlfSksZmx1c2g9VHJ1ZSkKKylQ
WSIpOyBzY3JpcHQuY2xvc2UoKTsKKyAgICAgICAgcXB1dGVudigiTU9PTkxJR0hUX0NPTlRST0xT
X0ZJWFRVUkUiLCBzY3JpcHQuZmlsZU5hbWUoKS50b1V0ZjgoKSk7CisgICAgICAgIFN5c3RlbUNv
bnRyb2xzIGNvbnRyb2xzOyBjb250cm9scy5vcGVuKCJ3aWZpIik7CisgICAgICAgIFFUUllfQ09N
UEFSRShjb250cm9scy5pdGVtcygpLnNpemUoKSwgMSk7IFFWRVJJRlkoIWNvbnRyb2xzLmJ1c3ko
KSk7CisgICAgICAgIGNvbnRyb2xzLnJlcXVlc3QoImJ0LWZvcmdldCIsICJpbnZhbGlkIiwgdHJ1
ZSk7IFFWRVJJRlkoIWNvbnRyb2xzLmJ1c3koKSk7CisgICAgICAgIGNvbnRyb2xzLnJlcXVlc3Qo
IndpZmktY29ubmVjdCIsICJ3bGFuMC9BQTpCQjpDQzpERDpFRTpGRiIpOworICAgICAgICBRVFJZ
X1ZFUklGWSghY29udHJvbHMucHJvbXB0KCkuaXNFbXB0eSgpKTsgUVZFUklGWShjb250cm9scy5i
dXN5KCkpOworICAgICAgICBjb250cm9scy5hbnN3ZXIoInNlY3JldC12YWx1ZSIpOyBRVFJZX1ZF
UklGWSghY29udHJvbHMuYnVzeSgpKTsKKyAgICAgICAgUVZFUklGWShjb250cm9scy5wcm9tcHQo
KS5pc0VtcHR5KCkpOyBRQ09NUEFSRShjb250cm9scy5zdGF0dXMoKSwgUVN0cmluZygiUmVhZHki
KSk7CisgICAgICAgIFFWRVJJRlkoY29udHJvbHMuaXRlbXMoKS5maXJzdCgpLnRvTWFwKCkudmFs
dWUoImNvbm5lY3RlZCIpLnRvQm9vbCgpKTsKKyAgICAgICAgY29udHJvbHMuY2xvc2UoKTsgUVZF
UklGWSghY29udHJvbHMuYnVzeSgpKTsKKyAgICAgICAgcXVuc2V0ZW52KCJNT09OTElHSFRfQ09O
VFJPTFNfRklYVFVSRSIpOworICAgIH0KKyAgICB2b2lkIG1hbmFnZWRVcGRhdGVyQ2Fubm90UmVw
bGFjZUN1c3RvbWl6ZWRDbGllbnQoKSB7CisgICAgICAgIFFUZW1wb3JhcnlEaXIgZGlyOyBRVkVS
SUZZKGRpci5pc1ZhbGlkKCkpOworICAgICAgICBjb25zdCBRU3RyaW5nIGltYWdlID0gZGlyLmZp
bGVQYXRoKCJjdXN0b20uQXBwSW1hZ2UiKTsKKyAgICAgICAgUUZpbGUgZihpbWFnZSk7IFFWRVJJ
RlkoZi5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7IGYud3JpdGUoImN1c3RvbWl6ZWQgY2xp
ZW50Iik7IGYuY2xvc2UoKTsKKyAgICAgICAgY29uc3QgUUJ5dGVBcnJheSBvbGQgPSBxZ2V0ZW52
KCJBUFBJTUFHRSIpOyBjb25zdCBib29sIGhhZCA9IHFFbnZpcm9ubWVudFZhcmlhYmxlSXNTZXQo
IkFQUElNQUdFIik7CisgICAgICAgIHFwdXRlbnYoIkFQUElNQUdFIiwgaW1hZ2UudG9VdGY4KCkp
OworICAgICAgICBBdXRvVXBkYXRlQ2hlY2tlciBjaGVja2VyOworICAgICAgICBRVkVSSUZZKGNo
ZWNrZXIub3NNYW5hZ2VkKCkpOyBRVkVSSUZZKCFjaGVja2VyLmNhbkluc3RhbGxVcGRhdGVzKCkp
OworICAgICAgICBRU2lnbmFsU3B5IGNvbXBsZXRlZCgmY2hlY2tlciwgJkF1dG9VcGRhdGVDaGVj
a2VyOjpjaGVja0NvbXBsZXRlZCk7CisgICAgICAgIFFTaWduYWxTcHkgZmFpbGVkKCZjaGVja2Vy
LCAmQXV0b1VwZGF0ZUNoZWNrZXI6Omluc3RhbGxGYWlsZWQpOworICAgICAgICBjaGVja2VyLnN0
YXJ0KCk7IGNoZWNrZXIuY2hlY2tOb3coKTsgY2hlY2tlci5jaGFubmVsQ2hhbmdlZCgpOyBjaGVj
a2VyLmluc3RhbGwoKTsKKyAgICAgICAgUUNPTVBBUkUoY29tcGxldGVkLmNvdW50KCksIDMpOyBR
Q09NUEFSRShmYWlsZWQuY291bnQoKSwgMSk7CisgICAgICAgIFFWRVJJRlkoIWNoZWNrZXIuY2hl
Y2tpbmcoKSk7IFFWRVJJRlkoIWNoZWNrZXIuaW5zdGFsbGluZygpKTsKKyAgICAgICAgUVZFUklG
WSghY2hlY2tlci5jYW5JbnN0YWxsKCkpOyBRVkVSSUZZKCFjaGVja2VyLnVwZGF0ZUF2YWlsYWJs
ZSgpKTsgUVZFUklGWSghY2hlY2tlci5vZmZlckF2YWlsYWJsZSgpKTsKKyAgICAgICAgUUNPTVBB
UkUoY2hlY2tlci5yZWxlYXNlVXJsKCksIFFTdHJpbmcoImh0dHBzOi8vZ2l0aHViLmNvbS90aDNk
M2NrM3IvTW9vbmxpZ2h0LU9TL3JlbGVhc2VzIikpOworICAgICAgICBRVkVSSUZZKGNoZWNrZXIu
Y3VycmVudFZlcnNpb24oKS5jb250YWlucygiRWNsaXBzZU9TIGN1c3RvbWl6ZWQiKSk7CisgICAg
ICAgIFFWRVJJRlkoZi5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpKTsgUUNPTVBBUkUoZi5yZWFk
QWxsKCksIFFCeXRlQXJyYXkoImN1c3RvbWl6ZWQgY2xpZW50IikpOyBmLmNsb3NlKCk7CisgICAg
ICAgIFFDT01QQVJFKFFEaXIoZGlyLnBhdGgoKSkuZW50cnlMaXN0KFFEaXI6OkZpbGVzKSwgUVN0
cmluZ0xpc3R7ImN1c3RvbS5BcHBJbWFnZSJ9KTsKKyAgICAgICAgaWYgKGhhZCkgcXB1dGVudigi
QVBQSU1BR0UiLCBvbGQpOyBlbHNlIHF1bnNldGVudigiQVBQSU1BR0UiKTsKKyAgICAgICAgUUNP
TVBBUkUoQXV0b1VwZGF0ZUNoZWNrZXI6OmNvbXBhcmVTZW1hbnRpY1ZlcnNpb25zKCIwLjUuMCIs
ICIwLjQuOSIpLCAxKTsKKyAgICB9CisgICAgdm9pZCBlbmRwb2ludFZhbGlkYXRpb24oKSB7Cisg
ICAgICAgIFFWRVJJRlkoQ3JpbXNvblN0YXR1czo6dmFsaWRFbmRwb2ludCgiaHR0cHM6Ly8xOTIu
MTY4LjEuMTA6NDc5OTAiKSk7CisgICAgICAgIFFWRVJJRlkoQ3JpbXNvblN0YXR1czo6dmFsaWRF
bmRwb2ludCgiaHR0cHM6Ly9bZmQwMDo6MV06NDc5OTAvIikpOworICAgICAgICBmb3IgKGF1dG8g
YmFkIDogeyJodHRwOi8vaG9zdCIsICJodHRwczovL3VzZXI6c2VjcmV0QGhvc3QiLCAiaHR0cHM6
Ly9ob3N0L2FwaSIsICJodHRwczovL2hvc3QvP3Rva2VuPXNlY3JldCIsICJmaWxlOi8vL2V0Yy9w
YXNzd2QiLCAiaHR0cHM6Ly9ob3N0LyNmcmFnbWVudCJ9KQorICAgICAgICAgICAgUVZFUklGWSgh
Q3JpbXNvblN0YXR1czo6dmFsaWRFbmRwb2ludChiYWQpKTsKKyAgICB9CisgICAgdm9pZCBtaXNz
aW5nQW5kSW52YWxpZE1ldHJpY3MoKSB7CisgICAgICAgIFFTdHJpbmcgZXJyb3I7CisgICAgICAg
IFFWRVJJRlkoQ3JpbXNvblN0YXR1czo6cGFyc2VTdGF0cygibm90IGpzb24iLCAmZXJyb3IpLmlz
RW1wdHkoKSk7IFFWRVJJRlkoIWVycm9yLmlzRW1wdHkoKSk7CisgICAgICAgIGF1dG8gcyA9IENy
aW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJjcHVfcGVyY2VudCI6NDIuNSwiY3B1X3RlbXBf
YyI6LTEsImdwdV9wZXJjZW50IjpudWxsLCJyYW1fdG90YWxfYnl0ZXMiOjAsInJhbV9wZXJjZW50
IjowLCJ2cmFtX3RvdGFsX2J5dGVzIjoxMDAsInZyYW1fdXNlZF9ieXRlcyI6MTIwfSkiLCAmZXJy
b3IpOworICAgICAgICBRVkVSSUZZKGVycm9yLmlzRW1wdHkoKSk7IFFDT01QQVJFKHMudmFsdWUo
ImNwdV9wZXJjZW50IikudG9Eb3VibGUoKSwgNDIuNSk7CisgICAgICAgIFFWRVJJRlkoIXMuY29u
dGFpbnMoImNwdV90ZW1wX2MiKSk7IFFWRVJJRlkoIXMuY29udGFpbnMoImdwdV9wZXJjZW50Iikp
OyBRVkVSSUZZKCFzLmNvbnRhaW5zKCJyYW1fcGVyY2VudCIpKTsKKyAgICAgICAgUUNPTVBBUkUo
cy52YWx1ZSgidnJhbV9wZXJjZW50IikudG9Eb3VibGUoKSwgMTAwLjApOworICAgICAgICBhdXRv
IGludmFsaWQgPSBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKFIiKHsiY3B1X3BlcmNlbnQiOjEw
MSwiZ3B1X3BlcmNlbnQiOiIwIn0pIiwgJmVycm9yKTsKKyAgICAgICAgUVZFUklGWShpbnZhbGlk
LmlzRW1wdHkoKSk7IFFWRVJJRlkoZXJyb3IuaXNFbXB0eSgpKTsKKyAgICAgICAgQ3JpbXNvblN0
YXR1czo6cGFyc2VTdGF0cyhRQnl0ZUFycmF5KDY1NTM3LCAnYScpLCAmZXJyb3IpOyBRVkVSSUZZ
KCFlcnJvci5pc0VtcHR5KCkpOworICAgICAgICBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKFIi
KHsiZXJyb3IiOiJ1bnN1cHBvcnRlZCJ9KSIsICZlcnJvcik7IFFWRVJJRlkoIWVycm9yLmlzRW1w
dHkoKSk7CisgICAgfQorICAgIHZvaWQgbG9jYWxIYXJkd2FyZUZpeHR1cmUoKSB7CisgICAgICAg
IFFUZW1wb3JhcnlEaXIgdGVtcDsgUVZFUklGWSh0ZW1wLmlzVmFsaWQoKSk7CisgICAgICAgIGF1
dG8gd3JpdGUgPSBbJl0oUVN0cmluZyBwLCBRQnl0ZUFycmF5IHZhbHVlKSB7IFFEaXIoKS5ta3Bh
dGgoUUZpbGVJbmZvKHRlbXAucGF0aCgpK3ApLmFic29sdXRlUGF0aCgpKTsgUUZpbGUgZih0ZW1w
LnBhdGgoKStwKTsgUVZFUklGWShmLm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsgZi53cml0
ZSh2YWx1ZSk7IH07CisgICAgICAgIHdyaXRlKCIvY2xhc3MvcG93ZXJfc3VwcGx5L0JBVDAvdHlw
ZSIsICJCYXR0ZXJ5Iik7IHdyaXRlKCIvY2xhc3MvcG93ZXJfc3VwcGx5L0JBVDAvY2FwYWNpdHki
LCAiNzMiKTsgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9zdGF0dXMiLCAiQ2hhcmdp
bmciKTsKKyAgICAgICAgd3JpdGUoIi9jbGFzcy9uZXQvd2xhbjAvb3BlcnN0YXRlIiwgInVwIik7
IHdyaXRlKCIvY2xhc3MvbmV0L2xvL29wZXJzdGF0ZSIsICJ1cCIpOworICAgICAgICBhdXRvIGxv
Y2FsID0gQ3JpbXNvblN0YXR1czo6cmVhZExvY2FsKHRlbXAucGF0aCgpKTsgUUNPTVBBUkUobG9j
YWwudmFsdWUoImJhdHRlcnlQZXJjZW50IikudG9JbnQoKSwgNzMpOyBRQ09NUEFSRShsb2NhbC52
YWx1ZSgiYmF0dGVyeVN0YXRlIikudG9TdHJpbmcoKSwgUVN0cmluZygiQ2hhcmdpbmciKSk7Cisg
ICAgICAgIFFDT01QQVJFKGxvY2FsLnZhbHVlKCJuZXR3b3JrIikudG9TdHJpbmcoKSwgUVN0cmlu
Zygid2xhbjAiKSk7IFFWRVJJRlkobG9jYWwudmFsdWUoImNvbm5lY3RlZCIpLnRvQm9vbCgpKTsK
KyAgICAgICAgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9jYXBhY2l0eSIsICIxMDEi
KTsgUUNPTVBBUkUoQ3JpbXNvblN0YXR1czo6cmVhZExvY2FsKHRlbXAucGF0aCgpKS52YWx1ZSgi
YmF0dGVyeVBlcmNlbnQiKS50b0ludCgpLCAtMSk7CisgICAgfQorICAgIHZvaWQgcHJpdmF0ZVNl
dHRpbmdzQW5kTm9Dcm9zc0hvc3RDcmVkZW50aWFscygpIHsKKyAgICAgICAgUVN0YW5kYXJkUGF0
aHM6OnNldFRlc3RNb2RlRW5hYmxlZCh0cnVlKTsKKyAgICAgICAgQ3JpbXNvblN0YXR1cyBzdGF0
dXM7IHN0YXR1cy5zZWxlY3RIb3N0KCJ0ZXN0LWEiLCAiaHR0cHM6Ly8xMjcuMC4wLjE6NDc5OTAi
KTsKKyAgICAgICAgUVZFUklGWShzdGF0dXMuY29uZmlndXJlKCJodHRwczovLzEyNy4wLjAuMTo0
Nzk5MCIsICJmaXh0dXJlLXRva2VuIiwgIiIpKTsgUVZFUklGWShzdGF0dXMuY29uZmlndXJlZCgp
KTsKKyAgICAgICAgYXV0byBwYXRoID0gUVN0YW5kYXJkUGF0aHM6OndyaXRhYmxlTG9jYXRpb24o
UVN0YW5kYXJkUGF0aHM6OkFwcENvbmZpZ0xvY2F0aW9uKSArICIvY3JpbXNvbi1ob3N0cy5qc29u
IjsKKyAgICAgICAgUVZFUklGWSgoUUZpbGU6OnBlcm1pc3Npb25zKHBhdGgpICYgKFFGaWxlRGV2
aWNlOjpSZWFkR3JvdXAgfCBRRmlsZURldmljZTo6UmVhZE90aGVyIHwgUUZpbGVEZXZpY2U6Oldy
aXRlR3JvdXAgfCBRRmlsZURldmljZTo6V3JpdGVPdGhlcikpID09IDApOworICAgICAgICBzdGF0
dXMuc2VsZWN0SG9zdCgidGVzdC1iIiwgImh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIik7IFFWRVJJ
RlkoIXN0YXR1cy5jb25maWd1cmVkKCkpOworICAgICAgICBRVkVSSUZZKCFzdGF0dXMuY29uZmln
dXJlKCJodHRwczovLzEyNy4wLjAuMjo0Nzk5MCIsICIiLCAiIikpOworICAgICAgICBRVkVSSUZZ
KCFzdGF0dXMuY29uZmlndXJlKCJodHRwczovLzEyNy4wLjAuMjo0Nzk5MCIsICJmaXh0dXJlLXRv
a2VuIiwgImludmFsaWQtcGluIikpOworICAgICAgICBRVkVSSUZZKCFzdGF0dXMuY29uZmlndXJl
KCJodHRwczovLzEyNy4wLjAuMjo0Nzk5MCIsICJ0b2tlblxuaW5qZWN0aW9uIiwgIiIpKTsKKyAg
ICAgICAgUUZpbGU6OnJlbW92ZShwYXRoKTsKKyAgICB9CisgICAgdm9pZCB0bHNBdXRoZW50aWNh
dGlvbkFuZFZpc2liaWxpdHkoKSB7CisgICAgICAgIFRsc0ZpeHR1cmUgc2VydmVyOyBRVkVSSUZZ
KHNlcnZlci5pc0xpc3RlbmluZygpKTsgUVZFUklGWSghc2VydmVyLmNlcnQuaXNOdWxsKCkpOwor
ICAgICAgICBRU3RyaW5nIHVybCA9ICJodHRwczovLzEyNy4wLjAuMToiICsgUVN0cmluZzo6bnVt
YmVyKHNlcnZlci5zZXJ2ZXJQb3J0KCkpOworICAgICAgICBRU3RyaW5nIHBpbiA9IFFTdHJpbmc6
OmZyb21MYXRpbjEoc2VydmVyLmNlcnQuZGlnZXN0KFFDcnlwdG9ncmFwaGljSGFzaDo6U2hhMjU2
KS50b0hleCgpKTsKKyAgICAgICAgQ3JpbXNvblN0YXR1cyBzdGF0dXM7IHN0YXR1cy5zZWxlY3RI
b3N0KCJmaXh0dXJlLXRscyIsIHVybCk7CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3Vy
ZSh1cmwsICJmaXh0dXJlLW9ubHktdG9rZW4iLCAiIikpOyBzdGF0dXMuc2V0VmlzaWJsZSh0cnVl
KTsKKyAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHN0YXR1cy5zdGF0dXMoKS5jb250
YWlucygiZmluZ2VycHJpbnQiKSwgNTAwMCk7CisgICAgICAgIFFDT01QQVJFKHNlcnZlci5yZXF1
ZXN0cywgMCk7IC8vIG5vIGNyZWRlbnRpYWxzIHNlbnQgYmVmb3JlIHRydXN0aW5nIHNlbGYtc2ln
bmVkIFRMUworICAgICAgICBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmUodXJsLCAiZml4dHVyZS1v
bmx5LXRva2VuIiwgcGluKSk7CisgICAgICAgIFFUUllfQ09NUEFSRV9XSVRIX1RJTUVPVVQoc3Rh
dHVzLnN0YXRzKCkudmFsdWUoImNwdV9wZXJjZW50IikudG9Eb3VibGUoKSwgMzcuNSwgNTAwMCk7
CisgICAgICAgIFFWRVJJRlkoc2VydmVyLmF1dGhvcml6YXRpb24uY29udGFpbnMoIkF1dGhvcml6
YXRpb246IEJlYXJlciBmaXh0dXJlLW9ubHktdG9rZW4iKSk7CisgICAgICAgIFFWRVJJRlkoc2Vy
dmVyLmF1dGhvcml6YXRpb24uc3RhcnRzV2l0aCgiR0VUIC9hcGkvaG9zdC9zdGF0cyAiKSk7Cisg
ICAgICAgIHN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsgaW50IGNvdW50ID0gc2VydmVyLnJlcXVl
c3RzOyBRVGVzdDo6cVdhaXQoMjEwMCk7IFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywgY291bnQp
OworICAgICAgICBmb3IgKGludCBjb2RlIDogezQwMSwgNDAzLCA0MDQsIDMwMn0pIHsKKyAgICAg
ICAgICAgIHNlcnZlci5jb2RlID0gY29kZTsgaW50IHByaW9yID0gc2VydmVyLnJlcXVlc3RzOyBz
dGF0dXMuc2V0VmlzaWJsZSh0cnVlKTsKKyAgICAgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElN
RU9VVChzZXJ2ZXIucmVxdWVzdHMgPiBwcmlvciwgNTAwMCk7CisgICAgICAgICAgICBRVFJZX1ZF
UklGWV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0YXRzKCkuaXNFbXB0eSgpLCA1MDAwKTsKKyAgICAg
ICAgICAgIHN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsKKyAgICAgICAgfQorICAgICAgICBzZXJ2
ZXIuY29kZSA9IDIwMDsgc2VydmVyLmJvZHkgPSBRQnl0ZUFycmF5KDcwMDAwLCAnYScpOyBpbnQg
cHJpb3IgPSBzZXJ2ZXIucmVxdWVzdHM7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAg
ICBRVFJZX1ZFUklGWV9XSVRIX1RJTUVPVVQoc2VydmVyLnJlcXVlc3RzID4gcHJpb3IsIDUwMDAp
OworICAgICAgICBRVFJZX1ZFUklGWV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0YXRzKCkuaXNFbXB0
eSgpLCA1MDAwKTsgc3RhdHVzLnNldFZpc2libGUoZmFsc2UpOworICAgICAgICBRVkVSSUZZKHN0
YXR1cy5jb25maWd1cmUodXJsLCAiZml4dHVyZS1vbmx5LXRva2VuIiwgUVN0cmluZyg2NCwgJzAn
KSkpOyBzdGF0dXMuc2V0VmlzaWJsZSh0cnVlKTsKKyAgICAgICAgY291bnQgPSBzZXJ2ZXIucmVx
dWVzdHM7IFFUZXN0OjpxV2FpdCg1MDApOyBRQ09NUEFSRShzZXJ2ZXIucmVxdWVzdHMsIGNvdW50
KTsgUVZFUklGWShzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCkpOworICAgICAgICBzdGF0dXMuc2V0
VmlzaWJsZShmYWxzZSk7CisgICAgfQorICAgIHZvaWQgcm91bmRlZE92ZXJsYXlBY2NlbnRzQW5k
T3BhY2l0eSgpIHsKKyAgICAgICAgZm9yKGludCBhY2NlbnQ9MDthY2NlbnQ8MTY7KythY2NlbnQp
IHsKKyAgICAgICAgICAgIGF1dG8gaW1hZ2U9RWNsaXBzZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNp
emUoNDAwLDE4MCksYWNjZW50LDg1KTsgUVZFUklGWSghaW1hZ2UuaXNOdWxsKCkpOworICAgICAg
ICAgICAgUUNPTVBBUkUoaW1hZ2UucGl4ZWxDb2xvcigwLDApLmFscGhhKCksMCk7CisgICAgICAg
ICAgICBRQ09NUEFSRShpbWFnZS5waXhlbENvbG9yKDIwMCw5MCkuYWxwaGEoKSw4NSoyNTUvMTAw
KTsKKyAgICAgICAgICAgIFFDT01QQVJFKGltYWdlLnBpeGVsQ29sb3IoMjAwLDgpLnJnYigpLEVj
bGlwc2VPdmVybGF5U3R5bGU6OmFjY2VudChhY2NlbnQpLnJnYigpKTsKKyAgICAgICAgfQorICAg
ICAgICBRVkVSSUZZKEVjbGlwc2VPdmVybGF5U3R5bGU6OnBhbmVsKFFTaXplKC0xLDEwMCksMCw4
NSkuaXNOdWxsKCkpOworICAgICAgICBRVkVSSUZZKEVjbGlwc2VPdmVybGF5U3R5bGU6OnBhbmVs
KFFTaXplKDQwOTYsMTAwKSwwLDg1KS5pc051bGwoKSk7CisgICAgfQorICAgIHZvaWQgbG9jYWxI
YXJkd2FyZUNvdW50ZXJzQW5kU2Vuc29ycygpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciByb290
OyBRVkVSSUZZKHJvb3QuaXNWYWxpZCgpKTsKKyAgICAgICAgYXV0byB3cml0ZT1bJl0oY29uc3Qg
UVN0cmluZyYgcGF0aCxjb25zdCBRQnl0ZUFycmF5JiBkYXRhKSB7IFFTdHJpbmcgZnVsbD1yb290
LnBhdGgoKStwYXRoOyBRRGlyKCkubWtwYXRoKFFGaWxlSW5mbyhmdWxsKS5hYnNvbHV0ZVBhdGgo
KSk7IFFGaWxlIGZpbGUoZnVsbCk7IFFWRVJJRlkoZmlsZS5vcGVuKFFJT0RldmljZTo6V3JpdGVP
bmx5KSk7IFFDT01QQVJFKGZpbGUud3JpdGUoZGF0YSkscWludDY0KGRhdGEuc2l6ZSgpKSk7IH07
CisgICAgICAgIFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlL2hhcmR3YXJlUmVmcmVzaCIs
MSk7CisgICAgICAgIHdyaXRlKCIvcHJvYy9zdGF0IiwiY3B1IDEwMCAwIDEwMCA4MDAgMCAwIDAg
MFxuIik7CisgICAgICAgIHdyaXRlKCIvcHJvYy9tZW1pbmZvIiwiTWVtVG90YWw6IDEwNDg1NzYg
a0Jcbk1lbUF2YWlsYWJsZTogMjYyMTQ0IGtCXG5Td2FwVG90YWw6IDEwMjQga0JcblN3YXBGcmVl
OiA1MTIga0JcbiIpOworICAgICAgICB3cml0ZSgiL3N5cy9jbGFzcy9od21vbi9od21vbjAvbmFt
ZSIsImNvcmV0ZW1wIik7IHdyaXRlKCIvc3lzL2NsYXNzL2h3bW9uL2h3bW9uMC90ZW1wMV9pbnB1
dCIsIjYyNTAwIik7CisgICAgICAgIHdyaXRlKCIvc3lzL2NsYXNzL2h3bW9uL2h3bW9uMC9mYW4x
X2lucHV0IiwiMjQwMCIpOworICAgICAgICB3cml0ZSgiL3Byb2MvbmV0L3JvdXRlIiwiSWZhY2Ug
RGVzdGluYXRpb24gR2F0ZXdheSBGbGFnc1xud2xhbjAgMDAwMDAwMDAgMDEwMjAzMDQgMDAwM1xu
Iik7CisgICAgICAgIHdyaXRlKCIvcHJvYy9uZXQvZGV2Iiwid2xhbjA6IDEwMDAgMCAwIDAgMCAw
IDAgMCAyMDAwIDAgMCAwIDAgMCAwIDBcbiIpOworICAgICAgICBRQnl0ZUFycmF5IHZpZGVvPSJk
cm0tY2xpZW50LWlkOiA3XG5kcm0tZW5naW5lLXZpZGVvOiAxMDAwMDAwMDAgbnNcbiI7CisgICAg
ICAgIHdyaXRlKCIvcHJvYy9zZWxmL2ZkaW5mby8xIix2aWRlbyk7IHdyaXRlKCIvcHJvYy9zZWxm
L2ZkaW5mby8yIix2aWRlbyk7CisgICAgICAgIGF1dG8gZmlyc3Q9TG9jYWxIYXJkd2FyZTo6c2Ft
cGxlKHJvb3QucGF0aCgpKTsgUVZFUklGWSghZmlyc3QuY29udGFpbnMoImNwdVBlcmNlbnQiKSk7
IFFWRVJJRlkoIWZpcnN0LmNvbnRhaW5zKCJ2aWRlb1BlcmNlbnQiKSk7CisgICAgICAgIFFDT01Q
QVJFKGZpcnN0WyJtZW1vcnlQZXJjZW50Il0udG9Eb3VibGUoKSw3NS4wKTsgUUNPTVBBUkUoZmly
c3RbInRlbXBlcmF0dXJlQyJdLnRvRG91YmxlKCksNjIuNSk7IFFDT01QQVJFKGZpcnN0WyJmYW5S
UE0iXS50b0RvdWJsZSgpLDI0MDAuMCk7CisgICAgICAgIFFUZXN0OjpxV2FpdCgxMDUwKTsKKyAg
ICAgICAgd3JpdGUoIi9wcm9jL3N0YXQiLCJjcHUgMTUwIDAgMTUwIDkwMCAwIDAgMCAwXG4iKTsK
KyAgICAgICAgdmlkZW89ImRybS1jbGllbnQtaWQ6IDdcbmRybS1lbmdpbmUtdmlkZW86IDIwMDAw
MDAwMCBuc1xuIjsKKyAgICAgICAgd3JpdGUoIi9wcm9jL3NlbGYvZmRpbmZvLzEiLHZpZGVvKTsg
d3JpdGUoIi9wcm9jL3NlbGYvZmRpbmZvLzIiLHZpZGVvKTsKKyAgICAgICAgd3JpdGUoIi9wcm9j
L25ldC9kZXYiLCJ3bGFuMDogMTA0OTU3NiAwIDAgMCAwIDAgMCAwIDUyNjI4OCAwIDAgMCAwIDAg
MCAwXG4iKTsKKyAgICAgICAgYXV0byBzZWNvbmQ9TG9jYWxIYXJkd2FyZTo6c2FtcGxlKHJvb3Qu
cGF0aCgpKTsgUUNPTVBBUkUoc2Vjb25kWyJjcHVQZXJjZW50Il0udG9Eb3VibGUoKSw1MC4wKTsK
KyAgICAgICAgUVZFUklGWShzZWNvbmRbInZpZGVvUGVyY2VudCJdLnRvRG91YmxlKCk+NSAmJiBz
ZWNvbmRbInZpZGVvUGVyY2VudCJdLnRvRG91YmxlKCk8MTEpOyAvLyBkdXBsaWNhdGUgZmQgbXVz
dCBub3QgZG91YmxlLWNvdW50CisgICAgICAgIFFWRVJJRlkoc2Vjb25kWyJyZWNlaXZlTWlCIl0u
dG9Eb3VibGUoKT4uNSAmJiBzZWNvbmRbInJlY2VpdmVNaUIiXS50b0RvdWJsZSgpPDEuMSk7Cisg
ICAgICAgIFFUZXN0OjpxV2FpdCgxMDUwKTsKKyAgICAgICAgd3JpdGUoIi9wcm9jL3N0YXQiLCJj
cHUgMSAwIDEgMSAwIDAgMCAwXG4iKTsgd3JpdGUoIi9wcm9jL25ldC9kZXYiLCJ3bGFuMDogMSAw
IDAgMCAwIDAgMCAwIDEgMCAwIDAgMCAwIDAgMFxuIik7CisgICAgICAgIGF1dG8gcmVzZXQ9TG9j
YWxIYXJkd2FyZTo6c2FtcGxlKHJvb3QucGF0aCgpKTsgUVZFUklGWSghcmVzZXQuY29udGFpbnMo
ImNwdVBlcmNlbnQiKSk7IFFWRVJJRlkoIXJlc2V0LmNvbnRhaW5zKCJyZWNlaXZlTWlCIikpOwor
ICAgICAgICBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS9oYXJkd2FyZVJlZnJlc2giLDIp
OworICAgIH0KKyAgICB2b2lkIGxvY2FsSGFyZHdhcmVVbmF2YWlsYWJsZUFuZEJvdW5kcygpIHsK
KyAgICAgICAgUVRlbXBvcmFyeURpciByb290OyBRVkVSSUZZKHJvb3QuaXNWYWxpZCgpKTsKKyAg
ICAgICAgYXV0byBlbXB0eT1Mb2NhbEhhcmR3YXJlOjpzYW1wbGUocm9vdC5wYXRoKCkpOyBRVkVS
SUZZKGVtcHR5LmlzRW1wdHkoKSk7CisgICAgICAgIExvY2FsSGFyZHdhcmUgbW9uaXRvcjsgbW9u
aXRvci5zZXRQb3NpdGlvbig5OTkpOyBRQ09NUEFSRShtb25pdG9yLnBvc2l0aW9uKCksMyk7Cisg
ICAgICAgIG1vbml0b3Iuc2V0T3BhY2l0eSgtNSk7IFFDT01QQVJFKG1vbml0b3Iub3BhY2l0eSgp
LDQwKTsKKyAgICAgICAgbW9uaXRvci5zZXRSZWZyZXNoU2Vjb25kcyg5OTkpOyBRQ09NUEFSRSht
b25pdG9yLnJlZnJlc2hTZWNvbmRzKCksNSk7CisgICAgICAgIG1vbml0b3Iuc2V0RmllbGRzKHsi
Y3B1IiwicGFzc3dvcmQiLCJtZW1vcnkifSk7IFFDT01QQVJFKG1vbml0b3IuZmllbGRzKCksUVN0
cmluZ0xpc3QoeyJjcHUiLCJtZW1vcnkifSkpOworICAgICAgICBtb25pdG9yLnNldE92ZXJsYXko
ZmFsc2UpOyBtb25pdG9yLnNldFJlZnJlc2hTZWNvbmRzKDIpOyBtb25pdG9yLnNldE9wYWNpdHko
ODUpOworICAgIH0KKyAgICB2b2lkIHNjYW5Qcm9ncmVzc0JlZm9yZUNvbXBsZXRpb24oKSB7Cisg
ICAgICAgIFFUZW1wb3JhcnlEaXIgZGlyOyBRRmlsZSBzY3JpcHQoZGlyLmZpbGVQYXRoKCJzY2Fu
LnB5IikpOyBRVkVSSUZZKHNjcmlwdC5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7CisgICAg
ICAgIHNjcmlwdC53cml0ZShSIlBZKGltcG9ydCBqc29uLHN5cyx0aW1lCitmb3IgbGluZSBpbiBz
eXMuc3RkaW46CisgICAgcmVxdWVzdD1qc29uLmxvYWRzKGxpbmUpCisgICAgaWYgcmVxdWVzdFsn
YWN0aW9uJ109PSdidC1zY2FuJzoKKyAgICAgICAgcHJpbnQoanNvbi5kdW1wcyh7J2l0ZW1zJzpb
eydpZCc6J0FBOkJCOkNDOkREOkVFOkZGJywnbmFtZSc6J0NvbnRyb2xsZXInfV0sJ3N0YXR1cyc6
J1NjYW5uaW5nJ30pLGZsdXNoPVRydWUpCisgICAgICAgIHRpbWUuc2xlZXAoLjUpCisgICAgcHJp
bnQoanNvbi5kdW1wcyh7J2l0ZW1zJzpbeydpZCc6J0FBOkJCOkNDOkREOkVFOkZGJywnbmFtZSc6
J0NvbnRyb2xsZXInfV0sJ3N0YXR1cyc6J1JlYWR5JywnZG9uZSc6VHJ1ZX0pLGZsdXNoPVRydWUp
CispUFkiKTsgc2NyaXB0LmNsb3NlKCk7IHFwdXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhU
VVJFIixzY3JpcHQuZmlsZU5hbWUoKS50b1V0ZjgoKSk7CisgICAgICAgIFN5c3RlbUNvbnRyb2xz
IGM7IGMub3BlbigiYnQiKTsgUVRSWV9WRVJJRlkoIWMuYnVzeSgpICYmICFjLml0ZW1zKCkuaXNF
bXB0eSgpKTsKKyAgICAgICAgYy5yZXF1ZXN0KCJidC1zY2FuIik7IFFUUllfQ09NUEFSRShjLnN0
YXR1cygpLFFTdHJpbmcoIlNjYW5uaW5nIikpOyBRVkVSSUZZKGMuYnVzeSgpKTsgUUNPTVBBUkUo
Yy5pdGVtcygpLnNpemUoKSwxKTsKKyAgICAgICAgUVRSWV9WRVJJRlkoIWMuYnVzeSgpKTsgYy5j
bG9zZSgpOyBxdW5zZXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIik7CisgICAgfQor
ICAgIHZvaWQgaWNvblJlc291cmNlcygpIHsKKyAgICAgICAgZm9yIChjb25zdCBRU3RyaW5nJiBu
YW1lIDogeyJlY2xpcHNlLWljb24iLCAiZWNsaXBzZS1jb250cm9scyIsICJlY2xpcHNlLXBvd2Vy
IiwgImNyaW1zb24tbmV0d29yayIsICJjcmltc29uLWJsdWV0b290aCIsICJjcmltc29uLWJhdHRl
cnkiLCAiY3JpbXNvbi1ob3N0IiwgInNldHRpbmdzIn0pIHsKKyAgICAgICAgICAgIGNvbnN0IFFT
dHJpbmcgcGF0aCA9ICI6L3Jlcy8iICsgbmFtZSArICIuc3ZnIjsKKyAgICAgICAgICAgIFFWRVJJ
RlkyKFFGaWxlOjpleGlzdHMocGF0aCksIHFQcmludGFibGUocGF0aCkpOworICAgICAgICAgICAg
UUltYWdlUmVhZGVyIHJlYWRlcihwYXRoKTsKKyAgICAgICAgICAgIFFWRVJJRlkyKCFyZWFkZXIu
cmVhZCgpLmlzTnVsbCgpLCBxUHJpbnRhYmxlKHBhdGggKyAiOiAiICsgcmVhZGVyLmVycm9yU3Ry
aW5nKCkpKTsKKyAgICAgICAgfQorICAgIH0KKyAgICB2b2lkIHFtbFBhbGV0dGVBbmRQYW5lbHMo
KSB7CisgICAgICAgIFFTdHJpbmcgc291cmNlID0gcUVudmlyb25tZW50VmFyaWFibGUoIlZJQkVN
SVNfVEVTVF9TT1VSQ0UiKTsgUVZFUklGWSghc291cmNlLmlzRW1wdHkoKSk7CisgICAgICAgIFFR
dWlja1N0eWxlOjpzZXRTdHlsZSgiTWF0ZXJpYWwiKTsKKyAgICAgICAgcW1sUmVnaXN0ZXJTaW5n
bGV0b25UeXBlKFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNlICsgIi9hcHAvbW9vbmxpZ2h0b3Mv
dGVzdHMvUHJlZmVyZW5jZXMucW1sIiksICJTdHJlYW1pbmdQcmVmZXJlbmNlcyIsIDEsIDAsICJT
dHJlYW1pbmdQcmVmZXJlbmNlcyIpOworICAgICAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGUo
UVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UgKyAiL2FwcC9ndWkvVmJUb2tlbnMucW1sIiksICJW
aWJlbWlzLlJlZGVzaWduIiwgMSwgMCwgIlZiVG9rZW5zIik7CisgICAgICAgIFFUZW1wb3JhcnlE
aXIgY29udHJvbHNGaXh0dXJlOyBRVkVSSUZZKGNvbnRyb2xzRml4dHVyZS5pc1ZhbGlkKCkpOwor
ICAgICAgICBRRmlsZSBoZWxwZXIoY29udHJvbHNGaXh0dXJlLmZpbGVQYXRoKCJoZWxwZXIucHki
KSk7IFFWRVJJRlkoaGVscGVyLm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsKKyAgICAgICAg
aGVscGVyLndyaXRlKFIiUFkoaW1wb3J0IGpzb24sc3lzCitmb3IgbGluZSBpbiBzeXMuc3RkaW46
CisgICAgdmFsdWU9anNvbi5sb2FkcyhsaW5lKQorICAgIHByaW50KGpzb24uZHVtcHMoeydzdGF0
ZSc6eyd2b2x1bWUnOjUwLCdtdXRlZCc6RmFsc2UsJ3dpZmlfZW5hYmxlZCc6VHJ1ZSwnYmx1ZXRv
b3RoX2VuYWJsZWQnOlRydWUsJ2Rpc3BsYXlzJzpbeydpZCc6J2VEUC0xfDEwMjR4NjQwfDYwJywn
bmFtZSc6J2VEUC0xIMK3IDEwMjTDlzY0MCDCtyA2MCBIeicsJ2N1cnJlbnQnOlRydWV9XSwncG9p
bnRlcnMnOlt7J2lkJzonMTInLCduYW1lJzonVG91Y2hwYWQnLCdzcGVlZCc6MCwnbmF0dXJhbCc6
VHJ1ZSwndGFwJzpUcnVlfV0sJ3NpbmtzJzpbeydpZCc6JzQyJywnbmFtZSc6J1NwZWFrZXJzJywn
ZGVmYXVsdCc6VHJ1ZX0seydpZCc6JzU3JywnbmFtZSc6J0FpclBvZHMnLCdkZWZhdWx0JzpGYWxz
ZX1dLCdicmlnaHRuZXNzJzp7J3NjcmVlbic6eydkZXZpY2UnOidpbnRlbF9iYWNrbGlnaHQnLCdw
ZXJjZW50Jzo2MH0sJ2tleWJvYXJkJzp7J2RldmljZSc6J3NwaTo6a2JkX2JhY2tsaWdodCcsJ3Bl
cmNlbnQnOjMwfX0sJ29zJzp7J05BTUUnOidFY2xpcHNlT1MnLCdWRVJTSU9OJzonMC4zLWRldics
J1RBUkdFVCc6J0ZpeHR1cmUgaGFyZHdhcmUnLCdGRURPUkEnOic0NCd9LCdrZXJuZWwnOidmaXh0
dXJlLWtlcm5lbCd9LCdpdGVtcyc6W3snaWQnOidmaXh0dXJlJywnbmFtZSc6J0ZpeHR1cmUgZGV2
aWNlJywnZGV0YWlsJzonQXZhaWxhYmxlJywnY29ubmVjdGVkJzpUcnVlfV0sJ3N0YXR1cyc6J1Jl
YWR5JywnZG9uZSc6VHJ1ZX0pLGZsdXNoPVRydWUpCispUFkiKTsgaGVscGVyLmNsb3NlKCk7Cisg
ICAgICAgIHFwdXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIixoZWxwZXIuZmlsZU5h
bWUoKS50b1V0ZjgoKSk7CisgICAgICAgIFFRbWxFbmdpbmUgZW5naW5lOworICAgICAgICBRUW1s
Q29tcG9uZW50IGNvbXBvbmVudCgmZW5naW5lLCBRVXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSAr
ICIvYXBwL21vb25saWdodG9zL3Rlc3RzL0hhcm5lc3MucW1sIikpOworICAgICAgICBRU2NvcGVk
UG9pbnRlcjxRT2JqZWN0PiByb290KGNvbXBvbmVudC5jcmVhdGUoKSk7IFFWRVJJRlkyKHJvb3Qs
IHFQcmludGFibGUoY29tcG9uZW50LmVycm9yU3RyaW5nKCkpKTsKKyAgICAgICAgYXV0byBwYW5l
bCA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oInRlc3RQYW5lbCIpOyBRVkVSSUZZKHBhbmVs
KTsKKyAgICAgICAgYXV0byBzdGF0ZSA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oInRlc3RT
dGF0ZSIpOyBRVkVSSUZZKHN0YXRlKTsKKyAgICAgICAgZm9yIChpbnQgaSA9IDA7IGkgPCAxNjsg
KytpKSB7CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9v
dC5kYXRhKCksICJjaG9vc2VBY2NlbnQiLCBRX0FSRyhRVmFyaWFudCwgaSkpKTsKKyAgICAgICAg
ICAgIFFDT01QQVJFKHN0YXRlLT5wcm9wZXJ0eSgiYWNjZW50IikudmFsdWU8UUNvbG9yPigpLnJn
YigpLEVjbGlwc2VPdmVybGF5U3R5bGU6OmFjY2VudChpKS5yZ2IoKSk7CisgICAgICAgICAgICBR
VkVSSUZZKHN0YXRlLT5wcm9wZXJ0eSgicHJlc3NlZCIpLnZhbHVlPFFDb2xvcj4oKS5pc1ZhbGlk
KCkpOworICAgICAgICB9CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhv
ZChyb290LmRhdGEoKSwgImNob29zZUFjY2VudCIsIFFfQVJHKFFWYXJpYW50LCA0KSkpOworICAg
ICAgICBmb3IgKFFTdHJpbmcga2luZCA6IHsibmV0d29yayIsICJiYXR0ZXJ5IiwgImhvc3QifSkg
eworICAgICAgICAgICAgUVZFUklGWShwYW5lbC0+c2V0UHJvcGVydHkoImtpbmQiLCBraW5kKSk7
CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QocGFuZWwsICJv
cGVuIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgICAgIFFWRVJJRlkocGFuZWwtPnBy
b3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAgICAgICAgUVN0cmluZyBvdXQgPSBx
RW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9TQ1JFRU5TSE9UUyIpOworICAgICAgICAgICAg
aWYgKCFvdXQuaXNFbXB0eSgpKSB7CisgICAgICAgICAgICAgICAgUURpcigpLm1rcGF0aChvdXQp
OworICAgICAgICAgICAgICAgIGF1dG8gd2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRv
dyo+KHJvb3QuZGF0YSgpKTsgUVZFUklGWSh3aW5kb3cpOworICAgICAgICAgICAgICAgIFFWRVJJ
Rlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQgKyAiLyIgKyBraW5kICsgIi5wbmciKSk7
CisgICAgICAgICAgICB9CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VN
ZXRob2QocGFuZWwsICJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgIH0KKyAg
ICAgICAgYXV0byBjb25uZWN0aW9ucyA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oImNvbm5l
Y3Rpb25zUGFuZWwiKTsgUVZFUklGWShjb25uZWN0aW9ucyk7CisgICAgICAgIGZvciAoUVN0cmlu
ZyBraW5kIDogeyJ3aWZpIiwgImJ0In0pIHsKKyAgICAgICAgICAgIHJvb3QtPnNldFByb3BlcnR5
KCJ3aWR0aCIsIDEwMjQpOyByb290LT5zZXRQcm9wZXJ0eSgiaGVpZ2h0IiwgNjQwKTsKKyAgICAg
ICAgICAgIFFWRVJJRlkoY29ubmVjdGlvbnMtPnNldFByb3BlcnR5KCJraW5kIiwga2luZCkpOwor
ICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNvbm5lY3Rpb25z
LCAib3BlbiIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICBRVkVSSUZZKGNvbm5l
Y3Rpb25zLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsKKyAgICAgICAgICAgIFFWRVJJ
RlkoY29ubmVjdGlvbnMtPnByb3BlcnR5KCJ3aWR0aCIpLnRvSW50KCkgPD0gOTkyKTsKKyAgICAg
ICAgICAgIFFTdHJpbmcgb3V0ID0gcUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fU0NSRUVO
U0hPVFMiKTsKKyAgICAgICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgeworICAgICAgICAgICAg
ICAgIGF1dG8gd2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgp
KTsgUVZFUklGWSh3aW5kb3cpOworICAgICAgICAgICAgICAgIFFWRVJJRlkod2luZG93LT5ncmFi
V2luZG93KCkuc2F2ZShvdXQgKyAiLyIgKyBraW5kICsgIi1zZWxlY3Rvci5wbmciKSk7CisgICAg
ICAgICAgICB9CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qo
Y29ubmVjdGlvbnMsICJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgIH0KKyAg
ICAgICAgUVFtbENvbXBvbmVudCBhY3Rpb25Db21wb25lbnQoJmVuZ2luZSxRVXJsOjpmcm9tTG9j
YWxGaWxlKHNvdXJjZSsiL2FwcC9ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5xbWwiKSk7CisgICAg
ICAgIFFTY29wZWRQb2ludGVyPFFPYmplY3Q+IGFjdGlvbihhY3Rpb25Db21wb25lbnQuY3JlYXRl
KCkpOyBRVkVSSUZZMihhY3Rpb24scVByaW50YWJsZShhY3Rpb25Db21wb25lbnQuZXJyb3JTdHJp
bmcoKSkpOworICAgICAgICBhdXRvIGFjdGlvbkl0ZW0gPSBxb2JqZWN0X2Nhc3Q8UVF1aWNrSXRl
bSo+KGFjdGlvbi5kYXRhKCkpOyBRVkVSSUZZKGFjdGlvbkl0ZW0pOworICAgICAgICBhdXRvIGFj
dGlvbldpbmRvdyA9IHFvYmplY3RfY2FzdDxRUXVpY2tXaW5kb3cqPihyb290LmRhdGEoKSk7IFFW
RVJJRlkoYWN0aW9uV2luZG93KTsKKyAgICAgICAgYWN0aW9uSXRlbS0+c2V0UGFyZW50SXRlbShh
Y3Rpb25XaW5kb3ctPmNvbnRlbnRJdGVtKCkpOyBhY3Rpb25JdGVtLT5mb3JjZUFjdGl2ZUZvY3Vz
KCk7CisgICAgICAgIFFTaWduYWxTcHkgYWN0aXZhdGVkKGFjdGlvbi5kYXRhKCksU0lHTkFMKGNs
aWNrZWQoKSkpOworICAgICAgICBRVGVzdDo6a2V5Q2xpY2soYWN0aW9uV2luZG93LFF0OjpLZXlf
UmV0dXJuKTsgUUNPTVBBUkUoYWN0aXZhdGVkLmNvdW50KCksMSk7CisgICAgICAgIGFjdGlvbkl0
ZW0tPnNldFZpc2libGUoZmFsc2UpOworICAgICAgICBhdXRvIGNlbnRlciA9IHJvb3QtPmZpbmRD
aGlsZDxRT2JqZWN0Kj4oImNvbnRyb2xDZW50ZXIiKTsgUVZFUklGWShjZW50ZXIpOworICAgICAg
ICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY2VudGVyLCJvcGVuIikpOyBRVGVz
dDo6cVdhaXQoNTAwKTsKKyAgICAgICAgUVZFUklGWShjZW50ZXItPnByb3BlcnR5KCJ2aXNpYmxl
IikudG9Cb29sKCkpOworICAgICAgICBRU3RyaW5nIG91dCA9IHFFbnZpcm9ubWVudFZhcmlhYmxl
KCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgIGF1dG8gd2luZG93ID0gcW9iamVjdF9j
YXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgpKTsgUVZFUklGWSh3aW5kb3cpOworICAgICAg
ICBpZiAoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShv
dXQrIi9lY2xpcHNlLWNvbnRyb2wtY2VudGVyLnBuZyIpKTsKKyAgICAgICAgUVZFUklGWShRTWV0
YU9iamVjdDo6aW52b2tlTWV0aG9kKGNlbnRlciwiY2xvc2UiKSk7IFFUZXN0OjpxV2FpdCgzMDAp
OworICAgICAgICBhdXRvIGFib3V0ID0gcm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigiYWJvdXRF
Y2xpcHNlIik7IFFWRVJJRlkoYWJvdXQpOworICAgICAgICBhYm91dC0+c2V0UHJvcGVydHkoImlu
Zm8iLCBRVmFyaWFudE1hcHt7Im9zIixRVmFyaWFudE1hcHt7Ik5BTUUiLCJFY2xpcHNlT1MifSx7
IlZFUlNJT04iLCIwLjMtZGV2In0seyJUQVJHRVQiLCJGaXh0dXJlIGhhcmR3YXJlIn0seyJGRURP
UkEiLCI0NCJ9fX0seyJrZXJuZWwiLCJmaXh0dXJlLWtlcm5lbCJ9fSk7CisgICAgICAgIFFWRVJJ
RlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChhYm91dCwib3BlbiIpKTsgUVRlc3Q6OnFXYWl0
KDMwMCk7CisgICAgICAgIFFWRVJJRlkoYWJvdXQtPnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29s
KCkpOworICAgICAgICBpZiAoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlkod2luZG93LT5ncmFiV2lu
ZG93KCkuc2F2ZShvdXQrIi9lY2xpcHNlLWFib3V0LnBuZyIpKTsKKyAgICAgICAgUVZFUklGWShR
TWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGFib3V0LCJjbG9zZSIpKTsKKyAgICAgICAgYXV0byBz
eXN0ZW09cm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigic3lzdGVtU2V0dGluZ3MiKTsgUVZFUklG
WShzeXN0ZW0pOworICAgICAgICBmb3IoaW50IHNjYWxlOnsxMDAsMTEwLDEyNX0pIHsKKyAgICAg
ICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiY2hv
b3NlU2NhbGUiLFFfQVJHKFFWYXJpYW50LHNjYWxlKSkpOworICAgICAgICAgICAgcm9vdC0+c2V0
UHJvcGVydHkoIndpZHRoIiwxMDI0KTsgcm9vdC0+c2V0UHJvcGVydHkoImhlaWdodCIsNjQwKTsK
KyAgICAgICAgICAgIHN5c3RlbS0+c2V0UHJvcGVydHkoImFjdGl2ZSIsdHJ1ZSk7IFFUZXN0Ojpx
V2FpdCg0MDApOworICAgICAgICAgICAgUVZFUklGWShzeXN0ZW0tPnByb3BlcnR5KCJ3aWR0aCIp
LnRvSW50KCk8PTEwMjQpOworICAgICAgICAgICAgaWYoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlko
d2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQrIi9zeXN0ZW0tY29udHJvbHMtIitRU3RyaW5n
OjpudW1iZXIoc2NhbGUpKyIucG5nIikpOworICAgICAgICAgICAgZm9yKGludCBhY2NlbnQ9MDth
Y2NlbnQ8MTY7YWNjZW50KyspIHsKKyAgICAgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0
OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29zZUFjY2VudCIsUV9BUkcoUVZhcmlhbnQs
YWNjZW50KSkpOyBRVGVzdDo6cVdhaXQoMTApOworICAgICAgICAgICAgICAgIFFWRVJJRlkoc3Rh
dGUtPnByb3BlcnR5KCJhY2NlbnQiKS52YWx1ZTxRQ29sb3I+KCkuaXNWYWxpZCgpKTsKKyAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgIGF1dG8gc2Nyb2xsPXJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0
Kj4oInN5c3RlbVNjcm9sbCIpOyBRVkVSSUZZKHNjcm9sbCk7CisgICAgICAgICAgICBhdXRvIGZs
aWNrPXNjcm9sbC0+cHJvcGVydHkoImNvbnRlbnRJdGVtIikudmFsdWU8UVF1aWNrSXRlbSo+KCk7
IFFWRVJJRlkoZmxpY2spOworICAgICAgICAgICAgYXV0byBtb25pdG9yPXJvb3QtPmZpbmRDaGls
ZDxRT2JqZWN0Kj4oImhhcmR3YXJlTW9uaXRvciIpOyBRVkVSSUZZKG1vbml0b3IpOworICAgICAg
ICAgICAgZmxpY2stPnNldFByb3BlcnR5KCJjb250ZW50WSIsbW9uaXRvci0+cHJvcGVydHkoInki
KSk7IFFUZXN0OjpxV2FpdCgyMDApOworICAgICAgICAgICAgaWYoIW91dC5pc0VtcHR5KCkpIFFW
RVJJRlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQrIi9oYXJkd2FyZS1tb25pdG9yLSIr
UVN0cmluZzo6bnVtYmVyKHNjYWxlKSsiLnBuZyIpKTsKKyAgICAgICAgICAgIGZsaWNrLT5zZXRQ
cm9wZXJ0eSgiY29udGVudFkiLDApOworICAgICAgICAgICAgc3lzdGVtLT5zZXRQcm9wZXJ0eSgi
YWN0aXZlIixmYWxzZSk7IFFUZXN0OjpxV2FpdCgxMDApOworICAgICAgICB9CisgICAgICAgIFFW
RVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiY2hvb3NlU2NhbGUi
LFFfQVJHKFFWYXJpYW50LDEwMCkpKTsKKyAgICAgICAgcXVuc2V0ZW52KCJNT09OTElHSFRfQ09O
VFJPTFNfRklYVFVSRSIpOworICAgIH0KK307CitRVEVTVF9NQUlOKENyaW1zb25UZXN0KQorI2lu
Y2x1ZGUgInRlc3QtY3JpbXNvbi5tb2MiCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVz
dHMvdGVzdC1jcmltc29uLnBybyBiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24u
cHJvCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjg4MWY4NTkKLS0tIC9kZXYv
bnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvdGVzdC1jcmltc29uLnBybwpAQCAtMCww
ICsxLDIxIEBACitRVCArPSBjb3JlIGd1aSBxdWljayBuZXR3b3JrIHF1aWNrY29udHJvbHMyIHRl
c3RsaWIgc3ZnCitDT05GSUcgKz0gYysrMTcgdGVzdGNhc2UKK1RBUkdFVCA9IHRlc3QtY3JpbXNv
bgorU09VUkNFUyArPSB0ZXN0LWNyaW1zb24uY3BwIC4uL2NyaW1zb25zdGF0dXMuY3BwCitIRUFE
RVJTICs9IC4uL2NyaW1zb25zdGF0dXMuaAorCitTT1VSQ0VTICs9IC4uL21hbmFnZWR1cGRhdGVz
LmNwcAorSEVBREVSUyArPSAuLi8uLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgKKworREVG
SU5FUyArPSBNT09OTElHSFRfQ09OVFJPTFNfVEVTVAorU09VUkNFUyArPSAuLi9zeXN0ZW1jb250
cm9scy5jcHAKK0hFQURFUlMgKz0gLi4vc3lzdGVtY29udHJvbHMuaAorCitTT1VSQ0VTICs9IC4u
L2VjbGlwc2Vwcm9maWxlcy5jcHAKK0hFQURFUlMgKz0gLi4vZWNsaXBzZXByb2ZpbGVzLmgKKwor
IyBNYXRjaCB0aGUgcHJvZHVjdGlvbiByZXNvdXJjZSBidW5kbGUgc28gcmVuZGVyZWQgaWNvbnMg
YXJlIGFjdHVhbGx5IHRlc3RlZC4KK1JFU09VUkNFUyArPSAuLi8uLi9yZXNvdXJjZXMucXJjCisK
K1NPVVJDRVMgKz0gLi4vbG9jYWxoYXJkd2FyZS5jcHAKK0hFQURFUlMgKz0gLi4vbG9jYWxoYXJk
d2FyZS5oCmRpZmYgLS1naXQgYS9hcHAvcW1sLnFyYyBiL2FwcC9xbWwucXJjCmluZGV4IGEzYzEx
ZGQuLjcxNGM2NTEgMTAwNjQ0Ci0tLSBhL2FwcC9xbWwucXJjCisrKyBiL2FwcC9xbWwucXJjCkBA
IC0xNCw2ICsxNCwxMSBAQAogICAgICAgICA8ZmlsZT5ndWkvVmJIb3N0Q2FyZC5xbWw8L2ZpbGU+
CiAgICAgICAgIDxmaWxlPmd1aS9WYldlbGNvbWVTaGVldC5xbWw8L2ZpbGU+CiAgICAgICAgIDxm
aWxlPmd1aS9tYWluLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0NyaW1zb25TdGF0dXNE
aWFsb2cucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvU3lzdGVtQ29ubmVjdGlvbnNEaWFs
b2cucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUNvbnRyb2xDZW50ZXIucW1s
PC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5xbWw8L2ZpbGU+
CisgICAgICAgIDxmaWxlPmd1aS9FY2xpcHNlQWJvdXREaWFsb2cucW1sPC9maWxlPgogICAgICAg
ICA8ZmlsZT5ndWkvUGNWaWV3LnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL0FwcFZpZXcu
cW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvU2V0dGluZ3NWaWV3LnFtbDwvZmlsZT4KZGlm
ZiAtLWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1iYXR0ZXJ5LnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1i
YXR0ZXJ5LnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi4zNzUzNTY2Ci0t
LSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9jcmltc29uLWJhdHRlcnkuc3ZnCkBAIC0wLDAgKzEg
QEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhl
aWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCI+PGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRUNF
RUYxIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGlu
ZWpvaW49InJvdW5kIj48cmVjdCB4PSIyIiB5PSI2IiB3aWR0aD0iMTgiIGhlaWdodD0iMTIiIHJ4
PSIyIi8+PHBhdGggZD0iTTIyIDEwdjRNNiAxMHY0TTEwIDEwdjRNMTQgMTB2NCIvPjwvZz48L3N2
Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnIGIvYXBwL3Jlcy9j
cmltc29uLWJsdWV0b290aC5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4u
Y2VmOWFiOAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3Zn
CkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3
aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZD0iTTcgN2wx
MCAxMC01IDRWM2w1IDRMNyAxNyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdp
ZHRoPSIxLjgiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIv
Pjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9jcmltc29uLWhvc3Quc3ZnIGIvYXBwL3Jlcy9j
cmltc29uLWhvc3Quc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmQxZDU5
YjAKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2NyaW1zb24taG9zdC5zdmcKQEAgLTAsMCAr
MSBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIg
aGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48ZyBmaWxsPSJub25lIiBzdHJva2U9IiNF
Q0VFRjEiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1s
aW5lam9pbj0icm91bmQiPjxyZWN0IHg9IjMiIHk9IjMiIHdpZHRoPSIxOCIgaGVpZ2h0PSIxNCIg
cng9IjIiLz48cGF0aCBkPSJNOCAyMWg4TTEyIDE3djRNNiAxMGgzbDItNCAzIDggMi00aDIiLz48
L2c+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1zb24tbmV0d29yay5zdmcgYi9hcHAv
cmVzL2NyaW1zb24tbmV0d29yay5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAw
MC4uYjJhMTAzYQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2
ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIg
d2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxnIGZpbGw9Im5vbmUi
IHN0cm9rZT0iI0VDRUVGMSIgc3Ryb2tlLXdpZHRoPSIxLjgiIHN0cm9rZS1saW5lY2FwPSJyb3Vu
ZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggZD0iTTMgOGExNCAxNCAwIDAgMSAxOCAw
TTYgMTJhOSA5IDAgMCAxIDEyIDBNOSAxNmE0IDQgMCAwIDEgNiAwIi8+PGNpcmNsZSBjeD0iMTIi
IGN5PSIyMCIgcj0iMSIvPjwvZz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1j
b250cm9scy5zdmcgYi9hcHAvcmVzL2VjbGlwc2UtY29udHJvbHMuc3ZnCm5ldyBmaWxlIG1vZGUg
MTAwNjQ0CmluZGV4IDAwMDAwMDAuLjY1M2RiZDgKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVz
L2VjbGlwc2UtY29udHJvbHMuc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93
d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAy
NCAyNCI+PHBhdGggZD0iTTQgNmgxNk00IDEyaDE2TTQgMThoMTZNOCAzdjZNMTYgOXY2TTEwIDE1
djYiIGZpbGw9Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2Ut
bGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlmZiAtLWdp
dCBhL2FwcC9yZXMvZWNsaXBzZS1pY29uLnN2ZyBiL2FwcC9yZXMvZWNsaXBzZS1pY29uLnN2Zwpu
ZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi43MTE1YzMzCi0tLSAvZGV2L251bGwK
KysrIGIvYXBwL3Jlcy9lY2xpcHNlLWljb24uc3ZnCkBAIC0wLDAgKzEsNyBAQAorPHN2ZyB4bWxu
cz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI1MTIiIGhlaWdodD0iNTEyIiB2
aWV3Qm94PSIwIDAgNTEyIDUxMiI+Cis8ZGVmcz48bGluZWFyR3JhZGllbnQgaWQ9InJpbSIgeDE9
IjAiIHkxPSIwIiB4Mj0iMSIgeTI9IjEiPjxzdG9wIHN0b3AtY29sb3I9IiNmZjc1OGIiLz48c3Rv
cCBvZmZzZXQ9Ii40OCIgc3RvcC1jb2xvcj0iI2RjMzY1OCIvPjxzdG9wIG9mZnNldD0iMSIgc3Rv
cC1jb2xvcj0iIzYzMTUyYiIvPjwvbGluZWFyR3JhZGllbnQ+PGxpbmVhckdyYWRpZW50IGlkPSJn
bGFzcyIgeDE9IjAiIHkxPSIwIiB4Mj0iMCIgeTI9IjEiPjxzdG9wIHN0b3AtY29sb3I9IiMyMDE1
MWMiLz48c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiMwODA4MGIiLz48L2xpbmVhckdyYWRp
ZW50PjwvZGVmcz4KKzxyZWN0IHg9IjEyIiB5PSIxMiIgd2lkdGg9IjQ4OCIgaGVpZ2h0PSI0ODgi
IHJ4PSIxMTAiIGZpbGw9InVybCgjZ2xhc3MpIiBzdHJva2U9IiNmZmZmZmYiIHN0cm9rZS1vcGFj
aXR5PSIuMTMiIHN0cm9rZS13aWR0aD0iMiIvPgorPGNpcmNsZSBjeD0iMjU2IiBjeT0iMjU2IiBy
PSIxNDQiIGZpbGw9InVybCgjcmltKSIvPgorPGNpcmNsZSBjeD0iMjY4IiBjeT0iMjQ5IiByPSIx
MzYiIGZpbGw9IiMwODA4MGIiLz4KKzxwYXRoIGQ9Ik0xNTEgMTYyYTE0MyAxNDMgMCAwIDEgMTM1
LTQ4IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmU4ZWUiIHN0cm9rZS1vcGFjaXR5PSIuNTUiIHN0
cm9rZS13aWR0aD0iMyIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIi8+Cis8L3N2Zz4KZGlmZiAtLWdp
dCBhL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTEyOC5wbmcgYi9hcHAvcmVzL2VjbGlwc2UtbWFyay0x
MjgucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAuLjE1MTIxYzA0YmU3YTRjYjlmYjY1ZmYwOTlkNzQ2N2I0NDRjNmU5
MGQKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDcwODcKemNtVjtnOCZLcWxQKTxoOzNLfExrMDAw
ZTFOSkxUcTAwNGpoMDA0anAxXkBzNiEjLWlsMDAwfHlOa2w8WmMlMUU+CnpkNi08KWI+TSZKLWRD
QHh5THdkJTJfJl9JZ3BrO2dGaClSWmdiajhFajJGTy0/SEM3ZG4yaGxeOFNuOVk9OTVWIwp6Nk1y
VT9jcnI2eSRtaUkyYTZGRlVJNU9pdmoyRk9Rdnp2VnBsRitgT21VXmtgK1RPZU8lcGIzKylvTHxE
ZlYjUmAKenMkWU12S2RIT0EtbTc9Y0pAPWUqJnBsNzVGOU0rS2BgKUM2QnNWQUZoYDJlallTaypV
YV49YloybW13SDdjYEE5CnpLKEtQPCUzIyYxUlIrZkQjXkwzI3p3eFM3dElVbHotZWBiJD85WXVn
eFkoSW5aQHNsYCpTY0x7eHc2THw/c0hGUAp6KHFXSUF5P0Ehej5aYEJMK3JXRDd7UD5weXQ1JlZA
SHtOKlQwbCM9WDk1d34kPis3P3RTRmlSfCY2bGRtSDZPVTwKemxwV2kpekh4WUhfempoRWQxKU5H
PEQ3SGRzPWdKfjtCY00kaChJSjNGJEhWd0tvSG0rVkxKVk1NYHk8KSRJWUdoCnomQERmXzxyeHZG
TyQqWjMqSm9DKlVoTkxjWDx6UmZSMFp6PFkhTEFORTNQPGUpQX12JTlVZENHdnxLOG09QUU8Nwp6
ZEF4ZDF0IWxeWEo/anlRUjBTZX01cmVlYFczNVlQKG9lTkB3KlRBbHo0TCRrUHlnPkhrSG0zZVQq
dXp+Kkt4fCUKel58dUNhc1pAJGZSPSlqUlRlb2ZmUjZkdSNJRjJINSZZPW5qdUJ5RXZgXzRDTWJK
e2VnSGEtK2tSVFVIfjBAaGxCCnpSNyVfMCtJfjVBPyVlLSUkMzF0aGlKfU89MDs4N3EpJCpESVFQ
VnN6IXNWQTt7KzVrdipNQjg5SmJYYz1RbypZdAp6TXEpdX4mZFdJR3draTlBYkhGYEhsbVllWEg4
M0tDVk10cD9gKT9NWGMqMGx5YERnJDdFQT5ocmVSZWdrLVd0M1gKelg7e0doOzJZb1F7QCp2PkA+
bCkreVJSI2slNlJxTzdeQnRTSDw+KH5fZzsqTU5vTys1b09SNjIqTUl6KUtsfFYoCnpLUkd9V1pO
O3pqMjRpYCgzSj9KQ1Jxd3AmNTF4UGFzcVlMQTwoOUBTUiU0OChEZm9LaHkhUjU9ejt0eEJLWXor
Owp6cispbTB8R041S1Vab1BlOFU/VC07QCpEMiNVSXxoZSM1cyQzZEotK0VGdypCZWhOfDU3JHM9
UXdwMzE3d0NLOXEKekBBPHt8Uk1pNTlHI3duTzB0OHx0ekclZS1wV0QyNyVUMHgxNW8/VTJJcURr
KT1lQFRyRWlMcitfSX19NDU4aVc9CnpgYUBIS1NJb3w+V012PkNAcjVmY199cz0jbntPJTxpX1JG
TTNSYkNsRDl2TjQ0PWN1S3A7JmFBSGdFcGdnKTEpagp6b1FTeFV0YjlmNWR7NzFHPis3PzNiOWVs
UUQ9KXJnPipnJnRsfWFVTmpHNUhiV1J1czc3LUxNU1JFb0U1LWc0OTEKekZTeilfY1hNfiMqVmxK
WUVCJiR4UHomYHdjPT1XNXpQTnRGJkJiRVRILStFdWgldj8laSQlWTIhOzliaztOQDRICnp5TCRD
JWNRN1RHUD8oQn1Bb0FWc2V6KVVxe19FRXM5dm0xdkw1ejVzM3AmI1V1aWwlaz8oWCVVYFNLVWV7
PlZvQAp6R09WWnlxdl87UENSQmh2dXM9NCZvcFopbkh9QmxHXklHUiEpN3poQnNBX0RENFVWMEE/
Qjc1NSNHe3xeLWNSVGgKejl4JFQmel4oQE8tcGslfExJM1ZPKkc0WE9oJV9DKFg/N3JEQk53fj0t
RnZSPmQqfGhFMjMrMytRUUpmb3peRSRBCnptWWpDKS1hUH43QXZEOWk+NURfTEdrU1Z7YGBGcWkt
WWc9SnRRKEI3cDlTY24malM5UDdoVXA+ZH5XMUNNVnJFKAp6LWRJSV9LOUBXSFReQzxeRGQ1TERn
eVN1TXZEVyVpUGRORzQxTzBuMVk+eGdUMCo3THtYWkdDbl4hakpzPllPdS0KenU+endPcGp2dzVg
YCoqSHlwU0p4diNNOGAhYW93UVVPazA7eyh8PmlAeEVuJXVnVihPLXZSX2NlRDFRZHpxKTxmCnpq
eFJkelZAWkQyV2Nte3VWfWR6emp7RUJVazNhaysjdy18KF4jUG8hMkUjK1NjUjEmZVgzVCNpVlZy
WGU9a284Kwp6cSFlIzc5NWdVJHtgSHk8ZHwrdzBUdDBkMUAwdUpENz1VdUFibj98I1VBK1gqK0I5
R1E/ei16UDFGJiheXzclPiMKekx0YVgzR09jalZ4blMkb08pRnJaJW5pV1pjaSM7X0Zgci1Wb251
U3w+SmYjQUFSLXVKNHRtc0hjTylTcT5ZWmFHCnpVc3crTldMfFVmeXM/JjJzbDMjQTlrKXFrYGVK
SD1SUGYjdCNTdX5MYU5nbC03MFQySzdiVTQkOWFFOE9aR2FpQwp6Mi1Fa0BpMVNMaFI2ZmFBaSs5
UCFnTWoyQ2NeQWpfPGJAfkFRUHR8TG40VEQ4NVdxUHtwO0QkQ018ZmpzWD5GeWEKenItI3x5R2RR
TkJsZ0AwR2JTZ3hROzhkeCZtfTByaU5VPXo2Qit0OyRGaGojUnFOb0IwcXZ8cSFaS0ozdlE1NE5f
CnphY283ejBzOXRzWm9UIV50b0x6T0V0NVB8U05VM35qYXVnJmBIPk1TLXFGXzQmZURaVElPbHtE
U3V1WVIzcD1fPAp6dDF5Xyl2MkFGOFpHKEgrbUN2IWFUd299d1AqSGB6bDVXaX51Y3dQc0ozODZC
Y1ExR1RgWXV2fCNmc1RDRWh6Z0cKelZwXmVpQDREOGtTPD8jU1VgKDk5WXUmQztvd2xNKDh9Vys+
UnQpOCtMY1VsZSt0JFYjbXp+TEYlZypNS2ctZSgoCnpBPWBLQzxsZzY+O2Fsc1U8SSFEUGQyeDd2
VHdMYkJwPE1nVzNLKG48a1BnIzA9YTVKK0FfVF5ndlg7O1dTZC0rKQp6Ukh1ejEybnk9N2I9fmpS
ckt1QF5xNm9zQyR7d3JlPT5Ib1QwaiNrVXFZNUwlQkoqYT89SVRHWmdiJHV8OT9NJDAKekN+ZXh4
S2lfZEQqRlc8cF93Qy1zaCUxOXdOVG1vPG1lI1FDZktOREhqSDtSbHpkR3VqRGxVI0YjfU9oeiUz
OUprCnpNSG1EYUcxRWQzSDJEaGxSUUZ7bnhfX29genZhWFIjVHJCR0okcnxUU2F8SFFlRDtkPkB1
NmtzYTltX34+OFlwcQp6QDxYP0IlWnBGNXdVfHB4ZFlCP0I7aSViRyludUY2QXV1KSlzQlBKKlFI
ZihKYWcyPSY9XiNaVzJyO0l5Nj01UlQKelBNY0ooMExFR2RNQEh5TXJ9QEdhUzg/cWh5b0VWTUNI
THNGZUM1JTVgUjBadmQ4dzRnMX1VPGNSelVIcHhJK345Cnp0R2I+c21TTG4pclc4ZUZRWHdzPTVE
e3I7TUh0SnBQeWoyMk5JaW8/TCVpZTZ2LXQ4PVM5NXgqNFc4TSt6ZFpkWQp6SCN+aG0ma1ZqcTVR
TWFhRXM0M0YxZmZyYWtTSyRxNmU9YWthWVF5dTY5JWJpcCMlLUQwRCY+JkRyS0A1ekpCJGAKemAw
KThGM0QkMD18SFlAZDtweU07dHJzMiM3IWBiNkMmNXBJaH5VJlFUcT0tQmc9RTdGR0IkKjRLKmxM
UlZ8ZjlBCnp2RnQ2M2E3TkU4eldGREEkezhJcShjZUFKVj1yeXo7fThGd018TiRjSFFmUipyR2cp
ZVJRR3Q3cTYpRWh3MXE3TQp6I3gjZiQ5NE9vVW9qfjFwT2ZgWUE/OVMoUypXeSQ3KX43eUErd0xM
cyFOPDh7X2c0UCstck1MZTY9PSh9NjhwdncKentDR3IhKmdKK3hCVkB4QyFYVExQRFBiYm5Ic2xt
d3QpKU1nPEt4VEQ7cF9rTEtUJiprOWxgY357JkQreUs2PndNCnpJRThFfi1MUyYxQXFYREdTQmhs
R2tad1N+cHk4SCR0dWdHJDRSaWZqPWthJmZmMTNRYCZ5d0EtaGctTD08M3NuWAp6MGZmLW54O2M1
VG1zO1JCUWdzajtaSVAqPTZkKjgkSjtlZWFKTSRjRmBqYnlGXndgc01eeWdVZihxPXlUbzcrZWsK
emkhfXp7VjU4X3o4TDU9MHhWV0t8cGtXanM1TWlLRjsrQEFXPG07Rko1eE02I2tsaSlGTC1+SEx4
bn5XQ09sI3JTCnokZGAtNiZOV1E3d0lNUXJSKXBhPTs8VDx+X354N2IxTGRfWlZxKFcwYWVVfldw
RTZ1MikwIz84OD8lMmY2ZVY5Tgp6KFZsNj1QflVxIWshK3tmMHdAQVItamZZZGVEaj0oPX1NKDMj
V0FnNm5tPkt1UE0jbGxpRU1hZTJwPHkxKDBOQ3AKelFyZlI/PlFvV3p6d31wczgoOytucVk4Z31f
Rkd1aWIxZU9aSlRvKGB7S01NRWBPKjVQWGlHUDRzUHxlQzVoYCYrCnorMWZmczJJRk5iUSk+YU4y
IW0wRE9Ybj0pPDBxV1hQXm15Uk5VPUZMJFBKSShMbj10Jjh6TztuX3pAOWBRUlI+cQp6clk0STY2
YClTTDdleWlWTkBvelY+V3VVOHM+SSZZVmd2cl9zciVXVUEwJXlxWTQ3d000RFVVcXNGRkJAYj14
KCUKektsPj5feXs8dDRCWmk/JG5VNXwkb3p1SCNGPGRGcmtxVVd1X2piTyZ7eik9bnJlVl4lbFpB
Ki1qJD5seXNNYyVMCnpUP2VMUTNKez49ViYtUSVfezhFZkNgTSVya2l6Z2tvX21Cc3JBIzBWNlFO
RWppYylnWGx2UUMoJHo4VCQkajFAYQp6RUlOZ0cqPih6WE1Bb0t3ViZFbSNZPFZGbSNYNz1BZStA
eTFUI1RDe040TT9AQVZBczIleFRUP3teT1RZaVh1PTUKenQ+cXMjSzB+ZnRBU0xEcWJeUnRyUmpJ
aENOZlZEI2ZYU2JNajBwTC0hWD9LWSYhVEo+ZypZTkRoV19GUktpVHBFCnpDUCpGOGpeOUx4QnZ3
R1IqN0xjM1VPLVVxRVB6KWZaMzM/N1U0cnUtUmkhbHVgMVFfQnlmRDAlbVpNTXMwR3hVdgp6Pz97
PHwkKkxVfkZXWHdYX3F0KDNEN2M3fEo3QDVROE03KEdpVE83T2NXbUU/SSlgYkg5Q19WUWw0empM
QUhTeyYKekFQOG1leE0wPml4PjZ5TGF8OXZgUiFaRXJkbUNjeTV1NW1WQn04UEBCRyF9b0RTIyU8
UEFIWilBMlMhe2VLSC0wCnpXa1lVfGJAQFI7Sk1+cEZRO0V+JHA0NCo7PnxZVHlpQjNTVz07TjUz
WTJ+eno5IWhaeHMpV1l5XmlWJHxRSGc5Uwp6alhSMUpLdkE2Y1NUamlqVkZLQ0slPnN4QkNGZU15
dCY3PnxSd35ZY0NXYFV3Jj5yeE96YXl6MGN3Z1UxYTlsbVcKenpPVHQzUXBlSmNaWmdKRiY8WCZ+
ZClEV05LcE1Neng/WHJaT3ArJXdrITxUKzZlXnNVP0UrMTxYYz9kISQ4ME8rCnpzfHMrbUJtNEMm
czBWZFowMGphZyV4aF4mKHc/ZGFoSnVTMnRkIXM9JF45UDtmZz84eEBUIzwhZlNLdEd2Rz1HWgp6
Q29laDJoPkl7SDRZNDAjcytzSVcrPDVBJDBCTExLdSZHZkMwRStYRHZpRno8RDM1OWc+S2dedHJ6
bGlOZFhvbW0KemtnPnRPRGoxKEEjP2MpNlBmWElLO3FicmY2eElWTWlwM0NBOVVVfjt4QHsxd3No
UiZ+Nys3c1lQYEFeS085VXlDCnp3bURHOHpKS0VFRDRxYkopZFdmNEJPTFghZkItVUM3STZhRSkt
TXNuejc/O1U1OyM+ZCM/bF55QjtDb0gpU0oyfQp6ZktwOGJ0RVVqaClwQl5uZHIhdCNXYD56K1Nh
QGAhUTFfeWN5NnBAUzVzSjwrOTkxd1gpbX1ZSDNTb1hySX4qaz8KelU8WEk1alZVSzVEPnxpNHBw
aiVMY3ozeW9tOHVVPTRGeWxrY0c3ZUo2WTZhTj5nb2VUPmUqN3ZWS2ZRPDFjO3BECnpsKHJkSVlt
ZHJHcHNAJV4tQHwkKWdYXkF1VHtralIlPmdOKk5oV1lmWWJVZVB0d2lkTllDRGtoRTNVNmQ+USly
MAp6Q0BCJXY8XzlSY0NeQGt6VyQmMEJ3czItZzUzekZ4SGZLSWNQezBfZSlBbz5rKU5OO3dTMCFh
RUZCRkVAUlZvbVcKekcqd2l1cXtNTEhqNSNuVmBMRjROSEhrUnRDO29iNzB1QDNyeWlfam9SQmtX
bllPQENjaWdDbistRShNOVd2Q3BiCnoofHx5QXs7eDBsRTVJYkhvZDZaQHhwIWJFUnQ0YEJLYEZZ
SkJgdXd0LSErP3hpO3VjI0t1SmN3c247Z2FHMVMlTAp6UD0kPUt7QVRZQzJCSCN5MndHaGJ2TGFr
SGAtSjNtXn1NSkNBJnt3Z0xTSjFLekB1Y1c8QHUzODl2UndBaT9NazEKejckNnN3ZEUxT1JvWUt9
cT1fcy1TTkBEdTBuVlJpemI+QUs/MnFvfE0kP2k+OTcrbzJSeXdZaHlLNmN5Xnltdj45CnpBMFIt
KzI2ZWdqaHV7UUd7XmBBWCtIQW5qYD9zPWdXU0VSMyZZJVRgcUI4RzI9NkZ0UHBHb20zdW1XQ3t0
Ty1icwp6d3Z3JkMzZS1JanEoSTZUYzIpfGtlcldAKENjeWNgM2RISlp2bmY4P2Qpa3pAUE1LXyFx
JX5lb0Rub2UrQmNDYSQKeiNQcTZVWk5Md0FaRDNPfE40alBPUjJZaU5Uc0M3S0AwQHUmZ304en0w
PEN9e05zQktDK28rKFU7cVgqbE9XamMqCnpaN2lFaGRIIUw/VEMmRkNZS3ViKFcjP0djZG5VOFBS
d357ZlE1IX1ERDY0MDdrZkE0KXEySEMwWGxSUEE9S3V3JAp6KkRUfnpYfTJNXz57YCNgeGprZWhp
M2tLSkk+Ji1ebWNOKlA3TG5GfSRMd1VIQjtDPUBaa0BeY1hrQGdaXmkoKjIKelB8cmxyeEk7Q1cx
QmNeP3xGLTRIKGVyRTdBc21SeFRyczFVUGFTKFFnKHcqJSg7YjZRQC1Zeys5bXtUQ1ZYdiFACnoh
cW9NP2tKb31KLUhxVz89P3FmKlZzSG9GK3FzU3xuQFhCT0RwKzdKdUpDN2JQVVcobTE/MSFELThq
bDM2bnc8Xwp6Kjw8SnFHQ1dvcXBqQ24/LXdyP0pjZUxnWmVyPy1SSmQpby15OXRQV3ZUQFdgUn0y
Njl7NVNCWGpebjFTNT9GKjAKekE4fnI3bnslX3JhN1RVenExM3htQFdmMVRIfHVNVTZlU1IkO0Ex
fHM9QEFDd0dOQms7KWdQIyskQk9XYzxJbXl6CnpfU3NiPm1fRX0lUDUzOGdJPVFsSUs1S0hARFhH
SmZlRUtRMXw0ZDx7JGd6ajNUN2pudmdNNTBeQk4mcDVWTyg8eAp6eSgyVzFaIUtFRStxJmtHa0lS
P18tJU1XWHpjYjxeJlRRJUNCaSQhKFRZZnVSO3NSOzBiIz9wPnJVRElQUGgoWk8KemZ7PWU3K1FG
QiRLMkEkQGFVYHpwQX07d0RnWWZrUVp7JFBBb0poZXthTWVZbU0jRUcrYCt8M0BZQDV3VFhQbSVv
CnpgNWluXzl3T1RTXlpyO0dNZ2J0UDFsPlclNUI2OzJoVjQoI0IwO3M1RmxpbzlAczZeMGUwbEVh
ezYrNl9HUjg5RQp6QkNJcnFIQXFJaVB9Q1RVQGMhLXZULUNYTmU7TUErMUVvRSpISkk/QjBVc0xX
UkdERXp6U3FCanFJY1lRKy1iPlUKeipuSU1vNFRteGltJGBEcjAjMGVeOy0oIT5iQU42KGZpYXx3
dF41OVpzUDUpTGh9MDl8STVGKHQlRmJUcXJkcyZICnomP1gpKDQ8dmJ4MWB8RnNtPDZjZU5HIXBS
X0hOPyhFc3JxYlZwPmY9TVNYUCNrKzMlXnZtbmchY01JT2dtKiQrIwp6dFc8YFB4SSRjPTdWMlJX
WTlycEU2bnNwRk8+dCVDZF9GYUUzN3N+QC13KGRYQmp0Z3IqPjZsNV9QSyR2RCYwMloKelNIcnV3
cmdBQGpLSWFUaFp8UCNkbUdONWJJcHx7KWM8K25feXMzUV9LaTwyRXBBSyFLemYhfilMc3w/KjRz
WHx1CnorR3RtbGl1JSFNPm4rKXRvUyZWXmFYfH51UikrY1VASyQha0MwZktiT3lqRlZjeThkIWhZ
TTNkdFYqWDEqaWc9Swp6P1p5WkE8ZzYzdj56PEVDJEBfVHBicHZza3RQU3xZdFItQzVISUYtb2Nr
cWtoOWpxX3NAIW4mXjVMVDY7X1IocjgKemFqO0orKSRjVzE7IXpeP3FnR340cytGQF54Pj8+YmdK
WGpYTWVuI0h6a14/bj80cUtjbVdEST8yZzxoTGUxUCNkCnpSYXp2I3A/cjFjKTcrY2UlX25EXyRr
S0VOQlIpPWkwfSYkY0RRYVNkfEVPbW5tdnpxTCQ+SVJOJkZ8KlA7dm1+OQp6MXhpKD1zY3BiOCFp
Mz51RWtoQTJJUUJKZjQyQHhTcylaQjdjMjNRN3VePz12LTZUJm5kNyslKyZYSFhfUn5hVFAKendp
QGErbEpGO3s7U35VcWshT0hUOH1pJGNlamVYNno8YXZwYWI7STgkRUkyK2MkWHwxa3RCfGFhWip3
QWhVXlReCnpadFk+blNKK2VAO2V9RjtiPiRxfXFhdTZiR0k8ey1qK15TSnVuYTtWTE1XRDJZdzVC
ZnZ3e3JzUW15b2NTIVVZfAp6RXloLXhVTU1AXzYyQnwtXkkmbGdDSDFzUSgoODlSMnBeYDIwPkhr
NlFKWUR1IVQ7SF9rKUlGbTxrSFNMeXNpQ00Kej1Bfk1SQEQjblAmaVA2dV9FcUgoUEU1RDZHfUQx
c0N+Q316aV47aXx5cEplKFBveTVMekJWTz43R3I0PE9ES2lfCnpnQk1LLVNFfD9YUWU1S0UoZnwo
P19jR3VyV1U4OzlFYHFOeWVzezFvanQ0TD9qLSteXkJTPG1pQkVIa1ZmaTs4TQp6STUqcUYlQz1j
NyY5dXtRMTdjTjU+V0RsPGN1Rm9BbTlAX25pbEhZK0dtfl47QH5jK0JzYTc5RHBad258I054cTIK
ekwxUSptM09yVUM7RjxDO0xvT24xJXhIclAqVSkhdlYoKUhMMG0za0pmVUR+ankrJiUqQVB9SnxO
S3c/N2U7ZU07Cnpvdz1STjRfaTRpKTZIb3VvZzUhIz45aUBiMWdLM09HNEU3flFDIylrSEVVNzNG
KyE1UjdsRGNATHExfCNSQTZsLQp6JmtMMHRKRTlUfVBiaH0wbk9eMztOPnI2S0ZoJjZ1Rko0PmBC
TCQjKU4tcGEpUCpWaHAmezF7OXdwMHFORTlkIz8KekBLKEJQJGVkSVFeSFF4RzdpNT9qcS1pJCs4
M19uUEZ4N0FfUWNxYnUxc15seUJLRWlueVBfZ0g7fVd+I0dRJlE/CnpYfGxJNTZvWChWdjdoSXBw
QDR7eSF0JitJJWU1YTBxeH1paCZZUm8mX3xWfGNzVXFUTyY/TTAtQXUhcj1GdmdGRAp6Wk9QV0ZX
UFZSbz1YRnpjfDkjYWVqNT5yPnVpcn1JNVpZd2w/dFllSDhzYiZlYmFyKDt3UlBMKFdnX0FMMn1t
QDwKejFWUH5EJkYkUnxvSndRNjBTODRQYW4+WDs8JD4ofmE4IT5IZG5GPj9AOXpZYGg+I0lPWkdF
WWhETnZaK3FFQXFPCnpBaDBgdkFhRW9EK31FWjY8R2wwZkYjV3Q+LWxqKUY8MzhPZHo9O0BOWHFx
XkpNfShrWDRpeWFQRiFQKnE0eXA+VQp6JiYoQHl3NntOTXRVKjs5VlIzQ3pJb0tOY2slKzJfdjQo
N1crd2FIeit5SmElbD9QYWBYdSpUMlIxbUFgKWErRGoKekdGaG1xKzh+dlI3Y1hBO0s9UHdSPTNf
Xj9zSCZZZVhhNFU4MV9uPHZYOEptVU8lQXwkdWVRNnBgXmx9X0ghWkleCnpgM24wQipvc0twKGI0
ZlVZWW90X0UwfDRRSiEtOT90RTJzQVJxdWIpIWpEd3w1M3VCPCNzND08aHQ3THYkMzgpJQp6YDg5
cE55bXZOQ2hpPnNuaSs/bSQpXk9tUzh4c1Y5cEVJWlRTTiokcFVzeUYyT0BDbHw8NWJubW9IX0ha
P0tgJTwKekhJOEckN3pHJFYkNGVaP14hRTF0Wjh7OSlOUWVmSGNEej4hISUqZmdTbnhNLTlLKk9s
S1QpYDZSRnd0dTd2OV55Cnp5Wjx+ZmBfQ0NvcldIPVQrR0NFSGBQKz9+VXdtYDUzK2FCby05JW8j
aD1AUD1sJS0kSFdITlo/c1pKJFJTSUZLeAp6VWR5NTBjYH0pZG9feSpfVSN3MiYyTXFYXk9aWnIw
ajV+NGgod256Iy1GQl8yIyFSRXlmaEdYTkFgPGtAbnx0JXgKemI8YmJ0eXwreFQrV1ReR3pXM2du
JndUYmpmNDtNYGJEajQtcGN4aVVDJXBHUT08TXVWX3Z6MnhfeXpDJWV2YVEqCnpVUVBrRGszUEJY
eTZjOVBFbmp8aFRVKWtWJV4mTWorcUxITE4oYnRrQmlxKG1LSTY8fkFHKz9rdEFfZ01kKWE1UAp6
eWkoNUowYEE7JSZpJikoKX4+eSFSNGg0VGo1Jm5BWWNlJmNfdWdrUjhHRip3Q0Qre2w7UWltSEQj
TXJpZ0k3eFIKekl2e3hQO1JuOGQhdG8wfm1yaUdfX2tKe3UqcmNJUUA0WmlfR2pgRiE8M0lvNExs
MW5QI0JWIWptRGl6OzxpSHBjCnpwSy08O0tEJStfaFFCVHJpJiRmdkhwOWIpSyleWmdaNj1kcDts
ZjNxZjh2UXB8R01oOCNmUns+aGx+e3d3Xz9UbAp6KlF7TjtfUysqUEJXViRkTVdoKVdPZCpRSz5O
VXRfdipqZ0FtUiRHMTFIWmtjeHwofVBeX3tPfndhPSspYVIyQEgKei1MaGlFKiUkVG5eZ0poRzBg
SSpaPmRCZk1SLUVAPDFyeUFlRzJ7NmFFNiU7PntgPkV7TU85elg/MnFOdUY4OVdPCnp6NVZ2dkBC
N1FZe1BYakFkKl4rLUNEUzZfdEpTMmxxWFV7cnFlKmt7Zmg0PTwpdkltRXZgQkM3eWw+eGQhKyR5
Tgp6X1M8aX1rN1VrJk1ZQkphKlhxcSV6IV90Qj5zI054YV8jZmEtWihmb3lzfWEkQ2w3QC01PzNE
d1VNbzdTcU9hcVcKek0rKm5zcXBKQVRkI2B+QWdraFNfdTh3PF9FSURiX3VZWX4jVTVRX1FhQnUo
UmNzPGduYndQMXFuQndmUyZ3Sk9fCnomNn08dCZnQ3d5UjRTJkxIJFglakF9YWVVTHNKVlRyWiYj
MjwldWVfPk1VejVWSGojaFhVOHcrJjcxIX1BQTBDXwp6S2FIWFk2MlpVYiRuMDxrVilPIW5SS1Vk
LVVBbGJaIyZ1VD80aTNHZVI0U2J3TVhgMHhxM1d3IWxiYUZiIUFVbHkKemgjMEszcSo4JilXWVNN
e2IjP3UwIVF3P2Z7PykoVkBue3J7VEtVJkI+aTBqfTtiVDhkUjhAS1J5UlNOVikyOCszCno8Wn03
NSVIYDVZYVUzMSVvUykmblomaHVzRXNSQmsqY2VsPSo2YTt9KVhzRHxeSVMocWB5PXpgRk00UnJu
dHlzJAp6TH4we3YpYmJ2ZF5CI15qOEhjR0pxaVFPV242TX57JjNDQERDYzk8SkA2IVZWbTFZaU00
QmckSz4rTX0ke0BCT2YKekpyVj9nX3VoP2Y8YDUpPm9IcmlVSEpRbnJpKShYIUV6PEJiN25CWl8r
OH1+YFImYFM1JlUhbXpQM1B+PnNHRm5vClp7e2k9SWRASF5eS3F2cUowMDJvdlBESExrVjFtRUIy
KGJWRgoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9lY2xpcHNl
LW1hcmstMjU2LnBuZyBiL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTI1Ni5wbmcKbmV3IGZpbGUgbW9k
ZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4u
YTEzNWM1NGUxNDllYWE5MGI2MTBhNjljOGY5YmY2ZGViMDZjMGU2NwpHSVQgYmluYXJ5IHBhdGNo
CmxpdGVyYWwgMTU4MjUKemNtWDlfV21zRUgoKz0ocU1UQCg7eUY+OSgrQCpNTjRVaXgkNCNuTEk2
ZmZAWCNpNipueUljNzN5eCpUQkMpYnxjCnoqX25IMFhHYkQ1KUQkcEtObCphKjBFVXZIdFFHKE8x
TntqREt0X2FxOE0qIWIzSUs/dURhbEd7YCgmTVVfK31YXgp6Xz9FbkQmazE+LTdgSXVDcSE1bG93
WFkyR0JkIXB3SVAjbUY2NGZFI0I2NWQxO2ltbjtBZCYlZENhUW52ckdARUAKenFlYlRsbF5ueVI8
VDhzVWJjfC1KUEdCMnBWPVptQ15MdWJGVGk+OEtTVCpfZXQjYS03OUMmaGRVe0paeldhdXJsCno7
b05hSVp8RUV9dn4lU25OKipfflZATEgqTUl5KmY5d3ZOUE1GTU0qT3R1dXFtLWhfZUEzaD53OTx+
JSt1SEZ1eAp6UHt3MSg0Y1FtbyFpRDdVQEkzcjdsJmIwJGQlJHNWPH5KPlk0Z1dnb0MreVk3M3Um
VXplPHlkPyE7Vlh9Ylp3cHwKel5NNmRMUGl6QHlKVXsxX1NGaUJJU1VKa35QRTEqSTZFOTNwPDVj
UmA2KGohWlJVc08zNl4mb3o4KTt6dFp5cnUwCno0RCQoT0RjT0glSVAzaTkwenApPCtsPzBpQ3gm
Uj4tc2pmSnowUV5jbHZ9akxzfC1xNiVYTF5qP0olQyN4fkA4OQp6KkdET2FEPjg8c3g5RCFDUzI4
QmFsYDFrMzVMWlVoQk9+QHdrYDM/a2JoSnBYJXVEQkF6Vj8xYyVXMXh4aTR5NEEKelZ7PX5tNyVE
WH49eWg3bmAzb21sJVUmKDUkNTg7X2k2PkIrKzJTakV0TCVgfkBIODJDVH57dHAwbEtBbzN3UyVn
CnojS08hckY0ZmpteGJwKiY0SmBAfDNpVStEJGpXfk1BUD13ZCppVUxvPUY4KmZDeX0oKzYtXnRN
MlpKZSprJEtXQgp6I0IqMnZQMHV9UE90JEJFbVEpSnVSSCtCdkN1WWBqNXhDT3l7QkErbi1LUyt2
WWFtPjg8TzJeWFVJM0RHMVclVVYKejU1KytCX29YRVE5bVVRRUlpSGpWdyR0WWYqem58VjxfKE4/
VnNyKCtEK2hrX1MySnR1KVJ7Y31NWVVgLWZyVlV2Cnohd2E0I3V8eml+TipNaW07JmdUdkgpaEVE
OSpkX2d4SFNaTkAmPnUqXjB6WG9RTVIxKCo2fWoldDtrT00pVWlzawp6cnwhN3RMUk57ci07UUhY
eWQ3NXtLZW8yRV9+emB0JFozWXd2RSNJOXNXSXtLRUFnekRCJGwpZ0lpUmMyYXY/YkoKem5pS3NU
LSM8SihfNGs8R3Jqcm5VRktCcHdFLWAoYjRKKF9vLT83MXs4JDxwWXI4a0lURHFETDJUeklLa3tT
KX1zCnpfVlJHclFmdEl+VkJmJjNicDIoQ2l7ezFBN21fbkN1U2tQeyEpM3Q0b3pEN25GWVZNNWpM
PytoYzBJRTNjPlZ0SAp6QWZjbD9IIzs7KkxYKEM4WWFnbCp1REVhUHtRaD5yfDg0T1coa1RYSFhI
RmdNY05OdlNfNH1HekhzbWZqbUBiNzQKenpsKDxPZmk+O25CdkdnR2BLMjBrTGg9NUVYJH4xaHpV
blJBZiohLW5Ea3BkSDtIaVVqIXxseTdQN0k+Wj02eDNFCnpUQl9ZRSNHdVNsTFBXUkA2bV5lP3cr
byYoWGxROFFhXylKM25hXj9eZTFBUndKPyhxNT5+WWk1YjZRNjlyc0pqewp6V153JmM0fHZAbmRf
NS1naFF3dkJHP3xKU3YySkpLUldAdVkwTSpeTXZmT1BlSiVLPXhzOG5gSCskV0JmK3U3V3cKem81
Xj4yVzk2KVArZjdeMj8mMDRZKVcqJn1jUEEzQngzbFZSUzV3XylSSSElUjF8a1ZoQGs2cn1mKEkz
LSE1V15QCnotZH1XYnsjPHxCY3BRbT9SNEEwZmU1RTgyJXN9TWlKX2crZVA7e1FeZFA5eW15dzRZ
WHleNkc/PzV2WnVBfSghMgp6Knx4NyNYaUIkYmB5PXJaQ2xCPU5lV3BWUVAySH0tLWR+KnwkTlVh
KS0qe2M+KFlwYVV2YzA0eEZGKWVHMXpPQXcKekF3NDZ4JT9wKGArYElkJG1zM3YmKzBecUp1ZFVz
RVJ1a0ooP3xTUklmVFV8TlFfcWNnTkNYdmZQMG9ZZ28rZCRvCnpXNjJ5SHVmUkMqK2U0ZkMpMXkl
byFPRGk3c0V5ZkgjPnhpUSZGQU41WlkrdTBPUGVhY2stZXI+d14yNDAjZVJ2aQp6PWQ1cDYjTkYk
ISk5Tk4zQyFwN1pnKGx8PEZ9X0dAaURSSlgzdn1JNzZyUWdtR2p5Y1lLNmZrfHR+WjM9SXRrTykK
ejcwcmFAZW04S1BpI2RaOUpSakVHRkxiPnhtaVo8bF53IWMmZlRCNDhGNTRBNCVkQzMhRXxiZXFe
UE1qJj9+aXZOCnpfanhyI0g4V3YhTnRuT3pMQkpLI2phTzZoKktzKHwlRWtzXlo8PWlHJmB2ciZQ
RUJ9UGpfPUt9T3x7czIhMjV5Nwp6IyZickBqLTVWTG5td0ViN2AxT3wmRjJpYDAoMSVTMWNgQlNn
NjlxSlpGNHN0ZEB4bShjWTduO1RnJSVGQ3hqbT0KekJwPyU1b2UjUjJfXktAXkQlSl43Rnc1fFI5
WT1ReVVDd0s3QyFNQGd4IzFLWGZwR19VTih9fGNeV1hBNztJTWhJCnoqSGklJFZCYnAhckF6ZE1u
biVBJTVzYTs2YmlmSVFiS3BXTjY4WkI8UGYlYjxPd0tXPVpedz9WbzxFfX0yPEJuKQp6P0Y5MTdD
ZVZJbEpWLVJrJF9vaFQ/TDVmNzJ6KDI5c0M+RVo/Z3F+K0tkJCthUHNTSjQmKWJgc05zX2wtXmwp
X2oKekh2JiNzUmUjX1ZocVBOJlZDQCRTYUNZY2g+KmEjP2BwcTRydnJ+b1M5KFY7NXtUd281RnVU
eWk7NjlvQztRdit9Cno3alBgeXoyMns/UF9hUW5QPlElfT83aH0tK1NQUi0pM3k1Q2kmaWV6Wn1U
RlNXMCNqLVkwVlA1XnFTNUFJa01JQAp6X01HRjd7cDB3azJ4WWprWSVoemMrbW07MDtCeyR2cDx1
MUQtNDVFYlNrOTNvNipXSUh0YjRCIyF8VSNXX3VEbXcKei1Pe0NiSDlEQ1JhPXdiJERuQG5OSjxY
KVZgfEk0QEAwezNJbFVNU3xUU35fNzVlMk9RVFRnNyZvbSZ8VzUqRT59CnpXSWQ5QiY0X3QwNTdT
dElrRl95eiZkO19qK0hROGYpbGgrY3QpRmt6V15SY2c2JG0oMGhkaXBZQmRuXjFtRzFTcQp6I3R5
bX5XXilLVjFkRXZaSykmPDl5VkF4OGlJR29FT1g3flJuYnZHaXc9SnhfWGNoZ18qYnhjNGJfbmkh
RWN0PkIKemV+d1dkYyY2WmV6VXVqZHpAfWstNUQ1WihMNThVKSt1ZHRuQkhOfllpPzh9NjlBI3xD
JCZvWlU3LT44fGNBM05fCno3dCtyI0ZNanVMbVYjQjZTKl4kK2tVWnwta2MhcUpXS1ZmTz5+OG4t
YGBLclRtdyE9O0kmaGR1dnRlWTdRSHFaQAp6aDlLWFkmMkJTc0cwMVRCMTVsSkZMYCEpRGBWNl94
LVNEYWxDdiVlcEYtbipMVVE5dm4jP0ZnMWxASDBUX3pXMGcKenVhXzVCVj8/T2QrbCpjIWpkentM
WVp2fHhDKlRXTDxoNCp0ZXBwLUg+b0pNQCVSJm1LNF5mWjk4JDBQQVo3WWxQCnokaUJYWCNRRHEw
eTN1fFAzVyolVThVWEJtNm84IUgwbG5fQkZBX28/e1RwKEpjdGtrb2clK0FoRjYxdSFaJHpxUwp6
UkJfMTB1KmpvZmM7KCt1aShAanlISkRSaDUxfnRRKlV4SilDO016aUZvO3U5PnRvS3FWLTVtJXlJ
PEN5YSYqeWUKekE5NjEkQGN1VzlLZXxyc2BRPj9gXkNKN2c3YTs8TU9rKUdkNX0rbktXPVlFNS1l
JHlKN0BhZCtIenJDeCswUiZMCnorK3lfZz9GWXNNWnV9dDN1YWBZWnNGMHNiYjBNIThveUtqfDtY
NmNvcjJhbWxiK2B6XnY2bEN6Pmo0OSV7YFhOTwp6dUdwSTBGc1UjTl5RKWVkVmdmMTNkI3VYKFM2
Znt9SmNnUSMpfXV2az1kbz1VZnJUXkFueXhRY3U9SVFZbjQpZmQKemhuMG1LVSZ6VnY5ckZtem4p
diZ7KXRGOV9ecWY2a3F3fnRXdSsxNF5sMighU0M/MlohJTtufis5cGNzNzE/WVd3CnpZYipiQUhY
Z3tMZFdoI2BkUDBicG9aUkZsTmFENUlmTjFWSTZmNVZIUjNJXypVMHRsXj5EYSFnRUo8ZkpQJVY5
RQp6TjYwTm5yX3JGWXRSIWRrbTg2Skk7TnFZTGp8M2RmbX5iaTRXd1ZnO1gtODE0NC1ffVZ2IWJi
NyR7NHY9PWwpUE0KenV9bjZpeWRMX1RKcH5ZZEo1cHg+fEloITM+S291bT0jYCo9SytoLW12I2Rn
MUJoajB2K18hQ0pxUGJnZnRnT1J7CnpPeV5GMDd9NGs5SzkxNF9gK1ZoUD49KSRqb3BlJmhxTk1X
cTw4LThYdX1mVSYmfis5NXZNM2FFeFZOX2hjfUA2UAp6NTYqbjMoKG9KTSZrPilWaClsdkdWdE50
ZWFsT1lDSGdnSUpkTmVrQypqb3drNj9JMX5OQHw/djdVY0J0QXsjKVUKekFBd1YwSzZNN1l0VkVT
MUFLVGxvSnpoZkw8LXE4YG1hT2J+KlZLN2VgOGBxMG1JQlYhPmMjbmVheiVIcCgyckY3CnoyP2Bq
Y0Imfm1pMjFDXnNrOVNIKDh4SkApdmRMaTdKbTwtKCM2bV9iIz1aVihmUkNzPCMmPDNETlE7Z18/
OyltYwp6anhAQEkrLTdffHNUTHo0X0VeXjhkO3laJUY7Uj48M1dzTkVTWlhFeS0mWTR4dWRtYD1t
U2VkJmBxNyg/Ui1PJDsKeiF0OGNPYnImLTkreUZ2RXN2QGw7cTY3Yns0SUBkV1dXNj5tJTMhPTZ7
VX49I2htWjRnNDljWDEofVFgKihzdHZyCno0YVVeTDtoUn05UylWeyphKTNmVTFCWWxYIz4jMUJV
eilUJUpzWU19PUZ3bkUlR203eW90dH1wMERAd04zNl9jZgp6YFModzx7a25oJlkyMlEydEVMcD4z
RT1gaz5jJFYyPXUkKXA8OW1uND1meCMkaUIoblghcGtDdT1aQVRQbGArIWQKej5XMXRKezlgeytk
aSR8d0hqTHdGM0skRUZEeihhVmg/ckF8bUAjPW9qalVYM2UrQzc/K31+bnBSTyp4fWFHQ29FCnpE
dHoqWk1PMD5AcXQtNSlFN0JDPlJ4WSlvQ0JqMmZ4aihZclZMYmw4a2FzQnB1ISt7Wl9gLX1hTzZQ
aiNteExeaQp6RVE5KFRtVndNJmJUcE5IdWkxSzNGbVE+aEJDUUxJJjtwQ2I8TGsjUWJQYXB3bWl9
OS0kZUB5MmdTbj19JFNUal4KelNHQTVjWFczYEdQYXBIRTI8WHZBWjBiRE5eO0h5eGwmcEEmUyVa
LVU0O1ZqdVREQDYkWCtGc1RCS0w3LW9BNmZRCnpnRjQxQWxXLVhwMTx6c0tCPChIfnFJdGpge1do
YnxjVDA9UT5ePUZmc0dISUcqaCV4MCh2RUMlZWpoY2JycT9IcQp6Nzs9Vj5jWFp0NUJnKnlhdTY8
KGRGMEF3JENHKmVDbiZJRXooOGIlNVJZZS16NUFGI1VuezV+fSE9OUo0JGdCKmwKeilBOXtzVEkq
eWRhN0R0UiR2RGUjbzJEfX5OVHU9MnFLaD5jcilLOT0peDhESzRraXk0X2VQb0slRipaaz8kU29k
CnpvN1dIOFgzSH0kXlQ5aEtAYE88JHlPTWNWbnw2dCNDNlNPZ2JERzJkRFF5eXtwWVZFUT5LQEJX
bDRlTmA/PSVgQAp6Tj9UWU9LKE5Va3wxPkVZNntUan1jT3swVmhpISF0WD87bGchelJ+ZT0tejN5
Xjl8dkE8cTA8S3s+O3F5b3hPMmsKel5qYCUrTyYqX1o7PX5Ab0c3JmxxJXVlRj44MkoyZnZqSDUx
bCl2NDh3JihsSjNPRihZQipyNC1WNmF3WSN2fGckCno0UTlSNHc/UzslODJPT3ZoKDJPVHgrayln
PjZIfnl3T2NSPjI0eXNMT2sjS0QhP1lZcmpGdnt9TGgxYThocXVSTgp6IW1RZDMwWX5mNClORUom
QUA0fkItTzlkTHZDSEF2ezxpeCt6TFZfVlItVnpKez9LMnNIeFp2SVFDVGFSRFUhczwKektpS2Vn
eTtXVEYwMi0+Ny0tYD9kPUpON1BsdGYmU0JSWChkJFBJITheMVJufGA2JFFAUkYoK2BMRihrPlYo
fFNmCnpvWTRnK3k0VW8pO0RtNC1zJDJKIyFqTmVhb1A1M1YlYEQzfnVGKTMxdm5iIVFEQVYyeU9Q
IXlrXkFVfT0xPn1aZAp6cShvbT0lcHwlRjE1JEYmZVI0IytvVURPRyRPK01aaTdRN2tNMXdiUml4
P3QkWHxQd3ImMFNteTl+VyhWQlEjPTsKendGenVfXlNQYC1lb2hoOSZtYkFhLWpYb3xobGdxc2sr
O01BbDFSeVY2ZDhIV0tOI2pSdSNfV1dPK341U0YyS3toCnoqJm5VbVA5YClPZXc5WUBhXk9nQUJi
VTZ4cHFlQVd4O0ApJFRnbGxER3Q5TlAoVnomWTtlYDI0RE8+bV9WZEJaawp6PnVpbEFmPCY8cGo/
Xi1WbmwjaShSV1hsR1h8VGBLX09vKEVDdCpfUSFVPisqLW9wWigla0YtPExHK0FaWHBuTXgKekpF
cVRfez1ycGp4eWlfJE98QWxFPGxve0ZWeE44Uzx4eCo8dllXYSEhPjF2ZWdgMzFtXzBNSHJyYi1W
OVAjTV5YCnp3K0BDRzx+WlJQcSszaTEzeSFUK2UjI0BqezNZIzRhLSttfWt5fFpQdzFrS2xScEo3
NGF8MUNpSWA7M3tBMW1EUgp6M2AhbXM8JlAmRmlefENoZ0RDRkFoZj97KXlSJF9hJjc0JkQkRUk+
ZGM1RmokLTM9S3JjeCtgNl4we19IcTZMQnIKeiF2KDtGVkN0aTR5JEk/OHp3RmQoNHtpI2RHdGMo
Wi1sI21DbEU/MUNmNE5LMkstUyQ1QGNaZj1FYTxLTz9iVUltCnpFP24/aDNlZ0UmP1c/SmUxT2Fh
fVdpM35IMUM5Sm9FfEBAaiZKR3tBdzZEPXh7bTMkVnhGeHImeUU0X2pBRCNVTgp6JHw7ZVZCPHx0
b1Ize1RrPWg5UWhaeHBRc0s9K0Zze3MmNyNIUz0xLVIrP2Fmbzw9WXQyX0ZMbiYyUj9US2FGbGAK
ekZ0ZUw/MyZTa0tIdXx+bWo+TV9wQGdtaHw7SDljOUN9KGQtMTkrQG83VSRIOWZqKmwhJHdMSjFl
O25XVEc9dWxSCnpxZ1ZNOGlebXF2JStSQj4hVzxxNyU1JkJ5Tj9IbWw0UF91cm5uZ1F8M1ktQ3hx
d3NOOyRDQzBsTlZiNDA8ZGJSUwp6OEhMcWpWX1NgKEg/Rk8hRT5Ke2I8c0xtKCZsezwwP0c4NGJR
cFMpemo5e1U1bjw3ZUNLcD9yMCNGTytodmImWWEKenJtN2swNihaKlZ5ej1MSTkzZDl9PUxGcXJo
KEtxQSVONEJoaTJ6bGNMYDA+dy02U0Y3Tzg5JT15Vkw5M2tDJXZuCno+NzA/MFVndTZCTlBLfXR7
eyopLSVWJVZzLU0kTGI+Pk8kK1ZLfUpZWENmZzYkI28oSkh4a3R5QG8xKkwxYjE4MQp6ZU5BZ3tE
Xyt+dDEjS042Tk02bmQwYk1RMEt5T0RYIW1sSUR2cT5XenJONms/NyNBRz1SVGhhUS1uMFpVbk1v
alMKenZjTz1mYUFXZEdMJHIhfE1SYW1VWX1US0Y5QFlBKVBhXzh8U2tBSl8pKytTQlhvZkZpUkl6
VUlVcURpek5AWVgoCnp4U0s1cVJsWVZaMkQ7OXRkVFkxYztIZUFBUmdSYTElVXdpREFGTT9SUk99
dWB4ZERBPzdYUGo3XjJhYGJFYHFrYQp6c09gNzctcnxFbDZBOXlBWWJMSVM5XlNJTFJ4Yl51Mys+
USYjOClMJE5hJm1mezBMNEc9NVZgQk9ZbUYpWnxCfnEKem4rO3RRd0NOWEUxRCt9MF4mJDZqMytf
diNDSkwmb1MwQjUrNk05KnxzVCRJYz1HY0dWYykzJTVKaH54ZXZieFRACnpFUUh8YWZ0OEpoZ2NZ
RTQtZTxHaVolSk4rT35SMVQyaEVgT15HIUlPWSZrZ2x1I3xMZT9gYjA8eHBldSRBNXJ4Rgp6JGNV
eHYrd1RjbmNSUnJISEc5eG11S1I5UGJ4fVJUQiROTXBnLURsVW1WQlI2b1duKVkyVGwrancmKkMl
LWwpY20KejgxeWRVWTsjcGFzSX1BeT1lPCM9KnJINUUpRWF7UmFKRHt5KGUqNG9OcX1US3hnVXtA
Xjs4bGZaKHtiX3E9K1Z3CnpoSTd6YUt3UG1NaEt5UkM+QThUcCtTczRXd0JfcEl1PSZ1NCp8MmZA
OUVjdWFWTnJPNSQtUD0qaTYjSSFlc1FjJAp6djdOTiljcX5hRDlRP2lJX3gpWmFSXiFEbEQ1Uig5
TUkxZ0Z4K0JrVGc4UTxOdD9+RW9faF4mKCpRWHk9SktgdjcKej15YXcmZXRvcFFhQnRzQS02KDkq
RFB8az94dVQjO1htXn5eckU7NVpzdU13bTU8d2RAZjI7N04lRzNgUV5kUkVRCnomfiZkLUhyV0F3
SVYlanV2ant5YE5vbilgd2xecGVDPClSb0c/VUlmJTd1RSo2fXNXcyo/O2FAWjE5fXtOSyQjYwp6
MGU4PyUpRiErS29Nb2NTPVNWcT9IZnEwYDVxS2FIbFBgOUprYmRqPlphanpUJUs7JmxpTjdUIXM/
ei08aj1SWFEKejQjMVNtIS12ejFWSWdFY3hUeCs3VEsjVD1jWHpJZzg7Rj98OUx6NmpPMHYhNzRG
TmtQUSMlQ196TjtqcmZpMFZMCnpkTG5OPWFINmFPP241KnFeOThwbnMtRkQhQXtTPCNXKll2NXtp
eH5rI2pwNz05VnlCNXFjRDc8PDc4dD11c1FSZAp6YSVhQGYxX2t4SVhSS0RvQG9aNHlDV2FZcXlf
VUEpKnRJbTBYfiFWfT5vNmY+KlBvOS1zTyViayprVmxKRiF1cDMKeitMQT9AQnQ4TUA0K2JQZ0hJ
IzlkKHhDNiZ6fkY1SFZQb0BhYGN6PFExZmB1R3VjSiZSTzJ5RUtQYnZDZXkjUHIrCnp5M0h6IUxe
Mk88OyNTOS1he1pEVDlWY3ZGWT96ZHA+fEh+cmx9ZjA+PmNfckdae1NeRytxUD5lR2J3Qks9ak03
ZAp6ckx1e248bDc/QER1bUVFdW87YGpRaXllPlhIdjlBYEtKakxHX0s/dkRLTj49bTA4cU58STRx
JlFNfiNMP20ka20Kel8renMzaylka0t4T35FQFM/QU5zTFNrMD8zN0owTHJJOCZOWXlFK3pMVUZs
dGtZQCFhO2pEangwWVR3JUMxfVZqCnpzZW91ZiRZITFUb0FgO3ZAalNPTTZPcXNwWlhySEo7QVd+
USYjSG5VZjgxVUVkc2JkTktDMSVYYSRRUyZwSVMhZAp6bzVQfDRmTjctTmJUfU8+QUBZRlIrUS1W
NVN3JlNzc0xVRVchOHk5WEZWX0UlPEQxbk9QNTVwayF6M3BiYCYtVl8KemxtYVhPIztNb0JGQkdO
X0s5ZShRdy14SHNXRH47VEFuNVdgOGEten55dVZDVzJ2amA7Jlc7LT03MndYeks3OzReCnpWVm5X
OVJCdFokUzJKPj5Qa283IyNkXzZyNDlsQHUzMjJuSV9fPTxNWUY8ZlVCTl5RY2tiVEEmPHNOMTIh
aHlSQgp6ajY5c0BDSXFUbkB0WG13V0Y9ZjZQMDY3JllZTFJDaG4kc1I/XzZNKEgydWxLJVlvcENI
ZjFzUzVTdVpAKUhQZEEKenkkPD8oKzNRRktUQz4+fUg9QElyWGV9Q3NaQiVKXztgQEpwe1VKNUxz
WS1EeFVPZHo/KkJGaD1fJTRDOWhDc2t1CnpxWCZHUnJ1S0gpPWVHVHVvSC1sS1NlamQrRD55K1VD
LWRQMmV1PVRkSHNBPEM7Q1BxNTJCWEV2PypZdz4pOWZQfgp6azZYSkQ8IStvcFRAQ004dFE8RztD
XnNrY2BQdTAlcz0lTk1FPlMrLT8kbGc4MSl8Vy1TKFVuY3s0Yjw5aCZfclAKejNvNXluTEE8TDhJ
TithRlooKVZQc2pNYkZjU0R1TUx+flFva3JZWl5pRj07aXwxSD0hTHJJSmBtVHVXQmhOTkoqCnpW
OCN9a2h4NjhlJjFNSGMzRChTYnMxbmJ0O05OTXdoe2JzeSVvbTRUOVZ3dU1Pb2MmSUJkSlI8VC1m
d3hyeE9zVAp6XnpNTzYzNntRMzM2QEwpY1VEVXJtR15pRikmKkg4azMlS28pKFVwdihIQzNge3so
VURgUiFXPmY+TCteNEFTelgKej52aGo2KHY+eXIqLVIrTiFRbnNXVTx7UklVYl96WCY3dnZaR1A0
STglP31KdCtga0ZJRElVTWtuQUJicHZGcTFvCnpTIWs9WEshfUw5dklTQTR4KnV7amhUVWMwY0t6
b31LYmQ3MG9eUGo9VkxBJUlWZEZNfFBFYm00a0x4cTRzVVc9QQp6UDt9PyU/N2ZTJiFCb0RiLT9E
YFNHc1lTbS0rYXFvMUVYUmo/UyQ2PktlKzhCPkBYXkxzdWI+WDFmPFVrd2YzUyoKekVNMXt2SilG
XiFKfD1BRk5hY3FRO0R+JSQ8UEQyQFRtdiZEak5ONEl3ZUIlWVhBe3IlRDlCVTVESCRHdDB3NT9C
Cnpxfi09a1l9V3YzdERXPmZUIW9tRm1SMTR7Py1hVHhlaVA1SnRBRT0qeU9iIURPZkxrKHcmVSZ0
UWh8K2NMYS1aYQp6Tz93KSZBKXlaT2xPMSUtRmEmdT8jclIpKi0+d3F7WWRTSjVATURWb05NN0V1
M3dhV0ViVlZBYzQ5VnsrSX1QdjsKeiRaOHJ3PXxoRWJhNHdVPHpmUFchaTdsSj0pOV9+OWNMJD9p
WTBiTTNzY29LKT9ycEgrUX5ufFgybDRkTGMhdlBaCno1KGQyaGUydTEqb2ZZOTB2en4tX1JTQXFN
Mkw3WEErcklnMFBWWTBuQVdDRWRkaTJ8OTF8Z0AjaFc+Kk1UdHVeXgp6Vm48N00hfWVmPUM0V0Rj
LU5oKzI3ZyU0cyVTXkdBQzREOXdgYE8jYGkqJkx1R3ZnYT9iYkNLJlAqSEF9dn5NcDsKekN3a0M+
MXs3UU1qQER9fCh6SVBNITI1KUJBJXJjPj5RJFdFVXE1P2AydioqfDhAKWN1NV4/N0dMZHd0dkZ7
NkVBCnowQmRzVW1BZ0tpU05eOCNlJT58eFJIJmhNdmhSYT4rMEVNbCE8IU05Q0U/NzQjLXNFb1E5
TW1TOXNIQipzLVp9PAp6fE1MS2hibi1YIT52fj1fcXVGWk12djtkSmRWTXIpTSlzXyhxLWNKMDE8
enBLUiVpZGxkNmJzdXRzWTJyUWh+NWcKeipXSDNsMkdYQW9taXcxVihudm5ic3VWRSYpRT9pN0Nv
YzM9I3M/Mnd3XkxvNnJ+MlU5VCNvUjJjMz82Qm5IVD5kCno9N0FVV1F9JE5gdDExJik+bnZMI3kh
eztUdl5LRCFUPWh1Tj4yMlJHKGs8fVM5NnlfNHNYNzQrbjlBbmU8UUhJdAp6YCM2T0xZKnZ7aXdJ
Sm41MV41YiU8bThlcEpBRUs1UFFPNCZwMU5HRSZGU31qY0dSZHAjU1k+XmNwOHpeVn5QcT4KenZh
aShBZDMtQj48LUYkcSFZX3h0PVYpZHJ4fV9iR28jQV4+VmhESmBuKzs1VmZZMTgzOUBBank0SDsy
e291YVp6CnorRTFVTUJwfGlDV08oeCV3OUlfdS03NGstUHM4VEAjOUx8bS02OXhKUUBFfH0xd2Fq
JmFWKkQ9N0B8Y0hCUFhofQp6NUxLVzchJWYjQzB3TmJ0cUgyOXBjMldEUVlSKz41ZmhzU347TDJw
JmRkWmBiMThraDA+MkBHJiN5cF4yZEV5cHwKekpTakQja3hvY1FmOX5tSE5KaCsoMn4ocSRzbjI5
a0psQSoyYXJzI2lmYUdhdFE0N0RAYTxzIU1PcmM0aGhWMStkCnojZ2Bza2ZaeDQ1bFdmTD1VfEtP
QjtDcnZLMSVTQSsjJlEleXtBTkhTeUc7fnJGQWpVRHFSMzs0cnxKTCojPG1+ZAp6SGk4a1RKcCMy
cWw0P3E9Ml9ZVWc2c3o5KVZDTWRFVDIreVZJeDRpbyRhOCZFUD1gOWdRMytTdTZtUXhEXkZuYEoK
enZwa1QkWkRYeXRIfWhWfEt7ck44YH1RVWg7IT5YanRtWmVQe3VMdllWQXAtOT9rOEh2WWFxYHtx
cT5CejllP3xYCnpSLVozMk1uNUQqJEplIzkwO1p4PTAoQzFePGloeVNvMWY0M0g5Q0h0YHFpeTRv
c3g0PmtebnVVSy1ZUSl2fDwhZgp6SjljYlBqIStVYCF0d2RsRlVXMj98QVFxbWcqfipCZzhtejcj
bC1tIW04OV42PSEhdUk/N15oTEJ5SF52Skg+LUMKekUrV1dWMl9xQDlOSFgrQE5DfHZeKTBQeFcw
TkFjVzNIRCl9WXU2cHZXJFRlMF5jYyR5aytJeClpZChPVmRuQXBVCnpSQE93OFcqellgIXxYSmVe
eHpAbjE3fURnP2JzYjdjU21TNmRGYHFhRitsTHFMSyQwb1JWPENDYzhLJTJre3h4Ugp6TTNCKDx2
VT10NjAxYFBBJTMpLVJqITxpLV53PShhMkIqZUdgPUFeS1B7JDZwKjBZPExVZDckUVA1c0U+NmpB
NkMKem94RHZUVzcoKTZwUT1hOU9RUVpART9DOWolfVdBJV9KIWIzYzk/bFEhNGMqWERjSjl4dTd5
NzFyZDgwNGomaUt5CnptKV8zUGReUldjKz5CLUNwZnt9akQtfHVoaSVKIzc7NkhSOShWeVg2VC1q
TDt4YFJFVTd5Ql4pdXBYST1XPk89cAp6ZEtaYGNFMlhXSEteVnNmMGRsbjZ2LW85Pml+XnIpWmE1
U2ZtSDN7aXl3OTk1MjYtTCo+S1Y2antrN2ExTzYlfTYKem8tcEw8YTdDRi0+YXcjV1V9PkMpIVhe
Vz9pelZJSEJlO21IS2RpY0RuKUs/c1diM2VeNyliQEM+WEcmYWFNPHZMCnpfJHY8OSRNZl9ZOT5E
PHMjYWlPdWQybml1QyVxOWoqK0Y4R1pzfG1HXnwmd0Bpdlk/YzxiUV4ybmhoaUlYNVhCegp6Nyk8
Rjdra1dvOHVDKD9uKGNjM25eUWpuJUdYMVE3K2hLR29YPkdqd1RjPF9GQndFQ3heaDxiSVA3IX4r
bkk3YkkKeiNqfkJ2JihrPmtTX05BV2ZkTlJNPkdHTkBiRjVCQWt4emtyQW4xWkU8S001Q0smVkZ8
d200dmM2K0BCZGRvWnRvCnppWGg/LTl8N1R3dyV5T0A4QjB0KnZNdyR+eE9qSzZMXmM9Y3szdTBN
YWh5WDxXZFRvTyZlSHtlKXgtdVlMWHFKMQp6KEZ+PmgoUjVLYWlXaD9YXzkxR20oUDlUdDRPajch
Z3pzYl40JkBYb0E2bkg7WF5aT0VGR1M4K2IjRz5xRHc/SV4KenckODt8QD5pa2Y8dzBAYHteeHNT
TFFqc3RHKGNPZiExKE1kVn1lMEtkU2A1akU8e3h2IUcrbz9XLUVTNjQxS15lCnpJeiNhXzA/c3hN
UzBRVm08dEt1ajcmczJiQWhqUSRHSyZRVkNIIVombWAyOUJMQXVTVDRFJGYoa0hORmZ7UVgkTAp6
eFc5I2xXKm1jfWZHTktpNVApZDVhYDAyal58RTQkcEdnNjxIZ00yYyQlJDR+KXphJWZORGZBSFRA
fWQ7R1kleCoKenEhenclblh7PSo/SUs4RygxVmhCI08lXzBHWDxOUyY1LXl+Y1ZTM2NET2R0IUlU
YD0qP3tBO2V1fShCLUtGQ1MyCnpNZCtZYiZTRkBOeUplbT5rZV9Hcj5iZyt4cyY9PmI3QHdCdWF3
KjVHVkV0P3Q3PG9eWTk1Pkx9VTJnR1Q9ZURxVQp6dnpMc2IwJkFrS3owTHAoeCZpUlc0UE9sX2Rx
WlR9aDgrX0IhOV4ydkBzZil5M3RUUkxYRjtoflFYe3lwTjAwcFYKelh3JWpBNj5zXyQ1bnUpYCgr
Z358QXl3UUZtNHNAV2hqbGxBaj9+cUJmcUtGPVM3SDNnJThWc0h4en4xJGBxfik+Cno/aG9+RCFg
MX1rPzZnN2BTeUFOdWxueWRAWk5ANVheSzxMUjBLQGpIbzdwRUVUbFk7UUp7JmY0MElYSTApez03
awp6MyEtPHRLO2RXKmNRSE5YNlkjbj9YKit5QFRgPC1YRW5CLSU5ZyR4YFgqeHsrb1JxRitweW1t
eTRkWiQ2Y3ZXP3YKemZRan56QmFtMUxsVWEhenNNNlNkN1pwNDdZJHJMSmg+cUxTKyRBdlUjQkQk
aT5xM3BNKHB+LUJiZmZKWD9yNTJsCnpUNks1MiMtcz5DS3pkVT16KSZsPXB0aCF0a251cmtte0JI
ZzkwcDw1dXw1PD1AO2QqQSFLYDhSV2lIVCF2SUp2LQp6UFVRWEoxOEFwenZuKXpLYENAbEdOeyNr
ZlEqeVJJY0tSRFArWShZaXNXO3NETXxjJEotfW9DRlBoPGdpQnQwZzQKekZ4fTBlZDlZQktJZWsq
SShDMjREeDhIfWpSUXtrPSFmcnxqUFozIWQ7aGpONW53MkMrV2RXMmx2dFJ7ZjtHXjd6CnomYXo1
NEt+d2VQWFoqO3I3JE5iNmlNRXQlPjNAZjt5TEtlPyFRYWh1WU5QRGRfY3N6fXI0Y3oxZ1dqOFY/
M25xPAp6aUttQW1LeDB3YDIyNE1rIyNUUCQ0cmp6N2o3PDZ2cnJqeyt2Qno0UTJUM31WU3J9QGV2
cHI7RkJSZmZUY2dUcGUKejBMX3JqPW9KZ1ZoYD87PjNWM1JwQll1NXwmcj00bT8/Z19pMHl1aTZW
eXdRZFp5czZ1MXBoc3tYYiZBUSF2bU1LCnpMKCVCYFl5YjNjT0MzbC0jamRwOHtxdk51LUVaQmtE
am1lUypMP25mSlo4PXRTKkFCSj9FU2Y0T1MkaHw9TkZ4Kwp6SCFlY3hEJWFITDhRZS1EVzQ5X1JX
WkdPUntHLTNlMDVSKFh7IURpOEl7WkZLJW9ORD09VDR8MkwqfEtHRXR+TU8Kek9jVikjKTZNRXB4
NiRiclpwcUVfTkklQyZYXiVCd28kJGcpU1cwZT0ybTFBTVpWMnN4ak0wMiE4YmN3cXJ6PX1XCno/
SlJDRzc+X05TYzJ0NkBpK3AqNjRWWTZYZ0VaMlVoWm8rM0xrITw3TnA+fj1vI0FwQkEme0FLVlR6
SE5lTEp8PAp6LTtMZigjd2szRG85MnplPUQ5V04rI3p1TDtUSG1OcCVaTTsofjZWJmx3bWIoV2dp
M1hkdmgqOTErb0J9TTVnNzwKek45X1FvP2t3bj9oeSYldVh0Xj1YR30pVzNMX1E3JiM0Pn5YRl5J
bFIyPFE2bXBIazhPMXdWbmZkc09oJXd0ODJ9CnpFcVlLezlxVDBpPDcmK1RfQWpjVUNoKmR5OVN6
MiElXnlgZWl5OU9iS3FJPXNqRWEqPF5IMmFBRi0tSjgjTUMkRwp6JmdyJnZWM15sKjY8aypIdHs5
JHFLezU7K0gyUHBOP1RKbnl7dVNkMz5DLVk7S1UhTVRHc1F0VEMyPHl9RGIraCgKejdxTi1MeWRJ
VSE4Nlo2YVRlaSYjeTY/NXJIamI4IyFBQ3F9MyMze1N3OERwKUFCZkE8aCo2VW5VRDVBIz9pa3R3
CnpUb1NuQHglU19qeGx0PTB0XyEjTUVwUX45SzMoYXUjeFBRREYzNTtIOEMpY0txO1Y9Q19saj5q
aGtsT3ZRQGhXYQp6WVp7MTI9KmQ9MHcxRERJJWp2KyQkYypjNShIS0o3N1BrfDcmN0txU3d7Ul9B
WSNsKHRUTVRRdTR1T1k/TG4jYTsKemUwRDd1Nz9zUDVzdipmNW81bFpuX218TEJ0MjQxY0xkUXtP
aXQlMmJZfVhlIWlRKlcreWxTIzhyJmhGPEM7SHo3CnpIKzEodS1tVFd9bkxpZl82SWFmYmM2Vjs4
cE1SMWJpUkA+XmFQIy13R2Y0UypvI1lnS01ZU0tEQUpuUVJ0b296cgp6aiFhJE5BeTh2QSh1cEBY
e2ZJI0Akfk9QMzg+diZAd1Z0JChyWUtPbj19d2NJN0lCaiMqdjViNz1QaHxYO302SE4KejQxV08t
PW9NaU10NSFTZmotQ15hY0FGNFljKytXKE1UbnBFdlR3YGptY0pIS3c8KDtOek9zOWZZSio7Ylkl
RGUwCnpiP1RlcWVDbjZMbz1Dakokfil9fllqPWhucT1takhlREdvYVctcjt7aD98UHdpciQ1bm40
b0tHVCNRQUNaZV8lJgp6Q3xnd2ZxaGMtTzF4TEVQKSlYJHlaWlpRVTR4aSk+MkY3JT9GPSE+c1lz
eUpfK3RtaEAtVzJMbkJWJHImTF8oUzsKejxqJkJaeyQzSCpRVndmKmk4SHdIUEI5KkQrYitPM3A5
JHM2KX4hSiYrLSRzN2xUUTk7S1ghWV5tJC0xWmR5IzFxCnpUMD9KXk0yJE5YbVROaytsVDVXLS1A
fjV9NDImP0hwfEVHZyFkdypRdStOPjtqcUNicCQmSH1RZUApTEJMeU9YdAp6TXhNQkxjQjhoTDxq
NjI3T0JibFVvSEZ0OUNLUShsNGZOdVlOdm59SURpRFoydUQrY3tJXyVhezwqMitgTGFKdHUKengt
PEw8SHczb152aD5wcVJMd0dgODJ7cWRROUpIRD59UGxYe1MlWHw4RHNkUGlROX4oX3J2OztIPlZI
V0I5PX1sCnpDZj1vPF4tbkNadUdxLUJQKTVoK3d9fTRTKXpuKlRBfV9BZEkpcU5RUnxLUV5uanxl
RmdgZj8yUTNUJWdwPDNDagp6X19PXjdLUSR9WXBPJVkqeyQwKDxQT2J5aDQ7MWtLI2tOP2J5fExZ
WnRfJjIqd1YwV2FCNUpeNEhDbzh2TGRAKXMKejc0Mj9RYSZQZ2pFP1loVlMzT3M4NTx5c0EpRj0o
UyhiNDZVPnkoXml7T0o1K3ZKSC1KZG4zT082OWJWVjFpJkdiCnpBTSNnMVVwLXQlTEQjKTlqQ0Ft
YV4lMkFVK2teQDl6ZXdhaGhSSGw4VDk7aDRTV1p3b3F0bHNrZGckP0BgYiF1Mgp6VDBYY010QCl6
PWx5IzZge0FMe3hAWUNOP3g4d2l9an0jYj1sej4qVFYpWnpec2lTZkUtUCM3blJASGNCTEp9QU8K
ekk/YjFmKnsyQ3s/UWdoPXdmM3dePFp1SzxkayU+MHMoe3RKQCVgdmFHYGx+aXF+VVJZWV9EPGBW
KEVxRHN8b0xaCnpoKzZTIT05aVI4UGRVOCtIOXNQNlYqZiFscnIhO0Y8RzU1WG9ZITx1c28tQXBj
LVZ3RztqOXU9QlhYaWQzOyYlfQp6JmJuMjU0fXtzRmE9KDlsYFl1a3NOSH1uYW5+VWU7YCt+ZDlj
UmAhLVVDNz58aFQ3bHo1ck1xKTR0UGFAMnhWISEKekpuZCFPbVdsWX4+KVkpQkFGNDFWTmdNRXw8
YHZ2Z25iZFdJaio8eD0yI1p9am5TLUomaDQxP31XIUkhIyFxPEFVCnpQPGJvdWwoYXFiQW55czBj
JkpnRHtvVkZrYyZJNj9AbFU+WighYFRrU2Zse0J1YmJOQT14NXVmSHMxJkxFXkJ3cwp6RzxIMVBx
T2ZRY2BvTigwVihKZT5aYUR3cGEpWjFuTU1BR1dxYUJsUiQ9MiRoIXh4V01ITGE5MTRMZyYkbnJN
bCUKenVFO00tWUxVM3tVb3ltOGB2dDtzUlBoM3JxdXgyTTVNOSNyTGU9blVPTklOUGsleSpMe1oq
d0AlJGxQSUdtOSZSCnp7VjhPcGR8TWpjTkQwMDYkWkIjQk8hYms4VEJ3RnNyNDJrWUxFc2spMyFJ
NmAkcGZyfD5peSlpKEhUYDs5MGNuewp6QmJNdiY5LUVfPmErNm51O2FeSktefjRqeTw4PlVhdHcm
YmdNaDk/eylqTXhkSXlXZyNMejt2TllxNEchPFNkWUIKekNnfXRnVFVJLWE8IzIqQGUoe0Q9bTh4
VC16ZkNWV0l8NDsoTzhUfEB6djxRUmBUY0lAV0BkZldNIWExMFVvM1FOCnpNRT0wYDtvPW54R3h4
M1NpTER3ZTJneDhPNUFxKXZhJEEhcmJ8TDhAMnJmbyQ+JlRmOCNILTReNHk8RTFtU0o4aQp6TTUh
MGUhc0V9TE9MdkVFSkpWdjIoZ2UpdSE8IyQzeiltPTJQS3BmfXprYj9xN2QxTChOSio9fUx7OTJl
b3ZRR3QKem5yN1R9TUo5K3FuYWF2SytvZn1nNjY5Tm1LeEFndTdhd08pUmJxWVRzP1lZRTMqPVZE
aSN9VDNVN35tYSNsM1FHCno7PjVTTiM5RW5iPGltWUMwdEYzfiVsUHxAbHZZNjNfIUNwSkp4Sjgh
YkpjZ0tQMzBSfXUkd0A7SEU8VD9xcSpXdwp6JmlaaCopOG4qaXhTRWBUP0A7XnFYTkNDME07X2E3
NktyWjZpeUN+N1psTmIlQlIjIXRyRjJaI3FTOXQ3UkF8c04KejRfI2VPRT5OXlIrc1NvaTk3JXBk
V0hLSVZic313JVRYflJ1WWp0KSpDTUNLPl9IKDs0ND9kPlNKe1Y7b2B7UTI0CnojYjc3VmBVWUVN
QVBJSkg9SDgmKl8hYkJjZjl3LV5AXm1HZnsxKnd2V3xzTlF0SVdraDZILSZxZ3pSYTxyQ2hAfQp6
P0NNdlE+Myk1cU40Xmo5SkVDeCg4c041IVpUPSlAaHZjMilqWi00Um85Uml5YHglLWl2djZGdFUh
e0olJGopcG8KenNuMnwxSDV6RjdQUj19YG1DRHI7Z3dvR0pPezJ0P0VNQn44QT17KDBnc0M+fT1e
OE5VeEB4KlUtWjhLeXN6cSQzCnpZbE9mNnVaK2hTcXFKZj9pWE5TNGA1LUo5c3UheHJZUVdVMEB9
dGh9Vl47Y3cjaDFvSiUjWVluOFUoNUdeMSlKZwp6JTtSO01Ackl1fE0yJEhUR3swSlhzPHlGKlgw
YjRNaXtaMkJjZW1VbUN8MGlsVTkpdztxKEdmbyR9eD80Klg4c1MKenIyJmI/eXgtPFRVdXUlRj0q
b0ZIRjcqQ2RmQmR3Rl5UcEApemUmcUU4MWliJlRDcDtYMX07Zl5MPXNnayZ7VWVBCnppWDVPKTl6
dkdBRVFrdml7ZkZ9QlQqaX1CTl4mfkMrSnNqUF5OTCMyTlM/O090ZkVzMys4OWp5cEk9fT8qdFpG
Ygp6S0NUKXJzVCF7aUtYO309WmxRN2c0RDV1eD9xSWR2ZEM+OT1kSzE+Z3VJZiRmNG5nKVBeaS1s
RkcqYE11UT14fWsKejBXdDlERl5hO0I7cTVlTVNsVXV0PHJaKiVJUUEjYlFJblIzaDxAZ3tfTllg
ZUg3YURySlYrUSZzS2lKN3UyWjxaCnoxYE9MP0xgRTJ0aCNPcWNObXd8VCQlJSsqbS1XVzNXbzMw
U1N7JUd1OypVaV4hYEI5RE1HaH1uKXZFKDxfKT11Kgp6bHN8ak5acGAxaURFSmJKNmZnQHAlX0xA
cyZPJlh1VTlxZFpNaFdIO2BJa3FGMyZjU0ZmMWBJfEx2QihsdXhgcWwKendPaypGZ15LO0R1TFBG
a1Z8R3loUWFEa1pqNXc1NW9LVSYhd0BZSnZhbTlCVXlaPTNnY0VgUTQhQE4/IS1MXnYjCno7Mktq
fipTe1N1SDs3RHB8SXZacXgwT3d5bHo5QGgjKmJod2s0JHRpYG8wM25wPjRfYD13fnFIQ3A4QSYy
dEJmUgp6eWZUWn49bm08S1UoPjxWQ0ZuSlJ7TXVwN2I/czMkMT1KKkI3OCF5NmFzIzE+QXEwfFhO
JjFnOzZ3RDdkRjRrWnUKemxBQWskMm5ZQ24he3ktR3NQTEpPcCp2e2QzRHhyQlcpKkBucko7LSMy
flM9bEwwWFgmR2cpYjhXfWEwSnlOWSFnCnpnMnh1YndLeVVDMS02IWQqXjYxWkphSD1BV3Nlcmcw
MHdyXyQ+RHN9N3ppSnlAQDFDbWlBUkomazdsZkJNX01Bewp6MT8/eGU/TFV2YTh3O099bCExd2Ni
e2VTOG5KJkolY1pBQyVCeDc4PHp4Xik8dHd7ND9JdDNHYXhpVWl6UmMlLUsKeiZQLWh8X1B5WG4x
Z0klNXFtXzBGZVkxeHVxYiV+d3FHI0h4WH59Ml43al5gdGd7eiVJMT8/X0JEPDtPTFV7UGhSCnp1
aGYofnlAOHFSYGh3a0NeODFmRTNFQDR8e3wyLT82Q2s1VUpqdjc1Iz0/REFHb1U2fnU5TmImUm53
IUw1dUJ9KQp6YyQqOE1SdXZQSj03bih7UGhSRWtyMUY8JEV4RGUxZmwhOy1UcHhmIyp1WWB0VE1V
NG5qazJYdiQoKkgrM3tsd0gKeiUhKj52IT1hMXUhKiVoJXBJNCpkRyhoNCgkaG9VZihDc183TEdL
QXNySzx9djsmM1R8cTQlNU5VZD1LI21kP3g0CnpoY0RPKEVuVTRBWXFASGV6Y3hAWF4wWilWSnZ5
JWBDT29FX0ZWVGRiaDtxc1plSnYpakgkRT0qTGReakNIXmJyNQp6N0J5KHtrPWQ5JVlMP2NGK0w1
cEhRUUA1OHZvfmshR04zVEdUemJAJnFpPTlXPCsrWFNWLU44UyZrTisrQUhnST4KelVTPV9KUlUk
WDg2OTxfSnNBODZpa051Mi1OP3VJSClsbj9lPTl1X3EtTjFuZHVYN3JZTF40MEdWdW8yNmIwbioo
Cno8aUt1PEdxezMjSHp9VyRPTT5Faj98eGhEMUNyM2hndHZSM0lYUSMxJFJSSGtnN3QzXmgwc2tH
OFhOQGZgNj5wJgp6Y1N0TUlOWkpPRV99YHptRSZURyY5PDVSe1FiRyFuKFZVMFdJbn5MRmRLNnpq
MmMpZ0pJPz13ej53YUJ6emYkM2UKeklhRGNVTEBxIWYpUEAjPk9pWllpUSt+Xmp2OEBZXnBDKilS
IV44PFNjOCNJSGFAdykhPndzZHR5elhQZ2gkcXhzCnpeZHhYOW0+fVVONE1yQksyfT13Vy1GUElw
WjRJV2U2KFUqRW5aR35VbnAtaTBxd3lyN3Q2cT9sJjFMaUozKXEhLQp6NjA9PkM1MDAmSyUyUiNs
bllxa3BFTD1tQzZFKiNRP1FldVZeTUdNdiVFSFdqRSlsMlo4bVE7I2lSNFNhXkltXy0KekRJOHAh
NjRaezJSdnQ1KGwzejdtOSR6YjMhPmBYRHZKenhwOEFMR2BgUDRgRHNaVWdsVWdtY353dEsjc0Zq
MVRRCnp3d2UtMlJmdCs1NVNFd1BwWFFld0FjayZhN2cqRDU2O19CMD1OanxUSDVwM0JuUUpuZVc7
JT9hZGRqbjZANWA8Ygp6a3xpfDskMUFiNEIkSmJlPilyOSh2QDh+cDRTPX40cGtNYkBaayZqUlF+
Mn1FNz05dEZeOFVQZXRNKnFNdWZaPmsKel40OH1UZyEpQXpfTnU4OWU+akl7RVYqeXRpVHlrakdj
Z2tzckFUWjRWKmkjdSU8PUVfdzVlZmRUQiFeI1YmJF43CnpWT21hOyh6V1Q5aHUjKXxqQGptZnBE
Q0VeYlZCVzFIM097QClwcXRqYEZ3PmwyO3U3S2p3RTJRPVBiS0lPc3NfYwp6Q3ZBeTFKS1poUFUx
MyZAQTtaWiUhezEzN15eMy14RSpsa0QlQVFSQXMyKjBNQz5nWGY+Tyg1T0woNF9UNTxFfnUKekg+
dzFxdjIlYiZnRjUoRGZwdVgrU0NCLUY5MU4ydUpQaWplWmlDVjAmeTFOQXpOcyomQiR5WG9USHpD
fDMrZD1QCnohVEJ1N2ZaJVdNS1R9UDBJd0V+dFFgOXFaZmcoPjJkYTI7fD42IUdDZylpYzVrKipS
KjlFc05YOGU/OTdFVUJQcgp6d1N3d28qZjZzZ0A5clklOV58XmNgbC0tVDtQVFl6MnNwWUYpeXst
JSRAfGdDJCM2I3lRR1F1N21VOWJWUWcoT2AKemJyTU5SNT9gKjwqJGkqSFhibCF3bT1rNzYxPTJG
byVBamZtZmNAaWdeKlIqN2lFcWc0VjN9bCFhX09gRyE2TiZSCno1PyNPRGM1ODRqMDRRT2JKOGk2
MC1uXmdUejtEZitLRW9AYTFUQ3pMdkV0c2tiVEUweTgwUmNJdDJ5Tjxpd2Y2TAp6anRJd0I2TTNv
Xlg+d2ZoVkBDfmhyYUhlR3FhKH1IV3RHXjZWMn16SjYocDdNKXtFVXN5QFUkfmZIQ3wydGpeOGUK
entOeUxXPylyVWxIT0FDJFM5eEB2ey04bmhnRnkwdkVpbGJyVGkyQ3JjMj47VW1fQVZ8aXtlY3py
ektSLWdGZXc1Cnoodz43ZkxqWG9gX3JYSmJmaX10RGc2ayY1RSsmbEZiLWxNcSZRNzI7dWNyIUdn
NHZeY182TDw2aHdUMz0mcGJyNgp6eWFxaFlzK3FWU3FfQTtoRFFNfEBFNTFeS21ialBwUF5TP0x2
QXYpRDcrVURrWDhNdzgzJkJkMTE7bUktVnlGRUwKensqSEV6Ky11ZzBVSH5vVTM8d1gwSH00S2NL
KVhQT3tjTUA9QnRiQDU9VWxuN2A9JEs3PDBuVkJgP2RsbyZJV1RjCnppfDR6dmwkeWp7SiV4VlRg
fEJHZDV9MSVKTnF0dDUpeE4oQCp5eU5WbX49ZkYxU040V0dGLUBPQVd9aVYoRmhjOwp6Um5gdj0x
ZHlDb0d5TWlFNk1iJktFbExkcDltS0JsSFRiUExxaElAYzwpVzc2UHFhUiZySVgrc09qMU5WUnE2
eDcKeiNxTGlDdkEzS2lUK314LSZCXnZ9PmNXWlVFSmNRZytjfEooYkZ7dElVZUpkMW9hVGxRUGI3
eVF4PSN3ZHpobndICnpjTiltUCtKbTlSJFRpQUxiJClZWTZrP1p+Wnd0a3JAODIqTmskNz8hbCRx
TjBaK1NZRz1qVlNrJXBVK21iTShVLQp6YmViOShUJGhoKns4Z0UoZ14mWCV3QmFSajRYaFJfZ2w7
Qm1hKChhUnt3fX5uJVpELTAodnBYJlUmbz17QTh3XnUKeldqWDdoZWpMZVZaai10QkVXZnwwJVBU
N2A2SGg5NkxwKUpgQ1E5IWNgUEQ/dT5OJUstPmB4aFBCdkx7TVlHSllDCnpQbWRmWCtIYU9AYT5Y
ZThAaSh1PWE5UGJfQj85Klg7XislT1kjcn1sTTMrQXxQeEFPMFZraGwmVH5xN3BMM1FHJgp6bXIo
dGs3b01BNUA2b3IoeXxHYSlXc2EhQXZUciFva2dKZkIlPnx4RTF6enFKazVATk49PGdLKjslby03
YCQ/Un0KeiRgVzxuYzd3dEtVc2AhQEt2T0ZaU1ZEIT5Ocyo+a2t1MmhDWWlxe3d3NVhUUjtRITxw
PCtra0l0dypacU9fXj9oCnpHN3x5Q0ZeNkNscndOa09DY0UjNWJ1UT5LS1RLU3dRb0NZKSpAeTdi
Q3pjJTVXbiMlbCs8OExjQVp6bU5kY3FWRQp6Q204IStjcWchUUEoUkNvI1dAbEB0RG44X3pmVjd5
bC0pfCZweEx9NDw0ZDMrbGRCZW1HJU41c2BrV1JpbXVeaXYKemUtc1UpUz5BO2dEKjkyP3luVCV8
bU1LdDhVRkJOdzN0SUd5OFpKMjA/aEI+SCptS3x8U3hZQTcxPyFJUnFZfUwtCno2MUB2WSpYdipQ
XzRqVkxUJjg0WTlmdmMjVkRkQGNvdmI9MUMjVV9fbn45Znk5TiU3K1klR0M/YEpmT1FFYFZJRQp6
STtINlFZcn1pMS1PaiRsd3FUPCYoQHFGWG9RPCRYY3NORkljWkltYFQtLSgxZCo/fSM3RVlsfUVq
aE9XeDNqdWgKemljWi0qQT9XRz08VDYlVUxARV4+ZXEkNWlEPl5HI3p7V00yIW5TaHpveH1mcEVs
bGZAaGdjel8qJlc8QEpNKmNqCnpZZD1HYERffHNIQW1BdilkXyNWOUMqMj9gSlomSX5AV0Q3Pit5
VjRaUiRqRnsyeV8yVGYmVGYrY3VCST5gSSQ1NQp6OzNVeE4xUWNqOW5JbzF6QDVjPTQ4aytxWj9q
SE1lYjE9bHd3UWNTRXgtWmI+YCQ+MzsrX2hkVDhGbyR6eVY7Py0KejwyPjdZJjM4ZmY8Pmg3Q0tw
P2lAIUFDU0tPel99V05sOTF+dmAyPm0rOT5rP3A7fTlqcHdxbjlqe0Y+LTJKVSROCnpRWFIwLUB2
IXpIQGI+bSo1c2wqPzEwSGYwNm0rT09LMDRBUXRteFE7bFlrdD5MRmkrNTJKd04pKy1JTX5nanBv
Tgp6bjsld25KfDkxPDExQUdPdmtNIzVfNDheJF9ZUUY2bFItKnlNLX1kXkJfI147Um1Md0hmeks1
MGtmUHRAZUVkJTsKej19RTtqcVBrJHotdExiMzQyTy1VJSNHSzVYWVkma0xgey0lalpVQGg5VSo5
UWZYKTc3dTQmaDFGeHZWe0E/VXFGCnpxSlIyZDZoJCF1RkpicTlXKERYbjFvWk5wdFpVLWdtcTdR
KWl6VWdGOGsoRjBod0ledEw3KHI5VG45JEt5PjRNUwp6K2w3UHZfQ2poQDRwdnc3OW1YWnpXKjAh
MCNSNns9YjNeMjkrZ0ZzeEc0MiFGRVo7P1FJJmNvTXBuQGc/cDRPMDcKemNSX3dFX31ecjF2PTEx
RlJFezFpKDh5SDdjJU1gQHZBLS0xaUM9azdpciQ8JEw9RTUkK0pjNnxoWX5qezhkXkkjCnp2WGZj
ai1uU1VVdWlfc315d15OQUkxeEA+ayt5QndyaWx+cUtKfUpZYFIpQSY+ZXJvc2ZCO3tIM0h3VUU/
Tm40VAp6d3M3ZXpjUXFDI0tSLVd2aHhzZj5pPXAkfDI7b2U/K3ZuTnwmfU5DdD9HelgtODJyJXIo
MkBGallTWjt0P3FtcEAKeldZU2YodCgrQnVlO2YlYVg7QzZ6cG9YI3ZeJDhZPUlBaVo0WW1TJTho
MGM1THVJTEAyKnh1bztnO15uY1VldTdSCnphRjM0SEo+NVh0KitFcyU+Y1lhdCpHaHVRaFEyMUU4
KHg3NGdZc1pYP1ZKNihCOzlPfThQaGVkbSZ4fU1FJkhGLQp6Q1Y+aTBNNTQ+P0U+dnEwY31YUGdK
RnpQZ2NrQGpoUHUyeyVacjUxQ1pOZGEqUz8pMUlLQkQ4SD9qIW9mdCEtX0YKeis1WHBNNmtTKD8w
Pilra1loQk8lTHw1dmNpYjBeVS1CbG5oJHVRd3tKSCZJcl8raHYmJmZqR3ljMEtoJjZySFJRCno0
ZlBieXRFZ0JgcFBYVzdiO0VwRldvMys5KVExaUNkbSk/bXItIWNoNGlIUH5DP3tNWU1ESl9KQU5o
M3Y0dktVMAp6bWcrKF49KE9oSGU3KW1rK29ERjFZJCUyLU5JS3VZY1p6NCEmUy1SN1I+Y2hjP0Nn
eHk9Kzk8VnFQb34hYE5xcS0KemNQR3pSKGhKU1o2Wkp0eSsqIXI+JiQ4VWswVmc2PXs8cVUlOHl5
WXtJVl8pd0VJTV97eDNXbU47MUhDKkY1RW9TCnpHb3MzcDZuSWJBUipxUUopO0FIQk1TV212enBJ
fkJkbW5zJT4pTG83TiF3e0h1RnJXX09tbCtPcU9HIXBhY2QjVgp6ZWNmZUhaQFpoJS1UMzJxKCYh
Tk88QSlrWT5ab3VlYihUQTBrJnojJWgtI1dzXn5rSWR1V1RtZmIlQzYkTG5UVGQKemBnZHMpVkck
N3V7WkB+cUlNZGhkaEs7QTApWHJPJUF9emJ1KCtacnhrUnw0bl8qVmU1QDZ5MygxLU8yYjt8fF5h
Cno+KyQ7Zk0tRytgUThxZnYkJk1XK0xrMjZIQEZZa3lqMGt5eS14U20/KGtuVFpjdTI4e3I7RFNY
S0ZfPihHVypvZQp6NklsKmhhcXIkZDg3TD9XXis3ayY/MCRGcjhUNUtyNGNaZzhSQUN4PGliMSFw
USt+d3crRDdzKEVmYXhyNVBRaD0KemUyMyF3QGZlQlI9V0BIVjZMTiF5aCZXbExHZ3xKQDtIUTh1
Klk2dExmUWJfcDlffDB6UXJzeGNNdkVqd1J5WiMmCnpYXj09MjgkUSVya3cyNG87czduUHdZOE56
TCFrTn5zS0heZj4hZEZDP1IxfEt4b2tmNi0jTCtkQkN6aGhIfWVkVQp6R2JMYVFLIzJAbnotYSQr
MEQ+R21ITFpFQWxzVD5Wc1dZWHIzPyt7aVN3bVl0bCprbTtUKik1dlBMXmVkIUQhaHgKejRUdzFi
KDxFclpUOUtfPnRAIVgjQW5aYE1DOyFlUzRNczs2e09kX0ohXllpK1FJMFBFbit3U0sjV35jPSVL
Qzg1CnpufSUwRkY+MXNPdThIT2cyez1acSpNWE9rdGtsNSpwRlpFNilPQj1wbkImVnFufTNYfUdo
M2NwI2J5PWhFJE5WOQp6MzRpMXApPjxqbWU7djt0KEhROzg8NFFJfU9VSnhweVBMRDBiVH5BX0R5
PX4rVGBTMFdvIzhKUFomT0I7WTRyZ28Kei1YbndhMEtROUwreWFtfEVqWnt7b0V2Nj8keFV5NSUw
VVYzZyNRMUE9dm5tRmNSbHtVITRLI3cyR0NZKmZSZGI9CktZP1pXR0BjI2tiY2BCUiQKCmxpdGVy
YWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTUxMi5w
bmcgYi9hcHAvcmVzL2VjbGlwc2UtbWFyay01MTIucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0Cmlu
ZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmVkNjhkNzEzYTgy
NzVmNGVjZmE5NjYxNzQ4OTQxYTkwYzBmOTQwZDcKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDIz
ODkwCnpjbVhWMTF5b2VlX2tYKH0tUUJVJmlYZXp8JDBDUnpwcDs0fS1RQmAyQWV8ekooeEhIO3Ep
NH08Zip7PWBDRFBLZAp6fEthPWxwUikodmQyaTt2bzFjNTwmYiVte2ApWl5fT2hnYV9rPXw4REol
QXVNeFAoSWxjO01lWi17RGdUR0dWLW4KelFxdUZ5KnFyZShmM2pTUXgza0tePk5HTEI3bnxBMHNW
TDYqeEFBKGVCQygqTG1GR0xmK159Q0ZiKGpZbCFMUXEjCno/c2RJU2otUHNNKG1QOCpsPzEpREIk
d0hKWlJORTc9YDZ5cmk7Tkh6QWxHYlFeIT9Zej8hJlYrbllva3JvREojNwp6JGpHOUskZ3JDamFJ
dSNGMU9KTlB3OyYyaU5fYEdJMiFZNVdgVVdZWVA8cGAoNUUjSHVmZGYlZT5SeCpXYVVjLUkKemlY
OyNVZ2AkbzgtPXc+TSNzZFQtajV1ayEzejRYWU9TO1hVJnMmazRAc25na01uMT9UJnd2en1rQmlB
Tj1GVUZDCno3MUBxXjUwPnhZO3daWF9LKkZSbGo0KlgoM0ZqfHp5UU9AT0E2R2xNOUc7eHI+RU9D
bUQpOWFPQlZGVFNncDl0dgp6bXRDNGN7c3g3b1J3KjgyRzhSYD9HQ18zd0lJOytyRm9ifjtSfHlZ
TnFKZjclQ052I0Vwez9fO3hieD9iY0xTM0sKeiQ2ZFpZQHxWNW9HcXR1Vz13dWBHY3YjJFQ/PkU2
QVpwZ1E/U0M0QjlSbjhEUT04RCgmO0tEZCVCK3RkTHQ1SkxuCnpMWEY0MCF8XmtsND99fG9sNj9p
bGJxJGlPXj55dU9efX52aEl5QUl0MTxMeVJ3ck9OcWBuaCZZZFYtOUAyZCQtYgp6V0tDVkRXUFQr
STR1WU9tNih0JUAwdF87ZUxYfFNGNzFFX0s3aVFweSMjMnYlO29TfGY2bUJ0M3U4WU85TlN9QiUK
emAjXnRsZHwrVnNjcmMyTzYrNmg3ZVdFRm1xe0tuU0EtPHpPZ30jPlRLbXdpYyFPT0BwZXl9JGtX
JGlDMCRvYm9ECnpeaztnNjFoQFAha199MmsrXkRMXnorQCE4T3RlQilrZmBlQjZxNXt+XnJsSmhh
SmEjWE1CQmo2UjswflZSN3BmKgp6aE9XfWokeEd7P2NqZmlxNFNEbz4yWVl7fSV2Z2RZTUk+MVUx
SG9QLWo2Kj5hYSlkdEpGZjglQlR0XjM/ZUsrRFcKeilnc3orck9KSnVKd351ZWE4blV9dnZBfEtX
R3YzM3NXVjA3ZUcqWnAoITlnPGdZTEVfRlNWdzFyTS1DaXNNS0htCno/QHYwdkgyQUhMMzg4JlBL
UnBXSzRwcWVNOEhEJDg7JGZ6NTtnc1EmJT59TXpKflIrOGFmPmJPXjNmRWZOfmhRVQp6X0c4ZU5Y
NGk8TkxjayszRTBSQitnRnlKTHJ0cCY9V2t2JFI9PmwjYVhEV3NfLUl7T3R2YCZ3ZSlHdmdgTDJX
cE4KenpRTnhHP355PGdSYDdZcXltfGt0T3JmQXotOUp4cz5HblQkUVNzfF5haCFCPDIofD4zQTwx
NDxseFBNclN+JEowCnolOzxCT2t6bTspIVNvRWFxZV9wSnBYa0hSYlFmY3cxQTxeS29KWnxZcTct
RzFfR3ZzbW8zSHNWMlc7VEZ1XkF2fAp6RDxDZEs3bG9qVDskWEEhPHcwbks0TytoRnZrbzF4NCgr
cF5uJX1MI2RNckxGbG4rYD9GPzNjSEEkWlh1Z35SdzEKelFxTntvKVNuc15BSXElMWAyOXhrTnAm
X2U1dVA/LWdtU3A2V0dwSSNHYkl3cXtLTlhUcWQycHBjZkVEeClhekpnCnppOT9zX15CcHhJKEZC
KCo5MTJfcyU2RE5mNGxpK05nant4fjx1YHFIJj16ckU7Tnx8fVYzNzxCNWY+R2lNfVJ6fgp6WmFo
SDxebF5sIXpNVSs2V15sdEAxez04ZXdvdGF0Y1h6UTVmfiZfOTRaeG0zbEVRRWRLUXk5SHZ4fFJ3
P24mTD4KelV5Mz17UHAoTDBtQCszKSNBY0o0YWB9fkleMVEzMGQ5e3BhSyp+a2NCTSlvMjt+fSVA
RGpHJEZCcWREVz0wam9WCnp4ZDtyP3pJX3puKztBQkZ1LWI5KnhnVX14aTxKbkVrfU9RPlo5LSZH
M3JoRkpoXyNCQjdjQzNmKzF9bFUxK3R6JAp6YWdPOSUlOGt3ZTdpQiUwXyY2PDFxKE9eNUteeDQ1
dGN8RGJWc29VfExoPG8mbHUoRzUlNDJzPnM1QTQqMl8xY3QKellZe1V8WnMrZiFuKE1HVzxnIWxY
TXlEOzUhR1hgOVZAWjV5dGgmaTw8ZCVjSGFpOXY0Q1RubmVUVFBUbig5O0JrCnpAYE9HYStfMjlP
RTFURzQqTG93bEZoK2lITGFxJkNBYzJjd1ZDTGt2cGAqU3JeIUFSPSsjYFB2QnV4aEc4dTw+agp6
MDtPJmc2QTReaktZbj9pVVo3I35ZeGRrQjheb1R9ZygmaFJmcUorUWIhLT1OWUpCSFFnVSFZPkxt
VHlGJXxDXzAKeitaVTlfUjhnbyQ9MDFgLU9QPlpFaVhBU2BDVnJhdWMzR0wjSjh+cns8PlpsPEp5
P2gzKnBDJEpZYmpoX2VtMnx1Cnp5TE1fWCV1c2dpNmVuWF40Vyh5fHRFQXxxQzA2ez0wWVIhb048
TXFJcE00cUJufHomQmVNP058Q0JHUS0ySiRVIQp6VWE4fFVZXlhrdTQ/PiRPSF93clc7VipDXl8j
S2tDYjM0fmpUM1JGaERtSCFSbXlQNy1mQWtAX3E4NlU7OC1mcjQKemxwJjtXPG9eQlFYeGhXYyNe
O0Q5JFNrez9GYklXOD45RFZBVGxaZVNTLTI1WllFcG05WE9rVXg9blZ6dzRhfncqCnpYck5mPVB0
KW8wanM4cDlpJk9TJVhFOz9zJkRyZjIwTVJ1bGFFQiF3PH5ebGszYm5GTkwkTjFJK3U1KnpJM2g7
VQp6cUdVK3RWczs5Kz4rakppPVJhSFBDKG04OWd+dEJ5QXJNZkgxITt8KGJJdFR0N3V0MC0hNmkh
cDltSmR6THklSkMKelA3ZEtndnJuNCNGUnI7WEFGS29kKFBFb1I2UzdhRUI1aVMlRDhQRmJKbkpT
YFNaezRsWDNxcDFKeURPeE9Xdz9hCnpGUzlAYm5WRmUhRzBsNWI0d0YrO15rQEc1SmtBP0BoJj02
UVJnVmB3OVBrNCpIbEpRX3EzaDw+Si15K2A/PD18YAp6dSQrfC1YYSV2JHY3PyF6a01kQDdGUGx1
K157TzBJU1NUczJVYmRRSng7QipKRHlANEs5ZV9YQ15lZHBMZHRGfkMKeik/Un1zRi1LfjElfnJE
eExkfT12WDQkMTNiRWB0MFN8SVUtME94WThvIUx9bF4lfEI0YXpBMnE7aXwxU3BBaFlICnpDeFdP
anJ9cT8mLVY7a1dQNUs3N18jfWo+VCV1NlBnejBeRiltX3g9R0h6fDsqZ1o3YjRfQT43USgrYHBV
PH05OQp6UiNzTjdlPjZNcXtoWE87VnojeGw2Xj07bEk4I0JQdUpKUFI0M0NjSG1FPk5NbFZne0pz
LS1nZlhPTipMKkUqRXgKejZSKFo+JW13PEteVXkhdnQqLWFweW1Zcnc8NGFjbjYyJjJJdG8+YT5v
dDRhX24pdm8jWWN7RU1VJmUqTER2emFuCnpjKSQpVHg/REJHTip6PTtVbW1ENSV7SGw9b31USX5t
UFNOSU1rakwrMEdWOTxqTTtCQ29vKk5rKWF8czlBe1Rtcwp6LT9LcFdUZVRZe1FyZyhGeDdkUmR8
TWFzOSs1bE82MWZuOztfeiVCdFc3VElIbGpGQlNDTyRKPj48QjswKX0pOFUKenUkSTc4cnxMZXh0
QFlLKj42cjxXcERJVUdsKUNhMHRZcDNwNGd2UzJIczlUQSFzYjdqeUViNkJtaTluRDhySEhPCnol
SXFTKUlGZjFfU1d7UihNSF9gOEc5a2FKSC1PJDtHT012YGBTRz4/ejZKIUg7JGRjJCRDOUhUNUpS
KWZPJFZEeAp6dndqO2gzV3VJdlFaPyE5bCQ1a2RCbGNte0NFX0EzdmtmPTR7QzFrPzZPQ2A9YTN9
dlZnfGFPNyZHd3BTR0JYezQKekpAaX5iaWtabllgRCpxM3djTmlNaGhgNH1OSVRhLVRJVzMjV1VT
RCVqdnBjOTd0b199SE5yXjFWOWcodElTXkVDCnpMfj9iYmRkXyZTQEpVbV5jViVjeGRDWmVUZ0E8
WjtJVTk3XkgrI1BPVWFkfjEtZUxTYUR6YSN0VFNjKk9YfmZWcAp6PXkjWElnKmduZSQjcG10P089
bjd3fUNQemdmM1Q0KWNtRkVPO2A/cl5GRWBFPUBeKEFkM2RvR0JaT1ZnM2ZPdX0Kem17VF8oN01T
I200RW9CSzxAQFp7THV9QSMhaTxURFk1I3hZPjchNXNHY3ltKmg4NDFXa0lUe0w3RFVtJDlXQnBE
CnpwI3VHbjIzNkQ4e1dHPmRvMTNoQzdnd3o0eS0/dmllJT5mWmUha2JMQVlmQUdERkF1b0khdlpN
bjxnRVlLUlFibgp6bDNZRVheWS16flRISF9oNFpqRH12bW5ieC1yIVlMRCFjYm5Pe2xjQSlKNjNy
dDdfVCE5UzgtSHJXKDhNa19YRGsKejc1K08mblFxZW4pZ0E8OHxCUjUmLWFmdHxSUXMwfkkpR2ol
a0JKKFdVeFQqYVhQXkJGR3I5OFcmR3FIckt1fHxvCnp1R2h0OVpMeFdKZHp5T3BncWhWYVY1JGVp
TkRWYlhqOSNmfXQ1YntGV2dDUCpmbjhWJEBKYnxDVDB3NG9KQFhUQgp6cjt9YTV4a2Y4a3dDenZL
R2VZUktPfTROMV5iTWlMUS0hODEoLTtLKGgmMl9jT3V0O08yJHtgZCtoO0NxSzIqP18Kekl+Y309
VU1yOGAoc1hldmhSJHVmKVh4OWRYV0xxSFI3aV9COzZkY018TXJ5OWVQVnt+JiZRcmwoZmBAbEBQ
WD9QCnpLaG5NeDNrP1M/RkE0PklBNnZFOTJqOzAqLXJtbnxGNVFtb05KVmReQlNUSzBGZndSRiFW
SkIxOSlFYikoS01TUgp6OWdQNHJhSWIlV3w2byk3I2gtMW52emFqRCZVMWAxOXlJanB7a2A8THAj
OUhoJiprTHI+SnYqLURGWjw4Q0AjKmMKenUyPUo0JjgqJUkrfV5CeTA9KiY5em44bExmSUY+VUAt
bz9NWXFzaTRfVTBqZ2ZzfThYLXVaVUpNY0F7U0gtNEpuCnpuQGVDQ0Ika3hwQWojJl88PGc5cXNp
Xj1xYFpHPk1wMnBKQSsyR1dhTjJfNzg9Z0N7LXopS3VyTj1WYkM7b3FKOAp6QEI/Ty1nTS10V0B2
RTMoKEhhXzw4ajRBZmV+ZXY5JT9feUxOUVY8cUxKYlBfT1khTCFMMS0wT0hsZGF3WTdrN08Kemg/
an5qPl96cTRUbEZyQXV0VEVtQk5qfkJNdzRIay1GQ3g0em5SUlczfnRHeDhlbVk5TXBhWilkYCpw
fGUyNGYqCnopXzNrVTFvc1FyZE0teF4qJlh+RGlNeD9uVDJ1TFJ0WlBMWjxQcSY1KFNJa1dGSCZ3
OG8/Qzg9ZW07T21QVy1vPwp6PDNWR2U9anU7QlVSPD1eOG5oS24oN3k3KmhQKil9SmIzPD94dWta
QjJtPHQ2biY2bXxwWGxAYlp6Yl8xSF9rM0QKelcjeEUpK1U8Nlo0c3NoQ0okQ2M0WEtUMzclNXp5
OEZtVGwrTEgyWTs1IzZrJT56bCg0ZH1EenxSWXtubE96dzBpCnp5UDM0KlJsQDJJOzF5anlyNTlV
MEUpQSFEbiFVRnRPLVMmO05DZHhoOXh8YHxnUmFjaEh8bjRET0l0RmdhRWpqYgp6e3BHI1ptJlV0
NHREZGpkT1ByallVallmfjQzencqN1o7MWFkfWRHTkFeSWRhUTUkendzSk99UldLNWR+UG89VkwK
eiE4SlpSOGFWekpQKyNHT3ckPlYmbF47dCZAeTdDb0gqcWkmRiYhQmpxYjJwPjVocHdkZ3RUeipD
MWc8Z1hnfHxQCno7UHNGJCN1eUx0PVZQaHliQUtkX15vI2xuTj1pIUJIfHBGV3UxTHxQc2hET2pE
b25BbG9PVEtQS1B1X3MmVUk8bwp6bXItQ0BITUc2bVJwKyhRb2JueHp4UH5kZEJKbWhXbGgmej8x
cV4/UHh8Ml4zcF5SXks2ejZiWEllckVIbjsrNzEKem5QQG5QSHNeU2c5fDRqIXpZQWJQe1B+dyVj
U3grKF91THA0big3O3lsYXloSnt9R0tzTmNzOCNVRzR6QHE5QlZ7CnpMMnVWPl9neXBwZXo+JVhm
UUIyWUp2K3dXPWxfNzZsVjIpd0w+P0w1IzFncCs2RDRqIT0wV3FSPGVFZ2BBJCtQZQp6YjBBSVct
YSN3fjFMTjhxJjdyWkRtTTA5YjJ7SzR1TmNMPF89dFlQVTQqM3lxZk1pQ2tBcXBacVFYeiU/XlZP
SGoKekNoJHJ8PS1YRjhyKyQjYl5LXzdmLXwyeXU+Y3tGSmFrR0QtTyR7OWtOaGAqeSFJLX1hcj4q
NG8yX3Z9SlI5N2dtCnowSnwlY1VlY2x2UHErSWQwPUshTExxfERoYVU4e2l1YldmeV5lY3NFQWtI
VkVoXz47c1VRPVAraWBMTmZka0dmKQp6U0tKYXJ3NXlAPWJhJnBNZiEtI2w8NTNodTVlYio9RXw8
YnY2e1JNbEkyPHE2RXYjPXFsQldLYkNtIXQhaUE1VjMKej1PNyVDd2R6V15TamVLVkNxSVcpalNz
ODdrOCU+aklHJl9LZSp4YyYzbHUmVlRwKUxic1l9QW1lNnxfOGZCa0JpCnpBYj9oNndpYFMmMWVo
fEQpaCRgbjBuZkpWaUBURH4lRSRqKkpzXyRtPDVkKWdXMHF6bD1BPmYyVXM2JDBFKm8lRAp6d05e
LV5XYHFtO0J+NlRqJXJgYTtHVDhga1VvRiNAQThAay1teVlAMU1SUHpUQi1rIXFfdjM3VXJQWC1p
SUdWTkYKek89ckIydSteVD9UUmRvXipYSzFtYjQtV0dhfFlueyhpOSpvLVpNM0c3bDBnaTZKRUpO
WXI2KyopTiFjV3xOcGV5CnptWldoO1BLflF3MT1vZk9gVVhOK2RnKjJOdzZBUXxUfmVTU1B0M0Qm
aFA9VUBrZGNwdUhsQl9jTypyTnQ3YXZ7OAp6TDh0eDNAMyNVX15aOUAlWH1RdCMtYXUqNFpFXzZI
T2ppI1FgbSpJSCRJckM5YkxBOEE5blcrZnJeK3ZvbWNyeTUKenVPTT9XZD0tenkzYGlhNSlEU0VQ
YjlIUlZoPWshQk8tSGk8e2wzYXN5eC1tSGV1OD1vV3Y5K2Y3MV8wZi07QkxICnp2LV5wb0UmJjtf
b2gpJWhiWGQ1Qm1oNnZUbmVYSj9oQlZifiZBKEl5ZDA4QzBvNVVIO2tafD9wdzdrc0FgTSp+bAp6
cGJYfVple345Jk9vI208Z010LXB0enxwXllqT35QN3NKcjU7KEt5JWlpOGdHbUF6Jl9Fc1hRSyRZ
UnUqPWV0Xk4KelM3fSh3Jk5wZ3BVc34wfTteTVNeNGAzVkphMm5OTSNFaz1PKjxGKyVxKjZTV2VJ
RjhUSmZIcVBMYEIkdGNAPCpzCnpQfEJTZkxRTnUhY0Nxa3h3Mi10PHdSVmFYOFRKWndsTFl3Njkx
T2VrLWNkc0RNNi1VPGtsKzxeUTtGMnpafihkcwp6OzBoam1kQSlteDBDUzVlTDJEaWtgWUA8NDk+
QzQrRiQoSWBZbkk1UWd6am5+MSoxUDxSSVdOUFZmcDwwJCo1O0UKenp0JmJpIzZ0dVFxbzJ4ZTZm
WjhZe3JCdVdsODhxMl5JVk52Sn1ELSNfbyNwZ2lVbTFTdVFDc0xVNSpnSSYybzRpCnp2aERVeSpg
WWBwSFB7MUU9KXUlVlc/eXZNZT5sPmlzSF5BcnNRTFoxPnYkTndZRFY/SXpgJVN4e2t5d1Vrd3x2
MQp6bHIzZkA4fj1NNFRxPHQjZ1UrYlcrVVFlSERQOWpqajh2X0FRSExZbWkkTDxWXn0yOWhTKHcm
UFZqe0pVQ0Y3dGsKejN2alA7QFlrMVFLXi1eUG9NMXRuQT1zUWtXREs5UDdxb2lqazUxQkZFPHhz
ejlUdnYwIzNEc3BCfWA9amxXNzlJCnpiMUhGM24hUk1ee2hFeVhrez15Nzc+Q31Eck9XTjI7MT9H
Y1l4X3N9ck9vNilYb2NzMmZvb2Z2c3ZIeW93b2EmSgp6NFNvRj03RWdzOTc/VFEqR31BcHBRMk4q
dnpoMTFTKUdod09PVT1aQEclJjd7NU1DIWU+QFR9aEMjUnd7JU1uP1cKejZrQiVoJktwJm5BOXlO
ekFDWVlXOGY2UzUhY21DV2tmKmxSaUh8ZyQ1MiZ4ZmtgaVQwKk8+SDdASTUobD9JMkl2CnowblFD
M3NeYWpQMHp8PWViejchcSNuQ1VvPCVoXjNxTDY0M3tqb2Q0IyllTn4+THc9PjhuYio2IUNSbXpJ
eSF1Mgp6Xk11KTspUCRKcmVnQEpidHl0K2teOFJtMGg9Snlqbl9Ve3c3TEl6ZDMwbmZRTWNOYkx5
NyQrIzt6KFUoT29XLWEKellxWUZ+OFR3cStzYVRRLSQkQUpQRU1KVXB6KXBBT1BePnpsWXZtMDhZ
fmxYMGE1PWgmRVM7UzFCTDd+Klg2YURXCnpEPVReOFU5OD52SG8jMlNuak0pZCNIUH1tZ2kmfkBz
MXYwIT1vT2g0YDZqMmBUdiQ8PEFAPzMhej8jX0Q4PXVBQwp6MkRxP3l1KXBkSmN1M0JCPmIyUz9M
aihna1RxUGR7SlJ4T3dgLSZiKilQNTFLWG83dik0OzU+dUU/blBYalA2ZiUKemRYYn1UOGo8UyNu
IzlHMXJlcm1VTSVCJW84cSFfQ1c0P1NkRDlFN1RQbSpUclRvWHJFcWlKMkUqO0RHPi1pMX5ACnpG
b00/IUt8Qm4+Ym4oZ3dCcEokLVlaVzEqPkolRnxAe1N9WTE1OU1PVm9adC0rPnV8XjNFVHYkbzlv
NVhOdTNMKwp6b2VQUGJRPm9ic2lMMlBpfEpYWWB0JGg1N2khdWEpIVNrWUhpO14lKDZyNTJBNno1
Rm5EPUt8KXQpVSRMVihNQnAKem09NWo4YH1KdkQjcEw0UlZ0ITJ+MXZaTzIpI2t0NnhHYClWPUpZ
JE5XT2hYUlNGLVo5RTg/KTZ0QyFqaG9UPzAqCnohYDNjMnpMKnBFYX1kYkFHPTZjVDxiJT1CVHhp
dldvWUJ9XiVtSXZEcDZIWVVJcXhRb2N1ND8kbGl1NXg8NHo7YAp6V1cjPEF4fnJkNk1WVUpBOW1a
bkVhWEF6Kk59QSFwellURm5AKDRKcU93eXpIPEJMQmUodkhOakJ0UWhrQ0hmOWIKejUhZmpDSTFV
MmFxU0UlP2d3KGV6ZE0kc2okZyN6VjxOeFVzQUFhK0wtTmt7QkB2JTFobSlXNEFDVkFVbmlYM35E
CnpVPUFlVFBFI31XY1lvPSFBN2pCcyZzaWY9MkgyIVBKYl88JndiUnQ8cm5EekFqbVQ7bzgzcmxS
a1AwKVIpYm51agp6VFUhKHJ6dEMkOTx2UTRsZiUreEtmIUI0QlklcGxWend3UXs2O2I/S0RRMHtM
dkhZSEFZSzxMdT9KWm0wRCRRfmcKekBJSDNUPTtwbndiNTZ5dlQ9SHFJeWwmdDYwRDlCKSQqQWdq
cFFqIUpXXlQ3I0poPkhTUC0zKS0/KHswNSRUbk55Cno3Tm14N0cjPGcoTUJLfXdYS1RgKUNLOCst
RGJQYlFzRSYtd1d7V0VCd154QWhNcTtTajxmb0gydipSelU5cldGawp6KmY2PVRPVkBQKiZUX21D
bHthPmtoK297SURacD1YQnRLZTtELW14UHVmPWlrdGx+NlAmZmVLcTlUNj1gM207ZUgKek5KUWFp
Q2dIeGExdUN8cU0oUkVxQEx+bVRhQSQpY1lTNjdWRkU/YFN7JTByWXdEdFQpeC1qRj8tfV4+fl9L
SX1eCnpEalI9O00rYjQ8UHZMaEg5a01Bczg1eFY/bi1YN0lwTHRTdG8yN2c4OStFaF5LPjJQX0J1
QX5veUI+fkskN0ZLfgp6MkR+RFh3S183XiQ2SVBwJklTdUNDdEFGJm1YViYjaXpReWNsZWcxQT5a
diUxWGomYHplbCt9WkJsRGxGYD9mUUkKem4xVzVsSWAtcTQzNXVQQ2IoMUdNczN+NFl2ZVckd3NA
flZkNHczd1hzMSNoMyh1K3FURXRiTntpYGBKbEV4Rm93CnpIOHdhQEx4fHh8N198STA3fTRMUitR
cEprWXRoO01SNVkkM3ZfTlV8WmBrQXs+fmxSbWdMZ3gwPiloKVNCTD9qRgp6RjZDd1U1fHtYZT8w
X2UhP2pzZXcqSDAtX2prdmpmO0JsPno9dTl4S14rPUlKMTc0WkJZNWR7cyo2czhPYStJclYKemV4
alpBalRBP3g3ciN6JWJiUCs1T3BSTyViWShxJTNWU3ItKWlCYVhvWng1QHg7an57RytJT0sjMGhs
bWlpajZwCno2bE5rUlF8RW5pU2wkV097aCgxT3VgaHdLV3hyRXZkXn4jQlc/YDVzez45OFFIb3lG
MEM3fEFsRCUhTUNebHZBZQp6elVDV3J0ejEqMWk9fFV6YEdSZD9KMjZxOGlXNWhXS3l1WTJeT3U/
fHZebWtxcnZ5KzlmcEFLeCU5R0NkQ3h6TGUKelQ7eChETmxJO3pWY3pZIU1OezVOUEUoe04ySik5
TklVRDBsZjRiUEtLZVlqaERafSFvRGU2T0ZzTmNBRzYoc3JHCnp0XjlBekRRY05HUXdscyFNYnd+
M2goKkNxeTI8VHk7KkZUc1dMY1BYUXU3MFVHKHFuUT4lZTNeRVlNdGUmYX5PLQp6VVYhKH43Xy00
KiRLZlZQSF94NGpfIWtKUystQE1KdSpXezZQakgkMVAqdWloUHBSaGV1UFRGcjgtanpOVTNfazEK
ekFuLSF4PigtMFdLXmZzTXIzdG98KGlqXmJyJmhVKipBYGw2QUl7IUYwcEA5MGF8K1RqI3lEWjcq
c3o7WE5FLSZJCnoyKkUxbWpjN3VUYG5+WlZfP05yY2U1JlgoUl9DQVZKV0pMYCZ2MUFiWk1sIW11
Y1RGWSlRSjE+K3tDWG0oX01RKwp6NHxqPjVgeFkhX0BDUE1+fEs5bkJmQHFQI3IhPnk7dEk5MD88
RDMtWFBUTTExdGRrYC1rP0dZKzxhaDgmU245bHIKelBKfWs/eTBwZ3hUOWRMOCojQ3oyQ2dqLT5i
bVc2RDV4Qz5ibChXfkNaQ3ktMlU3UyZLQHh8ajd3dXA9SyVeazloCno7dSg0NSMjZCE+a3wkdjxy
N1BIYFFmaF9zOWw/Z0ZweyZ4UjUwU187WCZUKFd5dGgrWDNNeUo0TVhTJWZ3ciEtdQp6K0FYWDE2
e3RKWWlZY3FAPFEwKytvK1BQVXY9P3JYSSRVbSszdlpkOHY5Wm0zckRMTFJEZlcjbiRXeCNUMjRR
M14KenFDIShNMkJxQUBnWlNefGFtK1hENCFJNUc/SnMwVmxDeyUhfEh7OUdXZDVxYHc4NH0lVUFA
fSpKTX40dXkhTW1QCnpjXmlqMFJyU35WazdhMF5VbGMzR2UqZ3w+IzllWXp7ZTJWKyk3d3YzbUcz
Jm14Y1k0Uj9efnwkR2NWUCFJelJragp6cl9UY150K1hmZHYqKzBwUmc0UDlKNUZFclQ0ZXRiZFlZ
KXwjZERRKG0hKWU/VFZPUUVhRzticGArUCEpSntpMiMKej4+eXJMc2x6dj8kMlIyMlYkOFd9T0kr
UnU/UFptajwtJCRYZHRTMVk0KTxwNTN3ey1AR2xsRmpYeVMjWFVuX2JpCno0Q3k/UWJRPD1aNGpN
KCYqbDZPdmxUI1M9PWY8PEB5Skt0OCp6XjYmX09nIWIrQG5qYTx8SV5OVWk7Zz1reXkkcgp6QVZT
cGpHSWN0bVNRZ1RwI1YkeVo9WDN3RkVeUlVlSG9uWn5SSHlgeEhHaCtfVHFuRCozT2t2Y1Z3Xkcz
OEVNYUUKenJgRGs3SFhTIzdEP2JYbGgmPz57PDtqOFFPNFA5JCpQXj5Bc0hxd1UhKVBReV5CemtE
M3VrOzghTnFSXzB7QFZRCnphaVlzJGI/QmVMeylmKCZYKGRZJSV5VjZ0NHpKeiZmX2tNQEE1dW9E
blR3QD87TEUtd01PXzAlPD58N2hTUztMKwp6P30qfmRmWlgoRXZmbGY3dkhscX5DfU9UQTVCI0hU
c15DY200WGBINnxGSUhVU1V6TytgPCVgblE/ZTFzeV9sJGYKeiZIR2lEMlRzdSUoOGdWPDNUSylp
eDlQVjxQbFdNOWBXZ3lQKVNlfE83fnV6JjJBJj17VTtmO2gzfmB0WHhFMl4/CnpXViV0JSVrej17
R0BvKzNrRkpEVVR7VFEwUExKd0c5JkMoVmwtXkFHazF2Q2JDTFlQNlBQWEF4ZWVTMU9oQDBrYgp6
PjR9PkR3ZCY3N19+Y0lLIWdLR2JsX0tKR1dRa3Jgekw+RnZySU99NjE1JjhFWGpDeWIlYnVlJk9A
KVB8ZXY/RGUKeklwMndyTjBAVn5lNGNKd3szQ09AZD1lNjVlQTx1UihRT3ZgbkwtX3h0WWNZfU1p
a04wT0JrWihZS016eUdgUD56CnpufG5LKlokM1ZaRlctTGxETWhoayZrWmxkNFJSJHZ3QlNHMmY3
SSNOe3JjKnN5QXx7bD5mQyRBUWlEdyYoIXYjRwp6TiRSODBhZ3Bme3chZmRSPWpVLXBBKTNVeiRl
Tl9Gd2hUNX1fJjsjWV5meGUqcWNFJCFnNVJqLTNzSlFHbkNzOEYKenFuI005Pz18NUh3NSVyaCVE
VzUjTnJkOW1NXnJnJj5ULX1QZ21NNGpebVY+VHM+QD1iIUIxRnxJVSQje3BjdjBACnoxa2JpIWBj
Pi1EKERAbWF1NXM7ZXNmTzghdzZWSVYyZWMyVmRiSHJ5I0pIfXtBUztmenJWTXc7OTl3OWR3cURY
egp6eHwpcUNzSitla1JnfWJ9UkJiOElAS2YqPklocGFUZjchbn5mLTlNRTxjPEhXNDI/NitSXm1h
cndfYl9TVVgmd1EKemozcHlRNjdRUj5ASXc0ZGc+ZyZ+Kip8NHFoWkZjSnBOO15IR2tCdDVOaVpB
cGN6a3BBTzdrWmhpSk57S2pLPylHCno+P3Y9NEA4YWdVejdiNEJzcE5qb0MyOXAwUy0zfHstbDxp
WTVNbnBXTm0weklHVW83XkhQTyVvX2UqZzgoUHJVXgp6IWVBWXhwLUAyNyQ1WSlOalYqcUwmXzJ0
Ui0tXkEmbSZ2K0hjaz8yamtVaGYwa1l8eHpQNSFqPG8zeEoxWWxzWSkKej8pYFV0QDY3SjlkRm1N
RWRAQGghb1IqaFZzRz1yRzg0NDFCbjdjZDJHOTM7PzgqM3U2bjdWKHpyVGtTdnRFNWs3CnorMXBG
JERfN1dab2J5LT55dDJYVz1DYVVJPkQxX1FtMjtrUCV5cSlHZnYzMEFoKXN4NlpVS0NYbCNVQHFL
bFd1Ugp6aC1XM1g+bkJsVThzR1gqcjFRRW9jeWckRXdJNzZiYmpkOyoyIT9ES2BDZiteKUNyWkxD
OCFTU2RtZ01rREFLJEkKej5DQjJ2dXBJQlY0R0JCe2x+a2BKKlNOVnMzPXVOIVJnNFVyMmd+YClz
X2twckB8UEl6djFIOXVAc3hUfEZGI1MlCnomKjZKayNAdDZ5NkNgWktoeXlMXyQyMWE9MygyeHRi
akM2Y28qKCRhZHc9Tjx6O3BrYm9XTCpBXmJmZjQ8RjVYNQp6eThDKEA2fiFGeUhlQkMpa2AwSGZY
dTtnUjd5TnV8QF9WQTlVdF9+WDlac2BXKnlFS1NvcE9IWkV9Sjx6OTZTJG8Kemh0b0huYUtBcU01
P1lqbU9wRGUqeiQxRChESEk+ST4rPk9uM1M9Nk9IKntfQy0yUnpucFNTQkd3fVc7Kl5lR2Z+CnpB
R2JaeEU8YnRMQGojUmA3bG1zKWt5YTR+IT88czg2eWw/JF9DJFN8bkt9RDFARklIPmcjQVVjOTRg
bHR2dCtoeQp6KHlAbEdXbip8fD5pM15XPmJ9JCFDNERNSWx6QU9mZmRNbl5HeEc3ODYmQ2dNI3p2
TFhKYSkzUUZMUk59KXJMWCMKemA+QTUyc2czJnJycHxMTz1ofnY4bFJwKGxjSkZGOGF9NUBuTHBk
M1luPzxjPUB6U2hTWSVjQiFYdUYmZndJIVhgCnpMNkcyS1BvTFJ7Kks+fnZWJjk7bnVVQzVjTztz
RjFrPWpyfDB0fDlyXnpvKno/fUE7Q1BYSzQxMCp4XjVZV2ttRAp6KystaHheST5nfXorSHNVajB4
TSpaJEwwPGduaTs/QTxUJmRmSHZ5KSEkOWA9P3soVn1IPklAT0lCb01wPW5BO2kKemd1VSVUX215
O2hiTTwzNG14PDcqWSh6PFM8bjxgIVIzKUJoN15iMmFXWFM5VVM9T2NFOFIzMkBoTEhCTzF8fEpo
CnpHM1dwQWtFWjw7YG1ucEJhV3cmKHpaeW1+Xj9MSyU7ZT4zc0Z+MHpPSitoIXRvbVNZISloeks9
a0BuPXJIVDJyVQp6R2x8JXtedFRQWDItcz0+IVMqaEl6UXB0cExIPGBJSVliPm5ydXZaQjFUVGRG
NTkmPXpDeDMocXRJRnF5RkFnMUYKelczNGthc2xIfmZfQV5VbnRNSjV5PGsrPzYkeG5gd0ojdDF9
ZW1ydVhQaEBRMz4xejs+JnA7cWNud21aP15SUnFsCno8Zz01YCpRKDloWDl8NkRzZ2E5JDY0YGVZ
X3sxcFJzeyl1cztBSmteY3clYTNnc3VNbShfTTF3OD1nPX10dWlzdQp6ITdKR05TWUxsUT9XV0xZ
SFlFMV5Wckk0Y3d5WXlIalBrd2FrbDJmKlRhcklVbH5he0BmVkQrTGhEO0smZUBmR0YKenoyK01l
dnZ0YmtRaSU5bGMhREdDe0c8eEViWj1mQl5AITdmQTFLMmh8SEh0MG90TzhkcGZ3MnA0Rk5QU19R
VmFfCnp1PUdAZldHPzkpYDZjP0J7K1l1aWNCWUQhK3xsVWUjKUJ3KzRiOGhQOThCaC0zYDhiRyVY
ZyYlLStEa3UhOF5MJgp6RTxDZ3E4JDBDeFA3YkdHUzh+fHJlI2ZIb0c5dFRtPy1SWSMyRkZfTFBH
KCM4WjtlZH18NGtjQ0xtUiFeZVA1bGUKenFfY3dITWIra1BENUJ6YlRhPjwta3dEMjZtMSV0UU54
UyVAXn1KT3A8ZDglJm1SSjFSc3J6Ri0tUy1kMDslOzJ+Cno2JEc0MXFyamx2dD9OZ0F4WENPM2VZ
RSEmb290PHgpQk8kWnltdkpTbEAqUVBGWFZRQXVlSTE9UWhFaUxjNEROdQp6K1V5ejUla01VeFJJ
OTFmOTV4IWRvOEYrQHFgZG8wKk5Ldm9wc2pIM3QlbHk4el8obkdYTno7MW5gRDdySl5zITIKenYq
JShhVUhiUlRsLWJFR0c/RVJhSnp2eXooYHx3WEI8bWpaNTxFVnlTO3Q5ejtCcEQ9T3ZTTyEkQ1pw
YGpOVjBeCno2JV9GPTc4fGRMNmgjVXsxQkxHQ2cyeGtvXllRNzw/dnxkbzVGWU9paUVYZGNKVjJh
c20lc1I3ZkA0UjMwfGc+cgp6RXQkNnlscy0+e2QheyFSdGsteS1lMjtXUFEwWGVJNF5TPV9LdW98
KnYpQV5RM1lMejsyaTI9alJQZm5tPiolJSoKenxNcSkqME5lMzJTfU1qMTE8KjRuTV9iM0dlQ2Ml
RTxLXkFgP1pffjx2cD59eUNqNkF8SVNST1ErPTZxV0xFJj9ECnprZ3IwWSpLNGE7ZX1kRUVXN3JU
NThKPTxSXlZnQX5QNjhoN0dDO1Eze3F8V0hZR3lUPztzNDR3PmBiRnJwJTt+fAp6em9xXkhUIX1V
d2hMUHtJNklvaGVpfnN7SGlldVRJY2p1ej5wMyRYUHZFOWZDeGRqYiRQMEwhcVdPKkdYYGA4Q3wK
ej1SMSFFbmFGO1pYJmAhJjNtbnY0WD55KnVaPXctNGd4Xz5mOHh+KTwtQThAZns8MSF3YX5lQz8l
VkthQkg5X0B8CnpOO3J4dG1HR3ZRLTlNeyVYbi1QPVc0Xz9PY1g+aDhwQzUrXmBga3dHNjlSN2l6
T19VSGVeUVpgQE1odkF8OXBffQp6QkBKOExiVz9WOz9wQ1Q1bUZ7YUV5PSVvS2JhZj1YeEE3bzJx
e3JNPldCdW9vb1otOHteSVYraj1SM1NkTGNJSisKenheTUhuUStTdTlwYldUOVIhTiNQQHkkdmVL
aEN9dHRiTiEwdDIlczFCTU0xUnFaUmgpISZQcCptbi1eaUN7K3JzCnokZ3U2WXhhYztOTUV9ZTI1
Xl4xQHZ5JUZoNnpNTTVTcXNxdSZ2MEY4LThaTXtoKXcmaVdfZSVBKXM7ZX1kLUZwWQp6cDZhcU9N
eHp6ZFMrSzZMY1FiQlppJW59TDNwKFpGcilSbFYjNmtrbVpjUG9YRDBiJW55UCY8RFRBOSMzV0ZO
V24KenA2aHpXLU5ROGB6ezMhVVBuamZlSWpDe0kwcyhQVVZ3VXhoRHlqKGJ0KG9zX2ZwbDYrKCM3
JUxpZW58RHBQWn5gCno3eVQleiEmNG4xR1FuR0J6KT1pKVkkUVhwLSQ7NV5WYGJLZHdSbmdkVVVI
R0d3UWJXVmpeSjsyKFd7R2I/fUJ1NAp6T1dzTyplNnRHTkNSMTRhSX4jRkwpM3BCakshbC07X2V6
bTZmfWlgNWV2VWckJlprP0RVWElrM3t9MTt1YStDWG8KelNBSUJzRUtlVlg7SjEpe1ZENHVENilD
MV9XISY8VnBJTW9zUEZPNC0pdzxGUWsoTDRObig8YDRCYmZjQkpmMTBJCnpLJHVES3cydkpFUEs8
WGVOU2NHK0xFNXdiOHF4eWpWQzVHZno3b3Z+cHFrPjE8Qmh8RVRFWFBWWHl1Ul9JSWpoUAp6MXxD
PzVTbT1JI2Njci1icyh5bm5zdiVPSlF6RH43M21rTXIhIWhwM2R4TWFsWXxGMk11PHt7dU4qPkUh
PWRnTDkKenNuTH1aYitGfGBzMlhtJHhaMUohK1RVek48fW9LcDIhXjt6UT5tYkBTJSQ3TmhJUHVy
ZlJCPXZVRypWO0RtLTdMCno0YnRJXnxHKnF+PVZSYmNUMDJxbm4pR0dVNT9BLU0jRzloTEhPTGIx
RGckXzNZJTcwdFdVTzhaNDVyfXlKVU8yegp6c18yY0k3R3wjPCh0LVc/QTxra2xtZUcpP3Z+TTt3
N3V1KFUtWGh9MyVYQEZuV1FacWw4JSYtTHglSDVQQFl4LXAKemhBaFhhcTt+JE9xVmIrLT1BMkxP
OHQ5PVQ3KllfZClHRzcmWV5IJD4+bjc8UWRPVmFWQEpJVVF1ZmZWVF5wRz5OCno9PzVpN3FgR0Ep
UXJEbnNWQShTcjh4ZCRTUFdSYGh7IyVxRFQtMFJNOGduSlpPMjE+OEBSZDJwUyQoNzF1XyM8dQp6
LUpHbFlvdzBlNXViNFpiP29XWEUreDNpNEIoanpmKH5FPG4kU0N0bWhEZU9wcXE3ZmZGJVpHSnBt
QGMxUXRyQzYKekM+diopZkgwST9LQk59K3YqdSlEVXtfPGNmMTM2I2licmlCUHRodEVtWlNOVzFh
YVRpd3h7TDwjfms5d3FvbTElCno8KjxNbUFNemQyYiorUnF5YDI4XkRkY3E8TyU3IyE2cDFScjF0
RjF7NCUxLTZRRzY/MTlgd1U+P0E8STdfSCY2egp6cXtwWmJDMjc4Z1BZWVEyPlYpRyRZOW56Pi1k
Z15CPzl3fi01fTwzaHd4czhiaHg4K1h0WmU8YEBWJV8zVEhnT2wKelM0ZD1tYVVkcXMrYkEoZnpA
ZndBT0lSZyR3OE85Uj5hJTtAKzNBUj1xSVZ6Q0k7fEcmdT5kaE8qaU04aFNJRjBWCnpPUkdiaD1U
VHFHXzxpc04/NT93dU01XktOSkNFRjxDaUMjUz9GQGszKUl9fTZtXjtycyREV0NNUC1qaHFLPmVl
VAp6Mlg0Kn1mbHAyJHFCfiEkZSpyLUd7dX5fM3tETCtuJi1yby1OYEF7Rjh3WktGVDs5Xl5EODle
TShaN3BZUnZodm8KekJTO20tIS0oNy1HUmJ6XkFBXjBgKmpDRUd6dT9IejFfd2UjR1hycHZgTjds
MCNNbjNVdURuOClwYktpQShrdm1OCnpOflFafkF3PTxnM0BqJVdMfHJRZjBpeSZPSSExT2NwYkA4
QEVIST1BUD1lKl9rTWNKRis/SlBRYjN2JG8+dzAqWQp6cXoqe3VqJjs0Z24oMGdIe1ZefGRsXmh7
SEYpQ2ZaMXp5YXJscyMkNDcleFppWmImNUt7cTN3OTBMMkReenA3S2YKemN3U2FNancpKWZ0c18m
U0FUcWg1ZGFxRVp1ISh8I09IcjM7eUN9VFJUK3tTRmJnRn17T3dqVjdqX0JAdWgrPGRACnoycTwy
UiRnUihsblg8Mio/JkQrbmpJcjV+NHt8bztqdl9WU3pfQFJXbXcjeDBgPFY7b0gjTkJQTUJhTksl
PG4jZgp6a2trKjBXdn0jOVM3S3Fxb3BAeSowWHI1NWNeNjNaT2U1dHNrTytGNTR7Vng7KF5VbSZQ
eT9nNkdXOFd6an5eUHAKelIwMTBPOHkpV1BmUjhlVGp8QHVZMS1jVnstJj9oK2owYXsoVFJkZ00h
OStnRCttUUEoJUp+SzI1d0JDbUtGTE18CnohMVZ3VnA7ZmFZZjxJdUlJX0RwNyZSfGBHMEUwOUkm
bTY5K3tpcUxUPDgjI2Z7KHVBWDxTUDRsVns0JCpMRlI8egp6SlFSWjhnOUxnWDBtfnJ+ZVp0eShY
Q0VKR3smNio3aTNSaUQzekFeYW0xV2ptRWxtZ3xNKXRDZSFJNSQjNUtxNFYKeik0Y2VUaWVLa21t
fjs/aVRBSS1OYTlHWl9zX3xrRCVNU29RJms1cnAzZihgRipaeU9zPTF6PkQwfSNOVWBiejkhCnpI
IUFiPnJ4NFFaPH0waTVfZG43VWE9N3clREAraVNgZncwISErPzNvKUluTC1vQkpSaTVjZEQoJW9C
Qm17enJ4Pgp6fEpzRTg8cEF1X0xsMGVFJGBxK1g+PWxvVCM9SCtsKC1mZEBTSy1kODNHdHxEOTU4
JEMxbTVKbW5RISVOU3JhQCQKek5gdjw4YH1oYlB7IWdCbG5eSkl7TWY9IS0tMkohV1hqYlZ9ITAy
T0tDOFFAfEc2RH1uV3E0YmRQPykoZCtYRTBZCnpuSTxpfVFsP34jWlRJNz02Q0olRSVgTF8qbnp9
cCVAclB1cEZ5KjM1UUU+akJOfU4kcGNOLXUyUmt6dFFnYSlldwp6RVNVe1p2IVRNOVo0KTNweTlX
bXlNNUd0fGNwPipjMHJRZDhGNnFyQj9MVnwyUjVJQmlIdDkrWiVAN3o2NTR2Sz0KemU7aip7OTdp
JGdSayY2fCZ6RjtwY0Bfd3ZMNT1sSCZQWDxkWXU+IXAtTlYrZ2Y9Uj41SHx3Jnk4QWh+eioqPkdC
Cno0NVR0S2NSe2ByeTxFU05rVlo+cFhRbGF3eXhTRHUlZT1eMkMyKzN6V2oqWFEzdCk/V1l+KyZ8
U34yM2ApIz5ZRQp6VHd1YHEyMzVmeFotSiM8SiNhQ1J6Z2xMWHxLNUxaamozWWY5T2V3PyRvdURk
Pkg0NDlkZ29nTURuS0ImQEkwekMKejxeKUBoVD5udVYxe0NrWngkYF47O1p0YCVFWFd1dkY4O31D
S2VDPVlfa3M/cnw4c3tMIXZFfGorMDI1VW08ZDQyCnp3cGBsJUtTUSRwem4rXn1lbSh7ZkNIKlJ7
M3hee3duRShmeXwxMFRLMUVjUUglR3BhZipGdkJ1b35IMmN3fCFRPQp6ZlZYMkRaaVNmdVdlU2d5
eGZ4T3dLISkyVE80Z3dkdHJKdGx8NlFMLVNCaEUrUj5yKythPkZndTB9OGhzS1ptalEKelcjQjhL
dUZ0UHZlfC1iJEpgS21tMiNCSmczPDdvM14jJENQfDhBWn53TXN6fmNBKGQkU3V5ZkU9SytHPjVi
QDtoCnotTmt4P01kYCh0cFR5RDdvNSN6Jk83QnM2QzgoUWxvZ0BaRyFgTUxwbXZ6RGMjR3F3KXsk
bWxWTWdzKURfVmwkZgp6UUdsNT5ITnwtbmw9bj0jbUd8KkkzOGFOUDdKbTRETShHOFNBZzB0bUVY
bystZDNQdjNhPH5qVmRiPWBqNEZUdncKekBJa0t5Sy0zUz1rI2VQamtTUCNgQzxiQmtPd2p3N1pE
WW85VEg/M3tNRWdvOSZZT01eclQ3PndhMzkzKDd1QVNzCnpTRilfTkRDcypKaz1sS3goTCZLR1F7
Y3UhJC0rJEBSXzMtZG1qWU16KX0/VEJPXzhCcnJxWD5vVXhAd0gyQHBnKQp6ezUwMzV7RGVJMTts
dERlMEYlI21oUn05UF5AZXpHNE1aKTY0cWR0ZV5yTkp0Jm1CbTdwOURCYytfdmY0YWYmXkAKenBa
fkBBaW5OMiZII084KjJQTmlMciUkUC1CZipoWDY8Q0tBYjVuT3Q2PDMwbE5RJTVKalcxMEw2LVpz
WTskLW08CnoxVkR6cDtnRzs0UTJhWHAlfnNHZ20yVjJRZGlKbWVKI1R5bjVOcUR7c0tfeEAxNylS
MU1IK1Q5U1J9Yktld0s/Jgp6UERTO1ohI25uO2ByJEppUi1hRkJkTUtlN0MxcCowY1VeSkg2Yj18
WERGUU1WTGI4Mm1yVSN4dFUwaDx9UlZNS2YKej11WkYtWFR7d0dMTklsNTVYcipMOFApeDhHMT1J
ZEYoTmVpJHsyfXI8PEV1X2F7MTAlUy1jR3NWX0JpbVFBSVJfCnpBPkh5aW1jUlRJQjtoKURYMzBJ
dEdycFN3cFVnTVdkUV80ZXNsaUFOR2lFISFgVDhYfVBOUjtPO0t4MlFlQm9BdQp6eElxSW9HSmY4
PzJWNncoRzVxVikwQk8xM15eVkpha3g9d2IhX0w8WkhDanxXMG5XO2VWfW5nNDFAXjVKOE5sSkYK
ejJhKU18WEoraiR7WEc7PExfMm1sYmxkWG5xZChpZHtAe2h7LXRAZSNgaWduY29lUzdLUH1eOX51
NVZ5SSo+emoqCnp2d0tEdEB9JDN+KHY0YXUjT0BgWClfPlU3YCUjI1B1byE4diMhemxRM2ghZ0Rp
eXZ8VGx9fUw7QmQkcy13c1pGJQp6VklqP317Kj5KNlF8VXdGP2d0PnZYamFNR2RZS04zPGZuP2pl
Z3t5KT08Z3Y2U3ByOVJ0ZndGITE0e2MzXk9NLSsKenRIY21VXkdDJXtIcmYkQGdPUSNEOEMzJTh6
TWROYylKdSp7TzY2cDJuRj9mbTxOYHBzYlRGMkIrTCRyMUQyYWpMCnpeZ0dxdWh7KFolP1VMVmIx
O253ZkdDP0l6bH1HPEA9UG1Mdjk8TWpFZlhNaHplSWA5MSMwUz42MDB8KHFWTnZ0cwp6aUxBekZR
QU1ePEF1WFQ9P0NgMTU/NVBWazM8UyRudEowR1Z8Ml5geVlYP2dlUGxQRkhkQTgyWG52Vk5sbSMr
cHEKemUhMDEjO00qUVhPOHM9QDlZPGFURkE8eSUzd214Q2s7OVReO3ZneHFEPHdtK05zT3oqQGpj
SX5QPG9DZWNgJGcqCnpIbzZ2TVlLd31KaDJffjl6PCNMTk9eM0FKRnJ+O3xoVSR3e2lLY3ExdCU9
I3VWMj1yPk9HdFMzYWFldzQrQG9TcAp6dlBaUj5LV2g7SkRidmROWjhQIWJhYFZ4Ml5qPTxrc3Ak
UUZnQVhWQGwtfVdHTVhFZDBlTmF4fitxLW9hWFVCSWUKenpIIz4zLT5jQUU1Yzg3ay1rTGxjajRY
UGcmI1p+enBnR15CKlp6P0MwMGEtd2o/dEptdmhIPDVWI2tXWThndClKCnpnfjFJPFRHLWE5QT81
SytMcmZObSNOfH1SPEVycFNqVWopTyltSXRfUVBSZHduVEtiTHVITk1yeVE8cEZHTjtAQAp6KFk4
U1c4SVE9eS0yKWNuKVc1ZilvVH0ofFJyYiZCYFEqcV5QSSMha1BRJkl7N3teS2VTbT0yRylJcEZS
WXZBYisKejE9P1hMKlQ3MDdfbUF9RE5VZmtCPWw0R0omTyhXdUprc0hTTzgwVnZkMj5NVy0wYXBi
MHdecU53ZmtYUkE9PVlmCno2e1ZqVDE1akt0dVloZDd4UkUzOCpYQDRHRV5uUyNXbytpK147Wnc9
Sz4jVjhycj43JW9zez5LTzdCQXQ5Q2Zrfgp6eX1URGVsfGxua3RlZ2xnMHQ7RTFVWFZTQV9FK1Fr
YmlDeUZ0Xm5fZSQjSlpZPUk5QHV5eTxqMTQrez9qPXJ8eU0KekdDPSZBUGg/e2FwS3MhJVIhcDdh
M2tCNkxuQGZeQkZ0ezJnNWAoeXQmYSZnTlhWJm8pdGt1eEFhfk5ZV2tsSlBNCnorJTlwPE5VSExX
TGkpczRqYWhoMm59T35IMVpXTFJ5MFh1YkFGak1SQXZiT01APkhiTD08bWRodzgpQm5DKmo7ZAp6
K1lWPFExSkhUQjhhTnpVS2JsYUooRmM2PWo/JVhTTDQyREprSElPZGhhYzAqeEwwbT9HVXs7di1Q
X3ljRm5APjcKekt4QWJuK3V3c2d5b1hVfD1EWCYzPStQRFA8VD1XOEtmcmxxK2ozdU9aezRTJDAl
VkBucGhrejhVPHF1YSFVYkFtCnpwWihsQDxCYllmTkxZV2dNRClVQWtjLTJgeWJYKy1IJEFXR2Z6
UDY3fEFyPSNafnlhJllZPlM2U2ZrX2NXblF8Mwp6TFMwWXF6TUUrN3kqUTY0YlFvQmx4Kms9M1cq
JUx1MWUhNWZWfnVHNFhrWW5Jbjl8RGZRJWAqUkN1Y3pJSS1xNl8KenM1elRfT0JnJWZsbWE8Tmpy
aEVFdD0qaUNibUIldjxPNXpwTTFRZTtYRDVteF5aY0l+PSRIXlIrblIqRmN4Pzw5CnpvZFR2YWlv
dXopVSpyc3BCM2VoTztiaD1aJnFsZ1ZEUylyTEZyJlQ8KnRPWkxOKVUjLU5wKnloYnBgVkdecj8w
RQp6ZERBYCQmI2lPPisrdSVqZTJ8Y00yTzk5PnwyYEREJCkwTiV6WTVsOEp6NmpZSGFZNzFKLUNR
b19IXlhKP1VCQW4KelRtSVJvMUdAOFZRdGV1KV90OUpzRT0ySD1oOzYhJnQ9OWZCXmlNM154I2hw
NzZVZXViV0VnMXY/O21TUDZxamo/CnpIKXBOYCpjRlkmI2Vxb3VLSDJiJXMtRWB7T1c5dEEmVXEr
blFUSEZrX2JHUnZ7QEpaZSVEJUJMeGw+NWhwNX1gTgp6YHc1NlAmfTkpX0pNSml7UVZFbyQyayFv
WkdAcTt1YngpdEptXmJnalBXWjhGUWErX0xoOH5lPU1AcyRoTF8tZHUKekAjbihWbVhaQEJ8Rl9z
UG83cnN6UDs/eFp1JGY3TVUwPkV3U29naldGMyF5Jk0mZipxI1MwXkxAMURVQll+YUg2Cnp1MGsz
JlQjV3E2cyp9VEBWQXRXK297SEhXUUBPcHVFaylvYiVlU20kd2l4N3lsP31pPG1FZjQ0IT1takAh
a3E3fQp6YCpPOVpxU3V4ZnBmd0JTO0BKQUJRTD1qOEdyKGlya15fXmc+ZGJHPWQlU3MxPEcrcXM2
eFpUT2RwMXlQcCk/Sk4Kek97aSEmQHUxMVYpaWR2PGt4UjFRNih7NkR3Wigya0B4PitJP0BYWCpU
fCM8LUVtKnQ7YXhHJDUrQiM4WDEzYkRmCnpMMzhiKkY1aW5icSZROztfJjZNUVRGUmR7UDMhUX11
JEpEM1gqX0VBNEhnYGpxVm17fGFaeDIwUGlYPGh8OVFRMQp6eWorc3RLNiFvK2oyKF5TbEArfm9s
X1dMaDJHekdnRDwmcG0kKCU5P0ohKGVpMHxkRU41Ki1jcDl8SDV4MlV7KTcKeiFOSjs7UW94antQ
Yys1UC1UeFpEIU0heDFkZiYhRFB9M3JYbWxkb3BGMlNwT29PcElWUjUpKztfKjczfXh8WE9oCno+
WkthbGNXK1FMSUtRNVduXk9Edkl9Myl3U0JHNWhkKUA5TmI1dGdfPDJOUG5xNHxwQkNuU09YZUs8
eyliYXVMTQp6RWl6bSFKfFVOV1VxQ3JtdzBicFIoTl8ofSs5KDVqQ0R+SEI7UWQwWnxGbHBXdjw+
bHBYUFFlfjRweiNvX0w7SFEKeloxJmRtODJ4Njsldl9BPjljRD8jU0RTUXphaWJHbnREVGh6UXI+
amIpZWB7KiFPVG91UWleeEx4a2BVMTBqez1RCno+KXYpdjFFSjIoJEZDNCFXR3ZaT09zS2YkUT1r
Xk42bGQlNkckdD04c1o7dXNVNVMpQms1S09RPEp0WmNVKDNhcAp6V3pwZG87JUpXQWZPKTZCMjwx
VnNoVmkrcTRudCtWJCR+VG8qWlh9KTBgPCMmWmNrRWVUcHkrN216VnJUfDIxJXYKemxSbFNJSThV
NmttYSlSIWh0QmJ2KW81XzFYV2JkJUtQQFVOcCtLSmMtUXArS041TSVGJGEzYVYjNDBiUXlZe1Et
Cno4KShlO25pNmA+NGB6TXRfNXV2fEJPX30qVEczZmclfW4/Y3FJZj1aKnRVb0QtJTctRlRSWENO
RyNvKXt5cVIjZAp6ZVBETkQpdW0+e3ckPG1pa0RuQzRZSnxlc1Z3OXU1P05sUHIyKyNXXihyTVkl
KGVFWTxIdDEhakM+dDBUeXdNdXUKeklNOTM1NXdHYyplSF9vOCY8Jmo1QmA0JndFNVp5cjh8Q3xE
RXhQSU40VkNubUleVkw/Ylc3MSR5Sl8hfTdaWVdYCnpaSDlNQkp4VlN9Iz0tUGNZdlVBfV4yOVRI
bSFPYHpXP0tYdigrOTVZbThJa0xadkBRQXsqJlY+bkw2OHJ6KilMMgp6I0BvellgZVVJKlJHUE84
bWtfSU9ENmBMTHdZcnZhTyRhdExUQ3JxMWRhe0xqQW0mNldgMlRjJHR+WEYoVUs+QHgKenZLfGdl
cDV4enMxekBWNEpGPSRJaW13MG4lQERtNnZhZ2JFTDQ5a0tRfERmKyQxZCshSCNOVEdST3prKkth
WHUzCnpwTnEkcmt5dj5UOylvVkRFbytiMEA4d3BgIUxSTSUkUjwjMTdwejJhY3BrTFk7eEtzZ1F3
K1pSYGphUiEoRFN6SAp6VT1SNFpuQkJ6Y1hMbVg5WUt9e31CfkEtfVZLVXJ+IXRXbyVQWXVVZFkj
dkRGN3UocT9wZ0hfakxUbEsrPVFYdl8KenMjJD4hWXNKYmM+JkVVS3EhZ0ZiU1JlWT5EfDxoLSEk
fmxyUmUodFpPXkxlM09eQmN5aVM0YDx8R1NSOUpzdFpSCnojVUs8ZUx1fG1EIVZiMTxuRG9jb0pm
PFNYOEt4Pz0tQW1IM15Dd0ZtSCtERDVKPzJIPGhAZCU5KlVWezJqYEtXTgp6JGk1Q2szPWApdiRx
WlF9bn5TbU5VVmJwU3hVOWZAd3x7d0BqKHFocUQySGNUPkY5JVFkJntTM2UqTjNQa1NGV0wKenRY
VlRITjBeVHY8USpZXyZWSnB9dG54WHIpaGcoRUpwK1c/YyZAPGA8SUB4fDZKPExLNVJFankmLT5o
TTh2ZXRfCnpfalY4fj5Pe0U1SVA4WSh0TkdXbCY+ZUFYa2JiOF4kWStBeG91Kl9RdXAyXmM7IVlD
ZEJjUFQqZ2BiIVczPUAjagp6OGZnfXI2PDBjQDRmYnZNQUh5K1dVIXskSXYqNT1obzxFZHJJS2Rh
WWg5PSlhRFcod1hCVH1SUTw4UV5LTFB8RyUKeiRzMDlUUFY2dCsrMUg9X2wkQFJycChlVyg3aXZu
aW9jTV53RSFUdE9lekFTYXRPOWwqeFU2SXo4elFxWEhoekJICnoyZTRrfiZEKFp0dSVVcX5YMD12
bEVQLTcoR01ne3pQKzZpZzU5eFMwTENvMXBSY2hIdVRYR2xWNGFRU0QqNGd2Pwp6eEBhdSUqVzN1
VHFrSTxOQVFAOD4jUGlIRHVrKkZGZXBkbSNqVWl2ckhaJEk0Ji1PfUshR3JNXnNSLVVRVWVDZlUK
endWYnV0Q3dDeWFXT0d6YXJKQ0JkcHMqcWF5USY/WE12JlFENlVtSWJZJC10WSRDYjclYFVlbCk0
OElIMUBPWjJVCnpNSXhfPj4kYV9DU2h6V0JlUSF5LVdPdW4jKHo0bndZeWdQZUZwKDhHfDR9Q09Y
KHxnfFYpS2ZeYEsxU3w+QUJsRQp6b0p9YHombDtlN1gjbnJqOyN3eD9hTl8oLXBBaypgUzIyTX1O
Ynt4TU9DV1hXPFRBM1VYLVVwOEVgYkRnMGBqQzsKelcqJWo9MWJjWUwhOSgtS0tmJWRkcHdSaUN1
WFA7YUFZMSZjKSNNeDtkPGh0bFdGeV5EJTxnbW9wT15ye2BOKE8mCnokRytVYERybHZ9KiZqZDAm
JU90X1c7dXZuTl94WXJDdVpKKVRDZyRwKjV0MCg1alR0VEszU2o0Z3lIX1MmYS0yTwp6R091c2tr
TWY+Qmc+cGpIXnI/PGQ8QnhYazdzK2cySWxDNmBqVj00UGFvZ2YtRllINWFVQ15VJlRNIUpjX1dJ
Tn0Kenl8Z2hsPEhvTjcjanV+PDhQTFJBczI2P05MQCFfJUJIclNVSEV2QE96U0RDQ2lOSmVJRzRa
ZUxuUlgtR2grUkdQCnpPLV9YKGA2cEBhaU9+aHtTcCstJT0xKUdlemh2KmNJUUEoY0NDdlBPX0Yl
eV5qRHtibkhSaChoc3k2O01hejVTYgp6NiRjM21CeFZNZkB1KCU/byZNIVhGaVlzWUJyKEgwY3ZK
MG1QQHZ4QmJQezJxYmVnYzBaUEZaRGZDU25FZT5WUGIKemUkIVN2RDI5NnlBTUVsSVZnRjE7SXJE
XzRHbjBrcigoS1FrTjZhPGxedjJZWk5uezt2d2BCKVpiOXsxVl4qKXQrCnojcWxoK2t4WHIoUVB7
bG57cXg9M2x+UC0jRVlmTz1LbTxZRmUrTiZONCRTSDZtTC1GUk1SQlQ8WUJfKiskWiN1dAp6dm9S
S3dZXnNBTDk2R2xAeWNELVItQkhXYztESUVFfEZyZSFZcT5eLUhffXh6JHRxTnc7THxXX3p3cFU3
U3R6MlMKek8jcnxlfDU5Tk1IU3RBIUd+djZxSz5PITd7SElfME9ufTE5Pi1ZeUZPR29aXjV7P31C
NzZzZmtQKDhQNjY1Kz5SCnooanY9dkpvNXN0aGUlTiZYUWxhSntDdi1WXjkha28xYjFYK1FecVUt
TD03JExHJCp3aklJKypXWn5IIyltJFV4bgp6Ym1EaiFBaXVObSM8cnlNWFBWN1p0dU8yZXxEMnl2
NmJURjdrLTEtRi0tNyRmO14pdTdMUXlucE9TQ1AhRFdRK2oKejYxeF9eQC0oaVo+ZklyKV5PNkFL
KEt9fnU3RTdNdnN2cGRPMzZAd2JLZXVNflJxaDBSaUA8S3FNci1YVikoTzRUCnpQXj10YHhBPEgy
I3tMNWdnWDRUalh3ckBqKiZKYCN5d0xqdykrVztnaVlOUXRNYStocU0jMVMhPGVrMmlqWDhrVQp6
MXpCYUM+KDh8YkJjP3lDM2VSTzJhQzxlYyRaVUdPZEc+Kj1aYzh5OG9sNGQ5cz99c3x4dVBsQUBX
VDw8cHdrKGcKeiR8ODhXK2khSzhXVyY8JGxNcWdqZHF2NFVXU2BYKEt3SjZFJCVNbDUmcWg+UjN6
bkBeSlJHJGBTaCN+QT87RjskCnpPUjNXckUyU19hJUtlMlpSfCVTfUlxaj9jWTdKI2pMRnhSWWB4
TjxhQXZ9RDJONCszSzlOWHhVWnZEQWFiVkpFRAp6KXh4KVBFfTk8Qjh0RV97U1ZwNUI1KmFGWnBU
KGs3XnxLfGNFSVRgMit4QylFdEY8IU0rd3R5O0opSyorLWRDcmkKejl4PzdOZTNXXjtJQypMKCp8
czFVeWB1Ml54TFQ8S24xdVdKczJINlB1Sl9WPU1TU1ZuOTM1U0U8e3hoP0pTXmZ6CnphTyFRM2ZC
IzMxY35NRTAtZCt1NUdvU3dwUktoJWtXK31WdkdhcF8zd1d4MCUtQi1VKSFRdmZ8bn0qJDRFeHlJ
RAp6YClKSElXN1dQQHQoP1BAKm42P2NvUjVseTdLc2V5RmkpJCt5WiFtNT0ydHpIO2ZUKyZRREUh
YWN4Kj9iaE1ON2AKemQ5Nj9lNSs1OD93M000X1gxPj9uY3prRCpUZmxQfGoqSkpNQ2t9JWJKVEFV
OUAqd1ZLZWRsNzg0eGNIaHJAMEx4Cno8SW5mXkIlJXowWiE4WXhnK0NJMVpFY2E8JEBUO3I/a0l8
JVZLTmtZd0pyKyg5cnY+WGMmfWgqN1RVaGFDUXk9Mgp6UkI5PVoyMEVQe2BwbUpDXzB9fX4jZilM
MkRCU0hBYj4tYUNhYkhvfkA1ZU9wSkRyM3IhYUpoZ2lxcnEkYFFDa1cKenQ4YXlVKnNfNmN0TD18
M24oUEsmRkZBLWA7X2RLJmF7c09lI3cpQXw0fnhfQiRnVV5ya0BUVXJwUUxNdjhfJTxhCno1Pkgh
ezM5X3slMXElO3djOUhHUzRtQXlIU2hGfn5FJEdCaEE5Vmg8NH0/VVYhUWxAdkh3OUI3RkdSMT9n
JnI/Wgp6ZmE0M1hZdDRUcUJNb3NmWWJ2fntJQDRLSUMoZSg4OHA/VFBJJV90TUdYZXlwbXlyZik3
ZT1mSE9ZT0dvY15TOE4KenFHQ2ZMIVEtbkhSRjdVNVokND5EX3QkS0BEK3UtRjkxYSFfO31YKnwx
KGc0T2lhJUlOOD5OKmpESkM7SmpGMCRrCnomT2Y9THUhSDZGeF52XmNATUV7PFVOfV5CKEZjUSZl
QnxMJXJ7UlJKRDk+O0VkSSo/ZT13TEtxMGwjTHMtcVZhOAp6NyZ6cnw/RE5CNUtWZ2wzbWR3WE9e
OzUjVmxMd0ZmdWFvb2VydXpSTWAxeyg1WW1iYjMlXzFAaSomYHlecFh8c2UKekJWPVN9VF9adzlC
ci0hcVgyXzA5SHJadEY4Nz8xV1UrKFg5YCtXYWAtI1BjKGJJLVoye2R+VGp1amd3I0E3R1UhCnp8
RVNjXykyI2lTVll9VjhrMT42WGc+dEVoXkk+JTUkPERkWSluPTQoa3IxMTtyeEdka0Q3e2w4WCZF
UERZcjdBVwp6dyVBOzU7bj45VSVLb1A1cGl7WTNgajw7fFQ1I2pMPGxHbWQ3MUxNLV5OI0tzcz92
ITFIfWZJI2B0Nl8oTVEhNGcKeks/aihvIWVBbCkyXm1EaGwkPiVrZ1puPTZMTmNgOW5Tb05XYkU4
JHNAUnxuJVBXMWVeIXF8N0lDenJgZz4xZWh6CnpSakJ5fmJOZVFVMndBaXdLbWZufSthaTNHSlFF
ejNlaGRWSnJ5aEoyMDAtQmU1UiNYYE18fFhee0VhdWckKlRIcQp6TDUqREIxb1dgcTleWXRCLUt1
R2xXNFhMbCQ/UFFYWCNsRz5FMzYpZCtQekJKcDJvKVF5d0M2VT9KQyMhQ3pYTlIKeikmY0hvYDB3
SVlQTnJrSlZtPDFHSD0zQGpLVjdOKGk8MVJHckZ6ZHFENW84Uj5nT25AQ0FPbFIjQnRBX0duYTxS
CnozfShDMVVOd018S21+a0xiWEw9JldyKU5aXnskTi0jT187fUdgJkdKaX1ufE9iNXpLQnVicnZz
Z2V5V19WYW9HdAp6aDdhfSoxSTJeRThXTCFycytkR0dMPzVQNFleOX1Tb0pqS3pMI3FjdldVJEw/
aGY1eW95NGw8JXllKis3Xml+N0oKeldGYUNWWSpmc3xGeHpHKkxNY1FtLWpYaEg0SEg2Q3VYSEQt
blhMTVdZTFg/a1JYMV94dU8rV15XJUJBeXBJMXdZCnpmVDZBcjBTfjB3eVFvZCtvZFlvOWpIRUc9
KH5oRnp4TzNVZU1sXnxaKFAwQyluI3JCQ1JIPHkxVCZ4VXV1NiVMcQp6UEtvdnxwc1kxYyNsZlkq
I19wS2c4YE5tdEc1e31kMyt4PnEhPX1zcTc9VV85Uih2S2BvODA3cEpGKVVydWowenEKek8yMnt3
PnY0TGpNVHxZdzxaKXljcHVDVmxScWV7aEFlYVQpVFNKKHFGVFZKM0x2PFlOOzNhVjIpZHtmYnNt
MlBrCnpGXjQldUZgPSYjeygoYyVzdXV+Z05yXiZJdjE8TlB5RVNPYUpwSjI/dHB5fUx5dG1TRGpm
bTNER18qeGg4UH42Zgp6NitOVzJTd21kNjhGO3deP2hNYlVodj4wV2I1Un1HWERMPzImRXk2TERV
U1AxQjQwSUYodF9NMWYqN1EkdTVzWl8KemIqPjhhPGlBMW1UcjhYYDVDPlZ2cktiMiQoXnBaa2FR
NEVTekBuKHIxK2YlWU8jfTg9X21OenNhI1N6Y0NsIyN8Cnp2KCVEO003RXg8OGApNEJxejJFWEMr
SEtSO09wZmFXRiMzfnNuPWd5WHc5biF2MWFhN1Rjdih0UTUkeUA/Y1dZcAp6N0s2YDNeeF9tVjEh
UV5eS0pwdGdVQUJCUzltb0ZzTiRYPTgxNm4wJjJ1OTlQWCVRKyRmYTE2dVZoT3lZYD0xRSQKemlP
ZEMyM2EzQHAzMD1XMG1gN35STTt9Ylp3c1hJZm8hQXdnc0NoRTVGMmFncE5XVihhZ21qfm9Sajck
ejFZeSZwCnprUDxjQmtGVEdrQkNvJnl5ZzUheVd2d2p4TzZ8O1ItY29+ZGIkbld+YnRCQnQobmR4
Q1hPKXlVaTEhaUc9Izs9Rgp6PUJ0NzJAVV9WXzRsP1NuPz9nfjF4Y3g9dXQrTjMwdUBHdkhnZypT
VFpgTz5haTxtRz11YFVTX2F+MHV8ITA3fUUKekYtU2A8R3QxdjZgcFFZOFFxUUpeRFBfQG5zWklp
UWM2dmg4b1VUTnViO3pTZl5nRDw1ezdYd3ghNE1kIU51Zy0zCnpTKlpIemJ1cmRyV3p5TyZlXnlJ
M3FAfnw3ZHYjaGxYQCE7WChrJHY3enhwUz5SMH5Td2kjKlRhM3B8eUp3NztpbQp6UktfKEYhU0g1
ejlpPmgkK0hUKiU8MVQqbkokdVRObDh9U1BtI0h2JStQdzxkal5vOERXIXlDRmFILWRyTlYyMmgK
ell1elpvWWBJNkdmTz96WS1WSk5BNmdpQ0sweWw5dC13Y1IzTU1acSZNLWFyem1ScDFsaFM9cyhm
fEpuS0h6eDwyCnp6V3VvNk0zZUs2KH1nXjVGcX02USZLbWBuM1d4S0NCZ0VrYHB7RlYpKyQ8ezBE
cVY0R3E+I2JRZHgzaChIekFiPwp6VUBEIVpxR3Q5d0x4K3V0MzAxRVkrbCFia2heRVhae2RDb15e
YFVJSGlzLS1MdmA+fFAkPXtTc1VMMk57cHFUWWUKekZffSMqazlPJnJVeWR2X0YtXmpnRXlET0FW
WTY7LUN9QmBVZ3JKRT89ZEdpamN7NW8xKCYoRHdXXkN6SWQ/OylzCnpET0R2XiRpNExMQlNNVmNm
ezdsblNRJHpDSXRRWHQwcTtlbD9JOXU8RWx+OylJSk9FYXhmMlo2OGwhbiYwM0xTTwp6JDl1OXtY
e285X3AhdDs7Sz5gMUFveSZDM0FBTFBuTT8tUC1ASV85QE89Z3ZRcz47YWM0ZGhNc1Z5QmNPO0lm
VigKendhQnE2K1k+U0xFPFl6U2hiKGIkU3ErQFdlZCR8JFB8V0JFY0tSVHkmYHBHeTA+RV98SV43
XiQqfiR8MGd4MUdvCnpBb2BEaVAoNDkrWjJsU1hobVUmIXtHX1BlckgqUUtTfV5EVTc3QCZJTUZl
MXpCdFVGaHIoTEc2WkpKVm9CdzspVgp6YjAlWnZRSX1hdWNsWUElZkdLOClJfnAxJUBiblBeR1Nx
YnVeI2wmfV83ZVVGcEg8IzBCfCRKbihmalImeGxmNz0KejdgQikyKGNYTHNOK0lldXQ2PWREJlN5
UC17WWtvRXlVRDBjIX49Mik8Xz9sWXd8eXJFRlI/eDllMTdQeWo5WkdtCnp1Yn5IbHU2blI1VDM3
V0EjKzt6fGRrMjJRMDIlY2ZHNCp9KyQ7fCt1WTlRaig/ekprbllQRmIpVnh8TylNX1gjOwp6Wkpn
JVMkMUhQclh1KldfJWAwdzBVIz5rPCR5OXwjP25Xfm5GdnFrenxKUElzXiNuXz9SQjZUPXJYISpC
TWxobkcKeiVNY1gqSFJYbiopRmx2YXNuMn0xZzR7T1JoSkVQeDU3a0Vgdl5YaipGM0BZTWt2Z1ho
JTYlYEFfUzAxPXFYKlZICnpiYUxUQXNPVTV1Q014akwqOFA5fmZea2xmdzhDRDNjMEMjdUZmXnpo
O2FhUzYjWUVBaWtvWispZTI9Ni1XTWh8OAp6MHtWRVI9TkNzbU9mandBd1BlbShxSThXOUZSSC16
QWVLX18tUlM7V3t9JDxvUHk1V2owVXFwP09oTGl5Vj8ySlYKelRleEU0d1MoWDJySHs0ZSRXQjI+
cjZVJTN7KDAxKWNiKmVTam5CWmFrYiY7PT5tV2khdjYrcmVLRkd7LSlJajRXCnpxcWA+a0UjSlFa
emA3dmIoXl8xdUBmX25LdFFAUWdlVmVHVEpETXU0SXVjfWJDYyYzYThhK3lvKjFOa3NeNXBeSAp6
SkArJChjb1BVaDx4ZWc3Jk54KXM5RSpWZGR2RnZuM1ZjV0NzSjdxflM3OTlHfEs8fnlKfWZxKSNA
Q05Aa2BSY00KelN4cCZ4VitCIXIkU3NBUVJ7Zk5BSV8jMTB1RntVYDdAbE4hMTUmfEpaUHZ9fWdF
dXlmek40fTlRMU4/TkxrWmlSCnptb3RkfDNKS1FSZ2tYJFQ1JiY+JT9CTipfJUdOeyoyKkJvIz4w
JCNXbyRkYVAwQmArRkk5O3NGd2g2UVZ7JHgjcQp6cGJze09SXz4zY0NubHdOODghVWtoKE0oQ0J2
b2A8aC1qYF9zbWFCS1VtbmM5PWcpMz1DMUtGYCghb1VweEpyQlYKej5Vb1FFYjw0d3RYLVBVYmh7
SSt7Mj9+PzFTbDxkI0BXRitTe1cmPEhGa3Z3TyFAPFF2YitQbnlZVUViR3syQmlmCnplJn5ySzlS
IUs+cnJwQnIkZTROfjd+blJhQnRSK3hPWWQ8fXViKE1LP31ZcjBxOUhINENERHI3YTJIbz50Nk5h
JQp6YkE2aiNQTjF2Iy1GaCN7PXtqJm9sd31wLVJ2TGBNe3xyLSZ3eVpHbWkmMV5kaDxwYzlKaWlq
N0l7dklHR3dYY0kKelBNQXt6NDZxaj1PMlg7fjVxYik5UXIpdTl4ITN9Tmp9MyQoVDQyPnZgPSMm
UnkkZ0t1XiQ8NSg5PjkjQW0mJWVsCno1Kns1anhELWM/a0VneihOM1VtWXt3ZHZXKTtFcVQ4ZWh+
azd+RFk/YHxuRkMleXtHWllmRipCTl89NSZII1F0egp6VSU5cFZnP0ZkJVRwWXFvXy1+b3tZd2xS
b3tNJEo8SXg/YjI5bVhhcjNsI0gmanREazdJeDZZazlISWJRPz59OHkKenYoR3dUb3YydW9vQmRW
aXR9ViZkKXdUcXBvMEcpclRWZS0kYkNiVlVUbUw1UntMdmxjKkUxU14rQkVWZDVtOFc1CnoobHl3
RVBnST97IUo/Xyl2JDY5Z1IwcFRIdHFPJTEzcmR7NkIzNl4xYHQ/ZyVqPCN6KHo3NDF2THp7RFR3
eSp3dgp6WUlYOD0mK3M8dXJeTjlHd2kkJnEoMlJCMkFGVlhgbTFPTmEwV30+WkZsOTN4OU1WKFYp
fC0hdjFzTjVkZ1U5eU0KekYrZyNsNTU5KipRYWFVQG1GKFRNXz14RE5LMllNUFBjfCFpM19BZk5V
QyhlKlBlKkV9TylOO352KW5xSChNNGF9CnpSe3ducClUMjlNYDFnO1dDSns1Mm84czhTZ0UqP1dw
ezlBaHJZK3lOJUY0PlYxKkgmPj1DRlVrXitScCMlRkskdQp6eUckeGVyc3ZHaV45SGpsXz1sYjJy
OHIjSylYR3FlRz5HWFFZeT8oMHgjdFZKYCZPOShAandJe0k4OHB7aEMqNEcKemdlM1BhKmsheWoq
TilFaWNsfC1AYy12TjxUbTQpWSNyWmdQdjVzLXw2a2NGNzhzIXM/MCstUyhhUE5sPT1vYTQpCnow
OExXOCRyNitBVyo4d3t6Yz1JdUpLb3ooS2UrQCZNaGlGa18kZXpkeG55WURXbzlNLWJyUCNGNk1G
NjcoMTt0LQp6NVN9NjYkT0olKUhDNWpeO3E4LT85Uk42KmEqfVhGV2EwSkJYOTZQdSppUkMyJERr
ZTw3IX1fKXttPSkqaX1oXncKeiVTP2pEbkhAYG1Raz1sfVUoZXUrYTs9fTRlNTF6WkhYS0d5Q2tA
TlR2cHV2MypoPF9NWHctMWxZa2U3Nk08O3ZiCno/P1hZVWU3PkBYKjlmXilWVjgjVU5wSUx6LTxt
dHE7JHhxRml+QEYtVGAwTXQjayExc3t4fDUpckdEJE9yciQtcwp6PnJVUlcyRWprYiU9S0htZjtm
PFZkdTg/VE93c2NRTD4lY2ZKK1JBM3M/PGIydklyMFpfY34xKnBrRmVlPD9teTwKekNAbzB3YE9C
dXkrXzkxeXZzSiZVX1drXylGNiQ4amx+d1gtY3FEZkZIViVYRm9+PVEyVyNqTnpsPnFFN208TzAm
CnotbmFwYipSelZMWFQ7WSpXQkpmcVVhViQ5WXE5bXR4WmZENFA4WVJHTUsxKDIkYlVwe2VAYXtX
V1pDaWlxZiMjUQp6ZV8kRyV6KUglNkhiYlJqZz18MmlWP3dnZFIhWlIpcXpuI3BPfEEjbTVKN3ZD
USZsZUxsOE9xdHlTZjAhcVc2bkQKejFhKjQpTFglbkhxSi0odWkpe3B5QHY8bjcqPj9UX3lJRj4t
cFRsXmUrWU53Ul5VYjZ7a28kQj1ITnlBTCFXXntECno/OytQRjB2TTYyYDFOLX5ZWXg1Zzw/d0pP
d2BKajhfOW5nJkVXaS05eDNeYjQ0MDckNlNqK0k5ZUYyci04UGxpVwp6aDlHSyV7aHpuMEd1JjM2
U3slTEQlKDxIUVcjOW5WUmh5VENfRi1jV1NydHkrQ057ZHdgbVF9d3E3ZSlGO0crdFcKemowJX40
VGZnalJTWCFVZyg3Pk1oblZ9OD1wYjZoMWI2Jk4jdDdAam5wTkMofF40fCo1TGxGbFo8ezUodzJl
T0NiCnprOHh3OzFJSDB7YjwkKVp4Xz09YEx0SkQ4OHlnen48MEpwcDwxPmA8Zzx2alA3Iz4wY0Zi
fjwyS1Q4VWBGWGEwRAp6OFVXJTZhQnRvKyMmdnw2bUw4I1g8V0V8NC1sWHFaPXFxb3hGK3p9e3Iq
c0J9Tzc/aXVRNUpEQGZCT29Ne2lwV2QKejl6VHxMaXxVUyZrSWRGUXFgZTdzRlBSVXxNdX4jZClf
dih4I2tYZyQ9Sz5DbjRLaSM3djQyYlZQLUhXSmAhcjwhCnorQSN+N0Y9Ny1ue3p8QnJHYSEhOUQ4
c0wpZn5NYz5fdClmdWM5UzxaSHxsSDVNMVZVYTZWVmJ8SCtoPFFTOzRSUQp6Nk8qfmVwZWkoWVhZ
ODlvOHlmXzF4R3UlYW95PD8pVHtIV34kWXs+NExYP09hSTlCQm9QV2k+Zm5gY2BtWW1jeiEKejU3
QjQ+I2prJntQRShZd0wxd3BTZVVAbllXZT5KOyopIVAxMmtpJCp1SHktc1YzOXRjSmppfmFCWF9j
QmZuOCpCCnpBeV5taSg4fkkoNH18VCpEQk81akdpS3A7dW4tJW8mOGlIMTB0VWp1KFd2bjcoQHdY
SkVaNDV7cXEhcCVSRHh1Qwp6SyQhfnhiSURPS1kyZCtSUzY7ZUBwMGFYaVJ2SUNnY21uYDQydnxw
PDljK0huJD1oZ0w8Q3E+LUZPc2pBMkJveVUKelMmOXheMipSRUhYZlpkPkRBRENKITszQVMwQi08
Qk42JnlEbU5qLTdqPCM+Pi1UN2FSI3c7OW0lPmAoZUZWbkJGCnorYUNJRU9pRG9hRGhqVFgwKipw
RygrJW1oZUwoQipSdTktaT5JMShzKU0yfTNzbClgLUZuMk13d2pYbk47e1RXUAp6YlI5TVBKOFch
bz1BPSNkKGV0aUBGXmUtIUNAOTxVejhYSSUxbXk+QW0zM1U1Xl90UU5uaT9MeWx+LU5PI0N3NW4K
eipGRXdPRDZXR3J1NERmS1didGxtM2NSQDZQJmp2dXt7UyNrZTtzVSYtM35oR05qfWYxdVJrbD0t
Z2VGfUZrTWR0CnoqPEomQDBaPlhIezU3UWl6aGglUi1gfm4oUTJhUkhYX0xiUyN5QUJWNyZMNVJt
Kk1CR3JnbW15WmYraUxRIyY5SQp6WDZoQmRwIzxXKmBgfCYjUE54NH1XRVEqI1dBVjE8Pn5vRzgk
YVc5ZlY3ZylJKFJfTjQ9RGhSIWNYQGFWRk1BKVQKenRxR1dwQDNXSn4lVXl9aTBlZjg/TmE2dzUy
Zl5fNzhnOWE8YjNKR2EtI0xXVFRLY1UlN2JtQzUtKEt+Y1dPdVNSCnohUihedENMPUh0VnEjJVVe
VTRaNTwhNiNUU3paYnZfe3dUQ2dibShmZmlhaHlNcWJOZyN3Qks5fDBLJj4+PHI0dQp6JCl6KWF4
aj9GdHp5bk5NJX1uTjQ7QmlZRCtIPnsyb2lpYWRwTklLYFZGP1dTNTE8RmMjKU9galo5TG5Vb2tj
YE8KemxZb1dqKzc7JEtCaD9zKE1uSCU9SjtPPDZedWg1S0JrM31MP208bVpsaSFUejgyaU91UHdE
S2AqY3goZXxLITZ7CnopNHZWbjspPnp8NEspKzgrWXwqI2d+OThmMWpfbUNVXzVUTlRNbldxY3ZO
UDZjVVhNUHxFeFlFZ0JgSElGbjB3Rgp6LXYhNDRSPyg5KDxNfn5tYEdYZm9eayN8MEd+UyMoKWNi
TEVndmBIQjRuZFlneTU1NiNuS0VpJGpNZ0MhaippQ00KeiNaYlR2MHQ7cnxGbk15JXNNfFFfRW9h
fjUobHsocm0oRHBhSShqWlJ8MDU3UjBrbyNrLSNDSjhrI1Zqc3NXMDQyCnpuNE50ak8xclFmMHYz
ckA9anZ3NjtYMHlwWkFTc1NwdENKYHZpeGBvYGFfdFheNGEoKSVyYyVGV3cqT24ka2NlZwp6YGNN
SD5zcV5RPVV6aCZWZkczYlk5UWE+ZyVeVnJnY2dkMSpuYmt0JCZScn5zMk05a2I4cGFpbEtxQzFz
JlFBe3gKempMYmJURTB9dWs4ezM9dlEtczBMP2FTME9OcUJlYiEyYG0paW1NfUg0a0x1PGxVX259
bVdiNklyZiUxeE1uWiQlCnpGekRWa3wyJHE1T3QpKi1qRXA/SkpwJXlJQClsOE9fSjQ+O1U0cz1j
TVRWd0BqdUleX3s4dXVQJjdPQXxMSUhlQgp6UzF3M0gwTXdFVz5hUndoVmBAdHFfYT1MckUkeTl5
JmAye0dGamBfMDcleENhKEtqK2BAY1IrakYmOCp5P3A7aFkKemFHQiVMYGVZUTB1JkhBTFIpZ00r
RFREYGtjT35vKTVkYH1OcUxKeCpfZismKnchQ0I8OTJ8NUY0OStpX2h4Nm8pCnpKMXZtREBHYyFK
Ul4+Slk7Q0dUa1kqNHp6TmpGMUJreStWWnhHdFkkRSpnenxiQl9wbm8xNSNwUHpYbThhSGlfJgp6
TlczREphPSQjZGM3RDFMZmVmNGt0e0lGaEpIKyt+JHd6fEh4ZUI/cVQ4a2JyU2t4fGxeeFBiP0t2
Mjl+MV5vI04KejtuWmcyMGVlUDBgVVRmPDtIWldJSXRNU1FQU3lwbTh5RDVXQ2N1a0poKDdyYkJw
UTUkalY4WiNBKUZRTmNZYVhhCnpJNWFtR1dYTTRzZTx6I3pOJHVoeDAtIVNhenk+bStCXlVyY2lW
RiVoRCFGNCphODBGdzJaYzhHd3RNPEB1JXN3Sgp6UnlCbDFmdVkpMj9tK2wkU1pEUW5LTjRmdjRa
b3VsY0VgI1khTkp1e3FlS21lcXlUKmFLNk53Qk1gKHEhMzNwX30Kej18KjhTTjM5STlkTiZVZzU/
fjclMERDYkM0RXIhbXA7NzZEelgtRmU2Zj8jQkh9fUZpU1VAU1goUU8zdkd3fU1FCnprX3BUcVp7
cFAkK3wtUXMrX3s7Q2hLNTJ5M3BSWjtpLVpMQWxOXjl8M2xSU1FIdCl2QzlVan0mKXhHRnspc3sx
eQp6SklNRUFLX3E5O0tIQ3V0NExAVHZGfkZYOSl3M0hHS0dTK3V5Zig0bHVkb3d8QDBMdXcpMlM3
ZHt3ZkpaZzQoKnQKelM8OU5lMWJXN1BoVFJ2PTlHUkgjZUlkI0FVUVk1bGImUlQlWn5RQkpWWCow
UXNEejZMN0xKeThWR2Q+ZXJya09lCnoweWN+MT0xQDtzc0ItVlhNLXIoaHB4VmMoSHp+JDx6VkMw
N20hZEI9JTRUTH1JPks1OFBzKXIoU1lsTFo7eVM9Ygp6JF80Y3d1USNuMSYofTNBeyVaUDZGUmt+
fmBDME1OIVEpdHxaR2ZTfV9BemNmSiFNPCQyYVVzdWE3eV9PUX5eQmQKemhUcnpkM2JyP2BudkxQ
b09XVGc2dk1ha2pXPklhe2ZYVzJlUE9eTXBRQHs+Mzxxfk9ESHtTeiMybCZCSUY7UU11CnomfFQp
ZypjJDJiJFBZOHgxRDlIa2hmc2pDZTV8Z3AjdGlOMDVMcWhTcSY3QXpGKjctQHBGM1pPKkdpTTxg
QEtXOwp6R3ElbG8qdjZ6cGhsZHVGOWx0e0sjM1ZSfWtBZyUre3x+PzxeUWVva0BHezMtUDB7UjE5
SkpzMVctUkVLKFlMe24KemN2Wl9KdSNMZ09MPUdVN0FRVz1+cjI+aWJhSzhXdj5JZERNWCowXyEj
fHwmUj9FTWFRZzRtSSZzJGN3b1dZPCtACnp7M0ooRTs2X3g9MiE5azhNTDVnPTBIVXZwWEAhMFVM
MyFmcWJAQ25yTztWJlBaKlNfKyErMFYjTk9nYzkwQ1Jedgp6YXFhRlA2eHU4QEBgcVBfaCp5MD5q
T0NMPWJYKFFMQDFqYHwybVNyX2lobFhXPU0jMldHdHRYPXI7LVcxQF5BQGsKejJ6VWpsT35QfVZI
M2VjT1pNQEdhO3E+KWxLUHhWN14xSlQ/Y080eCZjT0tlPD8oIXs3OXtTe2g+KUxucSVuSiU/CnpB
ZXorQWhRRm0lbG09b19LVGxtY2IkRkcoezM/ZmYme0soIyRVZXVPakRVckw8Y20lTU1GMl9ZXjZt
RUA8I1B3dQp6dDAjKSY5PVFaZXdNSGdSXzlAX3wlXiFUJGoza0pVJGU8PDZpO359YUJucH53Zzgr
SXUtWC1FbmR2cUVWeWclT0kKeiVhdWN6anEhWWhKVEJtel8oX1RgZlprZU5sU3JhJXs+I0AyS0pM
UHc4fnkrSTt7UVIoS2oyODIrb0xTaSV2cWlTClA7fTVDZCltQUNGVjtTOylIRSg9RQoKbGl0ZXJh
bCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9lY2xpcHNlLXBvd2VyLnN2ZyBi
L2FwcC9yZXMvZWNsaXBzZS1wb3dlci5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAw
MDAwMC4uYjQxZTVmZgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMvZWNsaXBzZS1wb3dlci5z
dmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmci
IHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48cGF0aCBkPSJNMTIg
M3Y4TTcgNWE4IDggMCAxIDAgMTAgMCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tl
LXdpZHRoPSIxLjgiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3Vu
ZCIvPjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzEyOHgxMjgvYXBw
cy9lY2xpcHNlLnBuZyBiL2FwcC9yZXMvaWNvbnMvaGljb2xvci8xMjh4MTI4L2FwcHMvZWNsaXBz
ZS5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMC4uMTUxMjFjMDRiZTdhNGNiOWZiNjVmZjA5OWQ3NDY3YjQ0NGM2ZTkw
ZApHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgNzA4Nwp6Y21WO2c4JktxbFApPGg7M0t8TGswMDBl
MU5KTFRxMDA0amgwMDRqcDFeQHM2ISMtaWwwMDB8eU5rbDxaYyUxRT4KemQ2LTwpYj5NJkotZENA
eHlMd2QlMl8mX0lncGs7Z0ZoKVJaZ2JqOEVqMkZPLT9IQzdkbjJobF44U245WT05NVYjCno2TXJV
P2NycjZ5JG1pSTJhNkZGVUk1T2l2ajJGT1F2enZWcGxGK2BPbVVea2ArVE9lTyVwYjMrKW9MfERm
ViNSYAp6cyRZTXZLZEhPQS1tNz1jSkA9ZSomcGw3NUY5TStLYGApQzZCc1ZBRmhgMmVqWVNrKlVh
Xj1iWjJtbXdIN2NgQTkKeksoS1A8JTMjJjFSUitmRCNeTDMjend4Uzd0SVVsei1lYGIkPzlZdWd4
WShJblpAc2xgKlNjTHt4dzZMfD9zSEZQCnoocVdJQXk/QSF6PlpgQkwrcldEN3tQPnB5dDUmVkBI
e04qVDBsIz1YOTV3fiQ+Kzc/dFNGaVJ8JjZsZG1INk9VPAp6bHBXaSl6SHhZSF96amhFZDEpTkc8
RDdIZHM9Z0p+O0JjTSRoKElKM0YkSFZ3S29IbStWTEpWTU1geTwpJElZR2gKeiZARGZfPHJ4dkZP
JCpaMypKb0MqVWhOTGNYPHpSZlIwWno8WSFMQU5FM1A8ZSlBfXYlOVVkQ0d2fEs4bT1BRTw3Cnpk
QXhkMXQhbF5YSj9qeVFSMFNlfTVyZWVgVzM1WVAob2VOQHcqVEFsejRMJGtQeWc+SGtIbTNlVCp1
en4qS3h8JQp6Xnx1Q2FzWkAkZlI9KWpSVGVvZmZSNmR1I0lGMkg1Jlk9bmp1QnlFdmBfNENNYkp7
ZWdIYS0ra1JUVUh+MEBobEIKelI3JV8wK0l+NUE/JWUtJSQzMXRoaUp9Tz0wOzg3cSkkKkRJUVBW
c3ohc1ZBO3srNWt2Kk1CODlKYlhjPVFvKll0CnpNcSl1fiZkV0lHd2tpOUFiSEZgSGxtWWVYSDgz
S0NWTXRwP2ApP01YYyowbHlgRGckN0VBPmhyZVJlZ2stV3QzWAp6WDt7R2g7MllvUXtAKnY+QD5s
KSt5UlIjayU2UnFPN15CdFNIPD4ofl9nOypNTm9PKzVvT1I2MipNSXopS2x8VigKektSR31XWk47
emoyNGlgKDNKP0pDUnF3cCY1MXhQYXNxWUxBPCg5QFNSJTQ4KERmb0toeSFSNT16O3R4QktZeis7
CnpyKyltMHxHTjVLVVpvUGU4VT9ULTtAKkQyI1VJfGhlIzVzJDNkSi0rRUZ3KkJlaE58NTckcz1R
d3AzMTd3Q0s5cQp6QEE8e3xSTWk1OUcjd25PMHQ4fHR6RyVlLXBXRDI3JVQweDE1bz9VMklxRGsp
PWVAVHJFaUxyK19JfX00NThpVz0KemBhQEhLU0lvfD5XTXY+Q0ByNWZjX31zPSNue08lPGlfUkZN
M1JiQ2xEOXZONDQ9Y3VLcDsmYUFIZ0VwZ2cpMSlqCnpvUVN4VXRiOWY1ZHs3MUc+Kzc/M2I5ZWxR
RD0pcmc+KmcmdGx9YVVOakc1SGJXUnVzNzctTE1TUkVvRTUtZzQ5MQp6RlN6KV9jWE1+IypWbEpZ
RUImJHhQeiZgd2M9PVc1elBOdEYmQmJFVEgtK0V1aCV2PyVpJCVZMiE7OWJrO05ANEgKenlMJEMl
Y1E3VEdQPyhCfUFvQVZzZXopVXF7X0VFczl2bTF2TDV6NXMzcCYjVXVpbCVrPyhYJVVgU0tVZXs+
Vm9ACnpHT1ZaeXF2XztQQ1JCaHZ1cz00Jm9wWiluSH1CbEdeSUdSISk3emhCc0FfREQ0VVYwQT9C
NzU1I0d7fF4tY1JUaAp6OXgkVCZ6XihATy1wayV8TEkzVk8qRzRYT2glX0MoWD83ckRCTnd+PS1G
dlI+ZCp8aEUyMyszK1FRSmZvel5FJEEKem1ZakMpLWFQfjdBdkQ5aT41RF9MR2tTVntgYEZxaS1Z
Zz1KdFEoQjdwOVNjbiZqUzlQN2hVcD5kflcxQ01WckUoCnotZElJX0s5QFdIVF5DPF5EZDVMRGd5
U3VNdkRXJWlQZE5HNDFPMG4xWT54Z1QwKjdMe1haR0NuXiFqSnM+WU91LQp6dT56d09wanZ3NWBg
KipIeXBTSnh2I004YCFhb3dRVU9rMDt7KHw+aUB4RW4ldWdWKE8tdlJfY2VEMVFkenEpPGYKemp4
UmR6VkBaRDJXY217dVZ9ZHp6antFQlVrM2FrKyN3LXwoXiNQbyEyRSMrU2NSMSZlWDNUI2lWVnJY
ZT1rbzgrCnpxIWUjNzk1Z1Uke2BIeTxkfCt3MFR0MGQxQDB1SkQ3PVV1QWJuP3wjVUErWCorQjlH
UT96LXpQMUYmKF5fNyU+Iwp6THRhWDNHT2NqVnhuUyRvTylGclolbmlXWmNpIztfRmByLVZvbnVT
fD5KZiNBQVItdUo0dG1zSGNPKVNxPllaYUcKelVzdytOV0x8VWZ5cz8mMnNsMyNBOWspcWtgZUpI
PVJQZiN0I1N1fkxhTmdsLTcwVDJLN2JVNCQ5YUU4T1pHYWlDCnoyLUVrQGkxU0xoUjZmYUFpKzlQ
IWdNajJDY15Bal88YkB+QVFQdHxMbjRURDg1V3FQe3A7RCRDTXxmanNYPkZ5YQp6ci0jfHlHZFFO
QmxnQDBHYlNneFE7OGR4Jm19MHJpTlU9ejZCK3Q7JEZoaiNScU5vQjBxdnxxIVpLSjN2UTU0Tl8K
emFjbzd6MHM5dHNab1QhXnRvTHpPRXQ1UHxTTlUzfmphdWcmYEg+TVMtcUZfNCZlRFpUSU9se0RT
dXVZUjNwPV88Cnp0MXlfKXYyQUY4WkcoSCttQ3YhYVR3b313UCpIYHpsNVdpfnVjd1BzSjM4NkJj
UTFHVGBZdXZ8I2ZzVENFaHpnRwp6VnBeZWlANEQ4a1M8PyNTVWAoOTlZdSZDO293bE0oOH1XKz5S
dCk4K0xjVWxlK3QkViNten5MRiVnKk1LZy1lKCgKekE9YEtDPGxnNj47YWxzVTxJIURQZDJ4N3ZU
d0xiQnA8TWdXM0sobjxrUGcjMD1hNUorQV9UXmd2WDs7V1NkLSspCnpSSHV6MTJueT03Yj1+alJy
S3VAXnE2b3NDJHt3cmU9PkhvVDBqI2tVcVk1TCVCSiphPz1JVEdaZ2IkdXw5P00kMAp6Q35leHhL
aV9kRCpGVzxwX3dDLXNoJTE5d05UbW88bWUjUUNmS05ESGpIO1JsemRHdWpEbFUjRiN9T2h6JTM5
SmsKek1IbURhRzFFZDNIMkRobFJRRntueF9fb2B6dmFYUiNUckJHSiRyfFRTYXxIUWVEO2Q+QHU2
a3NhOW1ffj44WXBxCnpAPFg/QiVacEY1d1V8cHhkWUI/QjtpJWJHKW51RjZBdXUpKXNCUEoqUUhm
KEphZzI9Jj1eI1pXMnI7SXk2PTVSVAp6UE1jSigwTEVHZE1ASHlNcn1AR2FTOD9xaHlvRVZNQ0hM
c0ZlQzUlNWBSMFp2ZDh3NGcxfVU8Y1J6VUhweEkrfjkKenRHYj5zbVNMbilyVzhlRlFYd3M9NUR7
cjtNSHRKcFB5ajIyTklpbz9MJWllNnYtdDg9Uzk1eCo0VzhNK3pkWmRZCnpII35obSZrVmpxNVFN
YWFFczQzRjFmZnJha1NLJHE2ZT1ha2FZUXl1NjklYmlwIyUtRDBEJj4mRHJLQDV6SkIkYAp6YDAp
OEYzRCQwPXxIWUBkO3B5TTt0cnMyIzchYGI2QyY1cEloflUmUVRxPS1CZz1FN0ZHQiQqNEsqbExS
VnxmOUEKenZGdDYzYTdORTh6V0ZEQSR7OElxKGNlQUpWPXJ5ejt9OEZ3TXxOJGNIUWZSKnJHZyll
UlFHdDdxNilFaHcxcTdNCnojeCNmJDk0T29Vb2p+MXBPZmBZQT85UyhTKld5JDcpfjd5QSt3TExz
IU48OHtfZzRQKy1yTUxlNj09KH02OHB2dwp6e0NHciEqZ0oreEJWQHhDIVhUTFBEUGJibkhzbG13
dCkpTWc8S3hURDtwX2tMS1QmKms5bGBjfnsmRCt5SzY+d00KeklFOEV+LUxTJjFBcVhER1NCaGxH
a1p3U35weThIJHR1Z0ckNFJpZmo9a2EmZmYxM1FgJnl3QS1oZy1MPTwzc25YCnowZmYtbng7YzVU
bXM7UkJRZ3NqO1pJUCo9NmQqOCRKO2VlYUpNJGNGYGpieUZed2BzTV55Z1VmKHE9eVRvNytlawp6
aSF9entWNThfejhMNT0weFZXS3xwa1dqczVNaUtGOytAQVc8bTtGSjV4TTYja2xpKUZMLX5ITHhu
fldDT2wjclMKeiRkYC02Jk5XUTd3SU1RclIpcGE9OzxUPH5ffng3YjFMZF9aVnEoVzBhZVV+V3BF
NnUyKTAjPzg4PyUyZjZlVjlOCnooVmw2PVB+VXEhayEre2Ywd0BBUi1qZllkZURqPSg9fU0oMyNX
QWc2bm0+S3VQTSNsbGlFTWFlMnA8eTEoME5DcAp6UXJmUj8+UW9Xenp3fXBzOCg7K25xWThnfV9G
R3VpYjFlT1pKVG8oYHtLTU1FYE8qNVBYaUdQNHNQfGVDNWhgJisKeisxZmZzMklGTmJRKT5hTjIh
bTBET1huPSk8MHFXWFBebXlSTlU9RkwkUEpJKExuPXQmOHpPO25fekA5YFFSUj5xCnpyWTRJNjZg
KVNMN2V5aVZOQG96Vj5XdVU4cz5JJllWZ3ZyX3NyJVdVQTAleXFZNDd3TTREVVVxc0ZGQkBiPXgo
JQp6S2w+Pl95ezx0NEJaaT8kblU1fCRvenVII0Y8ZEZya3FVV3VfamJPJnt6KT1ucmVWXiVsWkEq
LWokPmx5c01jJUwKelQ/ZUxRM0p7Pj1WJi1RJV97OEVmQ2BNJXJraXpna29fbUJzckEjMFY2UU5F
amljKWdYbHZRQygkejhUJCRqMUBhCnpFSU5nRyo+KHpYTUFvS3dWJkVtI1k8VkZtI1g3PUFlK0B5
MVQjVEN7TjRNP0BBVkFzMiV4VFQ/e15PVFlpWHU9NQp6dD5xcyNLMH5mdEFTTERxYl5SdHJSaklo
Q05mVkQjZlhTYk1qMHBMLSFYP0tZJiFUSj5nKllORGhXX0ZSS2lUcEUKekNQKkY4al45THhCdndH
Uio3TGMzVU8tVXFFUHopZlozMz83VTRydS1SaSFsdWAxUV9CeWZEMCVtWk1NczBHeFV2Cno/P3s8
fCQqTFV+RldYd1hfcXQoM0Q3Yzd8SjdANVE4TTcoR2lUTzdPY1dtRT9JKWBiSDlDX1ZRbDR6akxB
SFN7Jgp6QVA4bWV4TTA+aXg+NnlMYXw5dmBSIVpFcmRtQ2N5NXU1bVZCfThQQEJHIX1vRFMjJTxQ
QUhaKUEyUyF7ZUtILTAKeldrWVV8YkBAUjtKTX5wRlE7RX4kcDQ0Kjs+fFlUeWlCM1NXPTtONTNZ
Mn56ejkhaFp4cylXWXleaVYkfFFIZzlTCnpqWFIxSkt2QTZjU1RqaWpWRktDSyU+c3hCQ0ZlTXl0
Jjc+fFJ3flljQ1dgVXcmPnJ4T3pheXowY3dnVTFhOWxtVwp6ek9UdDNRcGVKY1paZ0pGJjxYJn5k
KURXTktwTU16eD9YclpPcCsld2shPFQrNmVec1U/RSsxPFhjP2QhJDgwTysKenN8cyttQm00QyZz
MFZkWjAwamFnJXhoXiYodz9kYWhKdVMydGQhcz0kXjlQO2ZnPzh4QFQjPCFmU0t0R3ZHPUdaCnpD
b2VoMmg+SXtINFk0MCNzK3NJVys8NUEkMEJMTEt1JkdmQzBFK1hEdmlGejxEMzU5Zz5LZ150cnps
aU5kWG9tbQp6a2c+dE9EajEoQSM/Yyk2UGZYSUs7cWJyZjZ4SVZNaXAzQ0E5VVV+O3hAezF3c2hS
Jn43KzdzWVBgQV5LTzlVeUMKendtREc4ekpLRUVENHFiSilkV2Y0Qk9MWCFmQi1VQzdJNmFFKS1N
c256Nz87VTU7Iz5kIz9sXnlCO0NvSClTSjJ9CnpmS3A4YnRFVWpoKXBCXm5kciF0I1dgPnorU2FA
YCFRMV95Y3k2cEBTNXNKPCs5OTF3WCltfVlIM1NvWHJJfiprPwp6VTxYSTVqVlVLNUQ+fGk0cHBq
JUxjejN5b204dVU9NEZ5bGtjRzdlSjZZNmFOPmdvZVQ+ZSo3dlZLZlE8MWM7cEQKemwocmRJWW1k
ckdwc0AlXi1AfCQpZ1heQXVUe2tqUiU+Z04qTmhXWWZZYlVlUHR3aWROWUNEa2hFM1U2ZD5RKXIw
CnpDQEIldjxfOVJjQ15Aa3pXJCYwQndzMi1nNTN6RnhIZktJY1B7MF9lKUFvPmspTk47d1MwIWFF
RkJGRUBSVm9tVwp6Ryp3aXVxe01MSGo1I25WYExGNE5ISGtSdEM7b2I3MHVAM3J5aV9qb1JCa1du
WU9AQ2NpZ0NuKy1FKE05V3ZDcGIKeih8fHlBezt4MGxFNUliSG9kNlpAeHAhYkVSdDRgQktgRllK
QmB1d3QtISs/eGk7dWMjS3VKY3dzbjtnYUcxUyVMCnpQPSQ9S3tBVFlDMkJII3kyd0doYnZMYWtI
YC1KM21efU1KQ0Eme3dnTFNKMUt6QHVjVzxAdTM4OXZSd0FpP01rMQp6NyQ2c3dkRTFPUm9ZS31x
PV9zLVNOQER1MG5WUml6Yj5BSz8ycW98TSQ/aT45NytvMlJ5d1loeUs2Y3leeW12PjkKekEwUi0r
MjZlZ2podXtRR3teYEFYK0hBbmpgP3M9Z1dTRVIzJlklVGBxQjhHMj02RnRQcEdvbTN1bVdDe3RP
LWJzCnp3dncmQzNlLUlqcShJNlRjMil8a2VyV0AoQ2N5Y2AzZEhKWnZuZjg/ZClrekBQTUtfIXEl
fmVvRG5vZStCY0NhJAp6I1BxNlVaTkx3QVpEM098TjRqUE9SMllpTlRzQzdLQDBAdSZnfTh6fTA8
Q317TnNCS0MrbysoVTtxWCpsT1dqYyoKelo3aUVoZEghTD9UQyZGQ1lLdWIoVyM/R2NkblU4UFJ3
fntmUTUhfURENjQwN2tmQTQpcTJIQzBYbFJQQT1LdXckCnoqRFR+elh9Mk1fPntgI2B4amtlaGkz
a0tKST4mLV5tY04qUDdMbkZ9JEx3VUhCO0M9QFprQF5jWGtAZ1peaSgqMgp6UHxybHJ4STtDVzFC
Y14/fEYtNEgoZXJFN0FzbVJ4VHJzMVVQYVMoUWcodyolKDtiNlFALVl7Kzlte1RDVlh2IUAKeiFx
b00/a0pvfUotSHFXPz0/cWYqVnNIb0YrcXNTfG5AWEJPRHArN0p1SkM3YlBVVyhtMT8xIUQtOGps
MzZudzxfCnoqPDxKcUdDV29xcGpDbj8td3I/SmNlTGdaZXI/LVJKZClvLXk5dFBXdlRAV2BSfTI2
OXs1U0JYal5uMVM1P0YqMAp6QTh+cjdueyVfcmE3VFV6cTEzeG1AV2YxVEh8dU1VNmVTUiQ7QTF8
cz1AQUN3R05CazspZ1AjKyRCT1djPElteXoKel9Tc2I+bV9FfSVQNTM4Z0k9UWxJSzVLSEBEWEdK
ZmVFS1ExfDRkPHskZ3pqM1Q3am52Z001MF5CTiZwNVZPKDx4Cnp5KDJXMVohS0VFK3Ema0drSVI/
Xy0lTVdYemNiPF4mVFElQ0JpJCEoVFlmdVI7c1I7MGIjP3A+clVESVBQaChaTwp6Zns9ZTcrUUZC
JEsyQSRAYVVgenBBfTt3RGdZZmtRWnskUEFvSmhle2FNZVltTSNFRytgK3wzQFlANXdUWFBtJW8K
emA1aW5fOXdPVFNeWnI7R01nYnRQMWw+VyU1QjY7MmhWNCgjQjA7czVGbGlvOUBzNl4wZTBsRWF7
Nis2X0dSODlFCnpCQ0lycUhBcUlpUH1DVFVAYyEtdlQtQ1hOZTtNQSsxRW9FKkhKST9CMFVzTFdS
R0RFenpTcUJqcUljWVErLWI+VQp6Km5JTW80VG14aW0kYERyMCMwZV47LSghPmJBTjYoZmlhfHd0
XjU5WnNQNSlMaH0wOXxJNUYodCVGYlRxcmRzJkgKeiY/WCkoNDx2YngxYHxGc208NmNlTkchcFJf
SE4/KEVzcnFiVnA+Zj1NU1hQI2srMyVedm1uZyFjTUlPZ20qJCsjCnp0VzxgUHhJJGM9N1YyUldZ
OXJwRTZuc3BGTz50JUNkX0ZhRTM3c35ALXcoZFhCanRncio+Nmw1X1BLJHZEJjAyWgp6U0hydXdy
Z0FAaktJYVRoWnxQI2RtR041YklwfHspYzwrbl95czNRX0tpPDJFcEFLIUt6ZiF+KUxzfD8qNHNY
fHUKeitHdG1saXUlIU0+bispdG9TJlZeYVh8fnVSKStjVUBLJCFrQzBmS2JPeWpGVmN5OGQhaFlN
M2R0VipYMSppZz1LCno/WnlaQTxnNjN2Pno8RUMkQF9UcGJwdnNrdFBTfFl0Ui1DNUhJRi1vY2tx
a2g5anFfc0AhbiZeNUxUNjtfUihyOAp6YWo7SispJGNXMTshel4/cWdHfjRzK0ZAXng+Pz5iZ0pY
alhNZW4jSHprXj9uPzRxS2NtV0RJPzJnPGhMZTFQI2QKelJhenYjcD9yMWMpNytjZSVfbkRfJGtL
RU5CUik9aTB9JiRjRFFhU2R8RU9tbm12enFMJD5JUk4mRnwqUDt2bX45CnoxeGkoPXNjcGI4IWkz
PnVFa2hBMklRQkpmNDJAeFNzKVpCN2MyM1E3dV4/PXYtNlQmbmQ3KyUrJlhIWF9SfmFUUAp6d2lA
YStsSkY7eztTflVxayFPSFQ4fWkkY2VqZVg2ejxhdnBhYjtJOCRFSTIrYyRYfDFrdEJ8YWFaKndB
aFVeVF4Kelp0WT5uU0orZUA7ZX1GO2I+JHF9cWF1NmJHSTx7LWorXlNKdW5hO1ZMTVdEMll3NUJm
dnd7cnNRbXlvY1MhVVl8CnpFeWgteFVNTUBfNjJCfC1eSSZsZ0NIMXNRKCg4OVIycF5gMjA+SGs2
UUpZRHUhVDtIX2spSUZtPGtIU0x5c2lDTQp6PUF+TVJARCNuUCZpUDZ1X0VxSChQRTVENkd9RDFz
Q35DfXppXjtpfHlwSmUoUG95NUx6QlZPPjdHcjQ8T0RLaV8KemdCTUstU0V8P1hRZTVLRShmfCg/
X2NHdXJXVTg7OUVgcU55ZXN7MW9qdDRMP2otK15eQlM8bWlCRUhrVmZpOzhNCnpJNSpxRiVDPWM3
Jjl1e1ExN2NONT5XRGw8Y3VGb0FtOUBfbmlsSFkrR21+XjtAfmMrQnNhNzlEcFp3bnwjTnhxMgp6
TDFRKm0zT3JVQztGPEM7TG9PbjEleEhyUCpVKSF2VigpSEwwbTNrSmZVRH5qeSsmJSpBUH1KfE5L
dz83ZTtlTTsKem93PVJONF9pNGkpNkhvdW9nNSEjPjlpQGIxZ0szT0c0RTd+UUMjKWtIRVU3M0Yr
ITVSN2xEY0BMcTF8I1JBNmwtCnoma0wwdEpFOVR9UGJofTBuT14zO04+cjZLRmgmNnVGSjQ+YEJM
JCMpTi1wYSlQKlZocCZ7MXs5d3AwcU5FOWQjPwp6QEsoQlAkZWRJUV5IUXhHN2k1P2pxLWkkKzgz
X25QRng3QV9RY3FidTFzXmx5QktFaW55UF9nSDt9V34jR1EmUT8Kelh8bEk1Nm9YKFZ2N2hJcHBA
NHt5IXQmK0klZTVhMHF4fWloJllSbyZffFZ8Y3NVcVRPJj9NMC1BdSFyPUZ2Z0ZECnpaT1BXRldQ
VlJvPVhGemN8OSNhZWo1PnI+dWlyfUk1Wll3bD90WWVIOHNiJmViYXIoO3dSUEwoV2dfQUwyfW1A
PAp6MVZQfkQmRiRSfG9Kd1E2MFM4NFBhbj5YOzwkPih+YTghPkhkbkY+P0A5ellgaD4jSU9aR0VZ
aEROdlorcUVBcU8KekFoMGB2QWFFb0QrfUVaNjxHbDBmRiNXdD4tbGopRjwzOE9kej07QE5YcXFe
Sk19KGtYNGl5YVBGIVAqcTR5cD5VCnomJihAeXc2e05NdFUqOzlWUjNDeklvS05jayUrMl92NCg3
Vyt3YUh6K3lKYSVsP1BhYFh1KlQyUjFtQWApYStEagp6R0ZobXErOH52UjdjWEE7Sz1Qd1I9M19e
P3NIJlllWGE0VTgxX248dlg4Sm1VTyVBfCR1ZVE2cGBebH1fSCFaSV4KemAzbjBCKm9zS3AoYjRm
VVlZb3RfRTB8NFFKIS05P3RFMnNBUnF1YikhakR3fDUzdUI8I3M0PTxodDdMdiQzOCklCnpgODlw
Tnltdk5DaGk+c25pKz9tJCleT21TOHhzVjlwRUlaVFNOKiRwVXN5RjJPQENsfDw1Ym5tb0hfSFo/
S2AlPAp6SEk4RyQ3ekckViQ0ZVo/XiFFMXRaOHs5KU5RZWZIY0R6PiEhJSpmZ1NueE0tOUsqT2xL
VClgNlJGd3R1N3Y5XnkKenlaPH5mYF9DQ29yV0g9VCtHQ0VIYFArP35Vd21gNTMrYUJvLTklbyNo
PUBQPWwlLSRIV0hOWj9zWkokUlNJRkt4CnpVZHk1MGNgfSlkb195Kl9VI3cyJjJNcVheT1pacjBq
NX40aCh3bnojLUZCXzIjIVJFeWZoR1hOQWA8a0BufHQleAp6YjxiYnR5fCt4VCtXVF5HelczZ24m
d1RiamY0O01gYkRqNC1wY3hpVUMlcEdRPTxNdVZfdnoyeF95ekMlZXZhUSoKelVRUGtEazNQQlh5
NmM5UEVuanxoVFUpa1YlXiZNaitxTEhMTihidGtCaXEobUtJNjx+QUcrP2t0QV9nTWQpYTVQCnp5
aSg1SjBgQTslJmkmKSgpfj55IVI0aDRUajUmbkFZY2UmY191Z2tSOEdGKndDRCt7bDtRaW1IRCNN
cmlnSTd4Ugp6SXZ7eFA7Um44ZCF0bzB+bXJpR19fa0p7dSpyY0lRQDRaaV9HamBGITwzSW80TGwx
blAjQlYham1EaXo7PGlIcGMKenBLLTw7S0QlK19oUUJUcmkmJGZ2SHA5YilLKV5aZ1o2PWRwO2xm
M3FmOHZRcHxHTWg4I2ZSez5obH57d3dfP1RsCnoqUXtOO19TKypQQldWJGRNV2gpV09kKlFLPk5V
dF92KmpnQW1SJEcxMUhaa2N4fCh9UF5fe09+d2E9KylhUjJASAp6LUxoaUUqJSRUbl5nSmhHMGBJ
Klo+ZEJmTVItRUA8MXJ5QWVHMns2YUU2JTs+e2A+RXtNTzl6WD8ycU51Rjg5V08Keno1VnZ2QEI3
UVl7UFhqQWQqXistQ0RTNl90SlMybHFYVXtycWUqa3tmaDQ9PCl2SW1FdmBCQzd5bD54ZCErJHlO
CnpfUzxpfWs3VWsmTVlCSmEqWHFxJXohX3RCPnMjTnhhXyNmYS1aKGZveXN9YSRDbDdALTU/M0R3
VU1vN1NxT2FxVwp6TSsqbnNxcEpBVGQjYH5BZ2toU191OHc8X0VJRGJfdVlZfiNVNVFfUWFCdShS
Y3M8Z25id1AxcW5Cd2ZTJndKT18KeiY2fTx0JmdDd3lSNFMmTEgkWCVqQX1hZVVMc0pWVHJaJiMy
PCV1ZV8+TVV6NVZIaiNoWFU4dysmNzEhfUFBMENfCnpLYUhYWTYyWlViJG4wPGtWKU8hblJLVWQt
VUFsYlojJnVUPzRpM0dlUjRTYndNWGAweHEzV3chbGJhRmIhQVVseQp6aCMwSzNxKjgmKVdZU017
YiM/dTAhUXc/Zns/KShWQG57cntUS1UmQj5pMGp9O2JUOGRSOEBLUnlSU05WKTI4KzMKejxafTc1
JUhgNVlhVTMxJW9TKSZuWiZodXNFc1JCaypjZWw9KjZhO30pWHNEfF5JUyhxYHk9emBGTTRScm50
eXMkCnpMfjB7diliYnZkXkIjXmo4SGNHSnFpUU9XbjZNfnsmM0NARENjOTxKQDYhVlZtMVlpTTRC
ZyRLPitNfSR7QEJPZgp6SnJWP2dfdWg/ZjxgNSk+b0hyaVVISlFucmkpKFghRXo8QmI3bkJaXys4
fX5gUiZgUzUmVSFtelAzUH4+c0dGbm8KWnt7aT1JZEBIXl5LcXZxSjAwMm92UERITGtWMW1FQjIo
YlZGCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL2ljb25zL2hp
Y29sb3IvMjU2eDI1Ni9hcHBzL2VjbGlwc2UucG5nIGIvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzI1
NngyNTYvYXBwcy9lY2xpcHNlLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi5hMTM1YzU0ZTE0OWVhYTkwYjYxMGE2
OWM4ZjliZjZkZWIwNmMwZTY3CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAxNTgyNQp6Y21YOV9X
bXNFSCgrPShxTVRAKDt5Rj45KCtAKk1ONFVpeCQ0I25MSTZmZkBYI2k2Km55SWM3M3l4KlRCQyli
fGMKeipfbkgwWEdiRDUpRCRwS05sKmEqMEVVdkh0UUcoTzFOe2pES3RfYXE4TSohYjNJSz91RGFs
R3tgKCZNVV8rfVheCnpfP0VuRCZrMT4tN2BJdUNxITVsb3dYWTJHQmQhcHdJUCNtRjY0ZkUjQjY1
ZDE7aW1uO0FkJiVkQ2FRbnZyR0BFQAp6cWViVGxsXm55UjxUOHNVYmN8LUpQR0IycFY9Wm1DXkx1
YkZUaT44S1NUKl9ldCNhLTc5QyZoZFV7Slp6V2F1cmwKejtvTmFJWnxFRX12fiVTbk4qKl9+VkBM
SCpNSXkqZjl3dk5QTUZNTSpPdHV1cW0taF9lQTNoPnc5PH4lK3VIRnV4CnpQe3cxKDRjUW1vIWlE
N1VASTNyN2wmYjAkZCUkc1Y8fko+WTRnV2dvQyt5WTczdSZVemU8eWQ/ITtWWH1iWndwfAp6Xk02
ZExQaXpAeUpVezFfU0ZpQklTVUprflBFMSpJNkU5M3A8NWNSYDYoaiFaUlVzTzM2XiZvejgpO3p0
WnlydTAKejREJChPRGNPSCVJUDNpOTB6cCk8K2w/MGlDeCZSPi1zamZKejBRXmNsdn1qTHN8LXE2
JVhMXmo/SiVDI3h+QDg5CnoqR0RPYUQ+ODxzeDlEIUNTMjhCYWxgMWszNUxaVWhCT35Ad2tgMz9r
YmhKcFgldURCQXpWPzFjJVcxeHhpNHk0QQp6Vns9fm03JURYfj15aDduYDNvbWwlVSYoNSQ1ODtf
aTY+QisrMlNqRXRMJWB+QEg4MkNUfnt0cDBsS0FvM3dTJWcKeiNLTyFyRjRmam14YnAqJjRKYEB8
M2lVK0Qkald+TUFQPXdkKmlVTG89RjgqZkN5fSgrNi1edE0yWkplKmskS1dCCnojQioydlAwdX1Q
T3QkQkVtUSlKdVJIK0J2Q3VZYGo1eENPeXtCQStuLUtTK3ZZYW0+ODxPMl5YVUkzREcxVyVVVgp6
NTUrK0Jfb1hFUTltVVFFSWlIalZ3JHRZZip6bnxWPF8oTj9Wc3IoK0QraGtfUzJKdHUpUntjfU1Z
VWAtZnJWVXYKeiF3YTQjdXx6aX5OKk1pbTsmZ1R2SCloRUQ5KmRfZ3hIU1pOQCY+dSpeMHpYb1FN
UjEoKjZ9aiV0O2tPTSlVaXNrCnpyfCE3dExSTntyLTtRSFh5ZDc1e0tlbzJFX356YHQkWjNZd3ZF
I0k5c1dJe0tFQWd6REIkbClnSWlSYzJhdj9iSgp6bmlLc1QtIzxKKF80azxHcmpyblVGS0Jwd0Ut
YChiNEooX28tPzcxezgkPHBZcjhrSVREcURMMlR6SUtre1MpfXMKel9WUkdyUWZ0SX5WQmYmM2Jw
MihDaXt7MUE3bV9uQ3VTa1B7ISkzdDRvekQ3bkZZVk01akw/K2hjMElFM2M+VnRICnpBZmNsP0gj
OzsqTFgoQzhZYWdsKnVERWFQe1FoPnJ8ODRPVyhrVFhIWEhGZ01jTk52U180fUd6SHNtZmptQGI3
NAp6emwoPE9maT47bkJ2R2dHYEsyMGtMaD01RVgkfjFoelVuUkFmKiEtbkRrcGRIO0hpVWohfGx5
N1A3ST5aPTZ4M0UKelRCX1lFI0d1U2xMUFdSQDZtXmU/dytvJihYbFE4UWFfKUozbmFeP15lMUFS
d0o/KHE1Pn5ZaTViNlE2OXJzSmp7CnpXXncmYzR8dkBuZF81LWdoUXd2Qkc/fEpTdjJKSktSV0B1
WTBNKl5NdmZPUGVKJUs9eHM4bmBIKyRXQmYrdTdXdwp6bzVePjJXOTYpUCtmN14yPyYwNFkpVyom
fWNQQTNCeDNsVlJTNXdfKVJJISVSMXxrVmhAazZyfWYoSTMtITVXXlAKei1kfVdieyM8fEJjcFFt
P1I0QTBmZTVFODIlc31NaUpfZytlUDt7UV5kUDl5bXl3NFlYeV42Rz8/NXZadUF9KCEyCnoqfHg3
I1hpQiRiYHk9clpDbEI9TmVXcFZRUDJIfS0tZH4qfCROVWEpLSp7Yz4oWXBhVXZjMDR4RkYpZUcx
ek9Bdwp6QXc0NnglP3AoYCtgSWQkbXMzdiYrMF5xSnVkVXNFUnVrSig/fFNSSWZUVXxOUV9xY2dO
Q1h2ZlAwb1lnbytkJG8Kelc2MnlIdWZSQyorZTRmQykxeSVvIU9EaTdzRXlmSCM+eGlRJkZBTjVa
WSt1ME9QZWFjay1lcj53XjI0MCNlUnZpCno9ZDVwNiNORiQhKTlOTjNDIXA3WmcobHw8Rn1fR0Bp
RFJKWDN2fUk3NnJRZ21HanljWUs2Zmt8dH5aMz1JdGtPKQp6NzByYUBlbThLUGkjZFo5SlJqRUdG
TGI+eG1pWjxsXnchYyZmVEI0OEY1NEE0JWRDMyFFfGJlcV5QTWomP35pdk4Kel9qeHIjSDhXdiFO
dG5PekxCSksjamFPNmgqS3MofCVFa3NeWjw9aUcmYHZyJlBFQn1Qal89S31PfHtzMiEyNXk3Cnoj
JmJyQGotNVZMbm13RWI3YDFPfCZGMmlgMCgxJVMxY2BCU2c2OXFKWkY0c3RkQHhtKGNZN247VGcl
JUZDeGptPQp6QnA/JTVvZSNSMl9eS0BeRCVKXjdGdzV8UjlZPVF5VUN3SzdDIU1AZ3gjMUtYZnBH
X1VOKH18Y15XWEE3O0lNaEkKeipIaSUkVkJicCFyQXpkTW5uJUElNXNhOzZiaWZJUWJLcFdONjha
QjxQZiViPE93S1c9Wl53P1ZvPEV9fTI8Qm4pCno/RjkxN0NlVklsSlYtUmskX29oVD9MNWY3Mnoo
MjlzQz5FWj9ncX4rS2QkK2FQc1NKNCYpYmBzTnNfbC1ebClfagp6SHYmI3NSZSNfVmhxUE4mVkNA
JFNhQ1ljaD4qYSM/YHBxNHJ2cn5vUzkoVjs1e1R3bzVGdVR5aTs2OW9DO1F2K30KejdqUGB5ejIy
ez9QX2FRblA+USV9PzdofS0rU1BSLSkzeTVDaSZpZXpafVRGU1cwI2otWTBWUDVecVM1QUlrTUlA
CnpfTUdGN3twMHdrMnhZamtZJWh6YyttbTswO0J7JHZwPHUxRC00NUViU2s5M282KldJSHRiNEIj
IXxVI1dfdURtdwp6LU97Q2JIOURDUmE9d2IkRG5Abk5KPFgpVmB8STRAQDB7M0lsVU1TfFRTfl83
NWUyT1FUVGc3Jm9tJnxXNSpFPn0KeldJZDlCJjRfdDA1N1N0SWtGX3l6JmQ7X2orSFE4ZilsaCtj
dClGa3pXXlJjZzYkbSgwaGRpcFlCZG5eMW1HMVNxCnojdHltfldeKUtWMWRFdlpLKSY8OXlWQXg4
aUlHb0VPWDd+Um5idkdpdz1KeF9YY2hnXypieGM0Yl9uaSFFY3Q+Qgp6ZX53V2RjJjZaZXpVdWpk
ekB9ay01RDVaKEw1OFUpK3VkdG5CSE5+WWk/OH02OUEjfEMkJm9aVTctPjh8Y0EzTl8Kejd0K3Ij
Rk1qdUxtViNCNlMqXiQra1VafC1rYyFxSldLVmZPPn44bi1gYEtyVG13IT07SSZoZHV2dGVZN1FI
cVpACnpoOUtYWSYyQlNzRzAxVEIxNWxKRkxgISlEYFY2X3gtU0RhbEN2JWVwRi1uKkxVUTl2biM/
RmcxbEBIMFRfelcwZwp6dWFfNUJWPz9PZCtsKmMhamR6e0xZWnZ8eEMqVFdMPGg0KnRlcHAtSD5v
Sk1AJVImbUs0XmZaOTgkMFBBWjdZbFAKeiRpQlhYI1FEcTB5M3V8UDNXKiVVOFVYQm02bzghSDBs
bl9CRkFfbz97VHAoSmN0a2tvZyUrQWhGNjF1IVokenFTCnpSQl8xMHUqam9mYzsoK3VpKEBqeUhK
RFJoNTF+dFEqVXhKKUM7TXppRm87dTk+dG9LcVYtNW0leUk8Q3lhJip5ZQp6QTk2MSRAY3VXOUtl
fHJzYFE+P2BeQ0o3ZzdhOzxNT2spR2Q1fStuS1c9WUU1LWUkeUo3QGFkK0h6ckN4KzBSJkwKeisr
eV9nP0ZZc01adX10M3VhYFlac0Ywc2JiME0hOG95S2p8O1g2Y29yMmFtbGIrYHpedjZsQ3o+ajQ5
JXtgWE5PCnp1R3BJMEZzVSNOXlEpZWRWZ2YxM2QjdVgoUzZme31KY2dRIyl9dXZrPWRvPVVmclRe
QW55eFFjdT1JUVluNClmZAp6aG4wbUtVJnpWdjlyRm16bil2JnspdEY5X15xZjZrcXd+dFd1KzE0
XmwyKCFTQz8yWiElO25+KzlwY3M3MT9ZV3cKelliKmJBSFhne0xkV2gjYGRQMGJwb1pSRmxOYUQ1
SWZOMVZJNmY1VkhSM0lfKlUwdGxePkRhIWdFSjxmSlAlVjlFCnpONjBObnJfckZZdFIhZGttODZK
STtOcVlManwzZGZtfmJpNFd3Vmc7WC04MTQ0LV99VnYhYmI3JHs0dj09bClQTQp6dX1uNml5ZExf
VEpwfllkSjVweD58SWghMz5Lb3VtPSNgKj1LK2gtbXYjZGcxQmhqMHYrXyFDSnFQYmdmdGdPUnsK
ek95XkYwN300azlLOTE0X2ArVmhQPj0pJGpvcGUmaHFOTVdxPDgtOFh1fWZVJiZ+Kzk1dk0zYUV4
Vk5faGN9QDZQCno1NipuMygob0pNJms+KVZoKWx2R1Z0TnRlYWxPWUNIZ2dJSmROZWtDKmpvd2s2
P0kxfk5AfD92N1VjQnRBeyMpVQp6QUF3VjBLNk03WXRWRVMxQUtUbG9KemhmTDwtcThgbWFPYn4q
Vks3ZWA4YHEwbUlCViE+YyNuZWF6JUhwKDJyRjcKejI/YGpjQiZ+bWkyMUNec2s5U0goOHhKQCl2
ZExpN0ptPC0oIzZtX2IjPVpWKGZSQ3M8IyY8M0ROUTtnXz87KW1jCnpqeEBASSstN198c1RMejRf
RV5eOGQ7eVolRjtSPjwzV3NORVNaWEV5LSZZNHh1ZG1gPW1TZWQmYHE3KD9SLU8kOwp6IXQ4Y09i
ciYtOSt5RnZFc3ZAbDtxNjdiezRJQGRXV1c2Pm0lMyE9NntVfj0jaG1aNGc0OWNYMSh9UWAqKHN0
dnIKejRhVV5MO2hSfTlTKVZ7KmEpM2ZVMUJZbFgjPiMxQlV6KVQlSnNZTX09RnduRSVHbTd5b3R0
fXAwREB3TjM2X2NmCnpgUyh3PHtrbmgmWTIyUTJ0RUxwPjNFPWBrPmMkVjI9dSQpcDw5bW40PWZ4
IyRpQihuWCFwa0N1PVpBVFBsYCshZAp6PlcxdEp7OWB7K2RpJHx3SGpMd0YzSyRFRkR6KGFWaD9y
QXxtQCM9b2pqVVgzZStDNz8rfX5ucFJPKnh9YUdDb0UKekR0eipaTU8wPkBxdC01KUU3QkM+UnhZ
KW9DQmoyZnhqKFlyVkxibDhrYXNCcHUhK3taX2AtfWFPNlBqI214TF5pCnpFUTkoVG1Wd00mYlRw
Tkh1aTFLM0ZtUT5oQkNRTEkmO3BDYjxMayNRYlBhcHdtaX05LSRlQHkyZ1NuPX0kU1RqXgp6U0dB
NWNYVzNgR1BhcEhFMjxYdkFaMGJETl47SHl4bCZwQSZTJVotVTQ7Vmp1VERANiRYK0ZzVEJLTDct
b0E2ZlEKemdGNDFBbFctWHAxPHpzS0I8KEh+cUl0amB7V2hifGNUMD1RPl49RmZzR0hJRypoJXgw
KHZFQyVlamhjYnJxP0hxCno3Oz1WPmNYWnQ1QmcqeWF1NjwoZEYwQXckQ0cqZUNuJklFeig4YiU1
UlllLXo1QUYjVW57NX59IT05SjQkZ0IqbAp6KUE5e3NUSSp5ZGE3RHRSJHZEZSNvMkR9fk5UdT0y
cUtoPmNyKUs5PSl4OERLNGtpeTRfZVBvSyVGKlprPyRTb2QKem83V0g4WDNIfSReVDloS0BgTzwk
eU9NY1ZufDZ0I0M2U09nYkRHMmREUXl5e3BZVkVRPktAQldsNGVOYD89JWBACnpOP1RZT0soTlVr
fDE+RVk2e1RqfWNPezBWaGkhIXRYPztsZyF6Un5lPS16M3leOXx2QTxxMDxLez47cXlveE8yawp6
XmpgJStPJipfWjs9fkBvRzcmbHEldWVGPjgySjJmdmpINTFsKXY0OHcmKGxKM09GKFlCKnI0LVY2
YXdZI3Z8ZyQKejRROVI0dz9TOyU4Mk9PdmgoMk9UeCtrKWc+Nkh+eXdPY1I+MjR5c0xPayNLRCE/
WVlyakZ2e31MaDFhOGhxdVJOCnohbVFkMzBZfmY0KU5FSiZBQDR+Qi1POWRMdkNIQXZ7PGl4K3pM
Vl9WUi1Wekp7P0syc0h4WnZJUUNUYVJEVSFzPAp6S2lLZWd5O1dURjAyLT43LS1gP2Q9Sk43UGx0
ZiZTQlJYKGQkUEkhOF4xUm58YDYkUUBSRigrYExGKGs+Vih8U2YKem9ZNGcreTRVbyk7RG00LXMk
MkojIWpOZWFvUDUzViVgRDN+dUYpMzF2bmIhUURBVjJ5T1AheWteQVV9PTE+fVpkCnpxKG9tPSVw
fCVGMTUkRiZlUjQjK29VRE9HJE8rTVppN1E3a00xd2JSaXg/dCRYfFB3ciYwU215OX5XKFZCUSM9
Owp6d0Z6dV9eU1BgLWVvaGg5Jm1iQWEtalhvfGhsZ3Fzays7TUFsMVJ5VjZkOEhXS04jalJ1I19X
V08rfjVTRjJLe2gKeiomblVtUDlgKU9ldzlZQGFeT2dBQmJVNnhwcWVBV3g7QCkkVGdsbERHdDlO
UChWeiZZO2VgMjRETz5tX1ZkQlprCno+dWlsQWY8Jjxwaj9eLVZubCNpKFJXWGxHWHxUYEtfT28o
RUN0Kl9RIVU+Kyotb3BaKCVrRi08TEcrQVpYcG5NeAp6SkVxVF97PXJwanh5aV8kT3xBbEU8bG97
RlZ4TjhTPHh4Kjx2WVdhISE+MXZlZ2AzMW1fME1IcnJiLVY5UCNNXlgKencrQENHPH5aUlBxKzNp
MTN5IVQrZSMjQGp7M1kjNGEtK219a3l8WlB3MWtLbFJwSjc0YXwxQ2lJYDsze0ExbURSCnozYCFt
czwmUCZGaV58Q2hnRENGQWhmP3speVIkX2EmNzQmRCRFST5kYzVGaiQtMz1LcmN4K2A2XjB7X0hx
NkxCcgp6IXYoO0ZWQ3RpNHkkST84endGZCg0e2kjZEd0YyhaLWwjbUNsRT8xQ2Y0TksySy1TJDVA
Y1pmPUVhPEtPP2JVSW0KekU/bj9oM2VnRSY/Vz9KZTFPYWF9V2kzfkgxQzlKb0V8QEBqJkpHe0F3
NkQ9eHttMyRWeEZ4ciZ5RTRfakFEI1VOCnokfDtlVkI8fHRvUjN7VGs9aDlRaFp4cFFzSz0rRnN7
cyY3I0hTPTEtUis/YWZvPD1ZdDJfRkxuJjJSP1RLYUZsYAp6RnRlTD8zJlNrS0h1fH5taj5NX3BA
Z21ofDtIOWM5Q30oZC0xOStAbzdVJEg5ZmoqbCEkd0xKMWU7bldURz11bFIKenFnVk04aV5tcXYl
K1JCPiFXPHE3JTUmQnlOP0htbDRQX3Vybm5nUXwzWS1DeHF3c047JENDMGxOVmI0MDxkYlJTCno4
SExxalZfU2AoSD9GTyFFPkp7YjxzTG0oJmx7PDA/Rzg0YlFwUyl6ajl7VTVuPDdlQ0twP3IwI0ZP
K2h2YiZZYQp6cm03azA2KFoqVnl6PUxJOTNkOX09TEZxcmgoS3FBJU40QmhpMnpsY0xgMD53LTZT
RjdPODklPXlWTDkza0Mldm4Kej43MD8wVWd1NkJOUEt9dHt7KiktJVYlVnMtTSRMYj4+TyQrVkt9
SllYQ2ZnNiQjbyhKSHhrdHlAbzEqTDFiMTgxCnplTkFne0RfK350MSNLTjZOTTZuZDBiTVEwS3lP
RFghbWxJRHZxPld6ck42az83I0FHPVJUaGFRLW4wWlVuTW9qUwp6dmNPPWZhQVdkR0wkciF8TVJh
bVVZfVRLRjlAWUEpUGFfOHxTa0FKXykrK1NCWG9mRmlSSXpVSVVxRGl6TkBZWCgKenhTSzVxUmxZ
VloyRDs5dGRUWTFjO0hlQUFSZ1JhMSVVd2lEQUZNP1JST311YHhkREE/N1hQajdeMmFgYkVgcWth
CnpzT2A3Ny1yfEVsNkE5eUFZYkxJUzleU0lMUnhiXnUzKz5RJiM4KUwkTmEmbWZ7MEw0Rz01VmBC
T1ltRilafEJ+cQp6bis7dFF3Q05YRTFEK30wXiYkNmozK192I0NKTCZvUzBCNSs2TTkqfHNUJElj
PUdjR1ZjKTMlNUpofnhldmJ4VEAKekVRSHxhZnQ4SmhnY1lFNC1lPEdpWiVKTitPflIxVDJoRWBP
XkchSU9ZJmtnbHUjfExlP2BiMDx4cGV1JEE1cnhGCnokY1V4dit3VGNuY1JSckhIRzl4bXVLUjlQ
Ynh9UlRCJE5NcGctRGxVbVZCUjZvV24pWTJUbCtqdyYqQyUtbCljbQp6ODF5ZFVZOyNwYXNJfUF5
PWU8Iz0qckg1RSlFYXtSYUpEe3koZSo0b05xfVRLeGdVe0BeOzhsZlooe2JfcT0rVncKemhJN3ph
S3dQbU1oS3lSQz5BOFRwK1NzNFd3Ql9wSXU9JnU0KnwyZkA5RWN1YVZOck81JC1QPSppNiNJIWVz
UWMkCnp2N05OKWNxfmFEOVE/aUlfeClaYVJeIURsRDVSKDlNSTFnRngrQmtUZzhRPE50P35Fb19o
XiYoKlFYeT1KS2B2Nwp6PXlhdyZldG9wUWFCdHNBLTYoOSpEUHxrP3h1VCM7WG1efl5yRTs1WnN1
TXdtNTx3ZEBmMjs3TiVHM2BRXmRSRVEKeiZ+JmQtSHJXQXdJViVqdXZqe3lgTm9uKWB3bF5wZUM8
KVJvRz9VSWYlN3VFKjZ9c1dzKj87YUBaMTl9e05LJCNjCnowZTg/JSlGIStLb01vY1M9U1ZxP0hm
cTBgNXFLYUhsUGA5SmtiZGo+WmFqelQlSzsmbGlON1Qhcz96LTxqPVJYUQp6NCMxU20hLXZ6MVZJ
Z0VjeFR4KzdUSyNUPWNYeklnODtGP3w5THo2ak8wdiE3NEZOa1BRIyVDX3pOO2pyZmkwVkwKemRM
bk49YUg2YU8/bjUqcV45OHBucy1GRCFBe1M8I1cqWXY1e2l4fmsjanA3PTlWeUI1cWNENzw8Nzh0
PXVzUVJkCnphJWFAZjFfa3hJWFJLRG9Ab1o0eUNXYVlxeV9VQSkqdEltMFh+IVZ9Pm82Zj4qUG85
LXNPJWJrKmtWbEpGIXVwMwp6K0xBP0BCdDhNQDQrYlBnSEkjOWQoeEM2Jnp+RjVIVlBvQGFgY3o8
UTFmYHVHdWNKJlJPMnlFS1BidkNleSNQcisKenkzSHohTF4yTzw7I1M5LWF7WkRUOVZjdkZZP3pk
cD58SH5ybH1mMD4+Y19yR1p7U15HK3FQPmVHYndCSz1qTTdkCnpyTHV7bjxsNz9ARHVtRUV1bztg
alFpeWU+WEh2OUFgS0pqTEdfSz92REtOPj1tMDhxTnxJNHEmUU1+I0w/bSRrbQp6Xyt6czNrKWRr
S3hPfkVAUz9BTnNMU2swPzM3SjBMckk4Jk5ZeUUrekxVRmx0a1lAIWE7akRqeDBZVHclQzF9VmoK
enNlb3VmJFkhMVRvQWA7dkBqU09NNk9xc3BaWHJISjtBV35RJiNIblVmODFVRWRzYmROS0MxJVhh
JFFTJnBJUyFkCnpvNVB8NGZONy1OYlR9Tz5BQFlGUitRLVY1U3cmU3NzTFVFVyE4eTlYRlZfRSU8
RDFuT1A1NXBrIXozcGJgJi1WXwp6bG1hWE8jO01vQkZCR05fSzllKFF3LXhIc1dEfjtUQW41V2A4
YS16fnl1VkNXMnZqYDsmVzstPTcyd1h6Szc7NF4KelZWblc5UkJ0WiRTMko+PlBrbzcjI2RfNnI0
OWxAdTMyMm5JX189PE1ZRjxmVUJOXlFja2JUQSY8c04xMiFoeVJCCnpqNjlzQENJcVRuQHRYbXdX
Rj1mNlAwNjcmWVlMUkNobiRzUj9fNk0oSDJ1bEslWW9wQ0hmMXNTNVN1WkApSFBkQQp6eSQ8Pygr
M1FGS1RDPj59SD1ASXJYZX1Dc1pCJUpfO2BASnB7VUo1THNZLUR4VU9kej8qQkZoPV8lNEM5aENz
a3UKenFYJkdScnVLSCk9ZUdUdW9ILWxLU2VqZCtEPnkrVUMtZFAyZXU9VGRIc0E8QztDUHE1MkJY
RXY/Kll3Pik5ZlB+CnprNlhKRDwhK29wVEBDTTh0UTxHO0Nec2tjYFB1MCVzPSVOTUU+UystPyRs
ZzgxKXxXLVMoVW5jezRiPDloJl9yUAp6M281eW5MQTxMOElOK2FGWigpVlBzak1iRmNTRHVNTH5+
UW9rcllaXmlGPTtpfDFIPSFMcklKYG1UdVdCaE5OSioKelY4I31raHg2OGUmMU1IYzNEKFNiczFu
YnQ7Tk5Nd2h7YnN5JW9tNFQ5Vnd1TU9vYyZJQmRKUjxULWZ3eHJ4T3NUCnpeek1PNjM2e1EzMzZA
TCljVURVcm1HXmlGKSYqSDhrMyVLbykoVXB2KEhDM2B7eyhVRGBSIVc+Zj5MK140QVN6WAp6PnZo
ajYodj55ciotUitOIVFuc1dVPHtSSVViX3pYJjd2dlpHUDRJOCU/fUp0K2BrRklESVVNa25BQmJw
dkZxMW8KelMhaz1YSyF9TDl2SVNBNHgqdXtqaFRVYzBjS3pvfUtiZDcwb15Qaj1WTEElSVZkRk18
UEVibTRrTHhxNHNVVz1BCnpQO30/JT83ZlMmIUJvRGItP0RgU0dzWVNtLSthcW8xRVhSaj9TJDY+
S2UrOEI+QFheTHN1Yj5YMWY8VWt3ZjNTKgp6RU0xe3ZKKUZeIUp8PUFGTmFjcVE7RH4lJDxQRDJA
VG12JkRqTk40SXdlQiVZWEF7ciVEOUJVNURIJEd0MHc1P0IKenF+LT1rWX1XdjN0RFc+ZlQhb21G
bVIxNHs/LWFUeGVpUDVKdEFFPSp5T2IhRE9mTGsodyZVJnRRaHwrY0xhLVphCnpPP3cpJkEpeVpP
bE8xJS1GYSZ1PyNyUikqLT53cXtZZFNKNUBNRFZvTk03RXUzd2FXRWJWVkFjNDlWeytJfVB2Owp6
JFo4cnc9fGhFYmE0d1U8emZQVyFpN2xKPSk5X345Y0wkP2lZMGJNM3Njb0spP3JwSCtRfm58WDJs
NGRMYyF2UFoKejUoZDJoZTJ1MSpvZlk5MHZ6fi1fUlNBcU0yTDdYQStySWcwUFZZMG5BV0NFZGRp
Mnw5MXxnQCNoVz4qTVR0dV5eCnpWbjw3TSF9ZWY9QzRXRGMtTmgrMjdnJTRzJVNeR0FDNEQ5d2Bg
TyNgaSomTHVHdmdhP2JiQ0smUCpIQX12fk1wOwp6Q3drQz4xezdRTWpARH18KHpJUE0hMjUpQkEl
cmM+PlEkV0VVcTU/YDJ2Kip8OEApY3U1Xj83R0xkd3R2Rns2RUEKejBCZHNVbUFnS2lTTl44I2Ul
Pnx4UkgmaE12aFJhPiswRU1sITwhTTlDRT83NCMtc0VvUTlNbVM5c0hCKnMtWn08Cnp8TUxLaGJu
LVghPnZ+PV9xdUZaTXZ2O2RKZFZNcilNKXNfKHEtY0owMTx6cEtSJWlkbGQ2YnN1dHNZMnJRaH41
Zwp6KldIM2wyR1hBb21pdzFWKG52bmJzdVZFJilFP2k3Q29jMz0jcz8yd3deTG82cn4yVTlUI29S
MmMzPzZCbkhUPmQKej03QVVXUX0kTmB0MTEmKT5udkwjeSF7O1R2XktEIVQ9aHVOPjIyUkcoazx9
Uzk2eV80c1g3NCtuOUFuZTxRSEl0CnpgIzZPTFkqdntpd0lKbjUxXjViJTxtOGVwSkFFSzVQUU80
JnAxTkdFJkZTfWpjR1JkcCNTWT5eY3A4el5WflBxPgp6dmFpKEFkMy1CPjwtRiRxIVlfeHQ9Vilk
cnh9X2JHbyNBXj5WaERKYG4rOzVWZlkxODM5QEFqeTRIOzJ7b3VhWnoKeitFMVVNQnB8aUNXTyh4
JXc5SV91LTc0ay1QczhUQCM5THxtLTY5eEpRQEV8fTF3YWomYVYqRD03QHxjSEJQWGh9Cno1TEtX
NyElZiNDMHdOYnRxSDI5cGMyV0RRWVIrPjVmaHNTfjtMMnAmZGRaYGIxOGtoMD4yQEcmI3lwXjJk
RXlwfAp6SlNqRCNreG9jUWY5fm1ITkpoKygyfihxJHNuMjlrSmxBKjJhcnMjaWZhR2F0UTQ3REBh
PHMhTU9yYzRoaFYxK2QKeiNnYHNrZlp4NDVsV2ZMPVV8S09CO0NydksxJVNBKyMmUSV5e0FOSFN5
Rzt+ckZBalVEcVIzOzRyfEpMKiM8bX5kCnpIaThrVEpwIzJxbDQ/cT0yX1lVZzZzejkpVkNNZEVU
Mit5Vkl4NGlvJGE4JkVQPWA5Z1EzK1N1Nm1ReEReRm5gSgp6dnBrVCRaRFh5dEh9aFZ8S3tyTjhg
fVFVaDshPlhqdG1aZVB7dUx2WVZBcC05P2s4SHZZYXFge3FxPkJ6OWU/fFgKelItWjMyTW41RCok
SmUjOTA7Wng9MChDMV48aWh5U28xZjQzSDlDSHRgcWl5NG9zeDQ+a15udVVLLVlRKXZ8PCFmCnpK
OWNiUGohK1VgIXR3ZGxGVVcyP3xBUXFtZyp+KkJnOG16NyNsLW0hbTg5XjY9ISF1ST83XmhMQnlI
XnZKSD4tQwp6RStXV1YyX3FAOU5IWCtATkN8dl4pMFB4VzBOQWNXM0hEKX1ZdTZwdlckVGUwXmNj
JHlrK0l4KWlkKE9WZG5BcFUKelJAT3c4Vyp6WWAhfFhKZV54ekBuMTd9RGc/YnNiN2NTbVM2ZEZg
cWFGK2xMcUxLJDBvUlY8Q0NjOEslMmt7eHhSCnpNM0IoPHZVPXQ2MDFgUEElMyktUmohPGktXnc9
KGEyQiplR2A9QV5LUHskNnAqMFk8TFVkNyRRUDVzRT42akE2Qwp6b3hEdlRXNygpNnBRPWE5T1FR
WkBFP0M5aiV9V0ElX0ohYjNjOT9sUSE0YypYRGNKOXh1N3k3MXJkODA0aiZpS3kKem0pXzNQZF5S
V2MrPkItQ3Bme31qRC18dWhpJUojNzs2SFI5KFZ5WDZULWpMO3hgUkVVN3lCXil1cFhJPVc+Tz1w
CnpkS1pgY0UyWFdIS15Wc2YwZGxuNnYtbzk+aX5ecilaYTVTZm1IM3tpeXc5OTUyNi1MKj5LVjZq
e2s3YTFPNiV9Ngp6by1wTDxhN0NGLT5hdyNXVX0+QykhWF5XP2l6VklIQmU7bUhLZGljRG4pSz9z
V2IzZV43KWJAQz5YRyZhYU08dkwKel8kdjw5JE1mX1k5PkQ8cyNhaU91ZDJuaXVDJXE5aiorRjhH
WnN8bUdefCZ3QGl2WT9jPGJRXjJuaGhpSVg1WEJ6Cno3KTxGN2trV284dUMoP24oY2Mzbl5Ram4l
R1gxUTcraEtHb1g+R2p3VGM8X0ZCd0VDeF5oPGJJUDchfituSTdiSQp6I2p+QnYmKGs+a1NfTkFX
ZmROUk0+R0dOQGJGNUJBa3h6a3JBbjFaRTxLTTVDSyZWRnx3bTR2YzYrQEJkZG9adG8KemlYaD8t
OXw3VHd3JXlPQDhCMHQqdk13JH54T2pLNkxeYz1jezN1ME1haHlYPFdkVG9PJmVIe2UpeC11WUxY
cUoxCnooRn4+aChSNUthaVdoP1hfOTFHbShQOVR0NE9qNyFnenNiXjQmQFhvQTZuSDtYXlpPRUZH
UzgrYiNHPnFEdz9JXgp6dyQ4O3xAPmlrZjx3MEBge154c1NMUWpzdEcoY09mITEoTWRWfWUwS2RT
YDVqRTx7eHYhRytvP1ctRVM2NDFLXmUKekl6I2FfMD9zeE1TMFFWbTx0S3VqNyZzMmJBaGpRJEdL
JlFWQ0ghWiZtYDI5QkxBdVNUNEUkZihrSE5GZntRWCRMCnp4VzkjbFcqbWN9ZkdOS2k1UClkNWFg
MDJqXnxFNCRwR2c2PEhnTTJjJCUkNH4pemElZk5EZkFIVEB9ZDtHWSV4Kgp6cSF6dyVuWHs9Kj9J
SzhHKDFWaEIjTyVfMEdYPE5TJjUteX5jVlMzY0RPZHQhSVRgPSo/e0E7ZXV9KEItS0ZDUzIKek1k
K1liJlNGQE55SmVtPmtlX0dyPmJnK3hzJj0+YjdAd0J1YXcqNUdWRXQ/dDc8b15ZOTU+TH1VMmdH
VD1lRHFVCnp2ekxzYjAmQWtLejBMcCh4JmlSVzRQT2xfZHFaVH1oOCtfQiE5XjJ2QHNmKXkzdFRS
TFhGO2h+UVh7eXBOMDBwVgp6WHclakE2PnNfJDVudSlgKCtnfnxBeXdRRm00c0BXaGpsbEFqP35x
QmZxS0Y9UzdIM2clOFZzSHh6fjEkYHF+KT4Kej9ob35EIWAxfWs/Nmc3YFN5QU51bG55ZEBaTkA1
WF5LPExSMEtAakhvN3BFRVRsWTtRSnsmZjQwSVhJMCl7PTdrCnozIS08dEs7ZFcqY1FITlg2WSNu
P1gqK3lAVGA8LVhFbkItJTlnJHhgWCp4eytvUnFGK3B5bW15NGRaJDZjdlc/dgp6ZlFqfnpCYW0x
TGxVYSF6c002U2Q3WnA0N1kkckxKaD5xTFMrJEF2VSNCRCRpPnEzcE0ocH4tQmJmZkpYP3I1MmwK
elQ2SzUyIy1zPkNLemRVPXopJmw9cHRoIXRrbnVya217QkhnOTBwPDV1fDU8PUA7ZCpBIUtgOFJX
aUhUIXZJSnYtCnpQVVFYSjE4QXB6dm4pektgQ0BsR057I2tmUSp5UkljS1JEUCtZKFlpc1c7c0RN
fGMkSi19b0NGUGg8Z2lCdDBnNAp6Rnh9MGVkOVlCS0llaypJKEMyNER4OEh9alJRe2s9IWZyfGpQ
WjMhZDtoak41bncyQytXZFcybHZ0UntmO0deN3oKeiZhejU0S353ZVBYWio7cjckTmI2aU1FdCU+
M0BmO3lMS2U/IVFhaHVZTlBEZF9jc3p9cjRjejFnV2o4Vj8zbnE8CnppS21BbUt4MHdgMjI0TWsj
I1RQJDRyano3ajc8NnZycmp7K3ZCejRRMlQzfVZTcn1AZXZwcjtGQlJmZlRjZ1RwZQp6MExfcmo9
b0pnVmhgPzs+M1YzUnBCWXU1fCZyPTRtPz9nX2kweXVpNlZ5d1FkWnlzNnUxcGhze1hiJkFRIXZt
TUsKekwoJUJgWXliM2NPQzNsLSNqZHA4e3F2TnUtRVpCa0RqbWVTKkw/bmZKWjg9dFMqQUJKP0VT
ZjRPUyRofD1ORngrCnpIIWVjeEQlYUhMOFFlLURXNDlfUldaR09Se0ctM2UwNVIoWHshRGk4SXta
Rkslb05EPT1UNHwyTCp8S0dFdH5NTwp6T2NWKSMpNk1FcHg2JGJyWnBxRV9OSSVDJlheJUJ3byQk
ZylTVzBlPTJtMUFNWlYyc3hqTTAyIThiY3dxcno9fVcKej9KUkNHNz5fTlNjMnQ2QGkrcCo2NFZZ
NlhnRVoyVWhabyszTGshPDdOcD5+PW8jQXBCQSZ7QUtWVHpITmVMSnw8CnotO0xmKCN3azNEbzky
emU9RDlXTisjenVMO1RIbU5wJVpNOyh+NlYmbHdtYihXZ2kzWGR2aCo5MStvQn1NNWc3PAp6Tjlf
UW8/a3duP2h5JiV1WHRePVhHfSlXM0xfUTcmIzQ+flhGXklsUjI8UTZtcEhrOE8xd1ZuZmRzT2gl
d3Q4Mn0KekVxWUt7OXFUMGk8NyYrVF9BamNVQ2gqZHk5U3oyISVeeWBlaXk5T2JLcUk9c2pFYSo8
XkgyYUFGLS1KOCNNQyRHCnomZ3ImdlYzXmwqNjxrKkh0ezkkcUt7NTsrSDJQcE4/VEpueXt1U2Qz
PkMtWTtLVSFNVEdzUXRUQzI8eX1EYitoKAp6N3FOLUx5ZElVITg2WjZhVGVpJiN5Nj81ckhqYjgj
IUFDcX0zIzN7U3c4RHApQUJmQTxoKjZVblVENUEjP2lrdHcKelRvU25AeCVTX2p4bHQ9MHRfISNN
RXBRfjlLMyhhdSN4UFFERjM1O0g4QyljS3E7Vj1DX2xqPmpoa2xPdlFAaFdhCnpZWnsxMj0qZD0w
dzFEREklanYrJCRjKmM1KEhLSjc3UGt8NyY3S3FTd3tSX0FZI2wodFRNVFF1NHVPWT9MbiNhOwp6
ZTBEN3U3P3NQNXN2KmY1bzVsWm5fbXxMQnQyNDFjTGRRe09pdCUyYll9WGUhaVEqVyt5bFMjOHIm
aEY8QztIejcKekgrMSh1LW1UV31uTGlmXzZJYWZiYzZWOzhwTVIxYmlSQD5eYVAjLXdHZjRTKm8j
WWdLTVlTS0RBSm5RUnRvb3pyCnpqIWEkTkF5OHZBKHVwQFh7ZkkjQCR+T1AzOD52JkB3VnQkKHJZ
S09uPX13Y0k3SUJqIyp2NWI3PVBofFg7fTZITgp6NDFXTy09b01pTXQ1IVNmai1DXmFjQUY0WWMr
K1coTVRucEV2VHdgam1jSkhLdzwoO056T3M5ZllKKjtiWSVEZTAKemI/VGVxZUNuNkxvPUNqSiR+
KX1+WWo9aG5xPW1qSGVER29hVy1yO3toP3xQd2lyJDVubjRvS0dUI1FBQ1plXyUmCnpDfGd3ZnFo
Yy1PMXhMRVApKVgkeVpaWlFVNHhpKT4yRjclP0Y9IT5zWXN5Sl8rdG1oQC1XMkxuQlYkciZMXyhT
Owp6PGomQlp7JDNIKlFWd2YqaThId0hQQjkqRCtiK08zcDkkczYpfiFKJistJHM3bFRROTtLWCFZ
Xm0kLTFaZHkjMXEKelQwP0peTTIkTlhtVE5rK2xUNVctLUB+NX00MiY/SHB8RUdnIWR3KlF1K04+
O2pxQ2JwJCZIfVFlQClMQkx5T1h0CnpNeE1CTGNCOGhMPGo2MjdPQmJsVW9IRnQ5Q0tRKGw0Zk51
WU52bn1JRGlEWjJ1RCtje0lfJWF7PCoyK2BMYUp0dQp6eC08TDxIdzNvXnZoPnBxUkx3R2A4Mntx
ZFE5SkhEPn1QbFh7UyVYfDhEc2RQaVE5fihfcnY7O0g+VkhXQjk9fWwKekNmPW88Xi1uQ1p1R3Et
QlApNWgrd319NFMpem4qVEF9X0FkSSlxTlFSfEtRXm5qfGVGZ2BmPzJRM1QlZ3A8M0NqCnpfX09e
N0tRJH1ZcE8lWSp7JDAoPFBPYnloNDsxa0sja04/Ynl8TFladF8mMip3VjBXYUI1Sl40SENvOHZM
ZEApcwp6NzQyP1FhJlBnakU/WWhWUzNPczg1PHlzQSlGPShTKGI0NlU+eSheaXtPSjUrdkpILUpk
bjNPTzY5YlZWMWkmR2IKekFNI2cxVXAtdCVMRCMpOWpDQW1hXiUyQVUra15AOXpld2FoaFJIbDhU
OTtoNFNXWndvcXRsc2tkZyQ/QGBiIXUyCnpUMFhjTXRAKXo9bHkjNmB7QUx7eEBZQ04/eDh3aX1q
fSNiPWx6PipUVilael5zaVNmRS1QIzduUkBIY0JMSn1BTwp6ST9iMWYqezJDez9RZ2g9d2Yzd148
WnVLPGRrJT4wcyh7dEpAJWB2YUdgbH5pcX5VUllZX0Q8YFYoRXFEc3xvTFoKemgrNlMhPTlpUjhQ
ZFU4K0g5c1A2VipmIWxyciE7RjxHNTVYb1khPHVzby1BcGMtVndHO2o5dT1CWFhpZDM7JiV9Cnom
Ym4yNTR9e3NGYT0oOWxgWXVrc05IfW5hbn5VZTtgK35kOWNSYCEtVUM3PnxoVDdsejVyTXEpNHRQ
YUAyeFYhIQp6Sm5kIU9tV2xZfj4pWSlCQUY0MVZOZ01FfDxgdnZnbmJkV0lqKjx4PTIjWn1qblMt
SiZoNDE/fVchSSEjIXE8QVUKelA8Ym91bChhcWJBbnlzMGMmSmdEe29WRmtjJkk2P0BsVT5aKCFg
VGtTZmx7QnViYk5BPXg1dWZIczEmTEVeQndzCnpHPEgxUHFPZlFjYG9OKDBWKEplPlphRHdwYSla
MW5NTUFHV3FhQmxSJD0yJGgheHhXTUhMYTkxNExnJiRuck1sJQp6dUU7TS1ZTFUze1VveW04YHZ0
O3NSUGgzcnF1eDJNNU05I3JMZT1uVU9OSU5QayV5Kkx7Wip3QCUkbFBJR205JlIKentWOE9wZHxN
amNORDAwNiRaQiNCTyFiazhUQndGc3I0MmtZTEVzaykzIUk2YCRwZnJ8Pml5KWkoSFRgOzkwY257
CnpCYk12JjktRV8+YSs2bnU7YV5KS15+NGp5PDg+VWF0dyZiZ01oOT97KWpNeGRJeVdnI0x6O3ZO
WXE0RyE8U2RZQgp6Q2d9dGdUVUktYTwjMipAZSh7RD1tOHhULXpmQ1ZXSXw0OyhPOFR8QHp2PFFS
YFRjSUBXQGRmV00hYTEwVW8zUU4Kek1FPTBgO289bnhHeHgzU2lMRHdlMmd4OE81QXEpdmEkQSFy
YnxMOEAycmZvJD4mVGY4I0gtNF40eTxFMW1TSjhpCnpNNSEwZSFzRX1MT0x2RUVKSlZ2MihnZSl1
ITwjJDN6KW09MlBLcGZ9emtiP3E3ZDFMKE5KKj19THs5MmVvdlFHdAp6bnI3VH1NSjkrcW5hYXZL
K29mfWc2NjlObUt4QWd1N2F3TylSYnFZVHM/WVlFMyo9VkRpI31UM1U3fm1hI2wzUUcKejs+NVNO
IzlFbmI8aW1ZQzB0RjN+JWxQfEBsdlk2M18hQ3BKSnhKOCFiSmNnS1AzMFJ9dSR3QDtIRTxUP3Fx
Kld3CnomaVpoKik4bippeFNFYFQ/QDtecVhOQ0MwTTtfYTc2S3JaNml5Q343WmxOYiVCUiMhdHJG
MlojcVM5dDdSQXxzTgp6NF8jZU9FPk5eUitzU29pOTclcGRXSEtJVmJzfXclVFh+UnVZanQpKkNN
Q0s+X0goOzQ0P2Q+U0p7VjtvYHtRMjQKeiNiNzdWYFVZRU1BUElKSD1IOCYqXyFiQmNmOXctXkBe
bUdmezEqd3ZXfHNOUXRJV2toNkgtJnFnelJhPHJDaEB9Cno/Q012UT4zKTVxTjReajlKRUN4KDhz
TjUhWlQ9KUBodmMyKWpaLTRSbzlSaXlgeCUtaXZ2NkZ0VSF7SiUkailwbwp6c24yfDFINXpGN1BS
PX1gbUNEcjtnd29HSk97MnQ/RU1CfjhBPXsoMGdzQz59PV44TlV4QHgqVS1aOEt5c3pxJDMKells
T2Y2dVoraFNxcUpmP2lYTlM0YDUtSjlzdSF4cllRV1UwQH10aH1WXjtjdyNoMW9KJSNZWW44VSg1
R14xKUpnCnolO1I7TUBySXV8TTIkSFRHezBKWHM8eUYqWDBiNE1pe1oyQmNlbVVtQ3wwaWxVOSl3
O3EoR2ZvJH14PzQqWDhzUwp6cjImYj95eC08VFV1dSVGPSpvRkhGNypDZGZCZHdGXlRwQCl6ZSZx
RTgxaWImVENwO1gxfTtmXkw9c2drJntVZUEKemlYNU8pOXp2R0FFUWt2aXtmRn1CVCppfUJOXiZ+
QytKc2pQXk5MIzJOUz87T3RmRXMzKzg5anlwST19Pyp0WkZiCnpLQ1QpcnNUIXtpS1g7fT1abFE3
ZzRENXV4P3FJZHZkQz45PWRLMT5ndUlmJGY0bmcpUF5pLWxGRypgTXVRPXh9awp6MFd0OURGXmE7
QjtxNWVNU2xVdXQ8cloqJUlRQSNiUUluUjNoPEBne19OWWBlSDdhRHJKVitRJnNLaUo3dTJaPFoK
ejFgT0w/TGBFMnRoI09xY05td3xUJCUlKyptLVdXM1dvMzBTU3slR3U7KlVpXiFgQjlETUdofW4p
dkUoPF8pPXUqCnpsc3xqTlpwYDFpREVKYko2ZmdAcCVfTEBzJk8mWHVVOXFkWk1oV0g7YElrcUYz
JmNTRmYxYEl8THZCKGx1eGBxbAp6d09rKkZnXks7RHVMUEZrVnxHeWhRYURrWmo1dzU1b0tVJiF3
QFlKdmFtOUJVeVo9M2djRWBRNCFATj8hLUxediMKejsyS2p+KlN7U3VIOzdEcHxJdlpxeDBPd3ls
ejlAaCMqYmh3azQkdGlgbzAzbnA+NF9gPXd+cUhDcDhBJjJ0QmZSCnp5ZlRafj1ubTxLVSg+PFZD
Rm5KUntNdXA3Yj9zMyQxPUoqQjc4IXk2YXMjMT5BcTB8WE4mMWc7NndEN2RGNGtadQp6bEFBayQy
bllDbiF7eS1Hc1BMSk9wKnZ7ZDNEeHJCVykqQG5ySjstIzJ+Uz1sTDBYWCZHZyliOFd9YTBKeU5Z
IWcKemcyeHVid0t5VUMxLTYhZCpeNjFaSmFIPUFXc2VyZzAwd3JfJD5Ec303emlKeUBAMUNtaUFS
SiZrN2xmQk1fTUF7CnoxPz94ZT9MVXZhOHc7T31sITF3Y2J7ZVM4bkomSiVjWkFDJUJ4Nzg8enhe
KTx0d3s0P0l0M0dheGlVaXpSYyUtSwp6JlAtaHxfUHlYbjFnSSU1cW1fMEZlWTF4dXFiJX53cUcj
SHhYfn0yXjdqXmB0Z3t6JUkxPz9fQkQ8O09MVXtQaFIKenVoZih+eUA4cVJgaHdrQ144MWZFM0VA
NHx7fDItPzZDazVVSmp2NzUjPT9EQUdvVTZ+dTlOYiZSbnchTDV1Qn0pCnpjJCo4TVJ1dlBKPTdu
KHtQaFJFa3IxRjwkRXhEZTFmbCE7LVRweGYjKnVZYHRUTVU0bmprMlh2JCgqSCsze2x3SAp6JSEq
PnYhPWExdSEqJWglcEk0KmRHKGg0KCRob1VmKENzXzdMR0tBc3JLPH12OyYzVHxxNCU1TlVkPUsj
bWQ/eDQKemhjRE8oRW5VNEFZcUBIZXpjeEBYXjBaKVZKdnklYENPb0VfRlZUZGJoO3FzWmVKdilq
SCRFPSpMZF5qQ0heYnI1Cno3Qnkoe2s9ZDklWUw/Y0YrTDVwSFFRQDU4dm9+ayFHTjNUR1R6YkAm
cWk9OVc8KytYU1YtTjhTJmtOKytBSGdJPgp6VVM9X0pSVSRYODY5PF9Kc0E4NmlrTnUyLU4/dUlI
KWxuP2U9OXVfcS1OMW5kdVg3cllMXjQwR1Z1bzI2YjBuKigKejxpS3U8R3F7MyNIen1XJE9NPkVq
P3x4aEQxQ3IzaGd0dlIzSVhRIzEkUlJIa2c3dDNeaDBza0c4WE5AZmA2PnAmCnpjU3RNSU5aSk9F
X31gem1FJlRHJjk8NVJ7UWJHIW4oVlUwV0lufkxGZEs2emoyYylnSkk/PXd6PndhQnp6ZiQzZQp6
SWFEY1VMQHEhZilQQCM+T2laWWlRK35eanY4QFlecEMqKVIhXjg8U2M4I0lIYUB3KSE+d3NkdHl6
WFBnaCRxeHMKel5keFg5bT59VU40TXJCSzJ9PXdXLUZQSXBaNElXZTYoVSpFblpHflVucC1pMHF3
eXI3dDZxP2wmMUxpSjMpcSEtCno2MD0+QzUwMCZLJTJSI2xuWXFrcEVMPW1DNkUqI1E/UWV1Vl5N
R012JUVIV2pFKWwyWjhtUTsjaVI0U2FeSW1fLQp6REk4cCE2NFp7MlJ2dDUobDN6N205JHpiMyE+
YFhEdkp6eHA4QUxHYGBQNGBEc1pVZ2xVZ21jfnd0SyNzRmoxVFEKend3ZS0yUmZ0KzU1U0V3UHBY
UWV3QWNrJmE3ZypENTY7X0IwPU5qfFRINXAzQm5RSm5lVzslP2FkZGpuNkA1YDxiCnprfGl8OyQx
QWI0QiRKYmU+KXI5KHZAOH5wNFM9fjRwa01iQFprJmpSUX4yfUU3PTl0Rl44VVBldE0qcU11Zlo+
awp6XjQ4fVRnISlBel9OdTg5ZT5qSXtFVip5dGlUeWtqR2Nna3NyQVRaNFYqaSN1JTw9RV93NWVm
ZFRCIV4jViYkXjcKelZPbWE7KHpXVDlodSMpfGpAam1mcERDRV5iVkJXMUgzT3tAKXBxdGpgRnc+
bDI7dTdLandFMlE9UGJLSU9zc19jCnpDdkF5MUpLWmhQVTEzJkBBO1paJSF7MTM3Xl4zLXhFKmxr
RCVBUVJBczIqME1DPmdYZj5PKDVPTCg0X1Q1PEV+dQp6SD53MXF2MiViJmdGNShEZnB1WCtTQ0It
RjkxTjJ1SlBpamVaaUNWMCZ5MU5Bek5zKiZCJHlYb1RIekN8MytkPVAKeiFUQnU3ZlolV01LVH1Q
MEl3RX50UWA5cVpmZyg+MmRhMjt8PjYhR0NnKWljNWsqKlIqOUVzTlg4ZT85N0VVQlByCnp3U3d3
bypmNnNnQDlyWSU5XnxeY2BsLS1UO1BUWXoyc3BZRil5ey0lJEB8Z0MkIzYjeVFHUXU3bVU5YlZR
ZyhPYAp6YnJNTlI1P2AqPCokaSpIWGJsIXdtPWs3NjE9MkZvJUFqZm1mY0BpZ14qUio3aUVxZzRW
M31sIWFfT2BHITZOJlIKejU/I09EYzU4NGowNFFPYko4aTYwLW5eZ1R6O0RmK0tFb0BhMVRDekx2
RXRza2JURTB5ODBSY0l0MnlOPGl3ZjZMCnpqdEl3QjZNM29eWD53ZmhWQEN+aHJhSGVHcWEofUhX
dEdeNlYyfXpKNihwN00pe0VVc3lAVSR+ZkhDfDJ0al44ZQp6e055TFc/KXJVbEhPQUMkUzl4QHZ7
LThuaGdGeTB2RWlsYnJUaTJDcmMyPjtVbV9BVnxpe2VjenJ6S1ItZ0ZldzUKeih3PjdmTGpYb2Bf
clhKYmZpfXREZzZrJjVFKyZsRmItbE1xJlE3Mjt1Y3IhR2c0dl5jXzZMPDZod1QzPSZwYnI2Cnp5
YXFoWXMrcVZTcV9BO2hEUU18QEU1MV5LbWJqUHBQXlM/THZBdilENytVRGtYOE13ODMmQmQxMTtt
SS1WeUZFTAp6eypIRXorLXVnMFVIfm9VMzx3WDBIfTRLY0spWFBPe2NNQD1CdGJANT1VbG43YD0k
Szc8MG5WQmA/ZGxvJklXVGMKeml8NHp2bCR5antKJXhWVGB8QkdkNX0xJUpOcXR0NSl4TihAKnl5
TlZtfj1mRjFTTjRXR0YtQE9BV31pVihGaGM7CnpSbmB2PTFkeUNvR3lNaUU2TWImS0VsTGRwOW1L
QmxIVGJQTHFoSUBjPClXNzZQcWFSJnJJWCtzT2oxTlZScTZ4Nwp6I3FMaUN2QTNLaVQrfXgtJkJe
dn0+Y1daVUVKY1FnK2N8SihiRnt0SVVlSmQxb2FUbFFQYjd5UXg9I3dkemhud0gKemNOKW1QK0pt
OVIkVGlBTGIkKVlZNms/Wn5ad3RrckA4MipOayQ3PyFsJHFOMForU1lHPWpWU2slcFUrbWJNKFUt
CnpiZWI5KFQkaGgqezhnRShnXiZYJXdCYVJqNFhoUl9nbDtCbWEoKGFSe3d9fm4lWkQtMCh2cFgm
VSZvPXtBOHdedQp6V2pYN2hlakxlVlpqLXRCRVdmfDAlUFQ3YDZIaDk2THApSmBDUTkhY2BQRD91
Pk4lSy0+YHhoUEJ2THtNWUdKWUMKelBtZGZYK0hhT0BhPlhlOEBpKHU9YTlQYl9CPzkqWDteKyVP
WSNyfWxNMytBfFB4QU8wVmtobCZUfnE3cEwzUUcmCnptcih0azdvTUE1QDZvcih5fEdhKVdzYSFB
dlRyIW9rZ0pmQiU+fHhFMXp6cUprNUBOTj08Z0sqOyVvLTdgJD9SfQp6JGBXPG5jN3d0S1VzYCFA
S3ZPRlpTVkQhPk5zKj5ra3UyaENZaXF7d3c1WFRSO1EhPHA8K2trSXR3KlpxT19eP2gKekc3fHlD
Rl42Q2xyd05rT0NjRSM1YnVRPktLVEtTd1FvQ1kpKkB5N2JDemMlNVduIyVsKzw4TGNBWnptTmRj
cVZFCnpDbTghK2NxZyFRQShSQ28jV0BsQHREbjhfemZWN3lsLSl8JnB4TH00PDRkMytsZEJlbUcl
TjVzYGtXUmltdV5pdgp6ZS1zVSlTPkE7Z0QqOTI/eW5UJXxtTUt0OFVGQk53M3RJR3k4WkoyMD9o
Qj5IKm1LfHxTeFlBNzE/IUlScVl9TC0KejYxQHZZKlh2KlBfNGpWTFQmODRZOWZ2YyNWRGRAY292
Yj0xQyNVX19ufjlmeTlOJTcrWSVHQz9gSmZPUUVgVklFCnpJO0g2UVlyfWkxLU9qJGx3cVQ8JihA
cUZYb1E8JFhjc05GSWNaSW1gVC0tKDFkKj99IzdFWWx9RWpoT1d4M2p1aAp6aWNaLSpBP1dHPTxU
NiVVTEBFXj5lcSQ1aUQ+XkcjentXTTIhblNoem94fWZwRWxsZkBoZ2N6XyomVzxASk0qY2oKellk
PUdgRF98c0hBbUF2KWRfI1Y5QyoyP2BKWiZJfkBXRDc+K3lWNFpSJGpGezJ5XzJUZiZUZitjdUJJ
PmBJJDU1Cno7M1V4TjFRY2o5bklvMXpANWM9NDhrK3FaP2pITWViMT1sd3dRY1NFeC1aYj5gJD4z
OytfaGRUOEZvJHp5Vjs/LQp6PDI+N1kmMzhmZjw+aDdDS3A/aUAhQUNTS096X31XTmw5MX52YDI+
bSs5Pms/cDt9OWpwd3FuOWp7Rj4tMkpVJE4KelFYUjAtQHYhekhAYj5tKjVzbCo/MTBIZjA2bStP
T0swNEFRdG14UTtsWWt0PkxGaSs1Mkp3TikrLUlNfmdqcG9OCnpuOyV3bkp8OTE8MTFBR092a00j
NV80OF4kX1lRRjZsUi0qeU0tfWReQl8jXjtSbUx3SGZ6SzUwa2ZQdEBlRWQlOwp6PX1FO2pxUGsk
ei10TGIzNDJPLVUlI0dLNVhZWSZrTGB7LSVqWlVAaDlVKjlRZlgpNzd1NCZoMUZ4dlZ7QT9VcUYK
enFKUjJkNmgkIXVGSmJxOVcoRFhuMW9aTnB0WlUtZ21xN1EpaXpVZ0Y4ayhGMGh3SV50TDcocjlU
bjkkS3k+NE1TCnorbDdQdl9DamhANHB2dzc5bVhaelcqMCEwI1I2ez1iM14yOStnRnN4RzQyIUZF
Wjs/UUkmY29NcG5AZz9wNE8wNwp6Y1Jfd0VffV5yMXY9MTFGUkV7MWkoOHlIN2MlTWBAdkEtLTFp
Qz1rN2lyJDwkTD1FNSQrSmM2fGhZfmp7OGReSSMKenZYZmNqLW5TVVV1aV9zfXl3Xk5BSTF4QD5r
K3lCd3JpbH5xS0p9SllgUilBJj5lcm9zZkI7e0gzSHdVRT9ObjRUCnp3czdlemNRcUMjS1ItV3Zo
eHNmPmk9cCR8MjtvZT8rdm5OfCZ9TkN0P0d6WC04MnIlcigyQEZqWVNaO3Q/cW1wQAp6V1lTZih0
KCtCdWU7ZiVhWDtDNnpwb1gjdl4kOFk9SUFpWjRZbVMlOGgwYzVMdUlMQDIqeHVvO2c7Xm5jVWV1
N1IKemFGMzRISj41WHQqK0VzJT5jWWF0KkdodVFoUTIxRTgoeDc0Z1lzWlg/Vko2KEI7OU99OFBo
ZWRtJnh9TUUmSEYtCnpDVj5pME01ND4/RT52cTBjfVhQZ0pGelBnY2tAamhQdTJ7JVpyNTFDWk5k
YSpTPykxSUtCRDhIP2ohb2Z0IS1fRgp6KzVYcE02a1MoPzA+KWtrWWhCTyVMfDV2Y2liMF5VLUJs
bmgkdVF3e0pIJklyXytodiYmZmpHeWMwS2gmNnJIUlEKejRmUGJ5dEVnQmBwUFhXN2I7RXBGV28z
KzkpUTFpQ2RtKT9tci0hY2g0aUhQfkM/e01ZTURKX0pBTmgzdjR2S1UwCnptZysoXj0oT2hIZTcp
bWsrb0RGMVkkJTItTklLdVljWno0ISZTLVI3Uj5jaGM/Q2d4eT0rOTxWcVBvfiFgTnFxLQp6Y1BH
elIoaEpTWjZaSnR5Kyohcj4mJDhVazBWZzY9ezxxVSU4eXlZe0lWXyl3RUlNX3t4M1dtTjsxSEMq
RjVFb1MKekdvczNwNm5JYkFSKnFRSik7QUhCTVNXbXZ6cEl+QmRtbnMlPilMbzdOIXd7SHVGcldf
T21sK09xT0chcGFjZCNWCnplY2ZlSFpAWmglLVQzMnEoJiFOTzxBKWtZPlpvdWViKFRBMGsmeiMl
aC0jV3NefmtJZHVXVG1mYiVDNiRMblRUZAp6YGdkcylWRyQ3dXtaQH5xSU1kaGRoSztBMClYck8l
QX16YnUoK1pyeGtSfDRuXypWZTVANnkzKDEtTzJiO3x8XmEKej4rJDtmTS1HK2BROHFmdiQmTVcr
TGsyNkhARllreWowa3l5LXhTbT8oa25UWmN1Mjh7cjtEU1hLRl8+KEdXKm9lCno2SWwqaGFxciRk
ODdMP1deKzdrJj8wJEZyOFQ1S3I0Y1pnOFJBQ3g8aWIxIXBRK353dytEN3MoRWZheHI1UFFoPQp6
ZTIzIXdAZmVCUj1XQEhWNkxOIXloJldsTEdnfEpAO0hROHUqWTZ0TGZRYl9wOV98MHpRcnN4Y012
RWp3UnlaIyYKelhePT0yOCRRJXJrdzI0bztzN25Qd1k4TnpMIWtOfnNLSF5mPiFkRkM/UjF8S3hv
a2Y2LSNMK2RCQ3poaEh9ZWRVCnpHYkxhUUsjMkBuei1hJCswRD5HbUhMWkVBbHNUPlZzV1lYcjM/
K3tpU3dtWXRsKmttO1QqKTV2UExeZWQhRCFoeAp6NFR3MWIoPEVyWlQ5S18+dEAhWCNBblpgTUM7
IWVTNE1zOzZ7T2RfSiFeWWkrUUkwUEVuK3dTSyNXfmM9JUtDODUKem59JTBGRj4xc091OEhPZzJ7
PVpxKk1YT2t0a2w1KnBGWkU2KU9CPXBuQiZWcW59M1h9R2gzY3AjYnk9aEUkTlY5CnozNGkxcCk+
PGptZTt2O3QoSFE7ODw0UUl9T1VKeHB5UExEMGJUfkFfRHk9fitUYFMwV28jOEpQWiZPQjtZNHJn
bwp6LVhud2EwS1E5TCt5YW18RWpae3tvRXY2PyR4VXk1JTBVVjNnI1ExQT12bm1GY1Jse1UhNEsj
dzJHQ1kqZlJkYj0KS1k/WldHQGMja2JjYEJSJAoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZm
IC0tZ2l0IGEvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzUxMng1MTIvYXBwcy9lY2xpcHNlLnBuZyBi
L2FwcC9yZXMvaWNvbnMvaGljb2xvci81MTJ4NTEyL2FwcHMvZWNsaXBzZS5wbmcKbmV3IGZpbGUg
bW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MC4uZWQ2OGQ3MTNhODI3NWY0ZWNmYTk2NjE3NDg5NDFhOTBjMGY5NDBkNwpHSVQgYmluYXJ5IHBh
dGNoCmxpdGVyYWwgMjM4OTAKemNtWFYxMXlvZWVfa1gofS1RQlUmaVhlenwkMENSenBwOzR9LVFC
YDJBZXx6Sih4SEg7cSk0fTxmKns9YENEUEtkCnp8S2E9bHBSKSh2ZDJpO3ZvMWM1PCZiJW17YCla
Xl9PaGdhX2s9fDhESiVBdU14UChJbGM7TWVaLXtEZ1RHR1Ytbgp6UXF1RnkqcXJlKGYzalNReDNr
S14+TkdMQjdufEEwc1ZMNip4QUEoZUJDKCpMbUZHTGYrXn1DRmIoallsIUxRcSMKej9zZElTai1Q
c00obVA4Kmw/MSlEQiR3SEpaUk5FNz1gNnlyaTtOSHpBbEdiUV4hP1l6PyEmVituWW9rcm9ESiM3
Cnokakc5SyRnckNqYUl1I0YxT0pOUHc7JjJpTl9gR0kyIVk1V2BVV1lZUDxwYCg1RSNIdWZkZiVl
PlJ4KldhVWMtSQp6aVg7I1VnYCRvOC09dz5NI3NkVC1qNXVrITN6NFhZT1M7WFUmcyZrNEBzbmdr
TW4xP1Qmd3Z6fWtCaUFOPUZVRkMKejcxQHFeNTA+eFk7d1pYX0sqRlJsajQqWCgzRmp8enlRT0BP
QTZHbE05Rzt4cj5FT0NtRCk5YU9CVkZUU2dwOXR2CnptdEM0Y3tzeDdvUncqODJHOFJgP0dDXzN3
SUk7K3JGb2J+O1J8eVlOcUpmNyVDTnYjRXB7P187eGJ4P2JjTFMzSwp6JDZkWllAfFY1b0dxdHVX
PXd1YEdjdiMkVD8+RTZBWnBnUT9TQzRCOVJuOERRPThEKCY7S0RkJUIrdGRMdDVKTG4KekxYRjQw
IXxea2w0P318b2w2P2lsYnEkaU9ePnl1T159fnZoSXlBSXQxPEx5UndyT05xYG5oJllkVi05QDJk
JC1iCnpXS0NWRFdQVCtJNHVZT202KHQlQDB0XztlTFh8U0Y3MUVfSzdpUXB5IyMydiU7b1N8ZjZt
QnQzdThZTzlOU31CJQp6YCNedGxkfCtWc2NyYzJPNis2aDdlV0VGbXF7S25TQS08ek9nfSM+VEtt
d2ljIU9PQHBleX0ka1ckaUMwJG9ib0QKel5rO2c2MWhAUCFrX30yayteRExeeitAIThPdGVCKWtm
YGVCNnE1e35ecmxKaGFKYSNYTUJCajZSOzB+VlI3cGYqCnpoT1d9aiR4R3s/Y2pmaXE0U0RvPjJZ
WXt9JXZnZFlNST4xVTFIb1AtajYqPmFhKWR0SkZmOCVCVHReMz9lSytEVwp6KWdzeityT0pKdUp3
fnVlYThuVX12dkF8S1dHdjMzc1dWMDdlRypacCghOWc8Z1lMRV9GU1Z3MXJNLUNpc01LSG0Kej9A
djB2SDJBSEwzODgmUEtScFdLNHBxZU04SEQkODskZno1O2dzUSYlPn1Nekp+Uis4YWY+Yk9eM2ZF
Zk5+aFFVCnpfRzhlTlg0aTxOTGNrKzNFMFJCK2dGeUpMcnRwJj1Xa3YkUj0+bCNhWERXc18tSXtP
dHZgJndlKUd2Z2BMMldwTgp6elFOeEc/fnk8Z1JgN1lxeW18a3RPcmZBei05SnhzPkduVCRRU3N8
XmFoIUI8Mih8PjNBPDE0PGx4UE1yU34kSjAKeiU7PEJPa3ptOykhU29FYXFlX3BKcFhrSFJiUWZj
dzFBPF5Lb0pafFlxNy1HMV9HdnNtbzNIc1YyVztURnVeQXZ8CnpEPENkSzdsb2pUOyRYQSE8dzBu
SzRPK2hGdmtvMXg0KCtwXm4lfUwjZE1yTEZsbitgP0Y/M2NIQSRaWHVnflJ3MQp6UXFOe28pU25z
XkFJcSUxYDI5eGtOcCZfZTV1UD8tZ21TcDZXR3BJI0diSXdxe0tOWFRxZDJwcGNmRUR4KWF6SmcK
emk5P3NfXkJweEkoRkIoKjkxMl9zJTZETmY0bGkrTmdqe3h+PHVgcUgmPXpyRTtOfHx9VjM3PEI1
Zj5HaU19Unp+CnpaYWhIPF5sXmwhek1VKzZXXmx0QDF7PThld290YXRjWHpRNWZ+Jl85NFp4bTNs
RVFFZEtReTlIdnh8Unc/biZMPgp6VXkzPXtQcChMMG1AKzMpI0FjSjRhYH1+SV4xUTMwZDl7cGFL
Kn5rY0JNKW8yO359JUBEakckRkJxZERXPTBqb1YKenhkO3I/eklfem4rO0FCRnUtYjkqeGdVfXhp
PEpuRWt9T1E+WjktJkczcmhGSmhfI0JCN2NDM2YrMX1sVTErdHokCnphZ085JSU4a3dlN2lCJTBf
JjY8MXEoT141S154NDV0Y3xEYlZzb1V8TGg8byZsdShHNSU0MnM+czVBNCoyXzFjdAp6WVl7VXxa
cytmIW4oTUdXPGchbFhNeUQ7NSFHWGA5VkBaNXl0aCZpPDxkJWNIYWk5djRDVG5uZVRUUFRuKDk7
QmsKekBgT0dhK18yOU9FMVRHNCpMb3dsRmgraUhMYXEmQ0FjMmN3VkNMa3ZwYCpTcl4hQVI9KyNg
UHZCdXhoRzh1PD5qCnowO08mZzZBNF5qS1luP2lVWjcjfll4ZGtCOF5vVH1nKCZoUmZxSitRYiEt
PU5ZSkJIUWdVIVk+TG1UeUYlfENfMAp6K1pVOV9SOGdvJD0wMWAtT1A+WkVpWEFTYENWcmF1YzNH
TCNKOH5yezw+Wmw8Snk/aDMqcEMkSlliamhfZW0yfHUKenlMTV9YJXVzZ2k2ZW5YXjRXKHl8dEVB
fHFDMDZ7PTBZUiFvTjxNcUlwTTRxQm58eiZCZU0/TnxDQkdRLTJKJFUhCnpVYTh8VVleWGt1ND8+
JE9IX3dyVztWKkNeXyNLa0NiMzR+alQzUkZoRG1IIVJteVA3LWZBa0BfcTg2VTs4LWZyNAp6bHAm
O1c8b15CUVh4aFdjI147RDkkU2t7P0ZiSVc4PjlEVkFUbFplU1MtMjVaWUVwbTlYT2tVeD1uVnp3
NGF+dyoKelhyTmY9UHQpbzBqczhwOWkmT1MlWEU7P3MmRHJmMjBNUnVsYUVCIXc8fl5sazNibkZO
TCROMUkrdTUqekkzaDtVCnpxR1UrdFZzOzkrPitqSmk9UmFIUEMobTg5Z350QnlBck1mSDEhO3wo
Ykl0VHQ3dXQwLSE2aSFwOW1KZHpMeSVKQwp6UDdkS2d2cm40I0ZScjtYQUZLb2QoUEVvUjZTN2FF
QjVpUyVEOFBGYkpuSlNgU1p7NGxYM3FwMUp5RE94T1d3P2EKekZTOUBiblZGZSFHMGw1YjR3Ris7
XmtARzVKa0E/QGgmPTZRUmdWYHc5UGs0KkhsSlFfcTNoPD5KLXkrYD88PXxgCnp1JCt8LVhhJXYk
djc/IXprTWRAN0ZQbHUrXntPMElTU1RzMlViZFFKeDtCKkpEeUA0SzllX1hDXmVkcExkdEZ+Qwp6
KT9SfXNGLUt+MSV+ckR4TGR9PXZYNCQxM2JFYHQwU3xJVS0wT3hZOG8hTH1sXiV8QjRhekEycTtp
fDFTcEFoWUgKekN4V09qcn1xPyYtVjtrV1A1Szc3XyN9aj5UJXU2UGd6MF5GKW1feD1HSHp8Oypn
WjdiNF9BPjdRKCtgcFU8fTk5CnpSI3NON2U+Nk1xe2hYTztWeiN4bDZePTtsSTgjQlB1SkpQUjQz
Q2NIbUU+Tk1sVmd7SnMtLWdmWE9OKkwqRSpFeAp6NlIoWj4lbXc8S15VeSF2dCotYXB5bVlydzw0
YWNuNjImMkl0bz5hPm90NGFfbil2byNZY3tFTVUmZSpMRHZ6YW4KemMpJClUeD9EQkdOKno9O1Vt
bUQ1JXtIbD1vfVRJfm1QU05JTWtqTCswR1Y5PGpNO0JDb28qTmspYXxzOUF7VG1zCnotP0twV1Rl
VFl7UXJnKEZ4N2RSZHxNYXM5KzVsTzYxZm47O196JUJ0VzdUSUhsakZCU0NPJEo+PjxCOzApfSk4
VQp6dSRJNzhyfExleHRAWUsqPjZyPFdwRElVR2wpQ2EwdFlwM3A0Z3ZTMkhzOVRBIXNiN2p5RWI2
Qm1pOW5EOHJISE8KeiVJcVMpSUZmMV9TV3tSKE1IX2A4RzlrYUpILU8kO0dPTXZgYFNHPj96Nkoh
SDskZGMkJEM5SFQ1SlIpZk8kVkR4Cnp2d2o7aDNXdUl2UVo/ITlsJDVrZEJsY217Q0VfQTN2a2Y9
NHtDMWs/Nk9DYD1hM312Vmd8YU83Jkd3cFNHQlh7NAp6SkBpfmJpa1puWWBEKnEzd2NOaU1oaGA0
fU5JVGEtVElXMyNXVVNEJWp2cGM5N3RvX31ITnJeMVY5Zyh0SVNeRUMKekx+P2JiZGRfJlNASlVt
XmNWJWN4ZENaZVRnQTxaO0lVOTdeSCsjUE9VYWR+MS1lTFNhRHphI3RUU2MqT1h+ZlZwCno9eSNY
SWcqZ25lJCNwbXQ/Tz1uN3d9Q1B6Z2YzVDQpY21GRU87YD9yXkZFYEU9QF4oQWQzZG9HQlpPVmcz
Zk91fQp6bXtUXyg3TVMjbTRFb0JLPEBAWntMdX1BIyFpPFREWTUjeFk+NyE1c0djeW0qaDg0MVdr
SVR7TDdEVW0kOVdCcEQKenAjdUduMjM2RDh7V0c+ZG8xM2hDN2d3ejR5LT92aWUlPmZaZSFrYkxB
WWZBR0RGQXVvSSF2Wk1uPGdFWUtSUWJuCnpsM1lFWF5ZLXp+VEhIX2g0WmpEfXZtbmJ4LXIhWUxE
IWNibk97bGNBKUo2M3J0N19UITlTOC1IclcoOE1rX1hEawp6NzUrTyZuUXFlbilnQTw4fEJSNSYt
YWZ0fFJRczB+SSlHaiVrQkooV1V4VCphWFBeQkZHcjk4VyZHcUhyS3V8fG8KenVHaHQ5Wkx4V0pk
enlPcGdxaFZhVjUkZWlORFZiWGo5I2Z9dDVie0ZXZ0NQKmZuOFYkQEpifENUMHc0b0pAWFRCCnpy
O31hNXhrZjhrd0N6dktHZVlSS099NE4xXmJNaUxRLSE4MSgtO0soaCYyX2NPdXQ7TzIke2BkK2g7
Q3FLMio/Xwp6SX5jfT1VTXI4YChzWGV2aFIkdWYpWHg5ZFhXTHFIUjdpX0I7NmRjTXxNcnk5ZVBW
e34mJlFybChmYEBsQFBYP1AKektobk14M2s/Uz9GQTQ+SUE2dkU5Mmo7MCotcm1ufEY1UW1vTkpW
ZF5CU1RLMEZmd1JGIVZKQjE5KUViKShLTVNSCno5Z1A0cmFJYiVXfDZvKTcjaC0xbnZ6YWpEJlUx
YDE5eUlqcHtrYDxMcCM5SGgmKmtMcj5KdiotREZaPDhDQCMqYwp6dTI9SjQmOColSSt9XkJ5MD0q
Jjl6bjhsTGZJRj5VQC1vP01ZcXNpNF9VMGpnZnN9OFgtdVpVSk1jQXtTSC00Sm4Kem5AZUNDQiRr
eHBBaiMmXzw8Zzlxc2lePXFgWkc+TXAycEpBKzJHV2FOMl83OD1nQ3steilLdXJOPVZiQztvcUo4
CnpAQj9PLWdNLXRXQHZFMygoSGFfPDhqNEFmZX5ldjklP195TE5RVjxxTEpiUF9PWSFMIUwxLTBP
SGxkYXdZN2s3Twp6aD9qfmo+X3pxNFRsRnJBdXRURW1CTmp+Qk13NEhrLUZDeDR6blJSVzN+dEd4
OGVtWTlNcGFaKWRgKnB8ZTI0ZioKeilfM2tVMW9zUXJkTS14XiomWH5EaU14P25UMnVMUnRaUExa
PFBxJjUoU0lrV0ZIJnc4bz9DOD1lbTtPbVBXLW8/Cno8M1ZHZT1qdTtCVVI8PV44bmhLbig3eTcq
aFAqKX1KYjM8P3h1a1pCMm08dDZuJjZtfHBYbEBiWnpiXzFIX2szRAp6VyN4RSkrVTw2WjRzc2hD
SiRDYzRYS1QzNyU1enk4Rm1UbCtMSDJZOzUjNmslPnpsKDRkfUR6fFJZe25sT3p3MGkKenlQMzQq
UmxAMkk7MXlqeXI1OVUwRSlBIURuIVVGdE8tUyY7TkNkeGg5eHxgfGdSYWNoSHxuNERPSXRGZ2FF
ampiCnp7cEcjWm0mVXQ0dERkamRPUHJqWVVqWWZ+NDN6dyo3WjsxYWR9ZEdOQV5JZGFRNSR6d3NK
T31SV0s1ZH5Qbz1WTAp6IThKWlI4YVZ6SlArI0dPdyQ+ViZsXjt0JkB5N0NvSCpxaSZGJiFCanFi
MnA+NWhwd2RndFR6KkMxZzxnWGd8fFAKejtQc0YkI3V5THQ9VlBoeWJBS2RfXm8jbG5OPWkhQkh8
cEZXdTFMfFBzaERPakRvbkFsb09US1BLUHVfcyZVSTxvCnptci1DQEhNRzZtUnArKFFvYm54enhQ
fmRkQkptaFdsaCZ6PzFxXj9QeHwyXjNwXlJeSzZ6NmJYSWVyRUhuOys3MQp6blBAblBIc15TZzl8
NGohellBYlB7UH53JWNTeCsoX3VMcDRuKDc7eWxheWhKe31HS3NOY3M4I1VHNHpAcTlCVnsKekwy
dVY+X2d5cHBlej4lWGZRQjJZSnYrd1c9bF83NmxWMil3TD4/TDUjMWdwKzZENGohPTBXcVI8ZUVn
YEEkK1BlCnpiMEFJVy1hI3d+MUxOOHEmN3JaRG1NMDliMntLNHVOY0w8Xz10WVBVNCozeXFmTWlD
a0FxcFpxUVh6JT9eVk9Iagp6Q2gkcnw9LVhGOHIrJCNiXktfN2YtfDJ5dT5je0ZKYWtHRC1PJHs5
a05oYCp5IUktfWFyPio0bzJfdn1KUjk3Z20KejBKfCVjVWVjbHZQcStJZDA9SyFMTHF8RGhhVTh7
aXViV2Z5XmVjc0VBa0hWRWhfPjtzVVE9UCtpYExOZmRrR2YpCnpTS0phcnc1eUA9YmEmcE1mIS0j
bDw1M2h1NWViKj1FfDxidjZ7Uk1sSTI8cTZFdiM9cWxCV0tiQ20hdCFpQTVWMwp6PU83JUN3ZHpX
XlNqZUtWQ3FJVylqU3M4N2s4JT5qSUcmX0tlKnhjJjNsdSZWVHApTGJzWX1BbWU2fF84ZkJrQmkK
ekFiP2g2d2lgUyYxZWh8RCloJGBuMG5mSlZpQFREfiVFJGoqSnNfJG08NWQpZ1cwcXpsPUE+ZjJV
czYkMEUqbyVECnp3Tl4tXldgcW07Qn42VGolcmBhO0dUOGBrVW9GI0BBOEBrLW15WUAxTVJQelRC
LWshcV92MzdVclBYLWlJR1ZORgp6Tz1yQjJ1K15UP1RSZG9eKlhLMW1iNC1XR2F8WW57KGk5Km8t
Wk0zRzdsMGdpNkpFSk5ZcjYrKilOIWNXfE5wZXkKem1aV2g7UEt+UXcxPW9mT2BVWE4rZGcqMk53
NkFRfFR+ZVNTUHQzRCZoUD1VQGtkY3B1SGxCX2NPKnJOdDdhdns4CnpMOHR4M0AzI1VfXlo5QCVY
fVF0Iy1hdSo0WkVfNkhPamkjUWBtKklIJElyQzliTEE4QTluVytmcl4rdm9tY3J5NQp6dU9NP1dk
PS16eTNgaWE1KURTRVBiOUhSVmg9ayFCTy1IaTx7bDNhc3l4LW1IZXU4PW9XdjkrZjcxXzBmLTtC
TEgKenYtXnBvRSYmO19vaCklaGJYZDVCbWg2dlRuZVhKP2hCVmJ+JkEoSXlkMDhDMG81VUg7a1p8
P3B3N2tzQWBNKn5sCnpwYlh9WmV7fjkmT28jbTxnTXQtcHR6fHBeWWpPflA3c0pyNTsoS3klaWk4
Z0dtQXomX0VzWFFLJFlSdSo9ZXReTgp6Uzd9KHcmTnBncFVzfjB9O15NU140YDNWSmEybk5NI0Vr
PU8qPEYrJXEqNlNXZUlGOFRKZkhxUExgQiR0Y0A8KnMKelB8QlNmTFFOdSFjQ3FreHcyLXQ8d1JW
YVg4VEpad2xMWXc2OTFPZWstY2RzRE02LVU8a2wrPF5RO0Yyelp+KGRzCno7MGhqbWRBKW14MENT
NWVMMkRpa2BZQDw0OT5DNCtGJChJYFluSTVRZ3pqbn4xKjFQPFJJV05QVmZwPDAkKjU7RQp6enQm
YmkjNnR1UXFvMnhlNmZaOFl7ckJ1V2w4OHEyXklWTnZKfUQtI19vI3BnaVVtMVN1UUNzTFU1KmdJ
JjJvNGkKenZoRFV5KmBZYHBIUHsxRT0pdSVWVz95dk1lPmw+aXNIXkFyc1FMWjE+diROd1lEVj9J
emAlU3h7a3l3VWt3fHYxCnpscjNmQDh+PU00VHE8dCNnVStiVytVUWVIRFA5ampqOHZfQVFITFlt
aSRMPFZefTI5aFModyZQVmp7SlVDRjd0awp6M3ZqUDtAWWsxUUteLV5Qb00xdG5BPXNRa1dESzlQ
N3FvaWprNTFCRkU8eHN6OVR2djAjM0RzcEJ9YD1qbFc3OUkKemIxSEYzbiFSTV57aEV5WGt7PXk3
Nz5DfURyT1dOMjsxP0djWXhfc31yT282KVhvY3MyZm9vZnZzdkh5b3dvYSZKCno0U29GPTdFZ3M5
Nz9UUSpHfUFwcFEyTip2emgxMVMpR2h3T09VPVpARyUmN3s1TUMhZT5AVH1oQyNSd3slTW4/Vwp6
NmtCJWgmS3AmbkE5eU56QUNZWVc4ZjZTNSFjbUNXa2YqbFJpSHxnJDUyJnhma2BpVDAqTz5IN0BJ
NShsP0kySXYKejBuUUMzc15halAwenw9ZWJ6NyFxI25DVW88JWheM3FMNjQze2pvZDQjKWVOfj5M
dz0+OG5iKjYhQ1Jtekl5IXUyCnpeTXUpOylQJEpyZWdASmJ0eXQra144Um0waD1KeWpuX1V7dzdM
SXpkMzBuZlFNY05iTHk3JCsjO3ooVShPb1ctYQp6WXFZRn44VHdxK3NhVFEtJCRBSlBFTUpVcHop
cEFPUF4+emxZdm0wOFl+bFgwYTU9aCZFUztTMUJMN34qWDZhRFcKekQ9VF44VTk4PnZIbyMyU25q
TSlkI0hQfW1naSZ+QHMxdjAhPW9PaDRgNmoyYFR2JDw8QUA/MyF6PyNfRDg9dUFDCnoyRHE/eXUp
cGRKY3UzQkI+YjJTP0xqKGdrVHFQZHtKUnhPd2AtJmIqKVA1MUtYbzd2KTQ7NT51RT9uUFhqUDZm
JQp6ZFhifVQ4ajxTI24jOUcxcmVybVVNJUIlbzhxIV9DVzQ/U2REOUU3VFBtKlRyVG9YckVxaUoy
RSo7REc+LWkxfkAKekZvTT8hS3xCbj5ibihnd0JwSiQtWVpXMSo+SiVGfEB7U31ZMTU5TU9Wb1p0
LSs+dXxeM0VUdiRvOW81WE51M0wrCnpvZVBQYlE+b2JzaUwyUGl8SlhZYHQkaDU3aSF1YSkhU2tZ
SGk7XiUoNnI1MkE2ejVGbkQ9S3wpdClVJExWKE1CcAp6bT01ajhgfUp2RCNwTDRSVnQhMn4xdlpP
Mikja3Q2eEdgKVY9SlkkTldPaFhSU0YtWjlFOD8pNnRDIWpob1Q/MCoKeiFgM2MyekwqcEVhfWRi
QUc9NmNUPGIlPUJUeGl2V29ZQn1eJW1JdkRwNkhZVUlxeFFvY3U0PyRsaXU1eDw0ejtgCnpXVyM8
QXh+cmQ2TVZVSkE5bVpuRWFYQXoqTn1BIXB6WVRGbkAoNEpxT3d5ekg8QkxCZSh2SE5qQnRRaGtD
SGY5Ygp6NSFmakNJMVUyYXFTRSU/Z3coZXpkTSRzaiRnI3pWPE54VXNBQWErTC1Oa3tCQHYlMWht
KVc0QUNWQVVuaVgzfkQKelU9QWVUUEUjfVdjWW89IUE3akJzJnNpZj0ySDIhUEpiXzwmd2JSdDxy
bkR6QWptVDtvODNybFJrUDApUilibnVqCnpUVSEocnp0QyQ5PHZRNGxmJSt4S2YhQjRCWSVwbFZ6
d3dRezY7Yj9LRFEwe0x2SFlIQVlLPEx1P0pabTBEJFF+Zwp6QElIM1Q9O3Bud2I1Nnl2VD1IcUl5
bCZ0NjBEOUIpJCpBZ2pwUWohSldeVDcjSmg+SFNQLTMpLT8oezA1JFRuTnkKejdObXg3RyM8ZyhN
Qkt9d1hLVGApQ0s4Ky1EYlBiUXNFJi13V3tXRUJ3XnhBaE1xO1NqPGZvSDJ2KlJ6VTlyV0ZrCnoq
ZjY9VE9WQFAqJlRfbUNse2E+a2grb3tJRFpwPVhCdEtlO0QtbXhQdWY9aWt0bH42UCZmZUtxOVQ2
PWAzbTtlSAp6TkpRYWlDZ0h4YTF1Q3xxTShSRXFATH5tVGFBJCljWVM2N1ZGRT9gU3slMHJZd0R0
VCl4LWpGPy19Xj5+X0tJfV4KekRqUj07TStiNDxQdkxoSDlrTUFzODV4Vj9uLVg3SXBMdFN0bzI3
Zzg5K0VoXks+MlBfQnVBfm95Qj5+SyQ3Rkt+CnoyRH5EWHdLXzdeJDZJUHAmSVN1Q0N0QUYmbVhW
JiNpelF5Y2xlZzFBPlp2JTFYaiZgemVsK31aQmxEbEZgP2ZRSQp6bjFXNWxJYC1xNDM1dVBDYigx
R01zM340WXZlVyR3c0B+VmQ0dzN3WHMxI2gzKHUrcVRFdGJOe2lgYEpsRXhGb3cKekg4d2FATHh8
eHw3X3xJMDd9NExSK1FwSmtZdGg7TVI1WSQzdl9OVXxaYGtBez5+bFJtZ0xneDA+KWgpU0JMP2pG
CnpGNkN3VTV8e1hlPzBfZSE/anNldypIMC1famt2amY7Qmw+ej11OXhLXis9SUoxNzRaQlk1ZHtz
KjZzOE9hK0lyVgp6ZXhqWkFqVEE/eDdyI3olYmJQKzVPcFJPJWJZKHElM1ZTci0paUJhWG9aeDVA
eDtqfntHK0lPSyMwaGxtaWlqNnAKejZsTmtSUXxFbmlTbCRXT3toKDFPdWBod0tXeHJFdmRefiNC
Vz9gNXN7Pjk4UUhveUYwQzd8QWxEJSFNQ15sdkFlCnp6VUNXcnR6MSoxaT18VXpgR1JkP0oyNnE4
aVc1aFdLeXVZMl5PdT98dl5ta3FydnkrOWZwQUt4JTlHQ2RDeHpMZQp6VDt4KERObEk7elZjelkh
TU57NU5QRSh7TjJKKTlOSVVEMGxmNGJQS0tlWWpoRFp9IW9EZTZPRnNOY0FHNihzckcKenReOUF6
RFFjTkdRd2xzIU1id34zaCgqQ3F5MjxUeTsqRlRzV0xjUFhRdTcwVUcocW5RPiVlM15FWU10ZSZh
fk8tCnpVViEofjdfLTQqJEtmVlBIX3g0al8ha0pTKy1ATUp1Kld7NlBqSCQxUCp1aWhQcFJoZXVQ
VEZyOC1qek5VM19rMQp6QW4tIXg+KC0wV0teZnNNcjN0b3woaWpeYnImaFUqKkFgbDZBSXshRjBw
QDkwYXwrVGojeURaNypzejtYTkUtJkkKejIqRTFtamM3dVRgbn5aVl8/TnJjZTUmWChSX0NBVkpX
SkxgJnYxQWJaTWwhbXVjVEZZKVFKMT4re0NYbShfTVErCno0fGo+NWB4WSFfQENQTX58SzluQmZA
cVAjciE+eTt0STkwPzxEMy1YUFRNMTF0ZGtgLWs/R1krPGFoOCZTbjlscgp6UEp9az95MHBneFQ5
ZEw4KiNDejJDZ2otPmJtVzZENXhDPmJsKFd+Q1pDeS0yVTdTJktAeHxqN3d1cD1LJV5rOWgKejt1
KDQ1IyNkIT5rfCR2PHI3UEhgUWZoX3M5bD9nRnB7JnhSNTBTXztYJlQoV3l0aCtYM015SjRNWFMl
ZndyIS11CnorQVhYMTZ7dEpZaVljcUA8UTArK28rUFBVdj0/clhJJFVtKzN2WmQ4djlabTNyRExM
UkRmVyNuJFd4I1QyNFEzXgp6cUMhKE0yQnFBQGdaU158YW0rWEQ0IUk1Rz9KczBWbEN7JSF8SHs5
R1dkNXFgdzg0fSVVQUB9KkpNfjR1eSFNbVAKemNeaWowUnJTflZrN2EwXlVsYzNHZSpnfD4jOWVZ
entlMlYrKTd3djNtRzMmbXhjWTRSP15+fCRHY1ZQIUl6UmtqCnpyX1RjXnQrWGZkdiorMHBSZzRQ
OUo1RkVyVDRldGJkWVkpfCNkRFEobSEpZT9UVk9RRWFHO2JwYCtQISlKe2kyIwp6Pj55ckxzbHp2
PyQyUjIyViQ4V31PSStSdT9QWm1qPC0kJFhkdFMxWTQpPHA1M3d7LUBHbGxGalh5UyNYVW5fYmkK
ejRDeT9RYlE8PVo0ak0oJipsNk92bFQjUz09Zjw8QHlKS3Q4KnpeNiZfT2chYitAbmphPHxJXk5V
aTtnPWt5eSRyCnpBVlNwakdJY3RtU1FnVHAjViR5Wj1YM3dGRV5SVWVIb25aflJIeWB4SEdoK19U
cW5EKjNPa3ZjVndeRzM4RU1hRQp6cmBEazdIWFMjN0Q/YlhsaCY/Pns8O2o4UU80UDkkKlBePkFz
SHF3VSEpUFF5XkJ6a0QzdWs7OCFOcVJfMHtAVlEKemFpWXMkYj9CZUx7KWYoJlgoZFklJXlWNnQ0
ekp6JmZfa01AQTV1b0RuVHdAPztMRS13TU9fMCU8Pnw3aFNTO0wrCno/fSp+ZGZaWChFdmZsZjd2
SGxxfkN9T1RBNUIjSFRzXkNjbTRYYEg2fEZJSFVTVXpPK2A8JWBuUT9lMXN5X2wkZgp6JkhHaUQy
VHN1JSg4Z1Y8M1RLKWl4OVBWPFBsV005YFdneVApU2V8Tzd+dXomMkEmPXtVO2Y7aDN+YHRYeEUy
Xj8KeldWJXQlJWt6PXtHQG8rM2tGSkRVVHtUUTBQTEp3RzkmQyhWbC1eQUdrMXZDYkNMWVA2UFBY
QXhlZVMxT2hAMGtiCno+NH0+RHdkJjc3X35jSUshZ0tHYmxfS0pHV1FrcmB6TD5GdnJJT302MTUm
OEVYakN5YiVidWUmT0ApUHxldj9EZQp6SXAyd3JOMEBWfmU0Y0p3ezNDT0BkPWU2NWVBPHVSKFFP
dmBuTC1feHRZY1l9TWlrTjBPQmtaKFlLTXp5R2BQPnoKem58bksqWiQzVlpGVy1MbERNaGhrJmta
bGQ0UlIkdndCU0cyZjdJI057cmMqc3lBfHtsPmZDJEFRaUR3JighdiNHCnpOJFI4MGFncGZ7dyFm
ZFI9alUtcEEpM1V6JGVOX0Z3aFQ1fV8mOyNZXmZ4ZSpxY0UkIWc1UmotM3NKUUduQ3M4Rgp6cW4j
TTk/PXw1SHc1JXJoJURXNSNOcmQ5bU1ecmcmPlQtfVBnbU00al5tVj5Ucz5APWIhQjFGfElVJCN7
cGN2MEAKejFrYmkhYGM+LUQoREBtYXU1cztlc2ZPOCF3NlZJVjJlYzJWZGJIcnkjSkh9e0FTO2Z6
clZNdzs5OXc5ZHdxRFh6Cnp4fClxQ3NKK2VrUmd9Yn1SQmI4SUBLZio+SWhwYVRmNyFufmYtOU1F
PGM8SFc0Mj82K1JebWFyd19iX1NVWCZ3UQp6ajNweVE2N1FSPkBJdzRkZz5nJn4qKnw0cWhaRmNK
cE47XkhHa0J0NU5pWkFwY3prcEFPN2taaGlKTntLaks/KUcKej4/dj00QDhhZ1V6N2I0QnNwTmpv
QzI5cDBTLTN8ey1sPGlZNU1ucFdObTB6SUdVbzdeSFBPJW9fZSpnOChQclVeCnohZUFZeHAtQDI3
JDVZKU5qVipxTCZfMnRSLS1eQSZtJnYrSGNrPzJqa1VoZjBrWXx4elA1IWo8bzN4SjFZbHNZKQp6
PylgVXRANjdKOWRGbU1FZEBAaCFvUipoVnNHPXJHODQ0MUJuN2NkMkc5Mzs/OCozdTZuN1YoenJU
a1N2dEU1azcKeisxcEYkRF83V1pvYnktPnl0MlhXPUNhVUk+RDFfUW0yO2tQJXlxKUdmdjMwQWgp
c3g2WlVLQ1hsI1VAcUtsV3VSCnpoLVczWD5uQmxVOHNHWCpyMVFFb2N5ZyRFd0k3NmJiamQ7KjIh
P0RLYENmK14pQ3JaTEM4IVNTZG1nTWtEQUskSQp6PkNCMnZ1cElCVjRHQkJ7bH5rYEoqU05WczM9
dU4hUmc0VXIyZ35gKXNfa3ByQHxQSXp2MUg5dUBzeFR8RkYjUyUKeiYqNkprI0B0Nnk2Q2BaS2h5
eUxfJDIxYT0zKDJ4dGJqQzZjbyooJGFkdz1OPHo7cGtib1dMKkFeYmZmNDxGNVg1Cnp5OEMoQDZ+
IUZ5SGVCQylrYDBIZlh1O2dSN3lOdXxAX1ZBOVV0X35YOVpzYFcqeUVLU29wT0haRX1KPHo5NlMk
bwp6aHRvSG5hS0FxTTU/WWptT3BEZSp6JDFEKERIST5JPis+T24zUz02T0gqe19DLTJSem5wU1NC
R3d9VzsqXmVHZn4KekFHYlp4RTxidExAaiNSYDdsbXMpa3lhNH4hPzxzODZ5bD8kX0MkU3xuS31E
MUBGSUg+ZyNBVWM5NGBsdHZ0K2h5CnooeUBsR1duKnx8PmkzXlc+Yn0kIUM0RE1JbHpBT2ZmZE1u
Xkd4Rzc4NiZDZ00jenZMWEphKTNRRkxSTn0pckxYIwp6YD5BNTJzZzMmcnJwfExPPWh+djhsUnAo
bGNKRkY4YX01QG5McGQzWW4/PGM9QHpTaFNZJWNCIVh1RiZmd0khWGAKekw2RzJLUG9MUnsqSz5+
dlYmOTtudVVDNWNPO3NGMWs9anJ8MHR8OXJeem8qej99QTtDUFhLNDEwKnheNVlXa21ECnorKy1o
eF5JPmd9eitIc1VqMHhNKlokTDA8Z25pOz9BPFQmZGZIdnkpISQ5YD0/eyhWfUg+SUBPSUJvTXA9
bkE7aQp6Z3VVJVRfbXk7aGJNPDM0bXg8NypZKHo8UzxuPGAhUjMpQmg3XmIyYVdYUzlVUz1PY0U4
UjMyQGhMSEJPMXx8SmgKekczV3BBa0VaPDtgbW5wQmFXdyYoelp5bX5eP0xLJTtlPjNzRn4wek9K
K2ghdG9tU1khKWh6Sz1rQG49ckhUMnJVCnpHbHwle150VFBYMi1zPT4hUypoSXpRcHRwTEg8YElJ
WWI+bnJ1dlpCMVRUZEY1OSY9ekN4MyhxdElGcXlGQWcxRgp6VzM0a2FzbEh+Zl9BXlVudE1KNXk8
ays/NiR4bmB3SiN0MX1lbXJ1WFBoQFEzPjF6Oz4mcDtxY253bVo/XlJScWwKejxnPTVgKlEoOWhY
OXw2RHNnYTkkNjRgZVlfezFwUnN7KXVzO0FKa15jdyVhM2dzdU1tKF9NMXc4PWc9fXR1aXN1Cnoh
N0pHTlNZTGxRP1dXTFlIWUUxXlZySTRjd3lZeUhqUGt3YWtsMmYqVGFySVVsfmF7QGZWRCtMaEQ7
SyZlQGZHRgp6ejIrTWV2dnRia1FpJTlsYyFER0N7Rzx4RWJaPWZCXkAhN2ZBMUsyaHxISHQwb3RP
OGRwZncycDRGTlBTX1FWYV8KenU9R0BmV0c/OSlgNmM/QnsrWXVpY0JZRCErfGxVZSMpQncrNGI4
aFA5OEJoLTNgOGJHJVhnJiUtK0RrdSE4XkwmCnpFPENncTgkMEN4UDdiR0dTOH58cmUjZkhvRzl0
VG0/LVJZIzJGRl9MUEcoIzhaO2VkfXw0a2NDTG1SIV5lUDVsZQp6cV9jd0hNYitrUEQ1QnpiVGE+
PC1rd0QyNm0xJXRRTnhTJUBefUpPcDxkOCUmbVJKMVJzcnpGLS1TLWQwOyU7Mn4KejYkRzQxcXJq
bHZ0P05nQXhYQ08zZVlFISZvb3Q8eClCTyRaeW12SlNsQCpRUEZYVlFBdWVJMT1RaEVpTGM0RE51
CnorVXl6NSVrTVV4Ukk5MWY5NXghZG84RitAcWBkbzAqTkt2b3BzakgzdCVseTh6XyhuR1hOejsx
bmBEN3JKXnMhMgp6diolKGFVSGJSVGwtYkVHRz9FUmFKenZ5eihgfHdYQjxtalo1PEVWeVM7dDl6
O0JwRD1PdlNPISRDWnBgak5WMF4KejYlX0Y9Nzh8ZEw2aCNVezFCTEdDZzJ4a29eWVE3PD92fGRv
NUZZT2lpRVhkY0pWMmFzbSVzUjdmQDRSMzB8Zz5yCnpFdCQ2eWxzLT57ZCF7IVJ0ay15LWUyO1dQ
UTBYZUk0XlM9X0t1b3wqdilBXlEzWUx6OzJpMj1qUlBmbm0+KiUlKgp6fE1xKSowTmUzMlN9TWox
MTwqNG5NX2IzR2VDYyVFPEteQWA/Wl9+PHZwPn15Q2o2QXxJU1JPUSs9NnFXTEUmP0QKemtncjBZ
Kks0YTtlfWRFRVc3clQ1OEo9PFJeVmdBflA2OGg3R0M7UTN7cXxXSFlHeVQ/O3M0NHc+YGJGcnAl
O358Cnp6b3FeSFQhfVV3aExQe0k2SW9oZWl+c3tIaWV1VEljanV6PnAzJFhQdkU5ZkN4ZGpiJFAw
TCFxV08qR1hgYDhDfAp6PVIxIUVuYUY7WlgmYCEmM21udjRYPnkqdVo9dy00Z3hfPmY4eH4pPC1B
OEBmezwxIXdhfmVDPyVWS2FCSDlfQHwKek47cnh0bUdHdlEtOU17JVhuLVA9VzRfP09jWD5oOHBD
NSteYGBrd0c2OVI3aXpPX1VIZV5RWmBATWh2QXw5cF99CnpCQEo4TGJXP1Y7P3BDVDVtRnthRXk9
JW9LYmFmPVh4QTdvMnF7ck0+V0J1b29vWi04e15JVitqPVIzU2RMY0lKKwp6eF5NSG5RK1N1OXBi
V1Q5UiFOI1BAeSR2ZUtoQ310dGJOITB0MiVzMUJNTTFScVpSaCkhJlBwKm1uLV5pQ3srcnMKeiRn
dTZZeGFjO05NRX1lMjVeXjFAdnklRmg2ek1NNVNxc3F1JnYwRjgtOFpNe2gpdyZpV19lJUEpcztl
fWQtRnBZCnpwNmFxT014enpkUytLNkxjUWJCWmklbn1MM3AoWkZyKVJsViM2a2ttWmNQb1hEMGIl
bnlQJjxEVEE5IzNXRk5Xbgp6cDZoelctTlE4YHp7MyFVUG5qZmVJakN7STBzKFBVVndVeGhEeWoo
YnQob3NfZnBsNisoIzclTGllbnxEcFBafmAKejd5VCV6ISY0bjFHUW5HQnopPWkpWSRRWHAtJDs1
XlZgYktkd1JuZ2RVVUhHR3dRYldWal5KOzIoV3tHYj99QnU0CnpPV3NPKmU2dEdOQ1IxNGFJfiNG
TCkzcEJqSyFsLTtfZXptNmZ9aWA1ZXZVZyQmWms/RFVYSWsze30xO3VhK0NYbwp6U0FJQnNFS2VW
WDtKMSl7VkQ0dUQ2KUMxX1chJjxWcElNb3NQRk80LSl3PEZRayhMNE5uKDxgNEJiZmNCSmYxMEkK
ekskdURLdzJ2SkVQSzxYZU5TY0crTEU1d2I4cXh5alZDNUdmejdvdn5wcWs+MTxCaHxFVEVYUFZY
eXVSX0lJamhQCnoxfEM/NVNtPUkjY2NyLWJzKHlubnN2JU9KUXpEfjczbWtNciEhaHAzZHhNYWxZ
fEYyTXU8e3t1Tio+RSE9ZGdMOQp6c25MfVpiK0Z8YHMyWG0keFoxSiErVFV6Tjx9b0twMiFeO3pR
Pm1iQFMlJDdOaElQdXJmUkI9dlVHKlY7RG0tN0wKejRidElefEcqcX49VlJiY1QwMnFubilHR1U1
P0EtTSNHOWhMSE9MYjFEZyRfM1klNzB0V1VPOFo0NXJ9eUpVTzJ6CnpzXzJjSTdHfCM8KHQtVz9B
PGtrbG1lRyk/dn5NO3c3dXUoVS1YaH0zJVhARm5XUVpxbDglJi1MeCVINVBAWXgtcAp6aEFoWGFx
O34kT3FWYistPUEyTE84dDk9VDcqWV9kKUdHNyZZXkgkPj5uNzxRZE9WYVZASklVUXVmZlZUXnBH
Pk4Kej0/NWk3cWBHQSlRckRuc1ZBKFNyOHhkJFNQV1JgaHsjJXFEVC0wUk04Z25KWk8yMT44QFJk
MnBTJCg3MXVfIzx1CnotSkdsWW93MGU1dWI0WmI/b1dYRSt4M2k0QihqemYofkU8biRTQ3RtaERl
T3BxcTdmZkYlWkdKcG1AYzFRdHJDNgp6Qz52KilmSDBJP0tCTn0rdip1KURVe188Y2YxMzYjaWJy
aUJQdGh0RW1aU05XMWFhVGl3eHtMPCN+azl3cW9tMSUKejwqPE1tQU16ZDJiKitScXlgMjheRGRj
cTxPJTcjITZwMVJyMXRGMXs0JTEtNlFHNj8xOWB3VT4/QTxJN19IJjZ6Cnpxe3BaYkMyNzhnUFlZ
UTI+VilHJFk5bno+LWRnXkI/OXd+LTV9PDNod3hzOGJoeDgrWHRaZTxgQFYlXzNUSGdPbAp6UzRk
PW1hVWRxcytiQShmekBmd0FPSVJnJHc4TzlSPmElO0ArM0FSPXFJVnpDSTt8RyZ1PmRoTyppTTho
U0lGMFYKek9SR2JoPVRUcUdfPGlzTj81P3d1TTVeS05KQ0VGPENpQyNTP0ZAazMpSX19Nm1eO3Jz
JERXQ01QLWpocUs+ZWVUCnoyWDQqfWZscDIkcUJ+ISRlKnItR3t1fl8ze0RMK24mLXJvLU5gQXtG
OHdaS0ZUOzleXkQ4OV5NKFo3cFlSdmh2bwp6QlM7bS0hLSg3LUdSYnpeQUFeMGAqakNFR3p1P0h6
MV93ZSNHWHJwdmBON2wwI01uM1V1RG44KXBiS2lBKGt2bU4Kek5+UVp+QXc9PGczQGolV0x8clFm
MGl5Jk9JITFPY3BiQDhARUhJPUFQPWUqX2tNY0pGKz9KUFFiM3Ykbz53MCpZCnpxeip7dWomOzRn
bigwZ0h7Vl58ZGxeaHtIRilDZloxenlhcmxzIyQ0NyV4WmlaYiY1S3txM3c5MEwyRF56cDdLZgp6
Y3dTYU1qdykpZnRzXyZTQVRxaDVkYXFFWnUhKHwjT0hyMzt5Q31UUlQre1NGYmdGfXtPd2pWN2pf
QkB1aCs8ZEAKejJxPDJSJGdSKGxuWDwyKj8mRCtuaklyNX40e3xvO2p2X1ZTel9AUldtdyN4MGA8
VjtvSCNOQlBNQmFOSyU8biNmCnpra2sqMFd2fSM5UzdLcXFvcEB5KjBYcjU1Y142M1pPZTV0c2tP
K0Y1NHtWeDsoXlVtJlB5P2c2R1c4V3pqfl5QcAp6UjAxME84eSlXUGZSOGVUanxAdVkxLWNWey0m
P2grajBheyhUUmRnTSE5K2dEK21RQSglSn5LMjV3QkNtS0ZMTXwKeiExVndWcDtmYVlmPEl1SUlf
RHA3JlJ8YEcwRTA5SSZtNjkre2lxTFQ8OCMjZnsodUFYPFNQNGxWezQkKkxGUjx6CnpKUVJaOGc5
TGdYMG1+cn5lWnR5KFhDRUpHeyY2KjdpM1JpRDN6QV5hbTFXam1FbG1nfE0pdENlIUk1JCM1S3E0
Vgp6KTRjZVRpZUtrbW1+Oz9pVEFJLU5hOUdaX3NffGtEJU1Tb1EmazVycDNmKGBGKlp5T3M9MXo+
RDB9I05VYGJ6OSEKekghQWI+cng0UVo8fTBpNV9kbjdVYT03dyVEQCtpU2BmdzAhISs/M28pSW5M
LW9CSlJpNWNkRCglb0JCbXt6cng+Cnp8SnNFODxwQXVfTGwwZUUkYHErWD49bG9UIz1IK2woLWZk
QFNLLWQ4M0d0fEQ5NTgkQzFtNUptblEhJU5TcmFAJAp6TmB2PDhgfWhiUHshZ0Jsbl5KSXtNZj0h
LS0ySiFXWGpiVn0hMDJPS0M4UUB8RzZEfW5XcTRiZFA/KShkK1hFMFkKem5JPGl9UWw/fiNaVEk3
PTZDSiVFJWBMXypuen1wJUByUHVwRnkqMzVRRT5qQk59TiRwY04tdTJSa3p0UWdhKWV3CnpFU1V7
WnYhVE05WjQpM3B5OVdteU01R3R8Y3A+KmMwclFkOEY2cXJCP0xWfDJSNUlCaUh0OStaJUA3ejY1
NHZLPQp6ZTtqKns5N2kkZ1JrJjZ8JnpGO3BjQF93dkw1PWxIJlBYPGRZdT4hcC1OVitnZj1SPjVI
fHcmeThBaH56Kio+R0IKejQ1VHRLY1J7YHJ5PEVTTmtWWj5wWFFsYXd5eFNEdSVlPV4yQzIrM3pX
aipYUTN0KT9XWX4rJnxTfjIzYCkjPllFCnpUd3VgcTIzNWZ4Wi1KIzxKI2FDUnpnbExYfEs1TFpq
ajNZZjlPZXc/JG91RGQ+SDQ0OWRnb2dNRG5LQiZASTB6Qwp6PF4pQGhUPm51VjF7Q2taeCRgXjs7
WnRgJUVYV3V2Rjg7fUNLZUM9WV9rcz9yfDhze0whdkV8aiswMjVVbTxkNDIKendwYGwlS1NRJHB6
bitefWVtKHtmQ0gqUnszeF57d25FKGZ5fDEwVEsxRWNRSCVHcGFmKkZ2QnVvfkgyY3d8IVE9Cnpm
VlgyRFppU2Z1V2VTZ3l4ZnhPd0shKTJUTzRnd2R0ckp0bHw2UUwtU0JoRStSPnIrK2E+Rmd1MH04
aHNLWm1qUQp6VyNCOEt1RnRQdmV8LWIkSmBLbW0yI0JKZzM8N28zXiMkQ1B8OEFafndNc3p+Y0Eo
ZCRTdXlmRT1LK0c+NWJAO2gKei1Oa3g/TWRgKHRwVHlEN281I3omTzdCczZDOChRbG9nQFpHIWBN
THBtdnpEYyNHcXcpeyRtbFZNZ3MpRF9WbCRmCnpRR2w1PkhOfC1ubD1uPSNtR3wqSTM4YU5QN0pt
NERNKEc4U0FnMHRtRVhvKy1kM1B2M2E8fmpWZGI9YGo0RlR2dwp6QElrS3lLLTNTPWsjZVBqa1NQ
I2BDPGJCa093anc3WkRZbzlUSD8ze01FZ285JllPTV5yVDc+d2EzOTMoN3VBU3MKelNGKV9ORENz
KkprPWxLeChMJktHUXtjdSEkLSskQFJfMy1kbWpZTXopfT9UQk9fOEJycnFYPm9VeEB3SDJAcGcp
Cnp7NTAzNXtEZUkxO2x0RGUwRiUjbWhSfTlQXkBlekc0TVopNjRxZHRlXnJOSnQmbUJtN3A5REJj
K192ZjRhZiZeQAp6cFp+QEFpbk4yJkgjTzgqMlBOaUxyJSRQLUJmKmhYNjxDS0FiNW5PdDY8MzBs
TlElNUpqVzEwTDYtWnNZOyQtbTwKejFWRHpwO2dHOzRRMmFYcCV+c0dnbTJWMlFkaUptZUojVHlu
NU5xRHtzS194QDE3KVIxTUgrVDlTUn1iS2V3Sz8mCnpQRFM7WiEjbm47YHIkSmlSLWFGQmRNS2U3
QzFwKjBjVV5KSDZiPXxYREZRTVZMYjgybXJVI3h0VTBoPH1SVk1LZgp6PXVaRi1YVHt3R0xOSWw1
NVhyKkw4UCl4OEcxPUlkRihOZWkkezJ9cjw8RXVfYXsxMCVTLWNHc1ZfQmltUUFJUl8KekE+SHlp
bWNSVElCO2gpRFgzMEl0R3JwU3dwVWdNV2RRXzRlc2xpQU5HaUUhIWBUOFh9UE5SO087S3gyUWVC
b0F1Cnp4SXFJb0dKZjg/MlY2dyhHNXFWKTBCTzEzXl5WSmFreD13YiFfTDxaSENqfFcwblc7ZVZ9
bmc0MUBeNUo4TmxKRgp6MmEpTXxYSitqJHtYRzs8TF8ybWxibGRYbnFkKGlke0B7aHstdEBlI2Bp
Z25jb2VTN0tQfV45fnU1VnlJKj56aioKenZ3S0R0QH0kM34odjRhdSNPQGBYKV8+VTdgJSMjUHVv
ITh2IyF6bFEzaCFnRGl5dnxUbH19TDtCZCRzLXdzWkYlCnpWSWo/fXsqPko2UXxVd0Y/Z3Q+dlhq
YU1HZFlLTjM8Zm4/amVne3kpPTxndjZTcHI5UnRmd0YhMTR7YzNeT00tKwp6dEhjbVVeR0Mle0hy
ZiRAZ09RI0Q4QzMlOHpNZE5jKUp1KntPNjZwMm5GP2ZtPE5gcHNiVEYyQitMJHIxRDJhakwKel5n
R3F1aHsoWiU/VUxWYjE7bndmR0M/SXpsfUc8QD1QbUx2OTxNakVmWE1oemVJYDkxIzBTPjYwMHwo
cVZOdnRzCnppTEF6RlFBTV48QXVYVD0/Q2AxNT81UFZrMzxTJG50SjBHVnwyXmB5WVg/Z2VQbFBG
SGRBODJYbnZWTmxtIytwcQp6ZSEwMSM7TSpRWE84cz1AOVk8YVRGQTx5JTN3bXhDazs5VF47dmd4
cUQ8d20rTnNPeipAamNJflA8b0NlY2AkZyoKekhvNnZNWUt3fUpoMl9+OXo8I0xOT14zQUpGcn47
fGhVJHd7aUtjcTF0JT0jdVYyPXI+T0d0UzNhYWV3NCtAb1NwCnp2UFpSPktXaDtKRGJ2ZE5aOFAh
YmFgVngyXmo9PGtzcCRRRmdBWFZAbC19V0dNWEVkMGVOYXh+K3Etb2FYVUJJZQp6ekgjPjMtPmNB
RTVjODdrLWtMbGNqNFhQZyYjWn56cGdHXkIqWno/QzAwYS13aj90Sm12aEg8NVYja1dZOGd0KUoK
emd+MUk8VEctYTlBPzVLK0xyZk5tI058fVI8RXJwU2pVailPKW1JdF9RUFJkd25US2JMdUhOTXJ5
UTxwRkdOO0BACnooWThTVzhJUT15LTIpY24pVzVmKW9UfSh8UnJiJkJgUSpxXlBJIyFrUFEmSXs3
e15LZVNtPTJHKUlwRlJZdkFiKwp6MT0/WEwqVDcwN19tQX1ETlVma0I9bDRHSiZPKFd1SmtzSFNP
ODBWdmQyPk1XLTBhcGIwd15xTndma1hSQT09WWYKejZ7VmpUMTVqS3R1WWhkN3hSRTM4KlhANEdF
Xm5TI1dvK2krXjtadz1LPiNWOHJyPjclb3N7PktPN0JBdDlDZmt+Cnp5fVREZWx8bG5rdGVnbGcw
dDtFMVVYVlNBX0UrUWtiaUN5RnRebl9lJCNKWlk9STlAdXl5PGoxNCt7P2o9cnx5TQp6R0M9JkFQ
aD97YXBLcyElUiFwN2Eza0I2TG5AZl5CRnR7Mmc1YCh5dCZhJmdOWFYmbyl0a3V4QWF+TllXa2xK
UE0KeislOXA8TlVITFdMaSlzNGphaGgybn1PfkgxWldMUnkwWHViQUZqTVJBdmJPTUA+SGJMPTxt
ZGh3OClCbkMqajtkCnorWVY8UTFKSFRCOGFOelVLYmxhSihGYzY9aj8lWFNMNDJESmtISU9kaGFj
MCp4TDBtP0dVezt2LVBfeWNGbkA+Nwp6S3hBYm4rdXdzZ3lvWFV8PURYJjM9K1BEUDxUPVc4S2Zy
bHErajN1T1p7NFMkMCVWQG5waGt6OFU8cXVhIVViQW0KenBaKGxAPEJiWWZOTFlXZ01EKVVBa2Mt
MmB5YlgrLUgkQVdHZnpQNjd8QXI9I1p+eWEmWVk+UzZTZmtfY1duUXwzCnpMUzBZcXpNRSs3eSpR
NjRiUW9CbHgqaz0zVyolTHUxZSE1ZlZ+dUc0WGtZbkluOXxEZlElYCpSQ3VjeklJLXE2Xwp6czV6
VF9PQmclZmxtYTxOanJoRUV0PSppQ2JtQiV2PE81enBNMVFlO1hENW14XlpjSX49JEheUituUipG
Y3g/PDkKem9kVHZhaW91eilVKnJzcEIzZWhPO2JoPVomcWxnVkRTKXJMRnImVDwqdE9aTE4pVSMt
TnAqeWhicGBWR15yPzBFCnpkREFgJCYjaU8+Kyt1JWplMnxjTTJPOTk+fDJgREQkKTBOJXpZNWw4
Sno2allIYVk3MUotQ1FvX0heWEo/VUJBbgp6VG1JUm8xR0A4VlF0ZXUpX3Q5SnNFPTJIPWg7NiEm
dD05ZkJeaU0zXngjaHA3NlVldWJXRWcxdj87bVNQNnFqaj8KekgpcE5gKmNGWSYjZXFvdUtIMmIl
cy1FYHtPVzl0QSZVcStuUVRIRmtfYkdSdntASlplJUQlQkx4bD41aHA1fWBOCnpgdzU2UCZ9OSlf
Sk1KaXtRVkVvJDJrIW9aR0BxO3VieCl0Sm1eYmdqUFdaOEZRYStfTGg4fmU9TUBzJGhMXy1kdQp6
QCNuKFZtWFpAQnxGX3NQbzdyc3pQOz94WnUkZjdNVTA+RXdTb2dqV0YzIXkmTSZmKnEjUzBeTEAx
RFVCWX5hSDYKenUwazMmVCNXcTZzKn1UQFZBdFcrb3tISFdRQE9wdUVrKW9iJWVTbSR3aXg3eWw/
fWk8bUVmNDQhPW1qQCFrcTd9CnpgKk85WnFTdXhmcGZ3QlM7QEpBQlFMPWo4R3IoaXJrXl9eZz5k
Ykc9ZCVTczE8RytxczZ4WlRPZHAxeVBwKT9KTgp6T3tpISZAdTExVilpZHY8a3hSMVE2KHs2RHda
KDJrQHg+K0k/QFhYKlR8IzwtRW0qdDtheEckNStCIzhYMTNiRGYKekwzOGIqRjVpbmJxJlE7O18m
Nk1RVEZSZHtQMyFRfXUkSkQzWCpfRUE0SGdganFWbXt8YVp4MjBQaVg8aHw5UVExCnp5aitzdEs2
IW8rajIoXlNsQCt+b2xfV0xoMkd6R2dEPCZwbSQoJTk/SiEoZWkwfGRFTjUqLWNwOXxINXgyVXsp
Nwp6IU5KOztRb3hqe1BjKzVQLVR4WkQhTSF4MWRmJiFEUH0zclhtbGRvcEYyU3BPb09wSVZSNSkr
O18qNzN9eHxYT2gKej5aS2FsY1crUUxJS1E1V25eT0R2SX0zKXdTQkc1aGQpQDlOYjV0Z188Mk5Q
bnE0fHBCQ25TT1hlSzx7KWJhdUxNCnpFaXptIUp8VU5XVXFDcm13MGJwUihOXyh9KzkoNWpDRH5I
QjtRZDBafEZscFd2PD5scFhQUWV+NHB6I29fTDtIUQp6WjEmZG04Mng2OyV2X0E+OWNEPyNTRFNR
emFpYkdudERUaHpRcj5qYillYHsqIU9Ub3VRaV54THhrYFUxMGp7PVEKej4pdil2MUVKMigkRkM0
IVdHdlpPT3NLZiRRPWteTjZsZCU2RyR0PThzWjt1c1U1UylCazVLT1E8SnRaY1UoM2FwCnpXenBk
bzslSldBZk8pNkIyPDFWc2hWaStxNG50K1YkJH5UbypaWH0pMGA8IyZaY2tFZVRweSs3bXpWclR8
MjEldgp6bFJsU0lJOFU2a21hKVIhaHRCYnYpbzVfMVhXYmQlS1BAVU5wK0tKYy1RcCtLTjVNJUYk
YTNhViM0MGJReVl7US0KejgpKGU7bmk2YD40YHpNdF81dXZ8Qk9ffSpURzNmZyV9bj9jcUlmPVoq
dFVvRC0lNy1GVFJYQ05HI28pe3lxUiNkCnplUERORCl1bT57dyQ8bWlrRG5DNFlKfGVzVnc5dTU/
TmxQcjIrI1deKHJNWSUoZUVZPEh0MSFqQz50MFR5d011dQp6SU05MzU1d0djKmVIX284JjwmajVC
YDQmd0U1WnlyOHxDfERFeFBJTjRWQ25tSV5WTD9iVzcxJHlKXyF9N1pZV1gKelpIOU1CSnhWU30j
PS1QY1l2VUF9XjI5VEhtIU9gelc/S1h2KCs5NVltOElrTFp2QFFBeyomVj5uTDY4cnoqKUwyCnoj
QG96WWBlVUkqUkdQTzhta19JT0Q2YExMd1lydmFPJGF0TFRDcnExZGF7TGpBbSY2V2AyVGMkdH5Y
RihVSz5AeAp6dkt8Z2VwNXh6czF6QFY0SkY9JElpbXcwbiVARG02dmFnYkVMNDlrS1F8RGYrJDFk
KyFII05UR1JPemsqS2FYdTMKenBOcSRya3l2PlQ7KW9WREVvK2IwQDh3cGAhTFJNJSRSPCMxN3B6
MmFjcGtMWTt4S3NnUXcrWlJgamFSIShEU3pICnpVPVI0Wm5CQnpjWExtWDlZS317fUJ+QS19VktV
cn4hdFdvJVBZdVVkWSN2REY3dShxP3BnSF9qTFRsSys9UVh2Xwp6cyMkPiFZc0piYz4mRVVLcSFn
RmJTUmVZPkR8PGgtISR+bHJSZSh0Wk9eTGUzT15CY3lpUzRgPHxHU1I5SnN0WlIKeiNVSzxlTHV8
bUQhVmIxPG5Eb2NvSmY8U1g4S3g/PS1BbUgzXkN3Rm1IK0RENUo/Mkg8aEBkJTkqVVZ7MmpgS1dO
CnokaTVDazM9YCl2JHFaUX1uflNtTlVWYnBTeFU5ZkB3fHt3QGoocWhxRDJIY1Q+RjklUWQme1Mz
ZSpOM1BrU0ZXTAp6dFhWVEhOMF5UdjxRKllfJlZKcH10bnhYciloZyhFSnArVz9jJkA8YDxJQHh8
Nko8TEs1UkVqeSYtPmhNOHZldF8Kel9qVjh+Pk97RTVJUDhZKHROR1dsJj5lQVhrYmI4XiRZK0F4
b3UqX1F1cDJeYzshWUNkQmNQVCpnYGIhVzM9QCNqCno4Zmd9cjY8MGNANGZidk1BSHkrV1UheyRJ
dio1PWhvPEVkcklLZGFZaDk9KWFEVyh3WEJUfVJRPDhRXktMUHxHJQp6JHMwOVRQVjZ0KysxSD1f
bCRAUnJwKGVXKDdpdm5pb2NNXndFIVR0T2V6QVNhdE85bCp4VTZJejh6UXFYSGh6QkgKejJlNGt+
JkQoWnR1JVVxflgwPXZsRVAtNyhHTWd7elArNmlnNTl4UzBMQ28xcFJjaEh1VFhHbFY0YVFTRCo0
Z3Y/Cnp4QGF1JSpXM3VUcWtJPE5BUUA4PiNQaUhEdWsqRkZlcGRtI2pVaXZySFokSTQmLU99SyFH
ck1ec1ItVVFVZUNmVQp6d1ZidXRDd0N5YVdPR3phckpDQmRwcypxYXlRJj9YTXYmUUQ2VW1JYlkk
LXRZJENiNyVgVWVsKTQ4SUgxQE9aMlUKek1JeF8+PiRhX0NTaHpXQmVRIXktV091biMoejRud1l5
Z1BlRnAoOEd8NH1DT1gofGd8VilLZl5gSzFTfD5BQmxFCnpvSn1geiZsO2U3WCNucmo7I3d4P2FO
XygtcEFrKmBTMjJNfU5ie3hNT0NXWFc8VEEzVVgtVXA4RWBiRGcwYGpDOwp6Vyolaj0xYmNZTCE5
KC1LS2YlZGRwd1JpQ3VYUDthQVkxJmMpI014O2Q8aHRsV0Z5XkQlPGdtb3BPXnJ7YE4oTyYKeiRH
K1VgRHJsdn0qJmpkMCYlT3RfVzt1dm5OX3hZckN1WkopVENnJHAqNXQwKDVqVHRUSzNTajRneUhf
UyZhLTJPCnpHT3Vza2tNZj5CZz5wakhecj88ZDxCeFhrN3MrZzJJbEM2YGpWPTRQYW9nZi1GWUg1
YVVDXlUmVE0hSmNfV0lOfQp6eXxnaGw8SG9ONyNqdX48OFBMUkFzMjY/TkxAIV8lQkhyU1VIRXZA
T3pTRENDaU5KZUlHNFplTG5SWC1HaCtSR1AKek8tX1goYDZwQGFpT35oe1NwKy0lPTEpR2V6aHYq
Y0lRQShjQ0N2UE9fRiV5XmpEe2JuSFJoKGhzeTY7TWF6NVNiCno2JGMzbUJ4Vk1mQHUoJT9vJk0h
WEZpWXNZQnIoSDBjdkowbVBAdnhCYlB7MnFiZWdjMFpQRlpEZkNTbkVlPlZQYgp6ZSQhU3ZEMjk2
eUFNRWxJVmdGMTtJckRfNEduMGtyKChLUWtONmE8bF52MllaTm57O3Z3YEIpWmI5ezFWXiopdCsK
eiNxbGgra3hYcihRUHtsbntxeD0zbH5QLSNFWWZPPUttPFlGZStOJk40JFNINm1MLUZSTVJCVDxZ
Ql8qKyRaI3V0Cnp2b1JLd1lec0FMOTZHbEB5Y0QtUi1CSFdjO0RJRUV8RnJlIVlxPl4tSF99eHok
dHFOdztMfFdfendwVTdTdHoyUwp6TyNyfGV8NTlOTUhTdEEhR352NnFLPk8hN3tISV8wT259MTk+
LVl5Rk9Hb1peNXs/fUI3NnNma1AoOFA2NjUrPlIKeihqdj12Sm81c3RoZSVOJlhRbGFKe0N2LVZe
OSFrbzFiMVgrUV5xVS1MPTckTEckKndqSUkrKldafkgjKW0kVXhuCnpibURqIUFpdU5tIzxyeU1Y
UFY3WnR1TzJlfEQyeXY2YlRGN2stMS1GLS03JGY7Xil1N0xReW5wT1NDUCFEV1Eragp6NjF4X15A
LShpWj5mSXIpXk82QUsoS31+dTdFN012c3ZwZE8zNkB3YktldU1+UnFoMFJpQDxLcU1yLVhWKShP
NFQKelBePXRgeEE8SDIje0w1Z2dYNFRqWHdyQGoqJkpgI3l3TGp3KStXO2dpWU5RdE1hK2hxTSMx
UyE8ZWsyaWpYOGtVCnoxekJhQz4oOHxiQmM/eUMzZVJPMmFDPGVjJFpVR09kRz4qPVpjOHk4b2w0
ZDlzP31zfHh1UGxBQFdUPDxwd2soZwp6JHw4OFcraSFLOFdXJjwkbE1xZ2pkcXY0VVdTYFgoS3dK
NkUkJU1sNSZxaD5SM3puQF5KUkckYFNoI35BPztGOyQKek9SM1dyRTJTX2ElS2UyWlJ8JVN9SXFq
P2NZN0ojakxGeFJZYHhOPGFBdn1EMk40KzNLOU5YeFVadkRBYWJWSkVECnopeHgpUEV9OTxCOHRF
X3tTVnA1QjUqYUZacFQoazdefEt8Y0VJVGAyK3hDKUV0RjwhTSt3dHk7SilLKistZENyaQp6OXg/
N05lM1deO0lDKkwoKnxzMVV5YHUyXnhMVDxLbjF1V0pzMkg2UHVKX1Y9TVNTVm45MzVTRTx7eGg/
SlNeZnoKemFPIVEzZkIjMzFjfk1FMC1kK3U1R29Td3BSS2gla1crfVZ2R2FwXzN3V3gwJS1CLVUp
IVF2ZnxufSokNEV4eUlECnpgKUpISVc3V1BAdCg/UEAqbjY/Y29SNWx5N0tzZXlGaSkkK3laIW01
PTJ0ekg7ZlQrJlFERSFhY3gqP2JoTU43YAp6ZDk2P2U1KzU4P3czTTRfWDE+P25jemtEKlRmbFB8
aipKSk1Da30lYkpUQVU5QCp3VktlZGw3ODR4Y0hockAwTHgKejxJbmZeQiUlejBaIThZeGcrQ0kx
WkVjYTwkQFQ7cj9rSXwlVktOa1l3SnIrKDlydj5YYyZ9aCo3VFVoYUNReT0yCnpSQjk9WjIwRVB7
YHBtSkNfMH19fiNmKUwyREJTSEFiPi1hQ2FiSG9+QDVlT3BKRHIzciFhSmhnaXFycSRgUUNrVwp6
dDhheVUqc182Y3RMPXwzbihQSyZGRkEtYDtfZEsmYXtzT2UjdylBfDR+eF9CJGdVXnJrQFRVcnBR
TE12OF8lPGEKejU+SCF7MzlfeyUxcSU7d2M5SEdTNG1BeUhTaEZ+fkUkR0JoQTlWaDw0fT9VViFR
bEB2SHc5QjdGR1IxP2cmcj9aCnpmYTQzWFl0NFRxQk1vc2ZZYnZ+e0lANEtJQyhlKDg4cD9UUEkl
X3RNR1hleXBteXJmKTdlPWZIT1lPR29jXlM4Tgp6cUdDZkwhUS1uSFJGN1U1WiQ0PkRfdCRLQEQr
dS1GOTFhIV87fVgqfDEoZzRPaWElSU44Pk4qakRKQztKakYwJGsKeiZPZj1MdSFINkZ4XnZeY0BN
RXs8VU59XkIoRmNRJmVCfEwlcntSUkpEOT47RWRJKj9lPXdMS3EwbCNMcy1xVmE4Cno3JnpyfD9E
TkI1S1ZnbDNtZHdYT147NSNWbEx3RmZ1YW9vZXJ1elJNYDF7KDVZbWJiMyVfMUBpKiZgeV5wWHxz
ZQp6QlY9U31UX1p3OUJyLSFxWDJfMDlIclp0Rjg3PzFXVSsoWDlgK1dhYC0jUGMoYkktWjJ7ZH5U
anVqZ3cjQTdHVSEKenxFU2NfKTIjaVNWWX1WOGsxPjZYZz50RWheST4lNSQ8RGRZKW49NChrcjEx
O3J4R2RrRDd7bDhYJkVQRFlyN0FXCnp3JUE7NTtuPjlVJUtvUDVwaXtZM2BqPDt8VDUjakw8bEdt
ZDcxTE0tXk4jS3NzP3YhMUh9ZkkjYHQ2XyhNUSE0Zwp6Sz9qKG8hZUFsKTJebURobCQ+JWtnWm49
NkxOY2A5blNvTldiRTgkc0BSfG4lUFcxZV4hcXw3SUN6cmBnPjFlaHoKelJqQnl+Yk5lUVUyd0Fp
d0ttZm59K2FpM0dKUUV6M2VoZFZKcnloSjIwMC1CZTVSI1hgTXx8WF57RWF1ZyQqVEhxCnpMNSpE
QjFvV2BxOV5ZdEItS3VHbFc0WExsJD9QUVhYI2xHPkUzNilkK1B6QkpwMm8pUXl3QzZVP0pDIyFD
elhOUgp6KSZjSG9gMHdJWVBOcmtKVm08MUdIPTNAaktWN04oaTwxUkdyRnpkcUQ1bzhSPmdPbkBD
QU9sUiNCdEFfR25hPFIKejN9KEMxVU53TXxLbX5rTGJYTD0mV3IpTlpeeyROLSNPXzt9R2AmR0pp
fW58T2I1ektCdWJydnNnZXlXX1Zhb0d0CnpoN2F9KjFJMl5FOFdMIXJzK2RHR0w/NVA0WV45fVNv
SmpLekwjcWN2V1UkTD9oZjV5b3k0bDwleWUqKzdeaX43Sgp6V0ZhQ1ZZKmZzfEZ4ekcqTE1jUW0t
alhoSDRISDZDdVhIRC1uWExNV1lMWD9rUlgxX3h1TytXXlclQkF5cEkxd1kKemZUNkFyMFN+MHd5
UW9kK29kWW85akhFRz0ofmhGenhPM1VlTWxefFooUDBDKW4jckJDUkg8eTFUJnhVdXU2JUxxCnpQ
S292fHBzWTFjI2xmWSojX3BLZzhgTm10RzV7fWQzK3g+cSE9fXNxNz1VXzlSKHZLYG84MDdwSkYp
VXJ1ajB6cQp6TzIye3c+djRMak1UfFl3PFopeWNwdUNWbFJxZXtoQWVhVClUU0oocUZUVkozTHY8
WU47M2FWMilke2Zic20yUGsKekZeNCV1RmA9JiN7KChjJXN1dX5nTnJeJkl2MTxOUHlFU09hSnBK
Mj90cHl9THl0bVNEamZtM0RHXyp4aDhQfjZmCno2K05XMlN3bWQ2OEY7d14/aE1iVWh2PjBXYjVS
fUdYREw/MiZFeTZMRFVTUDFCNDBJRih0X00xZio3USR1NXNaXwp6Yio+OGE8aUExbVRyOFhgNUM+
VnZyS2IyJChecFprYVE0RVN6QG4ocjErZiVZTyN9OD1fbU56c2EjU3pjQ2wjI3wKenYoJUQ7TTdF
eDw4YCk0QnF6MkVYQytIS1I7T3BmYVdGIzN+c249Z3lYdzluIXYxYWE3VGN2KHRRNSR5QD9jV1lw
Cno3SzZgM154X21WMSFRXl5LSnB0Z1VBQkJTOW1vRnNOJFg9ODE2bjAmMnU5OVBYJVErJGZhMTZ1
VmhPeVlgPTFFJAp6aU9kQzIzYTNAcDMwPVcwbWA3flJNO31iWndzWElmbyFBd2dzQ2hFNUYyYWdw
TldWKGFnbWp+b1JqNyR6MVl5JnAKemtQPGNCa0ZUR2tCQ28meXlnNSF5V3Z3anhPNnw7Ui1jb35k
YiRuV35idEJCdChuZHhDWE8peVVpMSFpRz0jOz1GCno9QnQ3MkBVX1ZfNGw/U24/P2d+MXhjeD11
dCtOMzB1QEd2SGdnKlNUWmBPPmFpPG1HPXVgVVNfYX4wdXwhMDd9RQp6Ri1TYDxHdDF2NmBwUVk4
UXFRSl5EUF9AbnNaSWlRYzZ2aDhvVVROdWI7elNmXmdEPDV7N1h3eCE0TWQhTnVnLTMKelMqWkh6
YnVyZHJXenlPJmVeeUkzcUB+fDdkdiNobFhAITtYKGskdjd6eHBTPlIwflN3aSMqVGEzcHx5Snc3
O2ltCnpSS18oRiFTSDV6OWk+aCQrSFQqJTwxVCpuSiR1VE5sOH1TUG0jSHYlK1B3PGRqXm84RFch
eUNGYUgtZHJOVjIyaAp6WXV6Wm9ZYEk2R2ZPP3pZLVZKTkE2Z2lDSzB5bDl0LXdjUjNNTVpxJk0t
YXJ6bVJwMWxoUz1zKGZ8Sm5LSHp4PDIKenpXdW82TTNlSzYofWdeNUZxfTZRJkttYG4zV3hLQ0Jn
RWtgcHtGVikrJDx7MERxVjRHcT4jYlFkeDNoKEh6QWI/CnpVQEQhWnFHdDl3THgrdXQzMDFFWSts
IWJraF5FWFp7ZENvXl5gVUlIaXMtLUx2YD58UCQ9e1NzVUwyTntwcVRZZQp6Rl99IyprOU8mclV5
ZHZfRi1eamdFeURPQVZZNjstQ31CYFVnckpFPz1kR2lqY3s1bzEoJihEd1deQ3pJZD87KXMKekRP
RHZeJGk0TExCU01WY2Z7N2xuU1EkekNJdFFYdDBxO2VsP0k5dTxFbH47KUlKT0VheGYyWjY4bCFu
JjAzTFNPCnokOXU5e1h7bzlfcCF0OztLPmAxQW95JkMzQUFMUG5NPy1QLUBJXzlATz1ndlFzPjth
YzRkaE1zVnlCY087SWZWKAp6d2FCcTYrWT5TTEU8WXpTaGIoYiRTcStAV2VkJHwkUHxXQkVjS1JU
eSZgcEd5MD5FX3xJXjdeJCp+JHwwZ3gxR28KekFvYERpUCg0OStaMmxTWGhtVSYhe0dfUGVySCpR
S1N9XkRVNzdAJklNRmUxekJ0VUZocihMRzZaSkpWb0J3OylWCnpiMCVadlFJfWF1Y2xZQSVmR0s4
KUl+cDElQGJuUF5HU3FidV4jbCZ9XzdlVUZwSDwjMEJ8JEpuKGZqUiZ4bGY3PQp6N2BCKTIoY1hM
c04rSWV1dDY9ZEQmU3lQLXtZa29FeVVEMGMhfj0yKTxfP2xZd3x5ckVGUj94OWUxN1B5ajlaR20K
enVifkhsdTZuUjVUMzdXQSMrO3p8ZGsyMlEwMiVjZkc0Kn0rJDt8K3VZOVFqKD96SmtuWVBGYilW
eHxPKU1fWCM7CnpaSmclUyQxSFByWHUqV18lYDB3MFUjPms8JHk5fCM/bld+bkZ2cWt6fEpQSXNe
I25fP1JCNlQ9clghKkJNbGhuRwp6JU1jWCpIUlhuKilGbHZhc24yfTFnNHtPUmhKRVB4NTdrRWB2
XlhqKkYzQFlNa3ZnWGglNiVgQV9TMDE9cVgqVkgKemJhTFRBc09VNXVDTXhqTCo4UDl+Zl5rbGZ3
OENEM2MwQyN1RmZeemg7YWFTNiNZRUFpa29aKyllMj02LVdNaHw4Cnowe1ZFUj1OQ3NtT2Zqd0F3
UGVtKHFJOFc5RlJILXpBZUtfXy1SUztXe30kPG9QeTVXajBVcXA/T2hMaXlWPzJKVgp6VGV4RTR3
UyhYMnJIezRlJFdCMj5yNlUlM3soMDEpY2IqZVNqbkJaYWtiJjs9Pm1XaSF2NityZUtGR3stKUlq
NFcKenFxYD5rRSNKUVp6YDd2YiheXzF1QGZfbkt0UUBRZ2VWZUdUSkRNdTRJdWN9YkNjJjNhOGEr
eW8qMU5rc141cF5ICnpKQCskKGNvUFVoPHhlZzcmTngpczlFKlZkZHZGdm4zVmNXQ3NKN3F+Uzc5
OUd8Szx+eUp9ZnEpI0BDTkBrYFJjTQp6U3hwJnhWK0IhciRTc0FRUntmTkFJXyMxMHVGe1VgN0Bs
TiExNSZ8SlpQdn19Z0V1eWZ6TjR9OVExTj9OTGtaaVIKem1vdGR8M0pLUVJna1gkVDUmJj4lP0JO
Kl8lR057KjIqQm8jPjAkI1dvJGRhUDBCYCtGSTk7c0Z3aDZRVnskeCNxCnpwYnN7T1JfPjNjQ25s
d044OCFVa2goTShDQnZvYDxoLWpgX3NtYUJLVW1uYzk9ZykzPUMxS0ZgKCFvVXB4SnJCVgp6PlVv
UUViPDR3dFgtUFViaHtJK3syP34/MVNsPGQjQFdGK1N7VyY8SEZrdndPIUA8UXZiK1BueVlVRWJH
ezJCaWYKemUmfnJLOVIhSz5ycnBCciRlNE5+N35uUmFCdFIreE9ZZDx9dWIoTUs/fVlyMHE5SEg0
Q0REcjdhMkhvPnQ2TmElCnpiQTZqI1BOMXYjLUZoI3s9e2omb2x3fXAtUnZMYE17fHItJnd5Wkdt
aSYxXmRoPHBjOUppaWo3SXt2SUdHd1hjSQp6UE1Be3o0NnFqPU8yWDt+NXFiKTlRcil1OXghM31O
an0zJChUNDI+dmA9IyZSeSRnS3VeJDw1KDk+OSNBbSYlZWwKejUqezVqeEQtYz9rRWd6KE4zVW1Z
e3dkdlcpO0VxVDhlaH5rN35EWT9gfG5GQyV5e0daWWZGKkJOXz01JkgjUXR6CnpVJTlwVmc/RmQl
VHBZcW9fLX5ve1l3bFJve00kSjxJeD9iMjltWGFyM2wjSCZqdERrN0l4NllrOUhJYlE/Pn04eQp6
dihHd1RvdjJ1b29CZFZpdH1WJmQpd1RxcG8wRylyVFZlLSRiQ2JWVVRtTDVSe0x2bGMqRTFTXitC
RVZkNW04VzUKeihseXdFUGdJP3shSj9fKXYkNjlnUjBwVEh0cU8lMTNyZHs2QjM2XjFgdD9nJWo8
I3ooejc0MXZMentEVHd5Knd2CnpZSVg4PSYrczx1cl5OOUd3aSQmcSgyUkIyQUZWWGBtMU9OYTBX
fT5aRmw5M3g5TVYoVil8LSF2MXNONWRnVTl5TQp6RitnI2w1NTkqKlFhYVVAbUYoVE1fPXhETksy
WU1QUGN8IWkzX0FmTlVDKGUqUGUqRX1PKU47fnYpbnFIKE00YX0KelJ7d25wKVQyOU1gMWc7V0NK
ezUybzhzOFNnRSo/V3B7OUFoclkreU4lRjQ+VjEqSCY+PUNGVWteK1JwIyVGSyR1Cnp5RyR4ZXJz
dkdpXjlIamxfPWxiMnI4ciNLKVhHcWVHPkdYUVl5PygweCN0VkpgJk85KEBqd0l7STg4cHtoQyo0
Rwp6Z2UzUGEqayF5aipOKUVpY2x8LUBjLXZOPFRtNClZI3JaZ1B2NXMtfDZrY0Y3OHMhcz8wKy1T
KGFQTmw9PW9hNCkKejA4TFc4JHI2K0FXKjh3e3pjPUl1SktveihLZStAJk1oaUZrXyRlemR4bnlZ
RFdvOU0tYnJQI0Y2TUY2NygxO3QtCno1U302NiRPSiUpSEM1al47cTgtPzlSTjYqYSp9WEZXYTBK
Qlg5NlB1KmlSQzIkRGtlPDchfV8pe209KSppfWhedwp6JVM/akRuSEBgbVFrPWx9VShldSthOz19
NGU1MXpaSFhLR3lDa0BOVHZwdXYzKmg8X01Ydy0xbFlrZTc2TTw7dmIKej8/WFlVZTc+QFgqOWZe
KVZWOCNVTnBJTHotPG10cTskeHFGaX5ARi1UYDBNdCNrITFze3h8NSlyR0QkT3JyJC1zCno+clVS
VzJFamtiJT1LSG1mO2Y8VmR1OD9UT3dzY1FMPiVjZkorUkEzcz88YjJ2SXIwWl9jfjEqcGtGZWU8
P215PAp6Q0BvMHdgT0J1eStfOTF5dnNKJlVfV2tfKUY2JDhqbH53WC1jcURmRkhWJVhGb349UTJX
I2pOemw+cUU3bTxPMCYKei1uYXBiKlJ6VkxYVDtZKldCSmZxVWFWJDlZcTltdHhaZkQ0UDhZUkdN
SzEoMiRiVXB7ZUBhe1dXWkNpaXFmIyNRCnplXyRHJXopSCU2SGJiUmpnPXwyaVY/d2dkUiFaUilx
em4jcE98QSNtNUo3dkNRJmxlTGw4T3F0eVNmMCFxVzZuRAp6MWEqNClMWCVuSHFKLSh1aSl7cHlA
djxuNyo+P1RfeUlGPi1wVGxeZStZTndSXlViNntrbyRCPUhOeUFMIVdee0QKej87K1BGMHZNNjJg
MU4tfllZeDVnPD93Sk93YEpqOF85bmcmRVdpLTl4M15iNDQwNyQ2U2orSTllRjJyLThQbGlXCnpo
OUdLJXtoem4wR3UmMzZTeyVMRCUoPEhRVyM5blZSaHlUQ19GLWNXU3J0eStDTntkd2BtUX13cTdl
KUY7Ryt0Vwp6ajAlfjRUZmdqUlNYIVVnKDc+TWhuVn04PXBiNmgxYjYmTiN0N0BqbnBOQyh8XjR8
KjVMbEZsWjx7NSh3MmVPQ2IKems4eHc7MUlIMHtiPCQpWnhfPT1gTHRKRDg4eWd6fjwwSnBwPDE+
YDxnPHZqUDcjPjBjRmJ+PDJLVDhVYEZYYTBECno4VVclNmFCdG8rIyZ2fDZtTDgjWDxXRXw0LWxY
cVo9cXFveEYren17cipzQn1PNz9pdVE1SkRAZkJPb017aXBXZAp6OXpUfExpfFVTJmtJZEZRcWBl
N3NGUFJVfE11fiNkKV92KHgja1hnJD1LPkNuNEtpIzd2NDJiVlAtSFdKYCFyPCEKeitBI343Rj03
LW57enxCckdhISE5RDhzTClmfk1jPl90KWZ1YzlTPFpIfGxINU0xVlVhNlZWYnxIK2g8UVM7NFJR
Cno2Typ+ZXBlaShZWFk4OW84eWZfMXhHdSVhb3k8PylUe0hXfiRZez40TFg/T2FJOUJCb1BXaT5m
bmBjYG1ZbWN6IQp6NTdCND4jamsme1BFKFl3TDF3cFNlVUBuWVdlPko7KikhUDEya2kkKnVIeS1z
VjM5dGNKaml+YUJYX2NCZm44KkIKekF5Xm1pKDh+SSg0fXxUKkRCTzVqR2lLcDt1bi0lbyY4aUgx
MHRVanUoV3ZuNyhAd1hKRVo0NXtxcSFwJVJEeHVDCnpLJCF+eGJJRE9LWTJkK1JTNjtlQHAwYVhp
UnZJQ2djbW5gNDJ2fHA8OWMrSG4kPWhnTDxDcT4tRk9zakEyQm95VQp6UyY5eF4yKlJFSFhmWmQ+
REFEQ0ohOzNBUzBCLTxCTjYmeURtTmotN2o8Iz4+LVQ3YVIjdzs5bSU+YChlRlZuQkYKeithQ0lF
T2lEb2FEaGpUWDAqKnBHKCslbWhlTChCKlJ1OS1pPkkxKHMpTTJ9M3NsKWAtRm4yTXd3alhuTjt7
VFdQCnpiUjlNUEo4VyFvPUE9I2QoZXRpQEZeZS0hQ0A5PFV6OFhJJTFteT5BbTMzVTVeX3RRTm5p
P0x5bH4tTk8jQ3c1bgp6KkZFd09ENldHcnU0RGZLV2J0bG0zY1JANlAmanZ1e3tTI2tlO3NVJi0z
fmhHTmp9ZjF1UmtsPS1nZUZ9RmtNZHQKeio8SiZAMFo+WEh7NTdRaXpoaCVSLWB+bihRMmFSSFhf
TGJTI3lBQlY3Jkw1Um0qTUJHcmdtbXlaZitpTFEjJjlJCnpYNmhCZHAjPFcqYGB8JiNQTng0fVdF
USojV0FWMTw+fm9HOCRhVzlmVjdnKUkoUl9OND1EaFIhY1hAYVZGTUEpVAp6dHFHV3BAM1dKfiVV
eX1pMGVmOD9OYTZ3NTJmXl83OGc5YTxiM0pHYS0jTFdUVEtjVSU3Ym1DNS0oS35jV091U1IKeiFS
KF50Q0w9SHRWcSMlVV5VNFo1PCE2I1RTelpidl97d1RDZ2JtKGZmaWFoeU1xYk5nI3dCSzl8MEsm
Pj48cjR1CnokKXopYXhqP0Z0enluTk0lfW5ONDtCaVlEK0g+ezJvaWlhZHBOSUtgVkY/V1M1MTxG
YyMpT2BqWjlMblVva2NgTwp6bFlvV2orNzskS0JoP3MoTW5IJT1KO088Nl51aDVLQmszfUw/bTxt
WmxpIVR6ODJpT3VQd0RLYCpjeChlfEshNnsKeik0dlZuOyk+enw0SykrOCtZfCojZ345OGYxal9t
Q1VfNVROVE1uV3Fjdk5QNmNVWE1QfEV4WUVnQmBISUZuMHdGCnotdiE0NFI/KDkoPE1+fm1gR1hm
b15rI3wwR35TIygpY2JMRWd2YEhCNG5kWWd5NTU2I25LRWkkak1nQyFqKmlDTQp6I1piVHYwdDty
fEZuTXklc018UV9Fb2F+NShseyhybShEcGFJKGpaUnwwNTdSMGtvI2stI0NKOGsjVmpzc1cwNDIK
em40TnRqTzFyUWYwdjNyQD1qdnc2O1gweXBaQVNzU3B0Q0pgdml4YG9gYV90WF40YSgpJXJjJUZX
dypPbiRrY2VnCnpgY01IPnNxXlE9VXpoJlZmRzNiWTlRYT5nJV5WcmdjZ2QxKm5ia3QkJlJyfnMy
TTlrYjhwYWlsS3FDMXMmUUF7eAp6akxiYlRFMH11azh7Mz12US1zMEw/YVMwT05xQmViITJgbSlp
bU19SDRrTHU8bFVfbn1tV2I2SXJmJTF4TW5aJCUKekZ6RFZrfDIkcTVPdCkqLWpFcD9KSnAleUlA
KWw4T19KND47VTRzPWNNVFZ3QGp1SV5fezh1dVAmN09BfExJSGVCCnpTMXczSDBNd0VXPmFSd2hW
YEB0cV9hPUxyRSR5OXkmYDJ7R0ZqYF8wNyV4Q2EoS2orYEBjUitqRiY4Knk/cDtoWQp6YUdCJUxg
ZVlRMHUmSEFMUilnTStEVERga2NPfm8pNWRgfU5xTEp4Kl9mKyYqdyFDQjw5Mnw1RjQ5K2lfaHg2
bykKekoxdm1EQEdjIUpSXj5KWTtDR1RrWSo0enpOakYxQmt5K1ZaeEd0WSRFKmd6fGJCX3BubzE1
I3BQelhtOGFIaV8mCnpOVzNESmE9JCNkYzdEMUxmZWY0a3R7SUZoSkgrK34kd3p8SHhlQj9xVDhr
YnJTa3h8bF54UGI/S3YyOX4xXm8jTgp6O25aZzIwZWVQMGBVVGY8O0haV0lJdE1TUVBTeXBtOHlE
NVdDY3VrSmgoN3JiQnBRNSRqVjhaI0EpRlFOY1lhWGEKekk1YW1HV1hNNHNlPHojek4kdWh4MC0h
U2F6eT5tK0JeVXJjaVZGJWhEIUY0KmE4MEZ3MlpjOEd3dE08QHUlc3dKCnpSeUJsMWZ1WSkyP20r
bCRTWkRRbktONGZ2NFpvdWxjRWAjWSFOSnV7cWVLbWVxeVQqYUs2TndCTWAocSEzM3BffQp6PXwq
OFNOMzlJOWROJlVnNT9+NyUwRENiQzRFciFtcDs3NkR6WC1GZTZmPyNCSH19RmlTVUBTWChRTzN2
R3d9TUUKemtfcFRxWntwUCQrfC1RcytfeztDaEs1MnkzcFJaO2ktWkxBbE5eOXwzbFJTUUh0KXZD
OVVqfSYpeEdGeylzezF5CnpKSU1FQUtfcTk7S0hDdXQ0TEBUdkZ+Rlg5KXczSEdLR1MrdXlmKDRs
dWRvd3xAMEx1dykyUzdke3dmSlpnNCgqdAp6Uzw5TmUxYlc3UGhUUnY9OUdSSCNlSWQjQVVRWTVs
YiZSVCVaflFCSlZYKjBRc0R6Nkw3TEp5OFZHZD5lcnJrT2UKejB5Y34xPTFAO3NzQi1WWE0tciho
cHhWYyhIen4kPHpWQzA3bSFkQj0lNFRMfUk+SzU4UHMpcihTWWxMWjt5Uz1iCnokXzRjd3VRI24x
Jih9M0F7JVpQNkZSa35+YEMwTU4hUSl0fFpHZlN9X0F6Y2ZKIU08JDJhVXN1YTd5X09Rfl5CZAp6
aFRyemQzYnI/YG52TFBvT1dUZzZ2TWFralc+SWF7ZlhXMmVQT15NcFFAez4zPHF+T0RIe1N6IzJs
JkJJRjtRTXUKeiZ8VClnKmMkMmIkUFk4eDFEOUhraGZzakNlNXxncCN0aU4wNUxxaFNxJjdBekYq
Ny1AcEYzWk8qR2lNPGBAS1c7CnpHcSVsbyp2NnpwaGxkdUY5bHR7SyMzVlJ9a0FnJSt7fH4/PF5R
ZW9rQEd7My1QMHtSMTlKSnMxVy1SRUsoWUx7bgp6Y3ZaX0p1I0xnT0w9R1U3QVFXPX5yMj5pYmFL
OFd2PklkRE1YKjBfISN8fCZSP0VNYVFnNG1JJnMkY3dvV1k8K0AKenszSihFOzZfeD0yITlrOE1M
NWc9MEhVdnBYQCEwVUwzIWZxYkBDbnJPO1YmUFoqU18rISswViNOT2djOTBDUl52CnphcWFGUDZ4
dThAQGBxUF9oKnkwPmpPQ0w9YlgoUUxAMWpgfDJtU3JfaWhsWFc9TSMyV0d0dFg9cjstVzFAXkFA
awp6MnpVamxPflB9VkgzZWNPWk1AR2E7cT4pbEtQeFY3XjFKVD9jTzR4JmNPS2U8Pyghezc5e1N7
aD4pTG5xJW5KJT8KekFleitBaFFGbSVsbT1vX0tUbG1jYiRGRyh7Mz9mZiZ7SygjJFVldU9qRFVy
TDxjbSVNTUYyX1leNm1FQDwjUHd1Cnp0MCMpJjk9UVpld01IZ1JfOUBffCVeIVQkajNrSlUkZTw8
Nmk7fn1hQm5wfndnOCtJdS1YLUVuZHZxRVZ5ZyVPSQp6JWF1Y3pqcSFZaEpUQm16XyhfVGBmWmtl
TmxTcmElez4jQDJLSkxQdzh+eStJO3tRUihLajI4MitvTFNpJXZxaVMKUDt9NUNkKW1BQ0ZWO1M7
KUhFKD1FCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFt
L2VjbGlwc2UucG5nIGIvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlLnBuZwpuZXcgZmlsZSBtb2RlIDEw
MDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi45YjMy
MmU5ZTAxM2NhMWNhNmU0OWQwNzU2OGNhZmRlNTkxN2NkMmE4CkdJVCBiaW5hcnkgcGF0Y2gKbGl0
ZXJhbCAxMTg0MAp6Y21lSVlYSD04djdCPjdLaipKSjluZDJ5O2x5TnxqLWtVVSFqKVMyXnNuU3RJ
MWYmTHRBcH5ARWE3RzAqZlQxS0gKejNQQ2BLKG40cktRSU1gd0F3WDB9QX5saSNBJXJDRm9qSz9I
e1FpRkhVR0YrU3ZhPDV6ZSlpdD9GNHc7OV40Qj5SCnpkJTFyY2BVZUMtYTxIPyV4PFpoMkUoQSRj
ZjQ+Vm5TJnVKUTJWYzhtJlV6eXRYbTV3KUJoP2xDPkBzKyQ3PVB3TQp6eWolMkBjO3Y7bjVEMUF4
PlYtdWBBYzhOKGd5PT1iZyUrJD5BQStFdEE9dDB+YT0oc1dvKHtkP2hzM1p5diM7U2kKemVQRVUw
eld1SDVsIUdob1RUSyZqd154NG5wMH0lVU84dm5wKng5SW0+SU1EJGBQQThHI2tYRF5Kb1dPMyR6
aH4jCnpPP3FZaVFFJmd8cF9PcEt6PzRHR2Z4ezdBK0pkdlMqZ3tyJThRemp4dXpHTDNpYDZJMiZk
PC0rbVYlJWc4cWJLNgp6KCFqKSttPjxBZ3ByMXwhP1NQPGotezBIfktfYCN3Sk8mPjlAeE1SKkE5
VHE9ZyQpR1ZIe1lrPjs/IUZMMyVoI3QKej59ZD88bWBtPTF0KXtKIWt1ZjVQZ3VMRD81e2NyTXpx
K3Q4c15mV1VteEY+SC0qdUJkeHhVKjgrNnpsaFB0UCsoCnpjcnlGKWIyX2RKNCpaXjE4K1V6aXR1
S0VwQTEzRDxfTj5Zb1Erfnt9KVlUUCtiPGwhbzx2OHJwVnl4eGQ4TH4zVAp6WlI0Q3YrX1JUUnck
NSE2aUxPT1AzX2ZiOG5peSZARW9pdmItIW9jUylCM2N3cnwxQiprP0hFQGhBNXBwNFlqd0sKem00
P0orPFdtamNSLSFqfSlZN1ZEKyEoJmolcSt3cUBebjYwIypPP2BnSGJyTV5tVkR7dTVMbGlDMnJk
RDwqN21zCno4bSkkaUBISW1zT1JHcmNMZXJkaCt2SmoobSZIZjIzTiVWN3M3cFE/Jk11MntrTlV6
MGg0YUl7IyNReUVhP2JuVwp6WGcxVi05OTNBUW02YDs3djsrQXNRfGVsdHtUK2hFPGlrJWB2NUp6
ZVdhSj8oRmlsTCRpa3ROcngtX0dhSGVDJHUKekw+dyNNZ0F6OH1HKnk+P1MoJDd6amNCclI5Wn5K
dj9kK19tZyZVXlJpYDJfP01AIyVQNiZnflpnVjdTUElrUWF0CnpjTSU3UWFJITlGKk5qMyNFOVlC
YEome3ZiNHpXcnpJJjUlcXFsJDd4YyNGPmBqIzNpMmxTPkRjb15RTl5WJX4jVgp6UlFoKHorPy1W
dD5ZdDZYblpASHstbjVMWSVVIXVEQnhhOUNfcS1vbF9ORzJuXlJsVjRfTnd3UHEpblB4e1FmOzgK
el9fS1pJcnlCYDlFI0w5RTNOMG9JKjdNSnVEa0EjY2NsSWtMI2JBMDBYcyMtVWRQd0dXKjwheX51
YXZyfGtYX28wCnpASnZ9cSMte1MhaitrfiFAI1l5NnVUKzA8Oytfa3ZKb1Y/KCtHRTclXihPWnVM
MllvJSZ2YjgwcHpWNClSKTs8MQp6eHFNI2cofVEwT3ElNEJgdUpeKENwUkB6QSZTPkJ0I0s4bThS
PWdoLWRufiNzOV9yZ0A2RDRvbXE7WFl5OX0kQmUKelF6eEo5WGc+bEErRmBJbHpgV1RgeytiajBQ
TyomZVhsKj8tWHVlZ15yfT5EYypOfjBMZ1ZnMyFtQFNHUGBUQ3p3CnpnJWNQWlJkNDM8Jk9UdTQ0
cj13eHBpOC1IX2pecEdRRGRDNWt4OH5ZSFphbUJpI040I1BZMG87MUtwUzF2Rn1Efgp6OFBVRFJz
eGFBUU16fUQzPDsockNKeWpEQVVaSFZpUV9iQSg4Q3hzVytkPX1obzI9NDg+ZEQjeFd2VXhVOXJW
ZncKeiYmJF91NlQjeWF5aEQlTFU9JGxLaFZ9U1B4fE8+ZG96cjh2QHVtd2lYQXA9YzhKUCtqRSRB
Qj5NME5JKlgxOGs1CnpNKXRPRlFHN2h6eEdlUFErc1FwTVdGeTV4NHlDVCRyPjY8MVVPQnNOWFd1
YXx2Xnh+RTZQUSZ8VXtoPXYqdGt9WQp6K0IoQkpzdX1XJFh5ckNqWDl7eUljanNnIVhtaVdWe2oo
eTRte0h9UXBvMk4+SjBEalJubDFqQnlrMkExem19RVoKemgoZSV1O2lqQDI9bVRgMHoxZXItX3x4
UCRINiVTZHVHRXpRbGUlSF5WPW08MFBqZzkldikkYjRieHF4VHpHc0gyCnpiLUxHNmdBcz9sZD5a
WipraCgwN0BUSHxgIUZOT1ZmJXFWNVdvM0V5b2cmZHYlUE5FOTZ0Kno4TX43bjB4TU94cQp6VWJX
UDNsJWgtODlPYyMyTTQpcHR6Sm9UPkJyaytsbExpJl5sZnZ8eClgcWVkQjgrMlpocTdyNkA/RElm
aElHXkAKenNrLU07VGNIO0dBSkNIUyZFNCVPIy0rdUVeeVdFdkx9I3RPaSZvQkJBVVo7OHkwcyZn
em5DN3UqOyo4NzZRcVM2CnpnK0Q+cHQke1pNWn5LVVVRNUpeQTg2fm9Wank8OyY4JmtyeFN9fGJz
dEA+V2gqeD9qeFRYQ15Pd3NpcFRCcW5PKAp6SGdvJE1jQVMtYVpfcyY1VT53c2lNOV9YfnRBd0xZ
SHZaPGZxeTFrZWdMYkB0T1JeP3M1UjtIJG5IcDxrQCE7a24KenU0S3MwS25kcUtYfnRZMTdvTDwx
ZEBOfitHMmluMj1udlFkK1o9clNEQCQwVV5SQjN0KzRIZktDa1M4QkNvZWpECnp5IzF1YTN3TTd1
a291Xng1RTBJeWd4Y0RiNXpzQ1VgIXBfdEZzanIpOXQzSUN2VmAteGYoUyhaSkAoNV8tcTZOaAp6
VnJ+Zm5GQHlpRXllXyk4eT1Kc0xLMz1YWGcjOVRmMElAN3piSCgwMXIpKCM1N2JNe0VEYz8qeDw3
aks8aDxlVCoKeko+T2RIdDI/dGJ1SHwjbWo7UkV6TnBwfHJsVGM3bSV2fk1tazBqM2g0dnVLSkQ2
Z2NaUWQ0ejVqdm07b1F7PGwqCnpJPzl4V0hrNURmSzYmdjl7T1NQaTBNJWdLdn47P1lGfWFlbCZH
cj5GQ3JSJnMxbGJfMWVrZkh9d0d6RFV5TyNmZwp6KX5Jd0ckN1J5RClvRUxUM055OCpoZWY8eVAt
ZDI3Uko1aDImbzYlU14+aytsKS1RJEVQcE9ZUW9rSS1QYVZRT2sKekwrditSZl84a250ISE2biVD
PWRhU0w8Wi0zQHIxPDF5UGtsQGxkLTZwdStXMjtTUXpBWXV5U1ojbCVGR0cqdG10Cnp1QWJVRD1R
WGM8PT1zcD98QmppN1VuO2ptY1lkfkZGQ0VoKGAzTyM/R15LY1dUbWR1RDJQcmdiX0I4Z0FoJTtC
bAp6Wm1CSjNUdkdadmh7cE4obWQtO3Jndzg7SHFqMD8oPyZ4XkJCV2t0PT50TEowKjdjP2pkJVdF
KGJ3ZGFzPTM2NykKeklgWCN3JSpjfTtYS08lTEREcTlRLT48T34rQXg8JD02SURedEk2dnhhJnNH
PGpgQmEra1ZfKGg5KjErS0FWQ3F4CnpiUTBtaTJgZEdhaE0mN3Z6YElvUUslWkRJJC01USowJTxp
YVRGNVJkJjdTVEchNnJ2ZDQ2UVpsPzFxJSRLbnxsQgp6Ynohd31EfG8oSUNrWE0kd2lueXYoWmZH
TCZrZ35GMFZ2dzsoMlJxKWFgKDg9KTRqRDZRbk4oYXMyWUh0VEQ0Oz8KejFGfGZZUl87TDVtbTJJ
YHVlTmdRJktzdkNDRTZFJjc9ZXsqa0tSOXNsYUhAczVwQD9VRXF7VHxvZEczYVNneERICnpzclc8
Vlo8KEJGUT1ZdXQ5IU16KG09UFRKPlleOy0mRnlZcjI2cD5YRj1PPFFKYWtZLUAoLXRtLTw1ZD9o
bTVBPgp6MyNAM0JyWWV4Wi10VjJEampOfnBGPyFiNVVpfSVIPU1kTVFtZ0FBWDdkb2dmbk5ze0tK
VV5fdWlqRTMza00pS2YKendXQnBRYE9IY3x2JHVoRG5UNj1oXkgkT0tmNTZjTVRMNDshO3BzQmF7
ZThmPV5QfH1nbWRLNm1BN19ubj05bW8kCnppcUVxdkVzeTxNKj40RjhCaT94Ki1rVihWSkMtdncp
JG1mMW42bmFtYWxhU1p1V1lMNDI4Iy0jb29raG54KUZPQwp6VjFJPU15dlI3Kj9AYHRpMSVyP1Rw
O0gkNF5HXnJaS3NleilGMXgmKnV7XkpJQFkmMSpzSi16QmFPc0VoUztVaDEKejs7PVczUE5pNyVp
M1UmUFN0d2A8XndheFNLViZPRDElQTxDUFg8VWJXJVhCfTs+b0A7Q3NrOEQ/SHFAKE01SmZ6CnpE
SmFNcXB5fmF1eDRXdyhXMW9XYD9II315WUEwJD80IV87JmI7cXVeVDIpQkFIdnFpJW4rZnZFLTEl
OWZeMj81YQp6KEskcUVzUGl4fEZ2PmFsc3NrYyZgZE9AWnhqSWN8dEhSXzZXSDFBVUNxfXBvbSlM
Wk1AUGJtZWRRV0BnfEx8ezsKeiZeJFclKElneldXRyQhblp9KD5jaDBVZl9aSEM/Tkt2YXhBZUxW
XyZgeVRqcUkpQyFMMXNEaHVLV05feHJQemF2CnpeaTRPZHwycXlqNG8za0dPR3BEWTlGXkUkSXg+
PVIyeG1vSjRjIVRDRHZMdilfTlktQHhSRFB+R2c4YGNxNX1qSAp6M21wSUopMytnfFNkO05sT1ht
YTchRDlnQXN0RHNgQn09YG02MGAyUCR0Xjc+NUxiSk4/Z2lDRGhmTVg1KF5uJn0KelBPQHZrPml7
WigkWGhDSG9zNnFzcVY3ZkBWdnpqNFR4ZTttO3BQbU9DMDZOIU50anEzeXplTV5LWVdwbSomTz9P
CnpMZWExMWd0bXR2MTZ4MmI2RHUpfl8wZX5HT1IpVFhPMFJaOGlUeypITlNqIyE1PXlhbmdScFNa
UEI1bjxrfiE2ewp6Xk4wfktLX2lWJCprQkQ4U1hJUXU5Z3JraW07QipnKm9QcUQ5MWNZKyM/OEhY
Nm4tQ1FIM25MTHRYaTB7NGZwZEAKejV3WUBnalZwfipBJWl3YSt+U2U7dzFMQTwtLUtaQ21TPSQ3
VkNlWk4rR3R4QmZDTmlOQElXSD1PWDB4QWxCUyteCnpgUHtTSnh8VURNREpNPzxDdFpLN1lfaDdV
cnleTnxBSFQkbnwyVGprRGhDamJ7M21PbElBREZya3UkLTVNNjdrPwp6YGlxS3cmfilWYDNafFBQ
aGdBU3gmRWRvRGd2OXd7TXd0THM7RjNJRm9FJjJ0PmJhR2R5ZDt7akVTKXpWZGx0Q1gKeitlMU5r
O0xpSUNXZEYjQ0EtWXcjQU08bW5FdDB2dEFsR0FTcDUwU3V6VD92YTVWMzxFNnhWSk54dGJSMj1a
VkZlCnpGTXNPYCZwbFZ+RXA9bC07PnIpQnpHRiozSGYrSjZ3QmBFUCFfaC1vbjUmblpCWjJyJmtm
ZjxTRXNEaypDKV5Tfgp6P1BPRmhoUDFfUEpTXkFiU0l4WDRsM2M0ZHpLNF9gMl5OZmFzcV9xelpS
PiE0d0RRSStHIT5rem99OVE8MTJAU0QKekgrRWtZSTZAbHx1NkUyVCVCUX1vYWpKZS1VJnROUnoo
MDBSY3BWIVpeRlolfV9XbDRJVjk1OE5IOWNSWHozZ2d5Cno/eWhCdDtIPT4tUUF6Y2BtN1l2NSZB
K0RubTklalhRdS1PRjN3RXRgazkoVzhBQVBeflBWfTVJMCQkeWpgX3QwNQp6dC1zMiVAaFk8SUEz
KzI9bWxoOHszVnE9PlEyNTBOUihLLUJ2dkEwJF9FNTB2Z1dhVyoqQSV+Mk48XktNaC14UyUKelM9
bWsxQnhTfUBBYEJsPmI1cH5eRlApaT85KTBQWUhTRGVVPzchcEM0QzRxa0VNIWs/cDhDQ0dGMV59
KjNmdm5lCnp3YmgxKVdkSUB2djRPXm9vPnI+eyNeaTxePzY9SGJlfHQ7MURRfldCJXlmbGtpTXIk
eG03a3czWjhOR09lTTk7Xwp6QzxfdjE/VWp8QSU0dmBTYnQ3WXBMN2gjK04kKE1wcXJDTSpQeEt5
Vz9AOGN8KjJNOVFoVjNWcVhfZVd5QGs9TjUKel5JIWZQM05KaVF4SHpIaFktKHlyakV4KFVPWX1u
al56WUdLakhpfEN6VzNpdTRlY3t9KWlwaHxRMCRpQlZSdHYqCno5QjsqRG1XJUIjKVFPanIkelVr
djFfLSpmOXhvdyEoQT0hKlczYjshUSo4V2okQGJgIVRaTXNVYTY7JHB2OTtfdwp6SDR8VEtBIWA/
NE1ifFFDNmQ1OG9DO3BFVzEjSmVueGBFMnFCfT82Rk89KTxWd0gwK35eMXx8WSRsP1lsUnUlSHsK
elgoMSlLLShTKHVaelcwOGloJWNqYUwoRWdKaXFfRStDMitMKV9KRiZjK0NrT0BAI1N6aWgpNCNT
fDZjKlkmMFVyCnpVK2Nme3JOJExAWTsxKDdDUkAwfiViazVFZHJiQT1Pd1lNVFlqcXh5TnlZJFVH
KW5MZUdyVWgjXlU2dF5ANVliRQp6UVducCQ0NHQjTUh6fFBDfEE5aSlYfjNgYiE8PTt+Nn5VMk89
b3V5R0h4Rk8wQG96Vzc8KXp3aFIkKlMpU0Bxb1YKem8tKHJQe3RBTFVJeChCP1ZeckU7SUd6fCko
Yksxe1ZkQzZmcyo2QSpqQm58JSolY2NXa2tVPyZBYiZJPj85bTVJCno7bDAwaUc3MGtjfEF9aVp2
Xy13bm1OPT1UeCVINW0+ZCpsKjZJUEJKR3hVciYhKjgwPkNZam9VenY8WEJicmlkVAp6UipRTyFi
YyojeFo2MztKVFAoZTR4dGdDNyFZaTlkYTdIbip6bmliIyF7fUxkTiZvSiMxKEBJS1lsPSgjUi1S
TVkKekgrJGFhMF5tP2YjY1hPP2hIe25gX0YoPUR0QlFPVkt+JkNiYSZAbCQqbD1QeD1UJiYtJmh+
JTMoWDRAZjNoeWB4CnpaJVclJCtaWndpMEVGfUh7Nk1+fENKVVpORmNuVUYmeTBKd2V3TDRgVUM4
SDVqO1JAITZLKEQwe2N6fjU2QlJjOQp6Z2slJX1FJlJPbEgzfVhQOFNHTU1rJnFkaWNQRHhyXnl1
Z3dlN3c5SWJEJUpDXnBObmVEWT95KDZscjdCWjw7YDwKellTeUtHeWNsfkZ4fm19fXoxNTQ4KzR+
QjdZRkArK2ZoNV9DcEt2JHwmb2ZhMmpmV0RfSDVRKHBeNF92SSVwdCV1CnpBPzEpbXo0c1Vga0tM
cmNgfHFgQVB8LTdXZWg5MTY4cEctOWRsb1NqPn1QOXE1Pyl8b1REd3JkRFg4djBePnVnQgp6KEN2
QkRoaW8taC0tXzwwbj04cVlmP0pBZlJYYml9Tl9NVjxJWntESWQ0NnM8dkJnJUhXbXtOfSNBeXEp
SXFHQzIKem5JUnApZSNkK0BxdmYzWHNYfXtuP2xsYS0kXkw4RDRPU0VUKmdQO2lATF4la3hxNXIp
UGRgZ344akNuPyVCOzF3CnooZDhhYTN7WFNwZmI9TWN5ZH0tUWxZbkd5UnJoPTNpYHREX3RCPmR4
KSU7dyRuQ31YIU5xRFJ1X181Jl5zfipxJAp6LXYhWUBOaThXPEM4WUNIV2R7Y1VhQzlsKnRrfj1w
O2N+KyRlfXBKN3pNJCF+WV4/T1hPRUAwdT0pKXwxTno4VkAKel9EZl48b1E5bHY5ZUg9TzNBOSVW
Z2tOfllBcmZQWW53emtLPENLSF9qIzJNQHV1NXVSNnBoaHk1YDtGUlRpPyVtCnoyMEo/IStSVDUk
VE5XcDVUS1NwM0MrTCQmNHk1NXJRWGs8VVJ8VFZRQCtYc0hSXzBPNklkQWxTVD1TKG1zX1ZmMQp6
V3FJYmswPFJNS2hkJVowKXBUOHlYcyU8fW0xZU41dGpBdkxBelBfOTF4X0ckd3U9RGF7S3k4KHlk
YDEpaFZvdSkKelh9I05QVXd4YE0+YWotQSliOzQ3NlN3dDRqajk/OTJnNTlORykoSE83cHopOUJH
QGhZO2M3O0t7ejBKTWdVY0Q/CnpeTUB4aU4qZGZKRDt1M3M2eD17QDROeFE3PjxWYDZDRkVRPTkx
JmpBaTFJQTdqcn1kJCYzSm95a0VhJTszRT5+TAp6NT5+bktDIzNYNUF8cyphTyojTTUpVWFgRExv
OGBGJmc7UW1fWn5gOUZzN3tgIUp9ZENoNm40YGxGV0soS0hsYEQKekRhJk5nMT53Qj5HKChoX0V5
Sm1iakhwUXJ2YWojamBSTkFgKU1yZyRePlh+KTQpfW5aTSpxamZNeH10YCZzPF5BCnpzTjs2YUE5
TEF9ZnRZaTtKNTdxKzMoQjFFNTZqRjMmbXg/c3p3dXIhSGQ5Qz5ITHU5ajxKMD9iTjJERyUwaDEp
bAp6Y31FYD5PVj5DOWhIK2pGPXdoZ21efVZ6eHYwYWIwdUxfIVVtU0BiOEZSel82RV5FXy03YUZM
QUlfMmk0eGhfOSMKeiVPdUZFJFQ5TSgqRDBtViVhSElrcTt5UnB0Pj80Y0syRyg3MklEPyt0WlAz
bSk0QiR5ZXQxX0JyIzNeNXBEQG42CnpyZ1R0alo+c1NxOUtwRkFoOGxWa21naF55SjF+QU1sZTdF
NndYdH1pTXJVNnIoM00lJGQ8N3w4bSZrTGA/QjxwWQp6Xm9KTntjOS1+PC1NKyR9PD8hSFN8QyNa
Sml6bW8pOC0pJGVtKVhed19Pei07YENDZiM1b31mZ2tAKzxaUjwwUFoKel9WczEjZ3VpMFhDfUZY
LXIwY3ZSKVRzKCtSSEc/e1hpTGhBeSZQYlg1RWJzNGJTanFyXj1XWjhzM28yR3NLTTQmCnpXZVN6
N1J2XlFwWXRgK0dTZzNoWFktdy1pKWJsYnUlZVhBK2JxQiljKGhVN3haP1ZIc0BfSFIzKWNeM1h8
QXNHKwp6dFJhejFlKH08aFJGdlhBUC11YytOeTgyRlFwS2hAPlkhKE1QdGZ3fXJLaTI4PT4kMXhu
K2M8aklBIT9IJXRIPlEKemM+JnxPaVY1aj97Xm0jU2pLa21Jbn1gND9kYUE9ejVYJGVaUHc0ZlEm
bFMhcl5TI0hAdHxndyhmb0FjTjRYKVUwCnohSCVNc3Q9SVRiPig9KjtlY3pNSCkjdnIoaUlGZXR7
Mjh5N2pgUFk4Un1DMkk3KUozUCt3RnpqclRPWUdIKXNGKwp6aHl8bVU/Z2labT52P19ec1pKSnFS
Y310OG1Na3NDJHV7Qz9pczdQNm1wSXk5PlNzWHdseH0yUCEpTFJjRXY7RUQKemc7YHMhe2tIZGRL
TU9ybzQmVXFgT3xOZ1YqfnJgRGZFVjc7JTkkRC1lO0NPQW4wO3FnPU9GdTZzVVJIP0ZQWjBLCnpP
YFUhdGFUb05pPGBFUFZvY3twNHMlMHVMY0VhYH0mS0V0Mmh+U09JWFVsQVNDaHZqLThJdExFSWNT
IV9Ac0hrUwp6VTE3bGJobURKZyVvYFNRNks7Qn1tOXxMbHEyV1JYaE9qRTVjdGVeMTIwdEQ7U0o1
NHwmajthJmg7UyplJn4qITYKej9ERnU3KHdDb1duXn5ybWs8QHMrZ2V4eXhYWX1jXigyfDY3LXR5
RyEtY0V4XyRWWnBDXk1Ja1ZaZGlGMG9mSkZhCnp0PHJaKE5idnFaUl9vbjVRRzQtNCpGeShydU1j
P1Jia0ZtcSZjNWlZMTU7X3R6UjI4TSNycEtUXlcpalhlMWk1WAp6K25MNUNKXjNxKD1UYU4/WT1q
NjtCRkUmYEUoP1FAcGwtY3BnTGo8dDA2Z2pKNUNINzMxaTIySlZ4R0hpKFV6LWIKejA/TlcjYnRk
WCgjLTQyTGNgZjxOXzklbUMjO2E/R20qQntkWEd0Qj4/R3w5KzIwX1B2YipgNUkyTjluPjBhXi12
CnpmXntZWUpxRS1QOUFCSVFmKzZUMXt+cV9oS21MRGtOeTRaS2JZbkdvVyhxfV9gdlo0QmpNaVVa
Jk0yVVojc2FBSgp6aipnQ25ofUJ3ZFU3M3hJeTs5MXJLMGUxbihmME9fXmFCZVFxWkA2IzB1anp6
VFM7QVlxfkpeJkdsanRHdkRtcmMKekI3U15ZVEd+Y1pwPyVWI0QlR15Vek1sVjlLZWRvUGdXPUB7
YU1RK0haVHRKUFJKaGt1UT0/Wj5nUz98ITx+IUZtCnpHTTJnNEwlO0s3SWFtZCVkS24/Zj1Tbn5S
cTNHdFRZWkZhSjwqV1ApNG81Y2BqPy1nS1BtPTMxIXZjK29nWVVFaAp6Uzk9VTJYJWlFOWBXVV89
K0QwRmBeWFJfXjM8aG53RGE8ZCl2ejM5VyF3cnQ/MztDP0pQcElHLVdWdzVmQDY3aDIKem1SVUlj
cHtBUzlaJlRHNlUkcEpVWUE9XnZCd1NNQXEyYGFgbX5QQE5GOy1uUik2eiZONmIyV0RCMGNxZEE5
a2o3CnpadThOaVVqcTNIVVklP0N3NVRSaTFoWT9abUFfMFF2cFE2VEZ9NEUhVV4qJVQqKE1+USM7
d0YmM2skIUEjMnQoewp6T0FTS1BhYjt5P15jNExgKSZXTW9ZTT4yfjdmX3ElVCp6NH4lUnFUVGR6
fn1EPmZYekNsfmk7I0c8NXZXIVJWUW0KenVzJVVXZDNtPm5wNz9xST1MPTM5bVYpTEBeUzh7fjk/
QF8qe1NBP2tjXy0+a0gzOyNTMHllaTVGMFVGWnUlaFc9CnpXYmktd1JfOXBNTztpZCh4RExaa1BF
UGpPZUVHQkc2SlAoYE5WeXlMNjsmNyV6UFB+Mk9CTUkyQFZHP3Q3UUB1bAp6KDl9WThlKmdNNz56
PGhaX1c2YUUqOGN1aE1xcDw2KnNie3ZkbyN6PHBAMmE/YThCbTZOZlFwV2QwPTNtYncmZmEKenFY
SyRCMERvSjdgWEskVmBHRmJ8U3YqSnZUZzNLeTs8SXw8JWBSNnhvYSlRQkp5VkgtRG43QG40UFIh
PChCIX1BCnp2T1dKIXVtVSVxeCpseEhGTmZQTXlpRERDWl52cTtpKEUybkhhPjFvaF9gQiE4SV4k
cDhPcWFZRF5IMlVXOS1kZwp6dklaPD1FbFpXckFJK2ImJEgzKlFRdysjY05zYzA2dEB6PS0zX0lJ
YTgrN1d6dlV3WVNlRmAmWmdCRzVFdUIrZU0KemhSKkU9bGp5ZGhpISMpXiRFbUM5JCNhfWNRR2xR
QXFANExvRjNYeHQ1ayQwTER5bXZfI29NM2RrSFVeUWhZeHRlCnpsUV8/NGc5VFJsIy1SZmFTY3hV
ZD4qeXc0bl95XzE/bHR1U2RaN1M3LSh6KWF5aUhGfFBFUFVRIUZQNWtVeUhpZAp6QCo2ZjlGeEkw
WTFpT2BMPHpvQEx2Mj5tczg2S3xHV0BCTFJWKGBrMjh5WEhsSkk/S0E9PipgX0RXYkdSLVU2fmYK
ej0zY3AqQDExQlFafCMyNV41bVZkejU0RUpfUiZvYD5GTGdiY3IpbUYlbDBtP2FFJHgjaGU4T2dB
eVVtWWx7WmM4Cnp6bmkwTktXel9eXyhfKEYzcyVSd3NwTEk+P0AjKCpxeTk0dU5qS2dxZyhvaDM5
b1NFJns2YjBAdHdleUE4QyF2WQp6SUpTNV5tOWUhKj5Sb29re2xxRXdoJlcpVVpMZ2ZMX1VFQTh3
e3tfZ0VmTiVjNk0qdyMkJk9CcnltMG53UyM2cyoKem52VUMjekEmRktSS2hlZEY7UnkjTGB9UFh5
ZiE7TTtCbEc3dFM2eklYViVpcGs0XkF0THlUUz1kJHBifFkhP18rCnpDSE1maUtwMkclOzlLfUx5
JlB0Km8rRFBydz9XNUN5dGQlQ08zO29RWX58VGpQdDVTbCp+O3R1VWJfXk9oOzQ3WAp6LU1Bc3dV
SlExWFVVKmdXPVN9QXE1MkpwfStwcTFsOUlLaXhONDB1ZU9KYVcjSWUhanA2V0gqM2s8P0p+VXsl
dCQKelMxbSQ5d0NacTVRKiQkeVh4RjN6dy1oV3tpJjZVVCZMey1yZSNjYyVoaDxuWWJDblElaEEw
VVA2Pld+Zz1UNTdOCnpzQXdDT2UoSE1mZEhwa0F6OzBWR1hmeitTUSYofjlsLUZnSzZYTyYyJjxq
biVoVzA3WC19cGVJNj1ZO0FRXllxegp6RDlxNkR4eW5GNiZvaTlIMU9aQD9ydWpefitZSWp9Rk5F
M1dqVCV4Nld4a2Z4ZCo+TCkhSjMkdkYkbUdBcCg7TFAKekpxY0opeyQmdlpaV3B8Zyt5JlNPcj5i
dD5rI0JPXjRaKEI0PF5ncSklXnFhLTdsNDkkdTdudm1LZEtVMXdBR2E9CnpEJTxZVzVRaHtrcH05
PEZ7XzNkUktxZzVQWXJDRVlYOT8pN1Q1ZUA3e2pgfl9oU3Q0SyhEQzByRT14VlRUTSpTfAp6M0ZB
bVc4WFJ1KzNAZEYpMEQzVFdsPyVoRkRkOyU/NndsR3ZAIyEybWZfUWU5b3g8KT4/fCVLQVl9X2xw
ZjslZXoKelIhNHEpI0dQcEs1cCh6MGU/b2diMDVQYzg+PmptSzQ2dEJ8d31wMD4kRFU4MWxsdyFX
bFpWPz5CSypSeVVPZ0MpCnpmSFZva0Nuak1fWUhQSjRtbT52OUk/KGshVkVPNT5NXjI2YjdqXmoj
NC1hUWk/RUNzWD0mZVF5MFdxSlc7NWVKKgp6eD95Z1BLRV9nWW48bnBoYWNINXlDTCp5fiRSS2Ur
bWhgVFQmMWEoOCtTK1ZNPT5BMntmPi1NYTcpUGs7bWxIPjYKenA/MityS3Q7Ym1NcDV8PEhjYGdO
Jm48QEU0WWN5NmFiN0szOXtsWjR5OD1GISQjTl9iVW93bEYlPjVmN211V0BgCnpKdEkwa0B2Y2wy
THZ2V28jZzRTckxnWipvJlFuYClkOCl3T2MyaG87SXhkKXxPYTR3M2heVn4rNW1RSjN3YSNnbQp6
PTlNKSFUTEJFe0Q9KSs2UHQrbitxeWllUWQ1Y3p5Izk8XyFjKGBhZ0s5aHp8Pkl8RVJgYCh9WSh+
VlpKYzc5Z2oKejh7S0BBaDM3cVFTKn1YTzs7M3RrSlI1WGtBIWhZJD1IISpQSnZzY3phaklGJXBa
JiNHaE1EfitVU08qUnN8Y05QCnp6PmJeZTlYfHc8ZEA/N0FwYyVGQ2A9Z20wYyhNKj84RVErcnBe
ZDhsX095MEFkc1ImUS1YZz5XcTd4eTFuYnJfOAp6YWhLc3VPfktUNjlXcX43VHR2TTJkPFFfIU00
bjtybUJnaXc1QVRmR1diZkRaeW5PWDQqclNuKGA0ZHooeERFMzkKejdkeSQ8fDVjWWx7eXZkY3RU
SHcjRSlVeSQkXjVINyZuJkBiZjd5OzN3fHhCcFByUEJEXiE4ckJxd2NJQCVOckNMCnpgdlI3PmE+
MGx3OTJweTlPMClSfCQrT00kOXVrU0Yyamd0dEQ9T0hSVlJhO3hTNGBFdkhxKjVAYXo9eHQzNkEr
fAp6dU05WTdiJDlqYCNDN1BKR3BvQGxnNTFhZzRLdm1AVnhhJUxZLVVlKHg5LUc7PV5TVFlHdUEr
SllRYSZZVWUpVjAKej1taT9vTFR0IX4tNU54WW43di1yJENLJDE8NWtXU0tmUG9zYGwtN1hMcTFU
blY3Pm1sN1F2UzB2Qzt+bjlrNG5sCnpSXlBPJnIkLU1ZbjJVfURpVS1LeCshdzN2PTBsdkRXXmRC
VkQ9VH1gJHVvR1hOaXMzUykkemJVVjZGbG40aVl0Qgp6WmB4cXhjfGh+QUF8WGZOQTlRd2ZSOCNS
YyV0e3FrcCRKITJuMj1iI3toN3hkNCYxKUJ4bXFNI3BtT29ETUZhKUUKej9XeU9xN3EtLXZtMm51
aCV6QSNRJk1CKGZFPGpYbFU2KFRiYmkqfDR3cHVINlA4WjBSOS05WnJqM2A9dHU0RVNLCnowe0JA
P2x5R2JOVGJiUiFUQFAoIXZ5ZGApMGdwbms3PFNhdlFUNlVWTVBwOG4wYChXV0NaQGdSO3tEcFZn
KHEyVgp6WmY7cHREUUdXPUF3JEUlUkA7KnJndjgkbD57d0d5TVBAYigyZ152PkIkcGN+e0RyTDdp
big1KHJsNkZeQHsyaXQKenBzJTF2LVRQKHVuS3NeMil5dU8pWEJmN3JzbVUpe15jXmF1e316OGpV
bzBAPjNnPCQtU29oc3JgZkNUTiRFal9pCnpydERydUFLdVZMVDNYdGhke0ckT3orUEJMKzc0OEtt
WlQ1eHI5Uno9cFpTOHwrTEpKRFAzWGtBMDxWQ0YoRTxHQgp6PWw8ZXo7UCM1fm1rN1dlMnwmTVRH
V0JKI3JpSyNRRk11YnhCSmshZmVrWVFlNk9rZ1MjVjImO3B8fXpIal4qd1MKelNTNGlOT0hfd3lp
PU1XTVV5Z1gyPkJYdG5acCpWdU1TQnNRQD1tbW5fR1FAVXY5QitSJnpBYjN0YH0rIzhCdmIxCnps
VzB+KD56fGhvXmJ2MyVWWkd6VjJfMHFhd3l4ayh6KTxzd1EhbHVOVnZgKCZtQ1UhQ0w+bERrQl8t
d2BJeE5keQp6ZnIwe0tjWTwpVThsUHROJWdrYGlHZn5fMzB0SW9Od3ZBZi1gdzlAPGh7N1VZK3pi
RzMjPVZYfmVGYF9EWWR5dTYKeioxKGh2NmJ7OSNCX3QqPSpHVmFuOEZtfHVRKW5eOWFeK2NZT3tB
Y35GTG80cENsSkEhTSN8Q2thdlZeNlAldHUmCnpiYkcwb1JsNzdFbXhmTCk7RUNWVD1jWW1udiRW
eUY2OzlDdiF8ZkVjaUpBbCEhcX5eUkhmZWNiZHRvYUEoRjQ8OQp6UTUwLTcyNXJTKHA4SiF7ZE9k
WHBteXZxP0p1K1Q0KXF9RS07NFd4ZVEoXlE1VUd1NTkqPGNtPSUhaH5TbVpJRVgKeng0XiluS3RE
bjZzVHVZb1N+TzxsJEc0Sk1qSkpHfHVMKVpEVTFJNylWK2V4aWw5IUpRKyF+cz96UyFeMGVWPWIx
CnpYQH1UYT5ucFU+OTtlNWpDYytDdSZvQ3NeKWt2bUY7Oy0wfT5Te0NDa2xsTmBGRkZfQDJKcVA/
TGgyS05LKWAobwp6N2R5SUd1aVZCYmV8ZSUqQTlIY1FII3JMQVZheFdgKSo+Z0pvbF5PTDRnR3pM
ZS1MUkZKJmxpMGM/a2AkQmZgUjkKeip0JllNMHc7eW01Uz08QWpIQlEpMX5UZWdYc0daLVR7MW0/
IVo8VyFiLTNfaHM3LUtlVm0kakQpKFhkenZFIWRWCnooUnsrVkd7Z1pyY1Y+e1B1QWR9Mm5oQUpu
YGVDZChMMClfJVptVndXJEl5diZLYWp1UWcyQmxnbDglSjB3NlAxLQp6dC1LeSNgbjNaSFp7Z19R
UnZOKzhKcHtjcWxsTjVtV1UqeEQwNiNOQnhXeyVYR3x7QTRITHghKCs3dVhFZD55UCgKelU9ZSQl
RFJGN2ZZbGwqLT5ofDBueyUyRldmdkZERzZAV3BFbWJaZ0ZwQW1hfD9RUXcxWWE3ZWZ6d2p4ZldK
OXZlCnpyNEwxUGFAPXxhczJMcVJIUmdLR00+PXhrd1ZKVnNOdyRtXk5oUV99czktaFFaM2VnYGtN
RmpPNlA9Um0tJn1tQwp6M2hsSzMzNy1kNHhoVzdfLS0lby1IWDd9eD9jIWQmSFplMX5HTXkldW5i
aEteN3JIKDwlS3JkUSNSRldUKjJhaWwKemtCcDltMi1EVypTTFY5YHE/aiFUO3U4YD15OFYlSmVR
eGw8N0IhfFZsbTc/enp9KDIwdmJqZWAkKSNuMHpgSkBpCnozJmFaNnY5STUjIV5HfEZ4cG9AUlFV
cUFfN18yeWo8emJDb1k9bmxIV0hMRSlHKyhBUmpMViNnNkk0O1lQUlMwewp6S2gtQWRgZVRiWks/
bk1MQUdtOCNjc0IqUzEpKy1fVzlAbkp3XnZoNWF9NTlgKUtiMzxkNmk7KDE+YThENGttU2UKejBY
TiZgWmlkS1RNdSp4SCRxbWY4ZWVmTy1GQ3o8K1R5XzJqOzc+PD1SUDFENjNAanlLeF8pQTI7JGdX
UGFxaThtCnolaH5BWT0lX1p+bjBoeXYkfExDRCZGI2U4eyF9Ym1fKVZzeHRYMSNDPU11bEk3S01e
WFUqOSZhUTJTME9kWkpXKwp6O0xZeFJoK2VGM1pPVXhnOGMrVzZzfT5hTTE2UXhWejVWMilEYXU/
ZHJWRHpaRkZDXl5wYTI7UEEpentnUmpCKzgKei1gYSU7YWheSlZWTCR6QmJZTmZyPWR9VzN6a1pU
OHd1RDVvM3ZCKGVoISY+TSNqOEJUPWh9Zm0pdDAzazdgRVRICnowaiNYV3lmcSUlZGNENTUqaWIp
dEt2cEZvQDQ7dzxtdEZYR3c0eSprRks5XkN5ZUYpPS13Xnw8RGFqR0V2MUdzKAp6NTRYYGpPZ3hr
cUZMclQ7OTBUeFBFdHtuc19ReiNwV0RvKl5CYlVHcSV1fUFXTitTbjAjR1RRelY3MFhINlI2R0MK
ejlJJjgpVX5KYlpnTF9DUFdURHhBbTZ3PEVVbitkcmFZT3BvO05hNiY+SVZBV3pZbDY/QWNxOSR5
Q0BSU25eUD87CnpMaDIqPEhjZi11ZW01a35JM20mMiFSKkA5WDZ+WjwqdkxwcCFlcEooKSUqdmAl
RjZSIW1wKDRyTXVka09NUmZMbwp6N0c3RmdpRm1WfFZsRWkpMnFvNz1JdFM5PFJyYjFFNGV1R3pi
YVRfbjhFVDg5ZWJjT2kzPEBvTi1geUAlMV5ncGwKem1IS3J6eVVld0c0ezQqeGlWPXIkdlh8ezsj
RjxeMnY+QGBQRUNwTCZRKCV9QFAmbzZEQzRGUEh7b2oxJkg4QCpRCnpzeVN4antCQyFiYSo+UnVq
XmxYOF9fTGptaXJ2NU8jb35YRntvblEyfDZMNkp8RD9yViNMfio/R0UkRU9wMSVWNgpQNDhoTDB7
OTFofj09Yzh2UGxlKC0KCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9y
ZXMvc3RlYW0vZWNsaXBzZV9oZXJvLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9oZXJvLnBu
ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwLi5hNWVkODBmYzE4NDY4NzEzMmFiZDY3MzcxY2Q3ODIxMDc3MGYxY2E1CkdJ
VCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAxOTQwNQp6Y21lSWFoZyp8cGAjKChVUStjY2tQaXZKVHRJ
QmRQc19ZVDRRYmxCPjRueiNBR05QO3EwVjBHRHRXX1FkUD1mNUcKek1MPEE2V0BIQTcwJTFrPTNJ
cWliQWRtbmRncGQmND4lUXN4ZCV4ZlI7NjA5Q2F+dk1JJWVCdCZJWH54bFVEdXNICnpgbytPfHxK
UjRWbVhlYSVaKiRAMiVUaUwoKE5hPWhgdX1AM189fT1xUSE0bntiTFdDSFIhVH55MV5WfHo4fEla
NAp6X0BqS3R4JDdaVUZnX3U7VXhVNCthNSRYSz9MYUBRPWRYOVhidWh1YDQzN0M+RFhBWiVZPH5Y
Zj5mT3g2aVNXIUIKemZoJDlaYjk4ZD1BRXc4WV9PX0VrTUBYO3hSfHpFblp8cn5jXllAcURfM01H
SW1GTmR2bTN5Zj11bEt5c3MhMlRhCnpFJjdOVFJmcWpNO1l8Q05oSChNPWJ9T0k/Tjw8WXNeNCRk
ZjhvX2FFSnc3e0lLMzNmP3FPUTB8RykhWXo8d359cQp6dyVGO2t2YnljVXNCVkUlUWcoTEpRNk1i
emNeeHFyQ2NFPH0peDckaj1yNEFqRlBAY3hSMFdAN2QlcE83PWpwbEgKenpkVXhIcURsWEJ7S3Fe
bjdYQVVuS2NWcGR1VGJ6XlFpaFAzey1VX31xLSQxbk5OOEFJTDRsRjBZZ1M9c2g/KSZeCnpmIzIy
QmxXbUYlMyk4OEBSO0h6PHd5JDtCKXQ/N0NNNWBadz08bTl0c2l8cWo/VXNsQi15aU9uWVc4QHpU
ZT5wcAp6KS1rclV3NFZOdHNTLSlrK1dLMGlWNEJ3NT9kPjBWKU5eYFRLSWVQZCRvcnBMVGliIys9
RUBhSyF0fH08bCZLPmQKej9Aem1aMHxlMWhmZTFBRXB4PCtmP2w/S0hKMSRfbmxGJktpJiMyUWp0
TVI5TDtFPW1iPi0mYSMpM1cyQCk8T3BRCnpUJGU2enNxc29sN2t2aldsM3JlJEh8OSZNdkhnMDUh
PXxLKnIteUhPNjx3bSk8el8jc3QrZzlNPnJMRzkwJEpuZAp6P08pRUwoUiFEMT49UW5aR3QpQ095
QW5MeGc2SE9YN3RRWWNLeFNaWjM7YyteSXIyYzV5VDN4QGswR2s+MV49T2EKenQ/KzZeRDM5cTxn
R0duQVJfSGwjPiRKPl8wKDxnSHY7N3gyLU1ecjV5TTQzZmkkbjhvNnV3TD9FPWJLWjZ7MVopCnpZ
K1FYQFNnMkBtRHpqMHdqWWw4M3UpYV5GR3JSWXxzRjVqMkhQS1QoSkZCQzdldHNYIzBiUDNRPCZC
ZDNgZyR7KQp6SzQqNCYtREswNnB2MENAX2FMNXFkY2c5SjUtV0NQS3RGVGV7ezRCY3VBVzg+VCt3
eClXSjxPeUgoU2l0PTVtKUoKejdKel9MLTxeYSFheDBAZCEqS1NvWWtseWJ3e0I7RWxTQHtvVkwo
cSFjOVpgQyRLS3I8TyoocX15VzNDVzNYSUszCnp0JmhzUDstMD1WSzklazFuSHpwKjxCcWJ0TndU
JGQtMFlgPi0wO1k/eUJjZ1BPRHIldDlCYiNgcGticXRgMUVOVQp6cF5lQUZTVD4kUThEY3RedT9t
JnApQT1Eb3pUcHU5aj1ES3lyOGtrVXA8TVZwUGxzTnZZU2o0b3BwY153Km5MdkIKelBSJVNyUjhk
fVVHfXkoY3M3KzExSUs4fjBBRSN7VmN+P0tTe0wjekZfUjQ5XlV7PzlBVEg/a1hqKFBBOHZUPSR3
Cnp4eXooT1Y5RmtedVlMcXlfS3Z7Knl3Nld+YVNETVFYNn5WV3JTenp1Ym1vPzl0LVVRYTNebnJt
TStpU3VURWBhegp6JkQ/I3dRbUEkPWpeQEJCbGpUc3xtRlphJikzO19aMSlBZ2RCYW56K3xHT0R7
PjNeNnlMITFvbl5qbSNsKVRDfFgKejVAS1Qqd3dAe081XkhDJVdFNT8tcmgwKlZtVjUoUlR2bUd5
aGo0VHxiaTEtdnU8PyU3TlllcXNtOzIhU29AYCV6CnpxdVp9RUB8P3dINFl6fGBSJlM5SkcxTmBg
XlRKX0kmKWJWO25WWFpsai1TYE90WSZrYGkhcFFFcUZ6dWE5LVkoLQp6OWA0PGg1REE8JENFZiRj
cUJYa3Q/dyl2U25fMTczM14kdFNHOChpODZVaklvamVeVUpNb1RfSWJqOGxqPUxOXlgKelhoQTQk
RCZVRWJtZTB4KkJPS1BnMC1AcjRSQkQlJClTYiFGdjduISNKfFAlNldKVXlQdmtwMT14JU9DfWFp
a1cxCnpMVWZzZEdkfSlVP2M4Tkc8V217ZWNHVHR6QHUkam89MUE5NzZqflpnYXIjPzBsJmcjPTtz
dFQ4cGgzNStrPmduQwp6U1pxVk8+OHJzbjVXRmwkNkEkPDZuS1pzOHc8fXEldmxzKytsVVVlUCZg
X29lODhTZz9wT2pSeWlLdk1rKnROWXoKelEwVz4+YVN1QVplQ1QrcT00SWtkK3lZKSFnVE1MTHIt
M0kmaUpOcnRZR0U2dmQjZmQ4JSorQEplKk1qdGthS25DCnp5SG5mfSt6SCMoc352dnNYJjNXSWVf
blc7Jl53U2JtYmkoUE1vdXRtRlpBOHxQUGpPISR6I2gtV05WJn04QW43PQp6NTg5a3FRdk1SNmk9
UUZUT2BVNkd7KzE8NzslP1gxM1JATWYlK0ZtUT5CcSU7YW1xRk9qVSZiMzxadkM1eGNlU0wKeklJ
XyNWXkx8VXJ4V1ZkU1JTNmlzOTA/MS1WMUFhbzVJKyRSKWlBXkBGbnF5fF54YzhQR3tRYHd7PD0h
S2B3SVROCnp4S1Q4NlBmVE5vZVZjKzcmeTQjKFRuQHZhPWM1ejVpJD51RDJwQDVgSj9lJkopb21X
OWpSTnRyWTc0UyQ3eD07aAp6JFgzUiNFMXRwKUU4Sns5YU5xZSQ0ZWh5TFh7aSN9ZVNmRzRLaEJu
UW0yRVo0ZFFUXiU8VjVCJGo+Wi1VeWZgUlkKemVyajUwO1F+c25HV05XTD88dHJ1UWZic1lmVU9N
M1FVSWZrP0lGZGxQd1VKcGJXc1FiPkQ1aGdsWF9COXMxMiNMCnp7V19DXypaPVVTd0BZXnNwK3I+
cS1YYiVuayE+NV5FRTBvdG47KXd9dXo3dUhAUz9oOTFiQEc5UDxIIVAxa05wMAp6P2YzJEpLIXM/
XjJYYTZEOUtNMUo0bH5UVHlIT2dzdSE0RVgzOFI1VS15RFRPPi1WdjlfWWpMZ1ZlaEtfUkQhWWIK
emMxNG4yMktnSWYxJkhMRWt3PE5ePCVuRjwzUU5uTkhufmM/X34jNF8kWEdvT0Fnc0o7amE7dHFU
Y3VJOVdCUnV7CnpJdWtGM01oJFhYa1QwOT8raF9UUmdHQVFqXk83WWBNcHYyVFVBJkolWSkjTDhG
dGtBKiRfeVR7LSFDcnFWNDZQRgp6XjliQjFXWU1eeGBua1VFdilidUtEaHtWa009VWZ2KmJwc19K
UThtI3h3aitRV1UyeXV6KSs3TSRWdCUjUXdBdkEKekY1LXJuTzMoVXVwaEk1NCQ+WEhXTzF6JDZJ
bmt5dTNMZzRfSyUzRnpaayU9S2F2PCp2VTRlJl5NNHZqI3k0eDZ7Cno3aSVzISRJQiV6Zm03KUI7
fHQyVTl9N195biFKcDJrSHVfakYxNV5KblhsaW9wJEhhelYrenhaYGU2VTEmTmZVcQp6RHIodTRZ
dCFafXIqM24mJjAwP29EfUJZemZydF8tV3Y2dUA9X3xzPit1TX4oaG9QKTx7VjFnOV5XUHojN0JE
cyQKeiVyVD16b3ghRHlMXmJ8YWoyQDFnJU9naXhvUm5DWThEYDI3YEx4eE5nejNLcj91S0F8aER2
YEVncUtYIVB2JElACnpINXclR3dgQHE4e2pfY2gxOUtAN0NFalcrLXg5dG5pYDF+cipCbSFFNEdD
JW90TjNtQkBWT0tnWmdRbipVJkRJcQp6KXJkTSRnbGVWMEdQIWx+SzJKMEFBa25nM0BKS3VaJTw0
cmJ3TGJ1YEJoX2dHZiQhTChjKC10P3NNJjY9Z1BeeiEKelM/NWRiXjdyOUp7VFM9MSR3VjVUbHQ/
Qkkkai08JDMxe190akFnKjYqTVlFPGQmRkdeTXkhO3tqZndlNGV5OXl2CnpgQEA9QDR+QW0tVlF4
Z2MybU9KOE0xJnpOIVdmTTZuLUl3YmUqLWJwd2VwSzNfb2tJdEEkN1B4SiZXdjtGPF5TeAp6Jkg9
czdYNHN1TldrQnE2VUo8dz5CNTt6P0VxNmEhR2cjfSk2JlJfLVNKa1E4VmcwQzgmJDkzPHpERGpE
MTRZTCoKekA9eFBNams8QDQjOTBaWTgtc3tJOyYoI2BPP1FBSj5Pb1BgTWFmX1F3Pj41PkJFWG0y
YUMtaCNLN2lTeGt7fn1kCnpKPFczZF5AaXdDNEVIfW9BbDM2MypuVz1ycSF9VmJzNGJsMGxWNjdN
UEJOI3Q/Ym1AdXgqeGgwI1dwfUFNITB4Vgp6KzxHNVpoNHVqSkpvaGV3T1J3azshYVJrXktVNWt5
TGohQGVmZjU4ITZHK3khMXRpO1VOZmZZJXdGMW5UekJVLX4KekBnaWluPGBiKlBRZXJeVlg1SU1a
ZFZieTJJPHYoMihYUHBHO15UUl9yWGAtLUl3SHdecXQoNk9aYkJSNnFtRmExCnpJX2VlP3YtXmNI
ITtPYTNzNTFNIUdOWkp0JmFOeSQhU0AtZG1ZLWc0OzJBNlRoMmBVeElUMSY7QSMlOEoxU1c/cwp6
eG9fX3tNRn00bzwlZGxoNno8IXY3SkpAQDh+IThVNnlick0jfXNAa2E7QW1JTCNMJT8xb1hjTGk9
OG9wQSVCdzIKelMwSythOHJOT3RVdFBRNllXY0BePVh8Jlh7YURvJjcpYUpXYE1laXA7QGRKdldZ
ejdQa1NTYnVzP2NhVG9ESVc2CnpHRykpbVh1ODNRK31JajN4X3M1bEVvMnN4YUNDZGltNipfRzlZ
QHw3a3AtTGxVPWNZdGQ3SGhUT0hJeFcpcjwjYQp6Tz9HKmE7UHBudmNmeSQjOUozT2k8M0YxVTdI
SXpaXlAhTDZge2FPVFVedUZEO3RoWXNFZU1HOFpiTExJRXRwQV4Kem9mIVJWJiE7TlpSd1BqVnFh
a2VPdWgqdVhDUjBeTExpeUNqbHNGMXJeRV4rc05tNHVEWGd2MXZAQD5KdHo7dFNHCnokSCYtQ3Jq
cWMzUXpLXykoemNDcHs/YmVWU052b2omNW5ITUJJeDl5NGt5PVpmNWM4UzNMQSRoWDBDJkFuWUxu
awp6NStoPFFKQ2dxcVRjVVVYYmk0anlOMjhlbzxPWUxyeWEtI21CRGdtbHYkfV5YZzM3OClIUHw4
bHY1WFd9MyhlJSoKejZSQCRBRF9FPj5aWWMtVXgwNDtHMDFsJU0rUUdqNUxUNT4ocXNAKXFuJn5J
RFBsI09vUktOT3U/I3x1PE5hU20jCnpGdD5EQG89Nmd9YCV6QUFXbVJNMkQ2OyFpczBHVH49VEVs
NWVaSlZ+QllEP31YfThhKSQtIzxDPGp6SHtiOUI5SAp6ZFQ7RipedSFPNEpYTzZQMj18MiN7NGkj
JGpTTXg0PXpVYD9jakx2aSpuZmtTVUxTP1NUIUZCZk8hamR0O2pQX0UKemA3Z3p+S3khNV5oVH1n
UDMzQGF5el5TaV9EJDtFe2ZmO1N1PjAqPU1qJGUqQCtTT0JhPm4hTnhRNEw0Xyp6PllWCnpKPDhv
SkhkNGhuVzx4WiFvRkh5MVExUntrOWglMSVIY3IoJG5rJkohTXpHJF4mOW9BMGxmPDcxPylGPlpt
X3MxcAp6e0dIKj9KYU8kYWRJc3BLTWNpWjMlRnRDQSR0cUtoQz1JbSZaa0gtMUw4PEJFT19sbWp7
UTNEO1N5KjVeYWpPLXMKekNnZU9NTT0wI1o4Kn07Z1d+PHB4YmxrNnN4QmlsI2dLNmN2eyZydjw/
NyV+dExPJUBaRHAoJmZ7MCk8JVZDPFg2CnpGYmlvMXZ6YmNheXFZSi1DQ1hJKjBMc1hBMm5QfU0j
Izt8d0pfQkM8PT1STG1hUTJ1KjNJeVZUWCtnfmBRIXZCeAp6ZUxJdWlaSy0qKFQyfl5jVkl0VlRa
PzlNaCQzOFZgWE1QS01Ud21KaHY1ezZCPW4lfFZGKl41SjAqRilVNUxfVksKenNfK31hYlkjQEhT
Rz9NJkNrQVdmakVjUGNxQG5nfTItdy13c01RWEkjQj1XJVlRaTxXY3JXMVJpOWJOPW5kNUxrCnor
Z0NNYGItOWZqdig5ITk2ZVJ0NkBsYE9tcEtIT1pZSFo/RCsqMyp5czN+ciZ7fTcrMzVrb3oyKiV7
dmxlMG0xVwp6O2srfSk8PklUbjdxKF5ENDNvQnZqNmQ3QWQwajBmM1h0Zj40I0ZiWE9nNEVzMHJ6
UjJralF9MlUwMjR1enQwNE0Kel8wQm40YGkhYj56MGFpO0JPNmRlUUBhY2dAOTJIKDA2Y2dQKmEq
OzJIQjA4VHhJb1pGR0U9TDAhdk0xVkZLMXlHCno5dVBPQElUaHF5cnIhTF9FdVN4cFR2fjNyN1Br
a3FLWUkkQnthLS00JDY2WWF7MGtQOWY9NjhrMUdnZDZXTGlSIwp6ZCEpSVpkVjlvNEhveWdWP1Eh
SSU9RX1lMlJeTXJENm5zODtOUXFjKm0+Oz4tSn5efT5vKSFrdm8zMTktcFBoMEMKemZsMXNnRHxE
eF4qdVJCVmctNk9hTSY3WTFSVUVrKyUleStFa2k+KWNDUTElTm84VilveyUjSyk/QDJfbGwhO2Y9
CnorJTJqSyZLLWImOztqTE5vPm5lN2tkZ01HbUVvekVDPil3d0lwaEVAbipeNnZjMCtAdnlvSyZA
dXlXIzJvRCQqPgp6eSZoPCFGJE5+QSk4U2ptZDs3MUhyfj9wWHNEYjg+TWMrVm5DY3p1fVdVMnok
RXo+SXFBU2pweCVPUTFMZDFxWDAKejA1OSViOHpiJCFzdnlVPnVrSHZtPTw/Mj5jWGM8PXJIOTk9
VVR2ViUhZiE2IyYxVkJ1emteaUsrZmp2SDZAPkNGCnolKFM+OHZ0bzM3d2YjfTliX1Q1SmopbXB2
Nit4bztFYkxSdGFnejE8eE4zaFc8ZXJPUmFDelVFWlZsaW1Kb3p1aAp6WDBgbmxxfkc2JTFSbkEo
Xi07VihyIWdkUml7T1R4RDROeFRqbm4lT1l8N2MzJllSTyp5VDxJVEUxbzNedXJNJiMKekpzeT9I
azM5cFhgfTBAQEU/QTVJYFJSUXlyPDUoc0IzaXUkUnRqPVQjNiZPSmAmLTU1ZXxNeCg7ejhxZWI2
QVo+Cnp6KzN2MV44Vyg2O1dmVlUqbDsrSjZvdiVOWiNIMyErZzI0NVp9a0hGdD1xP3VlYT9VZWs4
YiRERHx3REljfjhwXwp6eiQ/eEhTQFhZSW8/azJVIUVAX2BTcz9nY3cpZV9JPnF1UjlnRHc4OCVn
NkRZOCttbmV6Xld6fGRKeyEzJV5TZHsKeiZEVmRrLVEzLUM1fUswY1A8O3pkSDY9VFhkN3VQIXl2
RyFxKUJmPHJgQXJ2V05BOzFCaTQ1SyZpY0xie3Jwc09wCnppME95RWd8KnNhNyM1bzIxbjkyb0pO
fnQmRm5KJUBTPkp6ZChXSlVENnt1U29UaUdLR05kXzBFOSh4USFZMF5gYAp6aFVaRDY0LVluamhV
UWg2QWRAfWIzXmhYWHJqXmg+WWBUTDZrNk1gaFkoS2cjLUlkKEsweWlmMz1Kazw7cGVlZH4KenIj
a3RxYlV8TFh4Sk8tYmgkcEpQPT1kK0Y0b2w5MHE1UUF2NHIrPWM+K1B6KkYzVkF1SSVTNTw0Rkxs
YHRkNF9ECnooZHUoV1ZPcVlrK35lbUcwPkFqKT9LajYmRiFJU1A4UUwke2VzbkpNREwrWlAodns8
MG9YTUJHMUFxSEpQUUt8Ugp6KE9IeGtGaCVNODBSSDtNWFVCYSVfUF40Tm5DMVJlVT5MR3E8Izg2
WWN4Vj9ePEgyfElwbnVJSiVVYkBJQ3lCST4KellrJnMpN1ooRUchUCkxPU9+fWc0LSp6Mn0pZH5a
SFM7TkRTeWA/PERveGNFSmVlKkIkPGQ+VCtVX0YxI1Q9M3BvCnp8RmZrWiVPZ2otYiMqV3ZlQVIt
Z3xMVDhAWVFncURhVENgNj1aV3NaSmNqeGQzfkxfeWIhUjJUdG4zYSowckI9ewp6eEJtcWZhRV5x
YVktZjd7U0dvLTdlTjJaVilXQXYjbkNraihvX2JkYmFFSEREJGlDdSk4d3c0bkAlVyNabmNDPUQK
ejZTcDNuIyQwfVJqQVQzUHtNRy02dnBxNilAaXtuPHY1R2cxcz1PUV40RmRpfjh0d2ZeY3BGMmx3
dW5nUk41aGJrCnoqQDR0TEc4UDxaV2RjLVBuKDQ1QjUybTdMO1ZxfXVKRDErfWQoQFJvQnM4UCtq
Oyh9JCN9N0sjS2d1JSFMe0xyMAp6eHtzZHw9ST0+JiE7P1BCJk5kRW1UT2t7VmtJIVgxdGZ8XmpL
PlAwcVRQZ3A8aT0pXkNjVyN6K0Q/ezlKVTNDWmQKejVxSDxGX1pVZXUlRDtwfFlwMTtYN0k4V3ZH
SFRsVkd2QEozayExaDsoa2xicDF4UGRkem8mYkA3eUArMnBgJT5ICnorTHZFZVVoZUxgXzYxWj5j
YjxYR3h0bXVVRXZHYDF0NkB+RntDM0M9Q2ZeO3o/clM7fnh6Ujk8ZnJ9ZmQmSz5MVAp6Iz51TGZI
JihXVHRSQypuXzBYQUB6cUpZeyQ1QSpxSTtXWnZhP2BYQXZrbnJHa2B5QzxgZWdkQTVXRHY2I01I
Wj0KejM1TX07JTRYRys1ZkYtOGRQb290UFRtKUhjSztlVUNDZ19zNTJpNzBNPHd+a2cyeSlsTWg4
YXdmM3R5UnNNd2ktCno+Si1sPF9IS3k4RWV2STE7IUJWUyZCKWhiQU9GOE9FXj13KHA0fWlDc2RE
e2l2RmtGWUo0SFZuIXBITCteNik8Rwp6bkE3UjEkOzlqO1NnZXFiSipKeiNSWSVvRnBuaWxsQ2Nt
OEQkcSQ+V3kjeUFaUFR9fCYzVEU4OTxva281QHpAZEEKemNrJT9gKystJDM+fXQmNEg2RTZDcWZq
NHpfNCtwX1J3YHZjaC1BVyFAP0lOd2U/ZUtuR0g0UXtofk9ZMyhNXythCnpkY058bmlAJl9RSkQm
KXFHRGgjTEJqUT1udmd0UD4hRExJaiMmc3x8bVh6UEk8ZjJ8b0h1Vyt7cnd4U1p1U1NPawp6JExU
LTQ9Jm1+dnI0Nmp7aFRoTno2NSh8cHIyVyZHLWQtM2wyfFg3TEVVVHM7R2lBT0dGdWJCYWg1I01U
JSlAWkIKelVydVkkMVI1KV47OWUqYT9+V2d3RkI/b1ooV3RVX0FFWChBVVY0QWBZTG17bip0akFk
akN9Jnd3YTx5JkV+O0BFCno+TkBvejs0cGU/OGx1elduNEthK0kkdnx1c0JKeEslLXZ0Qz9aRFk/
azJgc3BYSG9kZiZiPk9CYHNYQyk2ekZAQQp6aWg7bkpLQ19NM0BGTVp6MGl1NyF4bGZYM2AhdFlX
bWwjWn4oP0Z7fDk3KzBBY2NxRHhgfjMkQldWS0Y5YlRUJiUKeiRobD5lYGRWWFM5dnFUaW5Db35e
SjBCSmcpYylsTFdWYlZrVD9iPnVwWTkxQW5eXzhnMSpgPmlrc2o8KTRkbVhFCnpwcjZwbCF6JlVC
bjdKRTx0JHJfO0U0cjQ/PTBoSHZZcWdBZT1RdjtmYipmX153IXtxWXF2NXZzR3c5bTBRP2RTUgp6
P05oTGRqPilrSm1IQHcxPFcqYENGYH57NGdwVTU4Y2g7Nz9Vc3A5QWFMTTA9TGkqeDFVMnklZD9T
Q25JcjdhQGYKekM1YHIwbXlTLUt6MlkpN217V2ptOCQkcjlJeGBQQCh0ZHFvPDVBQDdoRDF3VXFH
NXhxUjwqPmZvSl9hUylndD96CnpzNGM/KDd7a2dSTXx9TiV4QCN8KztaPlkzMUdAJUIocHFoVUot
NzNMWU10IWxQekIhOXpAN1J3QW8yQUJGd2hSWQp6b3FxcDw5YCpTYiRoXmwlN2ZIbEFVUn11NTZX
dUNAbFlhdVB1cig3Xjs9fSUmJE9TYFE/fTJVaU1FcW56cG5EdlUKemMqQ0RLdEVnTS0qPX1YSTxQ
WV9gYj1ueVlpaCUtJVNeT1R0VU92a0I5KzYoQVhuQUx8SXM4NTJMNm8+M2MqVjkoCnpsI1YjOU1M
anNOWXlTMEJVZ2pXVllpLXp6UlVhdkktVn04UjU2b3YxYVoqVipuYFA3KmBgbyMoPyE7aCYtXyYy
Pwp6Kl56ZilAY0AtP0A/cEdidVFpWDlNez9SWllBbkQlcEkzXmQ0T3hUPy1HSjVpY2NMYkhEWFI3
OEhtcFpyI2c2cEgKemNja0NpdFE0VUN2Pj9DU3NEQzVtJHUqcz5rSiF3eCg5PiFLXjM7fiU/ISky
KT9Dan1BP3hqNXZQZkZTPDJMTT8pCno0fS0laS1BMHFGZ1N5PTdAfCM3fjRZPWpjayloJXs0Zz1e
aDFjPT97XmwybEFfWEMjNE1hdGNodmA2WTY3KygjcQp6bUN9JClaITJuZHdWMXE4MytHT3FFMGpD
ZVdEKWRzVmo0MjM0Sj8jYG94eV9lSng3fFByN2g4K3BXbWQ2aG47Z1gKemR5fClAK0Z+MkFSOTh+
X0M7ckRBZ143Jk9LWUtZcnF3XmI9cktFUD0xcHJlRnNYP1VqK307OGtmQH0oaldRY3BkCnp7ZnRS
P2RFQEhwQlU9cGhvR1lQUT45RWBUKG8jdTdmQ294Qkx6JH1EdWV6aXg0ZH1mYT1FSmVNOTBWVEkl
Mz9aagp6dmZLZlVtPTlkKSNCbDBONVFBfHtuZisrXyNrbnB+ajFKVzxILVEkbjckN2hQT1p1aDUt
YVJpdVlwa0x+JHttLWQKenhxciNJNTkmUjB1YmJRU2lRaXVeYUFHaj4mUXtPYkhNNztjbGBaKyhU
e1U8JGZPfl9UNE9rX15hQG1XY1dMN3RgCnpRR2FJK0tqZllvQDg5JH5QMVRDQGt+RCtndD1rb00w
fjFEYm5CaEZ+VHY3KHYjR0BON3RqQXUxcW1TdDtJQ08mcgp6OEhgLSFaKlRuT3dfNVhWc2FxLTJm
Wk0kXzlfJmluP0R7VE5PbnJudk9SNH0kSzU5VkxaVHxXVktFajtSI0ZBVlEKeiojY0kmWUA8JHpx
UT0lbk8qfn1vP0BrWjE7PGglRldCZj1ubTh5OGBZbTB2N0JjUzMxSTY0a2EkSCRvYCh2JXFXCnpW
OEoob3U3eWxAUEpAWUREQmwzPEtsRDUkbCtUKmpDOHVWaW9VS2dWeTMhSm00RzFwIXREUUFoJWg4
bXlgO354Pwp6R1NNSXFtQis4TWQkP3w0c0laV0EheXctdyhpMm5CPk9IPCR8RHs1JnctJCsoaCF2
TjVZYXNIfXpNYkwwZV9DWVoKejVFZT43QzhnZlJfJmslZGwhWHZsaEUwR3c3RVY0NVNzVER6PzJh
Kjd2fiRXIXVsPSlLQzEpZ1k5Knx9XmtsZ3FfCnpUckI9WUg7VTR0dGtDWn0je3BZP3BBdTVtUylm
QSplUTBXJFZVRjt3RSp3ZnlhVXRGWUY/TzZKOV99VEtWd3R8Nwp6VkR6PHIhNzF2aSY5elNqdEx8
fTJacHB3JG4rRmxRZ2h1cyYyayR2b1g7KldeP0dJRCglNUs7dSV0KXg4PXo4ST0KekNwLWJPRWBQ
YVd2Vnt9QEp0c3lwcmMhWVFfbzttbFZJYGRDYlc3QigmZWxMOG9mbHY2bmJ3OWIkJiRucyFQS0lj
CnpnO15iV1hZa1JUIU09NXVYaD1rO3dNPnRsaEkwZiFCaWFjXmoxcDlnMm1kLTttKX1FTSEySn45
WUVjcDdHP2V2fQp6Oz5vV1N6azQqbjw2WihhWnU4QHZWPEM/aUsqM2ojaklAO3FnN2F0WVV1e1pS
amx6TEV2SlY+UGV1YWhSKkVRZ08KenV4dG4jRSk8QmZadEpoQSNOPCNQWlE5amFnTC1EbDQ2Yipz
eXx2YXImSmFma3hQPWVTTStEe28rezJLJERVP05uCnorSCNDMVJ5VyNfXj44dilJUTZrNyNJZmkm
TiZvVERaRXI4Nk9xWUVQVUxWLWQ/V31kbDVUODxtaHdAIWhDQXkkWgp6dVA+RiNtYWI4VVJUXkBm
WiNSMXc9QyQ0Qm03U15feiZaRWt2bT5kWTdLNTVKZDgwYWJhZHN4NEV6d2VDQjFieV4KejtrZGFI
bjFaI2wkeCZCTXtvWDtIK0QqdEhYKDIkIz9zemgoO2tGMHJ1bml9fWMmTitQPDEwMmBRLVlOb0Q+
PH0pCnoqbVBOcVhifC15OEw0PWk/R05WMkc9dSRtdSt+cH1FMjJtIys+ejFoe2ZQMkdVSytEN298
Kz1xSD92LUBucylxZgp6Y2YtREdzcWYtP0JFNEVscColRGJCNXczdHkmd3IqXmd5QTNpVD1KbGFB
ZH1udEIoR3s/bTBRTVUpeHJVQVQrZHAKem0+YDdyUHB3QnsjbjxEOChkcWFqdW00P054NT18byhD
S1dBRF4pOSk9REhAZnRxT1l5MGE/SVgoSTRRRHpWP0VtCnpndmVaU1pMRj1wLTVDWW1US0F+ZDww
Pn0lTmI3I2VOPXNXfHk4UyFnaXBePyVRLUU7dCNnbCZMTE55YTVCRT0tcwp6b009JWU3QCRGOVRN
WDl8WkB4WmdCWi0qdCpsaylEeWl+e1VKVmNiYzhDLUlNaXJQJl5UUlVNbSU5aVExWFRSMTsKemQ7
d0l1dnNGc31TYnhOWGhjMzlsJHU+VSQtRm0mZzM1VlRAYiQpcnZkYFp+TVd+ZjU0d2peNlZRSXsq
PGoqMURKCnpEV0BoVnJmMnZyUkRWMT85M25mKjRJRGBWay0qdyt4cCExSnste094Y19lQkA0JXB9
NWokWENuWkU7Pzh6M3MmIQp6QlY5a1M+eFNfIUM5X0xiV343Vml2ZEhXVVI/MDMoNWhzK3dYO2JJ
SSREN3dmdGArSGlQbyhJRkp1aVdkenV0c14Kem58NnliSSo2JUBRQGIrNG1AMHd3cmheeH5NP3Js
cSUtITNUb3ZHWlpEWGA0NkVeeUgycDFtSUM2ZWkwPSs/VnJ0CnpLOSk4a1dVI0BaRD5oZXpyT29z
aklzZ0RSP18zdkxvVC1zPzMjKj81VVUwViM3ekwxKT1ZSj1wdVFVcG1Te05OYQp6PVQzSFl7YHpR
bFFDOWZ5KUt8Nm5fXz1WI3dsRSZ6ZGBzb2cjSV4kS0YrKXtnPnJQdUtQP0g9Pkl+bFFpbTEtTjwK
ekd0fFRKajtFazRDU1F5ZWlxfTgyQHNmSjIwPjV0ajMpQnlfMFRhbSRLQCZyM1NCcnNlWjN8Yy12
VzRjZ1A0Xm1TCnowPFU9cDtqJWAocy0pNkxnKTtOZHI1Nz5zWXk7MDZ3bEVEbm5xI2A1T0A4Mloj
QkZGSWhwWVZkTjBlekBWeCZrPQp6ZD9EQik+QEBMNXZIJHRRbH1xeUF2QEFMd0pgY1RFUjZMZUl0
bEM8THEte1ApS1NYP3o3KGFYPUt7czxHMSp0O04KejBIc20tVUJgeDByUnZFQlBZLUxpQTtjZWw4
akpBd2kweW1TUG13KyQ3QHNIU0B3PnRDLX02RzRmPUhzdHtjPGNjCnoqKiZTfVYpZ01BTDY+TGNJ
YVBQWChIdjs5SGZEWkNuMDtuVl4tIVlHVDBsM3lRR3FtYlprcEBnK24mLVlHWlhoSAp6Y2o8ZEBm
RXw0Wm1UTV41WH15JXpycWZgN0dRJEo4WHlVUT9PJjFIWjNmKm50MnhsSiVrYFBDfkB1M15JJHZ6
NkEKell8YzY3Oy1NeEBUfTVJSFRUaHQjMntDR0IpU0spS0t5WFY1NCZCJX0/eUZmPWplOGJabVVH
S2o/MFVEc0R7NjNfCnpAbD81a3M2M2Y5KExkZSZfTyReVGpkcGtJQyN3Jnk/YUskbjk5Tk8zMCYt
Sk0pP0orfD1OazktTHBqa0dNKjNrTQp6XkltfGtPfEljNlZlclA0WD5PWVBfPVNZfSk7SzJlVk5V
MSQjRnA7Ykh7WV5mVEBBSnV7Tmx6UzhfMCNOWWxLVTkKemxDdnV+Zk5IdDZieWhhalEjJUpCSzYt
c2UrMj8hZkI2dnVnT05MKVdPdTkwVzdTKyhHY1I9ezBjYkJqO1ZhdyFGCnpqd3tGWldSaVYjWCtz
ZyhHdz1yYWwrfEZWVDshenRGJHBJLXQ5PWBINkIkPigxdlYxUj4zYHFGQ2FIMVZoP2d3dAp6V0Bu
djtkbFJtYFhYc0pGTl5pfT9tRkVncT1rQyNzIXAqU3tRVk1NUFR1WWVnb0VQK316JDs7KWU0MmB1
K2VXeWgKem5aeUNxUT56Pkk9JTw0OHYrYVM5KSRzTSlePVpTd0ktY0htU3FGUVErO0hvKUojKkpg
QENVfCZIazdnSFAtXkdJCnp2XjlednFGUmdsZTB7LUJZZDd2JVE3dVJvV3NBLV5QVjQqZkVCZ31F
KEI/Nl47UUFPOFE5MUZQJk9PQ1p6JiU2bwp6VTJMPShrR28mJmk3SVBQekphdXo9OG5lV3t5ZGR8
aUJzdGAodWB3Q3NNR1M4RV5UJmI+MzN8aXg/cGRiTjltJCsKemA+ZzlPJjBNWkNqYi13bEBvQ2V9
IW1gZFgtWSkwWHljbVNxWWRncUlRVXhKU1d+LUJZeCFJTnNARz8/RkBJbHxiCnpVfmFDcDNvPTJv
eiM3WDF1Y0BTJkNLVUx6b31QSDYlbEx9PzNub3ZzekR8VTcjdTQybjROP1FMNUN6ITx0ajZ1Jgp6
OSZKZ19jZD5NbmE1VysjPzNtdVUreV9ubzQ5eXFlMUp2YiFudF9OXzBvZzZ2WGRQb2FfOGw+WXZV
eWlCOyZOJGIKekdfQm0rNVJzMHRqfEduX2lzQE12KH5DKGp0YCZPdW0xeFJebHk+STE1XkFkfEVk
anRDcVNsNDl7K3JWblAhJHdUCnozcVF9QGR1ciV8IXV8eTVhdjBWeypCOWgraT5tcCloRWsmNmlR
NT9RUnQ8JFdiOCkyYkpWTTBPczAxfHt0PW5Oewp6bkkwbFR2ITg5SlUoRys8P0o3VStSTzBQdmpX
WmxGdCpwJWpPWShoQ0J9T1BlTH01MDluPkhNankmfEJkbH04NEoKejVaN3Q7aFd0OVArVndeI2ot
fWxDbDBmTSgpdFhnWGpwPXs8bV9wbjhheFlyMEFVQFc+MmtSQVJzPiZhSUk+PSZmCnplXiZ7MVdq
PnxIUEtVM0NfMzUyYyNjRT01PkNUMXUkLWJuY1kqWExESldgWGRIb0ZNQyVvTyZyPl8oQERIRl5q
YQp6UWMhVDJGaipae0FXWigybjNKbTk0VDlmYHlaQUYkYjs9QmkyRmRuMSRHbkdBQGtYJEwoQDFv
I3VuVzZ6X1V5TT4Kei1+NDtlK3Z1YWVFNDYoNDw8JlAlV3RXU3AjfiQ7cUhJQ2l6MyYzRWl6cklt
d0o1alJ0I00/anFgPDIlNy05SVApCnpxNGJ8R3k7UDZ2d0w2Xz1tei13OXErNVF4V09xfkpSfVdI
Kkt2YyNQV3c4WTJHP1B5YDtlP0dYOEwwYHchZTQqVQp6UTk3K3RIZk9td2pRZnwkK1pCTztDRilN
JmJQWlFDNVolTjR2PmVJPyU0VChXLUNwPTFuZVRpWWRpQ0w+Sj90OGgKenw1ZTZBSX44KmNtVlRV
X3RFMCphUyVEWDdCO21aZVQ1JVZUPDxLaUUqZkBWI3B4QCROaD5OMVA0QnNMSGRRfGpICnooTUU5
e2YyNUQ4ZWRiRDk4T2MzeWJWfkpjS3xzSm9LVU4mKi03Sjklcz1HWiFteT9jZj9QZ2BSVU5SfSlV
UzZBegp6STgoSkRpdXNKbUJiaVV1bXwkeFZTdXRaYmBoKiFES3M8Ul4hbnRBWCllKnUlQEwwMXxA
TWBsbl42cTlvSmxZVjYKemNxTm5OMjJXfVgoZUcrdk45bSlgO2xMY2N0Jl5mPGR9RntqYEwrMj88
XmJsZCMqbVJsXykwNHkpVHs9KnZkK3tSCnp0MnU+U3grVTV3MTZ5Uk5ofkpfNXhPd2tRRlVGPUsx
OUt9NV5GMWs3O3FWcElWOFB0Ul9fZ2Ayek0zSmUrbComMQp6PDJOZFB3SENRRzlSWSp4YSZ8eTxy
YG5NYTlBZjNFVllJTDNlY2U1SUMkaz8yTU1XfFQ4fSpmYVhedighS0lnYGgKendRaTRSPH1IPHNV
WWUpSlY0IT1ZWWBGR3tjNWB4PyZeK0tQTGY8NUt4P01LPUEhY307X0EkTHFPKiY5S0B3TzZ5Cno0
RDtgTnlzcXMkR0AwKEdnejcpQzBsQjlXVVJMSjlSKn1mZEtWYlc1O1puKmVnMj8tNGQmMHh2MHJh
aCR2OS1kRQp6ejI2ZFgqR2BQU3NZS1lEanJVZE1ZV3RiaUZzWDQlJmkmPXU8MHM4PlFmUSN5bEFe
KEhuPjdFRlhYKz9fYEFXdG8KemdIVTtUZiNJJHF6ZGxNR2E/P0BKOWNeSlNAOXZzdFFGemZjRz9l
cmJ2LXklYXtPKyFHOSUrNWlFfDI4VFVGP2R4CnpzRSNfUmJiRiMhNGBwZ3JRQyo+MFZpeHdZd2ky
TmJSKXl+R2kzQDRYPT5gaWFuIV9AS3J8N2QrMT8hKy1mSW9CYwp6RncoJkRuSXIjUzJZNDNgd0xn
SDcwekd7Vi0/dXxnLUAkYitebUdqTjhUOW5hemFhb1pwWGRNaVhGXzB4PShHUlcKejVRNCkkdXp7
QGJQbyUoQl8rUkFVOC1XS3FTMUg5ejhOfU1oZUZ+PWZSeHZYNnd3PXReRDJmaHlzRCEtfnB0TDRx
Cnp3KWtlQmlwOXxfay1eS3Qhc0dWIzNWbF5DandmQnJCYTtEdkhVOSkoYlFvVkNoJSR6S3tgITU3
RDh4UkcpWm53PQp6d35wX293bUl9MU94ZUVlVjdhdlJec3M/JWllUnxSSiFLUihuWn5CelQlKkRU
NlFifDVpTlhFYXhCZE8/TlNSU2cKemBQK1YmYVZ8a3BZU1g1ZXM3cVl3dj8wfUVTPERVYHJGZVdl
K2kwbUZhempQKFlkalktUiZ+N2lUMWlKRW1lYVo0CnppMmdAR00pcVZHQjJGMSRpWG8xaDErUDVh
dDlTR0xrQF5QNCZ9MV4wVV5XR31lY0RuYXIwRWdnSDNaVEteaz50bgp6TGZUZkYxJFh7b24kZ1Uo
Nlg5a344OEYwaTlHcVhKM29xcktON0Z3fHVnfEElSDlufi01QXZ7KF52MUxQbndRSGoKekQpTm49
bU5BKzY9KDFqQ2l5ZFhfYlQ8a25RZS0yU2NSNSNoKl5yMDZIfW1ufEV2cWM8ZFolKlQofHZHZzJ1
REM3CnomQzdqck58azxtelVAWXRLQXU9R0JqKXdjcSVEYHAhVnlpMll+OUZ9eWBya3QrQUBVRWFP
NlZ6SzFFfVhjK1VsMgp6X0cpXmZMeC1QKD4yV3krJTglJHchZyheUXRoamlCd2UzTGluKX49ZDZi
WXJTTXgrJDk/UUhJSCo2U1l8c35aankKejlmLUQkU0krWEkxTz5SNjJIaE80SDZzUzAwfj9veSUq
RXwzcWc5M0tgfWd6WjRTWWkhNVo9RHxfOEd9OXRSNkJRCnpITTNMcT5aV0VGciRoJGw0NGVONHV7
XmFham5LQU9Je240Mi1PVF4pSWRJeTBIQXI2bil2M0A+ek9ZU31VYCs3YQp6V2F7T0o/OHdZV1ZX
KFN5dURGZldQc1Q3eDROQmBKYj4+WVd4M2dWJVVZa1F9LUUrT1VTbypXJENhZ3Y1WTJnVCEKekht
fj5FeGwpNj95fHh9MCtsY0FPV0t9X0xaYTJjMFUmb3JReDBnSl9adz8rblNZVFdPVCQ/dVklMGZP
YzlFK1cxCnp2JCVEcXVeYXxMRl9XTGBFTF5yRTcheEpRPGtfO2FNTS1ZNT5+MVdweUt7U01qPX45
IVlMMXJGWmNhTnZ1RnxsWAp6NmxEdiVuNkp+RXQwVEJMMT4pUiZCSTYqRHZRbVBYeHYjUCozSkQ5
ZEBhd3VTaSUzT2I+SjZMLXN8JDlTIzs0RloKejtwPFZ2aHdBWTxSTTlxUG14ekQ+MCFsWTZPaXFH
dERlMlBmdHROcVkkSU5rPz57QChDdEdlOU1EVCQ7dFNzUjd6CnpFLTBmdXdlfDZ1P01Udm5aLXtz
RlY8KT1eSVhMaDZ6QzRAa042ZGNSKVRVd2ZMbUJ6PjE0IWN8SGhwd0BDUTttTwp6OXJsUHEhQjkh
K0xPUlAqS3NOI3xKeVE7czBBWVUxUX0yWlJNKCh8I1ZrMGdkSWFLTzh6UWs2RW9PPTw7bTFZbz8K
eiFAe1FLPWpQZzlFMSpNX1JFKWVrK3spemplQyYjZmJBKi1SMWE7Zktwfj59ekJ+WD98JWdNcko9
fHRVUFV1UGVNCnpOS3ZFeV83eEE/bVc1a2VqZyM+JnpFO01HS3pPelAoSEtgJlJKMEkqeGNVQ1NF
Tj4pR3dQNkVKb3tLfE4lYDdeOQp6XlAjaVIrR2h0RG5iX0ReKkRgWThjLWA+SSQhbiFeNWlgOHNT
RWpLO1g9bnJucUxRZih1ckVFeDQjdUM3VCszS0oKenNFPCN+T3BHJWxJdEVJSUpDbjc/KiY5cUl2
JFZkYnhUdDcjUD93O3RBe3Zmb3pDWWtfQXN9RmhSfDc1RmFqa3pHCnpkU2BqNnd3fEFpeD42WHoz
OGd6VnR0WXdnc2xAYCooJFgzb3RLSGt7ciY+RXh4UUpVI3NqaVd8QTU2Qllgcz9FYAp6ME9mKE0w
JENOfG9oV2wmPiVQUEsjfFdiSj9wYUtvYz94QkkpcWtTU1Y2VThaJERpbCtWen5xWDZQKDNuQl99
N2QKejhmZTNyWXcyUiY2fDBIRVc9bXBoPD81cChURFUhcyEwa0Z6TXhGV011ITN9JHBOb34xbTRL
PEJLaisrKmZpbUxxCnp2TT1nSWo9WnI7R3RYbmNFaUtpX0pzO1o8LXJ2KnhiVDJ3JkUxJGIpPUVL
VXliQy1yUDwxSG4zYj43fkpEQlVDJQp6dVAhKD43T144S1FDcT0lI3FMPiZaZChmdFRlXzNrSDhv
NE1eVU10RnBrYFN8I2NaY1FxXz8mLVpnZkEyJUxxZW0KenVDMDZvUWJnWn1VIVZVYUk8Myt0enEm
ZktZP3w0VkY8Y155R0xrcitOR2ZGJTVsKz1saVQ0Si02VXZGLW8jTSVMCnpiLUtGPW9rYVRGekMy
ckFUZ24hPTVNT29qWD8+dH5uKlojfD42TGNYRTNSQVAjUVN4MW49WmpDPkx5JHxGTDxffAp6aygz
ZUdiZW0kKWw1WEdeRUo5K3FMbkdaODB0b3xwXkg1cUQhcUlhbmxgVjRvPj8yM3krREskfmNlaVU5
YU9DTWIKelFfYmtDWCleUV5wSWErYE1HN3xBKmFgbHljVXpwMiRiZCE8N29hJX1xQ35ZX3lWcXpo
SnZDO1pCX2dSTj0kIXNnCnpSdUYrZXVuXjdEeWpubFZkOVVueEFfJE5ES1k+P20yXk4pK2ZlWUZD
a3RQRUUyOCEkaiFyTytfYSRhVHFQdWI/fQp6KDA8fTxmNmk3e1dsd2RMZStMa2BlYHM8aipSUSVK
a1AyfSFvP0VaJEx8ak5UIUhrOTFaWFImKjFfNCFBVCspZigKelc7V0otRV4lNiRPOXZ9RmB3MWRZ
ND5ENlhHcEE1OWhvb2pBKl9oQHtTOz8taSN6aFNHK3VKKT0tTXYpeW4hck5fCnpJQG1NUEJSXnF0
a2ZoQThnQEoqZ3E1UV9pTXlHWHZgc1JEWjVuTC1VK3VjKWohMG1Oek5KYn15dWAxMzBCenBCawp6
a3tWNXt2QXExTDFzYHE9YFk4VClDJjFhOFQ9JCV+eEh2V0h6P0ZQdllIbURkUjtsckF6K3s4VGtg
a3FIOHByQyUKellKM1g/ZzNRJCZCVURINTd3QTl3YEgpYEwpdE4lNkxTSjckTTZ+JmhzdG5aYG96
MEk3O0dTY0ZYJmVBfGxEeClpCnowJmVeSUYzYyl7WlI0RkU7TT1UYCs7fW4xeCZxOWlNdXElPFhF
ZkBsVEV+Zys0X3xlM29QfX17a3I4NFdYVVRhaAp6Y1FacGVGUXM4ZFVBVH0hTmUzQmdHMU1ReFVx
Wjlvdks/TW9HKCkzLVlpWD0/QWVgfXEhOExkemJDO3QtPFlufkoKejh3eWRMPSZmN1Z1OWRoQW1Y
cmdDZ3RPaG47WjBqNWV0SUc4OX47RXBXJG43JHc8ajRBNGxhMG5pOURPMjlgOXc8Cnp7fTgwVEFB
dkFra1MjdHgoZG40KylVLV5BUHNFOG9qTXBERFBTSjVxJm1hYyN1czRkeWtnKVYmaHRBcnZ0WW00
Rwp6aCN4S01SJEEjc3RWIzNESW5VOU5oRXV6d1chaGdRPE9jdD5OMFhfOSFRPG5NS21TK0YjQGdF
MkI0fCleLUxKZGMKelE8aTQ3eV96Kn54VzNUKU4+a18oZEVGMVhOe0VQdUhvdzBfYkl2IWFJbHNP
MjZNNUdpbEdjcmVWeyRJVzJ6U1puCnpsKypMNkhpY3puRypzekVXeTk9YU9WUnlkWlRJcXtJQz9t
bUpTPW9vKjxmKEZMdkokellsWUFFSCZndWpQOTtKawp6QEplSnJMTjNCI0MjSTlFV3JJNmdAemsk
cEJAKFgxTkopOFR2YVRIVHpQaWo9PHUzczlIQGxUd3VSWXF8VmA7PHsKenZycD09QnFzTzxHamU2
NjkqO0B1I3h1NT9HSn1UWCkzRG9fYSg0QCk8R25rUnkqSlA0dHJxJU9CdDNYP0Q4STUyCno4fUVz
X1ZhUElMWSZrZXN2WSptSkleVUBAZmEmaV90X31faCVHVEMzQWItOHBIPGFsclBtSnFjey1vTUJH
TGwrPwp6QX5PczU/OC1ZVWVecGlhYkMjQnJvYEwhJF5PM2MzVDhvVEFxR1VAezA3VTNrRiFDOCle
JHVUTFkzdUxwP0h4eWYKemxqXkEtO0cxQURzbm1DV3NYaGxRTDcpRkNIWERrNjZhbV9jb0xrbCg3
eytDPjhEKyRXYDtffmgpUHItMD12XnAjCnozPGVrP3h9cmh5KjtlbVBiTSE9JDV3WjhURT56V1g2
bU08NVVzRlhtRTwwUE4oM0Uxdlo4fldhe0xZV29kRmVvVwp6aGIyKyQ5XnA/QmBFfFZYPFB8dyhy
ZHBqPkJ3WnppQjE+b3AwVjZ7P2lhKHt9REg1PUFecEZVSV47NjVFX2plb20KemJQZiVAQ1Q8cExN
YXtqX3k1OF9jNCpLMnM4VGh6ZkRxYFNlWmt6KzdpTk0+YSRVfDVOaVpxP19EbDA0N1NRQiFOCnpq
Kmh+ZGwqU2B2UUx+VDJIK3QxOyhMRHFrbDh2PVc3RVV9bTl6NUpnPkIxMj04WEBrWUs1elg9Kmom
JVpOS2Ezdgp6bzhjU3wxXjhjX2omNk53ODV5YVE4Rm1rZm5LU1YpenN2PWxiVjRNUU1ZMWpOO1Bp
U0RobTVEeW1pMSZ0b09qI20KeklIMVNOU0hPPGJGa0Rsak5YZkZoN0xEdiY4X3JKQTk0QDZVKV5x
R2c0R1JZfl5NZ0QqRWpBMHwoZm9BSDlFMEkjCnoxcFBRdjxCSCZgbUZMNVhtZjtzMkVRTTgxNTFY
N2UhKlJNMntmMWBwI3s7US12ej1qUGxDe0pGcFQqUjJBdjJXVwp6S3pqUFVnfUw2PW0pbFpPZChU
NHVValNrLW01dD88N19wTGNAIXQ3JXJpTyFxZ1UpTjkkXz8qLT9MU2BBJFIyWjIKejZqV3F9RlUt
cHVkUjtkP25LaztjO2duX2xHJUt6Q1BTa01mb0B0RjRkU3dzd1pGIThRT3xwKUF5MGcpP0Y/KjtD
CnpOZzVhIW41amwqQ21scS1aZU9ZLSleJHB2Zjw7N0BjVmRDcFNRPX1scj1FS2UrJmk0I3I7LWVx
LW49JWZUVzE9RAp6TEo3N3pMRHE8I2MqUitRNmtQcnMobUshJmVsUXRqVE41fT1WeHVLTDRBYUM+
KkdpblQ1QE1keHJ3d0FCOHRXZnUKelJxNzNPYVlFKGYjJH4yPEdNMVRaPnx4I0VpUkRLNlg1fjFx
QmM7KENnWGZ7SEk2NVkmckVPU1NHYW5uZFcjXnF0CnpXQFFZIVhLPSsrbl81eEpfZHJTWCl+Xihy
MDdzZTVEaCM8Nil0SUM1NT9GbmI9ZnYlcWEqcWQ1PyFPNVRfTFp5Xwp6QypuUGlUWGdrPV5HNVMk
ZUhzNiopTHVgTDhsKkQtNmpveD1mNyN0PlNke0AwPWkoelhoe2ZpRDQhOCQ8UyooJigKeiMlOUlD
NmtkcklzQCF9XyNIVCZRPmJCRCNAT2FnSmx1NXFpdyt+TyZ7VGxRNCtZNHpKVighVX56YCUpMk9G
fk5xCnp1VE5FemAzV1MwJikqUUFHM35wQkA4U2RKPlU+dExXSjRORGk7Nm5EPD1vUylScSRIdzg9
RVFoJTwkejsoITYtPwp6X0FkXld2amJoP0c4T05Va0RweEdPVm9hUVQ3eXlLK3tmMjApdShhdnR0
V09DJSNscG9kVG0tNSkzMClZPktOYG4KektiPU9vYCloS15eKEpAZGwxNkdCeyEhcmJ3Z0NVWTl1
UX5zb2tEd1VaNXZYR3EmSCFIb1EjUSpKUStuKU9tNlg1Cno3VkoyQj9PcW5rektyUEU4WWBhP2xW
VDJuKD16R1p7b1NtSkN2R1d0UnVBPCthbjlZTGpjLX5XJlZLd1JXYC1sOwp6UH5STUIkdTx4aUQw
Y0doZGV1VHdHY1h7SylSdlQlQE5gPWc5en1ZST9BOVgmbGdWVGohKlk5RzV3WUAwNXhAM1EKekBs
O2V+UGlqTyZrMihKLUQ0JCR3SVM7d35ie3I1Xj5KZlpHJWJQMDlGOT5HU0ZwT3l0c0t7K2RgeFQ3
VithdGcpCnpkSippbWZVZFBPUF5VeE1fMkw3WWghVlBAPkV9UH01YzR5Y1ZYRmlGcWpsPGc1OXhO
cjZOOW1hPGlIKmYrJX17cQp6eH5VMV5Vd05uNFo+WXFjPFMqZjQpQDJrPGhzNUtCLUZRJiE7PEFk
Ym8oUHt5YUchbCk5aElhZUtWVzxlNlMxWG0Kem4qVERmYV8rP2s7aD9ING11b0V6NVJIWn15emFn
V1VeRjNZUDZPKW1fWl9XRD5CU0Yhe1A/RGBIZm4xI0ZTSndkCnpVQ3JnZm5Lc01YPDM8d153eWpU
PDZLJC1PNjd9LTRsWTNSSVhCVEwwaUF3PUFkYXIyRWtDR2p9bSZGYXJAOztkWQp6PClDUjxtN0ch
Qk1ENiR+PiEmJD9XU1FaN0s2RTdFR3RwTiVeWGJkZSZMKjEoWXd5MjRPQEhNOSVvSmY0eDxrVHAK
eklVb3F+RSpFLXJ5cmQjZEdjSCo+TD1MVXw5eUVRJDI/ZGM0Vk15NTEoKnVGVWghSktSbjZ1Um41
dTVNa2ZMSGdKCnohRHc5b0RsUjlJdUhzVHFVMlUqZWBURGFJcT18KjZ0VV9ne1h1Mih+Xk87UXxj
S2YmUihIYTc5V0ltMHYmMHQ2RQp6LS02dCRHJEZ8WlFvSiRaSy1Kfip3KjlffSZyPEE3cUVkSllN
dUE8Y24lQkl4dHtgVjZMTSptdDktUzl6PiZNaH4KemA2RGFLPn4hR2IrbjFOQUUlNz58MSQ/a3tC
IUZvYD9PdnckYHtoc0ooYDw+Z3AmX1IwYkJ5dUBQPVckeVBTanx9CnpUZGR6UTM8I3ZZZDB+Wko+
fX5WdnVCI3BgJDZBd1NtPyNYRD9jK2o8P01LaFYpa2hgUjE0IUtjXyNBP21La3lFZwp6TndYKEs1
e0cyPHE4Mn5adF9CZChvUTx+THZkZW9DPDRpVD12TWRuXz18KGQjTW0+dlQ8OVR3ZkIlb0xEX0hW
ViQKem00TnxjPEIqc21FfEhSUiY8XnlzNHx+X3lXPGJtNjNFMjVfTEJLJFg8ZmkkQHUwNkNnT1FU
Sy11VW1+dUNmOyRhCnpBeT8xRj5veXBkUTh4UDJZKX5rQyk3RWAxaFprV3E4U0wzKHZERFNEKHIw
TnlHVXU9TDMmcTF0JihfemAlMWJVTgp6UkxXampSYHpDSFU4JiEtKGk+QEl0fEVUdmJrNWV6dW9G
bz1uWWYtPjZaVXshZVVETVZ0cXhnQz0zcHFqcUVfOUIKenorfnwxPFdwdyZER2pBOzhIU1FzbjN2
QDkxTDNEd3ktSUkoYV9MSUVIWSZaKzBpbFlpN25jLSpaTGNYTXFCfnZPCno9MHImPyRWZ3VvQH1U
UiM/RWdfVC1DWmR2Rjc5NF9wPDAxdSNwd3NvfEEtXnBSYSpzJnhKdXE7Nk5FKGY0UyF8Vgp6JkZr
bHRnS3UzPGRoSlRxTiRSTkZyazlrS19JeH5JKSVPZUk1NU9xNU45aCZnQ2RJfFkqIUphYj1LQmpZ
cGp+N1QKejlWNCpOdlJQZXdtfHdORU4mWCNJQFNANCR6VnY8dmtmMDM+amN8eWc7RDJvKzYremt8
U1Z5byZjNWR8SFczdmtZCnpwbjwzSGtyYV43UU1tRTJ1clF5YyZDclAoeXRLeCRgSnNgM2FXWjsq
OWwtXn5mSzxmVW9scFJlUXFrRjt6V0U1Zwp6NntgKn1DPEc2QFBoc312I3BoTDVTQ2gjZ0F4U21E
S1djPEo5e2IoOzREPVc5YFJBJHVIcDQlK0UzZ148eHVKczEKZkBQRTt6b1J9RFNPenZWJVR1ZHto
eHk/QztwRyhocntQekM8TERJczsKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBh
L2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9pY29uLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9p
Y29uLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwLi5hMTM1YzU0ZTE0OWVhYTkwYjYxMGE2OWM4ZjliZjZkZWIwNmMw
ZTY3CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAxNTgyNQp6Y21YOV9XbXNFSCgrPShxTVRAKDt5
Rj45KCtAKk1ONFVpeCQ0I25MSTZmZkBYI2k2Km55SWM3M3l4KlRCQylifGMKeipfbkgwWEdiRDUp
RCRwS05sKmEqMEVVdkh0UUcoTzFOe2pES3RfYXE4TSohYjNJSz91RGFsR3tgKCZNVV8rfVheCnpf
P0VuRCZrMT4tN2BJdUNxITVsb3dYWTJHQmQhcHdJUCNtRjY0ZkUjQjY1ZDE7aW1uO0FkJiVkQ2FR
bnZyR0BFQAp6cWViVGxsXm55UjxUOHNVYmN8LUpQR0IycFY9Wm1DXkx1YkZUaT44S1NUKl9ldCNh
LTc5QyZoZFV7Slp6V2F1cmwKejtvTmFJWnxFRX12fiVTbk4qKl9+VkBMSCpNSXkqZjl3dk5QTUZN
TSpPdHV1cW0taF9lQTNoPnc5PH4lK3VIRnV4CnpQe3cxKDRjUW1vIWlEN1VASTNyN2wmYjAkZCUk
c1Y8fko+WTRnV2dvQyt5WTczdSZVemU8eWQ/ITtWWH1iWndwfAp6Xk02ZExQaXpAeUpVezFfU0Zp
QklTVUprflBFMSpJNkU5M3A8NWNSYDYoaiFaUlVzTzM2XiZvejgpO3p0WnlydTAKejREJChPRGNP
SCVJUDNpOTB6cCk8K2w/MGlDeCZSPi1zamZKejBRXmNsdn1qTHN8LXE2JVhMXmo/SiVDI3h+QDg5
CnoqR0RPYUQ+ODxzeDlEIUNTMjhCYWxgMWszNUxaVWhCT35Ad2tgMz9rYmhKcFgldURCQXpWPzFj
JVcxeHhpNHk0QQp6Vns9fm03JURYfj15aDduYDNvbWwlVSYoNSQ1ODtfaTY+QisrMlNqRXRMJWB+
QEg4MkNUfnt0cDBsS0FvM3dTJWcKeiNLTyFyRjRmam14YnAqJjRKYEB8M2lVK0Qkald+TUFQPXdk
KmlVTG89RjgqZkN5fSgrNi1edE0yWkplKmskS1dCCnojQioydlAwdX1QT3QkQkVtUSlKdVJIK0J2
Q3VZYGo1eENPeXtCQStuLUtTK3ZZYW0+ODxPMl5YVUkzREcxVyVVVgp6NTUrK0Jfb1hFUTltVVFF
SWlIalZ3JHRZZip6bnxWPF8oTj9Wc3IoK0QraGtfUzJKdHUpUntjfU1ZVWAtZnJWVXYKeiF3YTQj
dXx6aX5OKk1pbTsmZ1R2SCloRUQ5KmRfZ3hIU1pOQCY+dSpeMHpYb1FNUjEoKjZ9aiV0O2tPTSlV
aXNrCnpyfCE3dExSTntyLTtRSFh5ZDc1e0tlbzJFX356YHQkWjNZd3ZFI0k5c1dJe0tFQWd6REIk
bClnSWlSYzJhdj9iSgp6bmlLc1QtIzxKKF80azxHcmpyblVGS0Jwd0UtYChiNEooX28tPzcxezgk
PHBZcjhrSVREcURMMlR6SUtre1MpfXMKel9WUkdyUWZ0SX5WQmYmM2JwMihDaXt7MUE3bV9uQ3VT
a1B7ISkzdDRvekQ3bkZZVk01akw/K2hjMElFM2M+VnRICnpBZmNsP0gjOzsqTFgoQzhZYWdsKnVE
RWFQe1FoPnJ8ODRPVyhrVFhIWEhGZ01jTk52U180fUd6SHNtZmptQGI3NAp6emwoPE9maT47bkJ2
R2dHYEsyMGtMaD01RVgkfjFoelVuUkFmKiEtbkRrcGRIO0hpVWohfGx5N1A3ST5aPTZ4M0UKelRC
X1lFI0d1U2xMUFdSQDZtXmU/dytvJihYbFE4UWFfKUozbmFeP15lMUFSd0o/KHE1Pn5ZaTViNlE2
OXJzSmp7CnpXXncmYzR8dkBuZF81LWdoUXd2Qkc/fEpTdjJKSktSV0B1WTBNKl5NdmZPUGVKJUs9
eHM4bmBIKyRXQmYrdTdXdwp6bzVePjJXOTYpUCtmN14yPyYwNFkpVyomfWNQQTNCeDNsVlJTNXdf
KVJJISVSMXxrVmhAazZyfWYoSTMtITVXXlAKei1kfVdieyM8fEJjcFFtP1I0QTBmZTVFODIlc31N
aUpfZytlUDt7UV5kUDl5bXl3NFlYeV42Rz8/NXZadUF9KCEyCnoqfHg3I1hpQiRiYHk9clpDbEI9
TmVXcFZRUDJIfS0tZH4qfCROVWEpLSp7Yz4oWXBhVXZjMDR4RkYpZUcxek9Bdwp6QXc0NnglP3Ao
YCtgSWQkbXMzdiYrMF5xSnVkVXNFUnVrSig/fFNSSWZUVXxOUV9xY2dOQ1h2ZlAwb1lnbytkJG8K
elc2MnlIdWZSQyorZTRmQykxeSVvIU9EaTdzRXlmSCM+eGlRJkZBTjVaWSt1ME9QZWFjay1lcj53
XjI0MCNlUnZpCno9ZDVwNiNORiQhKTlOTjNDIXA3WmcobHw8Rn1fR0BpRFJKWDN2fUk3NnJRZ21H
anljWUs2Zmt8dH5aMz1JdGtPKQp6NzByYUBlbThLUGkjZFo5SlJqRUdGTGI+eG1pWjxsXnchYyZm
VEI0OEY1NEE0JWRDMyFFfGJlcV5QTWomP35pdk4Kel9qeHIjSDhXdiFOdG5PekxCSksjamFPNmgq
S3MofCVFa3NeWjw9aUcmYHZyJlBFQn1Qal89S31PfHtzMiEyNXk3CnojJmJyQGotNVZMbm13RWI3
YDFPfCZGMmlgMCgxJVMxY2BCU2c2OXFKWkY0c3RkQHhtKGNZN247VGclJUZDeGptPQp6QnA/JTVv
ZSNSMl9eS0BeRCVKXjdGdzV8UjlZPVF5VUN3SzdDIU1AZ3gjMUtYZnBHX1VOKH18Y15XWEE3O0lN
aEkKeipIaSUkVkJicCFyQXpkTW5uJUElNXNhOzZiaWZJUWJLcFdONjhaQjxQZiViPE93S1c9Wl53
P1ZvPEV9fTI8Qm4pCno/RjkxN0NlVklsSlYtUmskX29oVD9MNWY3MnooMjlzQz5FWj9ncX4rS2Qk
K2FQc1NKNCYpYmBzTnNfbC1ebClfagp6SHYmI3NSZSNfVmhxUE4mVkNAJFNhQ1ljaD4qYSM/YHBx
NHJ2cn5vUzkoVjs1e1R3bzVGdVR5aTs2OW9DO1F2K30KejdqUGB5ejIyez9QX2FRblA+USV9Pzdo
fS0rU1BSLSkzeTVDaSZpZXpafVRGU1cwI2otWTBWUDVecVM1QUlrTUlACnpfTUdGN3twMHdrMnhZ
amtZJWh6YyttbTswO0J7JHZwPHUxRC00NUViU2s5M282KldJSHRiNEIjIXxVI1dfdURtdwp6LU97
Q2JIOURDUmE9d2IkRG5Abk5KPFgpVmB8STRAQDB7M0lsVU1TfFRTfl83NWUyT1FUVGc3Jm9tJnxX
NSpFPn0KeldJZDlCJjRfdDA1N1N0SWtGX3l6JmQ7X2orSFE4ZilsaCtjdClGa3pXXlJjZzYkbSgw
aGRpcFlCZG5eMW1HMVNxCnojdHltfldeKUtWMWRFdlpLKSY8OXlWQXg4aUlHb0VPWDd+Um5idkdp
dz1KeF9YY2hnXypieGM0Yl9uaSFFY3Q+Qgp6ZX53V2RjJjZaZXpVdWpkekB9ay01RDVaKEw1OFUp
K3VkdG5CSE5+WWk/OH02OUEjfEMkJm9aVTctPjh8Y0EzTl8Kejd0K3IjRk1qdUxtViNCNlMqXiQr
a1VafC1rYyFxSldLVmZPPn44bi1gYEtyVG13IT07SSZoZHV2dGVZN1FIcVpACnpoOUtYWSYyQlNz
RzAxVEIxNWxKRkxgISlEYFY2X3gtU0RhbEN2JWVwRi1uKkxVUTl2biM/RmcxbEBIMFRfelcwZwp6
dWFfNUJWPz9PZCtsKmMhamR6e0xZWnZ8eEMqVFdMPGg0KnRlcHAtSD5vSk1AJVImbUs0XmZaOTgk
MFBBWjdZbFAKeiRpQlhYI1FEcTB5M3V8UDNXKiVVOFVYQm02bzghSDBsbl9CRkFfbz97VHAoSmN0
a2tvZyUrQWhGNjF1IVokenFTCnpSQl8xMHUqam9mYzsoK3VpKEBqeUhKRFJoNTF+dFEqVXhKKUM7
TXppRm87dTk+dG9LcVYtNW0leUk8Q3lhJip5ZQp6QTk2MSRAY3VXOUtlfHJzYFE+P2BeQ0o3Zzdh
OzxNT2spR2Q1fStuS1c9WUU1LWUkeUo3QGFkK0h6ckN4KzBSJkwKeisreV9nP0ZZc01adX10M3Vh
YFlac0Ywc2JiME0hOG95S2p8O1g2Y29yMmFtbGIrYHpedjZsQ3o+ajQ5JXtgWE5PCnp1R3BJMEZz
VSNOXlEpZWRWZ2YxM2QjdVgoUzZme31KY2dRIyl9dXZrPWRvPVVmclReQW55eFFjdT1JUVluNClm
ZAp6aG4wbUtVJnpWdjlyRm16bil2JnspdEY5X15xZjZrcXd+dFd1KzE0XmwyKCFTQz8yWiElO25+
KzlwY3M3MT9ZV3cKelliKmJBSFhne0xkV2gjYGRQMGJwb1pSRmxOYUQ1SWZOMVZJNmY1VkhSM0lf
KlUwdGxePkRhIWdFSjxmSlAlVjlFCnpONjBObnJfckZZdFIhZGttODZKSTtOcVlManwzZGZtfmJp
NFd3Vmc7WC04MTQ0LV99VnYhYmI3JHs0dj09bClQTQp6dX1uNml5ZExfVEpwfllkSjVweD58SWgh
Mz5Lb3VtPSNgKj1LK2gtbXYjZGcxQmhqMHYrXyFDSnFQYmdmdGdPUnsKek95XkYwN300azlLOTE0
X2ArVmhQPj0pJGpvcGUmaHFOTVdxPDgtOFh1fWZVJiZ+Kzk1dk0zYUV4Vk5faGN9QDZQCno1Nipu
Mygob0pNJms+KVZoKWx2R1Z0TnRlYWxPWUNIZ2dJSmROZWtDKmpvd2s2P0kxfk5AfD92N1VjQnRB
eyMpVQp6QUF3VjBLNk03WXRWRVMxQUtUbG9KemhmTDwtcThgbWFPYn4qVks3ZWA4YHEwbUlCViE+
YyNuZWF6JUhwKDJyRjcKejI/YGpjQiZ+bWkyMUNec2s5U0goOHhKQCl2ZExpN0ptPC0oIzZtX2Ij
PVpWKGZSQ3M8IyY8M0ROUTtnXz87KW1jCnpqeEBASSstN198c1RMejRfRV5eOGQ7eVolRjtSPjwz
V3NORVNaWEV5LSZZNHh1ZG1gPW1TZWQmYHE3KD9SLU8kOwp6IXQ4Y09iciYtOSt5RnZFc3ZAbDtx
NjdiezRJQGRXV1c2Pm0lMyE9NntVfj0jaG1aNGc0OWNYMSh9UWAqKHN0dnIKejRhVV5MO2hSfTlT
KVZ7KmEpM2ZVMUJZbFgjPiMxQlV6KVQlSnNZTX09RnduRSVHbTd5b3R0fXAwREB3TjM2X2NmCnpg
Uyh3PHtrbmgmWTIyUTJ0RUxwPjNFPWBrPmMkVjI9dSQpcDw5bW40PWZ4IyRpQihuWCFwa0N1PVpB
VFBsYCshZAp6PlcxdEp7OWB7K2RpJHx3SGpMd0YzSyRFRkR6KGFWaD9yQXxtQCM9b2pqVVgzZStD
Nz8rfX5ucFJPKnh9YUdDb0UKekR0eipaTU8wPkBxdC01KUU3QkM+UnhZKW9DQmoyZnhqKFlyVkxi
bDhrYXNCcHUhK3taX2AtfWFPNlBqI214TF5pCnpFUTkoVG1Wd00mYlRwTkh1aTFLM0ZtUT5oQkNR
TEkmO3BDYjxMayNRYlBhcHdtaX05LSRlQHkyZ1NuPX0kU1RqXgp6U0dBNWNYVzNgR1BhcEhFMjxY
dkFaMGJETl47SHl4bCZwQSZTJVotVTQ7Vmp1VERANiRYK0ZzVEJLTDctb0E2ZlEKemdGNDFBbFct
WHAxPHpzS0I8KEh+cUl0amB7V2hifGNUMD1RPl49RmZzR0hJRypoJXgwKHZFQyVlamhjYnJxP0hx
Cno3Oz1WPmNYWnQ1QmcqeWF1NjwoZEYwQXckQ0cqZUNuJklFeig4YiU1UlllLXo1QUYjVW57NX59
IT05SjQkZ0IqbAp6KUE5e3NUSSp5ZGE3RHRSJHZEZSNvMkR9fk5UdT0ycUtoPmNyKUs5PSl4OERL
NGtpeTRfZVBvSyVGKlprPyRTb2QKem83V0g4WDNIfSReVDloS0BgTzwkeU9NY1ZufDZ0I0M2U09n
YkRHMmREUXl5e3BZVkVRPktAQldsNGVOYD89JWBACnpOP1RZT0soTlVrfDE+RVk2e1RqfWNPezBW
aGkhIXRYPztsZyF6Un5lPS16M3leOXx2QTxxMDxLez47cXlveE8yawp6XmpgJStPJipfWjs9fkBv
RzcmbHEldWVGPjgySjJmdmpINTFsKXY0OHcmKGxKM09GKFlCKnI0LVY2YXdZI3Z8ZyQKejRROVI0
dz9TOyU4Mk9PdmgoMk9UeCtrKWc+Nkh+eXdPY1I+MjR5c0xPayNLRCE/WVlyakZ2e31MaDFhOGhx
dVJOCnohbVFkMzBZfmY0KU5FSiZBQDR+Qi1POWRMdkNIQXZ7PGl4K3pMVl9WUi1Wekp7P0syc0h4
WnZJUUNUYVJEVSFzPAp6S2lLZWd5O1dURjAyLT43LS1gP2Q9Sk43UGx0ZiZTQlJYKGQkUEkhOF4x
Um58YDYkUUBSRigrYExGKGs+Vih8U2YKem9ZNGcreTRVbyk7RG00LXMkMkojIWpOZWFvUDUzViVg
RDN+dUYpMzF2bmIhUURBVjJ5T1AheWteQVV9PTE+fVpkCnpxKG9tPSVwfCVGMTUkRiZlUjQjK29V
RE9HJE8rTVppN1E3a00xd2JSaXg/dCRYfFB3ciYwU215OX5XKFZCUSM9Owp6d0Z6dV9eU1BgLWVv
aGg5Jm1iQWEtalhvfGhsZ3Fzays7TUFsMVJ5VjZkOEhXS04jalJ1I19XV08rfjVTRjJLe2gKeiom
blVtUDlgKU9ldzlZQGFeT2dBQmJVNnhwcWVBV3g7QCkkVGdsbERHdDlOUChWeiZZO2VgMjRETz5t
X1ZkQlprCno+dWlsQWY8Jjxwaj9eLVZubCNpKFJXWGxHWHxUYEtfT28oRUN0Kl9RIVU+Kyotb3Ba
KCVrRi08TEcrQVpYcG5NeAp6SkVxVF97PXJwanh5aV8kT3xBbEU8bG97RlZ4TjhTPHh4Kjx2WVdh
ISE+MXZlZ2AzMW1fME1IcnJiLVY5UCNNXlgKencrQENHPH5aUlBxKzNpMTN5IVQrZSMjQGp7M1kj
NGEtK219a3l8WlB3MWtLbFJwSjc0YXwxQ2lJYDsze0ExbURSCnozYCFtczwmUCZGaV58Q2hnRENG
QWhmP3speVIkX2EmNzQmRCRFST5kYzVGaiQtMz1LcmN4K2A2XjB7X0hxNkxCcgp6IXYoO0ZWQ3Rp
NHkkST84endGZCg0e2kjZEd0YyhaLWwjbUNsRT8xQ2Y0TksySy1TJDVAY1pmPUVhPEtPP2JVSW0K
ekU/bj9oM2VnRSY/Vz9KZTFPYWF9V2kzfkgxQzlKb0V8QEBqJkpHe0F3NkQ9eHttMyRWeEZ4ciZ5
RTRfakFEI1VOCnokfDtlVkI8fHRvUjN7VGs9aDlRaFp4cFFzSz0rRnN7cyY3I0hTPTEtUis/YWZv
PD1ZdDJfRkxuJjJSP1RLYUZsYAp6RnRlTD8zJlNrS0h1fH5taj5NX3BAZ21ofDtIOWM5Q30oZC0x
OStAbzdVJEg5ZmoqbCEkd0xKMWU7bldURz11bFIKenFnVk04aV5tcXYlK1JCPiFXPHE3JTUmQnlO
P0htbDRQX3Vybm5nUXwzWS1DeHF3c047JENDMGxOVmI0MDxkYlJTCno4SExxalZfU2AoSD9GTyFF
Pkp7YjxzTG0oJmx7PDA/Rzg0YlFwUyl6ajl7VTVuPDdlQ0twP3IwI0ZPK2h2YiZZYQp6cm03azA2
KFoqVnl6PUxJOTNkOX09TEZxcmgoS3FBJU40QmhpMnpsY0xgMD53LTZTRjdPODklPXlWTDkza0Ml
dm4Kej43MD8wVWd1NkJOUEt9dHt7KiktJVYlVnMtTSRMYj4+TyQrVkt9SllYQ2ZnNiQjbyhKSHhr
dHlAbzEqTDFiMTgxCnplTkFne0RfK350MSNLTjZOTTZuZDBiTVEwS3lPRFghbWxJRHZxPld6ck42
az83I0FHPVJUaGFRLW4wWlVuTW9qUwp6dmNPPWZhQVdkR0wkciF8TVJhbVVZfVRLRjlAWUEpUGFf
OHxTa0FKXykrK1NCWG9mRmlSSXpVSVVxRGl6TkBZWCgKenhTSzVxUmxZVloyRDs5dGRUWTFjO0hl
QUFSZ1JhMSVVd2lEQUZNP1JST311YHhkREE/N1hQajdeMmFgYkVgcWthCnpzT2A3Ny1yfEVsNkE5
eUFZYkxJUzleU0lMUnhiXnUzKz5RJiM4KUwkTmEmbWZ7MEw0Rz01VmBCT1ltRilafEJ+cQp6bis7
dFF3Q05YRTFEK30wXiYkNmozK192I0NKTCZvUzBCNSs2TTkqfHNUJEljPUdjR1ZjKTMlNUpofnhl
dmJ4VEAKekVRSHxhZnQ4SmhnY1lFNC1lPEdpWiVKTitPflIxVDJoRWBPXkchSU9ZJmtnbHUjfExl
P2BiMDx4cGV1JEE1cnhGCnokY1V4dit3VGNuY1JSckhIRzl4bXVLUjlQYnh9UlRCJE5NcGctRGxV
bVZCUjZvV24pWTJUbCtqdyYqQyUtbCljbQp6ODF5ZFVZOyNwYXNJfUF5PWU8Iz0qckg1RSlFYXtS
YUpEe3koZSo0b05xfVRLeGdVe0BeOzhsZlooe2JfcT0rVncKemhJN3phS3dQbU1oS3lSQz5BOFRw
K1NzNFd3Ql9wSXU9JnU0KnwyZkA5RWN1YVZOck81JC1QPSppNiNJIWVzUWMkCnp2N05OKWNxfmFE
OVE/aUlfeClaYVJeIURsRDVSKDlNSTFnRngrQmtUZzhRPE50P35Fb19oXiYoKlFYeT1KS2B2Nwp6
PXlhdyZldG9wUWFCdHNBLTYoOSpEUHxrP3h1VCM7WG1efl5yRTs1WnN1TXdtNTx3ZEBmMjs3TiVH
M2BRXmRSRVEKeiZ+JmQtSHJXQXdJViVqdXZqe3lgTm9uKWB3bF5wZUM8KVJvRz9VSWYlN3VFKjZ9
c1dzKj87YUBaMTl9e05LJCNjCnowZTg/JSlGIStLb01vY1M9U1ZxP0hmcTBgNXFLYUhsUGA5Smti
ZGo+WmFqelQlSzsmbGlON1Qhcz96LTxqPVJYUQp6NCMxU20hLXZ6MVZJZ0VjeFR4KzdUSyNUPWNY
eklnODtGP3w5THo2ak8wdiE3NEZOa1BRIyVDX3pOO2pyZmkwVkwKemRMbk49YUg2YU8/bjUqcV45
OHBucy1GRCFBe1M8I1cqWXY1e2l4fmsjanA3PTlWeUI1cWNENzw8Nzh0PXVzUVJkCnphJWFAZjFf
a3hJWFJLRG9Ab1o0eUNXYVlxeV9VQSkqdEltMFh+IVZ9Pm82Zj4qUG85LXNPJWJrKmtWbEpGIXVw
Mwp6K0xBP0BCdDhNQDQrYlBnSEkjOWQoeEM2Jnp+RjVIVlBvQGFgY3o8UTFmYHVHdWNKJlJPMnlF
S1BidkNleSNQcisKenkzSHohTF4yTzw7I1M5LWF7WkRUOVZjdkZZP3pkcD58SH5ybH1mMD4+Y19y
R1p7U15HK3FQPmVHYndCSz1qTTdkCnpyTHV7bjxsNz9ARHVtRUV1bztgalFpeWU+WEh2OUFgS0pq
TEdfSz92REtOPj1tMDhxTnxJNHEmUU1+I0w/bSRrbQp6Xyt6czNrKWRrS3hPfkVAUz9BTnNMU2sw
PzM3SjBMckk4Jk5ZeUUrekxVRmx0a1lAIWE7akRqeDBZVHclQzF9VmoKenNlb3VmJFkhMVRvQWA7
dkBqU09NNk9xc3BaWHJISjtBV35RJiNIblVmODFVRWRzYmROS0MxJVhhJFFTJnBJUyFkCnpvNVB8
NGZONy1OYlR9Tz5BQFlGUitRLVY1U3cmU3NzTFVFVyE4eTlYRlZfRSU8RDFuT1A1NXBrIXozcGJg
Ji1WXwp6bG1hWE8jO01vQkZCR05fSzllKFF3LXhIc1dEfjtUQW41V2A4YS16fnl1VkNXMnZqYDsm
VzstPTcyd1h6Szc7NF4KelZWblc5UkJ0WiRTMko+PlBrbzcjI2RfNnI0OWxAdTMyMm5JX189PE1Z
RjxmVUJOXlFja2JUQSY8c04xMiFoeVJCCnpqNjlzQENJcVRuQHRYbXdXRj1mNlAwNjcmWVlMUkNo
biRzUj9fNk0oSDJ1bEslWW9wQ0hmMXNTNVN1WkApSFBkQQp6eSQ8PygrM1FGS1RDPj59SD1ASXJY
ZX1Dc1pCJUpfO2BASnB7VUo1THNZLUR4VU9kej8qQkZoPV8lNEM5aENza3UKenFYJkdScnVLSCk9
ZUdUdW9ILWxLU2VqZCtEPnkrVUMtZFAyZXU9VGRIc0E8QztDUHE1MkJYRXY/Kll3Pik5ZlB+Cnpr
NlhKRDwhK29wVEBDTTh0UTxHO0Nec2tjYFB1MCVzPSVOTUU+UystPyRsZzgxKXxXLVMoVW5jezRi
PDloJl9yUAp6M281eW5MQTxMOElOK2FGWigpVlBzak1iRmNTRHVNTH5+UW9rcllaXmlGPTtpfDFI
PSFMcklKYG1UdVdCaE5OSioKelY4I31raHg2OGUmMU1IYzNEKFNiczFuYnQ7Tk5Nd2h7YnN5JW9t
NFQ5Vnd1TU9vYyZJQmRKUjxULWZ3eHJ4T3NUCnpeek1PNjM2e1EzMzZATCljVURVcm1HXmlGKSYq
SDhrMyVLbykoVXB2KEhDM2B7eyhVRGBSIVc+Zj5MK140QVN6WAp6PnZoajYodj55ciotUitOIVFu
c1dVPHtSSVViX3pYJjd2dlpHUDRJOCU/fUp0K2BrRklESVVNa25BQmJwdkZxMW8KelMhaz1YSyF9
TDl2SVNBNHgqdXtqaFRVYzBjS3pvfUtiZDcwb15Qaj1WTEElSVZkRk18UEVibTRrTHhxNHNVVz1B
CnpQO30/JT83ZlMmIUJvRGItP0RgU0dzWVNtLSthcW8xRVhSaj9TJDY+S2UrOEI+QFheTHN1Yj5Y
MWY8VWt3ZjNTKgp6RU0xe3ZKKUZeIUp8PUFGTmFjcVE7RH4lJDxQRDJAVG12JkRqTk40SXdlQiVZ
WEF7ciVEOUJVNURIJEd0MHc1P0IKenF+LT1rWX1XdjN0RFc+ZlQhb21GbVIxNHs/LWFUeGVpUDVK
dEFFPSp5T2IhRE9mTGsodyZVJnRRaHwrY0xhLVphCnpPP3cpJkEpeVpPbE8xJS1GYSZ1PyNyUikq
LT53cXtZZFNKNUBNRFZvTk03RXUzd2FXRWJWVkFjNDlWeytJfVB2Owp6JFo4cnc9fGhFYmE0d1U8
emZQVyFpN2xKPSk5X345Y0wkP2lZMGJNM3Njb0spP3JwSCtRfm58WDJsNGRMYyF2UFoKejUoZDJo
ZTJ1MSpvZlk5MHZ6fi1fUlNBcU0yTDdYQStySWcwUFZZMG5BV0NFZGRpMnw5MXxnQCNoVz4qTVR0
dV5eCnpWbjw3TSF9ZWY9QzRXRGMtTmgrMjdnJTRzJVNeR0FDNEQ5d2BgTyNgaSomTHVHdmdhP2Ji
Q0smUCpIQX12fk1wOwp6Q3drQz4xezdRTWpARH18KHpJUE0hMjUpQkElcmM+PlEkV0VVcTU/YDJ2
Kip8OEApY3U1Xj83R0xkd3R2Rns2RUEKejBCZHNVbUFnS2lTTl44I2UlPnx4UkgmaE12aFJhPisw
RU1sITwhTTlDRT83NCMtc0VvUTlNbVM5c0hCKnMtWn08Cnp8TUxLaGJuLVghPnZ+PV9xdUZaTXZ2
O2RKZFZNcilNKXNfKHEtY0owMTx6cEtSJWlkbGQ2YnN1dHNZMnJRaH41Zwp6KldIM2wyR1hBb21p
dzFWKG52bmJzdVZFJilFP2k3Q29jMz0jcz8yd3deTG82cn4yVTlUI29SMmMzPzZCbkhUPmQKej03
QVVXUX0kTmB0MTEmKT5udkwjeSF7O1R2XktEIVQ9aHVOPjIyUkcoazx9Uzk2eV80c1g3NCtuOUFu
ZTxRSEl0CnpgIzZPTFkqdntpd0lKbjUxXjViJTxtOGVwSkFFSzVQUU80JnAxTkdFJkZTfWpjR1Jk
cCNTWT5eY3A4el5WflBxPgp6dmFpKEFkMy1CPjwtRiRxIVlfeHQ9Vilkcnh9X2JHbyNBXj5WaERK
YG4rOzVWZlkxODM5QEFqeTRIOzJ7b3VhWnoKeitFMVVNQnB8aUNXTyh4JXc5SV91LTc0ay1QczhU
QCM5THxtLTY5eEpRQEV8fTF3YWomYVYqRD03QHxjSEJQWGh9Cno1TEtXNyElZiNDMHdOYnRxSDI5
cGMyV0RRWVIrPjVmaHNTfjtMMnAmZGRaYGIxOGtoMD4yQEcmI3lwXjJkRXlwfAp6SlNqRCNreG9j
UWY5fm1ITkpoKygyfihxJHNuMjlrSmxBKjJhcnMjaWZhR2F0UTQ3REBhPHMhTU9yYzRoaFYxK2QK
eiNnYHNrZlp4NDVsV2ZMPVV8S09CO0NydksxJVNBKyMmUSV5e0FOSFN5Rzt+ckZBalVEcVIzOzRy
fEpMKiM8bX5kCnpIaThrVEpwIzJxbDQ/cT0yX1lVZzZzejkpVkNNZEVUMit5Vkl4NGlvJGE4JkVQ
PWA5Z1EzK1N1Nm1ReEReRm5gSgp6dnBrVCRaRFh5dEh9aFZ8S3tyTjhgfVFVaDshPlhqdG1aZVB7
dUx2WVZBcC05P2s4SHZZYXFge3FxPkJ6OWU/fFgKelItWjMyTW41RCokSmUjOTA7Wng9MChDMV48
aWh5U28xZjQzSDlDSHRgcWl5NG9zeDQ+a15udVVLLVlRKXZ8PCFmCnpKOWNiUGohK1VgIXR3ZGxG
VVcyP3xBUXFtZyp+KkJnOG16NyNsLW0hbTg5XjY9ISF1ST83XmhMQnlIXnZKSD4tQwp6RStXV1Yy
X3FAOU5IWCtATkN8dl4pMFB4VzBOQWNXM0hEKX1ZdTZwdlckVGUwXmNjJHlrK0l4KWlkKE9WZG5B
cFUKelJAT3c4Vyp6WWAhfFhKZV54ekBuMTd9RGc/YnNiN2NTbVM2ZEZgcWFGK2xMcUxLJDBvUlY8
Q0NjOEslMmt7eHhSCnpNM0IoPHZVPXQ2MDFgUEElMyktUmohPGktXnc9KGEyQiplR2A9QV5LUHsk
NnAqMFk8TFVkNyRRUDVzRT42akE2Qwp6b3hEdlRXNygpNnBRPWE5T1FRWkBFP0M5aiV9V0ElX0oh
YjNjOT9sUSE0YypYRGNKOXh1N3k3MXJkODA0aiZpS3kKem0pXzNQZF5SV2MrPkItQ3Bme31qRC18
dWhpJUojNzs2SFI5KFZ5WDZULWpMO3hgUkVVN3lCXil1cFhJPVc+Tz1wCnpkS1pgY0UyWFdIS15W
c2YwZGxuNnYtbzk+aX5ecilaYTVTZm1IM3tpeXc5OTUyNi1MKj5LVjZqe2s3YTFPNiV9Ngp6by1w
TDxhN0NGLT5hdyNXVX0+QykhWF5XP2l6VklIQmU7bUhLZGljRG4pSz9zV2IzZV43KWJAQz5YRyZh
YU08dkwKel8kdjw5JE1mX1k5PkQ8cyNhaU91ZDJuaXVDJXE5aiorRjhHWnN8bUdefCZ3QGl2WT9j
PGJRXjJuaGhpSVg1WEJ6Cno3KTxGN2trV284dUMoP24oY2Mzbl5Ram4lR1gxUTcraEtHb1g+R2p3
VGM8X0ZCd0VDeF5oPGJJUDchfituSTdiSQp6I2p+QnYmKGs+a1NfTkFXZmROUk0+R0dOQGJGNUJB
a3h6a3JBbjFaRTxLTTVDSyZWRnx3bTR2YzYrQEJkZG9adG8KemlYaD8tOXw3VHd3JXlPQDhCMHQq
dk13JH54T2pLNkxeYz1jezN1ME1haHlYPFdkVG9PJmVIe2UpeC11WUxYcUoxCnooRn4+aChSNUth
aVdoP1hfOTFHbShQOVR0NE9qNyFnenNiXjQmQFhvQTZuSDtYXlpPRUZHUzgrYiNHPnFEdz9JXgp6
dyQ4O3xAPmlrZjx3MEBge154c1NMUWpzdEcoY09mITEoTWRWfWUwS2RTYDVqRTx7eHYhRytvP1ct
RVM2NDFLXmUKekl6I2FfMD9zeE1TMFFWbTx0S3VqNyZzMmJBaGpRJEdLJlFWQ0ghWiZtYDI5QkxB
dVNUNEUkZihrSE5GZntRWCRMCnp4VzkjbFcqbWN9ZkdOS2k1UClkNWFgMDJqXnxFNCRwR2c2PEhn
TTJjJCUkNH4pemElZk5EZkFIVEB9ZDtHWSV4Kgp6cSF6dyVuWHs9Kj9JSzhHKDFWaEIjTyVfMEdY
PE5TJjUteX5jVlMzY0RPZHQhSVRgPSo/e0E7ZXV9KEItS0ZDUzIKek1kK1liJlNGQE55SmVtPmtl
X0dyPmJnK3hzJj0+YjdAd0J1YXcqNUdWRXQ/dDc8b15ZOTU+TH1VMmdHVD1lRHFVCnp2ekxzYjAm
QWtLejBMcCh4JmlSVzRQT2xfZHFaVH1oOCtfQiE5XjJ2QHNmKXkzdFRSTFhGO2h+UVh7eXBOMDBw
Vgp6WHclakE2PnNfJDVudSlgKCtnfnxBeXdRRm00c0BXaGpsbEFqP35xQmZxS0Y9UzdIM2clOFZz
SHh6fjEkYHF+KT4Kej9ob35EIWAxfWs/Nmc3YFN5QU51bG55ZEBaTkA1WF5LPExSMEtAakhvN3BF
RVRsWTtRSnsmZjQwSVhJMCl7PTdrCnozIS08dEs7ZFcqY1FITlg2WSNuP1gqK3lAVGA8LVhFbkIt
JTlnJHhgWCp4eytvUnFGK3B5bW15NGRaJDZjdlc/dgp6ZlFqfnpCYW0xTGxVYSF6c002U2Q3WnA0
N1kkckxKaD5xTFMrJEF2VSNCRCRpPnEzcE0ocH4tQmJmZkpYP3I1MmwKelQ2SzUyIy1zPkNLemRV
PXopJmw9cHRoIXRrbnVya217QkhnOTBwPDV1fDU8PUA7ZCpBIUtgOFJXaUhUIXZJSnYtCnpQVVFY
SjE4QXB6dm4pektgQ0BsR057I2tmUSp5UkljS1JEUCtZKFlpc1c7c0RNfGMkSi19b0NGUGg8Z2lC
dDBnNAp6Rnh9MGVkOVlCS0llaypJKEMyNER4OEh9alJRe2s9IWZyfGpQWjMhZDtoak41bncyQytX
ZFcybHZ0UntmO0deN3oKeiZhejU0S353ZVBYWio7cjckTmI2aU1FdCU+M0BmO3lMS2U/IVFhaHVZ
TlBEZF9jc3p9cjRjejFnV2o4Vj8zbnE8CnppS21BbUt4MHdgMjI0TWsjI1RQJDRyano3ajc8NnZy
cmp7K3ZCejRRMlQzfVZTcn1AZXZwcjtGQlJmZlRjZ1RwZQp6MExfcmo9b0pnVmhgPzs+M1YzUnBC
WXU1fCZyPTRtPz9nX2kweXVpNlZ5d1FkWnlzNnUxcGhze1hiJkFRIXZtTUsKekwoJUJgWXliM2NP
QzNsLSNqZHA4e3F2TnUtRVpCa0RqbWVTKkw/bmZKWjg9dFMqQUJKP0VTZjRPUyRofD1ORngrCnpI
IWVjeEQlYUhMOFFlLURXNDlfUldaR09Se0ctM2UwNVIoWHshRGk4SXtaRkslb05EPT1UNHwyTCp8
S0dFdH5NTwp6T2NWKSMpNk1FcHg2JGJyWnBxRV9OSSVDJlheJUJ3byQkZylTVzBlPTJtMUFNWlYy
c3hqTTAyIThiY3dxcno9fVcKej9KUkNHNz5fTlNjMnQ2QGkrcCo2NFZZNlhnRVoyVWhabyszTGsh
PDdOcD5+PW8jQXBCQSZ7QUtWVHpITmVMSnw8CnotO0xmKCN3azNEbzkyemU9RDlXTisjenVMO1RI
bU5wJVpNOyh+NlYmbHdtYihXZ2kzWGR2aCo5MStvQn1NNWc3PAp6TjlfUW8/a3duP2h5JiV1WHRe
PVhHfSlXM0xfUTcmIzQ+flhGXklsUjI8UTZtcEhrOE8xd1ZuZmRzT2gld3Q4Mn0KekVxWUt7OXFU
MGk8NyYrVF9BamNVQ2gqZHk5U3oyISVeeWBlaXk5T2JLcUk9c2pFYSo8XkgyYUFGLS1KOCNNQyRH
CnomZ3ImdlYzXmwqNjxrKkh0ezkkcUt7NTsrSDJQcE4/VEpueXt1U2QzPkMtWTtLVSFNVEdzUXRU
QzI8eX1EYitoKAp6N3FOLUx5ZElVITg2WjZhVGVpJiN5Nj81ckhqYjgjIUFDcX0zIzN7U3c4RHAp
QUJmQTxoKjZVblVENUEjP2lrdHcKelRvU25AeCVTX2p4bHQ9MHRfISNNRXBRfjlLMyhhdSN4UFFE
RjM1O0g4QyljS3E7Vj1DX2xqPmpoa2xPdlFAaFdhCnpZWnsxMj0qZD0wdzFEREklanYrJCRjKmM1
KEhLSjc3UGt8NyY3S3FTd3tSX0FZI2wodFRNVFF1NHVPWT9MbiNhOwp6ZTBEN3U3P3NQNXN2KmY1
bzVsWm5fbXxMQnQyNDFjTGRRe09pdCUyYll9WGUhaVEqVyt5bFMjOHImaEY8QztIejcKekgrMSh1
LW1UV31uTGlmXzZJYWZiYzZWOzhwTVIxYmlSQD5eYVAjLXdHZjRTKm8jWWdLTVlTS0RBSm5RUnRv
b3pyCnpqIWEkTkF5OHZBKHVwQFh7ZkkjQCR+T1AzOD52JkB3VnQkKHJZS09uPX13Y0k3SUJqIyp2
NWI3PVBofFg7fTZITgp6NDFXTy09b01pTXQ1IVNmai1DXmFjQUY0WWMrK1coTVRucEV2VHdgam1j
SkhLdzwoO056T3M5ZllKKjtiWSVEZTAKemI/VGVxZUNuNkxvPUNqSiR+KX1+WWo9aG5xPW1qSGVE
R29hVy1yO3toP3xQd2lyJDVubjRvS0dUI1FBQ1plXyUmCnpDfGd3ZnFoYy1PMXhMRVApKVgkeVpa
WlFVNHhpKT4yRjclP0Y9IT5zWXN5Sl8rdG1oQC1XMkxuQlYkciZMXyhTOwp6PGomQlp7JDNIKlFW
d2YqaThId0hQQjkqRCtiK08zcDkkczYpfiFKJistJHM3bFRROTtLWCFZXm0kLTFaZHkjMXEKelQw
P0peTTIkTlhtVE5rK2xUNVctLUB+NX00MiY/SHB8RUdnIWR3KlF1K04+O2pxQ2JwJCZIfVFlQClM
Qkx5T1h0CnpNeE1CTGNCOGhMPGo2MjdPQmJsVW9IRnQ5Q0tRKGw0Zk51WU52bn1JRGlEWjJ1RCtj
e0lfJWF7PCoyK2BMYUp0dQp6eC08TDxIdzNvXnZoPnBxUkx3R2A4MntxZFE5SkhEPn1QbFh7UyVY
fDhEc2RQaVE5fihfcnY7O0g+VkhXQjk9fWwKekNmPW88Xi1uQ1p1R3EtQlApNWgrd319NFMpem4q
VEF9X0FkSSlxTlFSfEtRXm5qfGVGZ2BmPzJRM1QlZ3A8M0NqCnpfX09eN0tRJH1ZcE8lWSp7JDAo
PFBPYnloNDsxa0sja04/Ynl8TFladF8mMip3VjBXYUI1Sl40SENvOHZMZEApcwp6NzQyP1FhJlBn
akU/WWhWUzNPczg1PHlzQSlGPShTKGI0NlU+eSheaXtPSjUrdkpILUpkbjNPTzY5YlZWMWkmR2IK
ekFNI2cxVXAtdCVMRCMpOWpDQW1hXiUyQVUra15AOXpld2FoaFJIbDhUOTtoNFNXWndvcXRsc2tk
ZyQ/QGBiIXUyCnpUMFhjTXRAKXo9bHkjNmB7QUx7eEBZQ04/eDh3aX1qfSNiPWx6PipUVilael5z
aVNmRS1QIzduUkBIY0JMSn1BTwp6ST9iMWYqezJDez9RZ2g9d2Yzd148WnVLPGRrJT4wcyh7dEpA
JWB2YUdgbH5pcX5VUllZX0Q8YFYoRXFEc3xvTFoKemgrNlMhPTlpUjhQZFU4K0g5c1A2VipmIWxy
ciE7RjxHNTVYb1khPHVzby1BcGMtVndHO2o5dT1CWFhpZDM7JiV9CnomYm4yNTR9e3NGYT0oOWxg
WXVrc05IfW5hbn5VZTtgK35kOWNSYCEtVUM3PnxoVDdsejVyTXEpNHRQYUAyeFYhIQp6Sm5kIU9t
V2xZfj4pWSlCQUY0MVZOZ01FfDxgdnZnbmJkV0lqKjx4PTIjWn1qblMtSiZoNDE/fVchSSEjIXE8
QVUKelA8Ym91bChhcWJBbnlzMGMmSmdEe29WRmtjJkk2P0BsVT5aKCFgVGtTZmx7QnViYk5BPXg1
dWZIczEmTEVeQndzCnpHPEgxUHFPZlFjYG9OKDBWKEplPlphRHdwYSlaMW5NTUFHV3FhQmxSJD0y
JGgheHhXTUhMYTkxNExnJiRuck1sJQp6dUU7TS1ZTFUze1VveW04YHZ0O3NSUGgzcnF1eDJNNU05
I3JMZT1uVU9OSU5QayV5Kkx7Wip3QCUkbFBJR205JlIKentWOE9wZHxNamNORDAwNiRaQiNCTyFi
azhUQndGc3I0MmtZTEVzaykzIUk2YCRwZnJ8Pml5KWkoSFRgOzkwY257CnpCYk12JjktRV8+YSs2
bnU7YV5KS15+NGp5PDg+VWF0dyZiZ01oOT97KWpNeGRJeVdnI0x6O3ZOWXE0RyE8U2RZQgp6Q2d9
dGdUVUktYTwjMipAZSh7RD1tOHhULXpmQ1ZXSXw0OyhPOFR8QHp2PFFSYFRjSUBXQGRmV00hYTEw
VW8zUU4Kek1FPTBgO289bnhHeHgzU2lMRHdlMmd4OE81QXEpdmEkQSFyYnxMOEAycmZvJD4mVGY4
I0gtNF40eTxFMW1TSjhpCnpNNSEwZSFzRX1MT0x2RUVKSlZ2MihnZSl1ITwjJDN6KW09MlBLcGZ9
emtiP3E3ZDFMKE5KKj19THs5MmVvdlFHdAp6bnI3VH1NSjkrcW5hYXZLK29mfWc2NjlObUt4QWd1
N2F3TylSYnFZVHM/WVlFMyo9VkRpI31UM1U3fm1hI2wzUUcKejs+NVNOIzlFbmI8aW1ZQzB0RjN+
JWxQfEBsdlk2M18hQ3BKSnhKOCFiSmNnS1AzMFJ9dSR3QDtIRTxUP3FxKld3CnomaVpoKik4bipp
eFNFYFQ/QDtecVhOQ0MwTTtfYTc2S3JaNml5Q343WmxOYiVCUiMhdHJGMlojcVM5dDdSQXxzTgp6
NF8jZU9FPk5eUitzU29pOTclcGRXSEtJVmJzfXclVFh+UnVZanQpKkNNQ0s+X0goOzQ0P2Q+U0p7
VjtvYHtRMjQKeiNiNzdWYFVZRU1BUElKSD1IOCYqXyFiQmNmOXctXkBebUdmezEqd3ZXfHNOUXRJ
V2toNkgtJnFnelJhPHJDaEB9Cno/Q012UT4zKTVxTjReajlKRUN4KDhzTjUhWlQ9KUBodmMyKWpa
LTRSbzlSaXlgeCUtaXZ2NkZ0VSF7SiUkailwbwp6c24yfDFINXpGN1BSPX1gbUNEcjtnd29HSk97
MnQ/RU1CfjhBPXsoMGdzQz59PV44TlV4QHgqVS1aOEt5c3pxJDMKellsT2Y2dVoraFNxcUpmP2lY
TlM0YDUtSjlzdSF4cllRV1UwQH10aH1WXjtjdyNoMW9KJSNZWW44VSg1R14xKUpnCnolO1I7TUBy
SXV8TTIkSFRHezBKWHM8eUYqWDBiNE1pe1oyQmNlbVVtQ3wwaWxVOSl3O3EoR2ZvJH14PzQqWDhz
Uwp6cjImYj95eC08VFV1dSVGPSpvRkhGNypDZGZCZHdGXlRwQCl6ZSZxRTgxaWImVENwO1gxfTtm
Xkw9c2drJntVZUEKemlYNU8pOXp2R0FFUWt2aXtmRn1CVCppfUJOXiZ+QytKc2pQXk5MIzJOUz87
T3RmRXMzKzg5anlwST19Pyp0WkZiCnpLQ1QpcnNUIXtpS1g7fT1abFE3ZzRENXV4P3FJZHZkQz45
PWRLMT5ndUlmJGY0bmcpUF5pLWxGRypgTXVRPXh9awp6MFd0OURGXmE7QjtxNWVNU2xVdXQ8cloq
JUlRQSNiUUluUjNoPEBne19OWWBlSDdhRHJKVitRJnNLaUo3dTJaPFoKejFgT0w/TGBFMnRoI09x
Y05td3xUJCUlKyptLVdXM1dvMzBTU3slR3U7KlVpXiFgQjlETUdofW4pdkUoPF8pPXUqCnpsc3xq
TlpwYDFpREVKYko2ZmdAcCVfTEBzJk8mWHVVOXFkWk1oV0g7YElrcUYzJmNTRmYxYEl8THZCKGx1
eGBxbAp6d09rKkZnXks7RHVMUEZrVnxHeWhRYURrWmo1dzU1b0tVJiF3QFlKdmFtOUJVeVo9M2dj
RWBRNCFATj8hLUxediMKejsyS2p+KlN7U3VIOzdEcHxJdlpxeDBPd3lsejlAaCMqYmh3azQkdGlg
bzAzbnA+NF9gPXd+cUhDcDhBJjJ0QmZSCnp5ZlRafj1ubTxLVSg+PFZDRm5KUntNdXA3Yj9zMyQx
PUoqQjc4IXk2YXMjMT5BcTB8WE4mMWc7NndEN2RGNGtadQp6bEFBayQybllDbiF7eS1Hc1BMSk9w
KnZ7ZDNEeHJCVykqQG5ySjstIzJ+Uz1sTDBYWCZHZyliOFd9YTBKeU5ZIWcKemcyeHVid0t5VUMx
LTYhZCpeNjFaSmFIPUFXc2VyZzAwd3JfJD5Ec303emlKeUBAMUNtaUFSSiZrN2xmQk1fTUF7Cnox
Pz94ZT9MVXZhOHc7T31sITF3Y2J7ZVM4bkomSiVjWkFDJUJ4Nzg8enheKTx0d3s0P0l0M0dheGlV
aXpSYyUtSwp6JlAtaHxfUHlYbjFnSSU1cW1fMEZlWTF4dXFiJX53cUcjSHhYfn0yXjdqXmB0Z3t6
JUkxPz9fQkQ8O09MVXtQaFIKenVoZih+eUA4cVJgaHdrQ144MWZFM0VANHx7fDItPzZDazVVSmp2
NzUjPT9EQUdvVTZ+dTlOYiZSbnchTDV1Qn0pCnpjJCo4TVJ1dlBKPTduKHtQaFJFa3IxRjwkRXhE
ZTFmbCE7LVRweGYjKnVZYHRUTVU0bmprMlh2JCgqSCsze2x3SAp6JSEqPnYhPWExdSEqJWglcEk0
KmRHKGg0KCRob1VmKENzXzdMR0tBc3JLPH12OyYzVHxxNCU1TlVkPUsjbWQ/eDQKemhjRE8oRW5V
NEFZcUBIZXpjeEBYXjBaKVZKdnklYENPb0VfRlZUZGJoO3FzWmVKdilqSCRFPSpMZF5qQ0heYnI1
Cno3Qnkoe2s9ZDklWUw/Y0YrTDVwSFFRQDU4dm9+ayFHTjNUR1R6YkAmcWk9OVc8KytYU1YtTjhT
JmtOKytBSGdJPgp6VVM9X0pSVSRYODY5PF9Kc0E4NmlrTnUyLU4/dUlIKWxuP2U9OXVfcS1OMW5k
dVg3cllMXjQwR1Z1bzI2YjBuKigKejxpS3U8R3F7MyNIen1XJE9NPkVqP3x4aEQxQ3IzaGd0dlIz
SVhRIzEkUlJIa2c3dDNeaDBza0c4WE5AZmA2PnAmCnpjU3RNSU5aSk9FX31gem1FJlRHJjk8NVJ7
UWJHIW4oVlUwV0lufkxGZEs2emoyYylnSkk/PXd6PndhQnp6ZiQzZQp6SWFEY1VMQHEhZilQQCM+
T2laWWlRK35eanY4QFlecEMqKVIhXjg8U2M4I0lIYUB3KSE+d3NkdHl6WFBnaCRxeHMKel5keFg5
bT59VU40TXJCSzJ9PXdXLUZQSXBaNElXZTYoVSpFblpHflVucC1pMHF3eXI3dDZxP2wmMUxpSjMp
cSEtCno2MD0+QzUwMCZLJTJSI2xuWXFrcEVMPW1DNkUqI1E/UWV1Vl5NR012JUVIV2pFKWwyWjht
UTsjaVI0U2FeSW1fLQp6REk4cCE2NFp7MlJ2dDUobDN6N205JHpiMyE+YFhEdkp6eHA4QUxHYGBQ
NGBEc1pVZ2xVZ21jfnd0SyNzRmoxVFEKend3ZS0yUmZ0KzU1U0V3UHBYUWV3QWNrJmE3ZypENTY7
X0IwPU5qfFRINXAzQm5RSm5lVzslP2FkZGpuNkA1YDxiCnprfGl8OyQxQWI0QiRKYmU+KXI5KHZA
OH5wNFM9fjRwa01iQFprJmpSUX4yfUU3PTl0Rl44VVBldE0qcU11Zlo+awp6XjQ4fVRnISlBel9O
dTg5ZT5qSXtFVip5dGlUeWtqR2Nna3NyQVRaNFYqaSN1JTw9RV93NWVmZFRCIV4jViYkXjcKelZP
bWE7KHpXVDlodSMpfGpAam1mcERDRV5iVkJXMUgzT3tAKXBxdGpgRnc+bDI7dTdLandFMlE9UGJL
SU9zc19jCnpDdkF5MUpLWmhQVTEzJkBBO1paJSF7MTM3Xl4zLXhFKmxrRCVBUVJBczIqME1DPmdY
Zj5PKDVPTCg0X1Q1PEV+dQp6SD53MXF2MiViJmdGNShEZnB1WCtTQ0ItRjkxTjJ1SlBpamVaaUNW
MCZ5MU5Bek5zKiZCJHlYb1RIekN8MytkPVAKeiFUQnU3ZlolV01LVH1QMEl3RX50UWA5cVpmZyg+
MmRhMjt8PjYhR0NnKWljNWsqKlIqOUVzTlg4ZT85N0VVQlByCnp3U3d3bypmNnNnQDlyWSU5Xnxe
Y2BsLS1UO1BUWXoyc3BZRil5ey0lJEB8Z0MkIzYjeVFHUXU3bVU5YlZRZyhPYAp6YnJNTlI1P2Aq
PCokaSpIWGJsIXdtPWs3NjE9MkZvJUFqZm1mY0BpZ14qUio3aUVxZzRWM31sIWFfT2BHITZOJlIK
ejU/I09EYzU4NGowNFFPYko4aTYwLW5eZ1R6O0RmK0tFb0BhMVRDekx2RXRza2JURTB5ODBSY0l0
MnlOPGl3ZjZMCnpqdEl3QjZNM29eWD53ZmhWQEN+aHJhSGVHcWEofUhXdEdeNlYyfXpKNihwN00p
e0VVc3lAVSR+ZkhDfDJ0al44ZQp6e055TFc/KXJVbEhPQUMkUzl4QHZ7LThuaGdGeTB2RWlsYnJU
aTJDcmMyPjtVbV9BVnxpe2VjenJ6S1ItZ0ZldzUKeih3PjdmTGpYb2BfclhKYmZpfXREZzZrJjVF
KyZsRmItbE1xJlE3Mjt1Y3IhR2c0dl5jXzZMPDZod1QzPSZwYnI2Cnp5YXFoWXMrcVZTcV9BO2hE
UU18QEU1MV5LbWJqUHBQXlM/THZBdilENytVRGtYOE13ODMmQmQxMTttSS1WeUZFTAp6eypIRXor
LXVnMFVIfm9VMzx3WDBIfTRLY0spWFBPe2NNQD1CdGJANT1VbG43YD0kSzc8MG5WQmA/ZGxvJklX
VGMKeml8NHp2bCR5antKJXhWVGB8QkdkNX0xJUpOcXR0NSl4TihAKnl5TlZtfj1mRjFTTjRXR0Yt
QE9BV31pVihGaGM7CnpSbmB2PTFkeUNvR3lNaUU2TWImS0VsTGRwOW1LQmxIVGJQTHFoSUBjPClX
NzZQcWFSJnJJWCtzT2oxTlZScTZ4Nwp6I3FMaUN2QTNLaVQrfXgtJkJedn0+Y1daVUVKY1FnK2N8
SihiRnt0SVVlSmQxb2FUbFFQYjd5UXg9I3dkemhud0gKemNOKW1QK0ptOVIkVGlBTGIkKVlZNms/
Wn5ad3RrckA4MipOayQ3PyFsJHFOMForU1lHPWpWU2slcFUrbWJNKFUtCnpiZWI5KFQkaGgqezhn
RShnXiZYJXdCYVJqNFhoUl9nbDtCbWEoKGFSe3d9fm4lWkQtMCh2cFgmVSZvPXtBOHdedQp6V2pY
N2hlakxlVlpqLXRCRVdmfDAlUFQ3YDZIaDk2THApSmBDUTkhY2BQRD91Pk4lSy0+YHhoUEJ2THtN
WUdKWUMKelBtZGZYK0hhT0BhPlhlOEBpKHU9YTlQYl9CPzkqWDteKyVPWSNyfWxNMytBfFB4QU8w
VmtobCZUfnE3cEwzUUcmCnptcih0azdvTUE1QDZvcih5fEdhKVdzYSFBdlRyIW9rZ0pmQiU+fHhF
MXp6cUprNUBOTj08Z0sqOyVvLTdgJD9SfQp6JGBXPG5jN3d0S1VzYCFAS3ZPRlpTVkQhPk5zKj5r
a3UyaENZaXF7d3c1WFRSO1EhPHA8K2trSXR3KlpxT19eP2gKekc3fHlDRl42Q2xyd05rT0NjRSM1
YnVRPktLVEtTd1FvQ1kpKkB5N2JDemMlNVduIyVsKzw4TGNBWnptTmRjcVZFCnpDbTghK2NxZyFR
QShSQ28jV0BsQHREbjhfemZWN3lsLSl8JnB4TH00PDRkMytsZEJlbUclTjVzYGtXUmltdV5pdgp6
ZS1zVSlTPkE7Z0QqOTI/eW5UJXxtTUt0OFVGQk53M3RJR3k4WkoyMD9oQj5IKm1LfHxTeFlBNzE/
IUlScVl9TC0KejYxQHZZKlh2KlBfNGpWTFQmODRZOWZ2YyNWRGRAY292Yj0xQyNVX19ufjlmeTlO
JTcrWSVHQz9gSmZPUUVgVklFCnpJO0g2UVlyfWkxLU9qJGx3cVQ8JihAcUZYb1E8JFhjc05GSWNa
SW1gVC0tKDFkKj99IzdFWWx9RWpoT1d4M2p1aAp6aWNaLSpBP1dHPTxUNiVVTEBFXj5lcSQ1aUQ+
XkcjentXTTIhblNoem94fWZwRWxsZkBoZ2N6XyomVzxASk0qY2oKellkPUdgRF98c0hBbUF2KWRf
I1Y5QyoyP2BKWiZJfkBXRDc+K3lWNFpSJGpGezJ5XzJUZiZUZitjdUJJPmBJJDU1Cno7M1V4TjFR
Y2o5bklvMXpANWM9NDhrK3FaP2pITWViMT1sd3dRY1NFeC1aYj5gJD4zOytfaGRUOEZvJHp5Vjs/
LQp6PDI+N1kmMzhmZjw+aDdDS3A/aUAhQUNTS096X31XTmw5MX52YDI+bSs5Pms/cDt9OWpwd3Fu
OWp7Rj4tMkpVJE4KelFYUjAtQHYhekhAYj5tKjVzbCo/MTBIZjA2bStPT0swNEFRdG14UTtsWWt0
PkxGaSs1Mkp3TikrLUlNfmdqcG9OCnpuOyV3bkp8OTE8MTFBR092a00jNV80OF4kX1lRRjZsUi0q
eU0tfWReQl8jXjtSbUx3SGZ6SzUwa2ZQdEBlRWQlOwp6PX1FO2pxUGskei10TGIzNDJPLVUlI0dL
NVhZWSZrTGB7LSVqWlVAaDlVKjlRZlgpNzd1NCZoMUZ4dlZ7QT9VcUYKenFKUjJkNmgkIXVGSmJx
OVcoRFhuMW9aTnB0WlUtZ21xN1EpaXpVZ0Y4ayhGMGh3SV50TDcocjlUbjkkS3k+NE1TCnorbDdQ
dl9DamhANHB2dzc5bVhaelcqMCEwI1I2ez1iM14yOStnRnN4RzQyIUZFWjs/UUkmY29NcG5AZz9w
NE8wNwp6Y1Jfd0VffV5yMXY9MTFGUkV7MWkoOHlIN2MlTWBAdkEtLTFpQz1rN2lyJDwkTD1FNSQr
SmM2fGhZfmp7OGReSSMKenZYZmNqLW5TVVV1aV9zfXl3Xk5BSTF4QD5rK3lCd3JpbH5xS0p9Sllg
UilBJj5lcm9zZkI7e0gzSHdVRT9ObjRUCnp3czdlemNRcUMjS1ItV3ZoeHNmPmk9cCR8MjtvZT8r
dm5OfCZ9TkN0P0d6WC04MnIlcigyQEZqWVNaO3Q/cW1wQAp6V1lTZih0KCtCdWU7ZiVhWDtDNnpw
b1gjdl4kOFk9SUFpWjRZbVMlOGgwYzVMdUlMQDIqeHVvO2c7Xm5jVWV1N1IKemFGMzRISj41WHQq
K0VzJT5jWWF0KkdodVFoUTIxRTgoeDc0Z1lzWlg/Vko2KEI7OU99OFBoZWRtJnh9TUUmSEYtCnpD
Vj5pME01ND4/RT52cTBjfVhQZ0pGelBnY2tAamhQdTJ7JVpyNTFDWk5kYSpTPykxSUtCRDhIP2oh
b2Z0IS1fRgp6KzVYcE02a1MoPzA+KWtrWWhCTyVMfDV2Y2liMF5VLUJsbmgkdVF3e0pIJklyXyto
diYmZmpHeWMwS2gmNnJIUlEKejRmUGJ5dEVnQmBwUFhXN2I7RXBGV28zKzkpUTFpQ2RtKT9tci0h
Y2g0aUhQfkM/e01ZTURKX0pBTmgzdjR2S1UwCnptZysoXj0oT2hIZTcpbWsrb0RGMVkkJTItTklL
dVljWno0ISZTLVI3Uj5jaGM/Q2d4eT0rOTxWcVBvfiFgTnFxLQp6Y1BHelIoaEpTWjZaSnR5Kyoh
cj4mJDhVazBWZzY9ezxxVSU4eXlZe0lWXyl3RUlNX3t4M1dtTjsxSEMqRjVFb1MKekdvczNwNm5J
YkFSKnFRSik7QUhCTVNXbXZ6cEl+QmRtbnMlPilMbzdOIXd7SHVGcldfT21sK09xT0chcGFjZCNW
CnplY2ZlSFpAWmglLVQzMnEoJiFOTzxBKWtZPlpvdWViKFRBMGsmeiMlaC0jV3NefmtJZHVXVG1m
YiVDNiRMblRUZAp6YGdkcylWRyQ3dXtaQH5xSU1kaGRoSztBMClYck8lQX16YnUoK1pyeGtSfDRu
XypWZTVANnkzKDEtTzJiO3x8XmEKej4rJDtmTS1HK2BROHFmdiQmTVcrTGsyNkhARllreWowa3l5
LXhTbT8oa25UWmN1Mjh7cjtEU1hLRl8+KEdXKm9lCno2SWwqaGFxciRkODdMP1deKzdrJj8wJEZy
OFQ1S3I0Y1pnOFJBQ3g8aWIxIXBRK353dytEN3MoRWZheHI1UFFoPQp6ZTIzIXdAZmVCUj1XQEhW
NkxOIXloJldsTEdnfEpAO0hROHUqWTZ0TGZRYl9wOV98MHpRcnN4Y012RWp3UnlaIyYKelhePT0y
OCRRJXJrdzI0bztzN25Qd1k4TnpMIWtOfnNLSF5mPiFkRkM/UjF8S3hva2Y2LSNMK2RCQ3poaEh9
ZWRVCnpHYkxhUUsjMkBuei1hJCswRD5HbUhMWkVBbHNUPlZzV1lYcjM/K3tpU3dtWXRsKmttO1Qq
KTV2UExeZWQhRCFoeAp6NFR3MWIoPEVyWlQ5S18+dEAhWCNBblpgTUM7IWVTNE1zOzZ7T2RfSiFe
WWkrUUkwUEVuK3dTSyNXfmM9JUtDODUKem59JTBGRj4xc091OEhPZzJ7PVpxKk1YT2t0a2w1KnBG
WkU2KU9CPXBuQiZWcW59M1h9R2gzY3AjYnk9aEUkTlY5CnozNGkxcCk+PGptZTt2O3QoSFE7ODw0
UUl9T1VKeHB5UExEMGJUfkFfRHk9fitUYFMwV28jOEpQWiZPQjtZNHJnbwp6LVhud2EwS1E5TCt5
YW18RWpae3tvRXY2PyR4VXk1JTBVVjNnI1ExQT12bm1GY1Jse1UhNEsjdzJHQ1kqZlJkYj0KS1k/
WldHQGMja2JjYEJSJAoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jl
cy9zdGVhbS9lY2xpcHNlX2xvZ28ucG5nIGIvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlX2xvZ28ucG5n
Cm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAuLjU1OGMxMGQ5ODRjMGE4YmU4NTg0YzA4NDk5Y2ZiMGUwNTdkNmZhZTYKR0lU
IGJpbmFyeSBwYXRjaApsaXRlcmFsIDk1NjEKemNtZUh0X2dCLXd2LVNyTzNuSGsxKGsqfXBOUnsz
ZERGRz1gMXE3ckRna0NqTjMmbGM8Nml3KDVkSTBHcDZjdDFTCno9fW8kSExLUCQrM0ZVNzUtaGJm
IWFeTGZ3YjhgLTchPjcjN0p+USpvPn0rMT8+dVF7KFd1dHs0PXF5YjB0Xm92NQp6WWVFb30lQmQ2
Sk5gJkNVYlRGTHUpSEwmZkFvXnk/QUpzUkhlMHkrXyltUUMtdWMzI2RaLTktcjB+OFB0QW5mYzgK
el9wITZfYlApRk5ldkRwTVYxdUE1NWJXLTRxYkRoQTZPVyY4NUYyVlhIIWlNfkFWakppd0Fhcio2
aXhsZjtgKWl8Cnp4ITVgTHV5YX5oYyZMIT83fjd1OFRzPlhEYWYmeFE/Jll9KXFDI1B4VXBrKVIr
Pk84c2ViKl5SOEpvSlREMk9Pcgp6bHJrU2QjdygwWWtwSHl5dCpAQD9iQC1XJHIrcW0zc2dQIWAz
TihZRDVpSGxnQGRXTCQpMDhqd2okZmIqP0AjZWkKejJHUjNpZyVJQFVTeyFCZ2JvVUFzN3tYcXU5
SGFjcGAwT31reGMrfUhRZWdPPmZGbngqe2FwSG0zbHxibERhOT08CnpjazM9Wl5wPklEbXpHeCoh
bWhjJUomZlROXyZiPyM0bkRgQW5LSjw5Qn55WlAwaEB1U1g4N0k8LV88aFBYa25JfAp6KXdsT0JQ
Y0F0OHI3b3ZZSE1udm1eaCFRR2NrenpDS0llM3RZc3FuME1kM1lIMTdufFRtejhDc2loJEJXN3g/
en4KenQkQV59PUg8KDBwPnI+UWVPMSE2PyVmLWhgIzlANkJ4ZE5sd2RCUXlqS3xETEhUOHtBRkZR
RjZwIShLRWpUI0t0CnozeVVoVCZaUyFCRDVEa2xpaHQ8bykyRnF4YiZSZTJ0NTN8JklZMDFec2pn
ISotZE5HXklkJURLSXZzUzUhSWV1LQp6e09JXmU9PGdpYHVHb2NDJih7bFNvYHUoPUlTUiZpR0Yk
YE09Wmd5WlhPS2RxZF87ez4zQVA4LSUwfX1nX19FfF8KekRnM2RQM3M0NWJJWlleeCtrYnlhM30+
Py1pfUQtYVk8RTY7IV5qTiNKSSZtITVabV8kVSVtVng2PHMrej5gcl9TCnpMRTlgOGJlUGVkeHV4
bWV4Vz9mMWh0Y2dxYVVUTz9wV183diN8TWYtNlJeWWtvYjFMa1prMzM4NUVPSFleN3dnbAp6NHRz
OFEtYFhYczs7WE8lK1FlMHB7Q2NmVVBFSklZWWlkWiUoP205RXJKYEBncDxpY2c7IWktSVk9WWdF
em11anEKek84UFE+K0B6NjhZO1NzOFZaTl8pO05NVEhYaGtZOGU/ZThHYVU5Q2ZeRWBlVT5jUCZ1
eXtTa2RxSjZqS1d8PkItCnpSWD1taTg7Qk41PzxOcXMxfjJEbGI7NX5KS3h1dnVHQ2dYfkNyYWVJ
V0szJTt5fjhpbVZgPCVnN0pCMEs5NDQ8JQp6ZHxiOXt1eD1QeksySFRMVH1yViUzQ1hsQXk+KFNR
PmZDVnRgJXtkeldVTnJkQSkybmEkNDZkakM5LUpKa1VnKVQKejNiT3ImZ3p2fnBlI0dEMHV7a01N
K011I0s+S2MpdyYjNU09TlU4QEZ0X18yO1I4WT9idXpjN0JQRitRWE1PI2FgCnpqY2VpbHJVR1JT
a0BoZEVzdFQ7OHs/MUt9aipkVH5Ydng3MHNHejBKSGAkXnpYdzNwOEg+KnVzSlhQclZ3MkRXeQp6
WHI8OGlZdmRXQFpfIXAla2s/QzxWX2BCJD5GPGp9dDt2P3J2Tm90PTltPllGQmB7Pj5aam5EPlJQ
UFgqMVAheE8KentsfUJOM1QxZExPRHpNPzUlLWtUNHwoREM1Pj1ZdytjUkI0cV5AIWArTHo1SHY4
U0w8X2NnOWlzY142KkNLYzNwCnp7QjBFSGR3YylVQ0w4T2QyYHBrVnwzLWdKdmFtdFZsXjYpeHtP
KFEhYmQrNm1NTkNiXklePG4+M31AYl9hPSVvcwp6Tj9RKyV5WlAzMnVqNWJAb1UpMnxpRFllJkYx
KSZgVVJ2Jl8qTTghdGRMKjVqPnYmT3pAe3ttRDR4ayFXLWNLcigKejZpcl9sO3dzXmZnY1FIIUd2
KmNmT1pOR0BSVihjYm1rUmxSUlVxeXsmYHBZN0RTemlIS2dlQnU5UVFAWTRjVUFCCnp5WiVwNlUt
RExmUVNVKyhMSUh3SzlNfUN3OVZYKkJUXyVQQCUhIUg5c2Z6UF9rRiNNUiVgTy10OG5TKllaJGMx
QAp6Q0A/fmxTRj5TMUB6YmpjZGBvWFRQVDtgJXpfI2NjSFN8ZDNZOC1TV3FLPWJaRj1UWDQlai1H
XmxnNE15MlMtJmkKeiVIdTFpcHM/PEx3fVQmI1o9JkFFYHs7OWdrSy1EX1h8YmMxaUA2d31Gc2V2
azM+TT99MzU2RWxeajBvdEZ1UWU8CnopPkBmT1ZveVMhIVReMSV5ZEBEVUtXS1VMRVBhd2Uob0l3
P2E5NFJaYVlOOEchMD1hMnF+NVpCKn5PfUdDcHxXcwp6NyMmRDdTMWI0bUpXSkZRV1B4KmJ1RUBq
MV9sRGJoR1U5WkUhfDBCazs0fWFJVEkmeTFhUld5MmE8QzM1anxRdSQKemlpdit+PzRoaHRZenBs
ZWxua2EpdGFRZUZJcUB3UGZAR00wX3VJQ3kobGtyKC1ZVjdSa28rNXJ6fF47bFBEND1DCnpGXmFM
YEpmYzYwXjJYNHFCREB3Jl9QJCgmTV5aeXFYYU8mcjxFRmp2UEV5ZSRVK0o9aklOYnEhX35PND9U
S3tlfQp6JURKWCtOY3B8V0U+RjZTYjxlTVVBX3FaUClGOWwmV0BmVSlFTjMqNDdnczBTYHpBczdv
dWdkK180RG4rWHVYYzEKeiNvMERkeTVJKkVIVXc3KXkzMHQ+P05pRjxXQGk0RihIQihNIW9fVk0y
bDFNTXM7QnY2b1VqKjxzPTFaKipKVkUtCno9Tk9RNFUlMi19TSF8PFlGb0YyQypCWTFoPDJNQFBa
IVNTdT8zQTE5RXZ2YHMre2xNPSVBI09CPUVEISoxbFA/cgp6I3xwJFQ9K21YIXojSXdrTFhYUkdP
MXlaUV48bW9DaVA9PXBJWD88Ky1pLVl8K156ODxPYW9+PDd2Sk9vMEMxRjUKeiZhM0M8MWlhI2cz
QWl+TU00aHBQMFFDV2R2KSpeQz4pWTVDVUs4NEUkZ1VkYzh2I2hGMTA/VCRvYVFIWnw3N3hkCnp3
U2ZyNVMyWTlTO1N9TXYre2p6a1RJMjJXZDBFUTVCPitxcEQ3eFBLdylUb2VCalJlK2lUJExtNk9m
N28jVSk8egp6JTN0Nzd2emtHM2dGO31OPikmJURndHk+MTklfnQ9SEJTSzlSZit9PVVmO1RFJWtm
PXd1M1l8Uj5SQmt2aVE7UWEKeitVMHlWM14tdXdpLVo2TyUyPWUjP0dnfDAmYXNjfEFNRktOLXVi
OEhraUlCKl90ejs8ZDF5UWJOWiVOYEBMU184CnpIPl9STCg/Vyg3Zl9nIzBMQWdrR19icXBgczhM
RlMlUmdJanxDYHcyTXVzTFozUn5LSDBlcSg7QXFaJjF7X2xwSAp6TXFtcVl5ci0rVyUoZEB8SVk0
bWF0NVRGMm47Yz5paWBtaVdaX0FNbzFPYXp0blMkKEJ8SGBNIzU/e3tHWTlkP24Kej85RjdZOT9z
O2JMczlNJjE7cypUYTw7MElxUCotYEI2UHBFKXAqeX0rQ05aKUshVHZlVnRabj5Rfl5HbUV2Q0U4
CnpAT2dDOEc5WWRLNWNufmJndDBtNzh2cW0/P152cHdSQVQ9c3VvaXsqdiZMczRtWlE5UVpsUUVM
SXFjV015anJATAp6ZmRhJlRXKjIwRyZvTSotPDZJQHdyYFZYcHZNNFdjTHMxQmQ3SWglRTdvbTY1
LSpVND93RFJQXmdTPk9VOG4jQjMKemVaQnpsYDVOVklzeUZOYyteeE5oJTU8Rl9CR3NPX3pyUX1w
N2pwczVLbCQmaiQ2IShieU19bTlVN2ViREltKXVoCnpkck9jUnZPTn14cmRGWipgT34xWmIyMCpg
I29GJFRsYXo7LWcpX0VGO1g4QWFKVT1hcUt+UWlRQj8zTlhJMDgmWgp6a0JCdzJkfVI/VCVIUkVK
dUB3MGw2IzNgUjZ4SW1adnoodThpXzZARXZDNV9MSGp6Xi1ySyg9NG4jMk4zeFdPNykKenFTISs1
Tzc4aTxmNUBlSklFU187Wn1RJE1zK0hKUmNfVFFYN0NMfkFaSlhVWmRlRC1DNj92V1N2OXI0Ukdx
NlZiCnokajtvYl5WSkFDTmFacmNESTxhZzkkKnFYQyNEIS01ISopKklgTEBVMCY8STM4ZVFWYShQ
QSFZczMoJTVrNjVWaQp6KVBOZll0R0xtZT9vYyQxLU9WJns1PVE9XiVVUTNyXkgyKkxXdihCZyVZ
djE0Nz1CeGh3YikkdEdwK2VRLWBRXkYKel5zWGkzYTNxcUBTYzw0YHwzcFJQT3N5WVFqPihBZylW
Y2FrREVodSR5fTJLSnctdylTR18kKS1lb0Y8M2c7VmdeCnp3bz03Um1KfWBSbkRhRXA+MXVXTT5k
QEU7ckFkJS08Ujd4RnopVzl0IS0rU2J1bj83aEppT04+PjJqNl5uQSVKaQp6PWdgQkZpYlROKURa
TVE9NzB5PVhuVWloPilkKGc/TVZhRFo+Yyp0OD9XSHVLM0UmcDB7PnsxOFhWSFo+XlR0TVAKenZS
bG1mVXNNaCo4WExCR3tGOGhLTlR3ck80NFN5UCFZTHJmLWtnYDJBa0Y/fU9xX2N9Kmlpa0ReZDZn
OCFYeEIxCnpeJmRxakt9dlVxI2ImfF5YRWdhcEtZcXNQWHFiYGwqN21QNSMpTDwrISpfVj5DWShg
OyRrSSNmMHNRdTU2NFgkTwp6Y3d8MztebEF8NzlZfWhISCE+eTtPO1g+OUBje2hETHBfZzdrK2hh
RExgQHhQYUQtbX1lTyQ0aWAwSCgjS1VgfmMKem1GOX17UCkwZj5qaHhoeXQ4ZHJ3Z3hsSnh4NSZg
S3J7WGQ5Kk5yZ3A3YjxIVk1CO2d6SFNadXgrSFZZdj9welA8Cnp2d3s8NEt6NjVpcDNLS3VoZi1i
NUV8WF4rakFBaSNmNDE/YlZYU05mU3BVZ01SSU81fj5xfGozUSU5eUVmdUVUKQp6bGl1TWw1ViZW
alQ8SWFORlBHPkVObyg0Ym4xJXZpeXphKlM5fEg7IyVDMENScnx6NCk+USl9VCs+IyRST3poZjkK
ekFGfkd0SUs5TWpvclhMVUQwSEF2cFBBdTQqPzVuK2FtYW5QdCo2bHdtNlU+K3h8RXZue04+I0Bj
fWZVWnFeQDRxCnphNXkyezxAOEMoQ2EqfWp3e2U0WlI4WSh7XnRYM0VXVH5OWms2JXhHTjRUfld3
RU5heFl3ZGtESiRJSWR4VDNnMQp6T3B+dG1oKFghPUk5WldJcXJMTztkNkA+TCp0THdtOW1HSWEp
K3NhUjBTcm0xbzNHZXJ3M2VrfWJ8TVdRTTVMOFkKelZLbV4/MF9SQGpwXyVLRGVsVV9LPTRZelFE
SDc0QnBNSD1nKmQmJClEdVZ6d2QpQHAtNypiV15iRUBQY21nU0FKCnpNcjJ8ZTlUb05LJStUX3Zu
YCFrUHdRSyZWQGVlWj8tPDNQT0d2ZlUxOTVVLUs4QSl2dGRqY3c+NnZrZXtVKUtrTQp6KXhOPks0
Typ7KUZ5M3BwRCYkZiFrUyVGMyRuPChMaiU1WWJ8Q0lrbHFHT3Q0WlN6IyZXMyshaEglRmpHOHc0
cVcKengoRVcpPytjJWw+RmZ8dHU7KllVQyFiOHRZPDs4PlN9SGhicF82I09zQD53KnReMTJQXmgy
aml5JSlSN2k+c3tPCnptfWpwbmZ+PiotTGIxbkwtSzgtXjt4N3lENy0hXyQ/QjcleEQ3SElGNE10
NUNYVjN6M1hCZnRyciV1UStgWFJJJAp6VExiJCMoZXFraG12ZDFuOFU4ezxOfCpJRzZ5eWNpPDx9
TE8pMzAhV1o5TElgYXlYQDg9en5nPj1LMk5DJlhlP2YKejY0XzMpRXFuTipiP245cTxSdGtgeGdZ
WU1SSV8jeyk5SUY4SCNtU2tGaGlvRTBRQGxGNmU7fEk8SGhDQ2x6NlI1CnpTJGNNalkzaHBzciNn
Q2FjTmBsd3V0U2tUZ0dtcWotKShGPXhmdFplWCNYJU0/e3d+fTZeWXFiZXtpe0dhSClDNwp6SmUp
M3M8YF9oOzQpRE13JmlieTkjX3l2Tk8/dDlyTWd0RHw0JjhFd14hM3hMckNvd0dVUHg2KzdrLShW
NiFBZzAKeihudEh8eGQwYz1vXldwVyFfbEswTE9JLWFCdiZMaXhGbyM+UEMtM3EwWUlKKV87Pzwj
MEtNNE9icVFWXjtyTkc1CnpfVzQpbWhJMzthKkxKRTMjZH1IJEFLP3ArYVc+IzszP2lCXzNWOWxK
cmBfa302YT42Xm8lUWJeVEA2fnl6OTBwdAp6LU9MOUpGYztFbUhrM0lhbTN4MyhBVm4hJmVuVjNT
aFQjVyNofDx9N3tOZmtkQkJlUmd6I0JLeSZsfHlJYSQtRjcKenVmcDhYbWNuUk5WWURVcUA/OSRM
cCs5LWk+TjRSX2hrUklrcyhPWG1xZV9afFk3dm8jUlAtbilUQUA9QzNoRyFACnpDMXU0X3JPPDBw
dnJiMW8oQH5qelFJSzRWJnNGWVhIPkZZfjdwKER6cm14OEVsaEM7YUsoVXxCY2xnJSZuIUEpWgp6
PUZCPFEkYEFJKjZ3Pj1VOEN4YCUpSlY2biQ0cypTSk8mbDMwYVF0TTxLQGx6az4hJH4tPDk7UDhf
QnY9aGVVSFgKem8kdTJQTVFhNkh4b3RAbmkxI1I7UUd4ekAtfFBjKSZRPmc3K2tnJUN5eVJpIztv
JT02QVQ2dThVdVZiSklDLT8/CnpwO1JJVGo9MmRDWW48fCRzIVpSPUxyQFBSI2crMHNmNGE4JkFR
SUFsLUE3R1Njfkc2ZXRHYzZneFhgSypiWEFlZgp6JWM1VkZQbzEyWHteQ01eKHVtUT8pVXZIeEBl
TD9tWGgwQncmdnBEREhEJnl5MCFsbkV7JElsY1NRdmMlQyozNjcKenFMVUQkc2ReQElgRlpLWG9A
X1RiOUtKbz9sKHM8KCUpd3hzeUc5bjU1KTU/KjwzNmg8QnFiSCpFO3VHOENBbi1PCnp6YXJxaCpZ
PClxNi1TNGNkYjltQFJ4NWE2cGA8X1FPdGokJCNxTVlCaFlPd0ZHOH5BRmdNY2NWKjtjTkdnOzk4
OAp6JD1xQ21hNGgrTmF9PFpZdERQKWx0ZkEyemwxOXlaUjxLWClrOHN9ez58SjZxbmo1ck44dkZ1
ez9efjUlSXcmKm8Keng7VkttXilgQiFgfW1Hdmw4SF9ock5jI2AzVlgzdS1EalhCMyNuTVhrdXQ8
N0NAUEA4Tnk0KGJEPlBTUXRtTUVLCnorWmMzTXIjTTtEPkRhRiRKKClBczc+TXJjQDVmRClXUFpI
T3B0SyEheGJAUjZhJDw0KCUpKVp+KVh7eVVrJUNMQAp6ZW5ARVM7dyQ/PSpvU2Y5bm5RQmU8Pmk3
c0o+cnNOUTQtZVpfVStwPi1PYGVoZ3ZQMUt5bC00YjdPeyk5MlNhMVQKemdSdiZReWI1eHRHRkBh
ZE80SzxFZys/PnJuX2UrcWNqO3lLQVRCaW9CeVNBQ14zdWo8JjhWUCo3b2ZCa3tpTHVACnpqK2Bl
fWA7dnApKztuMWg5Y3NwaXpvezdyU3greSlrVyNNV2BIJDByJjVNU01qcVU2aiNLcEBjWWAjMVJw
MEVFUwp6ZDcjfS0/OGs9PVd2ajRoUDZsc1MyQTRuaSRuJDtMR3ZCbEFUeCNnI1VWQj94a0RfdmUy
N1I3az13VX1YMTNyREYKejxSQnZDP345YCg5P0crNmUte31BMU88KD93VHJ4Y2Q/ZndhNlN9eXly
Tz89NnBUcWYmT0ArQys8UmdFcCh3YnJOCnphY0VsKyhCTyZwLV9ybCQzeVhAI19TUThhaSRoJjl4
VDl4ZTt3TSFHMFNAfWhXbmNaVjxfIWpWTzJpeXBCPzZEKQp6ezslZlh0d3hRMEJ1MU1Vc2Q0RHBX
N3BLVUR+JXZuaUAwbnJeXiFqQ2hHZ1V8Qz5JUDNSbEQhbilRdEkhMSRaUiMKekcjb0NoOzVLdFR4
VkJ+MiM7WGhrTy1nI0t4eVZKVyhWUnN3SkNvX1MtQnE3JXJgY1NjaDdlQloqT0QhMDVrPWpuCnpw
YHBQNjtDVyEoM2dveHpwfSVVPC0oPGZLR1ElMTliUkJIPHZYeHA3TilOMF4/QGtFOXZ8ekJJJjM7
eyh4Z0ZyIQp6MEBCaVkkbkFtc3l+ekMoRFVYcUI9fktmMiZCdmU8fDh+ZCYhPTtWdCFwWWp0Ujgq
Ujl5VjhtWG9uWH5xV2ooKWIKeipVOX5uVWV4cGJlTzMzQiYwNl47YHMycUFxIV4oYHpxbCMyViZ7
NyRPSndEZj89eDFHSEI1clFSJnFgNWExWjZWCno+VXJrKilINkVjbyliaUd5eUFmeko5dUcralIj
X1IpUClMOFZxPDU9Mlp6a0lvKXM4dEpjdUtnamt1eUByZGVRcAp6czQ2KGd4NiNSS2RifT54K0dF
XnozRGF6MEZ9RDVYam1YbUxqP3h+cGl0Zkd7Mklaa0lwK14+UEVgPTVrIWlUck4Kek9XTkdaTylv
am10P3AwV3VYZU1qYSMkRz4qO2ooWEw/Uz5YTjN9MyUlfU1nRCNmT3NZNTsrfClicU5YZmJxfEdN
CnoyOV5fKE5AJXg/djZ8UEduSSg8TzArcz01KG1aU1U+Y1l5KD9YdUU/c3IzQl5BSXZfV2UwRGdQ
blY2UFpTNHhNWQp6aHBrMG0we3J+Rjc5TEhRT0lBVSooTloydFN0QjdxISQofE9kbmRVTkRufGlG
ITVXbndramZPdWJkU1Ehd3MhekkKek9vJHhRdU1ZbFp2cGVrez9FbV9HX29jRG5mJkhaemQxQUt3
YHJFKGJGeyQhP0R7RDE3UFJlZD5abipWYDZ+RGUkCnplOVFHZC1OUi1Ua0JnaWhmRmdBdXwyfl9m
TzlGKlc1UHg/V1J3bGBack5jZ3JOMXdAJjU4S2glOHZpTEtMX2g4Uwp6KSg4bGlIcEhQQyhrRUla
Y3pOZ0YjNHQoOSQ7bDBqa0xPXj12P2BaVSlsZiY8aExIfl48Jmw2QG9DKU8pcSlvayQKejtfLTA+
OVcpfXZ1XldZWEJaQVgodWhGUVBMZnsyPFJ0Y01ELUZFU2RtdittM05KRHEyQ3xqN2dzU1EmJXdg
Z3lsCnpLTjgrOHI7NUgyT3Epb1pyOWB+KWV1PyN0ckctVmReZHYmbnFuO1NTd2Y4NXpAO0FtYkF3
RTlTIW8za1E0MDJUegp6ZUtGYFJpbil3eiVfRE9SYiFDbUUoNDh+UlM9UD9aMXplI3NVYS1GM0dx
eEJFIyFUVG5sJVkmMVBQNDVMUG9NRD0KeilhR2tlYmZxfEtOXz9+bGM9fmo0eGE0P3BfJmN5QXB0
UCNSbU9FPUVTTD1UdEJgWTY9Wio5PkJSflclP2h3UV98CnotM1FkampgYCg+IzB+dmktTHp9NEVy
ZjtiYXhNO1p3RWpzMz9lMGU2OGhVVll2Z0ZJdmFLdD1AMkJpcjFafFBzVgp6dTl1ZFRjZXQ2ZXpE
SDJKYythSV96ZGs1PGAhRXU+Tm1AeHZPYE1xRGQtP0xYck8lKXdaZX5sNjJYQDlmU1omKCMKenVU
JCk0TlFVLTc0aSNYRyE0NllTZkFwN2BPaHdZPT9Ne3A4cjlNSTc7bmBUbFRwUUkkIXNTQHlPY2Ny
bVlnSihxCnp0ck9qQCsxPUNmaXFTfFdNO35jcVkmXkt+RyQ0VjRsdkA/NksjRSU1YGBSN1lGcU10
PClYV1MpPn4/UkA7QDV7Mwp6Z2UpckUjIVJaSnNgI2EpUDJhXyY9SXJrV1l5OHNFKCVMU1grUSR1
KEwmPT5yNEVXQlJmX0dLWUczeXBJNWNQUXEKek5iZDg2JXFYdWAwJmFmNmdIVXVTKU9jQGlQaX1G
d2Y/K2gqbUYleTBAU3tLViZBQXBkWVNlc1VRI29NeSRBYHgqCnpxfnlqTks7Y2ReRkhmSXo+K2t1
UXY2dlI5JWI+OEkwb1dacyFVJGElOVJhNjAmQzZGb0E9MkZ6Jm47UXxENmEzOAp6X2B0eD1kfU8o
U3Y1QVNmOyFzJDhUd0tRMDdiZ1hrbTkxckU+cztMMmpLOE1RQ01HOEdHdHJ0VWF7WHRJMX5UO3sK
ejNhJE1RR2QzdWp6fl9KWTtPSk0+UGdralZgfXJIYXZ4SzBWdml4UXJTVSs2VXIyKlp3Ki04WWN6
PFRgJTttSjI3CnpkM2s0aWlqKnowam5oakF5JilYKmtzO29UbVdVbjlCNWBecW1LVX58ZGYqVnZl
b0kjd3pxPVNMd0dvZSEqa25uUwp6U2kzdHZ6V3xGY3ZiNHpONi07dEQkVVNSV3Qpcl9vXng+QUgl
aVlhV243ckpBRHkqN2hBaVQ8Yl81e3xmWDZRTUEKejNOb1E9KnRfbT1OTHp0fTVgaFY7cCsmT3Js
d3BhZCU9alhDP0pWVi1CQTdePDhucGp2d0JEXks+OEFCezcpbUNqCnotdTx2T24pSE9naGdrVCE9
KWUtZSE+PWYwODhFKE0/SmJ2VGpgT1psYT8zWH4qRndGSFdMXjxtTyE/UEByYzZWPgp6Q05QRWxt
Yk0/NXpPbm54TDdObm0tciU+ZWVhbS1pbGg1VGR7MHdtP2FLbCZXdTxQVmVad2pjRl9BOG8tNl4j
PVMKek4zI3NQRmdfam1gXzJXPHEoU1E0IVl1RloraGlAbWYram4zI1VKZF4hYHlYYntnSUFvezxz
cyZPZ0VUbG8lSXxyCnpSKU9UUmlFQlQoeXZRSCZiY1REcldSZXl1e193KTtXTXklI2xOZHlCP319
Vz1AK0praGt2MEVkb0szXlVga25JOAp6Rj9sJl9kQUJYMlI5VTsrQD4+PG1RZU8lXlR6bH1CPis9
JWZyVUNBXj5ZWnZBZSNtTDdzWWIkKD9md2FiYEMpNWcKektiPmZ2PyohbEYpbXg5OTd1UW59aXc4
JShBMnZEekNpQDJMX3l7U3R5ODl5RUQ0V1B8bjdIZCFBQTEoSVZgU188CnoodWwjI3c8Iys/RG49
QilSa3syNFVVfnQwTnUjZFk4VyFSSGAzKDRMR097d3VkfHY8RC1UR1pKeF4hQk5UZHBZcAp6dWZR
Z2FjdzE2ODxIRjAhT0JoS2A4X28pdD5mSlBxP1Q8Rks3RDBEamhxMnZxc1ZyJk9Wb097YiZrUi1D
Ty1LdXcKem1jQD5oU3JHYFZzYnRFXz8pYmVpQGg9Z3ctRGtqPVNwVGpeb2V0fVF6Z29DelZvRX0+
PGpTeUwrTVIkYSY3emg1CnoyWFl1cFpoQHl+Q1FrdF9Sfj5rVSstfFlZb0VNJXZTM3dRazZeUXxU
NyFJfnUtangpJHY7QD5rO0h3SD1yMDM9MQp6VTNvNk09c1o2PGh9YlhTbFN7WCpTbnVhWEd+cX5j
MmY+SFJhQGsrVVcoSjIjWXQ4TDZWdFdeYDc3fnN2SHpjSmIKem0lfmwxbVYtS1IoSlMmeilnIUs/
PD92KUQzKW1+SjtGOzE/QDxgZCE3d2Q9OW1aJmBwdE5ISEAofWRLLXs9SlppCno1c1I5UXh8SEla
ekBzbj43ZWpPR18mQm1meTM/fEt4KWR6dDFLVylhT2JRMkFoRnIqOW9FcURJanpMK00wRXYwIQp6
WE1WaHxaRXx5TT54clJIMSZ7TTtleV42TVc+NFZkaEFGO3s4ZTN4Zmk8cVYyaGo/PlNPOWJYTT9W
SE17RDtKRzcKenUqVHwkaChAX3hUT3JIM2hqPkIlJWF5X0l7PyVKUGU9NDdoVHlTe29jKTQ8OGZf
WXdtTCpnIVMmUjMySGJ7TigpCnpXKT44WjR2TmIwVUJSQT4tSWRTRTJmRE4wLXU4PmxeMTBtZ2Bx
PWVlJD8kUVBqT3UwSyF3MjFzK2Q9NjtDIW53Owp6TntmeDc1TCt+dU1TVzU5WismSEAxazR+PFJX
LWZkK1JtezVfRWNvRWpidEQ/RnxsckFwcTlERlI2dG87dVV9N0EKekNvZiZmNjY9T0Z1Vy1qJjFe
QEFUWUVpR0hyPTg0V2BEQnM/X3ErWktabmRjI3ItaHU4RU07eClgbXlZdmJrR2VSCnpOc1JANG1T
X3RwPWgtQTM8UE8jflU9VTtLTUI+alFeaGQ4JEkoSUJeQU17Y3xfZClGZ2BTJGpIXndAa2traWFB
PAp6RGI0QSkoeVY+Ji1zO3VeMHxUVkZgN1RZZzRHV0Bad3hidz1qKm43KTNxYjR+LVg2YDhIaj01
O1haKXRxIWBpUG0KentPa0VgK3p8c3FMMzdQVVJMQGl6OyFZOSRnVWFiWSlmPU9rby0pTlZIZVhZ
VjI3KUp9V35PUHc/fks7TE8+NC1gCnpGN0FFV3JII2QjUTx3OW1uX3ImPmVOcGI0ZVZgTWE8K3x0
KF5vQjlVdUR2Xm1XPjtMdSpvZUh1K19CfmoqRTFmeAp6OVNaPVd4V2UjTWkwVmZEKFBkQF4hS0Q2
YUJMYCM1PTspWl97TGstXkxGcXxKN3FNblgxdTx2fDVXaF9SUGFCXiYKeiNiNEpeRmNCT29IVkQr
ZmdDTElEX1h2bCpmKzJaQXVrXzVPR2VZTU1XUyNASnhkRih7a1dZdU9eK1orbWg1emJnCnowbXlS
TDJNcT5+SjV3LThMbD8yO2M9YiRBZUtwbExKazMxfFpXZSpXNVd8PyV0VHApbm13QStOZCp9RHcj
N292Qwp6NXY+dGo7VmluIVphQVAoNzFrYiZzXyQmP1lWUU1Ia3E/YVlTempOeVAwRXQ/LUs2PDU7
Q1Y8eGBaWEluRnowNVgKemo9OzZYdmdYQ2EmPGp+TjckQ1B4bGRYKzVkdSZLdShObGRMcjQ2R2BO
NUA7ZDckdFZje31Aal9EN3x6XmNxd0hLCnpTQCRPKTtlOEc+K0B1Z2w0aGRCTz5zfGlodm5YKXhs
djV7OFFlJkh5OHBAKmw3e2JlR0RlakpDPXdPdjRtdnRpbwp6PEY5YV8ya1lDdmx4N14rbyVnMkVK
NSN2Zl9YUVpUZHZPP0NCTWB8I0wzV3ZyPV4/byNePmdBZGdTRSo5UXZZbWQKens4WkQlZk5YTEh3
KUJWV1FIRGN4Sztuais2SFA7YUdRdjlJezdgWj9EJTxRPCpKQEJiVV5meHJwdD9Vfk1+e2tpCnpe
MSV6LS17KChwekxRXjVIS0x3PiZNK3lwQzw0bXMhITYqOEpHXjVaNjdXYDUrJE8zIWk4REZwYi1S
fTBSKmlCJQp6M0YwSWEjUT03eWJ0fT09en47UGVMS3F9YzBWZGtRbDEhXi1Sdz4+bCExRHFvNTIr
UlJtbzhVZ2l8XjdyLTl6ZFcKejdNODRncihlVFFsb2JFQyRCVmN5STUxeDk9OzZ+NkppNnZUS1I/
JCM/YiR2eXYqd1RRY0FUbk5vfHEpYmZyN2kjCnpKJFkmSzJEYyg7MkktdVFqIXc8e01MNylDMExg
YiF4aiVjeF9zdXJMY2tOaXo3aFFiZlVwN3kzYWJpekxIV3dCYQp6dG9IYDRxWmBVSyM7T0IrXkJj
MHNkKkg8UG5IdT01NDlNIyh7UWpWa3slIzMyUCVDQ3YxKFh3N1A8I3l6UkA/ciYKcCk4T0AqXloh
OUxeMW9tSXtDX3MlcHxhaUhSaEI2fXllYEUkRmc0d35DM2hZQHwxVztUWjg4Nz0KCmxpdGVyYWwg
MApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9wLnBuZyBi
L2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9wLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi40ZGJmZGRlNzY3NDViNzEx
ZDY0YThiM2IzNDM2NzRiMGRlOTUzMTM0CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAxODQxNAp6
Y21lSWFnPEk2bTdlQmd5aD5DKVcwI1lLV2t8TiNHQT5FQzFjUSp6b2h7eiZ+dmBFKnxvci1rVihq
V34+RVZWNFAKemEwa0Q/PVJXc094YzVGRUE5cz0yX25iTCU7JnNsUEd3VVorVyFYRW9DfmlSQGtV
UjJuUXRBKjB0fVg8RV94e0ZwCnpGY1A/fUFgRWBxYmRsM0BoZF92MHVVPEdFJmJieX5AUjVoS3U3
YCVSbTUyOG1IJW99T3c+UGAzbGZBcTc4eThEPAp6WEUqRGw5YnBPeGdjYyQlXi05d3hkMjd9P2ZD
YDsqeHJmbnFSNnx2Kkk0IS02YG8lakRCS2Fha2x8K3M/cyh6a2gKejFeMnlUdiE9UzdUU3dOY2so
fUlxNDxpR0N0Yl8jWjZOYkFIRlVaWiFDXjIpNmxTcyRQekBYcWxoTXNvbWBxTGRhCnpfbkR0ND8l
Ym4zeEczfjl3ITMlaGJMJCRSSn12fGpAfWZWMDdfZXh7Y2EwU01fVTZDJHwwTTlBMXBicjJlLWlr
QQp6Tj9fKi1CY1luaD09e1FwKk9wbXJgKUI5LWV2ISopcEpsWSlHUko8YENjMWxidVhBWm40IVpk
MXk7PG8qJWZacn4KejQ+QzxrTEx7OUF7b1plRWJ8aDtqKSViJi1NbypVb214JjJZMihGfGxQVXA+
PmstWW99Z3tacyZFbDxsVjF3e29kCnpXQnZVN0dPb0JkU1UyalJhWTJBNFQhU2NGNjF3Yk8jfntD
OEFweTB9Z1BDZGp7VGlKZSRAdFJHJlFvMkxUVSNrRAp6bmBtJUtRfm10QHJgcmNDKkZyTD1MYD8+
fUY/UyhiWjc3V1dZc1ZzX3tpZGRnS3x2fG5HcnNfP21OIXMqemdtWnAKenJkVk9kN35oY1FXUVA0
RG5mPTVOeWdRdjNJezc5bT1VdThXXip8cCtEKD0tM2BiY1FnPD59STt0OCYzfWQodHlBCnohOVU/
cnVVK0ZNKSNUO2xIQSpjY1ZsMzFiRURZMHE0QVo0diQyOVFeI3FgNlNzQk43UFdqZStQKiFIeWhv
K0daUQp6YFBNSTdQS1VOJUF4dFhZYkd0fkdZPn1EcmlLMTQ4YDRRKiYmLWUzJkgrNT5PPCs3WkxY
Wm84KUx9T3ZsZ156YCoKenk0b3U5VmhiUGRyeUtLQlJvZ2xIN2FWejIqe2pHVjllR3I0aWFTXjl8
N142Mmt7S245ZDx5LVQ9MDtPSVVocmVTCnpjeVpBVDl9Zm9+aS1aM1RDKz1GTG1ZT2xWbCFxdDNz
MVExYHB7QD5GKUs8QDhZPHRmM09qfDdgeWFqTXtqV25iSgp6OX5WYXtpQ2FGRmBTb1orcDAkbHJ0
SXliM3F9Q2Q3PyhmYWBqcz93Ml9OTjdXS1A/UVozJXwlbjMpT3d3VDMwS3AKem0hJSNtO3F+Q1Eq
TmBwWF57JXYmbCNRKE5zKCR0JElee0gkXyFUI1c3V2l1KithWGA9RHd5KHxnR0VEMEU2eSVJCnpV
KC1sMDNuO2U4NVF9KmU5MGQ3JF9lc2M7WERuPChUUTlCRjdrJF4oLSMja207Wl48VjdwJlVtZ2Ne
ITZiN2Y0TAp6aiZyY3BffVFxVFo1Pn1JWFhpWVVubzNtVVVefWA9dCl4Rldsan0qWHZgRzlJOz8r
ak8zU3JoIyk2UkNjPk8paSMKemxHIWhlWnJJJmA8el8jbiYyenJncSlXSFp1dCVvQmgjMDJAdm4o
V0ZuZThzbzdsPDAyVjQoJmI0eFkhRjJIZVI1Cno5UVk4b2ghJEx6K3MqVUVnI0RyaENffWVBUXNx
P21VZy1UPTBfdUg1RlUoV2RUPX1se1JaVWdCenxCfmd2Nzw8NAp6R3UyZHZiQGJMKWB4bHNTJl9s
PnE2V31jSiE9cXU+OCE9RThQeE5vO0x+WXx8KXZZfGNyNTRgUlA9ZHM3IVpWcHQKent5S0orQ2My
SXI0ckJFRylrckA3PmY5R0l2QyVefnJobEg0Z3kzcWNRO2lDNzgwTEdNYzt1fnFQSTVVazNXOXl4
CnpMVFp+aVhGI0xFRXokNEtiUUdhZ28+ZCM7Xj9iLXU/NmhZfHdVQWhBdl50Q3RaOFN2fjVfTH5r
OTRBck5wZ15kJgp6UipmKERsNDxOKE0wNX5zak9OYyR5LSRxPGFTbkVJN0khcVlfK3RpNUQ3LWkw
Z35zaENXM2I2VFFsQml8ZFYyZEIKenNqNHthYnl9V14yfWF3OTZYajV3QjE/Pjt6aXAoakNHejk9
Zj9tRGhsMHFZfFdAPmdNRlVgVEU7QnZOSG4pKElZCnppd0drNSRgbDl4Wl94cVNNcHwpakw0VUhL
NW5nPko2YjI8QVdAJDF2TEF1QFEqbipaRmBjMj0lYGI9LTAmTmV3bAp6PG9HSTVLJVJQQkJRQDFm
NHd0O04tamw5N1NncDM1YENifWBWPTRkWHtyeGtkWFFrJDh6eStXQGNYZVF5ViQ+N3EKem1vc0po
I2cpOVAmT1ErR2xeZClyVk5TX0JEa2xFWmoqMHdeYEkkfDg9V1I8MFRWbEM/anZDQVNHNkRAfnE2
KX19CnpQJE4zeWpmTGFXKGFWLXJrUDtHSCFqYyZLP0VZY0NJal5NYi1vJDZKXk9LfDYrfVghUkFf
YGpxLXZ5aVB7O0haagp6aGEyLVpzTGJtJk9CNzVLdHZOYkROK2BqIVEyYWBCR2A3MFkjR1NNXnpC
TlZBY1VGTlpaZWwkNTR+KTh1RSlhdkUKemU0dypBbTNhN312Z2M1SjxYMSFRWkhTa1FETmNzMldz
SGVRR21AIXNzZzgxYXw0Zn5RUDRTYllRaVN1fHZqUyFoCnprRU55PnlUfkt0SlRIODdwc0hCb19v
NWpnPG07VmxxQDE/XjB0TVJpKlBkPiVwfHRtd193WTdqOWpPJUBycVpQcAp6IT99K1l2fHRhRW09
MmQ1P0dJQ3czUHZBQkh0azh7Sy0leD53bWZ3PU13NFRZVkhuJX0rSmx1e0tMJllpaFd6OTkKeloz
UDxzZld6NmhTWE51RG8rcT18c3JpYzkzPzdiYGM7ZX42PGtXdFNaalF3ZEdeOzxaKnxWeShkcnA5
MENaYlVACnohKW9nZE87OWY4Xk8yNDtJfGdXN1ItI2M8TUF0Jjc9KWpEPi1MQTNkY0xzOT5GVj1l
RjM8SEA8ISslRTxQWndIZgp6N30lWkUpYzczQDhlPFJhMmtlNCNVbE5ueGlOQiNRM0F0REpYSzVe
TyVfT1YzQGtDSWQxOTRQVGBFNm80X2MrV14Kem9pMFpJPHh9fFlQYzt7d1NPeDRGcU00PTNtPDde
RmgpWVBHUE8yRi1xKjVHTSYlfmp9QVdNclRkZDJjVStvNFpKCnp1WlM5TmBwJWJ2S0kpPj1UXjFF
dk5xPWA1cmdrfHF5JX1BS1BHJklpJjVVeDZzR3hoT1htRCVNXkYkSEh6c19BIQp6PUgtaTxSZE8q
SUQ5QmJjaXtmeH02JnhgUmo2LWhUbkMkYFk7O2x7JkZ6OzE2elFXLV9rSkU1JXlmS30lVzByLXkK
ekhlTEUzQWl5bj0ld09JWEpKQUlAeTA1KChQSVd7fGdKdEpkdVMyTEpUWDFEUTlAdXdtdG0ofURK
UzhPU1FybDgjCnopQUUpcDlpejFMXmgpRHxTOXc9JTtgTG5TdlpXWFg7WHF7V2dIPj9tXyNFTClm
b093ZTZIY0F8OFV7cyRFdXFaZwp6dTxibU9OdExAZ0RsYCokKFQlNCVvLSh5SVBhJlZWdWFTUDBl
SEFTJHJ0NlhBUkpUaTRKQ012U0smP0trOTxhJkkKelNjT3RAXmV7QmtEPzJQZ3ZtQjtHNi1RdWg7
ST8jMW5kMTFXdU1zMjE8N2FZREIxd0NBaWNuc0JkKypIKF9ANFhMCnpGamZXXzhjTjV5JlozYm9Q
eTE1WWU3fT1KSTVvajQxbSljWWhsN15SVn1BKEF2WHJmSzx7OFBnaSg8em5XMmU/QAp6WUxGajRw
cXQxcGJLP188bWQhMDc7dUpTblgqPH5BWCtQM1QrK3Y/fDd9Q20wPVBgOElaRThBPGBSUVRmUDVJ
ZzMKek1ASlEjKUV3dXBydDdCO1VUe0habUIxUjNzQU1qS2BQeUJJNlM5SFdqNnh+c0h7cHJRaTl7
dUp1N3M7cXJzbEA3Cno0Tn1paWg+cEQwdTIjN1lSKkBDdSNJZ3BTb3dLWU0xeW9VR3lePmRWeUx7
N3phMXkxXj5TIUItXl4/eC0mITlaewp6MGZ4cmxLcHB8fXFeZERMa19nO3IkYTNSSVdSe2Z8aGts
IUpTMW08UERedXRjUzVxVTMyRT8rZloxXkEzPDNZa2cKelRYNCZeekR5Rkx2a299byZsLUgpdTQh
TiV5eHk5fkliS2Eranc7WSVCUzBVS1VIcEtQa0pzUmE0MUVNb3Vjd31uCnpaRGJ0dSROVFMxeCpi
T3skYldNNWU9dUxoUXUqciNDNjhpV2pzRTt4clo8fl5HSShDP0drQVg0e2VYUT9iflR3OQp6PDct
VkZSblJCJkBOckdaZFB9bzxXRlRgekd4bnJvbHFQQzkkbl5nbEtxclI2dCROMzItM1F7VzdtYEVX
O3I5KE4KeiR5eyhSWnxgLXMwZz9Qe3h1K09CSmppRmQ1PWlVQ258OSRxJDZzeDMxNCsraEVmV30/
KXZrU0FHKkFpQi1JYzQ2CnpicT43bnclYn5uZUc0JXEwMm4oY2wrJWw3QiFxUX5jIXdwTT1RRHlS
TSVzcE9SJnNRQ1RaMl5rYkooO0pKbGQ0bgp6S1NPKlEocz5KKWtrZGxtPS1yTUdoTzJocUpMfXI5
cGdlU0o3KE94MmNRfko9KlVfT2h0Ym1se3hSZnJnPFgqTTUKemZyeEEwKWVYVVUqOzg7QiQhQXBq
NlBYYE0kIUN4PDh2KWwodENLanB4dXtVfjQtfVZ3UUo7YE1mXyM7M2hgZFhsCnpFZn1teVkhbmN5
QVI/e0smQlM9Vz9Edlp7P0khbE5NSWlEdE4wU19hRHRPPD5zSklgaXE4dENkMnRLRERlP1pkQAp6
JihsNmd2ZlNYKDVKfilPZShsNGBLenI3JTY8Rk5zUkpWYiNlMyllMiNebjY3I01qRn5mRihwSjBi
JUQ/JHpqWXUKentyKkh2ODNQTj1WX2ppMkxtcHt+SSY3OTBpNE1mbkpvejJJI2Q9MEw+M2FMa2t1
ekF+I3BOQj0pVGVOPnVGUSp0CnpFTjBLI1lON1pIVCE8U2BBWGlCeXs4Z0lSPUleR2dedEwjTEsr
QTJuI3UqUHpZajw0OHs8e3wzVlF6TlNwSn5SJgp6UjwkWTBTdEwzR0pVZTR9KH0tbWNaSFJjI1Uw
cmJzZkl+cmIlbGNYbVB2VnBmRGBpP3dDJVNWODB2fHczdCR7T3kKenNVKzlSNWYtI1JPe3N4cSlA
ekdxdzd6a0FoWD91YXdnb3FBeSNleyteZitQZCo9KUB6WUlfc0NfRDt5MW1sO0JQCnpkNHR2VCMj
QEBgMy1gUy1ILVReM2hTY2pEISNhcUBAOHRxRzVQR34me00pfnAqJjFIUURrX1hidTs+azJZbHtg
ewp6PSgxazFEe34hfWtVeHMwTGtVcTdZbjRmQCg+eiUmdHdLRSRfaXJMV0QxTmZVcjtkVlBnQnRH
YjhvUWA0YlgjU1EKejgoN2ZQMCl6O1M8S2FtflppR3Apd3hScW0qKkwzKWRuTzxBT0YpdGFrbzxJ
b2V0e1ptKzA7NzRse0Naans9OTF6CnpHTFV+RCNIX21Qd2pvNXdBeWpBZihiY2tSSTNCXmVfVnk9
NF8zc1ZWenQ9PkMmNn4xZStMQCRiPFR9dFNTdWZ8SQp6WmtWSiUhYVdHNStkYlZEU0d4ZTUqJSRW
Mj80Q3JgKy1mdGNeS09rdT8hNXNhcDlFOStPX0lJUzZAPSQxN1E0JGIKekEzS145O0hBVHBgKSkk
V1lrX2RTKX5AalFPPXMlYWM0JTMlPTBBNFFPWm00IU4rMjBHKUxYQDYmM1VaTFgpLSZVCnpWSSRs
P3IkQl9YdE00bCQ8WCZfTz95MkRtdVFGMXRYc3RUZUcxNURtcTEqT3VGQnVARm56U1ZsY19SNVZW
ZlVFZgp6Qz5IdENYdHJQLUc3Uk40JFpaS3o5NFB6fHBWRkVwZnsyeHYyVlE1VWhCYUZ8ckZzcTZS
SnlfWHBrWntiO05VdGUKem9DMGptV1hySSlVemRCRDl0aUNiRStJYXVlUSQmKD1jbTU5cFgpPEsy
SntIXnJXK1NNI01JK1NpUiRqb19tc0xeCno4JG5rX01MJm0yVWJzSSNnI1FWY3ZpLUFlRlZWbV8p
KGh3V0pCP1UxbFkrRTdsYD44TDUkTXd7QFRoR3BBMGJtQAp6QDcmJD81Zlk7SXV8P3VucU9wRUA3
Q1FFdWxjNjR6V35UQjUwU1E9fTFyWFpJYyk4aldeVUJiKCF8YiY2Vio4KVMKejFAR3hUbUNIKHtu
LXZaXjllT0RGOEVrWld0YEdVaXtmISE9clIoWkwpT1RUeHBsYXNJdVFHO1JXcnUldmx4b1I9Cnpz
dmBkUDV3e1NVd3kkT2lHMWxMOzRHOV5jRF5ZYkopczdsVS1iWXB9REx7am9vZWgrJnUwY0xLVF9l
NUtAMkZ2QQp6e1hocUxjI05hJEw7eSpxM0h8Vyl6SzZldXgjVlRuX0QwKVNgd14rKndxNEghKDI4
MWdpXlF2MXdfWGVVOEphOWcKem93Q2RoQXtVPiM1S2EmaFoqP24/V0l2MG9md0UjeDI2cVl2MnB9
WntVfjNyQE9HQXZGQndQXiVjI1g0RCE7XmBUCnpGS3s1ZDstPX1RaEErSiQwK2NhN2NxQWkxQEU/
aXRjWThxeFg8LTZ0YG49aCRMfE1VbzJ6PTAqN31heSsxQSROaQp6SFFZVUN1ViNsa3R7VyhEenxC
NW84cno5fXtZVUpUWCojVzs+UHQ4WiFOMVdLJEdUQmopciROcT9hdXVTKG4xOE4KenowWDNFI0t7
OHtiO0k1WGU3XzRaV2RfWHR3blBKLVNoflBxYHhmeUhOWGJLNyFZYU5leTdedGR4YTJvRjt3PEhY
Cno9aykqajI3dzRZREtZaHJBNTsxSUV5JUQ3VElFcmQyUTJqZXt2ZmlUIXxETUBocVdCVHVnczt6
X3krNjVUJjxTNQp6SWBKXmpuRXY9Jl4xR1dqNUhDczdVa0RgalJUUEArTzMrelJEUXA0PkJvSUBN
WW9yZDJZR2RDJkY5RWs8R254cyQKejM7OE12N355c0NRQmAxcFRnYWJEcSN6Xk8rXzska018biEl
QXh8RUdaRj9NcDxDWkR2QSV5bE5Ba2VlblZxO35pCnpDRjlCe0trWXlEQDdXOzAxdFFabD89NV4z
T0UzYV9XTkxhTzQqTFdMUVlCXmp0SThAKWBgSmlNOExRJSUxVU1iaAp6elB6ZC1TbzlRQGJ5cUJQ
UXloTTJaQXxaWGh6MjVnYzY5WXt5akIqQyNafGB0WmIyMWNlR01gfTV7Zl5hTkt4NE4KejZnYUds
YjJReTJwUUNVdmQ+OyhrP1VHP2NmT2FoOG1GXnVHPDNQQSVPQEcxaUJoUFF1WHJPM2NeVDhQdSpA
aiUkCnorcmlUaExoJWd9Pz5eUGEyMyRKPUU9PFYqJWZyWHd1STtYdEBeK3UzJTB6KU1vQmxVdStZ
VEpoRSpnWG8kWDVYJQp6OVppRD0+OzZDK0AtVj8wdGRKSll5U2dQPS1FP1ZPVjR0XmBwP1ljZUFn
MThoPWE0c1NAWFp5ZCV1SmhaNkNtU08KeldYb0dORXVSM3E9cXJJbEZpcFAwaGpkWl9IdTRYJWFh
bSRQUD9EflY1YyhlQD5hYHY1dTdKSy1oWnE/b2chXmlOCnprUkgjaTI8fUElKmYrclh6bHFiWExk
a0F8UkkpbW1rOTQ1UnVEZmExQSsreDJZYER7Vk0wNVVldU1Gaih7d19hbwp6QVlZalAlUCZoWCZz
dUFzbVUqNE5HZiFrN2tZUkR0VXRZcT5ZYkFAJShHKnVvYTBkKWBZPGslOHlJU1VQM19+RUQKemNZ
YEJhczs7KjUrez9GMmoyNjtUMSUjb0BvanxTKXcpOSo/U316VVEmKCRgV1ZYdHFxMExpWF5ASV98
ME1DU0RoCnprWEZhcz5sS0QpSFlHe3BicWNgMDs/fm9hbTxwOSVRMVZ5PFdZXnI7dnYhdylnIUo5
aEVsSF9+KThyRTF8MWxpTgp6KGdTQGlKWGJoeTZIKV41P3k2Q2VYbHA4OXMtO2NofEl8d2dCeE0o
Y2VtKC02R0dydH1BKH4/b002aigtSyZYeyUKenphTXBJVTJAI0hTUzspWmNKcHNLI1YwREdQRmdz
RkUkKUBMP3ExRH57R2RWMV4lP2phfEtxRSUreUJPNyFYRTB0Cno3P3BePVNAXiQoZ2VVPSl2Z2pB
U1g3JlAqdlZ2KF5UPTVBYCY/US1jalloMnpFYkBaJXg9aFVSYW5+VWhBejxiMAp6JjI0M29QRU4z
VW9TYmx5UyYoYzNYSGA3JnN8UTR9a0pJaWdiM1RGNDI0MnwkQlphbiNGbUZrK0piKyVTaGF8ZD8K
emtWOFBWMnliRVomRnxNczNOUX5aVFRmVUhGd0E/dmpIaVoxVUs5YyM+KkZZaGlNJTNmT0lLb1Fr
V0BGdG9lWHc9Cnp6Z2wrV28jaUFvTkV3NnhYP3FQRmQqckp5KlJmYHxTOSo+fFZnSlYhcmU8YVp3
KlU+Y3J2K1dCLXZOTUtrP0B4Xgp6TFZvRXVnSz1GVS1lT3N1TC1afDMyPyN6X21od31HU1YzWUlB
WUh+V0dKSX0mLUJmSFNhOTV5OWdteUxHOVR4YmgKemo8S2N5UX5mKCFoe0sxTHc/IyFyZWxEQTU8
JCM/P21KVW1JQWk2JGFySWxMUyp3OHAlVT9IUzFNREUwUHw5JUFvCnphOzFDd2FRWXxJSEBwRUlS
KFlCbjRZRl9VMDBeJjgrcmU0T0tOZChrS1hfcChAI2VveFFUYGh9VFhAcH11KFloKAp6XjtRaSho
QGJvLWZLN35IUGRYVDh6JkNVPCgpeyZDMEBBVnBxfVR7X0d4WlFEVHUxaz1NdUFQZzRzSzx9RH5r
YEEKenhDWXxMdTM9Qjs9KHsoNjt1dHA7QlZJSGwtRyNYNVUlfkd8NWtWTD1hMnhNaFBlJmdBUVYx
a1IyQjNKTWpab3A3CnpsIUxEOCp5ViF2czdsdnJaYipeOWF3cTE3eGJqYHlyI0U2T0J6cDlUPys1
e1hUUitzWF4odnVEVEVlYUpvQygkbgp6YVJnRDFKWHA5YTJjQD5eSSktXk50S1ZWRk5eNylMRll5
Rks0JGY1RCR6bTVlbV9FNC1oeSE8Y05MSlBvYjtiM20KemkwJWA5Y24xUld5OEl0PiExVUdERWI+
T1RoWWFrUEVacSVUeXI4N3YxWnc7c2duVk5yTGVZMmBxQSVVZkNMWCElCnpVM1B7KColTDUycH4y
flYyMTRBKkI7cC1Ye3R3UiMoOGdZcThDd3h+ZTQ4IUsqKzsjdWZOMDNfZ1I1dyZAQ1RpZgp6Sj1e
LUZVe3E0RUl5eG1MT0NJTkpTSE1zSzFXKWBoejx9QGktIUI9MnRzZzt0Y24qREBxTUBFcnNmUSE8
YmE5dlYKeik/Rn5hSmk5PEkkIWBpczNAZ2coPGJ8LXBtI0dnS0RmJU1DSiNQKlhrT2goeGFrRylO
YTx5I1NuPC0qa0BmMGtzCnpVXjIrUyZDcmkzY3NmckhAeDYrV0I3USNjZWs2T041YHdOZ3k3T2c+
OH1MMiVHVlcpYmVzVE9GY0F2dSFNNlExJgp6MURhOVNxMDg8X0l3Sm9CcUwtPisoTHMtMElYNEBw
cHdpTHhobyQjVlh6O0c4MFFqNUNYTUUybEZeSWl8S1UlPz0KemZlbWtucyZSMm5IUn5EJCR4KGU2
YWA4RSFFbk9sMWBvbjxmQy1lWn01OGxTciFSO2l4IXRpQWgxZipCJnpSMiFfCno8dj9UYSl8M2pk
ITtVfDlMaztxQmc9QV4lWF5ZNCR3WkdYdWsoRU0tU2sjTTwyOVVRNVlJeyUoWk8tPVBlUiRJegp6
JEVmSU8tMFZ+PU16MSk2T1B7N2UpUThjcmJeZ3tPMFYqMSp5RUdIY2xYOFk9aihPd1l1eSNLQHkr
bCYtJF5KVzwKemM3WmhfS3UqM3VQSmN6bCUxbnxaQHx5MzRRM0M2ODdldj9JYlQ4KiY9UVA3bGFx
MnNZd156KWhwVT9RO3FrN1AkCnpYNzkkQjhmNWRRTCg3I1Y1OXlOJGhwNX0xPCglMjZiNT5AUiU5
TlgqbmZoTk5yUU8mLTtRMk15dWRHTUJgSjs4WQp6TlhERjZxI247fksjeGI/e1lhV0ktXkk2clo4
IW0/N0lGXzlaQk5mbEZXWDEpQFBKSWxjSVgwc2hPI3VZVVBMNC0Kejh8ZSlIJGY+ODhedjZGMCQt
VUA2SFQ3QC13R3VTIXU/e3hJT0EqYiQjPWFvPnBgXk8hbyV2fHVNO3FBK0E7Mlg0CnpiJng+c1NJ
IW5adGlEZDV4ZTc9VSR6emxnaUBBcyV7PzUqUjctI2U5aGtFZGk9PVpDb0tlWFVwcEx9MzlqIU57
Ugp6ezhUWGRHZk9icTFvSys+aWM0UC1tcFZeKCtqcXU8bTNjNFBsfk9gflVGR3diWktFOHg0fGdT
Slp3PUMwZFF4eyoKeng2OUdQXmY4ZTxVbVMxZWlWSmRiTkFpUypmWlgtISpgbUZWS3xVXyFyOFVV
O1VCV3hvd3F8T2FnZH0qaS1jQ09oCnp0UktXN1lqO3wyPjNzQF8jezB+Rmpub0NWUy04UFMkZ2xv
JFRieEF+JTU3dHdJZlcle0JyWXg/KUcqS2MldXstZwp6b2NkRVorUm5MV0JNdEleNzkzX21aTWYx
MGNKI0JCVStANUFMI0dZJWpGQEN8TTVWPU48JU1uPzJwUmhNcEdlaEcKekR+cnQ0bnRXUX43JGcp
MmlBZUozKURFZGdmUkUxbkBHZ00xbGR5PkVqWVczUUo+TzZWY1I0QEIkIWw2UTRmXi0mCno1S1gk
a0ojZ3FqWSlrJGZjczhFKlYjPUhxZWowb2RAOU9UTVQqM3UqRjxEK3dWPn1ZNkZxLTt0eSo5UHxZ
OE4oTwp6N3FAMFYpaWhRM00tQTBMOFJBPj4mWGB6TGkjbmAqJXhIekkkbGAzfU9TRUNFQjlvcVNG
JjExYF5lRilTXzU8b0QKenpkfW9BeUk8bWxkViQzbm58bTl3djFBMipSe0RSQmg2dEY/Oz47VEk4
Ymg8ajhqR2ZXVzNQdlRnZ3hYKmpXeDx7CnpkcWQ9aW0kdm0mTEN7RDU8TFN8UmReWjhBWX14Q2Ri
NnRHVkl9ITQzTFI1QjJRc0BXYzRZKjxOITZCOVFvN180ewp6eXxMRGUweVhLMmRwZyk/Y0drUWh2
aUFQSS09aShOJEpGZU5eI050TCVKSEUxWXR0YzBiTyU+Kip7IzBPcSN0dikKeiNtMHEhNnhPcGFT
bGMheHQzJmg+VWY1Sz1XX3taOD9RMiN1cm96aEZJS0FyWnxHbz1BdDdJSW1meSg+LV5SKCZVCnor
OWVgVGl0X2lpWnxXXl9rJUBRc25HNTBKUldfYyUqQihVX1QmelNSYFVkP0FheDUmSlhzT3g1Qzk3
ZGRuKHNPfAp6PGZveyZoWklHV3VJM25sZzNfSXZKO056TitETiZJJWwwYSgjY3QjbyM+bWBpMUo/
YVhGT2h+e0IhfGsrZSk1X1UKeiVYMWltQyp6VnwxKmw7RXRjUWV3VEVPcnE3NGF0QWh+OzdWZVZM
X2hiKT58WHZgN0JnQE1ufXNqVHtqRVBvcDJDCnpJXyRPOEApKHt1Pjc2UV8oUmViTnBIU1o+fEcq
RWI1I3J7QklfWGpwaVZBalRofSZaRCkzbjh9bDRTNytkKj0jUwp6QXYmWVVHckV2aCQhX2JiV3FY
TkJFYi1xPzgmQmVRQiZSd1ZBQkI3ZFJmSTReKmNBNjE8Pj44VDxtR25LJEFTeUEKemE9M0BRVVBf
fGJKeDhKZ0dPRHRrNl88NmB7IVBJVjlqMGUhZjBzYiNgcVo2T3lLVjdvYTJfVCUtbXgybzRwV1NR
Cnp0aGo+Zm97bFVyblA1ZGBnKSo9eTFaSURTJV80a3lWWUpBU2dyXik7QGBHezFscns1bWQhb2x6
PVBKYH07cnZzVwp6bll3Sz1zPG1SU3dZNShrUyNWKClwNHJ3bTdOR30yeXFfdk5qezktPHArSmhD
X2xicWx3b3Yqa2JkKTk8TnchYDgKenB6OGghSFBLYS0tdEBhZipMITI2KHtOSHhNXyVVISlQZjFG
eyNacHNVKUx+OEtVIyZ1bGRuXy1OOUcmOU5MYFV4CnpjU3t5SXROZW5MSTxlUTV4PDZnd2B+cmok
b1cxZDs3UylSR1JCbFd+eFZqejk5PF4lJSRRe14/eEJiIz0qaSNxJQp6KVhKNXwoRXtHVEojekx1
SkdhfTIwcW1iT3JzQnxMamZWUTtoa1lSYFF4WkBCPi0/byNPd3toQFh7IzQjX3UmXm4KemY2d0lj
ViMycFBgZzYwSHNUUlY3Q2lxKVVgUEk2cFhLNm59SHJNQzBkIVJ3e2xfbXpoOWtpdyhaelFrYW5h
TWx5CnpreTJEWlVQbU1WSX08VGB4SUBSclJ5Mi1PUDEwWUNER1o9NCQhUUM8eVlpYD4oOGp7TmBS
SEp6VX5jN2B7eW5fYwp6U0c3Nj4jdyhaUS1wQntXJTY1UGMwKU8yJDZaY0UpNnMwT1peemlAWG8q
fk1DYjVRNS07b0IxKyY/WEYrZ2RMZnAKekV5dzw4aFkleXMlcG9uQGJjfUMoIWdnRG1CRCZ6QkQ0
OGY2X31DYl5pYTNrRXt4fFlOQkFGajFTdj57US04blhYCnpZRiNhO3h7RGU9X31XTH4rdGdpfjBz
amNWM1ghJWsxMXBIaCZ8NkVjSnA1REhDa2hwdXhfTWU2TWFiMCMqNHRkPQp6eHRnZndYQCQze0Y/
VT1tZy0we2p7RHteKE1PKnJUcWVOPFpAVWNLJitvYCNGWUFAenIodlEpayFQKUZwSEd+VlAKelZ8
RUd5KnZMaCRjeFFjLVFKflA/ejJ1VjAyflM7a3pBZGZ8Km9HQ3x0anl5fTgycWAyNEUxRE0lRCt0
UypjZz4mCnpeaHtpNExGRGd7TzRvanFlM2tFY2M5Xj1+bUFKdFlDbj9BVFhIYDc0JDI/KSVUcXZS
YTNKeiZzQCRBcCRfUHBRNwp6TjIhbG5eSEopJjNyPDxTZ008JElJb3xYfSRfWGNiRDg1Yn5CUlB5
OE4tP1g/YC0raTBJK0wkYE9rPFYrdCZxelkKekVReVElWFc7LX07M2E4aWpEMWhYIz0rOFJjVHQ5
T3RrfWBgTFIoeTYjJTMoXlZ4cXxlXkxSMn02KmA/ZHBfa0g7Cnp2I0hvXytyYUZ6ZzxfO2B7SjNz
emJYRjxhRTVhNlAydHAqNDBlUnRZSEZLfWQ7MEVrbE4pNSQlQkhQfV9ydHVvLQp6b19ZYVIzcUFs
ZllYbyo0d2s2dDU7Um8rc0ExWDUpeF4mUU5lPnolclJRXz1uTlEzNHpgKlZhaDZUNTA3R3dtfmYK
elNEeGVBOzd6K3h0Wlk/WVR4OUlqWnc2PThAcCNfY0RiR1ZNekM0cllifWZKNWQ9dXwyP1UhUWl2
fS1eUUQpfT9nCnpiPFRecGVZPGcxQkprNjM0QVlXZHJlYHNZKGA9dm9aaVolRlBleEI8aGZRajh6
K1ZGWXBFWkt5Z2Q0JEE3I0JyRwp6U2B7IWtgZHFuTVJPc2xuaytHblJ5NFJCM3UxUzs5VWRlXlky
JDlIMG1qUE9xRnVGQzVAc35jXk8rQEZDT1k7NiYKekotcGdUI2VAMjlfRnIpdFA9fndXViYzTDZZ
YjIpVjZpJmJDPlVwPlgxN0woY1NmIXFOdSl9I2cpJmNAank4QyV0CnpUfTYjRHFqRUlFV35TS3Vk
c2ROWVB1KDYjQ0V0WEhFb3p7aEM2V0JfPjlgSk16amo+eFEpYU9IbExFPTJRe013Kwp6JEVCdClg
WV80aWdlRVF7Vl98SkEoRFE5ZlZtPitYVnFROVI+QGVQNXdlVHtQcTZOKlAlcWdTSDs/Rl9gKjcp
NlYKejE7Qm1CJTI8b21aSEoydXl6SDVFLVZJUU9YOV9nQXY5WkIqRCpibkZaWlNzfSVuczNEdElS
cDc2PnckbFViVGFPCnorc3g/KyRYQWNRN1RHRG5ibjY+WlUpRTlqM21xbV5pUmgxdyZ8UVJkLWw9
WlE2OTlacjY+M0QpdVNZcmlAJjZqJgp6ZCMxPjdOSHRXcCFeQyhaazMpWWU2I3Vob2Q0VDJWY309
YXw/c1ljYG9wO3FVND51NUxmPCh5NGV3akpYP35KYzwKejM/Z3lJMWpUZ09ucCt0K3VBIWNhezJI
aGh4aV4rVWVPQUZpK1AmUVp4ciY9SUJfU2hPTFArWms8blJsRD16Xng0CnpGNmIhaUJRbHwxKHkj
OHxEfjAoP2thWjBlSDJjOXJgfUFnb14ycUtsZiRwc0BucDY0VitMJFdqZkttOElXN0JKKAp6cj4x
Nz0+UktzayUle2pobGFAS3RLRE17JUVtTD0+RFZ0JXVFP1JoX2BtZWxWPXx+M3RnI3oxYyVgOWFA
djlXPSoKellwIURucE9HcGw7U35iRT5xU0ZqejVyZnNyajJBX3Z7aTxSOStFNXpfaiFLSi0xOzsy
Y1lJcit5fFMhY3VnNT5KCnpxTiY+R1d+NypjQCprQVQ3M2pKTHR8VEphVjY4Kko8PDdSYnBubD80
UjRwQzZFdCk5QFpQYWVENWVIcSpVV2VlPwp6OWU3ZmZ5Zmt4RFk0SkJ+am9gJmVPNG9PUUNiclZ2
PC1CMSt3P3dQWGlRPXRKeDs8ZFU1K2V9YCVMK1ZXZ0YmTDgKem9mRzR1OEB4VktqN18lM3xOUSlf
NkFGXjhTeWZTR1I4ZVl2JFV6TkJoQzd1YGh3TGs3dTVgeTNfQ2B7PnE1TT5CCnpve3NJe2V3Z0ky
dThLSXdvdyRvfnJEOD9lLTBtZG4jNFRXazZtMGFvVn5zWil3VWdiOExlIypPMmJ0M1FJa0twewp6
KUkhUWAlSW5tO3koV2UhPm5DVVFQbHswNmdIPnxqUnF5TFo2VW5pQkcreTI1ZSRndGlqY3RqYFk+
MH1WWDg2ZlkKekAqUWJwQGZWbU9YYSg7fmNDIWNkcVVoVX1yPVpRdCViQXJjXipCRVBVWEhzJHt+
VWgzKzM4WU5lLVhySFojJnJ2CnpNU3BzY0RhdCN+eFBNRmo5TTtOd1ZjZ3RhaGZRMypXQWA+a1My
WDhmOXJNR3ZleFpFflpjfXxSNlpxQko0aX1Vdwp6YWRfUmJuX3JgZlF9YlY5U0QtUytoU1g8TXZl
a31DUVdZRSYheHVKa1FHM1FiWkZKeVoxTT42YnRwR1MoanolMXUKelBPQ09qYjdNYXJ1e3tGOTFL
S0owZDNORGE2SkpOTFFSfk5veiMqRSghSTRiMWRybiV7Q2gkWT9DazYjVjYmajFKCnpCQ2BEeldk
YU52N2tJOVZASTZzPC0yMGVGcVVPbkxoRShgN24pMTFUPChgZlR4YitnSkktJjU/SG1tOW1eS35R
TQp6LXwzK1RCZj47RUdqNSRJa0FqSH13WlJwMmZRJDFCPkh2c3RkQjtSaEA5K2Y/RCt7MUBteWot
bklzPX1NNSQkcHYKektUdT40QXJRYCErfm9BQjNLNyUhT21fTmVkNmAyR2Iob3tTLT08c0ZFRWR8
YG5gcytzKHY2MHB4b3pGUW0qOCVKCno+bG45TTlEKTx6OUx8RiR6bVRKei0jLT5DU0BqMVFHQlBe
ZUBrWHg5Rj5Ve35uaE0jenk3T1NXZCk+cF9fWj5Tcwp6SmEmQkplLTU1RS1wfjB+TWppO1NsRSNS
djlJOEolb2dGV3NXY01aZCFkbiVXb0MyNWRzVz91S0FfKGdxVERGWiQKeldOfnRJQFVaaWBqJFk1
TCh+UVVFOXtlOzI8USM5JnQ7KmMtTVZRM0RVTzZyd3UmI0tKeDU+S30xJDNCSFJHe1luCnpqMTdW
JmRDY2dQT1FpT1BERyQjNnhiYVg0VT0meyZlNXNYRjlfOWtoP05aMUopbloxVEVnfik0c2ZgfCZM
I09VLQp6NEE7NFleUyYyKVZDbm8yYSEoaGMrX0w2ajh9dmhjamxrWG0pQCYkXj1VP0BhTU54ZTsh
cm5nOXBjcXFTdEMqPncKej00NlRZN28yS0JHKGM5S3NJQj8pQnZoZ0EmTnVzPyl3KkFCS05sZFJx
XjlZTnJsPllYdEtgVHExbEw+P3VJfjB8CnopJn5tcW43fCkzc2VfREdFdjNWe3J2fShmQ0clOEsk
YEZsWGx0KGBPSiZfWVdlOD9BWTZOPzw/N08hKlZMYWlxRwp6VTJ8cVVLRFpxenRZWjYxYEZzaFoz
cUhrMWZCWSZ+aE88UDV6U2NvWUooP2R2STczPStPfXxPMU1Ae0VrY1VIWSkKeispVUFjNlhrbE13
UWBpUWRjQThoeTE8MWk0PDtvQSFWTzVpIz5pMSl6aWYpOT8lJiVaY21qejl3TndGKEVzdWghCnpa
SD42OzA9c0lKNzUzPTIlR0oyYSllJU5jXyRmNFR7SWp4e2tVS0JuNjUwfjhwVDVfe3pDYmY5QjFg
WXpWcUNPUwp6a3MzPzxuOUUzYFdseHV7JTlUMSZPZVZlbkB+cUZnI15IKVBPJnZKI3ZlNDAzSXFF
dF5JbTchbkVneiojYVVjLSMKeilte3ZeLStOVVl6eG9YKj0pZD4+Qj1EYUV7KG1FWilxVl5fe0tA
VmFjSGdoQGtxOTN9UkROfiFjcWYlY19Vb2JFCnpNPSFOQmpFV1cpP0BRQ1lzalI1N1RXWV5FUlRX
cWQ/WHIrNXJvNFQ5Kn5fMG5LMU5QeiFEWFZlMG8hMClkPispeQp6JntmOWo+RSlHO0p8NzladGdv
KytsVmI/dVNeRCgoKE11V1lHfCNIYCZ3MjZsazUhJFc8LSgoPilaRT07eT5fT0cKenZheyhRSEc4
P2JzPFBgPzEtfW4oeShkaik2KVhlIXZhKTtmUj1YKTJ2YjhnUmk1NntLK0QzSioqRWFqP2xBWlJo
CnppNi1yPiEzJVJvV2t0ezU3ek5Md0Rkc3NaR04oTn5KbDBEKTkqP3xoSzgtXi0+IXU7cmo/bzsh
UyZIbVVRcWFUNAp6bSp+Zio/Uj07e3BFOzcraUBIczgjJH14ZWJhWiY/WFJVUXc5T0I+LW9pdlpB
cEdXVSNJRX5FQ1crKX1gKi1ifEYKejlFdVQoVyNTUEtTcVAoZWJjYH5oZ08qenBnWnRsVkk4fVJZ
WUJ3R2F5TlI1dmlQQGVnYSU3PGVYYWJraipvLVRsCnpXfU5KdE96QylETXh6R1NZYXdBX2xKNyZK
MChZXkcyUDBOazRyN1B8bSVvOEpwcnhneUFJZzhPQW1gJUg4aTtDTQp6IWBJak1PRSVTYGh7JCg+
LVYzI0xYWWwmVV5BakBrIXNYZFFnLVBxUypYRyRnSFp8ejlNTVc3QE1McFVkUytCb0MKelU1ZC0z
NXc+KTtLYXJzQUlDP3gkJXd2elo/UikwQUlXbkVaQWdgUkdmZUFSRnhtdVpBSChyazZAT0smNjtt
cEIrCnotNVB3PiZlayFteFUtPEgmWDNLb0x7LVB3XitQK349bElyekt7bkBGWD0wSnt1Zn4yU0Qt
fmlHeG9VZmk2UHdBIQp6Oyl+N2FFRyNfa3RFQF4xIWd9aCt1Z2hjP0Qra1k/S09ncFB6TU9zMWQ/
YUdoQndPOUUwdDtQOTUlTmFIJXdOYkQKelI1Xz9FI2s1QXF7TGFyVzlQVWtjUyFwdzVYNV9jV2gh
LXZ6WnIrMF5ueVBaI3s4fkw8WXVgfksjdkd5blFnYlNRCnolTjNUPmk0PD1Pd0VLKV9oZiY5JHYy
R29jRj42dGJ0PmF3VCVLS0B0cXd0UXlIalpHbWFkMDBsQFJUSE5ffWVwJAp6R0M+cDNCRTUzYHc5
fkJ8bUUrUCNqeW0xPiVZSlZ5NEdrN35BamFyVDslS3EjbHpPan1CVHdzciM0SnFIVDI8KUUKejw7
NG9lS1Q0JiNUWCZ8fTRLOUF0OUItJkJBRG5vTU1EZns5anBqV0g7KDRaV3pJU3NMbFg0YkByaHhQ
PS1oRT5GCnphKmV+ZEZuWnAxeWslYl9fI3xAZnFRNSRnOC1BKD4laiF0O0ZebzN9ezE5fW8/cCE5
YWB0azZiYTl9Z0FJIz9BSgp6QyYpN2Z3M21ZTlNeSnZtLS1fbnorPDErUnNXYX4mM1MzWSQ7ZVRV
emhtPEhCSj1qWFRWTHlMLXhfZ35+YX1uR1AKej5JKm9IT15mTVNmaWk0UUg+LUZEb1NSMlQoTXR2
ZUBsenFGeT1Ve3JGUGExbT0pYyg1Qk1LMmNFWlZuT2lQMkt+CnprRjB5Q2U5cEhIMkE8SkdRPk5X
JVNxQiRQZEFUbD1AZFomYz9nVEl0N1FyXypIa0xBRXw4UmYkbkQ0ZTluV2QydAp6X0dfdyF4O25K
VDc0akswbm9hNCk0Rmt0b21KbjZpQX03blN6UjZhSDVwQl5sUXdON2VeUDMpMSk2Pl4hKCVnQFAK
em10TnZybD59UjR1MFFWQUZFeHxhNTVNakBua2dTa0sqTHdmT31ydCVxU0drMj4rfGRVIXw5KmQl
Zmc+QFg/djU5CnomcVV4M1EpZysheztkPXE/eyV7N25GYCsjVE5UKDItJihII1VpNWdPUVBQcGEq
WmN4fGsxbEM0VnozPTNNWVFuIwp6JERPN0ZyI00oUChaampHQG1hcmRwfTh6RShHJXZ6IShtMUo2
UWx3RkJANF5kc2w+ITVtI0dSJnY5PjAxcX5mUkcKekBaSkc0dUczV0hGY010ZTl4JiFOa15NcD95
NnFKentgYjJHbGNYPXY3alV+Zm9uWXMoNmdSWWByQXx6RUBBengjCnpHLTU3MHhiN2hCdW12a2Rh
ViMpOEtFOFFHOUgzZXF7UCFKSGVPJW1zeUs9bEBHNEEyJVFtamdUWkVhV1FPbSpXTAp6Pz0wezd7
ZCttWEJQN0Z6ZEx2TiojdD4jJUFhS3w3eGJjeGo2TyhqdUtLTHRPciotQkNFbG98RXFyJUMkalc5
fHIKelpFZkM/M3l4ckgwaiNtY3B8Y28hXyk9eF9HfDZkSHIrSHRDTyVUPDw3dHJ2PUBFdGB2Jnc0
d2hgbjIlSHBRU3BDCnohVGpoMi1yMzhgd34pX3JwdX1UdFB+fGk+R0h+d01JVU8jTSZgN0IyV15w
WCtGOWVodj9WR2RHKWxkXnFkJEd8VQp6b3NCKSs8U1FLU3REWSZXYnplb2NRI3VYZU0tR2Y5MyVJ
WCVKd0VGd24lK2tBQHkhLXkjan1xUVQ8KlE9RnI9VX0KelZsZkhTRHUoTHxXSUFSSCp8ZXQtdjwh
ayUhazQxPzVAbk5TM313NFhiej52O2BedHJURDV1OUtERzdUTWxaP3hZCnpIamN5VGQ2OWV6dTdv
fU5CNzxoLU8rO31sISUyVz5VJFRKV1Q4Y2xNLU19d19He3J2Xk0yTzUkNSEmRlJtSTA1cAp6RiYo
UTBXX3RqekhCY2VXLUB4Rk4tYip9QHJkdFItMm9DZVpXPW9Yc2tMalJlKTNEM21Kdy0lQj8zX2A5
Mio7JGMKejVmWktvZiEyaSpNND9fMGtHPU0wMmwyVVhFVkkldTl8e1liXkh7aHFwVndLcGA5JW8q
TmhOc3JjPHVWdiQ1JHBACnpUeF5pelBMQHArKz9VaSpgQ1dPckJeMndvN19HQUc4RD49UHkoeGtV
akswYGlOQVduJU8rcXY2O2s3YlhJMSprdAp6ZSFIZGZtdUNydFFnNSQmPSlrQW5xKE43RD94KFF3
SkI/M21XflY1RVYxV2B0VWBJJH5xT2tJezdLVz1rKCMmYW8KemM3SSleZWNMR0sqdXJCaEZFMFcr
U2poPFJtPyFWSSpucz8qeDZHPX51RT1MNEVfN3VlMDZGcH5Xb3lUVWU7SVM4CnpeZCpjV0ghbn1i
czx4STxoPlE7WkRgOzRtek1NWkRjWVlvdENrSmhocVJlPzVmRmFtRjJAQzNoblI1Tyh5RjNVTgp6
VC16IXk9bFJLJjtAYlltTz5wRmw5P2l4I0U0PUgyTmZqfXl6Zz08PHUjPSNwNElkNGhLZiMycXUm
XzV2SDJXUzAKel5MWTJxWG93RE1jcHpjYkdlNH5fX0NMZCRjVE9GbVpIM1lyJlBlPUReS3Z7bDRW
KHA1Nj9Ufnl6M1MwPERnbzs4CnpZPmZgNHZsLTIyaiNhWVB6RG9ZeztZZTc2Sm5gamVgVjs1Kjtv
K2FyMGohT0wjekJ7Mk9+bnhyM2ZRSVhZRE1VMwp6VERpRTI9cEp5P3tUeyFhbGVHJT5INnF9dyYm
aEErIT5oQ2pTMitlKDsqSD5ecndiLWkzJjFXJThfTDVqaH13JC0KeiZANTltd2ooOENDXj01fF9T
PUNkcTReUU1DYT5hRGxjTlVocmFKWk1ZRyltTGdDeXZ1X2VkbnQxMkkkWGFSOSkmCnpgYGFfVGYk
MipCPldqXmIkNSFYUSZjMiVsO1UwVVZMNnAyc2dDWnRwY0l8MXpTM1BqP0ZKcSZsTyQjJGc4VWpB
TQp6cmMtSjMzOXBmZ0NNUTN1OU9wcyVzZHI2TlRibGBkci1xVHRJMlhLcHk0VHY1VChTRSkjNipT
K0ZPOE5jK3dCOGQKemtEb1k7OVY1Nmk1LWohYnFUbEByZmo2RX44Mk9gbGFzdWE4KiRoMFUmenY9
JGVtZy18R2J3LTF7WTFoPDxtKF4pCno/ajR6VSlqaSNpRDNSaj0wYHhJU155Y014c345cUQoYGol
dFBlWXx7SkJCX1N5XmFkYkFxWW5RME8/UiU+JEJ+Sgp6RlZYWFBeSX1LLU14SkExYi1VKzsrK0pH
fjhjeGtgbWFiejVCcmh7ZUV8OU88JXUxPTBacW4qcGVQYyV1WVgjWioKejBicytiRkVPaC07dWdU
MD1NUWU+PD5rcElAajgkMGkxX2J8cSFzfjh2cCpmUndJZGZaWmZrMTsqSWVweldDQDY8CnoyREFI
OyN6czlEPUlMPWU+MkxgbDtJMG5RQUg0dGY8aFB2XjtqUVYmWm84QWZyY2xwYzs7SWk8OXtNS1Zm
fEwhVQp6cGx+M2NnYE1qK05hRyVtclJ8eSowNUVFOVpuQmFxVVVJOEYxVEpQd2U3U1J2JkVMMHtW
V1VzU0kzdk5qY1R7QmwKekJDKnU+cjYoZjZ5fjVeflorPWw4eElXPUJhPDUxaTlmNUczKzZ7QWo3
eTFLYz9Dfmw0Yj5oITVzNTwoNm9vOG1QCnp7M2JBQEx7SXd6UExZcnAoOXFod1pyentFN35QUl5J
WHs7fDtBPUdSTyU9PXJjZ3JQb15MYm1TZU9LeFIoLSk9bwp6cENPbmN2fE9kI05PcGZfJExFeGFr
PTV3bGljOFB6NSM8czMqaTZ+YF9NXkZLRloyaWZPIWxQMjg9ZV5BNTxYfCQKelYjZyZzNTVuVGpl
azY9cV52YH5JPlRfUCVKYipibjN1dGJoZT1JYkJIOXFVZlF0VnpjdUp5QnxoPnwmSk5SdmBqCnpS
MUN1R3ZtQzZEc0J+e2UmaEA/PTVRfUY+O0MzfUArQitMeCQrSGZRTnReVGFQd2NhVFRHJmh2b3t5
bn1ReE9QKwp6dW5eez9WWUhVcmspUj9BK2ooVEBnN0MjOVRuRTljelMzO1A7QTl9fXllNDRJTD5U
az5Cc3AhZypZQFQ5NzVUelIKeiU8P2JVJDRKV0hefVRUU3FZZGtvXk9wbCVORkhrNnR2cUhaTC1S
Pmk/NjgtcSFOdCt6T1pFYW1aNH1veWp6OWt9CnpLfHM/QCoxc0FGZzEhcGJYI3NYYkxXaEd9NlEl
UzhMVntkcHpzfH1tQ1dtTD9WJVROZE09JCtlSjJqd0o4TTw7fgp6PW51dmU7aG82QHRJS34jbHpZ
RiljVVpUQztQYElEI2xOJmFud0BPJFJoOyo0S0t3dyFiP3xORGs/WV9gPyE+NlYKemBOMEhQbnFZ
MnN2ZmZSRHdjSndLbTkzSGYmV1JWWU8hNj5SMThEdSlPajR6RGF8KG00cWhudmZPTz5BZVlTPnpP
CnoyaEMxKEZoPVo5T3lKR193YDg3ISYlJTMkOG4pYU5rOWdkcXN2TV9iV0E9aWxNZWAjZzxyb3Yx
LUdtaTdaYDB6dwp6QDRPPHhLN0VndTh+YypuclZFOUBFNnZpZkJjSUF8SHtDeUE7OHpBd216c0k+
aj16WFleUSMwLXJ2UH40ZSZYIyUKelRueUU3cDhobUclandCSnpzY05aY30hRyotaz11ZUZQOFF6
MypkZHdsXihZeE40XiE5a1c8Zlo5cG5ETl53IWhXCnojSDtDLT9QLX5sSGNpYzkta0lBaVJSSVVs
I1JEYW5hWWBZLSpHR0BiZj4pYXhOPkM1fWhWdngjdkhKTUZuSWR4Tgp6UyNPblBtUGEmVXleZHpS
PWFjPjBeJldBJW4wOSMrMVhLeVUjb3QwNCZ5JllEcENHRXdxVUskQ1JMVlJ+JUNeS1QKekUpOUst
ZD11KFRqZXxUIT9nYUwlYVJrXkZTNS1TPD4mfWw/Rk9pWHtKRT1TOGI4K0wjNlJ0fUtyJUJFaD1S
K005Cnp0P2hTZW0pNSt8am4pZVY5Mm80KEBHIUs4cWxxPD1sJXQ+Nj17VU57KlZxPnVjYUFtKjUq
aThLe01MSmxPMClqNgp6OHh1R145cVQ+NVpPSDMoeWohU1NPQlhHTXdQMVNlOW5kZDstMnd7ZUVp
YFE4aWl8KCFJdnsyNTlBND07TExUNnoKeklwUHZkNiFxVnMtMHZrRUlISGBONz5pPk5JUXM1Nz17
K0JLdXBTIzc9WWFhKT4rVVZebGlUfU9nSkVFcykqflQ1CnoyamsjX3NLUClAJTU2JFApXzQ7Uyt0
aWVeZkh7M01mXypjWjtzc3MhWEYrfXlHMGJaakRzSHAqK0lqcy10XyklIQp6SXtEJExJdSZUOXcq
aVU8VmArfjxGbSNDKTI/YXxaOVVaTC0mMG9nOXJWQE03cF8yUzlWfHgwZmBQNTtydSUlM0AKeiZ1
UUxfLX1wQTtKa0lWVVhtYCF9UzxlZGp7KkAjUDNEel8pRm8wU0ZUM2RHPUBqQUBaXmxadngjSzNw
cHg1YUdNCnpAKjJyamB9Jj9fNWNPOVNDbnN5RHF7NVU/akB7PVUyO0VSdl91PCkqbHlwYlFTTyY1
Kj8+RnFDc05YPmMtaTFjNwp6Mz4haDBpRngtMz8jd1NXMShYIWw9aFFuRlBDQmZQQGZyNk5JNSlz
Nyk+MXlgbjdDU0kyZCpxUDkzcD09OUpPIXkKemI3ZzZyS3ArST5TTnxgLSotKz5KWjdCWCQ5R2lp
Y2FYYD50OTBDalRAcGhCKXFoZGF2LU0+TlJsM307eTJlTU9NCnpqWExuVXFwOztLJnFCfCpQSXJl
QXhFRUBBemtBc2NpNS1AbHd8WlliR3BPMVRyYkQrVElkdylwdTNOYHV6fkgodAp6dShLb2o+OWR7
dD1lWmZ2KGNORkRnfnxmakIxSFBqT1lPfmY+TSVSNiZzWDE1ZDBOIUI7Q2R9d3hlJSpmNkwrODAK
ek9BUkleXzV8bk9IR0IwOXFJTTRjKkxWMGgzJnNtNEVnT2J4RVpWdnNDTEhfP15qJDl2OXxeTVgq
VD5pQGJ0SGFpCnpzUD1Xd1I9KVVzUyh9b1luJVd6RGtgPl9FSl5FUnwlJWdjXytxflZYSkcwQzgl
fCt5N2dRWXQoKD0lPU1sMTxRSgp6X2JZPXVzPjw+NG5MQlA4QGZVel5KUWE+TSVITyN2PVk2Y0x0
em5JbyFwX1lIJUVzVU1fXmUteHY1NiU0P0p2R1AKem5ILXUoRWo0ZHY+YSNMN0liM0Mpbmo3dVhE
RUJ6bz9AaFRobFptMkFDfTc4P2NzUStaKXFsbH4jXiRVNUNAOG50Cnpge31UPylCU093KSYyYT4o
cn5HbFFXYV88bF9CQXZDOXdBSng4a3R4I1J1UT5KbSZKIWRZMEJPcVB7PFNCeFJPOAp6Rmt2eGdD
K009Wl9rNjw5Myl4a2I7PEpueWsrWnBgaylUKjZzYCR1JDVpeVh5NTJScHZrPC07Wj5+IyMxKk5N
OWIKejU3eDVIdy1YUEtvTyZpK243aSVPbDM3a3lJVkxwa0V7Uk9pOUdgPWAyVG9CeUIyN1cpQHpX
P1ZLcCFeaVcpNTltCno2PntvPjYmVn4lbE5sem51czU7Rm13RFBkSjJmcmtyMXwoYFgxckNEI1hQ
T3hiejI0VVExN2B3eldLfGM9QTNIcAp6d1krQlI1I0BMQXQ8Sz4xNGhHPF9YN05KZ2tBMyRgeHMj
JWotUDxQeHchYjk9RWBlO25Dan5Qemk+V0s5WDk+UDYKenA2fCpjR2xzSVQqSClsemoyJiVIempS
KUJKTDVaMD0tfXQ5RkBHOHYmKSNMNSk3JEFlZXR8NSNDdHNHSUt8Zz1DCnooMlNuLXlzO1khZC1k
KUpieEJKZXFHSX5EMTxVMWpvQ2B2USRmbkA5Xil4ZlRCYD5oWjZHUiRUYHI/Rk96Vjlidgp6cjJH
MT5hMGElbiM3Z0Aha3NMYl5BfDM/fHpJcjVWPEhHQ1puTj83NFUrcXByJlBodVVPJSllLVdVSihA
Zn10NWQKejgqNCV9WjBecFlIX0pSWFEmSD94IVp4YTVjY0B8RGtCOEk1cCFjbk5lPjEzbDtmaHVr
OFRnbXlufiZ3Qj0xZSpxCnomMkNvPE1hZTlnUT91RHxRfEtLV08re0RzckpUKU8tclRNKV93OWk+
JSQyUVNAczJ8eFhLKX05MEA2M21uPClTagp6T3JPUGdCVm52WiFQdC1pYTJvPW0rV1NsYjVASDUy
dFJMVDdhM04yYk4rNkprbzI+czB7VT9lNFl+dWdSdTVpPjAKWGIqTk5TVlMreG5ZTHYtS0RAKHk4
T3lCLXJzWn50VAoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy92
aWJlbWlzLnN2ZyBiL2FwcC9yZXMvdmliZW1pcy5zdmcKaW5kZXggYzNmM2M4MS4uNzExNWMzMyAx
MDA2NDQKLS0tIGEvYXBwL3Jlcy92aWJlbWlzLnN2ZworKysgYi9hcHAvcmVzL3ZpYmVtaXMuc3Zn
CkBAIC0xLDE5ICsxLDcgQEAKLTw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rpbmc9IlVURi04IiBz
dGFuZGFsb25lPSJubyI/PgotPCEtLSBWaWJlbWlzIGJyYW5kIG1hcms6IGEgY3V0LWdlbSBkaWFt
b25kIGNyYWRsaW5nIGEgcGxheSB0cmlhbmdsZS4KLSAgICAgRHJhd24gZnJvbSB0aGUgZGVzaWdu
LWtpdCB0b2tlbnMgKGRvY3MvZGVzaWduL3JlZGVzaWduL2xvZ28vUkVBRE1FLm1kKToKLSAgICAg
ZGlhbW9uZCBoYWxmLWRpYWdvbmFsIH4zNyUgb2YgdGhlIGJveCwgc3Ryb2tlIH43LjglIG9mIHRo
ZSBib3gsIGZpbGxlZAotICAgICBwbGF5IHRyaWFuZ2xlIH4zMCUgdGFsbCBjZW50ZXJlZCBpbnNp
ZGUsIGFjY2VudCBncmFkaWVudAotICAgICAjNkFEREU3IC0+ICMyRkM2RDAuIFRoZSBzb2Z0IGds
b3cgaXMgb21pdHRlZCBzbyB0aGUgbWFyayBzdGF5cyBjcmlzcCBhdAotICAgICB0aGUgc21hbGwg
c2l6ZXMgdGhpcyBTVkcgaXMgcmFzdGVyaXplZCBhdCAoU0RMIHN0cmVhbS13aW5kb3cgaWNvbiku
IC0tPgotPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAg
MCAyNTYgMjU2IiB3aWR0aD0iMjU2IiBoZWlnaHQ9IjI1NiI+Ci0gIDxkZWZzPgotICAgIDxsaW5l
YXJHcmFkaWVudCBpZD0idmJBY2NlbnQiIHgxPSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj4KLSAg
ICAgIDxzdG9wIG9mZnNldD0iMCIgc3RvcC1jb2xvcj0iIzZBRERFNyIvPgotICAgICAgPHN0b3Ag
b2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjMkZDNkQwIi8+Ci0gICAgPC9saW5lYXJHcmFkaWVudD4K
LSAgPC9kZWZzPgotICA8cGF0aCBkPSJNIDEyOCAzMy4zIEwgMjIyLjcgMTI4IEwgMTI4IDIyMi43
IEwgMzMuMyAxMjggWiIgZmlsbD0ibm9uZSIKLSAgICAgICAgc3Ryb2tlPSJ1cmwoI3ZiQWNjZW50
KSIgc3Ryb2tlLXdpZHRoPSIyMCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIvPgotICA8cGF0aCBk
PSJNIDEwNyA5Mi42IEwgMTA3IDE2My40IEwgMTY4IDEyOCBaIiBmaWxsPSJ1cmwoI3ZiQWNjZW50
KSIKLSAgICAgICAgc3Ryb2tlPSJ1cmwoI3ZiQWNjZW50KSIgc3Ryb2tlLXdpZHRoPSIxMiIgc3Ry
b2tlLWxpbmVqb2luPSJyb3VuZCIvPgorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAw
MC9zdmciIHdpZHRoPSI1MTIiIGhlaWdodD0iNTEyIiB2aWV3Qm94PSIwIDAgNTEyIDUxMiI+Cis8
ZGVmcz48bGluZWFyR3JhZGllbnQgaWQ9InJpbSIgeDE9IjAiIHkxPSIwIiB4Mj0iMSIgeTI9IjEi
PjxzdG9wIHN0b3AtY29sb3I9IiNmZjc1OGIiLz48c3RvcCBvZmZzZXQ9Ii40OCIgc3RvcC1jb2xv
cj0iI2RjMzY1OCIvPjxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzYzMTUyYiIvPjwvbGlu
ZWFyR3JhZGllbnQ+PGxpbmVhckdyYWRpZW50IGlkPSJnbGFzcyIgeDE9IjAiIHkxPSIwIiB4Mj0i
MCIgeTI9IjEiPjxzdG9wIHN0b3AtY29sb3I9IiMyMDE1MWMiLz48c3RvcCBvZmZzZXQ9IjEiIHN0
b3AtY29sb3I9IiMwODA4MGIiLz48L2xpbmVhckdyYWRpZW50PjwvZGVmcz4KKzxyZWN0IHg9IjEy
IiB5PSIxMiIgd2lkdGg9IjQ4OCIgaGVpZ2h0PSI0ODgiIHJ4PSIxMTAiIGZpbGw9InVybCgjZ2xh
c3MpIiBzdHJva2U9IiNmZmZmZmYiIHN0cm9rZS1vcGFjaXR5PSIuMTMiIHN0cm9rZS13aWR0aD0i
MiIvPgorPGNpcmNsZSBjeD0iMjU2IiBjeT0iMjU2IiByPSIxNDQiIGZpbGw9InVybCgjcmltKSIv
PgorPGNpcmNsZSBjeD0iMjY4IiBjeT0iMjQ5IiByPSIxMzYiIGZpbGw9IiMwODA4MGIiLz4KKzxw
YXRoIGQ9Ik0xNTEgMTYyYTE0MyAxNDMgMCAwIDEgMTM1LTQ4IiBmaWxsPSJub25lIiBzdHJva2U9
IiNmZmU4ZWUiIHN0cm9rZS1vcGFjaXR5PSIuNTUiIHN0cm9rZS13aWR0aD0iMyIgc3Ryb2tlLWxp
bmVjYXA9InJvdW5kIi8+CiA8L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXNvdXJjZXMucXJjIGIv
YXBwL3Jlc291cmNlcy5xcmMKaW5kZXggYjVkNGVlNy4uMDhiZGYyYiAxMDA2NDQKLS0tIGEvYXBw
L3Jlc291cmNlcy5xcmMKKysrIGIvYXBwL3Jlc291cmNlcy5xcmMKQEAgLTEsMTMgKzEsMjMgQEAK
IDxSQ0M+CiAgICAgPHFyZXNvdXJjZSBwcmVmaXg9Ii8iPgotICAgICAgICA8ZmlsZSBhbGlhcz0i
cmVzL3N0ZWFtL3ZpYmVtaXNfcC5wbmciPnJlcy9zdGVhbS92aWJlbWlzX3AucG5nPC9maWxlPgot
ICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXMucG5nIj5yZXMvc3RlYW0vdmli
ZW1pcy5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19o
ZXJvLnBuZyI+cmVzL3N0ZWFtL3ZpYmVtaXNfaGVyby5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxl
IGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19sb2dvLnBuZyI+cmVzL3N0ZWFtL3ZpYmVtaXNfbG9n
by5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19pY29u
LnBuZyI+cmVzL3N0ZWFtL3ZpYmVtaXNfaWNvbi5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFs
aWFzPSJyZXMvdmliZW1pcy1tYXJrLTUxMi5wbmciPnJlcy92aWJlbWlzLW1hcmstNTEyLnBuZzwv
ZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstMjU2LnBuZyI+cmVz
L3ZpYmVtaXMtbWFyay0yNTYucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3Zp
YmVtaXMtbWFyay0xMjgucG5nIj5yZXMvdmliZW1pcy1tYXJrLTEyOC5wbmc8L2ZpbGU+CisgICAg
ICAgIDxmaWxlPmd1aS9FY2xpcHNlSGFyZHdhcmVNb25pdG9yLnFtbDwvZmlsZT4KKyAgICAgICAg
PGZpbGU+Z3VpL0VjbGlwc2VTeXN0ZW1TZXR0aW5ncy5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxl
Pmd1aS9FY2xpcHNlQ29tYm9Cb3gucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5yZXMvY3JpbXNv
bi1uZXR3b3JrLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2NyaW1zb24tYmx1ZXRvb3Ro
LnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2VjbGlwc2UtY29udHJvbHMuc3ZnPC9maWxl
PgorICAgICAgICA8ZmlsZT5yZXMvZWNsaXBzZS1pY29uLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZp
bGU+cmVzL2VjbGlwc2UtcG93ZXIuc3ZnPC9maWxlPgorICAgICAgICA8ZmlsZT5yZXMvY3JpbXNv
bi1iYXR0ZXJ5LnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2NyaW1zb24taG9zdC5zdmc8
L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19wLnBuZyI+cmVz
L3N0ZWFtL2VjbGlwc2VfcC5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3Rl
YW0vdmliZW1pcy5wbmciPnJlcy9zdGVhbS9lY2xpcHNlLnBuZzwvZmlsZT4KKyAgICAgICAgPGZp
bGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2hlcm8ucG5nIj5yZXMvc3RlYW0vZWNsaXBzZV9o
ZXJvLnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2xv
Z28ucG5nIj5yZXMvc3RlYW0vZWNsaXBzZV9sb2dvLnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUg
YWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2ljb24ucG5nIj5yZXMvc3RlYW0vZWNsaXBzZV9pY29u
LnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstNTEyLnBu
ZyI+cmVzL2VjbGlwc2UtbWFyay01MTIucG5nPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0i
cmVzL3ZpYmVtaXMtbWFyay0yNTYucG5nIj5yZXMvZWNsaXBzZS1tYXJrLTI1Ni5wbmc8L2ZpbGU+
CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTEyOC5wbmciPnJlcy9lY2xp
cHNlLW1hcmstMTI4LnBuZzwvZmlsZT4KICAgICAgICAgPGZpbGUgYWxpYXM9ImZvbnRzL1NvcmEu
dHRmIj5mb250cy9Tb3JhLnR0ZjwvZmlsZT4KICAgICAgICAgPGZpbGUgYWxpYXM9ImZvbnRzL01h
bnJvcGUudHRmIj5mb250cy9NYW5yb3BlLnR0ZjwvZmlsZT4KICAgICAgICAgPGZpbGU+cmVzL3Nv
dW5kcy9uYXZfdGljay53YXY8L2ZpbGU+CmRpZmYgLS1naXQgYS9hcHAvc2V0dGluZ3Mvc3RyZWFt
aW5ncHJlZmVyZW5jZXMuY3BwIGIvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2VzLmNw
cAppbmRleCBkNjlhOTEzLi42MDIyYjI1IDEwMDY0NAotLS0gYS9hcHAvc2V0dGluZ3Mvc3RyZWFt
aW5ncHJlZmVyZW5jZXMuY3BwCisrKyBiL2FwcC9zZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNl
cy5jcHAKQEAgLTIyOSw3ICsyMjksNyBAQCB2b2lkIFN0cmVhbWluZ1ByZWZlcmVuY2VzOjpyZWxv
YWQoKQogICAgIHNlZW5XZWxjb21lSGludCA9IHNldHRpbmdzLnZhbHVlKFNFUl9TRUVOV0VMQ09N
RUhJTlQsIGZhbHNlKS50b0Jvb2woKTsKICAgICBlbmFibGVIZHIgPSBzZXR0aW5ncy52YWx1ZShT
RVJfSERSLCBmYWxzZSkudG9Cb29sKCk7CiAgICAgdWlTaG93SGludHMgPSBzZXR0aW5ncy52YWx1
ZShTRVJfVUlfU0hPV0hJTlRTLCB0cnVlKS50b0Jvb2woKTsKLSAgICB1aUFjY2VudEluZGV4ID0g
cUJvdW5kKDAsIHNldHRpbmdzLnZhbHVlKFNFUl9VSV9BQ0NFTlRJTkRFWCwgMCkudG9JbnQoKSwg
Myk7CisgICAgdWlBY2NlbnRJbmRleCA9IHFCb3VuZCgwLCBzZXR0aW5ncy52YWx1ZShTRVJfVUlf
QUNDRU5USU5ERVgsIDQpLnRvSW50KCksIDE1KTsKICAgICB1aVNvdW5kcyA9IHNldHRpbmdzLnZh
bHVlKFNFUl9VSVNPVU5EUywgdHJ1ZSkudG9Cb29sKCk7CiAgICAgZGlzcGxheUhkckNhcGFiaWxp
dHkgPSBzZXR0aW5ncy52YWx1ZShTRVJfRElTUExBWV9IRFJfQ0FQQUJJTElUWSwgdHJ1ZSkudG9C
b29sKCk7CiAgICAgaGRyVG9uZW1hcHBpbmcgPSBzZXR0aW5ncy52YWx1ZShTRVJfSERSX1RPTkVN
QVAsIGZhbHNlKS50b0Jvb2woKTsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvaW5wdXQvaW5w
dXQuY3BwIGIvYXBwL3N0cmVhbWluZy9pbnB1dC9pbnB1dC5jcHAKaW5kZXggMTA1MDVlZi4uM2Zh
Zjg3ZiAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWluZy9pbnB1dC9pbnB1dC5jcHAKKysrIGIvYXBw
L3N0cmVhbWluZy9pbnB1dC9pbnB1dC5jcHAKQEAgLTg4LDYgKzg4LDEwIEBAIFNkbElucHV0SGFu
ZGxlcjo6U2RsSW5wdXRIYW5kbGVyKFN0cmVhbWluZ1ByZWZlcmVuY2VzJiBwcmVmcywgaW50IHN0
cmVhbVdpZHRoLCBpCiAgICAgbV9TcGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlU3RhdHNP
dmVybGF5XS5rZXlDb2RlID0gU0RMS19zOwogICAgIG1fU3BlY2lhbEtleUNvbWJvc1tLZXlDb21i
b1RvZ2dsZVN0YXRzT3ZlcmxheV0uc2NhbkNvZGUgPSBTRExfU0NBTkNPREVfUzsKICAgICBtX1Nw
ZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVTdGF0c092ZXJsYXldLmVuYWJsZWQgPSB0cnVl
OworICAgIG1fU3BlY2lhbEtleUNvbWJvc1tLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmVdLmtl
eUNvbWJvID0gS2V5Q29tYm9Ub2dnbGVMb2NhbEhhcmR3YXJlOworICAgIG1fU3BlY2lhbEtleUNv
bWJvc1tLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmVdLmtleUNvZGUgPSBTRExLX2g7CisgICAg
bV9TcGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlTG9jYWxIYXJkd2FyZV0uc2NhbkNvZGUg
PSBTRExfU0NBTkNPREVfSDsKKyAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVM
b2NhbEhhcmR3YXJlXS5lbmFibGVkID0gdHJ1ZTsKIAogICAgIG1fU3BlY2lhbEtleUNvbWJvc1tL
ZXlDb21ib1RvZ2dsZU1vdXNlTW9kZV0ua2V5Q29tYm8gPSBLZXlDb21ib1RvZ2dsZU1vdXNlTW9k
ZTsKICAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVNb3VzZU1vZGVdLmtleUNv
ZGUgPSBTRExLX207CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmggYi9h
cHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmgKaW5kZXggZjgyOGMwNC4uN2Q1YjFkYSAxMDA2NDQK
LS0tIGEvYXBwL3N0cmVhbWluZy9pbnB1dC9pbnB1dC5oCisrKyBiL2FwcC9zdHJlYW1pbmcvaW5w
dXQvaW5wdXQuaApAQCAtMTg4LDYgKzE4OCw3IEBAIHByaXZhdGU6CiAgICAgICAgIEtleUNvbWJv
VW5ncmFiSW5wdXQsCiAgICAgICAgIEtleUNvbWJvVG9nZ2xlRnVsbFNjcmVlbiwKICAgICAgICAg
S2V5Q29tYm9Ub2dnbGVTdGF0c092ZXJsYXksCisgICAgICAgIEtleUNvbWJvVG9nZ2xlTG9jYWxI
YXJkd2FyZSwKICAgICAgICAgS2V5Q29tYm9Ub2dnbGVNb3VzZU1vZGUsCiAgICAgICAgIEtleUNv
bWJvVG9nZ2xlQ3Vyc29ySGlkZSwKICAgICAgICAgS2V5Q29tYm9Ub2dnbGVNaW5pbWl6ZSwKZGlm
ZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9hcmQuY3BwIGIvYXBwL3N0cmVhbWlu
Zy9pbnB1dC9rZXlib2FyZC5jcHAKaW5kZXggOTkzZTUzNC4uOTQyNTYyZSAxMDA2NDQKLS0tIGEv
YXBwL3N0cmVhbWluZy9pbnB1dC9rZXlib2FyZC5jcHAKKysrIGIvYXBwL3N0cmVhbWluZy9pbnB1
dC9rZXlib2FyZC5jcHAKQEAgLTUxLDYgKzUxLDExIEBAIHZvaWQgU2RsSW5wdXRIYW5kbGVyOjpw
ZXJmb3JtU3BlY2lhbEtleUNvbWJvKEtleUNvbWJvIGNvbWJvKQogICAgICAgICByYWlzZUFsbEtl
eXMoKTsKICAgICAgICAgYnJlYWs7CiAKKyAgICBjYXNlIEtleUNvbWJvVG9nZ2xlTG9jYWxIYXJk
d2FyZToKKyAgICAgICAgU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuc2V0T3Zl
cmxheVN0YXRlKE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlLAorICAgICAgICAgICAgICFT
ZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5pc092ZXJsYXlFbmFibGVkKE92ZXJs
YXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlKSk7CisgICAgICAgIGJyZWFrOworCiAgICAgY2FzZSBL
ZXlDb21ib1RvZ2dsZVN0YXRzT3ZlcmxheToKICAgICAgICAgU0RMX0xvZ0luZm8oU0RMX0xPR19D
QVRFR09SWV9BUFBMSUNBVElPTiwKICAgICAgICAgICAgICAgICAgICAgIkRldGVjdGVkIHN0YXRz
IHRvZ2dsZSBjb21ibyIpOwpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy9zZXNzaW9uLmNwcCBi
L2FwcC9zdHJlYW1pbmcvc2Vzc2lvbi5jcHAKaW5kZXggNThmZWI5Ni4uNzkxZWY0YyAxMDA2NDQK
LS0tIGEvYXBwL3N0cmVhbWluZy9zZXNzaW9uLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3Nlc3Np
b24uY3BwCkBAIC0xLDQgKzEsNSBAQAogI2luY2x1ZGUgInNlc3Npb24uaCINCisjaW5jbHVkZSA8
UVNldHRpbmdzPg0KICNpbmNsdWRlICJzZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5oIg0K
ICNpbmNsdWRlICJzdHJlYW1pbmcvc3RyZWFtdXRpbHMuaCINCiAjaW5jbHVkZSAic3RyZWFtaW5n
L3ZycnJhdGVwb2xpY3kuaCINCkBAIC0yNjY5LDYgKzI2NzAsNyBAQCB2b2lkIFNlc3Npb246OmV4
ZWNJbnRlcm5hbCgpCiANCiAgICAgLy8gVG9nZ2xlIHRoZSBzdGF0cyBvdmVybGF5IGlmIHJlcXVl
c3RlZCBieSB0aGUgdXNlcg0KICAgICBtX092ZXJsYXlNYW5hZ2VyLnNldE92ZXJsYXlTdGF0ZShP
dmVybGF5OjpPdmVybGF5RGVidWcsIG1fUHJlZmVyZW5jZXMtPnNob3dQZXJmb3JtYW5jZU92ZXJs
YXkpOw0KKyAgICBtX092ZXJsYXlNYW5hZ2VyLnNldE92ZXJsYXlTdGF0ZShPdmVybGF5OjpPdmVy
bGF5TG9jYWxIYXJkd2FyZSwgUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvbG9jYWxPdmVybGF5
IixmYWxzZSkudG9Cb29sKCkpOw0KIA0KICAgICAvLyBWaWJlbWlzOiBvcHQtaW4gb24tc2NyZWVu
IHRvdWNoIGNvbnRyb2xzIG92ZXJsYXkg4oCUDQogICAgIC8vIHRocmVlIGljb24tb25seSBidXR0
b25zIChNRU5VIG9wZW5zIHRoZSBRdWljayBNZW51LCBLQkQgcmVxdWVzdHMgdGhlIFN0ZWFtT1MN
CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZDNkMTF2
YS5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZDNkMTF2YS5jcHAK
aW5kZXggMzg4ZTMwNy4uZjg1MzIzOSAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWluZy92aWRlby9m
Zm1wZWctcmVuZGVyZXJzL2QzZDExdmEuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZt
cGVnLXJlbmRlcmVycy9kM2QxMXZhLmNwcApAQCAtOTY0LDcgKzk2NCw3IEBAIHZvaWQgRDNEMTFW
QVJlbmRlcmVyOjpub3RpZnlPdmVybGF5VXBkYXRlZChPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBl
KQogICAgICAgICByZW5kZXJSZWN0LnggPSAwOwogICAgICAgICByZW5kZXJSZWN0LnkgPSAwOwog
ICAgIH0KLSAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZykgeworICAg
IGVsc2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8IHR5cGUgPT0gT3Zlcmxh
eTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHsKICAgICAgICAgLy8gVG9wIGxlZnQKICAgICAgICAg
cmVuZGVyUmVjdC54ID0gMDsKICAgICAgICAgcmVuZGVyUmVjdC55ID0gbV9EaXNwbGF5SGVpZ2h0
IC0gbmV3U3VyZmFjZS0+aDsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVn
LXJlbmRlcmVycy9keHZhMi5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJl
cnMvZHh2YTIuY3BwCmluZGV4IDMyNjE4ZDguLjA0YjVkMTcgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJl
YW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9keHZhMi5jcHAKKysrIGIvYXBwL3N0cmVhbWlu
Zy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2R4dmEyLmNwcApAQCAtODYyLDcgKzg2Miw3IEBAIHZv
aWQgRFhWQTJSZW5kZXJlcjo6bm90aWZ5T3ZlcmxheVVwZGF0ZWQoT3ZlcmxheTo6T3ZlcmxheVR5
cGUgdHlwZSkKICAgICAgICAgcmVuZGVyUmVjdC54ID0gMDsKICAgICAgICAgcmVuZGVyUmVjdC55
ID0gbV9EaXNwbGF5SGVpZ2h0IC0gbmV3U3VyZmFjZS0+aDsKICAgICB9Ci0gICAgZWxzZSBpZiAo
dHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICBlbHNlIGlmICh0eXBlID09IE92
ZXJsYXk6Ok92ZXJsYXlEZWJ1ZyB8fCB0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3
YXJlKSB7CiAgICAgICAgIC8vIFRvcCBsZWZ0CiAgICAgICAgIHJlbmRlclJlY3QueCA9IDA7CiAg
ICAgICAgIHJlbmRlclJlY3QueSA9IDA7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVv
L2ZmbXBlZy1yZW5kZXJlcnMvZWdsdmlkLmNwcCBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVn
LXJlbmRlcmVycy9lZ2x2aWQuY3BwCmluZGV4IDk1ODdhMzUuLjIwNjgwZDggMTAwNjQ0Ci0tLSBh
L2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9lZ2x2aWQuY3BwCisrKyBiL2Fw
cC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9lZ2x2aWQuY3BwCkBAIC0yMzQsMTAg
KzIzNCwxMCBAQCB2b2lkIEVHTFJlbmRlcmVyOjpyZW5kZXJPdmVybGF5KE92ZXJsYXk6Ok92ZXJs
YXlUeXBlIHR5cGUsIGludCB2aWV3cG9ydFdpZHRoLCBpbgogICAgICAgICAgICAgb3ZlcmxheVJl
Y3QueCA9IDA7CiAgICAgICAgICAgICBvdmVybGF5UmVjdC55ID0gMDsKICAgICAgICAgfQotICAg
ICAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZykgeworICAgICAgICBl
bHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZyB8fCB0eXBlID09IE92ZXJsYXk6
Ok92ZXJsYXlMb2NhbEhhcmR3YXJlKSB7CiAgICAgICAgICAgICAvLyBWaWJlbWlzOiB1c2VyLWNv
bmZpZ3VyYWJsZSBjb3JuZXIuIE5COiBPcGVuR0wgb3JpZ2luIGlzIGxvd2VyLWxlZnQsCiAgICAg
ICAgICAgICAvLyBzbyAidG9wIiBpcyB0aGUgaGlnaC1ZIGVkZ2UgaGVyZS4KLSAgICAgICAgICAg
IGludCBhbmNob3IgPSBTZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5nZXREZWJ1
Z092ZXJsYXlBbmNob3IoKTsKKyAgICAgICAgICAgIGludCBhbmNob3IgPSBTZXNzaW9uOjpnZXQo
KS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5nZXRPdmVybGF5QW5jaG9yKHR5cGUpOwogICAgICAgICAg
ICAgYm9vbCByaWdodCA9IChhbmNob3IgPT0gMSB8fCBhbmNob3IgPT0gMyk7ICAvLyBUUiBvciBC
UgogICAgICAgICAgICAgYm9vbCBib3R0b20gPSAoYW5jaG9yID09IDIgfHwgYW5jaG9yID09IDMp
OyAvLyBCTCBvciBCUgogICAgICAgICAgICAgb3ZlcmxheVJlY3QueCA9IHJpZ2h0ID8gKHZpZXdw
b3J0V2lkdGggLSBuZXdTdXJmYWNlLT53KSA6IDA7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5n
L3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvcGx2ay5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2Zm
bXBlZy1yZW5kZXJlcnMvcGx2ay5jcHAKaW5kZXggYmMxNmZmMi4uYmFjMTg1YiAxMDA2NDQKLS0t
IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3BsdmsuY3BwCisrKyBiL2Fw
cC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9wbHZrLmNwcApAQCAtMTM4MiwxMCAr
MTM4MiwxMCBAQCB2b2lkIFBsVmtSZW5kZXJlcjo6cmVuZGVyRnJhbWUoQVZGcmFtZSAqZnJhbWUp
CiAgICAgICAgICAgICAgICAgb3ZlcmxheVBhcnRzW2ldLmRzdC54MCA9IDA7DQogICAgICAgICAg
ICAgICAgIG92ZXJsYXlQYXJ0c1tpXS5kc3QueTAgPSBTRExfbWF4KDAsIHRhcmdldEZyYW1lLmNy
b3AueTEgLSBvdmVybGF5UGFydHNbaV0uc3JjLnkxKTsNCiAgICAgICAgICAgICB9DQotICAgICAg
ICAgICAgZWxzZSBpZiAoaSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcpIHsNCi0gICAgICAgICAg
ICAgICAgLy8gVG9wIGxlZnQNCi0gICAgICAgICAgICAgICAgb3ZlcmxheVBhcnRzW2ldLmRzdC54
MCA9IDA7DQotICAgICAgICAgICAgICAgIG92ZXJsYXlQYXJ0c1tpXS5kc3QueTAgPSAwOw0KKyAg
ICAgICAgICAgIGVsc2UgaWYgKGkgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8IGkgPT0gT3Zl
cmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHsNCisgICAgICAgICAgICAgICAgaW50IGFuY2hv
cj1TZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5nZXRPdmVybGF5QW5jaG9yKHN0
YXRpY19jYXN0PE92ZXJsYXk6Ok92ZXJsYXlUeXBlPihpKSk7DQorICAgICAgICAgICAgICAgIG92
ZXJsYXlQYXJ0c1tpXS5kc3QueDA9KGFuY2hvcj09MSB8fCBhbmNob3I9PTMpID8gU0RMX21heCgw
LHRhcmdldEZyYW1lLmNyb3AueDEtb3ZlcmxheVBhcnRzW2ldLnNyYy54MSkgOiAwOw0KKyAgICAg
ICAgICAgICAgICBvdmVybGF5UGFydHNbaV0uZHN0LnkwPShhbmNob3I9PTIgfHwgYW5jaG9yPT0z
KSA/IFNETF9tYXgoMCx0YXJnZXRGcmFtZS5jcm9wLnkxLW92ZXJsYXlQYXJ0c1tpXS5zcmMueTEp
IDogMDsNCiAgICAgICAgICAgICB9DQogICAgICAgICAgICAgZWxzZSBpZiAoaSA9PSBPdmVybGF5
OjpPdmVybGF5VG91Y2hCdXR0b25NZW51IHx8IGkgPT0gT3ZlcmxheTo6T3ZlcmxheVRvdWNoQnV0
dG9uS2JkIHx8DQogICAgICAgICAgICAgICAgICAgICAgaSA9PSBPdmVybGF5OjpPdmVybGF5VG91
Y2hCdXR0b25Ub3VjaE1vZGUpIHsNCmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2Zm
bXBlZy1yZW5kZXJlcnMvc2RsdmlkLmNwcCBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJl
bmRlcmVycy9zZGx2aWQuY3BwCmluZGV4IDU2N2JmMTkuLmYxMzI1ZWQgMTAwNjQ0Ci0tLSBhL2Fw
cC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9zZGx2aWQuY3BwCisrKyBiL2FwcC9z
dHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9zZGx2aWQuY3BwCkBAIC0yNDEsMTEgKzI0
MSwxMSBAQCB2b2lkIFNkbFJlbmRlcmVyOjpyZW5kZXJPdmVybGF5KE92ZXJsYXk6Ok92ZXJsYXlU
eXBlIHR5cGUpCiAgICAgICAgICAgICAgICAgbV9PdmVybGF5UmVjdHNbdHlwZV0ueCA9IDA7CiAg
ICAgICAgICAgICAgICAgbV9PdmVybGF5UmVjdHNbdHlwZV0ueSA9IHZpZXdwb3J0UmVjdC5oIC0g
bmV3U3VyZmFjZS0+aDsKICAgICAgICAgICAgIH0KLSAgICAgICAgICAgIGVsc2UgaWYgKHR5cGUg
PT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7CisgICAgICAgICAgICBlbHNlIGlmICh0eXBlID09
IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZyB8fCB0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhh
cmR3YXJlKSB7CiAgICAgICAgICAgICAgICAgLy8gVmliZW1pczogdXNlci1jb25maWd1cmFibGUg
Y29ybmVyIChTREwgb3JpZ2luIGlzIHVwcGVyLWxlZnQpLgogICAgICAgICAgICAgICAgIFNETF9S
ZWN0IHZpZXdwb3J0UmVjdDsKICAgICAgICAgICAgICAgICBTRExfUmVuZGVyR2V0Vmlld3BvcnQo
bV9SZW5kZXJlciwgJnZpZXdwb3J0UmVjdCk7Ci0gICAgICAgICAgICAgICAgaW50IGFuY2hvciA9
IFNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmdldERlYnVnT3ZlcmxheUFuY2hv
cigpOworICAgICAgICAgICAgICAgIGludCBhbmNob3IgPSBTZXNzaW9uOjpnZXQoKS0+Z2V0T3Zl
cmxheU1hbmFnZXIoKS5nZXRPdmVybGF5QW5jaG9yKHR5cGUpOwogICAgICAgICAgICAgICAgIGJv
b2wgcmlnaHQgPSAoYW5jaG9yID09IDEgfHwgYW5jaG9yID09IDMpOyAgLy8gVFIgb3IgQlIKICAg
ICAgICAgICAgICAgICBib29sIGJvdHRvbSA9IChhbmNob3IgPT0gMiB8fCBhbmNob3IgPT0gMyk7
IC8vIEJMIG9yIEJSCiAgICAgICAgICAgICAgICAgbV9PdmVybGF5UmVjdHNbdHlwZV0ueCA9IHJp
Z2h0ID8gKHZpZXdwb3J0UmVjdC53IC0gbmV3U3VyZmFjZS0+dykgOiAwOwpkaWZmIC0tZ2l0IGEv
YXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3ZhYXBpLmNwcCBiL2FwcC9zdHJl
YW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92YWFwaS5jcHAKaW5kZXggYWI2NWUwYi4uMjg0
M2ZkNiAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3Zh
YXBpLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdmFhcGku
Y3BwCkBAIC03NDEsOSArNzQxLDkgQEAgdm9pZCBWQUFQSVJlbmRlcmVyOjpub3RpZnlPdmVybGF5
VXBkYXRlZChPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBlKQogICAgICAgICAgICAgb3ZlcmxheVJl
Y3QueCA9IDA7CiAgICAgICAgICAgICBvdmVybGF5UmVjdC55ID0gLW5ld1N1cmZhY2UtPmg7CiAg
ICAgICAgIH0KLSAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcp
IHsKKyAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgdHlw
ZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAgICAgLy8gVmli
ZW1pczogdXNlci1jb25maWd1cmFibGUgY29ybmVyICh1cHBlci1sZWZ0IG9yaWdpbikuCi0gICAg
ICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCku
Z2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAgICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lv
bjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0T3ZlcmxheUFuY2hvcih0eXBlKTsKICAg
ICAgICAgICAgIGJvb2wgcmlnaHQgPSAoYW5jaG9yID09IDEgfHwgYW5jaG9yID09IDMpOyAgLy8g
VFIgb3IgQlIKICAgICAgICAgICAgIGJvb2wgYm90dG9tID0gKGFuY2hvciA9PSAyIHx8IGFuY2hv
ciA9PSAzKTsgLy8gQkwgb3IgQlIKICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnggPSByaWdodCA/
IChtX0Rpc3BsYXlXaWR0aCAtIG5ld1N1cmZhY2UtPncpIDogMDsKZGlmZiAtLWdpdCBhL2FwcC9z
dHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92ZHBhdS5jcHAgYi9hcHAvc3RyZWFtaW5n
L3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdmRwYXUuY3BwCmluZGV4IDJmOWUwYzMuLjkwNmFjY2Mg
MTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92ZHBhdS5j
cHAKKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3ZkcGF1LmNwcApA
QCAtNDM2LDkgKzQzNiw5IEBAIHZvaWQgVkRQQVVSZW5kZXJlcjo6bm90aWZ5T3ZlcmxheVVwZGF0
ZWQoT3ZlcmxheTo6T3ZlcmxheVR5cGUgdHlwZSkKICAgICAgICAgICAgIG92ZXJsYXlSZWN0Lngw
ID0gMDsKICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnkwID0gbV9EaXNwbGF5SGVpZ2h0IC0gbmV3
U3VyZmFjZS0+aDsKICAgICAgICAgfQotICAgICAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6
Ok92ZXJsYXlEZWJ1ZykgeworICAgICAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJs
YXlEZWJ1ZyB8fCB0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlKSB7CiAgICAg
ICAgICAgICAvLyBWaWJlbWlzOiB1c2VyLWNvbmZpZ3VyYWJsZSBjb3JuZXIgKHVwcGVyLWxlZnQg
b3JpZ2luKS4KLSAgICAgICAgICAgIGludCBhbmNob3IgPSBTZXNzaW9uOjpnZXQoKS0+Z2V0T3Zl
cmxheU1hbmFnZXIoKS5nZXREZWJ1Z092ZXJsYXlBbmNob3IoKTsKKyAgICAgICAgICAgIGludCBh
bmNob3IgPSBTZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5nZXRPdmVybGF5QW5j
aG9yKHR5cGUpOwogICAgICAgICAgICAgYm9vbCByaWdodCA9IChhbmNob3IgPT0gMSB8fCBhbmNo
b3IgPT0gMyk7ICAvLyBUUiBvciBCUgogICAgICAgICAgICAgYm9vbCBib3R0b20gPSAoYW5jaG9y
ID09IDIgfHwgYW5jaG9yID09IDMpOyAvLyBCTCBvciBCUgogICAgICAgICAgICAgb3ZlcmxheVJl
Y3QueDAgPSByaWdodCA/IChtX0Rpc3BsYXlXaWR0aCAtIG5ld1N1cmZhY2UtPncpIDogMDsKZGlm
ZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9hdnNhbXBs
ZWxheWVyLm1tIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3Z0X2F2c2Ft
cGxlbGF5ZXIubW0KaW5kZXggYmQ1NTI4MS4uMTNkODhjNiAxMDA2NDQKLS0tIGEvYXBwL3N0cmVh
bWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3Z0X2F2c2FtcGxlbGF5ZXIubW0KKysrIGIvYXBw
L3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3Z0X2F2c2FtcGxlbGF5ZXIubW0KQEAg
LTQ5Niw2ICs0OTYsNyBAQCBwdWJsaWM6CiAgICAgICAgICAgICBbbV9PdmVybGF5VGV4dEZpZWxk
c1t0eXBlXSBzZXRTZWxlY3RhYmxlOk5PXTsKIAogICAgICAgICAgICAgc3dpdGNoICh0eXBlKSB7
CisgICAgICAgICAgICBjYXNlIE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlOgogICAgICAg
ICAgICAgY2FzZSBPdmVybGF5OjpPdmVybGF5RGVidWc6CiAgICAgICAgICAgICAgICAgW21fT3Zl
cmxheVRleHRGaWVsZHNbdHlwZV0gc2V0QWxpZ25tZW50Ok5TVGV4dEFsaWdubWVudExlZnRdOwog
ICAgICAgICAgICAgICAgIGJyZWFrOwpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9m
Zm1wZWctcmVuZGVyZXJzL3Z0X21ldGFsLm1tIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWct
cmVuZGVyZXJzL3Z0X21ldGFsLm1tCmluZGV4IDc5YjE2NWQuLjMzNGVlZmYgMTAwNjQ0Ci0tLSBh
L2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9tZXRhbC5tbQorKysgYi9h
cHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdnRfbWV0YWwubW0KQEAgLTYwMCw3
ICs2MDAsNyBAQCBwdWJsaWM6CiAgICAgICAgICAgICAgICAgICAgIHJlbmRlclJlY3QueCA9IDA7
CiAgICAgICAgICAgICAgICAgICAgIHJlbmRlclJlY3QueSA9IDA7CiAgICAgICAgICAgICAgICAg
fQotICAgICAgICAgICAgICAgIGVsc2UgaWYgKGkgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7
CisgICAgICAgICAgICAgICAgZWxzZSBpZiAoaSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwg
aSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAgICAgICAgICAg
ICAvLyBUb3AgbGVmdAogICAgICAgICAgICAgICAgICAgICByZW5kZXJSZWN0LnggPSAwOwogICAg
ICAgICAgICAgICAgICAgICByZW5kZXJSZWN0LnkgPSBtX0xhc3REcmF3YWJsZUhlaWdodCAtIG92
ZXJsYXlUZXh0dXJlLmhlaWdodDsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZt
cGVnLmNwcCBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLmNwcAppbmRleCAyYWMxYTZlLi40
YTZlMGMwIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy5jcHAKKysrIGIv
YXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWcuY3BwCkBAIC0xLDUgKzEsNiBAQAogI2luY2x1ZGUg
PExpbWVsaWdodC5oPgogI2luY2x1ZGUgImZmbXBlZy5oIgorI2luY2x1ZGUgIm1vb25saWdodG9z
L2xvY2FsaGFyZHdhcmUuaCIKICNpbmNsdWRlICJzdHJlYW1pbmcvc2Vzc2lvbi5oIgogI2luY2x1
ZGUgImJhY2tlbmQvc3lzdGVtcHJvcGVydGllcy5oIgogI2luY2x1ZGUgInNldHRpbmdzL3N0cmVh
bWluZ3ByZWZlcmVuY2VzLmgiCkBAIC0yNDQwLDYgKzI0NDEsMTEgQEAgaW50IEZGbXBlZ1ZpZGVv
RGVjb2Rlcjo6c3VibWl0RGVjb2RlVW5pdChQREVDT0RFX1VOSVQgZHUpCiAgICAgICAgICAgICBT
ZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5zZXRPdmVybGF5VGV4dFVwZGF0ZWQo
T3ZlcmxheTo6T3ZlcmxheURlYnVnKTsKICAgICAgICAgfQogCisgICAgICAgIGlmKFNlc3Npb246
OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmlzT3ZlcmxheUVuYWJsZWQoT3ZlcmxheTo6T3Zl
cmxheUxvY2FsSGFyZHdhcmUpKSB7CisgICAgICAgICAgICBRQnl0ZUFycmF5IHRleHQ9TG9jYWxI
YXJkd2FyZTo6b3ZlcmxheVRleHQoKS50b1V0ZjgoKTsKKyAgICAgICAgICAgIFNlc3Npb246Omdl
dCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLnVwZGF0ZU92ZXJsYXlUZXh0KE92ZXJsYXk6Ok92ZXJs
YXlMb2NhbEhhcmR3YXJlLHRleHQuY29uc3REYXRhKCkpOworICAgICAgICB9CisKICAgICAgICAg
Ly8gQWNjdW11bGF0ZSB0aGVzZSB2YWx1ZXMgaW50byB0aGUgZ2xvYmFsIHN0YXRzCiAgICAgICAg
IGFkZFZpZGVvU3RhdHMobV9BY3RpdmVXbmRWaWRlb1N0YXRzLCBtX0dsb2JhbFZpZGVvU3RhdHMp
OwogCmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5hZ2VyLmNwcCBi
L2FwcC9zdHJlYW1pbmcvdmlkZW8vb3ZlcmxheW1hbmFnZXIuY3BwCmluZGV4IDkyZTZjNmQuLjFj
YjNhOTIgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vb3ZlcmxheW1hbmFnZXIuY3Bw
CisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vb3ZlcmxheW1hbmFnZXIuY3BwCkBAIC0xLDYgKzEs
MTIgQEAKICNpbmNsdWRlICJvdmVybGF5bWFuYWdlci5oIgogI2luY2x1ZGUgInBhdGguaCIKICNp
bmNsdWRlICJzZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5oIgorI2luY2x1ZGUgIm1vb25s
aWdodG9zL2xvY2FsaGFyZHdhcmUuaCIKKyNpbmNsdWRlICJtb29ubGlnaHRvcy9vdmVybGF5c3R5
bGUuaCIKKyNpbmNsdWRlIDxRU2V0dGluZ3M+CisjaW5jbHVkZSA8UUltYWdlPgorI2luY2x1ZGUg
PFFQYWludGVyPgorI2luY2x1ZGUgPFFDb2xvcj4KIAogdXNpbmcgbmFtZXNwYWNlIE92ZXJsYXk7
CiAKQEAgLTksNiArMTUsMTMgQEAgaW50IE92ZXJsYXlNYW5hZ2VyOjpnZXREZWJ1Z092ZXJsYXlB
bmNob3IoKQogICAgIHJldHVybiBzdGF0aWNfY2FzdDxpbnQ+KFN0cmVhbWluZ1ByZWZlcmVuY2Vz
OjpnZXQoKS0+cGVyZk92ZXJsYXlQb3NpdGlvbik7CiB9CiAKK2ludCBPdmVybGF5TWFuYWdlcjo6
Z2V0T3ZlcmxheUFuY2hvcihPdmVybGF5VHlwZSB0eXBlKSB7CisgICAgaW50IHN0cmVhbT1nZXRE
ZWJ1Z092ZXJsYXlBbmNob3IoKTsKKyAgICBpZih0eXBlIT1PdmVybGF5TG9jYWxIYXJkd2FyZSkg
cmV0dXJuIHN0cmVhbTsKKyAgICBpbnQgbG9jYWw9cUJvdW5kKDAsUVNldHRpbmdzKCkudmFsdWUo
ImVjbGlwc2UvbG9jYWxQb3NpdGlvbiIsMSkudG9JbnQoKSwzKTsKKyAgICByZXR1cm4gaXNPdmVy
bGF5RW5hYmxlZChPdmVybGF5RGVidWcpICYmIGxvY2FsPT1zdHJlYW0gPyAobG9jYWwgXiAxKSA6
IGxvY2FsOworfQorCiBPdmVybGF5TWFuYWdlcjo6T3ZlcmxheU1hbmFnZXIoKSA6CiAgICAgbV9S
ZW5kZXJlcihudWxscHRyKSwKICAgICBtX0ZvbnREYXRhKFBhdGg6OnJlYWREYXRhRmlsZSgiTW9k
ZVNldmVuLnR0ZiIpKQpAQCAtMzIsOCArNDUsMTAgQEAgT3ZlcmxheU1hbmFnZXI6Ok92ZXJsYXlN
YW5hZ2VyKCkgOgogICAgICAgICBicmVhazsKICAgICB9CiAKLSAgICBtX092ZXJsYXlzW092ZXJs
YXlUeXBlOjpPdmVybGF5RGVidWddLmNvbG9yID0gezB4RDAsIDB4RDAsIDB4MDAsIDB4RkZ9Owor
ICAgIG1fT3ZlcmxheXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlEZWJ1Z10uY29sb3IgPSB7MHhFQywg
MHhFRSwgMHhGMSwgMHhGRn07CiAgICAgbV9PdmVybGF5c1tPdmVybGF5VHlwZTo6T3ZlcmxheURl
YnVnXS5mb250U2l6ZSA9IGRlYnVnRm9udFNpemU7CisgICAgbV9PdmVybGF5c1tPdmVybGF5TG9j
YWxIYXJkd2FyZV0uY29sb3IgPSB7MHhFQywweEVFLDB4RjEsMHhGRn07CisgICAgbV9PdmVybGF5
c1tPdmVybGF5TG9jYWxIYXJkd2FyZV0uZm9udFNpemUgPSBkZWJ1Z0ZvbnRTaXplOwogCiAgICAg
bV9PdmVybGF5c1tPdmVybGF5VHlwZTo6T3ZlcmxheVN0YXR1c1VwZGF0ZV0uY29sb3IgPSB7MHhD
QywgMHgwMCwgMHgwMCwgMHhGRn07CiAgICAgbV9PdmVybGF5c1tPdmVybGF5VHlwZTo6T3Zlcmxh
eVN0YXR1c1VwZGF0ZV0uZm9udFNpemUgPSAzNjsKQEAgLTM2OCwxMSArMzgzLDMyIEBAIHZvaWQg
T3ZlcmxheU1hbmFnZXI6Om5vdGlmeU92ZXJsYXlVcGRhdGVkKE92ZXJsYXlUeXBlIHR5cGUpCiAg
ICAgfQogCiAgICAgaWYgKG1fT3ZlcmxheXNbdHlwZV0uZW5hYmxlZCkgewotICAgICAgICAvLyBU
aGUgX1dyYXBwZWQgdmFyaWFudCBpcyByZXF1aXJlZCBmb3IgbGluZSBicmVha3MgdG8gd29yawot
ICAgICAgICBTRExfU3VyZmFjZSogc3VyZmFjZSA9IFRURl9SZW5kZXJUZXh0X0JsZW5kZWRfV3Jh
cHBlZChtX092ZXJsYXlzW3R5cGVdLmZvbnQsCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIG1fT3ZlcmxheXNbdHlwZV0udGV4dCwK
KyAgICAgICAgUUJ5dGVBcnJheSB0ZXh0KG1fT3ZlcmxheXNbdHlwZV0udGV4dCk7CisgICAgICAg
IGJvb2wgY2FyZD10eXBlPT1PdmVybGF5RGVidWcgfHwgdHlwZT09T3ZlcmxheUxvY2FsSGFyZHdh
cmU7CisgICAgICAgIGlmKHR5cGU9PU92ZXJsYXlEZWJ1ZykgeworICAgICAgICAgICAgaWYoIVFT
ZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL3N0cmVhbURldGFpbGVkIix0cnVlKS50b0Jvb2woKSkg
eworICAgICAgICAgICAgICAgIFFTdHJpbmdMaXN0IGNvbXBhY3Q7CisgICAgICAgICAgICAgICAg
Zm9yKGNvbnN0IFFTdHJpbmcmIGxpbmU6UVN0cmluZzo6ZnJvbVV0ZjgodGV4dCkuc3BsaXQoJ1xu
JykpIHsKKyAgICAgICAgICAgICAgICAgICAgaWYobGluZS5jb250YWlucygiRlBTIixRdDo6Q2Fz
ZUluc2Vuc2l0aXZlKSB8fCBsaW5lLmNvbnRhaW5zKCJmcmFtZSByYXRlIixRdDo6Q2FzZUluc2Vu
c2l0aXZlKSB8fCBsaW5lLmNvbnRhaW5zKCJsYXRlbmN5IixRdDo6Q2FzZUluc2Vuc2l0aXZlKSB8
fCBsaW5lLmNvbnRhaW5zKCJiaXRyYXRlIixRdDo6Q2FzZUluc2Vuc2l0aXZlKSB8fCBsaW5lLmNv
bnRhaW5zKCJkcm9wcGVkIixRdDo6Q2FzZUluc2Vuc2l0aXZlKSB8fCBsaW5lLmNvbnRhaW5zKCJy
ZXNvbHV0aW9uIixRdDo6Q2FzZUluc2Vuc2l0aXZlKSkgY29tcGFjdC5hcHBlbmQobGluZSk7Cisg
ICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIGlmKGNvbXBhY3QuaXNFbXB0eSgpKSBj
b21wYWN0PVFTdHJpbmc6OmZyb21VdGY4KHRleHQpLnNwbGl0KCdcbicpLm1pZCgwLDUpOworICAg
ICAgICAgICAgICAgIHRleHQ9Y29tcGFjdC5qb2luKCdcbicpLnRvVXRmOCgpOworICAgICAgICAg
ICAgfQorICAgICAgICAgICAgdGV4dC5wcmVwZW5kKCJFY2xpcHNlT1MgfCBTVFJFQU1cbiIpOwor
ICAgICAgICB9CisgICAgICAgIFNETF9TdXJmYWNlKiBzdXJmYWNlID0gVFRGX1JlbmRlclVURjhf
QmxlbmRlZF9XcmFwcGVkKG1fT3ZlcmxheXNbdHlwZV0uZm9udCwKKyAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGV4dC5jb25zdERh
dGEoKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgbV9PdmVybGF5c1t0eXBlXS5jb2xvciwKLSAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgMTAyNCk7CisgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNh
cmQgPyA0ODAgOiAxMDI0KTsKKyAgICAgICAgaWYoY2FyZCAmJiBzdXJmYWNlKSB7CisgICAgICAg
ICAgICBRSW1hZ2UgaW1hZ2U9RWNsaXBzZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNpemUoc3VyZmFj
ZS0+dysyOCxzdXJmYWNlLT5oKzI4KSxTdHJlYW1pbmdQcmVmZXJlbmNlczo6Z2V0KCktPnVpQWNj
ZW50SW5kZXgsUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2Uvb3ZlcmxheU9wYWNpdHkiLDg1KS50
b0ludCgpKTsKKyAgICAgICAgICAgIFNETF9TdXJmYWNlKiBwYW5lbD1pbWFnZS5pc051bGwoKSA/
IG51bGxwdHIgOiBTRExfQ3JlYXRlUkdCU3VyZmFjZVdpdGhGb3JtYXQoMCxpbWFnZS53aWR0aCgp
LGltYWdlLmhlaWdodCgpLDMyLFNETF9QSVhFTEZPUk1BVF9SR0JBMzIpOworICAgICAgICAgICAg
aWYocGFuZWwpIHsKKyAgICAgICAgICAgICAgICBmb3IoaW50IHJvdz0wO3JvdzxpbWFnZS5oZWln
aHQoKTsrK3JvdykgbWVtY3B5KHN0YXRpY19jYXN0PGNoYXIqPihwYW5lbC0+cGl4ZWxzKStyb3cq
cGFuZWwtPnBpdGNoLGltYWdlLmNvbnN0U2NhbkxpbmUocm93KSxpbWFnZS53aWR0aCgpKjQpOwor
ICAgICAgICAgICAgICAgIFNETF9SZWN0IGRlc3Q9ezE0LDE0LHN1cmZhY2UtPncsc3VyZmFjZS0+
aH07IFNETF9CbGl0U3VyZmFjZShzdXJmYWNlLG51bGxwdHIscGFuZWwsJmRlc3QpOworICAgICAg
ICAgICAgICAgIFNETF9GcmVlU3VyZmFjZShzdXJmYWNlKTsgc3VyZmFjZT1wYW5lbDsKKyAgICAg
ICAgICAgIH0KKyAgICAgICAgfQogCiAgICAgICAgIFNETF9BdG9taWNTZXRQdHIoKHZvaWQqKikm
bV9PdmVybGF5c1t0eXBlXS5zdXJmYWNlLCBzdXJmYWNlKTsKICAgICB9CmRpZmYgLS1naXQgYS9h
cHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5hZ2VyLmggYi9hcHAvc3RyZWFtaW5nL3ZpZGVv
L292ZXJsYXltYW5hZ2VyLmgKaW5kZXggZTE5ZmMwYy4uNTA5NWZkNiAxMDA2NDQKLS0tIGEvYXBw
L3N0cmVhbWluZy92aWRlby9vdmVybGF5bWFuYWdlci5oCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlk
ZW8vb3ZlcmxheW1hbmFnZXIuaApAQCAtMTAsNiArMTAsNyBAQCBuYW1lc3BhY2UgT3ZlcmxheSB7
CiAKIGVudW0gT3ZlcmxheVR5cGUgewogICAgIE92ZXJsYXlEZWJ1ZywKKyAgICBPdmVybGF5TG9j
YWxIYXJkd2FyZSwKICAgICBPdmVybGF5U3RhdHVzVXBkYXRlLAogICAgIE92ZXJsYXlTZXJ2ZXJD
b21tYW5kcywKICAgICBPdmVybGF5UXVpY2tNZW51LApAQCAtNzAsNiArNzEsNyBAQCBwdWJsaWM6
CiAgICAgLy8gcHJlZmVyZW5jZS4gUmV0dXJucyBTdHJlYW1pbmdQcmVmZXJlbmNlczo6UGVyZk92
ZXJsYXlQb3NpdGlvbiBhcyBhbiBpbnQKICAgICAvLyAoMD1UTCwgMT1UUiwgMj1CTCwgMz1CUiku
IFJlbmRlcmVycyBtYXAgdGhpcyB0byB0aGVpciBvd24gY29vcmRpbmF0ZSBzcGFjZS4KICAgICBp
bnQgZ2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAgaW50IGdldE92ZXJsYXlBbmNob3IoT3Zl
cmxheVR5cGUgdHlwZSk7CiAKICAgICB2b2lkIHNldE92ZXJsYXlSZW5kZXJlcihJT3ZlcmxheVJl
bmRlcmVyKiByZW5kZXJlcik7CiAKZGlmZiAtLWdpdCBhL3BhY2thZ2luZy9mbGF0cGFrL2lvLmdp
dGh1Yi5uYXZ5YXMzMjEuVmliZW1pcy5kZXNrdG9wIGIvcGFja2FnaW5nL2ZsYXRwYWsvaW8uZ2l0
aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AKaW5kZXggMDQ1YWRiZS4uZjEyZGE1ZCAxMDA2
NDQKLS0tIGEvcGFja2FnaW5nL2ZsYXRwYWsvaW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRl
c2t0b3AKKysrIGIvcGFja2FnaW5nL2ZsYXRwYWsvaW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlz
LmRlc2t0b3AKQEAgLTEsNiArMSw2IEBACiBbRGVza3RvcCBFbnRyeV0KIFR5cGU9QXBwbGljYXRp
b24KLU5hbWU9VmliZW1pcworTmFtZT1FY2xpcHNlCiBHZW5lcmljTmFtZT1HYW1lIFN0cmVhbWlu
ZyBDbGllbnQKIENvbW1lbnQ9U3RyZWFtIGdhbWVzIGFuZCBhcHBsaWNhdGlvbnMgZnJvbSBhIFN1
bnNoaW5lIC8gQXBvbGxvIC8gVmliZXBvbGxvIGhvc3QKIEV4ZWM9dmliZW1pcwo=
VIBEMIS_PATCH_B64
cat > /usr/local/share/moonlight-os/install-frontends.sh <<'FRONTENDS_INSTALL'
#!/usr/bin/env bash
# Run in Anaconda's installed root or a disposable Fedora test container.
set -euo pipefail
source "${FRONTENDS_LOCK:-/usr/local/share/moonlight-os/FRONTENDS.lock}"
DEST=${FRONTENDS_DEST:-/usr/local/libexec/moonlight-os/frontends}
SHARE=${FRONTENDS_SHARE_DEST:-/usr/local/share}
CACHE=${FRONTENDS_CACHE:-/var/cache/moonlight-frontends}
SRC=${ARTEMIS_SOURCE:-/usr/local/src/artemis}
mkdir -p "$DEST" "$CACHE"
fetch() {
  local url=$1 sha=$2 output=$3
  if [[ ! -f "$output" ]]; then curl -LfsS --retry 3 -o "$output" "$url"; fi
  printf '%s  %s\n' "$sha" "$output" | sha256sum -c -
}
# The upstream AppImage crashes in FFmpeg CUDA probing without NVIDIA libraries.
# Build the same stable tag against Fedora's tested Qt/SDL/FFmpeg stack instead.
VIBSRC=${VIBEMIS_SOURCE:-/usr/local/src/vibemis}
if [[ ! -d "$VIBSRC/.git" ]]; then git clone --no-checkout "$VIBEMIS_REPO" "$VIBSRC"; fi
git -C "$VIBSRC" checkout --detach "$VIBEMIS_COMMIT"
git -C "$VIBSRC" submodule update --init --recursive
PATCH=${VIBEMIS_PATCH:-/usr/local/share/moonlight-os/vibemis-crimson.patch}
printf '%s  %s\n' "$VIBEMIS_PATCH_SHA256" "$PATCH" | sha256sum -c -
if git -C "$VIBSRC" apply --reverse --check "$PATCH" 2>/dev/null; then
  echo 'Reviewed Vibemis patch already applied.'
else
  git -C "$VIBSRC" apply --check "$PATCH"
  git -C "$VIBSRC" apply "$PATCH"
fi
(cd "$VIBSRC" && { qmake6 vibemis.pro CONFIG+=release; (cd app && qmake6 app.pro CONFIG+=release); } 2>&1 | tee configure.log; for feature in "FFmpeg decoder selected" "VAAPI renderer selected" "EGL renderer selected"; do grep -Fq "$feature" configure.log; done; make release -j2)
mkdir -p "$DEST/vibemis/usr/bin"
install -m 0755 "$VIBSRC/app/vibemis" "$DEST/vibemis/usr/bin/vibemis"
install -d "$SHARE/applications"
cat > "$SHARE/applications/com.vibemis.Vibemis.desktop" <<'ECLIPSE_DESKTOP'
[Desktop Entry]
Name=Eclipse
Comment=EclipseOS streaming frontend
Exec=/usr/local/bin/moonlight-launch vibemis
Icon=eclipse
Terminal=false
Type=Application
Categories=Game;Network;
ECLIPSE_DESKTOP
for size in 128 256 512; do
  install -Dm0644 "$VIBSRC/app/res/icons/hicolor/${size}x${size}/apps/eclipse.png" \
    "$SHARE/icons/hicolor/${size}x${size}/apps/eclipse.png"
done
cat > "$DEST/vibemis/AppRun" <<'VIBRUN'
#!/usr/bin/env bash
exec "$(dirname "$(readlink -f "$0")")/usr/bin/vibemis" "$@"
VIBRUN
chmod 0755 "$DEST/vibemis/AppRun"
fetch "$PEGASUS_URL" "$PEGASUS_SHA256" "$CACHE/pegasus.zip"
mkdir -p "$DEST/pegasus"
unzip -qo "$CACHE/pegasus.zip" -d "$DEST/pegasus"
chmod 0755 "$DEST/pegasus/pegasus-fe"
if [[ ! -d "$SRC/.git" ]]; then git clone --no-checkout "$ARTEMIS_REPO" "$SRC"; fi
git -C "$SRC" checkout --detach "$ARTEMIS_COMMIT"
# Platform prebuilts are unnecessary on Linux; use exactly the source gitlinks.
git -C "$SRC" submodule update --init --recursive -- \
  moonlight-common-c/moonlight-common-c qmdnsengine/qmdnsengine app/SDL_GameControllerDB \
  soundio/libsoundio h264bitstream/h264bitstream
(cd "$SRC" && { qmake6 artemis.pro CONFIG+=release; (cd app && qmake6 app.pro CONFIG+=release); } 2>&1 | tee configure.log; for feature in "FFmpeg decoder selected" "VAAPI renderer selected" "EGL renderer selected"; do grep -Fq "$feature" configure.log; done; make release -j2)
install -m 0755 "$SRC/app/artemis" "$DEST/artemis"
cat > "$DEST/versions.conf" <<VERSIONS
VIBEMIS_VERSION=$VIBEMIS_VERSION
VIBEMIS_COMMIT=$VIBEMIS_COMMIT
VIBEMIS_PATCH_SHA256=$VIBEMIS_PATCH_SHA256
ARTEMIS_COMMIT=$ARTEMIS_COMMIT
PEGASUS_VERSION=$PEGASUS_VERSION
PEGASUS_SHA256=$PEGASUS_SHA256
VERSIONS
# Fail rather than publish a selector that points to an unusable loader.
for binary in "$DEST/vibemis/usr/bin/vibemis" "$DEST/artemis" "$DEST/pegasus/pegasus-fe"; do
  file "$binary" | grep -q 'x86-64'
  dependencies=$(ldd "$binary")
  if grep -q 'not found' <<< "$dependencies"; then printf '%s\n' "$dependencies" >&2; exit 1; fi
done
FRONTENDS_INSTALL
cat > /usr/local/bin/moonlight-launch <<'FRONTENDS_LAUNCH'
#!/usr/bin/env bash
set -euo pipefail
# Keep each client's bundled Qt/SDL libraries confined to its own child process.
unset LD_LIBRARY_PATH QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH
export QT_QPA_PLATFORM=xcb
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
BASE=${MOONLIGHT_FRONTEND_BASE:-/usr/local/libexec/moonlight-os}
case "${1:-}" in
  moonlight|cocoos) exec "$BASE/$1" "${@:2}" ;;
  artemis) exec "$BASE/frontends/artemis" "${@:2}" ;;
  vibemis)
    # Retain the tested full iHD driver on this Intel target.
    if [[ -f /usr/lib64/dri-nonfree/iHD_drv_video.so ]]; then
      export LIBVA_DRIVERS_PATH=/usr/lib64/dri-nonfree
    fi
    exec "$BASE/frontends/vibemis/AppRun" "${@:2}"
    ;;
  pegasus) exec "$BASE/frontends/pegasus/pegasus-fe" "${@:2}" ;;
  *) echo 'usage: moonlight-launch {moonlight|cocoos|vibemis|artemis|pegasus}' >&2; exit 2 ;;
esac
FRONTENDS_LAUNCH
cat > /usr/local/bin/moonlight-frontend-select <<'FRONTENDS_SELECT'
#!/usr/bin/env bash
# tty1 boot chooser. Selection is remembered; unattended boot has a short default.
set -euo pipefail
CONF=${MOONLIGHT_CLIENT_CONF:-/etc/moonlight-os-client.conf}
CLIENT=moonlight
if [[ -r "$CONF" ]]; then
  saved=$(sed -n 's/^CLIENT=//p' "$CONF")
  case "$saved" in moonlight|vibemis|artemis|pegasus|cocoos) CLIENT=$saved ;; esac
fi
printf '\033[40m\033[1;31m\n🌑 EclipseOS • FRONTEND\033[0;31m\n'
printf '  1) Eclipse\n  2) Artemis\n  3) Pegasus launcher\n  4) Moonlight\n  5) CocoOS\n'
DISPLAY_CLIENT=$CLIENT
[[ $CLIENT != vibemis ]] || DISPLAY_CLIENT=Eclipse
printf 'Enter keeps %s; auto-start in 8 seconds.\nChoose: ' "$DISPLAY_CLIENT"
choice=''
read -r -t 8 choice || true
case "$choice" in
  1) CLIENT=vibemis ;; 2) CLIENT=artemis ;; 3) CLIENT=pegasus ;;
  4) CLIENT=moonlight ;; 5) CLIENT=cocoos ;;
  '' ) ;; *) printf '\nUnknown selection; keeping %s.\n' "$CLIENT" ;;
esac
# The settings helper validates the enum; do not source arbitrary user input.
sudo "${MOONLIGHT_CLIENT_SETTER:-/usr/local/bin/moonlight-os-client}" "$CLIENT"
FRONTENDS_SELECT
chmod 0755 /usr/local/bin/moonlight-launch /usr/local/bin/moonlight-frontend-select
bash /usr/local/share/moonlight-os/install-frontends.sh
install -d -m 0755 /home/moonlight/.config/pegasus-frontend/metafiles
cat > /home/moonlight/.config/pegasus-frontend/metafiles/metadata.pegasus.txt <<'PEGASUS_META'
collection: EclipseOS Streaming
shortname: pc
files:
  /usr/local/libexec/moonlight-os/moonlight
  /usr/local/libexec/moonlight-os/frontends/vibemis/usr/bin/vibemis
  /usr/local/libexec/moonlight-os/frontends/artemis
  /usr/local/libexec/moonlight-os/cocoos

game: Moonlight
file: /usr/local/libexec/moonlight-os/moonlight
launch: /usr/local/bin/moonlight-launch moonlight
description: Browse paired hosts and stream games or the desktop with vanilla Moonlight.

game: Eclipse
file: /usr/local/libexec/moonlight-os/frontends/vibemis/usr/bin/vibemis
launch: /usr/local/bin/moonlight-launch vibemis
description: Controller-first streaming client with Vibepollo and Apollo extensions.

game: Artemis
file: /usr/local/libexec/moonlight-os/frontends/artemis
launch: /usr/local/bin/moonlight-launch artemis
description: Moonlight-derived client with an in-stream quick menu and host commands.

game: CocoOS
file: /usr/local/libexec/moonlight-os/cocoos
launch: /usr/local/bin/moonlight-launch cocoos
description: Existing console-style frontend, retained as an optional choice.
PEGASUS_META
chown -R moonlight:moonlight /home/moonlight/.config/pegasus-frontend
# END FRONTEND INTEGRATION

# Confirmed physical console geometry on this Retina panel, before either tty login path.
cat > /etc/profile.d/moonlight-rows.sh <<'ROWS'
case "$(tty 2>/dev/null)" in
  /dev/tty1|/dev/tty2) stty rows 100 2>/dev/null || true ;;
esac
ROWS

# Keep mixer changes explicit: hardware mixer levels vary between machines.
cat > /usr/local/bin/moonlight-audio <<'AUDIOHELP'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-mixer}" in
  mixer) alsamixer; sudo alsactl store ;;
  save) sudo alsactl store ;;
  status) wpctl status ;;
  *) echo "usage: moonlight-audio {mixer|save|status}" >&2; exit 2 ;;
esac
AUDIOHELP
chmod 0755 /usr/local/bin/moonlight-audio
cat > /etc/systemd/system/moonlight-audio-restore.service <<'AUDIORESTORE'
[Unit]
Description=Restore saved EclipseOS hardware mixer levels
After=sound.target
ConditionPathExists=/var/lib/alsa/asound.state

[Service]
Type=oneshot
ExecStart=/usr/sbin/alsactl restore

[Install]
WantedBy=multi-user.target
AUDIORESTORE
systemctl enable moonlight-audio-restore.service

# Minimal WM: fullscreen, without a desktop or compositor.
install -d -m 0755 /home/moonlight/.config/openbox
cat > /home/moonlight/.config/openbox/rc.xml <<'OPENBOX'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <focus><focusNew>yes</focusNew><followMouse>no</followMouse></focus>
  <keyboard />
</openbox_config>
OPENBOX
chown -R moonlight:moonlight /home/moonlight/.config/openbox

# Read local media events independently of X11 keyboard grabs during streaming.
cat > /usr/local/bin/moonlight-media-keys <<'MEDIAKEYS'
#!/usr/bin/env python3
"""Handle only local media keys, including when a streaming client grabs X11 input."""
import fcntl
import glob
import os
import selectors
import shlex
import struct
import subprocess
import time

# Linux input-event codes. No key capture/grab, text logging or remote commands.
ACTIONS = {
    225: 'sudo brightnessctl -d acpi_video0 set +5%',
    224: 'sudo brightnessctl -d acpi_video0 set 5%-',
    230: 'sudo brightnessctl -d spi::kbd_backlight set +10%',
    229: 'sudo brightnessctl -d spi::kbd_backlight set 10%-',
    115: 'wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+',
    114: 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-',
    113: 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle',
}
EVENT = struct.Struct('@llHHi')


def dispatch(kind, code, value):
    # Ignore release; mute toggles once per press, brightness/volume can repeat.
    if kind != 1 or code not in ACTIONS or value not in (1, 2):
        return
    if code == 113 and value == 2:
        return
    try:
        subprocess.run(shlex.split(ACTIONS[code]), timeout=2, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        pass


def main():
    os.environ.setdefault('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid()))
    selector = selectors.DefaultSelector()
    devices = {}
    refresh = 0
    while True:
        if time.monotonic() >= refresh:
            for path in glob.glob('/dev/input/event*'):
                if path in devices:
                    continue
                fd = None
                try:
                    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                    bits = bytearray(96)
                    # EVIOCGBIT(EV_KEY, 96); listen only to media-capable devices.
                    fcntl.ioctl(fd, 0x80000000 | (len(bits) << 16) | (ord('E') << 8) | 0x21, bits)
                    if not any(bits[c // 8] & (1 << (c % 8)) for c in ACTIONS):
                        os.close(fd)
                        continue
                    selector.register(fd, selectors.EVENT_READ, path)
                    devices[path] = fd
                except OSError:
                    if fd is not None:
                        os.close(fd)
            refresh = time.monotonic() + 2
        for key, _ in selector.select(timeout=1):
            try:
                data = os.read(key.fd, EVENT.size * 64)
                if not data:
                    raise OSError('Input device disconnected')
                for offset in range(0, len(data), EVENT.size):
                    _, _, kind, code, value = EVENT.unpack_from(data, offset)
                    dispatch(kind, code, value)
            except (OSError, struct.error):
                selector.unregister(key.fd)
                os.close(key.fd)
                devices.pop(key.data, None)


if __name__ == '__main__':
    main()
MEDIAKEYS
chmod 0755 /usr/local/bin/moonlight-media-keys
cat > /etc/systemd/system/moonlight-media-keys.service <<'MEDIAUNIT'
[Unit]
Description=Moonlight local brightness and volume keys
After=systemd-udevd.service
[Service]
User=moonlight
SupplementaryGroups=input
ExecStart=/usr/local/bin/moonlight-media-keys
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
MEDIAUNIT
systemctl enable moonlight-media-keys.service

cat > /usr/local/bin/moonlight-session <<'SESSION'
#!/usr/bin/env bash
set -u
export QT_QPA_PLATFORM=xcb
export SDL_VIDEODRIVER=x11
export XDG_SESSION_TYPE=x11
# A lightweight, non-compositing WM honors Qt and SDL fullscreen requests.
# Starting before the client avoids its original 1280x600 window on Retina panels.
openbox --sm-disable &
wm_pid=$!
trap 'kill "$wm_pid" 2>/dev/null || true' EXIT
# Wait for the WM selection, not an arbitrary startup delay.
for ((attempt=0; attempt<50; attempt++)); do
  xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id' && break
  kill -0 "$wm_pid" 2>/dev/null || { echo "Openbox failed to start" >&2; exit 1; }
  sleep 0.1
done
xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id' || exit 1
xset s off || true
xset -dpms || true
xset s noblank || true

CONF=/etc/moonlight-os-client.conf
[[ -r "$CONF" ]] && source "$CONF"
CLIENT=${CLIENT:-moonlight}
COCO=/usr/local/libexec/moonlight-os/cocoos
MOON=/usr/local/libexec/moonlight-os/moonlight

case "$CLIENT" in
  moonlight|vibemis|artemis|pegasus|cocoos) ;;
  *) CLIENT=moonlight ;;
esac
# Retain CocoOS's original restart/failure recovery behavior.
if [[ "$CLIENT" == cocoos ]]; then
  failures=0
  while (( failures < 3 )); do
    /usr/local/bin/moonlight-launch cocoos && failures=0 || failures=$((failures + 1))
    sleep 1
  done
  exec /usr/local/bin/moonlight-launch moonlight
fi
if /usr/local/bin/moonlight-launch "$CLIENT"; then
  exit 0
else
  echo "$CLIENT exited with an error; opening vanilla Moonlight." >&2
  /usr/local/bin/moonlight-launch moonlight
fi

SESSION
chmod 0755 /usr/local/bin/moonlight-session

cat > /usr/local/bin/moonlight-os-client <<'CLIENT'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  cocoos|moonlight|vibemis|artemis|pegasus)
    printf 'CLIENT=%s\n' "$1" | sudo tee /etc/moonlight-os-client.conf >/dev/null
    echo "Default client set to $1"
    ;;
  *) echo "usage: moonlight-os-client {cocoos|moonlight|vibemis|artemis|pegasus}" >&2; exit 2 ;;
esac
CLIENT
chmod 0755 /usr/local/bin/moonlight-os-client
printf 'CLIENT=moonlight\n' > /etc/moonlight-os-client.conf

cat > /usr/local/bin/moonlight-os-verify <<'VERIFY'
#!/usr/bin/env bash
set -u
ok=0; bad=0
pass(){ printf '[OK]   %s\n' "$*"; ok=$((ok+1)); }
fail(){ printf '[FAIL] %s\n' "$*"; bad=$((bad+1)); }
check(){ "$@" >/dev/null 2>&1 && pass "$*" || fail "$*"; }

echo "EclipseOS verification"
model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
[[ "$model" == "MacBookPro14,1" ]] && pass "model MacBookPro14,1" || fail "model is ${model:-unknown}"
check modinfo i915
# DRM card numbering is dynamic: find i915 and its render node on the same PCI device.
intel_card=; render_node=
for card in /sys/class/drm/card[0-9]*; do
  [[ $(basename "$card") =~ ^card[0-9]+$ ]] || continue
  driver=$(readlink -f "$card/device/driver" 2>/dev/null || true)
  [[ "$driver" == */i915 ]] || continue
  intel_card=$card
  for render in "$card"/device/drm/renderD*; do
    [[ -e "$render" ]] && render_node="/dev/dri/$(basename "$render")" && break
  done
  break
done
[[ -n "$intel_card" ]] && pass "i915 bound to DRM display device" || fail "i915 DRM binding"
[[ -n "$intel_card" && -e "/dev/dri/$(basename "$intel_card")" ]] && pass "DRM display node" || fail "DRM display node"
[[ -n "$render_node" && -e "$render_node" ]] && pass "DRM render node" || fail "DRM render node"

if command -v vainfo >/dev/null && [[ -n "$render_node" ]]; then
  va_rc=0
  va=$(vainfo --display drm --device "$render_node" 2>&1) || va_rc=$?
  if (( va_rc != 0 )); then
    fail "VA-API initialization (exit $va_rc)"
    printf '%s\n' "$va"
  fi
  for codec in H264 HEVC; do
    if (( va_rc == 0 )) && grep -Eq "VAProfile${codec}[^:]*:[[:space:]]*VAEntrypointVLD" <<<"$va"; then
      pass "VA-API $codec hardware decode profile"
    else
      fail "VA-API $codec hardware decode profile"
      printf '%s\n' "$va"
    fi
  done
else fail "vainfo and Intel render node available"; fi

command -v vulkaninfo >/dev/null 2>&1 && pass "Vulkan diagnostics installed" || fail "vulkaninfo installed"
command -v glxinfo >/dev/null 2>&1 && pass "OpenGL diagnostics installed" || fail "glxinfo installed"
command -v intel_gpu_top >/dev/null 2>&1 && pass "Intel GPU telemetry installed" || fail "intel_gpu_top installed"

rpm -q xorg-x11-drv-libinput >/dev/null 2>&1 && pass "X11 libinput driver installed" || fail "X11 libinput driver"
command -v libinput >/dev/null 2>&1 && pass "libinput diagnostics installed" || fail "libinput tools"
command -v xinput >/dev/null 2>&1 && pass "X11 input diagnostics installed" || fail "xinput"
check modinfo applespi
grep -Eqi 'Apple.*Keyboard|Apple.*SPI.*Keyboard' /proc/bus/input/devices 2>/dev/null && pass "Apple keyboard input device" || fail "Apple keyboard input device"
grep -Eqi 'Apple.*Touchpad|Apple.*SPI.*Touchpad' /proc/bus/input/devices 2>/dev/null && pass "Apple trackpad input device" || fail "Apple trackpad input device"
ls /dev/input/event* >/dev/null 2>&1 && pass "evdev input nodes" || fail "evdev input nodes"

check modinfo brcmfmac
check nmcli general status
check bluetoothctl show
[[ -e /usr/lib64/spa-0.2/bluez5/libspa-codec-bluez5-aac.so ]] && pass "AirPods AAC codec plugin installed" || fail "PipeWire AAC codec"
[[ -e /usr/lib64/spa-0.2/bluez5/libspa-codec-bluez5-sbc.so ]] && pass "Bluetooth SBC codec plugin installed" || fail "PipeWire SBC codec"
check modinfo hid_playstation
command -v evtest >/dev/null 2>&1 && pass "evtest installed" || fail "evtest installed"
[[ -r /home/moonlight/.config/wireplumber/wireplumber.conf.d/52-disable-dualsense-audio.conf ]] && pass "DualSense audio disabled by policy" || fail "DualSense audio policy"
[[ -x /usr/local/libexec/moonlight-os/cocoos ]] && pass "CocoOS binary" || fail "CocoOS binary"
[[ -x /usr/local/libexec/moonlight-os/moonlight ]] && pass "Moonlight binary" || fail "Moonlight binary"
check modinfo snd_hda_codec_cs8409
command -v brightnessctl >/dev/null 2>&1 && pass "brightness control installed" || fail "brightness control"
command -v upower >/dev/null 2>&1 && pass "battery/power diagnostics installed" || fail "upower"
check modinfo xhci_pci
check modinfo thunderbolt
ls /sys/class/nvme/nvme* >/dev/null 2>&1 && pass "internal NVMe controller visible" || fail "NVMe controller"
systemctl is-enabled thermald.service >/dev/null 2>&1 && pass "thermald enabled" || fail "thermald enabled"
[[ -r /sys/class/power_supply/BAT0/status || -r /sys/class/power_supply/BAT1/status ]] && pass "battery sysfs accessible" || fail "battery sysfs"
[[ -d /sys/class/backlight ]] && pass "backlight sysfs accessible" || fail "backlight sysfs"

# If the appliance X session is running, prove real X11 rendering and input access too.
if [[ -S /tmp/.X11-unix/X0 ]]; then
  export DISPLAY=:0
  export XAUTHORITY=/home/moonlight/.Xauthority

  glx=$(glxinfo -B 2>&1 || true)
  if grep -Eqi 'llvmpipe|softpipe|software rasterizer' <<<"$glx"; then
    fail "X11 is using software rendering"
  elif grep -Eqi 'OpenGL renderer string:.*(Intel|Iris)' <<<"$glx"; then
    pass "X11 OpenGL renderer is Intel hardware"
  else
    fail "X11 OpenGL renderer"
  fi

  xr=$(xrandr --query 2>&1 || true)
  grep -q ' connected' <<<"$xr" && pass "X11 display connector visible" || fail "X11 display connector"

  xi=$(xinput list 2>&1 || true)
  grep -Eqi 'keyboard|Apple.*Keyboard' <<<"$xi" && pass "X11 keyboard visible" || fail "X11 keyboard"
  grep -Eqi 'touchpad|Apple.*Touchpad|pointer' <<<"$xi" && pass "X11 pointing device visible" || fail "X11 pointing device"
else
  echo "[INFO] X11 runtime checks skipped because :0 is not currently running"
fi

printf '\nMemory: '; free -h | awk '/Mem:/ {print $3 " used / " $2 " total"}'
printf 'Checks: %d OK, %d failed\n' "$ok" "$bad"
(( bad == 0 ))
VERIFY
chmod 0755 /usr/local/bin/moonlight-os-verify

cat > /usr/local/sbin/moonlight-os-grow-root <<'GROW'
#!/usr/bin/env bash
set -euo pipefail
root_src=$(findmnt -n -o SOURCE /)
root_real=$(readlink -f "$root_src")
part=$(basename "$root_real")
sysnode=$(readlink -f "/sys/class/block/$part")
[[ -b "$root_real" && -r "$sysnode/partition" ]]
disk=$(basename "$(dirname "$sysnode")")
num=$(<"$sysnode/partition")
[[ -b "/dev/$disk" && "$num" =~ ^[1-9][0-9]*$ ]]
printf 'Root growth target: /dev/%s partition %s\n' "$disk" "$num"

rc=0
out=$(growpart "/dev/$disk" "$num" 2>&1) || rc=$?
printf '%s\n' "$out"

if (( rc != 0 )) && ! grep -q 'NOCHANGE:' <<<"$out"; then
  echo "Root partition expansion failed; will retry on next boot." >&2
  exit "$rc"
fi

udevadm settle
xfs_growfs /
touch /var/lib/moonlight-os-root-grown
GROW
chmod 0755 /usr/local/sbin/moonlight-os-grow-root
cat > /etc/systemd/system/moonlight-os-grow-root.service <<'GROWSVC'
[Unit]
Description=Expand EclipseOS root filesystem to fill USB
ConditionPathExists=!/var/lib/moonlight-os-root-grown
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/moonlight-os-grow-root
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
GROWSVC
systemctl enable moonlight-os-grow-root.service

cat > /usr/local/sbin/moonlight-os-boot-marker <<'BOOTMARK'
#!/usr/bin/env bash
set -eu
marker="MOONLIGHT_OS_BOOT_OK"
printf '%s\n' "$marker" > /run/moonlight-os-boot-ok
if [[ -w /dev/ttyS0 ]]; then
  printf '%s\n' "$marker" > /dev/ttyS0
fi
BOOTMARK
chmod 0755 /usr/local/sbin/moonlight-os-boot-marker

cat > /etc/systemd/system/moonlight-os-boot-marker.service <<'BOOTMARKSVC'
[Unit]
Description=EclipseOS boot verification marker
Requires=moonlight-os-grow-root.service
After=local-fs.target NetworkManager.service moonlight-os-grow-root.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/moonlight-os-boot-marker
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
BOOTMARKSVC
systemctl enable moonlight-os-boot-marker.service

install -d /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'GETTY'
[Unit]
After=plymouth-quit.service

[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin moonlight --noclear %I $TERM
Type=idle
GETTY
install -d /etc/systemd/system/getty@tty2.service.d
cp /etc/systemd/system/getty@tty1.service.d/autologin.conf /etc/systemd/system/getty@tty2.service.d/autologin.conf

cat > /etc/profile.d/moonlight-console-colors.sh <<'COLORS'
# EclipseOS diagnostic console theme: black background, red text.
# Apply only to Linux virtual consoles so X11/Moonlight rendering is untouched.
case "$(tty 2>/dev/null || true)" in
  /dev/tty[1-9]|/dev/tty[1-9][0-9])
    if command -v setterm >/dev/null 2>&1; then
      setterm --foreground red --background black --store 2>/dev/null || \
      setterm --foreground red --background black 2>/dev/null || true
      clear
    fi
    export PS1='\[\e[1;31m\]\u@moonlight-os\[\e[0;31m\]:\w\$ \[\e[0m\]'
    ;;
esac
COLORS
chmod 0644 /etc/profile.d/moonlight-console-colors.sh

cat > /home/moonlight/.bash_profile <<'PROFILE'
[[ -r /etc/profile.d/00-moonlight-red-terminal.sh ]] && source /etc/profile.d/00-moonlight-red-terminal.sh
if [[ -z "${DISPLAY:-}" && "$(tty 2>/dev/null)" == "/dev/tty1" ]]; then
  sudo timeout 3 plymouth quit 2>/dev/null || true
  if ! nm-online -q --timeout=8; then
    echo "No saved network connection found."
    moonlight-wifi || true
  fi
  moonlight-frontend-select || true
  exec startx /usr/local/bin/moonlight-session -- :0 vt1 -keeptty -nolisten tcp
elif [[ -z "${DISPLAY:-}" && "$(tty 2>/dev/null)" == "/dev/tty2" ]]; then
  moonlight-settings || true
fi
PROFILE
chown moonlight:moonlight /home/moonlight/.bash_profile

echo 'moonlight ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/moonlight-os
chmod 0440 /etc/sudoers.d/moonlight-os

# v0.1 is intentionally a development/debug image. Keep Git, compiler,
# kernel headers, DKMS, pinned source trees, and diagnostic tooling on the USB.
rm -rf /root/.cache /var/cache/dnf/*
dnf clean all || true

cat >> /etc/dnf/dnf.conf <<'DNF'
exclude=kernel kernel-core kernel-modules kernel-modules-extra
DNF

systemctl set-default multi-user.target
%end
