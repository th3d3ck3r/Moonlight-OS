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
VIBEMIS_PATCH_SHA256=4554e013ffd28d3ac259e61d3a08497b73ea82c878b3b77006a83c75c3678ee3
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
M2Y2NDVkLi5hZjBkODRhIDEwMDY0NAotLS0gYS9hcHAvZ3VpL0FwcFZpZXcucW1sCisrKyBiL2Fw
cC9ndWkvQXBwVmlldy5xbWwKQEAgLTUsMTIgKzUsMTQgQEAgaW1wb3J0IFF0UXVpY2suTGF5b3V0
cyAxLjMKIAogaW1wb3J0IFRoZW1lIDEuMAogaW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitp
bXBvcnQgQ3JpbXNvblN0YXR1cyAxLjAKIGltcG9ydCBBcHBNb2RlbCAxLjAKIGltcG9ydCBBcHBQ
cm9maWxlTWFuYWdlciAxLjAKIGltcG9ydCBDb21wdXRlck1hbmFnZXIgMS4wCiBpbXBvcnQgU2Rs
R2FtZXBhZEtleU5hdmlnYXRpb24gMS4wCiAKIENlbnRlcmVkR3JpZFZpZXcgeworICAgIHByb3Bl
cnR5IHZhciBjcmltc29uSG9zdDogKHt9KQogICAgIHByb3BlcnR5IGludCBjb21wdXRlckluZGV4
CiAgICAgcHJvcGVydHkgQXBwTW9kZWwgYXBwTW9kZWwgOiBjcmVhdGVNb2RlbCgpCiAgICAgcHJv
cGVydHkgYm9vbCBhY3RpdmF0ZWQKQEAgLTMxLDE3ICszMywyNiBAQCBDZW50ZXJlZEdyaWRWaWV3
IHsKICAgICAvLyB0b29sYmFyIGlzIGNvbGxhcHNlZCBvbiBhbGwgcmVkZXNpZ24gc2NyZWVucyAo
bWFpbi5xbWwpLiBDaHJvbWUgYmxvY2sgaXMgZGVmaW5lZCBiZWxvdy4KICAgICAvLyBHYXAgYmV0
d2VlbiB0aGUgIkFwcHMiIHRpdGxlIHJvdyBhbmQgdGhlIHRpbGUgcm93IGlzIDMwIChIVE1MIGJv
ZHkgZmxleCBnYXApLCBhbmQgdGhlCiAgICAgLy8gYm90dG9tIGNsZWFyYW5jZSBtYXRjaGVzIHRo
ZSBib2R5J3Mgb3duIGJvdHRvbSBwYWRkaW5nIChzY3JlZW5QYWRZID0gNTIpLgotICAgIHRvcE1h
cmdpbjogYXBwQ2hyb21lSGVhZGVyLmhlaWdodCArIDMwCisgICAgdG9wTWFyZ2luOiBhcHBDaHJv
bWVIZWFkZXIuaGVpZ2h0ICsgMTYKICAgICAvLyBTYW1lIHBhcnRpYWwtcm93IG1pbk1hcmdpbiBm
aXggYXMgUGNWaWV3IOKAlCBhbGlnbiB3aXRoIHRoZSA1NnB4IHNjcmVlbiBwYWRkaW5nLgorICAg
IHJlYWRvbmx5IHByb3BlcnR5IGJvb2wgZ2xhc3NXaWRlOiB3aWR0aCA+PSAxMjQwICYmIGhlaWdo
dCA+PSA1NDAKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgcmFpbFNwYWNlOiB3aWR0aCA+PSA5
MDAgPyA4NCA6IDAKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgbG9jYWxTcGFjZTogZ2xhc3NX
aWRlID8gTWF0aC5yb3VuZCgyNTIqVmJUb2tlbnMudGV4dFNjYWxlKSA6IDAKKyAgICByZWFkb25s
eSBwcm9wZXJ0eSBpbnQgaG9zdFNwYWNlOiBnbGFzc1dpZGUgJiYgd2lkdGggPj0gMTU4MCA/IE1h
dGgucm91bmQoMjYwKlZiVG9rZW5zLnRleHRTY2FsZSkgOiAwCiAgICAgbWluTWFyZ2luOiBWYlRv
a2Vucy5zY3JlZW5QYWRYCisgICAgYXZhaWxhYmxlV2lkdGg6IHdpZHRoIC0gcmFpbFNwYWNlIC0g
bG9jYWxTcGFjZSAtIGhvc3RTcGFjZSAtIDIqbWluTWFyZ2luCisgICAgb25SYWlsU3BhY2VDaGFu
Z2VkOiB1cGRhdGVNYXJnaW5zKCkKKyAgICBvbkxvY2FsU3BhY2VDaGFuZ2VkOiB1cGRhdGVNYXJn
aW5zKCkKKyAgICBvbkhvc3RTcGFjZUNoYW5nZWQ6IHVwZGF0ZU1hcmdpbnMoKQorICAgIGZ1bmN0
aW9uIHVwZGF0ZU1hcmdpbnMoKSB7IGxlZnRNYXJnaW49aG9yaXpvbnRhbE1hcmdpbityYWlsU3Bh
Y2UraG9zdFNwYWNlO3JpZ2h0TWFyZ2luPWhvcml6b250YWxNYXJnaW4rbG9jYWxTcGFjZSB9CiAg
ICAgYm90dG9tTWFyZ2luOiAoYXBwSGludEJhci52aXNpYmxlID8gYXBwSGludEJhci5oZWlnaHQg
OiAwKSArIFZiVG9rZW5zLnNjcmVlblBhZFkKICAgICAvLyBSZWRlc2lnbiAxYjogMzIweDQzMCBh
cHAgdGlsZXMgKEhUTUwgIzFiKSwgZ2FwIDM2IGhvcml6b250YWw7IGNlbGxIZWlnaHQgYWRkcyBy
b29tIGZvciB0aGUKICAgICAvLyAxNnB4LWdhcCArICLikrYgTGF1bmNoIiBoaW50IHJvdyAob3Ig
YXBwIG5hbWUpIGJlbG93IHRoZSBmb2N1c2VkIHRpbGUuCiAgICAgLy8gQ2FwIHRoZSByb3cgaGVp
Z2h0IHRvIHRoZSBhdmFpbGFibGUgdmlld3BvcnQgc28gdGlsZXMgbmV2ZXIgY2xpcCB0aGVpciBi
b3R0b20gYm9yZGVyIG9uCiAgICAgLy8gc2hvcnRlciByZW5kZXIgc3VyZmFjZXMgKGUuZy4gMTI4
MHg4MDAgaW4gR2FtZSBNb2RlKSDigJQgdGhlIGFic29sdXRlIDQ3NCB3YXMgdHVuZWQgZm9yCiAg
ICAgLy8gMTkyMHgxMjAwLiBBdCAxMjAwcCB0aGlzIHN0YXlzIDQ3NDsgb24gc2hvcnRlciBzdXJm
YWNlcyB0aWxlcyBzaHJpbmsgdG8gZml0LgotICAgIGNlbGxXaWR0aDogMzU2Ci0gICAgY2VsbEhl
aWdodDogTWF0aC5tYXgoMzAwLCBNYXRoLm1pbig0NzQsIGhlaWdodCAtIHRvcE1hcmdpbiAtIGJv
dHRvbU1hcmdpbikpCisgICAgY2VsbFdpZHRoOiBNYXRoLm1heCgyMjAsTWF0aC5taW4oMzAwLGF2
YWlsYWJsZVdpZHRoIC8gTWF0aC5tYXgoMSxNYXRoLmZsb29yKGF2YWlsYWJsZVdpZHRoLzI2MCkp
KSkKKyAgICBjZWxsSGVpZ2h0OiBNYXRoLm1heCgyNjAsIE1hdGgubWluKDM4MCwgaGVpZ2h0IC0g
dG9wTWFyZ2luIC0gYm90dG9tTWFyZ2luKSkKIAogICAgIC8vIOKTjiBxdWl0cyB0aGUgaW4tcHJv
Z3Jlc3Mgc2Vzc2lvbiBmcm9tCiAgICAgLy8gYW55d2hlcmUgaW4gdGhlIGFwcCBncmlkIOKAlCB0
aGUgZ2FtZXBhZCBlcXVpdmFsZW50IG9mIHRoZSBzdG9wIGJ1dHRvbiBvbiB0aGUKQEAgLTExMCw3
ICsxMjEsNyBAQCBDZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAgdmlzaWJsZTogdHJ1ZQogICAg
ICAgICBoZWlnaHQ6IGFwcHNUaXRsZVJvdy55ICsgYXBwc1RpdGxlUm93LmhlaWdodAogCi0gICAg
ICAgIFJlY3RhbmdsZSB7IGFuY2hvcnMuZmlsbDogcGFyZW50OyBjb2xvcjogVmJUb2tlbnMuYmdX
aW5kb3cgfQorICAgICAgICBSZWN0YW5nbGUgeyBhbmNob3JzLmZpbGw6IHBhcmVudDsgY29sb3I6
ICJ0cmFuc3BhcmVudCIgfQogCiAgICAgICAgIC8vIFJvdyAxIChiYWNrICsgaG9zdCBuYW1lL3N0
YXR1cyArIHJlZnJlc2gvc2V0dGluZ3MpIGFuZCBpdHMgZGl2aWRlciBub3cgbGl2ZSBpbiB0aGUK
ICAgICAgICAgLy8gYWx3YXlzLXByZXNlbnQgZ2xvYmFsIHRvb2xiYXIgKG1haW4ucW1sKSDigJQg
dGhlIHRvb2xiYXIgcmVhZHMgaG9zdE9ubGluZS9ob3N0VHlwZS8KQEAgLTEyMSwxMyArMTMyLDEz
IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgICAgICBSb3cgewogICAgICAgICAgICAgaWQ6IGFw
cHNUaXRsZVJvdwogICAgICAgICAgICAgYW5jaG9ycy50b3A6IHBhcmVudC50b3AKLSAgICAgICAg
ICAgIGFuY2hvcnMudG9wTWFyZ2luOiAzNAorICAgICAgICAgICAgYW5jaG9ycy50b3BNYXJnaW46
IDE2CiAgICAgICAgICAgICBhbmNob3JzLmxlZnQ6IHBhcmVudC5sZWZ0Ci0gICAgICAgICAgICBh
bmNob3JzLmxlZnRNYXJnaW46IFZiVG9rZW5zLnNjcmVlblBhZFgKKyAgICAgICAgICAgIGFuY2hv
cnMubGVmdE1hcmdpbjogVmJUb2tlbnMuc2NyZWVuUGFkWCthcHBHcmlkLnJhaWxTcGFjZSthcHBH
cmlkLmhvc3RTcGFjZQogICAgICAgICAgICAgc3BhY2luZzogMTQKICAgICAgICAgICAgIFRleHQg
ewogICAgICAgICAgICAgICAgIGlkOiBhcHBzVGl0bGUKLSAgICAgICAgICAgICAgICB0ZXh0OiBx
c1RyKCJBcHBzIikKKyAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJMaWJyYXJ5IikKICAgICAg
ICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udERpc3BsYXkKICAgICAgICAgICAg
ICAgICBmb250LndlaWdodDogRm9udC5Cb2xkCiAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNp
emU6IFZiVG9rZW5zLnNpemVTY3JlZW5UaXRsZQpAQCAtMTQzLDYgKzE1NCwzMSBAQCBDZW50ZXJl
ZEdyaWRWaWV3IHsKICAgICAgICAgfQogICAgIH0KIAorCisgICAgLy8gQ3JpbXNvbiBHbGFzcyBk
YXNoYm9hcmQgY2hyb21lIGxpdmVzIGluIHRoZSB2aWV3cG9ydCwgb3V0c2lkZSBjb250ZW50SXRl
bS4KKyAgICBDcmltc29uR2xhc3NSYWlsIHsKKyAgICAgICAgcGFyZW50OmFwcEdyaWQKKyAgICAg
ICAgejoxMTt4OjEyO3k6MTY7d2lkdGg6NjQ7aGVpZ2h0Ok1hdGgubWF4KDI4MCxhcHBHcmlkLmhl
aWdodC0zMi0oYXBwSGludEJhci52aXNpYmxlP2FwcEhpbnRCYXIuaGVpZ2h0OjApKQorICAgICAg
ICB2aXNpYmxlOmFwcEdyaWQucmFpbFNwYWNlPjA7aW5MaWJyYXJ5OnRydWUKKyAgICAgICAgb25I
b21lUmVxdWVzdGVkOiB7IGlmKHN0YWNrVmlldy5kZXB0aD4xKSBzdGFja1ZpZXcucG9wKG51bGwp
O2Vsc2UgYXBwR3JpZC5mb3JjZUFjdGl2ZUZvY3VzKCkgfQorICAgICAgICBvblNldHRpbmdzUmVx
dWVzdGVkOiBzZXR0aW5nc0J1dHRvbi5jbGlja2VkKCkKKyAgICAgICAgb25Db250cm9sc1JlcXVl
c3RlZDogZWNsaXBzZUNlbnRlckJ1dHRvbi5jbGlja2VkKCkKKyAgICB9CisgICAgQ3JpbXNvbkxv
Y2FsUGFuZWwgeworICAgICAgICBwYXJlbnQ6YXBwR3JpZAorICAgICAgICB6OjExO2FuY2hvcnMu
cmlnaHQ6cGFyZW50LnJpZ2h0O2FuY2hvcnMucmlnaHRNYXJnaW46MTY7eToxNjt3aWR0aDpNYXRo
Lm1heCgwLGFwcEdyaWQubG9jYWxTcGFjZS0yOCkKKyAgICAgICAgaGVpZ2h0Ok1hdGgubWF4KDI0
MCxhcHBHcmlkLmhlaWdodC0zMi0oYXBwSGludEJhci52aXNpYmxlP2FwcEhpbnRCYXIuaGVpZ2h0
OjApKTt2aXNpYmxlOmFwcEdyaWQubG9jYWxTcGFjZT4wCisgICAgICAgIGFjdGl2ZTp2aXNpYmxl
ICYmIGFwcEdyaWQuU3RhY2tWaWV3LnN0YXR1cz09PVN0YWNrVmlldy5BY3RpdmUKKyAgICAgICAg
b25Db250cm9sc1JlcXVlc3RlZDogZWNsaXBzZUNlbnRlckJ1dHRvbi5jbGlja2VkKCkKKyAgICB9
CisgICAgQ3JpbXNvbkhvc3RQYW5lbCB7CisgICAgICAgIHBhcmVudDphcHBHcmlkCisgICAgICAg
IHo6MTE7eDphcHBHcmlkLnJhaWxTcGFjZSsxMjt5OjE2O3dpZHRoOk1hdGgubWF4KDAsYXBwR3Jp
ZC5ob3N0U3BhY2UtMjQpCisgICAgICAgIGhlaWdodDpNYXRoLm1heCgyNDAsYXBwR3JpZC5oZWln
aHQtMzItKGFwcEhpbnRCYXIudmlzaWJsZT9hcHBIaW50QmFyLmhlaWdodDowKSk7dmlzaWJsZTph
cHBHcmlkLmhvc3RTcGFjZT4wCisgICAgICAgIGhvc3ROYW1lOmFwcEdyaWQub2JqZWN0TmFtZTto
b3N0VHlwZTphcHBHcmlkLmhvc3RUeXBlO3RyYW5zcG9ydDphcHBHcmlkLmhvc3RUcmFuc3BvcnQ7
b25saW5lOmFwcEdyaWQuaG9zdE9ubGluZTtob3N0OmFwcEdyaWQuY3JpbXNvbkhvc3QKKyAgICAg
ICAgb25Ib3N0UmVxdWVzdGVkOiB7IENyaW1zb25TdGF0dXMuc2VsZWN0SG9zdChhcHBHcmlkLmNy
aW1zb25Ib3N0LmlkfHwiIixhcHBHcmlkLmNyaW1zb25Ib3N0LnVybHx8IiIpO2NyaW1zb25QYW5l
bC5raW5kPSJob3N0Ijtjcmltc29uUGFuZWwub3BlbigpIH0KKyAgICB9CisKICAgICAvLyBQZXJz
aXN0ZW50IGdhbWVwYWQgaGludCBiYXIsIGZpeGVkIGF0IHRoZSBib3R0b20uIEdyaWQgYm90dG9t
TWFyZ2luIGNsZWFycyBpdC4KICAgICBWYkhpbnRCYXIgewogICAgICAgICBpZDogYXBwSGludEJh
cgpAQCAtMjI2LDcgKzI2Miw4IEBAIENlbnRlcmVkR3JpZFZpZXcgewogCiAgICAgZnVuY3Rpb24g
Y3JlYXRlTW9kZWwoKQogICAgIHsKLSAgICAgICAgdmFyIG1vZGVsID0gUXQuY3JlYXRlUW1sT2Jq
ZWN0KCdpbXBvcnQgQXBwTW9kZWwgMS4wOyBBcHBNb2RlbCB7fScsIHBhcmVudCwgJycpCisgICAg
ICAgIHZhciBtb2RlbCA9IFF0LmNyZWF0ZVFtbE9iamVjdCgnaW1wb3J0IENyaW1zb25TdGF0dXMg
MS4wCitpbXBvcnQgQXBwTW9kZWwgMS4wOyBBcHBNb2RlbCB7fScsIGFwcEdyaWQsICcnKQogICAg
ICAgICBtb2RlbC5pbml0aWFsaXplKENvbXB1dGVyTWFuYWdlciwgY29tcHV0ZXJJbmRleCwgc2hv
d0hpZGRlbkdhbWVzKQogICAgICAgICByZXR1cm4gbW9kZWwKICAgICB9CkBAIC0yNjUsMzAgKzMw
MiwxOCBAQCBDZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAgICAgIGZvY3VzZWQ6IGFwcERlbGVn
YXRlLmhpZ2hsaWdodGVkCiAKICAgICAgICAgICAgIEltYWdlIHsKLSAgICAgICAgICAgICAgICBw
cm9wZXJ0eSBib29sIGlzUGxhY2Vob2xkZXI6IGZhbHNlCisgICAgICAgICAgICAgICAgcmVhZG9u
bHkgcHJvcGVydHkgYm9vbCBpc1BsYWNlaG9sZGVyOiBzb3VyY2UudG9TdHJpbmcoKS5sZW5ndGgg
PT09IDAgfHwgc3RhdHVzID09PSBJbWFnZS5FcnJvciB8fAorICAgICAgICAgICAgICAgICAgICAo
IW1vZGVsLmlzQXBwQ29sbGVjdG9yR2FtZSAmJgorICAgICAgICAgICAgICAgICAgICAgKChzb3Vy
Y2VTaXplLndpZHRoID09PSAxMzAgJiYgc291cmNlU2l6ZS5oZWlnaHQgPT09IDE4MCkgfHwKKyAg
ICAgICAgICAgICAgICAgICAgICAoc291cmNlU2l6ZS53aWR0aCA9PT0gNjI4ICYmIHNvdXJjZVNp
emUuaGVpZ2h0ID09PSA4ODgpIHx8CisgICAgICAgICAgICAgICAgICAgICAgKHNvdXJjZVNpemUu
d2lkdGggPT09IDIwMCAmJiBzb3VyY2VTaXplLmhlaWdodCA9PT0gMjY2KSkpCiAKICAgICAgICAg
ICAgICAgICBpZDogYXBwSWNvbgogICAgICAgICAgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50
CiAgICAgICAgICAgICAgICAgYW5jaG9ycy5tYXJnaW5zOiA1CiAgICAgICAgICAgICAgICAgc291
cmNlOiBtb2RlbC5ib3hhcnQKLQotICAgICAgICAgICAgICAgIG9uU291cmNlU2l6ZUNoYW5nZWQ6
IHsKLSAgICAgICAgICAgICAgICAgICAgLy8gTmVhcmx5IGFsbCBvZiBOdmlkaWEncyBvZmZpY2lh
bCBib3ggYXJ0IGRvZXMgbm90IG1hdGNoIHRoZSBkaW1lbnNpb25zIG9mIHBsYWNlaG9sZGVyCi0g
ICAgICAgICAgICAgICAgICAgIC8vIGltYWdlcywgaG93ZXZlciB0aGUgb25lIGtub3duIGV4Y2Vw
dGlvbiBpcyBPdmVyY29va2VkLiBUaGVyZWZvcmUsIHdlIG9ubHkgZXhlY3V0ZQotICAgICAgICAg
ICAgICAgICAgICAvLyB0aGUgaW1hZ2Ugc2l6ZSBjaGVja3MgaWYgdGhpcyBpcyBub3QgYW4gYXBw
IGNvbGxlY3RvciBnYW1lLiBXZSBrbm93IHRoZSBvZmZpY2lhbGx5Ci0gICAgICAgICAgICAgICAg
ICAgIC8vIHN1cHBvcnRlZCBnYW1lcyBhbGwgaGF2ZSBib3ggYXJ0LCBzbyB0aGlzIGNoZWNrIGlz
IG5vdCByZXF1aXJlZC4KLSAgICAgICAgICAgICAgICAgICAgaWYgKCFtb2RlbC5pc0FwcENvbGxl
Y3RvckdhbWUgJiYKLSAgICAgICAgICAgICAgICAgICAgICAgICgoc291cmNlU2l6ZS53aWR0aCA9
PT0gMTMwICYmIHNvdXJjZVNpemUuaGVpZ2h0ID09PSAxODApIHx8IC8vIEdGRSAyLjAgcGxhY2Vo
b2xkZXIgaW1hZ2UKLSAgICAgICAgICAgICAgICAgICAgICAgICAoc291cmNlU2l6ZS53aWR0aCA9
PT0gNjI4ICYmIHNvdXJjZVNpemUuaGVpZ2h0ID09PSA4ODgpIHx8IC8vIEdGRSAzLjAgcGxhY2Vo
b2xkZXIgaW1hZ2UKLSAgICAgICAgICAgICAgICAgICAgICAgICAoc291cmNlU2l6ZS53aWR0aCA9
PT0gMjAwICYmIHNvdXJjZVNpemUuaGVpZ2h0ID09PSAyNjYpKSkgIC8vIE91ciBub19hcHBfaW1h
Z2UucG5nCi0gICAgICAgICAgICAgICAgICAgIHsKLSAgICAgICAgICAgICAgICAgICAgICAgIGlz
UGxhY2Vob2xkZXIgPSB0cnVlCi0gICAgICAgICAgICAgICAgICAgIH0KLSAgICAgICAgICAgICAg
ICAgICAgZWxzZQotICAgICAgICAgICAgICAgICAgICB7Ci0gICAgICAgICAgICAgICAgICAgICAg
ICBpc1BsYWNlaG9sZGVyID0gZmFsc2UKLSAgICAgICAgICAgICAgICAgICAgfQotICAgICAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgICAgICB2aXNpYmxlOiAhaXNQbGFjZWhvbGRlcgorICAgICAg
ICAgICAgICAgIGZpbGxNb2RlOiBJbWFnZS5QcmVzZXJ2ZUFzcGVjdENyb3AKIAogICAgICAgICAg
ICAgICAgIC8vIERpc3BsYXkgYSB0b29sdGlwIHdpdGggdGhlIGZ1bGwgbmFtZSBpZiBpdCdzIHRy
dW5jYXRlZAogICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogbW9kZWwubmFtZQpAQCAtMjk3
LDYgKzMyMiwxNSBAQCBDZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAgICAgICAgICBUb29sVGlw
LnZpc2libGU6IChhcHBEZWxlZ2F0ZS5ob3ZlcmVkIHx8IGFwcERlbGVnYXRlLmhpZ2hsaWdodGVk
KSAmJiAoIWFwcE5hbWVUZXh0IHx8IGFwcE5hbWVUZXh0LnRydW5jYXRlZCkKICAgICAgICAgICAg
IH0KIAorICAgICAgICAgICAgSW1hZ2UgeworICAgICAgICAgICAgICAgIHZpc2libGU6IGFwcElj
b24uaXNQbGFjZWhvbGRlciAmJiAhbW9kZWwucnVubmluZworICAgICAgICAgICAgICAgIGFuY2hv
cnMuaG9yaXpvbnRhbENlbnRlcjogcGFyZW50Lmhvcml6b250YWxDZW50ZXIKKyAgICAgICAgICAg
ICAgICB5OiBwYXJlbnQuaGVpZ2h0ICogMC4yMgorICAgICAgICAgICAgICAgIHdpZHRoOiBNYXRo
Lm1pbig2NCwgcGFyZW50LndpZHRoICogMC4zKTsgaGVpZ2h0OiB3aWR0aAorICAgICAgICAgICAg
ICAgIHNvdXJjZTogInFyYzovcmVzL2VjbGlwc2UtaWNvbi5zdmciCisgICAgICAgICAgICAgICAg
b3BhY2l0eTogMC44NQorICAgICAgICAgICAgfQorCiAgICAgICAgICAgICBMb2FkZXIgewogICAg
ICAgICAgICAgICAgIGFjdGl2ZTogbW9kZWwucnVubmluZwogICAgICAgICAgICAgICAgIGFzeW5j
aHJvbm91czogdHJ1ZQpAQCAtMzY1LDcgKzM5OSw3IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAg
ICAgICAgICAgICAgIC8vIGluIHRoZSB0aW1lIGluIHdoaWNoIHRoZSB0ZXh0IGxvYWRzIGZvciBl
YWNoIGdhbWUuCiAKICAgICAgICAgICAgICAgICB3aWR0aDogYXBwSWNvbi53aWR0aAotICAgICAg
ICAgICAgICAgIGhlaWdodDogbW9kZWwucnVubmluZyA/IDE3NSA6IGFwcEljb24uaGVpZ2h0Cisg
ICAgICAgICAgICAgICAgaGVpZ2h0OiBtb2RlbC5ydW5uaW5nID8gTWF0aC5taW4oMTQwLCBhcHBJ
Y29uLmhlaWdodCAqIDAuNDUpIDogYXBwSWNvbi5oZWlnaHQgKiAwLjU1CiAKICAgICAgICAgICAg
ICAgICBhbmNob3JzLmxlZnQ6IGFwcEljb24ubGVmdAogICAgICAgICAgICAgICAgIGFuY2hvcnMu
cmlnaHQ6IGFwcEljb24ucmlnaHQKQEAgLTM3NCw3ICs0MDgsMTAgQEAgQ2VudGVyZWRHcmlkVmll
dyB7CiAgICAgICAgICAgICAgICAgc291cmNlQ29tcG9uZW50OiBMYWJlbCB7CiAgICAgICAgICAg
ICAgICAgICAgIGlkOiBhcHBOYW1lVGV4dAogICAgICAgICAgICAgICAgICAgICB0ZXh0OiBtb2Rl
bC5uYW1lCi0gICAgICAgICAgICAgICAgICAgIGZvbnQucG9pbnRTaXplOiAyMgorICAgICAgICAg
ICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udERpc3BsYXkKKyAgICAgICAgICAg
ICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVIZWFkaW5nCisgICAgICAgICAg
ICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy50ZXh0CisgICAgICAgICAgICAgICAgICAgIHRleHRG
b3JtYXQ6IFRleHQuUGxhaW5UZXh0CiAgICAgICAgICAgICAgICAgICAgIGxlZnRQYWRkaW5nOiAy
MAogICAgICAgICAgICAgICAgICAgICByaWdodFBhZGRpbmc6IDIwCiAgICAgICAgICAgICAgICAg
ICAgIHZlcnRpY2FsQWxpZ25tZW50OiBUZXh0LkFsaWduVkNlbnRlcgpkaWZmIC0tZ2l0IGEvYXBw
L2d1aS9BdXRvUmVzaXppbmdDb21ib0JveC5xbWwgYi9hcHAvZ3VpL0F1dG9SZXNpemluZ0NvbWJv
Qm94LnFtbAppbmRleCA1M2FmY2FmLi5mMTIzOTMyIDEwMDY0NAotLS0gYS9hcHAvZ3VpL0F1dG9S
ZXNpemluZ0NvbWJvQm94LnFtbAorKysgYi9hcHAvZ3VpL0F1dG9SZXNpemluZ0NvbWJvQm94LnFt
bApAQCAtMSw1ICsxLDYgQEAKIGltcG9ydCBRdFF1aWNrIDIuOQogaW1wb3J0IFF0UXVpY2suQ29u
dHJvbHMgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKIAogaW1wb3J0IFNkbEdhbWVw
YWRLZXlOYXZpZ2F0aW9uIDEuMAogaW1wb3J0IFN5c3RlbVByb3BlcnRpZXMgMS4wCkBAIC05Miw3
ICs5Myw3IEBAIENvbWJvQm94IHsKICAgICAgICAgLy8gT3ZlcnJpZGUgdGhlIHBvcHVwIGNvbG9y
IHRvIGltcHJvdmUgY29udHJhc3Qgd2l0aCB0aGUgb3ZlcnJpZGRlbgogICAgICAgICAvLyBNYXRl
cmlhbCAyIGJhY2tncm91bmQgY29sb3Igc2V0IGluIG1haW4ucW1sLgogICAgICAgICBpZiAoU3lz
dGVtUHJvcGVydGllcy51c2VzTWF0ZXJpYWwzVGhlbWUpIHsKLSAgICAgICAgICAgIHBvcHVwLmJh
Y2tncm91bmQuY29sb3IgPSAiIzQyNDI0MiIKKyAgICAgICAgICAgIHBvcHVwLmJhY2tncm91bmQu
Y29sb3IgPSBRdC5iaW5kaW5nKGZ1bmN0aW9uKCkgeyByZXR1cm4gVmJUb2tlbnMuYmdFbGV2MiB9
KQogICAgICAgICB9CiAgICAgfQogCmRpZmYgLS1naXQgYS9hcHAvZ3VpL0NyaW1zb25CYWNrZ3Jv
dW5kUGlja2VyLnFtbCBiL2FwcC9ndWkvQ3JpbXNvbkJhY2tncm91bmRQaWNrZXIucW1sCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmFlMTVlMDgKLS0tIC9kZXYvbnVsbAorKysg
Yi9hcHAvZ3VpL0NyaW1zb25CYWNrZ3JvdW5kUGlja2VyLnFtbApAQCAtMCwwICsxLDMwIEBACitp
bXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0
UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IEVj
bGlwc2VQcm9maWxlcyAxLjAKK05hdmlnYWJsZURpYWxvZyB7CisgICAgaWQ6cGlja2VyCisgICAg
dGl0bGU6cXNUcigiQ3JpbXNvbiBHbGFzcyBiYWNrZ3JvdW5kIikKKyAgICB3aWR0aDpNYXRoLm1p
big2NDAscGFyZW50P3BhcmVudC53aWR0aC0zMjo2NDApO2hlaWdodDpNYXRoLm1pbig2MDAscGFy
ZW50P3BhcmVudC5oZWlnaHQtMzI6NjAwKQorICAgIHN0YW5kYXJkQnV0dG9uczpEaWFsb2cuQ2xv
c2UKKyAgICBwcm9wZXJ0eSB1cmwgZm9sZGVyOkVjbGlwc2VQcm9maWxlcy5iYWNrZ3JvdW5kRm9s
ZGVyKCkKKyAgICBwcm9wZXJ0eSB2YXIgZmlsZXM6W10KKyAgICBwcm9wZXJ0eSBzdHJpbmcgZXJy
b3I6IiIKKyAgICBvbk9wZW5lZDoge2ZpbGVzPUVjbGlwc2VQcm9maWxlcy5iYWNrZ3JvdW5kRmls
ZXMoZm9sZGVyKTtlcnJvcj0iIn0KKyAgICBjb250ZW50SXRlbTpDb2x1bW5MYXlvdXQgeworICAg
ICAgICBzcGFjaW5nOjEyCisgICAgICAgIExhYmVsIHsgdGV4dDpxc1RyKCJTZWxlY3QgYW4gaW1h
Z2UuIEEgcmVzaXplZCBjb3B5IGlzIHNhdmVkIHNvIHJlbW92YWJsZSBtZWRpYSBjYW4gYmUgZGlz
Y29ubmVjdGVkLiIpO0xheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7Y29s
b3I6VmJUb2tlbnMudGV4dERpbTtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlTGFiZWwgfQor
ICAgICAgICBUZXh0RmllbGQgeyBpZDpwYXRoO0xheW91dC5maWxsV2lkdGg6dHJ1ZTt0ZXh0OnBp
Y2tlci5mb2xkZXIudG9TdHJpbmcoKTtwbGFjZWhvbGRlclRleHQ6cXNUcigiRm9sZGVyIHBhdGgg
b3IgZmlsZTovLy8gVVJMIik7c2VsZWN0QnlNb3VzZTp0cnVlO2NvbG9yOlZiVG9rZW5zLnRleHQ7
Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUxhYmVsCisgICAgICAgICAgICBiYWNrZ3JvdW5k
OkNyaW1zb25HbGFzc1BhbmVsIHtyYWRpdXM6VmJUb2tlbnMucmFkaXVzQ29udHJvbH0KKyAgICAg
ICAgICAgIG9uQWNjZXB0ZWQ6e3BpY2tlci5mb2xkZXI9dGV4dC5pbmRleE9mKCJmaWxlOiIpPT09
MD90ZXh0OiJmaWxlOi8vIit0ZXh0O3BpY2tlci5maWxlcz1FY2xpcHNlUHJvZmlsZXMuYmFja2dy
b3VuZEZpbGVzKHBpY2tlci5mb2xkZXIpfQorICAgICAgICB9CisgICAgICAgIEVjbGlwc2VBY3Rp
b25CdXR0b24ge3RleHQ6cXNUcigiT3BlbiBmb2xkZXIiKTtvbkNsaWNrZWQ6e3BpY2tlci5mb2xk
ZXI9cGF0aC50ZXh0LmluZGV4T2YoImZpbGU6Iik9PT0wP3BhdGgudGV4dDoiZmlsZTovLyIrcGF0
aC50ZXh0O3BpY2tlci5maWxlcz1FY2xpcHNlUHJvZmlsZXMuYmFja2dyb3VuZEZpbGVzKHBpY2tl
ci5mb2xkZXIpfX0KKyAgICAgICAgTGlzdFZpZXcgeyBpZDpsaXN0O0xheW91dC5maWxsV2lkdGg6
dHJ1ZTtMYXlvdXQuZmlsbEhlaWdodDp0cnVlO2NsaXA6dHJ1ZTttb2RlbDpwaWNrZXIuZmlsZXM7
c3BhY2luZzo2O2tleU5hdmlnYXRpb25FbmFibGVkOnRydWU7YWN0aXZlRm9jdXNPblRhYjp0cnVl
CisgICAgICAgICAgICBkZWxlZ2F0ZTpFY2xpcHNlQWN0aW9uQnV0dG9uIHt3aWR0aDpsaXN0Lndp
ZHRoO3RleHQ6KG1vZGVsRGF0YS5kaXJlY3Rvcnk/IuKWuCAiOiIiKSttb2RlbERhdGEubmFtZQor
ICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDp7aWYobW9kZWxEYXRhLmRpcmVjdG9yeSl7cGlja2Vy
LmZvbGRlcj1tb2RlbERhdGEudXJsO3BhdGgudGV4dD1waWNrZXIuZm9sZGVyLnRvU3RyaW5nKCk7
cGlja2VyLmZpbGVzPUVjbGlwc2VQcm9maWxlcy5iYWNrZ3JvdW5kRmlsZXMocGlja2VyLmZvbGRl
cil9ZWxzZSBpZihFY2xpcHNlUHJvZmlsZXMuY2hvb3NlQmFja2dyb3VuZChtb2RlbERhdGEudXJs
KSlwaWNrZXIuY2xvc2UoKTtlbHNlIHBpY2tlci5lcnJvcj1xc1RyKCJVbmFibGUgdG8gcmVhZCB0
aGlzIGltYWdlLiBDaG9vc2UgUE5HLCBKUEVHLCBXZWJQIG9yIEJNUCB1cCB0byAzMiBNaUIuIil9
CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICAgICAgTGFiZWwge3RleHQ6cGlja2VyLmVy
cm9yO3Zpc2libGU6dGV4dC5sZW5ndGg+MDtjb2xvcjpWYlRva2Vucy5zdGF0dXNEYW5nZXI7TGF5
b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcDtmb250LnBpeGVsU2l6ZTpWYlRv
a2Vucy50eXBlTGFiZWx9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9Dcmltc29uR2xh
c3NCYWNrZHJvcC5xbWwgYi9hcHAvZ3VpL0NyaW1zb25HbGFzc0JhY2tkcm9wLnFtbApuZXcgZmls
ZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi42ZGMzZmZmCi0tLSAvZGV2L251bGwKKysrIGIv
YXBwL2d1aS9Dcmltc29uR2xhc3NCYWNrZHJvcC5xbWwKQEAgLTAsMCArMSwyMSBAQAoraW1wb3J0
IFF0UXVpY2sgMi45CitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBFY2xpcHNl
UHJvZmlsZXMgMS4wCitSZWN0YW5nbGUgeworICAgIGNvbG9yOiBWYlRva2Vucy5iZ1dpbmRvdwor
ICAgIGNsaXA6IHRydWUKKyAgICBJbWFnZSB7CisgICAgICAgIGlkOiB3YWxscGFwZXI7b2JqZWN0
TmFtZToiY3JpbXNvbldhbGxwYXBlciI7YW5jaG9ycy5maWxsOnBhcmVudDtzb3VyY2U6RWNsaXBz
ZVByb2ZpbGVzLmJhY2tncm91bmQ7ZmlsbE1vZGU6SW1hZ2UuUHJlc2VydmVBc3BlY3RDcm9wCisg
ICAgICAgIGFzeW5jaHJvbm91czp0cnVlO2NhY2hlOmZhbHNlO3NvdXJjZVNpemUud2lkdGg6MjU2
MDtzb3VyY2VTaXplLmhlaWdodDoyNTYwCisgICAgICAgIENvbm5lY3Rpb25zIHsgdGFyZ2V0OkVj
bGlwc2VQcm9maWxlcztmdW5jdGlvbiBvbkJhY2tncm91bmRDaGFuZ2VkKCl7dmFyIHVybD1FY2xp
cHNlUHJvZmlsZXMuYmFja2dyb3VuZDt3YWxscGFwZXIuc291cmNlPSIiO3dhbGxwYXBlci5zb3Vy
Y2U9dXJsfSB9CisgICAgfQorICAgIFJlY3RhbmdsZSB7IGFuY2hvcnMuZmlsbDpwYXJlbnQ7Y29s
b3I6VmJUb2tlbnMuYmdXaW5kb3c7b3BhY2l0eTpNYXRoLm1heChFY2xpcHNlUHJvZmlsZXMuaGln
aENvbnRyYXN0PzAuODowLEVjbGlwc2VQcm9maWxlcy5iYWNrZ3JvdW5kRGltLzEwMCkgfQorICAg
IFJlY3RhbmdsZSB7CisgICAgICAgIHdpZHRoOiBNYXRoLm1pbihwYXJlbnQud2lkdGgqMC43Miw4
NTApOyBoZWlnaHQ6IHdpZHRoOyByYWRpdXM6IHdpZHRoLzIKKyAgICAgICAgeDogcGFyZW50Lndp
ZHRoLXdpZHRoKjAuNjI7IHk6IC1oZWlnaHQqMC41NQorICAgICAgICBjb2xvcjogUXQucmdiYShW
YlRva2Vucy5hY2NlbnQucixWYlRva2Vucy5hY2NlbnQuZyxWYlRva2Vucy5hY2NlbnQuYiwwLjAz
NSkKKyAgICAgICAgYm9yZGVyLmNvbG9yOiBRdC5yZ2JhKFZiVG9rZW5zLmFjY2VudC5yLFZiVG9r
ZW5zLmFjY2VudC5nLFZiVG9rZW5zLmFjY2VudC5iLDAuMTUpOyBib3JkZXIud2lkdGg6IDIKKyAg
ICB9CisgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy5maWxsOnBhcmVudDsgZ3JhZGllbnQ6R3JhZGll
bnQgeyBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjowO2NvbG9yOiIjMDAwMDAwMDAiIH0KKyAgICAg
ICAgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246MTtjb2xvcjpWYlRva2Vucy5iZ1dpbmRvdyB9IH0g
fQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9Dcmltc29uR2xhc3NQYW5lbC5xbWwgYi9hcHAvZ3Vp
L0NyaW1zb25HbGFzc1BhbmVsLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
Li5lOWIzMzNjCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9Dcmltc29uR2xhc3NQYW5lbC5x
bWwKQEAgLTAsMCArMSwxMyBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgVmliZW1pcy5S
ZWRlc2lnbiAxLjAKK1JlY3RhbmdsZSB7CisgICAgaWQ6Z2xhc3MKKyAgICByYWRpdXM6IFZiVG9r
ZW5zLnJhZGl1c0NhcmQKKyAgICBjb2xvcjogVmJUb2tlbnMuYmdFbGV2CisgICAgYm9yZGVyLmNv
bG9yOiBWYlRva2Vucy5zdHJva2UKKyAgICBncmFkaWVudDogR3JhZGllbnQgeworICAgICAgICBH
cmFkaWVudFN0b3AgeyBwb3NpdGlvbjogMDsgY29sb3I6IFF0LnJnYmEoUXQubGlnaHRlcihnbGFz
cy5jb2xvciwxLjM1KS5yLFF0LmxpZ2h0ZXIoZ2xhc3MuY29sb3IsMS4zNSkuZyxRdC5saWdodGVy
KGdsYXNzLmNvbG9yLDEuMzUpLmIsVmJUb2tlbnMuZ2xhc3NPcGFjaXR5KSB9CisgICAgICAgIEdy
YWRpZW50U3RvcCB7IHBvc2l0aW9uOiAxOyBjb2xvcjogUXQucmdiYShnbGFzcy5jb2xvci5yLGds
YXNzLmNvbG9yLmcsZ2xhc3MuY29sb3IuYixWYlRva2Vucy5nbGFzc09wYWNpdHkpIH0KKyAgICB9
CisgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy50b3A6IHBhcmVudC50b3A7IGFuY2hvcnMudG9wTWFy
Z2luOiAxOyBhbmNob3JzLmhvcml6b250YWxDZW50ZXI6IHBhcmVudC5ob3Jpem9udGFsQ2VudGVy
OyB3aWR0aDogTWF0aC5tYXgoMCxwYXJlbnQud2lkdGgtMipwYXJlbnQucmFkaXVzKTsgaGVpZ2h0
OiAxOyBjb2xvcjogVmJUb2tlbnMuZ2xhc3NFZGdlIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkv
Q3JpbXNvbkdsYXNzUmFpbC5xbWwgYi9hcHAvZ3VpL0NyaW1zb25HbGFzc1JhaWwucW1sCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmUxYTRjNWIKLS0tIC9kZXYvbnVsbAorKysg
Yi9hcHAvZ3VpL0NyaW1zb25HbGFzc1JhaWwucW1sCkBAIC0wLDAgKzEsMjMgQEAKK2ltcG9ydCBR
dFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5M
YXlvdXRzIDEuMworaW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitDcmltc29uR2xhc3NQYW5l
bCB7CisgICAgaWQ6cmFpbAorICAgIHByb3BlcnR5IGJvb2wgaW5MaWJyYXJ5OmZhbHNlCisgICAg
c2lnbmFsIGhvbWVSZXF1ZXN0ZWQoKQorICAgIHNpZ25hbCBzZXR0aW5nc1JlcXVlc3RlZCgpCisg
ICAgc2lnbmFsIGNvbnRyb2xzUmVxdWVzdGVkKCkKKyAgICBDb2x1bW5MYXlvdXQgeworICAgICAg
ICBhbmNob3JzLnRvcDpwYXJlbnQudG9wO2FuY2hvcnMubGVmdDpwYXJlbnQubGVmdDthbmNob3Jz
LnJpZ2h0OnBhcmVudC5yaWdodDthbmNob3JzLnRvcE1hcmdpbjoxMDthbmNob3JzLmxlZnRNYXJn
aW46NDthbmNob3JzLnJpZ2h0TWFyZ2luOjQ7c3BhY2luZzoxMgorICAgICAgICBJbWFnZSB7IHNv
dXJjZToicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyI7TGF5b3V0LmFsaWdubWVudDpRdC5BbGln
bkhDZW50ZXI7TGF5b3V0LnByZWZlcnJlZFdpZHRoOjM4O0xheW91dC5wcmVmZXJyZWRIZWlnaHQ6
MzggfQorICAgICAgICBSZXBlYXRlciB7CisgICAgICAgICAgICBtb2RlbDpbe2xhYmVsOnFzVHIo
IkhvbWUiKSxpY29uOiJxcmM6L3Jlcy9jcmltc29uLWhvc3Quc3ZnIixhY3Rpb246ImhvbWUifSx7
bGFiZWw6cXNUcigiQ29udHJvbHMiKSxpY29uOiJxcmM6L3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2
ZyIsYWN0aW9uOiJjb250cm9scyJ9LHtsYWJlbDpxc1RyKCJTZXR0aW5ncyIpLGljb246InFyYzov
cmVzL3NldHRpbmdzLnN2ZyIsYWN0aW9uOiJzZXR0aW5ncyJ9XQorICAgICAgICAgICAgZGVsZWdh
dGU6IEVjbGlwc2VBY3Rpb25CdXR0b24geworICAgICAgICAgICAgICAgIG9iamVjdE5hbWU6ImNy
aW1zb25SYWlsQnV0dG9uIjtMYXlvdXQuZmlsbFdpZHRoOnRydWU7aW1wbGljaXRXaWR0aDo1Njtp
bXBsaWNpdEhlaWdodDo1Njt0ZXh0OiIiO2ljb25Tb3VyY2U6bW9kZWxEYXRhLmljb24KKyAgICAg
ICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6bW9kZWxEYXRhLmxhYmVsO1Rvb2xUaXAudGV4dDpt
b2RlbERhdGEubGFiZWw7VG9vbFRpcC52aXNpYmxlOmhvdmVyZWR8fGFjdGl2ZUZvY3VzCisgICAg
ICAgICAgICAgICAgb25DbGlja2VkOiB7aWYobW9kZWxEYXRhLmFjdGlvbj09PSJob21lIilyYWls
LmhvbWVSZXF1ZXN0ZWQoKTtlbHNlIGlmKG1vZGVsRGF0YS5hY3Rpb249PT0iY29udHJvbHMiKXJh
aWwuY29udHJvbHNSZXF1ZXN0ZWQoKTtlbHNlIHJhaWwuc2V0dGluZ3NSZXF1ZXN0ZWQoKX0KKyAg
ICAgICAgICAgIH0KKyAgICAgICAgfQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvQ3Jp
bXNvbkhvc3RQYW5lbC5xbWwgYi9hcHAvZ3VpL0NyaW1zb25Ib3N0UGFuZWwucW1sCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjI0NjJmMTIKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvZ3VpL0NyaW1zb25Ib3N0UGFuZWwucW1sCkBAIC0wLDAgKzEsMzIgQEAKK2ltcG9ydCBRdFF1
aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlv
dXRzIDEuMworaW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgU3RyZWFtaW5nUHJl
ZmVyZW5jZXMgMS4wCitDcmltc29uR2xhc3NQYW5lbCB7CisgICAgaWQ6cGFuZWwKKyAgICBwcm9w
ZXJ0eSBzdHJpbmcgaG9zdE5hbWU6IiIKKyAgICBwcm9wZXJ0eSBzdHJpbmcgaG9zdFR5cGU6IiIK
KyAgICBwcm9wZXJ0eSBzdHJpbmcgdHJhbnNwb3J0OiIiCisgICAgcHJvcGVydHkgYm9vbCBvbmxp
bmU6ZmFsc2UKKyAgICBwcm9wZXJ0eSB2YXIgaG9zdDooe30pCisgICAgc2lnbmFsIGhvc3RSZXF1
ZXN0ZWQoKQorICAgIFNjcm9sbFZpZXcgeworICAgICAgICBhbmNob3JzLmZpbGw6cGFyZW50O2Fu
Y2hvcnMubWFyZ2luczoxNjtjb250ZW50V2lkdGg6YXZhaWxhYmxlV2lkdGg7Y2xpcDp0cnVlCisg
ICAgICAgIENvbHVtbkxheW91dCB7CisgICAgICAgICAgICB3aWR0aDpwYXJlbnQud2lkdGg7c3Bh
Y2luZzoxNgorICAgICAgICAgICAgSW1hZ2UgeyBzb3VyY2U6InFyYzovcmVzL2VjbGlwc2UtaWNv
bi5zdmciO0xheW91dC5wcmVmZXJyZWRIZWlnaHQ6NjQ7TGF5b3V0LnByZWZlcnJlZFdpZHRoOjY0
O0xheW91dC5hbGlnbm1lbnQ6UXQuQWxpZ25IQ2VudGVyIH0KKyAgICAgICAgICAgIExhYmVsIHsg
dGV4dDpwYW5lbC5ob3N0TmFtZTtmb250LmZhbWlseTpWYlRva2Vucy5mb250RGlzcGxheTtmb250
LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlSGVhZGluZztmb250LmJvbGQ6dHJ1ZTtjb2xvcjpWYlRv
a2Vucy50ZXh0O0xheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7dGV4dEZv
cm1hdDpUZXh0LlBsYWluVGV4dCB9CisgICAgICAgICAgICBMYWJlbCB7IHRleHQ6cGFuZWwub25s
aW5lP3FzVHIoIkNvbm5lY3RlZCBob3N0Iik6cXNUcigiSG9zdCBvZmZsaW5lIik7Y29sb3I6cGFu
ZWwub25saW5lP1ZiVG9rZW5zLnN0YXR1c09ubGluZTpWYlRva2Vucy50ZXh0RGltO2ZvbnQucGl4
ZWxTaXplOlZiVG9rZW5zLnR5cGVMYWJlbDtMYXlvdXQuZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6
VGV4dC5XcmFwIH0KKyAgICAgICAgICAgIFJlcGVhdGVyIHsKKyAgICAgICAgICAgICAgICBtb2Rl
bDpbe2xhYmVsOnFzVHIoIkhvc3QgdHlwZSIpLHZhbHVlOnBhbmVsLmhvc3RUeXBlfHxxc1RyKCJD
b21wYXRpYmxlIGhvc3QiKX0se2xhYmVsOnFzVHIoIkNvbm5lY3Rpb24iKSx2YWx1ZTpwYW5lbC50
cmFuc3BvcnR8fHFzVHIoIkNoZWNraW5nIil9LHtsYWJlbDpxc1RyKCJSZXF1ZXN0ZWQgcmVzb2x1
dGlvbiIpLHZhbHVlOlN0cmVhbWluZ1ByZWZlcmVuY2VzLndpZHRoKyIgw5cgIitTdHJlYW1pbmdQ
cmVmZXJlbmNlcy5oZWlnaHR9LHtsYWJlbDpxc1RyKCJSZXF1ZXN0ZWQgZnJhbWUgcmF0ZSIpLHZh
bHVlOlN0cmVhbWluZ1ByZWZlcmVuY2VzLmZwcysiIEZQUyJ9LHtsYWJlbDpxc1RyKCJCaXRyYXRl
IGxpbWl0IiksdmFsdWU6KFN0cmVhbWluZ1ByZWZlcmVuY2VzLmJpdHJhdGVLYnBzLzEwMDApLnRv
Rml4ZWQoMSkrIiBNYnBzIn1dCisgICAgICAgICAgICAgICAgZGVsZWdhdGU6Q29sdW1uTGF5b3V0
IHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO3NwYWNpbmc6NQorICAgICAgICAgICAgICAgICAgICBM
YWJlbCB7dGV4dDptb2RlbERhdGEubGFiZWw7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUNh
cHRpb247Y29sb3I6VmJUb2tlbnMudGV4dERpbTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7d3JhcE1v
ZGU6VGV4dC5XcmFwfQorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7dGV4dDptb2RlbERhdGEu
dmFsdWU7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUxhYmVsO2NvbG9yOlZiVG9rZW5zLnRl
eHQ7TGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcDt0ZXh0Rm9ybWF0OlRl
eHQuUGxhaW5UZXh0fQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAg
ICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIkhvc3QgZGV0YWlscyIpO0xheW91
dC5maWxsV2lkdGg6dHJ1ZTtvbkNsaWNrZWQ6cGFuZWwuaG9zdFJlcXVlc3RlZCgpIH0KKyAgICAg
ICAgICAgIExhYmVsIHsgdGV4dDpxc1RyKCJDaG9vc2UgYW4gYXBwIHRvIHN0cmVhbS4gQWN0dWFs
IG5lZ290aWF0ZWQgcXVhbGl0eSBhcHBlYXJzIGluIHN0cmVhbSBzdGF0aXN0aWNzLiIpO2ZvbnQu
cGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVDYXB0aW9uO2NvbG9yOlZiVG9rZW5zLnRleHREaW07TGF5
b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcCB9CisgICAgICAgIH0KKyAgICB9
Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0NyaW1zb25Mb2NhbFBhbmVsLnFtbCBiL2FwcC9ndWkv
Q3JpbXNvbkxvY2FsUGFuZWwucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAu
LjVmZDJlZDkKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0NyaW1zb25Mb2NhbFBhbmVsLnFt
bApAQCAtMCwwICsxLDM2IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNv
bnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBWaWJlbWlzLlJl
ZGVzaWduIDEuMAoraW1wb3J0IExvY2FsSGFyZHdhcmUgMS4wCitDcmltc29uR2xhc3NQYW5lbCB7
CisgICAgaWQ6IHBhbmVsCisgICAgcHJvcGVydHkgYm9vbCBhY3RpdmU6IGZhbHNlCisgICAgc2ln
bmFsIGNvbnRyb2xzUmVxdWVzdGVkKCkKKyAgICBvbkFjdGl2ZUNoYW5nZWQ6IExvY2FsSGFyZHdh
cmUuc2V0Q29uc3VtZXJBY3RpdmUocGFuZWwsYWN0aXZlKQorICAgIENvbXBvbmVudC5vbkNvbXBs
ZXRlZDogaWYoYWN0aXZlKSBMb2NhbEhhcmR3YXJlLnNldENvbnN1bWVyQWN0aXZlKHBhbmVsLHRy
dWUpCisgICAgQ29tcG9uZW50Lm9uRGVzdHJ1Y3Rpb246IGlmKGFjdGl2ZSkgTG9jYWxIYXJkd2Fy
ZS5zZXRDb25zdW1lckFjdGl2ZShwYW5lbCxmYWxzZSkKKyAgICBmdW5jdGlvbiByZWFkaW5nKGtl
eSxzdWZmaXgpIHsgdmFyIHY9TG9jYWxIYXJkd2FyZS5yZWFkaW5nc1trZXldO3JldHVybiB2PT09
dW5kZWZpbmVkP3FzVHIoIlVuYXZhaWxhYmxlIik6TnVtYmVyKHYpLnRvRml4ZWQoMSkrKHN1ZmZp
eHx8IiIpIH0KKyAgICBTY3JvbGxWaWV3IHsKKyAgICAgICAgYW5jaG9ycy5maWxsOnBhcmVudDth
bmNob3JzLm1hcmdpbnM6MTY7Y29udGVudFdpZHRoOmF2YWlsYWJsZVdpZHRoO2NsaXA6dHJ1ZQor
ICAgICAgICBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgd2lkdGg6cGFyZW50LndpZHRoO3Nw
YWNpbmc6MTIKKyAgICAgICAgICAgIExhYmVsIHsgdGV4dDpxc1RyKCJMb2NhbCBTeXN0ZW0iKTtm
b250LmZhbWlseTpWYlRva2Vucy5mb250RGlzcGxheTtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50
eXBlQm9keTtmb250LmJvbGQ6dHJ1ZTtjb2xvcjpWYlRva2Vucy50ZXh0O0xheW91dC5maWxsV2lk
dGg6dHJ1ZTtlbGlkZTpUZXh0LkVsaWRlUmlnaHQgfQorICAgICAgICAgICAgTGFiZWwgeyB0ZXh0
OnFzVHIoIkVjbGlwc2VPUyBjb25zb2xlIik7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUNh
cHRpb247Y29sb3I6VmJUb2tlbnMudGV4dERpbTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7ZWxpZGU6
VGV4dC5FbGlkZVJpZ2h0IH0KKyAgICAgICAgICAgIFJlcGVhdGVyIHsKKyAgICAgICAgICAgICAg
ICBtb2RlbDpbe2xhYmVsOnFzVHIoIkNQVSIpLGtleToiY3B1UGVyY2VudCIsc3VmZml4OiIlIixt
YXg6MTAwfSx7bGFiZWw6cXNUcigiUkFNIiksa2V5OiJtZW1vcnlQZXJjZW50IixzdWZmaXg6IiUi
LG1heDoxMDB9LHtsYWJlbDpxc1RyKCJUZW1wZXJhdHVyZSIpLGtleToidGVtcGVyYXR1cmVDIixz
dWZmaXg6IiDCsEMiLG1heDoxMDB9LHtsYWJlbDpxc1RyKCJOZXR3b3JrIGRvd25sb2FkIiksa2V5
OiJyZWNlaXZlTWlCIixzdWZmaXg6IiBNaUIvcyIsbWF4OjB9XQorICAgICAgICAgICAgICAgIGRl
bGVnYXRlOkNyaW1zb25HbGFzc1BhbmVsIHsKKyAgICAgICAgICAgICAgICAgICAgb2JqZWN0TmFt
ZToiY3JpbXNvbk1ldHJpYyI7TGF5b3V0LmZpbGxXaWR0aDp0cnVlO2ltcGxpY2l0SGVpZ2h0Ok1h
dGgubWF4KDkyLFZiVG9rZW5zLnR5cGVCb2R5KjMrMjQpCisgICAgICAgICAgICAgICAgICAgIENv
bHVtbkxheW91dCB7CisgICAgICAgICAgICAgICAgICAgICAgICBhbmNob3JzLmZpbGw6cGFyZW50
O2FuY2hvcnMubWFyZ2luczoxMjtzcGFjaW5nOjUKKyAgICAgICAgICAgICAgICAgICAgICAgIExh
YmVsIHsgdGV4dDptb2RlbERhdGEubGFiZWw7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUxh
YmVsO2NvbG9yOlZiVG9rZW5zLnRleHREaW07TGF5b3V0LmZpbGxXaWR0aDp0cnVlO2VsaWRlOlRl
eHQuRWxpZGVSaWdodCB9CisgICAgICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6cGFu
ZWwucmVhZGluZyhtb2RlbERhdGEua2V5LG1vZGVsRGF0YS5zdWZmaXgpO2ZvbnQucGl4ZWxTaXpl
OlZiVG9rZW5zLnR5cGVCb2R5O2ZvbnQuYm9sZDp0cnVlO2NvbG9yOlZiVG9rZW5zLnRleHQ7TGF5
b3V0LmZpbGxXaWR0aDp0cnVlO2VsaWRlOlRleHQuRWxpZGVSaWdodCB9CisgICAgICAgICAgICAg
ICAgICAgICAgICBDcmltc29uU3BhcmtsaW5lIHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO0xheW91
dC5wcmVmZXJyZWRIZWlnaHQ6MjQ7c2FtcGxlczpMb2NhbEhhcmR3YXJlLmhpc3Rvcnk7bWV0cmlj
Om1vZGVsRGF0YS5rZXk7Y2VpbGluZzptb2RlbERhdGEubWF4IH0KKyAgICAgICAgICAgICAgICAg
ICAgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIEVjbGlw
c2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIlN5c3RlbSBDb250cm9scyIpO0xheW91dC5maWxs
V2lkdGg6dHJ1ZTtvbkNsaWNrZWQ6cGFuZWwuY29udHJvbHNSZXF1ZXN0ZWQoKSB9CisgICAgICAg
ICAgICBMYWJlbCB7IHRleHQ6cXNUcigiTG9jYWwgcmVhZGluZ3Mg4oCiIG1pc3Npbmcgc2Vuc29y
cyBzaG93IFVuYXZhaWxhYmxlIik7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUNhcHRpb247
Y29sb3I6VmJUb2tlbnMudGV4dERpbTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4
dC5XcmFwIH0KKyAgICAgICAgfQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvQ3JpbXNv
blNwYXJrbGluZS5xbWwgYi9hcHAvZ3VpL0NyaW1zb25TcGFya2xpbmUucW1sCm5ldyBmaWxlIG1v
ZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjQzZGQzYjQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAv
Z3VpL0NyaW1zb25TcGFya2xpbmUucW1sCkBAIC0wLDAgKzEsMjUgQEAKK2ltcG9ydCBRdFF1aWNr
IDIuOQoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitDYW52YXMgeworICAgIGlkOiBncmFw
aAorICAgIHByb3BlcnR5IHZhciBzYW1wbGVzOiBbXQorICAgIHByb3BlcnR5IHN0cmluZyBtZXRy
aWM6ICJjcHVQZXJjZW50IgorICAgIHByb3BlcnR5IHJlYWwgY2VpbGluZzogMTAwCisgICAgcHJv
cGVydHkgY29sb3IgbGluZUNvbG9yOiBWYlRva2Vucy5hY2NlbnQKKyAgICBvblNhbXBsZXNDaGFu
Z2VkOiByZXF1ZXN0UGFpbnQoKQorICAgIG9uTWV0cmljQ2hhbmdlZDogcmVxdWVzdFBhaW50KCkK
KyAgICBvbkxpbmVDb2xvckNoYW5nZWQ6IHJlcXVlc3RQYWludCgpCisgICAgb25XaWR0aENoYW5n
ZWQ6IHJlcXVlc3RQYWludCgpCisgICAgb25IZWlnaHRDaGFuZ2VkOiByZXF1ZXN0UGFpbnQoKQor
ICAgIG9uUGFpbnQ6IHsKKyAgICAgICAgdmFyIGM9Z2V0Q29udGV4dCgiMmQiKTtjLmNsZWFyUmVj
dCgwLDAsd2lkdGgsaGVpZ2h0KQorICAgICAgICB2YXIgaGlnaD1jZWlsaW5nCisgICAgICAgIGlm
KGhpZ2g8PTApIHsgaGlnaD0xO2Zvcih2YXIgaj0wO2o8c2FtcGxlcy5sZW5ndGg7aisrKSB7IHZh
ciBuPXNhbXBsZXNbal1bbWV0cmljXTtpZihuIT09dW5kZWZpbmVkJiZpc0Zpbml0ZShuKSloaWdo
PU1hdGgubWF4KGhpZ2gsbikgfSB9CisgICAgICAgIGMuc3Ryb2tlU3R5bGU9bGluZUNvbG9yO2Mu
bGluZVdpZHRoPTEuNTtjLmJlZ2luUGF0aCgpO3ZhciBzdGFydGVkPWZhbHNlCisgICAgICAgIGZv
cih2YXIgaT0wO2k8c2FtcGxlcy5sZW5ndGg7aSsrKSB7IHZhciB2PXNhbXBsZXNbaV1bbWV0cmlj
XTtpZih2PT09dW5kZWZpbmVkfHwhaXNGaW5pdGUodikpe3N0YXJ0ZWQ9ZmFsc2U7Y29udGludWV9
CisgICAgICAgICAgICB2YXIgeD0yKyh3aWR0aC00KSooNjAtc2FtcGxlcy5sZW5ndGgraSkvNTks
eT1oZWlnaHQtMi0oaGVpZ2h0LTQpKk1hdGgubWF4KDAsTWF0aC5taW4oaGlnaCx2KSkvaGlnaAor
ICAgICAgICAgICAgaWYoIXN0YXJ0ZWQpYy5tb3ZlVG8oeCx5KTtlbHNlIGMubGluZVRvKHgseSk7
c3RhcnRlZD10cnVlCisgICAgICAgIH0KKyAgICAgICAgYy5zdHJva2UoKQorICAgIH0KK30KZGlm
ZiAtLWdpdCBhL2FwcC9ndWkvQ3JpbXNvblN0YXR1c0RpYWxvZy5xbWwgYi9hcHAvZ3VpL0NyaW1z
b25TdGF0dXNEaWFsb2cucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmEx
ZDQ2NzIKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0NyaW1zb25TdGF0dXNEaWFsb2cucW1s
CkBAIC0wLDAgKzEsOTAgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29u
dHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0IFF0UXVpY2suQ29u
dHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBD
cmltc29uU3RhdHVzIDEuMAorCitOYXZpZ2FibGVEaWFsb2cgeworICAgIGlkOiBwYW5lbAorICAg
IHByb3BlcnR5IHN0cmluZyBraW5kOiAiaG9zdCIKKyAgICB3aWR0aDogTWF0aC5taW4oNjIwLCBw
YXJlbnQud2lkdGggLSAzMikKKyAgICBoZWlnaHQ6IE1hdGgubWluKGtpbmQgPT09ICJob3N0IiA/
IDY1MCA6IDI4MCwgcGFyZW50LmhlaWdodCAtIDMyKQorICAgIHRpdGxlOiBraW5kID09PSAiaG9z
dCIgPyBxc1RyKCJWaWJlcG9sbG8g4oCiIEhvc3QgaGFyZHdhcmUiKSA6IGtpbmQgPT09ICJuZXR3
b3JrIiA/IHFzVHIoIk5ldHdvcmsgc3RhdHVzIikgOiBxc1RyKCJCYXR0ZXJ5IHN0YXR1cyIpCisg
ICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuQ2xvc2UKKyAgICBNYXRlcmlhbC5iYWNrZ3JvdW5k
OiBWYlRva2Vucy5iZ0VsZXYKKyAgICBNYXRlcmlhbC5hY2NlbnQ6IFZiVG9rZW5zLmFjY2VudAor
ICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsgY29sb3I6IFZiVG9rZW5zLmJnRWxl
djsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNEaWFsb2c7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMu
c3Ryb2tlOyBib3JkZXIud2lkdGg6IDEgfQorICAgIG9uT3BlbmVkOiB7CisgICAgICAgIHVybElu
cHV0LnRleHQgPSBDcmltc29uU3RhdHVzLmVuZHBvaW50CisgICAgICAgIHBpbklucHV0LnRleHQg
PSBDcmltc29uU3RhdHVzLmZpbmdlcnByaW50CisgICAgICAgIHRva2VuSW5wdXQudGV4dCA9ICIi
CisgICAgICAgIENyaW1zb25TdGF0dXMuc2V0VmlzaWJsZShraW5kID09PSAiaG9zdCIpCisgICAg
fQorICAgIG9uQ2xvc2VkOiB7IENyaW1zb25TdGF0dXMuc2V0VmlzaWJsZShmYWxzZSk7IHRva2Vu
SW5wdXQudGV4dCA9ICIiOyBzdGFja1ZpZXcuZm9yY2VBY3RpdmVGb2N1cygpIH0KKyAgICBmdW5j
dGlvbiBtZXRyaWMoa2V5LCBzdWZmaXgpIHsKKyAgICAgICAgdmFyIG4gPSBDcmltc29uU3RhdHVz
LnN0YXRzW2tleV0KKyAgICAgICAgcmV0dXJuIG4gPT09IHVuZGVmaW5lZCA/IHFzVHIoIk4vQSIp
IDogTnVtYmVyKG4pLnRvRml4ZWQoMSkgKyBzdWZmaXgKKyAgICB9CisgICAgZnVuY3Rpb24gbWVt
b3J5KHByZWZpeCkgeworICAgICAgICB2YXIgcyA9IENyaW1zb25TdGF0dXMuc3RhdHMKKyAgICAg
ICAgcmV0dXJuIHNbcHJlZml4ICsgIl91c2VkX2J5dGVzIl0gPT09IHVuZGVmaW5lZCB8fCAhc1tw
cmVmaXggKyAiX3RvdGFsX2J5dGVzIl0gPyBxc1RyKCJOL0EiKQorICAgICAgICAgICAgIDogKHNb
cHJlZml4ICsgIl91c2VkX2J5dGVzIl0gLyAxMDczNzQxODI0KS50b0ZpeGVkKDEpICsgIiAvICIg
KyAoc1twcmVmaXggKyAiX3RvdGFsX2J5dGVzIl0gLyAxMDczNzQxODI0KS50b0ZpeGVkKDEpICsg
IiBHaUIiCisgICAgfQorICAgIGNvbnRlbnRJdGVtOiBTY3JvbGxWaWV3IHsKKyAgICAgICAgY2xp
cDogdHJ1ZQorICAgICAgICBjb250ZW50V2lkdGg6IGF2YWlsYWJsZVdpZHRoCisgICAgICAgIENv
bHVtbkxheW91dCB7CisgICAgICAgICAgICB3aWR0aDogcGFuZWwuYXZhaWxhYmxlV2lkdGgKKyAg
ICAgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMworICAgICAgICAgICAgTGFiZWwgewor
ICAgICAgICAgICAgICAgIHZpc2libGU6IHBhbmVsLmtpbmQgIT09ICJob3N0IgorICAgICAgICAg
ICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXAKKyAgICAg
ICAgICAgICAgICB0ZXh0OiBwYW5lbC5raW5kID09PSAibmV0d29yayIgPyAoQ3JpbXNvblN0YXR1
cy5sb2NhbC5uZXR3b3JrICsgKENyaW1zb25TdGF0dXMubG9jYWwud2lmaVNpZ25hbCA+PSAwID8g
IiDigKIgIiArIENyaW1zb25TdGF0dXMubG9jYWwud2lmaVNpZ25hbCArICIlIHNpZ25hbCIgOiAi
IikgKyAiXG4iICsgcXNUcigiQWN0aXZlIGxpbmsgc3RhdHVzOyBpbnRlcm5ldCBhY2Nlc3MgaXMg
bm90IGFzc3VtZWQuIikpCisgICAgICAgICAgICAgICAgICAgIDogKENyaW1zb25TdGF0dXMubG9j
YWwuYmF0dGVyeVBlcmNlbnQgPj0gMCA/IENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVBlcmNl
bnQgKyAiJSDigKIgIiA6ICIiKSArIENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVN0YXRlCisg
ICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQucGl4ZWxTaXplOiBWYlRv
a2Vucy50eXBlQm9keQorICAgICAgICAgICAgfQorICAgICAgICAgICAgTGFiZWwgeworICAgICAg
ICAgICAgICAgIHZpc2libGU6IHBhbmVsLmtpbmQgPT09ICJob3N0IgorICAgICAgICAgICAgICAg
IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXAKKyAgICAgICAgICAg
ICAgICB0ZXh0OiBDcmltc29uU3RhdHVzLnN0YXR1cworICAgICAgICAgICAgICAgIGNvbG9yOiBW
YlRva2Vucy50ZXh0RGltCisgICAgICAgICAgICB9CisgICAgICAgICAgICBSZXBlYXRlciB7Cisg
ICAgICAgICAgICAgICAgbW9kZWw6IHBhbmVsLmtpbmQgPT09ICJob3N0IiA/IFsKKyAgICAgICAg
ICAgICAgICAgICAgW3FzVHIoIkNQVSIpLCBwYW5lbC5tZXRyaWMoImNwdV9wZXJjZW50IiwgIiUi
KSwgcGFuZWwubWV0cmljKCJjcHVfdGVtcF9jIiwgIiDCsEMiKV0sCisgICAgICAgICAgICAgICAg
ICAgIFtxc1RyKCJSQU0iKSwgcGFuZWwubWVtb3J5KCJyYW0iKSwgcGFuZWwubWV0cmljKCJyYW1f
cGVyY2VudCIsICIlIildLAorICAgICAgICAgICAgICAgICAgICBbcXNUcigiR1BVIiksIHBhbmVs
Lm1ldHJpYygiZ3B1X3BlcmNlbnQiLCAiJSIpLCBwYW5lbC5tZXRyaWMoImdwdV90ZW1wX2MiLCAi
IMKwQyIpXSwKKyAgICAgICAgICAgICAgICAgICAgW3FzVHIoIlZSQU0iKSwgcGFuZWwubWVtb3J5
KCJ2cmFtIiksIHBhbmVsLm1ldHJpYygidnJhbV9wZXJjZW50IiwgIiUiKV0sCisgICAgICAgICAg
ICAgICAgICAgIFtxc1RyKCJHUFUgZW5jb2RlciIpLCBwYW5lbC5tZXRyaWMoImdwdV9lbmNvZGVy
X3BlcmNlbnQiLCAiJSIpLCAiIl0sCisgICAgICAgICAgICAgICAgICAgIFtxc1RyKCJIb3N0IG5l
dHdvcmsiKSwgcGFuZWwubWV0cmljKCJuZXRfcnhfYnBzIiwgIiBCL3MgUlgiKSwgcGFuZWwubWV0
cmljKCJuZXRfdHhfYnBzIiwgIiBCL3MgVFgiKV0KKyAgICAgICAgICAgICAgICBdIDogW10KKyAg
ICAgICAgICAgICAgICBkZWxlZ2F0ZTogUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgICAgICAgICAg
TGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgaW1wbGljaXRIZWlnaHQ6IDU4CisgICAgICAgICAgICAg
ICAgICAgIGNvbG9yOiBWYlRva2Vucy5iZ1dpbmRvdzsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXND
b250cm9sCisgICAgICAgICAgICAgICAgICAgIGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tl
OyBib3JkZXIud2lkdGg6IDEKKyAgICAgICAgICAgICAgICAgICAgUm93TGF5b3V0IHsKKyAgICAg
ICAgICAgICAgICAgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50OyBhbmNob3JzLm1hcmdpbnM6
IDEyCisgICAgICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IG1vZGVsRGF0YVswXTsg
Y29sb3I6IFZiVG9rZW5zLnRleHREaW07IExheW91dC5wcmVmZXJyZWRXaWR0aDogMTE1IH0KKyAg
ICAgICAgICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogbW9kZWxEYXRhWzFdOyBjb2xvcjog
VmJUb2tlbnMudGV4dDsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZSB9CisgICAgICAgICAgICAgICAg
ICAgICAgICBMYWJlbCB7IHRleHQ6IG1vZGVsRGF0YVsyXTsgY29sb3I6IFZiVG9rZW5zLmFjY2Vu
dCB9CisgICAgICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAg
ICB9CisgICAgICAgICAgICBHcm91cEJveCB7CisgICAgICAgICAgICAgICAgdmlzaWJsZTogcGFu
ZWwua2luZCA9PT0gImhvc3QiCisgICAgICAgICAgICAgICAgdGl0bGU6IHFzVHIoIkNvbmZpZ3Vy
ZSBob3N0IHN0YXRzIikKKyAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisg
ICAgICAgICAgICAgICAgQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgYW5jaG9y
cy5maWxsOiBwYXJlbnQKKyAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJTZWxlY3QgYSBob3N0
IGZpcnN0LiBFbmFibGUgcmVhbHRpbWUgc3RhdHMgaW4gVmliZXBvbGxvIGFuZCBjcmVhdGUgYSBy
ZWFkLW9ubHkgdG9rZW4gZm9yIEdFVCAvYXBpL2hvc3Qvc3RhdHMuIEdhbWVTdHJlYW0gcGFpcmlu
ZyBkb2VzIG5vdCBncmFudCB0aGlzIGFjY2Vzcy4iKTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0g
fQorICAgICAgICAgICAgICAgICAgICBUZXh0RmllbGQgeyBpZDogdXJsSW5wdXQ7IExheW91dC5m
aWxsV2lkdGg6IHRydWU7IHBsYWNlaG9sZGVyVGV4dDogcXNUcigiSFRUUFMgaG9zdCBVUkwsIGUu
Zy4gaHR0cHM6Ly8xOTIuMTY4LjEuMTA6NDc5OTAiKTsgc2VsZWN0QnlNb3VzZTogdHJ1ZSB9Cisg
ICAgICAgICAgICAgICAgICAgIFRleHRGaWVsZCB7IGlkOiB0b2tlbklucHV0OyBMYXlvdXQuZmls
bFdpZHRoOiB0cnVlOyBwbGFjZWhvbGRlclRleHQ6IHFzVHIoIlJlYWQtb25seSBBUEkgdG9rZW4g
KGJsYW5rIGtlZXBzIHNhdmVkIHRva2VuKSIpOyBlY2hvTW9kZTogVGV4dElucHV0LlBhc3N3b3Jk
OyBzZWxlY3RCeU1vdXNlOiB0cnVlIH0KKyAgICAgICAgICAgICAgICAgICAgVGV4dEZpZWxkIHsg
aWQ6IHBpbklucHV0OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBwbGFjZWhvbGRlclRleHQ6IHFz
VHIoIlNIQS0yNTYgY2VydGlmaWNhdGUgZmluZ2VycHJpbnQgZm9yIGEgc2VsZi1zaWduZWQgaG9z
dCIpOyBzZWxlY3RCeU1vdXNlOiB0cnVlIH0KKyAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyBM
YXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJW
ZXJpZnkgYSBzZWxmLXNpZ25lZCBjZXJ0aWZpY2F0ZSdzIFNIQS0yNTYgZmluZ2VycHJpbnQgb24g
dGhlIGhvc3QgYmVmb3JlIHNhdmluZyBpdC4gVG9rZW4gaXMgc3RvcmVkIHByaXZhdGVseSBvbiB0
aGlzIFVTQjsgaXQgaXMgbm90IGVuY3J5cHRlZC4gVW5zdXBwb3J0ZWQgb3IgbWlzc2luZyBzZW5z
b3JzIHNob3cgTi9BLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICAg
ICAgICAgIEJ1dHRvbiB7IHRleHQ6IHFzVHIoIlNhdmUgJiBjb25uZWN0Iik7IG9uQ2xpY2tlZDog
eyBpZiAoQ3JpbXNvblN0YXR1cy5jb25maWd1cmUodXJsSW5wdXQudGV4dCwgdG9rZW5JbnB1dC50
ZXh0LCBwaW5JbnB1dC50ZXh0KSkgdG9rZW5JbnB1dC50ZXh0ID0gIiIgfSB9CisgICAgICAgICAg
ICAgICAgfQorICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEv
YXBwL2d1aS9FY2xpcHNlQWJvdXREaWFsb2cucW1sIGIvYXBwL2d1aS9FY2xpcHNlQWJvdXREaWFs
b2cucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmZiZDBhM2YKLS0tIC9k
ZXYvbnVsbAorKysgYi9hcHAvZ3VpL0VjbGlwc2VBYm91dERpYWxvZy5xbWwKQEAgLTAsMCArMSwz
NCBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2lt
cG9ydCBRdFF1aWNrLkxheW91dHMgMS4zCitpbXBvcnQgUXRRdWljay5Db250cm9scy5NYXRlcmlh
bCAyLjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAorTmF2aWdhYmxlRGlhbG9nIHsKKyAg
ICBpZDogcGFuZWwKKyAgICBwcm9wZXJ0eSB2YXIgaW5mbzogKHt9KQorICAgIHdpZHRoOiBNYXRo
Lm1pbig1MjAscGFyZW50LndpZHRoLTMyKQorICAgIHRpdGxlOiBxc1RyKCJBYm91dCBFY2xpcHNl
IikKKyAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5DbG9zZQorICAgIE1hdGVyaWFsLmJhY2tn
cm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNj
ZW50CisgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgeyByYWRpdXM6IFZiVG9rZW5z
LnJhZGl1c0RpYWxvZzsgY29sb3I6IFZiVG9rZW5zLmJnRWxldjsgYm9yZGVyLmNvbG9yOiBWYlRv
a2Vucy5zdHJva2UKKyAgICAgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGNv
bG9yOiAidHJhbnNwYXJlbnQiOyBncmFkaWVudDogR3JhZGllbnQgeyBHcmFkaWVudFN0b3AgeyBw
b3NpdGlvbjogMDsgY29sb3I6IFF0LnJnYmEoMSwxLDEsMC4wMzUpIH0gR3JhZGllbnRTdG9wIHsg
cG9zaXRpb246IDE7IGNvbG9yOiAidHJhbnNwYXJlbnQiIH0gfSB9CisgICAgfQorICAgIGNvbnRl
bnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMK
KyAgICAgICAgSW1hZ2UgeyBzb3VyY2U6ICJxcmM6L3Jlcy9lY2xpcHNlLWljb24uc3ZnIjsgc291
cmNlU2l6ZS53aWR0aDogOTY7IHNvdXJjZVNpemUuaGVpZ2h0OiA5NjsgTGF5b3V0LmFsaWdubWVu
dDogUXQuQWxpZ25IQ2VudGVyOyBMYXlvdXQucHJlZmVycmVkV2lkdGg6IDk2OyBMYXlvdXQucHJl
ZmVycmVkSGVpZ2h0OiA5NiB9CisgICAgICAgIExhYmVsIHsgdGV4dDogIkVDTElQU0UiOyBjb2xv
cjogVmJUb2tlbnMudGV4dDsgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5OyBmb250
LnBpeGVsU2l6ZTogMjQ7IGZvbnQubGV0dGVyU3BhY2luZzogNDsgTGF5b3V0LmFsaWdubWVudDog
UXQuQWxpZ25IQ2VudGVyIH0KKyAgICAgICAgTGFiZWwgeyB0ZXh0OiBxc1RyKCJNYWRlIGJ5IFRo
M0QzY2szciIpOyBjb2xvcjogVmJUb2tlbnMuYWNjZW50OyBMYXlvdXQuYWxpZ25tZW50OiBRdC5B
bGlnbkhDZW50ZXIgfQorICAgICAgICBMYWJlbCB7CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3Jh
cDsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0KKyAgICAgICAgICAgIHRleHQ6IHFzVHIoIk9TOiAl
MSAlMlxuVGFyZ2V0OiAlM1xuRmVkb3JhOiAlNFxuS2VybmVsOiAlNVxuRWNsaXBzZSBmcm9udGVu
ZDogJTYg4oCiIGN1c3RvbWl6ZWQiKQorICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8u
b3MgfHwge30pLk5BTUUgfHwgIkVjbGlwc2VPUyIpCisgICAgICAgICAgICAgICAgLmFyZygocGFu
ZWwuaW5mby5vcyB8fCB7fSkuVkVSU0lPTiB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAg
ICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3MgfHwge30pLlRBUkdFVCB8fCBxc1RyKCJVbmF2
YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3MgfHwge30pLkZF
RE9SQSB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIC5hcmcocGFuZWwu
aW5mby5rZXJuZWwgfHwgcXNUcigiVW5hdmFpbGFibGUiKSkKKyAgICAgICAgICAgICAgICAuYXJn
KFF0LmFwcGxpY2F0aW9uLnZlcnNpb24gfHwgIjAuNS4wIikKKyAgICAgICAgfQorICAgICAgICBM
YWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IGNvbG9y
OiBWYlRva2Vucy50ZXh0RGltOyB0ZXh0OiBxc1RyKCJBIGxpZ2h0d2VpZ2h0IEVjbGlwc2VPUyBm
cm9udGVuZC4gQmFzZWQgb24gVmliZW1pcyBhbmQgTW9vbmxpZ2h0OyBvcmlnaW5hbCBvcGVuLXNv
dXJjZSBjcmVkaXRzIGFuZCBsaWNlbnNlcyByZW1haW4gYXZhaWxhYmxlIGluIFNldHRpbmdzLiBV
cGRhdGVzIGFyZSBtYW5hZ2VkIGJ5IEVjbGlwc2VPUy4iKSB9CisgICAgfQorfQpkaWZmIC0tZ2l0
IGEvYXBwL2d1aS9FY2xpcHNlQWN0aW9uQnV0dG9uLnFtbCBiL2FwcC9ndWkvRWNsaXBzZUFjdGlv
bkJ1dHRvbi5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uYTgzZWYwMQot
LS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5xbWwKQEAgLTAs
MCArMSwzNiBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAy
LjUKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMu
aW1wbCAyLjUKK0J1dHRvbiB7CisgICAgaWQ6IGJ1dHRvbgorICAgIHRvcEluc2V0OiAwOyBib3R0
b21JbnNldDogMDsgbGVmdEluc2V0OiAwOyByaWdodEluc2V0OiAwCisgICAgcHJvcGVydHkgc3Ry
aW5nIGljb25Tb3VyY2U6ICIiCisgICAgaW1wbGljaXRIZWlnaHQ6IE1hdGgubWF4KDQ0LGNvbnRl
bnRJdGVtLmltcGxpY2l0SGVpZ2h0ICsgMjApCisgICAgaW1wbGljaXRXaWR0aDogTWF0aC5tYXgo
MTAwLCBjb250ZW50SXRlbS5pbXBsaWNpdFdpZHRoICsgMjgpCisgICAgcGFkZGluZzogMTIKKyAg
ICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKKyAgICBmb250LnBpeGVsU2l6ZTogVmJU
b2tlbnMudHlwZUxhYmVsCisgICAgQWNjZXNzaWJsZS5uYW1lOiB0ZXh0CisgICAgYWN0aXZlRm9j
dXNPblRhYjogdHJ1ZQorICAgIEtleXMub25SZXR1cm5QcmVzc2VkOiBpZiAoZW5hYmxlZCkgY2xp
Y2tlZCgpCisgICAgS2V5cy5vbkVudGVyUHJlc3NlZDogaWYgKGVuYWJsZWQpIGNsaWNrZWQoKQor
ICAgIEtleXMub25SaWdodFByZXNzZWQ6IG5leHRJdGVtSW5Gb2N1c0NoYWluKHRydWUpLmZvcmNl
QWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgS2V5cy5vbkxlZnRQcmVzc2VkOiBuZXh0SXRl
bUluRm9jdXNDaGFpbihmYWxzZSkuZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICBL
ZXlzLm9uRG93blByZXNzZWQ6IG5leHRJdGVtSW5Gb2N1c0NoYWluKHRydWUpLmZvcmNlQWN0aXZl
Rm9jdXMoUXQuVGFiRm9jdXMpCisgICAgS2V5cy5vblVwUHJlc3NlZDogbmV4dEl0ZW1JbkZvY3Vz
Q2hhaW4oZmFsc2UpLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgYmFja2dyb3Vu
ZDogQ3JpbXNvbkdsYXNzUGFuZWwgeworICAgICAgICByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0Nv
bnRyb2wKKyAgICAgICAgY29sb3I6IGJ1dHRvbi5kb3duID8gVmJUb2tlbnMuYmdFbGV2MiA6IGJ1
dHRvbi5ob3ZlcmVkID8gVmJUb2tlbnMuYmdFbGV2MiA6IFZiVG9rZW5zLmJnV2luZG93CisgICAg
ICAgIGJvcmRlci53aWR0aDogYnV0dG9uLmFjdGl2ZUZvY3VzID8gMiA6IDEKKyAgICAgICAgYm9y
ZGVyLmNvbG9yOiBidXR0b24uYWN0aXZlRm9jdXMgfHwgYnV0dG9uLmhvdmVyZWQgPyBWYlRva2Vu
cy5hY2NlbnQgOiBWYlRva2Vucy5zdHJva2UKKyAgICAgICAgb3BhY2l0eTogYnV0dG9uLmVuYWJs
ZWQgPyAxIDogMC41CisgICAgfQorICAgIGNvbnRlbnRJdGVtOiBJdGVtIHsKKyAgICAgICAgaW1w
bGljaXRXaWR0aDogYnV0dG9uTGFiZWwuaW1wbGljaXRXaWR0aCArIChidXR0b24uaWNvblNvdXJj
ZSAhPT0gIiIgPyAyOCA6IDApCisgICAgICAgIGltcGxpY2l0SGVpZ2h0OiBNYXRoLm1heChidXR0
b25MYWJlbC5pbXBsaWNpdEhlaWdodCwgYnV0dG9uLmljb25Tb3VyY2UgIT09ICIiID8gMjAgOiAw
KQorICAgICAgICBvcGFjaXR5OiBidXR0b24uZW5hYmxlZCA/IDEgOiAwLjUKKyAgICAgICAgSWNv
bkltYWdlIHsgY29sb3I6IFZiVG9rZW5zLmFjY2VudDsgdmlzaWJsZTogYnV0dG9uLmljb25Tb3Vy
Y2UgIT09ICIiOyBzb3VyY2U6IGJ1dHRvbi5pY29uU291cmNlOyB3aWR0aDogdmlzaWJsZSA/IDIw
IDogMDsgaGVpZ2h0OiAyMDsgeDpidXR0b24udGV4dC5sZW5ndGg9PT0wPyhwYXJlbnQud2lkdGgt
d2lkdGgpLzI6MDsgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVy
IH0KKyAgICAgICAgTGFiZWwgeyBpZDpidXR0b25MYWJlbDt0ZXh0OiBidXR0b24udGV4dDsgdGV4
dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBmb250OiBidXR0
b24uZm9udDt4OmJ1dHRvbi5pY29uU291cmNlICE9PSAiIiA/IDI4IDogMDt3aWR0aDpNYXRoLm1h
eCgwLHBhcmVudC53aWR0aC14KTtlbGlkZTpUZXh0LkVsaWRlUmlnaHQ7IGFuY2hvcnMudmVydGlj
YWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlciB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEv
YXBwL2d1aS9FY2xpcHNlQ29tYm9Cb3gucW1sIGIvYXBwL2d1aS9FY2xpcHNlQ29tYm9Cb3gucW1s
Cm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmY0NzZkZTEKLS0tIC9kZXYvbnVs
bAorKysgYi9hcHAvZ3VpL0VjbGlwc2VDb21ib0JveC5xbWwKQEAgLTAsMCArMSwyOCBAQAoraW1w
b3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1
aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitD
b21ib0JveCB7CisgICAgaWQ6IGNvbnRyb2wKKyAgICB0b3BJbnNldDogMDsgYm90dG9tSW5zZXQ6
IDA7IGxlZnRJbnNldDogMDsgcmlnaHRJbnNldDogMAorICAgIGltcGxpY2l0SGVpZ2h0OiBNYXRo
Lm1heCg0NCwgZm9udC5waXhlbFNpemUgKyAyNCkKKyAgICBmb250LmZhbWlseTogVmJUb2tlbnMu
Zm9udEJvZHkKKyAgICBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUxhYmVsCisgICAgTWF0
ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBsZWZ0UGFkZGluZzogMTI7IHJpZ2h0
UGFkZGluZzogMzYKKyAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7IGNvbG9yOiBW
YlRva2Vucy5iZ0VsZXY7IHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ29udHJvbDsgYm9yZGVyLmNv
bG9yOiBjb250cm9sLmFjdGl2ZUZvY3VzID8gVmJUb2tlbnMuYWNjZW50IDogVmJUb2tlbnMuc3Ry
b2tlOyBib3JkZXIud2lkdGg6IGNvbnRyb2wuYWN0aXZlRm9jdXMgPyAyIDogMTsgb3BhY2l0eTog
Y29udHJvbC5lbmFibGVkID8gMSA6IC41IH0KKyAgICBjb250ZW50SXRlbTogTGFiZWwgeyB0ZXh0
OiBjb250cm9sLmRpc3BsYXlUZXh0OyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgZm9udDog
Y29udHJvbC5mb250OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgdmVydGljYWxBbGlnbm1lbnQ6IFRl
eHQuQWxpZ25WQ2VudGVyOyBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0OyBvcGFjaXR5OiBjb250cm9s
LmVuYWJsZWQgPyAxIDogLjUgfQorICAgIGRlbGVnYXRlOiBJdGVtRGVsZWdhdGUgeworICAgICAg
ICB3aWR0aDogY29udHJvbC53aWR0aAorICAgICAgICBpbXBsaWNpdEhlaWdodDogTWF0aC5tYXgo
NDQsY29udHJvbC5mb250LnBpeGVsU2l6ZSsyNCkKKyAgICAgICAgaGlnaGxpZ2h0ZWQ6IGNvbnRy
b2wuaGlnaGxpZ2h0ZWRJbmRleCA9PT0gaW5kZXgKKyAgICAgICAgY29udGVudEl0ZW06IExhYmVs
IHsgdGV4dDogY29udHJvbC50ZXh0QXQoaW5kZXgpOyB0ZXh0Rm9ybWF0OlRleHQuUGxhaW5UZXh0
OyBmb250OmNvbnRyb2wuZm9udDsgY29sb3I6VmJUb2tlbnMudGV4dDsgZWxpZGU6VGV4dC5FbGlk
ZVJpZ2h0IH0KKyAgICAgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgeyBjb2xvcjog
cGFyZW50LmhpZ2hsaWdodGVkID8gVmJUb2tlbnMuYmdFbGV2MiA6IFZiVG9rZW5zLmJnRWxldjsg
cmFkaXVzOlZiVG9rZW5zLnJhZGl1c0NvbnRyb2w7IGJvcmRlci5jb2xvcjpwYXJlbnQuaGlnaGxp
Z2h0ZWQ/VmJUb2tlbnMuYWNjZW50OiJ0cmFuc3BhcmVudCIgfQorICAgIH0KKyAgICBwb3B1cDog
UG9wdXAgeworICAgICAgICB5OiBjb250cm9sLmhlaWdodCArIDQ7IHdpZHRoOmNvbnRyb2wud2lk
dGg7IHBhZGRpbmc6NgorICAgICAgICBpbXBsaWNpdEhlaWdodDogTWF0aC5taW4oY29udGVudEl0
ZW0uaW1wbGljaXRIZWlnaHQgKyAxMiwzMjApCisgICAgICAgIGJhY2tncm91bmQ6Q3JpbXNvbkds
YXNzUGFuZWwgeyBjb2xvcjpWYlRva2Vucy5iZ0VsZXY7cmFkaXVzOlZiVG9rZW5zLnJhZGl1c0Nv
bnRyb2w7Ym9yZGVyLmNvbG9yOlZiVG9rZW5zLnN0cm9rZSB9CisgICAgICAgIGNvbnRlbnRJdGVt
Okxpc3RWaWV3IHsgY2xpcDp0cnVlO2ltcGxpY2l0SGVpZ2h0OmNvbnRlbnRIZWlnaHQ7bW9kZWw6
Y29udHJvbC5wb3B1cC52aXNpYmxlP2NvbnRyb2wuZGVsZWdhdGVNb2RlbDpudWxsO2N1cnJlbnRJ
bmRleDpjb250cm9sLmhpZ2hsaWdodGVkSW5kZXg7U2Nyb2xsSW5kaWNhdG9yLnZlcnRpY2FsOlNj
cm9sbEluZGljYXRvciB7fSB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNl
Q29udHJvbENlbnRlci5xbWwgYi9hcHAvZ3VpL0VjbGlwc2VDb250cm9sQ2VudGVyLnFtbApuZXcg
ZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5lMjMyZTFlCi0tLSAvZGV2L251bGwKKysr
IGIvYXBwL2d1aS9FY2xpcHNlQ29udHJvbENlbnRlci5xbWwKQEAgLTAsMCArMSwxNjQgQEAKK2lt
cG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRR
dWljay5MYXlvdXRzIDEuMworaW1wb3J0IFF0UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitp
bXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBTeXN0ZW1Db250cm9scyAxLjAKK2lt
cG9ydCBDcmltc29uU3RhdHVzIDEuMAoraW1wb3J0IFN0cmVhbWluZ1ByZWZlcmVuY2VzIDEuMAor
aW1wb3J0IEVjbGlwc2VQcm9maWxlcyAxLjAKKworRHJhd2VyIHsKKyAgICBpZDogcGFuZWwKKyAg
ICBlZGdlOiBRdC5SaWdodEVkZ2UKKyAgICB3aWR0aDogTWF0aC5taW4oNTYwLCBwYXJlbnQud2lk
dGggLSAyNCkKKyAgICBoZWlnaHQ6IHBhcmVudC5oZWlnaHQKKyAgICBtb2RhbDogdHJ1ZQorICAg
IE92ZXJsYXkubW9kYWw6IFJlY3RhbmdsZSB7Y29sb3I6VmJUb2tlbnMuc2hlZXRTY3JpbX0KKyAg
ICBlbnRlcjogVHJhbnNpdGlvbiB7IE51bWJlckFuaW1hdGlvbiB7IHByb3BlcnR5OiAicG9zaXRp
b24iOyBmcm9tOiAwOyB0bzogMTsgZHVyYXRpb246IFZiVG9rZW5zLnNoZWV0SW5NcyB9IH0KKyAg
ICBleGl0OiBUcmFuc2l0aW9uIHsgTnVtYmVyQW5pbWF0aW9uIHsgcHJvcGVydHk6ICJwb3NpdGlv
biI7IGZyb206IDE7IHRvOiAwOyBkdXJhdGlvbjogVmJUb2tlbnMuc2hlZXRJbk1zIH0gfQorICAg
IHByb3BlcnR5IHZhciBob3N0OiAoe30pCisgICAgcHJvcGVydHkgYm9vbCBjYW5XYWtlOiBmYWxz
ZQorICAgIHByb3BlcnR5IGJvb2wgY2FuTWFuYWdlOiBmYWxzZQorICAgIHByb3BlcnR5IHN0cmlu
ZyBuZXh0UGFuZWw6ICIiCisgICAgcHJvcGVydHkgc3RyaW5nIG1lc3NhZ2U6ICIiCisgICAgcHJv
cGVydHkgdmFyIHNhdmVkTmFtZXM6IFtdCisgICAgcHJvcGVydHkgc3RyaW5nIHBvd2VyQWN0aW9u
OiAiIgorICAgIHNpZ25hbCBuYXZpZ2F0ZVJlcXVlc3RlZChzdHJpbmcgZGVzdGluYXRpb24pCisg
ICAgc2lnbmFsIHdha2VSZXF1ZXN0ZWQoKQorICAgIE1hdGVyaWFsLnRoZW1lOiBNYXRlcmlhbC5E
YXJrCisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJp
YWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQ
YW5lbCB7IGNvbG9yOiBWYlRva2Vucy5iZ0VsZXY7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ry
b2tlCisgICAgICAgIFJlY3RhbmdsZSB7IGFuY2hvcnMuZmlsbDogcGFyZW50OyBjb2xvcjogInRy
YW5zcGFyZW50IjsgZ3JhZGllbnQ6IEdyYWRpZW50IHsgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246
IDA7IGNvbG9yOiBRdC5yZ2JhKDEsMSwxLDAuMDM1KSB9IEdyYWRpZW50U3RvcCB7IHBvc2l0aW9u
OiAxOyBjb2xvcjogInRyYW5zcGFyZW50IiB9IH0gfQorICAgIH0KKyAgICBmdW5jdGlvbiBkZWZl
cihkZXN0aW5hdGlvbikgeyBuZXh0UGFuZWwgPSBkZXN0aW5hdGlvbjsgY2xvc2UoKSB9CisgICAg
ZnVuY3Rpb24gYXBwbHkodmFsdWVzKSB7CisgICAgICAgIGlmICghdmFsdWVzLndpZHRoKSB7IG1l
c3NhZ2UgPSBxc1RyKCJTYXZlIHRoaXMgcHJvZmlsZSBmaXJzdC4iKTsgcmV0dXJuIH0KKyAgICAg
ICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMud2lkdGggPSB2YWx1ZXMud2lkdGgKKyAgICAgICAgU3Ry
ZWFtaW5nUHJlZmVyZW5jZXMuaGVpZ2h0ID0gdmFsdWVzLmhlaWdodAorICAgICAgICBTdHJlYW1p
bmdQcmVmZXJlbmNlcy5mcHMgPSB2YWx1ZXMuZnBzCisgICAgICAgIFN0cmVhbWluZ1ByZWZlcmVu
Y2VzLmJpdHJhdGVLYnBzID0gdmFsdWVzLmJpdHJhdGVLYnBzCisgICAgICAgIFN0cmVhbWluZ1By
ZWZlcmVuY2VzLnNhdmUoKQorICAgICAgICBtZXNzYWdlID0gcXNUcigiUHJvZmlsZSBhcHBsaWVk
IGZvciB0aGUgbmV4dCBzdHJlYW0uIikKKyAgICB9CisgICAgb25PcGVuZWQ6IHsgbWVzc2FnZSA9
ICIiOyBTeXN0ZW1Db250cm9scy5vcGVuKCJjZW50ZXIiKTsgcHJvZmlsZU5hbWUudGV4dCA9ICJH
YW1pbmciOyBzYXZlZE5hbWVzID0gRWNsaXBzZVByb2ZpbGVzLm5hbWVzKGhvc3QuaWQgfHwgIiIp
IH0KKyAgICBvbkNsb3NlZDogeworICAgICAgICBwb3dlckRpYWxvZy5jbG9zZSgpOyBTeXN0ZW1D
b250cm9scy5jbG9zZSgpOyBzdGFja1ZpZXcuZm9yY2VBY3RpdmVGb2N1cygpCisgICAgICAgIGlm
IChuZXh0UGFuZWwgIT09ICIiKSB7IHZhciBkZXN0aW5hdGlvbiA9IG5leHRQYW5lbDsgbmV4dFBh
bmVsID0gIiI7IG5hdmlnYXRlUmVxdWVzdGVkKGRlc3RpbmF0aW9uKSB9CisgICAgfQorICAgIGNv
bnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudDsg
YW5jaG9ycy5tYXJnaW5zOiAyMDsgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCisgICAgICAgIFJv
d0xheW91dCB7CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisgICAgICAgICAg
ICBMYWJlbCB7IHRleHQ6IHFzVHIoIkVjbGlwc2Ug4oCiIENvbnRyb2wgY2VudGVyIik7IGNvbG9y
OiBWYlRva2Vucy50ZXh0OyBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udERpc3BsYXk7IGZvbnQu
cGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZSB9Cisg
ICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiQ2xvc2UiKTsgb25D
bGlja2VkOiBwYW5lbC5jbG9zZSgpIH0KKyAgICAgICAgfQorICAgICAgICBTY3JvbGxWaWV3IHsK
KyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7IExheW91dC5maWxsSGVpZ2h0OiB0
cnVlCisgICAgICAgICAgICBjbGlwOiB0cnVlOyBjb250ZW50V2lkdGg6IGF2YWlsYWJsZVdpZHRo
CisgICAgICAgICAgICBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgICAgIHdpZHRoOiBwYXJl
bnQud2lkdGg7IHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMworICAgICAgICAgICAgICAgIExhYmVs
IHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHdy
YXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IENyaW1zb25TdGF0dXMubG9jYWwubmV0d29yayB8fCBx
c1RyKCJOZXR3b3JrIHVuYXZhaWxhYmxlIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAg
ICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHRleHQ6IENyaW1z
b25TdGF0dXMubG9jYWwuYmF0dGVyeVBlcmNlbnQgPj0gMCA/IHFzVHIoIkJhdHRlcnkgJTElIOKA
oiAlMiIpLmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50KS5hcmcoQ3JpbXNv
blN0YXR1cy5sb2NhbC5iYXR0ZXJ5U3RhdGUpIDogcXNUcigiQmF0dGVyeSB1bmF2YWlsYWJsZSIp
OyBjb2xvcjogVmJUb2tlbnMudGV4dERpbTsgd3JhcE1vZGU6IFRleHQuV3JhcCB9CisgICAgICAg
ICAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1
dHRvbiB7IHRleHQ6IHFzVHIoIldpLUZpIik7IGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29u
LW5ldHdvcmsuc3ZnIjsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigid2lmaSIpIH0KKyAgICAgICAg
ICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIkJsdWV0b290aCIp
OyBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnIjsgb25DbGlja2Vk
OiBwYW5lbC5kZWZlcigiYnQiKSB9CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAg
IExhYmVsIHsgdGV4dDogcXNUcigiQXVkaW8iKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQu
Ym9sZDogdHJ1ZSB9CisgICAgICAgICAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgICAg
ICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQorICAgICAgICAgICAgICAgICAgICBTbGlkZXIg
eworICAgICAgICAgICAgICAgICAgICAgICAgaWQ6IHZvbHVtZVNsaWRlcgorICAgICAgICAgICAg
ICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgZnJvbTogMDsgdG86IDEwMDsgc3Rl
cFNpemU6IDEKKyAgICAgICAgICAgICAgICAgICAgICAgIHZhbHVlOiBTeXN0ZW1Db250cm9scy5z
dGF0ZS52b2x1bWUgPT09IHVuZGVmaW5lZCB8fCBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUg
PT09IG51bGwgPyAwIDogU3lzdGVtQ29udHJvbHMuc3RhdGUudm9sdW1lCisgICAgICAgICAgICAg
ICAgICAgICAgICBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBTeXN0ZW1Db250cm9s
cy5zdGF0ZS52b2x1bWUgIT09IHVuZGVmaW5lZCAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1
bWUgIT09IG51bGwKKyAgICAgICAgICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNU
cigiU3BlYWtlciB2b2x1bWUiKQorICAgICAgICAgICAgICAgICAgICAgICAgb25Nb3ZlZDogaWYg
KCFwcmVzc2VkICYmIGVuYWJsZWQpIFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci12b2x1
bWUiLCBTdHJpbmcoTWF0aC5yb3VuZCh2YWx1ZSkpKQorICAgICAgICAgICAgICAgICAgICAgICAg
b25QcmVzc2VkQ2hhbmdlZDogaWYgKCFwcmVzc2VkICYmIGVuYWJsZWQpIFN5c3RlbUNvbnRyb2xz
LnJlcXVlc3QoImNlbnRlci12b2x1bWUiLCBTdHJpbmcoTWF0aC5yb3VuZCh2YWx1ZSkpKQorICAg
ICAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgICAgIExhYmVsIHsgaWQ6IHZvbHVt
ZVJlYWRvdXQ7IHRleHQ6IE1hdGgucm91bmQodm9sdW1lU2xpZGVyLnZhbHVlKSsiJSI7IGNvbG9y
OiBWYlRva2Vucy50ZXh0IH0KKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRv
biB7IHRleHQ6IFN5c3RlbUNvbnRyb2xzLnN0YXRlLm11dGVkID8gcXNUcigiVW5tdXRlIikgOiBx
c1RyKCJNdXRlIik7IGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5ICYmIFN5c3RlbUNvbnRy
b2xzLnN0YXRlLnZvbHVtZSAhPT0gbnVsbCAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUg
IT09IHVuZGVmaW5lZDsgb25DbGlja2VkOiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXIt
bXV0ZSIpIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgRWNsaXBzZUNvbWJv
Qm94IHsKKyAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQorICAgICAg
ICAgICAgICAgICAgICBtb2RlbDogU3lzdGVtQ29udHJvbHMuc3RhdGUuc2lua3MgfHwgW107IHRl
eHRSb2xlOiAibmFtZSIKKyAgICAgICAgICAgICAgICAgICAgZW5hYmxlZDogIVN5c3RlbUNvbnRy
b2xzLmJ1c3kgJiYgY291bnQgPiAwCisgICAgICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFt
ZTogcXNUcigiQXVkaW8gb3V0cHV0IikKKyAgICAgICAgICAgICAgICAgICAgY3VycmVudEluZGV4
OiB7IHZhciBsaXN0ID0gU3lzdGVtQ29udHJvbHMuc3RhdGUuc2lua3MgfHwgW107IGZvciAodmFy
IGk9MDtpPGxpc3QubGVuZ3RoO2krKykgaWYgKGxpc3RbaV0uZGVmYXVsdCkgcmV0dXJuIGk7IHJl
dHVybiAtMSB9CisgICAgICAgICAgICAgICAgICAgIGNvbnRlbnRJdGVtOiBMYWJlbCB7IHRleHQ6
IHBhcmVudC5kaXNwbGF5VGV4dDsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IGNvbG9yOiBW
YlRva2Vucy50ZXh0OyB2ZXJ0aWNhbEFsaWdubWVudDogVGV4dC5BbGlnblZDZW50ZXI7IGVsaWRl
OiBUZXh0LkVsaWRlUmlnaHQgfQorICAgICAgICAgICAgICAgICAgICBkZWxlZ2F0ZTogSXRlbURl
bGVnYXRlIHsgd2lkdGg6IHBhcmVudC53aWR0aDsgY29udGVudEl0ZW06IExhYmVsIHsgdGV4dDog
bW9kZWxEYXRhLm5hbWU7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyBjb2xvcjogVmJUb2tl
bnMudGV4dDsgZWxpZGU6IFRleHQuRWxpZGVSaWdodCB9IH0KKyAgICAgICAgICAgICAgICAgICAg
b25BY3RpdmF0ZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci1vdXRwdXQiLCBtb2Rl
bFtpbmRleF0uaWQpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIFJlcGVhdGVy
IHsKKyAgICAgICAgICAgICAgICAgICAgbW9kZWw6IFt7a2luZDoic2NyZWVuIixsYWJlbDpxc1Ry
KCJTY3JlZW4gYnJpZ2h0bmVzcyIpfSx7a2luZDoia2V5Ym9hcmQiLGxhYmVsOnFzVHIoIktleWJv
YXJkIGJyaWdodG5lc3MiKX1dCisgICAgICAgICAgICAgICAgICAgIGRlbGVnYXRlOiBDb2x1bW5M
YXlvdXQgeworICAgICAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQor
ICAgICAgICAgICAgICAgICAgICAgICAgcHJvcGVydHkgdmFyIGhhcmR3YXJlOiAoU3lzdGVtQ29u
dHJvbHMuc3RhdGUuYnJpZ2h0bmVzcyB8fCB7fSlbbW9kZWxEYXRhLmtpbmRdCisgICAgICAgICAg
ICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IG1vZGVsRGF0YS5sYWJlbCArIChoYXJkd2FyZSA/
ICIg4oCiICIgKyBoYXJkd2FyZS5wZXJjZW50ICsgIiUiIDogIiDigKIgIiArIHFzVHIoIlVuYXZh
aWxhYmxlIikpOyBjb2xvcjogVmJUb2tlbnMudGV4dCB9CisgICAgICAgICAgICAgICAgICAgICAg
ICBTbGlkZXIgeworICAgICAgICAgICAgICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6
IHRydWU7IGZyb206IG1vZGVsRGF0YS5raW5kID09PSAic2NyZWVuIiA/IDUgOiAwOyB0bzogMTAw
OyBzdGVwU2l6ZTogMQorICAgICAgICAgICAgICAgICAgICAgICAgICAgIHZhbHVlOiBoYXJkd2Fy
ZSA/IGhhcmR3YXJlLnBlcmNlbnQgOiAwOyBlbmFibGVkOiAhIWhhcmR3YXJlICYmICFTeXN0ZW1D
b250cm9scy5idXN5CisgICAgICAgICAgICAgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1l
OiBtb2RlbERhdGEubGFiZWwKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICBvbk1vdmVkOiBp
ZiAoIXByZXNzZWQgJiYgZW5hYmxlZCkgU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLSIr
bW9kZWxEYXRhLmtpbmQsIFN0cmluZyhNYXRoLnJvdW5kKHZhbHVlKSkpCisgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgb25QcmVzc2VkQ2hhbmdlZDogaWYgKCFwcmVzc2VkICYmIGVuYWJsZWQp
IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci0iK21vZGVsRGF0YS5raW5kLCBTdHJpbmco
TWF0aC5yb3VuZCh2YWx1ZSkpKQorICAgICAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAg
ICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEVjbGlwc2VB
Y3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJSZWZyZXNoIGNvbnRyb2xzIik7IGVuYWJsZWQ6ICFT
eXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNl
bnRlci1saXN0IikgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogcXNUcigiSG9zdCIp
OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAgICAgICAgICAgICAg
ICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5U
ZXh0OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBwYW5lbC5ob3N0LnVybCB8fCBxc1RyKCJT
ZWxlY3QgYSBob3N0IGluIHRoZSBsYXVuY2hlci4iKTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0g
fQorICAgICAgICAgICAgICAgIFJvd0xheW91dCB7CisgICAgICAgICAgICAgICAgICAgIEVjbGlw
c2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJIb3N0IHN0YXRzIik7IGVuYWJsZWQ6ICEhcGFu
ZWwuaG9zdC5pZDsgaWNvblNvdXJjZTogInFyYzovcmVzL2NyaW1zb24taG9zdC5zdmciOyBvbkNs
aWNrZWQ6IHBhbmVsLmRlZmVyKCJob3N0IikgfQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNl
QWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiV2FrZSBob3N0Iik7IGVuYWJsZWQ6ICEhcGFuZWwu
aG9zdC5pZCAmJiBwYW5lbC5jYW5XYWtlOyBvbkNsaWNrZWQ6IHsgcGFuZWwud2FrZVJlcXVlc3Rl
ZCgpOyBwYW5lbC5tZXNzYWdlID0gcXNUcigiV2FrZSByZXF1ZXN0IHNlbnQ7IHRoZSBob3N0IG11
c3Qgc3VwcG9ydCBXYWtlLW9uLUxBTi4iKSB9IH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAg
ICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIk9wZW4gaG9zdCBtYW5h
Z2VtZW50Iik7IGVuYWJsZWQ6ICEhcGFuZWwuaG9zdC51cmwgJiYgcGFuZWwuY2FuTWFuYWdlOyBv
bkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJtYW5hZ2VtZW50IikgfQorICAgICAgICAgICAgICAgIExh
YmVsIHsgdGV4dDogcXNUcigiU3RyZWFtIHByb2ZpbGVzIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0
OyBmb250LmJvbGQ6IHRydWUgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxX
aWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcGFuZWwuaG9zdC5pZCA/IHFz
VHIoIlNhdmVkIGZvciB0aGUgc2VsZWN0ZWQgaG9zdC4gQXBwbHkgYmVmb3JlIHN0YXJ0aW5nIGEg
c3RyZWFtLiIpIDogcXNUcigiR2xvYmFsIHByb2ZpbGVzLiBBcHBseSBiZWZvcmUgc3RhcnRpbmcg
YSBzdHJlYW0uIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICBF
Y2xpcHNlQ29tYm9Cb3ggeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBtb2RlbDogcGFuZWwuc2F2
ZWROYW1lczsgdmlzaWJsZTogY291bnQgPiAwOyBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIlNhdmVk
IHByb2ZpbGVzIik7IG9uQWN0aXZhdGVkOiBwcm9maWxlTmFtZS50ZXh0ID0gbW9kZWxbaW5kZXhd
IH0KKyAgICAgICAgICAgICAgICBUZXh0RmllbGQgeyBpZDogcHJvZmlsZU5hbWU7IExheW91dC5m
aWxsV2lkdGg6IHRydWU7IG1heGltdW1MZW5ndGg6IDQ4OyBwbGFjZWhvbGRlclRleHQ6IHFzVHIo
IlByb2ZpbGUgbmFtZSIpOyBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIlByb2ZpbGUgbmFtZSIpIH0K
KyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAgICAgICBFY2xpcHNl
QWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiU2F2ZSBjdXJyZW50Iik7IG9uQ2xpY2tlZDogeyBw
YW5lbC5tZXNzYWdlID0gRWNsaXBzZVByb2ZpbGVzLnNhdmUocGFuZWwuaG9zdC5pZCB8fCAiIiwg
cHJvZmlsZU5hbWUudGV4dCwge3dpZHRoOlN0cmVhbWluZ1ByZWZlcmVuY2VzLndpZHRoLGhlaWdo
dDpTdHJlYW1pbmdQcmVmZXJlbmNlcy5oZWlnaHQsZnBzOlN0cmVhbWluZ1ByZWZlcmVuY2VzLmZw
cyxiaXRyYXRlS2JwczpTdHJlYW1pbmdQcmVmZXJlbmNlcy5iaXRyYXRlS2Jwc30pID8gcXNUcigi
UHJvZmlsZSBzYXZlZC4iKSA6IHFzVHIoIlByb2ZpbGUgY291bGQgbm90IGJlIHNhdmVkLiIpOyBw
YW5lbC5zYXZlZE5hbWVzID0gRWNsaXBzZVByb2ZpbGVzLm5hbWVzKHBhbmVsLmhvc3QuaWQgfHwg
IiIpIH0gfQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDog
cXNUcigiQXBwbHkgc2F2ZWQiKTsgb25DbGlja2VkOiBwYW5lbC5hcHBseShFY2xpcHNlUHJvZmls
ZXMubG9hZChwYW5lbC5ob3N0LmlkIHx8ICIiLCBwcm9maWxlTmFtZS50ZXh0KSkgfQorICAgICAg
ICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiRGVza3RvcCBwcmVzZXQiKTsg
b25DbGlja2VkOiBwYW5lbC5hcHBseSh7d2lkdGg6MTI4MCxoZWlnaHQ6ODAwLGZwczo2MCxiaXRy
YXRlS2JwczoxNTAwMH0pIH0KKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRv
biB7IHRleHQ6IHFzVHIoIkxvdyBiYW5kd2lkdGgiKTsgb25DbGlja2VkOiBwYW5lbC5hcHBseSh7
d2lkdGg6MTI4MCxoZWlnaHQ6NzIwLGZwczozMCxiaXRyYXRlS2Jwczo1MDAwfSkgfQorICAgICAg
ICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIkFwcGVhcmFu
Y2UgJiBhY2Nlc3NpYmlsaXR5Iik7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmJvbGQ6IHRy
dWUgfQorICAgICAgICAgICAgICAgIEVjbGlwc2VDb21ib0JveCB7CisgICAgICAgICAgICAgICAg
ICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7IG1vZGVsOiBbcXNUcigiVGV4dCAxMDAlIikscXNU
cigiVGV4dCAxMTAlIikscXNUcigiVGV4dCAxMjUlIildCisgICAgICAgICAgICAgICAgICAgIEFj
Y2Vzc2libGUubmFtZTogcXNUcigiVGV4dCBzaXplIikKKyAgICAgICAgICAgICAgICAgICAgY3Vy
cmVudEluZGV4OiBFY2xpcHNlUHJvZmlsZXMudGV4dFNjYWxlID09PSAxMjUgPyAyIDogRWNsaXBz
ZVByb2ZpbGVzLnRleHRTY2FsZSA9PT0gMTEwID8gMSA6IDAKKyAgICAgICAgICAgICAgICAgICAg
b25BY3RpdmF0ZWQ6IEVjbGlwc2VQcm9maWxlcy50ZXh0U2NhbGUgPSBbMTAwLDExMCwxMjVdW2lu
ZGV4XQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBTd2l0Y2ggeyB0ZXh0OiBx
c1RyKCJSZWR1Y2UgbW90aW9uIik7IGNoZWNrZWQ6IEVjbGlwc2VQcm9maWxlcy5yZWR1Y2VkTW90
aW9uOyBvblRvZ2dsZWQ6IEVjbGlwc2VQcm9maWxlcy5yZWR1Y2VkTW90aW9uID0gY2hlY2tlZCB9
CisgICAgICAgICAgICAgICAgU3dpdGNoIHsgdGV4dDogcXNUcigiSGlnaGVyIGNvbnRyYXN0Iik7
IGNoZWNrZWQ6IEVjbGlwc2VQcm9maWxlcy5oaWdoQ29udHJhc3Q7IG9uVG9nZ2xlZDogRWNsaXBz
ZVByb2ZpbGVzLmhpZ2hDb250cmFzdCA9IGNoZWNrZWQgfQorICAgICAgICAgICAgICAgIExhYmVs
IHsgdGV4dDogcXNUcigiVG9vbHMgJiByZWNvdmVyeSIpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsg
Zm9udC5ib2xkOiB0cnVlIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAg
ICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiQWxsIHNldHRpbmdz
Iik7IGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9zZXR0aW5ncy5zdmciOyBvbkNsaWNrZWQ6IHBhbmVs
LmRlZmVyKCJzZXR0aW5ncyIpIH0KKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1
dHRvbiB7IHRleHQ6IHFzVHIoIlN1cHBvcnQgcmVwb3J0Iik7IGVuYWJsZWQ6ICFTeXN0ZW1Db250
cm9scy5idXN5OyBvbkNsaWNrZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci1yZXBv
cnQiKSB9CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0
LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcXNUcigiUmVjb3Zl
cnk6IEN0cmwrQWx0K0YyIG9wZW5zIHRoZSBkaWFnbm9zdGljIGNvbnNvbGUuIE1hYyBicmlnaHRu
ZXNzLCBrZXlib2FyZC1saWdodCBhbmQgdm9sdW1lIGtleXMgcmVtYWluIGF2YWlsYWJsZS4iKTsg
Y29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgICAgIFJvd0xheW91dCB7Cisg
ICAgICAgICAgICAgICAgICAgIFJlcGVhdGVyIHsKKyAgICAgICAgICAgICAgICAgICAgICAgIG1v
ZGVsOiBbe2FjdGlvbjoicmVib290IixsYWJlbDpxc1RyKCJSZXN0YXJ0Iil9LHthY3Rpb246InBv
d2Vyb2ZmIixsYWJlbDpxc1RyKCJTaHV0IGRvd24iKX1dCisgICAgICAgICAgICAgICAgICAgICAg
ICBkZWxlZ2F0ZTogRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IG1vZGVsRGF0YS5sYWJlbDsg
aWNvblNvdXJjZTogInFyYzovcmVzL2VjbGlwc2UtcG93ZXIuc3ZnIjsgZW5hYmxlZDogIVN5c3Rl
bUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogeyBwYW5lbC5wb3dlckFjdGlvbiA9IG1vZGVsRGF0
YS5hY3Rpb247IHBvd2VyRGlhbG9nLm9wZW4oKSB9IH0KKyAgICAgICAgICAgICAgICAgICAgfQor
ICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsg
dGV4dDogcXNUcigiQWJvdXQgRWNsaXBzZSIpOyBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVz
eTsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigiYWJvdXQiKSB9CisgICAgICAgICAgICAgICAgTGFi
ZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsg
d3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcGFuZWwubWVzc2FnZSB8fCBTeXN0ZW1Db250cm9s
cy5zdGF0dXM7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICBCdXN5
SW5kaWNhdG9yIHsgcnVubmluZzogU3lzdGVtQ29udHJvbHMuYnVzeTsgdmlzaWJsZTogcnVubmlu
ZzsgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25IQ2VudGVyIH0KKyAgICAgICAgICAgIH0KKyAg
ICAgICAgfQorICAgIH0KKyAgICBOYXZpZ2FibGVEaWFsb2cgeworICAgICAgICBpZDogcG93ZXJE
aWFsb2cKKyAgICAgICAgd2lkdGg6IE1hdGgubWluKDQ0MCwgcGFuZWwud2lkdGggLSAzMikKKyAg
ICAgICAgdGl0bGU6IHBhbmVsLnBvd2VyQWN0aW9uID09PSAicmVib290IiA/IHFzVHIoIlJlc3Rh
cnQgRWNsaXBzZU9TPyIpIDogcXNUcigiU2h1dCBkb3duIEVjbGlwc2VPUz8iKQorICAgICAgICBz
dGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5ZZXMgfCBEaWFsb2cuTm8KKyAgICAgICAgTWF0ZXJpYWwu
YmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgICAgIG9uQWNjZXB0ZWQ6IFN5c3RlbUNv
bnRyb2xzLnJlcXVlc3QoImNlbnRlci0iK3BhbmVsLnBvd2VyQWN0aW9uLCIiLHRydWUpCisgICAg
ICAgIGNvbnRlbnRJdGVtOiBMYWJlbCB7IHRleHQ6IHFzVHIoIlRoaXMgZW5kcyB0aGUgY3VycmVu
dCBsb2NhbCBzZXNzaW9uLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dCB9CisgICAgfQorfQpkaWZm
IC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlSGFyZHdhcmVNb25pdG9yLnFtbCBiL2FwcC9ndWkvRWNs
aXBzZUhhcmR3YXJlTW9uaXRvci5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAw
MC4uZWRiZTE5MQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNsaXBzZUhhcmR3YXJlTW9u
aXRvci5xbWwKQEAgLTAsMCArMSw3NyBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRR
dWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkxheW91dHMgMS4zCitpbXBvcnQgVmli
ZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBMb2NhbEhhcmR3YXJlIDEuMAorCitDb2x1bW5MYXlv
dXQgeworICAgIGlkOiBtb25pdG9yCisgICAgb2JqZWN0TmFtZToiaGFyZHdhcmVNb25pdG9yIgor
ICAgIHByb3BlcnR5IGJvb2wgYWN0aXZlOiBmYWxzZQorICAgIENvbXBvbmVudC5vbkNvbXBsZXRl
ZDogaWYoYWN0aXZlKSBMb2NhbEhhcmR3YXJlLnNldENvbnN1bWVyQWN0aXZlKG1vbml0b3IsdHJ1
ZSkKKyAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisgICAgb25BY3RpdmVDaGFuZ2VkOiBMb2Nh
bEhhcmR3YXJlLnNldENvbnN1bWVyQWN0aXZlKG1vbml0b3IsYWN0aXZlKQorICAgIENvbXBvbmVu
dC5vbkRlc3RydWN0aW9uOiBMb2NhbEhhcmR3YXJlLnNldENvbnN1bWVyQWN0aXZlKG1vbml0b3Is
ZmFsc2UpCisgICAgZnVuY3Rpb24gcmVhZGluZyhrZXksIHN1ZmZpeCwgZGlnaXRzKSB7IHZhciB2
PUxvY2FsSGFyZHdhcmUucmVhZGluZ3Nba2V5XTsgcmV0dXJuIHYgPT09IHVuZGVmaW5lZCA/IHFz
VHIoIlVuYXZhaWxhYmxlIikgOiBOdW1iZXIodikudG9GaXhlZChkaWdpdHMgPT09IHVuZGVmaW5l
ZCA/IDEgOiBkaWdpdHMpKyhzdWZmaXggfHwgIiIpIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5
OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4
dDogcXNUcigiTE9DQUwgTUFDIOKAoiBIYXJkd2FyZSBtb25pdG9yIik7IGNvbG9yOiBWYlRva2Vu
cy50ZXh0OyBmb250LmJvbGQ6IHRydWUgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tl
bnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmls
bFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJMb2NhbCByZWFk
aW5ncyBhcmUgaW5kZXBlbmRlbnQgb2Ygc3RyZWFtIGFuZCBob3N0IHN0YXRpc3RpY3MuIE1pc3Np
bmcgc2Vuc29ycyBzaG93IFVuYXZhaWxhYmxlOyBmaXJzdCBDUFUvbmV0d29yayByYXRlcyBuZWVk
IGEgc2Vjb25kIHNhbXBsZS4gSW50ZWwgR1BVIHNoYXJlZCBtZW1vcnkgaXMgc3lzdGVtIFJBTS4i
KTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgIEdyaWRMYXlvdXQgeworICAgICAgICBM
YXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBjb2x1bW5zOiB3aWR0aCA+PSA2MjAgPyAyIDogMTsgY29s
dW1uU3BhY2luZzogVmJUb2tlbnMuc3BhY2UzOyByb3dTcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMK
KyAgICAgICAgUmVwZWF0ZXIgeworICAgICAgICAgICAgbW9kZWw6IFsKKyAgICAgICAgICAgICAg
ICB7bGFiZWw6cXNUcigiQ1BVIiksIGtleToiY3B1UGVyY2VudCIsc3VmZml4OiIlIn0sIHtsYWJl
bDpxc1RyKCJDUFUgY2xvY2siKSxrZXk6ImNwdU1IeiIsc3VmZml4OiIgTUh6In0sCisgICAgICAg
ICAgICAgICAge2xhYmVsOnFzVHIoIk1lbW9yeSB1c2VkIiksa2V5OiJtZW1vcnlVc2VkR2lCIixz
dWZmaXg6IiBHaUIifSx7bGFiZWw6cXNUcigiTWVtb3J5IHRvdGFsIiksa2V5OiJtZW1vcnlUb3Rh
bEdpQiIsc3VmZml4OiIgR2lCIn0sCisgICAgICAgICAgICAgICAge2xhYmVsOnFzVHIoIkNQVSB0
ZW1wZXJhdHVyZSIpLGtleToidGVtcGVyYXR1cmVDIixzdWZmaXg6IiDCsEMifSx7bGFiZWw6cXNU
cigiRmFuIiksa2V5OiJmYW5SUE0iLHN1ZmZpeDoiIFJQTSJ9LAorICAgICAgICAgICAgICAgIHts
YWJlbDpxc1RyKCJHUFUgYnVzeSIpLGtleToiZ3B1UGVyY2VudCIsc3VmZml4OiIlIn0se2xhYmVs
OnFzVHIoIkVjbGlwc2UgdmlkZW8gZW5naW5lIiksa2V5OiJ2aWRlb1BlcmNlbnQiLHN1ZmZpeDoi
JSJ9LHtsYWJlbDpxc1RyKCJTd2FwIHVzZWQiKSxrZXk6InN3YXBVc2VkTWlCIixzdWZmaXg6IiBN
aUIifSwKKyAgICAgICAgICAgICAgICB7bGFiZWw6cXNUcigiTmV0d29yayBkb3dubG9hZCIpLGtl
eToicmVjZWl2ZU1pQiIsc3VmZml4OiIgTWlCL3MifSx7bGFiZWw6cXNUcigiTmV0d29yayB1cGxv
YWQiKSxrZXk6InRyYW5zbWl0TWlCIixzdWZmaXg6IiBNaUIvcyJ9LAorICAgICAgICAgICAgICAg
IHtsYWJlbDpxc1RyKCJTdG9yYWdlIHJlYWRzIiksa2V5OiJkaXNrUmVhZE1pQiIsc3VmZml4OiIg
TWlCL3MifSx7bGFiZWw6cXNUcigiU3RvcmFnZSB3cml0ZXMiKSxrZXk6ImRpc2tXcml0ZU1pQiIs
c3VmZml4OiIgTWlCL3MifSwKKyAgICAgICAgICAgICAgICB7bGFiZWw6cXNUcigiVVNCL3Jvb3Qg
ZnJlZSIpLGtleToic3RvcmFnZUZyZWVHaUIiLHN1ZmZpeDoiIEdpQiJ9LHtsYWJlbDpxc1RyKCJC
YXR0ZXJ5Iiksa2V5OiJiYXR0ZXJ5UGVyY2VudCIsc3VmZml4OiIlIn0KKyAgICAgICAgICAgIF0K
KyAgICAgICAgICAgIGRlbGVnYXRlOiBDcmltc29uR2xhc3NQYW5lbCB7CisgICAgICAgICAgICAg
ICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgaW1wbGljaXRIZWlnaHQ6IDg0OyByYWRpdXM6IFZi
VG9rZW5zLnJhZGl1c0NhcmQ7IGNvbG9yOiBWYlRva2Vucy5iZ0VsZXY7IGJvcmRlci5jb2xvcjog
VmJUb2tlbnMuc3Ryb2tlCisgICAgICAgICAgICAgICAgQ29sdW1uIHsgYW5jaG9ycy5maWxsOiBw
YXJlbnQ7IGFuY2hvcnMubWFyZ2luczogMTI7IHNwYWNpbmc6IDYKKyAgICAgICAgICAgICAgICAg
ICAgTGFiZWwgeyB0ZXh0OiBtb2RlbERhdGEubGFiZWw7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGlt
OyBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUJvZHkgfQorICAgICAgICAgICAgICAgICAg
ICBMYWJlbCB7IHRleHQ6IG1vbml0b3IucmVhZGluZyhtb2RlbERhdGEua2V5LG1vZGVsRGF0YS5z
dWZmaXgpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlOyBmb250LnBpeGVs
U2l6ZTogVmJUb2tlbnMudHlwZUJvZHkgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAg
IH0KKyAgICAgICAgfQorICAgIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZv
bnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigiUmVj
ZW50IENQVSBhbmQgUkFNIHVzYWdlIOKAoiB1cCB0byA2MCBzYW1wbGVzIik7IGNvbG9yOiBWYlRv
a2Vucy50ZXh0RGltIH0KKyAgICBDYW52YXMgeworICAgICAgICBpZDogZ3JhcGg7IExheW91dC5m
aWxsV2lkdGg6IHRydWU7IGltcGxpY2l0SGVpZ2h0OiAxMDAKKyAgICAgICAgb25QYWludDogewor
ICAgICAgICAgICAgdmFyIGM9Z2V0Q29udGV4dCgiMmQiKTsgYy5jbGVhclJlY3QoMCwwLHdpZHRo
LGhlaWdodCk7IGMuZmlsbFN0eWxlPVZiVG9rZW5zLmJnRWxldjsgYy5maWxsUmVjdCgwLDAsd2lk
dGgsaGVpZ2h0KQorICAgICAgICAgICAgdmFyIGtleXM9WyJjcHVQZXJjZW50IiwibWVtb3J5UGVy
Y2VudCJdLCBjb2xvcnM9W1ZiVG9rZW5zLmFjY2VudCxWYlRva2Vucy50ZXh0RGltXSwgaD1Mb2Nh
bEhhcmR3YXJlLmhpc3RvcnkKKyAgICAgICAgICAgIGZvcih2YXIgaz0wO2s8a2V5cy5sZW5ndGg7
aysrKSB7IGMuc3Ryb2tlU3R5bGU9Y29sb3JzW2tdOyBjLmxpbmVXaWR0aD0yOyBjLmJlZ2luUGF0
aCgpOyB2YXIgc3RhcnRlZD1mYWxzZQorICAgICAgICAgICAgICAgIGZvcih2YXIgaT0wO2k8aC5s
ZW5ndGg7aSsrKSB7IHZhciB2PWhbaV1ba2V5c1trXV07IGlmKHY9PT11bmRlZmluZWQpIHsgc3Rh
cnRlZD1mYWxzZTsgY29udGludWUgfQorICAgICAgICAgICAgICAgICAgICB2YXIgeD13aWR0aCpp
LzU5LCB5PWhlaWdodC00LShoZWlnaHQtOCkqTWF0aC5tYXgoMCxNYXRoLm1pbigxMDAsdikpLzEw
MAorICAgICAgICAgICAgICAgICAgICBpZighc3RhcnRlZCkgYy5tb3ZlVG8oeCx5KTsgZWxzZSBj
LmxpbmVUbyh4LHkpOyBzdGFydGVkPXRydWUgfQorICAgICAgICAgICAgICAgIGMuc3Ryb2tlKCkg
fQorICAgICAgICB9CisgICAgICAgIENvbm5lY3Rpb25zIHsgdGFyZ2V0OiBMb2NhbEhhcmR3YXJl
OyBmdW5jdGlvbiBvbkNoYW5nZWQoKSB7IGdyYXBoLnJlcXVlc3RQYWludCgpIH0gfQorICAgICAg
ICBDb25uZWN0aW9ucyB7IHRhcmdldDogVmJUb2tlbnM7IGZ1bmN0aW9uIG9uQWNjZW50Q2hhbmdl
ZCgpIHsgZ3JhcGgucmVxdWVzdFBhaW50KCkgfSB9CisgICAgfQorICAgIENoZWNrQm94IHsgZm9u
dC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVC
b2R5OyB0ZXh0OiBxc1RyKCJTaG93IGxvY2FsIGhhcmR3YXJlIG92ZXJsYXkgZHVyaW5nIHN0cmVh
bWluZyIpOyBjaGVja2VkOiBMb2NhbEhhcmR3YXJlLm92ZXJsYXk7IG9uVG9nZ2xlZDogTG9jYWxI
YXJkd2FyZS5vdmVybGF5PWNoZWNrZWQgfQorICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJU
b2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OiBx
c1RyKCJEZXRhaWxlZCBsb2NhbCBvdmVybGF5Iik7IGNoZWNrZWQ6IExvY2FsSGFyZHdhcmUuZGV0
YWlsZWQ7IG9uVG9nZ2xlZDogTG9jYWxIYXJkd2FyZS5kZXRhaWxlZD1jaGVja2VkIH0KKyAgICBD
aGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpW
YlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigiRGV0YWlsZWQgc3RyZWFtIHN0YXRpc3RpY3Mi
KTsgY2hlY2tlZDogTG9jYWxIYXJkd2FyZS5zdHJlYW1EZXRhaWxlZDsgb25Ub2dnbGVkOiBMb2Nh
bEhhcmR3YXJlLnN0cmVhbURldGFpbGVkPWNoZWNrZWQgfQorICAgIFJvd0xheW91dCB7CisgICAg
ICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXpl
OlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OiBxc1RyKCJMb2NhbCBvdmVybGF5IGNvcm5lciIpOyBj
b2xvcjogVmJUb2tlbnMudGV4dCB9CisgICAgICAgIEVjbGlwc2VDb21ib0JveCB7IExheW91dC5m
aWxsV2lkdGg6dHJ1ZTsgbW9kZWw6W3FzVHIoIlRvcCBsZWZ0IikscXNUcigiVG9wIHJpZ2h0Iiks
cXNUcigiQm90dG9tIGxlZnQiKSxxc1RyKCJCb3R0b20gcmlnaHQiKV07IGN1cnJlbnRJbmRleDpM
b2NhbEhhcmR3YXJlLnBvc2l0aW9uOyBvbkFjdGl2YXRlZDpMb2NhbEhhcmR3YXJlLnBvc2l0aW9u
PWluZGV4IH0KKyAgICB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9k
eTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6dHJ1
ZTsgd3JhcE1vZGU6VGV4dC5XcmFwOyB0ZXh0OnFzVHIoIklmIGJvdGggb3ZlcmxheXMgdXNlIHRo
ZSBzYW1lIGNvcm5lciwgTG9jYWwgTWFjIG1vdmVzIHRvIHRoZSBvcHBvc2l0ZSBob3Jpem9udGFs
IGNvcm5lci4gU3RyZWFtaW5nIHNob3J0Y3V0czogQ3RybCtBbHQrU2hpZnQrUyBmb3Igc3RyZWFt
IHN0YXRzOyBDdHJsK0FsdCtTaGlmdCtIIGZvciBsb2NhbCBoYXJkd2FyZS4gU3RyZWFtIHRleHQg
c2l6ZSBhbmQgY29ybmVyIHJlbWFpbiBpbiBWaWRlbyBzZXR0aW5ncy4iKTsgY29sb3I6VmJUb2tl
bnMudGV4dERpbSB9CisgICAgUm93TGF5b3V0IHsKKyAgICAgICAgTGFiZWwgeyBmb250LmZhbWls
eTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRl
eHQ6cXNUcigiUGFuZWwgb3BhY2l0eSIpOyBjb2xvcjpWYlRva2Vucy50ZXh0IH0KKyAgICAgICAg
U2xpZGVyIHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlOyBmcm9tOjQwO3RvOjEwMDtzdGVwU2l6ZTo1
O3ZhbHVlOkxvY2FsSGFyZHdhcmUub3BhY2l0eTsgb25Nb3ZlZDpMb2NhbEhhcmR3YXJlLm9wYWNp
dHk9TWF0aC5yb3VuZCh2YWx1ZSkgfQorICAgIH0KKyAgICBSb3dMYXlvdXQgeworICAgICAgICBM
YWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRv
a2Vucy50eXBlQm9keTsgdGV4dDpxc1RyKCJSZWZyZXNoIGludGVydmFsIik7Y29sb3I6VmJUb2tl
bnMudGV4dCB9CisgICAgICAgIEVjbGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1
ZTsgbW9kZWw6WyIxIHNlY29uZCIsIjIgc2Vjb25kcyIsIjUgc2Vjb25kcyJdOyBjdXJyZW50SW5k
ZXg6TG9jYWxIYXJkd2FyZS5yZWZyZXNoU2Vjb25kcz09PTE/MDpMb2NhbEhhcmR3YXJlLnJlZnJl
c2hTZWNvbmRzPT09NT8yOjE7IG9uQWN0aXZhdGVkOkxvY2FsSGFyZHdhcmUucmVmcmVzaFNlY29u
ZHM9WzEsMiw1XVtpbmRleF0gfQorICAgIH0KKyAgICBGbG93IHsKKyAgICAgICAgTGF5b3V0LmZp
bGxXaWR0aDp0cnVlCisgICAgICAgIFJlcGVhdGVyIHsgbW9kZWw6WyJjcHUiLCJtZW1vcnkiLCJ0
ZW1wZXJhdHVyZSIsImdwdSIsIm5ldHdvcmsiLCJiYXR0ZXJ5Iiwic3RvcmFnZSJdCisgICAgICAg
ICAgICBkZWxlZ2F0ZTpDaGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBm
b250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDptb2RlbERhdGE7IGNoZWNrZWQ6
TG9jYWxIYXJkd2FyZS5maWVsZHMuaW5kZXhPZihtb2RlbERhdGEpPj0wOyBvblRvZ2dsZWQ6e3Zh
ciBmPUxvY2FsSGFyZHdhcmUuZmllbGRzLnNsaWNlKCk7dmFyIGk9Zi5pbmRleE9mKG1vZGVsRGF0
YSk7aWYoY2hlY2tlZCYmaTwwKWYucHVzaChtb2RlbERhdGEpO2lmKCFjaGVja2VkJiZpPj0wKWYu
c3BsaWNlKGksMSk7TG9jYWxIYXJkd2FyZS5maWVsZHM9Zn0gfQorICAgICAgICB9CisgICAgfQor
ICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXpl
OlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5X
cmFwO3RleHQ6cXNUcigiRWNsaXBzZSB2aWRlby1lbmdpbmUgYWN0aXZpdHkgdXNlcyB0aGlzIHBy
b2Nlc3PigJlzIERSTSBjb3VudGVycyB3aGVuIGV4cG9zZWQuIEl0IGlzIG5vdCB3aG9sZS1zeXN0
ZW0gR1BVIGxvYWQuIFBlci1wcm9jZXNzIEdQVSBtZW1vcnkgaXMgdW5hdmFpbGFibGUuIFN0b3Jh
Z2UgcmF0ZXMgcmVmbGVjdCB0aGUgYWN0aXZlIHJvb3QgZGV2aWNlIHdoZW4gYWNjZXNzaWJsZS4g
Tm8gcHJpdmlsZWdlZCBHUFUgcHJvZmlsZXIgcnVucyBjb250aW51b3VzbHkuIik7Y29sb3I6VmJU
b2tlbnMudGV4dERpbSB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0VjbGlwc2VTeXN0ZW1TZXR0
aW5ncy5xbWwgYi9hcHAvZ3VpL0VjbGlwc2VTeXN0ZW1TZXR0aW5ncy5xbWwKbmV3IGZpbGUgbW9k
ZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uNWQyYmJjOQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9n
dWkvRWNsaXBzZVN5c3RlbVNldHRpbmdzLnFtbApAQCAtMCwwICsxLDgzIEBACitpbXBvcnQgUXRR
dWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5
b3V0cyAxLjMKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZp
YmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgU3lzdGVtQ29udHJvbHMgMS4wCitpbXBvcnQgTG9j
YWxIYXJkd2FyZSAxLjAKKworQ29sdW1uTGF5b3V0IHsKKyAgICBpZDogc3lzdGVtCisgICAgcHJv
cGVydHkgYm9vbCBhY3RpdmU6IGZhbHNlCisgICAgcHJvcGVydHkgc3RyaW5nIHBvd2VyQWN0aW9u
OiAiIgorICAgIHByb3BlcnR5IHZhciBwb2ludGVyOiBwb2ludGVyQ2hvaWNlLmN1cnJlbnRJbmRl
eCA+PSAwID8gKFN5c3RlbUNvbnRyb2xzLnN0YXRlLnBvaW50ZXJzIHx8IFtdKVtwb2ludGVyQ2hv
aWNlLmN1cnJlbnRJbmRleF0gfHwgKHt9KSA6ICh7fSkKKyAgICBzcGFjaW5nOiBWYlRva2Vucy5z
cGFjZTMKKyAgICBvbkFjdGl2ZUNoYW5nZWQ6IHsgaWYoYWN0aXZlKSBTeXN0ZW1Db250cm9scy5v
cGVuKCJjZW50ZXIiKTsgZWxzZSBTeXN0ZW1Db250cm9scy5jbG9zZSgpIH0KKyAgICBDb21wb25l
bnQub25EZXN0cnVjdGlvbjogeyBpZihhY3RpdmUpIFN5c3RlbUNvbnRyb2xzLmNsb3NlKCkgfQor
ICAgIGZ1bmN0aW9uIHJlcXVlc3QoYWN0aW9uLHZhbHVlKSB7IFN5c3RlbUNvbnRyb2xzLnJlcXVl
c3QoImNlbnRlci0iK2FjdGlvbix2YWx1ZSB8fCAiIikgfQorICAgIGZ1bmN0aW9uIHNob3dDb25u
ZWN0aW9ucyhraW5kKSB7IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCk7IGNvbm5lY3Rpb25zLmtpbmQ9
a2luZDsgY29ubmVjdGlvbnMub3BlbigpIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9r
ZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZp
bGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcDt0ZXh0OnFzVHIoIkVjbGlwc2VPUyDigKIg
U3lzdGVtIENvbnRyb2xzIik7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LmJvbGQ6dHJ1ZSB9Cisg
ICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6
VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0Lldy
YXA7dGV4dDpTeXN0ZW1Db250cm9scy5zdGF0dXM7Y29sb3I6VmJUb2tlbnMudGV4dERpbTt0ZXh0
Rm9ybWF0OlRleHQuUGxhaW5UZXh0IH0KKyAgICBCdXN5SW5kaWNhdG9yIHsgcnVubmluZzpzeXN0
ZW0uYWN0aXZlICYmIFN5c3RlbUNvbnRyb2xzLmJ1c3k7dmlzaWJsZTpydW5uaW5nO0xheW91dC5h
bGlnbm1lbnQ6UXQuQWxpZ25IQ2VudGVyIH0KKyAgICBSb3dMYXlvdXQgeworICAgICAgICBMYXlv
dXQuZmlsbFdpZHRoOnRydWUKKyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNU
cigiV2ktRmkgbmV0d29ya3MiKTtpY29uU291cmNlOiJxcmM6L3Jlcy9jcmltc29uLW5ldHdvcmsu
c3ZnIjtvbkNsaWNrZWQ6c3lzdGVtLnNob3dDb25uZWN0aW9ucygid2lmaSIpIH0KKyAgICAgICAg
RWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiQmx1ZXRvb3RoIGRldmljZXMiKTtpY29u
U291cmNlOiJxcmM6L3Jlcy9jcmltc29uLWJsdWV0b290aC5zdmciO29uQ2xpY2tlZDpzeXN0ZW0u
c2hvd0Nvbm5lY3Rpb25zKCJidCIpIH0KKyAgICB9CisgICAgUm93TGF5b3V0IHsKKyAgICAgICAg
Q2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6
VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiV2ktRmkgcmFkaW8iKTtjaGVja2VkOlN5c3Rl
bUNvbnRyb2xzLnN0YXRlLndpZmlfZW5hYmxlZD09PXRydWU7ZW5hYmxlZDohU3lzdGVtQ29udHJv
bHMuYnVzeSAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS53aWZpX2VuYWJsZWQhPT1udWxsICYmIFN5
c3RlbUNvbnRyb2xzLnN0YXRlLndpZmlfZW5hYmxlZCE9PXVuZGVmaW5lZDtvblRvZ2dsZWQ6c3lz
dGVtLnJlcXVlc3QoIndpZmktcmFkaW8iLGNoZWNrZWQ/Im9uIjoib2ZmIikgfQorICAgICAgICBD
aGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpW
YlRva2Vucy50eXBlQm9keTsgdGV4dDpxc1RyKCJCbHVldG9vdGggcmFkaW8iKTtjaGVja2VkOlN5
c3RlbUNvbnRyb2xzLnN0YXRlLmJsdWV0b290aF9lbmFibGVkPT09dHJ1ZTtlbmFibGVkOiFTeXN0
ZW1Db250cm9scy5idXN5ICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLmJsdWV0b290aF9lbmFibGVk
IT09bnVsbCAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS5ibHVldG9vdGhfZW5hYmxlZCE9PXVuZGVm
aW5lZDtvblRvZ2dsZWQ6c3lzdGVtLnJlcXVlc3QoImJ0LXJhZGlvIixjaGVja2VkPyJvbiI6Im9m
ZiIpIH0KKyAgICB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsg
Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiQXVkaW8gYW5kIGJy
aWdodG5lc3MiKTtjb2xvcjpWYlRva2Vucy50ZXh0O2ZvbnQuYm9sZDp0cnVlIH0KKyAgICBSb3dM
YXlvdXQgeworICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOnRydWUKKyAgICAgICAgU2xpZGVyIHsg
aWQ6dm9sdW1lO0xheW91dC5maWxsV2lkdGg6dHJ1ZTtmcm9tOjA7dG86MTAwO3N0ZXBTaXplOjE7
dmFsdWU6U3lzdGVtQ29udHJvbHMuc3RhdGUudm9sdW1lIHx8IDA7ZW5hYmxlZDohU3lzdGVtQ29u
dHJvbHMuYnVzeSAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUhPT1udWxsICYmIFN5c3Rl
bUNvbnRyb2xzLnN0YXRlLnZvbHVtZSE9PXVuZGVmaW5lZDtBY2Nlc3NpYmxlLm5hbWU6cXNUcigi
U3BlYWtlciB2b2x1bWUiKTtvblByZXNzZWRDaGFuZ2VkOmlmKCFwcmVzc2VkJiZlbmFibGVkKXN5
c3RlbS5yZXF1ZXN0KCJ2b2x1bWUiLFN0cmluZyhNYXRoLnJvdW5kKHZhbHVlKSkpO29uTW92ZWQ6
aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3QoInZvbHVtZSIsU3RyaW5nKE1hdGgu
cm91bmQodmFsdWUpKSkgfQorICAgICAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZv
bnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDpNYXRoLnJvdW5k
KHZvbHVtZS52YWx1ZSkrIiUiO2NvbG9yOlZiVG9rZW5zLnRleHQgfQorICAgICAgICBFY2xpcHNl
QWN0aW9uQnV0dG9uIHsgdGV4dDpTeXN0ZW1Db250cm9scy5zdGF0ZS5tdXRlZD9xc1RyKCJVbm11
dGUiKTpxc1RyKCJNdXRlIik7ZW5hYmxlZDp2b2x1bWUuZW5hYmxlZDtvbkNsaWNrZWQ6c3lzdGVt
LnJlcXVlc3QoIm11dGUiKSB9CisgICAgfQorICAgIEVjbGlwc2VDb21ib0JveCB7IExheW91dC5m
aWxsV2lkdGg6dHJ1ZTttb2RlbDpTeXN0ZW1Db250cm9scy5zdGF0ZS5zaW5rcyB8fCBbXTt0ZXh0
Um9sZToibmFtZSI7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBjb3VudD4wO0FjY2Vz
c2libGUubmFtZTpxc1RyKCJBdWRpbyBvdXRwdXQiKTtjdXJyZW50SW5kZXg6e3ZhciBhPVN5c3Rl
bUNvbnRyb2xzLnN0YXRlLnNpbmtzIHx8IFtdO2Zvcih2YXIgaT0wO2k8YS5sZW5ndGg7aSsrKWlm
KGFbaV0uZGVmYXVsdClyZXR1cm4gaTtyZXR1cm4gLTF9CisgICAgICAgIG9uQWN0aXZhdGVkOnN5
c3RlbS5yZXF1ZXN0KCJvdXRwdXQiLG1vZGVsW2luZGV4XS5pZCkgfQorICAgIFJvd0xheW91dCB7
CisgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIlRlc3Qgc291bmQiKTtl
bmFibGVkOnZvbHVtZS5lbmFibGVkO29uQ2xpY2tlZDpzeXN0ZW0ucmVxdWVzdCgidGVzdC1zb3Vu
ZCIpIH0KKyAgICAgICAgRWNsaXBzZUNvbWJvQm94IHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlOyBt
b2RlbDpbcXNUcigiQWlyUG9kczogTG93IGxhdGVuY3kiKSxxc1RyKCJBaXJQb2RzOiBRdWFsaXR5
IildO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25BY3RpdmF0ZWQ6c3lzdGVtLnJlcXVl
c3QoImFpcnBvZHMiLGluZGV4PT09MD8ibG93LWxhdGVuY3kiOiJxdWFsaXR5IikgfQorICAgIH0K
KyAgICBSZXBlYXRlciB7CisgICAgICAgIG1vZGVsOlt7a2luZDoic2NyZWVuIixsYWJlbDpxc1Ry
KCJTY3JlZW4gYnJpZ2h0bmVzcyIpfSx7a2luZDoia2V5Ym9hcmQiLGxhYmVsOnFzVHIoIktleWJv
YXJkIGxpZ2h0aW5nIil9XQorICAgICAgICBkZWxlZ2F0ZTpDb2x1bW5MYXlvdXQgeworICAgICAg
ICAgICAgTGF5b3V0LmZpbGxXaWR0aDp0cnVlCisgICAgICAgICAgICBwcm9wZXJ0eSB2YXIgaGFy
ZHdhcmU6KFN5c3RlbUNvbnRyb2xzLnN0YXRlLmJyaWdodG5lc3MgfHwge30pW21vZGVsRGF0YS5r
aW5kXQorICAgICAgICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsg
Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6bW9kZWxEYXRhLmxhYmVsKyho
YXJkd2FyZT8iIOKAoiAiK2hhcmR3YXJlLnBlcmNlbnQrIiUiOiIg4oCiICIrcXNUcigiVW5hdmFp
bGFibGUiKSk7Y29sb3I6VmJUb2tlbnMudGV4dCB9CisgICAgICAgICAgICBTbGlkZXIgeyBMYXlv
dXQuZmlsbFdpZHRoOnRydWU7ZnJvbTptb2RlbERhdGEua2luZD09PSJzY3JlZW4iPzU6MDt0bzox
MDA7c3RlcFNpemU6MTtlbmFibGVkOiEhaGFyZHdhcmUmJiFTeXN0ZW1Db250cm9scy5idXN5O3Zh
bHVlOmhhcmR3YXJlP2hhcmR3YXJlLnBlcmNlbnQ6MDtBY2Nlc3NpYmxlLm5hbWU6bW9kZWxEYXRh
LmxhYmVsO29uUHJlc3NlZENoYW5nZWQ6aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVl
c3QobW9kZWxEYXRhLmtpbmQsU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSk7b25Nb3ZlZDppZigh
cHJlc3NlZCYmZW5hYmxlZClzeXN0ZW0ucmVxdWVzdChtb2RlbERhdGEua2luZCxTdHJpbmcoTWF0
aC5yb3VuZCh2YWx1ZSkpKSB9CisgICAgICAgIH0KKyAgICB9CisgICAgTGFiZWwgeyBmb250LmZh
bWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7
IHRleHQ6cXNUcigiRGlzcGxheSBhbmQgaWRsZSBibGFua2luZyIpO2NvbG9yOlZiVG9rZW5zLnRl
eHQ7Zm9udC5ib2xkOnRydWUgfQorICAgIEVjbGlwc2VDb21ib0JveCB7IGlkOm1vZGVDaG9pY2U7
TGF5b3V0LmZpbGxXaWR0aDp0cnVlO21vZGVsOlN5c3RlbUNvbnRyb2xzLnN0YXRlLmRpc3BsYXlz
IHx8IFtdO3RleHRSb2xlOiJuYW1lIjtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5ICYmIGNv
dW50PjA7QWNjZXNzaWJsZS5uYW1lOnFzVHIoIkRpc3BsYXkgcmVzb2x1dGlvbiBhbmQgcmVmcmVz
aCByYXRlIik7Y3VycmVudEluZGV4Ont2YXIgYT1TeXN0ZW1Db250cm9scy5zdGF0ZS5kaXNwbGF5
cyB8fCBbXTtmb3IodmFyIGk9MDtpPGEubGVuZ3RoO2krKylpZihhW2ldLmN1cnJlbnQpcmV0dXJu
IGk7cmV0dXJuIC0xfSB9CisgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiQXBw
bHkgZGlzcGxheSBtb2RlIOKAoiAxNS1zZWNvbmQgcm9sbGJhY2siKTtlbmFibGVkOm1vZGVDaG9p
Y2UuZW5hYmxlZCYmbW9kZUNob2ljZS5jdXJyZW50SW5kZXg+PTA7b25DbGlja2VkOnN5c3RlbS5y
ZXF1ZXN0KCJkaXNwbGF5Iixtb2RlQ2hvaWNlLm1vZGVsW21vZGVDaG9pY2UuY3VycmVudEluZGV4
XS5pZCkgfQorICAgIEVjbGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgbW9k
ZWw6W3FzVHIoIk5ldmVyIGJsYW5rIikscXNUcigiQmxhbmsgYWZ0ZXIgNSBtaW51dGVzIikscXNU
cigiQmxhbmsgYWZ0ZXIgMTAgbWludXRlcyIpLHFzVHIoIkJsYW5rIGFmdGVyIDMwIG1pbnV0ZXMi
KV07ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeTtvbkFjdGl2YXRlZDpzeXN0ZW0ucmVxdWVz
dCgiaWRsZSIsWyIwIiwiMzAwIiwiNjAwIiwiMTgwMCJdW2luZGV4XSkgfQorICAgIExhYmVsIHsg
Zm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5
cGVCb2R5OyB0ZXh0OnFzVHIoIlBvaW50ZXIgYW5kIHRyYWNrcGFkIik7Y29sb3I6VmJUb2tlbnMu
dGV4dDtmb250LmJvbGQ6dHJ1ZSB9CisgICAgRWNsaXBzZUNvbWJvQm94IHsgaWQ6cG9pbnRlckNo
b2ljZTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7bW9kZWw6U3lzdGVtQ29udHJvbHMuc3RhdGUucG9p
bnRlcnMgfHwgW107dGV4dFJvbGU6Im5hbWUiO2VuYWJsZWQ6Y291bnQ+MCYmIVN5c3RlbUNvbnRy
b2xzLmJ1c3k7QWNjZXNzaWJsZS5uYW1lOnFzVHIoIlBvaW50ZXIgZGV2aWNlIikgfQorICAgIFNs
aWRlciB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTtmcm9tOi0xO3RvOjE7c3RlcFNpemU6LjA1O3Zh
bHVlOnN5c3RlbS5wb2ludGVyLnNwZWVkIHx8IDA7ZW5hYmxlZDpzeXN0ZW0ucG9pbnRlci5zcGVl
ZCE9PXVuZGVmaW5lZCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7QWNjZXNzaWJsZS5uYW1lOnFzVHIo
IlBvaW50ZXIgYWNjZWxlcmF0aW9uIHNwZWVkIik7b25QcmVzc2VkQ2hhbmdlZDppZighcHJlc3Nl
ZCYmZW5hYmxlZClzeXN0ZW0ucmVxdWVzdCgicG9pbnRlci1zcGVlZCIsc3lzdGVtLnBvaW50ZXIu
aWQrIjoiK3ZhbHVlLnRvRml4ZWQoMikpO29uTW92ZWQ6aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lz
dGVtLnJlcXVlc3QoInBvaW50ZXItc3BlZWQiLHN5c3RlbS5wb2ludGVyLmlkKyI6Iit2YWx1ZS50
b0ZpeGVkKDIpKSB9CisgICAgQ2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9k
eTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiTmF0dXJhbCBz
Y3JvbGxpbmciKTtjaGVja2VkOnN5c3RlbS5wb2ludGVyLm5hdHVyYWw9PT0xO2VuYWJsZWQ6c3lz
dGVtLnBvaW50ZXIubmF0dXJhbCE9PXVuZGVmaW5lZCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25U
b2dnbGVkOnN5c3RlbS5yZXF1ZXN0KCJwb2ludGVyLW5hdHVyYWwiLHN5c3RlbS5wb2ludGVyLmlk
KyI6IisoY2hlY2tlZD8iMSI6IjAiKSkgfQorICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJU
b2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFz
VHIoIlRhcCB0byBjbGljayIpO2NoZWNrZWQ6c3lzdGVtLnBvaW50ZXIudGFwPT09MTtlbmFibGVk
OnN5c3RlbS5wb2ludGVyLnRhcCE9PXVuZGVmaW5lZCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25U
b2dnbGVkOnN5c3RlbS5yZXF1ZXN0KCJwb2ludGVyLXRhcCIsc3lzdGVtLnBvaW50ZXIuaWQrIjoi
KyhjaGVja2VkPyIxIjoiMCIpKSB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5m
b250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lk
dGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7dGV4dDpxc1RyKCJQb2ludGVyIGFuZCBibGFua2lu
ZyBjaGFuZ2VzIGN1cnJlbnRseSBhcHBseSB0byB0aGlzIFgxMSBzZXNzaW9uLiBVbnN1cHBvcnRl
ZCBkZXZpY2UgY29udHJvbHMgYXJlIGRpc2FibGVkLiBEaXNwbGF5IGNoYW5nZXMgcmV2ZXJ0IHVu
bGVzcyBjb25maXJtZWQuIik7Y29sb3I6VmJUb2tlbnMudGV4dERpbSB9CisgICAgTGFiZWwgeyBm
b250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlw
ZUJvZHk7IHRleHQ6cXNUcigiUmVjb3ZlcnkgYW5kIHBvd2VyIik7Y29sb3I6VmJUb2tlbnMudGV4
dDtmb250LmJvbGQ6dHJ1ZSB9CisgICAgRWNsaXBzZUNvbWJvQm94IHsgaWQ6ZnJvbnRlbmQ7bW9k
ZWw6WyJFY2xpcHNlIiwiQXJ0ZW1pcyIsIlBlZ2FzdXMiLCJNb29ubGlnaHQiLCJDb2NvT1MiXTtB
Y2Nlc3NpYmxlLm5hbWU6cXNUcigiRnJvbnRlbmQgZm9yIG5leHQgYm9vdCIpIH0KKyAgICBFY2xp
cHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpxc1RyKCJTYXZlIGZyb250ZW5kIGZvciBuZXh0IGJvb3Qi
KTtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5O29uQ2xpY2tlZDpzeXN0ZW0ucmVxdWVzdCgi
ZnJvbnRlbmQiLFsidmliZW1pcyIsImFydGVtaXMiLCJwZWdhc3VzIiwibW9vbmxpZ2h0IiwiY29j
b29zIl1bZnJvbnRlbmQuY3VycmVudEluZGV4XSkgfQorICAgIEZsb3cgeworICAgICAgICBMYXlv
dXQuZmlsbFdpZHRoOnRydWU7c3BhY2luZzpWYlRva2Vucy5zcGFjZTIKKyAgICAgICAgUmVwZWF0
ZXIgeyBtb2RlbDpbe25hbWU6cXNUcigiUmVzdGFydCBmcm9udGVuZCIpLGFjdGlvbjoicmVzdGFy
dC1mcm9udGVuZCJ9LHtuYW1lOnFzVHIoIlJlc3RhcnQgRWNsaXBzZU9TIiksYWN0aW9uOiJyZWJv
b3QifSx7bmFtZTpxc1RyKCJTaHV0IGRvd24iKSxhY3Rpb246InBvd2Vyb2ZmIn1dCisgICAgICAg
ICAgICBkZWxlZ2F0ZTpFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDptb2RlbERhdGEubmFtZTtp
Y29uU291cmNlOiJxcmM6L3Jlcy9lY2xpcHNlLXBvd2VyLnN2ZyI7ZW5hYmxlZDohU3lzdGVtQ29u
dHJvbHMuYnVzeTtvbkNsaWNrZWQ6e3N5c3RlbS5wb3dlckFjdGlvbj1tb2RlbERhdGEuYWN0aW9u
O3Bvd2VyLm9wZW4oKX0gfQorICAgICAgICB9CisgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24g
eyB0ZXh0OnFzVHIoIlJlZGFjdGVkIHN1cHBvcnQgcmVwb3J0Iik7ZW5hYmxlZDohU3lzdGVtQ29u
dHJvbHMuYnVzeTtvbkNsaWNrZWQ6c3lzdGVtLnJlcXVlc3QoInJlcG9ydCIpIH0KKyAgICAgICAg
RWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiUmVmcmVzaCBjb250cm9scyIpO2VuYWJs
ZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25DbGlja2VkOnN5c3RlbS5yZXF1ZXN0KCJsaXN0Iikg
fQorICAgIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250
LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBN
b2RlOlRleHQuV3JhcDt0ZXh0OnFzVHIoIlN1c3BlbmQgYW5kIGxpZCBwcmVzZXRzIGF3YWl0IHBo
eXNpY2FsIHZhbGlkYXRpb24uIFJlY292ZXJ5IGNvbnNvbGU6IENvbnRyb2wgKyBPcHRpb24gKyBG
MiAoRm4gaWYgbmVlZGVkKS4iKTtjb2xvcjpWYlRva2Vucy50ZXh0RGltIH0KKyAgICBFY2xpcHNl
SGFyZHdhcmVNb25pdG9yIHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO2FjdGl2ZTpzeXN0ZW0uYWN0
aXZlIH0KKyAgICBTeXN0ZW1Db25uZWN0aW9uc0RpYWxvZyB7IGlkOmNvbm5lY3Rpb25zO3BhcmVu
dDpPdmVybGF5Lm92ZXJsYXk7b25DbG9zZWQ6aWYoc3lzdGVtLmFjdGl2ZSlyZXN1bWUucmVzdGFy
dCgpIH0KKyAgICBUaW1lciB7IGlkOnJlc3VtZTtpbnRlcnZhbDo2MDA7b25UcmlnZ2VyZWQ6aWYo
c3lzdGVtLmFjdGl2ZSlTeXN0ZW1Db250cm9scy5vcGVuKCJjZW50ZXIiKSB9CisgICAgTmF2aWdh
YmxlRGlhbG9nIHsgaWQ6cG93ZXI7cGFyZW50Ok92ZXJsYXkub3ZlcmxheTt3aWR0aDpNYXRoLm1p
big0NDAscGFyZW50LndpZHRoLTMyKTt0aXRsZTpxc1RyKCJDb25maXJtIHN5c3RlbSBhY3Rpb24i
KTtzdGFuZGFyZEJ1dHRvbnM6RGlhbG9nLlllc3xEaWFsb2cuTm87YmFja2dyb3VuZDpSZWN0YW5n
bGV7Y29sb3I6VmJUb2tlbnMuYmdFbGV2O3JhZGl1czpWYlRva2Vucy5yYWRpdXNEaWFsb2c7Ym9y
ZGVyLmNvbG9yOlZiVG9rZW5zLnN0cm9rZX0KKyAgICAgICAgb25BY2NlcHRlZDpTeXN0ZW1Db250
cm9scy5yZXF1ZXN0KCJjZW50ZXItIitzeXN0ZW0ucG93ZXJBY3Rpb24sIiIsdHJ1ZSk7Y29udGVu
dEl0ZW06TGFiZWx7d3JhcE1vZGU6VGV4dC5XcmFwO3RleHQ6cXNUcigiUHJvY2VlZCB3aXRoICUx
PyBBY3RpdmUgc3RyZWFtaW5nIHdpbGwgZW5kLiIpLmFyZyhzeXN0ZW0ucG93ZXJBY3Rpb24pO2Nv
bG9yOlZiVG9rZW5zLnRleHR9IH0KKyAgICBOYXZpZ2FibGVEaWFsb2cgeyBpZDpjb25maXJtYXRp
b247cGFyZW50Ok92ZXJsYXkub3ZlcmxheTt3aWR0aDpNYXRoLm1pbig0ODAscGFyZW50LndpZHRo
LTMyKTt0aXRsZTpxc1RyKCJLZWVwIGRpc3BsYXkgbW9kZT8iKTtzdGFuZGFyZEJ1dHRvbnM6RGlh
bG9nLlllc3xEaWFsb2cuTm87Y2xvc2VQb2xpY3k6UG9wdXAuTm9BdXRvQ2xvc2U7YmFja2dyb3Vu
ZDpSZWN0YW5nbGV7Y29sb3I6VmJUb2tlbnMuYmdFbGV2O3JhZGl1czpWYlRva2Vucy5yYWRpdXNE
aWFsb2c7Ym9yZGVyLmNvbG9yOlZiVG9rZW5zLnN0cm9rZX0KKyAgICAgICAgb25BY2NlcHRlZDpT
eXN0ZW1Db250cm9scy5hbnN3ZXIoInllcyIpO29uUmVqZWN0ZWQ6U3lzdGVtQ29udHJvbHMuYW5z
d2VyKCJubyIpO2NvbnRlbnRJdGVtOkxhYmVse3dyYXBNb2RlOlRleHQuV3JhcDt0ZXh0OlN5c3Rl
bUNvbnRyb2xzLnByb21wdDtjb2xvcjpWYlRva2Vucy50ZXh0fSB9CisgICAgQ29ubmVjdGlvbnMg
eyB0YXJnZXQ6U3lzdGVtQ29udHJvbHM7ZnVuY3Rpb24gb25DaGFuZ2VkKCl7aWYoc3lzdGVtLmFj
dGl2ZSYmU3lzdGVtQ29udHJvbHMucHJvbXB0Lmxlbmd0aD4wJiYhY29ubmVjdGlvbnMub3BlbmVk
KWNvbmZpcm1hdGlvbi5vcGVuKCk7aWYoIVN5c3RlbUNvbnRyb2xzLmJ1c3kpY29uZmlybWF0aW9u
LmNsb3NlKCl9IH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvTmF2aWdhYmxlRGlhbG9nLnFtbCBi
L2FwcC9ndWkvTmF2aWdhYmxlRGlhbG9nLnFtbAppbmRleCA0Mzg0ZDViLi5iZDllZGE1IDEwMDY0
NAotLS0gYS9hcHAvZ3VpL05hdmlnYWJsZURpYWxvZy5xbWwKKysrIGIvYXBwL2d1aS9OYXZpZ2Fi
bGVEaWFsb2cucW1sCkBAIC0xLDcgKzEsMzUgQEAKIGltcG9ydCBRdFF1aWNrIDIuMAogaW1wb3J0
IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5Db250cm9scy5NYXRlcmlhbCAy
LjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAogCiBEaWFsb2cgeworICAgIGlkOiBkaWFs
b2cKKyAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKKyAgICBmb250LnBpeGVsU2l6
ZTogVmJUb2tlbnMudHlwZUJvZHkKKyAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5i
Z0VsZXYKKyAgICBNYXRlcmlhbC5mb3JlZ3JvdW5kOiBWYlRva2Vucy50ZXh0CisgICAgTWF0ZXJp
YWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBPdmVybGF5Lm1vZGFsOiBSZWN0YW5nbGUg
e2NvbG9yOlZiVG9rZW5zLmRpYWxvZ1NjcmltfQorICAgIE92ZXJsYXkubW9kZWxlc3M6IFJlY3Rh
bmdsZSB7Y29sb3I6VmJUb2tlbnMuZGlhbG9nU2NyaW19CisgICAgYmFja2dyb3VuZDogQ3JpbXNv
bkdsYXNzUGFuZWwgeyByYWRpdXM6VmJUb2tlbnMucmFkaXVzRGlhbG9nIH0KKyAgICBoZWFkZXI6
IExhYmVsIHsKKyAgICAgICAgdmlzaWJsZTogZGlhbG9nLnRpdGxlLmxlbmd0aCA+IDAKKyAgICAg
ICAgdGV4dDogZGlhbG9nLnRpdGxlOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgY29sb3I6
VmJUb2tlbnMudGV4dAorICAgICAgICBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9u
dC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IGZvbnQuYm9sZDp0cnVlCisgICAgICAgIHBh
ZGRpbmc6VmJUb2tlbnMuc3BhY2U0OyBlbGlkZTpUZXh0LkVsaWRlUmlnaHQKKyAgICB9CisgICAg
Zm9vdGVyOiBEaWFsb2dCdXR0b25Cb3ggeworICAgICAgICBiYWNrZ3JvdW5kOiBJdGVtIHt9Cisg
ICAgICAgIHZpc2libGU6IGRpYWxvZy5zdGFuZGFyZEJ1dHRvbnMgIT09IERpYWxvZy5Ob0J1dHRv
bgorICAgICAgICBzdGFuZGFyZEJ1dHRvbnM6IGRpYWxvZy5zdGFuZGFyZEJ1dHRvbnMKKyAgICAg
ICAgaW1wbGljaXRIZWlnaHQ6IHZpc2libGUgPyBNYXRoLm1heCg0NCxWYlRva2Vucy50eXBlTGFi
ZWwrMjApKzIqVmJUb2tlbnMuc3BhY2UzIDogMAorICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5z
cGFjZTIKKyAgICAgICAgcGFkZGluZzogVmJUb2tlbnMuc3BhY2UzCisgICAgICAgIGRlbGVnYXRl
OiBFY2xpcHNlQWN0aW9uQnV0dG9uIHt9CisgICAgICAgIG9uQWNjZXB0ZWQ6IGRpYWxvZy5hY2Nl
cHQoKQorICAgICAgICBvblJlamVjdGVkOiBkaWFsb2cucmVqZWN0KCkKKyAgICB9CiAgICAgbW9k
YWw6IHRydWUKICAgICBhbmNob3JzLmNlbnRlckluOiBPdmVybGF5Lm92ZXJsYXkKIApkaWZmIC0t
Z2l0IGEvYXBwL2d1aS9OYXZpZ2FibGVNZW51LnFtbCBiL2FwcC9ndWkvTmF2aWdhYmxlTWVudS5x
bWwKaW5kZXggYTdiMjBmMC4uNTA1ZjM5NiAxMDA2NDQKLS0tIGEvYXBwL2d1aS9OYXZpZ2FibGVN
ZW51LnFtbAorKysgYi9hcHAvZ3VpL05hdmlnYWJsZU1lbnUucW1sCkBAIC0xLDggKzEsMTEgQEAK
IGltcG9ydCBRdFF1aWNrIDIuMAogaW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi4yCitpbXBvcnQg
VmliZW1pcy5SZWRlc2lnbiAxLjAKIAogTWVudSB7CiAgICAgcHJvcGVydHkgdmFyIGluaXRpYXRv
cgorICAgIHBhZGRpbmc6IFZiVG9rZW5zLnNwYWNlMgorICAgIGJhY2tncm91bmQ6IENyaW1zb25H
bGFzc1BhbmVsIHtyYWRpdXM6VmJUb2tlbnMucmFkaXVzQ29udHJvbH0KIAogICAgIG9uT3BlbmVk
OiB7CiAgICAgICAgIC8vIElmIHRoZSBpbml0aWF0aW5nIG9iamVjdCBjdXJyZW50bHkgaGFzIGtl
eWJvYXJkIGZvY3VzLApkaWZmIC0tZ2l0IGEvYXBwL2d1aS9OYXZpZ2FibGVUb29sQnV0dG9uLnFt
bCBiL2FwcC9ndWkvTmF2aWdhYmxlVG9vbEJ1dHRvbi5xbWwKaW5kZXggNWI2NDY3MS4uYTc5OTYx
OCAxMDA2NDQKLS0tIGEvYXBwL2d1aS9OYXZpZ2FibGVUb29sQnV0dG9uLnFtbAorKysgYi9hcHAv
Z3VpL05hdmlnYWJsZVRvb2xCdXR0b24ucW1sCkBAIC0yNyw3ICsyNyw3IEBAIFRvb2xCdXR0b24g
ewogICAgIHBhZGRpbmc6IDAKICAgICBMYXlvdXQuYWxpZ25tZW50OiBRdC5BbGlnblZDZW50ZXIK
IAotICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7CisgICAgYmFja2dyb3VuZDogQ3JpbXNvbkds
YXNzUGFuZWwgewogICAgICAgICByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0ljb25CdXR0b24KICAg
ICAgICAgY29sb3I6IGJ0bi5hY3RpdmVGb2N1cyA/IFZiVG9rZW5zLmZvY3VzZWRGaWxsIDogKGJ0
bi5ob3ZlcmVkID8gVmJUb2tlbnMuYmdFbGV2MiA6IFZiVG9rZW5zLmJnRWxldikKICAgICAgICAg
Ym9yZGVyLndpZHRoOiAxCmRpZmYgLS1naXQgYS9hcHAvZ3VpL1BjVmlldy5xbWwgYi9hcHAvZ3Vp
L1BjVmlldy5xbWwKaW5kZXggZjBlNzM5YS4uZmIxOTg0YSAxMDA2NDQKLS0tIGEvYXBwL2d1aS9Q
Y1ZpZXcucW1sCisrKyBiL2FwcC9ndWkvUGNWaWV3LnFtbApAQCAtNDMsNyArNDMsMTYgQEAgQ2Vu
dGVyZWRHcmlkVmlldyB7CiAgICAgLy8gYmFjayB0byBtaW5NYXJnaW4gKGRlZmF1bHQgMTBweCkg
4oCUIGNhcmRzIGh1Z2dlZCB0aGUgc2NyZWVuIGVkZ2UsIG1pc2FsaWduZWQgd2l0aCB0aGUKICAg
ICAvLyA1NnB4IGhlYWRlciBhbmQgdmlzdWFsbHkgY2xpcHBpbmcgdGhlIGZvY3VzIHJpbmcncyBv
dXRlciBnbG93LiBBbGlnbiBwYXJ0aWFsIHJvd3Mgd2l0aAogICAgIC8vIHRoZSByZWRlc2lnbidz
IHNjcmVlbiBwYWRkaW5nIGluc3RlYWQuCisgICAgcmVhZG9ubHkgcHJvcGVydHkgYm9vbCBnbGFz
c1dpZGU6IHdpZHRoID49IDEyNDAgJiYgaGVpZ2h0ID49IDU0MAorICAgIHJlYWRvbmx5IHByb3Bl
cnR5IGludCByYWlsU3BhY2U6IHdpZHRoID49IDkwMCA/IDg0IDogMAorICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGludCBsb2NhbFNwYWNlOiBnbGFzc1dpZGUgPyBNYXRoLnJvdW5kKDI1MipWYlRva2Vu
cy50ZXh0U2NhbGUpIDogMAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBob3N0U3BhY2U6IDAK
ICAgICBtaW5NYXJnaW46IFZiVG9rZW5zLnNjcmVlblBhZFgKKyAgICBhdmFpbGFibGVXaWR0aDog
d2lkdGggLSByYWlsU3BhY2UgLSBsb2NhbFNwYWNlIC0gaG9zdFNwYWNlIC0gMiptaW5NYXJnaW4K
KyAgICBvblJhaWxTcGFjZUNoYW5nZWQ6IHVwZGF0ZU1hcmdpbnMoKQorICAgIG9uTG9jYWxTcGFj
ZUNoYW5nZWQ6IHVwZGF0ZU1hcmdpbnMoKQorICAgIG9uSG9zdFNwYWNlQ2hhbmdlZDogdXBkYXRl
TWFyZ2lucygpCisgICAgZnVuY3Rpb24gdXBkYXRlTWFyZ2lucygpIHsgbGVmdE1hcmdpbj1ob3Jp
em9udGFsTWFyZ2luK3JhaWxTcGFjZStob3N0U3BhY2U7cmlnaHRNYXJnaW49aG9yaXpvbnRhbE1h
cmdpbitsb2NhbFNwYWNlIH0KICAgICAvLyBUaGUgIkFkZCBhIGNvbXB1dGVyIiBnaG9zdCBjYXJk
IGlzIGhhbmQtcGxhY2VkIGF0IHRoZSBpbmRleD09Y291bnQgY2VsbCAoc2VlIHRoZSBkZWxlZ2F0
ZSdzCiAgICAgLy8gc2libGluZyBiZWxvdykuIEdyaWRWaWV3LmNvbnRlbnRIZWlnaHQgb25seSBj
b3VudHMgcmVhbCBkZWxlZ2F0ZXMsIHNvIHdoZW4gdGhlIGxhc3Qgcm93IGlzIEZVTEwKICAgICAv
LyAoY291bnQgaXMgYSBtdWx0aXBsZSBvZiB0aGUgY29sdW1uIGNvdW50KSB0aGUgZ2hvc3QgY2Fy
ZCBzdGFydHMgYSBicmFuZC1uZXcgdmlydHVhbCByb3cgYXQKQEAgLTUyLDcgKzYxLDcgQEAgQ2Vu
dGVyZWRHcmlkVmlldyB7CiAgICAgYm90dG9tTWFyZ2luOiAocGNIaW50QmFyLnZpc2libGUgPyBw
Y0hpbnRCYXIuaGVpZ2h0IDogMCkgKyAxMgogICAgICAgICAgICAgICAgICAgKyAoKGNvdW50ID4g
MCAmJiAoY291bnQgJSBNYXRoLm1heCgxLCBNYXRoLmZsb29yKGl0ZW1zUGVyUm93KSkpID09PSAw
KSA/IGNlbGxIZWlnaHQgOiAwKQogICAgIC8vIFJlZGVzaWduOiA0MzBweCByaWNoIGhvc3QgY2Fy
ZHMgKGdhcCAzMikgaW4gYSBjZW50ZXJlZCB3cmFwcGluZyByb3cuCi0gICAgY2VsbFdpZHRoOiA0
NjI7IGNlbGxIZWlnaHQ6IDI3NDsKKyAgICBjZWxsV2lkdGg6IDM5MjsgY2VsbEhlaWdodDogMjY2
OwogICAgIG9iamVjdE5hbWU6IHFzVHIoIkNvbXB1dGVycyIpCiAKICAgICAvLyBELXBhZCBzZWxl
Y3Rpb24gc3RhdGUgZm9yIHRoZSBBZGQtYS1jb21wdXRlciBnaG9zdCDigJQgV0lUSE9VVCBmb2N1
cy4gVGhlCkBAIC0xMDUsMTkgKzExNCwxOSBAQCBDZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAg
YW5jaG9ycy5sZWZ0OiBwYXJlbnQubGVmdAogICAgICAgICBhbmNob3JzLnJpZ2h0OiBwYXJlbnQu
cmlnaHQKICAgICAgICAgdmlzaWJsZTogdHJ1ZQotICAgICAgICBoZWlnaHQ6IDc4CisgICAgICAg
IGhlaWdodDogNjYKIAotICAgICAgICBSZWN0YW5nbGUgeyBhbmNob3JzLmZpbGw6IHBhcmVudDsg
Y29sb3I6IFZiVG9rZW5zLmJnV2luZG93IH0KKyAgICAgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy5m
aWxsOiBwYXJlbnQ7IGNvbG9yOiAidHJhbnNwYXJlbnQiIH0KIAogICAgICAgICBSb3cgewogICAg
ICAgICAgICAgYW5jaG9ycy5sZWZ0OiBwYXJlbnQubGVmdAotICAgICAgICAgICAgYW5jaG9ycy5s
ZWZ0TWFyZ2luOiBWYlRva2Vucy5zY3JlZW5QYWRYCisgICAgICAgICAgICBhbmNob3JzLmxlZnRN
YXJnaW46IFZiVG9rZW5zLnNjcmVlblBhZFgrcGNHcmlkLnJhaWxTcGFjZStwY0dyaWQuaG9zdFNw
YWNlCiAgICAgICAgICAgICBhbmNob3JzLmJvdHRvbTogcGFyZW50LmJvdHRvbQogICAgICAgICAg
ICAgYW5jaG9ycy5ib3R0b21NYXJnaW46IDYKICAgICAgICAgICAgIHNwYWNpbmc6IDE0CiAgICAg
ICAgICAgICBUZXh0IHsKICAgICAgICAgICAgICAgICBpZDogc2VjdGlvblRpdGxlCi0gICAgICAg
ICAgICAgICAgdGV4dDogcXNUcigiQ29tcHV0ZXJzIikKKyAgICAgICAgICAgICAgICB0ZXh0OiBx
c1RyKCJIb3N0cyIpCiAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRE
aXNwbGF5CiAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZvbnQuQm9sZAogICAgICAgICAg
ICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy5zaXplU2NyZWVuVGl0bGUKQEAgLTEzNCw2
ICsxNDMsMjQgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAgICAgIH0KICAgICB9CiAKKworICAg
IC8vIENyaW1zb24gR2xhc3MgZGFzaGJvYXJkIGNocm9tZSBsaXZlcyBpbiB0aGUgdmlld3BvcnQs
IG91dHNpZGUgY29udGVudEl0ZW0uCisgICAgQ3JpbXNvbkdsYXNzUmFpbCB7CisgICAgICAgIHBh
cmVudDpwY0dyaWQKKyAgICAgICAgejoxMTt4OjEyO3k6MTY7d2lkdGg6NjQ7aGVpZ2h0Ok1hdGgu
bWF4KDI4MCxwY0dyaWQuaGVpZ2h0LTMyLShwY0hpbnRCYXIudmlzaWJsZT9wY0hpbnRCYXIuaGVp
Z2h0OjApKQorICAgICAgICB2aXNpYmxlOnBjR3JpZC5yYWlsU3BhY2U+MDtpbkxpYnJhcnk6ZmFs
c2UKKyAgICAgICAgb25Ib21lUmVxdWVzdGVkOiB7IGlmKHN0YWNrVmlldy5kZXB0aD4xKSBzdGFj
a1ZpZXcucG9wKG51bGwpO2Vsc2UgcGNHcmlkLmZvcmNlQWN0aXZlRm9jdXMoKSB9CisgICAgICAg
IG9uU2V0dGluZ3NSZXF1ZXN0ZWQ6IHNldHRpbmdzQnV0dG9uLmNsaWNrZWQoKQorICAgICAgICBv
bkNvbnRyb2xzUmVxdWVzdGVkOiBlY2xpcHNlQ2VudGVyQnV0dG9uLmNsaWNrZWQoKQorICAgIH0K
KyAgICBDcmltc29uTG9jYWxQYW5lbCB7CisgICAgICAgIHBhcmVudDpwY0dyaWQKKyAgICAgICAg
ejoxMTthbmNob3JzLnJpZ2h0OnBhcmVudC5yaWdodDthbmNob3JzLnJpZ2h0TWFyZ2luOjE2O3k6
MTY7d2lkdGg6TWF0aC5tYXgoMCxwY0dyaWQubG9jYWxTcGFjZS0yOCkKKyAgICAgICAgaGVpZ2h0
Ok1hdGgubWF4KDI0MCxwY0dyaWQuaGVpZ2h0LTMyLShwY0hpbnRCYXIudmlzaWJsZT9wY0hpbnRC
YXIuaGVpZ2h0OjApKTt2aXNpYmxlOnBjR3JpZC5sb2NhbFNwYWNlPjAKKyAgICAgICAgYWN0aXZl
OnZpc2libGUgJiYgcGNHcmlkLlN0YWNrVmlldy5zdGF0dXM9PT1TdGFja1ZpZXcuQWN0aXZlCisg
ICAgICAgIG9uQ29udHJvbHNSZXF1ZXN0ZWQ6IGVjbGlwc2VDZW50ZXJCdXR0b24uY2xpY2tlZCgp
CisgICAgfQorCiAgICAgLy8gUGVyc2lzdGVudCBnYW1lcGFkIGhpbnQgYmFyLCBmaXhlZCBhdCB0
aGUgYm90dG9tLiBHcmlkIGJvdHRvbU1hcmdpbiBjbGVhcnMgaXQuCiAgICAgVmJIaW50QmFyIHsK
ICAgICAgICAgaWQ6IHBjSGludEJhcgpAQCAtMjY5LDcgKzI5Niw3IEBAIENlbnRlcmVkR3JpZFZp
ZXcgewogCiAgICAgZnVuY3Rpb24gY3JlYXRlTW9kZWwoKQogICAgIHsKLSAgICAgICAgdmFyIG1v
ZGVsID0gUXQuY3JlYXRlUW1sT2JqZWN0KCdpbXBvcnQgQ29tcHV0ZXJNb2RlbCAxLjA7IENvbXB1
dGVyTW9kZWwge30nLCBwYXJlbnQsICcnKQorICAgICAgICB2YXIgbW9kZWwgPSBRdC5jcmVhdGVR
bWxPYmplY3QoJ2ltcG9ydCBDb21wdXRlck1vZGVsIDEuMDsgQ29tcHV0ZXJNb2RlbCB7fScsIHBj
R3JpZCwgJycpCiAgICAgICAgIG1vZGVsLmluaXRpYWxpemUoQ29tcHV0ZXJNYW5hZ2VyKQogICAg
ICAgICBtb2RlbC5wYWlyaW5nQ29tcGxldGVkLmNvbm5lY3QocGFpcmluZ0NvbXBsZXRlKQogICAg
ICAgICBtb2RlbC5jb25uZWN0aW9uVGVzdENvbXBsZXRlZC5jb25uZWN0KHRlc3RDb25uZWN0aW9u
RGlhbG9nLmNvbm5lY3Rpb25UZXN0Q29tcGxldGUpCkBAIC0zMDEsNyArMzI4LDcgQEAgQ2VudGVy
ZWRHcmlkVmlldyB7CiAKICAgICBkZWxlZ2F0ZTogTmF2aWdhYmxlSXRlbURlbGVnYXRlIHsKICAg
ICAgICAgaWQ6IHBjRGVsZWdhdGUKLSAgICAgICAgd2lkdGg6IDQzMDsgaGVpZ2h0OiAyNDI7Cisg
ICAgICAgIHdpZHRoOiBwY0dyaWQuY2VsbFdpZHRoIC0gMjA7IGhlaWdodDogMjQyOwogICAgICAg
ICBncmlkOiBwY0dyaWQKIAogICAgICAgICAvLyBUaGUgTWF0ZXJpYWwgc3R5bGUgcGFpbnRzIGFu
IGFsd2F5cy12aXNpYmxlCkBAIC00NDQsNyArNDcxLDcgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAg
ICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBtb2RlbC5vbmxpbmUgJiYgbW9kZWwucGFp
cmVkLAogICAgICAgICAgICAgICAgICAgICAgICAgdHJpZ2dlcjogZnVuY3Rpb24oKSB7CiAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgdmFyIGNvbXBvbmVudCA9IFF0LmNyZWF0ZUNvbXBvbmVu
dCgiQXBwVmlldy5xbWwiKQotICAgICAgICAgICAgICAgICAgICAgICAgICAgIHZhciBhcHBWaWV3
ID0gY29tcG9uZW50LmNyZWF0ZU9iamVjdChzdGFja1ZpZXcsIHsiY29tcHV0ZXJJbmRleCI6IGlu
ZGV4LCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUsICJzaG93SGlkZGVuR2FtZXMiOiB0cnVlLCAi
aG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhvc3RUeXBlIjogbW9kZWwuaG9zdFR5cGUsICJo
b3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0fSkKKyAgICAgICAgICAgICAgICAgICAgICAg
ICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3LCB7ImNv
bXB1dGVySW5kZXgiOiBpbmRleCwgImNyaW1zb25Ib3N0IjogY29tcHV0ZXJNb2RlbC5jcmltc29u
SG9zdChpbmRleCksICJvYmplY3ROYW1lIjogbW9kZWwubmFtZSwgInNob3dIaWRkZW5HYW1lcyI6
IHRydWUsICJob3N0T25saW5lIjogbW9kZWwub25saW5lLCAiaG9zdFR5cGUiOiBtb2RlbC5ob3N0
VHlwZSwgImhvc3RUcmFuc3BvcnQiOiBtb2RlbC50cmFuc3BvcnR9KQogICAgICAgICAgICAgICAg
ICAgICAgICAgICAgIHN0YWNrVmlldy5wdXNoKGFwcFZpZXcpCiAgICAgICAgICAgICAgICAgICAg
ICAgICB9CiAgICAgICAgICAgICAgICAgICAgIH0sCkBAIC01MzUsNyArNTYyLDcgQEAgQ2VudGVy
ZWRHcmlkVmlldyB7CiAgICAgICAgICAgICAgICAgZWxzZSBpZiAobW9kZWwucGFpcmVkKSB7CiAg
ICAgICAgICAgICAgICAgICAgIC8vIGdvIHRvIGdhbWUgdmlldwogICAgICAgICAgICAgICAgICAg
ICB2YXIgY29tcG9uZW50ID0gUXQuY3JlYXRlQ29tcG9uZW50KCJBcHBWaWV3LnFtbCIpCi0gICAg
ICAgICAgICAgICAgICAgIHZhciBhcHBWaWV3ID0gY29tcG9uZW50LmNyZWF0ZU9iamVjdChzdGFj
a1ZpZXcsIHsiY29tcHV0ZXJJbmRleCI6IGluZGV4LCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUs
ICJob3N0T25saW5lIjogbW9kZWwub25saW5lLCAiaG9zdFR5cGUiOiBtb2RlbC5ob3N0VHlwZSwg
Imhvc3RUcmFuc3BvcnQiOiBtb2RlbC50cmFuc3BvcnR9KQorICAgICAgICAgICAgICAgICAgICB2
YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3LCB7ImNvbXB1dGVy
SW5kZXgiOiBpbmRleCwgImNyaW1zb25Ib3N0IjogY29tcHV0ZXJNb2RlbC5jcmltc29uSG9zdChp
bmRleCksICJvYmplY3ROYW1lIjogbW9kZWwubmFtZSwgImhvc3RPbmxpbmUiOiBtb2RlbC5vbmxp
bmUsICJob3N0VHlwZSI6IG1vZGVsLmhvc3RUeXBlLCAiaG9zdFRyYW5zcG9ydCI6IG1vZGVsLnRy
YW5zcG9ydH0pCiAgICAgICAgICAgICAgICAgICAgIHN0YWNrVmlldy5wdXNoKGFwcFZpZXcpCiAg
ICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgIGVsc2UgewpAQCAtNjE2LDcgKzY0Myw3
IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgICAgICBvblNlbGVjdGVkQ2hhbmdlZDogYWRkUGNE
YXNoZWRCb3JkZXIucmVxdWVzdFBhaW50KCkKICAgICAgICAgeDogKHBjR3JpZC5jb3VudCAlIGNv
bHVtbnMpICogcGNHcmlkLmNlbGxXaWR0aAogICAgICAgICB5OiBNYXRoLmZsb29yKHBjR3JpZC5j
b3VudCAvIGNvbHVtbnMpICogcGNHcmlkLmNlbGxIZWlnaHQKLSAgICAgICAgd2lkdGg6IDQzMAor
ICAgICAgICB3aWR0aDogcGNHcmlkLmNlbGxXaWR0aC0yMAogICAgICAgICBoZWlnaHQ6IDI0Mgog
ICAgICAgICB6OiAyCiAKQEAgLTYyNSw3ICs2NTIsNyBAQCBDZW50ZXJlZEdyaWRWaWV3IHsKICAg
ICAgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50CiAgICAgICAgICAgICByYWRpdXM6IDIwCiAg
ICAgICAgICAgICBjb2xvcjogYWRkUGNDYXJkU2xvdC5oaWdobGlnaHRlZCA/IFZiVG9rZW5zLmJn
RWxldiA6ICJ0cmFuc3BhcmVudCIKLSAgICAgICAgICAgIEJlaGF2aW9yIG9uIGNvbG9yIHsgQ29s
b3JBbmltYXRpb24geyBkdXJhdGlvbjogMTIwIH0gfQorICAgICAgICAgICAgQmVoYXZpb3Igb24g
Y29sb3IgeyBDb2xvckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVk
ID8gMTIwIDogMCB9IH0KICAgICAgICAgfQogCiAgICAgICAgIENhbnZhcyB7CmRpZmYgLS1naXQg
YS9hcHAvZ3VpL1F1aWNrTWVudS5xbWwgYi9hcHAvZ3VpL1F1aWNrTWVudS5xbWwKaW5kZXggYjAz
M2QyNi4uODcyZmZmOSAxMDA2NDQKLS0tIGEvYXBwL2d1aS9RdWlja01lbnUucW1sCisrKyBiL2Fw
cC9ndWkvUXVpY2tNZW51LnFtbApAQCAtMjEsNiArMjEsMTAgQEAgUmVjdGFuZ2xlIHsKICAgICBy
YWRpdXM6IFZiVG9rZW5zLnJhZGl1c1dpbmRvdwogICAgIGJvcmRlci5jb2xvcjogVmJUb2tlbnMu
ZGl2aWRlcgogICAgIGJvcmRlci53aWR0aDogMQorICAgIGdyYWRpZW50OiBHcmFkaWVudCB7Cisg
ICAgICAgIEdyYWRpZW50U3RvcCB7cG9zaXRpb246MDtjb2xvcjpWYlRva2Vucy5nbGFzc1RvcH0K
KyAgICAgICAgR3JhZGllbnRTdG9wIHtwb3NpdGlvbjoxO2NvbG9yOlZiVG9rZW5zLnN1cmZhY2VS
YWlzZWR9CisgICAgfQogICAgIHZpc2libGU6IHRydWUgIC8vIEFsd2F5cyB2aXNpYmxlIHdoZW4g
Y3JlYXRlZAogICAgIG9wYWNpdHk6IDEuMAogICAgIApAQCAtMzYsNyArNDAsNyBAQCBSZWN0YW5n
bGUgewogICAgIAogICAgIC8vIEFuaW1hdGlvbiBmb3Igc21vb3RoIHNob3cvaGlkZQogICAgIEJl
aGF2aW9yIG9uIG9wYWNpdHkgewotICAgICAgICBOdW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjog
MjAwIH0KKyAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRpb246IFZiVG9rZW5zLm1vdGlv
bkVuYWJsZWQgPyAyMDAgOiAwIH0KICAgICB9CiAgICAgCiAgICAgLy8gSGFuZGxlIGtleWJvYXJk
IGlucHV0IGZvciBuYXZpZ2F0aW9uCkBAIC0xMzksNyArMTQzLDcgQEAgUmVjdGFuZ2xlIHsKICAg
ICAgICAgICAgICAgICAvLyBTaGVldC1yb3cgcmVjaXBlIOKAlCBmb2N1c2VkRmlsbCBzdXJmYWNl
ICsgYWNjZW50IGJvcmRlciB3aGVuCiAgICAgICAgICAgICAgICAgLy8gY3VycmVudCAoZmxhdCB2
YXJpYW50OiB0aGUgb3V0ZXIgZ2xvdyB3b3VsZCBjbGlwIGluc2lkZSB0aGlzIHNjcm9sbGluZwog
ICAgICAgICAgICAgICAgIC8vIGNsaXBwZWQgbGlzdCwgc28gdGhlIHJpbmcgaXMgYm9yZGVyLW9u
bHkgaGVyZSkuCi0gICAgICAgICAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAg
ICAgICAgICAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgICAgICAg
ICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ29udHJvbAogICAgICAgICAgICAgICAgICAg
ICBjb2xvcjogbWVudVJvdy5kb3duID8gUXQuZGFya2VyKFZiVG9rZW5zLmludGVyYWN0aXZlRm9j
dXMsIDEuMTUpCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiAobWVu
dVJvdy5hY3RpdmUgPyBWYlRva2Vucy5pbnRlcmFjdGl2ZUZvY3VzIDogInRyYW5zcGFyZW50IikK
QEAgLTIyOSw3ICsyMzMsNyBAQCBSZWN0YW5nbGUgewogICAgICAgICAgICAgICAgIGxlZnRQYWRk
aW5nOiAxMgogICAgICAgICAgICAgICAgIHJpZ2h0UGFkZGluZzogMTIKICAgICAgICAgICAgICAg
ICAvLyBUb2tlbiBmaWVsZCDigJQgd2luZG93LWRhcmsgd2VsbCArIGFjY2VudCBmb2N1cyBib3Jk
ZXIuCi0gICAgICAgICAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgICAg
ICAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgICAgICAgICAgICAg
IGNvbG9yOiBWYlRva2Vucy5zdXJmYWNlQmFzZQogICAgICAgICAgICAgICAgICAgICBib3JkZXIu
Y29sb3I6IHNlbmRUZXh0RmllbGQuYWN0aXZlRm9jdXMgPyBWYlRva2Vucy5hY2NlbnQgOiBWYlRv
a2Vucy5kaXZpZGVyCiAgICAgICAgICAgICAgICAgICAgIGJvcmRlci53aWR0aDogVmJUb2tlbnMu
Zm9jdXNCb3JkZXIKQEAgLTM3Miw3ICszNzYsNyBAQCBSZWN0YW5nbGUgewogICAgICAgICBvcGFj
aXR5OiBzaG93VG9hc3QgPyAxLjAgOiAwLjAKIAogICAgICAgICBCZWhhdmlvciBvbiBvcGFjaXR5
IHsKLSAgICAgICAgICAgIE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiAyMDAgfQorICAgICAg
ICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRpb246IFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQg
PyAyMDAgOiAwIH0KICAgICAgICAgfQogCiAgICAgICAgIFRleHQgewpAQCAtNDQ5LDcgKzQ1Myw3
IEBAIFJlY3RhbmdsZSB7CiAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJRdWl0IGdhbWUiKQogICAg
ICAgICAgICAgaWNvbjogInBvd2VyIgogICAgICAgICAgICAgYWN0aW9uOiAicXVpdCIKLSAgICAg
ICAgICAgIGRlc2NyaXB0aW9uOiBxc1RyKCJRdWl0IHRoZSBnYW1lIG9uIHRoZSBob3N0IGFuZCBy
ZXR1cm4gdG8gVmliZW1pcyIpCisgICAgICAgICAgICBkZXNjcmlwdGlvbjogcXNUcigiUXVpdCB0
aGUgZ2FtZSBvbiB0aGUgaG9zdCBhbmQgcmV0dXJuIHRvIEVjbGlwc2UiKQogICAgICAgICB9CiAg
ICAgICAgIExpc3RFbGVtZW50IHsKICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlNlcnZlciBjb21t
YW5kcyIpCkBAIC03MTQsNCArNzE4LDMgQEAgUmVjdGFuZ2xlIHsKICAgICAgICAgfQogICAgIH0K
IH0KLQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9TZXJ2ZXJDb21tYW5kcy5xbWwgYi9hcHAvZ3VpL1Nl
cnZlckNvbW1hbmRzLnFtbAppbmRleCBhMGJhNDdlLi45Y2U4M2QwIDEwMDY0NAotLS0gYS9hcHAv
Z3VpL1NlcnZlckNvbW1hbmRzLnFtbAorKysgYi9hcHAvZ3VpL1NlcnZlckNvbW1hbmRzLnFtbApA
QCAtMTU1LDcgKzE1NSw3IEBAIEdyb3VwQm94IHsKICAgICB9CiAKICAgICAvLyBDb25maXJtYXRp
b24gZGlhbG9nCi0gICAgRGlhbG9nIHsKKyAgICBOYXZpZ2FibGVEaWFsb2cgewogICAgICAgICBp
ZDogY29uZmlybURpYWxvZwogICAgICAgICBhbmNob3JzLmNlbnRlckluOiBwYXJlbnQKICAgICAg
ICAgd2lkdGg6IE1hdGgubWluKDQwMCwgcGFyZW50LndpZHRoICogMC45KQpAQCAtMTY4LDcgKzE2
OCw3IEBAIEdyb3VwQm94IHsKICAgICAgICAgdGl0bGU6IHFzVHIoIkNvbmZpcm0gQ29tbWFuZCIp
CiAgICAgICAgIG1vZGFsOiB0cnVlCiAKLSAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsK
KyAgICAgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgewogICAgICAgICAgICAgY29s
b3I6IFZiVG9rZW5zLnN1cmZhY2VSYWlzZWQKICAgICAgICAgICAgIHJhZGl1czogVmJUb2tlbnMu
cmFkaXVzRGlhbG9nCiAgICAgICAgICAgICBib3JkZXIud2lkdGg6IDEKQEAgLTIxNiw3ICsyMTYs
NyBAQCBHcm91cEJveCB7CiAgICAgfQogCiAgICAgLy8gQ3VzdG9tIGNvbW1hbmQgZGlhbG9nCi0g
ICAgRGlhbG9nIHsKKyAgICBOYXZpZ2FibGVEaWFsb2cgewogICAgICAgICBpZDogY3VzdG9tQ29t
bWFuZERpYWxvZwogICAgICAgICBhbmNob3JzLmNlbnRlckluOiBwYXJlbnQKICAgICAgICAgd2lk
dGg6IE1hdGgubWluKDQwMCwgcGFyZW50LndpZHRoICogMC45KQpAQCAtMjI1LDcgKzIyNSw3IEBA
IEdyb3VwQm94IHsKICAgICAgICAgdGl0bGU6IHFzVHIoIkN1c3RvbSBDb21tYW5kIikKICAgICAg
ICAgbW9kYWw6IHRydWUKIAotICAgICAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgeworICAgICAg
ICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgICAgICBjb2xvcjogVmJU
b2tlbnMuc3VyZmFjZVJhaXNlZAogICAgICAgICAgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNE
aWFsb2cKICAgICAgICAgICAgIGJvcmRlci53aWR0aDogMQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9T
ZXR0aW5nc1ZpZXcucW1sIGIvYXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sCmluZGV4IDQ5NGUzNWIu
LmU5ODkxNmIgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvU2V0dGluZ3NWaWV3LnFtbAorKysgYi9hcHAv
Z3VpL1NldHRpbmdzVmlldy5xbWwKQEAgLTEzLDkgKzEzLDExIEBAIGltcG9ydCBBdXRvVXBkYXRl
Q2hlY2tlciAxLjAKIGltcG9ydCBVaVNvdW5kTWFuYWdlciAxLjAKIAogaW1wb3J0IFZpYmVtaXMu
UmVkZXNpZ24gMS4wCitpbXBvcnQgRWNsaXBzZVByb2ZpbGVzIDEuMAogCiBJdGVtIHsKICAgICBp
ZDogc2V0dGluZ3NQYWdlCisgICAgQ3JpbXNvbkJhY2tncm91bmRQaWNrZXIgeyBpZDpiYWNrZ3Jv
dW5kUGlja2VyIH0KICAgICBvYmplY3ROYW1lOiBxc1RyKCJTZXR0aW5ncyIpCiAKICAgICAvLyBM
Qi9SQiBjYXRlZ29yeSBmbGlwcyBjaGFuZ2UgYGNhdGVnb3J5YCB3aXRob3V0IG1vdmluZyBpdGVt
IGZvY3VzLApAQCAtNjgsNyArNzAsNyBAQCBJdGVtIHsKICAgICBjb21wb25lbnQgVmJTZXR0aW5n
c0NhcmQ6IEdyb3VwQm94IHsKICAgICAgICAgcGFkZGluZzogVmJUb2tlbnMuc3BhY2U1CiAgICAg
ICAgIGxhYmVsOiBJdGVtIHt9Ci0gICAgICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7CisgICAg
ICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsKICAgICAgICAgICAgIGNvbG9yOiBW
YlRva2Vucy5iZ0VsZXYKICAgICAgICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ2FyZAog
ICAgICAgICAgICAgYm9yZGVyLndpZHRoOiAxCkBAIC0xNjIsMTQgKzE2NCwxNCBAQCBJdGVtIHsK
ICAgICAgICAgICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRp
Y2FsQ2VudGVyCiAgICAgICAgICAgICAgICAgICAgIHg6IHRvZ2dsZVJvb3QuY2hlY2tlZCA/IHBh
cmVudC53aWR0aCAtIHdpZHRoIC0gNCA6IDQKICAgICAgICAgICAgICAgICAgICAgY29sb3I6IHRv
Z2dsZVJvb3QuY2hlY2tlZCA/IFZiVG9rZW5zLnRleHRPbkFjY2VudCA6IFZiVG9rZW5zLnRleHRE
aW0KLSAgICAgICAgICAgICAgICAgICAgQmVoYXZpb3Igb24geCB7IE51bWJlckFuaW1hdGlvbiB7
IGR1cmF0aW9uOiAxMjAgfSB9CisgICAgICAgICAgICAgICAgICAgIEJlaGF2aW9yIG9uIHggeyBO
dW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjogVmJUb2tlbnMubW90aW9uRW5hYmxlZCA/IDEyMCA6
IDAgfSB9CiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgfQogICAgICAgICB9CiAgICAg
fQogCiAgICAgLy8gRnVsbC1ibGVlZCB3aW5kb3cgYmFja2dyb3VuZC4KLSAgICBSZWN0YW5nbGUg
eyBhbmNob3JzLmZpbGw6IHBhcmVudDsgY29sb3I6IFZiVG9rZW5zLmJnV2luZG93IH0KKyAgICBD
cmltc29uR2xhc3NCYWNrZHJvcCB7IGFuY2hvcnMuZmlsbDogcGFyZW50IH0KIAogICAgIC8vIFN0
YWNrVmlldyBhdHRhY2hlZCBoYW5kbGVycyBtdXN0IHN0YXkgb24gdGhlIHB1c2hlZCBwYWdlICh0
aGUgSXRlbSByb290KS4KICAgICBTdGFja1ZpZXcub25BY3RpdmF0ZWQ6IHsKQEAgLTM0NiwxMiAr
MzQ4LDEzIEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICB7IGljb246ICJnYW1lcGFkIiwg
ICBsYWJlbDogcXNUcigiSW5wdXQgJiBnYW1lcGFkIikgfSwKICAgICAgICAgICAgICAgICAgICAg
eyBpY29uOiAic3RyZWFtaW5nIiwgbGFiZWw6IHFzVHIoIlN0cmVhbWluZyIpIH0sCiAgICAgICAg
ICAgICAgICAgICAgIHsgaWNvbjogImFwcHMiLCAgICAgIGxhYmVsOiBxc1RyKCJBcHAgJiBVSSIp
IH0sCi0gICAgICAgICAgICAgICAgICAgIHsgaWNvbjogImFkdmFuY2VkIiwgIGxhYmVsOiBxc1Ry
KCJBZHZhbmNlZCIpIH0KKyAgICAgICAgICAgICAgICAgICAgeyBpY29uOiAiYWR2YW5jZWQiLCAg
bGFiZWw6IHFzVHIoIkFkdmFuY2VkIikgfSwKKyAgICAgICAgICAgICAgICAgICAgeyBpY29uOiAi
YWR2YW5jZWQiLCBsYWJlbDogcXNUcigiU3lzdGVtIENvbnRyb2xzIikgfQogICAgICAgICAgICAg
ICAgIF0KICAgICAgICAgICAgICAgICBkZWxlZ2F0ZTogQnV0dG9uIHsKICAgICAgICAgICAgICAg
ICAgICAgaWQ6IGNhdEJ1dHRvbgogICAgICAgICAgICAgICAgICAgICB3aWR0aDogc2lkZWJhckNv
bHVtbi53aWR0aAotICAgICAgICAgICAgICAgICAgICBoZWlnaHQ6IDU4CisgICAgICAgICAgICAg
ICAgICAgIGhlaWdodDogTWF0aC5taW4oNTgsTWF0aC5tYXgoNDQsKHNpZGViYXIuaGVpZ2h0LTY0
LShzaWRlYmFyUmVwZWF0ZXIuY291bnQtMSkqVmJUb2tlbnMuc3BhY2UyKS9zaWRlYmFyUmVwZWF0
ZXIuY291bnQpKQogICAgICAgICAgICAgICAgICAgICBwYWRkaW5nOiAwCiAgICAgICAgICAgICAg
ICAgICAgIGxlZnRQYWRkaW5nOiBWYlRva2Vucy5zcGFjZTQKICAgICAgICAgICAgICAgICAgICAg
cmlnaHRQYWRkaW5nOiBWYlRva2Vucy5zcGFjZTQKQEAgLTM3OSw3ICszODIsNyBAQCBJdGVtIHsK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICBib3JkZXIud2lkdGg6IChjYXRCdXR0b24uc2Vs
ZWN0ZWQgfHwgY2F0QnV0dG9uLmFjdGl2ZUZvY3VzKSA/IFZiVG9rZW5zLmZvY3VzQm9yZGVyIDog
MQogICAgICAgICAgICAgICAgICAgICAgICAgICAgIGJvcmRlci5jb2xvcjogKGNhdEJ1dHRvbi5z
ZWxlY3RlZCB8fCBjYXRCdXR0b24uYWN0aXZlRm9jdXMpID8gVmJUb2tlbnMuYWNjZW50IDogVmJU
b2tlbnMuc3Ryb2tlCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYW50aWFsaWFzaW5nOiB0
cnVlCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xv
ckFuaW1hdGlvbiB7IGR1cmF0aW9uOiAxMjAgfSB9CisgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xvckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vu
cy5tb3Rpb25FbmFibGVkID8gMTIwIDogMCB9IH0KICAgICAgICAgICAgICAgICAgICAgICAgIH0K
ICAgICAgICAgICAgICAgICAgICAgfQogCkBAIC01MjQsNyArNTI3LDcgQEAgSXRlbSB7CiAKICAg
ICAgICAgTnVtYmVyQW5pbWF0aW9uIG9uIGNvbnRlbnRZIHsKICAgICAgICAgICAgIGlkOiBhdXRv
U2Nyb2xsQW5pbWF0aW9uCi0gICAgICAgICAgICBkdXJhdGlvbjogMTAwCisgICAgICAgICAgICBk
dXJhdGlvbjogVmJUb2tlbnMubW90aW9uRW5hYmxlZCA/IDEwMCA6IDAKICAgICAgICAgfQogCiAg
ICAgICAgIFdpbmRvdy5vbkFjdGl2ZUZvY3VzSXRlbUNoYW5nZWQ6IHsKQEAgLTU3MSw2ICs1NzQs
MTIgQEAgSXRlbSB7CiAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMudGV4dAogICAgICAgICB9
CiAKKyAgICAgICAgRWNsaXBzZVN5c3RlbVNldHRpbmdzIHsKKyAgICAgICAgICAgIHdpZHRoOiBw
YXJlbnQud2lkdGggLSAocGFyZW50LmxlZnRQYWRkaW5nICsgcGFyZW50LnJpZ2h0UGFkZGluZykK
KyAgICAgICAgICAgIHZpc2libGU6IHNldHRpbmdzUGFnZS5jYXRlZ29yeSA9PT0gNgorICAgICAg
ICAgICAgYWN0aXZlOiBzZXR0aW5nc1BhZ2UudmlzaWJsZSAmJiB2aXNpYmxlCisgICAgICAgIH0K
KwogICAgICAgICAvLyAtLS0tIExpdmUgc3RyZWFtIHN1bW1hcnkgbGluZSAocmVkZXNpZ24pLCBy
ZWxvY2F0ZWQgaGVyZSAod2FzIGluc2lkZSBCYXNpYwogICAgICAgICAvLyBTZXR0aW5ncykgc28g
aXQgc2l0cyBkaXJlY3RseSB1bmRlciB0aGUgIlZpZGVvIiB0aXRsZSBsaWtlIHRoZSBkZXNpZ24u
CiAgICAgICAgIC8vIE51bWJlcnMgcmVuZGVyIGluIGFjY2VudDsgdGhlIHJlc3Qgc3RheXMgZGlt
LiBDb250ZW50L2JpbmRpbmdzIHVuY2hhbmdlZC4KQEAgLTYwMiw3ICs2MTEsNyBAQCBJdGVtIHsK
ICAgICAgICAgICAgIHdpZHRoOiAocGFyZW50LndpZHRoIC0gKHBhcmVudC5sZWZ0UGFkZGluZyAr
IHBhcmVudC5yaWdodFBhZGRpbmcpKQogICAgICAgICAgICAgcGFkZGluZzogVmJUb2tlbnMuc3Bh
Y2U1CiAgICAgICAgICAgICBsYWJlbDogSXRlbSB7fQotICAgICAgICAgICAgYmFja2dyb3VuZDog
UmVjdGFuZ2xlIHsKKyAgICAgICAgICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsK
ICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYmdFbGV2CiAgICAgICAgICAgICAgICAg
cmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDYXJkCiAgICAgICAgICAgICAgICAgYm9yZGVyLndpZHRo
OiAxCkBAIC03NTYsNyArNzY1LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAv
LyB0b3dhcmQgdGhlIGNvbnRyb2wncyBpbXBsaWNpdCBoZWlnaHQsIHNvIHRoZSB2YWx1ZSB0ZXh0
IHVzZWQgdG8gcmVuZGVyCiAgICAgICAgICAgICAgICAgICAgICAgICAvLyBwYXN0IHRoZSBjYXJk
J3MgYm90dG9tIGVkZ2UuIFNpemUgdGhlIGNhcmQgdG8gY29udGVudCArIGJvdGggbWFyZ2lucy4K
ICAgICAgICAgICAgICAgICAgICAgICAgIGltcGxpY2l0SGVpZ2h0OiByZXNvbHV0aW9uQ2FyZENv
bnRlbnQuaW1wbGljaXRIZWlnaHQgKyA0OAotICAgICAgICAgICAgICAgICAgICAgICAgYmFja2dy
b3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgICAgICAgICAgICAgIGJhY2tncm91bmQ6IENy
aW1zb25HbGFzc1BhbmVsIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb2xvcjogVmJU
b2tlbnMuYmdFbGV2CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcmFkaXVzOiBWYlRva2Vu
cy5yYWRpdXNDYXJkCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYm9yZGVyLndpZHRoOiBy
ZXNvbHV0aW9uQ29tYm9Cb3guYWN0aXZlRm9jdXMgPyBWYlRva2Vucy5mb2N1c0JvcmRlciA6IDEK
QEAgLTExMjUsNyArMTEzNCw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAgICAgLy8g
U2FtZSBjb250ZW50LW1hcmdpbiBzaXppbmcgZml4IGFzIHRoZSBSZXNvbHV0aW9uIGNhcmQg4oCU
IGtlZXBzCiAgICAgICAgICAgICAgICAgICAgICAgICAvLyB0aGUgZnJhbWUtcmF0ZSB2YWx1ZSB0
ZXh0IGluc2lkZSB0aGUgY2FyZCBib3VuZHMuCiAgICAgICAgICAgICAgICAgICAgICAgICBpbXBs
aWNpdEhlaWdodDogZnBzQ2FyZENvbnRlbnQuaW1wbGljaXRIZWlnaHQgKyA0OAotICAgICAgICAg
ICAgICAgICAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgICAgICAg
ICAgICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsKICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYmdFbGV2CiAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDYXJkCiAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgYm9yZGVyLndpZHRoOiBmcHNDb21ib0JveC5hY3RpdmVGb2N1cyA/IFZiVG9rZW5zLmZv
Y3VzQm9yZGVyIDogMQpAQCAtMTUxMyw3ICsxNTIyLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAg
ICAgfQogCiAgICAgICAgICAgICAgICAgLy8gLS0tLSBWaWRlbyBiaXRyYXRlIGNhcmQgKHJlZGVz
aWduKSAtLS0tCi0gICAgICAgICAgICAgICAgUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgICAgICBD
cmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgICAgICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lk
dGgKICAgICAgICAgICAgICAgICAgICAgaGVpZ2h0OiBiaXRyYXRlQ2FyZENvbHVtbi5pbXBsaWNp
dEhlaWdodCArIDUyCiAgICAgICAgICAgICAgICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVz
Q2FyZApAQCAtMTY3Myw3ICsxNjgyLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgIGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlcgog
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB4OiBhZGFwdGl2ZUJpdHJhdGVDaGVjay5j
aGVja2VkID8gcGFyZW50LndpZHRoIC0gd2lkdGggLSA0IDogNAogICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICBjb2xvcjogYWRhcHRpdmVCaXRyYXRlQ2hlY2suY2hlY2tlZCA/IFZiVG9r
ZW5zLnRleHRPbkFjY2VudCA6IFZiVG9rZW5zLnRleHREaW0KLSAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgQmVoYXZpb3Igb24geCB7IE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiAx
MjAgfSB9CisgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJlaGF2aW9yIG9uIHggeyBO
dW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjogVmJUb2tlbnMubW90aW9uRW5hYmxlZCA/IDEyMCA6
IDAgfSB9CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAg
ICAgICAgfQogICAgICAgICAgICAgICAgICAgICB9CkBAIC0xNjgxLDcgKzE2OTAsNyBAQCBJdGVt
IHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAg
ICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRp
cC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNU
cigiV2hlbiB0aGUgbmV0d29yayBjYW4ndCBzdXN0YWluIHRoZSBjb25maWd1cmVkIGJpdHJhdGUg
YW5kIHRoZSBzdHJlYW0gY29sbGFwc2VzLCBWaWJlbWlzIGF1dG9tYXRpY2FsbHkgcmVjb25uZWN0
cyBhdCBhIGxvd2VyIGJpdHJhdGUgdW50aWwgdGhlIHN0cmVhbSBpcyB1c2FibGUuIFlvdXIgc2F2
ZWQgYml0cmF0ZSBzZXR0aW5nIGlzIG5ldmVyIGNoYW5nZWQuIikKKyAgICAgICAgICAgICAgICAg
ICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJXaGVuIHRoZSBuZXR3b3JrIGNhbid0IHN1c3RhaW4gdGhl
IGNvbmZpZ3VyZWQgYml0cmF0ZSBhbmQgdGhlIHN0cmVhbSBjb2xsYXBzZXMsIEVjbGlwc2UgYXV0
b21hdGljYWxseSByZWNvbm5lY3RzIGF0IGEgbG93ZXIgYml0cmF0ZSB1bnRpbCB0aGUgc3RyZWFt
IGlzIHVzYWJsZS4gWW91ciBzYXZlZCBiaXRyYXRlIHNldHRpbmcgaXMgbmV2ZXIgY2hhbmdlZC4i
KQogICAgICAgICAgICAgICAgIH0KIAogICAgICAgICAgICAgICAgIC8vIFZpYmVtaXMgKHBlcmYg
Z3VpZGFuY2UpOiBhZHZpc2Ugd2hlbiB0aGUgYml0cmF0ZSBpcyBzZXQgd2VsbCBhYm92ZSB0aGUg
cmVjb21tZW5kZWQKQEAgLTE5MjksNyArMTkzOCw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxD
ZW50ZXIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgeDogdnN5bmNDaGVjay5jaGVj
a2VkID8gcGFyZW50LndpZHRoIC0gd2lkdGggLSA0IDogNAogICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICBjb2xvcjogdnN5bmNDaGVjay5jaGVja2VkID8gVmJUb2tlbnMudGV4dE9uQWNj
ZW50IDogVmJUb2tlbnMudGV4dERpbQotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBC
ZWhhdmlvciBvbiB4IHsgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgQmVoYXZpb3Igb24geCB7IE51bWJlckFuaW1hdGlv
biB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8gMTIwIDogMCB9IH0KICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAg
ICAgICAgICAgICAgICAgIH0KQEAgLTIwMjQsNyArMjAzMyw3IEBAIEl0ZW0gewogICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVy
dGljYWxDZW50ZXIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgeDogZnJhbWVQYWNp
bmdDaGVjay5jaGVja2VkID8gcGFyZW50LndpZHRoIC0gd2lkdGggLSA0IDogNAogICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICBjb2xvcjogZnJhbWVQYWNpbmdDaGVjay5jaGVja2VkID8g
VmJUb2tlbnMudGV4dE9uQWNjZW50IDogVmJUb2tlbnMudGV4dERpbQotICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICBCZWhhdmlvciBvbiB4IHsgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRp
b246IDEyMCB9IH0KKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQmVoYXZpb3Igb24g
eCB7IE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8g
MTIwIDogMCB9IH0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAg
ICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgIH0KQEAgLTIwOTYsNyArMjEwNSw3IEBA
IEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2Fs
Q2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIKICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgeDogdnJyQ2hlY2suY2hlY2tlZCA/IHBhcmVudC53aWR0aCAtIHdpZHRoIC0gNCA6IDQK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY29sb3I6IHZyckNoZWNrLmNoZWNrZWQg
PyBWYlRva2Vucy50ZXh0T25BY2NlbnQgOiBWYlRva2Vucy50ZXh0RGltCi0gICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgIEJlaGF2aW9yIG9uIHggeyBOdW1iZXJBbmltYXRpb24geyBkdXJh
dGlvbjogMTIwIH0gfQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBCZWhhdmlvciBv
biB4IHsgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRpb246IFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQg
PyAxMjAgOiAwIH0gfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAg
ICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgfQpAQCAtMjQ4Miw3ICsyNDkxLDcg
QEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAuZGVsYXk6IDEwMDAKICAgICAg
ICAgICAgICAgICAgICAgVG9vbFRpcC50aW1lb3V0OiA1MDAwCiAgICAgICAgICAgICAgICAgICAg
IFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAotICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRl
eHQ6IHFzVHIoIklmIGEgc3RyZWFtIGVuZHMgdW5leHBlY3RlZGx5IChhIG5ldHdvcmsgYmxpcCBv
ciB0aGUgaG9zdCB3YWtpbmcpLCBWaWJlbWlzIHdpbGwgdHJ5IHRvIHJlY29ubmVjdCBhdXRvbWF0
aWNhbGx5LiIpCisgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiSWYgYSBz
dHJlYW0gZW5kcyB1bmV4cGVjdGVkbHkgKGEgbmV0d29yayBibGlwIG9yIHRoZSBob3N0IHdha2lu
ZyksIEVjbGlwc2Ugd2lsbCB0cnkgdG8gcmVjb25uZWN0IGF1dG9tYXRpY2FsbHkuIikKICAgICAg
ICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAgICAgICAgIH0KQEAgLTI1NDYsNyArMjU1NSw3
IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMwogCiAg
ICAgICAgICAgICAgICAgVmJTZWN0aW9uSGVhZGVyIHsKLSAgICAgICAgICAgICAgICAgICAgdGV4
dDogcXNUcigiVmliZW1pcyBTdHJlYW1pbmcgRW5oYW5jZW1lbnRzIikKKyAgICAgICAgICAgICAg
ICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBTdHJlYW1pbmcgRW5oYW5jZW1lbnRzIikKICAgICAg
ICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICBMYWJlbCB7CkBAIC0yNzc2LDcgKzI3ODUs
NyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgIFZiVG9nZ2xlUm93IHsKICAgICAgICAgICAg
ICAgICAgICAgaWQ6IG11dGVPbkZvY3VzTG9zc0NoZWNrCi0gICAgICAgICAgICAgICAgICAgIHRl
eHQ6IHFzVHIoIk11dGUgYXVkaW8gc3RyZWFtIHdoZW4gVmliZW1pcyBpcyBub3QgdGhlIGFjdGl2
ZSB3aW5kb3ciKQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJNdXRlIGF1ZGlvIHN0
cmVhbSB3aGVuIEVjbGlwc2UgaXMgbm90IHRoZSBhY3RpdmUgd2luZG93IikKICAgICAgICAgICAg
ICAgICAgICAgdmlzaWJsZTogU3lzdGVtUHJvcGVydGllcy5oYXNEZXNrdG9wRW52aXJvbm1lbnQK
ICAgICAgICAgICAgICAgICAgICAgY2hlY2tlZDogU3RyZWFtaW5nUHJlZmVyZW5jZXMubXV0ZU9u
Rm9jdXNMb3NzCiAgICAgICAgICAgICAgICAgICAgIG9uQ2hlY2tlZENoYW5nZWQ6IHsKQEAgLTI3
ODYsNyArMjc5NSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLmRlbGF5
OiAxMDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGltZW91dDogNTAwMAogICAgICAg
ICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKLSAgICAgICAgICAgICAgICAg
ICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJNdXRlcyBWaWJlbWlzJ3MgYXVkaW8gd2hlbiB5b3UgQWx0
K1RhYiBvdXQgb2YgdGhlIHN0cmVhbSBvciBjbGljayBvbiBhIGRpZmZlcmVudCB3aW5kb3cuIikK
KyAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJNdXRlcyBFY2xpcHNlJ3Mg
YXVkaW8gd2hlbiB5b3UgQWx0K1RhYiBvdXQgb2YgdGhlIHN0cmVhbSBvciBjbGljayBvbiBhIGRp
ZmZlcmVudCB3aW5kb3cuIikKICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAgICAg
ICAgIH0KQEAgLTI5NzEsNyArMjk4MCw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAg
ICAgaWYgKFN0cmVhbWluZ1ByZWZlcmVuY2VzLmxhbmd1YWdlICE9PSBuZXdfbGFuZ3VhZ2UpIHsK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHJlYW1pbmdQcmVmZXJlbmNlcy5sYW5ndWFn
ZSA9IGxhbmd1YWdlTGlzdE1vZGVsLmdldChjdXJyZW50SW5kZXgpLnZhbAogICAgICAgICAgICAg
ICAgICAgICAgICAgICAgIGlmICghU3RyZWFtaW5nUHJlZmVyZW5jZXMucmV0cmFuc2xhdGUoKSkg
ewotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnNob3cocXNUcigiWW91
IG11c3QgcmVzdGFydCBWaWJlbWlzIGZvciB0aGlzIGNoYW5nZSB0byB0YWtlIGVmZmVjdCIpLCA1
MDAwKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnNob3cocXNUcigi
WW91IG11c3QgcmVzdGFydCBFY2xpcHNlIGZvciB0aGlzIGNoYW5nZSB0byB0YWtlIGVmZmVjdCIp
LCA1MDAwKQogICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICBlbHNlIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgLy8gRm9y
Y2UgdGhlIGJhY2sgb3BlcmF0aW9uIHRvIHBvcCBhbnkgQXBwVmlldyBwYWdlcyB0aGF0IGV4aXN0
LgpAQCAtMzA0MCw2ICszMDQ5LDEzIEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICB9CiAg
ICAgICAgICAgICAgICAgfQogCisgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OnFzVHIoIkNy
aW1zb24gR2xhc3Mg4oCiIEJhY2tncm91bmQiKTtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBl
Qm9keTtjb2xvcjpWYlRva2Vucy50ZXh0O2ZvbnQuYm9sZDp0cnVlIH0KKyAgICAgICAgICAgICAg
ICBGbG93IHsgd2lkdGg6cGFyZW50LndpZHRoO3NwYWNpbmc6MTIKKyAgICAgICAgICAgICAgICAg
ICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiQ2hvb3NlIGJhY2tncm91bmQiKTtv
bkNsaWNrZWQ6YmFja2dyb3VuZFBpY2tlci5vcGVuKCkgfQorICAgICAgICAgICAgICAgICAgICBF
Y2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpxc1RyKCJSZXNldCBiYWNrZ3JvdW5kIik7b25DbGlj
a2VkOkVjbGlwc2VQcm9maWxlcy5yZXNldEJhY2tncm91bmQoKSB9CisgICAgICAgICAgICAgICAg
fQorICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDpxc1RyKCJCYWNrZ3JvdW5kIGRpbW1pbmc6
ICUxJSIpLmFyZyhFY2xpcHNlUHJvZmlsZXMuYmFja2dyb3VuZERpbSk7Zm9udC5waXhlbFNpemU6
VmJUb2tlbnMudHlwZUxhYmVsO2NvbG9yOlZiVG9rZW5zLnRleHQgfQorICAgICAgICAgICAgICAg
IFNsaWRlciB7IHdpZHRoOnBhcmVudC53aWR0aDtmcm9tOjMwO3RvOjkwO3N0ZXBTaXplOjU7dmFs
dWU6RWNsaXBzZVByb2ZpbGVzLmJhY2tncm91bmREaW07QWNjZXNzaWJsZS5uYW1lOnFzVHIoIkJh
Y2tncm91bmQgZGltbWluZyIpO29uTW92ZWQ6RWNsaXBzZVByb2ZpbGVzLmJhY2tncm91bmREaW09
TWF0aC5yb3VuZCh2YWx1ZSkgfQogICAgICAgICAgICAgICAgIC8vIEJMLTIyNjMgKFNldHRpbmdz
IElBKTogcmVsb2NhdGVkIGZyb20gdGhlIEdhbWVwYWQgY2FyZCAtCiAgICAgICAgICAgICAgICAg
Ly8gYXBwLXdpZGUgYXBwZWFyYW5jZSwgbm90aGluZyBnYW1lcGFkLXNwZWNpZmljLgogICAgICAg
ICAgICAgICAgIExhYmVsIHsKQEAgLTMwNTUsMTQgKzMwNzEsMjYgQEAgSXRlbSB7CiAgICAgICAg
ICAgICAgICAgICAgIHRleHRSb2xlOiAidGV4dCIKICAgICAgICAgICAgICAgICAgICAgaG92ZXJF
bmFibGVkOiB0cnVlCiAgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBMaXN0TW9kZWwgewotICAg
ICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJUZWFsIChkZWZh
dWx0KSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNU
cigiVGVhbCIpIH0KICAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDog
cXNUcigiSW5kaWdvIikgfQogICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0
ZXh0OiBxc1RyKCJHcmVlbiIpIH0KICAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50
IHsgdGV4dDogcXNUcigiQW1iZXIiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxl
bWVudCB7IHRleHQ6IHFzVHIoIkNyaW1zb24gKGRlZmF1bHQpIikgfQorICAgICAgICAgICAgICAg
ICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJSZWQiKSB9CisgICAgICAgICAgICAg
ICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIk9yYW5nZSIpIH0KKyAgICAgICAg
ICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiR29sZCIpIH0KKyAgICAg
ICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiTGltZSIpIH0KKyAg
ICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiTWludCIpIH0K
KyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiQ3lhbiIp
IH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiQmx1
ZSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigi
VmlvbGV0IikgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBx
c1RyKCJQaW5rIikgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0
OiBxc1RyKCJTaWx2ZXIiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7
IHRleHQ6IHFzVHIoIlJvc2UiKSB9CiAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAg
ICAgICAgICAgQ29tcG9uZW50Lm9uQ29tcGxldGVkOiBjdXJyZW50SW5kZXggPSBTdHJlYW1pbmdQ
cmVmZXJlbmNlcy51aUFjY2VudEluZGV4CiAgICAgICAgICAgICAgICAgICAgIG9uQWN0aXZhdGVk
OiBTdHJlYW1pbmdQcmVmZXJlbmNlcy51aUFjY2VudEluZGV4ID0gY3VycmVudEluZGV4Ci0gICAg
ICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiVGhlIGFjY2VudCBjb2xvciB1c2Vk
IGFjcm9zcyB0aGUgcmVkZXNpZ25lZCBVSS4iKQorICAgICAgICAgICAgICAgICAgICBUb29sVGlw
LnRleHQ6IHFzVHIoIlRoZSBhY2NlbnQgY29sb3IgdXNlZCB0aHJvdWdob3V0IEVjbGlwc2UuIikK
ICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAg
ICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKICAgICAgICAgICAgICAgICB9CkBAIC0zMTQ3
LDcgKzMxNzUsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAuZGVs
YXk6IDEwMDAKICAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGltZW91dDogNTAwMAog
ICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAg
ICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlNhdmUgYWxsIFZpYmVtaXMgc2V0
dGluZ3MgdG8gfi92aWJlbWlzLXNldHRpbmdzLmluaSBmb3IgYmFja3VwIG9yIHRvIGNvcHkgdG8g
YW5vdGhlciBkZXZpY2UuIikKKyAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDog
cXNUcigiU2F2ZSBhbGwgRWNsaXBzZSBzZXR0aW5ncyB0byB+L3ZpYmVtaXMtc2V0dGluZ3MuaW5p
IGZvciBiYWNrdXAgb3IgdG8gY29weSB0byBhbm90aGVyIGRldmljZS4iKQogICAgICAgICAgICAg
ICAgICAgICB9CiAKICAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsKQEAgLTM0MDIsNyArMzQz
MCw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDEwMDAw
CiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAogICAgICAgICAg
ICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlRoaXMgZW5hYmxlcyB0aGUgY2FwdHVyZSBv
ZiBzeXN0ZW0td2lkZSBrZXlib2FyZCBzaG9ydGN1dHMgbGlrZSBBbHQrVGFiIHRoYXQgd291bGQg
bm9ybWFsbHkgYmUgaGFuZGxlZCBieSB0aGUgY2xpZW50IE9TIHdoaWxlIHN0cmVhbWluZy4iKSAr
ICJcblxuIiArCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcXNUcigiTk9URTog
Q2VydGFpbiBrZXlib2FyZCBzaG9ydGN1dHMgbGlrZSBDdHJsK0FsdCtEZWwgb24gV2luZG93cyBj
YW5ub3QgYmUgaW50ZXJjZXB0ZWQgYnkgYW55IGFwcGxpY2F0aW9uLCBpbmNsdWRpbmcgVmliZW1p
cy4iKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHFzVHIoIk5PVEU6IENlcnRh
aW4ga2V5Ym9hcmQgc2hvcnRjdXRzIGxpa2UgQ3RybCtBbHQrRGVsIG9uIFdpbmRvd3MgY2Fubm90
IGJlIGludGVyY2VwdGVkIGJ5IGFueSBhcHBsaWNhdGlvbiwgaW5jbHVkaW5nIEVjbGlwc2UuIikK
ICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICBBdXRvUmVzaXppbmdDb21ib0Jv
eCB7CkBAIC0zNjQzLDcgKzM2NzEsNyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgIFZiVG9n
Z2xlUm93IHsKICAgICAgICAgICAgICAgICAgICAgaWQ6IGJhY2tncm91bmRHYW1lcGFkQ2hlY2sK
LSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiUHJvY2VzcyBnYW1lcGFkIGlucHV0IHdo
ZW4gVmliZW1pcyBpcyBpbiB0aGUgYmFja2dyb3VuZCIpCisgICAgICAgICAgICAgICAgICAgIHRl
eHQ6IHFzVHIoIlByb2Nlc3MgZ2FtZXBhZCBpbnB1dCB3aGVuIEVjbGlwc2UgaXMgaW4gdGhlIGJh
Y2tncm91bmQiKQogICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBTeXN0ZW1Qcm9wZXJ0aWVz
Lmhhc0Rlc2t0b3BFbnZpcm9ubWVudAogICAgICAgICAgICAgICAgICAgICBjaGVja2VkOiBTdHJl
YW1pbmdQcmVmZXJlbmNlcy5iYWNrZ3JvdW5kR2FtZXBhZAogICAgICAgICAgICAgICAgICAgICBv
bkNoZWNrZWRDaGFuZ2VkOiB7CkBAIC0zNjUzLDcgKzM2ODEsNyBAQCBJdGVtIHsKICAgICAgICAg
ICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29s
VGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBo
b3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiQWxsb3dzIFZp
YmVtaXMgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0cyBldmVuIGlmIGl0J3Mgbm90IHRoZSBjdXJy
ZW50IHdpbmRvdyBpbiBmb2N1cyIpCisgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDog
cXNUcigiQWxsb3dzIEVjbGlwc2UgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0cyBldmVuIGlmIGl0
J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBmb2N1cyIpCiAgICAgICAgICAgICAgICAgfQog
CiAgICAgICAgICAgICAgICAgVmJUb2dnbGVSb3cgewpAQCAtMzcyNCw3ICszNzUyLDcgQEAgSXRl
bSB7CiAgICAgICAgICAgICAgICAgTGFiZWwgewogICAgICAgICAgICAgICAgICAgICB3aWR0aDog
cGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsVGl0bGUK
LSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiU29mdHdhcmUgdXBkYXRlcyIpCisgICAg
ICAgICAgICAgICAgICAgIHRleHQ6IEF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZCA/IHFzVHIo
IkVjbGlwc2VPUyB1cGRhdGVzIikgOiBxc1RyKCJTb2Z0d2FyZSB1cGRhdGVzIikKICAgICAgICAg
ICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVMYWJlbAogICAgICAgICAg
ICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKICAgICAgICAgICAgICAg
ICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtMzczMyw2ICszNzYxLDcgQEAgSXRlbSB7CiAK
ICAgICAgICAgICAgICAgICBBdXRvUmVzaXppbmdDb21ib0JveCB7CiAgICAgICAgICAgICAgICAg
ICAgIGlkOiB1cGRhdGVDaGFubmVsQ29tYm9Cb3gKKyAgICAgICAgICAgICAgICAgICAgdmlzaWJs
ZTogIUF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZAogICAgICAgICAgICAgICAgICAgICB0ZXh0
Um9sZTogInRleHQiCiAgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBMaXN0TW9kZWwgewogICAg
ICAgICAgICAgICAgICAgICAgICAgaWQ6IHVwZGF0ZUNoYW5uZWxMaXN0TW9kZWwKQEAgLTM3ODcs
NiArMzgxNiw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAvLyBpbnN0YWxsIGluIGZs
aWdodCBhdCBhIHRpbWUpLCBzbyBidXR0b25zIHN0YXkgZW5hYmxlZC4KICAgICAgICAgICAgICAg
ICAgICAgQnV0dG9uIHsKICAgICAgICAgICAgICAgICAgICAgICAgIGlkOiBjaGVja1VwZGF0ZXNC
dXR0b24KKyAgICAgICAgICAgICAgICAgICAgICAgIHZpc2libGU6ICFBdXRvVXBkYXRlQ2hlY2tl
ci5vc01hbmFnZWQKICAgICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkNoZWNrIGZv
ciB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogewogICAgICAg
ICAgICAgICAgICAgICAgICAgICAgIEF1dG9VcGRhdGVDaGVja2VyLmNoZWNrTm93KCkKQEAgLTM4
MDQsOCArMzgzNCw4IEBAIEl0ZW0gewogCiAgICAgICAgICAgICAgICAgICAgIEJ1dHRvbiB7CiAg
ICAgICAgICAgICAgICAgICAgICAgICBpZDogdmlld1JlbGVhc2VCdXR0b24KLSAgICAgICAgICAg
ICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpZXcgcmVsZWFzZSIpCi0gICAgICAgICAgICAgICAg
ICAgICAgICB2aXNpYmxlOiBBdXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2YWlsYWJsZQorICAgICAg
ICAgICAgICAgICAgICAgICAgdGV4dDogQXV0b1VwZGF0ZUNoZWNrZXIub3NNYW5hZ2VkID8gcXNU
cigiRWNsaXBzZU9TIHJlbGVhc2VzIikgOiBxc1RyKCJWaWV3IHJlbGVhc2UiKQorICAgICAgICAg
ICAgICAgICAgICAgICAgdmlzaWJsZTogKEF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZCB8fCBB
dXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2YWlsYWJsZSkKICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICYmIEF1dG9VcGRhdGVDaGVja2VyLnJlbGVhc2VVcmwgIT09ICIiCiAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAmJiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIK
ICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogewpAQCAtMzg0Miw3ICszODcyLDcg
QEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCiAKICAg
ICAgICAgICAgICAgICBWYlNlY3Rpb25IZWFkZXIgewotICAgICAgICAgICAgICAgICAgICB0ZXh0
OiBxc1RyKCJWaWJlbWlzIEZlYXR1cmVzIikKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiRWNsaXBzZSBGZWF0dXJlcyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAg
ICAgQ2xpcGJvYXJkU2V0dGluZ3MgewpAQCAtMzk0Nyw3ICszOTc3LDcgQEAgSXRlbSB7CiAgICAg
ICAgICAgICAgICAgUmVwZWF0ZXIgewogICAgICAgICAgICAgICAgICAgICB3aWR0aDogcGFyZW50
LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBbCi0gICAgICAgICAgICAgICAgICAg
ICAgICB7IGs6IHFzVHIoIlZpYmVtaXMgdmVyc2lvbiIpLCB2OiBTeXN0ZW1Qcm9wZXJ0aWVzLnZl
cnNpb25TdHJpbmcgfSwKKyAgICAgICAgICAgICAgICAgICAgICAgIHsgazogcXNUcigiRWNsaXBz
ZSB2ZXJzaW9uIiksIHY6IFN5c3RlbVByb3BlcnRpZXMudmVyc2lvblN0cmluZyB9LAogICAgICAg
ICAgICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJBcmNoaXRlY3R1cmUiKSwgICAgdjogU3lzdGVt
UHJvcGVydGllcy5mcmllbmRseU5hdGl2ZUFyY2hOYW1lIH0sCiAgICAgICAgICAgICAgICAgICAg
ICAgICB7IGs6IHFzVHIoIlN0ZWFtT1MgLyBnYW1lc2NvcGUiKSwgdjogU3lzdGVtUHJvcGVydGll
cy5pc1N0ZWFtRGVjayA/IHFzVHIoIlllcyIpIDogcXNUcigiTm8iKSB9LAogICAgICAgICAgICAg
ICAgICAgICAgICAgeyBrOiBxc1RyKCJEaXNwbGF5IHNlcnZlciIpLCAgdjogU3lzdGVtUHJvcGVy
dGllcy5pc1J1bm5pbmdXYXlsYW5kID8gKFN5c3RlbVByb3BlcnRpZXMuaXNSdW5uaW5nWFdheWxh
bmQgPyAiWFdheWxhbmQiIDogIldheWxhbmQiKSA6ICJYMTEiIH0sCkBAIC00MDEzLDcgKzQwNDMs
NyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgIExhYmVsIHsKICAgICAgICAgICAgICAgICAg
ICAgd2lkdGg6IHBhcmVudC53aWR0aAotICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJW
aWJlbWlzICUxIikuYXJnKFN5c3RlbVByb3BlcnRpZXMudmVyc2lvblN0cmluZykKKyAgICAgICAg
ICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSAlMSIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVz
LnZlcnNpb25TdHJpbmcpCiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRv
a2Vucy50eXBlQm9keQogICAgICAgICAgICAgICAgICAgICBmb250LmJvbGQ6IHRydWUKICAgICAg
ICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtNDA1OCw3ICs0MDg4LDcgQEAg
SXRlbSB7CiAKICAgICAgICAgICAgICAgICBMYWJlbCB7CiAgICAgICAgICAgICAgICAgICAgIHdp
ZHRoOiBwYXJlbnQud2lkdGgKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmliZW1p
cyBpcyB0aGUgTGludXgvU3RlYW1PUyBjbGllbnQgZm9yIEFwb2xsbyAmIFN1bnNoaW5lIGhvc3Rz
LiBUaGVzZSBvcGVuIGluIHlvdXIgYnJvd3Nlci4iKQorICAgICAgICAgICAgICAgICAgICB0ZXh0
OiBxc1RyKCJFY2xpcHNlIGlzIHRoZSBMaW51eC9TdGVhbU9TIGNsaWVudCBmb3IgQXBvbGxvICYg
U3Vuc2hpbmUgaG9zdHMuIFRoZXNlIG9wZW4gaW4geW91ciBicm93c2VyLiIpCiAgICAgICAgICAg
ICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQ2FwdGlvbgogICAgICAgICAg
ICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKICAgICAgICAgICAgICAg
ICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtNDA2Niw3ICs0MDk2LDcgQEAgSXRlbSB7CiAg
ICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgQnV0dG9uIHsKLSAgICAgICAgICAg
ICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBvbiBHaXRIdWIiKQorICAgICAgICAgICAgICAg
ICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIG9uIEdpdEh1YiIpCiAgICAgICAgICAgICAgICAgICAg
IG9uQ2xpY2tlZDogU3lzdGVtUHJvcGVydGllcy5vcGVuVXJsKCJodHRwczovL2dpdGh1Yi5jb20v
bmF2eWFzMzIxL3ZpYmVtaXMiKQogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICBC
dXR0b24gewpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9TeXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwg
Yi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9nLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwLi5lYzViNThiCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9TeXN0
ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwKQEAgLTAsMCArMSwxMTUgQEAKK2ltcG9ydCBRdFF1aWNr
IDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRz
IDEuMworaW1wb3J0IFF0UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1p
cy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBTeXN0ZW1Db250cm9scyAxLjAKKworTmF2aWdhYmxlRGlh
bG9nIHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9wZXJ0eSBzdHJpbmcga2luZDogIndpZmkiCisg
ICAgcHJvcGVydHkgdmFyIHNlbGVjdGVkOiAoe30pCisgICAgd2lkdGg6IE1hdGgubWluKDYyMCwg
cGFyZW50LndpZHRoIC0gMzIpCisgICAgaGVpZ2h0OiBNYXRoLm1pbig1NjAsIHBhcmVudC5oZWln
aHQgLSAzMikKKyAgICB0aXRsZToga2luZCA9PT0gIndpZmkiID8gcXNUcigiV2ktRmkgbmV0d29y
a3MiKSA6IHFzVHIoIkJsdWV0b290aCBkZXZpY2VzIikKKyAgICBzdGFuZGFyZEJ1dHRvbnM6IERp
YWxvZy5DbG9zZQorICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAg
IE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAgYmFja2dyb3VuZDogQ3JpbXNv
bkdsYXNzUGFuZWwgeyBjb2xvcjogVmJUb2tlbnMuYmdFbGV2OyByYWRpdXM6IFZiVG9rZW5zLnJh
ZGl1c0RpYWxvZzsgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UgfQorICAgIG9uT3BlbmVk
OiB7IHNlbGVjdGVkID0gKHt9KTsgU3lzdGVtQ29udHJvbHMub3BlbihraW5kKSB9CisgICAgb25D
bG9zZWQ6IHsgY3JlZGVudGlhbC5jbG9zZSgpOyBzZWNyZXQudGV4dCA9ICIiOyBmb3JnZXQuY2xv
c2UoKTsgU3lzdGVtQ29udHJvbHMuY2xvc2UoKSB9CisgICAgY29udGVudEl0ZW06IENvbHVtbkxh
eW91dCB7CisgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMworICAgICAgICBSb3dMYXlv
dXQgeworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQorICAgICAgICAgICAgTGFi
ZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tl
bnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7
IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB0ZXh0OiBTeXN0ZW1Db250cm9scy5zdGF0dXM7
IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgIEJ1c3lJbmRpY2F0b3IgeyBy
dW5uaW5nOiBTeXN0ZW1Db250cm9scy5idXN5OyB2aXNpYmxlOiBydW5uaW5nOyBpbXBsaWNpdFdp
ZHRoOiAzMjsgaW1wbGljaXRIZWlnaHQ6IDMyIH0KKyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25C
dXR0b24geyBpZDogc2NhbkJ1dHRvbjsgdGV4dDogcXNUcigiU2NhbiIpOyBlbmFibGVkOiAhU3lz
dGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiB7IHBhbmVsLnNlbGVjdGVkID0gKHt9KTsgU3lz
dGVtQ29udHJvbHMucmVxdWVzdChwYW5lbC5raW5kICsgIi1zY2FuIikgfSB9CisgICAgICAgIH0K
KyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIkNhbmNlbCBvcGVyYXRp
b24iKTsgdmlzaWJsZTogU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiB7IFN5c3RlbUNv
bnRyb2xzLmNsb3NlKCk7IHBhbmVsLnNlbGVjdGVkPSh7fSk7IHJlb3Blbi5yZXN0YXJ0KCkgfSB9
CisgICAgICAgIFRpbWVyIHsgaWQ6IHJlb3BlbjsgaW50ZXJ2YWw6IDYwMDsgb25UcmlnZ2VyZWQ6
IGlmKHBhbmVsLm9wZW5lZCkgU3lzdGVtQ29udHJvbHMub3BlbihwYW5lbC5raW5kKSB9CisgICAg
ICAgIFRpbWVyIHsgaW50ZXJ2YWw6NTAwMDsgcmVwZWF0OnRydWU7IHJ1bm5pbmc6cGFuZWwub3Bl
bmVkICYmIHBhbmVsLmtpbmQ9PT0iYnQiICYmICFTeXN0ZW1Db250cm9scy5idXN5ICYmICFjcmVk
ZW50aWFsLm9wZW5lZDsgb25UcmlnZ2VyZWQ6U3lzdGVtQ29udHJvbHMucmVxdWVzdCgiYnQtbGlz
dCIpIH0KKyAgICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9u
dC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFwOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbQor
ICAgICAgICAgICAgdGV4dDogcGFuZWwua2luZCA9PT0gIndpZmkiID8gcXNUcigiU2VsZWN0IGEg
bmV0d29yaywgdGhlbiBDb25uZWN0LiBBZHZhbmNlZCBvciBoaWRkZW4gbmV0d29ya3MgYXJlIGF2
YWlsYWJsZSBpbiB0aGUgZGlhZ25vc3RpYyBzaGVsbC4iKSA6IHFzVHIoIlB1dCB5b3VyIGNvbnRy
b2xsZXIgb3IgaGVhZHBob25lcyBpbiBwYWlyaW5nIG1vZGUsIHRoZW4gU2Nhbi4gRGV2aWNlcyBh
cHBlYXIgZHVyaW5nIHNjYW5uaW5nLiBTYXZlZCBkZXZpY2VzIGFyZSBsaXN0ZWQgd2l0aG91dCBz
Y2FubmluZy4iKQorICAgICAgICB9CisgICAgICAgIExpc3RWaWV3IHsKKyAgICAgICAgICAgIGlk
OiBkZXZpY2VzCisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBMYXlvdXQuZmls
bEhlaWdodDogdHJ1ZQorICAgICAgICAgICAgY2xpcDogdHJ1ZTsgc3BhY2luZzogNDsgbW9kZWw6
IFN5c3RlbUNvbnRyb2xzLml0ZW1zCisgICAgICAgICAgICBTY3JvbGxCYXIudmVydGljYWw6IFNj
cm9sbEJhciB7fQorICAgICAgICAgICAgZGVsZWdhdGU6IEl0ZW1EZWxlZ2F0ZSB7CisgICAgICAg
ICAgICAgICAgd2lkdGg6IGRldmljZXMud2lkdGgKKyAgICAgICAgICAgICAgICBpbXBsaWNpdEhl
aWdodDogTWF0aC5tYXgoNDQsY29udGVudEl0ZW0uaW1wbGljaXRIZWlnaHQrMjQpCisgICAgICAg
ICAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsgY29sb3I6cGFyZW50LmhpZ2hsaWdodGVk
IHx8IHBhcmVudC5ob3ZlcmVkID8gVmJUb2tlbnMuYmdFbGV2MiA6IFZiVG9rZW5zLmJnRWxldjsg
cmFkaXVzOlZiVG9rZW5zLnJhZGl1c0NvbnRyb2w7IGJvcmRlci5jb2xvcjpwYXJlbnQuYWN0aXZl
Rm9jdXM/VmJUb2tlbnMuYWNjZW50OlZiVG9rZW5zLnN0cm9rZSB9CisgICAgICAgICAgICAgICAg
ZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3kKKyAgICAgICAgICAgICAgICBoaWdobGlnaHRl
ZDogcGFuZWwuc2VsZWN0ZWQuaWQgPT09IG1vZGVsRGF0YS5pZAorICAgICAgICAgICAgICAgIGFj
dGl2ZUZvY3VzT25UYWI6IHRydWUKKyAgICAgICAgICAgICAgICBLZXlzLm9uUmV0dXJuUHJlc3Nl
ZDogaWYgKGVuYWJsZWQpIGNsaWNrZWQoKQorICAgICAgICAgICAgICAgIEtleXMub25FbnRlclBy
ZXNzZWQ6IGlmIChlbmFibGVkKSBjbGlja2VkKCkKKyAgICAgICAgICAgICAgICBLZXlzLm9uRG93
blByZXNzZWQ6IHsgaWYgKGluZGV4ICsgMSA8IGRldmljZXMuY291bnQpIHsgZGV2aWNlcy5pbmNy
ZW1lbnRDdXJyZW50SW5kZXgoKTsgaWYgKGRldmljZXMuY3VycmVudEl0ZW0pIGRldmljZXMuY3Vy
cmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykgfSBlbHNlIGlmIChjb25uZWN0
QnV0dG9uLmVuYWJsZWQpIGNvbm5lY3RCdXR0b24uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1
cyk7IGVsc2Ugc2NhbkJ1dHRvbi5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKSB9CisgICAg
ICAgICAgICAgICAgS2V5cy5vblVwUHJlc3NlZDogeyBpZiAoaW5kZXggPiAwKSB7IGRldmljZXMu
ZGVjcmVtZW50Q3VycmVudEluZGV4KCk7IGlmIChkZXZpY2VzLmN1cnJlbnRJdGVtKSBkZXZpY2Vz
LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpIH0gZWxzZSBzY2FuQnV0
dG9uLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpIH0KKyAgICAgICAgICAgICAgICBjb250
ZW50SXRlbTogTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhl
bFNpemU6VmJUb2tlbnMudHlwZUJvZHk7CisgICAgICAgICAgICAgICAgICAgIHRleHRGb3JtYXQ6
IFRleHQuUGxhaW5UZXh0OyBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0OyBjb2xvcjogVmJUb2tlbnMu
dGV4dAorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBtb2RlbERhdGEubmFtZSArICIgwrcgIiAr
IG1vZGVsRGF0YS5kZXRhaWwgKyAobW9kZWxEYXRhLmNvbm5lY3RlZCA/ICIgwrcgIiArIHFzVHIo
IkNvbm5lY3RlZCIpIDogIiIpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIG9u
Q2xpY2tlZDogeyBwYW5lbC5zZWxlY3RlZCA9IG1vZGVsRGF0YTsgZGV2aWNlcy5jdXJyZW50SW5k
ZXggPSBpbmRleCB9CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICAgICAgUm93TGF5b3V0
IHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgIEVjbGlw
c2VBY3Rpb25CdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBjb25uZWN0QnV0dG9uCisgICAg
ICAgICAgICAgICAgdGV4dDogcGFuZWwua2luZCA9PT0gIndpZmkiID8gcXNUcigiQ29ubmVjdCIp
IDogcXNUcigiUGFpciAvIENvbm5lY3QiKQorICAgICAgICAgICAgICAgIGVuYWJsZWQ6ICEhcGFu
ZWwuc2VsZWN0ZWQuaWQgJiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3kKKyAgICAgICAgICAgICAgICBv
bkNsaWNrZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QocGFuZWwua2luZCArICItY29ubmVjdCIs
IHBhbmVsLnNlbGVjdGVkLmlkKQorICAgICAgICAgICAgfQorICAgICAgICAgICAgRWNsaXBzZUFj
dGlvbkJ1dHRvbiB7CisgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRGlzY29ubmVjdCIpOyBl
bmFibGVkOiAhIXBhbmVsLnNlbGVjdGVkLmlkICYmIHBhbmVsLnNlbGVjdGVkLmNvbm5lY3RlZCAm
JiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogU3lzdGVt
Q29udHJvbHMucmVxdWVzdChwYW5lbC5raW5kICsgIi1kaXNjb25uZWN0IiwgcGFuZWwuc2VsZWN0
ZWQuaWQpCisgICAgICAgICAgICB9CisgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsg
dGV4dDogcXNUcigiRm9yZ2V0Iik7IHZpc2libGU6IHBhbmVsLmtpbmQgPT09ICJidCI7IGVuYWJs
ZWQ6ICEhcGFuZWwuc2VsZWN0ZWQuaWQgJiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tl
ZDogZm9yZ2V0Lm9wZW4oKSB9CisgICAgICAgIH0KKyAgICB9CisgICAgQ29ubmVjdGlvbnMgewor
ICAgICAgICB0YXJnZXQ6IFN5c3RlbUNvbnRyb2xzCisgICAgICAgIGZ1bmN0aW9uIG9uQ2hhbmdl
ZCgpIHsKKyAgICAgICAgICAgIGlmIChTeXN0ZW1Db250cm9scy5wcm9tcHQubGVuZ3RoID4gMCAm
JiBwYW5lbC5vcGVuZWQgJiYgIWNyZWRlbnRpYWwub3BlbmVkKSBjcmVkZW50aWFsLm9wZW4oKQor
ICAgICAgICAgICAgaWYgKCFTeXN0ZW1Db250cm9scy5idXN5KSB7CisgICAgICAgICAgICAgICAg
Y3JlZGVudGlhbC5jbG9zZSgpOyBzZWNyZXQudGV4dCA9ICIiCisgICAgICAgICAgICAgICAgdmFy
IGlkID0gcGFuZWwuc2VsZWN0ZWQuaWQKKyAgICAgICAgICAgICAgICBwYW5lbC5zZWxlY3RlZCA9
ICh7fSkKKyAgICAgICAgICAgICAgICBmb3IgKHZhciBpID0gMDsgaSA8IFN5c3RlbUNvbnRyb2xz
Lml0ZW1zLmxlbmd0aDsgaSsrKQorICAgICAgICAgICAgICAgICAgICBpZiAoU3lzdGVtQ29udHJv
bHMuaXRlbXNbaV0uaWQgPT09IGlkKSBwYW5lbC5zZWxlY3RlZCA9IFN5c3RlbUNvbnRyb2xzLml0
ZW1zW2ldCisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgTmF2aWdhYmxlRGlh
bG9nIHsKKyAgICAgICAgaWQ6IGNyZWRlbnRpYWwKKyAgICAgICAgb2JqZWN0TmFtZTogImNvbm5l
Y3Rpb25DcmVkZW50aWFsIgorICAgICAgICB0aXRsZTogcXNUcigiQ29ubmVjdGlvbiBhdXRoZW50
aWNhdGlvbiIpCisgICAgICAgIHdpZHRoOiBNYXRoLm1pbig0ODAsIHBhbmVsLndpZHRoKQorICAg
ICAgICBjbG9zZVBvbGljeTogUG9wdXAuTm9BdXRvQ2xvc2UKKyAgICAgICAgc3RhbmRhcmRCdXR0
b25zOiBEaWFsb2cuT2sgfCBEaWFsb2cuQ2FuY2VsCisgICAgICAgIE1hdGVyaWFsLmJhY2tncm91
bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgICAgICBvbk9wZW5lZDogeyBzZWNyZXQudGV4dCA9ICIi
OyBzZWNyZXQuZm9yY2VBY3RpdmVGb2N1cygpIH0KKyAgICAgICAgb25BY2NlcHRlZDogeyBTeXN0
ZW1Db250cm9scy5hbnN3ZXIoc2VjcmV0LnRleHQpOyBzZWNyZXQudGV4dCA9ICIiIH0KKyAgICAg
ICAgb25SZWplY3RlZDogeyBzZWNyZXQudGV4dCA9ICIiOyBTeXN0ZW1Db250cm9scy5jbG9zZSgp
OyByZW9wZW4ucmVzdGFydCgpIH0KKyAgICAgICAgY29udGVudEl0ZW06IENvbHVtbkxheW91dCB7
CisgICAgICAgICAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250
LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4
dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IFN5c3Rl
bUNvbnRyb2xzLnByb21wdDsgY29sb3I6IFZiVG9rZW5zLnRleHQgfQorICAgICAgICAgICAgVGV4
dEZpZWxkIHsgaWQ6IHNlY3JldDsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQu
cGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBlY2hv
TW9kZTogVGV4dElucHV0LlBhc3N3b3JkOyBtYXhpbXVtTGVuZ3RoOiA0MDk2OyBzZWxlY3RCeU1v
dXNlOiB0cnVlOyBvbkFjY2VwdGVkOiBjcmVkZW50aWFsLmFjY2VwdCgpIH0KKyAgICAgICAgICAg
IExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZi
VG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5X
cmFwOyB0ZXh0OiBxc1RyKCJFbnRlciB0aGUgcmVxdWVzdGVkIHBhc3N3b3JkIG9yIFBJTi4gRm9y
IGEgeWVzL25vIGNvbmZpcm1hdGlvbiwgdHlwZSB5ZXMgb3Igbm8uIik7IGNvbG9yOiBWYlRva2Vu
cy50ZXh0RGltIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBOYXZpZ2FibGVEaWFsb2cgeworICAg
ICAgICBpZDogZm9yZ2V0CisgICAgICAgIGltcGxpY2l0SGVpZ2h0OiBjb250ZW50SXRlbS5jb250
ZW50SGVpZ2h0ICsgaGVhZGVyLmltcGxpY2l0SGVpZ2h0ICsgZm9vdGVyLmltcGxpY2l0SGVpZ2h0
ICsgdG9wUGFkZGluZyArIGJvdHRvbVBhZGRpbmcKKyAgICAgICAgb2JqZWN0TmFtZTogImNvbm5l
Y3Rpb25Gb3JnZXQiCisgICAgICAgIHRpdGxlOiBxc1RyKCJGb3JnZXQgQmx1ZXRvb3RoIGRldmlj
ZT8iKQorICAgICAgICB3aWR0aDogTWF0aC5taW4oNDgwLCBwYW5lbC53aWR0aCkKKyAgICAgICAg
c3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuWWVzIHwgRGlhbG9nLk5vCisgICAgICAgIE1hdGVyaWFs
LmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgICAgICBvbkFjY2VwdGVkOiBTeXN0ZW1D
b250cm9scy5yZXF1ZXN0KCJidC1mb3JnZXQiLCBwYW5lbC5zZWxlY3RlZC5pZCwgdHJ1ZSkKKyAg
ICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7
IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWlu
VGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcXNUcigiUmVtb3ZlIHRoZSBzYXZlZCBw
YWlyaW5nIGZvciAlMT8gWW91IHdpbGwgbmVlZCB0byBwYWlyIGl0IGFnYWluLiIpLmFyZyhwYW5l
bC5zZWxlY3RlZC5uYW1lIHx8ICIiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQgfQorICAgIH0KK30K
ZGlmZiAtLWdpdCBhL2FwcC9ndWkvVGhlbWUucW1sIGIvYXBwL2d1aS9UaGVtZS5xbWwKaW5kZXgg
ZmI5MWM4NS4uNTdjOWY4NCAxMDA2NDQKLS0tIGEvYXBwL2d1aS9UaGVtZS5xbWwKKysrIGIvYXBw
L2d1aS9UaGVtZS5xbWwKQEAgLTExLDIwICsxMSwyMCBAQCBpbXBvcnQgVmliZW1pcy5SZWRlc2ln
biAxLjAKIFF0T2JqZWN0IHsKICAgICAvLyAtLS0tIENvbG9yIC0tLS0KICAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciBhY2NlbnQ6ICAgICAgICBWYlRva2Vucy5hY2NlbnQgIC8vIEJMLTIwNzc6
IHNpbmdsZSBzb3VyY2Ugb2YgdHJ1dGggKFZiVG9rZW5zIGJyYW5kIGFjY2VudCwgZGVmYXVsdCAj
MDBDQ0NDKQotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudFByZXNzZWQ6ICIjMDBB
M0EzIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJhY2tncm91bmQ6ICAgICIjMzAzMDMw
IiAgLy8gYXBwIHJvb3QKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdXJmYWNlOiAgICAg
ICAiIzJEMkQyRCIgIC8vIHJhaXNlZCBzdXJmYWNlcyAvIG92ZXJsYXlzCi0gICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3Igc3VyZmFjZUFsdDogICAgIiM0MjQyNDIiICAvLyBwb3B1cHMgLyBjb21i
byBkcm9wZG93bnMKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBib3JkZXI6ICAgICAgICAi
IzQ0NDQ0NCIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0UHJpbWFyeTogICAiI0ZG
RkZGRiIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0U2Vjb25kYXJ5OiAiI0NDQ0ND
QyIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0VGVydGlhcnk6ICAiI0FBQUFBQSIK
LSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0RGlzYWJsZWQ6ICAiIzc3Nzc3NyIKLSAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdWNjZXNzOiAgICAgICAiIzRDQUY1MCIKLSAgICBy
ZWFkb25seSBwcm9wZXJ0eSBjb2xvciB3YXJuaW5nOiAgICAgICAiI0UwQTAzMCIgIC8vIHRoZSBz
aW5nbGUgYW1iZXIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBlcnJvcjogICAgICAgICAi
I0Y0NDMzNiIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbmZvOiAgICAgICAgICAiIzgw
QTBDMCIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzY3JpbTogICAgICAgICAiI0QwMDAw
MDAwIgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudFByZXNzZWQ6IFZiVG9rZW5z
LmFjY2VudFByZXNzZWQKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiYWNrZ3JvdW5kOiAg
ICBWYlRva2Vucy5iZ1dpbmRvdyAgLy8gYXBwIHJvb3QKKyAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciBzdXJmYWNlOiAgICAgICBWYlRva2Vucy5iZ0VsZXYgIC8vIHJhaXNlZCBzdXJmYWNlcyAv
IG92ZXJsYXlzCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3VyZmFjZUFsdDogICAgVmJU
b2tlbnMuYmdFbGV2MiAgLy8gcG9wdXBzIC8gY29tYm8gZHJvcGRvd25zCisgICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3IgYm9yZGVyOiAgICAgICAgVmJUb2tlbnMuc3Ryb2tlCisgICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3IgdGV4dFByaW1hcnk6ICAgVmJUb2tlbnMudGV4dFByaW1hcnkKKyAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0U2Vjb25kYXJ5OiBWYlRva2Vucy50ZXh0U2Vj
b25kYXJ5CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFRlcnRpYXJ5OiAgVmJUb2tl
bnMudGV4dFRlcnRpYXJ5CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpc2FibGVk
OiAgVmJUb2tlbnMudGV4dERpc2FibGVkCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Vj
Y2VzczogICAgICAgVmJUb2tlbnMuc3RhdHVzU3VjY2VzcworICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIHdhcm5pbmc6ICAgICAgIFZiVG9rZW5zLnN0YXR1c1dhcm5pbmcgIC8vIHRoZSBzaW5n
bGUgYW1iZXIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBlcnJvcjogICAgICAgICBWYlRv
a2Vucy5zdGF0dXNEYW5nZXIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbmZvOiAgICAg
ICAgICBWYlRva2Vucy5zdGF0dXNJbmZvCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc2Ny
aW06ICAgICAgICAgVmJUb2tlbnMuZGlhbG9nU2NyaW0KIAogICAgIC8vIC0tLS0gVHlwb2dyYXBo
eSAocG9pbnRTaXplOyBwYWlyIHdpdGggYm9sZCB3aGVyZSBub3RlZCBpbiBERVNJR05fU1lTVEVN
Lm1kKSAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IGZvbnREaXNwbGF5OiAyNCAgLy8g
b3ZlcmxheS9RdWljayBNZW51IHRpdGxlIChib2xkKQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9WYkNh
cmQucW1sIGIvYXBwL2d1aS9WYkNhcmQucW1sCmluZGV4IDM3ZjJlMzIuLjFjOTcxMGQgMTAwNjQ0
Ci0tLSBhL2FwcC9ndWkvVmJDYXJkLnFtbAorKysgYi9hcHAvZ3VpL1ZiQ2FyZC5xbWwKQEAgLTE5
LDE1ICsxOSwxOSBAQCBJdGVtIHsKICAgICAgICAgcmFkaXVzOiBjYXJkLnJhZGl1cwogICAgIH0K
IAotICAgIFJlY3RhbmdsZSB7CisgICAgQ3JpbXNvbkdsYXNzUGFuZWwgewogICAgICAgICBpZDog
c3VyZmFjZQogICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAogICAgICAgICByYWRpdXM6IGNh
cmQucmFkaXVzCiAgICAgICAgIGNvbG9yOiBjYXJkLmZvY3VzZWQgPyBWYlRva2Vucy5mb2N1c2Vk
RmlsbCA6IGNhcmQuYmFzZUNvbG9yCisgICAgICAgIGdyYWRpZW50OiBHcmFkaWVudCB7CisgICAg
ICAgICAgICBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjowO2NvbG9yOmNhcmQuZm9jdXNlZCA/IFZi
VG9rZW5zLmJnRWxldjIgOiBWYlRva2Vucy5nbGFzc1RvcCB9CisgICAgICAgICAgICBHcmFkaWVu
dFN0b3AgeyBwb3NpdGlvbjoxO2NvbG9yOmNhcmQuZm9jdXNlZCA/IFZiVG9rZW5zLmZvY3VzZWRG
aWxsIDogY2FyZC5iYXNlQ29sb3IgfQorICAgICAgICB9CiAgICAgICAgIGJvcmRlci53aWR0aDog
MQogICAgICAgICBib3JkZXIuY29sb3I6IFZiVG9rZW5zLnN0cm9rZQogICAgICAgICBvcGFjaXR5
OiBjYXJkLmNvbnRlbnRPcGFjaXR5Ci0gICAgICAgIEJlaGF2aW9yIG9uIGNvbG9yIHsgQ29sb3JB
bmltYXRpb24geyBkdXJhdGlvbjogMTIwIH0gfQorICAgICAgICBCZWhhdmlvciBvbiBjb2xvciB7
IENvbG9yQW5pbWF0aW9uIHsgZHVyYXRpb246IFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQgPyAxMjAg
OiAwIH0gfQogICAgIH0KIAogICAgIEl0ZW0gewpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9WYkhvc3RD
YXJkLnFtbCBiL2FwcC9ndWkvVmJIb3N0Q2FyZC5xbWwKaW5kZXggOWUxZmU3Zi4uOWRiYTZhNiAx
MDA2NDQKLS0tIGEvYXBwL2d1aS9WYkhvc3RDYXJkLnFtbAorKysgYi9hcHAvZ3VpL1ZiSG9zdENh
cmQucW1sCkBAIC0yOSw3ICsyOSw3IEBAIEl0ZW0gewogICAgICAgICByYWRpdXM6IDIwCiAgICAg
fQogCi0gICAgUmVjdGFuZ2xlIHsKKyAgICBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgIGlk
OiBzdXJmYWNlCiAgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50CiAgICAgICAgIHJhZGl1czog
MjAKQEAgLTQ1LDIwICs0NSwyMCBAQCBJdGVtIHsKIAogICAgICAgICBDb2x1bW5MYXlvdXQgewog
ICAgICAgICAgICAgYW5jaG9ycy5maWxsOiBwYXJlbnQKLSAgICAgICAgICAgIGFuY2hvcnMubWFy
Z2luczogMzIKKyAgICAgICAgICAgIGFuY2hvcnMubWFyZ2luczogMjQKICAgICAgICAgICAgIC8v
IFJlc2VydmUgdGhlIGJvdHRvbSBzdHJpcCBmb3IgdGhlIGFuY2hvcmVkIGJhZGdlL21ldGEgcm93
IGJlbG93LiBUaGUgb2xkCiAgICAgICAgICAgICAvLyBzaW5nbGUtY29sdW1uIGZsb3cgb3ZlcmZs
b3dlZCB0aGUgZml4ZWQgMjQycHggY2FyZCBieSB+MTFweCB3aXRoIHJlYWwgZGV2aWNlIGZvbnRz
CiAgICAgICAgICAgICAvLyAoMzIrNTgrMjArbmFtZSs2K2FjY2VzcysyMCtiYWRnZSszMiA+IDI0
MiksIHNob3ZpbmcgdGhlIGJhZGdlIHJvdyBvbnRvIHRoZSBib3JkZXIuCiAgICAgICAgICAgICBh
bmNob3JzLmJvdHRvbU1hcmdpbjogNjQKLSAgICAgICAgICAgIHNwYWNpbmc6IDIwCisgICAgICAg
ICAgICBzcGFjaW5nOiAxNAogCiAgICAgICAgICAgICAvLyAtLS0tIFJvdyAxOiBtb25pdG9yIG91
dGxpbmUgKyBzdGF0dXMgcGlsbCAtLS0tCiAgICAgICAgICAgICBSb3dMYXlvdXQgewogICAgICAg
ICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKICAgICAgICAgICAgICAgICAvLyBNb25p
dG9yOiBhbiA4MsOXNTggcm91bmRlZCByZWN0YW5nbGUgZHJhd24gYXMgYSA1cHggb3V0bGluZSAo
bm8gZmlsbCksIGxpa2UgdGhlIEhUTUwuCiAgICAgICAgICAgICAgICAgUmVjdGFuZ2xlIHsKLSAg
ICAgICAgICAgICAgICAgICAgTGF5b3V0LnByZWZlcnJlZFdpZHRoOiA4MgotICAgICAgICAgICAg
ICAgICAgICBMYXlvdXQucHJlZmVycmVkSGVpZ2h0OiA1OAorICAgICAgICAgICAgICAgICAgICBM
YXlvdXQucHJlZmVycmVkV2lkdGg6IDY0CisgICAgICAgICAgICAgICAgICAgIExheW91dC5wcmVm
ZXJyZWRIZWlnaHQ6IDQ4CiAgICAgICAgICAgICAgICAgICAgIHJhZGl1czogMTAKICAgICAgICAg
ICAgICAgICAgICAgY29sb3I6ICJ0cmFuc3BhcmVudCIKICAgICAgICAgICAgICAgICAgICAgYm9y
ZGVyLndpZHRoOiA1CkBAIC04NSw3ICs4NSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAg
ICAgICAgICAgIGNvbG9yOiBjYXJkLm9ubGluZSA/IFZiVG9rZW5zLnN0YXR1c09ubGluZQogICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IChjYXJkLnN0YXR1
c1Vua25vd24gPyBWYlRva2Vucy50ZXh0RGltIDogIiM1QTYyNkMiKQogICAgICAgICAgICAgICAg
ICAgICAgICAgICAgIFNlcXVlbnRpYWxBbmltYXRpb24gb24gb3BhY2l0eSB7Ci0gICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgIHJ1bm5pbmc6IGNhcmQub25saW5lIHx8IGNhcmQuc3RhdHVz
VW5rbm93bgorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBydW5uaW5nOiBWYlRva2Vu
cy5tb3Rpb25FbmFibGVkICYmIChjYXJkLm9ubGluZSB8fCBjYXJkLnN0YXR1c1Vua25vd24pCiAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGxvb3BzOiBBbmltYXRpb24uSW5maW5pdGUK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJvbTog
MS4wOyB0bzogMC40NTsgZHVyYXRpb246IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAyIH0KICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMC40
NTsgdG86IDEuMDsgZHVyYXRpb246IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAyIH0KQEAgLTk2
LDcgKzk2LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGV4dDogY2Fy
ZC5vbmxpbmUgPyBxc1RyKCJPTkxJTkUiKQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgIDogKGNhcmQuc3RhdHVzVW5rbm93biA/IHFzVHIoIkNIRUNLSU5HIikg
OiBxc1RyKCJPRkZMSU5FIikpCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZm9udC5mYW1p
bHk6IFZiVG9rZW5zLmZvbnRCb2R5Ci0gICAgICAgICAgICAgICAgICAgICAgICAgICAgZm9udC5w
aXhlbFNpemU6IDE0CisgICAgICAgICAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6
IFZiVG9rZW5zLnR5cGVMYWJlbAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIGZvbnQud2Vp
Z2h0OiBGb250LkJvbGQKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBmb250LmxldHRlclNw
YWNpbmc6IDAuNwogICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNvbG9yOiBjYXJkLm9ubGlu
ZSA/IFZiVG9rZW5zLnN0YXR1c09ubGluZSA6IFZiVG9rZW5zLnRleHREaW0KQEAgLTExNCw3ICsx
MTQsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgdGV4dDogY2FyZC5ob3N0TmFtZQog
ICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udERpc3BsYXkKICAg
ICAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZvbnQuQm9sZAotICAgICAgICAgICAgICAg
ICAgICBmb250LnBpeGVsU2l6ZTogMjcKKyAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNp
emU6IFZiVG9rZW5zLnR5cGVIZWFkaW5nCiAgICAgICAgICAgICAgICAgICAgIGNvbG9yOiBjYXJk
Lm9ubGluZSA/IFZiVG9rZW5zLnRleHQgOiBWYlRva2Vucy50ZXh0TXV0ZQogICAgICAgICAgICAg
ICAgICAgICBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0CiAgICAgICAgICAgICAgICAgfQpAQCAtMTIz
LDcgKzEyMyw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICB0ZXh0OiBjYXJkLmFjY2Vz
c1RleHQKICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogY2FyZC5hY2Nlc3NUZXh0ICE9PSAi
IgogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKLSAg
ICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IDE3CisgICAgICAgICAgICAgICAgICAg
IGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlTGFiZWwKICAgICAgICAgICAgICAgICAgICAg
Y29sb3I6IFZiVG9rZW5zLnRleHREaW0KICAgICAgICAgICAgICAgICAgICAgZWxpZGU6IFRleHQu
RWxpZGVSaWdodAogICAgICAgICAgICAgICAgIH0KQEAgLTEzOSw4ICsxMzksOCBAQCBJdGVtIHsK
ICAgICAgICAgICAgIGFuY2hvcnMubGVmdDogcGFyZW50LmxlZnQKICAgICAgICAgICAgIGFuY2hv
cnMucmlnaHQ6IHBhcmVudC5yaWdodAogICAgICAgICAgICAgYW5jaG9ycy5ib3R0b206IHBhcmVu
dC5ib3R0b20KLSAgICAgICAgICAgIGFuY2hvcnMubGVmdE1hcmdpbjogMzIKLSAgICAgICAgICAg
IGFuY2hvcnMucmlnaHRNYXJnaW46IDMyCisgICAgICAgICAgICBhbmNob3JzLmxlZnRNYXJnaW46
IDI0CisgICAgICAgICAgICBhbmNob3JzLnJpZ2h0TWFyZ2luOiAyNAogICAgICAgICAgICAgYW5j
aG9ycy5ib3R0b21NYXJnaW46IDIyCiAgICAgICAgICAgICBzcGFjaW5nOiAxMAogICAgICAgICAg
ICAgLy8gSG9zdC10eXBlIGJhZGdlIChhY2NlbnQgb3V0bGluZSBmb3IgQXBvbGxvLWxpbmVhZ2Us
IG5ldXRyYWwgZm9yIFN1bnNoaW5lKS4KQEAgLTE1Nyw3ICsxNTcsNyBAQCBJdGVtIHsKICAgICAg
ICAgICAgICAgICAgICAgYW5jaG9ycy5jZW50ZXJJbjogcGFyZW50CiAgICAgICAgICAgICAgICAg
ICAgIHRleHQ6IGNhcmQuaG9zdEJhZGdlCiAgICAgICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5
OiBWYlRva2Vucy5mb250Qm9keQotICAgICAgICAgICAgICAgICAgICBmb250LnBpeGVsU2l6ZTog
MTMKKyAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVDYXB0
aW9uCiAgICAgICAgICAgICAgICAgICAgIGZvbnQud2VpZ2h0OiBGb250LkV4dHJhQm9sZAogICAg
ICAgICAgICAgICAgICAgICBmb250LmxldHRlclNwYWNpbmc6IDEuMgogICAgICAgICAgICAgICAg
ICAgICBjb2xvcjogY2FyZC5iYWRnZUFjY2VudCA/IFZiVG9rZW5zLmFjY2VudCA6IFZiVG9rZW5z
LnRleHREaW0KZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJIb3N0U2hlZXQucW1sIGIvYXBwL2d1aS9W
Ykhvc3RTaGVldC5xbWwKaW5kZXggYjRhMWFmOC4uNTdmY2JiNiAxMDA2NDQKLS0tIGEvYXBwL2d1
aS9WYkhvc3RTaGVldC5xbWwKKysrIGIvYXBwL2d1aS9WYkhvc3RTaGVldC5xbWwKQEAgLTc4LDcg
Kzc4LDcgQEAgUG9wdXAgewogICAgICAgICB9CiAKICAgICAgICAgLy8gLS0tLSBSaWdodCBwYW5l
bCAtLS0tCi0gICAgICAgIFJlY3RhbmdsZSB7CisgICAgICAgIENyaW1zb25HbGFzc1BhbmVsIHsK
ICAgICAgICAgICAgIGlkOiBwYW5lbAogICAgICAgICAgICAgd2lkdGg6IE1hdGgubWluKDU2MCwg
cm9vdC53aWR0aCAqIDAuNjIpCiAgICAgICAgICAgICBoZWlnaHQ6IHBhcmVudC5oZWlnaHQKZGlm
ZiAtLWdpdCBhL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbCBiL2FwcC9ndWkvVmJTdGF0dXNQaWxs
LnFtbAppbmRleCA4OWM0NzcwLi5jNzI4ZjA1IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiU3RhdHVz
UGlsbC5xbWwKKysrIGIvYXBwL2d1aS9WYlN0YXR1c1BpbGwucW1sCkBAIC0yNCw3ICsyNCw3IEBA
IFJlY3RhbmdsZSB7CiAgICAgICAgICAgICBjb2xvcjogcGlsbC5vbmxpbmUgPyBWYlRva2Vucy5z
dGF0dXNPbmxpbmUgOiBWYlRva2Vucy5zdGF0dXNPZmZsaW5lCiAgICAgICAgICAgICAvLyBQdWxz
ZSBvbmx5IHdoZW4gb25saW5lLgogICAgICAgICAgICAgU2VxdWVudGlhbEFuaW1hdGlvbiBvbiBv
cGFjaXR5IHsKLSAgICAgICAgICAgICAgICBydW5uaW5nOiBwaWxsLm9ubGluZQorICAgICAgICAg
ICAgICAgIHJ1bm5pbmc6IHBpbGwub25saW5lICYmIFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQKICAg
ICAgICAgICAgICAgICBsb29wczogQW5pbWF0aW9uLkluZmluaXRlCiAgICAgICAgICAgICAgICAg
TnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMS4wOyB0bzogMC40NTsgZHVyYXRpb246IFZiVG9rZW5z
Lm9ubGluZVB1bHNlTXMgLyAyOyBlYXNpbmcudHlwZTogRWFzaW5nLkluT3V0U2luZSB9CiAgICAg
ICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMC40NTsgdG86IDEuMDsgZHVyYXRp
b246IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAyOyBlYXNpbmcudHlwZTogRWFzaW5nLkluT3V0
U2luZSB9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1ZiVG9rZW5zLnFtbCBiL2FwcC9ndWkvVmJUb2tl
bnMucW1sCmluZGV4IDUyYTM0ZGUuLjdjZDg4ZDAgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVmJUb2tl
bnMucW1sCisrKyBiL2FwcC9ndWkvVmJUb2tlbnMucW1sCkBAIC0xLDU3ICsxLDYzIEBACiBwcmFn
bWEgU2luZ2xldG9uCiBpbXBvcnQgUXRRdWljayAyLjkKIGltcG9ydCBTdHJlYW1pbmdQcmVmZXJl
bmNlcyAxLjAKK2ltcG9ydCBFY2xpcHNlUHJvZmlsZXMgMS4wCiAKLS8vIFZpYmVtaXMgcmVkZXNp
Z24gZGVzaWduIHRva2Vucy4KKy8vIENyaW1zb24gR2xhc3Mg4oCUIEVjbGlwc2VPUyBmcm9udGVu
ZCBkZXNpZ24gdG9rZW5zLgogLy8gRGFyayB0aGVtZSBvbmx5LiBDYW52YXMgMTkyMHgxMjAwIChM
ZWdpb24gR28gUyksCiAvLyBzY2FsZXMgdG8gMTI4MHg4MDAgKFN0ZWFtIERlY2spIHZpYSBhbmNo
b3JzL0xheW91dHMg4oCUIG5ldmVyIGhhcmQtY29kZSBjb29yZGluYXRlcyBhZ2FpbnN0IHRoZXNl
LgogLy8gUmVnaXN0ZXJlZCBhcyBhIFFNTCBzaW5nbGV0b24gaW4gYXBwL21haW4uY3BwOiBxbWxS
ZWdpc3RlclNpbmdsZXRvblR5cGUocXJjOi9ndWkvVmJUb2tlbnMucW1sKS4KIFF0T2JqZWN0IHsK
ICAgICBpZDogdAogCisgICAgcmVhZG9ubHkgcHJvcGVydHkgcmVhbCB0ZXh0U2NhbGU6IEVjbGlw
c2VQcm9maWxlcy50ZXh0U2NhbGUgLyAxMDAKKyAgICByZWFkb25seSBwcm9wZXJ0eSBib29sIG1v
dGlvbkVuYWJsZWQ6ICFFY2xpcHNlUHJvZmlsZXMucmVkdWNlZE1vdGlvbgorCiAgICAgLy8gLS0t
LSBDb2xvciAtLS0tCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdBcHA6ICAgICAgICAi
IzA4MDkwQiIgIC8vIG91dGVybW9zdCBhcHAgYmcgYmVoaW5kIHRoZSByb3VuZGVkIHdpbmRvdwot
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnV2luZG93OiAgICAgIiMwRTEwMTMiICAvLyBt
YWluIHNjcmVlbiBiYWNrZ3JvdW5kCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdFbGV2
OiAgICAgICAiIzE1MTgxRCIgIC8vIGNhcmRzLCBwYW5lbHMsIGRpYWxvZ3MsIHNpZGViYXIgcm93
cwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxldjI6ICAgICAgIiMxQjFGMjYiICAv
LyBmb2N1c2VkL3NlbGVjdGVkIHN1cmZhY2UgZmlsbCwgY2hpcHMKLSAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBiZ0Zvb3RlcjogICAgICIjMEIwRDEwIiAgLy8gYm90dG9tIGdhbWVwYWQgaGlu
dCBiYXIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdHJva2U6ICAgICAgIFF0LnJnYmEo
MSwgMSwgMSwgMC4wOCkgIC8vIGRlZmF1bHQgMXB4IGNhcmQgYm9yZGVyCisgICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3IgYmdBcHA6ICAgICAgICAiIzA2MDYwNyIgIC8vIG91dGVybW9zdCBhcHAg
YmcgYmVoaW5kIHRoZSByb3VuZGVkIHdpbmRvdworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9y
IGJnV2luZG93OiAgICAgIiMwQjBCMEUiICAvLyBtYWluIHNjcmVlbiBiYWNrZ3JvdW5kCisgICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdFbGV2OiAgICAgICAiIzE1MTMxNiIgIC8vIGNhcmRz
LCBwYW5lbHMsIGRpYWxvZ3MsIHNpZGViYXIgcm93cworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIGJnRWxldjI6ICAgICAgIiMyNzFCMjIiICAvLyBmb2N1c2VkL3NlbGVjdGVkIHN1cmZhY2Ug
ZmlsbCwgY2hpcHMKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0Zvb3RlcjogICAgICIj
MDkwODBCIiAgLy8gYm90dG9tIGdhbWVwYWQgaGludCBiYXIKKyAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciBzdHJva2U6ICAgICAgIFF0LnJnYmEoMSwgMSwgMSwgRWNsaXBzZVByb2ZpbGVzLmhp
Z2hDb250cmFzdCA/IDAuMjUgOiAwLjA4KSAgLy8gZGVmYXVsdCAxcHggY2FyZCBib3JkZXIKICAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdHJva2VTb2Z0OiAgIFF0LnJnYmEoMSwgMSwgMSwg
MC4wNikgIC8vIGhlYWRlci9mb290ZXIgZGl2aWRlcnMKICAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciB0ZXh0OiAgICAgICAgICIjRUNFRUYxIiAgLy8gcHJpbWFyeSB0ZXh0Ci0gICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3IgdGV4dERpbTogICAgICAiIzk4QTFBQiIgIC8vIHNlY29uZGFyeSAv
IGxhYmVsIHRleHQKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0RGltOiAgICAgIChF
Y2xpcHNlUHJvZmlsZXMuaGlnaENvbnRyYXN0ID8gIiNEM0Q1REMiIDogIiM5OEExQUIiKSAgLy8g
c2Vjb25kYXJ5IC8gbGFiZWwgdGV4dAogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRN
dXRlOiAgICAgIiNCOUMwQzgiICAvLyB0ZXJ0aWFyeSAvIGluYWN0aXZlIGl0ZW0gbGFiZWxzCiAK
LSAgICAvLyBBY2NlbnQgaXMgc3dhcHBhYmxlIOKAlCBvbmUgb2YgdGhlIDQgY3VyYXRlZCB2YWx1
ZXMuIEluZGV4IDAgaXMgdGhlIFZpYmVtaXMgYnJhbmQKLSAgICAvLyB0ZWFsICMwMENDQ0MgKEJM
LTIwNzcpOiB0aGUgc2luZ2xlIGNhbm9uaWNhbCBhY2NlbnQgdGhhdCBUaGVtZS5xbWwgKyBhbGwg
bGl0ZXJhbHMgbm93Ci0gICAgLy8gcmVzb2x2ZSB0aHJvdWdoLCBhbmQgdGhlIGFuY2hvciBmb3Ig
dGhlIFAzLjE3L1AzLjE4IGRlc2lnbiB3b3JrLgotICAgIHJlYWRvbmx5IHByb3BlcnR5IHZhciBh
Y2NlbnRPcHRpb25zOiAgWyIjMDBDQ0NDIiwgIiM3QzhDRjgiLCAiIzNFRDU5OCIsICIjRjBBODY4
Il0KKyAgICAvLyBQcmVzZXJ2ZSBsZWdhY3kgaW5kaWNlcyAwLi4zOyBhcHBlbmQgY29sb3JzIGFu
ZCBkZWZhdWx0IG5ldyBwcmVmZXJlbmNlcyB0byBjcmltc29uLgorICAgIHJlYWRvbmx5IHByb3Bl
cnR5IHZhciBhY2NlbnRPcHRpb25zOiAgWyIjMDBDQ0NDIiwgIiM3QzhDRjgiLCAiIzNFRDU5OCIs
ICIjRjBBODY4IiwgIiNEQzM2NTgiLCAiI0YyNUQ2NCIsICIjRjU4MzQ3IiwgIiNGMUJDNDUiLCAi
I0I3REM2MyIsICIjNjNDQ0FFIiwgIiM2M0M0RUQiLCAiIzZDOUZGRiIsICIjQUQ4NUY1IiwgIiNF
OTc2QkMiLCAiI0NBRDBEQSIsICIjRDk5NUFDIl0KICAgICAvLyBCb3VuZCB0byB0aGUgc2F2ZWQg
cHJlZmVyZW5jZSAoU2V0dGluZ3MgPiBhY2NlbnQgcGlja2VyKTsgcGVyc2lzdHMgYWNyb3NzIHJl
c3RhcnRzLgogICAgIHByb3BlcnR5IGludCBhY2NlbnRJbmRleDogU3RyZWFtaW5nUHJlZmVyZW5j
ZXMudWlBY2NlbnRJbmRleAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAg
ICAgYWNjZW50T3B0aW9uc1thY2NlbnRJbmRleF0KLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xv
ciBhY2NlbnRIaTogICAgICIjNkFEREU3IiAgLy8gYWNjZW50IGdyYWRpZW50IGxpZ2h0IHN0b3Ag
LyBsaW5rIGhvdmVyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50OiAgICAgICBh
Y2NlbnRPcHRpb25zW01hdGgubWF4KDAsIE1hdGgubWluKGFjY2VudE9wdGlvbnMubGVuZ3RoIC0g
MSwgYWNjZW50SW5kZXgpKV0KKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRIaTog
ICAgIFF0LmxpZ2h0ZXIoYWNjZW50LCAxLjE4KSAgLy8gYWNjZW50IGdyYWRpZW50IGxpZ2h0IHN0
b3AgLyBsaW5rIGhvdmVyCiAKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNPbmxp
bmU6ICAiIzNFRDU5OCIgIC8vIG9ubGluZSBkb3QsIFJFU1VNRSBiYWRnZQogICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIHN0YXR1c09mZmxpbmU6ICIjNUE2MjZDIiAgLy8gb2ZmbGluZSBkb3Qg
LyBncmV5ZWQgbW9uaXRvcgogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN0YXR1c0Rhbmdl
cjogICIjRjI2RDZEIiAgLy8gZGVzdHJ1Y3RpdmUgKERlbGV0ZSBQQykKIAotICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIHRleHRPbkFjY2VudDogIiMwODA5MEIiICAvLyB0ZXh0IG9uIGFuIGFj
Y2VudC1maWxsZWQgYnV0dG9uCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dE9uQWNj
ZW50OiAiIzA2MDYwNyIgIC8vIHRleHQgb24gYW4gYWNjZW50LWZpbGxlZCBidXR0b24KIAorICAg
IHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgZ2xhc3NPcGFjaXR5OiBFY2xpcHNlUHJvZmlsZXMuaGln
aENvbnRyYXN0ID8gMS4wIDogMC45MgorICAgIHJlYWRvbmx5IHByb3BlcnR5IHN0cmluZyBkZXNp
Z25OYW1lOiAiQ3JpbXNvbiBHbGFzcyIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBnbGFz
c1RvcDogRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdCA/ICIjMjUyMTI2IiA6ICIjMjExRDIz
IgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGdsYXNzRWRnZTogUXQucmdiYSgxLDEsMSxF
Y2xpcHNlUHJvZmlsZXMuaGlnaENvbnRyYXN0ID8gMC4zNSA6IDAuMTYpCiAgICAgLy8gLS0tLSBU
eXBvZ3JhcGh5IChmYW1pbGllcyArIHNpemVzOyB3ZWlnaHRzIHBlciB0aGUgdHlwZSBzY2FsZSkg
LS0tLQogICAgIHJlYWRvbmx5IHByb3BlcnR5IHN0cmluZyBmb250RGlzcGxheTogIlNvcmEiICAg
ICAvLyB0aXRsZXMsIGNhcmQgbmFtZXMsIHdvcmRtYXJrLCBhbGwtY2FwcyBsYWJlbHMKICAgICBy
ZWFkb25seSBwcm9wZXJ0eSBzdHJpbmcgZm9udEJvZHk6ICAgICJNYW5yb3BlIiAgLy8gYm9keSAr
IFVJIHRleHQKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZVNjcmVlblRpdGxlOiAgMzQK
LSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZVNlY3Rpb25UaXRsZTogMjgKLSAgICByZWFk
b25seSBwcm9wZXJ0eSBpbnQgc2l6ZUNhcmROYW1lOiAgICAgMjcKLSAgICByZWFkb25seSBwcm9w
ZXJ0eSBpbnQgc2l6ZUJvZHk6ICAgICAgICAgMTYKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQg
c2l6ZUxhYmVsOiAgICAgICAgMTQKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZUJhZGdl
OiAgICAgICAgMTMKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZVdvcmRtYXJrOiAgICAg
MjEKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZVNjcmVlblRpdGxlOiAgTWF0aC5yb3Vu
ZCgzNCAqIHRleHRTY2FsZSkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZVNlY3Rpb25U
aXRsZTogTWF0aC5yb3VuZCgyOCAqIHRleHRTY2FsZSkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBp
bnQgc2l6ZUNhcmROYW1lOiAgICAgTWF0aC5yb3VuZCgyNyAqIHRleHRTY2FsZSkKKyAgICByZWFk
b25seSBwcm9wZXJ0eSBpbnQgc2l6ZUJvZHk6ICAgICAgICAgTWF0aC5yb3VuZCgxNiAqIHRleHRT
Y2FsZSkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZUxhYmVsOiAgICAgICAgTWF0aC5y
b3VuZCgxNCAqIHRleHRTY2FsZSkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZUJhZGdl
OiAgICAgICAgTWF0aC5yb3VuZCgxMyAqIHRleHRTY2FsZSkKKyAgICByZWFkb25seSBwcm9wZXJ0
eSBpbnQgc2l6ZVdvcmRtYXJrOiAgICAgTWF0aC5yb3VuZCgyMSAqIHRleHRTY2FsZSkKICAgICBy
ZWFkb25seSBwcm9wZXJ0eSByZWFsIHdvcmRtYXJrU3BhY2luZzogMy4wCiAgICAgcmVhZG9ubHkg
cHJvcGVydHkgcmVhbCBiYWRnZVNwYWNpbmc6ICAgIDEuMgogCiAgICAgLy8gLS0tLSBSYWRpdXMg
LS0tLQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCByYWRpdXNXaW5kb3c6ICAgICAyMAotICAg
IHJlYWRvbmx5IHByb3BlcnR5IGludCByYWRpdXNDYXJkOiAgICAgICAxNgorICAgIHJlYWRvbmx5
IHByb3BlcnR5IGludCByYWRpdXNDYXJkOiAgICAgICAyMAogICAgIHJlYWRvbmx5IHByb3BlcnR5
IGludCByYWRpdXNEaWFsb2c6ICAgICAyNAogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCByYWRp
dXNDb250cm9sOiAgICAxNAogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCByYWRpdXNJY29uQnV0
dG9uOiAxNApAQCAtNTksMTIgKzY1LDEyIEBAIFF0T2JqZWN0IHsKICAgICByZWFkb25seSBwcm9w
ZXJ0eSBpbnQgcmFkaXVzQmFkZ2U6ICAgICAgNwogCiAgICAgLy8gLS0tLSBTcGFjaW5nIC0tLS0K
LSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2NyZWVuUGFkWDogNTYKLSAgICByZWFkb25seSBw
cm9wZXJ0eSBpbnQgc2NyZWVuUGFkWTogNTIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2Ny
ZWVuUGFkWDogMjQKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2NyZWVuUGFkWTogMjQKICAg
ICByZWFkb25seSBwcm9wZXJ0eSBpbnQgaGVhZGVySDogICAgODQKICAgICByZWFkb25seSBwcm9w
ZXJ0eSBpbnQgZm9vdGVySDogICAgNzIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgY2FyZEdh
cDogICAgMzIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgdGlsZUdhcDogICAgMzYKKyAgICBy
ZWFkb25seSBwcm9wZXJ0eSBpbnQgY2FyZEdhcDogICAgMjAKKyAgICByZWFkb25seSBwcm9wZXJ0
eSBpbnQgdGlsZUdhcDogICAgMjAKICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgaWNvbkJ1dHRv
bjogNTIKIAogICAgIC8vIC0tLS0gR2FtZXBhZCBlcmdvbm9taWNzIC0tLS0KQEAgLTgzLDcgKzg5
LDcgQEAgUXRPYmplY3QgewogICAgIC8vIC0tLS0gTW90aW9uIChtcykgLS0tLQogICAgIHJlYWRv
bmx5IHByb3BlcnR5IGludCBvbmxpbmVQdWxzZU1zOiAyNDAwICAgLy8gb3BhY2l0eSAxIC0+IDAu
NDUgLT4gMSwgaW5maW5pdGUKICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgY2FyZXRCbGlua01z
OiAgMTAwMCAgIC8vIEFkZC1QQyBpbnB1dCBjYXJldAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGlu
dCBzaGVldEluTXM6ICAgICAyMjAgICAgLy8gc2lkZS1zaGVldCBzbGlkZS1pbgorICAgIHJlYWRv
bmx5IHByb3BlcnR5IGludCBzaGVldEluTXM6ICAgICBtb3Rpb25FbmFibGVkID8gMjIwIDogMCAg
ICAvLyBzaWRlLXNoZWV0IHNsaWRlLWluCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZGlh
bG9nU2NyaW06IFF0LnJnYmEoNC8yNTUsIDUvMjU1LCA3LzI1NSwgMC43MikKICAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBzaGVldFNjcmltOiAgUXQucmdiYSg0LzI1NSwgNS8yNTUsIDcvMjU1
LCAwLjYwKQogCkBAIC0xMTksNyArMTI1LDcgQEAgUXRPYmplY3QgewogICAgIC8vIHRleHRPbkFj
Y2VudCAoIzA4MDkwQikgaXMgZGVmaW5lZCBpbiB0aGUgYmFzZSBibG9jayBhYm92ZSDigJQgdGV4
dCBvbiBhbiBhY2NlbnQgZmlsbC4KIAogICAgIC8vIC0tLS0gSW50ZXJhY3RpdmUgc3RhdGVzOiBu
b3JtYWwgLyBob3ZlciAvIGZvY3VzIC8gcHJlc3NlZCAvIGRpc2FibGVkIC0tLS0KLSAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2VkOiAgICAgICIjMDBBM0EzIiAvLyBwcmVz
c2VkIGFjY2VudGVkIGNvbnRyb2wgKG1hdGNoZXMgbGVnYWN5IFRoZW1lLmFjY2VudFByZXNzZWQp
CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDogICAgICBRdC5kYXJr
ZXIoYWNjZW50LCAxLjE4KSAvLyBwcmVzc2VkIGFjY2VudGVkIGNvbnRyb2wgKG1hdGNoZXMgbGVn
YWN5IFRoZW1lLmFjY2VudFByZXNzZWQpCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW50
ZXJhY3RpdmVIb3ZlcjogICBiZ0VsZXYyICAgIC8vIHJvdyAvIGxpc3QtaXRlbSAvIGljb24tYnV0
dG9uIGhvdmVyIGZpbGwKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZUZv
Y3VzOiAgIGZvY3VzZWRGaWxsLy8gZm9jdXNlZCBmaWxsICg9IGJnRWxldjIpIOKAlCBwYWlyIHdp
dGggdGhlIGZvY3VzIHJpbmcKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2
ZVByZXNzZWQ6IGJnRWxldiAgICAgLy8gcHJlc3NlZCBuZXV0cmFsIGZpbGwgKHJlY2VkZXMgdW5k
ZXIgdGhlIHByZXNzKQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9WYldlbGNvbWVTaGVldC5xbWwgYi9h
cHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFtbAppbmRleCAxNzMxMTliLi5hMTRlYWU3IDEwMDY0NAot
LS0gYS9hcHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFtbAorKysgYi9hcHAvZ3VpL1ZiV2VsY29tZVNo
ZWV0LnFtbApAQCAtMjYsNyArMjYsNyBAQCBOYXZpZ2FibGVEaWFsb2cgewogICAgIC8vIFRva2Vu
IHNjcmltIGJlaGluZCB0aGUgbW9kYWwgY2FyZCAobWF0Y2hlcyB0aGUgcmVkZXNpZ24gZGlhbG9n
IGxhbmd1YWdlKS4KICAgICBPdmVybGF5Lm1vZGFsOiBSZWN0YW5nbGUgeyBjb2xvcjogVmJUb2tl
bnMuZGlhbG9nU2NyaW0gfQogCi0gICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICBiYWNr
Z3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgIGNvbG9yOiBWYlRva2Vucy5iZ0Vs
ZXYKICAgICAgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNEaWFsb2cKICAgICAgICAgYm9yZGVy
LndpZHRoOiAxCkBAIC0xMDgsMTQgKzEwOCwxMyBAQCBOYXZpZ2FibGVEaWFsb2cgewogICAgICAg
ICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UyICAvLyA4CiAgICAgICAgICAgICBSb3dMYXlv
dXQgewogICAgICAgICAgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMgotICAgICAgICAg
ICAgICAgIFJlY3RhbmdsZSB7Ci0gICAgICAgICAgICAgICAgICAgIHdpZHRoOiAxMzsgaGVpZ2h0
OiAxMwotICAgICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYWNjZW50Ci0gICAgICAg
ICAgICAgICAgICAgIHJvdGF0aW9uOiA0NQorICAgICAgICAgICAgICAgIEltYWdlIHsKKyAgICAg
ICAgICAgICAgICAgICAgc291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyIKKyAgICAg
ICAgICAgICAgICAgICAgTGF5b3V0LnByZWZlcnJlZFdpZHRoOiAyODsgTGF5b3V0LnByZWZlcnJl
ZEhlaWdodDogMjgKICAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmFsaWdubWVudDogUXQuQWxp
Z25WQ2VudGVyCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgIFRleHQgewotICAg
ICAgICAgICAgICAgICAgICB0ZXh0OiAiVklCRU1JUyIKKyAgICAgICAgICAgICAgICAgICAgdGV4
dDogIkVDTElQU0UiCiAgICAgICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5m
b250RGlzcGxheQogICAgICAgICAgICAgICAgICAgICBmb250LndlaWdodDogRm9udC5FeHRyYUJv
bGQKICAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnNpemVXb3Jk
bWFyayAgICAgIC8vIDIxCkBAIC0xMjUsNyArMTI0LDcgQEAgTmF2aWdhYmxlRGlhbG9nIHsKICAg
ICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAgICAgICAgICAgICBUZXh0IHsKLSAgICAg
ICAgICAgICAgICB0ZXh0OiBxc1RyKCJXZWxjb21lIHRvIFZpYmVtaXMiKQorICAgICAgICAgICAg
ICAgIHRleHQ6IHFzVHIoIldlbGNvbWUgdG8gRWNsaXBzZSIpCiAgICAgICAgICAgICAgICAgZm9u
dC5mYW1pbHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5CiAgICAgICAgICAgICAgICAgZm9udC53ZWln
aHQ6IEZvbnQuQm9sZAogICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50
eXBlRGlzcGxheSAgICAgICAgICAgLy8gMzQKQEAgLTE5NSw3ICsxOTQsNyBAQCBOYXZpZ2FibGVE
aWFsb2cgewogICAgICAgICAgICAgSW5mb1JvdyB7CiAgICAgICAgICAgICAgICAgZ2x5cGg6ICJh
cHBzIgogICAgICAgICAgICAgICAgIHRpdGxlOiBxc1RyKCJBZGQgdG8gU3RlYW0iKQotICAgICAg
ICAgICAgICAgIHN1YjogcXNUcigiT24gU3RlYW0gRGVjayAvIFN0ZWFtT1MsIGFkZCBWaWJlbWlz
IHRvIFN0ZWFtIGZyb20gRGVza3RvcCBNb2RlIHNvIGl0IGFwcGVhcnMgaW4gR2FtZSBNb2RlLiIp
CisgICAgICAgICAgICAgICAgc3ViOiBxc1RyKCJPbiBTdGVhbSBEZWNrIC8gU3RlYW1PUywgYWRk
IEVjbGlwc2UgdG8gU3RlYW0gZnJvbSBEZXNrdG9wIE1vZGUgc28gaXQgYXBwZWFycyBpbiBHYW1l
IE1vZGUuIikKICAgICAgICAgICAgIH0KIAogICAgICAgICAgICAgLy8gMykgU2V0dGluZ3MuCmRp
ZmYgLS1naXQgYS9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuY3BwIGIvYXBwL2d1aS9jb21wdXRlcm1v
ZGVsLmNwcAppbmRleCA2M2M3MTE1Li4yZDQ4N2ZmIDEwMDY0NAotLS0gYS9hcHAvZ3VpL2NvbXB1
dGVybW9kZWwuY3BwCisrKyBiL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5jcHAKQEAgLTEsMyArMSw0
IEBACisjaW5jbHVkZSA8UVVybD4KICNpbmNsdWRlICJjb21wdXRlcm1vZGVsLmgiCiAjaW5jbHVk
ZSAiYmFja2VuZC9zZXJ2ZXJwZXJtaXNzaW9ucy5oIgogI2luY2x1ZGUgInNldHRpbmdzL3ZpYmVt
aXNzZXR0aW5ncy5oIgpAQCAtNDIwLDMgKzQyMSwxMyBAQCB2b2lkIENvbXB1dGVyTW9kZWw6Omhh
bmRsZUNvbXB1dGVyU3RhdGVDaGFuZ2VkKE52Q29tcHV0ZXIqIGNvbXB1dGVyKQogfQogCiAjaW5j
bHVkZSAiY29tcHV0ZXJtb2RlbC5tb2MiCisKK1FWYXJpYW50TWFwIENvbXB1dGVyTW9kZWw6OmNy
aW1zb25Ib3N0KGludCBpbmRleCkgY29uc3QKK3sKKyAgICBpZiAoaW5kZXggPCAwIHx8IGluZGV4
ID49IG1fQ29tcHV0ZXJzLmNvdW50KCkpIHJldHVybiB7fTsKKyAgICBhdXRvIGNvbXB1dGVyID0g
bV9Db21wdXRlcnNbaW5kZXhdOworICAgIFFSZWFkTG9ja2VyIGxvY2soJmNvbXB1dGVyLT5sb2Nr
KTsKKyAgICBRVXJsIHVybDsgdXJsLnNldFNjaGVtZSgiaHR0cHMiKTsgdXJsLnNldEhvc3QoY29t
cHV0ZXItPmFjdGl2ZUFkZHJlc3MuYWRkcmVzcygpKTsKKyAgICB1cmwuc2V0UG9ydChjb21wdXRl
ci0+YWN0aXZlQWRkcmVzcy5wb3J0KCkgPiAwID8gY29tcHV0ZXItPmFjdGl2ZUFkZHJlc3MucG9y
dCgpICsgMSA6IDQ3OTkwKTsKKyAgICByZXR1cm4ge3siaWQiLCBjb21wdXRlci0+dXVpZH0sIHsi
dXJsIiwgdXJsLnRvU3RyaW5nKCl9fTsKK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvY29tcHV0ZXJt
b2RlbC5oIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmgKaW5kZXggNmVjYWUzMC4uMmVlNzNjMSAx
MDA2NDQKLS0tIGEvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmgKKysrIGIvYXBwL2d1aS9jb21wdXRl
cm1vZGVsLmgKQEAgLTQzLDYgKzQzLDggQEAgcHVibGljOgogCiAgICAgdmlydHVhbCBRSGFzaDxp
bnQsIFFCeXRlQXJyYXk+IHJvbGVOYW1lcygpIGNvbnN0IG92ZXJyaWRlOwogCisgICAgUV9JTlZP
S0FCTEUgUVZhcmlhbnRNYXAgY3JpbXNvbkhvc3QoaW50IGNvbXB1dGVySW5kZXgpIGNvbnN0Owor
CiAgICAgUV9JTlZPS0FCTEUgdm9pZCBkZWxldGVDb21wdXRlcihpbnQgY29tcHV0ZXJJbmRleCk7
CiAKICAgICBRX0lOVk9LQUJMRSBRU3RyaW5nIGdlbmVyYXRlUGluU3RyaW5nKCk7CmRpZmYgLS1n
aXQgYS9hcHAvZ3VpL21haW4ucW1sIGIvYXBwL2d1aS9tYWluLnFtbAppbmRleCA5YmNlNTEwLi4x
NGYzNTA4IDEwMDY0NAotLS0gYS9hcHAvZ3VpL21haW4ucW1sCisrKyBiL2FwcC9ndWkvbWFpbi5x
bWwKQEAgLTEyLDggKzEyLDI1IEBAIGltcG9ydCBTeXN0ZW1Qcm9wZXJ0aWVzIDEuMAogaW1wb3J0
IFNkbEdhbWVwYWRLZXlOYXZpZ2F0aW9uIDEuMAogaW1wb3J0IFVpU291bmRNYW5hZ2VyIDEuMAog
aW1wb3J0IFRoZW1lIDEuMAoraW1wb3J0IENyaW1zb25TdGF0dXMgMS4wCitpbXBvcnQgU3lzdGVt
Q29udHJvbHMgMS4wCiAKIEFwcGxpY2F0aW9uV2luZG93IHsKKyAgICBNYXRlcmlhbC50aGVtZTog
TWF0ZXJpYWwuRGFyaworICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAg
TWF0ZXJpYWwucHJpbWFyeTogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYmFja2dyb3Vu
ZDogVmJUb2tlbnMuYmdXaW5kb3cKKyAgICBNYXRlcmlhbC5mb3JlZ3JvdW5kOiBWYlRva2Vucy50
ZXh0CisgICAgY29sb3I6IFZiVG9rZW5zLmJnQXBwCisgICAgcGFsZXR0ZS53aW5kb3c6IFZiVG9r
ZW5zLmJnV2luZG93CisgICAgcGFsZXR0ZS53aW5kb3dUZXh0OiBWYlRva2Vucy50ZXh0CisgICAg
cGFsZXR0ZS5iYXNlOiBWYlRva2Vucy5iZ0FwcAorICAgIHBhbGV0dGUuYWx0ZXJuYXRlQmFzZTog
VmJUb2tlbnMuYmdFbGV2CisgICAgcGFsZXR0ZS50ZXh0OiBWYlRva2Vucy50ZXh0CisgICAgcGFs
ZXR0ZS5idXR0b246IFZiVG9rZW5zLmJnRWxldgorICAgIHBhbGV0dGUuYnV0dG9uVGV4dDogVmJU
b2tlbnMudGV4dAorICAgIHBhbGV0dGUuaGlnaGxpZ2h0OiBWYlRva2Vucy5hY2NlbnQKKyAgICBw
YWxldHRlLmhpZ2hsaWdodGVkVGV4dDogVmJUb2tlbnMudGV4dE9uQWNjZW50CiAgICAgcHJvcGVy
dHkgYm9vbCBwb2xsaW5nQWN0aXZlOiBmYWxzZQogCiAgICAgLy8gU2V0IGJ5IFNldHRpbmdzVmll
dyB0byBmb3JjZSB0aGUgYmFjayBvcGVyYXRpb24gdG8gcG9wIGFsbApAQCAtNDYsMTQgKzYzLDEz
IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgLy8gaW4gb3JkZXIgdG8gaW1wcm92ZSBj
b250cmFzdCBiZXR3ZWVuIEdGRSdzIHBsYWNlaG9sZGVyIGJveCBhcnQKICAgICAgICAgLy8gYW5k
IHRoZSBiYWNrZ3JvdW5kIG9mIHRoZSBhcHAgZ3JpZC4KICAgICAgICAgaWYgKFN5c3RlbVByb3Bl
cnRpZXMudXNlc01hdGVyaWFsM1RoZW1lKSB7Ci0gICAgICAgICAgICBNYXRlcmlhbC5iYWNrZ3Jv
dW5kID0gVGhlbWUuYmFja2dyb3VuZAorICAgICAgICAgICAgLy8gVGhlbWUgcmVtYWlucyBhIGxp
dmUgYmluZGluZyB0byB0aGUgc2hhcmVkIHBhbGV0dGUuCiAgICAgICAgIH0KIAogICAgICAgICAv
LyBCcmlkZ2UgdGhlIE1hdGVyaWFsIHN0eWxlIHRvIHRoZSBWaWJlbWlzIGRlc2lnbiB0b2tlbnMg
c28gdGhlCiAgICAgICAgIC8vIE1hdGVyaWFsLXN0eWxlZCBwYWdlcyAoQ29tcHV0ZXJzIGdyaWQs
IEFwcCBncmlkLCBkaWFsb2dzKSBzaGFyZSB0aGUgc2FtZQogICAgICAgICAvLyBhY2NlbnQvYmFj
a2dyb3VuZCBzeXN0ZW0gYXMgdGhlIHRva2VuLW5hdGl2ZSBwYWdlcy4gU2VlIGRvY3MvREVTSUdO
X1NZU1RFTS5tZC4KLSAgICAgICAgTWF0ZXJpYWwudGhlbWUgPSBNYXRlcmlhbC5EYXJrCi0gICAg
ICAgIE1hdGVyaWFsLmFjY2VudCA9IFRoZW1lLmFjY2VudAorICAgICAgICAvLyBNYXRlcmlhbCB0
aGVtZS9hY2NlbnQgYXJlIGJvdW5kIGF0IHRoZSByb290LCBpbmNsdWRpbmcgYWZ0ZXIgY2hhbmdl
cy4KIAogICAgICAgICBTZGxHYW1lcGFkS2V5TmF2aWdhdGlvbi5lbmFibGUoKQogICAgIH0KQEAg
LTEyOSw2ICsxNDUsOCBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgIH0KICAgICB9CiAK
KyAgICBDcmltc29uR2xhc3NCYWNrZHJvcCB7IGFuY2hvcnMuZmlsbDpwYXJlbnQgfQorCiAgICAg
U3RhY2tWaWV3IHsKICAgICAgICAgaWQ6IHN0YWNrVmlldwogICAgICAgICBhbmNob3JzLmZpbGw6
IHBhcmVudApAQCAtMjY3LDYgKzI4NSwyNSBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAg
IH0KICAgICB9CiAKKyAgICBDcmltc29uU3RhdHVzRGlhbG9nIHsgaWQ6IGNyaW1zb25QYW5lbCB9
CisgICAgU3lzdGVtQ29ubmVjdGlvbnNEaWFsb2cgeyBpZDogY29ubmVjdGlvblBhbmVsIH0KKyAg
ICBFY2xpcHNlQWJvdXREaWFsb2cgeyBpZDogZWNsaXBzZUFib3V0IH0KKyAgICBFY2xpcHNlQ29u
dHJvbENlbnRlciB7CisgICAgICAgIGlkOiBlY2xpcHNlQ2VudGVyCisgICAgICAgIGNhbk1hbmFn
ZTogU3lzdGVtUHJvcGVydGllcy5oYXNCcm93c2VyCisgICAgICAgIGNhbldha2U6IHRvb2xCYXIu
b25QY1ZpZXcKKyAgICAgICAgb25XYWtlUmVxdWVzdGVkOiB7CisgICAgICAgICAgICBpZiAodG9v
bEJhci5vblBjVmlldykgc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmNvbXB1dGVyTW9kZWwud2FrZUNv
bXB1dGVyKHN0YWNrVmlldy5jdXJyZW50SXRlbS5jdXJyZW50SW5kZXgpCisgICAgICAgIH0KKyAg
ICAgICAgb25OYXZpZ2F0ZVJlcXVlc3RlZDogeworICAgICAgICAgICAgaWYgKGRlc3RpbmF0aW9u
ID09PSAid2lmaSIgfHwgZGVzdGluYXRpb24gPT09ICJidCIpIHsgY29ubmVjdGlvblBhbmVsLmtp
bmQgPSBkZXN0aW5hdGlvbjsgY29ubmVjdGlvblBhbmVsLm9wZW4oKSB9CisgICAgICAgICAgICBl
bHNlIGlmIChkZXN0aW5hdGlvbiA9PT0gInNldHRpbmdzIikgbmF2aWdhdGVUbygicXJjOi9ndWkv
U2V0dGluZ3NWaWV3LnFtbCIsICJTZXR0aW5nc1ZpZXciKQorICAgICAgICAgICAgZWxzZSBpZiAo
ZGVzdGluYXRpb24gPT09ICJob3N0IikgeyBDcmltc29uU3RhdHVzLnNlbGVjdEhvc3QoZWNsaXBz
ZUNlbnRlci5ob3N0LmlkIHx8ICIiLCBlY2xpcHNlQ2VudGVyLmhvc3QudXJsIHx8ICIiKTsgY3Jp
bXNvblBhbmVsLmtpbmQgPSAiaG9zdCI7IGNyaW1zb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAg
ICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJhYm91dCIpIHsgZWNsaXBzZUFib3V0LmluZm8g
PSBTeXN0ZW1Db250cm9scy5zdGF0ZTsgZWNsaXBzZUFib3V0Lm9wZW4oKSB9CisgICAgICAgICAg
ICBlbHNlIGlmIChkZXN0aW5hdGlvbiA9PT0gIm1hbmFnZW1lbnQiICYmIFN5c3RlbVByb3BlcnRp
ZXMuaGFzQnJvd3NlcikgU3lzdGVtUHJvcGVydGllcy5vcGVuVXJsKGVjbGlwc2VDZW50ZXIuaG9z
dC51cmwpCisgICAgICAgIH0KKyAgICB9CisKICAgICBoZWFkZXI6IFRvb2xCYXIgewogICAgICAg
ICBpZDogdG9vbEJhcgogICAgICAgICAvLyBSZWRlc2lnbjogRVZFUlkgcmVkZXNpZ25lZCBsYXVu
Y2hlciBzY3JlZW4gKENvbXB1dGVycywgQXBwIGdyaWQsIFNldHRpbmdzLCBIZWxwKQpAQCAtMzI1
LDcgKzM2Miw4IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgLy8gcmVkZXNpZ24gcmF0
aGVyIHRoYW4gdGhlIGRlZmF1bHQgTWF0ZXJpYWwgaW5kaWdvLCB3aGljaCByZWFkIGFzIGFuICJ1
Z2x5IGJsdWUiIGhlYWRlcgogICAgICAgICAvLyBjbGFzaGluZyB3aXRoIHRoZSBkYXJrIFVJIGJl
bG93IGl0LiBIZWlnaHQgaXMgY29uc3RhbnQgb24gdGhlIGhvbWUgc2NyZWVucyAobm8gcnVudGlt
ZQogICAgICAgICAvLyBnZW9tZXRyeSBjaGFuZ2UpIHNvIHRoZSBibGFjay1zY3JlZW4gZml4IGlz
IHByZXNlcnZlZC4KLSAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgYmFj
a2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgeworICAgICAgICAgICAgcmFkaXVzOjAKICAgICAg
ICAgICAgIGNvbG9yOiBWYlRva2Vucy5iZ1dpbmRvdwogICAgICAgICAgICAgUmVjdGFuZ2xlIHsK
ICAgICAgICAgICAgICAgICBhbmNob3JzLmJvdHRvbTogcGFyZW50LmJvdHRvbQpAQCAtMzM4LDIw
ICszNzYsMTkgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICAvLyBWSUJFTUlTIHdvcmRt
YXJrIChkaWFtb25kICsgd29yZG1hcmspLCBzaG93biBvbiB0aGUgQ29tcHV0ZXJzIHNjcmVlbiBp
biBwbGFjZSBvZiBhIHRpdGxlLAogICAgICAgICAvLyBtYXRjaGluZyB0aGUgZGVzaWduIGhlYWRl
ci4gTGVmdC1hbGlnbmVkIGF0IHRoZSBIVE1MJ3MgNDBweCBwYWRkaW5nLgogICAgICAgICBSb3cg
ewotICAgICAgICAgICAgdmlzaWJsZTogdG9vbEJhci5vblBjVmlldworICAgICAgICAgICAgdmlz
aWJsZTogdG9vbEJhci5vblBjVmlldyAmJiB0b29sQmFyLndpZHRoID4gODIwCiAgICAgICAgICAg
ICBhbmNob3JzLmxlZnQ6IHBhcmVudC5sZWZ0CiAgICAgICAgICAgICBhbmNob3JzLmxlZnRNYXJn
aW46IDQwCiAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGlj
YWxDZW50ZXIKICAgICAgICAgICAgIHNwYWNpbmc6IDExCi0gICAgICAgICAgICBSZWN0YW5nbGUg
eworICAgICAgICAgICAgSW1hZ2UgewogICAgICAgICAgICAgICAgIGFuY2hvcnMudmVydGljYWxD
ZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlcgotICAgICAgICAgICAgICAgIHdpZHRoOiAxMzsg
aGVpZ2h0OiAxMwotICAgICAgICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy5hY2NlbnQKLSAgICAg
ICAgICAgICAgICByb3RhdGlvbjogNDUKKyAgICAgICAgICAgICAgICB3aWR0aDogMjg7IGhlaWdo
dDogMjgKKyAgICAgICAgICAgICAgICBzb3VyY2U6ICJxcmM6L3Jlcy9lY2xpcHNlLWljb24uc3Zn
IgogICAgICAgICAgICAgfQogICAgICAgICAgICAgVGV4dCB7CiAgICAgICAgICAgICAgICAgYW5j
aG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVyCi0gICAgICAgICAgICAg
ICAgdGV4dDogIlZJQkVNSVMiCisgICAgICAgICAgICAgICAgdGV4dDogIkVDTElQU0UiCiAgICAg
ICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5CiAgICAgICAgICAg
ICAgICAgZm9udC53ZWlnaHQ6IEZvbnQuRXh0cmFCb2xkCiAgICAgICAgICAgICAgICAgZm9udC5w
aXhlbFNpemU6IDIxCkBAIC0zNjUsNyArNDAyLDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAg
ICAgICAgICAgLy8gSGlkZGVuIG9uIENvbXB1dGVycyAodGhlIHdvcmRtYXJrIHN0YW5kcyBpbikg
YW5kIG9uIHRoZSBBcHAgZ3JpZCAod2hpY2ggc2hvd3MgYQogICAgICAgICAgICAgLy8gbGVmdC1h
bGlnbmVkIGhvc3QgKyBzdGF0dXMgYmxvY2sgaW5zdGVhZCkuIE9uIFNldHRpbmdzL0hlbHAgaXQg
c2hvd3MgdGhlIHNjcmVlbiBuYW1lOwogICAgICAgICAgICAgLy8gdGhlIHN0cmVhbWluZyBzZWd1
ZXMga2VlcCB0aGVpciBkZWZhdWx0IG9iamVjdE5hbWUgdGl0bGUuCi0gICAgICAgICAgICB2aXNp
YmxlOiAhdG9vbEJhci5vblBjVmlldyAmJiAhdG9vbEJhci5vbkFwcFZpZXcgJiYgdG9vbEJhci53
aWR0aCA+IDcwMAorICAgICAgICAgICAgdmlzaWJsZTogIXRvb2xCYXIub25QY1ZpZXcgJiYgIXRv
b2xCYXIub25BcHBWaWV3ICYmIHRvb2xCYXIud2lkdGggPiA4MjAKICAgICAgICAgICAgIGFuY2hv
cnMuZmlsbDogcGFyZW50CiAgICAgICAgICAgICB0ZXh0OiB0b29sQmFyLm9uU2V0dGluZ3MgPyBx
c1RyKCJTZXR0aW5ncyIpCiAgICAgICAgICAgICAgICAgOiB0b29sQmFyLm9uSGVscCA/IHFzVHIo
IkhlbHAiKQpAQCAtNDg3LDYgKzUyNCw1NCBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAg
ICAgICAgICAgfQogICAgICAgICAgICAgfQogCisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0
dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogbmV0d29ya1N0YXR1c0J1dHRvbgorICAgICAgICAg
ICAgICAgIGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnIgorICAgICAg
ICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiV2ktRmkgc2V0dGluZ3MiKQorICAgICAg
ICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xU
aXAudGV4dDogcXNUcigiTmV0d29yazogJTEiKS5hcmcoQ3JpbXNvblN0YXR1cy5sb2NhbC5uZXR3
b3JrIHx8IHFzVHIoIlVuYXZhaWxhYmxlIikpCisgICAgICAgICAgICAgICAgb25DbGlja2VkOiB7
IGNvbm5lY3Rpb25QYW5lbC5raW5kID0gIndpZmkiOyBjb25uZWN0aW9uUGFuZWwub3BlbigpIH0K
KyAgICAgICAgICAgICAgICBLZXlzLm9uRG93blByZXNzZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRl
bS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgICAgICAgICAgICAgIFJlY3Rhbmds
ZSB7CisgICAgICAgICAgICAgICAgICAgIGFuY2hvcnMucmlnaHQ6IHBhcmVudC5yaWdodDsgYW5j
aG9ycy5ib3R0b206IHBhcmVudC5ib3R0b207IGFuY2hvcnMubWFyZ2luczogNQorICAgICAgICAg
ICAgICAgICAgICB3aWR0aDogODsgaGVpZ2h0OiA4OyByYWRpdXM6IDQKKyAgICAgICAgICAgICAg
ICAgICAgY29sb3I6IENyaW1zb25TdGF0dXMubG9jYWwuY29ubmVjdGVkID8gVmJUb2tlbnMuc3Rh
dHVzT25saW5lIDogVmJUb2tlbnMuc3RhdHVzT2ZmbGluZQorICAgICAgICAgICAgICAgIH0KKyAg
ICAgICAgICAgIH0KKyAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24geworICAgICAgICAg
ICAgICAgIGlkOiBibHVldG9vdGhTZXR0aW5nc0J1dHRvbgorICAgICAgICAgICAgICAgIGljb25T
b3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWJsdWV0b290aC5zdmciCisgICAgICAgICAgICAgICAg
QWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJCbHVldG9vdGggc2V0dGluZ3MiKQorICAgICAgICAgICAg
ICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4
dDogcXNUcigiUGFpciBjb250cm9sbGVycyBhbmQgaGVhZHBob25lcyIpCisgICAgICAgICAgICAg
ICAgb25DbGlja2VkOiB7IGNvbm5lY3Rpb25QYW5lbC5raW5kID0gImJ0IjsgY29ubmVjdGlvblBh
bmVsLm9wZW4oKSB9CisgICAgICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1Zp
ZXcuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAg
IH0KKyAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24geworICAgICAgICAgICAgICAgIGlk
OiBiYXR0ZXJ5U3RhdHVzQnV0dG9uCisgICAgICAgICAgICAgICAgaWNvblNvdXJjZTogInFyYzov
cmVzL2NyaW1zb24tYmF0dGVyeS5zdmciCisgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1l
OiBxc1RyKCJCYXR0ZXJ5IHN0YXR1cyIpCisgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxl
OiBob3ZlcmVkCisgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBDcmltc29uU3RhdHVzLmxv
Y2FsLmJhdHRlcnlQZXJjZW50ID49IDAgPyBxc1RyKCJCYXR0ZXJ5OiAlMSUg4oCiICUyIikuYXJn
KENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVBlcmNlbnQpLmFyZyhDcmltc29uU3RhdHVzLmxv
Y2FsLmJhdHRlcnlTdGF0ZSkgOiBxc1RyKCJCYXR0ZXJ5IHVuYXZhaWxhYmxlIikKKyAgICAgICAg
ICAgICAgICBvbkNsaWNrZWQ6IHsgY3JpbXNvblBhbmVsLmtpbmQgPSAiYmF0dGVyeSI7IGNyaW1z
b25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3Rh
Y2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAg
ICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAgICAg
ICBpZDogaG9zdEhhcmR3YXJlQnV0dG9uCisgICAgICAgICAgICAgICAgaWNvblNvdXJjZTogInFy
YzovcmVzL2NyaW1zb24taG9zdC5zdmciCisgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1l
OiBxc1RyKCJWaWJlcG9sbG8gaG9zdCBoYXJkd2FyZSBzdGF0cyIpCisgICAgICAgICAgICAgICAg
VG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCisgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBx
c1RyKCJIb3N0IENQVSwgUkFNLCBHUFUgYW5kIHRlbXBlcmF0dXJlcyIpCisgICAgICAgICAgICAg
ICAgb25DbGlja2VkOiB7CisgICAgICAgICAgICAgICAgICAgIHZhciBpdGVtID0gc3RhY2tWaWV3
LmN1cnJlbnRJdGVtCisgICAgICAgICAgICAgICAgICAgIHZhciBob3N0ID0gdG9vbEJhci5vbkFw
cFZpZXcgPyBpdGVtLmNyaW1zb25Ib3N0CisgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDog
KHRvb2xCYXIub25QY1ZpZXcgPyBpdGVtLmNvbXB1dGVyTW9kZWwuY3JpbXNvbkhvc3QoaXRlbS5j
dXJyZW50SW5kZXgpIDoge30pCisgICAgICAgICAgICAgICAgICAgIENyaW1zb25TdGF0dXMuc2Vs
ZWN0SG9zdChob3N0LmlkIHx8ICIiLCBob3N0LnVybCB8fCAiIikKKyAgICAgICAgICAgICAgICAg
ICAgY3JpbXNvblBhbmVsLmtpbmQgPSAiaG9zdCI7IGNyaW1zb25QYW5lbC5vcGVuKCkKKyAgICAg
ICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1Zp
ZXcuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAg
IH0KKwogICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAg
aWQ6IGRpc2NvcmRCdXR0b24KICAgICAgICAgICAgICAgICB2aXNpYmxlOiBmYWxzZSAvLyBUZW1w
b3JhcmlseSBkaXNhYmxlZCBmb3IgVmliZW1pcwpAQCAtNTY0LDcgKzY0OSw3IEBAIEFwcGxpY2F0
aW9uV2luZG93IHsKICAgICAgICAgICAgICAgICAvLyBhbiBpbnN0YWxsIGZhaWx1cmUgZmFsbHMg
YmFjayB0byB0aGUgcmVsZWFzZSBwYWdlIG9uIGl0cyBvd24uCiAgICAgICAgICAgICAgICAgVG9v
bFRpcC50ZXh0OiBBdXRvVXBkYXRlQ2hlY2tlci5pbnN0YWxsaW5nCiAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICA/IHFzVHIoIkRvd25sb2FkaW5nIHVwZGF0ZeKApiIpCi0gICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICA6IHFzVHIoIlVwZGF0ZSBhdmFpbGFibGUgZm9yIFZpYmVtaXM6
IFZlcnNpb24gJTEg4oCUIHRhcCB0byBpbnN0YWxsIikuYXJnKEF1dG9VcGRhdGVDaGVja2VyLmF2
YWlsYWJsZVZlcnNpb24pCisgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IHFzVHIoIlVw
ZGF0ZSBhdmFpbGFibGUgZm9yIEVjbGlwc2U6IFZlcnNpb24gJTEg4oCUIHRhcCB0byBpbnN0YWxs
IikuYXJnKEF1dG9VcGRhdGVDaGVja2VyLmF2YWlsYWJsZVZlcnNpb24pCiAKICAgICAgICAgICAg
ICAgICAvLyBTdHJpY3RseS1uZXdlciBidWlsZHMgb25seSAoYSBjaGFubmVsLXN3aXRjaCBkb3du
Z3JhZGUgb2ZmZXIKICAgICAgICAgICAgICAgICAvLyBsaXZlcyBpbiBTZXR0aW5ncywgbm90IG9u
IHRoZSB0b29sYmFyKS4KQEAgLTY0Niw2ICs3MzEsMjEgQEAgQXBwbGljYXRpb25XaW5kb3cgewog
ICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgIH0KIAorICAgICAgICAgICAgTmF2aWdhYmxl
VG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IGVjbGlwc2VDZW50ZXJCdXR0b24KKyAg
ICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1jb250cm9scy5zdmci
CisgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJFY2xpcHNlIGNvbnRyb2wg
Y2VudGVyIikKKyAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAg
ICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIkNvbnRyb2wgY2VudGVyIOKAoiBDdHJsK1No
aWZ0K0MiKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeworICAgICAgICAgICAgICAgICAg
ICB2YXIgaXRlbSA9IHN0YWNrVmlldy5jdXJyZW50SXRlbQorICAgICAgICAgICAgICAgICAgICBl
Y2xpcHNlQ2VudGVyLmhvc3QgPSB0b29sQmFyLm9uQXBwVmlldyA/IGl0ZW0uY3JpbXNvbkhvc3Qg
OiAodG9vbEJhci5vblBjVmlldyA/IGl0ZW0uY29tcHV0ZXJNb2RlbC5jcmltc29uSG9zdChpdGVt
LmN1cnJlbnRJbmRleCkgOiB7fSkKKyAgICAgICAgICAgICAgICAgICAgZWNsaXBzZUNlbnRlci5v
cGVuKCkKKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVz
c2VkOiBzdGFja1ZpZXcuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykK
KyAgICAgICAgICAgICAgICBTaG9ydGN1dCB7IHNlcXVlbmNlOiAiQ3RybCtTaGlmdCtDIjsgZW5h
YmxlZDogdG9vbEJhci5vblBjVmlldyB8fCB0b29sQmFyLm9uQXBwVmlldzsgb25BY3RpdmF0ZWQ6
IGVjbGlwc2VDZW50ZXJCdXR0b24uY2xpY2tlZCgpIH0KKyAgICAgICAgICAgIH0KKwogICAgICAg
ICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAgaWQ6IHNldHRpbmdz
QnV0dG9uCiAKQEAgLTY3Myw3ICs3NzMsNyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAKICAgICBF
cnJvck1lc3NhZ2VEaWFsb2cgewogICAgICAgICBpZDogbm9Id0RlY29kZXJEaWFsb2cKLSAgICAg
ICAgdGV4dDogcXNUcigiTm8gZnVuY3Rpb25pbmcgaGFyZHdhcmUgYWNjZWxlcmF0ZWQgdmlkZW8g
ZGVjb2RlciB3YXMgZGV0ZWN0ZWQgYnkgVmliZW1pcy4gIiArCisgICAgICAgIHRleHQ6IHFzVHIo
Ik5vIGZ1bmN0aW9uaW5nIGhhcmR3YXJlIGFjY2VsZXJhdGVkIHZpZGVvIGRlY29kZXIgd2FzIGRl
dGVjdGVkIGJ5IEVjbGlwc2UuICIgKwogICAgICAgICAgICAgICAgICAgICJZb3VyIHN0cmVhbWlu
ZyBwZXJmb3JtYW5jZSBtYXkgYmUgc2V2ZXJlbHkgZGVncmFkZWQgaW4gdGhpcyBjb25maWd1cmF0
aW9uLiIpCiAgICAgICAgIGhlbHBUZXh0OiBxc1RyKCJDbGljayB0aGUgSGVscCBidXR0b24gZm9y
IG1vcmUgaW5mb3JtYXRpb24gb24gc29sdmluZyB0aGlzIHByb2JsZW0uIikKICAgICAgICAgaGVs
cFVybDogImh0dHBzOi8vZ2l0aHViLmNvbS9uYXZ5YXMzMjEvdmliZW1pcyIKQEAgLTY5MCw3ICs3
OTAsNyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgTmF2aWdhYmxlTWVzc2FnZURpYWxvZyB7
CiAgICAgICAgIGlkOiB3b3c2NERpYWxvZwogICAgICAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxv
Zy5PayB8IERpYWxvZy5DYW5jZWwKLSAgICAgICAgdGV4dDogcXNUcigiVGhpcyB2ZXJzaW9uIG9m
IFZpYmVtaXMgaXNuJ3Qgb3B0aW1pemVkIGZvciB5b3VyIFBDLiBQbGVhc2UgZG93bmxvYWQgdGhl
ICclMScgdmVyc2lvbiBvZiBWaWJlbWlzIGZvciB0aGUgYmVzdCBzdHJlYW1pbmcgcGVyZm9ybWFu
Y2UuIikuYXJnKFN5c3RlbVByb3BlcnRpZXMuZnJpZW5kbHlOYXRpdmVBcmNoTmFtZSkKKyAgICAg
ICAgdGV4dDogcXNUcigiVGhpcyB2ZXJzaW9uIG9mIEVjbGlwc2UgaXNuJ3Qgb3B0aW1pemVkIGZv
ciB5b3VyIFBDLiBQbGVhc2UgZG93bmxvYWQgdGhlICclMScgdmVyc2lvbiBvZiBFY2xpcHNlIGZv
ciB0aGUgYmVzdCBzdHJlYW1pbmcgcGVyZm9ybWFuY2UuIikuYXJnKFN5c3RlbVByb3BlcnRpZXMu
ZnJpZW5kbHlOYXRpdmVBcmNoTmFtZSkKICAgICAgICAgb25BY2NlcHRlZDogewogICAgICAgICAg
ICAgU3lzdGVtUHJvcGVydGllcy5vcGVuVXJsKCJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIx
L3ZpYmVtaXMvcmVsZWFzZXMiKTsKICAgICAgICAgfQpAQCAtNjk5LDcgKzc5OSw3IEBAIEFwcGxp
Y2F0aW9uV2luZG93IHsKICAgICBFcnJvck1lc3NhZ2VEaWFsb2cgewogICAgICAgICBpZDogdW5t
YXBwZWRHYW1lcGFkRGlhbG9nCiAgICAgICAgIHByb3BlcnR5IHN0cmluZyB1bm1hcHBlZEdhbWVw
YWRzIDogIiIKLSAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBkZXRlY3RlZCBnYW1lcGFkcyB3
aXRob3V0IGEgbWFwcGluZzoiKSArICJcbiIgKyB1bm1hcHBlZEdhbWVwYWRzCisgICAgICAgIHRl
eHQ6IHFzVHIoIkVjbGlwc2UgZGV0ZWN0ZWQgZ2FtZXBhZHMgd2l0aG91dCBhIG1hcHBpbmc6Iikg
KyAiXG4iICsgdW5tYXBwZWRHYW1lcGFkcwogICAgICAgICBoZWxwVGV4dFNlcGFyYXRvcjogIlxu
XG4iCiAgICAgICAgIGhlbHBUZXh0OiBxc1RyKCJDbGljayB0aGUgSGVscCBidXR0b24gZm9yIGlu
Zm9ybWF0aW9uIG9uIGhvdyB0byBtYXAgeW91ciBnYW1lcGFkcy4iKQogICAgICAgICBoZWxwVXJs
OiAiaHR0cHM6Ly9naXRodWIuY29tL25hdnlhczMyMS92aWJlbWlzIgpkaWZmIC0tZ2l0IGEvYXBw
L21haW4uY3BwIGIvYXBwL21haW4uY3BwCmluZGV4IDI5MjIyNzcuLjNlYzk0ZGIgMTAwNjQ0Ci0t
LSBhL2FwcC9tYWluLmNwcAorKysgYi9hcHAvbWFpbi5jcHAKQEAgLTg2OSw2ICs4NjksNyBAQCBp
bnQgbWFpbihpbnQgYXJnYywgY2hhciAqYXJndltdKQogICAgIH0NCiANCiAgICAgUUd1aUFwcGxp
Y2F0aW9uIGFwcChhcmdjLCBhcmd2KTsNCisgICAgUUd1aUFwcGxpY2F0aW9uOjpzZXRBcHBsaWNh
dGlvbkRpc3BsYXlOYW1lKCJFY2xpcHNlIik7CiANCiAgICAgLy8gVmliZW1pczogdGhlIFF0IFF1
aWNrIENvbnRyb2xzIE1hdGVyaWFsIHN0eWxlIHJlbmRlcnMgYnV0dG9uIHRleHQgaW4gQUxMIENB
UFMgYnkgZGVmYXVsdA0KICAgICAvLyAoZS5nLiB0aGUgYml0cmF0ZSAiVVNFIERFRkFVTFQgKDMw
IE1CUFMpIiBidXR0b24pLCB3aGljaCBsb29rcyBvZmYuIEZvcmNlIG1peGVkIGNhc2UgZm9yIHRo
ZQ0KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9jcmltc29uZ3JhcGhzLmggYi9hcHAvbW9v
bmxpZ2h0b3MvY3JpbXNvbmdyYXBocy5oCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAw
MDAuLmNkY2MzYTAKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbmdy
YXBocy5oCkBAIC0wLDAgKzEsNjMgQEAKKyNwcmFnbWEgb25jZQorI2luY2x1ZGUgPFFNYXA+Cisj
aW5jbHVkZSA8UVZlY3Rvcj4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRUmVn
dWxhckV4cHJlc3Npb24+CisjaW5jbHVkZSA8UVBhaW50ZXI+CisjaW5jbHVkZSA8UVBhaW50ZXJQ
YXRoPgorI2luY2x1ZGUgPFFGb250PgorI2luY2x1ZGUgPFF0TWF0aD4KKyNpbmNsdWRlIDxsaW1p
dHM+CisjaW5jbHVkZSAib3ZlcmxheXN0eWxlLmgiCituYW1lc3BhY2UgQ3JpbXNvbkdyYXBocyB7
Cit1c2luZyBIaXN0b3J5PVFNYXA8UVN0cmluZyxRVmVjdG9yPGRvdWJsZT4+OworaW5saW5lIGRv
dWJsZSBtaXNzaW5nKCkgeyByZXR1cm4gc3RkOjpudW1lcmljX2xpbWl0czxkb3VibGU+OjpxdWll
dF9OYU4oKTsgfQoraW5saW5lIFFNYXA8UVN0cmluZyxkb3VibGU+IHZhbHVlcyhjb25zdCBRU3Ry
aW5nJiB0ZXh0LGJvb2wgbG9jYWwsY29uc3QgUVZhcmlhbnRNYXAmIGhhcmR3YXJlKSB7CisgICAg
UU1hcDxRU3RyaW5nLGRvdWJsZT4gcmVzdWx0OworICAgIGF1dG8gdGFrZT1bJl0oY29uc3QgUVN0
cmluZyYga2V5LGNvbnN0IFFTdHJpbmcmIHNvdXJjZSkgeworICAgICAgICBib29sIG9rPWZhbHNl
OworICAgICAgICBjb25zdCBhdXRvIHZhbHVlPWhhcmR3YXJlLnZhbHVlKHNvdXJjZSk7CisgICAg
ICAgIGRvdWJsZSBudW1iZXI9dmFsdWUudG9Eb3VibGUoJm9rKTsKKyAgICAgICAgcmVzdWx0W2tl
eV09IXZhbHVlLmlzTnVsbCgpJiZvayYmcUlzRmluaXRlKG51bWJlcikmJm51bWJlcj49MD9udW1i
ZXI6bWlzc2luZygpOworICAgIH07CisgICAgdGFrZSgiTG9jYWwgQ1BVIiwiY3B1UGVyY2VudCIp
O3Rha2UoIkxvY2FsIFJBTSIsIm1lbW9yeVVzZWRHaUIiKTsKKyAgICBpZihsb2NhbCkge3Rha2Uo
IlRlbXBlcmF0dXJlIiwidGVtcGVyYXR1cmVDIik7dGFrZSgiRG93bmxvYWQiLCJyZWNlaXZlTWlC
Iik7fQorICAgIGVsc2UgeworICAgICAgICBhdXRvIGZwcz1RUmVndWxhckV4cHJlc3Npb24oIlJl
bmRlcmluZyBmcmFtZSByYXRlOiAoWzAtOV0rKD86XFwuWzAtOV0rKT8pIEZQUyIpLm1hdGNoKHRl
eHQpOworICAgICAgICBpZighZnBzLmhhc01hdGNoKCkpIGZwcz1RUmVndWxhckV4cHJlc3Npb24o
Il4oWzAtOV0rKD86XFwuWzAtOV0rKT8pIGZwcyIsUVJlZ3VsYXJFeHByZXNzaW9uOjpDYXNlSW5z
ZW5zaXRpdmVPcHRpb24pLm1hdGNoKHRleHQpOworICAgICAgICByZXN1bHRbIkZQUyJdPWZwcy5o
YXNNYXRjaCgpP2Zwcy5jYXB0dXJlZCgxKS50b0RvdWJsZSgpOm1pc3NpbmcoKTsKKyAgICAgICAg
YXV0byBsYXRlbmN5PVFSZWd1bGFyRXhwcmVzc2lvbigiQXZlcmFnZSBuZXR3b3JrIGxhdGVuY3k6
IChbMC05XSsoPzpcXC5bMC05XSspPykiKS5tYXRjaCh0ZXh0KTsKKyAgICAgICAgaWYoIWxhdGVu
Y3kuaGFzTWF0Y2goKSkgbGF0ZW5jeT1RUmVndWxhckV4cHJlc3Npb24oIlxcYm5ldCAoWzAtOV0r
KD86XFwuWzAtOV0rKT8pIG1zIikubWF0Y2godGV4dCk7CisgICAgICAgIHJlc3VsdFsiTmV0d29y
ayBsYXRlbmN5Il09bGF0ZW5jeS5oYXNNYXRjaCgpP2xhdGVuY3kuY2FwdHVyZWQoMSkudG9Eb3Vi
bGUoKTptaXNzaW5nKCk7CisgICAgfQorICAgIHJldHVybiByZXN1bHQ7Cit9CitpbmxpbmUgdm9p
ZCBwdXNoKEhpc3RvcnkmIGhpc3RvcnksY29uc3QgUU1hcDxRU3RyaW5nLGRvdWJsZT4mIHZhbHVl
cykgeworICAgIGZvcihhdXRvIGk9dmFsdWVzLmNiZWdpbigpO2khPXZhbHVlcy5jZW5kKCk7Kytp
KSB7YXV0byYgc2VyaWVzPWhpc3RvcnlbaS5rZXkoKV07c2VyaWVzLmFwcGVuZChxSXNGaW5pdGUo
aS52YWx1ZSgpKSYmaS52YWx1ZSgpPj0wP2kudmFsdWUoKTptaXNzaW5nKCkpO3doaWxlKHNlcmll
cy5zaXplKCk+NjApc2VyaWVzLnJlbW92ZUZpcnN0KCk7fQorfQoraW5saW5lIFFTdHJpbmdMaXN0
IGtleXMoYm9vbCBsb2NhbCkge3JldHVybiBsb2NhbD9RU3RyaW5nTGlzdHsiTG9jYWwgQ1BVIiwi
TG9jYWwgUkFNIiwiVGVtcGVyYXR1cmUiLCJEb3dubG9hZCJ9OlFTdHJpbmdMaXN0eyJGUFMiLCJO
ZXR3b3JrIGxhdGVuY3kiLCJMb2NhbCBDUFUiLCJMb2NhbCBSQU0ifTt9CitpbmxpbmUgdm9pZCBw
YWludChRSW1hZ2UmIGltYWdlLGludCB0b3AsaW50IGZvbnRTaXplLGludCBhY2NlbnRJbmRleCxj
b25zdCBIaXN0b3J5JiBoaXN0b3J5LGJvb2wgbG9jYWwpIHsKKyAgICBRUGFpbnRlciBwKCZpbWFn
ZSk7cC5zZXRSZW5kZXJIaW50KFFQYWludGVyOjpBbnRpYWxpYXNpbmcpO1FGb250IGZvbnQoIkRl
amFWdSBTYW5zIik7Zm9udC5zZXRQaXhlbFNpemUoZm9udFNpemUpO3Auc2V0Rm9udChmb250KTsK
KyAgICBjb25zdCBpbnQgcm93SGVpZ2h0PWZvbnRTaXplKzIyO2ludCByb3c9MDsKKyAgICBmb3Io
Y29uc3QgYXV0byYga2V5OmtleXMobG9jYWwpKSB7CisgICAgICAgIGNvbnN0IGF1dG8gc2VyaWVz
PWhpc3RvcnkudmFsdWUoa2V5KTtkb3VibGUgY3VycmVudD1zZXJpZXMuaXNFbXB0eSgpP21pc3Np
bmcoKTpzZXJpZXMubGFzdCgpOworICAgICAgICBRU3RyaW5nIHVuaXQ9a2V5PT0iTG9jYWwgQ1BV
Ij8iJSI6a2V5PT0iTG9jYWwgUkFNIj8iIEdpQiI6a2V5PT0iVGVtcGVyYXR1cmUiPyIgwrBDIjpr
ZXk9PSJEb3dubG9hZCI/IiBNaUIvcyI6a2V5PT0iTmV0d29yayBsYXRlbmN5Ij8iIG1zIjoiIjsK
KyAgICAgICAgUVN0cmluZyB2YWx1ZT1xSXNGaW5pdGUoY3VycmVudCk/UVN0cmluZzo6bnVtYmVy
KGN1cnJlbnQsJ2YnLGtleT09IkZQUyI/MDoxKSt1bml0OlFTdHJpbmcoIlVuYXZhaWxhYmxlIik7
CisgICAgICAgIGNvbnN0IGludCB5PXRvcCtyb3crKypyb3dIZWlnaHQ7CisgICAgICAgIHAuc2V0
UGVuKFFDb2xvcigiIzk4QTFBQiIpKTtwLmRyYXdUZXh0KFFSZWN0KDE2LHksaW1hZ2Uud2lkdGgo
KS0zMixyb3dIZWlnaHQpLFF0OjpBbGlnblZDZW50ZXIsa2V5KTsKKyAgICAgICAgY29uc3QgaW50
IGdyYXBoV2lkdGg9OTY7CisgICAgICAgIHAuc2V0UGVuKFFDb2xvcigiI0VDRUVGMSIpKTtwLmRy
YXdUZXh0KFFSZWN0KDE4NSx5LGltYWdlLndpZHRoKCktZ3JhcGhXaWR0aC0yMTUscm93SGVpZ2h0
KSxRdDo6QWxpZ25SaWdodHxRdDo6QWxpZ25WQ2VudGVyLHZhbHVlKTsKKyAgICAgICAgUVJlY3RG
IGJvdW5kcyhpbWFnZS53aWR0aCgpLWdyYXBoV2lkdGgtMTQseSs3LGdyYXBoV2lkdGgscm93SGVp
Z2h0LTE0KTsKKyAgICAgICAgZG91YmxlIGhpZ2g9a2V5PT0iTG9jYWwgQ1BVIj8xMDA6MTsKKyAg
ICAgICAgaWYoa2V5IT0iTG9jYWwgQ1BVIilmb3IoZG91YmxlIG46c2VyaWVzKWlmKHFJc0Zpbml0
ZShuKSloaWdoPXFNYXgoaGlnaCxuKjEuMTUpOworICAgICAgICBRUGFpbnRlclBhdGggcGF0aDti
b29sIHN0YXJ0ZWQ9ZmFsc2U7CisgICAgICAgIGZvcihpbnQgaT0wO2k8c2VyaWVzLnNpemUoKTtp
KyspIHtkb3VibGUgdj1zZXJpZXNbaV07aWYoIXFJc0Zpbml0ZSh2KSl7c3RhcnRlZD1mYWxzZTtj
b250aW51ZTt9CisgICAgICAgICAgICBRUG9pbnRGIHBvaW50KGJvdW5kcy5sZWZ0KCkrYm91bmRz
LndpZHRoKCkqKDYwLXNlcmllcy5zaXplKCkraSkvNTkuMCxib3VuZHMuYm90dG9tKCktYm91bmRz
LmhlaWdodCgpKnFCb3VuZCgwLjAsdi9oaWdoLDEuMCkpOworICAgICAgICAgICAgaWYoIXN0YXJ0
ZWQpcGF0aC5tb3ZlVG8ocG9pbnQpO2Vsc2UgcGF0aC5saW5lVG8ocG9pbnQpO3N0YXJ0ZWQ9dHJ1
ZTsKKyAgICAgICAgfQorICAgICAgICBwLnNldFBlbihRUGVuKEVjbGlwc2VPdmVybGF5U3R5bGU6
OmFjY2VudChhY2NlbnRJbmRleCksMS41KSk7cC5kcmF3UGF0aChwYXRoKTsKKyAgICAgICAgaWYo
cUlzRmluaXRlKGN1cnJlbnQpKSB7cC5zZXRCcnVzaChFY2xpcHNlT3ZlcmxheVN0eWxlOjphY2Nl
bnQoYWNjZW50SW5kZXgpKTtwLmRyYXdFbGxpcHNlKFFQb2ludEYoYm91bmRzLnJpZ2h0KCksYm91
bmRzLmJvdHRvbSgpLWJvdW5kcy5oZWlnaHQoKSpxQm91bmQoMC4wLGN1cnJlbnQvaGlnaCwxLjAp
KSwxLjUsMS41KTt9CisgICAgICAgIHAuc2V0UGVuKFFDb2xvcigyNTUsMjU1LDI1NSwxNCkpO3Au
ZHJhd0xpbmUoMTYseStyb3dIZWlnaHQtMSxpbWFnZS53aWR0aCgpLTE2LHkrcm93SGVpZ2h0LTEp
OworICAgIH0KK30KK30KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVz
LmNwcCBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcApuZXcgZmlsZSBtb2RlIDEw
MDY0NAppbmRleCAwMDAwMDAwLi5kYWZjYTJlCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25s
aWdodG9zL2NyaW1zb25zdGF0dXMuY3BwCkBAIC0wLDAgKzEsMjIyIEBACisjaW5jbHVkZSAiY3Jp
bXNvbnN0YXR1cy5oIgorI2luY2x1ZGUgPFFEYXRlVGltZT4KKyNpbmNsdWRlIDxRRGlyPgorI2lu
Y2x1ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFKc29uRG9jdW1lbnQ+CisjaW5jbHVkZSA8UUpzb25P
YmplY3Q+CisjaW5jbHVkZSA8UU5ldHdvcmtJbnRlcmZhY2U+CisjaW5jbHVkZSA8UU5ldHdvcmtS
ZXF1ZXN0PgorI2luY2x1ZGUgPFFTYXZlRmlsZT4KKyNpbmNsdWRlIDxRU3NsQ2VydGlmaWNhdGU+
CisjaW5jbHVkZSA8UVNzbEVycm9yPgorI2luY2x1ZGUgPFFTdGFuZGFyZFBhdGhzPgorI2luY2x1
ZGUgPFFDcnlwdG9ncmFwaGljSGFzaD4KKyNpbmNsdWRlIDxRVXJsPgorI2luY2x1ZGUgPGNtYXRo
PgorI2luY2x1ZGUgPFFRbWxFbmdpbmU+CisjaW5jbHVkZSA8UUNvcmVBcHBsaWNhdGlvbj4KKyNp
bmNsdWRlIDxtZW1vcnk+CisjaW5jbHVkZSA8UVJlZ3VsYXJFeHByZXNzaW9uPgorI2luY2x1ZGUg
PFFGaWxlSW5mbz4KKyNpbmNsdWRlIDxRU3NsQ29uZmlndXJhdGlvbj4KKworbmFtZXNwYWNlIHsK
K1FTdHJpbmcgcmVhZChjb25zdCBRU3RyaW5nJiBwYXRoKSB7CisgICAgUUZpbGUgZihwYXRoKTsg
cmV0dXJuIGYub3BlbihRSU9EZXZpY2U6OlJlYWRPbmx5KSA/IFFTdHJpbmc6OmZyb21VdGY4KGYu
cmVhZEFsbCgpKS50cmltbWVkKCkgOiBRU3RyaW5nKCk7Cit9Citjb25zdCBhdXRvIHVzZXJPbmx5
ID0gUUZpbGVEZXZpY2U6OlJlYWRPd25lciB8IFFGaWxlRGV2aWNlOjpXcml0ZU93bmVyOworfQor
Q3JpbXNvblN0YXR1czo6Q3JpbXNvblN0YXR1cyhRT2JqZWN0KiBwYXJlbnQpIDogUU9iamVjdChw
YXJlbnQpIHsKKyAgICBjb25uZWN0KCZtX2xvY2FsVGltZXIsICZRVGltZXI6OnRpbWVvdXQsIHRo
aXMsICZDcmltc29uU3RhdHVzOjpyZWZyZXNoTG9jYWwpOworICAgIGNvbm5lY3QoJm1fc3RhdHNU
aW1lciwgJlFUaW1lcjo6dGltZW91dCwgdGhpcywgJkNyaW1zb25TdGF0dXM6OnJlZnJlc2gpOwor
ICAgIGNvbm5lY3QoJm1fd2lmaSwgJlFQcm9jZXNzOjpmaW5pc2hlZCwgdGhpcywgW3RoaXNdKGlu
dCBleGl0LCBRUHJvY2Vzczo6RXhpdFN0YXR1cykgeworICAgICAgICBpZiAoZXhpdCA9PSAwKSB7
CisgICAgICAgICAgICBjb25zdCBhdXRvIGxpbmVzID0gUVN0cmluZzo6ZnJvbVV0ZjgobV93aWZp
LnJlYWRBbGxTdGFuZGFyZE91dHB1dCgpKS5zcGxpdCgnXG4nKTsKKyAgICAgICAgICAgIGZvciAo
Y29uc3QgYXV0byYgbGluZSA6IGxpbmVzKSB7CisgICAgICAgICAgICAgICAgaWYgKCFsaW5lLnN0
YXJ0c1dpdGgoInllczoiKSkgY29udGludWU7CisgICAgICAgICAgICAgICAgaW50IHNlcGFyYXRv
ciA9IGxpbmUuaW5kZXhPZignOicsIDQpOyBib29sIG9rID0gZmFsc2U7CisgICAgICAgICAgICAg
ICAgaW50IHNpZ25hbCA9IGxpbmUubWlkKDQsIHNlcGFyYXRvciAtIDQpLnRvSW50KCZvayk7Cisg
ICAgICAgICAgICAgICAgaWYgKG9rICYmIHNpZ25hbCA+PSAwICYmIHNpZ25hbCA8PSAxMDApIG1f
bG9jYWxbIndpZmlTaWduYWwiXSA9IHNpZ25hbDsKKyAgICAgICAgICAgICAgICBpZiAoc2VwYXJh
dG9yID49IDApIG1fbG9jYWxbIm5ldHdvcmsiXSA9IHRyKCJXaS1GaTogJTEiKS5hcmcobGluZS5t
aWQoc2VwYXJhdG9yICsgMSkpOworICAgICAgICAgICAgICAgIGJyZWFrOworICAgICAgICAgICAg
fQorICAgICAgICAgICAgZW1pdCBsb2NhbENoYW5nZWQoKTsKKyAgICAgICAgfQorICAgIH0pOwor
ICAgIG1fbG9jYWxUaW1lci5zdGFydCgxMDAwMCk7IG1fc3RhdHNUaW1lci5zZXRJbnRlcnZhbCgy
MDAwKTsgcmVmcmVzaExvY2FsKCk7Cit9CitDcmltc29uU3RhdHVzOjp+Q3JpbXNvblN0YXR1cygp
IHsKKyAgICBtX3N0YXRzVGltZXIuc3RvcCgpOyBtX2xvY2FsVGltZXIuc3RvcCgpOyBjYW5jZWwo
KTsKKyAgICBpZiAobV93aWZpLnN0YXRlKCkgIT0gUVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIHsgbV93
aWZpLmtpbGwoKTsgbV93aWZpLndhaXRGb3JGaW5pc2hlZCg1MDApOyB9Cit9CitRU3RyaW5nIENy
aW1zb25TdGF0dXM6OmNvbmZpZ0ZpbGUoKSBjb25zdCB7CisgICAgcmV0dXJuIFFTdGFuZGFyZFBh
dGhzOjp3cml0YWJsZUxvY2F0aW9uKFFTdGFuZGFyZFBhdGhzOjpBcHBDb25maWdMb2NhdGlvbikg
KyAiL2NyaW1zb24taG9zdHMuanNvbiI7Cit9CitRU3RyaW5nIENyaW1zb25TdGF0dXM6Om5vcm1h
bGl6ZWRQaW4oUVN0cmluZyBwaW4pIHsKKyAgICBwaW4ucmVtb3ZlKCc6Jyk7IHBpbi5yZW1vdmUo
JyAnKTsgcmV0dXJuIHBpbi50b0xvd2VyKCk7Cit9Citib29sIENyaW1zb25TdGF0dXM6OnZhbGlk
RW5kcG9pbnQoY29uc3QgUVN0cmluZyYgdmFsdWUpIHsKKyAgICBRVXJsIHUodmFsdWUsIFFVcmw6
OlN0cmljdE1vZGUpOworICAgIHJldHVybiB1LmlzVmFsaWQoKSAmJiB1LnNjaGVtZSgpID09ICJo
dHRwcyIgJiYgIXUuaG9zdCgpLmlzRW1wdHkoKSAmJgorICAgICAgICB1LnVzZXJJbmZvKCkuaXNF
bXB0eSgpICYmIHUucXVlcnkoKS5pc0VtcHR5KCkgJiYgdS5mcmFnbWVudCgpLmlzRW1wdHkoKSAm
JgorICAgICAgICAodS5wYXRoKCkuaXNFbXB0eSgpIHx8IHUucGF0aCgpID09ICIvIikgJiYgdS5w
b3J0KDQ3OTkwKSA+IDA7Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OmNhbmNlbCgpIHsKKyAgICBp
ZiAobV9yZXBseSkgeyBkaXNjb25uZWN0KG1fcmVwbHksIG51bGxwdHIsIHRoaXMsIG51bGxwdHIp
OyBtX3JlcGx5LT5hYm9ydCgpOyBtX3JlcGx5LT5kZWxldGVMYXRlcigpOyBtX3JlcGx5ID0gbnVs
bHB0cjsgfQorfQordm9pZCBDcmltc29uU3RhdHVzOjpzZWxlY3RIb3N0KFFTdHJpbmcgaWQsIFFT
dHJpbmcgc3VnZ2VzdGVkVXJsKSB7CisgICAgaWYgKGlkID09IG1faG9zdCkgcmV0dXJuOworICAg
IGNhbmNlbCgpOyBtX25ldHdvcmsuY2xlYXJDb25uZWN0aW9uQ2FjaGUoKTsgbV9ob3N0ID0gaWQ7
IG1fdG9rZW4uY2xlYXIoKTsgbV9waW4uY2xlYXIoKTsKKyAgICBtX2VuZHBvaW50ID0gdmFsaWRF
bmRwb2ludChzdWdnZXN0ZWRVcmwpID8gc3VnZ2VzdGVkVXJsIDogUVN0cmluZygpOworICAgIFFG
aWxlIGYoY29uZmlnRmlsZSgpKTsKKyAgICBpZiAoZi5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkp
KSB7CisgICAgICAgIGF1dG8gYyA9IFFKc29uRG9jdW1lbnQ6OmZyb21Kc29uKGYucmVhZEFsbCgp
KS5vYmplY3QoKS52YWx1ZShpZCkudG9PYmplY3QoKTsKKyAgICAgICAgaWYgKHZhbGlkRW5kcG9p
bnQoYy52YWx1ZSgidXJsIikudG9TdHJpbmcoKSkpIHsKKyAgICAgICAgICAgIG1fZW5kcG9pbnQg
PSBjLnZhbHVlKCJ1cmwiKS50b1N0cmluZygpOyBtX3Rva2VuID0gYy52YWx1ZSgidG9rZW4iKS50
b1N0cmluZygpOyBtX3BpbiA9IGMudmFsdWUoInBpbiIpLnRvU3RyaW5nKCk7CisgICAgICAgIH0K
KyAgICB9CisgICAgbV9zdGF0cy5jbGVhcigpOyBtX3N0YXR1cyA9IGlkLmlzRW1wdHkoKSA/IHRy
KCJDaG9vc2UgYSBob3N0IHRvIHZpZXcgaGFyZHdhcmUgc3RhdHMiKSA6IHRyKCJDb25maWd1cmUg
YSBWaWJlcG9sbG8gcmVhZC1vbmx5IHN0YXRzIHRva2VuIik7CisgICAgZW1pdCBjb25maWdDaGFu
Z2VkKCk7IGVtaXQgc3RhdHNDaGFuZ2VkKCk7IGlmIChtX3Zpc2libGUpIHJlZnJlc2goKTsKK30K
K2Jvb2wgQ3JpbXNvblN0YXR1czo6Y29uZmlndXJlKFFTdHJpbmcgdXJsLCBRU3RyaW5nIHRva2Vu
LCBRU3RyaW5nIHBpbikgeworICAgIHBpbiA9IG5vcm1hbGl6ZWRQaW4ocGluKTsKKyAgICBpZiAo
bV9ob3N0LmlzRW1wdHkoKSB8fCAhdmFsaWRFbmRwb2ludCh1cmwpIHx8ICghcGluLmlzRW1wdHko
KSAmJgorICAgICAgICAocGluLnNpemUoKSAhPSA2NCB8fCBwaW4uY29udGFpbnMoUVJlZ3VsYXJF
eHByZXNzaW9uKCJbXjAtOWEtZl0iKSkpKSkgeworICAgICAgICBmYWlsKHRyKCJVc2UgYW4gSFRU
UFMgaG9zdCBVUkwgYW5kIGFuIG9wdGlvbmFsIDY0LWRpZ2l0IFNIQS0yNTYgY2VydGlmaWNhdGUg
ZmluZ2VycHJpbnQiKSk7IHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgLy8gQSBibGFuayB0b2tl
biBrZWVwcyB0aGUgb2xkIHRva2VuIG9ubHkgZm9yIHRoZSBzYW1lIGVuZHBvaW50LgorICAgIGlm
ICh0b2tlbi5pc0VtcHR5KCkgJiYgUVVybCh1cmwpID09IFFVcmwobV9lbmRwb2ludCkpIHRva2Vu
ID0gbV90b2tlbjsKKyAgICBpZiAodG9rZW4uaXNFbXB0eSgpIHx8IHRva2VuLmNvbnRhaW5zKCdc
cicpIHx8IHRva2VuLmNvbnRhaW5zKCdcbicpIHx8IHRva2VuLnNpemUoKSA+IDQwOTYpIHsKKyAg
ICAgICAgZmFpbCh0cigiQSByZWFkLW9ubHkgVmliZXBvbGxvIEFQSSB0b2tlbiBpcyByZXF1aXJl
ZCIpKTsgcmV0dXJuIGZhbHNlOworICAgIH0KKyAgICBRRmlsZSBmKGNvbmZpZ0ZpbGUoKSk7IFFK
c29uT2JqZWN0IGFsbDsKKyAgICBpZiAoZi5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpKSBhbGwg
PSBRSnNvbkRvY3VtZW50Ojpmcm9tSnNvbihmLnJlYWRBbGwoKSkub2JqZWN0KCk7CisgICAgYWxs
W21faG9zdF0gPSBRSnNvbk9iamVjdHt7InVybCIsIHVybH0sIHsidG9rZW4iLCB0b2tlbn0sIHsi
cGluIiwgcGlufX07CisgICAgUURpcigpLm1rcGF0aChRRmlsZUluZm8oY29uZmlnRmlsZSgpKS5h
YnNvbHV0ZVBhdGgoKSk7CisgICAgUVNhdmVGaWxlIG91dChjb25maWdGaWxlKCkpOworICAgIGlm
ICghb3V0Lm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpIHx8ICFvdXQuc2V0UGVybWlzc2lvbnMo
dXNlck9ubHkpIHx8CisgICAgICAgIG91dC53cml0ZShRSnNvbkRvY3VtZW50KGFsbCkudG9Kc29u
KCkpIDwgMCB8fCAhb3V0LmNvbW1pdCgpKSB7CisgICAgICAgIGZhaWwodHIoIkNvdWxkIG5vdCBz
YXZlIGhvc3QgYWNjZXNzIHNldHRpbmdzIikpOyByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIGNh
bmNlbCgpOyBtX25ldHdvcmsuY2xlYXJDb25uZWN0aW9uQ2FjaGUoKTsgbV9lbmRwb2ludCA9IHVy
bDsgbV90b2tlbiA9IHRva2VuOyBtX3BpbiA9IHBpbjsKKyAgICBtX3N0YXRzVGltZXIuc2V0SW50
ZXJ2YWwoMjAwMCk7CisgICAgbV9zdGF0cy5jbGVhcigpOyBtX3N0YXR1cyA9IHRyKCJDb25uZWN0
aW5nIHRvIGhvc3Qgc3RhdHPigKYiKTsKKyAgICBlbWl0IGNvbmZpZ0NoYW5nZWQoKTsgZW1pdCBz
dGF0c0NoYW5nZWQoKTsgcmVmcmVzaCgpOyByZXR1cm4gdHJ1ZTsKK30KK3ZvaWQgQ3JpbXNvblN0
YXR1czo6c2V0VmlzaWJsZShib29sIHZpc2libGUpIHsKKyAgICBtX3Zpc2libGUgPSB2aXNpYmxl
OworICAgIGlmICh2aXNpYmxlKSB7IHJlZnJlc2hMb2NhbCgpOyBtX3N0YXRzVGltZXIuc3RhcnQo
KTsgcmVmcmVzaCgpOyB9CisgICAgZWxzZSB7IG1fc3RhdHNUaW1lci5zdG9wKCk7IGNhbmNlbCgp
OyB9Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OmZhaWwoUVN0cmluZyBtZXNzYWdlKSB7CisgICAg
bV9zdGF0cy5jbGVhcigpOyBtX3N0YXR1cyA9IG1lc3NhZ2U7CisgICAgbV9zdGF0c1RpbWVyLnNl
dEludGVydmFsKHFNaW4oMzAwMDAsIHFNYXgoNDAwMCwgbV9zdGF0c1RpbWVyLmludGVydmFsKCkg
KiAyKSkpOworICAgIGVtaXQgc3RhdHNDaGFuZ2VkKCk7Cit9CitRVmFyaWFudE1hcCBDcmltc29u
U3RhdHVzOjpwYXJzZVN0YXRzKGNvbnN0IFFCeXRlQXJyYXkmIGJ5dGVzLCBRU3RyaW5nKiBlcnJv
cikgeworICAgIGlmIChieXRlcy5zaXplKCkgPiA2NTUzNikgeyAqZXJyb3IgPSAiT3ZlcnNpemVk
IGhvc3Qgc3RhdHMgcmVzcG9uc2UiOyByZXR1cm4ge307IH0KKyAgICBRSnNvblBhcnNlRXJyb3Ig
ZTsgYXV0byBkb2MgPSBRSnNvbkRvY3VtZW50Ojpmcm9tSnNvbihieXRlcywgJmUpOworICAgIGlm
IChlLmVycm9yICE9IFFKc29uUGFyc2VFcnJvcjo6Tm9FcnJvciB8fCAhZG9jLmlzT2JqZWN0KCkp
IHsgKmVycm9yID0gIkludmFsaWQgaG9zdCBzdGF0cyByZXNwb25zZSI7IHJldHVybiB7fTsgfQor
ICAgIGF1dG8gb2JqID0gZG9jLm9iamVjdCgpOyBRVmFyaWFudE1hcCByZXN1bHQ7CisgICAgY29u
c3QgUVN0cmluZ0xpc3Qga2V5cyA9IHsiY3B1X3BlcmNlbnQiLCJjcHVfdGVtcF9jIiwicmFtX3Vz
ZWRfYnl0ZXMiLCJyYW1fdG90YWxfYnl0ZXMiLCJyYW1fcGVyY2VudCIsCisgICAgICAgICJncHVf
cGVyY2VudCIsImdwdV9lbmNvZGVyX3BlcmNlbnQiLCJncHVfdGVtcF9jIiwidnJhbV91c2VkX2J5
dGVzIiwidnJhbV90b3RhbF9ieXRlcyIsInZyYW1fcGVyY2VudCIsIm5ldF9yeF9icHMiLCJuZXRf
dHhfYnBzIn07CisgICAgYm9vbCByZWNvZ25pemVkID0gZmFsc2U7CisgICAgZm9yIChjb25zdCBh
dXRvJiBrZXkgOiBrZXlzKSB7CisgICAgICAgIGF1dG8gdiA9IG9iai52YWx1ZShrZXkpOyByZWNv
Z25pemVkIHw9IG9iai5jb250YWlucyhrZXkpOworICAgICAgICBkb3VibGUgbiA9IHYudG9Eb3Vi
bGUoLTEpOworICAgICAgICBpZiAoIXYuaXNEb3VibGUoKSB8fCAhc3RkOjppc2Zpbml0ZShuKSB8
fCBuIDwgMCB8fCAoa2V5LmVuZHNXaXRoKCJwZXJjZW50IikgJiYgbiA+IDEwMCkpIGNvbnRpbnVl
OworICAgICAgICByZXN1bHRba2V5XSA9IG47CisgICAgfQorICAgIGZvciAoY29uc3QgYXV0byYg
cHJlZml4IDoge1FTdHJpbmcoInJhbSIpLCBRU3RyaW5nKCJ2cmFtIil9KSB7CisgICAgICAgIGRv
dWJsZSB0b3RhbCA9IHJlc3VsdC52YWx1ZShwcmVmaXggKyAiX3RvdGFsX2J5dGVzIikudG9Eb3Vi
bGUoKTsKKyAgICAgICAgaWYgKHRvdGFsIDw9IDApIHsgcmVzdWx0LnJlbW92ZShwcmVmaXggKyAi
X3BlcmNlbnQiKTsgcmVzdWx0LnJlbW92ZShwcmVmaXggKyAiX3VzZWRfYnl0ZXMiKTsgfQorICAg
ICAgICBlbHNlIGlmIChyZXN1bHQuY29udGFpbnMocHJlZml4ICsgIl91c2VkX2J5dGVzIikpIHsK
KyAgICAgICAgICAgIGRvdWJsZSB1c2VkID0gcU1pbihyZXN1bHQudmFsdWUocHJlZml4ICsgIl91
c2VkX2J5dGVzIikudG9Eb3VibGUoKSwgdG90YWwpOworICAgICAgICAgICAgcmVzdWx0W3ByZWZp
eCArICJfdXNlZF9ieXRlcyJdID0gdXNlZDsgcmVzdWx0W3ByZWZpeCArICJfcGVyY2VudCJdID0g
dXNlZCAqIDEwMCAvIHRvdGFsOworICAgICAgICB9CisgICAgfQorICAgIGlmICghcmVjb2duaXpl
ZCkgeyAqZXJyb3IgPSAiSG9zdCBkb2VzIG5vdCBleHBvc2UgdGhlIGV4cGVjdGVkIFZpYmVwb2xs
byBzdGF0cyBmaWVsZHMiOyByZXR1cm4ge307IH0KKyAgICBlcnJvci0+Y2xlYXIoKTsgcmV0dXJu
IHJlc3VsdDsKK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6cmVmcmVzaCgpIHsKKyAgICBpZiAoIW1f
dmlzaWJsZSB8fCBtX3JlcGx5IHx8ICFjb25maWd1cmVkKCkpIHJldHVybjsKKyAgICBRVXJsIHVy
bChtX2VuZHBvaW50KTsgdXJsLnNldFBhdGgoIi9hcGkvaG9zdC9zdGF0cyIpOworICAgIFFOZXR3
b3JrUmVxdWVzdCByZXEodXJsKTsKKyAgICByZXEuc2V0QXR0cmlidXRlKFFOZXR3b3JrUmVxdWVz
dDo6UmVkaXJlY3RQb2xpY3lBdHRyaWJ1dGUsIFFOZXR3b3JrUmVxdWVzdDo6TWFudWFsUmVkaXJl
Y3RQb2xpY3kpOworICAgIHJlcS5zZXRUcmFuc2ZlclRpbWVvdXQoMzAwMCk7CisgICAgcmVxLnNl
dFJhd0hlYWRlcigiQXV0aG9yaXphdGlvbiIsICJCZWFyZXIgIiArIG1fdG9rZW4udG9VdGY4KCkp
OworICAgIHJlcS5zZXRSYXdIZWFkZXIoIkFjY2VwdCIsICJhcHBsaWNhdGlvbi9qc29uIik7Cisg
ICAgYXV0byByZXBseSA9IG1fbmV0d29yay5nZXQocmVxKTsgcmVwbHktPnNldFJlYWRCdWZmZXJT
aXplKDY1NTM2KTsgbV9yZXBseSA9IHJlcGx5OworICAgIGF1dG8gZGF0YSA9IHN0ZDo6bWFrZV9z
aGFyZWQ8UUJ5dGVBcnJheT4oKTsKKyAgICBhdXRvIGludmFsaWRQaW4gPSBzdGQ6Om1ha2Vfc2hh
cmVkPGJvb2w+KGZhbHNlKTsKKyAgICBhdXRvIG92ZXJzaXplZCA9IHN0ZDo6bWFrZV9zaGFyZWQ8
Ym9vbD4oZmFsc2UpOworICAgIGF1dG8gY2VydE1hdGNoZXMgPSBbdGhpcywgcmVwbHldIHsKKyAg
ICAgICAgcmV0dXJuIG5vcm1hbGl6ZWRQaW4oUVN0cmluZzo6ZnJvbUxhdGluMShyZXBseS0+c3Ns
Q29uZmlndXJhdGlvbigpLnBlZXJDZXJ0aWZpY2F0ZSgpLmRpZ2VzdChRQ3J5cHRvZ3JhcGhpY0hh
c2g6OlNoYTI1NikudG9IZXgoKSkpID09IG1fcGluOworICAgIH07CisgICAgY29ubmVjdChyZXBs
eSwgJlFOZXR3b3JrUmVwbHk6OmVuY3J5cHRlZCwgdGhpcywgW3RoaXMsIHJlcGx5LCBjZXJ0TWF0
Y2hlcywgaW52YWxpZFBpbl0geworICAgICAgICBpZiAoIW1fcGluLmlzRW1wdHkoKSAmJiAhY2Vy
dE1hdGNoZXMoKSkgeyAqaW52YWxpZFBpbiA9IHRydWU7IHJlcGx5LT5hYm9ydCgpOyB9CisgICAg
fSk7CisgICAgY29ubmVjdChyZXBseSwgJlFOZXR3b3JrUmVwbHk6OnNzbEVycm9ycywgdGhpcywg
W3RoaXMsIHJlcGx5LCBjZXJ0TWF0Y2hlc10oY29uc3QgUUxpc3Q8UVNzbEVycm9yPiYgZXJyb3Jz
KSB7CisgICAgICAgIGlmIChtX3Bpbi5pc0VtcHR5KCkgfHwgIWNlcnRNYXRjaGVzKCkpIHJldHVy
bjsKKyAgICAgICAgZm9yIChjb25zdCBhdXRvJiBlIDogZXJyb3JzKSB7CisgICAgICAgICAgICBp
ZiAoZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6U2VsZlNpZ25lZENlcnRpZmljYXRlICYmIGUuZXJy
b3IoKSAhPSBRU3NsRXJyb3I6OlNlbGZTaWduZWRDZXJ0aWZpY2F0ZUluQ2hhaW4gJiYKKyAgICAg
ICAgICAgICAgICBlLmVycm9yKCkgIT0gUVNzbEVycm9yOjpDZXJ0aWZpY2F0ZVVudHJ1c3RlZCAm
JiBlLmVycm9yKCkgIT0gUVNzbEVycm9yOjpIb3N0TmFtZU1pc21hdGNoKSByZXR1cm47CisgICAg
ICAgIH0KKyAgICAgICAgcmVwbHktPmlnbm9yZVNzbEVycm9ycyhlcnJvcnMpOyAvLyBPbmx5IHRo
aXMgZXhwbGljaXRseSBwaW5uZWQgaG9zdCBjZXJ0aWZpY2F0ZS4KKyAgICB9KTsKKyAgICBjb25u
ZWN0KHJlcGx5LCAmUU5ldHdvcmtSZXBseTo6cmVhZHlSZWFkLCB0aGlzLCBbcmVwbHksIGRhdGEs
IG92ZXJzaXplZF0geworICAgICAgICBpZiAoKm92ZXJzaXplZCB8fCByZXBseS0+aXNGaW5pc2hl
ZCgpKSByZXR1cm47CisgICAgICAgIGlmIChkYXRhLT5zaXplKCkgKyByZXBseS0+Ynl0ZXNBdmFp
bGFibGUoKSA+IDY1NTM2KSB7ICpvdmVyc2l6ZWQgPSB0cnVlOyByZXBseS0+YWJvcnQoKTsgcmV0
dXJuOyB9CisgICAgICAgIGRhdGEtPmFwcGVuZChyZXBseS0+cmVhZEFsbCgpKTsKKyAgICB9KTsK
KyAgICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtSZXBseTo6ZmluaXNoZWQsIHRoaXMsIFt0aGlz
LCByZXBseSwgZGF0YSwgaW52YWxpZFBpbiwgb3ZlcnNpemVkXSB7CisgICAgICAgIG1fcmVwbHkg
PSBudWxscHRyOworICAgICAgICBpbnQgc3RhdHVzID0gcmVwbHktPmF0dHJpYnV0ZShRTmV0d29y
a1JlcXVlc3Q6Okh0dHBTdGF0dXNDb2RlQXR0cmlidXRlKS50b0ludCgpOworICAgICAgICBpZiAo
Km92ZXJzaXplZCkgZmFpbCh0cigiSG9zdCBzdGF0cyByZXNwb25zZSBleGNlZWRlZCB0aGUgc2l6
ZSBsaW1pdCIpKTsKKyAgICAgICAgZWxzZSBpZiAoKmludmFsaWRQaW4pIGZhaWwodHIoIkhvc3Qg
Y2VydGlmaWNhdGUgY2hhbmdlZDsgdmVyaWZ5IHRoZSBzYXZlZCBmaW5nZXJwcmludCIpKTsKKyAg
ICAgICAgZWxzZSBpZiAoc3RhdHVzID09IDQwMSB8fCBzdGF0dXMgPT0gNDAzKSBmYWlsKHRyKCJI
b3N0IHN0YXRzIGFjY2VzcyBkZW5pZWQ6IGNoZWNrIHRoZSByZWFkLW9ubHkgdG9rZW4iKSk7Cisg
ICAgICAgIGVsc2UgaWYgKHN0YXR1cyA9PSA0MDQpIGZhaWwodHIoIlRoaXMgaG9zdCBkb2VzIG5v
dCBwcm92aWRlIFZpYmVwb2xsbyBoYXJkd2FyZSBzdGF0cyIpKTsKKyAgICAgICAgZWxzZSBpZiAo
cmVwbHktPmVycm9yKCkgPT0gUU5ldHdvcmtSZXBseTo6U3NsSGFuZHNoYWtlRmFpbGVkRXJyb3Ip
IGZhaWwodHIoIlZlcmlmeSB0aGUgaG9zdCBjZXJ0aWZpY2F0ZSBmaW5nZXJwcmludCBpbiBDb25m
aWd1cmUiKSk7CisgICAgICAgIGVsc2UgaWYgKHJlcGx5LT5lcnJvcigpICE9IFFOZXR3b3JrUmVw
bHk6Ok5vRXJyb3IgfHwgc3RhdHVzICE9IDIwMCkgZmFpbCh0cigiSG9zdCBzdGF0cyB1bmF2YWls
YWJsZTogY2hlY2sgY29ubmVjdGlvbiBhbmQgcmVhbHRpbWUgc3RhdHMgc2V0dGluZyIpKTsKKyAg
ICAgICAgZWxzZSB7CisgICAgICAgICAgICBkYXRhLT5hcHBlbmQocmVwbHktPnJlYWRBbGwoKSk7
IFFTdHJpbmcgZXJyb3I7CisgICAgICAgICAgICBhdXRvIHBhcnNlZCA9IHBhcnNlU3RhdHMoKmRh
dGEsICZlcnJvcik7CisgICAgICAgICAgICBpZiAoIWVycm9yLmlzRW1wdHkoKSkgZmFpbChlcnJv
cik7CisgICAgICAgICAgICBlbHNlIHsgbV9zdGF0c1RpbWVyLnNldEludGVydmFsKDIwMDApOyBt
X3N0YXRzID0gcGFyc2VkOyBtX3N0YXR1cyA9IHRyKCJIT1NUIOKAoiByZWNlaXZlZCAlMSIpLmFy
ZyhRRGF0ZVRpbWU6OmN1cnJlbnREYXRlVGltZSgpLnRvU3RyaW5nKCJoaDptbTpzcyIpKTsgZW1p
dCBzdGF0c0NoYW5nZWQoKTsgfQorICAgICAgICB9CisgICAgICAgIHJlcGx5LT5kZWxldGVMYXRl
cigpOworICAgIH0pOworICAgIC8vIEFic29sdXRlIHJlcXVlc3QgYm91bmQgZXZlbiBpZiBhIHBl
ZXIga2VlcHMgc2VuZGluZyBvY2Nhc2lvbmFsIGJ5dGVzLgorICAgIFFUaW1lcjo6c2luZ2xlU2hv
dCgzNTAwLCByZXBseSwgW3JlcGx5XSB7IGlmICghcmVwbHktPmlzRmluaXNoZWQoKSkgcmVwbHkt
PmFib3J0KCk7IH0pOworfQorUVZhcmlhbnRNYXAgQ3JpbXNvblN0YXR1czo6cmVhZExvY2FsKGNv
bnN0IFFTdHJpbmcmIHJvb3QpIHsKKyAgICBRVmFyaWFudE1hcCBvdXQ7IFFTdHJpbmdMaXN0IG5l
dHdvcmtzOworICAgIGZvciAoY29uc3QgYXV0byYgbmFtZSA6IFFEaXIocm9vdCArICIvY2xhc3Mv
bmV0IikuZW50cnlMaXN0KFFEaXI6OkRpcnMgfCBRRGlyOjpOb0RvdEFuZERvdERvdCkpIHsKKyAg
ICAgICAgaWYgKG5hbWUgPT0gImxvIiB8fCByZWFkKHJvb3QgKyAiL2NsYXNzL25ldC8iICsgbmFt
ZSArICIvb3BlcnN0YXRlIikgIT0gInVwIikgY29udGludWU7CisgICAgICAgIG5ldHdvcmtzIDw8
IG5hbWU7CisgICAgfQorICAgIG91dFsiY29ubmVjdGVkIl0gPSAhbmV0d29ya3MuaXNFbXB0eSgp
OyBvdXRbIm5ldHdvcmsiXSA9IG5ldHdvcmtzLmlzRW1wdHkoKSA/IHRyKCJObyBhY3RpdmUgbmV0
d29yayBsaW5rIikgOiBuZXR3b3Jrcy5qb2luKCIsICIpOworICAgIC8vIExpbmsgc3RhdHVzIGlz
IGludGVudGlvbmFsbHkgbm90IHByZXNlbnRlZCBhcyBpbnRlcm5ldCByZWFjaGFiaWxpdHkuCisg
ICAgb3V0WyJiYXR0ZXJ5UGVyY2VudCJdID0gLTE7IG91dFsiYmF0dGVyeVN0YXRlIl0gPSB0cigi
QmF0dGVyeSB1bmF2YWlsYWJsZSIpOworICAgIGZvciAoY29uc3QgYXV0byYgbmFtZSA6IFFEaXIo
cm9vdCArICIvY2xhc3MvcG93ZXJfc3VwcGx5IikuZW50cnlMaXN0KFFEaXI6OkRpcnMgfCBRRGly
OjpOb0RvdEFuZERvdERvdCkpIHsKKyAgICAgICAgY29uc3QgYXV0byBiYXNlID0gcm9vdCArICIv
Y2xhc3MvcG93ZXJfc3VwcGx5LyIgKyBuYW1lICsgIi8iOworICAgICAgICBpZiAocmVhZChiYXNl
ICsgInR5cGUiKSAhPSAiQmF0dGVyeSIgfHwgcmVhZChiYXNlICsgInByZXNlbnQiKSA9PSAiMCIp
IGNvbnRpbnVlOworICAgICAgICBib29sIG9rOyBpbnQgY2FwID0gcmVhZChiYXNlICsgImNhcGFj
aXR5IikudG9JbnQoJm9rKTsKKyAgICAgICAgaWYgKG9rICYmIGNhcCA+PSAwICYmIGNhcCA8PSAx
MDApIG91dFsiYmF0dGVyeVBlcmNlbnQiXSA9IGNhcDsKKyAgICAgICAgY29uc3QgYXV0byBzdGF0
ZSA9IHJlYWQoYmFzZSArICJzdGF0dXMiKTsgb3V0WyJiYXR0ZXJ5U3RhdGUiXSA9IHN0YXRlLmlz
RW1wdHkoKSA/IHRyKCJVbmtub3duIikgOiBzdGF0ZTsgYnJlYWs7CisgICAgfQorICAgIHJldHVy
biBvdXQ7Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OnJlZnJlc2hMb2NhbCgpIHsKKyAgICBtX2xv
Y2FsID0gcmVhZExvY2FsKCk7IG1fbG9jYWxbIndpZmlTaWduYWwiXSA9IC0xOyBlbWl0IGxvY2Fs
Q2hhbmdlZCgpOworICAgIGlmIChtX3dpZmkuc3RhdGUoKSA9PSBRUHJvY2Vzczo6Tm90UnVubmlu
ZykgeworICAgICAgICBtX3dpZmkuc3RhcnQoIm5tY2xpIiwgeyItdCIsICItLWVzY2FwZSIsICJu
byIsICItZiIsICJBQ1RJVkUsU0lHTkFMLFNTSUQiLCAiZGV2aWNlIiwgIndpZmkiLCAibGlzdCIs
ICItLXJlc2NhbiIsICJubyJ9KTsKKyAgICAgICAgUVRpbWVyOjpzaW5nbGVTaG90KDIwMDAsICZt
X3dpZmksIFt0aGlzXSB7IGlmIChtX3dpZmkuc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmlu
ZykgbV93aWZpLmtpbGwoKTsgfSk7CisgICAgfQorfQorCitzdGF0aWMgdm9pZCByZWdpc3RlckNy
aW1zb25TdGF0dXMoKSB7CisgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlPENyaW1zb25TdGF0
dXM+KCJDcmltc29uU3RhdHVzIiwgMSwgMCwgIkNyaW1zb25TdGF0dXMiLAorICAgICAgICBbXShR
UW1sRW5naW5lKiwgUUpTRW5naW5lKikgLT4gUU9iamVjdCogeyByZXR1cm4gbmV3IENyaW1zb25T
dGF0dXMoKTsgfSk7Cit9CitRX0NPUkVBUFBfU1RBUlRVUF9GVU5DVElPTihyZWdpc3RlckNyaW1z
b25TdGF0dXMpCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5oIGIv
YXBwL21vb25saWdodG9zL2NyaW1zb25zdGF0dXMuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwLi4yZGFjMGQxCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL2Ny
aW1zb25zdGF0dXMuaApAQCAtMCwwICsxLDUyIEBACisjcHJhZ21hIG9uY2UKKyNpbmNsdWRlIDxR
T2JqZWN0PgorI2luY2x1ZGUgPFFWYXJpYW50TWFwPgorI2luY2x1ZGUgPFFUaW1lcj4KKyNpbmNs
dWRlIDxRTmV0d29ya0FjY2Vzc01hbmFnZXI+CisjaW5jbHVkZSA8UVBvaW50ZXI+CisjaW5jbHVk
ZSA8UU5ldHdvcmtSZXBseT4KKyNpbmNsdWRlIDxRUHJvY2Vzcz4KKworLy8gT3B0aW9uYWwgbGF1
bmNoZXIgc3RhdHVzLiBOZXZlciBwYXJ0aWNpcGF0ZXMgaW4gdGhlIHN0cmVhbWluZy9kZWNvZGVy
IHBhdGguCitjbGFzcyBDcmltc29uU3RhdHVzIDogcHVibGljIFFPYmplY3QgeworICAgIFFfT0JK
RUNUCisgICAgUV9QUk9QRVJUWShRVmFyaWFudE1hcCBsb2NhbCBSRUFEIGxvY2FsIE5PVElGWSBs
b2NhbENoYW5nZWQpCisgICAgUV9QUk9QRVJUWShRVmFyaWFudE1hcCBzdGF0cyBSRUFEIHN0YXRz
IE5PVElGWSBzdGF0c0NoYW5nZWQpCisgICAgUV9QUk9QRVJUWShRU3RyaW5nIHN0YXR1cyBSRUFE
IHN0YXR1cyBOT1RJRlkgc3RhdHNDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBlbmRw
b2ludCBSRUFEIGVuZHBvaW50IE5PVElGWSBjb25maWdDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFko
UVN0cmluZyBmaW5nZXJwcmludCBSRUFEIGZpbmdlcnByaW50IE5PVElGWSBjb25maWdDaGFuZ2Vk
KQorICAgIFFfUFJPUEVSVFkoYm9vbCBjb25maWd1cmVkIFJFQUQgY29uZmlndXJlZCBOT1RJRlkg
Y29uZmlnQ2hhbmdlZCkKK3B1YmxpYzoKKyAgICBleHBsaWNpdCBDcmltc29uU3RhdHVzKFFPYmpl
Y3QqIHBhcmVudCA9IG51bGxwdHIpOworICAgIH5Dcmltc29uU3RhdHVzKCkgb3ZlcnJpZGU7Cisg
ICAgUVZhcmlhbnRNYXAgbG9jYWwoKSBjb25zdCB7IHJldHVybiBtX2xvY2FsOyB9CisgICAgUVZh
cmlhbnRNYXAgc3RhdHMoKSBjb25zdCB7IHJldHVybiBtX3N0YXRzOyB9CisgICAgUVN0cmluZyBz
dGF0dXMoKSBjb25zdCB7IHJldHVybiBtX3N0YXR1czsgfQorICAgIFFTdHJpbmcgZW5kcG9pbnQo
KSBjb25zdCB7IHJldHVybiBtX2VuZHBvaW50OyB9CisgICAgUVN0cmluZyBmaW5nZXJwcmludCgp
IGNvbnN0IHsgcmV0dXJuIG1fcGluOyB9CisgICAgYm9vbCBjb25maWd1cmVkKCkgY29uc3QgeyBy
ZXR1cm4gIW1fZW5kcG9pbnQuaXNFbXB0eSgpICYmICFtX3Rva2VuLmlzRW1wdHkoKTsgfQorICAg
IFFfSU5WT0tBQkxFIHZvaWQgc2VsZWN0SG9zdChRU3RyaW5nIGlkLCBRU3RyaW5nIHN1Z2dlc3Rl
ZFVybCk7CisgICAgUV9JTlZPS0FCTEUgYm9vbCBjb25maWd1cmUoUVN0cmluZyB1cmwsIFFTdHJp
bmcgdG9rZW4sIFFTdHJpbmcgcGluKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIHNldFZpc2libGUo
Ym9vbCB2aXNpYmxlKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIHJlZnJlc2goKTsKKyAgICBzdGF0
aWMgUVZhcmlhbnRNYXAgcGFyc2VTdGF0cyhjb25zdCBRQnl0ZUFycmF5JiBieXRlcywgUVN0cmlu
ZyogZXJyb3IpOworICAgIHN0YXRpYyBib29sIHZhbGlkRW5kcG9pbnQoY29uc3QgUVN0cmluZyYg
dXJsKTsKKyAgICBzdGF0aWMgUVN0cmluZyBub3JtYWxpemVkUGluKFFTdHJpbmcgcGluKTsKKyAg
ICBzdGF0aWMgUVZhcmlhbnRNYXAgcmVhZExvY2FsKGNvbnN0IFFTdHJpbmcmIHN5c1Jvb3QgPSAi
L3N5cyIpOworc2lnbmFsczoKKyAgICB2b2lkIGxvY2FsQ2hhbmdlZCgpOworICAgIHZvaWQgc3Rh
dHNDaGFuZ2VkKCk7CisgICAgdm9pZCBjb25maWdDaGFuZ2VkKCk7Citwcml2YXRlOgorICAgIHZv
aWQgcmVmcmVzaExvY2FsKCk7CisgICAgdm9pZCBmYWlsKFFTdHJpbmcgbWVzc2FnZSk7CisgICAg
dm9pZCBjYW5jZWwoKTsKKyAgICBRU3RyaW5nIGNvbmZpZ0ZpbGUoKSBjb25zdDsKKyAgICBRU3Ry
aW5nIG1faG9zdCwgbV9lbmRwb2ludCwgbV90b2tlbiwgbV9waW4sIG1fc3RhdHVzID0gIkNob29z
ZSBhIGhvc3QgdG8gdmlldyBoYXJkd2FyZSBzdGF0cyI7CisgICAgUVZhcmlhbnRNYXAgbV9sb2Nh
bCwgbV9zdGF0czsKKyAgICBRVGltZXIgbV9sb2NhbFRpbWVyLCBtX3N0YXRzVGltZXI7CisgICAg
UVByb2Nlc3MgbV93aWZpOworICAgIFFOZXR3b3JrQWNjZXNzTWFuYWdlciBtX25ldHdvcms7Cisg
ICAgUVBvaW50ZXI8UU5ldHdvcmtSZXBseT4gbV9yZXBseTsKKyAgICBib29sIG1fdmlzaWJsZSA9
IGZhbHNlOworfTsKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMu
Y3BwIGIvYXBwL21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5jcHAKbmV3IGZpbGUgbW9kZSAx
MDA2NDQKaW5kZXggMDAwMDAwMC4uNTFkOGUzZAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29u
bGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwCkBAIC0wLDAgKzEsODAgQEAKKyNpbmNsdWRlICJl
Y2xpcHNlcHJvZmlsZXMuaCIKKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVk
ZSA8UUNvcmVBcHBsaWNhdGlvbj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFJ
bWFnZVJlYWRlcj4KKyNpbmNsdWRlIDxRSW1hZ2U+CisjaW5jbHVkZSA8UURpcj4KKyNpbmNsdWRl
IDxRRmlsZUluZm8+CisjaW5jbHVkZSA8UVNhdmVGaWxlPgorI2luY2x1ZGUgPFFTdGFuZGFyZFBh
dGhzPgorUVN0cmluZyBFY2xpcHNlUHJvZmlsZXM6OmtleShRU3RyaW5nIGhvc3QsIFFTdHJpbmcg
bmFtZSkgeworICAgIHJldHVybiAiZWNsaXBzZS9wcm9maWxlcy8iICsgUVN0cmluZzo6ZnJvbUxh
dGluMShRQ3J5cHRvZ3JhcGhpY0hhc2g6Omhhc2goaG9zdC50b1V0ZjgoKSwgUUNyeXB0b2dyYXBo
aWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpICsgIi8iICsgUVN0cmluZzo6ZnJvbUxhdGluMShRQ3J5
cHRvZ3JhcGhpY0hhc2g6Omhhc2gobmFtZS50cmltbWVkKCkudG9VdGY4KCksIFFDcnlwdG9ncmFw
aGljSGFzaDo6U2hhMjU2KS50b0hleCgpKTsKK30KK2Jvb2wgRWNsaXBzZVByb2ZpbGVzOjp2YWxp
ZChjb25zdCBRVmFyaWFudE1hcCYgdmFsdWVzKSB7CisgICAgY29uc3QgUU1hcDxRU3RyaW5nLFFQ
YWlyPGludCxpbnQ+PiByYW5nZXMgPSB7eyJ3aWR0aCIsezMyMCw3NjgwfX0sIHsiaGVpZ2h0Iix7
MjAwLDQzMjB9fSwgeyJmcHMiLHsxLDI0MH19LCB7ImJpdHJhdGVLYnBzIix7NTAwLDE1MDAwMH19
fTsKKyAgICBpZiAodmFsdWVzLnNpemUoKSAhPSByYW5nZXMuc2l6ZSgpKSByZXR1cm4gZmFsc2U7
CisgICAgZm9yIChhdXRvIGkgPSByYW5nZXMuYmVnaW4oKTsgaSAhPSByYW5nZXMuZW5kKCk7ICsr
aSkgeworICAgICAgICBib29sIG9rOyBhdXRvIG4gPSB2YWx1ZXMudmFsdWUoaS5rZXkoKSkudG9J
bnQoJm9rKTsKKyAgICAgICAgaWYgKCFvayB8fCBuIDwgaS52YWx1ZSgpLmZpcnN0IHx8IG4gPiBp
LnZhbHVlKCkuc2Vjb25kKSByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIHJldHVybiB0cnVlOwor
fQorYm9vbCBFY2xpcHNlUHJvZmlsZXM6OnNhdmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUs
IFFWYXJpYW50TWFwIHZhbHVlcykgeworICAgIG5hbWUgPSBuYW1lLnRyaW1tZWQoKTsKKyAgICBp
ZiAoaG9zdC5zaXplKCkgPiAyNTYgfHwgbmFtZS5pc0VtcHR5KCkgfHwgbmFtZS5zaXplKCkgPiA0
OCB8fCAhdmFsaWQodmFsdWVzKSkgcmV0dXJuIGZhbHNlOworICAgIGlmICghbmFtZXMoaG9zdCku
Y29udGFpbnMobmFtZSkgJiYgbmFtZXMoaG9zdCkuc2l6ZSgpID49IDMyKSByZXR1cm4gZmFsc2U7
CisgICAgUVNldHRpbmdzIHNldHRpbmdzOyBzZXR0aW5ncy5zZXRWYWx1ZShrZXkoaG9zdCxuYW1l
KSsiL25hbWUiLG5hbWUpOyBzZXR0aW5ncy5zZXRWYWx1ZShrZXkoaG9zdCxuYW1lKSsiL3ZhbHVl
cyIsdmFsdWVzKTsgc2V0dGluZ3Muc3luYygpOworICAgIHJldHVybiBzZXR0aW5ncy5zdGF0dXMo
KSA9PSBRU2V0dGluZ3M6Ok5vRXJyb3I7Cit9CitRVmFyaWFudE1hcCBFY2xpcHNlUHJvZmlsZXM6
OmxvYWQoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUpIHsKKyAgICBRU2V0dGluZ3Mgc2V0dGlu
Z3M7IGF1dG8gdmFsdWUgPSBzZXR0aW5ncy52YWx1ZShrZXkoaG9zdCxuYW1lKSsiL3ZhbHVlcyIp
LnRvTWFwKCk7CisgICAgcmV0dXJuIHZhbGlkKHZhbHVlKSA/IHZhbHVlIDogUVZhcmlhbnRNYXAo
KTsKK30KK2Jvb2wgRWNsaXBzZVByb2ZpbGVzOjpyZW1vdmUoUVN0cmluZyBob3N0LCBRU3RyaW5n
IG5hbWUsIGJvb2wgY29uZmlybWVkKSB7CisgICAgaWYgKCFjb25maXJtZWQpIHJldHVybiBmYWxz
ZTsKKyAgICBRU2V0dGluZ3Mgc2V0dGluZ3M7IHNldHRpbmdzLnJlbW92ZShrZXkoaG9zdCxuYW1l
KSk7IHNldHRpbmdzLnN5bmMoKTsgcmV0dXJuIHNldHRpbmdzLnN0YXR1cygpID09IFFTZXR0aW5n
czo6Tm9FcnJvcjsKK30KK1FTdHJpbmdMaXN0IEVjbGlwc2VQcm9maWxlczo6bmFtZXMoUVN0cmlu
ZyBob3N0KSB7CisgICAgUVNldHRpbmdzIHNldHRpbmdzOyBzZXR0aW5ncy5iZWdpbkdyb3VwKGtl
eShob3N0LCAiIikuc2VjdGlvbignLycsMCwtMikpOworICAgIFFTdHJpbmdMaXN0IHJlc3VsdDsK
KyAgICBmb3IgKGNvbnN0IGF1dG8mIGNoaWxkIDogc2V0dGluZ3MuY2hpbGRHcm91cHMoKSkgeyBh
dXRvIG5hbWUgPSBzZXR0aW5ncy52YWx1ZShjaGlsZCsiL25hbWUiKS50b1N0cmluZygpOyBpZiAo
IW5hbWUuaXNFbXB0eSgpKSByZXN1bHQuYXBwZW5kKG5hbWUpOyB9CisgICAgcmVzdWx0LnNvcnQo
KTsgcmV0dXJuIHJlc3VsdDsKK30KK3N0YXRpYyB2b2lkIHJlZ2lzdGVyRWNsaXBzZVByb2ZpbGVz
KCkgeworICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9uVHlwZTxFY2xpcHNlUHJvZmlsZXM+KCJFY2xp
cHNlUHJvZmlsZXMiLDEsMCwiRWNsaXBzZVByb2ZpbGVzIixbXShRUW1sRW5naW5lKixRSlNFbmdp
bmUqKSAtPiBRT2JqZWN0KiB7IHJldHVybiBuZXcgRWNsaXBzZVByb2ZpbGVzKCk7IH0pOworfQor
UV9DT1JFQVBQX1NUQVJUVVBfRlVOQ1RJT04ocmVnaXN0ZXJFY2xpcHNlUHJvZmlsZXMpCisKK1FV
cmwgRWNsaXBzZVByb2ZpbGVzOjpiYWNrZ3JvdW5kRm9sZGVyKCkgY29uc3QgeworICAgIFFTdHJp
bmcgcGF0aD1RU3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRhcmRQYXRoczo6
UGljdHVyZXNMb2NhdGlvbik7CisgICAgcmV0dXJuIFFVcmw6OmZyb21Mb2NhbEZpbGUoUURpcihw
YXRoKS5leGlzdHMoKT9wYXRoOlFEaXI6OmhvbWVQYXRoKCkpOworfQorUVZhcmlhbnRMaXN0IEVj
bGlwc2VQcm9maWxlczo6YmFja2dyb3VuZEZpbGVzKFFVcmwgZGlyZWN0b3J5KSB7CisgICAgaWYo
ZGlyZWN0b3J5LmlzRW1wdHkoKSkgZGlyZWN0b3J5PWJhY2tncm91bmRGb2xkZXIoKTsKKyAgICBp
ZighZGlyZWN0b3J5LmlzTG9jYWxGaWxlKCkpIHJldHVybiB7fTsKKyAgICBRRGlyIGRpcihkaXJl
Y3RvcnkudG9Mb2NhbEZpbGUoKSk7IGlmKCFkaXIuZXhpc3RzKCkpIHJldHVybiB7fTsKKyAgICBR
VmFyaWFudExpc3QgcmVzdWx0OworICAgIGlmKCFkaXIuaXNSb290KCkpIHsgUURpciB1cD1kaXI7
dXAuY2RVcCgpO3Jlc3VsdC5hcHBlbmQoUVZhcmlhbnRNYXB7eyJuYW1lIixRU3RyaW5nKCIuLiIp
fSx7InVybCIsUVVybDo6ZnJvbUxvY2FsRmlsZSh1cC5hYnNvbHV0ZVBhdGgoKSl9LHsiZGlyZWN0
b3J5Iix0cnVlfX0pOyB9CisgICAgZm9yKGNvbnN0IFFGaWxlSW5mbyYgZmlsZTpkaXIuZW50cnlJ
bmZvTGlzdChRRGlyOjpEaXJzfFFEaXI6OkZpbGVzfFFEaXI6Ok5vRG90QW5kRG90RG90fFFEaXI6
OlJlYWRhYmxlLFFEaXI6OkRpcnNGaXJzdHxRRGlyOjpOYW1lKSkgeworICAgICAgICBpZihyZXN1
bHQuc2l6ZSgpPj01MTIpIGJyZWFrOworICAgICAgICBpZighZmlsZS5pc0RpcigpJiYhUVN0cmlu
Z0xpc3R7InBuZyIsImpwZyIsImpwZWciLCJ3ZWJwIiwiYm1wIn0uY29udGFpbnMoZmlsZS5zdWZm
aXgoKS50b0xvd2VyKCkpKSBjb250aW51ZTsKKyAgICAgICAgcmVzdWx0LmFwcGVuZChRVmFyaWFu
dE1hcHt7Im5hbWUiLGZpbGUuZmlsZU5hbWUoKX0seyJ1cmwiLFFVcmw6OmZyb21Mb2NhbEZpbGUo
ZmlsZS5hYnNvbHV0ZUZpbGVQYXRoKCkpfSx7ImRpcmVjdG9yeSIsZmlsZS5pc0RpcigpfX0pOwor
ICAgIH0KKyAgICByZXR1cm4gcmVzdWx0OworfQorYm9vbCBFY2xpcHNlUHJvZmlsZXM6OmNob29z
ZUJhY2tncm91bmQoUVVybCBzb3VyY2UpIHsKKyAgICBpZighc291cmNlLmlzTG9jYWxGaWxlKCkp
IHJldHVybiBmYWxzZTsKKyAgICBRRmlsZUluZm8gZmlsZShzb3VyY2UudG9Mb2NhbEZpbGUoKSk7
IGlmKCFmaWxlLmlzRmlsZSgpfHxmaWxlLnNpemUoKT4zMioxMDI0KjEwMjQpIHJldHVybiBmYWxz
ZTsKKyAgICBRSW1hZ2VSZWFkZXIgcmVhZGVyKGZpbGUuYWJzb2x1dGVGaWxlUGF0aCgpKTtyZWFk
ZXIuc2V0QXV0b1RyYW5zZm9ybSh0cnVlKTsKKyAgICBRU2l6ZSBzaXplPXJlYWRlci5zaXplKCk7
aWYoIXNpemUuaXNWYWxpZCgpfHxzaXplLndpZHRoKCk+MTYzODR8fHNpemUuaGVpZ2h0KCk+MTYz
ODR8fHFpbnQ2NChzaXplLndpZHRoKCkpKnNpemUuaGVpZ2h0KCk+NjQwMDAwMDApIHJldHVybiBm
YWxzZTsKKyAgICBpZihzaXplLndpZHRoKCk+MjU2MHx8c2l6ZS5oZWlnaHQoKT4yNTYwKSByZWFk
ZXIuc2V0U2NhbGVkU2l6ZShzaXplLnNjYWxlZCgyNTYwLDI1NjAsUXQ6OktlZXBBc3BlY3RSYXRp
bykpOworICAgIFFJbWFnZSBpbWFnZT1yZWFkZXIucmVhZCgpO2lmKGltYWdlLmlzTnVsbCgpKSBy
ZXR1cm4gZmFsc2U7CisgICAgUVN0cmluZyBmb2xkZXI9UVN0YW5kYXJkUGF0aHM6OndyaXRhYmxl
TG9jYXRpb24oUVN0YW5kYXJkUGF0aHM6OkFwcERhdGFMb2NhdGlvbikrIi9hcHBlYXJhbmNlIjsK
KyAgICBpZighUURpcigpLm1rcGF0aChmb2xkZXIpKSByZXR1cm4gZmFsc2U7CisgICAgUVN0cmlu
ZyBwYXRoPWZvbGRlcisiL2NyaW1zb24tZ2xhc3MtYmFja2dyb3VuZC5wbmciOworICAgIFFTYXZl
RmlsZSBvdXRwdXQocGF0aCk7aWYoIW91dHB1dC5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KXx8
IWltYWdlLnNhdmUoJm91dHB1dCwiUE5HIil8fCFvdXRwdXQuY29tbWl0KCkpIHJldHVybiBmYWxz
ZTsKKyAgICBRU2V0dGluZ3Mgc2V0dGluZ3M7c2V0dGluZ3Muc2V0VmFsdWUoImVjbGlwc2UvYmFj
a2dyb3VuZFBhdGgiLHBhdGgpO3NldHRpbmdzLnN5bmMoKTsKKyAgICBlbWl0IGJhY2tncm91bmRD
aGFuZ2VkKCk7ZW1pdCBhcHBlYXJhbmNlQ2hhbmdlZCgpO3JldHVybiBzZXR0aW5ncy5zdGF0dXMo
KT09UVNldHRpbmdzOjpOb0Vycm9yOworfQordm9pZCBFY2xpcHNlUHJvZmlsZXM6OnJlc2V0QmFj
a2dyb3VuZCgpIHsgUVNldHRpbmdzKCkucmVtb3ZlKCJlY2xpcHNlL2JhY2tncm91bmRQYXRoIik7
ZW1pdCBiYWNrZ3JvdW5kQ2hhbmdlZCgpO2VtaXQgYXBwZWFyYW5jZUNoYW5nZWQoKTsgfQpkaWZm
IC0tZ2l0IGEvYXBwL21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5oIGIvYXBwL21vb25saWdo
dG9zL2VjbGlwc2Vwcm9maWxlcy5oCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAu
LjY3NGZiOTAKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2Zp
bGVzLmgKQEAgLTAsMCArMSwzOSBAQAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4K
KyNpbmNsdWRlIDxRVmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRU2V0dGluZ3M+CisjaW5jbHVkZSA8
UVVybD4KKyNpbmNsdWRlIDxRVmFyaWFudExpc3Q+CitjbGFzcyBFY2xpcHNlUHJvZmlsZXMgOiBw
dWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpFQ1QKKyAgICBRX1BST1BFUlRZKGludCB0ZXh0U2Nh
bGUgUkVBRCB0ZXh0U2NhbGUgV1JJVEUgc2V0VGV4dFNjYWxlIE5PVElGWSBhcHBlYXJhbmNlQ2hh
bmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgcmVkdWNlZE1vdGlvbiBSRUFEIHJlZHVjZWRNb3Rp
b24gV1JJVEUgc2V0UmVkdWNlZE1vdGlvbiBOT1RJRlkgYXBwZWFyYW5jZUNoYW5nZWQpCisgICAg
UV9QUk9QRVJUWShib29sIGhpZ2hDb250cmFzdCBSRUFEIGhpZ2hDb250cmFzdCBXUklURSBzZXRI
aWdoQ29udHJhc3QgTk9USUZZIGFwcGVhcmFuY2VDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVVy
bCBiYWNrZ3JvdW5kIFJFQUQgYmFja2dyb3VuZCBOT1RJRlkgYmFja2dyb3VuZENoYW5nZWQpCisg
ICAgUV9QUk9QRVJUWShpbnQgYmFja2dyb3VuZERpbSBSRUFEIGJhY2tncm91bmREaW0gV1JJVEUg
c2V0QmFja2dyb3VuZERpbSBOT1RJRlkgYXBwZWFyYW5jZUNoYW5nZWQpCitwdWJsaWM6CisgICAg
ZXhwbGljaXQgRWNsaXBzZVByb2ZpbGVzKFFPYmplY3QqIHBhcmVudCA9IG51bGxwdHIpIDogUU9i
amVjdChwYXJlbnQpIHt9CisgICAgaW50IHRleHRTY2FsZSgpIGNvbnN0IHsgcmV0dXJuIHFCb3Vu
ZCgxMDAsUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvdGV4dFNjYWxlIiwxMDApLnRvSW50KCks
MTI1KTsgfQorICAgIGJvb2wgcmVkdWNlZE1vdGlvbigpIGNvbnN0IHsgcmV0dXJuIFFTZXR0aW5n
cygpLnZhbHVlKCJlY2xpcHNlL3JlZHVjZWRNb3Rpb24iLGZhbHNlKS50b0Jvb2woKTsgfQorICAg
IGJvb2wgaGlnaENvbnRyYXN0KCkgY29uc3QgeyByZXR1cm4gUVNldHRpbmdzKCkudmFsdWUoImVj
bGlwc2UvaGlnaENvbnRyYXN0IixmYWxzZSkudG9Cb29sKCk7IH0KKyAgICB2b2lkIHNldFRleHRT
Y2FsZShpbnQgdmFsdWUpIHsgUVNldHRpbmdzKCkuc2V0VmFsdWUoImVjbGlwc2UvdGV4dFNjYWxl
IixxQm91bmQoMTAwLHZhbHVlLDEyNSkpOyBlbWl0IGFwcGVhcmFuY2VDaGFuZ2VkKCk7IH0KKyAg
ICB2b2lkIHNldFJlZHVjZWRNb3Rpb24oYm9vbCB2YWx1ZSkgeyBRU2V0dGluZ3MoKS5zZXRWYWx1
ZSgiZWNsaXBzZS9yZWR1Y2VkTW90aW9uIix2YWx1ZSk7IGVtaXQgYXBwZWFyYW5jZUNoYW5nZWQo
KTsgfQorICAgIHZvaWQgc2V0SGlnaENvbnRyYXN0KGJvb2wgdmFsdWUpIHsgUVNldHRpbmdzKCku
c2V0VmFsdWUoImVjbGlwc2UvaGlnaENvbnRyYXN0Iix2YWx1ZSk7IGVtaXQgYXBwZWFyYW5jZUNo
YW5nZWQoKTsgfQorICAgIFFVcmwgYmFja2dyb3VuZCgpIGNvbnN0IHsgUVN0cmluZyBwYXRoPVFT
ZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2JhY2tncm91bmRQYXRoIikudG9TdHJpbmcoKTtyZXR1
cm4gcGF0aC5pc0VtcHR5KCk/UVVybCgpOlFVcmw6OmZyb21Mb2NhbEZpbGUocGF0aCk7IH0KKyAg
ICBpbnQgYmFja2dyb3VuZERpbSgpIGNvbnN0IHsgcmV0dXJuIHFCb3VuZCgzMCxRU2V0dGluZ3Mo
KS52YWx1ZSgiZWNsaXBzZS9iYWNrZ3JvdW5kRGltIiw2NSkudG9JbnQoKSw5MCk7IH0KKyAgICB2
b2lkIHNldEJhY2tncm91bmREaW0oaW50IHZhbHVlKSB7IFFTZXR0aW5ncygpLnNldFZhbHVlKCJl
Y2xpcHNlL2JhY2tncm91bmREaW0iLHFCb3VuZCgzMCx2YWx1ZSw5MCkpOyBlbWl0IGFwcGVhcmFu
Y2VDaGFuZ2VkKCk7IH0KKyAgICBRX0lOVk9LQUJMRSBib29sIGNob29zZUJhY2tncm91bmQoUVVy
bCBzb3VyY2UpOworICAgIFFfSU5WT0tBQkxFIHZvaWQgcmVzZXRCYWNrZ3JvdW5kKCk7CisgICAg
UV9JTlZPS0FCTEUgUVZhcmlhbnRMaXN0IGJhY2tncm91bmRGaWxlcyhRVXJsIGRpcmVjdG9yeT1R
VXJsKCkpOworICAgIFFfSU5WT0tBQkxFIFFVcmwgYmFja2dyb3VuZEZvbGRlcigpIGNvbnN0Owor
ICAgIFFfSU5WT0tBQkxFIGJvb2wgc2F2ZShRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSwgUVZh
cmlhbnRNYXAgdmFsdWVzKTsKKyAgICBRX0lOVk9LQUJMRSBRVmFyaWFudE1hcCBsb2FkKFFTdHJp
bmcgaG9zdCwgUVN0cmluZyBuYW1lKTsKKyAgICBRX0lOVk9LQUJMRSBib29sIHJlbW92ZShRU3Ry
aW5nIGhvc3QsIFFTdHJpbmcgbmFtZSwgYm9vbCBjb25maXJtZWQpOworICAgIFFfSU5WT0tBQkxF
IFFTdHJpbmdMaXN0IG5hbWVzKFFTdHJpbmcgaG9zdCk7CisgICAgc3RhdGljIGJvb2wgdmFsaWQo
Y29uc3QgUVZhcmlhbnRNYXAmIHZhbHVlcyk7CitzaWduYWxzOgorICAgIHZvaWQgYXBwZWFyYW5j
ZUNoYW5nZWQoKTsKKyAgICB2b2lkIGJhY2tncm91bmRDaGFuZ2VkKCk7Citwcml2YXRlOgorICAg
IHN0YXRpYyBRU3RyaW5nIGtleShRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSk7Cit9OwpkaWZm
IC0tZ2l0IGEvYXBwL21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuY3BwIGIvYXBwL21vb25saWdo
dG9zL2xvY2FsaGFyZHdhcmUuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAu
LjE5ZjgxOGQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvbG9jYWxoYXJkd2Fy
ZS5jcHAKQEAgLTAsMCArMSwxMzggQEAKKyNpbmNsdWRlICJsb2NhbGhhcmR3YXJlLmgiCisjaW5j
bHVkZSA8UXRNYXRoPgorI2luY2x1ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFEaXI+CisjaW5jbHVk
ZSA8UVNldD4KKyNpbmNsdWRlIDxRU3RvcmFnZUluZm8+CisjaW5jbHVkZSA8UUZpbGVJbmZvPgor
I2luY2x1ZGUgPFFFbGFwc2VkVGltZXI+CisjaW5jbHVkZSA8UU11dGV4PgorI2luY2x1ZGUgPFFN
dXRleExvY2tlcj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFDb3JlQXBwbGlj
YXRpb24+CisjaW5jbHVkZSA8UVJlZ3VsYXJFeHByZXNzaW9uPgorCitzdGF0aWMgUVN0cmluZyBy
ZWFkKGNvbnN0IFFTdHJpbmcmIHBhdGgpIHsgUUZpbGUgZihwYXRoKTsgcmV0dXJuIGYub3BlbihR
SU9EZXZpY2U6OlJlYWRPbmx5KSA/IFFTdHJpbmc6OmZyb21VdGY4KGYucmVhZCgzMjc2OCkpLnRy
aW1tZWQoKSA6IFFTdHJpbmcoKTsgfQorc3RhdGljIGRvdWJsZSBudW1iZXIoY29uc3QgUVN0cmlu
ZyYgcGF0aCkgeyBib29sIG9rOyBkb3VibGUgbj1yZWFkKHBhdGgpLnRvRG91YmxlKCZvayk7IHJl
dHVybiBvayAmJiBxSXNGaW5pdGUobikgPyBuIDogLTE7IH0KK0xvY2FsSGFyZHdhcmU6OkxvY2Fs
SGFyZHdhcmUoUU9iamVjdCogcGFyZW50KTpRT2JqZWN0KHBhcmVudCkgeyBtX3RpbWVyLnNldElu
dGVydmFsKHJlZnJlc2hTZWNvbmRzKCkqMTAwMCk7IGNvbm5lY3QoJm1fdGltZXIsJlFUaW1lcjo6
dGltZW91dCx0aGlzLCZMb2NhbEhhcmR3YXJlOjpyZWZyZXNoKTsgfQordm9pZCBMb2NhbEhhcmR3
YXJlOjpzZXRBY3RpdmUoYm9vbCBhY3RpdmUpIHsgbV9sZWdhY3lBY3RpdmU9YWN0aXZlO3VwZGF0
ZVNhbXBsaW5nKCk7IH0KK3ZvaWQgTG9jYWxIYXJkd2FyZTo6dXBkYXRlU2FtcGxpbmcoKSB7Cisg
ICAgaWYoIW1fbGVnYWN5QWN0aXZlICYmIG1fY29uc3VtZXJzLmlzRW1wdHkoKSkgbV90aW1lci5z
dG9wKCk7CisgICAgZWxzZSBpZighbV90aW1lci5pc0FjdGl2ZSgpKSB7cmVmcmVzaCgpO21fdGlt
ZXIuc3RhcnQoKTt9Cit9Cit2b2lkIExvY2FsSGFyZHdhcmU6OnNldENvbnN1bWVyQWN0aXZlKFFP
YmplY3QqIGNvbnN1bWVyLGJvb2wgYWN0aXZlKSB7CisgICAgaWYoIWNvbnN1bWVyKSByZXR1cm47
CisgICAgaWYoYWN0aXZlICYmICFtX2NvbnN1bWVycy5jb250YWlucyhjb25zdW1lcikpIHsKKyAg
ICAgICAgbV9jb25zdW1lcnMuaW5zZXJ0KGNvbnN1bWVyKTsKKyAgICAgICAgaWYoIW1fa25vd25D
b25zdW1lcnMuY29udGFpbnMoY29uc3VtZXIpKSB7CisgICAgICAgICAgICBtX2tub3duQ29uc3Vt
ZXJzLmluc2VydChjb25zdW1lcik7CisgICAgICAgICAgICBjb25uZWN0KGNvbnN1bWVyLCZRT2Jq
ZWN0OjpkZXN0cm95ZWQsdGhpcyxbdGhpcyxjb25zdW1lcl17bV9rbm93bkNvbnN1bWVycy5yZW1v
dmUoY29uc3VtZXIpO21fY29uc3VtZXJzLnJlbW92ZShjb25zdW1lcik7dXBkYXRlU2FtcGxpbmco
KTt9KTsKKyAgICAgICAgfQorICAgIH0gZWxzZSBpZighYWN0aXZlKSBtX2NvbnN1bWVycy5yZW1v
dmUoY29uc3VtZXIpOworICAgIHVwZGF0ZVNhbXBsaW5nKCk7Cit9Cit2b2lkIExvY2FsSGFyZHdh
cmU6OnJlZnJlc2goKSB7IG1fcmVhZGluZ3M9c2FtcGxlKCk7IG1faGlzdG9yeS5hcHBlbmQobV9y
ZWFkaW5ncyk7IHdoaWxlKG1faGlzdG9yeS5zaXplKCk+NjApIG1faGlzdG9yeS5yZW1vdmVGaXJz
dCgpOyBlbWl0IGNoYW5nZWQoKTsgfQordm9pZCBMb2NhbEhhcmR3YXJlOjpzZXRGaWVsZHMoUVN0
cmluZ0xpc3QgdikgeyBRU3RyaW5nTGlzdCBjbGVhbjsgZm9yKGNvbnN0IFFTdHJpbmcmIGtleTpR
U3RyaW5nTGlzdHsiY3B1IiwibWVtb3J5IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3JrIiwi
YmF0dGVyeSIsInN0b3JhZ2UifSkgaWYodi5jb250YWlucyhrZXkpKSBjbGVhbi5hcHBlbmQoa2V5
KTsgc2F2ZSgibG9jYWxGaWVsZHMiLGNsZWFuKTsgfQorCitRVmFyaWFudE1hcCBMb2NhbEhhcmR3
YXJlOjpzYW1wbGUoY29uc3QgUVN0cmluZyYgcm9vdCkgeworICAgIC8vIFNoYXJlZCBjYWNoZTog
U2V0dGluZ3MgYW5kIHRoZSBkZWNvZGVyIHJldXNlIG9uZSBib3VuZGVkLCByZWFkLW9ubHkgc2Ft
cGxlLgorICAgIHN0YXRpYyBRTXV0ZXggbXV0ZXg7IFFNdXRleExvY2tlciBsb2NrZXIoJm11dGV4
KTsKKyAgICBzdGF0aWMgUUVsYXBzZWRUaW1lciBjbG9jazsgaWYoIWNsb2NrLmlzVmFsaWQoKSkg
Y2xvY2suc3RhcnQoKTsKKyAgICBzdGF0aWMgUU1hcDxRU3RyaW5nLFFWYXJpYW50TWFwPiBwcmV2
aW91cywgY2FjaGVkOworICAgIHN0YXRpYyBRTWFwPFFTdHJpbmcscWludDY0PiBsYXN0OworICAg
IHFpbnQ2NCBub3c9Y2xvY2suZWxhcHNlZCgpOworICAgIGludCBpbnRlcnZhbD1xQm91bmQoMSxR
U2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9oYXJkd2FyZVJlZnJlc2giLDIpLnRvSW50KCksNSkq
MTAwMDsKKyAgICBpZihjYWNoZWQuY29udGFpbnMocm9vdCkgJiYgbm93LWxhc3QudmFsdWUocm9v
dCk8aW50ZXJ2YWwpIHJldHVybiBjYWNoZWQudmFsdWUocm9vdCk7CisgICAgUVZhcmlhbnRNYXAg
cmVzdWx0LCBjb3VudGVyczsKKyAgICBhdXRvIG9sZD1wcmV2aW91cy52YWx1ZShyb290KTsgZG91
YmxlIHNlY29uZHM9KG5vdy1sYXN0LnZhbHVlKHJvb3QpKS8xMDAwLjA7CisgICAgYXV0byBzdGF0
PXJlYWQocm9vdCsiL3Byb2Mvc3RhdCIpLnNlY3Rpb24oJ1xuJywwLDApLnNpbXBsaWZpZWQoKS5z
cGxpdCgnICcpOworICAgIGlmKHN0YXQuc2l6ZSgpPj05ICYmIHN0YXRbMF09PSJjcHUiKSB7Cisg
ICAgICAgIHF1aW50NjQgdG90YWw9MDsgZm9yKGludCBpPTE7aTw9ODtpKyspIHRvdGFsKz1zdGF0
W2ldLnRvVUxvbmdMb25nKCk7CisgICAgICAgIHF1aW50NjQgaWRsZT1zdGF0WzRdLnRvVUxvbmdM
b25nKCkrc3RhdFs1XS50b1VMb25nTG9uZygpOworICAgICAgICBjb3VudGVyc1sidG90YWwiXT10
b3RhbDsgY291bnRlcnNbImlkbGUiXT1pZGxlOworICAgICAgICBxdWludDY0IGJlZm9yZT1vbGQu
dmFsdWUoInRvdGFsIikudG9VTG9uZ0xvbmcoKTsKKyAgICAgICAgaWYob2xkLmNvbnRhaW5zKCJ0
b3RhbCIpICYmIHRvdGFsPmJlZm9yZSAmJiBpZGxlPj1vbGQudmFsdWUoImlkbGUiKS50b1VMb25n
TG9uZygpKSByZXN1bHRbImNwdVBlcmNlbnQiXT1xQm91bmQoMC4wLDEwMC4wKigxLjAtZG91Ymxl
KGlkbGUtb2xkWyJpZGxlIl0udG9VTG9uZ0xvbmcoKSkvZG91YmxlKHRvdGFsLWJlZm9yZSkpLDEw
MC4wKTsKKyAgICB9CisgICAgUU1hcDxRU3RyaW5nLHF1aW50NjQ+IG1lbW9yeTsKKyAgICBmb3Io
Y29uc3QgUVN0cmluZyYgbGluZTpyZWFkKHJvb3QrIi9wcm9jL21lbWluZm8iKS5zcGxpdCgnXG4n
KSkgeyBhdXRvIHBhcnRzPWxpbmUuc2ltcGxpZmllZCgpLnNwbGl0KCcgJyk7IGlmKHBhcnRzLnNp
emUoKT49MikgbWVtb3J5W3BhcnRzWzBdXT1wYXJ0c1sxXS50b1VMb25nTG9uZygpKjEwMjQ7IH0K
KyAgICBxdWludDY0IHRvdGFsPW1lbW9yeS52YWx1ZSgiTWVtVG90YWw6IiksIGF2YWlsYWJsZT1t
ZW1vcnkudmFsdWUoIk1lbUF2YWlsYWJsZToiKTsKKyAgICBpZih0b3RhbCAmJiBhdmFpbGFibGU8
PXRvdGFsICYmIG1lbW9yeS5jb250YWlucygiTWVtQXZhaWxhYmxlOiIpKSB7IHJlc3VsdFsibWVt
b3J5VXNlZEdpQiJdPWRvdWJsZSh0b3RhbC1hdmFpbGFibGUpLygxMDI0KjEwMjQqMTAyNCk7IHJl
c3VsdFsibWVtb3J5VG90YWxHaUIiXT1kb3VibGUodG90YWwpLygxMDI0KjEwMjQqMTAyNCk7IHJl
c3VsdFsibWVtb3J5UGVyY2VudCJdPTEwMC4wKih0b3RhbC1hdmFpbGFibGUpL3RvdGFsOyB9Cisg
ICAgaWYobWVtb3J5LmNvbnRhaW5zKCJTd2FwVG90YWw6IikpIHJlc3VsdFsic3dhcFVzZWRNaUIi
XT1kb3VibGUobWVtb3J5LnZhbHVlKCJTd2FwVG90YWw6IiktcU1pbihtZW1vcnkudmFsdWUoIlN3
YXBUb3RhbDoiKSxtZW1vcnkudmFsdWUoIlN3YXBGcmVlOiIpKSkvKDEwMjQqMTAyNCk7CisgICAg
ZG91YmxlIGZyZXF1ZW5jeT1udW1iZXIocm9vdCsiL3N5cy9kZXZpY2VzL3N5c3RlbS9jcHUvY3B1
MC9jcHVmcmVxL3NjYWxpbmdfY3VyX2ZyZXEiKTsgaWYoZnJlcXVlbmN5PjApIHJlc3VsdFsiY3B1
TUh6Il09ZnJlcXVlbmN5LzEwMDA7CisgICAgZG91YmxlIHRlbXBlcmF0dXJlPS0xLCBmYW49LTE7
CisgICAgUURpciBodyhyb290KyIvc3lzL2NsYXNzL2h3bW9uIik7CisgICAgZm9yKGNvbnN0IFFT
dHJpbmcmIGRldmljZTpody5lbnRyeUxpc3QoUURpcjo6RGlyc3xRRGlyOjpOb0RvdEFuZERvdERv
dCkpIHsKKyAgICAgICAgUURpciBzZW5zb3JzKGh3LmZpbGVQYXRoKGRldmljZSkpOyBRU3RyaW5n
IG5hbWU9cmVhZChzZW5zb3JzLmZpbGVQYXRoKCJuYW1lIikpOworICAgICAgICBmb3IoY29uc3Qg
UVN0cmluZyYgZmlsZTpzZW5zb3JzLmVudHJ5TGlzdCh7InRlbXAqX2lucHV0IiwiZmFuKl9pbnB1
dCJ9LFFEaXI6OkZpbGVzKSkgeworICAgICAgICAgICAgZG91YmxlIHZhbHVlPW51bWJlcihzZW5z
b3JzLmZpbGVQYXRoKGZpbGUpKTsKKyAgICAgICAgICAgIGlmKGZpbGUuc3RhcnRzV2l0aCgidGVt
cCIpICYmIChuYW1lPT0iY29yZXRlbXAiIHx8IG5hbWU9PSJrMTB0ZW1wIikgJiYgdmFsdWU+PTAg
JiYgdmFsdWU8PTE1MDAwMCkgdGVtcGVyYXR1cmU9cU1heCh0ZW1wZXJhdHVyZSx2YWx1ZS8xMDAw
KTsKKyAgICAgICAgICAgIGlmKGZpbGUuc3RhcnRzV2l0aCgiZmFuIikgJiYgdmFsdWU+PTAgJiYg
dmFsdWU8MzAwMDApIGZhbj1xTWF4KGZhbix2YWx1ZSk7CisgICAgICAgIH0KKyAgICB9CisgICAg
aWYodGVtcGVyYXR1cmU+PTApIHJlc3VsdFsidGVtcGVyYXR1cmVDIl09dGVtcGVyYXR1cmU7Cisg
ICAgaWYoZmFuPj0wKSByZXN1bHRbImZhblJQTSJdPWZhbjsKKyAgICBRRGlyIGRybShyb290KyIv
c3lzL2NsYXNzL2RybSIpOworICAgIGZvcihjb25zdCBRU3RyaW5nJiBjYXJkOmRybS5lbnRyeUxp
c3QoeyJjYXJkWzAtOV0qIn0sUURpcjo6RGlyc3xRRGlyOjpOb0RvdEFuZERvdERvdCkpIHsgZG91
YmxlIGJ1c3k9bnVtYmVyKGRybS5maWxlUGF0aChjYXJkKyIvZGV2aWNlL2dwdV9idXN5X3BlcmNl
bnQiKSk7IGlmKGJ1c3k+PTAgJiYgYnVzeTw9MTAwKSB7IHJlc3VsdFsiZ3B1UGVyY2VudCJdPWJ1
c3k7IGJyZWFrOyB9IH0KKyAgICAvLyBEUk0gZmRpbmZvIGlzIHVucHJpdmlsZWdlZCwgcmVhZC1v
bmx5IGFuZCBzY29wZWQgdG8gdGhpcyBFY2xpcHNlIHByb2Nlc3MuCisgICAgLy8gRGVkdXBsaWNh
dGUgZGVzY3JpcHRvcnMgYmVsb25naW5nIHRvIHRoZSBzYW1lIERSTSBjbGllbnQ7IG5ldmVyIGNh
bGwgdGhpcyBzeXN0ZW0td2lkZSBHUFUgbG9hZC4KKyAgICBxdWludDY0IHZpZGVvPTA7IGJvb2wg
aGFzVmlkZW89ZmFsc2U7IFFTZXQ8UVN0cmluZz4gY2xpZW50czsKKyAgICBRRGlyIGRlc2NyaXB0
b3JzKHJvb3QrIi9wcm9jL3NlbGYvZmRpbmZvIik7CisgICAgaW50IGluc3BlY3RlZD0wOworICAg
IGZvcihjb25zdCBRU3RyaW5nJiBmaWxlOmRlc2NyaXB0b3JzLmVudHJ5TGlzdChRRGlyOjpGaWxl
cykpIHsKKyAgICAgICAgaWYoKytpbnNwZWN0ZWQ+MjU2KSBicmVhazsKKyAgICAgICAgUVN0cmlu
ZyBpbmZvPXJlYWQoZGVzY3JpcHRvcnMuZmlsZVBhdGgoZmlsZSkpOworICAgICAgICBhdXRvIGNs
aWVudD1RUmVndWxhckV4cHJlc3Npb24oImRybS1jbGllbnQtaWQ6XFxzKihcXGQrKSIpLm1hdGNo
KGluZm8pOworICAgICAgICBpZighY2xpZW50Lmhhc01hdGNoKCkgfHwgY2xpZW50cy5jb250YWlu
cyhjbGllbnQuY2FwdHVyZWQoMSkpKSBjb250aW51ZTsKKyAgICAgICAgY2xpZW50cy5pbnNlcnQo
Y2xpZW50LmNhcHR1cmVkKDEpKTsKKyAgICAgICAgYXV0byBlbmdpbmVzPVFSZWd1bGFyRXhwcmVz
c2lvbigiZHJtLWVuZ2luZS12aWRlbyg/OlxcZCspPzpcXHMqKFxcZCspXFxzK25zIikuZ2xvYmFs
TWF0Y2goaW5mbyk7CisgICAgICAgIHdoaWxlKGVuZ2luZXMuaGFzTmV4dCgpKSB7IHZpZGVvKz1l
bmdpbmVzLm5leHQoKS5jYXB0dXJlZCgxKS50b1VMb25nTG9uZygpOyBoYXNWaWRlbz10cnVlOyB9
CisgICAgfQorICAgIGlmKGhhc1ZpZGVvKSB7CisgICAgICAgIGNvdW50ZXJzWyJ2aWRlbyJdPXZp
ZGVvOworICAgICAgICBpZihvbGQuY29udGFpbnMoInZpZGVvIikgJiYgc2Vjb25kcz4wICYmIHZp
ZGVvPj1vbGQudmFsdWUoInZpZGVvIikudG9VTG9uZ0xvbmcoKSkgcmVzdWx0WyJ2aWRlb1BlcmNl
bnQiXT1xQm91bmQoMC4wLGRvdWJsZSh2aWRlby1vbGRbInZpZGVvIl0udG9VTG9uZ0xvbmcoKSkv
c2Vjb25kcy8xMDAwMDAwMC4wLDEwMC4wKTsKKyAgICB9CisgICAgUVN0cmluZyBuaWM7CisgICAg
Zm9yKGNvbnN0IFFTdHJpbmcmIGxpbmU6cmVhZChyb290KyIvcHJvYy9uZXQvcm91dGUiKS5zcGxp
dCgnXG4nKSkgeyBhdXRvIHA9bGluZS5zaW1wbGlmaWVkKCkuc3BsaXQoJyAnKTsgaWYocC5zaXpl
KCk+MyAmJiBwWzFdPT0iMDAwMDAwMDAiKSB7IG5pYz1wWzBdOyBicmVhazsgfSB9CisgICAgZm9y
KGNvbnN0IFFTdHJpbmcmIGxpbmU6cmVhZChyb290KyIvcHJvYy9uZXQvZGV2Iikuc3BsaXQoJ1xu
JykpIHsKKyAgICAgICAgaWYobGluZS5zZWN0aW9uKCc6JywwLDApLnRyaW1tZWQoKSE9bmljIHx8
IG5pYy5pc0VtcHR5KCkpIGNvbnRpbnVlOworICAgICAgICBhdXRvIHA9bGluZS5zZWN0aW9uKCc6
JywxKS5zaW1wbGlmaWVkKCkuc3BsaXQoJyAnKTsgaWYocC5zaXplKCk8MTYpIGNvbnRpbnVlOwor
ICAgICAgICBxdWludDY0IHJ4PXBbMF0udG9VTG9uZ0xvbmcoKSwgdHg9cFs4XS50b1VMb25nTG9u
ZygpOyBjb3VudGVyc1sicngiXT1yeDsgY291bnRlcnNbInR4Il09dHg7IGNvdW50ZXJzWyJuaWMi
XT1uaWM7CisgICAgICAgIGlmKHNlY29uZHM+MCAmJiBvbGQudmFsdWUoIm5pYyIpLnRvU3RyaW5n
KCk9PW5pYyAmJiByeD49b2xkLnZhbHVlKCJyeCIpLnRvVUxvbmdMb25nKCkgJiYgdHg+PW9sZC52
YWx1ZSgidHgiKS50b1VMb25nTG9uZygpKSB7IHJlc3VsdFsicmVjZWl2ZU1pQiJdPWRvdWJsZShy
eC1vbGRbInJ4Il0udG9VTG9uZ0xvbmcoKSkvc2Vjb25kcy8oMTAyNCoxMDI0KTsgcmVzdWx0WyJ0
cmFuc21pdE1pQiJdPWRvdWJsZSh0eC1vbGRbInR4Il0udG9VTG9uZ0xvbmcoKSkvc2Vjb25kcy8o
MTAyNCoxMDI0KTsgfQorICAgIH0KKyAgICBRRGlyIHBvd2VyKHJvb3QrIi9zeXMvY2xhc3MvcG93
ZXJfc3VwcGx5Iik7CisgICAgZm9yKGNvbnN0IFFTdHJpbmcmIG5hbWU6cG93ZXIuZW50cnlMaXN0
KFFEaXI6OkRpcnN8UURpcjo6Tm9Eb3RBbmREb3REb3QpKSB7CisgICAgICAgIFFTdHJpbmcgcGF0
aD1wb3dlci5maWxlUGF0aChuYW1lKTsgaWYocmVhZChwYXRoKyIvdHlwZSIpIT0iQmF0dGVyeSIp
IGNvbnRpbnVlOworICAgICAgICBkb3VibGUgcGVyY2VudD1udW1iZXIocGF0aCsiL2NhcGFjaXR5
Iik7IGlmKHBlcmNlbnQ+PTAgJiYgcGVyY2VudDw9MTAwKSByZXN1bHRbImJhdHRlcnlQZXJjZW50
Il09cGVyY2VudDsKKyAgICAgICAgcmVzdWx0WyJiYXR0ZXJ5U3RhdGUiXT1yZWFkKHBhdGgrIi9z
dGF0dXMiKS5sZWZ0KDMyKTsgZG91YmxlIHdhdHRzPW51bWJlcihwYXRoKyIvcG93ZXJfbm93Iik7
IGlmKHdhdHRzPj0wKSByZXN1bHRbImJhdHRlcnlXYXR0cyJdPXdhdHRzLzEwMDAwMDA7IGJyZWFr
OworICAgIH0KKyAgICBpZihyb290LmlzRW1wdHkoKSkgeyBRU3RvcmFnZUluZm8gZGlzaz1RU3Rv
cmFnZUluZm86OnJvb3QoKTsgaWYoZGlzay5pc1ZhbGlkKCkgJiYgZGlzay5pc1JlYWR5KCkgJiYg
ZGlzay5ieXRlc1RvdGFsKCk+MCkgeyByZXN1bHRbInN0b3JhZ2VUb3RhbEdpQiJdPWRvdWJsZShk
aXNrLmJ5dGVzVG90YWwoKSkvKDEwMjQqMTAyNCoxMDI0KTsgcmVzdWx0WyJzdG9yYWdlRnJlZUdp
QiJdPWRvdWJsZShkaXNrLmJ5dGVzQXZhaWxhYmxlKCkpLygxMDI0KjEwMjQqMTAyNCk7IH0gfQor
ICAgIGlmKHJvb3QuaXNFbXB0eSgpKSB7CisgICAgICAgIFFTdHJpbmcgZGV2aWNlPVFGaWxlSW5m
byhRU3RyaW5nOjpmcm9tVXRmOChRU3RvcmFnZUluZm86OnJvb3QoKS5kZXZpY2UoKSkpLmNhbm9u
aWNhbEZpbGVQYXRoKCkuc2VjdGlvbignLycsLTEpOworICAgICAgICBhdXRvIGlvPXJlYWQoIi9z
eXMvY2xhc3MvYmxvY2svIitkZXZpY2UrIi9zdGF0Iikuc2ltcGxpZmllZCgpLnNwbGl0KCcgJyk7
CisgICAgICAgIGlmKCFkZXZpY2UuaXNFbXB0eSgpICYmIGlvLnNpemUoKT49NykgeworICAgICAg
ICAgICAgcXVpbnQ2NCByZWFkcz1pb1syXS50b1VMb25nTG9uZygpLHdyaXRlcz1pb1s2XS50b1VM
b25nTG9uZygpOworICAgICAgICAgICAgY291bnRlcnNbImRpc2siXT1kZXZpY2U7Y291bnRlcnNb
InJlYWRzIl09cmVhZHM7Y291bnRlcnNbIndyaXRlcyJdPXdyaXRlczsKKyAgICAgICAgICAgIGlm
KHNlY29uZHM+MCAmJiBvbGQudmFsdWUoImRpc2siKS50b1N0cmluZygpPT1kZXZpY2UgJiYgcmVh
ZHM+PW9sZC52YWx1ZSgicmVhZHMiKS50b1VMb25nTG9uZygpICYmIHdyaXRlcz49b2xkLnZhbHVl
KCJ3cml0ZXMiKS50b1VMb25nTG9uZygpKSB7CisgICAgICAgICAgICAgICAgcmVzdWx0WyJkaXNr
UmVhZE1pQiJdPWRvdWJsZShyZWFkcy1vbGRbInJlYWRzIl0udG9VTG9uZ0xvbmcoKSkqNTEyL3Nl
Y29uZHMvKDEwMjQqMTAyNCk7CisgICAgICAgICAgICAgICAgcmVzdWx0WyJkaXNrV3JpdGVNaUIi
XT1kb3VibGUod3JpdGVzLW9sZFsid3JpdGVzIl0udG9VTG9uZ0xvbmcoKSkqNTEyL3NlY29uZHMv
KDEwMjQqMTAyNCk7CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgcHJldmlv
dXNbcm9vdF09Y291bnRlcnM7IGxhc3Rbcm9vdF09bm93OyBjYWNoZWRbcm9vdF09cmVzdWx0OyBy
ZXR1cm4gcmVzdWx0OworfQorCitRU3RyaW5nIExvY2FsSGFyZHdhcmU6Om92ZXJsYXlUZXh0KCkg
eworICAgIGF1dG8gcj1zYW1wbGUoKTsgUVNldHRpbmdzIHM7IGF1dG8gZmllbGRzPXMudmFsdWUo
ImVjbGlwc2UvbG9jYWxGaWVsZHMiLFFTdHJpbmdMaXN0eyJjcHUiLCJtZW1vcnkiLCJ0ZW1wZXJh
dHVyZSIsImdwdSIsIm5ldHdvcmsiLCJiYXR0ZXJ5In0pLnRvU3RyaW5nTGlzdCgpOyBib29sIGRl
dGFpbD1zLnZhbHVlKCJlY2xpcHNlL2xvY2FsRGV0YWlsZWQiLGZhbHNlKS50b0Jvb2woKTsKKyAg
ICBRU3RyaW5nTGlzdCBsaW5lc3siRWNsaXBzZU9TIHwgTE9DQUwgTUFDIn07CisgICAgYXV0byB2
YWx1ZT1bJnJdKFFTdHJpbmcga2V5LFFTdHJpbmcgc3VmZml4LGludCBwcmVjaXNpb249MSkgeyBy
ZXR1cm4gci5jb250YWlucyhrZXkpID8gUVN0cmluZzo6bnVtYmVyKHJba2V5XS50b0RvdWJsZSgp
LCdmJyxwcmVjaXNpb24pK3N1ZmZpeCA6IFFTdHJpbmcoIlVuYXZhaWxhYmxlIik7IH07CisgICAg
aWYoZmllbGRzLmNvbnRhaW5zKCJjcHUiKSkgeyBsaW5lczw8IkNQVSAgIit2YWx1ZSgiY3B1UGVy
Y2VudCIsIiUiKTsgaWYoZGV0YWlsKSBsaW5lczw8IkNQVSBjbG9jayAgIit2YWx1ZSgiY3B1TUh6
IiwiIE1IeiIsMCk7IH0KKyAgICBpZihmaWVsZHMuY29udGFpbnMoIm1lbW9yeSIpKSB7IGxpbmVz
PDwiUkFNICAiK3ZhbHVlKCJtZW1vcnlVc2VkR2lCIiwiIEdpQiIpKyIgLyAiK3ZhbHVlKCJtZW1v
cnlUb3RhbEdpQiIsIiBHaUIiKTsgaWYoZGV0YWlsKSBsaW5lczw8IlN3YXAgICIrdmFsdWUoInN3
YXBVc2VkTWlCIiwiIE1pQiIpOyB9CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJ0ZW1wZXJhdHVy
ZSIpKSB7IGxpbmVzPDwiQ1BVIHRlbXBlcmF0dXJlICAiK3ZhbHVlKCJ0ZW1wZXJhdHVyZUMiLCIg
QyIpOyBpZihkZXRhaWwpIGxpbmVzPDwiRmFuICAiK3ZhbHVlKCJmYW5SUE0iLCIgUlBNIiwwKTsg
fQorICAgIGlmKGZpZWxkcy5jb250YWlucygiZ3B1IikpIHsgbGluZXM8PCJHUFUgYnVzeSAgIit2
YWx1ZSgiZ3B1UGVyY2VudCIsIiUiKTsgbGluZXM8PCJFY2xpcHNlIHZpZGVvIGVuZ2luZSAgIit2
YWx1ZSgidmlkZW9QZXJjZW50IiwiJSIpOyB9CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJuZXR3
b3JrIikpIGxpbmVzPDwiTmV0d29yayAgZG93biAiK3ZhbHVlKCJyZWNlaXZlTWlCIiwiIE1pQi9z
IikrIiB8IHVwICIrdmFsdWUoInRyYW5zbWl0TWlCIiwiIE1pQi9zIik7CisgICAgaWYoZmllbGRz
LmNvbnRhaW5zKCJiYXR0ZXJ5IikpIHsgbGluZXM8PCJCYXR0ZXJ5ICAiK3ZhbHVlKCJiYXR0ZXJ5
UGVyY2VudCIsIiUiLDApOyBpZihkZXRhaWwpIGxpbmVzPDwiQmF0dGVyeSBwb3dlciAgIit2YWx1
ZSgiYmF0dGVyeVdhdHRzIiwiIFciKTsgfQorICAgIGlmKGZpZWxkcy5jb250YWlucygic3RvcmFn
ZSIpKSB7IGxpbmVzPDwiVVNCL3Jvb3QgZnJlZSAgIit2YWx1ZSgic3RvcmFnZUZyZWVHaUIiLCIg
R2lCIik7IGlmKGRldGFpbCkgbGluZXM8PCJSb290IEkvTyAgcmVhZCAiK3ZhbHVlKCJkaXNrUmVh
ZE1pQiIsIiBNaUIvcyIpKyIgfCB3cml0ZSAiK3ZhbHVlKCJkaXNrV3JpdGVNaUIiLCIgTWlCL3Mi
KTsgfQorICAgIHJldHVybiBsaW5lcy5qb2luKCdcbicpOworfQorc3RhdGljIHZvaWQgcmVnaXN0
ZXJMb2NhbEhhcmR3YXJlKCkgeyBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGU8TG9jYWxIYXJkd2Fy
ZT4oIkxvY2FsSGFyZHdhcmUiLDEsMCwiTG9jYWxIYXJkd2FyZSIsW10oUVFtbEVuZ2luZSosUUpT
RW5naW5lKiktPlFPYmplY3Qqe3JldHVybiBuZXcgTG9jYWxIYXJkd2FyZSgpO30pOyB9CitRX0NP
UkVBUFBfU1RBUlRVUF9GVU5DVElPTihyZWdpc3RlckxvY2FsSGFyZHdhcmUpCmRpZmYgLS1naXQg
YS9hcHAvbW9vbmxpZ2h0b3MvbG9jYWxoYXJkd2FyZS5oIGIvYXBwL21vb25saWdodG9zL2xvY2Fs
aGFyZHdhcmUuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi42YjZlYWE2Ci0t
LSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuaApAQCAtMCww
ICsxLDU1IEBACisjcHJhZ21hIG9uY2UKKyNpbmNsdWRlIDxRT2JqZWN0PgorI2luY2x1ZGUgPFFW
YXJpYW50TWFwPgorI2luY2x1ZGUgPFFWYXJpYW50TGlzdD4KKyNpbmNsdWRlIDxRVGltZXI+Cisj
aW5jbHVkZSA8UVNldHRpbmdzPgorI2luY2x1ZGUgPFFTZXQ+CisKK2NsYXNzIExvY2FsSGFyZHdh
cmUgOiBwdWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpFQ1QKKyAgICBRX1BST1BFUlRZKFFWYXJp
YW50TWFwIHJlYWRpbmdzIFJFQUQgcmVhZGluZ3MgTk9USUZZIGNoYW5nZWQpCisgICAgUV9QUk9Q
RVJUWShRVmFyaWFudExpc3QgaGlzdG9yeSBSRUFEIGhpc3RvcnkgTk9USUZZIGNoYW5nZWQpCisg
ICAgUV9QUk9QRVJUWShib29sIG92ZXJsYXkgUkVBRCBvdmVybGF5IFdSSVRFIHNldE92ZXJsYXkg
Tk9USUZZIHByZWZlcmVuY2VzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgZGV0YWlsZWQg
UkVBRCBkZXRhaWxlZCBXUklURSBzZXREZXRhaWxlZCBOT1RJRlkgcHJlZmVyZW5jZXNDaGFuZ2Vk
KQorICAgIFFfUFJPUEVSVFkoYm9vbCBzdHJlYW1EZXRhaWxlZCBSRUFEIHN0cmVhbURldGFpbGVk
IFdSSVRFIHNldFN0cmVhbURldGFpbGVkIE5PVElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCisgICAg
UV9QUk9QRVJUWShpbnQgcG9zaXRpb24gUkVBRCBwb3NpdGlvbiBXUklURSBzZXRQb3NpdGlvbiBO
T1RJRlkgcHJlZmVyZW5jZXNDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoaW50IG9wYWNpdHkgUkVB
RCBvcGFjaXR5IFdSSVRFIHNldE9wYWNpdHkgTk9USUZZIHByZWZlcmVuY2VzQ2hhbmdlZCkKKyAg
ICBRX1BST1BFUlRZKGludCByZWZyZXNoU2Vjb25kcyBSRUFEIHJlZnJlc2hTZWNvbmRzIFdSSVRF
IHNldFJlZnJlc2hTZWNvbmRzIE5PVElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCisgICAgUV9QUk9Q
RVJUWShRU3RyaW5nTGlzdCBmaWVsZHMgUkVBRCBmaWVsZHMgV1JJVEUgc2V0RmllbGRzIE5PVElG
WSBwcmVmZXJlbmNlc0NoYW5nZWQpCitwdWJsaWM6CisgICAgZXhwbGljaXQgTG9jYWxIYXJkd2Fy
ZShRT2JqZWN0KiBwYXJlbnQ9bnVsbHB0cik7CisgICAgUVZhcmlhbnRNYXAgcmVhZGluZ3MoKSBj
b25zdCB7IHJldHVybiBtX3JlYWRpbmdzOyB9CisgICAgUVZhcmlhbnRMaXN0IGhpc3RvcnkoKSBj
b25zdCB7IHJldHVybiBtX2hpc3Rvcnk7IH0KKyAgICBib29sIG92ZXJsYXkoKSBjb25zdCB7IHJl
dHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9sb2NhbE92ZXJsYXkiLGZhbHNlKS50b0Jv
b2woKTsgfQorICAgIGJvb2wgZGV0YWlsZWQoKSBjb25zdCB7IHJldHVybiBRU2V0dGluZ3MoKS52
YWx1ZSgiZWNsaXBzZS9sb2NhbERldGFpbGVkIixmYWxzZSkudG9Cb29sKCk7IH0KKyAgICBib29s
IHN0cmVhbURldGFpbGVkKCkgY29uc3QgeyByZXR1cm4gUVNldHRpbmdzKCkudmFsdWUoImVjbGlw
c2Uvc3RyZWFtRGV0YWlsZWQiLGZhbHNlKS50b0Jvb2woKTsgfQorICAgIGludCBwb3NpdGlvbigp
IGNvbnN0IHsgcmV0dXJuIHFCb3VuZCgwLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2Fs
UG9zaXRpb24iLDEpLnRvSW50KCksMyk7IH0KKyAgICBpbnQgb3BhY2l0eSgpIGNvbnN0IHsgcmV0
dXJuIHFCb3VuZCg0MCxRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9vdmVybGF5T3BhY2l0eSIs
ODUpLnRvSW50KCksMTAwKTsgfQorICAgIGludCByZWZyZXNoU2Vjb25kcygpIGNvbnN0IHsgcmV0
dXJuIHFCb3VuZCgxLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2hhcmR3YXJlUmVmcmVzaCIs
MikudG9JbnQoKSw1KTsgfQorICAgIFFTdHJpbmdMaXN0IGZpZWxkcygpIGNvbnN0IHsgcmV0dXJu
IFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2FsRmllbGRzIixRU3RyaW5nTGlzdHsiY3B1
IiwibWVtb3J5IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3JrIiwiYmF0dGVyeSJ9KS50b1N0
cmluZ0xpc3QoKTsgfQorICAgIHZvaWQgc2V0T3ZlcmxheShib29sIHYpIHsgc2F2ZSgibG9jYWxP
dmVybGF5Iix2KTsgfQorICAgIHZvaWQgc2V0RGV0YWlsZWQoYm9vbCB2KSB7IHNhdmUoImxvY2Fs
RGV0YWlsZWQiLHYpOyB9CisgICAgdm9pZCBzZXRTdHJlYW1EZXRhaWxlZChib29sIHYpIHsgc2F2
ZSgic3RyZWFtRGV0YWlsZWQiLHYpOyB9CisgICAgdm9pZCBzZXRQb3NpdGlvbihpbnQgdikgeyBz
YXZlKCJsb2NhbFBvc2l0aW9uIixxQm91bmQoMCx2LDMpKTsgfQorICAgIHZvaWQgc2V0T3BhY2l0
eShpbnQgdikgeyBzYXZlKCJvdmVybGF5T3BhY2l0eSIscUJvdW5kKDQwLHYsMTAwKSk7IH0KKyAg
ICB2b2lkIHNldFJlZnJlc2hTZWNvbmRzKGludCB2KSB7IHNhdmUoImhhcmR3YXJlUmVmcmVzaCIs
cUJvdW5kKDEsdiw1KSk7IG1fdGltZXIuc2V0SW50ZXJ2YWwocmVmcmVzaFNlY29uZHMoKSoxMDAw
KTsgfQorICAgIHZvaWQgc2V0RmllbGRzKFFTdHJpbmdMaXN0IHYpOworICAgIFFfSU5WT0tBQkxF
IHZvaWQgc2V0QWN0aXZlKGJvb2wgYWN0aXZlKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIHNldENv
bnN1bWVyQWN0aXZlKFFPYmplY3QqIGNvbnN1bWVyLGJvb2wgYWN0aXZlKTsKKyAgICBzdGF0aWMg
UVZhcmlhbnRNYXAgc2FtcGxlKGNvbnN0IFFTdHJpbmcmIHJvb3Q9UVN0cmluZygpKTsKKyAgICBz
dGF0aWMgUVN0cmluZyBvdmVybGF5VGV4dCgpOworc2lnbmFsczoKKyAgICB2b2lkIGNoYW5nZWQo
KTsKKyAgICB2b2lkIHByZWZlcmVuY2VzQ2hhbmdlZCgpOworcHJpdmF0ZToKKyAgICB2b2lkIHJl
ZnJlc2goKTsKKyAgICB2b2lkIHVwZGF0ZVNhbXBsaW5nKCk7CisgICAgYm9vbCBtX2xlZ2FjeUFj
dGl2ZT1mYWxzZTsKKyAgICB2b2lkIHNhdmUoUVN0cmluZyBrZXksIFFWYXJpYW50IHZhbHVlKSB7
IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlLyIra2V5LHZhbHVlKTsgZW1pdCBwcmVmZXJl
bmNlc0NoYW5nZWQoKTsgfQorICAgIFFTZXQ8UU9iamVjdCo+IG1fY29uc3VtZXJzOworICAgIFFT
ZXQ8UU9iamVjdCo+IG1fa25vd25Db25zdW1lcnM7CisgICAgUVRpbWVyIG1fdGltZXI7CisgICAg
UVZhcmlhbnRNYXAgbV9yZWFkaW5nczsKKyAgICBRVmFyaWFudExpc3QgbV9oaXN0b3J5OworfTsK
ZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9tYW5hZ2VkdXBkYXRlcy5jcHAgYi9hcHAvbW9v
bmxpZ2h0b3MvbWFuYWdlZHVwZGF0ZXMuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAw
MDAwMDAuLjJiZmNiZmQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvbWFuYWdl
ZHVwZGF0ZXMuY3BwCkBAIC0wLDAgKzEsMTMyIEBACisvLyBFY2xpcHNlT1Mgb3ducyB0aGlzIGN1
c3RvbWl6ZWQgbmF0aXZlIGNsaWVudC4gTm8gZmVlZCByZXF1ZXN0cywgYXNzZXQKKy8vIGRvd25s
b2Fkcywgc3dhcHMgb3IgcmVsYXVuY2hlcyBhcmUgY29tcGlsZWQgaW50byB0aGlzIHVwZGF0ZSBp
bXBsZW1lbnRhdGlvbi4KKyNpbmNsdWRlICIuLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgi
CisjaW5jbHVkZSA8UUNvcmVBcHBsaWNhdGlvbj4KKyNpbmNsdWRlIDxRSnNvbk9iamVjdD4KKwor
c3RhdGljIFFTdHJpbmcgc3RyaXBCdWlsZE1ldGFkYXRhKGNvbnN0IFFTdHJpbmcmIHZlcnNpb24p
Cit7CisgICAgaW50IHBsdXNJZHggPSB2ZXJzaW9uLmluZGV4T2YoJysnKTsKKyAgICByZXR1cm4g
cGx1c0lkeCA+PSAwID8gdmVyc2lvbi5sZWZ0KHBsdXNJZHgpIDogdmVyc2lvbjsKK30KKworc3Rh
dGljIGJvb2wgaXNOdW1lcmljSWRlbnRpZmllcihjb25zdCBRU3RyaW5nJiBzKQoreworICAgIGlm
IChzLmlzRW1wdHkoKSkgeworICAgICAgICByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIGZvciAo
Y29uc3QgUUNoYXImIGMgOiBzKSB7CisgICAgICAgIGlmICghYy5pc0RpZ2l0KCkpIHsKKyAgICAg
ICAgICAgIHJldHVybiBmYWxzZTsKKyAgICAgICAgfQorICAgIH0KKyAgICByZXR1cm4gdHJ1ZTsK
K30KKworaW50IEF1dG9VcGRhdGVDaGVja2VyOjpjb21wYXJlU2VtYW50aWNWZXJzaW9ucyhjb25z
dCBRU3RyaW5nJiB2MSwgY29uc3QgUVN0cmluZyYgdjIpCit7CisgICAgUVN0cmluZyBzMSA9IHN0
cmlwQnVpbGRNZXRhZGF0YSh2MSk7CisgICAgUVN0cmluZyBzMiA9IHN0cmlwQnVpbGRNZXRhZGF0
YSh2Mik7CisKKyAgICBpbnQgZGFzaDEgPSBzMS5pbmRleE9mKCctJyk7CisgICAgaW50IGRhc2gy
ID0gczIuaW5kZXhPZignLScpOworICAgIFFTdHJpbmcgYmFzZTEgPSBkYXNoMSA+PSAwID8gczEu
bGVmdChkYXNoMSkgOiBzMTsKKyAgICBRU3RyaW5nIGJhc2UyID0gZGFzaDIgPj0gMCA/IHMyLmxl
ZnQoZGFzaDIpIDogczI7CisgICAgUVN0cmluZyBwcmUxID0gZGFzaDEgPj0gMCA/IHMxLm1pZChk
YXNoMSArIDEpIDogUVN0cmluZygpOworICAgIFFTdHJpbmcgcHJlMiA9IGRhc2gyID49IDAgPyBz
Mi5taWQoZGFzaDIgKyAxKSA6IFFTdHJpbmcoKTsKKworICAgIC8vIE51bWVyaWMgYmFzZSB2ZXJz
aW9ucyBjb21wYXJlIGZpcnN0ICgwLjQuMC1iZXRhLjAwMSA+IDAuMy4wKQorICAgIGNvbnN0IFFT
dHJpbmdMaXN0IGJhc2VQYXJ0czEgPSBiYXNlMS5zcGxpdCgnLicpOworICAgIGNvbnN0IFFTdHJp
bmdMaXN0IGJhc2VQYXJ0czIgPSBiYXNlMi5zcGxpdCgnLicpOworICAgIGZvciAoaW50IGkgPSAw
OyBpIDwgcU1heChiYXNlUGFydHMxLmNvdW50KCksIGJhc2VQYXJ0czIuY291bnQoKSk7IGkrKykg
eworICAgICAgICBxbG9uZ2xvbmcgYjEgPSBpIDwgYmFzZVBhcnRzMS5jb3VudCgpID8gYmFzZVBh
cnRzMVtpXS50b0xvbmdMb25nKCkgOiAwOworICAgICAgICBxbG9uZ2xvbmcgYjIgPSBpIDwgYmFz
ZVBhcnRzMi5jb3VudCgpID8gYmFzZVBhcnRzMltpXS50b0xvbmdMb25nKCkgOiAwOworICAgICAg
ICBpZiAoYjEgIT0gYjIpIHsKKyAgICAgICAgICAgIHJldHVybiBiMSA8IGIyID8gLTEgOiAxOwor
ICAgICAgICB9CisgICAgfQorCisgICAgLy8gRXF1YWwgYmFzZTogYSByZWxlYXNlIHdpdGggbm8g
cHJlcmVsZWFzZSBzdWZmaXggb3V0cmFua3MgYW55IHByZXJlbGVhc2UKKyAgICBpZiAocHJlMS5p
c0VtcHR5KCkgIT0gcHJlMi5pc0VtcHR5KCkpIHsKKyAgICAgICAgcmV0dXJuIHByZTEuaXNFbXB0
eSgpID8gMSA6IC0xOworICAgIH0KKyAgICBpZiAocHJlMS5pc0VtcHR5KCkpIHsKKyAgICAgICAg
cmV0dXJuIDA7CisgICAgfQorCisgICAgLy8gVHdvIHByZXJlbGVhc2VzOiBjb21wYXJlIGRvdC1z
ZXBhcmF0ZWQgaWRlbnRpZmllcnMgbGVmdCB0byByaWdodC4KKyAgICAvLyBOdW1lcmljIGlkZW50
aWZpZXJzIGNvbXBhcmUgbnVtZXJpY2FsbHkgKGxlYWRpbmcgemVyb3MgdG9sZXJhdGVkIOKAlCBv
dXIKKyAgICAvLyBDSSB6ZXJvLXBhZHMgY291bnRlcnMpLCBhbHBoYW51bWVyaWMgb25lcyBsZXhp
Y2FsbHkgaW4gQVNDSUkgb3JkZXIsIGFuZAorICAgIC8vIG51bWVyaWMgYWx3YXlzIHJhbmtzIGJl
bG93IGFscGhhbnVtZXJpYy4gVGhpcyBpcyB3aGF0IG9yZGVycworICAgIC8vICJhbHBoYSIgPCAi
YmV0YSIgPCAicmMiIGF0IGFuIGVxdWFsIGJhc2Ug4oCUIHRoZSBwcm9wZXJ0eSB0aGUgcHJldmlv
dXMKKyAgICAvLyBpbXBsZW1lbnRhdGlvbiBsYWNrZWQgKGl0IHNraXBwZWQgdGhlIHdvcmRzIGFu
ZCBjb21wYXJlZCBvbmx5IG51bWJlcnMsCisgICAgLy8gc28gMC4zLjAtYmV0YS4wMDggd3Jvbmds
eSBvdXRyYW5rZWQgMC4zLjAtcmMuMDAyKS4KKyAgICBjb25zdCBRU3RyaW5nTGlzdCBpZHMxID0g
cHJlMS5zcGxpdCgnLicpOworICAgIGNvbnN0IFFTdHJpbmdMaXN0IGlkczIgPSBwcmUyLnNwbGl0
KCcuJyk7CisgICAgZm9yIChpbnQgaSA9IDA7IGkgPCBxTWF4KGlkczEuY291bnQoKSwgaWRzMi5j
b3VudCgpKTsgaSsrKSB7CisgICAgICAgIGlmIChpID49IGlkczEuY291bnQoKSkgeworICAgICAg
ICAgICAgLy8gRXF1YWwgcHJlZml4LCBmZXdlciBmaWVsZHMgPSBsb3dlciBwcmVjZWRlbmNlICjC
pzExLjQuNCkKKyAgICAgICAgICAgIHJldHVybiAtMTsKKyAgICAgICAgfQorICAgICAgICBpZiAo
aSA+PSBpZHMyLmNvdW50KCkpIHsKKyAgICAgICAgICAgIHJldHVybiAxOworICAgICAgICB9Cisg
ICAgICAgIGJvb2wgbnVtMSA9IGlzTnVtZXJpY0lkZW50aWZpZXIoaWRzMVtpXSk7CisgICAgICAg
IGJvb2wgbnVtMiA9IGlzTnVtZXJpY0lkZW50aWZpZXIoaWRzMltpXSk7CisgICAgICAgIGlmIChu
dW0xICYmIG51bTIpIHsKKyAgICAgICAgICAgIHFsb25nbG9uZyBwMSA9IGlkczFbaV0udG9Mb25n
TG9uZygpOworICAgICAgICAgICAgcWxvbmdsb25nIHAyID0gaWRzMltpXS50b0xvbmdMb25nKCk7
CisgICAgICAgICAgICBpZiAocDEgIT0gcDIpIHsKKyAgICAgICAgICAgICAgICByZXR1cm4gcDEg
PCBwMiA/IC0xIDogMTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgICAgICBlbHNlIGlm
IChudW0xICE9IG51bTIpIHsKKyAgICAgICAgICAgIC8vIE51bWVyaWMgaWRlbnRpZmllcnMgcmFu
ayBiZWxvdyBhbHBoYW51bWVyaWMgb25lcyAowqcxMS40LjMpCisgICAgICAgICAgICByZXR1cm4g
bnVtMSA/IC0xIDogMTsKKyAgICAgICAgfQorICAgICAgICBlbHNlIHsKKyAgICAgICAgICAgIGlu
dCBjbXAgPSBRU3RyaW5nOjpjb21wYXJlKGlkczFbaV0sIGlkczJbaV0pOworICAgICAgICAgICAg
aWYgKGNtcCAhPSAwKSB7CisgICAgICAgICAgICAgICAgcmV0dXJuIGNtcCA8IDAgPyAtMSA6IDE7
CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgcmV0dXJuIDA7Cit9CisKK0F1
dG9VcGRhdGVDaGVja2VyOjpBdXRvVXBkYXRlQ2hlY2tlcihRT2JqZWN0KiBwYXJlbnQpIDoKKyAg
ICBRT2JqZWN0KHBhcmVudCksIG1fQ2hlY2tJbkZsaWdodChmYWxzZSksIG1fQ2hlY2tJc01hbnVh
bChmYWxzZSksCisgICAgbV9VcGRhdGVBdmFpbGFibGUoZmFsc2UpLCBtX09mZmVyQXZhaWxhYmxl
KGZhbHNlKSwgbV9JbnN0YWxsaW5nKGZhbHNlKQoreworICAgIGNsZWFyT2ZmZXIoKTsKKyAgICBz
ZXRTdGF0dXModHIoIiUxLiBVcGRhdGVzIGFyZSBtYW5hZ2VkIGJ5IEVjbGlwc2VPUy4gR2V0IHRo
ZSBtYXRjaGluZyBPUyBpbWFnZSBmcm9tICUyOyB1cHN0cmVhbSBWaWJlbWlzIHVwZGF0ZXMgYXJl
IGRpc2FibGVkLiIpLmFyZyhjdXJyZW50VmVyc2lvbigpLCBtX1JlbGVhc2VVcmwpKTsKK30KK1FT
dHJpbmcgQXV0b1VwZGF0ZUNoZWNrZXI6OmN1cnJlbnRWZXJzaW9uKCkgY29uc3QKK3sKKyAgICBy
ZXR1cm4gdHIoIkVjbGlwc2UgJTEgwrcgRWNsaXBzZU9TIGN1c3RvbWl6ZWQiKS5hcmcoUUNvcmVB
cHBsaWNhdGlvbjo6YXBwbGljYXRpb25WZXJzaW9uKCkpOworfQordm9pZCBBdXRvVXBkYXRlQ2hl
Y2tlcjo6Y2xlYXJPZmZlcigpCit7CisgICAgbV9VcGRhdGVBdmFpbGFibGUgPSBmYWxzZTsgbV9P
ZmZlckF2YWlsYWJsZSA9IGZhbHNlOworICAgIG1fT2ZmZXJWZXJzaW9uLmNsZWFyKCk7IG1fQXNz
ZXRVcmwuY2xlYXIoKTsgbV9PZmZlclRpZXIgPSAtMTsKKyAgICBtX1JlbGVhc2VVcmwgPSBRU3Ry
aW5nTGl0ZXJhbCgiaHR0cHM6Ly9naXRodWIuY29tL3RoM2QzY2szci9Nb29ubGlnaHQtT1MvcmVs
ZWFzZXMiKTsKK30KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6OnNldFN0YXR1cyhjb25zdCBRU3Ry
aW5nJiBtZXNzYWdlKQoreworICAgIGlmIChtX1N0YXR1c01lc3NhZ2UgIT0gbWVzc2FnZSkgeyBt
X1N0YXR1c01lc3NhZ2UgPSBtZXNzYWdlOyBlbWl0IHN0YXRlQ2hhbmdlZCgpOyB9Cit9Cit2b2lk
IEF1dG9VcGRhdGVDaGVja2VyOjpzdGFydCgpIHsgLyogTm8gdGltZXIgYW5kIG5vIGJhY2tncm91
bmQgdXBkYXRlIHJlcXVlc3RzLiAqLyB9Citib29sIEF1dG9VcGRhdGVDaGVja2VyOjpjYW5JbnN0
YWxsVXBkYXRlcygpIGNvbnN0IHsgcmV0dXJuIGZhbHNlOyB9Citib29sIEF1dG9VcGRhdGVDaGVj
a2VyOjpjYW5JbnN0YWxsKCkgY29uc3QgeyByZXR1cm4gZmFsc2U7IH0KK3ZvaWQgQXV0b1VwZGF0
ZUNoZWNrZXI6OmNoYW5uZWxDaGFuZ2VkKCkgeyBjaGVja05vdygpOyB9Cit2b2lkIEF1dG9VcGRh
dGVDaGVja2VyOjpjaGVja05vdygpCit7CisgICAgY2xlYXJPZmZlcigpOworICAgIHNldFN0YXR1
cyh0cigiVXBkYXRlcyBhcmUgbWFuYWdlZCBieSBFY2xpcHNlT1MuIERvd25sb2FkIHRoZSBtYXRj
aGluZyBPUyBpbWFnZSBmcm9tICUxLiBUaGlzIGNsaWVudCBuZXZlciBpbnN0YWxscyB1cHN0cmVh
bSBWaWJlbWlzIHJlbGVhc2VzLiIpLmFyZyhtX1JlbGVhc2VVcmwpKTsKKyAgICBlbWl0IHN0YXRl
Q2hhbmdlZCgpOyBlbWl0IGNoZWNrQ29tcGxldGVkKHRydWUsIGZhbHNlKTsKK30KK3ZvaWQgQXV0
b1VwZGF0ZUNoZWNrZXI6Omluc3RhbGwoKQoreworICAgIGNoZWNrTm93KCk7CisgICAgZW1pdCBp
bnN0YWxsRmFpbGVkKHRyKCJTdGFuZGFsb25lIFZpYmVtaXMgaW5zdGFsbGF0aW9uIGlzIGRpc2Fi
bGVkIGluIEVjbGlwc2VPUy4iKSwgbV9SZWxlYXNlVXJsKTsKK30KZGlmZiAtLWdpdCBhL2FwcC9t
b29ubGlnaHRvcy9vdmVybGF5c3R5bGUuaCBiL2FwcC9tb29ubGlnaHRvcy9vdmVybGF5c3R5bGUu
aApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi45MTFhNWMzCi0tLSAvZGV2L251
bGwKKysrIGIvYXBwL21vb25saWdodG9zL292ZXJsYXlzdHlsZS5oCkBAIC0wLDAgKzEsMjIgQEAK
KyNwcmFnbWEgb25jZQorI2luY2x1ZGUgPFFJbWFnZT4KKyNpbmNsdWRlIDxRUGFpbnRlcj4KKyNp
bmNsdWRlIDxRQ29sb3I+CisjaW5jbHVkZSA8UUxpbmVhckdyYWRpZW50PgorbmFtZXNwYWNlIEVj
bGlwc2VPdmVybGF5U3R5bGUgeworaW5saW5lIFFDb2xvciBhY2NlbnQoaW50IGluZGV4KSB7Cisg
ICAgY29uc3QgY2hhciogY29sb3JzW109eyIjMDBDQ0NDIiwiIzdDOENGOCIsIiMzRUQ1OTgiLCIj
RjBBODY4IiwiI0RDMzY1OCIsIiNGMjVENjQiLCIjRjU4MzQ3IiwiI0YxQkM0NSIsIiNCN0RDNjMi
LCIjNjNDQ0FFIiwiIzYzQzRFRCIsIiM2QzlGRkYiLCIjQUQ4NUY1IiwiI0U5NzZCQyIsIiNDQUQw
REEiLCIjRDk5NUFDIn07CisgICAgcmV0dXJuIFFDb2xvcihjb2xvcnNbcUJvdW5kKDAsaW5kZXgs
MTUpXSk7Cit9CitpbmxpbmUgUUltYWdlIHBhbmVsKFFTaXplIHNpemUsaW50IGFjY2VudEluZGV4
LGludCBvcGFjaXR5KSB7CisgICAgaWYoc2l6ZS53aWR0aCgpPDMyIHx8IHNpemUuaGVpZ2h0KCk8
MzIgfHwgc2l6ZS53aWR0aCgpPjIwNDggfHwgc2l6ZS5oZWlnaHQoKT40MDk2KSByZXR1cm4ge307
CisgICAgUUltYWdlIGltYWdlKHNpemUsUUltYWdlOjpGb3JtYXRfUkdCQTg4ODgpOyBpbWFnZS5m
aWxsKFF0Ojp0cmFuc3BhcmVudCk7CisgICAgUVBhaW50ZXIgcGFpbnRlcigmaW1hZ2UpOyBwYWlu
dGVyLnNldFJlbmRlckhpbnQoUVBhaW50ZXI6OkFudGlhbGlhc2luZyk7CisgICAgUUNvbG9yIGJn
KCIjMTUxMTE1Iik7IGJnLnNldEFscGhhKHFCb3VuZCg0MCxvcGFjaXR5LDEwMCkqMjU1LzEwMCk7
CisgICAgUUxpbmVhckdyYWRpZW50IGdsYXNzKDAsMCwwLHNpemUuaGVpZ2h0KCkpO1FDb2xvciBz
aGluZSgiIzI5MjQyQiIpO3NoaW5lLnNldEFscGhhKGJnLmFscGhhKCkpO2dsYXNzLnNldENvbG9y
QXQoMCxzaGluZSk7Z2xhc3Muc2V0Q29sb3JBdCgxLGJnKTsKKyAgICBwYWludGVyLnNldEJydXNo
KGdsYXNzKTsgcGFpbnRlci5zZXRQZW4oUVBlbihRQ29sb3IoMjU1LDI1NSwyNTUsNDgpLDEpKTsK
KyAgICBwYWludGVyLmRyYXdSb3VuZGVkUmVjdChRUmVjdEYoMSwxLGltYWdlLndpZHRoKCktMixp
bWFnZS5oZWlnaHQoKS0yKSwxOCwxOCk7CisgICAgcGFpbnRlci5zZXRQZW4oUVBlbihhY2NlbnQo
YWNjZW50SW5kZXgpLDMpKTsgcGFpbnRlci5kcmF3TGluZSgxNSw4LGltYWdlLndpZHRoKCktMTUs
OCk7CisgICAgcmV0dXJuIGltYWdlOworfQorfQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9z
L3N5c3RlbWNvbnRyb2xzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAK
bmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uM2VlM2ZmOQotLS0gL2Rldi9udWxs
CisrKyBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAKQEAgLTAsMCArMSw4MiBA
QAorI2luY2x1ZGUgInN5c3RlbWNvbnRyb2xzLmgiCisjaW5jbHVkZSA8UUNvcmVBcHBsaWNhdGlv
bj4KKyNpbmNsdWRlIDxRSnNvbkRvY3VtZW50PgorI2luY2x1ZGUgPFFKc29uT2JqZWN0PgorI2lu
Y2x1ZGUgPFFKc29uQXJyYXk+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNsdWRlIDxRRmls
ZUluZm8+CitTeXN0ZW1Db250cm9sczo6U3lzdGVtQ29udHJvbHMoUU9iamVjdCogcGFyZW50KSA6
IFFPYmplY3QocGFyZW50KSB7CisgICAgbV90aW1lb3V0LnNldFNpbmdsZVNob3QodHJ1ZSk7Cisg
ICAgY29ubmVjdCgmbV90aW1lb3V0LCAmUVRpbWVyOjp0aW1lb3V0LCB0aGlzLCBbdGhpc10geyBm
YWlsKHRyKCJPcGVyYXRpb24gdGltZWQgb3V0LiBSZXRyeSBvciB1c2UgdGhlIGRpYWdub3N0aWMg
c2hlbGwuIikpOyB9KTsKKyAgICBjb25uZWN0KCZtX3Byb2Nlc3MsICZRUHJvY2Vzczo6c3RhcnRl
ZCwgdGhpcywgW3RoaXNdIHsgcmVxdWVzdChtX21vZGUgKyAiLWxpc3QiKTsgfSk7CisgICAgY29u
bmVjdCgmbV9wcm9jZXNzLCAmUVByb2Nlc3M6OnJlYWR5UmVhZFN0YW5kYXJkRXJyb3IsIHRoaXMs
IFt0aGlzXSB7IG1fcHJvY2Vzcy5yZWFkQWxsU3RhbmRhcmRFcnJvcigpOyB9KTsKKyAgICBjb25u
ZWN0KCZtX3Byb2Nlc3MsICZRUHJvY2Vzczo6cmVhZHlSZWFkU3RhbmRhcmRPdXRwdXQsIHRoaXMs
IFt0aGlzXSB7CisgICAgICAgIG1fYnVmZmVyICs9IG1fcHJvY2Vzcy5yZWFkQWxsU3RhbmRhcmRP
dXRwdXQoKTsKKyAgICAgICAgaWYgKG1fYnVmZmVyLnNpemUoKSA+IDY1NTM2KSB7IGZhaWwodHIo
IkludmFsaWQgc3lzdGVtIHJlc3BvbnNlLiIpKTsgcmV0dXJuOyB9CisgICAgICAgIHdoaWxlICht
X2J1ZmZlci5jb250YWlucygnXG4nKSkgeworICAgICAgICAgICAgaW50IGVuZCA9IG1fYnVmZmVy
LmluZGV4T2YoJ1xuJyk7CisgICAgICAgICAgICBRSnNvblBhcnNlRXJyb3IgZXJyb3I7CisgICAg
ICAgICAgICBhdXRvIGRvY3VtZW50ID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24obV9idWZmZXIu
bGVmdChlbmQpLCAmZXJyb3IpOworICAgICAgICAgICAgbV9idWZmZXIucmVtb3ZlKDAsIGVuZCAr
IDEpOworICAgICAgICAgICAgaWYgKGVycm9yLmVycm9yICE9IFFKc29uUGFyc2VFcnJvcjo6Tm9F
cnJvciB8fCAhZG9jdW1lbnQuaXNPYmplY3QoKSkgeyBmYWlsKHRyKCJJbnZhbGlkIHN5c3RlbSBy
ZXNwb25zZS4iKSk7IHJldHVybjsgfQorICAgICAgICAgICAgYXV0byB2YWx1ZSA9IGRvY3VtZW50
Lm9iamVjdCgpOworICAgICAgICAgICAgaWYgKHZhbHVlLmNvbnRhaW5zKCJwcm9tcHQiKSkgewor
ICAgICAgICAgICAgICAgIG1fcHJvbXB0ID0gdmFsdWUudmFsdWUoInByb21wdCIpLnRvU3RyaW5n
KCkubGVmdCgxMDI0KTsKKyAgICAgICAgICAgICAgICBtX3RpbWVvdXQuc3RhcnQoMTIwMDAwKTsK
KyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGlmICh2YWx1ZS5jb250YWlucygiaXRlbXMiKSkg
eworICAgICAgICAgICAgICAgIGF1dG8gZW50cmllcyA9IHZhbHVlLnZhbHVlKCJpdGVtcyIpLnRv
QXJyYXkoKTsKKyAgICAgICAgICAgICAgICBpZiAoZW50cmllcy5zaXplKCkgPiA2NCkgeyBmYWls
KHRyKCJJbnZhbGlkIGRldmljZSBsaXN0LiIpKTsgcmV0dXJuOyB9CisgICAgICAgICAgICAgICAg
bV9pdGVtcyA9IGVudHJpZXMudG9WYXJpYW50TGlzdCgpOworICAgICAgICAgICAgfQorICAgICAg
ICAgICAgaWYgKHZhbHVlLnZhbHVlKCJzdGF0ZSIpLmlzT2JqZWN0KCkpIG1fc3RhdGUgPSB2YWx1
ZS52YWx1ZSgic3RhdGUiKS50b09iamVjdCgpLnRvVmFyaWFudE1hcCgpOworICAgICAgICAgICAg
aWYodmFsdWUuY29udGFpbnMoInN0YXR1cyIpKSBtX3N0YXR1cz12YWx1ZS52YWx1ZSgic3RhdHVz
IikudG9TdHJpbmcoKS5sZWZ0KDEwMjQpOworICAgICAgICAgICAgaWYodmFsdWUuY29udGFpbnMo
ImVycm9yIikpIG1fc3RhdHVzPXZhbHVlLnZhbHVlKCJlcnJvciIpLnRvU3RyaW5nKCkubGVmdCgx
MDI0KTsKKyAgICAgICAgICAgIGlmICh2YWx1ZS52YWx1ZSgiZG9uZSIpLnRvQm9vbCgpKSB7IG1f
dGltZW91dC5zdG9wKCk7IG1fYnVzeT1mYWxzZTsgbV9wcm9tcHQuY2xlYXIoKTsgfQorICAgICAg
ICAgICAgZW1pdCBjaGFuZ2VkKCk7CisgICAgICAgIH0KKyAgICB9KTsKKyAgICBjb25uZWN0KCZt
X3Byb2Nlc3MsICZRUHJvY2Vzczo6ZXJyb3JPY2N1cnJlZCwgdGhpcywgW3RoaXNdKFFQcm9jZXNz
OjpQcm9jZXNzRXJyb3IpIHsKKyAgICAgICAgaWYgKCFtX21vZGUuaXNFbXB0eSgpKSBmYWlsKHRy
KCJTeXN0ZW0gY29udHJvbHMgYXJlIHVuYXZhaWxhYmxlLiBVc2UgdGhlIGRpYWdub3N0aWMgc2hl
bGwuIikpOworICAgIH0pOworICAgIGNvbm5lY3QoJm1fcHJvY2VzcywgUU92ZXJsb2FkPGludCxR
UHJvY2Vzczo6RXhpdFN0YXR1cz46Om9mKCZRUHJvY2Vzczo6ZmluaXNoZWQpLCB0aGlzLCBbdGhp
c10oaW50LCBRUHJvY2Vzczo6RXhpdFN0YXR1cykgeworICAgICAgICBpZiAoIW1fbW9kZS5pc0Vt
cHR5KCkpIHsgbV90aW1lb3V0LnN0b3AoKTsgbV9idXN5ID0gZmFsc2U7IG1fcHJvbXB0LmNsZWFy
KCk7IG1fc3RhdHVzID0gdHIoIlN5c3RlbSBoZWxwZXIgc3RvcHBlZC4gQ2xvc2UgYW5kIHJlb3Bl
biB0aGlzIHBhbmVsLiIpOyBlbWl0IGNoYW5nZWQoKTsgfQorICAgIH0pOworfQorU3lzdGVtQ29u
dHJvbHM6On5TeXN0ZW1Db250cm9scygpIHsgY2xvc2UoKTsgaWYgKCFtX3Byb2Nlc3Mud2FpdEZv
ckZpbmlzaGVkKDUwMCkpIHsgbV9wcm9jZXNzLmtpbGwoKTsgbV9wcm9jZXNzLndhaXRGb3JGaW5p
c2hlZCg1MDApOyB9IH0KK3ZvaWQgU3lzdGVtQ29udHJvbHM6OnNlbmQoY29uc3QgUUpzb25PYmpl
Y3QmIHZhbHVlKSB7IG1fcHJvY2Vzcy53cml0ZShRSnNvbkRvY3VtZW50KHZhbHVlKS50b0pzb24o
UUpzb25Eb2N1bWVudDo6Q29tcGFjdCkgKyAnXG4nKTsgfQordm9pZCBTeXN0ZW1Db250cm9sczo6
b3BlbihRU3RyaW5nIG1vZGUpIHsKKyAgICBpZiAobW9kZSAhPSAid2lmaSIgJiYgbW9kZSAhPSAi
YnQiICYmIG1vZGUgIT0gImNlbnRlciIpIHJldHVybjsKKyAgICBjbG9zZSgpOworICAgIGlmICht
X3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgeyBtX3Byb2Nlc3Mua2ls
bCgpOyBtX3Byb2Nlc3Mud2FpdEZvckZpbmlzaGVkKDUwMCk7IH0KKyAgICBtX21vZGUgPSBtb2Rl
OyBtX2l0ZW1zLmNsZWFyKCk7IG1fc3RhdGUuY2xlYXIoKTsgbV9idWZmZXIuY2xlYXIoKTsgbV9z
dGF0dXMgPSB0cigiTG9hZGluZ+KApiIpOyBlbWl0IGNoYW5nZWQoKTsKKyAgICBRU3RyaW5nIGhl
bHBlciA9ICIvdXNyL2xvY2FsL2xpYmV4ZWMvbW9vbmxpZ2h0LW9zL3N5c3RlbS1jb250cm9scy5w
eSI7CisjaWZkZWYgTU9PTkxJR0hUX0NPTlRST0xTX1RFU1QKKyAgICBoZWxwZXIgPSBxRW52aXJv
bm1lbnRWYXJpYWJsZSgiTU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUiLCBoZWxwZXIpOworI2Vu
ZGlmCisgICAgbV9wcm9jZXNzLnN0YXJ0KCJweXRob24zIiwge2hlbHBlcn0pOworfQordm9pZCBT
eXN0ZW1Db250cm9sczo6cmVxdWVzdChRU3RyaW5nIGFjdGlvbiwgUVN0cmluZyBpZCwgYm9vbCBj
b25maXJtKSB7CisgICAgaWYgKG1fYnVzeSB8fCBtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vz
czo6UnVubmluZyB8fCAhYWN0aW9uLnN0YXJ0c1dpdGgobV9tb2RlICsgIi0iKSkgcmV0dXJuOwor
ICAgIGNvbnN0IFFTdHJpbmdMaXN0IGFsbG93ZWQgPSB7IndpZmktbGlzdCIsICJ3aWZpLXNjYW4i
LCAid2lmaS1jb25uZWN0IiwgIndpZmktZGlzY29ubmVjdCIsICJidC1saXN0IiwgImJ0LXNjYW4i
LCAiYnQtY29ubmVjdCIsICJidC1kaXNjb25uZWN0IiwgImJ0LWZvcmdldCIsICJjZW50ZXItd2lm
aS1yYWRpbyIsICJjZW50ZXItYnQtcmFkaW8iLCAiY2VudGVyLWFpcnBvZHMiLCAiY2VudGVyLXRl
c3Qtc291bmQiLCAiY2VudGVyLWlkbGUiLCAiY2VudGVyLXBvaW50ZXItc3BlZWQiLCAiY2VudGVy
LXBvaW50ZXItbmF0dXJhbCIsICJjZW50ZXItcG9pbnRlci10YXAiLCAiY2VudGVyLWRpc3BsYXki
LCAiY2VudGVyLWZyb250ZW5kIiwgImNlbnRlci1yZXN0YXJ0LWZyb250ZW5kIiwgImNlbnRlci1s
aXN0IiwgImNlbnRlci12b2x1bWUiLCAiY2VudGVyLW11dGUiLCAiY2VudGVyLW91dHB1dCIsICJj
ZW50ZXItc2NyZWVuIiwgImNlbnRlci1rZXlib2FyZCIsICJjZW50ZXItcmVib290IiwgImNlbnRl
ci1wb3dlcm9mZiIsICJjZW50ZXItc3VzcGVuZCIsICJjZW50ZXItcmVwb3J0In07CisgICAgaWYg
KCFhbGxvd2VkLmNvbnRhaW5zKGFjdGlvbikpIHJldHVybjsKKyAgICBtX2J1c3kgPSB0cnVlOyBt
X3Byb21wdC5jbGVhcigpOyBtX3N0YXR1cyA9IGFjdGlvbi5lbmRzV2l0aCgic2NhbiIpID8gdHIo
IlN0YXJ0aW5nIHNjYW7igKYiKSA6IHRyKCJXb3JraW5n4oCmIik7IG1fdGltZW91dC5zdGFydChh
Y3Rpb24uZW5kc1dpdGgoInNjYW4iKSA/IDMwMDAwIDogMTAwMDAwKTsKKyAgICBzZW5kKHt7ImFj
dGlvbiIsIGFjdGlvbn0sIHsiaWQiLCBpZH0sIHsiY29uZmlybSIsIGNvbmZpcm19fSk7IGVtaXQg
Y2hhbmdlZCgpOworfQordm9pZCBTeXN0ZW1Db250cm9sczo6YW5zd2VyKFFTdHJpbmcgdmFsdWUp
IHsKKyAgICBpZiAoIW1fYnVzeSB8fCBtX3Byb21wdC5pc0VtcHR5KCkgfHwgdmFsdWUuc2l6ZSgp
ID4gNDA5NiB8fCB2YWx1ZS5jb250YWlucygnXG4nKSB8fCB2YWx1ZS5jb250YWlucygnXHInKSB8
fCB2YWx1ZS5jb250YWlucyhRQ2hhcigwKSkpIHJldHVybjsKKyAgICBzZW5kKHt7ImFjdGlvbiIs
ICJhbnN3ZXIifSwgeyJ2YWx1ZSIsIHZhbHVlfX0pOyBtX3Byb21wdC5jbGVhcigpOyBtX3RpbWVv
dXQuc3RhcnQoMTIwMDAwKTsgZW1pdCBjaGFuZ2VkKCk7Cit9Cit2b2lkIFN5c3RlbUNvbnRyb2xz
OjpjbG9zZSgpIHsKKyAgICBtX21vZGUuY2xlYXIoKTsgbV90aW1lb3V0LnN0b3AoKTsgbV9idXN5
ID0gZmFsc2U7IG1fcHJvbXB0LmNsZWFyKCk7IG1fYnVmZmVyLmNsZWFyKCk7CisgICAgaWYgKG1f
cHJvY2Vzcy5zdGF0ZSgpICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSB7CisgICAgICAgIG1fcHJv
Y2Vzcy50ZXJtaW5hdGUoKTsKKyAgICAgICAgUVRpbWVyOjpzaW5nbGVTaG90KDQwMDAsIHRoaXMs
IFt0aGlzXSB7IGlmIChtX21vZGUuaXNFbXB0eSgpICYmIG1fcHJvY2Vzcy5zdGF0ZSgpICE9IFFQ
cm9jZXNzOjpOb3RSdW5uaW5nKSBtX3Byb2Nlc3Mua2lsbCgpOyB9KTsKKyAgICB9CisgICAgZW1p
dCBjaGFuZ2VkKCk7Cit9Cit2b2lkIFN5c3RlbUNvbnRyb2xzOjpmYWlsKFFTdHJpbmcgbWVzc2Fn
ZSkgeyBjbG9zZSgpOyBtX3N0YXR1cyA9IG1lc3NhZ2U7IGVtaXQgY2hhbmdlZCgpOyB9CitzdGF0
aWMgdm9pZCByZWdpc3RlclN5c3RlbUNvbnRyb2xzKCkgeworICAgIHFtbFJlZ2lzdGVyU2luZ2xl
dG9uVHlwZTxTeXN0ZW1Db250cm9scz4oIlN5c3RlbUNvbnRyb2xzIiwgMSwgMCwgIlN5c3RlbUNv
bnRyb2xzIiwgW10oUVFtbEVuZ2luZSosIFFKU0VuZ2luZSopIC0+IFFPYmplY3QqIHsgcmV0dXJu
IG5ldyBTeXN0ZW1Db250cm9scygpOyB9KTsKK30KK1FfQ09SRUFQUF9TVEFSVFVQX0ZVTkNUSU9O
KHJlZ2lzdGVyU3lzdGVtQ29udHJvbHMpCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3Mvc3lz
dGVtY29udHJvbHMuaCBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5oCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjE4ZTlkZWIKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuaApAQCAtMCwwICsxLDM5IEBACisjcHJhZ21h
IG9uY2UKKyNpbmNsdWRlIDxRT2JqZWN0PgorI2luY2x1ZGUgPFFKc29uT2JqZWN0PgorI2luY2x1
ZGUgPFFQcm9jZXNzPgorI2luY2x1ZGUgPFFUaW1lcj4KKyNpbmNsdWRlIDxRVmFyaWFudExpc3Q+
CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CitjbGFzcyBTeXN0ZW1Db250cm9scyA6IHB1YmxpYyBR
T2JqZWN0IHsKKyAgICBRX09CSkVDVAorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgc3RhdGUg
UkVBRCBzdGF0ZSBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFWYXJpYW50TGlzdCBp
dGVtcyBSRUFEIGl0ZW1zIE5PVElGWSBjaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBz
dGF0dXMgUkVBRCBzdGF0dXMgTk9USUZZIGNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShRU3RyaW5n
IHByb21wdCBSRUFEIHByb21wdCBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wg
YnVzeSBSRUFEIGJ1c3kgTk9USUZZIGNoYW5nZWQpCitwdWJsaWM6CisgICAgZXhwbGljaXQgU3lz
dGVtQ29udHJvbHMoUU9iamVjdCogcGFyZW50ID0gbnVsbHB0cik7CisgICAgflN5c3RlbUNvbnRy
b2xzKCk7CisgICAgUVZhcmlhbnRNYXAgc3RhdGUoKSBjb25zdCB7IHJldHVybiBtX3N0YXRlOyB9
CisgICAgUVZhcmlhbnRMaXN0IGl0ZW1zKCkgY29uc3QgeyByZXR1cm4gbV9pdGVtczsgfQorICAg
IFFTdHJpbmcgc3RhdHVzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0dXM7IH0KKyAgICBRU3RyaW5n
IHByb21wdCgpIGNvbnN0IHsgcmV0dXJuIG1fcHJvbXB0OyB9CisgICAgYm9vbCBidXN5KCkgY29u
c3QgeyByZXR1cm4gbV9idXN5OyB9CisgICAgUV9JTlZPS0FCTEUgdm9pZCBvcGVuKFFTdHJpbmcg
bW9kZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCByZXF1ZXN0KFFTdHJpbmcgYWN0aW9uLCBRU3Ry
aW5nIGlkID0gUVN0cmluZygpLCBib29sIGNvbmZpcm0gPSBmYWxzZSk7CisgICAgUV9JTlZPS0FC
TEUgdm9pZCBhbnN3ZXIoUVN0cmluZyB2YWx1ZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCBjbG9z
ZSgpOworc2lnbmFsczoKKyAgICB2b2lkIGNoYW5nZWQoKTsKK3ByaXZhdGU6CisgICAgdm9pZCBz
ZW5kKGNvbnN0IFFKc29uT2JqZWN0JiB2YWx1ZSk7CisgICAgdm9pZCBmYWlsKFFTdHJpbmcgbWVz
c2FnZSk7CisgICAgUVByb2Nlc3MgbV9wcm9jZXNzOworICAgIFFUaW1lciBtX3RpbWVvdXQ7Cisg
ICAgUUJ5dGVBcnJheSBtX2J1ZmZlcjsKKyAgICBRVmFyaWFudExpc3QgbV9pdGVtczsKKyAgICBR
VmFyaWFudE1hcCBtX3N0YXRlOworICAgIFFTdHJpbmcgbV9tb2RlLCBtX3N0YXR1cywgbV9wcm9t
cHQ7CisgICAgYm9vbCBtX2J1c3kgPSBmYWxzZTsKK307CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxp
Z2h0b3MvdGVzdHMvSGFybmVzcy5xbWwgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvSGFybmVzcy5x
bWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uYjcxOTc2MwotLS0gL2Rldi9u
dWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbApAQCAtMCwwICsxLDY0
IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1w
b3J0IFF0UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2ln
biAxLjAKK2ltcG9ydCBTdHJlYW1pbmdQcmVmZXJlbmNlcyAxLjAKK2ltcG9ydCBFY2xpcHNlUHJv
ZmlsZXMgMS4wCitpbXBvcnQgIi4uLy4uL2d1aSIKK0FwcGxpY2F0aW9uV2luZG93IHsKKyAgICBN
YXRlcmlhbC50aGVtZTogTWF0ZXJpYWwuRGFyaworICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tl
bnMuYWNjZW50CisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdXaW5kb3cKKyAg
ICBNYXRlcmlhbC5mb3JlZ3JvdW5kOiBWYlRva2Vucy50ZXh0CisgICAgY29sb3I6IFZiVG9rZW5z
LmJnQXBwCisgICAgd2lkdGg6IDEyODA7IGhlaWdodDogODAwOyB2aXNpYmxlOiB0cnVlCisgICAg
ZnVuY3Rpb24gY2hvb3NlU2NhbGUodmFsdWUpIHsgRWNsaXBzZVByb2ZpbGVzLnRleHRTY2FsZT12
YWx1ZSB9CisgICAgZnVuY3Rpb24gY2hvb3NlQWNjZW50KGkpIHsgU3RyZWFtaW5nUHJlZmVyZW5j
ZXMudWlBY2NlbnRJbmRleCA9IGkgfQorICAgIGZ1bmN0aW9uIGNob29zZUFjY2Vzc2liaWxpdHko
Y29udHJhc3QsbW90aW9uKSB7IEVjbGlwc2VQcm9maWxlcy5oaWdoQ29udHJhc3Q9Y29udHJhc3Q7
RWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb249bW90aW9uIH0KKyAgICBmdW5jdGlvbiBjaG9v
c2VXYWxscGFwZXIodXJsKSB7IHJldHVybiBFY2xpcHNlUHJvZmlsZXMuY2hvb3NlQmFja2dyb3Vu
ZCh1cmwpIH0KKyAgICBmdW5jdGlvbiByZXNldFdhbGxwYXBlcigpIHsgRWNsaXBzZVByb2ZpbGVz
LnJlc2V0QmFja2dyb3VuZCgpIH0KKyAgICBmdW5jdGlvbiBjaG9vc2VEaW1taW5nKHZhbHVlKSB7
IEVjbGlwc2VQcm9maWxlcy5iYWNrZ3JvdW5kRGltPXZhbHVlIH0KKyAgICBDcmltc29uR2xhc3NC
YWNrZHJvcCB7YW5jaG9ycy5maWxsOnBhcmVudH0KKyAgICBCdXR0b24ge2lkOnNldHRpbmdzQnV0
dG9uO3Zpc2libGU6ZmFsc2V9CisgICAgQnV0dG9uIHtpZDplY2xpcHNlQ2VudGVyQnV0dG9uO3Zp
c2libGU6ZmFsc2V9CisgICAgUXRPYmplY3Qge2lkOmNyaW1zb25QYW5lbDtwcm9wZXJ0eSBzdHJp
bmcga2luZDoiIjtmdW5jdGlvbiBvcGVuKCl7fX0KKyAgICBRdE9iamVjdCB7aWQ6YWRkUGNEaWFs
b2c7ZnVuY3Rpb24gb3Blbigpe319CisgICAgUXRPYmplY3Qge2lkOnF1aWNrTWVudU1hbmFnZXI7
cHJvcGVydHkgdmFyIHNlcnZlckNvbW1hbmRNYW5hZ2VyOm51bGw7ZnVuY3Rpb24gaGlkZSgpe30g
ZnVuY3Rpb24gZXhlY3V0ZUFjdGlvbihhY3Rpb24pe30gZnVuY3Rpb24gc2V0VGV4dElucHV0QWN0
aXZlKGFjdGl2ZSl7fSB9CisgICAgTG9hZGVyIHtvYmplY3ROYW1lOiJxdWlja01lbnVMb2FkZXIi
O2FjdGl2ZTpmYWxzZTthbmNob3JzLmNlbnRlckluOnBhcmVudDtzb3VyY2VDb21wb25lbnQ6UXVp
Y2tNZW51IHt9fQorICAgIFN0YWNrVmlldyB7IGlkOnN0YWNrVmlldztvYmplY3ROYW1lOiJwcm9k
dWN0aW9uU3RhY2siO2FuY2hvcnMuZmlsbDpwYXJlbnQ7dmlzaWJsZTpmYWxzZSB9CisgICAgZnVu
Y3Rpb24gc2hvd1Byb2R1Y3Rpb25WaWV3KHZpZXcpIHsKKyAgICAgICAgc3RhY2tWaWV3LnZpc2li
bGU9dHJ1ZTtzdGFja1ZpZXcuY2xlYXIoKQorICAgICAgICB2YXIgcHJvcHM9dmlldz09PSJBcHBW
aWV3Ij97Y29tcHV0ZXJJbmRleDowLG9iamVjdE5hbWU6IkdhbWluZyBQQyIsaG9zdFR5cGU6IlZJ
QkVQT0xMTyIsaG9zdFRyYW5zcG9ydDoiTEFOIixob3N0T25saW5lOnRydWUsc2hvd0dhbWVzOnRy
dWV9Ont9CisgICAgICAgIHN0YWNrVmlldy5wdXNoKFF0LnJlc29sdmVkVXJsKCIuLi8uLi9ndWkv
Iit2aWV3KyIucW1sIikscHJvcHMpCisgICAgfQorICAgIGZ1bmN0aW9uIGhpZGVQcm9kdWN0aW9u
Vmlldygpe3N0YWNrVmlldy5jbGVhcigpO3N0YWNrVmlldy52aXNpYmxlPWZhbHNlfQorICAgIFF0
T2JqZWN0IHsgb2JqZWN0TmFtZTogInRlc3RTdGF0ZSI7IHByb3BlcnR5IGNvbG9yIGFjY2VudDog
VmJUb2tlbnMuYWNjZW50OyBwcm9wZXJ0eSBjb2xvciBwcmVzc2VkOiBWYlRva2Vucy5hY2NlbnRQ
cmVzc2VkIH0KKyAgICBDcmltc29uU3RhdHVzRGlhbG9nIHsgb2JqZWN0TmFtZTogInRlc3RQYW5l
bCIgfQorICAgIFN5c3RlbUNvbm5lY3Rpb25zRGlhbG9nIHsgb2JqZWN0TmFtZTogImNvbm5lY3Rp
b25zUGFuZWwiIH0KKyAgICBFY2xpcHNlQ29udHJvbENlbnRlciB7IG9iamVjdE5hbWU6ICJjb250
cm9sQ2VudGVyIiB9CisgICAgU2Nyb2xsVmlldyB7IGlkOnN5c3RlbVNjcm9sbDsgb2JqZWN0TmFt
ZToic3lzdGVtU2Nyb2xsIjtjb250ZW50V2lkdGg6YXZhaWxhYmxlV2lkdGg7IGFuY2hvcnMuZmls
bDpwYXJlbnQ7IGFuY2hvcnMubWFyZ2luczoyNDsgdmlzaWJsZTpzeXN0ZW1QYW5lbC5hY3RpdmUK
KyAgICAgICAgRWNsaXBzZVN5c3RlbVNldHRpbmdzIHsgaWQ6c3lzdGVtUGFuZWw7b2JqZWN0TmFt
ZToic3lzdGVtU2V0dGluZ3MiO3dpZHRoOnN5c3RlbVNjcm9sbC5hdmFpbGFibGVXaWR0aDthY3Rp
dmU6ZmFsc2UgfQorICAgIH0KKyAgICBDcmltc29uQmFja2dyb3VuZFBpY2tlciB7b2JqZWN0TmFt
ZToiZ2xhc3NCYWNrZ3JvdW5kUGlja2VyIn0KKyAgICBJdGVtIHsKKyAgICAgICAgaWQ6ZGFzaGJv
YXJkO29iamVjdE5hbWU6ImdsYXNzRGFzaGJvYXJkIjthbmNob3JzLmZpbGw6cGFyZW50O3Zpc2li
bGU6ZmFsc2UKKyAgICAgICAgQ3JpbXNvbkdsYXNzQmFja2Ryb3Age2FuY2hvcnMuZmlsbDpwYXJl
bnR9CisgICAgICAgIENyaW1zb25HbGFzc1JhaWwge3g6MTY7eToxNjt3aWR0aDo2NDtoZWlnaHQ6
cGFyZW50LmhlaWdodC0zMn0KKyAgICAgICAgQ3JpbXNvbkhvc3RQYW5lbCB7b2JqZWN0TmFtZToi
Z2xhc3NIb3N0Ijt4Ojk2O3k6MTY7d2lkdGg6cGFyZW50LndpZHRoPj0xNTgwPzI2MDowO2hlaWdo
dDpwYXJlbnQuaGVpZ2h0LTMyO3Zpc2libGU6d2lkdGg+MDtob3N0TmFtZToiR2FtaW5nIFBDIjto
b3N0VHlwZToiVmliZXBvbGxvIjt0cmFuc3BvcnQ6IkxBTiI7b25saW5lOnRydWV9CisgICAgICAg
IENyaW1zb25Mb2NhbFBhbmVsIHthY3RpdmU6ZGFzaGJvYXJkLnZpc2libGU7eDpwYXJlbnQud2lk
dGgtd2lkdGgtMTY7eToxNjt3aWR0aDpNYXRoLnJvdW5kKDI1MipWYlRva2Vucy50ZXh0U2NhbGUp
O2hlaWdodDpwYXJlbnQuaGVpZ2h0LTMyO3Zpc2libGU6cGFyZW50LndpZHRoPj0xMjQwfQorICAg
ICAgICBDb2x1bW4geworICAgICAgICAgICAgeDpwYXJlbnQud2lkdGg+PTE1ODA/Mzc2OjEwNDt5
OjI0O3dpZHRoOnBhcmVudC53aWR0aC14LShwYXJlbnQud2lkdGg+PTEyNDA/TWF0aC5yb3VuZCgy
NTIqVmJUb2tlbnMudGV4dFNjYWxlKSs0MDoyNCk7c3BhY2luZzoxNgorICAgICAgICAgICAgTGFi
ZWwge3RleHQ6IkNyaW1zb24gR2xhc3Mg4oCiIExpYnJhcnkiO2ZvbnQucGl4ZWxTaXplOlZiVG9r
ZW5zLnR5cGVUaXRsZTtjb2xvcjpWYlRva2Vucy50ZXh0fQorICAgICAgICAgICAgTGFiZWwge3Rl
eHQ6IlVJIHZlcmlmaWNhdGlvbiBmaXh0dXJlIOKAoiBpbGx1c3RyYXRpdmUgaG9zdCBhbmQgYXBw
IGRhdGEiO2ZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVMYWJlbDtjb2xvcjpWYlRva2Vucy50
ZXh0RGltO3dpZHRoOnBhcmVudC53aWR0aDt3cmFwTW9kZTpUZXh0LldyYXB9CisgICAgICAgICAg
ICBGbG93IHt3aWR0aDpwYXJlbnQud2lkdGg7c3BhY2luZzoxNgorICAgICAgICAgICAgICAgIFJl
cGVhdGVyIHttb2RlbDpbIkRlc2t0b3AiLCJTdGVhbSBCaWcgUGljdHVyZSIsIkdhbWUgbGlicmFy
eSIsIk1lZGlhIl0KKyAgICAgICAgICAgICAgICAgICAgZGVsZWdhdGU6VmJDYXJkIHt3aWR0aDpN
YXRoLm1heCgxODAsTWF0aC5taW4oMjUwLChwYXJlbnQud2lkdGgtMzIpLzIpKTtoZWlnaHQ6MjIw
CisgICAgICAgICAgICAgICAgICAgICAgICBJbWFnZSB7YW5jaG9ycy5jZW50ZXJJbjpwYXJlbnQ7
d2lkdGg6NjQ7aGVpZ2h0OjY0O3NvdXJjZToicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyJ9Cisg
ICAgICAgICAgICAgICAgICAgICAgICBMYWJlbCB7YW5jaG9ycy5ib3R0b206cGFyZW50LmJvdHRv
bTthbmNob3JzLmJvdHRvbU1hcmdpbjoyMDthbmNob3JzLmhvcml6b250YWxDZW50ZXI6cGFyZW50
Lmhvcml6b250YWxDZW50ZXI7dGV4dDptb2RlbERhdGE7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250
LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keX0KKyAgICAgICAgICAgICAgICAgICAgfQorICAg
ICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBFY2xp
cHNlQWJvdXREaWFsb2cgeyBvYmplY3ROYW1lOiAiYWJvdXRFY2xpcHNlIiB9Cit9CmRpZmYgLS1n
aXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sIGIvYXBwL21vb25saWdo
dG9zL3Rlc3RzL1ByZWZlcmVuY2VzLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAw
MDAwLi4wM2FkYzY4Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL1By
ZWZlcmVuY2VzLnFtbApAQCAtMCwwICsxLDMgQEAKK3ByYWdtYSBTaW5nbGV0b24KK2ltcG9ydCBR
dFF1aWNrIDIuOQorUXRPYmplY3QgeyBwcm9wZXJ0eSBpbnQgdWlBY2NlbnRJbmRleDogNDsgcHJv
cGVydHkgYm9vbCBlbmFibGVNZG5zOnRydWU7IHByb3BlcnR5IGJvb2wgdWlTaG93SGludHM6IHRy
dWU7IHByb3BlcnR5IGludCB3aWR0aDogMTkyMDsgcHJvcGVydHkgaW50IGhlaWdodDogMTA4MDsg
cHJvcGVydHkgaW50IGZwczogNjA7IHByb3BlcnR5IGludCBiaXRyYXRlS2JwczogMjAwMDA7IGZ1
bmN0aW9uIHNhdmUoKSB7fSB9CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvVWlT
ZXJ2aWNlcy5xbWwgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvVWlTZXJ2aWNlcy5xbWwKbmV3IGZp
bGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMGMzZjk2NAotLS0gL2Rldi9udWxsCisrKyBi
L2FwcC9tb29ubGlnaHRvcy90ZXN0cy9VaVNlcnZpY2VzLnFtbApAQCAtMCwwICsxLDE3IEBACitw
cmFnbWEgU2luZ2xldG9uCitpbXBvcnQgUXRRdWljayAyLjkKK1F0T2JqZWN0IHsKKyAgICBwcm9w
ZXJ0eSBib29sIGhhc0Jyb3dzZXI6IGZhbHNlCisgICAgcHJvcGVydHkgc3RyaW5nIHZlcnNpb25T
dHJpbmc6ICJVSSBmaXh0dXJlIgorICAgIHNpZ25hbCBvdHBTdGFnZTFDb21wbGV0ZWQoc3RyaW5n
IHBpbixzdHJpbmcgZXJyb3IpCisgICAgc2lnbmFsIGNvbXB1dGVyQWRkQ29tcGxldGVkKGJvb2wg
c3VjY2Vzcyxib29sIGJsb2NrZWQpCisgICAgZnVuY3Rpb24gZ2V0Q29ubmVjdGVkR2FtZXBhZHMo
KXtyZXR1cm4gMH0KKyAgICBmdW5jdGlvbiBhY3RpdmF0ZWQoKXt9CisgICAgZnVuY3Rpb24gZm9j
dXNNb3ZlZCgpe30KKyAgICBmdW5jdGlvbiBiYWNrKCl7fQorICAgIGZ1bmN0aW9uIHN0YXJ0UG9s
bGluZygpe30KKyAgICBmdW5jdGlvbiBzdG9wUG9sbGluZygpe30KKyAgICBmdW5jdGlvbiBvcGVu
VXJsKHVybCl7fQorICAgIGZ1bmN0aW9uIGhhc1Byb2ZpbGUoaG9zdCxhcHApe3JldHVybiBmYWxz
ZX0KKyAgICBmdW5jdGlvbiBwcm9maWxlU3VtbWFyeShob3N0LGFwcCl7cmV0dXJuICIifQorfQpk
aWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAgYi9hcHAv
bW9vbmxpZ2h0b3MvdGVzdHMvdGVzdC1jcmltc29uLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NApp
bmRleCAwMDAwMDAwLi44NzYzODdiCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9z
L3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAKQEAgLTAsMCArMSw0OTEgQEAKKyNpbmNsdWRlIDxRdFRl
c3Q+CisjaW5jbHVkZSA8UVRlbXBvcmFyeURpcj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2lu
Y2x1ZGUgPFFRbWxDb21wb25lbnQ+CisjaW5jbHVkZSA8UVFtbENvbnRleHQ+CisjaW5jbHVkZSA8
UVF1aWNrU3R5bGU+CisjaW5jbHVkZSA8UVF1aWNrV2luZG93PgorI2luY2x1ZGUgPFFRdWlja0l0
ZW0+CisjaW5jbHVkZSA8UUZpbGU+CisjaW5jbHVkZSA8UUltYWdlUmVhZGVyPgorI2luY2x1ZGUg
PFFUY3BTZXJ2ZXI+CisjaW5jbHVkZSA8UVNzbFNvY2tldD4KKyNpbmNsdWRlIDxRU3NsS2V5Pgor
I2luY2x1ZGUgPFFTc2xDZXJ0aWZpY2F0ZT4KKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+
CisjaW5jbHVkZSA8bWVtb3J5PgorI2luY2x1ZGUgPFFTdGFuZGFyZFBhdGhzPgorI2luY2x1ZGUg
PFFEaXI+CisjaW5jbHVkZSA8UUZpbGVJbmZvPgorI2luY2x1ZGUgPFFNZXRhUHJvcGVydHk+Cisj
aW5jbHVkZSAiLi4vY3JpbXNvbnN0YXR1cy5oIgorI2luY2x1ZGUgIi4uL3N5c3RlbWNvbnRyb2xz
LmgiCisjaW5jbHVkZSAiLi4vZWNsaXBzZXByb2ZpbGVzLmgiCisjaW5jbHVkZSAiLi4vbG9jYWxo
YXJkd2FyZS5oIgorI2luY2x1ZGUgIi4uL292ZXJsYXlzdHlsZS5oIgorI2luY2x1ZGUgIi4uL2Ny
aW1zb25ncmFwaHMuaCIKKyNpbmNsdWRlICJ1aW1vZGVscy5oIgorI2luY2x1ZGUgIi4uLy4uL2Jh
Y2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaCIKKworY2xhc3MgVGxzRml4dHVyZSA6IHB1YmxpYyBR
VGNwU2VydmVyIHsKK3B1YmxpYzoKKyAgICBRQnl0ZUFycmF5IGJvZHkgPSBSIih7ImNwdV9wZXJj
ZW50IjozNy41LCJyYW1fdXNlZF9ieXRlcyI6NTAsInJhbV90b3RhbF9ieXRlcyI6MTAwfSkiOwor
ICAgIGludCBjb2RlID0gMjAwLCByZXF1ZXN0cyA9IDA7CisgICAgYm9vbCByZXNwb25kID0gdHJ1
ZTsKKyAgICBRQnl0ZUFycmF5IGF1dGhvcml6YXRpb247CisgICAgUVNzbENlcnRpZmljYXRlIGNl
cnQ7CisgICAgUVNzbEtleSBrZXk7CisgICAgVGxzRml4dHVyZSgpIHsKKyAgICAgICAgUUZpbGUg
YyhxRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9URVNUX0NFUlQiKSk7IGMub3BlbihRSU9E
ZXZpY2U6OlJlYWRPbmx5KTsgY2VydCA9IFFTc2xDZXJ0aWZpY2F0ZShjLnJlYWRBbGwoKSk7Cisg
ICAgICAgIFFGaWxlIGsocUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fVEVTVF9LRVkiKSk7
IGsub3BlbihRSU9EZXZpY2U6OlJlYWRPbmx5KTsga2V5ID0gUVNzbEtleShrLnJlYWRBbGwoKSwg
UVNzbDo6UnNhKTsKKyAgICAgICAgbGlzdGVuKFFIb3N0QWRkcmVzczo6TG9jYWxIb3N0KTsKKyAg
ICB9CisgICAgdm9pZCBpbmNvbWluZ0Nvbm5lY3Rpb24ocWludHB0ciBkZXNjcmlwdG9yKSBvdmVy
cmlkZSB7CisgICAgICAgIGF1dG8gc29ja2V0ID0gbmV3IFFTc2xTb2NrZXQodGhpcyk7CisgICAg
ICAgIHNvY2tldC0+c2V0TG9jYWxDZXJ0aWZpY2F0ZShjZXJ0KTsgc29ja2V0LT5zZXRQcml2YXRl
S2V5KGtleSk7IHNvY2tldC0+c2V0UGVlclZlcmlmeU1vZGUoUVNzbFNvY2tldDo6VmVyaWZ5Tm9u
ZSk7CisgICAgICAgIHNvY2tldC0+c2V0U29ja2V0RGVzY3JpcHRvcihkZXNjcmlwdG9yKTsKKyAg
ICAgICAgYXV0byBpbnB1dCA9IHN0ZDo6bWFrZV9zaGFyZWQ8UUJ5dGVBcnJheT4oKTsKKyAgICAg
ICAgY29ubmVjdChzb2NrZXQsICZRU3NsU29ja2V0OjpyZWFkeVJlYWQsIHRoaXMsIFt0aGlzLCBz
b2NrZXQsIGlucHV0XSB7CisgICAgICAgICAgICBpbnB1dC0+YXBwZW5kKHNvY2tldC0+cmVhZEFs
bCgpKTsKKyAgICAgICAgICAgIGlmICghaW5wdXQtPmNvbnRhaW5zKCJcclxuXHJcbiIpKSByZXR1
cm47CisgICAgICAgICAgICArK3JlcXVlc3RzOyBhdXRob3JpemF0aW9uID0gKmlucHV0OworICAg
ICAgICAgICAgaWYgKHJlc3BvbmQpIHsKKyAgICAgICAgICAgICAgICBRQnl0ZUFycmF5IGhlYWRl
ciA9ICJIVFRQLzEuMSAiICsgUUJ5dGVBcnJheTo6bnVtYmVyKGNvZGUpICsgIiBGaXh0dXJlXHJc
bkNvbnRlbnQtVHlwZTogYXBwbGljYXRpb24vanNvblxyXG5Db25uZWN0aW9uOiBjbG9zZVxyXG5D
b250ZW50LUxlbmd0aDogIiArIFFCeXRlQXJyYXk6Om51bWJlcihib2R5LnNpemUoKSkgKyAiXHJc
biI7CisgICAgICAgICAgICAgICAgaWYgKGNvZGUgPT0gMzAyKSBoZWFkZXIgKz0gIkxvY2F0aW9u
OiBodHRwczovLzEyNy4wLjAuMjoxMjM0NS9cclxuIjsKKyAgICAgICAgICAgICAgICBzb2NrZXQt
PndyaXRlKGhlYWRlciArICJcclxuIiArIGJvZHkpOyBzb2NrZXQtPmRpc2Nvbm5lY3RGcm9tSG9z
dCgpOworICAgICAgICAgICAgfQorICAgICAgICAgICAgaW5wdXQtPmNsZWFyKCk7CisgICAgICAg
IH0pOworICAgICAgICBjb25uZWN0KHNvY2tldCwgJlFTc2xTb2NrZXQ6OmRpc2Nvbm5lY3RlZCwg
c29ja2V0LCAmUU9iamVjdDo6ZGVsZXRlTGF0ZXIpOworICAgICAgICBzb2NrZXQtPnN0YXJ0U2Vy
dmVyRW5jcnlwdGlvbigpOworICAgIH0KK307CisKK2NsYXNzIENyaW1zb25UZXN0IDogcHVibGlj
IFFPYmplY3QgeworICAgIFFfT0JKRUNUCitwcml2YXRlIHNsb3RzOgorICAgIHZvaWQgaW5pdFRl
c3RDYXNlKCkgeworICAgICAgICBRQ29yZUFwcGxpY2F0aW9uOjpzZXRPcmdhbml6YXRpb25OYW1l
KCJFY2xpcHNlT1MgVGVzdCIpOworICAgICAgICBRQ29yZUFwcGxpY2F0aW9uOjpzZXRBcHBsaWNh
dGlvbk5hbWUoIkVjbGlwc2VGaXh0dXJlIik7CisgICAgICAgIFFTZXR0aW5nczo6c2V0RGVmYXVs
dEZvcm1hdChRU2V0dGluZ3M6OkluaUZvcm1hdCk7CisgICAgfQorICAgIHZvaWQgaG9zdFByb2Zp
bGVzUmVtYWluSXNvbGF0ZWQoKSB7CisgICAgICAgIEVjbGlwc2VQcm9maWxlcyBwcm9maWxlczsK
KyAgICAgICAgUVZhcmlhbnRNYXAgdmFsdWVze3sid2lkdGgiLDEyODB9LHsiaGVpZ2h0Iiw4MDB9
LHsiZnBzIiw2MH0seyJiaXRyYXRlS2JwcyIsMTUwMDB9fTsKKyAgICAgICAgUVZFUklGWShwcm9m
aWxlcy5zYXZlKCJmaXh0dXJlLWhvc3QtYSIsIkRlc2t0b3AiLHZhbHVlcykpOworICAgICAgICBR
Q09NUEFSRShwcm9maWxlcy5sb2FkKCJmaXh0dXJlLWhvc3QtYSIsIkRlc2t0b3AiKSx2YWx1ZXMp
OworICAgICAgICBRVkVSSUZZKHByb2ZpbGVzLmxvYWQoImZpeHR1cmUtaG9zdC1iIiwiRGVza3Rv
cCIpLmlzRW1wdHkoKSk7CisgICAgICAgIFFWRVJJRlkocHJvZmlsZXMubmFtZXMoImZpeHR1cmUt
aG9zdC1hIikuY29udGFpbnMoIkRlc2t0b3AiKSk7CisgICAgICAgIFFWRVJJRlkoIXByb2ZpbGVz
LnJlbW92ZSgiZml4dHVyZS1ob3N0LWEiLCJEZXNrdG9wIixmYWxzZSkpOworICAgICAgICB2YWx1
ZXNbImZwcyJdID0gMDsgUVZFUklGWSghcHJvZmlsZXMuc2F2ZSgiZml4dHVyZS1ob3N0LWEiLCJC
YWQiLHZhbHVlcykpOworICAgICAgICBRVkVSSUZZKHByb2ZpbGVzLnJlbW92ZSgiZml4dHVyZS1o
b3N0LWEiLCJEZXNrdG9wIix0cnVlKSk7CisgICAgICAgIFFWRVJJRlkocHJvZmlsZXMubG9hZCgi
Zml4dHVyZS1ob3N0LWEiLCJEZXNrdG9wIikuaXNFbXB0eSgpKTsKKyAgICB9CisgICAgdm9pZCBz
eXN0ZW1Db250cm9sc1ByaXZhdGVQaXBlKCkgeworICAgICAgICBRVGVtcG9yYXJ5RGlyIGRpcjsg
UVZFUklGWShkaXIuaXNWYWxpZCgpKTsKKyAgICAgICAgUUZpbGUgc2NyaXB0KGRpci5maWxlUGF0
aCgiZml4dHVyZS5weSIpKTsgUVZFUklGWShzY3JpcHQub3BlbihRSU9EZXZpY2U6OldyaXRlT25s
eSkpOworICAgICAgICBzY3JpcHQud3JpdGUoUiJQWShpbXBvcnQganNvbixzeXMKK2ZvciBsaW5l
IGluIHN5cy5zdGRpbjoKKyAgICB2YWx1ZT1qc29uLmxvYWRzKGxpbmUpCisgICAgYWN0aW9uPXZh
bHVlWydhY3Rpb24nXQorICAgIGlmIGFjdGlvbj09J3dpZmktY29ubmVjdCc6CisgICAgICAgIHBy
aW50KGpzb24uZHVtcHMoeydwcm9tcHQnOidXaS1GaSBwYXNzd29yZCd9KSxmbHVzaD1UcnVlKQor
ICAgICAgICByZXBseT1qc29uLmxvYWRzKHN5cy5zdGRpbi5yZWFkbGluZSgpKQorICAgICAgICBh
c3NlcnQgcmVwbHk9PXsnYWN0aW9uJzonYW5zd2VyJywndmFsdWUnOidzZWNyZXQtdmFsdWUnfQor
ICAgIHByaW50KGpzb24uZHVtcHMoeydpdGVtcyc6W3snaWQnOid3bGFuMC9BQTpCQjpDQzpERDpF
RTpGRicsJ25hbWUnOic8Yj5QbGFpbiBTU0lEPC9iPicsJ2RldGFpbCc6JzgwJSBXUEEyJywnY29u
bmVjdGVkJzphY3Rpb249PSd3aWZpLWNvbm5lY3QnfV0sJ3N0YXR1cyc6J1JlYWR5JywnZG9uZSc6
VHJ1ZX0pLGZsdXNoPVRydWUpCispUFkiKTsgc2NyaXB0LmNsb3NlKCk7CisgICAgICAgIHFwdXRl
bnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIiwgc2NyaXB0LmZpbGVOYW1lKCkudG9VdGY4
KCkpOworICAgICAgICBTeXN0ZW1Db250cm9scyBjb250cm9sczsgY29udHJvbHMub3Blbigid2lm
aSIpOworICAgICAgICBRVFJZX0NPTVBBUkUoY29udHJvbHMuaXRlbXMoKS5zaXplKCksIDEpOyBR
VkVSSUZZKCFjb250cm9scy5idXN5KCkpOworICAgICAgICBjb250cm9scy5yZXF1ZXN0KCJidC1m
b3JnZXQiLCAiaW52YWxpZCIsIHRydWUpOyBRVkVSSUZZKCFjb250cm9scy5idXN5KCkpOworICAg
ICAgICBjb250cm9scy5yZXF1ZXN0KCJ3aWZpLWNvbm5lY3QiLCAid2xhbjAvQUE6QkI6Q0M6REQ6
RUU6RkYiKTsKKyAgICAgICAgUVRSWV9WRVJJRlkoIWNvbnRyb2xzLnByb21wdCgpLmlzRW1wdHko
KSk7IFFWRVJJRlkoY29udHJvbHMuYnVzeSgpKTsKKyAgICAgICAgY29udHJvbHMuYW5zd2VyKCJz
ZWNyZXQtdmFsdWUiKTsgUVRSWV9WRVJJRlkoIWNvbnRyb2xzLmJ1c3koKSk7CisgICAgICAgIFFW
RVJJRlkoY29udHJvbHMucHJvbXB0KCkuaXNFbXB0eSgpKTsgUUNPTVBBUkUoY29udHJvbHMuc3Rh
dHVzKCksIFFTdHJpbmcoIlJlYWR5IikpOworICAgICAgICBRVkVSSUZZKGNvbnRyb2xzLml0ZW1z
KCkuZmlyc3QoKS50b01hcCgpLnZhbHVlKCJjb25uZWN0ZWQiKS50b0Jvb2woKSk7CisgICAgICAg
IGNvbnRyb2xzLmNsb3NlKCk7IFFWRVJJRlkoIWNvbnRyb2xzLmJ1c3koKSk7CisgICAgICAgIHF1
bnNldGVudigiTU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUiKTsKKyAgICB9CisgICAgdm9pZCBt
YW5hZ2VkVXBkYXRlckNhbm5vdFJlcGxhY2VDdXN0b21pemVkQ2xpZW50KCkgeworICAgICAgICBR
VGVtcG9yYXJ5RGlyIGRpcjsgUVZFUklGWShkaXIuaXNWYWxpZCgpKTsKKyAgICAgICAgY29uc3Qg
UVN0cmluZyBpbWFnZSA9IGRpci5maWxlUGF0aCgiY3VzdG9tLkFwcEltYWdlIik7CisgICAgICAg
IFFGaWxlIGYoaW1hZ2UpOyBRVkVSSUZZKGYub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOyBm
LndyaXRlKCJjdXN0b21pemVkIGNsaWVudCIpOyBmLmNsb3NlKCk7CisgICAgICAgIGNvbnN0IFFC
eXRlQXJyYXkgb2xkID0gcWdldGVudigiQVBQSU1BR0UiKTsgY29uc3QgYm9vbCBoYWQgPSBxRW52
aXJvbm1lbnRWYXJpYWJsZUlzU2V0KCJBUFBJTUFHRSIpOworICAgICAgICBxcHV0ZW52KCJBUFBJ
TUFHRSIsIGltYWdlLnRvVXRmOCgpKTsKKyAgICAgICAgQXV0b1VwZGF0ZUNoZWNrZXIgY2hlY2tl
cjsKKyAgICAgICAgUVZFUklGWShjaGVja2VyLm9zTWFuYWdlZCgpKTsgUVZFUklGWSghY2hlY2tl
ci5jYW5JbnN0YWxsVXBkYXRlcygpKTsKKyAgICAgICAgUVNpZ25hbFNweSBjb21wbGV0ZWQoJmNo
ZWNrZXIsICZBdXRvVXBkYXRlQ2hlY2tlcjo6Y2hlY2tDb21wbGV0ZWQpOworICAgICAgICBRU2ln
bmFsU3B5IGZhaWxlZCgmY2hlY2tlciwgJkF1dG9VcGRhdGVDaGVja2VyOjppbnN0YWxsRmFpbGVk
KTsKKyAgICAgICAgY2hlY2tlci5zdGFydCgpOyBjaGVja2VyLmNoZWNrTm93KCk7IGNoZWNrZXIu
Y2hhbm5lbENoYW5nZWQoKTsgY2hlY2tlci5pbnN0YWxsKCk7CisgICAgICAgIFFDT01QQVJFKGNv
bXBsZXRlZC5jb3VudCgpLCAzKTsgUUNPTVBBUkUoZmFpbGVkLmNvdW50KCksIDEpOworICAgICAg
ICBRVkVSSUZZKCFjaGVja2VyLmNoZWNraW5nKCkpOyBRVkVSSUZZKCFjaGVja2VyLmluc3RhbGxp
bmcoKSk7CisgICAgICAgIFFWRVJJRlkoIWNoZWNrZXIuY2FuSW5zdGFsbCgpKTsgUVZFUklGWSgh
Y2hlY2tlci51cGRhdGVBdmFpbGFibGUoKSk7IFFWRVJJRlkoIWNoZWNrZXIub2ZmZXJBdmFpbGFi
bGUoKSk7CisgICAgICAgIFFDT01QQVJFKGNoZWNrZXIucmVsZWFzZVVybCgpLCBRU3RyaW5nKCJo
dHRwczovL2dpdGh1Yi5jb20vdGgzZDNjazNyL01vb25saWdodC1PUy9yZWxlYXNlcyIpKTsKKyAg
ICAgICAgUVZFUklGWShjaGVja2VyLmN1cnJlbnRWZXJzaW9uKCkuY29udGFpbnMoIkVjbGlwc2VP
UyBjdXN0b21pemVkIikpOworICAgICAgICBRVkVSSUZZKGYub3BlbihRSU9EZXZpY2U6OlJlYWRP
bmx5KSk7IFFDT01QQVJFKGYucmVhZEFsbCgpLCBRQnl0ZUFycmF5KCJjdXN0b21pemVkIGNsaWVu
dCIpKTsgZi5jbG9zZSgpOworICAgICAgICBRQ09NUEFSRShRRGlyKGRpci5wYXRoKCkpLmVudHJ5
TGlzdChRRGlyOjpGaWxlcyksIFFTdHJpbmdMaXN0eyJjdXN0b20uQXBwSW1hZ2UifSk7CisgICAg
ICAgIGlmIChoYWQpIHFwdXRlbnYoIkFQUElNQUdFIiwgb2xkKTsgZWxzZSBxdW5zZXRlbnYoIkFQ
UElNQUdFIik7CisgICAgICAgIFFDT01QQVJFKEF1dG9VcGRhdGVDaGVja2VyOjpjb21wYXJlU2Vt
YW50aWNWZXJzaW9ucygiMC41LjAiLCAiMC40LjkiKSwgMSk7CisgICAgfQorICAgIHZvaWQgZW5k
cG9pbnRWYWxpZGF0aW9uKCkgeworICAgICAgICBRVkVSSUZZKENyaW1zb25TdGF0dXM6OnZhbGlk
RW5kcG9pbnQoImh0dHBzOi8vMTkyLjE2OC4xLjEwOjQ3OTkwIikpOworICAgICAgICBRVkVSSUZZ
KENyaW1zb25TdGF0dXM6OnZhbGlkRW5kcG9pbnQoImh0dHBzOi8vW2ZkMDA6OjFdOjQ3OTkwLyIp
KTsKKyAgICAgICAgZm9yIChhdXRvIGJhZCA6IHsiaHR0cDovL2hvc3QiLCAiaHR0cHM6Ly91c2Vy
OnNlY3JldEBob3N0IiwgImh0dHBzOi8vaG9zdC9hcGkiLCAiaHR0cHM6Ly9ob3N0Lz90b2tlbj1z
ZWNyZXQiLCAiZmlsZTovLy9ldGMvcGFzc3dkIiwgImh0dHBzOi8vaG9zdC8jZnJhZ21lbnQifSkK
KyAgICAgICAgICAgIFFWRVJJRlkoIUNyaW1zb25TdGF0dXM6OnZhbGlkRW5kcG9pbnQoYmFkKSk7
CisgICAgfQorICAgIHZvaWQgbWlzc2luZ0FuZEludmFsaWRNZXRyaWNzKCkgeworICAgICAgICBR
U3RyaW5nIGVycm9yOworICAgICAgICBRVkVSSUZZKENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMo
Im5vdCBqc29uIiwgJmVycm9yKS5pc0VtcHR5KCkpOyBRVkVSSUZZKCFlcnJvci5pc0VtcHR5KCkp
OworICAgICAgICBhdXRvIHMgPSBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKFIiKHsiY3B1X3Bl
cmNlbnQiOjQyLjUsImNwdV90ZW1wX2MiOi0xLCJncHVfcGVyY2VudCI6bnVsbCwicmFtX3RvdGFs
X2J5dGVzIjowLCJyYW1fcGVyY2VudCI6MCwidnJhbV90b3RhbF9ieXRlcyI6MTAwLCJ2cmFtX3Vz
ZWRfYnl0ZXMiOjEyMH0pIiwgJmVycm9yKTsKKyAgICAgICAgUVZFUklGWShlcnJvci5pc0VtcHR5
KCkpOyBRQ09NUEFSRShzLnZhbHVlKCJjcHVfcGVyY2VudCIpLnRvRG91YmxlKCksIDQyLjUpOwor
ICAgICAgICBRVkVSSUZZKCFzLmNvbnRhaW5zKCJjcHVfdGVtcF9jIikpOyBRVkVSSUZZKCFzLmNv
bnRhaW5zKCJncHVfcGVyY2VudCIpKTsgUVZFUklGWSghcy5jb250YWlucygicmFtX3BlcmNlbnQi
KSk7CisgICAgICAgIFFDT01QQVJFKHMudmFsdWUoInZyYW1fcGVyY2VudCIpLnRvRG91YmxlKCks
IDEwMC4wKTsKKyAgICAgICAgYXV0byBpbnZhbGlkID0gQ3JpbXNvblN0YXR1czo6cGFyc2VTdGF0
cyhSIih7ImNwdV9wZXJjZW50IjoxMDEsImdwdV9wZXJjZW50IjoiMCJ9KSIsICZlcnJvcik7Cisg
ICAgICAgIFFWRVJJRlkoaW52YWxpZC5pc0VtcHR5KCkpOyBRVkVSSUZZKGVycm9yLmlzRW1wdHko
KSk7CisgICAgICAgIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUUJ5dGVBcnJheSg2NTUzNywg
J2EnKSwgJmVycm9yKTsgUVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsKKyAgICAgICAgQ3JpbXNv
blN0YXR1czo6cGFyc2VTdGF0cyhSIih7ImVycm9yIjoidW5zdXBwb3J0ZWQifSkiLCAmZXJyb3Ip
OyBRVkVSSUZZKCFlcnJvci5pc0VtcHR5KCkpOworICAgIH0KKyAgICB2b2lkIGxvY2FsSGFyZHdh
cmVGaXh0dXJlKCkgeworICAgICAgICBRVGVtcG9yYXJ5RGlyIHRlbXA7IFFWRVJJRlkodGVtcC5p
c1ZhbGlkKCkpOworICAgICAgICBhdXRvIHdyaXRlID0gWyZdKFFTdHJpbmcgcCwgUUJ5dGVBcnJh
eSB2YWx1ZSkgeyBRRGlyKCkubWtwYXRoKFFGaWxlSW5mbyh0ZW1wLnBhdGgoKStwKS5hYnNvbHV0
ZVBhdGgoKSk7IFFGaWxlIGYodGVtcC5wYXRoKCkrcCk7IFFWRVJJRlkoZi5vcGVuKFFJT0Rldmlj
ZTo6V3JpdGVPbmx5KSk7IGYud3JpdGUodmFsdWUpOyB9OworICAgICAgICB3cml0ZSgiL2NsYXNz
L3Bvd2VyX3N1cHBseS9CQVQwL3R5cGUiLCAiQmF0dGVyeSIpOyB3cml0ZSgiL2NsYXNzL3Bvd2Vy
X3N1cHBseS9CQVQwL2NhcGFjaXR5IiwgIjczIik7IHdyaXRlKCIvY2xhc3MvcG93ZXJfc3VwcGx5
L0JBVDAvc3RhdHVzIiwgIkNoYXJnaW5nIik7CisgICAgICAgIHdyaXRlKCIvY2xhc3MvbmV0L3ds
YW4wL29wZXJzdGF0ZSIsICJ1cCIpOyB3cml0ZSgiL2NsYXNzL25ldC9sby9vcGVyc3RhdGUiLCAi
dXAiKTsKKyAgICAgICAgYXV0byBsb2NhbCA9IENyaW1zb25TdGF0dXM6OnJlYWRMb2NhbCh0ZW1w
LnBhdGgoKSk7IFFDT01QQVJFKGxvY2FsLnZhbHVlKCJiYXR0ZXJ5UGVyY2VudCIpLnRvSW50KCks
IDczKTsgUUNPTVBBUkUobG9jYWwudmFsdWUoImJhdHRlcnlTdGF0ZSIpLnRvU3RyaW5nKCksIFFT
dHJpbmcoIkNoYXJnaW5nIikpOworICAgICAgICBRQ09NUEFSRShsb2NhbC52YWx1ZSgibmV0d29y
ayIpLnRvU3RyaW5nKCksIFFTdHJpbmcoIndsYW4wIikpOyBRVkVSSUZZKGxvY2FsLnZhbHVlKCJj
b25uZWN0ZWQiKS50b0Jvb2woKSk7CisgICAgICAgIHdyaXRlKCIvY2xhc3MvcG93ZXJfc3VwcGx5
L0JBVDAvY2FwYWNpdHkiLCAiMTAxIik7IFFDT01QQVJFKENyaW1zb25TdGF0dXM6OnJlYWRMb2Nh
bCh0ZW1wLnBhdGgoKSkudmFsdWUoImJhdHRlcnlQZXJjZW50IikudG9JbnQoKSwgLTEpOworICAg
IH0KKyAgICB2b2lkIHByaXZhdGVTZXR0aW5nc0FuZE5vQ3Jvc3NIb3N0Q3JlZGVudGlhbHMoKSB7
CisgICAgICAgIFFTdGFuZGFyZFBhdGhzOjpzZXRUZXN0TW9kZUVuYWJsZWQodHJ1ZSk7CisgICAg
ICAgIENyaW1zb25TdGF0dXMgc3RhdHVzOyBzdGF0dXMuc2VsZWN0SG9zdCgidGVzdC1hIiwgImh0
dHBzOi8vMTI3LjAuMC4xOjQ3OTkwIik7CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3Vy
ZSgiaHR0cHM6Ly8xMjcuMC4wLjE6NDc5OTAiLCAiZml4dHVyZS10b2tlbiIsICIiKSk7IFFWRVJJ
Rlkoc3RhdHVzLmNvbmZpZ3VyZWQoKSk7CisgICAgICAgIGF1dG8gcGF0aCA9IFFTdGFuZGFyZFBh
dGhzOjp3cml0YWJsZUxvY2F0aW9uKFFTdGFuZGFyZFBhdGhzOjpBcHBDb25maWdMb2NhdGlvbikg
KyAiL2NyaW1zb24taG9zdHMuanNvbiI7CisgICAgICAgIFFWRVJJRlkoKFFGaWxlOjpwZXJtaXNz
aW9ucyhwYXRoKSAmIChRRmlsZURldmljZTo6UmVhZEdyb3VwIHwgUUZpbGVEZXZpY2U6OlJlYWRP
dGhlciB8IFFGaWxlRGV2aWNlOjpXcml0ZUdyb3VwIHwgUUZpbGVEZXZpY2U6OldyaXRlT3RoZXIp
KSA9PSAwKTsKKyAgICAgICAgc3RhdHVzLnNlbGVjdEhvc3QoInRlc3QtYiIsICJodHRwczovLzEy
Ny4wLjAuMjo0Nzk5MCIpOyBRVkVSSUZZKCFzdGF0dXMuY29uZmlndXJlZCgpKTsKKyAgICAgICAg
UVZFUklGWSghc3RhdHVzLmNvbmZpZ3VyZSgiaHR0cHM6Ly8xMjcuMC4wLjI6NDc5OTAiLCAiIiwg
IiIpKTsKKyAgICAgICAgUVZFUklGWSghc3RhdHVzLmNvbmZpZ3VyZSgiaHR0cHM6Ly8xMjcuMC4w
LjI6NDc5OTAiLCAiZml4dHVyZS10b2tlbiIsICJpbnZhbGlkLXBpbiIpKTsKKyAgICAgICAgUVZF
UklGWSghc3RhdHVzLmNvbmZpZ3VyZSgiaHR0cHM6Ly8xMjcuMC4wLjI6NDc5OTAiLCAidG9rZW5c
bmluamVjdGlvbiIsICIiKSk7CisgICAgICAgIFFGaWxlOjpyZW1vdmUocGF0aCk7CisgICAgfQor
ICAgIHZvaWQgdGxzQXV0aGVudGljYXRpb25BbmRWaXNpYmlsaXR5KCkgeworICAgICAgICBUbHNG
aXh0dXJlIHNlcnZlcjsgUVZFUklGWShzZXJ2ZXIuaXNMaXN0ZW5pbmcoKSk7IFFWRVJJRlkoIXNl
cnZlci5jZXJ0LmlzTnVsbCgpKTsKKyAgICAgICAgUVN0cmluZyB1cmwgPSAiaHR0cHM6Ly8xMjcu
MC4wLjE6IiArIFFTdHJpbmc6Om51bWJlcihzZXJ2ZXIuc2VydmVyUG9ydCgpKTsKKyAgICAgICAg
UVN0cmluZyBwaW4gPSBRU3RyaW5nOjpmcm9tTGF0aW4xKHNlcnZlci5jZXJ0LmRpZ2VzdChRQ3J5
cHRvZ3JhcGhpY0hhc2g6OlNoYTI1NikudG9IZXgoKSk7CisgICAgICAgIENyaW1zb25TdGF0dXMg
c3RhdHVzOyBzdGF0dXMuc2VsZWN0SG9zdCgiZml4dHVyZS10bHMiLCB1cmwpOworICAgICAgICBR
VkVSSUZZKHN0YXR1cy5jb25maWd1cmUodXJsLCAiZml4dHVyZS1vbmx5LXRva2VuIiwgIiIpKTsg
c3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9V
VChzdGF0dXMuc3RhdHVzKCkuY29udGFpbnMoImZpbmdlcnByaW50IiksIDUwMDApOworICAgICAg
ICBRQ09NUEFSRShzZXJ2ZXIucmVxdWVzdHMsIDApOyAvLyBubyBjcmVkZW50aWFscyBzZW50IGJl
Zm9yZSB0cnVzdGluZyBzZWxmLXNpZ25lZCBUTFMKKyAgICAgICAgUVZFUklGWShzdGF0dXMuY29u
ZmlndXJlKHVybCwgImZpeHR1cmUtb25seS10b2tlbiIsIHBpbikpOworICAgICAgICBRVFJZX0NP
TVBBUkVfV0lUSF9USU1FT1VUKHN0YXR1cy5zdGF0cygpLnZhbHVlKCJjcHVfcGVyY2VudCIpLnRv
RG91YmxlKCksIDM3LjUsIDUwMDApOworICAgICAgICBRVkVSSUZZKHNlcnZlci5hdXRob3JpemF0
aW9uLmNvbnRhaW5zKCJBdXRob3JpemF0aW9uOiBCZWFyZXIgZml4dHVyZS1vbmx5LXRva2VuIikp
OworICAgICAgICBRVkVSSUZZKHNlcnZlci5hdXRob3JpemF0aW9uLnN0YXJ0c1dpdGgoIkdFVCAv
YXBpL2hvc3Qvc3RhdHMgIikpOworICAgICAgICBzdGF0dXMuc2V0VmlzaWJsZShmYWxzZSk7IGlu
dCBjb3VudCA9IHNlcnZlci5yZXF1ZXN0czsgUVRlc3Q6OnFXYWl0KDIxMDApOyBRQ09NUEFSRShz
ZXJ2ZXIucmVxdWVzdHMsIGNvdW50KTsKKyAgICAgICAgZm9yIChpbnQgY29kZSA6IHs0MDEsIDQw
MywgNDA0LCAzMDJ9KSB7CisgICAgICAgICAgICBzZXJ2ZXIuY29kZSA9IGNvZGU7IGludCBwcmlv
ciA9IHNlcnZlci5yZXF1ZXN0czsgc3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAgICAgICAg
ICBRVFJZX1ZFUklGWV9XSVRIX1RJTUVPVVQoc2VydmVyLnJlcXVlc3RzID4gcHJpb3IsIDUwMDAp
OworICAgICAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHN0YXR1cy5zdGF0cygpLmlz
RW1wdHkoKSwgNTAwMCk7CisgICAgICAgICAgICBzdGF0dXMuc2V0VmlzaWJsZShmYWxzZSk7Cisg
ICAgICAgIH0KKyAgICAgICAgc2VydmVyLmNvZGUgPSAyMDA7IHNlcnZlci5ib2R5ID0gUUJ5dGVB
cnJheSg3MDAwMCwgJ2EnKTsgaW50IHByaW9yID0gc2VydmVyLnJlcXVlc3RzOyBzdGF0dXMuc2V0
VmlzaWJsZSh0cnVlKTsKKyAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHNlcnZlci5y
ZXF1ZXN0cyA+IHByaW9yLCA1MDAwKTsKKyAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VU
KHN0YXR1cy5zdGF0cygpLmlzRW1wdHkoKSwgNTAwMCk7IHN0YXR1cy5zZXRWaXNpYmxlKGZhbHNl
KTsKKyAgICAgICAgUVZFUklGWShzdGF0dXMuY29uZmlndXJlKHVybCwgImZpeHR1cmUtb25seS10
b2tlbiIsIFFTdHJpbmcoNjQsICcwJykpKTsgc3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAg
ICAgIGNvdW50ID0gc2VydmVyLnJlcXVlc3RzOyBRVGVzdDo6cVdhaXQoNTAwKTsgUUNPTVBBUkUo
c2VydmVyLnJlcXVlc3RzLCBjb3VudCk7IFFWRVJJRlkoc3RhdHVzLnN0YXRzKCkuaXNFbXB0eSgp
KTsKKyAgICAgICAgc3RhdHVzLnNldFZpc2libGUoZmFsc2UpOworICAgIH0KKyAgICB2b2lkIHJv
dW5kZWRPdmVybGF5QWNjZW50c0FuZE9wYWNpdHkoKSB7CisgICAgICAgIGZvcihpbnQgYWNjZW50
PTA7YWNjZW50PDE2OysrYWNjZW50KSB7CisgICAgICAgICAgICBhdXRvIGltYWdlPUVjbGlwc2VP
dmVybGF5U3R5bGU6OnBhbmVsKFFTaXplKDQwMCwxODApLGFjY2VudCw4NSk7IFFWRVJJRlkoIWlt
YWdlLmlzTnVsbCgpKTsKKyAgICAgICAgICAgIFFDT01QQVJFKGltYWdlLnBpeGVsQ29sb3IoMCww
KS5hbHBoYSgpLDApOworICAgICAgICAgICAgUUNPTVBBUkUoaW1hZ2UucGl4ZWxDb2xvcigyMDAs
OTApLmFscGhhKCksODUqMjU1LzEwMCk7CisgICAgICAgICAgICBRQ09NUEFSRShpbWFnZS5waXhl
bENvbG9yKDIwMCw4KS5yZ2IoKSxFY2xpcHNlT3ZlcmxheVN0eWxlOjphY2NlbnQoYWNjZW50KS5y
Z2IoKSk7CisgICAgICAgIH0KKyAgICAgICAgUVZFUklGWShFY2xpcHNlT3ZlcmxheVN0eWxlOjpw
YW5lbChRU2l6ZSgtMSwxMDApLDAsODUpLmlzTnVsbCgpKTsKKyAgICAgICAgUVZFUklGWShFY2xp
cHNlT3ZlcmxheVN0eWxlOjpwYW5lbChRU2l6ZSg0MDk2LDEwMCksMCw4NSkuaXNOdWxsKCkpOwor
ICAgIH0KKyAgICB2b2lkIGdyYXBoU2FtcGxlc1ByZXNlcnZlTWlzc2luZ0FuZFdpbmRvdygpIHsK
KyAgICAgICAgYXV0byB2YWx1ZXM9Q3JpbXNvbkdyYXBoczo6dmFsdWVzKCJWaWRlbyBzdHJlYW06
IDE5MjB4MTA4MCAxMjAuMDAgRlBTXG5SZW5kZXJpbmcgZnJhbWUgcmF0ZTogNTkuMjUgRlBTXG5B
dmVyYWdlIG5ldHdvcmsgbGF0ZW5jeTogMTIgbXMiLGZhbHNlLHt7ImNwdVBlcmNlbnQiLDI1LjB9
LHsibWVtb3J5VXNlZEdpQiIsNC41fX0pOworICAgICAgICBRQ09NUEFSRSh2YWx1ZXNbIkZQUyJd
LDU5LjI1KTtRQ09NUEFSRSh2YWx1ZXNbIk5ldHdvcmsgbGF0ZW5jeSJdLDEyLjApO1FDT01QQVJF
KHZhbHVlc1siTG9jYWwgQ1BVIl0sMjUuMCk7CisgICAgICAgIGF1dG8gY29tcGFjdD1Dcmltc29u
R3JhcGhzOjp2YWx1ZXMoIjYwIGZwcyDCtyAxOTIweDEwODAgSDI2NCDCtyBuZXQgNyBtcyDCtyBk
ZWMgMi4wIG1zIixmYWxzZSx7fSk7CisgICAgICAgIFFDT01QQVJFKGNvbXBhY3RbIkZQUyJdLDYw
LjApO1FDT01QQVJFKGNvbXBhY3RbIk5ldHdvcmsgbGF0ZW5jeSJdLDcuMCk7UVZFUklGWShxSXNO
YU4oY29tcGFjdFsiTG9jYWwgUkFNIl0pKTsKKyAgICAgICAgYXV0byB1bmF2YWlsYWJsZT1Dcmlt
c29uR3JhcGhzOjp2YWx1ZXMoIkF2ZXJhZ2UgbmV0d29yayBsYXRlbmN5OiBOL0FcblZpZGVvIHN0
cmVhbTogMTkyMHgxMDgwIDEyMC4wMCBGUFMiLGZhbHNlLHt9KTsKKyAgICAgICAgUVZFUklGWShx
SXNOYU4odW5hdmFpbGFibGVbIkZQUyJdKSk7UVZFUklGWShxSXNOYU4odW5hdmFpbGFibGVbIk5l
dHdvcmsgbGF0ZW5jeSJdKSk7CisgICAgICAgIGF1dG8gaW52YWxpZD1Dcmltc29uR3JhcGhzOjp2
YWx1ZXMoIiIsdHJ1ZSx7eyJjcHVQZXJjZW50IixRVmFyaWFudCgpfSx7Im1lbW9yeVVzZWRHaUIi
LCJpbnZhbGlkIn0seyJ0ZW1wZXJhdHVyZUMiLC0xfSx7InJlY2VpdmVNaUIiLDAuMH19KTsKKyAg
ICAgICAgUVZFUklGWShxSXNOYU4oaW52YWxpZFsiTG9jYWwgQ1BVIl0pKTtRVkVSSUZZKHFJc05h
TihpbnZhbGlkWyJMb2NhbCBSQU0iXSkpO1FWRVJJRlkocUlzTmFOKGludmFsaWRbIlRlbXBlcmF0
dXJlIl0pKTtRQ09NUEFSRShpbnZhbGlkWyJEb3dubG9hZCJdLDAuMCk7CisgICAgICAgIENyaW1z
b25HcmFwaHM6Okhpc3RvcnkgaGlzdG9yeTtmb3IoaW50IGk9MDtpPDgwO2krKylDcmltc29uR3Jh
cGhzOjpwdXNoKGhpc3RvcnksdmFsdWVzKTsKKyAgICAgICAgUUNPTVBBUkUoaGlzdG9yeVsiRlBT
Il0uc2l6ZSgpLDYwKTtDcmltc29uR3JhcGhzOjpwdXNoKGhpc3RvcnksdW5hdmFpbGFibGUpO1FW
RVJJRlkocUlzTmFOKGhpc3RvcnlbIkZQUyJdLmxhc3QoKSkpOworICAgICAgICBmb3IoaW50IGk9
MDtpPDYwO2krKyl7dmFsdWVzWyJGUFMiXT02MCtxU2luKGkqMC40KSoyO3ZhbHVlc1siTmV0d29y
ayBsYXRlbmN5Il09MTIrcVNpbihpKjAuMykqMzt2YWx1ZXNbIkxvY2FsIENQVSJdPTI1K3FTaW4o
aSowLjUpKjEwO3ZhbHVlc1siTG9jYWwgUkFNIl09NC41K3FTaW4oaSowLjIpKjAuMjtDcmltc29u
R3JhcGhzOjpwdXNoKGhpc3RvcnksdmFsdWVzKTt9CisgICAgICAgIFFJbWFnZSBpbWFnZT1FY2xp
cHNlT3ZlcmxheVN0eWxlOjpwYW5lbChRU2l6ZSg0ODAsMjUwKSw0LDg1KTtDcmltc29uR3JhcGhz
OjpwYWludChpbWFnZSw0MCwxOCw0LGhpc3RvcnksZmFsc2UpOworICAgICAgICB7UVBhaW50ZXIg
cGFpbnRlcigmaW1hZ2UpO3BhaW50ZXIuc2V0UGVuKFFDb2xvcigiI0VDRUVGMSIpKTtwYWludGVy
LmRyYXdUZXh0KDE2LDI4LCJFY2xpcHNlT1MgfCBTVFJFQU0g4oCUIGdyYXBoIGZpeHR1cmUiKTt9
CisgICAgICAgIFFTdHJpbmcgb3V0PXFFbnZpcm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1NDUkVF
TlNIT1RTIik7aWYoIW91dC5pc0VtcHR5KCkpe1FEaXIoKS5ta3BhdGgob3V0KTtRVkVSSUZZKGlt
YWdlLnNhdmUob3V0KyIvY3JpbXNvbi1nbGFzcy1vdmVybGF5LnBuZyIpKTt9CisgICAgfQorICAg
IHZvaWQgYmFja2dyb3VuZFNlbGVjdGlvbkFuZFBlcnNpc3RlbmNlKCkgeworICAgICAgICBFY2xp
cHNlUHJvZmlsZXMgcHJvZmlsZTtwcm9maWxlLnJlc2V0QmFja2dyb3VuZCgpO1FUZW1wb3JhcnlE
aXIgZm9sZGVyO1FWRVJJRlkoZm9sZGVyLmlzVmFsaWQoKSk7CisgICAgICAgIFFJbWFnZSBpbnB1
dCgzMDAwLDE4MDAsUUltYWdlOjpGb3JtYXRfUkdCMzIpO2lucHV0LmZpbGwoUUNvbG9yKCIjNzcy
MjMzIikpO1FTdHJpbmcgc291cmNlPWZvbGRlci5maWxlUGF0aCgid2FsbHBhcGVyLnBuZyIpO1FW
RVJJRlkoaW5wdXQuc2F2ZShzb3VyY2UpKTsKKyAgICAgICAgUVZFUklGWSghcHJvZmlsZS5jaG9v
c2VCYWNrZ3JvdW5kKFFVcmwoImh0dHBzOi8vZXhhbXBsZS5jb20vd2FsbHBhcGVyLnBuZyIpKSk7
CisgICAgICAgIFFWRVJJRlkoIXByb2ZpbGUuY2hvb3NlQmFja2dyb3VuZChRVXJsOjpmcm9tTG9j
YWxGaWxlKGZvbGRlci5maWxlUGF0aCgibWlzc2luZy5wbmciKSkpKTsKKyAgICAgICAgUUZpbGUg
aW52YWxpZChmb2xkZXIuZmlsZVBhdGgoImludmFsaWQucG5nIikpO1FWRVJJRlkoaW52YWxpZC5v
cGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7aW52YWxpZC53cml0ZSgibm90IGFuIGltYWdlIik7
aW52YWxpZC5jbG9zZSgpOworICAgICAgICBRVkVSSUZZKCFwcm9maWxlLmNob29zZUJhY2tncm91
bmQoUVVybDo6ZnJvbUxvY2FsRmlsZShpbnZhbGlkLmZpbGVOYW1lKCkpKSk7CisgICAgICAgIFFG
aWxlIG92ZXJzaXplZChmb2xkZXIuZmlsZVBhdGgoIm92ZXJzaXplZC5wbmciKSk7UVZFUklGWShv
dmVyc2l6ZWQub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpO1FWRVJJRlkob3ZlcnNpemVkLnJl
c2l6ZSgzMioxMDI0KjEwMjQrMSkpO292ZXJzaXplZC5jbG9zZSgpOworICAgICAgICBRVkVSSUZZ
KCFwcm9maWxlLmNob29zZUJhY2tncm91bmQoUVVybDo6ZnJvbUxvY2FsRmlsZShvdmVyc2l6ZWQu
ZmlsZU5hbWUoKSkpKTsKKyAgICAgICAgUVZFUklGWShwcm9maWxlLmNob29zZUJhY2tncm91bmQo
UVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UpKSk7UVZFUklGWShwcm9maWxlLmJhY2tncm91bmQo
KS5pc0xvY2FsRmlsZSgpKTsKKyAgICAgICAgUVN0cmluZyBzYXZlZD1wcm9maWxlLmJhY2tncm91
bmQoKS50b0xvY2FsRmlsZSgpO1FWRVJJRlkoc2F2ZWQhPXNvdXJjZSk7UVZFUklGWShRRmlsZTo6
cmVtb3ZlKHNvdXJjZSkpO1FWRVJJRlkoIVFJbWFnZShzYXZlZCkuaXNOdWxsKCkpO1FWRVJJRlko
UUltYWdlKHNhdmVkKS53aWR0aCgpPD0yNTYwKTsKKyAgICAgICAgRWNsaXBzZVByb2ZpbGVzIHJl
bG9hZGVkO1FDT01QQVJFKHJlbG9hZGVkLmJhY2tncm91bmQoKSxwcm9maWxlLmJhY2tncm91bmQo
KSk7cmVsb2FkZWQuc2V0QmFja2dyb3VuZERpbSgwKTtRQ09NUEFSRShyZWxvYWRlZC5iYWNrZ3Jv
dW5kRGltKCksMzApO3JlbG9hZGVkLnNldEJhY2tncm91bmREaW0oOTk5KTtRQ09NUEFSRShyZWxv
YWRlZC5iYWNrZ3JvdW5kRGltKCksOTApOworICAgICAgICBRVkVSSUZZKCFwcm9maWxlLmJhY2tn
cm91bmRGaWxlcyhRVXJsKCJodHRwczovL2V4YW1wbGUuY29tLyIpKS5zaXplKCkpO3Byb2ZpbGUu
cmVzZXRCYWNrZ3JvdW5kKCk7UVZFUklGWShwcm9maWxlLmJhY2tncm91bmQoKS5pc0VtcHR5KCkp
O3Byb2ZpbGUuc2V0QmFja2dyb3VuZERpbSg2NSk7CisgICAgfQorICAgIHZvaWQgaGFyZHdhcmVW
aXNpYmxlQ29uc3VtZXJzKCkgeworICAgICAgICBMb2NhbEhhcmR3YXJlIG1vbml0b3I7bW9uaXRv
ci5zZXRSZWZyZXNoU2Vjb25kcygxKTtRT2JqZWN0IGZpcnN0LHNlY29uZDtRU2lnbmFsU3B5IHNh
bXBsZXMoJm1vbml0b3IsJkxvY2FsSGFyZHdhcmU6OmNoYW5nZWQpOworICAgICAgICBtb25pdG9y
LnNldENvbnN1bWVyQWN0aXZlKCZmaXJzdCx0cnVlKTtRQ09NUEFSRShzYW1wbGVzLmNvdW50KCks
MSk7CisgICAgICAgIG1vbml0b3Iuc2V0Q29uc3VtZXJBY3RpdmUoJmZpcnN0LHRydWUpO1FDT01Q
QVJFKHNhbXBsZXMuY291bnQoKSwxKTsKKyAgICAgICAgbW9uaXRvci5zZXRDb25zdW1lckFjdGl2
ZSgmc2Vjb25kLHRydWUpO21vbml0b3Iuc2V0Q29uc3VtZXJBY3RpdmUoJmZpcnN0LGZhbHNlKTsK
KyAgICAgICAgbW9uaXRvci5zZXRBY3RpdmUodHJ1ZSk7bW9uaXRvci5zZXRBY3RpdmUoZmFsc2Up
OyAvLyBsZWdhY3kgY2FsbGVyIG11c3Qgbm90IHJldm9rZSBhbm90aGVyIHZpZXcncyBsZWFzZQor
ICAgICAgICBRVGVzdDo6cVdhaXQoMjEwMCk7UVZFUklGWShzYW1wbGVzLmNvdW50KCk+PTIpOwor
ICAgICAgICBtb25pdG9yLnNldENvbnN1bWVyQWN0aXZlKCZzZWNvbmQsZmFsc2UpO2ludCBjb3Vu
dD1zYW1wbGVzLmNvdW50KCk7UVRlc3Q6OnFXYWl0KDIxMDApO1FDT01QQVJFKHNhbXBsZXMuY291
bnQoKSxjb3VudCk7CisgICAgfQorICAgIHZvaWQgbG9jYWxIYXJkd2FyZUNvdW50ZXJzQW5kU2Vu
c29ycygpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciByb290OyBRVkVSSUZZKHJvb3QuaXNWYWxp
ZCgpKTsKKyAgICAgICAgYXV0byB3cml0ZT1bJl0oY29uc3QgUVN0cmluZyYgcGF0aCxjb25zdCBR
Qnl0ZUFycmF5JiBkYXRhKSB7IFFTdHJpbmcgZnVsbD1yb290LnBhdGgoKStwYXRoOyBRRGlyKCku
bWtwYXRoKFFGaWxlSW5mbyhmdWxsKS5hYnNvbHV0ZVBhdGgoKSk7IFFGaWxlIGZpbGUoZnVsbCk7
IFFWRVJJRlkoZmlsZS5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7IFFDT01QQVJFKGZpbGUu
d3JpdGUoZGF0YSkscWludDY0KGRhdGEuc2l6ZSgpKSk7IH07CisgICAgICAgIFFTZXR0aW5ncygp
LnNldFZhbHVlKCJlY2xpcHNlL2hhcmR3YXJlUmVmcmVzaCIsMSk7CisgICAgICAgIHdyaXRlKCIv
cHJvYy9zdGF0IiwiY3B1IDEwMCAwIDEwMCA4MDAgMCAwIDAgMFxuIik7CisgICAgICAgIHdyaXRl
KCIvcHJvYy9tZW1pbmZvIiwiTWVtVG90YWw6IDEwNDg1NzYga0Jcbk1lbUF2YWlsYWJsZTogMjYy
MTQ0IGtCXG5Td2FwVG90YWw6IDEwMjQga0JcblN3YXBGcmVlOiA1MTIga0JcbiIpOworICAgICAg
ICB3cml0ZSgiL3N5cy9jbGFzcy9od21vbi9od21vbjAvbmFtZSIsImNvcmV0ZW1wIik7IHdyaXRl
KCIvc3lzL2NsYXNzL2h3bW9uL2h3bW9uMC90ZW1wMV9pbnB1dCIsIjYyNTAwIik7CisgICAgICAg
IHdyaXRlKCIvc3lzL2NsYXNzL2h3bW9uL2h3bW9uMC9mYW4xX2lucHV0IiwiMjQwMCIpOworICAg
ICAgICB3cml0ZSgiL3Byb2MvbmV0L3JvdXRlIiwiSWZhY2UgRGVzdGluYXRpb24gR2F0ZXdheSBG
bGFnc1xud2xhbjAgMDAwMDAwMDAgMDEwMjAzMDQgMDAwM1xuIik7CisgICAgICAgIHdyaXRlKCIv
cHJvYy9uZXQvZGV2Iiwid2xhbjA6IDEwMDAgMCAwIDAgMCAwIDAgMCAyMDAwIDAgMCAwIDAgMCAw
IDBcbiIpOworICAgICAgICBRQnl0ZUFycmF5IHZpZGVvPSJkcm0tY2xpZW50LWlkOiA3XG5kcm0t
ZW5naW5lLXZpZGVvOiAxMDAwMDAwMDAgbnNcbiI7CisgICAgICAgIHdyaXRlKCIvcHJvYy9zZWxm
L2ZkaW5mby8xIix2aWRlbyk7IHdyaXRlKCIvcHJvYy9zZWxmL2ZkaW5mby8yIix2aWRlbyk7Cisg
ICAgICAgIGF1dG8gZmlyc3Q9TG9jYWxIYXJkd2FyZTo6c2FtcGxlKHJvb3QucGF0aCgpKTsgUVZF
UklGWSghZmlyc3QuY29udGFpbnMoImNwdVBlcmNlbnQiKSk7IFFWRVJJRlkoIWZpcnN0LmNvbnRh
aW5zKCJ2aWRlb1BlcmNlbnQiKSk7CisgICAgICAgIFFDT01QQVJFKGZpcnN0WyJtZW1vcnlQZXJj
ZW50Il0udG9Eb3VibGUoKSw3NS4wKTsgUUNPTVBBUkUoZmlyc3RbInRlbXBlcmF0dXJlQyJdLnRv
RG91YmxlKCksNjIuNSk7IFFDT01QQVJFKGZpcnN0WyJmYW5SUE0iXS50b0RvdWJsZSgpLDI0MDAu
MCk7CisgICAgICAgIFFUZXN0OjpxV2FpdCgxMDUwKTsKKyAgICAgICAgd3JpdGUoIi9wcm9jL3N0
YXQiLCJjcHUgMTUwIDAgMTUwIDkwMCAwIDAgMCAwXG4iKTsKKyAgICAgICAgdmlkZW89ImRybS1j
bGllbnQtaWQ6IDdcbmRybS1lbmdpbmUtdmlkZW86IDIwMDAwMDAwMCBuc1xuIjsKKyAgICAgICAg
d3JpdGUoIi9wcm9jL3NlbGYvZmRpbmZvLzEiLHZpZGVvKTsgd3JpdGUoIi9wcm9jL3NlbGYvZmRp
bmZvLzIiLHZpZGVvKTsKKyAgICAgICAgd3JpdGUoIi9wcm9jL25ldC9kZXYiLCJ3bGFuMDogMTA0
OTU3NiAwIDAgMCAwIDAgMCAwIDUyNjI4OCAwIDAgMCAwIDAgMCAwXG4iKTsKKyAgICAgICAgYXV0
byBzZWNvbmQ9TG9jYWxIYXJkd2FyZTo6c2FtcGxlKHJvb3QucGF0aCgpKTsgUUNPTVBBUkUoc2Vj
b25kWyJjcHVQZXJjZW50Il0udG9Eb3VibGUoKSw1MC4wKTsKKyAgICAgICAgUVZFUklGWShzZWNv
bmRbInZpZGVvUGVyY2VudCJdLnRvRG91YmxlKCk+NSAmJiBzZWNvbmRbInZpZGVvUGVyY2VudCJd
LnRvRG91YmxlKCk8MTEpOyAvLyBkdXBsaWNhdGUgZmQgbXVzdCBub3QgZG91YmxlLWNvdW50Cisg
ICAgICAgIFFWRVJJRlkoc2Vjb25kWyJyZWNlaXZlTWlCIl0udG9Eb3VibGUoKT4uNSAmJiBzZWNv
bmRbInJlY2VpdmVNaUIiXS50b0RvdWJsZSgpPDEuMSk7CisgICAgICAgIFFUZXN0OjpxV2FpdCgx
MDUwKTsKKyAgICAgICAgd3JpdGUoIi9wcm9jL3N0YXQiLCJjcHUgMSAwIDEgMSAwIDAgMCAwXG4i
KTsgd3JpdGUoIi9wcm9jL25ldC9kZXYiLCJ3bGFuMDogMSAwIDAgMCAwIDAgMCAwIDEgMCAwIDAg
MCAwIDAgMFxuIik7CisgICAgICAgIGF1dG8gcmVzZXQ9TG9jYWxIYXJkd2FyZTo6c2FtcGxlKHJv
b3QucGF0aCgpKTsgUVZFUklGWSghcmVzZXQuY29udGFpbnMoImNwdVBlcmNlbnQiKSk7IFFWRVJJ
RlkoIXJlc2V0LmNvbnRhaW5zKCJyZWNlaXZlTWlCIikpOworICAgICAgICBRU2V0dGluZ3MoKS5z
ZXRWYWx1ZSgiZWNsaXBzZS9oYXJkd2FyZVJlZnJlc2giLDIpOworICAgIH0KKyAgICB2b2lkIGxv
Y2FsSGFyZHdhcmVVbmF2YWlsYWJsZUFuZEJvdW5kcygpIHsKKyAgICAgICAgUVRlbXBvcmFyeURp
ciByb290OyBRVkVSSUZZKHJvb3QuaXNWYWxpZCgpKTsKKyAgICAgICAgYXV0byBlbXB0eT1Mb2Nh
bEhhcmR3YXJlOjpzYW1wbGUocm9vdC5wYXRoKCkpOyBRVkVSSUZZKGVtcHR5LmlzRW1wdHkoKSk7
CisgICAgICAgIExvY2FsSGFyZHdhcmUgbW9uaXRvcjsgbW9uaXRvci5zZXRQb3NpdGlvbig5OTkp
OyBRQ09NUEFSRShtb25pdG9yLnBvc2l0aW9uKCksMyk7CisgICAgICAgIG1vbml0b3Iuc2V0T3Bh
Y2l0eSgtNSk7IFFDT01QQVJFKG1vbml0b3Iub3BhY2l0eSgpLDQwKTsKKyAgICAgICAgbW9uaXRv
ci5zZXRSZWZyZXNoU2Vjb25kcyg5OTkpOyBRQ09NUEFSRShtb25pdG9yLnJlZnJlc2hTZWNvbmRz
KCksNSk7CisgICAgICAgIG1vbml0b3Iuc2V0RmllbGRzKHsiY3B1IiwicGFzc3dvcmQiLCJtZW1v
cnkifSk7IFFDT01QQVJFKG1vbml0b3IuZmllbGRzKCksUVN0cmluZ0xpc3QoeyJjcHUiLCJtZW1v
cnkifSkpOworICAgICAgICBtb25pdG9yLnNldE92ZXJsYXkoZmFsc2UpOyBtb25pdG9yLnNldFJl
ZnJlc2hTZWNvbmRzKDIpOyBtb25pdG9yLnNldE9wYWNpdHkoODUpOworICAgIH0KKyAgICB2b2lk
IHNjYW5Qcm9ncmVzc0JlZm9yZUNvbXBsZXRpb24oKSB7CisgICAgICAgIFFUZW1wb3JhcnlEaXIg
ZGlyOyBRRmlsZSBzY3JpcHQoZGlyLmZpbGVQYXRoKCJzY2FuLnB5IikpOyBRVkVSSUZZKHNjcmlw
dC5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7CisgICAgICAgIHNjcmlwdC53cml0ZShSIlBZ
KGltcG9ydCBqc29uLHN5cyx0aW1lCitmb3IgbGluZSBpbiBzeXMuc3RkaW46CisgICAgcmVxdWVz
dD1qc29uLmxvYWRzKGxpbmUpCisgICAgaWYgcmVxdWVzdFsnYWN0aW9uJ109PSdidC1zY2FuJzoK
KyAgICAgICAgcHJpbnQoanNvbi5kdW1wcyh7J2l0ZW1zJzpbeydpZCc6J0FBOkJCOkNDOkREOkVF
OkZGJywnbmFtZSc6J0NvbnRyb2xsZXInfV0sJ3N0YXR1cyc6J1NjYW5uaW5nJ30pLGZsdXNoPVRy
dWUpCisgICAgICAgIHRpbWUuc2xlZXAoLjUpCisgICAgcHJpbnQoanNvbi5kdW1wcyh7J2l0ZW1z
JzpbeydpZCc6J0FBOkJCOkNDOkREOkVFOkZGJywnbmFtZSc6J0NvbnRyb2xsZXInfV0sJ3N0YXR1
cyc6J1JlYWR5JywnZG9uZSc6VHJ1ZX0pLGZsdXNoPVRydWUpCispUFkiKTsgc2NyaXB0LmNsb3Nl
KCk7IHFwdXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIixzY3JpcHQuZmlsZU5hbWUo
KS50b1V0ZjgoKSk7CisgICAgICAgIFN5c3RlbUNvbnRyb2xzIGM7IGMub3BlbigiYnQiKTsgUVRS
WV9WRVJJRlkoIWMuYnVzeSgpICYmICFjLml0ZW1zKCkuaXNFbXB0eSgpKTsKKyAgICAgICAgYy5y
ZXF1ZXN0KCJidC1zY2FuIik7IFFUUllfQ09NUEFSRShjLnN0YXR1cygpLFFTdHJpbmcoIlNjYW5u
aW5nIikpOyBRVkVSSUZZKGMuYnVzeSgpKTsgUUNPTVBBUkUoYy5pdGVtcygpLnNpemUoKSwxKTsK
KyAgICAgICAgUVRSWV9WRVJJRlkoIWMuYnVzeSgpKTsgYy5jbG9zZSgpOyBxdW5zZXRlbnYoIk1P
T05MSUdIVF9DT05UUk9MU19GSVhUVVJFIik7CisgICAgfQorICAgIHZvaWQgaWNvblJlc291cmNl
cygpIHsKKyAgICAgICAgZm9yIChjb25zdCBRU3RyaW5nJiBuYW1lIDogeyJlY2xpcHNlLWljb24i
LCAiZWNsaXBzZS1jb250cm9scyIsICJlY2xpcHNlLXBvd2VyIiwgImNyaW1zb24tbmV0d29yayIs
ICJjcmltc29uLWJsdWV0b290aCIsICJjcmltc29uLWJhdHRlcnkiLCAiY3JpbXNvbi1ob3N0Iiwg
InNldHRpbmdzIn0pIHsKKyAgICAgICAgICAgIGNvbnN0IFFTdHJpbmcgcGF0aCA9ICI6L3Jlcy8i
ICsgbmFtZSArICIuc3ZnIjsKKyAgICAgICAgICAgIFFWRVJJRlkyKFFGaWxlOjpleGlzdHMocGF0
aCksIHFQcmludGFibGUocGF0aCkpOworICAgICAgICAgICAgUUltYWdlUmVhZGVyIHJlYWRlcihw
YXRoKTsKKyAgICAgICAgICAgIFFWRVJJRlkyKCFyZWFkZXIucmVhZCgpLmlzTnVsbCgpLCBxUHJp
bnRhYmxlKHBhdGggKyAiOiAiICsgcmVhZGVyLmVycm9yU3RyaW5nKCkpKTsKKyAgICAgICAgfQor
ICAgIH0KKyAgICB2b2lkIHFtbFBhbGV0dGVBbmRQYW5lbHMoKSB7CisgICAgICAgIFFTdHJpbmcg
c291cmNlID0gcUVudmlyb25tZW50VmFyaWFibGUoIlZJQkVNSVNfVEVTVF9TT1VSQ0UiKTsgUVZF
UklGWSghc291cmNlLmlzRW1wdHkoKSk7CisgICAgICAgIFFRdWlja1N0eWxlOjpzZXRTdHlsZSgi
TWF0ZXJpYWwiKTsKKyAgICAgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlKFFVcmw6OmZyb21M
b2NhbEZpbGUoc291cmNlICsgIi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1s
IiksICJTdHJlYW1pbmdQcmVmZXJlbmNlcyIsIDEsIDAsICJTdHJlYW1pbmdQcmVmZXJlbmNlcyIp
OworICAgICAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGUoUVVybDo6ZnJvbUxvY2FsRmlsZShz
b3VyY2UgKyAiL2FwcC9ndWkvVmJUb2tlbnMucW1sIiksICJWaWJlbWlzLlJlZGVzaWduIiwgMSwg
MCwgIlZiVG9rZW5zIik7CisgICAgICAgIFFUZW1wb3JhcnlEaXIgY29udHJvbHNGaXh0dXJlOyBR
VkVSSUZZKGNvbnRyb2xzRml4dHVyZS5pc1ZhbGlkKCkpOworICAgICAgICBRRmlsZSBoZWxwZXIo
Y29udHJvbHNGaXh0dXJlLmZpbGVQYXRoKCJoZWxwZXIucHkiKSk7IFFWRVJJRlkoaGVscGVyLm9w
ZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsKKyAgICAgICAgaGVscGVyLndyaXRlKFIiUFkoaW1w
b3J0IGpzb24sc3lzCitmb3IgbGluZSBpbiBzeXMuc3RkaW46CisgICAgdmFsdWU9anNvbi5sb2Fk
cyhsaW5lKQorICAgIHByaW50KGpzb24uZHVtcHMoeydzdGF0ZSc6eyd2b2x1bWUnOjUwLCdtdXRl
ZCc6RmFsc2UsJ3dpZmlfZW5hYmxlZCc6VHJ1ZSwnYmx1ZXRvb3RoX2VuYWJsZWQnOlRydWUsJ2Rp
c3BsYXlzJzpbeydpZCc6J2VEUC0xfDEwMjR4NjQwfDYwJywnbmFtZSc6J2VEUC0xIMK3IDEwMjTD
lzY0MCDCtyA2MCBIeicsJ2N1cnJlbnQnOlRydWV9XSwncG9pbnRlcnMnOlt7J2lkJzonMTInLCdu
YW1lJzonVG91Y2hwYWQnLCdzcGVlZCc6MCwnbmF0dXJhbCc6VHJ1ZSwndGFwJzpUcnVlfV0sJ3Np
bmtzJzpbeydpZCc6JzQyJywnbmFtZSc6J1NwZWFrZXJzJywnZGVmYXVsdCc6VHJ1ZX0seydpZCc6
JzU3JywnbmFtZSc6J0FpclBvZHMnLCdkZWZhdWx0JzpGYWxzZX1dLCdicmlnaHRuZXNzJzp7J3Nj
cmVlbic6eydkZXZpY2UnOidpbnRlbF9iYWNrbGlnaHQnLCdwZXJjZW50Jzo2MH0sJ2tleWJvYXJk
Jzp7J2RldmljZSc6J3NwaTo6a2JkX2JhY2tsaWdodCcsJ3BlcmNlbnQnOjMwfX0sJ29zJzp7J05B
TUUnOidFY2xpcHNlT1MnLCdWRVJTSU9OJzonMC4zLWRldicsJ1RBUkdFVCc6J0ZpeHR1cmUgaGFy
ZHdhcmUnLCdGRURPUkEnOic0NCd9LCdrZXJuZWwnOidmaXh0dXJlLWtlcm5lbCd9LCdpdGVtcyc6
W3snaWQnOidmaXh0dXJlJywnbmFtZSc6J0ZpeHR1cmUgZGV2aWNlJywnZGV0YWlsJzonQXZhaWxh
YmxlJywnY29ubmVjdGVkJzpUcnVlfV0sJ3N0YXR1cyc6J1JlYWR5JywnZG9uZSc6VHJ1ZX0pLGZs
dXNoPVRydWUpCispUFkiKTsgaGVscGVyLmNsb3NlKCk7CisgICAgICAgIHFwdXRlbnYoIk1PT05M
SUdIVF9DT05UUk9MU19GSVhUVVJFIixoZWxwZXIuZmlsZU5hbWUoKS50b1V0ZjgoKSk7CisgICAg
ICAgIHFtbFJlZ2lzdGVyVHlwZTxVaUNvbXB1dGVyTW9kZWw+KCJDb21wdXRlck1vZGVsIiwxLDAs
IkNvbXB1dGVyTW9kZWwiKTsKKyAgICAgICAgcW1sUmVnaXN0ZXJUeXBlPFVpQXBwTW9kZWw+KCJB
cHBNb2RlbCIsMSwwLCJBcHBNb2RlbCIpOworICAgICAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5
cGUoUVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UrIi9hcHAvZ3VpL1RoZW1lLnFtbCIpLCJUaGVt
ZSIsMSwwLCJUaGVtZSIpOworICAgICAgICBmb3IoY29uc3QgUVN0cmluZyYgbW9kdWxlOlFTdHJp
bmdMaXN0eyJDb21wdXRlck1hbmFnZXIiLCJBcHBQcm9maWxlTWFuYWdlciIsIlN5c3RlbVByb3Bl
cnRpZXMiLCJTZGxHYW1lcGFkS2V5TmF2aWdhdGlvbiIsIlVpU291bmRNYW5hZ2VyIiwiU2VydmVy
Q29tbWFuZE1hbmFnZXIifSkKKyAgICAgICAgICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9uVHlwZShR
VXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSsiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9VaVNlcnZp
Y2VzLnFtbCIpLG1vZHVsZS50b1V0ZjgoKS5jb25zdERhdGEoKSwxLDAsbW9kdWxlLnRvVXRmOCgp
LmNvbnN0RGF0YSgpKTsKKyAgICAgICAgUVFtbEVuZ2luZSBlbmdpbmU7CisgICAgICAgIFFTaWdu
YWxTcHkgcW1sV2FybmluZ3MoJmVuZ2luZSwmUVFtbEVuZ2luZTo6d2FybmluZ3MpOworICAgICAg
ICBRUW1sQ29tcG9uZW50IGNvbXBvbmVudCgmZW5naW5lLCBRVXJsOjpmcm9tTG9jYWxGaWxlKHNv
dXJjZSArICIvYXBwL21vb25saWdodG9zL3Rlc3RzL0hhcm5lc3MucW1sIikpOworICAgICAgICBR
U2NvcGVkUG9pbnRlcjxRT2JqZWN0PiByb290KGNvbXBvbmVudC5jcmVhdGUoKSk7IFFWRVJJRlky
KHJvb3QsIHFQcmludGFibGUoY29tcG9uZW50LmVycm9yU3RyaW5nKCkpKTsKKyAgICAgICAgYXV0
byBwYW5lbCA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oInRlc3RQYW5lbCIpOyBRVkVSSUZZ
KHBhbmVsKTsKKyAgICAgICAgYXV0byBzdGF0ZSA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4o
InRlc3RTdGF0ZSIpOyBRVkVSSUZZKHN0YXRlKTsKKyAgICAgICAgZm9yIChpbnQgaSA9IDA7IGkg
PCAxNjsgKytpKSB7CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRo
b2Qocm9vdC5kYXRhKCksICJjaG9vc2VBY2NlbnQiLCBRX0FSRyhRVmFyaWFudCwgaSkpKTsKKyAg
ICAgICAgICAgIFFDT01QQVJFKHN0YXRlLT5wcm9wZXJ0eSgiYWNjZW50IikudmFsdWU8UUNvbG9y
PigpLnJnYigpLEVjbGlwc2VPdmVybGF5U3R5bGU6OmFjY2VudChpKS5yZ2IoKSk7CisgICAgICAg
ICAgICBRVkVSSUZZKHN0YXRlLT5wcm9wZXJ0eSgicHJlc3NlZCIpLnZhbHVlPFFDb2xvcj4oKS5p
c1ZhbGlkKCkpOworICAgICAgICB9CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9r
ZU1ldGhvZChyb290LmRhdGEoKSwgImNob29zZUFjY2VudCIsIFFfQVJHKFFWYXJpYW50LCA0KSkp
OworICAgICAgICBmb3IgKFFTdHJpbmcga2luZCA6IHsibmV0d29yayIsICJiYXR0ZXJ5IiwgImhv
c3QifSkgeworICAgICAgICAgICAgUVZFUklGWShwYW5lbC0+c2V0UHJvcGVydHkoImtpbmQiLCBr
aW5kKSk7CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QocGFu
ZWwsICJvcGVuIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgICAgIFFWRVJJRlkocGFu
ZWwtPnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAgICAgICAgUVN0cmluZyBv
dXQgPSBxRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9TQ1JFRU5TSE9UUyIpOworICAgICAg
ICAgICAgaWYgKCFvdXQuaXNFbXB0eSgpKSB7CisgICAgICAgICAgICAgICAgUURpcigpLm1rcGF0
aChvdXQpOworICAgICAgICAgICAgICAgIGF1dG8gd2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlj
a1dpbmRvdyo+KHJvb3QuZGF0YSgpKTsgUVZFUklGWSh3aW5kb3cpOworICAgICAgICAgICAgICAg
IFFWRVJJRlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQgKyAiLyIgKyBraW5kICsgIi5w
bmciKSk7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0Ojpp
bnZva2VNZXRob2QocGFuZWwsICJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAg
IH0KKyAgICAgICAgYXV0byBjb25uZWN0aW9ucyA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4o
ImNvbm5lY3Rpb25zUGFuZWwiKTsgUVZFUklGWShjb25uZWN0aW9ucyk7CisgICAgICAgIGZvciAo
UVN0cmluZyBraW5kIDogeyJ3aWZpIiwgImJ0In0pIHsKKyAgICAgICAgICAgIHJvb3QtPnNldFBy
b3BlcnR5KCJ3aWR0aCIsIDEwMjQpOyByb290LT5zZXRQcm9wZXJ0eSgiaGVpZ2h0IiwgNjQwKTsK
KyAgICAgICAgICAgIFFWRVJJRlkoY29ubmVjdGlvbnMtPnNldFByb3BlcnR5KCJraW5kIiwga2lu
ZCkpOworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNvbm5l
Y3Rpb25zLCAib3BlbiIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICBRVkVSSUZZ
KGNvbm5lY3Rpb25zLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsKKyAgICAgICAgICAg
IFFWRVJJRlkoY29ubmVjdGlvbnMtPnByb3BlcnR5KCJ3aWR0aCIpLnRvSW50KCkgPD0gOTkyKTsK
KyAgICAgICAgICAgIFFTdHJpbmcgb3V0ID0gcUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05f
U0NSRUVOU0hPVFMiKTsKKyAgICAgICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgeworICAgICAg
ICAgICAgICAgIGF1dG8gd2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3Qu
ZGF0YSgpKTsgUVZFUklGWSh3aW5kb3cpOworICAgICAgICAgICAgICAgIFFWRVJJRlkod2luZG93
LT5ncmFiV2luZG93KCkuc2F2ZShvdXQgKyAiLyIgKyBraW5kICsgIi1zZWxlY3Rvci5wbmciKSk7
CisgICAgICAgICAgICB9CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VN
ZXRob2QoY29ubmVjdGlvbnMsICJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAg
IH0KKyAgICAgICAgYXV0byBjbGlja0RpYWxvZ0J1dHRvbj1bXShRT2JqZWN0KiBkaWFsb2csY29u
c3QgUVN0cmluZyYgdGV4dCkgeworICAgICAgICAgICAgYXV0byBmb290ZXI9ZGlhbG9nLT5wcm9w
ZXJ0eSgiZm9vdGVyIikudmFsdWU8UU9iamVjdCo+KCk7IGlmKCFmb290ZXIpIHJldHVybiBmYWxz
ZTsKKyAgICAgICAgICAgIGZvcihhdXRvIGNoaWxkOmZvb3Rlci0+ZmluZENoaWxkcmVuPFFPYmpl
Y3QqPigpKSBpZihjaGlsZC0+cHJvcGVydHkoInRleHQiKS50b1N0cmluZygpPT10ZXh0ICYmIGNo
aWxkLT5tZXRhT2JqZWN0KCktPmluZGV4T2ZTaWduYWwoImNsaWNrZWQoKSIpPj0wKSByZXR1cm4g
UU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChjaGlsZCwiY2xpY2tlZCIpOworICAgICAgICAgICAg
cmV0dXJuIGZhbHNlOworICAgICAgICB9OworICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0Ojpp
bnZva2VNZXRob2QoY29ubmVjdGlvbnMsIm9wZW4iKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAg
ICAgICBmb3IoY29uc3QgUVN0cmluZyYgbmFtZTp7ImNvbm5lY3Rpb25DcmVkZW50aWFsIiwiY29u
bmVjdGlvbkZvcmdldCJ9KSB7CisgICAgICAgICAgICBhdXRvIGRpYWxvZz1yb290LT5maW5kQ2hp
bGQ8UU9iamVjdCo+KG5hbWUpOyBRVkVSSUZZKGRpYWxvZyk7CisgICAgICAgICAgICBRVkVSSUZZ
KFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoZGlhbG9nLCJvcGVuIikpOyBRVGVzdDo6cVdhaXQo
MzAwKTsKKyAgICAgICAgICAgIFFWRVJJRlkoZGlhbG9nLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRv
Qm9vbCgpKTsKKyAgICAgICAgICAgIFFTdHJpbmcgZGVzdGluYXRpb249cUVudmlyb25tZW50VmFy
aWFibGUoIkNSSU1TT05fU0NSRUVOU0hPVFMiKTsKKyAgICAgICAgICAgIGlmKCFkZXN0aW5hdGlv
bi5pc0VtcHR5KCkpIFFWRVJJRlkocW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0
YSgpKS0+Z3JhYldpbmRvdygpLnNhdmUoZGVzdGluYXRpb24rIi8iK25hbWUrIi5wbmciKSk7Cisg
ICAgICAgICAgICBRVkVSSUZZKGNsaWNrRGlhbG9nQnV0dG9uKGRpYWxvZyxuYW1lPT0iY29ubmVj
dGlvbkNyZWRlbnRpYWwiPyJDYW5jZWwiOiJObyIpKTsKKyAgICAgICAgICAgIFFUZXN0OjpxV2Fp
dCg0MDApOyBRVkVSSUZZMighZGlhbG9nLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpLHFQ
cmludGFibGUobmFtZSkpOworICAgICAgICB9CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6
Omludm9rZU1ldGhvZChjb25uZWN0aW9ucywiY2xvc2UiKSk7IFFUZXN0OjpxV2FpdCgyMDApOwor
ICAgICAgICBRUW1sQ29tcG9uZW50IGFjdGlvbkNvbXBvbmVudCgmZW5naW5lLFFVcmw6OmZyb21M
b2NhbEZpbGUoc291cmNlKyIvYXBwL2d1aS9FY2xpcHNlQWN0aW9uQnV0dG9uLnFtbCIpKTsKKyAg
ICAgICAgUVNjb3BlZFBvaW50ZXI8UU9iamVjdD4gYWN0aW9uKGFjdGlvbkNvbXBvbmVudC5jcmVh
dGUoKSk7IFFWRVJJRlkyKGFjdGlvbixxUHJpbnRhYmxlKGFjdGlvbkNvbXBvbmVudC5lcnJvclN0
cmluZygpKSk7CisgICAgICAgIGF1dG8gYWN0aW9uSXRlbSA9IHFvYmplY3RfY2FzdDxRUXVpY2tJ
dGVtKj4oYWN0aW9uLmRhdGEoKSk7IFFWRVJJRlkoYWN0aW9uSXRlbSk7CisgICAgICAgIGF1dG8g
YWN0aW9uV2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgpKTsg
UVZFUklGWShhY3Rpb25XaW5kb3cpOworICAgICAgICBhY3Rpb25JdGVtLT5zZXRQYXJlbnRJdGVt
KGFjdGlvbldpbmRvdy0+Y29udGVudEl0ZW0oKSk7IGFjdGlvbkl0ZW0tPmZvcmNlQWN0aXZlRm9j
dXMoKTsKKyAgICAgICAgUVNpZ25hbFNweSBhY3RpdmF0ZWQoYWN0aW9uLmRhdGEoKSxTSUdOQUwo
Y2xpY2tlZCgpKSk7CisgICAgICAgIFFUZXN0OjprZXlDbGljayhhY3Rpb25XaW5kb3csUXQ6Oktl
eV9SZXR1cm4pOyBRQ09NUEFSRShhY3RpdmF0ZWQuY291bnQoKSwxKTsKKyAgICAgICAgYWN0aW9u
SXRlbS0+c2V0VmlzaWJsZShmYWxzZSk7CisgICAgICAgIGF1dG8gY2VudGVyID0gcm9vdC0+Zmlu
ZENoaWxkPFFPYmplY3QqPigiY29udHJvbENlbnRlciIpOyBRVkVSSUZZKGNlbnRlcik7CisgICAg
ICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChjZW50ZXIsIm9wZW4iKSk7IFFU
ZXN0OjpxV2FpdCg1MDApOworICAgICAgICBRVkVSSUZZKGNlbnRlci0+cHJvcGVydHkoInZpc2li
bGUiKS50b0Jvb2woKSk7CisgICAgICAgIFFTdHJpbmcgb3V0ID0gcUVudmlyb25tZW50VmFyaWFi
bGUoIkNSSU1TT05fU0NSRUVOU0hPVFMiKTsKKyAgICAgICAgYXV0byB3aW5kb3cgPSBxb2JqZWN0
X2Nhc3Q8UVF1aWNrV2luZG93Kj4ocm9vdC5kYXRhKCkpOyBRVkVSSUZZKHdpbmRvdyk7CisgICAg
ICAgIGlmICghb3V0LmlzRW1wdHkoKSkgUVZFUklGWSh3aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZl
KG91dCsiL2VjbGlwc2UtY29udHJvbC1jZW50ZXIucG5nIikpOworICAgICAgICBRVkVSSUZZKFFN
ZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY2VudGVyLCJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMw
MCk7CisgICAgICAgIGZvcihjb25zdCBRU3RyaW5nJiB2aWV3OlFTdHJpbmdMaXN0eyJQY1ZpZXci
LCJBcHBWaWV3In0pIHsKKyAgICAgICAgICAgIGZvcihpbnQgc2NhbGU6ezEwMCwxMTAsMTI1fSkg
eworICAgICAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290
LmRhdGEoKSwiY2hvb3NlU2NhbGUiLFFfQVJHKFFWYXJpYW50LHNjYWxlKSkpOworICAgICAgICAg
ICAgICAgIGZvcihRU2l6ZSBzaXplOntRU2l6ZSgxOTIwLDEwODApLFFTaXplKDEyODAsNzIwKSxR
U2l6ZSg5MDAsNjQwKX0pIHsKKyAgICAgICAgICAgICAgICAgICAgcm9vdC0+c2V0UHJvcGVydHko
IndpZHRoIixzaXplLndpZHRoKCkpO3Jvb3QtPnNldFByb3BlcnR5KCJoZWlnaHQiLHNpemUuaGVp
Z2h0KCkpOworICAgICAgICAgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VN
ZXRob2Qocm9vdC5kYXRhKCksInNob3dQcm9kdWN0aW9uVmlldyIsUV9BUkcoUVZhcmlhbnQsdmll
dykpKTtRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgICAgICAgICAgICAgYXV0byBzdGFjaz1y
b290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJwcm9kdWN0aW9uU3RhY2siKTtRVkVSSUZZKHN0YWNr
KTthdXRvIGl0ZW09c3RhY2stPnByb3BlcnR5KCJjdXJyZW50SXRlbSIpLnZhbHVlPFFPYmplY3Qq
PigpO1FWRVJJRlkoaXRlbSk7CisgICAgICAgICAgICAgICAgICAgIFFWRVJJRlkoaXRlbS0+cHJv
cGVydHkoImF2YWlsYWJsZVdpZHRoIikudG9Eb3VibGUoKT4zMDApOworICAgICAgICAgICAgICAg
ICAgICBRQ09NUEFSRShpdGVtLT5wcm9wZXJ0eSgiY291bnQiKS50b0ludCgpLHZpZXc9PSJQY1Zp
ZXciPzI6Nik7CisgICAgICAgICAgICAgICAgICAgIGF1dG8gZ3JpZD1xb2JqZWN0X2Nhc3Q8UVF1
aWNrSXRlbSo+KGl0ZW0pO1FWRVJJRlkoZ3JpZCk7CisgICAgICAgICAgICAgICAgICAgIGdyaWQt
PmZvcmNlQWN0aXZlRm9jdXMoKTtpdGVtLT5zZXRQcm9wZXJ0eSgiY3VycmVudEluZGV4IiwwKTsK
KyAgICAgICAgICAgICAgICAgICAgUVRlc3Q6OmtleUNsaWNrKHdpbmRvdyxRdDo6S2V5X1JpZ2h0
KTsKKyAgICAgICAgICAgICAgICAgICAgUVZFUklGWShpdGVtLT5wcm9wZXJ0eSgiY3VycmVudElu
ZGV4IikudG9JbnQoKT4wKTsKKyAgICAgICAgICAgICAgICAgICAgZm9yKGF1dG8gYnV0dG9uOml0
ZW0tPmZpbmRDaGlsZHJlbjxRUXVpY2tJdGVtKj4oImNyaW1zb25SYWlsQnV0dG9uIikpIHsKKyAg
ICAgICAgICAgICAgICAgICAgICAgIFFWRVJJRlkoYnV0dG9uLT53aWR0aCgpPj01Nik7YnV0dG9u
LT5mb3JjZUFjdGl2ZUZvY3VzKCk7UVZFUklGWShidXR0b24tPmhhc0FjdGl2ZUZvY3VzKCkpOwor
ICAgICAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgICAgIGdyaWQtPmZvcmNlQWN0
aXZlRm9jdXMoKTtpdGVtLT5zZXRQcm9wZXJ0eSgiY3VycmVudEluZGV4IiwtMSk7CisgICAgICAg
ICAgICAgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKVFWRVJJRlkod2luZG93LT5ncmFiV2luZG93
KCkuc2F2ZShvdXQrIi9jcmltc29uLWdsYXNzLSIrdmlldysiLSIrUVN0cmluZzo6bnVtYmVyKHNp
emUud2lkdGgoKSkrIi0iK1FTdHJpbmc6Om51bWJlcihzY2FsZSkrIi5wbmciKSk7CisgICAgICAg
ICAgICAgICAgfQorICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgICAgIHJvb3QtPnNldFBy
b3BlcnR5KCJ3aWR0aCIsMTkyMCk7cm9vdC0+c2V0UHJvcGVydHkoImhlaWdodCIsMTA4MCk7Cisg
ICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwic2hv
d1Byb2R1Y3Rpb25WaWV3IixRX0FSRyhRVmFyaWFudCxRU3RyaW5nKCJBcHBWaWV3IikpKSk7Cisg
ICAgICAgIGZvcihpbnQgYWNjZW50PTA7YWNjZW50PDE2O2FjY2VudCsrKSB7CisgICAgICAgICAg
ICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29zZUFj
Y2VudCIsUV9BUkcoUVZhcmlhbnQsYWNjZW50KSkpO1FUZXN0OjpxV2FpdCgzMCk7CisgICAgICAg
ICAgICBpZighb3V0LmlzRW1wdHkoKSlRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUo
b3V0KyIvY3JpbXNvbi1nbGFzcy1hY2NlbnQtIitRU3RyaW5nOjpudW1iZXIoYWNjZW50KSsiLnBu
ZyIpKTsKKyAgICAgICAgfQorICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRo
b2Qocm9vdC5kYXRhKCksImNob29zZUFjY2Vzc2liaWxpdHkiLFFfQVJHKFFWYXJpYW50LHRydWUp
LFFfQVJHKFFWYXJpYW50LHRydWUpKSk7UVRlc3Q6OnFXYWl0KDEwMCk7CisgICAgICAgIGlmKCFv
dXQuaXNFbXB0eSgpKVFWRVJJRlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQrIi9jcmlt
c29uLWdsYXNzLWhpZ2gtY29udHJhc3QucG5nIikpOworICAgICAgICBRVkVSSUZZKFFNZXRhT2Jq
ZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29zZUFjY2Vzc2liaWxpdHkiLFFfQVJH
KFFWYXJpYW50LGZhbHNlKSxRX0FSRyhRVmFyaWFudCxmYWxzZSkpKTsKKyAgICAgICAgUVZFUklG
WShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VBY2NlbnQiLFFf
QVJHKFFWYXJpYW50LDQpKSk7CisgICAgICAgIFFUZW1wb3JhcnlEaXIgd2FsbHBhcGVyRm9sZGVy
O1FWRVJJRlkod2FsbHBhcGVyRm9sZGVyLmlzVmFsaWQoKSk7CisgICAgICAgIFFJbWFnZSB3YWxs
cGFwZXIoMTkyMCwxMDgwLFFJbWFnZTo6Rm9ybWF0X1JHQjMyKTsKKyAgICAgICAge1FQYWludGVy
IHBhaW50ZXIoJndhbGxwYXBlcik7UUxpbmVhckdyYWRpZW50IGdyYWRpZW50KDAsMCwxOTIwLDEw
ODApO2dyYWRpZW50LnNldENvbG9yQXQoMCxRQ29sb3IoIiMzMjExMjIiKSk7Z3JhZGllbnQuc2V0
Q29sb3JBdCgxLFFDb2xvcigiIzE1MUQ0MiIpKTtwYWludGVyLmZpbGxSZWN0KHdhbGxwYXBlci5y
ZWN0KCksZ3JhZGllbnQpO3BhaW50ZXIuc2V0UGVuKFFQZW4oUUNvbG9yKCIjOUQzNTU1IiksOCkp
O3BhaW50ZXIuZHJhd0VsbGlwc2UoUVBvaW50RigxMTUwLDU1MCksNTUwLDU1MCk7fQorICAgICAg
ICBRU3RyaW5nIHdhbGxwYXBlclBhdGg9d2FsbHBhcGVyRm9sZGVyLmZpbGVQYXRoKCJmaXh0dXJl
LWJhY2tncm91bmQucG5nIik7UVZFUklGWSh3YWxscGFwZXIuc2F2ZSh3YWxscGFwZXJQYXRoKSk7
CisgICAgICAgIFFWYXJpYW50IHNlbGVjdGVkO1FWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1l
dGhvZChyb290LmRhdGEoKSwiY2hvb3NlV2FsbHBhcGVyIixRX1JFVFVSTl9BUkcoUVZhcmlhbnQs
c2VsZWN0ZWQpLFFfQVJHKFFWYXJpYW50LFFVcmw6OmZyb21Mb2NhbEZpbGUod2FsbHBhcGVyUGF0
aCkpKSk7UVZFUklGWShzZWxlY3RlZC50b0Jvb2woKSk7CisgICAgICAgIFFUZXN0OjpxV2FpdCgy
NTApOworICAgICAgICBpZighb3V0LmlzRW1wdHkoKSlRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRv
dygpLnNhdmUob3V0KyIvY3JpbXNvbi1nbGFzcy1zZWxlY3RlZC1iYWNrZ3JvdW5kLnBuZyIpKTsK
KyAgICAgICAgY29uc3QgYXV0byB3YWxscGFwZXJzPXJvb3QtPmZpbmRDaGlsZHJlbjxRT2JqZWN0
Kj4oImNyaW1zb25XYWxscGFwZXIiKTtRVkVSSUZZKCF3YWxscGFwZXJzLmlzRW1wdHkoKSk7Cisg
ICAgICAgIFFMaXN0PHN0ZDo6c2hhcmVkX3B0cjxRU2lnbmFsU3B5Pj4gaW1hZ2VDaGFuZ2VzOwor
ICAgICAgICBmb3IoYXV0byB3YWxscGFwZXI6d2FsbHBhcGVycykgeworICAgICAgICAgICAgYXV0
byBwcm9wZXJ0eT13YWxscGFwZXItPm1ldGFPYmplY3QoKS0+cHJvcGVydHkod2FsbHBhcGVyLT5t
ZXRhT2JqZWN0KCktPmluZGV4T2ZQcm9wZXJ0eSgic291cmNlIikpOworICAgICAgICAgICAgYXV0
byBzcHk9c3RkOjptYWtlX3NoYXJlZDxRU2lnbmFsU3B5Pih3YWxscGFwZXIscHJvcGVydHkubm90
aWZ5U2lnbmFsKCkpO1FWRVJJRlkoc3B5LT5pc1ZhbGlkKCkpO2ltYWdlQ2hhbmdlcy5hcHBlbmQo
c3B5KTsKKyAgICAgICAgfQorICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRo
b2Qocm9vdC5kYXRhKCksImNob29zZURpbW1pbmciLFFfQVJHKFFWYXJpYW50LDQ1KSkpOworICAg
ICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29z
ZVNjYWxlIixRX0FSRyhRVmFyaWFudCwxMTApKSk7UVRlc3Q6OnFXYWl0KDEwMCk7CisgICAgICAg
IGZvcihjb25zdCBhdXRvJiBzcHk6aW1hZ2VDaGFuZ2VzKVFDT01QQVJFKHNweS0+Y291bnQoKSww
KTsgLy8gZGltbWluZy90eXBlIGNoYW5nZXMgbXVzdCBub3QgcmVsb2FkIHRoZSBpbWFnZQorICAg
ICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29z
ZURpbW1pbmciLFFfQVJHKFFWYXJpYW50LDY1KSkpOworICAgICAgICBRVkVSSUZZKFFNZXRhT2Jq
ZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29zZVNjYWxlIixRX0FSRyhRVmFyaWFu
dCwxMjUpKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290
LmRhdGEoKSwicmVzZXRXYWxscGFwZXIiKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6
Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiaGlkZVByb2R1Y3Rpb25WaWV3IikpOworICAgICAg
ICBhdXRvIHF1aWNrTWVudT1yb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJxdWlja01lbnVMb2Fk
ZXIiKTtRVkVSSUZZKHF1aWNrTWVudSk7cXVpY2tNZW51LT5zZXRQcm9wZXJ0eSgiYWN0aXZlIix0
cnVlKTtRVGVzdDo6cVdhaXQoMTUwKTsKKyAgICAgICAgUVZFUklGWShxdWlja01lbnUtPnByb3Bl
cnR5KCJpdGVtIikudmFsdWU8UU9iamVjdCo+KCkpOworICAgICAgICBRVGVzdDo6a2V5Q2xpY2so
d2luZG93LFF0OjpLZXlfRG93bik7CisgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKVFWRVJJRlko
d2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQrIi9jcmltc29uLWdsYXNzLXF1aWNrLW1lbnUu
cG5nIikpOworICAgICAgICBxdWlja01lbnUtPnNldFByb3BlcnR5KCJhY3RpdmUiLGZhbHNlKTsK
KyAgICAgICAgUUNPTVBBUkUocW1sV2FybmluZ3MuY291bnQoKSwwKTsKKyAgICAgICAgYXV0byBk
YXNoYm9hcmQ9cm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigiZ2xhc3NEYXNoYm9hcmQiKTtRVkVS
SUZZKGRhc2hib2FyZCk7CisgICAgICAgIGZvcihpbnQgc2NhbGU6ezEwMCwxMTAsMTI1fSkgewor
ICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgp
LCJjaG9vc2VTY2FsZSIsUV9BUkcoUVZhcmlhbnQsc2NhbGUpKSk7CisgICAgICAgICAgICBmb3Io
UVNpemUgc2l6ZTp7UVNpemUoMTkyMCwxMDgwKSxRU2l6ZSgxMjgwLDcyMCksUVNpemUoOTAwLDY0
MCl9KSB7CisgICAgICAgICAgICAgICAgcm9vdC0+c2V0UHJvcGVydHkoIndpZHRoIixzaXplLndp
ZHRoKCkpO3Jvb3QtPnNldFByb3BlcnR5KCJoZWlnaHQiLHNpemUuaGVpZ2h0KCkpO2Rhc2hib2Fy
ZC0+c2V0UHJvcGVydHkoInZpc2libGUiLHRydWUpO1FUZXN0OjpxV2FpdCgyNTApOworICAgICAg
ICAgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKVFWRVJJRlkod2luZG93LT5ncmFiV2luZG93KCku
c2F2ZShvdXQrIi9jcmltc29uLWdsYXNzLWRhc2hib2FyZC0iK1FTdHJpbmc6Om51bWJlcihzaXpl
LndpZHRoKCkpKyItIitRU3RyaW5nOjpudW1iZXIoc2NhbGUpKyIucG5nIikpOworICAgICAgICAg
ICAgICAgIGF1dG8gY2FyZHM9ZGFzaGJvYXJkLT5maW5kQ2hpbGRyZW48UVF1aWNrSXRlbSo+KCJj
cmltc29uTWV0cmljIik7Zm9yKGF1dG8gY2FyZDpjYXJkcylRVkVSSUZZKGNhcmQtPndpZHRoKCk+
MTAwKTsKKyAgICAgICAgICAgICAgICBhdXRvIGhvc3Q9ZGFzaGJvYXJkLT5maW5kQ2hpbGQ8UVF1
aWNrSXRlbSo+KCJnbGFzc0hvc3QiKTtRVkVSSUZZKGhvc3QpO1FWRVJJRlkoaG9zdC0+d2lkdGgo
KT49MCk7CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICAgICAgZGFzaGJvYXJkLT5zZXRQ
cm9wZXJ0eSgidmlzaWJsZSIsZmFsc2UpOworICAgICAgICBhdXRvIHBpY2tlcj1yb290LT5maW5k
Q2hpbGQ8UU9iamVjdCo+KCJnbGFzc0JhY2tncm91bmRQaWNrZXIiKTtRVkVSSUZZKHBpY2tlcik7
UVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHBpY2tlciwib3BlbiIpKTtRVGVzdDo6
cVdhaXQoMTUwKTtRVkVSSUZZKHBpY2tlci0+cHJvcGVydHkoInZpc2libGUiKS50b0Jvb2woKSk7
CisgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKVFWRVJJRlkod2luZG93LT5ncmFiV2luZG93KCku
c2F2ZShvdXQrIi9jcmltc29uLWdsYXNzLWJhY2tncm91bmQtcGlja2VyLnBuZyIpKTsKKyAgICAg
ICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHBpY2tlciwiY2xvc2UiKSk7Cisg
ICAgICAgIGF1dG8gYWJvdXQgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJhYm91dEVjbGlw
c2UiKTsgUVZFUklGWShhYm91dCk7CisgICAgICAgIGFib3V0LT5zZXRQcm9wZXJ0eSgiaW5mbyIs
IFFWYXJpYW50TWFwe3sib3MiLFFWYXJpYW50TWFwe3siTkFNRSIsIkVjbGlwc2VPUyJ9LHsiVkVS
U0lPTiIsIjAuMy1kZXYifSx7IlRBUkdFVCIsIkZpeHR1cmUgaGFyZHdhcmUifSx7IkZFRE9SQSIs
IjQ0In19fSx7Imtlcm5lbCIsImZpeHR1cmUta2VybmVsIn19KTsKKyAgICAgICAgUVZFUklGWShR
TWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGFib3V0LCJvcGVuIikpOyBRVGVzdDo6cVdhaXQoMzAw
KTsKKyAgICAgICAgUVZFUklGWShhYm91dC0+cHJvcGVydHkoInZpc2libGUiKS50b0Jvb2woKSk7
CisgICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgUVZFUklGWSh3aW5kb3ctPmdyYWJXaW5kb3co
KS5zYXZlKG91dCsiL2VjbGlwc2UtYWJvdXQucG5nIikpOworICAgICAgICBRVkVSSUZZKFFNZXRh
T2JqZWN0OjppbnZva2VNZXRob2QoYWJvdXQsImNsb3NlIikpOworICAgICAgICBhdXRvIHN5c3Rl
bT1yb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJzeXN0ZW1TZXR0aW5ncyIpOyBRVkVSSUZZKHN5
c3RlbSk7CisgICAgICAgIGZvcihpbnQgc2NhbGU6ezEwMCwxMTAsMTI1fSkgeworICAgICAgICAg
ICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VT
Y2FsZSIsUV9BUkcoUVZhcmlhbnQsc2NhbGUpKSk7CisgICAgICAgICAgICByb290LT5zZXRQcm9w
ZXJ0eSgid2lkdGgiLDEwMjQpOyByb290LT5zZXRQcm9wZXJ0eSgiaGVpZ2h0Iiw2NDApOworICAg
ICAgICAgICAgc3lzdGVtLT5zZXRQcm9wZXJ0eSgiYWN0aXZlIix0cnVlKTsgUVRlc3Q6OnFXYWl0
KDQwMCk7CisgICAgICAgICAgICBRVkVSSUZZKHN5c3RlbS0+cHJvcGVydHkoIndpZHRoIikudG9J
bnQoKTw9MTAyNCk7CisgICAgICAgICAgICBpZighb3V0LmlzRW1wdHkoKSkgUVZFUklGWSh3aW5k
b3ctPmdyYWJXaW5kb3coKS5zYXZlKG91dCsiL3N5c3RlbS1jb250cm9scy0iK1FTdHJpbmc6Om51
bWJlcihzY2FsZSkrIi5wbmciKSk7CisgICAgICAgICAgICBmb3IoaW50IGFjY2VudD0wO2FjY2Vu
dDwxNjthY2NlbnQrKykgeworICAgICAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omlu
dm9rZU1ldGhvZChyb290LmRhdGEoKSwiY2hvb3NlQWNjZW50IixRX0FSRyhRVmFyaWFudCxhY2Nl
bnQpKSk7IFFUZXN0OjpxV2FpdCgxMCk7CisgICAgICAgICAgICAgICAgUVZFUklGWShzdGF0ZS0+
cHJvcGVydHkoImFjY2VudCIpLnZhbHVlPFFDb2xvcj4oKS5pc1ZhbGlkKCkpOworICAgICAgICAg
ICAgfQorICAgICAgICAgICAgYXV0byBzY3JvbGw9cm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigi
c3lzdGVtU2Nyb2xsIik7IFFWRVJJRlkoc2Nyb2xsKTsKKyAgICAgICAgICAgIGF1dG8gZmxpY2s9
c2Nyb2xsLT5wcm9wZXJ0eSgiY29udGVudEl0ZW0iKS52YWx1ZTxRUXVpY2tJdGVtKj4oKTsgUVZF
UklGWShmbGljayk7CisgICAgICAgICAgICBhdXRvIG1vbml0b3I9cm9vdC0+ZmluZENoaWxkPFFP
YmplY3QqPigiaGFyZHdhcmVNb25pdG9yIik7IFFWRVJJRlkobW9uaXRvcik7CisgICAgICAgICAg
ICBmbGljay0+c2V0UHJvcGVydHkoImNvbnRlbnRZIixtb25pdG9yLT5wcm9wZXJ0eSgieSIpKTsg
UVRlc3Q6OnFXYWl0KDIwMCk7CisgICAgICAgICAgICBpZighb3V0LmlzRW1wdHkoKSkgUVZFUklG
WSh3aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZlKG91dCsiL2hhcmR3YXJlLW1vbml0b3ItIitRU3Ry
aW5nOjpudW1iZXIoc2NhbGUpKyIucG5nIikpOworICAgICAgICAgICAgZmxpY2stPnNldFByb3Bl
cnR5KCJjb250ZW50WSIsMCk7CisgICAgICAgICAgICBzeXN0ZW0tPnNldFByb3BlcnR5KCJhY3Rp
dmUiLGZhbHNlKTsgUVRlc3Q6OnFXYWl0KDEwMCk7CisgICAgICAgIH0KKyAgICAgICAgUVZFUklG
WShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VTY2FsZSIsUV9B
UkcoUVZhcmlhbnQsMTAwKSkpOworICAgICAgICBRQ09NUEFSRShxbWxXYXJuaW5ncy5jb3VudCgp
LDApOworICAgICAgICBxdW5zZXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIik7Cisg
ICAgfQorfTsKK1FURVNUX01BSU4oQ3JpbXNvblRlc3QpCisjaW5jbHVkZSAidGVzdC1jcmltc29u
Lm1vYyIKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24ucHJv
IGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5wcm8KbmV3IGZpbGUgbW9kZSAx
MDA2NDQKaW5kZXggMDAwMDAwMC4uOTI1N2MzNgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29u
bGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24ucHJvCkBAIC0wLDAgKzEsMjMgQEAKK1FUICs9IGNv
cmUgZ3VpIHF1aWNrIG5ldHdvcmsgcXVpY2tjb250cm9sczIgdGVzdGxpYiBzdmcKK0NPTkZJRyAr
PSBjKysxNyB0ZXN0Y2FzZQorVEFSR0VUID0gdGVzdC1jcmltc29uCitTT1VSQ0VTICs9IHRlc3Qt
Y3JpbXNvbi5jcHAgLi4vY3JpbXNvbnN0YXR1cy5jcHAKK0hFQURFUlMgKz0gLi4vY3JpbXNvbnN0
YXR1cy5oCisKK1NPVVJDRVMgKz0gLi4vbWFuYWdlZHVwZGF0ZXMuY3BwCitIRUFERVJTICs9IC4u
Ly4uL2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaAorCitERUZJTkVTICs9IE1PT05MSUdIVF9D
T05UUk9MU19URVNUCitTT1VSQ0VTICs9IC4uL3N5c3RlbWNvbnRyb2xzLmNwcAorSEVBREVSUyAr
PSAuLi9zeXN0ZW1jb250cm9scy5oCisKK1NPVVJDRVMgKz0gLi4vZWNsaXBzZXByb2ZpbGVzLmNw
cAorSEVBREVSUyArPSAuLi9lY2xpcHNlcHJvZmlsZXMuaAorCisjIE1hdGNoIHRoZSBwcm9kdWN0
aW9uIHJlc291cmNlIGJ1bmRsZSBzbyByZW5kZXJlZCBpY29ucyBhcmUgYWN0dWFsbHkgdGVzdGVk
LgorUkVTT1VSQ0VTICs9IC4uLy4uL3Jlc291cmNlcy5xcmMKKworU09VUkNFUyArPSAuLi9sb2Nh
bGhhcmR3YXJlLmNwcAorSEVBREVSUyArPSAuLi9sb2NhbGhhcmR3YXJlLmgKKworSEVBREVSUyAr
PSB1aW1vZGVscy5oCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvdWltb2RlbHMu
aCBiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy91aW1vZGVscy5oCm5ldyBmaWxlIG1vZGUgMTAwNjQ0
CmluZGV4IDAwMDAwMDAuLmEwMDFlYjgKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0
b3MvdGVzdHMvdWltb2RlbHMuaApAQCAtMCwwICsxLDQwIEBACisjcHJhZ21hIG9uY2UKKyNpbmNs
dWRlIDxRQWJzdHJhY3RMaXN0TW9kZWw+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CitjbGFzcyBV
aUNvbXB1dGVyTW9kZWwgOiBwdWJsaWMgUUFic3RyYWN0TGlzdE1vZGVsIHsKKyAgICBRX09CSkVD
VAorcHVibGljOgorICAgIGVudW0gUm9sZXMge05hbWVSb2xlPVF0OjpVc2VyUm9sZSxPbmxpbmVS
b2xlLFBhaXJlZFJvbGUsQnVzeVJvbGUsV2FrZWFibGVSb2xlLFN0YXR1c1Vua25vd25Sb2xlLFNl
cnZlclN1cHBvcnRlZFJvbGUsRGV0YWlsc1JvbGUsQXBvbGxvVmVyc2lvblJvbGUsSXNBcG9sbG9T
ZXJ2ZXJSb2xlLFBlcm1pc3Npb25TdW1tYXJ5Um9sZSxIb3N0VHlwZVJvbGUsVHJhbnNwb3J0Um9s
ZSxMYXRlbmN5VGV4dFJvbGUsTGFzdFNlZW5UZXh0Um9sZX07UV9FTlVNKFJvbGVzKQorICAgIGV4
cGxpY2l0IFVpQ29tcHV0ZXJNb2RlbChRT2JqZWN0KiBwYXJlbnQ9bnVsbHB0cik6UUFic3RyYWN0
TGlzdE1vZGVsKHBhcmVudCl7fQorICAgIFFfSU5WT0tBQkxFIHZvaWQgaW5pdGlhbGl6ZShRT2Jq
ZWN0Kil7fQorICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50TWFwIGNyaW1zb25Ib3N0KGludCkgY29u
c3Qge3JldHVybiB7eyJpZCIsInVpLWZpeHR1cmUifSx7InVybCIsImh0dHBzOi8vMTI3LjAuMC4x
OjQ3OTkwIn19O30KKyAgICBpbnQgcm93Q291bnQoY29uc3QgUU1vZGVsSW5kZXgmID0gUU1vZGVs
SW5kZXgoKSkgY29uc3Qgb3ZlcnJpZGV7cmV0dXJuIDI7fQorICAgIFFIYXNoPGludCxRQnl0ZUFy
cmF5PiByb2xlTmFtZXMoKWNvbnN0IG92ZXJyaWRlIHtyZXR1cm4ge3tOYW1lUm9sZSwibmFtZSJ9
LHtPbmxpbmVSb2xlLCJvbmxpbmUifSx7UGFpcmVkUm9sZSwicGFpcmVkIn0se0J1c3lSb2xlLCJi
dXN5In0se1dha2VhYmxlUm9sZSwid2FrZWFibGUifSx7U3RhdHVzVW5rbm93blJvbGUsInN0YXR1
c1Vua25vd24ifSx7U2VydmVyU3VwcG9ydGVkUm9sZSwic2VydmVyU3VwcG9ydGVkIn0se0RldGFp
bHNSb2xlLCJkZXRhaWxzIn0se0Fwb2xsb1ZlcnNpb25Sb2xlLCJhcG9sbG9WZXJzaW9uIn0se0lz
QXBvbGxvU2VydmVyUm9sZSwiaXNBcG9sbG9TZXJ2ZXIifSx7UGVybWlzc2lvblN1bW1hcnlSb2xl
LCJwZXJtaXNzaW9uU3VtbWFyeSJ9LHtIb3N0VHlwZVJvbGUsImhvc3RUeXBlIn0se1RyYW5zcG9y
dFJvbGUsInRyYW5zcG9ydCJ9LHtMYXRlbmN5VGV4dFJvbGUsImxhdGVuY3lUZXh0In0se0xhc3RT
ZWVuVGV4dFJvbGUsImxhc3RTZWVuVGV4dCJ9fTt9CisgICAgUV9JTlZPS0FCTEUgUVZhcmlhbnQg
ZGF0YShjb25zdCBRTW9kZWxJbmRleCYgaW5kZXgsaW50IHJvbGUpIGNvbnN0IG92ZXJyaWRlIHsK
KyAgICAgICAgaWYocm9sZT09TmFtZVJvbGUpcmV0dXJuIGluZGV4LnJvdygpPyJCYWNrdXAgUEMi
OiJHYW1pbmcgUEMiOworICAgICAgICBpZihyb2xlPT1PbmxpbmVSb2xlfHxyb2xlPT1QYWlyZWRS
b2xlfHxyb2xlPT1TZXJ2ZXJTdXBwb3J0ZWRSb2xlfHxyb2xlPT1Jc0Fwb2xsb1NlcnZlclJvbGUp
cmV0dXJuIHRydWU7CisgICAgICAgIGlmKHJvbGU9PUhvc3RUeXBlUm9sZSlyZXR1cm4gIlZJQkVQ
T0xMTyI7aWYocm9sZT09VHJhbnNwb3J0Um9sZSlyZXR1cm4gIkxBTiI7CisgICAgICAgIGlmKHJv
bGU9PUxhdGVuY3lUZXh0Um9sZSlyZXR1cm4gIjQgbXMiO2lmKHJvbGU9PVBlcm1pc3Npb25TdW1t
YXJ5Um9sZSlyZXR1cm4gIkZ1bGwgYWNjZXNzIjsKKyAgICAgICAgaWYocm9sZT09RGV0YWlsc1Jv
bGUpcmV0dXJuIFFWYXJpYW50TGlzdCgpO2lmKHJvbGU9PUxhc3RTZWVuVGV4dFJvbGV8fHJvbGU9
PUFwb2xsb1ZlcnNpb25Sb2xlKXJldHVybiBRU3RyaW5nKCk7cmV0dXJuIGZhbHNlOworICAgIH0K
K3NpZ25hbHM6CisgICAgdm9pZCBvdHBTdGFnZTFDb21wbGV0ZWQoKTsKKyAgICB2b2lkIHBhaXJp
bmdDb21wbGV0ZWQoUVZhcmlhbnQgZXJyb3IpOworICAgIHZvaWQgY29ubmVjdGlvblRlc3RDb21w
bGV0ZWQoaW50IHJlc3VsdCk7Cit9OworY2xhc3MgVWlBcHBNb2RlbCA6IHB1YmxpYyBRQWJzdHJh
Y3RMaXN0TW9kZWwgeworICAgIFFfT0JKRUNUCitwdWJsaWM6CisgICAgZXhwbGljaXQgVWlBcHBN
b2RlbChRT2JqZWN0KiBwYXJlbnQ9bnVsbHB0cik6UUFic3RyYWN0TGlzdE1vZGVsKHBhcmVudCl7
fQorICAgIFFfSU5WT0tBQkxFIHZvaWQgaW5pdGlhbGl6ZShRT2JqZWN0KixpbnQsYm9vbCl7fQor
ICAgIFFfSU5WT0tBQkxFIGludCBnZXRSdW5uaW5nQXBwSWQoKXtyZXR1cm4gMDt9CisgICAgUV9J
TlZPS0FCTEUgUVN0cmluZyBnZXRSdW5uaW5nQXBwTmFtZSgpe3JldHVybiB7fTt9CisgICAgUV9J
TlZPS0FCTEUgaW50IGdldERpcmVjdExhdW5jaEFwcEluZGV4KCl7cmV0dXJuIC0xO30KKyAgICBR
X0lOVk9LQUJMRSBRU3RyaW5nIGdldENvbXB1dGVyVXVpZCgpe3JldHVybiAidWktZml4dHVyZSI7
fQorICAgIFFfSU5WT0tBQkxFIHZvaWQgcmVzeW5jUnVubmluZ1N0YXRlKCl7fQorICAgIGludCBy
b3dDb3VudChjb25zdCBRTW9kZWxJbmRleCYgPSBRTW9kZWxJbmRleCgpKWNvbnN0IG92ZXJyaWRl
e3JldHVybiA2O30KKyAgICBRSGFzaDxpbnQsUUJ5dGVBcnJheT4gcm9sZU5hbWVzKCljb25zdCBv
dmVycmlkZXtyZXR1cm4ge3syNTYsIm5hbWUifSx7MjU3LCJydW5uaW5nIn0sezI1OCwiYm94YXJ0
In0sezI1OSwiaGlkZGVuIn0sezI2MCwiYXBwaWQifSx7MjYxLCJkaXJlY3RMYXVuY2gifSx7MjYy
LCJpc0FwcENvbGxlY3RvckdhbWUifX07fQorICAgIFFWYXJpYW50IGRhdGEoY29uc3QgUU1vZGVs
SW5kZXgmIGluZGV4LGludCByb2xlKWNvbnN0IG92ZXJyaWRlIHtpZihyb2xlPT0yNTYpcmV0dXJu
IFFTdHJpbmdMaXN0eyJEZXNrdG9wIiwiU3RlYW0gQmlnIFBpY3R1cmUiLCJHYW1lIGxpYnJhcnki
LCJNZWRpYSIsIkJyb3dzZXIiLCJUb29scyJ9LnZhbHVlKGluZGV4LnJvdygpKTtpZihyb2xlPT0y
NTgpcmV0dXJuICJxcmM6L3Jlcy9ub19hcHBfaW1hZ2UucG5nIjtpZihyb2xlPT0yNjApcmV0dXJu
IGluZGV4LnJvdygpKzE7cmV0dXJuIGZhbHNlO30KK3NpZ25hbHM6CisgICAgdm9pZCBjb21wdXRl
ckxvc3QoKTsKK307CmRpZmYgLS1naXQgYS9hcHAvcW1sLnFyYyBiL2FwcC9xbWwucXJjCmluZGV4
IGEzYzExZGQuLjQ4ZTlkNTcgMTAwNjQ0Ci0tLSBhL2FwcC9xbWwucXJjCisrKyBiL2FwcC9xbWwu
cXJjCkBAIC0yLDYgKzIsMTQgQEAKICAgICA8cXJlc291cmNlIHByZWZpeD0iLyI+CiAgICAgICAg
IDxmaWxlPmd1aS9UaGVtZS5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9WYlRva2Vucy5x
bWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uR2xhc3NQYW5lbC5xbWw8L2ZpbGU+
CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uQmFja2dyb3VuZFBpY2tlci5xbWw8L2ZpbGU+Cisg
ICAgICAgIDxmaWxlPmd1aS9Dcmltc29uR2xhc3NCYWNrZHJvcC5xbWw8L2ZpbGU+CisgICAgICAg
IDxmaWxlPmd1aS9Dcmltc29uU3BhcmtsaW5lLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3Vp
L0NyaW1zb25Mb2NhbFBhbmVsLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0NyaW1zb25H
bGFzc1JhaWwucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvQ3JpbXNvbkhvc3RQYW5lbC5x
bWw8L2ZpbGU+CisKICAgICAgICAgPGZpbGU+Z3VpL1ZiRm9jdXNSaW5nLnFtbDwvZmlsZT4KICAg
ICAgICAgPGZpbGU+Z3VpL1ZiRHJvcFNoYWRvdy5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1
aS9WYkhpbnRCYXIucW1sPC9maWxlPgpAQCAtMTQsNiArMjIsMTEgQEAKICAgICAgICAgPGZpbGU+
Z3VpL1ZiSG9zdENhcmQucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvVmJXZWxjb21lU2hl
ZXQucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvbWFpbi5xbWw8L2ZpbGU+CisgICAgICAg
IDxmaWxlPmd1aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+
Z3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9nLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3Vp
L0VjbGlwc2VDb250cm9sQ2VudGVyLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0VjbGlw
c2VBY3Rpb25CdXR0b24ucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUFib3V0
RGlhbG9nLnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL1BjVmlldy5xbWw8L2ZpbGU+CiAg
ICAgICAgIDxmaWxlPmd1aS9BcHBWaWV3LnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL1Nl
dHRpbmdzVmlldy5xbWw8L2ZpbGU+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1zb24tYmF0dGVy
eS5zdmcgYi9hcHAvcmVzL2NyaW1zb24tYmF0dGVyeS5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQK
aW5kZXggMDAwMDAwMC4uMzc1MzU2NgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMvY3JpbXNv
bi1iYXR0ZXJ5LnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9y
Zy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxn
IGZpbGw9Im5vbmUiIHN0cm9rZT0iI0VDRUVGMSIgc3Ryb2tlLXdpZHRoPSIxLjgiIHN0cm9rZS1s
aW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHJlY3QgeD0iMiIgeT0iNiIg
d2lkdGg9IjE4IiBoZWlnaHQ9IjEyIiByeD0iMiIvPjxwYXRoIGQ9Ik0yMiAxMHY0TTYgMTB2NE0x
MCAxMHY0TTE0IDEwdjQiLz48L2c+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1zb24t
Ymx1ZXRvb3RoLnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnCm5ldyBmaWxlIG1v
ZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmNlZjlhYjgKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAv
cmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRw
Oi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIw
IDAgMjQgMjQiPjxwYXRoIGQ9Ik03IDdsMTAgMTAtNSA0VjNsNSA0TDcgMTciIGZpbGw9Im5vbmUi
IHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0icm91bmQi
IHN0cm9rZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvY3Jp
bXNvbi1ob3N0LnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1ob3N0LnN2ZwpuZXcgZmlsZSBtb2RlIDEw
MDY0NAppbmRleCAwMDAwMDAwLi5kMWQ1OWIwCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9j
cmltc29uLWhvc3Quc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMu
b3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCI+
PGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRUNFRUYxIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tl
LWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cmVjdCB4PSIzIiB5PSIz
IiB3aWR0aD0iMTgiIGhlaWdodD0iMTQiIHJ4PSIyIi8+PHBhdGggZD0iTTggMjFoOE0xMiAxN3Y0
TTYgMTBoM2wyLTQgMyA4IDItNGgyIi8+PC9nPjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9j
cmltc29uLW5ldHdvcmsuc3ZnIGIvYXBwL3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmIyYTEwM2EKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvcmVzL2NyaW1zb24tbmV0d29yay5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0
cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0i
MCAwIDI0IDI0Ij48ZyBmaWxsPSJub25lIiBzdHJva2U9IiNFQ0VFRjEiIHN0cm9rZS13aWR0aD0i
MS44IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxwYXRo
IGQ9Ik0zIDhhMTQgMTQgMCAwIDEgMTggME02IDEyYTkgOSAwIDAgMSAxMiAwTTkgMTZhNCA0IDAg
MCAxIDYgMCIvPjxjaXJjbGUgY3g9IjEyIiBjeT0iMjAiIHI9IjEiLz48L2c+PC9zdmc+CmRpZmYg
LS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtY29udHJvbHMuc3ZnIGIvYXBwL3Jlcy9lY2xpcHNlLWNv
bnRyb2xzLnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi42NTNkYmQ4Ci0t
LSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZwpAQCAtMCwwICsx
IEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBo
ZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik00IDZoMTZNNCAxMmgxNk00
IDE4aDE2TTggM3Y2TTE2IDl2Nk0xMCAxNXY2IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBz
dHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49
InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcgYi9h
cHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAw
MC4uNzExNWMzMwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMvZWNsaXBzZS1pY29uLnN2ZwpA
QCAtMCwwICsxLDcgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3
aWR0aD0iNTEyIiBoZWlnaHQ9IjUxMiIgdmlld0JveD0iMCAwIDUxMiA1MTIiPgorPGRlZnM+PGxp
bmVhckdyYWRpZW50IGlkPSJyaW0iIHgxPSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj48c3RvcCBz
dG9wLWNvbG9yPSIjZmY3NThiIi8+PHN0b3Agb2Zmc2V0PSIuNDgiIHN0b3AtY29sb3I9IiNkYzM2
NTgiLz48c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiM2MzE1MmIiLz48L2xpbmVhckdyYWRp
ZW50PjxsaW5lYXJHcmFkaWVudCBpZD0iZ2xhc3MiIHgxPSIwIiB5MT0iMCIgeDI9IjAiIHkyPSIx
Ij48c3RvcCBzdG9wLWNvbG9yPSIjMjAxNTFjIi8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9y
PSIjMDgwODBiIi8+PC9saW5lYXJHcmFkaWVudD48L2RlZnM+Cis8cmVjdCB4PSIxMiIgeT0iMTIi
IHdpZHRoPSI0ODgiIGhlaWdodD0iNDg4IiByeD0iMTEwIiBmaWxsPSJ1cmwoI2dsYXNzKSIgc3Ry
b2tlPSIjZmZmZmZmIiBzdHJva2Utb3BhY2l0eT0iLjEzIiBzdHJva2Utd2lkdGg9IjIiLz4KKzxj
aXJjbGUgY3g9IjI1NiIgY3k9IjI1NiIgcj0iMTQ0IiBmaWxsPSJ1cmwoI3JpbSkiLz4KKzxjaXJj
bGUgY3g9IjI2OCIgY3k9IjI0OSIgcj0iMTM2IiBmaWxsPSIjMDgwODBiIi8+Cis8cGF0aCBkPSJN
MTUxIDE2MmExNDMgMTQzIDAgMCAxIDEzNS00OCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZlOGVl
IiBzdHJva2Utb3BhY2l0eT0iLjU1IiBzdHJva2Utd2lkdGg9IjMiIHN0cm9rZS1saW5lY2FwPSJy
b3VuZCIvPgorPC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtbWFyay0xMjgucG5n
IGIvYXBwL3Jlcy9lY2xpcHNlLW1hcmstMTI4LnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi4xNTEyMWMwNGJlN2E0
Y2I5ZmI2NWZmMDk5ZDc0NjdiNDQ0YzZlOTBkCkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCA3MDg3
CnpjbVY7ZzgmS3FsUCk8aDszS3xMazAwMGUxTkpMVHEwMDRqaDAwNGpwMV5AczYhIy1pbDAwMHx5
TmtsPFpjJTFFPgp6ZDYtPCliPk0mSi1kQ0B4eUx3ZCUyXyZfSWdwaztnRmgpUlpnYmo4RWoyRk8t
P0hDN2RuMmhsXjhTbjlZPTk1ViMKejZNclU/Y3JyNnkkbWlJMmE2RkZVSTVPaXZqMkZPUXZ6dlZw
bEYrYE9tVV5rYCtUT2VPJXBiMyspb0x8RGZWI1JgCnpzJFlNdktkSE9BLW03PWNKQD1lKiZwbDc1
RjlNK0tgYClDNkJzVkFGaGAyZWpZU2sqVWFePWJaMm1td0g3Y2BBOQp6SyhLUDwlMyMmMVJSK2ZE
I15MMyN6d3hTN3RJVWx6LWVgYiQ/OVl1Z3hZKEluWkBzbGAqU2NMe3h3Nkx8P3NIRlAKeihxV0lB
eT9BIXo+WmBCTCtyV0Q3e1A+cHl0NSZWQEh7TipUMGwjPVg5NXd+JD4rNz90U0ZpUnwmNmxkbUg2
T1U8CnpscFdpKXpIeFlIX3pqaEVkMSlORzxEN0hkcz1nSn47QmNNJGgoSUozRiRIVndLb0htK1ZM
SlZNTWB5PCkkSVlHaAp6JkBEZl88cnh2Rk8kKlozKkpvQypVaE5MY1g8elJmUjBaejxZIUxBTkUz
UDxlKUF9diU5VWRDR3Z8SzhtPUFFPDcKemRBeGQxdCFsXlhKP2p5UVIwU2V9NXJlZWBXMzVZUChv
ZU5AdypUQWx6NEwka1B5Zz5Ia0htM2VUKnV6fipLeHwlCnpefHVDYXNaQCRmUj0palJUZW9mZlI2
ZHUjSUYySDUmWT1uanVCeUV2YF80Q01iSntlZ0hhLStrUlRVSH4wQGhsQgp6UjclXzArSX41QT8l
ZS0lJDMxdGhpSn1PPTA7ODdxKSQqRElRUFZzeiFzVkE7eys1a3YqTUI4OUpiWGM9UW8qWXQKek1x
KXV+JmRXSUd3a2k5QWJIRmBIbG1ZZVhIODNLQ1ZNdHA/YCk/TVhjKjBseWBEZyQ3RUE+aHJlUmVn
ay1XdDNYCnpYO3tHaDsyWW9Re0Aqdj5APmwpK3lSUiNrJTZScU83XkJ0U0g8Pih+X2c7Kk1Ob08r
NW9PUjYyKk1JeilLbHxWKAp6S1JHfVdaTjt6ajI0aWAoM0o/SkNScXdwJjUxeFBhc3FZTEE8KDlA
U1IlNDgoRGZvS2h5IVI1PXo7dHhCS1l6KzsKenIrKW0wfEdONUtVWm9QZThVP1QtO0AqRDIjVUl8
aGUjNXMkM2RKLStFRncqQmVoTnw1NyRzPVF3cDMxN3dDSzlxCnpAQTx7fFJNaTU5RyN3bk8wdDh8
dHpHJWUtcFdEMjclVDB4MTVvP1UySXFEayk9ZUBUckVpTHIrX0l9fTQ1OGlXPQp6YGFASEtTSW98
PldNdj5DQHI1ZmNffXM9I257TyU8aV9SRk0zUmJDbEQ5dk40ND1jdUtwOyZhQUhnRXBnZykxKWoK
em9RU3hVdGI5ZjVkezcxRz4rNz8zYjllbFFEPSlyZz4qZyZ0bH1hVU5qRzVIYldSdXM3Ny1MTVNS
RW9FNS1nNDkxCnpGU3opX2NYTX4jKlZsSllFQiYkeFB6JmB3Yz09VzV6UE50RiZCYkVUSC0rRXVo
JXY/JWkkJVkyITs5Yms7TkA0SAp6eUwkQyVjUTdUR1A/KEJ9QW9BVnNleilVcXtfRUVzOXZtMXZM
NXo1czNwJiNVdWlsJWs/KFglVWBTS1Vlez5Wb0AKekdPVlp5cXZfO1BDUkJodnVzPTQmb3BaKW5I
fUJsR15JR1IhKTd6aEJzQV9ERDRVVjBBP0I3NTUjR3t8Xi1jUlRoCno5eCRUJnpeKEBPLXBrJXxM
STNWTypHNFhPaCVfQyhYPzdyREJOd349LUZ2Uj5kKnxoRTIzKzMrUVFKZm96XkUkQQp6bVlqQykt
YVB+N0F2RDlpPjVEX0xHa1NWe2BgRnFpLVlnPUp0UShCN3A5U2NuJmpTOVA3aFVwPmR+VzFDTVZy
RSgKei1kSUlfSzlAV0hUXkM8XkRkNUxEZ3lTdU12RFclaVBkTkc0MU8wbjFZPnhnVDAqN0x7WFpH
Q25eIWpKcz5ZT3UtCnp1Pnp3T3Bqdnc1YGAqKkh5cFNKeHYjTThgIWFvd1FVT2swO3sofD5pQHhF
biV1Z1YoTy12Ul9jZUQxUWR6cSk8Zgp6anhSZHpWQFpEMldjbXt1Vn1kenpqe0VCVWszYWsrI3ct
fCheI1BvITJFIytTY1IxJmVYM1QjaVZWclhlPWtvOCsKenEhZSM3OTVnVSR7YEh5PGR8K3cwVHQw
ZDFAMHVKRDc9VXVBYm4/fCNVQStYKitCOUdRP3otelAxRiYoXl83JT4jCnpMdGFYM0dPY2pWeG5T
JG9PKUZyWiVuaVdaY2kjO19GYHItVm9udVN8PkpmI0FBUi11SjR0bXNIY08pU3E+WVphRwp6VXN3
K05XTHxVZnlzPyYyc2wzI0E5aylxa2BlSkg9UlBmI3QjU3V+TGFOZ2wtNzBUMks3YlU0JDlhRThP
WkdhaUMKejItRWtAaTFTTGhSNmZhQWkrOVAhZ01qMkNjXkFqXzxiQH5BUVB0fExuNFREODVXcVB7
cDtEJENNfGZqc1g+RnlhCnpyLSN8eUdkUU5CbGdAMEdiU2d4UTs4ZHgmbX0wcmlOVT16NkIrdDsk
RmhqI1JxTm9CMHF2fHEhWktKM3ZRNTROXwp6YWNvN3owczl0c1pvVCFedG9Mek9FdDVQfFNOVTN+
amF1ZyZgSD5NUy1xRl80JmVEWlRJT2x7RFN1dVlSM3A9XzwKenQxeV8pdjJBRjhaRyhIK21DdiFh
VHdvfXdQKkhgemw1V2l+dWN3UHNKMzg2QmNRMUdUYFl1dnwjZnNUQ0VoemdHCnpWcF5laUA0RDhr
Uzw/I1NVYCg5OVl1JkM7b3dsTSg4fVcrPlJ0KTgrTGNVbGUrdCRWI216fkxGJWcqTUtnLWUoKAp6
QT1gS0M8bGc2PjthbHNVPEkhRFBkMng3dlR3TGJCcDxNZ1czSyhuPGtQZyMwPWE1SitBX1ReZ3ZY
OztXU2QtKykKelJIdXoxMm55PTdiPX5qUnJLdUBecTZvc0Mke3dyZT0+SG9UMGoja1VxWTVMJUJK
KmE/PUlUR1pnYiR1fDk/TSQwCnpDfmV4eEtpX2REKkZXPHBfd0Mtc2glMTl3TlRtbzxtZSNRQ2ZL
TkRIakg7Umx6ZEd1akRsVSNGI31PaHolMzlKawp6TUhtRGFHMUVkM0gyRGhsUlFGe254X19vYHp2
YVhSI1RyQkdKJHJ8VFNhfEhRZUQ7ZD5AdTZrc2E5bV9+PjhZcHEKekA8WD9CJVpwRjV3VXxweGRZ
Qj9CO2klYkcpbnVGNkF1dSkpc0JQSipRSGYoSmFnMj0mPV4jWlcycjtJeTY9NVJUCnpQTWNKKDBM
RUdkTUBIeU1yfUBHYVM4P3FoeW9FVk1DSExzRmVDNSU1YFIwWnZkOHc0ZzF9VTxjUnpVSHB4SSt+
OQp6dEdiPnNtU0xuKXJXOGVGUVh3cz01RHtyO01IdEpwUHlqMjJOSWlvP0wlaWU2di10OD1TOTV4
KjRXOE0remRaZFkKekgjfmhtJmtWanE1UU1hYUVzNDNGMWZmcmFrU0skcTZlPWFrYVlReXU2OSVi
aXAjJS1EMEQmPiZEcktANXpKQiRgCnpgMCk4RjNEJDA9fEhZQGQ7cHlNO3RyczIjNyFgYjZDJjVw
SWh+VSZRVHE9LUJnPUU3RkdCJCo0SypsTFJWfGY5QQp6dkZ0NjNhN05FOHpXRkRBJHs4SXEoY2VB
SlY9cnl6O304RndNfE4kY0hRZlIqckdnKWVSUUd0N3E2KUVodzFxN00KeiN4I2YkOTRPb1Vvan4x
cE9mYFlBPzlTKFMqV3kkNyl+N3lBK3dMTHMhTjw4e19nNFArLXJNTGU2PT0ofTY4cHZ3Cnp7Q0dy
ISpnSit4QlZAeEMhWFRMUERQYmJuSHNsbXd0KSlNZzxLeFREO3Bfa0xLVCYqazlsYGN+eyZEK3lL
Nj53TQp6SUU4RX4tTFMmMUFxWERHU0JobEdrWndTfnB5OEgkdHVnRyQ0Umlmaj1rYSZmZjEzUWAm
eXdBLWhnLUw9PDNzblgKejBmZi1ueDtjNVRtcztSQlFnc2o7WklQKj02ZCo4JEo7ZWVhSk0kY0Zg
amJ5Rl53YHNNXnlnVWYocT15VG83K2VrCnppIX16e1Y1OF96OEw1PTB4VldLfHBrV2pzNU1pS0Y7
K0BBVzxtO0ZKNXhNNiNrbGkpRkwtfkhMeG5+V0NPbCNyUwp6JGRgLTYmTldRN3dJTVFyUilwYT07
PFQ8fl9+eDdiMUxkX1pWcShXMGFlVX5XcEU2dTIpMCM/ODg/JTJmNmVWOU4KeihWbDY9UH5VcSFr
ISt7ZjB3QEFSLWpmWWRlRGo9KD19TSgzI1dBZzZubT5LdVBNI2xsaUVNYWUycDx5MSgwTkNwCnpR
cmZSPz5Rb1d6end9cHM4KDsrbnFZOGd9X0ZHdWliMWVPWkpUbyhge0tNTUVgTyo1UFhpR1A0c1B8
ZUM1aGAmKwp6KzFmZnMySUZOYlEpPmFOMiFtMERPWG49KTwwcVdYUF5teVJOVT1GTCRQSkkoTG49
dCY4ek87bl96QDlgUVJSPnEKenJZNEk2NmApU0w3ZXlpVk5Ab3pWPld1VThzPkkmWVZndnJfc3Il
V1VBMCV5cVk0N3dNNERVVXFzRkZCQGI9eCglCnpLbD4+X3l7PHQ0QlppPyRuVTV8JG96dUgjRjxk
RnJrcVVXdV9qYk8me3opPW5yZVZeJWxaQSotaiQ+bHlzTWMlTAp6VD9lTFEzSns+PVYmLVElX3s4
RWZDYE0lcmtpemdrb19tQnNyQSMwVjZRTkVqaWMpZ1hsdlFDKCR6OFQkJGoxQGEKekVJTmdHKj4o
elhNQW9Ld1YmRW0jWTxWRm0jWDc9QWUrQHkxVCNUQ3tONE0/QEFWQXMyJXhUVD97Xk9UWWlYdT01
Cnp0PnFzI0swfmZ0QVNMRHFiXlJ0clJqSWhDTmZWRCNmWFNiTWowcEwtIVg/S1kmIVRKPmcqWU5E
aFdfRlJLaVRwRQp6Q1AqRjhqXjlMeEJ2d0dSKjdMYzNVTy1VcUVQeilmWjMzPzdVNHJ1LVJpIWx1
YDFRX0J5ZkQwJW1aTU1zMEd4VXYKej8/ezx8JCpMVX5GV1h3WF9xdCgzRDdjN3xKN0A1UThNNyhH
aVRPN09jV21FP0kpYGJIOUNfVlFsNHpqTEFIU3smCnpBUDhtZXhNMD5peD42eUxhfDl2YFIhWkVy
ZG1DY3k1dTVtVkJ9OFBAQkchfW9EUyMlPFBBSFopQTJTIXtlS0gtMAp6V2tZVXxiQEBSO0pNfnBG
UTtFfiRwNDQqOz58WVR5aUIzU1c9O041M1kyfnp6OSFoWnhzKVdZeV5pViR8UUhnOVMKempYUjFK
S3ZBNmNTVGppalZGS0NLJT5zeEJDRmVNeXQmNz58Und+WWNDV2BVdyY+cnhPemF5ejBjd2dVMWE5
bG1XCnp6T1R0M1FwZUpjWlpnSkYmPFgmfmQpRFdOS3BNTXp4P1hyWk9wKyV3ayE8VCs2ZV5zVT9F
KzE8WGM/ZCEkODBPKwp6c3xzK21CbTRDJnMwVmRaMDBqYWcleGheJih3P2RhaEp1UzJ0ZCFzPSRe
OVA7Zmc/OHhAVCM8IWZTS3RHdkc9R1oKekNvZWgyaD5Je0g0WTQwI3Mrc0lXKzw1QSQwQkxMS3Um
R2ZDMEUrWER2aUZ6PEQzNTlnPktnXnRyemxpTmRYb21tCnprZz50T0RqMShBIz9jKTZQZlhJSztx
YnJmNnhJVk1pcDNDQTlVVX47eEB7MXdzaFImfjcrN3NZUGBBXktPOVV5Qwp6d21ERzh6SktFRUQ0
cWJKKWRXZjRCT0xYIWZCLVVDN0k2YUUpLU1zbno3PztVNTsjPmQjP2xeeUI7Q29IKVNKMn0KemZL
cDhidEVVamgpcEJebmRyIXQjV2A+eitTYUBgIVExX3ljeTZwQFM1c0o8Kzk5MXdYKW19WUgzU29Y
ckl+Kms/CnpVPFhJNWpWVUs1RD58aTRwcGolTGN6M3lvbTh1VT00Rnlsa2NHN2VKNlk2YU4+Z29l
VD5lKjd2VktmUTwxYztwRAp6bChyZElZbWRyR3BzQCVeLUB8JClnWF5BdVR7a2pSJT5nTipOaFdZ
ZlliVWVQdHdpZE5ZQ0RraEUzVTZkPlEpcjAKekNAQiV2PF85UmNDXkBrelckJjBCd3MyLWc1M3pG
eEhmS0ljUHswX2UpQW8+aylOTjt3UzAhYUVGQkZFQFJWb21XCnpHKndpdXF7TUxIajUjblZgTEY0
TkhIa1J0QztvYjcwdUAzcnlpX2pvUkJrV25ZT0BDY2lnQ24rLUUoTTlXdkNwYgp6KHx8eUF7O3gw
bEU1SWJIb2Q2WkB4cCFiRVJ0NGBCS2BGWUpCYHV3dC0hKz94aTt1YyNLdUpjd3NuO2dhRzFTJUwK
elA9JD1Le0FUWUMyQkgjeTJ3R2hidkxha0hgLUozbV59TUpDQSZ7d2dMU0oxS3pAdWNXPEB1Mzg5
dlJ3QWk/TWsxCno3JDZzd2RFMU9Sb1lLfXE9X3MtU05ARHUwblZSaXpiPkFLPzJxb3xNJD9pPjk3
K28yUnl3WWh5SzZjeV55bXY+OQp6QTBSLSsyNmVnamh1e1FHe15gQVgrSEFuamA/cz1nV1NFUjMm
WSVUYHFCOEcyPTZGdFBwR29tM3VtV0N7dE8tYnMKend2dyZDM2UtSWpxKEk2VGMyKXxrZXJXQChD
Y3ljYDNkSEpadm5mOD9kKWt6QFBNS18hcSV+ZW9Ebm9lK0JjQ2EkCnojUHE2VVpOTHdBWkQzT3xO
NGpQT1IyWWlOVHNDN0tAMEB1Jmd9OHp9MDxDfXtOc0JLQytvKyhVO3FYKmxPV2pjKgp6WjdpRWhk
SCFMP1RDJkZDWUt1YihXIz9HY2RuVThQUnd+e2ZRNSF9REQ2NDA3a2ZBNClxMkhDMFhsUlBBPUt1
dyQKeipEVH56WH0yTV8+e2AjYHhqa2VoaTNrS0pJPiYtXm1jTipQN0xuRn0kTHdVSEI7Qz1AWmtA
XmNYa0BnWl5pKCoyCnpQfHJscnhJO0NXMUJjXj98Ri00SChlckU3QXNtUnhUcnMxVVBhUyhRZyh3
KiUoO2I2UUAtWXsrOW17VENWWHYhQAp6IXFvTT9rSm99Si1IcVc/PT9xZipWc0hvRitxc1N8bkBY
Qk9EcCs3SnVKQzdiUFVXKG0xPzEhRC04amwzNm53PF8Keio8PEpxR0NXb3FwakNuPy13cj9KY2VM
Z1plcj8tUkpkKW8teTl0UFd2VEBXYFJ9MjY5ezVTQlhqXm4xUzU/RiowCnpBOH5yN257JV9yYTdU
VXpxMTN4bUBXZjFUSHx1TVU2ZVNSJDtBMXxzPUBBQ3dHTkJrOylnUCMrJEJPV2M8SW15egp6X1Nz
Yj5tX0V9JVA1MzhnST1RbElLNUtIQERYR0pmZUVLUTF8NGQ8eyRnemozVDdqbnZnTTUwXkJOJnA1
Vk8oPHgKenkoMlcxWiFLRUUrcSZrR2tJUj9fLSVNV1h6Y2I8XiZUUSVDQmkkIShUWWZ1UjtzUjsw
YiM/cD5yVURJUFBoKFpPCnpmez1lNytRRkIkSzJBJEBhVWB6cEF9O3dEZ1lma1FaeyRQQW9KaGV7
YU1lWW1NI0VHK2ArfDNAWUA1d1RYUG0lbwp6YDVpbl85d09UU15acjtHTWdidFAxbD5XJTVCNjsy
aFY0KCNCMDtzNUZsaW85QHM2XjBlMGxFYXs2KzZfR1I4OUUKekJDSXJxSEFxSWlQfUNUVUBjIS12
VC1DWE5lO01BKzFFb0UqSEpJP0IwVXNMV1JHREV6elNxQmpxSWNZUSstYj5VCnoqbklNbzRUbXhp
bSRgRHIwIzBlXjstKCE+YkFONihmaWF8d3ReNTlac1A1KUxofTA5fEk1Rih0JUZiVHFyZHMmSAp6
Jj9YKSg0PHZieDFgfEZzbTw2Y2VORyFwUl9ITj8oRXNycWJWcD5mPU1TWFAjayszJV52bW5nIWNN
SU9nbSokKyMKenRXPGBQeEkkYz03VjJSV1k5cnBFNm5zcEZPPnQlQ2RfRmFFMzdzfkAtdyhkWEJq
dGdyKj42bDVfUEskdkQmMDJaCnpTSHJ1d3JnQUBqS0lhVGhafFAjZG1HTjViSXB8eyljPCtuX3lz
M1FfS2k8MkVwQUshS3pmIX4pTHN8Pyo0c1h8dQp6K0d0bWxpdSUhTT5uKyl0b1MmVl5hWHx+dVIp
K2NVQEskIWtDMGZLYk95akZWY3k4ZCFoWU0zZHRWKlgxKmlnPUsKej9aeVpBPGc2M3Y+ejxFQyRA
X1RwYnB2c2t0UFN8WXRSLUM1SElGLW9ja3FraDlqcV9zQCFuJl41TFQ2O19SKHI4CnphajtKKykk
Y1cxOyF6Xj9xZ0d+NHMrRkBeeD4/PmJnSlhqWE1lbiNIemteP24/NHFLY21XREk/Mmc8aExlMVAj
ZAp6UmF6diNwP3IxYyk3K2NlJV9uRF8ka0tFTkJSKT1pMH0mJGNEUWFTZHxFT21ubXZ6cUwkPklS
TiZGfCpQO3ZtfjkKejF4aSg9c2NwYjghaTM+dUVraEEySVFCSmY0MkB4U3MpWkI3YzIzUTd1Xj89
di02VCZuZDcrJSsmWEhYX1J+YVRQCnp3aUBhK2xKRjt7O1N+VXFrIU9IVDh9aSRjZWplWDZ6PGF2
cGFiO0k4JEVJMitjJFh8MWt0QnxhYVoqd0FoVV5UXgp6WnRZPm5TSitlQDtlfUY7Yj4kcX1xYXU2
YkdJPHstaiteU0p1bmE7VkxNV0QyWXc1QmZ2d3tyc1FteW9jUyFVWXwKekV5aC14VU1NQF82MkJ8
LV5JJmxnQ0gxc1EoKDg5UjJwXmAyMD5IazZRSllEdSFUO0hfaylJRm08a0hTTHlzaUNNCno9QX5N
UkBEI25QJmlQNnVfRXFIKFBFNUQ2R31EMXNDfkN9emleO2l8eXBKZShQb3k1THpCVk8+N0dyNDxP
REtpXwp6Z0JNSy1TRXw/WFFlNUtFKGZ8KD9fY0d1cldVODs5RWBxTnllc3sxb2p0NEw/ai0rXl5C
UzxtaUJFSGtWZmk7OE0Kekk1KnFGJUM9YzcmOXV7UTE3Y041PldEbDxjdUZvQW05QF9uaWxIWStH
bX5eO0B+YytCc2E3OURwWndufCNOeHEyCnpMMVEqbTNPclVDO0Y8QztMb09uMSV4SHJQKlUpIXZW
KClITDBtM2tKZlVEfmp5KyYlKkFQfUp8Tkt3PzdlO2VNOwp6b3c9Uk40X2k0aSk2SG91b2c1ISM+
OWlAYjFnSzNPRzRFN35RQyMpa0hFVTczRishNVI3bERjQExxMXwjUkE2bC0KeiZrTDB0SkU5VH1Q
Ymh9MG5PXjM7Tj5yNktGaCY2dUZKND5gQkwkIylOLXBhKVAqVmhwJnsxezl3cDBxTkU5ZCM/CnpA
SyhCUCRlZElRXkhReEc3aTU/anEtaSQrODNfblBGeDdBX1FjcWJ1MXNebHlCS0VpbnlQX2dIO31X
fiNHUSZRPwp6WHxsSTU2b1goVnY3aElwcEA0e3khdCYrSSVlNWEwcXh9aWgmWVJvJl98Vnxjc1Vx
VE8mP00wLUF1IXI9RnZnRkQKelpPUFdGV1BWUm89WEZ6Y3w5I2FlajU+cj51aXJ9STVaWXdsP3RZ
ZUg4c2ImZWJhcig7d1JQTChXZ19BTDJ9bUA8CnoxVlB+RCZGJFJ8b0p3UTYwUzg0UGFuPlg7PCQ+
KH5hOCE+SGRuRj4/QDl6WWBoPiNJT1pHRVloRE52WitxRUFxTwp6QWgwYHZBYUVvRCt9RVo2PEds
MGZGI1d0Pi1sailGPDM4T2R6PTtATlhxcV5KTX0oa1g0aXlhUEYhUCpxNHlwPlUKeiYmKEB5dzZ7
Tk10VSo7OVZSM0N6SW9LTmNrJSsyX3Y0KDdXK3dhSHoreUphJWw/UGFgWHUqVDJSMW1BYClhK0Rq
CnpHRmhtcSs4fnZSN2NYQTtLPVB3Uj0zX14/c0gmWWVYYTRVODFfbjx2WDhKbVVPJUF8JHVlUTZw
YF5sfV9IIVpJXgp6YDNuMEIqb3NLcChiNGZVWVlvdF9FMHw0UUohLTk/dEUyc0FScXViKSFqRHd8
NTN1QjwjczQ9PGh0N0x2JDM4KSUKemA4OXBOeW12TkNoaT5zbmkrP20kKV5PbVM4eHNWOXBFSVpU
U04qJHBVc3lGMk9AQ2x8PDVibm1vSF9IWj9LYCU8CnpISThHJDd6RyRWJDRlWj9eIUUxdFo4ezkp
TlFlZkhjRHo+ISElKmZnU254TS05SypPbEtUKWA2UkZ3dHU3djleeQp6eVo8fmZgX0NDb3JXSD1U
K0dDRUhgUCs/flV3bWA1MythQm8tOSVvI2g9QFA9bCUtJEhXSE5aP3NaSiRSU0lGS3gKelVkeTUw
Y2B9KWRvX3kqX1UjdzImMk1xWF5PWlpyMGo1fjRoKHdueiMtRkJfMiMhUkV5ZmhHWE5BYDxrQG58
dCV4CnpiPGJidHl8K3hUK1dUXkd6VzNnbiZ3VGJqZjQ7TWBiRGo0LXBjeGlVQyVwR1E9PE11Vl92
ejJ4X3l6QyVldmFRKgp6VVFQa0RrM1BCWHk2YzlQRW5qfGhUVSlrViVeJk1qK3FMSExOKGJ0a0Jp
cShtS0k2PH5BRys/a3RBX2dNZClhNVAKenlpKDVKMGBBOyUmaSYpKCl+PnkhUjRoNFRqNSZuQVlj
ZSZjX3Vna1I4R0Yqd0NEK3tsO1FpbUhEI01yaWdJN3hSCnpJdnt4UDtSbjhkIXRvMH5tcmlHX19r
Snt1KnJjSVFANFppX0dqYEYhPDNJbzRMbDFuUCNCViFqbURpejs8aUhwYwp6cEstPDtLRCUrX2hR
QlRyaSYkZnZIcDliKUspXlpnWjY9ZHA7bGYzcWY4dlFwfEdNaDgjZlJ7Pmhsfnt3d18/VGwKeipR
e047X1MrKlBCV1YkZE1XaClXT2QqUUs+TlV0X3YqamdBbVIkRzExSFprY3h8KH1QXl97T353YT0r
KWFSMkBICnotTGhpRSolJFRuXmdKaEcwYEkqWj5kQmZNUi1FQDwxcnlBZUcyezZhRTYlOz57YD5F
e01POXpYPzJxTnVGODlXTwp6ejVWdnZAQjdRWXtQWGpBZCpeKy1DRFM2X3RKUzJscVhVe3JxZSpr
e2ZoND08KXZJbUV2YEJDN3lsPnhkISskeU4Kel9TPGl9azdVayZNWUJKYSpYcXEleiFfdEI+cyNO
eGFfI2ZhLVooZm95c31hJENsN0AtNT8zRHdVTW83U3FPYXFXCnpNKypuc3FwSkFUZCNgfkFna2hT
X3U4dzxfRUlEYl91WVl+I1U1UV9RYUJ1KFJjczxnbmJ3UDFxbkJ3ZlMmd0pPXwp6JjZ9PHQmZ0N3
eVI0UyZMSCRYJWpBfWFlVUxzSlZUclomIzI8JXVlXz5NVXo1VkhqI2hYVTh3KyY3MSF9QUEwQ18K
ekthSFhZNjJaVWIkbjA8a1YpTyFuUktVZC1VQWxiWiMmdVQ/NGkzR2VSNFNid01YYDB4cTNXdyFs
YmFGYiFBVWx5CnpoIzBLM3EqOCYpV1lTTXtiIz91MCFRdz9mez8pKFZAbntye1RLVSZCPmkwan07
YlQ4ZFI4QEtSeVJTTlYpMjgrMwp6PFp9NzUlSGA1WWFVMzElb1MpJm5aJmh1c0VzUkJrKmNlbD0q
NmE7fSlYc0R8XklTKHFgeT16YEZNNFJybnR5cyQKekx+MHt2KWJidmReQiNeajhIY0dKcWlRT1du
Nk1+eyYzQ0BEQ2M5PEpANiFWVm0xWWlNNEJnJEs+K019JHtAQk9mCnpKclY/Z191aD9mPGA1KT5v
SHJpVUhKUW5yaSkoWCFFejxCYjduQlpfKzh9fmBSJmBTNSZVIW16UDNQfj5zR0Zubwpae3tpPUlk
QEheXktxdnFKMDAyb3ZQREhMa1YxbUVCMihiVkYKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlm
ZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTI1Ni5wbmcgYi9hcHAvcmVzL2VjbGlwc2Ut
bWFyay0yNTYucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmExMzVjNTRlMTQ5ZWFhOTBiNjEwYTY5YzhmOWJmNmRl
YjA2YzBlNjcKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDE1ODI1CnpjbVg5X1dtc0VIKCs9KHFN
VEAoO3lGPjkoK0AqTU40VWl4JDQjbkxJNmZmQFgjaTYqbnlJYzczeXgqVEJDKWJ8Ywp6Kl9uSDBY
R2JENSlEJHBLTmwqYSowRVV2SHRRRyhPMU57akRLdF9hcThNKiFiM0lLP3VEYWxHe2AoJk1VXyt9
WF4Kel8/RW5EJmsxPi03YEl1Q3EhNWxvd1hZMkdCZCFwd0lQI21GNjRmRSNCNjVkMTtpbW47QWQm
JWRDYVFudnJHQEVACnpxZWJUbGxebnlSPFQ4c1ViY3wtSlBHQjJwVj1abUNeTHViRlRpPjhLU1Qq
X2V0I2EtNzlDJmhkVXtKWnpXYXVybAp6O29OYUlafEVFfXZ+JVNuTioqX35WQExIKk1JeSpmOXd2
TlBNRk1NKk90dXVxbS1oX2VBM2g+dzk8fiUrdUhGdXgKelB7dzEoNGNRbW8haUQ3VUBJM3I3bCZi
MCRkJSRzVjx+Sj5ZNGdXZ29DK3lZNzN1JlV6ZTx5ZD8hO1ZYfWJad3B8CnpeTTZkTFBpekB5SlV7
MV9TRmlCSVNVSmt+UEUxKkk2RTkzcDw1Y1JgNihqIVpSVXNPMzZeJm96OCk7enRaeXJ1MAp6NEQk
KE9EY09IJUlQM2k5MHpwKTwrbD8waUN4JlI+LXNqZkp6MFFeY2x2fWpMc3wtcTYlWExeaj9KJUMj
eH5AODkKeipHRE9hRD44PHN4OUQhQ1MyOEJhbGAxazM1TFpVaEJPfkB3a2AzP2tiaEpwWCV1REJB
elY/MWMlVzF4eGk0eTRBCnpWez1+bTclRFh+PXloN25gM29tbCVVJig1JDU4O19pNj5CKysyU2pF
dEwlYH5ASDgyQ1R+e3RwMGxLQW8zd1MlZwp6I0tPIXJGNGZqbXhicComNEpgQHwzaVUrRCRqV35N
QVA9d2QqaVVMbz1GOCpmQ3l9KCs2LV50TTJaSmUqayRLV0IKeiNCKjJ2UDB1fVBPdCRCRW1RKUp1
UkgrQnZDdVlgajV4Q095e0JBK24tS1MrdllhbT44PE8yXlhVSTNERzFXJVVWCno1NSsrQl9vWEVR
OW1VUUVJaUhqVnckdFlmKnpufFY8XyhOP1ZzcigrRCtoa19TMkp0dSlSe2N9TVlVYC1mclZVdgp6
IXdhNCN1fHppfk4qTWltOyZnVHZIKWhFRDkqZF9neEhTWk5AJj51Kl4welhvUU1SMSgqNn1qJXQ7
a09NKVVpc2sKenJ8ITd0TFJOe3ItO1FIWHlkNzV7S2VvMkVffnpgdCRaM1l3dkUjSTlzV0l7S0VB
Z3pEQiRsKWdJaVJjMmF2P2JKCnpuaUtzVC0jPEooXzRrPEdyanJuVUZLQnB3RS1gKGI0Sihfby0/
NzF7OCQ8cFlyOGtJVERxREwyVHpJS2t7Uyl9cwp6X1ZSR3JRZnRJflZCZiYzYnAyKENpe3sxQTdt
X25DdVNrUHshKTN0NG96RDduRllWTTVqTD8raGMwSUUzYz5WdEgKekFmY2w/SCM7OypMWChDOFlh
Z2wqdURFYVB7UWg+cnw4NE9XKGtUWEhYSEZnTWNOTnZTXzR9R3pIc21mam1AYjc0Cnp6bCg8T2Zp
PjtuQnZHZ0dgSzIwa0xoPTVFWCR+MWh6VW5SQWYqIS1uRGtwZEg7SGlVaiF8bHk3UDdJPlo9Nngz
RQp6VEJfWUUjR3VTbExQV1JANm1eZT93K28mKFhsUThRYV8pSjNuYV4/XmUxQVJ3Sj8ocTU+fllp
NWI2UTY5cnNKansKeldedyZjNHx2QG5kXzUtZ2hRd3ZCRz98SlN2MkpKS1JXQHVZME0qXk12Zk9Q
ZUolSz14czhuYEgrJFdCZit1N1d3CnpvNV4+Mlc5NilQK2Y3XjI/JjA0WSlXKiZ9Y1BBM0J4M2xW
UlM1d18pUkkhJVIxfGtWaEBrNnJ9ZihJMy0hNVdeUAp6LWR9V2J7Izx8QmNwUW0/UjRBMGZlNUU4
MiVzfU1pSl9nK2VQO3tRXmRQOXlteXc0WVh5XjZHPz81dlp1QX0oITIKeip8eDcjWGlCJGJgeT1y
WkNsQj1OZVdwVlFQMkh9LS1kfip8JE5VYSktKntjPihZcGFVdmMwNHhGRillRzF6T0F3CnpBdzQ2
eCU/cChgK2BJZCRtczN2JiswXnFKdWRVc0VSdWtKKD98U1JJZlRVfE5RX3FjZ05DWHZmUDBvWWdv
K2Qkbwp6VzYyeUh1ZlJDKitlNGZDKTF5JW8hT0RpN3NFeWZIIz54aVEmRkFONVpZK3UwT1BlYWNr
LWVyPndeMjQwI2VSdmkKej1kNXA2I05GJCEpOU5OM0MhcDdaZyhsfDxGfV9HQGlEUkpYM3Z9STc2
clFnbUdqeWNZSzZma3x0flozPUl0a08pCno3MHJhQGVtOEtQaSNkWjlKUmpFR0ZMYj54bWlaPGxe
dyFjJmZUQjQ4RjU0QTQlZEMzIUV8YmVxXlBNaiY/fml2Tgp6X2p4ciNIOFd2IU50bk96TEJKSyNq
YU82aCpLcyh8JUVrc15aPD1pRyZgdnImUEVCfVBqXz1LfU98e3MyITI1eTcKeiMmYnJAai01Vkxu
bXdFYjdgMU98JkYyaWAwKDElUzFjYEJTZzY5cUpaRjRzdGRAeG0oY1k3bjtUZyUlRkN4am09CnpC
cD8lNW9lI1IyX15LQF5EJUpeN0Z3NXxSOVk9UXlVQ3dLN0MhTUBneCMxS1hmcEdfVU4ofXxjXldY
QTc7SU1oSQp6KkhpJSRWQmJwIXJBemRNbm4lQSU1c2E7NmJpZklRYktwV042OFpCPFBmJWI8T3dL
Vz1aXnc/Vm88RX19MjxCbikKej9GOTE3Q2VWSWxKVi1SayRfb2hUP0w1ZjcyeigyOXNDPkVaP2dx
fitLZCQrYVBzU0o0JiliYHNOc19sLV5sKV9qCnpIdiYjc1JlI19WaHFQTiZWQ0AkU2FDWWNoPiph
Iz9gcHE0cnZyfm9TOShWOzV7VHdvNUZ1VHlpOzY5b0M7UXYrfQp6N2pQYHl6MjJ7P1BfYVFuUD5R
JX0/N2h9LStTUFItKTN5NUNpJmllelp9VEZTVzAjai1ZMFZQNV5xUzVBSWtNSUAKel9NR0Y3e3Aw
d2syeFlqa1klaHpjK21tOzA7QnskdnA8dTFELTQ1RWJTazkzbzYqV0lIdGI0QiMhfFUjV191RG13
CnotT3tDYkg5RENSYT13YiREbkBuTko8WClWYHxJNEBAMHszSWxVTVN8VFN+Xzc1ZTJPUVRUZzcm
b20mfFc1KkU+fQp6V0lkOUImNF90MDU3U3RJa0ZfeXomZDtfaitIUThmKWxoK2N0KUZreldeUmNn
NiRtKDBoZGlwWUJkbl4xbUcxU3EKeiN0eW1+V14pS1YxZEV2WkspJjw5eVZBeDhpSUdvRU9YN35S
bmJ2R2l3PUp4X1hjaGdfKmJ4YzRiX25pIUVjdD5CCnplfndXZGMmNlplelV1amR6QH1rLTVENVoo
TDU4VSkrdWR0bkJITn5ZaT84fTY5QSN8QyQmb1pVNy0+OHxjQTNOXwp6N3QrciNGTWp1TG1WI0I2
UypeJCtrVVp8LWtjIXFKV0tWZk8+fjhuLWBgS3JUbXchPTtJJmhkdXZ0ZVk3UUhxWkAKemg5S1hZ
JjJCU3NHMDFUQjE1bEpGTGAhKURgVjZfeC1TRGFsQ3YlZXBGLW4qTFVROXZuIz9GZzFsQEgwVF96
VzBnCnp1YV81QlY/P09kK2wqYyFqZHp7TFladnx4QypUV0w8aDQqdGVwcC1IPm9KTUAlUiZtSzRe
Zlo5OCQwUEFaN1lsUAp6JGlCWFgjUURxMHkzdXxQM1cqJVU4VVhCbTZvOCFIMGxuX0JGQV9vP3tU
cChKY3Rra29nJStBaEY2MXUhWiR6cVMKelJCXzEwdSpqb2ZjOygrdWkoQGp5SEpEUmg1MX50USpV
eEopQztNemlGbzt1OT50b0txVi01bSV5STxDeWEmKnllCnpBOTYxJEBjdVc5S2V8cnNgUT4/YF5D
SjdnN2E7PE1PaylHZDV9K25LVz1ZRTUtZSR5SjdAYWQrSHpyQ3grMFImTAp6Kyt5X2c/RllzTVp1
fXQzdWFgWVpzRjBzYmIwTSE4b3lLanw7WDZjb3IyYW1sYitgel52NmxDej5qNDkle2BYTk8KenVH
cEkwRnNVI05eUSllZFZnZjEzZCN1WChTNmZ7fUpjZ1EjKX11dms9ZG89VWZyVF5Bbnl4UWN1PUlR
WW40KWZkCnpobjBtS1UmelZ2OXJGbXpuKXYmeyl0RjlfXnFmNmtxd350V3UrMTRebDIoIVNDPzJa
ISU7bn4rOXBjczcxP1lXdwp6WWIqYkFIWGd7TGRXaCNgZFAwYnBvWlJGbE5hRDVJZk4xVkk2ZjVW
SFIzSV8qVTB0bF4+RGEhZ0VKPGZKUCVWOUUKek42ME5ucl9yRll0UiFka204NkpJO05xWUxqfDNk
Zm1+Ymk0V3dWZztYLTgxNDQtX31WdiFiYjckezR2PT1sKVBNCnp1fW42aXlkTF9USnB+WWRKNXB4
PnxJaCEzPktvdW09I2AqPUsraC1tdiNkZzFCaGowditfIUNKcVBiZ2Z0Z09Sewp6T3leRjA3fTRr
OUs5MTRfYCtWaFA+PSkkam9wZSZocU5NV3E8OC04WHV9ZlUmJn4rOTV2TTNhRXhWTl9oY31ANlAK
ejU2Km4zKChvSk0maz4pVmgpbHZHVnROdGVhbE9ZQ0hnZ0lKZE5la0Mqam93azY/STF+TkB8P3Y3
VWNCdEF7IylVCnpBQXdWMEs2TTdZdFZFUzFBS1Rsb0p6aGZMPC1xOGBtYU9ifipWSzdlYDhgcTBt
SUJWIT5jI25lYXolSHAoMnJGNwp6Mj9gamNCJn5taTIxQ15zazlTSCg4eEpAKXZkTGk3Sm08LSgj
Nm1fYiM9WlYoZlJDczwjJjwzRE5RO2dfPzspbWMKemp4QEBJKy03X3xzVEx6NF9FXl44ZDt5WiVG
O1I+PDNXc05FU1pYRXktJlk0eHVkbWA9bVNlZCZgcTcoP1ItTyQ7CnohdDhjT2JyJi05K3lGdkVz
dkBsO3E2N2J7NElAZFdXVzY+bSUzIT02e1V+PSNobVo0ZzQ5Y1gxKH1RYCooc3R2cgp6NGFVXkw7
aFJ9OVMpVnsqYSkzZlUxQllsWCM+IzFCVXopVCVKc1lNfT1Gd25FJUdtN3lvdHR9cDBEQHdOMzZf
Y2YKemBTKHc8e2tuaCZZMjJRMnRFTHA+M0U9YGs+YyRWMj11JClwPDltbjQ9ZngjJGlCKG5YIXBr
Q3U9WkFUUGxgKyFkCno+VzF0Sns5YHsrZGkkfHdIakx3RjNLJEVGRHooYVZoP3JBfG1AIz1vampV
WDNlK0M3Pyt9fm5wUk8qeH1hR0NvRQp6RHR6KlpNTzA+QHF0LTUpRTdCQz5SeFkpb0NCajJmeGoo
WXJWTGJsOGthc0JwdSEre1pfYC19YU82UGojbXhMXmkKekVROShUbVZ3TSZiVHBOSHVpMUszRm1R
PmhCQ1FMSSY7cENiPExrI1FiUGFwd21pfTktJGVAeTJnU249fSRTVGpeCnpTR0E1Y1hXM2BHUGFw
SEUyPFh2QVowYkROXjtIeXhsJnBBJlMlWi1VNDtWanVUREA2JFgrRnNUQktMNy1vQTZmUQp6Z0Y0
MUFsVy1YcDE8enNLQjwoSH5xSXRqYHtXaGJ8Y1QwPVE+Xj1GZnNHSElHKmgleDAodkVDJWVqaGNi
cnE/SHEKejc7PVY+Y1hadDVCZyp5YXU2PChkRjBBdyRDRyplQ24mSUV6KDhiJTVSWWUtejVBRiNV
bns1fn0hPTlKNCRnQipsCnopQTl7c1RJKnlkYTdEdFIkdkRlI28yRH1+TlR1PTJxS2g+Y3IpSzk9
KXg4REs0a2l5NF9lUG9LJUYqWms/JFNvZAp6bzdXSDhYM0h9JF5UOWhLQGBPPCR5T01jVm58NnQj
QzZTT2diREcyZERReXl7cFlWRVE+S0BCV2w0ZU5gPz0lYEAKek4/VFlPSyhOVWt8MT5FWTZ7VGp9
Y097MFZoaSEhdFg/O2xnIXpSfmU9LXozeV45fHZBPHEwPEt7PjtxeW94TzJrCnpeamAlK08mKl9a
Oz1+QG9HNyZscSV1ZUY+ODJKMmZ2akg1MWwpdjQ4dyYobEozT0YoWUIqcjQtVjZhd1kjdnxnJAp6
NFE5UjR3P1M7JTgyT092aCgyT1R4K2spZz42SH55d09jUj4yNHlzTE9rI0tEIT9ZWXJqRnZ7fUxo
MWE4aHF1Uk4KeiFtUWQzMFl+ZjQpTkVKJkFANH5CLU85ZEx2Q0hBdns8aXgrekxWX1ZSLVZ6Sns/
SzJzSHhadklRQ1RhUkRVIXM8CnpLaUtlZ3k7V1RGMDItPjctLWA/ZD1KTjdQbHRmJlNCUlgoZCRQ
SSE4XjFSbnxgNiRRQFJGKCtgTEYoaz5WKHxTZgp6b1k0Zyt5NFVvKTtEbTQtcyQySiMhak5lYW9Q
NTNWJWBEM351RikzMXZuYiFRREFWMnlPUCF5a15BVX09MT59WmQKenEob209JXB8JUYxNSRGJmVS
NCMrb1VET0ckTytNWmk3UTdrTTF3YlJpeD90JFh8UHdyJjBTbXk5flcoVkJRIz07Cnp3Rnp1X15T
UGAtZW9oaDkmbWJBYS1qWG98aGxncXNrKztNQWwxUnlWNmQ4SFdLTiNqUnUjX1dXTyt+NVNGMkt7
aAp6KiZuVW1QOWApT2V3OVlAYV5PZ0FCYlU2eHBxZUFXeDtAKSRUZ2xsREd0OU5QKFZ6Jlk7ZWAy
NERPPm1fVmRCWmsKej51aWxBZjwmPHBqP14tVm5sI2koUldYbEdYfFRgS19PbyhFQ3QqX1EhVT4r
Ki1vcFooJWtGLTxMRytBWlhwbk14CnpKRXFUX3s9cnBqeHlpXyRPfEFsRTxsb3tGVnhOOFM8eHgq
PHZZV2EhIT4xdmVnYDMxbV8wTUhycmItVjlQI01eWAp6dytAQ0c8flpSUHErM2kxM3khVCtlIyNA
anszWSM0YS0rbX1reXxaUHcxa0tsUnBKNzRhfDFDaUlgOzN7QTFtRFIKejNgIW1zPCZQJkZpXnxD
aGdEQ0ZBaGY/eyl5UiRfYSY3NCZEJEVJPmRjNUZqJC0zPUtyY3grYDZeMHtfSHE2TEJyCnohdig7
RlZDdGk0eSRJPzh6d0ZkKDR7aSNkR3RjKFotbCNtQ2xFPzFDZjROSzJLLVMkNUBjWmY9RWE8S08/
YlVJbQp6RT9uP2gzZWdFJj9XP0plMU9hYX1XaTN+SDFDOUpvRXxAQGomSkd7QXc2RD14e20zJFZ4
RnhyJnlFNF9qQUQjVU4KeiR8O2VWQjx8dG9SM3tUaz1oOVFoWnhwUXNLPStGc3tzJjcjSFM9MS1S
Kz9hZm88PVl0Ml9GTG4mMlI/VEthRmxgCnpGdGVMPzMmU2tLSHV8fm1qPk1fcEBnbWh8O0g5YzlD
fShkLTE5K0BvN1UkSDlmaipsISR3TEoxZTtuV1RHPXVsUgp6cWdWTThpXm1xdiUrUkI+IVc8cTcl
NSZCeU4/SG1sNFBfdXJubmdRfDNZLUN4cXdzTjskQ0MwbE5WYjQwPGRiUlMKejhITHFqVl9TYChI
P0ZPIUU+SntiPHNMbSgmbHs8MD9HODRiUXBTKXpqOXtVNW48N2VDS3A/cjAjRk8raHZiJllhCnpy
bTdrMDYoWipWeXo9TEk5M2Q5fT1MRnFyaChLcUElTjRCaGkyemxjTGAwPnctNlNGN084OSU9eVZM
OTNrQyV2bgp6PjcwPzBVZ3U2Qk5QS310e3sqKS0lViVWcy1NJExiPj5PJCtWS31KWVhDZmc2JCNv
KEpIeGt0eUBvMSpMMWIxODEKemVOQWd7RF8rfnQxI0tONk5NNm5kMGJNUTBLeU9EWCFtbElEdnE+
V3pyTjZrPzcjQUc9UlRoYVEtbjBaVW5Nb2pTCnp2Y089ZmFBV2RHTCRyIXxNUmFtVVl9VEtGOUBZ
QSlQYV84fFNrQUpfKSsrU0JYb2ZGaVJJelVJVXFEaXpOQFlYKAp6eFNLNXFSbFlWWjJEOzl0ZFRZ
MWM7SGVBQVJnUmExJVV3aURBRk0/UlJPfXVgeGREQT83WFBqN14yYWBiRWBxa2EKenNPYDc3LXJ8
RWw2QTl5QVliTElTOV5TSUxSeGJedTMrPlEmIzgpTCROYSZtZnswTDRHPTVWYEJPWW1GKVp8Qn5x
CnpuKzt0UXdDTlhFMUQrfTBeJiQ2ajMrX3YjQ0pMJm9TMEI1KzZNOSp8c1QkSWM9R2NHVmMpMyU1
Smh+eGV2YnhUQAp6RVFIfGFmdDhKaGdjWUU0LWU8R2laJUpOK09+UjFUMmhFYE9eRyFJT1kma2ds
dSN8TGU/YGIwPHhwZXUkQTVyeEYKeiRjVXh2K3dUY25jUlJySEhHOXhtdUtSOVBieH1SVEIkTk1w
Zy1EbFVtVkJSNm9XbilZMlRsK2p3JipDJS1sKWNtCno4MXlkVVk7I3Bhc0l9QXk9ZTwjPSpySDVF
KUVhe1JhSkR7eShlKjRvTnF9VEt4Z1V7QF47OGxmWih7Yl9xPStWdwp6aEk3emFLd1BtTWhLeVJD
PkE4VHArU3M0V3dCX3BJdT0mdTQqfDJmQDlFY3VhVk5yTzUkLVA9Kmk2I0khZXNRYyQKenY3Tk4p
Y3F+YUQ5UT9pSV94KVphUl4hRGxENVIoOU1JMWdGeCtCa1RnOFE8TnQ/fkVvX2heJigqUVh5PUpL
YHY3Cno9eWF3JmV0b3BRYUJ0c0EtNig5KkRQfGs/eHVUIztYbV5+XnJFOzVac3VNd201PHdkQGYy
OzdOJUczYFFeZFJFUQp6Jn4mZC1IcldBd0lWJWp1dmp7eWBOb24pYHdsXnBlQzwpUm9HP1VJZiU3
dUUqNn1zV3MqPzthQFoxOX17TkskI2MKejBlOD8lKUYhK0tvTW9jUz1TVnE/SGZxMGA1cUthSGxQ
YDlKa2Jkaj5aYWp6VCVLOyZsaU43VCFzP3otPGo9UlhRCno0IzFTbSEtdnoxVklnRWN4VHgrN1RL
I1Q9Y1h6SWc4O0Y/fDlMejZqTzB2ITc0Rk5rUFEjJUNfek47anJmaTBWTAp6ZExuTj1hSDZhTz9u
NSpxXjk4cG5zLUZEIUF7UzwjVypZdjV7aXh+ayNqcDc9OVZ5QjVxY0Q3PDw3OHQ9dXNRUmQKemEl
YUBmMV9reElYUktEb0BvWjR5Q1dhWXF5X1VBKSp0SW0wWH4hVn0+bzZmPipQbzktc08lYmsqa1Zs
SkYhdXAzCnorTEE/QEJ0OE1ANCtiUGdISSM5ZCh4QzYmen5GNUhWUG9AYWBjejxRMWZgdUd1Y0om
Uk8yeUVLUGJ2Q2V5I1ByKwp6eTNIeiFMXjJPPDsjUzktYXtaRFQ5VmN2Rlk/emRwPnxIfnJsfWYw
Pj5jX3JHWntTXkcrcVA+ZUdid0JLPWpNN2QKenJMdXtuPGw3P0BEdW1FRXVvO2BqUWl5ZT5YSHY5
QWBLSmpMR19LP3ZES04+PW0wOHFOfEk0cSZRTX4jTD9tJGttCnpfK3pzM2spZGtLeE9+RUBTP0FO
c0xTazA/MzdKMExySTgmTll5RSt6TFVGbHRrWUAhYTtqRGp4MFlUdyVDMX1Wagp6c2VvdWYkWSEx
VG9BYDt2QGpTT002T3FzcFpYckhKO0FXflEmI0huVWY4MVVFZHNiZE5LQzElWGEkUVMmcElTIWQK
em81UHw0Zk43LU5iVH1PPkFAWUZSK1EtVjVTdyZTc3NMVUVXITh5OVhGVl9FJTxEMW5PUDU1cGsh
ejNwYmAmLVZfCnpsbWFYTyM7TW9CRkJHTl9LOWUoUXcteEhzV0R+O1RBbjVXYDhhLXp+eXVWQ1cy
dmpgOyZXOy09NzJ3WHpLNzs0Xgp6VlZuVzlSQnRaJFMySj4+UGtvNyMjZF82cjQ5bEB1MzIybklf
Xz08TVlGPGZVQk5eUWNrYlRBJjxzTjEyIWh5UkIKemo2OXNAQ0lxVG5AdFhtd1dGPWY2UDA2NyZZ
WUxSQ2huJHNSP182TShIMnVsSyVZb3BDSGYxc1M1U3VaQClIUGRBCnp5JDw/KCszUUZLVEM+Pn1I
PUBJclhlfUNzWkIlSl87YEBKcHtVSjVMc1ktRHhVT2R6PypCRmg9XyU0QzloQ3NrdQp6cVgmR1Jy
dUtIKT1lR1R1b0gtbEtTZWpkK0Q+eStVQy1kUDJldT1UZEhzQTxDO0NQcTUyQlhFdj8qWXc+KTlm
UH4Kems2WEpEPCErb3BUQENNOHRRPEc7Q15za2NgUHUwJXM9JU5NRT5TKy0/JGxnODEpfFctUyhV
bmN7NGI8OWgmX3JQCnozbzV5bkxBPEw4SU4rYUZaKClWUHNqTWJGY1NEdU1Mfn5Rb2tyWVpeaUY9
O2l8MUg9IUxySUpgbVR1V0JoTk5KKgp6VjgjfWtoeDY4ZSYxTUhjM0QoU2JzMW5idDtOTk13aHti
c3klb200VDlWd3VNT29jJklCZEpSPFQtZnd4cnhPc1QKel56TU82MzZ7UTMzNkBMKWNVRFVybUde
aUYpJipIOGszJUtvKShVcHYoSEMzYHt7KFVEYFIhVz5mPkwrXjRBU3pYCno+dmhqNih2PnlyKi1S
K04hUW5zV1U8e1JJVWJfelgmN3Z2WkdQNEk4JT99SnQrYGtGSURJVU1rbkFCYnB2RnExbwp6UyFr
PVhLIX1MOXZJU0E0eCp1e2poVFVjMGNLem99S2JkNzBvXlBqPVZMQSVJVmRGTXxQRWJtNGtMeHE0
c1VXPUEKelA7fT8lPzdmUyYhQm9EYi0/RGBTR3NZU20tK2FxbzFFWFJqP1MkNj5LZSs4Qj5AWF5M
c3ViPlgxZjxVa3dmM1MqCnpFTTF7dkopRl4hSnw9QUZOYWNxUTtEfiUkPFBEMkBUbXYmRGpOTjRJ
d2VCJVlYQXtyJUQ5QlU1REgkR3QwdzU/Qgp6cX4tPWtZfVd2M3REVz5mVCFvbUZtUjE0ez8tYVR4
ZWlQNUp0QUU9KnlPYiFET2ZMayh3JlUmdFFofCtjTGEtWmEKek8/dykmQSl5Wk9sTzElLUZhJnU/
I3JSKSotPndxe1lkU0o1QE1EVm9OTTdFdTN3YVdFYlZWQWM0OVZ7K0l9UHY7CnokWjhydz18aEVi
YTR3VTx6ZlBXIWk3bEo9KTlffjljTCQ/aVkwYk0zc2NvSyk/cnBIK1F+bnxYMmw0ZExjIXZQWgp6
NShkMmhlMnUxKm9mWTkwdnp+LV9SU0FxTTJMN1hBK3JJZzBQVlkwbkFXQ0VkZGkyfDkxfGdAI2hX
PipNVHR1Xl4KelZuPDdNIX1lZj1DNFdEYy1OaCsyN2clNHMlU15HQUM0RDl3YGBPI2BpKiZMdUd2
Z2E/YmJDSyZQKkhBfXZ+TXA7CnpDd2tDPjF7N1FNakBEfXwoeklQTSEyNSlCQSVyYz4+USRXRVVx
NT9gMnYqKnw4QCljdTVePzdHTGR3dHZGezZFQQp6MEJkc1VtQWdLaVNOXjgjZSU+fHhSSCZoTXZo
UmE+KzBFTWwhPCFNOUNFPzc0Iy1zRW9ROU1tUzlzSEIqcy1afTwKenxNTEtoYm4tWCE+dn49X3F1
RlpNdnY7ZEpkVk1yKU0pc18ocS1jSjAxPHpwS1IlaWRsZDZic3V0c1kyclFofjVnCnoqV0gzbDJH
WEFvbWl3MVYobnZuYnN1VkUmKUU/aTdDb2MzPSNzPzJ3d15MbzZyfjJVOVQjb1IyYzM/NkJuSFQ+
ZAp6PTdBVVdRfSROYHQxMSYpPm52TCN5IXs7VHZeS0QhVD1odU4+MjJSRyhrPH1TOTZ5XzRzWDc0
K245QW5lPFFISXQKemAjNk9MWSp2e2l3SUpuNTFeNWIlPG04ZXBKQUVLNVBRTzQmcDFOR0UmRlN9
amNHUmRwI1NZPl5jcDh6XlZ+UHE+Cnp2YWkoQWQzLUI+PC1GJHEhWV94dD1WKWRyeH1fYkdvI0Fe
PlZoREpgbis7NVZmWTE4MzlAQWp5NEg7MntvdWFaegp6K0UxVU1CcHxpQ1dPKHgldzlJX3UtNzRr
LVBzOFRAIzlMfG0tNjl4SlFARXx9MXdhaiZhVipEPTdAfGNIQlBYaH0KejVMS1c3ISVmI0Mwd05i
dHFIMjlwYzJXRFFZUis+NWZoc1N+O0wycCZkZFpgYjE4a2gwPjJARyYjeXBeMmRFeXB8CnpKU2pE
I2t4b2NRZjl+bUhOSmgrKDJ+KHEkc24yOWtKbEEqMmFycyNpZmFHYXRRNDdEQGE8cyFNT3JjNGho
VjErZAp6I2dgc2tmWng0NWxXZkw9VXxLT0I7Q3J2SzElU0ErIyZRJXl7QU5IU3lHO35yRkFqVURx
UjM7NHJ8SkwqIzxtfmQKekhpOGtUSnAjMnFsND9xPTJfWVVnNnN6OSlWQ01kRVQyK3lWSXg0aW8k
YTgmRVA9YDlnUTMrU3U2bVF4RF5GbmBKCnp2cGtUJFpEWHl0SH1oVnxLe3JOOGB9UVVoOyE+WGp0
bVplUHt1THZZVkFwLTk/azhIdllhcWB7cXE+Qno5ZT98WAp6Ui1aMzJNbjVEKiRKZSM5MDtaeD0w
KEMxXjxpaHlTbzFmNDNIOUNIdGBxaXk0b3N4ND5rXm51VUstWVEpdnw8IWYKeko5Y2JQaiErVWAh
dHdkbEZVVzI/fEFRcW1nKn4qQmc4bXo3I2wtbSFtODleNj0hIXVJPzdeaExCeUhedkpIPi1DCnpF
K1dXVjJfcUA5TkhYK0BOQ3x2XikwUHhXME5BY1czSEQpfVl1NnB2VyRUZTBeY2MkeWsrSXgpaWQo
T1ZkbkFwVQp6UkBPdzhXKnpZYCF8WEplXnh6QG4xN31EZz9ic2I3Y1NtUzZkRmBxYUYrbExxTEsk
MG9SVjxDQ2M4SyUya3t4eFIKek0zQig8dlU9dDYwMWBQQSUzKS1SaiE8aS1edz0oYTJCKmVHYD1B
XktQeyQ2cCowWTxMVWQ3JFFQNXNFPjZqQTZDCnpveER2VFc3KCk2cFE9YTlPUVFaQEU/QzlqJX1X
QSVfSiFiM2M5P2xRITRjKlhEY0o5eHU3eTcxcmQ4MDRqJmlLeQp6bSlfM1BkXlJXYys+Qi1DcGZ7
fWpELXx1aGklSiM3OzZIUjkoVnlYNlQtakw7eGBSRVU3eUJeKXVwWEk9Vz5PPXAKemRLWmBjRTJY
V0hLXlZzZjBkbG42di1vOT5pfl5yKVphNVNmbUgze2l5dzk5NTI2LUwqPktWNmp7azdhMU82JX02
CnpvLXBMPGE3Q0YtPmF3I1dVfT5DKSFYXlc/aXpWSUhCZTttSEtkaWNEbilLP3NXYjNlXjcpYkBD
PlhHJmFhTTx2TAp6XyR2PDkkTWZfWTk+RDxzI2FpT3VkMm5pdUMlcTlqKitGOEdac3xtR158JndA
aXZZP2M8YlFeMm5oaGlJWDVYQnoKejcpPEY3a2tXbzh1Qyg/bihjYzNuXlFqbiVHWDFRNytoS0dv
WD5HandUYzxfRkJ3RUN4Xmg8YklQNyF+K25JN2JJCnojan5CdiYoaz5rU19OQVdmZE5STT5HR05A
YkY1QkFreHprckFuMVpFPEtNNUNLJlZGfHdtNHZjNitAQmRkb1p0bwp6aVhoPy05fDdUd3cleU9A
OEIwdCp2TXckfnhPaks2TF5jPWN7M3UwTWFoeVg8V2RUb08mZUh7ZSl4LXVZTFhxSjEKeihGfj5o
KFI1S2FpV2g/WF85MUdtKFA5VHQ0T2o3IWd6c2JeNCZAWG9BNm5IO1heWk9FRkdTOCtiI0c+cUR3
P0leCnp3JDg7fEA+aWtmPHcwQGB7XnhzU0xRanN0RyhjT2YhMShNZFZ9ZTBLZFNgNWpFPHt4diFH
K28/Vy1FUzY0MUteZQp6SXojYV8wP3N4TVMwUVZtPHRLdWo3JnMyYkFoalEkR0smUVZDSCFaJm1g
MjlCTEF1U1Q0RSRmKGtITkZme1FYJEwKenhXOSNsVyptY31mR05LaTVQKWQ1YWAwMmpefEU0JHBH
ZzY8SGdNMmMkJSQ0fil6YSVmTkRmQUhUQH1kO0dZJXgqCnpxIXp3JW5Yez0qP0lLOEcoMVZoQiNP
JV8wR1g8TlMmNS15fmNWUzNjRE9kdCFJVGA9Kj97QTtldX0oQi1LRkNTMgp6TWQrWWImU0ZATnlK
ZW0+a2VfR3I+YmcreHMmPT5iN0B3QnVhdyo1R1ZFdD90NzxvXlk5NT5MfVUyZ0dUPWVEcVUKenZ6
THNiMCZBa0t6MExwKHgmaVJXNFBPbF9kcVpUfWg4K19CITleMnZAc2YpeTN0VFJMWEY7aH5RWHt5
cE4wMHBWCnpYdyVqQTY+c18kNW51KWAoK2d+fEF5d1FGbTRzQFdoamxsQWo/fnFCZnFLRj1TN0gz
ZyU4VnNIeHp+MSRgcX4pPgp6P2hvfkQhYDF9az82ZzdgU3lBTnVsbnlkQFpOQDVYXks8TFIwS0Bq
SG83cEVFVGxZO1FKeyZmNDBJWEkwKXs9N2sKejMhLTx0SztkVypjUUhOWDZZI24/WCoreUBUYDwt
WEVuQi0lOWckeGBYKnh7K29ScUYrcHltbXk0ZFokNmN2Vz92CnpmUWp+ekJhbTFMbFVhIXpzTTZT
ZDdacDQ3WSRyTEpoPnFMUyskQXZVI0JEJGk+cTNwTShwfi1CYmZmSlg/cjUybAp6VDZLNTIjLXM+
Q0t6ZFU9eikmbD1wdGghdGtudXJrbXtCSGc5MHA8NXV8NTw9QDtkKkEhS2A4UldpSFQhdklKdi0K
elBVUVhKMThBcHp2bil6S2BDQGxHTnsja2ZRKnlSSWNLUkRQK1koWWlzVztzRE18YyRKLX1vQ0ZQ
aDxnaUJ0MGc0CnpGeH0wZWQ5WUJLSWVrKkkoQzI0RHg4SH1qUlF7az0hZnJ8alBaMyFkO2hqTjVu
dzJDK1dkVzJsdnRSe2Y7R143egp6JmF6NTRLfndlUFhaKjtyNyROYjZpTUV0JT4zQGY7eUxLZT8h
UWFodVlOUERkX2Nzen1yNGN6MWdXajhWPzNucTwKemlLbUFtS3gwd2AyMjRNayMjVFAkNHJqejdq
Nzw2dnJyansrdkJ6NFEyVDN9VlNyfUBldnByO0ZCUmZmVGNnVHBlCnowTF9yaj1vSmdWaGA/Oz4z
VjNScEJZdTV8JnI9NG0/P2dfaTB5dWk2Vnl3UWRaeXM2dTFwaHN7WGImQVEhdm1NSwp6TCglQmBZ
eWIzY09DM2wtI2pkcDh7cXZOdS1FWkJrRGptZVMqTD9uZkpaOD10UypBQko/RVNmNE9TJGh8PU5G
eCsKekghZWN4RCVhSEw4UWUtRFc0OV9SV1pHT1J7Ry0zZTA1UihYeyFEaThJe1pGSyVvTkQ9PVQ0
fDJMKnxLR0V0fk1PCnpPY1YpIyk2TUVweDYkYnJacHFFX05JJUMmWF4lQndvJCRnKVNXMGU9Mm0x
QU1aVjJzeGpNMDIhOGJjd3Fyej19Vwp6P0pSQ0c3Pl9OU2MydDZAaStwKjY0Vlk2WGdFWjJVaFpv
KzNMayE8N05wPn49byNBcEJBJntBS1ZUekhOZUxKfDwKei07TGYoI3drM0RvOTJ6ZT1EOVdOKyN6
dUw7VEhtTnAlWk07KH42ViZsd21iKFdnaTNYZHZoKjkxK29CfU01Zzc8CnpOOV9Rbz9rd24/aHkm
JXVYdF49WEd9KVczTF9RNyYjND5+WEZeSWxSMjxRNm1wSGs4TzF3Vm5mZHNPaCV3dDgyfQp6RXFZ
S3s5cVQwaTw3JitUX0FqY1VDaCpkeTlTejIhJV55YGVpeTlPYktxST1zakVhKjxeSDJhQUYtLUo4
I01DJEcKeiZnciZ2VjNebCo2PGsqSHR7OSRxS3s1OytIMlBwTj9USm55e3VTZDM+Qy1ZO0tVIU1U
R3NRdFRDMjx5fURiK2goCno3cU4tTHlkSVUhODZaNmFUZWkmI3k2PzVySGpiOCMhQUNxfTMjM3tT
dzhEcClBQmZBPGgqNlVuVUQ1QSM/aWt0dwp6VG9TbkB4JVNfanhsdD0wdF8hI01FcFF+OUszKGF1
I3hQUURGMzU7SDhDKWNLcTtWPUNfbGo+amhrbE92UUBoV2EKellaezEyPSpkPTB3MURESSVqdisk
JGMqYzUoSEtKNzdQa3w3JjdLcVN3e1JfQVkjbCh0VE1UUXU0dU9ZP0xuI2E7CnplMEQ3dTc/c1A1
c3YqZjVvNWxabl9tfExCdDI0MWNMZFF7T2l0JTJiWX1YZSFpUSpXK3lsUyM4ciZoRjxDO0h6Nwp6
SCsxKHUtbVRXfW5MaWZfNklhZmJjNlY7OHBNUjFiaVJAPl5hUCMtd0dmNFMqbyNZZ0tNWVNLREFK
blFSdG9venIKemohYSROQXk4dkEodXBAWHtmSSNAJH5PUDM4PnYmQHdWdCQocllLT249fXdjSTdJ
QmojKnY1Yjc9UGh8WDt9NkhOCno0MVdPLT1vTWlNdDUhU2ZqLUNeYWNBRjRZYysrVyhNVG5wRXZU
d2BqbWNKSEt3PCg7TnpPczlmWUoqO2JZJURlMAp6Yj9UZXFlQ242TG89Q2pKJH4pfX5Zaj1obnE9
bWpIZURHb2FXLXI7e2g/fFB3aXIkNW5uNG9LR1QjUUFDWmVfJSYKekN8Z3dmcWhjLU8xeExFUCkp
WCR5WlpaUVU0eGkpPjJGNyU/Rj0hPnNZc3lKXyt0bWhALVcyTG5CViRyJkxfKFM7Cno8aiZCWnsk
M0gqUVZ3ZippOEh3SFBCOSpEK2IrTzNwOSRzNil+IUomKy0kczdsVFE5O0tYIVlebSQtMVpkeSMx
cQp6VDA/Sl5NMiROWG1UTmsrbFQ1Vy0tQH41fTQyJj9IcHxFR2chZHcqUXUrTj47anFDYnAkJkh9
UWVAKUxCTHlPWHQKek14TUJMY0I4aEw8ajYyN09CYmxVb0hGdDlDS1EobDRmTnVZTnZufUlEaURa
MnVEK2N7SV8lYXs8KjIrYExhSnR1Cnp4LTxMPEh3M29edmg+cHFSTHdHYDgye3FkUTlKSEQ+fVBs
WHtTJVh8OERzZFBpUTl+KF9ydjs7SD5WSFdCOT19bAp6Q2Y9bzxeLW5DWnVHcS1CUCk1aCt3fX00
Uyl6bipUQX1fQWRJKXFOUVJ8S1Febmp8ZUZnYGY/MlEzVCVncDwzQ2oKel9fT143S1EkfVlwTyVZ
KnskMCg8UE9ieWg0OzFrSyNrTj9ieXxMWVp0XyYyKndWMFdhQjVKXjRIQ284dkxkQClzCno3NDI/
UWEmUGdqRT9ZaFZTM09zODU8eXNBKUY9KFMoYjQ2VT55KF5pe09KNSt2SkgtSmRuM09PNjliVlYx
aSZHYgp6QU0jZzFVcC10JUxEIyk5akNBbWFeJTJBVStrXkA5emV3YWhoUkhsOFQ5O2g0U1dad29x
dGxza2RnJD9AYGIhdTIKelQwWGNNdEApej1seSM2YHtBTHt4QFlDTj94OHdpfWp9I2I9bHo+KlRW
KVp6XnNpU2ZFLVAjN25SQEhjQkxKfUFPCnpJP2IxZip7MkN7P1FnaD13ZjN3XjxadUs8ZGslPjBz
KHt0SkAlYHZhR2BsfmlxflVSWVlfRDxgVihFcURzfG9MWgp6aCs2UyE9OWlSOFBkVTgrSDlzUDZW
KmYhbHJyITtGPEc1NVhvWSE8dXNvLUFwYy1Wd0c7ajl1PUJYWGlkMzsmJX0KeiZibjI1NH17c0Zh
PSg5bGBZdWtzTkh9bmFuflVlO2ArfmQ5Y1JgIS1VQzc+fGhUN2x6NXJNcSk0dFBhQDJ4ViEhCnpK
bmQhT21XbFl+PilZKUJBRjQxVk5nTUV8PGB2dmduYmRXSWoqPHg9MiNafWpuUy1KJmg0MT99VyFJ
ISMhcTxBVQp6UDxib3VsKGFxYkFueXMwYyZKZ0R7b1ZGa2MmSTY/QGxVPlooIWBUa1NmbHtCdWJi
TkE9eDV1ZkhzMSZMRV5Cd3MKekc8SDFQcU9mUWNgb04oMFYoSmU+WmFEd3BhKVoxbk1NQUdXcWFC
bFIkPTIkaCF4eFdNSExhOTE0TGcmJG5yTWwlCnp1RTtNLVlMVTN7VW95bThgdnQ7c1JQaDNycXV4
Mk01TTkjckxlPW5VT05JTlBrJXkqTHtaKndAJSRsUElHbTkmUgp6e1Y4T3BkfE1qY05EMDA2JFpC
I0JPIWJrOFRCd0ZzcjQya1lMRXNrKTMhSTZgJHBmcnw+aXkpaShIVGA7OTBjbnsKekJiTXYmOS1F
Xz5hKzZudTthXkpLXn40ank8OD5VYXR3JmJnTWg5P3spak14ZEl5V2cjTHo7dk5ZcTRHITxTZFlC
CnpDZ310Z1RVSS1hPCMyKkBlKHtEPW04eFQtemZDVldJfDQ7KE84VHxAenY8UVJgVGNJQFdAZGZX
TSFhMTBVbzNRTgp6TUU9MGA7bz1ueEd4eDNTaUxEd2UyZ3g4TzVBcSl2YSRBIXJifEw4QDJyZm8k
PiZUZjgjSC00XjR5PEUxbVNKOGkKek01ITBlIXNFfUxPTHZFRUpKVnYyKGdlKXUhPCMkM3opbT0y
UEtwZn16a2I/cTdkMUwoTkoqPX1MezkyZW92UUd0CnpucjdUfU1KOStxbmFhdksrb2Z9ZzY2OU5t
S3hBZ3U3YXdPKVJicVlUcz9ZWUUzKj1WRGkjfVQzVTd+bWEjbDNRRwp6Oz41U04jOUVuYjxpbVlD
MHRGM34lbFB8QGx2WTYzXyFDcEpKeEo4IWJKY2dLUDMwUn11JHdAO0hFPFQ/cXEqV3cKeiZpWmgq
KThuKml4U0VgVD9AO15xWE5DQzBNO19hNzZLclo2aXlDfjdabE5iJUJSIyF0ckYyWiNxUzl0N1JB
fHNOCno0XyNlT0U+Tl5SK3NTb2k5NyVwZFdIS0lWYnN9dyVUWH5SdVlqdCkqQ01DSz5fSCg7NDQ/
ZD5TSntWO29ge1EyNAp6I2I3N1ZgVVlFTUFQSUpIPUg4JipfIWJCY2Y5dy1eQF5tR2Z7MSp3dld8
c05RdElXa2g2SC0mcWd6UmE8ckNoQH0Kej9DTXZRPjMpNXFONF5qOUpFQ3goOHNONSFaVD0pQGh2
YzIpalotNFJvOVJpeWB4JS1pdnY2RnRVIXtKJSRqKXBvCnpzbjJ8MUg1ekY3UFI9fWBtQ0RyO2d3
b0dKT3sydD9FTUJ+OEE9eygwZ3NDPn09XjhOVXhAeCpVLVo4S3lzenEkMwp6WWxPZjZ1WitoU3Fx
SmY/aVhOUzRgNS1KOXN1IXhyWVFXVTBAfXRofVZeO2N3I2gxb0olI1lZbjhVKDVHXjEpSmcKeiU7
UjtNQHJJdXxNMiRIVEd7MEpYczx5RipYMGI0TWl7WjJCY2VtVW1DfDBpbFU5KXc7cShHZm8kfXg/
NCpYOHNTCnpyMiZiP3l4LTxUVXV1JUY9Km9GSEY3KkNkZkJkd0ZeVHBAKXplJnFFODFpYiZUQ3A7
WDF9O2ZeTD1zZ2sme1VlQQp6aVg1Tyk5enZHQUVRa3Zpe2ZGfUJUKml9Qk5eJn5DK0pzalBeTkwj
Mk5TPztPdGZFczMrODlqeXBJPX0/KnRaRmIKektDVClyc1Qhe2lLWDt9PVpsUTdnNEQ1dXg/cUlk
dmRDPjk9ZEsxPmd1SWYkZjRuZylQXmktbEZHKmBNdVE9eH1rCnowV3Q5REZeYTtCO3E1ZU1TbFV1
dDxyWiolSVFBI2JRSW5SM2g8QGd7X05ZYGVIN2FEckpWK1Emc0tpSjd1Mlo8Wgp6MWBPTD9MYEUy
dGgjT3FjTm13fFQkJSUrKm0tV1czV28zMFNTeyVHdTsqVWleIWBCOURNR2h9bil2RSg8Xyk9dSoK
emxzfGpOWnBgMWlERUpiSjZmZ0BwJV9MQHMmTyZYdVU5cWRaTWhXSDtgSWtxRjMmY1NGZjFgSXxM
dkIobHV4YHFsCnp3T2sqRmdeSztEdUxQRmtWfEd5aFFhRGtaajV3NTVvS1UmIXdAWUp2YW05QlV5
Wj0zZ2NFYFE0IUBOPyEtTF52Iwp6OzJLan4qU3tTdUg7N0RwfEl2WnF4ME93eWx6OUBoIypiaHdr
NCR0aWBvMDNucD40X2A9d35xSENwOEEmMnRCZlIKenlmVFp+PW5tPEtVKD48VkNGbkpSe011cDdi
P3MzJDE9SipCNzgheTZhcyMxPkFxMHxYTiYxZzs2d0Q3ZEY0a1p1CnpsQUFrJDJuWUNuIXt5LUdz
UExKT3AqdntkM0R4ckJXKSpAbnJKOy0jMn5TPWxMMFhYJkdnKWI4V31hMEp5TlkhZwp6ZzJ4dWJ3
S3lVQzEtNiFkKl42MVpKYUg9QVdzZXJnMDB3cl8kPkRzfTd6aUp5QEAxQ21pQVJKJms3bGZCTV9N
QXsKejE/P3hlP0xVdmE4dztPfWwhMXdjYntlUzhuSiZKJWNaQUMlQng3ODx6eF4pPHR3ezQ/SXQz
R2F4aVVpelJjJS1LCnomUC1ofF9QeVhuMWdJJTVxbV8wRmVZMXh1cWIlfndxRyNIeFh+fTJeN2pe
YHRne3olSTE/P19CRDw7T0xVe1BoUgp6dWhmKH55QDhxUmBod2tDXjgxZkUzRUA0fHt8Mi0/NkNr
NVVKanY3NSM9P0RBR29VNn51OU5iJlJudyFMNXVCfSkKemMkKjhNUnV2UEo9N24oe1BoUkVrcjFG
PCRFeERlMWZsITstVHB4ZiMqdVlgdFRNVTRuamsyWHYkKCpIKzN7bHdICnolISo+diE9YTF1ISol
aCVwSTQqZEcoaDQoJGhvVWYoQ3NfN0xHS0Fzcks8fXY7JjNUfHE0JTVOVWQ9SyNtZD94NAp6aGNE
TyhFblU0QVlxQEhlemN4QFheMFopVkp2eSVgQ09vRV9GVlRkYmg7cXNaZUp2KWpIJEU9KkxkXmpD
SF5icjUKejdCeSh7az1kOSVZTD9jRitMNXBIUVFANTh2b35rIUdOM1RHVHpiQCZxaT05VzwrK1hT
Vi1OOFMma04rK0FIZ0k+CnpVUz1fSlJVJFg4Njk8X0pzQTg2aWtOdTItTj91SUgpbG4/ZT05dV9x
LU4xbmR1WDdyWUxeNDBHVnVvMjZiMG4qKAp6PGlLdTxHcXszI0h6fVckT00+RWo/fHhoRDFDcjNo
Z3R2UjNJWFEjMSRSUkhrZzd0M15oMHNrRzhYTkBmYDY+cCYKemNTdE1JTlpKT0VffWB6bUUmVEcm
OTw1UntRYkchbihWVTBXSW5+TEZkSzZ6ajJjKWdKST89d3o+d2FCenpmJDNlCnpJYURjVUxAcSFm
KVBAIz5PaVpZaVErfl5qdjhAWV5wQyopUiFeODxTYzgjSUhhQHcpIT53c2R0eXpYUGdoJHF4cwp6
XmR4WDltPn1VTjRNckJLMn09d1ctRlBJcFo0SVdlNihVKkVuWkd+VW5wLWkwcXd5cjd0NnE/bCYx
TGlKMylxIS0KejYwPT5DNTAwJkslMlIjbG5ZcWtwRUw9bUM2RSojUT9RZXVWXk1HTXYlRUhXakUp
bDJaOG1ROyNpUjRTYV5JbV8tCnpESThwITY0WnsyUnZ0NShsM3o3bTkkemIzIT5gWER2Snp4cDhB
TEdgYFA0YERzWlVnbFVnbWN+d3RLI3NGajFUUQp6d3dlLTJSZnQrNTVTRXdQcFhRZXdBY2smYTdn
KkQ1NjtfQjA9Tmp8VEg1cDNCblFKbmVXOyU/YWRkam42QDVgPGIKemt8aXw7JDFBYjRCJEpiZT4p
cjkodkA4fnA0Uz1+NHBrTWJAWmsmalJRfjJ9RTc9OXRGXjhVUGV0TSpxTXVmWj5rCnpeNDh9VGch
KUF6X051ODllPmpJe0VWKnl0aVR5a2pHY2drc3JBVFo0VippI3UlPD1FX3c1ZWZkVEIhXiNWJiRe
Nwp6Vk9tYTsoeldUOWh1Iyl8akBqbWZwRENFXmJWQlcxSDNPe0ApcHF0amBGdz5sMjt1N0tqd0Uy
UT1QYktJT3NzX2MKekN2QXkxSktaaFBVMTMmQEE7WlolIXsxMzdeXjMteEUqbGtEJUFRUkFzMiow
TUM+Z1hmPk8oNU9MKDRfVDU8RX51CnpIPncxcXYyJWImZ0Y1KERmcHVYK1NDQi1GOTFOMnVKUGlq
ZVppQ1YwJnkxTkF6TnMqJkIkeVhvVEh6Q3wzK2Q9UAp6IVRCdTdmWiVXTUtUfVAwSXdFfnRRYDlx
WmZnKD4yZGEyO3w+NiFHQ2cpaWM1ayoqUio5RXNOWDhlPzk3RVVCUHIKendTd3dvKmY2c2dAOXJZ
JTlefF5jYGwtLVQ7UFRZejJzcFlGKXl7LSUkQHxnQyQjNiN5UUdRdTdtVTliVlFnKE9gCnpick1O
UjU/YCo8KiRpKkhYYmwhd209azc2MT0yRm8lQWpmbWZjQGlnXipSKjdpRXFnNFYzfWwhYV9PYEch
Nk4mUgp6NT8jT0RjNTg0ajA0UU9iSjhpNjAtbl5nVHo7RGYrS0VvQGExVEN6THZFdHNrYlRFMHk4
MFJjSXQyeU48aXdmNkwKemp0SXdCNk0zb15YPndmaFZAQ35ocmFIZUdxYSh9SFd0R142VjJ9eko2
KHA3TSl7RVVzeUBVJH5mSEN8MnRqXjhlCnp7TnlMVz8pclVsSE9BQyRTOXhAdnstOG5oZ0Z5MHZF
aWxiclRpMkNyYzI+O1VtX0FWfGl7ZWN6cnpLUi1nRmV3NQp6KHc+N2ZMalhvYF9yWEpiZml9dERn
NmsmNUUrJmxGYi1sTXEmUTcyO3VjciFHZzR2XmNfNkw8Nmh3VDM9JnBicjYKenlhcWhZcytxVlNx
X0E7aERRTXxARTUxXkttYmpQcFBeUz9MdkF2KUQ3K1VEa1g4TXc4MyZCZDExO21JLVZ5RkVMCnp7
KkhFeistdWcwVUh+b1UzPHdYMEh9NEtjSylYUE97Y01APUJ0YkA1PVVsbjdgPSRLNzwwblZCYD9k
bG8mSVdUYwp6aXw0enZsJHlqe0oleFZUYHxCR2Q1fTElSk5xdHQ1KXhOKEAqeXlOVm1+PWZGMVNO
NFdHRi1AT0FXfWlWKEZoYzsKelJuYHY9MWR5Q29HeU1pRTZNYiZLRWxMZHA5bUtCbEhUYlBMcWhJ
QGM8KVc3NlBxYVImcklYK3NPajFOVlJxNng3CnojcUxpQ3ZBM0tpVCt9eC0mQl52fT5jV1pVRUpj
UWcrY3xKKGJGe3RJVWVKZDFvYVRsUVBiN3lReD0jd2R6aG53SAp6Y04pbVArSm05UiRUaUFMYiQp
WVk2az9aflp3dGtyQDgyKk5rJDc/IWwkcU4wWitTWUc9alZTayVwVSttYk0oVS0KemJlYjkoVCRo
aCp7OGdFKGdeJlgld0JhUmo0WGhSX2dsO0JtYSgoYVJ7d31+biVaRC0wKHZwWCZVJm89e0E4d151
CnpXalg3aGVqTGVWWmotdEJFV2Z8MCVQVDdgNkhoOTZMcClKYENROSFjYFBEP3U+TiVLLT5geGhQ
QnZMe01ZR0pZQwp6UG1kZlgrSGFPQGE+WGU4QGkodT1hOVBiX0I/OSpYO14rJU9ZI3J9bE0zK0F8
UHhBTzBWa2hsJlR+cTdwTDNRRyYKem1yKHRrN29NQTVANm9yKHl8R2EpV3NhIUF2VHIhb2tnSmZC
JT58eEUxenpxSms1QE5OPTxnSyo7JW8tN2AkP1J9CnokYFc8bmM3d3RLVXNgIUBLdk9GWlNWRCE+
TnMqPmtrdTJoQ1lpcXt3dzVYVFI7USE8cDwra2tJdHcqWnFPX14/aAp6Rzd8eUNGXjZDbHJ3TmtP
Q2NFIzVidVE+S0tUS1N3UW9DWSkqQHk3YkN6YyU1V24jJWwrPDhMY0Faem1OZGNxVkUKekNtOCEr
Y3FnIVFBKFJDbyNXQGxAdERuOF96ZlY3eWwtKXwmcHhMfTQ8NGQzK2xkQmVtRyVONXNga1dSaW11
Xml2CnplLXNVKVM+QTtnRCo5Mj95blQlfG1NS3Q4VUZCTnczdElHeThaSjIwP2hCPkgqbUt8fFN4
WUE3MT8hSVJxWX1MLQp6NjFAdlkqWHYqUF80alZMVCY4NFk5ZnZjI1ZEZEBjb3ZiPTFDI1VfX25+
OWZ5OU4lNytZJUdDP2BKZk9RRWBWSUUKekk7SDZRWXJ9aTEtT2okbHdxVDwmKEBxRlhvUTwkWGNz
TkZJY1pJbWBULS0oMWQqP30jN0VZbH1FamhPV3gzanVoCnppY1otKkE/V0c9PFQ2JVVMQEVePmVx
JDVpRD5eRyN6e1dNMiFuU2h6b3h9ZnBFbGxmQGhnY3pfKiZXPEBKTSpjagp6WWQ9R2BEX3xzSEFt
QXYpZF8jVjlDKjI/YEpaJkl+QFdENz4reVY0WlIkakZ7MnlfMlRmJlRmK2N1Qkk+YEkkNTUKejsz
VXhOMVFjajluSW8xekA1Yz00OGsrcVo/akhNZWIxPWx3d1FjU0V4LVpiPmAkPjM7K19oZFQ4Rm8k
enlWOz8tCno8Mj43WSYzOGZmPD5oN0NLcD9pQCFBQ1NLT3pffVdObDkxfnZgMj5tKzk+az9wO305
anB3cW45antGPi0ySlUkTgp6UVhSMC1AdiF6SEBiPm0qNXNsKj8xMEhmMDZtK09PSzA0QVF0bXhR
O2xZa3Q+TEZpKzUySndOKSstSU1+Z2pwb04Kem47JXduSnw5MTwxMUFHT3ZrTSM1XzQ4XiRfWVFG
NmxSLSp5TS19ZF5CXyNeO1JtTHdIZnpLNTBrZlB0QGVFZCU7Cno9fUU7anFQayR6LXRMYjM0Mk8t
VSUjR0s1WFlZJmtMYHstJWpaVUBoOVUqOVFmWCk3N3U0JmgxRnh2VntBP1VxRgp6cUpSMmQ2aCQh
dUZKYnE5VyhEWG4xb1pOcHRaVS1nbXE3USlpelVnRjhrKEYwaHdJXnRMNyhyOVRuOSRLeT40TVMK
eitsN1B2X0NqaEA0cHZ3NzltWFp6VyowITAjUjZ7PWIzXjI5K2dGc3hHNDIhRkVaOz9RSSZjb01w
bkBnP3A0TzA3CnpjUl93RV99XnIxdj0xMUZSRXsxaSg4eUg3YyVNYEB2QS0tMWlDPWs3aXIkPCRM
PUU1JCtKYzZ8aFl+ans4ZF5JIwp6dlhmY2otblNVVXVpX3N9eXdeTkFJMXhAPmsreUJ3cmlsfnFL
Sn1KWWBSKUEmPmVyb3NmQjt7SDNId1VFP05uNFQKendzN2V6Y1FxQyNLUi1Xdmh4c2Y+aT1wJHwy
O29lPyt2bk58Jn1OQ3Q/R3pYLTgyciVyKDJARmpZU1o7dD9xbXBACnpXWVNmKHQoK0J1ZTtmJWFY
O0M2enBvWCN2XiQ4WT1JQWlaNFltUyU4aDBjNUx1SUxAMip4dW87ZztebmNVZXU3Ugp6YUYzNEhK
PjVYdCorRXMlPmNZYXQqR2h1UWhRMjFFOCh4NzRnWXNaWD9WSjYoQjs5T304UGhlZG0meH1NRSZI
Ri0KekNWPmkwTTU0Pj9FPnZxMGN9WFBnSkZ6UGdja0BqaFB1MnslWnI1MUNaTmRhKlM/KTFJS0JE
OEg/aiFvZnQhLV9GCnorNVhwTTZrUyg/MD4pa2tZaEJPJUx8NXZjaWIwXlUtQmxuaCR1UXd7Skgm
SXJfK2h2JiZmakd5YzBLaCY2ckhSUQp6NGZQYnl0RWdCYHBQWFc3YjtFcEZXbzMrOSlRMWlDZG0p
P21yLSFjaDRpSFB+Qz97TVlNREpfSkFOaDN2NHZLVTAKem1nKyhePShPaEhlNyltaytvREYxWSQl
Mi1OSUt1WWNaejQhJlMtUjdSPmNoYz9DZ3h5PSs5PFZxUG9+IWBOcXEtCnpjUEd6UihoSlNaNlpK
dHkrKiFyPiYkOFVrMFZnNj17PHFVJTh5eVl7SVZfKXdFSU1fe3gzV21OOzFIQypGNUVvUwp6R29z
M3A2bkliQVIqcVFKKTtBSEJNU1dtdnpwSX5CZG1ucyU+KUxvN04hd3tIdUZyV19PbWwrT3FPRyFw
YWNkI1YKemVjZmVIWkBaaCUtVDMycSgmIU5PPEEpa1k+Wm91ZWIoVEEwayZ6IyVoLSNXc15+a0lk
dVdUbWZiJUM2JExuVFRkCnpgZ2RzKVZHJDd1e1pAfnFJTWRoZGhLO0EwKVhyTyVBfXpidSgrWnJ4
a1J8NG5fKlZlNUA2eTMoMS1PMmI7fHxeYQp6PiskO2ZNLUcrYFE4cWZ2JCZNVytMazI2SEBGWWt5
ajBreXkteFNtPyhrblRaY3UyOHtyO0RTWEtGXz4oR1cqb2UKejZJbCpoYXFyJGQ4N0w/V14rN2sm
PzAkRnI4VDVLcjRjWmc4UkFDeDxpYjEhcFErfnd3K0Q3cyhFZmF4cjVQUWg9CnplMjMhd0BmZUJS
PVdASFY2TE4heWgmV2xMR2d8SkA7SFE4dSpZNnRMZlFiX3A5X3wwelFyc3hjTXZFandSeVojJgp6
WF49PTI4JFElcmt3MjRvO3M3blB3WThOekwha05+c0tIXmY+IWRGQz9SMXxLeG9rZjYtI0wrZEJD
emhoSH1lZFUKekdiTGFRSyMyQG56LWEkKzBEPkdtSExaRUFsc1Q+VnNXWVhyMz8re2lTd21ZdGwq
a207VCopNXZQTF5lZCFEIWh4Cno0VHcxYig8RXJaVDlLXz50QCFYI0FuWmBNQzshZVM0TXM7NntP
ZF9KIV5ZaStRSTBQRW4rd1NLI1d+Yz0lS0M4NQp6bn0lMEZGPjFzT3U4SE9nMns9WnEqTVhPa3Rr
bDUqcEZaRTYpT0I9cG5CJlZxbn0zWH1HaDNjcCNieT1oRSROVjkKejM0aTFwKT48am1lO3Y7dChI
UTs4PDRRSX1PVUp4cHlQTEQwYlR+QV9EeT1+K1RgUzBXbyM4SlBaJk9CO1k0cmdvCnotWG53YTBL
UTlMK3lhbXxFalp7e29FdjY/JHhVeTUlMFVWM2cjUTFBPXZubUZjUmx7VSE0SyN3MkdDWSpmUmRi
PQpLWT9aV0dAYyNrYmNgQlIkCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9h
cHAvcmVzL2VjbGlwc2UtbWFyay01MTIucG5nIGIvYXBwL3Jlcy9lY2xpcHNlLW1hcmstNTEyLnBu
ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwLi5lZDY4ZDcxM2E4Mjc1ZjRlY2ZhOTY2MTc0ODk0MWE5MGMwZjk0MGQ3CkdJ
VCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAyMzg5MAp6Y21YVjExeW9lZV9rWCh9LVFCVSZpWGV6fCQw
Q1J6cHA7NH0tUUJgMkFlfHpKKHhISDtxKTR9PGYqez1gQ0RQS2QKenxLYT1scFIpKHZkMmk7dm8x
YzU8JmIlbXtgKVpeX09oZ2Ffaz18OERKJUF1TXhQKElsYztNZVote0RnVEdHVi1uCnpRcXVGeSpx
cmUoZjNqU1F4M2tLXj5OR0xCN258QTBzVkw2KnhBQShlQkMoKkxtRkdMZitefUNGYihqWWwhTFFx
Iwp6P3NkSVNqLVBzTShtUDgqbD8xKURCJHdISlpSTkU3PWA2eXJpO05IekFsR2JRXiE/WXo/ISZW
K25Zb2tyb0RKIzcKeiRqRzlLJGdyQ2phSXUjRjFPSk5QdzsmMmlOX2BHSTIhWTVXYFVXWVlQPHBg
KDVFI0h1ZmRmJWU+UngqV2FVYy1JCnppWDsjVWdgJG84LT13Pk0jc2RULWo1dWshM3o0WFlPUztY
VSZzJms0QHNuZ2tNbjE/VCZ3dnp9a0JpQU49RlVGQwp6NzFAcV41MD54WTt3WlhfSypGUmxqNCpY
KDNGanx6eVFPQE9BNkdsTTlHO3hyPkVPQ21EKTlhT0JWRlRTZ3A5dHYKem10QzRje3N4N29Sdyo4
Mkc4UmA/R0NfM3dJSTsrckZvYn47Unx5WU5xSmY3JUNOdiNFcHs/Xzt4Yng/YmNMUzNLCnokNmRa
WUB8VjVvR3F0dVc9d3VgR2N2IyRUPz5FNkFacGdRP1NDNEI5Um44RFE9OEQoJjtLRGQlQit0ZEx0
NUpMbgp6TFhGNDAhfF5rbDQ/fXxvbDY/aWxicSRpT14+eXVPXn1+dmhJeUFJdDE8THlSd3JPTnFg
bmgmWWRWLTlAMmQkLWIKeldLQ1ZEV1BUK0k0dVlPbTYodCVAMHRfO2VMWHxTRjcxRV9LN2lRcHkj
IzJ2JTtvU3xmNm1CdDN1OFlPOU5TfUIlCnpgI150bGR8K1ZzY3JjMk82KzZoN2VXRUZtcXtLblNB
LTx6T2d9Iz5US213aWMhT09AcGV5fSRrVyRpQzAkb2JvRAp6Xms7ZzYxaEBQIWtffTJrK15ETF56
K0AhOE90ZUIpa2ZgZUI2cTV7fl5ybEpoYUphI1hNQkJqNlI7MH5WUjdwZioKemhPV31qJHhHez9j
amZpcTRTRG8+MllZe30ldmdkWU1JPjFVMUhvUC1qNio+YWEpZHRKRmY4JUJUdF4zP2VLK0RXCnop
Z3N6K3JPSkp1Snd+dWVhOG5VfXZ2QXxLV0d2MzNzV1YwN2VHKlpwKCE5ZzxnWUxFX0ZTVncxck0t
Q2lzTUtIbQp6P0B2MHZIMkFITDM4OCZQS1JwV0s0cHFlTThIRCQ4OyRmejU7Z3NRJiU+fU16Sn5S
KzhhZj5iT14zZkVmTn5oUVUKel9HOGVOWDRpPE5MY2srM0UwUkIrZ0Z5SkxydHAmPVdrdiRSPT5s
I2FYRFdzXy1Je090dmAmd2UpR3ZnYEwyV3BOCnp6UU54Rz9+eTxnUmA3WXF5bXxrdE9yZkF6LTlK
eHM+R25UJFFTc3xeYWghQjwyKHw+M0E8MTQ8bHhQTXJTfiRKMAp6JTs8Qk9rem07KSFTb0VhcWVf
cEpwWGtIUmJRZmN3MUE8XktvSlp8WXE3LUcxX0d2c21vM0hzVjJXO1RGdV5BdnwKekQ8Q2RLN2xv
alQ7JFhBITx3MG5LNE8raEZ2a28xeDQoK3BebiV9TCNkTXJMRmxuK2A/Rj8zY0hBJFpYdWd+Uncx
CnpRcU57bylTbnNeQUlxJTFgMjl4a05wJl9lNXVQPy1nbVNwNldHcEkjR2JJd3F7S05YVHFkMnBw
Y2ZFRHgpYXpKZwp6aTk/c19eQnB4SShGQigqOTEyX3MlNkROZjRsaStOZ2p7eH48dWBxSCY9enJF
O058fH1WMzc8QjVmPkdpTX1Sen4KelphaEg8XmxebCF6TVUrNldebHRAMXs9OGV3b3RhdGNYelE1
Zn4mXzk0WnhtM2xFUUVkS1F5OUh2eHxSdz9uJkw+CnpVeTM9e1BwKEwwbUArMykjQWNKNGFgfX5J
XjFRMzBkOXtwYUsqfmtjQk0pbzI7fn0lQERqRyRGQnFkRFc9MGpvVgp6eGQ7cj96SV96bis7QUJG
dS1iOSp4Z1V9eGk8Sm5Fa31PUT5aOS0mRzNyaEZKaF8jQkI3Y0MzZisxfWxVMSt0eiQKemFnTzkl
JThrd2U3aUIlMF8mNjwxcShPXjVLXng0NXRjfERiVnNvVXxMaDxvJmx1KEc1JTQycz5zNUE0KjJf
MWN0CnpZWXtVfFpzK2YhbihNR1c8ZyFsWE15RDs1IUdYYDlWQFo1eXRoJmk8PGQlY0hhaTl2NENU
bm5lVFRQVG4oOTtCawp6QGBPR2ErXzI5T0UxVEc0Kkxvd2xGaCtpSExhcSZDQWMyY3dWQ0xrdnBg
KlNyXiFBUj0rI2BQdkJ1eGhHOHU8PmoKejA7TyZnNkE0XmpLWW4/aVVaNyN+WXhka0I4Xm9UfWco
JmhSZnFKK1FiIS09TllKQkhRZ1UhWT5MbVR5RiV8Q18wCnorWlU5X1I4Z28kPTAxYC1PUD5aRWlY
QVNgQ1ZyYXVjM0dMI0o4fnJ7PD5abDxKeT9oMypwQyRKWWJqaF9lbTJ8dQp6eUxNX1gldXNnaTZl
blheNFcoeXx0RUF8cUMwNns9MFlSIW9OPE1xSXBNNHFCbnx6JkJlTT9OfENCR1EtMkokVSEKelVh
OHxVWV5Ya3U0Pz4kT0hfd3JXO1YqQ15fI0trQ2IzNH5qVDNSRmhEbUghUm15UDctZkFrQF9xODZV
OzgtZnI0CnpscCY7VzxvXkJRWHhoV2MjXjtEOSRTa3s/RmJJVzg+OURWQVRsWmVTUy0yNVpZRXBt
OVhPa1V4PW5Wenc0YX53Kgp6WHJOZj1QdClvMGpzOHA5aSZPUyVYRTs/cyZEcmYyME1SdWxhRUIh
dzx+XmxrM2JuRk5MJE4xSSt1NSp6STNoO1UKenFHVSt0VnM7OSs+K2pKaT1SYUhQQyhtODlnfnRC
eUFyTWZIMSE7fChiSXRUdDd1dDAtITZpIXA5bUpkekx5JUpDCnpQN2RLZ3ZybjQjRlJyO1hBRktv
ZChQRW9SNlM3YUVCNWlTJUQ4UEZiSm5KU2BTWns0bFgzcXAxSnlET3hPV3c/YQp6RlM5QGJuVkZl
IUcwbDViNHdGKztea0BHNUprQT9AaCY9NlFSZ1ZgdzlQazQqSGxKUV9xM2g8PkoteStgPzw9fGAK
enUkK3wtWGEldiR2Nz8hemtNZEA3RlBsdStee08wSVNTVHMyVWJkUUp4O0IqSkR5QDRLOWVfWENe
ZWRwTGR0Rn5DCnopP1J9c0YtS34xJX5yRHhMZH09dlg0JDEzYkVgdDBTfElVLTBPeFk4byFMfWxe
JXxCNGF6QTJxO2l8MVNwQWhZSAp6Q3hXT2pyfXE/Ji1WO2tXUDVLNzdfI31qPlQldTZQZ3owXkYp
bV94PUdIenw7KmdaN2I0X0E+N1EoK2BwVTx9OTkKelIjc043ZT42TXF7aFhPO1Z6I3hsNl49O2xJ
OCNCUHVKSlBSNDNDY0htRT5OTWxWZ3tKcy0tZ2ZYT04qTCpFKkV4Cno2UihaPiVtdzxLXlV5IXZ0
Ki1hcHltWXJ3PDRhY242MiYySXRvPmE+b3Q0YV9uKXZvI1lje0VNVSZlKkxEdnphbgp6YykkKVR4
P0RCR04qej07VW1tRDUle0hsPW99VEl+bVBTTklNa2pMKzBHVjk8ak07QkNvbypOaylhfHM5QXtU
bXMKei0/S3BXVGVUWXtRcmcoRng3ZFJkfE1hczkrNWxPNjFmbjs7X3olQnRXN1RJSGxqRkJTQ08k
Sj4+PEI7MCl9KThVCnp1JEk3OHJ8TGV4dEBZSyo+NnI8V3BESVVHbClDYTB0WXAzcDRndlMySHM5
VEEhc2I3anlFYjZCbWk5bkQ4ckhITwp6JUlxUylJRmYxX1NXe1IoTUhfYDhHOWthSkgtTyQ7R09N
dmBgU0c+P3o2SiFIOyRkYyQkQzlIVDVKUilmTyRWRHgKenZ3ajtoM1d1SXZRWj8hOWwkNWtkQmxj
bXtDRV9BM3ZrZj00e0Mxaz82T0NgPWEzfXZWZ3xhTzcmR3dwU0dCWHs0CnpKQGl+YmlrWm5ZYEQq
cTN3Y05pTWhoYDR9TklUYS1USVczI1dVU0QlanZwYzk3dG9ffUhOcl4xVjlnKHRJU15FQwp6TH4/
YmJkZF8mU0BKVW1eY1YlY3hkQ1plVGdBPFo7SVU5N15IKyNQT1VhZH4xLWVMU2FEemEjdFRTYypP
WH5mVnAKej15I1hJZypnbmUkI3BtdD9PPW43d31DUHpnZjNUNCljbUZFTztgP3JeRkVgRT1AXihB
ZDNkb0dCWk9WZzNmT3V9Cnpte1RfKDdNUyNtNEVvQks8QEBae0x1fUEjIWk8VERZNSN4WT43ITVz
R2N5bSpoODQxV2tJVHtMN0RVbSQ5V0JwRAp6cCN1R24yMzZEOHtXRz5kbzEzaEM3Z3d6NHktP3Zp
ZSU+ZlplIWtiTEFZZkFHREZBdW9JIXZaTW48Z0VZS1JRYm4KemwzWUVYXlkten5USEhfaDRaakR9
dm1uYngtciFZTEQhY2JuT3tsY0EpSjYzcnQ3X1QhOVM4LUhyVyg4TWtfWERrCno3NStPJm5RcWVu
KWdBPDh8QlI1Ji1hZnR8UlFzMH5JKUdqJWtCSihXVXhUKmFYUF5CRkdyOThXJkdxSHJLdXx8bwp6
dUdodDlaTHhXSmR6eU9wZ3FoVmFWNSRlaU5EVmJYajkjZn10NWJ7RldnQ1AqZm44ViRASmJ8Q1Qw
dzRvSkBYVEIKenI7fWE1eGtmOGt3Q3p2S0dlWVJLT300TjFeYk1pTFEtITgxKC07SyhoJjJfY091
dDtPMiR7YGQraDtDcUsyKj9fCnpJfmN9PVVNcjhgKHNYZXZoUiR1ZilYeDlkWFdMcUhSN2lfQjs2
ZGNNfE1yeTllUFZ7fiYmUXJsKGZgQGxAUFg/UAp6S2huTXgzaz9TP0ZBND5JQTZ2RTkyajswKi1y
bW58RjVRbW9OSlZkXkJTVEswRmZ3UkYhVkpCMTkpRWIpKEtNU1IKejlnUDRyYUliJVd8Nm8pNyNo
LTFudnphakQmVTFgMTl5SWpwe2tgPExwIzlIaCYqa0xyPkp2Ki1ERlo8OENAIypjCnp1Mj1KNCY4
KiVJK31eQnkwPSomOXpuOGxMZklGPlVALW8/TVlxc2k0X1Uwamdmc304WC11WlVKTWNBe1NILTRK
bgp6bkBlQ0NCJGt4cEFqIyZfPDxnOXFzaV49cWBaRz5NcDJwSkErMkdXYU4yXzc4PWdDey16KUt1
ck49VmJDO29xSjgKekBCP08tZ00tdFdAdkUzKChIYV88OGo0QWZlfmV2OSU/X3lMTlFWPHFMSmJQ
X09ZIUwhTDEtME9IbGRhd1k3azdPCnpoP2p+aj5fenE0VGxGckF1dFRFbUJOan5CTXc0SGstRkN4
NHpuUlJXM350R3g4ZW1ZOU1wYVopZGAqcHxlMjRmKgp6KV8za1Uxb3NRcmRNLXheKiZYfkRpTXg/
blQydUxSdFpQTFo8UHEmNShTSWtXRkgmdzhvP0M4PWVtO09tUFctbz8KejwzVkdlPWp1O0JVUjw9
XjhuaEtuKDd5NypoUCopfUpiMzw/eHVrWkIybTx0Nm4mNm18cFhsQGJaemJfMUhfazNECnpXI3hF
KStVPDZaNHNzaENKJENjNFhLVDM3JTV6eThGbVRsK0xIMlk7NSM2ayU+emwoNGR9RHp8Ull7bmxP
encwaQp6eVAzNCpSbEAySTsxeWp5cjU5VTBFKUEhRG4hVUZ0Ty1TJjtOQ2R4aDl4fGB8Z1JhY2hI
fG40RE9JdEZnYUVqamIKentwRyNabSZVdDR0RGRqZE9QcmpZVWpZZn40M3p3KjdaOzFhZH1kR05B
XklkYVE1JHp3c0pPfVJXSzVkflBvPVZMCnohOEpaUjhhVnpKUCsjR093JD5WJmxeO3QmQHk3Q29I
KnFpJkYmIUJqcWIycD41aHB3ZGd0VHoqQzFnPGdYZ3x8UAp6O1BzRiQjdXlMdD1WUGh5YkFLZF9e
byNsbk49aSFCSHxwRld1MUx8UHNoRE9qRG9uQWxvT1RLUEtQdV9zJlVJPG8Kem1yLUNASE1HNm1S
cCsoUW9ibnh6eFB+ZGRCSm1oV2xoJno/MXFeP1B4fDJeM3BeUl5LNno2YlhJZXJFSG47KzcxCnpu
UEBuUEhzXlNnOXw0aiF6WUFiUHtQfnclY1N4KyhfdUxwNG4oNzt5bGF5aEp7fUdLc05jczgjVUc0
ekBxOUJWewp6TDJ1Vj5fZ3lwcGV6PiVYZlFCMllKdit3Vz1sXzc2bFYyKXdMPj9MNSMxZ3ArNkQ0
aiE9MFdxUjxlRWdgQSQrUGUKemIwQUlXLWEjd34xTE44cSY3clpEbU0wOWIye0s0dU5jTDxfPXRZ
UFU0KjN5cWZNaUNrQXFwWnFRWHolP15WT0hqCnpDaCRyfD0tWEY4ciskI2JeS183Zi18Mnl1PmN7
Rkpha0dELU8kezlrTmhgKnkhSS19YXI+KjRvMl92fUpSOTdnbQp6MEp8JWNVZWNsdlBxK0lkMD1L
IUxMcXxEaGFVOHtpdWJXZnleZWNzRUFrSFZFaF8+O3NVUT1QK2lgTE5mZGtHZikKelNLSmFydzV5
QD1iYSZwTWYhLSNsPDUzaHU1ZWIqPUV8PGJ2NntSTWxJMjxxNkV2Iz1xbEJXS2JDbSF0IWlBNVYz
Cno9TzclQ3dkeldeU2plS1ZDcUlXKWpTczg3azglPmpJRyZfS2UqeGMmM2x1JlZUcClMYnNZfUFt
ZTZ8XzhmQmtCaQp6QWI/aDZ3aWBTJjFlaHxEKWgkYG4wbmZKVmlAVER+JUUkaipKc18kbTw1ZCln
VzBxemw9QT5mMlVzNiQwRSpvJUQKendOXi1eV2BxbTtCfjZUaiVyYGE7R1Q4YGtVb0YjQEE4QGst
bXlZQDFNUlB6VEItayFxX3YzN1VyUFgtaUlHVk5GCnpPPXJCMnUrXlQ/VFJkb14qWEsxbWI0LVdH
YXxZbnsoaTkqby1aTTNHN2wwZ2k2SkVKTllyNisqKU4hY1d8TnBleQp6bVpXaDtQS35RdzE9b2ZP
YFVYTitkZyoyTnc2QVF8VH5lU1NQdDNEJmhQPVVAa2RjcHVIbEJfY08qck50N2F2ezgKekw4dHgz
QDMjVV9eWjlAJVh9UXQjLWF1KjRaRV82SE9qaSNRYG0qSUgkSXJDOWJMQThBOW5XK2ZyXit2b21j
cnk1Cnp1T00/V2Q9LXp5M2BpYTUpRFNFUGI5SFJWaD1rIUJPLUhpPHtsM2FzeXgtbUhldTg9b1d2
OStmNzFfMGYtO0JMSAp6di1ecG9FJiY7X29oKSVoYlhkNUJtaDZ2VG5lWEo/aEJWYn4mQShJeWQw
OEMwbzVVSDtrWnw/cHc3a3NBYE0qfmwKenBiWH1aZXt+OSZPbyNtPGdNdC1wdHp8cF5Zak9+UDdz
SnI1OyhLeSVpaThnR21BeiZfRXNYUUskWVJ1Kj1ldF5OCnpTN30odyZOcGdwVXN+MH07Xk1TXjRg
M1ZKYTJuTk0jRWs9Tyo8RislcSo2U1dlSUY4VEpmSHFQTGBCJHRjQDwqcwp6UHxCU2ZMUU51IWND
cWt4dzItdDx3UlZhWDhUSlp3bExZdzY5MU9lay1jZHNETTYtVTxrbCs8XlE7RjJ6Wn4oZHMKejsw
aGptZEEpbXgwQ1M1ZUwyRGlrYFlAPDQ5PkM0K0YkKElgWW5JNVFnempufjEqMVA8UklXTlBWZnA8
MCQqNTtFCnp6dCZiaSM2dHVRcW8yeGU2Zlo4WXtyQnVXbDg4cTJeSVZOdkp9RC0jX28jcGdpVW0x
U3VRQ3NMVTUqZ0kmMm80aQp6dmhEVXkqYFlgcEhQezFFPSl1JVZXP3l2TWU+bD5pc0heQXJzUUxa
MT52JE53WURWP0l6YCVTeHtreXdVa3d8djEKemxyM2ZAOH49TTRUcTx0I2dVK2JXK1VRZUhEUDlq
amo4dl9BUUhMWW1pJEw8Vl59MjloUyh3JlBWantKVUNGN3RrCnozdmpQO0BZazFRS14tXlBvTTF0
bkE9c1FrV0RLOVA3cW9pams1MUJGRTx4c3o5VHZ2MCMzRHNwQn1gPWpsVzc5SQp6YjFIRjNuIVJN
XntoRXlYa3s9eTc3PkN9RHJPV04yOzE/R2NZeF9zfXJPbzYpWG9jczJmb29mdnN2SHlvd29hJkoK
ejRTb0Y9N0Vnczk3P1RRKkd9QXBwUTJOKnZ6aDExUylHaHdPT1U9WkBHJSY3ezVNQyFlPkBUfWhD
I1J3eyVNbj9XCno2a0IlaCZLcCZuQTl5TnpBQ1lZVzhmNlM1IWNtQ1drZipsUmlIfGckNTImeGZr
YGlUMCpPPkg3QEk1KGw/STJJdgp6MG5RQzNzXmFqUDB6fD1lYno3IXEjbkNVbzwlaF4zcUw2NDN7
am9kNCMpZU5+Pkx3PT44bmIqNiFDUm16SXkhdTIKel5NdSk7KVAkSnJlZ0BKYnR5dCtrXjhSbTBo
PUp5am5fVXt3N0xJemQzMG5mUU1jTmJMeTckKyM7eihVKE9vVy1hCnpZcVlGfjhUd3Erc2FUUS0k
JEFKUEVNSlVweilwQU9QXj56bFl2bTA4WX5sWDBhNT1oJkVTO1MxQkw3fipYNmFEVwp6RD1UXjhV
OTg+dkhvIzJTbmpNKWQjSFB9bWdpJn5AczF2MCE9b09oNGA2ajJgVHYkPDxBQD8zIXo/I19EOD11
QUMKejJEcT95dSlwZEpjdTNCQj5iMlM/TGooZ2tUcVBke0pSeE93YC0mYiopUDUxS1hvN3YpNDs1
PnVFP25QWGpQNmYlCnpkWGJ9VDhqPFMjbiM5RzFyZXJtVU0lQiVvOHEhX0NXND9TZEQ5RTdUUG0q
VHJUb1hyRXFpSjJFKjtERz4taTF+QAp6Rm9NPyFLfEJuPmJuKGd3QnBKJC1ZWlcxKj5KJUZ8QHtT
fVkxNTlNT1ZvWnQtKz51fF4zRVR2JG85bzVYTnUzTCsKem9lUFBiUT5vYnNpTDJQaXxKWFlgdCRo
NTdpIXVhKSFTa1lIaTteJSg2cjUyQTZ6NUZuRD1LfCl0KVUkTFYoTUJwCnptPTVqOGB9SnZEI3BM
NFJWdCEyfjF2Wk8yKSNrdDZ4R2ApVj1KWSROV09oWFJTRi1aOUU4Pyk2dEMhamhvVD8wKgp6IWAz
YzJ6TCpwRWF9ZGJBRz02Y1Q8YiU9QlR4aXZXb1lCfV4lbUl2RHA2SFlVSXF4UW9jdTQ/JGxpdTV4
PDR6O2AKeldXIzxBeH5yZDZNVlVKQTltWm5FYVhBeipOfUEhcHpZVEZuQCg0SnFPd3l6SDxCTEJl
KHZITmpCdFFoa0NIZjliCno1IWZqQ0kxVTJhcVNFJT9ndyhlemRNJHNqJGcjelY8TnhVc0FBYStM
LU5re0JAdiUxaG0pVzRBQ1ZBVW5pWDN+RAp6VT1BZVRQRSN9V2NZbz0hQTdqQnMmc2lmPTJIMiFQ
SmJfPCZ3YlJ0PHJuRHpBam1UO284M3JsUmtQMClSKWJudWoKelRVIShyenRDJDk8dlE0bGYlK3hL
ZiFCNEJZJXBsVnp3d1F7NjtiP0tEUTB7THZIWUhBWUs8THU/SlptMEQkUX5nCnpASUgzVD07cG53
YjU2eXZUPUhxSXlsJnQ2MEQ5QikkKkFnanBRaiFKV15UNyNKaD5IU1AtMyktPyh7MDUkVG5OeQp6
N05teDdHIzxnKE1CS313WEtUYClDSzgrLURiUGJRc0UmLXdXe1dFQndeeEFoTXE7U2o8Zm9IMnYq
UnpVOXJXRmsKeipmNj1UT1ZAUComVF9tQ2x7YT5raCtve0lEWnA9WEJ0S2U7RC1teFB1Zj1pa3Rs
fjZQJmZlS3E5VDY9YDNtO2VICnpOSlFhaUNnSHhhMXVDfHFNKFJFcUBMfm1UYUEkKWNZUzY3VkZF
P2BTeyUwcll3RHRUKXgtakY/LX1ePn5fS0l9Xgp6RGpSPTtNK2I0PFB2TGhIOWtNQXM4NXhWP24t
WDdJcEx0U3RvMjdnODkrRWheSz4yUF9CdUF+b3lCPn5LJDdGS34KejJEfkRYd0tfN14kNklQcCZJ
U3VDQ3RBRiZtWFYmI2l6UXljbGVnMUE+WnYlMVhqJmB6ZWwrfVpCbERsRmA/ZlFJCnpuMVc1bElg
LXE0MzV1UENiKDFHTXMzfjRZdmVXJHdzQH5WZDR3M3dYczEjaDModStxVEV0Yk57aWBgSmxFeEZv
dwp6SDh3YUBMeHx4fDdffEkwN300TFIrUXBKa1l0aDtNUjVZJDN2X05VfFpga0F7Pn5sUm1nTGd4
MD4paClTQkw/akYKekY2Q3dVNXx7WGU/MF9lIT9qc2V3KkgwLV9qa3ZqZjtCbD56PXU5eEteKz1J
SjE3NFpCWTVke3MqNnM4T2ErSXJWCnpleGpaQWpUQT94N3IjeiViYlArNU9wUk8lYlkocSUzVlNy
LSlpQmFYb1p4NUB4O2p+e0crSU9LIzBobG1paWo2cAp6NmxOa1JRfEVuaVNsJFdPe2goMU91YGh3
S1d4ckV2ZF5+I0JXP2A1c3s+OThRSG95RjBDN3xBbEQlIU1DXmx2QWUKenpVQ1dydHoxKjFpPXxV
emBHUmQ/SjI2cThpVzVoV0t5dVkyXk91P3x2Xm1rcXJ2eSs5ZnBBS3glOUdDZEN4ekxlCnpUO3go
RE5sSTt6VmN6WSFNTns1TlBFKHtOMkopOU5JVUQwbGY0YlBLS2VZamhEWn0hb0RlNk9Gc05jQUc2
KHNyRwp6dF45QXpEUWNOR1F3bHMhTWJ3fjNoKCpDcXkyPFR5OypGVHNXTGNQWFF1NzBVRyhxblE+
JWUzXkVZTXRlJmF+Ty0KelVWISh+N18tNCokS2ZWUEhfeDRqXyFrSlMrLUBNSnUqV3s2UGpIJDFQ
KnVpaFBwUmhldVBURnI4LWp6TlUzX2sxCnpBbi0heD4oLTBXS15mc01yM3RvfChpal5iciZoVSoq
QWBsNkFJeyFGMHBAOTBhfCtUaiN5RFo3KnN6O1hORS0mSQp6MipFMW1qYzd1VGBuflpWXz9OcmNl
NSZYKFJfQ0FWSldKTGAmdjFBYlpNbCFtdWNURlkpUUoxPit7Q1htKF9NUSsKejR8aj41YHhZIV9A
Q1BNfnxLOW5CZkBxUCNyIT55O3RJOTA/PEQzLVhQVE0xMXRka2Ataz9HWSs8YWg4JlNuOWxyCnpQ
Sn1rP3kwcGd4VDlkTDgqI0N6MkNnai0+Ym1XNkQ1eEM+YmwoV35DWkN5LTJVN1MmS0B4fGo3d3Vw
PUslXms5aAp6O3UoNDUjI2QhPmt8JHY8cjdQSGBRZmhfczlsP2dGcHsmeFI1MFNfO1gmVChXeXRo
K1gzTXlKNE1YUyVmd3IhLXUKeitBWFgxNnt0SllpWWNxQDxRMCsrbytQUFV2PT9yWEkkVW0rM3Za
ZDh2OVptM3JETExSRGZXI24kV3gjVDI0UTNeCnpxQyEoTTJCcUFAZ1pTXnxhbStYRDQhSTVHP0pz
MFZsQ3slIXxIezlHV2Q1cWB3ODR9JVVBQH0qSk1+NHV5IU1tUAp6Y15pajBSclN+Vms3YTBeVWxj
M0dlKmd8PiM5ZVl6e2UyVispN3d2M21HMyZteGNZNFI/Xn58JEdjVlAhSXpSa2oKenJfVGNedCtY
ZmR2KiswcFJnNFA5SjVGRXJUNGV0YmRZWSl8I2REUShtISllP1RWT1FFYUc7YnBgK1AhKUp7aTIj
Cno+PnlyTHNsenY/JDJSMjJWJDhXfU9JK1J1P1BabWo8LSQkWGR0UzFZNCk8cDUzd3stQEdsbEZq
WHlTI1hVbl9iaQp6NEN5P1FiUTw9WjRqTSgmKmw2T3ZsVCNTPT1mPDxAeUpLdDgqel42Jl9PZyFi
K0BuamE8fEleTlVpO2c9a3l5JHIKekFWU3BqR0ljdG1TUWdUcCNWJHlaPVgzd0ZFXlJVZUhvblp+
Ukh5YHhIR2grX1RxbkQqM09rdmNWd15HMzhFTWFFCnpyYERrN0hYUyM3RD9iWGxoJj8+ezw7ajhR
TzRQOSQqUF4+QXNIcXdVISlQUXleQnprRDN1azs4IU5xUl8we0BWUQp6YWlZcyRiP0JlTHspZigm
WChkWSUleVY2dDR6SnomZl9rTUBBNXVvRG5Ud0A/O0xFLXdNT18wJTw+fDdoU1M7TCsKej99Kn5k
ZlpYKEV2ZmxmN3ZIbHF+Q31PVEE1QiNIVHNeQ2NtNFhgSDZ8RklIVVNVek8rYDwlYG5RP2Uxc3lf
bCRmCnomSEdpRDJUc3UlKDhnVjwzVEspaXg5UFY8UGxXTTlgV2d5UClTZXxPN351eiYyQSY9e1U7
ZjtoM35gdFh4RTJePwp6V1YldCUla3o9e0dAbysza0ZKRFVUe1RRMFBMSndHOSZDKFZsLV5BR2sx
dkNiQ0xZUDZQUFhBeGVlUzFPaEAwa2IKej40fT5Ed2QmNzdffmNJSyFnS0dibF9LSkdXUWtyYHpM
PkZ2cklPfTYxNSY4RVhqQ3liJWJ1ZSZPQClQfGV2P0RlCnpJcDJ3ck4wQFZ+ZTRjSnd7M0NPQGQ9
ZTY1ZUE8dVIoUU92YG5MLV94dFljWX1NaWtOME9Ca1ooWUtNenlHYFA+egp6bnxuSypaJDNWWkZX
LUxsRE1oaGsma1psZDRSUiR2d0JTRzJmN0kjTntyYypzeUF8e2w+ZkMkQVFpRHcmKCF2I0cKek4k
UjgwYWdwZnt3IWZkUj1qVS1wQSkzVXokZU5fRndoVDV9XyY7I1leZnhlKnFjRSQhZzVSai0zc0pR
R25DczhGCnpxbiNNOT89fDVIdzUlcmglRFc1I05yZDltTV5yZyY+VC19UGdtTTRqXm1WPlRzPkA9
YiFCMUZ8SVUkI3twY3YwQAp6MWtiaSFgYz4tRChEQG1hdTVzO2VzZk84IXc2VklWMmVjMlZkYkhy
eSNKSH17QVM7ZnpyVk13Ozk5dzlkd3FEWHoKenh8KXFDc0orZWtSZ31ifVJCYjhJQEtmKj5JaHBh
VGY3IW5+Zi05TUU8YzxIVzQyPzYrUl5tYXJ3X2JfU1VYJndRCnpqM3B5UTY3UVI+QEl3NGRnPmcm
fioqfDRxaFpGY0pwTjteSEdrQnQ1TmlaQXBjemtwQU83a1poaUpOe0tqSz8pRwp6Pj92PTRAOGFn
VXo3YjRCc3BOam9DMjlwMFMtM3x7LWw8aVk1TW5wV05tMHpJR1VvN15IUE8lb19lKmc4KFByVV4K
eiFlQVl4cC1AMjckNVkpTmpWKnFMJl8ydFItLV5BJm0mditIY2s/MmprVWhmMGtZfHh6UDUhajxv
M3hKMVlsc1kpCno/KWBVdEA2N0o5ZEZtTUVkQEBoIW9SKmhWc0c9ckc4NDQxQm43Y2QyRzkzOz84
KjN1Nm43Vih6clRrU3Z0RTVrNwp6KzFwRiREXzdXWm9ieS0+eXQyWFc9Q2FVST5EMV9RbTI7a1Al
eXEpR2Z2MzBBaClzeDZaVUtDWGwjVUBxS2xXdVIKemgtVzNYPm5CbFU4c0dYKnIxUUVvY3lnJEV3
STc2YmJqZDsqMiE/REtgQ2YrXilDclpMQzghU1NkbWdNa0RBSyRJCno+Q0IydnVwSUJWNEdCQnts
fmtgSipTTlZzMz11TiFSZzRVcjJnfmApc19rcHJAfFBJenYxSDl1QHN4VHxGRiNTJQp6Jio2Smsj
QHQ2eTZDYFpLaHl5TF8kMjFhPTMoMnh0YmpDNmNvKigkYWR3PU48ejtwa2JvV0wqQV5iZmY0PEY1
WDUKenk4QyhANn4hRnlIZUJDKWtgMEhmWHU7Z1I3eU51fEBfVkE5VXRfflg5WnNgVyp5RUtTb3BP
SFpFfUo8ejk2UyRvCnpodG9IbmFLQXFNNT9Zam1PcERlKnokMUQoREhJPkk+Kz5PbjNTPTZPSCp7
X0MtMlJ6bnBTU0JHd31XOypeZUdmfgp6QUdiWnhFPGJ0TEBqI1JgN2xtcylreWE0fiE/PHM4Nnls
PyRfQyRTfG5LfUQxQEZJSD5nI0FVYzk0YGx0dnQraHkKeih5QGxHV24qfHw+aTNeVz5ifSQhQzRE
TUlsekFPZmZkTW5eR3hHNzg2JkNnTSN6dkxYSmEpM1FGTFJOfSlyTFgjCnpgPkE1MnNnMyZycnB8
TE89aH52OGxScChsY0pGRjhhfTVAbkxwZDNZbj88Yz1AelNoU1klY0IhWHVGJmZ3SSFYYAp6TDZH
MktQb0xSeypLPn52ViY5O251VUM1Y087c0Yxaz1qcnwwdHw5cl56byp6P31BO0NQWEs0MTAqeF41
WVdrbUQKeisrLWh4Xkk+Z316K0hzVWoweE0qWiRMMDxnbmk7P0E8VCZkZkh2eSkhJDlgPT97KFZ9
SD5JQE9JQm9NcD1uQTtpCnpndVUlVF9teTtoYk08MzRteDw3KlkoejxTPG48YCFSMylCaDdeYjJh
V1hTOVVTPU9jRThSMzJAaExIQk8xfHxKaAp6RzNXcEFrRVo8O2BtbnBCYVd3Jih6Wnltfl4/TEsl
O2U+M3NGfjB6T0oraCF0b21TWSEpaHpLPWtAbj1ySFQyclUKekdsfCV7XnRUUFgyLXM9PiFTKmhJ
elFwdHBMSDxgSUlZYj5ucnV2WkIxVFRkRjU5Jj16Q3gzKHF0SUZxeUZBZzFGCnpXMzRrYXNsSH5m
X0FeVW50TUo1eTxrKz82JHhuYHdKI3QxfWVtcnVYUGhAUTM+MXo7PiZwO3FjbndtWj9eUlJxbAp6
PGc9NWAqUSg5aFg5fDZEc2dhOSQ2NGBlWV97MXBSc3spdXM7QUprXmN3JWEzZ3N1TW0oX00xdzg9
Zz19dHVpc3UKeiE3SkdOU1lMbFE/V1dMWUhZRTFeVnJJNGN3eVl5SGpQa3dha2wyZipUYXJJVWx+
YXtAZlZEK0xoRDtLJmVAZkdGCnp6MitNZXZ2dGJrUWklOWxjIURHQ3tHPHhFYlo9ZkJeQCE3ZkEx
SzJofEhIdDBvdE84ZHBmdzJwNEZOUFNfUVZhXwp6dT1HQGZXRz85KWA2Yz9CeytZdWljQllEISt8
bFVlIylCdys0YjhoUDk4QmgtM2A4YkclWGcmJS0rRGt1ITheTCYKekU8Q2dxOCQwQ3hQN2JHR1M4
fnxyZSNmSG9HOXRUbT8tUlkjMkZGX0xQRygjOFo7ZWR9fDRrY0NMbVIhXmVQNWxlCnpxX2N3SE1i
K2tQRDVCemJUYT48LWt3RDI2bTEldFFOeFMlQF59Sk9wPGQ4JSZtUkoxUnNyekYtLVMtZDA7JTsy
fgp6NiRHNDFxcmpsdnQ/TmdBeFhDTzNlWUUhJm9vdDx4KUJPJFp5bXZKU2xAKlFQRlhWUUF1ZUkx
PVFoRWlMYzRETnUKeitVeXo1JWtNVXhSSTkxZjk1eCFkbzhGK0BxYGRvMCpOS3ZvcHNqSDN0JWx5
OHpfKG5HWE56OzFuYEQ3ckpecyEyCnp2KiUoYVVIYlJUbC1iRUdHP0VSYUp6dnl6KGB8d1hCPG1q
WjU8RVZ5Uzt0OXo7QnBEPU92U08hJENacGBqTlYwXgp6NiVfRj03OHxkTDZoI1V7MUJMR0NnMnhr
b15ZUTc8P3Z8ZG81RllPaWlFWGRjSlYyYXNtJXNSN2ZANFIzMHxnPnIKekV0JDZ5bHMtPntkIXsh
UnRrLXktZTI7V1BRMFhlSTReUz1fS3VvfCp2KUFeUTNZTHo7MmkyPWpSUGZubT4qJSUqCnp8TXEp
KjBOZTMyU31NajExPCo0bk1fYjNHZUNjJUU8S15BYD9aX348dnA+fXlDajZBfElTUk9RKz02cVdM
RSY/RAp6a2dyMFkqSzRhO2V9ZEVFVzdyVDU4Sj08Ul5WZ0F+UDY4aDdHQztRM3txfFdIWUd5VD87
czQ0dz5gYkZycCU7fnwKenpvcV5IVCF9VXdoTFB7STZJb2hlaX5ze0hpZXVUSWNqdXo+cDMkWFB2
RTlmQ3hkamIkUDBMIXFXTypHWGBgOEN8Cno9UjEhRW5hRjtaWCZgISYzbW52NFg+eSp1Wj13LTRn
eF8+Zjh4fik8LUE4QGZ7PDEhd2F+ZUM/JVZLYUJIOV9AfAp6TjtyeHRtR0d2US05TXslWG4tUD1X
NF8/T2NYPmg4cEM1K15gYGt3RzY5Ujdpek9fVUhlXlFaYEBNaHZBfDlwX30KekJASjhMYlc/Vjs/
cENUNW1Ge2FFeT0lb0tiYWY9WHhBN28ycXtyTT5XQnVvb29aLTh7XklWK2o9UjNTZExjSUorCnp4
Xk1IblErU3U5cGJXVDlSIU4jUEB5JHZlS2hDfXR0Yk4hMHQyJXMxQk1NMVJxWlJoKSEmUHAqbW4t
XmlDeytycwp6JGd1Nll4YWM7Tk1FfWUyNV5eMUB2eSVGaDZ6TU01U3FzcXUmdjBGOC04Wk17aCl3
JmlXX2UlQSlzO2V9ZC1GcFkKenA2YXFPTXh6emRTK0s2TGNRYkJaaSVufUwzcChaRnIpUmxWIzZr
a21aY1BvWEQwYiVueVAmPERUQTkjM1dGTlduCnpwNmh6Vy1OUThgenszIVVQbmpmZUlqQ3tJMHMo
UFVWd1V4aER5aihidChvc19mcGw2KygjNyVMaWVufERwUFp+YAp6N3lUJXohJjRuMUdRbkdCeik9
aSlZJFFYcC0kOzVeVmBiS2R3Um5nZFVVSEdHd1FiV1ZqXko7MihXe0diP31CdTQKek9Xc08qZTZ0
R05DUjE0YUl+I0ZMKTNwQmpLIWwtO19lem02Zn1pYDVldlVnJCZaaz9EVVhJazN7fTE7dWErQ1hv
CnpTQUlCc0VLZVZYO0oxKXtWRDR1RDYpQzFfVyEmPFZwSU1vc1BGTzQtKXc8RlFrKEw0Tm4oPGA0
QmJmY0JKZjEwSQp6SyR1REt3MnZKRVBLPFhlTlNjRytMRTV3YjhxeHlqVkM1R2Z6N292fnBxaz4x
PEJofEVURVhQVlh5dVJfSUlqaFAKejF8Qz81U209SSNjY3ItYnMoeW5uc3YlT0pRekR+NzNta01y
ISFocDNkeE1hbFl8RjJNdTx7e3VOKj5FIT1kZ0w5Cnpzbkx9WmIrRnxgczJYbSR4WjFKIStUVXpO
PH1vS3AyIV47elE+bWJAUyUkN05oSVB1cmZSQj12VUcqVjtEbS03TAp6NGJ0SV58Rypxfj1WUmJj
VDAycW5uKUdHVTU/QS1NI0c5aExIT0xiMURnJF8zWSU3MHRXVU84WjQ1cn15SlVPMnoKenNfMmNJ
N0d8IzwodC1XP0E8a2tsbWVHKT92fk07dzd1dShVLVhofTMlWEBGbldRWnFsOCUmLUx4JUg1UEBZ
eC1wCnpoQWhYYXE7fiRPcVZiKy09QTJMTzh0OT1UNypZX2QpR0c3JlleSCQ+Pm43PFFkT1ZhVkBK
SVVRdWZmVlRecEc+Tgp6PT81aTdxYEdBKVFyRG5zVkEoU3I4eGQkU1BXUmBoeyMlcURULTBSTThn
bkpaTzIxPjhAUmQycFMkKDcxdV8jPHUKei1KR2xZb3cwZTV1YjRaYj9vV1hFK3gzaTRCKGp6Zih+
RTxuJFNDdG1oRGVPcHFxN2ZmRiVaR0pwbUBjMVF0ckM2CnpDPnYqKWZIMEk/S0JOfSt2KnUpRFV7
XzxjZjEzNiNpYnJpQlB0aHRFbVpTTlcxYWFUaXd4e0w8I35rOXdxb20xJQp6PCo8TW1BTXpkMmIq
K1JxeWAyOF5EZGNxPE8lNyMhNnAxUnIxdEYxezQlMS02UUc2PzE5YHdVPj9BPEk3X0gmNnoKenF7
cFpiQzI3OGdQWVlRMj5WKUckWTluej4tZGdeQj85d34tNX08M2h3eHM4Ymh4OCtYdFplPGBAViVf
M1RIZ09sCnpTNGQ9bWFVZHFzK2JBKGZ6QGZ3QU9JUmckdzhPOVI+YSU7QCszQVI9cUlWekNJO3xH
JnU+ZGhPKmlNOGhTSUYwVgp6T1JHYmg9VFRxR188aXNOPzU/d3VNNV5LTkpDRUY8Q2lDI1M/RkBr
MylJfX02bV47cnMkRFdDTVAtamhxSz5lZVQKejJYNCp9ZmxwMiRxQn4hJGUqci1He3V+XzN7REwr
biYtcm8tTmBBe0Y4d1pLRlQ7OV5eRDg5Xk0oWjdwWVJ2aHZvCnpCUzttLSEtKDctR1Jiel5BQV4w
YCpqQ0VHenU/SHoxX3dlI0dYcnB2YE43bDAjTW4zVXVEbjgpcGJLaUEoa3ZtTgp6Tn5RWn5Bdz08
ZzNAaiVXTHxyUWYwaXkmT0khMU9jcGJAOEBFSEk9QVA9ZSpfa01jSkYrP0pQUWIzdiRvPncwKlkK
enF6Knt1aiY7NGduKDBnSHtWXnxkbF5oe0hGKUNmWjF6eWFybHMjJDQ3JXhaaVpiJjVLe3Ezdzkw
TDJEXnpwN0tmCnpjd1NhTWp3KSlmdHNfJlNBVHFoNWRhcUVadSEofCNPSHIzO3lDfVRSVCt7U0Zi
Z0Z9e093alY3al9CQHVoKzxkQAp6MnE8MlIkZ1IobG5YPDIqPyZEK25qSXI1fjR7fG87anZfVlN6
X0BSV213I3gwYDxWO29II05CUE1CYU5LJTxuI2YKemtrayowV3Z9IzlTN0txcW9wQHkqMFhyNTVj
XjYzWk9lNXRza08rRjU0e1Z4OyheVW0mUHk/ZzZHVzhXemp+XlBwCnpSMDEwTzh5KVdQZlI4ZVRq
fEB1WTEtY1Z7LSY/aCtqMGF7KFRSZGdNITkrZ0QrbVFBKCVKfksyNXdCQ21LRkxNfAp6ITFWd1Zw
O2ZhWWY8SXVJSV9EcDcmUnxgRzBFMDlJJm02OSt7aXFMVDw4IyNmeyh1QVg8U1A0bFZ7NCQqTEZS
PHoKekpRUlo4ZzlMZ1gwbX5yfmVadHkoWENFSkd7JjYqN2kzUmlEM3pBXmFtMVdqbUVsbWd8TSl0
Q2UhSTUkIzVLcTRWCnopNGNlVGllS2ttbX47P2lUQUktTmE5R1pfc198a0QlTVNvUSZrNXJwM2Yo
YEYqWnlPcz0xej5EMH0jTlVgYno5IQp6SCFBYj5yeDRRWjx9MGk1X2RuN1VhPTd3JURAK2lTYGZ3
MCEhKz8zbylJbkwtb0JKUmk1Y2REKCVvQkJte3pyeD4KenxKc0U4PHBBdV9MbDBlRSRgcStYPj1s
b1QjPUgrbCgtZmRAU0stZDgzR3R8RDk1OCRDMW01Sm1uUSElTlNyYUAkCnpOYHY8OGB9aGJQeyFn
QmxuXkpJe01mPSEtLTJKIVdYamJWfSEwMk9LQzhRQHxHNkR9bldxNGJkUD8pKGQrWEUwWQp6bkk8
aX1RbD9+I1pUSTc9NkNKJUUlYExfKm56fXAlQHJQdXBGeSozNVFFPmpCTn1OJHBjTi11MlJrenRR
Z2EpZXcKekVTVXtadiFUTTlaNCkzcHk5V215TTVHdHxjcD4qYzByUWQ4RjZxckI/TFZ8MlI1SUJp
SHQ5K1olQDd6NjU0dks9CnplO2oqezk3aSRnUmsmNnwmekY7cGNAX3d2TDU9bEgmUFg8ZFl1PiFw
LU5WK2dmPVI+NUh8dyZ5OEFofnoqKj5HQgp6NDVUdEtjUntgcnk8RVNOa1ZaPnBYUWxhd3l4U0R1
JWU9XjJDMiszeldqKlhRM3QpP1dZfismfFN+MjNgKSM+WUUKelR3dWBxMjM1ZnhaLUojPEojYUNS
emdsTFh8SzVMWmpqM1lmOU9ldz8kb3VEZD5INDQ5ZGdvZ01EbktCJkBJMHpDCno8XilAaFQ+bnVW
MXtDa1p4JGBeOztadGAlRVhXdXZGODt9Q0tlQz1ZX2tzP3J8OHN7TCF2RXxqKzAyNVVtPGQ0Mgp6
d3BgbCVLU1EkcHpuK159ZW0oe2ZDSCpSezN4Xnt3bkUoZnl8MTBUSzFFY1FIJUdwYWYqRnZCdW9+
SDJjd3whUT0KemZWWDJEWmlTZnVXZVNneXhmeE93SyEpMlRPNGd3ZHRySnRsfDZRTC1TQmhFK1I+
cisrYT5GZ3UwfThoc0tabWpRCnpXI0I4S3VGdFB2ZXwtYiRKYEttbTIjQkpnMzw3bzNeIyRDUHw4
QVp+d01zen5jQShkJFN1eWZFPUsrRz41YkA7aAp6LU5reD9NZGAodHBUeUQ3bzUjeiZPN0JzNkM4
KFFsb2dAWkchYE1McG12ekRjI0dxdyl7JG1sVk1ncylEX1ZsJGYKelFHbDU+SE58LW5sPW49I21H
fCpJMzhhTlA3Sm00RE0oRzhTQWcwdG1FWG8rLWQzUHYzYTx+alZkYj1gajRGVHZ3CnpASWtLeUst
M1M9ayNlUGprU1AjYEM8YkJrT3dqdzdaRFlvOVRIPzN7TUVnbzkmWU9NXnJUNz53YTM5Myg3dUFT
cwp6U0YpX05EQ3MqSms9bEt4KEwmS0dRe2N1ISQtKyRAUl8zLWRtallNeil9P1RCT184QnJycVg+
b1V4QHdIMkBwZykKens1MDM1e0RlSTE7bHREZTBGJSNtaFJ9OVBeQGV6RzRNWik2NHFkdGVeck5K
dCZtQm03cDlEQmMrX3ZmNGFmJl5ACnpwWn5AQWluTjImSCNPOCoyUE5pTHIlJFAtQmYqaFg2PENL
QWI1bk90NjwzMGxOUSU1SmpXMTBMNi1ac1k7JC1tPAp6MVZEenA7Z0c7NFEyYVhwJX5zR2dtMlYy
UWRpSm1lSiNUeW41TnFEe3NLX3hAMTcpUjFNSCtUOVNSfWJLZXdLPyYKelBEUztaISNubjtgciRK
aVItYUZCZE1LZTdDMXAqMGNVXkpINmI9fFhERlFNVkxiODJtclUjeHRVMGg8fVJWTUtmCno9dVpG
LVhUe3dHTE5JbDU1WHIqTDhQKXg4RzE9SWRGKE5laSR7Mn1yPDxFdV9hezEwJVMtY0dzVl9CaW1R
QUlSXwp6QT5IeWltY1JUSUI7aClEWDMwSXRHcnBTd3BVZ01XZFFfNGVzbGlBTkdpRSEhYFQ4WH1Q
TlI7TztLeDJRZUJvQXUKenhJcUlvR0pmOD8yVjZ3KEc1cVYpMEJPMTNeXlZKYWt4PXdiIV9MPFpI
Q2p8VzBuVztlVn1uZzQxQF41SjhObEpGCnoyYSlNfFhKK2oke1hHOzxMXzJtbGJsZFhucWQoaWR7
QHtoey10QGUjYGlnbmNvZVM3S1B9Xjl+dTVWeUkqPnpqKgp6dndLRHRAfSQzfih2NGF1I09AYFgp
Xz5VN2AlIyNQdW8hOHYjIXpsUTNoIWdEaXl2fFRsfX1MO0JkJHMtd3NaRiUKelZJaj99eyo+SjZR
fFV3Rj9ndD52WGphTUdkWUtOMzxmbj9qZWd7eSk9PGd2NlNwcjlSdGZ3RiExNHtjM15PTS0rCnp0
SGNtVV5HQyV7SHJmJEBnT1EjRDhDMyU4ek1kTmMpSnUqe082NnAybkY/Zm08TmBwc2JURjJCK0wk
cjFEMmFqTAp6XmdHcXVoeyhaJT9VTFZiMTtud2ZHQz9Jemx9RzxAPVBtTHY5PE1qRWZYTWh6ZUlg
OTEjMFM+NjAwfChxVk52dHMKemlMQXpGUUFNXjxBdVhUPT9DYDE1PzVQVmszPFMkbnRKMEdWfDJe
YHlZWD9nZVBsUEZIZEE4MlhudlZObG0jK3BxCnplITAxIztNKlFYTzhzPUA5WTxhVEZBPHklM3dt
eENrOzlUXjt2Z3hxRDx3bStOc096KkBqY0l+UDxvQ2VjYCRnKgp6SG82dk1ZS3d9SmgyX345ejwj
TE5PXjNBSkZyfjt8aFUkd3tpS2NxMXQlPSN1VjI9cj5PR3RTM2FhZXc0K0BvU3AKenZQWlI+S1do
O0pEYnZkTlo4UCFiYWBWeDJeaj08a3NwJFFGZ0FYVkBsLX1XR01YRWQwZU5heH4rcS1vYVhVQkll
Cnp6SCM+My0+Y0FFNWM4N2sta0xsY2o0WFBnJiNafnpwZ0deQipaej9DMDBhLXdqP3RKbXZoSDw1
ViNrV1k4Z3QpSgp6Z34xSTxURy1hOUE/NUsrTHJmTm0jTnx9UjxFcnBTalVqKU8pbUl0X1FQUmR3
blRLYkx1SE5NcnlRPHBGR047QEAKeihZOFNXOElRPXktMiljbilXNWYpb1R9KHxScmImQmBRKnFe
UEkjIWtQUSZJezd7XktlU209MkcpSXBGUll2QWIrCnoxPT9YTCpUNzA3X21BfUROVWZrQj1sNEdK
Jk8oV3VKa3NIU084MFZ2ZDI+TVctMGFwYjB3XnFOd2ZrWFJBPT1ZZgp6NntWalQxNWpLdHVZaGQ3
eFJFMzgqWEA0R0VeblMjV28raSteO1p3PUs+I1Y4cnI+NyVvc3s+S083QkF0OUNma34Kenl9VERl
bHxsbmt0ZWdsZzB0O0UxVVhWU0FfRStRa2JpQ3lGdF5uX2UkI0paWT1JOUB1eXk8ajE0K3s/aj1y
fHlNCnpHQz0mQVBoP3thcEtzISVSIXA3YTNrQjZMbkBmXkJGdHsyZzVgKHl0JmEmZ05YViZvKXRr
dXhBYX5OWVdrbEpQTQp6KyU5cDxOVUhMV0xpKXM0amFoaDJufU9+SDFaV0xSeTBYdWJBRmpNUkF2
Yk9NQD5IYkw9PG1kaHc4KUJuQypqO2QKeitZVjxRMUpIVEI4YU56VUtibGFKKEZjNj1qPyVYU0w0
MkRKa0hJT2RoYWMwKnhMMG0/R1V7O3YtUF95Y0ZuQD43CnpLeEFibit1d3NneW9YVXw9RFgmMz0r
UERQPFQ9VzhLZnJscStqM3VPWns0UyQwJVZAbnBoa3o4VTxxdWEhVWJBbQp6cFoobEA8QmJZZk5M
WVdnTUQpVUFrYy0yYHliWCstSCRBV0dmelA2N3xBcj0jWn55YSZZWT5TNlNma19jV25RfDMKekxT
MFlxek1FKzd5KlE2NGJRb0JseCprPTNXKiVMdTFlITVmVn51RzRYa1luSW45fERmUSVgKlJDdWN6
SUktcTZfCnpzNXpUX09CZyVmbG1hPE5qcmhFRXQ9KmlDYm1CJXY8TzV6cE0xUWU7WEQ1bXheWmNJ
fj0kSF5SK25SKkZjeD88OQp6b2RUdmFpb3V6KVUqcnNwQjNlaE87Ymg9WiZxbGdWRFMpckxGciZU
PCp0T1pMTilVIy1OcCp5aGJwYFZHXnI/MEUKemREQWAkJiNpTz4rK3UlamUyfGNNMk85OT58MmBE
RCQpME4lelk1bDhKejZqWUhhWTcxSi1DUW9fSF5YSj9VQkFuCnpUbUlSbzFHQDhWUXRldSlfdDlK
c0U9Mkg9aDs2ISZ0PTlmQl5pTTNeeCNocDc2VWV1YldFZzF2PzttU1A2cWpqPwp6SClwTmAqY0ZZ
JiNlcW91S0gyYiVzLUVge09XOXRBJlVxK25RVEhGa19iR1J2e0BKWmUlRCVCTHhsPjVocDV9YE4K
emB3NTZQJn05KV9KTUppe1FWRW8kMmshb1pHQHE7dWJ4KXRKbV5iZ2pQV1o4RlFhK19MaDh+ZT1N
QHMkaExfLWR1CnpAI24oVm1YWkBCfEZfc1BvN3JzelA7P3hadSRmN01VMD5Fd1NvZ2pXRjMheSZN
JmYqcSNTMF5MQDFEVUJZfmFINgp6dTBrMyZUI1dxNnMqfVRAVkF0Vytve0hIV1FAT3B1RWspb2Il
ZVNtJHdpeDd5bD99aTxtRWY0NCE9bWpAIWtxN30KemAqTzlacVN1eGZwZndCUztASkFCUUw9ajhH
cihpcmteX15nPmRiRz1kJVNzMTxHK3FzNnhaVE9kcDF5UHApP0pOCnpPe2khJkB1MTFWKWlkdjxr
eFIxUTYoezZEd1ooMmtAeD4rST9AWFgqVHwjPC1FbSp0O2F4RyQ1K0IjOFgxM2JEZgp6TDM4YipG
NWluYnEmUTs7XyY2TVFURlJke1AzIVF9dSRKRDNYKl9FQTRIZ2BqcVZte3xhWngyMFBpWDxofDlR
UTEKenlqK3N0SzYhbytqMiheU2xAK35vbF9XTGgyR3pHZ0Q8JnBtJCglOT9KIShlaTB8ZEVONSot
Y3A5fEg1eDJVeyk3CnohTko7O1FveGp7UGMrNVAtVHhaRCFNIXgxZGYmIURQfTNyWG1sZG9wRjJT
cE9vT3BJVlI1KSs7Xyo3M314fFhPaAp6PlpLYWxjVytRTElLUTVXbl5PRHZJfTMpd1NCRzVoZClA
OU5iNXRnXzwyTlBucTR8cEJDblNPWGVLPHspYmF1TE0KekVpem0hSnxVTldVcUNybXcwYnBSKE5f
KH0rOSg1akNEfkhCO1FkMFp8RmxwV3Y8PmxwWFBRZX40cHojb19MO0hRCnpaMSZkbTgyeDY7JXZf
QT45Y0Q/I1NEU1F6YWliR250RFRoelFyPmpiKWVgeyohT1RvdVFpXnhMeGtgVTEwans9UQp6Pil2
KXYxRUoyKCRGQzQhV0d2Wk9Pc0tmJFE9a15ONmxkJTZHJHQ9OHNaO3VzVTVTKUJrNUtPUTxKdFpj
VSgzYXAKeld6cGRvOyVKV0FmTyk2QjI8MVZzaFZpK3E0bnQrViQkflRvKlpYfSkwYDwjJlpja0Vl
VHB5KzdtelZyVHwyMSV2CnpsUmxTSUk4VTZrbWEpUiFodEJidilvNV8xWFdiZCVLUEBVTnArS0pj
LVFwK0tONU0lRiRhM2FWIzQwYlF5WXtRLQp6OCkoZTtuaTZgPjRgek10XzV1dnxCT199KlRHM2Zn
JX1uP2NxSWY9Wip0VW9ELSU3LUZUUlhDTkcjbyl7eXFSI2QKemVQRE5EKXVtPnt3JDxtaWtEbkM0
WUp8ZXNWdzl1NT9ObFByMisjV14ock1ZJShlRVk8SHQxIWpDPnQwVHl3TXV1CnpJTTkzNTV3R2Mq
ZUhfbzgmPCZqNUJgNCZ3RTVaeXI4fEN8REV4UElONFZDbm1JXlZMP2JXNzEkeUpfIX03WllXWAp6
Wkg5TUJKeFZTfSM9LVBjWXZVQX1eMjlUSG0hT2B6Vz9LWHYoKzk1WW04SWtMWnZAUUF7KiZWPm5M
NjhyeiopTDIKeiNAb3pZYGVVSSpSR1BPOG1rX0lPRDZgTEx3WXJ2YU8kYXRMVENycTFkYXtMakFt
JjZXYDJUYyR0flhGKFVLPkB4Cnp2S3xnZXA1eHpzMXpAVjRKRj0kSWltdzBuJUBEbTZ2YWdiRUw0
OWtLUXxEZiskMWQrIUgjTlRHUk96aypLYVh1Mwp6cE5xJHJreXY+VDspb1ZERW8rYjBAOHdwYCFM
Uk0lJFI8IzE3cHoyYWNwa0xZO3hLc2dRdytaUmBqYVIhKERTekgKelU9UjRabkJCemNYTG1YOVlL
fXt9Qn5BLX1WS1VyfiF0V28lUFl1VWRZI3ZERjd1KHE/cGdIX2pMVGxLKz1RWHZfCnpzIyQ+IVlz
SmJjPiZFVUtxIWdGYlNSZVk+RHw8aC0hJH5sclJlKHRaT15MZTNPXkJjeWlTNGA8fEdTUjlKc3Ra
Ugp6I1VLPGVMdXxtRCFWYjE8bkRvY29KZjxTWDhLeD89LUFtSDNeQ3dGbUgrREQ1Sj8ySDxoQGQl
OSpVVnsyamBLV04KeiRpNUNrMz1gKXYkcVpRfW5+U21OVVZicFN4VTlmQHd8e3dAaihxaHFEMkhj
VD5GOSVRZCZ7UzNlKk4zUGtTRldMCnp0WFZUSE4wXlR2PFEqWV8mVkpwfXRueFhyKWhnKEVKcCtX
P2MmQDxgPElAeHw2SjxMSzVSRWp5Ji0+aE04dmV0Xwp6X2pWOH4+T3tFNUlQOFkodE5HV2wmPmVB
WGtiYjheJFkrQXhvdSpfUXVwMl5jOyFZQ2RCY1BUKmdgYiFXMz1AI2oKejhmZ31yNjwwY0A0ZmJ2
TUFIeStXVSF7JEl2KjU9aG88RWRySUtkYVloOT0pYURXKHdYQlR9UlE8OFFeS0xQfEclCnokczA5
VFBWNnQrKzFIPV9sJEBScnAoZVcoN2l2bmlvY01ed0UhVHRPZXpBU2F0TzlsKnhVNkl6OHpRcVhI
aHpCSAp6MmU0a34mRChadHUlVXF+WDA9dmxFUC03KEdNZ3t6UCs2aWc1OXhTMExDbzFwUmNoSHVU
WEdsVjRhUVNEKjRndj8KenhAYXUlKlczdVRxa0k8TkFRQDg+I1BpSER1aypGRmVwZG0jalVpdnJI
WiRJNCYtT31LIUdyTV5zUi1VUVVlQ2ZVCnp3VmJ1dEN3Q3lhV09HemFySkNCZHBzKnFheVEmP1hN
diZRRDZVbUliWSQtdFkkQ2I3JWBVZWwpNDhJSDFAT1oyVQp6TUl4Xz4+JGFfQ1NoeldCZVEheS1X
T3VuIyh6NG53WXlnUGVGcCg4R3w0fUNPWCh8Z3xWKUtmXmBLMVN8PkFCbEUKem9KfWB6Jmw7ZTdY
I25yajsjd3g/YU5fKC1wQWsqYFMyMk19TmJ7eE1PQ1dYVzxUQTNVWC1VcDhFYGJEZzBgakM7CnpX
KiVqPTFiY1lMITkoLUtLZiVkZHB3UmlDdVhQO2FBWTEmYykjTXg7ZDxodGxXRnleRCU8Z21vcE9e
cntgTihPJgp6JEcrVWBEcmx2fSomamQwJiVPdF9XO3V2bk5feFlyQ3VaSilUQ2ckcCo1dDAoNWpU
dFRLM1NqNGd5SF9TJmEtMk8KekdPdXNra01mPkJnPnBqSF5yPzxkPEJ4WGs3cytnMklsQzZgalY9
NFBhb2dmLUZZSDVhVUNeVSZUTSFKY19XSU59Cnp5fGdobDxIb043I2p1fjw4UExSQXMyNj9OTEAh
XyVCSHJTVUhFdkBPelNEQ0NpTkplSUc0WmVMblJYLUdoK1JHUAp6Ty1fWChgNnBAYWlPfmh7U3Ar
LSU9MSlHZXpodipjSVFBKGNDQ3ZQT19GJXleakR7Ym5IUmgoaHN5NjtNYXo1U2IKejYkYzNtQnhW
TWZAdSglP28mTSFYRmlZc1lCcihIMGN2SjBtUEB2eEJiUHsycWJlZ2MwWlBGWkRmQ1NuRWU+VlBi
CnplJCFTdkQyOTZ5QU1FbElWZ0YxO0lyRF80R24wa3IoKEtRa042YTxsXnYyWVpObns7dndgQila
Yjl7MVZeKil0Kwp6I3FsaCtreFhyKFFQe2xue3F4PTNsflAtI0VZZk89S208WUZlK04mTjQkU0g2
bUwtRlJNUkJUPFlCXyorJFojdXQKenZvUkt3WV5zQUw5NkdsQHljRC1SLUJIV2M7RElFRXxGcmUh
WXE+Xi1IX314eiR0cU53O0x8V196d3BVN1N0ejJTCnpPI3J8ZXw1OU5NSFN0QSFHfnY2cUs+TyE3
e0hJXzBPbn0xOT4tWXlGT0dvWl41ez99Qjc2c2ZrUCg4UDY2NSs+Ugp6KGp2PXZKbzVzdGhlJU4m
WFFsYUp7Q3YtVl45IWtvMWIxWCtRXnFVLUw9NyRMRyQqd2pJSSsqV1p+SCMpbSRVeG4KemJtRGoh
QWl1Tm0jPHJ5TVhQVjdadHVPMmV8RDJ5djZiVEY3ay0xLUYtLTckZjteKXU3TFF5bnBPU0NQIURX
UStqCno2MXhfXkAtKGlaPmZJcileTzZBSyhLfX51N0U3TXZzdnBkTzM2QHdiS2V1TX5ScWgwUmlA
PEtxTXItWFYpKE80VAp6UF49dGB4QTxIMiN7TDVnZ1g0VGpYd3JAaiomSmAjeXdMancpK1c7Z2lZ
TlF0TWEraHFNIzFTITxlazJpalg4a1UKejF6QmFDPig4fGJCYz95QzNlUk8yYUM8ZWMkWlVHT2RH
Pio9WmM4eThvbDRkOXM/fXN8eHVQbEFAV1Q8PHB3ayhnCnokfDg4VytpIUs4V1cmPCRsTXFnamRx
djRVV1NgWChLd0o2RSQlTWw1JnFoPlIzem5AXkpSRyRgU2gjfkE/O0Y7JAp6T1IzV3JFMlNfYSVL
ZTJaUnwlU31JcWo/Y1k3SiNqTEZ4UllgeE48YUF2fUQyTjQrM0s5Tlh4VVp2REFhYlZKRUQKeil4
eClQRX05PEI4dEVfe1NWcDVCNSphRlpwVChrN158S3xjRUlUYDIreEMpRXRGPCFNK3d0eTtKKUsq
Ky1kQ3JpCno5eD83TmUzV147SUMqTCgqfHMxVXlgdTJeeExUPEtuMXVXSnMySDZQdUpfVj1NU1NW
bjkzNVNFPHt4aD9KU15megp6YU8hUTNmQiMzMWN+TUUwLWQrdTVHb1N3cFJLaCVrVyt9VnZHYXBf
M3dXeDAlLUItVSkhUXZmfG59KiQ0RXh5SUQKemApSkhJVzdXUEB0KD9QQCpuNj9jb1I1bHk3S3Nl
eUZpKSQreVohbTU9MnR6SDtmVCsmUURFIWFjeCo/YmhNTjdgCnpkOTY/ZTUrNTg/dzNNNF9YMT4/
bmN6a0QqVGZsUHxqKkpKTUNrfSViSlRBVTlAKndWS2VkbDc4NHhjSGhyQDBMeAp6PEluZl5CJSV6
MFohOFl4ZytDSTFaRWNhPCRAVDtyP2tJfCVWS05rWXdKcisoOXJ2PlhjJn1oKjdUVWhhQ1F5PTIK
elJCOT1aMjBFUHtgcG1KQ18wfX1+I2YpTDJEQlNIQWI+LWFDYWJIb35ANWVPcEpEcjNyIWFKaGdp
cXJxJGBRQ2tXCnp0OGF5VSpzXzZjdEw9fDNuKFBLJkZGQS1gO19kSyZhe3NPZSN3KUF8NH54X0Ik
Z1VecmtAVFVycFFMTXY4XyU8YQp6NT5IIXszOV97JTFxJTt3YzlIR1M0bUF5SFNoRn5+RSRHQmhB
OVZoPDR9P1VWIVFsQHZIdzlCN0ZHUjE/ZyZyP1oKemZhNDNYWXQ0VHFCTW9zZllidn57SUA0S0lD
KGUoODhwP1RQSSVfdE1HWGV5cG15cmYpN2U9ZkhPWU9Hb2NeUzhOCnpxR0NmTCFRLW5IUkY3VTVa
JDQ+RF90JEtARCt1LUY5MWEhXzt9WCp8MShnNE9pYSVJTjg+TipqREpDO0pqRjAkawp6Jk9mPUx1
IUg2Rnhedl5jQE1FezxVTn1eQihGY1EmZUJ8TCVye1JSSkQ5PjtFZEkqP2U9d0xLcTBsI0xzLXFW
YTgKejcmenJ8P0ROQjVLVmdsM21kd1hPXjs1I1ZsTHdGZnVhb29lcnV6Uk1gMXsoNVltYmIzJV8x
QGkqJmB5XnBYfHNlCnpCVj1TfVRfWnc5QnItIXFYMl8wOUhyWnRGODc/MVdVKyhYOWArV2FgLSNQ
YyhiSS1aMntkflRqdWpndyNBN0dVIQp6fEVTY18pMiNpU1ZZfVY4azE+NlhnPnRFaF5JPiU1JDxE
ZFkpbj00KGtyMTE7cnhHZGtEN3tsOFgmRVBEWXI3QVcKenclQTs1O24+OVUlS29QNXBpe1kzYGo8
O3xUNSNqTDxsR21kNzFMTS1eTiNLc3M/diExSH1mSSNgdDZfKE1RITRnCnpLP2oobyFlQWwpMl5t
RGhsJD4la2dabj02TE5jYDluU29OV2JFOCRzQFJ8biVQVzFlXiFxfDdJQ3pyYGc+MWVoegp6UmpC
eX5iTmVRVTJ3QWl3S21mbn0rYWkzR0pRRXozZWhkVkpyeWhKMjAwLUJlNVIjWGBNfHxYXntFYXVn
JCpUSHEKekw1KkRCMW9XYHE5Xll0Qi1LdUdsVzRYTGwkP1BRWFgjbEc+RTM2KWQrUHpCSnAybylR
eXdDNlU/SkMjIUN6WE5SCnopJmNIb2Awd0lZUE5ya0pWbTwxR0g9M0BqS1Y3TihpPDFSR3JGemRx
RDVvOFI+Z09uQENBT2xSI0J0QV9HbmE8Ugp6M30oQzFVTndNfEttfmtMYlhMPSZXcilOWl57JE4t
I09fO31HYCZHSml9bnxPYjV6S0J1YnJ2c2dleVdfVmFvR3QKemg3YX0qMUkyXkU4V0whcnMrZEdH
TD81UDRZXjl9U29Kakt6TCNxY3ZXVSRMP2hmNXlveTRsPCV5ZSorN15pfjdKCnpXRmFDVlkqZnN8
Rnh6RypMTWNRbS1qWGhINEhINkN1WEhELW5YTE1XWUxYP2tSWDFfeHVPK1deVyVCQXlwSTF3WQp6
ZlQ2QXIwU34wd3lRb2Qrb2RZbzlqSEVHPSh+aEZ6eE8zVWVNbF58WihQMEMpbiNyQkNSSDx5MVQm
eFV1dTYlTHEKelBLb3Z8cHNZMWMjbGZZKiNfcEtnOGBObXRHNXt9ZDMreD5xIT19c3E3PVVfOVIo
dktgbzgwN3BKRilVcnVqMHpxCnpPMjJ7dz52NExqTVR8WXc8Wil5Y3B1Q1ZsUnFle2hBZWFUKVRT
SihxRlRWSjNMdjxZTjszYVYyKWR7ZmJzbTJQawp6Rl40JXVGYD0mI3soKGMlc3V1fmdOcl4mSXYx
PE5QeUVTT2FKcEoyP3RweX1MeXRtU0RqZm0zREdfKnhoOFB+NmYKejYrTlcyU3dtZDY4Rjt3Xj9o
TWJVaHY+MFdiNVJ9R1hETD8yJkV5NkxEVVNQMUI0MElGKHRfTTFmKjdRJHU1c1pfCnpiKj44YTxp
QTFtVHI4WGA1Qz5WdnJLYjIkKF5wWmthUTRFU3pAbihyMStmJVlPI304PV9tTnpzYSNTemNDbCMj
fAp6diglRDtNN0V4PDhgKTRCcXoyRVhDK0hLUjtPcGZhV0YjM35zbj1neVh3OW4hdjFhYTdUY3Yo
dFE1JHlAP2NXWXAKejdLNmAzXnhfbVYxIVFeXktKcHRnVUFCQlM5bW9Gc04kWD04MTZuMCYydTk5
UFglUSskZmExNnVWaE95WWA9MUUkCnppT2RDMjNhM0BwMzA9VzBtYDd+Uk07fWJad3NYSWZvIUF3
Z3NDaEU1RjJhZ3BOV1YoYWdtan5vUmo3JHoxWXkmcAp6a1A8Y0JrRlRHa0JDbyZ5eWc1IXlXdndq
eE82fDtSLWNvfmRiJG5XfmJ0QkJ0KG5keENYTyl5VWkxIWlHPSM7PUYKej1CdDcyQFVfVl80bD9T
bj8/Z34xeGN4PXV0K04zMHVAR3ZIZ2cqU1RaYE8+YWk8bUc9dWBVU19hfjB1fCEwN31FCnpGLVNg
PEd0MXY2YHBRWThRcVFKXkRQX0Buc1pJaVFjNnZoOG9VVE51Yjt6U2ZeZ0Q8NXs3WHd4ITRNZCFO
dWctMwp6UypaSHpidXJkcld6eU8mZV55STNxQH58N2R2I2hsWEAhO1goayR2N3p4cFM+UjB+U3dp
IypUYTNwfHlKdzc7aW0KelJLXyhGIVNINXo5aT5oJCtIVColPDFUKm5KJHVUTmw4fVNQbSNIdiUr
UHc8ZGpebzhEVyF5Q0ZhSC1kck5WMjJoCnpZdXpab1lgSTZHZk8/elktVkpOQTZnaUNLMHlsOXQt
d2NSM01NWnEmTS1hcnptUnAxbGhTPXMoZnxKbktIeng8Mgp6eld1bzZNM2VLNih9Z141RnF9NlEm
S21gbjNXeEtDQmdFa2Bwe0ZWKSskPHswRHFWNEdxPiNiUWR4M2goSHpBYj8KelVARCFacUd0OXdM
eCt1dDMwMUVZK2whYmtoXkVYWntkQ29eXmBVSUhpcy0tTHZgPnxQJD17U3NVTDJOe3BxVFllCnpG
X30jKms5TyZyVXlkdl9GLV5qZ0V5RE9BVlk2Oy1DfUJgVWdySkU/PWRHaWpjezVvMSgmKER3V15D
eklkPzspcwp6RE9Edl4kaTRMTEJTTVZjZns3bG5TUSR6Q0l0UVh0MHE7ZWw/STl1PEVsfjspSUpP
RWF4ZjJaNjhsIW4mMDNMU08KeiQ5dTl7WHtvOV9wIXQ7O0s+YDFBb3kmQzNBQUxQbk0/LVAtQElf
OUBPPWd2UXM+O2FjNGRoTXNWeUJjTztJZlYoCnp3YUJxNitZPlNMRTxZelNoYihiJFNxK0BXZWQk
fCRQfFdCRWNLUlR5JmBwR3kwPkVffEleN14kKn4kfDBneDFHbwp6QW9gRGlQKDQ5K1oybFNYaG1V
JiF7R19QZXJIKlFLU31eRFU3N0AmSU1GZTF6QnRVRmhyKExHNlpKSlZvQnc7KVYKemIwJVp2UUl9
YXVjbFlBJWZHSzgpSX5wMSVAYm5QXkdTcWJ1XiNsJn1fN2VVRnBIPCMwQnwkSm4oZmpSJnhsZjc9
Cno3YEIpMihjWExzTitJZXV0Nj1kRCZTeVAte1lrb0V5VUQwYyF+PTIpPF8/bFl3fHlyRUZSP3g5
ZTE3UHlqOVpHbQp6dWJ+SGx1Nm5SNVQzN1dBIys7enxkazIyUTAyJWNmRzQqfSskO3wrdVk5UWoo
P3pKa25ZUEZiKVZ4fE8pTV9YIzsKelpKZyVTJDFIUHJYdSpXXyVgMHcwVSM+azwkeTl8Iz9uV35u
RnZxa3p8SlBJc14jbl8/UkI2VD1yWCEqQk1saG5HCnolTWNYKkhSWG4qKUZsdmFzbjJ9MWc0e09S
aEpFUHg1N2tFYHZeWGoqRjNAWU1rdmdYaCU2JWBBX1MwMT1xWCpWSAp6YmFMVEFzT1U1dUNNeGpM
KjhQOX5mXmtsZnc4Q0QzYzBDI3VGZl56aDthYVM2I1lFQWlrb1orKWUyPTYtV01ofDgKejB7VkVS
PU5Dc21PZmp3QXdQZW0ocUk4VzlGUkgtekFlS19fLVJTO1d7fSQ8b1B5NVdqMFVxcD9PaExpeVY/
MkpWCnpUZXhFNHdTKFgyckh7NGUkV0IyPnI2VSUzeygwMSljYiplU2puQlpha2ImOz0+bVdpIXY2
K3JlS0ZHey0pSWo0Vwp6cXFgPmtFI0pRWnpgN3ZiKF5fMXVAZl9uS3RRQFFnZVZlR1RKRE11NEl1
Y31iQ2MmM2E4YSt5byoxTmtzXjVwXkgKekpAKyQoY29QVWg8eGVnNyZOeClzOUUqVmRkdkZ2bjNW
Y1dDc0o3cX5TNzk5R3xLPH55Sn1mcSkjQENOQGtgUmNNCnpTeHAmeFYrQiFyJFNzQVFSe2ZOQUlf
IzEwdUZ7VWA3QGxOITE1JnxKWlB2fX1nRXV5ZnpONH05UTFOP05Ma1ppUgp6bW90ZHwzSktRUmdr
WCRUNSYmPiU/Qk4qXyVHTnsqMipCbyM+MCQjV28kZGFQMEJgK0ZJOTtzRndoNlFWeyR4I3EKenBi
c3tPUl8+M2NDbmx3Tjg4IVVraChNKENCdm9gPGgtamBfc21hQktVbW5jOT1nKTM9QzFLRmAoIW9V
cHhKckJWCno+VW9RRWI8NHd0WC1QVWJoe0krezI/fj8xU2w8ZCNAV0YrU3tXJjxIRmt2d08hQDxR
dmIrUG55WVVFYkd7MkJpZgp6ZSZ+cks5UiFLPnJycEJyJGU0Tn43fm5SYUJ0Uit4T1lkPH11YihN
Sz99WXIwcTlISDRDRERyN2EySG8+dDZOYSUKemJBNmojUE4xdiMtRmgjez17aiZvbHd9cC1Sdkxg
TXt8ci0md3laR21pJjFeZGg8cGM5SmlpajdJe3ZJR0d3WGNJCnpQTUF7ejQ2cWo9TzJYO341cWIp
OVFyKXU5eCEzfU5qfTMkKFQ0Mj52YD0jJlJ5JGdLdV4kPDUoOT45I0FtJiVlbAp6NSp7NWp4RC1j
P2tFZ3ooTjNVbVl7d2R2Vyk7RXFUOGVofms3fkRZP2B8bkZDJXl7R1pZZkYqQk5fPTUmSCNRdHoK
elUlOXBWZz9GZCVUcFlxb18tfm97WXdsUm97TSRKPEl4P2IyOW1YYXIzbCNIJmp0RGs3SXg2WWs5
SEliUT8+fTh5Cnp2KEd3VG92MnVvb0JkVml0fVYmZCl3VHFwbzBHKXJUVmUtJGJDYlZVVG1MNVJ7
THZsYypFMVNeK0JFVmQ1bThXNQp6KGx5d0VQZ0k/eyFKP18pdiQ2OWdSMHBUSHRxTyUxM3JkezZC
MzZeMWB0P2clajwjeih6NzQxdkx6e0RUd3kqd3YKellJWDg9JitzPHVyXk45R3dpJCZxKDJSQjJB
RlZYYG0xT05hMFd9PlpGbDkzeDlNVihWKXwtIXYxc041ZGdVOXlNCnpGK2cjbDU1OSoqUWFhVUBt
RihUTV89eEROSzJZTVBQY3whaTNfQWZOVUMoZSpQZSpFfU8pTjt+dilucUgoTTRhfQp6Unt3bnAp
VDI5TWAxZztXQ0p7NTJvOHM4U2dFKj9XcHs5QWhyWSt5TiVGND5WMSpIJj49Q0ZVa14rUnAjJUZL
JHUKenlHJHhlcnN2R2leOUhqbF89bGIycjhyI0spWEdxZUc+R1hRWXk/KDB4I3RWSmAmTzkoQGp3
SXtJODhwe2hDKjRHCnpnZTNQYSprIXlqKk4pRWljbHwtQGMtdk48VG00KVkjclpnUHY1cy18Nmtj
Rjc4cyFzPzArLVMoYVBObD09b2E0KQp6MDhMVzgkcjYrQVcqOHd7emM9SXVKS296KEtlK0AmTWhp
RmtfJGV6ZHhueVlEV285TS1iclAjRjZNRjY3KDE7dC0KejVTfTY2JE9KJSlIQzVqXjtxOC0/OVJO
NiphKn1YRldhMEpCWDk2UHUqaVJDMiREa2U8NyF9Xyl7bT0pKml9aF53CnolUz9qRG5IQGBtUWs9
bH1VKGV1K2E7PX00ZTUxelpIWEtHeUNrQE5UdnB1djMqaDxfTVh3LTFsWWtlNzZNPDt2Ygp6Pz9Y
WVVlNz5AWCo5Zl4pVlY4I1VOcElMei08bXRxOyR4cUZpfkBGLVRgME10I2shMXN7eHw1KXJHRCRP
cnIkLXMKej5yVVJXMkVqa2IlPUtIbWY7ZjxWZHU4P1RPd3NjUUw+JWNmSitSQTNzPzxiMnZJcjBa
X2N+MSpwa0ZlZTw/bXk8CnpDQG8wd2BPQnV5K185MXl2c0omVV9Xa18pRjYkOGpsfndYLWNxRGZG
SFYlWEZvfj1RMlcjak56bD5xRTdtPE8wJgp6LW5hcGIqUnpWTFhUO1kqV0JKZnFVYVYkOVlxOW10
eFpmRDRQOFlSR01LMSgyJGJVcHtlQGF7V1daQ2lpcWYjI1EKemVfJEcleilIJTZIYmJSamc9fDJp
Vj93Z2RSIVpSKXF6biNwT3xBI201Sjd2Q1EmbGVMbDhPcXR5U2YwIXFXNm5ECnoxYSo0KUxYJW5I
cUotKHVpKXtweUB2PG43Kj4/VF95SUY+LXBUbF5lK1lOd1JeVWI2e2tvJEI9SE55QUwhV157RAp6
PzsrUEYwdk02MmAxTi1+WVl4NWc8P3dKT3dgSmo4XzluZyZFV2ktOXgzXmI0NDA3JDZTaitJOWVG
MnItOFBsaVcKemg5R0sle2h6bjBHdSYzNlN7JUxEJSg8SFFXIzluVlJoeVRDX0YtY1dTcnR5K0NO
e2R3YG1RfXdxN2UpRjtHK3RXCnpqMCV+NFRmZ2pSU1ghVWcoNz5NaG5WfTg9cGI2aDFiNiZOI3Q3
QGpucE5DKHxeNHwqNUxsRmxaPHs1KHcyZU9DYgp6azh4dzsxSUgwe2I8JClaeF89PWBMdEpEODh5
Z3p+PDBKcHA8MT5gPGc8dmpQNyM+MGNGYn48MktUOFVgRlhhMEQKejhVVyU2YUJ0bysjJnZ8Nm1M
OCNYPFdFfDQtbFhxWj1xcW94Rit6fXtyKnNCfU83P2l1UTVKREBmQk9vTXtpcFdkCno5elR8TGl8
VVMma0lkRlFxYGU3c0ZQUlV8TXV+I2QpX3YoeCNrWGckPUs+Q240S2kjN3Y0MmJWUC1IV0pgIXI8
IQp6K0EjfjdGPTctbnt6fEJyR2EhITlEOHNMKWZ+TWM+X3QpZnVjOVM8Wkh8bEg1TTFWVWE2VlZi
fEgraDxRUzs0UlEKejZPKn5lcGVpKFlYWTg5bzh5Zl8xeEd1JWFveTw/KVR7SFd+JFl7PjRMWD9P
YUk5QkJvUFdpPmZuYGNgbVltY3ohCno1N0I0PiNqayZ7UEUoWXdMMXdwU2VVQG5ZV2U+SjsqKSFQ
MTJraSQqdUh5LXNWMzl0Y0pqaX5hQlhfY0JmbjgqQgp6QXlebWkoOH5JKDR9fFQqREJPNWpHaUtw
O3VuLSVvJjhpSDEwdFVqdShXdm43KEB3WEpFWjQ1e3FxIXAlUkR4dUMKekskIX54YklET0tZMmQr
UlM2O2VAcDBhWGlSdklDZ2NtbmA0MnZ8cDw5YytIbiQ9aGdMPENxPi1GT3NqQTJCb3lVCnpTJjl4
XjIqUkVIWGZaZD5EQURDSiE7M0FTMEItPEJONiZ5RG1Oai03ajwjPj4tVDdhUiN3OzltJT5gKGVG
Vm5CRgp6K2FDSUVPaURvYURoalRYMCoqcEcoKyVtaGVMKEIqUnU5LWk+STEocylNMn0zc2wpYC1G
bjJNd3dqWG5OO3tUV1AKemJSOU1QSjhXIW89QT0jZChldGlARl5lLSFDQDk8VXo4WEklMW15PkFt
MzNVNV5fdFFObmk/THlsfi1OTyNDdzVuCnoqRkV3T0Q2V0dydTREZktXYnRsbTNjUkA2UCZqdnV7
e1Mja2U7c1UmLTN+aEdOan1mMXVSa2w9LWdlRn1Ga01kdAp6KjxKJkAwWj5YSHs1N1FpemhoJVIt
YH5uKFEyYVJIWF9MYlMjeUFCVjcmTDVSbSpNQkdyZ21teVpmK2lMUSMmOUkKelg2aEJkcCM8Vypg
YHwmI1BOeDR9V0VRKiNXQVYxPD5+b0c4JGFXOWZWN2cpSShSX040PURoUiFjWEBhVkZNQSlUCnp0
cUdXcEAzV0p+JVV5fWkwZWY4P05hNnc1MmZeXzc4ZzlhPGIzSkdhLSNMV1RUS2NVJTdibUM1LShL
fmNXT3VTUgp6IVIoXnRDTD1IdFZxIyVVXlU0WjU8ITYjVFN6WmJ2X3t3VENnYm0oZmZpYWh5TXFi
Tmcjd0JLOXwwSyY+PjxyNHUKeiQpeilheGo/RnR6eW5OTSV9bk40O0JpWUQrSD57Mm9paWFkcE5J
S2BWRj9XUzUxPEZjIylPYGpaOUxuVW9rY2BPCnpsWW9Xais3OyRLQmg/cyhNbkglPUo7Tzw2XnVo
NUtCazN9TD9tPG1abGkhVHo4MmlPdVB3REtgKmN4KGV8SyE2ewp6KTR2Vm47KT56fDRLKSs4K1l8
KiNnfjk4ZjFqX21DVV81VE5UTW5XcWN2TlA2Y1VYTVB8RXhZRWdCYEhJRm4wd0YKei12ITQ0Uj8o
OSg8TX5+bWBHWGZvXmsjfDBHflMjKCljYkxFZ3ZgSEI0bmRZZ3k1NTYjbktFaSRqTWdDIWoqaUNN
CnojWmJUdjB0O3J8Rm5NeSVzTXxRX0VvYX41KGx7KHJtKERwYUkoalpSfDA1N1Iwa28jay0jQ0o4
ayNWanNzVzA0Mgp6bjROdGpPMXJRZjB2M3JAPWp2dzY7WDB5cFpBU3NTcHRDSmB2aXhgb2BhX3RY
XjRhKCklcmMlRld3Kk9uJGtjZWcKemBjTUg+c3FeUT1VemgmVmZHM2JZOVFhPmclXlZyZ2NnZDEq
bmJrdCQmUnJ+czJNOWtiOHBhaWxLcUMxcyZRQXt4CnpqTGJiVEUwfXVrOHszPXZRLXMwTD9hUzBP
TnFCZWIhMmBtKWltTX1INGtMdTxsVV9ufW1XYjZJcmYlMXhNblokJQp6RnpEVmt8MiRxNU90KSot
akVwP0pKcCV5SUApbDhPX0o0PjtVNHM9Y01UVndAanVJXl97OHV1UCY3T0F8TElIZUIKelMxdzNI
ME13RVc+YVJ3aFZgQHRxX2E9THJFJHk5eSZgMntHRmpgXzA3JXhDYShLaitgQGNSK2pGJjgqeT9w
O2hZCnphR0IlTGBlWVEwdSZIQUxSKWdNK0RURGBrY09+byk1ZGB9TnFMSngqX2YrJip3IUNCPDky
fDVGNDkraV9oeDZvKQp6SjF2bURAR2MhSlJePkpZO0NHVGtZKjR6ek5qRjFCa3krVlp4R3RZJEUq
Z3p8YkJfcG5vMTUjcFB6WG04YUhpXyYKek5XM0RKYT0kI2RjN0QxTGZlZjRrdHtJRmhKSCsrfiR3
enxIeGVCP3FUOGticlNreHxsXnhQYj9LdjI5fjFebyNOCno7blpnMjBlZVAwYFVUZjw7SFpXSUl0
TVNRUFN5cG04eUQ1V0NjdWtKaCg3cmJCcFE1JGpWOFojQSlGUU5jWWFYYQp6STVhbUdXWE00c2U8
eiN6TiR1aHgwLSFTYXp5Pm0rQl5VcmNpVkYlaEQhRjQqYTgwRncyWmM4R3d0TTxAdSVzd0oKelJ5
QmwxZnVZKTI/bStsJFNaRFFuS040ZnY0Wm91bGNFYCNZIU5KdXtxZUttZXF5VCphSzZOd0JNYChx
ITMzcF99Cno9fCo4U04zOUk5ZE4mVWc1P343JTBEQ2JDNEVyIW1wOzc2RHpYLUZlNmY/I0JIfX1G
aVNVQFNYKFFPM3ZHd31NRQp6a19wVHFae3BQJCt8LVFzK197O0NoSzUyeTNwUlo7aS1aTEFsTl45
fDNsUlNRSHQpdkM5VWp9Jil4R0Z7KXN7MXkKekpJTUVBS19xOTtLSEN1dDRMQFR2Rn5GWDkpdzNI
R0tHUyt1eWYoNGx1ZG93fEAwTHV3KTJTN2R7d2ZKWmc0KCp0CnpTPDlOZTFiVzdQaFRSdj05R1JI
I2VJZCNBVVFZNWxiJlJUJVp+UUJKVlgqMFFzRHo2TDdMSnk4VkdkPmVycmtPZQp6MHljfjE9MUA7
c3NCLVZYTS1yKGhweFZjKEh6fiQ8elZDMDdtIWRCPSU0VEx9ST5LNThQcylyKFNZbExaO3lTPWIK
eiRfNGN3dVEjbjEmKH0zQXslWlA2RlJrfn5gQzBNTiFRKXR8WkdmU31fQXpjZkohTTwkMmFVc3Vh
N3lfT1F+XkJkCnpoVHJ6ZDNicj9gbnZMUG9PV1RnNnZNYWtqVz5JYXtmWFcyZVBPXk1wUUB7PjM8
cX5PREh7U3ojMmwmQklGO1FNdQp6JnxUKWcqYyQyYiRQWTh4MUQ5SGtoZnNqQ2U1fGdwI3RpTjA1
THFoU3EmN0F6Rio3LUBwRjNaTypHaU08YEBLVzsKekdxJWxvKnY2enBobGR1RjlsdHtLIzNWUn1r
QWclK3t8fj88XlFlb2tAR3szLVAwe1IxOUpKczFXLVJFSyhZTHtuCnpjdlpfSnUjTGdPTD1HVTdB
UVc9fnIyPmliYUs4V3Y+SWRETVgqMF8hI3x8JlI/RU1hUWc0bUkmcyRjd29XWTwrQAp6ezNKKEU7
Nl94PTIhOWs4TUw1Zz0wSFV2cFhAITBVTDMhZnFiQENuck87ViZQWipTXyshKzBWI05PZ2M5MENS
XnYKemFxYUZQNnh1OEBAYHFQX2gqeTA+ak9DTD1iWChRTEAxamB8Mm1Tcl9paGxYVz1NIzJXR3R0
WD1yOy1XMUBeQUBrCnoyelVqbE9+UH1WSDNlY09aTUBHYTtxPilsS1B4VjdeMUpUP2NPNHgmY09L
ZTw/KCF7Nzl7U3toPilMbnElbkolPwp6QWV6K0FoUUZtJWxtPW9fS1RsbWNiJEZHKHszP2ZmJntL
KCMkVWV1T2pEVXJMPGNtJU1NRjJfWV42bUVAPCNQd3UKenQwIykmOT1RWmV3TUhnUl85QF98JV4h
VCRqM2tKVSRlPDw2aTt+fWFCbnB+d2c4K0l1LVgtRW5kdnFFVnlnJU9JCnolYXVjempxIVloSlRC
bXpfKF9UYGZaa2VObFNyYSV7PiNAMktKTFB3OH55K0k7e1FSKEtqMjgyK29MU2kldnFpUwpQO301
Q2QpbUFDRlY7UzspSEUoPUUKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2Fw
cC9yZXMvZWNsaXBzZS1wb3dlci5zdmcgYi9hcHAvcmVzL2VjbGlwc2UtcG93ZXIuc3ZnCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmI0MWU1ZmYKLS0tIC9kZXYvbnVsbAorKysg
Yi9hcHAvcmVzL2VjbGlwc2UtcG93ZXIuc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0
dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9
IjAgMCAyNCAyNCI+PHBhdGggZD0iTTEyIDN2OE03IDVhOCA4IDAgMSAwIDEwIDAiIGZpbGw9Im5v
bmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0icm91
bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMv
aWNvbnMvaGljb2xvci8xMjh4MTI4L2FwcHMvZWNsaXBzZS5wbmcgYi9hcHAvcmVzL2ljb25zL2hp
Y29sb3IvMTI4eDEyOC9hcHBzL2VjbGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4
IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLjE1MTIxYzA0YmU3YTRj
YjlmYjY1ZmYwOTlkNzQ2N2I0NDRjNmU5MGQKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDcwODcK
emNtVjtnOCZLcWxQKTxoOzNLfExrMDAwZTFOSkxUcTAwNGpoMDA0anAxXkBzNiEjLWlsMDAwfHlO
a2w8WmMlMUU+CnpkNi08KWI+TSZKLWRDQHh5THdkJTJfJl9JZ3BrO2dGaClSWmdiajhFajJGTy0/
SEM3ZG4yaGxeOFNuOVk9OTVWIwp6Nk1yVT9jcnI2eSRtaUkyYTZGRlVJNU9pdmoyRk9Rdnp2VnBs
RitgT21VXmtgK1RPZU8lcGIzKylvTHxEZlYjUmAKenMkWU12S2RIT0EtbTc9Y0pAPWUqJnBsNzVG
OU0rS2BgKUM2QnNWQUZoYDJlallTaypVYV49YloybW13SDdjYEE5CnpLKEtQPCUzIyYxUlIrZkQj
XkwzI3p3eFM3dElVbHotZWBiJD85WXVneFkoSW5aQHNsYCpTY0x7eHc2THw/c0hGUAp6KHFXSUF5
P0Ehej5aYEJMK3JXRDd7UD5weXQ1JlZASHtOKlQwbCM9WDk1d34kPis3P3RTRmlSfCY2bGRtSDZP
VTwKemxwV2kpekh4WUhfempoRWQxKU5HPEQ3SGRzPWdKfjtCY00kaChJSjNGJEhWd0tvSG0rVkxK
Vk1NYHk8KSRJWUdoCnomQERmXzxyeHZGTyQqWjMqSm9DKlVoTkxjWDx6UmZSMFp6PFkhTEFORTNQ
PGUpQX12JTlVZENHdnxLOG09QUU8Nwp6ZEF4ZDF0IWxeWEo/anlRUjBTZX01cmVlYFczNVlQKG9l
TkB3KlRBbHo0TCRrUHlnPkhrSG0zZVQqdXp+Kkt4fCUKel58dUNhc1pAJGZSPSlqUlRlb2ZmUjZk
dSNJRjJINSZZPW5qdUJ5RXZgXzRDTWJKe2VnSGEtK2tSVFVIfjBAaGxCCnpSNyVfMCtJfjVBPyVl
LSUkMzF0aGlKfU89MDs4N3EpJCpESVFQVnN6IXNWQTt7KzVrdipNQjg5SmJYYz1RbypZdAp6TXEp
dX4mZFdJR3draTlBYkhGYEhsbVllWEg4M0tDVk10cD9gKT9NWGMqMGx5YERnJDdFQT5ocmVSZWdr
LVd0M1gKelg7e0doOzJZb1F7QCp2PkA+bCkreVJSI2slNlJxTzdeQnRTSDw+KH5fZzsqTU5vTys1
b09SNjIqTUl6KUtsfFYoCnpLUkd9V1pOO3pqMjRpYCgzSj9KQ1Jxd3AmNTF4UGFzcVlMQTwoOUBT
UiU0OChEZm9LaHkhUjU9ejt0eEJLWXorOwp6cispbTB8R041S1Vab1BlOFU/VC07QCpEMiNVSXxo
ZSM1cyQzZEotK0VGdypCZWhOfDU3JHM9UXdwMzE3d0NLOXEKekBBPHt8Uk1pNTlHI3duTzB0OHx0
ekclZS1wV0QyNyVUMHgxNW8/VTJJcURrKT1lQFRyRWlMcitfSX19NDU4aVc9CnpgYUBIS1NJb3w+
V012PkNAcjVmY199cz0jbntPJTxpX1JGTTNSYkNsRDl2TjQ0PWN1S3A7JmFBSGdFcGdnKTEpagp6
b1FTeFV0YjlmNWR7NzFHPis3PzNiOWVsUUQ9KXJnPipnJnRsfWFVTmpHNUhiV1J1czc3LUxNU1JF
b0U1LWc0OTEKekZTeilfY1hNfiMqVmxKWUVCJiR4UHomYHdjPT1XNXpQTnRGJkJiRVRILStFdWgl
dj8laSQlWTIhOzliaztOQDRICnp5TCRDJWNRN1RHUD8oQn1Bb0FWc2V6KVVxe19FRXM5dm0xdkw1
ejVzM3AmI1V1aWwlaz8oWCVVYFNLVWV7PlZvQAp6R09WWnlxdl87UENSQmh2dXM9NCZvcFopbkh9
QmxHXklHUiEpN3poQnNBX0RENFVWMEE/Qjc1NSNHe3xeLWNSVGgKejl4JFQmel4oQE8tcGslfExJ
M1ZPKkc0WE9oJV9DKFg/N3JEQk53fj0tRnZSPmQqfGhFMjMrMytRUUpmb3peRSRBCnptWWpDKS1h
UH43QXZEOWk+NURfTEdrU1Z7YGBGcWktWWc9SnRRKEI3cDlTY24malM5UDdoVXA+ZH5XMUNNVnJF
KAp6LWRJSV9LOUBXSFReQzxeRGQ1TERneVN1TXZEVyVpUGRORzQxTzBuMVk+eGdUMCo3THtYWkdD
bl4hakpzPllPdS0KenU+endPcGp2dzVgYCoqSHlwU0p4diNNOGAhYW93UVVPazA7eyh8PmlAeEVu
JXVnVihPLXZSX2NlRDFRZHpxKTxmCnpqeFJkelZAWkQyV2Nte3VWfWR6emp7RUJVazNhaysjdy18
KF4jUG8hMkUjK1NjUjEmZVgzVCNpVlZyWGU9a284Kwp6cSFlIzc5NWdVJHtgSHk8ZHwrdzBUdDBk
MUAwdUpENz1VdUFibj98I1VBK1gqK0I5R1E/ei16UDFGJiheXzclPiMKekx0YVgzR09jalZ4blMk
b08pRnJaJW5pV1pjaSM7X0Zgci1Wb251U3w+SmYjQUFSLXVKNHRtc0hjTylTcT5ZWmFHCnpVc3cr
TldMfFVmeXM/JjJzbDMjQTlrKXFrYGVKSD1SUGYjdCNTdX5MYU5nbC03MFQySzdiVTQkOWFFOE9a
R2FpQwp6Mi1Fa0BpMVNMaFI2ZmFBaSs5UCFnTWoyQ2NeQWpfPGJAfkFRUHR8TG40VEQ4NVdxUHtw
O0QkQ018ZmpzWD5GeWEKenItI3x5R2RRTkJsZ0AwR2JTZ3hROzhkeCZtfTByaU5VPXo2Qit0OyRG
aGojUnFOb0IwcXZ8cSFaS0ozdlE1NE5fCnphY283ejBzOXRzWm9UIV50b0x6T0V0NVB8U05VM35q
YXVnJmBIPk1TLXFGXzQmZURaVElPbHtEU3V1WVIzcD1fPAp6dDF5Xyl2MkFGOFpHKEgrbUN2IWFU
d299d1AqSGB6bDVXaX51Y3dQc0ozODZCY1ExR1RgWXV2fCNmc1RDRWh6Z0cKelZwXmVpQDREOGtT
PD8jU1VgKDk5WXUmQztvd2xNKDh9Vys+UnQpOCtMY1VsZSt0JFYjbXp+TEYlZypNS2ctZSgoCnpB
PWBLQzxsZzY+O2Fsc1U8SSFEUGQyeDd2VHdMYkJwPE1nVzNLKG48a1BnIzA9YTVKK0FfVF5ndlg7
O1dTZC0rKQp6Ukh1ejEybnk9N2I9fmpSckt1QF5xNm9zQyR7d3JlPT5Ib1QwaiNrVXFZNUwlQkoq
YT89SVRHWmdiJHV8OT9NJDAKekN+ZXh4S2lfZEQqRlc8cF93Qy1zaCUxOXdOVG1vPG1lI1FDZktO
REhqSDtSbHpkR3VqRGxVI0YjfU9oeiUzOUprCnpNSG1EYUcxRWQzSDJEaGxSUUZ7bnhfX29genZh
WFIjVHJCR0okcnxUU2F8SFFlRDtkPkB1NmtzYTltX34+OFlwcQp6QDxYP0IlWnBGNXdVfHB4ZFlC
P0I7aSViRyludUY2QXV1KSlzQlBKKlFIZihKYWcyPSY9XiNaVzJyO0l5Nj01UlQKelBNY0ooMExF
R2RNQEh5TXJ9QEdhUzg/cWh5b0VWTUNITHNGZUM1JTVgUjBadmQ4dzRnMX1VPGNSelVIcHhJK345
Cnp0R2I+c21TTG4pclc4ZUZRWHdzPTVEe3I7TUh0SnBQeWoyMk5JaW8/TCVpZTZ2LXQ4PVM5NXgq
NFc4TSt6ZFpkWQp6SCN+aG0ma1ZqcTVRTWFhRXM0M0YxZmZyYWtTSyRxNmU9YWthWVF5dTY5JWJp
cCMlLUQwRCY+JkRyS0A1ekpCJGAKemAwKThGM0QkMD18SFlAZDtweU07dHJzMiM3IWBiNkMmNXBJ
aH5VJlFUcT0tQmc9RTdGR0IkKjRLKmxMUlZ8ZjlBCnp2RnQ2M2E3TkU4eldGREEkezhJcShjZUFK
Vj1yeXo7fThGd018TiRjSFFmUipyR2cpZVJRR3Q3cTYpRWh3MXE3TQp6I3gjZiQ5NE9vVW9qfjFw
T2ZgWUE/OVMoUypXeSQ3KX43eUErd0xMcyFOPDh7X2c0UCstck1MZTY9PSh9NjhwdncKentDR3Ih
KmdKK3hCVkB4QyFYVExQRFBiYm5Ic2xtd3QpKU1nPEt4VEQ7cF9rTEtUJiprOWxgY357JkQreUs2
PndNCnpJRThFfi1MUyYxQXFYREdTQmhsR2tad1N+cHk4SCR0dWdHJDRSaWZqPWthJmZmMTNRYCZ5
d0EtaGctTD08M3NuWAp6MGZmLW54O2M1VG1zO1JCUWdzajtaSVAqPTZkKjgkSjtlZWFKTSRjRmBq
YnlGXndgc01eeWdVZihxPXlUbzcrZWsKemkhfXp7VjU4X3o4TDU9MHhWV0t8cGtXanM1TWlLRjsr
QEFXPG07Rko1eE02I2tsaSlGTC1+SEx4bn5XQ09sI3JTCnokZGAtNiZOV1E3d0lNUXJSKXBhPTs8
VDx+X354N2IxTGRfWlZxKFcwYWVVfldwRTZ1MikwIz84OD8lMmY2ZVY5Tgp6KFZsNj1QflVxIWsh
K3tmMHdAQVItamZZZGVEaj0oPX1NKDMjV0FnNm5tPkt1UE0jbGxpRU1hZTJwPHkxKDBOQ3AKelFy
ZlI/PlFvV3p6d31wczgoOytucVk4Z31fRkd1aWIxZU9aSlRvKGB7S01NRWBPKjVQWGlHUDRzUHxl
QzVoYCYrCnorMWZmczJJRk5iUSk+YU4yIW0wRE9Ybj0pPDBxV1hQXm15Uk5VPUZMJFBKSShMbj10
Jjh6TztuX3pAOWBRUlI+cQp6clk0STY2YClTTDdleWlWTkBvelY+V3VVOHM+SSZZVmd2cl9zciVX
VUEwJXlxWTQ3d000RFVVcXNGRkJAYj14KCUKektsPj5feXs8dDRCWmk/JG5VNXwkb3p1SCNGPGRG
cmtxVVd1X2piTyZ7eik9bnJlVl4lbFpBKi1qJD5seXNNYyVMCnpUP2VMUTNKez49ViYtUSVfezhF
ZkNgTSVya2l6Z2tvX21Cc3JBIzBWNlFORWppYylnWGx2UUMoJHo4VCQkajFAYQp6RUlOZ0cqPih6
WE1Bb0t3ViZFbSNZPFZGbSNYNz1BZStAeTFUI1RDe040TT9AQVZBczIleFRUP3teT1RZaVh1PTUK
enQ+cXMjSzB+ZnRBU0xEcWJeUnRyUmpJaENOZlZEI2ZYU2JNajBwTC0hWD9LWSYhVEo+ZypZTkRo
V19GUktpVHBFCnpDUCpGOGpeOUx4QnZ3R1IqN0xjM1VPLVVxRVB6KWZaMzM/N1U0cnUtUmkhbHVg
MVFfQnlmRDAlbVpNTXMwR3hVdgp6Pz97PHwkKkxVfkZXWHdYX3F0KDNEN2M3fEo3QDVROE03KEdp
VE83T2NXbUU/SSlgYkg5Q19WUWw0empMQUhTeyYKekFQOG1leE0wPml4PjZ5TGF8OXZgUiFaRXJk
bUNjeTV1NW1WQn04UEBCRyF9b0RTIyU8UEFIWilBMlMhe2VLSC0wCnpXa1lVfGJAQFI7Sk1+cEZR
O0V+JHA0NCo7PnxZVHlpQjNTVz07TjUzWTJ+eno5IWhaeHMpV1l5XmlWJHxRSGc5Uwp6alhSMUpL
dkE2Y1NUamlqVkZLQ0slPnN4QkNGZU15dCY3PnxSd35ZY0NXYFV3Jj5yeE96YXl6MGN3Z1UxYTls
bVcKenpPVHQzUXBlSmNaWmdKRiY8WCZ+ZClEV05LcE1Neng/WHJaT3ArJXdrITxUKzZlXnNVP0Ur
MTxYYz9kISQ4ME8rCnpzfHMrbUJtNEMmczBWZFowMGphZyV4aF4mKHc/ZGFoSnVTMnRkIXM9JF45
UDtmZz84eEBUIzwhZlNLdEd2Rz1HWgp6Q29laDJoPkl7SDRZNDAjcytzSVcrPDVBJDBCTExLdSZH
ZkMwRStYRHZpRno8RDM1OWc+S2dedHJ6bGlOZFhvbW0KemtnPnRPRGoxKEEjP2MpNlBmWElLO3Fi
cmY2eElWTWlwM0NBOVVVfjt4QHsxd3NoUiZ+Nys3c1lQYEFeS085VXlDCnp3bURHOHpKS0VFRDRx
YkopZFdmNEJPTFghZkItVUM3STZhRSktTXNuejc/O1U1OyM+ZCM/bF55QjtDb0gpU0oyfQp6Zktw
OGJ0RVVqaClwQl5uZHIhdCNXYD56K1NhQGAhUTFfeWN5NnBAUzVzSjwrOTkxd1gpbX1ZSDNTb1hy
SX4qaz8KelU8WEk1alZVSzVEPnxpNHBwaiVMY3ozeW9tOHVVPTRGeWxrY0c3ZUo2WTZhTj5nb2VU
PmUqN3ZWS2ZRPDFjO3BECnpsKHJkSVltZHJHcHNAJV4tQHwkKWdYXkF1VHtralIlPmdOKk5oV1lm
WWJVZVB0d2lkTllDRGtoRTNVNmQ+USlyMAp6Q0BCJXY8XzlSY0NeQGt6VyQmMEJ3czItZzUzekZ4
SGZLSWNQezBfZSlBbz5rKU5OO3dTMCFhRUZCRkVAUlZvbVcKekcqd2l1cXtNTEhqNSNuVmBMRjRO
SEhrUnRDO29iNzB1QDNyeWlfam9SQmtXbllPQENjaWdDbistRShNOVd2Q3BiCnoofHx5QXs7eDBs
RTVJYkhvZDZaQHhwIWJFUnQ0YEJLYEZZSkJgdXd0LSErP3hpO3VjI0t1SmN3c247Z2FHMVMlTAp6
UD0kPUt7QVRZQzJCSCN5MndHaGJ2TGFrSGAtSjNtXn1NSkNBJnt3Z0xTSjFLekB1Y1c8QHUzODl2
UndBaT9NazEKejckNnN3ZEUxT1JvWUt9cT1fcy1TTkBEdTBuVlJpemI+QUs/MnFvfE0kP2k+OTcr
bzJSeXdZaHlLNmN5Xnltdj45CnpBMFItKzI2ZWdqaHV7UUd7XmBBWCtIQW5qYD9zPWdXU0VSMyZZ
JVRgcUI4RzI9NkZ0UHBHb20zdW1XQ3t0Ty1icwp6d3Z3JkMzZS1JanEoSTZUYzIpfGtlcldAKENj
eWNgM2RISlp2bmY4P2Qpa3pAUE1LXyFxJX5lb0Rub2UrQmNDYSQKeiNQcTZVWk5Md0FaRDNPfE40
alBPUjJZaU5Uc0M3S0AwQHUmZ304en0wPEN9e05zQktDK28rKFU7cVgqbE9XamMqCnpaN2lFaGRI
IUw/VEMmRkNZS3ViKFcjP0djZG5VOFBSd357ZlE1IX1ERDY0MDdrZkE0KXEySEMwWGxSUEE9S3V3
JAp6KkRUfnpYfTJNXz57YCNgeGprZWhpM2tLSkk+Ji1ebWNOKlA3TG5GfSRMd1VIQjtDPUBaa0Be
Y1hrQGdaXmkoKjIKelB8cmxyeEk7Q1cxQmNeP3xGLTRIKGVyRTdBc21SeFRyczFVUGFTKFFnKHcq
JSg7YjZRQC1Zeys5bXtUQ1ZYdiFACnohcW9NP2tKb31KLUhxVz89P3FmKlZzSG9GK3FzU3xuQFhC
T0RwKzdKdUpDN2JQVVcobTE/MSFELThqbDM2bnc8Xwp6Kjw8SnFHQ1dvcXBqQ24/LXdyP0pjZUxn
WmVyPy1SSmQpby15OXRQV3ZUQFdgUn0yNjl7NVNCWGpebjFTNT9GKjAKekE4fnI3bnslX3JhN1RV
enExM3htQFdmMVRIfHVNVTZlU1IkO0ExfHM9QEFDd0dOQms7KWdQIyskQk9XYzxJbXl6CnpfU3Ni
Pm1fRX0lUDUzOGdJPVFsSUs1S0hARFhHSmZlRUtRMXw0ZDx7JGd6ajNUN2pudmdNNTBeQk4mcDVW
Tyg8eAp6eSgyVzFaIUtFRStxJmtHa0lSP18tJU1XWHpjYjxeJlRRJUNCaSQhKFRZZnVSO3NSOzBi
Iz9wPnJVRElQUGgoWk8KemZ7PWU3K1FGQiRLMkEkQGFVYHpwQX07d0RnWWZrUVp7JFBBb0poZXth
TWVZbU0jRUcrYCt8M0BZQDV3VFhQbSVvCnpgNWluXzl3T1RTXlpyO0dNZ2J0UDFsPlclNUI2OzJo
VjQoI0IwO3M1RmxpbzlAczZeMGUwbEVhezYrNl9HUjg5RQp6QkNJcnFIQXFJaVB9Q1RVQGMhLXZU
LUNYTmU7TUErMUVvRSpISkk/QjBVc0xXUkdERXp6U3FCanFJY1lRKy1iPlUKeipuSU1vNFRteGlt
JGBEcjAjMGVeOy0oIT5iQU42KGZpYXx3dF41OVpzUDUpTGh9MDl8STVGKHQlRmJUcXJkcyZICnom
P1gpKDQ8dmJ4MWB8RnNtPDZjZU5HIXBSX0hOPyhFc3JxYlZwPmY9TVNYUCNrKzMlXnZtbmchY01J
T2dtKiQrIwp6dFc8YFB4SSRjPTdWMlJXWTlycEU2bnNwRk8+dCVDZF9GYUUzN3N+QC13KGRYQmp0
Z3IqPjZsNV9QSyR2RCYwMloKelNIcnV3cmdBQGpLSWFUaFp8UCNkbUdONWJJcHx7KWM8K25feXMz
UV9LaTwyRXBBSyFLemYhfilMc3w/KjRzWHx1CnorR3RtbGl1JSFNPm4rKXRvUyZWXmFYfH51Uikr
Y1VASyQha0MwZktiT3lqRlZjeThkIWhZTTNkdFYqWDEqaWc9Swp6P1p5WkE8ZzYzdj56PEVDJEBf
VHBicHZza3RQU3xZdFItQzVISUYtb2NrcWtoOWpxX3NAIW4mXjVMVDY7X1IocjgKemFqO0orKSRj
VzE7IXpeP3FnR340cytGQF54Pj8+YmdKWGpYTWVuI0h6a14/bj80cUtjbVdEST8yZzxoTGUxUCNk
CnpSYXp2I3A/cjFjKTcrY2UlX25EXyRrS0VOQlIpPWkwfSYkY0RRYVNkfEVPbW5tdnpxTCQ+SVJO
JkZ8KlA7dm1+OQp6MXhpKD1zY3BiOCFpMz51RWtoQTJJUUJKZjQyQHhTcylaQjdjMjNRN3VePz12
LTZUJm5kNyslKyZYSFhfUn5hVFAKendpQGErbEpGO3s7U35VcWshT0hUOH1pJGNlamVYNno8YXZw
YWI7STgkRUkyK2MkWHwxa3RCfGFhWip3QWhVXlReCnpadFk+blNKK2VAO2V9RjtiPiRxfXFhdTZi
R0k8ey1qK15TSnVuYTtWTE1XRDJZdzVCZnZ3e3JzUW15b2NTIVVZfAp6RXloLXhVTU1AXzYyQnwt
XkkmbGdDSDFzUSgoODlSMnBeYDIwPkhrNlFKWUR1IVQ7SF9rKUlGbTxrSFNMeXNpQ00Kej1Bfk1S
QEQjblAmaVA2dV9FcUgoUEU1RDZHfUQxc0N+Q316aV47aXx5cEplKFBveTVMekJWTz43R3I0PE9E
S2lfCnpnQk1LLVNFfD9YUWU1S0UoZnwoP19jR3VyV1U4OzlFYHFOeWVzezFvanQ0TD9qLSteXkJT
PG1pQkVIa1ZmaTs4TQp6STUqcUYlQz1jNyY5dXtRMTdjTjU+V0RsPGN1Rm9BbTlAX25pbEhZK0dt
fl47QH5jK0JzYTc5RHBad258I054cTIKekwxUSptM09yVUM7RjxDO0xvT24xJXhIclAqVSkhdlYo
KUhMMG0za0pmVUR+ankrJiUqQVB9SnxOS3c/N2U7ZU07Cnpvdz1STjRfaTRpKTZIb3VvZzUhIz45
aUBiMWdLM09HNEU3flFDIylrSEVVNzNGKyE1UjdsRGNATHExfCNSQTZsLQp6JmtMMHRKRTlUfVBi
aH0wbk9eMztOPnI2S0ZoJjZ1Rko0PmBCTCQjKU4tcGEpUCpWaHAmezF7OXdwMHFORTlkIz8KekBL
KEJQJGVkSVFeSFF4RzdpNT9qcS1pJCs4M19uUEZ4N0FfUWNxYnUxc15seUJLRWlueVBfZ0g7fVd+
I0dRJlE/CnpYfGxJNTZvWChWdjdoSXBwQDR7eSF0JitJJWU1YTBxeH1paCZZUm8mX3xWfGNzVXFU
TyY/TTAtQXUhcj1GdmdGRAp6Wk9QV0ZXUFZSbz1YRnpjfDkjYWVqNT5yPnVpcn1JNVpZd2w/dFll
SDhzYiZlYmFyKDt3UlBMKFdnX0FMMn1tQDwKejFWUH5EJkYkUnxvSndRNjBTODRQYW4+WDs8JD4o
fmE4IT5IZG5GPj9AOXpZYGg+I0lPWkdFWWhETnZaK3FFQXFPCnpBaDBgdkFhRW9EK31FWjY8R2ww
ZkYjV3Q+LWxqKUY8MzhPZHo9O0BOWHFxXkpNfShrWDRpeWFQRiFQKnE0eXA+VQp6JiYoQHl3NntO
TXRVKjs5VlIzQ3pJb0tOY2slKzJfdjQoN1crd2FIeit5SmElbD9QYWBYdSpUMlIxbUFgKWErRGoK
ekdGaG1xKzh+dlI3Y1hBO0s9UHdSPTNfXj9zSCZZZVhhNFU4MV9uPHZYOEptVU8lQXwkdWVRNnBg
Xmx9X0ghWkleCnpgM24wQipvc0twKGI0ZlVZWW90X0UwfDRRSiEtOT90RTJzQVJxdWIpIWpEd3w1
M3VCPCNzND08aHQ3THYkMzgpJQp6YDg5cE55bXZOQ2hpPnNuaSs/bSQpXk9tUzh4c1Y5cEVJWlRT
TiokcFVzeUYyT0BDbHw8NWJubW9IX0haP0tgJTwKekhJOEckN3pHJFYkNGVaP14hRTF0Wjh7OSlO
UWVmSGNEej4hISUqZmdTbnhNLTlLKk9sS1QpYDZSRnd0dTd2OV55Cnp5Wjx+ZmBfQ0NvcldIPVQr
R0NFSGBQKz9+VXdtYDUzK2FCby05JW8jaD1AUD1sJS0kSFdITlo/c1pKJFJTSUZLeAp6VWR5NTBj
YH0pZG9feSpfVSN3MiYyTXFYXk9aWnIwajV+NGgod256Iy1GQl8yIyFSRXlmaEdYTkFgPGtAbnx0
JXgKemI8YmJ0eXwreFQrV1ReR3pXM2duJndUYmpmNDtNYGJEajQtcGN4aVVDJXBHUT08TXVWX3Z6
MnhfeXpDJWV2YVEqCnpVUVBrRGszUEJYeTZjOVBFbmp8aFRVKWtWJV4mTWorcUxITE4oYnRrQmlx
KG1LSTY8fkFHKz9rdEFfZ01kKWE1UAp6eWkoNUowYEE7JSZpJikoKX4+eSFSNGg0VGo1Jm5BWWNl
JmNfdWdrUjhHRip3Q0Qre2w7UWltSEQjTXJpZ0k3eFIKekl2e3hQO1JuOGQhdG8wfm1yaUdfX2tK
e3UqcmNJUUA0WmlfR2pgRiE8M0lvNExsMW5QI0JWIWptRGl6OzxpSHBjCnpwSy08O0tEJStfaFFC
VHJpJiRmdkhwOWIpSyleWmdaNj1kcDtsZjNxZjh2UXB8R01oOCNmUns+aGx+e3d3Xz9UbAp6KlF7
TjtfUysqUEJXViRkTVdoKVdPZCpRSz5OVXRfdipqZ0FtUiRHMTFIWmtjeHwofVBeX3tPfndhPSsp
YVIyQEgKei1MaGlFKiUkVG5eZ0poRzBgSSpaPmRCZk1SLUVAPDFyeUFlRzJ7NmFFNiU7PntgPkV7
TU85elg/MnFOdUY4OVdPCnp6NVZ2dkBCN1FZe1BYakFkKl4rLUNEUzZfdEpTMmxxWFV7cnFlKmt7
Zmg0PTwpdkltRXZgQkM3eWw+eGQhKyR5Tgp6X1M8aX1rN1VrJk1ZQkphKlhxcSV6IV90Qj5zI054
YV8jZmEtWihmb3lzfWEkQ2w3QC01PzNEd1VNbzdTcU9hcVcKek0rKm5zcXBKQVRkI2B+QWdraFNf
dTh3PF9FSURiX3VZWX4jVTVRX1FhQnUoUmNzPGduYndQMXFuQndmUyZ3Sk9fCnomNn08dCZnQ3d5
UjRTJkxIJFglakF9YWVVTHNKVlRyWiYjMjwldWVfPk1VejVWSGojaFhVOHcrJjcxIX1BQTBDXwp6
S2FIWFk2MlpVYiRuMDxrVilPIW5SS1VkLVVBbGJaIyZ1VD80aTNHZVI0U2J3TVhgMHhxM1d3IWxi
YUZiIUFVbHkKemgjMEszcSo4JilXWVNNe2IjP3UwIVF3P2Z7PykoVkBue3J7VEtVJkI+aTBqfTti
VDhkUjhAS1J5UlNOVikyOCszCno8Wn03NSVIYDVZYVUzMSVvUykmblomaHVzRXNSQmsqY2VsPSo2
YTt9KVhzRHxeSVMocWB5PXpgRk00UnJudHlzJAp6TH4we3YpYmJ2ZF5CI15qOEhjR0pxaVFPV242
TX57JjNDQERDYzk8SkA2IVZWbTFZaU00QmckSz4rTX0ke0BCT2YKekpyVj9nX3VoP2Y8YDUpPm9I
cmlVSEpRbnJpKShYIUV6PEJiN25CWl8rOH1+YFImYFM1JlUhbXpQM1B+PnNHRm5vClp7e2k9SWRA
SF5eS3F2cUowMDJvdlBESExrVjFtRUIyKGJWRgoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZm
IC0tZ2l0IGEvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzI1NngyNTYvYXBwcy9lY2xpcHNlLnBuZyBi
L2FwcC9yZXMvaWNvbnMvaGljb2xvci8yNTZ4MjU2L2FwcHMvZWNsaXBzZS5wbmcKbmV3IGZpbGUg
bW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MC4uYTEzNWM1NGUxNDllYWE5MGI2MTBhNjljOGY5YmY2ZGViMDZjMGU2NwpHSVQgYmluYXJ5IHBh
dGNoCmxpdGVyYWwgMTU4MjUKemNtWDlfV21zRUgoKz0ocU1UQCg7eUY+OSgrQCpNTjRVaXgkNCNu
TEk2ZmZAWCNpNipueUljNzN5eCpUQkMpYnxjCnoqX25IMFhHYkQ1KUQkcEtObCphKjBFVXZIdFFH
KE8xTntqREt0X2FxOE0qIWIzSUs/dURhbEd7YCgmTVVfK31YXgp6Xz9FbkQmazE+LTdgSXVDcSE1
bG93WFkyR0JkIXB3SVAjbUY2NGZFI0I2NWQxO2ltbjtBZCYlZENhUW52ckdARUAKenFlYlRsbF5u
eVI8VDhzVWJjfC1KUEdCMnBWPVptQ15MdWJGVGk+OEtTVCpfZXQjYS03OUMmaGRVe0paeldhdXJs
Cno7b05hSVp8RUV9dn4lU25OKipfflZATEgqTUl5KmY5d3ZOUE1GTU0qT3R1dXFtLWhfZUEzaD53
OTx+JSt1SEZ1eAp6UHt3MSg0Y1FtbyFpRDdVQEkzcjdsJmIwJGQlJHNWPH5KPlk0Z1dnb0MreVk3
M3UmVXplPHlkPyE7Vlh9Ylp3cHwKel5NNmRMUGl6QHlKVXsxX1NGaUJJU1VKa35QRTEqSTZFOTNw
PDVjUmA2KGohWlJVc08zNl4mb3o4KTt6dFp5cnUwCno0RCQoT0RjT0glSVAzaTkwenApPCtsPzBp
Q3gmUj4tc2pmSnowUV5jbHZ9akxzfC1xNiVYTF5qP0olQyN4fkA4OQp6KkdET2FEPjg8c3g5RCFD
UzI4QmFsYDFrMzVMWlVoQk9+QHdrYDM/a2JoSnBYJXVEQkF6Vj8xYyVXMXh4aTR5NEEKelZ7PX5t
NyVEWH49eWg3bmAzb21sJVUmKDUkNTg7X2k2PkIrKzJTakV0TCVgfkBIODJDVH57dHAwbEtBbzN3
UyVnCnojS08hckY0ZmpteGJwKiY0SmBAfDNpVStEJGpXfk1BUD13ZCppVUxvPUY4KmZDeX0oKzYt
XnRNMlpKZSprJEtXQgp6I0IqMnZQMHV9UE90JEJFbVEpSnVSSCtCdkN1WWBqNXhDT3l7QkErbi1L
Uyt2WWFtPjg8TzJeWFVJM0RHMVclVVYKejU1KytCX29YRVE5bVVRRUlpSGpWdyR0WWYqem58Vjxf
KE4/VnNyKCtEK2hrX1MySnR1KVJ7Y31NWVVgLWZyVlV2Cnohd2E0I3V8eml+TipNaW07JmdUdkgp
aEVEOSpkX2d4SFNaTkAmPnUqXjB6WG9RTVIxKCo2fWoldDtrT00pVWlzawp6cnwhN3RMUk57ci07
UUhYeWQ3NXtLZW8yRV9+emB0JFozWXd2RSNJOXNXSXtLRUFnekRCJGwpZ0lpUmMyYXY/YkoKem5p
S3NULSM8SihfNGs8R3Jqcm5VRktCcHdFLWAoYjRKKF9vLT83MXs4JDxwWXI4a0lURHFETDJUeklL
a3tTKX1zCnpfVlJHclFmdEl+VkJmJjNicDIoQ2l7ezFBN21fbkN1U2tQeyEpM3Q0b3pEN25GWVZN
NWpMPytoYzBJRTNjPlZ0SAp6QWZjbD9IIzs7KkxYKEM4WWFnbCp1REVhUHtRaD5yfDg0T1coa1RY
SFhIRmdNY05OdlNfNH1HekhzbWZqbUBiNzQKenpsKDxPZmk+O25CdkdnR2BLMjBrTGg9NUVYJH4x
aHpVblJBZiohLW5Ea3BkSDtIaVVqIXxseTdQN0k+Wj02eDNFCnpUQl9ZRSNHdVNsTFBXUkA2bV5l
P3crbyYoWGxROFFhXylKM25hXj9eZTFBUndKPyhxNT5+WWk1YjZRNjlyc0pqewp6V153JmM0fHZA
bmRfNS1naFF3dkJHP3xKU3YySkpLUldAdVkwTSpeTXZmT1BlSiVLPXhzOG5gSCskV0JmK3U3V3cK
em81Xj4yVzk2KVArZjdeMj8mMDRZKVcqJn1jUEEzQngzbFZSUzV3XylSSSElUjF8a1ZoQGs2cn1m
KEkzLSE1V15QCnotZH1XYnsjPHxCY3BRbT9SNEEwZmU1RTgyJXN9TWlKX2crZVA7e1FeZFA5eW15
dzRZWHleNkc/PzV2WnVBfSghMgp6Knx4NyNYaUIkYmB5PXJaQ2xCPU5lV3BWUVAySH0tLWR+Knwk
TlVhKS0qe2M+KFlwYVV2YzA0eEZGKWVHMXpPQXcKekF3NDZ4JT9wKGArYElkJG1zM3YmKzBecUp1
ZFVzRVJ1a0ooP3xTUklmVFV8TlFfcWNnTkNYdmZQMG9ZZ28rZCRvCnpXNjJ5SHVmUkMqK2U0ZkMp
MXklbyFPRGk3c0V5ZkgjPnhpUSZGQU41WlkrdTBPUGVhY2stZXI+d14yNDAjZVJ2aQp6PWQ1cDYj
TkYkISk5Tk4zQyFwN1pnKGx8PEZ9X0dAaURSSlgzdn1JNzZyUWdtR2p5Y1lLNmZrfHR+WjM9SXRr
TykKejcwcmFAZW04S1BpI2RaOUpSakVHRkxiPnhtaVo8bF53IWMmZlRCNDhGNTRBNCVkQzMhRXxi
ZXFeUE1qJj9+aXZOCnpfanhyI0g4V3YhTnRuT3pMQkpLI2phTzZoKktzKHwlRWtzXlo8PWlHJmB2
ciZQRUJ9UGpfPUt9T3x7czIhMjV5Nwp6IyZickBqLTVWTG5td0ViN2AxT3wmRjJpYDAoMSVTMWNg
QlNnNjlxSlpGNHN0ZEB4bShjWTduO1RnJSVGQ3hqbT0KekJwPyU1b2UjUjJfXktAXkQlSl43Rnc1
fFI5WT1ReVVDd0s3QyFNQGd4IzFLWGZwR19VTih9fGNeV1hBNztJTWhJCnoqSGklJFZCYnAhckF6
ZE1ubiVBJTVzYTs2YmlmSVFiS3BXTjY4WkI8UGYlYjxPd0tXPVpedz9WbzxFfX0yPEJuKQp6P0Y5
MTdDZVZJbEpWLVJrJF9vaFQ/TDVmNzJ6KDI5c0M+RVo/Z3F+K0tkJCthUHNTSjQmKWJgc05zX2wt
XmwpX2oKekh2JiNzUmUjX1ZocVBOJlZDQCRTYUNZY2g+KmEjP2BwcTRydnJ+b1M5KFY7NXtUd281
RnVUeWk7NjlvQztRdit9Cno3alBgeXoyMns/UF9hUW5QPlElfT83aH0tK1NQUi0pM3k1Q2kmaWV6
Wn1URlNXMCNqLVkwVlA1XnFTNUFJa01JQAp6X01HRjd7cDB3azJ4WWprWSVoemMrbW07MDtCeyR2
cDx1MUQtNDVFYlNrOTNvNipXSUh0YjRCIyF8VSNXX3VEbXcKei1Pe0NiSDlEQ1JhPXdiJERuQG5O
SjxYKVZgfEk0QEAwezNJbFVNU3xUU35fNzVlMk9RVFRnNyZvbSZ8VzUqRT59CnpXSWQ5QiY0X3Qw
NTdTdElrRl95eiZkO19qK0hROGYpbGgrY3QpRmt6V15SY2c2JG0oMGhkaXBZQmRuXjFtRzFTcQp6
I3R5bX5XXilLVjFkRXZaSykmPDl5VkF4OGlJR29FT1g3flJuYnZHaXc9SnhfWGNoZ18qYnhjNGJf
bmkhRWN0PkIKemV+d1dkYyY2WmV6VXVqZHpAfWstNUQ1WihMNThVKSt1ZHRuQkhOfllpPzh9NjlB
I3xDJCZvWlU3LT44fGNBM05fCno3dCtyI0ZNanVMbVYjQjZTKl4kK2tVWnwta2MhcUpXS1ZmTz5+
OG4tYGBLclRtdyE9O0kmaGR1dnRlWTdRSHFaQAp6aDlLWFkmMkJTc0cwMVRCMTVsSkZMYCEpRGBW
Nl94LVNEYWxDdiVlcEYtbipMVVE5dm4jP0ZnMWxASDBUX3pXMGcKenVhXzVCVj8/T2QrbCpjIWpk
entMWVp2fHhDKlRXTDxoNCp0ZXBwLUg+b0pNQCVSJm1LNF5mWjk4JDBQQVo3WWxQCnokaUJYWCNR
RHEweTN1fFAzVyolVThVWEJtNm84IUgwbG5fQkZBX28/e1RwKEpjdGtrb2clK0FoRjYxdSFaJHpx
Uwp6UkJfMTB1KmpvZmM7KCt1aShAanlISkRSaDUxfnRRKlV4SilDO016aUZvO3U5PnRvS3FWLTVt
JXlJPEN5YSYqeWUKekE5NjEkQGN1VzlLZXxyc2BRPj9gXkNKN2c3YTs8TU9rKUdkNX0rbktXPVlF
NS1lJHlKN0BhZCtIenJDeCswUiZMCnorK3lfZz9GWXNNWnV9dDN1YWBZWnNGMHNiYjBNIThveUtq
fDtYNmNvcjJhbWxiK2B6XnY2bEN6Pmo0OSV7YFhOTwp6dUdwSTBGc1UjTl5RKWVkVmdmMTNkI3VY
KFM2Znt9SmNnUSMpfXV2az1kbz1VZnJUXkFueXhRY3U9SVFZbjQpZmQKemhuMG1LVSZ6VnY5ckZt
em4pdiZ7KXRGOV9ecWY2a3F3fnRXdSsxNF5sMighU0M/MlohJTtufis5cGNzNzE/WVd3CnpZYipi
QUhYZ3tMZFdoI2BkUDBicG9aUkZsTmFENUlmTjFWSTZmNVZIUjNJXypVMHRsXj5EYSFnRUo8ZkpQ
JVY5RQp6TjYwTm5yX3JGWXRSIWRrbTg2Skk7TnFZTGp8M2RmbX5iaTRXd1ZnO1gtODE0NC1ffVZ2
IWJiNyR7NHY9PWwpUE0KenV9bjZpeWRMX1RKcH5ZZEo1cHg+fEloITM+S291bT0jYCo9SytoLW12
I2RnMUJoajB2K18hQ0pxUGJnZnRnT1J7CnpPeV5GMDd9NGs5SzkxNF9gK1ZoUD49KSRqb3BlJmhx
Tk1XcTw4LThYdX1mVSYmfis5NXZNM2FFeFZOX2hjfUA2UAp6NTYqbjMoKG9KTSZrPilWaClsdkdW
dE50ZWFsT1lDSGdnSUpkTmVrQypqb3drNj9JMX5OQHw/djdVY0J0QXsjKVUKekFBd1YwSzZNN1l0
VkVTMUFLVGxvSnpoZkw8LXE4YG1hT2J+KlZLN2VgOGBxMG1JQlYhPmMjbmVheiVIcCgyckY3Cnoy
P2BqY0Imfm1pMjFDXnNrOVNIKDh4SkApdmRMaTdKbTwtKCM2bV9iIz1aVihmUkNzPCMmPDNETlE7
Z18/OyltYwp6anhAQEkrLTdffHNUTHo0X0VeXjhkO3laJUY7Uj48M1dzTkVTWlhFeS0mWTR4dWRt
YD1tU2VkJmBxNyg/Ui1PJDsKeiF0OGNPYnImLTkreUZ2RXN2QGw7cTY3Yns0SUBkV1dXNj5tJTMh
PTZ7VX49I2htWjRnNDljWDEofVFgKihzdHZyCno0YVVeTDtoUn05UylWeyphKTNmVTFCWWxYIz4j
MUJVeilUJUpzWU19PUZ3bkUlR203eW90dH1wMERAd04zNl9jZgp6YFModzx7a25oJlkyMlEydEVM
cD4zRT1gaz5jJFYyPXUkKXA8OW1uND1meCMkaUIoblghcGtDdT1aQVRQbGArIWQKej5XMXRKezlg
eytkaSR8d0hqTHdGM0skRUZEeihhVmg/ckF8bUAjPW9qalVYM2UrQzc/K31+bnBSTyp4fWFHQ29F
CnpEdHoqWk1PMD5AcXQtNSlFN0JDPlJ4WSlvQ0JqMmZ4aihZclZMYmw4a2FzQnB1ISt7Wl9gLX1h
TzZQaiNteExeaQp6RVE5KFRtVndNJmJUcE5IdWkxSzNGbVE+aEJDUUxJJjtwQ2I8TGsjUWJQYXB3
bWl9OS0kZUB5MmdTbj19JFNUal4KelNHQTVjWFczYEdQYXBIRTI8WHZBWjBiRE5eO0h5eGwmcEEm
UyVaLVU0O1ZqdVREQDYkWCtGc1RCS0w3LW9BNmZRCnpnRjQxQWxXLVhwMTx6c0tCPChIfnFJdGpg
e1doYnxjVDA9UT5ePUZmc0dISUcqaCV4MCh2RUMlZWpoY2JycT9IcQp6Nzs9Vj5jWFp0NUJnKnlh
dTY8KGRGMEF3JENHKmVDbiZJRXooOGIlNVJZZS16NUFGI1VuezV+fSE9OUo0JGdCKmwKeilBOXtz
VEkqeWRhN0R0UiR2RGUjbzJEfX5OVHU9MnFLaD5jcilLOT0peDhESzRraXk0X2VQb0slRipaaz8k
U29kCnpvN1dIOFgzSH0kXlQ5aEtAYE88JHlPTWNWbnw2dCNDNlNPZ2JERzJkRFF5eXtwWVZFUT5L
QEJXbDRlTmA/PSVgQAp6Tj9UWU9LKE5Va3wxPkVZNntUan1jT3swVmhpISF0WD87bGchelJ+ZT0t
ejN5Xjl8dkE8cTA8S3s+O3F5b3hPMmsKel5qYCUrTyYqX1o7PX5Ab0c3JmxxJXVlRj44MkoyZnZq
SDUxbCl2NDh3JihsSjNPRihZQipyNC1WNmF3WSN2fGckCno0UTlSNHc/UzslODJPT3ZoKDJPVHgr
aylnPjZIfnl3T2NSPjI0eXNMT2sjS0QhP1lZcmpGdnt9TGgxYThocXVSTgp6IW1RZDMwWX5mNClO
RUomQUA0fkItTzlkTHZDSEF2ezxpeCt6TFZfVlItVnpKez9LMnNIeFp2SVFDVGFSRFUhczwKektp
S2VneTtXVEYwMi0+Ny0tYD9kPUpON1BsdGYmU0JSWChkJFBJITheMVJufGA2JFFAUkYoK2BMRihr
PlYofFNmCnpvWTRnK3k0VW8pO0RtNC1zJDJKIyFqTmVhb1A1M1YlYEQzfnVGKTMxdm5iIVFEQVYy
eU9QIXlrXkFVfT0xPn1aZAp6cShvbT0lcHwlRjE1JEYmZVI0IytvVURPRyRPK01aaTdRN2tNMXdi
Uml4P3QkWHxQd3ImMFNteTl+VyhWQlEjPTsKendGenVfXlNQYC1lb2hoOSZtYkFhLWpYb3xobGdx
c2srO01BbDFSeVY2ZDhIV0tOI2pSdSNfV1dPK341U0YyS3toCnoqJm5VbVA5YClPZXc5WUBhXk9n
QUJiVTZ4cHFlQVd4O0ApJFRnbGxER3Q5TlAoVnomWTtlYDI0RE8+bV9WZEJaawp6PnVpbEFmPCY8
cGo/Xi1WbmwjaShSV1hsR1h8VGBLX09vKEVDdCpfUSFVPisqLW9wWigla0YtPExHK0FaWHBuTXgK
ekpFcVRfez1ycGp4eWlfJE98QWxFPGxve0ZWeE44Uzx4eCo8dllXYSEhPjF2ZWdgMzFtXzBNSHJy
Yi1WOVAjTV5YCnp3K0BDRzx+WlJQcSszaTEzeSFUK2UjI0BqezNZIzRhLSttfWt5fFpQdzFrS2xS
cEo3NGF8MUNpSWA7M3tBMW1EUgp6M2AhbXM8JlAmRmlefENoZ0RDRkFoZj97KXlSJF9hJjc0JkQk
RUk+ZGM1RmokLTM9S3JjeCtgNl4we19IcTZMQnIKeiF2KDtGVkN0aTR5JEk/OHp3RmQoNHtpI2RH
dGMoWi1sI21DbEU/MUNmNE5LMkstUyQ1QGNaZj1FYTxLTz9iVUltCnpFP24/aDNlZ0UmP1c/SmUx
T2FhfVdpM35IMUM5Sm9FfEBAaiZKR3tBdzZEPXh7bTMkVnhGeHImeUU0X2pBRCNVTgp6JHw7ZVZC
PHx0b1Ize1RrPWg5UWhaeHBRc0s9K0Zze3MmNyNIUz0xLVIrP2Fmbzw9WXQyX0ZMbiYyUj9US2FG
bGAKekZ0ZUw/MyZTa0tIdXx+bWo+TV9wQGdtaHw7SDljOUN9KGQtMTkrQG83VSRIOWZqKmwhJHdM
SjFlO25XVEc9dWxSCnpxZ1ZNOGlebXF2JStSQj4hVzxxNyU1JkJ5Tj9IbWw0UF91cm5uZ1F8M1kt
Q3hxd3NOOyRDQzBsTlZiNDA8ZGJSUwp6OEhMcWpWX1NgKEg/Rk8hRT5Ke2I8c0xtKCZsezwwP0c4
NGJRcFMpemo5e1U1bjw3ZUNLcD9yMCNGTytodmImWWEKenJtN2swNihaKlZ5ej1MSTkzZDl9PUxG
cXJoKEtxQSVONEJoaTJ6bGNMYDA+dy02U0Y3Tzg5JT15Vkw5M2tDJXZuCno+NzA/MFVndTZCTlBL
fXR7eyopLSVWJVZzLU0kTGI+Pk8kK1ZLfUpZWENmZzYkI28oSkh4a3R5QG8xKkwxYjE4MQp6ZU5B
Z3tEXyt+dDEjS042Tk02bmQwYk1RMEt5T0RYIW1sSUR2cT5XenJONms/NyNBRz1SVGhhUS1uMFpV
bk1valMKenZjTz1mYUFXZEdMJHIhfE1SYW1VWX1US0Y5QFlBKVBhXzh8U2tBSl8pKytTQlhvZkZp
Ukl6VUlVcURpek5AWVgoCnp4U0s1cVJsWVZaMkQ7OXRkVFkxYztIZUFBUmdSYTElVXdpREFGTT9S
Uk99dWB4ZERBPzdYUGo3XjJhYGJFYHFrYQp6c09gNzctcnxFbDZBOXlBWWJMSVM5XlNJTFJ4Yl51
Mys+USYjOClMJE5hJm1mezBMNEc9NVZgQk9ZbUYpWnxCfnEKem4rO3RRd0NOWEUxRCt9MF4mJDZq
MytfdiNDSkwmb1MwQjUrNk05KnxzVCRJYz1HY0dWYykzJTVKaH54ZXZieFRACnpFUUh8YWZ0OEpo
Z2NZRTQtZTxHaVolSk4rT35SMVQyaEVgT15HIUlPWSZrZ2x1I3xMZT9gYjA8eHBldSRBNXJ4Rgp6
JGNVeHYrd1RjbmNSUnJISEc5eG11S1I5UGJ4fVJUQiROTXBnLURsVW1WQlI2b1duKVkyVGwrancm
KkMlLWwpY20KejgxeWRVWTsjcGFzSX1BeT1lPCM9KnJINUUpRWF7UmFKRHt5KGUqNG9OcX1US3hn
VXtAXjs4bGZaKHtiX3E9K1Z3CnpoSTd6YUt3UG1NaEt5UkM+QThUcCtTczRXd0JfcEl1PSZ1NCp8
MmZAOUVjdWFWTnJPNSQtUD0qaTYjSSFlc1FjJAp6djdOTiljcX5hRDlRP2lJX3gpWmFSXiFEbEQ1
Uig5TUkxZ0Z4K0JrVGc4UTxOdD9+RW9faF4mKCpRWHk9SktgdjcKej15YXcmZXRvcFFhQnRzQS02
KDkqRFB8az94dVQjO1htXn5eckU7NVpzdU13bTU8d2RAZjI7N04lRzNgUV5kUkVRCnomfiZkLUhy
V0F3SVYlanV2ant5YE5vbilgd2xecGVDPClSb0c/VUlmJTd1RSo2fXNXcyo/O2FAWjE5fXtOSyQj
Ywp6MGU4PyUpRiErS29Nb2NTPVNWcT9IZnEwYDVxS2FIbFBgOUprYmRqPlphanpUJUs7JmxpTjdU
IXM/ei08aj1SWFEKejQjMVNtIS12ejFWSWdFY3hUeCs3VEsjVD1jWHpJZzg7Rj98OUx6NmpPMHYh
NzRGTmtQUSMlQ196TjtqcmZpMFZMCnpkTG5OPWFINmFPP241KnFeOThwbnMtRkQhQXtTPCNXKll2
NXtpeH5rI2pwNz05VnlCNXFjRDc8PDc4dD11c1FSZAp6YSVhQGYxX2t4SVhSS0RvQG9aNHlDV2FZ
cXlfVUEpKnRJbTBYfiFWfT5vNmY+KlBvOS1zTyViayprVmxKRiF1cDMKeitMQT9AQnQ4TUA0K2JQ
Z0hJIzlkKHhDNiZ6fkY1SFZQb0BhYGN6PFExZmB1R3VjSiZSTzJ5RUtQYnZDZXkjUHIrCnp5M0h6
IUxeMk88OyNTOS1he1pEVDlWY3ZGWT96ZHA+fEh+cmx9ZjA+PmNfckdae1NeRytxUD5lR2J3Qks9
ak03ZAp6ckx1e248bDc/QER1bUVFdW87YGpRaXllPlhIdjlBYEtKakxHX0s/dkRLTj49bTA4cU58
STRxJlFNfiNMP20ka20Kel8renMzaylka0t4T35FQFM/QU5zTFNrMD8zN0owTHJJOCZOWXlFK3pM
VUZsdGtZQCFhO2pEangwWVR3JUMxfVZqCnpzZW91ZiRZITFUb0FgO3ZAalNPTTZPcXNwWlhySEo7
QVd+USYjSG5VZjgxVUVkc2JkTktDMSVYYSRRUyZwSVMhZAp6bzVQfDRmTjctTmJUfU8+QUBZRlIr
US1WNVN3JlNzc0xVRVchOHk5WEZWX0UlPEQxbk9QNTVwayF6M3BiYCYtVl8KemxtYVhPIztNb0JG
QkdOX0s5ZShRdy14SHNXRH47VEFuNVdgOGEten55dVZDVzJ2amA7Jlc7LT03MndYeks3OzReCnpW
Vm5XOVJCdFokUzJKPj5Qa283IyNkXzZyNDlsQHUzMjJuSV9fPTxNWUY8ZlVCTl5RY2tiVEEmPHNO
MTIhaHlSQgp6ajY5c0BDSXFUbkB0WG13V0Y9ZjZQMDY3JllZTFJDaG4kc1I/XzZNKEgydWxLJVlv
cENIZjFzUzVTdVpAKUhQZEEKenkkPD8oKzNRRktUQz4+fUg9QElyWGV9Q3NaQiVKXztgQEpwe1VK
NUxzWS1EeFVPZHo/KkJGaD1fJTRDOWhDc2t1CnpxWCZHUnJ1S0gpPWVHVHVvSC1sS1NlamQrRD55
K1VDLWRQMmV1PVRkSHNBPEM7Q1BxNTJCWEV2PypZdz4pOWZQfgp6azZYSkQ8IStvcFRAQ004dFE8
RztDXnNrY2BQdTAlcz0lTk1FPlMrLT8kbGc4MSl8Vy1TKFVuY3s0Yjw5aCZfclAKejNvNXluTEE8
TDhJTithRlooKVZQc2pNYkZjU0R1TUx+flFva3JZWl5pRj07aXwxSD0hTHJJSmBtVHVXQmhOTkoq
CnpWOCN9a2h4NjhlJjFNSGMzRChTYnMxbmJ0O05OTXdoe2JzeSVvbTRUOVZ3dU1Pb2MmSUJkSlI8
VC1md3hyeE9zVAp6XnpNTzYzNntRMzM2QEwpY1VEVXJtR15pRikmKkg4azMlS28pKFVwdihIQzNg
e3soVURgUiFXPmY+TCteNEFTelgKej52aGo2KHY+eXIqLVIrTiFRbnNXVTx7UklVYl96WCY3dnZa
R1A0STglP31KdCtga0ZJRElVTWtuQUJicHZGcTFvCnpTIWs9WEshfUw5dklTQTR4KnV7amhUVWMw
Y0t6b31LYmQ3MG9eUGo9VkxBJUlWZEZNfFBFYm00a0x4cTRzVVc9QQp6UDt9PyU/N2ZTJiFCb0Ri
LT9EYFNHc1lTbS0rYXFvMUVYUmo/UyQ2PktlKzhCPkBYXkxzdWI+WDFmPFVrd2YzUyoKekVNMXt2
SilGXiFKfD1BRk5hY3FRO0R+JSQ8UEQyQFRtdiZEak5ONEl3ZUIlWVhBe3IlRDlCVTVESCRHdDB3
NT9CCnpxfi09a1l9V3YzdERXPmZUIW9tRm1SMTR7Py1hVHhlaVA1SnRBRT0qeU9iIURPZkxrKHcm
VSZ0UWh8K2NMYS1aYQp6Tz93KSZBKXlaT2xPMSUtRmEmdT8jclIpKi0+d3F7WWRTSjVATURWb05N
N0V1M3dhV0ViVlZBYzQ5VnsrSX1QdjsKeiRaOHJ3PXxoRWJhNHdVPHpmUFchaTdsSj0pOV9+OWNM
JD9pWTBiTTNzY29LKT9ycEgrUX5ufFgybDRkTGMhdlBaCno1KGQyaGUydTEqb2ZZOTB2en4tX1JT
QXFNMkw3WEErcklnMFBWWTBuQVdDRWRkaTJ8OTF8Z0AjaFc+Kk1UdHVeXgp6Vm48N00hfWVmPUM0
V0RjLU5oKzI3ZyU0cyVTXkdBQzREOXdgYE8jYGkqJkx1R3ZnYT9iYkNLJlAqSEF9dn5NcDsKekN3
a0M+MXs3UU1qQER9fCh6SVBNITI1KUJBJXJjPj5RJFdFVXE1P2AydioqfDhAKWN1NV4/N0dMZHd0
dkZ7NkVBCnowQmRzVW1BZ0tpU05eOCNlJT58eFJIJmhNdmhSYT4rMEVNbCE8IU05Q0U/NzQjLXNF
b1E5TW1TOXNIQipzLVp9PAp6fE1MS2hibi1YIT52fj1fcXVGWk12djtkSmRWTXIpTSlzXyhxLWNK
MDE8enBLUiVpZGxkNmJzdXRzWTJyUWh+NWcKeipXSDNsMkdYQW9taXcxVihudm5ic3VWRSYpRT9p
N0NvYzM9I3M/Mnd3XkxvNnJ+MlU5VCNvUjJjMz82Qm5IVD5kCno9N0FVV1F9JE5gdDExJik+bnZM
I3kheztUdl5LRCFUPWh1Tj4yMlJHKGs8fVM5NnlfNHNYNzQrbjlBbmU8UUhJdAp6YCM2T0xZKnZ7
aXdJSm41MV41YiU8bThlcEpBRUs1UFFPNCZwMU5HRSZGU31qY0dSZHAjU1k+XmNwOHpeVn5QcT4K
enZhaShBZDMtQj48LUYkcSFZX3h0PVYpZHJ4fV9iR28jQV4+VmhESmBuKzs1VmZZMTgzOUBBank0
SDsye291YVp6CnorRTFVTUJwfGlDV08oeCV3OUlfdS03NGstUHM4VEAjOUx8bS02OXhKUUBFfH0x
d2FqJmFWKkQ9N0B8Y0hCUFhofQp6NUxLVzchJWYjQzB3TmJ0cUgyOXBjMldEUVlSKz41ZmhzU347
TDJwJmRkWmBiMThraDA+MkBHJiN5cF4yZEV5cHwKekpTakQja3hvY1FmOX5tSE5KaCsoMn4ocSRz
bjI5a0psQSoyYXJzI2lmYUdhdFE0N0RAYTxzIU1PcmM0aGhWMStkCnojZ2Bza2ZaeDQ1bFdmTD1V
fEtPQjtDcnZLMSVTQSsjJlEleXtBTkhTeUc7fnJGQWpVRHFSMzs0cnxKTCojPG1+ZAp6SGk4a1RK
cCMycWw0P3E9Ml9ZVWc2c3o5KVZDTWRFVDIreVZJeDRpbyRhOCZFUD1gOWdRMytTdTZtUXhEXkZu
YEoKenZwa1QkWkRYeXRIfWhWfEt7ck44YH1RVWg7IT5YanRtWmVQe3VMdllWQXAtOT9rOEh2WWFx
YHtxcT5CejllP3xYCnpSLVozMk1uNUQqJEplIzkwO1p4PTAoQzFePGloeVNvMWY0M0g5Q0h0YHFp
eTRvc3g0PmtebnVVSy1ZUSl2fDwhZgp6SjljYlBqIStVYCF0d2RsRlVXMj98QVFxbWcqfipCZzht
ejcjbC1tIW04OV42PSEhdUk/N15oTEJ5SF52Skg+LUMKekUrV1dWMl9xQDlOSFgrQE5DfHZeKTBQ
eFcwTkFjVzNIRCl9WXU2cHZXJFRlMF5jYyR5aytJeClpZChPVmRuQXBVCnpSQE93OFcqellgIXxY
SmVeeHpAbjE3fURnP2JzYjdjU21TNmRGYHFhRitsTHFMSyQwb1JWPENDYzhLJTJre3h4Ugp6TTNC
KDx2VT10NjAxYFBBJTMpLVJqITxpLV53PShhMkIqZUdgPUFeS1B7JDZwKjBZPExVZDckUVA1c0U+
NmpBNkMKem94RHZUVzcoKTZwUT1hOU9RUVpART9DOWolfVdBJV9KIWIzYzk/bFEhNGMqWERjSjl4
dTd5NzFyZDgwNGomaUt5CnptKV8zUGReUldjKz5CLUNwZnt9akQtfHVoaSVKIzc7NkhSOShWeVg2
VC1qTDt4YFJFVTd5Ql4pdXBYST1XPk89cAp6ZEtaYGNFMlhXSEteVnNmMGRsbjZ2LW85Pml+XnIp
WmE1U2ZtSDN7aXl3OTk1MjYtTCo+S1Y2antrN2ExTzYlfTYKem8tcEw8YTdDRi0+YXcjV1V9PkMp
IVheVz9pelZJSEJlO21IS2RpY0RuKUs/c1diM2VeNyliQEM+WEcmYWFNPHZMCnpfJHY8OSRNZl9Z
OT5EPHMjYWlPdWQybml1QyVxOWoqK0Y4R1pzfG1HXnwmd0Bpdlk/YzxiUV4ybmhoaUlYNVhCegp6
Nyk8Rjdra1dvOHVDKD9uKGNjM25eUWpuJUdYMVE3K2hLR29YPkdqd1RjPF9GQndFQ3heaDxiSVA3
IX4rbkk3YkkKeiNqfkJ2JihrPmtTX05BV2ZkTlJNPkdHTkBiRjVCQWt4emtyQW4xWkU8S001Q0sm
VkZ8d200dmM2K0BCZGRvWnRvCnppWGg/LTl8N1R3dyV5T0A4QjB0KnZNdyR+eE9qSzZMXmM9Y3sz
dTBNYWh5WDxXZFRvTyZlSHtlKXgtdVlMWHFKMQp6KEZ+PmgoUjVLYWlXaD9YXzkxR20oUDlUdDRP
ajchZ3pzYl40JkBYb0E2bkg7WF5aT0VGR1M4K2IjRz5xRHc/SV4KenckODt8QD5pa2Y8dzBAYHte
eHNTTFFqc3RHKGNPZiExKE1kVn1lMEtkU2A1akU8e3h2IUcrbz9XLUVTNjQxS15lCnpJeiNhXzA/
c3hNUzBRVm08dEt1ajcmczJiQWhqUSRHSyZRVkNIIVombWAyOUJMQXVTVDRFJGYoa0hORmZ7UVgk
TAp6eFc5I2xXKm1jfWZHTktpNVApZDVhYDAyal58RTQkcEdnNjxIZ00yYyQlJDR+KXphJWZORGZB
SFRAfWQ7R1kleCoKenEhenclblh7PSo/SUs4RygxVmhCI08lXzBHWDxOUyY1LXl+Y1ZTM2NET2R0
IUlUYD0qP3tBO2V1fShCLUtGQ1MyCnpNZCtZYiZTRkBOeUplbT5rZV9Hcj5iZyt4cyY9PmI3QHdC
dWF3KjVHVkV0P3Q3PG9eWTk1Pkx9VTJnR1Q9ZURxVQp6dnpMc2IwJkFrS3owTHAoeCZpUlc0UE9s
X2RxWlR9aDgrX0IhOV4ydkBzZil5M3RUUkxYRjtoflFYe3lwTjAwcFYKelh3JWpBNj5zXyQ1bnUp
YCgrZ358QXl3UUZtNHNAV2hqbGxBaj9+cUJmcUtGPVM3SDNnJThWc0h4en4xJGBxfik+Cno/aG9+
RCFgMX1rPzZnN2BTeUFOdWxueWRAWk5ANVheSzxMUjBLQGpIbzdwRUVUbFk7UUp7JmY0MElYSTAp
ez03awp6MyEtPHRLO2RXKmNRSE5YNlkjbj9YKit5QFRgPC1YRW5CLSU5ZyR4YFgqeHsrb1JxRitw
eW1teTRkWiQ2Y3ZXP3YKemZRan56QmFtMUxsVWEhenNNNlNkN1pwNDdZJHJMSmg+cUxTKyRBdlUj
QkQkaT5xM3BNKHB+LUJiZmZKWD9yNTJsCnpUNks1MiMtcz5DS3pkVT16KSZsPXB0aCF0a251cmtt
e0JIZzkwcDw1dXw1PD1AO2QqQSFLYDhSV2lIVCF2SUp2LQp6UFVRWEoxOEFwenZuKXpLYENAbEdO
eyNrZlEqeVJJY0tSRFArWShZaXNXO3NETXxjJEotfW9DRlBoPGdpQnQwZzQKekZ4fTBlZDlZQktJ
ZWsqSShDMjREeDhIfWpSUXtrPSFmcnxqUFozIWQ7aGpONW53MkMrV2RXMmx2dFJ7ZjtHXjd6Cnom
YXo1NEt+d2VQWFoqO3I3JE5iNmlNRXQlPjNAZjt5TEtlPyFRYWh1WU5QRGRfY3N6fXI0Y3oxZ1dq
OFY/M25xPAp6aUttQW1LeDB3YDIyNE1rIyNUUCQ0cmp6N2o3PDZ2cnJqeyt2Qno0UTJUM31WU3J9
QGV2cHI7RkJSZmZUY2dUcGUKejBMX3JqPW9KZ1ZoYD87PjNWM1JwQll1NXwmcj00bT8/Z19pMHl1
aTZWeXdRZFp5czZ1MXBoc3tYYiZBUSF2bU1LCnpMKCVCYFl5YjNjT0MzbC0jamRwOHtxdk51LUVa
QmtEam1lUypMP25mSlo4PXRTKkFCSj9FU2Y0T1MkaHw9TkZ4Kwp6SCFlY3hEJWFITDhRZS1EVzQ5
X1JXWkdPUntHLTNlMDVSKFh7IURpOEl7WkZLJW9ORD09VDR8MkwqfEtHRXR+TU8Kek9jVikjKTZN
RXB4NiRiclpwcUVfTkklQyZYXiVCd28kJGcpU1cwZT0ybTFBTVpWMnN4ak0wMiE4YmN3cXJ6PX1X
Cno/SlJDRzc+X05TYzJ0NkBpK3AqNjRWWTZYZ0VaMlVoWm8rM0xrITw3TnA+fj1vI0FwQkEme0FL
VlR6SE5lTEp8PAp6LTtMZigjd2szRG85MnplPUQ5V04rI3p1TDtUSG1OcCVaTTsofjZWJmx3bWIo
V2dpM1hkdmgqOTErb0J9TTVnNzwKek45X1FvP2t3bj9oeSYldVh0Xj1YR30pVzNMX1E3JiM0Pn5Y
Rl5JbFIyPFE2bXBIazhPMXdWbmZkc09oJXd0ODJ9CnpFcVlLezlxVDBpPDcmK1RfQWpjVUNoKmR5
OVN6MiElXnlgZWl5OU9iS3FJPXNqRWEqPF5IMmFBRi0tSjgjTUMkRwp6JmdyJnZWM15sKjY8aypI
dHs5JHFLezU7K0gyUHBOP1RKbnl7dVNkMz5DLVk7S1UhTVRHc1F0VEMyPHl9RGIraCgKejdxTi1M
eWRJVSE4Nlo2YVRlaSYjeTY/NXJIamI4IyFBQ3F9MyMze1N3OERwKUFCZkE8aCo2VW5VRDVBIz9p
a3R3CnpUb1NuQHglU19qeGx0PTB0XyEjTUVwUX45SzMoYXUjeFBRREYzNTtIOEMpY0txO1Y9Q19s
aj5qaGtsT3ZRQGhXYQp6WVp7MTI9KmQ9MHcxRERJJWp2KyQkYypjNShIS0o3N1BrfDcmN0txU3d7
Ul9BWSNsKHRUTVRRdTR1T1k/TG4jYTsKemUwRDd1Nz9zUDVzdipmNW81bFpuX218TEJ0MjQxY0xk
UXtPaXQlMmJZfVhlIWlRKlcreWxTIzhyJmhGPEM7SHo3CnpIKzEodS1tVFd9bkxpZl82SWFmYmM2
Vjs4cE1SMWJpUkA+XmFQIy13R2Y0UypvI1lnS01ZU0tEQUpuUVJ0b296cgp6aiFhJE5BeTh2QSh1
cEBYe2ZJI0Akfk9QMzg+diZAd1Z0JChyWUtPbj19d2NJN0lCaiMqdjViNz1QaHxYO302SE4KejQx
V08tPW9NaU10NSFTZmotQ15hY0FGNFljKytXKE1UbnBFdlR3YGptY0pIS3c8KDtOek9zOWZZSio7
YlklRGUwCnpiP1RlcWVDbjZMbz1Dakokfil9fllqPWhucT1takhlREdvYVctcjt7aD98UHdpciQ1
bm40b0tHVCNRQUNaZV8lJgp6Q3xnd2ZxaGMtTzF4TEVQKSlYJHlaWlpRVTR4aSk+MkY3JT9GPSE+
c1lzeUpfK3RtaEAtVzJMbkJWJHImTF8oUzsKejxqJkJaeyQzSCpRVndmKmk4SHdIUEI5KkQrYitP
M3A5JHM2KX4hSiYrLSRzN2xUUTk7S1ghWV5tJC0xWmR5IzFxCnpUMD9KXk0yJE5YbVROaytsVDVX
LS1AfjV9NDImP0hwfEVHZyFkdypRdStOPjtqcUNicCQmSH1RZUApTEJMeU9YdAp6TXhNQkxjQjho
TDxqNjI3T0JibFVvSEZ0OUNLUShsNGZOdVlOdm59SURpRFoydUQrY3tJXyVhezwqMitgTGFKdHUK
engtPEw8SHczb152aD5wcVJMd0dgODJ7cWRROUpIRD59UGxYe1MlWHw4RHNkUGlROX4oX3J2OztI
PlZIV0I5PX1sCnpDZj1vPF4tbkNadUdxLUJQKTVoK3d9fTRTKXpuKlRBfV9BZEkpcU5RUnxLUV5u
anxlRmdgZj8yUTNUJWdwPDNDagp6X19PXjdLUSR9WXBPJVkqeyQwKDxQT2J5aDQ7MWtLI2tOP2J5
fExZWnRfJjIqd1YwV2FCNUpeNEhDbzh2TGRAKXMKejc0Mj9RYSZQZ2pFP1loVlMzT3M4NTx5c0Ep
Rj0oUyhiNDZVPnkoXml7T0o1K3ZKSC1KZG4zT082OWJWVjFpJkdiCnpBTSNnMVVwLXQlTEQjKTlq
Q0FtYV4lMkFVK2teQDl6ZXdhaGhSSGw4VDk7aDRTV1p3b3F0bHNrZGckP0BgYiF1Mgp6VDBYY010
QCl6PWx5IzZge0FMe3hAWUNOP3g4d2l9an0jYj1sej4qVFYpWnpec2lTZkUtUCM3blJASGNCTEp9
QU8Kekk/YjFmKnsyQ3s/UWdoPXdmM3dePFp1SzxkayU+MHMoe3RKQCVgdmFHYGx+aXF+VVJZWV9E
PGBWKEVxRHN8b0xaCnpoKzZTIT05aVI4UGRVOCtIOXNQNlYqZiFscnIhO0Y8RzU1WG9ZITx1c28t
QXBjLVZ3RztqOXU9QlhYaWQzOyYlfQp6JmJuMjU0fXtzRmE9KDlsYFl1a3NOSH1uYW5+VWU7YCt+
ZDljUmAhLVVDNz58aFQ3bHo1ck1xKTR0UGFAMnhWISEKekpuZCFPbVdsWX4+KVkpQkFGNDFWTmdN
RXw8YHZ2Z25iZFdJaio8eD0yI1p9am5TLUomaDQxP31XIUkhIyFxPEFVCnpQPGJvdWwoYXFiQW55
czBjJkpnRHtvVkZrYyZJNj9AbFU+WighYFRrU2Zse0J1YmJOQT14NXVmSHMxJkxFXkJ3cwp6RzxI
MVBxT2ZRY2BvTigwVihKZT5aYUR3cGEpWjFuTU1BR1dxYUJsUiQ9MiRoIXh4V01ITGE5MTRMZyYk
bnJNbCUKenVFO00tWUxVM3tVb3ltOGB2dDtzUlBoM3JxdXgyTTVNOSNyTGU9blVPTklOUGsleSpM
e1oqd0AlJGxQSUdtOSZSCnp7VjhPcGR8TWpjTkQwMDYkWkIjQk8hYms4VEJ3RnNyNDJrWUxFc2sp
MyFJNmAkcGZyfD5peSlpKEhUYDs5MGNuewp6QmJNdiY5LUVfPmErNm51O2FeSktefjRqeTw4PlVh
dHcmYmdNaDk/eylqTXhkSXlXZyNMejt2TllxNEchPFNkWUIKekNnfXRnVFVJLWE8IzIqQGUoe0Q9
bTh4VC16ZkNWV0l8NDsoTzhUfEB6djxRUmBUY0lAV0BkZldNIWExMFVvM1FOCnpNRT0wYDtvPW54
R3h4M1NpTER3ZTJneDhPNUFxKXZhJEEhcmJ8TDhAMnJmbyQ+JlRmOCNILTReNHk8RTFtU0o4aQp6
TTUhMGUhc0V9TE9MdkVFSkpWdjIoZ2UpdSE8IyQzeiltPTJQS3BmfXprYj9xN2QxTChOSio9fUx7
OTJlb3ZRR3QKem5yN1R9TUo5K3FuYWF2SytvZn1nNjY5Tm1LeEFndTdhd08pUmJxWVRzP1lZRTMq
PVZEaSN9VDNVN35tYSNsM1FHCno7PjVTTiM5RW5iPGltWUMwdEYzfiVsUHxAbHZZNjNfIUNwSkp4
SjghYkpjZ0tQMzBSfXUkd0A7SEU8VD9xcSpXdwp6JmlaaCopOG4qaXhTRWBUP0A7XnFYTkNDME07
X2E3NktyWjZpeUN+N1psTmIlQlIjIXRyRjJaI3FTOXQ3UkF8c04KejRfI2VPRT5OXlIrc1NvaTk3
JXBkV0hLSVZic313JVRYflJ1WWp0KSpDTUNLPl9IKDs0ND9kPlNKe1Y7b2B7UTI0CnojYjc3VmBV
WUVNQVBJSkg9SDgmKl8hYkJjZjl3LV5AXm1HZnsxKnd2V3xzTlF0SVdraDZILSZxZ3pSYTxyQ2hA
fQp6P0NNdlE+Myk1cU40Xmo5SkVDeCg4c041IVpUPSlAaHZjMilqWi00Um85Uml5YHglLWl2djZG
dFUhe0olJGopcG8KenNuMnwxSDV6RjdQUj19YG1DRHI7Z3dvR0pPezJ0P0VNQn44QT17KDBnc0M+
fT1eOE5VeEB4KlUtWjhLeXN6cSQzCnpZbE9mNnVaK2hTcXFKZj9pWE5TNGA1LUo5c3UheHJZUVdV
MEB9dGh9Vl47Y3cjaDFvSiUjWVluOFUoNUdeMSlKZwp6JTtSO01Ackl1fE0yJEhUR3swSlhzPHlG
KlgwYjRNaXtaMkJjZW1VbUN8MGlsVTkpdztxKEdmbyR9eD80Klg4c1MKenIyJmI/eXgtPFRVdXUl
Rj0qb0ZIRjcqQ2RmQmR3Rl5UcEApemUmcUU4MWliJlRDcDtYMX07Zl5MPXNnayZ7VWVBCnppWDVP
KTl6dkdBRVFrdml7ZkZ9QlQqaX1CTl4mfkMrSnNqUF5OTCMyTlM/O090ZkVzMys4OWp5cEk9fT8q
dFpGYgp6S0NUKXJzVCF7aUtYO309WmxRN2c0RDV1eD9xSWR2ZEM+OT1kSzE+Z3VJZiRmNG5nKVBe
aS1sRkcqYE11UT14fWsKejBXdDlERl5hO0I7cTVlTVNsVXV0PHJaKiVJUUEjYlFJblIzaDxAZ3tf
TllgZUg3YURySlYrUSZzS2lKN3UyWjxaCnoxYE9MP0xgRTJ0aCNPcWNObXd8VCQlJSsqbS1XVzNX
bzMwU1N7JUd1OypVaV4hYEI5RE1HaH1uKXZFKDxfKT11Kgp6bHN8ak5acGAxaURFSmJKNmZnQHAl
X0xAcyZPJlh1VTlxZFpNaFdIO2BJa3FGMyZjU0ZmMWBJfEx2QihsdXhgcWwKendPaypGZ15LO0R1
TFBGa1Z8R3loUWFEa1pqNXc1NW9LVSYhd0BZSnZhbTlCVXlaPTNnY0VgUTQhQE4/IS1MXnYjCno7
MktqfipTe1N1SDs3RHB8SXZacXgwT3d5bHo5QGgjKmJod2s0JHRpYG8wM25wPjRfYD13fnFIQ3A4
QSYydEJmUgp6eWZUWn49bm08S1UoPjxWQ0ZuSlJ7TXVwN2I/czMkMT1KKkI3OCF5NmFzIzE+QXEw
fFhOJjFnOzZ3RDdkRjRrWnUKemxBQWskMm5ZQ24he3ktR3NQTEpPcCp2e2QzRHhyQlcpKkBucko7
LSMyflM9bEwwWFgmR2cpYjhXfWEwSnlOWSFnCnpnMnh1YndLeVVDMS02IWQqXjYxWkphSD1BV3Nl
cmcwMHdyXyQ+RHN9N3ppSnlAQDFDbWlBUkomazdsZkJNX01Bewp6MT8/eGU/TFV2YTh3O099bCEx
d2Nie2VTOG5KJkolY1pBQyVCeDc4PHp4Xik8dHd7ND9JdDNHYXhpVWl6UmMlLUsKeiZQLWh8X1B5
WG4xZ0klNXFtXzBGZVkxeHVxYiV+d3FHI0h4WH59Ml43al5gdGd7eiVJMT8/X0JEPDtPTFV7UGhS
Cnp1aGYofnlAOHFSYGh3a0NeODFmRTNFQDR8e3wyLT82Q2s1VUpqdjc1Iz0/REFHb1U2fnU5TmIm
Um53IUw1dUJ9KQp6YyQqOE1SdXZQSj03bih7UGhSRWtyMUY8JEV4RGUxZmwhOy1UcHhmIyp1WWB0
VE1VNG5qazJYdiQoKkgrM3tsd0gKeiUhKj52IT1hMXUhKiVoJXBJNCpkRyhoNCgkaG9VZihDc183
TEdLQXNySzx9djsmM1R8cTQlNU5VZD1LI21kP3g0CnpoY0RPKEVuVTRBWXFASGV6Y3hAWF4wWilW
SnZ5JWBDT29FX0ZWVGRiaDtxc1plSnYpakgkRT0qTGReakNIXmJyNQp6N0J5KHtrPWQ5JVlMP2NG
K0w1cEhRUUA1OHZvfmshR04zVEdUemJAJnFpPTlXPCsrWFNWLU44UyZrTisrQUhnST4KelVTPV9K
UlUkWDg2OTxfSnNBODZpa051Mi1OP3VJSClsbj9lPTl1X3EtTjFuZHVYN3JZTF40MEdWdW8yNmIw
biooCno8aUt1PEdxezMjSHp9VyRPTT5Faj98eGhEMUNyM2hndHZSM0lYUSMxJFJSSGtnN3QzXmgw
c2tHOFhOQGZgNj5wJgp6Y1N0TUlOWkpPRV99YHptRSZURyY5PDVSe1FiRyFuKFZVMFdJbn5MRmRL
NnpqMmMpZ0pJPz13ej53YUJ6emYkM2UKeklhRGNVTEBxIWYpUEAjPk9pWllpUSt+Xmp2OEBZXnBD
KilSIV44PFNjOCNJSGFAdykhPndzZHR5elhQZ2gkcXhzCnpeZHhYOW0+fVVONE1yQksyfT13Vy1G
UElwWjRJV2U2KFUqRW5aR35VbnAtaTBxd3lyN3Q2cT9sJjFMaUozKXEhLQp6NjA9PkM1MDAmSyUy
UiNsbllxa3BFTD1tQzZFKiNRP1FldVZeTUdNdiVFSFdqRSlsMlo4bVE7I2lSNFNhXkltXy0KekRJ
OHAhNjRaezJSdnQ1KGwzejdtOSR6YjMhPmBYRHZKenhwOEFMR2BgUDRgRHNaVWdsVWdtY353dEsj
c0ZqMVRRCnp3d2UtMlJmdCs1NVNFd1BwWFFld0FjayZhN2cqRDU2O19CMD1OanxUSDVwM0JuUUpu
ZVc7JT9hZGRqbjZANWA8Ygp6a3xpfDskMUFiNEIkSmJlPilyOSh2QDh+cDRTPX40cGtNYkBaayZq
UlF+Mn1FNz05dEZeOFVQZXRNKnFNdWZaPmsKel40OH1UZyEpQXpfTnU4OWU+akl7RVYqeXRpVHlr
akdjZ2tzckFUWjRWKmkjdSU8PUVfdzVlZmRUQiFeI1YmJF43CnpWT21hOyh6V1Q5aHUjKXxqQGpt
ZnBEQ0VeYlZCVzFIM097QClwcXRqYEZ3PmwyO3U3S2p3RTJRPVBiS0lPc3NfYwp6Q3ZBeTFKS1po
UFUxMyZAQTtaWiUhezEzN15eMy14RSpsa0QlQVFSQXMyKjBNQz5nWGY+Tyg1T0woNF9UNTxFfnUK
ekg+dzFxdjIlYiZnRjUoRGZwdVgrU0NCLUY5MU4ydUpQaWplWmlDVjAmeTFOQXpOcyomQiR5WG9U
SHpDfDMrZD1QCnohVEJ1N2ZaJVdNS1R9UDBJd0V+dFFgOXFaZmcoPjJkYTI7fD42IUdDZylpYzVr
KipSKjlFc05YOGU/OTdFVUJQcgp6d1N3d28qZjZzZ0A5clklOV58XmNgbC0tVDtQVFl6MnNwWUYp
eXstJSRAfGdDJCM2I3lRR1F1N21VOWJWUWcoT2AKemJyTU5SNT9gKjwqJGkqSFhibCF3bT1rNzYx
PTJGbyVBamZtZmNAaWdeKlIqN2lFcWc0VjN9bCFhX09gRyE2TiZSCno1PyNPRGM1ODRqMDRRT2JK
OGk2MC1uXmdUejtEZitLRW9AYTFUQ3pMdkV0c2tiVEUweTgwUmNJdDJ5Tjxpd2Y2TAp6anRJd0I2
TTNvXlg+d2ZoVkBDfmhyYUhlR3FhKH1IV3RHXjZWMn16SjYocDdNKXtFVXN5QFUkfmZIQ3wydGpe
OGUKentOeUxXPylyVWxIT0FDJFM5eEB2ey04bmhnRnkwdkVpbGJyVGkyQ3JjMj47VW1fQVZ8aXtl
Y3pyektSLWdGZXc1Cnoodz43ZkxqWG9gX3JYSmJmaX10RGc2ayY1RSsmbEZiLWxNcSZRNzI7dWNy
IUdnNHZeY182TDw2aHdUMz0mcGJyNgp6eWFxaFlzK3FWU3FfQTtoRFFNfEBFNTFeS21ialBwUF5T
P0x2QXYpRDcrVURrWDhNdzgzJkJkMTE7bUktVnlGRUwKensqSEV6Ky11ZzBVSH5vVTM8d1gwSH00
S2NLKVhQT3tjTUA9QnRiQDU9VWxuN2A9JEs3PDBuVkJgP2RsbyZJV1RjCnppfDR6dmwkeWp7SiV4
VlRgfEJHZDV9MSVKTnF0dDUpeE4oQCp5eU5WbX49ZkYxU040V0dGLUBPQVd9aVYoRmhjOwp6Um5g
dj0xZHlDb0d5TWlFNk1iJktFbExkcDltS0JsSFRiUExxaElAYzwpVzc2UHFhUiZySVgrc09qMU5W
UnE2eDcKeiNxTGlDdkEzS2lUK314LSZCXnZ9PmNXWlVFSmNRZytjfEooYkZ7dElVZUpkMW9hVGxR
UGI3eVF4PSN3ZHpobndICnpjTiltUCtKbTlSJFRpQUxiJClZWTZrP1p+Wnd0a3JAODIqTmskNz8h
bCRxTjBaK1NZRz1qVlNrJXBVK21iTShVLQp6YmViOShUJGhoKns4Z0UoZ14mWCV3QmFSajRYaFJf
Z2w7Qm1hKChhUnt3fX5uJVpELTAodnBYJlUmbz17QTh3XnUKeldqWDdoZWpMZVZaai10QkVXZnww
JVBUN2A2SGg5NkxwKUpgQ1E5IWNgUEQ/dT5OJUstPmB4aFBCdkx7TVlHSllDCnpQbWRmWCtIYU9A
YT5YZThAaSh1PWE5UGJfQj85Klg7XislT1kjcn1sTTMrQXxQeEFPMFZraGwmVH5xN3BMM1FHJgp6
bXIodGs3b01BNUA2b3IoeXxHYSlXc2EhQXZUciFva2dKZkIlPnx4RTF6enFKazVATk49PGdLKjsl
by03YCQ/Un0KeiRgVzxuYzd3dEtVc2AhQEt2T0ZaU1ZEIT5Ocyo+a2t1MmhDWWlxe3d3NVhUUjtR
ITxwPCtra0l0dypacU9fXj9oCnpHN3x5Q0ZeNkNscndOa09DY0UjNWJ1UT5LS1RLU3dRb0NZKSpA
eTdiQ3pjJTVXbiMlbCs8OExjQVp6bU5kY3FWRQp6Q204IStjcWchUUEoUkNvI1dAbEB0RG44X3pm
Vjd5bC0pfCZweEx9NDw0ZDMrbGRCZW1HJU41c2BrV1JpbXVeaXYKemUtc1UpUz5BO2dEKjkyP3lu
VCV8bU1LdDhVRkJOdzN0SUd5OFpKMjA/aEI+SCptS3x8U3hZQTcxPyFJUnFZfUwtCno2MUB2WSpY
dipQXzRqVkxUJjg0WTlmdmMjVkRkQGNvdmI9MUMjVV9fbn45Znk5TiU3K1klR0M/YEpmT1FFYFZJ
RQp6STtINlFZcn1pMS1PaiRsd3FUPCYoQHFGWG9RPCRYY3NORkljWkltYFQtLSgxZCo/fSM3RVls
fUVqaE9XeDNqdWgKemljWi0qQT9XRz08VDYlVUxARV4+ZXEkNWlEPl5HI3p7V00yIW5TaHpveH1m
cEVsbGZAaGdjel8qJlc8QEpNKmNqCnpZZD1HYERffHNIQW1BdilkXyNWOUMqMj9gSlomSX5AV0Q3
Pit5VjRaUiRqRnsyeV8yVGYmVGYrY3VCST5gSSQ1NQp6OzNVeE4xUWNqOW5JbzF6QDVjPTQ4aytx
Wj9qSE1lYjE9bHd3UWNTRXgtWmI+YCQ+MzsrX2hkVDhGbyR6eVY7Py0KejwyPjdZJjM4ZmY8Pmg3
Q0twP2lAIUFDU0tPel99V05sOTF+dmAyPm0rOT5rP3A7fTlqcHdxbjlqe0Y+LTJKVSROCnpRWFIw
LUB2IXpIQGI+bSo1c2wqPzEwSGYwNm0rT09LMDRBUXRteFE7bFlrdD5MRmkrNTJKd04pKy1JTX5n
anBvTgp6bjsld25KfDkxPDExQUdPdmtNIzVfNDheJF9ZUUY2bFItKnlNLX1kXkJfI147Um1Md0hm
eks1MGtmUHRAZUVkJTsKej19RTtqcVBrJHotdExiMzQyTy1VJSNHSzVYWVkma0xgey0lalpVQGg5
VSo5UWZYKTc3dTQmaDFGeHZWe0E/VXFGCnpxSlIyZDZoJCF1RkpicTlXKERYbjFvWk5wdFpVLWdt
cTdRKWl6VWdGOGsoRjBod0ledEw3KHI5VG45JEt5PjRNUwp6K2w3UHZfQ2poQDRwdnc3OW1YWnpX
KjAhMCNSNns9YjNeMjkrZ0ZzeEc0MiFGRVo7P1FJJmNvTXBuQGc/cDRPMDcKemNSX3dFX31ecjF2
PTExRlJFezFpKDh5SDdjJU1gQHZBLS0xaUM9azdpciQ8JEw9RTUkK0pjNnxoWX5qezhkXkkjCnp2
WGZjai1uU1VVdWlfc315d15OQUkxeEA+ayt5QndyaWx+cUtKfUpZYFIpQSY+ZXJvc2ZCO3tIM0h3
VUU/Tm40VAp6d3M3ZXpjUXFDI0tSLVd2aHhzZj5pPXAkfDI7b2U/K3ZuTnwmfU5DdD9HelgtODJy
JXIoMkBGallTWjt0P3FtcEAKeldZU2YodCgrQnVlO2YlYVg7QzZ6cG9YI3ZeJDhZPUlBaVo0WW1T
JThoMGM1THVJTEAyKnh1bztnO15uY1VldTdSCnphRjM0SEo+NVh0KitFcyU+Y1lhdCpHaHVRaFEy
MUU4KHg3NGdZc1pYP1ZKNihCOzlPfThQaGVkbSZ4fU1FJkhGLQp6Q1Y+aTBNNTQ+P0U+dnEwY31Y
UGdKRnpQZ2NrQGpoUHUyeyVacjUxQ1pOZGEqUz8pMUlLQkQ4SD9qIW9mdCEtX0YKeis1WHBNNmtT
KD8wPilra1loQk8lTHw1dmNpYjBeVS1CbG5oJHVRd3tKSCZJcl8raHYmJmZqR3ljMEtoJjZySFJR
Cno0ZlBieXRFZ0JgcFBYVzdiO0VwRldvMys5KVExaUNkbSk/bXItIWNoNGlIUH5DP3tNWU1ESl9K
QU5oM3Y0dktVMAp6bWcrKF49KE9oSGU3KW1rK29ERjFZJCUyLU5JS3VZY1p6NCEmUy1SN1I+Y2hj
P0NneHk9Kzk8VnFQb34hYE5xcS0KemNQR3pSKGhKU1o2Wkp0eSsqIXI+JiQ4VWswVmc2PXs8cVUl
OHl5WXtJVl8pd0VJTV97eDNXbU47MUhDKkY1RW9TCnpHb3MzcDZuSWJBUipxUUopO0FIQk1TV212
enBJfkJkbW5zJT4pTG83TiF3e0h1RnJXX09tbCtPcU9HIXBhY2QjVgp6ZWNmZUhaQFpoJS1UMzJx
KCYhTk88QSlrWT5ab3VlYihUQTBrJnojJWgtI1dzXn5rSWR1V1RtZmIlQzYkTG5UVGQKemBnZHMp
VkckN3V7WkB+cUlNZGhkaEs7QTApWHJPJUF9emJ1KCtacnhrUnw0bl8qVmU1QDZ5MygxLU8yYjt8
fF5hCno+KyQ7Zk0tRytgUThxZnYkJk1XK0xrMjZIQEZZa3lqMGt5eS14U20/KGtuVFpjdTI4e3I7
RFNYS0ZfPihHVypvZQp6NklsKmhhcXIkZDg3TD9XXis3ayY/MCRGcjhUNUtyNGNaZzhSQUN4PGli
MSFwUSt+d3crRDdzKEVmYXhyNVBRaD0KemUyMyF3QGZlQlI9V0BIVjZMTiF5aCZXbExHZ3xKQDtI
UTh1Klk2dExmUWJfcDlffDB6UXJzeGNNdkVqd1J5WiMmCnpYXj09MjgkUSVya3cyNG87czduUHdZ
OE56TCFrTn5zS0heZj4hZEZDP1IxfEt4b2tmNi0jTCtkQkN6aGhIfWVkVQp6R2JMYVFLIzJAbnot
YSQrMEQ+R21ITFpFQWxzVD5Wc1dZWHIzPyt7aVN3bVl0bCprbTtUKik1dlBMXmVkIUQhaHgKejRU
dzFiKDxFclpUOUtfPnRAIVgjQW5aYE1DOyFlUzRNczs2e09kX0ohXllpK1FJMFBFbit3U0sjV35j
PSVLQzg1CnpufSUwRkY+MXNPdThIT2cyez1acSpNWE9rdGtsNSpwRlpFNilPQj1wbkImVnFufTNY
fUdoM2NwI2J5PWhFJE5WOQp6MzRpMXApPjxqbWU7djt0KEhROzg8NFFJfU9VSnhweVBMRDBiVH5B
X0R5PX4rVGBTMFdvIzhKUFomT0I7WTRyZ28Kei1YbndhMEtROUwreWFtfEVqWnt7b0V2Nj8keFV5
NSUwVVYzZyNRMUE9dm5tRmNSbHtVITRLI3cyR0NZKmZSZGI9CktZP1pXR0BjI2tiY2BCUiQKCmxp
dGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvaWNvbnMvaGljb2xvci81
MTJ4NTEyL2FwcHMvZWNsaXBzZS5wbmcgYi9hcHAvcmVzL2ljb25zL2hpY29sb3IvNTEyeDUxMi9h
cHBzL2VjbGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmVkNjhkNzEzYTgyNzVmNGVjZmE5NjYxNzQ4OTQx
YTkwYzBmOTQwZDcKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDIzODkwCnpjbVhWMTF5b2VlX2tY
KH0tUUJVJmlYZXp8JDBDUnpwcDs0fS1RQmAyQWV8ekooeEhIO3EpNH08Zip7PWBDRFBLZAp6fEth
PWxwUikodmQyaTt2bzFjNTwmYiVte2ApWl5fT2hnYV9rPXw4REolQXVNeFAoSWxjO01lWi17RGdU
R0dWLW4KelFxdUZ5KnFyZShmM2pTUXgza0tePk5HTEI3bnxBMHNWTDYqeEFBKGVCQygqTG1GR0xm
K159Q0ZiKGpZbCFMUXEjCno/c2RJU2otUHNNKG1QOCpsPzEpREIkd0hKWlJORTc9YDZ5cmk7Tkh6
QWxHYlFeIT9Zej8hJlYrbllva3JvREojNwp6JGpHOUskZ3JDamFJdSNGMU9KTlB3OyYyaU5fYEdJ
MiFZNVdgVVdZWVA8cGAoNUUjSHVmZGYlZT5SeCpXYVVjLUkKemlYOyNVZ2AkbzgtPXc+TSNzZFQt
ajV1ayEzejRYWU9TO1hVJnMmazRAc25na01uMT9UJnd2en1rQmlBTj1GVUZDCno3MUBxXjUwPnhZ
O3daWF9LKkZSbGo0KlgoM0ZqfHp5UU9AT0E2R2xNOUc7eHI+RU9DbUQpOWFPQlZGVFNncDl0dgp6
bXRDNGN7c3g3b1J3KjgyRzhSYD9HQ18zd0lJOytyRm9ifjtSfHlZTnFKZjclQ052I0Vwez9fO3hi
eD9iY0xTM0sKeiQ2ZFpZQHxWNW9HcXR1Vz13dWBHY3YjJFQ/PkU2QVpwZ1E/U0M0QjlSbjhEUT04
RCgmO0tEZCVCK3RkTHQ1SkxuCnpMWEY0MCF8XmtsND99fG9sNj9pbGJxJGlPXj55dU9efX52aEl5
QUl0MTxMeVJ3ck9OcWBuaCZZZFYtOUAyZCQtYgp6V0tDVkRXUFQrSTR1WU9tNih0JUAwdF87ZUxY
fFNGNzFFX0s3aVFweSMjMnYlO29TfGY2bUJ0M3U4WU85TlN9QiUKemAjXnRsZHwrVnNjcmMyTzYr
Nmg3ZVdFRm1xe0tuU0EtPHpPZ30jPlRLbXdpYyFPT0BwZXl9JGtXJGlDMCRvYm9ECnpeaztnNjFo
QFAha199MmsrXkRMXnorQCE4T3RlQilrZmBlQjZxNXt+XnJsSmhhSmEjWE1CQmo2UjswflZSN3Bm
Kgp6aE9XfWokeEd7P2NqZmlxNFNEbz4yWVl7fSV2Z2RZTUk+MVUxSG9QLWo2Kj5hYSlkdEpGZjgl
QlR0XjM/ZUsrRFcKeilnc3orck9KSnVKd351ZWE4blV9dnZBfEtXR3YzM3NXVjA3ZUcqWnAoITln
PGdZTEVfRlNWdzFyTS1DaXNNS0htCno/QHYwdkgyQUhMMzg4JlBLUnBXSzRwcWVNOEhEJDg7JGZ6
NTtnc1EmJT59TXpKflIrOGFmPmJPXjNmRWZOfmhRVQp6X0c4ZU5YNGk8TkxjayszRTBSQitnRnlK
THJ0cCY9V2t2JFI9PmwjYVhEV3NfLUl7T3R2YCZ3ZSlHdmdgTDJXcE4KenpRTnhHP355PGdSYDdZ
cXltfGt0T3JmQXotOUp4cz5HblQkUVNzfF5haCFCPDIofD4zQTwxNDxseFBNclN+JEowCnolOzxC
T2t6bTspIVNvRWFxZV9wSnBYa0hSYlFmY3cxQTxeS29KWnxZcTctRzFfR3ZzbW8zSHNWMlc7VEZ1
XkF2fAp6RDxDZEs3bG9qVDskWEEhPHcwbks0TytoRnZrbzF4NCgrcF5uJX1MI2RNckxGbG4rYD9G
PzNjSEEkWlh1Z35SdzEKelFxTntvKVNuc15BSXElMWAyOXhrTnAmX2U1dVA/LWdtU3A2V0dwSSNH
Ykl3cXtLTlhUcWQycHBjZkVEeClhekpnCnppOT9zX15CcHhJKEZCKCo5MTJfcyU2RE5mNGxpK05n
ant4fjx1YHFIJj16ckU7Tnx8fVYzNzxCNWY+R2lNfVJ6fgp6WmFoSDxebF5sIXpNVSs2V15sdEAx
ez04ZXdvdGF0Y1h6UTVmfiZfOTRaeG0zbEVRRWRLUXk5SHZ4fFJ3P24mTD4KelV5Mz17UHAoTDBt
QCszKSNBY0o0YWB9fkleMVEzMGQ5e3BhSyp+a2NCTSlvMjt+fSVARGpHJEZCcWREVz0wam9WCnp4
ZDtyP3pJX3puKztBQkZ1LWI5KnhnVX14aTxKbkVrfU9RPlo5LSZHM3JoRkpoXyNCQjdjQzNmKzF9
bFUxK3R6JAp6YWdPOSUlOGt3ZTdpQiUwXyY2PDFxKE9eNUteeDQ1dGN8RGJWc29VfExoPG8mbHUo
RzUlNDJzPnM1QTQqMl8xY3QKellZe1V8WnMrZiFuKE1HVzxnIWxYTXlEOzUhR1hgOVZAWjV5dGgm
aTw8ZCVjSGFpOXY0Q1RubmVUVFBUbig5O0JrCnpAYE9HYStfMjlPRTFURzQqTG93bEZoK2lITGFx
JkNBYzJjd1ZDTGt2cGAqU3JeIUFSPSsjYFB2QnV4aEc4dTw+agp6MDtPJmc2QTReaktZbj9pVVo3
I35ZeGRrQjheb1R9ZygmaFJmcUorUWIhLT1OWUpCSFFnVSFZPkxtVHlGJXxDXzAKeitaVTlfUjhn
byQ9MDFgLU9QPlpFaVhBU2BDVnJhdWMzR0wjSjh+cns8PlpsPEp5P2gzKnBDJEpZYmpoX2VtMnx1
Cnp5TE1fWCV1c2dpNmVuWF40Vyh5fHRFQXxxQzA2ez0wWVIhb048TXFJcE00cUJufHomQmVNP058
Q0JHUS0ySiRVIQp6VWE4fFVZXlhrdTQ/PiRPSF93clc7VipDXl8jS2tDYjM0fmpUM1JGaERtSCFS
bXlQNy1mQWtAX3E4NlU7OC1mcjQKemxwJjtXPG9eQlFYeGhXYyNeO0Q5JFNrez9GYklXOD45RFZB
VGxaZVNTLTI1WllFcG05WE9rVXg9blZ6dzRhfncqCnpYck5mPVB0KW8wanM4cDlpJk9TJVhFOz9z
JkRyZjIwTVJ1bGFFQiF3PH5ebGszYm5GTkwkTjFJK3U1KnpJM2g7VQp6cUdVK3RWczs5Kz4rakpp
PVJhSFBDKG04OWd+dEJ5QXJNZkgxITt8KGJJdFR0N3V0MC0hNmkhcDltSmR6THklSkMKelA3ZEtn
dnJuNCNGUnI7WEFGS29kKFBFb1I2UzdhRUI1aVMlRDhQRmJKbkpTYFNaezRsWDNxcDFKeURPeE9X
dz9hCnpGUzlAYm5WRmUhRzBsNWI0d0YrO15rQEc1SmtBP0BoJj02UVJnVmB3OVBrNCpIbEpRX3Ez
aDw+Si15K2A/PD18YAp6dSQrfC1YYSV2JHY3PyF6a01kQDdGUGx1K157TzBJU1NUczJVYmRRSng7
QipKRHlANEs5ZV9YQ15lZHBMZHRGfkMKeik/Un1zRi1LfjElfnJEeExkfT12WDQkMTNiRWB0MFN8
SVUtME94WThvIUx9bF4lfEI0YXpBMnE7aXwxU3BBaFlICnpDeFdPanJ9cT8mLVY7a1dQNUs3N18j
fWo+VCV1NlBnejBeRiltX3g9R0h6fDsqZ1o3YjRfQT43USgrYHBVPH05OQp6UiNzTjdlPjZNcXto
WE87VnojeGw2Xj07bEk4I0JQdUpKUFI0M0NjSG1FPk5NbFZne0pzLS1nZlhPTipMKkUqRXgKejZS
KFo+JW13PEteVXkhdnQqLWFweW1Zcnc8NGFjbjYyJjJJdG8+YT5vdDRhX24pdm8jWWN7RU1VJmUq
TER2emFuCnpjKSQpVHg/REJHTip6PTtVbW1ENSV7SGw9b31USX5tUFNOSU1rakwrMEdWOTxqTTtC
Q29vKk5rKWF8czlBe1Rtcwp6LT9LcFdUZVRZe1FyZyhGeDdkUmR8TWFzOSs1bE82MWZuOztfeiVC
dFc3VElIbGpGQlNDTyRKPj48QjswKX0pOFUKenUkSTc4cnxMZXh0QFlLKj42cjxXcERJVUdsKUNh
MHRZcDNwNGd2UzJIczlUQSFzYjdqeUViNkJtaTluRDhySEhPCnolSXFTKUlGZjFfU1d7UihNSF9g
OEc5a2FKSC1PJDtHT012YGBTRz4/ejZKIUg7JGRjJCRDOUhUNUpSKWZPJFZEeAp6dndqO2gzV3VJ
dlFaPyE5bCQ1a2RCbGNte0NFX0EzdmtmPTR7QzFrPzZPQ2A9YTN9dlZnfGFPNyZHd3BTR0JYezQK
ekpAaX5iaWtabllgRCpxM3djTmlNaGhgNH1OSVRhLVRJVzMjV1VTRCVqdnBjOTd0b199SE5yXjFW
OWcodElTXkVDCnpMfj9iYmRkXyZTQEpVbV5jViVjeGRDWmVUZ0E8WjtJVTk3XkgrI1BPVWFkfjEt
ZUxTYUR6YSN0VFNjKk9YfmZWcAp6PXkjWElnKmduZSQjcG10P089bjd3fUNQemdmM1Q0KWNtRkVP
O2A/cl5GRWBFPUBeKEFkM2RvR0JaT1ZnM2ZPdX0Kem17VF8oN01TI200RW9CSzxAQFp7THV9QSMh
aTxURFk1I3hZPjchNXNHY3ltKmg4NDFXa0lUe0w3RFVtJDlXQnBECnpwI3VHbjIzNkQ4e1dHPmRv
MTNoQzdnd3o0eS0/dmllJT5mWmUha2JMQVlmQUdERkF1b0khdlpNbjxnRVlLUlFibgp6bDNZRVhe
WS16flRISF9oNFpqRH12bW5ieC1yIVlMRCFjYm5Pe2xjQSlKNjNydDdfVCE5UzgtSHJXKDhNa19Y
RGsKejc1K08mblFxZW4pZ0E8OHxCUjUmLWFmdHxSUXMwfkkpR2ola0JKKFdVeFQqYVhQXkJGR3I5
OFcmR3FIckt1fHxvCnp1R2h0OVpMeFdKZHp5T3BncWhWYVY1JGVpTkRWYlhqOSNmfXQ1YntGV2dD
UCpmbjhWJEBKYnxDVDB3NG9KQFhUQgp6cjt9YTV4a2Y4a3dDenZLR2VZUktPfTROMV5iTWlMUS0h
ODEoLTtLKGgmMl9jT3V0O08yJHtgZCtoO0NxSzIqP18Kekl+Y309VU1yOGAoc1hldmhSJHVmKVh4
OWRYV0xxSFI3aV9COzZkY018TXJ5OWVQVnt+JiZRcmwoZmBAbEBQWD9QCnpLaG5NeDNrP1M/RkE0
PklBNnZFOTJqOzAqLXJtbnxGNVFtb05KVmReQlNUSzBGZndSRiFWSkIxOSlFYikoS01TUgp6OWdQ
NHJhSWIlV3w2byk3I2gtMW52emFqRCZVMWAxOXlJanB7a2A8THAjOUhoJiprTHI+SnYqLURGWjw4
Q0AjKmMKenUyPUo0JjgqJUkrfV5CeTA9KiY5em44bExmSUY+VUAtbz9NWXFzaTRfVTBqZ2ZzfThY
LXVaVUpNY0F7U0gtNEpuCnpuQGVDQ0Ika3hwQWojJl88PGc5cXNpXj1xYFpHPk1wMnBKQSsyR1dh
TjJfNzg9Z0N7LXopS3VyTj1WYkM7b3FKOAp6QEI/Ty1nTS10V0B2RTMoKEhhXzw4ajRBZmV+ZXY5
JT9feUxOUVY8cUxKYlBfT1khTCFMMS0wT0hsZGF3WTdrN08Kemg/an5qPl96cTRUbEZyQXV0VEVt
Qk5qfkJNdzRIay1GQ3g0em5SUlczfnRHeDhlbVk5TXBhWilkYCpwfGUyNGYqCnopXzNrVTFvc1Fy
ZE0teF4qJlh+RGlNeD9uVDJ1TFJ0WlBMWjxQcSY1KFNJa1dGSCZ3OG8/Qzg9ZW07T21QVy1vPwp6
PDNWR2U9anU7QlVSPD1eOG5oS24oN3k3KmhQKil9SmIzPD94dWtaQjJtPHQ2biY2bXxwWGxAYlp6
Yl8xSF9rM0QKelcjeEUpK1U8Nlo0c3NoQ0okQ2M0WEtUMzclNXp5OEZtVGwrTEgyWTs1IzZrJT56
bCg0ZH1EenxSWXtubE96dzBpCnp5UDM0KlJsQDJJOzF5anlyNTlVMEUpQSFEbiFVRnRPLVMmO05D
ZHhoOXh8YHxnUmFjaEh8bjRET0l0RmdhRWpqYgp6e3BHI1ptJlV0NHREZGpkT1ByallVallmfjQz
encqN1o7MWFkfWRHTkFeSWRhUTUkendzSk99UldLNWR+UG89VkwKeiE4SlpSOGFWekpQKyNHT3ck
PlYmbF47dCZAeTdDb0gqcWkmRiYhQmpxYjJwPjVocHdkZ3RUeipDMWc8Z1hnfHxQCno7UHNGJCN1
eUx0PVZQaHliQUtkX15vI2xuTj1pIUJIfHBGV3UxTHxQc2hET2pEb25BbG9PVEtQS1B1X3MmVUk8
bwp6bXItQ0BITUc2bVJwKyhRb2JueHp4UH5kZEJKbWhXbGgmej8xcV4/UHh8Ml4zcF5SXks2ejZi
WEllckVIbjsrNzEKem5QQG5QSHNeU2c5fDRqIXpZQWJQe1B+dyVjU3grKF91THA0big3O3lsYXlo
Snt9R0tzTmNzOCNVRzR6QHE5QlZ7CnpMMnVWPl9neXBwZXo+JVhmUUIyWUp2K3dXPWxfNzZsVjIp
d0w+P0w1IzFncCs2RDRqIT0wV3FSPGVFZ2BBJCtQZQp6YjBBSVctYSN3fjFMTjhxJjdyWkRtTTA5
YjJ7SzR1TmNMPF89dFlQVTQqM3lxZk1pQ2tBcXBacVFYeiU/XlZPSGoKekNoJHJ8PS1YRjhyKyQj
Yl5LXzdmLXwyeXU+Y3tGSmFrR0QtTyR7OWtOaGAqeSFJLX1hcj4qNG8yX3Z9SlI5N2dtCnowSnwl
Y1VlY2x2UHErSWQwPUshTExxfERoYVU4e2l1YldmeV5lY3NFQWtIVkVoXz47c1VRPVAraWBMTmZk
a0dmKQp6U0tKYXJ3NXlAPWJhJnBNZiEtI2w8NTNodTVlYio9RXw8YnY2e1JNbEkyPHE2RXYjPXFs
QldLYkNtIXQhaUE1VjMKej1PNyVDd2R6V15TamVLVkNxSVcpalNzODdrOCU+aklHJl9LZSp4YyYz
bHUmVlRwKUxic1l9QW1lNnxfOGZCa0JpCnpBYj9oNndpYFMmMWVofEQpaCRgbjBuZkpWaUBURH4l
RSRqKkpzXyRtPDVkKWdXMHF6bD1BPmYyVXM2JDBFKm8lRAp6d05eLV5XYHFtO0J+NlRqJXJgYTtH
VDhga1VvRiNAQThAay1teVlAMU1SUHpUQi1rIXFfdjM3VXJQWC1pSUdWTkYKek89ckIydSteVD9U
UmRvXipYSzFtYjQtV0dhfFlueyhpOSpvLVpNM0c3bDBnaTZKRUpOWXI2KyopTiFjV3xOcGV5Cnpt
WldoO1BLflF3MT1vZk9gVVhOK2RnKjJOdzZBUXxUfmVTU1B0M0QmaFA9VUBrZGNwdUhsQl9jTypy
TnQ3YXZ7OAp6TDh0eDNAMyNVX15aOUAlWH1RdCMtYXUqNFpFXzZIT2ppI1FgbSpJSCRJckM5YkxB
OEE5blcrZnJeK3ZvbWNyeTUKenVPTT9XZD0tenkzYGlhNSlEU0VQYjlIUlZoPWshQk8tSGk8e2wz
YXN5eC1tSGV1OD1vV3Y5K2Y3MV8wZi07QkxICnp2LV5wb0UmJjtfb2gpJWhiWGQ1Qm1oNnZUbmVY
Sj9oQlZifiZBKEl5ZDA4QzBvNVVIO2tafD9wdzdrc0FgTSp+bAp6cGJYfVple345Jk9vI208Z010
LXB0enxwXllqT35QN3NKcjU7KEt5JWlpOGdHbUF6Jl9Fc1hRSyRZUnUqPWV0Xk4KelM3fSh3Jk5w
Z3BVc34wfTteTVNeNGAzVkphMm5OTSNFaz1PKjxGKyVxKjZTV2VJRjhUSmZIcVBMYEIkdGNAPCpz
CnpQfEJTZkxRTnUhY0Nxa3h3Mi10PHdSVmFYOFRKWndsTFl3NjkxT2VrLWNkc0RNNi1VPGtsKzxe
UTtGMnpafihkcwp6OzBoam1kQSlteDBDUzVlTDJEaWtgWUA8NDk+QzQrRiQoSWBZbkk1UWd6am5+
MSoxUDxSSVdOUFZmcDwwJCo1O0UKenp0JmJpIzZ0dVFxbzJ4ZTZmWjhZe3JCdVdsODhxMl5JVk52
Sn1ELSNfbyNwZ2lVbTFTdVFDc0xVNSpnSSYybzRpCnp2aERVeSpgWWBwSFB7MUU9KXUlVlc/eXZN
ZT5sPmlzSF5BcnNRTFoxPnYkTndZRFY/SXpgJVN4e2t5d1Vrd3x2MQp6bHIzZkA4fj1NNFRxPHQj
Z1UrYlcrVVFlSERQOWpqajh2X0FRSExZbWkkTDxWXn0yOWhTKHcmUFZqe0pVQ0Y3dGsKejN2alA7
QFlrMVFLXi1eUG9NMXRuQT1zUWtXREs5UDdxb2lqazUxQkZFPHhzejlUdnYwIzNEc3BCfWA9amxX
NzlJCnpiMUhGM24hUk1ee2hFeVhrez15Nzc+Q31Eck9XTjI7MT9HY1l4X3N9ck9vNilYb2NzMmZv
b2Z2c3ZIeW93b2EmSgp6NFNvRj03RWdzOTc/VFEqR31BcHBRMk4qdnpoMTFTKUdod09PVT1aQEcl
Jjd7NU1DIWU+QFR9aEMjUnd7JU1uP1cKejZrQiVoJktwJm5BOXlOekFDWVlXOGY2UzUhY21DV2tm
KmxSaUh8ZyQ1MiZ4ZmtgaVQwKk8+SDdASTUobD9JMkl2CnowblFDM3NeYWpQMHp8PWViejchcSNu
Q1VvPCVoXjNxTDY0M3tqb2Q0IyllTn4+THc9PjhuYio2IUNSbXpJeSF1Mgp6Xk11KTspUCRKcmVn
QEpidHl0K2teOFJtMGg9Snlqbl9Ve3c3TEl6ZDMwbmZRTWNOYkx5NyQrIzt6KFUoT29XLWEKellx
WUZ+OFR3cStzYVRRLSQkQUpQRU1KVXB6KXBBT1BePnpsWXZtMDhZfmxYMGE1PWgmRVM7UzFCTDd+
Klg2YURXCnpEPVReOFU5OD52SG8jMlNuak0pZCNIUH1tZ2kmfkBzMXYwIT1vT2g0YDZqMmBUdiQ8
PEFAPzMhej8jX0Q4PXVBQwp6MkRxP3l1KXBkSmN1M0JCPmIyUz9Maihna1RxUGR7SlJ4T3dgLSZi
KilQNTFLWG83dik0OzU+dUU/blBYalA2ZiUKemRYYn1UOGo8UyNuIzlHMXJlcm1VTSVCJW84cSFf
Q1c0P1NkRDlFN1RQbSpUclRvWHJFcWlKMkUqO0RHPi1pMX5ACnpGb00/IUt8Qm4+Ym4oZ3dCcEok
LVlaVzEqPkolRnxAe1N9WTE1OU1PVm9adC0rPnV8XjNFVHYkbzlvNVhOdTNMKwp6b2VQUGJRPm9i
c2lMMlBpfEpYWWB0JGg1N2khdWEpIVNrWUhpO14lKDZyNTJBNno1Rm5EPUt8KXQpVSRMVihNQnAK
em09NWo4YH1KdkQjcEw0UlZ0ITJ+MXZaTzIpI2t0NnhHYClWPUpZJE5XT2hYUlNGLVo5RTg/KTZ0
QyFqaG9UPzAqCnohYDNjMnpMKnBFYX1kYkFHPTZjVDxiJT1CVHhpdldvWUJ9XiVtSXZEcDZIWVVJ
cXhRb2N1ND8kbGl1NXg8NHo7YAp6V1cjPEF4fnJkNk1WVUpBOW1abkVhWEF6Kk59QSFwellURm5A
KDRKcU93eXpIPEJMQmUodkhOakJ0UWhrQ0hmOWIKejUhZmpDSTFVMmFxU0UlP2d3KGV6ZE0kc2ok
ZyN6VjxOeFVzQUFhK0wtTmt7QkB2JTFobSlXNEFDVkFVbmlYM35ECnpVPUFlVFBFI31XY1lvPSFB
N2pCcyZzaWY9MkgyIVBKYl88JndiUnQ8cm5EekFqbVQ7bzgzcmxSa1AwKVIpYm51agp6VFUhKHJ6
dEMkOTx2UTRsZiUreEtmIUI0QlklcGxWend3UXs2O2I/S0RRMHtMdkhZSEFZSzxMdT9KWm0wRCRR
fmcKekBJSDNUPTtwbndiNTZ5dlQ9SHFJeWwmdDYwRDlCKSQqQWdqcFFqIUpXXlQ3I0poPkhTUC0z
KS0/KHswNSRUbk55Cno3Tm14N0cjPGcoTUJLfXdYS1RgKUNLOCstRGJQYlFzRSYtd1d7V0VCd154
QWhNcTtTajxmb0gydipSelU5cldGawp6KmY2PVRPVkBQKiZUX21DbHthPmtoK297SURacD1YQnRL
ZTtELW14UHVmPWlrdGx+NlAmZmVLcTlUNj1gM207ZUgKek5KUWFpQ2dIeGExdUN8cU0oUkVxQEx+
bVRhQSQpY1lTNjdWRkU/YFN7JTByWXdEdFQpeC1qRj8tfV4+fl9LSX1eCnpEalI9O00rYjQ8UHZM
aEg5a01Bczg1eFY/bi1YN0lwTHRTdG8yN2c4OStFaF5LPjJQX0J1QX5veUI+fkskN0ZLfgp6MkR+
RFh3S183XiQ2SVBwJklTdUNDdEFGJm1YViYjaXpReWNsZWcxQT5adiUxWGomYHplbCt9WkJsRGxG
YD9mUUkKem4xVzVsSWAtcTQzNXVQQ2IoMUdNczN+NFl2ZVckd3NAflZkNHczd1hzMSNoMyh1K3FU
RXRiTntpYGBKbEV4Rm93CnpIOHdhQEx4fHh8N198STA3fTRMUitRcEprWXRoO01SNVkkM3ZfTlV8
WmBrQXs+fmxSbWdMZ3gwPiloKVNCTD9qRgp6RjZDd1U1fHtYZT8wX2UhP2pzZXcqSDAtX2prdmpm
O0JsPno9dTl4S14rPUlKMTc0WkJZNWR7cyo2czhPYStJclYKemV4alpBalRBP3g3ciN6JWJiUCs1
T3BSTyViWShxJTNWU3ItKWlCYVhvWng1QHg7an57RytJT0sjMGhsbWlpajZwCno2bE5rUlF8RW5p
U2wkV097aCgxT3VgaHdLV3hyRXZkXn4jQlc/YDVzez45OFFIb3lGMEM3fEFsRCUhTUNebHZBZQp6
elVDV3J0ejEqMWk9fFV6YEdSZD9KMjZxOGlXNWhXS3l1WTJeT3U/fHZebWtxcnZ5KzlmcEFLeCU5
R0NkQ3h6TGUKelQ7eChETmxJO3pWY3pZIU1OezVOUEUoe04ySik5TklVRDBsZjRiUEtLZVlqaERa
fSFvRGU2T0ZzTmNBRzYoc3JHCnp0XjlBekRRY05HUXdscyFNYnd+M2goKkNxeTI8VHk7KkZUc1dM
Y1BYUXU3MFVHKHFuUT4lZTNeRVlNdGUmYX5PLQp6VVYhKH43Xy00KiRLZlZQSF94NGpfIWtKUyst
QE1KdSpXezZQakgkMVAqdWloUHBSaGV1UFRGcjgtanpOVTNfazEKekFuLSF4PigtMFdLXmZzTXIz
dG98KGlqXmJyJmhVKipBYGw2QUl7IUYwcEA5MGF8K1RqI3lEWjcqc3o7WE5FLSZJCnoyKkUxbWpj
N3VUYG5+WlZfP05yY2U1JlgoUl9DQVZKV0pMYCZ2MUFiWk1sIW11Y1RGWSlRSjE+K3tDWG0oX01R
Kwp6NHxqPjVgeFkhX0BDUE1+fEs5bkJmQHFQI3IhPnk7dEk5MD88RDMtWFBUTTExdGRrYC1rP0dZ
KzxhaDgmU245bHIKelBKfWs/eTBwZ3hUOWRMOCojQ3oyQ2dqLT5ibVc2RDV4Qz5ibChXfkNaQ3kt
MlU3UyZLQHh8ajd3dXA9SyVeazloCno7dSg0NSMjZCE+a3wkdjxyN1BIYFFmaF9zOWw/Z0ZweyZ4
UjUwU187WCZUKFd5dGgrWDNNeUo0TVhTJWZ3ciEtdQp6K0FYWDE2e3RKWWlZY3FAPFEwKytvK1BQ
VXY9P3JYSSRVbSszdlpkOHY5Wm0zckRMTFJEZlcjbiRXeCNUMjRRM14KenFDIShNMkJxQUBnWlNe
fGFtK1hENCFJNUc/SnMwVmxDeyUhfEh7OUdXZDVxYHc4NH0lVUFAfSpKTX40dXkhTW1QCnpjXmlq
MFJyU35WazdhMF5VbGMzR2UqZ3w+IzllWXp7ZTJWKyk3d3YzbUczJm14Y1k0Uj9efnwkR2NWUCFJ
elJragp6cl9UY150K1hmZHYqKzBwUmc0UDlKNUZFclQ0ZXRiZFlZKXwjZERRKG0hKWU/VFZPUUVh
RzticGArUCEpSntpMiMKej4+eXJMc2x6dj8kMlIyMlYkOFd9T0krUnU/UFptajwtJCRYZHRTMVk0
KTxwNTN3ey1AR2xsRmpYeVMjWFVuX2JpCno0Q3k/UWJRPD1aNGpNKCYqbDZPdmxUI1M9PWY8PEB5
Skt0OCp6XjYmX09nIWIrQG5qYTx8SV5OVWk7Zz1reXkkcgp6QVZTcGpHSWN0bVNRZ1RwI1YkeVo9
WDN3RkVeUlVlSG9uWn5SSHlgeEhHaCtfVHFuRCozT2t2Y1Z3XkczOEVNYUUKenJgRGs3SFhTIzdE
P2JYbGgmPz57PDtqOFFPNFA5JCpQXj5Bc0hxd1UhKVBReV5CemtEM3VrOzghTnFSXzB7QFZRCnph
aVlzJGI/QmVMeylmKCZYKGRZJSV5VjZ0NHpKeiZmX2tNQEE1dW9EblR3QD87TEUtd01PXzAlPD58
N2hTUztMKwp6P30qfmRmWlgoRXZmbGY3dkhscX5DfU9UQTVCI0hUc15DY200WGBINnxGSUhVU1V6
TytgPCVgblE/ZTFzeV9sJGYKeiZIR2lEMlRzdSUoOGdWPDNUSylpeDlQVjxQbFdNOWBXZ3lQKVNl
fE83fnV6JjJBJj17VTtmO2gzfmB0WHhFMl4/CnpXViV0JSVrej17R0BvKzNrRkpEVVR7VFEwUExK
d0c5JkMoVmwtXkFHazF2Q2JDTFlQNlBQWEF4ZWVTMU9oQDBrYgp6PjR9PkR3ZCY3N19+Y0lLIWdL
R2JsX0tKR1dRa3Jgekw+RnZySU99NjE1JjhFWGpDeWIlYnVlJk9AKVB8ZXY/RGUKeklwMndyTjBA
Vn5lNGNKd3szQ09AZD1lNjVlQTx1UihRT3ZgbkwtX3h0WWNZfU1pa04wT0JrWihZS016eUdgUD56
CnpufG5LKlokM1ZaRlctTGxETWhoayZrWmxkNFJSJHZ3QlNHMmY3SSNOe3JjKnN5QXx7bD5mQyRB
UWlEdyYoIXYjRwp6TiRSODBhZ3Bme3chZmRSPWpVLXBBKTNVeiRlTl9Gd2hUNX1fJjsjWV5meGUq
cWNFJCFnNVJqLTNzSlFHbkNzOEYKenFuI005Pz18NUh3NSVyaCVEVzUjTnJkOW1NXnJnJj5ULX1Q
Z21NNGpebVY+VHM+QD1iIUIxRnxJVSQje3BjdjBACnoxa2JpIWBjPi1EKERAbWF1NXM7ZXNmTzgh
dzZWSVYyZWMyVmRiSHJ5I0pIfXtBUztmenJWTXc7OTl3OWR3cURYegp6eHwpcUNzSitla1JnfWJ9
UkJiOElAS2YqPklocGFUZjchbn5mLTlNRTxjPEhXNDI/NitSXm1hcndfYl9TVVgmd1EKemozcHlR
NjdRUj5ASXc0ZGc+ZyZ+Kip8NHFoWkZjSnBOO15IR2tCdDVOaVpBcGN6a3BBTzdrWmhpSk57S2pL
PylHCno+P3Y9NEA4YWdVejdiNEJzcE5qb0MyOXAwUy0zfHstbDxpWTVNbnBXTm0weklHVW83XkhQ
TyVvX2UqZzgoUHJVXgp6IWVBWXhwLUAyNyQ1WSlOalYqcUwmXzJ0Ui0tXkEmbSZ2K0hjaz8yamtV
aGYwa1l8eHpQNSFqPG8zeEoxWWxzWSkKej8pYFV0QDY3SjlkRm1NRWRAQGghb1IqaFZzRz1yRzg0
NDFCbjdjZDJHOTM7PzgqM3U2bjdWKHpyVGtTdnRFNWs3CnorMXBGJERfN1dab2J5LT55dDJYVz1D
YVVJPkQxX1FtMjtrUCV5cSlHZnYzMEFoKXN4NlpVS0NYbCNVQHFLbFd1Ugp6aC1XM1g+bkJsVThz
R1gqcjFRRW9jeWckRXdJNzZiYmpkOyoyIT9ES2BDZiteKUNyWkxDOCFTU2RtZ01rREFLJEkKej5D
QjJ2dXBJQlY0R0JCe2x+a2BKKlNOVnMzPXVOIVJnNFVyMmd+YClzX2twckB8UEl6djFIOXVAc3hU
fEZGI1MlCnomKjZKayNAdDZ5NkNgWktoeXlMXyQyMWE9MygyeHRiakM2Y28qKCRhZHc9Tjx6O3Br
Ym9XTCpBXmJmZjQ8RjVYNQp6eThDKEA2fiFGeUhlQkMpa2AwSGZYdTtnUjd5TnV8QF9WQTlVdF9+
WDlac2BXKnlFS1NvcE9IWkV9Sjx6OTZTJG8Kemh0b0huYUtBcU01P1lqbU9wRGUqeiQxRChESEk+
ST4rPk9uM1M9Nk9IKntfQy0yUnpucFNTQkd3fVc7Kl5lR2Z+CnpBR2JaeEU8YnRMQGojUmA3bG1z
KWt5YTR+IT88czg2eWw/JF9DJFN8bkt9RDFARklIPmcjQVVjOTRgbHR2dCtoeQp6KHlAbEdXbip8
fD5pM15XPmJ9JCFDNERNSWx6QU9mZmRNbl5HeEc3ODYmQ2dNI3p2TFhKYSkzUUZMUk59KXJMWCMK
emA+QTUyc2czJnJycHxMTz1ofnY4bFJwKGxjSkZGOGF9NUBuTHBkM1luPzxjPUB6U2hTWSVjQiFY
dUYmZndJIVhgCnpMNkcyS1BvTFJ7Kks+fnZWJjk7bnVVQzVjTztzRjFrPWpyfDB0fDlyXnpvKno/
fUE7Q1BYSzQxMCp4XjVZV2ttRAp6KystaHheST5nfXorSHNVajB4TSpaJEwwPGduaTs/QTxUJmRm
SHZ5KSEkOWA9P3soVn1IPklAT0lCb01wPW5BO2kKemd1VSVUX215O2hiTTwzNG14PDcqWSh6PFM8
bjxgIVIzKUJoN15iMmFXWFM5VVM9T2NFOFIzMkBoTEhCTzF8fEpoCnpHM1dwQWtFWjw7YG1ucEJh
V3cmKHpaeW1+Xj9MSyU7ZT4zc0Z+MHpPSitoIXRvbVNZISloeks9a0BuPXJIVDJyVQp6R2x8JXte
dFRQWDItcz0+IVMqaEl6UXB0cExIPGBJSVliPm5ydXZaQjFUVGRGNTkmPXpDeDMocXRJRnF5RkFn
MUYKelczNGthc2xIfmZfQV5VbnRNSjV5PGsrPzYkeG5gd0ojdDF9ZW1ydVhQaEBRMz4xejs+JnA7
cWNud21aP15SUnFsCno8Zz01YCpRKDloWDl8NkRzZ2E5JDY0YGVZX3sxcFJzeyl1cztBSmteY3cl
YTNnc3VNbShfTTF3OD1nPX10dWlzdQp6ITdKR05TWUxsUT9XV0xZSFlFMV5Wckk0Y3d5WXlIalBr
d2FrbDJmKlRhcklVbH5he0BmVkQrTGhEO0smZUBmR0YKenoyK01ldnZ0YmtRaSU5bGMhREdDe0c8
eEViWj1mQl5AITdmQTFLMmh8SEh0MG90TzhkcGZ3MnA0Rk5QU19RVmFfCnp1PUdAZldHPzkpYDZj
P0J7K1l1aWNCWUQhK3xsVWUjKUJ3KzRiOGhQOThCaC0zYDhiRyVYZyYlLStEa3UhOF5MJgp6RTxD
Z3E4JDBDeFA3YkdHUzh+fHJlI2ZIb0c5dFRtPy1SWSMyRkZfTFBHKCM4WjtlZH18NGtjQ0xtUiFe
ZVA1bGUKenFfY3dITWIra1BENUJ6YlRhPjwta3dEMjZtMSV0UU54UyVAXn1KT3A8ZDglJm1SSjFS
c3J6Ri0tUy1kMDslOzJ+Cno2JEc0MXFyamx2dD9OZ0F4WENPM2VZRSEmb290PHgpQk8kWnltdkpT
bEAqUVBGWFZRQXVlSTE9UWhFaUxjNEROdQp6K1V5ejUla01VeFJJOTFmOTV4IWRvOEYrQHFgZG8w
Kk5Ldm9wc2pIM3QlbHk4el8obkdYTno7MW5gRDdySl5zITIKenYqJShhVUhiUlRsLWJFR0c/RVJh
Snp2eXooYHx3WEI8bWpaNTxFVnlTO3Q5ejtCcEQ9T3ZTTyEkQ1pwYGpOVjBeCno2JV9GPTc4fGRM
NmgjVXsxQkxHQ2cyeGtvXllRNzw/dnxkbzVGWU9paUVYZGNKVjJhc20lc1I3ZkA0UjMwfGc+cgp6
RXQkNnlscy0+e2QheyFSdGsteS1lMjtXUFEwWGVJNF5TPV9LdW98KnYpQV5RM1lMejsyaTI9alJQ
Zm5tPiolJSoKenxNcSkqME5lMzJTfU1qMTE8KjRuTV9iM0dlQ2MlRTxLXkFgP1pffjx2cD59eUNq
NkF8SVNST1ErPTZxV0xFJj9ECnprZ3IwWSpLNGE7ZX1kRUVXN3JUNThKPTxSXlZnQX5QNjhoN0dD
O1Eze3F8V0hZR3lUPztzNDR3PmBiRnJwJTt+fAp6em9xXkhUIX1Vd2hMUHtJNklvaGVpfnN7SGll
dVRJY2p1ej5wMyRYUHZFOWZDeGRqYiRQMEwhcVdPKkdYYGA4Q3wKej1SMSFFbmFGO1pYJmAhJjNt
bnY0WD55KnVaPXctNGd4Xz5mOHh+KTwtQThAZns8MSF3YX5lQz8lVkthQkg5X0B8CnpOO3J4dG1H
R3ZRLTlNeyVYbi1QPVc0Xz9PY1g+aDhwQzUrXmBga3dHNjlSN2l6T19VSGVeUVpgQE1odkF8OXBf
fQp6QkBKOExiVz9WOz9wQ1Q1bUZ7YUV5PSVvS2JhZj1YeEE3bzJxe3JNPldCdW9vb1otOHteSVYr
aj1SM1NkTGNJSisKenheTUhuUStTdTlwYldUOVIhTiNQQHkkdmVLaEN9dHRiTiEwdDIlczFCTU0x
UnFaUmgpISZQcCptbi1eaUN7K3JzCnokZ3U2WXhhYztOTUV9ZTI1Xl4xQHZ5JUZoNnpNTTVTcXNx
dSZ2MEY4LThaTXtoKXcmaVdfZSVBKXM7ZX1kLUZwWQp6cDZhcU9NeHp6ZFMrSzZMY1FiQlppJW59
TDNwKFpGcilSbFYjNmtrbVpjUG9YRDBiJW55UCY8RFRBOSMzV0ZOV24KenA2aHpXLU5ROGB6ezMh
VVBuamZlSWpDe0kwcyhQVVZ3VXhoRHlqKGJ0KG9zX2ZwbDYrKCM3JUxpZW58RHBQWn5gCno3eVQl
eiEmNG4xR1FuR0J6KT1pKVkkUVhwLSQ7NV5WYGJLZHdSbmdkVVVIR0d3UWJXVmpeSjsyKFd7R2I/
fUJ1NAp6T1dzTyplNnRHTkNSMTRhSX4jRkwpM3BCakshbC07X2V6bTZmfWlgNWV2VWckJlprP0RV
WElrM3t9MTt1YStDWG8KelNBSUJzRUtlVlg7SjEpe1ZENHVENilDMV9XISY8VnBJTW9zUEZPNC0p
dzxGUWsoTDRObig8YDRCYmZjQkpmMTBJCnpLJHVES3cydkpFUEs8WGVOU2NHK0xFNXdiOHF4eWpW
QzVHZno3b3Z+cHFrPjE8Qmh8RVRFWFBWWHl1Ul9JSWpoUAp6MXxDPzVTbT1JI2Njci1icyh5bm5z
diVPSlF6RH43M21rTXIhIWhwM2R4TWFsWXxGMk11PHt7dU4qPkUhPWRnTDkKenNuTH1aYitGfGBz
MlhtJHhaMUohK1RVek48fW9LcDIhXjt6UT5tYkBTJSQ3TmhJUHVyZlJCPXZVRypWO0RtLTdMCno0
YnRJXnxHKnF+PVZSYmNUMDJxbm4pR0dVNT9BLU0jRzloTEhPTGIxRGckXzNZJTcwdFdVTzhaNDVy
fXlKVU8yegp6c18yY0k3R3wjPCh0LVc/QTxra2xtZUcpP3Z+TTt3N3V1KFUtWGh9MyVYQEZuV1Fa
cWw4JSYtTHglSDVQQFl4LXAKemhBaFhhcTt+JE9xVmIrLT1BMkxPOHQ5PVQ3KllfZClHRzcmWV5I
JD4+bjc8UWRPVmFWQEpJVVF1ZmZWVF5wRz5OCno9PzVpN3FgR0EpUXJEbnNWQShTcjh4ZCRTUFdS
YGh7IyVxRFQtMFJNOGduSlpPMjE+OEBSZDJwUyQoNzF1XyM8dQp6LUpHbFlvdzBlNXViNFpiP29X
WEUreDNpNEIoanpmKH5FPG4kU0N0bWhEZU9wcXE3ZmZGJVpHSnBtQGMxUXRyQzYKekM+diopZkgw
ST9LQk59K3YqdSlEVXtfPGNmMTM2I2licmlCUHRodEVtWlNOVzFhYVRpd3h7TDwjfms5d3FvbTEl
Cno8KjxNbUFNemQyYiorUnF5YDI4XkRkY3E8TyU3IyE2cDFScjF0RjF7NCUxLTZRRzY/MTlgd1U+
P0E8STdfSCY2egp6cXtwWmJDMjc4Z1BZWVEyPlYpRyRZOW56Pi1kZ15CPzl3fi01fTwzaHd4czhi
aHg4K1h0WmU8YEBWJV8zVEhnT2wKelM0ZD1tYVVkcXMrYkEoZnpAZndBT0lSZyR3OE85Uj5hJTtA
KzNBUj1xSVZ6Q0k7fEcmdT5kaE8qaU04aFNJRjBWCnpPUkdiaD1UVHFHXzxpc04/NT93dU01XktO
SkNFRjxDaUMjUz9GQGszKUl9fTZtXjtycyREV0NNUC1qaHFLPmVlVAp6Mlg0Kn1mbHAyJHFCfiEk
ZSpyLUd7dX5fM3tETCtuJi1yby1OYEF7Rjh3WktGVDs5Xl5EODleTShaN3BZUnZodm8KekJTO20t
IS0oNy1HUmJ6XkFBXjBgKmpDRUd6dT9IejFfd2UjR1hycHZgTjdsMCNNbjNVdURuOClwYktpQShr
dm1OCnpOflFafkF3PTxnM0BqJVdMfHJRZjBpeSZPSSExT2NwYkA4QEVIST1BUD1lKl9rTWNKRis/
SlBRYjN2JG8+dzAqWQp6cXoqe3VqJjs0Z24oMGdIe1ZefGRsXmh7SEYpQ2ZaMXp5YXJscyMkNDcl
eFppWmImNUt7cTN3OTBMMkReenA3S2YKemN3U2FNancpKWZ0c18mU0FUcWg1ZGFxRVp1ISh8I09I
cjM7eUN9VFJUK3tTRmJnRn17T3dqVjdqX0JAdWgrPGRACnoycTwyUiRnUihsblg8Mio/JkQrbmpJ
cjV+NHt8bztqdl9WU3pfQFJXbXcjeDBgPFY7b0gjTkJQTUJhTkslPG4jZgp6a2trKjBXdn0jOVM3
S3Fxb3BAeSowWHI1NWNeNjNaT2U1dHNrTytGNTR7Vng7KF5VbSZQeT9nNkdXOFd6an5eUHAKelIw
MTBPOHkpV1BmUjhlVGp8QHVZMS1jVnstJj9oK2owYXsoVFJkZ00hOStnRCttUUEoJUp+SzI1d0JD
bUtGTE18CnohMVZ3VnA7ZmFZZjxJdUlJX0RwNyZSfGBHMEUwOUkmbTY5K3tpcUxUPDgjI2Z7KHVB
WDxTUDRsVns0JCpMRlI8egp6SlFSWjhnOUxnWDBtfnJ+ZVp0eShYQ0VKR3smNio3aTNSaUQzekFe
YW0xV2ptRWxtZ3xNKXRDZSFJNSQjNUtxNFYKeik0Y2VUaWVLa21tfjs/aVRBSS1OYTlHWl9zX3xr
RCVNU29RJms1cnAzZihgRipaeU9zPTF6PkQwfSNOVWBiejkhCnpIIUFiPnJ4NFFaPH0waTVfZG43
VWE9N3clREAraVNgZncwISErPzNvKUluTC1vQkpSaTVjZEQoJW9CQm17enJ4Pgp6fEpzRTg8cEF1
X0xsMGVFJGBxK1g+PWxvVCM9SCtsKC1mZEBTSy1kODNHdHxEOTU4JEMxbTVKbW5RISVOU3JhQCQK
ek5gdjw4YH1oYlB7IWdCbG5eSkl7TWY9IS0tMkohV1hqYlZ9ITAyT0tDOFFAfEc2RH1uV3E0YmRQ
PykoZCtYRTBZCnpuSTxpfVFsP34jWlRJNz02Q0olRSVgTF8qbnp9cCVAclB1cEZ5KjM1UUU+akJO
fU4kcGNOLXUyUmt6dFFnYSlldwp6RVNVe1p2IVRNOVo0KTNweTlXbXlNNUd0fGNwPipjMHJRZDhG
NnFyQj9MVnwyUjVJQmlIdDkrWiVAN3o2NTR2Sz0KemU7aip7OTdpJGdSayY2fCZ6RjtwY0Bfd3ZM
NT1sSCZQWDxkWXU+IXAtTlYrZ2Y9Uj41SHx3Jnk4QWh+eioqPkdCCno0NVR0S2NSe2ByeTxFU05r
Vlo+cFhRbGF3eXhTRHUlZT1eMkMyKzN6V2oqWFEzdCk/V1l+KyZ8U34yM2ApIz5ZRQp6VHd1YHEy
MzVmeFotSiM8SiNhQ1J6Z2xMWHxLNUxaamozWWY5T2V3PyRvdURkPkg0NDlkZ29nTURuS0ImQEkw
ekMKejxeKUBoVD5udVYxe0NrWngkYF47O1p0YCVFWFd1dkY4O31DS2VDPVlfa3M/cnw4c3tMIXZF
fGorMDI1VW08ZDQyCnp3cGBsJUtTUSRwem4rXn1lbSh7ZkNIKlJ7M3hee3duRShmeXwxMFRLMUVj
UUglR3BhZipGdkJ1b35IMmN3fCFRPQp6ZlZYMkRaaVNmdVdlU2d5eGZ4T3dLISkyVE80Z3dkdHJK
dGx8NlFMLVNCaEUrUj5yKythPkZndTB9OGhzS1ptalEKelcjQjhLdUZ0UHZlfC1iJEpgS21tMiNC
SmczPDdvM14jJENQfDhBWn53TXN6fmNBKGQkU3V5ZkU9SytHPjViQDtoCnotTmt4P01kYCh0cFR5
RDdvNSN6Jk83QnM2QzgoUWxvZ0BaRyFgTUxwbXZ6RGMjR3F3KXskbWxWTWdzKURfVmwkZgp6UUds
NT5ITnwtbmw9bj0jbUd8KkkzOGFOUDdKbTRETShHOFNBZzB0bUVYbystZDNQdjNhPH5qVmRiPWBq
NEZUdncKekBJa0t5Sy0zUz1rI2VQamtTUCNgQzxiQmtPd2p3N1pEWW85VEg/M3tNRWdvOSZZT01e
clQ3PndhMzkzKDd1QVNzCnpTRilfTkRDcypKaz1sS3goTCZLR1F7Y3UhJC0rJEBSXzMtZG1qWU16
KX0/VEJPXzhCcnJxWD5vVXhAd0gyQHBnKQp6ezUwMzV7RGVJMTtsdERlMEYlI21oUn05UF5AZXpH
NE1aKTY0cWR0ZV5yTkp0Jm1CbTdwOURCYytfdmY0YWYmXkAKenBafkBBaW5OMiZII084KjJQTmlM
ciUkUC1CZipoWDY8Q0tBYjVuT3Q2PDMwbE5RJTVKalcxMEw2LVpzWTskLW08CnoxVkR6cDtnRzs0
UTJhWHAlfnNHZ20yVjJRZGlKbWVKI1R5bjVOcUR7c0tfeEAxNylSMU1IK1Q5U1J9Yktld0s/Jgp6
UERTO1ohI25uO2ByJEppUi1hRkJkTUtlN0MxcCowY1VeSkg2Yj18WERGUU1WTGI4Mm1yVSN4dFUw
aDx9UlZNS2YKej11WkYtWFR7d0dMTklsNTVYcipMOFApeDhHMT1JZEYoTmVpJHsyfXI8PEV1X2F7
MTAlUy1jR3NWX0JpbVFBSVJfCnpBPkh5aW1jUlRJQjtoKURYMzBJdEdycFN3cFVnTVdkUV80ZXNs
aUFOR2lFISFgVDhYfVBOUjtPO0t4MlFlQm9BdQp6eElxSW9HSmY4PzJWNncoRzVxVikwQk8xM15e
Vkpha3g9d2IhX0w8WkhDanxXMG5XO2VWfW5nNDFAXjVKOE5sSkYKejJhKU18WEoraiR7WEc7PExf
Mm1sYmxkWG5xZChpZHtAe2h7LXRAZSNgaWduY29lUzdLUH1eOX51NVZ5SSo+emoqCnp2d0tEdEB9
JDN+KHY0YXUjT0BgWClfPlU3YCUjI1B1byE4diMhemxRM2ghZ0RpeXZ8VGx9fUw7QmQkcy13c1pG
JQp6VklqP317Kj5KNlF8VXdGP2d0PnZYamFNR2RZS04zPGZuP2plZ3t5KT08Z3Y2U3ByOVJ0ZndG
ITE0e2MzXk9NLSsKenRIY21VXkdDJXtIcmYkQGdPUSNEOEMzJTh6TWROYylKdSp7TzY2cDJuRj9m
bTxOYHBzYlRGMkIrTCRyMUQyYWpMCnpeZ0dxdWh7KFolP1VMVmIxO253ZkdDP0l6bH1HPEA9UG1M
djk8TWpFZlhNaHplSWA5MSMwUz42MDB8KHFWTnZ0cwp6aUxBekZRQU1ePEF1WFQ9P0NgMTU/NVBW
azM8UyRudEowR1Z8Ml5geVlYP2dlUGxQRkhkQTgyWG52Vk5sbSMrcHEKemUhMDEjO00qUVhPOHM9
QDlZPGFURkE8eSUzd214Q2s7OVReO3ZneHFEPHdtK05zT3oqQGpjSX5QPG9DZWNgJGcqCnpIbzZ2
TVlLd31KaDJffjl6PCNMTk9eM0FKRnJ+O3xoVSR3e2lLY3ExdCU9I3VWMj1yPk9HdFMzYWFldzQr
QG9TcAp6dlBaUj5LV2g7SkRidmROWjhQIWJhYFZ4Ml5qPTxrc3AkUUZnQVhWQGwtfVdHTVhFZDBl
TmF4fitxLW9hWFVCSWUKenpIIz4zLT5jQUU1Yzg3ay1rTGxjajRYUGcmI1p+enBnR15CKlp6P0Mw
MGEtd2o/dEptdmhIPDVWI2tXWThndClKCnpnfjFJPFRHLWE5QT81SytMcmZObSNOfH1SPEVycFNq
VWopTyltSXRfUVBSZHduVEtiTHVITk1yeVE8cEZHTjtAQAp6KFk4U1c4SVE9eS0yKWNuKVc1Zilv
VH0ofFJyYiZCYFEqcV5QSSMha1BRJkl7N3teS2VTbT0yRylJcEZSWXZBYisKejE9P1hMKlQ3MDdf
bUF9RE5VZmtCPWw0R0omTyhXdUprc0hTTzgwVnZkMj5NVy0wYXBiMHdecU53ZmtYUkE9PVlmCno2
e1ZqVDE1akt0dVloZDd4UkUzOCpYQDRHRV5uUyNXbytpK147Wnc9Sz4jVjhycj43JW9zez5LTzdC
QXQ5Q2Zrfgp6eX1URGVsfGxua3RlZ2xnMHQ7RTFVWFZTQV9FK1FrYmlDeUZ0Xm5fZSQjSlpZPUk5
QHV5eTxqMTQrez9qPXJ8eU0KekdDPSZBUGg/e2FwS3MhJVIhcDdhM2tCNkxuQGZeQkZ0ezJnNWAo
eXQmYSZnTlhWJm8pdGt1eEFhfk5ZV2tsSlBNCnorJTlwPE5VSExXTGkpczRqYWhoMm59T35IMVpX
TFJ5MFh1YkFGak1SQXZiT01APkhiTD08bWRodzgpQm5DKmo7ZAp6K1lWPFExSkhUQjhhTnpVS2Js
YUooRmM2PWo/JVhTTDQyREprSElPZGhhYzAqeEwwbT9HVXs7di1QX3ljRm5APjcKekt4QWJuK3V3
c2d5b1hVfD1EWCYzPStQRFA8VD1XOEtmcmxxK2ozdU9aezRTJDAlVkBucGhrejhVPHF1YSFVYkFt
CnpwWihsQDxCYllmTkxZV2dNRClVQWtjLTJgeWJYKy1IJEFXR2Z6UDY3fEFyPSNafnlhJllZPlM2
U2ZrX2NXblF8Mwp6TFMwWXF6TUUrN3kqUTY0YlFvQmx4Kms9M1cqJUx1MWUhNWZWfnVHNFhrWW5J
bjl8RGZRJWAqUkN1Y3pJSS1xNl8KenM1elRfT0JnJWZsbWE8TmpyaEVFdD0qaUNibUIldjxPNXpw
TTFRZTtYRDVteF5aY0l+PSRIXlIrblIqRmN4Pzw5CnpvZFR2YWlvdXopVSpyc3BCM2VoTztiaD1a
JnFsZ1ZEUylyTEZyJlQ8KnRPWkxOKVUjLU5wKnloYnBgVkdecj8wRQp6ZERBYCQmI2lPPisrdSVq
ZTJ8Y00yTzk5PnwyYEREJCkwTiV6WTVsOEp6NmpZSGFZNzFKLUNRb19IXlhKP1VCQW4KelRtSVJv
MUdAOFZRdGV1KV90OUpzRT0ySD1oOzYhJnQ9OWZCXmlNM154I2hwNzZVZXViV0VnMXY/O21TUDZx
amo/CnpIKXBOYCpjRlkmI2Vxb3VLSDJiJXMtRWB7T1c5dEEmVXErblFUSEZrX2JHUnZ7QEpaZSVE
JUJMeGw+NWhwNX1gTgp6YHc1NlAmfTkpX0pNSml7UVZFbyQyayFvWkdAcTt1YngpdEptXmJnalBX
WjhGUWErX0xoOH5lPU1AcyRoTF8tZHUKekAjbihWbVhaQEJ8Rl9zUG83cnN6UDs/eFp1JGY3TVUw
PkV3U29naldGMyF5Jk0mZipxI1MwXkxAMURVQll+YUg2Cnp1MGszJlQjV3E2cyp9VEBWQXRXK297
SEhXUUBPcHVFaylvYiVlU20kd2l4N3lsP31pPG1FZjQ0IT1takAha3E3fQp6YCpPOVpxU3V4ZnBm
d0JTO0BKQUJRTD1qOEdyKGlya15fXmc+ZGJHPWQlU3MxPEcrcXM2eFpUT2RwMXlQcCk/Sk4Kek97
aSEmQHUxMVYpaWR2PGt4UjFRNih7NkR3Wigya0B4PitJP0BYWCpUfCM8LUVtKnQ7YXhHJDUrQiM4
WDEzYkRmCnpMMzhiKkY1aW5icSZROztfJjZNUVRGUmR7UDMhUX11JEpEM1gqX0VBNEhnYGpxVm17
fGFaeDIwUGlYPGh8OVFRMQp6eWorc3RLNiFvK2oyKF5TbEArfm9sX1dMaDJHekdnRDwmcG0kKCU5
P0ohKGVpMHxkRU41Ki1jcDl8SDV4MlV7KTcKeiFOSjs7UW94antQYys1UC1UeFpEIU0heDFkZiYh
RFB9M3JYbWxkb3BGMlNwT29PcElWUjUpKztfKjczfXh8WE9oCno+WkthbGNXK1FMSUtRNVduXk9E
dkl9Myl3U0JHNWhkKUA5TmI1dGdfPDJOUG5xNHxwQkNuU09YZUs8eyliYXVMTQp6RWl6bSFKfFVO
V1VxQ3JtdzBicFIoTl8ofSs5KDVqQ0R+SEI7UWQwWnxGbHBXdjw+bHBYUFFlfjRweiNvX0w7SFEK
eloxJmRtODJ4Njsldl9BPjljRD8jU0RTUXphaWJHbnREVGh6UXI+amIpZWB7KiFPVG91UWleeEx4
a2BVMTBqez1RCno+KXYpdjFFSjIoJEZDNCFXR3ZaT09zS2YkUT1rXk42bGQlNkckdD04c1o7dXNV
NVMpQms1S09RPEp0WmNVKDNhcAp6V3pwZG87JUpXQWZPKTZCMjwxVnNoVmkrcTRudCtWJCR+VG8q
Wlh9KTBgPCMmWmNrRWVUcHkrN216VnJUfDIxJXYKemxSbFNJSThVNmttYSlSIWh0QmJ2KW81XzFY
V2JkJUtQQFVOcCtLSmMtUXArS041TSVGJGEzYVYjNDBiUXlZe1EtCno4KShlO25pNmA+NGB6TXRf
NXV2fEJPX30qVEczZmclfW4/Y3FJZj1aKnRVb0QtJTctRlRSWENORyNvKXt5cVIjZAp6ZVBETkQp
dW0+e3ckPG1pa0RuQzRZSnxlc1Z3OXU1P05sUHIyKyNXXihyTVklKGVFWTxIdDEhakM+dDBUeXdN
dXUKeklNOTM1NXdHYyplSF9vOCY8Jmo1QmA0JndFNVp5cjh8Q3xERXhQSU40VkNubUleVkw/Ylc3
MSR5Sl8hfTdaWVdYCnpaSDlNQkp4VlN9Iz0tUGNZdlVBfV4yOVRIbSFPYHpXP0tYdigrOTVZbThJ
a0xadkBRQXsqJlY+bkw2OHJ6KilMMgp6I0BvellgZVVJKlJHUE84bWtfSU9ENmBMTHdZcnZhTyRh
dExUQ3JxMWRhe0xqQW0mNldgMlRjJHR+WEYoVUs+QHgKenZLfGdlcDV4enMxekBWNEpGPSRJaW13
MG4lQERtNnZhZ2JFTDQ5a0tRfERmKyQxZCshSCNOVEdST3prKkthWHUzCnpwTnEkcmt5dj5UOylv
VkRFbytiMEA4d3BgIUxSTSUkUjwjMTdwejJhY3BrTFk7eEtzZ1F3K1pSYGphUiEoRFN6SAp6VT1S
NFpuQkJ6Y1hMbVg5WUt9e31CfkEtfVZLVXJ+IXRXbyVQWXVVZFkjdkRGN3UocT9wZ0hfakxUbEsr
PVFYdl8KenMjJD4hWXNKYmM+JkVVS3EhZ0ZiU1JlWT5EfDxoLSEkfmxyUmUodFpPXkxlM09eQmN5
aVM0YDx8R1NSOUpzdFpSCnojVUs8ZUx1fG1EIVZiMTxuRG9jb0pmPFNYOEt4Pz0tQW1IM15Dd0Zt
SCtERDVKPzJIPGhAZCU5KlVWezJqYEtXTgp6JGk1Q2szPWApdiRxWlF9bn5TbU5VVmJwU3hVOWZA
d3x7d0BqKHFocUQySGNUPkY5JVFkJntTM2UqTjNQa1NGV0wKenRYVlRITjBeVHY8USpZXyZWSnB9
dG54WHIpaGcoRUpwK1c/YyZAPGA8SUB4fDZKPExLNVJFankmLT5oTTh2ZXRfCnpfalY4fj5Pe0U1
SVA4WSh0TkdXbCY+ZUFYa2JiOF4kWStBeG91Kl9RdXAyXmM7IVlDZEJjUFQqZ2BiIVczPUAjagp6
OGZnfXI2PDBjQDRmYnZNQUh5K1dVIXskSXYqNT1obzxFZHJJS2RhWWg5PSlhRFcod1hCVH1SUTw4
UV5LTFB8RyUKeiRzMDlUUFY2dCsrMUg9X2wkQFJycChlVyg3aXZuaW9jTV53RSFUdE9lekFTYXRP
OWwqeFU2SXo4elFxWEhoekJICnoyZTRrfiZEKFp0dSVVcX5YMD12bEVQLTcoR01ne3pQKzZpZzU5
eFMwTENvMXBSY2hIdVRYR2xWNGFRU0QqNGd2Pwp6eEBhdSUqVzN1VHFrSTxOQVFAOD4jUGlIRHVr
KkZGZXBkbSNqVWl2ckhaJEk0Ji1PfUshR3JNXnNSLVVRVWVDZlUKendWYnV0Q3dDeWFXT0d6YXJK
Q0JkcHMqcWF5USY/WE12JlFENlVtSWJZJC10WSRDYjclYFVlbCk0OElIMUBPWjJVCnpNSXhfPj4k
YV9DU2h6V0JlUSF5LVdPdW4jKHo0bndZeWdQZUZwKDhHfDR9Q09YKHxnfFYpS2ZeYEsxU3w+QUJs
RQp6b0p9YHombDtlN1gjbnJqOyN3eD9hTl8oLXBBaypgUzIyTX1OYnt4TU9DV1hXPFRBM1VYLVVw
OEVgYkRnMGBqQzsKelcqJWo9MWJjWUwhOSgtS0tmJWRkcHdSaUN1WFA7YUFZMSZjKSNNeDtkPGh0
bFdGeV5EJTxnbW9wT15ye2BOKE8mCnokRytVYERybHZ9KiZqZDAmJU90X1c7dXZuTl94WXJDdVpK
KVRDZyRwKjV0MCg1alR0VEszU2o0Z3lIX1MmYS0yTwp6R091c2trTWY+Qmc+cGpIXnI/PGQ8QnhY
azdzK2cySWxDNmBqVj00UGFvZ2YtRllINWFVQ15VJlRNIUpjX1dJTn0Kenl8Z2hsPEhvTjcjanV+
PDhQTFJBczI2P05MQCFfJUJIclNVSEV2QE96U0RDQ2lOSmVJRzRaZUxuUlgtR2grUkdQCnpPLV9Y
KGA2cEBhaU9+aHtTcCstJT0xKUdlemh2KmNJUUEoY0NDdlBPX0YleV5qRHtibkhSaChoc3k2O01h
ejVTYgp6NiRjM21CeFZNZkB1KCU/byZNIVhGaVlzWUJyKEgwY3ZKMG1QQHZ4QmJQezJxYmVnYzBa
UEZaRGZDU25FZT5WUGIKemUkIVN2RDI5NnlBTUVsSVZnRjE7SXJEXzRHbjBrcigoS1FrTjZhPGxe
djJZWk5uezt2d2BCKVpiOXsxVl4qKXQrCnojcWxoK2t4WHIoUVB7bG57cXg9M2x+UC0jRVlmTz1L
bTxZRmUrTiZONCRTSDZtTC1GUk1SQlQ8WUJfKiskWiN1dAp6dm9SS3dZXnNBTDk2R2xAeWNELVIt
QkhXYztESUVFfEZyZSFZcT5eLUhffXh6JHRxTnc7THxXX3p3cFU3U3R6MlMKek8jcnxlfDU5Tk1I
U3RBIUd+djZxSz5PITd7SElfME9ufTE5Pi1ZeUZPR29aXjV7P31CNzZzZmtQKDhQNjY1Kz5SCnoo
anY9dkpvNXN0aGUlTiZYUWxhSntDdi1WXjkha28xYjFYK1FecVUtTD03JExHJCp3aklJKypXWn5I
IyltJFV4bgp6Ym1EaiFBaXVObSM8cnlNWFBWN1p0dU8yZXxEMnl2NmJURjdrLTEtRi0tNyRmO14p
dTdMUXlucE9TQ1AhRFdRK2oKejYxeF9eQC0oaVo+ZklyKV5PNkFLKEt9fnU3RTdNdnN2cGRPMzZA
d2JLZXVNflJxaDBSaUA8S3FNci1YVikoTzRUCnpQXj10YHhBPEgyI3tMNWdnWDRUalh3ckBqKiZK
YCN5d0xqdykrVztnaVlOUXRNYStocU0jMVMhPGVrMmlqWDhrVQp6MXpCYUM+KDh8YkJjP3lDM2VS
TzJhQzxlYyRaVUdPZEc+Kj1aYzh5OG9sNGQ5cz99c3x4dVBsQUBXVDw8cHdrKGcKeiR8ODhXK2kh
SzhXVyY8JGxNcWdqZHF2NFVXU2BYKEt3SjZFJCVNbDUmcWg+UjN6bkBeSlJHJGBTaCN+QT87Rjsk
CnpPUjNXckUyU19hJUtlMlpSfCVTfUlxaj9jWTdKI2pMRnhSWWB4TjxhQXZ9RDJONCszSzlOWHhV
WnZEQWFiVkpFRAp6KXh4KVBFfTk8Qjh0RV97U1ZwNUI1KmFGWnBUKGs3XnxLfGNFSVRgMit4QylF
dEY8IU0rd3R5O0opSyorLWRDcmkKejl4PzdOZTNXXjtJQypMKCp8czFVeWB1Ml54TFQ8S24xdVdK
czJINlB1Sl9WPU1TU1ZuOTM1U0U8e3hoP0pTXmZ6CnphTyFRM2ZCIzMxY35NRTAtZCt1NUdvU3dw
UktoJWtXK31WdkdhcF8zd1d4MCUtQi1VKSFRdmZ8bn0qJDRFeHlJRAp6YClKSElXN1dQQHQoP1BA
Km42P2NvUjVseTdLc2V5RmkpJCt5WiFtNT0ydHpIO2ZUKyZRREUhYWN4Kj9iaE1ON2AKemQ5Nj9l
NSs1OD93M000X1gxPj9uY3prRCpUZmxQfGoqSkpNQ2t9JWJKVEFVOUAqd1ZLZWRsNzg0eGNIaHJA
MEx4Cno8SW5mXkIlJXowWiE4WXhnK0NJMVpFY2E8JEBUO3I/a0l8JVZLTmtZd0pyKyg5cnY+WGMm
fWgqN1RVaGFDUXk9Mgp6UkI5PVoyMEVQe2BwbUpDXzB9fX4jZilMMkRCU0hBYj4tYUNhYkhvfkA1
ZU9wSkRyM3IhYUpoZ2lxcnEkYFFDa1cKenQ4YXlVKnNfNmN0TD18M24oUEsmRkZBLWA7X2RLJmF7
c09lI3cpQXw0fnhfQiRnVV5ya0BUVXJwUUxNdjhfJTxhCno1PkghezM5X3slMXElO3djOUhHUzRt
QXlIU2hGfn5FJEdCaEE5Vmg8NH0/VVYhUWxAdkh3OUI3RkdSMT9nJnI/Wgp6ZmE0M1hZdDRUcUJN
b3NmWWJ2fntJQDRLSUMoZSg4OHA/VFBJJV90TUdYZXlwbXlyZik3ZT1mSE9ZT0dvY15TOE4KenFH
Q2ZMIVEtbkhSRjdVNVokND5EX3QkS0BEK3UtRjkxYSFfO31YKnwxKGc0T2lhJUlOOD5OKmpESkM7
SmpGMCRrCnomT2Y9THUhSDZGeF52XmNATUV7PFVOfV5CKEZjUSZlQnxMJXJ7UlJKRDk+O0VkSSo/
ZT13TEtxMGwjTHMtcVZhOAp6NyZ6cnw/RE5CNUtWZ2wzbWR3WE9eOzUjVmxMd0ZmdWFvb2VydXpS
TWAxeyg1WW1iYjMlXzFAaSomYHlecFh8c2UKekJWPVN9VF9adzlCci0hcVgyXzA5SHJadEY4Nz8x
V1UrKFg5YCtXYWAtI1BjKGJJLVoye2R+VGp1amd3I0E3R1UhCnp8RVNjXykyI2lTVll9VjhrMT42
WGc+dEVoXkk+JTUkPERkWSluPTQoa3IxMTtyeEdka0Q3e2w4WCZFUERZcjdBVwp6dyVBOzU7bj45
VSVLb1A1cGl7WTNgajw7fFQ1I2pMPGxHbWQ3MUxNLV5OI0tzcz92ITFIfWZJI2B0Nl8oTVEhNGcK
eks/aihvIWVBbCkyXm1EaGwkPiVrZ1puPTZMTmNgOW5Tb05XYkU4JHNAUnxuJVBXMWVeIXF8N0lD
enJgZz4xZWh6CnpSakJ5fmJOZVFVMndBaXdLbWZufSthaTNHSlFFejNlaGRWSnJ5aEoyMDAtQmU1
UiNYYE18fFhee0VhdWckKlRIcQp6TDUqREIxb1dgcTleWXRCLUt1R2xXNFhMbCQ/UFFYWCNsRz5F
MzYpZCtQekJKcDJvKVF5d0M2VT9KQyMhQ3pYTlIKeikmY0hvYDB3SVlQTnJrSlZtPDFHSD0zQGpL
VjdOKGk8MVJHckZ6ZHFENW84Uj5nT25AQ0FPbFIjQnRBX0duYTxSCnozfShDMVVOd018S21+a0xi
WEw9JldyKU5aXnskTi0jT187fUdgJkdKaX1ufE9iNXpLQnVicnZzZ2V5V19WYW9HdAp6aDdhfSox
STJeRThXTCFycytkR0dMPzVQNFleOX1Tb0pqS3pMI3FjdldVJEw/aGY1eW95NGw8JXllKis3Xml+
N0oKeldGYUNWWSpmc3xGeHpHKkxNY1FtLWpYaEg0SEg2Q3VYSEQtblhMTVdZTFg/a1JYMV94dU8r
V15XJUJBeXBJMXdZCnpmVDZBcjBTfjB3eVFvZCtvZFlvOWpIRUc9KH5oRnp4TzNVZU1sXnxaKFAw
QyluI3JCQ1JIPHkxVCZ4VXV1NiVMcQp6UEtvdnxwc1kxYyNsZlkqI19wS2c4YE5tdEc1e31kMyt4
PnEhPX1zcTc9VV85Uih2S2BvODA3cEpGKVVydWowenEKek8yMnt3PnY0TGpNVHxZdzxaKXljcHVD
VmxScWV7aEFlYVQpVFNKKHFGVFZKM0x2PFlOOzNhVjIpZHtmYnNtMlBrCnpGXjQldUZgPSYjeygo
YyVzdXV+Z05yXiZJdjE8TlB5RVNPYUpwSjI/dHB5fUx5dG1TRGpmbTNER18qeGg4UH42Zgp6NitO
VzJTd21kNjhGO3deP2hNYlVodj4wV2I1Un1HWERMPzImRXk2TERVU1AxQjQwSUYodF9NMWYqN1Ek
dTVzWl8KemIqPjhhPGlBMW1UcjhYYDVDPlZ2cktiMiQoXnBaa2FRNEVTekBuKHIxK2YlWU8jfTg9
X21OenNhI1N6Y0NsIyN8Cnp2KCVEO003RXg8OGApNEJxejJFWEMrSEtSO09wZmFXRiMzfnNuPWd5
WHc5biF2MWFhN1Rjdih0UTUkeUA/Y1dZcAp6N0s2YDNeeF9tVjEhUV5eS0pwdGdVQUJCUzltb0Zz
TiRYPTgxNm4wJjJ1OTlQWCVRKyRmYTE2dVZoT3lZYD0xRSQKemlPZEMyM2EzQHAzMD1XMG1gN35S
TTt9Ylp3c1hJZm8hQXdnc0NoRTVGMmFncE5XVihhZ21qfm9SajckejFZeSZwCnprUDxjQmtGVEdr
QkNvJnl5ZzUheVd2d2p4TzZ8O1ItY29+ZGIkbld+YnRCQnQobmR4Q1hPKXlVaTEhaUc9Izs9Rgp6
PUJ0NzJAVV9WXzRsP1NuPz9nfjF4Y3g9dXQrTjMwdUBHdkhnZypTVFpgTz5haTxtRz11YFVTX2F+
MHV8ITA3fUUKekYtU2A8R3QxdjZgcFFZOFFxUUpeRFBfQG5zWklpUWM2dmg4b1VUTnViO3pTZl5n
RDw1ezdYd3ghNE1kIU51Zy0zCnpTKlpIemJ1cmRyV3p5TyZlXnlJM3FAfnw3ZHYjaGxYQCE7WChr
JHY3enhwUz5SMH5Td2kjKlRhM3B8eUp3NztpbQp6UktfKEYhU0g1ejlpPmgkK0hUKiU8MVQqbkok
dVRObDh9U1BtI0h2JStQdzxkal5vOERXIXlDRmFILWRyTlYyMmgKell1elpvWWBJNkdmTz96WS1W
Sk5BNmdpQ0sweWw5dC13Y1IzTU1acSZNLWFyem1ScDFsaFM9cyhmfEpuS0h6eDwyCnp6V3VvNk0z
ZUs2KH1nXjVGcX02USZLbWBuM1d4S0NCZ0VrYHB7RlYpKyQ8ezBEcVY0R3E+I2JRZHgzaChIekFi
Pwp6VUBEIVpxR3Q5d0x4K3V0MzAxRVkrbCFia2heRVhae2RDb15eYFVJSGlzLS1MdmA+fFAkPXtT
c1VMMk57cHFUWWUKekZffSMqazlPJnJVeWR2X0YtXmpnRXlET0FWWTY7LUN9QmBVZ3JKRT89ZEdp
amN7NW8xKCYoRHdXXkN6SWQ/OylzCnpET0R2XiRpNExMQlNNVmNmezdsblNRJHpDSXRRWHQwcTtl
bD9JOXU8RWx+OylJSk9FYXhmMlo2OGwhbiYwM0xTTwp6JDl1OXtYe285X3AhdDs7Sz5gMUFveSZD
M0FBTFBuTT8tUC1ASV85QE89Z3ZRcz47YWM0ZGhNc1Z5QmNPO0lmVigKendhQnE2K1k+U0xFPFl6
U2hiKGIkU3ErQFdlZCR8JFB8V0JFY0tSVHkmYHBHeTA+RV98SV43XiQqfiR8MGd4MUdvCnpBb2BE
aVAoNDkrWjJsU1hobVUmIXtHX1BlckgqUUtTfV5EVTc3QCZJTUZlMXpCdFVGaHIoTEc2WkpKVm9C
dzspVgp6YjAlWnZRSX1hdWNsWUElZkdLOClJfnAxJUBiblBeR1NxYnVeI2wmfV83ZVVGcEg8IzBC
fCRKbihmalImeGxmNz0KejdgQikyKGNYTHNOK0lldXQ2PWREJlN5UC17WWtvRXlVRDBjIX49Mik8
Xz9sWXd8eXJFRlI/eDllMTdQeWo5WkdtCnp1Yn5IbHU2blI1VDM3V0EjKzt6fGRrMjJRMDIlY2ZH
NCp9KyQ7fCt1WTlRaig/ekprbllQRmIpVnh8TylNX1gjOwp6WkpnJVMkMUhQclh1KldfJWAwdzBV
Iz5rPCR5OXwjP25Xfm5GdnFrenxKUElzXiNuXz9SQjZUPXJYISpCTWxobkcKeiVNY1gqSFJYbiop
Rmx2YXNuMn0xZzR7T1JoSkVQeDU3a0Vgdl5YaipGM0BZTWt2Z1hoJTYlYEFfUzAxPXFYKlZICnpi
YUxUQXNPVTV1Q014akwqOFA5fmZea2xmdzhDRDNjMEMjdUZmXnpoO2FhUzYjWUVBaWtvWispZTI9
Ni1XTWh8OAp6MHtWRVI9TkNzbU9mandBd1BlbShxSThXOUZSSC16QWVLX18tUlM7V3t9JDxvUHk1
V2owVXFwP09oTGl5Vj8ySlYKelRleEU0d1MoWDJySHs0ZSRXQjI+cjZVJTN7KDAxKWNiKmVTam5C
WmFrYiY7PT5tV2khdjYrcmVLRkd7LSlJajRXCnpxcWA+a0UjSlFaemA3dmIoXl8xdUBmX25LdFFA
UWdlVmVHVEpETXU0SXVjfWJDYyYzYThhK3lvKjFOa3NeNXBeSAp6SkArJChjb1BVaDx4ZWc3Jk54
KXM5RSpWZGR2RnZuM1ZjV0NzSjdxflM3OTlHfEs8fnlKfWZxKSNAQ05Aa2BSY00KelN4cCZ4VitC
IXIkU3NBUVJ7Zk5BSV8jMTB1RntVYDdAbE4hMTUmfEpaUHZ9fWdFdXlmek40fTlRMU4/TkxrWmlS
Cnptb3RkfDNKS1FSZ2tYJFQ1JiY+JT9CTipfJUdOeyoyKkJvIz4wJCNXbyRkYVAwQmArRkk5O3NG
d2g2UVZ7JHgjcQp6cGJze09SXz4zY0NubHdOODghVWtoKE0oQ0J2b2A8aC1qYF9zbWFCS1VtbmM5
PWcpMz1DMUtGYCghb1VweEpyQlYKej5Vb1FFYjw0d3RYLVBVYmh7SSt7Mj9+PzFTbDxkI0BXRitT
e1cmPEhGa3Z3TyFAPFF2YitQbnlZVUViR3syQmlmCnplJn5ySzlSIUs+cnJwQnIkZTROfjd+blJh
QnRSK3hPWWQ8fXViKE1LP31ZcjBxOUhINENERHI3YTJIbz50Nk5hJQp6YkE2aiNQTjF2Iy1GaCN7
PXtqJm9sd31wLVJ2TGBNe3xyLSZ3eVpHbWkmMV5kaDxwYzlKaWlqN0l7dklHR3dYY0kKelBNQXt6
NDZxaj1PMlg7fjVxYik5UXIpdTl4ITN9Tmp9MyQoVDQyPnZgPSMmUnkkZ0t1XiQ8NSg5PjkjQW0m
JWVsCno1Kns1anhELWM/a0VneihOM1VtWXt3ZHZXKTtFcVQ4ZWh+azd+RFk/YHxuRkMleXtHWllm
RipCTl89NSZII1F0egp6VSU5cFZnP0ZkJVRwWXFvXy1+b3tZd2xSb3tNJEo8SXg/YjI5bVhhcjNs
I0gmanREazdJeDZZazlISWJRPz59OHkKenYoR3dUb3YydW9vQmRWaXR9ViZkKXdUcXBvMEcpclRW
ZS0kYkNiVlVUbUw1UntMdmxjKkUxU14rQkVWZDVtOFc1CnoobHl3RVBnST97IUo/Xyl2JDY5Z1Iw
cFRIdHFPJTEzcmR7NkIzNl4xYHQ/ZyVqPCN6KHo3NDF2THp7RFR3eSp3dgp6WUlYOD0mK3M8dXJe
TjlHd2kkJnEoMlJCMkFGVlhgbTFPTmEwV30+WkZsOTN4OU1WKFYpfC0hdjFzTjVkZ1U5eU0KekYr
ZyNsNTU5KipRYWFVQG1GKFRNXz14RE5LMllNUFBjfCFpM19BZk5VQyhlKlBlKkV9TylOO352KW5x
SChNNGF9CnpSe3ducClUMjlNYDFnO1dDSns1Mm84czhTZ0UqP1dwezlBaHJZK3lOJUY0PlYxKkgm
Pj1DRlVrXitScCMlRkskdQp6eUckeGVyc3ZHaV45SGpsXz1sYjJyOHIjSylYR3FlRz5HWFFZeT8o
MHgjdFZKYCZPOShAandJe0k4OHB7aEMqNEcKemdlM1BhKmsheWoqTilFaWNsfC1AYy12TjxUbTQp
WSNyWmdQdjVzLXw2a2NGNzhzIXM/MCstUyhhUE5sPT1vYTQpCnowOExXOCRyNitBVyo4d3t6Yz1J
dUpLb3ooS2UrQCZNaGlGa18kZXpkeG55WURXbzlNLWJyUCNGNk1GNjcoMTt0LQp6NVN9NjYkT0ol
KUhDNWpeO3E4LT85Uk42KmEqfVhGV2EwSkJYOTZQdSppUkMyJERrZTw3IX1fKXttPSkqaX1oXncK
eiVTP2pEbkhAYG1Raz1sfVUoZXUrYTs9fTRlNTF6WkhYS0d5Q2tATlR2cHV2MypoPF9NWHctMWxZ
a2U3Nk08O3ZiCno/P1hZVWU3PkBYKjlmXilWVjgjVU5wSUx6LTxtdHE7JHhxRml+QEYtVGAwTXQj
ayExc3t4fDUpckdEJE9yciQtcwp6PnJVUlcyRWprYiU9S0htZjtmPFZkdTg/VE93c2NRTD4lY2ZK
K1JBM3M/PGIydklyMFpfY34xKnBrRmVlPD9teTwKekNAbzB3YE9CdXkrXzkxeXZzSiZVX1drXylG
NiQ4amx+d1gtY3FEZkZIViVYRm9+PVEyVyNqTnpsPnFFN208TzAmCnotbmFwYipSelZMWFQ7WSpX
QkpmcVVhViQ5WXE5bXR4WmZENFA4WVJHTUsxKDIkYlVwe2VAYXtXV1pDaWlxZiMjUQp6ZV8kRyV6
KUglNkhiYlJqZz18MmlWP3dnZFIhWlIpcXpuI3BPfEEjbTVKN3ZDUSZsZUxsOE9xdHlTZjAhcVc2
bkQKejFhKjQpTFglbkhxSi0odWkpe3B5QHY8bjcqPj9UX3lJRj4tcFRsXmUrWU53Ul5VYjZ7a28k
Qj1ITnlBTCFXXntECno/OytQRjB2TTYyYDFOLX5ZWXg1Zzw/d0pPd2BKajhfOW5nJkVXaS05eDNe
YjQ0MDckNlNqK0k5ZUYyci04UGxpVwp6aDlHSyV7aHpuMEd1JjM2U3slTEQlKDxIUVcjOW5WUmh5
VENfRi1jV1NydHkrQ057ZHdgbVF9d3E3ZSlGO0crdFcKemowJX40VGZnalJTWCFVZyg3Pk1oblZ9
OD1wYjZoMWI2Jk4jdDdAam5wTkMofF40fCo1TGxGbFo8ezUodzJlT0NiCnprOHh3OzFJSDB7Yjwk
KVp4Xz09YEx0SkQ4OHlnen48MEpwcDwxPmA8Zzx2alA3Iz4wY0ZifjwyS1Q4VWBGWGEwRAp6OFVX
JTZhQnRvKyMmdnw2bUw4I1g8V0V8NC1sWHFaPXFxb3hGK3p9e3Iqc0J9Tzc/aXVRNUpEQGZCT29N
e2lwV2QKejl6VHxMaXxVUyZrSWRGUXFgZTdzRlBSVXxNdX4jZClfdih4I2tYZyQ9Sz5DbjRLaSM3
djQyYlZQLUhXSmAhcjwhCnorQSN+N0Y9Ny1ue3p8QnJHYSEhOUQ4c0wpZn5NYz5fdClmdWM5Uzxa
SHxsSDVNMVZVYTZWVmJ8SCtoPFFTOzRSUQp6Nk8qfmVwZWkoWVhZODlvOHlmXzF4R3UlYW95PD8p
VHtIV34kWXs+NExYP09hSTlCQm9QV2k+Zm5gY2BtWW1jeiEKejU3QjQ+I2prJntQRShZd0wxd3BT
ZVVAbllXZT5KOyopIVAxMmtpJCp1SHktc1YzOXRjSmppfmFCWF9jQmZuOCpCCnpBeV5taSg4fkko
NH18VCpEQk81akdpS3A7dW4tJW8mOGlIMTB0VWp1KFd2bjcoQHdYSkVaNDV7cXEhcCVSRHh1Qwp6
SyQhfnhiSURPS1kyZCtSUzY7ZUBwMGFYaVJ2SUNnY21uYDQydnxwPDljK0huJD1oZ0w8Q3E+LUZP
c2pBMkJveVUKelMmOXheMipSRUhYZlpkPkRBRENKITszQVMwQi08Qk42JnlEbU5qLTdqPCM+Pi1U
N2FSI3c7OW0lPmAoZUZWbkJGCnorYUNJRU9pRG9hRGhqVFgwKipwRygrJW1oZUwoQipSdTktaT5J
MShzKU0yfTNzbClgLUZuMk13d2pYbk47e1RXUAp6YlI5TVBKOFchbz1BPSNkKGV0aUBGXmUtIUNA
OTxVejhYSSUxbXk+QW0zM1U1Xl90UU5uaT9MeWx+LU5PI0N3NW4KeipGRXdPRDZXR3J1NERmS1di
dGxtM2NSQDZQJmp2dXt7UyNrZTtzVSYtM35oR05qfWYxdVJrbD0tZ2VGfUZrTWR0CnoqPEomQDBa
PlhIezU3UWl6aGglUi1gfm4oUTJhUkhYX0xiUyN5QUJWNyZMNVJtKk1CR3JnbW15WmYraUxRIyY5
SQp6WDZoQmRwIzxXKmBgfCYjUE54NH1XRVEqI1dBVjE8Pn5vRzgkYVc5ZlY3ZylJKFJfTjQ9RGhS
IWNYQGFWRk1BKVQKenRxR1dwQDNXSn4lVXl9aTBlZjg/TmE2dzUyZl5fNzhnOWE8YjNKR2EtI0xX
VFRLY1UlN2JtQzUtKEt+Y1dPdVNSCnohUihedENMPUh0VnEjJVVeVTRaNTwhNiNUU3paYnZfe3dU
Q2dibShmZmlhaHlNcWJOZyN3Qks5fDBLJj4+PHI0dQp6JCl6KWF4aj9GdHp5bk5NJX1uTjQ7QmlZ
RCtIPnsyb2lpYWRwTklLYFZGP1dTNTE8RmMjKU9galo5TG5Vb2tjYE8KemxZb1dqKzc7JEtCaD9z
KE1uSCU9SjtPPDZedWg1S0JrM31MP208bVpsaSFUejgyaU91UHdES2AqY3goZXxLITZ7CnopNHZW
bjspPnp8NEspKzgrWXwqI2d+OThmMWpfbUNVXzVUTlRNbldxY3ZOUDZjVVhNUHxFeFlFZ0JgSElG
bjB3Rgp6LXYhNDRSPyg5KDxNfn5tYEdYZm9eayN8MEd+UyMoKWNiTEVndmBIQjRuZFlneTU1NiNu
S0VpJGpNZ0MhaippQ00KeiNaYlR2MHQ7cnxGbk15JXNNfFFfRW9hfjUobHsocm0oRHBhSShqWlJ8
MDU3UjBrbyNrLSNDSjhrI1Zqc3NXMDQyCnpuNE50ak8xclFmMHYzckA9anZ3NjtYMHlwWkFTc1Nw
dENKYHZpeGBvYGFfdFheNGEoKSVyYyVGV3cqT24ka2NlZwp6YGNNSD5zcV5RPVV6aCZWZkczYlk5
UWE+ZyVeVnJnY2dkMSpuYmt0JCZScn5zMk05a2I4cGFpbEtxQzFzJlFBe3gKempMYmJURTB9dWs4
ezM9dlEtczBMP2FTME9OcUJlYiEyYG0paW1NfUg0a0x1PGxVX259bVdiNklyZiUxeE1uWiQlCnpG
ekRWa3wyJHE1T3QpKi1qRXA/SkpwJXlJQClsOE9fSjQ+O1U0cz1jTVRWd0BqdUleX3s4dXVQJjdP
QXxMSUhlQgp6UzF3M0gwTXdFVz5hUndoVmBAdHFfYT1MckUkeTl5JmAye0dGamBfMDcleENhKEtq
K2BAY1IrakYmOCp5P3A7aFkKemFHQiVMYGVZUTB1JkhBTFIpZ00rRFREYGtjT35vKTVkYH1OcUxK
eCpfZismKnchQ0I8OTJ8NUY0OStpX2h4Nm8pCnpKMXZtREBHYyFKUl4+Slk7Q0dUa1kqNHp6TmpG
MUJreStWWnhHdFkkRSpnenxiQl9wbm8xNSNwUHpYbThhSGlfJgp6TlczREphPSQjZGM3RDFMZmVm
NGt0e0lGaEpIKyt+JHd6fEh4ZUI/cVQ4a2JyU2t4fGxeeFBiP0t2Mjl+MV5vI04KejtuWmcyMGVl
UDBgVVRmPDtIWldJSXRNU1FQU3lwbTh5RDVXQ2N1a0poKDdyYkJwUTUkalY4WiNBKUZRTmNZYVhh
CnpJNWFtR1dYTTRzZTx6I3pOJHVoeDAtIVNhenk+bStCXlVyY2lWRiVoRCFGNCphODBGdzJaYzhH
d3RNPEB1JXN3Sgp6UnlCbDFmdVkpMj9tK2wkU1pEUW5LTjRmdjRab3VsY0VgI1khTkp1e3FlS21l
cXlUKmFLNk53Qk1gKHEhMzNwX30Kej18KjhTTjM5STlkTiZVZzU/fjclMERDYkM0RXIhbXA7NzZE
elgtRmU2Zj8jQkh9fUZpU1VAU1goUU8zdkd3fU1FCnprX3BUcVp7cFAkK3wtUXMrX3s7Q2hLNTJ5
M3BSWjtpLVpMQWxOXjl8M2xSU1FIdCl2QzlVan0mKXhHRnspc3sxeQp6SklNRUFLX3E5O0tIQ3V0
NExAVHZGfkZYOSl3M0hHS0dTK3V5Zig0bHVkb3d8QDBMdXcpMlM3ZHt3ZkpaZzQoKnQKelM8OU5l
MWJXN1BoVFJ2PTlHUkgjZUlkI0FVUVk1bGImUlQlWn5RQkpWWCowUXNEejZMN0xKeThWR2Q+ZXJy
a09lCnoweWN+MT0xQDtzc0ItVlhNLXIoaHB4VmMoSHp+JDx6VkMwN20hZEI9JTRUTH1JPks1OFBz
KXIoU1lsTFo7eVM9Ygp6JF80Y3d1USNuMSYofTNBeyVaUDZGUmt+fmBDME1OIVEpdHxaR2ZTfV9B
emNmSiFNPCQyYVVzdWE3eV9PUX5eQmQKemhUcnpkM2JyP2BudkxQb09XVGc2dk1ha2pXPklhe2ZY
VzJlUE9eTXBRQHs+Mzxxfk9ESHtTeiMybCZCSUY7UU11CnomfFQpZypjJDJiJFBZOHgxRDlIa2hm
c2pDZTV8Z3AjdGlOMDVMcWhTcSY3QXpGKjctQHBGM1pPKkdpTTxgQEtXOwp6R3ElbG8qdjZ6cGhs
ZHVGOWx0e0sjM1ZSfWtBZyUre3x+PzxeUWVva0BHezMtUDB7UjE5SkpzMVctUkVLKFlMe24KemN2
Wl9KdSNMZ09MPUdVN0FRVz1+cjI+aWJhSzhXdj5JZERNWCowXyEjfHwmUj9FTWFRZzRtSSZzJGN3
b1dZPCtACnp7M0ooRTs2X3g9MiE5azhNTDVnPTBIVXZwWEAhMFVMMyFmcWJAQ25yTztWJlBaKlNf
KyErMFYjTk9nYzkwQ1Jedgp6YXFhRlA2eHU4QEBgcVBfaCp5MD5qT0NMPWJYKFFMQDFqYHwybVNy
X2lobFhXPU0jMldHdHRYPXI7LVcxQF5BQGsKejJ6VWpsT35QfVZIM2VjT1pNQEdhO3E+KWxLUHhW
N14xSlQ/Y080eCZjT0tlPD8oIXs3OXtTe2g+KUxucSVuSiU/CnpBZXorQWhRRm0lbG09b19LVGxt
Y2IkRkcoezM/ZmYme0soIyRVZXVPakRVckw8Y20lTU1GMl9ZXjZtRUA8I1B3dQp6dDAjKSY5PVFa
ZXdNSGdSXzlAX3wlXiFUJGoza0pVJGU8PDZpO359YUJucH53ZzgrSXUtWC1FbmR2cUVWeWclT0kK
eiVhdWN6anEhWWhKVEJtel8oX1RgZlprZU5sU3JhJXs+I0AyS0pMUHc4fnkrSTt7UVIoS2oyODIr
b0xTaSV2cWlTClA7fTVDZCltQUNGVjtTOylIRSg9RQoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpk
aWZmIC0tZ2l0IGEvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNs
aXBzZS5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMC4uOWIzMjJlOWUwMTNjYTFjYTZlNDlkMDc1NjhjYWZkZTU5MTdj
ZDJhOApHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTE4NDAKemNtZUlZWEg9OHY3Qj43S2oqSko5
bmQyeTtseU58ai1rVVUhailTMl5zblN0STFmJkx0QXB+QEVhN0cwKmZUMUtICnozUENgSyhuNHJL
UUlNYHdBd1gwfUF+bGkjQSVyQ0Zvaks/SHtRaUZIVUdGK1N2YTw1emUpaXQ/RjR3OzleNEI+Ugp6
ZCUxcmNgVWVDLWE8SD8leDxaaDJFKEEkY2Y0PlZuUyZ1SlEyVmM4bSZVenl0WG01dylCaD9sQz5A
cyskNz1Qd00KenlqJTJAYzt2O241RDFBeD5WLXVgQWM4TihneT09YmclKyQ+QUErRXRBPXQwfmE9
KHNXbyh7ZD9oczNaeXYjO1NpCnplUEVVMHpXdUg1bCFHaG9UVEsmandeeDRucDB9JVVPOHZucCp4
OUltPklNRCRgUEE4RyNrWEReSm9XTzMkemh+Iwp6Tz9xWWlRRSZnfHBfT3BLej80R0dmeHs3QStK
ZHZTKmd7ciU4UXpqeHV6R0wzaWA2STImZDwtK21WJSVnOHFiSzYKeighaikrbT48QWdwcjF8IT9T
UDxqLXswSH5LX2Ajd0pPJj45QHhNUipBOVRxPWckKUdWSHtZaz47PyFGTDMlaCN0Cno+fWQ/PG1g
bT0xdCl7SiFrdWY1UGd1TEQ/NXtjck16cSt0OHNeZldVbXhGPkgtKnVCZHh4VSo4KzZ6bGhQdFAr
KAp6Y3J5RiliMl9kSjQqWl4xOCtVeml0dUtFcEExM0Q8X04+WW9RK357fSlZVFArYjxsIW88djhy
cFZ5eHhkOEx+M1QKelpSNEN2K19SVFJ3JDUhNmlMT09QM19mYjhuaXkmQEVvaXZiLSFvY1MpQjNj
d3J8MUIqaz9IRUBoQTVwcDRZandLCnptND9KKzxXbWpjUi0han0pWTdWRCshKCZqJXErd3FAXm42
MCMqTz9gZ0hick1ebVZEe3U1TGxpQzJyZEQ8Kjdtcwp6OG0pJGlASEltc09SR3JjTGVyZGgrdkpq
KG0mSGYyM04lVjdzN3BRPyZNdTJ7a05VejBoNGFJeyMjUXlFYT9iblcKelhnMVYtOTkzQVFtNmA7
N3Y7K0FzUXxlbHR7VCtoRTxpayVgdjVKemVXYUo/KEZpbEwkaWt0TnJ4LV9HYUhlQyR1CnpMPncj
TWdBejh9Ryp5Pj9TKCQ3empjQnJSOVp+SnY/ZCtfbWcmVV5SaWAyXz9NQCMlUDYmZ35aZ1Y3U1BJ
a1FhdAp6Y00lN1FhSSE5RipOajMjRTlZQmBKJnt2YjR6V3J6SSY1JXFxbCQ3eGMjRj5gaiMzaTJs
Uz5EY29eUU5eViV+I1YKelJRaCh6Kz8tVnQ+WXQ2WG5aQEh7LW41TFklVSF1REJ4YTlDX3Etb2xf
Tkcybl5SbFY0X053d1BxKW5QeHtRZjs4CnpfX0taSXJ5QmA5RSNMOUUzTjBvSSo3TUp1RGtBI2Nj
bElrTCNiQTAwWHMjLVVkUHdHVyo8IXl+dWF2cnxrWF9vMAp6QEp2fXEjLXtTIWora34hQCNZeTZ1
VCswPDsrX2t2Sm9WPygrR0U3JV4oT1p1TDJZbyUmdmI4MHB6VjQpUik7PDEKenhxTSNnKH1RME9x
JTRCYHVKXihDcFJAekEmUz5CdCNLOG04Uj1naC1kbn4jczlfcmdANkQ0b21xO1hZeTl9JEJlCnpR
enhKOVhnPmxBK0ZgSWx6YFdUYHsrYmowUE8qJmVYbCo/LVh1ZWdecn0+RGMqTn4wTGdWZzMhbUBT
R1BgVEN6dwp6ZyVjUFpSZDQzPCZPVHU0NHI9d3hwaTgtSF9qXnBHUURkQzVreDh+WUhaYW1CaSNO
NCNQWTBvOzFLcFMxdkZ9RH4KejhQVURSc3hhQVFNen1EMzw7KHJDSnlqREFVWkhWaVFfYkEoOEN4
c1crZD19aG8yPTQ4PmREI3hXdlV4VTlyVmZ3CnomJiRfdTZUI3lheWhEJUxVPSRsS2hWfVNQeHxP
PmRvenI4dkB1bXdpWEFwPWM4SlArakUkQUI+TTBOSSpYMThrNQp6TSl0T0ZRRzdoenhHZVBRK3NR
cE1XRnk1eDR5Q1Qkcj42PDFVT0JzTlhXdWF8dl54fkU2UFEmfFV7aD12KnRrfVkKeitCKEJKc3V9
VyRYeXJDalg5e3lJY2pzZyFYbWlXVntqKHk0bXtIfVFwbzJOPkowRGpSbmwxakJ5azJBMXptfUVa
CnpoKGUldTtpakAyPW1UYDB6MWVyLV98eFAkSDYlU2R1R0V6UWxlJUheVj1tPDBQamc5JXYpJGI0
YnhxeFR6R3NIMgp6Yi1MRzZnQXM/bGQ+Wloqa2goMDdAVEh8YCFGTk9WZiVxVjVXbzNFeW9nJmR2
JVBORTk2dCp6OE1+N24weE1PeHEKelViV1AzbCVoLTg5T2MjMk00KXB0ekpvVD5CcmsrbGxMaSZe
bGZ2fHgpYHFlZEI4KzJaaHE3cjZAP0RJZmhJR15ACnpzay1NO1RjSDtHQUpDSFMmRTQlTyMtK3VF
XnlXRXZMfSN0T2kmb0JCQVVaOzh5MHMmZ3puQzd1KjsqODc2UXFTNgp6ZytEPnB0JHtaTVp+S1VV
UTVKXkE4Nn5vVmp5PDsmOCZrcnhTfXxic3RAPldoKng/anhUWENeT3dzaXBUQnFuTygKekhnbyRN
Y0FTLWFaX3MmNVU+d3NpTTlfWH50QXdMWUh2WjxmcXkxa2VnTGJAdE9SXj9zNVI7SCRuSHA8a0Ah
O2tuCnp1NEtzMEtuZHFLWH50WTE3b0w8MWRATn4rRzJpbjI9bnZRZCtaPXJTREAkMFVeUkIzdCs0
SGZLQ2tTOEJDb2VqRAp6eSMxdWEzd003dWtvdV54NUUwSXlneGNEYjV6c0NVYCFwX3RGc2pyKTl0
M0lDdlZgLXhmKFMoWkpAKDVfLXE2TmgKelZyfmZuRkB5aUV5ZV8pOHk9SnNMSzM9WFhnIzlUZjBJ
QDd6YkgoMDFyKSgjNTdiTXtFRGM/Kng8N2pLPGg8ZVQqCnpKPk9kSHQyP3RidUh8I21qO1JFek5w
cHxybFRjN20ldn5NbWswajNoNHZ1S0pENmdjWlFkNHo1anZtO29RezxsKgp6ST85eFdIazVEZks2
JnY5e09TUGkwTSVnS3Z+Oz9ZRn1hZWwmR3I+RkNyUiZzMWxiXzFla2ZIfXdHekRVeU8jZmcKeil+
SXdHJDdSeUQpb0VMVDNOeTgqaGVmPHlQLWQyN1JKNWgyJm82JVNePmsrbCktUSRFUHBPWVFva0kt
UGFWUU9rCnpMK3YrUmZfOGtudCEhNm4lQz1kYVNMPFotM0ByMTwxeVBrbEBsZC02cHUrVzI7U1F6
QVl1eVNaI2wlRkdHKnRtdAp6dUFiVUQ9UVhjPD09c3A/fEJqaTdVbjtqbWNZZH5GRkNFaChgM08j
P0deS2NXVG1kdUQyUHJnYl9COGdBaCU7QmwKelptQkozVHZHWnZoe3BOKG1kLTtyZ3c4O0hxajA/
KD8meF5CQldrdD0+dExKMCo3Yz9qZCVXRShid2Rhcz0zNjcpCnpJYFgjdyUqY307WEtPJUxERHE5
US0+PE9+K0F4PCQ9NklEXnRJNnZ4YSZzRzxqYEJhK2tWXyhoOSoxK0tBVkNxeAp6YlEwbWkyYGRH
YWhNJjd2emBJb1FLJVpESSQtNVEqMCU8aWFURjVSZCY3U1RHITZydmQ0NlFabD8xcSUkS258bEIK
emJ6IXd9RHxvKElDa1hNJHdpbnl2KFpmR0wma2d+RjBWdnc7KDJScSlhYCg4PSk0akQ2UW5OKGFz
MllIdFRENDs/CnoxRnxmWVJfO0w1bW0ySWB1ZU5nUSZLc3ZDQ0U2RSY3PWV7KmtLUjlzbGFIQHM1
cEA/VUVxe1R8b2RHM2FTZ3hESAp6c3JXPFZaPChCRlE9WXV0OSFNeihtPVBUSj5ZXjstJkZ5WXIy
NnA+WEY9TzxRSmFrWS1AKC10bS08NWQ/aG01QT4KejMjQDNCcllleFotdFYyRGpqTn5wRj8hYjVV
aX0lSD1NZE1RbWdBQVg3ZG9nZm5Oc3tLSlVeX3VpakUzM2tNKUtmCnp3V0JwUWBPSGN8diR1aERu
VDY9aF5IJE9LZjU2Y01UTDQ7ITtwc0Jhe2U4Zj1eUHx9Z21kSzZtQTdfbm49OW1vJAp6aXFFcXZF
c3k8TSo+NEY4Qmk/eCota1YoVkpDLXZ3KSRtZjFuNm5hbWFsYVNadVdZTDQyOCMtI29va2hueClG
T0MKelYxST1NeXZSNyo/QGB0aTElcj9UcDtIJDReR15yWktzZXopRjF4Jip1e15KSUBZJjEqc0ot
ekJhT3NFaFM7VWgxCno7Oz1XM1BOaTclaTNVJlBTdHdgPF53YXhTS1YmT0QxJUE8Q1BYPFViVyVY
Qn07Pm9AO0NzazhEP0hxQChNNUpmegp6REphTXFweX5hdXg0V3coVzFvV2A/SCN9eVlBMCQ/NCFf
OyZiO3F1XlQyKUJBSHZxaSVuK2Z2RS0xJTlmXjI/NWEKeihLJHFFc1BpeHxGdj5hbHNza2MmYGRP
QFp4akljfHRIUl82V0gxQVVDcX1wb20pTFpNQFBibWVkUVdAZ3xMfHs7CnomXiRXJShJZ3pXV0ck
IW5afSg+Y2gwVWZfWkhDP05LdmF4QWVMVl8mYHlUanFJKUMhTDFzRGh1S1dOX3hyUHphdgp6Xmk0
T2R8MnF5ajRvM2tHT0dwRFk5Rl5FJEl4Pj1SMnhtb0o0YyFUQ0R2THYpX05ZLUB4UkRQfkdnOGBj
cTV9akgKejNtcElKKTMrZ3xTZDtObE9YbWE3IUQ5Z0FzdERzYEJ9PWBtNjBgMlAkdF43PjVMYkpO
P2dpQ0RoZk1YNShebiZ9CnpQT0B2az5pe1ooJFhoQ0hvczZxc3FWN2ZAVnZ6ajRUeGU7bTtwUG1P
QzA2TiFOdGpxM3l6ZU1eS1lXcG0qJk8/Twp6TGVhMTFndG10djE2eDJiNkR1KX5fMGV+R09SKVRY
TzBSWjhpVHsqSE5TaiMhNT15YW5nUnBTWlBCNW48a34hNnsKel5OMH5LS19pViQqa0JEOFNYSVF1
OWdya2ltO0IqZypvUHFEOTFjWSsjPzhIWDZuLUNRSDNuTEx0WGkwezRmcGRACno1d1lAZ2pWcH4q
QSVpd2ErflNlO3cxTEE8LS1LWkNtUz0kN1ZDZVpOK0d0eEJmQ05pTkBJV0g9T1gweEFsQlMrXgp6
YFB7U0p4fFVETURKTT88Q3RaSzdZX2g3VXJ5Xk58QUhUJG58MlRqa0RoQ2piezNtT2xJQURGcmt1
JC01TTY3az8KemBpcUt3Jn4pVmAzWnxQUGhnQVN4JkVkb0Rndjl3e013dExzO0YzSUZvRSYydD5i
YUdkeWQ7e2pFUyl6VmRsdENYCnorZTFOaztMaUlDV2RGI0NBLVl3I0FNPG1uRXQwdnRBbEdBU3A1
MFN1elQ/dmE1VjM8RTZ4VkpOeHRiUjI9WlZGZQp6Rk1zT2AmcGxWfkVwPWwtOz5yKUJ6R0YqM0hm
K0o2d0JgRVAhX2gtb241Jm5aQloyciZrZmY8U0VzRGsqQyleU34Kej9QT0ZoaFAxX1BKU15BYlNJ
eFg0bDNjNGR6SzRfYDJeTmZhc3FfcXpaUj4hNHdEUUkrRyE+a3pvfTlRPDEyQFNECnpIK0VrWUk2
QGx8dTZFMlQlQlF9b2FqSmUtVSZ0TlJ6KDAwUmNwViFaXkZaJX1fV2w0SVY5NThOSDljUlh6M2dn
eQp6P3loQnQ7SD0+LVFBemNgbTdZdjUmQStEbm05JWpYUXUtT0Yzd0V0YGs5KFc4QUFQXn5QVn01
STAkJHlqYF90MDUKenQtczIlQGhZPElBMysyPW1saDh7M1ZxPT5RMjUwTlIoSy1CdnZBMCRfRTUw
dmdXYVcqKkElfjJOPF5LTWgteFMlCnpTPW1rMUJ4U31AQWBCbD5iNXB+XkZQKWk/OSkwUFlIU0Rl
VT83IXBDNEM0cWtFTSFrP3A4Q0NHRjFefSozZnZuZQp6d2JoMSlXZElAdnY0T15vbz5yPnsjXmk8
Xj82PUhiZXx0OzFEUX5XQiV5ZmxraU1yJHhtN2t3M1o4TkdPZU05O18KekM8X3YxP1VqfEElNHZg
U2J0N1lwTDdoIytOJChNcHFyQ00qUHhLeVc/QDhjfCoyTTlRaFYzVnFYX2VXeUBrPU41CnpeSSFm
UDNOSmlReEh6SGhZLSh5cmpFeChVT1l9bmpeellHS2pIaXxDelczaXU0ZWN7fSlpcGh8UTAkaUJW
UnR2Kgp6OUI7KkRtVyVCIylRT2pyJHpVa3YxXy0qZjl4b3chKEE9ISpXM2I7IVEqOFdqJEBiYCFU
Wk1zVWE2OyRwdjk7X3cKekg0fFRLQSFgPzRNYnxRQzZkNThvQztwRVcxI0plbnhgRTJxQn0/NkZP
PSk8VndIMCt+XjF8fFkkbD9ZbFJ1JUh7CnpYKDEpSy0oUyh1WnpXMDhpaCVjamFMKEVnSmlxX0Ur
QzIrTClfSkYmYytDa09AQCNTemloKTQjU3w2YypZJjBVcgp6VStjZntyTiRMQFk7MSg3Q1JAMH4l
Yms1RWRyYkE9T3dZTVRZanF4eU55WSRVRyluTGVHclVoI15VNnReQDVZYkUKelFXbnAkNDR0I01I
enxQQ3xBOWkpWH4zYGIhPD07fjZ+VTJPPW91eUdIeEZPMEBvelc3PCl6d2hSJCpTKVNAcW9WCnpv
LShyUHt0QUxVSXgoQj9WXnJFO0lHenwpKGJLMXtWZEM2ZnMqNkEqakJufCUqJWNjV2trVT8mQWIm
ST4/OW01SQp6O2wwMGlHNzBrY3xBfWladl8td25tTj09VHglSDVtPmQqbCo2SVBCSkd4VXImISo4
MD5DWWpvVXp2PFhCYnJpZFQKelIqUU8hYmMqI3haNjM7SlRQKGU0eHRnQzchWWk5ZGE3SG4qem5p
YiMhe31MZE4mb0ojMShASUtZbD0oI1ItUk1ZCnpIKyRhYTBebT9mI2NYTz9oSHtuYF9GKD1EdEJR
T1ZLfiZDYmEmQGwkKmw9UHg9VCYmLSZofiUzKFg0QGYzaHlgeAp6WiVXJSQrWlp3aTBFRn1IezZN
fnxDSlVaTkZjblVGJnkwSndld0w0YFVDOEg1ajtSQCE2SyhEMHtjen41NkJSYzkKemdrJSV9RSZS
T2xIM31YUDhTR01NayZxZGljUER4cl55dWd3ZTd3OUliRCVKQ15wTm5lRFk/eSg2bHI3Qlo8O2A8
CnpZU3lLR3ljbH5GeH5tfX16MTU0OCs0fkI3WUZAKytmaDVfQ3BLdiR8Jm9mYTJqZldEX0g1UShw
XjRfdkklcHQldQp6QT8xKW16NHNVYGtLTHJjYHxxYEFQfC03V2VoOTE2OHBHLTlkbG9Taj59UDlx
NT8pfG9URHdyZERYOHYwXj51Z0IKeihDdkJEaGlvLWgtLV88MG49OHFZZj9KQWZSWGJpfU5fTVY8
SVp7RElkNDZzPHZCZyVIV217Tn0jQXlxKUlxR0MyCnpuSVJwKWUjZCtAcXZmM1hzWH17bj9sbGEt
JF5MOEQ0T1NFVCpnUDtpQExeJWt4cTVyKVBkYGd+OGpDbj8lQjsxdwp6KGQ4YWEze1hTcGZiPU1j
eWR9LVFsWW5HeVJyaD0zaWB0RF90Qj5keCklO3ckbkN9WCFOcURSdV9fNSZec34qcSQKei12IVlA
Tmk4VzxDOFlDSFdke2NVYUM5bCp0a349cDtjfiskZX1wSjd6TSQhflleP09YT0VAMHU9KSl8MU56
OFZACnpfRGZePG9ROWx2OWVIPU8zQTklVmdrTn5ZQXJmUFlud3prSzxDS0hfaiMyTUB1dTV1UjZw
aGh5NWA7RlJUaT8lbQp6MjBKPyErUlQ1JFROV3A1VEtTcDNDK0wkJjR5NTVyUVhrPFVSfFRWUUAr
WHNIUl8wTzZJZEFsU1Q9Uyhtc19WZjEKeldxSWJrMDxSTUtoZCVaMClwVDh5WHMlPH1tMWVONXRq
QXZMQXpQXzkxeF9HJHd1PURhe0t5OCh5ZGAxKWhWb3UpCnpYfSNOUFV3eGBNPmFqLUEpYjs0NzZT
d3Q0amo5PzkyZzU5TkcpKEhPN3B6KTlCR0BoWTtjNztLe3owSk1nVWNEPwp6Xk1AeGlOKmRmSkQ7
dTNzNng9e0A0TnhRNz48VmA2Q0ZFUT05MSZqQWkxSUE3anJ9ZCQmM0pveWtFYSU7M0U+fkwKejU+
fm5LQyMzWDVBfHMqYU8qI001KVVhYERMbzhgRiZnO1FtX1p+YDlGczd7YCFKfWRDaDZuNGBsRldL
KEtIbGBECnpEYSZOZzE+d0I+RygoaF9FeUptYmpIcFFydmFqI2pgUk5BYClNcmckXj5Yfik0KX1u
Wk0qcWpmTXh9dGAmczxeQQp6c047NmFBOUxBfWZ0WWk7SjU3cSszKEIxRTU2akYzJm14P3N6d3Vy
IUhkOUM+SEx1OWo8SjA/Yk4yREclMGgxKWwKemN9RWA+T1Y+QzloSCtqRj13aGdtXn1Wenh2MGFi
MHVMXyFVbVNAYjhGUnpfNkVeRV8tN2FGTEFJXzJpNHhoXzkjCnolT3VGRSRUOU0oKkQwbVYlYUhJ
a3E7eVJwdD4/NGNLMkcoNzJJRD8rdFpQM20pNEIkeWV0MV9CciMzXjVwREBuNgp6cmdUdGpaPnNT
cTlLcEZBaDhsVmttZ2heeUoxfkFNbGU3RTZ3WHR9aU1yVTZyKDNNJSRkPDd8OG0ma0xgP0I8cFkK
el5vSk57YzktfjwtTSskfTw/IUhTfEMjWkppem1vKTgtKSRlbSlYXndfT3otO2BDQ2YjNW99Zmdr
QCs8WlI8MFBaCnpfVnMxI2d1aTBYQ31GWC1yMGN2UilUcygrUkhHP3tYaUxoQXkmUGJYNUViczRi
U2pxcl49V1o4czNvMkdzS000Jgp6V2VTejdSdl5RcFl0YCtHU2czaFhZLXctaSlibGJ1JWVYQSti
cUIpYyhoVTd4Wj9WSHNAX0hSMyljXjNYfEFzRysKenRSYXoxZSh9PGhSRnZYQVAtdWMrTnk4MkZR
cEtoQD5ZIShNUHRmd31yS2kyOD0+JDF4bitjPGpJQSE/SCV0SD5RCnpjPiZ8T2lWNWo/e15tI1Nq
S2ttSW59YDQ/ZGFBPXo1WCRlWlB3NGZRJmxTIXJeUyNIQHR8Z3coZm9BY040WClVMAp6IUglTXN0
PUlUYj4oPSo7ZWN6TUgpI3ZyKGlJRmV0ezI4eTdqYFBZOFJ9QzJJNylKM1Ard0Z6anJUT1lHSClz
RisKemh5fG1VP2dpWm0+dj9fXnNaSkpxUmN9dDhtTWtzQyR1e0M/aXM3UDZtcEl5OT5Tc1h3bHh9
MlAhKUxSY0V2O0VECnpnO2BzIXtrSGRkS01Pcm80JlVxYE98TmdWKn5yYERmRVY3OyU5JEQtZTtD
T0FuMDtxZz1PRnU2c1VSSD9GUFowSwp6T2BVIXRhVG9OaTxgRVBWb2N7cDRzJTB1TGNFYWB9JktF
dDJoflNPSVhVbEFTQ2h2ai04SXRMRUljUyFfQHNIa1MKelUxN2xiaG1ESmclb2BTUTZLO0J9bTl8
TGxxMldSWGhPakU1Y3RlXjEyMHREO1NKNTR8Jmo7YSZoO1MqZSZ+KiE2Cno/REZ1Nyh3Q29Xbl5+
cm1rPEBzK2dleHl4WFl9Y14oMnw2Ny10eUchLWNFeF8kVlpwQ15NSWtWWmRpRjBvZkpGYQp6dDxy
WihOYnZxWlJfb241UUc0LTQqRnkocnVNYz9SYmtGbXEmYzVpWTE1O190elIyOE0jcnBLVF5XKWpY
ZTFpNVgKeituTDVDSl4zcSg9VGFOP1k9ajY7QkZFJmBFKD9RQHBsLWNwZ0xqPHQwNmdqSjVDSDcz
MWkyMkpWeEdIaShVei1iCnowP05XI2J0ZFgoIy00MkxjYGY8Tl85JW1DIzthP0dtKkJ7ZFhHdEI+
P0d8OSsyMF9QdmIqYDVJMk45bj4wYV4tdgp6Zl57WVlKcUUtUDlBQklRZis2VDF7fnFfaEttTERr
Tnk0WktiWW5Hb1cocX1fYHZaNEJqTWlVWiZNMlVaI3NhQUoKemoqZ0NuaH1Cd2RVNzN4SXk7OTFy
SzBlMW4oZjBPX15hQmVRcVpANiMwdWp6elRTO0FZcX5KXiZHbGp0R3ZEbXJjCnpCN1NeWVRHfmNa
cD8lViNEJUdeVXpNbFY5S2Vkb1BnVz1Ae2FNUStIWlR0SlBSSmhrdVE9P1o+Z1M/fCE8fiFGbQp6
R00yZzRMJTtLN0lhbWQlZEtuP2Y9U25+UnEzR3RUWVpGYUo8KldQKTRvNWNgaj8tZ0tQbT0zMSF2
YytvZ1lVRWgKelM5PVUyWCVpRTlgV1VfPStEMEZgXlhSX14zPGhud0RhPGQpdnozOVchd3J0PzM7
Qz9KUHBJRy1XVnc1ZkA2N2gyCnptUlVJY3B7QVM5WiZURzZVJHBKVVlBPV52QndTTUFxMmBhYG1+
UEBORjstblIpNnomTjZiMldEQjBjcWRBOWtqNwp6WnU4TmlVanEzSFVZJT9DdzVUUmkxaFk/Wm1B
XzBRdnBRNlRGfTRFIVVeKiVUKihNflEjO3dGJjNrJCFBIzJ0KHsKek9BU0tQYWI7eT9eYzRMYCkm
V01vWU0+Mn43Zl9xJVQqejR+JVJxVFRken59RD5mWHpDbH5pOyNHPDV2VyFSVlFtCnp1cyVVV2Qz
bT5ucDc/cUk9TD0zOW1WKUxAXlM4e345P0BfKntTQT9rY18tPmtIMzsjUzB5ZWk1RjBVRlp1JWhX
PQp6V2JpLXdSXzlwTU87aWQoeERMWmtQRVBqT2VFR0JHNkpQKGBOVnl5TDY7JjclelBQfjJPQk1J
MkBWRz90N1FAdWwKeig5fVk4ZSpnTTc+ejxoWl9XNmFFKjhjdWhNcXA8NipzYnt2ZG8jejxwQDJh
P2E4Qm02TmZRcFdkMD0zbWJ3JmZhCnpxWEskQjBEb0o3YFhLJFZgR0ZifFN2Kkp2VGczS3k7PEl8
PCVgUjZ4b2EpUUJKeVZILURuN0BuNFBSITwoQiF9QQp6dk9XSiF1bVUlcXgqbHhIRk5mUE15aURE
Q1pednE7aShFMm5IYT4xb2hfYEIhOEleJHA4T3FhWUReSDJVVzktZGcKenZJWjw9RWxaV3JBSSti
JiRIMypRUXcrI2NOc2MwNnRAej0tM19JSWE4KzdXenZVd1lTZUZgJlpnQkc1RXVCK2VNCnpoUipF
PWxqeWRoaSEjKV4kRW1DOSQjYX1jUUdsUUFxQDRMb0YzWHh0NWskMExEeW12XyNvTTNka0hVXlFo
WXh0ZQp6bFFfPzRnOVRSbCMtUmZhU2N4VWQ+Knl3NG5feV8xP2x0dVNkWjdTNy0oeilheWlIRnxQ
RVBVUSFGUDVrVXlIaWQKekAqNmY5RnhJMFkxaU9gTDx6b0BMdjI+bXM4Nkt8R1dAQkxSVihgazI4
eVhIbEpJP0tBPT4qYF9EV2JHUi1VNn5mCno9M2NwKkAxMUJRWnwjMjVeNW1WZHo1NEVKX1Imb2A+
RkxnYmNyKW1GJWwwbT9hRSR4I2hlOE9nQXlVbVlse1pjOAp6em5pME5LV3pfXl8oXyhGM3MlUndz
cExJPj9AIygqcXk5NHVOaktncWcob2gzOW9TRSZ7NmIwQHR3ZXlBOEMhdlkKeklKUzVebTllISo+
Um9va3tscUV3aCZXKVVaTGdmTF9VRUE4d3t7X2dFZk4lYzZNKncjJCZPQnJ5bTBud1MjNnMqCnpu
dlVDI3pBJkZLUktoZWRGO1J5I0xgfVBYeWYhO007QmxHN3RTNnpJWFYlaXBrNF5BdEx5VFM9ZCRw
YnxZIT9fKwp6Q0hNZmlLcDJHJTs5S31MeSZQdCpvK0RQcnc/VzVDeXRkJUNPMztvUVl+fFRqUHQ1
U2wqfjt0dVViX15PaDs0N1gKei1NQXN3VUpRMVhVVSpnVz1TfUFxNTJKcH0rcHExbDlJS2l4TjQw
dWVPSmFXI0llIWpwNldIKjNrPD9KflV7JXQkCnpTMW0kOXdDWnE1USokJHlYeEYzenctaFd7aSY2
VVQmTHstcmUjY2MlaGg8blliQ25RJWhBMFVQNj5Xfmc9VDU3Tgp6c0F3Q09lKEhNZmRIcGtBejsw
VkdYZnorU1EmKH45bC1GZ0s2WE8mMiY8am4laFcwN1gtfXBlSTY9WTtBUV5ZcXoKekQ5cTZEeHlu
RjYmb2k5SDFPWkA/cnVqXn4rWUlqfUZORTNXalQleDZXeGtmeGQqPkwpIUozJHZGJG1HQXAoO0xQ
CnpKcWNKKXskJnZaWldwfGcreSZTT3I+YnQ+ayNCT140WihCNDxeZ3EpJV5xYS03bDQ5JHU3bnZt
S2RLVTF3QUdhPQp6RCU8WVc1UWh7a3B9OTxGe18zZFJLcWc1UFlyQ0VZWDk/KTdUNWVAN3tqYH5f
aFN0NEsoREMwckU9eFZUVE0qU3wKejNGQW1XOFhSdSszQGRGKTBEM1RXbD8laEZEZDslPzZ3bEd2
QCMhMm1mX1FlOW94PCk+P3wlS0FZfV9scGY7JWV6CnpSITRxKSNHUHBLNXAoejBlP29nYjA1UGM4
Pj5qbUs0NnRCfHd9cDA+JERVODFsbHchV2xaVj8+QksqUnlVT2dDKQp6ZkhWb2tDbmpNX1lIUEo0
bW0+djlJPyhrIVZFTzU+TV4yNmI3al5qIzQtYVFpP0VDc1g9JmVReTBXcUpXOzVlSioKeng/eWdQ
S0VfZ1luPG5waGFjSDV5Q0wqeX4kUktlK21oYFRUJjFhKDgrUytWTT0+QTJ7Zj4tTWE3KVBrO21s
SD42CnpwPzIrckt0O2JtTXA1fDxIY2BnTiZuPEBFNFljeTZhYjdLMzl7bFo0eTg9RiEkI05fYlVv
d2xGJT41ZjdtdVdAYAp6SnRJMGtAdmNsMkx2dldvI2c0U3JMZ1oqbyZRbmApZDgpd09jMmhvO0l4
ZCl8T2E0dzNoXlZ+KzVtUUozd2EjZ20Kej05TSkhVExCRXtEPSkrNlB0K24rcXlpZVFkNWN6eSM5
PF8hYyhgYWdLOWh6fD5JfEVSYGAofVkoflZaSmM3OWdqCno4e0tAQWgzN3FRUyp9WE87OzN0a0pS
NVhrQSFoWSQ9SCEqUEp2c2N6YWpJRiVwWiYjR2hNRH4rVVNPKlJzfGNOUAp6ej5iXmU5WHx3PGRA
PzdBcGMlRkNgPWdtMGMoTSo/OEVRK3JwXmQ4bF9PeTBBZHNSJlEtWGc+V3E3eHkxbmJyXzgKemFo
S3N1T35LVDY5V3F+N1R0dk0yZDxRXyFNNG47cm1CZ2l3NUFUZkdXYmZEWnluT1g0KnJTbihgNGR6
KHhERTM5Cno3ZHkkPHw1Y1lse3l2ZGN0VEh3I0UpVXkkJF41SDcmbiZAYmY3eTszd3x4QnBQclBC
RF4hOHJCcXdjSUAlTnJDTAp6YHZSNz5hPjBsdzkycHk5TzApUnwkK09NJDl1a1NGMmpndHREPU9I
UlZSYTt4UzRgRXZIcSo1QGF6PXh0MzZBK3wKenVNOVk3YiQ5amAjQzdQSkdwb0BsZzUxYWc0S3Zt
QFZ4YSVMWS1VZSh4OS1HOz1eU1RZR3VBK0pZUWEmWVVlKVYwCno9bWk/b0xUdCF+LTVOeFluN3Yt
ciRDSyQxPDVrV1NLZlBvc2BsLTdYTHExVG5WNz5tbDdRdlMwdkM7fm45azRubAp6Ul5QTyZyJC1N
WW4yVX1EaVUtS3grIXczdj0wbHZEV15kQlZEPVR9YCR1b0dYTmlzM1MpJHpiVVY2RmxuNGlZdEIK
elpgeHF4Y3xofkFBfFhmTkE5UXdmUjgjUmMldHtxa3AkSiEybjI9YiN7aDd4ZDQmMSlCeG1xTSNw
bU9vRE1GYSlFCno/V3lPcTdxLS12bTJudWglekEjUSZNQihmRTxqWGxVNihUYmJpKnw0d3B1SDZQ
OFowUjktOVpyajNgPXR1NEVTSwp6MHtCQD9seUdiTlRiYlIhVEBQKCF2eWRgKTBncG5rNzxTYXZR
VDZVVk1QcDhuMGAoV1dDWkBnUjt7RHBWZyhxMlYKelpmO3B0RFFHVz1BdyRFJVJAOypyZ3Y4JGw+
e3dHeU1QQGIoMmdedj5CJHBjfntEckw3aW4oNShybDZGXkB7Mml0CnpwcyUxdi1UUCh1bktzXjIp
eXVPKVhCZjdyc21VKXteY15hdXt9ejhqVW8wQD4zZzwkLVNvaHNyYGZDVE4kRWpfaQp6cnREcnVB
S3VWTFQzWHRoZHtHJE96K1BCTCs3NDhLbVpUNXhyOVJ6PXBaUzh8K0xKSkRQM1hrQTA8VkNGKEU8
R0IKej1sPGV6O1AjNX5tazdXZTJ8Jk1UR1dCSiNyaUsjUUZNdWJ4QkprIWZla1lRZTZPa2dTI1Yy
JjtwfH16SGpeKndTCnpTUzRpTk9IX3d5aT1NV01VeWdYMj5CWHRuWnAqVnVNU0JzUUA9bW1uX0dR
QFV2OUIrUiZ6QWIzdGB9KyM4QnZiMQp6bFcwfig+enxob15idjMlVlpHelYyXzBxYXd5eGsoeik8
c3dRIWx1TlZ2YCgmbUNVIUNMPmxEa0JfLXdgSXhOZHkKemZyMHtLY1k8KVU4bFB0TiVna2BpR2Z+
XzMwdElvTnd2QWYtYHc5QDxoezdVWSt6YkczIz1WWH5lRmBfRFlkeXU2CnoqMShodjZiezkjQl90
Kj0qR1ZhbjhGbXx1USluXjlhXitjWU97QWN+RkxvNHBDbEpBIU0jfENrYXZWXjZQJXR1Jgp6YmJH
MG9SbDc3RW14ZkwpO0VDVlQ9Y1ltbnYkVnlGNjs5Q3YhfGZFY2lKQWwhIXF+XlJIZmVjYmR0b2FB
KEY0PDkKelE1MC03MjVyUyhwOEohe2RPZFhwbXl2cT9KdStUNClxfUUtOzRXeGVRKF5RNVVHdTU5
KjxjbT0lIWh+U21aSUVYCnp4NF4pbkt0RG42c1R1WW9Tfk88bCRHNEpNakpKR3x1TClaRFUxSTcp
VitleGlsOSFKUSshfnM/elMhXjBlVj1iMQp6WEB9VGE+bnBVPjk7ZTVqQ2MrQ3Umb0NzXilrdm1G
OzstMH0+U3tDQ2tsbE5gRkZGX0AySnFQP0xoMktOSylgKG8KejdkeUlHdWlWQmJlfGUlKkE5SGNR
SCNyTEFWYXhXYCkqPmdKb2xeT0w0Z0d6TGUtTFJGSiZsaTBjP2tgJEJmYFI5CnoqdCZZTTB3O3lt
NVM9PEFqSEJRKTF+VGVnWHNHWi1UezFtPyFaPFchYi0zX2hzNy1LZVZtJGpEKShYZHp2RSFkVgp6
KFJ7K1ZHe2dacmNWPntQdUFkfTJuaEFKbmBlQ2QoTDApXyVabVZ3VyRJeXYmS2FqdVFnMkJsZ2w4
JUowdzZQMS0KenQtS3kjYG4zWkhae2dfUVJ2Tis4SnB7Y3FsbE41bVdVKnhEMDYjTkJ4V3slWEd8
e0E0SEx4ISgrN3VYRWQ+eVAoCnpVPWUkJURSRjdmWWxsKi0+aHwwbnslMkZXZnZGREc2QFdwRW1i
WmdGcEFtYXw/UVF3MVlhN2VmendqeGZXSjl2ZQp6cjRMMVBhQD18YXMyTHFSSFJnS0dNPj14a3dW
SlZzTnckbV5OaFFffXM5LWhRWjNlZ2BrTUZqTzZQPVJtLSZ9bUMKejNobEszMzctZDR4aFc3Xy0t
JW8tSFg3fXg/YyFkJkhaZTF+R015JXVuYmhLXjdySCg8JUtyZFEjUkZXVCoyYWlsCnprQnA5bTIt
RFcqU0xWOWBxP2ohVDt1OGA9eThWJUplUXhsPDdCIXxWbG03P3p6fSgyMHZiamVgJCkjbjB6YEpA
aQp6MyZhWjZ2OUk1IyFeR3xGeHBvQFJRVXFBXzdfMnlqPHpiQ29ZPW5sSFdITEUpRysoQVJqTFYj
ZzZJNDtZUFJTMHsKektoLUFkYGVUYlpLP25NTEFHbTgjY3NCKlMxKSstX1c5QG5Kd152aDVhfTU5
YClLYjM8ZDZpOygxPmE4RDRrbVNlCnowWE4mYFppZEtUTXUqeEgkcW1mOGVlZk8tRkN6PCtUeV8y
ajs3Pjw9UlAxRDYzQGp5S3hfKUEyOyRnV1BhcWk4bQp6JWh+QVk9JV9afm4waHl2JHxMQ0QmRiNl
OHshfWJtXylWc3h0WDEjQz1NdWxJN0tNXlhVKjkmYVEyUzBPZFpKVysKejtMWXhSaCtlRjNaT1V4
ZzhjK1c2c30+YU0xNlF4Vno1VjIpRGF1P2RyVkR6WkZGQ15ecGEyO1BBKXp7Z1JqQis4CnotYGEl
O2FoXkpWVkwkekJiWU5mcj1kfVczemtaVDh3dUQ1bzN2QihlaCEmPk0jajhCVD1ofWZtKXQwM2s3
YEVUSAp6MGojWFd5ZnElJWRjRDU1KmliKXRLdnBGb0A0O3c8bXRGWEd3NHkqa0ZLOV5DeWVGKT0t
d158PERhakdFdjFHcygKejU0WGBqT2d4a3FGTHJUOzkwVHhQRXR7bnNfUXojcFdEbypeQmJVR3El
dX1BV04rU24wI0dUUXpWNzBYSDZSNkdDCno5SSY4KVV+SmJaZ0xfQ1BXVER4QW02dzxFVW4rZHJh
WU9wbztOYTYmPklWQVd6WWw2P0FjcTkkeUNAUlNuXlA/Owp6TGgyKjxIY2YtdWVtNWt+STNtJjIh
UipAOVg2flo8KnZMcHAhZXBKKCklKnZgJUY2UiFtcCg0ck11ZGtPTVJmTG8KejdHN0ZnaUZtVnxW
bEVpKTJxbzc9SXRTOTxScmIxRTRldUd6YmFUX244RVQ4OWViY09pMzxAb04tYHlAJTFeZ3BsCnpt
SEtyenlVZXdHNHs0KnhpVj1yJHZYfHs7I0Y8XjJ2PkBgUEVDcEwmUSglfUBQJm82REM0RlBIe29q
MSZIOEAqUQp6c3lTeGp7QkMhYmEqPlJ1al5sWDhfX0xqbWlydjVPI29+WEZ7b25RMnw2TDZKfEQ/
clYjTH4qP0dFJEVPcDElVjYKUDQ4aEwwezkxaH49PWM4dlBsZSgtCgpsaXRlcmFsIDAKSGNtVj9k
MDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmcgYi9hcHAv
cmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uYTVlZDgwZmMxODQ2ODcxMzJh
YmQ2NzM3MWNkNzgyMTA3NzBmMWNhNQpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTk0MDUKemNt
ZUlhaGcqfHBgIygoVVErY2NrUGl2SlR0SUJkUHNfWVQ0UWJsQj40bnojQUdOUDtxMFYwR0R0V19R
ZFA9ZjVHCnpNTDxBNldASEE3MCUxaz0zSXFpYkFkbW5kZ3BkJjQ+JVFzeGQleGZSOzYwOUNhfnZN
SSVlQnQmSVh+eGxVRHVzSAp6YG8rT3x8SlI0Vm1YZWElWiokQDIlVGlMKChOYT1oYHV9QDNfPX09
cVEhNG57YkxXQ0hSIVR+eTFeVnx6OHxJWjQKel9Aakt0eCQ3WlVGZ191O1V4VTQrYTUkWEs/TGFA
UT1kWDlYYnVodWA0MzdDPkRYQVolWTx+WGY+Zk94NmlTVyFCCnpmaCQ5WmI5OGQ9QUV3OFlfT19F
a01AWDt4Unx6RW5afHJ+Y15ZQHFEXzNNR0ltRk5kdm0zeWY9dWxLeXNzITJUYQp6RSY3TlRSZnFq
TTtZfENOaEgoTT1ifU9JP048PFlzXjQkZGY4b19hRUp3N3tJSzMzZj9xT1EwfEcpIVl6PHd+fXEK
enclRjtrdmJ5Y1VzQlZFJVFnKExKUTZNYnpjXnhxckNjRTx9KXg3JGo9cjRBakZQQGN4UjBXQDdk
JXBPNz1qcGxICnp6ZFV4SHFEbFhCe0txXm43WEFVbktjVnBkdVRiel5RaWhQM3stVV99cS0kMW5O
TjhBSUw0bEYwWWdTPXNoPykmXgp6ZiMyMkJsV21GJTMpODhAUjtIejx3eSQ7Qil0PzdDTTVgWnc9
PG05dHNpfHFqP1VzbEIteWlPbllXOEB6VGU+cHAKeikta3JVdzRWTnRzUy0paytXSzBpVjRCdzU/
ZD4wVilOXmBUS0llUGQkb3JwTFRpYiMrPUVAYUshdHx9PGwmSz5kCno/QHptWjB8ZTFoZmUxQUVw
eDwrZj9sP0tISjEkX25sRiZLaSYjMlFqdE1SOUw7RT1tYj4tJmEjKTNXMkApPE9wUQp6VCRlNnpz
cXNvbDdrdmpXbDNyZSRIfDkmTXZIZzA1IT18SypyLXlITzY8d20pPHpfI3N0K2c5TT5yTEc5MCRK
bmQKej9PKUVMKFIhRDE+PVFuWkd0KUNPeUFuTHhnNkhPWDd0UVljS3hTWlozO2MrXklyMmM1eVQz
eEBrMEdrPjFePU9hCnp0Pys2XkQzOXE8Z0dHbkFSX0hsIz4kSj5fMCg8Z0h2Ozd4Mi1NXnI1eU00
M2ZpJG44bzZ1d0w/RT1iS1o2ezFaKQp6WStRWEBTZzJAbUR6ajB3allsODN1KWFeRkdyUll8c0Y1
ajJIUEtUKEpGQkM3ZXRzWCMwYlAzUTwmQmQzYGckeykKeks0KjQmLURLMDZwdjBDQF9hTDVxZGNn
OUo1LVdDUEt0RlRle3s0QmN1QVc4PlQrd3gpV0o8T3lIKFNpdD01bSlKCno3SnpfTC08XmEhYXgw
QGQhKktTb1lrbHlid3tCO0VsU0B7b1ZMKHEhYzlaYEMkS0tyPE8qKHF9eVczQ1czWElLMwp6dCZo
c1A7LTA9Vks5JWsxbkh6cCo8QnFidE53VCRkLTBZYD4tMDtZP3lCY2dQT0RyJXQ5QmIjYHBrYnF0
YDFFTlUKenBeZUFGU1Q+JFE4RGN0XnU/bSZwKUE9RG96VHB1OWo9REt5cjhra1VwPE1WcFBsc052
WVNqNG9wcGNedypuTHZCCnpQUiVTclI4ZH1VR315KGNzNysxMUlLOH4wQUUje1Zjfj9LU3tMI3pG
X1I0OV5Vez85QVRIP2tYaihQQTh2VD0kdwp6eHl6KE9WOUZrXnVZTHF5X0t2eyp5dzZXfmFTRE1R
WDZ+VldyU3p6dWJtbz85dC1VUWEzXm5ybU0raVN1VEVgYXoKeiZEPyN3UW1BJD1qXkBCQmxqVHN8
bUZaYSYpMztfWjEpQWdkQmFueit8R09Eez4zXjZ5TCExb25eam0jbClUQ3xYCno1QEtUKnd3QHtP
NV5IQyVXRTU/LXJoMCpWbVY1KFJUdm1HeWhqNFR8YmkxLXZ1PD8lN05ZZXFzbTsyIVNvQGAlegp6
cXVafUVAfD93SDRZenxgUiZTOUpHMU5gYF5USl9JJiliVjtuVlhabGotU2BPdFkma2BpIXBRRXFG
enVhOS1ZKC0KejlgNDxoNURBPCRDRWYkY3FCWGt0P3cpdlNuXzE3MzNeJHRTRzgoaTg2VWpJb2pl
XlVKTW9UX0liajhsaj1MTl5YCnpYaEE0JEQmVUVibWUweCpCT0tQZzAtQHI0UkJEJSQpU2IhRnY3
biEjSnxQJTZXSlV5UHZrcDE9eCVPQ31haWtXMQp6TFVmc2RHZH0pVT9jOE5HPFdte2VjR1R0ekB1
JGpvPTFBOTc2an5aZ2FyIz8wbCZnIz07c3RUOHBoMzUraz5nbkMKelNacVZPPjhyc241V0ZsJDZB
JDw2bktaczh3PH1xJXZscysrbFVVZVAmYF9vZTg4U2c/cE9qUnlpS3ZNayp0Tll6CnpRMFc+PmFT
dUFaZUNUK3E9NElrZCt5WSkhZ1RNTExyLTNJJmlKTnJ0WUdFNnZkI2ZkOCUqK0BKZSpNanRrYUtu
Qwp6eUhuZn0rekgjKHN+dnZzWCYzV0llX25XOyZed1NibWJpKFBNb3V0bUZaQTh8UFBqTyEkeiNo
LVdOViZ9OEFuNz0KejU4OWtxUXZNUjZpPVFGVE9gVTZHeysxPDc7JT9YMTNSQE1mJStGbVE+QnEl
O2FtcUZPalUmYjM8WnZDNXhjZVNMCnpJSV8jVl5MfFVyeFdWZFNSUzZpczkwPzEtVjFBYW81SSsk
UilpQV5ARm5xeXxeeGM4UEd7UWB3ezw9IUtgd0lUTgp6eEtUODZQZlROb2VWYys3Jnk0IyhUbkB2
YT1jNXo1aSQ+dUQycEA1YEo/ZSZKKW9tVzlqUk50clk3NFMkN3g9O2gKeiRYM1IjRTF0cClFOEp7
OWFOcWUkNGVoeUxYe2kjfWVTZkc0S2hCblFtMkVaNGRRVF4lPFY1QiRqPlotVXlmYFJZCnplcmo1
MDtRfnNuR1dOV0w/PHRydVFmYnNZZlVPTTNRVUlmaz9JRmRsUHdVSnBiV3NRYj5ENWhnbFhfQjlz
MTIjTAp6e1dfQ18qWj1VU3dAWV5zcCtyPnEtWGIlbmshPjVeRUUwb3RuOyl3fXV6N3VIQFM/aDkx
YkBHOVA8SCFQMWtOcDAKej9mMyRKSyFzP14yWGE2RDlLTTFKNGx+VFR5SE9nc3UhNEVYMzhSNVUt
eURUTz4tVnY5X1lqTGdWZWhLX1JEIVliCnpjMTRuMjJLZ0lmMSZITEVrdzxOXjwlbkY8M1FObk5I
bn5jP19+IzRfJFhHb09BZ3NKO2phO3RxVGN1STlXQlJ1ewp6SXVrRjNNaCRYWGtUMDk/K2hfVFJn
R0FRal5PN1lgTXB2MlRVQSZKJVkpI0w4RnRrQSokX3lUey0hQ3JxVjQ2UEYKel45YkIxV1lNXnhg
bmtVRXYpYnVLRGh7VmtNPVVmdipicHNfSlE4bSN4d2orUVdVMnl1eikrN00kVnQlI1F3QXZBCnpG
NS1ybk8zKFV1cGhJNTQkPlhIV08xeiQ2SW5reXUzTGc0X0slM0Z6WmslPUthdjwqdlU0ZSZeTTR2
aiN5NHg2ewp6N2klcyEkSUIlemZtNylCO3x0MlU5fTdfeW4hSnAya0h1X2pGMTVeSm5YbGlvcCRI
YXpWK3p4WmBlNlUxJk5mVXEKekRyKHU0WXQhWn1yKjNuJiYwMD9vRH1CWXpmcnRfLVd2NnVAPV98
cz4rdU1+KGhvUCk8e1YxZzleV1B6IzdCRHMkCnolclQ9em94IUR5TF5ifGFqMkAxZyVPZ2l4b1Ju
Q1k4RGAyN2BMeHhOZ3ozS3I/dUtBfGhEdmBFZ3FLWCFQdiRJQAp6SDV3JUd3YEBxOHtqX2NoMTlL
QDdDRWpXKy14OXRuaWAxfnIqQm0hRTRHQyVvdE4zbUJAVk9LZ1pnUW4qVSZESXEKeilyZE0kZ2xl
VjBHUCFsfksySjBBQWtuZzNASkt1WiU8NHJid0xidWBCaF9nR2YkIUwoYygtdD9zTSY2PWdQXnoh
CnpTPzVkYl43cjlKe1RTPTEkd1Y1VGx0P0JJJGotPCQzMXtfdGpBZyo2Kk1ZRTxkJkZHXk15ITt7
amZ3ZTRleTl5dgp6YEBAPUA0fkFtLVZReGdjMm1PSjhNMSZ6TiFXZk02bi1Jd2JlKi1icHdlcEsz
X29rSXRBJDdQeEomV3Y7RjxeU3gKeiZIPXM3WDRzdU5Xa0JxNlVKPHc+QjU7ej9FcTZhIUdnI30p
NiZSXy1TSmtROFZnMEM4JiQ5Mzx6RERqRDE0WUwqCnpAPXhQTWprPEA0IzkwWlk4LXN7STsmKCNg
Tz9RQUo+T29QYE1hZl9Rdz4+NT5CRVhtMmFDLWgjSzdpU3hre359ZAp6SjxXM2ReQGl3QzRFSH1v
QWwzNjMqblc9cnEhfVZiczRibDBsVjY3TVBCTiN0P2JtQHV4KnhoMCNXcH1BTSEweFYKeis8RzVa
aDR1akpKb2hld09Sd2s7IWFSa15LVTVreUxqIUBlZmY1OCE2Ryt5ITF0aTtVTmZmWSV3RjFuVHpC
VS1+CnpAZ2lpbjxgYipQUWVyXlZYNUlNWmRWYnkySTx2KDIoWFBwRzteVFJfclhgLS1Jd0h3XnF0
KDZPWmJCUjZxbUZhMQp6SV9lZT92LV5jSCE7T2EzczUxTSFHTlpKdCZhTnkkIVNALWRtWS1nNDsy
QTZUaDJgVXhJVDEmO0EjJThKMVNXP3MKenhvX197TUZ9NG88JWRsaDZ6PCF2N0pKQEA4fiE4VTZ5
YnJNI31zQGthO0FtSUwjTCU/MW9YY0xpPThvcEElQncyCnpTMEsrYThyTk90VXRQUTZZV2NAXj1Y
fCZYe2FEbyY3KWFKV2BNZWlwO0BkSnZXWXo3UGtTU2J1cz9jYVRvRElXNgp6R0cpKW1YdTgzUSt9
SWozeF9zNWxFbzJzeGFDQ2RpbTYqX0c5WUB8N2twLUxsVT1jWXRkN0hoVE9ISXhXKXI8I2EKek8/
RyphO1BwbnZjZnkkIzlKM09pPDNGMVU3SEl6Wl5QIUw2YHthT1RVXnVGRDt0aFlzRWVNRzhaYkxM
SUV0cEFeCnpvZiFSViYhO05aUndQalZxYWtlT3VoKnVYQ1IwXkxMaXlDamxzRjFyXkVeK3NObTR1
RFhndjF2QEA+SnR6O3RTRwp6JEgmLUNyanFjM1F6S18pKHpjQ3B7P2JlVlNOdm9qJjVuSE1CSXg5
eTRreT1aZjVjOFMzTEEkaFgwQyZBbllMbmsKejUraDxRSkNncXFUY1VVWGJpNGp5TjI4ZW88T1lM
cnlhLSNtQkRnbWx2JH1eWGczNzgpSFB8OGx2NVhXfTMoZSUqCno2UkAkQURfRT4+WlljLVV4MDQ7
RzAxbCVNK1FHajVMVDU+KHFzQClxbiZ+SURQbCNPb1JLTk91PyN8dTxOYVNtIwp6RnQ+REBvPTZn
fWAlekFBV21STTJENjshaXMwR1R+PVRFbDVlWkpWfkJZRD99WH04YSkkLSM8Qzxqekh7YjlCOUgK
emRUO0YqXnUhTzRKWE82UDI9fDIjezRpIyRqU014ND16VWA/Y2pMdmkqbmZrU1VMUz9TVCFGQmZP
IWpkdDtqUF9FCnpgN2d6fkt5ITVeaFR9Z1AzM0BheXpeU2lfRCQ7RXtmZjtTdT4wKj1NaiRlKkAr
U09CYT5uIU54UTRMNF8qej5ZVgp6Sjw4b0pIZDRoblc8eFohb0ZIeTFRMVJ7azloJTElSGNyKCRu
ayZKIU16RyReJjlvQTBsZjw3MT8pRj5abV9zMXAKentHSCo/SmFPJGFkSXNwS01jaVozJUZ0Q0Ek
dHFLaEM9SW0mWmtILTFMODxCRU9fbG1qe1EzRDtTeSo1XmFqTy1zCnpDZ2VPTU09MCNaOCp9O2dX
fjxweGJsazZzeEJpbCNnSzZjdnsmcnY8PzclfnRMTyVAWkRwKCZmezApPCVWQzxYNgp6RmJpbzF2
emJjYXlxWUotQ0NYSSowTHNYQTJuUH1NIyM7fHdKX0JDPD09UkxtYVEydSozSXlWVFgrZ35gUSF2
QngKemVMSXVpWkstKihUMn5eY1ZJdFZUWj85TWgkMzhWYFhNUEtNVHdtSmh2NXs2Qj1uJXxWRipe
NUowKkYpVTVMX1ZLCnpzXyt9YWJZI0BIU0c/TSZDa0FXZmpFY1BjcUBuZ30yLXctd3NNUVhJI0I9
VyVZUWk8V2NyVzFSaTliTj1uZDVMawp6K2dDTWBiLTlmanYoOSE5NmVSdDZAbGBPbXBLSE9aWUha
P0QrKjMqeXMzfnIme303KzM1a296Miole3ZsZTBtMVcKejtrK30pPD5JVG43cSheRDQzb0J2ajZk
N0FkMGowZjNYdGY+NCNGYlhPZzRFczByelIya2pRfTJVMDI0dXp0MDRNCnpfMEJuNGBpIWI+ejBh
aTtCTzZkZVFAYWNnQDkySCgwNmNnUCphKjsySEIwOFR4SW9aRkdFPUwwIXZNMVZGSzF5Rwp6OXVQ
T0BJVGhxeXJyIUxfRXVTeHBUdn4zcjdQa2txS1lJJEJ7YS0tNCQ2NllhezBrUDlmPTY4azFHZ2Q2
V0xpUiMKemQhKUlaZFY5bzRIb3lnVj9RIUklPUV9ZTJSXk1yRDZuczg7TlFxYyptPjs+LUp+Xn0+
bykha3ZvMzE5LXBQaDBDCnpmbDFzZ0R8RHheKnVSQlZnLTZPYU0mN1kxUlVFayslJXkrRWtpPilj
Q1ExJU5vOFYpb3slI0spP0AyX2xsITtmPQp6KyUyaksmSy1iJjs7akxObz5uZTdrZGdNR21Fb3pF
Qz4pd3dJcGhFQG4qXjZ2YzArQHZ5b0smQHV5VyMyb0QkKj4KenkmaDwhRiROfkEpOFNqbWQ7NzFI
cn4/cFhzRGI4Pk1jK1ZuQ2N6dX1XVTJ6JEV6PklxQVNqcHglT1ExTGQxcVgwCnowNTklYjh6YiQh
c3Z5VT51a0h2bT08PzI+Y1hjPD1ySDk5PVVUdlYlIWYhNiMmMVZCdXprXmlLK2Zqdkg2QD5DRgp6
JShTPjh2dG8zN3dmI305Yl9UNUpqKW1wdjYreG87RWJMUnRhZ3oxPHhOM2hXPGVyT1JhQ3pVRVpW
bGltSm96dWgKelgwYG5scX5HNiUxUm5BKF4tO1YociFnZFJpe09UeEQ0TnhUam5uJU9ZfDdjMyZZ
Uk8qeVQ8SVRFMW8zXnVyTSYjCnpKc3k/SGszOXBYYH0wQEBFP0E1SWBSUlF5cjw1KHNCM2l1JFJ0
aj1UIzYmT0pgJi01NWV8TXgoO3o4cWViNkFaPgp6eiszdjFeOFcoNjtXZlZVKmw7K0o2b3YlTloj
SDMhK2cyNDVafWtIRnQ9cT91ZWE/VWVrOGIkRER8d0RJY344cF8KenokP3hIU0BYWUlvP2syVSFF
QF9gU3M/Z2N3KWVfST5xdVI5Z0R3ODglZzZEWTgrbW5lel5XenxkSnshMyVeU2R7CnomRFZkay1R
My1DNX1LMGNQPDt6ZEg2PVRYZDd1UCF5dkchcSlCZjxyYEFydldOQTsxQmk0NUsmaWNMYntycHNP
cAp6aTBPeUVnfCpzYTcjNW8yMW45Mm9KTn50JkZuSiVAUz5KemQoV0pVRDZ7dVNvVGlHS0dOZF8w
RTkoeFEhWTBeYGAKemhVWkQ2NC1ZbmpoVVFoNkFkQH1iM15oWFhyal5oPllgVEw2azZNYGhZKEtn
Iy1JZChLMHlpZjM9Sms8O3BlZWR+CnpyI2t0cWJVfExYeEpPLWJoJHBKUD09ZCtGNG9sOTBxNVFB
djRyKz1jPitQeipGM1ZBdUklUzU8NEZMbGB0ZDRfRAp6KGR1KFdWT3FZayt+ZW1HMD5Baik/S2o2
JkYhSVNQOFFMJHtlc25KTURMK1pQKHZ7PDBvWE1CRzFBcUhKUFFLfFIKeihPSHhrRmglTTgwUkg7
TVhVQmElX1BeNE5uQzFSZVU+TEdxPCM4NlljeFY/XjxIMnxJcG51SUolVWJASUN5Qkk+CnpZayZz
KTdaKEVHIVApMT1Pfn1nNC0qejJ9KWR+WkhTO05EU3lgPzxEb3hjRUplZSpCJDxkPlQrVV9GMSNU
PTNwbwp6fEZma1olT2dqLWIjKld2ZUFSLWd8TFQ4QFlRZ3FEYVRDYDY9WldzWkpjanhkM35MX3li
IVIyVHRuM2EqMHJCPXsKenhCbXFmYUVecWFZLWY3e1NHby03ZU4yWlYpV0F2I25Da2oob19iZGJh
RUhERCRpQ3UpOHd3NG5AJVcjWm5jQz1ECno2U3AzbiMkMH1SakFUM1B7TUctNnZwcTYpQGl7bjx2
NUdnMXM9T1FeNEZkaX44dHdmXmNwRjJsd3VuZ1JONWhiawp6KkA0dExHOFA8WldkYy1Qbig0NUI1
Mm03TDtWcX11SkQxK31kKEBSb0JzOFArajsofSQjfTdLI0tndSUhTHtMcjAKenh7c2R8PUk9PiYh
Oz9QQiZOZEVtVE9re1ZrSSFYMXRmfF5qSz5QMHFUUGdwPGk9KV5DY1cjeitEP3s5SlUzQ1pkCno1
cUg8Rl9aVWV1JUQ7cHxZcDE7WDdJOFd2R0hUbFZHdkBKM2shMWg7KGtsYnAxeFBkZHpvJmJAN3lA
KzJwYCU+SAp6K0x2RWVVaGVMYF82MVo+Y2I8WEd4dG11VUV2R2AxdDZAfkZ7QzNDPUNmXjt6P3JT
O354elI5PGZyfWZkJks+TFQKeiM+dUxmSCYoV1R0UkMqbl8wWEFAenFKWXskNUEqcUk7V1p2YT9g
WEF2a25yR2tgeUM8YGVnZEE1V0R2NiNNSFo9CnozNU19OyU0WEcrNWZGLThkUG9vdFBUbSlIY0s7
ZVVDQ2dfczUyaTcwTTx3fmtnMnkpbE1oOGF3ZjN0eVJzTXdpLQp6PkotbDxfSEt5OEVldkkxOyFC
VlMmQiloYkFPRjhPRV49dyhwNH1pQ3NkRHtpdkZrRllKNEhWbiFwSEwrXjYpPEcKem5BN1IxJDs5
ajtTZ2VxYkoqSnojUlklb0ZwbmlsbENjbThEJHEkPld5I3lBWlBUfXwmM1RFODk8b2tvNUB6QGRB
CnpjayU/YCsrLSQzPn10JjRINkU2Q3FmajR6XzQrcF9Sd2B2Y2gtQVchQD9JTndlP2VLbkdINFF7
aH5PWTMoTV8rYQp6ZGNOfG5pQCZfUUpEJilxR0RoI0xCalE9bnZndFA+IURMSWojJnN8fG1YelBJ
PGYyfG9IdVcre3J3eFNadVNTT2sKeiRMVC00PSZtfnZyNDZqe2hUaE56NjUofHByMlcmRy1kLTNs
MnxYN0xFVVRzO0dpQU9HRnViQmFoNSNNVCUpQFpCCnpVcnVZJDFSNSleOzllKmE/fldnd0ZCP29a
KFd0VV9BRVgoQVVWNEFgWUxte24qdGpBZGpDfSZ3d2E8eSZFfjtARQp6Pk5Ab3o7NHBlPzhsdXpX
bjRLYStJJHZ8dXNCSnhLJS12dEM/WkRZP2syYHNwWEhvZGYmYj5PQmBzWEMpNnpGQEEKemloO25K
S0NfTTNARk1aejBpdTcheGxmWDNgIXRZV21sI1p+KD9Ge3w5NyswQWNjcUR4YH4zJEJXVktGOWJU
VCYlCnokaGw+ZWBkVlhTOXZxVGluQ29+XkowQkpnKWMpbExXVmJWa1Q/Yj51cFk5MUFuXl84ZzEq
YD5pa3NqPCk0ZG1YRQp6cHI2cGwheiZVQm43SkU8dCRyXztFNHI0Pz0waEh2WXFnQWU9UXY7ZmIq
Zl9edyF7cVlxdjV2c0d3OW0wUT9kU1IKej9OaExkaj4pa0ptSEB3MTxXKmBDRmB+ezRncFU1OGNo
Ozc/VXNwOUFhTE0wPUxpKngxVTJ5JWQ/U0NuSXI3YUBmCnpDNWByMG15Uy1LejJZKTdte1dqbTgk
JHI5SXhgUEAodGRxbzw1QUA3aEQxd1VxRzV4cVI8Kj5mb0pfYVMpZ3Q/egp6czRjPyg3e2tnUk18
fU4leEAjfCs7Wj5ZMzFHQCVCKHBxaFVKLTczTFlNdCFsUHpCITl6QDdSd0FvMkFCRndoUlkKem9x
cXA8OWAqU2IkaF5sJTdmSGxBVVJ9dTU2V3VDQGxZYXVQdXIoN147PX0lJiRPU2BRP30yVWlNRXFu
enBuRHZVCnpjKkNES3RFZ00tKj19WEk8UFlfYGI9bnlZaWglLSVTXk9UdFVPdmtCOSs2KEFYbkFM
fElzODUyTDZvPjNjKlY5KAp6bCNWIzlNTGpzTll5UzBCVWdqV1ZZaS16elJVYXZJLVZ9OFI1Nm92
MWFaKlYqbmBQNypgYG8jKD8hO2gmLV8mMj8KeipeemYpQGNALT9AP3BHYnVRaVg5TXs/UlpZQW5E
JXBJM15kNE94VD8tR0o1aWNjTGJIRFhSNzhIbXBaciNnNnBICnpjY2tDaXRRNFVDdj4/Q1NzREM1
bSR1KnM+a0ohd3goOT4hS14zO34lPyEpMik/Q2p9QT94ajV2UGZGUzwyTE0/KQp6NH0tJWktQTBx
RmdTeT03QHwjN340WT1qY2spaCV7NGc9XmgxYz0/e15sMmxBX1hDIzRNYXRjaHZgNlk2NysoI3EK
em1DfSQpWiEybmR3VjFxODMrR09xRTBqQ2VXRClkc1ZqNDIzNEo/I2BveHlfZUp4N3xQcjdoOCtw
V21kNmhuO2dYCnpkeXwpQCtGfjJBUjk4fl9DO3JEQWdeNyZPS1lLWXJxd15iPXJLRVA9MXByZUZz
WD9Vait9OzhrZkB9KGpXUWNwZAp6e2Z0Uj9kRUBIcEJVPXBob0dZUFE+OUVgVChvI3U3ZkNveEJM
eiR9RHVleml4NGR9ZmE9RUplTTkwVlRJJTM/WmoKenZmS2ZVbT05ZCkjQmwwTjVRQXx7bmYrK18j
a25wfmoxSlc8SC1RJG43JDdoUE9adWg1LWFSaXVZcGtMfiR7bS1kCnp4cXIjSTU5JlIwdWJiUVNp
UWl1XmFBR2o+JlF7T2JITTc7Y2xgWisoVHtVPCRmT35fVDRPa19eYUBtV2NXTDd0YAp6UUdhSStL
amZZb0A4OSR+UDFUQ0BrfkQrZ3Q9a29NMH4xRGJuQmhGflR2Nyh2I0dATjd0akF1MXFtU3Q7SUNP
JnIKejhIYC0hWipUbk93XzVYVnNhcS0yZlpNJF85XyZpbj9Ee1ROT25ybnZPUjR9JEs1OVZMWlR8
V1ZLRWo7UiNGQVZRCnoqI2NJJllAPCR6cVE9JW5PKn59bz9Aa1oxOzxoJUZXQmY9bm04eThgWW0w
djdCY1MzMUk2NGthJEgkb2AodiVxVwp6VjhKKG91N3lsQFBKQFlEREJsMzxLbEQ1JGwrVCpqQzh1
VmlvVUtnVnkzIUptNEcxcCF0RFFBaCVoOG15YDt+eD8KekdTTUlxbUIrOE1kJD98NHNJWldBIXl3
LXcoaTJuQj5PSDwkfER7NSZ3LSQrKGghdk41WWFzSH16TWJMMGVfQ1laCno1RWU+N0M4Z2ZSXyZr
JWRsIVh2bGhFMEd3N0VWNDVTc1REej8yYSo3dn4kVyF1bD0pS0MxKWdZOSp8fV5rbGdxXwp6VHJC
PVlIO1U0dHRrQ1p9I3twWT9wQXU1bVMpZkEqZVEwVyRWVUY7d0Uqd2Z5YVV0RllGP082SjlffVRL
Vnd0fDcKelZEejxyITcxdmkmOXpTanRMfH0yWnBwdyRuK0ZsUWdodXMmMmskdm9YOypXXj9HSUQo
JTVLO3UldCl4OD16OEk9CnpDcC1iT0VgUGFXdlZ7fUBKdHN5cHJjIVlRX287bWxWSWBkQ2JXN0Io
JmVsTDhvZmx2Nm5idzliJCYkbnMhUEtJYwp6ZzteYldYWWtSVCFNPTV1WGg9azt3TT50bGhJMGYh
QmlhY15qMXA5ZzJtZC07bSl9RU0hMkp+OVlFY3A3Rz9ldn0Kejs+b1dTems0Km48NlooYVp1OEB2
VjxDP2lLKjNqI2pJQDtxZzdhdFlVdXtaUmpsekxFdkpWPlBldWFoUipFUWdPCnp1eHRuI0UpPEJm
WnRKaEEjTjwjUFpROWphZ0wtRGw0NmIqc3l8dmFyJkphZmt4UD1lU00rRHtvK3sySyREVT9Obgp6
K0gjQzFSeVcjX14+OHYpSVE2azcjSWZpJk4mb1REWkVyODZPcVlFUFVMVi1kP1d9ZGw1VDg8bWh3
QCFoQ0F5JFoKenVQPkYjbWFiOFVSVF5AZlojUjF3PUMkNEJtN1NeX3omWkVrdm0+ZFk3SzU1SmQ4
MGFiYWRzeDRFendlQ0IxYnleCno7a2RhSG4xWiNsJHgmQk17b1g7SCtEKnRIWCgyJCM/c3poKDtr
RjBydW5pfX1jJk4rUDwxMDJgUS1ZTm9EPjx9KQp6Km1QTnFYYnwteThMND1pP0dOVjJHPXUkbXUr
fnB9RTIybSMrPnoxaHtmUDJHVUsrRDdvfCs9cUg/di1AbnMpcWYKemNmLURHc3FmLT9CRTRFbHAq
JURiQjV3M3R5JndyKl5neUEzaVQ9SmxhQWR9bnRCKEd7P20wUU1VKXhyVUFUK2RwCnptPmA3clBw
d0J7I248RDgoZHFhanVtND9OeDU9fG8oQ0tXQUReKTkpPURIQGZ0cU9ZeTBhP0lYKEk0UUR6Vj9F
bQp6Z3ZlWlNaTEY9cC01Q1ltVEtBfmQ8MD59JU5iNyNlTj1zV3x5OFMhZ2lwXj8lUS1FO3QjZ2wm
TExOeWE1QkU9LXMKem9NPSVlN0AkRjlUTVg5fFpAeFpnQlotKnQqbGspRHlpfntVSlZjYmM4Qy1J
TWlyUCZeVFJVTW0lOWlRMVhUUjE7CnpkO3dJdXZzRnN9U2J4TlhoYzM5bCR1PlUkLUZtJmczNVZU
QGIkKXJ2ZGBafk1XfmY1NHdqXjZWUUl7KjxqKjFESgp6RFdAaFZyZjJ2clJEVjE/OTNuZio0SURg
VmstKncreHAhMUp7LXtPeGNfZUJANCVwfTVqJFhDblpFOz84ejNzJiEKekJWOWtTPnhTXyFDOV9M
Yld+N1ZpdmRIV1VSPzAzKDVocyt3WDtiSUkkRDd3ZnRgK0hpUG8oSUZKdWlXZHp1dHNeCnpufDZ5
YkkqNiVAUUBiKzRtQDB3d3JoXnh+TT9ybHElLSEzVG92R1paRFhgNDZFXnlIMnAxbUlDNmVpMD0r
P1ZydAp6SzkpOGtXVSNAWkQ+aGV6ck9vc2pJc2dEUj9fM3ZMb1Qtcz8zIyo/NVVVMFYjN3pMMSk9
WUo9cHVRVXBtU3tOTmEKej1UM0hZe2B6UWxRQzlmeSlLfDZuX189ViN3bEUmemRgc29nI0leJEtG
Kyl7Zz5yUHVLUD9IPT5JfmxRaW0xLU48CnpHdHxUSmo7RWs0Q1NReWVpcX04MkBzZkoyMD41dGoz
KUJ5XzBUYW0kS0AmcjNTQnJzZVozfGMtdlc0Y2dQNF5tUwp6MDxVPXA7aiVgKHMtKTZMZyk7TmRy
NTc+c1l5OzA2d2xFRG5ucSNgNU9AODJaI0JGRklocFlWZE4wZXpAVngmaz0KemQ/REIpPkBATDV2
SCR0UWx9cXlBdkBBTHdKYGNURVI2TGVJdGxDPExxLXtQKUtTWD96NyhhWD1Le3M8RzEqdDtOCnow
SHNtLVVCYHgwclJ2RUJQWS1MaUE7Y2VsOGpKQXdpMHltU1BtdyskN0BzSFNAdz50Qy19Nkc0Zj1I
c3R7YzxjYwp6KiomU31WKWdNQUw2PkxjSWFQUFgoSHY7OUhmRFpDbjA7blZeLSFZR1QwbDN5UUdx
bWJaa3BAZytuJi1ZR1pYaEgKemNqPGRAZkV8NFptVE1eNVh9eSV6cnFmYDdHUSRKOFh5VVE/TyYx
SFozZipudDJ4bEola2BQQ35AdTNeSSR2ejZBCnpZfGM2NzstTXhAVH01SUhUVGh0IzJ7Q0dCKVNL
KUtLeVhWNTQmQiV9P3lGZj1qZThiWm1VR0tqPzBVRHNEezYzXwp6QGw/NWtzNjNmOShMZGUmX08k
XlRqZHBrSUMjdyZ5P2FLJG45OU5PMzAmLUpNKT9KK3w9Tms5LUxwamtHTSoza00Kel5JbXxrT3xJ
YzZWZXJQNFg+T1lQXz1TWX0pO0syZVZOVTEkI0ZwO2JIe1leZlRAQUp1e05selM4XzAjTllsS1U5
CnpsQ3Z1fmZOSHQ2YnloYWpRIyVKQks2LXNlKzI/IWZCNnZ1Z09OTClXT3U5MFc3UysoR2NSPXsw
Y2JCajtWYXchRgp6and7RlpXUmlWI1grc2coR3c9cmFsK3xGVlQ7IXp0RiRwSS10OT1gSDZCJD4o
MXZWMVI+M2BxRkNhSDFWaD9nd3QKeldAbnY7ZGxSbWBYWHNKRk5eaX0/bUZFZ3E9a0MjcyFwKlN7
UVZNTVBUdVllZ29FUCt9eiQ7OyllNDJgdStlV3loCnpuWnlDcVE+ej5JPSU8NDh2K2FTOSkkc00p
Xj1aU3dJLWNIbVNxRlFRKztIbylKIypKYEBDVXwmSGs3Z0hQLV5HSQp6dl45XnZxRlJnbGUwey1C
WWQ3diVRN3VSb1dzQS1eUFY0KmZFQmd9RShCPzZeO1FBTzhROTFGUCZPT0NaeiYlNm8KelUyTD0o
a0dvJiZpN0lQUHpKYXV6PThuZVd7eWRkfGlCc3RgKHVgd0NzTUdTOEVeVCZiPjMzfGl4P3BkYk45
bSQrCnpgPmc5TyYwTVpDamItd2xAb0NlfSFtYGRYLVkpMFh5Y21TcVlkZ3FJUVV4SlNXfi1CWXgh
SU5zQEc/P0ZASWx8Ygp6VX5hQ3Azbz0yb3ojN1gxdWNAUyZDS1VMem99UEg2JWxMfT8zbm92c3pE
fFU3I3U0Mm40Tj9RTDVDeiE8dGo2dSYKejkmSmdfY2Q+TW5hNVcrIz8zbXVVK3lfbm80OXlxZTFK
dmIhbnRfTl8wb2c2dlhkUG9hXzhsPll2VXlpQjsmTiRiCnpHX0JtKzVSczB0anxHbl9pc0BNdih+
QyhqdGAmT3VtMXhSXmx5PkkxNV5BZHxFZGp0Q3FTbDQ5eytyVm5QISR3VAp6M3FRfUBkdXIlfCF1
fHk1YXYwVnsqQjloK2k+bXApaEVrJjZpUTU/UVJ0PCRXYjgpMmJKVk0wT3MwMXx7dD1uTnsKem5J
MGxUdiE4OUpVKEcrPD9KN1UrUk8wUHZqV1psRnQqcCVqT1koaENCfU9QZUx9NTA5bj5ITWp5JnxC
ZGx9ODRKCno1Wjd0O2hXdDlQK1Z3XiNqLX1sQ2wwZk0oKXRYZ1hqcD17PG1fcG44YXhZcjBBVUBX
PjJrUkFScz4mYUlJPj0mZgp6ZV4mezFXaj58SFBLVTNDXzM1MmMjY0U9NT5DVDF1JC1ibmNZKlhM
REpXYFhkSG9GTUMlb08mcj5fKEBESEZeamEKelFjIVQyRmoqWntBV1ooMm4zSm05NFQ5ZmB5WkFG
JGI7PUJpMkZkbjEkR25HQUBrWCRMKEAxbyN1blc2el9VeU0+CnotfjQ7ZSt2dWFlRTQ2KDQ8PCZQ
JVd0V1NwI34kO3FISUNpejMmM0VpenJJbXdKNWpSdCNNP2pxYDwyJTctOUlQKQp6cTRifEd5O1A2
dndMNl89bXotdzlxKzVReFdPcX5KUn1XSCpLdmMjUFd3OFkyRz9QeWA7ZT9HWDhMMGB3IWU0KlUK
elE5Nyt0SGZPbXdqUWZ8JCtaQk87Q0YpTSZiUFpRQzVaJU40dj5lST8lNFQoVy1DcD0xbmVUaVlk
aUNMPko/dDhoCnp8NWU2QUl+OCpjbVZUVV90RTAqYVMlRFg3QjttWmVUNSVWVDw8S2lFKmZAViNw
eEAkTmg+TjFQNEJzTEhkUXxqSAp6KE1FOXtmMjVEOGVkYkQ5OE9jM3liVn5KY0t8c0pvS1VOJiot
N0o5JXM9R1ohbXk/Y2Y/UGdgUlVOUn0pVVM2QXoKekk4KEpEaXVzSm1CYmlVdW18JHhWU3V0WmJg
aCohREtzPFJeIW50QVgpZSp1JUBMMDF8QE1gbG5eNnE5b0psWVY2CnpjcU5uTjIyV31YKGVHK3ZO
OW0pYDtsTGNjdCZeZjxkfUZ7amBMKzI/PF5ibGQjKm1SbF8pMDR5KVR7PSp2ZCt7Ugp6dDJ1PlN4
K1U1dzE2eVJOaH5KXzV4T3drUUZVRj1LMTlLfTVeRjFrNztxVnBJVjhQdFJfX2dgMnpNM0plK2wq
JjEKejwyTmRQd0hDUUc5UlkqeGEmfHk8cmBuTWE5QWYzRVZZSUwzZWNlNUlDJGs/Mk1NV3xUOH0q
ZmFYXnYoIUtJZ2BoCnp3UWk0Ujx9SDxzVVllKUpWNCE9WVlgRkd7YzVgeD8mXitLUExmPDVLeD9N
Sz1BIWN9O19BJExxTyomOUtAd082eQp6NEQ7YE55c3FzJEdAMChHZ3o3KUMwbEI5V1VSTEo5Uip9
ZmRLVmJXNTtabiplZzI/LTRkJjB4djByYWgkdjktZEUKenoyNmRYKkdgUFNzWUtZRGpyVWRNWVd0
YmlGc1g0JSZpJj11PDBzOD5RZlEjeWxBXihIbj43RUZYWCs/X2BBV3RvCnpnSFU7VGYjSSRxemRs
TUdhPz9ASjljXkpTQDl2c3RRRnpmY0c/ZXJidi15JWF7TyshRzklKzVpRXwyOFRVRj9keAp6c0Uj
X1JiYkYjITRgcGdyUUMqPjBWaXh3WXdpMk5iUil5fkdpM0A0WD0+YGlhbiFfQEtyfDdkKzE/ISst
ZklvQmMKekZ3KCZEbklyI1MyWTQzYHdMZ0g3MHpHe1YtP3V8Zy1AJGIrXm1Hak44VDluYXphYW9a
cFhkTWlYRl8weD0oR1JXCno1UTQpJHV6e0BiUG8lKEJfK1JBVTgtV0txUzFIOXo4Tn1NaGVGfj1m
Unh2WDZ3dz10XkQyZmh5c0QhLX5wdEw0cQp6dylrZUJpcDl8X2stXkt0IXNHViMzVmxeQ2p3ZkJy
QmE7RHZIVTkpKGJRb1ZDaCUkekt7YCE1N0Q4eFJHKVpudz0Kend+cF9vd21JfTFPeGVFZVY3YXZS
XnNzPyVpZVJ8UkohS1Ioblp+QnpUJSpEVDZRYnw1aU5YRWF4QmRPP05TUlNnCnpgUCtWJmFWfGtw
WVNYNWVzN3FZd3Y/MH1FUzxEVWByRmVXZStpMG1GYXpqUChZZGpZLVImfjdpVDFpSkVtZWFaNAp6
aTJnQEdNKXFWR0IyRjEkaVhvMWgxK1A1YXQ5U0dMa0BeUDQmfTFeMFVeV0d9ZWNEbmFyMEVnZ0gz
WlRLXms+dG4KekxmVGZGMSRYe29uJGdVKDZYOWt+ODhGMGk5R3FYSjNvcXJLTjdGd3x1Z3xBJUg5
bn4tNUF2eyhedjFMUG53UUhqCnpEKU5uPW1OQSs2PSgxakNpeWRYX2JUPGtuUWUtMlNjUjUjaCpe
cjA2SH1tbnxFdnFjPGRaJSpUKHx2R2cydURDNwp6JkM3anJOfGs8bXpVQFl0S0F1PUdCail3Y3El
RGBwIVZ5aTJZfjlGfXlgcmt0K0FAVUVhTzZWeksxRX1YYytVbDIKel9HKV5mTHgtUCg+Mld5KyU4
JSR3IWcoXlF0aGppQndlM0xpbil+PWQ2YllyU014KyQ5P1FISUgqNlNZfHN+Wmp5Cno5Zi1EJFNJ
K1hJMU8+UjYySGhPNEg2c1MwMH4/b3klKkV8M3FnOTNLYH1nelo0U1lpITVaPUR8XzhHfTl0UjZC
UQp6SE0zTHE+WldFRnIkaCRsNDRlTjR1e15hYWpuS0FPSXtuNDItT1ReKUlkSXkwSEFyNm4pdjNA
PnpPWVN9VWArN2EKeldhe09KPzh3WVdWVyhTeXVERmZXUHNUN3g0TkJgSmI+PllXeDNnViVVWWtR
fS1FK09VU28qVyRDYWd2NVkyZ1QhCnpIbX4+RXhsKTY/eXx4fTArbGNBT1dLfV9MWmEyYzBVJm9y
UXgwZ0pfWnc/K25TWVRXT1QkP3VZJTBmT2M5RStXMQp6diQlRHF1XmF8TEZfV0xgRUxeckU3IXhK
UTxrXzthTU0tWTU+fjFXcHlLe1NNaj1+OSFZTDFyRlpjYU52dUZ8bFgKejZsRHYlbjZKfkV0MFRC
TDE+KVImQkk2KkR2UW1QWHh2I1AqM0pEOWRAYXd1U2klM09iPko2TC1zfCQ5UyM7NEZaCno7cDxW
dmh3QVk8Uk05cVBteHpEPjAhbFk2T2lxR3REZTJQZnR0TnFZJElOaz8+e0AoQ3RHZTlNRFQkO3RT
c1I3egp6RS0wZnV3ZXw2dT9NVHZuWi17c0ZWPCk9XklYTGg2ekM0QGtONmRjUilUVXdmTG1Cej4x
NCFjfEhocHdAQ1E7bU8KejlybFBxIUI5IStMT1JQKktzTiN8SnlRO3MwQVlVMVF9MlpSTSgofCNW
azBnZElhS084elFrNkVvTz08O20xWW8/CnohQHtRSz1qUGc5RTEqTV9SRSllayt7KXpqZUMmI2Zi
QSotUjFhO2ZLcH4+fXpCflg/fCVnTXJKPXx0VVBVdVBlTQp6Tkt2RXlfN3hBP21XNWtlamcjPiZ6
RTtNR0t6T3pQKEhLYCZSSjBJKnhjVUNTRU4+KUd3UDZFSm97S3xOJWA3XjkKel5QI2lSK0dodERu
Yl9EXipEYFk4Yy1gPkkkIW4hXjVpYDhzU0VqSztYPW5ybnFMUWYodXJFRXg0I3VDN1QrM0tKCnpz
RTwjfk9wRyVsSXRFSUlKQ243PyomOXFJdiRWZGJ4VHQ3I1A/dzt0QXt2Zm96Q1lrX0FzfUZoUnw3
NUZhamt6Rwp6ZFNgajZ3d3xBaXg+Nlh6MzhnelZ0dFl3Z3NsQGAqKCRYM290S0hre3ImPkV4eFFK
VSNzamlXfEE1NkJZYHM/RWAKejBPZihNMCRDTnxvaFdsJj4lUFBLI3xXYko/cGFLb2M/eEJJKXFr
U1NWNlU4WiREaWwrVnp+cVg2UCgzbkJffTdkCno4ZmUzcll3MlImNnwwSEVXPW1waDw/NXAoVERV
IXMhMGtGek14RldNdSEzfSRwTm9+MW00SzxCS2orKypmaW1McQp6dk09Z0lqPVpyO0d0WG5jRWlL
aV9KcztaPC1ydip4YlQydyZFMSRiKT1FS1V5YkMtclA8MUhuM2I+N35KREJVQyUKenVQISg+N09e
OEtRQ3E9JSNxTD4mWmQoZnRUZV8za0g4bzRNXlVNdEZwa2BTfCNjWmNRcV8/Ji1aZ2ZBMiVMcWVt
Cnp1QzA2b1FiZ1p9VSFWVWFJPDMrdHpxJmZLWT98NFZGPGNeeUdMa3IrTkdmRiU1bCs9bGlUNEot
NlV2Ri1vI00lTAp6Yi1LRj1va2FURnpDMnJBVGduIT01TU9valg/PnR+bipaI3w+NkxjWEUzUkFQ
I1FTeDFuPVpqQz5MeSR8Rkw8X3wKemsoM2VHYmVtJClsNVhHXkVKOStxTG5HWjgwdG98cF5INXFE
IXFJYW5sYFY0bz4/MjN5K0RLJH5jZWlVOWFPQ01iCnpRX2JrQ1gpXlFecElhK2BNRzd8QSphYGx5
Y1V6cDIkYmQhPDdvYSV9cUN+WV95VnF6aEp2QztaQl9nUk49JCFzZwp6UnVGK2V1bl43RHlqbmxW
ZDlVbnhBXyROREtZPj9tMl5OKStmZVlGQ2t0UEVFMjghJGohck8rX2EkYVRxUHViP30KeigwPH08
ZjZpN3tXbHdkTGUrTGtgZWBzPGoqUlElSmtQMn0hbz9FWiRMfGpOVCFIazkxWlhSJioxXzQhQVQr
KWYoCnpXO1dKLUVeJTYkTzl2fUZgdzFkWTQ+RDZYR3BBNTlob29qQSpfaEB7Uzs/LWkjemhTRyt1
Sik9LU12KXluIXJOXwp6SUBtTVBCUl5xdGtmaEE4Z0BKKmdxNVFfaU15R1h2YHNSRFo1bkwtVSt1
YylqITBtTnpOSmJ9eXVgMTMwQnpwQmsKemt7VjV7dkFxMUwxc2BxPWBZOFQpQyYxYThUPSQlfnhI
dldIej9GUHZZSG1EZFI7bHJBeit7OFRrYGtxSDhwckMlCnpZSjNYP2czUSQmQlVESDU3d0E5d2BI
KWBMKXROJTZMU0o3JE02fiZoc3RuWmBvejBJNztHU2NGWCZlQXxsRHgpaQp6MCZlXklGM2Mpe1pS
NEZFO009VGArO31uMXgmcTlpTXVxJTxYRWZAbFRFfmcrNF98ZTNvUH19e2tyODRXWFVUYWgKemNR
WnBlRlFzOGRVQVR9IU5lM0JnRzFNUXhVcVo5b3ZLP01vRygpMy1ZaVg9P0FlYH1xIThMZHpiQzt0
LTxZbn5KCno4d3lkTD0mZjdWdTlkaEFtWHJnQ2d0T2huO1owajVldElHODl+O0VwVyRuNyR3PGo0
QTRsYTBuaTlETzI5YDl3PAp6e304MFRBQXZBa2tTI3R4KGRuNCspVS1eQVBzRThvak1wRERQU0o1
cSZtYWMjdXM0ZHlrZylWJmh0QXJ2dFltNEcKemgjeEtNUiRBI3N0ViMzREluVTlOaEV1endXIWhn
UTxPY3Q+TjBYXzkhUTxuTUttUytGI0BnRTJCNHwpXi1MSmRjCnpRPGk0N3lfeip+eFczVClOPmtf
KGRFRjFYTntFUHVIb3cwX2JJdiFhSWxzTzI2TTVHaWxHY3JlVnskSVcyelNabgp6bCsqTDZIaWN6
bkcqc3pFV3k5PWFPVlJ5ZFpUSXF7SUM/bW1KUz1vbyo8ZihGTHZKJHpZbFlBRUgmZ3VqUDk7SmsK
ekBKZUpyTE4zQiNDI0k5RVdySTZnQHprJHBCQChYMU5KKThUdmFUSFR6UGlqPTx1M3M5SEBsVHd1
UllxfFZgOzx7Cnp2cnA9PUJxc088R2plNjY5KjtAdSN4dTU/R0p9VFgpM0RvX2EoNEApPEdua1J5
KkpQNHRycSVPQnQzWD9EOEk1Mgp6OH1Fc19WYVBJTFkma2VzdlkqbUpJXlVAQGZhJmlfdF99X2gl
R1RDM0FiLThwSDxhbHJQbUpxY3stb01CR0xsKz8KekF+T3M1PzgtWVVlXnBpYWJDI0Jyb2BMISRe
TzNjM1Q4b1RBcUdVQHswN1Uza0YhQzgpXiR1VExZM3VMcD9IeHlmCnpsal5BLTtHMUFEc25tQ1dz
WGhsUUw3KUZDSFhEazY2YW1fY29Ma2woN3srQz44RCskV2A7X35oKVByLTA9dl5wIwp6Mzxlaz94
fXJoeSo7ZW1QYk0hPSQ1d1o4VEU+eldYNm1NPDVVc0ZYbUU8MFBOKDNFMXZaOH5XYXtMWVdvZEZl
b1cKemhiMiskOV5wP0JgRXxWWDxQfHcocmRwaj5Cd1p6aUIxPm9wMFY2ez9pYSh7fURINT1BXnBG
VUleOzY1RV9qZW9tCnpiUGYlQENUPHBMTWF7al95NThfYzQqSzJzOFRoemZEcWBTZVpreis3aU5N
PmEkVXw1TmlacT9fRGwwNDdTUUIhTgp6aipofmRsKlNgdlFMflQySCt0MTsoTERxa2w4dj1XN0VV
fW05ejVKZz5CMTI9OFhAa1lLNXpYPSpqJiVaTkthM3YKem84Y1N8MV44Y19qJjZOdzg1eWFROEZt
a2ZuS1NWKXpzdj1sYlY0TVFNWTFqTjtQaVNEaG01RHltaTEmdG9PaiNtCnpJSDFTTlNITzxiRmtE
bGpOWGZGaDdMRHYmOF9ySkE5NEA2VSlecUdnNEdSWX5eTWdEKkVqQTB8KGZvQUg5RTBJIwp6MXBQ
UXY8QkgmYG1GTDVYbWY7czJFUU04MTUxWDdlISpSTTJ7ZjFgcCN7O1Etdno9alBsQ3tKRnBUKlIy
QXYyV1cKekt6alBVZ31MNj1tKWxaT2QoVDR1VWpTay1tNXQ/PDdfcExjQCF0NyVyaU8hcWdVKU45
JF8/Ki0/TFNgQSRSMloyCno2aldxfUZVLXB1ZFI7ZD9uS2s7Yztnbl9sRyVLekNQU2tNZm9AdEY0
ZFN3c3daRiE4UU98cClBeTBnKT9GPyo7Qwp6Tmc1YSFuNWpsKkNtbHEtWmVPWS0pXiRwdmY8OzdA
Y1ZkQ3BTUT19bHI9RUtlKyZpNCNyOy1lcS1uPSVmVFcxPUQKekxKNzd6TERxPCNjKlIrUTZrUHJz
KG1LISZlbFF0alRONX09Vnh1S0w0QWFDPipHaW5UNUBNZHhyd3dBQjh0V2Z1CnpScTczT2FZRShm
IyR+MjxHTTFUWj58eCNFaVJESzZYNX4xcUJjOyhDZ1hme0hJNjVZJnJFT1NTR2FubmRXI15xdAp6
V0BRWSFYSz0rK25fNXhKX2RyU1gpfl4ocjA3c2U1RGgjPDYpdElDNTU/Rm5iPWZ2JXFhKnFkNT8h
TzVUX0xaeV8KekMqblBpVFhnaz1eRzVTJGVIczYqKUx1YEw4bCpELTZqb3g9ZjcjdD5TZHtAMD1p
KHpYaHtmaUQ0ITgkPFMqKCYoCnojJTlJQzZrZHJJc0AhfV8jSFQmUT5iQkQjQE9hZ0psdTVxaXcr
fk8me1RsUTQrWTR6SlYoIVV+emAlKTJPRn5OcQp6dVRORXpgM1dTMCYpKlFBRzN+cEJAOFNkSj5V
PnRMV0o0TkRpOzZuRDw9b1MpUnEkSHc4PUVRaCU8JHo7KCE2LT8Kel9BZF5XdmpiaD9HOE9OVWtE
cHhHT1ZvYVFUN3l5Syt7ZjIwKXUoYXZ0dFdPQyUjbHBvZFRtLTUpMzApWT5LTmBuCnpLYj1Pb2Ap
aEteXihKQGRsMTZHQnshIXJid2dDVVk5dVF+c29rRHdVWjV2WEdxJkghSG9RI1EqSlErbilPbTZY
NQp6N1ZKMkI/T3Fua3pLclBFOFlgYT9sVlQybig9ekdae29TbUpDdkdXdFJ1QTwrYW45WUxqYy1+
VyZWS3dSV2AtbDsKelB+Uk1CJHU8eGlEMGNHaGRldVR3R2NYe0spUnZUJUBOYD1nOXp9WUk/QTlY
JmxnVlRqISpZOUc1d1lAMDV4QDNRCnpAbDtlflBpak8mazIoSi1ENCQkd0lTO3d+YntyNV4+SmZa
RyViUDA5Rjk+R1NGcE95dHNLeytkYHhUN1YrYXRnKQp6ZEoqaW1mVWRQT1BeVXhNXzJMN1loIVZQ
QD5FfVB9NWM0eWNWWEZpRnFqbDxnNTl4TnI2TjltYTxpSCpmKyV9e3EKenh+VTFeVXdObjRaPllx
YzxTKmY0KUAyazxoczVLQi1GUSYhOzxBZGJvKFB7eWFHIWwpOWhJYWVLVlc8ZTZTMVhtCnpuKlRE
ZmFfKz9rO2g/SDRtdW9FejVSSFp9eXphZ1dVXkYzWVA2TyltX1pfV0Q+QlNGIXtQP0RgSGZuMSNG
U0p3ZAp6VUNyZ2ZuS3NNWDwzPHded3lqVDw2SyQtTzY3fS00bFkzUklYQlRMMGlBdz1BZGFyMkVr
Q0dqfW0mRmFyQDs7ZFkKejwpQ1I8bTdHIUJNRDYkfj4hJiQ/V1NRWjdLNkU3RUd0cE4lXlhiZGUm
TCoxKFl3eTI0T0BITTklb0pmNHg8a1RwCnpJVW9xfkUqRS1yeXJkI2RHY0gqPkw9TFV8OXlFUSQy
P2RjNFZNeTUxKCp1RlVoIUpLUm42dVJuNXU1TWtmTEhnSgp6IUR3OW9EbFI5SXVIc1RxVTJVKmVg
VERhSXE9fCo2dFVfZ3tYdTIofl5PO1F8Y0tmJlIoSGE3OVdJbTB2JjB0NkUKei0tNnQkRyRGfFpR
b0okWkstSn4qdyo5X30mcjxBN3FFZEpZTXVBPGNuJUJJeHR7YFY2TE0qbXQ5LVM5ej4mTWh+Cnpg
NkRhSz5+IUdiK24xTkFFJTc+fDEkP2t7QiFGb2A/T3Z3JGB7aHNKKGA8PmdwJl9SMGJCeXVAUD1X
JHlQU2p8fQp6VGRkelEzPCN2WWQwflpKPn1+VnZ1QiNwYCQ2QXdTbT8jWEQ/YytqPD9NS2hWKWto
YFIxNCFLY18jQT9tS2t5RWcKek53WChLNXtHMjxxODJ+WnRfQmQob1E8fkx2ZGVvQzw0aVQ9dk1k
bl89fChkI01tPnZUPDlUd2ZCJW9MRF9IVlYkCnptNE58YzxCKnNtRXxIUlImPF55czR8fl95Vzxi
bTYzRTI1X0xCSyRYPGZpJEB1MDZDZ09RVEstdVVtfnVDZjskYQp6QXk/MUY+b3lwZFE4eFAyWSl+
a0MpN0VgMWhaa1dxOFNMMyh2RERTRChyME55R1V1PUwzJnExdCYoX3pgJTFiVU4KelJMV2pqUmB6
Q0hVOCYhLShpPkBJdHxFVHZiazVlenVvRm89bllmLT42WlV7IWVVRE1WdHF4Z0M9M3BxanFFXzlC
Cnp6K358MTxXcHcmREdqQTs4SFNRc24zdkA5MUwzRHd5LUlJKGFfTElFSFkmWiswaWxZaTduYy0q
WkxjWE1xQn52Twp6PTByJj8kVmd1b0B9VFIjP0VnX1QtQ1pkdkY3OTRfcDwwMXUjcHdzb3xBLV5w
UmEqcyZ4SnVxOzZORShmNFMhfFYKeiZGa2x0Z0t1MzxkaEpUcU4kUk5Gcms5a0tfSXh+SSklT2VJ
NTVPcTVOOWgmZ0NkSXxZKiFKYWI9S0JqWXBqfjdUCno5VjQqTnZSUGV3bXx3TkVOJlgjSUBTQDQk
elZ2PHZrZjAzPmpjfHlnO0Qybys2K3prfFNWeW8mYzVkfEhXM3ZrWQp6cG48M0hrcmFeN1FNbUUy
dXJReWMmQ3JQKHl0S3gkYEpzYDNhV1o7KjlsLV5+Zks8ZlVvbHBSZVFxa0Y7eldFNWcKejZ7YCp9
QzxHNkBQaHN9diNwaEw1U0NoI2dBeFNtREtXYzxKOXtiKDs0RD1XOWBSQSR1SHA0JStFM2dePHh1
SnMxCmZAUEU7em9SfURTT3p2ViVUdWR7aHh5P0M7cEcoaHJ7UHpDPExESXM7CgpsaXRlcmFsIDAK
SGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaWNvbi5wbmcg
Yi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaWNvbi5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5k
ZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uYTEzNWM1NGUxNDll
YWE5MGI2MTBhNjljOGY5YmY2ZGViMDZjMGU2NwpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTU4
MjUKemNtWDlfV21zRUgoKz0ocU1UQCg7eUY+OSgrQCpNTjRVaXgkNCNuTEk2ZmZAWCNpNipueUlj
NzN5eCpUQkMpYnxjCnoqX25IMFhHYkQ1KUQkcEtObCphKjBFVXZIdFFHKE8xTntqREt0X2FxOE0q
IWIzSUs/dURhbEd7YCgmTVVfK31YXgp6Xz9FbkQmazE+LTdgSXVDcSE1bG93WFkyR0JkIXB3SVAj
bUY2NGZFI0I2NWQxO2ltbjtBZCYlZENhUW52ckdARUAKenFlYlRsbF5ueVI8VDhzVWJjfC1KUEdC
MnBWPVptQ15MdWJGVGk+OEtTVCpfZXQjYS03OUMmaGRVe0paeldhdXJsCno7b05hSVp8RUV9dn4l
U25OKipfflZATEgqTUl5KmY5d3ZOUE1GTU0qT3R1dXFtLWhfZUEzaD53OTx+JSt1SEZ1eAp6UHt3
MSg0Y1FtbyFpRDdVQEkzcjdsJmIwJGQlJHNWPH5KPlk0Z1dnb0MreVk3M3UmVXplPHlkPyE7Vlh9
Ylp3cHwKel5NNmRMUGl6QHlKVXsxX1NGaUJJU1VKa35QRTEqSTZFOTNwPDVjUmA2KGohWlJVc08z
Nl4mb3o4KTt6dFp5cnUwCno0RCQoT0RjT0glSVAzaTkwenApPCtsPzBpQ3gmUj4tc2pmSnowUV5j
bHZ9akxzfC1xNiVYTF5qP0olQyN4fkA4OQp6KkdET2FEPjg8c3g5RCFDUzI4QmFsYDFrMzVMWlVo
Qk9+QHdrYDM/a2JoSnBYJXVEQkF6Vj8xYyVXMXh4aTR5NEEKelZ7PX5tNyVEWH49eWg3bmAzb21s
JVUmKDUkNTg7X2k2PkIrKzJTakV0TCVgfkBIODJDVH57dHAwbEtBbzN3UyVnCnojS08hckY0Zmpt
eGJwKiY0SmBAfDNpVStEJGpXfk1BUD13ZCppVUxvPUY4KmZDeX0oKzYtXnRNMlpKZSprJEtXQgp6
I0IqMnZQMHV9UE90JEJFbVEpSnVSSCtCdkN1WWBqNXhDT3l7QkErbi1LUyt2WWFtPjg8TzJeWFVJ
M0RHMVclVVYKejU1KytCX29YRVE5bVVRRUlpSGpWdyR0WWYqem58VjxfKE4/VnNyKCtEK2hrX1My
SnR1KVJ7Y31NWVVgLWZyVlV2Cnohd2E0I3V8eml+TipNaW07JmdUdkgpaEVEOSpkX2d4SFNaTkAm
PnUqXjB6WG9RTVIxKCo2fWoldDtrT00pVWlzawp6cnwhN3RMUk57ci07UUhYeWQ3NXtLZW8yRV9+
emB0JFozWXd2RSNJOXNXSXtLRUFnekRCJGwpZ0lpUmMyYXY/YkoKem5pS3NULSM8SihfNGs8R3Jq
cm5VRktCcHdFLWAoYjRKKF9vLT83MXs4JDxwWXI4a0lURHFETDJUeklLa3tTKX1zCnpfVlJHclFm
dEl+VkJmJjNicDIoQ2l7ezFBN21fbkN1U2tQeyEpM3Q0b3pEN25GWVZNNWpMPytoYzBJRTNjPlZ0
SAp6QWZjbD9IIzs7KkxYKEM4WWFnbCp1REVhUHtRaD5yfDg0T1coa1RYSFhIRmdNY05OdlNfNH1H
ekhzbWZqbUBiNzQKenpsKDxPZmk+O25CdkdnR2BLMjBrTGg9NUVYJH4xaHpVblJBZiohLW5Ea3Bk
SDtIaVVqIXxseTdQN0k+Wj02eDNFCnpUQl9ZRSNHdVNsTFBXUkA2bV5lP3crbyYoWGxROFFhXylK
M25hXj9eZTFBUndKPyhxNT5+WWk1YjZRNjlyc0pqewp6V153JmM0fHZAbmRfNS1naFF3dkJHP3xK
U3YySkpLUldAdVkwTSpeTXZmT1BlSiVLPXhzOG5gSCskV0JmK3U3V3cKem81Xj4yVzk2KVArZjde
Mj8mMDRZKVcqJn1jUEEzQngzbFZSUzV3XylSSSElUjF8a1ZoQGs2cn1mKEkzLSE1V15QCnotZH1X
YnsjPHxCY3BRbT9SNEEwZmU1RTgyJXN9TWlKX2crZVA7e1FeZFA5eW15dzRZWHleNkc/PzV2WnVB
fSghMgp6Knx4NyNYaUIkYmB5PXJaQ2xCPU5lV3BWUVAySH0tLWR+KnwkTlVhKS0qe2M+KFlwYVV2
YzA0eEZGKWVHMXpPQXcKekF3NDZ4JT9wKGArYElkJG1zM3YmKzBecUp1ZFVzRVJ1a0ooP3xTUklm
VFV8TlFfcWNnTkNYdmZQMG9ZZ28rZCRvCnpXNjJ5SHVmUkMqK2U0ZkMpMXklbyFPRGk3c0V5Zkgj
PnhpUSZGQU41WlkrdTBPUGVhY2stZXI+d14yNDAjZVJ2aQp6PWQ1cDYjTkYkISk5Tk4zQyFwN1pn
KGx8PEZ9X0dAaURSSlgzdn1JNzZyUWdtR2p5Y1lLNmZrfHR+WjM9SXRrTykKejcwcmFAZW04S1Bp
I2RaOUpSakVHRkxiPnhtaVo8bF53IWMmZlRCNDhGNTRBNCVkQzMhRXxiZXFeUE1qJj9+aXZOCnpf
anhyI0g4V3YhTnRuT3pMQkpLI2phTzZoKktzKHwlRWtzXlo8PWlHJmB2ciZQRUJ9UGpfPUt9T3x7
czIhMjV5Nwp6IyZickBqLTVWTG5td0ViN2AxT3wmRjJpYDAoMSVTMWNgQlNnNjlxSlpGNHN0ZEB4
bShjWTduO1RnJSVGQ3hqbT0KekJwPyU1b2UjUjJfXktAXkQlSl43Rnc1fFI5WT1ReVVDd0s3QyFN
QGd4IzFLWGZwR19VTih9fGNeV1hBNztJTWhJCnoqSGklJFZCYnAhckF6ZE1ubiVBJTVzYTs2Ymlm
SVFiS3BXTjY4WkI8UGYlYjxPd0tXPVpedz9WbzxFfX0yPEJuKQp6P0Y5MTdDZVZJbEpWLVJrJF9v
aFQ/TDVmNzJ6KDI5c0M+RVo/Z3F+K0tkJCthUHNTSjQmKWJgc05zX2wtXmwpX2oKekh2JiNzUmUj
X1ZocVBOJlZDQCRTYUNZY2g+KmEjP2BwcTRydnJ+b1M5KFY7NXtUd281RnVUeWk7NjlvQztRdit9
Cno3alBgeXoyMns/UF9hUW5QPlElfT83aH0tK1NQUi0pM3k1Q2kmaWV6Wn1URlNXMCNqLVkwVlA1
XnFTNUFJa01JQAp6X01HRjd7cDB3azJ4WWprWSVoemMrbW07MDtCeyR2cDx1MUQtNDVFYlNrOTNv
NipXSUh0YjRCIyF8VSNXX3VEbXcKei1Pe0NiSDlEQ1JhPXdiJERuQG5OSjxYKVZgfEk0QEAwezNJ
bFVNU3xUU35fNzVlMk9RVFRnNyZvbSZ8VzUqRT59CnpXSWQ5QiY0X3QwNTdTdElrRl95eiZkO19q
K0hROGYpbGgrY3QpRmt6V15SY2c2JG0oMGhkaXBZQmRuXjFtRzFTcQp6I3R5bX5XXilLVjFkRXZa
SykmPDl5VkF4OGlJR29FT1g3flJuYnZHaXc9SnhfWGNoZ18qYnhjNGJfbmkhRWN0PkIKemV+d1dk
YyY2WmV6VXVqZHpAfWstNUQ1WihMNThVKSt1ZHRuQkhOfllpPzh9NjlBI3xDJCZvWlU3LT44fGNB
M05fCno3dCtyI0ZNanVMbVYjQjZTKl4kK2tVWnwta2MhcUpXS1ZmTz5+OG4tYGBLclRtdyE9O0km
aGR1dnRlWTdRSHFaQAp6aDlLWFkmMkJTc0cwMVRCMTVsSkZMYCEpRGBWNl94LVNEYWxDdiVlcEYt
bipMVVE5dm4jP0ZnMWxASDBUX3pXMGcKenVhXzVCVj8/T2QrbCpjIWpkentMWVp2fHhDKlRXTDxo
NCp0ZXBwLUg+b0pNQCVSJm1LNF5mWjk4JDBQQVo3WWxQCnokaUJYWCNRRHEweTN1fFAzVyolVThV
WEJtNm84IUgwbG5fQkZBX28/e1RwKEpjdGtrb2clK0FoRjYxdSFaJHpxUwp6UkJfMTB1KmpvZmM7
KCt1aShAanlISkRSaDUxfnRRKlV4SilDO016aUZvO3U5PnRvS3FWLTVtJXlJPEN5YSYqeWUKekE5
NjEkQGN1VzlLZXxyc2BRPj9gXkNKN2c3YTs8TU9rKUdkNX0rbktXPVlFNS1lJHlKN0BhZCtIenJD
eCswUiZMCnorK3lfZz9GWXNNWnV9dDN1YWBZWnNGMHNiYjBNIThveUtqfDtYNmNvcjJhbWxiK2B6
XnY2bEN6Pmo0OSV7YFhOTwp6dUdwSTBGc1UjTl5RKWVkVmdmMTNkI3VYKFM2Znt9SmNnUSMpfXV2
az1kbz1VZnJUXkFueXhRY3U9SVFZbjQpZmQKemhuMG1LVSZ6VnY5ckZtem4pdiZ7KXRGOV9ecWY2
a3F3fnRXdSsxNF5sMighU0M/MlohJTtufis5cGNzNzE/WVd3CnpZYipiQUhYZ3tMZFdoI2BkUDBi
cG9aUkZsTmFENUlmTjFWSTZmNVZIUjNJXypVMHRsXj5EYSFnRUo8ZkpQJVY5RQp6TjYwTm5yX3JG
WXRSIWRrbTg2Skk7TnFZTGp8M2RmbX5iaTRXd1ZnO1gtODE0NC1ffVZ2IWJiNyR7NHY9PWwpUE0K
enV9bjZpeWRMX1RKcH5ZZEo1cHg+fEloITM+S291bT0jYCo9SytoLW12I2RnMUJoajB2K18hQ0px
UGJnZnRnT1J7CnpPeV5GMDd9NGs5SzkxNF9gK1ZoUD49KSRqb3BlJmhxTk1XcTw4LThYdX1mVSYm
fis5NXZNM2FFeFZOX2hjfUA2UAp6NTYqbjMoKG9KTSZrPilWaClsdkdWdE50ZWFsT1lDSGdnSUpk
TmVrQypqb3drNj9JMX5OQHw/djdVY0J0QXsjKVUKekFBd1YwSzZNN1l0VkVTMUFLVGxvSnpoZkw8
LXE4YG1hT2J+KlZLN2VgOGBxMG1JQlYhPmMjbmVheiVIcCgyckY3CnoyP2BqY0Imfm1pMjFDXnNr
OVNIKDh4SkApdmRMaTdKbTwtKCM2bV9iIz1aVihmUkNzPCMmPDNETlE7Z18/OyltYwp6anhAQEkr
LTdffHNUTHo0X0VeXjhkO3laJUY7Uj48M1dzTkVTWlhFeS0mWTR4dWRtYD1tU2VkJmBxNyg/Ui1P
JDsKeiF0OGNPYnImLTkreUZ2RXN2QGw7cTY3Yns0SUBkV1dXNj5tJTMhPTZ7VX49I2htWjRnNDlj
WDEofVFgKihzdHZyCno0YVVeTDtoUn05UylWeyphKTNmVTFCWWxYIz4jMUJVeilUJUpzWU19PUZ3
bkUlR203eW90dH1wMERAd04zNl9jZgp6YFModzx7a25oJlkyMlEydEVMcD4zRT1gaz5jJFYyPXUk
KXA8OW1uND1meCMkaUIoblghcGtDdT1aQVRQbGArIWQKej5XMXRKezlgeytkaSR8d0hqTHdGM0sk
RUZEeihhVmg/ckF8bUAjPW9qalVYM2UrQzc/K31+bnBSTyp4fWFHQ29FCnpEdHoqWk1PMD5AcXQt
NSlFN0JDPlJ4WSlvQ0JqMmZ4aihZclZMYmw4a2FzQnB1ISt7Wl9gLX1hTzZQaiNteExeaQp6RVE5
KFRtVndNJmJUcE5IdWkxSzNGbVE+aEJDUUxJJjtwQ2I8TGsjUWJQYXB3bWl9OS0kZUB5MmdTbj19
JFNUal4KelNHQTVjWFczYEdQYXBIRTI8WHZBWjBiRE5eO0h5eGwmcEEmUyVaLVU0O1ZqdVREQDYk
WCtGc1RCS0w3LW9BNmZRCnpnRjQxQWxXLVhwMTx6c0tCPChIfnFJdGpge1doYnxjVDA9UT5ePUZm
c0dISUcqaCV4MCh2RUMlZWpoY2JycT9IcQp6Nzs9Vj5jWFp0NUJnKnlhdTY8KGRGMEF3JENHKmVD
biZJRXooOGIlNVJZZS16NUFGI1VuezV+fSE9OUo0JGdCKmwKeilBOXtzVEkqeWRhN0R0UiR2RGUj
bzJEfX5OVHU9MnFLaD5jcilLOT0peDhESzRraXk0X2VQb0slRipaaz8kU29kCnpvN1dIOFgzSH0k
XlQ5aEtAYE88JHlPTWNWbnw2dCNDNlNPZ2JERzJkRFF5eXtwWVZFUT5LQEJXbDRlTmA/PSVgQAp6
Tj9UWU9LKE5Va3wxPkVZNntUan1jT3swVmhpISF0WD87bGchelJ+ZT0tejN5Xjl8dkE8cTA8S3s+
O3F5b3hPMmsKel5qYCUrTyYqX1o7PX5Ab0c3JmxxJXVlRj44MkoyZnZqSDUxbCl2NDh3JihsSjNP
RihZQipyNC1WNmF3WSN2fGckCno0UTlSNHc/UzslODJPT3ZoKDJPVHgraylnPjZIfnl3T2NSPjI0
eXNMT2sjS0QhP1lZcmpGdnt9TGgxYThocXVSTgp6IW1RZDMwWX5mNClORUomQUA0fkItTzlkTHZD
SEF2ezxpeCt6TFZfVlItVnpKez9LMnNIeFp2SVFDVGFSRFUhczwKektpS2VneTtXVEYwMi0+Ny0t
YD9kPUpON1BsdGYmU0JSWChkJFBJITheMVJufGA2JFFAUkYoK2BMRihrPlYofFNmCnpvWTRnK3k0
VW8pO0RtNC1zJDJKIyFqTmVhb1A1M1YlYEQzfnVGKTMxdm5iIVFEQVYyeU9QIXlrXkFVfT0xPn1a
ZAp6cShvbT0lcHwlRjE1JEYmZVI0IytvVURPRyRPK01aaTdRN2tNMXdiUml4P3QkWHxQd3ImMFNt
eTl+VyhWQlEjPTsKendGenVfXlNQYC1lb2hoOSZtYkFhLWpYb3xobGdxc2srO01BbDFSeVY2ZDhI
V0tOI2pSdSNfV1dPK341U0YyS3toCnoqJm5VbVA5YClPZXc5WUBhXk9nQUJiVTZ4cHFlQVd4O0Ap
JFRnbGxER3Q5TlAoVnomWTtlYDI0RE8+bV9WZEJaawp6PnVpbEFmPCY8cGo/Xi1WbmwjaShSV1hs
R1h8VGBLX09vKEVDdCpfUSFVPisqLW9wWigla0YtPExHK0FaWHBuTXgKekpFcVRfez1ycGp4eWlf
JE98QWxFPGxve0ZWeE44Uzx4eCo8dllXYSEhPjF2ZWdgMzFtXzBNSHJyYi1WOVAjTV5YCnp3K0BD
Rzx+WlJQcSszaTEzeSFUK2UjI0BqezNZIzRhLSttfWt5fFpQdzFrS2xScEo3NGF8MUNpSWA7M3tB
MW1EUgp6M2AhbXM8JlAmRmlefENoZ0RDRkFoZj97KXlSJF9hJjc0JkQkRUk+ZGM1RmokLTM9S3Jj
eCtgNl4we19IcTZMQnIKeiF2KDtGVkN0aTR5JEk/OHp3RmQoNHtpI2RHdGMoWi1sI21DbEU/MUNm
NE5LMkstUyQ1QGNaZj1FYTxLTz9iVUltCnpFP24/aDNlZ0UmP1c/SmUxT2FhfVdpM35IMUM5Sm9F
fEBAaiZKR3tBdzZEPXh7bTMkVnhGeHImeUU0X2pBRCNVTgp6JHw7ZVZCPHx0b1Ize1RrPWg5UWha
eHBRc0s9K0Zze3MmNyNIUz0xLVIrP2Fmbzw9WXQyX0ZMbiYyUj9US2FGbGAKekZ0ZUw/MyZTa0tI
dXx+bWo+TV9wQGdtaHw7SDljOUN9KGQtMTkrQG83VSRIOWZqKmwhJHdMSjFlO25XVEc9dWxSCnpx
Z1ZNOGlebXF2JStSQj4hVzxxNyU1JkJ5Tj9IbWw0UF91cm5uZ1F8M1ktQ3hxd3NOOyRDQzBsTlZi
NDA8ZGJSUwp6OEhMcWpWX1NgKEg/Rk8hRT5Ke2I8c0xtKCZsezwwP0c4NGJRcFMpemo5e1U1bjw3
ZUNLcD9yMCNGTytodmImWWEKenJtN2swNihaKlZ5ej1MSTkzZDl9PUxGcXJoKEtxQSVONEJoaTJ6
bGNMYDA+dy02U0Y3Tzg5JT15Vkw5M2tDJXZuCno+NzA/MFVndTZCTlBLfXR7eyopLSVWJVZzLU0k
TGI+Pk8kK1ZLfUpZWENmZzYkI28oSkh4a3R5QG8xKkwxYjE4MQp6ZU5BZ3tEXyt+dDEjS042Tk02
bmQwYk1RMEt5T0RYIW1sSUR2cT5XenJONms/NyNBRz1SVGhhUS1uMFpVbk1valMKenZjTz1mYUFX
ZEdMJHIhfE1SYW1VWX1US0Y5QFlBKVBhXzh8U2tBSl8pKytTQlhvZkZpUkl6VUlVcURpek5AWVgo
Cnp4U0s1cVJsWVZaMkQ7OXRkVFkxYztIZUFBUmdSYTElVXdpREFGTT9SUk99dWB4ZERBPzdYUGo3
XjJhYGJFYHFrYQp6c09gNzctcnxFbDZBOXlBWWJMSVM5XlNJTFJ4Yl51Mys+USYjOClMJE5hJm1m
ezBMNEc9NVZgQk9ZbUYpWnxCfnEKem4rO3RRd0NOWEUxRCt9MF4mJDZqMytfdiNDSkwmb1MwQjUr
Nk05KnxzVCRJYz1HY0dWYykzJTVKaH54ZXZieFRACnpFUUh8YWZ0OEpoZ2NZRTQtZTxHaVolSk4r
T35SMVQyaEVgT15HIUlPWSZrZ2x1I3xMZT9gYjA8eHBldSRBNXJ4Rgp6JGNVeHYrd1RjbmNSUnJI
SEc5eG11S1I5UGJ4fVJUQiROTXBnLURsVW1WQlI2b1duKVkyVGwrancmKkMlLWwpY20KejgxeWRV
WTsjcGFzSX1BeT1lPCM9KnJINUUpRWF7UmFKRHt5KGUqNG9OcX1US3hnVXtAXjs4bGZaKHtiX3E9
K1Z3CnpoSTd6YUt3UG1NaEt5UkM+QThUcCtTczRXd0JfcEl1PSZ1NCp8MmZAOUVjdWFWTnJPNSQt
UD0qaTYjSSFlc1FjJAp6djdOTiljcX5hRDlRP2lJX3gpWmFSXiFEbEQ1Uig5TUkxZ0Z4K0JrVGc4
UTxOdD9+RW9faF4mKCpRWHk9SktgdjcKej15YXcmZXRvcFFhQnRzQS02KDkqRFB8az94dVQjO1ht
Xn5eckU7NVpzdU13bTU8d2RAZjI7N04lRzNgUV5kUkVRCnomfiZkLUhyV0F3SVYlanV2ant5YE5v
bilgd2xecGVDPClSb0c/VUlmJTd1RSo2fXNXcyo/O2FAWjE5fXtOSyQjYwp6MGU4PyUpRiErS29N
b2NTPVNWcT9IZnEwYDVxS2FIbFBgOUprYmRqPlphanpUJUs7JmxpTjdUIXM/ei08aj1SWFEKejQj
MVNtIS12ejFWSWdFY3hUeCs3VEsjVD1jWHpJZzg7Rj98OUx6NmpPMHYhNzRGTmtQUSMlQ196Tjtq
cmZpMFZMCnpkTG5OPWFINmFPP241KnFeOThwbnMtRkQhQXtTPCNXKll2NXtpeH5rI2pwNz05VnlC
NXFjRDc8PDc4dD11c1FSZAp6YSVhQGYxX2t4SVhSS0RvQG9aNHlDV2FZcXlfVUEpKnRJbTBYfiFW
fT5vNmY+KlBvOS1zTyViayprVmxKRiF1cDMKeitMQT9AQnQ4TUA0K2JQZ0hJIzlkKHhDNiZ6fkY1
SFZQb0BhYGN6PFExZmB1R3VjSiZSTzJ5RUtQYnZDZXkjUHIrCnp5M0h6IUxeMk88OyNTOS1he1pE
VDlWY3ZGWT96ZHA+fEh+cmx9ZjA+PmNfckdae1NeRytxUD5lR2J3Qks9ak03ZAp6ckx1e248bDc/
QER1bUVFdW87YGpRaXllPlhIdjlBYEtKakxHX0s/dkRLTj49bTA4cU58STRxJlFNfiNMP20ka20K
el8renMzaylka0t4T35FQFM/QU5zTFNrMD8zN0owTHJJOCZOWXlFK3pMVUZsdGtZQCFhO2pEangw
WVR3JUMxfVZqCnpzZW91ZiRZITFUb0FgO3ZAalNPTTZPcXNwWlhySEo7QVd+USYjSG5VZjgxVUVk
c2JkTktDMSVYYSRRUyZwSVMhZAp6bzVQfDRmTjctTmJUfU8+QUBZRlIrUS1WNVN3JlNzc0xVRVch
OHk5WEZWX0UlPEQxbk9QNTVwayF6M3BiYCYtVl8KemxtYVhPIztNb0JGQkdOX0s5ZShRdy14SHNX
RH47VEFuNVdgOGEten55dVZDVzJ2amA7Jlc7LT03MndYeks3OzReCnpWVm5XOVJCdFokUzJKPj5Q
a283IyNkXzZyNDlsQHUzMjJuSV9fPTxNWUY8ZlVCTl5RY2tiVEEmPHNOMTIhaHlSQgp6ajY5c0BD
SXFUbkB0WG13V0Y9ZjZQMDY3JllZTFJDaG4kc1I/XzZNKEgydWxLJVlvcENIZjFzUzVTdVpAKUhQ
ZEEKenkkPD8oKzNRRktUQz4+fUg9QElyWGV9Q3NaQiVKXztgQEpwe1VKNUxzWS1EeFVPZHo/KkJG
aD1fJTRDOWhDc2t1CnpxWCZHUnJ1S0gpPWVHVHVvSC1sS1NlamQrRD55K1VDLWRQMmV1PVRkSHNB
PEM7Q1BxNTJCWEV2PypZdz4pOWZQfgp6azZYSkQ8IStvcFRAQ004dFE8RztDXnNrY2BQdTAlcz0l
Tk1FPlMrLT8kbGc4MSl8Vy1TKFVuY3s0Yjw5aCZfclAKejNvNXluTEE8TDhJTithRlooKVZQc2pN
YkZjU0R1TUx+flFva3JZWl5pRj07aXwxSD0hTHJJSmBtVHVXQmhOTkoqCnpWOCN9a2h4NjhlJjFN
SGMzRChTYnMxbmJ0O05OTXdoe2JzeSVvbTRUOVZ3dU1Pb2MmSUJkSlI8VC1md3hyeE9zVAp6XnpN
TzYzNntRMzM2QEwpY1VEVXJtR15pRikmKkg4azMlS28pKFVwdihIQzNge3soVURgUiFXPmY+TCte
NEFTelgKej52aGo2KHY+eXIqLVIrTiFRbnNXVTx7UklVYl96WCY3dnZaR1A0STglP31KdCtga0ZJ
RElVTWtuQUJicHZGcTFvCnpTIWs9WEshfUw5dklTQTR4KnV7amhUVWMwY0t6b31LYmQ3MG9eUGo9
VkxBJUlWZEZNfFBFYm00a0x4cTRzVVc9QQp6UDt9PyU/N2ZTJiFCb0RiLT9EYFNHc1lTbS0rYXFv
MUVYUmo/UyQ2PktlKzhCPkBYXkxzdWI+WDFmPFVrd2YzUyoKekVNMXt2SilGXiFKfD1BRk5hY3FR
O0R+JSQ8UEQyQFRtdiZEak5ONEl3ZUIlWVhBe3IlRDlCVTVESCRHdDB3NT9CCnpxfi09a1l9V3Yz
dERXPmZUIW9tRm1SMTR7Py1hVHhlaVA1SnRBRT0qeU9iIURPZkxrKHcmVSZ0UWh8K2NMYS1aYQp6
Tz93KSZBKXlaT2xPMSUtRmEmdT8jclIpKi0+d3F7WWRTSjVATURWb05NN0V1M3dhV0ViVlZBYzQ5
VnsrSX1QdjsKeiRaOHJ3PXxoRWJhNHdVPHpmUFchaTdsSj0pOV9+OWNMJD9pWTBiTTNzY29LKT9y
cEgrUX5ufFgybDRkTGMhdlBaCno1KGQyaGUydTEqb2ZZOTB2en4tX1JTQXFNMkw3WEErcklnMFBW
WTBuQVdDRWRkaTJ8OTF8Z0AjaFc+Kk1UdHVeXgp6Vm48N00hfWVmPUM0V0RjLU5oKzI3ZyU0cyVT
XkdBQzREOXdgYE8jYGkqJkx1R3ZnYT9iYkNLJlAqSEF9dn5NcDsKekN3a0M+MXs3UU1qQER9fCh6
SVBNITI1KUJBJXJjPj5RJFdFVXE1P2AydioqfDhAKWN1NV4/N0dMZHd0dkZ7NkVBCnowQmRzVW1B
Z0tpU05eOCNlJT58eFJIJmhNdmhSYT4rMEVNbCE8IU05Q0U/NzQjLXNFb1E5TW1TOXNIQipzLVp9
PAp6fE1MS2hibi1YIT52fj1fcXVGWk12djtkSmRWTXIpTSlzXyhxLWNKMDE8enBLUiVpZGxkNmJz
dXRzWTJyUWh+NWcKeipXSDNsMkdYQW9taXcxVihudm5ic3VWRSYpRT9pN0NvYzM9I3M/Mnd3Xkxv
NnJ+MlU5VCNvUjJjMz82Qm5IVD5kCno9N0FVV1F9JE5gdDExJik+bnZMI3kheztUdl5LRCFUPWh1
Tj4yMlJHKGs8fVM5NnlfNHNYNzQrbjlBbmU8UUhJdAp6YCM2T0xZKnZ7aXdJSm41MV41YiU8bThl
cEpBRUs1UFFPNCZwMU5HRSZGU31qY0dSZHAjU1k+XmNwOHpeVn5QcT4KenZhaShBZDMtQj48LUYk
cSFZX3h0PVYpZHJ4fV9iR28jQV4+VmhESmBuKzs1VmZZMTgzOUBBank0SDsye291YVp6CnorRTFV
TUJwfGlDV08oeCV3OUlfdS03NGstUHM4VEAjOUx8bS02OXhKUUBFfH0xd2FqJmFWKkQ9N0B8Y0hC
UFhofQp6NUxLVzchJWYjQzB3TmJ0cUgyOXBjMldEUVlSKz41ZmhzU347TDJwJmRkWmBiMThraDA+
MkBHJiN5cF4yZEV5cHwKekpTakQja3hvY1FmOX5tSE5KaCsoMn4ocSRzbjI5a0psQSoyYXJzI2lm
YUdhdFE0N0RAYTxzIU1PcmM0aGhWMStkCnojZ2Bza2ZaeDQ1bFdmTD1VfEtPQjtDcnZLMSVTQSsj
JlEleXtBTkhTeUc7fnJGQWpVRHFSMzs0cnxKTCojPG1+ZAp6SGk4a1RKcCMycWw0P3E9Ml9ZVWc2
c3o5KVZDTWRFVDIreVZJeDRpbyRhOCZFUD1gOWdRMytTdTZtUXhEXkZuYEoKenZwa1QkWkRYeXRI
fWhWfEt7ck44YH1RVWg7IT5YanRtWmVQe3VMdllWQXAtOT9rOEh2WWFxYHtxcT5CejllP3xYCnpS
LVozMk1uNUQqJEplIzkwO1p4PTAoQzFePGloeVNvMWY0M0g5Q0h0YHFpeTRvc3g0PmtebnVVSy1Z
USl2fDwhZgp6SjljYlBqIStVYCF0d2RsRlVXMj98QVFxbWcqfipCZzhtejcjbC1tIW04OV42PSEh
dUk/N15oTEJ5SF52Skg+LUMKekUrV1dWMl9xQDlOSFgrQE5DfHZeKTBQeFcwTkFjVzNIRCl9WXU2
cHZXJFRlMF5jYyR5aytJeClpZChPVmRuQXBVCnpSQE93OFcqellgIXxYSmVeeHpAbjE3fURnP2Jz
YjdjU21TNmRGYHFhRitsTHFMSyQwb1JWPENDYzhLJTJre3h4Ugp6TTNCKDx2VT10NjAxYFBBJTMp
LVJqITxpLV53PShhMkIqZUdgPUFeS1B7JDZwKjBZPExVZDckUVA1c0U+NmpBNkMKem94RHZUVzco
KTZwUT1hOU9RUVpART9DOWolfVdBJV9KIWIzYzk/bFEhNGMqWERjSjl4dTd5NzFyZDgwNGomaUt5
CnptKV8zUGReUldjKz5CLUNwZnt9akQtfHVoaSVKIzc7NkhSOShWeVg2VC1qTDt4YFJFVTd5Ql4p
dXBYST1XPk89cAp6ZEtaYGNFMlhXSEteVnNmMGRsbjZ2LW85Pml+XnIpWmE1U2ZtSDN7aXl3OTk1
MjYtTCo+S1Y2antrN2ExTzYlfTYKem8tcEw8YTdDRi0+YXcjV1V9PkMpIVheVz9pelZJSEJlO21I
S2RpY0RuKUs/c1diM2VeNyliQEM+WEcmYWFNPHZMCnpfJHY8OSRNZl9ZOT5EPHMjYWlPdWQybml1
QyVxOWoqK0Y4R1pzfG1HXnwmd0Bpdlk/YzxiUV4ybmhoaUlYNVhCegp6Nyk8Rjdra1dvOHVDKD9u
KGNjM25eUWpuJUdYMVE3K2hLR29YPkdqd1RjPF9GQndFQ3heaDxiSVA3IX4rbkk3YkkKeiNqfkJ2
JihrPmtTX05BV2ZkTlJNPkdHTkBiRjVCQWt4emtyQW4xWkU8S001Q0smVkZ8d200dmM2K0BCZGRv
WnRvCnppWGg/LTl8N1R3dyV5T0A4QjB0KnZNdyR+eE9qSzZMXmM9Y3szdTBNYWh5WDxXZFRvTyZl
SHtlKXgtdVlMWHFKMQp6KEZ+PmgoUjVLYWlXaD9YXzkxR20oUDlUdDRPajchZ3pzYl40JkBYb0E2
bkg7WF5aT0VGR1M4K2IjRz5xRHc/SV4KenckODt8QD5pa2Y8dzBAYHteeHNTTFFqc3RHKGNPZiEx
KE1kVn1lMEtkU2A1akU8e3h2IUcrbz9XLUVTNjQxS15lCnpJeiNhXzA/c3hNUzBRVm08dEt1ajcm
czJiQWhqUSRHSyZRVkNIIVombWAyOUJMQXVTVDRFJGYoa0hORmZ7UVgkTAp6eFc5I2xXKm1jfWZH
TktpNVApZDVhYDAyal58RTQkcEdnNjxIZ00yYyQlJDR+KXphJWZORGZBSFRAfWQ7R1kleCoKenEh
enclblh7PSo/SUs4RygxVmhCI08lXzBHWDxOUyY1LXl+Y1ZTM2NET2R0IUlUYD0qP3tBO2V1fShC
LUtGQ1MyCnpNZCtZYiZTRkBOeUplbT5rZV9Hcj5iZyt4cyY9PmI3QHdCdWF3KjVHVkV0P3Q3PG9e
WTk1Pkx9VTJnR1Q9ZURxVQp6dnpMc2IwJkFrS3owTHAoeCZpUlc0UE9sX2RxWlR9aDgrX0IhOV4y
dkBzZil5M3RUUkxYRjtoflFYe3lwTjAwcFYKelh3JWpBNj5zXyQ1bnUpYCgrZ358QXl3UUZtNHNA
V2hqbGxBaj9+cUJmcUtGPVM3SDNnJThWc0h4en4xJGBxfik+Cno/aG9+RCFgMX1rPzZnN2BTeUFO
dWxueWRAWk5ANVheSzxMUjBLQGpIbzdwRUVUbFk7UUp7JmY0MElYSTApez03awp6MyEtPHRLO2RX
KmNRSE5YNlkjbj9YKit5QFRgPC1YRW5CLSU5ZyR4YFgqeHsrb1JxRitweW1teTRkWiQ2Y3ZXP3YK
emZRan56QmFtMUxsVWEhenNNNlNkN1pwNDdZJHJMSmg+cUxTKyRBdlUjQkQkaT5xM3BNKHB+LUJi
ZmZKWD9yNTJsCnpUNks1MiMtcz5DS3pkVT16KSZsPXB0aCF0a251cmtte0JIZzkwcDw1dXw1PD1A
O2QqQSFLYDhSV2lIVCF2SUp2LQp6UFVRWEoxOEFwenZuKXpLYENAbEdOeyNrZlEqeVJJY0tSRFAr
WShZaXNXO3NETXxjJEotfW9DRlBoPGdpQnQwZzQKekZ4fTBlZDlZQktJZWsqSShDMjREeDhIfWpS
UXtrPSFmcnxqUFozIWQ7aGpONW53MkMrV2RXMmx2dFJ7ZjtHXjd6CnomYXo1NEt+d2VQWFoqO3I3
JE5iNmlNRXQlPjNAZjt5TEtlPyFRYWh1WU5QRGRfY3N6fXI0Y3oxZ1dqOFY/M25xPAp6aUttQW1L
eDB3YDIyNE1rIyNUUCQ0cmp6N2o3PDZ2cnJqeyt2Qno0UTJUM31WU3J9QGV2cHI7RkJSZmZUY2dU
cGUKejBMX3JqPW9KZ1ZoYD87PjNWM1JwQll1NXwmcj00bT8/Z19pMHl1aTZWeXdRZFp5czZ1MXBo
c3tYYiZBUSF2bU1LCnpMKCVCYFl5YjNjT0MzbC0jamRwOHtxdk51LUVaQmtEam1lUypMP25mSlo4
PXRTKkFCSj9FU2Y0T1MkaHw9TkZ4Kwp6SCFlY3hEJWFITDhRZS1EVzQ5X1JXWkdPUntHLTNlMDVS
KFh7IURpOEl7WkZLJW9ORD09VDR8MkwqfEtHRXR+TU8Kek9jVikjKTZNRXB4NiRiclpwcUVfTkkl
QyZYXiVCd28kJGcpU1cwZT0ybTFBTVpWMnN4ak0wMiE4YmN3cXJ6PX1XCno/SlJDRzc+X05TYzJ0
NkBpK3AqNjRWWTZYZ0VaMlVoWm8rM0xrITw3TnA+fj1vI0FwQkEme0FLVlR6SE5lTEp8PAp6LTtM
Zigjd2szRG85MnplPUQ5V04rI3p1TDtUSG1OcCVaTTsofjZWJmx3bWIoV2dpM1hkdmgqOTErb0J9
TTVnNzwKek45X1FvP2t3bj9oeSYldVh0Xj1YR30pVzNMX1E3JiM0Pn5YRl5JbFIyPFE2bXBIazhP
MXdWbmZkc09oJXd0ODJ9CnpFcVlLezlxVDBpPDcmK1RfQWpjVUNoKmR5OVN6MiElXnlgZWl5OU9i
S3FJPXNqRWEqPF5IMmFBRi0tSjgjTUMkRwp6JmdyJnZWM15sKjY8aypIdHs5JHFLezU7K0gyUHBO
P1RKbnl7dVNkMz5DLVk7S1UhTVRHc1F0VEMyPHl9RGIraCgKejdxTi1MeWRJVSE4Nlo2YVRlaSYj
eTY/NXJIamI4IyFBQ3F9MyMze1N3OERwKUFCZkE8aCo2VW5VRDVBIz9pa3R3CnpUb1NuQHglU19q
eGx0PTB0XyEjTUVwUX45SzMoYXUjeFBRREYzNTtIOEMpY0txO1Y9Q19saj5qaGtsT3ZRQGhXYQp6
WVp7MTI9KmQ9MHcxRERJJWp2KyQkYypjNShIS0o3N1BrfDcmN0txU3d7Ul9BWSNsKHRUTVRRdTR1
T1k/TG4jYTsKemUwRDd1Nz9zUDVzdipmNW81bFpuX218TEJ0MjQxY0xkUXtPaXQlMmJZfVhlIWlR
KlcreWxTIzhyJmhGPEM7SHo3CnpIKzEodS1tVFd9bkxpZl82SWFmYmM2Vjs4cE1SMWJpUkA+XmFQ
Iy13R2Y0UypvI1lnS01ZU0tEQUpuUVJ0b296cgp6aiFhJE5BeTh2QSh1cEBYe2ZJI0Akfk9QMzg+
diZAd1Z0JChyWUtPbj19d2NJN0lCaiMqdjViNz1QaHxYO302SE4KejQxV08tPW9NaU10NSFTZmot
Q15hY0FGNFljKytXKE1UbnBFdlR3YGptY0pIS3c8KDtOek9zOWZZSio7YlklRGUwCnpiP1RlcWVD
bjZMbz1Dakokfil9fllqPWhucT1takhlREdvYVctcjt7aD98UHdpciQ1bm40b0tHVCNRQUNaZV8l
Jgp6Q3xnd2ZxaGMtTzF4TEVQKSlYJHlaWlpRVTR4aSk+MkY3JT9GPSE+c1lzeUpfK3RtaEAtVzJM
bkJWJHImTF8oUzsKejxqJkJaeyQzSCpRVndmKmk4SHdIUEI5KkQrYitPM3A5JHM2KX4hSiYrLSRz
N2xUUTk7S1ghWV5tJC0xWmR5IzFxCnpUMD9KXk0yJE5YbVROaytsVDVXLS1AfjV9NDImP0hwfEVH
ZyFkdypRdStOPjtqcUNicCQmSH1RZUApTEJMeU9YdAp6TXhNQkxjQjhoTDxqNjI3T0JibFVvSEZ0
OUNLUShsNGZOdVlOdm59SURpRFoydUQrY3tJXyVhezwqMitgTGFKdHUKengtPEw8SHczb152aD5w
cVJMd0dgODJ7cWRROUpIRD59UGxYe1MlWHw4RHNkUGlROX4oX3J2OztIPlZIV0I5PX1sCnpDZj1v
PF4tbkNadUdxLUJQKTVoK3d9fTRTKXpuKlRBfV9BZEkpcU5RUnxLUV5uanxlRmdgZj8yUTNUJWdw
PDNDagp6X19PXjdLUSR9WXBPJVkqeyQwKDxQT2J5aDQ7MWtLI2tOP2J5fExZWnRfJjIqd1YwV2FC
NUpeNEhDbzh2TGRAKXMKejc0Mj9RYSZQZ2pFP1loVlMzT3M4NTx5c0EpRj0oUyhiNDZVPnkoXml7
T0o1K3ZKSC1KZG4zT082OWJWVjFpJkdiCnpBTSNnMVVwLXQlTEQjKTlqQ0FtYV4lMkFVK2teQDl6
ZXdhaGhSSGw4VDk7aDRTV1p3b3F0bHNrZGckP0BgYiF1Mgp6VDBYY010QCl6PWx5IzZge0FMe3hA
WUNOP3g4d2l9an0jYj1sej4qVFYpWnpec2lTZkUtUCM3blJASGNCTEp9QU8Kekk/YjFmKnsyQ3s/
UWdoPXdmM3dePFp1SzxkayU+MHMoe3RKQCVgdmFHYGx+aXF+VVJZWV9EPGBWKEVxRHN8b0xaCnpo
KzZTIT05aVI4UGRVOCtIOXNQNlYqZiFscnIhO0Y8RzU1WG9ZITx1c28tQXBjLVZ3RztqOXU9QlhY
aWQzOyYlfQp6JmJuMjU0fXtzRmE9KDlsYFl1a3NOSH1uYW5+VWU7YCt+ZDljUmAhLVVDNz58aFQ3
bHo1ck1xKTR0UGFAMnhWISEKekpuZCFPbVdsWX4+KVkpQkFGNDFWTmdNRXw8YHZ2Z25iZFdJaio8
eD0yI1p9am5TLUomaDQxP31XIUkhIyFxPEFVCnpQPGJvdWwoYXFiQW55czBjJkpnRHtvVkZrYyZJ
Nj9AbFU+WighYFRrU2Zse0J1YmJOQT14NXVmSHMxJkxFXkJ3cwp6RzxIMVBxT2ZRY2BvTigwVihK
ZT5aYUR3cGEpWjFuTU1BR1dxYUJsUiQ9MiRoIXh4V01ITGE5MTRMZyYkbnJNbCUKenVFO00tWUxV
M3tVb3ltOGB2dDtzUlBoM3JxdXgyTTVNOSNyTGU9blVPTklOUGsleSpMe1oqd0AlJGxQSUdtOSZS
Cnp7VjhPcGR8TWpjTkQwMDYkWkIjQk8hYms4VEJ3RnNyNDJrWUxFc2spMyFJNmAkcGZyfD5peSlp
KEhUYDs5MGNuewp6QmJNdiY5LUVfPmErNm51O2FeSktefjRqeTw4PlVhdHcmYmdNaDk/eylqTXhk
SXlXZyNMejt2TllxNEchPFNkWUIKekNnfXRnVFVJLWE8IzIqQGUoe0Q9bTh4VC16ZkNWV0l8NDso
TzhUfEB6djxRUmBUY0lAV0BkZldNIWExMFVvM1FOCnpNRT0wYDtvPW54R3h4M1NpTER3ZTJneDhP
NUFxKXZhJEEhcmJ8TDhAMnJmbyQ+JlRmOCNILTReNHk8RTFtU0o4aQp6TTUhMGUhc0V9TE9MdkVF
SkpWdjIoZ2UpdSE8IyQzeiltPTJQS3BmfXprYj9xN2QxTChOSio9fUx7OTJlb3ZRR3QKem5yN1R9
TUo5K3FuYWF2SytvZn1nNjY5Tm1LeEFndTdhd08pUmJxWVRzP1lZRTMqPVZEaSN9VDNVN35tYSNs
M1FHCno7PjVTTiM5RW5iPGltWUMwdEYzfiVsUHxAbHZZNjNfIUNwSkp4SjghYkpjZ0tQMzBSfXUk
d0A7SEU8VD9xcSpXdwp6JmlaaCopOG4qaXhTRWBUP0A7XnFYTkNDME07X2E3NktyWjZpeUN+N1ps
TmIlQlIjIXRyRjJaI3FTOXQ3UkF8c04KejRfI2VPRT5OXlIrc1NvaTk3JXBkV0hLSVZic313JVRY
flJ1WWp0KSpDTUNLPl9IKDs0ND9kPlNKe1Y7b2B7UTI0CnojYjc3VmBVWUVNQVBJSkg9SDgmKl8h
YkJjZjl3LV5AXm1HZnsxKnd2V3xzTlF0SVdraDZILSZxZ3pSYTxyQ2hAfQp6P0NNdlE+Myk1cU40
Xmo5SkVDeCg4c041IVpUPSlAaHZjMilqWi00Um85Uml5YHglLWl2djZGdFUhe0olJGopcG8KenNu
MnwxSDV6RjdQUj19YG1DRHI7Z3dvR0pPezJ0P0VNQn44QT17KDBnc0M+fT1eOE5VeEB4KlUtWjhL
eXN6cSQzCnpZbE9mNnVaK2hTcXFKZj9pWE5TNGA1LUo5c3UheHJZUVdVMEB9dGh9Vl47Y3cjaDFv
SiUjWVluOFUoNUdeMSlKZwp6JTtSO01Ackl1fE0yJEhUR3swSlhzPHlGKlgwYjRNaXtaMkJjZW1V
bUN8MGlsVTkpdztxKEdmbyR9eD80Klg4c1MKenIyJmI/eXgtPFRVdXUlRj0qb0ZIRjcqQ2RmQmR3
Rl5UcEApemUmcUU4MWliJlRDcDtYMX07Zl5MPXNnayZ7VWVBCnppWDVPKTl6dkdBRVFrdml7ZkZ9
QlQqaX1CTl4mfkMrSnNqUF5OTCMyTlM/O090ZkVzMys4OWp5cEk9fT8qdFpGYgp6S0NUKXJzVCF7
aUtYO309WmxRN2c0RDV1eD9xSWR2ZEM+OT1kSzE+Z3VJZiRmNG5nKVBeaS1sRkcqYE11UT14fWsK
ejBXdDlERl5hO0I7cTVlTVNsVXV0PHJaKiVJUUEjYlFJblIzaDxAZ3tfTllgZUg3YURySlYrUSZz
S2lKN3UyWjxaCnoxYE9MP0xgRTJ0aCNPcWNObXd8VCQlJSsqbS1XVzNXbzMwU1N7JUd1OypVaV4h
YEI5RE1HaH1uKXZFKDxfKT11Kgp6bHN8ak5acGAxaURFSmJKNmZnQHAlX0xAcyZPJlh1VTlxZFpN
aFdIO2BJa3FGMyZjU0ZmMWBJfEx2QihsdXhgcWwKendPaypGZ15LO0R1TFBGa1Z8R3loUWFEa1pq
NXc1NW9LVSYhd0BZSnZhbTlCVXlaPTNnY0VgUTQhQE4/IS1MXnYjCno7MktqfipTe1N1SDs3RHB8
SXZacXgwT3d5bHo5QGgjKmJod2s0JHRpYG8wM25wPjRfYD13fnFIQ3A4QSYydEJmUgp6eWZUWn49
bm08S1UoPjxWQ0ZuSlJ7TXVwN2I/czMkMT1KKkI3OCF5NmFzIzE+QXEwfFhOJjFnOzZ3RDdkRjRr
WnUKemxBQWskMm5ZQ24he3ktR3NQTEpPcCp2e2QzRHhyQlcpKkBucko7LSMyflM9bEwwWFgmR2cp
YjhXfWEwSnlOWSFnCnpnMnh1YndLeVVDMS02IWQqXjYxWkphSD1BV3NlcmcwMHdyXyQ+RHN9N3pp
SnlAQDFDbWlBUkomazdsZkJNX01Bewp6MT8/eGU/TFV2YTh3O099bCExd2Nie2VTOG5KJkolY1pB
QyVCeDc4PHp4Xik8dHd7ND9JdDNHYXhpVWl6UmMlLUsKeiZQLWh8X1B5WG4xZ0klNXFtXzBGZVkx
eHVxYiV+d3FHI0h4WH59Ml43al5gdGd7eiVJMT8/X0JEPDtPTFV7UGhSCnp1aGYofnlAOHFSYGh3
a0NeODFmRTNFQDR8e3wyLT82Q2s1VUpqdjc1Iz0/REFHb1U2fnU5TmImUm53IUw1dUJ9KQp6YyQq
OE1SdXZQSj03bih7UGhSRWtyMUY8JEV4RGUxZmwhOy1UcHhmIyp1WWB0VE1VNG5qazJYdiQoKkgr
M3tsd0gKeiUhKj52IT1hMXUhKiVoJXBJNCpkRyhoNCgkaG9VZihDc183TEdLQXNySzx9djsmM1R8
cTQlNU5VZD1LI21kP3g0CnpoY0RPKEVuVTRBWXFASGV6Y3hAWF4wWilWSnZ5JWBDT29FX0ZWVGRi
aDtxc1plSnYpakgkRT0qTGReakNIXmJyNQp6N0J5KHtrPWQ5JVlMP2NGK0w1cEhRUUA1OHZvfmsh
R04zVEdUemJAJnFpPTlXPCsrWFNWLU44UyZrTisrQUhnST4KelVTPV9KUlUkWDg2OTxfSnNBODZp
a051Mi1OP3VJSClsbj9lPTl1X3EtTjFuZHVYN3JZTF40MEdWdW8yNmIwbiooCno8aUt1PEdxezMj
SHp9VyRPTT5Faj98eGhEMUNyM2hndHZSM0lYUSMxJFJSSGtnN3QzXmgwc2tHOFhOQGZgNj5wJgp6
Y1N0TUlOWkpPRV99YHptRSZURyY5PDVSe1FiRyFuKFZVMFdJbn5MRmRLNnpqMmMpZ0pJPz13ej53
YUJ6emYkM2UKeklhRGNVTEBxIWYpUEAjPk9pWllpUSt+Xmp2OEBZXnBDKilSIV44PFNjOCNJSGFA
dykhPndzZHR5elhQZ2gkcXhzCnpeZHhYOW0+fVVONE1yQksyfT13Vy1GUElwWjRJV2U2KFUqRW5a
R35VbnAtaTBxd3lyN3Q2cT9sJjFMaUozKXEhLQp6NjA9PkM1MDAmSyUyUiNsbllxa3BFTD1tQzZF
KiNRP1FldVZeTUdNdiVFSFdqRSlsMlo4bVE7I2lSNFNhXkltXy0KekRJOHAhNjRaezJSdnQ1KGwz
ejdtOSR6YjMhPmBYRHZKenhwOEFMR2BgUDRgRHNaVWdsVWdtY353dEsjc0ZqMVRRCnp3d2UtMlJm
dCs1NVNFd1BwWFFld0FjayZhN2cqRDU2O19CMD1OanxUSDVwM0JuUUpuZVc7JT9hZGRqbjZANWA8
Ygp6a3xpfDskMUFiNEIkSmJlPilyOSh2QDh+cDRTPX40cGtNYkBaayZqUlF+Mn1FNz05dEZeOFVQ
ZXRNKnFNdWZaPmsKel40OH1UZyEpQXpfTnU4OWU+akl7RVYqeXRpVHlrakdjZ2tzckFUWjRWKmkj
dSU8PUVfdzVlZmRUQiFeI1YmJF43CnpWT21hOyh6V1Q5aHUjKXxqQGptZnBEQ0VeYlZCVzFIM097
QClwcXRqYEZ3PmwyO3U3S2p3RTJRPVBiS0lPc3NfYwp6Q3ZBeTFKS1poUFUxMyZAQTtaWiUhezEz
N15eMy14RSpsa0QlQVFSQXMyKjBNQz5nWGY+Tyg1T0woNF9UNTxFfnUKekg+dzFxdjIlYiZnRjUo
RGZwdVgrU0NCLUY5MU4ydUpQaWplWmlDVjAmeTFOQXpOcyomQiR5WG9USHpDfDMrZD1QCnohVEJ1
N2ZaJVdNS1R9UDBJd0V+dFFgOXFaZmcoPjJkYTI7fD42IUdDZylpYzVrKipSKjlFc05YOGU/OTdF
VUJQcgp6d1N3d28qZjZzZ0A5clklOV58XmNgbC0tVDtQVFl6MnNwWUYpeXstJSRAfGdDJCM2I3lR
R1F1N21VOWJWUWcoT2AKemJyTU5SNT9gKjwqJGkqSFhibCF3bT1rNzYxPTJGbyVBamZtZmNAaWde
KlIqN2lFcWc0VjN9bCFhX09gRyE2TiZSCno1PyNPRGM1ODRqMDRRT2JKOGk2MC1uXmdUejtEZitL
RW9AYTFUQ3pMdkV0c2tiVEUweTgwUmNJdDJ5Tjxpd2Y2TAp6anRJd0I2TTNvXlg+d2ZoVkBDfmhy
YUhlR3FhKH1IV3RHXjZWMn16SjYocDdNKXtFVXN5QFUkfmZIQ3wydGpeOGUKentOeUxXPylyVWxI
T0FDJFM5eEB2ey04bmhnRnkwdkVpbGJyVGkyQ3JjMj47VW1fQVZ8aXtlY3pyektSLWdGZXc1Cnoo
dz43ZkxqWG9gX3JYSmJmaX10RGc2ayY1RSsmbEZiLWxNcSZRNzI7dWNyIUdnNHZeY182TDw2aHdU
Mz0mcGJyNgp6eWFxaFlzK3FWU3FfQTtoRFFNfEBFNTFeS21ialBwUF5TP0x2QXYpRDcrVURrWDhN
dzgzJkJkMTE7bUktVnlGRUwKensqSEV6Ky11ZzBVSH5vVTM8d1gwSH00S2NLKVhQT3tjTUA9QnRi
QDU9VWxuN2A9JEs3PDBuVkJgP2RsbyZJV1RjCnppfDR6dmwkeWp7SiV4VlRgfEJHZDV9MSVKTnF0
dDUpeE4oQCp5eU5WbX49ZkYxU040V0dGLUBPQVd9aVYoRmhjOwp6Um5gdj0xZHlDb0d5TWlFNk1i
JktFbExkcDltS0JsSFRiUExxaElAYzwpVzc2UHFhUiZySVgrc09qMU5WUnE2eDcKeiNxTGlDdkEz
S2lUK314LSZCXnZ9PmNXWlVFSmNRZytjfEooYkZ7dElVZUpkMW9hVGxRUGI3eVF4PSN3ZHpobndI
CnpjTiltUCtKbTlSJFRpQUxiJClZWTZrP1p+Wnd0a3JAODIqTmskNz8hbCRxTjBaK1NZRz1qVlNr
JXBVK21iTShVLQp6YmViOShUJGhoKns4Z0UoZ14mWCV3QmFSajRYaFJfZ2w7Qm1hKChhUnt3fX5u
JVpELTAodnBYJlUmbz17QTh3XnUKeldqWDdoZWpMZVZaai10QkVXZnwwJVBUN2A2SGg5NkxwKUpg
Q1E5IWNgUEQ/dT5OJUstPmB4aFBCdkx7TVlHSllDCnpQbWRmWCtIYU9AYT5YZThAaSh1PWE5UGJf
Qj85Klg7XislT1kjcn1sTTMrQXxQeEFPMFZraGwmVH5xN3BMM1FHJgp6bXIodGs3b01BNUA2b3Io
eXxHYSlXc2EhQXZUciFva2dKZkIlPnx4RTF6enFKazVATk49PGdLKjslby03YCQ/Un0KeiRgVzxu
Yzd3dEtVc2AhQEt2T0ZaU1ZEIT5Ocyo+a2t1MmhDWWlxe3d3NVhUUjtRITxwPCtra0l0dypacU9f
Xj9oCnpHN3x5Q0ZeNkNscndOa09DY0UjNWJ1UT5LS1RLU3dRb0NZKSpAeTdiQ3pjJTVXbiMlbCs8
OExjQVp6bU5kY3FWRQp6Q204IStjcWchUUEoUkNvI1dAbEB0RG44X3pmVjd5bC0pfCZweEx9NDw0
ZDMrbGRCZW1HJU41c2BrV1JpbXVeaXYKemUtc1UpUz5BO2dEKjkyP3luVCV8bU1LdDhVRkJOdzN0
SUd5OFpKMjA/aEI+SCptS3x8U3hZQTcxPyFJUnFZfUwtCno2MUB2WSpYdipQXzRqVkxUJjg0WTlm
dmMjVkRkQGNvdmI9MUMjVV9fbn45Znk5TiU3K1klR0M/YEpmT1FFYFZJRQp6STtINlFZcn1pMS1P
aiRsd3FUPCYoQHFGWG9RPCRYY3NORkljWkltYFQtLSgxZCo/fSM3RVlsfUVqaE9XeDNqdWgKemlj
Wi0qQT9XRz08VDYlVUxARV4+ZXEkNWlEPl5HI3p7V00yIW5TaHpveH1mcEVsbGZAaGdjel8qJlc8
QEpNKmNqCnpZZD1HYERffHNIQW1BdilkXyNWOUMqMj9gSlomSX5AV0Q3Pit5VjRaUiRqRnsyeV8y
VGYmVGYrY3VCST5gSSQ1NQp6OzNVeE4xUWNqOW5JbzF6QDVjPTQ4aytxWj9qSE1lYjE9bHd3UWNT
RXgtWmI+YCQ+MzsrX2hkVDhGbyR6eVY7Py0KejwyPjdZJjM4ZmY8Pmg3Q0twP2lAIUFDU0tPel99
V05sOTF+dmAyPm0rOT5rP3A7fTlqcHdxbjlqe0Y+LTJKVSROCnpRWFIwLUB2IXpIQGI+bSo1c2wq
PzEwSGYwNm0rT09LMDRBUXRteFE7bFlrdD5MRmkrNTJKd04pKy1JTX5nanBvTgp6bjsld25KfDkx
PDExQUdPdmtNIzVfNDheJF9ZUUY2bFItKnlNLX1kXkJfI147Um1Md0hmeks1MGtmUHRAZUVkJTsK
ej19RTtqcVBrJHotdExiMzQyTy1VJSNHSzVYWVkma0xgey0lalpVQGg5VSo5UWZYKTc3dTQmaDFG
eHZWe0E/VXFGCnpxSlIyZDZoJCF1RkpicTlXKERYbjFvWk5wdFpVLWdtcTdRKWl6VWdGOGsoRjBo
d0ledEw3KHI5VG45JEt5PjRNUwp6K2w3UHZfQ2poQDRwdnc3OW1YWnpXKjAhMCNSNns9YjNeMjkr
Z0ZzeEc0MiFGRVo7P1FJJmNvTXBuQGc/cDRPMDcKemNSX3dFX31ecjF2PTExRlJFezFpKDh5SDdj
JU1gQHZBLS0xaUM9azdpciQ8JEw9RTUkK0pjNnxoWX5qezhkXkkjCnp2WGZjai1uU1VVdWlfc315
d15OQUkxeEA+ayt5QndyaWx+cUtKfUpZYFIpQSY+ZXJvc2ZCO3tIM0h3VUU/Tm40VAp6d3M3ZXpj
UXFDI0tSLVd2aHhzZj5pPXAkfDI7b2U/K3ZuTnwmfU5DdD9HelgtODJyJXIoMkBGallTWjt0P3Ft
cEAKeldZU2YodCgrQnVlO2YlYVg7QzZ6cG9YI3ZeJDhZPUlBaVo0WW1TJThoMGM1THVJTEAyKnh1
bztnO15uY1VldTdSCnphRjM0SEo+NVh0KitFcyU+Y1lhdCpHaHVRaFEyMUU4KHg3NGdZc1pYP1ZK
NihCOzlPfThQaGVkbSZ4fU1FJkhGLQp6Q1Y+aTBNNTQ+P0U+dnEwY31YUGdKRnpQZ2NrQGpoUHUy
eyVacjUxQ1pOZGEqUz8pMUlLQkQ4SD9qIW9mdCEtX0YKeis1WHBNNmtTKD8wPilra1loQk8lTHw1
dmNpYjBeVS1CbG5oJHVRd3tKSCZJcl8raHYmJmZqR3ljMEtoJjZySFJRCno0ZlBieXRFZ0JgcFBY
VzdiO0VwRldvMys5KVExaUNkbSk/bXItIWNoNGlIUH5DP3tNWU1ESl9KQU5oM3Y0dktVMAp6bWcr
KF49KE9oSGU3KW1rK29ERjFZJCUyLU5JS3VZY1p6NCEmUy1SN1I+Y2hjP0NneHk9Kzk8VnFQb34h
YE5xcS0KemNQR3pSKGhKU1o2Wkp0eSsqIXI+JiQ4VWswVmc2PXs8cVUlOHl5WXtJVl8pd0VJTV97
eDNXbU47MUhDKkY1RW9TCnpHb3MzcDZuSWJBUipxUUopO0FIQk1TV212enBJfkJkbW5zJT4pTG83
TiF3e0h1RnJXX09tbCtPcU9HIXBhY2QjVgp6ZWNmZUhaQFpoJS1UMzJxKCYhTk88QSlrWT5ab3Vl
YihUQTBrJnojJWgtI1dzXn5rSWR1V1RtZmIlQzYkTG5UVGQKemBnZHMpVkckN3V7WkB+cUlNZGhk
aEs7QTApWHJPJUF9emJ1KCtacnhrUnw0bl8qVmU1QDZ5MygxLU8yYjt8fF5hCno+KyQ7Zk0tRytg
UThxZnYkJk1XK0xrMjZIQEZZa3lqMGt5eS14U20/KGtuVFpjdTI4e3I7RFNYS0ZfPihHVypvZQp6
NklsKmhhcXIkZDg3TD9XXis3ayY/MCRGcjhUNUtyNGNaZzhSQUN4PGliMSFwUSt+d3crRDdzKEVm
YXhyNVBRaD0KemUyMyF3QGZlQlI9V0BIVjZMTiF5aCZXbExHZ3xKQDtIUTh1Klk2dExmUWJfcDlf
fDB6UXJzeGNNdkVqd1J5WiMmCnpYXj09MjgkUSVya3cyNG87czduUHdZOE56TCFrTn5zS0heZj4h
ZEZDP1IxfEt4b2tmNi0jTCtkQkN6aGhIfWVkVQp6R2JMYVFLIzJAbnotYSQrMEQ+R21ITFpFQWxz
VD5Wc1dZWHIzPyt7aVN3bVl0bCprbTtUKik1dlBMXmVkIUQhaHgKejRUdzFiKDxFclpUOUtfPnRA
IVgjQW5aYE1DOyFlUzRNczs2e09kX0ohXllpK1FJMFBFbit3U0sjV35jPSVLQzg1CnpufSUwRkY+
MXNPdThIT2cyez1acSpNWE9rdGtsNSpwRlpFNilPQj1wbkImVnFufTNYfUdoM2NwI2J5PWhFJE5W
OQp6MzRpMXApPjxqbWU7djt0KEhROzg8NFFJfU9VSnhweVBMRDBiVH5BX0R5PX4rVGBTMFdvIzhK
UFomT0I7WTRyZ28Kei1YbndhMEtROUwreWFtfEVqWnt7b0V2Nj8keFV5NSUwVVYzZyNRMUE9dm5t
RmNSbHtVITRLI3cyR0NZKmZSZGI9CktZP1pXR0BjI2tiY2BCUiQKCmxpdGVyYWwgMApIY21WP2Qw
MDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9sb2dvLnBuZyBiL2FwcC9y
ZXMvc3RlYW0vZWNsaXBzZV9sb2dvLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi41NThjMTBkOTg0YzBhOGJlODU4
NGMwODQ5OWNmYjBlMDU3ZDZmYWU2CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCA5NTYxCnpjbWVI
dF9nQi13di1Tck8zbkhrMShrKn1wTlJ7M2RERkc9YDFxN3JEZ2tDak4zJmxjPDZpdyg1ZEkwR3A2
Y3QxUwp6PX1vJEhMS1AkKzNGVTc1LWhiZiFhXkxmd2I4YC03IT43IzdKflEqbz59KzE/PnVReyhX
dXR7ND1xeWIwdF5vdjUKelllRW99JUJkNkpOYCZDVWJURkx1KUhMJmZBb155P0FKc1JIZTB5K18p
bVFDLXVjMyNkWi05LXIwfjhQdEFuZmM4CnpfcCE2X2JQKUZOZXZEcE1WMXVBNTViVy00cWJEaEE2
T1cmODVGMlZYSCFpTX5BVmpKaXdBYXIqNml4bGY7YClpfAp6eCE1YEx1eWF+aGMmTCE/N343dThU
cz5YRGFmJnhRPyZZfSlxQyNQeFVwaylSKz5POHNlYipeUjhKb0pURDJPT3IKemxya1NkI3coMFlr
cEh5eXQqQEA/YkAtVyRyK3FtM3NnUCFgM04oWUQ1aUhsZ0BkV0wkKTA4andqJGZiKj9AI2VpCnoy
R1IzaWclSUBVU3shQmdib1VBczd7WHF1OUhhY3BgME99a3hjK31IUWVnTz5mRm54KnthcEhtM2x8
YmxEYTk9PAp6Y2szPVpecD5JRG16R3gqIW1oYyVKJmZUTl8mYj8jNG5EYEFuS0o8OUJ+eVpQMGhA
dVNYODdJPC1fPGhQWGtuSXwKeil3bE9CUGNBdDhyN292WUhNbnZtXmghUUdja3p6Q0tJZTN0WXNx
bjBNZDNZSDE3bnxUbXo4Q3NpaCRCVzd4P3p+Cnp0JEFefT1IPCgwcD5yPlFlTzEhNj8lZi1oYCM5
QDZCeGRObHdkQlF5akt8RExIVDh7QUZGUUY2cCEoS0VqVCNLdAp6M3lVaFQmWlMhQkQ1RGtsaWh0
PG8pMkZxeGImUmUydDUzfCZJWTAxXnNqZyEqLWROR15JZCVES0l2c1M1IUlldS0KentPSV5lPTxn
aWB1R29jQyYoe2xTb2B1KD1JU1ImaUdGJGBNPVpneVpYT0tkcWRfO3s+M0FQOC0lMH19Z19fRXxf
CnpEZzNkUDNzNDViSVpZXngra2J5YTN9Pj8taX1ELWFZPEU2OyFeak4jSkkmbSE1Wm1fJFUlbVZ4
NjxzK3o+YHJfUwp6TEU5YDhiZVBlZHh1eG1leFc/ZjFodGNncWFVVE8/cFdfN3YjfE1mLTZSXllr
b2IxTGtaazMzODVFT0hZXjd3Z2wKejR0czhRLWBYWHM7O1hPJStRZTBwe0NjZlVQRUpJWVlpZFol
KD9tOUVySmBAZ3A8aWNnOyFpLUlZPVlnRXptdWpxCnpPOFBRPitAejY4WTtTczhWWk5fKTtOTVRI
WGhrWThlP2U4R2FVOUNmXkVgZVU+Y1AmdXl7U2tkcUo2aktXfD5CLQp6Ulg9bWk4O0JONT88TnFz
MX4yRGxiOzV+Skt4dXZ1R0NnWH5DcmFlSVdLMyU7eX44aW1WYDwlZzdKQjBLOTQ0PCUKemR8Yjl7
dXg9UHpLMkhUTFR9clYlM0NYbEF5PihTUT5mQ1Z0YCV7ZHpXVU5yZEEpMm5hJDQ2ZGpDOS1KSmtV
ZylUCnozYk9yJmd6dn5wZSNHRDB1e2tNTStNdSNLPktjKXcmIzVNPU5VOEBGdF9fMjtSOFk/YnV6
YzdCUEYrUVhNTyNhYAp6amNlaWxyVUdSU2tAaGRFc3RUOzh7PzFLfWoqZFR+WHZ4NzBzR3owSkhg
JF56WHczcDhIPip1c0pYUHJWdzJEV3kKelhyPDhpWXZkV0BaXyFwJWtrP0M8Vl9gQiQ+RjxqfXQ7
dj9ydk5vdD05bT5ZRkJgez4+WmpuRD5SUFBYKjFQIXhPCnp7bH1CTjNUMWRMT0R6TT81JS1rVDR8
KERDNT49WXcrY1JCNHFeQCFgK0x6NUh2OFNMPF9jZzlpc2NeNipDS2MzcAp6e0IwRUhkd2MpVUNM
OE9kMmBwa1Z8My1nSnZhbXRWbF42KXh7TyhRIWJkKzZtTU5DYl5JXjxuPjN9QGJfYT0lb3MKek4/
USsleVpQMzJ1ajViQG9VKTJ8aURZZSZGMSkmYFVSdiZfKk04IXRkTCo1aj52Jk96QHt7bUQ0eGsh
Vy1jS3IoCno2aXJfbDt3c15mZ2NRSCFHdipjZk9aTkdAUlYoY2Jta1JsUlJVcXl7JmBwWTdEU3pp
SEtnZUJ1OVFRQFk0Y1VBQgp6eVolcDZVLURMZlFTVSsoTElId0s5TX1DdzlWWCpCVF8lUEAlISFI
OXNmelBfa0YjTVIlYE8tdDhuUypZWiRjMUAKekNAP35sU0Y+UzFAemJqY2Rgb1hUUFQ7YCV6XyNj
Y0hTfGQzWTgtU1dxSz1iWkY9VFg0JWotR15sZzRNeTJTLSZpCnolSHUxaXBzPzxMd31UJiNaPSZB
RWB7Ozlna0stRF9YfGJjMWlANnd9RnNldmszPk0/fTM1NkVsXmowb3RGdVFlPAp6KT5AZk9Wb3lT
ISFUXjEleWRARFVLV0tVTEVQYXdlKG9Jdz9hOTRSWmFZTjhHITA9YTJxfjVaQip+T31HQ3B8V3MK
ejcjJkQ3UzFiNG1KV0pGUVdQeCpidUVAajFfbERiaEdVOVpFIXwwQms7NH1hSVRJJnkxYVJXeTJh
PEMzNWp8UXUkCnppaXYrfj80aGh0WXpwbGVsbmthKXRhUWVGSXFAd1BmQEdNMF91SUN5KGxrcigt
WVY3UmtvKzVyenxeO2xQRDQ9Qwp6Rl5hTGBKZmM2MF4yWDRxQkRAdyZfUCQoJk1eWnlxWGFPJnI8
RUZqdlBFeWUkVStKPWpJTmJxIV9+TzQ/VEt7ZX0KeiVESlgrTmNwfFdFPkY2U2I8ZU1VQV9xWlAp
RjlsJldAZlUpRU4zKjQ3Z3MwU2B6QXM3b3VnZCtfNERuK1h1WGMxCnojbzBEZHk1SSpFSFV3Nyl5
MzB0Pj9OaUY8V0BpNEYoSEIoTSFvX1ZNMmwxTU1zO0J2Nm9Vaio8cz0xWioqSlZFLQp6PU5PUTRV
JTItfU0hfDxZRm9GMkMqQlkxaDwyTUBQWiFTU3U/M0ExOUV2dmBzK3tsTT0lQSNPQj1FRCEqMWxQ
P3IKeiN8cCRUPSttWCF6I0l3a0xYWFJHTzF5WlFePG1vQ2lQPT1wSVg/PCstaS1ZfCteejg8T2Fv
fjw3dkpPbzBDMUY1CnomYTNDPDFpYSNnM0Fpfk1NNGhwUDBRQ1dkdikqXkM+KVk1Q1VLODRFJGdV
ZGM4diNoRjEwP1Qkb2FRSFp8Nzd4ZAp6d1NmcjVTMlk5UztTfU12K3tqemtUSTIyV2QwRVE1Qj4r
cXBEN3hQS3cpVG9lQmpSZStpVCRMbTZPZjdvI1UpPHoKeiUzdDc3dnprRzNnRjt9Tj4pJiVEZ3R5
PjE5JX50PUhCU0s5UmYrfT1VZjtURSVrZj13dTNZfFI+UkJrdmlRO1FhCnorVTB5VjNeLXV3aS1a
Nk8lMj1lIz9HZ3wwJmFzY3xBTUZLTi11YjhIa2lJQipfdHo7PGQxeVFiTlolTmBATFNfOAp6SD5f
UkwoP1coN2ZfZyMwTEFna0dfYnFwYHM4TEZTJVJnSWp8Q2B3Mk11c0xaM1J+S0gwZXEoO0FxWiYx
e19scEgKek1xbXFZeXItK1clKGRAfElZNG1hdDVURjJuO2M+aWlgbWlXWl9BTW8xT2F6dG5TJChC
fEhgTSM1P3t7R1k5ZD9uCno/OUY3WTk/cztiTHM5TSYxO3MqVGE8OzBJcVAqLWBCNlBwRSlwKnl9
K0NOWilLIVR2ZVZ0Wm4+UX5eR21FdkNFOAp6QE9nQzhHOVlkSzVjbn5iZ3QwbTc4dnFtPz9ednB3
UkFUPXN1b2l7KnYmTHM0bVpROVFabFFFTElxY1dNeWpyQEwKemZkYSZUVyoyMEcmb00qLTw2SUB3
cmBWWHB2TTRXY0xzMUJkN0loJUU3b202NS0qVTQ/d0RSUF5nUz5PVThuI0IzCnplWkJ6bGA1TlZJ
c3lGTmMrXnhOaCU1PEZfQkdzT196clF9cDdqcHM1S2wkJmokNiEoYnlNfW05VTdlYkRJbSl1aAp6
ZHJPY1J2T059eHJkRloqYE9+MVpiMjAqYCNvRiRUbGF6Oy1nKV9FRjtYOEFhSlU9YXFLflFpUUI/
M05YSTA4JloKemtCQncyZH1SP1QlSFJFSnVAdzBsNiMzYFI2eEltWnZ6KHU4aV82QEV2QzVfTEhq
el4tcksoPTRuIzJOM3hXTzcpCnpxUyErNU83OGk8ZjVAZUpJRVNfO1p9USRNcytISlJjX1RRWDdD
TH5BWkpYVVpkZUQtQzY/dldTdjlyNFJHcTZWYgp6JGo7b2JeVkpBQ05hWnJjREk8YWc5JCpxWEMj
RCEtNSEqKSpJYExAVTAmPEkzOGVRVmEoUEEhWXMzKCU1azY1VmkKeilQTmZZdEdMbWU/b2MkMS1P
ViZ7NT1RPV4lVVEzcl5IMipMV3YoQmclWXYxNDc9Qnhod2IpJHRHcCtlUS1gUV5GCnpec1hpM2Ez
cXFAU2M8NGB8M3BSUE9zeVlRaj4oQWcpVmNha0RFaHUkeX0yS0p3LXcpU0dfJCktZW9GPDNnO1Zn
Xgp6d289N1JtSn1gUm5EYUVwPjF1V00+ZEBFO3JBZCUtPFI3eEZ6KVc5dCEtK1NidW4/N2hKaU9O
Pj4yajZebkElSmkKej1nYEJGaWJUTilEWk1RPTcweT1YblVpaD4pZChnP01WYURaPmMqdDg/V0h1
SzNFJnAwez57MThYVkhaPl5UdE1QCnp2UmxtZlVzTWgqOFhMQkd7RjhoS05Ud3JPNDRTeVAhWUxy
Zi1rZ2AyQWtGP31PcV9jfSppaWtEXmQ2ZzghWHhCMQp6XiZkcWpLfXZVcSNiJnxeWEVnYXBLWXFz
UFhxYmBsKjdtUDUjKUw8KyEqX1Y+Q1koYDska0kjZjBzUXU1NjRYJE8KemN3fDM7XmxBfDc5WX1o
SEghPnk7TztYPjlAY3toRExwX2c3aytoYURMYEB4UGFELW19ZU8kNGlgMEgoI0tVYH5jCnptRjl9
e1ApMGY+amh4aHl0OGRyd2d4bEp4eDUmYEtye1hkOSpOcmdwN2I8SFZNQjtnekhTWnV4K0hWWXY/
cHpQPAp6dnd7PDRLejY1aXAzS0t1aGYtYjVFfFheK2pBQWkjZjQxP2JWWFNOZlNwVWdNUklPNX4+
cXxqM1ElOXlFZnVFVCkKemxpdU1sNVYmVmpUPElhTkZQRz5FTm8oNGJuMSV2aXl6YSpTOXxIOyMl
QzBDUnJ8ejQpPlEpfVQrPiMkUk96aGY5CnpBRn5HdElLOU1qb3JYTFVEMEhBdnBQQXU0Kj81bith
bWFuUHQqNmx3bTZVPit4fEV2bntOPiNAY31mVVpxXkA0cQp6YTV5Mns8QDhDKENhKn1qd3tlNFpS
OFkoe150WDNFV1R+TlprNiV4R040VH5Xd0VOYXhZd2RrREokSUlkeFQzZzEKek9wfnRtaChYIT1J
OVpXSXFyTE87ZDZAPkwqdEx3bTltR0lhKStzYVIwU3JtMW8zR2VydzNla31ifE1XUU01TDhZCnpW
S21ePzBfUkBqcF8lS0RlbFVfSz00WXpRREg3NEJwTUg9ZypkJiQpRHVWendkKUBwLTcqYldeYkVA
UGNtZ1NBSgp6TXIyfGU5VG9OSyUrVF92bmAha1B3UUsmVkBlZVo/LTwzUE9HdmZVMTk1VS1LOEEp
dnRkamN3PjZ2a2V7VSlLa00Keil4Tj5LNE8qeylGeTNwcEQmJGYha1MlRjMkbjwoTGolNVlifENJ
a2xxR090NFpTeiMmVzMrIWhIJUZqRzh3NHFXCnp4KEVXKT8rYyVsPkZmfHR1OypZVUMhYjh0WTw7
OD5TfUhoYnBfNiNPc0A+dyp0XjEyUF5oMmppeSUpUjdpPnN7Twp6bX1qcG5mfj4qLUxiMW5MLUs4
LV47eDd5RDctIV8kP0I3JXhEN0hJRjRNdDVDWFYzejNYQmZ0cnIldVErYFhSSSQKelRMYiQjKGVx
a2htdmQxbjhVOHs8TnwqSUc2eXljaTw8fUxPKTMwIVdaOUxJYGF5WEA4PXp+Zz49SzJOQyZYZT9m
Cno2NF8zKUVxbk4qYj9uOXE8UnRrYHhnWVlNUklfI3spOUlGOEgjbVNrRmhpb0UwUUBsRjZlO3xJ
PEhoQ0NsejZSNQp6UyRjTWpZM2hwc3IjZ0NhY05gbHd1dFNrVGdHbXFqLSkoRj14ZnRaZVgjWCVN
P3t3fn02XllxYmV7aXtHYUgpQzcKekplKTNzPGBfaDs0KURNdyZpYnk5I195dk5PP3Q5ck1ndER8
NCY4RXdeITN4THJDb3dHVVB4Nis3ay0oVjYhQWcwCnoobnRIfHhkMGM9b15XcFchX2xLMExPSS1h
QnYmTGl4Rm8jPlBDLTNxMFlJSilfOz88IzBLTTRPYnFRVl47ck5HNQp6X1c0KW1oSTM7YSpMSkUz
I2R9SCRBSz9wK2FXPiM7Mz9pQl8zVjlsSnJgX2t9NmE+Nl5vJVFiXlRANn55ejkwcHQKei1PTDlK
RmM7RW1IazNJYW0zeDMoQVZuISZlblYzU2hUI1cjaHw8fTd7TmZrZEJCZVJneiNCS3kmbHx5SWEk
LUY3Cnp1ZnA4WG1jblJOVllEVXFAPzkkTHArOS1pPk40Ul9oa1JJa3MoT1htcWVfWnxZN3ZvI1JQ
LW4pVEFAPUMzaEchQAp6QzF1NF9yTzwwcHZyYjFvKEB+anpRSUs0ViZzRllYSD5GWX43cChEenJt
eDhFbGhDO2FLKFV8QmNsZyUmbiFBKVoKej1GQjxRJGBBSSo2dz49VThDeGAlKUpWNm4kNHMqU0pP
JmwzMGFRdE08S0Bsems+ISR+LTw5O1A4X0J2PWhlVUhYCnpvJHUyUE1RYTZIeG90QG5pMSNSO1FH
eHpALXxQYykmUT5nNytrZyVDeXlSaSM7byU9NkFUNnU4VXVWYkpJQy0/Pwp6cDtSSVRqPTJkQ1lu
PHwkcyFaUj1MckBQUiNnKzBzZjRhOCZBUUlBbC1BN0dTY35HNmV0R2M2Z3hYYEsqYlhBZWYKeiVj
NVZGUG8xMlh7XkNNXih1bVE/KVV2SHhAZUw/bVhoMEJ3JnZwRERIRCZ5eTAhbG5FeyRJbGNTUXZj
JUMqMzY3CnpxTFVEJHNkXkBJYEZaS1hvQF9UYjlLSm8/bChzPCglKXd4c3lHOW41NSk1Pyo8MzZo
PEJxYkgqRTt1RzhDQW4tTwp6emFycWgqWTwpcTYtUzRjZGI5bUBSeDVhNnBgPF9RT3RqJCQjcU1Z
QmhZT3dGRzh+QUZnTWNjVio7Y05HZzs5ODgKeiQ9cUNtYTRoK05hfTxaWXREUClsdGZBMnpsMTl5
WlI8S1gpazhzfXs+fEo2cW5qNXJOOHZGdXs/Xn41JUl3JipvCnp4O1ZLbV4pYEIhYH1tR3ZsOEhf
aHJOYyNgM1ZYM3UtRGpYQjMjbk1Ya3V0PDdDQFBAOE55NChiRD5QU1F0bU1FSwp6K1pjM01yI007
RD5EYUYkSigpQXM3Pk1yY0A1ZkQpV1BaSE9wdEshIXhiQFI2YSQ8NCglKSlafilYe3lVayVDTEAK
emVuQEVTO3ckPz0qb1NmOW5uUUJlPD5pN3NKPnJzTlE0LWVaX1UrcD4tT2BlaGd2UDFLeWwtNGI3
T3spOTJTYTFUCnpnUnYmUXliNXh0R0ZAYWRPNEs8RWcrPz5ybl9lK3Fjajt5S0FUQmlvQnlTQUNe
M3VqPCY4VlAqN29mQmt7aUx1QAp6aitgZX1gO3ZwKSs7bjFoOWNzcGl6b3s3clN4K3kpa1cjTVdg
SCQwciY1TVNNanFVNmojS3BAY1lgIzFScDBFRVMKemQ3I30tPzhrPT1Xdmo0aFA2bHNTMkE0bmkk
biQ7TEd2QmxBVHgjZyNVVkI/eGtEX3ZlMjdSN2s9d1V9WDEzckRGCno8UkJ2Qz9+OWAoOT9HKzZl
LXt9QTFPPCg/d1RyeGNkP2Z3YTZTfXl5ck8/PTZwVHFmJk9AK0MrPFJnRXAod2JyTgp6YWNFbCso
Qk8mcC1fcmwkM3lYQCNfU1E4YWkkaCY5eFQ5eGU7d00hRzBTQH1oV25jWlY8XyFqVk8yaXlwQj82
RCkKens7JWZYdHd4UTBCdTFNVXNkNERwVzdwS1VEfiV2bmlAMG5yXl4hakNoR2dVfEM+SVAzUmxE
IW4pUXRJITEkWlIjCnpHI29DaDs1S3RUeFZCfjIjO1hoa08tZyNLeHlWSlcoVlJzd0pDb19TLUJx
NyVyYGNTY2g3ZUJaKk9EITA1az1qbgp6cGBwUDY7Q1chKDNnb3h6cH0lVTwtKDxmS0dRJTE5YlJC
SDx2WHhwN04pTjBeP0BrRTl2fHpCSSYzO3soeGdGciEKejBAQmlZJG5BbXN5fnpDKERVWHFCPX5L
ZjImQnZlPHw4fmQmIT07VnQhcFlqdFI4KlI5eVY4bVhvblh+cVdqKCliCnoqVTl+blVleHBiZU8z
M0ImMDZeO2BzMnFBcSFeKGB6cWwjMlYmezckT0p3RGY/PXgxR0hCNXJRUiZxYDVhMVo2Vgp6PlVy
ayopSDZFY28pYmlHeXlBZnpKOXVHK2pSI19SKVApTDhWcTw1PTJaemtJbylzOHRKY3VLZ2prdXlA
cmRlUXAKenM0NihneDYjUktkYn0+eCtHRV56M0RhejBGfUQ1WGptWG1Maj94fnBpdGZHezJJWmtJ
cCtePlBFYD01ayFpVHJOCnpPV05HWk8pb2ptdD9wMFd1WGVNamEjJEc+KjtqKFhMP1M+WE4zfTMl
JX1NZ0QjZk9zWTU7K3wpYnFOWGZicXxHTQp6MjleXyhOQCV4P3Y2fFBHbkkoPE8wK3M9NShtWlNV
PmNZeSg/WHVFP3NyM0JeQUl2X1dlMERnUG5WNlBaUzR4TVkKemhwazBtMHtyfkY3OUxIUU9JQVUq
KE5aMnRTdEI3cSEkKHxPZG5kVU5EbnxpRiE1V253a2pmT3ViZFNRIXdzIXpJCnpPbyR4UXVNWWxa
dnBla3s/RW1fR19vY0RuZiZIWnpkMUFLd2ByRShiRnskIT9Ee0QxN1BSZWQ+Wm4qVmA2fkRlJAp6
ZTlRR2QtTlItVGtCZ2loZkZnQXV8Mn5fZk85RipXNVB4P1dSd2xgWnJOY2dyTjF3QCY1OEtoJTh2
aUxLTF9oOFMKeikoOGxpSHBIUEMoa0VJWmN6TmdGIzR0KDkkO2wwamtMT149dj9gWlUpbGYmPGhM
SH5ePCZsNkBvQylPKXEpb2skCno7Xy0wPjlXKX12dV5XWVhCWkFYKHVoRlFQTGZ7MjxSdGNNRC1G
RVNkbXYrbTNOSkRxMkN8ajdnc1NRJiV3YGd5bAp6S044KzhyOzVIMk9xKW9acjlgfilldT8jdHJH
LVZkXmR2Jm5xbjtTU3dmODV6QDtBbWJBd0U5UyFvM2tRNDAyVHoKemVLRmBSaW4pd3olX0RPUmIh
Q21FKDQ4flJTPVA/WjF6ZSNzVWEtRjNHcXhCRSMhVFRubCVZJjFQUDQ1TFBvTUQ9CnopYUdrZWJm
cXxLTl8/fmxjPX5qNHhhND9wXyZjeUFwdFAjUm1PRT1FU0w9VHRCYFk2PVoqOT5CUn5XJT9od1Ff
fAp6LTNRZGpqYGAoPiMwfnZpLUx6fTRFcmY7YmF4TTtad0VqczM/ZTBlNjhoVVZZdmdGSXZhS3Q9
QDJCaXIxWnxQc1YKenU5dWRUY2V0NmV6REgySmMrYUlfemRrNTxgIUV1Pk5tQHh2T2BNcURkLT9M
WHJPJSl3WmV+bDYyWEA5ZlNaJigjCnp1VCQpNE5RVS03NGkjWEchNDZZU2ZBcDdgT2h3WT0/TXtw
OHI5TUk3O25gVGxUcFFJJCFzU0B5T2Njcm1ZZ0oocQp6dHJPakArMT1DZmlxU3xXTTt+Y3FZJl5L
fkckNFY0bHZAPzZLI0UlNWBgUjdZRnFNdDwpWFdTKT5+P1JAO0A1ezMKemdlKXJFIyFSWkpzYCNh
KVAyYV8mPUlya1dZeThzRSglTFNYK1EkdShMJj0+cjRFV0JSZl9HS1lHM3lwSTVjUFFxCnpOYmQ4
NiVxWHVgMCZhZjZnSFV1UylPY0BpUGl9RndmPytoKm1GJXkwQFN7S1YmQUFwZFlTZXNVUSNvTXkk
QWB4Kgp6cX55ak5LO2NkXkZIZkl6PitrdVF2NnZSOSViPjhJMG9XWnMhVSRhJTlSYTYwJkM2Rm9B
PTJGeiZuO1F8RDZhMzgKel9gdHg9ZH1PKFN2NUFTZjshcyQ4VHdLUTA3YmdYa205MXJFPnM7TDJq
SzhNUUNNRzhHR3RydFVhe1h0STF+VDt7CnozYSRNUUdkM3Vqen5fSlk7T0pNPlBna2pWYH1ySGF2
eEswVnZpeFFyU1UrNlVyMipadyotOFljejxUYCU7bUoyNwp6ZDNrNGlpaip6MGpuaGpBeSYpWCpr
cztvVG1XVW45QjVgXnFtS1V+fGRmKlZ2ZW9JI3d6cT1TTHdHb2UhKmtublMKelNpM3R2eld8RmN2
YjR6TjYtO3REJFVTUld0KXJfb154PkFIJWlZYVduN3JKQUR5KjdoQWlUPGJfNXt8Zlg2UU1BCnoz
Tm9RPSp0X209Tkx6dH01YGhWO3ArJk9ybHdwYWQlPWpYQz9KVlYtQkE3Xjw4bnBqdndCRF5LPjhB
Qns3KW1Dagp6LXU8dk9uKUhPZ2hna1QhPSllLWUhPj1mMDg4RShNP0pidlRqYE9abGE/M1h+KkZ3
RkhXTF48bU8hP1BAcmM2Vj4KekNOUEVsbWJNPzV6T25ueEw3Tm5tLXIlPmVlYW0taWxoNVRkezB3
bT9hS2wmV3U8UFZlWndqY0ZfQThvLTZeIz1TCnpOMyNzUEZnX2ptYF8yVzxxKFNRNCFZdUZaK2hp
QG1mK2puMyNVSmReIWB5WGJ7Z0lBb3s8c3MmT2dFVGxvJUl8cgp6UilPVFJpRUJUKHl2UUgmYmNU
RHJXUmV5dXtfdyk7V015JSNsTmR5Qj99fVc9QCtKa2hrdjBFZG9LM15VYGtuSTgKekY/bCZfZEFC
WDJSOVU7K0A+PjxtUWVPJV5Uemx9Qj4rPSVmclVDQV4+WVp2QWUjbUw3c1liJCg/ZndhYmBDKTVn
CnpLYj5mdj8qIWxGKW14OTk3dVFufWl3OCUoQTJ2RHpDaUAyTF95e1N0eTg5eUVENFdQfG43SGQh
QUExKElWYFNfPAp6KHVsIyN3PCMrP0RuPUIpUmt7MjRVVX50ME51I2RZOFchUkhgMyg0TEdPe3d1
ZHx2PEQtVEdaSnheIUJOVGRwWXAKenVmUWdhY3cxNjg8SEYwIU9CaEtgOF9vKXQ+ZkpQcT9UPEZL
N0QwRGpocTJ2cXNWciZPVm9Pe2Ima1ItQ08tS3V3CnptY0A+aFNyR2BWc2J0RV8/KWJlaUBoPWd3
LURraj1TcFRqXm9ldH1RemdvQ3pWb0V9PjxqU3lMK01SJGEmN3poNQp6MlhZdXBaaEB5fkNRa3Rf
Un4+a1UrLXxZWW9FTSV2UzN3UWs2XlF8VDchSX51LWp4KSR2O0A+aztId0g9cjAzPTEKelUzbzZN
PXNaNjxofWJYU2xTe1gqU251YVhHfnF+YzJmPkhSYUBrK1VXKEoyI1l0OEw2VnRXXmA3N35zdkh6
Y0piCnptJX5sMW1WLUtSKEpTJnopZyFLPzw/dilEMyltfko7RjsxP0A8YGQhN3dkPTltWiZgcHRO
SEhAKH1kSy17PUpaaQp6NXNSOVF4fEhJWnpAc24+N2VqT0dfJkJtZnkzP3xLeClkenQxS1cpYU9i
UTJBaEZyKjlvRXFESWp6TCtNMEV2MCEKelhNVmh8WkV8eU0+eHJSSDEme007ZXleNk1XPjRWZGhB
Rjt7OGUzeGZpPHFWMmhqPz5TTzliWE0/VkhNe0Q7Skc3Cnp1KlR8JGgoQF94VE9ySDNoaj5CJSVh
eV9Jez8lSlBlPTQ3aFR5U3tvYyk0PDhmX1l3bUwqZyFTJlIzMkhie04oKQp6Vyk+OFo0dk5iMFVC
UkE+LUlkU0UyZkROMC11OD5sXjEwbWdgcT1lZSQ/JFFQak91MEshdzIxcytkPTY7QyFudzsKek57
Zng3NUwrfnVNU1c1OVorJkhAMWs0fjxSVy1mZCtSbXs1X0Vjb0VqYnREP0Z8bHJBcHE5REZSNnRv
O3VVfTdBCnpDb2YmZjY2PU9GdVctaiYxXkBBVFlFaUdIcj04NFdgREJzP19xK1pLWm5kYyNyLWh1
OEVNO3gpYG15WXZia0dlUgp6TnNSQDRtU190cD1oLUEzPFBPI35VPVU7S01CPmpRXmhkOCRJKElC
XkFNe2N8X2QpRmdgUyRqSF53QGtra2lhQTwKekRiNEEpKHlWPiYtczt1XjB8VFZGYDdUWWc0R1dA
Wnd4Ync9aipuNykzcWI0fi1YNmA4SGo9NTtYWil0cSFgaVBtCnp7T2tFYCt6fHNxTDM3UFVSTEBp
ejshWTkkZ1VhYlkpZj1Pa28tKU5WSGVYWVYyNylKfVd+T1B3P35LO0xPPjQtYAp6RjdBRVdySCNk
I1E8dzltbl9yJj5lTnBiNGVWYE1hPCt8dCheb0I5VXVEdl5tVz47THUqb2VIdStfQn5qKkUxZngK
ejlTWj1XeFdlI01pMFZmRChQZEBeIUtENmFCTGAjNT07KVpfe0xrLV5MRnF8SjdxTW5YMXU8dnw1
V2hfUlBhQl4mCnojYjRKXkZjQk9vSFZEK2ZnQ0xJRF9YdmwqZisyWkF1a181T0dlWU1NV1MjQEp4
ZEYoe2tXWXVPXitaK21oNXpiZwp6MG15UkwyTXE+fko1dy04TGw/MjtjPWIkQWVLcGxMSmszMXxa
V2UqVzVXfD8ldFRwKW5td0ErTmQqfUR3IzdvdkMKejV2PnRqO1ZpbiFaYUFQKDcxa2Imc18kJj9Z
VlFNSGtxP2FZU3pqTnlQMEV0Py1LNjw1O0NWPHhgWlhJbkZ6MDVYCnpqPTs2WHZnWENhJjxqfk43
JENQeGxkWCs1ZHUmS3UoTmxkTHI0NkdgTjVAO2Q3JHRWY3t9QGpfRDd8el5jcXdISwp6U0AkTyk7
ZThHPitAdWdsNGhkQk8+c3xpaHZuWCl4bHY1ezhRZSZIeThwQCpsN3tiZUdEZWpKQz13T3Y0bXZ0
aW8KejxGOWFfMmtZQ3ZseDdeK28lZzJFSjUjdmZfWFFaVGR2Tz9DQk1gfCNMM1d2cj1eP28jXj5n
QWRnU0UqOVF2WW1kCnp7OFpEJWZOWExIdylCVldRSERjeEs7bmorNkhQO2FHUXY5SXs3YFo/RCU8
UTwqSkBCYlVeZnhycHQ/VX5NfntraQp6XjElei0teygocHpMUV41SEtMdz4mTSt5cEM8NG1zISE2
KjhKR141WjY3V2A1KyRPMyFpOERGcGItUn0wUippQiUKejNGMElhI1E9N3lidH09PXp+O1BlTEtx
fWMwVmRrUWwxIV4tUnc+PmwhMURxbzUyK1JSbW84VWdpfF43ci05emRXCno3TTg0Z3IoZVRRbG9i
RUMkQlZjeUk1MXg5PTs2fjZKaTZ2VEtSPyQjP2Ikdnl2KndUUWNBVG5Ob3xxKWJmcjdpIwp6SiRZ
JksyRGMoOzJJLXVRaiF3PHtNTDcpQzBMYGIheGolY3hfc3VyTGNrTml6N2hRYmZVcDd5M2FiaXpM
SFd3QmEKenRvSGA0cVpgVUsjO09CK15CYzBzZCpIPFBuSHU9NTQ5TSMoe1FqVmt7JSMzMlAlQ0N2
MShYdzdQPCN5elJAP3ImCnApOE9AKl5aITlMXjFvbUl7Q19zJXB8YWlIUmhCNn15ZWBFJEZnNHd+
QzNoWUB8MVc7VFo4ODc9CgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAv
cmVzL3N0ZWFtL2VjbGlwc2VfcC5wbmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfcC5wbmcKbmV3
IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMC4uNGRiZmRkZTc2NzQ1YjcxMWQ2NGE4YjNiMzQzNjc0YjBkZTk1MzEzNApHSVQgYmlu
YXJ5IHBhdGNoCmxpdGVyYWwgMTg0MTQKemNtZUlhZzxJNm03ZUJneWg+QylXMCNZS1drfE4jR0E+
RUMxY1Eqem9oe3omfnZgRSp8b3Ita1Yoald+PkVWVjRQCnphMGtEPz1SV3NPeGM1RkVBOXM9Ml9u
YkwlOyZzbFBHd1VaK1chWEVvQ35pUkBrVVIyblF0QSowdH1YPEVfeHtGcAp6RmNQP31BYEVgcWJk
bDNAaGRfdjB1VTxHRSZiYnl+QFI1aEt1N2AlUm01MjhtSCVvfU93PlBgM2xmQXE3OHk4RDwKelhF
KkRsOWJwT3hnY2MkJV4tOXd4ZDI3fT9mQ2A7KnhyZm5xUjZ8dipJNCEtNmBvJWpEQkthYWtsfCtz
P3MoemtoCnoxXjJ5VHYhPVM3VFN3TmNrKH1JcTQ8aUdDdGJfI1o2TmJBSEZVWlohQ14yKTZsU3Mk
UHpAWHFsaE1zb21gcUxkYQp6X25EdDQ/JWJuM3hHM345dyEzJWhiTCQkUkp9dnxqQH1mVjA3X2V4
e2NhMFNNX1U2QyR8ME05QTFwYnIyZS1pa0EKek4/XyotQmNZbmg9PXtRcCpPcG1yYClCOS1ldiEq
KXBKbFkpR1JKPGBDYzFsYnVYQVpuNCFaZDF5OzxvKiVmWnJ+Cno0PkM8a0xMezlBe29aZUVifGg7
aiklYiYtTW8qVW9teCYyWTIoRnxsUFVwPj5rLVlvfWd7WnMmRWw8bFYxd3tvZAp6V0J2VTdHT29C
ZFNVMmpSYVkyQTRUIVNjRjYxd2JPI357QzhBcHkwfWdQQ2Rqe1RpSmUkQHRSRyZRbzJMVFUja0QK
em5gbSVLUX5tdEByYHJjQypGckw9TGA/Pn1GP1MoYlo3N1dXWXNWc197aWRkZ0t8dnxuR3JzXz9t
TiFzKnpnbVpwCnpyZFZPZDd+aGNRV1FQNERuZj01TnlnUXYzSXs3OW09VXU4V14qfHArRCg9LTNg
YmNRZzw+fUk7dDgmM31kKHR5QQp6ITlVP3J1VStGTSkjVDtsSEEqY2NWbDMxYkVEWTBxNEFaNHYk
MjlRXiNxYDZTc0JON1BXamUrUCohSHlobytHWlEKemBQTUk3UEtVTiVBeHRYWWJHdH5HWT59RHJp
SzE0OGA0USomJi1lMyZIKzU+TzwrN1pMWFpvOClMfU92bGdeemAqCnp5NG91OVZoYlBkcnlLS0JS
b2dsSDdhVnoyKntqR1Y5ZUdyNGlhU145fDdeNjJre0tuOWQ8eS1UPTA7T0lVaHJlUwp6Y3laQVQ5
fWZvfmktWjNUQys9RkxtWU9sVmwhcXQzczFRMWBwe0A+RilLPEA4WTx0ZjNPanw3YHlhak17aldu
YkoKejl+VmF7aUNhRkZgU29aK3AwJGxydEl5YjNxfUNkNz8oZmFganM/dzJfTk43V0tQP1FaMyV8
JW4zKU93d1QzMEtwCnptISUjbTtxfkNRKk5gcFheeyV2JmwjUShOcygkdCRJXntIJF8hVCNXN1dp
dSorYVhgPUR3eSh8Z0dFRDBFNnklSQp6VSgtbDAzbjtlODVRfSplOTBkNyRfZXNjO1hEbjwoVFE5
QkY3ayReKC0jI2ttO1pePFY3cCZVbWdjXiE2YjdmNEwKemomcmNwX31RcVRaNT59SVhYaVlVbm8z
bVVVXn1gPXQpeEZXbGp9Klh2YEc5STs/K2pPM1NyaCMpNlJDYz5PKWkjCnpsRyFoZVpySSZgPHpf
I24mMnpyZ3EpV0hadXQlb0JoIzAyQHZuKFdGbmU4c283bDwwMlY0KCZiNHhZIUYySGVSNQp6OVFZ
OG9oISRMeitzKlVFZyNEcmhDX31lQVFzcT9tVWctVD0wX3VINUZVKFdkVD19bHtSWlVnQnp8Qn5n
djc8PDQKekd1MmR2YkBiTClgeGxzUyZfbD5xNld9Y0ohPXF1PjghPUU4UHhObztMfll8fCl2WXxj
cjU0YFJQPWRzNyFaVnB0Cnp7eUtKK0NjMklyNHJCRUcpa3JANz5mOUdJdkMlXn5yaGxINGd5M3Fj
UTtpQzc4MExHTWM7dX5xUEk1VWszVzl5eAp6TFRafmlYRiNMRUV6JDRLYlFHYWdvPmQjO14/Yi11
PzZoWXx3VUFoQXZedEN0WjhTdn41X0x+azk0QXJOcGdeZCYKelIqZihEbDQ8TihNMDV+c2pPTmMk
eS0kcTxhU25FSTdJIXFZXyt0aTVENy1pMGd+c2hDVzNiNlRRbEJpfGRWMmRCCnpzajR7YWJ5fVde
Mn1hdzk2WGo1d0IxPz47emlwKGpDR3o5PWY/bURobDBxWXxXQD5nTUZVYFRFO0J2TkhuKShJWQp6
aXdHazUkYGw5eFpfeHFTTXB8KWpMNFVISzVuZz5KNmIyPEFXQCQxdkxBdUBRKm4qWkZgYzI9JWBi
PS0wJk5ld2wKejxvR0k1SyVSUEJCUUAxZjR3dDtOLWpsOTdTZ3AzNWBDYn1gVj00ZFh7cnhrZFhR
ayQ4enkrV0BjWGVReVYkPjdxCnptb3NKaCNnKTlQJk9RK0dsXmQpclZOU19CRGtsRVpqKjB3XmBJ
JHw4PVdSPDBUVmxDP2p2Q0FTRzZEQH5xNil9fQp6UCROM3lqZkxhVyhhVi1ya1A7R0ghamMmSz9F
WWNDSWpeTWItbyQ2Sl5PS3w2K31YIVJBX2BqcS12eWlQeztIWmoKemhhMi1ac0xibSZPQjc1S3R2
TmJETitgaiFRMmFgQkdgNzBZI0dTTV56Qk5WQWNVRk5aWmVsJDU0fik4dUUpYXZFCnplNHcqQW0z
YTd9dmdjNUo8WDEhUVpIU2tRRE5jczJXc0hlUUdtQCFzc2c4MWF8NGZ+UVA0U2JZUWlTdXx2alMh
aAp6a0VOeT55VH5LdEpUSDg3cHNIQm9fbzVqZzxtO1ZscUAxP14wdE1SaSpQZD4lcHx0bXdfd1k3
ajlqTyVAcnFaUHAKeiE/fStZdnx0YUVtPTJkNT9HSUN3M1B2QUJIdGs4e0stJXg+d21mdz1NdzRU
WVZIbiV9K0psdXtLTCZZaWhXejk5CnpaM1A8c2ZXejZoU1hOdURvK3E9fHNyaWM5Mz83YmBjO2V+
NjxrV3RTWmpRd2RHXjs8Wip8VnkoZHJwOTBDWmJVQAp6ISlvZ2RPOzlmOF5PMjQ7SXxnVzdSLSNj
PE1BdCY3PSlqRD4tTEEzZGNMczk+RlY9ZUYzPEhAPCErJUU8UFp3SGYKejd9JVpFKWM3M0A4ZTxS
YTJrZTQjVWxObnhpTkIjUTNBdERKWEs1Xk8lX09WM0BrQ0lkMTk0UFRgRTZvNF9jK1deCnpvaTBa
STx4fXxZUGM7e3dTT3g0RnFNND0zbTw3XkZoKVlQR1BPMkYtcSo1R00mJX5qfUFXTXJUZGQyY1Ur
bzRaSgp6dVpTOU5gcCVidktJKT49VF4xRXZOcT1gNXJna3xxeSV9QUtQRyZJaSY1VXg2c0d4aE9Y
bUQlTV5GJEhIenNfQSEKej1ILWk8UmRPKklEOUJiY2l7Znh9NiZ4YFJqNi1oVG5DJGBZOztseyZG
ejsxNnpRVy1fa0pFNSV5Zkt9JVcwci15CnpIZUxFM0FpeW49JXdPSVhKSkFJQHkwNSgoUElXe3xn
SnRKZHVTMkxKVFgxRFE5QHV3bXRtKH1ESlM4T1NRcmw4Iwp6KUFFKXA5aXoxTF5oKUR8Uzl3PSU7
YExuU3ZaV1hYO1hxe1dnSD4/bV8jRUwpZm9Pd2U2SGNBfDhVe3MkRXVxWmcKenU8Ym1PTnRMQGdE
bGAqJChUJTQlby0oeUlQYSZWVnVhU1AwZUhBUyRydDZYQVJKVGk0SkNNdlNLJj9Lazk8YSZJCnpT
Y090QF5le0JrRD8yUGd2bUI7RzYtUXVoO0k/IzFuZDExV3VNczIxPDdhWURCMXdDQWljbnNCZCsq
SChfQDRYTAp6RmpmV184Y041eSZaM2JvUHkxNVllN309Skk1b2o0MW0pY1lobDdeUlZ9QShBdlhy
Zks8ezhQZ2koPHpuVzJlP0AKellMRmo0cHF0MXBiSz9fPG1kITA3O3VKU25YKjx+QVgrUDNUKyt2
P3w3fUNtMD1QYDhJWkU4QTxgUlFUZlA1SWczCnpNQEpRIylFd3VwcnQ3QjtVVHtIWm1CMVIzc0FN
aktgUHlCSTZTOUhXajZ4fnNIe3ByUWk5e3VKdTdzO3Fyc2xANwp6NE59aWloPnBEMHUyIzdZUipA
Q3UjSWdwU293S1lNMXlvVUd5Xj5kVnlMezd6YTF5MV4+UyFCLV5eP3gtJiE5WnsKejBmeHJsS3Bw
fH1xXmRETGtfZztyJGEzUklXUntmfGhrbCFKUzFtPFBEXnV0Y1M1cVUzMkU/K2ZaMV5BMzwzWWtn
CnpUWDQmXnpEeUZMdmtvfW8mbC1IKXU0IU4leXh5OX5JYkthK2p3O1klQlMwVUtVSHBLUGtKc1Jh
NDFFTW91Y3d9bgp6WkRidHUkTlRTMXgqYk97JGJXTTVlPXVMaFF1KnIjQzY4aVdqc0U7eHJaPH5e
R0koQz9Ha0FYNHtlWFE/Yn5UdzkKejw3LVZGUm5SQiZATnJHWmRQfW88V0ZUYHpHeG5yb2xxUEM5
JG5eZ2xLcXJSNnQkTjMyLTNRe1c3bWBFVztyOShOCnokeXsoUlp8YC1zMGc/UHt4dStPQkpqaUZk
NT1pVUNufDkkcSQ2c3gzMTQrK2hFZld9Pyl2a1NBRypBaUItSWM0Ngp6YnE+N253JWJ+bmVHNCVx
MDJuKGNsKyVsN0IhcVF+YyF3cE09UUR5Uk0lc3BPUiZzUUNUWjJea2JKKDtKSmxkNG4KektTTypR
KHM+Silra2RsbT0tck1HaE8yaHFKTH1yOXBnZVNKNyhPeDJjUX5KPSpVX09odGJtbHt4UmZyZzxY
Kk01CnpmcnhBMCllWFVVKjs4O0IkIUFwajZQWGBNJCFDeDw4dilsKHRDS2pweHV7VX40LX1Wd1FK
O2BNZl8jOzNoYGRYbAp6RWZ9bXlZIW5jeUFSP3tLJkJTPVc/RHZaez9JIWxOTUlpRHROMFNfYUR0
Tzw+c0pJYGlxOHRDZDJ0S0REZT9aZEAKeiYobDZndmZTWCg1Sn4pT2UobDRgS3pyNyU2PEZOc1JK
VmIjZTMpZTIjXm42NyNNakZ+ZkYocEowYiVEPyR6all1Cnp7cipIdjgzUE49Vl9qaTJMbXB7fkkm
NzkwaTRNZm5Kb3oySSNkPTBMPjNhTGtrdXpBfiNwTkI9KVRlTj51RlEqdAp6RU4wSyNZTjdaSFQh
PFNgQVhpQnl7OGdJUj1JXkdnXnRMI0xLK0EybiN1KlB6WWo8NDh7PHt8M1ZRek5TcEp+UiYKelI8
JFkwU3RMM0dKVWU0fSh9LW1jWkhSYyNVMHJic2ZJfnJiJWxjWG1QdlZwZkRgaT93QyVTVjgwdnx3
M3Qke095CnpzVSs5UjVmLSNST3tzeHEpQHpHcXc3emtBaFg/dWF3Z29xQXkjZXsrXmYrUGQqPSlA
ellJX3NDX0Q7eTFtbDtCUAp6ZDR0dlQjI0BAYDMtYFMtSC1UXjNoU2NqRCEjYXFAQDh0cUc1UEd+
JntNKX5wKiYxSFFEa19YYnU7PmsyWWx7YHsKej0oMWsxRHt+IX1rVXhzMExrVXE3WW40ZkAoPnol
JnR3S0UkX2lyTFdEMU5mVXI7ZFZQZ0J0R2I4b1FgNGJYI1NRCno4KDdmUDApejtTPEthbX5aaUdw
KXd4UnFtKipMMylkbk88QU9GKXRha288SW9ldHtabSswOzc0bHtDWmp7PTkxegp6R0xVfkQjSF9t
UHdqbzV3QXlqQWYoYmNrUkkzQl5lX1Z5PTRfM3NWVnp0PT5DJjZ+MWUrTEAkYjxUfXRTU3VmfEkK
elprVkolIWFXRzUrZGJWRFNHeGU1KiUkVjI/NENyYCstZnRjXktPa3U/ITVzYXA5RTkrT19JSVM2
QD0kMTdRNCRiCnpBM0teOTtIQVRwYCkpJFdZa19kUyl+QGpRTz1zJWFjNCUzJT0wQTRRT1ptNCFO
KzIwRylMWEA2JjNVWkxYKS0mVQp6VkkkbD9yJEJfWHRNNGwkPFgmX08/eTJEbXVRRjF0WHN0VGVH
MTVEbXExKk91RkJ1QEZuelNWbGNfUjVWVmZVRWYKekM+SHRDWHRyUC1HN1JONCRaWkt6OTRQenxw
VkZFcGZ7Mnh2MlZRNVVoQmFGfHJGc3E2Ukp5X1hwa1p7YjtOVXRlCnpvQzBqbVdYckkpVXpkQkQ5
dGlDYkUrSWF1ZVEkJig9Y201OXBYKTxLMkp7SF5yVytTTSNNSStTaVIkam9fbXNMXgp6OCRua19N
TCZtMlVic0kjZyNRVmN2aS1BZUZWVm1fKShod1dKQj9VMWxZK0U3bGA+OEw1JE13e0BUaEdwQTBi
bUAKekA3JiQ/NWZZO0l1fD91bnFPcEVAN0NRRXVsYzY0eld+VEI1MFNRPX0xclhaSWMpOGpXXlVC
YighfGImNlYqOClTCnoxQEd4VG1DSCh7bi12Wl45ZU9ERjhFa1pXdGBHVWl7ZiEhPXJSKFpMKU9U
VHhwbGFzSXVRRztSV3J1JXZseG9SPQp6c3ZgZFA1d3tTVXd5JE9pRzFsTDs0RzleY0ReWWJKKXM3
bFUtYllwfURMe2pvb2VoKyZ1MGNMS1RfZTVLQDJGdkEKentYaHFMYyNOYSRMO3kqcTNIfFcpeks2
ZXV4I1ZUbl9EMClTYHdeKyp3cTRIISgyODFnaV5RdjF3X1hlVThKYTlnCnpvd0NkaEF7VT4jNUth
JmhaKj9uP1dJdjBvZndFI3gyNnFZdjJwfVp7VX4zckBPR0F2RkJ3UF4lYyNYNEQhO15gVAp6Rkt7
NWQ7LT19UWhBK0okMCtjYTdjcUFpMUBFP2l0Y1k4cXhYPC02dGBuPWgkTHxNVW8yej0wKjd9YXkr
MUEkTmkKekhRWVVDdVYjbGt0e1coRHp8QjVvOHJ6OX17WVVKVFgqI1c7PlB0OFohTjFXSyRHVEJq
KXIkTnE/YXV1UyhuMThOCnp6MFgzRSNLezh7YjtJNVhlN180WldkX1h0d25QSi1TaH5QcWB4ZnlI
TlhiSzchWWFOZXk3XnRkeGEyb0Y7dzxIWAp6PWspKmoyN3c0WURLWWhyQTU7MUlFeSVEN1RJRXJk
MlEyamV7dmZpVCF8RE1AaHFXQlR1Z3M7el95KzY1VCY8UzUKeklgSl5qbkV2PSZeMUdXajVIQ3M3
VWtEYGpSVFBAK08zK3pSRFFwND5Cb0lATVlvcmQyWUdkQyZGOUVrPEdueHMkCnozOzhNdjd+eXND
UUJgMXBUZ2FiRHEjel5PK187JGtNfG4hJUF4fEVHWkY/TXA8Q1pEdkEleWxOQWtlZW5WcTt+aQp6
Q0Y5QntLa1l5REA3VzswMXRRWmw/PTVeM09FM2FfV05MYU80KkxXTFFZQl5qdEk4QClgYEppTThM
USUlMVVNYmgKenpQemQtU285UUBieXFCUFF5aE0yWkF8WlhoejI1Z2M2OVl7eWpCKkMjWnxgdFpi
MjFjZUdNYH01e2ZeYU5LeDROCno2Z2FHbGIyUXkycFFDVXZkPjsoaz9VRz9jZk9haDhtRl51Rzwz
UEElT0BHMWlCaFBRdVhyTzNjXlQ4UHUqQGolJAp6K3JpVGhMaCVnfT8+XlBhMjMkSj1FPTxWKiVm
clh3dUk7WHRAXit1MyUweilNb0JsVXUrWVRKaEUqZ1hvJFg1WCUKejlaaUQ9Pjs2QytALVY/MHRk
SkpZeVNnUD0tRT9WT1Y0dF5gcD9ZY2VBZzE4aD1hNHNTQFhaeWQldUpoWjZDbVNPCnpXWG9HTkV1
UjNxPXFySWxGaXBQMGhqZFpfSHU0WCVhYW0kUFA/RH5WNWMoZUA+YWB2NXU3SkstaFpxP29nIV5p
Tgp6a1JII2kyPH1BJSpmK3JYemxxYlhMZGtBfFJJKW1tazk0NVJ1RGZhMUErK3gyWWBEe1ZNMDVV
ZXVNRmooe3dfYW8KekFZWWpQJVAmaFgmc3VBc21VKjROR2YhazdrWVJEdFV0WXE+WWJBQCUoRyp1
b2EwZClgWTxrJTh5SVNVUDNffkVECnpjWWBCYXM7Oyo1K3s/RjJqMjY7VDElI29Ab2p8Uyl3KTkq
P1N9elVRJigkYFdWWHRxcTBMaVheQElffDBNQ1NEaAp6a1hGYXM+bEtEKUhZR3twYnFjYDA7P35v
YW08cDklUTFWeTxXWV5yO3Z2IXcpZyFKOWhFbEhffik4ckUxfDFsaU4KeihnU0BpSlhiaHk2SCle
NT95NkNlWGxwODlzLTtjaHxJfHdnQnhNKGNlbSgtNkdHcnR9QSh+P29NNmooLUsmWHslCnp6YU1w
SVUyQCNIU1M7KVpjSnBzSyNWMERHUEZnc0ZFJClATD9xMUR+e0dkVjFeJT9qYXxLcUUlK3lCTzch
WEUwdAp6Nz9wXj1TQF4kKGdlVT0pdmdqQVNYNyZQKnZWdiheVD01QWAmP1EtY2pZaDJ6RWJAWiV4
PWhVUmFuflVoQXo8YjAKeiYyNDNvUEVOM1VvU2JseVMmKGMzWEhgNyZzfFE0fWtKSWlnYjNURjQy
NDJ8JEJaYW4jRm1GaytKYislU2hhfGQ/CnprVjhQVjJ5YkVaJkZ8TXMzTlF+WlRUZlVIRndBP3Zq
SGlaMVVLOWMjPipGWWhpTSUzZk9JS29Ra1dARnRvZVh3PQp6emdsK1dvI2lBb05FdzZ4WD9xUEZk
KnJKeSpSZmB8UzkqPnxWZ0pWIXJlPGFadypVPmNyditXQi12Tk1Laz9AeF4KekxWb0V1Z0s9RlUt
ZU9zdUwtWnwzMj8jel9taHd9R1NWM1lJQVlIfldHSkl9Ji1CZkhTYTk1eTlnbXlMRzlUeGJoCnpq
PEtjeVF+ZighaHtLMUx3PyMhcmVsREE1PCQjPz9tSlVtSUFpNiRhcklsTFMqdzhwJVU/SFMxTURF
MFB8OSVBbwp6YTsxQ3dhUVl8SUhAcEVJUihZQm40WUZfVTAwXiY4K3JlNE9LTmQoa0tYX3AoQCNl
b3hRVGBofVRYQHB9dShZaCgKel47UWkoaEBiby1mSzd+SFBkWFQ4eiZDVTwoKXsmQzBAQVZwcX1U
e19HeFpRRFR1MWs9TXVBUGc0c0s8fUR+a2BBCnp4Q1l8THUzPUI7PSh7KDY7dXRwO0JWSUhsLUcj
WDVVJX5HfDVrVkw9YTJ4TWhQZSZnQVFWMWtSMkIzSk1qWm9wNwp6bCFMRDgqeVYhdnM3bHZyWmIq
Xjlhd3ExN3hiamB5ciNFNk9CenA5VD8rNXtYVFIrc1heKHZ1RFRFZWFKb0MoJG4KemFSZ0QxSlhw
OWEyY0A+XkkpLV5OdEtWVkZOXjcpTEZZeUZLNCRmNUQkem01ZW1fRTQtaHkhPGNOTEpQb2I7YjNt
CnppMCVgOWNuMVJXeThJdD4hMVVHREViPk9UaFlha1BFWnElVHlyODd2MVp3O3NnblZOckxlWTJg
cUElVWZDTFghJQp6VTNQeygqJUw1MnB+Mn5WMjE0QSpCO3AtWHt0d1IjKDhnWXE4Q3d4fmU0OCFL
Kis7I3VmTjAzX2dSNXcmQENUaWYKeko9Xi1GVXtxNEVJeXhtTE9DSU5KU0hNc0sxVylgaHo8fUBp
LSFCPTJ0c2c7dGNuKkRAcU1ARXJzZlEhPGJhOXZWCnopP0Z+YUppOTxJJCFgaXMzQGdnKDxifC1w
bSNHZ0tEZiVNQ0ojUCpYa09oKHhha0cpTmE8eSNTbjwtKmtAZjBrcwp6VV4yK1MmQ3JpM2NzZnJI
QHg2K1dCN1EjY2VrNk9ONWB3Tmd5N09nPjh9TDIlR1ZXKWJlc1RPRmNBdnUhTTZRMSYKejFEYTlT
cTA4PF9Jd0pvQnFMLT4rKExzLTBJWDRAcHB3aUx4aG8kI1ZYejtHODBRajVDWE1FMmxGXklpfEtV
JT89CnpmZW1rbnMmUjJuSFJ+RCQkeChlNmFgOEUhRW5PbDFgb248ZkMtZVp9NThsU3IhUjtpeCF0
aUFoMWYqQiZ6UjIhXwp6PHY/VGEpfDNqZCE7VXw5TGs7cUJnPUFeJVheWTQkd1pHWHVrKEVNLVNr
I008MjlVUTVZSXslKFpPLT1QZVIkSXoKeiRFZklPLTBWfj1NejEpNk9QezdlKVE4Y3JiXmd7TzBW
KjEqeUVHSGNsWDhZPWooT3dZdXkjS0B5K2wmLSReSlc8CnpjN1poX0t1KjN1UEpjemwlMW58WkB8
eTM0UTNDNjg3ZXY/SWJUOComPVFQN2xhcTJzWXdeeilocFU/UTtxazdQJAp6WDc5JEI4ZjVkUUwo
NyNWNTl5TiRocDV9MTwoJTI2YjU+QFIlOU5YKm5maE5OclFPJi07UTJNeXVkR01CYEo7OFkKek5Y
REY2cSNuO35LI3hiP3tZYVdJLV5JNnJaOCFtPzdJRl85WkJOZmxGV1gxKUBQSklsY0lYMHNoTyN1
WVVQTDQtCno4fGUpSCRmPjg4XnY2RjAkLVVANkhUN0Atd0d1UyF1P3t4SU9BKmIkIz1hbz5wYF5P
IW8ldnx1TTtxQStBOzJYNAp6YiZ4PnNTSSFuWnRpRGQ1eGU3PVUkenpsZ2lAQXMlez81KlI3LSNl
OWhrRWRpPT1aQ29LZVhVcHBMfTM5aiFOe1IKens4VFhkR2ZPYnExb0srPmljNFAtbXBWXigranF1
PG0zYzRQbH5PYH5VRkd3YlpLRTh4NHxnU0padz1DMGRReHsqCnp4NjlHUF5mOGU8VW1TMWVpVkpk
Yk5BaVMqZlpYLSEqYG1GVkt8VV8hcjhVVTtVQld4b3dxfE9hZ2R9KmktY0NPaAp6dFJLVzdZajt8
Mj4zc0BfI3swfkZqbm9DVlMtOFBTJGdsbyRUYnhBfiU1N3R3SWZXJXtCcll4PylHKktjJXV7LWcK
em9jZEVaK1JuTFdCTXRJXjc5M19tWk1mMTBjSiNCQlUrQDVBTCNHWSVqRkBDfE01Vj1OPCVNbj8y
cFJoTXBHZWhHCnpEfnJ0NG50V1F+NyRnKTJpQWVKMylERWRnZlJFMW5AR2dNMWxkeT5FallXM1FK
Pk82VmNSNEBCJCFsNlE0Zl4tJgp6NUtYJGtKI2dxalkpayRmY3M4RSpWIz1IcWVqMG9kQDlPVE1U
KjN1KkY8RCt3Vj59WTZGcS07dHkqOVB8WThOKE8KejdxQDBWKWloUTNNLUEwTDhSQT4+Jlhgekxp
I25gKiV4SHpJJGxgM31PU0VDRUI5b3FTRiYxMWBeZUYpU181PG9ECnp6ZH1vQXlJPG1sZFYkM25u
fG05d3YxQTIqUntEUkJoNnRGPzs+O1RJOGJoPGo4akdmV1czUHZUZ2d4WCpqV3g8ewp6ZHFkPWlt
JHZtJkxDe0Q1PExTfFJkXlo4QVl9eENkYjZ0R1ZJfSE0M0xSNUIyUXNAV2M0WSo8TiE2QjlRbzdf
NHsKenl8TERlMHlYSzJkcGcpP2NHa1FodmlBUEktPWkoTiRKRmVOXiNOdEwlSkhFMVl0dGMwYk8l
PioqeyMwT3EjdHYpCnojbTBxITZ4T3BhU2xjIXh0MyZoPlVmNUs9V197Wjg/UTIjdXJvemhGSUtB
clp8R289QXQ3SUltZnkoPi1eUigmVQp6KzllYFRpdF9paVp8V15fayVAUXNuRzUwSlJXX2MlKkIo
VV9UJnpTUmBVZD9BYXg1JkpYc094NUM5N2RkbihzT3wKejxmb3smaFpJR1d1STNubGczX0l2SjtO
ek4rRE4mSSVsMGEoI2N0I28jPm1gaTFKP2FYRk9ofntCIXxrK2UpNV9VCnolWDFpbUMqelZ8MSps
O0V0Y1Fld1RFT3JxNzRhdEFofjs3VmVWTF9oYik+fFh2YDdCZ0BNbn1zalR7akVQb3AyQwp6SV8k
TzhAKSh7dT43NlFfKFJlYk5wSFNaPnxHKkViNSNye0JJX1hqcGlWQWpUaH0mWkQpM244fWw0Uzcr
ZCo9I1MKekF2JllVR3JFdmgkIV9iYldxWE5CRWItcT84JkJlUUImUndWQUJCN2RSZkk0XipjQTYx
PD4+OFQ8bUduSyRBU3lBCnphPTNAUVVQX3xiSng4SmdHT0R0azZfPDZgeyFQSVY5ajBlIWYwc2Ij
YHFaNk95S1Y3b2EyX1QlLW14Mm80cFdTUQp6dGhqPmZve2xVcm5QNWRgZykqPXkxWklEUyVfNGt5
VllKQVNncl4pO0BgR3sxbHJ7NW1kIW9sej1QSmB9O3J2c1cKem5Zd0s9czxtUlN3WTUoa1MjVigp
cDRyd203Tkd9MnlxX3ZOans5LTxwK0poQ19sYnFsd292KmtiZCk5PE53IWA4CnpwejhoIUhQS2Et
LXRAYWYqTCEyNih7Tkh4TV8lVSEpUGYxRnsjWnBzVSlMfjhLVSMmdWxkbl8tTjlHJjlOTGBVeAp6
Y1N7eUl0TmVuTEk8ZVE1eDw2Z3dgfnJqJG9XMWQ7N1MpUkdSQmxXfnhWano5OTxeJSUkUXteP3hC
YiM9KmkjcSUKeilYSjV8KEV7R1RKI3pMdUpHYX0yMHFtYk9yc0J8TGpmVlE7aGtZUmBReFpAQj4t
P28jT3d7aEBYeyM0I191Jl5uCnpmNndJY1YjMnBQYGc2MEhzVFJWN0NpcSlVYFBJNnBYSzZufUhy
TUMwZCFSd3tsX216aDlraXcoWnpRa2FuYU1seQp6a3kyRFpVUG1NVkl9PFRgeElAUnJSeTItT1Ax
MFlDREdaPTQkIVFDPHlZaWA+KDhqe05gUkhKelV+Yzdge3luX2MKelNHNzY+I3coWlEtcEJ7VyU2
NVBjMClPMiQ2WmNFKTZzME9aXnppQFhvKn5NQ2I1UTUtO29CMSsmP1hGK2dkTGZwCnpFeXc8OGhZ
JXlzJXBvbkBiY31DKCFnZ0RtQkQmekJENDhmNl99Q2JeaWEza0V7eHxZTkJBRmoxU3Y+e1EtOG5Y
WAp6WUYjYTt4e0RlPV99V0x+K3RnaX4wc2pjVjNYISVrMTFwSGgmfDZFY0pwNURIQ2tocHV4X01l
Nk1hYjAjKjR0ZD0Kenh0Z2Z3WEAkM3tGP1U9bWctMHtqe0R7XihNTypyVHFlTjxaQFVjSyYrb2Aj
RllBQHpyKHZRKWshUClGcEhHflZQCnpWfEVHeSp2TGgkY3hRYy1RSn5QP3oydVYwMn5TO2t6QWRm
fCpvR0N8dGp5eX04MnFgMjRFMURNJUQrdFMqY2c+Jgp6Xmh7aTRMRkRne080b2pxZTNrRWNjOV49
fm1BSnRZQ24/QVRYSGA3NCQyPyklVHF2UmEzSnomc0AkQXAkX1BwUTcKek4yIWxuXkhKKSYzcjw8
U2dNPCRJSW98WH0kX1hjYkQ4NWJ+QlJQeThOLT9YP2AtK2kwSStMJGBPazxWK3QmcXpZCnpFUXlR
JVhXOy19OzNhOGlqRDFoWCM9KzhSY1R0OU90a31gYExSKHk2IyUzKF5WeHF8ZV5MUjJ9NipgP2Rw
X2tIOwp6diNIb18rcmFGemc8Xztge0ozc3piWEY8YUU1YTZQMnRwKjQwZVJ0WUhGS31kOzBFa2xO
KTUkJUJIUH1fcnR1by0Kem9fWWFSM3FBbGZZWG8qNHdrNnQ1O1JvK3NBMVg1KXheJlFOZT56JXJS
UV89bk5RMzR6YCpWYWg2VDUwN0d3bX5mCnpTRHhlQTs3eit4dFpZP1lUeDlJalp3Nj04QHAjX2NE
YkdWTXpDNHJZYn1mSjVkPXV8Mj9VIVFpdn0tXlFEKX0/Zwp6YjxUXnBlWTxnMUJKazYzNEFZV2Ry
ZWBzWShgPXZvWmlaJUZQZXhCPGhmUWo4eitWRllwRVpLeWdkNCRBNyNCckcKelNgeyFrYGRxbk1S
T3NsbmsrR25SeTRSQjN1MVM7OVVkZV5ZMiQ5SDBtalBPcUZ1RkM1QHN+Y15PK0BGQ09ZOzYmCnpK
LXBnVCNlQDI5X0ZyKXRQPX53V1YmM0w2WWIyKVY2aSZiQz5VcD5YMTdMKGNTZiFxTnUpfSNnKSZj
QGp5OEMldAp6VH02I0RxakVJRVd+U0t1ZHNkTllQdSg2I0NFdFhIRW96e2hDNldCXz45YEpNempq
PnhRKWFPSGxMRT0yUXtNdysKeiRFQnQpYFlfNGlnZUVRe1ZffEpBKERROWZWbT4rWFZxUTlSPkBl
UDV3ZVR7UHE2TipQJXFnU0g7P0ZfYCo3KTZWCnoxO0JtQiUyPG9tWkhKMnV5ekg1RS1WSVFPWDlf
Z0F2OVpCKkQqYm5GWlpTc30lbnMzRHRJUnA3Nj53JGxVYlRhTwp6K3N4PyskWEFjUTdUR0RuYm42
PlpVKUU5ajNtcW1eaVJoMXcmfFFSZC1sPVpRNjk5WnI2PjNEKXVTWXJpQCY2aiYKemQjMT43Tkh0
V3AhXkMoWmszKVllNiN1aG9kNFQyVmN9PWF8P3NZY2BvcDtxVTQ+dTVMZjwoeTRld2pKWD9+SmM8
CnozP2d5STFqVGdPbnArdCt1QSFjYXsySGhoeGleK1VlT0FGaStQJlFaeHImPUlCX1NoT0xQK1pr
PG5SbEQ9el54NAp6RjZiIWlCUWx8MSh5Izh8RH4wKD9rYVowZUgyYzlyYH1BZ29eMnFLbGYkcHNA
bnA2NFYrTCRXamZLbThJVzdCSigKenI+MTc9PlJLc2slJXtqaGxhQEt0S0RNeyVFbUw9PkRWdCV1
RT9SaF9gbWVsVj18fjN0ZyN6MWMlYDlhQHY5Vz0qCnpZcCFEbnBPR3BsO1N+YkU+cVNGano1cmZz
cmoyQV92e2k8UjkrRTV6X2ohS0otMTs7MmNZSXIreXxTIWN1ZzU+Sgp6cU4mPkdXfjcqY0Aqa0FU
NzNqSkx0fFRKYVY2OCpKPDw3UmJwbmw/NFI0cEM2RXQpOUBaUGFlRDVlSHEqVVdlZT8KejllN2Zm
eWZreERZNEpCfmpvYCZlTzRvT1FDYnJWdjwtQjErdz93UFhpUT10Sng7PGRVNStlfWAlTCtWV2dG
Jkw4CnpvZkc0dThAeFZLajdfJTN8TlEpXzZBRl44U3lmU0dSOGVZdiRVek5CaEM3dWBod0xrN3U1
YHkzX0Ngez5xNU0+Qgp6b3tzSXtld2dJMnU4S0l3b3ckb35yRDg/ZS0wbWRuIzRUV2s2bTBhb1Z+
c1opd1VnYjhMZSMqTzJidDNRSWtLcHsKeilJIVFgJUlubTt5KFdlIT5uQ1VRUGx7MDZnSD58alJx
eUxaNlVuaUJHK3kyNWUkZ3RpamN0amBZPjB9Vlg4NmZZCnpAKlFicEBmVm1PWGEoO35jQyFjZHFV
aFV9cj1aUXQlYkFyY14qQkVQVVhIcyR7flVoMyszOFlOZS1YckhaIyZydgp6TVNwc2NEYXQjfnhQ
TUZqOU07TndWY2d0YWhmUTMqV0FgPmtTMlg4ZjlyTUd2ZXhaRX5aY318UjZacUJKNGl9VXcKemFk
X1Jibl9yYGZRfWJWOVNELVMraFNYPE12ZWt9Q1FXWUUmIXh1SmtRRzNRYlpGSnlaMU0+NmJ0cEdT
KGp6JTF1CnpQT0NPamI3TWFydXt7RjkxS0tKMGQzTkRhNkpKTkxRUn5Ob3ojKkUoIUk0YjFkcm4l
e0NoJFk/Q2s2I1Y2JmoxSgp6QkNgRHpXZGFOdjdrSTlWQEk2czwtMjBlRnFVT25MaEUoYDduKTEx
VDwoYGZUeGIrZ0pJLSY1P0htbTltXkt+UU0Kei18MytUQmY+O0VHajUkSWtBakh9d1pScDJmUSQx
Qj5IdnN0ZEI7UmhAOStmP0QrezFAbXlqLW5Jcz19TTUkJHB2CnpLVHU+NEFyUWAhK35vQUIzSzcl
IU9tX05lZDZgMkdiKG97Uy09PHNGRUVkfGBuYHMrcyh2NjBweG96RlFtKjglSgp6PmxuOU05RCk8
ejlMfEYkem1USnotIy0+Q1NAajFRR0JQXmVAa1h4OUY+VXt+bmhNI3p5N09TV2QpPnBfX1o+U3MK
ekphJkJKZS01NUUtcH4wfk1qaTtTbEUjUnY5SThKJW9nRldzV2NNWmQhZG4lV29DMjVkc1c/dUtB
XyhncVRERlokCnpXTn50SUBVWmlgaiRZNUwoflFVRTl7ZTsyPFEjOSZ0OypjLU1WUTNEVU82cnd1
JiNLSng1Pkt9MSQzQkhSR3tZbgp6ajE3ViZkQ2NnUE9RaU9QREckIzZ4YmFYNFU9JnsmZTVzWEY5
XzlraD9OWjFKKW5aMVRFZ34pNHNmYHwmTCNPVS0KejRBOzRZXlMmMilWQ25vMmEhKGhjK19MNmo4
fXZoY2psa1htKUAmJF49VT9AYU1OeGU7IXJuZzlwY3FxU3RDKj53Cno9NDZUWTdvMktCRyhjOUtz
SUI/KUJ2aGdBJk51cz8pdypBQktObGRScV45WU5ybD5ZWHRLYFRxMWxMPj91SX4wfAp6KSZ+bXFu
N3wpM3NlX0RHRXYzVntydn0oZkNHJThLJGBGbFhsdChgT0omX1lXZTg/QVk2Tj88PzdPISpWTGFp
cUcKelUyfHFVS0RacXp0WVo2MWBGc2haM3FIazFmQlkmfmhPPFA1elNjb1lKKD9kdkk3Mz0rT318
TzFNQHtFa2NVSFkpCnorKVVBYzZYa2xNd1FgaVFkY0E4aHkxPDFpNDw7b0EhVk81aSM+aTEpemlm
KTk/JSYlWmNtano5d053RihFc3VoIQp6Wkg+NjswPXNJSjc1Mz0yJUdKMmEpZSVOY18kZjRUe0lq
eHtrVUtCbjY1MH44cFQ1X3t6Q2JmOUIxYFl6VnFDT1MKemtzMz88bjlFM2BXbHh1eyU5VDEmT2VW
ZW5AfnFGZyNeSClQTyZ2SiN2ZTQwM0lxRXReSW03IW5FZ3oqI2FVYy0jCnopbXt2Xi0rTlVZenhv
WCo9KWQ+PkI9RGFFeyhtRVopcVZeX3tLQFZhY0hnaEBrcTkzfVJETn4hY3FmJWNfVW9iRQp6TT0h
TkJqRVdXKT9AUUNZc2pSNTdUV1leRVJUV3FkP1hyKzVybzRUOSp+XzBuSzFOUHohRFhWZTBvITAp
ZD4rKXkKeiZ7ZjlqPkUpRztKfDc5WnRnbysrbFZiP3VTXkQoKChNdVdZR3wjSGAmdzI2bGs1ISRX
PC0oKD4pWkU9O3k+X09HCnp2YXsoUUhHOD9iczxQYD8xLX1uKHkoZGopNilYZSF2YSk7ZlI9WCky
dmI4Z1JpNTZ7SytEM0oqKkVhaj9sQVpSaAp6aTYtcj4hMyVSb1drdHs1N3pOTHdEZHNzWkdOKE5+
SmwwRCk5Kj98aEs4LV4tPiF1O3JqP287IVMmSG1VUXFhVDQKem0qfmYqP1I9O3twRTs3K2lASHM4
IyR9eGViYVomP1hSVVF3OU9CPi1vaXZaQXBHV1UjSUV+RUNXKyl9YCotYnxGCno5RXVUKFcjU1BL
U3FQKGViY2B+aGdPKnpwZ1p0bFZJOH1SWVlCd0dheU5SNXZpUEBlZ2ElNzxlWGFia2oqby1UbAp6
V31OSnRPekMpRE14ekdTWWF3QV9sSjcmSjAoWV5HMlAwTms0cjdQfG0lbzhKcHJ4Z3lBSWc4T0Ft
YCVIOGk7Q00KeiFgSWpNT0UlU2BoeyQoPi1WMyNMWFlsJlVeQWpAayFzWGRRZy1QcVMqWEckZ0ha
fHo5TU1XN0BNTHBVZFMrQm9DCnpVNWQtMzV3Pik7S2Fyc0FJQz94JCV3dnpaP1IpMEFJV25FWkFn
YFJHZmVBUkZ4bXVaQUgocms2QE9LJjY7bXBCKwp6LTVQdz4mZWshbXhVLTxIJlgzS29Mey1Qd14r
UCt+PWxJcnpLe25ARlg9MEp7dWZ+MlNELX5pR3hvVWZpNlB3QSEKejspfjdhRUcjX2t0RUBeMSFn
fWgrdWdoYz9EK2tZP0tPZ3BQek1PczFkP2FHaEJ3TzlFMHQ7UDk1JU5hSCV3TmJECnpSNV8/RSNr
NUFxe0xhclc5UFVrY1MhcHc1WDVfY1doIS12elpyKzBebnlQWiN7OH5MPFl1YH5LI3ZHeW5RZ2JT
UQp6JU4zVD5pNDw9T3dFSylfaGYmOSR2MkdvY0Y+NnRidD5hd1QlS0tAdHF3dFF5SGpaR21hZDAw
bEBSVEhOX31lcCQKekdDPnAzQkU1M2B3OX5CfG1FK1AjanltMT4lWUpWeTRHazd+QWphclQ7JUtx
I2x6T2p9QlR3c3IjNEpxSFQyPClFCno8OzRvZUtUNCYjVFgmfH00SzlBdDlCLSZCQURub01NRGZ7
OWpwaldIOyg0Wld6SVNzTGxYNGJAcmh4UD0taEU+Rgp6YSplfmRGblpwMXlrJWJfXyN8QGZxUTUk
ZzgtQSg+JWohdDtGXm8zfXsxOX1vP3AhOWFgdGs2YmE5fWdBSSM/QUoKekMmKTdmdzNtWU5TXkp2
bS0tX256KzwxK1JzV2F+JjNTM1kkO2VUVXpobTxIQko9alhUVkx5TC14X2d+fmF9bkdQCno+SSpv
SE9eZk1TZmlpNFFIPi1GRG9TUjJUKE10dmVAbHpxRnk9VXtyRlBhMW09KWMoNUJNSzJjRVpWbk9p
UDJLfgp6a0YweUNlOXBISDJBPEpHUT5OVyVTcUIkUGRBVGw9QGRaJmM/Z1RJdDdRcl8qSGtMQUV8
OFJmJG5ENGU5bldkMnQKel9HX3cheDtuSlQ3NGpLMG5vYTQpNEZrdG9tSm42aUF9N25TelI2YUg1
cEJebFF3TjdlXlAzKTEpNj5eISglZ0BQCnptdE52cmw+fVI0dTBRVkFGRXh8YTU1TWpAbmtnU2tL
Kkx3Zk99cnQlcVNHazI+K3xkVSF8OSpkJWZnPkBYP3Y1OQp6JnFVeDNRKWcrIXs7ZD1xP3slezdu
RmArI1ROVCgyLSYoSCNVaTVnT1FQUHBhKlpjeHxrMWxDNFZ6Mz0zTVlRbiMKeiRETzdGciNNKFAo
WmpqR0BtYXJkcH04ekUoRyV2eiEobTFKNlFsd0ZCQDReZHNsPiE1bSNHUiZ2OT4wMXF+ZlJHCnpA
WkpHNHVHM1dIRmNNdGU5eCYhTmteTXA/eTZxSnp7YGIyR2xjWD12N2pVfmZvbllzKDZnUllgckF8
ekVAQXp4Iwp6Ry01NzB4YjdoQnVtdmtkYVYjKThLRThRRzlIM2Vxe1AhSkhlTyVtc3lLPWxARzRB
MiVRbWpnVFpFYVdRT20qV0wKej89MHs3e2QrbVhCUDdGemRMdk4qI3Q+IyVBYUt8N3hiY3hqNk8o
anVLS0x0T3IqLUJDRWxvfEVxciVDJGpXOXxyCnpaRWZDPzN5eHJIMGojbWNwfGNvIV8pPXhfR3w2
ZEhyK0h0Q08lVDw8N3Rydj1ARXRgdiZ3NHdoYG4yJUhwUVNwQwp6IVRqaDItcjM4YHd+KV9ycHV9
VHRQfnxpPkdIfndNSVVPI00mYDdCMldecFgrRjllaHY/VkdkRylsZF5xZCRHfFUKem9zQikrPFNR
S1N0RFkmV2J6ZW9jUSN1WGVNLUdmOTMlSVglSndFRnduJStrQUB5IS15I2p9cVFUPCpRPUZyPVV9
CnpWbGZIU0R1KEx8V0lBUkgqfGV0LXY8IWslIWs0MT81QG5OUzN9dzRYYno+djtgXnRyVEQ1dTlL
REc3VE1sWj94WQp6SGpjeVRkNjllenU3b31OQjc8aC1PKzt9bCElMlc+VSRUSldUOGNsTS1NfXdf
R3tydl5NMk81JDUhJkZSbUkwNXAKekYmKFEwV190anpIQmNlVy1AeEZOLWIqfUByZHRSLTJvQ2Va
Vz1vWHNrTGpSZSkzRDNtSnctJUI/M19gOTIqOyRjCno1ZlpLb2YhMmkqTTQ/XzBrRz1NMDJsMlVY
RVZJJXU5fHtZYl5Ie2hxcFZ3S3BgOSVvKk5oTnNyYzx1VnYkNSRwQAp6VHheaXpQTEBwKys/VWkq
YENXT3JCXjJ3bzdfR0FHOEQ+PVB5KHhrVWpLMGBpTkFXbiVPK3F2NjtrN2JYSTEqa3QKemUhSGRm
bXVDcnRRZzUkJj0pa0FucShON0Q/eChRd0pCPzNtV35WNUVWMVdgdFVgSSR+cU9rSXs3S1c9aygj
JmFvCnpjN0kpXmVjTEdLKnVyQmhGRTBXK1NqaDxSbT8hVkkqbnM/Kng2Rz1+dUU9TDRFXzd1ZTA2
RnB+V295VFVlO0lTOAp6XmQqY1dIIW59YnM8eEk8aD5RO1pEYDs0bXpNTVpEY1lZb3RDa0poaHFS
ZT81ZkZhbUYyQEMzaG5SNU8oeUYzVU4KelQteiF5PWxSSyY7QGJZbU8+cEZsOT9peCNFND1IMk5m
an15emc9PDx1Iz0jcDRJZDRoS2YjMnF1Jl81dkgyV1MwCnpeTFkycVhvd0RNY3B6Y2JHZTR+X19D
TGQkY1RPRm1aSDNZciZQZT1EXkt2e2w0VihwNTY/VH55ejNTMDxEZ287OAp6WT5mYDR2bC0yMmoj
YVlQekRvWXs7WWU3NkpuYGplYFY7NSo7bythcjBqIU9MI3pCezJPfm54cjNmUUlYWURNVTMKelRE
aUUyPXBKeT97VHshYWxlRyU+SDZxfXcmJmhBKyE+aENqUzIrZSg7Kkg+XnJ3Yi1pMyYxVyU4X0w1
amh9dyQtCnomQDU5bXdqKDhDQ149NXxfUz1DZHE0XlFNQ2E+YURsY05VaHJhSlpNWUcpbUxnQ3l2
dV9lZG50MTJJJFhhUjkpJgp6YGBhX1RmJDIqQj5Xal5iJDUhWFEmYzIlbDtVMFVWTDZwMnNnQ1p0
cGNJfDF6UzNQaj9GSnEmbE8kIyRnOFVqQU0KenJjLUozMzlwZmdDTVEzdTlPcHMlc2RyNk5UYmxg
ZHItcVR0STJYS3B5NFR2NVQoU0UpIzYqUytGTzhOYyt3QjhkCnprRG9ZOzlWNTZpNS1qIWJxVGxA
cmZqNkV+ODJPYGxhc3VhOCokaDBVJnp2PSRlbWctfEdidy0xe1kxaDw8bSheKQp6P2o0elUpamkj
aUQzUmo9MGB4SVNeeWNNeHN+OXFEKGBqJXRQZVl8e0pCQl9TeV5hZGJBcVluUTBPP1IlPiRCfkoK
ekZWWFhQXkl9Sy1NeEpBMWItVSs7KytKR344Y3hrYG1hYno1QnJoe2VFfDlPPCV1MT0wWnFuKnBl
UGMldVlYI1oqCnowYnMrYkZFT2gtO3VnVDA9TVFlPjw+a3BJQGo4JDBpMV9ifHEhc344dnAqZlJ3
SWRmWlpmazE7KkllcHpXQ0A2PAp6MkRBSDsjenM5RD1JTD1lPjJMYGw7STBuUUFINHRmPGhQdl47
alFWJlpvOEFmcmNscGM7O0lpPDl7TUtWZnxMIVUKenBsfjNjZ2BNaitOYUclbXJSfHkqMDVFRTla
bkJhcVVVSThGMVRKUHdlN1NSdiZFTDB7VldVc1NJM3ZOamNUe0JsCnpCQyp1PnI2KGY2eX41Xn5a
Kz1sOHhJVz1CYTw1MWk5ZjVHMys2e0FqN3kxS2M/Q35sNGI+aCE1czU8KDZvbzhtUAp6ezNiQUBM
e0l3elBMWXJwKDlxaHdacnp7RTd+UFJeSVh7O3w7QT1HUk8lPT1yY2dyUG9eTGJtU2VPS3hSKC0p
PW8KenBDT25jdnxPZCNOT3BmXyRMRXhhaz01d2xpYzhQejUjPHMzKmk2fmBfTV5GS0ZaMmlmTyFs
UDI4PWVeQTU8WHwkCnpWI2cmczU1blRqZWs2PXFedmB+ST5UX1AlSmIqYm4zdXRiaGU9SWJCSDlx
VWZRdFZ6Y3VKeUJ8aD58JkpOUnZgagp6UjFDdUd2bUM2RHNCfntlJmhAPz01UX1GPjtDM31AK0Ir
THgkK0hmUU50XlRhUHdjYVRURyZodm97eW59UXhPUCsKenVuXns/VllIVXJrKVI/QStqKFRAZzdD
IzlUbkU5Y3pTMztQO0E5fX15ZTQ0SUw+VGs+QnNwIWcqWUBUOTc1VHpSCnolPD9iVSQ0SldIXn1U
VFNxWWRrb15PcGwlTkZIazZ0dnFIWkwtUj5pPzY4LXEhTnQrek9aRWFtWjR9b3lqejlrfQp6S3xz
P0AqMXNBRmcxIXBiWCNzWGJMV2hHfTZRJVM4TFZ7ZHB6c3x9bUNXbUw/ViVUTmRNPSQrZUoyandK
OE08O34Kej1udXZlO2hvNkB0SUt+I2x6WUYpY1VaVEM7UGBJRCNsTiZhbndATyRSaDsqNEtLd3ch
Yj98TkRrP1lfYD8hPjZWCnpgTjBIUG5xWTJzdmZmUkR3Y0p3S205M0hmJldSVllPITY+UjE4RHUp
T2o0ekRhfChtNHFobnZmT08+QWVZUz56Twp6MmhDMShGaD1aOU95Skdfd2A4NyEmJSUzJDhuKWFO
azlnZHFzdk1fYldBPWlsTWVgI2c8cm92MS1HbWk3WmAwencKekA0Tzx4SzdFZ3U4fmMqbnJWRTlA
RTZ2aWZCY0lBfEh7Q3lBOzh6QXdtenNJPmo9elhZXlEjMC1ydlB+NGUmWCMlCnpUbnlFN3A4aG1H
JWp3Qkp6c2NOWmN9IUcqLWs9dWVGUDhRejMqZGR3bF4oWXhONF4hOWtXPGZaOXBuRE5edyFoVwp6
I0g7Qy0/UC1+bEhjaWM5LWtJQWlSUklVbCNSRGFuYVlgWS0qR0dAYmY+KWF4Tj5DNX1oVnZ4I3ZI
Sk1GbklkeE4KelMjT25QbVBhJlV5XmR6Uj1hYz4wXiZXQSVuMDkjKzFYS3lVI290MDQmeSZZRHBD
R0V3cVVLJENSTFZSfiVDXktUCnpFKTlLLWQ9dShUamV8VCE/Z2FMJWFSa15GUzUtUzw+Jn1sP0ZP
aVh7SkU9UzhiOCtMIzZSdH1LciVCRWg9UitNOQp6dD9oU2VtKTUrfGpuKWVWOTJvNChARyFLOHFs
cTw9bCV0PjY9e1VOeypWcT51Y2FBbSo1Kmk4S3tNTEpsTzApajYKejh4dUdeOXFUPjVaT0gzKHlq
IVNTT0JYR013UDFTZTluZGQ7LTJ3e2VFaWBROGlpfCghSXZ7MjU5QTQ9O0xMVDZ6CnpJcFB2ZDYh
cVZzLTB2a0VJSEhgTjc+aT5OSVFzNTc9eytCS3VwUyM3PVlhYSk+K1VWXmxpVH1PZ0pFRXMpKn5U
NQp6MmprI19zS1ApQCU1NiRQKV80O1MrdGllXmZIezNNZl8qY1o7c3NzIVhGK315RzBiWmpEc0hw
KitJanMtdF8pJSEKekl7RCRMSXUmVDl3KmlVPFZgK348Rm0jQykyP2F8WjlVWkwtJjBvZzlyVkBN
N3BfMlM5Vnx4MGZgUDU7cnUlJTNACnomdVFMXy19cEE7SmtJVlVYbWAhfVM8ZWRqeypAI1AzRHpf
KUZvMFNGVDNkRz1AakFAWl5sWnZ4I0szcHB4NWFHTQp6QCoycmpgfSY/XzVjTzlTQ25zeURxezVV
P2pAez1VMjtFUnZfdTwpKmx5cGJRU08mNSo/PkZxQ3NOWD5jLWkxYzcKejM+IWgwaUZ4LTM/I3dT
VzEoWCFsPWhRbkZQQ0JmUEBmcjZOSTUpczcpPjF5YG43Q1NJMmQqcVA5M3A9PTlKTyF5CnpiN2c2
cktwK0k+U058YC0qLSs+Slo3QlgkOUdpaWNhWGA+dDkwQ2pUQHBoQilxaGRhdi1NPk5SbDN9O3ky
ZU1PTQp6alhMblVxcDs7SyZxQnwqUElyZUF4RUVAQXprQXNjaTUtQGx3fFpZYkdwTzFUcmJEK1RJ
ZHcpcHUzTmB1en5IKHQKenUoS29qPjlke3Q9ZVpmdihjTkZEZ358ZmpCMUhQak9ZT35mPk0lUjYm
c1gxNWQwTiFCO0NkfXd4ZSUqZjZMKzgwCnpPQVJJXl81fG5PSEdCMDlxSU00YypMVjBoMyZzbTRF
Z09ieEVaVnZzQ0xIXz9eaiQ5djl8Xk1YKlQ+aUBidEhhaQp6c1A9V3dSPSlVc1MofW9ZbiVXekRr
YD5fRUpeRVJ8JSVnY18rcX5WWEpHMEM4JXwreTdnUVl0KCg9JT1NbDE8UUoKel9iWT11cz48PjRu
TEJQOEBmVXpeSlFhPk0lSE8jdj1ZNmNMdHpuSW8hcF9ZSCVFc1VNX15lLXh2NTYlND9KdkdQCnpu
SC11KEVqNGR2PmEjTDdJYjNDKW5qN3VYREVCem8/QGhUaGxabTJBQ303OD9jc1ErWilxbGx+I14k
VTVDQDhudAp6YHt9VD8pQlNPdykmMmE+KHJ+R2xRV2FfPGxfQkF2Qzl3QUp4OGt0eCNSdVE+Sm0m
SiFkWTBCT3FQezxTQnhSTzgKekZrdnhnQytNPVpfazY8OTMpeGtiOzxKbnlrK1pwYGspVCo2c2Ak
dSQ1aXlYeTUyUnB2azwtO1o+fiMjMSpOTTliCno1N3g1SHctWFBLb08maStuN2klT2wzN2t5SVZM
cGtFe1JPaTlHYD1gMlRvQnlCMjdXKUB6Vz9WS3AhXmlXKTU5bQp6Nj57bz42JlZ+JWxObHpudXM1
O0Ztd0RQZEoyZnJrcjF8KGBYMXJDRCNYUE94YnoyNFVRMTdgd3pXS3xjPUEzSHAKendZK0JSNSNA
TEF0PEs+MTRoRzxfWDdOSmdrQTMkYHhzIyVqLVA8UHh3IWI5PUVgZTtuQ2p+UHppPldLOVg5PlA2
CnpwNnwqY0dsc0lUKkgpbHpqMiYlSHpqUilCSkw1WjA9LX10OUZARzh2JikjTDUpNyRBZWV0fDUj
Q3RzR0lLfGc9Qwp6KDJTbi15cztZIWQtZClKYnhCSmVxR0l+RDE8VTFqb0NgdlEkZm5AOV4peGZU
QmA+aFo2R1IkVGByP0ZPelY5YnYKenIyRzE+YTBhJW4jN2dAIWtzTGJeQXwzP3x6SXI1VjxIR0Na
bk4/NzRVK3FwciZQaHVVTyUpZS1XVUooQGZ9dDVkCno4KjQlfVowXnBZSF9KUlhRJkg/eCFaeGE1
Y2NAfERrQjhJNXAhY25OZT4xM2w7Zmh1azhUZ215bn4md0I9MWUqcQp6JjJDbzxNYWU5Z1E/dUR8
UXxLS1dPK3tEc3JKVClPLXJUTSlfdzlpPiUkMlFTQHMyfHhYSyl9OTBANjNtbjwpU2oKek9yT1Bn
QlZudlohUHQtaWEybz1tK1dTbGI1QEg1MnRSTFQ3YTNOMmJOKzZKa28yPnMwe1U/ZTRZfnVnUnU1
aT4wClhiKk5OU1ZTK3huWUx2LUtEQCh5OE95Qi1yc1p+dFQKCmxpdGVyYWwgMApIY21WP2QwMDAw
MQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvdmliZW1pcy5zdmcgYi9hcHAvcmVzL3ZpYmVtaXMuc3Zn
CmluZGV4IGMzZjNjODEuLjcxMTVjMzMgMTAwNjQ0Ci0tLSBhL2FwcC9yZXMvdmliZW1pcy5zdmcK
KysrIGIvYXBwL3Jlcy92aWJlbWlzLnN2ZwpAQCAtMSwxOSArMSw3IEBACi08P3htbCB2ZXJzaW9u
PSIxLjAiIGVuY29kaW5nPSJVVEYtOCIgc3RhbmRhbG9uZT0ibm8iPz4KLTwhLS0gVmliZW1pcyBi
cmFuZCBtYXJrOiBhIGN1dC1nZW0gZGlhbW9uZCBjcmFkbGluZyBhIHBsYXkgdHJpYW5nbGUuCi0g
ICAgIERyYXduIGZyb20gdGhlIGRlc2lnbi1raXQgdG9rZW5zIChkb2NzL2Rlc2lnbi9yZWRlc2ln
bi9sb2dvL1JFQURNRS5tZCk6Ci0gICAgIGRpYW1vbmQgaGFsZi1kaWFnb25hbCB+MzclIG9mIHRo
ZSBib3gsIHN0cm9rZSB+Ny44JSBvZiB0aGUgYm94LCBmaWxsZWQKLSAgICAgcGxheSB0cmlhbmds
ZSB+MzAlIHRhbGwgY2VudGVyZWQgaW5zaWRlLCBhY2NlbnQgZ3JhZGllbnQKLSAgICAgIzZBRERF
NyAtPiAjMkZDNkQwLiBUaGUgc29mdCBnbG93IGlzIG9taXR0ZWQgc28gdGhlIG1hcmsgc3RheXMg
Y3Jpc3AgYXQKLSAgICAgdGhlIHNtYWxsIHNpemVzIHRoaXMgU1ZHIGlzIHJhc3Rlcml6ZWQgYXQg
KFNETCBzdHJlYW0td2luZG93IGljb24pLiAtLT4KLTxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMu
b3JnLzIwMDAvc3ZnIiB2aWV3Qm94PSIwIDAgMjU2IDI1NiIgd2lkdGg9IjI1NiIgaGVpZ2h0PSIy
NTYiPgotICA8ZGVmcz4KLSAgICA8bGluZWFyR3JhZGllbnQgaWQ9InZiQWNjZW50IiB4MT0iMCIg
eTE9IjAiIHgyPSIxIiB5Mj0iMSI+Ci0gICAgICA8c3RvcCBvZmZzZXQ9IjAiIHN0b3AtY29sb3I9
IiM2QURERTciLz4KLSAgICAgIDxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzJGQzZEMCIv
PgotICAgIDwvbGluZWFyR3JhZGllbnQ+Ci0gIDwvZGVmcz4KLSAgPHBhdGggZD0iTSAxMjggMzMu
MyBMIDIyMi43IDEyOCBMIDEyOCAyMjIuNyBMIDMzLjMgMTI4IFoiIGZpbGw9Im5vbmUiCi0gICAg
ICAgIHN0cm9rZT0idXJsKCN2YkFjY2VudCkiIHN0cm9rZS13aWR0aD0iMjAiIHN0cm9rZS1saW5l
am9pbj0icm91bmQiLz4KLSAgPHBhdGggZD0iTSAxMDcgOTIuNiBMIDEwNyAxNjMuNCBMIDE2OCAx
MjggWiIgZmlsbD0idXJsKCN2YkFjY2VudCkiCi0gICAgICAgIHN0cm9rZT0idXJsKCN2YkFjY2Vu
dCkiIHN0cm9rZS13aWR0aD0iMTIiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KKzxzdmcgeG1s
bnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iNTEyIiBoZWlnaHQ9IjUxMiIg
dmlld0JveD0iMCAwIDUxMiA1MTIiPgorPGRlZnM+PGxpbmVhckdyYWRpZW50IGlkPSJyaW0iIHgx
PSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjZmY3NThiIi8+PHN0
b3Agb2Zmc2V0PSIuNDgiIHN0b3AtY29sb3I9IiNkYzM2NTgiLz48c3RvcCBvZmZzZXQ9IjEiIHN0
b3AtY29sb3I9IiM2MzE1MmIiLz48L2xpbmVhckdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0i
Z2xhc3MiIHgxPSIwIiB5MT0iMCIgeDI9IjAiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjMjAx
NTFjIi8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjMDgwODBiIi8+PC9saW5lYXJHcmFk
aWVudD48L2RlZnM+Cis8cmVjdCB4PSIxMiIgeT0iMTIiIHdpZHRoPSI0ODgiIGhlaWdodD0iNDg4
IiByeD0iMTEwIiBmaWxsPSJ1cmwoI2dsYXNzKSIgc3Ryb2tlPSIjZmZmZmZmIiBzdHJva2Utb3Bh
Y2l0eT0iLjEzIiBzdHJva2Utd2lkdGg9IjIiLz4KKzxjaXJjbGUgY3g9IjI1NiIgY3k9IjI1NiIg
cj0iMTQ0IiBmaWxsPSJ1cmwoI3JpbSkiLz4KKzxjaXJjbGUgY3g9IjI2OCIgY3k9IjI0OSIgcj0i
MTM2IiBmaWxsPSIjMDgwODBiIi8+Cis8cGF0aCBkPSJNMTUxIDE2MmExNDMgMTQzIDAgMCAxIDEz
NS00OCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZlOGVlIiBzdHJva2Utb3BhY2l0eT0iLjU1IiBz
dHJva2Utd2lkdGg9IjMiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPgogPC9zdmc+CmRpZmYgLS1n
aXQgYS9hcHAvcmVzb3VyY2VzLnFyYyBiL2FwcC9yZXNvdXJjZXMucXJjCmluZGV4IGI1ZDRlZTcu
LjA4YmRmMmIgMTAwNjQ0Ci0tLSBhL2FwcC9yZXNvdXJjZXMucXJjCisrKyBiL2FwcC9yZXNvdXJj
ZXMucXJjCkBAIC0xLDEzICsxLDIzIEBACiA8UkNDPgogICAgIDxxcmVzb3VyY2UgcHJlZml4PSIv
Ij4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX3AucG5nIj5yZXMvc3Rl
YW0vdmliZW1pc19wLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92
aWJlbWlzLnBuZyI+cmVzL3N0ZWFtL3ZpYmVtaXMucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBh
bGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfaGVyby5wbmciPnJlcy9zdGVhbS92aWJlbWlzX2hlcm8u
cG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfbG9nby5w
bmciPnJlcy9zdGVhbS92aWJlbWlzX2xvZ28ucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlh
cz0icmVzL3N0ZWFtL3ZpYmVtaXNfaWNvbi5wbmciPnJlcy9zdGVhbS92aWJlbWlzX2ljb24ucG5n
PC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay01MTIucG5nIj5y
ZXMvdmliZW1pcy1tYXJrLTUxMi5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMv
dmliZW1pcy1tYXJrLTI1Ni5wbmciPnJlcy92aWJlbWlzLW1hcmstMjU2LnBuZzwvZmlsZT4KLSAg
ICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstMTI4LnBuZyI+cmVzL3ZpYmVtaXMt
bWFyay0xMjgucG5nPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUhhcmR3YXJlTW9u
aXRvci5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9FY2xpcHNlU3lzdGVtU2V0dGluZ3Mu
cW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUNvbWJvQm94LnFtbDwvZmlsZT4K
KyAgICAgICAgPGZpbGU+cmVzL2NyaW1zb24tbmV0d29yay5zdmc8L2ZpbGU+CisgICAgICAgIDxm
aWxlPnJlcy9jcmltc29uLWJsdWV0b290aC5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9l
Y2xpcHNlLWNvbnRyb2xzLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2VjbGlwc2UtaWNv
bi5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9lY2xpcHNlLXBvd2VyLnN2ZzwvZmlsZT4K
KyAgICAgICAgPGZpbGU+cmVzL2NyaW1zb24tYmF0dGVyeS5zdmc8L2ZpbGU+CisgICAgICAgIDxm
aWxlPnJlcy9jcmltc29uLWhvc3Quc3ZnPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVz
L3N0ZWFtL3ZpYmVtaXNfcC5wbmciPnJlcy9zdGVhbS9lY2xpcHNlX3AucG5nPC9maWxlPgorICAg
ICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXMucG5nIj5yZXMvc3RlYW0vZWNsaXBz
ZS5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19oZXJv
LnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFs
aWFzPSJyZXMvc3RlYW0vdmliZW1pc19sb2dvLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfbG9nby5w
bmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19pY29uLnBu
ZyI+cmVzL3N0ZWFtL2VjbGlwc2VfaWNvbi5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFz
PSJyZXMvdmliZW1pcy1tYXJrLTUxMi5wbmciPnJlcy9lY2xpcHNlLW1hcmstNTEyLnBuZzwvZmls
ZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstMjU2LnBuZyI+cmVzL2Vj
bGlwc2UtbWFyay0yNTYucG5nPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVt
aXMtbWFyay0xMjgucG5nIj5yZXMvZWNsaXBzZS1tYXJrLTEyOC5wbmc8L2ZpbGU+CiAgICAgICAg
IDxmaWxlIGFsaWFzPSJmb250cy9Tb3JhLnR0ZiI+Zm9udHMvU29yYS50dGY8L2ZpbGU+CiAgICAg
ICAgIDxmaWxlIGFsaWFzPSJmb250cy9NYW5yb3BlLnR0ZiI+Zm9udHMvTWFucm9wZS50dGY8L2Zp
bGU+CiAgICAgICAgIDxmaWxlPnJlcy9zb3VuZHMvbmF2X3RpY2sud2F2PC9maWxlPgpkaWZmIC0t
Z2l0IGEvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2VzLmNwcCBiL2FwcC9zZXR0aW5n
cy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5jcHAKaW5kZXggZDY5YTkxMy4uNjAyMmIyNSAxMDA2NDQK
LS0tIGEvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2VzLmNwcAorKysgYi9hcHAvc2V0
dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuY3BwCkBAIC0yMjksNyArMjI5LDcgQEAgdm9pZCBT
dHJlYW1pbmdQcmVmZXJlbmNlczo6cmVsb2FkKCkKICAgICBzZWVuV2VsY29tZUhpbnQgPSBzZXR0
aW5ncy52YWx1ZShTRVJfU0VFTldFTENPTUVISU5ULCBmYWxzZSkudG9Cb29sKCk7CiAgICAgZW5h
YmxlSGRyID0gc2V0dGluZ3MudmFsdWUoU0VSX0hEUiwgZmFsc2UpLnRvQm9vbCgpOwogICAgIHVp
U2hvd0hpbnRzID0gc2V0dGluZ3MudmFsdWUoU0VSX1VJX1NIT1dISU5UUywgdHJ1ZSkudG9Cb29s
KCk7Ci0gICAgdWlBY2NlbnRJbmRleCA9IHFCb3VuZCgwLCBzZXR0aW5ncy52YWx1ZShTRVJfVUlf
QUNDRU5USU5ERVgsIDApLnRvSW50KCksIDMpOworICAgIHVpQWNjZW50SW5kZXggPSBxQm91bmQo
MCwgc2V0dGluZ3MudmFsdWUoU0VSX1VJX0FDQ0VOVElOREVYLCA0KS50b0ludCgpLCAxNSk7CiAg
ICAgdWlTb3VuZHMgPSBzZXR0aW5ncy52YWx1ZShTRVJfVUlTT1VORFMsIHRydWUpLnRvQm9vbCgp
OwogICAgIGRpc3BsYXlIZHJDYXBhYmlsaXR5ID0gc2V0dGluZ3MudmFsdWUoU0VSX0RJU1BMQVlf
SERSX0NBUEFCSUxJVFksIHRydWUpLnRvQm9vbCgpOwogICAgIGhkclRvbmVtYXBwaW5nID0gc2V0
dGluZ3MudmFsdWUoU0VSX0hEUl9UT05FTUFQLCBmYWxzZSkudG9Cb29sKCk7CmRpZmYgLS1naXQg
YS9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmNwcCBiL2FwcC9zdHJlYW1pbmcvaW5wdXQvaW5w
dXQuY3BwCmluZGV4IDEwNTA1ZWYuLjNmYWY4N2YgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcv
aW5wdXQvaW5wdXQuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvaW5wdXQvaW5wdXQuY3BwCkBAIC04
OCw2ICs4OCwxMCBAQCBTZGxJbnB1dEhhbmRsZXI6OlNkbElucHV0SGFuZGxlcihTdHJlYW1pbmdQ
cmVmZXJlbmNlcyYgcHJlZnMsIGludCBzdHJlYW1XaWR0aCwgaQogICAgIG1fU3BlY2lhbEtleUNv
bWJvc1tLZXlDb21ib1RvZ2dsZVN0YXRzT3ZlcmxheV0ua2V5Q29kZSA9IFNETEtfczsKICAgICBt
X1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVTdGF0c092ZXJsYXldLnNjYW5Db2RlID0g
U0RMX1NDQU5DT0RFX1M7CiAgICAgbV9TcGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlU3Rh
dHNPdmVybGF5XS5lbmFibGVkID0gdHJ1ZTsKKyAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29t
Ym9Ub2dnbGVMb2NhbEhhcmR3YXJlXS5rZXlDb21ibyA9IEtleUNvbWJvVG9nZ2xlTG9jYWxIYXJk
d2FyZTsKKyAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVMb2NhbEhhcmR3YXJl
XS5rZXlDb2RlID0gU0RMS19oOworICAgIG1fU3BlY2lhbEtleUNvbWJvc1tLZXlDb21ib1RvZ2ds
ZUxvY2FsSGFyZHdhcmVdLnNjYW5Db2RlID0gU0RMX1NDQU5DT0RFX0g7CisgICAgbV9TcGVjaWFs
S2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlTG9jYWxIYXJkd2FyZV0uZW5hYmxlZCA9IHRydWU7CiAK
ICAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVNb3VzZU1vZGVdLmtleUNvbWJv
ID0gS2V5Q29tYm9Ub2dnbGVNb3VzZU1vZGU7CiAgICAgbV9TcGVjaWFsS2V5Q29tYm9zW0tleUNv
bWJvVG9nZ2xlTW91c2VNb2RlXS5rZXlDb2RlID0gU0RMS19tOwpkaWZmIC0tZ2l0IGEvYXBwL3N0
cmVhbWluZy9pbnB1dC9pbnB1dC5oIGIvYXBwL3N0cmVhbWluZy9pbnB1dC9pbnB1dC5oCmluZGV4
IGY4MjhjMDQuLjdkNWIxZGEgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvaW5wdXQvaW5wdXQu
aAorKysgYi9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmgKQEAgLTE4OCw2ICsxODgsNyBAQCBw
cml2YXRlOgogICAgICAgICBLZXlDb21ib1VuZ3JhYklucHV0LAogICAgICAgICBLZXlDb21ib1Rv
Z2dsZUZ1bGxTY3JlZW4sCiAgICAgICAgIEtleUNvbWJvVG9nZ2xlU3RhdHNPdmVybGF5LAorICAg
ICAgICBLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmUsCiAgICAgICAgIEtleUNvbWJvVG9nZ2xl
TW91c2VNb2RlLAogICAgICAgICBLZXlDb21ib1RvZ2dsZUN1cnNvckhpZGUsCiAgICAgICAgIEtl
eUNvbWJvVG9nZ2xlTWluaW1pemUsCmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL2lucHV0L2tl
eWJvYXJkLmNwcCBiL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9hcmQuY3BwCmluZGV4IDk5M2U1
MzQuLjk0MjU2MmUgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9hcmQuY3Bw
CisrKyBiL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9hcmQuY3BwCkBAIC01MSw2ICs1MSwxMSBA
QCB2b2lkIFNkbElucHV0SGFuZGxlcjo6cGVyZm9ybVNwZWNpYWxLZXlDb21ibyhLZXlDb21ibyBj
b21ibykKICAgICAgICAgcmFpc2VBbGxLZXlzKCk7CiAgICAgICAgIGJyZWFrOwogCisgICAgY2Fz
ZSBLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmU6CisgICAgICAgIFNlc3Npb246OmdldCgpLT5n
ZXRPdmVybGF5TWFuYWdlcigpLnNldE92ZXJsYXlTdGF0ZShPdmVybGF5OjpPdmVybGF5TG9jYWxI
YXJkd2FyZSwKKyAgICAgICAgICAgICAhU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2Vy
KCkuaXNPdmVybGF5RW5hYmxlZChPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkpOworICAg
ICAgICBicmVhazsKKwogICAgIGNhc2UgS2V5Q29tYm9Ub2dnbGVTdGF0c092ZXJsYXk6CiAgICAg
ICAgIFNETF9Mb2dJbmZvKFNETF9MT0dfQ0FURUdPUllfQVBQTElDQVRJT04sCiAgICAgICAgICAg
ICAgICAgICAgICJEZXRlY3RlZCBzdGF0cyB0b2dnbGUgY29tYm8iKTsKZGlmZiAtLWdpdCBhL2Fw
cC9zdHJlYW1pbmcvc2Vzc2lvbi5jcHAgYi9hcHAvc3RyZWFtaW5nL3Nlc3Npb24uY3BwCmluZGV4
IDU4ZmViOTYuLjc5MWVmNGMgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvc2Vzc2lvbi5jcHAK
KysrIGIvYXBwL3N0cmVhbWluZy9zZXNzaW9uLmNwcApAQCAtMSw0ICsxLDUgQEAKICNpbmNsdWRl
ICJzZXNzaW9uLmgiDQorI2luY2x1ZGUgPFFTZXR0aW5ncz4NCiAjaW5jbHVkZSAic2V0dGluZ3Mv
c3RyZWFtaW5ncHJlZmVyZW5jZXMuaCINCiAjaW5jbHVkZSAic3RyZWFtaW5nL3N0cmVhbXV0aWxz
LmgiDQogI2luY2x1ZGUgInN0cmVhbWluZy92cnJyYXRlcG9saWN5LmgiDQpAQCAtMjY2OSw2ICsy
NjcwLDcgQEAgdm9pZCBTZXNzaW9uOjpleGVjSW50ZXJuYWwoKQogDQogICAgIC8vIFRvZ2dsZSB0
aGUgc3RhdHMgb3ZlcmxheSBpZiByZXF1ZXN0ZWQgYnkgdGhlIHVzZXINCiAgICAgbV9PdmVybGF5
TWFuYWdlci5zZXRPdmVybGF5U3RhdGUoT3ZlcmxheTo6T3ZlcmxheURlYnVnLCBtX1ByZWZlcmVu
Y2VzLT5zaG93UGVyZm9ybWFuY2VPdmVybGF5KTsNCisgICAgbV9PdmVybGF5TWFuYWdlci5zZXRP
dmVybGF5U3RhdGUoT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUsIFFTZXR0aW5ncygpLnZh
bHVlKCJlY2xpcHNlL2xvY2FsT3ZlcmxheSIsZmFsc2UpLnRvQm9vbCgpKTsNCiANCiAgICAgLy8g
VmliZW1pczogb3B0LWluIG9uLXNjcmVlbiB0b3VjaCBjb250cm9scyBvdmVybGF5IOKAlA0KICAg
ICAvLyB0aHJlZSBpY29uLW9ubHkgYnV0dG9ucyAoTUVOVSBvcGVucyB0aGUgUXVpY2sgTWVudSwg
S0JEIHJlcXVlc3RzIHRoZSBTdGVhbU9TDQpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRl
by9mZm1wZWctcmVuZGVyZXJzL2QzZDExdmEuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1w
ZWctcmVuZGVyZXJzL2QzZDExdmEuY3BwCmluZGV4IDM4OGUzMDcuLmY4NTMyMzkgMTAwNjQ0Ci0t
LSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9kM2QxMXZhLmNwcAorKysg
Yi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZDNkMTF2YS5jcHAKQEAgLTk2
NCw3ICs5NjQsNyBAQCB2b2lkIEQzRDExVkFSZW5kZXJlcjo6bm90aWZ5T3ZlcmxheVVwZGF0ZWQo
T3ZlcmxheTo6T3ZlcmxheVR5cGUgdHlwZSkKICAgICAgICAgcmVuZGVyUmVjdC54ID0gMDsKICAg
ICAgICAgcmVuZGVyUmVjdC55ID0gMDsKICAgICB9Ci0gICAgZWxzZSBpZiAodHlwZSA9PSBPdmVy
bGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJs
YXlEZWJ1ZyB8fCB0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlKSB7CiAgICAg
ICAgIC8vIFRvcCBsZWZ0CiAgICAgICAgIHJlbmRlclJlY3QueCA9IDA7CiAgICAgICAgIHJlbmRl
clJlY3QueSA9IG1fRGlzcGxheUhlaWdodCAtIG5ld1N1cmZhY2UtPmg7CmRpZmYgLS1naXQgYS9h
cHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZHh2YTIuY3BwIGIvYXBwL3N0cmVh
bWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2R4dmEyLmNwcAppbmRleCAzMjYxOGQ4Li4wNGI1
ZDE3IDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZHh2
YTIuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9keHZhMi5j
cHAKQEAgLTg2Miw3ICs4NjIsNyBAQCB2b2lkIERYVkEyUmVuZGVyZXI6Om5vdGlmeU92ZXJsYXlV
cGRhdGVkKE92ZXJsYXk6Ok92ZXJsYXlUeXBlIHR5cGUpCiAgICAgICAgIHJlbmRlclJlY3QueCA9
IDA7CiAgICAgICAgIHJlbmRlclJlY3QueSA9IG1fRGlzcGxheUhlaWdodCAtIG5ld1N1cmZhY2Ut
Pmg7CiAgICAgfQotICAgIGVsc2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7
CisgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgdHlwZSA9PSBP
dmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAvLyBUb3AgbGVmdAogICAg
ICAgICByZW5kZXJSZWN0LnggPSAwOwogICAgICAgICByZW5kZXJSZWN0LnkgPSAwOwpkaWZmIC0t
Z2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2VnbHZpZC5jcHAgYi9h
cHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZWdsdmlkLmNwcAppbmRleCA5NTg3
YTM1Li4yMDY4MGQ4IDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5k
ZXJlcnMvZWdsdmlkLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJl
cnMvZWdsdmlkLmNwcApAQCAtMjM0LDEwICsyMzQsMTAgQEAgdm9pZCBFR0xSZW5kZXJlcjo6cmVu
ZGVyT3ZlcmxheShPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBlLCBpbnQgdmlld3BvcnRXaWR0aCwg
aW4KICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnggPSAwOwogICAgICAgICAgICAgb3ZlcmxheVJl
Y3QueSA9IDA7CiAgICAgICAgIH0KLSAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpP
dmVybGF5RGVidWcpIHsKKyAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5
RGVidWcgfHwgdHlwZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAg
ICAgICAgLy8gVmliZW1pczogdXNlci1jb25maWd1cmFibGUgY29ybmVyLiBOQjogT3BlbkdMIG9y
aWdpbiBpcyBsb3dlci1sZWZ0LAogICAgICAgICAgICAgLy8gc28gInRvcCIgaXMgdGhlIGhpZ2gt
WSBlZGdlIGhlcmUuCi0gICAgICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdl
dE92ZXJsYXlNYW5hZ2VyKCkuZ2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAgICAgICAgICBp
bnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0T3Zlcmxh
eUFuY2hvcih0eXBlKTsKICAgICAgICAgICAgIGJvb2wgcmlnaHQgPSAoYW5jaG9yID09IDEgfHwg
YW5jaG9yID09IDMpOyAgLy8gVFIgb3IgQlIKICAgICAgICAgICAgIGJvb2wgYm90dG9tID0gKGFu
Y2hvciA9PSAyIHx8IGFuY2hvciA9PSAzKTsgLy8gQkwgb3IgQlIKICAgICAgICAgICAgIG92ZXJs
YXlSZWN0LnggPSByaWdodCA/ICh2aWV3cG9ydFdpZHRoIC0gbmV3U3VyZmFjZS0+dykgOiAwOwpk
aWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3BsdmsuY3Bw
IGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3BsdmsuY3BwCmluZGV4IGJj
MTZmZjIuLmJhYzE4NWIgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJl
bmRlcmVycy9wbHZrLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJl
cnMvcGx2ay5jcHAKQEAgLTEzODIsMTAgKzEzODIsMTAgQEAgdm9pZCBQbFZrUmVuZGVyZXI6OnJl
bmRlckZyYW1lKEFWRnJhbWUgKmZyYW1lKQogICAgICAgICAgICAgICAgIG92ZXJsYXlQYXJ0c1tp
XS5kc3QueDAgPSAwOw0KICAgICAgICAgICAgICAgICBvdmVybGF5UGFydHNbaV0uZHN0LnkwID0g
U0RMX21heCgwLCB0YXJnZXRGcmFtZS5jcm9wLnkxIC0gb3ZlcmxheVBhcnRzW2ldLnNyYy55MSk7
DQogICAgICAgICAgICAgfQ0KLSAgICAgICAgICAgIGVsc2UgaWYgKGkgPT0gT3ZlcmxheTo6T3Zl
cmxheURlYnVnKSB7DQotICAgICAgICAgICAgICAgIC8vIFRvcCBsZWZ0DQotICAgICAgICAgICAg
ICAgIG92ZXJsYXlQYXJ0c1tpXS5kc3QueDAgPSAwOw0KLSAgICAgICAgICAgICAgICBvdmVybGF5
UGFydHNbaV0uZHN0LnkwID0gMDsNCisgICAgICAgICAgICBlbHNlIGlmIChpID09IE92ZXJsYXk6
Ok92ZXJsYXlEZWJ1ZyB8fCBpID09IE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlKSB7DQor
ICAgICAgICAgICAgICAgIGludCBhbmNob3I9U2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5h
Z2VyKCkuZ2V0T3ZlcmxheUFuY2hvcihzdGF0aWNfY2FzdDxPdmVybGF5OjpPdmVybGF5VHlwZT4o
aSkpOw0KKyAgICAgICAgICAgICAgICBvdmVybGF5UGFydHNbaV0uZHN0LngwPShhbmNob3I9PTEg
fHwgYW5jaG9yPT0zKSA/IFNETF9tYXgoMCx0YXJnZXRGcmFtZS5jcm9wLngxLW92ZXJsYXlQYXJ0
c1tpXS5zcmMueDEpIDogMDsNCisgICAgICAgICAgICAgICAgb3ZlcmxheVBhcnRzW2ldLmRzdC55
MD0oYW5jaG9yPT0yIHx8IGFuY2hvcj09MykgPyBTRExfbWF4KDAsdGFyZ2V0RnJhbWUuY3JvcC55
MS1vdmVybGF5UGFydHNbaV0uc3JjLnkxKSA6IDA7DQogICAgICAgICAgICAgfQ0KICAgICAgICAg
ICAgIGVsc2UgaWYgKGkgPT0gT3ZlcmxheTo6T3ZlcmxheVRvdWNoQnV0dG9uTWVudSB8fCBpID09
IE92ZXJsYXk6Ok92ZXJsYXlUb3VjaEJ1dHRvbktiZCB8fA0KICAgICAgICAgICAgICAgICAgICAg
IGkgPT0gT3ZlcmxheTo6T3ZlcmxheVRvdWNoQnV0dG9uVG91Y2hNb2RlKSB7DQpkaWZmIC0tZ2l0
IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3NkbHZpZC5jcHAgYi9hcHAv
c3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvc2RsdmlkLmNwcAppbmRleCA1NjdiZjE5
Li5mMTMyNWVkIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJl
cnMvc2RsdmlkLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMv
c2RsdmlkLmNwcApAQCAtMjQxLDExICsyNDEsMTEgQEAgdm9pZCBTZGxSZW5kZXJlcjo6cmVuZGVy
T3ZlcmxheShPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBlKQogICAgICAgICAgICAgICAgIG1fT3Zl
cmxheVJlY3RzW3R5cGVdLnggPSAwOwogICAgICAgICAgICAgICAgIG1fT3ZlcmxheVJlY3RzW3R5
cGVdLnkgPSB2aWV3cG9ydFJlY3QuaCAtIG5ld1N1cmZhY2UtPmg7CiAgICAgICAgICAgICB9Ci0g
ICAgICAgICAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZykgeworICAg
ICAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgdHlwZSA9
PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAgICAgICAgIC8vIFZp
YmVtaXM6IHVzZXItY29uZmlndXJhYmxlIGNvcm5lciAoU0RMIG9yaWdpbiBpcyB1cHBlci1sZWZ0
KS4KICAgICAgICAgICAgICAgICBTRExfUmVjdCB2aWV3cG9ydFJlY3Q7CiAgICAgICAgICAgICAg
ICAgU0RMX1JlbmRlckdldFZpZXdwb3J0KG1fUmVuZGVyZXIsICZ2aWV3cG9ydFJlY3QpOwotICAg
ICAgICAgICAgICAgIGludCBhbmNob3IgPSBTZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFn
ZXIoKS5nZXREZWJ1Z092ZXJsYXlBbmNob3IoKTsKKyAgICAgICAgICAgICAgICBpbnQgYW5jaG9y
ID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0T3ZlcmxheUFuY2hvcih0
eXBlKTsKICAgICAgICAgICAgICAgICBib29sIHJpZ2h0ID0gKGFuY2hvciA9PSAxIHx8IGFuY2hv
ciA9PSAzKTsgIC8vIFRSIG9yIEJSCiAgICAgICAgICAgICAgICAgYm9vbCBib3R0b20gPSAoYW5j
aG9yID09IDIgfHwgYW5jaG9yID09IDMpOyAvLyBCTCBvciBCUgogICAgICAgICAgICAgICAgIG1f
T3ZlcmxheVJlY3RzW3R5cGVdLnggPSByaWdodCA/ICh2aWV3cG9ydFJlY3QudyAtIG5ld1N1cmZh
Y2UtPncpIDogMDsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRl
cmVycy92YWFwaS5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdmFh
cGkuY3BwCmluZGV4IGFiNjVlMGIuLjI4NDNmZDYgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcv
dmlkZW8vZmZtcGVnLXJlbmRlcmVycy92YWFwaS5jcHAKKysrIGIvYXBwL3N0cmVhbWluZy92aWRl
by9mZm1wZWctcmVuZGVyZXJzL3ZhYXBpLmNwcApAQCAtNzQxLDkgKzc0MSw5IEBAIHZvaWQgVkFB
UElSZW5kZXJlcjo6bm90aWZ5T3ZlcmxheVVwZGF0ZWQoT3ZlcmxheTo6T3ZlcmxheVR5cGUgdHlw
ZSkKICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnggPSAwOwogICAgICAgICAgICAgb3ZlcmxheVJl
Y3QueSA9IC1uZXdTdXJmYWNlLT5oOwogICAgICAgICB9Ci0gICAgICAgIGVsc2UgaWYgKHR5cGUg
PT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7CisgICAgICAgIGVsc2UgaWYgKHR5cGUgPT0gT3Zl
cmxheTo6T3ZlcmxheURlYnVnIHx8IHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdh
cmUpIHsKICAgICAgICAgICAgIC8vIFZpYmVtaXM6IHVzZXItY29uZmlndXJhYmxlIGNvcm5lciAo
dXBwZXItbGVmdCBvcmlnaW4pLgotICAgICAgICAgICAgaW50IGFuY2hvciA9IFNlc3Npb246Omdl
dCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmdldERlYnVnT3ZlcmxheUFuY2hvcigpOworICAgICAg
ICAgICAgaW50IGFuY2hvciA9IFNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmdl
dE92ZXJsYXlBbmNob3IodHlwZSk7CiAgICAgICAgICAgICBib29sIHJpZ2h0ID0gKGFuY2hvciA9
PSAxIHx8IGFuY2hvciA9PSAzKTsgIC8vIFRSIG9yIEJSCiAgICAgICAgICAgICBib29sIGJvdHRv
bSA9IChhbmNob3IgPT0gMiB8fCBhbmNob3IgPT0gMyk7IC8vIEJMIG9yIEJSCiAgICAgICAgICAg
ICBvdmVybGF5UmVjdC54ID0gcmlnaHQgPyAobV9EaXNwbGF5V2lkdGggLSBuZXdTdXJmYWNlLT53
KSA6IDA7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMv
dmRwYXUuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3ZkcGF1LmNw
cAppbmRleCAyZjllMGMzLi45MDZhY2NjIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVv
L2ZmbXBlZy1yZW5kZXJlcnMvdmRwYXUuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZt
cGVnLXJlbmRlcmVycy92ZHBhdS5jcHAKQEAgLTQzNiw5ICs0MzYsOSBAQCB2b2lkIFZEUEFVUmVu
ZGVyZXI6Om5vdGlmeU92ZXJsYXlVcGRhdGVkKE92ZXJsYXk6Ok92ZXJsYXlUeXBlIHR5cGUpCiAg
ICAgICAgICAgICBvdmVybGF5UmVjdC54MCA9IDA7CiAgICAgICAgICAgICBvdmVybGF5UmVjdC55
MCA9IG1fRGlzcGxheUhlaWdodCAtIG5ld1N1cmZhY2UtPmg7CiAgICAgICAgIH0KLSAgICAgICAg
ZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICAgICAgZWxzZSBp
ZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgdHlwZSA9PSBPdmVybGF5OjpPdmVy
bGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAgICAgLy8gVmliZW1pczogdXNlci1jb25maWd1
cmFibGUgY29ybmVyICh1cHBlci1sZWZ0IG9yaWdpbikuCi0gICAgICAgICAgICBpbnQgYW5jaG9y
ID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0RGVidWdPdmVybGF5QW5j
aG9yKCk7CisgICAgICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJs
YXlNYW5hZ2VyKCkuZ2V0T3ZlcmxheUFuY2hvcih0eXBlKTsKICAgICAgICAgICAgIGJvb2wgcmln
aHQgPSAoYW5jaG9yID09IDEgfHwgYW5jaG9yID09IDMpOyAgLy8gVFIgb3IgQlIKICAgICAgICAg
ICAgIGJvb2wgYm90dG9tID0gKGFuY2hvciA9PSAyIHx8IGFuY2hvciA9PSAzKTsgLy8gQkwgb3Ig
QlIKICAgICAgICAgICAgIG92ZXJsYXlSZWN0LngwID0gcmlnaHQgPyAobV9EaXNwbGF5V2lkdGgg
LSBuZXdTdXJmYWNlLT53KSA6IDA7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2Zm
bXBlZy1yZW5kZXJlcnMvdnRfYXZzYW1wbGVsYXllci5tbSBiL2FwcC9zdHJlYW1pbmcvdmlkZW8v
ZmZtcGVnLXJlbmRlcmVycy92dF9hdnNhbXBsZWxheWVyLm1tCmluZGV4IGJkNTUyODEuLjEzZDg4
YzYgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9h
dnNhbXBsZWxheWVyLm1tCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVy
cy92dF9hdnNhbXBsZWxheWVyLm1tCkBAIC00OTYsNiArNDk2LDcgQEAgcHVibGljOgogICAgICAg
ICAgICAgW21fT3ZlcmxheVRleHRGaWVsZHNbdHlwZV0gc2V0U2VsZWN0YWJsZTpOT107CiAKICAg
ICAgICAgICAgIHN3aXRjaCAodHlwZSkgeworICAgICAgICAgICAgY2FzZSBPdmVybGF5OjpPdmVy
bGF5TG9jYWxIYXJkd2FyZToKICAgICAgICAgICAgIGNhc2UgT3ZlcmxheTo6T3ZlcmxheURlYnVn
OgogICAgICAgICAgICAgICAgIFttX092ZXJsYXlUZXh0RmllbGRzW3R5cGVdIHNldEFsaWdubWVu
dDpOU1RleHRBbGlnbm1lbnRMZWZ0XTsKICAgICAgICAgICAgICAgICBicmVhazsKZGlmZiAtLWdp
dCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9tZXRhbC5tbSBiL2Fw
cC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9tZXRhbC5tbQppbmRleCA3OWIx
NjVkLi4zMzRlZWZmIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5k
ZXJlcnMvdnRfbWV0YWwubW0KKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVy
ZXJzL3Z0X21ldGFsLm1tCkBAIC02MDAsNyArNjAwLDcgQEAgcHVibGljOgogICAgICAgICAgICAg
ICAgICAgICByZW5kZXJSZWN0LnggPSAwOwogICAgICAgICAgICAgICAgICAgICByZW5kZXJSZWN0
LnkgPSAwOwogICAgICAgICAgICAgICAgIH0KLSAgICAgICAgICAgICAgICBlbHNlIGlmIChpID09
IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZykgeworICAgICAgICAgICAgICAgIGVsc2UgaWYgKGkgPT0g
T3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8IGkgPT0gT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdh
cmUpIHsKICAgICAgICAgICAgICAgICAgICAgLy8gVG9wIGxlZnQKICAgICAgICAgICAgICAgICAg
ICAgcmVuZGVyUmVjdC54ID0gMDsKICAgICAgICAgICAgICAgICAgICAgcmVuZGVyUmVjdC55ID0g
bV9MYXN0RHJhd2FibGVIZWlnaHQgLSBvdmVybGF5VGV4dHVyZS5oZWlnaHQ7CmRpZmYgLS1naXQg
YS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2Zm
bXBlZy5jcHAKaW5kZXggMmFjMWE2ZS4uNGE2ZTBjMCAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWlu
Zy92aWRlby9mZm1wZWcuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLmNwcApA
QCAtMSw1ICsxLDYgQEAKICNpbmNsdWRlIDxMaW1lbGlnaHQuaD4KICNpbmNsdWRlICJmZm1wZWcu
aCIKKyNpbmNsdWRlICJtb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmgiCiAjaW5jbHVkZSAic3Ry
ZWFtaW5nL3Nlc3Npb24uaCIKICNpbmNsdWRlICJiYWNrZW5kL3N5c3RlbXByb3BlcnRpZXMuaCIK
ICNpbmNsdWRlICJzZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5oIgpAQCAtMjQ0MCw2ICsy
NDQxLDExIEBAIGludCBGRm1wZWdWaWRlb0RlY29kZXI6OnN1Ym1pdERlY29kZVVuaXQoUERFQ09E
RV9VTklUIGR1KQogICAgICAgICAgICAgU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2Vy
KCkuc2V0T3ZlcmxheVRleHRVcGRhdGVkKE92ZXJsYXk6Ok92ZXJsYXlEZWJ1Zyk7CiAgICAgICAg
IH0KIAorICAgICAgICBpZihTZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5pc092
ZXJsYXlFbmFibGVkKE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlKSkgeworICAgICAgICAg
ICAgUUJ5dGVBcnJheSB0ZXh0PUxvY2FsSGFyZHdhcmU6Om92ZXJsYXlUZXh0KCkudG9VdGY4KCk7
CisgICAgICAgICAgICBTZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS51cGRhdGVP
dmVybGF5VGV4dChPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSx0ZXh0LmNvbnN0RGF0YSgp
KTsKKyAgICAgICAgfQorCiAgICAgICAgIC8vIEFjY3VtdWxhdGUgdGhlc2UgdmFsdWVzIGludG8g
dGhlIGdsb2JhbCBzdGF0cwogICAgICAgICBhZGRWaWRlb1N0YXRzKG1fQWN0aXZlV25kVmlkZW9T
dGF0cywgbV9HbG9iYWxWaWRlb1N0YXRzKTsKIApkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92
aWRlby9vdmVybGF5bWFuYWdlci5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5h
Z2VyLmNwcAppbmRleCA5MmU2YzZkLi40ODNmZmRiIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5n
L3ZpZGVvL292ZXJsYXltYW5hZ2VyLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJs
YXltYW5hZ2VyLmNwcApAQCAtMSw2ICsxLDEyIEBACiAjaW5jbHVkZSAib3ZlcmxheW1hbmFnZXIu
aCIKICNpbmNsdWRlICJwYXRoLmgiCiAjaW5jbHVkZSAic2V0dGluZ3Mvc3RyZWFtaW5ncHJlZmVy
ZW5jZXMuaCIKKyNpbmNsdWRlICJtb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmgiCisjaW5jbHVk
ZSAibW9vbmxpZ2h0b3Mvb3ZlcmxheXN0eWxlLmgiCisjaW5jbHVkZSA8UVNldHRpbmdzPgorI2lu
Y2x1ZGUgPFFJbWFnZT4KKyNpbmNsdWRlIDxRUGFpbnRlcj4KKyNpbmNsdWRlIDxRQ29sb3I+CiAK
IHVzaW5nIG5hbWVzcGFjZSBPdmVybGF5OwogCkBAIC05LDYgKzE1LDEzIEBAIGludCBPdmVybGF5
TWFuYWdlcjo6Z2V0RGVidWdPdmVybGF5QW5jaG9yKCkKICAgICByZXR1cm4gc3RhdGljX2Nhc3Q8
aW50PihTdHJlYW1pbmdQcmVmZXJlbmNlczo6Z2V0KCktPnBlcmZPdmVybGF5UG9zaXRpb24pOwog
fQogCitpbnQgT3ZlcmxheU1hbmFnZXI6OmdldE92ZXJsYXlBbmNob3IoT3ZlcmxheVR5cGUgdHlw
ZSkgeworICAgIGludCBzdHJlYW09Z2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAgaWYodHlw
ZSE9T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHJldHVybiBzdHJlYW07CisgICAgaW50IGxvY2FsPXFC
b3VuZCgwLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2FsUG9zaXRpb24iLDEpLnRvSW50
KCksMyk7CisgICAgcmV0dXJuIGlzT3ZlcmxheUVuYWJsZWQoT3ZlcmxheURlYnVnKSAmJiBsb2Nh
bD09c3RyZWFtID8gKGxvY2FsIF4gMSkgOiBsb2NhbDsKK30KKwogT3ZlcmxheU1hbmFnZXI6Ok92
ZXJsYXlNYW5hZ2VyKCkgOgogICAgIG1fUmVuZGVyZXIobnVsbHB0ciksCiAgICAgbV9Gb250RGF0
YShQYXRoOjpyZWFkRGF0YUZpbGUoIk1vZGVTZXZlbi50dGYiKSkKQEAgLTMyLDggKzQ1LDEwIEBA
IE92ZXJsYXlNYW5hZ2VyOjpPdmVybGF5TWFuYWdlcigpIDoKICAgICAgICAgYnJlYWs7CiAgICAg
fQogCi0gICAgbV9PdmVybGF5c1tPdmVybGF5VHlwZTo6T3ZlcmxheURlYnVnXS5jb2xvciA9IHsw
eEQwLCAweEQwLCAweDAwLCAweEZGfTsKKyAgICBtX092ZXJsYXlzW092ZXJsYXlUeXBlOjpPdmVy
bGF5RGVidWddLmNvbG9yID0gezB4RUMsIDB4RUUsIDB4RjEsIDB4RkZ9OwogICAgIG1fT3Zlcmxh
eXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlEZWJ1Z10uZm9udFNpemUgPSBkZWJ1Z0ZvbnRTaXplOwor
ICAgIG1fT3ZlcmxheXNbT3ZlcmxheUxvY2FsSGFyZHdhcmVdLmNvbG9yID0gezB4RUMsMHhFRSww
eEYxLDB4RkZ9OworICAgIG1fT3ZlcmxheXNbT3ZlcmxheUxvY2FsSGFyZHdhcmVdLmZvbnRTaXpl
ID0gZGVidWdGb250U2l6ZTsKIAogICAgIG1fT3ZlcmxheXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlT
dGF0dXNVcGRhdGVdLmNvbG9yID0gezB4Q0MsIDB4MDAsIDB4MDAsIDB4RkZ9OwogICAgIG1fT3Zl
cmxheXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlTdGF0dXNVcGRhdGVdLmZvbnRTaXplID0gMzY7CkBA
IC0xMjYsNiArMTQxLDEwIEBAIFNETF9TdXJmYWNlKiBPdmVybGF5TWFuYWdlcjo6Z2V0VXBkYXRl
ZE92ZXJsYXlTdXJmYWNlKE92ZXJsYXlUeXBlIHR5cGUpCiAKIHZvaWQgT3ZlcmxheU1hbmFnZXI6
OnNldE92ZXJsYXlUZXh0VXBkYXRlZChPdmVybGF5VHlwZSB0eXBlKQogeworICAgIGlmKG1fT3Zl
cmxheXNbdHlwZV0uZW5hYmxlZCAmJiAodHlwZT09T3ZlcmxheURlYnVnIHx8IHR5cGU9PU92ZXJs
YXlMb2NhbEhhcmR3YXJlKSkgeworICAgICAgICBRTXV0ZXhMb2NrZXIgZ3JhcGhMb2NrKCZtX0dy
YXBoTG9jayk7CisgICAgICAgIENyaW1zb25HcmFwaHM6OnB1c2gobV9HcmFwaEhpc3RvcnlbdHlw
ZV0sQ3JpbXNvbkdyYXBoczo6dmFsdWVzKFFTdHJpbmc6OmZyb21VdGY4KG1fT3ZlcmxheXNbdHlw
ZV0udGV4dCksdHlwZT09T3ZlcmxheUxvY2FsSGFyZHdhcmUsTG9jYWxIYXJkd2FyZTo6c2FtcGxl
KCkpKTsKKyAgICB9CiAgICAgLy8gT25seSB1cGRhdGUgdGhlIG92ZXJsYXkgc3RhdGUgaWYgaXQn
cyBlbmFibGVkLiBJZiBpdCdzIG5vdCBlbmFibGVkLAogICAgIC8vIHRoZSByZW5kZXJlciBoYXMg
YWxyZWFkeSBiZWVuIG5vdGlmaWVkIGJ5IHNldE92ZXJsYXlTdGF0ZSgpLgogICAgIGlmIChtX092
ZXJsYXlzW3R5cGVdLmVuYWJsZWQpIHsKQEAgLTE0Myw2ICsxNjIsNyBAQCB2b2lkIE92ZXJsYXlN
YW5hZ2VyOjpzZXRPdmVybGF5U3RhdGUoT3ZlcmxheVR5cGUgdHlwZSwgYm9vbCBlbmFibGVkKQog
ICAgICAgICBpZiAoIWVuYWJsZWQpIHsKICAgICAgICAgICAgIC8vIFNldCB0aGUgdGV4dCB0byBl
bXB0eSBzdHJpbmcgb24gZGlzYWJsZQogICAgICAgICAgICAgbV9PdmVybGF5c1t0eXBlXS50ZXh0
WzBdID0gMDsKKyAgICAgICAgICAgIHsgUU11dGV4TG9ja2VyIGdyYXBoTG9jaygmbV9HcmFwaExv
Y2spO21fR3JhcGhIaXN0b3J5W3R5cGVdLmNsZWFyKCk7IH0KICAgICAgICAgfQogCiAgICAgICAg
IG5vdGlmeU92ZXJsYXlVcGRhdGVkKHR5cGUpOwpAQCAtMzY4LDExICszODgsMjcgQEAgdm9pZCBP
dmVybGF5TWFuYWdlcjo6bm90aWZ5T3ZlcmxheVVwZGF0ZWQoT3ZlcmxheVR5cGUgdHlwZSkKICAg
ICB9CiAKICAgICBpZiAobV9PdmVybGF5c1t0eXBlXS5lbmFibGVkKSB7Ci0gICAgICAgIC8vIFRo
ZSBfV3JhcHBlZCB2YXJpYW50IGlzIHJlcXVpcmVkIGZvciBsaW5lIGJyZWFrcyB0byB3b3JrCi0g
ICAgICAgIFNETF9TdXJmYWNlKiBzdXJmYWNlID0gVFRGX1JlbmRlclRleHRfQmxlbmRlZF9XcmFw
cGVkKG1fT3ZlcmxheXNbdHlwZV0uZm9udCwKLSAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgbV9PdmVybGF5c1t0eXBlXS50ZXh0LAot
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICBtX092ZXJsYXlzW3R5cGVdLmNvbG9yLAotICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAxMDI0KTsKKyAgICAgICAgUUJ5dGVB
cnJheSB0ZXh0KG1fT3ZlcmxheXNbdHlwZV0udGV4dCk7CisgICAgICAgIGNvbnN0IGJvb2wgY2Fy
ZD10eXBlPT1PdmVybGF5RGVidWcgfHwgdHlwZT09T3ZlcmxheUxvY2FsSGFyZHdhcmU7CisgICAg
ICAgIGNvbnN0IGJvb2wgZGV0YWlsZWQ9UVNldHRpbmdzKCkudmFsdWUodHlwZT09T3ZlcmxheURl
YnVnPyJlY2xpcHNlL3N0cmVhbURldGFpbGVkIjoiZWNsaXBzZS9sb2NhbERldGFpbGVkIixmYWxz
ZSkudG9Cb29sKCk7CisgICAgICAgIGlmKGNhcmQgJiYgIWRldGFpbGVkKSB0ZXh0PSh0eXBlPT1P
dmVybGF5RGVidWc/IkVjbGlwc2VPUyB8IFNUUkVBTSI6IkVjbGlwc2VPUyB8IExPQ0FMIik7Cisg
ICAgICAgIGVsc2UgaWYodHlwZT09T3ZlcmxheURlYnVnKSB0ZXh0LnByZXBlbmQoIkVjbGlwc2VP
UyB8IFNUUkVBTVxuIik7CisgICAgICAgIFNETF9TdXJmYWNlKiBzdXJmYWNlPVRURl9SZW5kZXJV
VEY4X0JsZW5kZWRfV3JhcHBlZChtX092ZXJsYXlzW3R5cGVdLmZvbnQsdGV4dC5jb25zdERhdGEo
KSxtX092ZXJsYXlzW3R5cGVdLmNvbG9yLGNhcmQ/NDgwOjEwMjQpOworICAgICAgICBpZihjYXJk
ICYmIHN1cmZhY2UpIHsKKyAgICAgICAgICAgIGludCBmb250U2l6ZT1tX092ZXJsYXlzW3R5cGVd
LmZvbnRTaXplOworICAgICAgICAgICAgaW50IGdyYXBoSGVpZ2h0PTQqKGZvbnRTaXplKzIyKSsx
MjsKKyAgICAgICAgICAgIGludCB3aWR0aD1xTWF4KHN1cmZhY2UtPncrMzIsNDgwKTsKKyAgICAg
ICAgICAgIFFJbWFnZSBpbWFnZT1FY2xpcHNlT3ZlcmxheVN0eWxlOjpwYW5lbChRU2l6ZSh3aWR0
aCxzdXJmYWNlLT5oKzMyK2dyYXBoSGVpZ2h0KSxTdHJlYW1pbmdQcmVmZXJlbmNlczo6Z2V0KCkt
PnVpQWNjZW50SW5kZXgsUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2Uvb3ZlcmxheU9wYWNpdHki
LDg1KS50b0ludCgpKTsKKyAgICAgICAgICAgIENyaW1zb25HcmFwaHM6Okhpc3RvcnkgaGlzdG9y
eTsKKyAgICAgICAgICAgIHsgUU11dGV4TG9ja2VyIGdyYXBoTG9jaygmbV9HcmFwaExvY2spO2hp
c3Rvcnk9bV9HcmFwaEhpc3RvcnlbdHlwZV07IH0KKyAgICAgICAgICAgIGlmKCFpbWFnZS5pc051
bGwoKSkgQ3JpbXNvbkdyYXBoczo6cGFpbnQoaW1hZ2Usc3VyZmFjZS0+aCsyNCxxTWluKGZvbnRT
aXplLDIwKSxTdHJlYW1pbmdQcmVmZXJlbmNlczo6Z2V0KCktPnVpQWNjZW50SW5kZXgsaGlzdG9y
eSx0eXBlPT1PdmVybGF5TG9jYWxIYXJkd2FyZSk7CisgICAgICAgICAgICBTRExfU3VyZmFjZSog
cGFuZWw9aW1hZ2UuaXNOdWxsKCk/bnVsbHB0cjpTRExfQ3JlYXRlUkdCU3VyZmFjZVdpdGhGb3Jt
YXQoMCxpbWFnZS53aWR0aCgpLGltYWdlLmhlaWdodCgpLDMyLFNETF9QSVhFTEZPUk1BVF9SR0JB
MzIpOworICAgICAgICAgICAgaWYocGFuZWwpIHsKKyAgICAgICAgICAgICAgICBmb3IoaW50IHJv
dz0wO3JvdzxpbWFnZS5oZWlnaHQoKTsrK3JvdykgbWVtY3B5KHN0YXRpY19jYXN0PGNoYXIqPihw
YW5lbC0+cGl4ZWxzKStyb3cqcGFuZWwtPnBpdGNoLGltYWdlLmNvbnN0U2NhbkxpbmUocm93KSxp
bWFnZS53aWR0aCgpKjQpOworICAgICAgICAgICAgICAgIFNETF9SZWN0IGRlc3Q9ezE2LDE2LHN1
cmZhY2UtPncsc3VyZmFjZS0+aH07U0RMX0JsaXRTdXJmYWNlKHN1cmZhY2UsbnVsbHB0cixwYW5l
bCwmZGVzdCk7CisgICAgICAgICAgICAgICAgU0RMX0ZyZWVTdXJmYWNlKHN1cmZhY2UpO3N1cmZh
Y2U9cGFuZWw7CisgICAgICAgICAgICB9CisgICAgICAgIH0KIAogICAgICAgICBTRExfQXRvbWlj
U2V0UHRyKCh2b2lkKiopJm1fT3ZlcmxheXNbdHlwZV0uc3VyZmFjZSwgc3VyZmFjZSk7CiAgICAg
fQpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9vdmVybGF5bWFuYWdlci5oIGIvYXBw
L3N0cmVhbWluZy92aWRlby9vdmVybGF5bWFuYWdlci5oCmluZGV4IGUxOWZjMGMuLjQxMTJhMWQg
MTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vb3ZlcmxheW1hbmFnZXIuaAorKysgYi9h
cHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5hZ2VyLmgKQEAgLTIsNiArMiw3IEBACiAKICNp
bmNsdWRlIDxRU3RyaW5nPgogI2luY2x1ZGUgPFFNdXRleD4KKyNpbmNsdWRlICJtb29ubGlnaHRv
cy9jcmltc29uZ3JhcGhzLmgiCiAKICNpbmNsdWRlICJTRExfY29tcGF0LmgiCiAjaW5jbHVkZSA8
U0RMX3R0Zi5oPgpAQCAtMTAsNiArMTEsNyBAQCBuYW1lc3BhY2UgT3ZlcmxheSB7CiAKIGVudW0g
T3ZlcmxheVR5cGUgewogICAgIE92ZXJsYXlEZWJ1ZywKKyAgICBPdmVybGF5TG9jYWxIYXJkd2Fy
ZSwKICAgICBPdmVybGF5U3RhdHVzVXBkYXRlLAogICAgIE92ZXJsYXlTZXJ2ZXJDb21tYW5kcywK
ICAgICBPdmVybGF5UXVpY2tNZW51LApAQCAtNzAsNiArNzIsNyBAQCBwdWJsaWM6CiAgICAgLy8g
cHJlZmVyZW5jZS4gUmV0dXJucyBTdHJlYW1pbmdQcmVmZXJlbmNlczo6UGVyZk92ZXJsYXlQb3Np
dGlvbiBhcyBhbiBpbnQKICAgICAvLyAoMD1UTCwgMT1UUiwgMj1CTCwgMz1CUikuIFJlbmRlcmVy
cyBtYXAgdGhpcyB0byB0aGVpciBvd24gY29vcmRpbmF0ZSBzcGFjZS4KICAgICBpbnQgZ2V0RGVi
dWdPdmVybGF5QW5jaG9yKCk7CisgICAgaW50IGdldE92ZXJsYXlBbmNob3IoT3ZlcmxheVR5cGUg
dHlwZSk7CiAKICAgICB2b2lkIHNldE92ZXJsYXlSZW5kZXJlcihJT3ZlcmxheVJlbmRlcmVyKiBy
ZW5kZXJlcik7CiAKQEAgLTExNyw2ICsxMjAsOCBAQCBwcml2YXRlOgogICAgIElPdmVybGF5UmVu
ZGVyZXIqIG1fUmVuZGVyZXI7CiAgICAgUU11dGV4IG1fUmVuZGVyZXJMb2NrOyAgIC8vIGd1YXJk
cyBtX1JlbmRlcmVyIHN3YXAgdnMgY3Jvc3MtdGhyZWFkIG5vdGlmeQogICAgIFFCeXRlQXJyYXkg
bV9Gb250RGF0YTsKKyAgICBRTXV0ZXggbV9HcmFwaExvY2s7CisgICAgQ3JpbXNvbkdyYXBoczo6
SGlzdG9yeSBtX0dyYXBoSGlzdG9yeVtPdmVybGF5TWF4XTsKIH07CiAKIH0KZGlmZiAtLWdpdCBh
L3BhY2thZ2luZy9mbGF0cGFrL2lvLmdpdGh1Yi5uYXZ5YXMzMjEuVmliZW1pcy5kZXNrdG9wIGIv
cGFja2FnaW5nL2ZsYXRwYWsvaW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AKaW5k
ZXggMDQ1YWRiZS4uZjEyZGE1ZCAxMDA2NDQKLS0tIGEvcGFja2FnaW5nL2ZsYXRwYWsvaW8uZ2l0
aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AKKysrIGIvcGFja2FnaW5nL2ZsYXRwYWsvaW8u
Z2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AKQEAgLTEsNiArMSw2IEBACiBbRGVza3Rv
cCBFbnRyeV0KIFR5cGU9QXBwbGljYXRpb24KLU5hbWU9VmliZW1pcworTmFtZT1FY2xpcHNlCiBH
ZW5lcmljTmFtZT1HYW1lIFN0cmVhbWluZyBDbGllbnQKIENvbW1lbnQ9U3RyZWFtIGdhbWVzIGFu
ZCBhcHBsaWNhdGlvbnMgZnJvbSBhIFN1bnNoaW5lIC8gQXBvbGxvIC8gVmliZXBvbGxvIGhvc3QK
IEV4ZWM9dmliZW1pcwo=
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
