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
VIBEMIS_PATCH_SHA256=a7a667113fd818d19ec2f5ae76a94825fe08479ef3b8987261d5577e55dd71b2
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
dG9yLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi4xNzg3ZDAxCi0tLSAv
ZGV2L251bGwKKysrIGIvYXBwL2d1aS9FY2xpcHNlSGFyZHdhcmVNb25pdG9yLnFtbApAQCAtMCww
ICsxLDc3IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIu
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
YW5nZWQoKSB7IGdyYXBoLnJlcXVlc3RQYWludCgpIH0gfQorICAgICAgICBDb25uZWN0aW9ucyB7
IHRhcmdldDogVmJUb2tlbnM7IGZ1bmN0aW9uIG9uQWNjZW50Q2hhbmdlZCgpIHsgZ3JhcGgucmVx
dWVzdFBhaW50KCkgfSB9CisgICAgfQorICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tl
bnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OiBxc1Ry
KCJTaG93IGxvY2FsIGhhcmR3YXJlIG92ZXJsYXkgZHVyaW5nIHN0cmVhbWluZyIpOyBjaGVja2Vk
OiBMb2NhbEhhcmR3YXJlLm92ZXJsYXk7IG9uVG9nZ2xlZDogTG9jYWxIYXJkd2FyZS5vdmVybGF5
PWNoZWNrZWQgfQorICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7
IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OiBxc1RyKCJEZXRhaWxlZCBs
b2NhbCBvdmVybGF5Iik7IGNoZWNrZWQ6IExvY2FsSGFyZHdhcmUuZGV0YWlsZWQ7IG9uVG9nZ2xl
ZDogTG9jYWxIYXJkd2FyZS5kZXRhaWxlZD1jaGVja2VkIH0KKyAgICBDaGVja0JveCB7IGZvbnQu
ZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9k
eTsgdGV4dDogcXNUcigiRGV0YWlsZWQgc3RyZWFtIHN0YXRpc3RpY3MiKTsgY2hlY2tlZDogTG9j
YWxIYXJkd2FyZS5zdHJlYW1EZXRhaWxlZDsgb25Ub2dnbGVkOiBMb2NhbEhhcmR3YXJlLnN0cmVh
bURldGFpbGVkPWNoZWNrZWQgfQorICAgIFJvd0xheW91dCB7CisgICAgICAgIExhYmVsIHsgZm9u
dC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVC
b2R5OyB0ZXh0OiBxc1RyKCJMb2NhbCBvdmVybGF5IGNvcm5lciIpOyBjb2xvcjogVmJUb2tlbnMu
dGV4dCB9CisgICAgICAgIEVjbGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsg
bW9kZWw6W3FzVHIoIlRvcCBsZWZ0IikscXNUcigiVG9wIHJpZ2h0IikscXNUcigiQm90dG9tIGxl
ZnQiKSxxc1RyKCJCb3R0b20gcmlnaHQiKV07IGN1cnJlbnRJbmRleDpMb2NhbEhhcmR3YXJlLnBv
c2l0aW9uOyBvbkFjdGl2YXRlZDpMb2NhbEhhcmR3YXJlLnBvc2l0aW9uPWluZGV4IH0KKyAgICB9
CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNp
emU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgd3JhcE1vZGU6VGV4
dC5XcmFwOyB0ZXh0OnFzVHIoIklmIGJvdGggb3ZlcmxheXMgdXNlIHRoZSBzYW1lIGNvcm5lciwg
TG9jYWwgTWFjIG1vdmVzIHRvIHRoZSBvcHBvc2l0ZSBob3Jpem9udGFsIGNvcm5lci4gU3RyZWFt
aW5nIHNob3J0Y3V0czogQ3RybCtBbHQrU2hpZnQrUyBmb3Igc3RyZWFtIHN0YXRzOyBDdHJsK0Fs
dCtTaGlmdCtIIGZvciBsb2NhbCBoYXJkd2FyZS4gU3RyZWFtIHRleHQgc2l6ZSBhbmQgY29ybmVy
IHJlbWFpbiBpbiBWaWRlbyBzZXR0aW5ncy4iKTsgY29sb3I6VmJUb2tlbnMudGV4dERpbSB9Cisg
ICAgUm93TGF5b3V0IHsKKyAgICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250
Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiUGFuZWwg
b3BhY2l0eSIpOyBjb2xvcjpWYlRva2Vucy50ZXh0IH0KKyAgICAgICAgU2xpZGVyIHsgTGF5b3V0
LmZpbGxXaWR0aDp0cnVlOyBmcm9tOjQwO3RvOjEwMDtzdGVwU2l6ZTo1O3ZhbHVlOkxvY2FsSGFy
ZHdhcmUub3BhY2l0eTsgb25Nb3ZlZDpMb2NhbEhhcmR3YXJlLm9wYWNpdHk9TWF0aC5yb3VuZCh2
YWx1ZSkgfQorICAgIH0KKyAgICBSb3dMYXlvdXQgeworICAgICAgICBMYWJlbCB7IGZvbnQuZmFt
aWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsg
dGV4dDpxc1RyKCJSZWZyZXNoIGludGVydmFsIik7Y29sb3I6VmJUb2tlbnMudGV4dCB9CisgICAg
ICAgIEVjbGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgbW9kZWw6WyIxIHNl
Y29uZCIsIjIgc2Vjb25kcyIsIjUgc2Vjb25kcyJdOyBjdXJyZW50SW5kZXg6TG9jYWxIYXJkd2Fy
ZS5yZWZyZXNoU2Vjb25kcz09PTE/MDpMb2NhbEhhcmR3YXJlLnJlZnJlc2hTZWNvbmRzPT09NT8y
OjE7IG9uQWN0aXZhdGVkOkxvY2FsSGFyZHdhcmUucmVmcmVzaFNlY29uZHM9WzEsMiw1XVtpbmRl
eF0gfQorICAgIH0KKyAgICBGbG93IHsKKyAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDp0cnVlCisg
ICAgICAgIFJlcGVhdGVyIHsgbW9kZWw6WyJjcHUiLCJtZW1vcnkiLCJ0ZW1wZXJhdHVyZSIsImdw
dSIsIm5ldHdvcmsiLCJiYXR0ZXJ5Iiwic3RvcmFnZSJdCisgICAgICAgICAgICBkZWxlZ2F0ZTpD
aGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpW
YlRva2Vucy50eXBlQm9keTsgdGV4dDptb2RlbERhdGE7IGNoZWNrZWQ6TG9jYWxIYXJkd2FyZS5m
aWVsZHMuaW5kZXhPZihtb2RlbERhdGEpPj0wOyBvblRvZ2dsZWQ6e3ZhciBmPUxvY2FsSGFyZHdh
cmUuZmllbGRzLnNsaWNlKCk7dmFyIGk9Zi5pbmRleE9mKG1vZGVsRGF0YSk7aWYoY2hlY2tlZCYm
aTwwKWYucHVzaChtb2RlbERhdGEpO2lmKCFjaGVja2VkJiZpPj0wKWYuc3BsaWNlKGksMSk7TG9j
YWxIYXJkd2FyZS5maWVsZHM9Zn0gfQorICAgICAgICB9CisgICAgfQorICAgIExhYmVsIHsgZm9u
dC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVC
b2R5OyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5XcmFwO3RleHQ6cXNUcigi
RWNsaXBzZSB2aWRlby1lbmdpbmUgYWN0aXZpdHkgdXNlcyB0aGlzIHByb2Nlc3PigJlzIERSTSBj
b3VudGVycyB3aGVuIGV4cG9zZWQuIEl0IGlzIG5vdCB3aG9sZS1zeXN0ZW0gR1BVIGxvYWQuIFBl
ci1wcm9jZXNzIEdQVSBtZW1vcnkgaXMgdW5hdmFpbGFibGUuIFN0b3JhZ2UgcmF0ZXMgcmVmbGVj
dCB0aGUgYWN0aXZlIHJvb3QgZGV2aWNlIHdoZW4gYWNjZXNzaWJsZS4gTm8gcHJpdmlsZWdlZCBH
UFUgcHJvZmlsZXIgcnVucyBjb250aW51b3VzbHkuIik7Y29sb3I6VmJUb2tlbnMudGV4dERpbSB9
Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0VjbGlwc2VTeXN0ZW1TZXR0aW5ncy5xbWwgYi9hcHAv
Z3VpL0VjbGlwc2VTeXN0ZW1TZXR0aW5ncy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXgg
MDAwMDAwMC4uNWQyYmJjOQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNsaXBzZVN5c3Rl
bVNldHRpbmdzLnFtbApAQCAtMCwwICsxLDgzIEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9y
dCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9y
dCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24g
MS4wCitpbXBvcnQgU3lzdGVtQ29udHJvbHMgMS4wCitpbXBvcnQgTG9jYWxIYXJkd2FyZSAxLjAK
KworQ29sdW1uTGF5b3V0IHsKKyAgICBpZDogc3lzdGVtCisgICAgcHJvcGVydHkgYm9vbCBhY3Rp
dmU6IGZhbHNlCisgICAgcHJvcGVydHkgc3RyaW5nIHBvd2VyQWN0aW9uOiAiIgorICAgIHByb3Bl
cnR5IHZhciBwb2ludGVyOiBwb2ludGVyQ2hvaWNlLmN1cnJlbnRJbmRleCA+PSAwID8gKFN5c3Rl
bUNvbnRyb2xzLnN0YXRlLnBvaW50ZXJzIHx8IFtdKVtwb2ludGVyQ2hvaWNlLmN1cnJlbnRJbmRl
eF0gfHwgKHt9KSA6ICh7fSkKKyAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICBvbkFj
dGl2ZUNoYW5nZWQ6IHsgaWYoYWN0aXZlKSBTeXN0ZW1Db250cm9scy5vcGVuKCJjZW50ZXIiKTsg
ZWxzZSBTeXN0ZW1Db250cm9scy5jbG9zZSgpIH0KKyAgICBDb21wb25lbnQub25EZXN0cnVjdGlv
bjogeyBpZihhY3RpdmUpIFN5c3RlbUNvbnRyb2xzLmNsb3NlKCkgfQorICAgIGZ1bmN0aW9uIHJl
cXVlc3QoYWN0aW9uLHZhbHVlKSB7IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci0iK2Fj
dGlvbix2YWx1ZSB8fCAiIikgfQorICAgIGZ1bmN0aW9uIHNob3dDb25uZWN0aW9ucyhraW5kKSB7
IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCk7IGNvbm5lY3Rpb25zLmtpbmQ9a2luZDsgY29ubmVjdGlv
bnMub3BlbigpIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBm
b250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dy
YXBNb2RlOlRleHQuV3JhcDt0ZXh0OnFzVHIoIkVjbGlwc2VPUyDigKIgU3lzdGVtIENvbnRyb2xz
Iik7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LmJvbGQ6dHJ1ZSB9CisgICAgTGFiZWwgeyBmb250
LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJv
ZHk7IExheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7dGV4dDpTeXN0ZW1D
b250cm9scy5zdGF0dXM7Y29sb3I6VmJUb2tlbnMudGV4dERpbTt0ZXh0Rm9ybWF0OlRleHQuUGxh
aW5UZXh0IH0KKyAgICBCdXN5SW5kaWNhdG9yIHsgcnVubmluZzpzeXN0ZW0uYWN0aXZlICYmIFN5
c3RlbUNvbnRyb2xzLmJ1c3k7dmlzaWJsZTpydW5uaW5nO0xheW91dC5hbGlnbm1lbnQ6UXQuQWxp
Z25IQ2VudGVyIH0KKyAgICBSb3dMYXlvdXQgeworICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOnRy
dWUKKyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiV2ktRmkgbmV0d29y
a3MiKTtpY29uU291cmNlOiJxcmM6L3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnIjtvbkNsaWNrZWQ6
c3lzdGVtLnNob3dDb25uZWN0aW9ucygid2lmaSIpIH0KKyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1
dHRvbiB7IHRleHQ6cXNUcigiQmx1ZXRvb3RoIGRldmljZXMiKTtpY29uU291cmNlOiJxcmM6L3Jl
cy9jcmltc29uLWJsdWV0b290aC5zdmciO29uQ2xpY2tlZDpzeXN0ZW0uc2hvd0Nvbm5lY3Rpb25z
KCJidCIpIH0KKyAgICB9CisgICAgUm93TGF5b3V0IHsKKyAgICAgICAgQ2hlY2tCb3ggeyBmb250
LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJv
ZHk7IHRleHQ6cXNUcigiV2ktRmkgcmFkaW8iKTtjaGVja2VkOlN5c3RlbUNvbnRyb2xzLnN0YXRl
LndpZmlfZW5hYmxlZD09PXRydWU7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBTeXN0
ZW1Db250cm9scy5zdGF0ZS53aWZpX2VuYWJsZWQhPT1udWxsICYmIFN5c3RlbUNvbnRyb2xzLnN0
YXRlLndpZmlfZW5hYmxlZCE9PXVuZGVmaW5lZDtvblRvZ2dsZWQ6c3lzdGVtLnJlcXVlc3QoIndp
ZmktcmFkaW8iLGNoZWNrZWQ/Im9uIjoib2ZmIikgfQorICAgICAgICBDaGVja0JveCB7IGZvbnQu
ZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9k
eTsgdGV4dDpxc1RyKCJCbHVldG9vdGggcmFkaW8iKTtjaGVja2VkOlN5c3RlbUNvbnRyb2xzLnN0
YXRlLmJsdWV0b290aF9lbmFibGVkPT09dHJ1ZTtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5
ICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLmJsdWV0b290aF9lbmFibGVkIT09bnVsbCAmJiBTeXN0
ZW1Db250cm9scy5zdGF0ZS5ibHVldG9vdGhfZW5hYmxlZCE9PXVuZGVmaW5lZDtvblRvZ2dsZWQ6
c3lzdGVtLnJlcXVlc3QoImJ0LXJhZGlvIixjaGVja2VkPyJvbiI6Im9mZiIpIH0KKyAgICB9Cisg
ICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6
VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiQXVkaW8gYW5kIGJyaWdodG5lc3MiKTtjb2xv
cjpWYlRva2Vucy50ZXh0O2ZvbnQuYm9sZDp0cnVlIH0KKyAgICBSb3dMYXlvdXQgeworICAgICAg
ICBMYXlvdXQuZmlsbFdpZHRoOnRydWUKKyAgICAgICAgU2xpZGVyIHsgaWQ6dm9sdW1lO0xheW91
dC5maWxsV2lkdGg6dHJ1ZTtmcm9tOjA7dG86MTAwO3N0ZXBTaXplOjE7dmFsdWU6U3lzdGVtQ29u
dHJvbHMuc3RhdGUudm9sdW1lIHx8IDA7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBT
eXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUhPT1udWxsICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRl
LnZvbHVtZSE9PXVuZGVmaW5lZDtBY2Nlc3NpYmxlLm5hbWU6cXNUcigiU3BlYWtlciB2b2x1bWUi
KTtvblByZXNzZWRDaGFuZ2VkOmlmKCFwcmVzc2VkJiZlbmFibGVkKXN5c3RlbS5yZXF1ZXN0KCJ2
b2x1bWUiLFN0cmluZyhNYXRoLnJvdW5kKHZhbHVlKSkpO29uTW92ZWQ6aWYoIXByZXNzZWQmJmVu
YWJsZWQpc3lzdGVtLnJlcXVlc3QoInZvbHVtZSIsU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSkg
fQorICAgICAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBp
eGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDpNYXRoLnJvdW5kKHZvbHVtZS52YWx1ZSkr
IiUiO2NvbG9yOlZiVG9rZW5zLnRleHQgfQorICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsg
dGV4dDpTeXN0ZW1Db250cm9scy5zdGF0ZS5tdXRlZD9xc1RyKCJVbm11dGUiKTpxc1RyKCJNdXRl
Iik7ZW5hYmxlZDp2b2x1bWUuZW5hYmxlZDtvbkNsaWNrZWQ6c3lzdGVtLnJlcXVlc3QoIm11dGUi
KSB9CisgICAgfQorICAgIEVjbGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTtt
b2RlbDpTeXN0ZW1Db250cm9scy5zdGF0ZS5zaW5rcyB8fCBbXTt0ZXh0Um9sZToibmFtZSI7ZW5h
YmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBjb3VudD4wO0FjY2Vzc2libGUubmFtZTpxc1Ry
KCJBdWRpbyBvdXRwdXQiKTtjdXJyZW50SW5kZXg6e3ZhciBhPVN5c3RlbUNvbnRyb2xzLnN0YXRl
LnNpbmtzIHx8IFtdO2Zvcih2YXIgaT0wO2k8YS5sZW5ndGg7aSsrKWlmKGFbaV0uZGVmYXVsdCly
ZXR1cm4gaTtyZXR1cm4gLTF9CisgICAgICAgIG9uQWN0aXZhdGVkOnN5c3RlbS5yZXF1ZXN0KCJv
dXRwdXQiLG1vZGVsW2luZGV4XS5pZCkgfQorICAgIFJvd0xheW91dCB7CisgICAgICAgIEVjbGlw
c2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIlRlc3Qgc291bmQiKTtlbmFibGVkOnZvbHVtZS5l
bmFibGVkO29uQ2xpY2tlZDpzeXN0ZW0ucmVxdWVzdCgidGVzdC1zb3VuZCIpIH0KKyAgICAgICAg
RWNsaXBzZUNvbWJvQm94IHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlOyBtb2RlbDpbcXNUcigiQWly
UG9kczogTG93IGxhdGVuY3kiKSxxc1RyKCJBaXJQb2RzOiBRdWFsaXR5IildO2VuYWJsZWQ6IVN5
c3RlbUNvbnRyb2xzLmJ1c3k7b25BY3RpdmF0ZWQ6c3lzdGVtLnJlcXVlc3QoImFpcnBvZHMiLGlu
ZGV4PT09MD8ibG93LWxhdGVuY3kiOiJxdWFsaXR5IikgfQorICAgIH0KKyAgICBSZXBlYXRlciB7
CisgICAgICAgIG1vZGVsOlt7a2luZDoic2NyZWVuIixsYWJlbDpxc1RyKCJTY3JlZW4gYnJpZ2h0
bmVzcyIpfSx7a2luZDoia2V5Ym9hcmQiLGxhYmVsOnFzVHIoIktleWJvYXJkIGxpZ2h0aW5nIil9
XQorICAgICAgICBkZWxlZ2F0ZTpDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgTGF5b3V0LmZp
bGxXaWR0aDp0cnVlCisgICAgICAgICAgICBwcm9wZXJ0eSB2YXIgaGFyZHdhcmU6KFN5c3RlbUNv
bnRyb2xzLnN0YXRlLmJyaWdodG5lc3MgfHwge30pW21vZGVsRGF0YS5raW5kXQorICAgICAgICAg
ICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6
VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6bW9kZWxEYXRhLmxhYmVsKyhoYXJkd2FyZT8iIOKAoiAi
K2hhcmR3YXJlLnBlcmNlbnQrIiUiOiIg4oCiICIrcXNUcigiVW5hdmFpbGFibGUiKSk7Y29sb3I6
VmJUb2tlbnMudGV4dCB9CisgICAgICAgICAgICBTbGlkZXIgeyBMYXlvdXQuZmlsbFdpZHRoOnRy
dWU7ZnJvbTptb2RlbERhdGEua2luZD09PSJzY3JlZW4iPzU6MDt0bzoxMDA7c3RlcFNpemU6MTtl
bmFibGVkOiEhaGFyZHdhcmUmJiFTeXN0ZW1Db250cm9scy5idXN5O3ZhbHVlOmhhcmR3YXJlP2hh
cmR3YXJlLnBlcmNlbnQ6MDtBY2Nlc3NpYmxlLm5hbWU6bW9kZWxEYXRhLmxhYmVsO29uUHJlc3Nl
ZENoYW5nZWQ6aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3QobW9kZWxEYXRhLmtp
bmQsU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSk7b25Nb3ZlZDppZighcHJlc3NlZCYmZW5hYmxl
ZClzeXN0ZW0ucmVxdWVzdChtb2RlbERhdGEua2luZCxTdHJpbmcoTWF0aC5yb3VuZCh2YWx1ZSkp
KSB9CisgICAgICAgIH0KKyAgICB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5m
b250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiRGlz
cGxheSBhbmQgaWRsZSBibGFua2luZyIpO2NvbG9yOlZiVG9rZW5zLnRleHQ7Zm9udC5ib2xkOnRy
dWUgfQorICAgIEVjbGlwc2VDb21ib0JveCB7IGlkOm1vZGVDaG9pY2U7TGF5b3V0LmZpbGxXaWR0
aDp0cnVlO21vZGVsOlN5c3RlbUNvbnRyb2xzLnN0YXRlLmRpc3BsYXlzIHx8IFtdO3RleHRSb2xl
OiJuYW1lIjtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5ICYmIGNvdW50PjA7QWNjZXNzaWJs
ZS5uYW1lOnFzVHIoIkRpc3BsYXkgcmVzb2x1dGlvbiBhbmQgcmVmcmVzaCByYXRlIik7Y3VycmVu
dEluZGV4Ont2YXIgYT1TeXN0ZW1Db250cm9scy5zdGF0ZS5kaXNwbGF5cyB8fCBbXTtmb3IodmFy
IGk9MDtpPGEubGVuZ3RoO2krKylpZihhW2ldLmN1cnJlbnQpcmV0dXJuIGk7cmV0dXJuIC0xfSB9
CisgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiQXBwbHkgZGlzcGxheSBtb2Rl
IOKAoiAxNS1zZWNvbmQgcm9sbGJhY2siKTtlbmFibGVkOm1vZGVDaG9pY2UuZW5hYmxlZCYmbW9k
ZUNob2ljZS5jdXJyZW50SW5kZXg+PTA7b25DbGlja2VkOnN5c3RlbS5yZXF1ZXN0KCJkaXNwbGF5
Iixtb2RlQ2hvaWNlLm1vZGVsW21vZGVDaG9pY2UuY3VycmVudEluZGV4XS5pZCkgfQorICAgIEVj
bGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgbW9kZWw6W3FzVHIoIk5ldmVy
IGJsYW5rIikscXNUcigiQmxhbmsgYWZ0ZXIgNSBtaW51dGVzIikscXNUcigiQmxhbmsgYWZ0ZXIg
MTAgbWludXRlcyIpLHFzVHIoIkJsYW5rIGFmdGVyIDMwIG1pbnV0ZXMiKV07ZW5hYmxlZDohU3lz
dGVtQ29udHJvbHMuYnVzeTtvbkFjdGl2YXRlZDpzeXN0ZW0ucmVxdWVzdCgiaWRsZSIsWyIwIiwi
MzAwIiwiNjAwIiwiMTgwMCJdW2luZGV4XSkgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJU
b2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFz
VHIoIlBvaW50ZXIgYW5kIHRyYWNrcGFkIik7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LmJvbGQ6
dHJ1ZSB9CisgICAgRWNsaXBzZUNvbWJvQm94IHsgaWQ6cG9pbnRlckNob2ljZTtMYXlvdXQuZmls
bFdpZHRoOnRydWU7bW9kZWw6U3lzdGVtQ29udHJvbHMuc3RhdGUucG9pbnRlcnMgfHwgW107dGV4
dFJvbGU6Im5hbWUiO2VuYWJsZWQ6Y291bnQ+MCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7QWNjZXNz
aWJsZS5uYW1lOnFzVHIoIlBvaW50ZXIgZGV2aWNlIikgfQorICAgIFNsaWRlciB7IExheW91dC5m
aWxsV2lkdGg6dHJ1ZTtmcm9tOi0xO3RvOjE7c3RlcFNpemU6LjA1O3ZhbHVlOnN5c3RlbS5wb2lu
dGVyLnNwZWVkIHx8IDA7ZW5hYmxlZDpzeXN0ZW0ucG9pbnRlci5zcGVlZCE9PXVuZGVmaW5lZCYm
IVN5c3RlbUNvbnRyb2xzLmJ1c3k7QWNjZXNzaWJsZS5uYW1lOnFzVHIoIlBvaW50ZXIgYWNjZWxl
cmF0aW9uIHNwZWVkIik7b25QcmVzc2VkQ2hhbmdlZDppZighcHJlc3NlZCYmZW5hYmxlZClzeXN0
ZW0ucmVxdWVzdCgicG9pbnRlci1zcGVlZCIsc3lzdGVtLnBvaW50ZXIuaWQrIjoiK3ZhbHVlLnRv
Rml4ZWQoMikpO29uTW92ZWQ6aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3QoInBv
aW50ZXItc3BlZWQiLHN5c3RlbS5wb2ludGVyLmlkKyI6Iit2YWx1ZS50b0ZpeGVkKDIpKSB9Cisg
ICAgQ2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNp
emU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiTmF0dXJhbCBzY3JvbGxpbmciKTtjaGVj
a2VkOnN5c3RlbS5wb2ludGVyLm5hdHVyYWw9PT0xO2VuYWJsZWQ6c3lzdGVtLnBvaW50ZXIubmF0
dXJhbCE9PXVuZGVmaW5lZCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25Ub2dnbGVkOnN5c3RlbS5y
ZXF1ZXN0KCJwb2ludGVyLW5hdHVyYWwiLHN5c3RlbS5wb2ludGVyLmlkKyI6IisoY2hlY2tlZD8i
MSI6IjAiKSkgfQorICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7
IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIlRhcCB0byBjbGlj
ayIpO2NoZWNrZWQ6c3lzdGVtLnBvaW50ZXIudGFwPT09MTtlbmFibGVkOnN5c3RlbS5wb2ludGVy
LnRhcCE9PXVuZGVmaW5lZCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25Ub2dnbGVkOnN5c3RlbS5y
ZXF1ZXN0KCJwb2ludGVyLXRhcCIsc3lzdGVtLnBvaW50ZXIuaWQrIjoiKyhjaGVja2VkPyIxIjoi
MCIpKSB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5w
aXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9k
ZTpUZXh0LldyYXA7dGV4dDpxc1RyKCJQb2ludGVyIGFuZCBibGFua2luZyBjaGFuZ2VzIGN1cnJl
bnRseSBhcHBseSB0byB0aGlzIFgxMSBzZXNzaW9uLiBVbnN1cHBvcnRlZCBkZXZpY2UgY29udHJv
bHMgYXJlIGRpc2FibGVkLiBEaXNwbGF5IGNoYW5nZXMgcmV2ZXJ0IHVubGVzcyBjb25maXJtZWQu
Iik7Y29sb3I6VmJUb2tlbnMudGV4dERpbSB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRv
a2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNU
cigiUmVjb3ZlcnkgYW5kIHBvd2VyIik7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LmJvbGQ6dHJ1
ZSB9CisgICAgRWNsaXBzZUNvbWJvQm94IHsgaWQ6ZnJvbnRlbmQ7bW9kZWw6WyJFY2xpcHNlIiwi
QXJ0ZW1pcyIsIlBlZ2FzdXMiLCJNb29ubGlnaHQiLCJDb2NvT1MiXTtBY2Nlc3NpYmxlLm5hbWU6
cXNUcigiRnJvbnRlbmQgZm9yIG5leHQgYm9vdCIpIH0KKyAgICBFY2xpcHNlQWN0aW9uQnV0dG9u
IHsgdGV4dDpxc1RyKCJTYXZlIGZyb250ZW5kIGZvciBuZXh0IGJvb3QiKTtlbmFibGVkOiFTeXN0
ZW1Db250cm9scy5idXN5O29uQ2xpY2tlZDpzeXN0ZW0ucmVxdWVzdCgiZnJvbnRlbmQiLFsidmli
ZW1pcyIsImFydGVtaXMiLCJwZWdhc3VzIiwibW9vbmxpZ2h0IiwiY29jb29zIl1bZnJvbnRlbmQu
Y3VycmVudEluZGV4XSkgfQorICAgIEZsb3cgeworICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOnRy
dWU7c3BhY2luZzpWYlRva2Vucy5zcGFjZTIKKyAgICAgICAgUmVwZWF0ZXIgeyBtb2RlbDpbe25h
bWU6cXNUcigiUmVzdGFydCBmcm9udGVuZCIpLGFjdGlvbjoicmVzdGFydC1mcm9udGVuZCJ9LHtu
YW1lOnFzVHIoIlJlc3RhcnQgRWNsaXBzZU9TIiksYWN0aW9uOiJyZWJvb3QifSx7bmFtZTpxc1Ry
KCJTaHV0IGRvd24iKSxhY3Rpb246InBvd2Vyb2ZmIn1dCisgICAgICAgICAgICBkZWxlZ2F0ZTpF
Y2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDptb2RlbERhdGEubmFtZTtpY29uU291cmNlOiJxcmM6
L3Jlcy9lY2xpcHNlLXBvd2VyLnN2ZyI7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeTtvbkNs
aWNrZWQ6e3N5c3RlbS5wb3dlckFjdGlvbj1tb2RlbERhdGEuYWN0aW9uO3Bvd2VyLm9wZW4oKX0g
fQorICAgICAgICB9CisgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIlJl
ZGFjdGVkIHN1cHBvcnQgcmVwb3J0Iik7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeTtvbkNs
aWNrZWQ6c3lzdGVtLnJlcXVlc3QoInJlcG9ydCIpIH0KKyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1
dHRvbiB7IHRleHQ6cXNUcigiUmVmcmVzaCBjb250cm9scyIpO2VuYWJsZWQ6IVN5c3RlbUNvbnRy
b2xzLmJ1c3k7b25DbGlja2VkOnN5c3RlbS5yZXF1ZXN0KCJsaXN0IikgfQorICAgIH0KKyAgICBM
YWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRv
a2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcDt0
ZXh0OnFzVHIoIlN1c3BlbmQgYW5kIGxpZCBwcmVzZXRzIGF3YWl0IHBoeXNpY2FsIHZhbGlkYXRp
b24uIFJlY292ZXJ5IGNvbnNvbGU6IENvbnRyb2wgKyBPcHRpb24gKyBGMiAoRm4gaWYgbmVlZGVk
KS4iKTtjb2xvcjpWYlRva2Vucy50ZXh0RGltIH0KKyAgICBFY2xpcHNlSGFyZHdhcmVNb25pdG9y
IHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO2FjdGl2ZTpzeXN0ZW0uYWN0aXZlIH0KKyAgICBTeXN0
ZW1Db25uZWN0aW9uc0RpYWxvZyB7IGlkOmNvbm5lY3Rpb25zO3BhcmVudDpPdmVybGF5Lm92ZXJs
YXk7b25DbG9zZWQ6aWYoc3lzdGVtLmFjdGl2ZSlyZXN1bWUucmVzdGFydCgpIH0KKyAgICBUaW1l
ciB7IGlkOnJlc3VtZTtpbnRlcnZhbDo2MDA7b25UcmlnZ2VyZWQ6aWYoc3lzdGVtLmFjdGl2ZSlT
eXN0ZW1Db250cm9scy5vcGVuKCJjZW50ZXIiKSB9CisgICAgTmF2aWdhYmxlRGlhbG9nIHsgaWQ6
cG93ZXI7cGFyZW50Ok92ZXJsYXkub3ZlcmxheTt3aWR0aDpNYXRoLm1pbig0NDAscGFyZW50Lndp
ZHRoLTMyKTt0aXRsZTpxc1RyKCJDb25maXJtIHN5c3RlbSBhY3Rpb24iKTtzdGFuZGFyZEJ1dHRv
bnM6RGlhbG9nLlllc3xEaWFsb2cuTm87YmFja2dyb3VuZDpSZWN0YW5nbGV7Y29sb3I6VmJUb2tl
bnMuYmdFbGV2O3JhZGl1czpWYlRva2Vucy5yYWRpdXNEaWFsb2c7Ym9yZGVyLmNvbG9yOlZiVG9r
ZW5zLnN0cm9rZX0KKyAgICAgICAgb25BY2NlcHRlZDpTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJj
ZW50ZXItIitzeXN0ZW0ucG93ZXJBY3Rpb24sIiIsdHJ1ZSk7Y29udGVudEl0ZW06TGFiZWx7d3Jh
cE1vZGU6VGV4dC5XcmFwO3RleHQ6cXNUcigiUHJvY2VlZCB3aXRoICUxPyBBY3RpdmUgc3RyZWFt
aW5nIHdpbGwgZW5kLiIpLmFyZyhzeXN0ZW0ucG93ZXJBY3Rpb24pO2NvbG9yOlZiVG9rZW5zLnRl
eHR9IH0KKyAgICBOYXZpZ2FibGVEaWFsb2cgeyBpZDpjb25maXJtYXRpb247cGFyZW50Ok92ZXJs
YXkub3ZlcmxheTt3aWR0aDpNYXRoLm1pbig0ODAscGFyZW50LndpZHRoLTMyKTt0aXRsZTpxc1Ry
KCJLZWVwIGRpc3BsYXkgbW9kZT8iKTtzdGFuZGFyZEJ1dHRvbnM6RGlhbG9nLlllc3xEaWFsb2cu
Tm87Y2xvc2VQb2xpY3k6UG9wdXAuTm9BdXRvQ2xvc2U7YmFja2dyb3VuZDpSZWN0YW5nbGV7Y29s
b3I6VmJUb2tlbnMuYmdFbGV2O3JhZGl1czpWYlRva2Vucy5yYWRpdXNEaWFsb2c7Ym9yZGVyLmNv
bG9yOlZiVG9rZW5zLnN0cm9rZX0KKyAgICAgICAgb25BY2NlcHRlZDpTeXN0ZW1Db250cm9scy5h
bnN3ZXIoInllcyIpO29uUmVqZWN0ZWQ6U3lzdGVtQ29udHJvbHMuYW5zd2VyKCJubyIpO2NvbnRl
bnRJdGVtOkxhYmVse3dyYXBNb2RlOlRleHQuV3JhcDt0ZXh0OlN5c3RlbUNvbnRyb2xzLnByb21w
dDtjb2xvcjpWYlRva2Vucy50ZXh0fSB9CisgICAgQ29ubmVjdGlvbnMgeyB0YXJnZXQ6U3lzdGVt
Q29udHJvbHM7ZnVuY3Rpb24gb25DaGFuZ2VkKCl7aWYoc3lzdGVtLmFjdGl2ZSYmU3lzdGVtQ29u
dHJvbHMucHJvbXB0Lmxlbmd0aD4wJiYhY29ubmVjdGlvbnMub3BlbmVkKWNvbmZpcm1hdGlvbi5v
cGVuKCk7aWYoIVN5c3RlbUNvbnRyb2xzLmJ1c3kpY29uZmlybWF0aW9uLmNsb3NlKCl9IH0KK30K
ZGlmZiAtLWdpdCBhL2FwcC9ndWkvTmF2aWdhYmxlRGlhbG9nLnFtbCBiL2FwcC9ndWkvTmF2aWdh
YmxlRGlhbG9nLnFtbAppbmRleCA0Mzg0ZDViLi5jMDZkZGYzIDEwMDY0NAotLS0gYS9hcHAvZ3Vp
L05hdmlnYWJsZURpYWxvZy5xbWwKKysrIGIvYXBwL2d1aS9OYXZpZ2FibGVEaWFsb2cucW1sCkBA
IC0xLDcgKzEsMzMgQEAKIGltcG9ydCBRdFF1aWNrIDIuMAogaW1wb3J0IFF0UXVpY2suQ29udHJv
bHMgMi41CitpbXBvcnQgUXRRdWljay5Db250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9ydCBWaWJl
bWlzLlJlZGVzaWduIDEuMAogCiBEaWFsb2cgeworICAgIGlkOiBkaWFsb2cKKyAgICBmb250LmZh
bWlseTogVmJUb2tlbnMuZm9udEJvZHkKKyAgICBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlw
ZUJvZHkKKyAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICBNYXRl
cmlhbC5mb3JlZ3JvdW5kOiBWYlRva2Vucy50ZXh0CisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRv
a2Vucy5hY2NlbnQKKyAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgeyBjb2xvcjpWYlRva2Vucy5i
Z0VsZXY7IHJhZGl1czpWYlRva2Vucy5yYWRpdXNEaWFsb2c7IGJvcmRlci5jb2xvcjpWYlRva2Vu
cy5zdHJva2UgfQorICAgIGhlYWRlcjogTGFiZWwgeworICAgICAgICB2aXNpYmxlOiBkaWFsb2cu
dGl0bGUubGVuZ3RoID4gMAorICAgICAgICB0ZXh0OiBkaWFsb2cudGl0bGU7IHRleHRGb3JtYXQ6
IFRleHQuUGxhaW5UZXh0OyBjb2xvcjpWYlRva2Vucy50ZXh0CisgICAgICAgIGZvbnQuZmFtaWx5
OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgZm9u
dC5ib2xkOnRydWUKKyAgICAgICAgcGFkZGluZzpWYlRva2Vucy5zcGFjZTQ7IGVsaWRlOlRleHQu
RWxpZGVSaWdodAorICAgIH0KKyAgICBmb290ZXI6IERpYWxvZ0J1dHRvbkJveCB7CisgICAgICAg
IGJhY2tncm91bmQ6IEl0ZW0ge30KKyAgICAgICAgdmlzaWJsZTogZGlhbG9nLnN0YW5kYXJkQnV0
dG9ucyAhPT0gRGlhbG9nLk5vQnV0dG9uCisgICAgICAgIHN0YW5kYXJkQnV0dG9uczogZGlhbG9n
LnN0YW5kYXJkQnV0dG9ucworICAgICAgICBpbXBsaWNpdEhlaWdodDogdmlzaWJsZSA/IE1hdGgu
bWF4KDQ0LFZiVG9rZW5zLnR5cGVMYWJlbCsyMCkrMipWYlRva2Vucy5zcGFjZTMgOiAwCisgICAg
ICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMgorICAgICAgICBwYWRkaW5nOiBWYlRva2Vucy5z
cGFjZTMKKyAgICAgICAgZGVsZWdhdGU6IEVjbGlwc2VBY3Rpb25CdXR0b24ge30KKyAgICAgICAg
b25BY2NlcHRlZDogZGlhbG9nLmFjY2VwdCgpCisgICAgICAgIG9uUmVqZWN0ZWQ6IGRpYWxvZy5y
ZWplY3QoKQorICAgIH0KICAgICBtb2RhbDogdHJ1ZQogICAgIGFuY2hvcnMuY2VudGVySW46IE92
ZXJsYXkub3ZlcmxheQogCmRpZmYgLS1naXQgYS9hcHAvZ3VpL1BjVmlldy5xbWwgYi9hcHAvZ3Vp
L1BjVmlldy5xbWwKaW5kZXggZjBlNzM5YS4uZjRkMDEyYiAxMDA2NDQKLS0tIGEvYXBwL2d1aS9Q
Y1ZpZXcucW1sCisrKyBiL2FwcC9ndWkvUGNWaWV3LnFtbApAQCAtNDQ0LDcgKzQ0NCw3IEBAIENl
bnRlcmVkR3JpZFZpZXcgewogICAgICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogbW9kZWwu
b25saW5lICYmIG1vZGVsLnBhaXJlZCwKICAgICAgICAgICAgICAgICAgICAgICAgIHRyaWdnZXI6
IGZ1bmN0aW9uKCkgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHZhciBjb21wb25lbnQg
PSBRdC5jcmVhdGVDb21wb25lbnQoIkFwcFZpZXcucW1sIikKLSAgICAgICAgICAgICAgICAgICAg
ICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3LCB7
ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgIm9iamVjdE5hbWUiOiBtb2RlbC5uYW1lLCAic2hvd0hp
ZGRlbkdhbWVzIjogdHJ1ZSwgImhvc3RPbmxpbmUiOiBtb2RlbC5vbmxpbmUsICJob3N0VHlwZSI6
IG1vZGVsLmhvc3RUeXBlLCAiaG9zdFRyYW5zcG9ydCI6IG1vZGVsLnRyYW5zcG9ydH0pCisgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgdmFyIGFwcFZpZXcgPSBjb21wb25lbnQuY3JlYXRlT2Jq
ZWN0KHN0YWNrVmlldywgeyJjb21wdXRlckluZGV4IjogaW5kZXgsICJjcmltc29uSG9zdCI6IGNv
bXB1dGVyTW9kZWwuY3JpbXNvbkhvc3QoaW5kZXgpLCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUs
ICJzaG93SGlkZGVuR2FtZXMiOiB0cnVlLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhv
c3RUeXBlIjogbW9kZWwuaG9zdFR5cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0
fSkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdGFja1ZpZXcucHVzaChhcHBWaWV3KQog
ICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICB9LApAQCAtNTM1
LDcgKzUzNSw3IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgICAgICAgICAgICAgIGVsc2UgaWYg
KG1vZGVsLnBhaXJlZCkgewogICAgICAgICAgICAgICAgICAgICAvLyBnbyB0byBnYW1lIHZpZXcK
ICAgICAgICAgICAgICAgICAgICAgdmFyIGNvbXBvbmVudCA9IFF0LmNyZWF0ZUNvbXBvbmVudCgi
QXBwVmlldy5xbWwiKQotICAgICAgICAgICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVu
dC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgIm9iamVj
dE5hbWUiOiBtb2RlbC5uYW1lLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhvc3RUeXBl
IjogbW9kZWwuaG9zdFR5cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0fSkKKyAg
ICAgICAgICAgICAgICAgICAgdmFyIGFwcFZpZXcgPSBjb21wb25lbnQuY3JlYXRlT2JqZWN0KHN0
YWNrVmlldywgeyJjb21wdXRlckluZGV4IjogaW5kZXgsICJjcmltc29uSG9zdCI6IGNvbXB1dGVy
TW9kZWwuY3JpbXNvbkhvc3QoaW5kZXgpLCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUsICJob3N0
T25saW5lIjogbW9kZWwub25saW5lLCAiaG9zdFR5cGUiOiBtb2RlbC5ob3N0VHlwZSwgImhvc3RU
cmFuc3BvcnQiOiBtb2RlbC50cmFuc3BvcnR9KQogICAgICAgICAgICAgICAgICAgICBzdGFja1Zp
ZXcucHVzaChhcHBWaWV3KQogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICBlbHNl
IHsKZGlmZiAtLWdpdCBhL2FwcC9ndWkvUXVpY2tNZW51LnFtbCBiL2FwcC9ndWkvUXVpY2tNZW51
LnFtbAppbmRleCBiMDMzZDI2Li4wZDk3OTRkIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1F1aWNrTWVu
dS5xbWwKKysrIGIvYXBwL2d1aS9RdWlja01lbnUucW1sCkBAIC00NDksNyArNDQ5LDcgQEAgUmVj
dGFuZ2xlIHsKICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlF1aXQgZ2FtZSIpCiAgICAgICAgICAg
ICBpY29uOiAicG93ZXIiCiAgICAgICAgICAgICBhY3Rpb246ICJxdWl0IgotICAgICAgICAgICAg
ZGVzY3JpcHRpb246IHFzVHIoIlF1aXQgdGhlIGdhbWUgb24gdGhlIGhvc3QgYW5kIHJldHVybiB0
byBWaWJlbWlzIikKKyAgICAgICAgICAgIGRlc2NyaXB0aW9uOiBxc1RyKCJRdWl0IHRoZSBnYW1l
IG9uIHRoZSBob3N0IGFuZCByZXR1cm4gdG8gRWNsaXBzZSIpCiAgICAgICAgIH0KICAgICAgICAg
TGlzdEVsZW1lbnQgewogICAgICAgICAgICAgdGV4dDogcXNUcigiU2VydmVyIGNvbW1hbmRzIikK
ZGlmZiAtLWdpdCBhL2FwcC9ndWkvU2V0dGluZ3NWaWV3LnFtbCBiL2FwcC9ndWkvU2V0dGluZ3NW
aWV3LnFtbAppbmRleCA0OTRlMzViLi45MGJhM2M2IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1NldHRp
bmdzVmlldy5xbWwKKysrIGIvYXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sCkBAIC0zNDYsMTIgKzM0
NiwxMyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgeyBpY29uOiAiZ2FtZXBhZCIsICAg
bGFiZWw6IHFzVHIoIklucHV0ICYgZ2FtZXBhZCIpIH0sCiAgICAgICAgICAgICAgICAgICAgIHsg
aWNvbjogInN0cmVhbWluZyIsIGxhYmVsOiBxc1RyKCJTdHJlYW1pbmciKSB9LAogICAgICAgICAg
ICAgICAgICAgICB7IGljb246ICJhcHBzIiwgICAgICBsYWJlbDogcXNUcigiQXBwICYgVUkiKSB9
LAotICAgICAgICAgICAgICAgICAgICB7IGljb246ICJhZHZhbmNlZCIsICBsYWJlbDogcXNUcigi
QWR2YW5jZWQiKSB9CisgICAgICAgICAgICAgICAgICAgIHsgaWNvbjogImFkdmFuY2VkIiwgIGxh
YmVsOiBxc1RyKCJBZHZhbmNlZCIpIH0sCisgICAgICAgICAgICAgICAgICAgIHsgaWNvbjogImFk
dmFuY2VkIiwgbGFiZWw6IHFzVHIoIlN5c3RlbSBDb250cm9scyIpIH0KICAgICAgICAgICAgICAg
ICBdCiAgICAgICAgICAgICAgICAgZGVsZWdhdGU6IEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAg
ICAgIGlkOiBjYXRCdXR0b24KICAgICAgICAgICAgICAgICAgICAgd2lkdGg6IHNpZGViYXJDb2x1
bW4ud2lkdGgKLSAgICAgICAgICAgICAgICAgICAgaGVpZ2h0OiA1OAorICAgICAgICAgICAgICAg
ICAgICBoZWlnaHQ6IE1hdGgubWluKDU4LE1hdGgubWF4KDQ0LChzaWRlYmFyLmhlaWdodC02NC0o
c2lkZWJhclJlcGVhdGVyLmNvdW50LTEpKlZiVG9rZW5zLnNwYWNlMikvc2lkZWJhclJlcGVhdGVy
LmNvdW50KSkKICAgICAgICAgICAgICAgICAgICAgcGFkZGluZzogMAogICAgICAgICAgICAgICAg
ICAgICBsZWZ0UGFkZGluZzogVmJUb2tlbnMuc3BhY2U0CiAgICAgICAgICAgICAgICAgICAgIHJp
Z2h0UGFkZGluZzogVmJUb2tlbnMuc3BhY2U0CkBAIC01NzEsNiArNTcyLDEyIEBAIEl0ZW0gewog
ICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLnRleHQKICAgICAgICAgfQogCisgICAgICAgIEVj
bGlwc2VTeXN0ZW1TZXR0aW5ncyB7CisgICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoIC0g
KHBhcmVudC5sZWZ0UGFkZGluZyArIHBhcmVudC5yaWdodFBhZGRpbmcpCisgICAgICAgICAgICB2
aXNpYmxlOiBzZXR0aW5nc1BhZ2UuY2F0ZWdvcnkgPT09IDYKKyAgICAgICAgICAgIGFjdGl2ZTog
c2V0dGluZ3NQYWdlLnZpc2libGUgJiYgdmlzaWJsZQorICAgICAgICB9CisKICAgICAgICAgLy8g
LS0tLSBMaXZlIHN0cmVhbSBzdW1tYXJ5IGxpbmUgKHJlZGVzaWduKSwgcmVsb2NhdGVkIGhlcmUg
KHdhcyBpbnNpZGUgQmFzaWMKICAgICAgICAgLy8gU2V0dGluZ3MpIHNvIGl0IHNpdHMgZGlyZWN0
bHkgdW5kZXIgdGhlICJWaWRlbyIgdGl0bGUgbGlrZSB0aGUgZGVzaWduLgogICAgICAgICAvLyBO
dW1iZXJzIHJlbmRlciBpbiBhY2NlbnQ7IHRoZSByZXN0IHN0YXlzIGRpbS4gQ29udGVudC9iaW5k
aW5ncyB1bmNoYW5nZWQuCkBAIC0xNjgxLDcgKzE2ODgsNyBAQCBJdGVtIHsKICAgICAgICAgICAg
ICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlw
LnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3Zl
cmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiV2hlbiB0aGUgbmV0
d29yayBjYW4ndCBzdXN0YWluIHRoZSBjb25maWd1cmVkIGJpdHJhdGUgYW5kIHRoZSBzdHJlYW0g
Y29sbGFwc2VzLCBWaWJlbWlzIGF1dG9tYXRpY2FsbHkgcmVjb25uZWN0cyBhdCBhIGxvd2VyIGJp
dHJhdGUgdW50aWwgdGhlIHN0cmVhbSBpcyB1c2FibGUuIFlvdXIgc2F2ZWQgYml0cmF0ZSBzZXR0
aW5nIGlzIG5ldmVyIGNoYW5nZWQuIikKKyAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0
OiBxc1RyKCJXaGVuIHRoZSBuZXR3b3JrIGNhbid0IHN1c3RhaW4gdGhlIGNvbmZpZ3VyZWQgYml0
cmF0ZSBhbmQgdGhlIHN0cmVhbSBjb2xsYXBzZXMsIEVjbGlwc2UgYXV0b21hdGljYWxseSByZWNv
bm5lY3RzIGF0IGEgbG93ZXIgYml0cmF0ZSB1bnRpbCB0aGUgc3RyZWFtIGlzIHVzYWJsZS4gWW91
ciBzYXZlZCBiaXRyYXRlIHNldHRpbmcgaXMgbmV2ZXIgY2hhbmdlZC4iKQogICAgICAgICAgICAg
ICAgIH0KIAogICAgICAgICAgICAgICAgIC8vIFZpYmVtaXMgKHBlcmYgZ3VpZGFuY2UpOiBhZHZp
c2Ugd2hlbiB0aGUgYml0cmF0ZSBpcyBzZXQgd2VsbCBhYm92ZSB0aGUgcmVjb21tZW5kZWQKQEAg
LTI0ODIsNyArMjQ4OSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLmRl
bGF5OiAxMDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGltZW91dDogNTAwMAogICAg
ICAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKLSAgICAgICAgICAgICAg
ICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJJZiBhIHN0cmVhbSBlbmRzIHVuZXhwZWN0ZWRseSAo
YSBuZXR3b3JrIGJsaXAgb3IgdGhlIGhvc3Qgd2FraW5nKSwgVmliZW1pcyB3aWxsIHRyeSB0byBy
ZWNvbm5lY3QgYXV0b21hdGljYWxseS4iKQorICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRl
eHQ6IHFzVHIoIklmIGEgc3RyZWFtIGVuZHMgdW5leHBlY3RlZGx5IChhIG5ldHdvcmsgYmxpcCBv
ciB0aGUgaG9zdCB3YWtpbmcpLCBFY2xpcHNlIHdpbGwgdHJ5IHRvIHJlY29ubmVjdCBhdXRvbWF0
aWNhbGx5LiIpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgfQogICAgICAgICB9CkBA
IC0yNTQ2LDcgKzI1NTMsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICBzcGFjaW5nOiBWYlRv
a2Vucy5zcGFjZTMKIAogICAgICAgICAgICAgICAgIFZiU2VjdGlvbkhlYWRlciB7Ci0gICAgICAg
ICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMgU3RyZWFtaW5nIEVuaGFuY2VtZW50cyIp
CisgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkVjbGlwc2UgU3RyZWFtaW5nIEVuaGFu
Y2VtZW50cyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgTGFiZWwgewpA
QCAtMjc3Niw3ICsyNzgzLDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBWYlRvZ2dsZVJv
dyB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiBtdXRlT25Gb2N1c0xvc3NDaGVjawotICAgICAg
ICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJNdXRlIGF1ZGlvIHN0cmVhbSB3aGVuIFZpYmVtaXMg
aXMgbm90IHRoZSBhY3RpdmUgd2luZG93IikKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiTXV0ZSBhdWRpbyBzdHJlYW0gd2hlbiBFY2xpcHNlIGlzIG5vdCB0aGUgYWN0aXZlIHdpbmRv
dyIpCiAgICAgICAgICAgICAgICAgICAgIHZpc2libGU6IFN5c3RlbVByb3BlcnRpZXMuaGFzRGVz
a3RvcEVudmlyb25tZW50CiAgICAgICAgICAgICAgICAgICAgIGNoZWNrZWQ6IFN0cmVhbWluZ1By
ZWZlcmVuY2VzLm11dGVPbkZvY3VzTG9zcwogICAgICAgICAgICAgICAgICAgICBvbkNoZWNrZWRD
aGFuZ2VkOiB7CkBAIC0yNzg2LDcgKzI3OTMsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAg
ICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVv
dXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0g
ICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiTXV0ZXMgVmliZW1pcydzIGF1
ZGlvIHdoZW4geW91IEFsdCtUYWIgb3V0IG9mIHRoZSBzdHJlYW0gb3IgY2xpY2sgb24gYSBkaWZm
ZXJlbnQgd2luZG93LiIpCisgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigi
TXV0ZXMgRWNsaXBzZSdzIGF1ZGlvIHdoZW4geW91IEFsdCtUYWIgb3V0IG9mIHRoZSBzdHJlYW0g
b3IgY2xpY2sgb24gYSBkaWZmZXJlbnQgd2luZG93LiIpCiAgICAgICAgICAgICAgICAgfQogICAg
ICAgICAgICAgfQogICAgICAgICB9CkBAIC0yOTcxLDcgKzI5NzgsNyBAQCBJdGVtIHsKICAgICAg
ICAgICAgICAgICAgICAgICAgIGlmIChTdHJlYW1pbmdQcmVmZXJlbmNlcy5sYW5ndWFnZSAhPT0g
bmV3X2xhbmd1YWdlKSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgU3RyZWFtaW5nUHJl
ZmVyZW5jZXMubGFuZ3VhZ2UgPSBsYW5ndWFnZUxpc3RNb2RlbC5nZXQoY3VycmVudEluZGV4KS52
YWwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiAoIVN0cmVhbWluZ1ByZWZlcmVuY2Vz
LnJldHJhbnNsYXRlKCkpIHsKLSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRp
cC5zaG93KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQgVmliZW1pcyBmb3IgdGhpcyBjaGFuZ2UgdG8g
dGFrZSBlZmZlY3QiKSwgNTAwMCkKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVG9v
bFRpcC5zaG93KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQgRWNsaXBzZSBmb3IgdGhpcyBjaGFuZ2Ug
dG8gdGFrZSBlZmZlY3QiKSwgNTAwMCkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9CiAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgZWxzZSB7CiAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgIC8vIEZvcmNlIHRoZSBiYWNrIG9wZXJhdGlvbiB0byBwb3AgYW55IEFwcFZpZXcg
cGFnZXMgdGhhdCBleGlzdC4KQEAgLTMwNTUsMTQgKzMwNjIsMjYgQEAgSXRlbSB7CiAgICAgICAg
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
LDcgKzMxNjYsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAuZGVs
YXk6IDEwMDAKICAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGltZW91dDogNTAwMAog
ICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAg
ICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlNhdmUgYWxsIFZpYmVtaXMgc2V0
dGluZ3MgdG8gfi92aWJlbWlzLXNldHRpbmdzLmluaSBmb3IgYmFja3VwIG9yIHRvIGNvcHkgdG8g
YW5vdGhlciBkZXZpY2UuIikKKyAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDog
cXNUcigiU2F2ZSBhbGwgRWNsaXBzZSBzZXR0aW5ncyB0byB+L3ZpYmVtaXMtc2V0dGluZ3MuaW5p
IGZvciBiYWNrdXAgb3IgdG8gY29weSB0byBhbm90aGVyIGRldmljZS4iKQogICAgICAgICAgICAg
ICAgICAgICB9CiAKICAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsKQEAgLTM0MDIsNyArMzQy
MSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDEwMDAw
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
eCB7CkBAIC0zNjQzLDcgKzM2NjIsNyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgIFZiVG9n
Z2xlUm93IHsKICAgICAgICAgICAgICAgICAgICAgaWQ6IGJhY2tncm91bmRHYW1lcGFkQ2hlY2sK
LSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiUHJvY2VzcyBnYW1lcGFkIGlucHV0IHdo
ZW4gVmliZW1pcyBpcyBpbiB0aGUgYmFja2dyb3VuZCIpCisgICAgICAgICAgICAgICAgICAgIHRl
eHQ6IHFzVHIoIlByb2Nlc3MgZ2FtZXBhZCBpbnB1dCB3aGVuIEVjbGlwc2UgaXMgaW4gdGhlIGJh
Y2tncm91bmQiKQogICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBTeXN0ZW1Qcm9wZXJ0aWVz
Lmhhc0Rlc2t0b3BFbnZpcm9ubWVudAogICAgICAgICAgICAgICAgICAgICBjaGVja2VkOiBTdHJl
YW1pbmdQcmVmZXJlbmNlcy5iYWNrZ3JvdW5kR2FtZXBhZAogICAgICAgICAgICAgICAgICAgICBv
bkNoZWNrZWRDaGFuZ2VkOiB7CkBAIC0zNjUzLDcgKzM2NzIsNyBAQCBJdGVtIHsKICAgICAgICAg
ICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29s
VGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBo
b3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiQWxsb3dzIFZp
YmVtaXMgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0cyBldmVuIGlmIGl0J3Mgbm90IHRoZSBjdXJy
ZW50IHdpbmRvdyBpbiBmb2N1cyIpCisgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDog
cXNUcigiQWxsb3dzIEVjbGlwc2UgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0cyBldmVuIGlmIGl0
J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBmb2N1cyIpCiAgICAgICAgICAgICAgICAgfQog
CiAgICAgICAgICAgICAgICAgVmJUb2dnbGVSb3cgewpAQCAtMzcyNCw3ICszNzQzLDcgQEAgSXRl
bSB7CiAgICAgICAgICAgICAgICAgTGFiZWwgewogICAgICAgICAgICAgICAgICAgICB3aWR0aDog
cGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsVGl0bGUK
LSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiU29mdHdhcmUgdXBkYXRlcyIpCisgICAg
ICAgICAgICAgICAgICAgIHRleHQ6IEF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZCA/IHFzVHIo
IkVjbGlwc2VPUyB1cGRhdGVzIikgOiBxc1RyKCJTb2Z0d2FyZSB1cGRhdGVzIikKICAgICAgICAg
ICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVMYWJlbAogICAgICAgICAg
ICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKICAgICAgICAgICAgICAg
ICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtMzczMyw2ICszNzUyLDcgQEAgSXRlbSB7CiAK
ICAgICAgICAgICAgICAgICBBdXRvUmVzaXppbmdDb21ib0JveCB7CiAgICAgICAgICAgICAgICAg
ICAgIGlkOiB1cGRhdGVDaGFubmVsQ29tYm9Cb3gKKyAgICAgICAgICAgICAgICAgICAgdmlzaWJs
ZTogIUF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZAogICAgICAgICAgICAgICAgICAgICB0ZXh0
Um9sZTogInRleHQiCiAgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBMaXN0TW9kZWwgewogICAg
ICAgICAgICAgICAgICAgICAgICAgaWQ6IHVwZGF0ZUNoYW5uZWxMaXN0TW9kZWwKQEAgLTM3ODcs
NiArMzgwNyw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAvLyBpbnN0YWxsIGluIGZs
aWdodCBhdCBhIHRpbWUpLCBzbyBidXR0b25zIHN0YXkgZW5hYmxlZC4KICAgICAgICAgICAgICAg
ICAgICAgQnV0dG9uIHsKICAgICAgICAgICAgICAgICAgICAgICAgIGlkOiBjaGVja1VwZGF0ZXNC
dXR0b24KKyAgICAgICAgICAgICAgICAgICAgICAgIHZpc2libGU6ICFBdXRvVXBkYXRlQ2hlY2tl
ci5vc01hbmFnZWQKICAgICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkNoZWNrIGZv
ciB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogewogICAgICAg
ICAgICAgICAgICAgICAgICAgICAgIEF1dG9VcGRhdGVDaGVja2VyLmNoZWNrTm93KCkKQEAgLTM4
MDQsOCArMzgyNSw4IEBAIEl0ZW0gewogCiAgICAgICAgICAgICAgICAgICAgIEJ1dHRvbiB7CiAg
ICAgICAgICAgICAgICAgICAgICAgICBpZDogdmlld1JlbGVhc2VCdXR0b24KLSAgICAgICAgICAg
ICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpZXcgcmVsZWFzZSIpCi0gICAgICAgICAgICAgICAg
ICAgICAgICB2aXNpYmxlOiBBdXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2YWlsYWJsZQorICAgICAg
ICAgICAgICAgICAgICAgICAgdGV4dDogQXV0b1VwZGF0ZUNoZWNrZXIub3NNYW5hZ2VkID8gcXNU
cigiRWNsaXBzZU9TIHJlbGVhc2VzIikgOiBxc1RyKCJWaWV3IHJlbGVhc2UiKQorICAgICAgICAg
ICAgICAgICAgICAgICAgdmlzaWJsZTogKEF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZCB8fCBB
dXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2YWlsYWJsZSkKICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICYmIEF1dG9VcGRhdGVDaGVja2VyLnJlbGVhc2VVcmwgIT09ICIiCiAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAmJiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIK
ICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogewpAQCAtMzg0Miw3ICszODYzLDcg
QEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCiAKICAg
ICAgICAgICAgICAgICBWYlNlY3Rpb25IZWFkZXIgewotICAgICAgICAgICAgICAgICAgICB0ZXh0
OiBxc1RyKCJWaWJlbWlzIEZlYXR1cmVzIikKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiRWNsaXBzZSBGZWF0dXJlcyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAg
ICAgQ2xpcGJvYXJkU2V0dGluZ3MgewpAQCAtMzk0Nyw3ICszOTY4LDcgQEAgSXRlbSB7CiAgICAg
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
bmQgPyAiWFdheWxhbmQiIDogIldheWxhbmQiKSA6ICJYMTEiIH0sCkBAIC00MDEzLDcgKzQwMzQs
NyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgIExhYmVsIHsKICAgICAgICAgICAgICAgICAg
ICAgd2lkdGg6IHBhcmVudC53aWR0aAotICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJW
aWJlbWlzICUxIikuYXJnKFN5c3RlbVByb3BlcnRpZXMudmVyc2lvblN0cmluZykKKyAgICAgICAg
ICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSAlMSIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVz
LnZlcnNpb25TdHJpbmcpCiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRv
a2Vucy50eXBlQm9keQogICAgICAgICAgICAgICAgICAgICBmb250LmJvbGQ6IHRydWUKICAgICAg
ICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtNDA1OCw3ICs0MDc5LDcgQEAg
SXRlbSB7CiAKICAgICAgICAgICAgICAgICBMYWJlbCB7CiAgICAgICAgICAgICAgICAgICAgIHdp
ZHRoOiBwYXJlbnQud2lkdGgKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmliZW1p
cyBpcyB0aGUgTGludXgvU3RlYW1PUyBjbGllbnQgZm9yIEFwb2xsbyAmIFN1bnNoaW5lIGhvc3Rz
LiBUaGVzZSBvcGVuIGluIHlvdXIgYnJvd3Nlci4iKQorICAgICAgICAgICAgICAgICAgICB0ZXh0
OiBxc1RyKCJFY2xpcHNlIGlzIHRoZSBMaW51eC9TdGVhbU9TIGNsaWVudCBmb3IgQXBvbGxvICYg
U3Vuc2hpbmUgaG9zdHMuIFRoZXNlIG9wZW4gaW4geW91ciBicm93c2VyLiIpCiAgICAgICAgICAg
ICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQ2FwdGlvbgogICAgICAgICAg
ICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKICAgICAgICAgICAgICAg
ICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtNDA2Niw3ICs0MDg3LDcgQEAgSXRlbSB7CiAg
ICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgQnV0dG9uIHsKLSAgICAgICAgICAg
ICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBvbiBHaXRIdWIiKQorICAgICAgICAgICAgICAg
ICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIG9uIEdpdEh1YiIpCiAgICAgICAgICAgICAgICAgICAg
IG9uQ2xpY2tlZDogU3lzdGVtUHJvcGVydGllcy5vcGVuVXJsKCJodHRwczovL2dpdGh1Yi5jb20v
bmF2eWFzMzIxL3ZpYmVtaXMiKQogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICBC
dXR0b24gewpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9TeXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwg
Yi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9nLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwLi45NmNjMDk5Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9TeXN0
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
IE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAgYmFja2dyb3VuZDogUmVjdGFu
Z2xlIHsgY29sb3I6IFZiVG9rZW5zLmJnRWxldjsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNEaWFs
b2c7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlIH0KKyAgICBvbk9wZW5lZDogeyBzZWxl
Y3RlZCA9ICh7fSk7IFN5c3RlbUNvbnRyb2xzLm9wZW4oa2luZCkgfQorICAgIG9uQ2xvc2VkOiB7
IGNyZWRlbnRpYWwuY2xvc2UoKTsgc2VjcmV0LnRleHQgPSAiIjsgZm9yZ2V0LmNsb3NlKCk7IFN5
c3RlbUNvbnRyb2xzLmNsb3NlKCkgfQorICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgewor
ICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICAgICAgUm93TGF5b3V0IHsKKyAg
ICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgIExhYmVsIHsgZm9u
dC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVC
b2R5OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0Rm9y
bWF0OiBUZXh0LlBsYWluVGV4dDsgdGV4dDogU3lzdGVtQ29udHJvbHMuc3RhdHVzOyBjb2xvcjog
VmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICBCdXN5SW5kaWNhdG9yIHsgcnVubmluZzog
U3lzdGVtQ29udHJvbHMuYnVzeTsgdmlzaWJsZTogcnVubmluZzsgaW1wbGljaXRXaWR0aDogMzI7
IGltcGxpY2l0SGVpZ2h0OiAzMiB9CisgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsg
aWQ6IHNjYW5CdXR0b247IHRleHQ6IHFzVHIoIlNjYW4iKTsgZW5hYmxlZDogIVN5c3RlbUNvbnRy
b2xzLmJ1c3k7IG9uQ2xpY2tlZDogeyBwYW5lbC5zZWxlY3RlZCA9ICh7fSk7IFN5c3RlbUNvbnRy
b2xzLnJlcXVlc3QocGFuZWwua2luZCArICItc2NhbiIpIH0gfQorICAgICAgICB9CisgICAgICAg
IEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJDYW5jZWwgb3BlcmF0aW9uIik7IHZp
c2libGU6IFN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogeyBTeXN0ZW1Db250cm9scy5j
bG9zZSgpOyBwYW5lbC5zZWxlY3RlZD0oe30pOyByZW9wZW4ucmVzdGFydCgpIH0gfQorICAgICAg
ICBUaW1lciB7IGlkOiByZW9wZW47IGludGVydmFsOiA2MDA7IG9uVHJpZ2dlcmVkOiBpZihwYW5l
bC5vcGVuZWQpIFN5c3RlbUNvbnRyb2xzLm9wZW4ocGFuZWwua2luZCkgfQorICAgICAgICBUaW1l
ciB7IGludGVydmFsOjUwMDA7IHJlcGVhdDp0cnVlOyBydW5uaW5nOnBhbmVsLm9wZW5lZCAmJiBw
YW5lbC5raW5kPT09ImJ0IiAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeSAmJiAhY3JlZGVudGlhbC5v
cGVuZWQ7IG9uVHJpZ2dlcmVkOlN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImJ0LWxpc3QiKSB9Cisg
ICAgICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxT
aXplOlZiVG9rZW5zLnR5cGVCb2R5OworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1
ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0KKyAgICAgICAg
ICAgIHRleHQ6IHBhbmVsLmtpbmQgPT09ICJ3aWZpIiA/IHFzVHIoIlNlbGVjdCBhIG5ldHdvcmss
IHRoZW4gQ29ubmVjdC4gQWR2YW5jZWQgb3IgaGlkZGVuIG5ldHdvcmtzIGFyZSBhdmFpbGFibGUg
aW4gdGhlIGRpYWdub3N0aWMgc2hlbGwuIikgOiBxc1RyKCJQdXQgeW91ciBjb250cm9sbGVyIG9y
IGhlYWRwaG9uZXMgaW4gcGFpcmluZyBtb2RlLCB0aGVuIFNjYW4uIERldmljZXMgYXBwZWFyIGR1
cmluZyBzY2FubmluZy4gU2F2ZWQgZGV2aWNlcyBhcmUgbGlzdGVkIHdpdGhvdXQgc2Nhbm5pbmcu
IikKKyAgICAgICAgfQorICAgICAgICBMaXN0VmlldyB7CisgICAgICAgICAgICBpZDogZGV2aWNl
cworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgTGF5b3V0LmZpbGxIZWlnaHQ6
IHRydWUKKyAgICAgICAgICAgIGNsaXA6IHRydWU7IHNwYWNpbmc6IDQ7IG1vZGVsOiBTeXN0ZW1D
b250cm9scy5pdGVtcworICAgICAgICAgICAgU2Nyb2xsQmFyLnZlcnRpY2FsOiBTY3JvbGxCYXIg
e30KKyAgICAgICAgICAgIGRlbGVnYXRlOiBJdGVtRGVsZWdhdGUgeworICAgICAgICAgICAgICAg
IHdpZHRoOiBkZXZpY2VzLndpZHRoCisgICAgICAgICAgICAgICAgaW1wbGljaXRIZWlnaHQ6IE1h
dGgubWF4KDQ0LGNvbnRlbnRJdGVtLmltcGxpY2l0SGVpZ2h0KzI0KQorICAgICAgICAgICAgICAg
IGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7IGNvbG9yOnBhcmVudC5oaWdobGlnaHRlZCB8fCBwYXJl
bnQuaG92ZXJlZCA/IFZiVG9rZW5zLmJnRWxldjIgOiBWYlRva2Vucy5iZ0VsZXY7IHJhZGl1czpW
YlRva2Vucy5yYWRpdXNDb250cm9sOyBib3JkZXIuY29sb3I6cGFyZW50LmFjdGl2ZUZvY3VzP1Zi
VG9rZW5zLmFjY2VudDpWYlRva2Vucy5zdHJva2UgfQorICAgICAgICAgICAgICAgIGVuYWJsZWQ6
ICFTeXN0ZW1Db250cm9scy5idXN5CisgICAgICAgICAgICAgICAgaGlnaGxpZ2h0ZWQ6IHBhbmVs
LnNlbGVjdGVkLmlkID09PSBtb2RlbERhdGEuaWQKKyAgICAgICAgICAgICAgICBhY3RpdmVGb2N1
c09uVGFiOiB0cnVlCisgICAgICAgICAgICAgICAgS2V5cy5vblJldHVyblByZXNzZWQ6IGlmIChl
bmFibGVkKSBjbGlja2VkKCkKKyAgICAgICAgICAgICAgICBLZXlzLm9uRW50ZXJQcmVzc2VkOiBp
ZiAoZW5hYmxlZCkgY2xpY2tlZCgpCisgICAgICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2Vk
OiB7IGlmIChpbmRleCArIDEgPCBkZXZpY2VzLmNvdW50KSB7IGRldmljZXMuaW5jcmVtZW50Q3Vy
cmVudEluZGV4KCk7IGlmIChkZXZpY2VzLmN1cnJlbnRJdGVtKSBkZXZpY2VzLmN1cnJlbnRJdGVt
LmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpIH0gZWxzZSBpZiAoY29ubmVjdEJ1dHRvbi5l
bmFibGVkKSBjb25uZWN0QnV0dG9uLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpOyBlbHNl
IHNjYW5CdXR0b24uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykgfQorICAgICAgICAgICAg
ICAgIEtleXMub25VcFByZXNzZWQ6IHsgaWYgKGluZGV4ID4gMCkgeyBkZXZpY2VzLmRlY3JlbWVu
dEN1cnJlbnRJbmRleCgpOyBpZiAoZGV2aWNlcy5jdXJyZW50SXRlbSkgZGV2aWNlcy5jdXJyZW50
SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKSB9IGVsc2Ugc2NhbkJ1dHRvbi5mb3Jj
ZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKSB9CisgICAgICAgICAgICAgICAgY29udGVudEl0ZW06
IExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZi
VG9rZW5zLnR5cGVCb2R5OworICAgICAgICAgICAgICAgICAgICB0ZXh0Rm9ybWF0OiBUZXh0LlBs
YWluVGV4dDsgZWxpZGU6IFRleHQuRWxpZGVSaWdodDsgY29sb3I6IFZiVG9rZW5zLnRleHQKKyAg
ICAgICAgICAgICAgICAgICAgdGV4dDogbW9kZWxEYXRhLm5hbWUgKyAiIMK3ICIgKyBtb2RlbERh
dGEuZGV0YWlsICsgKG1vZGVsRGF0YS5jb25uZWN0ZWQgPyAiIMK3ICIgKyBxc1RyKCJDb25uZWN0
ZWQiKSA6ICIiKQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6
IHsgcGFuZWwuc2VsZWN0ZWQgPSBtb2RlbERhdGE7IGRldmljZXMuY3VycmVudEluZGV4ID0gaW5k
ZXggfQorICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgICAgIFJvd0xheW91dCB7CisgICAg
ICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisgICAgICAgICAgICBFY2xpcHNlQWN0aW9u
QnV0dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogY29ubmVjdEJ1dHRvbgorICAgICAgICAgICAg
ICAgIHRleHQ6IHBhbmVsLmtpbmQgPT09ICJ3aWZpIiA/IHFzVHIoIkNvbm5lY3QiKSA6IHFzVHIo
IlBhaXIgLyBDb25uZWN0IikKKyAgICAgICAgICAgICAgICBlbmFibGVkOiAhIXBhbmVsLnNlbGVj
dGVkLmlkICYmICFTeXN0ZW1Db250cm9scy5idXN5CisgICAgICAgICAgICAgICAgb25DbGlja2Vk
OiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KHBhbmVsLmtpbmQgKyAiLWNvbm5lY3QiLCBwYW5lbC5z
ZWxlY3RlZC5pZCkKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0
b24geworICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkRpc2Nvbm5lY3QiKTsgZW5hYmxlZDog
ISFwYW5lbC5zZWxlY3RlZC5pZCAmJiBwYW5lbC5zZWxlY3RlZC5jb25uZWN0ZWQgJiYgIVN5c3Rl
bUNvbnRyb2xzLmJ1c3kKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IFN5c3RlbUNvbnRyb2xz
LnJlcXVlc3QocGFuZWwua2luZCArICItZGlzY29ubmVjdCIsIHBhbmVsLnNlbGVjdGVkLmlkKQor
ICAgICAgICAgICAgfQorICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFz
VHIoIkZvcmdldCIpOyB2aXNpYmxlOiBwYW5lbC5raW5kID09PSAiYnQiOyBlbmFibGVkOiAhIXBh
bmVsLnNlbGVjdGVkLmlkICYmICFTeXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6IGZvcmdl
dC5vcGVuKCkgfQorICAgICAgICB9CisgICAgfQorICAgIENvbm5lY3Rpb25zIHsKKyAgICAgICAg
dGFyZ2V0OiBTeXN0ZW1Db250cm9scworICAgICAgICBmdW5jdGlvbiBvbkNoYW5nZWQoKSB7Cisg
ICAgICAgICAgICBpZiAoU3lzdGVtQ29udHJvbHMucHJvbXB0Lmxlbmd0aCA+IDAgJiYgcGFuZWwu
b3BlbmVkICYmICFjcmVkZW50aWFsLm9wZW5lZCkgY3JlZGVudGlhbC5vcGVuKCkKKyAgICAgICAg
ICAgIGlmICghU3lzdGVtQ29udHJvbHMuYnVzeSkgeworICAgICAgICAgICAgICAgIGNyZWRlbnRp
YWwuY2xvc2UoKTsgc2VjcmV0LnRleHQgPSAiIgorICAgICAgICAgICAgICAgIHZhciBpZCA9IHBh
bmVsLnNlbGVjdGVkLmlkCisgICAgICAgICAgICAgICAgcGFuZWwuc2VsZWN0ZWQgPSAoe30pCisg
ICAgICAgICAgICAgICAgZm9yICh2YXIgaSA9IDA7IGkgPCBTeXN0ZW1Db250cm9scy5pdGVtcy5s
ZW5ndGg7IGkrKykKKyAgICAgICAgICAgICAgICAgICAgaWYgKFN5c3RlbUNvbnRyb2xzLml0ZW1z
W2ldLmlkID09PSBpZCkgcGFuZWwuc2VsZWN0ZWQgPSBTeXN0ZW1Db250cm9scy5pdGVtc1tpXQor
ICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQorICAgIE5hdmlnYWJsZURpYWxvZyB7Cisg
ICAgICAgIGlkOiBjcmVkZW50aWFsCisgICAgICAgIG9iamVjdE5hbWU6ICJjb25uZWN0aW9uQ3Jl
ZGVudGlhbCIKKyAgICAgICAgdGl0bGU6IHFzVHIoIkNvbm5lY3Rpb24gYXV0aGVudGljYXRpb24i
KQorICAgICAgICB3aWR0aDogTWF0aC5taW4oNDgwLCBwYW5lbC53aWR0aCkKKyAgICAgICAgY2xv
c2VQb2xpY3k6IFBvcHVwLk5vQXV0b0Nsb3NlCisgICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlh
bG9nLk9rIHwgRGlhbG9nLkNhbmNlbAorICAgICAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRv
a2Vucy5iZ0VsZXYKKyAgICAgICAgb25PcGVuZWQ6IHsgc2VjcmV0LnRleHQgPSAiIjsgc2VjcmV0
LmZvcmNlQWN0aXZlRm9jdXMoKSB9CisgICAgICAgIG9uQWNjZXB0ZWQ6IHsgU3lzdGVtQ29udHJv
bHMuYW5zd2VyKHNlY3JldC50ZXh0KTsgc2VjcmV0LnRleHQgPSAiIiB9CisgICAgICAgIG9uUmVq
ZWN0ZWQ6IHsgc2VjcmV0LnRleHQgPSAiIjsgU3lzdGVtQ29udHJvbHMuY2xvc2UoKTsgcmVvcGVu
LnJlc3RhcnQoKSB9CisgICAgICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAgICAg
ICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNp
emU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHRleHRGb3JtYXQ6
IFRleHQuUGxhaW5UZXh0OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBTeXN0ZW1Db250cm9s
cy5wcm9tcHQ7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0KKyAgICAgICAgICAgIFRleHRGaWVsZCB7
IGlkOiBzZWNyZXQ7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6
ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgZWNob01vZGU6IFRl
eHRJbnB1dC5QYXNzd29yZDsgbWF4aW11bUxlbmd0aDogNDA5Njsgc2VsZWN0QnlNb3VzZTogdHJ1
ZTsgb25BY2NlcHRlZDogY3JlZGVudGlhbC5hY2NlcHQoKSB9CisgICAgICAgICAgICBMYWJlbCB7
IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50
eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4
dDogcXNUcigiRW50ZXIgdGhlIHJlcXVlc3RlZCBwYXNzd29yZCBvciBQSU4uIEZvciBhIHllcy9u
byBjb25maXJtYXRpb24sIHR5cGUgeWVzIG9yIG5vLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERp
bSB9CisgICAgICAgIH0KKyAgICB9CisgICAgTmF2aWdhYmxlRGlhbG9nIHsKKyAgICAgICAgaWQ6
IGZvcmdldAorICAgICAgICBpbXBsaWNpdEhlaWdodDogY29udGVudEl0ZW0uY29udGVudEhlaWdo
dCArIGhlYWRlci5pbXBsaWNpdEhlaWdodCArIGZvb3Rlci5pbXBsaWNpdEhlaWdodCArIHRvcFBh
ZGRpbmcgKyBib3R0b21QYWRkaW5nCisgICAgICAgIG9iamVjdE5hbWU6ICJjb25uZWN0aW9uRm9y
Z2V0IgorICAgICAgICB0aXRsZTogcXNUcigiRm9yZ2V0IEJsdWV0b290aCBkZXZpY2U/IikKKyAg
ICAgICAgd2lkdGg6IE1hdGgubWluKDQ4MCwgcGFuZWwud2lkdGgpCisgICAgICAgIHN0YW5kYXJk
QnV0dG9uczogRGlhbG9nLlllcyB8IERpYWxvZy5ObworICAgICAgICBNYXRlcmlhbC5iYWNrZ3Jv
dW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAgICAgb25BY2NlcHRlZDogU3lzdGVtQ29udHJvbHMu
cmVxdWVzdCgiYnQtZm9yZ2V0IiwgcGFuZWwuc2VsZWN0ZWQuaWQsIHRydWUpCisgICAgICAgIGNv
bnRlbnRJdGVtOiBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBp
eGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHdy
YXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIlJlbW92ZSB0aGUgc2F2ZWQgcGFpcmluZyBm
b3IgJTE/IFlvdSB3aWxsIG5lZWQgdG8gcGFpciBpdCBhZ2Fpbi4iKS5hcmcocGFuZWwuc2VsZWN0
ZWQubmFtZSB8fCAiIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0KKyAgICB9Cit9CmRpZmYgLS1n
aXQgYS9hcHAvZ3VpL1RoZW1lLnFtbCBiL2FwcC9ndWkvVGhlbWUucW1sCmluZGV4IGZiOTFjODUu
LjU3YzlmODQgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVGhlbWUucW1sCisrKyBiL2FwcC9ndWkvVGhl
bWUucW1sCkBAIC0xMSwyMCArMTEsMjAgQEAgaW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCiBR
dE9iamVjdCB7CiAgICAgLy8gLS0tLSBDb2xvciAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVydHkg
Y29sb3IgYWNjZW50OiAgICAgICAgVmJUb2tlbnMuYWNjZW50ICAvLyBCTC0yMDc3OiBzaW5nbGUg
c291cmNlIG9mIHRydXRoIChWYlRva2VucyBicmFuZCBhY2NlbnQsIGRlZmF1bHQgIzAwQ0NDQykK
LSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2VkOiAiIzAwQTNBMyIKLSAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiYWNrZ3JvdW5kOiAgICAiIzMwMzAzMCIgIC8vIGFw
cCByb290Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3VyZmFjZTogICAgICAgIiMyRDJE
MkQiICAvLyByYWlzZWQgc3VyZmFjZXMgLyBvdmVybGF5cwotICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIHN1cmZhY2VBbHQ6ICAgICIjNDI0MjQyIiAgLy8gcG9wdXBzIC8gY29tYm8gZHJvcGRv
d25zCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYm9yZGVyOiAgICAgICAgIiM0NDQ0NDQi
Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFByaW1hcnk6ICAgIiNGRkZGRkYiCi0g
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFNlY29uZGFyeTogIiNDQ0NDQ0MiCi0gICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFRlcnRpYXJ5OiAgIiNBQUFBQUEiCi0gICAgcmVh
ZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpc2FibGVkOiAgIiM3Nzc3NzciCi0gICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3Igc3VjY2VzczogICAgICAgIiM0Q0FGNTAiCi0gICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3Igd2FybmluZzogICAgICAgIiNFMEEwMzAiICAvLyB0aGUgc2luZ2xlIGFt
YmVyCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZXJyb3I6ICAgICAgICAgIiNGNDQzMzYi
Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW5mbzogICAgICAgICAgIiM4MEEwQzAiCi0g
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc2NyaW06ICAgICAgICAgIiNEMDAwMDAwMCIKKyAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2VkOiBWYlRva2Vucy5hY2NlbnRQ
cmVzc2VkCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmFja2dyb3VuZDogICAgVmJUb2tl
bnMuYmdXaW5kb3cgIC8vIGFwcCByb290CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Vy
ZmFjZTogICAgICAgVmJUb2tlbnMuYmdFbGV2ICAvLyByYWlzZWQgc3VyZmFjZXMgLyBvdmVybGF5
cworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZhY2VBbHQ6ICAgIFZiVG9rZW5zLmJn
RWxldjIgIC8vIHBvcHVwcyAvIGNvbWJvIGRyb3Bkb3ducworICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIGJvcmRlcjogICAgICAgIFZiVG9rZW5zLnN0cm9rZQorICAgIHJlYWRvbmx5IHByb3Bl
cnR5IGNvbG9yIHRleHRQcmltYXJ5OiAgIFZiVG9rZW5zLnRleHRQcmltYXJ5CisgICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3IgdGV4dFNlY29uZGFyeTogVmJUb2tlbnMudGV4dFNlY29uZGFyeQor
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRUZXJ0aWFyeTogIFZiVG9rZW5zLnRleHRU
ZXJ0aWFyeQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHREaXNhYmxlZDogIFZiVG9r
ZW5zLnRleHREaXNhYmxlZAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1Y2Nlc3M6ICAg
ICAgIFZiVG9rZW5zLnN0YXR1c1N1Y2Nlc3MKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB3
YXJuaW5nOiAgICAgICBWYlRva2Vucy5zdGF0dXNXYXJuaW5nICAvLyB0aGUgc2luZ2xlIGFtYmVy
CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZXJyb3I6ICAgICAgICAgVmJUb2tlbnMuc3Rh
dHVzRGFuZ2VyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW5mbzogICAgICAgICAgVmJU
b2tlbnMuc3RhdHVzSW5mbworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHNjcmltOiAgICAg
ICAgIFZiVG9rZW5zLmRpYWxvZ1NjcmltCiAKICAgICAvLyAtLS0tIFR5cG9ncmFwaHkgKHBvaW50
U2l6ZTsgcGFpciB3aXRoIGJvbGQgd2hlcmUgbm90ZWQgaW4gREVTSUdOX1NZU1RFTS5tZCkgLS0t
LQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBmb250RGlzcGxheTogMjQgIC8vIG92ZXJsYXkv
UXVpY2sgTWVudSB0aXRsZSAoYm9sZCkKZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJDYXJkLnFtbCBi
L2FwcC9ndWkvVmJDYXJkLnFtbAppbmRleCAzN2YyZTMyLi4xZTkwYTAyIDEwMDY0NAotLS0gYS9h
cHAvZ3VpL1ZiQ2FyZC5xbWwKKysrIGIvYXBwL2d1aS9WYkNhcmQucW1sCkBAIC0yNyw3ICsyNyw3
IEBAIEl0ZW0gewogICAgICAgICBib3JkZXIud2lkdGg6IDEKICAgICAgICAgYm9yZGVyLmNvbG9y
OiBWYlRva2Vucy5zdHJva2UKICAgICAgICAgb3BhY2l0eTogY2FyZC5jb250ZW50T3BhY2l0eQot
ICAgICAgICBCZWhhdmlvciBvbiBjb2xvciB7IENvbG9yQW5pbWF0aW9uIHsgZHVyYXRpb246IDEy
MCB9IH0KKyAgICAgICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xvckFuaW1hdGlvbiB7IGR1cmF0
aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8gMTIwIDogMCB9IH0KICAgICB9CiAKICAgICBJ
dGVtIHsKZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbCBiL2FwcC9ndWkvVmJT
dGF0dXNQaWxsLnFtbAppbmRleCA4OWM0NzcwLi5jNzI4ZjA1IDEwMDY0NAotLS0gYS9hcHAvZ3Vp
L1ZiU3RhdHVzUGlsbC5xbWwKKysrIGIvYXBwL2d1aS9WYlN0YXR1c1BpbGwucW1sCkBAIC0yNCw3
ICsyNCw3IEBAIFJlY3RhbmdsZSB7CiAgICAgICAgICAgICBjb2xvcjogcGlsbC5vbmxpbmUgPyBW
YlRva2Vucy5zdGF0dXNPbmxpbmUgOiBWYlRva2Vucy5zdGF0dXNPZmZsaW5lCiAgICAgICAgICAg
ICAvLyBQdWxzZSBvbmx5IHdoZW4gb25saW5lLgogICAgICAgICAgICAgU2VxdWVudGlhbEFuaW1h
dGlvbiBvbiBvcGFjaXR5IHsKLSAgICAgICAgICAgICAgICBydW5uaW5nOiBwaWxsLm9ubGluZQor
ICAgICAgICAgICAgICAgIHJ1bm5pbmc6IHBpbGwub25saW5lICYmIFZiVG9rZW5zLm1vdGlvbkVu
YWJsZWQKICAgICAgICAgICAgICAgICBsb29wczogQW5pbWF0aW9uLkluZmluaXRlCiAgICAgICAg
ICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMS4wOyB0bzogMC40NTsgZHVyYXRpb246
IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAyOyBlYXNpbmcudHlwZTogRWFzaW5nLkluT3V0U2lu
ZSB9CiAgICAgICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMC40NTsgdG86IDEu
MDsgZHVyYXRpb246IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAyOyBlYXNpbmcudHlwZTogRWFz
aW5nLkluT3V0U2luZSB9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1ZiVG9rZW5zLnFtbCBiL2FwcC9n
dWkvVmJUb2tlbnMucW1sCmluZGV4IDUyYTM0ZGUuLmNiZjc5ODUgMTAwNjQ0Ci0tLSBhL2FwcC9n
dWkvVmJUb2tlbnMucW1sCisrKyBiL2FwcC9ndWkvVmJUb2tlbnMucW1sCkBAIC0xLDYgKzEsNyBA
QAogcHJhZ21hIFNpbmdsZXRvbgogaW1wb3J0IFF0UXVpY2sgMi45CiBpbXBvcnQgU3RyZWFtaW5n
UHJlZmVyZW5jZXMgMS4wCitpbXBvcnQgRWNsaXBzZVByb2ZpbGVzIDEuMAogCiAvLyBWaWJlbWlz
IHJlZGVzaWduIGRlc2lnbiB0b2tlbnMuCiAvLyBEYXJrIHRoZW1lIG9ubHkuIENhbnZhcyAxOTIw
eDEyMDAgKExlZ2lvbiBHbyBTKSwKQEAgLTksNDMgKzEwLDQ0IEBAIGltcG9ydCBTdHJlYW1pbmdQ
cmVmZXJlbmNlcyAxLjAKIFF0T2JqZWN0IHsKICAgICBpZDogdAogCisgICAgcmVhZG9ubHkgcHJv
cGVydHkgcmVhbCB0ZXh0U2NhbGU6IEVjbGlwc2VQcm9maWxlcy50ZXh0U2NhbGUgLyAxMDAKKyAg
ICByZWFkb25seSBwcm9wZXJ0eSBib29sIG1vdGlvbkVuYWJsZWQ6ICFFY2xpcHNlUHJvZmlsZXMu
cmVkdWNlZE1vdGlvbgorCiAgICAgLy8gLS0tLSBDb2xvciAtLS0tCi0gICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3IgYmdBcHA6ICAgICAgICAiIzA4MDkwQiIgIC8vIG91dGVybW9zdCBhcHAgYmcg
YmVoaW5kIHRoZSByb3VuZGVkIHdpbmRvdwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJn
V2luZG93OiAgICAgIiMwRTEwMTMiICAvLyBtYWluIHNjcmVlbiBiYWNrZ3JvdW5kCi0gICAgcmVh
ZG9ubHkgcHJvcGVydHkgY29sb3IgYmdFbGV2OiAgICAgICAiIzE1MTgxRCIgIC8vIGNhcmRzLCBw
YW5lbHMsIGRpYWxvZ3MsIHNpZGViYXIgcm93cwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9y
IGJnRWxldjI6ICAgICAgIiMxQjFGMjYiICAvLyBmb2N1c2VkL3NlbGVjdGVkIHN1cmZhY2UgZmls
bCwgY2hpcHMKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0Zvb3RlcjogICAgICIjMEIw
RDEwIiAgLy8gYm90dG9tIGdhbWVwYWQgaGludCBiYXIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciBzdHJva2U6ICAgICAgIFF0LnJnYmEoMSwgMSwgMSwgMC4wOCkgIC8vIGRlZmF1bHQgMXB4
IGNhcmQgYm9yZGVyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdBcHA6ICAgICAgICAi
IzA2MDYwNyIgIC8vIG91dGVybW9zdCBhcHAgYmcgYmVoaW5kIHRoZSByb3VuZGVkIHdpbmRvdwor
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnV2luZG93OiAgICAgIiMwQjBCMEUiICAvLyBt
YWluIHNjcmVlbiBiYWNrZ3JvdW5kCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdFbGV2
OiAgICAgICAiIzE1MTExNSIgIC8vIGNhcmRzLCBwYW5lbHMsIGRpYWxvZ3MsIHNpZGViYXIgcm93
cworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxldjI6ICAgICAgIiMyMTE3MUMiICAv
LyBmb2N1c2VkL3NlbGVjdGVkIHN1cmZhY2UgZmlsbCwgY2hpcHMKKyAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBiZ0Zvb3RlcjogICAgICIjMDkwODBCIiAgLy8gYm90dG9tIGdhbWVwYWQgaGlu
dCBiYXIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdHJva2U6ICAgICAgIFF0LnJnYmEo
MSwgMSwgMSwgRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdCA/IDAuMjUgOiAwLjA4KSAgLy8g
ZGVmYXVsdCAxcHggY2FyZCBib3JkZXIKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdHJv
a2VTb2Z0OiAgIFF0LnJnYmEoMSwgMSwgMSwgMC4wNikgIC8vIGhlYWRlci9mb290ZXIgZGl2aWRl
cnMKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0OiAgICAgICAgICIjRUNFRUYxIiAg
Ly8gcHJpbWFyeSB0ZXh0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpbTogICAg
ICAiIzk4QTFBQiIgIC8vIHNlY29uZGFyeSAvIGxhYmVsIHRleHQKKyAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciB0ZXh0RGltOiAgICAgIChFY2xpcHNlUHJvZmlsZXMuaGlnaENvbnRyYXN0ID8g
IiNEM0Q1REMiIDogIiM5OEExQUIiKSAgLy8gc2Vjb25kYXJ5IC8gbGFiZWwgdGV4dAogICAgIHJl
YWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRNdXRlOiAgICAgIiNCOUMwQzgiICAvLyB0ZXJ0aWFy
eSAvIGluYWN0aXZlIGl0ZW0gbGFiZWxzCiAKLSAgICAvLyBBY2NlbnQgaXMgc3dhcHBhYmxlIOKA
lCBvbmUgb2YgdGhlIDQgY3VyYXRlZCB2YWx1ZXMuIEluZGV4IDAgaXMgdGhlIFZpYmVtaXMgYnJh
bmQKLSAgICAvLyB0ZWFsICMwMENDQ0MgKEJMLTIwNzcpOiB0aGUgc2luZ2xlIGNhbm9uaWNhbCBh
Y2NlbnQgdGhhdCBUaGVtZS5xbWwgKyBhbGwgbGl0ZXJhbHMgbm93Ci0gICAgLy8gcmVzb2x2ZSB0
aHJvdWdoLCBhbmQgdGhlIGFuY2hvciBmb3IgdGhlIFAzLjE3L1AzLjE4IGRlc2lnbiB3b3JrLgot
ICAgIHJlYWRvbmx5IHByb3BlcnR5IHZhciBhY2NlbnRPcHRpb25zOiAgWyIjMDBDQ0NDIiwgIiM3
QzhDRjgiLCAiIzNFRDU5OCIsICIjRjBBODY4Il0KKyAgICAvLyBQcmVzZXJ2ZSBsZWdhY3kgaW5k
aWNlcyAwLi4zOyBhcHBlbmQgY29sb3JzIGFuZCBkZWZhdWx0IG5ldyBwcmVmZXJlbmNlcyB0byBj
cmltc29uLgorICAgIHJlYWRvbmx5IHByb3BlcnR5IHZhciBhY2NlbnRPcHRpb25zOiAgWyIjMDBD
Q0NDIiwgIiM3QzhDRjgiLCAiIzNFRDU5OCIsICIjRjBBODY4IiwgIiNEQzM2NTgiLCAiI0YyNUQ2
NCIsICIjRjU4MzQ3IiwgIiNGMUJDNDUiLCAiI0I3REM2MyIsICIjNjNDQ0FFIiwgIiM2M0M0RUQi
LCAiIzZDOUZGRiIsICIjQUQ4NUY1IiwgIiNFOTc2QkMiLCAiI0NBRDBEQSIsICIjRDk5NUFDIl0K
ICAgICAvLyBCb3VuZCB0byB0aGUgc2F2ZWQgcHJlZmVyZW5jZSAoU2V0dGluZ3MgPiBhY2NlbnQg
cGlja2VyKTsgcGVyc2lzdHMgYWNyb3NzIHJlc3RhcnRzLgogICAgIHByb3BlcnR5IGludCBhY2Nl
bnRJbmRleDogU3RyZWFtaW5nUHJlZmVyZW5jZXMudWlBY2NlbnRJbmRleAotICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAgICAgYWNjZW50T3B0aW9uc1thY2NlbnRJbmRleF0K
LSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRIaTogICAgICIjNkFEREU3IiAgLy8g
YWNjZW50IGdyYWRpZW50IGxpZ2h0IHN0b3AgLyBsaW5rIGhvdmVyCisgICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3IgYWNjZW50OiAgICAgICBhY2NlbnRPcHRpb25zW01hdGgubWF4KDAsIE1hdGgu
bWluKGFjY2VudE9wdGlvbnMubGVuZ3RoIC0gMSwgYWNjZW50SW5kZXgpKV0KKyAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRIaTogICAgIFF0LmxpZ2h0ZXIoYWNjZW50LCAxLjE4KSAg
Ly8gYWNjZW50IGdyYWRpZW50IGxpZ2h0IHN0b3AgLyBsaW5rIGhvdmVyCiAKICAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNPbmxpbmU6ICAiIzNFRDU5OCIgIC8vIG9ubGluZSBkb3Qs
IFJFU1VNRSBiYWRnZQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN0YXR1c09mZmxpbmU6
ICIjNUE2MjZDIiAgLy8gb2ZmbGluZSBkb3QgLyBncmV5ZWQgbW9uaXRvcgogICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIHN0YXR1c0RhbmdlcjogICIjRjI2RDZEIiAgLy8gZGVzdHJ1Y3RpdmUg
KERlbGV0ZSBQQykKIAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRPbkFjY2VudDog
IiMwODA5MEIiICAvLyB0ZXh0IG9uIGFuIGFjY2VudC1maWxsZWQgYnV0dG9uCisgICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3IgdGV4dE9uQWNjZW50OiAiIzA2MDYwNyIgIC8vIHRleHQgb24gYW4g
YWNjZW50LWZpbGxlZCBidXR0b24KIAogICAgIC8vIC0tLS0gVHlwb2dyYXBoeSAoZmFtaWxpZXMg
KyBzaXplczsgd2VpZ2h0cyBwZXIgdGhlIHR5cGUgc2NhbGUpIC0tLS0KICAgICByZWFkb25seSBw
cm9wZXJ0eSBzdHJpbmcgZm9udERpc3BsYXk6ICJTb3JhIiAgICAgLy8gdGl0bGVzLCBjYXJkIG5h
bWVzLCB3b3JkbWFyaywgYWxsLWNhcHMgbGFiZWxzCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgc3Ry
aW5nIGZvbnRCb2R5OiAgICAiTWFucm9wZSIgIC8vIGJvZHkgKyBVSSB0ZXh0Ci0gICAgcmVhZG9u
bHkgcHJvcGVydHkgaW50IHNpemVTY3JlZW5UaXRsZTogIDM0Ci0gICAgcmVhZG9ubHkgcHJvcGVy
dHkgaW50IHNpemVTZWN0aW9uVGl0bGU6IDI4Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNp
emVDYXJkTmFtZTogICAgIDI3Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVCb2R5OiAg
ICAgICAgIDE2Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVMYWJlbDogICAgICAgIDE0
Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVCYWRnZTogICAgICAgIDEzCi0gICAgcmVh
ZG9ubHkgcHJvcGVydHkgaW50IHNpemVXb3JkbWFyazogICAgIDIxCisgICAgcmVhZG9ubHkgcHJv
cGVydHkgaW50IHNpemVTY3JlZW5UaXRsZTogIE1hdGgucm91bmQoMzQgKiB0ZXh0U2NhbGUpCisg
ICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVTZWN0aW9uVGl0bGU6IE1hdGgucm91bmQoMjgg
KiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVDYXJkTmFtZTogICAg
IE1hdGgucm91bmQoMjcgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNp
emVCb2R5OiAgICAgICAgIE1hdGgucm91bmQoMTYgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkg
cHJvcGVydHkgaW50IHNpemVMYWJlbDogICAgICAgIE1hdGgucm91bmQoMTQgKiB0ZXh0U2NhbGUp
CisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVCYWRnZTogICAgICAgIE1hdGgucm91bmQo
MTMgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVXb3JkbWFyazog
ICAgIE1hdGgucm91bmQoMjEgKiB0ZXh0U2NhbGUpCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgcmVh
bCB3b3JkbWFya1NwYWNpbmc6IDMuMAogICAgIHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgYmFkZ2VT
cGFjaW5nOiAgICAxLjIKIApAQCAtODMsNyArODUsNyBAQCBRdE9iamVjdCB7CiAgICAgLy8gLS0t
LSBNb3Rpb24gKG1zKSAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IG9ubGluZVB1bHNl
TXM6IDI0MDAgICAvLyBvcGFjaXR5IDEgLT4gMC40NSAtPiAxLCBpbmZpbml0ZQogICAgIHJlYWRv
bmx5IHByb3BlcnR5IGludCBjYXJldEJsaW5rTXM6ICAxMDAwICAgLy8gQWRkLVBDIGlucHV0IGNh
cmV0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNoZWV0SW5NczogICAgIDIyMCAgICAvLyBz
aWRlLXNoZWV0IHNsaWRlLWluCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNoZWV0SW5Nczog
ICAgIG1vdGlvbkVuYWJsZWQgPyAyMjAgOiAwICAgIC8vIHNpZGUtc2hlZXQgc2xpZGUtaW4KICAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBkaWFsb2dTY3JpbTogUXQucmdiYSg0LzI1NSwgNS8y
NTUsIDcvMjU1LCAwLjcyKQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHNoZWV0U2NyaW06
ICBRdC5yZ2JhKDQvMjU1LCA1LzI1NSwgNy8yNTUsIDAuNjApCiAKQEAgLTExOSw3ICsxMjEsNyBA
QCBRdE9iamVjdCB7CiAgICAgLy8gdGV4dE9uQWNjZW50ICgjMDgwOTBCKSBpcyBkZWZpbmVkIGlu
IHRoZSBiYXNlIGJsb2NrIGFib3ZlIOKAlCB0ZXh0IG9uIGFuIGFjY2VudCBmaWxsLgogCiAgICAg
Ly8gLS0tLSBJbnRlcmFjdGl2ZSBzdGF0ZXM6IG5vcm1hbCAvIGhvdmVyIC8gZm9jdXMgLyBwcmVz
c2VkIC8gZGlzYWJsZWQgLS0tLQotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudFBy
ZXNzZWQ6ICAgICAgIiMwMEEzQTMiIC8vIHByZXNzZWQgYWNjZW50ZWQgY29udHJvbCAobWF0Y2hl
cyBsZWdhY3kgVGhlbWUuYWNjZW50UHJlc3NlZCkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xv
ciBhY2NlbnRQcmVzc2VkOiAgICAgIFF0LmRhcmtlcihhY2NlbnQsIDEuMTgpIC8vIHByZXNzZWQg
YWNjZW50ZWQgY29udHJvbCAobWF0Y2hlcyBsZWdhY3kgVGhlbWUuYWNjZW50UHJlc3NlZCkKICAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZUhvdmVyOiAgIGJnRWxldjIgICAg
Ly8gcm93IC8gbGlzdC1pdGVtIC8gaWNvbi1idXR0b24gaG92ZXIgZmlsbAogICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIGludGVyYWN0aXZlRm9jdXM6ICAgZm9jdXNlZEZpbGwvLyBmb2N1c2Vk
IGZpbGwgKD0gYmdFbGV2Mikg4oCUIHBhaXIgd2l0aCB0aGUgZm9jdXMgcmluZwogICAgIHJlYWRv
bmx5IHByb3BlcnR5IGNvbG9yIGludGVyYWN0aXZlUHJlc3NlZDogYmdFbGV2ICAgICAvLyBwcmVz
c2VkIG5ldXRyYWwgZmlsbCAocmVjZWRlcyB1bmRlciB0aGUgcHJlc3MpCmRpZmYgLS1naXQgYS9h
cHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFtbCBiL2FwcC9ndWkvVmJXZWxjb21lU2hlZXQucW1sCmlu
ZGV4IDE3MzExOWIuLjQzODNjYjAgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVmJXZWxjb21lU2hlZXQu
cW1sCisrKyBiL2FwcC9ndWkvVmJXZWxjb21lU2hlZXQucW1sCkBAIC0xMDgsMTQgKzEwOCwxMyBA
QCBOYXZpZ2FibGVEaWFsb2cgewogICAgICAgICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2Uy
ICAvLyA4CiAgICAgICAgICAgICBSb3dMYXlvdXQgewogICAgICAgICAgICAgICAgIHNwYWNpbmc6
IFZiVG9rZW5zLnNwYWNlMgotICAgICAgICAgICAgICAgIFJlY3RhbmdsZSB7Ci0gICAgICAgICAg
ICAgICAgICAgIHdpZHRoOiAxMzsgaGVpZ2h0OiAxMwotICAgICAgICAgICAgICAgICAgICBjb2xv
cjogVmJUb2tlbnMuYWNjZW50Ci0gICAgICAgICAgICAgICAgICAgIHJvdGF0aW9uOiA0NQorICAg
ICAgICAgICAgICAgIEltYWdlIHsKKyAgICAgICAgICAgICAgICAgICAgc291cmNlOiAicXJjOi9y
ZXMvZWNsaXBzZS1pY29uLnN2ZyIKKyAgICAgICAgICAgICAgICAgICAgTGF5b3V0LnByZWZlcnJl
ZFdpZHRoOiAyODsgTGF5b3V0LnByZWZlcnJlZEhlaWdodDogMjgKICAgICAgICAgICAgICAgICAg
ICAgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25WQ2VudGVyCiAgICAgICAgICAgICAgICAgfQog
ICAgICAgICAgICAgICAgIFRleHQgewotICAgICAgICAgICAgICAgICAgICB0ZXh0OiAiVklCRU1J
UyIKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogIkVDTElQU0UiCiAgICAgICAgICAgICAgICAg
ICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250RGlzcGxheQogICAgICAgICAgICAgICAgICAg
ICBmb250LndlaWdodDogRm9udC5FeHRyYUJvbGQKICAgICAgICAgICAgICAgICAgICAgZm9udC5w
aXhlbFNpemU6IFZiVG9rZW5zLnNpemVXb3JkbWFyayAgICAgIC8vIDIxCkBAIC0xMjUsNyArMTI0
LDcgQEAgTmF2aWdhYmxlRGlhbG9nIHsKICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9
CiAgICAgICAgICAgICBUZXh0IHsKLSAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJXZWxjb21l
IHRvIFZpYmVtaXMiKQorICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIldlbGNvbWUgdG8gRWNs
aXBzZSIpCiAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5
CiAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZvbnQuQm9sZAogICAgICAgICAgICAgICAg
IGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlRGlzcGxheSAgICAgICAgICAgLy8gMzQKQEAg
LTE5NSw3ICsxOTQsNyBAQCBOYXZpZ2FibGVEaWFsb2cgewogICAgICAgICAgICAgSW5mb1JvdyB7
CiAgICAgICAgICAgICAgICAgZ2x5cGg6ICJhcHBzIgogICAgICAgICAgICAgICAgIHRpdGxlOiBx
c1RyKCJBZGQgdG8gU3RlYW0iKQotICAgICAgICAgICAgICAgIHN1YjogcXNUcigiT24gU3RlYW0g
RGVjayAvIFN0ZWFtT1MsIGFkZCBWaWJlbWlzIHRvIFN0ZWFtIGZyb20gRGVza3RvcCBNb2RlIHNv
IGl0IGFwcGVhcnMgaW4gR2FtZSBNb2RlLiIpCisgICAgICAgICAgICAgICAgc3ViOiBxc1RyKCJP
biBTdGVhbSBEZWNrIC8gU3RlYW1PUywgYWRkIEVjbGlwc2UgdG8gU3RlYW0gZnJvbSBEZXNrdG9w
IE1vZGUgc28gaXQgYXBwZWFycyBpbiBHYW1lIE1vZGUuIikKICAgICAgICAgICAgIH0KIAogICAg
ICAgICAgICAgLy8gMykgU2V0dGluZ3MuCmRpZmYgLS1naXQgYS9hcHAvZ3VpL2NvbXB1dGVybW9k
ZWwuY3BwIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmNwcAppbmRleCA2M2M3MTE1Li4yZDQ4N2Zm
IDEwMDY0NAotLS0gYS9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuY3BwCisrKyBiL2FwcC9ndWkvY29t
cHV0ZXJtb2RlbC5jcHAKQEAgLTEsMyArMSw0IEBACisjaW5jbHVkZSA8UVVybD4KICNpbmNsdWRl
ICJjb21wdXRlcm1vZGVsLmgiCiAjaW5jbHVkZSAiYmFja2VuZC9zZXJ2ZXJwZXJtaXNzaW9ucy5o
IgogI2luY2x1ZGUgInNldHRpbmdzL3ZpYmVtaXNzZXR0aW5ncy5oIgpAQCAtNDIwLDMgKzQyMSwx
MyBAQCB2b2lkIENvbXB1dGVyTW9kZWw6OmhhbmRsZUNvbXB1dGVyU3RhdGVDaGFuZ2VkKE52Q29t
cHV0ZXIqIGNvbXB1dGVyKQogfQogCiAjaW5jbHVkZSAiY29tcHV0ZXJtb2RlbC5tb2MiCisKK1FW
YXJpYW50TWFwIENvbXB1dGVyTW9kZWw6OmNyaW1zb25Ib3N0KGludCBpbmRleCkgY29uc3QKK3sK
KyAgICBpZiAoaW5kZXggPCAwIHx8IGluZGV4ID49IG1fQ29tcHV0ZXJzLmNvdW50KCkpIHJldHVy
biB7fTsKKyAgICBhdXRvIGNvbXB1dGVyID0gbV9Db21wdXRlcnNbaW5kZXhdOworICAgIFFSZWFk
TG9ja2VyIGxvY2soJmNvbXB1dGVyLT5sb2NrKTsKKyAgICBRVXJsIHVybDsgdXJsLnNldFNjaGVt
ZSgiaHR0cHMiKTsgdXJsLnNldEhvc3QoY29tcHV0ZXItPmFjdGl2ZUFkZHJlc3MuYWRkcmVzcygp
KTsKKyAgICB1cmwuc2V0UG9ydChjb21wdXRlci0+YWN0aXZlQWRkcmVzcy5wb3J0KCkgPiAwID8g
Y29tcHV0ZXItPmFjdGl2ZUFkZHJlc3MucG9ydCgpICsgMSA6IDQ3OTkwKTsKKyAgICByZXR1cm4g
e3siaWQiLCBjb21wdXRlci0+dXVpZH0sIHsidXJsIiwgdXJsLnRvU3RyaW5nKCl9fTsKK30KZGlm
ZiAtLWdpdCBhL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5oIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVs
LmgKaW5kZXggNmVjYWUzMC4uMmVlNzNjMSAxMDA2NDQKLS0tIGEvYXBwL2d1aS9jb21wdXRlcm1v
ZGVsLmgKKysrIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmgKQEAgLTQzLDYgKzQzLDggQEAgcHVi
bGljOgogCiAgICAgdmlydHVhbCBRSGFzaDxpbnQsIFFCeXRlQXJyYXk+IHJvbGVOYW1lcygpIGNv
bnN0IG92ZXJyaWRlOwogCisgICAgUV9JTlZPS0FCTEUgUVZhcmlhbnRNYXAgY3JpbXNvbkhvc3Qo
aW50IGNvbXB1dGVySW5kZXgpIGNvbnN0OworCiAgICAgUV9JTlZPS0FCTEUgdm9pZCBkZWxldGVD
b21wdXRlcihpbnQgY29tcHV0ZXJJbmRleCk7CiAKICAgICBRX0lOVk9LQUJMRSBRU3RyaW5nIGdl
bmVyYXRlUGluU3RyaW5nKCk7CmRpZmYgLS1naXQgYS9hcHAvZ3VpL21haW4ucW1sIGIvYXBwL2d1
aS9tYWluLnFtbAppbmRleCA5YmNlNTEwLi44NDhmYzE0IDEwMDY0NAotLS0gYS9hcHAvZ3VpL21h
aW4ucW1sCisrKyBiL2FwcC9ndWkvbWFpbi5xbWwKQEAgLTEyLDggKzEyLDI1IEBAIGltcG9ydCBT
eXN0ZW1Qcm9wZXJ0aWVzIDEuMAogaW1wb3J0IFNkbEdhbWVwYWRLZXlOYXZpZ2F0aW9uIDEuMAog
aW1wb3J0IFVpU291bmRNYW5hZ2VyIDEuMAogaW1wb3J0IFRoZW1lIDEuMAoraW1wb3J0IENyaW1z
b25TdGF0dXMgMS4wCitpbXBvcnQgU3lzdGVtQ29udHJvbHMgMS4wCiAKIEFwcGxpY2F0aW9uV2lu
ZG93IHsKKyAgICBNYXRlcmlhbC50aGVtZTogTWF0ZXJpYWwuRGFyaworICAgIE1hdGVyaWFsLmFj
Y2VudDogVmJUb2tlbnMuYWNjZW50CisgICAgTWF0ZXJpYWwucHJpbWFyeTogVmJUb2tlbnMuYmdF
bGV2CisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdXaW5kb3cKKyAgICBNYXRl
cmlhbC5mb3JlZ3JvdW5kOiBWYlRva2Vucy50ZXh0CisgICAgY29sb3I6IFZiVG9rZW5zLmJnQXBw
CisgICAgcGFsZXR0ZS53aW5kb3c6IFZiVG9rZW5zLmJnV2luZG93CisgICAgcGFsZXR0ZS53aW5k
b3dUZXh0OiBWYlRva2Vucy50ZXh0CisgICAgcGFsZXR0ZS5iYXNlOiBWYlRva2Vucy5iZ0FwcAor
ICAgIHBhbGV0dGUuYWx0ZXJuYXRlQmFzZTogVmJUb2tlbnMuYmdFbGV2CisgICAgcGFsZXR0ZS50
ZXh0OiBWYlRva2Vucy50ZXh0CisgICAgcGFsZXR0ZS5idXR0b246IFZiVG9rZW5zLmJnRWxldgor
ICAgIHBhbGV0dGUuYnV0dG9uVGV4dDogVmJUb2tlbnMudGV4dAorICAgIHBhbGV0dGUuaGlnaGxp
Z2h0OiBWYlRva2Vucy5hY2NlbnQKKyAgICBwYWxldHRlLmhpZ2hsaWdodGVkVGV4dDogVmJUb2tl
bnMudGV4dE9uQWNjZW50CiAgICAgcHJvcGVydHkgYm9vbCBwb2xsaW5nQWN0aXZlOiBmYWxzZQog
CiAgICAgLy8gU2V0IGJ5IFNldHRpbmdzVmlldyB0byBmb3JjZSB0aGUgYmFjayBvcGVyYXRpb24g
dG8gcG9wIGFsbApAQCAtNDYsMTQgKzYzLDEzIEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAg
ICAgLy8gaW4gb3JkZXIgdG8gaW1wcm92ZSBjb250cmFzdCBiZXR3ZWVuIEdGRSdzIHBsYWNlaG9s
ZGVyIGJveCBhcnQKICAgICAgICAgLy8gYW5kIHRoZSBiYWNrZ3JvdW5kIG9mIHRoZSBhcHAgZ3Jp
ZC4KICAgICAgICAgaWYgKFN5c3RlbVByb3BlcnRpZXMudXNlc01hdGVyaWFsM1RoZW1lKSB7Ci0g
ICAgICAgICAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kID0gVGhlbWUuYmFja2dyb3VuZAorICAgICAg
ICAgICAgLy8gVGhlbWUgcmVtYWlucyBhIGxpdmUgYmluZGluZyB0byB0aGUgc2hhcmVkIHBhbGV0
dGUuCiAgICAgICAgIH0KIAogICAgICAgICAvLyBCcmlkZ2UgdGhlIE1hdGVyaWFsIHN0eWxlIHRv
IHRoZSBWaWJlbWlzIGRlc2lnbiB0b2tlbnMgc28gdGhlCiAgICAgICAgIC8vIE1hdGVyaWFsLXN0
eWxlZCBwYWdlcyAoQ29tcHV0ZXJzIGdyaWQsIEFwcCBncmlkLCBkaWFsb2dzKSBzaGFyZSB0aGUg
c2FtZQogICAgICAgICAvLyBhY2NlbnQvYmFja2dyb3VuZCBzeXN0ZW0gYXMgdGhlIHRva2VuLW5h
dGl2ZSBwYWdlcy4gU2VlIGRvY3MvREVTSUdOX1NZU1RFTS5tZC4KLSAgICAgICAgTWF0ZXJpYWwu
dGhlbWUgPSBNYXRlcmlhbC5EYXJrCi0gICAgICAgIE1hdGVyaWFsLmFjY2VudCA9IFRoZW1lLmFj
Y2VudAorICAgICAgICAvLyBNYXRlcmlhbCB0aGVtZS9hY2NlbnQgYXJlIGJvdW5kIGF0IHRoZSBy
b290LCBpbmNsdWRpbmcgYWZ0ZXIgY2hhbmdlcy4KIAogICAgICAgICBTZGxHYW1lcGFkS2V5TmF2
aWdhdGlvbi5lbmFibGUoKQogICAgIH0KQEAgLTI2Nyw2ICsyODMsMjUgQEAgQXBwbGljYXRpb25X
aW5kb3cgewogICAgICAgICB9CiAgICAgfQogCisgICAgQ3JpbXNvblN0YXR1c0RpYWxvZyB7IGlk
OiBjcmltc29uUGFuZWwgfQorICAgIFN5c3RlbUNvbm5lY3Rpb25zRGlhbG9nIHsgaWQ6IGNvbm5l
Y3Rpb25QYW5lbCB9CisgICAgRWNsaXBzZUFib3V0RGlhbG9nIHsgaWQ6IGVjbGlwc2VBYm91dCB9
CisgICAgRWNsaXBzZUNvbnRyb2xDZW50ZXIgeworICAgICAgICBpZDogZWNsaXBzZUNlbnRlcgor
ICAgICAgICBjYW5NYW5hZ2U6IFN5c3RlbVByb3BlcnRpZXMuaGFzQnJvd3NlcgorICAgICAgICBj
YW5XYWtlOiB0b29sQmFyLm9uUGNWaWV3CisgICAgICAgIG9uV2FrZVJlcXVlc3RlZDogeworICAg
ICAgICAgICAgaWYgKHRvb2xCYXIub25QY1ZpZXcpIHN0YWNrVmlldy5jdXJyZW50SXRlbS5jb21w
dXRlck1vZGVsLndha2VDb21wdXRlcihzdGFja1ZpZXcuY3VycmVudEl0ZW0uY3VycmVudEluZGV4
KQorICAgICAgICB9CisgICAgICAgIG9uTmF2aWdhdGVSZXF1ZXN0ZWQ6IHsKKyAgICAgICAgICAg
IGlmIChkZXN0aW5hdGlvbiA9PT0gIndpZmkiIHx8IGRlc3RpbmF0aW9uID09PSAiYnQiKSB7IGNv
bm5lY3Rpb25QYW5lbC5raW5kID0gZGVzdGluYXRpb247IGNvbm5lY3Rpb25QYW5lbC5vcGVuKCkg
fQorICAgICAgICAgICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJzZXR0aW5ncyIpIG5hdmln
YXRlVG8oInFyYzovZ3VpL1NldHRpbmdzVmlldy5xbWwiLCAiU2V0dGluZ3NWaWV3IikKKyAgICAg
ICAgICAgIGVsc2UgaWYgKGRlc3RpbmF0aW9uID09PSAiaG9zdCIpIHsgQ3JpbXNvblN0YXR1cy5z
ZWxlY3RIb3N0KGVjbGlwc2VDZW50ZXIuaG9zdC5pZCB8fCAiIiwgZWNsaXBzZUNlbnRlci5ob3N0
LnVybCB8fCAiIik7IGNyaW1zb25QYW5lbC5raW5kID0gImhvc3QiOyBjcmltc29uUGFuZWwub3Bl
bigpIH0KKyAgICAgICAgICAgIGVsc2UgaWYgKGRlc3RpbmF0aW9uID09PSAiYWJvdXQiKSB7IGVj
bGlwc2VBYm91dC5pbmZvID0gU3lzdGVtQ29udHJvbHMuc3RhdGU7IGVjbGlwc2VBYm91dC5vcGVu
KCkgfQorICAgICAgICAgICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJtYW5hZ2VtZW50IiAm
JiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIpIFN5c3RlbVByb3BlcnRpZXMub3BlblVybChl
Y2xpcHNlQ2VudGVyLmhvc3QudXJsKQorICAgICAgICB9CisgICAgfQorCiAgICAgaGVhZGVyOiBU
b29sQmFyIHsKICAgICAgICAgaWQ6IHRvb2xCYXIKICAgICAgICAgLy8gUmVkZXNpZ246IEVWRVJZ
IHJlZGVzaWduZWQgbGF1bmNoZXIgc2NyZWVuIChDb21wdXRlcnMsIEFwcCBncmlkLCBTZXR0aW5n
cywgSGVscCkKQEAgLTMzOCwyMCArMzczLDE5IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAg
ICAgLy8gVklCRU1JUyB3b3JkbWFyayAoZGlhbW9uZCArIHdvcmRtYXJrKSwgc2hvd24gb24gdGhl
IENvbXB1dGVycyBzY3JlZW4gaW4gcGxhY2Ugb2YgYSB0aXRsZSwKICAgICAgICAgLy8gbWF0Y2hp
bmcgdGhlIGRlc2lnbiBoZWFkZXIuIExlZnQtYWxpZ25lZCBhdCB0aGUgSFRNTCdzIDQwcHggcGFk
ZGluZy4KICAgICAgICAgUm93IHsKLSAgICAgICAgICAgIHZpc2libGU6IHRvb2xCYXIub25QY1Zp
ZXcKKyAgICAgICAgICAgIHZpc2libGU6IHRvb2xCYXIub25QY1ZpZXcgJiYgdG9vbEJhci53aWR0
aCA+IDgyMAogICAgICAgICAgICAgYW5jaG9ycy5sZWZ0OiBwYXJlbnQubGVmdAogICAgICAgICAg
ICAgYW5jaG9ycy5sZWZ0TWFyZ2luOiA0MAogICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENl
bnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVyCiAgICAgICAgICAgICBzcGFjaW5nOiAxMQotICAg
ICAgICAgICAgUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgIEltYWdlIHsKICAgICAgICAgICAgICAg
ICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIKLSAgICAgICAg
ICAgICAgICB3aWR0aDogMTM7IGhlaWdodDogMTMKLSAgICAgICAgICAgICAgICBjb2xvcjogVmJU
b2tlbnMuYWNjZW50Ci0gICAgICAgICAgICAgICAgcm90YXRpb246IDQ1CisgICAgICAgICAgICAg
ICAgd2lkdGg6IDI4OyBoZWlnaHQ6IDI4CisgICAgICAgICAgICAgICAgc291cmNlOiAicXJjOi9y
ZXMvZWNsaXBzZS1pY29uLnN2ZyIKICAgICAgICAgICAgIH0KICAgICAgICAgICAgIFRleHQgewog
ICAgICAgICAgICAgICAgIGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENl
bnRlcgotICAgICAgICAgICAgICAgIHRleHQ6ICJWSUJFTUlTIgorICAgICAgICAgICAgICAgIHRl
eHQ6ICJFQ0xJUFNFIgogICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250
RGlzcGxheQogICAgICAgICAgICAgICAgIGZvbnQud2VpZ2h0OiBGb250LkV4dHJhQm9sZAogICAg
ICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiAyMQpAQCAtMzY1LDcgKzM5OSw3IEBAIEFwcGxp
Y2F0aW9uV2luZG93IHsKICAgICAgICAgICAgIC8vIEhpZGRlbiBvbiBDb21wdXRlcnMgKHRoZSB3
b3JkbWFyayBzdGFuZHMgaW4pIGFuZCBvbiB0aGUgQXBwIGdyaWQgKHdoaWNoIHNob3dzIGEKICAg
ICAgICAgICAgIC8vIGxlZnQtYWxpZ25lZCBob3N0ICsgc3RhdHVzIGJsb2NrIGluc3RlYWQpLiBP
biBTZXR0aW5ncy9IZWxwIGl0IHNob3dzIHRoZSBzY3JlZW4gbmFtZTsKICAgICAgICAgICAgIC8v
IHRoZSBzdHJlYW1pbmcgc2VndWVzIGtlZXAgdGhlaXIgZGVmYXVsdCBvYmplY3ROYW1lIHRpdGxl
LgotICAgICAgICAgICAgdmlzaWJsZTogIXRvb2xCYXIub25QY1ZpZXcgJiYgIXRvb2xCYXIub25B
cHBWaWV3ICYmIHRvb2xCYXIud2lkdGggPiA3MDAKKyAgICAgICAgICAgIHZpc2libGU6ICF0b29s
QmFyLm9uUGNWaWV3ICYmICF0b29sQmFyLm9uQXBwVmlldyAmJiB0b29sQmFyLndpZHRoID4gODIw
CiAgICAgICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAogICAgICAgICAgICAgdGV4dDogdG9v
bEJhci5vblNldHRpbmdzID8gcXNUcigiU2V0dGluZ3MiKQogICAgICAgICAgICAgICAgIDogdG9v
bEJhci5vbkhlbHAgPyBxc1RyKCJIZWxwIikKQEAgLTQ4Nyw2ICs1MjEsNTQgQEAgQXBwbGljYXRp
b25XaW5kb3cgewogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgIH0KIAorICAgICAgICAg
ICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IG5ldHdvcmtTdGF0
dXNCdXR0b24KKyAgICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1u
ZXR3b3JrLnN2ZyIKKyAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIldpLUZp
IHNldHRpbmdzIikKKyAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAg
ICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIk5ldHdvcms6ICUxIikuYXJnKENyaW1z
b25TdGF0dXMubG9jYWwubmV0d29yayB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAg
ICAgICAgIG9uQ2xpY2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9ICJ3aWZpIjsgY29ubmVj
dGlvblBhbmVsLm9wZW4oKSB9CisgICAgICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBz
dGFja1ZpZXcuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAg
ICAgICAgICAgICBSZWN0YW5nbGUgeworICAgICAgICAgICAgICAgICAgICBhbmNob3JzLnJpZ2h0
OiBwYXJlbnQucmlnaHQ7IGFuY2hvcnMuYm90dG9tOiBwYXJlbnQuYm90dG9tOyBhbmNob3JzLm1h
cmdpbnM6IDUKKyAgICAgICAgICAgICAgICAgICAgd2lkdGg6IDg7IGhlaWdodDogODsgcmFkaXVz
OiA0CisgICAgICAgICAgICAgICAgICAgIGNvbG9yOiBDcmltc29uU3RhdHVzLmxvY2FsLmNvbm5l
Y3RlZCA/IFZiVG9rZW5zLnN0YXR1c09ubGluZSA6IFZiVG9rZW5zLnN0YXR1c09mZmxpbmUKKyAg
ICAgICAgICAgICAgICB9CisgICAgICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29s
QnV0dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogYmx1ZXRvb3RoU2V0dGluZ3NCdXR0b24KKyAg
ICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3Zn
IgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiQmx1ZXRvb3RoIHNldHRp
bmdzIikKKyAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAg
ICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlBhaXIgY29udHJvbGxlcnMgYW5kIGhlYWRwaG9u
ZXMiKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9
ICJidCI7IGNvbm5lY3Rpb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgICAgIEtleXMub25E
b3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFi
Rm9jdXMpCisgICAgICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsK
KyAgICAgICAgICAgICAgICBpZDogYmF0dGVyeVN0YXR1c0J1dHRvbgorICAgICAgICAgICAgICAg
IGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWJhdHRlcnkuc3ZnIgorICAgICAgICAgICAg
ICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiQmF0dGVyeSBzdGF0dXMiKQorICAgICAgICAgICAg
ICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4
dDogQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAwID8gcXNUcigiQmF0dGVy
eTogJTElIOKAoiAlMiIpLmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50KS5h
cmcoQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5U3RhdGUpIDogcXNUcigiQmF0dGVyeSB1bmF2
YWlsYWJsZSIpCisgICAgICAgICAgICAgICAgb25DbGlja2VkOiB7IGNyaW1zb25QYW5lbC5raW5k
ID0gImJhdHRlcnkiOyBjcmltc29uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAgICAgICBLZXlz
Lm9uRG93blByZXNzZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0
LlRhYkZvY3VzKQorICAgICAgICAgICAgfQorICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRv
biB7CisgICAgICAgICAgICAgICAgaWQ6IGhvc3RIYXJkd2FyZUJ1dHRvbgorICAgICAgICAgICAg
ICAgIGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWhvc3Quc3ZnIgorICAgICAgICAgICAg
ICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiVmliZXBvbGxvIGhvc3QgaGFyZHdhcmUgc3RhdHMi
KQorICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAg
ICAgIFRvb2xUaXAudGV4dDogcXNUcigiSG9zdCBDUFUsIFJBTSwgR1BVIGFuZCB0ZW1wZXJhdHVy
ZXMiKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeworICAgICAgICAgICAgICAgICAgICB2
YXIgaXRlbSA9IHN0YWNrVmlldy5jdXJyZW50SXRlbQorICAgICAgICAgICAgICAgICAgICB2YXIg
aG9zdCA9IHRvb2xCYXIub25BcHBWaWV3ID8gaXRlbS5jcmltc29uSG9zdAorICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICA6ICh0b29sQmFyLm9uUGNWaWV3ID8gaXRlbS5jb21wdXRlck1vZGVs
LmNyaW1zb25Ib3N0KGl0ZW0uY3VycmVudEluZGV4KSA6IHt9KQorICAgICAgICAgICAgICAgICAg
ICBDcmltc29uU3RhdHVzLnNlbGVjdEhvc3QoaG9zdC5pZCB8fCAiIiwgaG9zdC51cmwgfHwgIiIp
CisgICAgICAgICAgICAgICAgICAgIGNyaW1zb25QYW5lbC5raW5kID0gImhvc3QiOyBjcmltc29u
UGFuZWwub3BlbigpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEtleXMub25E
b3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFi
Rm9jdXMpCisgICAgICAgICAgICB9CisKICAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24g
ewogICAgICAgICAgICAgICAgIGlkOiBkaXNjb3JkQnV0dG9uCiAgICAgICAgICAgICAgICAgdmlz
aWJsZTogZmFsc2UgLy8gVGVtcG9yYXJpbHkgZGlzYWJsZWQgZm9yIFZpYmVtaXMKQEAgLTU2NCw3
ICs2NDYsNyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgICAgICAgICAgLy8gYW4gaW5z
dGFsbCBmYWlsdXJlIGZhbGxzIGJhY2sgdG8gdGhlIHJlbGVhc2UgcGFnZSBvbiBpdHMgb3duLgog
ICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogQXV0b1VwZGF0ZUNoZWNrZXIuaW5zdGFsbGlu
ZwogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPyBxc1RyKCJEb3dubG9hZGluZyB1cGRh
dGXigKYiKQotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBxc1RyKCJVcGRhdGUgYXZh
aWxhYmxlIGZvciBWaWJlbWlzOiBWZXJzaW9uICUxIOKAlCB0YXAgdG8gaW5zdGFsbCIpLmFyZyhB
dXRvVXBkYXRlQ2hlY2tlci5hdmFpbGFibGVWZXJzaW9uKQorICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgOiBxc1RyKCJVcGRhdGUgYXZhaWxhYmxlIGZvciBFY2xpcHNlOiBWZXJzaW9uICUx
IOKAlCB0YXAgdG8gaW5zdGFsbCIpLmFyZyhBdXRvVXBkYXRlQ2hlY2tlci5hdmFpbGFibGVWZXJz
aW9uKQogCiAgICAgICAgICAgICAgICAgLy8gU3RyaWN0bHktbmV3ZXIgYnVpbGRzIG9ubHkgKGEg
Y2hhbm5lbC1zd2l0Y2ggZG93bmdyYWRlIG9mZmVyCiAgICAgICAgICAgICAgICAgLy8gbGl2ZXMg
aW4gU2V0dGluZ3MsIG5vdCBvbiB0aGUgdG9vbGJhcikuCkBAIC02NDYsNiArNzI4LDIxIEBAIEFw
cGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAKKyAg
ICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBlY2xp
cHNlQ2VudGVyQnV0dG9uCisgICAgICAgICAgICAgICAgaWNvblNvdXJjZTogInFyYzovcmVzL2Vj
bGlwc2UtY29udHJvbHMuc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNU
cigiRWNsaXBzZSBjb250cm9sIGNlbnRlciIpCisgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNp
YmxlOiBob3ZlcmVkCisgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJDb250cm9s
IGNlbnRlciDigKIgQ3RybCtTaGlmdCtDIikKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsK
KyAgICAgICAgICAgICAgICAgICAgdmFyIGl0ZW0gPSBzdGFja1ZpZXcuY3VycmVudEl0ZW0KKyAg
ICAgICAgICAgICAgICAgICAgZWNsaXBzZUNlbnRlci5ob3N0ID0gdG9vbEJhci5vbkFwcFZpZXcg
PyBpdGVtLmNyaW1zb25Ib3N0IDogKHRvb2xCYXIub25QY1ZpZXcgPyBpdGVtLmNvbXB1dGVyTW9k
ZWwuY3JpbXNvbkhvc3QoaXRlbS5jdXJyZW50SW5kZXgpIDoge30pCisgICAgICAgICAgICAgICAg
ICAgIGVjbGlwc2VDZW50ZXIub3BlbigpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAg
ICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZl
Rm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAgICAgICAgU2hvcnRjdXQgeyBzZXF1ZW5jZTog
IkN0cmwrU2hpZnQrQyI7IGVuYWJsZWQ6IHRvb2xCYXIub25QY1ZpZXcgfHwgdG9vbEJhci5vbkFw
cFZpZXc7IG9uQWN0aXZhdGVkOiBlY2xpcHNlQ2VudGVyQnV0dG9uLmNsaWNrZWQoKSB9CisgICAg
ICAgICAgICB9CisKICAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24gewogICAgICAgICAg
ICAgICAgIGlkOiBzZXR0aW5nc0J1dHRvbgogCkBAIC02NzMsNyArNzcwLDcgQEAgQXBwbGljYXRp
b25XaW5kb3cgewogCiAgICAgRXJyb3JNZXNzYWdlRGlhbG9nIHsKICAgICAgICAgaWQ6IG5vSHdE
ZWNvZGVyRGlhbG9nCi0gICAgICAgIHRleHQ6IHFzVHIoIk5vIGZ1bmN0aW9uaW5nIGhhcmR3YXJl
IGFjY2VsZXJhdGVkIHZpZGVvIGRlY29kZXIgd2FzIGRldGVjdGVkIGJ5IFZpYmVtaXMuICIgKwor
ICAgICAgICB0ZXh0OiBxc1RyKCJObyBmdW5jdGlvbmluZyBoYXJkd2FyZSBhY2NlbGVyYXRlZCB2
aWRlbyBkZWNvZGVyIHdhcyBkZXRlY3RlZCBieSBFY2xpcHNlLiAiICsKICAgICAgICAgICAgICAg
ICAgICAiWW91ciBzdHJlYW1pbmcgcGVyZm9ybWFuY2UgbWF5IGJlIHNldmVyZWx5IGRlZ3JhZGVk
IGluIHRoaXMgY29uZmlndXJhdGlvbi4iKQogICAgICAgICBoZWxwVGV4dDogcXNUcigiQ2xpY2sg
dGhlIEhlbHAgYnV0dG9uIGZvciBtb3JlIGluZm9ybWF0aW9uIG9uIHNvbHZpbmcgdGhpcyBwcm9i
bGVtLiIpCiAgICAgICAgIGhlbHBVcmw6ICJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3Zp
YmVtaXMiCkBAIC02OTAsNyArNzg3LDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgIE5hdmln
YWJsZU1lc3NhZ2VEaWFsb2cgewogICAgICAgICBpZDogd293NjREaWFsb2cKICAgICAgICAgc3Rh
bmRhcmRCdXR0b25zOiBEaWFsb2cuT2sgfCBEaWFsb2cuQ2FuY2VsCi0gICAgICAgIHRleHQ6IHFz
VHIoIlRoaXMgdmVyc2lvbiBvZiBWaWJlbWlzIGlzbid0IG9wdGltaXplZCBmb3IgeW91ciBQQy4g
UGxlYXNlIGRvd25sb2FkIHRoZSAnJTEnIHZlcnNpb24gb2YgVmliZW1pcyBmb3IgdGhlIGJlc3Qg
c3RyZWFtaW5nIHBlcmZvcm1hbmNlLiIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLmZyaWVuZGx5TmF0
aXZlQXJjaE5hbWUpCisgICAgICAgIHRleHQ6IHFzVHIoIlRoaXMgdmVyc2lvbiBvZiBFY2xpcHNl
IGlzbid0IG9wdGltaXplZCBmb3IgeW91ciBQQy4gUGxlYXNlIGRvd25sb2FkIHRoZSAnJTEnIHZl
cnNpb24gb2YgRWNsaXBzZSBmb3IgdGhlIGJlc3Qgc3RyZWFtaW5nIHBlcmZvcm1hbmNlLiIpLmFy
ZyhTeXN0ZW1Qcm9wZXJ0aWVzLmZyaWVuZGx5TmF0aXZlQXJjaE5hbWUpCiAgICAgICAgIG9uQWNj
ZXB0ZWQ6IHsKICAgICAgICAgICAgIFN5c3RlbVByb3BlcnRpZXMub3BlblVybCgiaHR0cHM6Ly9n
aXRodWIuY29tL25hdnlhczMyMS92aWJlbWlzL3JlbGVhc2VzIik7CiAgICAgICAgIH0KQEAgLTY5
OSw3ICs3OTYsNyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgRXJyb3JNZXNzYWdlRGlhbG9n
IHsKICAgICAgICAgaWQ6IHVubWFwcGVkR2FtZXBhZERpYWxvZwogICAgICAgICBwcm9wZXJ0eSBz
dHJpbmcgdW5tYXBwZWRHYW1lcGFkcyA6ICIiCi0gICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMg
ZGV0ZWN0ZWQgZ2FtZXBhZHMgd2l0aG91dCBhIG1hcHBpbmc6IikgKyAiXG4iICsgdW5tYXBwZWRH
YW1lcGFkcworICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIGRldGVjdGVkIGdhbWVwYWRzIHdp
dGhvdXQgYSBtYXBwaW5nOiIpICsgIlxuIiArIHVubWFwcGVkR2FtZXBhZHMKICAgICAgICAgaGVs
cFRleHRTZXBhcmF0b3I6ICJcblxuIgogICAgICAgICBoZWxwVGV4dDogcXNUcigiQ2xpY2sgdGhl
IEhlbHAgYnV0dG9uIGZvciBpbmZvcm1hdGlvbiBvbiBob3cgdG8gbWFwIHlvdXIgZ2FtZXBhZHMu
IikKICAgICAgICAgaGVscFVybDogImh0dHBzOi8vZ2l0aHViLmNvbS9uYXZ5YXMzMjEvdmliZW1p
cyIKZGlmZiAtLWdpdCBhL2FwcC9tYWluLmNwcCBiL2FwcC9tYWluLmNwcAppbmRleCAyOTIyMjc3
Li4zZWM5NGRiIDEwMDY0NAotLS0gYS9hcHAvbWFpbi5jcHAKKysrIGIvYXBwL21haW4uY3BwCkBA
IC04NjksNiArODY5LDcgQEAgaW50IG1haW4oaW50IGFyZ2MsIGNoYXIgKmFyZ3ZbXSkKICAgICB9
DQogDQogICAgIFFHdWlBcHBsaWNhdGlvbiBhcHAoYXJnYywgYXJndik7DQorICAgIFFHdWlBcHBs
aWNhdGlvbjo6c2V0QXBwbGljYXRpb25EaXNwbGF5TmFtZSgiRWNsaXBzZSIpOwogDQogICAgIC8v
IFZpYmVtaXM6IHRoZSBRdCBRdWljayBDb250cm9scyBNYXRlcmlhbCBzdHlsZSByZW5kZXJzIGJ1
dHRvbiB0ZXh0IGluIEFMTCBDQVBTIGJ5IGRlZmF1bHQNCiAgICAgLy8gKGUuZy4gdGhlIGJpdHJh
dGUgIlVTRSBERUZBVUxUICgzMCBNQlBTKSIgYnV0dG9uKSwgd2hpY2ggbG9va3Mgb2ZmLiBGb3Jj
ZSBtaXhlZCBjYXNlIGZvciB0aGUNCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNv
bnN0YXR1cy5jcHAgYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5jcHAKbmV3IGZpbGUg
bW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uZGFmY2EyZQotLS0gL2Rldi9udWxsCisrKyBiL2Fw
cC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcApAQCAtMCwwICsxLDIyMiBAQAorI2luY2x1
ZGUgImNyaW1zb25zdGF0dXMuaCIKKyNpbmNsdWRlIDxRRGF0ZVRpbWU+CisjaW5jbHVkZSA8UURp
cj4KKyNpbmNsdWRlIDxRRmlsZT4KKyNpbmNsdWRlIDxRSnNvbkRvY3VtZW50PgorI2luY2x1ZGUg
PFFKc29uT2JqZWN0PgorI2luY2x1ZGUgPFFOZXR3b3JrSW50ZXJmYWNlPgorI2luY2x1ZGUgPFFO
ZXR3b3JrUmVxdWVzdD4KKyNpbmNsdWRlIDxRU2F2ZUZpbGU+CisjaW5jbHVkZSA8UVNzbENlcnRp
ZmljYXRlPgorI2luY2x1ZGUgPFFTc2xFcnJvcj4KKyNpbmNsdWRlIDxRU3RhbmRhcmRQYXRocz4K
KyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVkZSA8UVVybD4KKyNpbmNsdWRl
IDxjbWF0aD4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFDb3JlQXBwbGljYXRp
b24+CisjaW5jbHVkZSA8bWVtb3J5PgorI2luY2x1ZGUgPFFSZWd1bGFyRXhwcmVzc2lvbj4KKyNp
bmNsdWRlIDxRRmlsZUluZm8+CisjaW5jbHVkZSA8UVNzbENvbmZpZ3VyYXRpb24+CisKK25hbWVz
cGFjZSB7CitRU3RyaW5nIHJlYWQoY29uc3QgUVN0cmluZyYgcGF0aCkgeworICAgIFFGaWxlIGYo
cGF0aCk7IHJldHVybiBmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkgPyBRU3RyaW5nOjpmcm9t
VXRmOChmLnJlYWRBbGwoKSkudHJpbW1lZCgpIDogUVN0cmluZygpOworfQorY29uc3QgYXV0byB1
c2VyT25seSA9IFFGaWxlRGV2aWNlOjpSZWFkT3duZXIgfCBRRmlsZURldmljZTo6V3JpdGVPd25l
cjsKK30KK0NyaW1zb25TdGF0dXM6OkNyaW1zb25TdGF0dXMoUU9iamVjdCogcGFyZW50KSA6IFFP
YmplY3QocGFyZW50KSB7CisgICAgY29ubmVjdCgmbV9sb2NhbFRpbWVyLCAmUVRpbWVyOjp0aW1l
b3V0LCB0aGlzLCAmQ3JpbXNvblN0YXR1czo6cmVmcmVzaExvY2FsKTsKKyAgICBjb25uZWN0KCZt
X3N0YXRzVGltZXIsICZRVGltZXI6OnRpbWVvdXQsIHRoaXMsICZDcmltc29uU3RhdHVzOjpyZWZy
ZXNoKTsKKyAgICBjb25uZWN0KCZtX3dpZmksICZRUHJvY2Vzczo6ZmluaXNoZWQsIHRoaXMsIFt0
aGlzXShpbnQgZXhpdCwgUVByb2Nlc3M6OkV4aXRTdGF0dXMpIHsKKyAgICAgICAgaWYgKGV4aXQg
PT0gMCkgeworICAgICAgICAgICAgY29uc3QgYXV0byBsaW5lcyA9IFFTdHJpbmc6OmZyb21VdGY4
KG1fd2lmaS5yZWFkQWxsU3RhbmRhcmRPdXRwdXQoKSkuc3BsaXQoJ1xuJyk7CisgICAgICAgICAg
ICBmb3IgKGNvbnN0IGF1dG8mIGxpbmUgOiBsaW5lcykgeworICAgICAgICAgICAgICAgIGlmICgh
bGluZS5zdGFydHNXaXRoKCJ5ZXM6IikpIGNvbnRpbnVlOworICAgICAgICAgICAgICAgIGludCBz
ZXBhcmF0b3IgPSBsaW5lLmluZGV4T2YoJzonLCA0KTsgYm9vbCBvayA9IGZhbHNlOworICAgICAg
ICAgICAgICAgIGludCBzaWduYWwgPSBsaW5lLm1pZCg0LCBzZXBhcmF0b3IgLSA0KS50b0ludCgm
b2spOworICAgICAgICAgICAgICAgIGlmIChvayAmJiBzaWduYWwgPj0gMCAmJiBzaWduYWwgPD0g
MTAwKSBtX2xvY2FsWyJ3aWZpU2lnbmFsIl0gPSBzaWduYWw7CisgICAgICAgICAgICAgICAgaWYg
KHNlcGFyYXRvciA+PSAwKSBtX2xvY2FsWyJuZXR3b3JrIl0gPSB0cigiV2ktRmk6ICUxIikuYXJn
KGxpbmUubWlkKHNlcGFyYXRvciArIDEpKTsKKyAgICAgICAgICAgICAgICBicmVhazsKKyAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgIGVtaXQgbG9jYWxDaGFuZ2VkKCk7CisgICAgICAgIH0KKyAg
ICB9KTsKKyAgICBtX2xvY2FsVGltZXIuc3RhcnQoMTAwMDApOyBtX3N0YXRzVGltZXIuc2V0SW50
ZXJ2YWwoMjAwMCk7IHJlZnJlc2hMb2NhbCgpOworfQorQ3JpbXNvblN0YXR1czo6fkNyaW1zb25T
dGF0dXMoKSB7CisgICAgbV9zdGF0c1RpbWVyLnN0b3AoKTsgbV9sb2NhbFRpbWVyLnN0b3AoKTsg
Y2FuY2VsKCk7CisgICAgaWYgKG1fd2lmaS5zdGF0ZSgpICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5n
KSB7IG1fd2lmaS5raWxsKCk7IG1fd2lmaS53YWl0Rm9yRmluaXNoZWQoNTAwKTsgfQorfQorUVN0
cmluZyBDcmltc29uU3RhdHVzOjpjb25maWdGaWxlKCkgY29uc3QgeworICAgIHJldHVybiBRU3Rh
bmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRhcmRQYXRoczo6QXBwQ29uZmlnTG9j
YXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpzb24iOworfQorUVN0cmluZyBDcmltc29uU3RhdHVz
Ojpub3JtYWxpemVkUGluKFFTdHJpbmcgcGluKSB7CisgICAgcGluLnJlbW92ZSgnOicpOyBwaW4u
cmVtb3ZlKCcgJyk7IHJldHVybiBwaW4udG9Mb3dlcigpOworfQorYm9vbCBDcmltc29uU3RhdHVz
Ojp2YWxpZEVuZHBvaW50KGNvbnN0IFFTdHJpbmcmIHZhbHVlKSB7CisgICAgUVVybCB1KHZhbHVl
LCBRVXJsOjpTdHJpY3RNb2RlKTsKKyAgICByZXR1cm4gdS5pc1ZhbGlkKCkgJiYgdS5zY2hlbWUo
KSA9PSAiaHR0cHMiICYmICF1Lmhvc3QoKS5pc0VtcHR5KCkgJiYKKyAgICAgICAgdS51c2VySW5m
bygpLmlzRW1wdHkoKSAmJiB1LnF1ZXJ5KCkuaXNFbXB0eSgpICYmIHUuZnJhZ21lbnQoKS5pc0Vt
cHR5KCkgJiYKKyAgICAgICAgKHUucGF0aCgpLmlzRW1wdHkoKSB8fCB1LnBhdGgoKSA9PSAiLyIp
ICYmIHUucG9ydCg0Nzk5MCkgPiAwOworfQordm9pZCBDcmltc29uU3RhdHVzOjpjYW5jZWwoKSB7
CisgICAgaWYgKG1fcmVwbHkpIHsgZGlzY29ubmVjdChtX3JlcGx5LCBudWxscHRyLCB0aGlzLCBu
dWxscHRyKTsgbV9yZXBseS0+YWJvcnQoKTsgbV9yZXBseS0+ZGVsZXRlTGF0ZXIoKTsgbV9yZXBs
eSA9IG51bGxwdHI7IH0KK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6c2VsZWN0SG9zdChRU3RyaW5n
IGlkLCBRU3RyaW5nIHN1Z2dlc3RlZFVybCkgeworICAgIGlmIChpZCA9PSBtX2hvc3QpIHJldHVy
bjsKKyAgICBjYW5jZWwoKTsgbV9uZXR3b3JrLmNsZWFyQ29ubmVjdGlvbkNhY2hlKCk7IG1faG9z
dCA9IGlkOyBtX3Rva2VuLmNsZWFyKCk7IG1fcGluLmNsZWFyKCk7CisgICAgbV9lbmRwb2ludCA9
IHZhbGlkRW5kcG9pbnQoc3VnZ2VzdGVkVXJsKSA/IHN1Z2dlc3RlZFVybCA6IFFTdHJpbmcoKTsK
KyAgICBRRmlsZSBmKGNvbmZpZ0ZpbGUoKSk7CisgICAgaWYgKGYub3BlbihRSU9EZXZpY2U6OlJl
YWRPbmx5KSkgeworICAgICAgICBhdXRvIGMgPSBRSnNvbkRvY3VtZW50Ojpmcm9tSnNvbihmLnJl
YWRBbGwoKSkub2JqZWN0KCkudmFsdWUoaWQpLnRvT2JqZWN0KCk7CisgICAgICAgIGlmICh2YWxp
ZEVuZHBvaW50KGMudmFsdWUoInVybCIpLnRvU3RyaW5nKCkpKSB7CisgICAgICAgICAgICBtX2Vu
ZHBvaW50ID0gYy52YWx1ZSgidXJsIikudG9TdHJpbmcoKTsgbV90b2tlbiA9IGMudmFsdWUoInRv
a2VuIikudG9TdHJpbmcoKTsgbV9waW4gPSBjLnZhbHVlKCJwaW4iKS50b1N0cmluZygpOworICAg
ICAgICB9CisgICAgfQorICAgIG1fc3RhdHMuY2xlYXIoKTsgbV9zdGF0dXMgPSBpZC5pc0VtcHR5
KCkgPyB0cigiQ2hvb3NlIGEgaG9zdCB0byB2aWV3IGhhcmR3YXJlIHN0YXRzIikgOiB0cigiQ29u
ZmlndXJlIGEgVmliZXBvbGxvIHJlYWQtb25seSBzdGF0cyB0b2tlbiIpOworICAgIGVtaXQgY29u
ZmlnQ2hhbmdlZCgpOyBlbWl0IHN0YXRzQ2hhbmdlZCgpOyBpZiAobV92aXNpYmxlKSByZWZyZXNo
KCk7Cit9Citib29sIENyaW1zb25TdGF0dXM6OmNvbmZpZ3VyZShRU3RyaW5nIHVybCwgUVN0cmlu
ZyB0b2tlbiwgUVN0cmluZyBwaW4pIHsKKyAgICBwaW4gPSBub3JtYWxpemVkUGluKHBpbik7Cisg
ICAgaWYgKG1faG9zdC5pc0VtcHR5KCkgfHwgIXZhbGlkRW5kcG9pbnQodXJsKSB8fCAoIXBpbi5p
c0VtcHR5KCkgJiYKKyAgICAgICAgKHBpbi5zaXplKCkgIT0gNjQgfHwgcGluLmNvbnRhaW5zKFFS
ZWd1bGFyRXhwcmVzc2lvbigiW14wLTlhLWZdIikpKSkpIHsKKyAgICAgICAgZmFpbCh0cigiVXNl
IGFuIEhUVFBTIGhvc3QgVVJMIGFuZCBhbiBvcHRpb25hbCA2NC1kaWdpdCBTSEEtMjU2IGNlcnRp
ZmljYXRlIGZpbmdlcnByaW50IikpOyByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIC8vIEEgYmxh
bmsgdG9rZW4ga2VlcHMgdGhlIG9sZCB0b2tlbiBvbmx5IGZvciB0aGUgc2FtZSBlbmRwb2ludC4K
KyAgICBpZiAodG9rZW4uaXNFbXB0eSgpICYmIFFVcmwodXJsKSA9PSBRVXJsKG1fZW5kcG9pbnQp
KSB0b2tlbiA9IG1fdG9rZW47CisgICAgaWYgKHRva2VuLmlzRW1wdHkoKSB8fCB0b2tlbi5jb250
YWlucygnXHInKSB8fCB0b2tlbi5jb250YWlucygnXG4nKSB8fCB0b2tlbi5zaXplKCkgPiA0MDk2
KSB7CisgICAgICAgIGZhaWwodHIoIkEgcmVhZC1vbmx5IFZpYmVwb2xsbyBBUEkgdG9rZW4gaXMg
cmVxdWlyZWQiKSk7IHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgUUZpbGUgZihjb25maWdGaWxl
KCkpOyBRSnNvbk9iamVjdCBhbGw7CisgICAgaWYgKGYub3BlbihRSU9EZXZpY2U6OlJlYWRPbmx5
KSkgYWxsID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24oZi5yZWFkQWxsKCkpLm9iamVjdCgpOwor
ICAgIGFsbFttX2hvc3RdID0gUUpzb25PYmplY3R7eyJ1cmwiLCB1cmx9LCB7InRva2VuIiwgdG9r
ZW59LCB7InBpbiIsIHBpbn19OworICAgIFFEaXIoKS5ta3BhdGgoUUZpbGVJbmZvKGNvbmZpZ0Zp
bGUoKSkuYWJzb2x1dGVQYXRoKCkpOworICAgIFFTYXZlRmlsZSBvdXQoY29uZmlnRmlsZSgpKTsK
KyAgICBpZiAoIW91dC5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSB8fCAhb3V0LnNldFBlcm1p
c3Npb25zKHVzZXJPbmx5KSB8fAorICAgICAgICBvdXQud3JpdGUoUUpzb25Eb2N1bWVudChhbGwp
LnRvSnNvbigpKSA8IDAgfHwgIW91dC5jb21taXQoKSkgeworICAgICAgICBmYWlsKHRyKCJDb3Vs
ZCBub3Qgc2F2ZSBob3N0IGFjY2VzcyBzZXR0aW5ncyIpKTsgcmV0dXJuIGZhbHNlOworICAgIH0K
KyAgICBjYW5jZWwoKTsgbV9uZXR3b3JrLmNsZWFyQ29ubmVjdGlvbkNhY2hlKCk7IG1fZW5kcG9p
bnQgPSB1cmw7IG1fdG9rZW4gPSB0b2tlbjsgbV9waW4gPSBwaW47CisgICAgbV9zdGF0c1RpbWVy
LnNldEludGVydmFsKDIwMDApOworICAgIG1fc3RhdHMuY2xlYXIoKTsgbV9zdGF0dXMgPSB0cigi
Q29ubmVjdGluZyB0byBob3N0IHN0YXRz4oCmIik7CisgICAgZW1pdCBjb25maWdDaGFuZ2VkKCk7
IGVtaXQgc3RhdHNDaGFuZ2VkKCk7IHJlZnJlc2goKTsgcmV0dXJuIHRydWU7Cit9Cit2b2lkIENy
aW1zb25TdGF0dXM6OnNldFZpc2libGUoYm9vbCB2aXNpYmxlKSB7CisgICAgbV92aXNpYmxlID0g
dmlzaWJsZTsKKyAgICBpZiAodmlzaWJsZSkgeyByZWZyZXNoTG9jYWwoKTsgbV9zdGF0c1RpbWVy
LnN0YXJ0KCk7IHJlZnJlc2goKTsgfQorICAgIGVsc2UgeyBtX3N0YXRzVGltZXIuc3RvcCgpOyBj
YW5jZWwoKTsgfQorfQordm9pZCBDcmltc29uU3RhdHVzOjpmYWlsKFFTdHJpbmcgbWVzc2FnZSkg
eworICAgIG1fc3RhdHMuY2xlYXIoKTsgbV9zdGF0dXMgPSBtZXNzYWdlOworICAgIG1fc3RhdHNU
aW1lci5zZXRJbnRlcnZhbChxTWluKDMwMDAwLCBxTWF4KDQwMDAsIG1fc3RhdHNUaW1lci5pbnRl
cnZhbCgpICogMikpKTsKKyAgICBlbWl0IHN0YXRzQ2hhbmdlZCgpOworfQorUVZhcmlhbnRNYXAg
Q3JpbXNvblN0YXR1czo6cGFyc2VTdGF0cyhjb25zdCBRQnl0ZUFycmF5JiBieXRlcywgUVN0cmlu
ZyogZXJyb3IpIHsKKyAgICBpZiAoYnl0ZXMuc2l6ZSgpID4gNjU1MzYpIHsgKmVycm9yID0gIk92
ZXJzaXplZCBob3N0IHN0YXRzIHJlc3BvbnNlIjsgcmV0dXJuIHt9OyB9CisgICAgUUpzb25QYXJz
ZUVycm9yIGU7IGF1dG8gZG9jID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24oYnl0ZXMsICZlKTsK
KyAgICBpZiAoZS5lcnJvciAhPSBRSnNvblBhcnNlRXJyb3I6Ok5vRXJyb3IgfHwgIWRvYy5pc09i
amVjdCgpKSB7ICplcnJvciA9ICJJbnZhbGlkIGhvc3Qgc3RhdHMgcmVzcG9uc2UiOyByZXR1cm4g
e307IH0KKyAgICBhdXRvIG9iaiA9IGRvYy5vYmplY3QoKTsgUVZhcmlhbnRNYXAgcmVzdWx0Owor
ICAgIGNvbnN0IFFTdHJpbmdMaXN0IGtleXMgPSB7ImNwdV9wZXJjZW50IiwiY3B1X3RlbXBfYyIs
InJhbV91c2VkX2J5dGVzIiwicmFtX3RvdGFsX2J5dGVzIiwicmFtX3BlcmNlbnQiLAorICAgICAg
ICAiZ3B1X3BlcmNlbnQiLCJncHVfZW5jb2Rlcl9wZXJjZW50IiwiZ3B1X3RlbXBfYyIsInZyYW1f
dXNlZF9ieXRlcyIsInZyYW1fdG90YWxfYnl0ZXMiLCJ2cmFtX3BlcmNlbnQiLCJuZXRfcnhfYnBz
IiwibmV0X3R4X2JwcyJ9OworICAgIGJvb2wgcmVjb2duaXplZCA9IGZhbHNlOworICAgIGZvciAo
Y29uc3QgYXV0byYga2V5IDoga2V5cykgeworICAgICAgICBhdXRvIHYgPSBvYmoudmFsdWUoa2V5
KTsgcmVjb2duaXplZCB8PSBvYmouY29udGFpbnMoa2V5KTsKKyAgICAgICAgZG91YmxlIG4gPSB2
LnRvRG91YmxlKC0xKTsKKyAgICAgICAgaWYgKCF2LmlzRG91YmxlKCkgfHwgIXN0ZDo6aXNmaW5p
dGUobikgfHwgbiA8IDAgfHwgKGtleS5lbmRzV2l0aCgicGVyY2VudCIpICYmIG4gPiAxMDApKSBj
b250aW51ZTsKKyAgICAgICAgcmVzdWx0W2tleV0gPSBuOworICAgIH0KKyAgICBmb3IgKGNvbnN0
IGF1dG8mIHByZWZpeCA6IHtRU3RyaW5nKCJyYW0iKSwgUVN0cmluZygidnJhbSIpfSkgeworICAg
ICAgICBkb3VibGUgdG90YWwgPSByZXN1bHQudmFsdWUocHJlZml4ICsgIl90b3RhbF9ieXRlcyIp
LnRvRG91YmxlKCk7CisgICAgICAgIGlmICh0b3RhbCA8PSAwKSB7IHJlc3VsdC5yZW1vdmUocHJl
Zml4ICsgIl9wZXJjZW50Iik7IHJlc3VsdC5yZW1vdmUocHJlZml4ICsgIl91c2VkX2J5dGVzIik7
IH0KKyAgICAgICAgZWxzZSBpZiAocmVzdWx0LmNvbnRhaW5zKHByZWZpeCArICJfdXNlZF9ieXRl
cyIpKSB7CisgICAgICAgICAgICBkb3VibGUgdXNlZCA9IHFNaW4ocmVzdWx0LnZhbHVlKHByZWZp
eCArICJfdXNlZF9ieXRlcyIpLnRvRG91YmxlKCksIHRvdGFsKTsKKyAgICAgICAgICAgIHJlc3Vs
dFtwcmVmaXggKyAiX3VzZWRfYnl0ZXMiXSA9IHVzZWQ7IHJlc3VsdFtwcmVmaXggKyAiX3BlcmNl
bnQiXSA9IHVzZWQgKiAxMDAgLyB0b3RhbDsKKyAgICAgICAgfQorICAgIH0KKyAgICBpZiAoIXJl
Y29nbml6ZWQpIHsgKmVycm9yID0gIkhvc3QgZG9lcyBub3QgZXhwb3NlIHRoZSBleHBlY3RlZCBW
aWJlcG9sbG8gc3RhdHMgZmllbGRzIjsgcmV0dXJuIHt9OyB9CisgICAgZXJyb3ItPmNsZWFyKCk7
IHJldHVybiByZXN1bHQ7Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OnJlZnJlc2goKSB7CisgICAg
aWYgKCFtX3Zpc2libGUgfHwgbV9yZXBseSB8fCAhY29uZmlndXJlZCgpKSByZXR1cm47CisgICAg
UVVybCB1cmwobV9lbmRwb2ludCk7IHVybC5zZXRQYXRoKCIvYXBpL2hvc3Qvc3RhdHMiKTsKKyAg
ICBRTmV0d29ya1JlcXVlc3QgcmVxKHVybCk7CisgICAgcmVxLnNldEF0dHJpYnV0ZShRTmV0d29y
a1JlcXVlc3Q6OlJlZGlyZWN0UG9saWN5QXR0cmlidXRlLCBRTmV0d29ya1JlcXVlc3Q6Ok1hbnVh
bFJlZGlyZWN0UG9saWN5KTsKKyAgICByZXEuc2V0VHJhbnNmZXJUaW1lb3V0KDMwMDApOworICAg
IHJlcS5zZXRSYXdIZWFkZXIoIkF1dGhvcml6YXRpb24iLCAiQmVhcmVyICIgKyBtX3Rva2VuLnRv
VXRmOCgpKTsKKyAgICByZXEuc2V0UmF3SGVhZGVyKCJBY2NlcHQiLCAiYXBwbGljYXRpb24vanNv
biIpOworICAgIGF1dG8gcmVwbHkgPSBtX25ldHdvcmsuZ2V0KHJlcSk7IHJlcGx5LT5zZXRSZWFk
QnVmZmVyU2l6ZSg2NTUzNik7IG1fcmVwbHkgPSByZXBseTsKKyAgICBhdXRvIGRhdGEgPSBzdGQ6
Om1ha2Vfc2hhcmVkPFFCeXRlQXJyYXk+KCk7CisgICAgYXV0byBpbnZhbGlkUGluID0gc3RkOjpt
YWtlX3NoYXJlZDxib29sPihmYWxzZSk7CisgICAgYXV0byBvdmVyc2l6ZWQgPSBzdGQ6Om1ha2Vf
c2hhcmVkPGJvb2w+KGZhbHNlKTsKKyAgICBhdXRvIGNlcnRNYXRjaGVzID0gW3RoaXMsIHJlcGx5
XSB7CisgICAgICAgIHJldHVybiBub3JtYWxpemVkUGluKFFTdHJpbmc6OmZyb21MYXRpbjEocmVw
bHktPnNzbENvbmZpZ3VyYXRpb24oKS5wZWVyQ2VydGlmaWNhdGUoKS5kaWdlc3QoUUNyeXB0b2dy
YXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpKSA9PSBtX3BpbjsKKyAgICB9OworICAgIGNvbm5l
Y3QocmVwbHksICZRTmV0d29ya1JlcGx5OjplbmNyeXB0ZWQsIHRoaXMsIFt0aGlzLCByZXBseSwg
Y2VydE1hdGNoZXMsIGludmFsaWRQaW5dIHsKKyAgICAgICAgaWYgKCFtX3Bpbi5pc0VtcHR5KCkg
JiYgIWNlcnRNYXRjaGVzKCkpIHsgKmludmFsaWRQaW4gPSB0cnVlOyByZXBseS0+YWJvcnQoKTsg
fQorICAgIH0pOworICAgIGNvbm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5Ojpzc2xFcnJvcnMs
IHRoaXMsIFt0aGlzLCByZXBseSwgY2VydE1hdGNoZXNdKGNvbnN0IFFMaXN0PFFTc2xFcnJvcj4m
IGVycm9ycykgeworICAgICAgICBpZiAobV9waW4uaXNFbXB0eSgpIHx8ICFjZXJ0TWF0Y2hlcygp
KSByZXR1cm47CisgICAgICAgIGZvciAoY29uc3QgYXV0byYgZSA6IGVycm9ycykgeworICAgICAg
ICAgICAgaWYgKGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6OlNlbGZTaWduZWRDZXJ0aWZpY2F0ZSAm
JiBlLmVycm9yKCkgIT0gUVNzbEVycm9yOjpTZWxmU2lnbmVkQ2VydGlmaWNhdGVJbkNoYWluICYm
CisgICAgICAgICAgICAgICAgZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6Q2VydGlmaWNhdGVVbnRy
dXN0ZWQgJiYgZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6SG9zdE5hbWVNaXNtYXRjaCkgcmV0dXJu
OworICAgICAgICB9CisgICAgICAgIHJlcGx5LT5pZ25vcmVTc2xFcnJvcnMoZXJyb3JzKTsgLy8g
T25seSB0aGlzIGV4cGxpY2l0bHkgcGlubmVkIGhvc3QgY2VydGlmaWNhdGUuCisgICAgfSk7Cisg
ICAgY29ubmVjdChyZXBseSwgJlFOZXR3b3JrUmVwbHk6OnJlYWR5UmVhZCwgdGhpcywgW3JlcGx5
LCBkYXRhLCBvdmVyc2l6ZWRdIHsKKyAgICAgICAgaWYgKCpvdmVyc2l6ZWQgfHwgcmVwbHktPmlz
RmluaXNoZWQoKSkgcmV0dXJuOworICAgICAgICBpZiAoZGF0YS0+c2l6ZSgpICsgcmVwbHktPmJ5
dGVzQXZhaWxhYmxlKCkgPiA2NTUzNikgeyAqb3ZlcnNpemVkID0gdHJ1ZTsgcmVwbHktPmFib3J0
KCk7IHJldHVybjsgfQorICAgICAgICBkYXRhLT5hcHBlbmQocmVwbHktPnJlYWRBbGwoKSk7Cisg
ICAgfSk7CisgICAgY29ubmVjdChyZXBseSwgJlFOZXR3b3JrUmVwbHk6OmZpbmlzaGVkLCB0aGlz
LCBbdGhpcywgcmVwbHksIGRhdGEsIGludmFsaWRQaW4sIG92ZXJzaXplZF0geworICAgICAgICBt
X3JlcGx5ID0gbnVsbHB0cjsKKyAgICAgICAgaW50IHN0YXR1cyA9IHJlcGx5LT5hdHRyaWJ1dGUo
UU5ldHdvcmtSZXF1ZXN0OjpIdHRwU3RhdHVzQ29kZUF0dHJpYnV0ZSkudG9JbnQoKTsKKyAgICAg
ICAgaWYgKCpvdmVyc2l6ZWQpIGZhaWwodHIoIkhvc3Qgc3RhdHMgcmVzcG9uc2UgZXhjZWVkZWQg
dGhlIHNpemUgbGltaXQiKSk7CisgICAgICAgIGVsc2UgaWYgKCppbnZhbGlkUGluKSBmYWlsKHRy
KCJIb3N0IGNlcnRpZmljYXRlIGNoYW5nZWQ7IHZlcmlmeSB0aGUgc2F2ZWQgZmluZ2VycHJpbnQi
KSk7CisgICAgICAgIGVsc2UgaWYgKHN0YXR1cyA9PSA0MDEgfHwgc3RhdHVzID09IDQwMykgZmFp
bCh0cigiSG9zdCBzdGF0cyBhY2Nlc3MgZGVuaWVkOiBjaGVjayB0aGUgcmVhZC1vbmx5IHRva2Vu
IikpOworICAgICAgICBlbHNlIGlmIChzdGF0dXMgPT0gNDA0KSBmYWlsKHRyKCJUaGlzIGhvc3Qg
ZG9lcyBub3QgcHJvdmlkZSBWaWJlcG9sbG8gaGFyZHdhcmUgc3RhdHMiKSk7CisgICAgICAgIGVs
c2UgaWYgKHJlcGx5LT5lcnJvcigpID09IFFOZXR3b3JrUmVwbHk6OlNzbEhhbmRzaGFrZUZhaWxl
ZEVycm9yKSBmYWlsKHRyKCJWZXJpZnkgdGhlIGhvc3QgY2VydGlmaWNhdGUgZmluZ2VycHJpbnQg
aW4gQ29uZmlndXJlIikpOworICAgICAgICBlbHNlIGlmIChyZXBseS0+ZXJyb3IoKSAhPSBRTmV0
d29ya1JlcGx5OjpOb0Vycm9yIHx8IHN0YXR1cyAhPSAyMDApIGZhaWwodHIoIkhvc3Qgc3RhdHMg
dW5hdmFpbGFibGU6IGNoZWNrIGNvbm5lY3Rpb24gYW5kIHJlYWx0aW1lIHN0YXRzIHNldHRpbmci
KSk7CisgICAgICAgIGVsc2UgeworICAgICAgICAgICAgZGF0YS0+YXBwZW5kKHJlcGx5LT5yZWFk
QWxsKCkpOyBRU3RyaW5nIGVycm9yOworICAgICAgICAgICAgYXV0byBwYXJzZWQgPSBwYXJzZVN0
YXRzKCpkYXRhLCAmZXJyb3IpOworICAgICAgICAgICAgaWYgKCFlcnJvci5pc0VtcHR5KCkpIGZh
aWwoZXJyb3IpOworICAgICAgICAgICAgZWxzZSB7IG1fc3RhdHNUaW1lci5zZXRJbnRlcnZhbCgy
MDAwKTsgbV9zdGF0cyA9IHBhcnNlZDsgbV9zdGF0dXMgPSB0cigiSE9TVCDigKIgcmVjZWl2ZWQg
JTEiKS5hcmcoUURhdGVUaW1lOjpjdXJyZW50RGF0ZVRpbWUoKS50b1N0cmluZygiaGg6bW06c3Mi
KSk7IGVtaXQgc3RhdHNDaGFuZ2VkKCk7IH0KKyAgICAgICAgfQorICAgICAgICByZXBseS0+ZGVs
ZXRlTGF0ZXIoKTsKKyAgICB9KTsKKyAgICAvLyBBYnNvbHV0ZSByZXF1ZXN0IGJvdW5kIGV2ZW4g
aWYgYSBwZWVyIGtlZXBzIHNlbmRpbmcgb2NjYXNpb25hbCBieXRlcy4KKyAgICBRVGltZXI6OnNp
bmdsZVNob3QoMzUwMCwgcmVwbHksIFtyZXBseV0geyBpZiAoIXJlcGx5LT5pc0ZpbmlzaGVkKCkp
IHJlcGx5LT5hYm9ydCgpOyB9KTsKK30KK1FWYXJpYW50TWFwIENyaW1zb25TdGF0dXM6OnJlYWRM
b2NhbChjb25zdCBRU3RyaW5nJiByb290KSB7CisgICAgUVZhcmlhbnRNYXAgb3V0OyBRU3RyaW5n
TGlzdCBuZXR3b3JrczsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIG5hbWUgOiBRRGlyKHJvb3QgKyAi
L2NsYXNzL25ldCIpLmVudHJ5TGlzdChRRGlyOjpEaXJzIHwgUURpcjo6Tm9Eb3RBbmREb3REb3Qp
KSB7CisgICAgICAgIGlmIChuYW1lID09ICJsbyIgfHwgcmVhZChyb290ICsgIi9jbGFzcy9uZXQv
IiArIG5hbWUgKyAiL29wZXJzdGF0ZSIpICE9ICJ1cCIpIGNvbnRpbnVlOworICAgICAgICBuZXR3
b3JrcyA8PCBuYW1lOworICAgIH0KKyAgICBvdXRbImNvbm5lY3RlZCJdID0gIW5ldHdvcmtzLmlz
RW1wdHkoKTsgb3V0WyJuZXR3b3JrIl0gPSBuZXR3b3Jrcy5pc0VtcHR5KCkgPyB0cigiTm8gYWN0
aXZlIG5ldHdvcmsgbGluayIpIDogbmV0d29ya3Muam9pbigiLCAiKTsKKyAgICAvLyBMaW5rIHN0
YXR1cyBpcyBpbnRlbnRpb25hbGx5IG5vdCBwcmVzZW50ZWQgYXMgaW50ZXJuZXQgcmVhY2hhYmls
aXR5LgorICAgIG91dFsiYmF0dGVyeVBlcmNlbnQiXSA9IC0xOyBvdXRbImJhdHRlcnlTdGF0ZSJd
ID0gdHIoIkJhdHRlcnkgdW5hdmFpbGFibGUiKTsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIG5hbWUg
OiBRRGlyKHJvb3QgKyAiL2NsYXNzL3Bvd2VyX3N1cHBseSIpLmVudHJ5TGlzdChRRGlyOjpEaXJz
IHwgUURpcjo6Tm9Eb3RBbmREb3REb3QpKSB7CisgICAgICAgIGNvbnN0IGF1dG8gYmFzZSA9IHJv
b3QgKyAiL2NsYXNzL3Bvd2VyX3N1cHBseS8iICsgbmFtZSArICIvIjsKKyAgICAgICAgaWYgKHJl
YWQoYmFzZSArICJ0eXBlIikgIT0gIkJhdHRlcnkiIHx8IHJlYWQoYmFzZSArICJwcmVzZW50Iikg
PT0gIjAiKSBjb250aW51ZTsKKyAgICAgICAgYm9vbCBvazsgaW50IGNhcCA9IHJlYWQoYmFzZSAr
ICJjYXBhY2l0eSIpLnRvSW50KCZvayk7CisgICAgICAgIGlmIChvayAmJiBjYXAgPj0gMCAmJiBj
YXAgPD0gMTAwKSBvdXRbImJhdHRlcnlQZXJjZW50Il0gPSBjYXA7CisgICAgICAgIGNvbnN0IGF1
dG8gc3RhdGUgPSByZWFkKGJhc2UgKyAic3RhdHVzIik7IG91dFsiYmF0dGVyeVN0YXRlIl0gPSBz
dGF0ZS5pc0VtcHR5KCkgPyB0cigiVW5rbm93biIpIDogc3RhdGU7IGJyZWFrOworICAgIH0KKyAg
ICByZXR1cm4gb3V0OworfQordm9pZCBDcmltc29uU3RhdHVzOjpyZWZyZXNoTG9jYWwoKSB7Cisg
ICAgbV9sb2NhbCA9IHJlYWRMb2NhbCgpOyBtX2xvY2FsWyJ3aWZpU2lnbmFsIl0gPSAtMTsgZW1p
dCBsb2NhbENoYW5nZWQoKTsKKyAgICBpZiAobV93aWZpLnN0YXRlKCkgPT0gUVByb2Nlc3M6Ok5v
dFJ1bm5pbmcpIHsKKyAgICAgICAgbV93aWZpLnN0YXJ0KCJubWNsaSIsIHsiLXQiLCAiLS1lc2Nh
cGUiLCAibm8iLCAiLWYiLCAiQUNUSVZFLFNJR05BTCxTU0lEIiwgImRldmljZSIsICJ3aWZpIiwg
Imxpc3QiLCAiLS1yZXNjYW4iLCAibm8ifSk7CisgICAgICAgIFFUaW1lcjo6c2luZ2xlU2hvdCgy
MDAwLCAmbV93aWZpLCBbdGhpc10geyBpZiAobV93aWZpLnN0YXRlKCkgIT0gUVByb2Nlc3M6Ok5v
dFJ1bm5pbmcpIG1fd2lmaS5raWxsKCk7IH0pOworICAgIH0KK30KKworc3RhdGljIHZvaWQgcmVn
aXN0ZXJDcmltc29uU3RhdHVzKCkgeworICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9uVHlwZTxDcmlt
c29uU3RhdHVzPigiQ3JpbXNvblN0YXR1cyIsIDEsIDAsICJDcmltc29uU3RhdHVzIiwKKyAgICAg
ICAgW10oUVFtbEVuZ2luZSosIFFKU0VuZ2luZSopIC0+IFFPYmplY3QqIHsgcmV0dXJuIG5ldyBD
cmltc29uU3RhdHVzKCk7IH0pOworfQorUV9DT1JFQVBQX1NUQVJUVVBfRlVOQ1RJT04ocmVnaXN0
ZXJDcmltc29uU3RhdHVzKQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL2NyaW1zb25zdGF0
dXMuaCBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmgKbmV3IGZpbGUgbW9kZSAxMDA2
NDQKaW5kZXggMDAwMDAwMC4uMmRhYzBkMQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGln
aHRvcy9jcmltc29uc3RhdHVzLmgKQEAgLTAsMCArMSw1MiBAQAorI3ByYWdtYSBvbmNlCisjaW5j
bHVkZSA8UU9iamVjdD4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRVGltZXI+
CisjaW5jbHVkZSA8UU5ldHdvcmtBY2Nlc3NNYW5hZ2VyPgorI2luY2x1ZGUgPFFQb2ludGVyPgor
I2luY2x1ZGUgPFFOZXR3b3JrUmVwbHk+CisjaW5jbHVkZSA8UVByb2Nlc3M+CisKKy8vIE9wdGlv
bmFsIGxhdW5jaGVyIHN0YXR1cy4gTmV2ZXIgcGFydGljaXBhdGVzIGluIHRoZSBzdHJlYW1pbmcv
ZGVjb2RlciBwYXRoLgorY2xhc3MgQ3JpbXNvblN0YXR1cyA6IHB1YmxpYyBRT2JqZWN0IHsKKyAg
ICBRX09CSkVDVAorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgbG9jYWwgUkVBRCBsb2NhbCBO
T1RJRlkgbG9jYWxDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgc3RhdHMgUkVB
RCBzdGF0cyBOT1RJRlkgc3RhdHNDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBzdGF0
dXMgUkVBRCBzdGF0dXMgTk9USUZZIHN0YXRzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJp
bmcgZW5kcG9pbnQgUkVBRCBlbmRwb2ludCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKKyAgICBRX1BS
T1BFUlRZKFFTdHJpbmcgZmluZ2VycHJpbnQgUkVBRCBmaW5nZXJwcmludCBOT1RJRlkgY29uZmln
Q2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgY29uZmlndXJlZCBSRUFEIGNvbmZpZ3VyZWQg
Tk9USUZZIGNvbmZpZ0NoYW5nZWQpCitwdWJsaWM6CisgICAgZXhwbGljaXQgQ3JpbXNvblN0YXR1
cyhRT2JqZWN0KiBwYXJlbnQgPSBudWxscHRyKTsKKyAgICB+Q3JpbXNvblN0YXR1cygpIG92ZXJy
aWRlOworICAgIFFWYXJpYW50TWFwIGxvY2FsKCkgY29uc3QgeyByZXR1cm4gbV9sb2NhbDsgfQor
ICAgIFFWYXJpYW50TWFwIHN0YXRzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0czsgfQorICAgIFFT
dHJpbmcgc3RhdHVzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0dXM7IH0KKyAgICBRU3RyaW5nIGVu
ZHBvaW50KCkgY29uc3QgeyByZXR1cm4gbV9lbmRwb2ludDsgfQorICAgIFFTdHJpbmcgZmluZ2Vy
cHJpbnQoKSBjb25zdCB7IHJldHVybiBtX3BpbjsgfQorICAgIGJvb2wgY29uZmlndXJlZCgpIGNv
bnN0IHsgcmV0dXJuICFtX2VuZHBvaW50LmlzRW1wdHkoKSAmJiAhbV90b2tlbi5pc0VtcHR5KCk7
IH0KKyAgICBRX0lOVk9LQUJMRSB2b2lkIHNlbGVjdEhvc3QoUVN0cmluZyBpZCwgUVN0cmluZyBz
dWdnZXN0ZWRVcmwpOworICAgIFFfSU5WT0tBQkxFIGJvb2wgY29uZmlndXJlKFFTdHJpbmcgdXJs
LCBRU3RyaW5nIHRva2VuLCBRU3RyaW5nIHBpbik7CisgICAgUV9JTlZPS0FCTEUgdm9pZCBzZXRW
aXNpYmxlKGJvb2wgdmlzaWJsZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCByZWZyZXNoKCk7Cisg
ICAgc3RhdGljIFFWYXJpYW50TWFwIHBhcnNlU3RhdHMoY29uc3QgUUJ5dGVBcnJheSYgYnl0ZXMs
IFFTdHJpbmcqIGVycm9yKTsKKyAgICBzdGF0aWMgYm9vbCB2YWxpZEVuZHBvaW50KGNvbnN0IFFT
dHJpbmcmIHVybCk7CisgICAgc3RhdGljIFFTdHJpbmcgbm9ybWFsaXplZFBpbihRU3RyaW5nIHBp
bik7CisgICAgc3RhdGljIFFWYXJpYW50TWFwIHJlYWRMb2NhbChjb25zdCBRU3RyaW5nJiBzeXNS
b290ID0gIi9zeXMiKTsKK3NpZ25hbHM6CisgICAgdm9pZCBsb2NhbENoYW5nZWQoKTsKKyAgICB2
b2lkIHN0YXRzQ2hhbmdlZCgpOworICAgIHZvaWQgY29uZmlnQ2hhbmdlZCgpOworcHJpdmF0ZToK
KyAgICB2b2lkIHJlZnJlc2hMb2NhbCgpOworICAgIHZvaWQgZmFpbChRU3RyaW5nIG1lc3NhZ2Up
OworICAgIHZvaWQgY2FuY2VsKCk7CisgICAgUVN0cmluZyBjb25maWdGaWxlKCkgY29uc3Q7Cisg
ICAgUVN0cmluZyBtX2hvc3QsIG1fZW5kcG9pbnQsIG1fdG9rZW4sIG1fcGluLCBtX3N0YXR1cyA9
ICJDaG9vc2UgYSBob3N0IHRvIHZpZXcgaGFyZHdhcmUgc3RhdHMiOworICAgIFFWYXJpYW50TWFw
IG1fbG9jYWwsIG1fc3RhdHM7CisgICAgUVRpbWVyIG1fbG9jYWxUaW1lciwgbV9zdGF0c1RpbWVy
OworICAgIFFQcm9jZXNzIG1fd2lmaTsKKyAgICBRTmV0d29ya0FjY2Vzc01hbmFnZXIgbV9uZXR3
b3JrOworICAgIFFQb2ludGVyPFFOZXR3b3JrUmVwbHk+IG1fcmVwbHk7CisgICAgYm9vbCBtX3Zp
c2libGUgPSBmYWxzZTsKK307CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXBy
b2ZpbGVzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmE2M2Q1MmQKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmNwcApAQCAtMCwwICsxLDQxIEBACisjaW5j
bHVkZSAiZWNsaXBzZXByb2ZpbGVzLmgiCisjaW5jbHVkZSA8UUNyeXB0b2dyYXBoaWNIYXNoPgor
I2luY2x1ZGUgPFFDb3JlQXBwbGljYXRpb24+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KK1FTdHJp
bmcgRWNsaXBzZVByb2ZpbGVzOjprZXkoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUpIHsKKyAg
ICByZXR1cm4gImVjbGlwc2UvcHJvZmlsZXMvIiArIFFTdHJpbmc6OmZyb21MYXRpbjEoUUNyeXB0
b2dyYXBoaWNIYXNoOjpoYXNoKGhvc3QudG9VdGY4KCksIFFDcnlwdG9ncmFwaGljSGFzaDo6U2hh
MjU2KS50b0hleCgpKSArICIvIiArIFFTdHJpbmc6OmZyb21MYXRpbjEoUUNyeXB0b2dyYXBoaWNI
YXNoOjpoYXNoKG5hbWUudHJpbW1lZCgpLnRvVXRmOCgpLCBRQ3J5cHRvZ3JhcGhpY0hhc2g6OlNo
YTI1NikudG9IZXgoKSk7Cit9Citib29sIEVjbGlwc2VQcm9maWxlczo6dmFsaWQoY29uc3QgUVZh
cmlhbnRNYXAmIHZhbHVlcykgeworICAgIGNvbnN0IFFNYXA8UVN0cmluZyxRUGFpcjxpbnQsaW50
Pj4gcmFuZ2VzID0ge3sid2lkdGgiLHszMjAsNzY4MH19LCB7ImhlaWdodCIsezIwMCw0MzIwfX0s
IHsiZnBzIix7MSwyNDB9fSwgeyJiaXRyYXRlS2JwcyIsezUwMCwxNTAwMDB9fX07CisgICAgaWYg
KHZhbHVlcy5zaXplKCkgIT0gcmFuZ2VzLnNpemUoKSkgcmV0dXJuIGZhbHNlOworICAgIGZvciAo
YXV0byBpID0gcmFuZ2VzLmJlZ2luKCk7IGkgIT0gcmFuZ2VzLmVuZCgpOyArK2kpIHsKKyAgICAg
ICAgYm9vbCBvazsgYXV0byBuID0gdmFsdWVzLnZhbHVlKGkua2V5KCkpLnRvSW50KCZvayk7Cisg
ICAgICAgIGlmICghb2sgfHwgbiA8IGkudmFsdWUoKS5maXJzdCB8fCBuID4gaS52YWx1ZSgpLnNl
Y29uZCkgcmV0dXJuIGZhbHNlOworICAgIH0KKyAgICByZXR1cm4gdHJ1ZTsKK30KK2Jvb2wgRWNs
aXBzZVByb2ZpbGVzOjpzYXZlKFFTdHJpbmcgaG9zdCwgUVN0cmluZyBuYW1lLCBRVmFyaWFudE1h
cCB2YWx1ZXMpIHsKKyAgICBuYW1lID0gbmFtZS50cmltbWVkKCk7CisgICAgaWYgKGhvc3Quc2l6
ZSgpID4gMjU2IHx8IG5hbWUuaXNFbXB0eSgpIHx8IG5hbWUuc2l6ZSgpID4gNDggfHwgIXZhbGlk
KHZhbHVlcykpIHJldHVybiBmYWxzZTsKKyAgICBpZiAoIW5hbWVzKGhvc3QpLmNvbnRhaW5zKG5h
bWUpICYmIG5hbWVzKGhvc3QpLnNpemUoKSA+PSAzMikgcmV0dXJuIGZhbHNlOworICAgIFFTZXR0
aW5ncyBzZXR0aW5nczsgc2V0dGluZ3Muc2V0VmFsdWUoa2V5KGhvc3QsbmFtZSkrIi9uYW1lIixu
YW1lKTsgc2V0dGluZ3Muc2V0VmFsdWUoa2V5KGhvc3QsbmFtZSkrIi92YWx1ZXMiLHZhbHVlcyk7
IHNldHRpbmdzLnN5bmMoKTsKKyAgICByZXR1cm4gc2V0dGluZ3Muc3RhdHVzKCkgPT0gUVNldHRp
bmdzOjpOb0Vycm9yOworfQorUVZhcmlhbnRNYXAgRWNsaXBzZVByb2ZpbGVzOjpsb2FkKFFTdHJp
bmcgaG9zdCwgUVN0cmluZyBuYW1lKSB7CisgICAgUVNldHRpbmdzIHNldHRpbmdzOyBhdXRvIHZh
bHVlID0gc2V0dGluZ3MudmFsdWUoa2V5KGhvc3QsbmFtZSkrIi92YWx1ZXMiKS50b01hcCgpOwor
ICAgIHJldHVybiB2YWxpZCh2YWx1ZSkgPyB2YWx1ZSA6IFFWYXJpYW50TWFwKCk7Cit9Citib29s
IEVjbGlwc2VQcm9maWxlczo6cmVtb3ZlKFFTdHJpbmcgaG9zdCwgUVN0cmluZyBuYW1lLCBib29s
IGNvbmZpcm1lZCkgeworICAgIGlmICghY29uZmlybWVkKSByZXR1cm4gZmFsc2U7CisgICAgUVNl
dHRpbmdzIHNldHRpbmdzOyBzZXR0aW5ncy5yZW1vdmUoa2V5KGhvc3QsbmFtZSkpOyBzZXR0aW5n
cy5zeW5jKCk7IHJldHVybiBzZXR0aW5ncy5zdGF0dXMoKSA9PSBRU2V0dGluZ3M6Ok5vRXJyb3I7
Cit9CitRU3RyaW5nTGlzdCBFY2xpcHNlUHJvZmlsZXM6Om5hbWVzKFFTdHJpbmcgaG9zdCkgewor
ICAgIFFTZXR0aW5ncyBzZXR0aW5nczsgc2V0dGluZ3MuYmVnaW5Hcm91cChrZXkoaG9zdCwgIiIp
LnNlY3Rpb24oJy8nLDAsLTIpKTsKKyAgICBRU3RyaW5nTGlzdCByZXN1bHQ7CisgICAgZm9yIChj
b25zdCBhdXRvJiBjaGlsZCA6IHNldHRpbmdzLmNoaWxkR3JvdXBzKCkpIHsgYXV0byBuYW1lID0g
c2V0dGluZ3MudmFsdWUoY2hpbGQrIi9uYW1lIikudG9TdHJpbmcoKTsgaWYgKCFuYW1lLmlzRW1w
dHkoKSkgcmVzdWx0LmFwcGVuZChuYW1lKTsgfQorICAgIHJlc3VsdC5zb3J0KCk7IHJldHVybiBy
ZXN1bHQ7Cit9CitzdGF0aWMgdm9pZCByZWdpc3RlckVjbGlwc2VQcm9maWxlcygpIHsKKyAgICBx
bWxSZWdpc3RlclNpbmdsZXRvblR5cGU8RWNsaXBzZVByb2ZpbGVzPigiRWNsaXBzZVByb2ZpbGVz
IiwxLDAsIkVjbGlwc2VQcm9maWxlcyIsW10oUVFtbEVuZ2luZSosUUpTRW5naW5lKikgLT4gUU9i
amVjdCogeyByZXR1cm4gbmV3IEVjbGlwc2VQcm9maWxlcygpOyB9KTsKK30KK1FfQ09SRUFQUF9T
VEFSVFVQX0ZVTkNUSU9OKHJlZ2lzdGVyRWNsaXBzZVByb2ZpbGVzKQpkaWZmIC0tZ2l0IGEvYXBw
L21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5oIGIvYXBwL21vb25saWdodG9zL2VjbGlwc2Vw
cm9maWxlcy5oCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmQzOTgzODcKLS0t
IC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmgKQEAgLTAs
MCArMSwyNyBAQAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4KKyNpbmNsdWRlIDxR
VmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRU2V0dGluZ3M+CitjbGFzcyBFY2xpcHNlUHJvZmlsZXMg
OiBwdWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpFQ1QKKyAgICBRX1BST1BFUlRZKGludCB0ZXh0
U2NhbGUgUkVBRCB0ZXh0U2NhbGUgV1JJVEUgc2V0VGV4dFNjYWxlIE5PVElGWSBhcHBlYXJhbmNl
Q2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgcmVkdWNlZE1vdGlvbiBSRUFEIHJlZHVjZWRN
b3Rpb24gV1JJVEUgc2V0UmVkdWNlZE1vdGlvbiBOT1RJRlkgYXBwZWFyYW5jZUNoYW5nZWQpCisg
ICAgUV9QUk9QRVJUWShib29sIGhpZ2hDb250cmFzdCBSRUFEIGhpZ2hDb250cmFzdCBXUklURSBz
ZXRIaWdoQ29udHJhc3QgTk9USUZZIGFwcGVhcmFuY2VDaGFuZ2VkKQorcHVibGljOgorICAgIGV4
cGxpY2l0IEVjbGlwc2VQcm9maWxlcyhRT2JqZWN0KiBwYXJlbnQgPSBudWxscHRyKSA6IFFPYmpl
Y3QocGFyZW50KSB7fQorICAgIGludCB0ZXh0U2NhbGUoKSBjb25zdCB7IHJldHVybiBxQm91bmQo
MTAwLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL3RleHRTY2FsZSIsMTAwKS50b0ludCgpLDEy
NSk7IH0KKyAgICBib29sIHJlZHVjZWRNb3Rpb24oKSBjb25zdCB7IHJldHVybiBRU2V0dGluZ3Mo
KS52YWx1ZSgiZWNsaXBzZS9yZWR1Y2VkTW90aW9uIixmYWxzZSkudG9Cb29sKCk7IH0KKyAgICBi
b29sIGhpZ2hDb250cmFzdCgpIGNvbnN0IHsgcmV0dXJuIFFTZXR0aW5ncygpLnZhbHVlKCJlY2xp
cHNlL2hpZ2hDb250cmFzdCIsZmFsc2UpLnRvQm9vbCgpOyB9CisgICAgdm9pZCBzZXRUZXh0U2Nh
bGUoaW50IHZhbHVlKSB7IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlL3RleHRTY2FsZSIs
cUJvdW5kKDEwMCx2YWx1ZSwxMjUpKTsgZW1pdCBhcHBlYXJhbmNlQ2hhbmdlZCgpOyB9CisgICAg
dm9pZCBzZXRSZWR1Y2VkTW90aW9uKGJvb2wgdmFsdWUpIHsgUVNldHRpbmdzKCkuc2V0VmFsdWUo
ImVjbGlwc2UvcmVkdWNlZE1vdGlvbiIsdmFsdWUpOyBlbWl0IGFwcGVhcmFuY2VDaGFuZ2VkKCk7
IH0KKyAgICB2b2lkIHNldEhpZ2hDb250cmFzdChib29sIHZhbHVlKSB7IFFTZXR0aW5ncygpLnNl
dFZhbHVlKCJlY2xpcHNlL2hpZ2hDb250cmFzdCIsdmFsdWUpOyBlbWl0IGFwcGVhcmFuY2VDaGFu
Z2VkKCk7IH0KKyAgICBRX0lOVk9LQUJMRSBib29sIHNhdmUoUVN0cmluZyBob3N0LCBRU3RyaW5n
IG5hbWUsIFFWYXJpYW50TWFwIHZhbHVlcyk7CisgICAgUV9JTlZPS0FCTEUgUVZhcmlhbnRNYXAg
bG9hZChRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSk7CisgICAgUV9JTlZPS0FCTEUgYm9vbCBy
ZW1vdmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUsIGJvb2wgY29uZmlybWVkKTsKKyAgICBR
X0lOVk9LQUJMRSBRU3RyaW5nTGlzdCBuYW1lcyhRU3RyaW5nIGhvc3QpOworICAgIHN0YXRpYyBi
b29sIHZhbGlkKGNvbnN0IFFWYXJpYW50TWFwJiB2YWx1ZXMpOworc2lnbmFsczoKKyAgICB2b2lk
IGFwcGVhcmFuY2VDaGFuZ2VkKCk7Citwcml2YXRlOgorICAgIHN0YXRpYyBRU3RyaW5nIGtleShR
U3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSk7Cit9OwpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdo
dG9zL2xvY2FsaGFyZHdhcmUuY3BwIGIvYXBwL21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuY3Bw
Cm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjQxM2NjNjEKLS0tIC9kZXYvbnVs
bAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvbG9jYWxoYXJkd2FyZS5jcHAKQEAgLTAsMCArMSwxMjMg
QEAKKyNpbmNsdWRlICJsb2NhbGhhcmR3YXJlLmgiCisjaW5jbHVkZSA8UXRNYXRoPgorI2luY2x1
ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFEaXI+CisjaW5jbHVkZSA8UVNldD4KKyNpbmNsdWRlIDxR
U3RvcmFnZUluZm8+CisjaW5jbHVkZSA8UUZpbGVJbmZvPgorI2luY2x1ZGUgPFFFbGFwc2VkVGlt
ZXI+CisjaW5jbHVkZSA8UU11dGV4PgorI2luY2x1ZGUgPFFNdXRleExvY2tlcj4KKyNpbmNsdWRl
IDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFDb3JlQXBwbGljYXRpb24+CisjaW5jbHVkZSA8UVJl
Z3VsYXJFeHByZXNzaW9uPgorCitzdGF0aWMgUVN0cmluZyByZWFkKGNvbnN0IFFTdHJpbmcmIHBh
dGgpIHsgUUZpbGUgZihwYXRoKTsgcmV0dXJuIGYub3BlbihRSU9EZXZpY2U6OlJlYWRPbmx5KSA/
IFFTdHJpbmc6OmZyb21VdGY4KGYucmVhZCgzMjc2OCkpLnRyaW1tZWQoKSA6IFFTdHJpbmcoKTsg
fQorc3RhdGljIGRvdWJsZSBudW1iZXIoY29uc3QgUVN0cmluZyYgcGF0aCkgeyBib29sIG9rOyBk
b3VibGUgbj1yZWFkKHBhdGgpLnRvRG91YmxlKCZvayk7IHJldHVybiBvayAmJiBxSXNGaW5pdGUo
bikgPyBuIDogLTE7IH0KK0xvY2FsSGFyZHdhcmU6OkxvY2FsSGFyZHdhcmUoUU9iamVjdCogcGFy
ZW50KTpRT2JqZWN0KHBhcmVudCkgeyBtX3RpbWVyLnNldEludGVydmFsKHJlZnJlc2hTZWNvbmRz
KCkqMTAwMCk7IGNvbm5lY3QoJm1fdGltZXIsJlFUaW1lcjo6dGltZW91dCx0aGlzLCZMb2NhbEhh
cmR3YXJlOjpyZWZyZXNoKTsgfQordm9pZCBMb2NhbEhhcmR3YXJlOjpzZXRBY3RpdmUoYm9vbCBh
Y3RpdmUpIHsgaWYgKGFjdGl2ZSkgeyByZWZyZXNoKCk7IG1fdGltZXIuc3RhcnQoKTsgfSBlbHNl
IG1fdGltZXIuc3RvcCgpOyB9Cit2b2lkIExvY2FsSGFyZHdhcmU6OnJlZnJlc2goKSB7IG1fcmVh
ZGluZ3M9c2FtcGxlKCk7IG1faGlzdG9yeS5hcHBlbmQobV9yZWFkaW5ncyk7IHdoaWxlKG1faGlz
dG9yeS5zaXplKCk+NjApIG1faGlzdG9yeS5yZW1vdmVGaXJzdCgpOyBlbWl0IGNoYW5nZWQoKTsg
fQordm9pZCBMb2NhbEhhcmR3YXJlOjpzZXRGaWVsZHMoUVN0cmluZ0xpc3QgdikgeyBRU3RyaW5n
TGlzdCBjbGVhbjsgZm9yKGNvbnN0IFFTdHJpbmcmIGtleTpRU3RyaW5nTGlzdHsiY3B1IiwibWVt
b3J5IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3JrIiwiYmF0dGVyeSIsInN0b3JhZ2UifSkg
aWYodi5jb250YWlucyhrZXkpKSBjbGVhbi5hcHBlbmQoa2V5KTsgc2F2ZSgibG9jYWxGaWVsZHMi
LGNsZWFuKTsgfQorCitRVmFyaWFudE1hcCBMb2NhbEhhcmR3YXJlOjpzYW1wbGUoY29uc3QgUVN0
cmluZyYgcm9vdCkgeworICAgIC8vIFNoYXJlZCBjYWNoZTogU2V0dGluZ3MgYW5kIHRoZSBkZWNv
ZGVyIHJldXNlIG9uZSBib3VuZGVkLCByZWFkLW9ubHkgc2FtcGxlLgorICAgIHN0YXRpYyBRTXV0
ZXggbXV0ZXg7IFFNdXRleExvY2tlciBsb2NrZXIoJm11dGV4KTsKKyAgICBzdGF0aWMgUUVsYXBz
ZWRUaW1lciBjbG9jazsgaWYoIWNsb2NrLmlzVmFsaWQoKSkgY2xvY2suc3RhcnQoKTsKKyAgICBz
dGF0aWMgUU1hcDxRU3RyaW5nLFFWYXJpYW50TWFwPiBwcmV2aW91cywgY2FjaGVkOworICAgIHN0
YXRpYyBRTWFwPFFTdHJpbmcscWludDY0PiBsYXN0OworICAgIHFpbnQ2NCBub3c9Y2xvY2suZWxh
cHNlZCgpOworICAgIGludCBpbnRlcnZhbD1xQm91bmQoMSxRU2V0dGluZ3MoKS52YWx1ZSgiZWNs
aXBzZS9oYXJkd2FyZVJlZnJlc2giLDIpLnRvSW50KCksNSkqMTAwMDsKKyAgICBpZihjYWNoZWQu
Y29udGFpbnMocm9vdCkgJiYgbm93LWxhc3QudmFsdWUocm9vdCk8aW50ZXJ2YWwpIHJldHVybiBj
YWNoZWQudmFsdWUocm9vdCk7CisgICAgUVZhcmlhbnRNYXAgcmVzdWx0LCBjb3VudGVyczsKKyAg
ICBhdXRvIG9sZD1wcmV2aW91cy52YWx1ZShyb290KTsgZG91YmxlIHNlY29uZHM9KG5vdy1sYXN0
LnZhbHVlKHJvb3QpKS8xMDAwLjA7CisgICAgYXV0byBzdGF0PXJlYWQocm9vdCsiL3Byb2Mvc3Rh
dCIpLnNlY3Rpb24oJ1xuJywwLDApLnNpbXBsaWZpZWQoKS5zcGxpdCgnICcpOworICAgIGlmKHN0
YXQuc2l6ZSgpPj05ICYmIHN0YXRbMF09PSJjcHUiKSB7CisgICAgICAgIHF1aW50NjQgdG90YWw9
MDsgZm9yKGludCBpPTE7aTw9ODtpKyspIHRvdGFsKz1zdGF0W2ldLnRvVUxvbmdMb25nKCk7Cisg
ICAgICAgIHF1aW50NjQgaWRsZT1zdGF0WzRdLnRvVUxvbmdMb25nKCkrc3RhdFs1XS50b1VMb25n
TG9uZygpOworICAgICAgICBjb3VudGVyc1sidG90YWwiXT10b3RhbDsgY291bnRlcnNbImlkbGUi
XT1pZGxlOworICAgICAgICBxdWludDY0IGJlZm9yZT1vbGQudmFsdWUoInRvdGFsIikudG9VTG9u
Z0xvbmcoKTsKKyAgICAgICAgaWYob2xkLmNvbnRhaW5zKCJ0b3RhbCIpICYmIHRvdGFsPmJlZm9y
ZSAmJiBpZGxlPj1vbGQudmFsdWUoImlkbGUiKS50b1VMb25nTG9uZygpKSByZXN1bHRbImNwdVBl
cmNlbnQiXT1xQm91bmQoMC4wLDEwMC4wKigxLjAtZG91YmxlKGlkbGUtb2xkWyJpZGxlIl0udG9V
TG9uZ0xvbmcoKSkvZG91YmxlKHRvdGFsLWJlZm9yZSkpLDEwMC4wKTsKKyAgICB9CisgICAgUU1h
cDxRU3RyaW5nLHF1aW50NjQ+IG1lbW9yeTsKKyAgICBmb3IoY29uc3QgUVN0cmluZyYgbGluZTpy
ZWFkKHJvb3QrIi9wcm9jL21lbWluZm8iKS5zcGxpdCgnXG4nKSkgeyBhdXRvIHBhcnRzPWxpbmUu
c2ltcGxpZmllZCgpLnNwbGl0KCcgJyk7IGlmKHBhcnRzLnNpemUoKT49MikgbWVtb3J5W3BhcnRz
WzBdXT1wYXJ0c1sxXS50b1VMb25nTG9uZygpKjEwMjQ7IH0KKyAgICBxdWludDY0IHRvdGFsPW1l
bW9yeS52YWx1ZSgiTWVtVG90YWw6IiksIGF2YWlsYWJsZT1tZW1vcnkudmFsdWUoIk1lbUF2YWls
YWJsZToiKTsKKyAgICBpZih0b3RhbCAmJiBhdmFpbGFibGU8PXRvdGFsICYmIG1lbW9yeS5jb250
YWlucygiTWVtQXZhaWxhYmxlOiIpKSB7IHJlc3VsdFsibWVtb3J5VXNlZEdpQiJdPWRvdWJsZSh0
b3RhbC1hdmFpbGFibGUpLygxMDI0KjEwMjQqMTAyNCk7IHJlc3VsdFsibWVtb3J5VG90YWxHaUIi
XT1kb3VibGUodG90YWwpLygxMDI0KjEwMjQqMTAyNCk7IHJlc3VsdFsibWVtb3J5UGVyY2VudCJd
PTEwMC4wKih0b3RhbC1hdmFpbGFibGUpL3RvdGFsOyB9CisgICAgaWYobWVtb3J5LmNvbnRhaW5z
KCJTd2FwVG90YWw6IikpIHJlc3VsdFsic3dhcFVzZWRNaUIiXT1kb3VibGUobWVtb3J5LnZhbHVl
KCJTd2FwVG90YWw6IiktcU1pbihtZW1vcnkudmFsdWUoIlN3YXBUb3RhbDoiKSxtZW1vcnkudmFs
dWUoIlN3YXBGcmVlOiIpKSkvKDEwMjQqMTAyNCk7CisgICAgZG91YmxlIGZyZXF1ZW5jeT1udW1i
ZXIocm9vdCsiL3N5cy9kZXZpY2VzL3N5c3RlbS9jcHUvY3B1MC9jcHVmcmVxL3NjYWxpbmdfY3Vy
X2ZyZXEiKTsgaWYoZnJlcXVlbmN5PjApIHJlc3VsdFsiY3B1TUh6Il09ZnJlcXVlbmN5LzEwMDA7
CisgICAgZG91YmxlIHRlbXBlcmF0dXJlPS0xLCBmYW49LTE7CisgICAgUURpciBodyhyb290KyIv
c3lzL2NsYXNzL2h3bW9uIik7CisgICAgZm9yKGNvbnN0IFFTdHJpbmcmIGRldmljZTpody5lbnRy
eUxpc3QoUURpcjo6RGlyc3xRRGlyOjpOb0RvdEFuZERvdERvdCkpIHsKKyAgICAgICAgUURpciBz
ZW5zb3JzKGh3LmZpbGVQYXRoKGRldmljZSkpOyBRU3RyaW5nIG5hbWU9cmVhZChzZW5zb3JzLmZp
bGVQYXRoKCJuYW1lIikpOworICAgICAgICBmb3IoY29uc3QgUVN0cmluZyYgZmlsZTpzZW5zb3Jz
LmVudHJ5TGlzdCh7InRlbXAqX2lucHV0IiwiZmFuKl9pbnB1dCJ9LFFEaXI6OkZpbGVzKSkgewor
ICAgICAgICAgICAgZG91YmxlIHZhbHVlPW51bWJlcihzZW5zb3JzLmZpbGVQYXRoKGZpbGUpKTsK
KyAgICAgICAgICAgIGlmKGZpbGUuc3RhcnRzV2l0aCgidGVtcCIpICYmIChuYW1lPT0iY29yZXRl
bXAiIHx8IG5hbWU9PSJrMTB0ZW1wIikgJiYgdmFsdWU+PTAgJiYgdmFsdWU8PTE1MDAwMCkgdGVt
cGVyYXR1cmU9cU1heCh0ZW1wZXJhdHVyZSx2YWx1ZS8xMDAwKTsKKyAgICAgICAgICAgIGlmKGZp
bGUuc3RhcnRzV2l0aCgiZmFuIikgJiYgdmFsdWU+PTAgJiYgdmFsdWU8MzAwMDApIGZhbj1xTWF4
KGZhbix2YWx1ZSk7CisgICAgICAgIH0KKyAgICB9CisgICAgaWYodGVtcGVyYXR1cmU+PTApIHJl
c3VsdFsidGVtcGVyYXR1cmVDIl09dGVtcGVyYXR1cmU7CisgICAgaWYoZmFuPj0wKSByZXN1bHRb
ImZhblJQTSJdPWZhbjsKKyAgICBRRGlyIGRybShyb290KyIvc3lzL2NsYXNzL2RybSIpOworICAg
IGZvcihjb25zdCBRU3RyaW5nJiBjYXJkOmRybS5lbnRyeUxpc3QoeyJjYXJkWzAtOV0qIn0sUURp
cjo6RGlyc3xRRGlyOjpOb0RvdEFuZERvdERvdCkpIHsgZG91YmxlIGJ1c3k9bnVtYmVyKGRybS5m
aWxlUGF0aChjYXJkKyIvZGV2aWNlL2dwdV9idXN5X3BlcmNlbnQiKSk7IGlmKGJ1c3k+PTAgJiYg
YnVzeTw9MTAwKSB7IHJlc3VsdFsiZ3B1UGVyY2VudCJdPWJ1c3k7IGJyZWFrOyB9IH0KKyAgICAv
LyBEUk0gZmRpbmZvIGlzIHVucHJpdmlsZWdlZCwgcmVhZC1vbmx5IGFuZCBzY29wZWQgdG8gdGhp
cyBFY2xpcHNlIHByb2Nlc3MuCisgICAgLy8gRGVkdXBsaWNhdGUgZGVzY3JpcHRvcnMgYmVsb25n
aW5nIHRvIHRoZSBzYW1lIERSTSBjbGllbnQ7IG5ldmVyIGNhbGwgdGhpcyBzeXN0ZW0td2lkZSBH
UFUgbG9hZC4KKyAgICBxdWludDY0IHZpZGVvPTA7IGJvb2wgaGFzVmlkZW89ZmFsc2U7IFFTZXQ8
UVN0cmluZz4gY2xpZW50czsKKyAgICBRRGlyIGRlc2NyaXB0b3JzKHJvb3QrIi9wcm9jL3NlbGYv
ZmRpbmZvIik7CisgICAgaW50IGluc3BlY3RlZD0wOworICAgIGZvcihjb25zdCBRU3RyaW5nJiBm
aWxlOmRlc2NyaXB0b3JzLmVudHJ5TGlzdChRRGlyOjpGaWxlcykpIHsKKyAgICAgICAgaWYoKytp
bnNwZWN0ZWQ+MjU2KSBicmVhazsKKyAgICAgICAgUVN0cmluZyBpbmZvPXJlYWQoZGVzY3JpcHRv
cnMuZmlsZVBhdGgoZmlsZSkpOworICAgICAgICBhdXRvIGNsaWVudD1RUmVndWxhckV4cHJlc3Np
b24oImRybS1jbGllbnQtaWQ6XFxzKihcXGQrKSIpLm1hdGNoKGluZm8pOworICAgICAgICBpZigh
Y2xpZW50Lmhhc01hdGNoKCkgfHwgY2xpZW50cy5jb250YWlucyhjbGllbnQuY2FwdHVyZWQoMSkp
KSBjb250aW51ZTsKKyAgICAgICAgY2xpZW50cy5pbnNlcnQoY2xpZW50LmNhcHR1cmVkKDEpKTsK
KyAgICAgICAgYXV0byBlbmdpbmVzPVFSZWd1bGFyRXhwcmVzc2lvbigiZHJtLWVuZ2luZS12aWRl
byg/OlxcZCspPzpcXHMqKFxcZCspXFxzK25zIikuZ2xvYmFsTWF0Y2goaW5mbyk7CisgICAgICAg
IHdoaWxlKGVuZ2luZXMuaGFzTmV4dCgpKSB7IHZpZGVvKz1lbmdpbmVzLm5leHQoKS5jYXB0dXJl
ZCgxKS50b1VMb25nTG9uZygpOyBoYXNWaWRlbz10cnVlOyB9CisgICAgfQorICAgIGlmKGhhc1Zp
ZGVvKSB7CisgICAgICAgIGNvdW50ZXJzWyJ2aWRlbyJdPXZpZGVvOworICAgICAgICBpZihvbGQu
Y29udGFpbnMoInZpZGVvIikgJiYgc2Vjb25kcz4wICYmIHZpZGVvPj1vbGQudmFsdWUoInZpZGVv
IikudG9VTG9uZ0xvbmcoKSkgcmVzdWx0WyJ2aWRlb1BlcmNlbnQiXT1xQm91bmQoMC4wLGRvdWJs
ZSh2aWRlby1vbGRbInZpZGVvIl0udG9VTG9uZ0xvbmcoKSkvc2Vjb25kcy8xMDAwMDAwMC4wLDEw
MC4wKTsKKyAgICB9CisgICAgUVN0cmluZyBuaWM7CisgICAgZm9yKGNvbnN0IFFTdHJpbmcmIGxp
bmU6cmVhZChyb290KyIvcHJvYy9uZXQvcm91dGUiKS5zcGxpdCgnXG4nKSkgeyBhdXRvIHA9bGlu
ZS5zaW1wbGlmaWVkKCkuc3BsaXQoJyAnKTsgaWYocC5zaXplKCk+MyAmJiBwWzFdPT0iMDAwMDAw
MDAiKSB7IG5pYz1wWzBdOyBicmVhazsgfSB9CisgICAgZm9yKGNvbnN0IFFTdHJpbmcmIGxpbmU6
cmVhZChyb290KyIvcHJvYy9uZXQvZGV2Iikuc3BsaXQoJ1xuJykpIHsKKyAgICAgICAgaWYobGlu
ZS5zZWN0aW9uKCc6JywwLDApLnRyaW1tZWQoKSE9bmljIHx8IG5pYy5pc0VtcHR5KCkpIGNvbnRp
bnVlOworICAgICAgICBhdXRvIHA9bGluZS5zZWN0aW9uKCc6JywxKS5zaW1wbGlmaWVkKCkuc3Bs
aXQoJyAnKTsgaWYocC5zaXplKCk8MTYpIGNvbnRpbnVlOworICAgICAgICBxdWludDY0IHJ4PXBb
MF0udG9VTG9uZ0xvbmcoKSwgdHg9cFs4XS50b1VMb25nTG9uZygpOyBjb3VudGVyc1sicngiXT1y
eDsgY291bnRlcnNbInR4Il09dHg7IGNvdW50ZXJzWyJuaWMiXT1uaWM7CisgICAgICAgIGlmKHNl
Y29uZHM+MCAmJiBvbGQudmFsdWUoIm5pYyIpLnRvU3RyaW5nKCk9PW5pYyAmJiByeD49b2xkLnZh
bHVlKCJyeCIpLnRvVUxvbmdMb25nKCkgJiYgdHg+PW9sZC52YWx1ZSgidHgiKS50b1VMb25nTG9u
ZygpKSB7IHJlc3VsdFsicmVjZWl2ZU1pQiJdPWRvdWJsZShyeC1vbGRbInJ4Il0udG9VTG9uZ0xv
bmcoKSkvc2Vjb25kcy8oMTAyNCoxMDI0KTsgcmVzdWx0WyJ0cmFuc21pdE1pQiJdPWRvdWJsZSh0
eC1vbGRbInR4Il0udG9VTG9uZ0xvbmcoKSkvc2Vjb25kcy8oMTAyNCoxMDI0KTsgfQorICAgIH0K
KyAgICBRRGlyIHBvd2VyKHJvb3QrIi9zeXMvY2xhc3MvcG93ZXJfc3VwcGx5Iik7CisgICAgZm9y
KGNvbnN0IFFTdHJpbmcmIG5hbWU6cG93ZXIuZW50cnlMaXN0KFFEaXI6OkRpcnN8UURpcjo6Tm9E
b3RBbmREb3REb3QpKSB7CisgICAgICAgIFFTdHJpbmcgcGF0aD1wb3dlci5maWxlUGF0aChuYW1l
KTsgaWYocmVhZChwYXRoKyIvdHlwZSIpIT0iQmF0dGVyeSIpIGNvbnRpbnVlOworICAgICAgICBk
b3VibGUgcGVyY2VudD1udW1iZXIocGF0aCsiL2NhcGFjaXR5Iik7IGlmKHBlcmNlbnQ+PTAgJiYg
cGVyY2VudDw9MTAwKSByZXN1bHRbImJhdHRlcnlQZXJjZW50Il09cGVyY2VudDsKKyAgICAgICAg
cmVzdWx0WyJiYXR0ZXJ5U3RhdGUiXT1yZWFkKHBhdGgrIi9zdGF0dXMiKS5sZWZ0KDMyKTsgZG91
YmxlIHdhdHRzPW51bWJlcihwYXRoKyIvcG93ZXJfbm93Iik7IGlmKHdhdHRzPj0wKSByZXN1bHRb
ImJhdHRlcnlXYXR0cyJdPXdhdHRzLzEwMDAwMDA7IGJyZWFrOworICAgIH0KKyAgICBpZihyb290
LmlzRW1wdHkoKSkgeyBRU3RvcmFnZUluZm8gZGlzaz1RU3RvcmFnZUluZm86OnJvb3QoKTsgaWYo
ZGlzay5pc1ZhbGlkKCkgJiYgZGlzay5pc1JlYWR5KCkgJiYgZGlzay5ieXRlc1RvdGFsKCk+MCkg
eyByZXN1bHRbInN0b3JhZ2VUb3RhbEdpQiJdPWRvdWJsZShkaXNrLmJ5dGVzVG90YWwoKSkvKDEw
MjQqMTAyNCoxMDI0KTsgcmVzdWx0WyJzdG9yYWdlRnJlZUdpQiJdPWRvdWJsZShkaXNrLmJ5dGVz
QXZhaWxhYmxlKCkpLygxMDI0KjEwMjQqMTAyNCk7IH0gfQorICAgIGlmKHJvb3QuaXNFbXB0eSgp
KSB7CisgICAgICAgIFFTdHJpbmcgZGV2aWNlPVFGaWxlSW5mbyhRU3RyaW5nOjpmcm9tVXRmOChR
U3RvcmFnZUluZm86OnJvb3QoKS5kZXZpY2UoKSkpLmNhbm9uaWNhbEZpbGVQYXRoKCkuc2VjdGlv
bignLycsLTEpOworICAgICAgICBhdXRvIGlvPXJlYWQoIi9zeXMvY2xhc3MvYmxvY2svIitkZXZp
Y2UrIi9zdGF0Iikuc2ltcGxpZmllZCgpLnNwbGl0KCcgJyk7CisgICAgICAgIGlmKCFkZXZpY2Uu
aXNFbXB0eSgpICYmIGlvLnNpemUoKT49NykgeworICAgICAgICAgICAgcXVpbnQ2NCByZWFkcz1p
b1syXS50b1VMb25nTG9uZygpLHdyaXRlcz1pb1s2XS50b1VMb25nTG9uZygpOworICAgICAgICAg
ICAgY291bnRlcnNbImRpc2siXT1kZXZpY2U7Y291bnRlcnNbInJlYWRzIl09cmVhZHM7Y291bnRl
cnNbIndyaXRlcyJdPXdyaXRlczsKKyAgICAgICAgICAgIGlmKHNlY29uZHM+MCAmJiBvbGQudmFs
dWUoImRpc2siKS50b1N0cmluZygpPT1kZXZpY2UgJiYgcmVhZHM+PW9sZC52YWx1ZSgicmVhZHMi
KS50b1VMb25nTG9uZygpICYmIHdyaXRlcz49b2xkLnZhbHVlKCJ3cml0ZXMiKS50b1VMb25nTG9u
ZygpKSB7CisgICAgICAgICAgICAgICAgcmVzdWx0WyJkaXNrUmVhZE1pQiJdPWRvdWJsZShyZWFk
cy1vbGRbInJlYWRzIl0udG9VTG9uZ0xvbmcoKSkqNTEyL3NlY29uZHMvKDEwMjQqMTAyNCk7Cisg
ICAgICAgICAgICAgICAgcmVzdWx0WyJkaXNrV3JpdGVNaUIiXT1kb3VibGUod3JpdGVzLW9sZFsi
d3JpdGVzIl0udG9VTG9uZ0xvbmcoKSkqNTEyL3NlY29uZHMvKDEwMjQqMTAyNCk7CisgICAgICAg
ICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgcHJldmlvdXNbcm9vdF09Y291bnRlcnM7IGxh
c3Rbcm9vdF09bm93OyBjYWNoZWRbcm9vdF09cmVzdWx0OyByZXR1cm4gcmVzdWx0OworfQorCitR
U3RyaW5nIExvY2FsSGFyZHdhcmU6Om92ZXJsYXlUZXh0KCkgeworICAgIGF1dG8gcj1zYW1wbGUo
KTsgUVNldHRpbmdzIHM7IGF1dG8gZmllbGRzPXMudmFsdWUoImVjbGlwc2UvbG9jYWxGaWVsZHMi
LFFTdHJpbmdMaXN0eyJjcHUiLCJtZW1vcnkiLCJ0ZW1wZXJhdHVyZSIsImdwdSIsIm5ldHdvcmsi
LCJiYXR0ZXJ5In0pLnRvU3RyaW5nTGlzdCgpOyBib29sIGRldGFpbD1zLnZhbHVlKCJlY2xpcHNl
L2xvY2FsRGV0YWlsZWQiLGZhbHNlKS50b0Jvb2woKTsKKyAgICBRU3RyaW5nTGlzdCBsaW5lc3si
RWNsaXBzZU9TIHwgTE9DQUwgTUFDIn07CisgICAgYXV0byB2YWx1ZT1bJnJdKFFTdHJpbmcga2V5
LFFTdHJpbmcgc3VmZml4LGludCBwcmVjaXNpb249MSkgeyByZXR1cm4gci5jb250YWlucyhrZXkp
ID8gUVN0cmluZzo6bnVtYmVyKHJba2V5XS50b0RvdWJsZSgpLCdmJyxwcmVjaXNpb24pK3N1ZmZp
eCA6IFFTdHJpbmcoIlVuYXZhaWxhYmxlIik7IH07CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJj
cHUiKSkgeyBsaW5lczw8IkNQVSAgIit2YWx1ZSgiY3B1UGVyY2VudCIsIiUiKTsgaWYoZGV0YWls
KSBsaW5lczw8IkNQVSBjbG9jayAgIit2YWx1ZSgiY3B1TUh6IiwiIE1IeiIsMCk7IH0KKyAgICBp
ZihmaWVsZHMuY29udGFpbnMoIm1lbW9yeSIpKSB7IGxpbmVzPDwiUkFNICAiK3ZhbHVlKCJtZW1v
cnlVc2VkR2lCIiwiIEdpQiIpKyIgLyAiK3ZhbHVlKCJtZW1vcnlUb3RhbEdpQiIsIiBHaUIiKTsg
aWYoZGV0YWlsKSBsaW5lczw8IlN3YXAgICIrdmFsdWUoInN3YXBVc2VkTWlCIiwiIE1pQiIpOyB9
CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJ0ZW1wZXJhdHVyZSIpKSB7IGxpbmVzPDwiQ1BVIHRl
bXBlcmF0dXJlICAiK3ZhbHVlKCJ0ZW1wZXJhdHVyZUMiLCIgQyIpOyBpZihkZXRhaWwpIGxpbmVz
PDwiRmFuICAiK3ZhbHVlKCJmYW5SUE0iLCIgUlBNIiwwKTsgfQorICAgIGlmKGZpZWxkcy5jb250
YWlucygiZ3B1IikpIHsgbGluZXM8PCJHUFUgYnVzeSAgIit2YWx1ZSgiZ3B1UGVyY2VudCIsIiUi
KTsgbGluZXM8PCJFY2xpcHNlIHZpZGVvIGVuZ2luZSAgIit2YWx1ZSgidmlkZW9QZXJjZW50Iiwi
JSIpOyB9CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJuZXR3b3JrIikpIGxpbmVzPDwiTmV0d29y
ayAgZG93biAiK3ZhbHVlKCJyZWNlaXZlTWlCIiwiIE1pQi9zIikrIiB8IHVwICIrdmFsdWUoInRy
YW5zbWl0TWlCIiwiIE1pQi9zIik7CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJiYXR0ZXJ5Iikp
IHsgbGluZXM8PCJCYXR0ZXJ5ICAiK3ZhbHVlKCJiYXR0ZXJ5UGVyY2VudCIsIiUiLDApOyBpZihk
ZXRhaWwpIGxpbmVzPDwiQmF0dGVyeSBwb3dlciAgIit2YWx1ZSgiYmF0dGVyeVdhdHRzIiwiIFci
KTsgfQorICAgIGlmKGZpZWxkcy5jb250YWlucygic3RvcmFnZSIpKSB7IGxpbmVzPDwiVVNCL3Jv
b3QgZnJlZSAgIit2YWx1ZSgic3RvcmFnZUZyZWVHaUIiLCIgR2lCIik7IGlmKGRldGFpbCkgbGlu
ZXM8PCJSb290IEkvTyAgcmVhZCAiK3ZhbHVlKCJkaXNrUmVhZE1pQiIsIiBNaUIvcyIpKyIgfCB3
cml0ZSAiK3ZhbHVlKCJkaXNrV3JpdGVNaUIiLCIgTWlCL3MiKTsgfQorICAgIHJldHVybiBsaW5l
cy5qb2luKCdcbicpOworfQorc3RhdGljIHZvaWQgcmVnaXN0ZXJMb2NhbEhhcmR3YXJlKCkgeyBx
bWxSZWdpc3RlclNpbmdsZXRvblR5cGU8TG9jYWxIYXJkd2FyZT4oIkxvY2FsSGFyZHdhcmUiLDEs
MCwiTG9jYWxIYXJkd2FyZSIsW10oUVFtbEVuZ2luZSosUUpTRW5naW5lKiktPlFPYmplY3Qqe3Jl
dHVybiBuZXcgTG9jYWxIYXJkd2FyZSgpO30pOyB9CitRX0NPUkVBUFBfU1RBUlRVUF9GVU5DVElP
TihyZWdpc3RlckxvY2FsSGFyZHdhcmUpCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvbG9j
YWxoYXJkd2FyZS5oIGIvYXBwL21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuaApuZXcgZmlsZSBt
b2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi4zMTFmZWE4Ci0tLSAvZGV2L251bGwKKysrIGIvYXBw
L21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuaApAQCAtMCwwICsxLDQ5IEBACisjcHJhZ21hIG9u
Y2UKKyNpbmNsdWRlIDxRT2JqZWN0PgorI2luY2x1ZGUgPFFWYXJpYW50TWFwPgorI2luY2x1ZGUg
PFFWYXJpYW50TGlzdD4KKyNpbmNsdWRlIDxRVGltZXI+CisjaW5jbHVkZSA8UVNldHRpbmdzPgor
CitjbGFzcyBMb2NhbEhhcmR3YXJlIDogcHVibGljIFFPYmplY3QgeworICAgIFFfT0JKRUNUCisg
ICAgUV9QUk9QRVJUWShRVmFyaWFudE1hcCByZWFkaW5ncyBSRUFEIHJlYWRpbmdzIE5PVElGWSBj
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRMaXN0IGhpc3RvcnkgUkVBRCBoaXN0b3J5
IE5PVElGWSBjaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBvdmVybGF5IFJFQUQgb3Zlcmxh
eSBXUklURSBzZXRPdmVybGF5IE5PVElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCisgICAgUV9QUk9Q
RVJUWShib29sIGRldGFpbGVkIFJFQUQgZGV0YWlsZWQgV1JJVEUgc2V0RGV0YWlsZWQgTk9USUZZ
IHByZWZlcmVuY2VzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgc3RyZWFtRGV0YWlsZWQg
UkVBRCBzdHJlYW1EZXRhaWxlZCBXUklURSBzZXRTdHJlYW1EZXRhaWxlZCBOT1RJRlkgcHJlZmVy
ZW5jZXNDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoaW50IHBvc2l0aW9uIFJFQUQgcG9zaXRpb24g
V1JJVEUgc2V0UG9zaXRpb24gTk9USUZZIHByZWZlcmVuY2VzQ2hhbmdlZCkKKyAgICBRX1BST1BF
UlRZKGludCBvcGFjaXR5IFJFQUQgb3BhY2l0eSBXUklURSBzZXRPcGFjaXR5IE5PVElGWSBwcmVm
ZXJlbmNlc0NoYW5nZWQpCisgICAgUV9QUk9QRVJUWShpbnQgcmVmcmVzaFNlY29uZHMgUkVBRCBy
ZWZyZXNoU2Vjb25kcyBXUklURSBzZXRSZWZyZXNoU2Vjb25kcyBOT1RJRlkgcHJlZmVyZW5jZXND
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZ0xpc3QgZmllbGRzIFJFQUQgZmllbGRzIFdS
SVRFIHNldEZpZWxkcyBOT1RJRlkgcHJlZmVyZW5jZXNDaGFuZ2VkKQorcHVibGljOgorICAgIGV4
cGxpY2l0IExvY2FsSGFyZHdhcmUoUU9iamVjdCogcGFyZW50PW51bGxwdHIpOworICAgIFFWYXJp
YW50TWFwIHJlYWRpbmdzKCkgY29uc3QgeyByZXR1cm4gbV9yZWFkaW5nczsgfQorICAgIFFWYXJp
YW50TGlzdCBoaXN0b3J5KCkgY29uc3QgeyByZXR1cm4gbV9oaXN0b3J5OyB9CisgICAgYm9vbCBv
dmVybGF5KCkgY29uc3QgeyByZXR1cm4gUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvbG9jYWxP
dmVybGF5IixmYWxzZSkudG9Cb29sKCk7IH0KKyAgICBib29sIGRldGFpbGVkKCkgY29uc3QgeyBy
ZXR1cm4gUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvbG9jYWxEZXRhaWxlZCIsZmFsc2UpLnRv
Qm9vbCgpOyB9CisgICAgYm9vbCBzdHJlYW1EZXRhaWxlZCgpIGNvbnN0IHsgcmV0dXJuIFFTZXR0
aW5ncygpLnZhbHVlKCJlY2xpcHNlL3N0cmVhbURldGFpbGVkIix0cnVlKS50b0Jvb2woKTsgfQor
ICAgIGludCBwb3NpdGlvbigpIGNvbnN0IHsgcmV0dXJuIHFCb3VuZCgwLFFTZXR0aW5ncygpLnZh
bHVlKCJlY2xpcHNlL2xvY2FsUG9zaXRpb24iLDEpLnRvSW50KCksMyk7IH0KKyAgICBpbnQgb3Bh
Y2l0eSgpIGNvbnN0IHsgcmV0dXJuIHFCb3VuZCg0MCxRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBz
ZS9vdmVybGF5T3BhY2l0eSIsODUpLnRvSW50KCksMTAwKTsgfQorICAgIGludCByZWZyZXNoU2Vj
b25kcygpIGNvbnN0IHsgcmV0dXJuIHFCb3VuZCgxLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNl
L2hhcmR3YXJlUmVmcmVzaCIsMikudG9JbnQoKSw1KTsgfQorICAgIFFTdHJpbmdMaXN0IGZpZWxk
cygpIGNvbnN0IHsgcmV0dXJuIFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2FsRmllbGRz
IixRU3RyaW5nTGlzdHsiY3B1IiwibWVtb3J5IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3Jr
IiwiYmF0dGVyeSJ9KS50b1N0cmluZ0xpc3QoKTsgfQorICAgIHZvaWQgc2V0T3ZlcmxheShib29s
IHYpIHsgc2F2ZSgibG9jYWxPdmVybGF5Iix2KTsgfQorICAgIHZvaWQgc2V0RGV0YWlsZWQoYm9v
bCB2KSB7IHNhdmUoImxvY2FsRGV0YWlsZWQiLHYpOyB9CisgICAgdm9pZCBzZXRTdHJlYW1EZXRh
aWxlZChib29sIHYpIHsgc2F2ZSgic3RyZWFtRGV0YWlsZWQiLHYpOyB9CisgICAgdm9pZCBzZXRQ
b3NpdGlvbihpbnQgdikgeyBzYXZlKCJsb2NhbFBvc2l0aW9uIixxQm91bmQoMCx2LDMpKTsgfQor
ICAgIHZvaWQgc2V0T3BhY2l0eShpbnQgdikgeyBzYXZlKCJvdmVybGF5T3BhY2l0eSIscUJvdW5k
KDQwLHYsMTAwKSk7IH0KKyAgICB2b2lkIHNldFJlZnJlc2hTZWNvbmRzKGludCB2KSB7IHNhdmUo
ImhhcmR3YXJlUmVmcmVzaCIscUJvdW5kKDEsdiw1KSk7IG1fdGltZXIuc2V0SW50ZXJ2YWwocmVm
cmVzaFNlY29uZHMoKSoxMDAwKTsgfQorICAgIHZvaWQgc2V0RmllbGRzKFFTdHJpbmdMaXN0IHYp
OworICAgIFFfSU5WT0tBQkxFIHZvaWQgc2V0QWN0aXZlKGJvb2wgYWN0aXZlKTsKKyAgICBzdGF0
aWMgUVZhcmlhbnRNYXAgc2FtcGxlKGNvbnN0IFFTdHJpbmcmIHJvb3Q9UVN0cmluZygpKTsKKyAg
ICBzdGF0aWMgUVN0cmluZyBvdmVybGF5VGV4dCgpOworc2lnbmFsczoKKyAgICB2b2lkIGNoYW5n
ZWQoKTsKKyAgICB2b2lkIHByZWZlcmVuY2VzQ2hhbmdlZCgpOworcHJpdmF0ZToKKyAgICB2b2lk
IHJlZnJlc2goKTsKKyAgICB2b2lkIHNhdmUoUVN0cmluZyBrZXksIFFWYXJpYW50IHZhbHVlKSB7
IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlLyIra2V5LHZhbHVlKTsgZW1pdCBwcmVmZXJl
bmNlc0NoYW5nZWQoKTsgfQorICAgIFFUaW1lciBtX3RpbWVyOworICAgIFFWYXJpYW50TWFwIG1f
cmVhZGluZ3M7CisgICAgUVZhcmlhbnRMaXN0IG1faGlzdG9yeTsKK307CmRpZmYgLS1naXQgYS9h
cHAvbW9vbmxpZ2h0b3MvbWFuYWdlZHVwZGF0ZXMuY3BwIGIvYXBwL21vb25saWdodG9zL21hbmFn
ZWR1cGRhdGVzLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi4yYmZjYmZk
Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL21hbmFnZWR1cGRhdGVzLmNwcApA
QCAtMCwwICsxLDEzMiBAQAorLy8gRWNsaXBzZU9TIG93bnMgdGhpcyBjdXN0b21pemVkIG5hdGl2
ZSBjbGllbnQuIE5vIGZlZWQgcmVxdWVzdHMsIGFzc2V0CisvLyBkb3dubG9hZHMsIHN3YXBzIG9y
IHJlbGF1bmNoZXMgYXJlIGNvbXBpbGVkIGludG8gdGhpcyB1cGRhdGUgaW1wbGVtZW50YXRpb24u
CisjaW5jbHVkZSAiLi4vYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5oIgorI2luY2x1ZGUgPFFD
b3JlQXBwbGljYXRpb24+CisjaW5jbHVkZSA8UUpzb25PYmplY3Q+CisKK3N0YXRpYyBRU3RyaW5n
IHN0cmlwQnVpbGRNZXRhZGF0YShjb25zdCBRU3RyaW5nJiB2ZXJzaW9uKQoreworICAgIGludCBw
bHVzSWR4ID0gdmVyc2lvbi5pbmRleE9mKCcrJyk7CisgICAgcmV0dXJuIHBsdXNJZHggPj0gMCA/
IHZlcnNpb24ubGVmdChwbHVzSWR4KSA6IHZlcnNpb247Cit9CisKK3N0YXRpYyBib29sIGlzTnVt
ZXJpY0lkZW50aWZpZXIoY29uc3QgUVN0cmluZyYgcykKK3sKKyAgICBpZiAocy5pc0VtcHR5KCkp
IHsKKyAgICAgICAgcmV0dXJuIGZhbHNlOworICAgIH0KKyAgICBmb3IgKGNvbnN0IFFDaGFyJiBj
IDogcykgeworICAgICAgICBpZiAoIWMuaXNEaWdpdCgpKSB7CisgICAgICAgICAgICByZXR1cm4g
ZmFsc2U7CisgICAgICAgIH0KKyAgICB9CisgICAgcmV0dXJuIHRydWU7Cit9CisKK2ludCBBdXRv
VXBkYXRlQ2hlY2tlcjo6Y29tcGFyZVNlbWFudGljVmVyc2lvbnMoY29uc3QgUVN0cmluZyYgdjEs
IGNvbnN0IFFTdHJpbmcmIHYyKQoreworICAgIFFTdHJpbmcgczEgPSBzdHJpcEJ1aWxkTWV0YWRh
dGEodjEpOworICAgIFFTdHJpbmcgczIgPSBzdHJpcEJ1aWxkTWV0YWRhdGEodjIpOworCisgICAg
aW50IGRhc2gxID0gczEuaW5kZXhPZignLScpOworICAgIGludCBkYXNoMiA9IHMyLmluZGV4T2Yo
Jy0nKTsKKyAgICBRU3RyaW5nIGJhc2UxID0gZGFzaDEgPj0gMCA/IHMxLmxlZnQoZGFzaDEpIDog
czE7CisgICAgUVN0cmluZyBiYXNlMiA9IGRhc2gyID49IDAgPyBzMi5sZWZ0KGRhc2gyKSA6IHMy
OworICAgIFFTdHJpbmcgcHJlMSA9IGRhc2gxID49IDAgPyBzMS5taWQoZGFzaDEgKyAxKSA6IFFT
dHJpbmcoKTsKKyAgICBRU3RyaW5nIHByZTIgPSBkYXNoMiA+PSAwID8gczIubWlkKGRhc2gyICsg
MSkgOiBRU3RyaW5nKCk7CisKKyAgICAvLyBOdW1lcmljIGJhc2UgdmVyc2lvbnMgY29tcGFyZSBm
aXJzdCAoMC40LjAtYmV0YS4wMDEgPiAwLjMuMCkKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBiYXNl
UGFydHMxID0gYmFzZTEuc3BsaXQoJy4nKTsKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBiYXNlUGFy
dHMyID0gYmFzZTIuc3BsaXQoJy4nKTsKKyAgICBmb3IgKGludCBpID0gMDsgaSA8IHFNYXgoYmFz
ZVBhcnRzMS5jb3VudCgpLCBiYXNlUGFydHMyLmNvdW50KCkpOyBpKyspIHsKKyAgICAgICAgcWxv
bmdsb25nIGIxID0gaSA8IGJhc2VQYXJ0czEuY291bnQoKSA/IGJhc2VQYXJ0czFbaV0udG9Mb25n
TG9uZygpIDogMDsKKyAgICAgICAgcWxvbmdsb25nIGIyID0gaSA8IGJhc2VQYXJ0czIuY291bnQo
KSA/IGJhc2VQYXJ0czJbaV0udG9Mb25nTG9uZygpIDogMDsKKyAgICAgICAgaWYgKGIxICE9IGIy
KSB7CisgICAgICAgICAgICByZXR1cm4gYjEgPCBiMiA/IC0xIDogMTsKKyAgICAgICAgfQorICAg
IH0KKworICAgIC8vIEVxdWFsIGJhc2U6IGEgcmVsZWFzZSB3aXRoIG5vIHByZXJlbGVhc2Ugc3Vm
Zml4IG91dHJhbmtzIGFueSBwcmVyZWxlYXNlCisgICAgaWYgKHByZTEuaXNFbXB0eSgpICE9IHBy
ZTIuaXNFbXB0eSgpKSB7CisgICAgICAgIHJldHVybiBwcmUxLmlzRW1wdHkoKSA/IDEgOiAtMTsK
KyAgICB9CisgICAgaWYgKHByZTEuaXNFbXB0eSgpKSB7CisgICAgICAgIHJldHVybiAwOworICAg
IH0KKworICAgIC8vIFR3byBwcmVyZWxlYXNlczogY29tcGFyZSBkb3Qtc2VwYXJhdGVkIGlkZW50
aWZpZXJzIGxlZnQgdG8gcmlnaHQuCisgICAgLy8gTnVtZXJpYyBpZGVudGlmaWVycyBjb21wYXJl
IG51bWVyaWNhbGx5IChsZWFkaW5nIHplcm9zIHRvbGVyYXRlZCDigJQgb3VyCisgICAgLy8gQ0kg
emVyby1wYWRzIGNvdW50ZXJzKSwgYWxwaGFudW1lcmljIG9uZXMgbGV4aWNhbGx5IGluIEFTQ0lJ
IG9yZGVyLCBhbmQKKyAgICAvLyBudW1lcmljIGFsd2F5cyByYW5rcyBiZWxvdyBhbHBoYW51bWVy
aWMuIFRoaXMgaXMgd2hhdCBvcmRlcnMKKyAgICAvLyAiYWxwaGEiIDwgImJldGEiIDwgInJjIiBh
dCBhbiBlcXVhbCBiYXNlIOKAlCB0aGUgcHJvcGVydHkgdGhlIHByZXZpb3VzCisgICAgLy8gaW1w
bGVtZW50YXRpb24gbGFja2VkIChpdCBza2lwcGVkIHRoZSB3b3JkcyBhbmQgY29tcGFyZWQgb25s
eSBudW1iZXJzLAorICAgIC8vIHNvIDAuMy4wLWJldGEuMDA4IHdyb25nbHkgb3V0cmFua2VkIDAu
My4wLXJjLjAwMikuCisgICAgY29uc3QgUVN0cmluZ0xpc3QgaWRzMSA9IHByZTEuc3BsaXQoJy4n
KTsKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBpZHMyID0gcHJlMi5zcGxpdCgnLicpOworICAgIGZv
ciAoaW50IGkgPSAwOyBpIDwgcU1heChpZHMxLmNvdW50KCksIGlkczIuY291bnQoKSk7IGkrKykg
eworICAgICAgICBpZiAoaSA+PSBpZHMxLmNvdW50KCkpIHsKKyAgICAgICAgICAgIC8vIEVxdWFs
IHByZWZpeCwgZmV3ZXIgZmllbGRzID0gbG93ZXIgcHJlY2VkZW5jZSAowqcxMS40LjQpCisgICAg
ICAgICAgICByZXR1cm4gLTE7CisgICAgICAgIH0KKyAgICAgICAgaWYgKGkgPj0gaWRzMi5jb3Vu
dCgpKSB7CisgICAgICAgICAgICByZXR1cm4gMTsKKyAgICAgICAgfQorICAgICAgICBib29sIG51
bTEgPSBpc051bWVyaWNJZGVudGlmaWVyKGlkczFbaV0pOworICAgICAgICBib29sIG51bTIgPSBp
c051bWVyaWNJZGVudGlmaWVyKGlkczJbaV0pOworICAgICAgICBpZiAobnVtMSAmJiBudW0yKSB7
CisgICAgICAgICAgICBxbG9uZ2xvbmcgcDEgPSBpZHMxW2ldLnRvTG9uZ0xvbmcoKTsKKyAgICAg
ICAgICAgIHFsb25nbG9uZyBwMiA9IGlkczJbaV0udG9Mb25nTG9uZygpOworICAgICAgICAgICAg
aWYgKHAxICE9IHAyKSB7CisgICAgICAgICAgICAgICAgcmV0dXJuIHAxIDwgcDIgPyAtMSA6IDE7
CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICAgICAgZWxzZSBpZiAobnVtMSAhPSBudW0y
KSB7CisgICAgICAgICAgICAvLyBOdW1lcmljIGlkZW50aWZpZXJzIHJhbmsgYmVsb3cgYWxwaGFu
dW1lcmljIG9uZXMgKMKnMTEuNC4zKQorICAgICAgICAgICAgcmV0dXJuIG51bTEgPyAtMSA6IDE7
CisgICAgICAgIH0KKyAgICAgICAgZWxzZSB7CisgICAgICAgICAgICBpbnQgY21wID0gUVN0cmlu
Zzo6Y29tcGFyZShpZHMxW2ldLCBpZHMyW2ldKTsKKyAgICAgICAgICAgIGlmIChjbXAgIT0gMCkg
eworICAgICAgICAgICAgICAgIHJldHVybiBjbXAgPCAwID8gLTEgOiAxOworICAgICAgICAgICAg
fQorICAgICAgICB9CisgICAgfQorICAgIHJldHVybiAwOworfQorCitBdXRvVXBkYXRlQ2hlY2tl
cjo6QXV0b1VwZGF0ZUNoZWNrZXIoUU9iamVjdCogcGFyZW50KSA6CisgICAgUU9iamVjdChwYXJl
bnQpLCBtX0NoZWNrSW5GbGlnaHQoZmFsc2UpLCBtX0NoZWNrSXNNYW51YWwoZmFsc2UpLAorICAg
IG1fVXBkYXRlQXZhaWxhYmxlKGZhbHNlKSwgbV9PZmZlckF2YWlsYWJsZShmYWxzZSksIG1fSW5z
dGFsbGluZyhmYWxzZSkKK3sKKyAgICBjbGVhck9mZmVyKCk7CisgICAgc2V0U3RhdHVzKHRyKCIl
MS4gVXBkYXRlcyBhcmUgbWFuYWdlZCBieSBFY2xpcHNlT1MuIEdldCB0aGUgbWF0Y2hpbmcgT1Mg
aW1hZ2UgZnJvbSAlMjsgdXBzdHJlYW0gVmliZW1pcyB1cGRhdGVzIGFyZSBkaXNhYmxlZC4iKS5h
cmcoY3VycmVudFZlcnNpb24oKSwgbV9SZWxlYXNlVXJsKSk7Cit9CitRU3RyaW5nIEF1dG9VcGRh
dGVDaGVja2VyOjpjdXJyZW50VmVyc2lvbigpIGNvbnN0Cit7CisgICAgcmV0dXJuIHRyKCJFY2xp
cHNlICUxIMK3IEVjbGlwc2VPUyBjdXN0b21pemVkIikuYXJnKFFDb3JlQXBwbGljYXRpb246OmFw
cGxpY2F0aW9uVmVyc2lvbigpKTsKK30KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6OmNsZWFyT2Zm
ZXIoKQoreworICAgIG1fVXBkYXRlQXZhaWxhYmxlID0gZmFsc2U7IG1fT2ZmZXJBdmFpbGFibGUg
PSBmYWxzZTsKKyAgICBtX09mZmVyVmVyc2lvbi5jbGVhcigpOyBtX0Fzc2V0VXJsLmNsZWFyKCk7
IG1fT2ZmZXJUaWVyID0gLTE7CisgICAgbV9SZWxlYXNlVXJsID0gUVN0cmluZ0xpdGVyYWwoImh0
dHBzOi8vZ2l0aHViLmNvbS90aDNkM2NrM3IvTW9vbmxpZ2h0LU9TL3JlbGVhc2VzIik7Cit9Cit2
b2lkIEF1dG9VcGRhdGVDaGVja2VyOjpzZXRTdGF0dXMoY29uc3QgUVN0cmluZyYgbWVzc2FnZSkK
K3sKKyAgICBpZiAobV9TdGF0dXNNZXNzYWdlICE9IG1lc3NhZ2UpIHsgbV9TdGF0dXNNZXNzYWdl
ID0gbWVzc2FnZTsgZW1pdCBzdGF0ZUNoYW5nZWQoKTsgfQorfQordm9pZCBBdXRvVXBkYXRlQ2hl
Y2tlcjo6c3RhcnQoKSB7IC8qIE5vIHRpbWVyIGFuZCBubyBiYWNrZ3JvdW5kIHVwZGF0ZSByZXF1
ZXN0cy4gKi8gfQorYm9vbCBBdXRvVXBkYXRlQ2hlY2tlcjo6Y2FuSW5zdGFsbFVwZGF0ZXMoKSBj
b25zdCB7IHJldHVybiBmYWxzZTsgfQorYm9vbCBBdXRvVXBkYXRlQ2hlY2tlcjo6Y2FuSW5zdGFs
bCgpIGNvbnN0IHsgcmV0dXJuIGZhbHNlOyB9Cit2b2lkIEF1dG9VcGRhdGVDaGVja2VyOjpjaGFu
bmVsQ2hhbmdlZCgpIHsgY2hlY2tOb3coKTsgfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6Y2hl
Y2tOb3coKQoreworICAgIGNsZWFyT2ZmZXIoKTsKKyAgICBzZXRTdGF0dXModHIoIlVwZGF0ZXMg
YXJlIG1hbmFnZWQgYnkgRWNsaXBzZU9TLiBEb3dubG9hZCB0aGUgbWF0Y2hpbmcgT1MgaW1hZ2Ug
ZnJvbSAlMS4gVGhpcyBjbGllbnQgbmV2ZXIgaW5zdGFsbHMgdXBzdHJlYW0gVmliZW1pcyByZWxl
YXNlcy4iKS5hcmcobV9SZWxlYXNlVXJsKSk7CisgICAgZW1pdCBzdGF0ZUNoYW5nZWQoKTsgZW1p
dCBjaGVja0NvbXBsZXRlZCh0cnVlLCBmYWxzZSk7Cit9Cit2b2lkIEF1dG9VcGRhdGVDaGVja2Vy
OjppbnN0YWxsKCkKK3sKKyAgICBjaGVja05vdygpOworICAgIGVtaXQgaW5zdGFsbEZhaWxlZCh0
cigiU3RhbmRhbG9uZSBWaWJlbWlzIGluc3RhbGxhdGlvbiBpcyBkaXNhYmxlZCBpbiBFY2xpcHNl
T1MuIiksIG1fUmVsZWFzZVVybCk7Cit9CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3Mvb3Zl
cmxheXN0eWxlLmggYi9hcHAvbW9vbmxpZ2h0b3Mvb3ZlcmxheXN0eWxlLmgKbmV3IGZpbGUgbW9k
ZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uY2UzMGZhZgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9t
b29ubGlnaHRvcy9vdmVybGF5c3R5bGUuaApAQCAtMCwwICsxLDIwIEBACisjcHJhZ21hIG9uY2UK
KyNpbmNsdWRlIDxRSW1hZ2U+CisjaW5jbHVkZSA8UVBhaW50ZXI+CisjaW5jbHVkZSA8UUNvbG9y
PgorbmFtZXNwYWNlIEVjbGlwc2VPdmVybGF5U3R5bGUgeworaW5saW5lIFFDb2xvciBhY2NlbnQo
aW50IGluZGV4KSB7CisgICAgY29uc3QgY2hhciogY29sb3JzW109eyIjMDBDQ0NDIiwiIzdDOENG
OCIsIiMzRUQ1OTgiLCIjRjBBODY4IiwiI0RDMzY1OCIsIiNGMjVENjQiLCIjRjU4MzQ3IiwiI0Yx
QkM0NSIsIiNCN0RDNjMiLCIjNjNDQ0FFIiwiIzYzQzRFRCIsIiM2QzlGRkYiLCIjQUQ4NUY1Iiwi
I0U5NzZCQyIsIiNDQUQwREEiLCIjRDk5NUFDIn07CisgICAgcmV0dXJuIFFDb2xvcihjb2xvcnNb
cUJvdW5kKDAsaW5kZXgsMTUpXSk7Cit9CitpbmxpbmUgUUltYWdlIHBhbmVsKFFTaXplIHNpemUs
aW50IGFjY2VudEluZGV4LGludCBvcGFjaXR5KSB7CisgICAgaWYoc2l6ZS53aWR0aCgpPDMyIHx8
IHNpemUuaGVpZ2h0KCk8MzIgfHwgc2l6ZS53aWR0aCgpPjIwNDggfHwgc2l6ZS5oZWlnaHQoKT40
MDk2KSByZXR1cm4ge307CisgICAgUUltYWdlIGltYWdlKHNpemUsUUltYWdlOjpGb3JtYXRfUkdC
QTg4ODgpOyBpbWFnZS5maWxsKFF0Ojp0cmFuc3BhcmVudCk7CisgICAgUVBhaW50ZXIgcGFpbnRl
cigmaW1hZ2UpOyBwYWludGVyLnNldFJlbmRlckhpbnQoUVBhaW50ZXI6OkFudGlhbGlhc2luZyk7
CisgICAgUUNvbG9yIGJnKCIjMTUxMTE1Iik7IGJnLnNldEFscGhhKHFCb3VuZCg0MCxvcGFjaXR5
LDEwMCkqMjU1LzEwMCk7CisgICAgcGFpbnRlci5zZXRCcnVzaChiZyk7IHBhaW50ZXIuc2V0UGVu
KFFQZW4oYWNjZW50KGFjY2VudEluZGV4KSwxKSk7CisgICAgcGFpbnRlci5kcmF3Um91bmRlZFJl
Y3QoUVJlY3RGKDEsMSxpbWFnZS53aWR0aCgpLTIsaW1hZ2UuaGVpZ2h0KCktMiksMTIsMTIpOwor
ICAgIHBhaW50ZXIuc2V0UGVuKFFQZW4oYWNjZW50KGFjY2VudEluZGV4KSwzKSk7IHBhaW50ZXIu
ZHJhd0xpbmUoMTUsOCxpbWFnZS53aWR0aCgpLTE1LDgpOworICAgIHJldHVybiBpbWFnZTsKK30K
K30KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAgYi9hcHAv
bW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4
IDAwMDAwMDAuLjNlZTNmZjkKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3Mvc3lz
dGVtY29udHJvbHMuY3BwCkBAIC0wLDAgKzEsODIgQEAKKyNpbmNsdWRlICJzeXN0ZW1jb250cm9s
cy5oIgorI2luY2x1ZGUgPFFDb3JlQXBwbGljYXRpb24+CisjaW5jbHVkZSA8UUpzb25Eb2N1bWVu
dD4KKyNpbmNsdWRlIDxRSnNvbk9iamVjdD4KKyNpbmNsdWRlIDxRSnNvbkFycmF5PgorI2luY2x1
ZGUgPFFRbWxFbmdpbmU+CisjaW5jbHVkZSA8UUZpbGVJbmZvPgorU3lzdGVtQ29udHJvbHM6OlN5
c3RlbUNvbnRyb2xzKFFPYmplY3QqIHBhcmVudCkgOiBRT2JqZWN0KHBhcmVudCkgeworICAgIG1f
dGltZW91dC5zZXRTaW5nbGVTaG90KHRydWUpOworICAgIGNvbm5lY3QoJm1fdGltZW91dCwgJlFU
aW1lcjo6dGltZW91dCwgdGhpcywgW3RoaXNdIHsgZmFpbCh0cigiT3BlcmF0aW9uIHRpbWVkIG91
dC4gUmV0cnkgb3IgdXNlIHRoZSBkaWFnbm9zdGljIHNoZWxsLiIpKTsgfSk7CisgICAgY29ubmVj
dCgmbV9wcm9jZXNzLCAmUVByb2Nlc3M6OnN0YXJ0ZWQsIHRoaXMsIFt0aGlzXSB7IHJlcXVlc3Qo
bV9tb2RlICsgIi1saXN0Iik7IH0pOworICAgIGNvbm5lY3QoJm1fcHJvY2VzcywgJlFQcm9jZXNz
OjpyZWFkeVJlYWRTdGFuZGFyZEVycm9yLCB0aGlzLCBbdGhpc10geyBtX3Byb2Nlc3MucmVhZEFs
bFN0YW5kYXJkRXJyb3IoKTsgfSk7CisgICAgY29ubmVjdCgmbV9wcm9jZXNzLCAmUVByb2Nlc3M6
OnJlYWR5UmVhZFN0YW5kYXJkT3V0cHV0LCB0aGlzLCBbdGhpc10geworICAgICAgICBtX2J1ZmZl
ciArPSBtX3Byb2Nlc3MucmVhZEFsbFN0YW5kYXJkT3V0cHV0KCk7CisgICAgICAgIGlmIChtX2J1
ZmZlci5zaXplKCkgPiA2NTUzNikgeyBmYWlsKHRyKCJJbnZhbGlkIHN5c3RlbSByZXNwb25zZS4i
KSk7IHJldHVybjsgfQorICAgICAgICB3aGlsZSAobV9idWZmZXIuY29udGFpbnMoJ1xuJykpIHsK
KyAgICAgICAgICAgIGludCBlbmQgPSBtX2J1ZmZlci5pbmRleE9mKCdcbicpOworICAgICAgICAg
ICAgUUpzb25QYXJzZUVycm9yIGVycm9yOworICAgICAgICAgICAgYXV0byBkb2N1bWVudCA9IFFK
c29uRG9jdW1lbnQ6OmZyb21Kc29uKG1fYnVmZmVyLmxlZnQoZW5kKSwgJmVycm9yKTsKKyAgICAg
ICAgICAgIG1fYnVmZmVyLnJlbW92ZSgwLCBlbmQgKyAxKTsKKyAgICAgICAgICAgIGlmIChlcnJv
ci5lcnJvciAhPSBRSnNvblBhcnNlRXJyb3I6Ok5vRXJyb3IgfHwgIWRvY3VtZW50LmlzT2JqZWN0
KCkpIHsgZmFpbCh0cigiSW52YWxpZCBzeXN0ZW0gcmVzcG9uc2UuIikpOyByZXR1cm47IH0KKyAg
ICAgICAgICAgIGF1dG8gdmFsdWUgPSBkb2N1bWVudC5vYmplY3QoKTsKKyAgICAgICAgICAgIGlm
ICh2YWx1ZS5jb250YWlucygicHJvbXB0IikpIHsKKyAgICAgICAgICAgICAgICBtX3Byb21wdCA9
IHZhbHVlLnZhbHVlKCJwcm9tcHQiKS50b1N0cmluZygpLmxlZnQoMTAyNCk7CisgICAgICAgICAg
ICAgICAgbV90aW1lb3V0LnN0YXJ0KDEyMDAwMCk7CisgICAgICAgICAgICB9CisgICAgICAgICAg
ICBpZiAodmFsdWUuY29udGFpbnMoIml0ZW1zIikpIHsKKyAgICAgICAgICAgICAgICBhdXRvIGVu
dHJpZXMgPSB2YWx1ZS52YWx1ZSgiaXRlbXMiKS50b0FycmF5KCk7CisgICAgICAgICAgICAgICAg
aWYgKGVudHJpZXMuc2l6ZSgpID4gNjQpIHsgZmFpbCh0cigiSW52YWxpZCBkZXZpY2UgbGlzdC4i
KSk7IHJldHVybjsgfQorICAgICAgICAgICAgICAgIG1faXRlbXMgPSBlbnRyaWVzLnRvVmFyaWFu
dExpc3QoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGlmICh2YWx1ZS52YWx1ZSgic3Rh
dGUiKS5pc09iamVjdCgpKSBtX3N0YXRlID0gdmFsdWUudmFsdWUoInN0YXRlIikudG9PYmplY3Qo
KS50b1ZhcmlhbnRNYXAoKTsKKyAgICAgICAgICAgIGlmKHZhbHVlLmNvbnRhaW5zKCJzdGF0dXMi
KSkgbV9zdGF0dXM9dmFsdWUudmFsdWUoInN0YXR1cyIpLnRvU3RyaW5nKCkubGVmdCgxMDI0KTsK
KyAgICAgICAgICAgIGlmKHZhbHVlLmNvbnRhaW5zKCJlcnJvciIpKSBtX3N0YXR1cz12YWx1ZS52
YWx1ZSgiZXJyb3IiKS50b1N0cmluZygpLmxlZnQoMTAyNCk7CisgICAgICAgICAgICBpZiAodmFs
dWUudmFsdWUoImRvbmUiKS50b0Jvb2woKSkgeyBtX3RpbWVvdXQuc3RvcCgpOyBtX2J1c3k9ZmFs
c2U7IG1fcHJvbXB0LmNsZWFyKCk7IH0KKyAgICAgICAgICAgIGVtaXQgY2hhbmdlZCgpOworICAg
ICAgICB9CisgICAgfSk7CisgICAgY29ubmVjdCgmbV9wcm9jZXNzLCAmUVByb2Nlc3M6OmVycm9y
T2NjdXJyZWQsIHRoaXMsIFt0aGlzXShRUHJvY2Vzczo6UHJvY2Vzc0Vycm9yKSB7CisgICAgICAg
IGlmICghbV9tb2RlLmlzRW1wdHkoKSkgZmFpbCh0cigiU3lzdGVtIGNvbnRyb2xzIGFyZSB1bmF2
YWlsYWJsZS4gVXNlIHRoZSBkaWFnbm9zdGljIHNoZWxsLiIpKTsKKyAgICB9KTsKKyAgICBjb25u
ZWN0KCZtX3Byb2Nlc3MsIFFPdmVybG9hZDxpbnQsUVByb2Nlc3M6OkV4aXRTdGF0dXM+OjpvZigm
UVByb2Nlc3M6OmZpbmlzaGVkKSwgdGhpcywgW3RoaXNdKGludCwgUVByb2Nlc3M6OkV4aXRTdGF0
dXMpIHsKKyAgICAgICAgaWYgKCFtX21vZGUuaXNFbXB0eSgpKSB7IG1fdGltZW91dC5zdG9wKCk7
IG1fYnVzeSA9IGZhbHNlOyBtX3Byb21wdC5jbGVhcigpOyBtX3N0YXR1cyA9IHRyKCJTeXN0ZW0g
aGVscGVyIHN0b3BwZWQuIENsb3NlIGFuZCByZW9wZW4gdGhpcyBwYW5lbC4iKTsgZW1pdCBjaGFu
Z2VkKCk7IH0KKyAgICB9KTsKK30KK1N5c3RlbUNvbnRyb2xzOjp+U3lzdGVtQ29udHJvbHMoKSB7
IGNsb3NlKCk7IGlmICghbV9wcm9jZXNzLndhaXRGb3JGaW5pc2hlZCg1MDApKSB7IG1fcHJvY2Vz
cy5raWxsKCk7IG1fcHJvY2Vzcy53YWl0Rm9yRmluaXNoZWQoNTAwKTsgfSB9Cit2b2lkIFN5c3Rl
bUNvbnRyb2xzOjpzZW5kKGNvbnN0IFFKc29uT2JqZWN0JiB2YWx1ZSkgeyBtX3Byb2Nlc3Mud3Jp
dGUoUUpzb25Eb2N1bWVudCh2YWx1ZSkudG9Kc29uKFFKc29uRG9jdW1lbnQ6OkNvbXBhY3QpICsg
J1xuJyk7IH0KK3ZvaWQgU3lzdGVtQ29udHJvbHM6Om9wZW4oUVN0cmluZyBtb2RlKSB7CisgICAg
aWYgKG1vZGUgIT0gIndpZmkiICYmIG1vZGUgIT0gImJ0IiAmJiBtb2RlICE9ICJjZW50ZXIiKSBy
ZXR1cm47CisgICAgY2xvc2UoKTsKKyAgICBpZiAobV9wcm9jZXNzLnN0YXRlKCkgIT0gUVByb2Nl
c3M6Ok5vdFJ1bm5pbmcpIHsgbV9wcm9jZXNzLmtpbGwoKTsgbV9wcm9jZXNzLndhaXRGb3JGaW5p
c2hlZCg1MDApOyB9CisgICAgbV9tb2RlID0gbW9kZTsgbV9pdGVtcy5jbGVhcigpOyBtX3N0YXRl
LmNsZWFyKCk7IG1fYnVmZmVyLmNsZWFyKCk7IG1fc3RhdHVzID0gdHIoIkxvYWRpbmfigKYiKTsg
ZW1pdCBjaGFuZ2VkKCk7CisgICAgUVN0cmluZyBoZWxwZXIgPSAiL3Vzci9sb2NhbC9saWJleGVj
L21vb25saWdodC1vcy9zeXN0ZW0tY29udHJvbHMucHkiOworI2lmZGVmIE1PT05MSUdIVF9DT05U
Uk9MU19URVNUCisgICAgaGVscGVyID0gcUVudmlyb25tZW50VmFyaWFibGUoIk1PT05MSUdIVF9D
T05UUk9MU19GSVhUVVJFIiwgaGVscGVyKTsKKyNlbmRpZgorICAgIG1fcHJvY2Vzcy5zdGFydCgi
cHl0aG9uMyIsIHtoZWxwZXJ9KTsKK30KK3ZvaWQgU3lzdGVtQ29udHJvbHM6OnJlcXVlc3QoUVN0
cmluZyBhY3Rpb24sIFFTdHJpbmcgaWQsIGJvb2wgY29uZmlybSkgeworICAgIGlmIChtX2J1c3kg
fHwgbV9wcm9jZXNzLnN0YXRlKCkgIT0gUVByb2Nlc3M6OlJ1bm5pbmcgfHwgIWFjdGlvbi5zdGFy
dHNXaXRoKG1fbW9kZSArICItIikpIHJldHVybjsKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBhbGxv
d2VkID0geyJ3aWZpLWxpc3QiLCAid2lmaS1zY2FuIiwgIndpZmktY29ubmVjdCIsICJ3aWZpLWRp
c2Nvbm5lY3QiLCAiYnQtbGlzdCIsICJidC1zY2FuIiwgImJ0LWNvbm5lY3QiLCAiYnQtZGlzY29u
bmVjdCIsICJidC1mb3JnZXQiLCAiY2VudGVyLXdpZmktcmFkaW8iLCAiY2VudGVyLWJ0LXJhZGlv
IiwgImNlbnRlci1haXJwb2RzIiwgImNlbnRlci10ZXN0LXNvdW5kIiwgImNlbnRlci1pZGxlIiwg
ImNlbnRlci1wb2ludGVyLXNwZWVkIiwgImNlbnRlci1wb2ludGVyLW5hdHVyYWwiLCAiY2VudGVy
LXBvaW50ZXItdGFwIiwgImNlbnRlci1kaXNwbGF5IiwgImNlbnRlci1mcm9udGVuZCIsICJjZW50
ZXItcmVzdGFydC1mcm9udGVuZCIsICJjZW50ZXItbGlzdCIsICJjZW50ZXItdm9sdW1lIiwgImNl
bnRlci1tdXRlIiwgImNlbnRlci1vdXRwdXQiLCAiY2VudGVyLXNjcmVlbiIsICJjZW50ZXIta2V5
Ym9hcmQiLCAiY2VudGVyLXJlYm9vdCIsICJjZW50ZXItcG93ZXJvZmYiLCAiY2VudGVyLXN1c3Bl
bmQiLCAiY2VudGVyLXJlcG9ydCJ9OworICAgIGlmICghYWxsb3dlZC5jb250YWlucyhhY3Rpb24p
KSByZXR1cm47CisgICAgbV9idXN5ID0gdHJ1ZTsgbV9wcm9tcHQuY2xlYXIoKTsgbV9zdGF0dXMg
PSBhY3Rpb24uZW5kc1dpdGgoInNjYW4iKSA/IHRyKCJTdGFydGluZyBzY2Fu4oCmIikgOiB0cigi
V29ya2luZ+KApiIpOyBtX3RpbWVvdXQuc3RhcnQoYWN0aW9uLmVuZHNXaXRoKCJzY2FuIikgPyAz
MDAwMCA6IDEwMDAwMCk7CisgICAgc2VuZCh7eyJhY3Rpb24iLCBhY3Rpb259LCB7ImlkIiwgaWR9
LCB7ImNvbmZpcm0iLCBjb25maXJtfX0pOyBlbWl0IGNoYW5nZWQoKTsKK30KK3ZvaWQgU3lzdGVt
Q29udHJvbHM6OmFuc3dlcihRU3RyaW5nIHZhbHVlKSB7CisgICAgaWYgKCFtX2J1c3kgfHwgbV9w
cm9tcHQuaXNFbXB0eSgpIHx8IHZhbHVlLnNpemUoKSA+IDQwOTYgfHwgdmFsdWUuY29udGFpbnMo
J1xuJykgfHwgdmFsdWUuY29udGFpbnMoJ1xyJykgfHwgdmFsdWUuY29udGFpbnMoUUNoYXIoMCkp
KSByZXR1cm47CisgICAgc2VuZCh7eyJhY3Rpb24iLCAiYW5zd2VyIn0sIHsidmFsdWUiLCB2YWx1
ZX19KTsgbV9wcm9tcHQuY2xlYXIoKTsgbV90aW1lb3V0LnN0YXJ0KDEyMDAwMCk7IGVtaXQgY2hh
bmdlZCgpOworfQordm9pZCBTeXN0ZW1Db250cm9sczo6Y2xvc2UoKSB7CisgICAgbV9tb2RlLmNs
ZWFyKCk7IG1fdGltZW91dC5zdG9wKCk7IG1fYnVzeSA9IGZhbHNlOyBtX3Byb21wdC5jbGVhcigp
OyBtX2J1ZmZlci5jbGVhcigpOworICAgIGlmIChtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vz
czo6Tm90UnVubmluZykgeworICAgICAgICBtX3Byb2Nlc3MudGVybWluYXRlKCk7CisgICAgICAg
IFFUaW1lcjo6c2luZ2xlU2hvdCg0MDAwLCB0aGlzLCBbdGhpc10geyBpZiAobV9tb2RlLmlzRW1w
dHkoKSAmJiBtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgbV9wcm9j
ZXNzLmtpbGwoKTsgfSk7CisgICAgfQorICAgIGVtaXQgY2hhbmdlZCgpOworfQordm9pZCBTeXN0
ZW1Db250cm9sczo6ZmFpbChRU3RyaW5nIG1lc3NhZ2UpIHsgY2xvc2UoKTsgbV9zdGF0dXMgPSBt
ZXNzYWdlOyBlbWl0IGNoYW5nZWQoKTsgfQorc3RhdGljIHZvaWQgcmVnaXN0ZXJTeXN0ZW1Db250
cm9scygpIHsKKyAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGU8U3lzdGVtQ29udHJvbHM+KCJT
eXN0ZW1Db250cm9scyIsIDEsIDAsICJTeXN0ZW1Db250cm9scyIsIFtdKFFRbWxFbmdpbmUqLCBR
SlNFbmdpbmUqKSAtPiBRT2JqZWN0KiB7IHJldHVybiBuZXcgU3lzdGVtQ29udHJvbHMoKTsgfSk7
Cit9CitRX0NPUkVBUFBfU1RBUlRVUF9GVU5DVElPTihyZWdpc3RlclN5c3RlbUNvbnRyb2xzKQpk
aWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmggYi9hcHAvbW9vbmxp
Z2h0b3Mvc3lzdGVtY29udHJvbHMuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
Li4xOGU5ZGViCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3N5c3RlbWNvbnRy
b2xzLmgKQEAgLTAsMCArMSwzOSBAQAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4K
KyNpbmNsdWRlIDxRSnNvbk9iamVjdD4KKyNpbmNsdWRlIDxRUHJvY2Vzcz4KKyNpbmNsdWRlIDxR
VGltZXI+CisjaW5jbHVkZSA8UVZhcmlhbnRMaXN0PgorI2luY2x1ZGUgPFFWYXJpYW50TWFwPgor
Y2xhc3MgU3lzdGVtQ29udHJvbHMgOiBwdWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpFQ1QKKyAg
ICBRX1BST1BFUlRZKFFWYXJpYW50TWFwIHN0YXRlIFJFQUQgc3RhdGUgTk9USUZZIGNoYW5nZWQp
CisgICAgUV9QUk9QRVJUWShRVmFyaWFudExpc3QgaXRlbXMgUkVBRCBpdGVtcyBOT1RJRlkgY2hh
bmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgc3RhdHVzIFJFQUQgc3RhdHVzIE5PVElGWSBj
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBwcm9tcHQgUkVBRCBwcm9tcHQgTk9USUZZ
IGNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShib29sIGJ1c3kgUkVBRCBidXN5IE5PVElGWSBjaGFu
Z2VkKQorcHVibGljOgorICAgIGV4cGxpY2l0IFN5c3RlbUNvbnRyb2xzKFFPYmplY3QqIHBhcmVu
dCA9IG51bGxwdHIpOworICAgIH5TeXN0ZW1Db250cm9scygpOworICAgIFFWYXJpYW50TWFwIHN0
YXRlKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0ZTsgfQorICAgIFFWYXJpYW50TGlzdCBpdGVtcygp
IGNvbnN0IHsgcmV0dXJuIG1faXRlbXM7IH0KKyAgICBRU3RyaW5nIHN0YXR1cygpIGNvbnN0IHsg
cmV0dXJuIG1fc3RhdHVzOyB9CisgICAgUVN0cmluZyBwcm9tcHQoKSBjb25zdCB7IHJldHVybiBt
X3Byb21wdDsgfQorICAgIGJvb2wgYnVzeSgpIGNvbnN0IHsgcmV0dXJuIG1fYnVzeTsgfQorICAg
IFFfSU5WT0tBQkxFIHZvaWQgb3BlbihRU3RyaW5nIG1vZGUpOworICAgIFFfSU5WT0tBQkxFIHZv
aWQgcmVxdWVzdChRU3RyaW5nIGFjdGlvbiwgUVN0cmluZyBpZCA9IFFTdHJpbmcoKSwgYm9vbCBj
b25maXJtID0gZmFsc2UpOworICAgIFFfSU5WT0tBQkxFIHZvaWQgYW5zd2VyKFFTdHJpbmcgdmFs
dWUpOworICAgIFFfSU5WT0tBQkxFIHZvaWQgY2xvc2UoKTsKK3NpZ25hbHM6CisgICAgdm9pZCBj
aGFuZ2VkKCk7Citwcml2YXRlOgorICAgIHZvaWQgc2VuZChjb25zdCBRSnNvbk9iamVjdCYgdmFs
dWUpOworICAgIHZvaWQgZmFpbChRU3RyaW5nIG1lc3NhZ2UpOworICAgIFFQcm9jZXNzIG1fcHJv
Y2VzczsKKyAgICBRVGltZXIgbV90aW1lb3V0OworICAgIFFCeXRlQXJyYXkgbV9idWZmZXI7Cisg
ICAgUVZhcmlhbnRMaXN0IG1faXRlbXM7CisgICAgUVZhcmlhbnRNYXAgbV9zdGF0ZTsKKyAgICBR
U3RyaW5nIG1fbW9kZSwgbV9zdGF0dXMsIG1fcHJvbXB0OworICAgIGJvb2wgbV9idXN5ID0gZmFs
c2U7Cit9OwpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL0hhcm5lc3MucW1sIGIv
YXBwL21vb25saWdodG9zL3Rlc3RzL0hhcm5lc3MucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0Cmlu
ZGV4IDAwMDAwMDAuLmJmOTA5NjEKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3Mv
dGVzdHMvSGFybmVzcy5xbWwKQEAgLTAsMCArMSwyNiBAQAoraW1wb3J0IFF0UXVpY2sgMi45Citp
bXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVy
aWFsIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgU3RyZWFtaW5nUHJl
ZmVyZW5jZXMgMS4wCitpbXBvcnQgRWNsaXBzZVByb2ZpbGVzIDEuMAoraW1wb3J0ICIuLi8uLi9n
dWkiCitBcHBsaWNhdGlvbldpbmRvdyB7CisgICAgTWF0ZXJpYWwudGhlbWU6IE1hdGVyaWFsLkRh
cmsKKyAgICBNYXRlcmlhbC5hY2NlbnQ6IFZiVG9rZW5zLmFjY2VudAorICAgIE1hdGVyaWFsLmJh
Y2tncm91bmQ6IFZiVG9rZW5zLmJnV2luZG93CisgICAgTWF0ZXJpYWwuZm9yZWdyb3VuZDogVmJU
b2tlbnMudGV4dAorICAgIGNvbG9yOiBWYlRva2Vucy5iZ0FwcAorICAgIHdpZHRoOiAxMjgwOyBo
ZWlnaHQ6IDgwMDsgdmlzaWJsZTogdHJ1ZQorICAgIGZ1bmN0aW9uIGNob29zZVNjYWxlKHZhbHVl
KSB7IEVjbGlwc2VQcm9maWxlcy50ZXh0U2NhbGU9dmFsdWUgfQorICAgIGZ1bmN0aW9uIGNob29z
ZUFjY2VudChpKSB7IFN0cmVhbWluZ1ByZWZlcmVuY2VzLnVpQWNjZW50SW5kZXggPSBpIH0KKyAg
ICBJdGVtIHsgaWQ6IHN0YWNrVmlldyB9CisgICAgUXRPYmplY3QgeyBvYmplY3ROYW1lOiAidGVz
dFN0YXRlIjsgcHJvcGVydHkgY29sb3IgYWNjZW50OiBWYlRva2Vucy5hY2NlbnQ7IHByb3BlcnR5
IGNvbG9yIHByZXNzZWQ6IFZiVG9rZW5zLmFjY2VudFByZXNzZWQgfQorICAgIENyaW1zb25TdGF0
dXNEaWFsb2cgeyBvYmplY3ROYW1lOiAidGVzdFBhbmVsIiB9CisgICAgU3lzdGVtQ29ubmVjdGlv
bnNEaWFsb2cgeyBvYmplY3ROYW1lOiAiY29ubmVjdGlvbnNQYW5lbCIgfQorICAgIEVjbGlwc2VD
b250cm9sQ2VudGVyIHsgb2JqZWN0TmFtZTogImNvbnRyb2xDZW50ZXIiIH0KKyAgICBTY3JvbGxW
aWV3IHsgaWQ6c3lzdGVtU2Nyb2xsOyBvYmplY3ROYW1lOiJzeXN0ZW1TY3JvbGwiO2NvbnRlbnRX
aWR0aDphdmFpbGFibGVXaWR0aDsgYW5jaG9ycy5maWxsOnBhcmVudDsgYW5jaG9ycy5tYXJnaW5z
OjI0OyB2aXNpYmxlOnN5c3RlbVBhbmVsLmFjdGl2ZQorICAgICAgICBFY2xpcHNlU3lzdGVtU2V0
dGluZ3MgeyBpZDpzeXN0ZW1QYW5lbDtvYmplY3ROYW1lOiJzeXN0ZW1TZXR0aW5ncyI7d2lkdGg6
c3lzdGVtU2Nyb2xsLmF2YWlsYWJsZVdpZHRoO2FjdGl2ZTpmYWxzZSB9CisgICAgfQorICAgIEVj
bGlwc2VBYm91dERpYWxvZyB7IG9iamVjdE5hbWU6ICJhYm91dEVjbGlwc2UiIH0KK30KZGlmZiAt
LWdpdCBhL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9QcmVmZXJlbmNlcy5xbWwgYi9hcHAvbW9vbmxp
Z2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAw
MDAwMDAuLjk5NmU1YWMKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMv
UHJlZmVyZW5jZXMucW1sCkBAIC0wLDAgKzEsMyBAQAorcHJhZ21hIFNpbmdsZXRvbgoraW1wb3J0
IFF0UXVpY2sgMi45CitRdE9iamVjdCB7IHByb3BlcnR5IGludCB1aUFjY2VudEluZGV4OiA0OyBw
cm9wZXJ0eSBib29sIHVpU2hvd0hpbnRzOiB0cnVlOyBwcm9wZXJ0eSBpbnQgd2lkdGg6IDE5MjA7
IHByb3BlcnR5IGludCBoZWlnaHQ6IDEwODA7IHByb3BlcnR5IGludCBmcHM6IDYwOyBwcm9wZXJ0
eSBpbnQgYml0cmF0ZUticHM6IDIwMDAwOyBmdW5jdGlvbiBzYXZlKCkge30gfQpkaWZmIC0tZ2l0
IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAgYi9hcHAvbW9vbmxpZ2h0
b3MvdGVzdHMvdGVzdC1jcmltc29uLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAw
MDAwLi45NmM1ZmVmCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rl
c3QtY3JpbXNvbi5jcHAKQEAgLTAsMCArMSwzNzEgQEAKKyNpbmNsdWRlIDxRdFRlc3Q+CisjaW5j
bHVkZSA8UVRlbXBvcmFyeURpcj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFR
bWxDb21wb25lbnQ+CisjaW5jbHVkZSA8UVFtbENvbnRleHQ+CisjaW5jbHVkZSA8UVF1aWNrU3R5
bGU+CisjaW5jbHVkZSA8UVF1aWNrV2luZG93PgorI2luY2x1ZGUgPFFRdWlja0l0ZW0+CisjaW5j
bHVkZSA8UUZpbGU+CisjaW5jbHVkZSA8UUltYWdlUmVhZGVyPgorI2luY2x1ZGUgPFFUY3BTZXJ2
ZXI+CisjaW5jbHVkZSA8UVNzbFNvY2tldD4KKyNpbmNsdWRlIDxRU3NsS2V5PgorI2luY2x1ZGUg
PFFTc2xDZXJ0aWZpY2F0ZT4KKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVk
ZSA8bWVtb3J5PgorI2luY2x1ZGUgPFFTdGFuZGFyZFBhdGhzPgorI2luY2x1ZGUgPFFEaXI+Cisj
aW5jbHVkZSA8UUZpbGVJbmZvPgorI2luY2x1ZGUgIi4uL2NyaW1zb25zdGF0dXMuaCIKKyNpbmNs
dWRlICIuLi9zeXN0ZW1jb250cm9scy5oIgorI2luY2x1ZGUgIi4uL2VjbGlwc2Vwcm9maWxlcy5o
IgorI2luY2x1ZGUgIi4uL2xvY2FsaGFyZHdhcmUuaCIKKyNpbmNsdWRlICIuLi9vdmVybGF5c3R5
bGUuaCIKKyNpbmNsdWRlICIuLi8uLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgiCisKK2Ns
YXNzIFRsc0ZpeHR1cmUgOiBwdWJsaWMgUVRjcFNlcnZlciB7CitwdWJsaWM6CisgICAgUUJ5dGVB
cnJheSBib2R5ID0gUiIoeyJjcHVfcGVyY2VudCI6MzcuNSwicmFtX3VzZWRfYnl0ZXMiOjUwLCJy
YW1fdG90YWxfYnl0ZXMiOjEwMH0pIjsKKyAgICBpbnQgY29kZSA9IDIwMCwgcmVxdWVzdHMgPSAw
OworICAgIGJvb2wgcmVzcG9uZCA9IHRydWU7CisgICAgUUJ5dGVBcnJheSBhdXRob3JpemF0aW9u
OworICAgIFFTc2xDZXJ0aWZpY2F0ZSBjZXJ0OworICAgIFFTc2xLZXkga2V5OworICAgIFRsc0Zp
eHR1cmUoKSB7CisgICAgICAgIFFGaWxlIGMocUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05f
VEVTVF9DRVJUIikpOyBjLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGNlcnQgPSBRU3NsQ2Vy
dGlmaWNhdGUoYy5yZWFkQWxsKCkpOworICAgICAgICBRRmlsZSBrKHFFbnZpcm9ubWVudFZhcmlh
YmxlKCJDUklNU09OX1RFU1RfS0VZIikpOyBrLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGtl
eSA9IFFTc2xLZXkoay5yZWFkQWxsKCksIFFTc2w6OlJzYSk7CisgICAgICAgIGxpc3RlbihRSG9z
dEFkZHJlc3M6OkxvY2FsSG9zdCk7CisgICAgfQorICAgIHZvaWQgaW5jb21pbmdDb25uZWN0aW9u
KHFpbnRwdHIgZGVzY3JpcHRvcikgb3ZlcnJpZGUgeworICAgICAgICBhdXRvIHNvY2tldCA9IG5l
dyBRU3NsU29ja2V0KHRoaXMpOworICAgICAgICBzb2NrZXQtPnNldExvY2FsQ2VydGlmaWNhdGUo
Y2VydCk7IHNvY2tldC0+c2V0UHJpdmF0ZUtleShrZXkpOyBzb2NrZXQtPnNldFBlZXJWZXJpZnlN
b2RlKFFTc2xTb2NrZXQ6OlZlcmlmeU5vbmUpOworICAgICAgICBzb2NrZXQtPnNldFNvY2tldERl
c2NyaXB0b3IoZGVzY3JpcHRvcik7CisgICAgICAgIGF1dG8gaW5wdXQgPSBzdGQ6Om1ha2Vfc2hh
cmVkPFFCeXRlQXJyYXk+KCk7CisgICAgICAgIGNvbm5lY3Qoc29ja2V0LCAmUVNzbFNvY2tldDo6
cmVhZHlSZWFkLCB0aGlzLCBbdGhpcywgc29ja2V0LCBpbnB1dF0geworICAgICAgICAgICAgaW5w
dXQtPmFwcGVuZChzb2NrZXQtPnJlYWRBbGwoKSk7CisgICAgICAgICAgICBpZiAoIWlucHV0LT5j
b250YWlucygiXHJcblxyXG4iKSkgcmV0dXJuOworICAgICAgICAgICAgKytyZXF1ZXN0czsgYXV0
aG9yaXphdGlvbiA9ICppbnB1dDsKKyAgICAgICAgICAgIGlmIChyZXNwb25kKSB7CisgICAgICAg
ICAgICAgICAgUUJ5dGVBcnJheSBoZWFkZXIgPSAiSFRUUC8xLjEgIiArIFFCeXRlQXJyYXk6Om51
bWJlcihjb2RlKSArICIgRml4dHVyZVxyXG5Db250ZW50LVR5cGU6IGFwcGxpY2F0aW9uL2pzb25c
clxuQ29ubmVjdGlvbjogY2xvc2VcclxuQ29udGVudC1MZW5ndGg6ICIgKyBRQnl0ZUFycmF5Ojpu
dW1iZXIoYm9keS5zaXplKCkpICsgIlxyXG4iOworICAgICAgICAgICAgICAgIGlmIChjb2RlID09
IDMwMikgaGVhZGVyICs9ICJMb2NhdGlvbjogaHR0cHM6Ly8xMjcuMC4wLjI6MTIzNDUvXHJcbiI7
CisgICAgICAgICAgICAgICAgc29ja2V0LT53cml0ZShoZWFkZXIgKyAiXHJcbiIgKyBib2R5KTsg
c29ja2V0LT5kaXNjb25uZWN0RnJvbUhvc3QoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAg
IGlucHV0LT5jbGVhcigpOworICAgICAgICB9KTsKKyAgICAgICAgY29ubmVjdChzb2NrZXQsICZR
U3NsU29ja2V0OjpkaXNjb25uZWN0ZWQsIHNvY2tldCwgJlFPYmplY3Q6OmRlbGV0ZUxhdGVyKTsK
KyAgICAgICAgc29ja2V0LT5zdGFydFNlcnZlckVuY3J5cHRpb24oKTsKKyAgICB9Cit9OworCitj
bGFzcyBDcmltc29uVGVzdCA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorcHJpdmF0
ZSBzbG90czoKKyAgICB2b2lkIGluaXRUZXN0Q2FzZSgpIHsKKyAgICAgICAgUUNvcmVBcHBsaWNh
dGlvbjo6c2V0T3JnYW5pemF0aW9uTmFtZSgiRWNsaXBzZU9TIFRlc3QiKTsKKyAgICAgICAgUUNv
cmVBcHBsaWNhdGlvbjo6c2V0QXBwbGljYXRpb25OYW1lKCJFY2xpcHNlRml4dHVyZSIpOworICAg
ICAgICBRU2V0dGluZ3M6OnNldERlZmF1bHRGb3JtYXQoUVNldHRpbmdzOjpJbmlGb3JtYXQpOwor
ICAgIH0KKyAgICB2b2lkIGhvc3RQcm9maWxlc1JlbWFpbklzb2xhdGVkKCkgeworICAgICAgICBF
Y2xpcHNlUHJvZmlsZXMgcHJvZmlsZXM7CisgICAgICAgIFFWYXJpYW50TWFwIHZhbHVlc3t7Indp
ZHRoIiwxMjgwfSx7ImhlaWdodCIsODAwfSx7ImZwcyIsNjB9LHsiYml0cmF0ZUticHMiLDE1MDAw
fX07CisgICAgICAgIFFWRVJJRlkocHJvZmlsZXMuc2F2ZSgiZml4dHVyZS1ob3N0LWEiLCJEZXNr
dG9wIix2YWx1ZXMpKTsKKyAgICAgICAgUUNPTVBBUkUocHJvZmlsZXMubG9hZCgiZml4dHVyZS1o
b3N0LWEiLCJEZXNrdG9wIiksdmFsdWVzKTsKKyAgICAgICAgUVZFUklGWShwcm9maWxlcy5sb2Fk
KCJmaXh0dXJlLWhvc3QtYiIsIkRlc2t0b3AiKS5pc0VtcHR5KCkpOworICAgICAgICBRVkVSSUZZ
KHByb2ZpbGVzLm5hbWVzKCJmaXh0dXJlLWhvc3QtYSIpLmNvbnRhaW5zKCJEZXNrdG9wIikpOwor
ICAgICAgICBRVkVSSUZZKCFwcm9maWxlcy5yZW1vdmUoImZpeHR1cmUtaG9zdC1hIiwiRGVza3Rv
cCIsZmFsc2UpKTsKKyAgICAgICAgdmFsdWVzWyJmcHMiXSA9IDA7IFFWRVJJRlkoIXByb2ZpbGVz
LnNhdmUoImZpeHR1cmUtaG9zdC1hIiwiQmFkIix2YWx1ZXMpKTsKKyAgICAgICAgUVZFUklGWShw
cm9maWxlcy5yZW1vdmUoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIsdHJ1ZSkpOworICAgICAg
ICBRVkVSSUZZKHByb2ZpbGVzLmxvYWQoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIpLmlzRW1w
dHkoKSk7CisgICAgfQorICAgIHZvaWQgc3lzdGVtQ29udHJvbHNQcml2YXRlUGlwZSgpIHsKKyAg
ICAgICAgUVRlbXBvcmFyeURpciBkaXI7IFFWRVJJRlkoZGlyLmlzVmFsaWQoKSk7CisgICAgICAg
IFFGaWxlIHNjcmlwdChkaXIuZmlsZVBhdGgoImZpeHR1cmUucHkiKSk7IFFWRVJJRlkoc2NyaXB0
Lm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsKKyAgICAgICAgc2NyaXB0LndyaXRlKFIiUFko
aW1wb3J0IGpzb24sc3lzCitmb3IgbGluZSBpbiBzeXMuc3RkaW46CisgICAgdmFsdWU9anNvbi5s
b2FkcyhsaW5lKQorICAgIGFjdGlvbj12YWx1ZVsnYWN0aW9uJ10KKyAgICBpZiBhY3Rpb249PSd3
aWZpLWNvbm5lY3QnOgorICAgICAgICBwcmludChqc29uLmR1bXBzKHsncHJvbXB0JzonV2ktRmkg
cGFzc3dvcmQnfSksZmx1c2g9VHJ1ZSkKKyAgICAgICAgcmVwbHk9anNvbi5sb2FkcyhzeXMuc3Rk
aW4ucmVhZGxpbmUoKSkKKyAgICAgICAgYXNzZXJ0IHJlcGx5PT17J2FjdGlvbic6J2Fuc3dlcics
J3ZhbHVlJzonc2VjcmV0LXZhbHVlJ30KKyAgICBwcmludChqc29uLmR1bXBzKHsnaXRlbXMnOlt7
J2lkJzond2xhbjAvQUE6QkI6Q0M6REQ6RUU6RkYnLCduYW1lJzonPGI+UGxhaW4gU1NJRDwvYj4n
LCdkZXRhaWwnOic4MCUgV1BBMicsJ2Nvbm5lY3RlZCc6YWN0aW9uPT0nd2lmaS1jb25uZWN0J31d
LCdzdGF0dXMnOidSZWFkeScsJ2RvbmUnOlRydWV9KSxmbHVzaD1UcnVlKQorKVBZIik7IHNjcmlw
dC5jbG9zZSgpOworICAgICAgICBxcHV0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIs
IHNjcmlwdC5maWxlTmFtZSgpLnRvVXRmOCgpKTsKKyAgICAgICAgU3lzdGVtQ29udHJvbHMgY29u
dHJvbHM7IGNvbnRyb2xzLm9wZW4oIndpZmkiKTsKKyAgICAgICAgUVRSWV9DT01QQVJFKGNvbnRy
b2xzLml0ZW1zKCkuc2l6ZSgpLCAxKTsgUVZFUklGWSghY29udHJvbHMuYnVzeSgpKTsKKyAgICAg
ICAgY29udHJvbHMucmVxdWVzdCgiYnQtZm9yZ2V0IiwgImludmFsaWQiLCB0cnVlKTsgUVZFUklG
WSghY29udHJvbHMuYnVzeSgpKTsKKyAgICAgICAgY29udHJvbHMucmVxdWVzdCgid2lmaS1jb25u
ZWN0IiwgIndsYW4wL0FBOkJCOkNDOkREOkVFOkZGIik7CisgICAgICAgIFFUUllfVkVSSUZZKCFj
b250cm9scy5wcm9tcHQoKS5pc0VtcHR5KCkpOyBRVkVSSUZZKGNvbnRyb2xzLmJ1c3koKSk7Cisg
ICAgICAgIGNvbnRyb2xzLmFuc3dlcigic2VjcmV0LXZhbHVlIik7IFFUUllfVkVSSUZZKCFjb250
cm9scy5idXN5KCkpOworICAgICAgICBRVkVSSUZZKGNvbnRyb2xzLnByb21wdCgpLmlzRW1wdHko
KSk7IFFDT01QQVJFKGNvbnRyb2xzLnN0YXR1cygpLCBRU3RyaW5nKCJSZWFkeSIpKTsKKyAgICAg
ICAgUVZFUklGWShjb250cm9scy5pdGVtcygpLmZpcnN0KCkudG9NYXAoKS52YWx1ZSgiY29ubmVj
dGVkIikudG9Cb29sKCkpOworICAgICAgICBjb250cm9scy5jbG9zZSgpOyBRVkVSSUZZKCFjb250
cm9scy5idXN5KCkpOworICAgICAgICBxdW5zZXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhU
VVJFIik7CisgICAgfQorICAgIHZvaWQgbWFuYWdlZFVwZGF0ZXJDYW5ub3RSZXBsYWNlQ3VzdG9t
aXplZENsaWVudCgpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciBkaXI7IFFWRVJJRlkoZGlyLmlz
VmFsaWQoKSk7CisgICAgICAgIGNvbnN0IFFTdHJpbmcgaW1hZ2UgPSBkaXIuZmlsZVBhdGgoImN1
c3RvbS5BcHBJbWFnZSIpOworICAgICAgICBRRmlsZSBmKGltYWdlKTsgUVZFUklGWShmLm9wZW4o
UUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsgZi53cml0ZSgiY3VzdG9taXplZCBjbGllbnQiKTsgZi5j
bG9zZSgpOworICAgICAgICBjb25zdCBRQnl0ZUFycmF5IG9sZCA9IHFnZXRlbnYoIkFQUElNQUdF
Iik7IGNvbnN0IGJvb2wgaGFkID0gcUVudmlyb25tZW50VmFyaWFibGVJc1NldCgiQVBQSU1BR0Ui
KTsKKyAgICAgICAgcXB1dGVudigiQVBQSU1BR0UiLCBpbWFnZS50b1V0ZjgoKSk7CisgICAgICAg
IEF1dG9VcGRhdGVDaGVja2VyIGNoZWNrZXI7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5vc01h
bmFnZWQoKSk7IFFWRVJJRlkoIWNoZWNrZXIuY2FuSW5zdGFsbFVwZGF0ZXMoKSk7CisgICAgICAg
IFFTaWduYWxTcHkgY29tcGxldGVkKCZjaGVja2VyLCAmQXV0b1VwZGF0ZUNoZWNrZXI6OmNoZWNr
Q29tcGxldGVkKTsKKyAgICAgICAgUVNpZ25hbFNweSBmYWlsZWQoJmNoZWNrZXIsICZBdXRvVXBk
YXRlQ2hlY2tlcjo6aW5zdGFsbEZhaWxlZCk7CisgICAgICAgIGNoZWNrZXIuc3RhcnQoKTsgY2hl
Y2tlci5jaGVja05vdygpOyBjaGVja2VyLmNoYW5uZWxDaGFuZ2VkKCk7IGNoZWNrZXIuaW5zdGFs
bCgpOworICAgICAgICBRQ09NUEFSRShjb21wbGV0ZWQuY291bnQoKSwgMyk7IFFDT01QQVJFKGZh
aWxlZC5jb3VudCgpLCAxKTsKKyAgICAgICAgUVZFUklGWSghY2hlY2tlci5jaGVja2luZygpKTsg
UVZFUklGWSghY2hlY2tlci5pbnN0YWxsaW5nKCkpOworICAgICAgICBRVkVSSUZZKCFjaGVja2Vy
LmNhbkluc3RhbGwoKSk7IFFWRVJJRlkoIWNoZWNrZXIudXBkYXRlQXZhaWxhYmxlKCkpOyBRVkVS
SUZZKCFjaGVja2VyLm9mZmVyQXZhaWxhYmxlKCkpOworICAgICAgICBRQ09NUEFSRShjaGVja2Vy
LnJlbGVhc2VVcmwoKSwgUVN0cmluZygiaHR0cHM6Ly9naXRodWIuY29tL3RoM2QzY2szci9Nb29u
bGlnaHQtT1MvcmVsZWFzZXMiKSk7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5jdXJyZW50VmVy
c2lvbigpLmNvbnRhaW5zKCJFY2xpcHNlT1MgY3VzdG9taXplZCIpKTsKKyAgICAgICAgUVZFUklG
WShmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkpOyBRQ09NUEFSRShmLnJlYWRBbGwoKSwgUUJ5
dGVBcnJheSgiY3VzdG9taXplZCBjbGllbnQiKSk7IGYuY2xvc2UoKTsKKyAgICAgICAgUUNPTVBB
UkUoUURpcihkaXIucGF0aCgpKS5lbnRyeUxpc3QoUURpcjo6RmlsZXMpLCBRU3RyaW5nTGlzdHsi
Y3VzdG9tLkFwcEltYWdlIn0pOworICAgICAgICBpZiAoaGFkKSBxcHV0ZW52KCJBUFBJTUFHRSIs
IG9sZCk7IGVsc2UgcXVuc2V0ZW52KCJBUFBJTUFHRSIpOworICAgICAgICBRQ09NUEFSRShBdXRv
VXBkYXRlQ2hlY2tlcjo6Y29tcGFyZVNlbWFudGljVmVyc2lvbnMoIjAuNS4wIiwgIjAuNC45Iiks
IDEpOworICAgIH0KKyAgICB2b2lkIGVuZHBvaW50VmFsaWRhdGlvbigpIHsKKyAgICAgICAgUVZF
UklGWShDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovLzE5Mi4xNjguMS4xMDo0
Nzk5MCIpKTsKKyAgICAgICAgUVZFUklGWShDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KCJo
dHRwczovL1tmZDAwOjoxXTo0Nzk5MC8iKSk7CisgICAgICAgIGZvciAoYXV0byBiYWQgOiB7Imh0
dHA6Ly9ob3N0IiwgImh0dHBzOi8vdXNlcjpzZWNyZXRAaG9zdCIsICJodHRwczovL2hvc3QvYXBp
IiwgImh0dHBzOi8vaG9zdC8/dG9rZW49c2VjcmV0IiwgImZpbGU6Ly8vZXRjL3Bhc3N3ZCIsICJo
dHRwczovL2hvc3QvI2ZyYWdtZW50In0pCisgICAgICAgICAgICBRVkVSSUZZKCFDcmltc29uU3Rh
dHVzOjp2YWxpZEVuZHBvaW50KGJhZCkpOworICAgIH0KKyAgICB2b2lkIG1pc3NpbmdBbmRJbnZh
bGlkTWV0cmljcygpIHsKKyAgICAgICAgUVN0cmluZyBlcnJvcjsKKyAgICAgICAgUVZFUklGWShD
cmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKCJub3QganNvbiIsICZlcnJvcikuaXNFbXB0eSgpKTsg
UVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsKKyAgICAgICAgYXV0byBzID0gQ3JpbXNvblN0YXR1
czo6cGFyc2VTdGF0cyhSIih7ImNwdV9wZXJjZW50Ijo0Mi41LCJjcHVfdGVtcF9jIjotMSwiZ3B1
X3BlcmNlbnQiOm51bGwsInJhbV90b3RhbF9ieXRlcyI6MCwicmFtX3BlcmNlbnQiOjAsInZyYW1f
dG90YWxfYnl0ZXMiOjEwMCwidnJhbV91c2VkX2J5dGVzIjoxMjB9KSIsICZlcnJvcik7CisgICAg
ICAgIFFWRVJJRlkoZXJyb3IuaXNFbXB0eSgpKTsgUUNPTVBBUkUocy52YWx1ZSgiY3B1X3BlcmNl
bnQiKS50b0RvdWJsZSgpLCA0Mi41KTsKKyAgICAgICAgUVZFUklGWSghcy5jb250YWlucygiY3B1
X3RlbXBfYyIpKTsgUVZFUklGWSghcy5jb250YWlucygiZ3B1X3BlcmNlbnQiKSk7IFFWRVJJRlko
IXMuY29udGFpbnMoInJhbV9wZXJjZW50IikpOworICAgICAgICBRQ09NUEFSRShzLnZhbHVlKCJ2
cmFtX3BlcmNlbnQiKS50b0RvdWJsZSgpLCAxMDAuMCk7CisgICAgICAgIGF1dG8gaW52YWxpZCA9
IENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJjcHVfcGVyY2VudCI6MTAxLCJncHVfcGVy
Y2VudCI6IjAifSkiLCAmZXJyb3IpOworICAgICAgICBRVkVSSUZZKGludmFsaWQuaXNFbXB0eSgp
KTsgUVZFUklGWShlcnJvci5pc0VtcHR5KCkpOworICAgICAgICBDcmltc29uU3RhdHVzOjpwYXJz
ZVN0YXRzKFFCeXRlQXJyYXkoNjU1MzcsICdhJyksICZlcnJvcik7IFFWRVJJRlkoIWVycm9yLmlz
RW1wdHkoKSk7CisgICAgICAgIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJlcnJvciI6
InVuc3VwcG9ydGVkIn0pIiwgJmVycm9yKTsgUVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsKKyAg
ICB9CisgICAgdm9pZCBsb2NhbEhhcmR3YXJlRml4dHVyZSgpIHsKKyAgICAgICAgUVRlbXBvcmFy
eURpciB0ZW1wOyBRVkVSSUZZKHRlbXAuaXNWYWxpZCgpKTsKKyAgICAgICAgYXV0byB3cml0ZSA9
IFsmXShRU3RyaW5nIHAsIFFCeXRlQXJyYXkgdmFsdWUpIHsgUURpcigpLm1rcGF0aChRRmlsZUlu
Zm8odGVtcC5wYXRoKCkrcCkuYWJzb2x1dGVQYXRoKCkpOyBRRmlsZSBmKHRlbXAucGF0aCgpK3Ap
OyBRVkVSSUZZKGYub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOyBmLndyaXRlKHZhbHVlKTsg
fTsKKyAgICAgICAgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC90eXBlIiwgIkJhdHRl
cnkiKTsgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9jYXBhY2l0eSIsICI3MyIpOyB3
cml0ZSgiL2NsYXNzL3Bvd2VyX3N1cHBseS9CQVQwL3N0YXR1cyIsICJDaGFyZ2luZyIpOworICAg
ICAgICB3cml0ZSgiL2NsYXNzL25ldC93bGFuMC9vcGVyc3RhdGUiLCAidXAiKTsgd3JpdGUoIi9j
bGFzcy9uZXQvbG8vb3BlcnN0YXRlIiwgInVwIik7CisgICAgICAgIGF1dG8gbG9jYWwgPSBDcmlt
c29uU3RhdHVzOjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpOyBRQ09NUEFSRShsb2NhbC52YWx1ZSgi
YmF0dGVyeVBlcmNlbnQiKS50b0ludCgpLCA3Myk7IFFDT01QQVJFKGxvY2FsLnZhbHVlKCJiYXR0
ZXJ5U3RhdGUiKS50b1N0cmluZygpLCBRU3RyaW5nKCJDaGFyZ2luZyIpKTsKKyAgICAgICAgUUNP
TVBBUkUobG9jYWwudmFsdWUoIm5ldHdvcmsiKS50b1N0cmluZygpLCBRU3RyaW5nKCJ3bGFuMCIp
KTsgUVZFUklGWShsb2NhbC52YWx1ZSgiY29ubmVjdGVkIikudG9Cb29sKCkpOworICAgICAgICB3
cml0ZSgiL2NsYXNzL3Bvd2VyX3N1cHBseS9CQVQwL2NhcGFjaXR5IiwgIjEwMSIpOyBRQ09NUEFS
RShDcmltc29uU3RhdHVzOjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpLnZhbHVlKCJiYXR0ZXJ5UGVy
Y2VudCIpLnRvSW50KCksIC0xKTsKKyAgICB9CisgICAgdm9pZCBwcml2YXRlU2V0dGluZ3NBbmRO
b0Nyb3NzSG9zdENyZWRlbnRpYWxzKCkgeworICAgICAgICBRU3RhbmRhcmRQYXRoczo6c2V0VGVz
dE1vZGVFbmFibGVkKHRydWUpOworICAgICAgICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVz
LnNlbGVjdEhvc3QoInRlc3QtYSIsICJodHRwczovLzEyNy4wLjAuMTo0Nzk5MCIpOworICAgICAg
ICBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4xOjQ3OTkwIiwgImZp
eHR1cmUtdG9rZW4iLCAiIikpOyBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmVkKCkpOworICAgICAg
ICBhdXRvIHBhdGggPSBRU3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRhcmRQ
YXRoczo6QXBwQ29uZmlnTG9jYXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpzb24iOworICAgICAg
ICBRVkVSSUZZKChRRmlsZTo6cGVybWlzc2lvbnMocGF0aCkgJiAoUUZpbGVEZXZpY2U6OlJlYWRH
cm91cCB8IFFGaWxlRGV2aWNlOjpSZWFkT3RoZXIgfCBRRmlsZURldmljZTo6V3JpdGVHcm91cCB8
IFFGaWxlRGV2aWNlOjpXcml0ZU90aGVyKSkgPT0gMCk7CisgICAgICAgIHN0YXR1cy5zZWxlY3RI
b3N0KCJ0ZXN0LWIiLCAiaHR0cHM6Ly8xMjcuMC4wLjI6NDc5OTAiKTsgUVZFUklGWSghc3RhdHVz
LmNvbmZpZ3VyZWQoKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBz
Oi8vMTI3LjAuMC4yOjQ3OTkwIiwgIiIsICIiKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5j
b25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIiwgImZpeHR1cmUtdG9rZW4iLCAiaW52
YWxpZC1waW4iKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8v
MTI3LjAuMC4yOjQ3OTkwIiwgInRva2VuXG5pbmplY3Rpb24iLCAiIikpOworICAgICAgICBRRmls
ZTo6cmVtb3ZlKHBhdGgpOworICAgIH0KKyAgICB2b2lkIHRsc0F1dGhlbnRpY2F0aW9uQW5kVmlz
aWJpbGl0eSgpIHsKKyAgICAgICAgVGxzRml4dHVyZSBzZXJ2ZXI7IFFWRVJJRlkoc2VydmVyLmlz
TGlzdGVuaW5nKCkpOyBRVkVSSUZZKCFzZXJ2ZXIuY2VydC5pc051bGwoKSk7CisgICAgICAgIFFT
dHJpbmcgdXJsID0gImh0dHBzOi8vMTI3LjAuMC4xOiIgKyBRU3RyaW5nOjpudW1iZXIoc2VydmVy
LnNlcnZlclBvcnQoKSk7CisgICAgICAgIFFTdHJpbmcgcGluID0gUVN0cmluZzo6ZnJvbUxhdGlu
MShzZXJ2ZXIuY2VydC5kaWdlc3QoUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkp
OworICAgICAgICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVjdEhvc3QoImZpeHR1
cmUtdGxzIiwgdXJsKTsKKyAgICAgICAgUVZFUklGWShzdGF0dXMuY29uZmlndXJlKHVybCwgImZp
eHR1cmUtb25seS10b2tlbiIsICIiKSk7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAg
ICBRVFJZX1ZFUklGWV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0YXR1cygpLmNvbnRhaW5zKCJmaW5n
ZXJwcmludCIpLCA1MDAwKTsKKyAgICAgICAgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCAwKTsg
Ly8gbm8gY3JlZGVudGlhbHMgc2VudCBiZWZvcmUgdHJ1c3Rpbmcgc2VsZi1zaWduZWQgVExTCisg
ICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJmaXh0dXJlLW9ubHktdG9rZW4i
LCBwaW4pKTsKKyAgICAgICAgUVRSWV9DT01QQVJFX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMo
KS52YWx1ZSgiY3B1X3BlcmNlbnQiKS50b0RvdWJsZSgpLCAzNy41LCA1MDAwKTsKKyAgICAgICAg
UVZFUklGWShzZXJ2ZXIuYXV0aG9yaXphdGlvbi5jb250YWlucygiQXV0aG9yaXphdGlvbjogQmVh
cmVyIGZpeHR1cmUtb25seS10b2tlbiIpKTsKKyAgICAgICAgUVZFUklGWShzZXJ2ZXIuYXV0aG9y
aXphdGlvbi5zdGFydHNXaXRoKCJHRVQgL2FwaS9ob3N0L3N0YXRzICIpKTsKKyAgICAgICAgc3Rh
dHVzLnNldFZpc2libGUoZmFsc2UpOyBpbnQgY291bnQgPSBzZXJ2ZXIucmVxdWVzdHM7IFFUZXN0
OjpxV2FpdCgyMTAwKTsgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCBjb3VudCk7CisgICAgICAg
IGZvciAoaW50IGNvZGUgOiB7NDAxLCA0MDMsIDQwNCwgMzAyfSkgeworICAgICAgICAgICAgc2Vy
dmVyLmNvZGUgPSBjb2RlOyBpbnQgcHJpb3IgPSBzZXJ2ZXIucmVxdWVzdHM7IHN0YXR1cy5zZXRW
aXNpYmxlKHRydWUpOworICAgICAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHNlcnZl
ci5yZXF1ZXN0cyA+IHByaW9yLCA1MDAwKTsKKyAgICAgICAgICAgIFFUUllfVkVSSUZZX1dJVEhf
VElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOworICAgICAgICAgICAgc3Rh
dHVzLnNldFZpc2libGUoZmFsc2UpOworICAgICAgICB9CisgICAgICAgIHNlcnZlci5jb2RlID0g
MjAwOyBzZXJ2ZXIuYm9keSA9IFFCeXRlQXJyYXkoNzAwMDAsICdhJyk7IGludCBwcmlvciA9IHNl
cnZlci5yZXF1ZXN0czsgc3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAgICAgIFFUUllfVkVS
SUZZX1dJVEhfVElNRU9VVChzZXJ2ZXIucmVxdWVzdHMgPiBwcmlvciwgNTAwMCk7CisgICAgICAg
IFFUUllfVkVSSUZZX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDAp
OyBzdGF0dXMuc2V0VmlzaWJsZShmYWxzZSk7CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZp
Z3VyZSh1cmwsICJmaXh0dXJlLW9ubHktdG9rZW4iLCBRU3RyaW5nKDY0LCAnMCcpKSk7IHN0YXR1
cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAgICBjb3VudCA9IHNlcnZlci5yZXF1ZXN0czsgUVRl
c3Q6OnFXYWl0KDUwMCk7IFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywgY291bnQpOyBRVkVSSUZZ
KHN0YXR1cy5zdGF0cygpLmlzRW1wdHkoKSk7CisgICAgICAgIHN0YXR1cy5zZXRWaXNpYmxlKGZh
bHNlKTsKKyAgICB9CisgICAgdm9pZCByb3VuZGVkT3ZlcmxheUFjY2VudHNBbmRPcGFjaXR5KCkg
eworICAgICAgICBmb3IoaW50IGFjY2VudD0wO2FjY2VudDwxNjsrK2FjY2VudCkgeworICAgICAg
ICAgICAgYXV0byBpbWFnZT1FY2xpcHNlT3ZlcmxheVN0eWxlOjpwYW5lbChRU2l6ZSg0MDAsMTgw
KSxhY2NlbnQsODUpOyBRVkVSSUZZKCFpbWFnZS5pc051bGwoKSk7CisgICAgICAgICAgICBRQ09N
UEFSRShpbWFnZS5waXhlbENvbG9yKDAsMCkuYWxwaGEoKSwwKTsKKyAgICAgICAgICAgIFFDT01Q
QVJFKGltYWdlLnBpeGVsQ29sb3IoMjAwLDkwKS5hbHBoYSgpLDg1KjI1NS8xMDApOworICAgICAg
ICAgICAgUUNPTVBBUkUoaW1hZ2UucGl4ZWxDb2xvcigyMDAsOCkucmdiKCksRWNsaXBzZU92ZXJs
YXlTdHlsZTo6YWNjZW50KGFjY2VudCkucmdiKCkpOworICAgICAgICB9CisgICAgICAgIFFWRVJJ
RlkoRWNsaXBzZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNpemUoLTEsMTAwKSwwLDg1KS5pc051bGwo
KSk7CisgICAgICAgIFFWRVJJRlkoRWNsaXBzZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNpemUoNDA5
NiwxMDApLDAsODUpLmlzTnVsbCgpKTsKKyAgICB9CisgICAgdm9pZCBsb2NhbEhhcmR3YXJlQ291
bnRlcnNBbmRTZW5zb3JzKCkgeworICAgICAgICBRVGVtcG9yYXJ5RGlyIHJvb3Q7IFFWRVJJRlko
cm9vdC5pc1ZhbGlkKCkpOworICAgICAgICBhdXRvIHdyaXRlPVsmXShjb25zdCBRU3RyaW5nJiBw
YXRoLGNvbnN0IFFCeXRlQXJyYXkmIGRhdGEpIHsgUVN0cmluZyBmdWxsPXJvb3QucGF0aCgpK3Bh
dGg7IFFEaXIoKS5ta3BhdGgoUUZpbGVJbmZvKGZ1bGwpLmFic29sdXRlUGF0aCgpKTsgUUZpbGUg
ZmlsZShmdWxsKTsgUVZFUklGWShmaWxlLm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsgUUNP
TVBBUkUoZmlsZS53cml0ZShkYXRhKSxxaW50NjQoZGF0YS5zaXplKCkpKTsgfTsKKyAgICAgICAg
UVNldHRpbmdzKCkuc2V0VmFsdWUoImVjbGlwc2UvaGFyZHdhcmVSZWZyZXNoIiwxKTsKKyAgICAg
ICAgd3JpdGUoIi9wcm9jL3N0YXQiLCJjcHUgMTAwIDAgMTAwIDgwMCAwIDAgMCAwXG4iKTsKKyAg
ICAgICAgd3JpdGUoIi9wcm9jL21lbWluZm8iLCJNZW1Ub3RhbDogMTA0ODU3NiBrQlxuTWVtQXZh
aWxhYmxlOiAyNjIxNDQga0JcblN3YXBUb3RhbDogMTAyNCBrQlxuU3dhcEZyZWU6IDUxMiBrQlxu
Iik7CisgICAgICAgIHdyaXRlKCIvc3lzL2NsYXNzL2h3bW9uL2h3bW9uMC9uYW1lIiwiY29yZXRl
bXAiKTsgd3JpdGUoIi9zeXMvY2xhc3MvaHdtb24vaHdtb24wL3RlbXAxX2lucHV0IiwiNjI1MDAi
KTsKKyAgICAgICAgd3JpdGUoIi9zeXMvY2xhc3MvaHdtb24vaHdtb24wL2ZhbjFfaW5wdXQiLCIy
NDAwIik7CisgICAgICAgIHdyaXRlKCIvcHJvYy9uZXQvcm91dGUiLCJJZmFjZSBEZXN0aW5hdGlv
biBHYXRld2F5IEZsYWdzXG53bGFuMCAwMDAwMDAwMCAwMTAyMDMwNCAwMDAzXG4iKTsKKyAgICAg
ICAgd3JpdGUoIi9wcm9jL25ldC9kZXYiLCJ3bGFuMDogMTAwMCAwIDAgMCAwIDAgMCAwIDIwMDAg
MCAwIDAgMCAwIDAgMFxuIik7CisgICAgICAgIFFCeXRlQXJyYXkgdmlkZW89ImRybS1jbGllbnQt
aWQ6IDdcbmRybS1lbmdpbmUtdmlkZW86IDEwMDAwMDAwMCBuc1xuIjsKKyAgICAgICAgd3JpdGUo
Ii9wcm9jL3NlbGYvZmRpbmZvLzEiLHZpZGVvKTsgd3JpdGUoIi9wcm9jL3NlbGYvZmRpbmZvLzIi
LHZpZGVvKTsKKyAgICAgICAgYXV0byBmaXJzdD1Mb2NhbEhhcmR3YXJlOjpzYW1wbGUocm9vdC5w
YXRoKCkpOyBRVkVSSUZZKCFmaXJzdC5jb250YWlucygiY3B1UGVyY2VudCIpKTsgUVZFUklGWSgh
Zmlyc3QuY29udGFpbnMoInZpZGVvUGVyY2VudCIpKTsKKyAgICAgICAgUUNPTVBBUkUoZmlyc3Rb
Im1lbW9yeVBlcmNlbnQiXS50b0RvdWJsZSgpLDc1LjApOyBRQ09NUEFSRShmaXJzdFsidGVtcGVy
YXR1cmVDIl0udG9Eb3VibGUoKSw2Mi41KTsgUUNPTVBBUkUoZmlyc3RbImZhblJQTSJdLnRvRG91
YmxlKCksMjQwMC4wKTsKKyAgICAgICAgUVRlc3Q6OnFXYWl0KDEwNTApOworICAgICAgICB3cml0
ZSgiL3Byb2Mvc3RhdCIsImNwdSAxNTAgMCAxNTAgOTAwIDAgMCAwIDBcbiIpOworICAgICAgICB2
aWRlbz0iZHJtLWNsaWVudC1pZDogN1xuZHJtLWVuZ2luZS12aWRlbzogMjAwMDAwMDAwIG5zXG4i
OworICAgICAgICB3cml0ZSgiL3Byb2Mvc2VsZi9mZGluZm8vMSIsdmlkZW8pOyB3cml0ZSgiL3By
b2Mvc2VsZi9mZGluZm8vMiIsdmlkZW8pOworICAgICAgICB3cml0ZSgiL3Byb2MvbmV0L2RldiIs
IndsYW4wOiAxMDQ5NTc2IDAgMCAwIDAgMCAwIDAgNTI2Mjg4IDAgMCAwIDAgMCAwIDBcbiIpOwor
ICAgICAgICBhdXRvIHNlY29uZD1Mb2NhbEhhcmR3YXJlOjpzYW1wbGUocm9vdC5wYXRoKCkpOyBR
Q09NUEFSRShzZWNvbmRbImNwdVBlcmNlbnQiXS50b0RvdWJsZSgpLDUwLjApOworICAgICAgICBR
VkVSSUZZKHNlY29uZFsidmlkZW9QZXJjZW50Il0udG9Eb3VibGUoKT41ICYmIHNlY29uZFsidmlk
ZW9QZXJjZW50Il0udG9Eb3VibGUoKTwxMSk7IC8vIGR1cGxpY2F0ZSBmZCBtdXN0IG5vdCBkb3Vi
bGUtY291bnQKKyAgICAgICAgUVZFUklGWShzZWNvbmRbInJlY2VpdmVNaUIiXS50b0RvdWJsZSgp
Pi41ICYmIHNlY29uZFsicmVjZWl2ZU1pQiJdLnRvRG91YmxlKCk8MS4xKTsKKyAgICAgICAgUVRl
c3Q6OnFXYWl0KDEwNTApOworICAgICAgICB3cml0ZSgiL3Byb2Mvc3RhdCIsImNwdSAxIDAgMSAx
IDAgMCAwIDBcbiIpOyB3cml0ZSgiL3Byb2MvbmV0L2RldiIsIndsYW4wOiAxIDAgMCAwIDAgMCAw
IDAgMSAwIDAgMCAwIDAgMCAwXG4iKTsKKyAgICAgICAgYXV0byByZXNldD1Mb2NhbEhhcmR3YXJl
OjpzYW1wbGUocm9vdC5wYXRoKCkpOyBRVkVSSUZZKCFyZXNldC5jb250YWlucygiY3B1UGVyY2Vu
dCIpKTsgUVZFUklGWSghcmVzZXQuY29udGFpbnMoInJlY2VpdmVNaUIiKSk7CisgICAgICAgIFFT
ZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlL2hhcmR3YXJlUmVmcmVzaCIsMik7CisgICAgfQor
ICAgIHZvaWQgbG9jYWxIYXJkd2FyZVVuYXZhaWxhYmxlQW5kQm91bmRzKCkgeworICAgICAgICBR
VGVtcG9yYXJ5RGlyIHJvb3Q7IFFWRVJJRlkocm9vdC5pc1ZhbGlkKCkpOworICAgICAgICBhdXRv
IGVtcHR5PUxvY2FsSGFyZHdhcmU6OnNhbXBsZShyb290LnBhdGgoKSk7IFFWRVJJRlkoZW1wdHku
aXNFbXB0eSgpKTsKKyAgICAgICAgTG9jYWxIYXJkd2FyZSBtb25pdG9yOyBtb25pdG9yLnNldFBv
c2l0aW9uKDk5OSk7IFFDT01QQVJFKG1vbml0b3IucG9zaXRpb24oKSwzKTsKKyAgICAgICAgbW9u
aXRvci5zZXRPcGFjaXR5KC01KTsgUUNPTVBBUkUobW9uaXRvci5vcGFjaXR5KCksNDApOworICAg
ICAgICBtb25pdG9yLnNldFJlZnJlc2hTZWNvbmRzKDk5OSk7IFFDT01QQVJFKG1vbml0b3IucmVm
cmVzaFNlY29uZHMoKSw1KTsKKyAgICAgICAgbW9uaXRvci5zZXRGaWVsZHMoeyJjcHUiLCJwYXNz
d29yZCIsIm1lbW9yeSJ9KTsgUUNPTVBBUkUobW9uaXRvci5maWVsZHMoKSxRU3RyaW5nTGlzdCh7
ImNwdSIsIm1lbW9yeSJ9KSk7CisgICAgICAgIG1vbml0b3Iuc2V0T3ZlcmxheShmYWxzZSk7IG1v
bml0b3Iuc2V0UmVmcmVzaFNlY29uZHMoMik7IG1vbml0b3Iuc2V0T3BhY2l0eSg4NSk7CisgICAg
fQorICAgIHZvaWQgc2NhblByb2dyZXNzQmVmb3JlQ29tcGxldGlvbigpIHsKKyAgICAgICAgUVRl
bXBvcmFyeURpciBkaXI7IFFGaWxlIHNjcmlwdChkaXIuZmlsZVBhdGgoInNjYW4ucHkiKSk7IFFW
RVJJRlkoc2NyaXB0Lm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsKKyAgICAgICAgc2NyaXB0
LndyaXRlKFIiUFkoaW1wb3J0IGpzb24sc3lzLHRpbWUKK2ZvciBsaW5lIGluIHN5cy5zdGRpbjoK
KyAgICByZXF1ZXN0PWpzb24ubG9hZHMobGluZSkKKyAgICBpZiByZXF1ZXN0WydhY3Rpb24nXT09
J2J0LXNjYW4nOgorICAgICAgICBwcmludChqc29uLmR1bXBzKHsnaXRlbXMnOlt7J2lkJzonQUE6
QkI6Q0M6REQ6RUU6RkYnLCduYW1lJzonQ29udHJvbGxlcid9XSwnc3RhdHVzJzonU2Nhbm5pbmcn
fSksZmx1c2g9VHJ1ZSkKKyAgICAgICAgdGltZS5zbGVlcCguNSkKKyAgICBwcmludChqc29uLmR1
bXBzKHsnaXRlbXMnOlt7J2lkJzonQUE6QkI6Q0M6REQ6RUU6RkYnLCduYW1lJzonQ29udHJvbGxl
cid9XSwnc3RhdHVzJzonUmVhZHknLCdkb25lJzpUcnVlfSksZmx1c2g9VHJ1ZSkKKylQWSIpOyBz
Y3JpcHQuY2xvc2UoKTsgcXB1dGVudigiTU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUiLHNjcmlw
dC5maWxlTmFtZSgpLnRvVXRmOCgpKTsKKyAgICAgICAgU3lzdGVtQ29udHJvbHMgYzsgYy5vcGVu
KCJidCIpOyBRVFJZX1ZFUklGWSghYy5idXN5KCkgJiYgIWMuaXRlbXMoKS5pc0VtcHR5KCkpOwor
ICAgICAgICBjLnJlcXVlc3QoImJ0LXNjYW4iKTsgUVRSWV9DT01QQVJFKGMuc3RhdHVzKCksUVN0
cmluZygiU2Nhbm5pbmciKSk7IFFWRVJJRlkoYy5idXN5KCkpOyBRQ09NUEFSRShjLml0ZW1zKCku
c2l6ZSgpLDEpOworICAgICAgICBRVFJZX1ZFUklGWSghYy5idXN5KCkpOyBjLmNsb3NlKCk7IHF1
bnNldGVudigiTU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUiKTsKKyAgICB9CisgICAgdm9pZCBp
Y29uUmVzb3VyY2VzKCkgeworICAgICAgICBmb3IgKGNvbnN0IFFTdHJpbmcmIG5hbWUgOiB7ImVj
bGlwc2UtaWNvbiIsICJlY2xpcHNlLWNvbnRyb2xzIiwgImVjbGlwc2UtcG93ZXIiLCAiY3JpbXNv
bi1uZXR3b3JrIiwgImNyaW1zb24tYmx1ZXRvb3RoIiwgImNyaW1zb24tYmF0dGVyeSIsICJjcmlt
c29uLWhvc3QiLCAic2V0dGluZ3MifSkgeworICAgICAgICAgICAgY29uc3QgUVN0cmluZyBwYXRo
ID0gIjovcmVzLyIgKyBuYW1lICsgIi5zdmciOworICAgICAgICAgICAgUVZFUklGWTIoUUZpbGU6
OmV4aXN0cyhwYXRoKSwgcVByaW50YWJsZShwYXRoKSk7CisgICAgICAgICAgICBRSW1hZ2VSZWFk
ZXIgcmVhZGVyKHBhdGgpOworICAgICAgICAgICAgUVZFUklGWTIoIXJlYWRlci5yZWFkKCkuaXNO
dWxsKCksIHFQcmludGFibGUocGF0aCArICI6ICIgKyByZWFkZXIuZXJyb3JTdHJpbmcoKSkpOwor
ICAgICAgICB9CisgICAgfQorICAgIHZvaWQgcW1sUGFsZXR0ZUFuZFBhbmVscygpIHsKKyAgICAg
ICAgUVN0cmluZyBzb3VyY2UgPSBxRW52aXJvbm1lbnRWYXJpYWJsZSgiVklCRU1JU19URVNUX1NP
VVJDRSIpOyBRVkVSSUZZKCFzb3VyY2UuaXNFbXB0eSgpKTsKKyAgICAgICAgUVF1aWNrU3R5bGU6
OnNldFN0eWxlKCJNYXRlcmlhbCIpOworICAgICAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGUo
UVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UgKyAiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9QcmVm
ZXJlbmNlcy5xbWwiKSwgIlN0cmVhbWluZ1ByZWZlcmVuY2VzIiwgMSwgMCwgIlN0cmVhbWluZ1By
ZWZlcmVuY2VzIik7CisgICAgICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9uVHlwZShRVXJsOjpmcm9t
TG9jYWxGaWxlKHNvdXJjZSArICIvYXBwL2d1aS9WYlRva2Vucy5xbWwiKSwgIlZpYmVtaXMuUmVk
ZXNpZ24iLCAxLCAwLCAiVmJUb2tlbnMiKTsKKyAgICAgICAgUVRlbXBvcmFyeURpciBjb250cm9s
c0ZpeHR1cmU7IFFWRVJJRlkoY29udHJvbHNGaXh0dXJlLmlzVmFsaWQoKSk7CisgICAgICAgIFFG
aWxlIGhlbHBlcihjb250cm9sc0ZpeHR1cmUuZmlsZVBhdGgoImhlbHBlci5weSIpKTsgUVZFUklG
WShoZWxwZXIub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOworICAgICAgICBoZWxwZXIud3Jp
dGUoUiJQWShpbXBvcnQganNvbixzeXMKK2ZvciBsaW5lIGluIHN5cy5zdGRpbjoKKyAgICB2YWx1
ZT1qc29uLmxvYWRzKGxpbmUpCisgICAgcHJpbnQoanNvbi5kdW1wcyh7J3N0YXRlJzp7J3ZvbHVt
ZSc6NTAsJ211dGVkJzpGYWxzZSwnd2lmaV9lbmFibGVkJzpUcnVlLCdibHVldG9vdGhfZW5hYmxl
ZCc6VHJ1ZSwnZGlzcGxheXMnOlt7J2lkJzonZURQLTF8MTAyNHg2NDB8NjAnLCduYW1lJzonZURQ
LTEgwrcgMTAyNMOXNjQwIMK3IDYwIEh6JywnY3VycmVudCc6VHJ1ZX1dLCdwb2ludGVycyc6W3sn
aWQnOicxMicsJ25hbWUnOidUb3VjaHBhZCcsJ3NwZWVkJzowLCduYXR1cmFsJzpUcnVlLCd0YXAn
OlRydWV9XSwnc2lua3MnOlt7J2lkJzonNDInLCduYW1lJzonU3BlYWtlcnMnLCdkZWZhdWx0JzpU
cnVlfSx7J2lkJzonNTcnLCduYW1lJzonQWlyUG9kcycsJ2RlZmF1bHQnOkZhbHNlfV0sJ2JyaWdo
dG5lc3MnOnsnc2NyZWVuJzp7J2RldmljZSc6J2ludGVsX2JhY2tsaWdodCcsJ3BlcmNlbnQnOjYw
fSwna2V5Ym9hcmQnOnsnZGV2aWNlJzonc3BpOjprYmRfYmFja2xpZ2h0JywncGVyY2VudCc6MzB9
fSwnb3MnOnsnTkFNRSc6J0VjbGlwc2VPUycsJ1ZFUlNJT04nOicwLjMtZGV2JywnVEFSR0VUJzon
Rml4dHVyZSBoYXJkd2FyZScsJ0ZFRE9SQSc6JzQ0J30sJ2tlcm5lbCc6J2ZpeHR1cmUta2VybmVs
J30sJ2l0ZW1zJzpbeydpZCc6J2ZpeHR1cmUnLCduYW1lJzonRml4dHVyZSBkZXZpY2UnLCdkZXRh
aWwnOidBdmFpbGFibGUnLCdjb25uZWN0ZWQnOlRydWV9XSwnc3RhdHVzJzonUmVhZHknLCdkb25l
JzpUcnVlfSksZmx1c2g9VHJ1ZSkKKylQWSIpOyBoZWxwZXIuY2xvc2UoKTsKKyAgICAgICAgcXB1
dGVudigiTU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUiLGhlbHBlci5maWxlTmFtZSgpLnRvVXRm
OCgpKTsKKyAgICAgICAgUVFtbEVuZ2luZSBlbmdpbmU7CisgICAgICAgIFFRbWxDb21wb25lbnQg
Y29tcG9uZW50KCZlbmdpbmUsIFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNlICsgIi9hcHAvbW9v
bmxpZ2h0b3MvdGVzdHMvSGFybmVzcy5xbWwiKSk7CisgICAgICAgIFFTY29wZWRQb2ludGVyPFFP
YmplY3Q+IHJvb3QoY29tcG9uZW50LmNyZWF0ZSgpKTsgUVZFUklGWTIocm9vdCwgcVByaW50YWJs
ZShjb21wb25lbnQuZXJyb3JTdHJpbmcoKSkpOworICAgICAgICBhdXRvIHBhbmVsID0gcm9vdC0+
ZmluZENoaWxkPFFPYmplY3QqPigidGVzdFBhbmVsIik7IFFWRVJJRlkocGFuZWwpOworICAgICAg
ICBhdXRvIHN0YXRlID0gcm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigidGVzdFN0YXRlIik7IFFW
RVJJRlkoc3RhdGUpOworICAgICAgICBmb3IgKGludCBpID0gMDsgaSA8IDE2OyArK2kpIHsKKyAg
ICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwg
ImNob29zZUFjY2VudCIsIFFfQVJHKFFWYXJpYW50LCBpKSkpOworICAgICAgICAgICAgUUNPTVBB
UkUoc3RhdGUtPnByb3BlcnR5KCJhY2NlbnQiKS52YWx1ZTxRQ29sb3I+KCkucmdiKCksRWNsaXBz
ZU92ZXJsYXlTdHlsZTo6YWNjZW50KGkpLnJnYigpKTsKKyAgICAgICAgICAgIFFWRVJJRlkoc3Rh
dGUtPnByb3BlcnR5KCJwcmVzc2VkIikudmFsdWU8UUNvbG9yPigpLmlzVmFsaWQoKSk7CisgICAg
ICAgIH0KKyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0
YSgpLCAiY2hvb3NlQWNjZW50IiwgUV9BUkcoUVZhcmlhbnQsIDQpKSk7CisgICAgICAgIGZvciAo
UVN0cmluZyBraW5kIDogeyJuZXR3b3JrIiwgImJhdHRlcnkiLCAiaG9zdCJ9KSB7CisgICAgICAg
ICAgICBRVkVSSUZZKHBhbmVsLT5zZXRQcm9wZXJ0eSgia2luZCIsIGtpbmQpKTsKKyAgICAgICAg
ICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChwYW5lbCwgIm9wZW4iKSk7IFFU
ZXN0OjpxV2FpdCgzMDApOworICAgICAgICAgICAgUVZFUklGWShwYW5lbC0+cHJvcGVydHkoInZp
c2libGUiKS50b0Jvb2woKSk7CisgICAgICAgICAgICBRU3RyaW5nIG91dCA9IHFFbnZpcm9ubWVu
dFZhcmlhYmxlKCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgICAgICBpZiAoIW91dC5p
c0VtcHR5KCkpIHsKKyAgICAgICAgICAgICAgICBRRGlyKCkubWtwYXRoKG91dCk7CisgICAgICAg
ICAgICAgICAgYXV0byB3aW5kb3cgPSBxb2JqZWN0X2Nhc3Q8UVF1aWNrV2luZG93Kj4ocm9vdC5k
YXRhKCkpOyBRVkVSSUZZKHdpbmRvdyk7CisgICAgICAgICAgICAgICAgUVZFUklGWSh3aW5kb3ct
PmdyYWJXaW5kb3coKS5zYXZlKG91dCArICIvIiArIGtpbmQgKyAiLnBuZyIpKTsKKyAgICAgICAg
ICAgIH0KKyAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChwYW5l
bCwgImNsb3NlIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgfQorICAgICAgICBhdXRv
IGNvbm5lY3Rpb25zID0gcm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigiY29ubmVjdGlvbnNQYW5l
bCIpOyBRVkVSSUZZKGNvbm5lY3Rpb25zKTsKKyAgICAgICAgZm9yIChRU3RyaW5nIGtpbmQgOiB7
IndpZmkiLCAiYnQifSkgeworICAgICAgICAgICAgcm9vdC0+c2V0UHJvcGVydHkoIndpZHRoIiwg
MTAyNCk7IHJvb3QtPnNldFByb3BlcnR5KCJoZWlnaHQiLCA2NDApOworICAgICAgICAgICAgUVZF
UklGWShjb25uZWN0aW9ucy0+c2V0UHJvcGVydHkoImtpbmQiLCBraW5kKSk7CisgICAgICAgICAg
ICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY29ubmVjdGlvbnMsICJvcGVuIikp
OyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgICAgIFFWRVJJRlkoY29ubmVjdGlvbnMtPnBy
b3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAgICAgICAgUVZFUklGWShjb25uZWN0
aW9ucy0+cHJvcGVydHkoIndpZHRoIikudG9JbnQoKSA8PSA5OTIpOworICAgICAgICAgICAgUVN0
cmluZyBvdXQgPSBxRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9TQ1JFRU5TSE9UUyIpOwor
ICAgICAgICAgICAgaWYgKCFvdXQuaXNFbXB0eSgpKSB7CisgICAgICAgICAgICAgICAgYXV0byB3
aW5kb3cgPSBxb2JqZWN0X2Nhc3Q8UVF1aWNrV2luZG93Kj4ocm9vdC5kYXRhKCkpOyBRVkVSSUZZ
KHdpbmRvdyk7CisgICAgICAgICAgICAgICAgUVZFUklGWSh3aW5kb3ctPmdyYWJXaW5kb3coKS5z
YXZlKG91dCArICIvIiArIGtpbmQgKyAiLXNlbGVjdG9yLnBuZyIpKTsKKyAgICAgICAgICAgIH0K
KyAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChjb25uZWN0aW9u
cywgImNsb3NlIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgfQorICAgICAgICBhdXRv
IGNsaWNrRGlhbG9nQnV0dG9uPVtdKFFPYmplY3QqIGRpYWxvZyxjb25zdCBRU3RyaW5nJiB0ZXh0
KSB7CisgICAgICAgICAgICBhdXRvIGZvb3Rlcj1kaWFsb2ctPnByb3BlcnR5KCJmb290ZXIiKS52
YWx1ZTxRT2JqZWN0Kj4oKTsgaWYoIWZvb3RlcikgcmV0dXJuIGZhbHNlOworICAgICAgICAgICAg
Zm9yKGF1dG8gY2hpbGQ6Zm9vdGVyLT5maW5kQ2hpbGRyZW48UU9iamVjdCo+KCkpIGlmKGNoaWxk
LT5wcm9wZXJ0eSgidGV4dCIpLnRvU3RyaW5nKCk9PXRleHQgJiYgY2hpbGQtPm1ldGFPYmplY3Qo
KS0+aW5kZXhPZlNpZ25hbCgiY2xpY2tlZCgpIik+PTApIHJldHVybiBRTWV0YU9iamVjdDo6aW52
b2tlTWV0aG9kKGNoaWxkLCJjbGlja2VkIik7CisgICAgICAgICAgICByZXR1cm4gZmFsc2U7Cisg
ICAgICAgIH07CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChjb25u
ZWN0aW9ucywib3BlbiIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgIGZvcihjb25zdCBR
U3RyaW5nJiBuYW1lOnsiY29ubmVjdGlvbkNyZWRlbnRpYWwiLCJjb25uZWN0aW9uRm9yZ2V0In0p
IHsKKyAgICAgICAgICAgIGF1dG8gZGlhbG9nPXJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4obmFt
ZSk7IFFWRVJJRlkoZGlhbG9nKTsKKyAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omlu
dm9rZU1ldGhvZChkaWFsb2csIm9wZW4iKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAgICAgICAg
ICAgUVZFUklGWShkaWFsb2ctPnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAg
ICAgICAgUVN0cmluZyBkZXN0aW5hdGlvbj1xRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9T
Q1JFRU5TSE9UUyIpOworICAgICAgICAgICAgaWYoIWRlc3RpbmF0aW9uLmlzRW1wdHkoKSkgUVZF
UklGWShxb2JqZWN0X2Nhc3Q8UVF1aWNrV2luZG93Kj4ocm9vdC5kYXRhKCkpLT5ncmFiV2luZG93
KCkuc2F2ZShkZXN0aW5hdGlvbisiLyIrbmFtZSsiLnBuZyIpKTsKKyAgICAgICAgICAgIFFWRVJJ
RlkoY2xpY2tEaWFsb2dCdXR0b24oZGlhbG9nLG5hbWU9PSJjb25uZWN0aW9uQ3JlZGVudGlhbCI/
IkNhbmNlbCI6Ik5vIikpOworICAgICAgICAgICAgUVRlc3Q6OnFXYWl0KDQwMCk7IFFWRVJJRlky
KCFkaWFsb2ctPnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkscVByaW50YWJsZShuYW1lKSk7
CisgICAgICAgIH0KKyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNv
bm5lY3Rpb25zLCJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDIwMCk7CisgICAgICAgIFFRbWxDb21w
b25lbnQgYWN0aW9uQ29tcG9uZW50KCZlbmdpbmUsUVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2Ur
Ii9hcHAvZ3VpL0VjbGlwc2VBY3Rpb25CdXR0b24ucW1sIikpOworICAgICAgICBRU2NvcGVkUG9p
bnRlcjxRT2JqZWN0PiBhY3Rpb24oYWN0aW9uQ29tcG9uZW50LmNyZWF0ZSgpKTsgUVZFUklGWTIo
YWN0aW9uLHFQcmludGFibGUoYWN0aW9uQ29tcG9uZW50LmVycm9yU3RyaW5nKCkpKTsKKyAgICAg
ICAgYXV0byBhY3Rpb25JdGVtID0gcW9iamVjdF9jYXN0PFFRdWlja0l0ZW0qPihhY3Rpb24uZGF0
YSgpKTsgUVZFUklGWShhY3Rpb25JdGVtKTsKKyAgICAgICAgYXV0byBhY3Rpb25XaW5kb3cgPSBx
b2JqZWN0X2Nhc3Q8UVF1aWNrV2luZG93Kj4ocm9vdC5kYXRhKCkpOyBRVkVSSUZZKGFjdGlvbldp
bmRvdyk7CisgICAgICAgIGFjdGlvbkl0ZW0tPnNldFBhcmVudEl0ZW0oYWN0aW9uV2luZG93LT5j
b250ZW50SXRlbSgpKTsgYWN0aW9uSXRlbS0+Zm9yY2VBY3RpdmVGb2N1cygpOworICAgICAgICBR
U2lnbmFsU3B5IGFjdGl2YXRlZChhY3Rpb24uZGF0YSgpLFNJR05BTChjbGlja2VkKCkpKTsKKyAg
ICAgICAgUVRlc3Q6OmtleUNsaWNrKGFjdGlvbldpbmRvdyxRdDo6S2V5X1JldHVybik7IFFDT01Q
QVJFKGFjdGl2YXRlZC5jb3VudCgpLDEpOworICAgICAgICBhY3Rpb25JdGVtLT5zZXRWaXNpYmxl
KGZhbHNlKTsKKyAgICAgICAgYXV0byBjZW50ZXIgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+
KCJjb250cm9sQ2VudGVyIik7IFFWRVJJRlkoY2VudGVyKTsKKyAgICAgICAgUVZFUklGWShRTWV0
YU9iamVjdDo6aW52b2tlTWV0aG9kKGNlbnRlciwib3BlbiIpKTsgUVRlc3Q6OnFXYWl0KDUwMCk7
CisgICAgICAgIFFWRVJJRlkoY2VudGVyLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsK
KyAgICAgICAgUVN0cmluZyBvdXQgPSBxRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9TQ1JF
RU5TSE9UUyIpOworICAgICAgICBhdXRvIHdpbmRvdyA9IHFvYmplY3RfY2FzdDxRUXVpY2tXaW5k
b3cqPihyb290LmRhdGEoKSk7IFFWRVJJRlkod2luZG93KTsKKyAgICAgICAgaWYgKCFvdXQuaXNF
bXB0eSgpKSBRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0KyIvZWNsaXBzZS1j
b250cm9sLWNlbnRlci5wbmciKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9r
ZU1ldGhvZChjZW50ZXIsImNsb3NlIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgYXV0
byBhYm91dCA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oImFib3V0RWNsaXBzZSIpOyBRVkVS
SUZZKGFib3V0KTsKKyAgICAgICAgYWJvdXQtPnNldFByb3BlcnR5KCJpbmZvIiwgUVZhcmlhbnRN
YXB7eyJvcyIsUVZhcmlhbnRNYXB7eyJOQU1FIiwiRWNsaXBzZU9TIn0seyJWRVJTSU9OIiwiMC4z
LWRldiJ9LHsiVEFSR0VUIiwiRml4dHVyZSBoYXJkd2FyZSJ9LHsiRkVET1JBIiwiNDQifX19LHsi
a2VybmVsIiwiZml4dHVyZS1rZXJuZWwifX0pOworICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0
OjppbnZva2VNZXRob2QoYWJvdXQsIm9wZW4iKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAgICAg
ICBRVkVSSUZZKGFib3V0LT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsKKyAgICAgICAg
aWYgKCFvdXQuaXNFbXB0eSgpKSBRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0
KyIvZWNsaXBzZS1hYm91dC5wbmciKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omlu
dm9rZU1ldGhvZChhYm91dCwiY2xvc2UiKSk7CisgICAgICAgIGF1dG8gc3lzdGVtPXJvb3QtPmZp
bmRDaGlsZDxRT2JqZWN0Kj4oInN5c3RlbVNldHRpbmdzIik7IFFWRVJJRlkoc3lzdGVtKTsKKyAg
ICAgICAgZm9yKGludCBzY2FsZTp7MTAwLDExMCwxMjV9KSB7CisgICAgICAgICAgICBRVkVSSUZZ
KFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29zZVNjYWxlIixRX0FS
RyhRVmFyaWFudCxzY2FsZSkpKTsKKyAgICAgICAgICAgIHJvb3QtPnNldFByb3BlcnR5KCJ3aWR0
aCIsMTAyNCk7IHJvb3QtPnNldFByb3BlcnR5KCJoZWlnaHQiLDY0MCk7CisgICAgICAgICAgICBz
eXN0ZW0tPnNldFByb3BlcnR5KCJhY3RpdmUiLHRydWUpOyBRVGVzdDo6cVdhaXQoNDAwKTsKKyAg
ICAgICAgICAgIFFWRVJJRlkoc3lzdGVtLT5wcm9wZXJ0eSgid2lkdGgiKS50b0ludCgpPD0xMDI0
KTsKKyAgICAgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKSBRVkVSSUZZKHdpbmRvdy0+Z3JhYldp
bmRvdygpLnNhdmUob3V0KyIvc3lzdGVtLWNvbnRyb2xzLSIrUVN0cmluZzo6bnVtYmVyKHNjYWxl
KSsiLnBuZyIpKTsKKyAgICAgICAgICAgIGZvcihpbnQgYWNjZW50PTA7YWNjZW50PDE2O2FjY2Vu
dCsrKSB7CisgICAgICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9k
KHJvb3QuZGF0YSgpLCJjaG9vc2VBY2NlbnQiLFFfQVJHKFFWYXJpYW50LGFjY2VudCkpKTsgUVRl
c3Q6OnFXYWl0KDEwKTsKKyAgICAgICAgICAgICAgICBRVkVSSUZZKHN0YXRlLT5wcm9wZXJ0eSgi
YWNjZW50IikudmFsdWU8UUNvbG9yPigpLmlzVmFsaWQoKSk7CisgICAgICAgICAgICB9CisgICAg
ICAgICAgICBhdXRvIHNjcm9sbD1yb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJzeXN0ZW1TY3Jv
bGwiKTsgUVZFUklGWShzY3JvbGwpOworICAgICAgICAgICAgYXV0byBmbGljaz1zY3JvbGwtPnBy
b3BlcnR5KCJjb250ZW50SXRlbSIpLnZhbHVlPFFRdWlja0l0ZW0qPigpOyBRVkVSSUZZKGZsaWNr
KTsKKyAgICAgICAgICAgIGF1dG8gbW9uaXRvcj1yb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJo
YXJkd2FyZU1vbml0b3IiKTsgUVZFUklGWShtb25pdG9yKTsKKyAgICAgICAgICAgIGZsaWNrLT5z
ZXRQcm9wZXJ0eSgiY29udGVudFkiLG1vbml0b3ItPnByb3BlcnR5KCJ5IikpOyBRVGVzdDo6cVdh
aXQoMjAwKTsKKyAgICAgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKSBRVkVSSUZZKHdpbmRvdy0+
Z3JhYldpbmRvdygpLnNhdmUob3V0KyIvaGFyZHdhcmUtbW9uaXRvci0iK1FTdHJpbmc6Om51bWJl
cihzY2FsZSkrIi5wbmciKSk7CisgICAgICAgICAgICBmbGljay0+c2V0UHJvcGVydHkoImNvbnRl
bnRZIiwwKTsKKyAgICAgICAgICAgIHN5c3RlbS0+c2V0UHJvcGVydHkoImFjdGl2ZSIsZmFsc2Up
OyBRVGVzdDo6cVdhaXQoMTAwKTsKKyAgICAgICAgfQorICAgICAgICBRVkVSSUZZKFFNZXRhT2Jq
ZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29zZVNjYWxlIixRX0FSRyhRVmFyaWFu
dCwxMDApKSk7CisgICAgICAgIHF1bnNldGVudigiTU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUi
KTsKKyAgICB9Cit9OworUVRFU1RfTUFJTihDcmltc29uVGVzdCkKKyNpbmNsdWRlICJ0ZXN0LWNy
aW1zb24ubW9jIgpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNv
bi5wcm8gYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvdGVzdC1jcmltc29uLnBybwpuZXcgZmlsZSBt
b2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi44ODFmODU5Ci0tLSAvZGV2L251bGwKKysrIGIvYXBw
L21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5wcm8KQEAgLTAsMCArMSwyMSBAQAorUVQg
Kz0gY29yZSBndWkgcXVpY2sgbmV0d29yayBxdWlja2NvbnRyb2xzMiB0ZXN0bGliIHN2ZworQ09O
RklHICs9IGMrKzE3IHRlc3RjYXNlCitUQVJHRVQgPSB0ZXN0LWNyaW1zb24KK1NPVVJDRVMgKz0g
dGVzdC1jcmltc29uLmNwcCAuLi9jcmltc29uc3RhdHVzLmNwcAorSEVBREVSUyArPSAuLi9jcmlt
c29uc3RhdHVzLmgKKworU09VUkNFUyArPSAuLi9tYW5hZ2VkdXBkYXRlcy5jcHAKK0hFQURFUlMg
Kz0gLi4vLi4vYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5oCisKK0RFRklORVMgKz0gTU9PTkxJ
R0hUX0NPTlRST0xTX1RFU1QKK1NPVVJDRVMgKz0gLi4vc3lzdGVtY29udHJvbHMuY3BwCitIRUFE
RVJTICs9IC4uL3N5c3RlbWNvbnRyb2xzLmgKKworU09VUkNFUyArPSAuLi9lY2xpcHNlcHJvZmls
ZXMuY3BwCitIRUFERVJTICs9IC4uL2VjbGlwc2Vwcm9maWxlcy5oCisKKyMgTWF0Y2ggdGhlIHBy
b2R1Y3Rpb24gcmVzb3VyY2UgYnVuZGxlIHNvIHJlbmRlcmVkIGljb25zIGFyZSBhY3R1YWxseSB0
ZXN0ZWQuCitSRVNPVVJDRVMgKz0gLi4vLi4vcmVzb3VyY2VzLnFyYworCitTT1VSQ0VTICs9IC4u
L2xvY2FsaGFyZHdhcmUuY3BwCitIRUFERVJTICs9IC4uL2xvY2FsaGFyZHdhcmUuaApkaWZmIC0t
Z2l0IGEvYXBwL3FtbC5xcmMgYi9hcHAvcW1sLnFyYwppbmRleCBhM2MxMWRkLi43MTRjNjUxIDEw
MDY0NAotLS0gYS9hcHAvcW1sLnFyYworKysgYi9hcHAvcW1sLnFyYwpAQCAtMTQsNiArMTQsMTEg
QEAKICAgICAgICAgPGZpbGU+Z3VpL1ZiSG9zdENhcmQucW1sPC9maWxlPgogICAgICAgICA8Zmls
ZT5ndWkvVmJXZWxjb21lU2hlZXQucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvbWFpbi5x
bWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbDwvZmls
ZT4KKyAgICAgICAgPGZpbGU+Z3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9nLnFtbDwvZmlsZT4K
KyAgICAgICAgPGZpbGU+Z3VpL0VjbGlwc2VDb250cm9sQ2VudGVyLnFtbDwvZmlsZT4KKyAgICAg
ICAgPGZpbGU+Z3VpL0VjbGlwc2VBY3Rpb25CdXR0b24ucW1sPC9maWxlPgorICAgICAgICA8Zmls
ZT5ndWkvRWNsaXBzZUFib3V0RGlhbG9nLnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL1Bj
Vmlldy5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9BcHBWaWV3LnFtbDwvZmlsZT4KICAg
ICAgICAgPGZpbGU+Z3VpL1NldHRpbmdzVmlldy5xbWw8L2ZpbGU+CmRpZmYgLS1naXQgYS9hcHAv
cmVzL2NyaW1zb24tYmF0dGVyeS5zdmcgYi9hcHAvcmVzL2NyaW1zb24tYmF0dGVyeS5zdmcKbmV3
IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMzc1MzU2NgotLS0gL2Rldi9udWxsCisr
KyBiL2FwcC9yZXMvY3JpbXNvbi1iYXR0ZXJ5LnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5z
PSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3
Qm94PSIwIDAgMjQgMjQiPjxnIGZpbGw9Im5vbmUiIHN0cm9rZT0iI0VDRUVGMSIgc3Ryb2tlLXdp
ZHRoPSIxLjgiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+
PHJlY3QgeD0iMiIgeT0iNiIgd2lkdGg9IjE4IiBoZWlnaHQ9IjEyIiByeD0iMiIvPjxwYXRoIGQ9
Ik0yMiAxMHY0TTYgMTB2NE0xMCAxMHY0TTE0IDEwdjQiLz48L2c+PC9zdmc+CmRpZmYgLS1naXQg
YS9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1ibHVldG9v
dGguc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmNlZjlhYjgKLS0tIC9k
ZXYvbnVsbAorKysgYi9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZwpAQCAtMCwwICsxIEBA
Cis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWln
aHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik03IDdsMTAgMTAtNSA0VjNsNSA0
TDcgMTciIGZpbGw9Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJv
a2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlmZiAt
LWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1ob3N0LnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1ob3N0LnN2
ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5kMWQ1OWIwCi0tLSAvZGV2L251
bGwKKysrIGIvYXBwL3Jlcy9jcmltc29uLWhvc3Quc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1s
bnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZp
ZXdCb3g9IjAgMCAyNCAyNCI+PGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRUNFRUYxIiBzdHJva2Ut
d2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5k
Ij48cmVjdCB4PSIzIiB5PSIzIiB3aWR0aD0iMTgiIGhlaWdodD0iMTQiIHJ4PSIyIi8+PHBhdGgg
ZD0iTTggMjFoOE0xMiAxN3Y0TTYgMTBoM2wyLTQgMyA4IDItNGgyIi8+PC9nPjwvc3ZnPgpkaWZm
IC0tZ2l0IGEvYXBwL3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnIGIvYXBwL3Jlcy9jcmltc29uLW5l
dHdvcmsuc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmIyYTEwM2EKLS0t
IC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2NyaW1zb24tbmV0d29yay5zdmcKQEAgLTAsMCArMSBA
QAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVp
Z2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48ZyBmaWxsPSJub25lIiBzdHJva2U9IiNFQ0VF
RjEiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5l
am9pbj0icm91bmQiPjxwYXRoIGQ9Ik0zIDhhMTQgMTQgMCAwIDEgMTggME02IDEyYTkgOSAwIDAg
MSAxMiAwTTkgMTZhNCA0IDAgMCAxIDYgMCIvPjxjaXJjbGUgY3g9IjEyIiBjeT0iMjAiIHI9IjEi
Lz48L2c+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtY29udHJvbHMuc3ZnIGIv
YXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAw
MDAwMDAwLi42NTNkYmQ4Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9lY2xpcHNlLWNvbnRy
b2xzLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAw
L3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9
Ik00IDZoMTZNNCAxMmgxNk00IDE4aDE2TTggM3Y2TTE2IDl2Nk0xMCAxNXY2IiBmaWxsPSJub25l
IiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5k
IiBzdHJva2UtbGluZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2Vj
bGlwc2UtaWNvbi5zdmcgYi9hcHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcKbmV3IGZpbGUgbW9kZSAx
MDA2NDQKaW5kZXggMDAwMDAwMC4uNzExNWMzMwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMv
ZWNsaXBzZS1pY29uLnN2ZwpAQCAtMCwwICsxLDcgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cu
dzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iNTEyIiBoZWlnaHQ9IjUxMiIgdmlld0JveD0iMCAwIDUx
MiA1MTIiPgorPGRlZnM+PGxpbmVhckdyYWRpZW50IGlkPSJyaW0iIHgxPSIwIiB5MT0iMCIgeDI9
IjEiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjZmY3NThiIi8+PHN0b3Agb2Zmc2V0PSIuNDgi
IHN0b3AtY29sb3I9IiNkYzM2NTgiLz48c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiM2MzE1
MmIiLz48L2xpbmVhckdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0iZ2xhc3MiIHgxPSIwIiB5
MT0iMCIgeDI9IjAiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjMjAxNTFjIi8+PHN0b3Agb2Zm
c2V0PSIxIiBzdG9wLWNvbG9yPSIjMDgwODBiIi8+PC9saW5lYXJHcmFkaWVudD48L2RlZnM+Cis8
cmVjdCB4PSIxMiIgeT0iMTIiIHdpZHRoPSI0ODgiIGhlaWdodD0iNDg4IiByeD0iMTEwIiBmaWxs
PSJ1cmwoI2dsYXNzKSIgc3Ryb2tlPSIjZmZmZmZmIiBzdHJva2Utb3BhY2l0eT0iLjEzIiBzdHJv
a2Utd2lkdGg9IjIiLz4KKzxjaXJjbGUgY3g9IjI1NiIgY3k9IjI1NiIgcj0iMTQ0IiBmaWxsPSJ1
cmwoI3JpbSkiLz4KKzxjaXJjbGUgY3g9IjI2OCIgY3k9IjI0OSIgcj0iMTM2IiBmaWxsPSIjMDgw
ODBiIi8+Cis8cGF0aCBkPSJNMTUxIDE2MmExNDMgMTQzIDAgMCAxIDEzNS00OCIgZmlsbD0ibm9u
ZSIgc3Ryb2tlPSIjZmZlOGVlIiBzdHJva2Utb3BhY2l0eT0iLjU1IiBzdHJva2Utd2lkdGg9IjMi
IHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPgorPC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2Vj
bGlwc2UtbWFyay0xMjgucG5nIGIvYXBwL3Jlcy9lY2xpcHNlLW1hcmstMTI4LnBuZwpuZXcgZmls
ZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwLi4xNTEyMWMwNGJlN2E0Y2I5ZmI2NWZmMDk5ZDc0NjdiNDQ0YzZlOTBkCkdJVCBiaW5hcnkg
cGF0Y2gKbGl0ZXJhbCA3MDg3CnpjbVY7ZzgmS3FsUCk8aDszS3xMazAwMGUxTkpMVHEwMDRqaDAw
NGpwMV5AczYhIy1pbDAwMHx5TmtsPFpjJTFFPgp6ZDYtPCliPk0mSi1kQ0B4eUx3ZCUyXyZfSWdw
aztnRmgpUlpnYmo4RWoyRk8tP0hDN2RuMmhsXjhTbjlZPTk1ViMKejZNclU/Y3JyNnkkbWlJMmE2
RkZVSTVPaXZqMkZPUXZ6dlZwbEYrYE9tVV5rYCtUT2VPJXBiMyspb0x8RGZWI1JgCnpzJFlNdktk
SE9BLW03PWNKQD1lKiZwbDc1RjlNK0tgYClDNkJzVkFGaGAyZWpZU2sqVWFePWJaMm1td0g3Y2BB
OQp6SyhLUDwlMyMmMVJSK2ZEI15MMyN6d3hTN3RJVWx6LWVgYiQ/OVl1Z3hZKEluWkBzbGAqU2NM
e3h3Nkx8P3NIRlAKeihxV0lBeT9BIXo+WmBCTCtyV0Q3e1A+cHl0NSZWQEh7TipUMGwjPVg5NXd+
JD4rNz90U0ZpUnwmNmxkbUg2T1U8CnpscFdpKXpIeFlIX3pqaEVkMSlORzxEN0hkcz1nSn47QmNN
JGgoSUozRiRIVndLb0htK1ZMSlZNTWB5PCkkSVlHaAp6JkBEZl88cnh2Rk8kKlozKkpvQypVaE5M
Y1g8elJmUjBaejxZIUxBTkUzUDxlKUF9diU5VWRDR3Z8SzhtPUFFPDcKemRBeGQxdCFsXlhKP2p5
UVIwU2V9NXJlZWBXMzVZUChvZU5AdypUQWx6NEwka1B5Zz5Ia0htM2VUKnV6fipLeHwlCnpefHVD
YXNaQCRmUj0palJUZW9mZlI2ZHUjSUYySDUmWT1uanVCeUV2YF80Q01iSntlZ0hhLStrUlRVSH4w
QGhsQgp6UjclXzArSX41QT8lZS0lJDMxdGhpSn1PPTA7ODdxKSQqRElRUFZzeiFzVkE7eys1a3Yq
TUI4OUpiWGM9UW8qWXQKek1xKXV+JmRXSUd3a2k5QWJIRmBIbG1ZZVhIODNLQ1ZNdHA/YCk/TVhj
KjBseWBEZyQ3RUE+aHJlUmVnay1XdDNYCnpYO3tHaDsyWW9Re0Aqdj5APmwpK3lSUiNrJTZScU83
XkJ0U0g8Pih+X2c7Kk1Ob08rNW9PUjYyKk1JeilLbHxWKAp6S1JHfVdaTjt6ajI0aWAoM0o/SkNS
cXdwJjUxeFBhc3FZTEE8KDlAU1IlNDgoRGZvS2h5IVI1PXo7dHhCS1l6KzsKenIrKW0wfEdONUtV
Wm9QZThVP1QtO0AqRDIjVUl8aGUjNXMkM2RKLStFRncqQmVoTnw1NyRzPVF3cDMxN3dDSzlxCnpA
QTx7fFJNaTU5RyN3bk8wdDh8dHpHJWUtcFdEMjclVDB4MTVvP1UySXFEayk9ZUBUckVpTHIrX0l9
fTQ1OGlXPQp6YGFASEtTSW98PldNdj5DQHI1ZmNffXM9I257TyU8aV9SRk0zUmJDbEQ5dk40ND1j
dUtwOyZhQUhnRXBnZykxKWoKem9RU3hVdGI5ZjVkezcxRz4rNz8zYjllbFFEPSlyZz4qZyZ0bH1h
VU5qRzVIYldSdXM3Ny1MTVNSRW9FNS1nNDkxCnpGU3opX2NYTX4jKlZsSllFQiYkeFB6JmB3Yz09
VzV6UE50RiZCYkVUSC0rRXVoJXY/JWkkJVkyITs5Yms7TkA0SAp6eUwkQyVjUTdUR1A/KEJ9QW9B
VnNleilVcXtfRUVzOXZtMXZMNXo1czNwJiNVdWlsJWs/KFglVWBTS1Vlez5Wb0AKekdPVlp5cXZf
O1BDUkJodnVzPTQmb3BaKW5IfUJsR15JR1IhKTd6aEJzQV9ERDRVVjBBP0I3NTUjR3t8Xi1jUlRo
Cno5eCRUJnpeKEBPLXBrJXxMSTNWTypHNFhPaCVfQyhYPzdyREJOd349LUZ2Uj5kKnxoRTIzKzMr
UVFKZm96XkUkQQp6bVlqQyktYVB+N0F2RDlpPjVEX0xHa1NWe2BgRnFpLVlnPUp0UShCN3A5U2Nu
JmpTOVA3aFVwPmR+VzFDTVZyRSgKei1kSUlfSzlAV0hUXkM8XkRkNUxEZ3lTdU12RFclaVBkTkc0
MU8wbjFZPnhnVDAqN0x7WFpHQ25eIWpKcz5ZT3UtCnp1Pnp3T3Bqdnc1YGAqKkh5cFNKeHYjTThg
IWFvd1FVT2swO3sofD5pQHhFbiV1Z1YoTy12Ul9jZUQxUWR6cSk8Zgp6anhSZHpWQFpEMldjbXt1
Vn1kenpqe0VCVWszYWsrI3ctfCheI1BvITJFIytTY1IxJmVYM1QjaVZWclhlPWtvOCsKenEhZSM3
OTVnVSR7YEh5PGR8K3cwVHQwZDFAMHVKRDc9VXVBYm4/fCNVQStYKitCOUdRP3otelAxRiYoXl83
JT4jCnpMdGFYM0dPY2pWeG5TJG9PKUZyWiVuaVdaY2kjO19GYHItVm9udVN8PkpmI0FBUi11SjR0
bXNIY08pU3E+WVphRwp6VXN3K05XTHxVZnlzPyYyc2wzI0E5aylxa2BlSkg9UlBmI3QjU3V+TGFO
Z2wtNzBUMks3YlU0JDlhRThPWkdhaUMKejItRWtAaTFTTGhSNmZhQWkrOVAhZ01qMkNjXkFqXzxi
QH5BUVB0fExuNFREODVXcVB7cDtEJENNfGZqc1g+RnlhCnpyLSN8eUdkUU5CbGdAMEdiU2d4UTs4
ZHgmbX0wcmlOVT16NkIrdDskRmhqI1JxTm9CMHF2fHEhWktKM3ZRNTROXwp6YWNvN3owczl0c1pv
VCFedG9Mek9FdDVQfFNOVTN+amF1ZyZgSD5NUy1xRl80JmVEWlRJT2x7RFN1dVlSM3A9XzwKenQx
eV8pdjJBRjhaRyhIK21DdiFhVHdvfXdQKkhgemw1V2l+dWN3UHNKMzg2QmNRMUdUYFl1dnwjZnNU
Q0VoemdHCnpWcF5laUA0RDhrUzw/I1NVYCg5OVl1JkM7b3dsTSg4fVcrPlJ0KTgrTGNVbGUrdCRW
I216fkxGJWcqTUtnLWUoKAp6QT1gS0M8bGc2PjthbHNVPEkhRFBkMng3dlR3TGJCcDxNZ1czSyhu
PGtQZyMwPWE1SitBX1ReZ3ZYOztXU2QtKykKelJIdXoxMm55PTdiPX5qUnJLdUBecTZvc0Mke3dy
ZT0+SG9UMGoja1VxWTVMJUJKKmE/PUlUR1pnYiR1fDk/TSQwCnpDfmV4eEtpX2REKkZXPHBfd0Mt
c2glMTl3TlRtbzxtZSNRQ2ZLTkRIakg7Umx6ZEd1akRsVSNGI31PaHolMzlKawp6TUhtRGFHMUVk
M0gyRGhsUlFGe254X19vYHp2YVhSI1RyQkdKJHJ8VFNhfEhRZUQ7ZD5AdTZrc2E5bV9+PjhZcHEK
ekA8WD9CJVpwRjV3VXxweGRZQj9CO2klYkcpbnVGNkF1dSkpc0JQSipRSGYoSmFnMj0mPV4jWlcy
cjtJeTY9NVJUCnpQTWNKKDBMRUdkTUBIeU1yfUBHYVM4P3FoeW9FVk1DSExzRmVDNSU1YFIwWnZk
OHc0ZzF9VTxjUnpVSHB4SSt+OQp6dEdiPnNtU0xuKXJXOGVGUVh3cz01RHtyO01IdEpwUHlqMjJO
SWlvP0wlaWU2di10OD1TOTV4KjRXOE0remRaZFkKekgjfmhtJmtWanE1UU1hYUVzNDNGMWZmcmFr
U0skcTZlPWFrYVlReXU2OSViaXAjJS1EMEQmPiZEcktANXpKQiRgCnpgMCk4RjNEJDA9fEhZQGQ7
cHlNO3RyczIjNyFgYjZDJjVwSWh+VSZRVHE9LUJnPUU3RkdCJCo0SypsTFJWfGY5QQp6dkZ0NjNh
N05FOHpXRkRBJHs4SXEoY2VBSlY9cnl6O304RndNfE4kY0hRZlIqckdnKWVSUUd0N3E2KUVodzFx
N00KeiN4I2YkOTRPb1Vvan4xcE9mYFlBPzlTKFMqV3kkNyl+N3lBK3dMTHMhTjw4e19nNFArLXJN
TGU2PT0ofTY4cHZ3Cnp7Q0dyISpnSit4QlZAeEMhWFRMUERQYmJuSHNsbXd0KSlNZzxLeFREO3Bf
a0xLVCYqazlsYGN+eyZEK3lLNj53TQp6SUU4RX4tTFMmMUFxWERHU0JobEdrWndTfnB5OEgkdHVn
RyQ0Umlmaj1rYSZmZjEzUWAmeXdBLWhnLUw9PDNzblgKejBmZi1ueDtjNVRtcztSQlFnc2o7WklQ
Kj02ZCo4JEo7ZWVhSk0kY0ZgamJ5Rl53YHNNXnlnVWYocT15VG83K2VrCnppIX16e1Y1OF96OEw1
PTB4VldLfHBrV2pzNU1pS0Y7K0BBVzxtO0ZKNXhNNiNrbGkpRkwtfkhMeG5+V0NPbCNyUwp6JGRg
LTYmTldRN3dJTVFyUilwYT07PFQ8fl9+eDdiMUxkX1pWcShXMGFlVX5XcEU2dTIpMCM/ODg/JTJm
NmVWOU4KeihWbDY9UH5VcSFrISt7ZjB3QEFSLWpmWWRlRGo9KD19TSgzI1dBZzZubT5LdVBNI2xs
aUVNYWUycDx5MSgwTkNwCnpRcmZSPz5Rb1d6end9cHM4KDsrbnFZOGd9X0ZHdWliMWVPWkpUbyhg
e0tNTUVgTyo1UFhpR1A0c1B8ZUM1aGAmKwp6KzFmZnMySUZOYlEpPmFOMiFtMERPWG49KTwwcVdY
UF5teVJOVT1GTCRQSkkoTG49dCY4ek87bl96QDlgUVJSPnEKenJZNEk2NmApU0w3ZXlpVk5Ab3pW
Pld1VThzPkkmWVZndnJfc3IlV1VBMCV5cVk0N3dNNERVVXFzRkZCQGI9eCglCnpLbD4+X3l7PHQ0
QlppPyRuVTV8JG96dUgjRjxkRnJrcVVXdV9qYk8me3opPW5yZVZeJWxaQSotaiQ+bHlzTWMlTAp6
VD9lTFEzSns+PVYmLVElX3s4RWZDYE0lcmtpemdrb19tQnNyQSMwVjZRTkVqaWMpZ1hsdlFDKCR6
OFQkJGoxQGEKekVJTmdHKj4oelhNQW9Ld1YmRW0jWTxWRm0jWDc9QWUrQHkxVCNUQ3tONE0/QEFW
QXMyJXhUVD97Xk9UWWlYdT01Cnp0PnFzI0swfmZ0QVNMRHFiXlJ0clJqSWhDTmZWRCNmWFNiTWow
cEwtIVg/S1kmIVRKPmcqWU5EaFdfRlJLaVRwRQp6Q1AqRjhqXjlMeEJ2d0dSKjdMYzNVTy1VcUVQ
eilmWjMzPzdVNHJ1LVJpIWx1YDFRX0J5ZkQwJW1aTU1zMEd4VXYKej8/ezx8JCpMVX5GV1h3WF9x
dCgzRDdjN3xKN0A1UThNNyhHaVRPN09jV21FP0kpYGJIOUNfVlFsNHpqTEFIU3smCnpBUDhtZXhN
MD5peD42eUxhfDl2YFIhWkVyZG1DY3k1dTVtVkJ9OFBAQkchfW9EUyMlPFBBSFopQTJTIXtlS0gt
MAp6V2tZVXxiQEBSO0pNfnBGUTtFfiRwNDQqOz58WVR5aUIzU1c9O041M1kyfnp6OSFoWnhzKVdZ
eV5pViR8UUhnOVMKempYUjFKS3ZBNmNTVGppalZGS0NLJT5zeEJDRmVNeXQmNz58Und+WWNDV2BV
dyY+cnhPemF5ejBjd2dVMWE5bG1XCnp6T1R0M1FwZUpjWlpnSkYmPFgmfmQpRFdOS3BNTXp4P1hy
Wk9wKyV3ayE8VCs2ZV5zVT9FKzE8WGM/ZCEkODBPKwp6c3xzK21CbTRDJnMwVmRaMDBqYWcleGhe
Jih3P2RhaEp1UzJ0ZCFzPSReOVA7Zmc/OHhAVCM8IWZTS3RHdkc9R1oKekNvZWgyaD5Je0g0WTQw
I3Mrc0lXKzw1QSQwQkxMS3UmR2ZDMEUrWER2aUZ6PEQzNTlnPktnXnRyemxpTmRYb21tCnprZz50
T0RqMShBIz9jKTZQZlhJSztxYnJmNnhJVk1pcDNDQTlVVX47eEB7MXdzaFImfjcrN3NZUGBBXktP
OVV5Qwp6d21ERzh6SktFRUQ0cWJKKWRXZjRCT0xYIWZCLVVDN0k2YUUpLU1zbno3PztVNTsjPmQj
P2xeeUI7Q29IKVNKMn0KemZLcDhidEVVamgpcEJebmRyIXQjV2A+eitTYUBgIVExX3ljeTZwQFM1
c0o8Kzk5MXdYKW19WUgzU29Yckl+Kms/CnpVPFhJNWpWVUs1RD58aTRwcGolTGN6M3lvbTh1VT00
Rnlsa2NHN2VKNlk2YU4+Z29lVD5lKjd2VktmUTwxYztwRAp6bChyZElZbWRyR3BzQCVeLUB8JCln
WF5BdVR7a2pSJT5nTipOaFdZZlliVWVQdHdpZE5ZQ0RraEUzVTZkPlEpcjAKekNAQiV2PF85UmND
XkBrelckJjBCd3MyLWc1M3pGeEhmS0ljUHswX2UpQW8+aylOTjt3UzAhYUVGQkZFQFJWb21XCnpH
KndpdXF7TUxIajUjblZgTEY0TkhIa1J0QztvYjcwdUAzcnlpX2pvUkJrV25ZT0BDY2lnQ24rLUUo
TTlXdkNwYgp6KHx8eUF7O3gwbEU1SWJIb2Q2WkB4cCFiRVJ0NGBCS2BGWUpCYHV3dC0hKz94aTt1
YyNLdUpjd3NuO2dhRzFTJUwKelA9JD1Le0FUWUMyQkgjeTJ3R2hidkxha0hgLUozbV59TUpDQSZ7
d2dMU0oxS3pAdWNXPEB1Mzg5dlJ3QWk/TWsxCno3JDZzd2RFMU9Sb1lLfXE9X3MtU05ARHUwblZS
aXpiPkFLPzJxb3xNJD9pPjk3K28yUnl3WWh5SzZjeV55bXY+OQp6QTBSLSsyNmVnamh1e1FHe15g
QVgrSEFuamA/cz1nV1NFUjMmWSVUYHFCOEcyPTZGdFBwR29tM3VtV0N7dE8tYnMKend2dyZDM2Ut
SWpxKEk2VGMyKXxrZXJXQChDY3ljYDNkSEpadm5mOD9kKWt6QFBNS18hcSV+ZW9Ebm9lK0JjQ2Ek
CnojUHE2VVpOTHdBWkQzT3xONGpQT1IyWWlOVHNDN0tAMEB1Jmd9OHp9MDxDfXtOc0JLQytvKyhV
O3FYKmxPV2pjKgp6WjdpRWhkSCFMP1RDJkZDWUt1YihXIz9HY2RuVThQUnd+e2ZRNSF9REQ2NDA3
a2ZBNClxMkhDMFhsUlBBPUt1dyQKeipEVH56WH0yTV8+e2AjYHhqa2VoaTNrS0pJPiYtXm1jTipQ
N0xuRn0kTHdVSEI7Qz1AWmtAXmNYa0BnWl5pKCoyCnpQfHJscnhJO0NXMUJjXj98Ri00SChlckU3
QXNtUnhUcnMxVVBhUyhRZyh3KiUoO2I2UUAtWXsrOW17VENWWHYhQAp6IXFvTT9rSm99Si1IcVc/
PT9xZipWc0hvRitxc1N8bkBYQk9EcCs3SnVKQzdiUFVXKG0xPzEhRC04amwzNm53PF8Keio8PEpx
R0NXb3FwakNuPy13cj9KY2VMZ1plcj8tUkpkKW8teTl0UFd2VEBXYFJ9MjY5ezVTQlhqXm4xUzU/
RiowCnpBOH5yN257JV9yYTdUVXpxMTN4bUBXZjFUSHx1TVU2ZVNSJDtBMXxzPUBBQ3dHTkJrOyln
UCMrJEJPV2M8SW15egp6X1NzYj5tX0V9JVA1MzhnST1RbElLNUtIQERYR0pmZUVLUTF8NGQ8eyRn
emozVDdqbnZnTTUwXkJOJnA1Vk8oPHgKenkoMlcxWiFLRUUrcSZrR2tJUj9fLSVNV1h6Y2I8XiZU
USVDQmkkIShUWWZ1UjtzUjswYiM/cD5yVURJUFBoKFpPCnpmez1lNytRRkIkSzJBJEBhVWB6cEF9
O3dEZ1lma1FaeyRQQW9KaGV7YU1lWW1NI0VHK2ArfDNAWUA1d1RYUG0lbwp6YDVpbl85d09UU15a
cjtHTWdidFAxbD5XJTVCNjsyaFY0KCNCMDtzNUZsaW85QHM2XjBlMGxFYXs2KzZfR1I4OUUKekJD
SXJxSEFxSWlQfUNUVUBjIS12VC1DWE5lO01BKzFFb0UqSEpJP0IwVXNMV1JHREV6elNxQmpxSWNZ
USstYj5VCnoqbklNbzRUbXhpbSRgRHIwIzBlXjstKCE+YkFONihmaWF8d3ReNTlac1A1KUxofTA5
fEk1Rih0JUZiVHFyZHMmSAp6Jj9YKSg0PHZieDFgfEZzbTw2Y2VORyFwUl9ITj8oRXNycWJWcD5m
PU1TWFAjayszJV52bW5nIWNNSU9nbSokKyMKenRXPGBQeEkkYz03VjJSV1k5cnBFNm5zcEZPPnQl
Q2RfRmFFMzdzfkAtdyhkWEJqdGdyKj42bDVfUEskdkQmMDJaCnpTSHJ1d3JnQUBqS0lhVGhafFAj
ZG1HTjViSXB8eyljPCtuX3lzM1FfS2k8MkVwQUshS3pmIX4pTHN8Pyo0c1h8dQp6K0d0bWxpdSUh
TT5uKyl0b1MmVl5hWHx+dVIpK2NVQEskIWtDMGZLYk95akZWY3k4ZCFoWU0zZHRWKlgxKmlnPUsK
ej9aeVpBPGc2M3Y+ejxFQyRAX1RwYnB2c2t0UFN8WXRSLUM1SElGLW9ja3FraDlqcV9zQCFuJl41
TFQ2O19SKHI4CnphajtKKykkY1cxOyF6Xj9xZ0d+NHMrRkBeeD4/PmJnSlhqWE1lbiNIemteP24/
NHFLY21XREk/Mmc8aExlMVAjZAp6UmF6diNwP3IxYyk3K2NlJV9uRF8ka0tFTkJSKT1pMH0mJGNE
UWFTZHxFT21ubXZ6cUwkPklSTiZGfCpQO3ZtfjkKejF4aSg9c2NwYjghaTM+dUVraEEySVFCSmY0
MkB4U3MpWkI3YzIzUTd1Xj89di02VCZuZDcrJSsmWEhYX1J+YVRQCnp3aUBhK2xKRjt7O1N+VXFr
IU9IVDh9aSRjZWplWDZ6PGF2cGFiO0k4JEVJMitjJFh8MWt0QnxhYVoqd0FoVV5UXgp6WnRZPm5T
SitlQDtlfUY7Yj4kcX1xYXU2YkdJPHstaiteU0p1bmE7VkxNV0QyWXc1QmZ2d3tyc1FteW9jUyFV
WXwKekV5aC14VU1NQF82MkJ8LV5JJmxnQ0gxc1EoKDg5UjJwXmAyMD5IazZRSllEdSFUO0hfaylJ
Rm08a0hTTHlzaUNNCno9QX5NUkBEI25QJmlQNnVfRXFIKFBFNUQ2R31EMXNDfkN9emleO2l8eXBK
ZShQb3k1THpCVk8+N0dyNDxPREtpXwp6Z0JNSy1TRXw/WFFlNUtFKGZ8KD9fY0d1cldVODs5RWBx
Tnllc3sxb2p0NEw/ai0rXl5CUzxtaUJFSGtWZmk7OE0Kekk1KnFGJUM9YzcmOXV7UTE3Y041PldE
bDxjdUZvQW05QF9uaWxIWStHbX5eO0B+YytCc2E3OURwWndufCNOeHEyCnpMMVEqbTNPclVDO0Y8
QztMb09uMSV4SHJQKlUpIXZWKClITDBtM2tKZlVEfmp5KyYlKkFQfUp8Tkt3PzdlO2VNOwp6b3c9
Uk40X2k0aSk2SG91b2c1ISM+OWlAYjFnSzNPRzRFN35RQyMpa0hFVTczRishNVI3bERjQExxMXwj
UkE2bC0KeiZrTDB0SkU5VH1QYmh9MG5PXjM7Tj5yNktGaCY2dUZKND5gQkwkIylOLXBhKVAqVmhw
Jnsxezl3cDBxTkU5ZCM/CnpASyhCUCRlZElRXkhReEc3aTU/anEtaSQrODNfblBGeDdBX1FjcWJ1
MXNebHlCS0VpbnlQX2dIO31XfiNHUSZRPwp6WHxsSTU2b1goVnY3aElwcEA0e3khdCYrSSVlNWEw
cXh9aWgmWVJvJl98Vnxjc1VxVE8mP00wLUF1IXI9RnZnRkQKelpPUFdGV1BWUm89WEZ6Y3w5I2Fl
ajU+cj51aXJ9STVaWXdsP3RZZUg4c2ImZWJhcig7d1JQTChXZ19BTDJ9bUA8CnoxVlB+RCZGJFJ8
b0p3UTYwUzg0UGFuPlg7PCQ+KH5hOCE+SGRuRj4/QDl6WWBoPiNJT1pHRVloRE52WitxRUFxTwp6
QWgwYHZBYUVvRCt9RVo2PEdsMGZGI1d0Pi1sailGPDM4T2R6PTtATlhxcV5KTX0oa1g0aXlhUEYh
UCpxNHlwPlUKeiYmKEB5dzZ7Tk10VSo7OVZSM0N6SW9LTmNrJSsyX3Y0KDdXK3dhSHoreUphJWw/
UGFgWHUqVDJSMW1BYClhK0RqCnpHRmhtcSs4fnZSN2NYQTtLPVB3Uj0zX14/c0gmWWVYYTRVODFf
bjx2WDhKbVVPJUF8JHVlUTZwYF5sfV9IIVpJXgp6YDNuMEIqb3NLcChiNGZVWVlvdF9FMHw0UUoh
LTk/dEUyc0FScXViKSFqRHd8NTN1QjwjczQ9PGh0N0x2JDM4KSUKemA4OXBOeW12TkNoaT5zbmkr
P20kKV5PbVM4eHNWOXBFSVpUU04qJHBVc3lGMk9AQ2x8PDVibm1vSF9IWj9LYCU8CnpISThHJDd6
RyRWJDRlWj9eIUUxdFo4ezkpTlFlZkhjRHo+ISElKmZnU254TS05SypPbEtUKWA2UkZ3dHU3djle
eQp6eVo8fmZgX0NDb3JXSD1UK0dDRUhgUCs/flV3bWA1MythQm8tOSVvI2g9QFA9bCUtJEhXSE5a
P3NaSiRSU0lGS3gKelVkeTUwY2B9KWRvX3kqX1UjdzImMk1xWF5PWlpyMGo1fjRoKHdueiMtRkJf
MiMhUkV5ZmhHWE5BYDxrQG58dCV4CnpiPGJidHl8K3hUK1dUXkd6VzNnbiZ3VGJqZjQ7TWBiRGo0
LXBjeGlVQyVwR1E9PE11Vl92ejJ4X3l6QyVldmFRKgp6VVFQa0RrM1BCWHk2YzlQRW5qfGhUVSlr
ViVeJk1qK3FMSExOKGJ0a0JpcShtS0k2PH5BRys/a3RBX2dNZClhNVAKenlpKDVKMGBBOyUmaSYp
KCl+PnkhUjRoNFRqNSZuQVljZSZjX3Vna1I4R0Yqd0NEK3tsO1FpbUhEI01yaWdJN3hSCnpJdnt4
UDtSbjhkIXRvMH5tcmlHX19rSnt1KnJjSVFANFppX0dqYEYhPDNJbzRMbDFuUCNCViFqbURpejs8
aUhwYwp6cEstPDtLRCUrX2hRQlRyaSYkZnZIcDliKUspXlpnWjY9ZHA7bGYzcWY4dlFwfEdNaDgj
ZlJ7Pmhsfnt3d18/VGwKeipRe047X1MrKlBCV1YkZE1XaClXT2QqUUs+TlV0X3YqamdBbVIkRzEx
SFprY3h8KH1QXl97T353YT0rKWFSMkBICnotTGhpRSolJFRuXmdKaEcwYEkqWj5kQmZNUi1FQDwx
cnlBZUcyezZhRTYlOz57YD5Fe01POXpYPzJxTnVGODlXTwp6ejVWdnZAQjdRWXtQWGpBZCpeKy1D
RFM2X3RKUzJscVhVe3JxZSpre2ZoND08KXZJbUV2YEJDN3lsPnhkISskeU4Kel9TPGl9azdVayZN
WUJKYSpYcXEleiFfdEI+cyNOeGFfI2ZhLVooZm95c31hJENsN0AtNT8zRHdVTW83U3FPYXFXCnpN
Kypuc3FwSkFUZCNgfkFna2hTX3U4dzxfRUlEYl91WVl+I1U1UV9RYUJ1KFJjczxnbmJ3UDFxbkJ3
ZlMmd0pPXwp6JjZ9PHQmZ0N3eVI0UyZMSCRYJWpBfWFlVUxzSlZUclomIzI8JXVlXz5NVXo1Vkhq
I2hYVTh3KyY3MSF9QUEwQ18KekthSFhZNjJaVWIkbjA8a1YpTyFuUktVZC1VQWxiWiMmdVQ/NGkz
R2VSNFNid01YYDB4cTNXdyFsYmFGYiFBVWx5CnpoIzBLM3EqOCYpV1lTTXtiIz91MCFRdz9mez8p
KFZAbntye1RLVSZCPmkwan07YlQ4ZFI4QEtSeVJTTlYpMjgrMwp6PFp9NzUlSGA1WWFVMzElb1Mp
Jm5aJmh1c0VzUkJrKmNlbD0qNmE7fSlYc0R8XklTKHFgeT16YEZNNFJybnR5cyQKekx+MHt2KWJi
dmReQiNeajhIY0dKcWlRT1duNk1+eyYzQ0BEQ2M5PEpANiFWVm0xWWlNNEJnJEs+K019JHtAQk9m
CnpKclY/Z191aD9mPGA1KT5vSHJpVUhKUW5yaSkoWCFFejxCYjduQlpfKzh9fmBSJmBTNSZVIW16
UDNQfj5zR0Zubwpae3tpPUlkQEheXktxdnFKMDAyb3ZQREhMa1YxbUVCMihiVkYKCmxpdGVyYWwg
MApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTI1Ni5wbmcg
Yi9hcHAvcmVzL2VjbGlwc2UtbWFyay0yNTYucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4
IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmExMzVjNTRlMTQ5ZWFh
OTBiNjEwYTY5YzhmOWJmNmRlYjA2YzBlNjcKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDE1ODI1
CnpjbVg5X1dtc0VIKCs9KHFNVEAoO3lGPjkoK0AqTU40VWl4JDQjbkxJNmZmQFgjaTYqbnlJYzcz
eXgqVEJDKWJ8Ywp6Kl9uSDBYR2JENSlEJHBLTmwqYSowRVV2SHRRRyhPMU57akRLdF9hcThNKiFi
M0lLP3VEYWxHe2AoJk1VXyt9WF4Kel8/RW5EJmsxPi03YEl1Q3EhNWxvd1hZMkdCZCFwd0lQI21G
NjRmRSNCNjVkMTtpbW47QWQmJWRDYVFudnJHQEVACnpxZWJUbGxebnlSPFQ4c1ViY3wtSlBHQjJw
Vj1abUNeTHViRlRpPjhLU1QqX2V0I2EtNzlDJmhkVXtKWnpXYXVybAp6O29OYUlafEVFfXZ+JVNu
TioqX35WQExIKk1JeSpmOXd2TlBNRk1NKk90dXVxbS1oX2VBM2g+dzk8fiUrdUhGdXgKelB7dzEo
NGNRbW8haUQ3VUBJM3I3bCZiMCRkJSRzVjx+Sj5ZNGdXZ29DK3lZNzN1JlV6ZTx5ZD8hO1ZYfWJa
d3B8CnpeTTZkTFBpekB5SlV7MV9TRmlCSVNVSmt+UEUxKkk2RTkzcDw1Y1JgNihqIVpSVXNPMzZe
Jm96OCk7enRaeXJ1MAp6NEQkKE9EY09IJUlQM2k5MHpwKTwrbD8waUN4JlI+LXNqZkp6MFFeY2x2
fWpMc3wtcTYlWExeaj9KJUMjeH5AODkKeipHRE9hRD44PHN4OUQhQ1MyOEJhbGAxazM1TFpVaEJP
fkB3a2AzP2tiaEpwWCV1REJBelY/MWMlVzF4eGk0eTRBCnpWez1+bTclRFh+PXloN25gM29tbCVV
Jig1JDU4O19pNj5CKysyU2pFdEwlYH5ASDgyQ1R+e3RwMGxLQW8zd1MlZwp6I0tPIXJGNGZqbXhi
cComNEpgQHwzaVUrRCRqV35NQVA9d2QqaVVMbz1GOCpmQ3l9KCs2LV50TTJaSmUqayRLV0IKeiNC
KjJ2UDB1fVBPdCRCRW1RKUp1UkgrQnZDdVlgajV4Q095e0JBK24tS1MrdllhbT44PE8yXlhVSTNE
RzFXJVVWCno1NSsrQl9vWEVROW1VUUVJaUhqVnckdFlmKnpufFY8XyhOP1ZzcigrRCtoa19TMkp0
dSlSe2N9TVlVYC1mclZVdgp6IXdhNCN1fHppfk4qTWltOyZnVHZIKWhFRDkqZF9neEhTWk5AJj51
Kl4welhvUU1SMSgqNn1qJXQ7a09NKVVpc2sKenJ8ITd0TFJOe3ItO1FIWHlkNzV7S2VvMkVffnpg
dCRaM1l3dkUjSTlzV0l7S0VBZ3pEQiRsKWdJaVJjMmF2P2JKCnpuaUtzVC0jPEooXzRrPEdyanJu
VUZLQnB3RS1gKGI0Sihfby0/NzF7OCQ8cFlyOGtJVERxREwyVHpJS2t7Uyl9cwp6X1ZSR3JRZnRJ
flZCZiYzYnAyKENpe3sxQTdtX25DdVNrUHshKTN0NG96RDduRllWTTVqTD8raGMwSUUzYz5WdEgK
ekFmY2w/SCM7OypMWChDOFlhZ2wqdURFYVB7UWg+cnw4NE9XKGtUWEhYSEZnTWNOTnZTXzR9R3pI
c21mam1AYjc0Cnp6bCg8T2ZpPjtuQnZHZ0dgSzIwa0xoPTVFWCR+MWh6VW5SQWYqIS1uRGtwZEg7
SGlVaiF8bHk3UDdJPlo9NngzRQp6VEJfWUUjR3VTbExQV1JANm1eZT93K28mKFhsUThRYV8pSjNu
YV4/XmUxQVJ3Sj8ocTU+fllpNWI2UTY5cnNKansKeldedyZjNHx2QG5kXzUtZ2hRd3ZCRz98SlN2
MkpKS1JXQHVZME0qXk12Zk9QZUolSz14czhuYEgrJFdCZit1N1d3CnpvNV4+Mlc5NilQK2Y3XjI/
JjA0WSlXKiZ9Y1BBM0J4M2xWUlM1d18pUkkhJVIxfGtWaEBrNnJ9ZihJMy0hNVdeUAp6LWR9V2J7
Izx8QmNwUW0/UjRBMGZlNUU4MiVzfU1pSl9nK2VQO3tRXmRQOXlteXc0WVh5XjZHPz81dlp1QX0o
ITIKeip8eDcjWGlCJGJgeT1yWkNsQj1OZVdwVlFQMkh9LS1kfip8JE5VYSktKntjPihZcGFVdmMw
NHhGRillRzF6T0F3CnpBdzQ2eCU/cChgK2BJZCRtczN2JiswXnFKdWRVc0VSdWtKKD98U1JJZlRV
fE5RX3FjZ05DWHZmUDBvWWdvK2Qkbwp6VzYyeUh1ZlJDKitlNGZDKTF5JW8hT0RpN3NFeWZIIz54
aVEmRkFONVpZK3UwT1BlYWNrLWVyPndeMjQwI2VSdmkKej1kNXA2I05GJCEpOU5OM0MhcDdaZyhs
fDxGfV9HQGlEUkpYM3Z9STc2clFnbUdqeWNZSzZma3x0flozPUl0a08pCno3MHJhQGVtOEtQaSNk
WjlKUmpFR0ZMYj54bWlaPGxedyFjJmZUQjQ4RjU0QTQlZEMzIUV8YmVxXlBNaiY/fml2Tgp6X2p4
ciNIOFd2IU50bk96TEJKSyNqYU82aCpLcyh8JUVrc15aPD1pRyZgdnImUEVCfVBqXz1LfU98e3My
ITI1eTcKeiMmYnJAai01VkxubXdFYjdgMU98JkYyaWAwKDElUzFjYEJTZzY5cUpaRjRzdGRAeG0o
Y1k3bjtUZyUlRkN4am09CnpCcD8lNW9lI1IyX15LQF5EJUpeN0Z3NXxSOVk9UXlVQ3dLN0MhTUBn
eCMxS1hmcEdfVU4ofXxjXldYQTc7SU1oSQp6KkhpJSRWQmJwIXJBemRNbm4lQSU1c2E7NmJpZklR
YktwV042OFpCPFBmJWI8T3dLVz1aXnc/Vm88RX19MjxCbikKej9GOTE3Q2VWSWxKVi1SayRfb2hU
P0w1ZjcyeigyOXNDPkVaP2dxfitLZCQrYVBzU0o0JiliYHNOc19sLV5sKV9qCnpIdiYjc1JlI19W
aHFQTiZWQ0AkU2FDWWNoPiphIz9gcHE0cnZyfm9TOShWOzV7VHdvNUZ1VHlpOzY5b0M7UXYrfQp6
N2pQYHl6MjJ7P1BfYVFuUD5RJX0/N2h9LStTUFItKTN5NUNpJmllelp9VEZTVzAjai1ZMFZQNV5x
UzVBSWtNSUAKel9NR0Y3e3Awd2syeFlqa1klaHpjK21tOzA7QnskdnA8dTFELTQ1RWJTazkzbzYq
V0lIdGI0QiMhfFUjV191RG13CnotT3tDYkg5RENSYT13YiREbkBuTko8WClWYHxJNEBAMHszSWxV
TVN8VFN+Xzc1ZTJPUVRUZzcmb20mfFc1KkU+fQp6V0lkOUImNF90MDU3U3RJa0ZfeXomZDtfaitI
UThmKWxoK2N0KUZreldeUmNnNiRtKDBoZGlwWUJkbl4xbUcxU3EKeiN0eW1+V14pS1YxZEV2Wksp
Jjw5eVZBeDhpSUdvRU9YN35SbmJ2R2l3PUp4X1hjaGdfKmJ4YzRiX25pIUVjdD5CCnplfndXZGMm
NlplelV1amR6QH1rLTVENVooTDU4VSkrdWR0bkJITn5ZaT84fTY5QSN8QyQmb1pVNy0+OHxjQTNO
Xwp6N3QrciNGTWp1TG1WI0I2UypeJCtrVVp8LWtjIXFKV0tWZk8+fjhuLWBgS3JUbXchPTtJJmhk
dXZ0ZVk3UUhxWkAKemg5S1hZJjJCU3NHMDFUQjE1bEpGTGAhKURgVjZfeC1TRGFsQ3YlZXBGLW4q
TFVROXZuIz9GZzFsQEgwVF96VzBnCnp1YV81QlY/P09kK2wqYyFqZHp7TFladnx4QypUV0w8aDQq
dGVwcC1IPm9KTUAlUiZtSzReZlo5OCQwUEFaN1lsUAp6JGlCWFgjUURxMHkzdXxQM1cqJVU4VVhC
bTZvOCFIMGxuX0JGQV9vP3tUcChKY3Rra29nJStBaEY2MXUhWiR6cVMKelJCXzEwdSpqb2ZjOygr
dWkoQGp5SEpEUmg1MX50USpVeEopQztNemlGbzt1OT50b0txVi01bSV5STxDeWEmKnllCnpBOTYx
JEBjdVc5S2V8cnNgUT4/YF5DSjdnN2E7PE1PaylHZDV9K25LVz1ZRTUtZSR5SjdAYWQrSHpyQ3gr
MFImTAp6Kyt5X2c/RllzTVp1fXQzdWFgWVpzRjBzYmIwTSE4b3lLanw7WDZjb3IyYW1sYitgel52
NmxDej5qNDkle2BYTk8KenVHcEkwRnNVI05eUSllZFZnZjEzZCN1WChTNmZ7fUpjZ1EjKX11dms9
ZG89VWZyVF5Bbnl4UWN1PUlRWW40KWZkCnpobjBtS1UmelZ2OXJGbXpuKXYmeyl0RjlfXnFmNmtx
d350V3UrMTRebDIoIVNDPzJaISU7bn4rOXBjczcxP1lXdwp6WWIqYkFIWGd7TGRXaCNgZFAwYnBv
WlJGbE5hRDVJZk4xVkk2ZjVWSFIzSV8qVTB0bF4+RGEhZ0VKPGZKUCVWOUUKek42ME5ucl9yRll0
UiFka204NkpJO05xWUxqfDNkZm1+Ymk0V3dWZztYLTgxNDQtX31WdiFiYjckezR2PT1sKVBNCnp1
fW42aXlkTF9USnB+WWRKNXB4PnxJaCEzPktvdW09I2AqPUsraC1tdiNkZzFCaGowditfIUNKcVBi
Z2Z0Z09Sewp6T3leRjA3fTRrOUs5MTRfYCtWaFA+PSkkam9wZSZocU5NV3E8OC04WHV9ZlUmJn4r
OTV2TTNhRXhWTl9oY31ANlAKejU2Km4zKChvSk0maz4pVmgpbHZHVnROdGVhbE9ZQ0hnZ0lKZE5l
a0Mqam93azY/STF+TkB8P3Y3VWNCdEF7IylVCnpBQXdWMEs2TTdZdFZFUzFBS1Rsb0p6aGZMPC1x
OGBtYU9ifipWSzdlYDhgcTBtSUJWIT5jI25lYXolSHAoMnJGNwp6Mj9gamNCJn5taTIxQ15zazlT
SCg4eEpAKXZkTGk3Sm08LSgjNm1fYiM9WlYoZlJDczwjJjwzRE5RO2dfPzspbWMKemp4QEBJKy03
X3xzVEx6NF9FXl44ZDt5WiVGO1I+PDNXc05FU1pYRXktJlk0eHVkbWA9bVNlZCZgcTcoP1ItTyQ7
CnohdDhjT2JyJi05K3lGdkVzdkBsO3E2N2J7NElAZFdXVzY+bSUzIT02e1V+PSNobVo0ZzQ5Y1gx
KH1RYCooc3R2cgp6NGFVXkw7aFJ9OVMpVnsqYSkzZlUxQllsWCM+IzFCVXopVCVKc1lNfT1Gd25F
JUdtN3lvdHR9cDBEQHdOMzZfY2YKemBTKHc8e2tuaCZZMjJRMnRFTHA+M0U9YGs+YyRWMj11JClw
PDltbjQ9ZngjJGlCKG5YIXBrQ3U9WkFUUGxgKyFkCno+VzF0Sns5YHsrZGkkfHdIakx3RjNLJEVG
RHooYVZoP3JBfG1AIz1vampVWDNlK0M3Pyt9fm5wUk8qeH1hR0NvRQp6RHR6KlpNTzA+QHF0LTUp
RTdCQz5SeFkpb0NCajJmeGooWXJWTGJsOGthc0JwdSEre1pfYC19YU82UGojbXhMXmkKekVROShU
bVZ3TSZiVHBOSHVpMUszRm1RPmhCQ1FMSSY7cENiPExrI1FiUGFwd21pfTktJGVAeTJnU249fSRT
VGpeCnpTR0E1Y1hXM2BHUGFwSEUyPFh2QVowYkROXjtIeXhsJnBBJlMlWi1VNDtWanVUREA2JFgr
RnNUQktMNy1vQTZmUQp6Z0Y0MUFsVy1YcDE8enNLQjwoSH5xSXRqYHtXaGJ8Y1QwPVE+Xj1GZnNH
SElHKmgleDAodkVDJWVqaGNicnE/SHEKejc7PVY+Y1hadDVCZyp5YXU2PChkRjBBdyRDRyplQ24m
SUV6KDhiJTVSWWUtejVBRiNVbns1fn0hPTlKNCRnQipsCnopQTl7c1RJKnlkYTdEdFIkdkRlI28y
RH1+TlR1PTJxS2g+Y3IpSzk9KXg4REs0a2l5NF9lUG9LJUYqWms/JFNvZAp6bzdXSDhYM0h9JF5U
OWhLQGBPPCR5T01jVm58NnQjQzZTT2diREcyZERReXl7cFlWRVE+S0BCV2w0ZU5gPz0lYEAKek4/
VFlPSyhOVWt8MT5FWTZ7VGp9Y097MFZoaSEhdFg/O2xnIXpSfmU9LXozeV45fHZBPHEwPEt7Pjtx
eW94TzJrCnpeamAlK08mKl9aOz1+QG9HNyZscSV1ZUY+ODJKMmZ2akg1MWwpdjQ4dyYobEozT0Yo
WUIqcjQtVjZhd1kjdnxnJAp6NFE5UjR3P1M7JTgyT092aCgyT1R4K2spZz42SH55d09jUj4yNHlz
TE9rI0tEIT9ZWXJqRnZ7fUxoMWE4aHF1Uk4KeiFtUWQzMFl+ZjQpTkVKJkFANH5CLU85ZEx2Q0hB
dns8aXgrekxWX1ZSLVZ6Sns/SzJzSHhadklRQ1RhUkRVIXM8CnpLaUtlZ3k7V1RGMDItPjctLWA/
ZD1KTjdQbHRmJlNCUlgoZCRQSSE4XjFSbnxgNiRRQFJGKCtgTEYoaz5WKHxTZgp6b1k0Zyt5NFVv
KTtEbTQtcyQySiMhak5lYW9QNTNWJWBEM351RikzMXZuYiFRREFWMnlPUCF5a15BVX09MT59WmQK
enEob209JXB8JUYxNSRGJmVSNCMrb1VET0ckTytNWmk3UTdrTTF3YlJpeD90JFh8UHdyJjBTbXk5
flcoVkJRIz07Cnp3Rnp1X15TUGAtZW9oaDkmbWJBYS1qWG98aGxncXNrKztNQWwxUnlWNmQ4SFdL
TiNqUnUjX1dXTyt+NVNGMkt7aAp6KiZuVW1QOWApT2V3OVlAYV5PZ0FCYlU2eHBxZUFXeDtAKSRU
Z2xsREd0OU5QKFZ6Jlk7ZWAyNERPPm1fVmRCWmsKej51aWxBZjwmPHBqP14tVm5sI2koUldYbEdY
fFRgS19PbyhFQ3QqX1EhVT4rKi1vcFooJWtGLTxMRytBWlhwbk14CnpKRXFUX3s9cnBqeHlpXyRP
fEFsRTxsb3tGVnhOOFM8eHgqPHZZV2EhIT4xdmVnYDMxbV8wTUhycmItVjlQI01eWAp6dytAQ0c8
flpSUHErM2kxM3khVCtlIyNAanszWSM0YS0rbX1reXxaUHcxa0tsUnBKNzRhfDFDaUlgOzN7QTFt
RFIKejNgIW1zPCZQJkZpXnxDaGdEQ0ZBaGY/eyl5UiRfYSY3NCZEJEVJPmRjNUZqJC0zPUtyY3gr
YDZeMHtfSHE2TEJyCnohdig7RlZDdGk0eSRJPzh6d0ZkKDR7aSNkR3RjKFotbCNtQ2xFPzFDZjRO
SzJLLVMkNUBjWmY9RWE8S08/YlVJbQp6RT9uP2gzZWdFJj9XP0plMU9hYX1XaTN+SDFDOUpvRXxA
QGomSkd7QXc2RD14e20zJFZ4RnhyJnlFNF9qQUQjVU4KeiR8O2VWQjx8dG9SM3tUaz1oOVFoWnhw
UXNLPStGc3tzJjcjSFM9MS1SKz9hZm88PVl0Ml9GTG4mMlI/VEthRmxgCnpGdGVMPzMmU2tLSHV8
fm1qPk1fcEBnbWh8O0g5YzlDfShkLTE5K0BvN1UkSDlmaipsISR3TEoxZTtuV1RHPXVsUgp6cWdW
TThpXm1xdiUrUkI+IVc8cTclNSZCeU4/SG1sNFBfdXJubmdRfDNZLUN4cXdzTjskQ0MwbE5WYjQw
PGRiUlMKejhITHFqVl9TYChIP0ZPIUU+SntiPHNMbSgmbHs8MD9HODRiUXBTKXpqOXtVNW48N2VD
S3A/cjAjRk8raHZiJllhCnpybTdrMDYoWipWeXo9TEk5M2Q5fT1MRnFyaChLcUElTjRCaGkyemxj
TGAwPnctNlNGN084OSU9eVZMOTNrQyV2bgp6PjcwPzBVZ3U2Qk5QS310e3sqKS0lViVWcy1NJExi
Pj5PJCtWS31KWVhDZmc2JCNvKEpIeGt0eUBvMSpMMWIxODEKemVOQWd7RF8rfnQxI0tONk5NNm5k
MGJNUTBLeU9EWCFtbElEdnE+V3pyTjZrPzcjQUc9UlRoYVEtbjBaVW5Nb2pTCnp2Y089ZmFBV2RH
TCRyIXxNUmFtVVl9VEtGOUBZQSlQYV84fFNrQUpfKSsrU0JYb2ZGaVJJelVJVXFEaXpOQFlYKAp6
eFNLNXFSbFlWWjJEOzl0ZFRZMWM7SGVBQVJnUmExJVV3aURBRk0/UlJPfXVgeGREQT83WFBqN14y
YWBiRWBxa2EKenNPYDc3LXJ8RWw2QTl5QVliTElTOV5TSUxSeGJedTMrPlEmIzgpTCROYSZtZnsw
TDRHPTVWYEJPWW1GKVp8Qn5xCnpuKzt0UXdDTlhFMUQrfTBeJiQ2ajMrX3YjQ0pMJm9TMEI1KzZN
OSp8c1QkSWM9R2NHVmMpMyU1Smh+eGV2YnhUQAp6RVFIfGFmdDhKaGdjWUU0LWU8R2laJUpOK09+
UjFUMmhFYE9eRyFJT1kma2dsdSN8TGU/YGIwPHhwZXUkQTVyeEYKeiRjVXh2K3dUY25jUlJySEhH
OXhtdUtSOVBieH1SVEIkTk1wZy1EbFVtVkJSNm9XbilZMlRsK2p3JipDJS1sKWNtCno4MXlkVVk7
I3Bhc0l9QXk9ZTwjPSpySDVFKUVhe1JhSkR7eShlKjRvTnF9VEt4Z1V7QF47OGxmWih7Yl9xPStW
dwp6aEk3emFLd1BtTWhLeVJDPkE4VHArU3M0V3dCX3BJdT0mdTQqfDJmQDlFY3VhVk5yTzUkLVA9
Kmk2I0khZXNRYyQKenY3Tk4pY3F+YUQ5UT9pSV94KVphUl4hRGxENVIoOU1JMWdGeCtCa1RnOFE8
TnQ/fkVvX2heJigqUVh5PUpLYHY3Cno9eWF3JmV0b3BRYUJ0c0EtNig5KkRQfGs/eHVUIztYbV5+
XnJFOzVac3VNd201PHdkQGYyOzdOJUczYFFeZFJFUQp6Jn4mZC1IcldBd0lWJWp1dmp7eWBOb24p
YHdsXnBlQzwpUm9HP1VJZiU3dUUqNn1zV3MqPzthQFoxOX17TkskI2MKejBlOD8lKUYhK0tvTW9j
Uz1TVnE/SGZxMGA1cUthSGxQYDlKa2Jkaj5aYWp6VCVLOyZsaU43VCFzP3otPGo9UlhRCno0IzFT
bSEtdnoxVklnRWN4VHgrN1RLI1Q9Y1h6SWc4O0Y/fDlMejZqTzB2ITc0Rk5rUFEjJUNfek47anJm
aTBWTAp6ZExuTj1hSDZhTz9uNSpxXjk4cG5zLUZEIUF7UzwjVypZdjV7aXh+ayNqcDc9OVZ5QjVx
Y0Q3PDw3OHQ9dXNRUmQKemElYUBmMV9reElYUktEb0BvWjR5Q1dhWXF5X1VBKSp0SW0wWH4hVn0+
bzZmPipQbzktc08lYmsqa1ZsSkYhdXAzCnorTEE/QEJ0OE1ANCtiUGdISSM5ZCh4QzYmen5GNUhW
UG9AYWBjejxRMWZgdUd1Y0omUk8yeUVLUGJ2Q2V5I1ByKwp6eTNIeiFMXjJPPDsjUzktYXtaRFQ5
VmN2Rlk/emRwPnxIfnJsfWYwPj5jX3JHWntTXkcrcVA+ZUdid0JLPWpNN2QKenJMdXtuPGw3P0BE
dW1FRXVvO2BqUWl5ZT5YSHY5QWBLSmpMR19LP3ZES04+PW0wOHFOfEk0cSZRTX4jTD9tJGttCnpf
K3pzM2spZGtLeE9+RUBTP0FOc0xTazA/MzdKMExySTgmTll5RSt6TFVGbHRrWUAhYTtqRGp4MFlU
dyVDMX1Wagp6c2VvdWYkWSExVG9BYDt2QGpTT002T3FzcFpYckhKO0FXflEmI0huVWY4MVVFZHNi
ZE5LQzElWGEkUVMmcElTIWQKem81UHw0Zk43LU5iVH1PPkFAWUZSK1EtVjVTdyZTc3NMVUVXITh5
OVhGVl9FJTxEMW5PUDU1cGshejNwYmAmLVZfCnpsbWFYTyM7TW9CRkJHTl9LOWUoUXcteEhzV0R+
O1RBbjVXYDhhLXp+eXVWQ1cydmpgOyZXOy09NzJ3WHpLNzs0Xgp6VlZuVzlSQnRaJFMySj4+UGtv
NyMjZF82cjQ5bEB1MzIybklfXz08TVlGPGZVQk5eUWNrYlRBJjxzTjEyIWh5UkIKemo2OXNAQ0lx
VG5AdFhtd1dGPWY2UDA2NyZZWUxSQ2huJHNSP182TShIMnVsSyVZb3BDSGYxc1M1U3VaQClIUGRB
Cnp5JDw/KCszUUZLVEM+Pn1IPUBJclhlfUNzWkIlSl87YEBKcHtVSjVMc1ktRHhVT2R6PypCRmg9
XyU0QzloQ3NrdQp6cVgmR1JydUtIKT1lR1R1b0gtbEtTZWpkK0Q+eStVQy1kUDJldT1UZEhzQTxD
O0NQcTUyQlhFdj8qWXc+KTlmUH4Kems2WEpEPCErb3BUQENNOHRRPEc7Q15za2NgUHUwJXM9JU5N
RT5TKy0/JGxnODEpfFctUyhVbmN7NGI8OWgmX3JQCnozbzV5bkxBPEw4SU4rYUZaKClWUHNqTWJG
Y1NEdU1Mfn5Rb2tyWVpeaUY9O2l8MUg9IUxySUpgbVR1V0JoTk5KKgp6VjgjfWtoeDY4ZSYxTUhj
M0QoU2JzMW5idDtOTk13aHtic3klb200VDlWd3VNT29jJklCZEpSPFQtZnd4cnhPc1QKel56TU82
MzZ7UTMzNkBMKWNVRFVybUdeaUYpJipIOGszJUtvKShVcHYoSEMzYHt7KFVEYFIhVz5mPkwrXjRB
U3pYCno+dmhqNih2PnlyKi1SK04hUW5zV1U8e1JJVWJfelgmN3Z2WkdQNEk4JT99SnQrYGtGSURJ
VU1rbkFCYnB2RnExbwp6UyFrPVhLIX1MOXZJU0E0eCp1e2poVFVjMGNLem99S2JkNzBvXlBqPVZM
QSVJVmRGTXxQRWJtNGtMeHE0c1VXPUEKelA7fT8lPzdmUyYhQm9EYi0/RGBTR3NZU20tK2FxbzFF
WFJqP1MkNj5LZSs4Qj5AWF5Mc3ViPlgxZjxVa3dmM1MqCnpFTTF7dkopRl4hSnw9QUZOYWNxUTtE
fiUkPFBEMkBUbXYmRGpOTjRJd2VCJVlYQXtyJUQ5QlU1REgkR3QwdzU/Qgp6cX4tPWtZfVd2M3RE
Vz5mVCFvbUZtUjE0ez8tYVR4ZWlQNUp0QUU9KnlPYiFET2ZMayh3JlUmdFFofCtjTGEtWmEKek8/
dykmQSl5Wk9sTzElLUZhJnU/I3JSKSotPndxe1lkU0o1QE1EVm9OTTdFdTN3YVdFYlZWQWM0OVZ7
K0l9UHY7CnokWjhydz18aEViYTR3VTx6ZlBXIWk3bEo9KTlffjljTCQ/aVkwYk0zc2NvSyk/cnBI
K1F+bnxYMmw0ZExjIXZQWgp6NShkMmhlMnUxKm9mWTkwdnp+LV9SU0FxTTJMN1hBK3JJZzBQVlkw
bkFXQ0VkZGkyfDkxfGdAI2hXPipNVHR1Xl4KelZuPDdNIX1lZj1DNFdEYy1OaCsyN2clNHMlU15H
QUM0RDl3YGBPI2BpKiZMdUd2Z2E/YmJDSyZQKkhBfXZ+TXA7CnpDd2tDPjF7N1FNakBEfXwoeklQ
TSEyNSlCQSVyYz4+USRXRVVxNT9gMnYqKnw4QCljdTVePzdHTGR3dHZGezZFQQp6MEJkc1VtQWdL
aVNOXjgjZSU+fHhSSCZoTXZoUmE+KzBFTWwhPCFNOUNFPzc0Iy1zRW9ROU1tUzlzSEIqcy1afTwK
enxNTEtoYm4tWCE+dn49X3F1RlpNdnY7ZEpkVk1yKU0pc18ocS1jSjAxPHpwS1IlaWRsZDZic3V0
c1kyclFofjVnCnoqV0gzbDJHWEFvbWl3MVYobnZuYnN1VkUmKUU/aTdDb2MzPSNzPzJ3d15MbzZy
fjJVOVQjb1IyYzM/NkJuSFQ+ZAp6PTdBVVdRfSROYHQxMSYpPm52TCN5IXs7VHZeS0QhVD1odU4+
MjJSRyhrPH1TOTZ5XzRzWDc0K245QW5lPFFISXQKemAjNk9MWSp2e2l3SUpuNTFeNWIlPG04ZXBK
QUVLNVBRTzQmcDFOR0UmRlN9amNHUmRwI1NZPl5jcDh6XlZ+UHE+Cnp2YWkoQWQzLUI+PC1GJHEh
WV94dD1WKWRyeH1fYkdvI0FePlZoREpgbis7NVZmWTE4MzlAQWp5NEg7MntvdWFaegp6K0UxVU1C
cHxpQ1dPKHgldzlJX3UtNzRrLVBzOFRAIzlMfG0tNjl4SlFARXx9MXdhaiZhVipEPTdAfGNIQlBY
aH0KejVMS1c3ISVmI0Mwd05idHFIMjlwYzJXRFFZUis+NWZoc1N+O0wycCZkZFpgYjE4a2gwPjJA
RyYjeXBeMmRFeXB8CnpKU2pEI2t4b2NRZjl+bUhOSmgrKDJ+KHEkc24yOWtKbEEqMmFycyNpZmFH
YXRRNDdEQGE8cyFNT3JjNGhoVjErZAp6I2dgc2tmWng0NWxXZkw9VXxLT0I7Q3J2SzElU0ErIyZR
JXl7QU5IU3lHO35yRkFqVURxUjM7NHJ8SkwqIzxtfmQKekhpOGtUSnAjMnFsND9xPTJfWVVnNnN6
OSlWQ01kRVQyK3lWSXg0aW8kYTgmRVA9YDlnUTMrU3U2bVF4RF5GbmBKCnp2cGtUJFpEWHl0SH1o
VnxLe3JOOGB9UVVoOyE+WGp0bVplUHt1THZZVkFwLTk/azhIdllhcWB7cXE+Qno5ZT98WAp6Ui1a
MzJNbjVEKiRKZSM5MDtaeD0wKEMxXjxpaHlTbzFmNDNIOUNIdGBxaXk0b3N4ND5rXm51VUstWVEp
dnw8IWYKeko5Y2JQaiErVWAhdHdkbEZVVzI/fEFRcW1nKn4qQmc4bXo3I2wtbSFtODleNj0hIXVJ
PzdeaExCeUhedkpIPi1DCnpFK1dXVjJfcUA5TkhYK0BOQ3x2XikwUHhXME5BY1czSEQpfVl1NnB2
VyRUZTBeY2MkeWsrSXgpaWQoT1ZkbkFwVQp6UkBPdzhXKnpZYCF8WEplXnh6QG4xN31EZz9ic2I3
Y1NtUzZkRmBxYUYrbExxTEskMG9SVjxDQ2M4SyUya3t4eFIKek0zQig8dlU9dDYwMWBQQSUzKS1S
aiE8aS1edz0oYTJCKmVHYD1BXktQeyQ2cCowWTxMVWQ3JFFQNXNFPjZqQTZDCnpveER2VFc3KCk2
cFE9YTlPUVFaQEU/QzlqJX1XQSVfSiFiM2M5P2xRITRjKlhEY0o5eHU3eTcxcmQ4MDRqJmlLeQp6
bSlfM1BkXlJXYys+Qi1DcGZ7fWpELXx1aGklSiM3OzZIUjkoVnlYNlQtakw7eGBSRVU3eUJeKXVw
WEk9Vz5PPXAKemRLWmBjRTJYV0hLXlZzZjBkbG42di1vOT5pfl5yKVphNVNmbUgze2l5dzk5NTI2
LUwqPktWNmp7azdhMU82JX02CnpvLXBMPGE3Q0YtPmF3I1dVfT5DKSFYXlc/aXpWSUhCZTttSEtk
aWNEbilLP3NXYjNlXjcpYkBDPlhHJmFhTTx2TAp6XyR2PDkkTWZfWTk+RDxzI2FpT3VkMm5pdUMl
cTlqKitGOEdac3xtR158JndAaXZZP2M8YlFeMm5oaGlJWDVYQnoKejcpPEY3a2tXbzh1Qyg/bihj
YzNuXlFqbiVHWDFRNytoS0dvWD5HandUYzxfRkJ3RUN4Xmg8YklQNyF+K25JN2JJCnojan5CdiYo
az5rU19OQVdmZE5STT5HR05AYkY1QkFreHprckFuMVpFPEtNNUNLJlZGfHdtNHZjNitAQmRkb1p0
bwp6aVhoPy05fDdUd3cleU9AOEIwdCp2TXckfnhPaks2TF5jPWN7M3UwTWFoeVg8V2RUb08mZUh7
ZSl4LXVZTFhxSjEKeihGfj5oKFI1S2FpV2g/WF85MUdtKFA5VHQ0T2o3IWd6c2JeNCZAWG9BNm5I
O1heWk9FRkdTOCtiI0c+cUR3P0leCnp3JDg7fEA+aWtmPHcwQGB7XnhzU0xRanN0RyhjT2YhMShN
ZFZ9ZTBLZFNgNWpFPHt4diFHK28/Vy1FUzY0MUteZQp6SXojYV8wP3N4TVMwUVZtPHRLdWo3JnMy
YkFoalEkR0smUVZDSCFaJm1gMjlCTEF1U1Q0RSRmKGtITkZme1FYJEwKenhXOSNsVyptY31mR05L
aTVQKWQ1YWAwMmpefEU0JHBHZzY8SGdNMmMkJSQ0fil6YSVmTkRmQUhUQH1kO0dZJXgqCnpxIXp3
JW5Yez0qP0lLOEcoMVZoQiNPJV8wR1g8TlMmNS15fmNWUzNjRE9kdCFJVGA9Kj97QTtldX0oQi1L
RkNTMgp6TWQrWWImU0ZATnlKZW0+a2VfR3I+YmcreHMmPT5iN0B3QnVhdyo1R1ZFdD90NzxvXlk5
NT5MfVUyZ0dUPWVEcVUKenZ6THNiMCZBa0t6MExwKHgmaVJXNFBPbF9kcVpUfWg4K19CITleMnZA
c2YpeTN0VFJMWEY7aH5RWHt5cE4wMHBWCnpYdyVqQTY+c18kNW51KWAoK2d+fEF5d1FGbTRzQFdo
amxsQWo/fnFCZnFLRj1TN0gzZyU4VnNIeHp+MSRgcX4pPgp6P2hvfkQhYDF9az82ZzdgU3lBTnVs
bnlkQFpOQDVYXks8TFIwS0BqSG83cEVFVGxZO1FKeyZmNDBJWEkwKXs9N2sKejMhLTx0SztkVypj
UUhOWDZZI24/WCoreUBUYDwtWEVuQi0lOWckeGBYKnh7K29ScUYrcHltbXk0ZFokNmN2Vz92Cnpm
UWp+ekJhbTFMbFVhIXpzTTZTZDdacDQ3WSRyTEpoPnFMUyskQXZVI0JEJGk+cTNwTShwfi1CYmZm
Slg/cjUybAp6VDZLNTIjLXM+Q0t6ZFU9eikmbD1wdGghdGtudXJrbXtCSGc5MHA8NXV8NTw9QDtk
KkEhS2A4UldpSFQhdklKdi0KelBVUVhKMThBcHp2bil6S2BDQGxHTnsja2ZRKnlSSWNLUkRQK1ko
WWlzVztzRE18YyRKLX1vQ0ZQaDxnaUJ0MGc0CnpGeH0wZWQ5WUJLSWVrKkkoQzI0RHg4SH1qUlF7
az0hZnJ8alBaMyFkO2hqTjVudzJDK1dkVzJsdnRSe2Y7R143egp6JmF6NTRLfndlUFhaKjtyNyRO
YjZpTUV0JT4zQGY7eUxLZT8hUWFodVlOUERkX2Nzen1yNGN6MWdXajhWPzNucTwKemlLbUFtS3gw
d2AyMjRNayMjVFAkNHJqejdqNzw2dnJyansrdkJ6NFEyVDN9VlNyfUBldnByO0ZCUmZmVGNnVHBl
CnowTF9yaj1vSmdWaGA/Oz4zVjNScEJZdTV8JnI9NG0/P2dfaTB5dWk2Vnl3UWRaeXM2dTFwaHN7
WGImQVEhdm1NSwp6TCglQmBZeWIzY09DM2wtI2pkcDh7cXZOdS1FWkJrRGptZVMqTD9uZkpaOD10
UypBQko/RVNmNE9TJGh8PU5GeCsKekghZWN4RCVhSEw4UWUtRFc0OV9SV1pHT1J7Ry0zZTA1UihY
eyFEaThJe1pGSyVvTkQ9PVQ0fDJMKnxLR0V0fk1PCnpPY1YpIyk2TUVweDYkYnJacHFFX05JJUMm
WF4lQndvJCRnKVNXMGU9Mm0xQU1aVjJzeGpNMDIhOGJjd3Fyej19Vwp6P0pSQ0c3Pl9OU2MydDZA
aStwKjY0Vlk2WGdFWjJVaFpvKzNMayE8N05wPn49byNBcEJBJntBS1ZUekhOZUxKfDwKei07TGYo
I3drM0RvOTJ6ZT1EOVdOKyN6dUw7VEhtTnAlWk07KH42ViZsd21iKFdnaTNYZHZoKjkxK29CfU01
Zzc8CnpOOV9Rbz9rd24/aHkmJXVYdF49WEd9KVczTF9RNyYjND5+WEZeSWxSMjxRNm1wSGs4TzF3
Vm5mZHNPaCV3dDgyfQp6RXFZS3s5cVQwaTw3JitUX0FqY1VDaCpkeTlTejIhJV55YGVpeTlPYktx
ST1zakVhKjxeSDJhQUYtLUo4I01DJEcKeiZnciZ2VjNebCo2PGsqSHR7OSRxS3s1OytIMlBwTj9U
Sm55e3VTZDM+Qy1ZO0tVIU1UR3NRdFRDMjx5fURiK2goCno3cU4tTHlkSVUhODZaNmFUZWkmI3k2
PzVySGpiOCMhQUNxfTMjM3tTdzhEcClBQmZBPGgqNlVuVUQ1QSM/aWt0dwp6VG9TbkB4JVNfanhs
dD0wdF8hI01FcFF+OUszKGF1I3hQUURGMzU7SDhDKWNLcTtWPUNfbGo+amhrbE92UUBoV2EKella
ezEyPSpkPTB3MURESSVqdiskJGMqYzUoSEtKNzdQa3w3JjdLcVN3e1JfQVkjbCh0VE1UUXU0dU9Z
P0xuI2E7CnplMEQ3dTc/c1A1c3YqZjVvNWxabl9tfExCdDI0MWNMZFF7T2l0JTJiWX1YZSFpUSpX
K3lsUyM4ciZoRjxDO0h6Nwp6SCsxKHUtbVRXfW5MaWZfNklhZmJjNlY7OHBNUjFiaVJAPl5hUCMt
d0dmNFMqbyNZZ0tNWVNLREFKblFSdG9venIKemohYSROQXk4dkEodXBAWHtmSSNAJH5PUDM4PnYm
QHdWdCQocllLT249fXdjSTdJQmojKnY1Yjc9UGh8WDt9NkhOCno0MVdPLT1vTWlNdDUhU2ZqLUNe
YWNBRjRZYysrVyhNVG5wRXZUd2BqbWNKSEt3PCg7TnpPczlmWUoqO2JZJURlMAp6Yj9UZXFlQ242
TG89Q2pKJH4pfX5Zaj1obnE9bWpIZURHb2FXLXI7e2g/fFB3aXIkNW5uNG9LR1QjUUFDWmVfJSYK
ekN8Z3dmcWhjLU8xeExFUCkpWCR5WlpaUVU0eGkpPjJGNyU/Rj0hPnNZc3lKXyt0bWhALVcyTG5C
ViRyJkxfKFM7Cno8aiZCWnskM0gqUVZ3ZippOEh3SFBCOSpEK2IrTzNwOSRzNil+IUomKy0kczds
VFE5O0tYIVlebSQtMVpkeSMxcQp6VDA/Sl5NMiROWG1UTmsrbFQ1Vy0tQH41fTQyJj9IcHxFR2ch
ZHcqUXUrTj47anFDYnAkJkh9UWVAKUxCTHlPWHQKek14TUJMY0I4aEw8ajYyN09CYmxVb0hGdDlD
S1EobDRmTnVZTnZufUlEaURaMnVEK2N7SV8lYXs8KjIrYExhSnR1Cnp4LTxMPEh3M29edmg+cHFS
THdHYDgye3FkUTlKSEQ+fVBsWHtTJVh8OERzZFBpUTl+KF9ydjs7SD5WSFdCOT19bAp6Q2Y9bzxe
LW5DWnVHcS1CUCk1aCt3fX00Uyl6bipUQX1fQWRJKXFOUVJ8S1Febmp8ZUZnYGY/MlEzVCVncDwz
Q2oKel9fT143S1EkfVlwTyVZKnskMCg8UE9ieWg0OzFrSyNrTj9ieXxMWVp0XyYyKndWMFdhQjVK
XjRIQ284dkxkQClzCno3NDI/UWEmUGdqRT9ZaFZTM09zODU8eXNBKUY9KFMoYjQ2VT55KF5pe09K
NSt2SkgtSmRuM09PNjliVlYxaSZHYgp6QU0jZzFVcC10JUxEIyk5akNBbWFeJTJBVStrXkA5emV3
YWhoUkhsOFQ5O2g0U1dad29xdGxza2RnJD9AYGIhdTIKelQwWGNNdEApej1seSM2YHtBTHt4QFlD
Tj94OHdpfWp9I2I9bHo+KlRWKVp6XnNpU2ZFLVAjN25SQEhjQkxKfUFPCnpJP2IxZip7MkN7P1Fn
aD13ZjN3XjxadUs8ZGslPjBzKHt0SkAlYHZhR2BsfmlxflVSWVlfRDxgVihFcURzfG9MWgp6aCs2
UyE9OWlSOFBkVTgrSDlzUDZWKmYhbHJyITtGPEc1NVhvWSE8dXNvLUFwYy1Wd0c7ajl1PUJYWGlk
MzsmJX0KeiZibjI1NH17c0ZhPSg5bGBZdWtzTkh9bmFuflVlO2ArfmQ5Y1JgIS1VQzc+fGhUN2x6
NXJNcSk0dFBhQDJ4ViEhCnpKbmQhT21XbFl+PilZKUJBRjQxVk5nTUV8PGB2dmduYmRXSWoqPHg9
MiNafWpuUy1KJmg0MT99VyFJISMhcTxBVQp6UDxib3VsKGFxYkFueXMwYyZKZ0R7b1ZGa2MmSTY/
QGxVPlooIWBUa1NmbHtCdWJiTkE9eDV1ZkhzMSZMRV5Cd3MKekc8SDFQcU9mUWNgb04oMFYoSmU+
WmFEd3BhKVoxbk1NQUdXcWFCbFIkPTIkaCF4eFdNSExhOTE0TGcmJG5yTWwlCnp1RTtNLVlMVTN7
VW95bThgdnQ7c1JQaDNycXV4Mk01TTkjckxlPW5VT05JTlBrJXkqTHtaKndAJSRsUElHbTkmUgp6
e1Y4T3BkfE1qY05EMDA2JFpCI0JPIWJrOFRCd0ZzcjQya1lMRXNrKTMhSTZgJHBmcnw+aXkpaShI
VGA7OTBjbnsKekJiTXYmOS1FXz5hKzZudTthXkpLXn40ank8OD5VYXR3JmJnTWg5P3spak14ZEl5
V2cjTHo7dk5ZcTRHITxTZFlCCnpDZ310Z1RVSS1hPCMyKkBlKHtEPW04eFQtemZDVldJfDQ7KE84
VHxAenY8UVJgVGNJQFdAZGZXTSFhMTBVbzNRTgp6TUU9MGA7bz1ueEd4eDNTaUxEd2UyZ3g4TzVB
cSl2YSRBIXJifEw4QDJyZm8kPiZUZjgjSC00XjR5PEUxbVNKOGkKek01ITBlIXNFfUxPTHZFRUpK
VnYyKGdlKXUhPCMkM3opbT0yUEtwZn16a2I/cTdkMUwoTkoqPX1MezkyZW92UUd0CnpucjdUfU1K
OStxbmFhdksrb2Z9ZzY2OU5tS3hBZ3U3YXdPKVJicVlUcz9ZWUUzKj1WRGkjfVQzVTd+bWEjbDNR
Rwp6Oz41U04jOUVuYjxpbVlDMHRGM34lbFB8QGx2WTYzXyFDcEpKeEo4IWJKY2dLUDMwUn11JHdA
O0hFPFQ/cXEqV3cKeiZpWmgqKThuKml4U0VgVD9AO15xWE5DQzBNO19hNzZLclo2aXlDfjdabE5i
JUJSIyF0ckYyWiNxUzl0N1JBfHNOCno0XyNlT0U+Tl5SK3NTb2k5NyVwZFdIS0lWYnN9dyVUWH5S
dVlqdCkqQ01DSz5fSCg7NDQ/ZD5TSntWO29ge1EyNAp6I2I3N1ZgVVlFTUFQSUpIPUg4JipfIWJC
Y2Y5dy1eQF5tR2Z7MSp3dld8c05RdElXa2g2SC0mcWd6UmE8ckNoQH0Kej9DTXZRPjMpNXFONF5q
OUpFQ3goOHNONSFaVD0pQGh2YzIpalotNFJvOVJpeWB4JS1pdnY2RnRVIXtKJSRqKXBvCnpzbjJ8
MUg1ekY3UFI9fWBtQ0RyO2d3b0dKT3sydD9FTUJ+OEE9eygwZ3NDPn09XjhOVXhAeCpVLVo4S3lz
enEkMwp6WWxPZjZ1WitoU3FxSmY/aVhOUzRgNS1KOXN1IXhyWVFXVTBAfXRofVZeO2N3I2gxb0ol
I1lZbjhVKDVHXjEpSmcKeiU7UjtNQHJJdXxNMiRIVEd7MEpYczx5RipYMGI0TWl7WjJCY2VtVW1D
fDBpbFU5KXc7cShHZm8kfXg/NCpYOHNTCnpyMiZiP3l4LTxUVXV1JUY9Km9GSEY3KkNkZkJkd0Ze
VHBAKXplJnFFODFpYiZUQ3A7WDF9O2ZeTD1zZ2sme1VlQQp6aVg1Tyk5enZHQUVRa3Zpe2ZGfUJU
Kml9Qk5eJn5DK0pzalBeTkwjMk5TPztPdGZFczMrODlqeXBJPX0/KnRaRmIKektDVClyc1Qhe2lL
WDt9PVpsUTdnNEQ1dXg/cUlkdmRDPjk9ZEsxPmd1SWYkZjRuZylQXmktbEZHKmBNdVE9eH1rCnow
V3Q5REZeYTtCO3E1ZU1TbFV1dDxyWiolSVFBI2JRSW5SM2g8QGd7X05ZYGVIN2FEckpWK1Emc0tp
Sjd1Mlo8Wgp6MWBPTD9MYEUydGgjT3FjTm13fFQkJSUrKm0tV1czV28zMFNTeyVHdTsqVWleIWBC
OURNR2h9bil2RSg8Xyk9dSoKemxzfGpOWnBgMWlERUpiSjZmZ0BwJV9MQHMmTyZYdVU5cWRaTWhX
SDtgSWtxRjMmY1NGZjFgSXxMdkIobHV4YHFsCnp3T2sqRmdeSztEdUxQRmtWfEd5aFFhRGtaajV3
NTVvS1UmIXdAWUp2YW05QlV5Wj0zZ2NFYFE0IUBOPyEtTF52Iwp6OzJLan4qU3tTdUg7N0RwfEl2
WnF4ME93eWx6OUBoIypiaHdrNCR0aWBvMDNucD40X2A9d35xSENwOEEmMnRCZlIKenlmVFp+PW5t
PEtVKD48VkNGbkpSe011cDdiP3MzJDE9SipCNzgheTZhcyMxPkFxMHxYTiYxZzs2d0Q3ZEY0a1p1
CnpsQUFrJDJuWUNuIXt5LUdzUExKT3AqdntkM0R4ckJXKSpAbnJKOy0jMn5TPWxMMFhYJkdnKWI4
V31hMEp5TlkhZwp6ZzJ4dWJ3S3lVQzEtNiFkKl42MVpKYUg9QVdzZXJnMDB3cl8kPkRzfTd6aUp5
QEAxQ21pQVJKJms3bGZCTV9NQXsKejE/P3hlP0xVdmE4dztPfWwhMXdjYntlUzhuSiZKJWNaQUMl
Qng3ODx6eF4pPHR3ezQ/SXQzR2F4aVVpelJjJS1LCnomUC1ofF9QeVhuMWdJJTVxbV8wRmVZMXh1
cWIlfndxRyNIeFh+fTJeN2peYHRne3olSTE/P19CRDw7T0xVe1BoUgp6dWhmKH55QDhxUmBod2tD
XjgxZkUzRUA0fHt8Mi0/NkNrNVVKanY3NSM9P0RBR29VNn51OU5iJlJudyFMNXVCfSkKemMkKjhN
UnV2UEo9N24oe1BoUkVrcjFGPCRFeERlMWZsITstVHB4ZiMqdVlgdFRNVTRuamsyWHYkKCpIKzN7
bHdICnolISo+diE9YTF1ISolaCVwSTQqZEcoaDQoJGhvVWYoQ3NfN0xHS0Fzcks8fXY7JjNUfHE0
JTVOVWQ9SyNtZD94NAp6aGNETyhFblU0QVlxQEhlemN4QFheMFopVkp2eSVgQ09vRV9GVlRkYmg7
cXNaZUp2KWpIJEU9KkxkXmpDSF5icjUKejdCeSh7az1kOSVZTD9jRitMNXBIUVFANTh2b35rIUdO
M1RHVHpiQCZxaT05VzwrK1hTVi1OOFMma04rK0FIZ0k+CnpVUz1fSlJVJFg4Njk8X0pzQTg2aWtO
dTItTj91SUgpbG4/ZT05dV9xLU4xbmR1WDdyWUxeNDBHVnVvMjZiMG4qKAp6PGlLdTxHcXszI0h6
fVckT00+RWo/fHhoRDFDcjNoZ3R2UjNJWFEjMSRSUkhrZzd0M15oMHNrRzhYTkBmYDY+cCYKemNT
dE1JTlpKT0VffWB6bUUmVEcmOTw1UntRYkchbihWVTBXSW5+TEZkSzZ6ajJjKWdKST89d3o+d2FC
enpmJDNlCnpJYURjVUxAcSFmKVBAIz5PaVpZaVErfl5qdjhAWV5wQyopUiFeODxTYzgjSUhhQHcp
IT53c2R0eXpYUGdoJHF4cwp6XmR4WDltPn1VTjRNckJLMn09d1ctRlBJcFo0SVdlNihVKkVuWkd+
VW5wLWkwcXd5cjd0NnE/bCYxTGlKMylxIS0KejYwPT5DNTAwJkslMlIjbG5ZcWtwRUw9bUM2RSoj
UT9RZXVWXk1HTXYlRUhXakUpbDJaOG1ROyNpUjRTYV5JbV8tCnpESThwITY0WnsyUnZ0NShsM3o3
bTkkemIzIT5gWER2Snp4cDhBTEdgYFA0YERzWlVnbFVnbWN+d3RLI3NGajFUUQp6d3dlLTJSZnQr
NTVTRXdQcFhRZXdBY2smYTdnKkQ1NjtfQjA9Tmp8VEg1cDNCblFKbmVXOyU/YWRkam42QDVgPGIK
emt8aXw7JDFBYjRCJEpiZT4pcjkodkA4fnA0Uz1+NHBrTWJAWmsmalJRfjJ9RTc9OXRGXjhVUGV0
TSpxTXVmWj5rCnpeNDh9VGchKUF6X051ODllPmpJe0VWKnl0aVR5a2pHY2drc3JBVFo0VippI3Ul
PD1FX3c1ZWZkVEIhXiNWJiReNwp6Vk9tYTsoeldUOWh1Iyl8akBqbWZwRENFXmJWQlcxSDNPe0Ap
cHF0amBGdz5sMjt1N0tqd0UyUT1QYktJT3NzX2MKekN2QXkxSktaaFBVMTMmQEE7WlolIXsxMzde
XjMteEUqbGtEJUFRUkFzMiowTUM+Z1hmPk8oNU9MKDRfVDU8RX51CnpIPncxcXYyJWImZ0Y1KERm
cHVYK1NDQi1GOTFOMnVKUGlqZVppQ1YwJnkxTkF6TnMqJkIkeVhvVEh6Q3wzK2Q9UAp6IVRCdTdm
WiVXTUtUfVAwSXdFfnRRYDlxWmZnKD4yZGEyO3w+NiFHQ2cpaWM1ayoqUio5RXNOWDhlPzk3RVVC
UHIKendTd3dvKmY2c2dAOXJZJTlefF5jYGwtLVQ7UFRZejJzcFlGKXl7LSUkQHxnQyQjNiN5UUdR
dTdtVTliVlFnKE9gCnpick1OUjU/YCo8KiRpKkhYYmwhd209azc2MT0yRm8lQWpmbWZjQGlnXipS
KjdpRXFnNFYzfWwhYV9PYEchNk4mUgp6NT8jT0RjNTg0ajA0UU9iSjhpNjAtbl5nVHo7RGYrS0Vv
QGExVEN6THZFdHNrYlRFMHk4MFJjSXQyeU48aXdmNkwKemp0SXdCNk0zb15YPndmaFZAQ35ocmFI
ZUdxYSh9SFd0R142VjJ9eko2KHA3TSl7RVVzeUBVJH5mSEN8MnRqXjhlCnp7TnlMVz8pclVsSE9B
QyRTOXhAdnstOG5oZ0Z5MHZFaWxiclRpMkNyYzI+O1VtX0FWfGl7ZWN6cnpLUi1nRmV3NQp6KHc+
N2ZMalhvYF9yWEpiZml9dERnNmsmNUUrJmxGYi1sTXEmUTcyO3VjciFHZzR2XmNfNkw8Nmh3VDM9
JnBicjYKenlhcWhZcytxVlNxX0E7aERRTXxARTUxXkttYmpQcFBeUz9MdkF2KUQ3K1VEa1g4TXc4
MyZCZDExO21JLVZ5RkVMCnp7KkhFeistdWcwVUh+b1UzPHdYMEh9NEtjSylYUE97Y01APUJ0YkA1
PVVsbjdgPSRLNzwwblZCYD9kbG8mSVdUYwp6aXw0enZsJHlqe0oleFZUYHxCR2Q1fTElSk5xdHQ1
KXhOKEAqeXlOVm1+PWZGMVNONFdHRi1AT0FXfWlWKEZoYzsKelJuYHY9MWR5Q29HeU1pRTZNYiZL
RWxMZHA5bUtCbEhUYlBMcWhJQGM8KVc3NlBxYVImcklYK3NPajFOVlJxNng3CnojcUxpQ3ZBM0tp
VCt9eC0mQl52fT5jV1pVRUpjUWcrY3xKKGJGe3RJVWVKZDFvYVRsUVBiN3lReD0jd2R6aG53SAp6
Y04pbVArSm05UiRUaUFMYiQpWVk2az9aflp3dGtyQDgyKk5rJDc/IWwkcU4wWitTWUc9alZTayVw
VSttYk0oVS0KemJlYjkoVCRoaCp7OGdFKGdeJlgld0JhUmo0WGhSX2dsO0JtYSgoYVJ7d31+biVa
RC0wKHZwWCZVJm89e0E4d151CnpXalg3aGVqTGVWWmotdEJFV2Z8MCVQVDdgNkhoOTZMcClKYENR
OSFjYFBEP3U+TiVLLT5geGhQQnZMe01ZR0pZQwp6UG1kZlgrSGFPQGE+WGU4QGkodT1hOVBiX0I/
OSpYO14rJU9ZI3J9bE0zK0F8UHhBTzBWa2hsJlR+cTdwTDNRRyYKem1yKHRrN29NQTVANm9yKHl8
R2EpV3NhIUF2VHIhb2tnSmZCJT58eEUxenpxSms1QE5OPTxnSyo7JW8tN2AkP1J9CnokYFc8bmM3
d3RLVXNgIUBLdk9GWlNWRCE+TnMqPmtrdTJoQ1lpcXt3dzVYVFI7USE8cDwra2tJdHcqWnFPX14/
aAp6Rzd8eUNGXjZDbHJ3TmtPQ2NFIzVidVE+S0tUS1N3UW9DWSkqQHk3YkN6YyU1V24jJWwrPDhM
Y0Faem1OZGNxVkUKekNtOCErY3FnIVFBKFJDbyNXQGxAdERuOF96ZlY3eWwtKXwmcHhMfTQ8NGQz
K2xkQmVtRyVONXNga1dSaW11Xml2CnplLXNVKVM+QTtnRCo5Mj95blQlfG1NS3Q4VUZCTnczdElH
eThaSjIwP2hCPkgqbUt8fFN4WUE3MT8hSVJxWX1MLQp6NjFAdlkqWHYqUF80alZMVCY4NFk5ZnZj
I1ZEZEBjb3ZiPTFDI1VfX25+OWZ5OU4lNytZJUdDP2BKZk9RRWBWSUUKekk7SDZRWXJ9aTEtT2ok
bHdxVDwmKEBxRlhvUTwkWGNzTkZJY1pJbWBULS0oMWQqP30jN0VZbH1FamhPV3gzanVoCnppY1ot
KkE/V0c9PFQ2JVVMQEVePmVxJDVpRD5eRyN6e1dNMiFuU2h6b3h9ZnBFbGxmQGhnY3pfKiZXPEBK
TSpjagp6WWQ9R2BEX3xzSEFtQXYpZF8jVjlDKjI/YEpaJkl+QFdENz4reVY0WlIkakZ7MnlfMlRm
JlRmK2N1Qkk+YEkkNTUKejszVXhOMVFjajluSW8xekA1Yz00OGsrcVo/akhNZWIxPWx3d1FjU0V4
LVpiPmAkPjM7K19oZFQ4Rm8kenlWOz8tCno8Mj43WSYzOGZmPD5oN0NLcD9pQCFBQ1NLT3pffVdO
bDkxfnZgMj5tKzk+az9wO305anB3cW45antGPi0ySlUkTgp6UVhSMC1AdiF6SEBiPm0qNXNsKj8x
MEhmMDZtK09PSzA0QVF0bXhRO2xZa3Q+TEZpKzUySndOKSstSU1+Z2pwb04Kem47JXduSnw5MTwx
MUFHT3ZrTSM1XzQ4XiRfWVFGNmxSLSp5TS19ZF5CXyNeO1JtTHdIZnpLNTBrZlB0QGVFZCU7Cno9
fUU7anFQayR6LXRMYjM0Mk8tVSUjR0s1WFlZJmtMYHstJWpaVUBoOVUqOVFmWCk3N3U0JmgxRnh2
VntBP1VxRgp6cUpSMmQ2aCQhdUZKYnE5VyhEWG4xb1pOcHRaVS1nbXE3USlpelVnRjhrKEYwaHdJ
XnRMNyhyOVRuOSRLeT40TVMKeitsN1B2X0NqaEA0cHZ3NzltWFp6VyowITAjUjZ7PWIzXjI5K2dG
c3hHNDIhRkVaOz9RSSZjb01wbkBnP3A0TzA3CnpjUl93RV99XnIxdj0xMUZSRXsxaSg4eUg3YyVN
YEB2QS0tMWlDPWs3aXIkPCRMPUU1JCtKYzZ8aFl+ans4ZF5JIwp6dlhmY2otblNVVXVpX3N9eXde
TkFJMXhAPmsreUJ3cmlsfnFLSn1KWWBSKUEmPmVyb3NmQjt7SDNId1VFP05uNFQKendzN2V6Y1Fx
QyNLUi1Xdmh4c2Y+aT1wJHwyO29lPyt2bk58Jn1OQ3Q/R3pYLTgyciVyKDJARmpZU1o7dD9xbXBA
CnpXWVNmKHQoK0J1ZTtmJWFYO0M2enBvWCN2XiQ4WT1JQWlaNFltUyU4aDBjNUx1SUxAMip4dW87
ZztebmNVZXU3Ugp6YUYzNEhKPjVYdCorRXMlPmNZYXQqR2h1UWhRMjFFOCh4NzRnWXNaWD9WSjYo
Qjs5T304UGhlZG0meH1NRSZIRi0KekNWPmkwTTU0Pj9FPnZxMGN9WFBnSkZ6UGdja0BqaFB1Mnsl
WnI1MUNaTmRhKlM/KTFJS0JEOEg/aiFvZnQhLV9GCnorNVhwTTZrUyg/MD4pa2tZaEJPJUx8NXZj
aWIwXlUtQmxuaCR1UXd7SkgmSXJfK2h2JiZmakd5YzBLaCY2ckhSUQp6NGZQYnl0RWdCYHBQWFc3
YjtFcEZXbzMrOSlRMWlDZG0pP21yLSFjaDRpSFB+Qz97TVlNREpfSkFOaDN2NHZLVTAKem1nKyhe
PShPaEhlNyltaytvREYxWSQlMi1OSUt1WWNaejQhJlMtUjdSPmNoYz9DZ3h5PSs5PFZxUG9+IWBO
cXEtCnpjUEd6UihoSlNaNlpKdHkrKiFyPiYkOFVrMFZnNj17PHFVJTh5eVl7SVZfKXdFSU1fe3gz
V21OOzFIQypGNUVvUwp6R29zM3A2bkliQVIqcVFKKTtBSEJNU1dtdnpwSX5CZG1ucyU+KUxvN04h
d3tIdUZyV19PbWwrT3FPRyFwYWNkI1YKemVjZmVIWkBaaCUtVDMycSgmIU5PPEEpa1k+Wm91ZWIo
VEEwayZ6IyVoLSNXc15+a0lkdVdUbWZiJUM2JExuVFRkCnpgZ2RzKVZHJDd1e1pAfnFJTWRoZGhL
O0EwKVhyTyVBfXpidSgrWnJ4a1J8NG5fKlZlNUA2eTMoMS1PMmI7fHxeYQp6PiskO2ZNLUcrYFE4
cWZ2JCZNVytMazI2SEBGWWt5ajBreXkteFNtPyhrblRaY3UyOHtyO0RTWEtGXz4oR1cqb2UKejZJ
bCpoYXFyJGQ4N0w/V14rN2smPzAkRnI4VDVLcjRjWmc4UkFDeDxpYjEhcFErfnd3K0Q3cyhFZmF4
cjVQUWg9CnplMjMhd0BmZUJSPVdASFY2TE4heWgmV2xMR2d8SkA7SFE4dSpZNnRMZlFiX3A5X3ww
elFyc3hjTXZFandSeVojJgp6WF49PTI4JFElcmt3MjRvO3M3blB3WThOekwha05+c0tIXmY+IWRG
Qz9SMXxLeG9rZjYtI0wrZEJDemhoSH1lZFUKekdiTGFRSyMyQG56LWEkKzBEPkdtSExaRUFsc1Q+
VnNXWVhyMz8re2lTd21ZdGwqa207VCopNXZQTF5lZCFEIWh4Cno0VHcxYig8RXJaVDlLXz50QCFY
I0FuWmBNQzshZVM0TXM7NntPZF9KIV5ZaStRSTBQRW4rd1NLI1d+Yz0lS0M4NQp6bn0lMEZGPjFz
T3U4SE9nMns9WnEqTVhPa3RrbDUqcEZaRTYpT0I9cG5CJlZxbn0zWH1HaDNjcCNieT1oRSROVjkK
ejM0aTFwKT48am1lO3Y7dChIUTs4PDRRSX1PVUp4cHlQTEQwYlR+QV9EeT1+K1RgUzBXbyM4SlBa
Jk9CO1k0cmdvCnotWG53YTBLUTlMK3lhbXxFalp7e29FdjY/JHhVeTUlMFVWM2cjUTFBPXZubUZj
Umx7VSE0SyN3MkdDWSpmUmRiPQpLWT9aV0dAYyNrYmNgQlIkCgpsaXRlcmFsIDAKSGNtVj9kMDAw
MDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtbWFyay01MTIucG5nIGIvYXBwL3Jlcy9l
Y2xpcHNlLW1hcmstNTEyLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi5lZDY4ZDcxM2E4Mjc1ZjRlY2ZhOTY2MTc0
ODk0MWE5MGMwZjk0MGQ3CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAyMzg5MAp6Y21YVjExeW9l
ZV9rWCh9LVFCVSZpWGV6fCQwQ1J6cHA7NH0tUUJgMkFlfHpKKHhISDtxKTR9PGYqez1gQ0RQS2QK
enxLYT1scFIpKHZkMmk7dm8xYzU8JmIlbXtgKVpeX09oZ2Ffaz18OERKJUF1TXhQKElsYztNZVot
e0RnVEdHVi1uCnpRcXVGeSpxcmUoZjNqU1F4M2tLXj5OR0xCN258QTBzVkw2KnhBQShlQkMoKkxt
RkdMZitefUNGYihqWWwhTFFxIwp6P3NkSVNqLVBzTShtUDgqbD8xKURCJHdISlpSTkU3PWA2eXJp
O05IekFsR2JRXiE/WXo/ISZWK25Zb2tyb0RKIzcKeiRqRzlLJGdyQ2phSXUjRjFPSk5QdzsmMmlO
X2BHSTIhWTVXYFVXWVlQPHBgKDVFI0h1ZmRmJWU+UngqV2FVYy1JCnppWDsjVWdgJG84LT13Pk0j
c2RULWo1dWshM3o0WFlPUztYVSZzJms0QHNuZ2tNbjE/VCZ3dnp9a0JpQU49RlVGQwp6NzFAcV41
MD54WTt3WlhfSypGUmxqNCpYKDNGanx6eVFPQE9BNkdsTTlHO3hyPkVPQ21EKTlhT0JWRlRTZ3A5
dHYKem10QzRje3N4N29Sdyo4Mkc4UmA/R0NfM3dJSTsrckZvYn47Unx5WU5xSmY3JUNOdiNFcHs/
Xzt4Yng/YmNMUzNLCnokNmRaWUB8VjVvR3F0dVc9d3VgR2N2IyRUPz5FNkFacGdRP1NDNEI5Um44
RFE9OEQoJjtLRGQlQit0ZEx0NUpMbgp6TFhGNDAhfF5rbDQ/fXxvbDY/aWxicSRpT14+eXVPXn1+
dmhJeUFJdDE8THlSd3JPTnFgbmgmWWRWLTlAMmQkLWIKeldLQ1ZEV1BUK0k0dVlPbTYodCVAMHRf
O2VMWHxTRjcxRV9LN2lRcHkjIzJ2JTtvU3xmNm1CdDN1OFlPOU5TfUIlCnpgI150bGR8K1ZzY3Jj
Mk82KzZoN2VXRUZtcXtLblNBLTx6T2d9Iz5US213aWMhT09AcGV5fSRrVyRpQzAkb2JvRAp6Xms7
ZzYxaEBQIWtffTJrK15ETF56K0AhOE90ZUIpa2ZgZUI2cTV7fl5ybEpoYUphI1hNQkJqNlI7MH5W
UjdwZioKemhPV31qJHhHez9jamZpcTRTRG8+MllZe30ldmdkWU1JPjFVMUhvUC1qNio+YWEpZHRK
RmY4JUJUdF4zP2VLK0RXCnopZ3N6K3JPSkp1Snd+dWVhOG5VfXZ2QXxLV0d2MzNzV1YwN2VHKlpw
KCE5ZzxnWUxFX0ZTVncxck0tQ2lzTUtIbQp6P0B2MHZIMkFITDM4OCZQS1JwV0s0cHFlTThIRCQ4
OyRmejU7Z3NRJiU+fU16Sn5SKzhhZj5iT14zZkVmTn5oUVUKel9HOGVOWDRpPE5MY2srM0UwUkIr
Z0Z5SkxydHAmPVdrdiRSPT5sI2FYRFdzXy1Je090dmAmd2UpR3ZnYEwyV3BOCnp6UU54Rz9+eTxn
UmA3WXF5bXxrdE9yZkF6LTlKeHM+R25UJFFTc3xeYWghQjwyKHw+M0E8MTQ8bHhQTXJTfiRKMAp6
JTs8Qk9rem07KSFTb0VhcWVfcEpwWGtIUmJRZmN3MUE8XktvSlp8WXE3LUcxX0d2c21vM0hzVjJX
O1RGdV5BdnwKekQ8Q2RLN2xvalQ7JFhBITx3MG5LNE8raEZ2a28xeDQoK3BebiV9TCNkTXJMRmxu
K2A/Rj8zY0hBJFpYdWd+UncxCnpRcU57bylTbnNeQUlxJTFgMjl4a05wJl9lNXVQPy1nbVNwNldH
cEkjR2JJd3F7S05YVHFkMnBwY2ZFRHgpYXpKZwp6aTk/c19eQnB4SShGQigqOTEyX3MlNkROZjRs
aStOZ2p7eH48dWBxSCY9enJFO058fH1WMzc8QjVmPkdpTX1Sen4KelphaEg8XmxebCF6TVUrNlde
bHRAMXs9OGV3b3RhdGNYelE1Zn4mXzk0WnhtM2xFUUVkS1F5OUh2eHxSdz9uJkw+CnpVeTM9e1Bw
KEwwbUArMykjQWNKNGFgfX5JXjFRMzBkOXtwYUsqfmtjQk0pbzI7fn0lQERqRyRGQnFkRFc9MGpv
Vgp6eGQ7cj96SV96bis7QUJGdS1iOSp4Z1V9eGk8Sm5Fa31PUT5aOS0mRzNyaEZKaF8jQkI3Y0Mz
ZisxfWxVMSt0eiQKemFnTzklJThrd2U3aUIlMF8mNjwxcShPXjVLXng0NXRjfERiVnNvVXxMaDxv
Jmx1KEc1JTQycz5zNUE0KjJfMWN0CnpZWXtVfFpzK2YhbihNR1c8ZyFsWE15RDs1IUdYYDlWQFo1
eXRoJmk8PGQlY0hhaTl2NENUbm5lVFRQVG4oOTtCawp6QGBPR2ErXzI5T0UxVEc0Kkxvd2xGaCtp
SExhcSZDQWMyY3dWQ0xrdnBgKlNyXiFBUj0rI2BQdkJ1eGhHOHU8PmoKejA7TyZnNkE0XmpLWW4/
aVVaNyN+WXhka0I4Xm9UfWcoJmhSZnFKK1FiIS09TllKQkhRZ1UhWT5MbVR5RiV8Q18wCnorWlU5
X1I4Z28kPTAxYC1PUD5aRWlYQVNgQ1ZyYXVjM0dMI0o4fnJ7PD5abDxKeT9oMypwQyRKWWJqaF9l
bTJ8dQp6eUxNX1gldXNnaTZlblheNFcoeXx0RUF8cUMwNns9MFlSIW9OPE1xSXBNNHFCbnx6JkJl
TT9OfENCR1EtMkokVSEKelVhOHxVWV5Ya3U0Pz4kT0hfd3JXO1YqQ15fI0trQ2IzNH5qVDNSRmhE
bUghUm15UDctZkFrQF9xODZVOzgtZnI0CnpscCY7VzxvXkJRWHhoV2MjXjtEOSRTa3s/RmJJVzg+
OURWQVRsWmVTUy0yNVpZRXBtOVhPa1V4PW5Wenc0YX53Kgp6WHJOZj1QdClvMGpzOHA5aSZPUyVY
RTs/cyZEcmYyME1SdWxhRUIhdzx+XmxrM2JuRk5MJE4xSSt1NSp6STNoO1UKenFHVSt0VnM7OSs+
K2pKaT1SYUhQQyhtODlnfnRCeUFyTWZIMSE7fChiSXRUdDd1dDAtITZpIXA5bUpkekx5JUpDCnpQ
N2RLZ3ZybjQjRlJyO1hBRktvZChQRW9SNlM3YUVCNWlTJUQ4UEZiSm5KU2BTWns0bFgzcXAxSnlE
T3hPV3c/YQp6RlM5QGJuVkZlIUcwbDViNHdGKztea0BHNUprQT9AaCY9NlFSZ1ZgdzlQazQqSGxK
UV9xM2g8PkoteStgPzw9fGAKenUkK3wtWGEldiR2Nz8hemtNZEA3RlBsdStee08wSVNTVHMyVWJk
UUp4O0IqSkR5QDRLOWVfWENeZWRwTGR0Rn5DCnopP1J9c0YtS34xJX5yRHhMZH09dlg0JDEzYkVg
dDBTfElVLTBPeFk4byFMfWxeJXxCNGF6QTJxO2l8MVNwQWhZSAp6Q3hXT2pyfXE/Ji1WO2tXUDVL
NzdfI31qPlQldTZQZ3owXkYpbV94PUdIenw7KmdaN2I0X0E+N1EoK2BwVTx9OTkKelIjc043ZT42
TXF7aFhPO1Z6I3hsNl49O2xJOCNCUHVKSlBSNDNDY0htRT5OTWxWZ3tKcy0tZ2ZYT04qTCpFKkV4
Cno2UihaPiVtdzxLXlV5IXZ0Ki1hcHltWXJ3PDRhY242MiYySXRvPmE+b3Q0YV9uKXZvI1lje0VN
VSZlKkxEdnphbgp6YykkKVR4P0RCR04qej07VW1tRDUle0hsPW99VEl+bVBTTklNa2pMKzBHVjk8
ak07QkNvbypOaylhfHM5QXtUbXMKei0/S3BXVGVUWXtRcmcoRng3ZFJkfE1hczkrNWxPNjFmbjs7
X3olQnRXN1RJSGxqRkJTQ08kSj4+PEI7MCl9KThVCnp1JEk3OHJ8TGV4dEBZSyo+NnI8V3BESVVH
bClDYTB0WXAzcDRndlMySHM5VEEhc2I3anlFYjZCbWk5bkQ4ckhITwp6JUlxUylJRmYxX1NXe1Io
TUhfYDhHOWthSkgtTyQ7R09NdmBgU0c+P3o2SiFIOyRkYyQkQzlIVDVKUilmTyRWRHgKenZ3ajto
M1d1SXZRWj8hOWwkNWtkQmxjbXtDRV9BM3ZrZj00e0Mxaz82T0NgPWEzfXZWZ3xhTzcmR3dwU0dC
WHs0CnpKQGl+YmlrWm5ZYEQqcTN3Y05pTWhoYDR9TklUYS1USVczI1dVU0QlanZwYzk3dG9ffUhO
cl4xVjlnKHRJU15FQwp6TH4/YmJkZF8mU0BKVW1eY1YlY3hkQ1plVGdBPFo7SVU5N15IKyNQT1Vh
ZH4xLWVMU2FEemEjdFRTYypPWH5mVnAKej15I1hJZypnbmUkI3BtdD9PPW43d31DUHpnZjNUNClj
bUZFTztgP3JeRkVgRT1AXihBZDNkb0dCWk9WZzNmT3V9Cnpte1RfKDdNUyNtNEVvQks8QEBae0x1
fUEjIWk8VERZNSN4WT43ITVzR2N5bSpoODQxV2tJVHtMN0RVbSQ5V0JwRAp6cCN1R24yMzZEOHtX
Rz5kbzEzaEM3Z3d6NHktP3ZpZSU+ZlplIWtiTEFZZkFHREZBdW9JIXZaTW48Z0VZS1JRYm4Kemwz
WUVYXlkten5USEhfaDRaakR9dm1uYngtciFZTEQhY2JuT3tsY0EpSjYzcnQ3X1QhOVM4LUhyVyg4
TWtfWERrCno3NStPJm5RcWVuKWdBPDh8QlI1Ji1hZnR8UlFzMH5JKUdqJWtCSihXVXhUKmFYUF5C
RkdyOThXJkdxSHJLdXx8bwp6dUdodDlaTHhXSmR6eU9wZ3FoVmFWNSRlaU5EVmJYajkjZn10NWJ7
RldnQ1AqZm44ViRASmJ8Q1QwdzRvSkBYVEIKenI7fWE1eGtmOGt3Q3p2S0dlWVJLT300TjFeYk1p
TFEtITgxKC07SyhoJjJfY091dDtPMiR7YGQraDtDcUsyKj9fCnpJfmN9PVVNcjhgKHNYZXZoUiR1
ZilYeDlkWFdMcUhSN2lfQjs2ZGNNfE1yeTllUFZ7fiYmUXJsKGZgQGxAUFg/UAp6S2huTXgzaz9T
P0ZBND5JQTZ2RTkyajswKi1ybW58RjVRbW9OSlZkXkJTVEswRmZ3UkYhVkpCMTkpRWIpKEtNU1IK
ejlnUDRyYUliJVd8Nm8pNyNoLTFudnphakQmVTFgMTl5SWpwe2tgPExwIzlIaCYqa0xyPkp2Ki1E
Rlo8OENAIypjCnp1Mj1KNCY4KiVJK31eQnkwPSomOXpuOGxMZklGPlVALW8/TVlxc2k0X1Uwamdm
c304WC11WlVKTWNBe1NILTRKbgp6bkBlQ0NCJGt4cEFqIyZfPDxnOXFzaV49cWBaRz5NcDJwSkEr
MkdXYU4yXzc4PWdDey16KUt1ck49VmJDO29xSjgKekBCP08tZ00tdFdAdkUzKChIYV88OGo0QWZl
fmV2OSU/X3lMTlFWPHFMSmJQX09ZIUwhTDEtME9IbGRhd1k3azdPCnpoP2p+aj5fenE0VGxGckF1
dFRFbUJOan5CTXc0SGstRkN4NHpuUlJXM350R3g4ZW1ZOU1wYVopZGAqcHxlMjRmKgp6KV8za1Ux
b3NRcmRNLXheKiZYfkRpTXg/blQydUxSdFpQTFo8UHEmNShTSWtXRkgmdzhvP0M4PWVtO09tUFct
bz8KejwzVkdlPWp1O0JVUjw9XjhuaEtuKDd5NypoUCopfUpiMzw/eHVrWkIybTx0Nm4mNm18cFhs
QGJaemJfMUhfazNECnpXI3hFKStVPDZaNHNzaENKJENjNFhLVDM3JTV6eThGbVRsK0xIMlk7NSM2
ayU+emwoNGR9RHp8Ull7bmxPencwaQp6eVAzNCpSbEAySTsxeWp5cjU5VTBFKUEhRG4hVUZ0Ty1T
JjtOQ2R4aDl4fGB8Z1JhY2hIfG40RE9JdEZnYUVqamIKentwRyNabSZVdDR0RGRqZE9QcmpZVWpZ
Zn40M3p3KjdaOzFhZH1kR05BXklkYVE1JHp3c0pPfVJXSzVkflBvPVZMCnohOEpaUjhhVnpKUCsj
R093JD5WJmxeO3QmQHk3Q29IKnFpJkYmIUJqcWIycD41aHB3ZGd0VHoqQzFnPGdYZ3x8UAp6O1Bz
RiQjdXlMdD1WUGh5YkFLZF9ebyNsbk49aSFCSHxwRld1MUx8UHNoRE9qRG9uQWxvT1RLUEtQdV9z
JlVJPG8Kem1yLUNASE1HNm1ScCsoUW9ibnh6eFB+ZGRCSm1oV2xoJno/MXFeP1B4fDJeM3BeUl5L
Nno2YlhJZXJFSG47KzcxCnpuUEBuUEhzXlNnOXw0aiF6WUFiUHtQfnclY1N4KyhfdUxwNG4oNzt5
bGF5aEp7fUdLc05jczgjVUc0ekBxOUJWewp6TDJ1Vj5fZ3lwcGV6PiVYZlFCMllKdit3Vz1sXzc2
bFYyKXdMPj9MNSMxZ3ArNkQ0aiE9MFdxUjxlRWdgQSQrUGUKemIwQUlXLWEjd34xTE44cSY3clpE
bU0wOWIye0s0dU5jTDxfPXRZUFU0KjN5cWZNaUNrQXFwWnFRWHolP15WT0hqCnpDaCRyfD0tWEY4
ciskI2JeS183Zi18Mnl1PmN7Rkpha0dELU8kezlrTmhgKnkhSS19YXI+KjRvMl92fUpSOTdnbQp6
MEp8JWNVZWNsdlBxK0lkMD1LIUxMcXxEaGFVOHtpdWJXZnleZWNzRUFrSFZFaF8+O3NVUT1QK2lg
TE5mZGtHZikKelNLSmFydzV5QD1iYSZwTWYhLSNsPDUzaHU1ZWIqPUV8PGJ2NntSTWxJMjxxNkV2
Iz1xbEJXS2JDbSF0IWlBNVYzCno9TzclQ3dkeldeU2plS1ZDcUlXKWpTczg3azglPmpJRyZfS2Uq
eGMmM2x1JlZUcClMYnNZfUFtZTZ8XzhmQmtCaQp6QWI/aDZ3aWBTJjFlaHxEKWgkYG4wbmZKVmlA
VER+JUUkaipKc18kbTw1ZClnVzBxemw9QT5mMlVzNiQwRSpvJUQKendOXi1eV2BxbTtCfjZUaiVy
YGE7R1Q4YGtVb0YjQEE4QGstbXlZQDFNUlB6VEItayFxX3YzN1VyUFgtaUlHVk5GCnpPPXJCMnUr
XlQ/VFJkb14qWEsxbWI0LVdHYXxZbnsoaTkqby1aTTNHN2wwZ2k2SkVKTllyNisqKU4hY1d8TnBl
eQp6bVpXaDtQS35RdzE9b2ZPYFVYTitkZyoyTnc2QVF8VH5lU1NQdDNEJmhQPVVAa2RjcHVIbEJf
Y08qck50N2F2ezgKekw4dHgzQDMjVV9eWjlAJVh9UXQjLWF1KjRaRV82SE9qaSNRYG0qSUgkSXJD
OWJMQThBOW5XK2ZyXit2b21jcnk1Cnp1T00/V2Q9LXp5M2BpYTUpRFNFUGI5SFJWaD1rIUJPLUhp
PHtsM2FzeXgtbUhldTg9b1d2OStmNzFfMGYtO0JMSAp6di1ecG9FJiY7X29oKSVoYlhkNUJtaDZ2
VG5lWEo/aEJWYn4mQShJeWQwOEMwbzVVSDtrWnw/cHc3a3NBYE0qfmwKenBiWH1aZXt+OSZPbyNt
PGdNdC1wdHp8cF5Zak9+UDdzSnI1OyhLeSVpaThnR21BeiZfRXNYUUskWVJ1Kj1ldF5OCnpTN30o
dyZOcGdwVXN+MH07Xk1TXjRgM1ZKYTJuTk0jRWs9Tyo8RislcSo2U1dlSUY4VEpmSHFQTGBCJHRj
QDwqcwp6UHxCU2ZMUU51IWNDcWt4dzItdDx3UlZhWDhUSlp3bExZdzY5MU9lay1jZHNETTYtVTxr
bCs8XlE7RjJ6Wn4oZHMKejswaGptZEEpbXgwQ1M1ZUwyRGlrYFlAPDQ5PkM0K0YkKElgWW5JNVFn
empufjEqMVA8UklXTlBWZnA8MCQqNTtFCnp6dCZiaSM2dHVRcW8yeGU2Zlo4WXtyQnVXbDg4cTJe
SVZOdkp9RC0jX28jcGdpVW0xU3VRQ3NMVTUqZ0kmMm80aQp6dmhEVXkqYFlgcEhQezFFPSl1JVZX
P3l2TWU+bD5pc0heQXJzUUxaMT52JE53WURWP0l6YCVTeHtreXdVa3d8djEKemxyM2ZAOH49TTRU
cTx0I2dVK2JXK1VRZUhEUDlqamo4dl9BUUhMWW1pJEw8Vl59MjloUyh3JlBWantKVUNGN3RrCnoz
dmpQO0BZazFRS14tXlBvTTF0bkE9c1FrV0RLOVA3cW9pams1MUJGRTx4c3o5VHZ2MCMzRHNwQn1g
PWpsVzc5SQp6YjFIRjNuIVJNXntoRXlYa3s9eTc3PkN9RHJPV04yOzE/R2NZeF9zfXJPbzYpWG9j
czJmb29mdnN2SHlvd29hJkoKejRTb0Y9N0Vnczk3P1RRKkd9QXBwUTJOKnZ6aDExUylHaHdPT1U9
WkBHJSY3ezVNQyFlPkBUfWhDI1J3eyVNbj9XCno2a0IlaCZLcCZuQTl5TnpBQ1lZVzhmNlM1IWNt
Q1drZipsUmlIfGckNTImeGZrYGlUMCpPPkg3QEk1KGw/STJJdgp6MG5RQzNzXmFqUDB6fD1lYno3
IXEjbkNVbzwlaF4zcUw2NDN7am9kNCMpZU5+Pkx3PT44bmIqNiFDUm16SXkhdTIKel5NdSk7KVAk
SnJlZ0BKYnR5dCtrXjhSbTBoPUp5am5fVXt3N0xJemQzMG5mUU1jTmJMeTckKyM7eihVKE9vVy1h
CnpZcVlGfjhUd3Erc2FUUS0kJEFKUEVNSlVweilwQU9QXj56bFl2bTA4WX5sWDBhNT1oJkVTO1Mx
Qkw3fipYNmFEVwp6RD1UXjhVOTg+dkhvIzJTbmpNKWQjSFB9bWdpJn5AczF2MCE9b09oNGA2ajJg
VHYkPDxBQD8zIXo/I19EOD11QUMKejJEcT95dSlwZEpjdTNCQj5iMlM/TGooZ2tUcVBke0pSeE93
YC0mYiopUDUxS1hvN3YpNDs1PnVFP25QWGpQNmYlCnpkWGJ9VDhqPFMjbiM5RzFyZXJtVU0lQiVv
OHEhX0NXND9TZEQ5RTdUUG0qVHJUb1hyRXFpSjJFKjtERz4taTF+QAp6Rm9NPyFLfEJuPmJuKGd3
QnBKJC1ZWlcxKj5KJUZ8QHtTfVkxNTlNT1ZvWnQtKz51fF4zRVR2JG85bzVYTnUzTCsKem9lUFBi
UT5vYnNpTDJQaXxKWFlgdCRoNTdpIXVhKSFTa1lIaTteJSg2cjUyQTZ6NUZuRD1LfCl0KVUkTFYo
TUJwCnptPTVqOGB9SnZEI3BMNFJWdCEyfjF2Wk8yKSNrdDZ4R2ApVj1KWSROV09oWFJTRi1aOUU4
Pyk2dEMhamhvVD8wKgp6IWAzYzJ6TCpwRWF9ZGJBRz02Y1Q8YiU9QlR4aXZXb1lCfV4lbUl2RHA2
SFlVSXF4UW9jdTQ/JGxpdTV4PDR6O2AKeldXIzxBeH5yZDZNVlVKQTltWm5FYVhBeipOfUEhcHpZ
VEZuQCg0SnFPd3l6SDxCTEJlKHZITmpCdFFoa0NIZjliCno1IWZqQ0kxVTJhcVNFJT9ndyhlemRN
JHNqJGcjelY8TnhVc0FBYStMLU5re0JAdiUxaG0pVzRBQ1ZBVW5pWDN+RAp6VT1BZVRQRSN9V2NZ
bz0hQTdqQnMmc2lmPTJIMiFQSmJfPCZ3YlJ0PHJuRHpBam1UO284M3JsUmtQMClSKWJudWoKelRV
IShyenRDJDk8dlE0bGYlK3hLZiFCNEJZJXBsVnp3d1F7NjtiP0tEUTB7THZIWUhBWUs8THU/Slpt
MEQkUX5nCnpASUgzVD07cG53YjU2eXZUPUhxSXlsJnQ2MEQ5QikkKkFnanBRaiFKV15UNyNKaD5I
U1AtMyktPyh7MDUkVG5OeQp6N05teDdHIzxnKE1CS313WEtUYClDSzgrLURiUGJRc0UmLXdXe1dF
QndeeEFoTXE7U2o8Zm9IMnYqUnpVOXJXRmsKeipmNj1UT1ZAUComVF9tQ2x7YT5raCtve0lEWnA9
WEJ0S2U7RC1teFB1Zj1pa3RsfjZQJmZlS3E5VDY9YDNtO2VICnpOSlFhaUNnSHhhMXVDfHFNKFJF
cUBMfm1UYUEkKWNZUzY3VkZFP2BTeyUwcll3RHRUKXgtakY/LX1ePn5fS0l9Xgp6RGpSPTtNK2I0
PFB2TGhIOWtNQXM4NXhWP24tWDdJcEx0U3RvMjdnODkrRWheSz4yUF9CdUF+b3lCPn5LJDdGS34K
ejJEfkRYd0tfN14kNklQcCZJU3VDQ3RBRiZtWFYmI2l6UXljbGVnMUE+WnYlMVhqJmB6ZWwrfVpC
bERsRmA/ZlFJCnpuMVc1bElgLXE0MzV1UENiKDFHTXMzfjRZdmVXJHdzQH5WZDR3M3dYczEjaDMo
dStxVEV0Yk57aWBgSmxFeEZvdwp6SDh3YUBMeHx4fDdffEkwN300TFIrUXBKa1l0aDtNUjVZJDN2
X05VfFpga0F7Pn5sUm1nTGd4MD4paClTQkw/akYKekY2Q3dVNXx7WGU/MF9lIT9qc2V3KkgwLV9q
a3ZqZjtCbD56PXU5eEteKz1JSjE3NFpCWTVke3MqNnM4T2ErSXJWCnpleGpaQWpUQT94N3IjeiVi
YlArNU9wUk8lYlkocSUzVlNyLSlpQmFYb1p4NUB4O2p+e0crSU9LIzBobG1paWo2cAp6NmxOa1JR
fEVuaVNsJFdPe2goMU91YGh3S1d4ckV2ZF5+I0JXP2A1c3s+OThRSG95RjBDN3xBbEQlIU1DXmx2
QWUKenpVQ1dydHoxKjFpPXxVemBHUmQ/SjI2cThpVzVoV0t5dVkyXk91P3x2Xm1rcXJ2eSs5ZnBB
S3glOUdDZEN4ekxlCnpUO3goRE5sSTt6VmN6WSFNTns1TlBFKHtOMkopOU5JVUQwbGY0YlBLS2VZ
amhEWn0hb0RlNk9Gc05jQUc2KHNyRwp6dF45QXpEUWNOR1F3bHMhTWJ3fjNoKCpDcXkyPFR5OypG
VHNXTGNQWFF1NzBVRyhxblE+JWUzXkVZTXRlJmF+Ty0KelVWISh+N18tNCokS2ZWUEhfeDRqXyFr
SlMrLUBNSnUqV3s2UGpIJDFQKnVpaFBwUmhldVBURnI4LWp6TlUzX2sxCnpBbi0heD4oLTBXS15m
c01yM3RvfChpal5iciZoVSoqQWBsNkFJeyFGMHBAOTBhfCtUaiN5RFo3KnN6O1hORS0mSQp6MipF
MW1qYzd1VGBuflpWXz9OcmNlNSZYKFJfQ0FWSldKTGAmdjFBYlpNbCFtdWNURlkpUUoxPit7Q1ht
KF9NUSsKejR8aj41YHhZIV9AQ1BNfnxLOW5CZkBxUCNyIT55O3RJOTA/PEQzLVhQVE0xMXRka2At
az9HWSs8YWg4JlNuOWxyCnpQSn1rP3kwcGd4VDlkTDgqI0N6MkNnai0+Ym1XNkQ1eEM+YmwoV35D
WkN5LTJVN1MmS0B4fGo3d3VwPUslXms5aAp6O3UoNDUjI2QhPmt8JHY8cjdQSGBRZmhfczlsP2dG
cHsmeFI1MFNfO1gmVChXeXRoK1gzTXlKNE1YUyVmd3IhLXUKeitBWFgxNnt0SllpWWNxQDxRMCsr
bytQUFV2PT9yWEkkVW0rM3ZaZDh2OVptM3JETExSRGZXI24kV3gjVDI0UTNeCnpxQyEoTTJCcUFA
Z1pTXnxhbStYRDQhSTVHP0pzMFZsQ3slIXxIezlHV2Q1cWB3ODR9JVVBQH0qSk1+NHV5IU1tUAp6
Y15pajBSclN+Vms3YTBeVWxjM0dlKmd8PiM5ZVl6e2UyVispN3d2M21HMyZteGNZNFI/Xn58JEdj
VlAhSXpSa2oKenJfVGNedCtYZmR2KiswcFJnNFA5SjVGRXJUNGV0YmRZWSl8I2REUShtISllP1RW
T1FFYUc7YnBgK1AhKUp7aTIjCno+PnlyTHNsenY/JDJSMjJWJDhXfU9JK1J1P1BabWo8LSQkWGR0
UzFZNCk8cDUzd3stQEdsbEZqWHlTI1hVbl9iaQp6NEN5P1FiUTw9WjRqTSgmKmw2T3ZsVCNTPT1m
PDxAeUpLdDgqel42Jl9PZyFiK0BuamE8fEleTlVpO2c9a3l5JHIKekFWU3BqR0ljdG1TUWdUcCNW
JHlaPVgzd0ZFXlJVZUhvblp+Ukh5YHhIR2grX1RxbkQqM09rdmNWd15HMzhFTWFFCnpyYERrN0hY
UyM3RD9iWGxoJj8+ezw7ajhRTzRQOSQqUF4+QXNIcXdVISlQUXleQnprRDN1azs4IU5xUl8we0BW
UQp6YWlZcyRiP0JlTHspZigmWChkWSUleVY2dDR6SnomZl9rTUBBNXVvRG5Ud0A/O0xFLXdNT18w
JTw+fDdoU1M7TCsKej99Kn5kZlpYKEV2ZmxmN3ZIbHF+Q31PVEE1QiNIVHNeQ2NtNFhgSDZ8RklI
VVNVek8rYDwlYG5RP2Uxc3lfbCRmCnomSEdpRDJUc3UlKDhnVjwzVEspaXg5UFY8UGxXTTlgV2d5
UClTZXxPN351eiYyQSY9e1U7ZjtoM35gdFh4RTJePwp6V1YldCUla3o9e0dAbysza0ZKRFVUe1RR
MFBMSndHOSZDKFZsLV5BR2sxdkNiQ0xZUDZQUFhBeGVlUzFPaEAwa2IKej40fT5Ed2QmNzdffmNJ
SyFnS0dibF9LSkdXUWtyYHpMPkZ2cklPfTYxNSY4RVhqQ3liJWJ1ZSZPQClQfGV2P0RlCnpJcDJ3
ck4wQFZ+ZTRjSnd7M0NPQGQ9ZTY1ZUE8dVIoUU92YG5MLV94dFljWX1NaWtOME9Ca1ooWUtNenlH
YFA+egp6bnxuSypaJDNWWkZXLUxsRE1oaGsma1psZDRSUiR2d0JTRzJmN0kjTntyYypzeUF8e2w+
ZkMkQVFpRHcmKCF2I0cKek4kUjgwYWdwZnt3IWZkUj1qVS1wQSkzVXokZU5fRndoVDV9XyY7I1le
ZnhlKnFjRSQhZzVSai0zc0pRR25DczhGCnpxbiNNOT89fDVIdzUlcmglRFc1I05yZDltTV5yZyY+
VC19UGdtTTRqXm1WPlRzPkA9YiFCMUZ8SVUkI3twY3YwQAp6MWtiaSFgYz4tRChEQG1hdTVzO2Vz
Zk84IXc2VklWMmVjMlZkYkhyeSNKSH17QVM7ZnpyVk13Ozk5dzlkd3FEWHoKenh8KXFDc0orZWtS
Z31ifVJCYjhJQEtmKj5JaHBhVGY3IW5+Zi05TUU8YzxIVzQyPzYrUl5tYXJ3X2JfU1VYJndRCnpq
M3B5UTY3UVI+QEl3NGRnPmcmfioqfDRxaFpGY0pwTjteSEdrQnQ1TmlaQXBjemtwQU83a1poaUpO
e0tqSz8pRwp6Pj92PTRAOGFnVXo3YjRCc3BOam9DMjlwMFMtM3x7LWw8aVk1TW5wV05tMHpJR1Vv
N15IUE8lb19lKmc4KFByVV4KeiFlQVl4cC1AMjckNVkpTmpWKnFMJl8ydFItLV5BJm0mditIY2s/
MmprVWhmMGtZfHh6UDUhajxvM3hKMVlsc1kpCno/KWBVdEA2N0o5ZEZtTUVkQEBoIW9SKmhWc0c9
ckc4NDQxQm43Y2QyRzkzOz84KjN1Nm43Vih6clRrU3Z0RTVrNwp6KzFwRiREXzdXWm9ieS0+eXQy
WFc9Q2FVST5EMV9RbTI7a1AleXEpR2Z2MzBBaClzeDZaVUtDWGwjVUBxS2xXdVIKemgtVzNYPm5C
bFU4c0dYKnIxUUVvY3lnJEV3STc2YmJqZDsqMiE/REtgQ2YrXilDclpMQzghU1NkbWdNa0RBSyRJ
Cno+Q0IydnVwSUJWNEdCQntsfmtgSipTTlZzMz11TiFSZzRVcjJnfmApc19rcHJAfFBJenYxSDl1
QHN4VHxGRiNTJQp6Jio2SmsjQHQ2eTZDYFpLaHl5TF8kMjFhPTMoMnh0YmpDNmNvKigkYWR3PU48
ejtwa2JvV0wqQV5iZmY0PEY1WDUKenk4QyhANn4hRnlIZUJDKWtgMEhmWHU7Z1I3eU51fEBfVkE5
VXRfflg5WnNgVyp5RUtTb3BPSFpFfUo8ejk2UyRvCnpodG9IbmFLQXFNNT9Zam1PcERlKnokMUQo
REhJPkk+Kz5PbjNTPTZPSCp7X0MtMlJ6bnBTU0JHd31XOypeZUdmfgp6QUdiWnhFPGJ0TEBqI1Jg
N2xtcylreWE0fiE/PHM4NnlsPyRfQyRTfG5LfUQxQEZJSD5nI0FVYzk0YGx0dnQraHkKeih5QGxH
V24qfHw+aTNeVz5ifSQhQzRETUlsekFPZmZkTW5eR3hHNzg2JkNnTSN6dkxYSmEpM1FGTFJOfSly
TFgjCnpgPkE1MnNnMyZycnB8TE89aH52OGxScChsY0pGRjhhfTVAbkxwZDNZbj88Yz1AelNoU1kl
Y0IhWHVGJmZ3SSFYYAp6TDZHMktQb0xSeypLPn52ViY5O251VUM1Y087c0Yxaz1qcnwwdHw5cl56
byp6P31BO0NQWEs0MTAqeF41WVdrbUQKeisrLWh4Xkk+Z316K0hzVWoweE0qWiRMMDxnbmk7P0E8
VCZkZkh2eSkhJDlgPT97KFZ9SD5JQE9JQm9NcD1uQTtpCnpndVUlVF9teTtoYk08MzRteDw3Klko
ejxTPG48YCFSMylCaDdeYjJhV1hTOVVTPU9jRThSMzJAaExIQk8xfHxKaAp6RzNXcEFrRVo8O2Bt
bnBCYVd3Jih6Wnltfl4/TEslO2U+M3NGfjB6T0oraCF0b21TWSEpaHpLPWtAbj1ySFQyclUKekds
fCV7XnRUUFgyLXM9PiFTKmhJelFwdHBMSDxgSUlZYj5ucnV2WkIxVFRkRjU5Jj16Q3gzKHF0SUZx
eUZBZzFGCnpXMzRrYXNsSH5mX0FeVW50TUo1eTxrKz82JHhuYHdKI3QxfWVtcnVYUGhAUTM+MXo7
PiZwO3FjbndtWj9eUlJxbAp6PGc9NWAqUSg5aFg5fDZEc2dhOSQ2NGBlWV97MXBSc3spdXM7QUpr
XmN3JWEzZ3N1TW0oX00xdzg9Zz19dHVpc3UKeiE3SkdOU1lMbFE/V1dMWUhZRTFeVnJJNGN3eVl5
SGpQa3dha2wyZipUYXJJVWx+YXtAZlZEK0xoRDtLJmVAZkdGCnp6MitNZXZ2dGJrUWklOWxjIURH
Q3tHPHhFYlo9ZkJeQCE3ZkExSzJofEhIdDBvdE84ZHBmdzJwNEZOUFNfUVZhXwp6dT1HQGZXRz85
KWA2Yz9CeytZdWljQllEISt8bFVlIylCdys0YjhoUDk4QmgtM2A4YkclWGcmJS0rRGt1ITheTCYK
ekU8Q2dxOCQwQ3hQN2JHR1M4fnxyZSNmSG9HOXRUbT8tUlkjMkZGX0xQRygjOFo7ZWR9fDRrY0NM
bVIhXmVQNWxlCnpxX2N3SE1iK2tQRDVCemJUYT48LWt3RDI2bTEldFFOeFMlQF59Sk9wPGQ4JSZt
UkoxUnNyekYtLVMtZDA7JTsyfgp6NiRHNDFxcmpsdnQ/TmdBeFhDTzNlWUUhJm9vdDx4KUJPJFp5
bXZKU2xAKlFQRlhWUUF1ZUkxPVFoRWlMYzRETnUKeitVeXo1JWtNVXhSSTkxZjk1eCFkbzhGK0Bx
YGRvMCpOS3ZvcHNqSDN0JWx5OHpfKG5HWE56OzFuYEQ3ckpecyEyCnp2KiUoYVVIYlJUbC1iRUdH
P0VSYUp6dnl6KGB8d1hCPG1qWjU8RVZ5Uzt0OXo7QnBEPU92U08hJENacGBqTlYwXgp6NiVfRj03
OHxkTDZoI1V7MUJMR0NnMnhrb15ZUTc8P3Z8ZG81RllPaWlFWGRjSlYyYXNtJXNSN2ZANFIzMHxn
PnIKekV0JDZ5bHMtPntkIXshUnRrLXktZTI7V1BRMFhlSTReUz1fS3VvfCp2KUFeUTNZTHo7Mmky
PWpSUGZubT4qJSUqCnp8TXEpKjBOZTMyU31NajExPCo0bk1fYjNHZUNjJUU8S15BYD9aX348dnA+
fXlDajZBfElTUk9RKz02cVdMRSY/RAp6a2dyMFkqSzRhO2V9ZEVFVzdyVDU4Sj08Ul5WZ0F+UDY4
aDdHQztRM3txfFdIWUd5VD87czQ0dz5gYkZycCU7fnwKenpvcV5IVCF9VXdoTFB7STZJb2hlaX5z
e0hpZXVUSWNqdXo+cDMkWFB2RTlmQ3hkamIkUDBMIXFXTypHWGBgOEN8Cno9UjEhRW5hRjtaWCZg
ISYzbW52NFg+eSp1Wj13LTRneF8+Zjh4fik8LUE4QGZ7PDEhd2F+ZUM/JVZLYUJIOV9AfAp6Tjty
eHRtR0d2US05TXslWG4tUD1XNF8/T2NYPmg4cEM1K15gYGt3RzY5Ujdpek9fVUhlXlFaYEBNaHZB
fDlwX30KekJASjhMYlc/Vjs/cENUNW1Ge2FFeT0lb0tiYWY9WHhBN28ycXtyTT5XQnVvb29aLTh7
XklWK2o9UjNTZExjSUorCnp4Xk1IblErU3U5cGJXVDlSIU4jUEB5JHZlS2hDfXR0Yk4hMHQyJXMx
Qk1NMVJxWlJoKSEmUHAqbW4tXmlDeytycwp6JGd1Nll4YWM7Tk1FfWUyNV5eMUB2eSVGaDZ6TU01
U3FzcXUmdjBGOC04Wk17aCl3JmlXX2UlQSlzO2V9ZC1GcFkKenA2YXFPTXh6emRTK0s2TGNRYkJa
aSVufUwzcChaRnIpUmxWIzZra21aY1BvWEQwYiVueVAmPERUQTkjM1dGTlduCnpwNmh6Vy1OUThg
enszIVVQbmpmZUlqQ3tJMHMoUFVWd1V4aER5aihidChvc19mcGw2KygjNyVMaWVufERwUFp+YAp6
N3lUJXohJjRuMUdRbkdCeik9aSlZJFFYcC0kOzVeVmBiS2R3Um5nZFVVSEdHd1FiV1ZqXko7MihX
e0diP31CdTQKek9Xc08qZTZ0R05DUjE0YUl+I0ZMKTNwQmpLIWwtO19lem02Zn1pYDVldlVnJCZa
az9EVVhJazN7fTE7dWErQ1hvCnpTQUlCc0VLZVZYO0oxKXtWRDR1RDYpQzFfVyEmPFZwSU1vc1BG
TzQtKXc8RlFrKEw0Tm4oPGA0QmJmY0JKZjEwSQp6SyR1REt3MnZKRVBLPFhlTlNjRytMRTV3Yjhx
eHlqVkM1R2Z6N292fnBxaz4xPEJofEVURVhQVlh5dVJfSUlqaFAKejF8Qz81U209SSNjY3ItYnMo
eW5uc3YlT0pRekR+NzNta01yISFocDNkeE1hbFl8RjJNdTx7e3VOKj5FIT1kZ0w5Cnpzbkx9WmIr
RnxgczJYbSR4WjFKIStUVXpOPH1vS3AyIV47elE+bWJAUyUkN05oSVB1cmZSQj12VUcqVjtEbS03
TAp6NGJ0SV58Rypxfj1WUmJjVDAycW5uKUdHVTU/QS1NI0c5aExIT0xiMURnJF8zWSU3MHRXVU84
WjQ1cn15SlVPMnoKenNfMmNJN0d8IzwodC1XP0E8a2tsbWVHKT92fk07dzd1dShVLVhofTMlWEBG
bldRWnFsOCUmLUx4JUg1UEBZeC1wCnpoQWhYYXE7fiRPcVZiKy09QTJMTzh0OT1UNypZX2QpR0c3
JlleSCQ+Pm43PFFkT1ZhVkBKSVVRdWZmVlRecEc+Tgp6PT81aTdxYEdBKVFyRG5zVkEoU3I4eGQk
U1BXUmBoeyMlcURULTBSTThnbkpaTzIxPjhAUmQycFMkKDcxdV8jPHUKei1KR2xZb3cwZTV1YjRa
Yj9vV1hFK3gzaTRCKGp6Zih+RTxuJFNDdG1oRGVPcHFxN2ZmRiVaR0pwbUBjMVF0ckM2CnpDPnYq
KWZIMEk/S0JOfSt2KnUpRFV7XzxjZjEzNiNpYnJpQlB0aHRFbVpTTlcxYWFUaXd4e0w8I35rOXdx
b20xJQp6PCo8TW1BTXpkMmIqK1JxeWAyOF5EZGNxPE8lNyMhNnAxUnIxdEYxezQlMS02UUc2PzE5
YHdVPj9BPEk3X0gmNnoKenF7cFpiQzI3OGdQWVlRMj5WKUckWTluej4tZGdeQj85d34tNX08M2h3
eHM4Ymh4OCtYdFplPGBAViVfM1RIZ09sCnpTNGQ9bWFVZHFzK2JBKGZ6QGZ3QU9JUmckdzhPOVI+
YSU7QCszQVI9cUlWekNJO3xHJnU+ZGhPKmlNOGhTSUYwVgp6T1JHYmg9VFRxR188aXNOPzU/d3VN
NV5LTkpDRUY8Q2lDI1M/RkBrMylJfX02bV47cnMkRFdDTVAtamhxSz5lZVQKejJYNCp9ZmxwMiRx
Qn4hJGUqci1He3V+XzN7REwrbiYtcm8tTmBBe0Y4d1pLRlQ7OV5eRDg5Xk0oWjdwWVJ2aHZvCnpC
UzttLSEtKDctR1Jiel5BQV4wYCpqQ0VHenU/SHoxX3dlI0dYcnB2YE43bDAjTW4zVXVEbjgpcGJL
aUEoa3ZtTgp6Tn5RWn5Bdz08ZzNAaiVXTHxyUWYwaXkmT0khMU9jcGJAOEBFSEk9QVA9ZSpfa01j
SkYrP0pQUWIzdiRvPncwKlkKenF6Knt1aiY7NGduKDBnSHtWXnxkbF5oe0hGKUNmWjF6eWFybHMj
JDQ3JXhaaVpiJjVLe3EzdzkwTDJEXnpwN0tmCnpjd1NhTWp3KSlmdHNfJlNBVHFoNWRhcUVadSEo
fCNPSHIzO3lDfVRSVCt7U0ZiZ0Z9e093alY3al9CQHVoKzxkQAp6MnE8MlIkZ1IobG5YPDIqPyZE
K25qSXI1fjR7fG87anZfVlN6X0BSV213I3gwYDxWO29II05CUE1CYU5LJTxuI2YKemtrayowV3Z9
IzlTN0txcW9wQHkqMFhyNTVjXjYzWk9lNXRza08rRjU0e1Z4OyheVW0mUHk/ZzZHVzhXemp+XlBw
CnpSMDEwTzh5KVdQZlI4ZVRqfEB1WTEtY1Z7LSY/aCtqMGF7KFRSZGdNITkrZ0QrbVFBKCVKfksy
NXdCQ21LRkxNfAp6ITFWd1ZwO2ZhWWY8SXVJSV9EcDcmUnxgRzBFMDlJJm02OSt7aXFMVDw4IyNm
eyh1QVg8U1A0bFZ7NCQqTEZSPHoKekpRUlo4ZzlMZ1gwbX5yfmVadHkoWENFSkd7JjYqN2kzUmlE
M3pBXmFtMVdqbUVsbWd8TSl0Q2UhSTUkIzVLcTRWCnopNGNlVGllS2ttbX47P2lUQUktTmE5R1pf
c198a0QlTVNvUSZrNXJwM2YoYEYqWnlPcz0xej5EMH0jTlVgYno5IQp6SCFBYj5yeDRRWjx9MGk1
X2RuN1VhPTd3JURAK2lTYGZ3MCEhKz8zbylJbkwtb0JKUmk1Y2REKCVvQkJte3pyeD4KenxKc0U4
PHBBdV9MbDBlRSRgcStYPj1sb1QjPUgrbCgtZmRAU0stZDgzR3R8RDk1OCRDMW01Sm1uUSElTlNy
YUAkCnpOYHY8OGB9aGJQeyFnQmxuXkpJe01mPSEtLTJKIVdYamJWfSEwMk9LQzhRQHxHNkR9bldx
NGJkUD8pKGQrWEUwWQp6bkk8aX1RbD9+I1pUSTc9NkNKJUUlYExfKm56fXAlQHJQdXBGeSozNVFF
PmpCTn1OJHBjTi11MlJrenRRZ2EpZXcKekVTVXtadiFUTTlaNCkzcHk5V215TTVHdHxjcD4qYzBy
UWQ4RjZxckI/TFZ8MlI1SUJpSHQ5K1olQDd6NjU0dks9CnplO2oqezk3aSRnUmsmNnwmekY7cGNA
X3d2TDU9bEgmUFg8ZFl1PiFwLU5WK2dmPVI+NUh8dyZ5OEFofnoqKj5HQgp6NDVUdEtjUntgcnk8
RVNOa1ZaPnBYUWxhd3l4U0R1JWU9XjJDMiszeldqKlhRM3QpP1dZfismfFN+MjNgKSM+WUUKelR3
dWBxMjM1ZnhaLUojPEojYUNSemdsTFh8SzVMWmpqM1lmOU9ldz8kb3VEZD5INDQ5ZGdvZ01EbktC
JkBJMHpDCno8XilAaFQ+bnVWMXtDa1p4JGBeOztadGAlRVhXdXZGODt9Q0tlQz1ZX2tzP3J8OHN7
TCF2RXxqKzAyNVVtPGQ0Mgp6d3BgbCVLU1EkcHpuK159ZW0oe2ZDSCpSezN4Xnt3bkUoZnl8MTBU
SzFFY1FIJUdwYWYqRnZCdW9+SDJjd3whUT0KemZWWDJEWmlTZnVXZVNneXhmeE93SyEpMlRPNGd3
ZHRySnRsfDZRTC1TQmhFK1I+cisrYT5GZ3UwfThoc0tabWpRCnpXI0I4S3VGdFB2ZXwtYiRKYEtt
bTIjQkpnMzw3bzNeIyRDUHw4QVp+d01zen5jQShkJFN1eWZFPUsrRz41YkA7aAp6LU5reD9NZGAo
dHBUeUQ3bzUjeiZPN0JzNkM4KFFsb2dAWkchYE1McG12ekRjI0dxdyl7JG1sVk1ncylEX1ZsJGYK
elFHbDU+SE58LW5sPW49I21HfCpJMzhhTlA3Sm00RE0oRzhTQWcwdG1FWG8rLWQzUHYzYTx+alZk
Yj1gajRGVHZ3CnpASWtLeUstM1M9ayNlUGprU1AjYEM8YkJrT3dqdzdaRFlvOVRIPzN7TUVnbzkm
WU9NXnJUNz53YTM5Myg3dUFTcwp6U0YpX05EQ3MqSms9bEt4KEwmS0dRe2N1ISQtKyRAUl8zLWRt
allNeil9P1RCT184QnJycVg+b1V4QHdIMkBwZykKens1MDM1e0RlSTE7bHREZTBGJSNtaFJ9OVBe
QGV6RzRNWik2NHFkdGVeck5KdCZtQm03cDlEQmMrX3ZmNGFmJl5ACnpwWn5AQWluTjImSCNPOCoy
UE5pTHIlJFAtQmYqaFg2PENLQWI1bk90NjwzMGxOUSU1SmpXMTBMNi1ac1k7JC1tPAp6MVZEenA7
Z0c7NFEyYVhwJX5zR2dtMlYyUWRpSm1lSiNUeW41TnFEe3NLX3hAMTcpUjFNSCtUOVNSfWJLZXdL
PyYKelBEUztaISNubjtgciRKaVItYUZCZE1LZTdDMXAqMGNVXkpINmI9fFhERlFNVkxiODJtclUj
eHRVMGg8fVJWTUtmCno9dVpGLVhUe3dHTE5JbDU1WHIqTDhQKXg4RzE9SWRGKE5laSR7Mn1yPDxF
dV9hezEwJVMtY0dzVl9CaW1RQUlSXwp6QT5IeWltY1JUSUI7aClEWDMwSXRHcnBTd3BVZ01XZFFf
NGVzbGlBTkdpRSEhYFQ4WH1QTlI7TztLeDJRZUJvQXUKenhJcUlvR0pmOD8yVjZ3KEc1cVYpMEJP
MTNeXlZKYWt4PXdiIV9MPFpIQ2p8VzBuVztlVn1uZzQxQF41SjhObEpGCnoyYSlNfFhKK2oke1hH
OzxMXzJtbGJsZFhucWQoaWR7QHtoey10QGUjYGlnbmNvZVM3S1B9Xjl+dTVWeUkqPnpqKgp6dndL
RHRAfSQzfih2NGF1I09AYFgpXz5VN2AlIyNQdW8hOHYjIXpsUTNoIWdEaXl2fFRsfX1MO0JkJHMt
d3NaRiUKelZJaj99eyo+SjZRfFV3Rj9ndD52WGphTUdkWUtOMzxmbj9qZWd7eSk9PGd2NlNwcjlS
dGZ3RiExNHtjM15PTS0rCnp0SGNtVV5HQyV7SHJmJEBnT1EjRDhDMyU4ek1kTmMpSnUqe082NnAy
bkY/Zm08TmBwc2JURjJCK0wkcjFEMmFqTAp6XmdHcXVoeyhaJT9VTFZiMTtud2ZHQz9Jemx9RzxA
PVBtTHY5PE1qRWZYTWh6ZUlgOTEjMFM+NjAwfChxVk52dHMKemlMQXpGUUFNXjxBdVhUPT9DYDE1
PzVQVmszPFMkbnRKMEdWfDJeYHlZWD9nZVBsUEZIZEE4MlhudlZObG0jK3BxCnplITAxIztNKlFY
TzhzPUA5WTxhVEZBPHklM3dteENrOzlUXjt2Z3hxRDx3bStOc096KkBqY0l+UDxvQ2VjYCRnKgp6
SG82dk1ZS3d9SmgyX345ejwjTE5PXjNBSkZyfjt8aFUkd3tpS2NxMXQlPSN1VjI9cj5PR3RTM2Fh
ZXc0K0BvU3AKenZQWlI+S1doO0pEYnZkTlo4UCFiYWBWeDJeaj08a3NwJFFGZ0FYVkBsLX1XR01Y
RWQwZU5heH4rcS1vYVhVQkllCnp6SCM+My0+Y0FFNWM4N2sta0xsY2o0WFBnJiNafnpwZ0deQipa
ej9DMDBhLXdqP3RKbXZoSDw1ViNrV1k4Z3QpSgp6Z34xSTxURy1hOUE/NUsrTHJmTm0jTnx9UjxF
cnBTalVqKU8pbUl0X1FQUmR3blRLYkx1SE5NcnlRPHBGR047QEAKeihZOFNXOElRPXktMiljbilX
NWYpb1R9KHxScmImQmBRKnFeUEkjIWtQUSZJezd7XktlU209MkcpSXBGUll2QWIrCnoxPT9YTCpU
NzA3X21BfUROVWZrQj1sNEdKJk8oV3VKa3NIU084MFZ2ZDI+TVctMGFwYjB3XnFOd2ZrWFJBPT1Z
Zgp6NntWalQxNWpLdHVZaGQ3eFJFMzgqWEA0R0VeblMjV28raSteO1p3PUs+I1Y4cnI+NyVvc3s+
S083QkF0OUNma34Kenl9VERlbHxsbmt0ZWdsZzB0O0UxVVhWU0FfRStRa2JpQ3lGdF5uX2UkI0pa
WT1JOUB1eXk8ajE0K3s/aj1yfHlNCnpHQz0mQVBoP3thcEtzISVSIXA3YTNrQjZMbkBmXkJGdHsy
ZzVgKHl0JmEmZ05YViZvKXRrdXhBYX5OWVdrbEpQTQp6KyU5cDxOVUhMV0xpKXM0amFoaDJufU9+
SDFaV0xSeTBYdWJBRmpNUkF2Yk9NQD5IYkw9PG1kaHc4KUJuQypqO2QKeitZVjxRMUpIVEI4YU56
VUtibGFKKEZjNj1qPyVYU0w0MkRKa0hJT2RoYWMwKnhMMG0/R1V7O3YtUF95Y0ZuQD43CnpLeEFi
bit1d3NneW9YVXw9RFgmMz0rUERQPFQ9VzhLZnJscStqM3VPWns0UyQwJVZAbnBoa3o4VTxxdWEh
VWJBbQp6cFoobEA8QmJZZk5MWVdnTUQpVUFrYy0yYHliWCstSCRBV0dmelA2N3xBcj0jWn55YSZZ
WT5TNlNma19jV25RfDMKekxTMFlxek1FKzd5KlE2NGJRb0JseCprPTNXKiVMdTFlITVmVn51RzRY
a1luSW45fERmUSVgKlJDdWN6SUktcTZfCnpzNXpUX09CZyVmbG1hPE5qcmhFRXQ9KmlDYm1CJXY8
TzV6cE0xUWU7WEQ1bXheWmNJfj0kSF5SK25SKkZjeD88OQp6b2RUdmFpb3V6KVUqcnNwQjNlaE87
Ymg9WiZxbGdWRFMpckxGciZUPCp0T1pMTilVIy1OcCp5aGJwYFZHXnI/MEUKemREQWAkJiNpTz4r
K3UlamUyfGNNMk85OT58MmBERCQpME4lelk1bDhKejZqWUhhWTcxSi1DUW9fSF5YSj9VQkFuCnpU
bUlSbzFHQDhWUXRldSlfdDlKc0U9Mkg9aDs2ISZ0PTlmQl5pTTNeeCNocDc2VWV1YldFZzF2Pztt
U1A2cWpqPwp6SClwTmAqY0ZZJiNlcW91S0gyYiVzLUVge09XOXRBJlVxK25RVEhGa19iR1J2e0BK
WmUlRCVCTHhsPjVocDV9YE4KemB3NTZQJn05KV9KTUppe1FWRW8kMmshb1pHQHE7dWJ4KXRKbV5i
Z2pQV1o4RlFhK19MaDh+ZT1NQHMkaExfLWR1CnpAI24oVm1YWkBCfEZfc1BvN3JzelA7P3hadSRm
N01VMD5Fd1NvZ2pXRjMheSZNJmYqcSNTMF5MQDFEVUJZfmFINgp6dTBrMyZUI1dxNnMqfVRAVkF0
Vytve0hIV1FAT3B1RWspb2IlZVNtJHdpeDd5bD99aTxtRWY0NCE9bWpAIWtxN30KemAqTzlacVN1
eGZwZndCUztASkFCUUw9ajhHcihpcmteX15nPmRiRz1kJVNzMTxHK3FzNnhaVE9kcDF5UHApP0pO
CnpPe2khJkB1MTFWKWlkdjxreFIxUTYoezZEd1ooMmtAeD4rST9AWFgqVHwjPC1FbSp0O2F4RyQ1
K0IjOFgxM2JEZgp6TDM4YipGNWluYnEmUTs7XyY2TVFURlJke1AzIVF9dSRKRDNYKl9FQTRIZ2Bq
cVZte3xhWngyMFBpWDxofDlRUTEKenlqK3N0SzYhbytqMiheU2xAK35vbF9XTGgyR3pHZ0Q8JnBt
JCglOT9KIShlaTB8ZEVONSotY3A5fEg1eDJVeyk3CnohTko7O1FveGp7UGMrNVAtVHhaRCFNIXgx
ZGYmIURQfTNyWG1sZG9wRjJTcE9vT3BJVlI1KSs7Xyo3M314fFhPaAp6PlpLYWxjVytRTElLUTVX
bl5PRHZJfTMpd1NCRzVoZClAOU5iNXRnXzwyTlBucTR8cEJDblNPWGVLPHspYmF1TE0KekVpem0h
SnxVTldVcUNybXcwYnBSKE5fKH0rOSg1akNEfkhCO1FkMFp8RmxwV3Y8PmxwWFBRZX40cHojb19M
O0hRCnpaMSZkbTgyeDY7JXZfQT45Y0Q/I1NEU1F6YWliR250RFRoelFyPmpiKWVgeyohT1RvdVFp
XnhMeGtgVTEwans9UQp6Pil2KXYxRUoyKCRGQzQhV0d2Wk9Pc0tmJFE9a15ONmxkJTZHJHQ9OHNa
O3VzVTVTKUJrNUtPUTxKdFpjVSgzYXAKeld6cGRvOyVKV0FmTyk2QjI8MVZzaFZpK3E0bnQrViQk
flRvKlpYfSkwYDwjJlpja0VlVHB5KzdtelZyVHwyMSV2CnpsUmxTSUk4VTZrbWEpUiFodEJidilv
NV8xWFdiZCVLUEBVTnArS0pjLVFwK0tONU0lRiRhM2FWIzQwYlF5WXtRLQp6OCkoZTtuaTZgPjRg
ek10XzV1dnxCT199KlRHM2ZnJX1uP2NxSWY9Wip0VW9ELSU3LUZUUlhDTkcjbyl7eXFSI2QKemVQ
RE5EKXVtPnt3JDxtaWtEbkM0WUp8ZXNWdzl1NT9ObFByMisjV14ock1ZJShlRVk8SHQxIWpDPnQw
VHl3TXV1CnpJTTkzNTV3R2MqZUhfbzgmPCZqNUJgNCZ3RTVaeXI4fEN8REV4UElONFZDbm1JXlZM
P2JXNzEkeUpfIX03WllXWAp6Wkg5TUJKeFZTfSM9LVBjWXZVQX1eMjlUSG0hT2B6Vz9LWHYoKzk1
WW04SWtMWnZAUUF7KiZWPm5MNjhyeiopTDIKeiNAb3pZYGVVSSpSR1BPOG1rX0lPRDZgTEx3WXJ2
YU8kYXRMVENycTFkYXtMakFtJjZXYDJUYyR0flhGKFVLPkB4Cnp2S3xnZXA1eHpzMXpAVjRKRj0k
SWltdzBuJUBEbTZ2YWdiRUw0OWtLUXxEZiskMWQrIUgjTlRHUk96aypLYVh1Mwp6cE5xJHJreXY+
VDspb1ZERW8rYjBAOHdwYCFMUk0lJFI8IzE3cHoyYWNwa0xZO3hLc2dRdytaUmBqYVIhKERTekgK
elU9UjRabkJCemNYTG1YOVlLfXt9Qn5BLX1WS1VyfiF0V28lUFl1VWRZI3ZERjd1KHE/cGdIX2pM
VGxLKz1RWHZfCnpzIyQ+IVlzSmJjPiZFVUtxIWdGYlNSZVk+RHw8aC0hJH5sclJlKHRaT15MZTNP
XkJjeWlTNGA8fEdTUjlKc3RaUgp6I1VLPGVMdXxtRCFWYjE8bkRvY29KZjxTWDhLeD89LUFtSDNe
Q3dGbUgrREQ1Sj8ySDxoQGQlOSpVVnsyamBLV04KeiRpNUNrMz1gKXYkcVpRfW5+U21OVVZicFN4
VTlmQHd8e3dAaihxaHFEMkhjVD5GOSVRZCZ7UzNlKk4zUGtTRldMCnp0WFZUSE4wXlR2PFEqWV8m
VkpwfXRueFhyKWhnKEVKcCtXP2MmQDxgPElAeHw2SjxMSzVSRWp5Ji0+aE04dmV0Xwp6X2pWOH4+
T3tFNUlQOFkodE5HV2wmPmVBWGtiYjheJFkrQXhvdSpfUXVwMl5jOyFZQ2RCY1BUKmdgYiFXMz1A
I2oKejhmZ31yNjwwY0A0ZmJ2TUFIeStXVSF7JEl2KjU9aG88RWRySUtkYVloOT0pYURXKHdYQlR9
UlE8OFFeS0xQfEclCnokczA5VFBWNnQrKzFIPV9sJEBScnAoZVcoN2l2bmlvY01ed0UhVHRPZXpB
U2F0TzlsKnhVNkl6OHpRcVhIaHpCSAp6MmU0a34mRChadHUlVXF+WDA9dmxFUC03KEdNZ3t6UCs2
aWc1OXhTMExDbzFwUmNoSHVUWEdsVjRhUVNEKjRndj8KenhAYXUlKlczdVRxa0k8TkFRQDg+I1Bp
SER1aypGRmVwZG0jalVpdnJIWiRJNCYtT31LIUdyTV5zUi1VUVVlQ2ZVCnp3VmJ1dEN3Q3lhV09H
emFySkNCZHBzKnFheVEmP1hNdiZRRDZVbUliWSQtdFkkQ2I3JWBVZWwpNDhJSDFAT1oyVQp6TUl4
Xz4+JGFfQ1NoeldCZVEheS1XT3VuIyh6NG53WXlnUGVGcCg4R3w0fUNPWCh8Z3xWKUtmXmBLMVN8
PkFCbEUKem9KfWB6Jmw7ZTdYI25yajsjd3g/YU5fKC1wQWsqYFMyMk19TmJ7eE1PQ1dYVzxUQTNV
WC1VcDhFYGJEZzBgakM7CnpXKiVqPTFiY1lMITkoLUtLZiVkZHB3UmlDdVhQO2FBWTEmYykjTXg7
ZDxodGxXRnleRCU8Z21vcE9ecntgTihPJgp6JEcrVWBEcmx2fSomamQwJiVPdF9XO3V2bk5feFly
Q3VaSilUQ2ckcCo1dDAoNWpUdFRLM1NqNGd5SF9TJmEtMk8KekdPdXNra01mPkJnPnBqSF5yPzxk
PEJ4WGs3cytnMklsQzZgalY9NFBhb2dmLUZZSDVhVUNeVSZUTSFKY19XSU59Cnp5fGdobDxIb043
I2p1fjw4UExSQXMyNj9OTEAhXyVCSHJTVUhFdkBPelNEQ0NpTkplSUc0WmVMblJYLUdoK1JHUAp6
Ty1fWChgNnBAYWlPfmh7U3ArLSU9MSlHZXpodipjSVFBKGNDQ3ZQT19GJXleakR7Ym5IUmgoaHN5
NjtNYXo1U2IKejYkYzNtQnhWTWZAdSglP28mTSFYRmlZc1lCcihIMGN2SjBtUEB2eEJiUHsycWJl
Z2MwWlBGWkRmQ1NuRWU+VlBiCnplJCFTdkQyOTZ5QU1FbElWZ0YxO0lyRF80R24wa3IoKEtRa042
YTxsXnYyWVpObns7dndgQilaYjl7MVZeKil0Kwp6I3FsaCtreFhyKFFQe2xue3F4PTNsflAtI0VZ
Zk89S208WUZlK04mTjQkU0g2bUwtRlJNUkJUPFlCXyorJFojdXQKenZvUkt3WV5zQUw5NkdsQHlj
RC1SLUJIV2M7RElFRXxGcmUhWXE+Xi1IX314eiR0cU53O0x8V196d3BVN1N0ejJTCnpPI3J8ZXw1
OU5NSFN0QSFHfnY2cUs+TyE3e0hJXzBPbn0xOT4tWXlGT0dvWl41ez99Qjc2c2ZrUCg4UDY2NSs+
Ugp6KGp2PXZKbzVzdGhlJU4mWFFsYUp7Q3YtVl45IWtvMWIxWCtRXnFVLUw9NyRMRyQqd2pJSSsq
V1p+SCMpbSRVeG4KemJtRGohQWl1Tm0jPHJ5TVhQVjdadHVPMmV8RDJ5djZiVEY3ay0xLUYtLTck
ZjteKXU3TFF5bnBPU0NQIURXUStqCno2MXhfXkAtKGlaPmZJcileTzZBSyhLfX51N0U3TXZzdnBk
TzM2QHdiS2V1TX5ScWgwUmlAPEtxTXItWFYpKE80VAp6UF49dGB4QTxIMiN7TDVnZ1g0VGpYd3JA
aiomSmAjeXdMancpK1c7Z2lZTlF0TWEraHFNIzFTITxlazJpalg4a1UKejF6QmFDPig4fGJCYz95
QzNlUk8yYUM8ZWMkWlVHT2RHPio9WmM4eThvbDRkOXM/fXN8eHVQbEFAV1Q8PHB3ayhnCnokfDg4
VytpIUs4V1cmPCRsTXFnamRxdjRVV1NgWChLd0o2RSQlTWw1JnFoPlIzem5AXkpSRyRgU2gjfkE/
O0Y7JAp6T1IzV3JFMlNfYSVLZTJaUnwlU31JcWo/Y1k3SiNqTEZ4UllgeE48YUF2fUQyTjQrM0s5
Tlh4VVp2REFhYlZKRUQKeil4eClQRX05PEI4dEVfe1NWcDVCNSphRlpwVChrN158S3xjRUlUYDIr
eEMpRXRGPCFNK3d0eTtKKUsqKy1kQ3JpCno5eD83TmUzV147SUMqTCgqfHMxVXlgdTJeeExUPEtu
MXVXSnMySDZQdUpfVj1NU1NWbjkzNVNFPHt4aD9KU15megp6YU8hUTNmQiMzMWN+TUUwLWQrdTVH
b1N3cFJLaCVrVyt9VnZHYXBfM3dXeDAlLUItVSkhUXZmfG59KiQ0RXh5SUQKemApSkhJVzdXUEB0
KD9QQCpuNj9jb1I1bHk3S3NleUZpKSQreVohbTU9MnR6SDtmVCsmUURFIWFjeCo/YmhNTjdgCnpk
OTY/ZTUrNTg/dzNNNF9YMT4/bmN6a0QqVGZsUHxqKkpKTUNrfSViSlRBVTlAKndWS2VkbDc4NHhj
SGhyQDBMeAp6PEluZl5CJSV6MFohOFl4ZytDSTFaRWNhPCRAVDtyP2tJfCVWS05rWXdKcisoOXJ2
PlhjJn1oKjdUVWhhQ1F5PTIKelJCOT1aMjBFUHtgcG1KQ18wfX1+I2YpTDJEQlNIQWI+LWFDYWJI
b35ANWVPcEpEcjNyIWFKaGdpcXJxJGBRQ2tXCnp0OGF5VSpzXzZjdEw9fDNuKFBLJkZGQS1gO19k
SyZhe3NPZSN3KUF8NH54X0IkZ1VecmtAVFVycFFMTXY4XyU8YQp6NT5IIXszOV97JTFxJTt3YzlI
R1M0bUF5SFNoRn5+RSRHQmhBOVZoPDR9P1VWIVFsQHZIdzlCN0ZHUjE/ZyZyP1oKemZhNDNYWXQ0
VHFCTW9zZllidn57SUA0S0lDKGUoODhwP1RQSSVfdE1HWGV5cG15cmYpN2U9ZkhPWU9Hb2NeUzhO
CnpxR0NmTCFRLW5IUkY3VTVaJDQ+RF90JEtARCt1LUY5MWEhXzt9WCp8MShnNE9pYSVJTjg+Tipq
REpDO0pqRjAkawp6Jk9mPUx1IUg2Rnhedl5jQE1FezxVTn1eQihGY1EmZUJ8TCVye1JSSkQ5PjtF
ZEkqP2U9d0xLcTBsI0xzLXFWYTgKejcmenJ8P0ROQjVLVmdsM21kd1hPXjs1I1ZsTHdGZnVhb29l
cnV6Uk1gMXsoNVltYmIzJV8xQGkqJmB5XnBYfHNlCnpCVj1TfVRfWnc5QnItIXFYMl8wOUhyWnRG
ODc/MVdVKyhYOWArV2FgLSNQYyhiSS1aMntkflRqdWpndyNBN0dVIQp6fEVTY18pMiNpU1ZZfVY4
azE+NlhnPnRFaF5JPiU1JDxEZFkpbj00KGtyMTE7cnhHZGtEN3tsOFgmRVBEWXI3QVcKenclQTs1
O24+OVUlS29QNXBpe1kzYGo8O3xUNSNqTDxsR21kNzFMTS1eTiNLc3M/diExSH1mSSNgdDZfKE1R
ITRnCnpLP2oobyFlQWwpMl5tRGhsJD4la2dabj02TE5jYDluU29OV2JFOCRzQFJ8biVQVzFlXiFx
fDdJQ3pyYGc+MWVoegp6UmpCeX5iTmVRVTJ3QWl3S21mbn0rYWkzR0pRRXozZWhkVkpyeWhKMjAw
LUJlNVIjWGBNfHxYXntFYXVnJCpUSHEKekw1KkRCMW9XYHE5Xll0Qi1LdUdsVzRYTGwkP1BRWFgj
bEc+RTM2KWQrUHpCSnAybylReXdDNlU/SkMjIUN6WE5SCnopJmNIb2Awd0lZUE5ya0pWbTwxR0g9
M0BqS1Y3TihpPDFSR3JGemRxRDVvOFI+Z09uQENBT2xSI0J0QV9HbmE8Ugp6M30oQzFVTndNfEtt
fmtMYlhMPSZXcilOWl57JE4tI09fO31HYCZHSml9bnxPYjV6S0J1YnJ2c2dleVdfVmFvR3QKemg3
YX0qMUkyXkU4V0whcnMrZEdHTD81UDRZXjl9U29Kakt6TCNxY3ZXVSRMP2hmNXlveTRsPCV5ZSor
N15pfjdKCnpXRmFDVlkqZnN8Rnh6RypMTWNRbS1qWGhINEhINkN1WEhELW5YTE1XWUxYP2tSWDFf
eHVPK1deVyVCQXlwSTF3WQp6ZlQ2QXIwU34wd3lRb2Qrb2RZbzlqSEVHPSh+aEZ6eE8zVWVNbF58
WihQMEMpbiNyQkNSSDx5MVQmeFV1dTYlTHEKelBLb3Z8cHNZMWMjbGZZKiNfcEtnOGBObXRHNXt9
ZDMreD5xIT19c3E3PVVfOVIodktgbzgwN3BKRilVcnVqMHpxCnpPMjJ7dz52NExqTVR8WXc8Wil5
Y3B1Q1ZsUnFle2hBZWFUKVRTSihxRlRWSjNMdjxZTjszYVYyKWR7ZmJzbTJQawp6Rl40JXVGYD0m
I3soKGMlc3V1fmdOcl4mSXYxPE5QeUVTT2FKcEoyP3RweX1MeXRtU0RqZm0zREdfKnhoOFB+NmYK
ejYrTlcyU3dtZDY4Rjt3Xj9oTWJVaHY+MFdiNVJ9R1hETD8yJkV5NkxEVVNQMUI0MElGKHRfTTFm
KjdRJHU1c1pfCnpiKj44YTxpQTFtVHI4WGA1Qz5WdnJLYjIkKF5wWmthUTRFU3pAbihyMStmJVlP
I304PV9tTnpzYSNTemNDbCMjfAp6diglRDtNN0V4PDhgKTRCcXoyRVhDK0hLUjtPcGZhV0YjM35z
bj1neVh3OW4hdjFhYTdUY3YodFE1JHlAP2NXWXAKejdLNmAzXnhfbVYxIVFeXktKcHRnVUFCQlM5
bW9Gc04kWD04MTZuMCYydTk5UFglUSskZmExNnVWaE95WWA9MUUkCnppT2RDMjNhM0BwMzA9VzBt
YDd+Uk07fWJad3NYSWZvIUF3Z3NDaEU1RjJhZ3BOV1YoYWdtan5vUmo3JHoxWXkmcAp6a1A8Y0Jr
RlRHa0JDbyZ5eWc1IXlXdndqeE82fDtSLWNvfmRiJG5XfmJ0QkJ0KG5keENYTyl5VWkxIWlHPSM7
PUYKej1CdDcyQFVfVl80bD9Tbj8/Z34xeGN4PXV0K04zMHVAR3ZIZ2cqU1RaYE8+YWk8bUc9dWBV
U19hfjB1fCEwN31FCnpGLVNgPEd0MXY2YHBRWThRcVFKXkRQX0Buc1pJaVFjNnZoOG9VVE51Yjt6
U2ZeZ0Q8NXs3WHd4ITRNZCFOdWctMwp6UypaSHpidXJkcld6eU8mZV55STNxQH58N2R2I2hsWEAh
O1goayR2N3p4cFM+UjB+U3dpIypUYTNwfHlKdzc7aW0KelJLXyhGIVNINXo5aT5oJCtIVColPDFU
Km5KJHVUTmw4fVNQbSNIdiUrUHc8ZGpebzhEVyF5Q0ZhSC1kck5WMjJoCnpZdXpab1lgSTZHZk8/
elktVkpOQTZnaUNLMHlsOXQtd2NSM01NWnEmTS1hcnptUnAxbGhTPXMoZnxKbktIeng8Mgp6eld1
bzZNM2VLNih9Z141RnF9NlEmS21gbjNXeEtDQmdFa2Bwe0ZWKSskPHswRHFWNEdxPiNiUWR4M2go
SHpBYj8KelVARCFacUd0OXdMeCt1dDMwMUVZK2whYmtoXkVYWntkQ29eXmBVSUhpcy0tTHZgPnxQ
JD17U3NVTDJOe3BxVFllCnpGX30jKms5TyZyVXlkdl9GLV5qZ0V5RE9BVlk2Oy1DfUJgVWdySkU/
PWRHaWpjezVvMSgmKER3V15DeklkPzspcwp6RE9Edl4kaTRMTEJTTVZjZns3bG5TUSR6Q0l0UVh0
MHE7ZWw/STl1PEVsfjspSUpPRWF4ZjJaNjhsIW4mMDNMU08KeiQ5dTl7WHtvOV9wIXQ7O0s+YDFB
b3kmQzNBQUxQbk0/LVAtQElfOUBPPWd2UXM+O2FjNGRoTXNWeUJjTztJZlYoCnp3YUJxNitZPlNM
RTxZelNoYihiJFNxK0BXZWQkfCRQfFdCRWNLUlR5JmBwR3kwPkVffEleN14kKn4kfDBneDFHbwp6
QW9gRGlQKDQ5K1oybFNYaG1VJiF7R19QZXJIKlFLU31eRFU3N0AmSU1GZTF6QnRVRmhyKExHNlpK
SlZvQnc7KVYKemIwJVp2UUl9YXVjbFlBJWZHSzgpSX5wMSVAYm5QXkdTcWJ1XiNsJn1fN2VVRnBI
PCMwQnwkSm4oZmpSJnhsZjc9Cno3YEIpMihjWExzTitJZXV0Nj1kRCZTeVAte1lrb0V5VUQwYyF+
PTIpPF8/bFl3fHlyRUZSP3g5ZTE3UHlqOVpHbQp6dWJ+SGx1Nm5SNVQzN1dBIys7enxkazIyUTAy
JWNmRzQqfSskO3wrdVk5UWooP3pKa25ZUEZiKVZ4fE8pTV9YIzsKelpKZyVTJDFIUHJYdSpXXyVg
MHcwVSM+azwkeTl8Iz9uV35uRnZxa3p8SlBJc14jbl8/UkI2VD1yWCEqQk1saG5HCnolTWNYKkhS
WG4qKUZsdmFzbjJ9MWc0e09SaEpFUHg1N2tFYHZeWGoqRjNAWU1rdmdYaCU2JWBBX1MwMT1xWCpW
SAp6YmFMVEFzT1U1dUNNeGpMKjhQOX5mXmtsZnc4Q0QzYzBDI3VGZl56aDthYVM2I1lFQWlrb1or
KWUyPTYtV01ofDgKejB7VkVSPU5Dc21PZmp3QXdQZW0ocUk4VzlGUkgtekFlS19fLVJTO1d7fSQ8
b1B5NVdqMFVxcD9PaExpeVY/MkpWCnpUZXhFNHdTKFgyckh7NGUkV0IyPnI2VSUzeygwMSljYipl
U2puQlpha2ImOz0+bVdpIXY2K3JlS0ZHey0pSWo0Vwp6cXFgPmtFI0pRWnpgN3ZiKF5fMXVAZl9u
S3RRQFFnZVZlR1RKRE11NEl1Y31iQ2MmM2E4YSt5byoxTmtzXjVwXkgKekpAKyQoY29QVWg8eGVn
NyZOeClzOUUqVmRkdkZ2bjNWY1dDc0o3cX5TNzk5R3xLPH55Sn1mcSkjQENOQGtgUmNNCnpTeHAm
eFYrQiFyJFNzQVFSe2ZOQUlfIzEwdUZ7VWA3QGxOITE1JnxKWlB2fX1nRXV5ZnpONH05UTFOP05M
a1ppUgp6bW90ZHwzSktRUmdrWCRUNSYmPiU/Qk4qXyVHTnsqMipCbyM+MCQjV28kZGFQMEJgK0ZJ
OTtzRndoNlFWeyR4I3EKenBic3tPUl8+M2NDbmx3Tjg4IVVraChNKENCdm9gPGgtamBfc21hQktV
bW5jOT1nKTM9QzFLRmAoIW9VcHhKckJWCno+VW9RRWI8NHd0WC1QVWJoe0krezI/fj8xU2w8ZCNA
V0YrU3tXJjxIRmt2d08hQDxRdmIrUG55WVVFYkd7MkJpZgp6ZSZ+cks5UiFLPnJycEJyJGU0Tn43
fm5SYUJ0Uit4T1lkPH11YihNSz99WXIwcTlISDRDRERyN2EySG8+dDZOYSUKemJBNmojUE4xdiMt
Rmgjez17aiZvbHd9cC1SdkxgTXt8ci0md3laR21pJjFeZGg8cGM5SmlpajdJe3ZJR0d3WGNJCnpQ
TUF7ejQ2cWo9TzJYO341cWIpOVFyKXU5eCEzfU5qfTMkKFQ0Mj52YD0jJlJ5JGdLdV4kPDUoOT45
I0FtJiVlbAp6NSp7NWp4RC1jP2tFZ3ooTjNVbVl7d2R2Vyk7RXFUOGVofms3fkRZP2B8bkZDJXl7
R1pZZkYqQk5fPTUmSCNRdHoKelUlOXBWZz9GZCVUcFlxb18tfm97WXdsUm97TSRKPEl4P2IyOW1Y
YXIzbCNIJmp0RGs3SXg2WWs5SEliUT8+fTh5Cnp2KEd3VG92MnVvb0JkVml0fVYmZCl3VHFwbzBH
KXJUVmUtJGJDYlZVVG1MNVJ7THZsYypFMVNeK0JFVmQ1bThXNQp6KGx5d0VQZ0k/eyFKP18pdiQ2
OWdSMHBUSHRxTyUxM3JkezZCMzZeMWB0P2clajwjeih6NzQxdkx6e0RUd3kqd3YKellJWDg9Jitz
PHVyXk45R3dpJCZxKDJSQjJBRlZYYG0xT05hMFd9PlpGbDkzeDlNVihWKXwtIXYxc041ZGdVOXlN
CnpGK2cjbDU1OSoqUWFhVUBtRihUTV89eEROSzJZTVBQY3whaTNfQWZOVUMoZSpQZSpFfU8pTjt+
dilucUgoTTRhfQp6Unt3bnApVDI5TWAxZztXQ0p7NTJvOHM4U2dFKj9XcHs5QWhyWSt5TiVGND5W
MSpIJj49Q0ZVa14rUnAjJUZLJHUKenlHJHhlcnN2R2leOUhqbF89bGIycjhyI0spWEdxZUc+R1hR
WXk/KDB4I3RWSmAmTzkoQGp3SXtJODhwe2hDKjRHCnpnZTNQYSprIXlqKk4pRWljbHwtQGMtdk48
VG00KVkjclpnUHY1cy18NmtjRjc4cyFzPzArLVMoYVBObD09b2E0KQp6MDhMVzgkcjYrQVcqOHd7
emM9SXVKS296KEtlK0AmTWhpRmtfJGV6ZHhueVlEV285TS1iclAjRjZNRjY3KDE7dC0KejVTfTY2
JE9KJSlIQzVqXjtxOC0/OVJONiphKn1YRldhMEpCWDk2UHUqaVJDMiREa2U8NyF9Xyl7bT0pKml9
aF53CnolUz9qRG5IQGBtUWs9bH1VKGV1K2E7PX00ZTUxelpIWEtHeUNrQE5UdnB1djMqaDxfTVh3
LTFsWWtlNzZNPDt2Ygp6Pz9YWVVlNz5AWCo5Zl4pVlY4I1VOcElMei08bXRxOyR4cUZpfkBGLVRg
ME10I2shMXN7eHw1KXJHRCRPcnIkLXMKej5yVVJXMkVqa2IlPUtIbWY7ZjxWZHU4P1RPd3NjUUw+
JWNmSitSQTNzPzxiMnZJcjBaX2N+MSpwa0ZlZTw/bXk8CnpDQG8wd2BPQnV5K185MXl2c0omVV9X
a18pRjYkOGpsfndYLWNxRGZGSFYlWEZvfj1RMlcjak56bD5xRTdtPE8wJgp6LW5hcGIqUnpWTFhU
O1kqV0JKZnFVYVYkOVlxOW10eFpmRDRQOFlSR01LMSgyJGJVcHtlQGF7V1daQ2lpcWYjI1EKemVf
JEcleilIJTZIYmJSamc9fDJpVj93Z2RSIVpSKXF6biNwT3xBI201Sjd2Q1EmbGVMbDhPcXR5U2Yw
IXFXNm5ECnoxYSo0KUxYJW5IcUotKHVpKXtweUB2PG43Kj4/VF95SUY+LXBUbF5lK1lOd1JeVWI2
e2tvJEI9SE55QUwhV157RAp6PzsrUEYwdk02MmAxTi1+WVl4NWc8P3dKT3dgSmo4XzluZyZFV2kt
OXgzXmI0NDA3JDZTaitJOWVGMnItOFBsaVcKemg5R0sle2h6bjBHdSYzNlN7JUxEJSg8SFFXIzlu
VlJoeVRDX0YtY1dTcnR5K0NOe2R3YG1RfXdxN2UpRjtHK3RXCnpqMCV+NFRmZ2pSU1ghVWcoNz5N
aG5WfTg9cGI2aDFiNiZOI3Q3QGpucE5DKHxeNHwqNUxsRmxaPHs1KHcyZU9DYgp6azh4dzsxSUgw
e2I8JClaeF89PWBMdEpEODh5Z3p+PDBKcHA8MT5gPGc8dmpQNyM+MGNGYn48MktUOFVgRlhhMEQK
ejhVVyU2YUJ0bysjJnZ8Nm1MOCNYPFdFfDQtbFhxWj1xcW94Rit6fXtyKnNCfU83P2l1UTVKREBm
Qk9vTXtpcFdkCno5elR8TGl8VVMma0lkRlFxYGU3c0ZQUlV8TXV+I2QpX3YoeCNrWGckPUs+Q240
S2kjN3Y0MmJWUC1IV0pgIXI8IQp6K0EjfjdGPTctbnt6fEJyR2EhITlEOHNMKWZ+TWM+X3QpZnVj
OVM8Wkh8bEg1TTFWVWE2VlZifEgraDxRUzs0UlEKejZPKn5lcGVpKFlYWTg5bzh5Zl8xeEd1JWFv
eTw/KVR7SFd+JFl7PjRMWD9PYUk5QkJvUFdpPmZuYGNgbVltY3ohCno1N0I0PiNqayZ7UEUoWXdM
MXdwU2VVQG5ZV2U+SjsqKSFQMTJraSQqdUh5LXNWMzl0Y0pqaX5hQlhfY0JmbjgqQgp6QXlebWko
OH5JKDR9fFQqREJPNWpHaUtwO3VuLSVvJjhpSDEwdFVqdShXdm43KEB3WEpFWjQ1e3FxIXAlUkR4
dUMKekskIX54YklET0tZMmQrUlM2O2VAcDBhWGlSdklDZ2NtbmA0MnZ8cDw5YytIbiQ9aGdMPENx
Pi1GT3NqQTJCb3lVCnpTJjl4XjIqUkVIWGZaZD5EQURDSiE7M0FTMEItPEJONiZ5RG1Oai03ajwj
Pj4tVDdhUiN3OzltJT5gKGVGVm5CRgp6K2FDSUVPaURvYURoalRYMCoqcEcoKyVtaGVMKEIqUnU5
LWk+STEocylNMn0zc2wpYC1GbjJNd3dqWG5OO3tUV1AKemJSOU1QSjhXIW89QT0jZChldGlARl5l
LSFDQDk8VXo4WEklMW15PkFtMzNVNV5fdFFObmk/THlsfi1OTyNDdzVuCnoqRkV3T0Q2V0dydTRE
ZktXYnRsbTNjUkA2UCZqdnV7e1Mja2U7c1UmLTN+aEdOan1mMXVSa2w9LWdlRn1Ga01kdAp6KjxK
JkAwWj5YSHs1N1FpemhoJVItYH5uKFEyYVJIWF9MYlMjeUFCVjcmTDVSbSpNQkdyZ21teVpmK2lM
USMmOUkKelg2aEJkcCM8VypgYHwmI1BOeDR9V0VRKiNXQVYxPD5+b0c4JGFXOWZWN2cpSShSX040
PURoUiFjWEBhVkZNQSlUCnp0cUdXcEAzV0p+JVV5fWkwZWY4P05hNnc1MmZeXzc4ZzlhPGIzSkdh
LSNMV1RUS2NVJTdibUM1LShLfmNXT3VTUgp6IVIoXnRDTD1IdFZxIyVVXlU0WjU8ITYjVFN6WmJ2
X3t3VENnYm0oZmZpYWh5TXFiTmcjd0JLOXwwSyY+PjxyNHUKeiQpeilheGo/RnR6eW5OTSV9bk40
O0JpWUQrSD57Mm9paWFkcE5JS2BWRj9XUzUxPEZjIylPYGpaOUxuVW9rY2BPCnpsWW9Xais3OyRL
Qmg/cyhNbkglPUo7Tzw2XnVoNUtCazN9TD9tPG1abGkhVHo4MmlPdVB3REtgKmN4KGV8SyE2ewp6
KTR2Vm47KT56fDRLKSs4K1l8KiNnfjk4ZjFqX21DVV81VE5UTW5XcWN2TlA2Y1VYTVB8RXhZRWdC
YEhJRm4wd0YKei12ITQ0Uj8oOSg8TX5+bWBHWGZvXmsjfDBHflMjKCljYkxFZ3ZgSEI0bmRZZ3k1
NTYjbktFaSRqTWdDIWoqaUNNCnojWmJUdjB0O3J8Rm5NeSVzTXxRX0VvYX41KGx7KHJtKERwYUko
alpSfDA1N1Iwa28jay0jQ0o4ayNWanNzVzA0Mgp6bjROdGpPMXJRZjB2M3JAPWp2dzY7WDB5cFpB
U3NTcHRDSmB2aXhgb2BhX3RYXjRhKCklcmMlRld3Kk9uJGtjZWcKemBjTUg+c3FeUT1VemgmVmZH
M2JZOVFhPmclXlZyZ2NnZDEqbmJrdCQmUnJ+czJNOWtiOHBhaWxLcUMxcyZRQXt4CnpqTGJiVEUw
fXVrOHszPXZRLXMwTD9hUzBPTnFCZWIhMmBtKWltTX1INGtMdTxsVV9ufW1XYjZJcmYlMXhNblok
JQp6RnpEVmt8MiRxNU90KSotakVwP0pKcCV5SUApbDhPX0o0PjtVNHM9Y01UVndAanVJXl97OHV1
UCY3T0F8TElIZUIKelMxdzNIME13RVc+YVJ3aFZgQHRxX2E9THJFJHk5eSZgMntHRmpgXzA3JXhD
YShLaitgQGNSK2pGJjgqeT9wO2hZCnphR0IlTGBlWVEwdSZIQUxSKWdNK0RURGBrY09+byk1ZGB9
TnFMSngqX2YrJip3IUNCPDkyfDVGNDkraV9oeDZvKQp6SjF2bURAR2MhSlJePkpZO0NHVGtZKjR6
ek5qRjFCa3krVlp4R3RZJEUqZ3p8YkJfcG5vMTUjcFB6WG04YUhpXyYKek5XM0RKYT0kI2RjN0Qx
TGZlZjRrdHtJRmhKSCsrfiR3enxIeGVCP3FUOGticlNreHxsXnhQYj9LdjI5fjFebyNOCno7blpn
MjBlZVAwYFVUZjw7SFpXSUl0TVNRUFN5cG04eUQ1V0NjdWtKaCg3cmJCcFE1JGpWOFojQSlGUU5j
WWFYYQp6STVhbUdXWE00c2U8eiN6TiR1aHgwLSFTYXp5Pm0rQl5VcmNpVkYlaEQhRjQqYTgwRncy
WmM4R3d0TTxAdSVzd0oKelJ5QmwxZnVZKTI/bStsJFNaRFFuS040ZnY0Wm91bGNFYCNZIU5KdXtx
ZUttZXF5VCphSzZOd0JNYChxITMzcF99Cno9fCo4U04zOUk5ZE4mVWc1P343JTBEQ2JDNEVyIW1w
Ozc2RHpYLUZlNmY/I0JIfX1GaVNVQFNYKFFPM3ZHd31NRQp6a19wVHFae3BQJCt8LVFzK197O0No
SzUyeTNwUlo7aS1aTEFsTl45fDNsUlNRSHQpdkM5VWp9Jil4R0Z7KXN7MXkKekpJTUVBS19xOTtL
SEN1dDRMQFR2Rn5GWDkpdzNIR0tHUyt1eWYoNGx1ZG93fEAwTHV3KTJTN2R7d2ZKWmc0KCp0CnpT
PDlOZTFiVzdQaFRSdj05R1JII2VJZCNBVVFZNWxiJlJUJVp+UUJKVlgqMFFzRHo2TDdMSnk4Vkdk
PmVycmtPZQp6MHljfjE9MUA7c3NCLVZYTS1yKGhweFZjKEh6fiQ8elZDMDdtIWRCPSU0VEx9ST5L
NThQcylyKFNZbExaO3lTPWIKeiRfNGN3dVEjbjEmKH0zQXslWlA2RlJrfn5gQzBNTiFRKXR8Wkdm
U31fQXpjZkohTTwkMmFVc3VhN3lfT1F+XkJkCnpoVHJ6ZDNicj9gbnZMUG9PV1RnNnZNYWtqVz5J
YXtmWFcyZVBPXk1wUUB7PjM8cX5PREh7U3ojMmwmQklGO1FNdQp6JnxUKWcqYyQyYiRQWTh4MUQ5
SGtoZnNqQ2U1fGdwI3RpTjA1THFoU3EmN0F6Rio3LUBwRjNaTypHaU08YEBLVzsKekdxJWxvKnY2
enBobGR1RjlsdHtLIzNWUn1rQWclK3t8fj88XlFlb2tAR3szLVAwe1IxOUpKczFXLVJFSyhZTHtu
CnpjdlpfSnUjTGdPTD1HVTdBUVc9fnIyPmliYUs4V3Y+SWRETVgqMF8hI3x8JlI/RU1hUWc0bUkm
cyRjd29XWTwrQAp6ezNKKEU7Nl94PTIhOWs4TUw1Zz0wSFV2cFhAITBVTDMhZnFiQENuck87ViZQ
WipTXyshKzBWI05PZ2M5MENSXnYKemFxYUZQNnh1OEBAYHFQX2gqeTA+ak9DTD1iWChRTEAxamB8
Mm1Tcl9paGxYVz1NIzJXR3R0WD1yOy1XMUBeQUBrCnoyelVqbE9+UH1WSDNlY09aTUBHYTtxPils
S1B4VjdeMUpUP2NPNHgmY09LZTw/KCF7Nzl7U3toPilMbnElbkolPwp6QWV6K0FoUUZtJWxtPW9f
S1RsbWNiJEZHKHszP2ZmJntLKCMkVWV1T2pEVXJMPGNtJU1NRjJfWV42bUVAPCNQd3UKenQwIykm
OT1RWmV3TUhnUl85QF98JV4hVCRqM2tKVSRlPDw2aTt+fWFCbnB+d2c4K0l1LVgtRW5kdnFFVnln
JU9JCnolYXVjempxIVloSlRCbXpfKF9UYGZaa2VObFNyYSV7PiNAMktKTFB3OH55K0k7e1FSKEtq
MjgyK29MU2kldnFpUwpQO301Q2QpbUFDRlY7UzspSEUoPUUKCmxpdGVyYWwgMApIY21WP2QwMDAw
MQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1wb3dlci5zdmcgYi9hcHAvcmVzL2VjbGlw
c2UtcG93ZXIuc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmI0MWU1ZmYK
LS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2VjbGlwc2UtcG93ZXIuc3ZnCkBAIC0wLDAgKzEg
QEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhl
aWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZD0iTTEyIDN2OE03IDVhOCA4IDAg
MSAwIDEwIDAiIGZpbGw9Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBz
dHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlm
ZiAtLWdpdCBhL2FwcC9yZXMvaWNvbnMvaGljb2xvci8xMjh4MTI4L2FwcHMvZWNsaXBzZS5wbmcg
Yi9hcHAvcmVzL2ljb25zL2hpY29sb3IvMTI4eDEyOC9hcHBzL2VjbGlwc2UucG5nCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAuLjE1MTIxYzA0YmU3YTRjYjlmYjY1ZmYwOTlkNzQ2N2I0NDRjNmU5MGQKR0lUIGJpbmFyeSBw
YXRjaApsaXRlcmFsIDcwODcKemNtVjtnOCZLcWxQKTxoOzNLfExrMDAwZTFOSkxUcTAwNGpoMDA0
anAxXkBzNiEjLWlsMDAwfHlOa2w8WmMlMUU+CnpkNi08KWI+TSZKLWRDQHh5THdkJTJfJl9JZ3Br
O2dGaClSWmdiajhFajJGTy0/SEM3ZG4yaGxeOFNuOVk9OTVWIwp6Nk1yVT9jcnI2eSRtaUkyYTZG
RlVJNU9pdmoyRk9Rdnp2VnBsRitgT21VXmtgK1RPZU8lcGIzKylvTHxEZlYjUmAKenMkWU12S2RI
T0EtbTc9Y0pAPWUqJnBsNzVGOU0rS2BgKUM2QnNWQUZoYDJlallTaypVYV49YloybW13SDdjYEE5
CnpLKEtQPCUzIyYxUlIrZkQjXkwzI3p3eFM3dElVbHotZWBiJD85WXVneFkoSW5aQHNsYCpTY0x7
eHc2THw/c0hGUAp6KHFXSUF5P0Ehej5aYEJMK3JXRDd7UD5weXQ1JlZASHtOKlQwbCM9WDk1d34k
Pis3P3RTRmlSfCY2bGRtSDZPVTwKemxwV2kpekh4WUhfempoRWQxKU5HPEQ3SGRzPWdKfjtCY00k
aChJSjNGJEhWd0tvSG0rVkxKVk1NYHk8KSRJWUdoCnomQERmXzxyeHZGTyQqWjMqSm9DKlVoTkxj
WDx6UmZSMFp6PFkhTEFORTNQPGUpQX12JTlVZENHdnxLOG09QUU8Nwp6ZEF4ZDF0IWxeWEo/anlR
UjBTZX01cmVlYFczNVlQKG9lTkB3KlRBbHo0TCRrUHlnPkhrSG0zZVQqdXp+Kkt4fCUKel58dUNh
c1pAJGZSPSlqUlRlb2ZmUjZkdSNJRjJINSZZPW5qdUJ5RXZgXzRDTWJKe2VnSGEtK2tSVFVIfjBA
aGxCCnpSNyVfMCtJfjVBPyVlLSUkMzF0aGlKfU89MDs4N3EpJCpESVFQVnN6IXNWQTt7KzVrdipN
Qjg5SmJYYz1RbypZdAp6TXEpdX4mZFdJR3draTlBYkhGYEhsbVllWEg4M0tDVk10cD9gKT9NWGMq
MGx5YERnJDdFQT5ocmVSZWdrLVd0M1gKelg7e0doOzJZb1F7QCp2PkA+bCkreVJSI2slNlJxTzde
QnRTSDw+KH5fZzsqTU5vTys1b09SNjIqTUl6KUtsfFYoCnpLUkd9V1pOO3pqMjRpYCgzSj9KQ1Jx
d3AmNTF4UGFzcVlMQTwoOUBTUiU0OChEZm9LaHkhUjU9ejt0eEJLWXorOwp6cispbTB8R041S1Va
b1BlOFU/VC07QCpEMiNVSXxoZSM1cyQzZEotK0VGdypCZWhOfDU3JHM9UXdwMzE3d0NLOXEKekBB
PHt8Uk1pNTlHI3duTzB0OHx0ekclZS1wV0QyNyVUMHgxNW8/VTJJcURrKT1lQFRyRWlMcitfSX19
NDU4aVc9CnpgYUBIS1NJb3w+V012PkNAcjVmY199cz0jbntPJTxpX1JGTTNSYkNsRDl2TjQ0PWN1
S3A7JmFBSGdFcGdnKTEpagp6b1FTeFV0YjlmNWR7NzFHPis3PzNiOWVsUUQ9KXJnPipnJnRsfWFV
TmpHNUhiV1J1czc3LUxNU1JFb0U1LWc0OTEKekZTeilfY1hNfiMqVmxKWUVCJiR4UHomYHdjPT1X
NXpQTnRGJkJiRVRILStFdWgldj8laSQlWTIhOzliaztOQDRICnp5TCRDJWNRN1RHUD8oQn1Bb0FW
c2V6KVVxe19FRXM5dm0xdkw1ejVzM3AmI1V1aWwlaz8oWCVVYFNLVWV7PlZvQAp6R09WWnlxdl87
UENSQmh2dXM9NCZvcFopbkh9QmxHXklHUiEpN3poQnNBX0RENFVWMEE/Qjc1NSNHe3xeLWNSVGgK
ejl4JFQmel4oQE8tcGslfExJM1ZPKkc0WE9oJV9DKFg/N3JEQk53fj0tRnZSPmQqfGhFMjMrMytR
UUpmb3peRSRBCnptWWpDKS1hUH43QXZEOWk+NURfTEdrU1Z7YGBGcWktWWc9SnRRKEI3cDlTY24m
alM5UDdoVXA+ZH5XMUNNVnJFKAp6LWRJSV9LOUBXSFReQzxeRGQ1TERneVN1TXZEVyVpUGRORzQx
TzBuMVk+eGdUMCo3THtYWkdDbl4hakpzPllPdS0KenU+endPcGp2dzVgYCoqSHlwU0p4diNNOGAh
YW93UVVPazA7eyh8PmlAeEVuJXVnVihPLXZSX2NlRDFRZHpxKTxmCnpqeFJkelZAWkQyV2Nte3VW
fWR6emp7RUJVazNhaysjdy18KF4jUG8hMkUjK1NjUjEmZVgzVCNpVlZyWGU9a284Kwp6cSFlIzc5
NWdVJHtgSHk8ZHwrdzBUdDBkMUAwdUpENz1VdUFibj98I1VBK1gqK0I5R1E/ei16UDFGJiheXzcl
PiMKekx0YVgzR09jalZ4blMkb08pRnJaJW5pV1pjaSM7X0Zgci1Wb251U3w+SmYjQUFSLXVKNHRt
c0hjTylTcT5ZWmFHCnpVc3crTldMfFVmeXM/JjJzbDMjQTlrKXFrYGVKSD1SUGYjdCNTdX5MYU5n
bC03MFQySzdiVTQkOWFFOE9aR2FpQwp6Mi1Fa0BpMVNMaFI2ZmFBaSs5UCFnTWoyQ2NeQWpfPGJA
fkFRUHR8TG40VEQ4NVdxUHtwO0QkQ018ZmpzWD5GeWEKenItI3x5R2RRTkJsZ0AwR2JTZ3hROzhk
eCZtfTByaU5VPXo2Qit0OyRGaGojUnFOb0IwcXZ8cSFaS0ozdlE1NE5fCnphY283ejBzOXRzWm9U
IV50b0x6T0V0NVB8U05VM35qYXVnJmBIPk1TLXFGXzQmZURaVElPbHtEU3V1WVIzcD1fPAp6dDF5
Xyl2MkFGOFpHKEgrbUN2IWFUd299d1AqSGB6bDVXaX51Y3dQc0ozODZCY1ExR1RgWXV2fCNmc1RD
RWh6Z0cKelZwXmVpQDREOGtTPD8jU1VgKDk5WXUmQztvd2xNKDh9Vys+UnQpOCtMY1VsZSt0JFYj
bXp+TEYlZypNS2ctZSgoCnpBPWBLQzxsZzY+O2Fsc1U8SSFEUGQyeDd2VHdMYkJwPE1nVzNLKG48
a1BnIzA9YTVKK0FfVF5ndlg7O1dTZC0rKQp6Ukh1ejEybnk9N2I9fmpSckt1QF5xNm9zQyR7d3Jl
PT5Ib1QwaiNrVXFZNUwlQkoqYT89SVRHWmdiJHV8OT9NJDAKekN+ZXh4S2lfZEQqRlc8cF93Qy1z
aCUxOXdOVG1vPG1lI1FDZktOREhqSDtSbHpkR3VqRGxVI0YjfU9oeiUzOUprCnpNSG1EYUcxRWQz
SDJEaGxSUUZ7bnhfX29genZhWFIjVHJCR0okcnxUU2F8SFFlRDtkPkB1NmtzYTltX34+OFlwcQp6
QDxYP0IlWnBGNXdVfHB4ZFlCP0I7aSViRyludUY2QXV1KSlzQlBKKlFIZihKYWcyPSY9XiNaVzJy
O0l5Nj01UlQKelBNY0ooMExFR2RNQEh5TXJ9QEdhUzg/cWh5b0VWTUNITHNGZUM1JTVgUjBadmQ4
dzRnMX1VPGNSelVIcHhJK345Cnp0R2I+c21TTG4pclc4ZUZRWHdzPTVEe3I7TUh0SnBQeWoyMk5J
aW8/TCVpZTZ2LXQ4PVM5NXgqNFc4TSt6ZFpkWQp6SCN+aG0ma1ZqcTVRTWFhRXM0M0YxZmZyYWtT
SyRxNmU9YWthWVF5dTY5JWJpcCMlLUQwRCY+JkRyS0A1ekpCJGAKemAwKThGM0QkMD18SFlAZDtw
eU07dHJzMiM3IWBiNkMmNXBJaH5VJlFUcT0tQmc9RTdGR0IkKjRLKmxMUlZ8ZjlBCnp2RnQ2M2E3
TkU4eldGREEkezhJcShjZUFKVj1yeXo7fThGd018TiRjSFFmUipyR2cpZVJRR3Q3cTYpRWh3MXE3
TQp6I3gjZiQ5NE9vVW9qfjFwT2ZgWUE/OVMoUypXeSQ3KX43eUErd0xMcyFOPDh7X2c0UCstck1M
ZTY9PSh9NjhwdncKentDR3IhKmdKK3hCVkB4QyFYVExQRFBiYm5Ic2xtd3QpKU1nPEt4VEQ7cF9r
TEtUJiprOWxgY357JkQreUs2PndNCnpJRThFfi1MUyYxQXFYREdTQmhsR2tad1N+cHk4SCR0dWdH
JDRSaWZqPWthJmZmMTNRYCZ5d0EtaGctTD08M3NuWAp6MGZmLW54O2M1VG1zO1JCUWdzajtaSVAq
PTZkKjgkSjtlZWFKTSRjRmBqYnlGXndgc01eeWdVZihxPXlUbzcrZWsKemkhfXp7VjU4X3o4TDU9
MHhWV0t8cGtXanM1TWlLRjsrQEFXPG07Rko1eE02I2tsaSlGTC1+SEx4bn5XQ09sI3JTCnokZGAt
NiZOV1E3d0lNUXJSKXBhPTs8VDx+X354N2IxTGRfWlZxKFcwYWVVfldwRTZ1MikwIz84OD8lMmY2
ZVY5Tgp6KFZsNj1QflVxIWshK3tmMHdAQVItamZZZGVEaj0oPX1NKDMjV0FnNm5tPkt1UE0jbGxp
RU1hZTJwPHkxKDBOQ3AKelFyZlI/PlFvV3p6d31wczgoOytucVk4Z31fRkd1aWIxZU9aSlRvKGB7
S01NRWBPKjVQWGlHUDRzUHxlQzVoYCYrCnorMWZmczJJRk5iUSk+YU4yIW0wRE9Ybj0pPDBxV1hQ
Xm15Uk5VPUZMJFBKSShMbj10Jjh6TztuX3pAOWBRUlI+cQp6clk0STY2YClTTDdleWlWTkBvelY+
V3VVOHM+SSZZVmd2cl9zciVXVUEwJXlxWTQ3d000RFVVcXNGRkJAYj14KCUKektsPj5feXs8dDRC
Wmk/JG5VNXwkb3p1SCNGPGRGcmtxVVd1X2piTyZ7eik9bnJlVl4lbFpBKi1qJD5seXNNYyVMCnpU
P2VMUTNKez49ViYtUSVfezhFZkNgTSVya2l6Z2tvX21Cc3JBIzBWNlFORWppYylnWGx2UUMoJHo4
VCQkajFAYQp6RUlOZ0cqPih6WE1Bb0t3ViZFbSNZPFZGbSNYNz1BZStAeTFUI1RDe040TT9AQVZB
czIleFRUP3teT1RZaVh1PTUKenQ+cXMjSzB+ZnRBU0xEcWJeUnRyUmpJaENOZlZEI2ZYU2JNajBw
TC0hWD9LWSYhVEo+ZypZTkRoV19GUktpVHBFCnpDUCpGOGpeOUx4QnZ3R1IqN0xjM1VPLVVxRVB6
KWZaMzM/N1U0cnUtUmkhbHVgMVFfQnlmRDAlbVpNTXMwR3hVdgp6Pz97PHwkKkxVfkZXWHdYX3F0
KDNEN2M3fEo3QDVROE03KEdpVE83T2NXbUU/SSlgYkg5Q19WUWw0empMQUhTeyYKekFQOG1leE0w
Pml4PjZ5TGF8OXZgUiFaRXJkbUNjeTV1NW1WQn04UEBCRyF9b0RTIyU8UEFIWilBMlMhe2VLSC0w
CnpXa1lVfGJAQFI7Sk1+cEZRO0V+JHA0NCo7PnxZVHlpQjNTVz07TjUzWTJ+eno5IWhaeHMpV1l5
XmlWJHxRSGc5Uwp6alhSMUpLdkE2Y1NUamlqVkZLQ0slPnN4QkNGZU15dCY3PnxSd35ZY0NXYFV3
Jj5yeE96YXl6MGN3Z1UxYTlsbVcKenpPVHQzUXBlSmNaWmdKRiY8WCZ+ZClEV05LcE1Neng/WHJa
T3ArJXdrITxUKzZlXnNVP0UrMTxYYz9kISQ4ME8rCnpzfHMrbUJtNEMmczBWZFowMGphZyV4aF4m
KHc/ZGFoSnVTMnRkIXM9JF45UDtmZz84eEBUIzwhZlNLdEd2Rz1HWgp6Q29laDJoPkl7SDRZNDAj
cytzSVcrPDVBJDBCTExLdSZHZkMwRStYRHZpRno8RDM1OWc+S2dedHJ6bGlOZFhvbW0KemtnPnRP
RGoxKEEjP2MpNlBmWElLO3FicmY2eElWTWlwM0NBOVVVfjt4QHsxd3NoUiZ+Nys3c1lQYEFeS085
VXlDCnp3bURHOHpKS0VFRDRxYkopZFdmNEJPTFghZkItVUM3STZhRSktTXNuejc/O1U1OyM+ZCM/
bF55QjtDb0gpU0oyfQp6ZktwOGJ0RVVqaClwQl5uZHIhdCNXYD56K1NhQGAhUTFfeWN5NnBAUzVz
SjwrOTkxd1gpbX1ZSDNTb1hySX4qaz8KelU8WEk1alZVSzVEPnxpNHBwaiVMY3ozeW9tOHVVPTRG
eWxrY0c3ZUo2WTZhTj5nb2VUPmUqN3ZWS2ZRPDFjO3BECnpsKHJkSVltZHJHcHNAJV4tQHwkKWdY
XkF1VHtralIlPmdOKk5oV1lmWWJVZVB0d2lkTllDRGtoRTNVNmQ+USlyMAp6Q0BCJXY8XzlSY0Ne
QGt6VyQmMEJ3czItZzUzekZ4SGZLSWNQezBfZSlBbz5rKU5OO3dTMCFhRUZCRkVAUlZvbVcKekcq
d2l1cXtNTEhqNSNuVmBMRjROSEhrUnRDO29iNzB1QDNyeWlfam9SQmtXbllPQENjaWdDbistRShN
OVd2Q3BiCnoofHx5QXs7eDBsRTVJYkhvZDZaQHhwIWJFUnQ0YEJLYEZZSkJgdXd0LSErP3hpO3Vj
I0t1SmN3c247Z2FHMVMlTAp6UD0kPUt7QVRZQzJCSCN5MndHaGJ2TGFrSGAtSjNtXn1NSkNBJnt3
Z0xTSjFLekB1Y1c8QHUzODl2UndBaT9NazEKejckNnN3ZEUxT1JvWUt9cT1fcy1TTkBEdTBuVlJp
emI+QUs/MnFvfE0kP2k+OTcrbzJSeXdZaHlLNmN5Xnltdj45CnpBMFItKzI2ZWdqaHV7UUd7XmBB
WCtIQW5qYD9zPWdXU0VSMyZZJVRgcUI4RzI9NkZ0UHBHb20zdW1XQ3t0Ty1icwp6d3Z3JkMzZS1J
anEoSTZUYzIpfGtlcldAKENjeWNgM2RISlp2bmY4P2Qpa3pAUE1LXyFxJX5lb0Rub2UrQmNDYSQK
eiNQcTZVWk5Md0FaRDNPfE40alBPUjJZaU5Uc0M3S0AwQHUmZ304en0wPEN9e05zQktDK28rKFU7
cVgqbE9XamMqCnpaN2lFaGRIIUw/VEMmRkNZS3ViKFcjP0djZG5VOFBSd357ZlE1IX1ERDY0MDdr
ZkE0KXEySEMwWGxSUEE9S3V3JAp6KkRUfnpYfTJNXz57YCNgeGprZWhpM2tLSkk+Ji1ebWNOKlA3
TG5GfSRMd1VIQjtDPUBaa0BeY1hrQGdaXmkoKjIKelB8cmxyeEk7Q1cxQmNeP3xGLTRIKGVyRTdB
c21SeFRyczFVUGFTKFFnKHcqJSg7YjZRQC1Zeys5bXtUQ1ZYdiFACnohcW9NP2tKb31KLUhxVz89
P3FmKlZzSG9GK3FzU3xuQFhCT0RwKzdKdUpDN2JQVVcobTE/MSFELThqbDM2bnc8Xwp6Kjw8SnFH
Q1dvcXBqQ24/LXdyP0pjZUxnWmVyPy1SSmQpby15OXRQV3ZUQFdgUn0yNjl7NVNCWGpebjFTNT9G
KjAKekE4fnI3bnslX3JhN1RVenExM3htQFdmMVRIfHVNVTZlU1IkO0ExfHM9QEFDd0dOQms7KWdQ
IyskQk9XYzxJbXl6CnpfU3NiPm1fRX0lUDUzOGdJPVFsSUs1S0hARFhHSmZlRUtRMXw0ZDx7JGd6
ajNUN2pudmdNNTBeQk4mcDVWTyg8eAp6eSgyVzFaIUtFRStxJmtHa0lSP18tJU1XWHpjYjxeJlRR
JUNCaSQhKFRZZnVSO3NSOzBiIz9wPnJVRElQUGgoWk8KemZ7PWU3K1FGQiRLMkEkQGFVYHpwQX07
d0RnWWZrUVp7JFBBb0poZXthTWVZbU0jRUcrYCt8M0BZQDV3VFhQbSVvCnpgNWluXzl3T1RTXlpy
O0dNZ2J0UDFsPlclNUI2OzJoVjQoI0IwO3M1RmxpbzlAczZeMGUwbEVhezYrNl9HUjg5RQp6QkNJ
cnFIQXFJaVB9Q1RVQGMhLXZULUNYTmU7TUErMUVvRSpISkk/QjBVc0xXUkdERXp6U3FCanFJY1lR
Ky1iPlUKeipuSU1vNFRteGltJGBEcjAjMGVeOy0oIT5iQU42KGZpYXx3dF41OVpzUDUpTGh9MDl8
STVGKHQlRmJUcXJkcyZICnomP1gpKDQ8dmJ4MWB8RnNtPDZjZU5HIXBSX0hOPyhFc3JxYlZwPmY9
TVNYUCNrKzMlXnZtbmchY01JT2dtKiQrIwp6dFc8YFB4SSRjPTdWMlJXWTlycEU2bnNwRk8+dCVD
ZF9GYUUzN3N+QC13KGRYQmp0Z3IqPjZsNV9QSyR2RCYwMloKelNIcnV3cmdBQGpLSWFUaFp8UCNk
bUdONWJJcHx7KWM8K25feXMzUV9LaTwyRXBBSyFLemYhfilMc3w/KjRzWHx1CnorR3RtbGl1JSFN
Pm4rKXRvUyZWXmFYfH51UikrY1VASyQha0MwZktiT3lqRlZjeThkIWhZTTNkdFYqWDEqaWc9Swp6
P1p5WkE8ZzYzdj56PEVDJEBfVHBicHZza3RQU3xZdFItQzVISUYtb2NrcWtoOWpxX3NAIW4mXjVM
VDY7X1IocjgKemFqO0orKSRjVzE7IXpeP3FnR340cytGQF54Pj8+YmdKWGpYTWVuI0h6a14/bj80
cUtjbVdEST8yZzxoTGUxUCNkCnpSYXp2I3A/cjFjKTcrY2UlX25EXyRrS0VOQlIpPWkwfSYkY0RR
YVNkfEVPbW5tdnpxTCQ+SVJOJkZ8KlA7dm1+OQp6MXhpKD1zY3BiOCFpMz51RWtoQTJJUUJKZjQy
QHhTcylaQjdjMjNRN3VePz12LTZUJm5kNyslKyZYSFhfUn5hVFAKendpQGErbEpGO3s7U35VcWsh
T0hUOH1pJGNlamVYNno8YXZwYWI7STgkRUkyK2MkWHwxa3RCfGFhWip3QWhVXlReCnpadFk+blNK
K2VAO2V9RjtiPiRxfXFhdTZiR0k8ey1qK15TSnVuYTtWTE1XRDJZdzVCZnZ3e3JzUW15b2NTIVVZ
fAp6RXloLXhVTU1AXzYyQnwtXkkmbGdDSDFzUSgoODlSMnBeYDIwPkhrNlFKWUR1IVQ7SF9rKUlG
bTxrSFNMeXNpQ00Kej1Bfk1SQEQjblAmaVA2dV9FcUgoUEU1RDZHfUQxc0N+Q316aV47aXx5cEpl
KFBveTVMekJWTz43R3I0PE9ES2lfCnpnQk1LLVNFfD9YUWU1S0UoZnwoP19jR3VyV1U4OzlFYHFO
eWVzezFvanQ0TD9qLSteXkJTPG1pQkVIa1ZmaTs4TQp6STUqcUYlQz1jNyY5dXtRMTdjTjU+V0Rs
PGN1Rm9BbTlAX25pbEhZK0dtfl47QH5jK0JzYTc5RHBad258I054cTIKekwxUSptM09yVUM7RjxD
O0xvT24xJXhIclAqVSkhdlYoKUhMMG0za0pmVUR+ankrJiUqQVB9SnxOS3c/N2U7ZU07Cnpvdz1S
TjRfaTRpKTZIb3VvZzUhIz45aUBiMWdLM09HNEU3flFDIylrSEVVNzNGKyE1UjdsRGNATHExfCNS
QTZsLQp6JmtMMHRKRTlUfVBiaH0wbk9eMztOPnI2S0ZoJjZ1Rko0PmBCTCQjKU4tcGEpUCpWaHAm
ezF7OXdwMHFORTlkIz8KekBLKEJQJGVkSVFeSFF4RzdpNT9qcS1pJCs4M19uUEZ4N0FfUWNxYnUx
c15seUJLRWlueVBfZ0g7fVd+I0dRJlE/CnpYfGxJNTZvWChWdjdoSXBwQDR7eSF0JitJJWU1YTBx
eH1paCZZUm8mX3xWfGNzVXFUTyY/TTAtQXUhcj1GdmdGRAp6Wk9QV0ZXUFZSbz1YRnpjfDkjYWVq
NT5yPnVpcn1JNVpZd2w/dFllSDhzYiZlYmFyKDt3UlBMKFdnX0FMMn1tQDwKejFWUH5EJkYkUnxv
SndRNjBTODRQYW4+WDs8JD4ofmE4IT5IZG5GPj9AOXpZYGg+I0lPWkdFWWhETnZaK3FFQXFPCnpB
aDBgdkFhRW9EK31FWjY8R2wwZkYjV3Q+LWxqKUY8MzhPZHo9O0BOWHFxXkpNfShrWDRpeWFQRiFQ
KnE0eXA+VQp6JiYoQHl3NntOTXRVKjs5VlIzQ3pJb0tOY2slKzJfdjQoN1crd2FIeit5SmElbD9Q
YWBYdSpUMlIxbUFgKWErRGoKekdGaG1xKzh+dlI3Y1hBO0s9UHdSPTNfXj9zSCZZZVhhNFU4MV9u
PHZYOEptVU8lQXwkdWVRNnBgXmx9X0ghWkleCnpgM24wQipvc0twKGI0ZlVZWW90X0UwfDRRSiEt
OT90RTJzQVJxdWIpIWpEd3w1M3VCPCNzND08aHQ3THYkMzgpJQp6YDg5cE55bXZOQ2hpPnNuaSs/
bSQpXk9tUzh4c1Y5cEVJWlRTTiokcFVzeUYyT0BDbHw8NWJubW9IX0haP0tgJTwKekhJOEckN3pH
JFYkNGVaP14hRTF0Wjh7OSlOUWVmSGNEej4hISUqZmdTbnhNLTlLKk9sS1QpYDZSRnd0dTd2OV55
Cnp5Wjx+ZmBfQ0NvcldIPVQrR0NFSGBQKz9+VXdtYDUzK2FCby05JW8jaD1AUD1sJS0kSFdITlo/
c1pKJFJTSUZLeAp6VWR5NTBjYH0pZG9feSpfVSN3MiYyTXFYXk9aWnIwajV+NGgod256Iy1GQl8y
IyFSRXlmaEdYTkFgPGtAbnx0JXgKemI8YmJ0eXwreFQrV1ReR3pXM2duJndUYmpmNDtNYGJEajQt
cGN4aVVDJXBHUT08TXVWX3Z6MnhfeXpDJWV2YVEqCnpVUVBrRGszUEJYeTZjOVBFbmp8aFRVKWtW
JV4mTWorcUxITE4oYnRrQmlxKG1LSTY8fkFHKz9rdEFfZ01kKWE1UAp6eWkoNUowYEE7JSZpJiko
KX4+eSFSNGg0VGo1Jm5BWWNlJmNfdWdrUjhHRip3Q0Qre2w7UWltSEQjTXJpZ0k3eFIKekl2e3hQ
O1JuOGQhdG8wfm1yaUdfX2tKe3UqcmNJUUA0WmlfR2pgRiE8M0lvNExsMW5QI0JWIWptRGl6Ozxp
SHBjCnpwSy08O0tEJStfaFFCVHJpJiRmdkhwOWIpSyleWmdaNj1kcDtsZjNxZjh2UXB8R01oOCNm
Uns+aGx+e3d3Xz9UbAp6KlF7TjtfUysqUEJXViRkTVdoKVdPZCpRSz5OVXRfdipqZ0FtUiRHMTFI
WmtjeHwofVBeX3tPfndhPSspYVIyQEgKei1MaGlFKiUkVG5eZ0poRzBgSSpaPmRCZk1SLUVAPDFy
eUFlRzJ7NmFFNiU7PntgPkV7TU85elg/MnFOdUY4OVdPCnp6NVZ2dkBCN1FZe1BYakFkKl4rLUNE
UzZfdEpTMmxxWFV7cnFlKmt7Zmg0PTwpdkltRXZgQkM3eWw+eGQhKyR5Tgp6X1M8aX1rN1VrJk1Z
QkphKlhxcSV6IV90Qj5zI054YV8jZmEtWihmb3lzfWEkQ2w3QC01PzNEd1VNbzdTcU9hcVcKek0r
Km5zcXBKQVRkI2B+QWdraFNfdTh3PF9FSURiX3VZWX4jVTVRX1FhQnUoUmNzPGduYndQMXFuQndm
UyZ3Sk9fCnomNn08dCZnQ3d5UjRTJkxIJFglakF9YWVVTHNKVlRyWiYjMjwldWVfPk1VejVWSGoj
aFhVOHcrJjcxIX1BQTBDXwp6S2FIWFk2MlpVYiRuMDxrVilPIW5SS1VkLVVBbGJaIyZ1VD80aTNH
ZVI0U2J3TVhgMHhxM1d3IWxiYUZiIUFVbHkKemgjMEszcSo4JilXWVNNe2IjP3UwIVF3P2Z7Pyko
VkBue3J7VEtVJkI+aTBqfTtiVDhkUjhAS1J5UlNOVikyOCszCno8Wn03NSVIYDVZYVUzMSVvUykm
blomaHVzRXNSQmsqY2VsPSo2YTt9KVhzRHxeSVMocWB5PXpgRk00UnJudHlzJAp6TH4we3YpYmJ2
ZF5CI15qOEhjR0pxaVFPV242TX57JjNDQERDYzk8SkA2IVZWbTFZaU00QmckSz4rTX0ke0BCT2YK
ekpyVj9nX3VoP2Y8YDUpPm9IcmlVSEpRbnJpKShYIUV6PEJiN25CWl8rOH1+YFImYFM1JlUhbXpQ
M1B+PnNHRm5vClp7e2k9SWRASF5eS3F2cUowMDJvdlBESExrVjFtRUIyKGJWRgoKbGl0ZXJhbCAw
CkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzI1NngyNTYv
YXBwcy9lY2xpcHNlLnBuZyBiL2FwcC9yZXMvaWNvbnMvaGljb2xvci8yNTZ4MjU2L2FwcHMvZWNs
aXBzZS5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMC4uYTEzNWM1NGUxNDllYWE5MGI2MTBhNjljOGY5YmY2ZGViMDZj
MGU2NwpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTU4MjUKemNtWDlfV21zRUgoKz0ocU1UQCg7
eUY+OSgrQCpNTjRVaXgkNCNuTEk2ZmZAWCNpNipueUljNzN5eCpUQkMpYnxjCnoqX25IMFhHYkQ1
KUQkcEtObCphKjBFVXZIdFFHKE8xTntqREt0X2FxOE0qIWIzSUs/dURhbEd7YCgmTVVfK31YXgp6
Xz9FbkQmazE+LTdgSXVDcSE1bG93WFkyR0JkIXB3SVAjbUY2NGZFI0I2NWQxO2ltbjtBZCYlZENh
UW52ckdARUAKenFlYlRsbF5ueVI8VDhzVWJjfC1KUEdCMnBWPVptQ15MdWJGVGk+OEtTVCpfZXQj
YS03OUMmaGRVe0paeldhdXJsCno7b05hSVp8RUV9dn4lU25OKipfflZATEgqTUl5KmY5d3ZOUE1G
TU0qT3R1dXFtLWhfZUEzaD53OTx+JSt1SEZ1eAp6UHt3MSg0Y1FtbyFpRDdVQEkzcjdsJmIwJGQl
JHNWPH5KPlk0Z1dnb0MreVk3M3UmVXplPHlkPyE7Vlh9Ylp3cHwKel5NNmRMUGl6QHlKVXsxX1NG
aUJJU1VKa35QRTEqSTZFOTNwPDVjUmA2KGohWlJVc08zNl4mb3o4KTt6dFp5cnUwCno0RCQoT0Rj
T0glSVAzaTkwenApPCtsPzBpQ3gmUj4tc2pmSnowUV5jbHZ9akxzfC1xNiVYTF5qP0olQyN4fkA4
OQp6KkdET2FEPjg8c3g5RCFDUzI4QmFsYDFrMzVMWlVoQk9+QHdrYDM/a2JoSnBYJXVEQkF6Vj8x
YyVXMXh4aTR5NEEKelZ7PX5tNyVEWH49eWg3bmAzb21sJVUmKDUkNTg7X2k2PkIrKzJTakV0TCVg
fkBIODJDVH57dHAwbEtBbzN3UyVnCnojS08hckY0ZmpteGJwKiY0SmBAfDNpVStEJGpXfk1BUD13
ZCppVUxvPUY4KmZDeX0oKzYtXnRNMlpKZSprJEtXQgp6I0IqMnZQMHV9UE90JEJFbVEpSnVSSCtC
dkN1WWBqNXhDT3l7QkErbi1LUyt2WWFtPjg8TzJeWFVJM0RHMVclVVYKejU1KytCX29YRVE5bVVR
RUlpSGpWdyR0WWYqem58VjxfKE4/VnNyKCtEK2hrX1MySnR1KVJ7Y31NWVVgLWZyVlV2Cnohd2E0
I3V8eml+TipNaW07JmdUdkgpaEVEOSpkX2d4SFNaTkAmPnUqXjB6WG9RTVIxKCo2fWoldDtrT00p
VWlzawp6cnwhN3RMUk57ci07UUhYeWQ3NXtLZW8yRV9+emB0JFozWXd2RSNJOXNXSXtLRUFnekRC
JGwpZ0lpUmMyYXY/YkoKem5pS3NULSM8SihfNGs8R3Jqcm5VRktCcHdFLWAoYjRKKF9vLT83MXs4
JDxwWXI4a0lURHFETDJUeklLa3tTKX1zCnpfVlJHclFmdEl+VkJmJjNicDIoQ2l7ezFBN21fbkN1
U2tQeyEpM3Q0b3pEN25GWVZNNWpMPytoYzBJRTNjPlZ0SAp6QWZjbD9IIzs7KkxYKEM4WWFnbCp1
REVhUHtRaD5yfDg0T1coa1RYSFhIRmdNY05OdlNfNH1HekhzbWZqbUBiNzQKenpsKDxPZmk+O25C
dkdnR2BLMjBrTGg9NUVYJH4xaHpVblJBZiohLW5Ea3BkSDtIaVVqIXxseTdQN0k+Wj02eDNFCnpU
Ql9ZRSNHdVNsTFBXUkA2bV5lP3crbyYoWGxROFFhXylKM25hXj9eZTFBUndKPyhxNT5+WWk1YjZR
Njlyc0pqewp6V153JmM0fHZAbmRfNS1naFF3dkJHP3xKU3YySkpLUldAdVkwTSpeTXZmT1BlSiVL
PXhzOG5gSCskV0JmK3U3V3cKem81Xj4yVzk2KVArZjdeMj8mMDRZKVcqJn1jUEEzQngzbFZSUzV3
XylSSSElUjF8a1ZoQGs2cn1mKEkzLSE1V15QCnotZH1XYnsjPHxCY3BRbT9SNEEwZmU1RTgyJXN9
TWlKX2crZVA7e1FeZFA5eW15dzRZWHleNkc/PzV2WnVBfSghMgp6Knx4NyNYaUIkYmB5PXJaQ2xC
PU5lV3BWUVAySH0tLWR+KnwkTlVhKS0qe2M+KFlwYVV2YzA0eEZGKWVHMXpPQXcKekF3NDZ4JT9w
KGArYElkJG1zM3YmKzBecUp1ZFVzRVJ1a0ooP3xTUklmVFV8TlFfcWNnTkNYdmZQMG9ZZ28rZCRv
CnpXNjJ5SHVmUkMqK2U0ZkMpMXklbyFPRGk3c0V5ZkgjPnhpUSZGQU41WlkrdTBPUGVhY2stZXI+
d14yNDAjZVJ2aQp6PWQ1cDYjTkYkISk5Tk4zQyFwN1pnKGx8PEZ9X0dAaURSSlgzdn1JNzZyUWdt
R2p5Y1lLNmZrfHR+WjM9SXRrTykKejcwcmFAZW04S1BpI2RaOUpSakVHRkxiPnhtaVo8bF53IWMm
ZlRCNDhGNTRBNCVkQzMhRXxiZXFeUE1qJj9+aXZOCnpfanhyI0g4V3YhTnRuT3pMQkpLI2phTzZo
KktzKHwlRWtzXlo8PWlHJmB2ciZQRUJ9UGpfPUt9T3x7czIhMjV5Nwp6IyZickBqLTVWTG5td0Vi
N2AxT3wmRjJpYDAoMSVTMWNgQlNnNjlxSlpGNHN0ZEB4bShjWTduO1RnJSVGQ3hqbT0KekJwPyU1
b2UjUjJfXktAXkQlSl43Rnc1fFI5WT1ReVVDd0s3QyFNQGd4IzFLWGZwR19VTih9fGNeV1hBNztJ
TWhJCnoqSGklJFZCYnAhckF6ZE1ubiVBJTVzYTs2YmlmSVFiS3BXTjY4WkI8UGYlYjxPd0tXPVpe
dz9WbzxFfX0yPEJuKQp6P0Y5MTdDZVZJbEpWLVJrJF9vaFQ/TDVmNzJ6KDI5c0M+RVo/Z3F+K0tk
JCthUHNTSjQmKWJgc05zX2wtXmwpX2oKekh2JiNzUmUjX1ZocVBOJlZDQCRTYUNZY2g+KmEjP2Bw
cTRydnJ+b1M5KFY7NXtUd281RnVUeWk7NjlvQztRdit9Cno3alBgeXoyMns/UF9hUW5QPlElfT83
aH0tK1NQUi0pM3k1Q2kmaWV6Wn1URlNXMCNqLVkwVlA1XnFTNUFJa01JQAp6X01HRjd7cDB3azJ4
WWprWSVoemMrbW07MDtCeyR2cDx1MUQtNDVFYlNrOTNvNipXSUh0YjRCIyF8VSNXX3VEbXcKei1P
e0NiSDlEQ1JhPXdiJERuQG5OSjxYKVZgfEk0QEAwezNJbFVNU3xUU35fNzVlMk9RVFRnNyZvbSZ8
VzUqRT59CnpXSWQ5QiY0X3QwNTdTdElrRl95eiZkO19qK0hROGYpbGgrY3QpRmt6V15SY2c2JG0o
MGhkaXBZQmRuXjFtRzFTcQp6I3R5bX5XXilLVjFkRXZaSykmPDl5VkF4OGlJR29FT1g3flJuYnZH
aXc9SnhfWGNoZ18qYnhjNGJfbmkhRWN0PkIKemV+d1dkYyY2WmV6VXVqZHpAfWstNUQ1WihMNThV
KSt1ZHRuQkhOfllpPzh9NjlBI3xDJCZvWlU3LT44fGNBM05fCno3dCtyI0ZNanVMbVYjQjZTKl4k
K2tVWnwta2MhcUpXS1ZmTz5+OG4tYGBLclRtdyE9O0kmaGR1dnRlWTdRSHFaQAp6aDlLWFkmMkJT
c0cwMVRCMTVsSkZMYCEpRGBWNl94LVNEYWxDdiVlcEYtbipMVVE5dm4jP0ZnMWxASDBUX3pXMGcK
enVhXzVCVj8/T2QrbCpjIWpkentMWVp2fHhDKlRXTDxoNCp0ZXBwLUg+b0pNQCVSJm1LNF5mWjk4
JDBQQVo3WWxQCnokaUJYWCNRRHEweTN1fFAzVyolVThVWEJtNm84IUgwbG5fQkZBX28/e1RwKEpj
dGtrb2clK0FoRjYxdSFaJHpxUwp6UkJfMTB1KmpvZmM7KCt1aShAanlISkRSaDUxfnRRKlV4SilD
O016aUZvO3U5PnRvS3FWLTVtJXlJPEN5YSYqeWUKekE5NjEkQGN1VzlLZXxyc2BRPj9gXkNKN2c3
YTs8TU9rKUdkNX0rbktXPVlFNS1lJHlKN0BhZCtIenJDeCswUiZMCnorK3lfZz9GWXNNWnV9dDN1
YWBZWnNGMHNiYjBNIThveUtqfDtYNmNvcjJhbWxiK2B6XnY2bEN6Pmo0OSV7YFhOTwp6dUdwSTBG
c1UjTl5RKWVkVmdmMTNkI3VYKFM2Znt9SmNnUSMpfXV2az1kbz1VZnJUXkFueXhRY3U9SVFZbjQp
ZmQKemhuMG1LVSZ6VnY5ckZtem4pdiZ7KXRGOV9ecWY2a3F3fnRXdSsxNF5sMighU0M/MlohJTtu
fis5cGNzNzE/WVd3CnpZYipiQUhYZ3tMZFdoI2BkUDBicG9aUkZsTmFENUlmTjFWSTZmNVZIUjNJ
XypVMHRsXj5EYSFnRUo8ZkpQJVY5RQp6TjYwTm5yX3JGWXRSIWRrbTg2Skk7TnFZTGp8M2RmbX5i
aTRXd1ZnO1gtODE0NC1ffVZ2IWJiNyR7NHY9PWwpUE0KenV9bjZpeWRMX1RKcH5ZZEo1cHg+fElo
ITM+S291bT0jYCo9SytoLW12I2RnMUJoajB2K18hQ0pxUGJnZnRnT1J7CnpPeV5GMDd9NGs5Szkx
NF9gK1ZoUD49KSRqb3BlJmhxTk1XcTw4LThYdX1mVSYmfis5NXZNM2FFeFZOX2hjfUA2UAp6NTYq
bjMoKG9KTSZrPilWaClsdkdWdE50ZWFsT1lDSGdnSUpkTmVrQypqb3drNj9JMX5OQHw/djdVY0J0
QXsjKVUKekFBd1YwSzZNN1l0VkVTMUFLVGxvSnpoZkw8LXE4YG1hT2J+KlZLN2VgOGBxMG1JQlYh
PmMjbmVheiVIcCgyckY3CnoyP2BqY0Imfm1pMjFDXnNrOVNIKDh4SkApdmRMaTdKbTwtKCM2bV9i
Iz1aVihmUkNzPCMmPDNETlE7Z18/OyltYwp6anhAQEkrLTdffHNUTHo0X0VeXjhkO3laJUY7Uj48
M1dzTkVTWlhFeS0mWTR4dWRtYD1tU2VkJmBxNyg/Ui1PJDsKeiF0OGNPYnImLTkreUZ2RXN2QGw7
cTY3Yns0SUBkV1dXNj5tJTMhPTZ7VX49I2htWjRnNDljWDEofVFgKihzdHZyCno0YVVeTDtoUn05
UylWeyphKTNmVTFCWWxYIz4jMUJVeilUJUpzWU19PUZ3bkUlR203eW90dH1wMERAd04zNl9jZgp6
YFModzx7a25oJlkyMlEydEVMcD4zRT1gaz5jJFYyPXUkKXA8OW1uND1meCMkaUIoblghcGtDdT1a
QVRQbGArIWQKej5XMXRKezlgeytkaSR8d0hqTHdGM0skRUZEeihhVmg/ckF8bUAjPW9qalVYM2Ur
Qzc/K31+bnBSTyp4fWFHQ29FCnpEdHoqWk1PMD5AcXQtNSlFN0JDPlJ4WSlvQ0JqMmZ4aihZclZM
Ymw4a2FzQnB1ISt7Wl9gLX1hTzZQaiNteExeaQp6RVE5KFRtVndNJmJUcE5IdWkxSzNGbVE+aEJD
UUxJJjtwQ2I8TGsjUWJQYXB3bWl9OS0kZUB5MmdTbj19JFNUal4KelNHQTVjWFczYEdQYXBIRTI8
WHZBWjBiRE5eO0h5eGwmcEEmUyVaLVU0O1ZqdVREQDYkWCtGc1RCS0w3LW9BNmZRCnpnRjQxQWxX
LVhwMTx6c0tCPChIfnFJdGpge1doYnxjVDA9UT5ePUZmc0dISUcqaCV4MCh2RUMlZWpoY2JycT9I
cQp6Nzs9Vj5jWFp0NUJnKnlhdTY8KGRGMEF3JENHKmVDbiZJRXooOGIlNVJZZS16NUFGI1VuezV+
fSE9OUo0JGdCKmwKeilBOXtzVEkqeWRhN0R0UiR2RGUjbzJEfX5OVHU9MnFLaD5jcilLOT0peDhE
SzRraXk0X2VQb0slRipaaz8kU29kCnpvN1dIOFgzSH0kXlQ5aEtAYE88JHlPTWNWbnw2dCNDNlNP
Z2JERzJkRFF5eXtwWVZFUT5LQEJXbDRlTmA/PSVgQAp6Tj9UWU9LKE5Va3wxPkVZNntUan1jT3sw
VmhpISF0WD87bGchelJ+ZT0tejN5Xjl8dkE8cTA8S3s+O3F5b3hPMmsKel5qYCUrTyYqX1o7PX5A
b0c3JmxxJXVlRj44MkoyZnZqSDUxbCl2NDh3JihsSjNPRihZQipyNC1WNmF3WSN2fGckCno0UTlS
NHc/UzslODJPT3ZoKDJPVHgraylnPjZIfnl3T2NSPjI0eXNMT2sjS0QhP1lZcmpGdnt9TGgxYTho
cXVSTgp6IW1RZDMwWX5mNClORUomQUA0fkItTzlkTHZDSEF2ezxpeCt6TFZfVlItVnpKez9LMnNI
eFp2SVFDVGFSRFUhczwKektpS2VneTtXVEYwMi0+Ny0tYD9kPUpON1BsdGYmU0JSWChkJFBJIThe
MVJufGA2JFFAUkYoK2BMRihrPlYofFNmCnpvWTRnK3k0VW8pO0RtNC1zJDJKIyFqTmVhb1A1M1Yl
YEQzfnVGKTMxdm5iIVFEQVYyeU9QIXlrXkFVfT0xPn1aZAp6cShvbT0lcHwlRjE1JEYmZVI0Iytv
VURPRyRPK01aaTdRN2tNMXdiUml4P3QkWHxQd3ImMFNteTl+VyhWQlEjPTsKendGenVfXlNQYC1l
b2hoOSZtYkFhLWpYb3xobGdxc2srO01BbDFSeVY2ZDhIV0tOI2pSdSNfV1dPK341U0YyS3toCnoq
Jm5VbVA5YClPZXc5WUBhXk9nQUJiVTZ4cHFlQVd4O0ApJFRnbGxER3Q5TlAoVnomWTtlYDI0RE8+
bV9WZEJaawp6PnVpbEFmPCY8cGo/Xi1WbmwjaShSV1hsR1h8VGBLX09vKEVDdCpfUSFVPisqLW9w
Wigla0YtPExHK0FaWHBuTXgKekpFcVRfez1ycGp4eWlfJE98QWxFPGxve0ZWeE44Uzx4eCo8dllX
YSEhPjF2ZWdgMzFtXzBNSHJyYi1WOVAjTV5YCnp3K0BDRzx+WlJQcSszaTEzeSFUK2UjI0BqezNZ
IzRhLSttfWt5fFpQdzFrS2xScEo3NGF8MUNpSWA7M3tBMW1EUgp6M2AhbXM8JlAmRmlefENoZ0RD
RkFoZj97KXlSJF9hJjc0JkQkRUk+ZGM1RmokLTM9S3JjeCtgNl4we19IcTZMQnIKeiF2KDtGVkN0
aTR5JEk/OHp3RmQoNHtpI2RHdGMoWi1sI21DbEU/MUNmNE5LMkstUyQ1QGNaZj1FYTxLTz9iVUlt
CnpFP24/aDNlZ0UmP1c/SmUxT2FhfVdpM35IMUM5Sm9FfEBAaiZKR3tBdzZEPXh7bTMkVnhGeHIm
eUU0X2pBRCNVTgp6JHw7ZVZCPHx0b1Ize1RrPWg5UWhaeHBRc0s9K0Zze3MmNyNIUz0xLVIrP2Fm
bzw9WXQyX0ZMbiYyUj9US2FGbGAKekZ0ZUw/MyZTa0tIdXx+bWo+TV9wQGdtaHw7SDljOUN9KGQt
MTkrQG83VSRIOWZqKmwhJHdMSjFlO25XVEc9dWxSCnpxZ1ZNOGlebXF2JStSQj4hVzxxNyU1JkJ5
Tj9IbWw0UF91cm5uZ1F8M1ktQ3hxd3NOOyRDQzBsTlZiNDA8ZGJSUwp6OEhMcWpWX1NgKEg/Rk8h
RT5Ke2I8c0xtKCZsezwwP0c4NGJRcFMpemo5e1U1bjw3ZUNLcD9yMCNGTytodmImWWEKenJtN2sw
NihaKlZ5ej1MSTkzZDl9PUxGcXJoKEtxQSVONEJoaTJ6bGNMYDA+dy02U0Y3Tzg5JT15Vkw5M2tD
JXZuCno+NzA/MFVndTZCTlBLfXR7eyopLSVWJVZzLU0kTGI+Pk8kK1ZLfUpZWENmZzYkI28oSkh4
a3R5QG8xKkwxYjE4MQp6ZU5BZ3tEXyt+dDEjS042Tk02bmQwYk1RMEt5T0RYIW1sSUR2cT5XenJO
Nms/NyNBRz1SVGhhUS1uMFpVbk1valMKenZjTz1mYUFXZEdMJHIhfE1SYW1VWX1US0Y5QFlBKVBh
Xzh8U2tBSl8pKytTQlhvZkZpUkl6VUlVcURpek5AWVgoCnp4U0s1cVJsWVZaMkQ7OXRkVFkxYztI
ZUFBUmdSYTElVXdpREFGTT9SUk99dWB4ZERBPzdYUGo3XjJhYGJFYHFrYQp6c09gNzctcnxFbDZB
OXlBWWJMSVM5XlNJTFJ4Yl51Mys+USYjOClMJE5hJm1mezBMNEc9NVZgQk9ZbUYpWnxCfnEKem4r
O3RRd0NOWEUxRCt9MF4mJDZqMytfdiNDSkwmb1MwQjUrNk05KnxzVCRJYz1HY0dWYykzJTVKaH54
ZXZieFRACnpFUUh8YWZ0OEpoZ2NZRTQtZTxHaVolSk4rT35SMVQyaEVgT15HIUlPWSZrZ2x1I3xM
ZT9gYjA8eHBldSRBNXJ4Rgp6JGNVeHYrd1RjbmNSUnJISEc5eG11S1I5UGJ4fVJUQiROTXBnLURs
VW1WQlI2b1duKVkyVGwrancmKkMlLWwpY20KejgxeWRVWTsjcGFzSX1BeT1lPCM9KnJINUUpRWF7
UmFKRHt5KGUqNG9OcX1US3hnVXtAXjs4bGZaKHtiX3E9K1Z3CnpoSTd6YUt3UG1NaEt5UkM+QThU
cCtTczRXd0JfcEl1PSZ1NCp8MmZAOUVjdWFWTnJPNSQtUD0qaTYjSSFlc1FjJAp6djdOTiljcX5h
RDlRP2lJX3gpWmFSXiFEbEQ1Uig5TUkxZ0Z4K0JrVGc4UTxOdD9+RW9faF4mKCpRWHk9SktgdjcK
ej15YXcmZXRvcFFhQnRzQS02KDkqRFB8az94dVQjO1htXn5eckU7NVpzdU13bTU8d2RAZjI7N04l
RzNgUV5kUkVRCnomfiZkLUhyV0F3SVYlanV2ant5YE5vbilgd2xecGVDPClSb0c/VUlmJTd1RSo2
fXNXcyo/O2FAWjE5fXtOSyQjYwp6MGU4PyUpRiErS29Nb2NTPVNWcT9IZnEwYDVxS2FIbFBgOUpr
YmRqPlphanpUJUs7JmxpTjdUIXM/ei08aj1SWFEKejQjMVNtIS12ejFWSWdFY3hUeCs3VEsjVD1j
WHpJZzg7Rj98OUx6NmpPMHYhNzRGTmtQUSMlQ196TjtqcmZpMFZMCnpkTG5OPWFINmFPP241KnFe
OThwbnMtRkQhQXtTPCNXKll2NXtpeH5rI2pwNz05VnlCNXFjRDc8PDc4dD11c1FSZAp6YSVhQGYx
X2t4SVhSS0RvQG9aNHlDV2FZcXlfVUEpKnRJbTBYfiFWfT5vNmY+KlBvOS1zTyViayprVmxKRiF1
cDMKeitMQT9AQnQ4TUA0K2JQZ0hJIzlkKHhDNiZ6fkY1SFZQb0BhYGN6PFExZmB1R3VjSiZSTzJ5
RUtQYnZDZXkjUHIrCnp5M0h6IUxeMk88OyNTOS1he1pEVDlWY3ZGWT96ZHA+fEh+cmx9ZjA+PmNf
ckdae1NeRytxUD5lR2J3Qks9ak03ZAp6ckx1e248bDc/QER1bUVFdW87YGpRaXllPlhIdjlBYEtK
akxHX0s/dkRLTj49bTA4cU58STRxJlFNfiNMP20ka20Kel8renMzaylka0t4T35FQFM/QU5zTFNr
MD8zN0owTHJJOCZOWXlFK3pMVUZsdGtZQCFhO2pEangwWVR3JUMxfVZqCnpzZW91ZiRZITFUb0Fg
O3ZAalNPTTZPcXNwWlhySEo7QVd+USYjSG5VZjgxVUVkc2JkTktDMSVYYSRRUyZwSVMhZAp6bzVQ
fDRmTjctTmJUfU8+QUBZRlIrUS1WNVN3JlNzc0xVRVchOHk5WEZWX0UlPEQxbk9QNTVwayF6M3Bi
YCYtVl8KemxtYVhPIztNb0JGQkdOX0s5ZShRdy14SHNXRH47VEFuNVdgOGEten55dVZDVzJ2amA7
Jlc7LT03MndYeks3OzReCnpWVm5XOVJCdFokUzJKPj5Qa283IyNkXzZyNDlsQHUzMjJuSV9fPTxN
WUY8ZlVCTl5RY2tiVEEmPHNOMTIhaHlSQgp6ajY5c0BDSXFUbkB0WG13V0Y9ZjZQMDY3JllZTFJD
aG4kc1I/XzZNKEgydWxLJVlvcENIZjFzUzVTdVpAKUhQZEEKenkkPD8oKzNRRktUQz4+fUg9QEly
WGV9Q3NaQiVKXztgQEpwe1VKNUxzWS1EeFVPZHo/KkJGaD1fJTRDOWhDc2t1CnpxWCZHUnJ1S0gp
PWVHVHVvSC1sS1NlamQrRD55K1VDLWRQMmV1PVRkSHNBPEM7Q1BxNTJCWEV2PypZdz4pOWZQfgp6
azZYSkQ8IStvcFRAQ004dFE8RztDXnNrY2BQdTAlcz0lTk1FPlMrLT8kbGc4MSl8Vy1TKFVuY3s0
Yjw5aCZfclAKejNvNXluTEE8TDhJTithRlooKVZQc2pNYkZjU0R1TUx+flFva3JZWl5pRj07aXwx
SD0hTHJJSmBtVHVXQmhOTkoqCnpWOCN9a2h4NjhlJjFNSGMzRChTYnMxbmJ0O05OTXdoe2JzeSVv
bTRUOVZ3dU1Pb2MmSUJkSlI8VC1md3hyeE9zVAp6XnpNTzYzNntRMzM2QEwpY1VEVXJtR15pRikm
Kkg4azMlS28pKFVwdihIQzNge3soVURgUiFXPmY+TCteNEFTelgKej52aGo2KHY+eXIqLVIrTiFR
bnNXVTx7UklVYl96WCY3dnZaR1A0STglP31KdCtga0ZJRElVTWtuQUJicHZGcTFvCnpTIWs9WEsh
fUw5dklTQTR4KnV7amhUVWMwY0t6b31LYmQ3MG9eUGo9VkxBJUlWZEZNfFBFYm00a0x4cTRzVVc9
QQp6UDt9PyU/N2ZTJiFCb0RiLT9EYFNHc1lTbS0rYXFvMUVYUmo/UyQ2PktlKzhCPkBYXkxzdWI+
WDFmPFVrd2YzUyoKekVNMXt2SilGXiFKfD1BRk5hY3FRO0R+JSQ8UEQyQFRtdiZEak5ONEl3ZUIl
WVhBe3IlRDlCVTVESCRHdDB3NT9CCnpxfi09a1l9V3YzdERXPmZUIW9tRm1SMTR7Py1hVHhlaVA1
SnRBRT0qeU9iIURPZkxrKHcmVSZ0UWh8K2NMYS1aYQp6Tz93KSZBKXlaT2xPMSUtRmEmdT8jclIp
Ki0+d3F7WWRTSjVATURWb05NN0V1M3dhV0ViVlZBYzQ5VnsrSX1QdjsKeiRaOHJ3PXxoRWJhNHdV
PHpmUFchaTdsSj0pOV9+OWNMJD9pWTBiTTNzY29LKT9ycEgrUX5ufFgybDRkTGMhdlBaCno1KGQy
aGUydTEqb2ZZOTB2en4tX1JTQXFNMkw3WEErcklnMFBWWTBuQVdDRWRkaTJ8OTF8Z0AjaFc+Kk1U
dHVeXgp6Vm48N00hfWVmPUM0V0RjLU5oKzI3ZyU0cyVTXkdBQzREOXdgYE8jYGkqJkx1R3ZnYT9i
YkNLJlAqSEF9dn5NcDsKekN3a0M+MXs3UU1qQER9fCh6SVBNITI1KUJBJXJjPj5RJFdFVXE1P2Ay
dioqfDhAKWN1NV4/N0dMZHd0dkZ7NkVBCnowQmRzVW1BZ0tpU05eOCNlJT58eFJIJmhNdmhSYT4r
MEVNbCE8IU05Q0U/NzQjLXNFb1E5TW1TOXNIQipzLVp9PAp6fE1MS2hibi1YIT52fj1fcXVGWk12
djtkSmRWTXIpTSlzXyhxLWNKMDE8enBLUiVpZGxkNmJzdXRzWTJyUWh+NWcKeipXSDNsMkdYQW9t
aXcxVihudm5ic3VWRSYpRT9pN0NvYzM9I3M/Mnd3XkxvNnJ+MlU5VCNvUjJjMz82Qm5IVD5kCno9
N0FVV1F9JE5gdDExJik+bnZMI3kheztUdl5LRCFUPWh1Tj4yMlJHKGs8fVM5NnlfNHNYNzQrbjlB
bmU8UUhJdAp6YCM2T0xZKnZ7aXdJSm41MV41YiU8bThlcEpBRUs1UFFPNCZwMU5HRSZGU31qY0dS
ZHAjU1k+XmNwOHpeVn5QcT4KenZhaShBZDMtQj48LUYkcSFZX3h0PVYpZHJ4fV9iR28jQV4+VmhE
SmBuKzs1VmZZMTgzOUBBank0SDsye291YVp6CnorRTFVTUJwfGlDV08oeCV3OUlfdS03NGstUHM4
VEAjOUx8bS02OXhKUUBFfH0xd2FqJmFWKkQ9N0B8Y0hCUFhofQp6NUxLVzchJWYjQzB3TmJ0cUgy
OXBjMldEUVlSKz41ZmhzU347TDJwJmRkWmBiMThraDA+MkBHJiN5cF4yZEV5cHwKekpTakQja3hv
Y1FmOX5tSE5KaCsoMn4ocSRzbjI5a0psQSoyYXJzI2lmYUdhdFE0N0RAYTxzIU1PcmM0aGhWMStk
CnojZ2Bza2ZaeDQ1bFdmTD1VfEtPQjtDcnZLMSVTQSsjJlEleXtBTkhTeUc7fnJGQWpVRHFSMzs0
cnxKTCojPG1+ZAp6SGk4a1RKcCMycWw0P3E9Ml9ZVWc2c3o5KVZDTWRFVDIreVZJeDRpbyRhOCZF
UD1gOWdRMytTdTZtUXhEXkZuYEoKenZwa1QkWkRYeXRIfWhWfEt7ck44YH1RVWg7IT5YanRtWmVQ
e3VMdllWQXAtOT9rOEh2WWFxYHtxcT5CejllP3xYCnpSLVozMk1uNUQqJEplIzkwO1p4PTAoQzFe
PGloeVNvMWY0M0g5Q0h0YHFpeTRvc3g0PmtebnVVSy1ZUSl2fDwhZgp6SjljYlBqIStVYCF0d2Rs
RlVXMj98QVFxbWcqfipCZzhtejcjbC1tIW04OV42PSEhdUk/N15oTEJ5SF52Skg+LUMKekUrV1dW
Ml9xQDlOSFgrQE5DfHZeKTBQeFcwTkFjVzNIRCl9WXU2cHZXJFRlMF5jYyR5aytJeClpZChPVmRu
QXBVCnpSQE93OFcqellgIXxYSmVeeHpAbjE3fURnP2JzYjdjU21TNmRGYHFhRitsTHFMSyQwb1JW
PENDYzhLJTJre3h4Ugp6TTNCKDx2VT10NjAxYFBBJTMpLVJqITxpLV53PShhMkIqZUdgPUFeS1B7
JDZwKjBZPExVZDckUVA1c0U+NmpBNkMKem94RHZUVzcoKTZwUT1hOU9RUVpART9DOWolfVdBJV9K
IWIzYzk/bFEhNGMqWERjSjl4dTd5NzFyZDgwNGomaUt5CnptKV8zUGReUldjKz5CLUNwZnt9akQt
fHVoaSVKIzc7NkhSOShWeVg2VC1qTDt4YFJFVTd5Ql4pdXBYST1XPk89cAp6ZEtaYGNFMlhXSEte
VnNmMGRsbjZ2LW85Pml+XnIpWmE1U2ZtSDN7aXl3OTk1MjYtTCo+S1Y2antrN2ExTzYlfTYKem8t
cEw8YTdDRi0+YXcjV1V9PkMpIVheVz9pelZJSEJlO21IS2RpY0RuKUs/c1diM2VeNyliQEM+WEcm
YWFNPHZMCnpfJHY8OSRNZl9ZOT5EPHMjYWlPdWQybml1QyVxOWoqK0Y4R1pzfG1HXnwmd0Bpdlk/
YzxiUV4ybmhoaUlYNVhCegp6Nyk8Rjdra1dvOHVDKD9uKGNjM25eUWpuJUdYMVE3K2hLR29YPkdq
d1RjPF9GQndFQ3heaDxiSVA3IX4rbkk3YkkKeiNqfkJ2JihrPmtTX05BV2ZkTlJNPkdHTkBiRjVC
QWt4emtyQW4xWkU8S001Q0smVkZ8d200dmM2K0BCZGRvWnRvCnppWGg/LTl8N1R3dyV5T0A4QjB0
KnZNdyR+eE9qSzZMXmM9Y3szdTBNYWh5WDxXZFRvTyZlSHtlKXgtdVlMWHFKMQp6KEZ+PmgoUjVL
YWlXaD9YXzkxR20oUDlUdDRPajchZ3pzYl40JkBYb0E2bkg7WF5aT0VGR1M4K2IjRz5xRHc/SV4K
enckODt8QD5pa2Y8dzBAYHteeHNTTFFqc3RHKGNPZiExKE1kVn1lMEtkU2A1akU8e3h2IUcrbz9X
LUVTNjQxS15lCnpJeiNhXzA/c3hNUzBRVm08dEt1ajcmczJiQWhqUSRHSyZRVkNIIVombWAyOUJM
QXVTVDRFJGYoa0hORmZ7UVgkTAp6eFc5I2xXKm1jfWZHTktpNVApZDVhYDAyal58RTQkcEdnNjxI
Z00yYyQlJDR+KXphJWZORGZBSFRAfWQ7R1kleCoKenEhenclblh7PSo/SUs4RygxVmhCI08lXzBH
WDxOUyY1LXl+Y1ZTM2NET2R0IUlUYD0qP3tBO2V1fShCLUtGQ1MyCnpNZCtZYiZTRkBOeUplbT5r
ZV9Hcj5iZyt4cyY9PmI3QHdCdWF3KjVHVkV0P3Q3PG9eWTk1Pkx9VTJnR1Q9ZURxVQp6dnpMc2Iw
JkFrS3owTHAoeCZpUlc0UE9sX2RxWlR9aDgrX0IhOV4ydkBzZil5M3RUUkxYRjtoflFYe3lwTjAw
cFYKelh3JWpBNj5zXyQ1bnUpYCgrZ358QXl3UUZtNHNAV2hqbGxBaj9+cUJmcUtGPVM3SDNnJThW
c0h4en4xJGBxfik+Cno/aG9+RCFgMX1rPzZnN2BTeUFOdWxueWRAWk5ANVheSzxMUjBLQGpIbzdw
RUVUbFk7UUp7JmY0MElYSTApez03awp6MyEtPHRLO2RXKmNRSE5YNlkjbj9YKit5QFRgPC1YRW5C
LSU5ZyR4YFgqeHsrb1JxRitweW1teTRkWiQ2Y3ZXP3YKemZRan56QmFtMUxsVWEhenNNNlNkN1pw
NDdZJHJMSmg+cUxTKyRBdlUjQkQkaT5xM3BNKHB+LUJiZmZKWD9yNTJsCnpUNks1MiMtcz5DS3pk
VT16KSZsPXB0aCF0a251cmtte0JIZzkwcDw1dXw1PD1AO2QqQSFLYDhSV2lIVCF2SUp2LQp6UFVR
WEoxOEFwenZuKXpLYENAbEdOeyNrZlEqeVJJY0tSRFArWShZaXNXO3NETXxjJEotfW9DRlBoPGdp
QnQwZzQKekZ4fTBlZDlZQktJZWsqSShDMjREeDhIfWpSUXtrPSFmcnxqUFozIWQ7aGpONW53MkMr
V2RXMmx2dFJ7ZjtHXjd6CnomYXo1NEt+d2VQWFoqO3I3JE5iNmlNRXQlPjNAZjt5TEtlPyFRYWh1
WU5QRGRfY3N6fXI0Y3oxZ1dqOFY/M25xPAp6aUttQW1LeDB3YDIyNE1rIyNUUCQ0cmp6N2o3PDZ2
cnJqeyt2Qno0UTJUM31WU3J9QGV2cHI7RkJSZmZUY2dUcGUKejBMX3JqPW9KZ1ZoYD87PjNWM1Jw
Qll1NXwmcj00bT8/Z19pMHl1aTZWeXdRZFp5czZ1MXBoc3tYYiZBUSF2bU1LCnpMKCVCYFl5YjNj
T0MzbC0jamRwOHtxdk51LUVaQmtEam1lUypMP25mSlo4PXRTKkFCSj9FU2Y0T1MkaHw9TkZ4Kwp6
SCFlY3hEJWFITDhRZS1EVzQ5X1JXWkdPUntHLTNlMDVSKFh7IURpOEl7WkZLJW9ORD09VDR8Mkwq
fEtHRXR+TU8Kek9jVikjKTZNRXB4NiRiclpwcUVfTkklQyZYXiVCd28kJGcpU1cwZT0ybTFBTVpW
MnN4ak0wMiE4YmN3cXJ6PX1XCno/SlJDRzc+X05TYzJ0NkBpK3AqNjRWWTZYZ0VaMlVoWm8rM0xr
ITw3TnA+fj1vI0FwQkEme0FLVlR6SE5lTEp8PAp6LTtMZigjd2szRG85MnplPUQ5V04rI3p1TDtU
SG1OcCVaTTsofjZWJmx3bWIoV2dpM1hkdmgqOTErb0J9TTVnNzwKek45X1FvP2t3bj9oeSYldVh0
Xj1YR30pVzNMX1E3JiM0Pn5YRl5JbFIyPFE2bXBIazhPMXdWbmZkc09oJXd0ODJ9CnpFcVlLezlx
VDBpPDcmK1RfQWpjVUNoKmR5OVN6MiElXnlgZWl5OU9iS3FJPXNqRWEqPF5IMmFBRi0tSjgjTUMk
Rwp6JmdyJnZWM15sKjY8aypIdHs5JHFLezU7K0gyUHBOP1RKbnl7dVNkMz5DLVk7S1UhTVRHc1F0
VEMyPHl9RGIraCgKejdxTi1MeWRJVSE4Nlo2YVRlaSYjeTY/NXJIamI4IyFBQ3F9MyMze1N3OERw
KUFCZkE8aCo2VW5VRDVBIz9pa3R3CnpUb1NuQHglU19qeGx0PTB0XyEjTUVwUX45SzMoYXUjeFBR
REYzNTtIOEMpY0txO1Y9Q19saj5qaGtsT3ZRQGhXYQp6WVp7MTI9KmQ9MHcxRERJJWp2KyQkYypj
NShIS0o3N1BrfDcmN0txU3d7Ul9BWSNsKHRUTVRRdTR1T1k/TG4jYTsKemUwRDd1Nz9zUDVzdipm
NW81bFpuX218TEJ0MjQxY0xkUXtPaXQlMmJZfVhlIWlRKlcreWxTIzhyJmhGPEM7SHo3CnpIKzEo
dS1tVFd9bkxpZl82SWFmYmM2Vjs4cE1SMWJpUkA+XmFQIy13R2Y0UypvI1lnS01ZU0tEQUpuUVJ0
b296cgp6aiFhJE5BeTh2QSh1cEBYe2ZJI0Akfk9QMzg+diZAd1Z0JChyWUtPbj19d2NJN0lCaiMq
djViNz1QaHxYO302SE4KejQxV08tPW9NaU10NSFTZmotQ15hY0FGNFljKytXKE1UbnBFdlR3YGpt
Y0pIS3c8KDtOek9zOWZZSio7YlklRGUwCnpiP1RlcWVDbjZMbz1Dakokfil9fllqPWhucT1takhl
REdvYVctcjt7aD98UHdpciQ1bm40b0tHVCNRQUNaZV8lJgp6Q3xnd2ZxaGMtTzF4TEVQKSlYJHla
WlpRVTR4aSk+MkY3JT9GPSE+c1lzeUpfK3RtaEAtVzJMbkJWJHImTF8oUzsKejxqJkJaeyQzSCpR
VndmKmk4SHdIUEI5KkQrYitPM3A5JHM2KX4hSiYrLSRzN2xUUTk7S1ghWV5tJC0xWmR5IzFxCnpU
MD9KXk0yJE5YbVROaytsVDVXLS1AfjV9NDImP0hwfEVHZyFkdypRdStOPjtqcUNicCQmSH1RZUAp
TEJMeU9YdAp6TXhNQkxjQjhoTDxqNjI3T0JibFVvSEZ0OUNLUShsNGZOdVlOdm59SURpRFoydUQr
Y3tJXyVhezwqMitgTGFKdHUKengtPEw8SHczb152aD5wcVJMd0dgODJ7cWRROUpIRD59UGxYe1Ml
WHw4RHNkUGlROX4oX3J2OztIPlZIV0I5PX1sCnpDZj1vPF4tbkNadUdxLUJQKTVoK3d9fTRTKXpu
KlRBfV9BZEkpcU5RUnxLUV5uanxlRmdgZj8yUTNUJWdwPDNDagp6X19PXjdLUSR9WXBPJVkqeyQw
KDxQT2J5aDQ7MWtLI2tOP2J5fExZWnRfJjIqd1YwV2FCNUpeNEhDbzh2TGRAKXMKejc0Mj9RYSZQ
Z2pFP1loVlMzT3M4NTx5c0EpRj0oUyhiNDZVPnkoXml7T0o1K3ZKSC1KZG4zT082OWJWVjFpJkdi
CnpBTSNnMVVwLXQlTEQjKTlqQ0FtYV4lMkFVK2teQDl6ZXdhaGhSSGw4VDk7aDRTV1p3b3F0bHNr
ZGckP0BgYiF1Mgp6VDBYY010QCl6PWx5IzZge0FMe3hAWUNOP3g4d2l9an0jYj1sej4qVFYpWnpe
c2lTZkUtUCM3blJASGNCTEp9QU8Kekk/YjFmKnsyQ3s/UWdoPXdmM3dePFp1SzxkayU+MHMoe3RK
QCVgdmFHYGx+aXF+VVJZWV9EPGBWKEVxRHN8b0xaCnpoKzZTIT05aVI4UGRVOCtIOXNQNlYqZiFs
cnIhO0Y8RzU1WG9ZITx1c28tQXBjLVZ3RztqOXU9QlhYaWQzOyYlfQp6JmJuMjU0fXtzRmE9KDls
YFl1a3NOSH1uYW5+VWU7YCt+ZDljUmAhLVVDNz58aFQ3bHo1ck1xKTR0UGFAMnhWISEKekpuZCFP
bVdsWX4+KVkpQkFGNDFWTmdNRXw8YHZ2Z25iZFdJaio8eD0yI1p9am5TLUomaDQxP31XIUkhIyFx
PEFVCnpQPGJvdWwoYXFiQW55czBjJkpnRHtvVkZrYyZJNj9AbFU+WighYFRrU2Zse0J1YmJOQT14
NXVmSHMxJkxFXkJ3cwp6RzxIMVBxT2ZRY2BvTigwVihKZT5aYUR3cGEpWjFuTU1BR1dxYUJsUiQ9
MiRoIXh4V01ITGE5MTRMZyYkbnJNbCUKenVFO00tWUxVM3tVb3ltOGB2dDtzUlBoM3JxdXgyTTVN
OSNyTGU9blVPTklOUGsleSpMe1oqd0AlJGxQSUdtOSZSCnp7VjhPcGR8TWpjTkQwMDYkWkIjQk8h
Yms4VEJ3RnNyNDJrWUxFc2spMyFJNmAkcGZyfD5peSlpKEhUYDs5MGNuewp6QmJNdiY5LUVfPmEr
Nm51O2FeSktefjRqeTw4PlVhdHcmYmdNaDk/eylqTXhkSXlXZyNMejt2TllxNEchPFNkWUIKekNn
fXRnVFVJLWE8IzIqQGUoe0Q9bTh4VC16ZkNWV0l8NDsoTzhUfEB6djxRUmBUY0lAV0BkZldNIWEx
MFVvM1FOCnpNRT0wYDtvPW54R3h4M1NpTER3ZTJneDhPNUFxKXZhJEEhcmJ8TDhAMnJmbyQ+JlRm
OCNILTReNHk8RTFtU0o4aQp6TTUhMGUhc0V9TE9MdkVFSkpWdjIoZ2UpdSE8IyQzeiltPTJQS3Bm
fXprYj9xN2QxTChOSio9fUx7OTJlb3ZRR3QKem5yN1R9TUo5K3FuYWF2SytvZn1nNjY5Tm1LeEFn
dTdhd08pUmJxWVRzP1lZRTMqPVZEaSN9VDNVN35tYSNsM1FHCno7PjVTTiM5RW5iPGltWUMwdEYz
fiVsUHxAbHZZNjNfIUNwSkp4SjghYkpjZ0tQMzBSfXUkd0A7SEU8VD9xcSpXdwp6JmlaaCopOG4q
aXhTRWBUP0A7XnFYTkNDME07X2E3NktyWjZpeUN+N1psTmIlQlIjIXRyRjJaI3FTOXQ3UkF8c04K
ejRfI2VPRT5OXlIrc1NvaTk3JXBkV0hLSVZic313JVRYflJ1WWp0KSpDTUNLPl9IKDs0ND9kPlNK
e1Y7b2B7UTI0CnojYjc3VmBVWUVNQVBJSkg9SDgmKl8hYkJjZjl3LV5AXm1HZnsxKnd2V3xzTlF0
SVdraDZILSZxZ3pSYTxyQ2hAfQp6P0NNdlE+Myk1cU40Xmo5SkVDeCg4c041IVpUPSlAaHZjMilq
Wi00Um85Uml5YHglLWl2djZGdFUhe0olJGopcG8KenNuMnwxSDV6RjdQUj19YG1DRHI7Z3dvR0pP
ezJ0P0VNQn44QT17KDBnc0M+fT1eOE5VeEB4KlUtWjhLeXN6cSQzCnpZbE9mNnVaK2hTcXFKZj9p
WE5TNGA1LUo5c3UheHJZUVdVMEB9dGh9Vl47Y3cjaDFvSiUjWVluOFUoNUdeMSlKZwp6JTtSO01A
ckl1fE0yJEhUR3swSlhzPHlGKlgwYjRNaXtaMkJjZW1VbUN8MGlsVTkpdztxKEdmbyR9eD80Klg4
c1MKenIyJmI/eXgtPFRVdXUlRj0qb0ZIRjcqQ2RmQmR3Rl5UcEApemUmcUU4MWliJlRDcDtYMX07
Zl5MPXNnayZ7VWVBCnppWDVPKTl6dkdBRVFrdml7ZkZ9QlQqaX1CTl4mfkMrSnNqUF5OTCMyTlM/
O090ZkVzMys4OWp5cEk9fT8qdFpGYgp6S0NUKXJzVCF7aUtYO309WmxRN2c0RDV1eD9xSWR2ZEM+
OT1kSzE+Z3VJZiRmNG5nKVBeaS1sRkcqYE11UT14fWsKejBXdDlERl5hO0I7cTVlTVNsVXV0PHJa
KiVJUUEjYlFJblIzaDxAZ3tfTllgZUg3YURySlYrUSZzS2lKN3UyWjxaCnoxYE9MP0xgRTJ0aCNP
cWNObXd8VCQlJSsqbS1XVzNXbzMwU1N7JUd1OypVaV4hYEI5RE1HaH1uKXZFKDxfKT11Kgp6bHN8
ak5acGAxaURFSmJKNmZnQHAlX0xAcyZPJlh1VTlxZFpNaFdIO2BJa3FGMyZjU0ZmMWBJfEx2Qihs
dXhgcWwKendPaypGZ15LO0R1TFBGa1Z8R3loUWFEa1pqNXc1NW9LVSYhd0BZSnZhbTlCVXlaPTNn
Y0VgUTQhQE4/IS1MXnYjCno7MktqfipTe1N1SDs3RHB8SXZacXgwT3d5bHo5QGgjKmJod2s0JHRp
YG8wM25wPjRfYD13fnFIQ3A4QSYydEJmUgp6eWZUWn49bm08S1UoPjxWQ0ZuSlJ7TXVwN2I/czMk
MT1KKkI3OCF5NmFzIzE+QXEwfFhOJjFnOzZ3RDdkRjRrWnUKemxBQWskMm5ZQ24he3ktR3NQTEpP
cCp2e2QzRHhyQlcpKkBucko7LSMyflM9bEwwWFgmR2cpYjhXfWEwSnlOWSFnCnpnMnh1YndLeVVD
MS02IWQqXjYxWkphSD1BV3NlcmcwMHdyXyQ+RHN9N3ppSnlAQDFDbWlBUkomazdsZkJNX01Bewp6
MT8/eGU/TFV2YTh3O099bCExd2Nie2VTOG5KJkolY1pBQyVCeDc4PHp4Xik8dHd7ND9JdDNHYXhp
VWl6UmMlLUsKeiZQLWh8X1B5WG4xZ0klNXFtXzBGZVkxeHVxYiV+d3FHI0h4WH59Ml43al5gdGd7
eiVJMT8/X0JEPDtPTFV7UGhSCnp1aGYofnlAOHFSYGh3a0NeODFmRTNFQDR8e3wyLT82Q2s1VUpq
djc1Iz0/REFHb1U2fnU5TmImUm53IUw1dUJ9KQp6YyQqOE1SdXZQSj03bih7UGhSRWtyMUY8JEV4
RGUxZmwhOy1UcHhmIyp1WWB0VE1VNG5qazJYdiQoKkgrM3tsd0gKeiUhKj52IT1hMXUhKiVoJXBJ
NCpkRyhoNCgkaG9VZihDc183TEdLQXNySzx9djsmM1R8cTQlNU5VZD1LI21kP3g0CnpoY0RPKEVu
VTRBWXFASGV6Y3hAWF4wWilWSnZ5JWBDT29FX0ZWVGRiaDtxc1plSnYpakgkRT0qTGReakNIXmJy
NQp6N0J5KHtrPWQ5JVlMP2NGK0w1cEhRUUA1OHZvfmshR04zVEdUemJAJnFpPTlXPCsrWFNWLU44
UyZrTisrQUhnST4KelVTPV9KUlUkWDg2OTxfSnNBODZpa051Mi1OP3VJSClsbj9lPTl1X3EtTjFu
ZHVYN3JZTF40MEdWdW8yNmIwbiooCno8aUt1PEdxezMjSHp9VyRPTT5Faj98eGhEMUNyM2hndHZS
M0lYUSMxJFJSSGtnN3QzXmgwc2tHOFhOQGZgNj5wJgp6Y1N0TUlOWkpPRV99YHptRSZURyY5PDVS
e1FiRyFuKFZVMFdJbn5MRmRLNnpqMmMpZ0pJPz13ej53YUJ6emYkM2UKeklhRGNVTEBxIWYpUEAj
Pk9pWllpUSt+Xmp2OEBZXnBDKilSIV44PFNjOCNJSGFAdykhPndzZHR5elhQZ2gkcXhzCnpeZHhY
OW0+fVVONE1yQksyfT13Vy1GUElwWjRJV2U2KFUqRW5aR35VbnAtaTBxd3lyN3Q2cT9sJjFMaUoz
KXEhLQp6NjA9PkM1MDAmSyUyUiNsbllxa3BFTD1tQzZFKiNRP1FldVZeTUdNdiVFSFdqRSlsMlo4
bVE7I2lSNFNhXkltXy0KekRJOHAhNjRaezJSdnQ1KGwzejdtOSR6YjMhPmBYRHZKenhwOEFMR2Bg
UDRgRHNaVWdsVWdtY353dEsjc0ZqMVRRCnp3d2UtMlJmdCs1NVNFd1BwWFFld0FjayZhN2cqRDU2
O19CMD1OanxUSDVwM0JuUUpuZVc7JT9hZGRqbjZANWA8Ygp6a3xpfDskMUFiNEIkSmJlPilyOSh2
QDh+cDRTPX40cGtNYkBaayZqUlF+Mn1FNz05dEZeOFVQZXRNKnFNdWZaPmsKel40OH1UZyEpQXpf
TnU4OWU+akl7RVYqeXRpVHlrakdjZ2tzckFUWjRWKmkjdSU8PUVfdzVlZmRUQiFeI1YmJF43CnpW
T21hOyh6V1Q5aHUjKXxqQGptZnBEQ0VeYlZCVzFIM097QClwcXRqYEZ3PmwyO3U3S2p3RTJRPVBi
S0lPc3NfYwp6Q3ZBeTFKS1poUFUxMyZAQTtaWiUhezEzN15eMy14RSpsa0QlQVFSQXMyKjBNQz5n
WGY+Tyg1T0woNF9UNTxFfnUKekg+dzFxdjIlYiZnRjUoRGZwdVgrU0NCLUY5MU4ydUpQaWplWmlD
VjAmeTFOQXpOcyomQiR5WG9USHpDfDMrZD1QCnohVEJ1N2ZaJVdNS1R9UDBJd0V+dFFgOXFaZmco
PjJkYTI7fD42IUdDZylpYzVrKipSKjlFc05YOGU/OTdFVUJQcgp6d1N3d28qZjZzZ0A5clklOV58
XmNgbC0tVDtQVFl6MnNwWUYpeXstJSRAfGdDJCM2I3lRR1F1N21VOWJWUWcoT2AKemJyTU5SNT9g
KjwqJGkqSFhibCF3bT1rNzYxPTJGbyVBamZtZmNAaWdeKlIqN2lFcWc0VjN9bCFhX09gRyE2TiZS
Cno1PyNPRGM1ODRqMDRRT2JKOGk2MC1uXmdUejtEZitLRW9AYTFUQ3pMdkV0c2tiVEUweTgwUmNJ
dDJ5Tjxpd2Y2TAp6anRJd0I2TTNvXlg+d2ZoVkBDfmhyYUhlR3FhKH1IV3RHXjZWMn16SjYocDdN
KXtFVXN5QFUkfmZIQ3wydGpeOGUKentOeUxXPylyVWxIT0FDJFM5eEB2ey04bmhnRnkwdkVpbGJy
VGkyQ3JjMj47VW1fQVZ8aXtlY3pyektSLWdGZXc1Cnoodz43ZkxqWG9gX3JYSmJmaX10RGc2ayY1
RSsmbEZiLWxNcSZRNzI7dWNyIUdnNHZeY182TDw2aHdUMz0mcGJyNgp6eWFxaFlzK3FWU3FfQTto
RFFNfEBFNTFeS21ialBwUF5TP0x2QXYpRDcrVURrWDhNdzgzJkJkMTE7bUktVnlGRUwKensqSEV6
Ky11ZzBVSH5vVTM8d1gwSH00S2NLKVhQT3tjTUA9QnRiQDU9VWxuN2A9JEs3PDBuVkJgP2RsbyZJ
V1RjCnppfDR6dmwkeWp7SiV4VlRgfEJHZDV9MSVKTnF0dDUpeE4oQCp5eU5WbX49ZkYxU040V0dG
LUBPQVd9aVYoRmhjOwp6Um5gdj0xZHlDb0d5TWlFNk1iJktFbExkcDltS0JsSFRiUExxaElAYzwp
Vzc2UHFhUiZySVgrc09qMU5WUnE2eDcKeiNxTGlDdkEzS2lUK314LSZCXnZ9PmNXWlVFSmNRZytj
fEooYkZ7dElVZUpkMW9hVGxRUGI3eVF4PSN3ZHpobndICnpjTiltUCtKbTlSJFRpQUxiJClZWTZr
P1p+Wnd0a3JAODIqTmskNz8hbCRxTjBaK1NZRz1qVlNrJXBVK21iTShVLQp6YmViOShUJGhoKns4
Z0UoZ14mWCV3QmFSajRYaFJfZ2w7Qm1hKChhUnt3fX5uJVpELTAodnBYJlUmbz17QTh3XnUKeldq
WDdoZWpMZVZaai10QkVXZnwwJVBUN2A2SGg5NkxwKUpgQ1E5IWNgUEQ/dT5OJUstPmB4aFBCdkx7
TVlHSllDCnpQbWRmWCtIYU9AYT5YZThAaSh1PWE5UGJfQj85Klg7XislT1kjcn1sTTMrQXxQeEFP
MFZraGwmVH5xN3BMM1FHJgp6bXIodGs3b01BNUA2b3IoeXxHYSlXc2EhQXZUciFva2dKZkIlPnx4
RTF6enFKazVATk49PGdLKjslby03YCQ/Un0KeiRgVzxuYzd3dEtVc2AhQEt2T0ZaU1ZEIT5Ocyo+
a2t1MmhDWWlxe3d3NVhUUjtRITxwPCtra0l0dypacU9fXj9oCnpHN3x5Q0ZeNkNscndOa09DY0Uj
NWJ1UT5LS1RLU3dRb0NZKSpAeTdiQ3pjJTVXbiMlbCs8OExjQVp6bU5kY3FWRQp6Q204IStjcWch
UUEoUkNvI1dAbEB0RG44X3pmVjd5bC0pfCZweEx9NDw0ZDMrbGRCZW1HJU41c2BrV1JpbXVeaXYK
emUtc1UpUz5BO2dEKjkyP3luVCV8bU1LdDhVRkJOdzN0SUd5OFpKMjA/aEI+SCptS3x8U3hZQTcx
PyFJUnFZfUwtCno2MUB2WSpYdipQXzRqVkxUJjg0WTlmdmMjVkRkQGNvdmI9MUMjVV9fbn45Znk5
TiU3K1klR0M/YEpmT1FFYFZJRQp6STtINlFZcn1pMS1PaiRsd3FUPCYoQHFGWG9RPCRYY3NORklj
WkltYFQtLSgxZCo/fSM3RVlsfUVqaE9XeDNqdWgKemljWi0qQT9XRz08VDYlVUxARV4+ZXEkNWlE
Pl5HI3p7V00yIW5TaHpveH1mcEVsbGZAaGdjel8qJlc8QEpNKmNqCnpZZD1HYERffHNIQW1Bdilk
XyNWOUMqMj9gSlomSX5AV0Q3Pit5VjRaUiRqRnsyeV8yVGYmVGYrY3VCST5gSSQ1NQp6OzNVeE4x
UWNqOW5JbzF6QDVjPTQ4aytxWj9qSE1lYjE9bHd3UWNTRXgtWmI+YCQ+MzsrX2hkVDhGbyR6eVY7
Py0KejwyPjdZJjM4ZmY8Pmg3Q0twP2lAIUFDU0tPel99V05sOTF+dmAyPm0rOT5rP3A7fTlqcHdx
bjlqe0Y+LTJKVSROCnpRWFIwLUB2IXpIQGI+bSo1c2wqPzEwSGYwNm0rT09LMDRBUXRteFE7bFlr
dD5MRmkrNTJKd04pKy1JTX5nanBvTgp6bjsld25KfDkxPDExQUdPdmtNIzVfNDheJF9ZUUY2bFIt
KnlNLX1kXkJfI147Um1Md0hmeks1MGtmUHRAZUVkJTsKej19RTtqcVBrJHotdExiMzQyTy1VJSNH
SzVYWVkma0xgey0lalpVQGg5VSo5UWZYKTc3dTQmaDFGeHZWe0E/VXFGCnpxSlIyZDZoJCF1Rkpi
cTlXKERYbjFvWk5wdFpVLWdtcTdRKWl6VWdGOGsoRjBod0ledEw3KHI5VG45JEt5PjRNUwp6K2w3
UHZfQ2poQDRwdnc3OW1YWnpXKjAhMCNSNns9YjNeMjkrZ0ZzeEc0MiFGRVo7P1FJJmNvTXBuQGc/
cDRPMDcKemNSX3dFX31ecjF2PTExRlJFezFpKDh5SDdjJU1gQHZBLS0xaUM9azdpciQ8JEw9RTUk
K0pjNnxoWX5qezhkXkkjCnp2WGZjai1uU1VVdWlfc315d15OQUkxeEA+ayt5QndyaWx+cUtKfUpZ
YFIpQSY+ZXJvc2ZCO3tIM0h3VUU/Tm40VAp6d3M3ZXpjUXFDI0tSLVd2aHhzZj5pPXAkfDI7b2U/
K3ZuTnwmfU5DdD9HelgtODJyJXIoMkBGallTWjt0P3FtcEAKeldZU2YodCgrQnVlO2YlYVg7QzZ6
cG9YI3ZeJDhZPUlBaVo0WW1TJThoMGM1THVJTEAyKnh1bztnO15uY1VldTdSCnphRjM0SEo+NVh0
KitFcyU+Y1lhdCpHaHVRaFEyMUU4KHg3NGdZc1pYP1ZKNihCOzlPfThQaGVkbSZ4fU1FJkhGLQp6
Q1Y+aTBNNTQ+P0U+dnEwY31YUGdKRnpQZ2NrQGpoUHUyeyVacjUxQ1pOZGEqUz8pMUlLQkQ4SD9q
IW9mdCEtX0YKeis1WHBNNmtTKD8wPilra1loQk8lTHw1dmNpYjBeVS1CbG5oJHVRd3tKSCZJcl8r
aHYmJmZqR3ljMEtoJjZySFJRCno0ZlBieXRFZ0JgcFBYVzdiO0VwRldvMys5KVExaUNkbSk/bXIt
IWNoNGlIUH5DP3tNWU1ESl9KQU5oM3Y0dktVMAp6bWcrKF49KE9oSGU3KW1rK29ERjFZJCUyLU5J
S3VZY1p6NCEmUy1SN1I+Y2hjP0NneHk9Kzk8VnFQb34hYE5xcS0KemNQR3pSKGhKU1o2Wkp0eSsq
IXI+JiQ4VWswVmc2PXs8cVUlOHl5WXtJVl8pd0VJTV97eDNXbU47MUhDKkY1RW9TCnpHb3MzcDZu
SWJBUipxUUopO0FIQk1TV212enBJfkJkbW5zJT4pTG83TiF3e0h1RnJXX09tbCtPcU9HIXBhY2Qj
Vgp6ZWNmZUhaQFpoJS1UMzJxKCYhTk88QSlrWT5ab3VlYihUQTBrJnojJWgtI1dzXn5rSWR1V1Rt
ZmIlQzYkTG5UVGQKemBnZHMpVkckN3V7WkB+cUlNZGhkaEs7QTApWHJPJUF9emJ1KCtacnhrUnw0
bl8qVmU1QDZ5MygxLU8yYjt8fF5hCno+KyQ7Zk0tRytgUThxZnYkJk1XK0xrMjZIQEZZa3lqMGt5
eS14U20/KGtuVFpjdTI4e3I7RFNYS0ZfPihHVypvZQp6NklsKmhhcXIkZDg3TD9XXis3ayY/MCRG
cjhUNUtyNGNaZzhSQUN4PGliMSFwUSt+d3crRDdzKEVmYXhyNVBRaD0KemUyMyF3QGZlQlI9V0BI
VjZMTiF5aCZXbExHZ3xKQDtIUTh1Klk2dExmUWJfcDlffDB6UXJzeGNNdkVqd1J5WiMmCnpYXj09
MjgkUSVya3cyNG87czduUHdZOE56TCFrTn5zS0heZj4hZEZDP1IxfEt4b2tmNi0jTCtkQkN6aGhI
fWVkVQp6R2JMYVFLIzJAbnotYSQrMEQ+R21ITFpFQWxzVD5Wc1dZWHIzPyt7aVN3bVl0bCprbTtU
Kik1dlBMXmVkIUQhaHgKejRUdzFiKDxFclpUOUtfPnRAIVgjQW5aYE1DOyFlUzRNczs2e09kX0oh
XllpK1FJMFBFbit3U0sjV35jPSVLQzg1CnpufSUwRkY+MXNPdThIT2cyez1acSpNWE9rdGtsNSpw
RlpFNilPQj1wbkImVnFufTNYfUdoM2NwI2J5PWhFJE5WOQp6MzRpMXApPjxqbWU7djt0KEhROzg8
NFFJfU9VSnhweVBMRDBiVH5BX0R5PX4rVGBTMFdvIzhKUFomT0I7WTRyZ28Kei1YbndhMEtROUwr
eWFtfEVqWnt7b0V2Nj8keFV5NSUwVVYzZyNRMUE9dm5tRmNSbHtVITRLI3cyR0NZKmZSZGI9CktZ
P1pXR0BjI2tiY2BCUiQKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9y
ZXMvaWNvbnMvaGljb2xvci81MTJ4NTEyL2FwcHMvZWNsaXBzZS5wbmcgYi9hcHAvcmVzL2ljb25z
L2hpY29sb3IvNTEyeDUxMi9hcHBzL2VjbGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0Cmlu
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
bCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlLnBuZyBi
L2FwcC9yZXMvc3RlYW0vZWNsaXBzZS5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uOWIzMjJlOWUwMTNjYTFjYTZl
NDlkMDc1NjhjYWZkZTU5MTdjZDJhOApHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTE4NDAKemNt
ZUlZWEg9OHY3Qj43S2oqSko5bmQyeTtseU58ai1rVVUhailTMl5zblN0STFmJkx0QXB+QEVhN0cw
KmZUMUtICnozUENgSyhuNHJLUUlNYHdBd1gwfUF+bGkjQSVyQ0Zvaks/SHtRaUZIVUdGK1N2YTw1
emUpaXQ/RjR3OzleNEI+Ugp6ZCUxcmNgVWVDLWE8SD8leDxaaDJFKEEkY2Y0PlZuUyZ1SlEyVmM4
bSZVenl0WG01dylCaD9sQz5AcyskNz1Qd00KenlqJTJAYzt2O241RDFBeD5WLXVgQWM4TihneT09
YmclKyQ+QUErRXRBPXQwfmE9KHNXbyh7ZD9oczNaeXYjO1NpCnplUEVVMHpXdUg1bCFHaG9UVEsm
andeeDRucDB9JVVPOHZucCp4OUltPklNRCRgUEE4RyNrWEReSm9XTzMkemh+Iwp6Tz9xWWlRRSZn
fHBfT3BLej80R0dmeHs3QStKZHZTKmd7ciU4UXpqeHV6R0wzaWA2STImZDwtK21WJSVnOHFiSzYK
eighaikrbT48QWdwcjF8IT9TUDxqLXswSH5LX2Ajd0pPJj45QHhNUipBOVRxPWckKUdWSHtZaz47
PyFGTDMlaCN0Cno+fWQ/PG1gbT0xdCl7SiFrdWY1UGd1TEQ/NXtjck16cSt0OHNeZldVbXhGPkgt
KnVCZHh4VSo4KzZ6bGhQdFArKAp6Y3J5RiliMl9kSjQqWl4xOCtVeml0dUtFcEExM0Q8X04+WW9R
K357fSlZVFArYjxsIW88djhycFZ5eHhkOEx+M1QKelpSNEN2K19SVFJ3JDUhNmlMT09QM19mYjhu
aXkmQEVvaXZiLSFvY1MpQjNjd3J8MUIqaz9IRUBoQTVwcDRZandLCnptND9KKzxXbWpjUi0han0p
WTdWRCshKCZqJXErd3FAXm42MCMqTz9gZ0hick1ebVZEe3U1TGxpQzJyZEQ8Kjdtcwp6OG0pJGlA
SEltc09SR3JjTGVyZGgrdkpqKG0mSGYyM04lVjdzN3BRPyZNdTJ7a05VejBoNGFJeyMjUXlFYT9i
blcKelhnMVYtOTkzQVFtNmA7N3Y7K0FzUXxlbHR7VCtoRTxpayVgdjVKemVXYUo/KEZpbEwkaWt0
TnJ4LV9HYUhlQyR1CnpMPncjTWdBejh9Ryp5Pj9TKCQ3empjQnJSOVp+SnY/ZCtfbWcmVV5SaWAy
Xz9NQCMlUDYmZ35aZ1Y3U1BJa1FhdAp6Y00lN1FhSSE5RipOajMjRTlZQmBKJnt2YjR6V3J6SSY1
JXFxbCQ3eGMjRj5gaiMzaTJsUz5EY29eUU5eViV+I1YKelJRaCh6Kz8tVnQ+WXQ2WG5aQEh7LW41
TFklVSF1REJ4YTlDX3Etb2xfTkcybl5SbFY0X053d1BxKW5QeHtRZjs4CnpfX0taSXJ5QmA5RSNM
OUUzTjBvSSo3TUp1RGtBI2NjbElrTCNiQTAwWHMjLVVkUHdHVyo8IXl+dWF2cnxrWF9vMAp6QEp2
fXEjLXtTIWora34hQCNZeTZ1VCswPDsrX2t2Sm9WPygrR0U3JV4oT1p1TDJZbyUmdmI4MHB6VjQp
Uik7PDEKenhxTSNnKH1RME9xJTRCYHVKXihDcFJAekEmUz5CdCNLOG04Uj1naC1kbn4jczlfcmdA
NkQ0b21xO1hZeTl9JEJlCnpRenhKOVhnPmxBK0ZgSWx6YFdUYHsrYmowUE8qJmVYbCo/LVh1ZWde
cn0+RGMqTn4wTGdWZzMhbUBTR1BgVEN6dwp6ZyVjUFpSZDQzPCZPVHU0NHI9d3hwaTgtSF9qXnBH
UURkQzVreDh+WUhaYW1CaSNONCNQWTBvOzFLcFMxdkZ9RH4KejhQVURSc3hhQVFNen1EMzw7KHJD
SnlqREFVWkhWaVFfYkEoOEN4c1crZD19aG8yPTQ4PmREI3hXdlV4VTlyVmZ3CnomJiRfdTZUI3lh
eWhEJUxVPSRsS2hWfVNQeHxPPmRvenI4dkB1bXdpWEFwPWM4SlArakUkQUI+TTBOSSpYMThrNQp6
TSl0T0ZRRzdoenhHZVBRK3NRcE1XRnk1eDR5Q1Qkcj42PDFVT0JzTlhXdWF8dl54fkU2UFEmfFV7
aD12KnRrfVkKeitCKEJKc3V9VyRYeXJDalg5e3lJY2pzZyFYbWlXVntqKHk0bXtIfVFwbzJOPkow
RGpSbmwxakJ5azJBMXptfUVaCnpoKGUldTtpakAyPW1UYDB6MWVyLV98eFAkSDYlU2R1R0V6UWxl
JUheVj1tPDBQamc5JXYpJGI0YnhxeFR6R3NIMgp6Yi1MRzZnQXM/bGQ+Wloqa2goMDdAVEh8YCFG
Tk9WZiVxVjVXbzNFeW9nJmR2JVBORTk2dCp6OE1+N24weE1PeHEKelViV1AzbCVoLTg5T2MjMk00
KXB0ekpvVD5CcmsrbGxMaSZebGZ2fHgpYHFlZEI4KzJaaHE3cjZAP0RJZmhJR15ACnpzay1NO1Rj
SDtHQUpDSFMmRTQlTyMtK3VFXnlXRXZMfSN0T2kmb0JCQVVaOzh5MHMmZ3puQzd1KjsqODc2UXFT
Ngp6ZytEPnB0JHtaTVp+S1VVUTVKXkE4Nn5vVmp5PDsmOCZrcnhTfXxic3RAPldoKng/anhUWENe
T3dzaXBUQnFuTygKekhnbyRNY0FTLWFaX3MmNVU+d3NpTTlfWH50QXdMWUh2WjxmcXkxa2VnTGJA
dE9SXj9zNVI7SCRuSHA8a0AhO2tuCnp1NEtzMEtuZHFLWH50WTE3b0w8MWRATn4rRzJpbjI9bnZR
ZCtaPXJTREAkMFVeUkIzdCs0SGZLQ2tTOEJDb2VqRAp6eSMxdWEzd003dWtvdV54NUUwSXlneGNE
YjV6c0NVYCFwX3RGc2pyKTl0M0lDdlZgLXhmKFMoWkpAKDVfLXE2TmgKelZyfmZuRkB5aUV5ZV8p
OHk9SnNMSzM9WFhnIzlUZjBJQDd6YkgoMDFyKSgjNTdiTXtFRGM/Kng8N2pLPGg8ZVQqCnpKPk9k
SHQyP3RidUh8I21qO1JFek5wcHxybFRjN20ldn5NbWswajNoNHZ1S0pENmdjWlFkNHo1anZtO29R
ezxsKgp6ST85eFdIazVEZks2JnY5e09TUGkwTSVnS3Z+Oz9ZRn1hZWwmR3I+RkNyUiZzMWxiXzFl
a2ZIfXdHekRVeU8jZmcKeil+SXdHJDdSeUQpb0VMVDNOeTgqaGVmPHlQLWQyN1JKNWgyJm82JVNe
PmsrbCktUSRFUHBPWVFva0ktUGFWUU9rCnpMK3YrUmZfOGtudCEhNm4lQz1kYVNMPFotM0ByMTwx
eVBrbEBsZC02cHUrVzI7U1F6QVl1eVNaI2wlRkdHKnRtdAp6dUFiVUQ9UVhjPD09c3A/fEJqaTdV
bjtqbWNZZH5GRkNFaChgM08jP0deS2NXVG1kdUQyUHJnYl9COGdBaCU7QmwKelptQkozVHZHWnZo
e3BOKG1kLTtyZ3c4O0hxajA/KD8meF5CQldrdD0+dExKMCo3Yz9qZCVXRShid2Rhcz0zNjcpCnpJ
YFgjdyUqY307WEtPJUxERHE5US0+PE9+K0F4PCQ9NklEXnRJNnZ4YSZzRzxqYEJhK2tWXyhoOSox
K0tBVkNxeAp6YlEwbWkyYGRHYWhNJjd2emBJb1FLJVpESSQtNVEqMCU8aWFURjVSZCY3U1RHITZy
dmQ0NlFabD8xcSUkS258bEIKemJ6IXd9RHxvKElDa1hNJHdpbnl2KFpmR0wma2d+RjBWdnc7KDJS
cSlhYCg4PSk0akQ2UW5OKGFzMllIdFRENDs/CnoxRnxmWVJfO0w1bW0ySWB1ZU5nUSZLc3ZDQ0U2
RSY3PWV7KmtLUjlzbGFIQHM1cEA/VUVxe1R8b2RHM2FTZ3hESAp6c3JXPFZaPChCRlE9WXV0OSFN
eihtPVBUSj5ZXjstJkZ5WXIyNnA+WEY9TzxRSmFrWS1AKC10bS08NWQ/aG01QT4KejMjQDNCclll
eFotdFYyRGpqTn5wRj8hYjVVaX0lSD1NZE1RbWdBQVg3ZG9nZm5Oc3tLSlVeX3VpakUzM2tNKUtm
Cnp3V0JwUWBPSGN8diR1aERuVDY9aF5IJE9LZjU2Y01UTDQ7ITtwc0Jhe2U4Zj1eUHx9Z21kSzZt
QTdfbm49OW1vJAp6aXFFcXZFc3k8TSo+NEY4Qmk/eCota1YoVkpDLXZ3KSRtZjFuNm5hbWFsYVNa
dVdZTDQyOCMtI29va2hueClGT0MKelYxST1NeXZSNyo/QGB0aTElcj9UcDtIJDReR15yWktzZXop
RjF4Jip1e15KSUBZJjEqc0otekJhT3NFaFM7VWgxCno7Oz1XM1BOaTclaTNVJlBTdHdgPF53YXhT
S1YmT0QxJUE8Q1BYPFViVyVYQn07Pm9AO0NzazhEP0hxQChNNUpmegp6REphTXFweX5hdXg0V3co
VzFvV2A/SCN9eVlBMCQ/NCFfOyZiO3F1XlQyKUJBSHZxaSVuK2Z2RS0xJTlmXjI/NWEKeihLJHFF
c1BpeHxGdj5hbHNza2MmYGRPQFp4akljfHRIUl82V0gxQVVDcX1wb20pTFpNQFBibWVkUVdAZ3xM
fHs7CnomXiRXJShJZ3pXV0ckIW5afSg+Y2gwVWZfWkhDP05LdmF4QWVMVl8mYHlUanFJKUMhTDFz
RGh1S1dOX3hyUHphdgp6Xmk0T2R8MnF5ajRvM2tHT0dwRFk5Rl5FJEl4Pj1SMnhtb0o0YyFUQ0R2
THYpX05ZLUB4UkRQfkdnOGBjcTV9akgKejNtcElKKTMrZ3xTZDtObE9YbWE3IUQ5Z0FzdERzYEJ9
PWBtNjBgMlAkdF43PjVMYkpOP2dpQ0RoZk1YNShebiZ9CnpQT0B2az5pe1ooJFhoQ0hvczZxc3FW
N2ZAVnZ6ajRUeGU7bTtwUG1PQzA2TiFOdGpxM3l6ZU1eS1lXcG0qJk8/Twp6TGVhMTFndG10djE2
eDJiNkR1KX5fMGV+R09SKVRYTzBSWjhpVHsqSE5TaiMhNT15YW5nUnBTWlBCNW48a34hNnsKel5O
MH5LS19pViQqa0JEOFNYSVF1OWdya2ltO0IqZypvUHFEOTFjWSsjPzhIWDZuLUNRSDNuTEx0WGkw
ezRmcGRACno1d1lAZ2pWcH4qQSVpd2ErflNlO3cxTEE8LS1LWkNtUz0kN1ZDZVpOK0d0eEJmQ05p
TkBJV0g9T1gweEFsQlMrXgp6YFB7U0p4fFVETURKTT88Q3RaSzdZX2g3VXJ5Xk58QUhUJG58MlRq
a0RoQ2piezNtT2xJQURGcmt1JC01TTY3az8KemBpcUt3Jn4pVmAzWnxQUGhnQVN4JkVkb0Rndjl3
e013dExzO0YzSUZvRSYydD5iYUdkeWQ7e2pFUyl6VmRsdENYCnorZTFOaztMaUlDV2RGI0NBLVl3
I0FNPG1uRXQwdnRBbEdBU3A1MFN1elQ/dmE1VjM8RTZ4VkpOeHRiUjI9WlZGZQp6Rk1zT2AmcGxW
fkVwPWwtOz5yKUJ6R0YqM0hmK0o2d0JgRVAhX2gtb241Jm5aQloyciZrZmY8U0VzRGsqQyleU34K
ej9QT0ZoaFAxX1BKU15BYlNJeFg0bDNjNGR6SzRfYDJeTmZhc3FfcXpaUj4hNHdEUUkrRyE+a3pv
fTlRPDEyQFNECnpIK0VrWUk2QGx8dTZFMlQlQlF9b2FqSmUtVSZ0TlJ6KDAwUmNwViFaXkZaJX1f
V2w0SVY5NThOSDljUlh6M2dneQp6P3loQnQ7SD0+LVFBemNgbTdZdjUmQStEbm05JWpYUXUtT0Yz
d0V0YGs5KFc4QUFQXn5QVn01STAkJHlqYF90MDUKenQtczIlQGhZPElBMysyPW1saDh7M1ZxPT5R
MjUwTlIoSy1CdnZBMCRfRTUwdmdXYVcqKkElfjJOPF5LTWgteFMlCnpTPW1rMUJ4U31AQWBCbD5i
NXB+XkZQKWk/OSkwUFlIU0RlVT83IXBDNEM0cWtFTSFrP3A4Q0NHRjFefSozZnZuZQp6d2JoMSlX
ZElAdnY0T15vbz5yPnsjXmk8Xj82PUhiZXx0OzFEUX5XQiV5ZmxraU1yJHhtN2t3M1o4TkdPZU05
O18KekM8X3YxP1VqfEElNHZgU2J0N1lwTDdoIytOJChNcHFyQ00qUHhLeVc/QDhjfCoyTTlRaFYz
VnFYX2VXeUBrPU41CnpeSSFmUDNOSmlReEh6SGhZLSh5cmpFeChVT1l9bmpeellHS2pIaXxDelcz
aXU0ZWN7fSlpcGh8UTAkaUJWUnR2Kgp6OUI7KkRtVyVCIylRT2pyJHpVa3YxXy0qZjl4b3chKEE9
ISpXM2I7IVEqOFdqJEBiYCFUWk1zVWE2OyRwdjk7X3cKekg0fFRLQSFgPzRNYnxRQzZkNThvQztw
RVcxI0plbnhgRTJxQn0/NkZPPSk8VndIMCt+XjF8fFkkbD9ZbFJ1JUh7CnpYKDEpSy0oUyh1WnpX
MDhpaCVjamFMKEVnSmlxX0UrQzIrTClfSkYmYytDa09AQCNTemloKTQjU3w2YypZJjBVcgp6VStj
ZntyTiRMQFk7MSg3Q1JAMH4lYms1RWRyYkE9T3dZTVRZanF4eU55WSRVRyluTGVHclVoI15VNnRe
QDVZYkUKelFXbnAkNDR0I01IenxQQ3xBOWkpWH4zYGIhPD07fjZ+VTJPPW91eUdIeEZPMEBvelc3
PCl6d2hSJCpTKVNAcW9WCnpvLShyUHt0QUxVSXgoQj9WXnJFO0lHenwpKGJLMXtWZEM2ZnMqNkEq
akJufCUqJWNjV2trVT8mQWImST4/OW01SQp6O2wwMGlHNzBrY3xBfWladl8td25tTj09VHglSDVt
PmQqbCo2SVBCSkd4VXImISo4MD5DWWpvVXp2PFhCYnJpZFQKelIqUU8hYmMqI3haNjM7SlRQKGU0
eHRnQzchWWk5ZGE3SG4qem5pYiMhe31MZE4mb0ojMShASUtZbD0oI1ItUk1ZCnpIKyRhYTBebT9m
I2NYTz9oSHtuYF9GKD1EdEJRT1ZLfiZDYmEmQGwkKmw9UHg9VCYmLSZofiUzKFg0QGYzaHlgeAp6
WiVXJSQrWlp3aTBFRn1IezZNfnxDSlVaTkZjblVGJnkwSndld0w0YFVDOEg1ajtSQCE2SyhEMHtj
en41NkJSYzkKemdrJSV9RSZST2xIM31YUDhTR01NayZxZGljUER4cl55dWd3ZTd3OUliRCVKQ15w
Tm5lRFk/eSg2bHI3Qlo8O2A8CnpZU3lLR3ljbH5GeH5tfX16MTU0OCs0fkI3WUZAKytmaDVfQ3BL
diR8Jm9mYTJqZldEX0g1UShwXjRfdkklcHQldQp6QT8xKW16NHNVYGtLTHJjYHxxYEFQfC03V2Vo
OTE2OHBHLTlkbG9Taj59UDlxNT8pfG9URHdyZERYOHYwXj51Z0IKeihDdkJEaGlvLWgtLV88MG49
OHFZZj9KQWZSWGJpfU5fTVY8SVp7RElkNDZzPHZCZyVIV217Tn0jQXlxKUlxR0MyCnpuSVJwKWUj
ZCtAcXZmM1hzWH17bj9sbGEtJF5MOEQ0T1NFVCpnUDtpQExeJWt4cTVyKVBkYGd+OGpDbj8lQjsx
dwp6KGQ4YWEze1hTcGZiPU1jeWR9LVFsWW5HeVJyaD0zaWB0RF90Qj5keCklO3ckbkN9WCFOcURS
dV9fNSZec34qcSQKei12IVlATmk4VzxDOFlDSFdke2NVYUM5bCp0a349cDtjfiskZX1wSjd6TSQh
flleP09YT0VAMHU9KSl8MU56OFZACnpfRGZePG9ROWx2OWVIPU8zQTklVmdrTn5ZQXJmUFlud3pr
SzxDS0hfaiMyTUB1dTV1UjZwaGh5NWA7RlJUaT8lbQp6MjBKPyErUlQ1JFROV3A1VEtTcDNDK0wk
JjR5NTVyUVhrPFVSfFRWUUArWHNIUl8wTzZJZEFsU1Q9Uyhtc19WZjEKeldxSWJrMDxSTUtoZCVa
MClwVDh5WHMlPH1tMWVONXRqQXZMQXpQXzkxeF9HJHd1PURhe0t5OCh5ZGAxKWhWb3UpCnpYfSNO
UFV3eGBNPmFqLUEpYjs0NzZTd3Q0amo5PzkyZzU5TkcpKEhPN3B6KTlCR0BoWTtjNztLe3owSk1n
VWNEPwp6Xk1AeGlOKmRmSkQ7dTNzNng9e0A0TnhRNz48VmA2Q0ZFUT05MSZqQWkxSUE3anJ9ZCQm
M0pveWtFYSU7M0U+fkwKejU+fm5LQyMzWDVBfHMqYU8qI001KVVhYERMbzhgRiZnO1FtX1p+YDlG
czd7YCFKfWRDaDZuNGBsRldLKEtIbGBECnpEYSZOZzE+d0I+RygoaF9FeUptYmpIcFFydmFqI2pg
Uk5BYClNcmckXj5Yfik0KX1uWk0qcWpmTXh9dGAmczxeQQp6c047NmFBOUxBfWZ0WWk7SjU3cSsz
KEIxRTU2akYzJm14P3N6d3VyIUhkOUM+SEx1OWo8SjA/Yk4yREclMGgxKWwKemN9RWA+T1Y+Qzlo
SCtqRj13aGdtXn1Wenh2MGFiMHVMXyFVbVNAYjhGUnpfNkVeRV8tN2FGTEFJXzJpNHhoXzkjCnol
T3VGRSRUOU0oKkQwbVYlYUhJa3E7eVJwdD4/NGNLMkcoNzJJRD8rdFpQM20pNEIkeWV0MV9CciMz
XjVwREBuNgp6cmdUdGpaPnNTcTlLcEZBaDhsVmttZ2heeUoxfkFNbGU3RTZ3WHR9aU1yVTZyKDNN
JSRkPDd8OG0ma0xgP0I8cFkKel5vSk57YzktfjwtTSskfTw/IUhTfEMjWkppem1vKTgtKSRlbSlY
XndfT3otO2BDQ2YjNW99ZmdrQCs8WlI8MFBaCnpfVnMxI2d1aTBYQ31GWC1yMGN2UilUcygrUkhH
P3tYaUxoQXkmUGJYNUViczRiU2pxcl49V1o4czNvMkdzS000Jgp6V2VTejdSdl5RcFl0YCtHU2cz
aFhZLXctaSlibGJ1JWVYQSticUIpYyhoVTd4Wj9WSHNAX0hSMyljXjNYfEFzRysKenRSYXoxZSh9
PGhSRnZYQVAtdWMrTnk4MkZRcEtoQD5ZIShNUHRmd31yS2kyOD0+JDF4bitjPGpJQSE/SCV0SD5R
CnpjPiZ8T2lWNWo/e15tI1NqS2ttSW59YDQ/ZGFBPXo1WCRlWlB3NGZRJmxTIXJeUyNIQHR8Z3co
Zm9BY040WClVMAp6IUglTXN0PUlUYj4oPSo7ZWN6TUgpI3ZyKGlJRmV0ezI4eTdqYFBZOFJ9QzJJ
NylKM1Ard0Z6anJUT1lHSClzRisKemh5fG1VP2dpWm0+dj9fXnNaSkpxUmN9dDhtTWtzQyR1e0M/
aXM3UDZtcEl5OT5Tc1h3bHh9MlAhKUxSY0V2O0VECnpnO2BzIXtrSGRkS01Pcm80JlVxYE98TmdW
Kn5yYERmRVY3OyU5JEQtZTtDT0FuMDtxZz1PRnU2c1VSSD9GUFowSwp6T2BVIXRhVG9OaTxgRVBW
b2N7cDRzJTB1TGNFYWB9JktFdDJoflNPSVhVbEFTQ2h2ai04SXRMRUljUyFfQHNIa1MKelUxN2xi
aG1ESmclb2BTUTZLO0J9bTl8TGxxMldSWGhPakU1Y3RlXjEyMHREO1NKNTR8Jmo7YSZoO1MqZSZ+
KiE2Cno/REZ1Nyh3Q29Xbl5+cm1rPEBzK2dleHl4WFl9Y14oMnw2Ny10eUchLWNFeF8kVlpwQ15N
SWtWWmRpRjBvZkpGYQp6dDxyWihOYnZxWlJfb241UUc0LTQqRnkocnVNYz9SYmtGbXEmYzVpWTE1
O190elIyOE0jcnBLVF5XKWpYZTFpNVgKeituTDVDSl4zcSg9VGFOP1k9ajY7QkZFJmBFKD9RQHBs
LWNwZ0xqPHQwNmdqSjVDSDczMWkyMkpWeEdIaShVei1iCnowP05XI2J0ZFgoIy00MkxjYGY8Tl85
JW1DIzthP0dtKkJ7ZFhHdEI+P0d8OSsyMF9QdmIqYDVJMk45bj4wYV4tdgp6Zl57WVlKcUUtUDlB
QklRZis2VDF7fnFfaEttTERrTnk0WktiWW5Hb1cocX1fYHZaNEJqTWlVWiZNMlVaI3NhQUoKemoq
Z0NuaH1Cd2RVNzN4SXk7OTFySzBlMW4oZjBPX15hQmVRcVpANiMwdWp6elRTO0FZcX5KXiZHbGp0
R3ZEbXJjCnpCN1NeWVRHfmNacD8lViNEJUdeVXpNbFY5S2Vkb1BnVz1Ae2FNUStIWlR0SlBSSmhr
dVE9P1o+Z1M/fCE8fiFGbQp6R00yZzRMJTtLN0lhbWQlZEtuP2Y9U25+UnEzR3RUWVpGYUo8KldQ
KTRvNWNgaj8tZ0tQbT0zMSF2YytvZ1lVRWgKelM5PVUyWCVpRTlgV1VfPStEMEZgXlhSX14zPGhu
d0RhPGQpdnozOVchd3J0PzM7Qz9KUHBJRy1XVnc1ZkA2N2gyCnptUlVJY3B7QVM5WiZURzZVJHBK
VVlBPV52QndTTUFxMmBhYG1+UEBORjstblIpNnomTjZiMldEQjBjcWRBOWtqNwp6WnU4TmlVanEz
SFVZJT9DdzVUUmkxaFk/Wm1BXzBRdnBRNlRGfTRFIVVeKiVUKihNflEjO3dGJjNrJCFBIzJ0KHsK
ek9BU0tQYWI7eT9eYzRMYCkmV01vWU0+Mn43Zl9xJVQqejR+JVJxVFRken59RD5mWHpDbH5pOyNH
PDV2VyFSVlFtCnp1cyVVV2QzbT5ucDc/cUk9TD0zOW1WKUxAXlM4e345P0BfKntTQT9rY18tPmtI
MzsjUzB5ZWk1RjBVRlp1JWhXPQp6V2JpLXdSXzlwTU87aWQoeERMWmtQRVBqT2VFR0JHNkpQKGBO
Vnl5TDY7JjclelBQfjJPQk1JMkBWRz90N1FAdWwKeig5fVk4ZSpnTTc+ejxoWl9XNmFFKjhjdWhN
cXA8NipzYnt2ZG8jejxwQDJhP2E4Qm02TmZRcFdkMD0zbWJ3JmZhCnpxWEskQjBEb0o3YFhLJFZg
R0ZifFN2Kkp2VGczS3k7PEl8PCVgUjZ4b2EpUUJKeVZILURuN0BuNFBSITwoQiF9QQp6dk9XSiF1
bVUlcXgqbHhIRk5mUE15aUREQ1pednE7aShFMm5IYT4xb2hfYEIhOEleJHA4T3FhWUReSDJVVzkt
ZGcKenZJWjw9RWxaV3JBSStiJiRIMypRUXcrI2NOc2MwNnRAej0tM19JSWE4KzdXenZVd1lTZUZg
JlpnQkc1RXVCK2VNCnpoUipFPWxqeWRoaSEjKV4kRW1DOSQjYX1jUUdsUUFxQDRMb0YzWHh0NWsk
MExEeW12XyNvTTNka0hVXlFoWXh0ZQp6bFFfPzRnOVRSbCMtUmZhU2N4VWQ+Knl3NG5feV8xP2x0
dVNkWjdTNy0oeilheWlIRnxQRVBVUSFGUDVrVXlIaWQKekAqNmY5RnhJMFkxaU9gTDx6b0BMdjI+
bXM4Nkt8R1dAQkxSVihgazI4eVhIbEpJP0tBPT4qYF9EV2JHUi1VNn5mCno9M2NwKkAxMUJRWnwj
MjVeNW1WZHo1NEVKX1Imb2A+RkxnYmNyKW1GJWwwbT9hRSR4I2hlOE9nQXlVbVlse1pjOAp6em5p
ME5LV3pfXl8oXyhGM3MlUndzcExJPj9AIygqcXk5NHVOaktncWcob2gzOW9TRSZ7NmIwQHR3ZXlB
OEMhdlkKeklKUzVebTllISo+Um9va3tscUV3aCZXKVVaTGdmTF9VRUE4d3t7X2dFZk4lYzZNKncj
JCZPQnJ5bTBud1MjNnMqCnpudlVDI3pBJkZLUktoZWRGO1J5I0xgfVBYeWYhO007QmxHN3RTNnpJ
WFYlaXBrNF5BdEx5VFM9ZCRwYnxZIT9fKwp6Q0hNZmlLcDJHJTs5S31MeSZQdCpvK0RQcnc/VzVD
eXRkJUNPMztvUVl+fFRqUHQ1U2wqfjt0dVViX15PaDs0N1gKei1NQXN3VUpRMVhVVSpnVz1TfUFx
NTJKcH0rcHExbDlJS2l4TjQwdWVPSmFXI0llIWpwNldIKjNrPD9KflV7JXQkCnpTMW0kOXdDWnE1
USokJHlYeEYzenctaFd7aSY2VVQmTHstcmUjY2MlaGg8blliQ25RJWhBMFVQNj5Xfmc9VDU3Tgp6
c0F3Q09lKEhNZmRIcGtBejswVkdYZnorU1EmKH45bC1GZ0s2WE8mMiY8am4laFcwN1gtfXBlSTY9
WTtBUV5ZcXoKekQ5cTZEeHluRjYmb2k5SDFPWkA/cnVqXn4rWUlqfUZORTNXalQleDZXeGtmeGQq
PkwpIUozJHZGJG1HQXAoO0xQCnpKcWNKKXskJnZaWldwfGcreSZTT3I+YnQ+ayNCT140WihCNDxe
Z3EpJV5xYS03bDQ5JHU3bnZtS2RLVTF3QUdhPQp6RCU8WVc1UWh7a3B9OTxGe18zZFJLcWc1UFly
Q0VZWDk/KTdUNWVAN3tqYH5faFN0NEsoREMwckU9eFZUVE0qU3wKejNGQW1XOFhSdSszQGRGKTBE
M1RXbD8laEZEZDslPzZ3bEd2QCMhMm1mX1FlOW94PCk+P3wlS0FZfV9scGY7JWV6CnpSITRxKSNH
UHBLNXAoejBlP29nYjA1UGM4Pj5qbUs0NnRCfHd9cDA+JERVODFsbHchV2xaVj8+QksqUnlVT2dD
KQp6ZkhWb2tDbmpNX1lIUEo0bW0+djlJPyhrIVZFTzU+TV4yNmI3al5qIzQtYVFpP0VDc1g9JmVR
eTBXcUpXOzVlSioKeng/eWdQS0VfZ1luPG5waGFjSDV5Q0wqeX4kUktlK21oYFRUJjFhKDgrUytW
TT0+QTJ7Zj4tTWE3KVBrO21sSD42CnpwPzIrckt0O2JtTXA1fDxIY2BnTiZuPEBFNFljeTZhYjdL
Mzl7bFo0eTg9RiEkI05fYlVvd2xGJT41ZjdtdVdAYAp6SnRJMGtAdmNsMkx2dldvI2c0U3JMZ1oq
byZRbmApZDgpd09jMmhvO0l4ZCl8T2E0dzNoXlZ+KzVtUUozd2EjZ20Kej05TSkhVExCRXtEPSkr
NlB0K24rcXlpZVFkNWN6eSM5PF8hYyhgYWdLOWh6fD5JfEVSYGAofVkoflZaSmM3OWdqCno4e0tA
QWgzN3FRUyp9WE87OzN0a0pSNVhrQSFoWSQ9SCEqUEp2c2N6YWpJRiVwWiYjR2hNRH4rVVNPKlJz
fGNOUAp6ej5iXmU5WHx3PGRAPzdBcGMlRkNgPWdtMGMoTSo/OEVRK3JwXmQ4bF9PeTBBZHNSJlEt
WGc+V3E3eHkxbmJyXzgKemFoS3N1T35LVDY5V3F+N1R0dk0yZDxRXyFNNG47cm1CZ2l3NUFUZkdX
YmZEWnluT1g0KnJTbihgNGR6KHhERTM5Cno3ZHkkPHw1Y1lse3l2ZGN0VEh3I0UpVXkkJF41SDcm
biZAYmY3eTszd3x4QnBQclBCRF4hOHJCcXdjSUAlTnJDTAp6YHZSNz5hPjBsdzkycHk5TzApUnwk
K09NJDl1a1NGMmpndHREPU9IUlZSYTt4UzRgRXZIcSo1QGF6PXh0MzZBK3wKenVNOVk3YiQ5amAj
QzdQSkdwb0BsZzUxYWc0S3ZtQFZ4YSVMWS1VZSh4OS1HOz1eU1RZR3VBK0pZUWEmWVVlKVYwCno9
bWk/b0xUdCF+LTVOeFluN3YtciRDSyQxPDVrV1NLZlBvc2BsLTdYTHExVG5WNz5tbDdRdlMwdkM7
fm45azRubAp6Ul5QTyZyJC1NWW4yVX1EaVUtS3grIXczdj0wbHZEV15kQlZEPVR9YCR1b0dYTmlz
M1MpJHpiVVY2RmxuNGlZdEIKelpgeHF4Y3xofkFBfFhmTkE5UXdmUjgjUmMldHtxa3AkSiEybjI9
YiN7aDd4ZDQmMSlCeG1xTSNwbU9vRE1GYSlFCno/V3lPcTdxLS12bTJudWglekEjUSZNQihmRTxq
WGxVNihUYmJpKnw0d3B1SDZQOFowUjktOVpyajNgPXR1NEVTSwp6MHtCQD9seUdiTlRiYlIhVEBQ
KCF2eWRgKTBncG5rNzxTYXZRVDZVVk1QcDhuMGAoV1dDWkBnUjt7RHBWZyhxMlYKelpmO3B0RFFH
Vz1BdyRFJVJAOypyZ3Y4JGw+e3dHeU1QQGIoMmdedj5CJHBjfntEckw3aW4oNShybDZGXkB7Mml0
CnpwcyUxdi1UUCh1bktzXjIpeXVPKVhCZjdyc21VKXteY15hdXt9ejhqVW8wQD4zZzwkLVNvaHNy
YGZDVE4kRWpfaQp6cnREcnVBS3VWTFQzWHRoZHtHJE96K1BCTCs3NDhLbVpUNXhyOVJ6PXBaUzh8
K0xKSkRQM1hrQTA8VkNGKEU8R0IKej1sPGV6O1AjNX5tazdXZTJ8Jk1UR1dCSiNyaUsjUUZNdWJ4
QkprIWZla1lRZTZPa2dTI1YyJjtwfH16SGpeKndTCnpTUzRpTk9IX3d5aT1NV01VeWdYMj5CWHRu
WnAqVnVNU0JzUUA9bW1uX0dRQFV2OUIrUiZ6QWIzdGB9KyM4QnZiMQp6bFcwfig+enxob15idjMl
VlpHelYyXzBxYXd5eGsoeik8c3dRIWx1TlZ2YCgmbUNVIUNMPmxEa0JfLXdgSXhOZHkKemZyMHtL
Y1k8KVU4bFB0TiVna2BpR2Z+XzMwdElvTnd2QWYtYHc5QDxoezdVWSt6YkczIz1WWH5lRmBfRFlk
eXU2CnoqMShodjZiezkjQl90Kj0qR1ZhbjhGbXx1USluXjlhXitjWU97QWN+RkxvNHBDbEpBIU0j
fENrYXZWXjZQJXR1Jgp6YmJHMG9SbDc3RW14ZkwpO0VDVlQ9Y1ltbnYkVnlGNjs5Q3YhfGZFY2lK
QWwhIXF+XlJIZmVjYmR0b2FBKEY0PDkKelE1MC03MjVyUyhwOEohe2RPZFhwbXl2cT9KdStUNClx
fUUtOzRXeGVRKF5RNVVHdTU5KjxjbT0lIWh+U21aSUVYCnp4NF4pbkt0RG42c1R1WW9Tfk88bCRH
NEpNakpKR3x1TClaRFUxSTcpVitleGlsOSFKUSshfnM/elMhXjBlVj1iMQp6WEB9VGE+bnBVPjk7
ZTVqQ2MrQ3Umb0NzXilrdm1GOzstMH0+U3tDQ2tsbE5gRkZGX0AySnFQP0xoMktOSylgKG8Kejdk
eUlHdWlWQmJlfGUlKkE5SGNRSCNyTEFWYXhXYCkqPmdKb2xeT0w0Z0d6TGUtTFJGSiZsaTBjP2tg
JEJmYFI5CnoqdCZZTTB3O3ltNVM9PEFqSEJRKTF+VGVnWHNHWi1UezFtPyFaPFchYi0zX2hzNy1L
ZVZtJGpEKShYZHp2RSFkVgp6KFJ7K1ZHe2dacmNWPntQdUFkfTJuaEFKbmBlQ2QoTDApXyVabVZ3
VyRJeXYmS2FqdVFnMkJsZ2w4JUowdzZQMS0KenQtS3kjYG4zWkhae2dfUVJ2Tis4SnB7Y3FsbE41
bVdVKnhEMDYjTkJ4V3slWEd8e0E0SEx4ISgrN3VYRWQ+eVAoCnpVPWUkJURSRjdmWWxsKi0+aHww
bnslMkZXZnZGREc2QFdwRW1iWmdGcEFtYXw/UVF3MVlhN2VmendqeGZXSjl2ZQp6cjRMMVBhQD18
YXMyTHFSSFJnS0dNPj14a3dWSlZzTnckbV5OaFFffXM5LWhRWjNlZ2BrTUZqTzZQPVJtLSZ9bUMK
ejNobEszMzctZDR4aFc3Xy0tJW8tSFg3fXg/YyFkJkhaZTF+R015JXVuYmhLXjdySCg8JUtyZFEj
UkZXVCoyYWlsCnprQnA5bTItRFcqU0xWOWBxP2ohVDt1OGA9eThWJUplUXhsPDdCIXxWbG03P3p6
fSgyMHZiamVgJCkjbjB6YEpAaQp6MyZhWjZ2OUk1IyFeR3xGeHBvQFJRVXFBXzdfMnlqPHpiQ29Z
PW5sSFdITEUpRysoQVJqTFYjZzZJNDtZUFJTMHsKektoLUFkYGVUYlpLP25NTEFHbTgjY3NCKlMx
KSstX1c5QG5Kd152aDVhfTU5YClLYjM8ZDZpOygxPmE4RDRrbVNlCnowWE4mYFppZEtUTXUqeEgk
cW1mOGVlZk8tRkN6PCtUeV8yajs3Pjw9UlAxRDYzQGp5S3hfKUEyOyRnV1BhcWk4bQp6JWh+QVk9
JV9afm4waHl2JHxMQ0QmRiNlOHshfWJtXylWc3h0WDEjQz1NdWxJN0tNXlhVKjkmYVEyUzBPZFpK
VysKejtMWXhSaCtlRjNaT1V4ZzhjK1c2c30+YU0xNlF4Vno1VjIpRGF1P2RyVkR6WkZGQ15ecGEy
O1BBKXp7Z1JqQis4CnotYGElO2FoXkpWVkwkekJiWU5mcj1kfVczemtaVDh3dUQ1bzN2QihlaCEm
Pk0jajhCVD1ofWZtKXQwM2s3YEVUSAp6MGojWFd5ZnElJWRjRDU1KmliKXRLdnBGb0A0O3c8bXRG
WEd3NHkqa0ZLOV5DeWVGKT0td158PERhakdFdjFHcygKejU0WGBqT2d4a3FGTHJUOzkwVHhQRXR7
bnNfUXojcFdEbypeQmJVR3EldX1BV04rU24wI0dUUXpWNzBYSDZSNkdDCno5SSY4KVV+SmJaZ0xf
Q1BXVER4QW02dzxFVW4rZHJhWU9wbztOYTYmPklWQVd6WWw2P0FjcTkkeUNAUlNuXlA/Owp6TGgy
KjxIY2YtdWVtNWt+STNtJjIhUipAOVg2flo8KnZMcHAhZXBKKCklKnZgJUY2UiFtcCg0ck11ZGtP
TVJmTG8KejdHN0ZnaUZtVnxWbEVpKTJxbzc9SXRTOTxScmIxRTRldUd6YmFUX244RVQ4OWViY09p
MzxAb04tYHlAJTFeZ3BsCnptSEtyenlVZXdHNHs0KnhpVj1yJHZYfHs7I0Y8XjJ2PkBgUEVDcEwm
USglfUBQJm82REM0RlBIe29qMSZIOEAqUQp6c3lTeGp7QkMhYmEqPlJ1al5sWDhfX0xqbWlydjVP
I29+WEZ7b25RMnw2TDZKfEQ/clYjTH4qP0dFJEVPcDElVjYKUDQ4aEwwezkxaH49PWM4dlBsZSgt
CgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlw
c2VfaGVyby5wbmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmcKbmV3IGZpbGUgbW9k
ZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4u
YTVlZDgwZmMxODQ2ODcxMzJhYmQ2NzM3MWNkNzgyMTA3NzBmMWNhNQpHSVQgYmluYXJ5IHBhdGNo
CmxpdGVyYWwgMTk0MDUKemNtZUlhaGcqfHBgIygoVVErY2NrUGl2SlR0SUJkUHNfWVQ0UWJsQj40
bnojQUdOUDtxMFYwR0R0V19RZFA9ZjVHCnpNTDxBNldASEE3MCUxaz0zSXFpYkFkbW5kZ3BkJjQ+
JVFzeGQleGZSOzYwOUNhfnZNSSVlQnQmSVh+eGxVRHVzSAp6YG8rT3x8SlI0Vm1YZWElWiokQDIl
VGlMKChOYT1oYHV9QDNfPX09cVEhNG57YkxXQ0hSIVR+eTFeVnx6OHxJWjQKel9Aakt0eCQ3WlVG
Z191O1V4VTQrYTUkWEs/TGFAUT1kWDlYYnVodWA0MzdDPkRYQVolWTx+WGY+Zk94NmlTVyFCCnpm
aCQ5WmI5OGQ9QUV3OFlfT19Fa01AWDt4Unx6RW5afHJ+Y15ZQHFEXzNNR0ltRk5kdm0zeWY9dWxL
eXNzITJUYQp6RSY3TlRSZnFqTTtZfENOaEgoTT1ifU9JP048PFlzXjQkZGY4b19hRUp3N3tJSzMz
Zj9xT1EwfEcpIVl6PHd+fXEKenclRjtrdmJ5Y1VzQlZFJVFnKExKUTZNYnpjXnhxckNjRTx9KXg3
JGo9cjRBakZQQGN4UjBXQDdkJXBPNz1qcGxICnp6ZFV4SHFEbFhCe0txXm43WEFVbktjVnBkdVRi
el5RaWhQM3stVV99cS0kMW5OTjhBSUw0bEYwWWdTPXNoPykmXgp6ZiMyMkJsV21GJTMpODhAUjtI
ejx3eSQ7Qil0PzdDTTVgWnc9PG05dHNpfHFqP1VzbEIteWlPbllXOEB6VGU+cHAKeikta3JVdzRW
TnRzUy0paytXSzBpVjRCdzU/ZD4wVilOXmBUS0llUGQkb3JwTFRpYiMrPUVAYUshdHx9PGwmSz5k
Cno/QHptWjB8ZTFoZmUxQUVweDwrZj9sP0tISjEkX25sRiZLaSYjMlFqdE1SOUw7RT1tYj4tJmEj
KTNXMkApPE9wUQp6VCRlNnpzcXNvbDdrdmpXbDNyZSRIfDkmTXZIZzA1IT18SypyLXlITzY8d20p
PHpfI3N0K2c5TT5yTEc5MCRKbmQKej9PKUVMKFIhRDE+PVFuWkd0KUNPeUFuTHhnNkhPWDd0UVlj
S3hTWlozO2MrXklyMmM1eVQzeEBrMEdrPjFePU9hCnp0Pys2XkQzOXE8Z0dHbkFSX0hsIz4kSj5f
MCg8Z0h2Ozd4Mi1NXnI1eU00M2ZpJG44bzZ1d0w/RT1iS1o2ezFaKQp6WStRWEBTZzJAbUR6ajB3
allsODN1KWFeRkdyUll8c0Y1ajJIUEtUKEpGQkM3ZXRzWCMwYlAzUTwmQmQzYGckeykKeks0KjQm
LURLMDZwdjBDQF9hTDVxZGNnOUo1LVdDUEt0RlRle3s0QmN1QVc4PlQrd3gpV0o8T3lIKFNpdD01
bSlKCno3SnpfTC08XmEhYXgwQGQhKktTb1lrbHlid3tCO0VsU0B7b1ZMKHEhYzlaYEMkS0tyPE8q
KHF9eVczQ1czWElLMwp6dCZoc1A7LTA9Vks5JWsxbkh6cCo8QnFidE53VCRkLTBZYD4tMDtZP3lC
Y2dQT0RyJXQ5QmIjYHBrYnF0YDFFTlUKenBeZUFGU1Q+JFE4RGN0XnU/bSZwKUE9RG96VHB1OWo9
REt5cjhra1VwPE1WcFBsc052WVNqNG9wcGNedypuTHZCCnpQUiVTclI4ZH1VR315KGNzNysxMUlL
OH4wQUUje1Zjfj9LU3tMI3pGX1I0OV5Vez85QVRIP2tYaihQQTh2VD0kdwp6eHl6KE9WOUZrXnVZ
THF5X0t2eyp5dzZXfmFTRE1RWDZ+VldyU3p6dWJtbz85dC1VUWEzXm5ybU0raVN1VEVgYXoKeiZE
PyN3UW1BJD1qXkBCQmxqVHN8bUZaYSYpMztfWjEpQWdkQmFueit8R09Eez4zXjZ5TCExb25eam0j
bClUQ3xYCno1QEtUKnd3QHtPNV5IQyVXRTU/LXJoMCpWbVY1KFJUdm1HeWhqNFR8YmkxLXZ1PD8l
N05ZZXFzbTsyIVNvQGAlegp6cXVafUVAfD93SDRZenxgUiZTOUpHMU5gYF5USl9JJiliVjtuVlha
bGotU2BPdFkma2BpIXBRRXFGenVhOS1ZKC0KejlgNDxoNURBPCRDRWYkY3FCWGt0P3cpdlNuXzE3
MzNeJHRTRzgoaTg2VWpJb2plXlVKTW9UX0liajhsaj1MTl5YCnpYaEE0JEQmVUVibWUweCpCT0tQ
ZzAtQHI0UkJEJSQpU2IhRnY3biEjSnxQJTZXSlV5UHZrcDE9eCVPQ31haWtXMQp6TFVmc2RHZH0p
VT9jOE5HPFdte2VjR1R0ekB1JGpvPTFBOTc2an5aZ2FyIz8wbCZnIz07c3RUOHBoMzUraz5nbkMK
elNacVZPPjhyc241V0ZsJDZBJDw2bktaczh3PH1xJXZscysrbFVVZVAmYF9vZTg4U2c/cE9qUnlp
S3ZNayp0Tll6CnpRMFc+PmFTdUFaZUNUK3E9NElrZCt5WSkhZ1RNTExyLTNJJmlKTnJ0WUdFNnZk
I2ZkOCUqK0BKZSpNanRrYUtuQwp6eUhuZn0rekgjKHN+dnZzWCYzV0llX25XOyZed1NibWJpKFBN
b3V0bUZaQTh8UFBqTyEkeiNoLVdOViZ9OEFuNz0KejU4OWtxUXZNUjZpPVFGVE9gVTZHeysxPDc7
JT9YMTNSQE1mJStGbVE+QnElO2FtcUZPalUmYjM8WnZDNXhjZVNMCnpJSV8jVl5MfFVyeFdWZFNS
UzZpczkwPzEtVjFBYW81SSskUilpQV5ARm5xeXxeeGM4UEd7UWB3ezw9IUtgd0lUTgp6eEtUODZQ
ZlROb2VWYys3Jnk0IyhUbkB2YT1jNXo1aSQ+dUQycEA1YEo/ZSZKKW9tVzlqUk50clk3NFMkN3g9
O2gKeiRYM1IjRTF0cClFOEp7OWFOcWUkNGVoeUxYe2kjfWVTZkc0S2hCblFtMkVaNGRRVF4lPFY1
QiRqPlotVXlmYFJZCnplcmo1MDtRfnNuR1dOV0w/PHRydVFmYnNZZlVPTTNRVUlmaz9JRmRsUHdV
SnBiV3NRYj5ENWhnbFhfQjlzMTIjTAp6e1dfQ18qWj1VU3dAWV5zcCtyPnEtWGIlbmshPjVeRUUw
b3RuOyl3fXV6N3VIQFM/aDkxYkBHOVA8SCFQMWtOcDAKej9mMyRKSyFzP14yWGE2RDlLTTFKNGx+
VFR5SE9nc3UhNEVYMzhSNVUteURUTz4tVnY5X1lqTGdWZWhLX1JEIVliCnpjMTRuMjJLZ0lmMSZI
TEVrdzxOXjwlbkY8M1FObk5Ibn5jP19+IzRfJFhHb09BZ3NKO2phO3RxVGN1STlXQlJ1ewp6SXVr
RjNNaCRYWGtUMDk/K2hfVFJnR0FRal5PN1lgTXB2MlRVQSZKJVkpI0w4RnRrQSokX3lUey0hQ3Jx
VjQ2UEYKel45YkIxV1lNXnhgbmtVRXYpYnVLRGh7VmtNPVVmdipicHNfSlE4bSN4d2orUVdVMnl1
eikrN00kVnQlI1F3QXZBCnpGNS1ybk8zKFV1cGhJNTQkPlhIV08xeiQ2SW5reXUzTGc0X0slM0Z6
WmslPUthdjwqdlU0ZSZeTTR2aiN5NHg2ewp6N2klcyEkSUIlemZtNylCO3x0MlU5fTdfeW4hSnAy
a0h1X2pGMTVeSm5YbGlvcCRIYXpWK3p4WmBlNlUxJk5mVXEKekRyKHU0WXQhWn1yKjNuJiYwMD9v
RH1CWXpmcnRfLVd2NnVAPV98cz4rdU1+KGhvUCk8e1YxZzleV1B6IzdCRHMkCnolclQ9em94IUR5
TF5ifGFqMkAxZyVPZ2l4b1JuQ1k4RGAyN2BMeHhOZ3ozS3I/dUtBfGhEdmBFZ3FLWCFQdiRJQAp6
SDV3JUd3YEBxOHtqX2NoMTlLQDdDRWpXKy14OXRuaWAxfnIqQm0hRTRHQyVvdE4zbUJAVk9LZ1pn
UW4qVSZESXEKeilyZE0kZ2xlVjBHUCFsfksySjBBQWtuZzNASkt1WiU8NHJid0xidWBCaF9nR2Yk
IUwoYygtdD9zTSY2PWdQXnohCnpTPzVkYl43cjlKe1RTPTEkd1Y1VGx0P0JJJGotPCQzMXtfdGpB
Zyo2Kk1ZRTxkJkZHXk15ITt7amZ3ZTRleTl5dgp6YEBAPUA0fkFtLVZReGdjMm1PSjhNMSZ6TiFX
Zk02bi1Jd2JlKi1icHdlcEszX29rSXRBJDdQeEomV3Y7RjxeU3gKeiZIPXM3WDRzdU5Xa0JxNlVK
PHc+QjU7ej9FcTZhIUdnI30pNiZSXy1TSmtROFZnMEM4JiQ5Mzx6RERqRDE0WUwqCnpAPXhQTWpr
PEA0IzkwWlk4LXN7STsmKCNgTz9RQUo+T29QYE1hZl9Rdz4+NT5CRVhtMmFDLWgjSzdpU3hre359
ZAp6SjxXM2ReQGl3QzRFSH1vQWwzNjMqblc9cnEhfVZiczRibDBsVjY3TVBCTiN0P2JtQHV4Knho
MCNXcH1BTSEweFYKeis8RzVaaDR1akpKb2hld09Sd2s7IWFSa15LVTVreUxqIUBlZmY1OCE2Ryt5
ITF0aTtVTmZmWSV3RjFuVHpCVS1+CnpAZ2lpbjxgYipQUWVyXlZYNUlNWmRWYnkySTx2KDIoWFBw
RzteVFJfclhgLS1Jd0h3XnF0KDZPWmJCUjZxbUZhMQp6SV9lZT92LV5jSCE7T2EzczUxTSFHTlpK
dCZhTnkkIVNALWRtWS1nNDsyQTZUaDJgVXhJVDEmO0EjJThKMVNXP3MKenhvX197TUZ9NG88JWRs
aDZ6PCF2N0pKQEA4fiE4VTZ5YnJNI31zQGthO0FtSUwjTCU/MW9YY0xpPThvcEElQncyCnpTMEsr
YThyTk90VXRQUTZZV2NAXj1YfCZYe2FEbyY3KWFKV2BNZWlwO0BkSnZXWXo3UGtTU2J1cz9jYVRv
RElXNgp6R0cpKW1YdTgzUSt9SWozeF9zNWxFbzJzeGFDQ2RpbTYqX0c5WUB8N2twLUxsVT1jWXRk
N0hoVE9ISXhXKXI8I2EKek8/RyphO1BwbnZjZnkkIzlKM09pPDNGMVU3SEl6Wl5QIUw2YHthT1RV
XnVGRDt0aFlzRWVNRzhaYkxMSUV0cEFeCnpvZiFSViYhO05aUndQalZxYWtlT3VoKnVYQ1IwXkxM
aXlDamxzRjFyXkVeK3NObTR1RFhndjF2QEA+SnR6O3RTRwp6JEgmLUNyanFjM1F6S18pKHpjQ3B7
P2JlVlNOdm9qJjVuSE1CSXg5eTRreT1aZjVjOFMzTEEkaFgwQyZBbllMbmsKejUraDxRSkNncXFU
Y1VVWGJpNGp5TjI4ZW88T1lMcnlhLSNtQkRnbWx2JH1eWGczNzgpSFB8OGx2NVhXfTMoZSUqCno2
UkAkQURfRT4+WlljLVV4MDQ7RzAxbCVNK1FHajVMVDU+KHFzQClxbiZ+SURQbCNPb1JLTk91PyN8
dTxOYVNtIwp6RnQ+REBvPTZnfWAlekFBV21STTJENjshaXMwR1R+PVRFbDVlWkpWfkJZRD99WH04
YSkkLSM8Qzxqekh7YjlCOUgKemRUO0YqXnUhTzRKWE82UDI9fDIjezRpIyRqU014ND16VWA/Y2pM
dmkqbmZrU1VMUz9TVCFGQmZPIWpkdDtqUF9FCnpgN2d6fkt5ITVeaFR9Z1AzM0BheXpeU2lfRCQ7
RXtmZjtTdT4wKj1NaiRlKkArU09CYT5uIU54UTRMNF8qej5ZVgp6Sjw4b0pIZDRoblc8eFohb0ZI
eTFRMVJ7azloJTElSGNyKCRuayZKIU16RyReJjlvQTBsZjw3MT8pRj5abV9zMXAKentHSCo/SmFP
JGFkSXNwS01jaVozJUZ0Q0EkdHFLaEM9SW0mWmtILTFMODxCRU9fbG1qe1EzRDtTeSo1XmFqTy1z
CnpDZ2VPTU09MCNaOCp9O2dXfjxweGJsazZzeEJpbCNnSzZjdnsmcnY8PzclfnRMTyVAWkRwKCZm
ezApPCVWQzxYNgp6RmJpbzF2emJjYXlxWUotQ0NYSSowTHNYQTJuUH1NIyM7fHdKX0JDPD09Ukxt
YVEydSozSXlWVFgrZ35gUSF2QngKemVMSXVpWkstKihUMn5eY1ZJdFZUWj85TWgkMzhWYFhNUEtN
VHdtSmh2NXs2Qj1uJXxWRipeNUowKkYpVTVMX1ZLCnpzXyt9YWJZI0BIU0c/TSZDa0FXZmpFY1Bj
cUBuZ30yLXctd3NNUVhJI0I9VyVZUWk8V2NyVzFSaTliTj1uZDVMawp6K2dDTWBiLTlmanYoOSE5
NmVSdDZAbGBPbXBLSE9aWUhaP0QrKjMqeXMzfnIme303KzM1a296Miole3ZsZTBtMVcKejtrK30p
PD5JVG43cSheRDQzb0J2ajZkN0FkMGowZjNYdGY+NCNGYlhPZzRFczByelIya2pRfTJVMDI0dXp0
MDRNCnpfMEJuNGBpIWI+ejBhaTtCTzZkZVFAYWNnQDkySCgwNmNnUCphKjsySEIwOFR4SW9aRkdF
PUwwIXZNMVZGSzF5Rwp6OXVQT0BJVGhxeXJyIUxfRXVTeHBUdn4zcjdQa2txS1lJJEJ7YS0tNCQ2
NllhezBrUDlmPTY4azFHZ2Q2V0xpUiMKemQhKUlaZFY5bzRIb3lnVj9RIUklPUV9ZTJSXk1yRDZu
czg7TlFxYyptPjs+LUp+Xn0+bykha3ZvMzE5LXBQaDBDCnpmbDFzZ0R8RHheKnVSQlZnLTZPYU0m
N1kxUlVFayslJXkrRWtpPiljQ1ExJU5vOFYpb3slI0spP0AyX2xsITtmPQp6KyUyaksmSy1iJjs7
akxObz5uZTdrZGdNR21Fb3pFQz4pd3dJcGhFQG4qXjZ2YzArQHZ5b0smQHV5VyMyb0QkKj4Kenkm
aDwhRiROfkEpOFNqbWQ7NzFIcn4/cFhzRGI4Pk1jK1ZuQ2N6dX1XVTJ6JEV6PklxQVNqcHglT1Ex
TGQxcVgwCnowNTklYjh6YiQhc3Z5VT51a0h2bT08PzI+Y1hjPD1ySDk5PVVUdlYlIWYhNiMmMVZC
dXprXmlLK2Zqdkg2QD5DRgp6JShTPjh2dG8zN3dmI305Yl9UNUpqKW1wdjYreG87RWJMUnRhZ3ox
PHhOM2hXPGVyT1JhQ3pVRVpWbGltSm96dWgKelgwYG5scX5HNiUxUm5BKF4tO1YociFnZFJpe09U
eEQ0TnhUam5uJU9ZfDdjMyZZUk8qeVQ8SVRFMW8zXnVyTSYjCnpKc3k/SGszOXBYYH0wQEBFP0E1
SWBSUlF5cjw1KHNCM2l1JFJ0aj1UIzYmT0pgJi01NWV8TXgoO3o4cWViNkFaPgp6eiszdjFeOFco
NjtXZlZVKmw7K0o2b3YlTlojSDMhK2cyNDVafWtIRnQ9cT91ZWE/VWVrOGIkRER8d0RJY344cF8K
enokP3hIU0BYWUlvP2syVSFFQF9gU3M/Z2N3KWVfST5xdVI5Z0R3ODglZzZEWTgrbW5lel5Xenxk
SnshMyVeU2R7CnomRFZkay1RMy1DNX1LMGNQPDt6ZEg2PVRYZDd1UCF5dkchcSlCZjxyYEFydldO
QTsxQmk0NUsmaWNMYntycHNPcAp6aTBPeUVnfCpzYTcjNW8yMW45Mm9KTn50JkZuSiVAUz5KemQo
V0pVRDZ7dVNvVGlHS0dOZF8wRTkoeFEhWTBeYGAKemhVWkQ2NC1ZbmpoVVFoNkFkQH1iM15oWFhy
al5oPllgVEw2azZNYGhZKEtnIy1JZChLMHlpZjM9Sms8O3BlZWR+CnpyI2t0cWJVfExYeEpPLWJo
JHBKUD09ZCtGNG9sOTBxNVFBdjRyKz1jPitQeipGM1ZBdUklUzU8NEZMbGB0ZDRfRAp6KGR1KFdW
T3FZayt+ZW1HMD5Baik/S2o2JkYhSVNQOFFMJHtlc25KTURMK1pQKHZ7PDBvWE1CRzFBcUhKUFFL
fFIKeihPSHhrRmglTTgwUkg7TVhVQmElX1BeNE5uQzFSZVU+TEdxPCM4NlljeFY/XjxIMnxJcG51
SUolVWJASUN5Qkk+CnpZayZzKTdaKEVHIVApMT1Pfn1nNC0qejJ9KWR+WkhTO05EU3lgPzxEb3hj
RUplZSpCJDxkPlQrVV9GMSNUPTNwbwp6fEZma1olT2dqLWIjKld2ZUFSLWd8TFQ4QFlRZ3FEYVRD
YDY9WldzWkpjanhkM35MX3liIVIyVHRuM2EqMHJCPXsKenhCbXFmYUVecWFZLWY3e1NHby03ZU4y
WlYpV0F2I25Da2oob19iZGJhRUhERCRpQ3UpOHd3NG5AJVcjWm5jQz1ECno2U3AzbiMkMH1SakFU
M1B7TUctNnZwcTYpQGl7bjx2NUdnMXM9T1FeNEZkaX44dHdmXmNwRjJsd3VuZ1JONWhiawp6KkA0
dExHOFA8WldkYy1Qbig0NUI1Mm03TDtWcX11SkQxK31kKEBSb0JzOFArajsofSQjfTdLI0tndSUh
THtMcjAKenh7c2R8PUk9PiYhOz9QQiZOZEVtVE9re1ZrSSFYMXRmfF5qSz5QMHFUUGdwPGk9KV5D
Y1cjeitEP3s5SlUzQ1pkCno1cUg8Rl9aVWV1JUQ7cHxZcDE7WDdJOFd2R0hUbFZHdkBKM2shMWg7
KGtsYnAxeFBkZHpvJmJAN3lAKzJwYCU+SAp6K0x2RWVVaGVMYF82MVo+Y2I8WEd4dG11VUV2R2Ax
dDZAfkZ7QzNDPUNmXjt6P3JTO354elI5PGZyfWZkJks+TFQKeiM+dUxmSCYoV1R0UkMqbl8wWEFA
enFKWXskNUEqcUk7V1p2YT9gWEF2a25yR2tgeUM8YGVnZEE1V0R2NiNNSFo9CnozNU19OyU0WEcr
NWZGLThkUG9vdFBUbSlIY0s7ZVVDQ2dfczUyaTcwTTx3fmtnMnkpbE1oOGF3ZjN0eVJzTXdpLQp6
PkotbDxfSEt5OEVldkkxOyFCVlMmQiloYkFPRjhPRV49dyhwNH1pQ3NkRHtpdkZrRllKNEhWbiFw
SEwrXjYpPEcKem5BN1IxJDs5ajtTZ2VxYkoqSnojUlklb0ZwbmlsbENjbThEJHEkPld5I3lBWlBU
fXwmM1RFODk8b2tvNUB6QGRBCnpjayU/YCsrLSQzPn10JjRINkU2Q3FmajR6XzQrcF9Sd2B2Y2gt
QVchQD9JTndlP2VLbkdINFF7aH5PWTMoTV8rYQp6ZGNOfG5pQCZfUUpEJilxR0RoI0xCalE9bnZn
dFA+IURMSWojJnN8fG1YelBJPGYyfG9IdVcre3J3eFNadVNTT2sKeiRMVC00PSZtfnZyNDZqe2hU
aE56NjUofHByMlcmRy1kLTNsMnxYN0xFVVRzO0dpQU9HRnViQmFoNSNNVCUpQFpCCnpVcnVZJDFS
NSleOzllKmE/fldnd0ZCP29aKFd0VV9BRVgoQVVWNEFgWUxte24qdGpBZGpDfSZ3d2E8eSZFfjtA
RQp6Pk5Ab3o7NHBlPzhsdXpXbjRLYStJJHZ8dXNCSnhLJS12dEM/WkRZP2syYHNwWEhvZGYmYj5P
QmBzWEMpNnpGQEEKemloO25KS0NfTTNARk1aejBpdTcheGxmWDNgIXRZV21sI1p+KD9Ge3w5Nysw
QWNjcUR4YH4zJEJXVktGOWJUVCYlCnokaGw+ZWBkVlhTOXZxVGluQ29+XkowQkpnKWMpbExXVmJW
a1Q/Yj51cFk5MUFuXl84ZzEqYD5pa3NqPCk0ZG1YRQp6cHI2cGwheiZVQm43SkU8dCRyXztFNHI0
Pz0waEh2WXFnQWU9UXY7ZmIqZl9edyF7cVlxdjV2c0d3OW0wUT9kU1IKej9OaExkaj4pa0ptSEB3
MTxXKmBDRmB+ezRncFU1OGNoOzc/VXNwOUFhTE0wPUxpKngxVTJ5JWQ/U0NuSXI3YUBmCnpDNWBy
MG15Uy1LejJZKTdte1dqbTgkJHI5SXhgUEAodGRxbzw1QUA3aEQxd1VxRzV4cVI8Kj5mb0pfYVMp
Z3Q/egp6czRjPyg3e2tnUk18fU4leEAjfCs7Wj5ZMzFHQCVCKHBxaFVKLTczTFlNdCFsUHpCITl6
QDdSd0FvMkFCRndoUlkKem9xcXA8OWAqU2IkaF5sJTdmSGxBVVJ9dTU2V3VDQGxZYXVQdXIoN147
PX0lJiRPU2BRP30yVWlNRXFuenBuRHZVCnpjKkNES3RFZ00tKj19WEk8UFlfYGI9bnlZaWglLSVT
Xk9UdFVPdmtCOSs2KEFYbkFMfElzODUyTDZvPjNjKlY5KAp6bCNWIzlNTGpzTll5UzBCVWdqV1ZZ
aS16elJVYXZJLVZ9OFI1Nm92MWFaKlYqbmBQNypgYG8jKD8hO2gmLV8mMj8KeipeemYpQGNALT9A
P3BHYnVRaVg5TXs/UlpZQW5EJXBJM15kNE94VD8tR0o1aWNjTGJIRFhSNzhIbXBaciNnNnBICnpj
Y2tDaXRRNFVDdj4/Q1NzREM1bSR1KnM+a0ohd3goOT4hS14zO34lPyEpMik/Q2p9QT94ajV2UGZG
UzwyTE0/KQp6NH0tJWktQTBxRmdTeT03QHwjN340WT1qY2spaCV7NGc9XmgxYz0/e15sMmxBX1hD
IzRNYXRjaHZgNlk2NysoI3EKem1DfSQpWiEybmR3VjFxODMrR09xRTBqQ2VXRClkc1ZqNDIzNEo/
I2BveHlfZUp4N3xQcjdoOCtwV21kNmhuO2dYCnpkeXwpQCtGfjJBUjk4fl9DO3JEQWdeNyZPS1lL
WXJxd15iPXJLRVA9MXByZUZzWD9Vait9OzhrZkB9KGpXUWNwZAp6e2Z0Uj9kRUBIcEJVPXBob0dZ
UFE+OUVgVChvI3U3ZkNveEJMeiR9RHVleml4NGR9ZmE9RUplTTkwVlRJJTM/WmoKenZmS2ZVbT05
ZCkjQmwwTjVRQXx7bmYrK18ja25wfmoxSlc8SC1RJG43JDdoUE9adWg1LWFSaXVZcGtMfiR7bS1k
Cnp4cXIjSTU5JlIwdWJiUVNpUWl1XmFBR2o+JlF7T2JITTc7Y2xgWisoVHtVPCRmT35fVDRPa19e
YUBtV2NXTDd0YAp6UUdhSStLamZZb0A4OSR+UDFUQ0BrfkQrZ3Q9a29NMH4xRGJuQmhGflR2Nyh2
I0dATjd0akF1MXFtU3Q7SUNPJnIKejhIYC0hWipUbk93XzVYVnNhcS0yZlpNJF85XyZpbj9Ee1RO
T25ybnZPUjR9JEs1OVZMWlR8V1ZLRWo7UiNGQVZRCnoqI2NJJllAPCR6cVE9JW5PKn59bz9Aa1ox
OzxoJUZXQmY9bm04eThgWW0wdjdCY1MzMUk2NGthJEgkb2AodiVxVwp6VjhKKG91N3lsQFBKQFlE
REJsMzxLbEQ1JGwrVCpqQzh1VmlvVUtnVnkzIUptNEcxcCF0RFFBaCVoOG15YDt+eD8KekdTTUlx
bUIrOE1kJD98NHNJWldBIXl3LXcoaTJuQj5PSDwkfER7NSZ3LSQrKGghdk41WWFzSH16TWJMMGVf
Q1laCno1RWU+N0M4Z2ZSXyZrJWRsIVh2bGhFMEd3N0VWNDVTc1REej8yYSo3dn4kVyF1bD0pS0Mx
KWdZOSp8fV5rbGdxXwp6VHJCPVlIO1U0dHRrQ1p9I3twWT9wQXU1bVMpZkEqZVEwVyRWVUY7d0Uq
d2Z5YVV0RllGP082SjlffVRLVnd0fDcKelZEejxyITcxdmkmOXpTanRMfH0yWnBwdyRuK0ZsUWdo
dXMmMmskdm9YOypXXj9HSUQoJTVLO3UldCl4OD16OEk9CnpDcC1iT0VgUGFXdlZ7fUBKdHN5cHJj
IVlRX287bWxWSWBkQ2JXN0IoJmVsTDhvZmx2Nm5idzliJCYkbnMhUEtJYwp6ZzteYldYWWtSVCFN
PTV1WGg9azt3TT50bGhJMGYhQmlhY15qMXA5ZzJtZC07bSl9RU0hMkp+OVlFY3A3Rz9ldn0Kejs+
b1dTems0Km48NlooYVp1OEB2VjxDP2lLKjNqI2pJQDtxZzdhdFlVdXtaUmpsekxFdkpWPlBldWFo
UipFUWdPCnp1eHRuI0UpPEJmWnRKaEEjTjwjUFpROWphZ0wtRGw0NmIqc3l8dmFyJkphZmt4UD1l
U00rRHtvK3sySyREVT9Obgp6K0gjQzFSeVcjX14+OHYpSVE2azcjSWZpJk4mb1REWkVyODZPcVlF
UFVMVi1kP1d9ZGw1VDg8bWh3QCFoQ0F5JFoKenVQPkYjbWFiOFVSVF5AZlojUjF3PUMkNEJtN1Ne
X3omWkVrdm0+ZFk3SzU1SmQ4MGFiYWRzeDRFendlQ0IxYnleCno7a2RhSG4xWiNsJHgmQk17b1g7
SCtEKnRIWCgyJCM/c3poKDtrRjBydW5pfX1jJk4rUDwxMDJgUS1ZTm9EPjx9KQp6Km1QTnFYYnwt
eThMND1pP0dOVjJHPXUkbXUrfnB9RTIybSMrPnoxaHtmUDJHVUsrRDdvfCs9cUg/di1AbnMpcWYK
emNmLURHc3FmLT9CRTRFbHAqJURiQjV3M3R5JndyKl5neUEzaVQ9SmxhQWR9bnRCKEd7P20wUU1V
KXhyVUFUK2RwCnptPmA3clBwd0J7I248RDgoZHFhanVtND9OeDU9fG8oQ0tXQUReKTkpPURIQGZ0
cU9ZeTBhP0lYKEk0UUR6Vj9FbQp6Z3ZlWlNaTEY9cC01Q1ltVEtBfmQ8MD59JU5iNyNlTj1zV3x5
OFMhZ2lwXj8lUS1FO3QjZ2wmTExOeWE1QkU9LXMKem9NPSVlN0AkRjlUTVg5fFpAeFpnQlotKnQq
bGspRHlpfntVSlZjYmM4Qy1JTWlyUCZeVFJVTW0lOWlRMVhUUjE7CnpkO3dJdXZzRnN9U2J4Tlho
YzM5bCR1PlUkLUZtJmczNVZUQGIkKXJ2ZGBafk1XfmY1NHdqXjZWUUl7KjxqKjFESgp6RFdAaFZy
ZjJ2clJEVjE/OTNuZio0SURgVmstKncreHAhMUp7LXtPeGNfZUJANCVwfTVqJFhDblpFOz84ejNz
JiEKekJWOWtTPnhTXyFDOV9MYld+N1ZpdmRIV1VSPzAzKDVocyt3WDtiSUkkRDd3ZnRgK0hpUG8o
SUZKdWlXZHp1dHNeCnpufDZ5YkkqNiVAUUBiKzRtQDB3d3JoXnh+TT9ybHElLSEzVG92R1paRFhg
NDZFXnlIMnAxbUlDNmVpMD0rP1ZydAp6SzkpOGtXVSNAWkQ+aGV6ck9vc2pJc2dEUj9fM3ZMb1Qt
cz8zIyo/NVVVMFYjN3pMMSk9WUo9cHVRVXBtU3tOTmEKej1UM0hZe2B6UWxRQzlmeSlLfDZuX189
ViN3bEUmemRgc29nI0leJEtGKyl7Zz5yUHVLUD9IPT5JfmxRaW0xLU48CnpHdHxUSmo7RWs0Q1NR
eWVpcX04MkBzZkoyMD41dGozKUJ5XzBUYW0kS0AmcjNTQnJzZVozfGMtdlc0Y2dQNF5tUwp6MDxV
PXA7aiVgKHMtKTZMZyk7TmRyNTc+c1l5OzA2d2xFRG5ucSNgNU9AODJaI0JGRklocFlWZE4wZXpA
Vngmaz0KemQ/REIpPkBATDV2SCR0UWx9cXlBdkBBTHdKYGNURVI2TGVJdGxDPExxLXtQKUtTWD96
NyhhWD1Le3M8RzEqdDtOCnowSHNtLVVCYHgwclJ2RUJQWS1MaUE7Y2VsOGpKQXdpMHltU1Btdysk
N0BzSFNAdz50Qy19Nkc0Zj1Ic3R7YzxjYwp6KiomU31WKWdNQUw2PkxjSWFQUFgoSHY7OUhmRFpD
bjA7blZeLSFZR1QwbDN5UUdxbWJaa3BAZytuJi1ZR1pYaEgKemNqPGRAZkV8NFptVE1eNVh9eSV6
cnFmYDdHUSRKOFh5VVE/TyYxSFozZipudDJ4bEola2BQQ35AdTNeSSR2ejZBCnpZfGM2NzstTXhA
VH01SUhUVGh0IzJ7Q0dCKVNLKUtLeVhWNTQmQiV9P3lGZj1qZThiWm1VR0tqPzBVRHNEezYzXwp6
QGw/NWtzNjNmOShMZGUmX08kXlRqZHBrSUMjdyZ5P2FLJG45OU5PMzAmLUpNKT9KK3w9Tms5LUxw
amtHTSoza00Kel5JbXxrT3xJYzZWZXJQNFg+T1lQXz1TWX0pO0syZVZOVTEkI0ZwO2JIe1leZlRA
QUp1e05selM4XzAjTllsS1U5CnpsQ3Z1fmZOSHQ2YnloYWpRIyVKQks2LXNlKzI/IWZCNnZ1Z09O
TClXT3U5MFc3UysoR2NSPXswY2JCajtWYXchRgp6and7RlpXUmlWI1grc2coR3c9cmFsK3xGVlQ7
IXp0RiRwSS10OT1gSDZCJD4oMXZWMVI+M2BxRkNhSDFWaD9nd3QKeldAbnY7ZGxSbWBYWHNKRk5e
aX0/bUZFZ3E9a0MjcyFwKlN7UVZNTVBUdVllZ29FUCt9eiQ7OyllNDJgdStlV3loCnpuWnlDcVE+
ej5JPSU8NDh2K2FTOSkkc00pXj1aU3dJLWNIbVNxRlFRKztIbylKIypKYEBDVXwmSGs3Z0hQLV5H
SQp6dl45XnZxRlJnbGUwey1CWWQ3diVRN3VSb1dzQS1eUFY0KmZFQmd9RShCPzZeO1FBTzhROTFG
UCZPT0NaeiYlNm8KelUyTD0oa0dvJiZpN0lQUHpKYXV6PThuZVd7eWRkfGlCc3RgKHVgd0NzTUdT
OEVeVCZiPjMzfGl4P3BkYk45bSQrCnpgPmc5TyYwTVpDamItd2xAb0NlfSFtYGRYLVkpMFh5Y21T
cVlkZ3FJUVV4SlNXfi1CWXghSU5zQEc/P0ZASWx8Ygp6VX5hQ3Azbz0yb3ojN1gxdWNAUyZDS1VM
em99UEg2JWxMfT8zbm92c3pEfFU3I3U0Mm40Tj9RTDVDeiE8dGo2dSYKejkmSmdfY2Q+TW5hNVcr
Iz8zbXVVK3lfbm80OXlxZTFKdmIhbnRfTl8wb2c2dlhkUG9hXzhsPll2VXlpQjsmTiRiCnpHX0Jt
KzVSczB0anxHbl9pc0BNdih+QyhqdGAmT3VtMXhSXmx5PkkxNV5BZHxFZGp0Q3FTbDQ5eytyVm5Q
ISR3VAp6M3FRfUBkdXIlfCF1fHk1YXYwVnsqQjloK2k+bXApaEVrJjZpUTU/UVJ0PCRXYjgpMmJK
Vk0wT3MwMXx7dD1uTnsKem5JMGxUdiE4OUpVKEcrPD9KN1UrUk8wUHZqV1psRnQqcCVqT1koaENC
fU9QZUx9NTA5bj5ITWp5JnxCZGx9ODRKCno1Wjd0O2hXdDlQK1Z3XiNqLX1sQ2wwZk0oKXRYZ1hq
cD17PG1fcG44YXhZcjBBVUBXPjJrUkFScz4mYUlJPj0mZgp6ZV4mezFXaj58SFBLVTNDXzM1MmMj
Y0U9NT5DVDF1JC1ibmNZKlhMREpXYFhkSG9GTUMlb08mcj5fKEBESEZeamEKelFjIVQyRmoqWntB
V1ooMm4zSm05NFQ5ZmB5WkFGJGI7PUJpMkZkbjEkR25HQUBrWCRMKEAxbyN1blc2el9VeU0+Cnot
fjQ7ZSt2dWFlRTQ2KDQ8PCZQJVd0V1NwI34kO3FISUNpejMmM0VpenJJbXdKNWpSdCNNP2pxYDwy
JTctOUlQKQp6cTRifEd5O1A2dndMNl89bXotdzlxKzVReFdPcX5KUn1XSCpLdmMjUFd3OFkyRz9Q
eWA7ZT9HWDhMMGB3IWU0KlUKelE5Nyt0SGZPbXdqUWZ8JCtaQk87Q0YpTSZiUFpRQzVaJU40dj5l
ST8lNFQoVy1DcD0xbmVUaVlkaUNMPko/dDhoCnp8NWU2QUl+OCpjbVZUVV90RTAqYVMlRFg3Qjtt
WmVUNSVWVDw8S2lFKmZAViNweEAkTmg+TjFQNEJzTEhkUXxqSAp6KE1FOXtmMjVEOGVkYkQ5OE9j
M3liVn5KY0t8c0pvS1VOJiotN0o5JXM9R1ohbXk/Y2Y/UGdgUlVOUn0pVVM2QXoKekk4KEpEaXVz
Sm1CYmlVdW18JHhWU3V0WmJgaCohREtzPFJeIW50QVgpZSp1JUBMMDF8QE1gbG5eNnE5b0psWVY2
CnpjcU5uTjIyV31YKGVHK3ZOOW0pYDtsTGNjdCZeZjxkfUZ7amBMKzI/PF5ibGQjKm1SbF8pMDR5
KVR7PSp2ZCt7Ugp6dDJ1PlN4K1U1dzE2eVJOaH5KXzV4T3drUUZVRj1LMTlLfTVeRjFrNztxVnBJ
VjhQdFJfX2dgMnpNM0plK2wqJjEKejwyTmRQd0hDUUc5UlkqeGEmfHk8cmBuTWE5QWYzRVZZSUwz
ZWNlNUlDJGs/Mk1NV3xUOH0qZmFYXnYoIUtJZ2BoCnp3UWk0Ujx9SDxzVVllKUpWNCE9WVlgRkd7
YzVgeD8mXitLUExmPDVLeD9NSz1BIWN9O19BJExxTyomOUtAd082eQp6NEQ7YE55c3FzJEdAMChH
Z3o3KUMwbEI5V1VSTEo5Uip9ZmRLVmJXNTtabiplZzI/LTRkJjB4djByYWgkdjktZEUKenoyNmRY
KkdgUFNzWUtZRGpyVWRNWVd0YmlGc1g0JSZpJj11PDBzOD5RZlEjeWxBXihIbj43RUZYWCs/X2BB
V3RvCnpnSFU7VGYjSSRxemRsTUdhPz9ASjljXkpTQDl2c3RRRnpmY0c/ZXJidi15JWF7TyshRzkl
KzVpRXwyOFRVRj9keAp6c0UjX1JiYkYjITRgcGdyUUMqPjBWaXh3WXdpMk5iUil5fkdpM0A0WD0+
YGlhbiFfQEtyfDdkKzE/ISstZklvQmMKekZ3KCZEbklyI1MyWTQzYHdMZ0g3MHpHe1YtP3V8Zy1A
JGIrXm1Hak44VDluYXphYW9acFhkTWlYRl8weD0oR1JXCno1UTQpJHV6e0BiUG8lKEJfK1JBVTgt
V0txUzFIOXo4Tn1NaGVGfj1mUnh2WDZ3dz10XkQyZmh5c0QhLX5wdEw0cQp6dylrZUJpcDl8X2st
Xkt0IXNHViMzVmxeQ2p3ZkJyQmE7RHZIVTkpKGJRb1ZDaCUkekt7YCE1N0Q4eFJHKVpudz0Kend+
cF9vd21JfTFPeGVFZVY3YXZSXnNzPyVpZVJ8UkohS1Ioblp+QnpUJSpEVDZRYnw1aU5YRWF4QmRP
P05TUlNnCnpgUCtWJmFWfGtwWVNYNWVzN3FZd3Y/MH1FUzxEVWByRmVXZStpMG1GYXpqUChZZGpZ
LVImfjdpVDFpSkVtZWFaNAp6aTJnQEdNKXFWR0IyRjEkaVhvMWgxK1A1YXQ5U0dMa0BeUDQmfTFe
MFVeV0d9ZWNEbmFyMEVnZ0gzWlRLXms+dG4KekxmVGZGMSRYe29uJGdVKDZYOWt+ODhGMGk5R3FY
SjNvcXJLTjdGd3x1Z3xBJUg5bn4tNUF2eyhedjFMUG53UUhqCnpEKU5uPW1OQSs2PSgxakNpeWRY
X2JUPGtuUWUtMlNjUjUjaCpecjA2SH1tbnxFdnFjPGRaJSpUKHx2R2cydURDNwp6JkM3anJOfGs8
bXpVQFl0S0F1PUdCail3Y3ElRGBwIVZ5aTJZfjlGfXlgcmt0K0FAVUVhTzZWeksxRX1YYytVbDIK
el9HKV5mTHgtUCg+Mld5KyU4JSR3IWcoXlF0aGppQndlM0xpbil+PWQ2YllyU014KyQ5P1FISUgq
NlNZfHN+Wmp5Cno5Zi1EJFNJK1hJMU8+UjYySGhPNEg2c1MwMH4/b3klKkV8M3FnOTNLYH1nelo0
U1lpITVaPUR8XzhHfTl0UjZCUQp6SE0zTHE+WldFRnIkaCRsNDRlTjR1e15hYWpuS0FPSXtuNDIt
T1ReKUlkSXkwSEFyNm4pdjNAPnpPWVN9VWArN2EKeldhe09KPzh3WVdWVyhTeXVERmZXUHNUN3g0
TkJgSmI+PllXeDNnViVVWWtRfS1FK09VU28qVyRDYWd2NVkyZ1QhCnpIbX4+RXhsKTY/eXx4fTAr
bGNBT1dLfV9MWmEyYzBVJm9yUXgwZ0pfWnc/K25TWVRXT1QkP3VZJTBmT2M5RStXMQp6diQlRHF1
XmF8TEZfV0xgRUxeckU3IXhKUTxrXzthTU0tWTU+fjFXcHlLe1NNaj1+OSFZTDFyRlpjYU52dUZ8
bFgKejZsRHYlbjZKfkV0MFRCTDE+KVImQkk2KkR2UW1QWHh2I1AqM0pEOWRAYXd1U2klM09iPko2
TC1zfCQ5UyM7NEZaCno7cDxWdmh3QVk8Uk05cVBteHpEPjAhbFk2T2lxR3REZTJQZnR0TnFZJElO
az8+e0AoQ3RHZTlNRFQkO3RTc1I3egp6RS0wZnV3ZXw2dT9NVHZuWi17c0ZWPCk9XklYTGg2ekM0
QGtONmRjUilUVXdmTG1Cej4xNCFjfEhocHdAQ1E7bU8KejlybFBxIUI5IStMT1JQKktzTiN8SnlR
O3MwQVlVMVF9MlpSTSgofCNWazBnZElhS084elFrNkVvTz08O20xWW8/CnohQHtRSz1qUGc5RTEq
TV9SRSllayt7KXpqZUMmI2ZiQSotUjFhO2ZLcH4+fXpCflg/fCVnTXJKPXx0VVBVdVBlTQp6Tkt2
RXlfN3hBP21XNWtlamcjPiZ6RTtNR0t6T3pQKEhLYCZSSjBJKnhjVUNTRU4+KUd3UDZFSm97S3xO
JWA3XjkKel5QI2lSK0dodERuYl9EXipEYFk4Yy1gPkkkIW4hXjVpYDhzU0VqSztYPW5ybnFMUWYo
dXJFRXg0I3VDN1QrM0tKCnpzRTwjfk9wRyVsSXRFSUlKQ243PyomOXFJdiRWZGJ4VHQ3I1A/dzt0
QXt2Zm96Q1lrX0FzfUZoUnw3NUZhamt6Rwp6ZFNgajZ3d3xBaXg+Nlh6MzhnelZ0dFl3Z3NsQGAq
KCRYM290S0hre3ImPkV4eFFKVSNzamlXfEE1NkJZYHM/RWAKejBPZihNMCRDTnxvaFdsJj4lUFBL
I3xXYko/cGFLb2M/eEJJKXFrU1NWNlU4WiREaWwrVnp+cVg2UCgzbkJffTdkCno4ZmUzcll3MlIm
NnwwSEVXPW1waDw/NXAoVERVIXMhMGtGek14RldNdSEzfSRwTm9+MW00SzxCS2orKypmaW1McQp6
dk09Z0lqPVpyO0d0WG5jRWlLaV9KcztaPC1ydip4YlQydyZFMSRiKT1FS1V5YkMtclA8MUhuM2I+
N35KREJVQyUKenVQISg+N09eOEtRQ3E9JSNxTD4mWmQoZnRUZV8za0g4bzRNXlVNdEZwa2BTfCNj
WmNRcV8/Ji1aZ2ZBMiVMcWVtCnp1QzA2b1FiZ1p9VSFWVWFJPDMrdHpxJmZLWT98NFZGPGNeeUdM
a3IrTkdmRiU1bCs9bGlUNEotNlV2Ri1vI00lTAp6Yi1LRj1va2FURnpDMnJBVGduIT01TU9valg/
PnR+bipaI3w+NkxjWEUzUkFQI1FTeDFuPVpqQz5MeSR8Rkw8X3wKemsoM2VHYmVtJClsNVhHXkVK
OStxTG5HWjgwdG98cF5INXFEIXFJYW5sYFY0bz4/MjN5K0RLJH5jZWlVOWFPQ01iCnpRX2JrQ1gp
XlFecElhK2BNRzd8QSphYGx5Y1V6cDIkYmQhPDdvYSV9cUN+WV95VnF6aEp2QztaQl9nUk49JCFz
Zwp6UnVGK2V1bl43RHlqbmxWZDlVbnhBXyROREtZPj9tMl5OKStmZVlGQ2t0UEVFMjghJGohck8r
X2EkYVRxUHViP30KeigwPH08ZjZpN3tXbHdkTGUrTGtgZWBzPGoqUlElSmtQMn0hbz9FWiRMfGpO
VCFIazkxWlhSJioxXzQhQVQrKWYoCnpXO1dKLUVeJTYkTzl2fUZgdzFkWTQ+RDZYR3BBNTlob29q
QSpfaEB7Uzs/LWkjemhTRyt1Sik9LU12KXluIXJOXwp6SUBtTVBCUl5xdGtmaEE4Z0BKKmdxNVFf
aU15R1h2YHNSRFo1bkwtVSt1YylqITBtTnpOSmJ9eXVgMTMwQnpwQmsKemt7VjV7dkFxMUwxc2Bx
PWBZOFQpQyYxYThUPSQlfnhIdldIej9GUHZZSG1EZFI7bHJBeit7OFRrYGtxSDhwckMlCnpZSjNY
P2czUSQmQlVESDU3d0E5d2BIKWBMKXROJTZMU0o3JE02fiZoc3RuWmBvejBJNztHU2NGWCZlQXxs
RHgpaQp6MCZlXklGM2Mpe1pSNEZFO009VGArO31uMXgmcTlpTXVxJTxYRWZAbFRFfmcrNF98ZTNv
UH19e2tyODRXWFVUYWgKemNRWnBlRlFzOGRVQVR9IU5lM0JnRzFNUXhVcVo5b3ZLP01vRygpMy1Z
aVg9P0FlYH1xIThMZHpiQzt0LTxZbn5KCno4d3lkTD0mZjdWdTlkaEFtWHJnQ2d0T2huO1owajVl
dElHODl+O0VwVyRuNyR3PGo0QTRsYTBuaTlETzI5YDl3PAp6e304MFRBQXZBa2tTI3R4KGRuNCsp
VS1eQVBzRThvak1wRERQU0o1cSZtYWMjdXM0ZHlrZylWJmh0QXJ2dFltNEcKemgjeEtNUiRBI3N0
ViMzREluVTlOaEV1endXIWhnUTxPY3Q+TjBYXzkhUTxuTUttUytGI0BnRTJCNHwpXi1MSmRjCnpR
PGk0N3lfeip+eFczVClOPmtfKGRFRjFYTntFUHVIb3cwX2JJdiFhSWxzTzI2TTVHaWxHY3JlVnsk
SVcyelNabgp6bCsqTDZIaWN6bkcqc3pFV3k5PWFPVlJ5ZFpUSXF7SUM/bW1KUz1vbyo8ZihGTHZK
JHpZbFlBRUgmZ3VqUDk7SmsKekBKZUpyTE4zQiNDI0k5RVdySTZnQHprJHBCQChYMU5KKThUdmFU
SFR6UGlqPTx1M3M5SEBsVHd1UllxfFZgOzx7Cnp2cnA9PUJxc088R2plNjY5KjtAdSN4dTU/R0p9
VFgpM0RvX2EoNEApPEdua1J5KkpQNHRycSVPQnQzWD9EOEk1Mgp6OH1Fc19WYVBJTFkma2Vzdlkq
bUpJXlVAQGZhJmlfdF99X2glR1RDM0FiLThwSDxhbHJQbUpxY3stb01CR0xsKz8KekF+T3M1Pzgt
WVVlXnBpYWJDI0Jyb2BMISReTzNjM1Q4b1RBcUdVQHswN1Uza0YhQzgpXiR1VExZM3VMcD9IeHlm
Cnpsal5BLTtHMUFEc25tQ1dzWGhsUUw3KUZDSFhEazY2YW1fY29Ma2woN3srQz44RCskV2A7X35o
KVByLTA9dl5wIwp6Mzxlaz94fXJoeSo7ZW1QYk0hPSQ1d1o4VEU+eldYNm1NPDVVc0ZYbUU8MFBO
KDNFMXZaOH5XYXtMWVdvZEZlb1cKemhiMiskOV5wP0JgRXxWWDxQfHcocmRwaj5Cd1p6aUIxPm9w
MFY2ez9pYSh7fURINT1BXnBGVUleOzY1RV9qZW9tCnpiUGYlQENUPHBMTWF7al95NThfYzQqSzJz
OFRoemZEcWBTZVpreis3aU5NPmEkVXw1TmlacT9fRGwwNDdTUUIhTgp6aipofmRsKlNgdlFMflQy
SCt0MTsoTERxa2w4dj1XN0VVfW05ejVKZz5CMTI9OFhAa1lLNXpYPSpqJiVaTkthM3YKem84Y1N8
MV44Y19qJjZOdzg1eWFROEZta2ZuS1NWKXpzdj1sYlY0TVFNWTFqTjtQaVNEaG01RHltaTEmdG9P
aiNtCnpJSDFTTlNITzxiRmtEbGpOWGZGaDdMRHYmOF9ySkE5NEA2VSlecUdnNEdSWX5eTWdEKkVq
QTB8KGZvQUg5RTBJIwp6MXBQUXY8QkgmYG1GTDVYbWY7czJFUU04MTUxWDdlISpSTTJ7ZjFgcCN7
O1Etdno9alBsQ3tKRnBUKlIyQXYyV1cKekt6alBVZ31MNj1tKWxaT2QoVDR1VWpTay1tNXQ/PDdf
cExjQCF0NyVyaU8hcWdVKU45JF8/Ki0/TFNgQSRSMloyCno2aldxfUZVLXB1ZFI7ZD9uS2s7Yztn
bl9sRyVLekNQU2tNZm9AdEY0ZFN3c3daRiE4UU98cClBeTBnKT9GPyo7Qwp6Tmc1YSFuNWpsKkNt
bHEtWmVPWS0pXiRwdmY8OzdAY1ZkQ3BTUT19bHI9RUtlKyZpNCNyOy1lcS1uPSVmVFcxPUQKekxK
Nzd6TERxPCNjKlIrUTZrUHJzKG1LISZlbFF0alRONX09Vnh1S0w0QWFDPipHaW5UNUBNZHhyd3dB
Qjh0V2Z1CnpScTczT2FZRShmIyR+MjxHTTFUWj58eCNFaVJESzZYNX4xcUJjOyhDZ1hme0hJNjVZ
JnJFT1NTR2FubmRXI15xdAp6V0BRWSFYSz0rK25fNXhKX2RyU1gpfl4ocjA3c2U1RGgjPDYpdElD
NTU/Rm5iPWZ2JXFhKnFkNT8hTzVUX0xaeV8KekMqblBpVFhnaz1eRzVTJGVIczYqKUx1YEw4bCpE
LTZqb3g9ZjcjdD5TZHtAMD1pKHpYaHtmaUQ0ITgkPFMqKCYoCnojJTlJQzZrZHJJc0AhfV8jSFQm
UT5iQkQjQE9hZ0psdTVxaXcrfk8me1RsUTQrWTR6SlYoIVV+emAlKTJPRn5OcQp6dVRORXpgM1dT
MCYpKlFBRzN+cEJAOFNkSj5VPnRMV0o0TkRpOzZuRDw9b1MpUnEkSHc4PUVRaCU8JHo7KCE2LT8K
el9BZF5XdmpiaD9HOE9OVWtEcHhHT1ZvYVFUN3l5Syt7ZjIwKXUoYXZ0dFdPQyUjbHBvZFRtLTUp
MzApWT5LTmBuCnpLYj1Pb2ApaEteXihKQGRsMTZHQnshIXJid2dDVVk5dVF+c29rRHdVWjV2WEdx
JkghSG9RI1EqSlErbilPbTZYNQp6N1ZKMkI/T3Fua3pLclBFOFlgYT9sVlQybig9ekdae29TbUpD
dkdXdFJ1QTwrYW45WUxqYy1+VyZWS3dSV2AtbDsKelB+Uk1CJHU8eGlEMGNHaGRldVR3R2NYe0sp
UnZUJUBOYD1nOXp9WUk/QTlYJmxnVlRqISpZOUc1d1lAMDV4QDNRCnpAbDtlflBpak8mazIoSi1E
NCQkd0lTO3d+YntyNV4+SmZaRyViUDA5Rjk+R1NGcE95dHNLeytkYHhUN1YrYXRnKQp6ZEoqaW1m
VWRQT1BeVXhNXzJMN1loIVZQQD5FfVB9NWM0eWNWWEZpRnFqbDxnNTl4TnI2TjltYTxpSCpmKyV9
e3EKenh+VTFeVXdObjRaPllxYzxTKmY0KUAyazxoczVLQi1GUSYhOzxBZGJvKFB7eWFHIWwpOWhJ
YWVLVlc8ZTZTMVhtCnpuKlREZmFfKz9rO2g/SDRtdW9FejVSSFp9eXphZ1dVXkYzWVA2TyltX1pf
V0Q+QlNGIXtQP0RgSGZuMSNGU0p3ZAp6VUNyZ2ZuS3NNWDwzPHded3lqVDw2SyQtTzY3fS00bFkz
UklYQlRMMGlBdz1BZGFyMkVrQ0dqfW0mRmFyQDs7ZFkKejwpQ1I8bTdHIUJNRDYkfj4hJiQ/V1NR
WjdLNkU3RUd0cE4lXlhiZGUmTCoxKFl3eTI0T0BITTklb0pmNHg8a1RwCnpJVW9xfkUqRS1yeXJk
I2RHY0gqPkw9TFV8OXlFUSQyP2RjNFZNeTUxKCp1RlVoIUpLUm42dVJuNXU1TWtmTEhnSgp6IUR3
OW9EbFI5SXVIc1RxVTJVKmVgVERhSXE9fCo2dFVfZ3tYdTIofl5PO1F8Y0tmJlIoSGE3OVdJbTB2
JjB0NkUKei0tNnQkRyRGfFpRb0okWkstSn4qdyo5X30mcjxBN3FFZEpZTXVBPGNuJUJJeHR7YFY2
TE0qbXQ5LVM5ej4mTWh+CnpgNkRhSz5+IUdiK24xTkFFJTc+fDEkP2t7QiFGb2A/T3Z3JGB7aHNK
KGA8PmdwJl9SMGJCeXVAUD1XJHlQU2p8fQp6VGRkelEzPCN2WWQwflpKPn1+VnZ1QiNwYCQ2QXdT
bT8jWEQ/YytqPD9NS2hWKWtoYFIxNCFLY18jQT9tS2t5RWcKek53WChLNXtHMjxxODJ+WnRfQmQo
b1E8fkx2ZGVvQzw0aVQ9dk1kbl89fChkI01tPnZUPDlUd2ZCJW9MRF9IVlYkCnptNE58YzxCKnNt
RXxIUlImPF55czR8fl95VzxibTYzRTI1X0xCSyRYPGZpJEB1MDZDZ09RVEstdVVtfnVDZjskYQp6
QXk/MUY+b3lwZFE4eFAyWSl+a0MpN0VgMWhaa1dxOFNMMyh2RERTRChyME55R1V1PUwzJnExdCYo
X3pgJTFiVU4KelJMV2pqUmB6Q0hVOCYhLShpPkBJdHxFVHZiazVlenVvRm89bllmLT42WlV7IWVV
RE1WdHF4Z0M9M3BxanFFXzlCCnp6K358MTxXcHcmREdqQTs4SFNRc24zdkA5MUwzRHd5LUlJKGFf
TElFSFkmWiswaWxZaTduYy0qWkxjWE1xQn52Twp6PTByJj8kVmd1b0B9VFIjP0VnX1QtQ1pkdkY3
OTRfcDwwMXUjcHdzb3xBLV5wUmEqcyZ4SnVxOzZORShmNFMhfFYKeiZGa2x0Z0t1MzxkaEpUcU4k
Uk5Gcms5a0tfSXh+SSklT2VJNTVPcTVOOWgmZ0NkSXxZKiFKYWI9S0JqWXBqfjdUCno5VjQqTnZS
UGV3bXx3TkVOJlgjSUBTQDQkelZ2PHZrZjAzPmpjfHlnO0Qybys2K3prfFNWeW8mYzVkfEhXM3Zr
WQp6cG48M0hrcmFeN1FNbUUydXJReWMmQ3JQKHl0S3gkYEpzYDNhV1o7KjlsLV5+Zks8ZlVvbHBS
ZVFxa0Y7eldFNWcKejZ7YCp9QzxHNkBQaHN9diNwaEw1U0NoI2dBeFNtREtXYzxKOXtiKDs0RD1X
OWBSQSR1SHA0JStFM2dePHh1SnMxCmZAUEU7em9SfURTT3p2ViVUdWR7aHh5P0M7cEcoaHJ7UHpD
PExESXM7CgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFt
L2VjbGlwc2VfaWNvbi5wbmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaWNvbi5wbmcKbmV3IGZp
bGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMC4uYTEzNWM1NGUxNDllYWE5MGI2MTBhNjljOGY5YmY2ZGViMDZjMGU2NwpHSVQgYmluYXJ5
IHBhdGNoCmxpdGVyYWwgMTU4MjUKemNtWDlfV21zRUgoKz0ocU1UQCg7eUY+OSgrQCpNTjRVaXgk
NCNuTEk2ZmZAWCNpNipueUljNzN5eCpUQkMpYnxjCnoqX25IMFhHYkQ1KUQkcEtObCphKjBFVXZI
dFFHKE8xTntqREt0X2FxOE0qIWIzSUs/dURhbEd7YCgmTVVfK31YXgp6Xz9FbkQmazE+LTdgSXVD
cSE1bG93WFkyR0JkIXB3SVAjbUY2NGZFI0I2NWQxO2ltbjtBZCYlZENhUW52ckdARUAKenFlYlRs
bF5ueVI8VDhzVWJjfC1KUEdCMnBWPVptQ15MdWJGVGk+OEtTVCpfZXQjYS03OUMmaGRVe0paeldh
dXJsCno7b05hSVp8RUV9dn4lU25OKipfflZATEgqTUl5KmY5d3ZOUE1GTU0qT3R1dXFtLWhfZUEz
aD53OTx+JSt1SEZ1eAp6UHt3MSg0Y1FtbyFpRDdVQEkzcjdsJmIwJGQlJHNWPH5KPlk0Z1dnb0Mr
eVk3M3UmVXplPHlkPyE7Vlh9Ylp3cHwKel5NNmRMUGl6QHlKVXsxX1NGaUJJU1VKa35QRTEqSTZF
OTNwPDVjUmA2KGohWlJVc08zNl4mb3o4KTt6dFp5cnUwCno0RCQoT0RjT0glSVAzaTkwenApPCts
PzBpQ3gmUj4tc2pmSnowUV5jbHZ9akxzfC1xNiVYTF5qP0olQyN4fkA4OQp6KkdET2FEPjg8c3g5
RCFDUzI4QmFsYDFrMzVMWlVoQk9+QHdrYDM/a2JoSnBYJXVEQkF6Vj8xYyVXMXh4aTR5NEEKelZ7
PX5tNyVEWH49eWg3bmAzb21sJVUmKDUkNTg7X2k2PkIrKzJTakV0TCVgfkBIODJDVH57dHAwbEtB
bzN3UyVnCnojS08hckY0ZmpteGJwKiY0SmBAfDNpVStEJGpXfk1BUD13ZCppVUxvPUY4KmZDeX0o
KzYtXnRNMlpKZSprJEtXQgp6I0IqMnZQMHV9UE90JEJFbVEpSnVSSCtCdkN1WWBqNXhDT3l7QkEr
bi1LUyt2WWFtPjg8TzJeWFVJM0RHMVclVVYKejU1KytCX29YRVE5bVVRRUlpSGpWdyR0WWYqem58
VjxfKE4/VnNyKCtEK2hrX1MySnR1KVJ7Y31NWVVgLWZyVlV2Cnohd2E0I3V8eml+TipNaW07JmdU
dkgpaEVEOSpkX2d4SFNaTkAmPnUqXjB6WG9RTVIxKCo2fWoldDtrT00pVWlzawp6cnwhN3RMUk57
ci07UUhYeWQ3NXtLZW8yRV9+emB0JFozWXd2RSNJOXNXSXtLRUFnekRCJGwpZ0lpUmMyYXY/YkoK
em5pS3NULSM8SihfNGs8R3Jqcm5VRktCcHdFLWAoYjRKKF9vLT83MXs4JDxwWXI4a0lURHFETDJU
eklLa3tTKX1zCnpfVlJHclFmdEl+VkJmJjNicDIoQ2l7ezFBN21fbkN1U2tQeyEpM3Q0b3pEN25G
WVZNNWpMPytoYzBJRTNjPlZ0SAp6QWZjbD9IIzs7KkxYKEM4WWFnbCp1REVhUHtRaD5yfDg0T1co
a1RYSFhIRmdNY05OdlNfNH1HekhzbWZqbUBiNzQKenpsKDxPZmk+O25CdkdnR2BLMjBrTGg9NUVY
JH4xaHpVblJBZiohLW5Ea3BkSDtIaVVqIXxseTdQN0k+Wj02eDNFCnpUQl9ZRSNHdVNsTFBXUkA2
bV5lP3crbyYoWGxROFFhXylKM25hXj9eZTFBUndKPyhxNT5+WWk1YjZRNjlyc0pqewp6V153JmM0
fHZAbmRfNS1naFF3dkJHP3xKU3YySkpLUldAdVkwTSpeTXZmT1BlSiVLPXhzOG5gSCskV0JmK3U3
V3cKem81Xj4yVzk2KVArZjdeMj8mMDRZKVcqJn1jUEEzQngzbFZSUzV3XylSSSElUjF8a1ZoQGs2
cn1mKEkzLSE1V15QCnotZH1XYnsjPHxCY3BRbT9SNEEwZmU1RTgyJXN9TWlKX2crZVA7e1FeZFA5
eW15dzRZWHleNkc/PzV2WnVBfSghMgp6Knx4NyNYaUIkYmB5PXJaQ2xCPU5lV3BWUVAySH0tLWR+
KnwkTlVhKS0qe2M+KFlwYVV2YzA0eEZGKWVHMXpPQXcKekF3NDZ4JT9wKGArYElkJG1zM3YmKzBe
cUp1ZFVzRVJ1a0ooP3xTUklmVFV8TlFfcWNnTkNYdmZQMG9ZZ28rZCRvCnpXNjJ5SHVmUkMqK2U0
ZkMpMXklbyFPRGk3c0V5ZkgjPnhpUSZGQU41WlkrdTBPUGVhY2stZXI+d14yNDAjZVJ2aQp6PWQ1
cDYjTkYkISk5Tk4zQyFwN1pnKGx8PEZ9X0dAaURSSlgzdn1JNzZyUWdtR2p5Y1lLNmZrfHR+WjM9
SXRrTykKejcwcmFAZW04S1BpI2RaOUpSakVHRkxiPnhtaVo8bF53IWMmZlRCNDhGNTRBNCVkQzMh
RXxiZXFeUE1qJj9+aXZOCnpfanhyI0g4V3YhTnRuT3pMQkpLI2phTzZoKktzKHwlRWtzXlo8PWlH
JmB2ciZQRUJ9UGpfPUt9T3x7czIhMjV5Nwp6IyZickBqLTVWTG5td0ViN2AxT3wmRjJpYDAoMSVT
MWNgQlNnNjlxSlpGNHN0ZEB4bShjWTduO1RnJSVGQ3hqbT0KekJwPyU1b2UjUjJfXktAXkQlSl43
Rnc1fFI5WT1ReVVDd0s3QyFNQGd4IzFLWGZwR19VTih9fGNeV1hBNztJTWhJCnoqSGklJFZCYnAh
ckF6ZE1ubiVBJTVzYTs2YmlmSVFiS3BXTjY4WkI8UGYlYjxPd0tXPVpedz9WbzxFfX0yPEJuKQp6
P0Y5MTdDZVZJbEpWLVJrJF9vaFQ/TDVmNzJ6KDI5c0M+RVo/Z3F+K0tkJCthUHNTSjQmKWJgc05z
X2wtXmwpX2oKekh2JiNzUmUjX1ZocVBOJlZDQCRTYUNZY2g+KmEjP2BwcTRydnJ+b1M5KFY7NXtU
d281RnVUeWk7NjlvQztRdit9Cno3alBgeXoyMns/UF9hUW5QPlElfT83aH0tK1NQUi0pM3k1Q2km
aWV6Wn1URlNXMCNqLVkwVlA1XnFTNUFJa01JQAp6X01HRjd7cDB3azJ4WWprWSVoemMrbW07MDtC
eyR2cDx1MUQtNDVFYlNrOTNvNipXSUh0YjRCIyF8VSNXX3VEbXcKei1Pe0NiSDlEQ1JhPXdiJERu
QG5OSjxYKVZgfEk0QEAwezNJbFVNU3xUU35fNzVlMk9RVFRnNyZvbSZ8VzUqRT59CnpXSWQ5QiY0
X3QwNTdTdElrRl95eiZkO19qK0hROGYpbGgrY3QpRmt6V15SY2c2JG0oMGhkaXBZQmRuXjFtRzFT
cQp6I3R5bX5XXilLVjFkRXZaSykmPDl5VkF4OGlJR29FT1g3flJuYnZHaXc9SnhfWGNoZ18qYnhj
NGJfbmkhRWN0PkIKemV+d1dkYyY2WmV6VXVqZHpAfWstNUQ1WihMNThVKSt1ZHRuQkhOfllpPzh9
NjlBI3xDJCZvWlU3LT44fGNBM05fCno3dCtyI0ZNanVMbVYjQjZTKl4kK2tVWnwta2MhcUpXS1Zm
Tz5+OG4tYGBLclRtdyE9O0kmaGR1dnRlWTdRSHFaQAp6aDlLWFkmMkJTc0cwMVRCMTVsSkZMYCEp
RGBWNl94LVNEYWxDdiVlcEYtbipMVVE5dm4jP0ZnMWxASDBUX3pXMGcKenVhXzVCVj8/T2QrbCpj
IWpkentMWVp2fHhDKlRXTDxoNCp0ZXBwLUg+b0pNQCVSJm1LNF5mWjk4JDBQQVo3WWxQCnokaUJY
WCNRRHEweTN1fFAzVyolVThVWEJtNm84IUgwbG5fQkZBX28/e1RwKEpjdGtrb2clK0FoRjYxdSFa
JHpxUwp6UkJfMTB1KmpvZmM7KCt1aShAanlISkRSaDUxfnRRKlV4SilDO016aUZvO3U5PnRvS3FW
LTVtJXlJPEN5YSYqeWUKekE5NjEkQGN1VzlLZXxyc2BRPj9gXkNKN2c3YTs8TU9rKUdkNX0rbktX
PVlFNS1lJHlKN0BhZCtIenJDeCswUiZMCnorK3lfZz9GWXNNWnV9dDN1YWBZWnNGMHNiYjBNIThv
eUtqfDtYNmNvcjJhbWxiK2B6XnY2bEN6Pmo0OSV7YFhOTwp6dUdwSTBGc1UjTl5RKWVkVmdmMTNk
I3VYKFM2Znt9SmNnUSMpfXV2az1kbz1VZnJUXkFueXhRY3U9SVFZbjQpZmQKemhuMG1LVSZ6VnY5
ckZtem4pdiZ7KXRGOV9ecWY2a3F3fnRXdSsxNF5sMighU0M/MlohJTtufis5cGNzNzE/WVd3CnpZ
YipiQUhYZ3tMZFdoI2BkUDBicG9aUkZsTmFENUlmTjFWSTZmNVZIUjNJXypVMHRsXj5EYSFnRUo8
ZkpQJVY5RQp6TjYwTm5yX3JGWXRSIWRrbTg2Skk7TnFZTGp8M2RmbX5iaTRXd1ZnO1gtODE0NC1f
fVZ2IWJiNyR7NHY9PWwpUE0KenV9bjZpeWRMX1RKcH5ZZEo1cHg+fEloITM+S291bT0jYCo9Syto
LW12I2RnMUJoajB2K18hQ0pxUGJnZnRnT1J7CnpPeV5GMDd9NGs5SzkxNF9gK1ZoUD49KSRqb3Bl
JmhxTk1XcTw4LThYdX1mVSYmfis5NXZNM2FFeFZOX2hjfUA2UAp6NTYqbjMoKG9KTSZrPilWaCls
dkdWdE50ZWFsT1lDSGdnSUpkTmVrQypqb3drNj9JMX5OQHw/djdVY0J0QXsjKVUKekFBd1YwSzZN
N1l0VkVTMUFLVGxvSnpoZkw8LXE4YG1hT2J+KlZLN2VgOGBxMG1JQlYhPmMjbmVheiVIcCgyckY3
CnoyP2BqY0Imfm1pMjFDXnNrOVNIKDh4SkApdmRMaTdKbTwtKCM2bV9iIz1aVihmUkNzPCMmPDNE
TlE7Z18/OyltYwp6anhAQEkrLTdffHNUTHo0X0VeXjhkO3laJUY7Uj48M1dzTkVTWlhFeS0mWTR4
dWRtYD1tU2VkJmBxNyg/Ui1PJDsKeiF0OGNPYnImLTkreUZ2RXN2QGw7cTY3Yns0SUBkV1dXNj5t
JTMhPTZ7VX49I2htWjRnNDljWDEofVFgKihzdHZyCno0YVVeTDtoUn05UylWeyphKTNmVTFCWWxY
Iz4jMUJVeilUJUpzWU19PUZ3bkUlR203eW90dH1wMERAd04zNl9jZgp6YFModzx7a25oJlkyMlEy
dEVMcD4zRT1gaz5jJFYyPXUkKXA8OW1uND1meCMkaUIoblghcGtDdT1aQVRQbGArIWQKej5XMXRK
ezlgeytkaSR8d0hqTHdGM0skRUZEeihhVmg/ckF8bUAjPW9qalVYM2UrQzc/K31+bnBSTyp4fWFH
Q29FCnpEdHoqWk1PMD5AcXQtNSlFN0JDPlJ4WSlvQ0JqMmZ4aihZclZMYmw4a2FzQnB1ISt7Wl9g
LX1hTzZQaiNteExeaQp6RVE5KFRtVndNJmJUcE5IdWkxSzNGbVE+aEJDUUxJJjtwQ2I8TGsjUWJQ
YXB3bWl9OS0kZUB5MmdTbj19JFNUal4KelNHQTVjWFczYEdQYXBIRTI8WHZBWjBiRE5eO0h5eGwm
cEEmUyVaLVU0O1ZqdVREQDYkWCtGc1RCS0w3LW9BNmZRCnpnRjQxQWxXLVhwMTx6c0tCPChIfnFJ
dGpge1doYnxjVDA9UT5ePUZmc0dISUcqaCV4MCh2RUMlZWpoY2JycT9IcQp6Nzs9Vj5jWFp0NUJn
KnlhdTY8KGRGMEF3JENHKmVDbiZJRXooOGIlNVJZZS16NUFGI1VuezV+fSE9OUo0JGdCKmwKeilB
OXtzVEkqeWRhN0R0UiR2RGUjbzJEfX5OVHU9MnFLaD5jcilLOT0peDhESzRraXk0X2VQb0slRipa
az8kU29kCnpvN1dIOFgzSH0kXlQ5aEtAYE88JHlPTWNWbnw2dCNDNlNPZ2JERzJkRFF5eXtwWVZF
UT5LQEJXbDRlTmA/PSVgQAp6Tj9UWU9LKE5Va3wxPkVZNntUan1jT3swVmhpISF0WD87bGchelJ+
ZT0tejN5Xjl8dkE8cTA8S3s+O3F5b3hPMmsKel5qYCUrTyYqX1o7PX5Ab0c3JmxxJXVlRj44Mkoy
ZnZqSDUxbCl2NDh3JihsSjNPRihZQipyNC1WNmF3WSN2fGckCno0UTlSNHc/UzslODJPT3ZoKDJP
VHgraylnPjZIfnl3T2NSPjI0eXNMT2sjS0QhP1lZcmpGdnt9TGgxYThocXVSTgp6IW1RZDMwWX5m
NClORUomQUA0fkItTzlkTHZDSEF2ezxpeCt6TFZfVlItVnpKez9LMnNIeFp2SVFDVGFSRFUhczwK
ektpS2VneTtXVEYwMi0+Ny0tYD9kPUpON1BsdGYmU0JSWChkJFBJITheMVJufGA2JFFAUkYoK2BM
RihrPlYofFNmCnpvWTRnK3k0VW8pO0RtNC1zJDJKIyFqTmVhb1A1M1YlYEQzfnVGKTMxdm5iIVFE
QVYyeU9QIXlrXkFVfT0xPn1aZAp6cShvbT0lcHwlRjE1JEYmZVI0IytvVURPRyRPK01aaTdRN2tN
MXdiUml4P3QkWHxQd3ImMFNteTl+VyhWQlEjPTsKendGenVfXlNQYC1lb2hoOSZtYkFhLWpYb3xo
bGdxc2srO01BbDFSeVY2ZDhIV0tOI2pSdSNfV1dPK341U0YyS3toCnoqJm5VbVA5YClPZXc5WUBh
Xk9nQUJiVTZ4cHFlQVd4O0ApJFRnbGxER3Q5TlAoVnomWTtlYDI0RE8+bV9WZEJaawp6PnVpbEFm
PCY8cGo/Xi1WbmwjaShSV1hsR1h8VGBLX09vKEVDdCpfUSFVPisqLW9wWigla0YtPExHK0FaWHBu
TXgKekpFcVRfez1ycGp4eWlfJE98QWxFPGxve0ZWeE44Uzx4eCo8dllXYSEhPjF2ZWdgMzFtXzBN
SHJyYi1WOVAjTV5YCnp3K0BDRzx+WlJQcSszaTEzeSFUK2UjI0BqezNZIzRhLSttfWt5fFpQdzFr
S2xScEo3NGF8MUNpSWA7M3tBMW1EUgp6M2AhbXM8JlAmRmlefENoZ0RDRkFoZj97KXlSJF9hJjc0
JkQkRUk+ZGM1RmokLTM9S3JjeCtgNl4we19IcTZMQnIKeiF2KDtGVkN0aTR5JEk/OHp3RmQoNHtp
I2RHdGMoWi1sI21DbEU/MUNmNE5LMkstUyQ1QGNaZj1FYTxLTz9iVUltCnpFP24/aDNlZ0UmP1c/
SmUxT2FhfVdpM35IMUM5Sm9FfEBAaiZKR3tBdzZEPXh7bTMkVnhGeHImeUU0X2pBRCNVTgp6JHw7
ZVZCPHx0b1Ize1RrPWg5UWhaeHBRc0s9K0Zze3MmNyNIUz0xLVIrP2Fmbzw9WXQyX0ZMbiYyUj9U
S2FGbGAKekZ0ZUw/MyZTa0tIdXx+bWo+TV9wQGdtaHw7SDljOUN9KGQtMTkrQG83VSRIOWZqKmwh
JHdMSjFlO25XVEc9dWxSCnpxZ1ZNOGlebXF2JStSQj4hVzxxNyU1JkJ5Tj9IbWw0UF91cm5uZ1F8
M1ktQ3hxd3NOOyRDQzBsTlZiNDA8ZGJSUwp6OEhMcWpWX1NgKEg/Rk8hRT5Ke2I8c0xtKCZsezww
P0c4NGJRcFMpemo5e1U1bjw3ZUNLcD9yMCNGTytodmImWWEKenJtN2swNihaKlZ5ej1MSTkzZDl9
PUxGcXJoKEtxQSVONEJoaTJ6bGNMYDA+dy02U0Y3Tzg5JT15Vkw5M2tDJXZuCno+NzA/MFVndTZC
TlBLfXR7eyopLSVWJVZzLU0kTGI+Pk8kK1ZLfUpZWENmZzYkI28oSkh4a3R5QG8xKkwxYjE4MQp6
ZU5BZ3tEXyt+dDEjS042Tk02bmQwYk1RMEt5T0RYIW1sSUR2cT5XenJONms/NyNBRz1SVGhhUS1u
MFpVbk1valMKenZjTz1mYUFXZEdMJHIhfE1SYW1VWX1US0Y5QFlBKVBhXzh8U2tBSl8pKytTQlhv
ZkZpUkl6VUlVcURpek5AWVgoCnp4U0s1cVJsWVZaMkQ7OXRkVFkxYztIZUFBUmdSYTElVXdpREFG
TT9SUk99dWB4ZERBPzdYUGo3XjJhYGJFYHFrYQp6c09gNzctcnxFbDZBOXlBWWJMSVM5XlNJTFJ4
Yl51Mys+USYjOClMJE5hJm1mezBMNEc9NVZgQk9ZbUYpWnxCfnEKem4rO3RRd0NOWEUxRCt9MF4m
JDZqMytfdiNDSkwmb1MwQjUrNk05KnxzVCRJYz1HY0dWYykzJTVKaH54ZXZieFRACnpFUUh8YWZ0
OEpoZ2NZRTQtZTxHaVolSk4rT35SMVQyaEVgT15HIUlPWSZrZ2x1I3xMZT9gYjA8eHBldSRBNXJ4
Rgp6JGNVeHYrd1RjbmNSUnJISEc5eG11S1I5UGJ4fVJUQiROTXBnLURsVW1WQlI2b1duKVkyVGwr
ancmKkMlLWwpY20KejgxeWRVWTsjcGFzSX1BeT1lPCM9KnJINUUpRWF7UmFKRHt5KGUqNG9OcX1U
S3hnVXtAXjs4bGZaKHtiX3E9K1Z3CnpoSTd6YUt3UG1NaEt5UkM+QThUcCtTczRXd0JfcEl1PSZ1
NCp8MmZAOUVjdWFWTnJPNSQtUD0qaTYjSSFlc1FjJAp6djdOTiljcX5hRDlRP2lJX3gpWmFSXiFE
bEQ1Uig5TUkxZ0Z4K0JrVGc4UTxOdD9+RW9faF4mKCpRWHk9SktgdjcKej15YXcmZXRvcFFhQnRz
QS02KDkqRFB8az94dVQjO1htXn5eckU7NVpzdU13bTU8d2RAZjI7N04lRzNgUV5kUkVRCnomfiZk
LUhyV0F3SVYlanV2ant5YE5vbilgd2xecGVDPClSb0c/VUlmJTd1RSo2fXNXcyo/O2FAWjE5fXtO
SyQjYwp6MGU4PyUpRiErS29Nb2NTPVNWcT9IZnEwYDVxS2FIbFBgOUprYmRqPlphanpUJUs7Jmxp
TjdUIXM/ei08aj1SWFEKejQjMVNtIS12ejFWSWdFY3hUeCs3VEsjVD1jWHpJZzg7Rj98OUx6NmpP
MHYhNzRGTmtQUSMlQ196TjtqcmZpMFZMCnpkTG5OPWFINmFPP241KnFeOThwbnMtRkQhQXtTPCNX
Kll2NXtpeH5rI2pwNz05VnlCNXFjRDc8PDc4dD11c1FSZAp6YSVhQGYxX2t4SVhSS0RvQG9aNHlD
V2FZcXlfVUEpKnRJbTBYfiFWfT5vNmY+KlBvOS1zTyViayprVmxKRiF1cDMKeitMQT9AQnQ4TUA0
K2JQZ0hJIzlkKHhDNiZ6fkY1SFZQb0BhYGN6PFExZmB1R3VjSiZSTzJ5RUtQYnZDZXkjUHIrCnp5
M0h6IUxeMk88OyNTOS1he1pEVDlWY3ZGWT96ZHA+fEh+cmx9ZjA+PmNfckdae1NeRytxUD5lR2J3
Qks9ak03ZAp6ckx1e248bDc/QER1bUVFdW87YGpRaXllPlhIdjlBYEtKakxHX0s/dkRLTj49bTA4
cU58STRxJlFNfiNMP20ka20Kel8renMzaylka0t4T35FQFM/QU5zTFNrMD8zN0owTHJJOCZOWXlF
K3pMVUZsdGtZQCFhO2pEangwWVR3JUMxfVZqCnpzZW91ZiRZITFUb0FgO3ZAalNPTTZPcXNwWlhy
SEo7QVd+USYjSG5VZjgxVUVkc2JkTktDMSVYYSRRUyZwSVMhZAp6bzVQfDRmTjctTmJUfU8+QUBZ
RlIrUS1WNVN3JlNzc0xVRVchOHk5WEZWX0UlPEQxbk9QNTVwayF6M3BiYCYtVl8KemxtYVhPIztN
b0JGQkdOX0s5ZShRdy14SHNXRH47VEFuNVdgOGEten55dVZDVzJ2amA7Jlc7LT03MndYeks3OzRe
CnpWVm5XOVJCdFokUzJKPj5Qa283IyNkXzZyNDlsQHUzMjJuSV9fPTxNWUY8ZlVCTl5RY2tiVEEm
PHNOMTIhaHlSQgp6ajY5c0BDSXFUbkB0WG13V0Y9ZjZQMDY3JllZTFJDaG4kc1I/XzZNKEgydWxL
JVlvcENIZjFzUzVTdVpAKUhQZEEKenkkPD8oKzNRRktUQz4+fUg9QElyWGV9Q3NaQiVKXztgQEpw
e1VKNUxzWS1EeFVPZHo/KkJGaD1fJTRDOWhDc2t1CnpxWCZHUnJ1S0gpPWVHVHVvSC1sS1NlamQr
RD55K1VDLWRQMmV1PVRkSHNBPEM7Q1BxNTJCWEV2PypZdz4pOWZQfgp6azZYSkQ8IStvcFRAQ004
dFE8RztDXnNrY2BQdTAlcz0lTk1FPlMrLT8kbGc4MSl8Vy1TKFVuY3s0Yjw5aCZfclAKejNvNXlu
TEE8TDhJTithRlooKVZQc2pNYkZjU0R1TUx+flFva3JZWl5pRj07aXwxSD0hTHJJSmBtVHVXQmhO
TkoqCnpWOCN9a2h4NjhlJjFNSGMzRChTYnMxbmJ0O05OTXdoe2JzeSVvbTRUOVZ3dU1Pb2MmSUJk
SlI8VC1md3hyeE9zVAp6XnpNTzYzNntRMzM2QEwpY1VEVXJtR15pRikmKkg4azMlS28pKFVwdihI
QzNge3soVURgUiFXPmY+TCteNEFTelgKej52aGo2KHY+eXIqLVIrTiFRbnNXVTx7UklVYl96WCY3
dnZaR1A0STglP31KdCtga0ZJRElVTWtuQUJicHZGcTFvCnpTIWs9WEshfUw5dklTQTR4KnV7amhU
VWMwY0t6b31LYmQ3MG9eUGo9VkxBJUlWZEZNfFBFYm00a0x4cTRzVVc9QQp6UDt9PyU/N2ZTJiFC
b0RiLT9EYFNHc1lTbS0rYXFvMUVYUmo/UyQ2PktlKzhCPkBYXkxzdWI+WDFmPFVrd2YzUyoKekVN
MXt2SilGXiFKfD1BRk5hY3FRO0R+JSQ8UEQyQFRtdiZEak5ONEl3ZUIlWVhBe3IlRDlCVTVESCRH
dDB3NT9CCnpxfi09a1l9V3YzdERXPmZUIW9tRm1SMTR7Py1hVHhlaVA1SnRBRT0qeU9iIURPZkxr
KHcmVSZ0UWh8K2NMYS1aYQp6Tz93KSZBKXlaT2xPMSUtRmEmdT8jclIpKi0+d3F7WWRTSjVATURW
b05NN0V1M3dhV0ViVlZBYzQ5VnsrSX1QdjsKeiRaOHJ3PXxoRWJhNHdVPHpmUFchaTdsSj0pOV9+
OWNMJD9pWTBiTTNzY29LKT9ycEgrUX5ufFgybDRkTGMhdlBaCno1KGQyaGUydTEqb2ZZOTB2en4t
X1JTQXFNMkw3WEErcklnMFBWWTBuQVdDRWRkaTJ8OTF8Z0AjaFc+Kk1UdHVeXgp6Vm48N00hfWVm
PUM0V0RjLU5oKzI3ZyU0cyVTXkdBQzREOXdgYE8jYGkqJkx1R3ZnYT9iYkNLJlAqSEF9dn5NcDsK
ekN3a0M+MXs3UU1qQER9fCh6SVBNITI1KUJBJXJjPj5RJFdFVXE1P2AydioqfDhAKWN1NV4/N0dM
ZHd0dkZ7NkVBCnowQmRzVW1BZ0tpU05eOCNlJT58eFJIJmhNdmhSYT4rMEVNbCE8IU05Q0U/NzQj
LXNFb1E5TW1TOXNIQipzLVp9PAp6fE1MS2hibi1YIT52fj1fcXVGWk12djtkSmRWTXIpTSlzXyhx
LWNKMDE8enBLUiVpZGxkNmJzdXRzWTJyUWh+NWcKeipXSDNsMkdYQW9taXcxVihudm5ic3VWRSYp
RT9pN0NvYzM9I3M/Mnd3XkxvNnJ+MlU5VCNvUjJjMz82Qm5IVD5kCno9N0FVV1F9JE5gdDExJik+
bnZMI3kheztUdl5LRCFUPWh1Tj4yMlJHKGs8fVM5NnlfNHNYNzQrbjlBbmU8UUhJdAp6YCM2T0xZ
KnZ7aXdJSm41MV41YiU8bThlcEpBRUs1UFFPNCZwMU5HRSZGU31qY0dSZHAjU1k+XmNwOHpeVn5Q
cT4KenZhaShBZDMtQj48LUYkcSFZX3h0PVYpZHJ4fV9iR28jQV4+VmhESmBuKzs1VmZZMTgzOUBB
ank0SDsye291YVp6CnorRTFVTUJwfGlDV08oeCV3OUlfdS03NGstUHM4VEAjOUx8bS02OXhKUUBF
fH0xd2FqJmFWKkQ9N0B8Y0hCUFhofQp6NUxLVzchJWYjQzB3TmJ0cUgyOXBjMldEUVlSKz41Zmhz
U347TDJwJmRkWmBiMThraDA+MkBHJiN5cF4yZEV5cHwKekpTakQja3hvY1FmOX5tSE5KaCsoMn4o
cSRzbjI5a0psQSoyYXJzI2lmYUdhdFE0N0RAYTxzIU1PcmM0aGhWMStkCnojZ2Bza2ZaeDQ1bFdm
TD1VfEtPQjtDcnZLMSVTQSsjJlEleXtBTkhTeUc7fnJGQWpVRHFSMzs0cnxKTCojPG1+ZAp6SGk4
a1RKcCMycWw0P3E9Ml9ZVWc2c3o5KVZDTWRFVDIreVZJeDRpbyRhOCZFUD1gOWdRMytTdTZtUXhE
XkZuYEoKenZwa1QkWkRYeXRIfWhWfEt7ck44YH1RVWg7IT5YanRtWmVQe3VMdllWQXAtOT9rOEh2
WWFxYHtxcT5CejllP3xYCnpSLVozMk1uNUQqJEplIzkwO1p4PTAoQzFePGloeVNvMWY0M0g5Q0h0
YHFpeTRvc3g0PmtebnVVSy1ZUSl2fDwhZgp6SjljYlBqIStVYCF0d2RsRlVXMj98QVFxbWcqfipC
ZzhtejcjbC1tIW04OV42PSEhdUk/N15oTEJ5SF52Skg+LUMKekUrV1dWMl9xQDlOSFgrQE5DfHZe
KTBQeFcwTkFjVzNIRCl9WXU2cHZXJFRlMF5jYyR5aytJeClpZChPVmRuQXBVCnpSQE93OFcqellg
IXxYSmVeeHpAbjE3fURnP2JzYjdjU21TNmRGYHFhRitsTHFMSyQwb1JWPENDYzhLJTJre3h4Ugp6
TTNCKDx2VT10NjAxYFBBJTMpLVJqITxpLV53PShhMkIqZUdgPUFeS1B7JDZwKjBZPExVZDckUVA1
c0U+NmpBNkMKem94RHZUVzcoKTZwUT1hOU9RUVpART9DOWolfVdBJV9KIWIzYzk/bFEhNGMqWERj
Sjl4dTd5NzFyZDgwNGomaUt5CnptKV8zUGReUldjKz5CLUNwZnt9akQtfHVoaSVKIzc7NkhSOShW
eVg2VC1qTDt4YFJFVTd5Ql4pdXBYST1XPk89cAp6ZEtaYGNFMlhXSEteVnNmMGRsbjZ2LW85Pml+
XnIpWmE1U2ZtSDN7aXl3OTk1MjYtTCo+S1Y2antrN2ExTzYlfTYKem8tcEw8YTdDRi0+YXcjV1V9
PkMpIVheVz9pelZJSEJlO21IS2RpY0RuKUs/c1diM2VeNyliQEM+WEcmYWFNPHZMCnpfJHY8OSRN
Zl9ZOT5EPHMjYWlPdWQybml1QyVxOWoqK0Y4R1pzfG1HXnwmd0Bpdlk/YzxiUV4ybmhoaUlYNVhC
egp6Nyk8Rjdra1dvOHVDKD9uKGNjM25eUWpuJUdYMVE3K2hLR29YPkdqd1RjPF9GQndFQ3heaDxi
SVA3IX4rbkk3YkkKeiNqfkJ2JihrPmtTX05BV2ZkTlJNPkdHTkBiRjVCQWt4emtyQW4xWkU8S001
Q0smVkZ8d200dmM2K0BCZGRvWnRvCnppWGg/LTl8N1R3dyV5T0A4QjB0KnZNdyR+eE9qSzZMXmM9
Y3szdTBNYWh5WDxXZFRvTyZlSHtlKXgtdVlMWHFKMQp6KEZ+PmgoUjVLYWlXaD9YXzkxR20oUDlU
dDRPajchZ3pzYl40JkBYb0E2bkg7WF5aT0VGR1M4K2IjRz5xRHc/SV4KenckODt8QD5pa2Y8dzBA
YHteeHNTTFFqc3RHKGNPZiExKE1kVn1lMEtkU2A1akU8e3h2IUcrbz9XLUVTNjQxS15lCnpJeiNh
XzA/c3hNUzBRVm08dEt1ajcmczJiQWhqUSRHSyZRVkNIIVombWAyOUJMQXVTVDRFJGYoa0hORmZ7
UVgkTAp6eFc5I2xXKm1jfWZHTktpNVApZDVhYDAyal58RTQkcEdnNjxIZ00yYyQlJDR+KXphJWZO
RGZBSFRAfWQ7R1kleCoKenEhenclblh7PSo/SUs4RygxVmhCI08lXzBHWDxOUyY1LXl+Y1ZTM2NE
T2R0IUlUYD0qP3tBO2V1fShCLUtGQ1MyCnpNZCtZYiZTRkBOeUplbT5rZV9Hcj5iZyt4cyY9PmI3
QHdCdWF3KjVHVkV0P3Q3PG9eWTk1Pkx9VTJnR1Q9ZURxVQp6dnpMc2IwJkFrS3owTHAoeCZpUlc0
UE9sX2RxWlR9aDgrX0IhOV4ydkBzZil5M3RUUkxYRjtoflFYe3lwTjAwcFYKelh3JWpBNj5zXyQ1
bnUpYCgrZ358QXl3UUZtNHNAV2hqbGxBaj9+cUJmcUtGPVM3SDNnJThWc0h4en4xJGBxfik+Cno/
aG9+RCFgMX1rPzZnN2BTeUFOdWxueWRAWk5ANVheSzxMUjBLQGpIbzdwRUVUbFk7UUp7JmY0MElY
STApez03awp6MyEtPHRLO2RXKmNRSE5YNlkjbj9YKit5QFRgPC1YRW5CLSU5ZyR4YFgqeHsrb1Jx
RitweW1teTRkWiQ2Y3ZXP3YKemZRan56QmFtMUxsVWEhenNNNlNkN1pwNDdZJHJMSmg+cUxTKyRB
dlUjQkQkaT5xM3BNKHB+LUJiZmZKWD9yNTJsCnpUNks1MiMtcz5DS3pkVT16KSZsPXB0aCF0a251
cmtte0JIZzkwcDw1dXw1PD1AO2QqQSFLYDhSV2lIVCF2SUp2LQp6UFVRWEoxOEFwenZuKXpLYENA
bEdOeyNrZlEqeVJJY0tSRFArWShZaXNXO3NETXxjJEotfW9DRlBoPGdpQnQwZzQKekZ4fTBlZDlZ
QktJZWsqSShDMjREeDhIfWpSUXtrPSFmcnxqUFozIWQ7aGpONW53MkMrV2RXMmx2dFJ7ZjtHXjd6
CnomYXo1NEt+d2VQWFoqO3I3JE5iNmlNRXQlPjNAZjt5TEtlPyFRYWh1WU5QRGRfY3N6fXI0Y3ox
Z1dqOFY/M25xPAp6aUttQW1LeDB3YDIyNE1rIyNUUCQ0cmp6N2o3PDZ2cnJqeyt2Qno0UTJUM31W
U3J9QGV2cHI7RkJSZmZUY2dUcGUKejBMX3JqPW9KZ1ZoYD87PjNWM1JwQll1NXwmcj00bT8/Z19p
MHl1aTZWeXdRZFp5czZ1MXBoc3tYYiZBUSF2bU1LCnpMKCVCYFl5YjNjT0MzbC0jamRwOHtxdk51
LUVaQmtEam1lUypMP25mSlo4PXRTKkFCSj9FU2Y0T1MkaHw9TkZ4Kwp6SCFlY3hEJWFITDhRZS1E
VzQ5X1JXWkdPUntHLTNlMDVSKFh7IURpOEl7WkZLJW9ORD09VDR8MkwqfEtHRXR+TU8Kek9jVikj
KTZNRXB4NiRiclpwcUVfTkklQyZYXiVCd28kJGcpU1cwZT0ybTFBTVpWMnN4ak0wMiE4YmN3cXJ6
PX1XCno/SlJDRzc+X05TYzJ0NkBpK3AqNjRWWTZYZ0VaMlVoWm8rM0xrITw3TnA+fj1vI0FwQkEm
e0FLVlR6SE5lTEp8PAp6LTtMZigjd2szRG85MnplPUQ5V04rI3p1TDtUSG1OcCVaTTsofjZWJmx3
bWIoV2dpM1hkdmgqOTErb0J9TTVnNzwKek45X1FvP2t3bj9oeSYldVh0Xj1YR30pVzNMX1E3JiM0
Pn5YRl5JbFIyPFE2bXBIazhPMXdWbmZkc09oJXd0ODJ9CnpFcVlLezlxVDBpPDcmK1RfQWpjVUNo
KmR5OVN6MiElXnlgZWl5OU9iS3FJPXNqRWEqPF5IMmFBRi0tSjgjTUMkRwp6JmdyJnZWM15sKjY8
aypIdHs5JHFLezU7K0gyUHBOP1RKbnl7dVNkMz5DLVk7S1UhTVRHc1F0VEMyPHl9RGIraCgKejdx
Ti1MeWRJVSE4Nlo2YVRlaSYjeTY/NXJIamI4IyFBQ3F9MyMze1N3OERwKUFCZkE8aCo2VW5VRDVB
Iz9pa3R3CnpUb1NuQHglU19qeGx0PTB0XyEjTUVwUX45SzMoYXUjeFBRREYzNTtIOEMpY0txO1Y9
Q19saj5qaGtsT3ZRQGhXYQp6WVp7MTI9KmQ9MHcxRERJJWp2KyQkYypjNShIS0o3N1BrfDcmN0tx
U3d7Ul9BWSNsKHRUTVRRdTR1T1k/TG4jYTsKemUwRDd1Nz9zUDVzdipmNW81bFpuX218TEJ0MjQx
Y0xkUXtPaXQlMmJZfVhlIWlRKlcreWxTIzhyJmhGPEM7SHo3CnpIKzEodS1tVFd9bkxpZl82SWFm
YmM2Vjs4cE1SMWJpUkA+XmFQIy13R2Y0UypvI1lnS01ZU0tEQUpuUVJ0b296cgp6aiFhJE5BeTh2
QSh1cEBYe2ZJI0Akfk9QMzg+diZAd1Z0JChyWUtPbj19d2NJN0lCaiMqdjViNz1QaHxYO302SE4K
ejQxV08tPW9NaU10NSFTZmotQ15hY0FGNFljKytXKE1UbnBFdlR3YGptY0pIS3c8KDtOek9zOWZZ
Sio7YlklRGUwCnpiP1RlcWVDbjZMbz1Dakokfil9fllqPWhucT1takhlREdvYVctcjt7aD98UHdp
ciQ1bm40b0tHVCNRQUNaZV8lJgp6Q3xnd2ZxaGMtTzF4TEVQKSlYJHlaWlpRVTR4aSk+MkY3JT9G
PSE+c1lzeUpfK3RtaEAtVzJMbkJWJHImTF8oUzsKejxqJkJaeyQzSCpRVndmKmk4SHdIUEI5KkQr
YitPM3A5JHM2KX4hSiYrLSRzN2xUUTk7S1ghWV5tJC0xWmR5IzFxCnpUMD9KXk0yJE5YbVROayts
VDVXLS1AfjV9NDImP0hwfEVHZyFkdypRdStOPjtqcUNicCQmSH1RZUApTEJMeU9YdAp6TXhNQkxj
QjhoTDxqNjI3T0JibFVvSEZ0OUNLUShsNGZOdVlOdm59SURpRFoydUQrY3tJXyVhezwqMitgTGFK
dHUKengtPEw8SHczb152aD5wcVJMd0dgODJ7cWRROUpIRD59UGxYe1MlWHw4RHNkUGlROX4oX3J2
OztIPlZIV0I5PX1sCnpDZj1vPF4tbkNadUdxLUJQKTVoK3d9fTRTKXpuKlRBfV9BZEkpcU5RUnxL
UV5uanxlRmdgZj8yUTNUJWdwPDNDagp6X19PXjdLUSR9WXBPJVkqeyQwKDxQT2J5aDQ7MWtLI2tO
P2J5fExZWnRfJjIqd1YwV2FCNUpeNEhDbzh2TGRAKXMKejc0Mj9RYSZQZ2pFP1loVlMzT3M4NTx5
c0EpRj0oUyhiNDZVPnkoXml7T0o1K3ZKSC1KZG4zT082OWJWVjFpJkdiCnpBTSNnMVVwLXQlTEQj
KTlqQ0FtYV4lMkFVK2teQDl6ZXdhaGhSSGw4VDk7aDRTV1p3b3F0bHNrZGckP0BgYiF1Mgp6VDBY
Y010QCl6PWx5IzZge0FMe3hAWUNOP3g4d2l9an0jYj1sej4qVFYpWnpec2lTZkUtUCM3blJASGNC
TEp9QU8Kekk/YjFmKnsyQ3s/UWdoPXdmM3dePFp1SzxkayU+MHMoe3RKQCVgdmFHYGx+aXF+VVJZ
WV9EPGBWKEVxRHN8b0xaCnpoKzZTIT05aVI4UGRVOCtIOXNQNlYqZiFscnIhO0Y8RzU1WG9ZITx1
c28tQXBjLVZ3RztqOXU9QlhYaWQzOyYlfQp6JmJuMjU0fXtzRmE9KDlsYFl1a3NOSH1uYW5+VWU7
YCt+ZDljUmAhLVVDNz58aFQ3bHo1ck1xKTR0UGFAMnhWISEKekpuZCFPbVdsWX4+KVkpQkFGNDFW
TmdNRXw8YHZ2Z25iZFdJaio8eD0yI1p9am5TLUomaDQxP31XIUkhIyFxPEFVCnpQPGJvdWwoYXFi
QW55czBjJkpnRHtvVkZrYyZJNj9AbFU+WighYFRrU2Zse0J1YmJOQT14NXVmSHMxJkxFXkJ3cwp6
RzxIMVBxT2ZRY2BvTigwVihKZT5aYUR3cGEpWjFuTU1BR1dxYUJsUiQ9MiRoIXh4V01ITGE5MTRM
ZyYkbnJNbCUKenVFO00tWUxVM3tVb3ltOGB2dDtzUlBoM3JxdXgyTTVNOSNyTGU9blVPTklOUGsl
eSpMe1oqd0AlJGxQSUdtOSZSCnp7VjhPcGR8TWpjTkQwMDYkWkIjQk8hYms4VEJ3RnNyNDJrWUxF
c2spMyFJNmAkcGZyfD5peSlpKEhUYDs5MGNuewp6QmJNdiY5LUVfPmErNm51O2FeSktefjRqeTw4
PlVhdHcmYmdNaDk/eylqTXhkSXlXZyNMejt2TllxNEchPFNkWUIKekNnfXRnVFVJLWE8IzIqQGUo
e0Q9bTh4VC16ZkNWV0l8NDsoTzhUfEB6djxRUmBUY0lAV0BkZldNIWExMFVvM1FOCnpNRT0wYDtv
PW54R3h4M1NpTER3ZTJneDhPNUFxKXZhJEEhcmJ8TDhAMnJmbyQ+JlRmOCNILTReNHk8RTFtU0o4
aQp6TTUhMGUhc0V9TE9MdkVFSkpWdjIoZ2UpdSE8IyQzeiltPTJQS3BmfXprYj9xN2QxTChOSio9
fUx7OTJlb3ZRR3QKem5yN1R9TUo5K3FuYWF2SytvZn1nNjY5Tm1LeEFndTdhd08pUmJxWVRzP1lZ
RTMqPVZEaSN9VDNVN35tYSNsM1FHCno7PjVTTiM5RW5iPGltWUMwdEYzfiVsUHxAbHZZNjNfIUNw
Skp4SjghYkpjZ0tQMzBSfXUkd0A7SEU8VD9xcSpXdwp6JmlaaCopOG4qaXhTRWBUP0A7XnFYTkND
ME07X2E3NktyWjZpeUN+N1psTmIlQlIjIXRyRjJaI3FTOXQ3UkF8c04KejRfI2VPRT5OXlIrc1Nv
aTk3JXBkV0hLSVZic313JVRYflJ1WWp0KSpDTUNLPl9IKDs0ND9kPlNKe1Y7b2B7UTI0CnojYjc3
VmBVWUVNQVBJSkg9SDgmKl8hYkJjZjl3LV5AXm1HZnsxKnd2V3xzTlF0SVdraDZILSZxZ3pSYTxy
Q2hAfQp6P0NNdlE+Myk1cU40Xmo5SkVDeCg4c041IVpUPSlAaHZjMilqWi00Um85Uml5YHglLWl2
djZGdFUhe0olJGopcG8KenNuMnwxSDV6RjdQUj19YG1DRHI7Z3dvR0pPezJ0P0VNQn44QT17KDBn
c0M+fT1eOE5VeEB4KlUtWjhLeXN6cSQzCnpZbE9mNnVaK2hTcXFKZj9pWE5TNGA1LUo5c3UheHJZ
UVdVMEB9dGh9Vl47Y3cjaDFvSiUjWVluOFUoNUdeMSlKZwp6JTtSO01Ackl1fE0yJEhUR3swSlhz
PHlGKlgwYjRNaXtaMkJjZW1VbUN8MGlsVTkpdztxKEdmbyR9eD80Klg4c1MKenIyJmI/eXgtPFRV
dXUlRj0qb0ZIRjcqQ2RmQmR3Rl5UcEApemUmcUU4MWliJlRDcDtYMX07Zl5MPXNnayZ7VWVBCnpp
WDVPKTl6dkdBRVFrdml7ZkZ9QlQqaX1CTl4mfkMrSnNqUF5OTCMyTlM/O090ZkVzMys4OWp5cEk9
fT8qdFpGYgp6S0NUKXJzVCF7aUtYO309WmxRN2c0RDV1eD9xSWR2ZEM+OT1kSzE+Z3VJZiRmNG5n
KVBeaS1sRkcqYE11UT14fWsKejBXdDlERl5hO0I7cTVlTVNsVXV0PHJaKiVJUUEjYlFJblIzaDxA
Z3tfTllgZUg3YURySlYrUSZzS2lKN3UyWjxaCnoxYE9MP0xgRTJ0aCNPcWNObXd8VCQlJSsqbS1X
VzNXbzMwU1N7JUd1OypVaV4hYEI5RE1HaH1uKXZFKDxfKT11Kgp6bHN8ak5acGAxaURFSmJKNmZn
QHAlX0xAcyZPJlh1VTlxZFpNaFdIO2BJa3FGMyZjU0ZmMWBJfEx2QihsdXhgcWwKendPaypGZ15L
O0R1TFBGa1Z8R3loUWFEa1pqNXc1NW9LVSYhd0BZSnZhbTlCVXlaPTNnY0VgUTQhQE4/IS1MXnYj
Cno7MktqfipTe1N1SDs3RHB8SXZacXgwT3d5bHo5QGgjKmJod2s0JHRpYG8wM25wPjRfYD13fnFI
Q3A4QSYydEJmUgp6eWZUWn49bm08S1UoPjxWQ0ZuSlJ7TXVwN2I/czMkMT1KKkI3OCF5NmFzIzE+
QXEwfFhOJjFnOzZ3RDdkRjRrWnUKemxBQWskMm5ZQ24he3ktR3NQTEpPcCp2e2QzRHhyQlcpKkBu
cko7LSMyflM9bEwwWFgmR2cpYjhXfWEwSnlOWSFnCnpnMnh1YndLeVVDMS02IWQqXjYxWkphSD1B
V3NlcmcwMHdyXyQ+RHN9N3ppSnlAQDFDbWlBUkomazdsZkJNX01Bewp6MT8/eGU/TFV2YTh3O099
bCExd2Nie2VTOG5KJkolY1pBQyVCeDc4PHp4Xik8dHd7ND9JdDNHYXhpVWl6UmMlLUsKeiZQLWh8
X1B5WG4xZ0klNXFtXzBGZVkxeHVxYiV+d3FHI0h4WH59Ml43al5gdGd7eiVJMT8/X0JEPDtPTFV7
UGhSCnp1aGYofnlAOHFSYGh3a0NeODFmRTNFQDR8e3wyLT82Q2s1VUpqdjc1Iz0/REFHb1U2fnU5
TmImUm53IUw1dUJ9KQp6YyQqOE1SdXZQSj03bih7UGhSRWtyMUY8JEV4RGUxZmwhOy1UcHhmIyp1
WWB0VE1VNG5qazJYdiQoKkgrM3tsd0gKeiUhKj52IT1hMXUhKiVoJXBJNCpkRyhoNCgkaG9VZihD
c183TEdLQXNySzx9djsmM1R8cTQlNU5VZD1LI21kP3g0CnpoY0RPKEVuVTRBWXFASGV6Y3hAWF4w
WilWSnZ5JWBDT29FX0ZWVGRiaDtxc1plSnYpakgkRT0qTGReakNIXmJyNQp6N0J5KHtrPWQ5JVlM
P2NGK0w1cEhRUUA1OHZvfmshR04zVEdUemJAJnFpPTlXPCsrWFNWLU44UyZrTisrQUhnST4KelVT
PV9KUlUkWDg2OTxfSnNBODZpa051Mi1OP3VJSClsbj9lPTl1X3EtTjFuZHVYN3JZTF40MEdWdW8y
NmIwbiooCno8aUt1PEdxezMjSHp9VyRPTT5Faj98eGhEMUNyM2hndHZSM0lYUSMxJFJSSGtnN3Qz
Xmgwc2tHOFhOQGZgNj5wJgp6Y1N0TUlOWkpPRV99YHptRSZURyY5PDVSe1FiRyFuKFZVMFdJbn5M
RmRLNnpqMmMpZ0pJPz13ej53YUJ6emYkM2UKeklhRGNVTEBxIWYpUEAjPk9pWllpUSt+Xmp2OEBZ
XnBDKilSIV44PFNjOCNJSGFAdykhPndzZHR5elhQZ2gkcXhzCnpeZHhYOW0+fVVONE1yQksyfT13
Vy1GUElwWjRJV2U2KFUqRW5aR35VbnAtaTBxd3lyN3Q2cT9sJjFMaUozKXEhLQp6NjA9PkM1MDAm
SyUyUiNsbllxa3BFTD1tQzZFKiNRP1FldVZeTUdNdiVFSFdqRSlsMlo4bVE7I2lSNFNhXkltXy0K
ekRJOHAhNjRaezJSdnQ1KGwzejdtOSR6YjMhPmBYRHZKenhwOEFMR2BgUDRgRHNaVWdsVWdtY353
dEsjc0ZqMVRRCnp3d2UtMlJmdCs1NVNFd1BwWFFld0FjayZhN2cqRDU2O19CMD1OanxUSDVwM0Ju
UUpuZVc7JT9hZGRqbjZANWA8Ygp6a3xpfDskMUFiNEIkSmJlPilyOSh2QDh+cDRTPX40cGtNYkBa
ayZqUlF+Mn1FNz05dEZeOFVQZXRNKnFNdWZaPmsKel40OH1UZyEpQXpfTnU4OWU+akl7RVYqeXRp
VHlrakdjZ2tzckFUWjRWKmkjdSU8PUVfdzVlZmRUQiFeI1YmJF43CnpWT21hOyh6V1Q5aHUjKXxq
QGptZnBEQ0VeYlZCVzFIM097QClwcXRqYEZ3PmwyO3U3S2p3RTJRPVBiS0lPc3NfYwp6Q3ZBeTFK
S1poUFUxMyZAQTtaWiUhezEzN15eMy14RSpsa0QlQVFSQXMyKjBNQz5nWGY+Tyg1T0woNF9UNTxF
fnUKekg+dzFxdjIlYiZnRjUoRGZwdVgrU0NCLUY5MU4ydUpQaWplWmlDVjAmeTFOQXpOcyomQiR5
WG9USHpDfDMrZD1QCnohVEJ1N2ZaJVdNS1R9UDBJd0V+dFFgOXFaZmcoPjJkYTI7fD42IUdDZylp
YzVrKipSKjlFc05YOGU/OTdFVUJQcgp6d1N3d28qZjZzZ0A5clklOV58XmNgbC0tVDtQVFl6MnNw
WUYpeXstJSRAfGdDJCM2I3lRR1F1N21VOWJWUWcoT2AKemJyTU5SNT9gKjwqJGkqSFhibCF3bT1r
NzYxPTJGbyVBamZtZmNAaWdeKlIqN2lFcWc0VjN9bCFhX09gRyE2TiZSCno1PyNPRGM1ODRqMDRR
T2JKOGk2MC1uXmdUejtEZitLRW9AYTFUQ3pMdkV0c2tiVEUweTgwUmNJdDJ5Tjxpd2Y2TAp6anRJ
d0I2TTNvXlg+d2ZoVkBDfmhyYUhlR3FhKH1IV3RHXjZWMn16SjYocDdNKXtFVXN5QFUkfmZIQ3wy
dGpeOGUKentOeUxXPylyVWxIT0FDJFM5eEB2ey04bmhnRnkwdkVpbGJyVGkyQ3JjMj47VW1fQVZ8
aXtlY3pyektSLWdGZXc1Cnoodz43ZkxqWG9gX3JYSmJmaX10RGc2ayY1RSsmbEZiLWxNcSZRNzI7
dWNyIUdnNHZeY182TDw2aHdUMz0mcGJyNgp6eWFxaFlzK3FWU3FfQTtoRFFNfEBFNTFeS21ialBw
UF5TP0x2QXYpRDcrVURrWDhNdzgzJkJkMTE7bUktVnlGRUwKensqSEV6Ky11ZzBVSH5vVTM8d1gw
SH00S2NLKVhQT3tjTUA9QnRiQDU9VWxuN2A9JEs3PDBuVkJgP2RsbyZJV1RjCnppfDR6dmwkeWp7
SiV4VlRgfEJHZDV9MSVKTnF0dDUpeE4oQCp5eU5WbX49ZkYxU040V0dGLUBPQVd9aVYoRmhjOwp6
Um5gdj0xZHlDb0d5TWlFNk1iJktFbExkcDltS0JsSFRiUExxaElAYzwpVzc2UHFhUiZySVgrc09q
MU5WUnE2eDcKeiNxTGlDdkEzS2lUK314LSZCXnZ9PmNXWlVFSmNRZytjfEooYkZ7dElVZUpkMW9h
VGxRUGI3eVF4PSN3ZHpobndICnpjTiltUCtKbTlSJFRpQUxiJClZWTZrP1p+Wnd0a3JAODIqTmsk
Nz8hbCRxTjBaK1NZRz1qVlNrJXBVK21iTShVLQp6YmViOShUJGhoKns4Z0UoZ14mWCV3QmFSajRY
aFJfZ2w7Qm1hKChhUnt3fX5uJVpELTAodnBYJlUmbz17QTh3XnUKeldqWDdoZWpMZVZaai10QkVX
ZnwwJVBUN2A2SGg5NkxwKUpgQ1E5IWNgUEQ/dT5OJUstPmB4aFBCdkx7TVlHSllDCnpQbWRmWCtI
YU9AYT5YZThAaSh1PWE5UGJfQj85Klg7XislT1kjcn1sTTMrQXxQeEFPMFZraGwmVH5xN3BMM1FH
Jgp6bXIodGs3b01BNUA2b3IoeXxHYSlXc2EhQXZUciFva2dKZkIlPnx4RTF6enFKazVATk49PGdL
Kjslby03YCQ/Un0KeiRgVzxuYzd3dEtVc2AhQEt2T0ZaU1ZEIT5Ocyo+a2t1MmhDWWlxe3d3NVhU
UjtRITxwPCtra0l0dypacU9fXj9oCnpHN3x5Q0ZeNkNscndOa09DY0UjNWJ1UT5LS1RLU3dRb0NZ
KSpAeTdiQ3pjJTVXbiMlbCs8OExjQVp6bU5kY3FWRQp6Q204IStjcWchUUEoUkNvI1dAbEB0RG44
X3pmVjd5bC0pfCZweEx9NDw0ZDMrbGRCZW1HJU41c2BrV1JpbXVeaXYKemUtc1UpUz5BO2dEKjky
P3luVCV8bU1LdDhVRkJOdzN0SUd5OFpKMjA/aEI+SCptS3x8U3hZQTcxPyFJUnFZfUwtCno2MUB2
WSpYdipQXzRqVkxUJjg0WTlmdmMjVkRkQGNvdmI9MUMjVV9fbn45Znk5TiU3K1klR0M/YEpmT1FF
YFZJRQp6STtINlFZcn1pMS1PaiRsd3FUPCYoQHFGWG9RPCRYY3NORkljWkltYFQtLSgxZCo/fSM3
RVlsfUVqaE9XeDNqdWgKemljWi0qQT9XRz08VDYlVUxARV4+ZXEkNWlEPl5HI3p7V00yIW5TaHpv
eH1mcEVsbGZAaGdjel8qJlc8QEpNKmNqCnpZZD1HYERffHNIQW1BdilkXyNWOUMqMj9gSlomSX5A
V0Q3Pit5VjRaUiRqRnsyeV8yVGYmVGYrY3VCST5gSSQ1NQp6OzNVeE4xUWNqOW5JbzF6QDVjPTQ4
aytxWj9qSE1lYjE9bHd3UWNTRXgtWmI+YCQ+MzsrX2hkVDhGbyR6eVY7Py0KejwyPjdZJjM4ZmY8
Pmg3Q0twP2lAIUFDU0tPel99V05sOTF+dmAyPm0rOT5rP3A7fTlqcHdxbjlqe0Y+LTJKVSROCnpR
WFIwLUB2IXpIQGI+bSo1c2wqPzEwSGYwNm0rT09LMDRBUXRteFE7bFlrdD5MRmkrNTJKd04pKy1J
TX5nanBvTgp6bjsld25KfDkxPDExQUdPdmtNIzVfNDheJF9ZUUY2bFItKnlNLX1kXkJfI147Um1M
d0hmeks1MGtmUHRAZUVkJTsKej19RTtqcVBrJHotdExiMzQyTy1VJSNHSzVYWVkma0xgey0lalpV
QGg5VSo5UWZYKTc3dTQmaDFGeHZWe0E/VXFGCnpxSlIyZDZoJCF1RkpicTlXKERYbjFvWk5wdFpV
LWdtcTdRKWl6VWdGOGsoRjBod0ledEw3KHI5VG45JEt5PjRNUwp6K2w3UHZfQ2poQDRwdnc3OW1Y
WnpXKjAhMCNSNns9YjNeMjkrZ0ZzeEc0MiFGRVo7P1FJJmNvTXBuQGc/cDRPMDcKemNSX3dFX31e
cjF2PTExRlJFezFpKDh5SDdjJU1gQHZBLS0xaUM9azdpciQ8JEw9RTUkK0pjNnxoWX5qezhkXkkj
Cnp2WGZjai1uU1VVdWlfc315d15OQUkxeEA+ayt5QndyaWx+cUtKfUpZYFIpQSY+ZXJvc2ZCO3tI
M0h3VUU/Tm40VAp6d3M3ZXpjUXFDI0tSLVd2aHhzZj5pPXAkfDI7b2U/K3ZuTnwmfU5DdD9Helgt
ODJyJXIoMkBGallTWjt0P3FtcEAKeldZU2YodCgrQnVlO2YlYVg7QzZ6cG9YI3ZeJDhZPUlBaVo0
WW1TJThoMGM1THVJTEAyKnh1bztnO15uY1VldTdSCnphRjM0SEo+NVh0KitFcyU+Y1lhdCpHaHVR
aFEyMUU4KHg3NGdZc1pYP1ZKNihCOzlPfThQaGVkbSZ4fU1FJkhGLQp6Q1Y+aTBNNTQ+P0U+dnEw
Y31YUGdKRnpQZ2NrQGpoUHUyeyVacjUxQ1pOZGEqUz8pMUlLQkQ4SD9qIW9mdCEtX0YKeis1WHBN
NmtTKD8wPilra1loQk8lTHw1dmNpYjBeVS1CbG5oJHVRd3tKSCZJcl8raHYmJmZqR3ljMEtoJjZy
SFJRCno0ZlBieXRFZ0JgcFBYVzdiO0VwRldvMys5KVExaUNkbSk/bXItIWNoNGlIUH5DP3tNWU1E
Sl9KQU5oM3Y0dktVMAp6bWcrKF49KE9oSGU3KW1rK29ERjFZJCUyLU5JS3VZY1p6NCEmUy1SN1I+
Y2hjP0NneHk9Kzk8VnFQb34hYE5xcS0KemNQR3pSKGhKU1o2Wkp0eSsqIXI+JiQ4VWswVmc2PXs8
cVUlOHl5WXtJVl8pd0VJTV97eDNXbU47MUhDKkY1RW9TCnpHb3MzcDZuSWJBUipxUUopO0FIQk1T
V212enBJfkJkbW5zJT4pTG83TiF3e0h1RnJXX09tbCtPcU9HIXBhY2QjVgp6ZWNmZUhaQFpoJS1U
MzJxKCYhTk88QSlrWT5ab3VlYihUQTBrJnojJWgtI1dzXn5rSWR1V1RtZmIlQzYkTG5UVGQKemBn
ZHMpVkckN3V7WkB+cUlNZGhkaEs7QTApWHJPJUF9emJ1KCtacnhrUnw0bl8qVmU1QDZ5MygxLU8y
Yjt8fF5hCno+KyQ7Zk0tRytgUThxZnYkJk1XK0xrMjZIQEZZa3lqMGt5eS14U20/KGtuVFpjdTI4
e3I7RFNYS0ZfPihHVypvZQp6NklsKmhhcXIkZDg3TD9XXis3ayY/MCRGcjhUNUtyNGNaZzhSQUN4
PGliMSFwUSt+d3crRDdzKEVmYXhyNVBRaD0KemUyMyF3QGZlQlI9V0BIVjZMTiF5aCZXbExHZ3xK
QDtIUTh1Klk2dExmUWJfcDlffDB6UXJzeGNNdkVqd1J5WiMmCnpYXj09MjgkUSVya3cyNG87czdu
UHdZOE56TCFrTn5zS0heZj4hZEZDP1IxfEt4b2tmNi0jTCtkQkN6aGhIfWVkVQp6R2JMYVFLIzJA
bnotYSQrMEQ+R21ITFpFQWxzVD5Wc1dZWHIzPyt7aVN3bVl0bCprbTtUKik1dlBMXmVkIUQhaHgK
ejRUdzFiKDxFclpUOUtfPnRAIVgjQW5aYE1DOyFlUzRNczs2e09kX0ohXllpK1FJMFBFbit3U0sj
V35jPSVLQzg1CnpufSUwRkY+MXNPdThIT2cyez1acSpNWE9rdGtsNSpwRlpFNilPQj1wbkImVnFu
fTNYfUdoM2NwI2J5PWhFJE5WOQp6MzRpMXApPjxqbWU7djt0KEhROzg8NFFJfU9VSnhweVBMRDBi
VH5BX0R5PX4rVGBTMFdvIzhKUFomT0I7WTRyZ28Kei1YbndhMEtROUwreWFtfEVqWnt7b0V2Nj8k
eFV5NSUwVVYzZyNRMUE9dm5tRmNSbHtVITRLI3cyR0NZKmZSZGI9CktZP1pXR0BjI2tiY2BCUiQK
CmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBz
ZV9sb2dvLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9sb2dvLnBuZwpuZXcgZmlsZSBtb2Rl
IDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi41
NThjMTBkOTg0YzBhOGJlODU4NGMwODQ5OWNmYjBlMDU3ZDZmYWU2CkdJVCBiaW5hcnkgcGF0Y2gK
bGl0ZXJhbCA5NTYxCnpjbWVIdF9nQi13di1Tck8zbkhrMShrKn1wTlJ7M2RERkc9YDFxN3JEZ2tD
ak4zJmxjPDZpdyg1ZEkwR3A2Y3QxUwp6PX1vJEhMS1AkKzNGVTc1LWhiZiFhXkxmd2I4YC03IT43
IzdKflEqbz59KzE/PnVReyhXdXR7ND1xeWIwdF5vdjUKelllRW99JUJkNkpOYCZDVWJURkx1KUhM
JmZBb155P0FKc1JIZTB5K18pbVFDLXVjMyNkWi05LXIwfjhQdEFuZmM4CnpfcCE2X2JQKUZOZXZE
cE1WMXVBNTViVy00cWJEaEE2T1cmODVGMlZYSCFpTX5BVmpKaXdBYXIqNml4bGY7YClpfAp6eCE1
YEx1eWF+aGMmTCE/N343dThUcz5YRGFmJnhRPyZZfSlxQyNQeFVwaylSKz5POHNlYipeUjhKb0pU
RDJPT3IKemxya1NkI3coMFlrcEh5eXQqQEA/YkAtVyRyK3FtM3NnUCFgM04oWUQ1aUhsZ0BkV0wk
KTA4andqJGZiKj9AI2VpCnoyR1IzaWclSUBVU3shQmdib1VBczd7WHF1OUhhY3BgME99a3hjK31I
UWVnTz5mRm54KnthcEhtM2x8YmxEYTk9PAp6Y2szPVpecD5JRG16R3gqIW1oYyVKJmZUTl8mYj8j
NG5EYEFuS0o8OUJ+eVpQMGhAdVNYODdJPC1fPGhQWGtuSXwKeil3bE9CUGNBdDhyN292WUhNbnZt
XmghUUdja3p6Q0tJZTN0WXNxbjBNZDNZSDE3bnxUbXo4Q3NpaCRCVzd4P3p+Cnp0JEFefT1IPCgw
cD5yPlFlTzEhNj8lZi1oYCM5QDZCeGRObHdkQlF5akt8RExIVDh7QUZGUUY2cCEoS0VqVCNLdAp6
M3lVaFQmWlMhQkQ1RGtsaWh0PG8pMkZxeGImUmUydDUzfCZJWTAxXnNqZyEqLWROR15JZCVES0l2
c1M1IUlldS0KentPSV5lPTxnaWB1R29jQyYoe2xTb2B1KD1JU1ImaUdGJGBNPVpneVpYT0tkcWRf
O3s+M0FQOC0lMH19Z19fRXxfCnpEZzNkUDNzNDViSVpZXngra2J5YTN9Pj8taX1ELWFZPEU2OyFe
ak4jSkkmbSE1Wm1fJFUlbVZ4NjxzK3o+YHJfUwp6TEU5YDhiZVBlZHh1eG1leFc/ZjFodGNncWFV
VE8/cFdfN3YjfE1mLTZSXllrb2IxTGtaazMzODVFT0hZXjd3Z2wKejR0czhRLWBYWHM7O1hPJStR
ZTBwe0NjZlVQRUpJWVlpZFolKD9tOUVySmBAZ3A8aWNnOyFpLUlZPVlnRXptdWpxCnpPOFBRPitA
ejY4WTtTczhWWk5fKTtOTVRIWGhrWThlP2U4R2FVOUNmXkVgZVU+Y1AmdXl7U2tkcUo2aktXfD5C
LQp6Ulg9bWk4O0JONT88TnFzMX4yRGxiOzV+Skt4dXZ1R0NnWH5DcmFlSVdLMyU7eX44aW1WYDwl
ZzdKQjBLOTQ0PCUKemR8Yjl7dXg9UHpLMkhUTFR9clYlM0NYbEF5PihTUT5mQ1Z0YCV7ZHpXVU5y
ZEEpMm5hJDQ2ZGpDOS1KSmtVZylUCnozYk9yJmd6dn5wZSNHRDB1e2tNTStNdSNLPktjKXcmIzVN
PU5VOEBGdF9fMjtSOFk/YnV6YzdCUEYrUVhNTyNhYAp6amNlaWxyVUdSU2tAaGRFc3RUOzh7PzFL
fWoqZFR+WHZ4NzBzR3owSkhgJF56WHczcDhIPip1c0pYUHJWdzJEV3kKelhyPDhpWXZkV0BaXyFw
JWtrP0M8Vl9gQiQ+RjxqfXQ7dj9ydk5vdD05bT5ZRkJgez4+WmpuRD5SUFBYKjFQIXhPCnp7bH1C
TjNUMWRMT0R6TT81JS1rVDR8KERDNT49WXcrY1JCNHFeQCFgK0x6NUh2OFNMPF9jZzlpc2NeNipD
S2MzcAp6e0IwRUhkd2MpVUNMOE9kMmBwa1Z8My1nSnZhbXRWbF42KXh7TyhRIWJkKzZtTU5DYl5J
XjxuPjN9QGJfYT0lb3MKek4/USsleVpQMzJ1ajViQG9VKTJ8aURZZSZGMSkmYFVSdiZfKk04IXRk
TCo1aj52Jk96QHt7bUQ0eGshVy1jS3IoCno2aXJfbDt3c15mZ2NRSCFHdipjZk9aTkdAUlYoY2Jt
a1JsUlJVcXl7JmBwWTdEU3ppSEtnZUJ1OVFRQFk0Y1VBQgp6eVolcDZVLURMZlFTVSsoTElId0s5
TX1DdzlWWCpCVF8lUEAlISFIOXNmelBfa0YjTVIlYE8tdDhuUypZWiRjMUAKekNAP35sU0Y+UzFA
emJqY2Rgb1hUUFQ7YCV6XyNjY0hTfGQzWTgtU1dxSz1iWkY9VFg0JWotR15sZzRNeTJTLSZpCnol
SHUxaXBzPzxMd31UJiNaPSZBRWB7Ozlna0stRF9YfGJjMWlANnd9RnNldmszPk0/fTM1NkVsXmow
b3RGdVFlPAp6KT5AZk9Wb3lTISFUXjEleWRARFVLV0tVTEVQYXdlKG9Jdz9hOTRSWmFZTjhHITA9
YTJxfjVaQip+T31HQ3B8V3MKejcjJkQ3UzFiNG1KV0pGUVdQeCpidUVAajFfbERiaEdVOVpFIXww
Qms7NH1hSVRJJnkxYVJXeTJhPEMzNWp8UXUkCnppaXYrfj80aGh0WXpwbGVsbmthKXRhUWVGSXFA
d1BmQEdNMF91SUN5KGxrcigtWVY3UmtvKzVyenxeO2xQRDQ9Qwp6Rl5hTGBKZmM2MF4yWDRxQkRA
dyZfUCQoJk1eWnlxWGFPJnI8RUZqdlBFeWUkVStKPWpJTmJxIV9+TzQ/VEt7ZX0KeiVESlgrTmNw
fFdFPkY2U2I8ZU1VQV9xWlApRjlsJldAZlUpRU4zKjQ3Z3MwU2B6QXM3b3VnZCtfNERuK1h1WGMx
CnojbzBEZHk1SSpFSFV3Nyl5MzB0Pj9OaUY8V0BpNEYoSEIoTSFvX1ZNMmwxTU1zO0J2Nm9Vaio8
cz0xWioqSlZFLQp6PU5PUTRVJTItfU0hfDxZRm9GMkMqQlkxaDwyTUBQWiFTU3U/M0ExOUV2dmBz
K3tsTT0lQSNPQj1FRCEqMWxQP3IKeiN8cCRUPSttWCF6I0l3a0xYWFJHTzF5WlFePG1vQ2lQPT1w
SVg/PCstaS1ZfCteejg8T2Fvfjw3dkpPbzBDMUY1CnomYTNDPDFpYSNnM0Fpfk1NNGhwUDBRQ1dk
dikqXkM+KVk1Q1VLODRFJGdVZGM4diNoRjEwP1Qkb2FRSFp8Nzd4ZAp6d1NmcjVTMlk5UztTfU12
K3tqemtUSTIyV2QwRVE1Qj4rcXBEN3hQS3cpVG9lQmpSZStpVCRMbTZPZjdvI1UpPHoKeiUzdDc3
dnprRzNnRjt9Tj4pJiVEZ3R5PjE5JX50PUhCU0s5UmYrfT1VZjtURSVrZj13dTNZfFI+UkJrdmlR
O1FhCnorVTB5VjNeLXV3aS1aNk8lMj1lIz9HZ3wwJmFzY3xBTUZLTi11YjhIa2lJQipfdHo7PGQx
eVFiTlolTmBATFNfOAp6SD5fUkwoP1coN2ZfZyMwTEFna0dfYnFwYHM4TEZTJVJnSWp8Q2B3Mk11
c0xaM1J+S0gwZXEoO0FxWiYxe19scEgKek1xbXFZeXItK1clKGRAfElZNG1hdDVURjJuO2M+aWlg
bWlXWl9BTW8xT2F6dG5TJChCfEhgTSM1P3t7R1k5ZD9uCno/OUY3WTk/cztiTHM5TSYxO3MqVGE8
OzBJcVAqLWBCNlBwRSlwKnl9K0NOWilLIVR2ZVZ0Wm4+UX5eR21FdkNFOAp6QE9nQzhHOVlkSzVj
bn5iZ3QwbTc4dnFtPz9ednB3UkFUPXN1b2l7KnYmTHM0bVpROVFabFFFTElxY1dNeWpyQEwKemZk
YSZUVyoyMEcmb00qLTw2SUB3cmBWWHB2TTRXY0xzMUJkN0loJUU3b202NS0qVTQ/d0RSUF5nUz5P
VThuI0IzCnplWkJ6bGA1TlZJc3lGTmMrXnhOaCU1PEZfQkdzT196clF9cDdqcHM1S2wkJmokNiEo
YnlNfW05VTdlYkRJbSl1aAp6ZHJPY1J2T059eHJkRloqYE9+MVpiMjAqYCNvRiRUbGF6Oy1nKV9F
RjtYOEFhSlU9YXFLflFpUUI/M05YSTA4JloKemtCQncyZH1SP1QlSFJFSnVAdzBsNiMzYFI2eElt
WnZ6KHU4aV82QEV2QzVfTEhqel4tcksoPTRuIzJOM3hXTzcpCnpxUyErNU83OGk8ZjVAZUpJRVNf
O1p9USRNcytISlJjX1RRWDdDTH5BWkpYVVpkZUQtQzY/dldTdjlyNFJHcTZWYgp6JGo7b2JeVkpB
Q05hWnJjREk8YWc5JCpxWEMjRCEtNSEqKSpJYExAVTAmPEkzOGVRVmEoUEEhWXMzKCU1azY1VmkK
eilQTmZZdEdMbWU/b2MkMS1PViZ7NT1RPV4lVVEzcl5IMipMV3YoQmclWXYxNDc9Qnhod2IpJHRH
cCtlUS1gUV5GCnpec1hpM2EzcXFAU2M8NGB8M3BSUE9zeVlRaj4oQWcpVmNha0RFaHUkeX0yS0p3
LXcpU0dfJCktZW9GPDNnO1ZnXgp6d289N1JtSn1gUm5EYUVwPjF1V00+ZEBFO3JBZCUtPFI3eEZ6
KVc5dCEtK1NidW4/N2hKaU9OPj4yajZebkElSmkKej1nYEJGaWJUTilEWk1RPTcweT1YblVpaD4p
ZChnP01WYURaPmMqdDg/V0h1SzNFJnAwez57MThYVkhaPl5UdE1QCnp2UmxtZlVzTWgqOFhMQkd7
RjhoS05Ud3JPNDRTeVAhWUxyZi1rZ2AyQWtGP31PcV9jfSppaWtEXmQ2ZzghWHhCMQp6XiZkcWpL
fXZVcSNiJnxeWEVnYXBLWXFzUFhxYmBsKjdtUDUjKUw8KyEqX1Y+Q1koYDska0kjZjBzUXU1NjRY
JE8KemN3fDM7XmxBfDc5WX1oSEghPnk7TztYPjlAY3toRExwX2c3aytoYURMYEB4UGFELW19ZU8k
NGlgMEgoI0tVYH5jCnptRjl9e1ApMGY+amh4aHl0OGRyd2d4bEp4eDUmYEtye1hkOSpOcmdwN2I8
SFZNQjtnekhTWnV4K0hWWXY/cHpQPAp6dnd7PDRLejY1aXAzS0t1aGYtYjVFfFheK2pBQWkjZjQx
P2JWWFNOZlNwVWdNUklPNX4+cXxqM1ElOXlFZnVFVCkKemxpdU1sNVYmVmpUPElhTkZQRz5FTm8o
NGJuMSV2aXl6YSpTOXxIOyMlQzBDUnJ8ejQpPlEpfVQrPiMkUk96aGY5CnpBRn5HdElLOU1qb3JY
TFVEMEhBdnBQQXU0Kj81bithbWFuUHQqNmx3bTZVPit4fEV2bntOPiNAY31mVVpxXkA0cQp6YTV5
Mns8QDhDKENhKn1qd3tlNFpSOFkoe150WDNFV1R+TlprNiV4R040VH5Xd0VOYXhZd2RrREokSUlk
eFQzZzEKek9wfnRtaChYIT1JOVpXSXFyTE87ZDZAPkwqdEx3bTltR0lhKStzYVIwU3JtMW8zR2Vy
dzNla31ifE1XUU01TDhZCnpWS21ePzBfUkBqcF8lS0RlbFVfSz00WXpRREg3NEJwTUg9ZypkJiQp
RHVWendkKUBwLTcqYldeYkVAUGNtZ1NBSgp6TXIyfGU5VG9OSyUrVF92bmAha1B3UUsmVkBlZVo/
LTwzUE9HdmZVMTk1VS1LOEEpdnRkamN3PjZ2a2V7VSlLa00Keil4Tj5LNE8qeylGeTNwcEQmJGYh
a1MlRjMkbjwoTGolNVlifENJa2xxR090NFpTeiMmVzMrIWhIJUZqRzh3NHFXCnp4KEVXKT8rYyVs
PkZmfHR1OypZVUMhYjh0WTw7OD5TfUhoYnBfNiNPc0A+dyp0XjEyUF5oMmppeSUpUjdpPnN7Twp6
bX1qcG5mfj4qLUxiMW5MLUs4LV47eDd5RDctIV8kP0I3JXhEN0hJRjRNdDVDWFYzejNYQmZ0cnIl
dVErYFhSSSQKelRMYiQjKGVxa2htdmQxbjhVOHs8TnwqSUc2eXljaTw8fUxPKTMwIVdaOUxJYGF5
WEA4PXp+Zz49SzJOQyZYZT9mCno2NF8zKUVxbk4qYj9uOXE8UnRrYHhnWVlNUklfI3spOUlGOEgj
bVNrRmhpb0UwUUBsRjZlO3xJPEhoQ0NsejZSNQp6UyRjTWpZM2hwc3IjZ0NhY05gbHd1dFNrVGdH
bXFqLSkoRj14ZnRaZVgjWCVNP3t3fn02XllxYmV7aXtHYUgpQzcKekplKTNzPGBfaDs0KURNdyZp
Ynk5I195dk5PP3Q5ck1ndER8NCY4RXdeITN4THJDb3dHVVB4Nis3ay0oVjYhQWcwCnoobnRIfHhk
MGM9b15XcFchX2xLMExPSS1hQnYmTGl4Rm8jPlBDLTNxMFlJSilfOz88IzBLTTRPYnFRVl47ck5H
NQp6X1c0KW1oSTM7YSpMSkUzI2R9SCRBSz9wK2FXPiM7Mz9pQl8zVjlsSnJgX2t9NmE+Nl5vJVFi
XlRANn55ejkwcHQKei1PTDlKRmM7RW1IazNJYW0zeDMoQVZuISZlblYzU2hUI1cjaHw8fTd7TmZr
ZEJCZVJneiNCS3kmbHx5SWEkLUY3Cnp1ZnA4WG1jblJOVllEVXFAPzkkTHArOS1pPk40Ul9oa1JJ
a3MoT1htcWVfWnxZN3ZvI1JQLW4pVEFAPUMzaEchQAp6QzF1NF9yTzwwcHZyYjFvKEB+anpRSUs0
ViZzRllYSD5GWX43cChEenJteDhFbGhDO2FLKFV8QmNsZyUmbiFBKVoKej1GQjxRJGBBSSo2dz49
VThDeGAlKUpWNm4kNHMqU0pPJmwzMGFRdE08S0Bsems+ISR+LTw5O1A4X0J2PWhlVUhYCnpvJHUy
UE1RYTZIeG90QG5pMSNSO1FHeHpALXxQYykmUT5nNytrZyVDeXlSaSM7byU9NkFUNnU4VXVWYkpJ
Qy0/Pwp6cDtSSVRqPTJkQ1luPHwkcyFaUj1MckBQUiNnKzBzZjRhOCZBUUlBbC1BN0dTY35HNmV0
R2M2Z3hYYEsqYlhBZWYKeiVjNVZGUG8xMlh7XkNNXih1bVE/KVV2SHhAZUw/bVhoMEJ3JnZwRERI
RCZ5eTAhbG5FeyRJbGNTUXZjJUMqMzY3CnpxTFVEJHNkXkBJYEZaS1hvQF9UYjlLSm8/bChzPCgl
KXd4c3lHOW41NSk1Pyo8MzZoPEJxYkgqRTt1RzhDQW4tTwp6emFycWgqWTwpcTYtUzRjZGI5bUBS
eDVhNnBgPF9RT3RqJCQjcU1ZQmhZT3dGRzh+QUZnTWNjVio7Y05HZzs5ODgKeiQ9cUNtYTRoK05h
fTxaWXREUClsdGZBMnpsMTl5WlI8S1gpazhzfXs+fEo2cW5qNXJOOHZGdXs/Xn41JUl3JipvCnp4
O1ZLbV4pYEIhYH1tR3ZsOEhfaHJOYyNgM1ZYM3UtRGpYQjMjbk1Ya3V0PDdDQFBAOE55NChiRD5Q
U1F0bU1FSwp6K1pjM01yI007RD5EYUYkSigpQXM3Pk1yY0A1ZkQpV1BaSE9wdEshIXhiQFI2YSQ8
NCglKSlafilYe3lVayVDTEAKemVuQEVTO3ckPz0qb1NmOW5uUUJlPD5pN3NKPnJzTlE0LWVaX1Ur
cD4tT2BlaGd2UDFLeWwtNGI3T3spOTJTYTFUCnpnUnYmUXliNXh0R0ZAYWRPNEs8RWcrPz5ybl9l
K3Fjajt5S0FUQmlvQnlTQUNeM3VqPCY4VlAqN29mQmt7aUx1QAp6aitgZX1gO3ZwKSs7bjFoOWNz
cGl6b3s3clN4K3kpa1cjTVdgSCQwciY1TVNNanFVNmojS3BAY1lgIzFScDBFRVMKemQ3I30tPzhr
PT1Xdmo0aFA2bHNTMkE0bmkkbiQ7TEd2QmxBVHgjZyNVVkI/eGtEX3ZlMjdSN2s9d1V9WDEzckRG
Cno8UkJ2Qz9+OWAoOT9HKzZlLXt9QTFPPCg/d1RyeGNkP2Z3YTZTfXl5ck8/PTZwVHFmJk9AK0Mr
PFJnRXAod2JyTgp6YWNFbCsoQk8mcC1fcmwkM3lYQCNfU1E4YWkkaCY5eFQ5eGU7d00hRzBTQH1o
V25jWlY8XyFqVk8yaXlwQj82RCkKens7JWZYdHd4UTBCdTFNVXNkNERwVzdwS1VEfiV2bmlAMG5y
Xl4hakNoR2dVfEM+SVAzUmxEIW4pUXRJITEkWlIjCnpHI29DaDs1S3RUeFZCfjIjO1hoa08tZyNL
eHlWSlcoVlJzd0pDb19TLUJxNyVyYGNTY2g3ZUJaKk9EITA1az1qbgp6cGBwUDY7Q1chKDNnb3h6
cH0lVTwtKDxmS0dRJTE5YlJCSDx2WHhwN04pTjBeP0BrRTl2fHpCSSYzO3soeGdGciEKejBAQmlZ
JG5BbXN5fnpDKERVWHFCPX5LZjImQnZlPHw4fmQmIT07VnQhcFlqdFI4KlI5eVY4bVhvblh+cVdq
KCliCnoqVTl+blVleHBiZU8zM0ImMDZeO2BzMnFBcSFeKGB6cWwjMlYmezckT0p3RGY/PXgxR0hC
NXJRUiZxYDVhMVo2Vgp6PlVyayopSDZFY28pYmlHeXlBZnpKOXVHK2pSI19SKVApTDhWcTw1PTJa
emtJbylzOHRKY3VLZ2prdXlAcmRlUXAKenM0NihneDYjUktkYn0+eCtHRV56M0RhejBGfUQ1WGpt
WG1Maj94fnBpdGZHezJJWmtJcCtePlBFYD01ayFpVHJOCnpPV05HWk8pb2ptdD9wMFd1WGVNamEj
JEc+KjtqKFhMP1M+WE4zfTMlJX1NZ0QjZk9zWTU7K3wpYnFOWGZicXxHTQp6MjleXyhOQCV4P3Y2
fFBHbkkoPE8wK3M9NShtWlNVPmNZeSg/WHVFP3NyM0JeQUl2X1dlMERnUG5WNlBaUzR4TVkKemhw
azBtMHtyfkY3OUxIUU9JQVUqKE5aMnRTdEI3cSEkKHxPZG5kVU5EbnxpRiE1V253a2pmT3ViZFNR
IXdzIXpJCnpPbyR4UXVNWWxadnBla3s/RW1fR19vY0RuZiZIWnpkMUFLd2ByRShiRnskIT9Ee0Qx
N1BSZWQ+Wm4qVmA2fkRlJAp6ZTlRR2QtTlItVGtCZ2loZkZnQXV8Mn5fZk85RipXNVB4P1dSd2xg
WnJOY2dyTjF3QCY1OEtoJTh2aUxLTF9oOFMKeikoOGxpSHBIUEMoa0VJWmN6TmdGIzR0KDkkO2ww
amtMT149dj9gWlUpbGYmPGhMSH5ePCZsNkBvQylPKXEpb2skCno7Xy0wPjlXKX12dV5XWVhCWkFY
KHVoRlFQTGZ7MjxSdGNNRC1GRVNkbXYrbTNOSkRxMkN8ajdnc1NRJiV3YGd5bAp6S044KzhyOzVI
Mk9xKW9acjlgfilldT8jdHJHLVZkXmR2Jm5xbjtTU3dmODV6QDtBbWJBd0U5UyFvM2tRNDAyVHoK
emVLRmBSaW4pd3olX0RPUmIhQ21FKDQ4flJTPVA/WjF6ZSNzVWEtRjNHcXhCRSMhVFRubCVZJjFQ
UDQ1TFBvTUQ9CnopYUdrZWJmcXxLTl8/fmxjPX5qNHhhND9wXyZjeUFwdFAjUm1PRT1FU0w9VHRC
YFk2PVoqOT5CUn5XJT9od1FffAp6LTNRZGpqYGAoPiMwfnZpLUx6fTRFcmY7YmF4TTtad0VqczM/
ZTBlNjhoVVZZdmdGSXZhS3Q9QDJCaXIxWnxQc1YKenU5dWRUY2V0NmV6REgySmMrYUlfemRrNTxg
IUV1Pk5tQHh2T2BNcURkLT9MWHJPJSl3WmV+bDYyWEA5ZlNaJigjCnp1VCQpNE5RVS03NGkjWEch
NDZZU2ZBcDdgT2h3WT0/TXtwOHI5TUk3O25gVGxUcFFJJCFzU0B5T2Njcm1ZZ0oocQp6dHJPakAr
MT1DZmlxU3xXTTt+Y3FZJl5LfkckNFY0bHZAPzZLI0UlNWBgUjdZRnFNdDwpWFdTKT5+P1JAO0A1
ezMKemdlKXJFIyFSWkpzYCNhKVAyYV8mPUlya1dZeThzRSglTFNYK1EkdShMJj0+cjRFV0JSZl9H
S1lHM3lwSTVjUFFxCnpOYmQ4NiVxWHVgMCZhZjZnSFV1UylPY0BpUGl9RndmPytoKm1GJXkwQFN7
S1YmQUFwZFlTZXNVUSNvTXkkQWB4Kgp6cX55ak5LO2NkXkZIZkl6PitrdVF2NnZSOSViPjhJMG9X
WnMhVSRhJTlSYTYwJkM2Rm9BPTJGeiZuO1F8RDZhMzgKel9gdHg9ZH1PKFN2NUFTZjshcyQ4VHdL
UTA3YmdYa205MXJFPnM7TDJqSzhNUUNNRzhHR3RydFVhe1h0STF+VDt7CnozYSRNUUdkM3Vqen5f
Slk7T0pNPlBna2pWYH1ySGF2eEswVnZpeFFyU1UrNlVyMipadyotOFljejxUYCU7bUoyNwp6ZDNr
NGlpaip6MGpuaGpBeSYpWCprcztvVG1XVW45QjVgXnFtS1V+fGRmKlZ2ZW9JI3d6cT1TTHdHb2Uh
KmtublMKelNpM3R2eld8RmN2YjR6TjYtO3REJFVTUld0KXJfb154PkFIJWlZYVduN3JKQUR5Kjdo
QWlUPGJfNXt8Zlg2UU1BCnozTm9RPSp0X209Tkx6dH01YGhWO3ArJk9ybHdwYWQlPWpYQz9KVlYt
QkE3Xjw4bnBqdndCRF5LPjhBQns3KW1Dagp6LXU8dk9uKUhPZ2hna1QhPSllLWUhPj1mMDg4RShN
P0pidlRqYE9abGE/M1h+KkZ3RkhXTF48bU8hP1BAcmM2Vj4KekNOUEVsbWJNPzV6T25ueEw3Tm5t
LXIlPmVlYW0taWxoNVRkezB3bT9hS2wmV3U8UFZlWndqY0ZfQThvLTZeIz1TCnpOMyNzUEZnX2pt
YF8yVzxxKFNRNCFZdUZaK2hpQG1mK2puMyNVSmReIWB5WGJ7Z0lBb3s8c3MmT2dFVGxvJUl8cgp6
UilPVFJpRUJUKHl2UUgmYmNURHJXUmV5dXtfdyk7V015JSNsTmR5Qj99fVc9QCtKa2hrdjBFZG9L
M15VYGtuSTgKekY/bCZfZEFCWDJSOVU7K0A+PjxtUWVPJV5Uemx9Qj4rPSVmclVDQV4+WVp2QWUj
bUw3c1liJCg/ZndhYmBDKTVnCnpLYj5mdj8qIWxGKW14OTk3dVFufWl3OCUoQTJ2RHpDaUAyTF95
e1N0eTg5eUVENFdQfG43SGQhQUExKElWYFNfPAp6KHVsIyN3PCMrP0RuPUIpUmt7MjRVVX50ME51
I2RZOFchUkhgMyg0TEdPe3d1ZHx2PEQtVEdaSnheIUJOVGRwWXAKenVmUWdhY3cxNjg8SEYwIU9C
aEtgOF9vKXQ+ZkpQcT9UPEZLN0QwRGpocTJ2cXNWciZPVm9Pe2Ima1ItQ08tS3V3CnptY0A+aFNy
R2BWc2J0RV8/KWJlaUBoPWd3LURraj1TcFRqXm9ldH1RemdvQ3pWb0V9PjxqU3lMK01SJGEmN3po
NQp6MlhZdXBaaEB5fkNRa3RfUn4+a1UrLXxZWW9FTSV2UzN3UWs2XlF8VDchSX51LWp4KSR2O0A+
aztId0g9cjAzPTEKelUzbzZNPXNaNjxofWJYU2xTe1gqU251YVhHfnF+YzJmPkhSYUBrK1VXKEoy
I1l0OEw2VnRXXmA3N35zdkh6Y0piCnptJX5sMW1WLUtSKEpTJnopZyFLPzw/dilEMyltfko7Rjsx
P0A8YGQhN3dkPTltWiZgcHROSEhAKH1kSy17PUpaaQp6NXNSOVF4fEhJWnpAc24+N2VqT0dfJkJt
ZnkzP3xLeClkenQxS1cpYU9iUTJBaEZyKjlvRXFESWp6TCtNMEV2MCEKelhNVmh8WkV8eU0+eHJS
SDEme007ZXleNk1XPjRWZGhBRjt7OGUzeGZpPHFWMmhqPz5TTzliWE0/VkhNe0Q7Skc3Cnp1KlR8
JGgoQF94VE9ySDNoaj5CJSVheV9Jez8lSlBlPTQ3aFR5U3tvYyk0PDhmX1l3bUwqZyFTJlIzMkhi
e04oKQp6Vyk+OFo0dk5iMFVCUkE+LUlkU0UyZkROMC11OD5sXjEwbWdgcT1lZSQ/JFFQak91MEsh
dzIxcytkPTY7QyFudzsKek57Zng3NUwrfnVNU1c1OVorJkhAMWs0fjxSVy1mZCtSbXs1X0Vjb0Vq
YnREP0Z8bHJBcHE5REZSNnRvO3VVfTdBCnpDb2YmZjY2PU9GdVctaiYxXkBBVFlFaUdIcj04NFdg
REJzP19xK1pLWm5kYyNyLWh1OEVNO3gpYG15WXZia0dlUgp6TnNSQDRtU190cD1oLUEzPFBPI35V
PVU7S01CPmpRXmhkOCRJKElCXkFNe2N8X2QpRmdgUyRqSF53QGtra2lhQTwKekRiNEEpKHlWPiYt
czt1XjB8VFZGYDdUWWc0R1dAWnd4Ync9aipuNykzcWI0fi1YNmA4SGo9NTtYWil0cSFgaVBtCnp7
T2tFYCt6fHNxTDM3UFVSTEBpejshWTkkZ1VhYlkpZj1Pa28tKU5WSGVYWVYyNylKfVd+T1B3P35L
O0xPPjQtYAp6RjdBRVdySCNkI1E8dzltbl9yJj5lTnBiNGVWYE1hPCt8dCheb0I5VXVEdl5tVz47
THUqb2VIdStfQn5qKkUxZngKejlTWj1XeFdlI01pMFZmRChQZEBeIUtENmFCTGAjNT07KVpfe0xr
LV5MRnF8SjdxTW5YMXU8dnw1V2hfUlBhQl4mCnojYjRKXkZjQk9vSFZEK2ZnQ0xJRF9YdmwqZisy
WkF1a181T0dlWU1NV1MjQEp4ZEYoe2tXWXVPXitaK21oNXpiZwp6MG15UkwyTXE+fko1dy04TGw/
MjtjPWIkQWVLcGxMSmszMXxaV2UqVzVXfD8ldFRwKW5td0ErTmQqfUR3IzdvdkMKejV2PnRqO1Zp
biFaYUFQKDcxa2Imc18kJj9ZVlFNSGtxP2FZU3pqTnlQMEV0Py1LNjw1O0NWPHhgWlhJbkZ6MDVY
CnpqPTs2WHZnWENhJjxqfk43JENQeGxkWCs1ZHUmS3UoTmxkTHI0NkdgTjVAO2Q3JHRWY3t9QGpf
RDd8el5jcXdISwp6U0AkTyk7ZThHPitAdWdsNGhkQk8+c3xpaHZuWCl4bHY1ezhRZSZIeThwQCps
N3tiZUdEZWpKQz13T3Y0bXZ0aW8KejxGOWFfMmtZQ3ZseDdeK28lZzJFSjUjdmZfWFFaVGR2Tz9D
Qk1gfCNMM1d2cj1eP28jXj5nQWRnU0UqOVF2WW1kCnp7OFpEJWZOWExIdylCVldRSERjeEs7bmor
NkhQO2FHUXY5SXs3YFo/RCU8UTwqSkBCYlVeZnhycHQ/VX5NfntraQp6XjElei0teygocHpMUV41
SEtMdz4mTSt5cEM8NG1zISE2KjhKR141WjY3V2A1KyRPMyFpOERGcGItUn0wUippQiUKejNGMElh
I1E9N3lidH09PXp+O1BlTEtxfWMwVmRrUWwxIV4tUnc+PmwhMURxbzUyK1JSbW84VWdpfF43ci05
emRXCno3TTg0Z3IoZVRRbG9iRUMkQlZjeUk1MXg5PTs2fjZKaTZ2VEtSPyQjP2Ikdnl2KndUUWNB
VG5Ob3xxKWJmcjdpIwp6SiRZJksyRGMoOzJJLXVRaiF3PHtNTDcpQzBMYGIheGolY3hfc3VyTGNr
Tml6N2hRYmZVcDd5M2FiaXpMSFd3QmEKenRvSGA0cVpgVUsjO09CK15CYzBzZCpIPFBuSHU9NTQ5
TSMoe1FqVmt7JSMzMlAlQ0N2MShYdzdQPCN5elJAP3ImCnApOE9AKl5aITlMXjFvbUl7Q19zJXB8
YWlIUmhCNn15ZWBFJEZnNHd+QzNoWUB8MVc7VFo4ODc9CgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEK
CmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfcC5wbmcgYi9hcHAvcmVzL3N0ZWFt
L2VjbGlwc2VfcC5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uNGRiZmRkZTc2NzQ1YjcxMWQ2NGE4YjNiMzQzNjc0
YjBkZTk1MzEzNApHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTg0MTQKemNtZUlhZzxJNm03ZUJn
eWg+QylXMCNZS1drfE4jR0E+RUMxY1Eqem9oe3omfnZgRSp8b3Ita1Yoald+PkVWVjRQCnphMGtE
Pz1SV3NPeGM1RkVBOXM9Ml9uYkwlOyZzbFBHd1VaK1chWEVvQ35pUkBrVVIyblF0QSowdH1YPEVf
eHtGcAp6RmNQP31BYEVgcWJkbDNAaGRfdjB1VTxHRSZiYnl+QFI1aEt1N2AlUm01MjhtSCVvfU93
PlBgM2xmQXE3OHk4RDwKelhFKkRsOWJwT3hnY2MkJV4tOXd4ZDI3fT9mQ2A7KnhyZm5xUjZ8dipJ
NCEtNmBvJWpEQkthYWtsfCtzP3MoemtoCnoxXjJ5VHYhPVM3VFN3TmNrKH1JcTQ8aUdDdGJfI1o2
TmJBSEZVWlohQ14yKTZsU3MkUHpAWHFsaE1zb21gcUxkYQp6X25EdDQ/JWJuM3hHM345dyEzJWhi
TCQkUkp9dnxqQH1mVjA3X2V4e2NhMFNNX1U2QyR8ME05QTFwYnIyZS1pa0EKek4/XyotQmNZbmg9
PXtRcCpPcG1yYClCOS1ldiEqKXBKbFkpR1JKPGBDYzFsYnVYQVpuNCFaZDF5OzxvKiVmWnJ+Cno0
PkM8a0xMezlBe29aZUVifGg7aiklYiYtTW8qVW9teCYyWTIoRnxsUFVwPj5rLVlvfWd7WnMmRWw8
bFYxd3tvZAp6V0J2VTdHT29CZFNVMmpSYVkyQTRUIVNjRjYxd2JPI357QzhBcHkwfWdQQ2Rqe1Rp
SmUkQHRSRyZRbzJMVFUja0QKem5gbSVLUX5tdEByYHJjQypGckw9TGA/Pn1GP1MoYlo3N1dXWXNW
c197aWRkZ0t8dnxuR3JzXz9tTiFzKnpnbVpwCnpyZFZPZDd+aGNRV1FQNERuZj01TnlnUXYzSXs3
OW09VXU4V14qfHArRCg9LTNgYmNRZzw+fUk7dDgmM31kKHR5QQp6ITlVP3J1VStGTSkjVDtsSEEq
Y2NWbDMxYkVEWTBxNEFaNHYkMjlRXiNxYDZTc0JON1BXamUrUCohSHlobytHWlEKemBQTUk3UEtV
TiVBeHRYWWJHdH5HWT59RHJpSzE0OGA0USomJi1lMyZIKzU+TzwrN1pMWFpvOClMfU92bGdeemAq
Cnp5NG91OVZoYlBkcnlLS0JSb2dsSDdhVnoyKntqR1Y5ZUdyNGlhU145fDdeNjJre0tuOWQ8eS1U
PTA7T0lVaHJlUwp6Y3laQVQ5fWZvfmktWjNUQys9RkxtWU9sVmwhcXQzczFRMWBwe0A+RilLPEA4
WTx0ZjNPanw3YHlhak17alduYkoKejl+VmF7aUNhRkZgU29aK3AwJGxydEl5YjNxfUNkNz8oZmFg
anM/dzJfTk43V0tQP1FaMyV8JW4zKU93d1QzMEtwCnptISUjbTtxfkNRKk5gcFheeyV2JmwjUShO
cygkdCRJXntIJF8hVCNXN1dpdSorYVhgPUR3eSh8Z0dFRDBFNnklSQp6VSgtbDAzbjtlODVRfSpl
OTBkNyRfZXNjO1hEbjwoVFE5QkY3ayReKC0jI2ttO1pePFY3cCZVbWdjXiE2YjdmNEwKemomcmNw
X31RcVRaNT59SVhYaVlVbm8zbVVVXn1gPXQpeEZXbGp9Klh2YEc5STs/K2pPM1NyaCMpNlJDYz5P
KWkjCnpsRyFoZVpySSZgPHpfI24mMnpyZ3EpV0hadXQlb0JoIzAyQHZuKFdGbmU4c283bDwwMlY0
KCZiNHhZIUYySGVSNQp6OVFZOG9oISRMeitzKlVFZyNEcmhDX31lQVFzcT9tVWctVD0wX3VINUZV
KFdkVD19bHtSWlVnQnp8Qn5ndjc8PDQKekd1MmR2YkBiTClgeGxzUyZfbD5xNld9Y0ohPXF1Pjgh
PUU4UHhObztMfll8fCl2WXxjcjU0YFJQPWRzNyFaVnB0Cnp7eUtKK0NjMklyNHJCRUcpa3JANz5m
OUdJdkMlXn5yaGxINGd5M3FjUTtpQzc4MExHTWM7dX5xUEk1VWszVzl5eAp6TFRafmlYRiNMRUV6
JDRLYlFHYWdvPmQjO14/Yi11PzZoWXx3VUFoQXZedEN0WjhTdn41X0x+azk0QXJOcGdeZCYKelIq
ZihEbDQ8TihNMDV+c2pPTmMkeS0kcTxhU25FSTdJIXFZXyt0aTVENy1pMGd+c2hDVzNiNlRRbEJp
fGRWMmRCCnpzajR7YWJ5fVdeMn1hdzk2WGo1d0IxPz47emlwKGpDR3o5PWY/bURobDBxWXxXQD5n
TUZVYFRFO0J2TkhuKShJWQp6aXdHazUkYGw5eFpfeHFTTXB8KWpMNFVISzVuZz5KNmIyPEFXQCQx
dkxBdUBRKm4qWkZgYzI9JWBiPS0wJk5ld2wKejxvR0k1SyVSUEJCUUAxZjR3dDtOLWpsOTdTZ3Az
NWBDYn1gVj00ZFh7cnhrZFhRayQ4enkrV0BjWGVReVYkPjdxCnptb3NKaCNnKTlQJk9RK0dsXmQp
clZOU19CRGtsRVpqKjB3XmBJJHw4PVdSPDBUVmxDP2p2Q0FTRzZEQH5xNil9fQp6UCROM3lqZkxh
VyhhVi1ya1A7R0ghamMmSz9FWWNDSWpeTWItbyQ2Sl5PS3w2K31YIVJBX2BqcS12eWlQeztIWmoK
emhhMi1ac0xibSZPQjc1S3R2TmJETitgaiFRMmFgQkdgNzBZI0dTTV56Qk5WQWNVRk5aWmVsJDU0
fik4dUUpYXZFCnplNHcqQW0zYTd9dmdjNUo8WDEhUVpIU2tRRE5jczJXc0hlUUdtQCFzc2c4MWF8
NGZ+UVA0U2JZUWlTdXx2alMhaAp6a0VOeT55VH5LdEpUSDg3cHNIQm9fbzVqZzxtO1ZscUAxP14w
dE1SaSpQZD4lcHx0bXdfd1k3ajlqTyVAcnFaUHAKeiE/fStZdnx0YUVtPTJkNT9HSUN3M1B2QUJI
dGs4e0stJXg+d21mdz1NdzRUWVZIbiV9K0psdXtLTCZZaWhXejk5CnpaM1A8c2ZXejZoU1hOdURv
K3E9fHNyaWM5Mz83YmBjO2V+NjxrV3RTWmpRd2RHXjs8Wip8VnkoZHJwOTBDWmJVQAp6ISlvZ2RP
OzlmOF5PMjQ7SXxnVzdSLSNjPE1BdCY3PSlqRD4tTEEzZGNMczk+RlY9ZUYzPEhAPCErJUU8UFp3
SGYKejd9JVpFKWM3M0A4ZTxSYTJrZTQjVWxObnhpTkIjUTNBdERKWEs1Xk8lX09WM0BrQ0lkMTk0
UFRgRTZvNF9jK1deCnpvaTBaSTx4fXxZUGM7e3dTT3g0RnFNND0zbTw3XkZoKVlQR1BPMkYtcSo1
R00mJX5qfUFXTXJUZGQyY1UrbzRaSgp6dVpTOU5gcCVidktJKT49VF4xRXZOcT1gNXJna3xxeSV9
QUtQRyZJaSY1VXg2c0d4aE9YbUQlTV5GJEhIenNfQSEKej1ILWk8UmRPKklEOUJiY2l7Znh9NiZ4
YFJqNi1oVG5DJGBZOztseyZGejsxNnpRVy1fa0pFNSV5Zkt9JVcwci15CnpIZUxFM0FpeW49JXdP
SVhKSkFJQHkwNSgoUElXe3xnSnRKZHVTMkxKVFgxRFE5QHV3bXRtKH1ESlM4T1NRcmw4Iwp6KUFF
KXA5aXoxTF5oKUR8Uzl3PSU7YExuU3ZaV1hYO1hxe1dnSD4/bV8jRUwpZm9Pd2U2SGNBfDhVe3Mk
RXVxWmcKenU8Ym1PTnRMQGdEbGAqJChUJTQlby0oeUlQYSZWVnVhU1AwZUhBUyRydDZYQVJKVGk0
SkNNdlNLJj9Lazk8YSZJCnpTY090QF5le0JrRD8yUGd2bUI7RzYtUXVoO0k/IzFuZDExV3VNczIx
PDdhWURCMXdDQWljbnNCZCsqSChfQDRYTAp6RmpmV184Y041eSZaM2JvUHkxNVllN309Skk1b2o0
MW0pY1lobDdeUlZ9QShBdlhyZks8ezhQZ2koPHpuVzJlP0AKellMRmo0cHF0MXBiSz9fPG1kITA3
O3VKU25YKjx+QVgrUDNUKyt2P3w3fUNtMD1QYDhJWkU4QTxgUlFUZlA1SWczCnpNQEpRIylFd3Vw
cnQ3QjtVVHtIWm1CMVIzc0FNaktgUHlCSTZTOUhXajZ4fnNIe3ByUWk5e3VKdTdzO3Fyc2xANwp6
NE59aWloPnBEMHUyIzdZUipAQ3UjSWdwU293S1lNMXlvVUd5Xj5kVnlMezd6YTF5MV4+UyFCLV5e
P3gtJiE5WnsKejBmeHJsS3BwfH1xXmRETGtfZztyJGEzUklXUntmfGhrbCFKUzFtPFBEXnV0Y1M1
cVUzMkU/K2ZaMV5BMzwzWWtnCnpUWDQmXnpEeUZMdmtvfW8mbC1IKXU0IU4leXh5OX5JYkthK2p3
O1klQlMwVUtVSHBLUGtKc1JhNDFFTW91Y3d9bgp6WkRidHUkTlRTMXgqYk97JGJXTTVlPXVMaFF1
KnIjQzY4aVdqc0U7eHJaPH5eR0koQz9Ha0FYNHtlWFE/Yn5UdzkKejw3LVZGUm5SQiZATnJHWmRQ
fW88V0ZUYHpHeG5yb2xxUEM5JG5eZ2xLcXJSNnQkTjMyLTNRe1c3bWBFVztyOShOCnokeXsoUlp8
YC1zMGc/UHt4dStPQkpqaUZkNT1pVUNufDkkcSQ2c3gzMTQrK2hFZld9Pyl2a1NBRypBaUItSWM0
Ngp6YnE+N253JWJ+bmVHNCVxMDJuKGNsKyVsN0IhcVF+YyF3cE09UUR5Uk0lc3BPUiZzUUNUWjJe
a2JKKDtKSmxkNG4KektTTypRKHM+Silra2RsbT0tck1HaE8yaHFKTH1yOXBnZVNKNyhPeDJjUX5K
PSpVX09odGJtbHt4UmZyZzxYKk01CnpmcnhBMCllWFVVKjs4O0IkIUFwajZQWGBNJCFDeDw4dils
KHRDS2pweHV7VX40LX1Wd1FKO2BNZl8jOzNoYGRYbAp6RWZ9bXlZIW5jeUFSP3tLJkJTPVc/RHZa
ez9JIWxOTUlpRHROMFNfYUR0Tzw+c0pJYGlxOHRDZDJ0S0REZT9aZEAKeiYobDZndmZTWCg1Sn4p
T2UobDRgS3pyNyU2PEZOc1JKVmIjZTMpZTIjXm42NyNNakZ+ZkYocEowYiVEPyR6all1Cnp7cipI
djgzUE49Vl9qaTJMbXB7fkkmNzkwaTRNZm5Kb3oySSNkPTBMPjNhTGtrdXpBfiNwTkI9KVRlTj51
RlEqdAp6RU4wSyNZTjdaSFQhPFNgQVhpQnl7OGdJUj1JXkdnXnRMI0xLK0EybiN1KlB6WWo8NDh7
PHt8M1ZRek5TcEp+UiYKelI8JFkwU3RMM0dKVWU0fSh9LW1jWkhSYyNVMHJic2ZJfnJiJWxjWG1Q
dlZwZkRgaT93QyVTVjgwdnx3M3Qke095CnpzVSs5UjVmLSNST3tzeHEpQHpHcXc3emtBaFg/dWF3
Z29xQXkjZXsrXmYrUGQqPSlAellJX3NDX0Q7eTFtbDtCUAp6ZDR0dlQjI0BAYDMtYFMtSC1UXjNo
U2NqRCEjYXFAQDh0cUc1UEd+JntNKX5wKiYxSFFEa19YYnU7PmsyWWx7YHsKej0oMWsxRHt+IX1r
VXhzMExrVXE3WW40ZkAoPnolJnR3S0UkX2lyTFdEMU5mVXI7ZFZQZ0J0R2I4b1FgNGJYI1NRCno4
KDdmUDApejtTPEthbX5aaUdwKXd4UnFtKipMMylkbk88QU9GKXRha288SW9ldHtabSswOzc0bHtD
Wmp7PTkxegp6R0xVfkQjSF9tUHdqbzV3QXlqQWYoYmNrUkkzQl5lX1Z5PTRfM3NWVnp0PT5DJjZ+
MWUrTEAkYjxUfXRTU3VmfEkKelprVkolIWFXRzUrZGJWRFNHeGU1KiUkVjI/NENyYCstZnRjXktP
a3U/ITVzYXA5RTkrT19JSVM2QD0kMTdRNCRiCnpBM0teOTtIQVRwYCkpJFdZa19kUyl+QGpRTz1z
JWFjNCUzJT0wQTRRT1ptNCFOKzIwRylMWEA2JjNVWkxYKS0mVQp6VkkkbD9yJEJfWHRNNGwkPFgm
X08/eTJEbXVRRjF0WHN0VGVHMTVEbXExKk91RkJ1QEZuelNWbGNfUjVWVmZVRWYKekM+SHRDWHRy
UC1HN1JONCRaWkt6OTRQenxwVkZFcGZ7Mnh2MlZRNVVoQmFGfHJGc3E2Ukp5X1hwa1p7YjtOVXRl
CnpvQzBqbVdYckkpVXpkQkQ5dGlDYkUrSWF1ZVEkJig9Y201OXBYKTxLMkp7SF5yVytTTSNNSStT
aVIkam9fbXNMXgp6OCRua19NTCZtMlVic0kjZyNRVmN2aS1BZUZWVm1fKShod1dKQj9VMWxZK0U3
bGA+OEw1JE13e0BUaEdwQTBibUAKekA3JiQ/NWZZO0l1fD91bnFPcEVAN0NRRXVsYzY0eld+VEI1
MFNRPX0xclhaSWMpOGpXXlVCYighfGImNlYqOClTCnoxQEd4VG1DSCh7bi12Wl45ZU9ERjhFa1pX
dGBHVWl7ZiEhPXJSKFpMKU9UVHhwbGFzSXVRRztSV3J1JXZseG9SPQp6c3ZgZFA1d3tTVXd5JE9p
RzFsTDs0RzleY0ReWWJKKXM3bFUtYllwfURMe2pvb2VoKyZ1MGNMS1RfZTVLQDJGdkEKentYaHFM
YyNOYSRMO3kqcTNIfFcpeks2ZXV4I1ZUbl9EMClTYHdeKyp3cTRIISgyODFnaV5RdjF3X1hlVThK
YTlnCnpvd0NkaEF7VT4jNUthJmhaKj9uP1dJdjBvZndFI3gyNnFZdjJwfVp7VX4zckBPR0F2RkJ3
UF4lYyNYNEQhO15gVAp6Rkt7NWQ7LT19UWhBK0okMCtjYTdjcUFpMUBFP2l0Y1k4cXhYPC02dGBu
PWgkTHxNVW8yej0wKjd9YXkrMUEkTmkKekhRWVVDdVYjbGt0e1coRHp8QjVvOHJ6OX17WVVKVFgq
I1c7PlB0OFohTjFXSyRHVEJqKXIkTnE/YXV1UyhuMThOCnp6MFgzRSNLezh7YjtJNVhlN180Wldk
X1h0d25QSi1TaH5QcWB4ZnlITlhiSzchWWFOZXk3XnRkeGEyb0Y7dzxIWAp6PWspKmoyN3c0WURL
WWhyQTU7MUlFeSVEN1RJRXJkMlEyamV7dmZpVCF8RE1AaHFXQlR1Z3M7el95KzY1VCY8UzUKeklg
Sl5qbkV2PSZeMUdXajVIQ3M3VWtEYGpSVFBAK08zK3pSRFFwND5Cb0lATVlvcmQyWUdkQyZGOUVr
PEdueHMkCnozOzhNdjd+eXNDUUJgMXBUZ2FiRHEjel5PK187JGtNfG4hJUF4fEVHWkY/TXA8Q1pE
dkEleWxOQWtlZW5WcTt+aQp6Q0Y5QntLa1l5REA3VzswMXRRWmw/PTVeM09FM2FfV05MYU80KkxX
TFFZQl5qdEk4QClgYEppTThMUSUlMVVNYmgKenpQemQtU285UUBieXFCUFF5aE0yWkF8WlhoejI1
Z2M2OVl7eWpCKkMjWnxgdFpiMjFjZUdNYH01e2ZeYU5LeDROCno2Z2FHbGIyUXkycFFDVXZkPjso
az9VRz9jZk9haDhtRl51RzwzUEElT0BHMWlCaFBRdVhyTzNjXlQ4UHUqQGolJAp6K3JpVGhMaCVn
fT8+XlBhMjMkSj1FPTxWKiVmclh3dUk7WHRAXit1MyUweilNb0JsVXUrWVRKaEUqZ1hvJFg1WCUK
ejlaaUQ9Pjs2QytALVY/MHRkSkpZeVNnUD0tRT9WT1Y0dF5gcD9ZY2VBZzE4aD1hNHNTQFhaeWQl
dUpoWjZDbVNPCnpXWG9HTkV1UjNxPXFySWxGaXBQMGhqZFpfSHU0WCVhYW0kUFA/RH5WNWMoZUA+
YWB2NXU3SkstaFpxP29nIV5pTgp6a1JII2kyPH1BJSpmK3JYemxxYlhMZGtBfFJJKW1tazk0NVJ1
RGZhMUErK3gyWWBEe1ZNMDVVZXVNRmooe3dfYW8KekFZWWpQJVAmaFgmc3VBc21VKjROR2Yhazdr
WVJEdFV0WXE+WWJBQCUoRyp1b2EwZClgWTxrJTh5SVNVUDNffkVECnpjWWBCYXM7Oyo1K3s/RjJq
MjY7VDElI29Ab2p8Uyl3KTkqP1N9elVRJigkYFdWWHRxcTBMaVheQElffDBNQ1NEaAp6a1hGYXM+
bEtEKUhZR3twYnFjYDA7P35vYW08cDklUTFWeTxXWV5yO3Z2IXcpZyFKOWhFbEhffik4ckUxfDFs
aU4KeihnU0BpSlhiaHk2SCleNT95NkNlWGxwODlzLTtjaHxJfHdnQnhNKGNlbSgtNkdHcnR9QSh+
P29NNmooLUsmWHslCnp6YU1wSVUyQCNIU1M7KVpjSnBzSyNWMERHUEZnc0ZFJClATD9xMUR+e0dk
VjFeJT9qYXxLcUUlK3lCTzchWEUwdAp6Nz9wXj1TQF4kKGdlVT0pdmdqQVNYNyZQKnZWdiheVD01
QWAmP1EtY2pZaDJ6RWJAWiV4PWhVUmFuflVoQXo8YjAKeiYyNDNvUEVOM1VvU2JseVMmKGMzWEhg
NyZzfFE0fWtKSWlnYjNURjQyNDJ8JEJaYW4jRm1GaytKYislU2hhfGQ/CnprVjhQVjJ5YkVaJkZ8
TXMzTlF+WlRUZlVIRndBP3ZqSGlaMVVLOWMjPipGWWhpTSUzZk9JS29Ra1dARnRvZVh3PQp6emds
K1dvI2lBb05FdzZ4WD9xUEZkKnJKeSpSZmB8UzkqPnxWZ0pWIXJlPGFadypVPmNyditXQi12Tk1L
az9AeF4KekxWb0V1Z0s9RlUtZU9zdUwtWnwzMj8jel9taHd9R1NWM1lJQVlIfldHSkl9Ji1CZkhT
YTk1eTlnbXlMRzlUeGJoCnpqPEtjeVF+ZighaHtLMUx3PyMhcmVsREE1PCQjPz9tSlVtSUFpNiRh
cklsTFMqdzhwJVU/SFMxTURFMFB8OSVBbwp6YTsxQ3dhUVl8SUhAcEVJUihZQm40WUZfVTAwXiY4
K3JlNE9LTmQoa0tYX3AoQCNlb3hRVGBofVRYQHB9dShZaCgKel47UWkoaEBiby1mSzd+SFBkWFQ4
eiZDVTwoKXsmQzBAQVZwcX1Ue19HeFpRRFR1MWs9TXVBUGc0c0s8fUR+a2BBCnp4Q1l8THUzPUI7
PSh7KDY7dXRwO0JWSUhsLUcjWDVVJX5HfDVrVkw9YTJ4TWhQZSZnQVFWMWtSMkIzSk1qWm9wNwp6
bCFMRDgqeVYhdnM3bHZyWmIqXjlhd3ExN3hiamB5ciNFNk9CenA5VD8rNXtYVFIrc1heKHZ1RFRF
ZWFKb0MoJG4KemFSZ0QxSlhwOWEyY0A+XkkpLV5OdEtWVkZOXjcpTEZZeUZLNCRmNUQkem01ZW1f
RTQtaHkhPGNOTEpQb2I7YjNtCnppMCVgOWNuMVJXeThJdD4hMVVHREViPk9UaFlha1BFWnElVHly
ODd2MVp3O3NnblZOckxlWTJgcUElVWZDTFghJQp6VTNQeygqJUw1MnB+Mn5WMjE0QSpCO3AtWHt0
d1IjKDhnWXE4Q3d4fmU0OCFLKis7I3VmTjAzX2dSNXcmQENUaWYKeko9Xi1GVXtxNEVJeXhtTE9D
SU5KU0hNc0sxVylgaHo8fUBpLSFCPTJ0c2c7dGNuKkRAcU1ARXJzZlEhPGJhOXZWCnopP0Z+YUpp
OTxJJCFgaXMzQGdnKDxifC1wbSNHZ0tEZiVNQ0ojUCpYa09oKHhha0cpTmE8eSNTbjwtKmtAZjBr
cwp6VV4yK1MmQ3JpM2NzZnJIQHg2K1dCN1EjY2VrNk9ONWB3Tmd5N09nPjh9TDIlR1ZXKWJlc1RP
RmNBdnUhTTZRMSYKejFEYTlTcTA4PF9Jd0pvQnFMLT4rKExzLTBJWDRAcHB3aUx4aG8kI1ZYejtH
ODBRajVDWE1FMmxGXklpfEtVJT89CnpmZW1rbnMmUjJuSFJ+RCQkeChlNmFgOEUhRW5PbDFgb248
ZkMtZVp9NThsU3IhUjtpeCF0aUFoMWYqQiZ6UjIhXwp6PHY/VGEpfDNqZCE7VXw5TGs7cUJnPUFe
JVheWTQkd1pHWHVrKEVNLVNrI008MjlVUTVZSXslKFpPLT1QZVIkSXoKeiRFZklPLTBWfj1NejEp
Nk9QezdlKVE4Y3JiXmd7TzBWKjEqeUVHSGNsWDhZPWooT3dZdXkjS0B5K2wmLSReSlc8CnpjN1po
X0t1KjN1UEpjemwlMW58WkB8eTM0UTNDNjg3ZXY/SWJUOComPVFQN2xhcTJzWXdeeilocFU/UTtx
azdQJAp6WDc5JEI4ZjVkUUwoNyNWNTl5TiRocDV9MTwoJTI2YjU+QFIlOU5YKm5maE5OclFPJi07
UTJNeXVkR01CYEo7OFkKek5YREY2cSNuO35LI3hiP3tZYVdJLV5JNnJaOCFtPzdJRl85WkJOZmxG
V1gxKUBQSklsY0lYMHNoTyN1WVVQTDQtCno4fGUpSCRmPjg4XnY2RjAkLVVANkhUN0Atd0d1UyF1
P3t4SU9BKmIkIz1hbz5wYF5PIW8ldnx1TTtxQStBOzJYNAp6YiZ4PnNTSSFuWnRpRGQ1eGU3PVUk
enpsZ2lAQXMlez81KlI3LSNlOWhrRWRpPT1aQ29LZVhVcHBMfTM5aiFOe1IKens4VFhkR2ZPYnEx
b0srPmljNFAtbXBWXigranF1PG0zYzRQbH5PYH5VRkd3YlpLRTh4NHxnU0padz1DMGRReHsqCnp4
NjlHUF5mOGU8VW1TMWVpVkpkYk5BaVMqZlpYLSEqYG1GVkt8VV8hcjhVVTtVQld4b3dxfE9hZ2R9
KmktY0NPaAp6dFJLVzdZajt8Mj4zc0BfI3swfkZqbm9DVlMtOFBTJGdsbyRUYnhBfiU1N3R3SWZX
JXtCcll4PylHKktjJXV7LWcKem9jZEVaK1JuTFdCTXRJXjc5M19tWk1mMTBjSiNCQlUrQDVBTCNH
WSVqRkBDfE01Vj1OPCVNbj8ycFJoTXBHZWhHCnpEfnJ0NG50V1F+NyRnKTJpQWVKMylERWRnZlJF
MW5AR2dNMWxkeT5FallXM1FKPk82VmNSNEBCJCFsNlE0Zl4tJgp6NUtYJGtKI2dxalkpayRmY3M4
RSpWIz1IcWVqMG9kQDlPVE1UKjN1KkY8RCt3Vj59WTZGcS07dHkqOVB8WThOKE8KejdxQDBWKWlo
UTNNLUEwTDhSQT4+JlhgekxpI25gKiV4SHpJJGxgM31PU0VDRUI5b3FTRiYxMWBeZUYpU181PG9E
Cnp6ZH1vQXlJPG1sZFYkM25ufG05d3YxQTIqUntEUkJoNnRGPzs+O1RJOGJoPGo4akdmV1czUHZU
Z2d4WCpqV3g8ewp6ZHFkPWltJHZtJkxDe0Q1PExTfFJkXlo4QVl9eENkYjZ0R1ZJfSE0M0xSNUIy
UXNAV2M0WSo8TiE2QjlRbzdfNHsKenl8TERlMHlYSzJkcGcpP2NHa1FodmlBUEktPWkoTiRKRmVO
XiNOdEwlSkhFMVl0dGMwYk8lPioqeyMwT3EjdHYpCnojbTBxITZ4T3BhU2xjIXh0MyZoPlVmNUs9
V197Wjg/UTIjdXJvemhGSUtBclp8R289QXQ3SUltZnkoPi1eUigmVQp6KzllYFRpdF9paVp8V15f
ayVAUXNuRzUwSlJXX2MlKkIoVV9UJnpTUmBVZD9BYXg1JkpYc094NUM5N2RkbihzT3wKejxmb3sm
aFpJR1d1STNubGczX0l2SjtOek4rRE4mSSVsMGEoI2N0I28jPm1gaTFKP2FYRk9ofntCIXxrK2Up
NV9VCnolWDFpbUMqelZ8MSpsO0V0Y1Fld1RFT3JxNzRhdEFofjs3VmVWTF9oYik+fFh2YDdCZ0BN
bn1zalR7akVQb3AyQwp6SV8kTzhAKSh7dT43NlFfKFJlYk5wSFNaPnxHKkViNSNye0JJX1hqcGlW
QWpUaH0mWkQpM244fWw0UzcrZCo9I1MKekF2JllVR3JFdmgkIV9iYldxWE5CRWItcT84JkJlUUIm
UndWQUJCN2RSZkk0XipjQTYxPD4+OFQ8bUduSyRBU3lBCnphPTNAUVVQX3xiSng4SmdHT0R0azZf
PDZgeyFQSVY5ajBlIWYwc2IjYHFaNk95S1Y3b2EyX1QlLW14Mm80cFdTUQp6dGhqPmZve2xVcm5Q
NWRgZykqPXkxWklEUyVfNGt5VllKQVNncl4pO0BgR3sxbHJ7NW1kIW9sej1QSmB9O3J2c1cKem5Z
d0s9czxtUlN3WTUoa1MjVigpcDRyd203Tkd9MnlxX3ZOans5LTxwK0poQ19sYnFsd292KmtiZCk5
PE53IWA4CnpwejhoIUhQS2EtLXRAYWYqTCEyNih7Tkh4TV8lVSEpUGYxRnsjWnBzVSlMfjhLVSMm
dWxkbl8tTjlHJjlOTGBVeAp6Y1N7eUl0TmVuTEk8ZVE1eDw2Z3dgfnJqJG9XMWQ7N1MpUkdSQmxX
fnhWano5OTxeJSUkUXteP3hCYiM9KmkjcSUKeilYSjV8KEV7R1RKI3pMdUpHYX0yMHFtYk9yc0J8
TGpmVlE7aGtZUmBReFpAQj4tP28jT3d7aEBYeyM0I191Jl5uCnpmNndJY1YjMnBQYGc2MEhzVFJW
N0NpcSlVYFBJNnBYSzZufUhyTUMwZCFSd3tsX216aDlraXcoWnpRa2FuYU1seQp6a3kyRFpVUG1N
Vkl9PFRgeElAUnJSeTItT1AxMFlDREdaPTQkIVFDPHlZaWA+KDhqe05gUkhKelV+Yzdge3luX2MK
elNHNzY+I3coWlEtcEJ7VyU2NVBjMClPMiQ2WmNFKTZzME9aXnppQFhvKn5NQ2I1UTUtO29CMSsm
P1hGK2dkTGZwCnpFeXc8OGhZJXlzJXBvbkBiY31DKCFnZ0RtQkQmekJENDhmNl99Q2JeaWEza0V7
eHxZTkJBRmoxU3Y+e1EtOG5YWAp6WUYjYTt4e0RlPV99V0x+K3RnaX4wc2pjVjNYISVrMTFwSGgm
fDZFY0pwNURIQ2tocHV4X01lNk1hYjAjKjR0ZD0Kenh0Z2Z3WEAkM3tGP1U9bWctMHtqe0R7XihN
TypyVHFlTjxaQFVjSyYrb2AjRllBQHpyKHZRKWshUClGcEhHflZQCnpWfEVHeSp2TGgkY3hRYy1R
Sn5QP3oydVYwMn5TO2t6QWRmfCpvR0N8dGp5eX04MnFgMjRFMURNJUQrdFMqY2c+Jgp6Xmh7aTRM
RkRne080b2pxZTNrRWNjOV49fm1BSnRZQ24/QVRYSGA3NCQyPyklVHF2UmEzSnomc0AkQXAkX1Bw
UTcKek4yIWxuXkhKKSYzcjw8U2dNPCRJSW98WH0kX1hjYkQ4NWJ+QlJQeThOLT9YP2AtK2kwSStM
JGBPazxWK3QmcXpZCnpFUXlRJVhXOy19OzNhOGlqRDFoWCM9KzhSY1R0OU90a31gYExSKHk2IyUz
KF5WeHF8ZV5MUjJ9NipgP2RwX2tIOwp6diNIb18rcmFGemc8Xztge0ozc3piWEY8YUU1YTZQMnRw
KjQwZVJ0WUhGS31kOzBFa2xOKTUkJUJIUH1fcnR1by0Kem9fWWFSM3FBbGZZWG8qNHdrNnQ1O1Jv
K3NBMVg1KXheJlFOZT56JXJSUV89bk5RMzR6YCpWYWg2VDUwN0d3bX5mCnpTRHhlQTs3eit4dFpZ
P1lUeDlJalp3Nj04QHAjX2NEYkdWTXpDNHJZYn1mSjVkPXV8Mj9VIVFpdn0tXlFEKX0/Zwp6YjxU
XnBlWTxnMUJKazYzNEFZV2RyZWBzWShgPXZvWmlaJUZQZXhCPGhmUWo4eitWRllwRVpLeWdkNCRB
NyNCckcKelNgeyFrYGRxbk1ST3NsbmsrR25SeTRSQjN1MVM7OVVkZV5ZMiQ5SDBtalBPcUZ1RkM1
QHN+Y15PK0BGQ09ZOzYmCnpKLXBnVCNlQDI5X0ZyKXRQPX53V1YmM0w2WWIyKVY2aSZiQz5VcD5Y
MTdMKGNTZiFxTnUpfSNnKSZjQGp5OEMldAp6VH02I0RxakVJRVd+U0t1ZHNkTllQdSg2I0NFdFhI
RW96e2hDNldCXz45YEpNempqPnhRKWFPSGxMRT0yUXtNdysKeiRFQnQpYFlfNGlnZUVRe1ZffEpB
KERROWZWbT4rWFZxUTlSPkBlUDV3ZVR7UHE2TipQJXFnU0g7P0ZfYCo3KTZWCnoxO0JtQiUyPG9t
WkhKMnV5ekg1RS1WSVFPWDlfZ0F2OVpCKkQqYm5GWlpTc30lbnMzRHRJUnA3Nj53JGxVYlRhTwp6
K3N4PyskWEFjUTdUR0RuYm42PlpVKUU5ajNtcW1eaVJoMXcmfFFSZC1sPVpRNjk5WnI2PjNEKXVT
WXJpQCY2aiYKemQjMT43Tkh0V3AhXkMoWmszKVllNiN1aG9kNFQyVmN9PWF8P3NZY2BvcDtxVTQ+
dTVMZjwoeTRld2pKWD9+SmM8CnozP2d5STFqVGdPbnArdCt1QSFjYXsySGhoeGleK1VlT0FGaStQ
JlFaeHImPUlCX1NoT0xQK1prPG5SbEQ9el54NAp6RjZiIWlCUWx8MSh5Izh8RH4wKD9rYVowZUgy
YzlyYH1BZ29eMnFLbGYkcHNAbnA2NFYrTCRXamZLbThJVzdCSigKenI+MTc9PlJLc2slJXtqaGxh
QEt0S0RNeyVFbUw9PkRWdCV1RT9SaF9gbWVsVj18fjN0ZyN6MWMlYDlhQHY5Vz0qCnpZcCFEbnBP
R3BsO1N+YkU+cVNGano1cmZzcmoyQV92e2k8UjkrRTV6X2ohS0otMTs7MmNZSXIreXxTIWN1ZzU+
Sgp6cU4mPkdXfjcqY0Aqa0FUNzNqSkx0fFRKYVY2OCpKPDw3UmJwbmw/NFI0cEM2RXQpOUBaUGFl
RDVlSHEqVVdlZT8KejllN2ZmeWZreERZNEpCfmpvYCZlTzRvT1FDYnJWdjwtQjErdz93UFhpUT10
Sng7PGRVNStlfWAlTCtWV2dGJkw4CnpvZkc0dThAeFZLajdfJTN8TlEpXzZBRl44U3lmU0dSOGVZ
diRVek5CaEM3dWBod0xrN3U1YHkzX0Ngez5xNU0+Qgp6b3tzSXtld2dJMnU4S0l3b3ckb35yRDg/
ZS0wbWRuIzRUV2s2bTBhb1Z+c1opd1VnYjhMZSMqTzJidDNRSWtLcHsKeilJIVFgJUlubTt5KFdl
IT5uQ1VRUGx7MDZnSD58alJxeUxaNlVuaUJHK3kyNWUkZ3RpamN0amBZPjB9Vlg4NmZZCnpAKlFi
cEBmVm1PWGEoO35jQyFjZHFVaFV9cj1aUXQlYkFyY14qQkVQVVhIcyR7flVoMyszOFlOZS1Yckha
IyZydgp6TVNwc2NEYXQjfnhQTUZqOU07TndWY2d0YWhmUTMqV0FgPmtTMlg4ZjlyTUd2ZXhaRX5a
Y318UjZacUJKNGl9VXcKemFkX1Jibl9yYGZRfWJWOVNELVMraFNYPE12ZWt9Q1FXWUUmIXh1SmtR
RzNRYlpGSnlaMU0+NmJ0cEdTKGp6JTF1CnpQT0NPamI3TWFydXt7RjkxS0tKMGQzTkRhNkpKTkxR
Un5Ob3ojKkUoIUk0YjFkcm4le0NoJFk/Q2s2I1Y2JmoxSgp6QkNgRHpXZGFOdjdrSTlWQEk2czwt
MjBlRnFVT25MaEUoYDduKTExVDwoYGZUeGIrZ0pJLSY1P0htbTltXkt+UU0Kei18MytUQmY+O0VH
ajUkSWtBakh9d1pScDJmUSQxQj5IdnN0ZEI7UmhAOStmP0QrezFAbXlqLW5Jcz19TTUkJHB2CnpL
VHU+NEFyUWAhK35vQUIzSzclIU9tX05lZDZgMkdiKG97Uy09PHNGRUVkfGBuYHMrcyh2NjBweG96
RlFtKjglSgp6PmxuOU05RCk8ejlMfEYkem1USnotIy0+Q1NAajFRR0JQXmVAa1h4OUY+VXt+bmhN
I3p5N09TV2QpPnBfX1o+U3MKekphJkJKZS01NUUtcH4wfk1qaTtTbEUjUnY5SThKJW9nRldzV2NN
WmQhZG4lV29DMjVkc1c/dUtBXyhncVRERlokCnpXTn50SUBVWmlgaiRZNUwoflFVRTl7ZTsyPFEj
OSZ0OypjLU1WUTNEVU82cnd1JiNLSng1Pkt9MSQzQkhSR3tZbgp6ajE3ViZkQ2NnUE9RaU9QREck
IzZ4YmFYNFU9JnsmZTVzWEY5XzlraD9OWjFKKW5aMVRFZ34pNHNmYHwmTCNPVS0KejRBOzRZXlMm
MilWQ25vMmEhKGhjK19MNmo4fXZoY2psa1htKUAmJF49VT9AYU1OeGU7IXJuZzlwY3FxU3RDKj53
Cno9NDZUWTdvMktCRyhjOUtzSUI/KUJ2aGdBJk51cz8pdypBQktObGRScV45WU5ybD5ZWHRLYFRx
MWxMPj91SX4wfAp6KSZ+bXFuN3wpM3NlX0RHRXYzVntydn0oZkNHJThLJGBGbFhsdChgT0omX1lX
ZTg/QVk2Tj88PzdPISpWTGFpcUcKelUyfHFVS0RacXp0WVo2MWBGc2haM3FIazFmQlkmfmhPPFA1
elNjb1lKKD9kdkk3Mz0rT318TzFNQHtFa2NVSFkpCnorKVVBYzZYa2xNd1FgaVFkY0E4aHkxPDFp
NDw7b0EhVk81aSM+aTEpemlmKTk/JSYlWmNtano5d053RihFc3VoIQp6Wkg+NjswPXNJSjc1Mz0y
JUdKMmEpZSVOY18kZjRUe0lqeHtrVUtCbjY1MH44cFQ1X3t6Q2JmOUIxYFl6VnFDT1MKemtzMz88
bjlFM2BXbHh1eyU5VDEmT2VWZW5AfnFGZyNeSClQTyZ2SiN2ZTQwM0lxRXReSW03IW5FZ3oqI2FV
Yy0jCnopbXt2Xi0rTlVZenhvWCo9KWQ+PkI9RGFFeyhtRVopcVZeX3tLQFZhY0hnaEBrcTkzfVJE
Tn4hY3FmJWNfVW9iRQp6TT0hTkJqRVdXKT9AUUNZc2pSNTdUV1leRVJUV3FkP1hyKzVybzRUOSp+
XzBuSzFOUHohRFhWZTBvITApZD4rKXkKeiZ7ZjlqPkUpRztKfDc5WnRnbysrbFZiP3VTXkQoKChN
dVdZR3wjSGAmdzI2bGs1ISRXPC0oKD4pWkU9O3k+X09HCnp2YXsoUUhHOD9iczxQYD8xLX1uKHko
ZGopNilYZSF2YSk7ZlI9WCkydmI4Z1JpNTZ7SytEM0oqKkVhaj9sQVpSaAp6aTYtcj4hMyVSb1dr
dHs1N3pOTHdEZHNzWkdOKE5+SmwwRCk5Kj98aEs4LV4tPiF1O3JqP287IVMmSG1VUXFhVDQKem0q
fmYqP1I9O3twRTs3K2lASHM4IyR9eGViYVomP1hSVVF3OU9CPi1vaXZaQXBHV1UjSUV+RUNXKyl9
YCotYnxGCno5RXVUKFcjU1BLU3FQKGViY2B+aGdPKnpwZ1p0bFZJOH1SWVlCd0dheU5SNXZpUEBl
Z2ElNzxlWGFia2oqby1UbAp6V31OSnRPekMpRE14ekdTWWF3QV9sSjcmSjAoWV5HMlAwTms0cjdQ
fG0lbzhKcHJ4Z3lBSWc4T0FtYCVIOGk7Q00KeiFgSWpNT0UlU2BoeyQoPi1WMyNMWFlsJlVeQWpA
ayFzWGRRZy1QcVMqWEckZ0hafHo5TU1XN0BNTHBVZFMrQm9DCnpVNWQtMzV3Pik7S2Fyc0FJQz94
JCV3dnpaP1IpMEFJV25FWkFnYFJHZmVBUkZ4bXVaQUgocms2QE9LJjY7bXBCKwp6LTVQdz4mZWsh
bXhVLTxIJlgzS29Mey1Qd14rUCt+PWxJcnpLe25ARlg9MEp7dWZ+MlNELX5pR3hvVWZpNlB3QSEK
ejspfjdhRUcjX2t0RUBeMSFnfWgrdWdoYz9EK2tZP0tPZ3BQek1PczFkP2FHaEJ3TzlFMHQ7UDk1
JU5hSCV3TmJECnpSNV8/RSNrNUFxe0xhclc5UFVrY1MhcHc1WDVfY1doIS12elpyKzBebnlQWiN7
OH5MPFl1YH5LI3ZHeW5RZ2JTUQp6JU4zVD5pNDw9T3dFSylfaGYmOSR2MkdvY0Y+NnRidD5hd1Ql
S0tAdHF3dFF5SGpaR21hZDAwbEBSVEhOX31lcCQKekdDPnAzQkU1M2B3OX5CfG1FK1AjanltMT4l
WUpWeTRHazd+QWphclQ7JUtxI2x6T2p9QlR3c3IjNEpxSFQyPClFCno8OzRvZUtUNCYjVFgmfH00
SzlBdDlCLSZCQURub01NRGZ7OWpwaldIOyg0Wld6SVNzTGxYNGJAcmh4UD0taEU+Rgp6YSplfmRG
blpwMXlrJWJfXyN8QGZxUTUkZzgtQSg+JWohdDtGXm8zfXsxOX1vP3AhOWFgdGs2YmE5fWdBSSM/
QUoKekMmKTdmdzNtWU5TXkp2bS0tX256KzwxK1JzV2F+JjNTM1kkO2VUVXpobTxIQko9alhUVkx5
TC14X2d+fmF9bkdQCno+SSpvSE9eZk1TZmlpNFFIPi1GRG9TUjJUKE10dmVAbHpxRnk9VXtyRlBh
MW09KWMoNUJNSzJjRVpWbk9pUDJLfgp6a0YweUNlOXBISDJBPEpHUT5OVyVTcUIkUGRBVGw9QGRa
JmM/Z1RJdDdRcl8qSGtMQUV8OFJmJG5ENGU5bldkMnQKel9HX3cheDtuSlQ3NGpLMG5vYTQpNEZr
dG9tSm42aUF9N25TelI2YUg1cEJebFF3TjdlXlAzKTEpNj5eISglZ0BQCnptdE52cmw+fVI0dTBR
VkFGRXh8YTU1TWpAbmtnU2tLKkx3Zk99cnQlcVNHazI+K3xkVSF8OSpkJWZnPkBYP3Y1OQp6JnFV
eDNRKWcrIXs7ZD1xP3slezduRmArI1ROVCgyLSYoSCNVaTVnT1FQUHBhKlpjeHxrMWxDNFZ6Mz0z
TVlRbiMKeiRETzdGciNNKFAoWmpqR0BtYXJkcH04ekUoRyV2eiEobTFKNlFsd0ZCQDReZHNsPiE1
bSNHUiZ2OT4wMXF+ZlJHCnpAWkpHNHVHM1dIRmNNdGU5eCYhTmteTXA/eTZxSnp7YGIyR2xjWD12
N2pVfmZvbllzKDZnUllgckF8ekVAQXp4Iwp6Ry01NzB4YjdoQnVtdmtkYVYjKThLRThRRzlIM2Vx
e1AhSkhlTyVtc3lLPWxARzRBMiVRbWpnVFpFYVdRT20qV0wKej89MHs3e2QrbVhCUDdGemRMdk4q
I3Q+IyVBYUt8N3hiY3hqNk8oanVLS0x0T3IqLUJDRWxvfEVxciVDJGpXOXxyCnpaRWZDPzN5eHJI
MGojbWNwfGNvIV8pPXhfR3w2ZEhyK0h0Q08lVDw8N3Rydj1ARXRgdiZ3NHdoYG4yJUhwUVNwQwp6
IVRqaDItcjM4YHd+KV9ycHV9VHRQfnxpPkdIfndNSVVPI00mYDdCMldecFgrRjllaHY/VkdkRyls
ZF5xZCRHfFUKem9zQikrPFNRS1N0RFkmV2J6ZW9jUSN1WGVNLUdmOTMlSVglSndFRnduJStrQUB5
IS15I2p9cVFUPCpRPUZyPVV9CnpWbGZIU0R1KEx8V0lBUkgqfGV0LXY8IWslIWs0MT81QG5OUzN9
dzRYYno+djtgXnRyVEQ1dTlLREc3VE1sWj94WQp6SGpjeVRkNjllenU3b31OQjc8aC1PKzt9bCEl
Mlc+VSRUSldUOGNsTS1NfXdfR3tydl5NMk81JDUhJkZSbUkwNXAKekYmKFEwV190anpIQmNlVy1A
eEZOLWIqfUByZHRSLTJvQ2VaVz1vWHNrTGpSZSkzRDNtSnctJUI/M19gOTIqOyRjCno1ZlpLb2Yh
MmkqTTQ/XzBrRz1NMDJsMlVYRVZJJXU5fHtZYl5Ie2hxcFZ3S3BgOSVvKk5oTnNyYzx1VnYkNSRw
QAp6VHheaXpQTEBwKys/VWkqYENXT3JCXjJ3bzdfR0FHOEQ+PVB5KHhrVWpLMGBpTkFXbiVPK3F2
NjtrN2JYSTEqa3QKemUhSGRmbXVDcnRRZzUkJj0pa0FucShON0Q/eChRd0pCPzNtV35WNUVWMVdg
dFVgSSR+cU9rSXs3S1c9aygjJmFvCnpjN0kpXmVjTEdLKnVyQmhGRTBXK1NqaDxSbT8hVkkqbnM/
Kng2Rz1+dUU9TDRFXzd1ZTA2RnB+V295VFVlO0lTOAp6XmQqY1dIIW59YnM8eEk8aD5RO1pEYDs0
bXpNTVpEY1lZb3RDa0poaHFSZT81ZkZhbUYyQEMzaG5SNU8oeUYzVU4KelQteiF5PWxSSyY7QGJZ
bU8+cEZsOT9peCNFND1IMk5man15emc9PDx1Iz0jcDRJZDRoS2YjMnF1Jl81dkgyV1MwCnpeTFky
cVhvd0RNY3B6Y2JHZTR+X19DTGQkY1RPRm1aSDNZciZQZT1EXkt2e2w0VihwNTY/VH55ejNTMDxE
Z287OAp6WT5mYDR2bC0yMmojYVlQekRvWXs7WWU3NkpuYGplYFY7NSo7bythcjBqIU9MI3pCezJP
fm54cjNmUUlYWURNVTMKelREaUUyPXBKeT97VHshYWxlRyU+SDZxfXcmJmhBKyE+aENqUzIrZSg7
Kkg+XnJ3Yi1pMyYxVyU4X0w1amh9dyQtCnomQDU5bXdqKDhDQ149NXxfUz1DZHE0XlFNQ2E+YURs
Y05VaHJhSlpNWUcpbUxnQ3l2dV9lZG50MTJJJFhhUjkpJgp6YGBhX1RmJDIqQj5Xal5iJDUhWFEm
YzIlbDtVMFVWTDZwMnNnQ1p0cGNJfDF6UzNQaj9GSnEmbE8kIyRnOFVqQU0KenJjLUozMzlwZmdD
TVEzdTlPcHMlc2RyNk5UYmxgZHItcVR0STJYS3B5NFR2NVQoU0UpIzYqUytGTzhOYyt3QjhkCnpr
RG9ZOzlWNTZpNS1qIWJxVGxAcmZqNkV+ODJPYGxhc3VhOCokaDBVJnp2PSRlbWctfEdidy0xe1kx
aDw8bSheKQp6P2o0elUpamkjaUQzUmo9MGB4SVNeeWNNeHN+OXFEKGBqJXRQZVl8e0pCQl9TeV5h
ZGJBcVluUTBPP1IlPiRCfkoKekZWWFhQXkl9Sy1NeEpBMWItVSs7KytKR344Y3hrYG1hYno1QnJo
e2VFfDlPPCV1MT0wWnFuKnBlUGMldVlYI1oqCnowYnMrYkZFT2gtO3VnVDA9TVFlPjw+a3BJQGo4
JDBpMV9ifHEhc344dnAqZlJ3SWRmWlpmazE7KkllcHpXQ0A2PAp6MkRBSDsjenM5RD1JTD1lPjJM
YGw7STBuUUFINHRmPGhQdl47alFWJlpvOEFmcmNscGM7O0lpPDl7TUtWZnxMIVUKenBsfjNjZ2BN
aitOYUclbXJSfHkqMDVFRTlabkJhcVVVSThGMVRKUHdlN1NSdiZFTDB7VldVc1NJM3ZOamNUe0Js
CnpCQyp1PnI2KGY2eX41Xn5aKz1sOHhJVz1CYTw1MWk5ZjVHMys2e0FqN3kxS2M/Q35sNGI+aCE1
czU8KDZvbzhtUAp6ezNiQUBMe0l3elBMWXJwKDlxaHdacnp7RTd+UFJeSVh7O3w7QT1HUk8lPT1y
Y2dyUG9eTGJtU2VPS3hSKC0pPW8KenBDT25jdnxPZCNOT3BmXyRMRXhhaz01d2xpYzhQejUjPHMz
Kmk2fmBfTV5GS0ZaMmlmTyFsUDI4PWVeQTU8WHwkCnpWI2cmczU1blRqZWs2PXFedmB+ST5UX1Al
SmIqYm4zdXRiaGU9SWJCSDlxVWZRdFZ6Y3VKeUJ8aD58JkpOUnZgagp6UjFDdUd2bUM2RHNCfntl
JmhAPz01UX1GPjtDM31AK0IrTHgkK0hmUU50XlRhUHdjYVRURyZodm97eW59UXhPUCsKenVuXns/
VllIVXJrKVI/QStqKFRAZzdDIzlUbkU5Y3pTMztQO0E5fX15ZTQ0SUw+VGs+QnNwIWcqWUBUOTc1
VHpSCnolPD9iVSQ0SldIXn1UVFNxWWRrb15PcGwlTkZIazZ0dnFIWkwtUj5pPzY4LXEhTnQrek9a
RWFtWjR9b3lqejlrfQp6S3xzP0AqMXNBRmcxIXBiWCNzWGJMV2hHfTZRJVM4TFZ7ZHB6c3x9bUNX
bUw/ViVUTmRNPSQrZUoyandKOE08O34Kej1udXZlO2hvNkB0SUt+I2x6WUYpY1VaVEM7UGBJRCNs
TiZhbndATyRSaDsqNEtLd3chYj98TkRrP1lfYD8hPjZWCnpgTjBIUG5xWTJzdmZmUkR3Y0p3S205
M0hmJldSVllPITY+UjE4RHUpT2o0ekRhfChtNHFobnZmT08+QWVZUz56Twp6MmhDMShGaD1aOU95
Skdfd2A4NyEmJSUzJDhuKWFOazlnZHFzdk1fYldBPWlsTWVgI2c8cm92MS1HbWk3WmAwencKekA0
Tzx4SzdFZ3U4fmMqbnJWRTlARTZ2aWZCY0lBfEh7Q3lBOzh6QXdtenNJPmo9elhZXlEjMC1ydlB+
NGUmWCMlCnpUbnlFN3A4aG1HJWp3Qkp6c2NOWmN9IUcqLWs9dWVGUDhRejMqZGR3bF4oWXhONF4h
OWtXPGZaOXBuRE5edyFoVwp6I0g7Qy0/UC1+bEhjaWM5LWtJQWlSUklVbCNSRGFuYVlgWS0qR0dA
YmY+KWF4Tj5DNX1oVnZ4I3ZISk1GbklkeE4KelMjT25QbVBhJlV5XmR6Uj1hYz4wXiZXQSVuMDkj
KzFYS3lVI290MDQmeSZZRHBDR0V3cVVLJENSTFZSfiVDXktUCnpFKTlLLWQ9dShUamV8VCE/Z2FM
JWFSa15GUzUtUzw+Jn1sP0ZPaVh7SkU9UzhiOCtMIzZSdH1LciVCRWg9UitNOQp6dD9oU2VtKTUr
fGpuKWVWOTJvNChARyFLOHFscTw9bCV0PjY9e1VOeypWcT51Y2FBbSo1Kmk4S3tNTEpsTzApajYK
ejh4dUdeOXFUPjVaT0gzKHlqIVNTT0JYR013UDFTZTluZGQ7LTJ3e2VFaWBROGlpfCghSXZ7MjU5
QTQ9O0xMVDZ6CnpJcFB2ZDYhcVZzLTB2a0VJSEhgTjc+aT5OSVFzNTc9eytCS3VwUyM3PVlhYSk+
K1VWXmxpVH1PZ0pFRXMpKn5UNQp6MmprI19zS1ApQCU1NiRQKV80O1MrdGllXmZIezNNZl8qY1o7
c3NzIVhGK315RzBiWmpEc0hwKitJanMtdF8pJSEKekl7RCRMSXUmVDl3KmlVPFZgK348Rm0jQyky
P2F8WjlVWkwtJjBvZzlyVkBNN3BfMlM5Vnx4MGZgUDU7cnUlJTNACnomdVFMXy19cEE7SmtJVlVY
bWAhfVM8ZWRqeypAI1AzRHpfKUZvMFNGVDNkRz1AakFAWl5sWnZ4I0szcHB4NWFHTQp6QCoycmpg
fSY/XzVjTzlTQ25zeURxezVVP2pAez1VMjtFUnZfdTwpKmx5cGJRU08mNSo/PkZxQ3NOWD5jLWkx
YzcKejM+IWgwaUZ4LTM/I3dTVzEoWCFsPWhRbkZQQ0JmUEBmcjZOSTUpczcpPjF5YG43Q1NJMmQq
cVA5M3A9PTlKTyF5CnpiN2c2cktwK0k+U058YC0qLSs+Slo3QlgkOUdpaWNhWGA+dDkwQ2pUQHBo
QilxaGRhdi1NPk5SbDN9O3kyZU1PTQp6alhMblVxcDs7SyZxQnwqUElyZUF4RUVAQXprQXNjaTUt
QGx3fFpZYkdwTzFUcmJEK1RJZHcpcHUzTmB1en5IKHQKenUoS29qPjlke3Q9ZVpmdihjTkZEZ358
ZmpCMUhQak9ZT35mPk0lUjYmc1gxNWQwTiFCO0NkfXd4ZSUqZjZMKzgwCnpPQVJJXl81fG5PSEdC
MDlxSU00YypMVjBoMyZzbTRFZ09ieEVaVnZzQ0xIXz9eaiQ5djl8Xk1YKlQ+aUBidEhhaQp6c1A9
V3dSPSlVc1MofW9ZbiVXekRrYD5fRUpeRVJ8JSVnY18rcX5WWEpHMEM4JXwreTdnUVl0KCg9JT1N
bDE8UUoKel9iWT11cz48PjRuTEJQOEBmVXpeSlFhPk0lSE8jdj1ZNmNMdHpuSW8hcF9ZSCVFc1VN
X15lLXh2NTYlND9KdkdQCnpuSC11KEVqNGR2PmEjTDdJYjNDKW5qN3VYREVCem8/QGhUaGxabTJB
Q303OD9jc1ErWilxbGx+I14kVTVDQDhudAp6YHt9VD8pQlNPdykmMmE+KHJ+R2xRV2FfPGxfQkF2
Qzl3QUp4OGt0eCNSdVE+Sm0mSiFkWTBCT3FQezxTQnhSTzgKekZrdnhnQytNPVpfazY8OTMpeGti
OzxKbnlrK1pwYGspVCo2c2AkdSQ1aXlYeTUyUnB2azwtO1o+fiMjMSpOTTliCno1N3g1SHctWFBL
b08maStuN2klT2wzN2t5SVZMcGtFe1JPaTlHYD1gMlRvQnlCMjdXKUB6Vz9WS3AhXmlXKTU5bQp6
Nj57bz42JlZ+JWxObHpudXM1O0Ztd0RQZEoyZnJrcjF8KGBYMXJDRCNYUE94YnoyNFVRMTdgd3pX
S3xjPUEzSHAKendZK0JSNSNATEF0PEs+MTRoRzxfWDdOSmdrQTMkYHhzIyVqLVA8UHh3IWI5PUVg
ZTtuQ2p+UHppPldLOVg5PlA2CnpwNnwqY0dsc0lUKkgpbHpqMiYlSHpqUilCSkw1WjA9LX10OUZA
Rzh2JikjTDUpNyRBZWV0fDUjQ3RzR0lLfGc9Qwp6KDJTbi15cztZIWQtZClKYnhCSmVxR0l+RDE8
VTFqb0NgdlEkZm5AOV4peGZUQmA+aFo2R1IkVGByP0ZPelY5YnYKenIyRzE+YTBhJW4jN2dAIWtz
TGJeQXwzP3x6SXI1VjxIR0Nabk4/NzRVK3FwciZQaHVVTyUpZS1XVUooQGZ9dDVkCno4KjQlfVow
XnBZSF9KUlhRJkg/eCFaeGE1Y2NAfERrQjhJNXAhY25OZT4xM2w7Zmh1azhUZ215bn4md0I9MWUq
cQp6JjJDbzxNYWU5Z1E/dUR8UXxLS1dPK3tEc3JKVClPLXJUTSlfdzlpPiUkMlFTQHMyfHhYSyl9
OTBANjNtbjwpU2oKek9yT1BnQlZudlohUHQtaWEybz1tK1dTbGI1QEg1MnRSTFQ3YTNOMmJOKzZK
a28yPnMwe1U/ZTRZfnVnUnU1aT4wClhiKk5OU1ZTK3huWUx2LUtEQCh5OE95Qi1yc1p+dFQKCmxp
dGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvdmliZW1pcy5zdmcgYi9h
cHAvcmVzL3ZpYmVtaXMuc3ZnCmluZGV4IGMzZjNjODEuLjcxMTVjMzMgMTAwNjQ0Ci0tLSBhL2Fw
cC9yZXMvdmliZW1pcy5zdmcKKysrIGIvYXBwL3Jlcy92aWJlbWlzLnN2ZwpAQCAtMSwxOSArMSw3
IEBACi08P3htbCB2ZXJzaW9uPSIxLjAiIGVuY29kaW5nPSJVVEYtOCIgc3RhbmRhbG9uZT0ibm8i
Pz4KLTwhLS0gVmliZW1pcyBicmFuZCBtYXJrOiBhIGN1dC1nZW0gZGlhbW9uZCBjcmFkbGluZyBh
IHBsYXkgdHJpYW5nbGUuCi0gICAgIERyYXduIGZyb20gdGhlIGRlc2lnbi1raXQgdG9rZW5zIChk
b2NzL2Rlc2lnbi9yZWRlc2lnbi9sb2dvL1JFQURNRS5tZCk6Ci0gICAgIGRpYW1vbmQgaGFsZi1k
aWFnb25hbCB+MzclIG9mIHRoZSBib3gsIHN0cm9rZSB+Ny44JSBvZiB0aGUgYm94LCBmaWxsZWQK
LSAgICAgcGxheSB0cmlhbmdsZSB+MzAlIHRhbGwgY2VudGVyZWQgaW5zaWRlLCBhY2NlbnQgZ3Jh
ZGllbnQKLSAgICAgIzZBRERFNyAtPiAjMkZDNkQwLiBUaGUgc29mdCBnbG93IGlzIG9taXR0ZWQg
c28gdGhlIG1hcmsgc3RheXMgY3Jpc3AgYXQKLSAgICAgdGhlIHNtYWxsIHNpemVzIHRoaXMgU1ZH
IGlzIHJhc3Rlcml6ZWQgYXQgKFNETCBzdHJlYW0td2luZG93IGljb24pLiAtLT4KLTxzdmcgeG1s
bnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB2aWV3Qm94PSIwIDAgMjU2IDI1NiIgd2lk
dGg9IjI1NiIgaGVpZ2h0PSIyNTYiPgotICA8ZGVmcz4KLSAgICA8bGluZWFyR3JhZGllbnQgaWQ9
InZiQWNjZW50IiB4MT0iMCIgeTE9IjAiIHgyPSIxIiB5Mj0iMSI+Ci0gICAgICA8c3RvcCBvZmZz
ZXQ9IjAiIHN0b3AtY29sb3I9IiM2QURERTciLz4KLSAgICAgIDxzdG9wIG9mZnNldD0iMSIgc3Rv
cC1jb2xvcj0iIzJGQzZEMCIvPgotICAgIDwvbGluZWFyR3JhZGllbnQ+Ci0gIDwvZGVmcz4KLSAg
PHBhdGggZD0iTSAxMjggMzMuMyBMIDIyMi43IDEyOCBMIDEyOCAyMjIuNyBMIDMzLjMgMTI4IFoi
IGZpbGw9Im5vbmUiCi0gICAgICAgIHN0cm9rZT0idXJsKCN2YkFjY2VudCkiIHN0cm9rZS13aWR0
aD0iMjAiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KLSAgPHBhdGggZD0iTSAxMDcgOTIuNiBM
IDEwNyAxNjMuNCBMIDE2OCAxMjggWiIgZmlsbD0idXJsKCN2YkFjY2VudCkiCi0gICAgICAgIHN0
cm9rZT0idXJsKCN2YkFjY2VudCkiIHN0cm9rZS13aWR0aD0iMTIiIHN0cm9rZS1saW5lam9pbj0i
cm91bmQiLz4KKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0i
NTEyIiBoZWlnaHQ9IjUxMiIgdmlld0JveD0iMCAwIDUxMiA1MTIiPgorPGRlZnM+PGxpbmVhckdy
YWRpZW50IGlkPSJyaW0iIHgxPSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj48c3RvcCBzdG9wLWNv
bG9yPSIjZmY3NThiIi8+PHN0b3Agb2Zmc2V0PSIuNDgiIHN0b3AtY29sb3I9IiNkYzM2NTgiLz48
c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiM2MzE1MmIiLz48L2xpbmVhckdyYWRpZW50Pjxs
aW5lYXJHcmFkaWVudCBpZD0iZ2xhc3MiIHgxPSIwIiB5MT0iMCIgeDI9IjAiIHkyPSIxIj48c3Rv
cCBzdG9wLWNvbG9yPSIjMjAxNTFjIi8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjMDgw
ODBiIi8+PC9saW5lYXJHcmFkaWVudD48L2RlZnM+Cis8cmVjdCB4PSIxMiIgeT0iMTIiIHdpZHRo
PSI0ODgiIGhlaWdodD0iNDg4IiByeD0iMTEwIiBmaWxsPSJ1cmwoI2dsYXNzKSIgc3Ryb2tlPSIj
ZmZmZmZmIiBzdHJva2Utb3BhY2l0eT0iLjEzIiBzdHJva2Utd2lkdGg9IjIiLz4KKzxjaXJjbGUg
Y3g9IjI1NiIgY3k9IjI1NiIgcj0iMTQ0IiBmaWxsPSJ1cmwoI3JpbSkiLz4KKzxjaXJjbGUgY3g9
IjI2OCIgY3k9IjI0OSIgcj0iMTM2IiBmaWxsPSIjMDgwODBiIi8+Cis8cGF0aCBkPSJNMTUxIDE2
MmExNDMgMTQzIDAgMCAxIDEzNS00OCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZlOGVlIiBzdHJv
a2Utb3BhY2l0eT0iLjU1IiBzdHJva2Utd2lkdGg9IjMiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIv
PgogPC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzb3VyY2VzLnFyYyBiL2FwcC9yZXNvdXJjZXMu
cXJjCmluZGV4IGI1ZDRlZTcuLjA4YmRmMmIgMTAwNjQ0Ci0tLSBhL2FwcC9yZXNvdXJjZXMucXJj
CisrKyBiL2FwcC9yZXNvdXJjZXMucXJjCkBAIC0xLDEzICsxLDIzIEBACiA8UkNDPgogICAgIDxx
cmVzb3VyY2UgcHJlZml4PSIvIj4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJl
bWlzX3AucG5nIj5yZXMvc3RlYW0vdmliZW1pc19wLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUg
YWxpYXM9InJlcy9zdGVhbS92aWJlbWlzLnBuZyI+cmVzL3N0ZWFtL3ZpYmVtaXMucG5nPC9maWxl
PgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfaGVyby5wbmciPnJlcy9z
dGVhbS92aWJlbWlzX2hlcm8ucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0
ZWFtL3ZpYmVtaXNfbG9nby5wbmciPnJlcy9zdGVhbS92aWJlbWlzX2xvZ28ucG5nPC9maWxlPgot
ICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfaWNvbi5wbmciPnJlcy9zdGVh
bS92aWJlbWlzX2ljb24ucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVt
aXMtbWFyay01MTIucG5nIj5yZXMvdmliZW1pcy1tYXJrLTUxMi5wbmc8L2ZpbGU+Ci0gICAgICAg
IDxmaWxlIGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTI1Ni5wbmciPnJlcy92aWJlbWlzLW1hcmst
MjU2LnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstMTI4
LnBuZyI+cmVzL3ZpYmVtaXMtbWFyay0xMjgucG5nPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkv
RWNsaXBzZUhhcmR3YXJlTW9uaXRvci5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9FY2xp
cHNlU3lzdGVtU2V0dGluZ3MucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUNv
bWJvQm94LnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2NyaW1zb24tbmV0d29yay5zdmc8
L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9jcmltc29uLWJsdWV0b290aC5zdmc8L2ZpbGU+Cisg
ICAgICAgIDxmaWxlPnJlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZp
bGU+cmVzL2VjbGlwc2UtaWNvbi5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9lY2xpcHNl
LXBvd2VyLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2NyaW1zb24tYmF0dGVyeS5zdmc8
L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9jcmltc29uLWhvc3Quc3ZnPC9maWxlPgorICAgICAg
ICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfcC5wbmciPnJlcy9zdGVhbS9lY2xpcHNl
X3AucG5nPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXMucG5n
Ij5yZXMvc3RlYW0vZWNsaXBzZS5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMv
c3RlYW0vdmliZW1pc19oZXJvLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmc8L2ZpbGU+
CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19sb2dvLnBuZyI+cmVzL3N0
ZWFtL2VjbGlwc2VfbG9nby5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3Rl
YW0vdmliZW1pc19pY29uLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfaWNvbi5wbmc8L2ZpbGU+Cisg
ICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTUxMi5wbmciPnJlcy9lY2xpcHNl
LW1hcmstNTEyLnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1h
cmstMjU2LnBuZyI+cmVzL2VjbGlwc2UtbWFyay0yNTYucG5nPC9maWxlPgorICAgICAgICA8Zmls
ZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay0xMjgucG5nIj5yZXMvZWNsaXBzZS1tYXJrLTEyOC5w
bmc8L2ZpbGU+CiAgICAgICAgIDxmaWxlIGFsaWFzPSJmb250cy9Tb3JhLnR0ZiI+Zm9udHMvU29y
YS50dGY8L2ZpbGU+CiAgICAgICAgIDxmaWxlIGFsaWFzPSJmb250cy9NYW5yb3BlLnR0ZiI+Zm9u
dHMvTWFucm9wZS50dGY8L2ZpbGU+CiAgICAgICAgIDxmaWxlPnJlcy9zb3VuZHMvbmF2X3RpY2su
d2F2PC9maWxlPgpkaWZmIC0tZ2l0IGEvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2Vz
LmNwcCBiL2FwcC9zZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5jcHAKaW5kZXggZDY5YTkx
My4uNjAyMmIyNSAxMDA2NDQKLS0tIGEvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2Vz
LmNwcAorKysgYi9hcHAvc2V0dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuY3BwCkBAIC0yMjks
NyArMjI5LDcgQEAgdm9pZCBTdHJlYW1pbmdQcmVmZXJlbmNlczo6cmVsb2FkKCkKICAgICBzZWVu
V2VsY29tZUhpbnQgPSBzZXR0aW5ncy52YWx1ZShTRVJfU0VFTldFTENPTUVISU5ULCBmYWxzZSku
dG9Cb29sKCk7CiAgICAgZW5hYmxlSGRyID0gc2V0dGluZ3MudmFsdWUoU0VSX0hEUiwgZmFsc2Up
LnRvQm9vbCgpOwogICAgIHVpU2hvd0hpbnRzID0gc2V0dGluZ3MudmFsdWUoU0VSX1VJX1NIT1dI
SU5UUywgdHJ1ZSkudG9Cb29sKCk7Ci0gICAgdWlBY2NlbnRJbmRleCA9IHFCb3VuZCgwLCBzZXR0
aW5ncy52YWx1ZShTRVJfVUlfQUNDRU5USU5ERVgsIDApLnRvSW50KCksIDMpOworICAgIHVpQWNj
ZW50SW5kZXggPSBxQm91bmQoMCwgc2V0dGluZ3MudmFsdWUoU0VSX1VJX0FDQ0VOVElOREVYLCA0
KS50b0ludCgpLCAxNSk7CiAgICAgdWlTb3VuZHMgPSBzZXR0aW5ncy52YWx1ZShTRVJfVUlTT1VO
RFMsIHRydWUpLnRvQm9vbCgpOwogICAgIGRpc3BsYXlIZHJDYXBhYmlsaXR5ID0gc2V0dGluZ3Mu
dmFsdWUoU0VSX0RJU1BMQVlfSERSX0NBUEFCSUxJVFksIHRydWUpLnRvQm9vbCgpOwogICAgIGhk
clRvbmVtYXBwaW5nID0gc2V0dGluZ3MudmFsdWUoU0VSX0hEUl9UT05FTUFQLCBmYWxzZSkudG9C
b29sKCk7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmNwcCBiL2FwcC9z
dHJlYW1pbmcvaW5wdXQvaW5wdXQuY3BwCmluZGV4IDEwNTA1ZWYuLjNmYWY4N2YgMTAwNjQ0Ci0t
LSBhL2FwcC9zdHJlYW1pbmcvaW5wdXQvaW5wdXQuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvaW5w
dXQvaW5wdXQuY3BwCkBAIC04OCw2ICs4OCwxMCBAQCBTZGxJbnB1dEhhbmRsZXI6OlNkbElucHV0
SGFuZGxlcihTdHJlYW1pbmdQcmVmZXJlbmNlcyYgcHJlZnMsIGludCBzdHJlYW1XaWR0aCwgaQog
ICAgIG1fU3BlY2lhbEtleUNvbWJvc1tLZXlDb21ib1RvZ2dsZVN0YXRzT3ZlcmxheV0ua2V5Q29k
ZSA9IFNETEtfczsKICAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVTdGF0c092
ZXJsYXldLnNjYW5Db2RlID0gU0RMX1NDQU5DT0RFX1M7CiAgICAgbV9TcGVjaWFsS2V5Q29tYm9z
W0tleUNvbWJvVG9nZ2xlU3RhdHNPdmVybGF5XS5lbmFibGVkID0gdHJ1ZTsKKyAgICBtX1NwZWNp
YWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVMb2NhbEhhcmR3YXJlXS5rZXlDb21ibyA9IEtleUNv
bWJvVG9nZ2xlTG9jYWxIYXJkd2FyZTsKKyAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9U
b2dnbGVMb2NhbEhhcmR3YXJlXS5rZXlDb2RlID0gU0RMS19oOworICAgIG1fU3BlY2lhbEtleUNv
bWJvc1tLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmVdLnNjYW5Db2RlID0gU0RMX1NDQU5DT0RF
X0g7CisgICAgbV9TcGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlTG9jYWxIYXJkd2FyZV0u
ZW5hYmxlZCA9IHRydWU7CiAKICAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVN
b3VzZU1vZGVdLmtleUNvbWJvID0gS2V5Q29tYm9Ub2dnbGVNb3VzZU1vZGU7CiAgICAgbV9TcGVj
aWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlTW91c2VNb2RlXS5rZXlDb2RlID0gU0RMS19tOwpk
aWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy9pbnB1dC9pbnB1dC5oIGIvYXBwL3N0cmVhbWluZy9p
bnB1dC9pbnB1dC5oCmluZGV4IGY4MjhjMDQuLjdkNWIxZGEgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJl
YW1pbmcvaW5wdXQvaW5wdXQuaAorKysgYi9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmgKQEAg
LTE4OCw2ICsxODgsNyBAQCBwcml2YXRlOgogICAgICAgICBLZXlDb21ib1VuZ3JhYklucHV0LAog
ICAgICAgICBLZXlDb21ib1RvZ2dsZUZ1bGxTY3JlZW4sCiAgICAgICAgIEtleUNvbWJvVG9nZ2xl
U3RhdHNPdmVybGF5LAorICAgICAgICBLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmUsCiAgICAg
ICAgIEtleUNvbWJvVG9nZ2xlTW91c2VNb2RlLAogICAgICAgICBLZXlDb21ib1RvZ2dsZUN1cnNv
ckhpZGUsCiAgICAgICAgIEtleUNvbWJvVG9nZ2xlTWluaW1pemUsCmRpZmYgLS1naXQgYS9hcHAv
c3RyZWFtaW5nL2lucHV0L2tleWJvYXJkLmNwcCBiL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9h
cmQuY3BwCmluZGV4IDk5M2U1MzQuLjk0MjU2MmUgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcv
aW5wdXQva2V5Ym9hcmQuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9hcmQuY3Bw
CkBAIC01MSw2ICs1MSwxMSBAQCB2b2lkIFNkbElucHV0SGFuZGxlcjo6cGVyZm9ybVNwZWNpYWxL
ZXlDb21ibyhLZXlDb21ibyBjb21ibykKICAgICAgICAgcmFpc2VBbGxLZXlzKCk7CiAgICAgICAg
IGJyZWFrOwogCisgICAgY2FzZSBLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmU6CisgICAgICAg
IFNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLnNldE92ZXJsYXlTdGF0ZShPdmVy
bGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSwKKyAgICAgICAgICAgICAhU2Vzc2lvbjo6Z2V0KCkt
PmdldE92ZXJsYXlNYW5hZ2VyKCkuaXNPdmVybGF5RW5hYmxlZChPdmVybGF5OjpPdmVybGF5TG9j
YWxIYXJkd2FyZSkpOworICAgICAgICBicmVhazsKKwogICAgIGNhc2UgS2V5Q29tYm9Ub2dnbGVT
dGF0c092ZXJsYXk6CiAgICAgICAgIFNETF9Mb2dJbmZvKFNETF9MT0dfQ0FURUdPUllfQVBQTElD
QVRJT04sCiAgICAgICAgICAgICAgICAgICAgICJEZXRlY3RlZCBzdGF0cyB0b2dnbGUgY29tYm8i
KTsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvc2Vzc2lvbi5jcHAgYi9hcHAvc3RyZWFtaW5n
L3Nlc3Npb24uY3BwCmluZGV4IDU4ZmViOTYuLjc5MWVmNGMgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJl
YW1pbmcvc2Vzc2lvbi5jcHAKKysrIGIvYXBwL3N0cmVhbWluZy9zZXNzaW9uLmNwcApAQCAtMSw0
ICsxLDUgQEAKICNpbmNsdWRlICJzZXNzaW9uLmgiDQorI2luY2x1ZGUgPFFTZXR0aW5ncz4NCiAj
aW5jbHVkZSAic2V0dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuaCINCiAjaW5jbHVkZSAic3Ry
ZWFtaW5nL3N0cmVhbXV0aWxzLmgiDQogI2luY2x1ZGUgInN0cmVhbWluZy92cnJyYXRlcG9saWN5
LmgiDQpAQCAtMjY2OSw2ICsyNjcwLDcgQEAgdm9pZCBTZXNzaW9uOjpleGVjSW50ZXJuYWwoKQog
DQogICAgIC8vIFRvZ2dsZSB0aGUgc3RhdHMgb3ZlcmxheSBpZiByZXF1ZXN0ZWQgYnkgdGhlIHVz
ZXINCiAgICAgbV9PdmVybGF5TWFuYWdlci5zZXRPdmVybGF5U3RhdGUoT3ZlcmxheTo6T3Zlcmxh
eURlYnVnLCBtX1ByZWZlcmVuY2VzLT5zaG93UGVyZm9ybWFuY2VPdmVybGF5KTsNCisgICAgbV9P
dmVybGF5TWFuYWdlci5zZXRPdmVybGF5U3RhdGUoT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdh
cmUsIFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2FsT3ZlcmxheSIsZmFsc2UpLnRvQm9v
bCgpKTsNCiANCiAgICAgLy8gVmliZW1pczogb3B0LWluIG9uLXNjcmVlbiB0b3VjaCBjb250cm9s
cyBvdmVybGF5IOKAlA0KICAgICAvLyB0aHJlZSBpY29uLW9ubHkgYnV0dG9ucyAoTUVOVSBvcGVu
cyB0aGUgUXVpY2sgTWVudSwgS0JEIHJlcXVlc3RzIHRoZSBTdGVhbU9TDQpkaWZmIC0tZ2l0IGEv
YXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2QzZDExdmEuY3BwIGIvYXBwL3N0
cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2QzZDExdmEuY3BwCmluZGV4IDM4OGUzMDcu
LmY4NTMyMzkgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVy
cy9kM2QxMXZhLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMv
ZDNkMTF2YS5jcHAKQEAgLTk2NCw3ICs5NjQsNyBAQCB2b2lkIEQzRDExVkFSZW5kZXJlcjo6bm90
aWZ5T3ZlcmxheVVwZGF0ZWQoT3ZlcmxheTo6T3ZlcmxheVR5cGUgdHlwZSkKICAgICAgICAgcmVu
ZGVyUmVjdC54ID0gMDsKICAgICAgICAgcmVuZGVyUmVjdC55ID0gMDsKICAgICB9Ci0gICAgZWxz
ZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICBlbHNlIGlmICh0eXBl
ID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZyB8fCB0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlMb2Nh
bEhhcmR3YXJlKSB7CiAgICAgICAgIC8vIFRvcCBsZWZ0CiAgICAgICAgIHJlbmRlclJlY3QueCA9
IDA7CiAgICAgICAgIHJlbmRlclJlY3QueSA9IG1fRGlzcGxheUhlaWdodCAtIG5ld1N1cmZhY2Ut
Pmg7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZHh2
YTIuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2R4dmEyLmNwcApp
bmRleCAzMjYxOGQ4Li4wNGI1ZDE3IDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2Zm
bXBlZy1yZW5kZXJlcnMvZHh2YTIuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVn
LXJlbmRlcmVycy9keHZhMi5jcHAKQEAgLTg2Miw3ICs4NjIsNyBAQCB2b2lkIERYVkEyUmVuZGVy
ZXI6Om5vdGlmeU92ZXJsYXlVcGRhdGVkKE92ZXJsYXk6Ok92ZXJsYXlUeXBlIHR5cGUpCiAgICAg
ICAgIHJlbmRlclJlY3QueCA9IDA7CiAgICAgICAgIHJlbmRlclJlY3QueSA9IG1fRGlzcGxheUhl
aWdodCAtIG5ld1N1cmZhY2UtPmg7CiAgICAgfQotICAgIGVsc2UgaWYgKHR5cGUgPT0gT3Zlcmxh
eTo6T3ZlcmxheURlYnVnKSB7CisgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5
RGVidWcgfHwgdHlwZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAg
ICAvLyBUb3AgbGVmdAogICAgICAgICByZW5kZXJSZWN0LnggPSAwOwogICAgICAgICByZW5kZXJS
ZWN0LnkgPSAwOwpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVy
ZXJzL2VnbHZpZC5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZWds
dmlkLmNwcAppbmRleCA5NTg3YTM1Li4yMDY4MGQ4IDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5n
L3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZWdsdmlkLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3Zp
ZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZWdsdmlkLmNwcApAQCAtMjM0LDEwICsyMzQsMTAgQEAgdm9p
ZCBFR0xSZW5kZXJlcjo6cmVuZGVyT3ZlcmxheShPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBlLCBp
bnQgdmlld3BvcnRXaWR0aCwgaW4KICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnggPSAwOwogICAg
ICAgICAgICAgb3ZlcmxheVJlY3QueSA9IDA7CiAgICAgICAgIH0KLSAgICAgICAgZWxzZSBpZiAo
dHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICAgICAgZWxzZSBpZiAodHlwZSA9
PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgdHlwZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxI
YXJkd2FyZSkgewogICAgICAgICAgICAgLy8gVmliZW1pczogdXNlci1jb25maWd1cmFibGUgY29y
bmVyLiBOQjogT3BlbkdMIG9yaWdpbiBpcyBsb3dlci1sZWZ0LAogICAgICAgICAgICAgLy8gc28g
InRvcCIgaXMgdGhlIGhpZ2gtWSBlZGdlIGhlcmUuCi0gICAgICAgICAgICBpbnQgYW5jaG9yID0g
U2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0RGVidWdPdmVybGF5QW5jaG9y
KCk7CisgICAgICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlN
YW5hZ2VyKCkuZ2V0T3ZlcmxheUFuY2hvcih0eXBlKTsKICAgICAgICAgICAgIGJvb2wgcmlnaHQg
PSAoYW5jaG9yID09IDEgfHwgYW5jaG9yID09IDMpOyAgLy8gVFIgb3IgQlIKICAgICAgICAgICAg
IGJvb2wgYm90dG9tID0gKGFuY2hvciA9PSAyIHx8IGFuY2hvciA9PSAzKTsgLy8gQkwgb3IgQlIK
ICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnggPSByaWdodCA/ICh2aWV3cG9ydFdpZHRoIC0gbmV3
U3VyZmFjZS0+dykgOiAwOwpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWct
cmVuZGVyZXJzL3BsdmsuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJz
L3BsdmsuY3BwCmluZGV4IGJjMTZmZjIuLmJhYzE4NWIgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1p
bmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9wbHZrLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3Zp
ZGVvL2ZmbXBlZy1yZW5kZXJlcnMvcGx2ay5jcHAKQEAgLTEzODIsMTAgKzEzODIsMTAgQEAgdm9p
ZCBQbFZrUmVuZGVyZXI6OnJlbmRlckZyYW1lKEFWRnJhbWUgKmZyYW1lKQogICAgICAgICAgICAg
ICAgIG92ZXJsYXlQYXJ0c1tpXS5kc3QueDAgPSAwOw0KICAgICAgICAgICAgICAgICBvdmVybGF5
UGFydHNbaV0uZHN0LnkwID0gU0RMX21heCgwLCB0YXJnZXRGcmFtZS5jcm9wLnkxIC0gb3Zlcmxh
eVBhcnRzW2ldLnNyYy55MSk7DQogICAgICAgICAgICAgfQ0KLSAgICAgICAgICAgIGVsc2UgaWYg
KGkgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7DQotICAgICAgICAgICAgICAgIC8vIFRvcCBs
ZWZ0DQotICAgICAgICAgICAgICAgIG92ZXJsYXlQYXJ0c1tpXS5kc3QueDAgPSAwOw0KLSAgICAg
ICAgICAgICAgICBvdmVybGF5UGFydHNbaV0uZHN0LnkwID0gMDsNCisgICAgICAgICAgICBlbHNl
IGlmIChpID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZyB8fCBpID09IE92ZXJsYXk6Ok92ZXJsYXlM
b2NhbEhhcmR3YXJlKSB7DQorICAgICAgICAgICAgICAgIGludCBhbmNob3I9U2Vzc2lvbjo6Z2V0
KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0T3ZlcmxheUFuY2hvcihzdGF0aWNfY2FzdDxPdmVy
bGF5OjpPdmVybGF5VHlwZT4oaSkpOw0KKyAgICAgICAgICAgICAgICBvdmVybGF5UGFydHNbaV0u
ZHN0LngwPShhbmNob3I9PTEgfHwgYW5jaG9yPT0zKSA/IFNETF9tYXgoMCx0YXJnZXRGcmFtZS5j
cm9wLngxLW92ZXJsYXlQYXJ0c1tpXS5zcmMueDEpIDogMDsNCisgICAgICAgICAgICAgICAgb3Zl
cmxheVBhcnRzW2ldLmRzdC55MD0oYW5jaG9yPT0yIHx8IGFuY2hvcj09MykgPyBTRExfbWF4KDAs
dGFyZ2V0RnJhbWUuY3JvcC55MS1vdmVybGF5UGFydHNbaV0uc3JjLnkxKSA6IDA7DQogICAgICAg
ICAgICAgfQ0KICAgICAgICAgICAgIGVsc2UgaWYgKGkgPT0gT3ZlcmxheTo6T3ZlcmxheVRvdWNo
QnV0dG9uTWVudSB8fCBpID09IE92ZXJsYXk6Ok92ZXJsYXlUb3VjaEJ1dHRvbktiZCB8fA0KICAg
ICAgICAgICAgICAgICAgICAgIGkgPT0gT3ZlcmxheTo6T3ZlcmxheVRvdWNoQnV0dG9uVG91Y2hN
b2RlKSB7DQpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJz
L3NkbHZpZC5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvc2Rsdmlk
LmNwcAppbmRleCA1NjdiZjE5Li5mMTMyNWVkIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3Zp
ZGVvL2ZmbXBlZy1yZW5kZXJlcnMvc2RsdmlkLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVv
L2ZmbXBlZy1yZW5kZXJlcnMvc2RsdmlkLmNwcApAQCAtMjQxLDExICsyNDEsMTEgQEAgdm9pZCBT
ZGxSZW5kZXJlcjo6cmVuZGVyT3ZlcmxheShPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBlKQogICAg
ICAgICAgICAgICAgIG1fT3ZlcmxheVJlY3RzW3R5cGVdLnggPSAwOwogICAgICAgICAgICAgICAg
IG1fT3ZlcmxheVJlY3RzW3R5cGVdLnkgPSB2aWV3cG9ydFJlY3QuaCAtIG5ld1N1cmZhY2UtPmg7
CiAgICAgICAgICAgICB9Ci0gICAgICAgICAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92
ZXJsYXlEZWJ1ZykgeworICAgICAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVy
bGF5RGVidWcgfHwgdHlwZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAg
ICAgICAgICAgICAgIC8vIFZpYmVtaXM6IHVzZXItY29uZmlndXJhYmxlIGNvcm5lciAoU0RMIG9y
aWdpbiBpcyB1cHBlci1sZWZ0KS4KICAgICAgICAgICAgICAgICBTRExfUmVjdCB2aWV3cG9ydFJl
Y3Q7CiAgICAgICAgICAgICAgICAgU0RMX1JlbmRlckdldFZpZXdwb3J0KG1fUmVuZGVyZXIsICZ2
aWV3cG9ydFJlY3QpOwotICAgICAgICAgICAgICAgIGludCBhbmNob3IgPSBTZXNzaW9uOjpnZXQo
KS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5nZXREZWJ1Z092ZXJsYXlBbmNob3IoKTsKKyAgICAgICAg
ICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCku
Z2V0T3ZlcmxheUFuY2hvcih0eXBlKTsKICAgICAgICAgICAgICAgICBib29sIHJpZ2h0ID0gKGFu
Y2hvciA9PSAxIHx8IGFuY2hvciA9PSAzKTsgIC8vIFRSIG9yIEJSCiAgICAgICAgICAgICAgICAg
Ym9vbCBib3R0b20gPSAoYW5jaG9yID09IDIgfHwgYW5jaG9yID09IDMpOyAvLyBCTCBvciBCUgog
ICAgICAgICAgICAgICAgIG1fT3ZlcmxheVJlY3RzW3R5cGVdLnggPSByaWdodCA/ICh2aWV3cG9y
dFJlY3QudyAtIG5ld1N1cmZhY2UtPncpIDogMDsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcv
dmlkZW8vZmZtcGVnLXJlbmRlcmVycy92YWFwaS5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2Zm
bXBlZy1yZW5kZXJlcnMvdmFhcGkuY3BwCmluZGV4IGFiNjVlMGIuLjI4NDNmZDYgMTAwNjQ0Ci0t
LSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92YWFwaS5jcHAKKysrIGIv
YXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3ZhYXBpLmNwcApAQCAtNzQxLDkg
Kzc0MSw5IEBAIHZvaWQgVkFBUElSZW5kZXJlcjo6bm90aWZ5T3ZlcmxheVVwZGF0ZWQoT3Zlcmxh
eTo6T3ZlcmxheVR5cGUgdHlwZSkKICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnggPSAwOwogICAg
ICAgICAgICAgb3ZlcmxheVJlY3QueSA9IC1uZXdTdXJmYWNlLT5oOwogICAgICAgICB9Ci0gICAg
ICAgIGVsc2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7CisgICAgICAgIGVs
c2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8IHR5cGUgPT0gT3ZlcmxheTo6
T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHsKICAgICAgICAgICAgIC8vIFZpYmVtaXM6IHVzZXItY29u
ZmlndXJhYmxlIGNvcm5lciAodXBwZXItbGVmdCBvcmlnaW4pLgotICAgICAgICAgICAgaW50IGFu
Y2hvciA9IFNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmdldERlYnVnT3Zlcmxh
eUFuY2hvcigpOworICAgICAgICAgICAgaW50IGFuY2hvciA9IFNlc3Npb246OmdldCgpLT5nZXRP
dmVybGF5TWFuYWdlcigpLmdldE92ZXJsYXlBbmNob3IodHlwZSk7CiAgICAgICAgICAgICBib29s
IHJpZ2h0ID0gKGFuY2hvciA9PSAxIHx8IGFuY2hvciA9PSAzKTsgIC8vIFRSIG9yIEJSCiAgICAg
ICAgICAgICBib29sIGJvdHRvbSA9IChhbmNob3IgPT0gMiB8fCBhbmNob3IgPT0gMyk7IC8vIEJM
IG9yIEJSCiAgICAgICAgICAgICBvdmVybGF5UmVjdC54ID0gcmlnaHQgPyAobV9EaXNwbGF5V2lk
dGggLSBuZXdTdXJmYWNlLT53KSA6IDA7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVv
L2ZmbXBlZy1yZW5kZXJlcnMvdmRwYXUuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWct
cmVuZGVyZXJzL3ZkcGF1LmNwcAppbmRleCAyZjllMGMzLi45MDZhY2NjIDEwMDY0NAotLS0gYS9h
cHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdmRwYXUuY3BwCisrKyBiL2FwcC9z
dHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92ZHBhdS5jcHAKQEAgLTQzNiw5ICs0MzYs
OSBAQCB2b2lkIFZEUEFVUmVuZGVyZXI6Om5vdGlmeU92ZXJsYXlVcGRhdGVkKE92ZXJsYXk6Ok92
ZXJsYXlUeXBlIHR5cGUpCiAgICAgICAgICAgICBvdmVybGF5UmVjdC54MCA9IDA7CiAgICAgICAg
ICAgICBvdmVybGF5UmVjdC55MCA9IG1fRGlzcGxheUhlaWdodCAtIG5ld1N1cmZhY2UtPmg7CiAg
ICAgICAgIH0KLSAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcp
IHsKKyAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgdHlw
ZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAgICAgLy8gVmli
ZW1pczogdXNlci1jb25maWd1cmFibGUgY29ybmVyICh1cHBlci1sZWZ0IG9yaWdpbikuCi0gICAg
ICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCku
Z2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAgICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lv
bjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0T3ZlcmxheUFuY2hvcih0eXBlKTsKICAg
ICAgICAgICAgIGJvb2wgcmlnaHQgPSAoYW5jaG9yID09IDEgfHwgYW5jaG9yID09IDMpOyAgLy8g
VFIgb3IgQlIKICAgICAgICAgICAgIGJvb2wgYm90dG9tID0gKGFuY2hvciA9PSAyIHx8IGFuY2hv
ciA9PSAzKTsgLy8gQkwgb3IgQlIKICAgICAgICAgICAgIG92ZXJsYXlSZWN0LngwID0gcmlnaHQg
PyAobV9EaXNwbGF5V2lkdGggLSBuZXdTdXJmYWNlLT53KSA6IDA7CmRpZmYgLS1naXQgYS9hcHAv
c3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdnRfYXZzYW1wbGVsYXllci5tbSBiL2Fw
cC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9hdnNhbXBsZWxheWVyLm1tCmlu
ZGV4IGJkNTUyODEuLjEzZDg4YzYgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZt
cGVnLXJlbmRlcmVycy92dF9hdnNhbXBsZWxheWVyLm1tCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlk
ZW8vZmZtcGVnLXJlbmRlcmVycy92dF9hdnNhbXBsZWxheWVyLm1tCkBAIC00OTYsNiArNDk2LDcg
QEAgcHVibGljOgogICAgICAgICAgICAgW21fT3ZlcmxheVRleHRGaWVsZHNbdHlwZV0gc2V0U2Vs
ZWN0YWJsZTpOT107CiAKICAgICAgICAgICAgIHN3aXRjaCAodHlwZSkgeworICAgICAgICAgICAg
Y2FzZSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZToKICAgICAgICAgICAgIGNhc2UgT3Zl
cmxheTo6T3ZlcmxheURlYnVnOgogICAgICAgICAgICAgICAgIFttX092ZXJsYXlUZXh0RmllbGRz
W3R5cGVdIHNldEFsaWdubWVudDpOU1RleHRBbGlnbm1lbnRMZWZ0XTsKICAgICAgICAgICAgICAg
ICBicmVhazsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVy
cy92dF9tZXRhbC5tbSBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9t
ZXRhbC5tbQppbmRleCA3OWIxNjVkLi4zMzRlZWZmIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5n
L3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdnRfbWV0YWwubW0KKysrIGIvYXBwL3N0cmVhbWluZy92
aWRlby9mZm1wZWctcmVuZGVyZXJzL3Z0X21ldGFsLm1tCkBAIC02MDAsNyArNjAwLDcgQEAgcHVi
bGljOgogICAgICAgICAgICAgICAgICAgICByZW5kZXJSZWN0LnggPSAwOwogICAgICAgICAgICAg
ICAgICAgICByZW5kZXJSZWN0LnkgPSAwOwogICAgICAgICAgICAgICAgIH0KLSAgICAgICAgICAg
ICAgICBlbHNlIGlmIChpID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZykgeworICAgICAgICAgICAg
ICAgIGVsc2UgaWYgKGkgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8IGkgPT0gT3ZlcmxheTo6
T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHsKICAgICAgICAgICAgICAgICAgICAgLy8gVG9wIGxlZnQK
ICAgICAgICAgICAgICAgICAgICAgcmVuZGVyUmVjdC54ID0gMDsKICAgICAgICAgICAgICAgICAg
ICAgcmVuZGVyUmVjdC55ID0gbV9MYXN0RHJhd2FibGVIZWlnaHQgLSBvdmVybGF5VGV4dHVyZS5o
ZWlnaHQ7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy5jcHAgYi9hcHAv
c3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy5jcHAKaW5kZXggMmFjMWE2ZS4uNGE2ZTBjMCAxMDA2NDQK
LS0tIGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWcuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcv
dmlkZW8vZmZtcGVnLmNwcApAQCAtMSw1ICsxLDYgQEAKICNpbmNsdWRlIDxMaW1lbGlnaHQuaD4K
ICNpbmNsdWRlICJmZm1wZWcuaCIKKyNpbmNsdWRlICJtb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJl
LmgiCiAjaW5jbHVkZSAic3RyZWFtaW5nL3Nlc3Npb24uaCIKICNpbmNsdWRlICJiYWNrZW5kL3N5
c3RlbXByb3BlcnRpZXMuaCIKICNpbmNsdWRlICJzZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNl
cy5oIgpAQCAtMjQ0MCw2ICsyNDQxLDExIEBAIGludCBGRm1wZWdWaWRlb0RlY29kZXI6OnN1Ym1p
dERlY29kZVVuaXQoUERFQ09ERV9VTklUIGR1KQogICAgICAgICAgICAgU2Vzc2lvbjo6Z2V0KCkt
PmdldE92ZXJsYXlNYW5hZ2VyKCkuc2V0T3ZlcmxheVRleHRVcGRhdGVkKE92ZXJsYXk6Ok92ZXJs
YXlEZWJ1Zyk7CiAgICAgICAgIH0KIAorICAgICAgICBpZihTZXNzaW9uOjpnZXQoKS0+Z2V0T3Zl
cmxheU1hbmFnZXIoKS5pc092ZXJsYXlFbmFibGVkKE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3
YXJlKSkgeworICAgICAgICAgICAgUUJ5dGVBcnJheSB0ZXh0PUxvY2FsSGFyZHdhcmU6Om92ZXJs
YXlUZXh0KCkudG9VdGY4KCk7CisgICAgICAgICAgICBTZXNzaW9uOjpnZXQoKS0+Z2V0T3Zlcmxh
eU1hbmFnZXIoKS51cGRhdGVPdmVybGF5VGV4dChPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2Fy
ZSx0ZXh0LmNvbnN0RGF0YSgpKTsKKyAgICAgICAgfQorCiAgICAgICAgIC8vIEFjY3VtdWxhdGUg
dGhlc2UgdmFsdWVzIGludG8gdGhlIGdsb2JhbCBzdGF0cwogICAgICAgICBhZGRWaWRlb1N0YXRz
KG1fQWN0aXZlV25kVmlkZW9TdGF0cywgbV9HbG9iYWxWaWRlb1N0YXRzKTsKIApkaWZmIC0tZ2l0
IGEvYXBwL3N0cmVhbWluZy92aWRlby9vdmVybGF5bWFuYWdlci5jcHAgYi9hcHAvc3RyZWFtaW5n
L3ZpZGVvL292ZXJsYXltYW5hZ2VyLmNwcAppbmRleCA5MmU2YzZkLi4xY2IzYTkyIDEwMDY0NAot
LS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5hZ2VyLmNwcAorKysgYi9hcHAvc3Ry
ZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5hZ2VyLmNwcApAQCAtMSw2ICsxLDEyIEBACiAjaW5jbHVk
ZSAib3ZlcmxheW1hbmFnZXIuaCIKICNpbmNsdWRlICJwYXRoLmgiCiAjaW5jbHVkZSAic2V0dGlu
Z3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuaCIKKyNpbmNsdWRlICJtb29ubGlnaHRvcy9sb2NhbGhh
cmR3YXJlLmgiCisjaW5jbHVkZSAibW9vbmxpZ2h0b3Mvb3ZlcmxheXN0eWxlLmgiCisjaW5jbHVk
ZSA8UVNldHRpbmdzPgorI2luY2x1ZGUgPFFJbWFnZT4KKyNpbmNsdWRlIDxRUGFpbnRlcj4KKyNp
bmNsdWRlIDxRQ29sb3I+CiAKIHVzaW5nIG5hbWVzcGFjZSBPdmVybGF5OwogCkBAIC05LDYgKzE1
LDEzIEBAIGludCBPdmVybGF5TWFuYWdlcjo6Z2V0RGVidWdPdmVybGF5QW5jaG9yKCkKICAgICBy
ZXR1cm4gc3RhdGljX2Nhc3Q8aW50PihTdHJlYW1pbmdQcmVmZXJlbmNlczo6Z2V0KCktPnBlcmZP
dmVybGF5UG9zaXRpb24pOwogfQogCitpbnQgT3ZlcmxheU1hbmFnZXI6OmdldE92ZXJsYXlBbmNo
b3IoT3ZlcmxheVR5cGUgdHlwZSkgeworICAgIGludCBzdHJlYW09Z2V0RGVidWdPdmVybGF5QW5j
aG9yKCk7CisgICAgaWYodHlwZSE9T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHJldHVybiBzdHJlYW07
CisgICAgaW50IGxvY2FsPXFCb3VuZCgwLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2Fs
UG9zaXRpb24iLDEpLnRvSW50KCksMyk7CisgICAgcmV0dXJuIGlzT3ZlcmxheUVuYWJsZWQoT3Zl
cmxheURlYnVnKSAmJiBsb2NhbD09c3RyZWFtID8gKGxvY2FsIF4gMSkgOiBsb2NhbDsKK30KKwog
T3ZlcmxheU1hbmFnZXI6Ok92ZXJsYXlNYW5hZ2VyKCkgOgogICAgIG1fUmVuZGVyZXIobnVsbHB0
ciksCiAgICAgbV9Gb250RGF0YShQYXRoOjpyZWFkRGF0YUZpbGUoIk1vZGVTZXZlbi50dGYiKSkK
QEAgLTMyLDggKzQ1LDEwIEBAIE92ZXJsYXlNYW5hZ2VyOjpPdmVybGF5TWFuYWdlcigpIDoKICAg
ICAgICAgYnJlYWs7CiAgICAgfQogCi0gICAgbV9PdmVybGF5c1tPdmVybGF5VHlwZTo6T3Zlcmxh
eURlYnVnXS5jb2xvciA9IHsweEQwLCAweEQwLCAweDAwLCAweEZGfTsKKyAgICBtX092ZXJsYXlz
W092ZXJsYXlUeXBlOjpPdmVybGF5RGVidWddLmNvbG9yID0gezB4RUMsIDB4RUUsIDB4RjEsIDB4
RkZ9OwogICAgIG1fT3ZlcmxheXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlEZWJ1Z10uZm9udFNpemUg
PSBkZWJ1Z0ZvbnRTaXplOworICAgIG1fT3ZlcmxheXNbT3ZlcmxheUxvY2FsSGFyZHdhcmVdLmNv
bG9yID0gezB4RUMsMHhFRSwweEYxLDB4RkZ9OworICAgIG1fT3ZlcmxheXNbT3ZlcmxheUxvY2Fs
SGFyZHdhcmVdLmZvbnRTaXplID0gZGVidWdGb250U2l6ZTsKIAogICAgIG1fT3ZlcmxheXNbT3Zl
cmxheVR5cGU6Ok92ZXJsYXlTdGF0dXNVcGRhdGVdLmNvbG9yID0gezB4Q0MsIDB4MDAsIDB4MDAs
IDB4RkZ9OwogICAgIG1fT3ZlcmxheXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlTdGF0dXNVcGRhdGVd
LmZvbnRTaXplID0gMzY7CkBAIC0zNjgsMTEgKzM4MywzMiBAQCB2b2lkIE92ZXJsYXlNYW5hZ2Vy
Ojpub3RpZnlPdmVybGF5VXBkYXRlZChPdmVybGF5VHlwZSB0eXBlKQogICAgIH0KIAogICAgIGlm
IChtX092ZXJsYXlzW3R5cGVdLmVuYWJsZWQpIHsKLSAgICAgICAgLy8gVGhlIF9XcmFwcGVkIHZh
cmlhbnQgaXMgcmVxdWlyZWQgZm9yIGxpbmUgYnJlYWtzIHRvIHdvcmsKLSAgICAgICAgU0RMX1N1
cmZhY2UqIHN1cmZhY2UgPSBUVEZfUmVuZGVyVGV4dF9CbGVuZGVkX1dyYXBwZWQobV9PdmVybGF5
c1t0eXBlXS5mb250LAotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICBtX092ZXJsYXlzW3R5cGVdLnRleHQsCisgICAgICAgIFFCeXRl
QXJyYXkgdGV4dChtX092ZXJsYXlzW3R5cGVdLnRleHQpOworICAgICAgICBib29sIGNhcmQ9dHlw
ZT09T3ZlcmxheURlYnVnIHx8IHR5cGU9PU92ZXJsYXlMb2NhbEhhcmR3YXJlOworICAgICAgICBp
Zih0eXBlPT1PdmVybGF5RGVidWcpIHsKKyAgICAgICAgICAgIGlmKCFRU2V0dGluZ3MoKS52YWx1
ZSgiZWNsaXBzZS9zdHJlYW1EZXRhaWxlZCIsdHJ1ZSkudG9Cb29sKCkpIHsKKyAgICAgICAgICAg
ICAgICBRU3RyaW5nTGlzdCBjb21wYWN0OworICAgICAgICAgICAgICAgIGZvcihjb25zdCBRU3Ry
aW5nJiBsaW5lOlFTdHJpbmc6OmZyb21VdGY4KHRleHQpLnNwbGl0KCdcbicpKSB7CisgICAgICAg
ICAgICAgICAgICAgIGlmKGxpbmUuY29udGFpbnMoIkZQUyIsUXQ6OkNhc2VJbnNlbnNpdGl2ZSkg
fHwgbGluZS5jb250YWlucygiZnJhbWUgcmF0ZSIsUXQ6OkNhc2VJbnNlbnNpdGl2ZSkgfHwgbGlu
ZS5jb250YWlucygibGF0ZW5jeSIsUXQ6OkNhc2VJbnNlbnNpdGl2ZSkgfHwgbGluZS5jb250YWlu
cygiYml0cmF0ZSIsUXQ6OkNhc2VJbnNlbnNpdGl2ZSkgfHwgbGluZS5jb250YWlucygiZHJvcHBl
ZCIsUXQ6OkNhc2VJbnNlbnNpdGl2ZSkgfHwgbGluZS5jb250YWlucygicmVzb2x1dGlvbiIsUXQ6
OkNhc2VJbnNlbnNpdGl2ZSkpIGNvbXBhY3QuYXBwZW5kKGxpbmUpOworICAgICAgICAgICAgICAg
IH0KKyAgICAgICAgICAgICAgICBpZihjb21wYWN0LmlzRW1wdHkoKSkgY29tcGFjdD1RU3RyaW5n
Ojpmcm9tVXRmOCh0ZXh0KS5zcGxpdCgnXG4nKS5taWQoMCw1KTsKKyAgICAgICAgICAgICAgICB0
ZXh0PWNvbXBhY3Quam9pbignXG4nKS50b1V0ZjgoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAg
ICAgIHRleHQucHJlcGVuZCgiRWNsaXBzZU9TIHwgU1RSRUFNXG4iKTsKKyAgICAgICAgfQorICAg
ICAgICBTRExfU3VyZmFjZSogc3VyZmFjZSA9IFRURl9SZW5kZXJVVEY4X0JsZW5kZWRfV3JhcHBl
ZChtX092ZXJsYXlzW3R5cGVdLmZvbnQsCisgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRleHQuY29uc3REYXRhKCksCiAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIG1f
T3ZlcmxheXNbdHlwZV0uY29sb3IsCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgIDEwMjQpOworICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjYXJkID8gNDgwIDogMTAy
NCk7CisgICAgICAgIGlmKGNhcmQgJiYgc3VyZmFjZSkgeworICAgICAgICAgICAgUUltYWdlIGlt
YWdlPUVjbGlwc2VPdmVybGF5U3R5bGU6OnBhbmVsKFFTaXplKHN1cmZhY2UtPncrMjgsc3VyZmFj
ZS0+aCsyOCksU3RyZWFtaW5nUHJlZmVyZW5jZXM6OmdldCgpLT51aUFjY2VudEluZGV4LFFTZXR0
aW5ncygpLnZhbHVlKCJlY2xpcHNlL292ZXJsYXlPcGFjaXR5Iiw4NSkudG9JbnQoKSk7CisgICAg
ICAgICAgICBTRExfU3VyZmFjZSogcGFuZWw9aW1hZ2UuaXNOdWxsKCkgPyBudWxscHRyIDogU0RM
X0NyZWF0ZVJHQlN1cmZhY2VXaXRoRm9ybWF0KDAsaW1hZ2Uud2lkdGgoKSxpbWFnZS5oZWlnaHQo
KSwzMixTRExfUElYRUxGT1JNQVRfUkdCQTMyKTsKKyAgICAgICAgICAgIGlmKHBhbmVsKSB7Cisg
ICAgICAgICAgICAgICAgZm9yKGludCByb3c9MDtyb3c8aW1hZ2UuaGVpZ2h0KCk7Kytyb3cpIG1l
bWNweShzdGF0aWNfY2FzdDxjaGFyKj4ocGFuZWwtPnBpeGVscykrcm93KnBhbmVsLT5waXRjaCxp
bWFnZS5jb25zdFNjYW5MaW5lKHJvdyksaW1hZ2Uud2lkdGgoKSo0KTsKKyAgICAgICAgICAgICAg
ICBTRExfUmVjdCBkZXN0PXsxNCwxNCxzdXJmYWNlLT53LHN1cmZhY2UtPmh9OyBTRExfQmxpdFN1
cmZhY2Uoc3VyZmFjZSxudWxscHRyLHBhbmVsLCZkZXN0KTsKKyAgICAgICAgICAgICAgICBTRExf
RnJlZVN1cmZhY2Uoc3VyZmFjZSk7IHN1cmZhY2U9cGFuZWw7CisgICAgICAgICAgICB9CisgICAg
ICAgIH0KIAogICAgICAgICBTRExfQXRvbWljU2V0UHRyKCh2b2lkKiopJm1fT3ZlcmxheXNbdHlw
ZV0uc3VyZmFjZSwgc3VyZmFjZSk7CiAgICAgfQpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92
aWRlby9vdmVybGF5bWFuYWdlci5oIGIvYXBwL3N0cmVhbWluZy92aWRlby9vdmVybGF5bWFuYWdl
ci5oCmluZGV4IGUxOWZjMGMuLjUwOTVmZDYgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlk
ZW8vb3ZlcmxheW1hbmFnZXIuaAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5h
Z2VyLmgKQEAgLTEwLDYgKzEwLDcgQEAgbmFtZXNwYWNlIE92ZXJsYXkgewogCiBlbnVtIE92ZXJs
YXlUeXBlIHsKICAgICBPdmVybGF5RGVidWcsCisgICAgT3ZlcmxheUxvY2FsSGFyZHdhcmUsCiAg
ICAgT3ZlcmxheVN0YXR1c1VwZGF0ZSwKICAgICBPdmVybGF5U2VydmVyQ29tbWFuZHMsCiAgICAg
T3ZlcmxheVF1aWNrTWVudSwKQEAgLTcwLDYgKzcxLDcgQEAgcHVibGljOgogICAgIC8vIHByZWZl
cmVuY2UuIFJldHVybnMgU3RyZWFtaW5nUHJlZmVyZW5jZXM6OlBlcmZPdmVybGF5UG9zaXRpb24g
YXMgYW4gaW50CiAgICAgLy8gKDA9VEwsIDE9VFIsIDI9QkwsIDM9QlIpLiBSZW5kZXJlcnMgbWFw
IHRoaXMgdG8gdGhlaXIgb3duIGNvb3JkaW5hdGUgc3BhY2UuCiAgICAgaW50IGdldERlYnVnT3Zl
cmxheUFuY2hvcigpOworICAgIGludCBnZXRPdmVybGF5QW5jaG9yKE92ZXJsYXlUeXBlIHR5cGUp
OwogCiAgICAgdm9pZCBzZXRPdmVybGF5UmVuZGVyZXIoSU92ZXJsYXlSZW5kZXJlciogcmVuZGVy
ZXIpOwogCmRpZmYgLS1naXQgYS9wYWNrYWdpbmcvZmxhdHBhay9pby5naXRodWIubmF2eWFzMzIx
LlZpYmVtaXMuZGVza3RvcCBiL3BhY2thZ2luZy9mbGF0cGFrL2lvLmdpdGh1Yi5uYXZ5YXMzMjEu
VmliZW1pcy5kZXNrdG9wCmluZGV4IDA0NWFkYmUuLmYxMmRhNWQgMTAwNjQ0Ci0tLSBhL3BhY2th
Z2luZy9mbGF0cGFrL2lvLmdpdGh1Yi5uYXZ5YXMzMjEuVmliZW1pcy5kZXNrdG9wCisrKyBiL3Bh
Y2thZ2luZy9mbGF0cGFrL2lvLmdpdGh1Yi5uYXZ5YXMzMjEuVmliZW1pcy5kZXNrdG9wCkBAIC0x
LDYgKzEsNiBAQAogW0Rlc2t0b3AgRW50cnldCiBUeXBlPUFwcGxpY2F0aW9uCi1OYW1lPVZpYmVt
aXMKK05hbWU9RWNsaXBzZQogR2VuZXJpY05hbWU9R2FtZSBTdHJlYW1pbmcgQ2xpZW50CiBDb21t
ZW50PVN0cmVhbSBnYW1lcyBhbmQgYXBwbGljYXRpb25zIGZyb20gYSBTdW5zaGluZSAvIEFwb2xs
byAvIFZpYmVwb2xsbyBob3N0CiBFeGVjPXZpYmVtaXMK
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
