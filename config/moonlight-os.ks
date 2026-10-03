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
VIBEMIS_PATCH_SHA256=0aea98bf167d3bee0514cab2be386d5cbc6d7dafd9f6da8cdc7e7e6d8002a801
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
ZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi44MjRmMjZlCi0tLSAvZGV2L251bGwKKysrIGIv
YXBwL2d1aS9Dcmltc29uR2xhc3NCYWNrZHJvcC5xbWwKQEAgLTAsMCArMSwyMSBAQAoraW1wb3J0
IFF0UXVpY2sgMi45CitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBFY2xpcHNl
UHJvZmlsZXMgMS4wCitSZWN0YW5nbGUgeworICAgIGNvbG9yOiBWYlRva2Vucy5iZ1dpbmRvdwor
ICAgIGNsaXA6IHRydWUKKyAgICBJbWFnZSB7CisgICAgICAgIGlkOiB3YWxscGFwZXI7YW5jaG9y
cy5maWxsOnBhcmVudDtzb3VyY2U6RWNsaXBzZVByb2ZpbGVzLmJhY2tncm91bmQ7ZmlsbE1vZGU6
SW1hZ2UuUHJlc2VydmVBc3BlY3RDcm9wCisgICAgICAgIGFzeW5jaHJvbm91czp0cnVlO2NhY2hl
OmZhbHNlO3NvdXJjZVNpemUud2lkdGg6MjU2MDtzb3VyY2VTaXplLmhlaWdodDoyNTYwCisgICAg
ICAgIENvbm5lY3Rpb25zIHsgdGFyZ2V0OkVjbGlwc2VQcm9maWxlcztmdW5jdGlvbiBvbkFwcGVh
cmFuY2VDaGFuZ2VkKCl7dmFyIHVybD1FY2xpcHNlUHJvZmlsZXMuYmFja2dyb3VuZDt3YWxscGFw
ZXIuc291cmNlPSIiO3dhbGxwYXBlci5zb3VyY2U9dXJsfSB9CisgICAgfQorICAgIFJlY3Rhbmds
ZSB7IGFuY2hvcnMuZmlsbDpwYXJlbnQ7Y29sb3I6VmJUb2tlbnMuYmdXaW5kb3c7b3BhY2l0eTpN
YXRoLm1heChFY2xpcHNlUHJvZmlsZXMuaGlnaENvbnRyYXN0PzAuODowLEVjbGlwc2VQcm9maWxl
cy5iYWNrZ3JvdW5kRGltLzEwMCkgfQorICAgIFJlY3RhbmdsZSB7CisgICAgICAgIHdpZHRoOiBN
YXRoLm1pbihwYXJlbnQud2lkdGgqMC43Miw4NTApOyBoZWlnaHQ6IHdpZHRoOyByYWRpdXM6IHdp
ZHRoLzIKKyAgICAgICAgeDogcGFyZW50LndpZHRoLXdpZHRoKjAuNjI7IHk6IC1oZWlnaHQqMC41
NQorICAgICAgICBjb2xvcjogUXQucmdiYShWYlRva2Vucy5hY2NlbnQucixWYlRva2Vucy5hY2Nl
bnQuZyxWYlRva2Vucy5hY2NlbnQuYiwwLjAzNSkKKyAgICAgICAgYm9yZGVyLmNvbG9yOiBRdC5y
Z2JhKFZiVG9rZW5zLmFjY2VudC5yLFZiVG9rZW5zLmFjY2VudC5nLFZiVG9rZW5zLmFjY2VudC5i
LDAuMTUpOyBib3JkZXIud2lkdGg6IDIKKyAgICB9CisgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy5m
aWxsOnBhcmVudDsgZ3JhZGllbnQ6R3JhZGllbnQgeyBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjow
O2NvbG9yOiIjMDAwMDAwMDAiIH0KKyAgICAgICAgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246MTtj
b2xvcjpWYlRva2Vucy5iZ1dpbmRvdyB9IH0gfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9Dcmlt
c29uR2xhc3NQYW5lbC5xbWwgYi9hcHAvZ3VpL0NyaW1zb25HbGFzc1BhbmVsLnFtbApuZXcgZmls
ZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5lOWIzMzNjCi0tLSAvZGV2L251bGwKKysrIGIv
YXBwL2d1aS9Dcmltc29uR2xhc3NQYW5lbC5xbWwKQEAgLTAsMCArMSwxMyBAQAoraW1wb3J0IFF0
UXVpY2sgMi45CitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK1JlY3RhbmdsZSB7CisgICAg
aWQ6Z2xhc3MKKyAgICByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0NhcmQKKyAgICBjb2xvcjogVmJU
b2tlbnMuYmdFbGV2CisgICAgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UKKyAgICBncmFk
aWVudDogR3JhZGllbnQgeworICAgICAgICBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjogMDsgY29s
b3I6IFF0LnJnYmEoUXQubGlnaHRlcihnbGFzcy5jb2xvciwxLjM1KS5yLFF0LmxpZ2h0ZXIoZ2xh
c3MuY29sb3IsMS4zNSkuZyxRdC5saWdodGVyKGdsYXNzLmNvbG9yLDEuMzUpLmIsVmJUb2tlbnMu
Z2xhc3NPcGFjaXR5KSB9CisgICAgICAgIEdyYWRpZW50U3RvcCB7IHBvc2l0aW9uOiAxOyBjb2xv
cjogUXQucmdiYShnbGFzcy5jb2xvci5yLGdsYXNzLmNvbG9yLmcsZ2xhc3MuY29sb3IuYixWYlRv
a2Vucy5nbGFzc09wYWNpdHkpIH0KKyAgICB9CisgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy50b3A6
IHBhcmVudC50b3A7IGFuY2hvcnMudG9wTWFyZ2luOiAxOyBhbmNob3JzLmhvcml6b250YWxDZW50
ZXI6IHBhcmVudC5ob3Jpem9udGFsQ2VudGVyOyB3aWR0aDogTWF0aC5tYXgoMCxwYXJlbnQud2lk
dGgtMipwYXJlbnQucmFkaXVzKTsgaGVpZ2h0OiAxOyBjb2xvcjogVmJUb2tlbnMuZ2xhc3NFZGdl
IH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvQ3JpbXNvbkdsYXNzUmFpbC5xbWwgYi9hcHAvZ3Vp
L0NyaW1zb25HbGFzc1JhaWwucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAu
LmUxYTRjNWIKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0NyaW1zb25HbGFzc1JhaWwucW1s
CkBAIC0wLDAgKzEsMjMgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29u
dHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0IFZpYmVtaXMuUmVk
ZXNpZ24gMS4wCitDcmltc29uR2xhc3NQYW5lbCB7CisgICAgaWQ6cmFpbAorICAgIHByb3BlcnR5
IGJvb2wgaW5MaWJyYXJ5OmZhbHNlCisgICAgc2lnbmFsIGhvbWVSZXF1ZXN0ZWQoKQorICAgIHNp
Z25hbCBzZXR0aW5nc1JlcXVlc3RlZCgpCisgICAgc2lnbmFsIGNvbnRyb2xzUmVxdWVzdGVkKCkK
KyAgICBDb2x1bW5MYXlvdXQgeworICAgICAgICBhbmNob3JzLnRvcDpwYXJlbnQudG9wO2FuY2hv
cnMubGVmdDpwYXJlbnQubGVmdDthbmNob3JzLnJpZ2h0OnBhcmVudC5yaWdodDthbmNob3JzLnRv
cE1hcmdpbjoxMDthbmNob3JzLmxlZnRNYXJnaW46NDthbmNob3JzLnJpZ2h0TWFyZ2luOjQ7c3Bh
Y2luZzoxMgorICAgICAgICBJbWFnZSB7IHNvdXJjZToicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2
ZyI7TGF5b3V0LmFsaWdubWVudDpRdC5BbGlnbkhDZW50ZXI7TGF5b3V0LnByZWZlcnJlZFdpZHRo
OjM4O0xheW91dC5wcmVmZXJyZWRIZWlnaHQ6MzggfQorICAgICAgICBSZXBlYXRlciB7CisgICAg
ICAgICAgICBtb2RlbDpbe2xhYmVsOnFzVHIoIkhvbWUiKSxpY29uOiJxcmM6L3Jlcy9jcmltc29u
LWhvc3Quc3ZnIixhY3Rpb246ImhvbWUifSx7bGFiZWw6cXNUcigiQ29udHJvbHMiKSxpY29uOiJx
cmM6L3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZyIsYWN0aW9uOiJjb250cm9scyJ9LHtsYWJlbDpx
c1RyKCJTZXR0aW5ncyIpLGljb246InFyYzovcmVzL3NldHRpbmdzLnN2ZyIsYWN0aW9uOiJzZXR0
aW5ncyJ9XQorICAgICAgICAgICAgZGVsZWdhdGU6IEVjbGlwc2VBY3Rpb25CdXR0b24geworICAg
ICAgICAgICAgICAgIG9iamVjdE5hbWU6ImNyaW1zb25SYWlsQnV0dG9uIjtMYXlvdXQuZmlsbFdp
ZHRoOnRydWU7aW1wbGljaXRXaWR0aDo1NjtpbXBsaWNpdEhlaWdodDo1Njt0ZXh0OiIiO2ljb25T
b3VyY2U6bW9kZWxEYXRhLmljb24KKyAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6bW9k
ZWxEYXRhLmxhYmVsO1Rvb2xUaXAudGV4dDptb2RlbERhdGEubGFiZWw7VG9vbFRpcC52aXNpYmxl
OmhvdmVyZWR8fGFjdGl2ZUZvY3VzCisgICAgICAgICAgICAgICAgb25DbGlja2VkOiB7aWYobW9k
ZWxEYXRhLmFjdGlvbj09PSJob21lIilyYWlsLmhvbWVSZXF1ZXN0ZWQoKTtlbHNlIGlmKG1vZGVs
RGF0YS5hY3Rpb249PT0iY29udHJvbHMiKXJhaWwuY29udHJvbHNSZXF1ZXN0ZWQoKTtlbHNlIHJh
aWwuc2V0dGluZ3NSZXF1ZXN0ZWQoKX0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgIH0K
K30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvQ3JpbXNvbkhvc3RQYW5lbC5xbWwgYi9hcHAvZ3VpL0Ny
aW1zb25Ib3N0UGFuZWwucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjI0
NjJmMTIKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0NyaW1zb25Ib3N0UGFuZWwucW1sCkBA
IC0wLDAgKzEsMzIgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJv
bHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0IFZpYmVtaXMuUmVkZXNp
Z24gMS4wCitpbXBvcnQgU3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCitDcmltc29uR2xhc3NQYW5l
bCB7CisgICAgaWQ6cGFuZWwKKyAgICBwcm9wZXJ0eSBzdHJpbmcgaG9zdE5hbWU6IiIKKyAgICBw
cm9wZXJ0eSBzdHJpbmcgaG9zdFR5cGU6IiIKKyAgICBwcm9wZXJ0eSBzdHJpbmcgdHJhbnNwb3J0
OiIiCisgICAgcHJvcGVydHkgYm9vbCBvbmxpbmU6ZmFsc2UKKyAgICBwcm9wZXJ0eSB2YXIgaG9z
dDooe30pCisgICAgc2lnbmFsIGhvc3RSZXF1ZXN0ZWQoKQorICAgIFNjcm9sbFZpZXcgeworICAg
ICAgICBhbmNob3JzLmZpbGw6cGFyZW50O2FuY2hvcnMubWFyZ2luczoxNjtjb250ZW50V2lkdGg6
YXZhaWxhYmxlV2lkdGg7Y2xpcDp0cnVlCisgICAgICAgIENvbHVtbkxheW91dCB7CisgICAgICAg
ICAgICB3aWR0aDpwYXJlbnQud2lkdGg7c3BhY2luZzoxNgorICAgICAgICAgICAgSW1hZ2UgeyBz
b3VyY2U6InFyYzovcmVzL2VjbGlwc2UtaWNvbi5zdmciO0xheW91dC5wcmVmZXJyZWRIZWlnaHQ6
NjQ7TGF5b3V0LnByZWZlcnJlZFdpZHRoOjY0O0xheW91dC5hbGlnbm1lbnQ6UXQuQWxpZ25IQ2Vu
dGVyIH0KKyAgICAgICAgICAgIExhYmVsIHsgdGV4dDpwYW5lbC5ob3N0TmFtZTtmb250LmZhbWls
eTpWYlRva2Vucy5mb250RGlzcGxheTtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlSGVhZGlu
Zztmb250LmJvbGQ6dHJ1ZTtjb2xvcjpWYlRva2Vucy50ZXh0O0xheW91dC5maWxsV2lkdGg6dHJ1
ZTt3cmFwTW9kZTpUZXh0LldyYXA7dGV4dEZvcm1hdDpUZXh0LlBsYWluVGV4dCB9CisgICAgICAg
ICAgICBMYWJlbCB7IHRleHQ6cGFuZWwub25saW5lP3FzVHIoIkNvbm5lY3RlZCBob3N0Iik6cXNU
cigiSG9zdCBvZmZsaW5lIik7Y29sb3I6cGFuZWwub25saW5lP1ZiVG9rZW5zLnN0YXR1c09ubGlu
ZTpWYlRva2Vucy50ZXh0RGltO2ZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVMYWJlbDtMYXlv
dXQuZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5XcmFwIH0KKyAgICAgICAgICAgIFJlcGVh
dGVyIHsKKyAgICAgICAgICAgICAgICBtb2RlbDpbe2xhYmVsOnFzVHIoIkhvc3QgdHlwZSIpLHZh
bHVlOnBhbmVsLmhvc3RUeXBlfHxxc1RyKCJDb21wYXRpYmxlIGhvc3QiKX0se2xhYmVsOnFzVHIo
IkNvbm5lY3Rpb24iKSx2YWx1ZTpwYW5lbC50cmFuc3BvcnR8fHFzVHIoIkNoZWNraW5nIil9LHts
YWJlbDpxc1RyKCJSZXF1ZXN0ZWQgcmVzb2x1dGlvbiIpLHZhbHVlOlN0cmVhbWluZ1ByZWZlcmVu
Y2VzLndpZHRoKyIgw5cgIitTdHJlYW1pbmdQcmVmZXJlbmNlcy5oZWlnaHR9LHtsYWJlbDpxc1Ry
KCJSZXF1ZXN0ZWQgZnJhbWUgcmF0ZSIpLHZhbHVlOlN0cmVhbWluZ1ByZWZlcmVuY2VzLmZwcysi
IEZQUyJ9LHtsYWJlbDpxc1RyKCJCaXRyYXRlIGxpbWl0IiksdmFsdWU6KFN0cmVhbWluZ1ByZWZl
cmVuY2VzLmJpdHJhdGVLYnBzLzEwMDApLnRvRml4ZWQoMSkrIiBNYnBzIn1dCisgICAgICAgICAg
ICAgICAgZGVsZWdhdGU6Q29sdW1uTGF5b3V0IHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO3NwYWNp
bmc6NQorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7dGV4dDptb2RlbERhdGEubGFiZWw7Zm9u
dC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUNhcHRpb247Y29sb3I6VmJUb2tlbnMudGV4dERpbTtM
YXlvdXQuZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5XcmFwfQorICAgICAgICAgICAgICAg
ICAgICBMYWJlbCB7dGV4dDptb2RlbERhdGEudmFsdWU7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMu
dHlwZUxhYmVsO2NvbG9yOlZiVG9rZW5zLnRleHQ7TGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBN
b2RlOlRleHQuV3JhcDt0ZXh0Rm9ybWF0OlRleHQuUGxhaW5UZXh0fQorICAgICAgICAgICAgICAg
IH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0
OnFzVHIoIkhvc3QgZGV0YWlscyIpO0xheW91dC5maWxsV2lkdGg6dHJ1ZTtvbkNsaWNrZWQ6cGFu
ZWwuaG9zdFJlcXVlc3RlZCgpIH0KKyAgICAgICAgICAgIExhYmVsIHsgdGV4dDpxc1RyKCJDaG9v
c2UgYW4gYXBwIHRvIHN0cmVhbS4gQWN0dWFsIG5lZ290aWF0ZWQgcXVhbGl0eSBhcHBlYXJzIGlu
IHN0cmVhbSBzdGF0aXN0aWNzLiIpO2ZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVDYXB0aW9u
O2NvbG9yOlZiVG9rZW5zLnRleHREaW07TGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRl
eHQuV3JhcCB9CisgICAgICAgIH0KKyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0NyaW1z
b25Mb2NhbFBhbmVsLnFtbCBiL2FwcC9ndWkvQ3JpbXNvbkxvY2FsUGFuZWwucW1sCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjVmZDJlZDkKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvZ3VpL0NyaW1zb25Mb2NhbFBhbmVsLnFtbApAQCAtMCwwICsxLDM2IEBACitpbXBvcnQgUXRR
dWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5
b3V0cyAxLjMKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IExvY2FsSGFyZHdh
cmUgMS4wCitDcmltc29uR2xhc3NQYW5lbCB7CisgICAgaWQ6IHBhbmVsCisgICAgcHJvcGVydHkg
Ym9vbCBhY3RpdmU6IGZhbHNlCisgICAgc2lnbmFsIGNvbnRyb2xzUmVxdWVzdGVkKCkKKyAgICBv
bkFjdGl2ZUNoYW5nZWQ6IExvY2FsSGFyZHdhcmUuc2V0Q29uc3VtZXJBY3RpdmUocGFuZWwsYWN0
aXZlKQorICAgIENvbXBvbmVudC5vbkNvbXBsZXRlZDogaWYoYWN0aXZlKSBMb2NhbEhhcmR3YXJl
LnNldENvbnN1bWVyQWN0aXZlKHBhbmVsLHRydWUpCisgICAgQ29tcG9uZW50Lm9uRGVzdHJ1Y3Rp
b246IGlmKGFjdGl2ZSkgTG9jYWxIYXJkd2FyZS5zZXRDb25zdW1lckFjdGl2ZShwYW5lbCxmYWxz
ZSkKKyAgICBmdW5jdGlvbiByZWFkaW5nKGtleSxzdWZmaXgpIHsgdmFyIHY9TG9jYWxIYXJkd2Fy
ZS5yZWFkaW5nc1trZXldO3JldHVybiB2PT09dW5kZWZpbmVkP3FzVHIoIlVuYXZhaWxhYmxlIik6
TnVtYmVyKHYpLnRvRml4ZWQoMSkrKHN1ZmZpeHx8IiIpIH0KKyAgICBTY3JvbGxWaWV3IHsKKyAg
ICAgICAgYW5jaG9ycy5maWxsOnBhcmVudDthbmNob3JzLm1hcmdpbnM6MTY7Y29udGVudFdpZHRo
OmF2YWlsYWJsZVdpZHRoO2NsaXA6dHJ1ZQorICAgICAgICBDb2x1bW5MYXlvdXQgeworICAgICAg
ICAgICAgd2lkdGg6cGFyZW50LndpZHRoO3NwYWNpbmc6MTIKKyAgICAgICAgICAgIExhYmVsIHsg
dGV4dDpxc1RyKCJMb2NhbCBTeXN0ZW0iKTtmb250LmZhbWlseTpWYlRva2Vucy5mb250RGlzcGxh
eTtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTtmb250LmJvbGQ6dHJ1ZTtjb2xvcjpW
YlRva2Vucy50ZXh0O0xheW91dC5maWxsV2lkdGg6dHJ1ZTtlbGlkZTpUZXh0LkVsaWRlUmlnaHQg
fQorICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OnFzVHIoIkVjbGlwc2VPUyBjb25zb2xlIik7Zm9u
dC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUNhcHRpb247Y29sb3I6VmJUb2tlbnMudGV4dERpbTtM
YXlvdXQuZmlsbFdpZHRoOnRydWU7ZWxpZGU6VGV4dC5FbGlkZVJpZ2h0IH0KKyAgICAgICAgICAg
IFJlcGVhdGVyIHsKKyAgICAgICAgICAgICAgICBtb2RlbDpbe2xhYmVsOnFzVHIoIkNQVSIpLGtl
eToiY3B1UGVyY2VudCIsc3VmZml4OiIlIixtYXg6MTAwfSx7bGFiZWw6cXNUcigiUkFNIiksa2V5
OiJtZW1vcnlQZXJjZW50IixzdWZmaXg6IiUiLG1heDoxMDB9LHtsYWJlbDpxc1RyKCJUZW1wZXJh
dHVyZSIpLGtleToidGVtcGVyYXR1cmVDIixzdWZmaXg6IiDCsEMiLG1heDoxMDB9LHtsYWJlbDpx
c1RyKCJOZXR3b3JrIGRvd25sb2FkIiksa2V5OiJyZWNlaXZlTWlCIixzdWZmaXg6IiBNaUIvcyIs
bWF4OjB9XQorICAgICAgICAgICAgICAgIGRlbGVnYXRlOkNyaW1zb25HbGFzc1BhbmVsIHsKKyAg
ICAgICAgICAgICAgICAgICAgb2JqZWN0TmFtZToiY3JpbXNvbk1ldHJpYyI7TGF5b3V0LmZpbGxX
aWR0aDp0cnVlO2ltcGxpY2l0SGVpZ2h0Ok1hdGgubWF4KDkyLFZiVG9rZW5zLnR5cGVCb2R5KjMr
MjQpCisgICAgICAgICAgICAgICAgICAgIENvbHVtbkxheW91dCB7CisgICAgICAgICAgICAgICAg
ICAgICAgICBhbmNob3JzLmZpbGw6cGFyZW50O2FuY2hvcnMubWFyZ2luczoxMjtzcGFjaW5nOjUK
KyAgICAgICAgICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDptb2RlbERhdGEubGFiZWw7Zm9u
dC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUxhYmVsO2NvbG9yOlZiVG9rZW5zLnRleHREaW07TGF5
b3V0LmZpbGxXaWR0aDp0cnVlO2VsaWRlOlRleHQuRWxpZGVSaWdodCB9CisgICAgICAgICAgICAg
ICAgICAgICAgICBMYWJlbCB7IHRleHQ6cGFuZWwucmVhZGluZyhtb2RlbERhdGEua2V5LG1vZGVs
RGF0YS5zdWZmaXgpO2ZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5O2ZvbnQuYm9sZDp0
cnVlO2NvbG9yOlZiVG9rZW5zLnRleHQ7TGF5b3V0LmZpbGxXaWR0aDp0cnVlO2VsaWRlOlRleHQu
RWxpZGVSaWdodCB9CisgICAgICAgICAgICAgICAgICAgICAgICBDcmltc29uU3BhcmtsaW5lIHsg
TGF5b3V0LmZpbGxXaWR0aDp0cnVlO0xheW91dC5wcmVmZXJyZWRIZWlnaHQ6MjQ7c2FtcGxlczpM
b2NhbEhhcmR3YXJlLmhpc3Rvcnk7bWV0cmljOm1vZGVsRGF0YS5rZXk7Y2VpbGluZzptb2RlbERh
dGEubWF4IH0KKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIH0KKyAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIlN5
c3RlbSBDb250cm9scyIpO0xheW91dC5maWxsV2lkdGg6dHJ1ZTtvbkNsaWNrZWQ6cGFuZWwuY29u
dHJvbHNSZXF1ZXN0ZWQoKSB9CisgICAgICAgICAgICBMYWJlbCB7IHRleHQ6cXNUcigiTG9jYWwg
cmVhZGluZ3Mg4oCiIG1pc3Npbmcgc2Vuc29ycyBzaG93IFVuYXZhaWxhYmxlIik7Zm9udC5waXhl
bFNpemU6VmJUb2tlbnMudHlwZUNhcHRpb247Y29sb3I6VmJUb2tlbnMudGV4dERpbTtMYXlvdXQu
ZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5XcmFwIH0KKyAgICAgICAgfQorICAgIH0KK30K
ZGlmZiAtLWdpdCBhL2FwcC9ndWkvQ3JpbXNvblNwYXJrbGluZS5xbWwgYi9hcHAvZ3VpL0NyaW1z
b25TcGFya2xpbmUucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjQzZGQz
YjQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0NyaW1zb25TcGFya2xpbmUucW1sCkBAIC0w
LDAgKzEsMjUgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24g
MS4wCitDYW52YXMgeworICAgIGlkOiBncmFwaAorICAgIHByb3BlcnR5IHZhciBzYW1wbGVzOiBb
XQorICAgIHByb3BlcnR5IHN0cmluZyBtZXRyaWM6ICJjcHVQZXJjZW50IgorICAgIHByb3BlcnR5
IHJlYWwgY2VpbGluZzogMTAwCisgICAgcHJvcGVydHkgY29sb3IgbGluZUNvbG9yOiBWYlRva2Vu
cy5hY2NlbnQKKyAgICBvblNhbXBsZXNDaGFuZ2VkOiByZXF1ZXN0UGFpbnQoKQorICAgIG9uTWV0
cmljQ2hhbmdlZDogcmVxdWVzdFBhaW50KCkKKyAgICBvbkxpbmVDb2xvckNoYW5nZWQ6IHJlcXVl
c3RQYWludCgpCisgICAgb25XaWR0aENoYW5nZWQ6IHJlcXVlc3RQYWludCgpCisgICAgb25IZWln
aHRDaGFuZ2VkOiByZXF1ZXN0UGFpbnQoKQorICAgIG9uUGFpbnQ6IHsKKyAgICAgICAgdmFyIGM9
Z2V0Q29udGV4dCgiMmQiKTtjLmNsZWFyUmVjdCgwLDAsd2lkdGgsaGVpZ2h0KQorICAgICAgICB2
YXIgaGlnaD1jZWlsaW5nCisgICAgICAgIGlmKGhpZ2g8PTApIHsgaGlnaD0xO2Zvcih2YXIgaj0w
O2o8c2FtcGxlcy5sZW5ndGg7aisrKSB7IHZhciBuPXNhbXBsZXNbal1bbWV0cmljXTtpZihuIT09
dW5kZWZpbmVkJiZpc0Zpbml0ZShuKSloaWdoPU1hdGgubWF4KGhpZ2gsbikgfSB9CisgICAgICAg
IGMuc3Ryb2tlU3R5bGU9bGluZUNvbG9yO2MubGluZVdpZHRoPTEuNTtjLmJlZ2luUGF0aCgpO3Zh
ciBzdGFydGVkPWZhbHNlCisgICAgICAgIGZvcih2YXIgaT0wO2k8c2FtcGxlcy5sZW5ndGg7aSsr
KSB7IHZhciB2PXNhbXBsZXNbaV1bbWV0cmljXTtpZih2PT09dW5kZWZpbmVkfHwhaXNGaW5pdGUo
dikpe3N0YXJ0ZWQ9ZmFsc2U7Y29udGludWV9CisgICAgICAgICAgICB2YXIgeD0yKyh3aWR0aC00
KSooNjAtc2FtcGxlcy5sZW5ndGgraSkvNTkseT1oZWlnaHQtMi0oaGVpZ2h0LTQpKk1hdGgubWF4
KDAsTWF0aC5taW4oaGlnaCx2KSkvaGlnaAorICAgICAgICAgICAgaWYoIXN0YXJ0ZWQpYy5tb3Zl
VG8oeCx5KTtlbHNlIGMubGluZVRvKHgseSk7c3RhcnRlZD10cnVlCisgICAgICAgIH0KKyAgICAg
ICAgYy5zdHJva2UoKQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvQ3JpbXNvblN0YXR1
c0RpYWxvZy5xbWwgYi9hcHAvZ3VpL0NyaW1zb25TdGF0dXNEaWFsb2cucW1sCm5ldyBmaWxlIG1v
ZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmExZDQ2NzIKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAv
Z3VpL0NyaW1zb25TdGF0dXNEaWFsb2cucW1sCkBAIC0wLDAgKzEsOTAgQEAKK2ltcG9ydCBRdFF1
aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlv
dXRzIDEuMworaW1wb3J0IFF0UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmli
ZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBDcmltc29uU3RhdHVzIDEuMAorCitOYXZpZ2FibGVE
aWFsb2cgeworICAgIGlkOiBwYW5lbAorICAgIHByb3BlcnR5IHN0cmluZyBraW5kOiAiaG9zdCIK
KyAgICB3aWR0aDogTWF0aC5taW4oNjIwLCBwYXJlbnQud2lkdGggLSAzMikKKyAgICBoZWlnaHQ6
IE1hdGgubWluKGtpbmQgPT09ICJob3N0IiA/IDY1MCA6IDI4MCwgcGFyZW50LmhlaWdodCAtIDMy
KQorICAgIHRpdGxlOiBraW5kID09PSAiaG9zdCIgPyBxc1RyKCJWaWJlcG9sbG8g4oCiIEhvc3Qg
aGFyZHdhcmUiKSA6IGtpbmQgPT09ICJuZXR3b3JrIiA/IHFzVHIoIk5ldHdvcmsgc3RhdHVzIikg
OiBxc1RyKCJCYXR0ZXJ5IHN0YXR1cyIpCisgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuQ2xv
c2UKKyAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICBNYXRlcmlh
bC5hY2NlbnQ6IFZiVG9rZW5zLmFjY2VudAorICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1Bh
bmVsIHsgY29sb3I6IFZiVG9rZW5zLmJnRWxldjsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNEaWFs
b2c7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlOyBib3JkZXIud2lkdGg6IDEgfQorICAg
IG9uT3BlbmVkOiB7CisgICAgICAgIHVybElucHV0LnRleHQgPSBDcmltc29uU3RhdHVzLmVuZHBv
aW50CisgICAgICAgIHBpbklucHV0LnRleHQgPSBDcmltc29uU3RhdHVzLmZpbmdlcnByaW50Cisg
ICAgICAgIHRva2VuSW5wdXQudGV4dCA9ICIiCisgICAgICAgIENyaW1zb25TdGF0dXMuc2V0Vmlz
aWJsZShraW5kID09PSAiaG9zdCIpCisgICAgfQorICAgIG9uQ2xvc2VkOiB7IENyaW1zb25TdGF0
dXMuc2V0VmlzaWJsZShmYWxzZSk7IHRva2VuSW5wdXQudGV4dCA9ICIiOyBzdGFja1ZpZXcuZm9y
Y2VBY3RpdmVGb2N1cygpIH0KKyAgICBmdW5jdGlvbiBtZXRyaWMoa2V5LCBzdWZmaXgpIHsKKyAg
ICAgICAgdmFyIG4gPSBDcmltc29uU3RhdHVzLnN0YXRzW2tleV0KKyAgICAgICAgcmV0dXJuIG4g
PT09IHVuZGVmaW5lZCA/IHFzVHIoIk4vQSIpIDogTnVtYmVyKG4pLnRvRml4ZWQoMSkgKyBzdWZm
aXgKKyAgICB9CisgICAgZnVuY3Rpb24gbWVtb3J5KHByZWZpeCkgeworICAgICAgICB2YXIgcyA9
IENyaW1zb25TdGF0dXMuc3RhdHMKKyAgICAgICAgcmV0dXJuIHNbcHJlZml4ICsgIl91c2VkX2J5
dGVzIl0gPT09IHVuZGVmaW5lZCB8fCAhc1twcmVmaXggKyAiX3RvdGFsX2J5dGVzIl0gPyBxc1Ry
KCJOL0EiKQorICAgICAgICAgICAgIDogKHNbcHJlZml4ICsgIl91c2VkX2J5dGVzIl0gLyAxMDcz
NzQxODI0KS50b0ZpeGVkKDEpICsgIiAvICIgKyAoc1twcmVmaXggKyAiX3RvdGFsX2J5dGVzIl0g
LyAxMDczNzQxODI0KS50b0ZpeGVkKDEpICsgIiBHaUIiCisgICAgfQorICAgIGNvbnRlbnRJdGVt
OiBTY3JvbGxWaWV3IHsKKyAgICAgICAgY2xpcDogdHJ1ZQorICAgICAgICBjb250ZW50V2lkdGg6
IGF2YWlsYWJsZVdpZHRoCisgICAgICAgIENvbHVtbkxheW91dCB7CisgICAgICAgICAgICB3aWR0
aDogcGFuZWwuYXZhaWxhYmxlV2lkdGgKKyAgICAgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNw
YWNlMworICAgICAgICAgICAgTGFiZWwgeworICAgICAgICAgICAgICAgIHZpc2libGU6IHBhbmVs
LmtpbmQgIT09ICJob3N0IgorICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7
IHdyYXBNb2RlOiBUZXh0LldyYXAKKyAgICAgICAgICAgICAgICB0ZXh0OiBwYW5lbC5raW5kID09
PSAibmV0d29yayIgPyAoQ3JpbXNvblN0YXR1cy5sb2NhbC5uZXR3b3JrICsgKENyaW1zb25TdGF0
dXMubG9jYWwud2lmaVNpZ25hbCA+PSAwID8gIiDigKIgIiArIENyaW1zb25TdGF0dXMubG9jYWwu
d2lmaVNpZ25hbCArICIlIHNpZ25hbCIgOiAiIikgKyAiXG4iICsgcXNUcigiQWN0aXZlIGxpbmsg
c3RhdHVzOyBpbnRlcm5ldCBhY2Nlc3MgaXMgbm90IGFzc3VtZWQuIikpCisgICAgICAgICAgICAg
ICAgICAgIDogKENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVBlcmNlbnQgPj0gMCA/IENyaW1z
b25TdGF0dXMubG9jYWwuYmF0dGVyeVBlcmNlbnQgKyAiJSDigKIgIiA6ICIiKSArIENyaW1zb25T
dGF0dXMubG9jYWwuYmF0dGVyeVN0YXRlCisgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5z
LnRleHQ7IGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQm9keQorICAgICAgICAgICAgfQor
ICAgICAgICAgICAgTGFiZWwgeworICAgICAgICAgICAgICAgIHZpc2libGU6IHBhbmVsLmtpbmQg
PT09ICJob3N0IgorICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBN
b2RlOiBUZXh0LldyYXAKKyAgICAgICAgICAgICAgICB0ZXh0OiBDcmltc29uU3RhdHVzLnN0YXR1
cworICAgICAgICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy50ZXh0RGltCisgICAgICAgICAgICB9
CisgICAgICAgICAgICBSZXBlYXRlciB7CisgICAgICAgICAgICAgICAgbW9kZWw6IHBhbmVsLmtp
bmQgPT09ICJob3N0IiA/IFsKKyAgICAgICAgICAgICAgICAgICAgW3FzVHIoIkNQVSIpLCBwYW5l
bC5tZXRyaWMoImNwdV9wZXJjZW50IiwgIiUiKSwgcGFuZWwubWV0cmljKCJjcHVfdGVtcF9jIiwg
IiDCsEMiKV0sCisgICAgICAgICAgICAgICAgICAgIFtxc1RyKCJSQU0iKSwgcGFuZWwubWVtb3J5
KCJyYW0iKSwgcGFuZWwubWV0cmljKCJyYW1fcGVyY2VudCIsICIlIildLAorICAgICAgICAgICAg
ICAgICAgICBbcXNUcigiR1BVIiksIHBhbmVsLm1ldHJpYygiZ3B1X3BlcmNlbnQiLCAiJSIpLCBw
YW5lbC5tZXRyaWMoImdwdV90ZW1wX2MiLCAiIMKwQyIpXSwKKyAgICAgICAgICAgICAgICAgICAg
W3FzVHIoIlZSQU0iKSwgcGFuZWwubWVtb3J5KCJ2cmFtIiksIHBhbmVsLm1ldHJpYygidnJhbV9w
ZXJjZW50IiwgIiUiKV0sCisgICAgICAgICAgICAgICAgICAgIFtxc1RyKCJHUFUgZW5jb2RlciIp
LCBwYW5lbC5tZXRyaWMoImdwdV9lbmNvZGVyX3BlcmNlbnQiLCAiJSIpLCAiIl0sCisgICAgICAg
ICAgICAgICAgICAgIFtxc1RyKCJIb3N0IG5ldHdvcmsiKSwgcGFuZWwubWV0cmljKCJuZXRfcnhf
YnBzIiwgIiBCL3MgUlgiKSwgcGFuZWwubWV0cmljKCJuZXRfdHhfYnBzIiwgIiBCL3MgVFgiKV0K
KyAgICAgICAgICAgICAgICBdIDogW10KKyAgICAgICAgICAgICAgICBkZWxlZ2F0ZTogUmVjdGFu
Z2xlIHsKKyAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgaW1wbGlj
aXRIZWlnaHQ6IDU4CisgICAgICAgICAgICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy5iZ1dpbmRv
dzsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDb250cm9sCisgICAgICAgICAgICAgICAgICAgIGJv
cmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlOyBib3JkZXIud2lkdGg6IDEKKyAgICAgICAgICAg
ICAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgICAgIGFuY2hvcnMuZmls
bDogcGFyZW50OyBhbmNob3JzLm1hcmdpbnM6IDEyCisgICAgICAgICAgICAgICAgICAgICAgICBM
YWJlbCB7IHRleHQ6IG1vZGVsRGF0YVswXTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW07IExheW91
dC5wcmVmZXJyZWRXaWR0aDogMTE1IH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExhYmVsIHsg
dGV4dDogbW9kZWxEYXRhWzFdOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgTGF5b3V0LmZpbGxXaWR0
aDogdHJ1ZSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IG1vZGVsRGF0
YVsyXTsgY29sb3I6IFZiVG9rZW5zLmFjY2VudCB9CisgICAgICAgICAgICAgICAgICAgIH0KKyAg
ICAgICAgICAgICAgICB9CisgICAgICAgICAgICB9CisgICAgICAgICAgICBHcm91cEJveCB7Cisg
ICAgICAgICAgICAgICAgdmlzaWJsZTogcGFuZWwua2luZCA9PT0gImhvc3QiCisgICAgICAgICAg
ICAgICAgdGl0bGU6IHFzVHIoIkNvbmZpZ3VyZSBob3N0IHN0YXRzIikKKyAgICAgICAgICAgICAg
ICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisgICAgICAgICAgICAgICAgQ29sdW1uTGF5b3V0IHsK
KyAgICAgICAgICAgICAgICAgICAgYW5jaG9ycy5maWxsOiBwYXJlbnQKKyAgICAgICAgICAgICAg
ICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFw
OyB0ZXh0OiBxc1RyKCJTZWxlY3QgYSBob3N0IGZpcnN0LiBFbmFibGUgcmVhbHRpbWUgc3RhdHMg
aW4gVmliZXBvbGxvIGFuZCBjcmVhdGUgYSByZWFkLW9ubHkgdG9rZW4gZm9yIEdFVCAvYXBpL2hv
c3Qvc3RhdHMuIEdhbWVTdHJlYW0gcGFpcmluZyBkb2VzIG5vdCBncmFudCB0aGlzIGFjY2Vzcy4i
KTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgICAgICAgICBUZXh0Rmll
bGQgeyBpZDogdXJsSW5wdXQ7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHBsYWNlaG9sZGVyVGV4
dDogcXNUcigiSFRUUFMgaG9zdCBVUkwsIGUuZy4gaHR0cHM6Ly8xOTIuMTY4LjEuMTA6NDc5OTAi
KTsgc2VsZWN0QnlNb3VzZTogdHJ1ZSB9CisgICAgICAgICAgICAgICAgICAgIFRleHRGaWVsZCB7
IGlkOiB0b2tlbklucHV0OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBwbGFjZWhvbGRlclRleHQ6
IHFzVHIoIlJlYWQtb25seSBBUEkgdG9rZW4gKGJsYW5rIGtlZXBzIHNhdmVkIHRva2VuKSIpOyBl
Y2hvTW9kZTogVGV4dElucHV0LlBhc3N3b3JkOyBzZWxlY3RCeU1vdXNlOiB0cnVlIH0KKyAgICAg
ICAgICAgICAgICAgICAgVGV4dEZpZWxkIHsgaWQ6IHBpbklucHV0OyBMYXlvdXQuZmlsbFdpZHRo
OiB0cnVlOyBwbGFjZWhvbGRlclRleHQ6IHFzVHIoIlNIQS0yNTYgY2VydGlmaWNhdGUgZmluZ2Vy
cHJpbnQgZm9yIGEgc2VsZi1zaWduZWQgaG9zdCIpOyBzZWxlY3RCeU1vdXNlOiB0cnVlIH0KKyAg
ICAgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9k
ZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJWZXJpZnkgYSBzZWxmLXNpZ25lZCBjZXJ0aWZpY2F0
ZSdzIFNIQS0yNTYgZmluZ2VycHJpbnQgb24gdGhlIGhvc3QgYmVmb3JlIHNhdmluZyBpdC4gVG9r
ZW4gaXMgc3RvcmVkIHByaXZhdGVseSBvbiB0aGlzIFVTQjsgaXQgaXMgbm90IGVuY3J5cHRlZC4g
VW5zdXBwb3J0ZWQgb3IgbWlzc2luZyBzZW5zb3JzIHNob3cgTi9BLiIpOyBjb2xvcjogVmJUb2tl
bnMudGV4dERpbSB9CisgICAgICAgICAgICAgICAgICAgIEJ1dHRvbiB7IHRleHQ6IHFzVHIoIlNh
dmUgJiBjb25uZWN0Iik7IG9uQ2xpY2tlZDogeyBpZiAoQ3JpbXNvblN0YXR1cy5jb25maWd1cmUo
dXJsSW5wdXQudGV4dCwgdG9rZW5JbnB1dC50ZXh0LCBwaW5JbnB1dC50ZXh0KSkgdG9rZW5JbnB1
dC50ZXh0ID0gIiIgfSB9CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgfQorICAgICAg
ICB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlQWJvdXREaWFsb2cucW1s
IGIvYXBwL2d1aS9FY2xpcHNlQWJvdXREaWFsb2cucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0Cmlu
ZGV4IDAwMDAwMDAuLmZiZDBhM2YKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0VjbGlwc2VB
Ym91dERpYWxvZy5xbWwKQEAgLTAsMCArMSwzNCBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBv
cnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkxheW91dHMgMS4zCitpbXBv
cnQgUXRRdWljay5Db250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWdu
IDEuMAorTmF2aWdhYmxlRGlhbG9nIHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9wZXJ0eSB2YXIg
aW5mbzogKHt9KQorICAgIHdpZHRoOiBNYXRoLm1pbig1MjAscGFyZW50LndpZHRoLTMyKQorICAg
IHRpdGxlOiBxc1RyKCJBYm91dCBFY2xpcHNlIikKKyAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxv
Zy5DbG9zZQorICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgIE1h
dGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAgYmFja2dyb3VuZDogQ3JpbXNvbkds
YXNzUGFuZWwgeyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0RpYWxvZzsgY29sb3I6IFZiVG9rZW5z
LmJnRWxldjsgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UKKyAgICAgICAgUmVjdGFuZ2xl
IHsgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGNvbG9yOiAidHJhbnNwYXJlbnQiOyBncmFkaWVudDog
R3JhZGllbnQgeyBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjogMDsgY29sb3I6IFF0LnJnYmEoMSwx
LDEsMC4wMzUpIH0gR3JhZGllbnRTdG9wIHsgcG9zaXRpb246IDE7IGNvbG9yOiAidHJhbnNwYXJl
bnQiIH0gfSB9CisgICAgfQorICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAgICAg
ICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICAgICAgSW1hZ2UgeyBzb3VyY2U6ICJxcmM6
L3Jlcy9lY2xpcHNlLWljb24uc3ZnIjsgc291cmNlU2l6ZS53aWR0aDogOTY7IHNvdXJjZVNpemUu
aGVpZ2h0OiA5NjsgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25IQ2VudGVyOyBMYXlvdXQucHJl
ZmVycmVkV2lkdGg6IDk2OyBMYXlvdXQucHJlZmVycmVkSGVpZ2h0OiA5NiB9CisgICAgICAgIExh
YmVsIHsgdGV4dDogIkVDTElQU0UiOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5mYW1pbHk6
IFZiVG9rZW5zLmZvbnREaXNwbGF5OyBmb250LnBpeGVsU2l6ZTogMjQ7IGZvbnQubGV0dGVyU3Bh
Y2luZzogNDsgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25IQ2VudGVyIH0KKyAgICAgICAgTGFi
ZWwgeyB0ZXh0OiBxc1RyKCJNYWRlIGJ5IFRoM0QzY2szciIpOyBjb2xvcjogVmJUb2tlbnMuYWNj
ZW50OyBMYXlvdXQuYWxpZ25tZW50OiBRdC5BbGlnbkhDZW50ZXIgfQorICAgICAgICBMYWJlbCB7
CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0OiBUZXh0LlBs
YWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0KKyAg
ICAgICAgICAgIHRleHQ6IHFzVHIoIk9TOiAlMSAlMlxuVGFyZ2V0OiAlM1xuRmVkb3JhOiAlNFxu
S2VybmVsOiAlNVxuRWNsaXBzZSBmcm9udGVuZDogJTYg4oCiIGN1c3RvbWl6ZWQiKQorICAgICAg
ICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3MgfHwge30pLk5BTUUgfHwgIkVjbGlwc2VPUyIp
CisgICAgICAgICAgICAgICAgLmFyZygocGFuZWwuaW5mby5vcyB8fCB7fSkuVkVSU0lPTiB8fCBx
c1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3Mg
fHwge30pLlRBUkdFVCB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIC5h
cmcoKHBhbmVsLmluZm8ub3MgfHwge30pLkZFRE9SQSB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQor
ICAgICAgICAgICAgICAgIC5hcmcocGFuZWwuaW5mby5rZXJuZWwgfHwgcXNUcigiVW5hdmFpbGFi
bGUiKSkKKyAgICAgICAgICAgICAgICAuYXJnKFF0LmFwcGxpY2F0aW9uLnZlcnNpb24gfHwgIjAu
NS4wIikKKyAgICAgICAgfQorICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7
IHdyYXBNb2RlOiBUZXh0LldyYXA7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltOyB0ZXh0OiBxc1Ry
KCJBIGxpZ2h0d2VpZ2h0IEVjbGlwc2VPUyBmcm9udGVuZC4gQmFzZWQgb24gVmliZW1pcyBhbmQg
TW9vbmxpZ2h0OyBvcmlnaW5hbCBvcGVuLXNvdXJjZSBjcmVkaXRzIGFuZCBsaWNlbnNlcyByZW1h
aW4gYXZhaWxhYmxlIGluIFNldHRpbmdzLiBVcGRhdGVzIGFyZSBtYW5hZ2VkIGJ5IEVjbGlwc2VP
Uy4iKSB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlQWN0aW9uQnV0dG9u
LnFtbCBiL2FwcC9ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2
NDQKaW5kZXggMDAwMDAwMC4uYTgzZWYwMQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNs
aXBzZUFjdGlvbkJ1dHRvbi5xbWwKQEAgLTAsMCArMSwzNiBAQAoraW1wb3J0IFF0UXVpY2sgMi45
CitpbXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEu
MAoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMuaW1wbCAyLjUKK0J1dHRvbiB7CisgICAgaWQ6IGJ1
dHRvbgorICAgIHRvcEluc2V0OiAwOyBib3R0b21JbnNldDogMDsgbGVmdEluc2V0OiAwOyByaWdo
dEluc2V0OiAwCisgICAgcHJvcGVydHkgc3RyaW5nIGljb25Tb3VyY2U6ICIiCisgICAgaW1wbGlj
aXRIZWlnaHQ6IE1hdGgubWF4KDQ0LGNvbnRlbnRJdGVtLmltcGxpY2l0SGVpZ2h0ICsgMjApCisg
ICAgaW1wbGljaXRXaWR0aDogTWF0aC5tYXgoMTAwLCBjb250ZW50SXRlbS5pbXBsaWNpdFdpZHRo
ICsgMjgpCisgICAgcGFkZGluZzogMTIKKyAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJv
ZHkKKyAgICBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUxhYmVsCisgICAgQWNjZXNzaWJs
ZS5uYW1lOiB0ZXh0CisgICAgYWN0aXZlRm9jdXNPblRhYjogdHJ1ZQorICAgIEtleXMub25SZXR1
cm5QcmVzc2VkOiBpZiAoZW5hYmxlZCkgY2xpY2tlZCgpCisgICAgS2V5cy5vbkVudGVyUHJlc3Nl
ZDogaWYgKGVuYWJsZWQpIGNsaWNrZWQoKQorICAgIEtleXMub25SaWdodFByZXNzZWQ6IG5leHRJ
dGVtSW5Gb2N1c0NoYWluKHRydWUpLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAg
S2V5cy5vbkxlZnRQcmVzc2VkOiBuZXh0SXRlbUluRm9jdXNDaGFpbihmYWxzZSkuZm9yY2VBY3Rp
dmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICBLZXlzLm9uRG93blByZXNzZWQ6IG5leHRJdGVtSW5G
b2N1c0NoYWluKHRydWUpLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgS2V5cy5v
blVwUHJlc3NlZDogbmV4dEl0ZW1JbkZvY3VzQ2hhaW4oZmFsc2UpLmZvcmNlQWN0aXZlRm9jdXMo
UXQuVGFiRm9jdXMpCisgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgeworICAgICAg
ICByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0NvbnRyb2wKKyAgICAgICAgY29sb3I6IGJ1dHRvbi5k
b3duID8gVmJUb2tlbnMuYmdFbGV2MiA6IGJ1dHRvbi5ob3ZlcmVkID8gVmJUb2tlbnMuYmdFbGV2
MiA6IFZiVG9rZW5zLmJnV2luZG93CisgICAgICAgIGJvcmRlci53aWR0aDogYnV0dG9uLmFjdGl2
ZUZvY3VzID8gMiA6IDEKKyAgICAgICAgYm9yZGVyLmNvbG9yOiBidXR0b24uYWN0aXZlRm9jdXMg
fHwgYnV0dG9uLmhvdmVyZWQgPyBWYlRva2Vucy5hY2NlbnQgOiBWYlRva2Vucy5zdHJva2UKKyAg
ICAgICAgb3BhY2l0eTogYnV0dG9uLmVuYWJsZWQgPyAxIDogMC41CisgICAgfQorICAgIGNvbnRl
bnRJdGVtOiBJdGVtIHsKKyAgICAgICAgaW1wbGljaXRXaWR0aDogYnV0dG9uTGFiZWwuaW1wbGlj
aXRXaWR0aCArIChidXR0b24uaWNvblNvdXJjZSAhPT0gIiIgPyAyOCA6IDApCisgICAgICAgIGlt
cGxpY2l0SGVpZ2h0OiBNYXRoLm1heChidXR0b25MYWJlbC5pbXBsaWNpdEhlaWdodCwgYnV0dG9u
Lmljb25Tb3VyY2UgIT09ICIiID8gMjAgOiAwKQorICAgICAgICBvcGFjaXR5OiBidXR0b24uZW5h
YmxlZCA/IDEgOiAwLjUKKyAgICAgICAgSWNvbkltYWdlIHsgY29sb3I6IFZiVG9rZW5zLmFjY2Vu
dDsgdmlzaWJsZTogYnV0dG9uLmljb25Tb3VyY2UgIT09ICIiOyBzb3VyY2U6IGJ1dHRvbi5pY29u
U291cmNlOyB3aWR0aDogdmlzaWJsZSA/IDIwIDogMDsgaGVpZ2h0OiAyMDsgeDpidXR0b24udGV4
dC5sZW5ndGg9PT0wPyhwYXJlbnQud2lkdGgtd2lkdGgpLzI6MDsgYW5jaG9ycy52ZXJ0aWNhbENl
bnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVyIH0KKyAgICAgICAgTGFiZWwgeyBpZDpidXR0b25M
YWJlbDt0ZXh0OiBidXR0b24udGV4dDsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IGNvbG9y
OiBWYlRva2Vucy50ZXh0OyBmb250OiBidXR0b24uZm9udDt4OmJ1dHRvbi5pY29uU291cmNlICE9
PSAiIiA/IDI4IDogMDt3aWR0aDpNYXRoLm1heCgwLHBhcmVudC53aWR0aC14KTtlbGlkZTpUZXh0
LkVsaWRlUmlnaHQ7IGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRl
ciB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlQ29tYm9Cb3gucW1sIGIv
YXBwL2d1aS9FY2xpcHNlQ29tYm9Cb3gucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAw
MDAwMDAuLmY0NzZkZTEKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0VjbGlwc2VDb21ib0Jv
eC5xbWwKQEAgLTAsMCArMSwyOCBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWlj
ay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1w
b3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitDb21ib0JveCB7CisgICAgaWQ6IGNvbnRyb2wKKyAg
ICB0b3BJbnNldDogMDsgYm90dG9tSW5zZXQ6IDA7IGxlZnRJbnNldDogMDsgcmlnaHRJbnNldDog
MAorICAgIGltcGxpY2l0SGVpZ2h0OiBNYXRoLm1heCg0NCwgZm9udC5waXhlbFNpemUgKyAyNCkK
KyAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKKyAgICBmb250LnBpeGVsU2l6ZTog
VmJUb2tlbnMudHlwZUxhYmVsCisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQK
KyAgICBsZWZ0UGFkZGluZzogMTI7IHJpZ2h0UGFkZGluZzogMzYKKyAgICBiYWNrZ3JvdW5kOiBD
cmltc29uR2xhc3NQYW5lbCB7IGNvbG9yOiBWYlRva2Vucy5iZ0VsZXY7IHJhZGl1czogVmJUb2tl
bnMucmFkaXVzQ29udHJvbDsgYm9yZGVyLmNvbG9yOiBjb250cm9sLmFjdGl2ZUZvY3VzID8gVmJU
b2tlbnMuYWNjZW50IDogVmJUb2tlbnMuc3Ryb2tlOyBib3JkZXIud2lkdGg6IGNvbnRyb2wuYWN0
aXZlRm9jdXMgPyAyIDogMTsgb3BhY2l0eTogY29udHJvbC5lbmFibGVkID8gMSA6IC41IH0KKyAg
ICBjb250ZW50SXRlbTogTGFiZWwgeyB0ZXh0OiBjb250cm9sLmRpc3BsYXlUZXh0OyB0ZXh0Rm9y
bWF0OiBUZXh0LlBsYWluVGV4dDsgZm9udDogY29udHJvbC5mb250OyBjb2xvcjogVmJUb2tlbnMu
dGV4dDsgdmVydGljYWxBbGlnbm1lbnQ6IFRleHQuQWxpZ25WQ2VudGVyOyBlbGlkZTogVGV4dC5F
bGlkZVJpZ2h0OyBvcGFjaXR5OiBjb250cm9sLmVuYWJsZWQgPyAxIDogLjUgfQorICAgIGRlbGVn
YXRlOiBJdGVtRGVsZWdhdGUgeworICAgICAgICB3aWR0aDogY29udHJvbC53aWR0aAorICAgICAg
ICBpbXBsaWNpdEhlaWdodDogTWF0aC5tYXgoNDQsY29udHJvbC5mb250LnBpeGVsU2l6ZSsyNCkK
KyAgICAgICAgaGlnaGxpZ2h0ZWQ6IGNvbnRyb2wuaGlnaGxpZ2h0ZWRJbmRleCA9PT0gaW5kZXgK
KyAgICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgdGV4dDogY29udHJvbC50ZXh0QXQoaW5kZXgp
OyB0ZXh0Rm9ybWF0OlRleHQuUGxhaW5UZXh0OyBmb250OmNvbnRyb2wuZm9udDsgY29sb3I6VmJU
b2tlbnMudGV4dDsgZWxpZGU6VGV4dC5FbGlkZVJpZ2h0IH0KKyAgICAgICAgYmFja2dyb3VuZDog
Q3JpbXNvbkdsYXNzUGFuZWwgeyBjb2xvcjogcGFyZW50LmhpZ2hsaWdodGVkID8gVmJUb2tlbnMu
YmdFbGV2MiA6IFZiVG9rZW5zLmJnRWxldjsgcmFkaXVzOlZiVG9rZW5zLnJhZGl1c0NvbnRyb2w7
IGJvcmRlci5jb2xvcjpwYXJlbnQuaGlnaGxpZ2h0ZWQ/VmJUb2tlbnMuYWNjZW50OiJ0cmFuc3Bh
cmVudCIgfQorICAgIH0KKyAgICBwb3B1cDogUG9wdXAgeworICAgICAgICB5OiBjb250cm9sLmhl
aWdodCArIDQ7IHdpZHRoOmNvbnRyb2wud2lkdGg7IHBhZGRpbmc6NgorICAgICAgICBpbXBsaWNp
dEhlaWdodDogTWF0aC5taW4oY29udGVudEl0ZW0uaW1wbGljaXRIZWlnaHQgKyAxMiwzMjApCisg
ICAgICAgIGJhY2tncm91bmQ6Q3JpbXNvbkdsYXNzUGFuZWwgeyBjb2xvcjpWYlRva2Vucy5iZ0Vs
ZXY7cmFkaXVzOlZiVG9rZW5zLnJhZGl1c0NvbnRyb2w7Ym9yZGVyLmNvbG9yOlZiVG9rZW5zLnN0
cm9rZSB9CisgICAgICAgIGNvbnRlbnRJdGVtOkxpc3RWaWV3IHsgY2xpcDp0cnVlO2ltcGxpY2l0
SGVpZ2h0OmNvbnRlbnRIZWlnaHQ7bW9kZWw6Y29udHJvbC5wb3B1cC52aXNpYmxlP2NvbnRyb2wu
ZGVsZWdhdGVNb2RlbDpudWxsO2N1cnJlbnRJbmRleDpjb250cm9sLmhpZ2hsaWdodGVkSW5kZXg7
U2Nyb2xsSW5kaWNhdG9yLnZlcnRpY2FsOlNjcm9sbEluZGljYXRvciB7fSB9CisgICAgfQorfQpk
aWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlQ29udHJvbENlbnRlci5xbWwgYi9hcHAvZ3VpL0Vj
bGlwc2VDb250cm9sQ2VudGVyLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
Li5lMjMyZTFlCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9FY2xpcHNlQ29udHJvbENlbnRl
ci5xbWwKQEAgLTAsMCArMSwxNjQgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVp
Y2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0IFF0UXVp
Y2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2lt
cG9ydCBTeXN0ZW1Db250cm9scyAxLjAKK2ltcG9ydCBDcmltc29uU3RhdHVzIDEuMAoraW1wb3J0
IFN0cmVhbWluZ1ByZWZlcmVuY2VzIDEuMAoraW1wb3J0IEVjbGlwc2VQcm9maWxlcyAxLjAKKwor
RHJhd2VyIHsKKyAgICBpZDogcGFuZWwKKyAgICBlZGdlOiBRdC5SaWdodEVkZ2UKKyAgICB3aWR0
aDogTWF0aC5taW4oNTYwLCBwYXJlbnQud2lkdGggLSAyNCkKKyAgICBoZWlnaHQ6IHBhcmVudC5o
ZWlnaHQKKyAgICBtb2RhbDogdHJ1ZQorICAgIE92ZXJsYXkubW9kYWw6IFJlY3RhbmdsZSB7Y29s
b3I6VmJUb2tlbnMuc2hlZXRTY3JpbX0KKyAgICBlbnRlcjogVHJhbnNpdGlvbiB7IE51bWJlckFu
aW1hdGlvbiB7IHByb3BlcnR5OiAicG9zaXRpb24iOyBmcm9tOiAwOyB0bzogMTsgZHVyYXRpb246
IFZiVG9rZW5zLnNoZWV0SW5NcyB9IH0KKyAgICBleGl0OiBUcmFuc2l0aW9uIHsgTnVtYmVyQW5p
bWF0aW9uIHsgcHJvcGVydHk6ICJwb3NpdGlvbiI7IGZyb206IDE7IHRvOiAwOyBkdXJhdGlvbjog
VmJUb2tlbnMuc2hlZXRJbk1zIH0gfQorICAgIHByb3BlcnR5IHZhciBob3N0OiAoe30pCisgICAg
cHJvcGVydHkgYm9vbCBjYW5XYWtlOiBmYWxzZQorICAgIHByb3BlcnR5IGJvb2wgY2FuTWFuYWdl
OiBmYWxzZQorICAgIHByb3BlcnR5IHN0cmluZyBuZXh0UGFuZWw6ICIiCisgICAgcHJvcGVydHkg
c3RyaW5nIG1lc3NhZ2U6ICIiCisgICAgcHJvcGVydHkgdmFyIHNhdmVkTmFtZXM6IFtdCisgICAg
cHJvcGVydHkgc3RyaW5nIHBvd2VyQWN0aW9uOiAiIgorICAgIHNpZ25hbCBuYXZpZ2F0ZVJlcXVl
c3RlZChzdHJpbmcgZGVzdGluYXRpb24pCisgICAgc2lnbmFsIHdha2VSZXF1ZXN0ZWQoKQorICAg
IE1hdGVyaWFsLnRoZW1lOiBNYXRlcmlhbC5EYXJrCisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDog
VmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAg
ICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7IGNvbG9yOiBWYlRva2Vucy5iZ0VsZXY7
IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlCisgICAgICAgIFJlY3RhbmdsZSB7IGFuY2hv
cnMuZmlsbDogcGFyZW50OyBjb2xvcjogInRyYW5zcGFyZW50IjsgZ3JhZGllbnQ6IEdyYWRpZW50
IHsgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246IDA7IGNvbG9yOiBRdC5yZ2JhKDEsMSwxLDAuMDM1
KSB9IEdyYWRpZW50U3RvcCB7IHBvc2l0aW9uOiAxOyBjb2xvcjogInRyYW5zcGFyZW50IiB9IH0g
fQorICAgIH0KKyAgICBmdW5jdGlvbiBkZWZlcihkZXN0aW5hdGlvbikgeyBuZXh0UGFuZWwgPSBk
ZXN0aW5hdGlvbjsgY2xvc2UoKSB9CisgICAgZnVuY3Rpb24gYXBwbHkodmFsdWVzKSB7CisgICAg
ICAgIGlmICghdmFsdWVzLndpZHRoKSB7IG1lc3NhZ2UgPSBxc1RyKCJTYXZlIHRoaXMgcHJvZmls
ZSBmaXJzdC4iKTsgcmV0dXJuIH0KKyAgICAgICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMud2lkdGgg
PSB2YWx1ZXMud2lkdGgKKyAgICAgICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMuaGVpZ2h0ID0gdmFs
dWVzLmhlaWdodAorICAgICAgICBTdHJlYW1pbmdQcmVmZXJlbmNlcy5mcHMgPSB2YWx1ZXMuZnBz
CisgICAgICAgIFN0cmVhbWluZ1ByZWZlcmVuY2VzLmJpdHJhdGVLYnBzID0gdmFsdWVzLmJpdHJh
dGVLYnBzCisgICAgICAgIFN0cmVhbWluZ1ByZWZlcmVuY2VzLnNhdmUoKQorICAgICAgICBtZXNz
YWdlID0gcXNUcigiUHJvZmlsZSBhcHBsaWVkIGZvciB0aGUgbmV4dCBzdHJlYW0uIikKKyAgICB9
CisgICAgb25PcGVuZWQ6IHsgbWVzc2FnZSA9ICIiOyBTeXN0ZW1Db250cm9scy5vcGVuKCJjZW50
ZXIiKTsgcHJvZmlsZU5hbWUudGV4dCA9ICJHYW1pbmciOyBzYXZlZE5hbWVzID0gRWNsaXBzZVBy
b2ZpbGVzLm5hbWVzKGhvc3QuaWQgfHwgIiIpIH0KKyAgICBvbkNsb3NlZDogeworICAgICAgICBw
b3dlckRpYWxvZy5jbG9zZSgpOyBTeXN0ZW1Db250cm9scy5jbG9zZSgpOyBzdGFja1ZpZXcuZm9y
Y2VBY3RpdmVGb2N1cygpCisgICAgICAgIGlmIChuZXh0UGFuZWwgIT09ICIiKSB7IHZhciBkZXN0
aW5hdGlvbiA9IG5leHRQYW5lbDsgbmV4dFBhbmVsID0gIiI7IG5hdmlnYXRlUmVxdWVzdGVkKGRl
c3RpbmF0aW9uKSB9CisgICAgfQorICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAg
ICAgICBhbmNob3JzLmZpbGw6IHBhcmVudDsgYW5jaG9ycy5tYXJnaW5zOiAyMDsgc3BhY2luZzog
VmJUb2tlbnMuc3BhY2UzCisgICAgICAgIFJvd0xheW91dCB7CisgICAgICAgICAgICBMYXlvdXQu
ZmlsbFdpZHRoOiB0cnVlCisgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIkVjbGlwc2Ug
4oCiIENvbnRyb2wgY2VudGVyIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmZhbWlseTog
VmJUb2tlbnMuZm9udERpc3BsYXk7IGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQm9keTsg
TGF5b3V0LmZpbGxXaWR0aDogdHJ1ZSB9CisgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9u
IHsgdGV4dDogcXNUcigiQ2xvc2UiKTsgb25DbGlja2VkOiBwYW5lbC5jbG9zZSgpIH0KKyAgICAg
ICAgfQorICAgICAgICBTY3JvbGxWaWV3IHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6
IHRydWU7IExheW91dC5maWxsSGVpZ2h0OiB0cnVlCisgICAgICAgICAgICBjbGlwOiB0cnVlOyBj
b250ZW50V2lkdGg6IGF2YWlsYWJsZVdpZHRoCisgICAgICAgICAgICBDb2x1bW5MYXlvdXQgewor
ICAgICAgICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lkdGg7IHNwYWNpbmc6IFZiVG9rZW5zLnNw
YWNlMworICAgICAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4
dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IENyaW1z
b25TdGF0dXMubG9jYWwubmV0d29yayB8fCBxc1RyKCJOZXR3b3JrIHVuYXZhaWxhYmxlIik7IGNv
bG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5m
aWxsV2lkdGg6IHRydWU7IHRleHQ6IENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVBlcmNlbnQg
Pj0gMCA/IHFzVHIoIkJhdHRlcnkgJTElIOKAoiAlMiIpLmFyZyhDcmltc29uU3RhdHVzLmxvY2Fs
LmJhdHRlcnlQZXJjZW50KS5hcmcoQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5U3RhdGUpIDog
cXNUcigiQmF0dGVyeSB1bmF2YWlsYWJsZSIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbTsgd3Jh
cE1vZGU6IFRleHQuV3JhcCB9CisgICAgICAgICAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAg
ICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIldpLUZpIik7IGlj
b25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnIjsgb25DbGlja2VkOiBwYW5l
bC5kZWZlcigid2lmaSIpIH0KKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRv
biB7IHRleHQ6IHFzVHIoIkJsdWV0b290aCIpOyBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNv
bi1ibHVldG9vdGguc3ZnIjsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigiYnQiKSB9CisgICAgICAg
ICAgICAgICAgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogcXNUcigiQXVkaW8iKTsg
Y29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQuYm9sZDogdHJ1ZSB9CisgICAgICAgICAgICAgICAg
Um93TGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQor
ICAgICAgICAgICAgICAgICAgICBTbGlkZXIgeworICAgICAgICAgICAgICAgICAgICAgICAgaWQ6
IHZvbHVtZVNsaWRlcgorICAgICAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDog
dHJ1ZTsgZnJvbTogMDsgdG86IDEwMDsgc3RlcFNpemU6IDEKKyAgICAgICAgICAgICAgICAgICAg
ICAgIHZhbHVlOiBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUgPT09IHVuZGVmaW5lZCB8fCBT
eXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUgPT09IG51bGwgPyAwIDogU3lzdGVtQ29udHJvbHMu
c3RhdGUudm9sdW1lCisgICAgICAgICAgICAgICAgICAgICAgICBlbmFibGVkOiAhU3lzdGVtQ29u
dHJvbHMuYnVzeSAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUgIT09IHVuZGVmaW5lZCAm
JiBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUgIT09IG51bGwKKyAgICAgICAgICAgICAgICAg
ICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiU3BlYWtlciB2b2x1bWUiKQorICAgICAgICAg
ICAgICAgICAgICAgICAgb25Nb3ZlZDogaWYgKCFwcmVzc2VkICYmIGVuYWJsZWQpIFN5c3RlbUNv
bnRyb2xzLnJlcXVlc3QoImNlbnRlci12b2x1bWUiLCBTdHJpbmcoTWF0aC5yb3VuZCh2YWx1ZSkp
KQorICAgICAgICAgICAgICAgICAgICAgICAgb25QcmVzc2VkQ2hhbmdlZDogaWYgKCFwcmVzc2Vk
ICYmIGVuYWJsZWQpIFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci12b2x1bWUiLCBTdHJp
bmcoTWF0aC5yb3VuZCh2YWx1ZSkpKQorICAgICAgICAgICAgICAgICAgICB9CisgICAgICAgICAg
ICAgICAgICAgIExhYmVsIHsgaWQ6IHZvbHVtZVJlYWRvdXQ7IHRleHQ6IE1hdGgucm91bmQodm9s
dW1lU2xpZGVyLnZhbHVlKSsiJSI7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0KKyAgICAgICAgICAg
ICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IFN5c3RlbUNvbnRyb2xzLnN0YXRl
Lm11dGVkID8gcXNUcigiVW5tdXRlIikgOiBxc1RyKCJNdXRlIik7IGVuYWJsZWQ6ICFTeXN0ZW1D
b250cm9scy5idXN5ICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSAhPT0gbnVsbCAmJiBT
eXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUgIT09IHVuZGVmaW5lZDsgb25DbGlja2VkOiBTeXN0
ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItbXV0ZSIpIH0KKyAgICAgICAgICAgICAgICB9Cisg
ICAgICAgICAgICAgICAgRWNsaXBzZUNvbWJvQm94IHsKKyAgICAgICAgICAgICAgICAgICAgTGF5
b3V0LmZpbGxXaWR0aDogdHJ1ZQorICAgICAgICAgICAgICAgICAgICBtb2RlbDogU3lzdGVtQ29u
dHJvbHMuc3RhdGUuc2lua3MgfHwgW107IHRleHRSb2xlOiAibmFtZSIKKyAgICAgICAgICAgICAg
ICAgICAgZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3kgJiYgY291bnQgPiAwCisgICAgICAg
ICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiQXVkaW8gb3V0cHV0IikKKyAgICAg
ICAgICAgICAgICAgICAgY3VycmVudEluZGV4OiB7IHZhciBsaXN0ID0gU3lzdGVtQ29udHJvbHMu
c3RhdGUuc2lua3MgfHwgW107IGZvciAodmFyIGk9MDtpPGxpc3QubGVuZ3RoO2krKykgaWYgKGxp
c3RbaV0uZGVmYXVsdCkgcmV0dXJuIGk7IHJldHVybiAtMSB9CisgICAgICAgICAgICAgICAgICAg
IGNvbnRlbnRJdGVtOiBMYWJlbCB7IHRleHQ6IHBhcmVudC5kaXNwbGF5VGV4dDsgdGV4dEZvcm1h
dDogVGV4dC5QbGFpblRleHQ7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyB2ZXJ0aWNhbEFsaWdubWVu
dDogVGV4dC5BbGlnblZDZW50ZXI7IGVsaWRlOiBUZXh0LkVsaWRlUmlnaHQgfQorICAgICAgICAg
ICAgICAgICAgICBkZWxlZ2F0ZTogSXRlbURlbGVnYXRlIHsgd2lkdGg6IHBhcmVudC53aWR0aDsg
Y29udGVudEl0ZW06IExhYmVsIHsgdGV4dDogbW9kZWxEYXRhLm5hbWU7IHRleHRGb3JtYXQ6IFRl
eHQuUGxhaW5UZXh0OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZWxpZGU6IFRleHQuRWxpZGVSaWdo
dCB9IH0KKyAgICAgICAgICAgICAgICAgICAgb25BY3RpdmF0ZWQ6IFN5c3RlbUNvbnRyb2xzLnJl
cXVlc3QoImNlbnRlci1vdXRwdXQiLCBtb2RlbFtpbmRleF0uaWQpCisgICAgICAgICAgICAgICAg
fQorICAgICAgICAgICAgICAgIFJlcGVhdGVyIHsKKyAgICAgICAgICAgICAgICAgICAgbW9kZWw6
IFt7a2luZDoic2NyZWVuIixsYWJlbDpxc1RyKCJTY3JlZW4gYnJpZ2h0bmVzcyIpfSx7a2luZDoi
a2V5Ym9hcmQiLGxhYmVsOnFzVHIoIktleWJvYXJkIGJyaWdodG5lc3MiKX1dCisgICAgICAgICAg
ICAgICAgICAgIGRlbGVnYXRlOiBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgICAgICAgICAg
ICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQorICAgICAgICAgICAgICAgICAgICAgICAgcHJvcGVy
dHkgdmFyIGhhcmR3YXJlOiAoU3lzdGVtQ29udHJvbHMuc3RhdGUuYnJpZ2h0bmVzcyB8fCB7fSlb
bW9kZWxEYXRhLmtpbmRdCisgICAgICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IG1v
ZGVsRGF0YS5sYWJlbCArIChoYXJkd2FyZSA/ICIg4oCiICIgKyBoYXJkd2FyZS5wZXJjZW50ICsg
IiUiIDogIiDigKIgIiArIHFzVHIoIlVuYXZhaWxhYmxlIikpOyBjb2xvcjogVmJUb2tlbnMudGV4
dCB9CisgICAgICAgICAgICAgICAgICAgICAgICBTbGlkZXIgeworICAgICAgICAgICAgICAgICAg
ICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7IGZyb206IG1vZGVsRGF0YS5raW5kID09
PSAic2NyZWVuIiA/IDUgOiAwOyB0bzogMTAwOyBzdGVwU2l6ZTogMQorICAgICAgICAgICAgICAg
ICAgICAgICAgICAgIHZhbHVlOiBoYXJkd2FyZSA/IGhhcmR3YXJlLnBlcmNlbnQgOiAwOyBlbmFi
bGVkOiAhIWhhcmR3YXJlICYmICFTeXN0ZW1Db250cm9scy5idXN5CisgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBtb2RlbERhdGEubGFiZWwKKyAgICAgICAgICAg
ICAgICAgICAgICAgICAgICBvbk1vdmVkOiBpZiAoIXByZXNzZWQgJiYgZW5hYmxlZCkgU3lzdGVt
Q29udHJvbHMucmVxdWVzdCgiY2VudGVyLSIrbW9kZWxEYXRhLmtpbmQsIFN0cmluZyhNYXRoLnJv
dW5kKHZhbHVlKSkpCisgICAgICAgICAgICAgICAgICAgICAgICAgICAgb25QcmVzc2VkQ2hhbmdl
ZDogaWYgKCFwcmVzc2VkICYmIGVuYWJsZWQpIFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRl
ci0iK21vZGVsRGF0YS5raW5kLCBTdHJpbmcoTWF0aC5yb3VuZCh2YWx1ZSkpKQorICAgICAgICAg
ICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAg
fQorICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJSZWZy
ZXNoIGNvbnRyb2xzIik7IGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6
IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci1saXN0IikgfQorICAgICAgICAgICAgICAg
IExhYmVsIHsgdGV4dDogcXNUcigiSG9zdCIpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5i
b2xkOiB0cnVlIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRy
dWU7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0
OiBwYW5lbC5ob3N0LnVybCB8fCBxc1RyKCJTZWxlY3QgYSBob3N0IGluIHRoZSBsYXVuY2hlci4i
KTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgICAgIFJvd0xheW91dCB7
CisgICAgICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJI
b3N0IHN0YXRzIik7IGVuYWJsZWQ6ICEhcGFuZWwuaG9zdC5pZDsgaWNvblNvdXJjZTogInFyYzov
cmVzL2NyaW1zb24taG9zdC5zdmciOyBvbkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJob3N0IikgfQor
ICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiV2Fr
ZSBob3N0Iik7IGVuYWJsZWQ6ICEhcGFuZWwuaG9zdC5pZCAmJiBwYW5lbC5jYW5XYWtlOyBvbkNs
aWNrZWQ6IHsgcGFuZWwud2FrZVJlcXVlc3RlZCgpOyBwYW5lbC5tZXNzYWdlID0gcXNUcigiV2Fr
ZSByZXF1ZXN0IHNlbnQ7IHRoZSBob3N0IG11c3Qgc3VwcG9ydCBXYWtlLW9uLUxBTi4iKSB9IH0K
KyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7
IHRleHQ6IHFzVHIoIk9wZW4gaG9zdCBtYW5hZ2VtZW50Iik7IGVuYWJsZWQ6ICEhcGFuZWwuaG9z
dC51cmwgJiYgcGFuZWwuY2FuTWFuYWdlOyBvbkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJtYW5hZ2Vt
ZW50IikgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogcXNUcigiU3RyZWFtIHByb2Zp
bGVzIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmJvbGQ6IHRydWUgfQorICAgICAgICAg
ICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3Jh
cDsgdGV4dDogcGFuZWwuaG9zdC5pZCA/IHFzVHIoIlNhdmVkIGZvciB0aGUgc2VsZWN0ZWQgaG9z
dC4gQXBwbHkgYmVmb3JlIHN0YXJ0aW5nIGEgc3RyZWFtLiIpIDogcXNUcigiR2xvYmFsIHByb2Zp
bGVzLiBBcHBseSBiZWZvcmUgc3RhcnRpbmcgYSBzdHJlYW0uIik7IGNvbG9yOiBWYlRva2Vucy50
ZXh0RGltIH0KKyAgICAgICAgICAgICAgICBFY2xpcHNlQ29tYm9Cb3ggeyBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyBtb2RlbDogcGFuZWwuc2F2ZWROYW1lczsgdmlzaWJsZTogY291bnQgPiAwOyBB
Y2Nlc3NpYmxlLm5hbWU6IHFzVHIoIlNhdmVkIHByb2ZpbGVzIik7IG9uQWN0aXZhdGVkOiBwcm9m
aWxlTmFtZS50ZXh0ID0gbW9kZWxbaW5kZXhdIH0KKyAgICAgICAgICAgICAgICBUZXh0RmllbGQg
eyBpZDogcHJvZmlsZU5hbWU7IExheW91dC5maWxsV2lkdGg6IHRydWU7IG1heGltdW1MZW5ndGg6
IDQ4OyBwbGFjZWhvbGRlclRleHQ6IHFzVHIoIlByb2ZpbGUgbmFtZSIpOyBBY2Nlc3NpYmxlLm5h
bWU6IHFzVHIoIlByb2ZpbGUgbmFtZSIpIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgewor
ICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiU2F2
ZSBjdXJyZW50Iik7IG9uQ2xpY2tlZDogeyBwYW5lbC5tZXNzYWdlID0gRWNsaXBzZVByb2ZpbGVz
LnNhdmUocGFuZWwuaG9zdC5pZCB8fCAiIiwgcHJvZmlsZU5hbWUudGV4dCwge3dpZHRoOlN0cmVh
bWluZ1ByZWZlcmVuY2VzLndpZHRoLGhlaWdodDpTdHJlYW1pbmdQcmVmZXJlbmNlcy5oZWlnaHQs
ZnBzOlN0cmVhbWluZ1ByZWZlcmVuY2VzLmZwcyxiaXRyYXRlS2JwczpTdHJlYW1pbmdQcmVmZXJl
bmNlcy5iaXRyYXRlS2Jwc30pID8gcXNUcigiUHJvZmlsZSBzYXZlZC4iKSA6IHFzVHIoIlByb2Zp
bGUgY291bGQgbm90IGJlIHNhdmVkLiIpOyBwYW5lbC5zYXZlZE5hbWVzID0gRWNsaXBzZVByb2Zp
bGVzLm5hbWVzKHBhbmVsLmhvc3QuaWQgfHwgIiIpIH0gfQorICAgICAgICAgICAgICAgICAgICBF
Y2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiQXBwbHkgc2F2ZWQiKTsgb25DbGlja2Vk
OiBwYW5lbC5hcHBseShFY2xpcHNlUHJvZmlsZXMubG9hZChwYW5lbC5ob3N0LmlkIHx8ICIiLCBw
cm9maWxlTmFtZS50ZXh0KSkgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBS
b3dMYXlvdXQgeworICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4
dDogcXNUcigiRGVza3RvcCBwcmVzZXQiKTsgb25DbGlja2VkOiBwYW5lbC5hcHBseSh7d2lkdGg6
MTI4MCxoZWlnaHQ6ODAwLGZwczo2MCxiaXRyYXRlS2JwczoxNTAwMH0pIH0KKyAgICAgICAgICAg
ICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIkxvdyBiYW5kd2lkdGgi
KTsgb25DbGlja2VkOiBwYW5lbC5hcHBseSh7d2lkdGg6MTI4MCxoZWlnaHQ6NzIwLGZwczozMCxi
aXRyYXRlS2Jwczo1MDAwfSkgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBM
YWJlbCB7IHRleHQ6IHFzVHIoIkFwcGVhcmFuY2UgJiBhY2Nlc3NpYmlsaXR5Iik7IGNvbG9yOiBW
YlRva2Vucy50ZXh0OyBmb250LmJvbGQ6IHRydWUgfQorICAgICAgICAgICAgICAgIEVjbGlwc2VD
b21ib0JveCB7CisgICAgICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7IG1v
ZGVsOiBbcXNUcigiVGV4dCAxMDAlIikscXNUcigiVGV4dCAxMTAlIikscXNUcigiVGV4dCAxMjUl
IildCisgICAgICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiVGV4dCBzaXpl
IikKKyAgICAgICAgICAgICAgICAgICAgY3VycmVudEluZGV4OiBFY2xpcHNlUHJvZmlsZXMudGV4
dFNjYWxlID09PSAxMjUgPyAyIDogRWNsaXBzZVByb2ZpbGVzLnRleHRTY2FsZSA9PT0gMTEwID8g
MSA6IDAKKyAgICAgICAgICAgICAgICAgICAgb25BY3RpdmF0ZWQ6IEVjbGlwc2VQcm9maWxlcy50
ZXh0U2NhbGUgPSBbMTAwLDExMCwxMjVdW2luZGV4XQorICAgICAgICAgICAgICAgIH0KKyAgICAg
ICAgICAgICAgICBTd2l0Y2ggeyB0ZXh0OiBxc1RyKCJSZWR1Y2UgbW90aW9uIik7IGNoZWNrZWQ6
IEVjbGlwc2VQcm9maWxlcy5yZWR1Y2VkTW90aW9uOyBvblRvZ2dsZWQ6IEVjbGlwc2VQcm9maWxl
cy5yZWR1Y2VkTW90aW9uID0gY2hlY2tlZCB9CisgICAgICAgICAgICAgICAgU3dpdGNoIHsgdGV4
dDogcXNUcigiSGlnaGVyIGNvbnRyYXN0Iik7IGNoZWNrZWQ6IEVjbGlwc2VQcm9maWxlcy5oaWdo
Q29udHJhc3Q7IG9uVG9nZ2xlZDogRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdCA9IGNoZWNr
ZWQgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogcXNUcigiVG9vbHMgJiByZWNvdmVy
eSIpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAgICAgICAgICAg
ICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9u
IHsgdGV4dDogcXNUcigiQWxsIHNldHRpbmdzIik7IGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9zZXR0
aW5ncy5zdmciOyBvbkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJzZXR0aW5ncyIpIH0KKyAgICAgICAg
ICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIlN1cHBvcnQgcmVw
b3J0Iik7IGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6IFN5c3RlbUNv
bnRyb2xzLnJlcXVlc3QoImNlbnRlci1yZXBvcnQiKSB9CisgICAgICAgICAgICAgICAgfQorICAg
ICAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRl
eHQuV3JhcDsgdGV4dDogcXNUcigiUmVjb3Zlcnk6IEN0cmwrQWx0K0YyIG9wZW5zIHRoZSBkaWFn
bm9zdGljIGNvbnNvbGUuIE1hYyBicmlnaHRuZXNzLCBrZXlib2FyZC1saWdodCBhbmQgdm9sdW1l
IGtleXMgcmVtYWluIGF2YWlsYWJsZS4iKTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAg
ICAgICAgICAgICAgIFJvd0xheW91dCB7CisgICAgICAgICAgICAgICAgICAgIFJlcGVhdGVyIHsK
KyAgICAgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBbe2FjdGlvbjoicmVib290IixsYWJlbDpx
c1RyKCJSZXN0YXJ0Iil9LHthY3Rpb246InBvd2Vyb2ZmIixsYWJlbDpxc1RyKCJTaHV0IGRvd24i
KX1dCisgICAgICAgICAgICAgICAgICAgICAgICBkZWxlZ2F0ZTogRWNsaXBzZUFjdGlvbkJ1dHRv
biB7IHRleHQ6IG1vZGVsRGF0YS5sYWJlbDsgaWNvblNvdXJjZTogInFyYzovcmVzL2VjbGlwc2Ut
cG93ZXIuc3ZnIjsgZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogeyBw
YW5lbC5wb3dlckFjdGlvbiA9IG1vZGVsRGF0YS5hY3Rpb247IHBvd2VyRGlhbG9nLm9wZW4oKSB9
IH0KKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiQWJvdXQgRWNsaXBzZSIpOyBl
bmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigiYWJv
dXQiKSB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB0
ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcGFu
ZWwubWVzc2FnZSB8fCBTeXN0ZW1Db250cm9scy5zdGF0dXM7IGNvbG9yOiBWYlRva2Vucy50ZXh0
RGltIH0KKyAgICAgICAgICAgICAgICBCdXN5SW5kaWNhdG9yIHsgcnVubmluZzogU3lzdGVtQ29u
dHJvbHMuYnVzeTsgdmlzaWJsZTogcnVubmluZzsgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25I
Q2VudGVyIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBOYXZpZ2FibGVE
aWFsb2cgeworICAgICAgICBpZDogcG93ZXJEaWFsb2cKKyAgICAgICAgd2lkdGg6IE1hdGgubWlu
KDQ0MCwgcGFuZWwud2lkdGggLSAzMikKKyAgICAgICAgdGl0bGU6IHBhbmVsLnBvd2VyQWN0aW9u
ID09PSAicmVib290IiA/IHFzVHIoIlJlc3RhcnQgRWNsaXBzZU9TPyIpIDogcXNUcigiU2h1dCBk
b3duIEVjbGlwc2VPUz8iKQorICAgICAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5ZZXMgfCBE
aWFsb2cuTm8KKyAgICAgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2Cisg
ICAgICAgIG9uQWNjZXB0ZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci0iK3BhbmVs
LnBvd2VyQWN0aW9uLCIiLHRydWUpCisgICAgICAgIGNvbnRlbnRJdGVtOiBMYWJlbCB7IHRleHQ6
IHFzVHIoIlRoaXMgZW5kcyB0aGUgY3VycmVudCBsb2NhbCBzZXNzaW9uLiIpOyBjb2xvcjogVmJU
b2tlbnMudGV4dCB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlSGFyZHdh
cmVNb25pdG9yLnFtbCBiL2FwcC9ndWkvRWNsaXBzZUhhcmR3YXJlTW9uaXRvci5xbWwKbmV3IGZp
bGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uZWRiZTE5MQotLS0gL2Rldi9udWxsCisrKyBi
L2FwcC9ndWkvRWNsaXBzZUhhcmR3YXJlTW9uaXRvci5xbWwKQEAgLTAsMCArMSw3NyBAQAoraW1w
b3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1
aWNrLkxheW91dHMgMS4zCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBMb2Nh
bEhhcmR3YXJlIDEuMAorCitDb2x1bW5MYXlvdXQgeworICAgIGlkOiBtb25pdG9yCisgICAgb2Jq
ZWN0TmFtZToiaGFyZHdhcmVNb25pdG9yIgorICAgIHByb3BlcnR5IGJvb2wgYWN0aXZlOiBmYWxz
ZQorICAgIENvbXBvbmVudC5vbkNvbXBsZXRlZDogaWYoYWN0aXZlKSBMb2NhbEhhcmR3YXJlLnNl
dENvbnN1bWVyQWN0aXZlKG1vbml0b3IsdHJ1ZSkKKyAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVl
CisgICAgb25BY3RpdmVDaGFuZ2VkOiBMb2NhbEhhcmR3YXJlLnNldENvbnN1bWVyQWN0aXZlKG1v
bml0b3IsYWN0aXZlKQorICAgIENvbXBvbmVudC5vbkRlc3RydWN0aW9uOiBMb2NhbEhhcmR3YXJl
LnNldENvbnN1bWVyQWN0aXZlKG1vbml0b3IsZmFsc2UpCisgICAgZnVuY3Rpb24gcmVhZGluZyhr
ZXksIHN1ZmZpeCwgZGlnaXRzKSB7IHZhciB2PUxvY2FsSGFyZHdhcmUucmVhZGluZ3Nba2V5XTsg
cmV0dXJuIHYgPT09IHVuZGVmaW5lZCA/IHFzVHIoIlVuYXZhaWxhYmxlIikgOiBOdW1iZXIodiku
dG9GaXhlZChkaWdpdHMgPT09IHVuZGVmaW5lZCA/IDEgOiBkaWdpdHMpKyhzdWZmaXggfHwgIiIp
IH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVs
U2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigiTE9DQUwgTUFDIOKAoiBIYXJkd2Fy
ZSBtb25pdG9yIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmJvbGQ6IHRydWUgfQorICAg
IExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZi
VG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5X
cmFwOyB0ZXh0OiBxc1RyKCJMb2NhbCByZWFkaW5ncyBhcmUgaW5kZXBlbmRlbnQgb2Ygc3RyZWFt
IGFuZCBob3N0IHN0YXRpc3RpY3MuIE1pc3Npbmcgc2Vuc29ycyBzaG93IFVuYXZhaWxhYmxlOyBm
aXJzdCBDUFUvbmV0d29yayByYXRlcyBuZWVkIGEgc2Vjb25kIHNhbXBsZS4gSW50ZWwgR1BVIHNo
YXJlZCBtZW1vcnkgaXMgc3lzdGVtIFJBTS4iKTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQor
ICAgIEdyaWRMYXlvdXQgeworICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBjb2x1bW5z
OiB3aWR0aCA+PSA2MjAgPyAyIDogMTsgY29sdW1uU3BhY2luZzogVmJUb2tlbnMuc3BhY2UzOyBy
b3dTcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICAgICAgUmVwZWF0ZXIgeworICAgICAgICAg
ICAgbW9kZWw6IFsKKyAgICAgICAgICAgICAgICB7bGFiZWw6cXNUcigiQ1BVIiksIGtleToiY3B1
UGVyY2VudCIsc3VmZml4OiIlIn0sIHtsYWJlbDpxc1RyKCJDUFUgY2xvY2siKSxrZXk6ImNwdU1I
eiIsc3VmZml4OiIgTUh6In0sCisgICAgICAgICAgICAgICAge2xhYmVsOnFzVHIoIk1lbW9yeSB1
c2VkIiksa2V5OiJtZW1vcnlVc2VkR2lCIixzdWZmaXg6IiBHaUIifSx7bGFiZWw6cXNUcigiTWVt
b3J5IHRvdGFsIiksa2V5OiJtZW1vcnlUb3RhbEdpQiIsc3VmZml4OiIgR2lCIn0sCisgICAgICAg
ICAgICAgICAge2xhYmVsOnFzVHIoIkNQVSB0ZW1wZXJhdHVyZSIpLGtleToidGVtcGVyYXR1cmVD
IixzdWZmaXg6IiDCsEMifSx7bGFiZWw6cXNUcigiRmFuIiksa2V5OiJmYW5SUE0iLHN1ZmZpeDoi
IFJQTSJ9LAorICAgICAgICAgICAgICAgIHtsYWJlbDpxc1RyKCJHUFUgYnVzeSIpLGtleToiZ3B1
UGVyY2VudCIsc3VmZml4OiIlIn0se2xhYmVsOnFzVHIoIkVjbGlwc2UgdmlkZW8gZW5naW5lIiks
a2V5OiJ2aWRlb1BlcmNlbnQiLHN1ZmZpeDoiJSJ9LHtsYWJlbDpxc1RyKCJTd2FwIHVzZWQiKSxr
ZXk6InN3YXBVc2VkTWlCIixzdWZmaXg6IiBNaUIifSwKKyAgICAgICAgICAgICAgICB7bGFiZWw6
cXNUcigiTmV0d29yayBkb3dubG9hZCIpLGtleToicmVjZWl2ZU1pQiIsc3VmZml4OiIgTWlCL3Mi
fSx7bGFiZWw6cXNUcigiTmV0d29yayB1cGxvYWQiKSxrZXk6InRyYW5zbWl0TWlCIixzdWZmaXg6
IiBNaUIvcyJ9LAorICAgICAgICAgICAgICAgIHtsYWJlbDpxc1RyKCJTdG9yYWdlIHJlYWRzIiks
a2V5OiJkaXNrUmVhZE1pQiIsc3VmZml4OiIgTWlCL3MifSx7bGFiZWw6cXNUcigiU3RvcmFnZSB3
cml0ZXMiKSxrZXk6ImRpc2tXcml0ZU1pQiIsc3VmZml4OiIgTWlCL3MifSwKKyAgICAgICAgICAg
ICAgICB7bGFiZWw6cXNUcigiVVNCL3Jvb3QgZnJlZSIpLGtleToic3RvcmFnZUZyZWVHaUIiLHN1
ZmZpeDoiIEdpQiJ9LHtsYWJlbDpxc1RyKCJCYXR0ZXJ5Iiksa2V5OiJiYXR0ZXJ5UGVyY2VudCIs
c3VmZml4OiIlIn0KKyAgICAgICAgICAgIF0KKyAgICAgICAgICAgIGRlbGVnYXRlOiBDcmltc29u
R2xhc3NQYW5lbCB7CisgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgaW1w
bGljaXRIZWlnaHQ6IDg0OyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0NhcmQ7IGNvbG9yOiBWYlRv
a2Vucy5iZ0VsZXY7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlCisgICAgICAgICAgICAg
ICAgQ29sdW1uIHsgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGFuY2hvcnMubWFyZ2luczogMTI7IHNw
YWNpbmc6IDYKKyAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBtb2RlbERhdGEubGFi
ZWw7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltOyBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlw
ZUJvZHkgfQorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IG1vbml0b3IucmVhZGlu
Zyhtb2RlbERhdGEua2V5LG1vZGVsRGF0YS5zdWZmaXgpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsg
Zm9udC5ib2xkOiB0cnVlOyBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUJvZHkgfQorICAg
ICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBMYWJl
bCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vu
cy50eXBlQm9keTsgdGV4dDogcXNUcigiUmVjZW50IENQVSBhbmQgUkFNIHVzYWdlIOKAoiB1cCB0
byA2MCBzYW1wbGVzIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICBDYW52YXMgewor
ICAgICAgICBpZDogZ3JhcGg7IExheW91dC5maWxsV2lkdGg6IHRydWU7IGltcGxpY2l0SGVpZ2h0
OiAxMDAKKyAgICAgICAgb25QYWludDogeworICAgICAgICAgICAgdmFyIGM9Z2V0Q29udGV4dCgi
MmQiKTsgYy5jbGVhclJlY3QoMCwwLHdpZHRoLGhlaWdodCk7IGMuZmlsbFN0eWxlPVZiVG9rZW5z
LmJnRWxldjsgYy5maWxsUmVjdCgwLDAsd2lkdGgsaGVpZ2h0KQorICAgICAgICAgICAgdmFyIGtl
eXM9WyJjcHVQZXJjZW50IiwibWVtb3J5UGVyY2VudCJdLCBjb2xvcnM9W1ZiVG9rZW5zLmFjY2Vu
dCxWYlRva2Vucy50ZXh0RGltXSwgaD1Mb2NhbEhhcmR3YXJlLmhpc3RvcnkKKyAgICAgICAgICAg
IGZvcih2YXIgaz0wO2s8a2V5cy5sZW5ndGg7aysrKSB7IGMuc3Ryb2tlU3R5bGU9Y29sb3JzW2td
OyBjLmxpbmVXaWR0aD0yOyBjLmJlZ2luUGF0aCgpOyB2YXIgc3RhcnRlZD1mYWxzZQorICAgICAg
ICAgICAgICAgIGZvcih2YXIgaT0wO2k8aC5sZW5ndGg7aSsrKSB7IHZhciB2PWhbaV1ba2V5c1tr
XV07IGlmKHY9PT11bmRlZmluZWQpIHsgc3RhcnRlZD1mYWxzZTsgY29udGludWUgfQorICAgICAg
ICAgICAgICAgICAgICB2YXIgeD13aWR0aCppLzU5LCB5PWhlaWdodC00LShoZWlnaHQtOCkqTWF0
aC5tYXgoMCxNYXRoLm1pbigxMDAsdikpLzEwMAorICAgICAgICAgICAgICAgICAgICBpZighc3Rh
cnRlZCkgYy5tb3ZlVG8oeCx5KTsgZWxzZSBjLmxpbmVUbyh4LHkpOyBzdGFydGVkPXRydWUgfQor
ICAgICAgICAgICAgICAgIGMuc3Ryb2tlKCkgfQorICAgICAgICB9CisgICAgICAgIENvbm5lY3Rp
b25zIHsgdGFyZ2V0OiBMb2NhbEhhcmR3YXJlOyBmdW5jdGlvbiBvbkNoYW5nZWQoKSB7IGdyYXBo
LnJlcXVlc3RQYWludCgpIH0gfQorICAgICAgICBDb25uZWN0aW9ucyB7IHRhcmdldDogVmJUb2tl
bnM7IGZ1bmN0aW9uIG9uQWNjZW50Q2hhbmdlZCgpIHsgZ3JhcGgucmVxdWVzdFBhaW50KCkgfSB9
CisgICAgfQorICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZv
bnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OiBxc1RyKCJTaG93IGxvY2FsIGhh
cmR3YXJlIG92ZXJsYXkgZHVyaW5nIHN0cmVhbWluZyIpOyBjaGVja2VkOiBMb2NhbEhhcmR3YXJl
Lm92ZXJsYXk7IG9uVG9nZ2xlZDogTG9jYWxIYXJkd2FyZS5vdmVybGF5PWNoZWNrZWQgfQorICAg
IENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXpl
OlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OiBxc1RyKCJEZXRhaWxlZCBsb2NhbCBvdmVybGF5Iik7
IGNoZWNrZWQ6IExvY2FsSGFyZHdhcmUuZGV0YWlsZWQ7IG9uVG9nZ2xlZDogTG9jYWxIYXJkd2Fy
ZS5kZXRhaWxlZD1jaGVja2VkIH0KKyAgICBDaGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5z
LmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigi
RGV0YWlsZWQgc3RyZWFtIHN0YXRpc3RpY3MiKTsgY2hlY2tlZDogTG9jYWxIYXJkd2FyZS5zdHJl
YW1EZXRhaWxlZDsgb25Ub2dnbGVkOiBMb2NhbEhhcmR3YXJlLnN0cmVhbURldGFpbGVkPWNoZWNr
ZWQgfQorICAgIFJvd0xheW91dCB7CisgICAgICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tl
bnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OiBxc1Ry
KCJMb2NhbCBvdmVybGF5IGNvcm5lciIpOyBjb2xvcjogVmJUb2tlbnMudGV4dCB9CisgICAgICAg
IEVjbGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgbW9kZWw6W3FzVHIoIlRv
cCBsZWZ0IikscXNUcigiVG9wIHJpZ2h0IikscXNUcigiQm90dG9tIGxlZnQiKSxxc1RyKCJCb3R0
b20gcmlnaHQiKV07IGN1cnJlbnRJbmRleDpMb2NhbEhhcmR3YXJlLnBvc2l0aW9uOyBvbkFjdGl2
YXRlZDpMb2NhbEhhcmR3YXJlLnBvc2l0aW9uPWluZGV4IH0KKyAgICB9CisgICAgTGFiZWwgeyBm
b250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlw
ZUJvZHk7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgd3JhcE1vZGU6VGV4dC5XcmFwOyB0ZXh0OnFz
VHIoIklmIGJvdGggb3ZlcmxheXMgdXNlIHRoZSBzYW1lIGNvcm5lciwgTG9jYWwgTWFjIG1vdmVz
IHRvIHRoZSBvcHBvc2l0ZSBob3Jpem9udGFsIGNvcm5lci4gU3RyZWFtaW5nIHNob3J0Y3V0czog
Q3RybCtBbHQrU2hpZnQrUyBmb3Igc3RyZWFtIHN0YXRzOyBDdHJsK0FsdCtTaGlmdCtIIGZvciBs
b2NhbCBoYXJkd2FyZS4gU3RyZWFtIHRleHQgc2l6ZSBhbmQgY29ybmVyIHJlbWFpbiBpbiBWaWRl
byBzZXR0aW5ncy4iKTsgY29sb3I6VmJUb2tlbnMudGV4dERpbSB9CisgICAgUm93TGF5b3V0IHsK
KyAgICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhl
bFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiUGFuZWwgb3BhY2l0eSIpOyBjb2xv
cjpWYlRva2Vucy50ZXh0IH0KKyAgICAgICAgU2xpZGVyIHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVl
OyBmcm9tOjQwO3RvOjEwMDtzdGVwU2l6ZTo1O3ZhbHVlOkxvY2FsSGFyZHdhcmUub3BhY2l0eTsg
b25Nb3ZlZDpMb2NhbEhhcmR3YXJlLm9wYWNpdHk9TWF0aC5yb3VuZCh2YWx1ZSkgfQorICAgIH0K
KyAgICBSb3dMYXlvdXQgeworICAgICAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZv
bnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDpxc1RyKCJSZWZy
ZXNoIGludGVydmFsIik7Y29sb3I6VmJUb2tlbnMudGV4dCB9CisgICAgICAgIEVjbGlwc2VDb21i
b0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgbW9kZWw6WyIxIHNlY29uZCIsIjIgc2Vjb25k
cyIsIjUgc2Vjb25kcyJdOyBjdXJyZW50SW5kZXg6TG9jYWxIYXJkd2FyZS5yZWZyZXNoU2Vjb25k
cz09PTE/MDpMb2NhbEhhcmR3YXJlLnJlZnJlc2hTZWNvbmRzPT09NT8yOjE7IG9uQWN0aXZhdGVk
OkxvY2FsSGFyZHdhcmUucmVmcmVzaFNlY29uZHM9WzEsMiw1XVtpbmRleF0gfQorICAgIH0KKyAg
ICBGbG93IHsKKyAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDp0cnVlCisgICAgICAgIFJlcGVhdGVy
IHsgbW9kZWw6WyJjcHUiLCJtZW1vcnkiLCJ0ZW1wZXJhdHVyZSIsImdwdSIsIm5ldHdvcmsiLCJi
YXR0ZXJ5Iiwic3RvcmFnZSJdCisgICAgICAgICAgICBkZWxlZ2F0ZTpDaGVja0JveCB7IGZvbnQu
ZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9k
eTsgdGV4dDptb2RlbERhdGE7IGNoZWNrZWQ6TG9jYWxIYXJkd2FyZS5maWVsZHMuaW5kZXhPZiht
b2RlbERhdGEpPj0wOyBvblRvZ2dsZWQ6e3ZhciBmPUxvY2FsSGFyZHdhcmUuZmllbGRzLnNsaWNl
KCk7dmFyIGk9Zi5pbmRleE9mKG1vZGVsRGF0YSk7aWYoY2hlY2tlZCYmaTwwKWYucHVzaChtb2Rl
bERhdGEpO2lmKCFjaGVja2VkJiZpPj0wKWYuc3BsaWNlKGksMSk7TG9jYWxIYXJkd2FyZS5maWVs
ZHM9Zn0gfQorICAgICAgICB9CisgICAgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tl
bnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmls
bFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5XcmFwO3RleHQ6cXNUcigiRWNsaXBzZSB2aWRlby1l
bmdpbmUgYWN0aXZpdHkgdXNlcyB0aGlzIHByb2Nlc3PigJlzIERSTSBjb3VudGVycyB3aGVuIGV4
cG9zZWQuIEl0IGlzIG5vdCB3aG9sZS1zeXN0ZW0gR1BVIGxvYWQuIFBlci1wcm9jZXNzIEdQVSBt
ZW1vcnkgaXMgdW5hdmFpbGFibGUuIFN0b3JhZ2UgcmF0ZXMgcmVmbGVjdCB0aGUgYWN0aXZlIHJv
b3QgZGV2aWNlIHdoZW4gYWNjZXNzaWJsZS4gTm8gcHJpdmlsZWdlZCBHUFUgcHJvZmlsZXIgcnVu
cyBjb250aW51b3VzbHkuIik7Y29sb3I6VmJUb2tlbnMudGV4dERpbSB9Cit9CmRpZmYgLS1naXQg
YS9hcHAvZ3VpL0VjbGlwc2VTeXN0ZW1TZXR0aW5ncy5xbWwgYi9hcHAvZ3VpL0VjbGlwc2VTeXN0
ZW1TZXR0aW5ncy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uNWQyYmJj
OQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNsaXBzZVN5c3RlbVNldHRpbmdzLnFtbApA
QCAtMCwwICsxLDgzIEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRy
b2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBRdFF1aWNrLkNvbnRy
b2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgU3lz
dGVtQ29udHJvbHMgMS4wCitpbXBvcnQgTG9jYWxIYXJkd2FyZSAxLjAKKworQ29sdW1uTGF5b3V0
IHsKKyAgICBpZDogc3lzdGVtCisgICAgcHJvcGVydHkgYm9vbCBhY3RpdmU6IGZhbHNlCisgICAg
cHJvcGVydHkgc3RyaW5nIHBvd2VyQWN0aW9uOiAiIgorICAgIHByb3BlcnR5IHZhciBwb2ludGVy
OiBwb2ludGVyQ2hvaWNlLmN1cnJlbnRJbmRleCA+PSAwID8gKFN5c3RlbUNvbnRyb2xzLnN0YXRl
LnBvaW50ZXJzIHx8IFtdKVtwb2ludGVyQ2hvaWNlLmN1cnJlbnRJbmRleF0gfHwgKHt9KSA6ICh7
fSkKKyAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICBvbkFjdGl2ZUNoYW5nZWQ6IHsg
aWYoYWN0aXZlKSBTeXN0ZW1Db250cm9scy5vcGVuKCJjZW50ZXIiKTsgZWxzZSBTeXN0ZW1Db250
cm9scy5jbG9zZSgpIH0KKyAgICBDb21wb25lbnQub25EZXN0cnVjdGlvbjogeyBpZihhY3RpdmUp
IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCkgfQorICAgIGZ1bmN0aW9uIHJlcXVlc3QoYWN0aW9uLHZh
bHVlKSB7IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci0iK2FjdGlvbix2YWx1ZSB8fCAi
IikgfQorICAgIGZ1bmN0aW9uIHNob3dDb25uZWN0aW9ucyhraW5kKSB7IFN5c3RlbUNvbnRyb2xz
LmNsb3NlKCk7IGNvbm5lY3Rpb25zLmtpbmQ9a2luZDsgY29ubmVjdGlvbnMub3BlbigpIH0KKyAg
ICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpW
YlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3Jh
cDt0ZXh0OnFzVHIoIkVjbGlwc2VPUyDigKIgU3lzdGVtIENvbnRyb2xzIik7Y29sb3I6VmJUb2tl
bnMudGV4dDtmb250LmJvbGQ6dHJ1ZSB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vu
cy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxs
V2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7dGV4dDpTeXN0ZW1Db250cm9scy5zdGF0dXM7
Y29sb3I6VmJUb2tlbnMudGV4dERpbTt0ZXh0Rm9ybWF0OlRleHQuUGxhaW5UZXh0IH0KKyAgICBC
dXN5SW5kaWNhdG9yIHsgcnVubmluZzpzeXN0ZW0uYWN0aXZlICYmIFN5c3RlbUNvbnRyb2xzLmJ1
c3k7dmlzaWJsZTpydW5uaW5nO0xheW91dC5hbGlnbm1lbnQ6UXQuQWxpZ25IQ2VudGVyIH0KKyAg
ICBSb3dMYXlvdXQgeworICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOnRydWUKKyAgICAgICAgRWNs
aXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiV2ktRmkgbmV0d29ya3MiKTtpY29uU291cmNl
OiJxcmM6L3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnIjtvbkNsaWNrZWQ6c3lzdGVtLnNob3dDb25u
ZWN0aW9ucygid2lmaSIpIH0KKyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNU
cigiQmx1ZXRvb3RoIGRldmljZXMiKTtpY29uU291cmNlOiJxcmM6L3Jlcy9jcmltc29uLWJsdWV0
b290aC5zdmciO29uQ2xpY2tlZDpzeXN0ZW0uc2hvd0Nvbm5lY3Rpb25zKCJidCIpIH0KKyAgICB9
CisgICAgUm93TGF5b3V0IHsKKyAgICAgICAgQ2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vu
cy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigi
V2ktRmkgcmFkaW8iKTtjaGVja2VkOlN5c3RlbUNvbnRyb2xzLnN0YXRlLndpZmlfZW5hYmxlZD09
PXRydWU7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBTeXN0ZW1Db250cm9scy5zdGF0
ZS53aWZpX2VuYWJsZWQhPT1udWxsICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLndpZmlfZW5hYmxl
ZCE9PXVuZGVmaW5lZDtvblRvZ2dsZWQ6c3lzdGVtLnJlcXVlc3QoIndpZmktcmFkaW8iLGNoZWNr
ZWQ/Im9uIjoib2ZmIikgfQorICAgICAgICBDaGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5z
LmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDpxc1RyKCJC
bHVldG9vdGggcmFkaW8iKTtjaGVja2VkOlN5c3RlbUNvbnRyb2xzLnN0YXRlLmJsdWV0b290aF9l
bmFibGVkPT09dHJ1ZTtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5ICYmIFN5c3RlbUNvbnRy
b2xzLnN0YXRlLmJsdWV0b290aF9lbmFibGVkIT09bnVsbCAmJiBTeXN0ZW1Db250cm9scy5zdGF0
ZS5ibHVldG9vdGhfZW5hYmxlZCE9PXVuZGVmaW5lZDtvblRvZ2dsZWQ6c3lzdGVtLnJlcXVlc3Qo
ImJ0LXJhZGlvIixjaGVja2VkPyJvbiI6Im9mZiIpIH0KKyAgICB9CisgICAgTGFiZWwgeyBmb250
LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJv
ZHk7IHRleHQ6cXNUcigiQXVkaW8gYW5kIGJyaWdodG5lc3MiKTtjb2xvcjpWYlRva2Vucy50ZXh0
O2ZvbnQuYm9sZDp0cnVlIH0KKyAgICBSb3dMYXlvdXQgeworICAgICAgICBMYXlvdXQuZmlsbFdp
ZHRoOnRydWUKKyAgICAgICAgU2xpZGVyIHsgaWQ6dm9sdW1lO0xheW91dC5maWxsV2lkdGg6dHJ1
ZTtmcm9tOjA7dG86MTAwO3N0ZXBTaXplOjE7dmFsdWU6U3lzdGVtQ29udHJvbHMuc3RhdGUudm9s
dW1lIHx8IDA7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBTeXN0ZW1Db250cm9scy5z
dGF0ZS52b2x1bWUhPT1udWxsICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSE9PXVuZGVm
aW5lZDtBY2Nlc3NpYmxlLm5hbWU6cXNUcigiU3BlYWtlciB2b2x1bWUiKTtvblByZXNzZWRDaGFu
Z2VkOmlmKCFwcmVzc2VkJiZlbmFibGVkKXN5c3RlbS5yZXF1ZXN0KCJ2b2x1bWUiLFN0cmluZyhN
YXRoLnJvdW5kKHZhbHVlKSkpO29uTW92ZWQ6aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJl
cXVlc3QoInZvbHVtZSIsU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSkgfQorICAgICAgICBMYWJl
bCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vu
cy50eXBlQm9keTsgdGV4dDpNYXRoLnJvdW5kKHZvbHVtZS52YWx1ZSkrIiUiO2NvbG9yOlZiVG9r
ZW5zLnRleHQgfQorICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpTeXN0ZW1Db250
cm9scy5zdGF0ZS5tdXRlZD9xc1RyKCJVbm11dGUiKTpxc1RyKCJNdXRlIik7ZW5hYmxlZDp2b2x1
bWUuZW5hYmxlZDtvbkNsaWNrZWQ6c3lzdGVtLnJlcXVlc3QoIm11dGUiKSB9CisgICAgfQorICAg
IEVjbGlwc2VDb21ib0JveCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTttb2RlbDpTeXN0ZW1Db250
cm9scy5zdGF0ZS5zaW5rcyB8fCBbXTt0ZXh0Um9sZToibmFtZSI7ZW5hYmxlZDohU3lzdGVtQ29u
dHJvbHMuYnVzeSAmJiBjb3VudD4wO0FjY2Vzc2libGUubmFtZTpxc1RyKCJBdWRpbyBvdXRwdXQi
KTtjdXJyZW50SW5kZXg6e3ZhciBhPVN5c3RlbUNvbnRyb2xzLnN0YXRlLnNpbmtzIHx8IFtdO2Zv
cih2YXIgaT0wO2k8YS5sZW5ndGg7aSsrKWlmKGFbaV0uZGVmYXVsdClyZXR1cm4gaTtyZXR1cm4g
LTF9CisgICAgICAgIG9uQWN0aXZhdGVkOnN5c3RlbS5yZXF1ZXN0KCJvdXRwdXQiLG1vZGVsW2lu
ZGV4XS5pZCkgfQorICAgIFJvd0xheW91dCB7CisgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24g
eyB0ZXh0OnFzVHIoIlRlc3Qgc291bmQiKTtlbmFibGVkOnZvbHVtZS5lbmFibGVkO29uQ2xpY2tl
ZDpzeXN0ZW0ucmVxdWVzdCgidGVzdC1zb3VuZCIpIH0KKyAgICAgICAgRWNsaXBzZUNvbWJvQm94
IHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlOyBtb2RlbDpbcXNUcigiQWlyUG9kczogTG93IGxhdGVu
Y3kiKSxxc1RyKCJBaXJQb2RzOiBRdWFsaXR5IildO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1
c3k7b25BY3RpdmF0ZWQ6c3lzdGVtLnJlcXVlc3QoImFpcnBvZHMiLGluZGV4PT09MD8ibG93LWxh
dGVuY3kiOiJxdWFsaXR5IikgfQorICAgIH0KKyAgICBSZXBlYXRlciB7CisgICAgICAgIG1vZGVs
Olt7a2luZDoic2NyZWVuIixsYWJlbDpxc1RyKCJTY3JlZW4gYnJpZ2h0bmVzcyIpfSx7a2luZDoi
a2V5Ym9hcmQiLGxhYmVsOnFzVHIoIktleWJvYXJkIGxpZ2h0aW5nIil9XQorICAgICAgICBkZWxl
Z2F0ZTpDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDp0cnVlCisg
ICAgICAgICAgICBwcm9wZXJ0eSB2YXIgaGFyZHdhcmU6KFN5c3RlbUNvbnRyb2xzLnN0YXRlLmJy
aWdodG5lc3MgfHwge30pW21vZGVsRGF0YS5raW5kXQorICAgICAgICAgICAgTGFiZWwgeyBmb250
LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJv
ZHk7IHRleHQ6bW9kZWxEYXRhLmxhYmVsKyhoYXJkd2FyZT8iIOKAoiAiK2hhcmR3YXJlLnBlcmNl
bnQrIiUiOiIg4oCiICIrcXNUcigiVW5hdmFpbGFibGUiKSk7Y29sb3I6VmJUb2tlbnMudGV4dCB9
CisgICAgICAgICAgICBTbGlkZXIgeyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7ZnJvbTptb2RlbERh
dGEua2luZD09PSJzY3JlZW4iPzU6MDt0bzoxMDA7c3RlcFNpemU6MTtlbmFibGVkOiEhaGFyZHdh
cmUmJiFTeXN0ZW1Db250cm9scy5idXN5O3ZhbHVlOmhhcmR3YXJlP2hhcmR3YXJlLnBlcmNlbnQ6
MDtBY2Nlc3NpYmxlLm5hbWU6bW9kZWxEYXRhLmxhYmVsO29uUHJlc3NlZENoYW5nZWQ6aWYoIXBy
ZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3QobW9kZWxEYXRhLmtpbmQsU3RyaW5nKE1hdGgu
cm91bmQodmFsdWUpKSk7b25Nb3ZlZDppZighcHJlc3NlZCYmZW5hYmxlZClzeXN0ZW0ucmVxdWVz
dChtb2RlbERhdGEua2luZCxTdHJpbmcoTWF0aC5yb3VuZCh2YWx1ZSkpKSB9CisgICAgICAgIH0K
KyAgICB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5w
aXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiRGlzcGxheSBhbmQgaWRsZSBi
bGFua2luZyIpO2NvbG9yOlZiVG9rZW5zLnRleHQ7Zm9udC5ib2xkOnRydWUgfQorICAgIEVjbGlw
c2VDb21ib0JveCB7IGlkOm1vZGVDaG9pY2U7TGF5b3V0LmZpbGxXaWR0aDp0cnVlO21vZGVsOlN5
c3RlbUNvbnRyb2xzLnN0YXRlLmRpc3BsYXlzIHx8IFtdO3RleHRSb2xlOiJuYW1lIjtlbmFibGVk
OiFTeXN0ZW1Db250cm9scy5idXN5ICYmIGNvdW50PjA7QWNjZXNzaWJsZS5uYW1lOnFzVHIoIkRp
c3BsYXkgcmVzb2x1dGlvbiBhbmQgcmVmcmVzaCByYXRlIik7Y3VycmVudEluZGV4Ont2YXIgYT1T
eXN0ZW1Db250cm9scy5zdGF0ZS5kaXNwbGF5cyB8fCBbXTtmb3IodmFyIGk9MDtpPGEubGVuZ3Ro
O2krKylpZihhW2ldLmN1cnJlbnQpcmV0dXJuIGk7cmV0dXJuIC0xfSB9CisgICAgRWNsaXBzZUFj
dGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiQXBwbHkgZGlzcGxheSBtb2RlIOKAoiAxNS1zZWNvbmQg
cm9sbGJhY2siKTtlbmFibGVkOm1vZGVDaG9pY2UuZW5hYmxlZCYmbW9kZUNob2ljZS5jdXJyZW50
SW5kZXg+PTA7b25DbGlja2VkOnN5c3RlbS5yZXF1ZXN0KCJkaXNwbGF5Iixtb2RlQ2hvaWNlLm1v
ZGVsW21vZGVDaG9pY2UuY3VycmVudEluZGV4XS5pZCkgfQorICAgIEVjbGlwc2VDb21ib0JveCB7
IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgbW9kZWw6W3FzVHIoIk5ldmVyIGJsYW5rIikscXNUcigi
QmxhbmsgYWZ0ZXIgNSBtaW51dGVzIikscXNUcigiQmxhbmsgYWZ0ZXIgMTAgbWludXRlcyIpLHFz
VHIoIkJsYW5rIGFmdGVyIDMwIG1pbnV0ZXMiKV07ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVz
eTtvbkFjdGl2YXRlZDpzeXN0ZW0ucmVxdWVzdCgiaWRsZSIsWyIwIiwiMzAwIiwiNjAwIiwiMTgw
MCJdW2luZGV4XSkgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7
IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIlBvaW50ZXIgYW5k
IHRyYWNrcGFkIik7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LmJvbGQ6dHJ1ZSB9CisgICAgRWNs
aXBzZUNvbWJvQm94IHsgaWQ6cG9pbnRlckNob2ljZTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7bW9k
ZWw6U3lzdGVtQ29udHJvbHMuc3RhdGUucG9pbnRlcnMgfHwgW107dGV4dFJvbGU6Im5hbWUiO2Vu
YWJsZWQ6Y291bnQ+MCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7QWNjZXNzaWJsZS5uYW1lOnFzVHIo
IlBvaW50ZXIgZGV2aWNlIikgfQorICAgIFNsaWRlciB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTtm
cm9tOi0xO3RvOjE7c3RlcFNpemU6LjA1O3ZhbHVlOnN5c3RlbS5wb2ludGVyLnNwZWVkIHx8IDA7
ZW5hYmxlZDpzeXN0ZW0ucG9pbnRlci5zcGVlZCE9PXVuZGVmaW5lZCYmIVN5c3RlbUNvbnRyb2xz
LmJ1c3k7QWNjZXNzaWJsZS5uYW1lOnFzVHIoIlBvaW50ZXIgYWNjZWxlcmF0aW9uIHNwZWVkIik7
b25QcmVzc2VkQ2hhbmdlZDppZighcHJlc3NlZCYmZW5hYmxlZClzeXN0ZW0ucmVxdWVzdCgicG9p
bnRlci1zcGVlZCIsc3lzdGVtLnBvaW50ZXIuaWQrIjoiK3ZhbHVlLnRvRml4ZWQoMikpO29uTW92
ZWQ6aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3QoInBvaW50ZXItc3BlZWQiLHN5
c3RlbS5wb2ludGVyLmlkKyI6Iit2YWx1ZS50b0ZpeGVkKDIpKSB9CisgICAgQ2hlY2tCb3ggeyBm
b250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlw
ZUJvZHk7IHRleHQ6cXNUcigiTmF0dXJhbCBzY3JvbGxpbmciKTtjaGVja2VkOnN5c3RlbS5wb2lu
dGVyLm5hdHVyYWw9PT0xO2VuYWJsZWQ6c3lzdGVtLnBvaW50ZXIubmF0dXJhbCE9PXVuZGVmaW5l
ZCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25Ub2dnbGVkOnN5c3RlbS5yZXF1ZXN0KCJwb2ludGVy
LW5hdHVyYWwiLHN5c3RlbS5wb2ludGVyLmlkKyI6IisoY2hlY2tlZD8iMSI6IjAiKSkgfQorICAg
IENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXpl
OlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIlRhcCB0byBjbGljayIpO2NoZWNrZWQ6c3lz
dGVtLnBvaW50ZXIudGFwPT09MTtlbmFibGVkOnN5c3RlbS5wb2ludGVyLnRhcCE9PXVuZGVmaW5l
ZCYmIVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25Ub2dnbGVkOnN5c3RlbS5yZXF1ZXN0KCJwb2ludGVy
LXRhcCIsc3lzdGVtLnBvaW50ZXIuaWQrIjoiKyhjaGVja2VkPyIxIjoiMCIpKSB9CisgICAgTGFi
ZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tl
bnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7dGV4
dDpxc1RyKCJQb2ludGVyIGFuZCBibGFua2luZyBjaGFuZ2VzIGN1cnJlbnRseSBhcHBseSB0byB0
aGlzIFgxMSBzZXNzaW9uLiBVbnN1cHBvcnRlZCBkZXZpY2UgY29udHJvbHMgYXJlIGRpc2FibGVk
LiBEaXNwbGF5IGNoYW5nZXMgcmV2ZXJ0IHVubGVzcyBjb25maXJtZWQuIik7Y29sb3I6VmJUb2tl
bnMudGV4dERpbSB9CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsg
Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiUmVjb3ZlcnkgYW5k
IHBvd2VyIik7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LmJvbGQ6dHJ1ZSB9CisgICAgRWNsaXBz
ZUNvbWJvQm94IHsgaWQ6ZnJvbnRlbmQ7bW9kZWw6WyJFY2xpcHNlIiwiQXJ0ZW1pcyIsIlBlZ2Fz
dXMiLCJNb29ubGlnaHQiLCJDb2NvT1MiXTtBY2Nlc3NpYmxlLm5hbWU6cXNUcigiRnJvbnRlbmQg
Zm9yIG5leHQgYm9vdCIpIH0KKyAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpxc1RyKCJT
YXZlIGZyb250ZW5kIGZvciBuZXh0IGJvb3QiKTtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5
O29uQ2xpY2tlZDpzeXN0ZW0ucmVxdWVzdCgiZnJvbnRlbmQiLFsidmliZW1pcyIsImFydGVtaXMi
LCJwZWdhc3VzIiwibW9vbmxpZ2h0IiwiY29jb29zIl1bZnJvbnRlbmQuY3VycmVudEluZGV4XSkg
fQorICAgIEZsb3cgeworICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOnRydWU7c3BhY2luZzpWYlRv
a2Vucy5zcGFjZTIKKyAgICAgICAgUmVwZWF0ZXIgeyBtb2RlbDpbe25hbWU6cXNUcigiUmVzdGFy
dCBmcm9udGVuZCIpLGFjdGlvbjoicmVzdGFydC1mcm9udGVuZCJ9LHtuYW1lOnFzVHIoIlJlc3Rh
cnQgRWNsaXBzZU9TIiksYWN0aW9uOiJyZWJvb3QifSx7bmFtZTpxc1RyKCJTaHV0IGRvd24iKSxh
Y3Rpb246InBvd2Vyb2ZmIn1dCisgICAgICAgICAgICBkZWxlZ2F0ZTpFY2xpcHNlQWN0aW9uQnV0
dG9uIHsgdGV4dDptb2RlbERhdGEubmFtZTtpY29uU291cmNlOiJxcmM6L3Jlcy9lY2xpcHNlLXBv
d2VyLnN2ZyI7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeTtvbkNsaWNrZWQ6e3N5c3RlbS5w
b3dlckFjdGlvbj1tb2RlbERhdGEuYWN0aW9uO3Bvd2VyLm9wZW4oKX0gfQorICAgICAgICB9Cisg
ICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIlJlZGFjdGVkIHN1cHBvcnQg
cmVwb3J0Iik7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeTtvbkNsaWNrZWQ6c3lzdGVtLnJl
cXVlc3QoInJlcG9ydCIpIH0KKyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNU
cigiUmVmcmVzaCBjb250cm9scyIpO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25DbGlj
a2VkOnN5c3RlbS5yZXF1ZXN0KCJsaXN0IikgfQorICAgIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFt
aWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsg
TGF5b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcDt0ZXh0OnFzVHIoIlN1c3Bl
bmQgYW5kIGxpZCBwcmVzZXRzIGF3YWl0IHBoeXNpY2FsIHZhbGlkYXRpb24uIFJlY292ZXJ5IGNv
bnNvbGU6IENvbnRyb2wgKyBPcHRpb24gKyBGMiAoRm4gaWYgbmVlZGVkKS4iKTtjb2xvcjpWYlRv
a2Vucy50ZXh0RGltIH0KKyAgICBFY2xpcHNlSGFyZHdhcmVNb25pdG9yIHsgTGF5b3V0LmZpbGxX
aWR0aDp0cnVlO2FjdGl2ZTpzeXN0ZW0uYWN0aXZlIH0KKyAgICBTeXN0ZW1Db25uZWN0aW9uc0Rp
YWxvZyB7IGlkOmNvbm5lY3Rpb25zO3BhcmVudDpPdmVybGF5Lm92ZXJsYXk7b25DbG9zZWQ6aWYo
c3lzdGVtLmFjdGl2ZSlyZXN1bWUucmVzdGFydCgpIH0KKyAgICBUaW1lciB7IGlkOnJlc3VtZTtp
bnRlcnZhbDo2MDA7b25UcmlnZ2VyZWQ6aWYoc3lzdGVtLmFjdGl2ZSlTeXN0ZW1Db250cm9scy5v
cGVuKCJjZW50ZXIiKSB9CisgICAgTmF2aWdhYmxlRGlhbG9nIHsgaWQ6cG93ZXI7cGFyZW50Ok92
ZXJsYXkub3ZlcmxheTt3aWR0aDpNYXRoLm1pbig0NDAscGFyZW50LndpZHRoLTMyKTt0aXRsZTpx
c1RyKCJDb25maXJtIHN5c3RlbSBhY3Rpb24iKTtzdGFuZGFyZEJ1dHRvbnM6RGlhbG9nLlllc3xE
aWFsb2cuTm87YmFja2dyb3VuZDpSZWN0YW5nbGV7Y29sb3I6VmJUb2tlbnMuYmdFbGV2O3JhZGl1
czpWYlRva2Vucy5yYWRpdXNEaWFsb2c7Ym9yZGVyLmNvbG9yOlZiVG9rZW5zLnN0cm9rZX0KKyAg
ICAgICAgb25BY2NlcHRlZDpTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItIitzeXN0ZW0u
cG93ZXJBY3Rpb24sIiIsdHJ1ZSk7Y29udGVudEl0ZW06TGFiZWx7d3JhcE1vZGU6VGV4dC5XcmFw
O3RleHQ6cXNUcigiUHJvY2VlZCB3aXRoICUxPyBBY3RpdmUgc3RyZWFtaW5nIHdpbGwgZW5kLiIp
LmFyZyhzeXN0ZW0ucG93ZXJBY3Rpb24pO2NvbG9yOlZiVG9rZW5zLnRleHR9IH0KKyAgICBOYXZp
Z2FibGVEaWFsb2cgeyBpZDpjb25maXJtYXRpb247cGFyZW50Ok92ZXJsYXkub3ZlcmxheTt3aWR0
aDpNYXRoLm1pbig0ODAscGFyZW50LndpZHRoLTMyKTt0aXRsZTpxc1RyKCJLZWVwIGRpc3BsYXkg
bW9kZT8iKTtzdGFuZGFyZEJ1dHRvbnM6RGlhbG9nLlllc3xEaWFsb2cuTm87Y2xvc2VQb2xpY3k6
UG9wdXAuTm9BdXRvQ2xvc2U7YmFja2dyb3VuZDpSZWN0YW5nbGV7Y29sb3I6VmJUb2tlbnMuYmdF
bGV2O3JhZGl1czpWYlRva2Vucy5yYWRpdXNEaWFsb2c7Ym9yZGVyLmNvbG9yOlZiVG9rZW5zLnN0
cm9rZX0KKyAgICAgICAgb25BY2NlcHRlZDpTeXN0ZW1Db250cm9scy5hbnN3ZXIoInllcyIpO29u
UmVqZWN0ZWQ6U3lzdGVtQ29udHJvbHMuYW5zd2VyKCJubyIpO2NvbnRlbnRJdGVtOkxhYmVse3dy
YXBNb2RlOlRleHQuV3JhcDt0ZXh0OlN5c3RlbUNvbnRyb2xzLnByb21wdDtjb2xvcjpWYlRva2Vu
cy50ZXh0fSB9CisgICAgQ29ubmVjdGlvbnMgeyB0YXJnZXQ6U3lzdGVtQ29udHJvbHM7ZnVuY3Rp
b24gb25DaGFuZ2VkKCl7aWYoc3lzdGVtLmFjdGl2ZSYmU3lzdGVtQ29udHJvbHMucHJvbXB0Lmxl
bmd0aD4wJiYhY29ubmVjdGlvbnMub3BlbmVkKWNvbmZpcm1hdGlvbi5vcGVuKCk7aWYoIVN5c3Rl
bUNvbnRyb2xzLmJ1c3kpY29uZmlybWF0aW9uLmNsb3NlKCl9IH0KK30KZGlmZiAtLWdpdCBhL2Fw
cC9ndWkvTmF2aWdhYmxlRGlhbG9nLnFtbCBiL2FwcC9ndWkvTmF2aWdhYmxlRGlhbG9nLnFtbApp
bmRleCA0Mzg0ZDViLi5iZDllZGE1IDEwMDY0NAotLS0gYS9hcHAvZ3VpL05hdmlnYWJsZURpYWxv
Zy5xbWwKKysrIGIvYXBwL2d1aS9OYXZpZ2FibGVEaWFsb2cucW1sCkBAIC0xLDcgKzEsMzUgQEAK
IGltcG9ydCBRdFF1aWNrIDIuMAogaW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQg
UXRRdWljay5Db250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEu
MAogCiBEaWFsb2cgeworICAgIGlkOiBkaWFsb2cKKyAgICBmb250LmZhbWlseTogVmJUb2tlbnMu
Zm9udEJvZHkKKyAgICBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUJvZHkKKyAgICBNYXRl
cmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICBNYXRlcmlhbC5mb3JlZ3JvdW5k
OiBWYlRva2Vucy50ZXh0CisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAg
ICBPdmVybGF5Lm1vZGFsOiBSZWN0YW5nbGUge2NvbG9yOlZiVG9rZW5zLmRpYWxvZ1NjcmltfQor
ICAgIE92ZXJsYXkubW9kZWxlc3M6IFJlY3RhbmdsZSB7Y29sb3I6VmJUb2tlbnMuZGlhbG9nU2Ny
aW19CisgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgeyByYWRpdXM6VmJUb2tlbnMu
cmFkaXVzRGlhbG9nIH0KKyAgICBoZWFkZXI6IExhYmVsIHsKKyAgICAgICAgdmlzaWJsZTogZGlh
bG9nLnRpdGxlLmxlbmd0aCA+IDAKKyAgICAgICAgdGV4dDogZGlhbG9nLnRpdGxlOyB0ZXh0Rm9y
bWF0OiBUZXh0LlBsYWluVGV4dDsgY29sb3I6VmJUb2tlbnMudGV4dAorICAgICAgICBmb250LmZh
bWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7
IGZvbnQuYm9sZDp0cnVlCisgICAgICAgIHBhZGRpbmc6VmJUb2tlbnMuc3BhY2U0OyBlbGlkZTpU
ZXh0LkVsaWRlUmlnaHQKKyAgICB9CisgICAgZm9vdGVyOiBEaWFsb2dCdXR0b25Cb3ggeworICAg
ICAgICBiYWNrZ3JvdW5kOiBJdGVtIHt9CisgICAgICAgIHZpc2libGU6IGRpYWxvZy5zdGFuZGFy
ZEJ1dHRvbnMgIT09IERpYWxvZy5Ob0J1dHRvbgorICAgICAgICBzdGFuZGFyZEJ1dHRvbnM6IGRp
YWxvZy5zdGFuZGFyZEJ1dHRvbnMKKyAgICAgICAgaW1wbGljaXRIZWlnaHQ6IHZpc2libGUgPyBN
YXRoLm1heCg0NCxWYlRva2Vucy50eXBlTGFiZWwrMjApKzIqVmJUb2tlbnMuc3BhY2UzIDogMAor
ICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTIKKyAgICAgICAgcGFkZGluZzogVmJUb2tl
bnMuc3BhY2UzCisgICAgICAgIGRlbGVnYXRlOiBFY2xpcHNlQWN0aW9uQnV0dG9uIHt9CisgICAg
ICAgIG9uQWNjZXB0ZWQ6IGRpYWxvZy5hY2NlcHQoKQorICAgICAgICBvblJlamVjdGVkOiBkaWFs
b2cucmVqZWN0KCkKKyAgICB9CiAgICAgbW9kYWw6IHRydWUKICAgICBhbmNob3JzLmNlbnRlcklu
OiBPdmVybGF5Lm92ZXJsYXkKIApkaWZmIC0tZ2l0IGEvYXBwL2d1aS9OYXZpZ2FibGVNZW51LnFt
bCBiL2FwcC9ndWkvTmF2aWdhYmxlTWVudS5xbWwKaW5kZXggYTdiMjBmMC4uNTA1ZjM5NiAxMDA2
NDQKLS0tIGEvYXBwL2d1aS9OYXZpZ2FibGVNZW51LnFtbAorKysgYi9hcHAvZ3VpL05hdmlnYWJs
ZU1lbnUucW1sCkBAIC0xLDggKzEsMTEgQEAKIGltcG9ydCBRdFF1aWNrIDIuMAogaW1wb3J0IFF0
UXVpY2suQ29udHJvbHMgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKIAogTWVudSB7
CiAgICAgcHJvcGVydHkgdmFyIGluaXRpYXRvcgorICAgIHBhZGRpbmc6IFZiVG9rZW5zLnNwYWNl
MgorICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHtyYWRpdXM6VmJUb2tlbnMucmFk
aXVzQ29udHJvbH0KIAogICAgIG9uT3BlbmVkOiB7CiAgICAgICAgIC8vIElmIHRoZSBpbml0aWF0
aW5nIG9iamVjdCBjdXJyZW50bHkgaGFzIGtleWJvYXJkIGZvY3VzLApkaWZmIC0tZ2l0IGEvYXBw
L2d1aS9OYXZpZ2FibGVUb29sQnV0dG9uLnFtbCBiL2FwcC9ndWkvTmF2aWdhYmxlVG9vbEJ1dHRv
bi5xbWwKaW5kZXggNWI2NDY3MS4uYTc5OTYxOCAxMDA2NDQKLS0tIGEvYXBwL2d1aS9OYXZpZ2Fi
bGVUb29sQnV0dG9uLnFtbAorKysgYi9hcHAvZ3VpL05hdmlnYWJsZVRvb2xCdXR0b24ucW1sCkBA
IC0yNyw3ICsyNyw3IEBAIFRvb2xCdXR0b24gewogICAgIHBhZGRpbmc6IDAKICAgICBMYXlvdXQu
YWxpZ25tZW50OiBRdC5BbGlnblZDZW50ZXIKIAotICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7
CisgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgewogICAgICAgICByYWRpdXM6IFZi
VG9rZW5zLnJhZGl1c0ljb25CdXR0b24KICAgICAgICAgY29sb3I6IGJ0bi5hY3RpdmVGb2N1cyA/
IFZiVG9rZW5zLmZvY3VzZWRGaWxsIDogKGJ0bi5ob3ZlcmVkID8gVmJUb2tlbnMuYmdFbGV2MiA6
IFZiVG9rZW5zLmJnRWxldikKICAgICAgICAgYm9yZGVyLndpZHRoOiAxCmRpZmYgLS1naXQgYS9h
cHAvZ3VpL1BjVmlldy5xbWwgYi9hcHAvZ3VpL1BjVmlldy5xbWwKaW5kZXggZjBlNzM5YS4uZmIx
OTg0YSAxMDA2NDQKLS0tIGEvYXBwL2d1aS9QY1ZpZXcucW1sCisrKyBiL2FwcC9ndWkvUGNWaWV3
LnFtbApAQCAtNDMsNyArNDMsMTYgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAgLy8gYmFjayB0
byBtaW5NYXJnaW4gKGRlZmF1bHQgMTBweCkg4oCUIGNhcmRzIGh1Z2dlZCB0aGUgc2NyZWVuIGVk
Z2UsIG1pc2FsaWduZWQgd2l0aCB0aGUKICAgICAvLyA1NnB4IGhlYWRlciBhbmQgdmlzdWFsbHkg
Y2xpcHBpbmcgdGhlIGZvY3VzIHJpbmcncyBvdXRlciBnbG93LiBBbGlnbiBwYXJ0aWFsIHJvd3Mg
d2l0aAogICAgIC8vIHRoZSByZWRlc2lnbidzIHNjcmVlbiBwYWRkaW5nIGluc3RlYWQuCisgICAg
cmVhZG9ubHkgcHJvcGVydHkgYm9vbCBnbGFzc1dpZGU6IHdpZHRoID49IDEyNDAgJiYgaGVpZ2h0
ID49IDU0MAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCByYWlsU3BhY2U6IHdpZHRoID49IDkw
MCA/IDg0IDogMAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBsb2NhbFNwYWNlOiBnbGFzc1dp
ZGUgPyBNYXRoLnJvdW5kKDI1MipWYlRva2Vucy50ZXh0U2NhbGUpIDogMAorICAgIHJlYWRvbmx5
IHByb3BlcnR5IGludCBob3N0U3BhY2U6IDAKICAgICBtaW5NYXJnaW46IFZiVG9rZW5zLnNjcmVl
blBhZFgKKyAgICBhdmFpbGFibGVXaWR0aDogd2lkdGggLSByYWlsU3BhY2UgLSBsb2NhbFNwYWNl
IC0gaG9zdFNwYWNlIC0gMiptaW5NYXJnaW4KKyAgICBvblJhaWxTcGFjZUNoYW5nZWQ6IHVwZGF0
ZU1hcmdpbnMoKQorICAgIG9uTG9jYWxTcGFjZUNoYW5nZWQ6IHVwZGF0ZU1hcmdpbnMoKQorICAg
IG9uSG9zdFNwYWNlQ2hhbmdlZDogdXBkYXRlTWFyZ2lucygpCisgICAgZnVuY3Rpb24gdXBkYXRl
TWFyZ2lucygpIHsgbGVmdE1hcmdpbj1ob3Jpem9udGFsTWFyZ2luK3JhaWxTcGFjZStob3N0U3Bh
Y2U7cmlnaHRNYXJnaW49aG9yaXpvbnRhbE1hcmdpbitsb2NhbFNwYWNlIH0KICAgICAvLyBUaGUg
IkFkZCBhIGNvbXB1dGVyIiBnaG9zdCBjYXJkIGlzIGhhbmQtcGxhY2VkIGF0IHRoZSBpbmRleD09
Y291bnQgY2VsbCAoc2VlIHRoZSBkZWxlZ2F0ZSdzCiAgICAgLy8gc2libGluZyBiZWxvdykuIEdy
aWRWaWV3LmNvbnRlbnRIZWlnaHQgb25seSBjb3VudHMgcmVhbCBkZWxlZ2F0ZXMsIHNvIHdoZW4g
dGhlIGxhc3Qgcm93IGlzIEZVTEwKICAgICAvLyAoY291bnQgaXMgYSBtdWx0aXBsZSBvZiB0aGUg
Y29sdW1uIGNvdW50KSB0aGUgZ2hvc3QgY2FyZCBzdGFydHMgYSBicmFuZC1uZXcgdmlydHVhbCBy
b3cgYXQKQEAgLTUyLDcgKzYxLDcgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAgYm90dG9tTWFy
Z2luOiAocGNIaW50QmFyLnZpc2libGUgPyBwY0hpbnRCYXIuaGVpZ2h0IDogMCkgKyAxMgogICAg
ICAgICAgICAgICAgICAgKyAoKGNvdW50ID4gMCAmJiAoY291bnQgJSBNYXRoLm1heCgxLCBNYXRo
LmZsb29yKGl0ZW1zUGVyUm93KSkpID09PSAwKSA/IGNlbGxIZWlnaHQgOiAwKQogICAgIC8vIFJl
ZGVzaWduOiA0MzBweCByaWNoIGhvc3QgY2FyZHMgKGdhcCAzMikgaW4gYSBjZW50ZXJlZCB3cmFw
cGluZyByb3cuCi0gICAgY2VsbFdpZHRoOiA0NjI7IGNlbGxIZWlnaHQ6IDI3NDsKKyAgICBjZWxs
V2lkdGg6IDM5MjsgY2VsbEhlaWdodDogMjY2OwogICAgIG9iamVjdE5hbWU6IHFzVHIoIkNvbXB1
dGVycyIpCiAKICAgICAvLyBELXBhZCBzZWxlY3Rpb24gc3RhdGUgZm9yIHRoZSBBZGQtYS1jb21w
dXRlciBnaG9zdCDigJQgV0lUSE9VVCBmb2N1cy4gVGhlCkBAIC0xMDUsMTkgKzExNCwxOSBAQCBD
ZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAgYW5jaG9ycy5sZWZ0OiBwYXJlbnQubGVmdAogICAg
ICAgICBhbmNob3JzLnJpZ2h0OiBwYXJlbnQucmlnaHQKICAgICAgICAgdmlzaWJsZTogdHJ1ZQot
ICAgICAgICBoZWlnaHQ6IDc4CisgICAgICAgIGhlaWdodDogNjYKIAotICAgICAgICBSZWN0YW5n
bGUgeyBhbmNob3JzLmZpbGw6IHBhcmVudDsgY29sb3I6IFZiVG9rZW5zLmJnV2luZG93IH0KKyAg
ICAgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGNvbG9yOiAidHJhbnNwYXJl
bnQiIH0KIAogICAgICAgICBSb3cgewogICAgICAgICAgICAgYW5jaG9ycy5sZWZ0OiBwYXJlbnQu
bGVmdAotICAgICAgICAgICAgYW5jaG9ycy5sZWZ0TWFyZ2luOiBWYlRva2Vucy5zY3JlZW5QYWRY
CisgICAgICAgICAgICBhbmNob3JzLmxlZnRNYXJnaW46IFZiVG9rZW5zLnNjcmVlblBhZFgrcGNH
cmlkLnJhaWxTcGFjZStwY0dyaWQuaG9zdFNwYWNlCiAgICAgICAgICAgICBhbmNob3JzLmJvdHRv
bTogcGFyZW50LmJvdHRvbQogICAgICAgICAgICAgYW5jaG9ycy5ib3R0b21NYXJnaW46IDYKICAg
ICAgICAgICAgIHNwYWNpbmc6IDE0CiAgICAgICAgICAgICBUZXh0IHsKICAgICAgICAgICAgICAg
ICBpZDogc2VjdGlvblRpdGxlCi0gICAgICAgICAgICAgICAgdGV4dDogcXNUcigiQ29tcHV0ZXJz
IikKKyAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJIb3N0cyIpCiAgICAgICAgICAgICAgICAg
Zm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5CiAgICAgICAgICAgICAgICAgZm9udC53
ZWlnaHQ6IEZvbnQuQm9sZAogICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vu
cy5zaXplU2NyZWVuVGl0bGUKQEAgLTEzNCw2ICsxNDMsMjQgQEAgQ2VudGVyZWRHcmlkVmlldyB7
CiAgICAgICAgIH0KICAgICB9CiAKKworICAgIC8vIENyaW1zb24gR2xhc3MgZGFzaGJvYXJkIGNo
cm9tZSBsaXZlcyBpbiB0aGUgdmlld3BvcnQsIG91dHNpZGUgY29udGVudEl0ZW0uCisgICAgQ3Jp
bXNvbkdsYXNzUmFpbCB7CisgICAgICAgIHBhcmVudDpwY0dyaWQKKyAgICAgICAgejoxMTt4OjEy
O3k6MTY7d2lkdGg6NjQ7aGVpZ2h0Ok1hdGgubWF4KDI4MCxwY0dyaWQuaGVpZ2h0LTMyLShwY0hp
bnRCYXIudmlzaWJsZT9wY0hpbnRCYXIuaGVpZ2h0OjApKQorICAgICAgICB2aXNpYmxlOnBjR3Jp
ZC5yYWlsU3BhY2U+MDtpbkxpYnJhcnk6ZmFsc2UKKyAgICAgICAgb25Ib21lUmVxdWVzdGVkOiB7
IGlmKHN0YWNrVmlldy5kZXB0aD4xKSBzdGFja1ZpZXcucG9wKG51bGwpO2Vsc2UgcGNHcmlkLmZv
cmNlQWN0aXZlRm9jdXMoKSB9CisgICAgICAgIG9uU2V0dGluZ3NSZXF1ZXN0ZWQ6IHNldHRpbmdz
QnV0dG9uLmNsaWNrZWQoKQorICAgICAgICBvbkNvbnRyb2xzUmVxdWVzdGVkOiBlY2xpcHNlQ2Vu
dGVyQnV0dG9uLmNsaWNrZWQoKQorICAgIH0KKyAgICBDcmltc29uTG9jYWxQYW5lbCB7CisgICAg
ICAgIHBhcmVudDpwY0dyaWQKKyAgICAgICAgejoxMTthbmNob3JzLnJpZ2h0OnBhcmVudC5yaWdo
dDthbmNob3JzLnJpZ2h0TWFyZ2luOjE2O3k6MTY7d2lkdGg6TWF0aC5tYXgoMCxwY0dyaWQubG9j
YWxTcGFjZS0yOCkKKyAgICAgICAgaGVpZ2h0Ok1hdGgubWF4KDI0MCxwY0dyaWQuaGVpZ2h0LTMy
LShwY0hpbnRCYXIudmlzaWJsZT9wY0hpbnRCYXIuaGVpZ2h0OjApKTt2aXNpYmxlOnBjR3JpZC5s
b2NhbFNwYWNlPjAKKyAgICAgICAgYWN0aXZlOnZpc2libGUgJiYgcGNHcmlkLlN0YWNrVmlldy5z
dGF0dXM9PT1TdGFja1ZpZXcuQWN0aXZlCisgICAgICAgIG9uQ29udHJvbHNSZXF1ZXN0ZWQ6IGVj
bGlwc2VDZW50ZXJCdXR0b24uY2xpY2tlZCgpCisgICAgfQorCiAgICAgLy8gUGVyc2lzdGVudCBn
YW1lcGFkIGhpbnQgYmFyLCBmaXhlZCBhdCB0aGUgYm90dG9tLiBHcmlkIGJvdHRvbU1hcmdpbiBj
bGVhcnMgaXQuCiAgICAgVmJIaW50QmFyIHsKICAgICAgICAgaWQ6IHBjSGludEJhcgpAQCAtMjY5
LDcgKzI5Niw3IEBAIENlbnRlcmVkR3JpZFZpZXcgewogCiAgICAgZnVuY3Rpb24gY3JlYXRlTW9k
ZWwoKQogICAgIHsKLSAgICAgICAgdmFyIG1vZGVsID0gUXQuY3JlYXRlUW1sT2JqZWN0KCdpbXBv
cnQgQ29tcHV0ZXJNb2RlbCAxLjA7IENvbXB1dGVyTW9kZWwge30nLCBwYXJlbnQsICcnKQorICAg
ICAgICB2YXIgbW9kZWwgPSBRdC5jcmVhdGVRbWxPYmplY3QoJ2ltcG9ydCBDb21wdXRlck1vZGVs
IDEuMDsgQ29tcHV0ZXJNb2RlbCB7fScsIHBjR3JpZCwgJycpCiAgICAgICAgIG1vZGVsLmluaXRp
YWxpemUoQ29tcHV0ZXJNYW5hZ2VyKQogICAgICAgICBtb2RlbC5wYWlyaW5nQ29tcGxldGVkLmNv
bm5lY3QocGFpcmluZ0NvbXBsZXRlKQogICAgICAgICBtb2RlbC5jb25uZWN0aW9uVGVzdENvbXBs
ZXRlZC5jb25uZWN0KHRlc3RDb25uZWN0aW9uRGlhbG9nLmNvbm5lY3Rpb25UZXN0Q29tcGxldGUp
CkBAIC0zMDEsNyArMzI4LDcgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAKICAgICBkZWxlZ2F0ZTog
TmF2aWdhYmxlSXRlbURlbGVnYXRlIHsKICAgICAgICAgaWQ6IHBjRGVsZWdhdGUKLSAgICAgICAg
d2lkdGg6IDQzMDsgaGVpZ2h0OiAyNDI7CisgICAgICAgIHdpZHRoOiBwY0dyaWQuY2VsbFdpZHRo
IC0gMjA7IGhlaWdodDogMjQyOwogICAgICAgICBncmlkOiBwY0dyaWQKIAogICAgICAgICAvLyBU
aGUgTWF0ZXJpYWwgc3R5bGUgcGFpbnRzIGFuIGFsd2F5cy12aXNpYmxlCkBAIC00NDQsNyArNDcx
LDcgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxl
OiBtb2RlbC5vbmxpbmUgJiYgbW9kZWwucGFpcmVkLAogICAgICAgICAgICAgICAgICAgICAgICAg
dHJpZ2dlcjogZnVuY3Rpb24oKSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdmFyIGNv
bXBvbmVudCA9IFF0LmNyZWF0ZUNvbXBvbmVudCgiQXBwVmlldy5xbWwiKQotICAgICAgICAgICAg
ICAgICAgICAgICAgICAgIHZhciBhcHBWaWV3ID0gY29tcG9uZW50LmNyZWF0ZU9iamVjdChzdGFj
a1ZpZXcsIHsiY29tcHV0ZXJJbmRleCI6IGluZGV4LCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUs
ICJzaG93SGlkZGVuR2FtZXMiOiB0cnVlLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhv
c3RUeXBlIjogbW9kZWwuaG9zdFR5cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0
fSkKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5j
cmVhdGVPYmplY3Qoc3RhY2tWaWV3LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgImNyaW1zb25I
b3N0IjogY29tcHV0ZXJNb2RlbC5jcmltc29uSG9zdChpbmRleCksICJvYmplY3ROYW1lIjogbW9k
ZWwubmFtZSwgInNob3dIaWRkZW5HYW1lcyI6IHRydWUsICJob3N0T25saW5lIjogbW9kZWwub25s
aW5lLCAiaG9zdFR5cGUiOiBtb2RlbC5ob3N0VHlwZSwgImhvc3RUcmFuc3BvcnQiOiBtb2RlbC50
cmFuc3BvcnR9KQogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0YWNrVmlldy5wdXNoKGFw
cFZpZXcpCiAgICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgIH0s
CkBAIC01MzUsNyArNTYyLDcgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAgICAgICAgICAgICAg
ZWxzZSBpZiAobW9kZWwucGFpcmVkKSB7CiAgICAgICAgICAgICAgICAgICAgIC8vIGdvIHRvIGdh
bWUgdmlldwogICAgICAgICAgICAgICAgICAgICB2YXIgY29tcG9uZW50ID0gUXQuY3JlYXRlQ29t
cG9uZW50KCJBcHBWaWV3LnFtbCIpCi0gICAgICAgICAgICAgICAgICAgIHZhciBhcHBWaWV3ID0g
Y29tcG9uZW50LmNyZWF0ZU9iamVjdChzdGFja1ZpZXcsIHsiY29tcHV0ZXJJbmRleCI6IGluZGV4
LCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUsICJob3N0T25saW5lIjogbW9kZWwub25saW5lLCAi
aG9zdFR5cGUiOiBtb2RlbC5ob3N0VHlwZSwgImhvc3RUcmFuc3BvcnQiOiBtb2RlbC50cmFuc3Bv
cnR9KQorICAgICAgICAgICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVP
YmplY3Qoc3RhY2tWaWV3LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgImNyaW1zb25Ib3N0Ijog
Y29tcHV0ZXJNb2RlbC5jcmltc29uSG9zdChpbmRleCksICJvYmplY3ROYW1lIjogbW9kZWwubmFt
ZSwgImhvc3RPbmxpbmUiOiBtb2RlbC5vbmxpbmUsICJob3N0VHlwZSI6IG1vZGVsLmhvc3RUeXBl
LCAiaG9zdFRyYW5zcG9ydCI6IG1vZGVsLnRyYW5zcG9ydH0pCiAgICAgICAgICAgICAgICAgICAg
IHN0YWNrVmlldy5wdXNoKGFwcFZpZXcpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAg
ICAgIGVsc2UgewpAQCAtNjE2LDcgKzY0Myw3IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgICAg
ICBvblNlbGVjdGVkQ2hhbmdlZDogYWRkUGNEYXNoZWRCb3JkZXIucmVxdWVzdFBhaW50KCkKICAg
ICAgICAgeDogKHBjR3JpZC5jb3VudCAlIGNvbHVtbnMpICogcGNHcmlkLmNlbGxXaWR0aAogICAg
ICAgICB5OiBNYXRoLmZsb29yKHBjR3JpZC5jb3VudCAvIGNvbHVtbnMpICogcGNHcmlkLmNlbGxI
ZWlnaHQKLSAgICAgICAgd2lkdGg6IDQzMAorICAgICAgICB3aWR0aDogcGNHcmlkLmNlbGxXaWR0
aC0yMAogICAgICAgICBoZWlnaHQ6IDI0MgogICAgICAgICB6OiAyCiAKQEAgLTYyNSw3ICs2NTIs
NyBAQCBDZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50
CiAgICAgICAgICAgICByYWRpdXM6IDIwCiAgICAgICAgICAgICBjb2xvcjogYWRkUGNDYXJkU2xv
dC5oaWdobGlnaHRlZCA/IFZiVG9rZW5zLmJnRWxldiA6ICJ0cmFuc3BhcmVudCIKLSAgICAgICAg
ICAgIEJlaGF2aW9yIG9uIGNvbG9yIHsgQ29sb3JBbmltYXRpb24geyBkdXJhdGlvbjogMTIwIH0g
fQorICAgICAgICAgICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xvckFuaW1hdGlvbiB7IGR1cmF0
aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8gMTIwIDogMCB9IH0KICAgICAgICAgfQogCiAg
ICAgICAgIENhbnZhcyB7CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1F1aWNrTWVudS5xbWwgYi9hcHAv
Z3VpL1F1aWNrTWVudS5xbWwKaW5kZXggYjAzM2QyNi4uODcyZmZmOSAxMDA2NDQKLS0tIGEvYXBw
L2d1aS9RdWlja01lbnUucW1sCisrKyBiL2FwcC9ndWkvUXVpY2tNZW51LnFtbApAQCAtMjEsNiAr
MjEsMTAgQEAgUmVjdGFuZ2xlIHsKICAgICByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c1dpbmRvdwog
ICAgIGJvcmRlci5jb2xvcjogVmJUb2tlbnMuZGl2aWRlcgogICAgIGJvcmRlci53aWR0aDogMQor
ICAgIGdyYWRpZW50OiBHcmFkaWVudCB7CisgICAgICAgIEdyYWRpZW50U3RvcCB7cG9zaXRpb246
MDtjb2xvcjpWYlRva2Vucy5nbGFzc1RvcH0KKyAgICAgICAgR3JhZGllbnRTdG9wIHtwb3NpdGlv
bjoxO2NvbG9yOlZiVG9rZW5zLnN1cmZhY2VSYWlzZWR9CisgICAgfQogICAgIHZpc2libGU6IHRy
dWUgIC8vIEFsd2F5cyB2aXNpYmxlIHdoZW4gY3JlYXRlZAogICAgIG9wYWNpdHk6IDEuMAogICAg
IApAQCAtMzYsNyArNDAsNyBAQCBSZWN0YW5nbGUgewogICAgIAogICAgIC8vIEFuaW1hdGlvbiBm
b3Igc21vb3RoIHNob3cvaGlkZQogICAgIEJlaGF2aW9yIG9uIG9wYWNpdHkgewotICAgICAgICBO
dW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjogMjAwIH0KKyAgICAgICAgTnVtYmVyQW5pbWF0aW9u
IHsgZHVyYXRpb246IFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQgPyAyMDAgOiAwIH0KICAgICB9CiAg
ICAgCiAgICAgLy8gSGFuZGxlIGtleWJvYXJkIGlucHV0IGZvciBuYXZpZ2F0aW9uCkBAIC0xMzks
NyArMTQzLDcgQEAgUmVjdGFuZ2xlIHsKICAgICAgICAgICAgICAgICAvLyBTaGVldC1yb3cgcmVj
aXBlIOKAlCBmb2N1c2VkRmlsbCBzdXJmYWNlICsgYWNjZW50IGJvcmRlciB3aGVuCiAgICAgICAg
ICAgICAgICAgLy8gY3VycmVudCAoZmxhdCB2YXJpYW50OiB0aGUgb3V0ZXIgZ2xvdyB3b3VsZCBj
bGlwIGluc2lkZSB0aGlzIHNjcm9sbGluZwogICAgICAgICAgICAgICAgIC8vIGNsaXBwZWQgbGlz
dCwgc28gdGhlIHJpbmcgaXMgYm9yZGVyLW9ubHkgaGVyZSkuCi0gICAgICAgICAgICAgICAgYmFj
a2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgICAgICBiYWNrZ3JvdW5kOiBDcmltc29u
R2xhc3NQYW5lbCB7CiAgICAgICAgICAgICAgICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVz
Q29udHJvbAogICAgICAgICAgICAgICAgICAgICBjb2xvcjogbWVudVJvdy5kb3duID8gUXQuZGFy
a2VyKFZiVG9rZW5zLmludGVyYWN0aXZlRm9jdXMsIDEuMTUpCiAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgOiAobWVudVJvdy5hY3RpdmUgPyBWYlRva2Vucy5pbnRlcmFj
dGl2ZUZvY3VzIDogInRyYW5zcGFyZW50IikKQEAgLTIyOSw3ICsyMzMsNyBAQCBSZWN0YW5nbGUg
ewogICAgICAgICAgICAgICAgIGxlZnRQYWRkaW5nOiAxMgogICAgICAgICAgICAgICAgIHJpZ2h0
UGFkZGluZzogMTIKICAgICAgICAgICAgICAgICAvLyBUb2tlbiBmaWVsZCDigJQgd2luZG93LWRh
cmsgd2VsbCArIGFjY2VudCBmb2N1cyBib3JkZXIuCi0gICAgICAgICAgICAgICAgYmFja2dyb3Vu
ZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgICAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQ
YW5lbCB7CiAgICAgICAgICAgICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy5zdXJmYWNlQmFzZQog
ICAgICAgICAgICAgICAgICAgICBib3JkZXIuY29sb3I6IHNlbmRUZXh0RmllbGQuYWN0aXZlRm9j
dXMgPyBWYlRva2Vucy5hY2NlbnQgOiBWYlRva2Vucy5kaXZpZGVyCiAgICAgICAgICAgICAgICAg
ICAgIGJvcmRlci53aWR0aDogVmJUb2tlbnMuZm9jdXNCb3JkZXIKQEAgLTM3Miw3ICszNzYsNyBA
QCBSZWN0YW5nbGUgewogICAgICAgICBvcGFjaXR5OiBzaG93VG9hc3QgPyAxLjAgOiAwLjAKIAog
ICAgICAgICBCZWhhdmlvciBvbiBvcGFjaXR5IHsKLSAgICAgICAgICAgIE51bWJlckFuaW1hdGlv
biB7IGR1cmF0aW9uOiAyMDAgfQorICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRp
b246IFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQgPyAyMDAgOiAwIH0KICAgICAgICAgfQogCiAgICAg
ICAgIFRleHQgewpAQCAtNDQ5LDcgKzQ1Myw3IEBAIFJlY3RhbmdsZSB7CiAgICAgICAgICAgICB0
ZXh0OiBxc1RyKCJRdWl0IGdhbWUiKQogICAgICAgICAgICAgaWNvbjogInBvd2VyIgogICAgICAg
ICAgICAgYWN0aW9uOiAicXVpdCIKLSAgICAgICAgICAgIGRlc2NyaXB0aW9uOiBxc1RyKCJRdWl0
IHRoZSBnYW1lIG9uIHRoZSBob3N0IGFuZCByZXR1cm4gdG8gVmliZW1pcyIpCisgICAgICAgICAg
ICBkZXNjcmlwdGlvbjogcXNUcigiUXVpdCB0aGUgZ2FtZSBvbiB0aGUgaG9zdCBhbmQgcmV0dXJu
IHRvIEVjbGlwc2UiKQogICAgICAgICB9CiAgICAgICAgIExpc3RFbGVtZW50IHsKICAgICAgICAg
ICAgIHRleHQ6IHFzVHIoIlNlcnZlciBjb21tYW5kcyIpCkBAIC03MTQsNCArNzE4LDMgQEAgUmVj
dGFuZ2xlIHsKICAgICAgICAgfQogICAgIH0KIH0KLQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9TZXJ2
ZXJDb21tYW5kcy5xbWwgYi9hcHAvZ3VpL1NlcnZlckNvbW1hbmRzLnFtbAppbmRleCBhMGJhNDdl
Li45Y2U4M2QwIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1NlcnZlckNvbW1hbmRzLnFtbAorKysgYi9h
cHAvZ3VpL1NlcnZlckNvbW1hbmRzLnFtbApAQCAtMTU1LDcgKzE1NSw3IEBAIEdyb3VwQm94IHsK
ICAgICB9CiAKICAgICAvLyBDb25maXJtYXRpb24gZGlhbG9nCi0gICAgRGlhbG9nIHsKKyAgICBO
YXZpZ2FibGVEaWFsb2cgewogICAgICAgICBpZDogY29uZmlybURpYWxvZwogICAgICAgICBhbmNo
b3JzLmNlbnRlckluOiBwYXJlbnQKICAgICAgICAgd2lkdGg6IE1hdGgubWluKDQwMCwgcGFyZW50
LndpZHRoICogMC45KQpAQCAtMTY4LDcgKzE2OCw3IEBAIEdyb3VwQm94IHsKICAgICAgICAgdGl0
bGU6IHFzVHIoIkNvbmZpcm0gQ29tbWFuZCIpCiAgICAgICAgIG1vZGFsOiB0cnVlCiAKLSAgICAg
ICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgYmFja2dyb3VuZDogQ3JpbXNvbkds
YXNzUGFuZWwgewogICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLnN1cmZhY2VSYWlzZWQKICAg
ICAgICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVzRGlhbG9nCiAgICAgICAgICAgICBib3Jk
ZXIud2lkdGg6IDEKQEAgLTIxNiw3ICsyMTYsNyBAQCBHcm91cEJveCB7CiAgICAgfQogCiAgICAg
Ly8gQ3VzdG9tIGNvbW1hbmQgZGlhbG9nCi0gICAgRGlhbG9nIHsKKyAgICBOYXZpZ2FibGVEaWFs
b2cgewogICAgICAgICBpZDogY3VzdG9tQ29tbWFuZERpYWxvZwogICAgICAgICBhbmNob3JzLmNl
bnRlckluOiBwYXJlbnQKICAgICAgICAgd2lkdGg6IE1hdGgubWluKDQwMCwgcGFyZW50LndpZHRo
ICogMC45KQpAQCAtMjI1LDcgKzIyNSw3IEBAIEdyb3VwQm94IHsKICAgICAgICAgdGl0bGU6IHFz
VHIoIkN1c3RvbSBDb21tYW5kIikKICAgICAgICAgbW9kYWw6IHRydWUKIAotICAgICAgICBiYWNr
Z3JvdW5kOiBSZWN0YW5nbGUgeworICAgICAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5l
bCB7CiAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuc3VyZmFjZVJhaXNlZAogICAgICAgICAg
ICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNEaWFsb2cKICAgICAgICAgICAgIGJvcmRlci53aWR0
aDogMQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sIGIvYXBwL2d1aS9TZXR0
aW5nc1ZpZXcucW1sCmluZGV4IDQ5NGUzNWIuLmU5ODkxNmIgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkv
U2V0dGluZ3NWaWV3LnFtbAorKysgYi9hcHAvZ3VpL1NldHRpbmdzVmlldy5xbWwKQEAgLTEzLDkg
KzEzLDExIEBAIGltcG9ydCBBdXRvVXBkYXRlQ2hlY2tlciAxLjAKIGltcG9ydCBVaVNvdW5kTWFu
YWdlciAxLjAKIAogaW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgRWNsaXBzZVBy
b2ZpbGVzIDEuMAogCiBJdGVtIHsKICAgICBpZDogc2V0dGluZ3NQYWdlCisgICAgQ3JpbXNvbkJh
Y2tncm91bmRQaWNrZXIgeyBpZDpiYWNrZ3JvdW5kUGlja2VyIH0KICAgICBvYmplY3ROYW1lOiBx
c1RyKCJTZXR0aW5ncyIpCiAKICAgICAvLyBMQi9SQiBjYXRlZ29yeSBmbGlwcyBjaGFuZ2UgYGNh
dGVnb3J5YCB3aXRob3V0IG1vdmluZyBpdGVtIGZvY3VzLApAQCAtNjgsNyArNzAsNyBAQCBJdGVt
IHsKICAgICBjb21wb25lbnQgVmJTZXR0aW5nc0NhcmQ6IEdyb3VwQm94IHsKICAgICAgICAgcGFk
ZGluZzogVmJUb2tlbnMuc3BhY2U1CiAgICAgICAgIGxhYmVsOiBJdGVtIHt9Ci0gICAgICAgIGJh
Y2tncm91bmQ6IFJlY3RhbmdsZSB7CisgICAgICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1Bh
bmVsIHsKICAgICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy5iZ0VsZXYKICAgICAgICAgICAgIHJh
ZGl1czogVmJUb2tlbnMucmFkaXVzQ2FyZAogICAgICAgICAgICAgYm9yZGVyLndpZHRoOiAxCkBA
IC0xNjIsMTQgKzE2NCwxNCBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgYW5jaG9ycy52
ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVyCiAgICAgICAgICAgICAgICAgICAg
IHg6IHRvZ2dsZVJvb3QuY2hlY2tlZCA/IHBhcmVudC53aWR0aCAtIHdpZHRoIC0gNCA6IDQKICAg
ICAgICAgICAgICAgICAgICAgY29sb3I6IHRvZ2dsZVJvb3QuY2hlY2tlZCA/IFZiVG9rZW5zLnRl
eHRPbkFjY2VudCA6IFZiVG9rZW5zLnRleHREaW0KLSAgICAgICAgICAgICAgICAgICAgQmVoYXZp
b3Igb24geCB7IE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiAxMjAgfSB9CisgICAgICAgICAg
ICAgICAgICAgIEJlaGF2aW9yIG9uIHggeyBOdW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjogVmJU
b2tlbnMubW90aW9uRW5hYmxlZCA/IDEyMCA6IDAgfSB9CiAgICAgICAgICAgICAgICAgfQogICAg
ICAgICAgICAgfQogICAgICAgICB9CiAgICAgfQogCiAgICAgLy8gRnVsbC1ibGVlZCB3aW5kb3cg
YmFja2dyb3VuZC4KLSAgICBSZWN0YW5nbGUgeyBhbmNob3JzLmZpbGw6IHBhcmVudDsgY29sb3I6
IFZiVG9rZW5zLmJnV2luZG93IH0KKyAgICBDcmltc29uR2xhc3NCYWNrZHJvcCB7IGFuY2hvcnMu
ZmlsbDogcGFyZW50IH0KIAogICAgIC8vIFN0YWNrVmlldyBhdHRhY2hlZCBoYW5kbGVycyBtdXN0
IHN0YXkgb24gdGhlIHB1c2hlZCBwYWdlICh0aGUgSXRlbSByb290KS4KICAgICBTdGFja1ZpZXcu
b25BY3RpdmF0ZWQ6IHsKQEAgLTM0NiwxMiArMzQ4LDEzIEBAIEl0ZW0gewogICAgICAgICAgICAg
ICAgICAgICB7IGljb246ICJnYW1lcGFkIiwgICBsYWJlbDogcXNUcigiSW5wdXQgJiBnYW1lcGFk
IikgfSwKICAgICAgICAgICAgICAgICAgICAgeyBpY29uOiAic3RyZWFtaW5nIiwgbGFiZWw6IHFz
VHIoIlN0cmVhbWluZyIpIH0sCiAgICAgICAgICAgICAgICAgICAgIHsgaWNvbjogImFwcHMiLCAg
ICAgIGxhYmVsOiBxc1RyKCJBcHAgJiBVSSIpIH0sCi0gICAgICAgICAgICAgICAgICAgIHsgaWNv
bjogImFkdmFuY2VkIiwgIGxhYmVsOiBxc1RyKCJBZHZhbmNlZCIpIH0KKyAgICAgICAgICAgICAg
ICAgICAgeyBpY29uOiAiYWR2YW5jZWQiLCAgbGFiZWw6IHFzVHIoIkFkdmFuY2VkIikgfSwKKyAg
ICAgICAgICAgICAgICAgICAgeyBpY29uOiAiYWR2YW5jZWQiLCBsYWJlbDogcXNUcigiU3lzdGVt
IENvbnRyb2xzIikgfQogICAgICAgICAgICAgICAgIF0KICAgICAgICAgICAgICAgICBkZWxlZ2F0
ZTogQnV0dG9uIHsKICAgICAgICAgICAgICAgICAgICAgaWQ6IGNhdEJ1dHRvbgogICAgICAgICAg
ICAgICAgICAgICB3aWR0aDogc2lkZWJhckNvbHVtbi53aWR0aAotICAgICAgICAgICAgICAgICAg
ICBoZWlnaHQ6IDU4CisgICAgICAgICAgICAgICAgICAgIGhlaWdodDogTWF0aC5taW4oNTgsTWF0
aC5tYXgoNDQsKHNpZGViYXIuaGVpZ2h0LTY0LShzaWRlYmFyUmVwZWF0ZXIuY291bnQtMSkqVmJU
b2tlbnMuc3BhY2UyKS9zaWRlYmFyUmVwZWF0ZXIuY291bnQpKQogICAgICAgICAgICAgICAgICAg
ICBwYWRkaW5nOiAwCiAgICAgICAgICAgICAgICAgICAgIGxlZnRQYWRkaW5nOiBWYlRva2Vucy5z
cGFjZTQKICAgICAgICAgICAgICAgICAgICAgcmlnaHRQYWRkaW5nOiBWYlRva2Vucy5zcGFjZTQK
QEAgLTM3OSw3ICszODIsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBi
b3JkZXIud2lkdGg6IChjYXRCdXR0b24uc2VsZWN0ZWQgfHwgY2F0QnV0dG9uLmFjdGl2ZUZvY3Vz
KSA/IFZiVG9rZW5zLmZvY3VzQm9yZGVyIDogMQogICAgICAgICAgICAgICAgICAgICAgICAgICAg
IGJvcmRlci5jb2xvcjogKGNhdEJ1dHRvbi5zZWxlY3RlZCB8fCBjYXRCdXR0b24uYWN0aXZlRm9j
dXMpID8gVmJUb2tlbnMuYWNjZW50IDogVmJUb2tlbnMuc3Ryb2tlCiAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgYW50aWFsaWFzaW5nOiB0cnVlCi0gICAgICAgICAgICAgICAgICAgICAgICAg
ICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xvckFuaW1hdGlvbiB7IGR1cmF0aW9uOiAxMjAgfSB9
CisgICAgICAgICAgICAgICAgICAgICAgICAgICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xvckFu
aW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8gMTIwIDogMCB9IH0K
ICAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgfQogCkBAIC01
MjQsNyArNTI3LDcgQEAgSXRlbSB7CiAKICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIG9uIGNvbnRl
bnRZIHsKICAgICAgICAgICAgIGlkOiBhdXRvU2Nyb2xsQW5pbWF0aW9uCi0gICAgICAgICAgICBk
dXJhdGlvbjogMTAwCisgICAgICAgICAgICBkdXJhdGlvbjogVmJUb2tlbnMubW90aW9uRW5hYmxl
ZCA/IDEwMCA6IDAKICAgICAgICAgfQogCiAgICAgICAgIFdpbmRvdy5vbkFjdGl2ZUZvY3VzSXRl
bUNoYW5nZWQ6IHsKQEAgLTU3MSw2ICs1NzQsMTIgQEAgSXRlbSB7CiAgICAgICAgICAgICBjb2xv
cjogVmJUb2tlbnMudGV4dAogICAgICAgICB9CiAKKyAgICAgICAgRWNsaXBzZVN5c3RlbVNldHRp
bmdzIHsKKyAgICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lkdGggLSAocGFyZW50LmxlZnRQYWRk
aW5nICsgcGFyZW50LnJpZ2h0UGFkZGluZykKKyAgICAgICAgICAgIHZpc2libGU6IHNldHRpbmdz
UGFnZS5jYXRlZ29yeSA9PT0gNgorICAgICAgICAgICAgYWN0aXZlOiBzZXR0aW5nc1BhZ2Uudmlz
aWJsZSAmJiB2aXNpYmxlCisgICAgICAgIH0KKwogICAgICAgICAvLyAtLS0tIExpdmUgc3RyZWFt
IHN1bW1hcnkgbGluZSAocmVkZXNpZ24pLCByZWxvY2F0ZWQgaGVyZSAod2FzIGluc2lkZSBCYXNp
YwogICAgICAgICAvLyBTZXR0aW5ncykgc28gaXQgc2l0cyBkaXJlY3RseSB1bmRlciB0aGUgIlZp
ZGVvIiB0aXRsZSBsaWtlIHRoZSBkZXNpZ24uCiAgICAgICAgIC8vIE51bWJlcnMgcmVuZGVyIGlu
IGFjY2VudDsgdGhlIHJlc3Qgc3RheXMgZGltLiBDb250ZW50L2JpbmRpbmdzIHVuY2hhbmdlZC4K
QEAgLTYwMiw3ICs2MTEsNyBAQCBJdGVtIHsKICAgICAgICAgICAgIHdpZHRoOiAocGFyZW50Lndp
ZHRoIC0gKHBhcmVudC5sZWZ0UGFkZGluZyArIHBhcmVudC5yaWdodFBhZGRpbmcpKQogICAgICAg
ICAgICAgcGFkZGluZzogVmJUb2tlbnMuc3BhY2U1CiAgICAgICAgICAgICBsYWJlbDogSXRlbSB7
fQotICAgICAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgIGJhY2tn
cm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsKICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tl
bnMuYmdFbGV2CiAgICAgICAgICAgICAgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDYXJkCiAg
ICAgICAgICAgICAgICAgYm9yZGVyLndpZHRoOiAxCkBAIC03NTYsNyArNzY1LDcgQEAgSXRlbSB7
CiAgICAgICAgICAgICAgICAgICAgICAgICAvLyB0b3dhcmQgdGhlIGNvbnRyb2wncyBpbXBsaWNp
dCBoZWlnaHQsIHNvIHRoZSB2YWx1ZSB0ZXh0IHVzZWQgdG8gcmVuZGVyCiAgICAgICAgICAgICAg
ICAgICAgICAgICAvLyBwYXN0IHRoZSBjYXJkJ3MgYm90dG9tIGVkZ2UuIFNpemUgdGhlIGNhcmQg
dG8gY29udGVudCArIGJvdGggbWFyZ2lucy4KICAgICAgICAgICAgICAgICAgICAgICAgIGltcGxp
Y2l0SGVpZ2h0OiByZXNvbHV0aW9uQ2FyZENvbnRlbnQuaW1wbGljaXRIZWlnaHQgKyA0OAotICAg
ICAgICAgICAgICAgICAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgICAg
ICAgICAgICAgICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsKICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYmdFbGV2CiAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDYXJkCiAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgYm9yZGVyLndpZHRoOiByZXNvbHV0aW9uQ29tYm9Cb3guYWN0aXZlRm9jdXMg
PyBWYlRva2Vucy5mb2N1c0JvcmRlciA6IDEKQEAgLTExMjUsNyArMTEzNCw3IEBAIEl0ZW0gewog
ICAgICAgICAgICAgICAgICAgICAgICAgLy8gU2FtZSBjb250ZW50LW1hcmdpbiBzaXppbmcgZml4
IGFzIHRoZSBSZXNvbHV0aW9uIGNhcmQg4oCUIGtlZXBzCiAgICAgICAgICAgICAgICAgICAgICAg
ICAvLyB0aGUgZnJhbWUtcmF0ZSB2YWx1ZSB0ZXh0IGluc2lkZSB0aGUgY2FyZCBib3VuZHMuCiAg
ICAgICAgICAgICAgICAgICAgICAgICBpbXBsaWNpdEhlaWdodDogZnBzQ2FyZENvbnRlbnQuaW1w
bGljaXRIZWlnaHQgKyA0OAotICAgICAgICAgICAgICAgICAgICAgICAgYmFja2dyb3VuZDogUmVj
dGFuZ2xlIHsKKyAgICAgICAgICAgICAgICAgICAgICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFz
c1BhbmVsIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYmdF
bGV2CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXND
YXJkCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYm9yZGVyLndpZHRoOiBmcHNDb21ib0Jv
eC5hY3RpdmVGb2N1cyA/IFZiVG9rZW5zLmZvY3VzQm9yZGVyIDogMQpAQCAtMTUxMyw3ICsxNTIy
LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgLy8gLS0t
LSBWaWRlbyBiaXRyYXRlIGNhcmQgKHJlZGVzaWduKSAtLS0tCi0gICAgICAgICAgICAgICAgUmVj
dGFuZ2xlIHsKKyAgICAgICAgICAgICAgICBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgICAg
ICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lkdGgKICAgICAgICAgICAgICAgICAgICAgaGVpZ2h0
OiBiaXRyYXRlQ2FyZENvbHVtbi5pbXBsaWNpdEhlaWdodCArIDUyCiAgICAgICAgICAgICAgICAg
ICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ2FyZApAQCAtMTY3Myw3ICsxNjgyLDcgQEAgSXRl
bSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGFuY2hvcnMudmVydGljYWxDZW50
ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlcgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICB4OiBhZGFwdGl2ZUJpdHJhdGVDaGVjay5jaGVja2VkID8gcGFyZW50LndpZHRoIC0gd2lkdGgg
LSA0IDogNAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb2xvcjogYWRhcHRpdmVC
aXRyYXRlQ2hlY2suY2hlY2tlZCA/IFZiVG9rZW5zLnRleHRPbkFjY2VudCA6IFZiVG9rZW5zLnRl
eHREaW0KLSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQmVoYXZpb3Igb24geCB7IE51
bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiAxMjAgfSB9CisgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgIEJlaGF2aW9yIG9uIHggeyBOdW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjogVmJU
b2tlbnMubW90aW9uRW5hYmxlZCA/IDEyMCA6IDAgfSB9CiAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgfQogICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICB9
CkBAIC0xNjgxLDcgKzE2OTAsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRp
cC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAK
ICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAg
ICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiV2hlbiB0aGUgbmV0d29yayBjYW4ndCBzdXN0
YWluIHRoZSBjb25maWd1cmVkIGJpdHJhdGUgYW5kIHRoZSBzdHJlYW0gY29sbGFwc2VzLCBWaWJl
bWlzIGF1dG9tYXRpY2FsbHkgcmVjb25uZWN0cyBhdCBhIGxvd2VyIGJpdHJhdGUgdW50aWwgdGhl
IHN0cmVhbSBpcyB1c2FibGUuIFlvdXIgc2F2ZWQgYml0cmF0ZSBzZXR0aW5nIGlzIG5ldmVyIGNo
YW5nZWQuIikKKyAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJXaGVuIHRo
ZSBuZXR3b3JrIGNhbid0IHN1c3RhaW4gdGhlIGNvbmZpZ3VyZWQgYml0cmF0ZSBhbmQgdGhlIHN0
cmVhbSBjb2xsYXBzZXMsIEVjbGlwc2UgYXV0b21hdGljYWxseSByZWNvbm5lY3RzIGF0IGEgbG93
ZXIgYml0cmF0ZSB1bnRpbCB0aGUgc3RyZWFtIGlzIHVzYWJsZS4gWW91ciBzYXZlZCBiaXRyYXRl
IHNldHRpbmcgaXMgbmV2ZXIgY2hhbmdlZC4iKQogICAgICAgICAgICAgICAgIH0KIAogICAgICAg
ICAgICAgICAgIC8vIFZpYmVtaXMgKHBlcmYgZ3VpZGFuY2UpOiBhZHZpc2Ugd2hlbiB0aGUgYml0
cmF0ZSBpcyBzZXQgd2VsbCBhYm92ZSB0aGUgcmVjb21tZW5kZWQKQEAgLTE5MjksNyArMTkzOCw3
IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRp
Y2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIKICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgeDogdnN5bmNDaGVjay5jaGVja2VkID8gcGFyZW50LndpZHRoIC0gd2lkdGggLSA0
IDogNAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb2xvcjogdnN5bmNDaGVjay5j
aGVja2VkID8gVmJUb2tlbnMudGV4dE9uQWNjZW50IDogVmJUb2tlbnMudGV4dERpbQotICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICBCZWhhdmlvciBvbiB4IHsgTnVtYmVyQW5pbWF0aW9u
IHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQmVo
YXZpb3Igb24geCB7IE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25F
bmFibGVkID8gMTIwIDogMCB9IH0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAg
ICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgIH0KQEAgLTIwMjQsNyAr
MjAzMyw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBhbmNob3Jz
LnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIKICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgeDogZnJhbWVQYWNpbmdDaGVjay5jaGVja2VkID8gcGFyZW50LndpZHRo
IC0gd2lkdGggLSA0IDogNAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb2xvcjog
ZnJhbWVQYWNpbmdDaGVjay5jaGVja2VkID8gVmJUb2tlbnMudGV4dE9uQWNjZW50IDogVmJUb2tl
bnMudGV4dERpbQotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBCZWhhdmlvciBvbiB4
IHsgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgQmVoYXZpb3Igb24geCB7IE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9u
OiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8gMTIwIDogMCB9IH0KICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAg
ICAgIH0KQEAgLTIwOTYsNyArMjEwNSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgeDogdnJyQ2hlY2suY2hlY2tlZCA/IHBh
cmVudC53aWR0aCAtIHdpZHRoIC0gNCA6IDQKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgY29sb3I6IHZyckNoZWNrLmNoZWNrZWQgPyBWYlRva2Vucy50ZXh0T25BY2NlbnQgOiBWYlRv
a2Vucy50ZXh0RGltCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJlaGF2aW9yIG9u
IHggeyBOdW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjogMTIwIH0gfQorICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICBCZWhhdmlvciBvbiB4IHsgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRp
b246IFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQgPyAxMjAgOiAwIH0gfQogICAgICAgICAgICAgICAg
ICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAg
ICAgICAgfQpAQCAtMjQ4Miw3ICsyNDkxLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAg
IFRvb2xUaXAuZGVsYXk6IDEwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50aW1lb3V0
OiA1MDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAotICAg
ICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIklmIGEgc3RyZWFtIGVuZHMgdW5l
eHBlY3RlZGx5IChhIG5ldHdvcmsgYmxpcCBvciB0aGUgaG9zdCB3YWtpbmcpLCBWaWJlbWlzIHdp
bGwgdHJ5IHRvIHJlY29ubmVjdCBhdXRvbWF0aWNhbGx5LiIpCisgICAgICAgICAgICAgICAgICAg
IFRvb2xUaXAudGV4dDogcXNUcigiSWYgYSBzdHJlYW0gZW5kcyB1bmV4cGVjdGVkbHkgKGEgbmV0
d29yayBibGlwIG9yIHRoZSBob3N0IHdha2luZyksIEVjbGlwc2Ugd2lsbCB0cnkgdG8gcmVjb25u
ZWN0IGF1dG9tYXRpY2FsbHkuIikKICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAg
ICAgICAgIH0KQEAgLTI1NDYsNyArMjU1NSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgIHNw
YWNpbmc6IFZiVG9rZW5zLnNwYWNlMwogCiAgICAgICAgICAgICAgICAgVmJTZWN0aW9uSGVhZGVy
IHsKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBTdHJlYW1pbmcgRW5o
YW5jZW1lbnRzIikKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBTdHJl
YW1pbmcgRW5oYW5jZW1lbnRzIikKICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAg
ICBMYWJlbCB7CkBAIC0yNzc2LDcgKzI3ODUsNyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAg
IFZiVG9nZ2xlUm93IHsKICAgICAgICAgICAgICAgICAgICAgaWQ6IG11dGVPbkZvY3VzTG9zc0No
ZWNrCi0gICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIk11dGUgYXVkaW8gc3RyZWFtIHdo
ZW4gVmliZW1pcyBpcyBub3QgdGhlIGFjdGl2ZSB3aW5kb3ciKQorICAgICAgICAgICAgICAgICAg
ICB0ZXh0OiBxc1RyKCJNdXRlIGF1ZGlvIHN0cmVhbSB3aGVuIEVjbGlwc2UgaXMgbm90IHRoZSBh
Y3RpdmUgd2luZG93IikKICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogU3lzdGVtUHJvcGVy
dGllcy5oYXNEZXNrdG9wRW52aXJvbm1lbnQKICAgICAgICAgICAgICAgICAgICAgY2hlY2tlZDog
U3RyZWFtaW5nUHJlZmVyZW5jZXMubXV0ZU9uRm9jdXNMb3NzCiAgICAgICAgICAgICAgICAgICAg
IG9uQ2hlY2tlZENoYW5nZWQ6IHsKQEAgLTI3ODYsNyArMjc5NSw3IEBAIEl0ZW0gewogICAgICAg
ICAgICAgICAgICAgICBUb29sVGlwLmRlbGF5OiAxMDAwCiAgICAgICAgICAgICAgICAgICAgIFRv
b2xUaXAudGltZW91dDogNTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6
IGhvdmVyZWQKLSAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJNdXRlcyBW
aWJlbWlzJ3MgYXVkaW8gd2hlbiB5b3UgQWx0K1RhYiBvdXQgb2YgdGhlIHN0cmVhbSBvciBjbGlj
ayBvbiBhIGRpZmZlcmVudCB3aW5kb3cuIikKKyAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50
ZXh0OiBxc1RyKCJNdXRlcyBFY2xpcHNlJ3MgYXVkaW8gd2hlbiB5b3UgQWx0K1RhYiBvdXQgb2Yg
dGhlIHN0cmVhbSBvciBjbGljayBvbiBhIGRpZmZlcmVudCB3aW5kb3cuIikKICAgICAgICAgICAg
ICAgICB9CiAgICAgICAgICAgICB9CiAgICAgICAgIH0KQEAgLTI5NzEsNyArMjk4MCw3IEBAIEl0
ZW0gewogICAgICAgICAgICAgICAgICAgICAgICAgaWYgKFN0cmVhbWluZ1ByZWZlcmVuY2VzLmxh
bmd1YWdlICE9PSBuZXdfbGFuZ3VhZ2UpIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBT
dHJlYW1pbmdQcmVmZXJlbmNlcy5sYW5ndWFnZSA9IGxhbmd1YWdlTGlzdE1vZGVsLmdldChjdXJy
ZW50SW5kZXgpLnZhbAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmICghU3RyZWFtaW5n
UHJlZmVyZW5jZXMucmV0cmFuc2xhdGUoKSkgewotICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICBUb29sVGlwLnNob3cocXNUcigiWW91IG11c3QgcmVzdGFydCBWaWJlbWlzIGZvciB0aGlz
IGNoYW5nZSB0byB0YWtlIGVmZmVjdCIpLCA1MDAwKQorICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICBUb29sVGlwLnNob3cocXNUcigiWW91IG11c3QgcmVzdGFydCBFY2xpcHNlIGZvciB0
aGlzIGNoYW5nZSB0byB0YWtlIGVmZmVjdCIpLCA1MDAwKQogICAgICAgICAgICAgICAgICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICBlbHNlIHsKICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgLy8gRm9yY2UgdGhlIGJhY2sgb3BlcmF0aW9uIHRvIHBvcCBh
bnkgQXBwVmlldyBwYWdlcyB0aGF0IGV4aXN0LgpAQCAtMzA0MCw2ICszMDQ5LDEzIEBAIEl0ZW0g
ewogICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgfQogCisgICAgICAgICAg
ICAgICAgTGFiZWwgeyB0ZXh0OnFzVHIoIkNyaW1zb24gR2xhc3Mg4oCiIEJhY2tncm91bmQiKTtm
b250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTtjb2xvcjpWYlRva2Vucy50ZXh0O2ZvbnQu
Ym9sZDp0cnVlIH0KKyAgICAgICAgICAgICAgICBGbG93IHsgd2lkdGg6cGFyZW50LndpZHRoO3Nw
YWNpbmc6MTIKKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6
cXNUcigiQ2hvb3NlIGJhY2tncm91bmQiKTtvbkNsaWNrZWQ6YmFja2dyb3VuZFBpY2tlci5vcGVu
KCkgfQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpxc1Ry
KCJSZXNldCBiYWNrZ3JvdW5kIik7b25DbGlja2VkOkVjbGlwc2VQcm9maWxlcy5yZXNldEJhY2tn
cm91bmQoKSB9CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4
dDpxc1RyKCJCYWNrZ3JvdW5kIGRpbW1pbmc6ICUxJSIpLmFyZyhFY2xpcHNlUHJvZmlsZXMuYmFj
a2dyb3VuZERpbSk7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUxhYmVsO2NvbG9yOlZiVG9r
ZW5zLnRleHQgfQorICAgICAgICAgICAgICAgIFNsaWRlciB7IHdpZHRoOnBhcmVudC53aWR0aDtm
cm9tOjMwO3RvOjkwO3N0ZXBTaXplOjU7dmFsdWU6RWNsaXBzZVByb2ZpbGVzLmJhY2tncm91bmRE
aW07QWNjZXNzaWJsZS5uYW1lOnFzVHIoIkJhY2tncm91bmQgZGltbWluZyIpO29uTW92ZWQ6RWNs
aXBzZVByb2ZpbGVzLmJhY2tncm91bmREaW09TWF0aC5yb3VuZCh2YWx1ZSkgfQogICAgICAgICAg
ICAgICAgIC8vIEJMLTIyNjMgKFNldHRpbmdzIElBKTogcmVsb2NhdGVkIGZyb20gdGhlIEdhbWVw
YWQgY2FyZCAtCiAgICAgICAgICAgICAgICAgLy8gYXBwLXdpZGUgYXBwZWFyYW5jZSwgbm90aGlu
ZyBnYW1lcGFkLXNwZWNpZmljLgogICAgICAgICAgICAgICAgIExhYmVsIHsKQEAgLTMwNTUsMTQg
KzMwNzEsMjYgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgIHRleHRSb2xlOiAidGV4dCIK
ICAgICAgICAgICAgICAgICAgICAgaG92ZXJFbmFibGVkOiB0cnVlCiAgICAgICAgICAgICAgICAg
ICAgIG1vZGVsOiBMaXN0TW9kZWwgewotICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1l
bnQgeyB0ZXh0OiBxc1RyKCJUZWFsIChkZWZhdWx0KSIpIH0KKyAgICAgICAgICAgICAgICAgICAg
ICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiVGVhbCIpIH0KICAgICAgICAgICAgICAgICAg
ICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiSW5kaWdvIikgfQogICAgICAgICAgICAg
ICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJHcmVlbiIpIH0KICAgICAgICAg
ICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiQW1iZXIiKSB9CisgICAg
ICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIkNyaW1zb24gKGRl
ZmF1bHQpIikgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBx
c1RyKCJSZWQiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6
IHFzVHIoIk9yYW5nZSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsg
dGV4dDogcXNUcigiR29sZCIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50
IHsgdGV4dDogcXNUcigiTGltZSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVt
ZW50IHsgdGV4dDogcXNUcigiTWludCIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RF
bGVtZW50IHsgdGV4dDogcXNUcigiQ3lhbiIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExp
c3RFbGVtZW50IHsgdGV4dDogcXNUcigiQmx1ZSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAg
IExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiVmlvbGV0IikgfQorICAgICAgICAgICAgICAgICAg
ICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJQaW5rIikgfQorICAgICAgICAgICAgICAg
ICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJTaWx2ZXIiKSB9CisgICAgICAgICAg
ICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIlJvc2UiKSB9CiAgICAgICAg
ICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgQ29tcG9uZW50Lm9uQ29tcGxldGVk
OiBjdXJyZW50SW5kZXggPSBTdHJlYW1pbmdQcmVmZXJlbmNlcy51aUFjY2VudEluZGV4CiAgICAg
ICAgICAgICAgICAgICAgIG9uQWN0aXZhdGVkOiBTdHJlYW1pbmdQcmVmZXJlbmNlcy51aUFjY2Vu
dEluZGV4ID0gY3VycmVudEluZGV4Ci0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDog
cXNUcigiVGhlIGFjY2VudCBjb2xvciB1c2VkIGFjcm9zcyB0aGUgcmVkZXNpZ25lZCBVSS4iKQor
ICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlRoZSBhY2NlbnQgY29sb3Ig
dXNlZCB0aHJvdWdob3V0IEVjbGlwc2UuIikKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5k
ZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQK
ICAgICAgICAgICAgICAgICB9CkBAIC0zMTQ3LDcgKzMxNzUsNyBAQCBJdGVtIHsKICAgICAgICAg
ICAgICAgICAgICAgICAgIFRvb2xUaXAuZGVsYXk6IDEwMDAKICAgICAgICAgICAgICAgICAgICAg
ICAgIFRvb2xUaXAudGltZW91dDogNTAwMAogICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRp
cC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6
IHFzVHIoIlNhdmUgYWxsIFZpYmVtaXMgc2V0dGluZ3MgdG8gfi92aWJlbWlzLXNldHRpbmdzLmlu
aSBmb3IgYmFja3VwIG9yIHRvIGNvcHkgdG8gYW5vdGhlciBkZXZpY2UuIikKKyAgICAgICAgICAg
ICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiU2F2ZSBhbGwgRWNsaXBzZSBzZXR0aW5n
cyB0byB+L3ZpYmVtaXMtc2V0dGluZ3MuaW5pIGZvciBiYWNrdXAgb3IgdG8gY29weSB0byBhbm90
aGVyIGRldmljZS4iKQogICAgICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICAg
ICAgQnV0dG9uIHsKQEAgLTM0MDIsNyArMzQzMCw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAg
ICAgICBUb29sVGlwLnRpbWVvdXQ6IDEwMDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAu
dmlzaWJsZTogaG92ZXJlZAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIo
IlRoaXMgZW5hYmxlcyB0aGUgY2FwdHVyZSBvZiBzeXN0ZW0td2lkZSBrZXlib2FyZCBzaG9ydGN1
dHMgbGlrZSBBbHQrVGFiIHRoYXQgd291bGQgbm9ybWFsbHkgYmUgaGFuZGxlZCBieSB0aGUgY2xp
ZW50IE9TIHdoaWxlIHN0cmVhbWluZy4iKSArICJcblxuIiArCi0gICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgcXNUcigiTk9URTogQ2VydGFpbiBrZXlib2FyZCBzaG9ydGN1dHMgbGlr
ZSBDdHJsK0FsdCtEZWwgb24gV2luZG93cyBjYW5ub3QgYmUgaW50ZXJjZXB0ZWQgYnkgYW55IGFw
cGxpY2F0aW9uLCBpbmNsdWRpbmcgVmliZW1pcy4iKQorICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgIHFzVHIoIk5PVEU6IENlcnRhaW4ga2V5Ym9hcmQgc2hvcnRjdXRzIGxpa2UgQ3Ry
bCtBbHQrRGVsIG9uIFdpbmRvd3MgY2Fubm90IGJlIGludGVyY2VwdGVkIGJ5IGFueSBhcHBsaWNh
dGlvbiwgaW5jbHVkaW5nIEVjbGlwc2UuIikKICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAg
ICAgICAgICBBdXRvUmVzaXppbmdDb21ib0JveCB7CkBAIC0zNjQzLDcgKzM2NzEsNyBAQCBJdGVt
IHsKIAogICAgICAgICAgICAgICAgIFZiVG9nZ2xlUm93IHsKICAgICAgICAgICAgICAgICAgICAg
aWQ6IGJhY2tncm91bmRHYW1lcGFkQ2hlY2sKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiUHJvY2VzcyBnYW1lcGFkIGlucHV0IHdoZW4gVmliZW1pcyBpcyBpbiB0aGUgYmFja2dyb3Vu
ZCIpCisgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlByb2Nlc3MgZ2FtZXBhZCBpbnB1
dCB3aGVuIEVjbGlwc2UgaXMgaW4gdGhlIGJhY2tncm91bmQiKQogICAgICAgICAgICAgICAgICAg
ICB2aXNpYmxlOiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Rlc2t0b3BFbnZpcm9ubWVudAogICAgICAg
ICAgICAgICAgICAgICBjaGVja2VkOiBTdHJlYW1pbmdQcmVmZXJlbmNlcy5iYWNrZ3JvdW5kR2Ft
ZXBhZAogICAgICAgICAgICAgICAgICAgICBvbkNoZWNrZWRDaGFuZ2VkOiB7CkBAIC0zNjUzLDcg
KzM2ODEsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAw
MAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAg
ICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRv
b2xUaXAudGV4dDogcXNUcigiQWxsb3dzIFZpYmVtaXMgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0
cyBldmVuIGlmIGl0J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBmb2N1cyIpCisgICAgICAg
ICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiQWxsb3dzIEVjbGlwc2UgdG8gY2FwdHVy
ZSBnYW1lcGFkIGlucHV0cyBldmVuIGlmIGl0J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBm
b2N1cyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgVmJUb2dnbGVSb3cg
ewpAQCAtMzcyNCw3ICszNzUyLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgTGFiZWwgewog
ICAgICAgICAgICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAg
ICAgIGlkOiB1cGRhdGVDaGFubmVsVGl0bGUKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiU29mdHdhcmUgdXBkYXRlcyIpCisgICAgICAgICAgICAgICAgICAgIHRleHQ6IEF1dG9VcGRh
dGVDaGVja2VyLm9zTWFuYWdlZCA/IHFzVHIoIkVjbGlwc2VPUyB1cGRhdGVzIikgOiBxc1RyKCJT
b2Z0d2FyZSB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZi
VG9rZW5zLnR5cGVMYWJlbAogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tl
bnMuZm9udEJvZHkKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAt
MzczMyw2ICszNzYxLDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBBdXRvUmVzaXppbmdD
b21ib0JveCB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsQ29tYm9Cb3gK
KyAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogIUF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdl
ZAogICAgICAgICAgICAgICAgICAgICB0ZXh0Um9sZTogInRleHQiCiAgICAgICAgICAgICAgICAg
ICAgIG1vZGVsOiBMaXN0TW9kZWwgewogICAgICAgICAgICAgICAgICAgICAgICAgaWQ6IHVwZGF0
ZUNoYW5uZWxMaXN0TW9kZWwKQEAgLTM3ODcsNiArMzgxNiw3IEBAIEl0ZW0gewogICAgICAgICAg
ICAgICAgICAgICAvLyBpbnN0YWxsIGluIGZsaWdodCBhdCBhIHRpbWUpLCBzbyBidXR0b25zIHN0
YXkgZW5hYmxlZC4KICAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsKICAgICAgICAgICAgICAg
ICAgICAgICAgIGlkOiBjaGVja1VwZGF0ZXNCdXR0b24KKyAgICAgICAgICAgICAgICAgICAgICAg
IHZpc2libGU6ICFBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFnZWQKICAgICAgICAgICAgICAgICAg
ICAgICAgIHRleHQ6IHFzVHIoIkNoZWNrIGZvciB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAg
ICAgICAgIG9uQ2xpY2tlZDogewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIEF1dG9VcGRh
dGVDaGVja2VyLmNoZWNrTm93KCkKQEAgLTM4MDQsOCArMzgzNCw4IEBAIEl0ZW0gewogCiAgICAg
ICAgICAgICAgICAgICAgIEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAgICAgICAgICBpZDogdmll
d1JlbGVhc2VCdXR0b24KLSAgICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpZXcg
cmVsZWFzZSIpCi0gICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBBdXRvVXBkYXRlQ2hl
Y2tlci5vZmZlckF2YWlsYWJsZQorICAgICAgICAgICAgICAgICAgICAgICAgdGV4dDogQXV0b1Vw
ZGF0ZUNoZWNrZXIub3NNYW5hZ2VkID8gcXNUcigiRWNsaXBzZU9TIHJlbGVhc2VzIikgOiBxc1Ry
KCJWaWV3IHJlbGVhc2UiKQorICAgICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogKEF1dG9V
cGRhdGVDaGVja2VyLm9zTWFuYWdlZCB8fCBBdXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2YWlsYWJs
ZSkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICYmIEF1dG9VcGRhdGVDaGVja2Vy
LnJlbGVhc2VVcmwgIT09ICIiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAmJiBT
eXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIKICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2xp
Y2tlZDogewpAQCAtMzg0Miw3ICszODcyLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgc3Bh
Y2luZzogVmJUb2tlbnMuc3BhY2UzCiAKICAgICAgICAgICAgICAgICBWYlNlY3Rpb25IZWFkZXIg
ewotICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWJlbWlzIEZlYXR1cmVzIikKKyAg
ICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBGZWF0dXJlcyIpCiAgICAgICAg
ICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgQ2xpcGJvYXJkU2V0dGluZ3MgewpAQCAtMzk0
Nyw3ICszOTc3LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgUmVwZWF0ZXIgewogICAgICAg
ICAgICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIG1v
ZGVsOiBbCi0gICAgICAgICAgICAgICAgICAgICAgICB7IGs6IHFzVHIoIlZpYmVtaXMgdmVyc2lv
biIpLCB2OiBTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcgfSwKKyAgICAgICAgICAgICAg
ICAgICAgICAgIHsgazogcXNUcigiRWNsaXBzZSB2ZXJzaW9uIiksIHY6IFN5c3RlbVByb3BlcnRp
ZXMudmVyc2lvblN0cmluZyB9LAogICAgICAgICAgICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJB
cmNoaXRlY3R1cmUiKSwgICAgdjogU3lzdGVtUHJvcGVydGllcy5mcmllbmRseU5hdGl2ZUFyY2hO
YW1lIH0sCiAgICAgICAgICAgICAgICAgICAgICAgICB7IGs6IHFzVHIoIlN0ZWFtT1MgLyBnYW1l
c2NvcGUiKSwgdjogU3lzdGVtUHJvcGVydGllcy5pc1N0ZWFtRGVjayA/IHFzVHIoIlllcyIpIDog
cXNUcigiTm8iKSB9LAogICAgICAgICAgICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJEaXNwbGF5
IHNlcnZlciIpLCAgdjogU3lzdGVtUHJvcGVydGllcy5pc1J1bm5pbmdXYXlsYW5kID8gKFN5c3Rl
bVByb3BlcnRpZXMuaXNSdW5uaW5nWFdheWxhbmQgPyAiWFdheWxhbmQiIDogIldheWxhbmQiKSA6
ICJYMTEiIH0sCkBAIC00MDEzLDcgKzQwNDMsNyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAg
IExhYmVsIHsKICAgICAgICAgICAgICAgICAgICAgd2lkdGg6IHBhcmVudC53aWR0aAotICAgICAg
ICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWJlbWlzICUxIikuYXJnKFN5c3RlbVByb3BlcnRp
ZXMudmVyc2lvblN0cmluZykKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBz
ZSAlMSIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcpCiAgICAgICAgICAgICAg
ICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQm9keQogICAgICAgICAgICAgICAg
ICAgICBmb250LmJvbGQ6IHRydWUKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQu
V3JhcApAQCAtNDA1OCw3ICs0MDg4LDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBMYWJl
bCB7CiAgICAgICAgICAgICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lkdGgKLSAgICAgICAgICAg
ICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBpcyB0aGUgTGludXgvU3RlYW1PUyBjbGllbnQg
Zm9yIEFwb2xsbyAmIFN1bnNoaW5lIGhvc3RzLiBUaGVzZSBvcGVuIGluIHlvdXIgYnJvd3Nlci4i
KQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIGlzIHRoZSBMaW51eC9T
dGVhbU9TIGNsaWVudCBmb3IgQXBvbGxvICYgU3Vuc2hpbmUgaG9zdHMuIFRoZXNlIG9wZW4gaW4g
eW91ciBicm93c2VyLiIpCiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRv
a2Vucy50eXBlQ2FwdGlvbgogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tl
bnMuZm9udEJvZHkKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAt
NDA2Niw3ICs0MDk2LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAg
ICAgICAgQnV0dG9uIHsKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBv
biBHaXRIdWIiKQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIG9uIEdp
dEh1YiIpCiAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogU3lzdGVtUHJvcGVydGllcy5v
cGVuVXJsKCJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3ZpYmVtaXMiKQogICAgICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgICAgICBCdXR0b24gewpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9T
eXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwgYi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlh
bG9nLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5lYzViNThiCi0tLSAv
ZGV2L251bGwKKysrIGIvYXBwL2d1aS9TeXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwKQEAgLTAs
MCArMSwxMTUgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMg
Mi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0IFF0UXVpY2suQ29udHJvbHMu
TWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBTeXN0ZW1D
b250cm9scyAxLjAKKworTmF2aWdhYmxlRGlhbG9nIHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9w
ZXJ0eSBzdHJpbmcga2luZDogIndpZmkiCisgICAgcHJvcGVydHkgdmFyIHNlbGVjdGVkOiAoe30p
CisgICAgd2lkdGg6IE1hdGgubWluKDYyMCwgcGFyZW50LndpZHRoIC0gMzIpCisgICAgaGVpZ2h0
OiBNYXRoLm1pbig1NjAsIHBhcmVudC5oZWlnaHQgLSAzMikKKyAgICB0aXRsZToga2luZCA9PT0g
IndpZmkiID8gcXNUcigiV2ktRmkgbmV0d29ya3MiKSA6IHFzVHIoIkJsdWV0b290aCBkZXZpY2Vz
IikKKyAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5DbG9zZQorICAgIE1hdGVyaWFsLmJhY2tn
cm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNj
ZW50CisgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgeyBjb2xvcjogVmJUb2tlbnMu
YmdFbGV2OyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0RpYWxvZzsgYm9yZGVyLmNvbG9yOiBWYlRv
a2Vucy5zdHJva2UgfQorICAgIG9uT3BlbmVkOiB7IHNlbGVjdGVkID0gKHt9KTsgU3lzdGVtQ29u
dHJvbHMub3BlbihraW5kKSB9CisgICAgb25DbG9zZWQ6IHsgY3JlZGVudGlhbC5jbG9zZSgpOyBz
ZWNyZXQudGV4dCA9ICIiOyBmb3JnZXQuY2xvc2UoKTsgU3lzdGVtQ29udHJvbHMuY2xvc2UoKSB9
CisgICAgY29udGVudEl0ZW06IENvbHVtbkxheW91dCB7CisgICAgICAgIHNwYWNpbmc6IFZiVG9r
ZW5zLnNwYWNlMworICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgTGF5b3V0LmZpbGxX
aWR0aDogdHJ1ZQorICAgICAgICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250
Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6
IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB0
ZXh0OiBTeXN0ZW1Db250cm9scy5zdGF0dXM7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAg
ICAgICAgICAgIEJ1c3lJbmRpY2F0b3IgeyBydW5uaW5nOiBTeXN0ZW1Db250cm9scy5idXN5OyB2
aXNpYmxlOiBydW5uaW5nOyBpbXBsaWNpdFdpZHRoOiAzMjsgaW1wbGljaXRIZWlnaHQ6IDMyIH0K
KyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyBpZDogc2NhbkJ1dHRvbjsgdGV4dDog
cXNUcigiU2NhbiIpOyBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiB7
IHBhbmVsLnNlbGVjdGVkID0gKHt9KTsgU3lzdGVtQ29udHJvbHMucmVxdWVzdChwYW5lbC5raW5k
ICsgIi1zY2FuIikgfSB9CisgICAgICAgIH0KKyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7
IHRleHQ6IHFzVHIoIkNhbmNlbCBvcGVyYXRpb24iKTsgdmlzaWJsZTogU3lzdGVtQ29udHJvbHMu
YnVzeTsgb25DbGlja2VkOiB7IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCk7IHBhbmVsLnNlbGVjdGVk
PSh7fSk7IHJlb3Blbi5yZXN0YXJ0KCkgfSB9CisgICAgICAgIFRpbWVyIHsgaWQ6IHJlb3Blbjsg
aW50ZXJ2YWw6IDYwMDsgb25UcmlnZ2VyZWQ6IGlmKHBhbmVsLm9wZW5lZCkgU3lzdGVtQ29udHJv
bHMub3BlbihwYW5lbC5raW5kKSB9CisgICAgICAgIFRpbWVyIHsgaW50ZXJ2YWw6NTAwMDsgcmVw
ZWF0OnRydWU7IHJ1bm5pbmc6cGFuZWwub3BlbmVkICYmIHBhbmVsLmtpbmQ9PT0iYnQiICYmICFT
eXN0ZW1Db250cm9scy5idXN5ICYmICFjcmVkZW50aWFsLm9wZW5lZDsgb25UcmlnZ2VyZWQ6U3lz
dGVtQ29udHJvbHMucmVxdWVzdCgiYnQtbGlzdCIpIH0KKyAgICAgICAgTGFiZWwgeyBmb250LmZh
bWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7
CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFw
OyBjb2xvcjogVmJUb2tlbnMudGV4dERpbQorICAgICAgICAgICAgdGV4dDogcGFuZWwua2luZCA9
PT0gIndpZmkiID8gcXNUcigiU2VsZWN0IGEgbmV0d29yaywgdGhlbiBDb25uZWN0LiBBZHZhbmNl
ZCBvciBoaWRkZW4gbmV0d29ya3MgYXJlIGF2YWlsYWJsZSBpbiB0aGUgZGlhZ25vc3RpYyBzaGVs
bC4iKSA6IHFzVHIoIlB1dCB5b3VyIGNvbnRyb2xsZXIgb3IgaGVhZHBob25lcyBpbiBwYWlyaW5n
IG1vZGUsIHRoZW4gU2Nhbi4gRGV2aWNlcyBhcHBlYXIgZHVyaW5nIHNjYW5uaW5nLiBTYXZlZCBk
ZXZpY2VzIGFyZSBsaXN0ZWQgd2l0aG91dCBzY2FubmluZy4iKQorICAgICAgICB9CisgICAgICAg
IExpc3RWaWV3IHsKKyAgICAgICAgICAgIGlkOiBkZXZpY2VzCisgICAgICAgICAgICBMYXlvdXQu
ZmlsbFdpZHRoOiB0cnVlOyBMYXlvdXQuZmlsbEhlaWdodDogdHJ1ZQorICAgICAgICAgICAgY2xp
cDogdHJ1ZTsgc3BhY2luZzogNDsgbW9kZWw6IFN5c3RlbUNvbnRyb2xzLml0ZW1zCisgICAgICAg
ICAgICBTY3JvbGxCYXIudmVydGljYWw6IFNjcm9sbEJhciB7fQorICAgICAgICAgICAgZGVsZWdh
dGU6IEl0ZW1EZWxlZ2F0ZSB7CisgICAgICAgICAgICAgICAgd2lkdGg6IGRldmljZXMud2lkdGgK
KyAgICAgICAgICAgICAgICBpbXBsaWNpdEhlaWdodDogTWF0aC5tYXgoNDQsY29udGVudEl0ZW0u
aW1wbGljaXRIZWlnaHQrMjQpCisgICAgICAgICAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xl
IHsgY29sb3I6cGFyZW50LmhpZ2hsaWdodGVkIHx8IHBhcmVudC5ob3ZlcmVkID8gVmJUb2tlbnMu
YmdFbGV2MiA6IFZiVG9rZW5zLmJnRWxldjsgcmFkaXVzOlZiVG9rZW5zLnJhZGl1c0NvbnRyb2w7
IGJvcmRlci5jb2xvcjpwYXJlbnQuYWN0aXZlRm9jdXM/VmJUb2tlbnMuYWNjZW50OlZiVG9rZW5z
LnN0cm9rZSB9CisgICAgICAgICAgICAgICAgZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3kK
KyAgICAgICAgICAgICAgICBoaWdobGlnaHRlZDogcGFuZWwuc2VsZWN0ZWQuaWQgPT09IG1vZGVs
RGF0YS5pZAorICAgICAgICAgICAgICAgIGFjdGl2ZUZvY3VzT25UYWI6IHRydWUKKyAgICAgICAg
ICAgICAgICBLZXlzLm9uUmV0dXJuUHJlc3NlZDogaWYgKGVuYWJsZWQpIGNsaWNrZWQoKQorICAg
ICAgICAgICAgICAgIEtleXMub25FbnRlclByZXNzZWQ6IGlmIChlbmFibGVkKSBjbGlja2VkKCkK
KyAgICAgICAgICAgICAgICBLZXlzLm9uRG93blByZXNzZWQ6IHsgaWYgKGluZGV4ICsgMSA8IGRl
dmljZXMuY291bnQpIHsgZGV2aWNlcy5pbmNyZW1lbnRDdXJyZW50SW5kZXgoKTsgaWYgKGRldmlj
ZXMuY3VycmVudEl0ZW0pIGRldmljZXMuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5U
YWJGb2N1cykgfSBlbHNlIGlmIChjb25uZWN0QnV0dG9uLmVuYWJsZWQpIGNvbm5lY3RCdXR0b24u
Zm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cyk7IGVsc2Ugc2NhbkJ1dHRvbi5mb3JjZUFjdGl2
ZUZvY3VzKFF0LlRhYkZvY3VzKSB9CisgICAgICAgICAgICAgICAgS2V5cy5vblVwUHJlc3NlZDog
eyBpZiAoaW5kZXggPiAwKSB7IGRldmljZXMuZGVjcmVtZW50Q3VycmVudEluZGV4KCk7IGlmIChk
ZXZpY2VzLmN1cnJlbnRJdGVtKSBkZXZpY2VzLmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMo
UXQuVGFiRm9jdXMpIH0gZWxzZSBzY2FuQnV0dG9uLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9j
dXMpIH0KKyAgICAgICAgICAgICAgICBjb250ZW50SXRlbTogTGFiZWwgeyBmb250LmZhbWlseTpW
YlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7CisgICAg
ICAgICAgICAgICAgICAgIHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyBlbGlkZTogVGV4dC5F
bGlkZVJpZ2h0OyBjb2xvcjogVmJUb2tlbnMudGV4dAorICAgICAgICAgICAgICAgICAgICB0ZXh0
OiBtb2RlbERhdGEubmFtZSArICIgwrcgIiArIG1vZGVsRGF0YS5kZXRhaWwgKyAobW9kZWxEYXRh
LmNvbm5lY3RlZCA/ICIgwrcgIiArIHFzVHIoIkNvbm5lY3RlZCIpIDogIiIpCisgICAgICAgICAg
ICAgICAgfQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBwYW5lbC5zZWxlY3RlZCA9IG1v
ZGVsRGF0YTsgZGV2aWNlcy5jdXJyZW50SW5kZXggPSBpbmRleCB9CisgICAgICAgICAgICB9Cisg
ICAgICAgIH0KKyAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lk
dGg6IHRydWUKKyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geworICAgICAgICAgICAg
ICAgIGlkOiBjb25uZWN0QnV0dG9uCisgICAgICAgICAgICAgICAgdGV4dDogcGFuZWwua2luZCA9
PT0gIndpZmkiID8gcXNUcigiQ29ubmVjdCIpIDogcXNUcigiUGFpciAvIENvbm5lY3QiKQorICAg
ICAgICAgICAgICAgIGVuYWJsZWQ6ICEhcGFuZWwuc2VsZWN0ZWQuaWQgJiYgIVN5c3RlbUNvbnRy
b2xzLmJ1c3kKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVl
c3QocGFuZWwua2luZCArICItY29ubmVjdCIsIHBhbmVsLnNlbGVjdGVkLmlkKQorICAgICAgICAg
ICAgfQorICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7CisgICAgICAgICAgICAgICAg
dGV4dDogcXNUcigiRGlzY29ubmVjdCIpOyBlbmFibGVkOiAhIXBhbmVsLnNlbGVjdGVkLmlkICYm
IHBhbmVsLnNlbGVjdGVkLmNvbm5lY3RlZCAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAg
ICAgICAgICAgIG9uQ2xpY2tlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdChwYW5lbC5raW5kICsg
Ii1kaXNjb25uZWN0IiwgcGFuZWwuc2VsZWN0ZWQuaWQpCisgICAgICAgICAgICB9CisgICAgICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiRm9yZ2V0Iik7IHZpc2libGU6
IHBhbmVsLmtpbmQgPT09ICJidCI7IGVuYWJsZWQ6ICEhcGFuZWwuc2VsZWN0ZWQuaWQgJiYgIVN5
c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogZm9yZ2V0Lm9wZW4oKSB9CisgICAgICAgIH0K
KyAgICB9CisgICAgQ29ubmVjdGlvbnMgeworICAgICAgICB0YXJnZXQ6IFN5c3RlbUNvbnRyb2xz
CisgICAgICAgIGZ1bmN0aW9uIG9uQ2hhbmdlZCgpIHsKKyAgICAgICAgICAgIGlmIChTeXN0ZW1D
b250cm9scy5wcm9tcHQubGVuZ3RoID4gMCAmJiBwYW5lbC5vcGVuZWQgJiYgIWNyZWRlbnRpYWwu
b3BlbmVkKSBjcmVkZW50aWFsLm9wZW4oKQorICAgICAgICAgICAgaWYgKCFTeXN0ZW1Db250cm9s
cy5idXN5KSB7CisgICAgICAgICAgICAgICAgY3JlZGVudGlhbC5jbG9zZSgpOyBzZWNyZXQudGV4
dCA9ICIiCisgICAgICAgICAgICAgICAgdmFyIGlkID0gcGFuZWwuc2VsZWN0ZWQuaWQKKyAgICAg
ICAgICAgICAgICBwYW5lbC5zZWxlY3RlZCA9ICh7fSkKKyAgICAgICAgICAgICAgICBmb3IgKHZh
ciBpID0gMDsgaSA8IFN5c3RlbUNvbnRyb2xzLml0ZW1zLmxlbmd0aDsgaSsrKQorICAgICAgICAg
ICAgICAgICAgICBpZiAoU3lzdGVtQ29udHJvbHMuaXRlbXNbaV0uaWQgPT09IGlkKSBwYW5lbC5z
ZWxlY3RlZCA9IFN5c3RlbUNvbnRyb2xzLml0ZW1zW2ldCisgICAgICAgICAgICB9CisgICAgICAg
IH0KKyAgICB9CisgICAgTmF2aWdhYmxlRGlhbG9nIHsKKyAgICAgICAgaWQ6IGNyZWRlbnRpYWwK
KyAgICAgICAgb2JqZWN0TmFtZTogImNvbm5lY3Rpb25DcmVkZW50aWFsIgorICAgICAgICB0aXRs
ZTogcXNUcigiQ29ubmVjdGlvbiBhdXRoZW50aWNhdGlvbiIpCisgICAgICAgIHdpZHRoOiBNYXRo
Lm1pbig0ODAsIHBhbmVsLndpZHRoKQorICAgICAgICBjbG9zZVBvbGljeTogUG9wdXAuTm9BdXRv
Q2xvc2UKKyAgICAgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuT2sgfCBEaWFsb2cuQ2FuY2Vs
CisgICAgICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgICAgICBv
bk9wZW5lZDogeyBzZWNyZXQudGV4dCA9ICIiOyBzZWNyZXQuZm9yY2VBY3RpdmVGb2N1cygpIH0K
KyAgICAgICAgb25BY2NlcHRlZDogeyBTeXN0ZW1Db250cm9scy5hbnN3ZXIoc2VjcmV0LnRleHQp
OyBzZWNyZXQudGV4dCA9ICIiIH0KKyAgICAgICAgb25SZWplY3RlZDogeyBzZWNyZXQudGV4dCA9
ICIiOyBTeXN0ZW1Db250cm9scy5jbG9zZSgpOyByZW9wZW4ucmVzdGFydCgpIH0KKyAgICAgICAg
Y29udGVudEl0ZW06IENvbHVtbkxheW91dCB7CisgICAgICAgICAgICBMYWJlbCB7IGZvbnQuZmFt
aWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsg
TGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHdyYXBN
b2RlOiBUZXh0LldyYXA7IHRleHQ6IFN5c3RlbUNvbnRyb2xzLnByb21wdDsgY29sb3I6IFZiVG9r
ZW5zLnRleHQgfQorICAgICAgICAgICAgVGV4dEZpZWxkIHsgaWQ6IHNlY3JldDsgZm9udC5mYW1p
bHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBM
YXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBlY2hvTW9kZTogVGV4dElucHV0LlBhc3N3b3JkOyBtYXhp
bXVtTGVuZ3RoOiA0MDk2OyBzZWxlY3RCeU1vdXNlOiB0cnVlOyBvbkFjY2VwdGVkOiBjcmVkZW50
aWFsLmFjY2VwdCgpIH0KKyAgICAgICAgICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMu
Zm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJFbnRlciB0aGUgcmVx
dWVzdGVkIHBhc3N3b3JkIG9yIFBJTi4gRm9yIGEgeWVzL25vIGNvbmZpcm1hdGlvbiwgdHlwZSB5
ZXMgb3Igbm8uIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgfQorICAgIH0K
KyAgICBOYXZpZ2FibGVEaWFsb2cgeworICAgICAgICBpZDogZm9yZ2V0CisgICAgICAgIGltcGxp
Y2l0SGVpZ2h0OiBjb250ZW50SXRlbS5jb250ZW50SGVpZ2h0ICsgaGVhZGVyLmltcGxpY2l0SGVp
Z2h0ICsgZm9vdGVyLmltcGxpY2l0SGVpZ2h0ICsgdG9wUGFkZGluZyArIGJvdHRvbVBhZGRpbmcK
KyAgICAgICAgb2JqZWN0TmFtZTogImNvbm5lY3Rpb25Gb3JnZXQiCisgICAgICAgIHRpdGxlOiBx
c1RyKCJGb3JnZXQgQmx1ZXRvb3RoIGRldmljZT8iKQorICAgICAgICB3aWR0aDogTWF0aC5taW4o
NDgwLCBwYW5lbC53aWR0aCkKKyAgICAgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuWWVzIHwg
RGlhbG9nLk5vCisgICAgICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgor
ICAgICAgICBvbkFjY2VwdGVkOiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJidC1mb3JnZXQiLCBw
YW5lbC5zZWxlY3RlZC5pZCwgdHJ1ZSkKKyAgICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgZm9u
dC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVC
b2R5OyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4
dDogcXNUcigiUmVtb3ZlIHRoZSBzYXZlZCBwYWlyaW5nIGZvciAlMT8gWW91IHdpbGwgbmVlZCB0
byBwYWlyIGl0IGFnYWluLiIpLmFyZyhwYW5lbC5zZWxlY3RlZC5uYW1lIHx8ICIiKTsgY29sb3I6
IFZiVG9rZW5zLnRleHQgfQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvVGhlbWUucW1s
IGIvYXBwL2d1aS9UaGVtZS5xbWwKaW5kZXggZmI5MWM4NS4uNTdjOWY4NCAxMDA2NDQKLS0tIGEv
YXBwL2d1aS9UaGVtZS5xbWwKKysrIGIvYXBwL2d1aS9UaGVtZS5xbWwKQEAgLTExLDIwICsxMSwy
MCBAQCBpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKIFF0T2JqZWN0IHsKICAgICAvLyAtLS0t
IENvbG9yIC0tLS0KICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnQ6ICAgICAgICBW
YlRva2Vucy5hY2NlbnQgIC8vIEJMLTIwNzc6IHNpbmdsZSBzb3VyY2Ugb2YgdHJ1dGggKFZiVG9r
ZW5zIGJyYW5kIGFjY2VudCwgZGVmYXVsdCAjMDBDQ0NDKQotICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIGFjY2VudFByZXNzZWQ6ICIjMDBBM0EzIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIGJhY2tncm91bmQ6ICAgICIjMzAzMDMwIiAgLy8gYXBwIHJvb3QKLSAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciBzdXJmYWNlOiAgICAgICAiIzJEMkQyRCIgIC8vIHJhaXNlZCBzdXJmYWNl
cyAvIG92ZXJsYXlzCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3VyZmFjZUFsdDogICAg
IiM0MjQyNDIiICAvLyBwb3B1cHMgLyBjb21ibyBkcm9wZG93bnMKLSAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBib3JkZXI6ICAgICAgICAiIzQ0NDQ0NCIKLSAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciB0ZXh0UHJpbWFyeTogICAiI0ZGRkZGRiIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciB0ZXh0U2Vjb25kYXJ5OiAiI0NDQ0NDQyIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xv
ciB0ZXh0VGVydGlhcnk6ICAiI0FBQUFBQSIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0
ZXh0RGlzYWJsZWQ6ICAiIzc3Nzc3NyIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdWNj
ZXNzOiAgICAgICAiIzRDQUY1MCIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB3YXJuaW5n
OiAgICAgICAiI0UwQTAzMCIgIC8vIHRoZSBzaW5nbGUgYW1iZXIKLSAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBlcnJvcjogICAgICAgICAiI0Y0NDMzNiIKLSAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciBpbmZvOiAgICAgICAgICAiIzgwQTBDMCIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciBzY3JpbTogICAgICAgICAiI0QwMDAwMDAwIgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIGFjY2VudFByZXNzZWQ6IFZiVG9rZW5zLmFjY2VudFByZXNzZWQKKyAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciBiYWNrZ3JvdW5kOiAgICBWYlRva2Vucy5iZ1dpbmRvdyAgLy8gYXBwIHJv
b3QKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdXJmYWNlOiAgICAgICBWYlRva2Vucy5i
Z0VsZXYgIC8vIHJhaXNlZCBzdXJmYWNlcyAvIG92ZXJsYXlzCisgICAgcmVhZG9ubHkgcHJvcGVy
dHkgY29sb3Igc3VyZmFjZUFsdDogICAgVmJUb2tlbnMuYmdFbGV2MiAgLy8gcG9wdXBzIC8gY29t
Ym8gZHJvcGRvd25zCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYm9yZGVyOiAgICAgICAg
VmJUb2tlbnMuc3Ryb2tlCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFByaW1hcnk6
ICAgVmJUb2tlbnMudGV4dFByaW1hcnkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0
U2Vjb25kYXJ5OiBWYlRva2Vucy50ZXh0U2Vjb25kYXJ5CisgICAgcmVhZG9ubHkgcHJvcGVydHkg
Y29sb3IgdGV4dFRlcnRpYXJ5OiAgVmJUb2tlbnMudGV4dFRlcnRpYXJ5CisgICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3IgdGV4dERpc2FibGVkOiAgVmJUb2tlbnMudGV4dERpc2FibGVkCisgICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3VjY2VzczogICAgICAgVmJUb2tlbnMuc3RhdHVzU3Vj
Y2VzcworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHdhcm5pbmc6ICAgICAgIFZiVG9rZW5z
LnN0YXR1c1dhcm5pbmcgIC8vIHRoZSBzaW5nbGUgYW1iZXIKKyAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciBlcnJvcjogICAgICAgICBWYlRva2Vucy5zdGF0dXNEYW5nZXIKKyAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBpbmZvOiAgICAgICAgICBWYlRva2Vucy5zdGF0dXNJbmZvCisgICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc2NyaW06ICAgICAgICAgVmJUb2tlbnMuZGlhbG9nU2Ny
aW0KIAogICAgIC8vIC0tLS0gVHlwb2dyYXBoeSAocG9pbnRTaXplOyBwYWlyIHdpdGggYm9sZCB3
aGVyZSBub3RlZCBpbiBERVNJR05fU1lTVEVNLm1kKSAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVy
dHkgaW50IGZvbnREaXNwbGF5OiAyNCAgLy8gb3ZlcmxheS9RdWljayBNZW51IHRpdGxlIChib2xk
KQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9WYkNhcmQucW1sIGIvYXBwL2d1aS9WYkNhcmQucW1sCmlu
ZGV4IDM3ZjJlMzIuLjFjOTcxMGQgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVmJDYXJkLnFtbAorKysg
Yi9hcHAvZ3VpL1ZiQ2FyZC5xbWwKQEAgLTE5LDE1ICsxOSwxOSBAQCBJdGVtIHsKICAgICAgICAg
cmFkaXVzOiBjYXJkLnJhZGl1cwogICAgIH0KIAotICAgIFJlY3RhbmdsZSB7CisgICAgQ3JpbXNv
bkdsYXNzUGFuZWwgewogICAgICAgICBpZDogc3VyZmFjZQogICAgICAgICBhbmNob3JzLmZpbGw6
IHBhcmVudAogICAgICAgICByYWRpdXM6IGNhcmQucmFkaXVzCiAgICAgICAgIGNvbG9yOiBjYXJk
LmZvY3VzZWQgPyBWYlRva2Vucy5mb2N1c2VkRmlsbCA6IGNhcmQuYmFzZUNvbG9yCisgICAgICAg
IGdyYWRpZW50OiBHcmFkaWVudCB7CisgICAgICAgICAgICBHcmFkaWVudFN0b3AgeyBwb3NpdGlv
bjowO2NvbG9yOmNhcmQuZm9jdXNlZCA/IFZiVG9rZW5zLmJnRWxldjIgOiBWYlRva2Vucy5nbGFz
c1RvcCB9CisgICAgICAgICAgICBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjoxO2NvbG9yOmNhcmQu
Zm9jdXNlZCA/IFZiVG9rZW5zLmZvY3VzZWRGaWxsIDogY2FyZC5iYXNlQ29sb3IgfQorICAgICAg
ICB9CiAgICAgICAgIGJvcmRlci53aWR0aDogMQogICAgICAgICBib3JkZXIuY29sb3I6IFZiVG9r
ZW5zLnN0cm9rZQogICAgICAgICBvcGFjaXR5OiBjYXJkLmNvbnRlbnRPcGFjaXR5Ci0gICAgICAg
IEJlaGF2aW9yIG9uIGNvbG9yIHsgQ29sb3JBbmltYXRpb24geyBkdXJhdGlvbjogMTIwIH0gfQor
ICAgICAgICBCZWhhdmlvciBvbiBjb2xvciB7IENvbG9yQW5pbWF0aW9uIHsgZHVyYXRpb246IFZi
VG9rZW5zLm1vdGlvbkVuYWJsZWQgPyAxMjAgOiAwIH0gfQogICAgIH0KIAogICAgIEl0ZW0gewpk
aWZmIC0tZ2l0IGEvYXBwL2d1aS9WYkhvc3RDYXJkLnFtbCBiL2FwcC9ndWkvVmJIb3N0Q2FyZC5x
bWwKaW5kZXggOWUxZmU3Zi4uOWRiYTZhNiAxMDA2NDQKLS0tIGEvYXBwL2d1aS9WYkhvc3RDYXJk
LnFtbAorKysgYi9hcHAvZ3VpL1ZiSG9zdENhcmQucW1sCkBAIC0yOSw3ICsyOSw3IEBAIEl0ZW0g
ewogICAgICAgICByYWRpdXM6IDIwCiAgICAgfQogCi0gICAgUmVjdGFuZ2xlIHsKKyAgICBDcmlt
c29uR2xhc3NQYW5lbCB7CiAgICAgICAgIGlkOiBzdXJmYWNlCiAgICAgICAgIGFuY2hvcnMuZmls
bDogcGFyZW50CiAgICAgICAgIHJhZGl1czogMjAKQEAgLTQ1LDIwICs0NSwyMCBAQCBJdGVtIHsK
IAogICAgICAgICBDb2x1bW5MYXlvdXQgewogICAgICAgICAgICAgYW5jaG9ycy5maWxsOiBwYXJl
bnQKLSAgICAgICAgICAgIGFuY2hvcnMubWFyZ2luczogMzIKKyAgICAgICAgICAgIGFuY2hvcnMu
bWFyZ2luczogMjQKICAgICAgICAgICAgIC8vIFJlc2VydmUgdGhlIGJvdHRvbSBzdHJpcCBmb3Ig
dGhlIGFuY2hvcmVkIGJhZGdlL21ldGEgcm93IGJlbG93LiBUaGUgb2xkCiAgICAgICAgICAgICAv
LyBzaW5nbGUtY29sdW1uIGZsb3cgb3ZlcmZsb3dlZCB0aGUgZml4ZWQgMjQycHggY2FyZCBieSB+
MTFweCB3aXRoIHJlYWwgZGV2aWNlIGZvbnRzCiAgICAgICAgICAgICAvLyAoMzIrNTgrMjArbmFt
ZSs2K2FjY2VzcysyMCtiYWRnZSszMiA+IDI0MiksIHNob3ZpbmcgdGhlIGJhZGdlIHJvdyBvbnRv
IHRoZSBib3JkZXIuCiAgICAgICAgICAgICBhbmNob3JzLmJvdHRvbU1hcmdpbjogNjQKLSAgICAg
ICAgICAgIHNwYWNpbmc6IDIwCisgICAgICAgICAgICBzcGFjaW5nOiAxNAogCiAgICAgICAgICAg
ICAvLyAtLS0tIFJvdyAxOiBtb25pdG9yIG91dGxpbmUgKyBzdGF0dXMgcGlsbCAtLS0tCiAgICAg
ICAgICAgICBSb3dMYXlvdXQgewogICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRy
dWUKICAgICAgICAgICAgICAgICAvLyBNb25pdG9yOiBhbiA4MsOXNTggcm91bmRlZCByZWN0YW5n
bGUgZHJhd24gYXMgYSA1cHggb3V0bGluZSAobm8gZmlsbCksIGxpa2UgdGhlIEhUTUwuCiAgICAg
ICAgICAgICAgICAgUmVjdGFuZ2xlIHsKLSAgICAgICAgICAgICAgICAgICAgTGF5b3V0LnByZWZl
cnJlZFdpZHRoOiA4MgotICAgICAgICAgICAgICAgICAgICBMYXlvdXQucHJlZmVycmVkSGVpZ2h0
OiA1OAorICAgICAgICAgICAgICAgICAgICBMYXlvdXQucHJlZmVycmVkV2lkdGg6IDY0CisgICAg
ICAgICAgICAgICAgICAgIExheW91dC5wcmVmZXJyZWRIZWlnaHQ6IDQ4CiAgICAgICAgICAgICAg
ICAgICAgIHJhZGl1czogMTAKICAgICAgICAgICAgICAgICAgICAgY29sb3I6ICJ0cmFuc3BhcmVu
dCIKICAgICAgICAgICAgICAgICAgICAgYm9yZGVyLndpZHRoOiA1CkBAIC04NSw3ICs4NSw3IEBA
IEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNvbG9yOiBjYXJkLm9ubGluZSA/
IFZiVG9rZW5zLnN0YXR1c09ubGluZQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICA6IChjYXJkLnN0YXR1c1Vua25vd24gPyBWYlRva2Vucy50ZXh0RGltIDog
IiM1QTYyNkMiKQogICAgICAgICAgICAgICAgICAgICAgICAgICAgIFNlcXVlbnRpYWxBbmltYXRp
b24gb24gb3BhY2l0eSB7Ci0gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHJ1bm5pbmc6
IGNhcmQub25saW5lIHx8IGNhcmQuc3RhdHVzVW5rbm93bgorICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICBydW5uaW5nOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkICYmIChjYXJkLm9ubGlu
ZSB8fCBjYXJkLnN0YXR1c1Vua25vd24pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
IGxvb3BzOiBBbmltYXRpb24uSW5maW5pdGUKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMS4wOyB0bzogMC40NTsgZHVyYXRpb246IFZiVG9r
ZW5zLm9ubGluZVB1bHNlTXMgLyAyIH0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
TnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMC40NTsgdG86IDEuMDsgZHVyYXRpb246IFZiVG9rZW5z
Lm9ubGluZVB1bHNlTXMgLyAyIH0KQEAgLTk2LDcgKzk2LDcgQEAgSXRlbSB7CiAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgdGV4dDogY2FyZC5vbmxpbmUgPyBxc1RyKCJPTkxJTkUiKQogICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDogKGNhcmQuc3RhdHVz
VW5rbm93biA/IHFzVHIoIkNIRUNLSU5HIikgOiBxc1RyKCJPRkZMSU5FIikpCiAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRCb2R5Ci0gICAgICAg
ICAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IDE0CisgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVMYWJlbAogICAgICAgICAg
ICAgICAgICAgICAgICAgICAgIGZvbnQud2VpZ2h0OiBGb250LkJvbGQKICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICBmb250LmxldHRlclNwYWNpbmc6IDAuNwogICAgICAgICAgICAgICAgICAg
ICAgICAgICAgIGNvbG9yOiBjYXJkLm9ubGluZSA/IFZiVG9rZW5zLnN0YXR1c09ubGluZSA6IFZi
VG9rZW5zLnRleHREaW0KQEAgLTExNCw3ICsxMTQsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAg
ICAgICAgdGV4dDogY2FyZC5ob3N0TmFtZQogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWls
eTogVmJUb2tlbnMuZm9udERpc3BsYXkKICAgICAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6
IEZvbnQuQm9sZAotICAgICAgICAgICAgICAgICAgICBmb250LnBpeGVsU2l6ZTogMjcKKyAgICAg
ICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVIZWFkaW5nCiAgICAg
ICAgICAgICAgICAgICAgIGNvbG9yOiBjYXJkLm9ubGluZSA/IFZiVG9rZW5zLnRleHQgOiBWYlRv
a2Vucy50ZXh0TXV0ZQogICAgICAgICAgICAgICAgICAgICBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0
CiAgICAgICAgICAgICAgICAgfQpAQCAtMTIzLDcgKzEyMyw3IEBAIEl0ZW0gewogICAgICAgICAg
ICAgICAgICAgICB0ZXh0OiBjYXJkLmFjY2Vzc1RleHQKICAgICAgICAgICAgICAgICAgICAgdmlz
aWJsZTogY2FyZC5hY2Nlc3NUZXh0ICE9PSAiIgogICAgICAgICAgICAgICAgICAgICBmb250LmZh
bWlseTogVmJUb2tlbnMuZm9udEJvZHkKLSAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNp
emU6IDE3CisgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBl
TGFiZWwKICAgICAgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLnRleHREaW0KICAgICAg
ICAgICAgICAgICAgICAgZWxpZGU6IFRleHQuRWxpZGVSaWdodAogICAgICAgICAgICAgICAgIH0K
QEAgLTEzOSw4ICsxMzksOCBAQCBJdGVtIHsKICAgICAgICAgICAgIGFuY2hvcnMubGVmdDogcGFy
ZW50LmxlZnQKICAgICAgICAgICAgIGFuY2hvcnMucmlnaHQ6IHBhcmVudC5yaWdodAogICAgICAg
ICAgICAgYW5jaG9ycy5ib3R0b206IHBhcmVudC5ib3R0b20KLSAgICAgICAgICAgIGFuY2hvcnMu
bGVmdE1hcmdpbjogMzIKLSAgICAgICAgICAgIGFuY2hvcnMucmlnaHRNYXJnaW46IDMyCisgICAg
ICAgICAgICBhbmNob3JzLmxlZnRNYXJnaW46IDI0CisgICAgICAgICAgICBhbmNob3JzLnJpZ2h0
TWFyZ2luOiAyNAogICAgICAgICAgICAgYW5jaG9ycy5ib3R0b21NYXJnaW46IDIyCiAgICAgICAg
ICAgICBzcGFjaW5nOiAxMAogICAgICAgICAgICAgLy8gSG9zdC10eXBlIGJhZGdlIChhY2NlbnQg
b3V0bGluZSBmb3IgQXBvbGxvLWxpbmVhZ2UsIG5ldXRyYWwgZm9yIFN1bnNoaW5lKS4KQEAgLTE1
Nyw3ICsxNTcsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgYW5jaG9ycy5jZW50ZXJJ
bjogcGFyZW50CiAgICAgICAgICAgICAgICAgICAgIHRleHQ6IGNhcmQuaG9zdEJhZGdlCiAgICAg
ICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250Qm9keQotICAgICAgICAg
ICAgICAgICAgICBmb250LnBpeGVsU2l6ZTogMTMKKyAgICAgICAgICAgICAgICAgICAgZm9udC5w
aXhlbFNpemU6IFZiVG9rZW5zLnR5cGVDYXB0aW9uCiAgICAgICAgICAgICAgICAgICAgIGZvbnQu
d2VpZ2h0OiBGb250LkV4dHJhQm9sZAogICAgICAgICAgICAgICAgICAgICBmb250LmxldHRlclNw
YWNpbmc6IDEuMgogICAgICAgICAgICAgICAgICAgICBjb2xvcjogY2FyZC5iYWRnZUFjY2VudCA/
IFZiVG9rZW5zLmFjY2VudCA6IFZiVG9rZW5zLnRleHREaW0KZGlmZiAtLWdpdCBhL2FwcC9ndWkv
VmJIb3N0U2hlZXQucW1sIGIvYXBwL2d1aS9WYkhvc3RTaGVldC5xbWwKaW5kZXggYjRhMWFmOC4u
NTdmY2JiNiAxMDA2NDQKLS0tIGEvYXBwL2d1aS9WYkhvc3RTaGVldC5xbWwKKysrIGIvYXBwL2d1
aS9WYkhvc3RTaGVldC5xbWwKQEAgLTc4LDcgKzc4LDcgQEAgUG9wdXAgewogICAgICAgICB9CiAK
ICAgICAgICAgLy8gLS0tLSBSaWdodCBwYW5lbCAtLS0tCi0gICAgICAgIFJlY3RhbmdsZSB7Cisg
ICAgICAgIENyaW1zb25HbGFzc1BhbmVsIHsKICAgICAgICAgICAgIGlkOiBwYW5lbAogICAgICAg
ICAgICAgd2lkdGg6IE1hdGgubWluKDU2MCwgcm9vdC53aWR0aCAqIDAuNjIpCiAgICAgICAgICAg
ICBoZWlnaHQ6IHBhcmVudC5oZWlnaHQKZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJTdGF0dXNQaWxs
LnFtbCBiL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbAppbmRleCA4OWM0NzcwLi5jNzI4ZjA1IDEw
MDY0NAotLS0gYS9hcHAvZ3VpL1ZiU3RhdHVzUGlsbC5xbWwKKysrIGIvYXBwL2d1aS9WYlN0YXR1
c1BpbGwucW1sCkBAIC0yNCw3ICsyNCw3IEBAIFJlY3RhbmdsZSB7CiAgICAgICAgICAgICBjb2xv
cjogcGlsbC5vbmxpbmUgPyBWYlRva2Vucy5zdGF0dXNPbmxpbmUgOiBWYlRva2Vucy5zdGF0dXNP
ZmZsaW5lCiAgICAgICAgICAgICAvLyBQdWxzZSBvbmx5IHdoZW4gb25saW5lLgogICAgICAgICAg
ICAgU2VxdWVudGlhbEFuaW1hdGlvbiBvbiBvcGFjaXR5IHsKLSAgICAgICAgICAgICAgICBydW5u
aW5nOiBwaWxsLm9ubGluZQorICAgICAgICAgICAgICAgIHJ1bm5pbmc6IHBpbGwub25saW5lICYm
IFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQKICAgICAgICAgICAgICAgICBsb29wczogQW5pbWF0aW9u
LkluZmluaXRlCiAgICAgICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMS4wOyB0
bzogMC40NTsgZHVyYXRpb246IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAyOyBlYXNpbmcudHlw
ZTogRWFzaW5nLkluT3V0U2luZSB9CiAgICAgICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsg
ZnJvbTogMC40NTsgdG86IDEuMDsgZHVyYXRpb246IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAy
OyBlYXNpbmcudHlwZTogRWFzaW5nLkluT3V0U2luZSB9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1Zi
VG9rZW5zLnFtbCBiL2FwcC9ndWkvVmJUb2tlbnMucW1sCmluZGV4IDUyYTM0ZGUuLjdjZDg4ZDAg
MTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVmJUb2tlbnMucW1sCisrKyBiL2FwcC9ndWkvVmJUb2tlbnMu
cW1sCkBAIC0xLDU3ICsxLDYzIEBACiBwcmFnbWEgU2luZ2xldG9uCiBpbXBvcnQgUXRRdWljayAy
LjkKIGltcG9ydCBTdHJlYW1pbmdQcmVmZXJlbmNlcyAxLjAKK2ltcG9ydCBFY2xpcHNlUHJvZmls
ZXMgMS4wCiAKLS8vIFZpYmVtaXMgcmVkZXNpZ24gZGVzaWduIHRva2Vucy4KKy8vIENyaW1zb24g
R2xhc3Mg4oCUIEVjbGlwc2VPUyBmcm9udGVuZCBkZXNpZ24gdG9rZW5zLgogLy8gRGFyayB0aGVt
ZSBvbmx5LiBDYW52YXMgMTkyMHgxMjAwIChMZWdpb24gR28gUyksCiAvLyBzY2FsZXMgdG8gMTI4
MHg4MDAgKFN0ZWFtIERlY2spIHZpYSBhbmNob3JzL0xheW91dHMg4oCUIG5ldmVyIGhhcmQtY29k
ZSBjb29yZGluYXRlcyBhZ2FpbnN0IHRoZXNlLgogLy8gUmVnaXN0ZXJlZCBhcyBhIFFNTCBzaW5n
bGV0b24gaW4gYXBwL21haW4uY3BwOiBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGUocXJjOi9ndWkv
VmJUb2tlbnMucW1sKS4KIFF0T2JqZWN0IHsKICAgICBpZDogdAogCisgICAgcmVhZG9ubHkgcHJv
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
OiAgICAgICAiIzE1MTMxNiIgIC8vIGNhcmRzLCBwYW5lbHMsIGRpYWxvZ3MsIHNpZGViYXIgcm93
cworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxldjI6ICAgICAgIiMyNzFCMjIiICAv
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
YWNjZW50LWZpbGxlZCBidXR0b24KIAorICAgIHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgZ2xhc3NP
cGFjaXR5OiBFY2xpcHNlUHJvZmlsZXMuaGlnaENvbnRyYXN0ID8gMS4wIDogMC45MgorICAgIHJl
YWRvbmx5IHByb3BlcnR5IHN0cmluZyBkZXNpZ25OYW1lOiAiQ3JpbXNvbiBHbGFzcyIKKyAgICBy
ZWFkb25seSBwcm9wZXJ0eSBjb2xvciBnbGFzc1RvcDogRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250
cmFzdCA/ICIjMjUyMTI2IiA6ICIjMjExRDIzIgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9y
IGdsYXNzRWRnZTogUXQucmdiYSgxLDEsMSxFY2xpcHNlUHJvZmlsZXMuaGlnaENvbnRyYXN0ID8g
MC4zNSA6IDAuMTYpCiAgICAgLy8gLS0tLSBUeXBvZ3JhcGh5IChmYW1pbGllcyArIHNpemVzOyB3
ZWlnaHRzIHBlciB0aGUgdHlwZSBzY2FsZSkgLS0tLQogICAgIHJlYWRvbmx5IHByb3BlcnR5IHN0
cmluZyBmb250RGlzcGxheTogIlNvcmEiICAgICAvLyB0aXRsZXMsIGNhcmQgbmFtZXMsIHdvcmRt
YXJrLCBhbGwtY2FwcyBsYWJlbHMKICAgICByZWFkb25seSBwcm9wZXJ0eSBzdHJpbmcgZm9udEJv
ZHk6ICAgICJNYW5yb3BlIiAgLy8gYm9keSArIFVJIHRleHQKLSAgICByZWFkb25seSBwcm9wZXJ0
eSBpbnQgc2l6ZVNjcmVlblRpdGxlOiAgMzQKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6
ZVNlY3Rpb25UaXRsZTogMjgKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZUNhcmROYW1l
OiAgICAgMjcKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZUJvZHk6ICAgICAgICAgMTYK
LSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZUxhYmVsOiAgICAgICAgMTQKLSAgICByZWFk
b25seSBwcm9wZXJ0eSBpbnQgc2l6ZUJhZGdlOiAgICAgICAgMTMKLSAgICByZWFkb25seSBwcm9w
ZXJ0eSBpbnQgc2l6ZVdvcmRtYXJrOiAgICAgMjEKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQg
c2l6ZVNjcmVlblRpdGxlOiAgTWF0aC5yb3VuZCgzNCAqIHRleHRTY2FsZSkKKyAgICByZWFkb25s
eSBwcm9wZXJ0eSBpbnQgc2l6ZVNlY3Rpb25UaXRsZTogTWF0aC5yb3VuZCgyOCAqIHRleHRTY2Fs
ZSkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZUNhcmROYW1lOiAgICAgTWF0aC5yb3Vu
ZCgyNyAqIHRleHRTY2FsZSkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZUJvZHk6ICAg
ICAgICAgTWF0aC5yb3VuZCgxNiAqIHRleHRTY2FsZSkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBp
bnQgc2l6ZUxhYmVsOiAgICAgICAgTWF0aC5yb3VuZCgxNCAqIHRleHRTY2FsZSkKKyAgICByZWFk
b25seSBwcm9wZXJ0eSBpbnQgc2l6ZUJhZGdlOiAgICAgICAgTWF0aC5yb3VuZCgxMyAqIHRleHRT
Y2FsZSkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2l6ZVdvcmRtYXJrOiAgICAgTWF0aC5y
b3VuZCgyMSAqIHRleHRTY2FsZSkKICAgICByZWFkb25seSBwcm9wZXJ0eSByZWFsIHdvcmRtYXJr
U3BhY2luZzogMy4wCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgcmVhbCBiYWRnZVNwYWNpbmc6ICAg
IDEuMgogCiAgICAgLy8gLS0tLSBSYWRpdXMgLS0tLQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGlu
dCByYWRpdXNXaW5kb3c6ICAgICAyMAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCByYWRpdXND
YXJkOiAgICAgICAxNgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCByYWRpdXNDYXJkOiAgICAg
ICAyMAogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCByYWRpdXNEaWFsb2c6ICAgICAyNAogICAg
IHJlYWRvbmx5IHByb3BlcnR5IGludCByYWRpdXNDb250cm9sOiAgICAxNAogICAgIHJlYWRvbmx5
IHByb3BlcnR5IGludCByYWRpdXNJY29uQnV0dG9uOiAxNApAQCAtNTksMTIgKzY1LDEyIEBAIFF0
T2JqZWN0IHsKICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgcmFkaXVzQmFkZ2U6ICAgICAgNwog
CiAgICAgLy8gLS0tLSBTcGFjaW5nIC0tLS0KLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2Ny
ZWVuUGFkWDogNTYKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2NyZWVuUGFkWTogNTIKKyAg
ICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2NyZWVuUGFkWDogMjQKKyAgICByZWFkb25seSBwcm9w
ZXJ0eSBpbnQgc2NyZWVuUGFkWTogMjQKICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgaGVhZGVy
SDogICAgODQKICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgZm9vdGVySDogICAgNzIKLSAgICBy
ZWFkb25seSBwcm9wZXJ0eSBpbnQgY2FyZEdhcDogICAgMzIKLSAgICByZWFkb25seSBwcm9wZXJ0
eSBpbnQgdGlsZUdhcDogICAgMzYKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgY2FyZEdhcDog
ICAgMjAKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgdGlsZUdhcDogICAgMjAKICAgICByZWFk
b25seSBwcm9wZXJ0eSBpbnQgaWNvbkJ1dHRvbjogNTIKIAogICAgIC8vIC0tLS0gR2FtZXBhZCBl
cmdvbm9taWNzIC0tLS0KQEAgLTgzLDcgKzg5LDcgQEAgUXRPYmplY3QgewogICAgIC8vIC0tLS0g
TW90aW9uIChtcykgLS0tLQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBvbmxpbmVQdWxzZU1z
OiAyNDAwICAgLy8gb3BhY2l0eSAxIC0+IDAuNDUgLT4gMSwgaW5maW5pdGUKICAgICByZWFkb25s
eSBwcm9wZXJ0eSBpbnQgY2FyZXRCbGlua01zOiAgMTAwMCAgIC8vIEFkZC1QQyBpbnB1dCBjYXJl
dAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaGVldEluTXM6ICAgICAyMjAgICAgLy8gc2lk
ZS1zaGVldCBzbGlkZS1pbgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaGVldEluTXM6ICAg
ICBtb3Rpb25FbmFibGVkID8gMjIwIDogMCAgICAvLyBzaWRlLXNoZWV0IHNsaWRlLWluCiAgICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZGlhbG9nU2NyaW06IFF0LnJnYmEoNC8yNTUsIDUvMjU1
LCA3LzI1NSwgMC43MikKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzaGVldFNjcmltOiAg
UXQucmdiYSg0LzI1NSwgNS8yNTUsIDcvMjU1LCAwLjYwKQogCkBAIC0xMTksNyArMTI1LDcgQEAg
UXRPYmplY3QgewogICAgIC8vIHRleHRPbkFjY2VudCAoIzA4MDkwQikgaXMgZGVmaW5lZCBpbiB0
aGUgYmFzZSBibG9jayBhYm92ZSDigJQgdGV4dCBvbiBhbiBhY2NlbnQgZmlsbC4KIAogICAgIC8v
IC0tLS0gSW50ZXJhY3RpdmUgc3RhdGVzOiBub3JtYWwgLyBob3ZlciAvIGZvY3VzIC8gcHJlc3Nl
ZCAvIGRpc2FibGVkIC0tLS0KLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVz
c2VkOiAgICAgICIjMDBBM0EzIiAvLyBwcmVzc2VkIGFjY2VudGVkIGNvbnRyb2wgKG1hdGNoZXMg
bGVnYWN5IFRoZW1lLmFjY2VudFByZXNzZWQpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
YWNjZW50UHJlc3NlZDogICAgICBRdC5kYXJrZXIoYWNjZW50LCAxLjE4KSAvLyBwcmVzc2VkIGFj
Y2VudGVkIGNvbnRyb2wgKG1hdGNoZXMgbGVnYWN5IFRoZW1lLmFjY2VudFByZXNzZWQpCiAgICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW50ZXJhY3RpdmVIb3ZlcjogICBiZ0VsZXYyICAgIC8v
IHJvdyAvIGxpc3QtaXRlbSAvIGljb24tYnV0dG9uIGhvdmVyIGZpbGwKICAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZUZvY3VzOiAgIGZvY3VzZWRGaWxsLy8gZm9jdXNlZCBm
aWxsICg9IGJnRWxldjIpIOKAlCBwYWlyIHdpdGggdGhlIGZvY3VzIHJpbmcKICAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZVByZXNzZWQ6IGJnRWxldiAgICAgLy8gcHJlc3Nl
ZCBuZXV0cmFsIGZpbGwgKHJlY2VkZXMgdW5kZXIgdGhlIHByZXNzKQpkaWZmIC0tZ2l0IGEvYXBw
L2d1aS9WYldlbGNvbWVTaGVldC5xbWwgYi9hcHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFtbAppbmRl
eCAxNzMxMTliLi5hMTRlYWU3IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFt
bAorKysgYi9hcHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFtbApAQCAtMjYsNyArMjYsNyBAQCBOYXZp
Z2FibGVEaWFsb2cgewogICAgIC8vIFRva2VuIHNjcmltIGJlaGluZCB0aGUgbW9kYWwgY2FyZCAo
bWF0Y2hlcyB0aGUgcmVkZXNpZ24gZGlhbG9nIGxhbmd1YWdlKS4KICAgICBPdmVybGF5Lm1vZGFs
OiBSZWN0YW5nbGUgeyBjb2xvcjogVmJUb2tlbnMuZGlhbG9nU2NyaW0gfQogCi0gICAgYmFja2dy
b3VuZDogUmVjdGFuZ2xlIHsKKyAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7CiAg
ICAgICAgIGNvbG9yOiBWYlRva2Vucy5iZ0VsZXYKICAgICAgICAgcmFkaXVzOiBWYlRva2Vucy5y
YWRpdXNEaWFsb2cKICAgICAgICAgYm9yZGVyLndpZHRoOiAxCkBAIC0xMDgsMTQgKzEwOCwxMyBA
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
aS9tYWluLnFtbAppbmRleCA5YmNlNTEwLi4xNGYzNTA4IDEwMDY0NAotLS0gYS9hcHAvZ3VpL21h
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
aWdhdGlvbi5lbmFibGUoKQogICAgIH0KQEAgLTEyOSw2ICsxNDUsOCBAQCBBcHBsaWNhdGlvbldp
bmRvdyB7CiAgICAgICAgIH0KICAgICB9CiAKKyAgICBDcmltc29uR2xhc3NCYWNrZHJvcCB7IGFu
Y2hvcnMuZmlsbDpwYXJlbnQgfQorCiAgICAgU3RhY2tWaWV3IHsKICAgICAgICAgaWQ6IHN0YWNr
VmlldwogICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudApAQCAtMjY3LDYgKzI4NSwyNSBAQCBB
cHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgIH0KICAgICB9CiAKKyAgICBDcmltc29uU3RhdHVz
RGlhbG9nIHsgaWQ6IGNyaW1zb25QYW5lbCB9CisgICAgU3lzdGVtQ29ubmVjdGlvbnNEaWFsb2cg
eyBpZDogY29ubmVjdGlvblBhbmVsIH0KKyAgICBFY2xpcHNlQWJvdXREaWFsb2cgeyBpZDogZWNs
aXBzZUFib3V0IH0KKyAgICBFY2xpcHNlQ29udHJvbENlbnRlciB7CisgICAgICAgIGlkOiBlY2xp
cHNlQ2VudGVyCisgICAgICAgIGNhbk1hbmFnZTogU3lzdGVtUHJvcGVydGllcy5oYXNCcm93c2Vy
CisgICAgICAgIGNhbldha2U6IHRvb2xCYXIub25QY1ZpZXcKKyAgICAgICAgb25XYWtlUmVxdWVz
dGVkOiB7CisgICAgICAgICAgICBpZiAodG9vbEJhci5vblBjVmlldykgc3RhY2tWaWV3LmN1cnJl
bnRJdGVtLmNvbXB1dGVyTW9kZWwud2FrZUNvbXB1dGVyKHN0YWNrVmlldy5jdXJyZW50SXRlbS5j
dXJyZW50SW5kZXgpCisgICAgICAgIH0KKyAgICAgICAgb25OYXZpZ2F0ZVJlcXVlc3RlZDogewor
ICAgICAgICAgICAgaWYgKGRlc3RpbmF0aW9uID09PSAid2lmaSIgfHwgZGVzdGluYXRpb24gPT09
ICJidCIpIHsgY29ubmVjdGlvblBhbmVsLmtpbmQgPSBkZXN0aW5hdGlvbjsgY29ubmVjdGlvblBh
bmVsLm9wZW4oKSB9CisgICAgICAgICAgICBlbHNlIGlmIChkZXN0aW5hdGlvbiA9PT0gInNldHRp
bmdzIikgbmF2aWdhdGVUbygicXJjOi9ndWkvU2V0dGluZ3NWaWV3LnFtbCIsICJTZXR0aW5nc1Zp
ZXciKQorICAgICAgICAgICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJob3N0IikgeyBDcmlt
c29uU3RhdHVzLnNlbGVjdEhvc3QoZWNsaXBzZUNlbnRlci5ob3N0LmlkIHx8ICIiLCBlY2xpcHNl
Q2VudGVyLmhvc3QudXJsIHx8ICIiKTsgY3JpbXNvblBhbmVsLmtpbmQgPSAiaG9zdCI7IGNyaW1z
b25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJh
Ym91dCIpIHsgZWNsaXBzZUFib3V0LmluZm8gPSBTeXN0ZW1Db250cm9scy5zdGF0ZTsgZWNsaXBz
ZUFib3V0Lm9wZW4oKSB9CisgICAgICAgICAgICBlbHNlIGlmIChkZXN0aW5hdGlvbiA9PT0gIm1h
bmFnZW1lbnQiICYmIFN5c3RlbVByb3BlcnRpZXMuaGFzQnJvd3NlcikgU3lzdGVtUHJvcGVydGll
cy5vcGVuVXJsKGVjbGlwc2VDZW50ZXIuaG9zdC51cmwpCisgICAgICAgIH0KKyAgICB9CisKICAg
ICBoZWFkZXI6IFRvb2xCYXIgewogICAgICAgICBpZDogdG9vbEJhcgogICAgICAgICAvLyBSZWRl
c2lnbjogRVZFUlkgcmVkZXNpZ25lZCBsYXVuY2hlciBzY3JlZW4gKENvbXB1dGVycywgQXBwIGdy
aWQsIFNldHRpbmdzLCBIZWxwKQpAQCAtMzI1LDcgKzM2Miw4IEBAIEFwcGxpY2F0aW9uV2luZG93
IHsKICAgICAgICAgLy8gcmVkZXNpZ24gcmF0aGVyIHRoYW4gdGhlIGRlZmF1bHQgTWF0ZXJpYWwg
aW5kaWdvLCB3aGljaCByZWFkIGFzIGFuICJ1Z2x5IGJsdWUiIGhlYWRlcgogICAgICAgICAvLyBj
bGFzaGluZyB3aXRoIHRoZSBkYXJrIFVJIGJlbG93IGl0LiBIZWlnaHQgaXMgY29uc3RhbnQgb24g
dGhlIGhvbWUgc2NyZWVucyAobm8gcnVudGltZQogICAgICAgICAvLyBnZW9tZXRyeSBjaGFuZ2Up
IHNvIHRoZSBibGFjay1zY3JlZW4gZml4IGlzIHByZXNlcnZlZC4KLSAgICAgICAgYmFja2dyb3Vu
ZDogUmVjdGFuZ2xlIHsKKyAgICAgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgewor
ICAgICAgICAgICAgcmFkaXVzOjAKICAgICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy5iZ1dpbmRv
dwogICAgICAgICAgICAgUmVjdGFuZ2xlIHsKICAgICAgICAgICAgICAgICBhbmNob3JzLmJvdHRv
bTogcGFyZW50LmJvdHRvbQpAQCAtMzM4LDIwICszNzYsMTkgQEAgQXBwbGljYXRpb25XaW5kb3cg
ewogICAgICAgICAvLyBWSUJFTUlTIHdvcmRtYXJrIChkaWFtb25kICsgd29yZG1hcmspLCBzaG93
biBvbiB0aGUgQ29tcHV0ZXJzIHNjcmVlbiBpbiBwbGFjZSBvZiBhIHRpdGxlLAogICAgICAgICAv
LyBtYXRjaGluZyB0aGUgZGVzaWduIGhlYWRlci4gTGVmdC1hbGlnbmVkIGF0IHRoZSBIVE1MJ3Mg
NDBweCBwYWRkaW5nLgogICAgICAgICBSb3cgewotICAgICAgICAgICAgdmlzaWJsZTogdG9vbEJh
ci5vblBjVmlldworICAgICAgICAgICAgdmlzaWJsZTogdG9vbEJhci5vblBjVmlldyAmJiB0b29s
QmFyLndpZHRoID4gODIwCiAgICAgICAgICAgICBhbmNob3JzLmxlZnQ6IHBhcmVudC5sZWZ0CiAg
ICAgICAgICAgICBhbmNob3JzLmxlZnRNYXJnaW46IDQwCiAgICAgICAgICAgICBhbmNob3JzLnZl
cnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIKICAgICAgICAgICAgIHNwYWNpbmc6
IDExCi0gICAgICAgICAgICBSZWN0YW5nbGUgeworICAgICAgICAgICAgSW1hZ2UgewogICAgICAg
ICAgICAgICAgIGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlcgot
ICAgICAgICAgICAgICAgIHdpZHRoOiAxMzsgaGVpZ2h0OiAxMwotICAgICAgICAgICAgICAgIGNv
bG9yOiBWYlRva2Vucy5hY2NlbnQKLSAgICAgICAgICAgICAgICByb3RhdGlvbjogNDUKKyAgICAg
ICAgICAgICAgICB3aWR0aDogMjg7IGhlaWdodDogMjgKKyAgICAgICAgICAgICAgICBzb3VyY2U6
ICJxcmM6L3Jlcy9lY2xpcHNlLWljb24uc3ZnIgogICAgICAgICAgICAgfQogICAgICAgICAgICAg
VGV4dCB7CiAgICAgICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZl
cnRpY2FsQ2VudGVyCi0gICAgICAgICAgICAgICAgdGV4dDogIlZJQkVNSVMiCisgICAgICAgICAg
ICAgICAgdGV4dDogIkVDTElQU0UiCiAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9r
ZW5zLmZvbnREaXNwbGF5CiAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZvbnQuRXh0cmFC
b2xkCiAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IDIxCkBAIC0zNjUsNyArNDAyLDcg
QEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICAgICAgLy8gSGlkZGVuIG9uIENvbXB1dGVy
cyAodGhlIHdvcmRtYXJrIHN0YW5kcyBpbikgYW5kIG9uIHRoZSBBcHAgZ3JpZCAod2hpY2ggc2hv
d3MgYQogICAgICAgICAgICAgLy8gbGVmdC1hbGlnbmVkIGhvc3QgKyBzdGF0dXMgYmxvY2sgaW5z
dGVhZCkuIE9uIFNldHRpbmdzL0hlbHAgaXQgc2hvd3MgdGhlIHNjcmVlbiBuYW1lOwogICAgICAg
ICAgICAgLy8gdGhlIHN0cmVhbWluZyBzZWd1ZXMga2VlcCB0aGVpciBkZWZhdWx0IG9iamVjdE5h
bWUgdGl0bGUuCi0gICAgICAgICAgICB2aXNpYmxlOiAhdG9vbEJhci5vblBjVmlldyAmJiAhdG9v
bEJhci5vbkFwcFZpZXcgJiYgdG9vbEJhci53aWR0aCA+IDcwMAorICAgICAgICAgICAgdmlzaWJs
ZTogIXRvb2xCYXIub25QY1ZpZXcgJiYgIXRvb2xCYXIub25BcHBWaWV3ICYmIHRvb2xCYXIud2lk
dGggPiA4MjAKICAgICAgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50CiAgICAgICAgICAgICB0
ZXh0OiB0b29sQmFyLm9uU2V0dGluZ3MgPyBxc1RyKCJTZXR0aW5ncyIpCiAgICAgICAgICAgICAg
ICAgOiB0b29sQmFyLm9uSGVscCA/IHFzVHIoIkhlbHAiKQpAQCAtNDg3LDYgKzUyNCw1NCBAQCBB
cHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgfQogCisg
ICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogbmV0
d29ya1N0YXR1c0J1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9j
cmltc29uLW5ldHdvcmsuc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNU
cigiV2ktRmkgc2V0dGluZ3MiKQorICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92
ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiTmV0d29yazogJTEiKS5h
cmcoQ3JpbXNvblN0YXR1cy5sb2NhbC5uZXR3b3JrIHx8IHFzVHIoIlVuYXZhaWxhYmxlIikpCisg
ICAgICAgICAgICAgICAgb25DbGlja2VkOiB7IGNvbm5lY3Rpb25QYW5lbC5raW5kID0gIndpZmki
OyBjb25uZWN0aW9uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAgICAgICBLZXlzLm9uRG93blBy
ZXNzZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3Vz
KQorICAgICAgICAgICAgICAgIFJlY3RhbmdsZSB7CisgICAgICAgICAgICAgICAgICAgIGFuY2hv
cnMucmlnaHQ6IHBhcmVudC5yaWdodDsgYW5jaG9ycy5ib3R0b206IHBhcmVudC5ib3R0b207IGFu
Y2hvcnMubWFyZ2luczogNQorICAgICAgICAgICAgICAgICAgICB3aWR0aDogODsgaGVpZ2h0OiA4
OyByYWRpdXM6IDQKKyAgICAgICAgICAgICAgICAgICAgY29sb3I6IENyaW1zb25TdGF0dXMubG9j
YWwuY29ubmVjdGVkID8gVmJUb2tlbnMuc3RhdHVzT25saW5lIDogVmJUb2tlbnMuc3RhdHVzT2Zm
bGluZQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIE5hdmln
YWJsZVRvb2xCdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBibHVldG9vdGhTZXR0aW5nc0J1
dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWJsdWV0
b290aC5zdmciCisgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJCbHVldG9v
dGggc2V0dGluZ3MiKQorICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAor
ICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiUGFpciBjb250cm9sbGVycyBhbmQg
aGVhZHBob25lcyIpCisgICAgICAgICAgICAgICAgb25DbGlja2VkOiB7IGNvbm5lY3Rpb25QYW5l
bC5raW5kID0gImJ0IjsgY29ubmVjdGlvblBhbmVsLm9wZW4oKSB9CisgICAgICAgICAgICAgICAg
S2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1ZpZXcuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1
cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xC
dXR0b24geworICAgICAgICAgICAgICAgIGlkOiBiYXR0ZXJ5U3RhdHVzQnV0dG9uCisgICAgICAg
ICAgICAgICAgaWNvblNvdXJjZTogInFyYzovcmVzL2NyaW1zb24tYmF0dGVyeS5zdmciCisgICAg
ICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJCYXR0ZXJ5IHN0YXR1cyIpCisgICAg
ICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCisgICAgICAgICAgICAgICAgVG9v
bFRpcC50ZXh0OiBDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50ID49IDAgPyBxc1Ry
KCJCYXR0ZXJ5OiAlMSUg4oCiICUyIikuYXJnKENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVBl
cmNlbnQpLmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlTdGF0ZSkgOiBxc1RyKCJCYXR0
ZXJ5IHVuYXZhaWxhYmxlIikKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsgY3JpbXNvblBh
bmVsLmtpbmQgPSAiYmF0dGVyeSI7IGNyaW1zb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAg
ICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZl
Rm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVU
b29sQnV0dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogaG9zdEhhcmR3YXJlQnV0dG9uCisgICAg
ICAgICAgICAgICAgaWNvblNvdXJjZTogInFyYzovcmVzL2NyaW1zb24taG9zdC5zdmciCisgICAg
ICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJWaWJlcG9sbG8gaG9zdCBoYXJkd2Fy
ZSBzdGF0cyIpCisgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCisgICAg
ICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJIb3N0IENQVSwgUkFNLCBHUFUgYW5kIHRl
bXBlcmF0dXJlcyIpCisgICAgICAgICAgICAgICAgb25DbGlja2VkOiB7CisgICAgICAgICAgICAg
ICAgICAgIHZhciBpdGVtID0gc3RhY2tWaWV3LmN1cnJlbnRJdGVtCisgICAgICAgICAgICAgICAg
ICAgIHZhciBob3N0ID0gdG9vbEJhci5vbkFwcFZpZXcgPyBpdGVtLmNyaW1zb25Ib3N0CisgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgIDogKHRvb2xCYXIub25QY1ZpZXcgPyBpdGVtLmNvbXB1
dGVyTW9kZWwuY3JpbXNvbkhvc3QoaXRlbS5jdXJyZW50SW5kZXgpIDoge30pCisgICAgICAgICAg
ICAgICAgICAgIENyaW1zb25TdGF0dXMuc2VsZWN0SG9zdChob3N0LmlkIHx8ICIiLCBob3N0LnVy
bCB8fCAiIikKKyAgICAgICAgICAgICAgICAgICAgY3JpbXNvblBhbmVsLmtpbmQgPSAiaG9zdCI7
IGNyaW1zb25QYW5lbC5vcGVuKCkKKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAg
S2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1ZpZXcuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1
cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAgIH0KKwogICAgICAgICAgICAgTmF2aWdhYmxlVG9v
bEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAgaWQ6IGRpc2NvcmRCdXR0b24KICAgICAgICAgICAg
ICAgICB2aXNpYmxlOiBmYWxzZSAvLyBUZW1wb3JhcmlseSBkaXNhYmxlZCBmb3IgVmliZW1pcwpA
QCAtNTY0LDcgKzY0OSw3IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgICAgICAgICAv
LyBhbiBpbnN0YWxsIGZhaWx1cmUgZmFsbHMgYmFjayB0byB0aGUgcmVsZWFzZSBwYWdlIG9uIGl0
cyBvd24uCiAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBBdXRvVXBkYXRlQ2hlY2tlci5p
bnN0YWxsaW5nCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA/IHFzVHIoIkRvd25sb2Fk
aW5nIHVwZGF0ZeKApiIpCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IHFzVHIoIlVw
ZGF0ZSBhdmFpbGFibGUgZm9yIFZpYmVtaXM6IFZlcnNpb24gJTEg4oCUIHRhcCB0byBpbnN0YWxs
IikuYXJnKEF1dG9VcGRhdGVDaGVja2VyLmF2YWlsYWJsZVZlcnNpb24pCisgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICA6IHFzVHIoIlVwZGF0ZSBhdmFpbGFibGUgZm9yIEVjbGlwc2U6IFZl
cnNpb24gJTEg4oCUIHRhcCB0byBpbnN0YWxsIikuYXJnKEF1dG9VcGRhdGVDaGVja2VyLmF2YWls
YWJsZVZlcnNpb24pCiAKICAgICAgICAgICAgICAgICAvLyBTdHJpY3RseS1uZXdlciBidWlsZHMg
b25seSAoYSBjaGFubmVsLXN3aXRjaCBkb3duZ3JhZGUgb2ZmZXIKICAgICAgICAgICAgICAgICAv
LyBsaXZlcyBpbiBTZXR0aW5ncywgbm90IG9uIHRoZSB0b29sYmFyKS4KQEAgLTY0Niw2ICs3MzEs
MjEgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAg
IH0KIAorICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAg
aWQ6IGVjbGlwc2VDZW50ZXJCdXR0b24KKyAgICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJj
Oi9yZXMvZWNsaXBzZS1jb250cm9scy5zdmciCisgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5u
YW1lOiBxc1RyKCJFY2xpcHNlIGNvbnRyb2wgY2VudGVyIikKKyAgICAgICAgICAgICAgICBUb29s
VGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIo
IkNvbnRyb2wgY2VudGVyIOKAoiBDdHJsK1NoaWZ0K0MiKQorICAgICAgICAgICAgICAgIG9uQ2xp
Y2tlZDogeworICAgICAgICAgICAgICAgICAgICB2YXIgaXRlbSA9IHN0YWNrVmlldy5jdXJyZW50
SXRlbQorICAgICAgICAgICAgICAgICAgICBlY2xpcHNlQ2VudGVyLmhvc3QgPSB0b29sQmFyLm9u
QXBwVmlldyA/IGl0ZW0uY3JpbXNvbkhvc3QgOiAodG9vbEJhci5vblBjVmlldyA/IGl0ZW0uY29t
cHV0ZXJNb2RlbC5jcmltc29uSG9zdChpdGVtLmN1cnJlbnRJbmRleCkgOiB7fSkKKyAgICAgICAg
ICAgICAgICAgICAgZWNsaXBzZUNlbnRlci5vcGVuKCkKKyAgICAgICAgICAgICAgICB9CisgICAg
ICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1ZpZXcuY3VycmVudEl0ZW0uZm9y
Y2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAgICAgICBTaG9ydGN1dCB7IHNl
cXVlbmNlOiAiQ3RybCtTaGlmdCtDIjsgZW5hYmxlZDogdG9vbEJhci5vblBjVmlldyB8fCB0b29s
QmFyLm9uQXBwVmlldzsgb25BY3RpdmF0ZWQ6IGVjbGlwc2VDZW50ZXJCdXR0b24uY2xpY2tlZCgp
IH0KKyAgICAgICAgICAgIH0KKwogICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CiAg
ICAgICAgICAgICAgICAgaWQ6IHNldHRpbmdzQnV0dG9uCiAKQEAgLTY3Myw3ICs3NzMsNyBAQCBB
cHBsaWNhdGlvbldpbmRvdyB7CiAKICAgICBFcnJvck1lc3NhZ2VEaWFsb2cgewogICAgICAgICBp
ZDogbm9Id0RlY29kZXJEaWFsb2cKLSAgICAgICAgdGV4dDogcXNUcigiTm8gZnVuY3Rpb25pbmcg
aGFyZHdhcmUgYWNjZWxlcmF0ZWQgdmlkZW8gZGVjb2RlciB3YXMgZGV0ZWN0ZWQgYnkgVmliZW1p
cy4gIiArCisgICAgICAgIHRleHQ6IHFzVHIoIk5vIGZ1bmN0aW9uaW5nIGhhcmR3YXJlIGFjY2Vs
ZXJhdGVkIHZpZGVvIGRlY29kZXIgd2FzIGRldGVjdGVkIGJ5IEVjbGlwc2UuICIgKwogICAgICAg
ICAgICAgICAgICAgICJZb3VyIHN0cmVhbWluZyBwZXJmb3JtYW5jZSBtYXkgYmUgc2V2ZXJlbHkg
ZGVncmFkZWQgaW4gdGhpcyBjb25maWd1cmF0aW9uLiIpCiAgICAgICAgIGhlbHBUZXh0OiBxc1Ry
KCJDbGljayB0aGUgSGVscCBidXR0b24gZm9yIG1vcmUgaW5mb3JtYXRpb24gb24gc29sdmluZyB0
aGlzIHByb2JsZW0uIikKICAgICAgICAgaGVscFVybDogImh0dHBzOi8vZ2l0aHViLmNvbS9uYXZ5
YXMzMjEvdmliZW1pcyIKQEAgLTY5MCw3ICs3OTAsNyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAg
ICAgTmF2aWdhYmxlTWVzc2FnZURpYWxvZyB7CiAgICAgICAgIGlkOiB3b3c2NERpYWxvZwogICAg
ICAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5PayB8IERpYWxvZy5DYW5jZWwKLSAgICAgICAg
dGV4dDogcXNUcigiVGhpcyB2ZXJzaW9uIG9mIFZpYmVtaXMgaXNuJ3Qgb3B0aW1pemVkIGZvciB5
b3VyIFBDLiBQbGVhc2UgZG93bmxvYWQgdGhlICclMScgdmVyc2lvbiBvZiBWaWJlbWlzIGZvciB0
aGUgYmVzdCBzdHJlYW1pbmcgcGVyZm9ybWFuY2UuIikuYXJnKFN5c3RlbVByb3BlcnRpZXMuZnJp
ZW5kbHlOYXRpdmVBcmNoTmFtZSkKKyAgICAgICAgdGV4dDogcXNUcigiVGhpcyB2ZXJzaW9uIG9m
IEVjbGlwc2UgaXNuJ3Qgb3B0aW1pemVkIGZvciB5b3VyIFBDLiBQbGVhc2UgZG93bmxvYWQgdGhl
ICclMScgdmVyc2lvbiBvZiBFY2xpcHNlIGZvciB0aGUgYmVzdCBzdHJlYW1pbmcgcGVyZm9ybWFu
Y2UuIikuYXJnKFN5c3RlbVByb3BlcnRpZXMuZnJpZW5kbHlOYXRpdmVBcmNoTmFtZSkKICAgICAg
ICAgb25BY2NlcHRlZDogewogICAgICAgICAgICAgU3lzdGVtUHJvcGVydGllcy5vcGVuVXJsKCJo
dHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3ZpYmVtaXMvcmVsZWFzZXMiKTsKICAgICAgICAg
fQpAQCAtNjk5LDcgKzc5OSw3IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICBFcnJvck1lc3Nh
Z2VEaWFsb2cgewogICAgICAgICBpZDogdW5tYXBwZWRHYW1lcGFkRGlhbG9nCiAgICAgICAgIHBy
b3BlcnR5IHN0cmluZyB1bm1hcHBlZEdhbWVwYWRzIDogIiIKLSAgICAgICAgdGV4dDogcXNUcigi
VmliZW1pcyBkZXRlY3RlZCBnYW1lcGFkcyB3aXRob3V0IGEgbWFwcGluZzoiKSArICJcbiIgKyB1
bm1hcHBlZEdhbWVwYWRzCisgICAgICAgIHRleHQ6IHFzVHIoIkVjbGlwc2UgZGV0ZWN0ZWQgZ2Ft
ZXBhZHMgd2l0aG91dCBhIG1hcHBpbmc6IikgKyAiXG4iICsgdW5tYXBwZWRHYW1lcGFkcwogICAg
ICAgICBoZWxwVGV4dFNlcGFyYXRvcjogIlxuXG4iCiAgICAgICAgIGhlbHBUZXh0OiBxc1RyKCJD
bGljayB0aGUgSGVscCBidXR0b24gZm9yIGluZm9ybWF0aW9uIG9uIGhvdyB0byBtYXAgeW91ciBn
YW1lcGFkcy4iKQogICAgICAgICBoZWxwVXJsOiAiaHR0cHM6Ly9naXRodWIuY29tL25hdnlhczMy
MS92aWJlbWlzIgpkaWZmIC0tZ2l0IGEvYXBwL21haW4uY3BwIGIvYXBwL21haW4uY3BwCmluZGV4
IDI5MjIyNzcuLjNlYzk0ZGIgMTAwNjQ0Ci0tLSBhL2FwcC9tYWluLmNwcAorKysgYi9hcHAvbWFp
bi5jcHAKQEAgLTg2OSw2ICs4NjksNyBAQCBpbnQgbWFpbihpbnQgYXJnYywgY2hhciAqYXJndltd
KQogICAgIH0NCiANCiAgICAgUUd1aUFwcGxpY2F0aW9uIGFwcChhcmdjLCBhcmd2KTsNCisgICAg
UUd1aUFwcGxpY2F0aW9uOjpzZXRBcHBsaWNhdGlvbkRpc3BsYXlOYW1lKCJFY2xpcHNlIik7CiAN
CiAgICAgLy8gVmliZW1pczogdGhlIFF0IFF1aWNrIENvbnRyb2xzIE1hdGVyaWFsIHN0eWxlIHJl
bmRlcnMgYnV0dG9uIHRleHQgaW4gQUxMIENBUFMgYnkgZGVmYXVsdA0KICAgICAvLyAoZS5nLiB0
aGUgYml0cmF0ZSAiVVNFIERFRkFVTFQgKDMwIE1CUFMpIiBidXR0b24pLCB3aGljaCBsb29rcyBv
ZmYuIEZvcmNlIG1peGVkIGNhc2UgZm9yIHRoZQ0KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRv
cy9jcmltc29uZ3JhcGhzLmggYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbmdyYXBocy5oCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmNkY2MzYTAKLS0tIC9kZXYvbnVsbAorKysg
Yi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbmdyYXBocy5oCkBAIC0wLDAgKzEsNjMgQEAKKyNwcmFn
bWEgb25jZQorI2luY2x1ZGUgPFFNYXA+CisjaW5jbHVkZSA8UVZlY3Rvcj4KKyNpbmNsdWRlIDxR
VmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRUmVndWxhckV4cHJlc3Npb24+CisjaW5jbHVkZSA8UVBh
aW50ZXI+CisjaW5jbHVkZSA8UVBhaW50ZXJQYXRoPgorI2luY2x1ZGUgPFFGb250PgorI2luY2x1
ZGUgPFF0TWF0aD4KKyNpbmNsdWRlIDxsaW1pdHM+CisjaW5jbHVkZSAib3ZlcmxheXN0eWxlLmgi
CituYW1lc3BhY2UgQ3JpbXNvbkdyYXBocyB7Cit1c2luZyBIaXN0b3J5PVFNYXA8UVN0cmluZyxR
VmVjdG9yPGRvdWJsZT4+OworaW5saW5lIGRvdWJsZSBtaXNzaW5nKCkgeyByZXR1cm4gc3RkOjpu
dW1lcmljX2xpbWl0czxkb3VibGU+OjpxdWlldF9OYU4oKTsgfQoraW5saW5lIFFNYXA8UVN0cmlu
Zyxkb3VibGU+IHZhbHVlcyhjb25zdCBRU3RyaW5nJiB0ZXh0LGJvb2wgbG9jYWwsY29uc3QgUVZh
cmlhbnRNYXAmIGhhcmR3YXJlKSB7CisgICAgUU1hcDxRU3RyaW5nLGRvdWJsZT4gcmVzdWx0Owor
ICAgIGF1dG8gdGFrZT1bJl0oY29uc3QgUVN0cmluZyYga2V5LGNvbnN0IFFTdHJpbmcmIHNvdXJj
ZSkgeworICAgICAgICBib29sIG9rPWZhbHNlOworICAgICAgICBjb25zdCBhdXRvIHZhbHVlPWhh
cmR3YXJlLnZhbHVlKHNvdXJjZSk7CisgICAgICAgIGRvdWJsZSBudW1iZXI9dmFsdWUudG9Eb3Vi
bGUoJm9rKTsKKyAgICAgICAgcmVzdWx0W2tleV09IXZhbHVlLmlzTnVsbCgpJiZvayYmcUlzRmlu
aXRlKG51bWJlcikmJm51bWJlcj49MD9udW1iZXI6bWlzc2luZygpOworICAgIH07CisgICAgdGFr
ZSgiTG9jYWwgQ1BVIiwiY3B1UGVyY2VudCIpO3Rha2UoIkxvY2FsIFJBTSIsIm1lbW9yeVVzZWRH
aUIiKTsKKyAgICBpZihsb2NhbCkge3Rha2UoIlRlbXBlcmF0dXJlIiwidGVtcGVyYXR1cmVDIik7
dGFrZSgiRG93bmxvYWQiLCJyZWNlaXZlTWlCIik7fQorICAgIGVsc2UgeworICAgICAgICBhdXRv
IGZwcz1RUmVndWxhckV4cHJlc3Npb24oIlJlbmRlcmluZyBmcmFtZSByYXRlOiAoWzAtOV0rKD86
XFwuWzAtOV0rKT8pIEZQUyIpLm1hdGNoKHRleHQpOworICAgICAgICBpZighZnBzLmhhc01hdGNo
KCkpIGZwcz1RUmVndWxhckV4cHJlc3Npb24oIl4oWzAtOV0rKD86XFwuWzAtOV0rKT8pIGZwcyIs
UVJlZ3VsYXJFeHByZXNzaW9uOjpDYXNlSW5zZW5zaXRpdmVPcHRpb24pLm1hdGNoKHRleHQpOwor
ICAgICAgICByZXN1bHRbIkZQUyJdPWZwcy5oYXNNYXRjaCgpP2Zwcy5jYXB0dXJlZCgxKS50b0Rv
dWJsZSgpOm1pc3NpbmcoKTsKKyAgICAgICAgYXV0byBsYXRlbmN5PVFSZWd1bGFyRXhwcmVzc2lv
bigiQXZlcmFnZSBuZXR3b3JrIGxhdGVuY3k6IChbMC05XSsoPzpcXC5bMC05XSspPykiKS5tYXRj
aCh0ZXh0KTsKKyAgICAgICAgaWYoIWxhdGVuY3kuaGFzTWF0Y2goKSkgbGF0ZW5jeT1RUmVndWxh
ckV4cHJlc3Npb24oIlxcYm5ldCAoWzAtOV0rKD86XFwuWzAtOV0rKT8pIG1zIikubWF0Y2godGV4
dCk7CisgICAgICAgIHJlc3VsdFsiTmV0d29yayBsYXRlbmN5Il09bGF0ZW5jeS5oYXNNYXRjaCgp
P2xhdGVuY3kuY2FwdHVyZWQoMSkudG9Eb3VibGUoKTptaXNzaW5nKCk7CisgICAgfQorICAgIHJl
dHVybiByZXN1bHQ7Cit9CitpbmxpbmUgdm9pZCBwdXNoKEhpc3RvcnkmIGhpc3RvcnksY29uc3Qg
UU1hcDxRU3RyaW5nLGRvdWJsZT4mIHZhbHVlcykgeworICAgIGZvcihhdXRvIGk9dmFsdWVzLmNi
ZWdpbigpO2khPXZhbHVlcy5jZW5kKCk7KytpKSB7YXV0byYgc2VyaWVzPWhpc3RvcnlbaS5rZXko
KV07c2VyaWVzLmFwcGVuZChxSXNGaW5pdGUoaS52YWx1ZSgpKSYmaS52YWx1ZSgpPj0wP2kudmFs
dWUoKTptaXNzaW5nKCkpO3doaWxlKHNlcmllcy5zaXplKCk+NjApc2VyaWVzLnJlbW92ZUZpcnN0
KCk7fQorfQoraW5saW5lIFFTdHJpbmdMaXN0IGtleXMoYm9vbCBsb2NhbCkge3JldHVybiBsb2Nh
bD9RU3RyaW5nTGlzdHsiTG9jYWwgQ1BVIiwiTG9jYWwgUkFNIiwiVGVtcGVyYXR1cmUiLCJEb3du
bG9hZCJ9OlFTdHJpbmdMaXN0eyJGUFMiLCJOZXR3b3JrIGxhdGVuY3kiLCJMb2NhbCBDUFUiLCJM
b2NhbCBSQU0ifTt9CitpbmxpbmUgdm9pZCBwYWludChRSW1hZ2UmIGltYWdlLGludCB0b3AsaW50
IGZvbnRTaXplLGludCBhY2NlbnRJbmRleCxjb25zdCBIaXN0b3J5JiBoaXN0b3J5LGJvb2wgbG9j
YWwpIHsKKyAgICBRUGFpbnRlciBwKCZpbWFnZSk7cC5zZXRSZW5kZXJIaW50KFFQYWludGVyOjpB
bnRpYWxpYXNpbmcpO1FGb250IGZvbnQoIkRlamFWdSBTYW5zIik7Zm9udC5zZXRQaXhlbFNpemUo
Zm9udFNpemUpO3Auc2V0Rm9udChmb250KTsKKyAgICBjb25zdCBpbnQgcm93SGVpZ2h0PWZvbnRT
aXplKzIyO2ludCByb3c9MDsKKyAgICBmb3IoY29uc3QgYXV0byYga2V5OmtleXMobG9jYWwpKSB7
CisgICAgICAgIGNvbnN0IGF1dG8gc2VyaWVzPWhpc3RvcnkudmFsdWUoa2V5KTtkb3VibGUgY3Vy
cmVudD1zZXJpZXMuaXNFbXB0eSgpP21pc3NpbmcoKTpzZXJpZXMubGFzdCgpOworICAgICAgICBR
U3RyaW5nIHVuaXQ9a2V5PT0iTG9jYWwgQ1BVIj8iJSI6a2V5PT0iTG9jYWwgUkFNIj8iIEdpQiI6
a2V5PT0iVGVtcGVyYXR1cmUiPyIgwrBDIjprZXk9PSJEb3dubG9hZCI/IiBNaUIvcyI6a2V5PT0i
TmV0d29yayBsYXRlbmN5Ij8iIG1zIjoiIjsKKyAgICAgICAgUVN0cmluZyB2YWx1ZT1xSXNGaW5p
dGUoY3VycmVudCk/UVN0cmluZzo6bnVtYmVyKGN1cnJlbnQsJ2YnLGtleT09IkZQUyI/MDoxKSt1
bml0OlFTdHJpbmcoIlVuYXZhaWxhYmxlIik7CisgICAgICAgIGNvbnN0IGludCB5PXRvcCtyb3cr
Kypyb3dIZWlnaHQ7CisgICAgICAgIHAuc2V0UGVuKFFDb2xvcigiIzk4QTFBQiIpKTtwLmRyYXdU
ZXh0KFFSZWN0KDE2LHksaW1hZ2Uud2lkdGgoKS0zMixyb3dIZWlnaHQpLFF0OjpBbGlnblZDZW50
ZXIsa2V5KTsKKyAgICAgICAgY29uc3QgaW50IGdyYXBoV2lkdGg9OTY7CisgICAgICAgIHAuc2V0
UGVuKFFDb2xvcigiI0VDRUVGMSIpKTtwLmRyYXdUZXh0KFFSZWN0KDE4NSx5LGltYWdlLndpZHRo
KCktZ3JhcGhXaWR0aC0yMTUscm93SGVpZ2h0KSxRdDo6QWxpZ25SaWdodHxRdDo6QWxpZ25WQ2Vu
dGVyLHZhbHVlKTsKKyAgICAgICAgUVJlY3RGIGJvdW5kcyhpbWFnZS53aWR0aCgpLWdyYXBoV2lk
dGgtMTQseSs3LGdyYXBoV2lkdGgscm93SGVpZ2h0LTE0KTsKKyAgICAgICAgZG91YmxlIGhpZ2g9
a2V5PT0iTG9jYWwgQ1BVIj8xMDA6MTsKKyAgICAgICAgaWYoa2V5IT0iTG9jYWwgQ1BVIilmb3Io
ZG91YmxlIG46c2VyaWVzKWlmKHFJc0Zpbml0ZShuKSloaWdoPXFNYXgoaGlnaCxuKjEuMTUpOwor
ICAgICAgICBRUGFpbnRlclBhdGggcGF0aDtib29sIHN0YXJ0ZWQ9ZmFsc2U7CisgICAgICAgIGZv
cihpbnQgaT0wO2k8c2VyaWVzLnNpemUoKTtpKyspIHtkb3VibGUgdj1zZXJpZXNbaV07aWYoIXFJ
c0Zpbml0ZSh2KSl7c3RhcnRlZD1mYWxzZTtjb250aW51ZTt9CisgICAgICAgICAgICBRUG9pbnRG
IHBvaW50KGJvdW5kcy5sZWZ0KCkrYm91bmRzLndpZHRoKCkqKDYwLXNlcmllcy5zaXplKCkraSkv
NTkuMCxib3VuZHMuYm90dG9tKCktYm91bmRzLmhlaWdodCgpKnFCb3VuZCgwLjAsdi9oaWdoLDEu
MCkpOworICAgICAgICAgICAgaWYoIXN0YXJ0ZWQpcGF0aC5tb3ZlVG8ocG9pbnQpO2Vsc2UgcGF0
aC5saW5lVG8ocG9pbnQpO3N0YXJ0ZWQ9dHJ1ZTsKKyAgICAgICAgfQorICAgICAgICBwLnNldFBl
bihRUGVuKEVjbGlwc2VPdmVybGF5U3R5bGU6OmFjY2VudChhY2NlbnRJbmRleCksMS41KSk7cC5k
cmF3UGF0aChwYXRoKTsKKyAgICAgICAgaWYocUlzRmluaXRlKGN1cnJlbnQpKSB7cC5zZXRCcnVz
aChFY2xpcHNlT3ZlcmxheVN0eWxlOjphY2NlbnQoYWNjZW50SW5kZXgpKTtwLmRyYXdFbGxpcHNl
KFFQb2ludEYoYm91bmRzLnJpZ2h0KCksYm91bmRzLmJvdHRvbSgpLWJvdW5kcy5oZWlnaHQoKSpx
Qm91bmQoMC4wLGN1cnJlbnQvaGlnaCwxLjApKSwxLjUsMS41KTt9CisgICAgICAgIHAuc2V0UGVu
KFFDb2xvcigyNTUsMjU1LDI1NSwxNCkpO3AuZHJhd0xpbmUoMTYseStyb3dIZWlnaHQtMSxpbWFn
ZS53aWR0aCgpLTE2LHkrcm93SGVpZ2h0LTEpOworICAgIH0KK30KK30KZGlmZiAtLWdpdCBhL2Fw
cC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29u
c3RhdHVzLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5kYWZjYTJlCi0t
LSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL2NyaW1zb25zdGF0dXMuY3BwCkBAIC0w
LDAgKzEsMjIyIEBACisjaW5jbHVkZSAiY3JpbXNvbnN0YXR1cy5oIgorI2luY2x1ZGUgPFFEYXRl
VGltZT4KKyNpbmNsdWRlIDxRRGlyPgorI2luY2x1ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFKc29u
RG9jdW1lbnQ+CisjaW5jbHVkZSA8UUpzb25PYmplY3Q+CisjaW5jbHVkZSA8UU5ldHdvcmtJbnRl
cmZhY2U+CisjaW5jbHVkZSA8UU5ldHdvcmtSZXF1ZXN0PgorI2luY2x1ZGUgPFFTYXZlRmlsZT4K
KyNpbmNsdWRlIDxRU3NsQ2VydGlmaWNhdGU+CisjaW5jbHVkZSA8UVNzbEVycm9yPgorI2luY2x1
ZGUgPFFTdGFuZGFyZFBhdGhzPgorI2luY2x1ZGUgPFFDcnlwdG9ncmFwaGljSGFzaD4KKyNpbmNs
dWRlIDxRVXJsPgorI2luY2x1ZGUgPGNtYXRoPgorI2luY2x1ZGUgPFFRbWxFbmdpbmU+CisjaW5j
bHVkZSA8UUNvcmVBcHBsaWNhdGlvbj4KKyNpbmNsdWRlIDxtZW1vcnk+CisjaW5jbHVkZSA8UVJl
Z3VsYXJFeHByZXNzaW9uPgorI2luY2x1ZGUgPFFGaWxlSW5mbz4KKyNpbmNsdWRlIDxRU3NsQ29u
ZmlndXJhdGlvbj4KKworbmFtZXNwYWNlIHsKK1FTdHJpbmcgcmVhZChjb25zdCBRU3RyaW5nJiBw
YXRoKSB7CisgICAgUUZpbGUgZihwYXRoKTsgcmV0dXJuIGYub3BlbihRSU9EZXZpY2U6OlJlYWRP
bmx5KSA/IFFTdHJpbmc6OmZyb21VdGY4KGYucmVhZEFsbCgpKS50cmltbWVkKCkgOiBRU3RyaW5n
KCk7Cit9Citjb25zdCBhdXRvIHVzZXJPbmx5ID0gUUZpbGVEZXZpY2U6OlJlYWRPd25lciB8IFFG
aWxlRGV2aWNlOjpXcml0ZU93bmVyOworfQorQ3JpbXNvblN0YXR1czo6Q3JpbXNvblN0YXR1cyhR
T2JqZWN0KiBwYXJlbnQpIDogUU9iamVjdChwYXJlbnQpIHsKKyAgICBjb25uZWN0KCZtX2xvY2Fs
VGltZXIsICZRVGltZXI6OnRpbWVvdXQsIHRoaXMsICZDcmltc29uU3RhdHVzOjpyZWZyZXNoTG9j
YWwpOworICAgIGNvbm5lY3QoJm1fc3RhdHNUaW1lciwgJlFUaW1lcjo6dGltZW91dCwgdGhpcywg
JkNyaW1zb25TdGF0dXM6OnJlZnJlc2gpOworICAgIGNvbm5lY3QoJm1fd2lmaSwgJlFQcm9jZXNz
OjpmaW5pc2hlZCwgdGhpcywgW3RoaXNdKGludCBleGl0LCBRUHJvY2Vzczo6RXhpdFN0YXR1cykg
eworICAgICAgICBpZiAoZXhpdCA9PSAwKSB7CisgICAgICAgICAgICBjb25zdCBhdXRvIGxpbmVz
ID0gUVN0cmluZzo6ZnJvbVV0ZjgobV93aWZpLnJlYWRBbGxTdGFuZGFyZE91dHB1dCgpKS5zcGxp
dCgnXG4nKTsKKyAgICAgICAgICAgIGZvciAoY29uc3QgYXV0byYgbGluZSA6IGxpbmVzKSB7Cisg
ICAgICAgICAgICAgICAgaWYgKCFsaW5lLnN0YXJ0c1dpdGgoInllczoiKSkgY29udGludWU7Cisg
ICAgICAgICAgICAgICAgaW50IHNlcGFyYXRvciA9IGxpbmUuaW5kZXhPZignOicsIDQpOyBib29s
IG9rID0gZmFsc2U7CisgICAgICAgICAgICAgICAgaW50IHNpZ25hbCA9IGxpbmUubWlkKDQsIHNl
cGFyYXRvciAtIDQpLnRvSW50KCZvayk7CisgICAgICAgICAgICAgICAgaWYgKG9rICYmIHNpZ25h
bCA+PSAwICYmIHNpZ25hbCA8PSAxMDApIG1fbG9jYWxbIndpZmlTaWduYWwiXSA9IHNpZ25hbDsK
KyAgICAgICAgICAgICAgICBpZiAoc2VwYXJhdG9yID49IDApIG1fbG9jYWxbIm5ldHdvcmsiXSA9
IHRyKCJXaS1GaTogJTEiKS5hcmcobGluZS5taWQoc2VwYXJhdG9yICsgMSkpOworICAgICAgICAg
ICAgICAgIGJyZWFrOworICAgICAgICAgICAgfQorICAgICAgICAgICAgZW1pdCBsb2NhbENoYW5n
ZWQoKTsKKyAgICAgICAgfQorICAgIH0pOworICAgIG1fbG9jYWxUaW1lci5zdGFydCgxMDAwMCk7
IG1fc3RhdHNUaW1lci5zZXRJbnRlcnZhbCgyMDAwKTsgcmVmcmVzaExvY2FsKCk7Cit9CitDcmlt
c29uU3RhdHVzOjp+Q3JpbXNvblN0YXR1cygpIHsKKyAgICBtX3N0YXRzVGltZXIuc3RvcCgpOyBt
X2xvY2FsVGltZXIuc3RvcCgpOyBjYW5jZWwoKTsKKyAgICBpZiAobV93aWZpLnN0YXRlKCkgIT0g
UVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIHsgbV93aWZpLmtpbGwoKTsgbV93aWZpLndhaXRGb3JGaW5p
c2hlZCg1MDApOyB9Cit9CitRU3RyaW5nIENyaW1zb25TdGF0dXM6OmNvbmZpZ0ZpbGUoKSBjb25z
dCB7CisgICAgcmV0dXJuIFFTdGFuZGFyZFBhdGhzOjp3cml0YWJsZUxvY2F0aW9uKFFTdGFuZGFy
ZFBhdGhzOjpBcHBDb25maWdMb2NhdGlvbikgKyAiL2NyaW1zb24taG9zdHMuanNvbiI7Cit9CitR
U3RyaW5nIENyaW1zb25TdGF0dXM6Om5vcm1hbGl6ZWRQaW4oUVN0cmluZyBwaW4pIHsKKyAgICBw
aW4ucmVtb3ZlKCc6Jyk7IHBpbi5yZW1vdmUoJyAnKTsgcmV0dXJuIHBpbi50b0xvd2VyKCk7Cit9
Citib29sIENyaW1zb25TdGF0dXM6OnZhbGlkRW5kcG9pbnQoY29uc3QgUVN0cmluZyYgdmFsdWUp
IHsKKyAgICBRVXJsIHUodmFsdWUsIFFVcmw6OlN0cmljdE1vZGUpOworICAgIHJldHVybiB1Lmlz
VmFsaWQoKSAmJiB1LnNjaGVtZSgpID09ICJodHRwcyIgJiYgIXUuaG9zdCgpLmlzRW1wdHkoKSAm
JgorICAgICAgICB1LnVzZXJJbmZvKCkuaXNFbXB0eSgpICYmIHUucXVlcnkoKS5pc0VtcHR5KCkg
JiYgdS5mcmFnbWVudCgpLmlzRW1wdHkoKSAmJgorICAgICAgICAodS5wYXRoKCkuaXNFbXB0eSgp
IHx8IHUucGF0aCgpID09ICIvIikgJiYgdS5wb3J0KDQ3OTkwKSA+IDA7Cit9Cit2b2lkIENyaW1z
b25TdGF0dXM6OmNhbmNlbCgpIHsKKyAgICBpZiAobV9yZXBseSkgeyBkaXNjb25uZWN0KG1fcmVw
bHksIG51bGxwdHIsIHRoaXMsIG51bGxwdHIpOyBtX3JlcGx5LT5hYm9ydCgpOyBtX3JlcGx5LT5k
ZWxldGVMYXRlcigpOyBtX3JlcGx5ID0gbnVsbHB0cjsgfQorfQordm9pZCBDcmltc29uU3RhdHVz
OjpzZWxlY3RIb3N0KFFTdHJpbmcgaWQsIFFTdHJpbmcgc3VnZ2VzdGVkVXJsKSB7CisgICAgaWYg
KGlkID09IG1faG9zdCkgcmV0dXJuOworICAgIGNhbmNlbCgpOyBtX25ldHdvcmsuY2xlYXJDb25u
ZWN0aW9uQ2FjaGUoKTsgbV9ob3N0ID0gaWQ7IG1fdG9rZW4uY2xlYXIoKTsgbV9waW4uY2xlYXIo
KTsKKyAgICBtX2VuZHBvaW50ID0gdmFsaWRFbmRwb2ludChzdWdnZXN0ZWRVcmwpID8gc3VnZ2Vz
dGVkVXJsIDogUVN0cmluZygpOworICAgIFFGaWxlIGYoY29uZmlnRmlsZSgpKTsKKyAgICBpZiAo
Zi5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpKSB7CisgICAgICAgIGF1dG8gYyA9IFFKc29uRG9j
dW1lbnQ6OmZyb21Kc29uKGYucmVhZEFsbCgpKS5vYmplY3QoKS52YWx1ZShpZCkudG9PYmplY3Qo
KTsKKyAgICAgICAgaWYgKHZhbGlkRW5kcG9pbnQoYy52YWx1ZSgidXJsIikudG9TdHJpbmcoKSkp
IHsKKyAgICAgICAgICAgIG1fZW5kcG9pbnQgPSBjLnZhbHVlKCJ1cmwiKS50b1N0cmluZygpOyBt
X3Rva2VuID0gYy52YWx1ZSgidG9rZW4iKS50b1N0cmluZygpOyBtX3BpbiA9IGMudmFsdWUoInBp
biIpLnRvU3RyaW5nKCk7CisgICAgICAgIH0KKyAgICB9CisgICAgbV9zdGF0cy5jbGVhcigpOyBt
X3N0YXR1cyA9IGlkLmlzRW1wdHkoKSA/IHRyKCJDaG9vc2UgYSBob3N0IHRvIHZpZXcgaGFyZHdh
cmUgc3RhdHMiKSA6IHRyKCJDb25maWd1cmUgYSBWaWJlcG9sbG8gcmVhZC1vbmx5IHN0YXRzIHRv
a2VuIik7CisgICAgZW1pdCBjb25maWdDaGFuZ2VkKCk7IGVtaXQgc3RhdHNDaGFuZ2VkKCk7IGlm
IChtX3Zpc2libGUpIHJlZnJlc2goKTsKK30KK2Jvb2wgQ3JpbXNvblN0YXR1czo6Y29uZmlndXJl
KFFTdHJpbmcgdXJsLCBRU3RyaW5nIHRva2VuLCBRU3RyaW5nIHBpbikgeworICAgIHBpbiA9IG5v
cm1hbGl6ZWRQaW4ocGluKTsKKyAgICBpZiAobV9ob3N0LmlzRW1wdHkoKSB8fCAhdmFsaWRFbmRw
b2ludCh1cmwpIHx8ICghcGluLmlzRW1wdHkoKSAmJgorICAgICAgICAocGluLnNpemUoKSAhPSA2
NCB8fCBwaW4uY29udGFpbnMoUVJlZ3VsYXJFeHByZXNzaW9uKCJbXjAtOWEtZl0iKSkpKSkgewor
ICAgICAgICBmYWlsKHRyKCJVc2UgYW4gSFRUUFMgaG9zdCBVUkwgYW5kIGFuIG9wdGlvbmFsIDY0
LWRpZ2l0IFNIQS0yNTYgY2VydGlmaWNhdGUgZmluZ2VycHJpbnQiKSk7IHJldHVybiBmYWxzZTsK
KyAgICB9CisgICAgLy8gQSBibGFuayB0b2tlbiBrZWVwcyB0aGUgb2xkIHRva2VuIG9ubHkgZm9y
IHRoZSBzYW1lIGVuZHBvaW50LgorICAgIGlmICh0b2tlbi5pc0VtcHR5KCkgJiYgUVVybCh1cmwp
ID09IFFVcmwobV9lbmRwb2ludCkpIHRva2VuID0gbV90b2tlbjsKKyAgICBpZiAodG9rZW4uaXNF
bXB0eSgpIHx8IHRva2VuLmNvbnRhaW5zKCdccicpIHx8IHRva2VuLmNvbnRhaW5zKCdcbicpIHx8
IHRva2VuLnNpemUoKSA+IDQwOTYpIHsKKyAgICAgICAgZmFpbCh0cigiQSByZWFkLW9ubHkgVmli
ZXBvbGxvIEFQSSB0b2tlbiBpcyByZXF1aXJlZCIpKTsgcmV0dXJuIGZhbHNlOworICAgIH0KKyAg
ICBRRmlsZSBmKGNvbmZpZ0ZpbGUoKSk7IFFKc29uT2JqZWN0IGFsbDsKKyAgICBpZiAoZi5vcGVu
KFFJT0RldmljZTo6UmVhZE9ubHkpKSBhbGwgPSBRSnNvbkRvY3VtZW50Ojpmcm9tSnNvbihmLnJl
YWRBbGwoKSkub2JqZWN0KCk7CisgICAgYWxsW21faG9zdF0gPSBRSnNvbk9iamVjdHt7InVybCIs
IHVybH0sIHsidG9rZW4iLCB0b2tlbn0sIHsicGluIiwgcGlufX07CisgICAgUURpcigpLm1rcGF0
aChRRmlsZUluZm8oY29uZmlnRmlsZSgpKS5hYnNvbHV0ZVBhdGgoKSk7CisgICAgUVNhdmVGaWxl
IG91dChjb25maWdGaWxlKCkpOworICAgIGlmICghb3V0Lm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9u
bHkpIHx8ICFvdXQuc2V0UGVybWlzc2lvbnModXNlck9ubHkpIHx8CisgICAgICAgIG91dC53cml0
ZShRSnNvbkRvY3VtZW50KGFsbCkudG9Kc29uKCkpIDwgMCB8fCAhb3V0LmNvbW1pdCgpKSB7Cisg
ICAgICAgIGZhaWwodHIoIkNvdWxkIG5vdCBzYXZlIGhvc3QgYWNjZXNzIHNldHRpbmdzIikpOyBy
ZXR1cm4gZmFsc2U7CisgICAgfQorICAgIGNhbmNlbCgpOyBtX25ldHdvcmsuY2xlYXJDb25uZWN0
aW9uQ2FjaGUoKTsgbV9lbmRwb2ludCA9IHVybDsgbV90b2tlbiA9IHRva2VuOyBtX3BpbiA9IHBp
bjsKKyAgICBtX3N0YXRzVGltZXIuc2V0SW50ZXJ2YWwoMjAwMCk7CisgICAgbV9zdGF0cy5jbGVh
cigpOyBtX3N0YXR1cyA9IHRyKCJDb25uZWN0aW5nIHRvIGhvc3Qgc3RhdHPigKYiKTsKKyAgICBl
bWl0IGNvbmZpZ0NoYW5nZWQoKTsgZW1pdCBzdGF0c0NoYW5nZWQoKTsgcmVmcmVzaCgpOyByZXR1
cm4gdHJ1ZTsKK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6c2V0VmlzaWJsZShib29sIHZpc2libGUp
IHsKKyAgICBtX3Zpc2libGUgPSB2aXNpYmxlOworICAgIGlmICh2aXNpYmxlKSB7IHJlZnJlc2hM
b2NhbCgpOyBtX3N0YXRzVGltZXIuc3RhcnQoKTsgcmVmcmVzaCgpOyB9CisgICAgZWxzZSB7IG1f
c3RhdHNUaW1lci5zdG9wKCk7IGNhbmNlbCgpOyB9Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OmZh
aWwoUVN0cmluZyBtZXNzYWdlKSB7CisgICAgbV9zdGF0cy5jbGVhcigpOyBtX3N0YXR1cyA9IG1l
c3NhZ2U7CisgICAgbV9zdGF0c1RpbWVyLnNldEludGVydmFsKHFNaW4oMzAwMDAsIHFNYXgoNDAw
MCwgbV9zdGF0c1RpbWVyLmludGVydmFsKCkgKiAyKSkpOworICAgIGVtaXQgc3RhdHNDaGFuZ2Vk
KCk7Cit9CitRVmFyaWFudE1hcCBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKGNvbnN0IFFCeXRl
QXJyYXkmIGJ5dGVzLCBRU3RyaW5nKiBlcnJvcikgeworICAgIGlmIChieXRlcy5zaXplKCkgPiA2
NTUzNikgeyAqZXJyb3IgPSAiT3ZlcnNpemVkIGhvc3Qgc3RhdHMgcmVzcG9uc2UiOyByZXR1cm4g
e307IH0KKyAgICBRSnNvblBhcnNlRXJyb3IgZTsgYXV0byBkb2MgPSBRSnNvbkRvY3VtZW50Ojpm
cm9tSnNvbihieXRlcywgJmUpOworICAgIGlmIChlLmVycm9yICE9IFFKc29uUGFyc2VFcnJvcjo6
Tm9FcnJvciB8fCAhZG9jLmlzT2JqZWN0KCkpIHsgKmVycm9yID0gIkludmFsaWQgaG9zdCBzdGF0
cyByZXNwb25zZSI7IHJldHVybiB7fTsgfQorICAgIGF1dG8gb2JqID0gZG9jLm9iamVjdCgpOyBR
VmFyaWFudE1hcCByZXN1bHQ7CisgICAgY29uc3QgUVN0cmluZ0xpc3Qga2V5cyA9IHsiY3B1X3Bl
cmNlbnQiLCJjcHVfdGVtcF9jIiwicmFtX3VzZWRfYnl0ZXMiLCJyYW1fdG90YWxfYnl0ZXMiLCJy
YW1fcGVyY2VudCIsCisgICAgICAgICJncHVfcGVyY2VudCIsImdwdV9lbmNvZGVyX3BlcmNlbnQi
LCJncHVfdGVtcF9jIiwidnJhbV91c2VkX2J5dGVzIiwidnJhbV90b3RhbF9ieXRlcyIsInZyYW1f
cGVyY2VudCIsIm5ldF9yeF9icHMiLCJuZXRfdHhfYnBzIn07CisgICAgYm9vbCByZWNvZ25pemVk
ID0gZmFsc2U7CisgICAgZm9yIChjb25zdCBhdXRvJiBrZXkgOiBrZXlzKSB7CisgICAgICAgIGF1
dG8gdiA9IG9iai52YWx1ZShrZXkpOyByZWNvZ25pemVkIHw9IG9iai5jb250YWlucyhrZXkpOwor
ICAgICAgICBkb3VibGUgbiA9IHYudG9Eb3VibGUoLTEpOworICAgICAgICBpZiAoIXYuaXNEb3Vi
bGUoKSB8fCAhc3RkOjppc2Zpbml0ZShuKSB8fCBuIDwgMCB8fCAoa2V5LmVuZHNXaXRoKCJwZXJj
ZW50IikgJiYgbiA+IDEwMCkpIGNvbnRpbnVlOworICAgICAgICByZXN1bHRba2V5XSA9IG47Cisg
ICAgfQorICAgIGZvciAoY29uc3QgYXV0byYgcHJlZml4IDoge1FTdHJpbmcoInJhbSIpLCBRU3Ry
aW5nKCJ2cmFtIil9KSB7CisgICAgICAgIGRvdWJsZSB0b3RhbCA9IHJlc3VsdC52YWx1ZShwcmVm
aXggKyAiX3RvdGFsX2J5dGVzIikudG9Eb3VibGUoKTsKKyAgICAgICAgaWYgKHRvdGFsIDw9IDAp
IHsgcmVzdWx0LnJlbW92ZShwcmVmaXggKyAiX3BlcmNlbnQiKTsgcmVzdWx0LnJlbW92ZShwcmVm
aXggKyAiX3VzZWRfYnl0ZXMiKTsgfQorICAgICAgICBlbHNlIGlmIChyZXN1bHQuY29udGFpbnMo
cHJlZml4ICsgIl91c2VkX2J5dGVzIikpIHsKKyAgICAgICAgICAgIGRvdWJsZSB1c2VkID0gcU1p
bihyZXN1bHQudmFsdWUocHJlZml4ICsgIl91c2VkX2J5dGVzIikudG9Eb3VibGUoKSwgdG90YWwp
OworICAgICAgICAgICAgcmVzdWx0W3ByZWZpeCArICJfdXNlZF9ieXRlcyJdID0gdXNlZDsgcmVz
dWx0W3ByZWZpeCArICJfcGVyY2VudCJdID0gdXNlZCAqIDEwMCAvIHRvdGFsOworICAgICAgICB9
CisgICAgfQorICAgIGlmICghcmVjb2duaXplZCkgeyAqZXJyb3IgPSAiSG9zdCBkb2VzIG5vdCBl
eHBvc2UgdGhlIGV4cGVjdGVkIFZpYmVwb2xsbyBzdGF0cyBmaWVsZHMiOyByZXR1cm4ge307IH0K
KyAgICBlcnJvci0+Y2xlYXIoKTsgcmV0dXJuIHJlc3VsdDsKK30KK3ZvaWQgQ3JpbXNvblN0YXR1
czo6cmVmcmVzaCgpIHsKKyAgICBpZiAoIW1fdmlzaWJsZSB8fCBtX3JlcGx5IHx8ICFjb25maWd1
cmVkKCkpIHJldHVybjsKKyAgICBRVXJsIHVybChtX2VuZHBvaW50KTsgdXJsLnNldFBhdGgoIi9h
cGkvaG9zdC9zdGF0cyIpOworICAgIFFOZXR3b3JrUmVxdWVzdCByZXEodXJsKTsKKyAgICByZXEu
c2V0QXR0cmlidXRlKFFOZXR3b3JrUmVxdWVzdDo6UmVkaXJlY3RQb2xpY3lBdHRyaWJ1dGUsIFFO
ZXR3b3JrUmVxdWVzdDo6TWFudWFsUmVkaXJlY3RQb2xpY3kpOworICAgIHJlcS5zZXRUcmFuc2Zl
clRpbWVvdXQoMzAwMCk7CisgICAgcmVxLnNldFJhd0hlYWRlcigiQXV0aG9yaXphdGlvbiIsICJC
ZWFyZXIgIiArIG1fdG9rZW4udG9VdGY4KCkpOworICAgIHJlcS5zZXRSYXdIZWFkZXIoIkFjY2Vw
dCIsICJhcHBsaWNhdGlvbi9qc29uIik7CisgICAgYXV0byByZXBseSA9IG1fbmV0d29yay5nZXQo
cmVxKTsgcmVwbHktPnNldFJlYWRCdWZmZXJTaXplKDY1NTM2KTsgbV9yZXBseSA9IHJlcGx5Owor
ICAgIGF1dG8gZGF0YSA9IHN0ZDo6bWFrZV9zaGFyZWQ8UUJ5dGVBcnJheT4oKTsKKyAgICBhdXRv
IGludmFsaWRQaW4gPSBzdGQ6Om1ha2Vfc2hhcmVkPGJvb2w+KGZhbHNlKTsKKyAgICBhdXRvIG92
ZXJzaXplZCA9IHN0ZDo6bWFrZV9zaGFyZWQ8Ym9vbD4oZmFsc2UpOworICAgIGF1dG8gY2VydE1h
dGNoZXMgPSBbdGhpcywgcmVwbHldIHsKKyAgICAgICAgcmV0dXJuIG5vcm1hbGl6ZWRQaW4oUVN0
cmluZzo6ZnJvbUxhdGluMShyZXBseS0+c3NsQ29uZmlndXJhdGlvbigpLnBlZXJDZXJ0aWZpY2F0
ZSgpLmRpZ2VzdChRQ3J5cHRvZ3JhcGhpY0hhc2g6OlNoYTI1NikudG9IZXgoKSkpID09IG1fcGlu
OworICAgIH07CisgICAgY29ubmVjdChyZXBseSwgJlFOZXR3b3JrUmVwbHk6OmVuY3J5cHRlZCwg
dGhpcywgW3RoaXMsIHJlcGx5LCBjZXJ0TWF0Y2hlcywgaW52YWxpZFBpbl0geworICAgICAgICBp
ZiAoIW1fcGluLmlzRW1wdHkoKSAmJiAhY2VydE1hdGNoZXMoKSkgeyAqaW52YWxpZFBpbiA9IHRy
dWU7IHJlcGx5LT5hYm9ydCgpOyB9CisgICAgfSk7CisgICAgY29ubmVjdChyZXBseSwgJlFOZXR3
b3JrUmVwbHk6OnNzbEVycm9ycywgdGhpcywgW3RoaXMsIHJlcGx5LCBjZXJ0TWF0Y2hlc10oY29u
c3QgUUxpc3Q8UVNzbEVycm9yPiYgZXJyb3JzKSB7CisgICAgICAgIGlmIChtX3Bpbi5pc0VtcHR5
KCkgfHwgIWNlcnRNYXRjaGVzKCkpIHJldHVybjsKKyAgICAgICAgZm9yIChjb25zdCBhdXRvJiBl
IDogZXJyb3JzKSB7CisgICAgICAgICAgICBpZiAoZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6U2Vs
ZlNpZ25lZENlcnRpZmljYXRlICYmIGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6OlNlbGZTaWduZWRD
ZXJ0aWZpY2F0ZUluQ2hhaW4gJiYKKyAgICAgICAgICAgICAgICBlLmVycm9yKCkgIT0gUVNzbEVy
cm9yOjpDZXJ0aWZpY2F0ZVVudHJ1c3RlZCAmJiBlLmVycm9yKCkgIT0gUVNzbEVycm9yOjpIb3N0
TmFtZU1pc21hdGNoKSByZXR1cm47CisgICAgICAgIH0KKyAgICAgICAgcmVwbHktPmlnbm9yZVNz
bEVycm9ycyhlcnJvcnMpOyAvLyBPbmx5IHRoaXMgZXhwbGljaXRseSBwaW5uZWQgaG9zdCBjZXJ0
aWZpY2F0ZS4KKyAgICB9KTsKKyAgICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtSZXBseTo6cmVh
ZHlSZWFkLCB0aGlzLCBbcmVwbHksIGRhdGEsIG92ZXJzaXplZF0geworICAgICAgICBpZiAoKm92
ZXJzaXplZCB8fCByZXBseS0+aXNGaW5pc2hlZCgpKSByZXR1cm47CisgICAgICAgIGlmIChkYXRh
LT5zaXplKCkgKyByZXBseS0+Ynl0ZXNBdmFpbGFibGUoKSA+IDY1NTM2KSB7ICpvdmVyc2l6ZWQg
PSB0cnVlOyByZXBseS0+YWJvcnQoKTsgcmV0dXJuOyB9CisgICAgICAgIGRhdGEtPmFwcGVuZChy
ZXBseS0+cmVhZEFsbCgpKTsKKyAgICB9KTsKKyAgICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtS
ZXBseTo6ZmluaXNoZWQsIHRoaXMsIFt0aGlzLCByZXBseSwgZGF0YSwgaW52YWxpZFBpbiwgb3Zl
cnNpemVkXSB7CisgICAgICAgIG1fcmVwbHkgPSBudWxscHRyOworICAgICAgICBpbnQgc3RhdHVz
ID0gcmVwbHktPmF0dHJpYnV0ZShRTmV0d29ya1JlcXVlc3Q6Okh0dHBTdGF0dXNDb2RlQXR0cmli
dXRlKS50b0ludCgpOworICAgICAgICBpZiAoKm92ZXJzaXplZCkgZmFpbCh0cigiSG9zdCBzdGF0
cyByZXNwb25zZSBleGNlZWRlZCB0aGUgc2l6ZSBsaW1pdCIpKTsKKyAgICAgICAgZWxzZSBpZiAo
KmludmFsaWRQaW4pIGZhaWwodHIoIkhvc3QgY2VydGlmaWNhdGUgY2hhbmdlZDsgdmVyaWZ5IHRo
ZSBzYXZlZCBmaW5nZXJwcmludCIpKTsKKyAgICAgICAgZWxzZSBpZiAoc3RhdHVzID09IDQwMSB8
fCBzdGF0dXMgPT0gNDAzKSBmYWlsKHRyKCJIb3N0IHN0YXRzIGFjY2VzcyBkZW5pZWQ6IGNoZWNr
IHRoZSByZWFkLW9ubHkgdG9rZW4iKSk7CisgICAgICAgIGVsc2UgaWYgKHN0YXR1cyA9PSA0MDQp
IGZhaWwodHIoIlRoaXMgaG9zdCBkb2VzIG5vdCBwcm92aWRlIFZpYmVwb2xsbyBoYXJkd2FyZSBz
dGF0cyIpKTsKKyAgICAgICAgZWxzZSBpZiAocmVwbHktPmVycm9yKCkgPT0gUU5ldHdvcmtSZXBs
eTo6U3NsSGFuZHNoYWtlRmFpbGVkRXJyb3IpIGZhaWwodHIoIlZlcmlmeSB0aGUgaG9zdCBjZXJ0
aWZpY2F0ZSBmaW5nZXJwcmludCBpbiBDb25maWd1cmUiKSk7CisgICAgICAgIGVsc2UgaWYgKHJl
cGx5LT5lcnJvcigpICE9IFFOZXR3b3JrUmVwbHk6Ok5vRXJyb3IgfHwgc3RhdHVzICE9IDIwMCkg
ZmFpbCh0cigiSG9zdCBzdGF0cyB1bmF2YWlsYWJsZTogY2hlY2sgY29ubmVjdGlvbiBhbmQgcmVh
bHRpbWUgc3RhdHMgc2V0dGluZyIpKTsKKyAgICAgICAgZWxzZSB7CisgICAgICAgICAgICBkYXRh
LT5hcHBlbmQocmVwbHktPnJlYWRBbGwoKSk7IFFTdHJpbmcgZXJyb3I7CisgICAgICAgICAgICBh
dXRvIHBhcnNlZCA9IHBhcnNlU3RhdHMoKmRhdGEsICZlcnJvcik7CisgICAgICAgICAgICBpZiAo
IWVycm9yLmlzRW1wdHkoKSkgZmFpbChlcnJvcik7CisgICAgICAgICAgICBlbHNlIHsgbV9zdGF0
c1RpbWVyLnNldEludGVydmFsKDIwMDApOyBtX3N0YXRzID0gcGFyc2VkOyBtX3N0YXR1cyA9IHRy
KCJIT1NUIOKAoiByZWNlaXZlZCAlMSIpLmFyZyhRRGF0ZVRpbWU6OmN1cnJlbnREYXRlVGltZSgp
LnRvU3RyaW5nKCJoaDptbTpzcyIpKTsgZW1pdCBzdGF0c0NoYW5nZWQoKTsgfQorICAgICAgICB9
CisgICAgICAgIHJlcGx5LT5kZWxldGVMYXRlcigpOworICAgIH0pOworICAgIC8vIEFic29sdXRl
IHJlcXVlc3QgYm91bmQgZXZlbiBpZiBhIHBlZXIga2VlcHMgc2VuZGluZyBvY2Nhc2lvbmFsIGJ5
dGVzLgorICAgIFFUaW1lcjo6c2luZ2xlU2hvdCgzNTAwLCByZXBseSwgW3JlcGx5XSB7IGlmICgh
cmVwbHktPmlzRmluaXNoZWQoKSkgcmVwbHktPmFib3J0KCk7IH0pOworfQorUVZhcmlhbnRNYXAg
Q3JpbXNvblN0YXR1czo6cmVhZExvY2FsKGNvbnN0IFFTdHJpbmcmIHJvb3QpIHsKKyAgICBRVmFy
aWFudE1hcCBvdXQ7IFFTdHJpbmdMaXN0IG5ldHdvcmtzOworICAgIGZvciAoY29uc3QgYXV0byYg
bmFtZSA6IFFEaXIocm9vdCArICIvY2xhc3MvbmV0IikuZW50cnlMaXN0KFFEaXI6OkRpcnMgfCBR
RGlyOjpOb0RvdEFuZERvdERvdCkpIHsKKyAgICAgICAgaWYgKG5hbWUgPT0gImxvIiB8fCByZWFk
KHJvb3QgKyAiL2NsYXNzL25ldC8iICsgbmFtZSArICIvb3BlcnN0YXRlIikgIT0gInVwIikgY29u
dGludWU7CisgICAgICAgIG5ldHdvcmtzIDw8IG5hbWU7CisgICAgfQorICAgIG91dFsiY29ubmVj
dGVkIl0gPSAhbmV0d29ya3MuaXNFbXB0eSgpOyBvdXRbIm5ldHdvcmsiXSA9IG5ldHdvcmtzLmlz
RW1wdHkoKSA/IHRyKCJObyBhY3RpdmUgbmV0d29yayBsaW5rIikgOiBuZXR3b3Jrcy5qb2luKCIs
ICIpOworICAgIC8vIExpbmsgc3RhdHVzIGlzIGludGVudGlvbmFsbHkgbm90IHByZXNlbnRlZCBh
cyBpbnRlcm5ldCByZWFjaGFiaWxpdHkuCisgICAgb3V0WyJiYXR0ZXJ5UGVyY2VudCJdID0gLTE7
IG91dFsiYmF0dGVyeVN0YXRlIl0gPSB0cigiQmF0dGVyeSB1bmF2YWlsYWJsZSIpOworICAgIGZv
ciAoY29uc3QgYXV0byYgbmFtZSA6IFFEaXIocm9vdCArICIvY2xhc3MvcG93ZXJfc3VwcGx5Iiku
ZW50cnlMaXN0KFFEaXI6OkRpcnMgfCBRRGlyOjpOb0RvdEFuZERvdERvdCkpIHsKKyAgICAgICAg
Y29uc3QgYXV0byBiYXNlID0gcm9vdCArICIvY2xhc3MvcG93ZXJfc3VwcGx5LyIgKyBuYW1lICsg
Ii8iOworICAgICAgICBpZiAocmVhZChiYXNlICsgInR5cGUiKSAhPSAiQmF0dGVyeSIgfHwgcmVh
ZChiYXNlICsgInByZXNlbnQiKSA9PSAiMCIpIGNvbnRpbnVlOworICAgICAgICBib29sIG9rOyBp
bnQgY2FwID0gcmVhZChiYXNlICsgImNhcGFjaXR5IikudG9JbnQoJm9rKTsKKyAgICAgICAgaWYg
KG9rICYmIGNhcCA+PSAwICYmIGNhcCA8PSAxMDApIG91dFsiYmF0dGVyeVBlcmNlbnQiXSA9IGNh
cDsKKyAgICAgICAgY29uc3QgYXV0byBzdGF0ZSA9IHJlYWQoYmFzZSArICJzdGF0dXMiKTsgb3V0
WyJiYXR0ZXJ5U3RhdGUiXSA9IHN0YXRlLmlzRW1wdHkoKSA/IHRyKCJVbmtub3duIikgOiBzdGF0
ZTsgYnJlYWs7CisgICAgfQorICAgIHJldHVybiBvdXQ7Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6
OnJlZnJlc2hMb2NhbCgpIHsKKyAgICBtX2xvY2FsID0gcmVhZExvY2FsKCk7IG1fbG9jYWxbIndp
ZmlTaWduYWwiXSA9IC0xOyBlbWl0IGxvY2FsQ2hhbmdlZCgpOworICAgIGlmIChtX3dpZmkuc3Rh
dGUoKSA9PSBRUHJvY2Vzczo6Tm90UnVubmluZykgeworICAgICAgICBtX3dpZmkuc3RhcnQoIm5t
Y2xpIiwgeyItdCIsICItLWVzY2FwZSIsICJubyIsICItZiIsICJBQ1RJVkUsU0lHTkFMLFNTSUQi
LCAiZGV2aWNlIiwgIndpZmkiLCAibGlzdCIsICItLXJlc2NhbiIsICJubyJ9KTsKKyAgICAgICAg
UVRpbWVyOjpzaW5nbGVTaG90KDIwMDAsICZtX3dpZmksIFt0aGlzXSB7IGlmIChtX3dpZmkuc3Rh
dGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgbV93aWZpLmtpbGwoKTsgfSk7CisgICAgfQor
fQorCitzdGF0aWMgdm9pZCByZWdpc3RlckNyaW1zb25TdGF0dXMoKSB7CisgICAgcW1sUmVnaXN0
ZXJTaW5nbGV0b25UeXBlPENyaW1zb25TdGF0dXM+KCJDcmltc29uU3RhdHVzIiwgMSwgMCwgIkNy
aW1zb25TdGF0dXMiLAorICAgICAgICBbXShRUW1sRW5naW5lKiwgUUpTRW5naW5lKikgLT4gUU9i
amVjdCogeyByZXR1cm4gbmV3IENyaW1zb25TdGF0dXMoKTsgfSk7Cit9CitRX0NPUkVBUFBfU1RB
UlRVUF9GVU5DVElPTihyZWdpc3RlckNyaW1zb25TdGF0dXMpCmRpZmYgLS1naXQgYS9hcHAvbW9v
bmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5oIGIvYXBwL21vb25saWdodG9zL2NyaW1zb25zdGF0dXMu
aApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi4yZGFjMGQxCi0tLSAvZGV2L251
bGwKKysrIGIvYXBwL21vb25saWdodG9zL2NyaW1zb25zdGF0dXMuaApAQCAtMCwwICsxLDUyIEBA
CisjcHJhZ21hIG9uY2UKKyNpbmNsdWRlIDxRT2JqZWN0PgorI2luY2x1ZGUgPFFWYXJpYW50TWFw
PgorI2luY2x1ZGUgPFFUaW1lcj4KKyNpbmNsdWRlIDxRTmV0d29ya0FjY2Vzc01hbmFnZXI+Cisj
aW5jbHVkZSA8UVBvaW50ZXI+CisjaW5jbHVkZSA8UU5ldHdvcmtSZXBseT4KKyNpbmNsdWRlIDxR
UHJvY2Vzcz4KKworLy8gT3B0aW9uYWwgbGF1bmNoZXIgc3RhdHVzLiBOZXZlciBwYXJ0aWNpcGF0
ZXMgaW4gdGhlIHN0cmVhbWluZy9kZWNvZGVyIHBhdGguCitjbGFzcyBDcmltc29uU3RhdHVzIDog
cHVibGljIFFPYmplY3QgeworICAgIFFfT0JKRUNUCisgICAgUV9QUk9QRVJUWShRVmFyaWFudE1h
cCBsb2NhbCBSRUFEIGxvY2FsIE5PVElGWSBsb2NhbENoYW5nZWQpCisgICAgUV9QUk9QRVJUWShR
VmFyaWFudE1hcCBzdGF0cyBSRUFEIHN0YXRzIE5PVElGWSBzdGF0c0NoYW5nZWQpCisgICAgUV9Q
Uk9QRVJUWShRU3RyaW5nIHN0YXR1cyBSRUFEIHN0YXR1cyBOT1RJRlkgc3RhdHNDaGFuZ2VkKQor
ICAgIFFfUFJPUEVSVFkoUVN0cmluZyBlbmRwb2ludCBSRUFEIGVuZHBvaW50IE5PVElGWSBjb25m
aWdDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBmaW5nZXJwcmludCBSRUFEIGZpbmdl
cnByaW50IE5PVElGWSBjb25maWdDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBjb25maWd1
cmVkIFJFQUQgY29uZmlndXJlZCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKK3B1YmxpYzoKKyAgICBl
eHBsaWNpdCBDcmltc29uU3RhdHVzKFFPYmplY3QqIHBhcmVudCA9IG51bGxwdHIpOworICAgIH5D
cmltc29uU3RhdHVzKCkgb3ZlcnJpZGU7CisgICAgUVZhcmlhbnRNYXAgbG9jYWwoKSBjb25zdCB7
IHJldHVybiBtX2xvY2FsOyB9CisgICAgUVZhcmlhbnRNYXAgc3RhdHMoKSBjb25zdCB7IHJldHVy
biBtX3N0YXRzOyB9CisgICAgUVN0cmluZyBzdGF0dXMoKSBjb25zdCB7IHJldHVybiBtX3N0YXR1
czsgfQorICAgIFFTdHJpbmcgZW5kcG9pbnQoKSBjb25zdCB7IHJldHVybiBtX2VuZHBvaW50OyB9
CisgICAgUVN0cmluZyBmaW5nZXJwcmludCgpIGNvbnN0IHsgcmV0dXJuIG1fcGluOyB9CisgICAg
Ym9vbCBjb25maWd1cmVkKCkgY29uc3QgeyByZXR1cm4gIW1fZW5kcG9pbnQuaXNFbXB0eSgpICYm
ICFtX3Rva2VuLmlzRW1wdHkoKTsgfQorICAgIFFfSU5WT0tBQkxFIHZvaWQgc2VsZWN0SG9zdChR
U3RyaW5nIGlkLCBRU3RyaW5nIHN1Z2dlc3RlZFVybCk7CisgICAgUV9JTlZPS0FCTEUgYm9vbCBj
b25maWd1cmUoUVN0cmluZyB1cmwsIFFTdHJpbmcgdG9rZW4sIFFTdHJpbmcgcGluKTsKKyAgICBR
X0lOVk9LQUJMRSB2b2lkIHNldFZpc2libGUoYm9vbCB2aXNpYmxlKTsKKyAgICBRX0lOVk9LQUJM
RSB2b2lkIHJlZnJlc2goKTsKKyAgICBzdGF0aWMgUVZhcmlhbnRNYXAgcGFyc2VTdGF0cyhjb25z
dCBRQnl0ZUFycmF5JiBieXRlcywgUVN0cmluZyogZXJyb3IpOworICAgIHN0YXRpYyBib29sIHZh
bGlkRW5kcG9pbnQoY29uc3QgUVN0cmluZyYgdXJsKTsKKyAgICBzdGF0aWMgUVN0cmluZyBub3Jt
YWxpemVkUGluKFFTdHJpbmcgcGluKTsKKyAgICBzdGF0aWMgUVZhcmlhbnRNYXAgcmVhZExvY2Fs
KGNvbnN0IFFTdHJpbmcmIHN5c1Jvb3QgPSAiL3N5cyIpOworc2lnbmFsczoKKyAgICB2b2lkIGxv
Y2FsQ2hhbmdlZCgpOworICAgIHZvaWQgc3RhdHNDaGFuZ2VkKCk7CisgICAgdm9pZCBjb25maWdD
aGFuZ2VkKCk7Citwcml2YXRlOgorICAgIHZvaWQgcmVmcmVzaExvY2FsKCk7CisgICAgdm9pZCBm
YWlsKFFTdHJpbmcgbWVzc2FnZSk7CisgICAgdm9pZCBjYW5jZWwoKTsKKyAgICBRU3RyaW5nIGNv
bmZpZ0ZpbGUoKSBjb25zdDsKKyAgICBRU3RyaW5nIG1faG9zdCwgbV9lbmRwb2ludCwgbV90b2tl
biwgbV9waW4sIG1fc3RhdHVzID0gIkNob29zZSBhIGhvc3QgdG8gdmlldyBoYXJkd2FyZSBzdGF0
cyI7CisgICAgUVZhcmlhbnRNYXAgbV9sb2NhbCwgbV9zdGF0czsKKyAgICBRVGltZXIgbV9sb2Nh
bFRpbWVyLCBtX3N0YXRzVGltZXI7CisgICAgUVByb2Nlc3MgbV93aWZpOworICAgIFFOZXR3b3Jr
QWNjZXNzTWFuYWdlciBtX25ldHdvcms7CisgICAgUVBvaW50ZXI8UU5ldHdvcmtSZXBseT4gbV9y
ZXBseTsKKyAgICBib29sIG1fdmlzaWJsZSA9IGZhbHNlOworfTsKZGlmZiAtLWdpdCBhL2FwcC9t
b29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwIGIvYXBwL21vb25saWdodG9zL2VjbGlwc2Vw
cm9maWxlcy5jcHAKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uZmU2MGZhZAot
LS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwCkBA
IC0wLDAgKzEsODAgQEAKKyNpbmNsdWRlICJlY2xpcHNlcHJvZmlsZXMuaCIKKyNpbmNsdWRlIDxR
Q3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVkZSA8UUNvcmVBcHBsaWNhdGlvbj4KKyNpbmNsdWRl
IDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFJbWFnZVJlYWRlcj4KKyNpbmNsdWRlIDxRSW1hZ2U+
CisjaW5jbHVkZSA8UURpcj4KKyNpbmNsdWRlIDxRRmlsZUluZm8+CisjaW5jbHVkZSA8UVNhdmVG
aWxlPgorI2luY2x1ZGUgPFFTdGFuZGFyZFBhdGhzPgorUVN0cmluZyBFY2xpcHNlUHJvZmlsZXM6
OmtleShRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSkgeworICAgIHJldHVybiAiZWNsaXBzZS9w
cm9maWxlcy8iICsgUVN0cmluZzo6ZnJvbUxhdGluMShRQ3J5cHRvZ3JhcGhpY0hhc2g6Omhhc2go
aG9zdC50b1V0ZjgoKSwgUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpICsgIi8i
ICsgUVN0cmluZzo6ZnJvbUxhdGluMShRQ3J5cHRvZ3JhcGhpY0hhc2g6Omhhc2gobmFtZS50cmlt
bWVkKCkudG9VdGY4KCksIFFDcnlwdG9ncmFwaGljSGFzaDo6U2hhMjU2KS50b0hleCgpKTsKK30K
K2Jvb2wgRWNsaXBzZVByb2ZpbGVzOjp2YWxpZChjb25zdCBRVmFyaWFudE1hcCYgdmFsdWVzKSB7
CisgICAgY29uc3QgUU1hcDxRU3RyaW5nLFFQYWlyPGludCxpbnQ+PiByYW5nZXMgPSB7eyJ3aWR0
aCIsezMyMCw3NjgwfX0sIHsiaGVpZ2h0Iix7MjAwLDQzMjB9fSwgeyJmcHMiLHsxLDI0MH19LCB7
ImJpdHJhdGVLYnBzIix7NTAwLDE1MDAwMH19fTsKKyAgICBpZiAodmFsdWVzLnNpemUoKSAhPSBy
YW5nZXMuc2l6ZSgpKSByZXR1cm4gZmFsc2U7CisgICAgZm9yIChhdXRvIGkgPSByYW5nZXMuYmVn
aW4oKTsgaSAhPSByYW5nZXMuZW5kKCk7ICsraSkgeworICAgICAgICBib29sIG9rOyBhdXRvIG4g
PSB2YWx1ZXMudmFsdWUoaS5rZXkoKSkudG9JbnQoJm9rKTsKKyAgICAgICAgaWYgKCFvayB8fCBu
IDwgaS52YWx1ZSgpLmZpcnN0IHx8IG4gPiBpLnZhbHVlKCkuc2Vjb25kKSByZXR1cm4gZmFsc2U7
CisgICAgfQorICAgIHJldHVybiB0cnVlOworfQorYm9vbCBFY2xpcHNlUHJvZmlsZXM6OnNhdmUo
UVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUsIFFWYXJpYW50TWFwIHZhbHVlcykgeworICAgIG5h
bWUgPSBuYW1lLnRyaW1tZWQoKTsKKyAgICBpZiAoaG9zdC5zaXplKCkgPiAyNTYgfHwgbmFtZS5p
c0VtcHR5KCkgfHwgbmFtZS5zaXplKCkgPiA0OCB8fCAhdmFsaWQodmFsdWVzKSkgcmV0dXJuIGZh
bHNlOworICAgIGlmICghbmFtZXMoaG9zdCkuY29udGFpbnMobmFtZSkgJiYgbmFtZXMoaG9zdCku
c2l6ZSgpID49IDMyKSByZXR1cm4gZmFsc2U7CisgICAgUVNldHRpbmdzIHNldHRpbmdzOyBzZXR0
aW5ncy5zZXRWYWx1ZShrZXkoaG9zdCxuYW1lKSsiL25hbWUiLG5hbWUpOyBzZXR0aW5ncy5zZXRW
YWx1ZShrZXkoaG9zdCxuYW1lKSsiL3ZhbHVlcyIsdmFsdWVzKTsgc2V0dGluZ3Muc3luYygpOwor
ICAgIHJldHVybiBzZXR0aW5ncy5zdGF0dXMoKSA9PSBRU2V0dGluZ3M6Ok5vRXJyb3I7Cit9CitR
VmFyaWFudE1hcCBFY2xpcHNlUHJvZmlsZXM6OmxvYWQoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5h
bWUpIHsKKyAgICBRU2V0dGluZ3Mgc2V0dGluZ3M7IGF1dG8gdmFsdWUgPSBzZXR0aW5ncy52YWx1
ZShrZXkoaG9zdCxuYW1lKSsiL3ZhbHVlcyIpLnRvTWFwKCk7CisgICAgcmV0dXJuIHZhbGlkKHZh
bHVlKSA/IHZhbHVlIDogUVZhcmlhbnRNYXAoKTsKK30KK2Jvb2wgRWNsaXBzZVByb2ZpbGVzOjpy
ZW1vdmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUsIGJvb2wgY29uZmlybWVkKSB7CisgICAg
aWYgKCFjb25maXJtZWQpIHJldHVybiBmYWxzZTsKKyAgICBRU2V0dGluZ3Mgc2V0dGluZ3M7IHNl
dHRpbmdzLnJlbW92ZShrZXkoaG9zdCxuYW1lKSk7IHNldHRpbmdzLnN5bmMoKTsgcmV0dXJuIHNl
dHRpbmdzLnN0YXR1cygpID09IFFTZXR0aW5nczo6Tm9FcnJvcjsKK30KK1FTdHJpbmdMaXN0IEVj
bGlwc2VQcm9maWxlczo6bmFtZXMoUVN0cmluZyBob3N0KSB7CisgICAgUVNldHRpbmdzIHNldHRp
bmdzOyBzZXR0aW5ncy5iZWdpbkdyb3VwKGtleShob3N0LCAiIikuc2VjdGlvbignLycsMCwtMikp
OworICAgIFFTdHJpbmdMaXN0IHJlc3VsdDsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIGNoaWxkIDog
c2V0dGluZ3MuY2hpbGRHcm91cHMoKSkgeyBhdXRvIG5hbWUgPSBzZXR0aW5ncy52YWx1ZShjaGls
ZCsiL25hbWUiKS50b1N0cmluZygpOyBpZiAoIW5hbWUuaXNFbXB0eSgpKSByZXN1bHQuYXBwZW5k
KG5hbWUpOyB9CisgICAgcmVzdWx0LnNvcnQoKTsgcmV0dXJuIHJlc3VsdDsKK30KK3N0YXRpYyB2
b2lkIHJlZ2lzdGVyRWNsaXBzZVByb2ZpbGVzKCkgeworICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9u
VHlwZTxFY2xpcHNlUHJvZmlsZXM+KCJFY2xpcHNlUHJvZmlsZXMiLDEsMCwiRWNsaXBzZVByb2Zp
bGVzIixbXShRUW1sRW5naW5lKixRSlNFbmdpbmUqKSAtPiBRT2JqZWN0KiB7IHJldHVybiBuZXcg
RWNsaXBzZVByb2ZpbGVzKCk7IH0pOworfQorUV9DT1JFQVBQX1NUQVJUVVBfRlVOQ1RJT04ocmVn
aXN0ZXJFY2xpcHNlUHJvZmlsZXMpCisKK1FVcmwgRWNsaXBzZVByb2ZpbGVzOjpiYWNrZ3JvdW5k
Rm9sZGVyKCkgY29uc3QgeworICAgIFFTdHJpbmcgcGF0aD1RU3RhbmRhcmRQYXRoczo6d3JpdGFi
bGVMb2NhdGlvbihRU3RhbmRhcmRQYXRoczo6UGljdHVyZXNMb2NhdGlvbik7CisgICAgcmV0dXJu
IFFVcmw6OmZyb21Mb2NhbEZpbGUoUURpcihwYXRoKS5leGlzdHMoKT9wYXRoOlFEaXI6OmhvbWVQ
YXRoKCkpOworfQorUVZhcmlhbnRMaXN0IEVjbGlwc2VQcm9maWxlczo6YmFja2dyb3VuZEZpbGVz
KFFVcmwgZGlyZWN0b3J5KSB7CisgICAgaWYoZGlyZWN0b3J5LmlzRW1wdHkoKSkgZGlyZWN0b3J5
PWJhY2tncm91bmRGb2xkZXIoKTsKKyAgICBpZighZGlyZWN0b3J5LmlzTG9jYWxGaWxlKCkpIHJl
dHVybiB7fTsKKyAgICBRRGlyIGRpcihkaXJlY3RvcnkudG9Mb2NhbEZpbGUoKSk7IGlmKCFkaXIu
ZXhpc3RzKCkpIHJldHVybiB7fTsKKyAgICBRVmFyaWFudExpc3QgcmVzdWx0OworICAgIGlmKCFk
aXIuaXNSb290KCkpIHsgUURpciB1cD1kaXI7dXAuY2RVcCgpO3Jlc3VsdC5hcHBlbmQoUVZhcmlh
bnRNYXB7eyJuYW1lIixRU3RyaW5nKCIuLiIpfSx7InVybCIsUVVybDo6ZnJvbUxvY2FsRmlsZSh1
cC5hYnNvbHV0ZVBhdGgoKSl9LHsiZGlyZWN0b3J5Iix0cnVlfX0pOyB9CisgICAgZm9yKGNvbnN0
IFFGaWxlSW5mbyYgZmlsZTpkaXIuZW50cnlJbmZvTGlzdChRRGlyOjpEaXJzfFFEaXI6OkZpbGVz
fFFEaXI6Ok5vRG90QW5kRG90RG90fFFEaXI6OlJlYWRhYmxlLFFEaXI6OkRpcnNGaXJzdHxRRGly
OjpOYW1lKSkgeworICAgICAgICBpZihyZXN1bHQuc2l6ZSgpPj01MTIpIGJyZWFrOworICAgICAg
ICBpZighZmlsZS5pc0RpcigpJiYhUVN0cmluZ0xpc3R7InBuZyIsImpwZyIsImpwZWciLCJ3ZWJw
IiwiYm1wIn0uY29udGFpbnMoZmlsZS5zdWZmaXgoKS50b0xvd2VyKCkpKSBjb250aW51ZTsKKyAg
ICAgICAgcmVzdWx0LmFwcGVuZChRVmFyaWFudE1hcHt7Im5hbWUiLGZpbGUuZmlsZU5hbWUoKX0s
eyJ1cmwiLFFVcmw6OmZyb21Mb2NhbEZpbGUoZmlsZS5hYnNvbHV0ZUZpbGVQYXRoKCkpfSx7ImRp
cmVjdG9yeSIsZmlsZS5pc0RpcigpfX0pOworICAgIH0KKyAgICByZXR1cm4gcmVzdWx0OworfQor
Ym9vbCBFY2xpcHNlUHJvZmlsZXM6OmNob29zZUJhY2tncm91bmQoUVVybCBzb3VyY2UpIHsKKyAg
ICBpZighc291cmNlLmlzTG9jYWxGaWxlKCkpIHJldHVybiBmYWxzZTsKKyAgICBRRmlsZUluZm8g
ZmlsZShzb3VyY2UudG9Mb2NhbEZpbGUoKSk7IGlmKCFmaWxlLmlzRmlsZSgpfHxmaWxlLnNpemUo
KT4zMioxMDI0KjEwMjQpIHJldHVybiBmYWxzZTsKKyAgICBRSW1hZ2VSZWFkZXIgcmVhZGVyKGZp
bGUuYWJzb2x1dGVGaWxlUGF0aCgpKTtyZWFkZXIuc2V0QXV0b1RyYW5zZm9ybSh0cnVlKTsKKyAg
ICBRU2l6ZSBzaXplPXJlYWRlci5zaXplKCk7aWYoIXNpemUuaXNWYWxpZCgpfHxzaXplLndpZHRo
KCk+MTYzODR8fHNpemUuaGVpZ2h0KCk+MTYzODR8fHFpbnQ2NChzaXplLndpZHRoKCkpKnNpemUu
aGVpZ2h0KCk+NjQwMDAwMDApIHJldHVybiBmYWxzZTsKKyAgICBpZihzaXplLndpZHRoKCk+MjU2
MHx8c2l6ZS5oZWlnaHQoKT4yNTYwKSByZWFkZXIuc2V0U2NhbGVkU2l6ZShzaXplLnNjYWxlZCgy
NTYwLDI1NjAsUXQ6OktlZXBBc3BlY3RSYXRpbykpOworICAgIFFJbWFnZSBpbWFnZT1yZWFkZXIu
cmVhZCgpO2lmKGltYWdlLmlzTnVsbCgpKSByZXR1cm4gZmFsc2U7CisgICAgUVN0cmluZyBmb2xk
ZXI9UVN0YW5kYXJkUGF0aHM6OndyaXRhYmxlTG9jYXRpb24oUVN0YW5kYXJkUGF0aHM6OkFwcERh
dGFMb2NhdGlvbikrIi9hcHBlYXJhbmNlIjsKKyAgICBpZighUURpcigpLm1rcGF0aChmb2xkZXIp
KSByZXR1cm4gZmFsc2U7CisgICAgUVN0cmluZyBwYXRoPWZvbGRlcisiL2NyaW1zb24tZ2xhc3Mt
YmFja2dyb3VuZC5wbmciOworICAgIFFTYXZlRmlsZSBvdXRwdXQocGF0aCk7aWYoIW91dHB1dC5v
cGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KXx8IWltYWdlLnNhdmUoJm91dHB1dCwiUE5HIil8fCFv
dXRwdXQuY29tbWl0KCkpIHJldHVybiBmYWxzZTsKKyAgICBRU2V0dGluZ3Mgc2V0dGluZ3M7c2V0
dGluZ3Muc2V0VmFsdWUoImVjbGlwc2UvYmFja2dyb3VuZFBhdGgiLHBhdGgpO3NldHRpbmdzLnN5
bmMoKTsKKyAgICBlbWl0IGFwcGVhcmFuY2VDaGFuZ2VkKCk7cmV0dXJuIHNldHRpbmdzLnN0YXR1
cygpPT1RU2V0dGluZ3M6Ok5vRXJyb3I7Cit9Cit2b2lkIEVjbGlwc2VQcm9maWxlczo6cmVzZXRC
YWNrZ3JvdW5kKCkgeyBRU2V0dGluZ3MoKS5yZW1vdmUoImVjbGlwc2UvYmFja2dyb3VuZFBhdGgi
KTtlbWl0IGFwcGVhcmFuY2VDaGFuZ2VkKCk7IH0KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRv
cy9lY2xpcHNlcHJvZmlsZXMuaCBiL2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuaApu
ZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi45MWI5Njc1Ci0tLSAvZGV2L251bGwK
KysrIGIvYXBwL21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5oCkBAIC0wLDAgKzEsMzggQEAK
KyNwcmFnbWEgb25jZQorI2luY2x1ZGUgPFFPYmplY3Q+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+
CisjaW5jbHVkZSA8UVNldHRpbmdzPgorI2luY2x1ZGUgPFFVcmw+CisjaW5jbHVkZSA8UVZhcmlh
bnRMaXN0PgorY2xhc3MgRWNsaXBzZVByb2ZpbGVzIDogcHVibGljIFFPYmplY3QgeworICAgIFFf
T0JKRUNUCisgICAgUV9QUk9QRVJUWShpbnQgdGV4dFNjYWxlIFJFQUQgdGV4dFNjYWxlIFdSSVRF
IHNldFRleHRTY2FsZSBOT1RJRlkgYXBwZWFyYW5jZUNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShi
b29sIHJlZHVjZWRNb3Rpb24gUkVBRCByZWR1Y2VkTW90aW9uIFdSSVRFIHNldFJlZHVjZWRNb3Rp
b24gTk9USUZZIGFwcGVhcmFuY2VDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBoaWdoQ29u
dHJhc3QgUkVBRCBoaWdoQ29udHJhc3QgV1JJVEUgc2V0SGlnaENvbnRyYXN0IE5PVElGWSBhcHBl
YXJhbmNlQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFVcmwgYmFja2dyb3VuZCBSRUFEIGJhY2tn
cm91bmQgTk9USUZZIGFwcGVhcmFuY2VDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoaW50IGJhY2tn
cm91bmREaW0gUkVBRCBiYWNrZ3JvdW5kRGltIFdSSVRFIHNldEJhY2tncm91bmREaW0gTk9USUZZ
IGFwcGVhcmFuY2VDaGFuZ2VkKQorcHVibGljOgorICAgIGV4cGxpY2l0IEVjbGlwc2VQcm9maWxl
cyhRT2JqZWN0KiBwYXJlbnQgPSBudWxscHRyKSA6IFFPYmplY3QocGFyZW50KSB7fQorICAgIGlu
dCB0ZXh0U2NhbGUoKSBjb25zdCB7IHJldHVybiBxQm91bmQoMTAwLFFTZXR0aW5ncygpLnZhbHVl
KCJlY2xpcHNlL3RleHRTY2FsZSIsMTAwKS50b0ludCgpLDEyNSk7IH0KKyAgICBib29sIHJlZHVj
ZWRNb3Rpb24oKSBjb25zdCB7IHJldHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9yZWR1
Y2VkTW90aW9uIixmYWxzZSkudG9Cb29sKCk7IH0KKyAgICBib29sIGhpZ2hDb250cmFzdCgpIGNv
bnN0IHsgcmV0dXJuIFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2hpZ2hDb250cmFzdCIsZmFs
c2UpLnRvQm9vbCgpOyB9CisgICAgdm9pZCBzZXRUZXh0U2NhbGUoaW50IHZhbHVlKSB7IFFTZXR0
aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlL3RleHRTY2FsZSIscUJvdW5kKDEwMCx2YWx1ZSwxMjUp
KTsgZW1pdCBhcHBlYXJhbmNlQ2hhbmdlZCgpOyB9CisgICAgdm9pZCBzZXRSZWR1Y2VkTW90aW9u
KGJvb2wgdmFsdWUpIHsgUVNldHRpbmdzKCkuc2V0VmFsdWUoImVjbGlwc2UvcmVkdWNlZE1vdGlv
biIsdmFsdWUpOyBlbWl0IGFwcGVhcmFuY2VDaGFuZ2VkKCk7IH0KKyAgICB2b2lkIHNldEhpZ2hD
b250cmFzdChib29sIHZhbHVlKSB7IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlL2hpZ2hD
b250cmFzdCIsdmFsdWUpOyBlbWl0IGFwcGVhcmFuY2VDaGFuZ2VkKCk7IH0KKyAgICBRVXJsIGJh
Y2tncm91bmQoKSBjb25zdCB7IFFTdHJpbmcgcGF0aD1RU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBz
ZS9iYWNrZ3JvdW5kUGF0aCIpLnRvU3RyaW5nKCk7cmV0dXJuIHBhdGguaXNFbXB0eSgpP1FVcmwo
KTpRVXJsOjpmcm9tTG9jYWxGaWxlKHBhdGgpOyB9CisgICAgaW50IGJhY2tncm91bmREaW0oKSBj
b25zdCB7IHJldHVybiBxQm91bmQoMzAsUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvYmFja2dy
b3VuZERpbSIsNjUpLnRvSW50KCksOTApOyB9CisgICAgdm9pZCBzZXRCYWNrZ3JvdW5kRGltKGlu
dCB2YWx1ZSkgeyBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS9iYWNrZ3JvdW5kRGltIixx
Qm91bmQoMzAsdmFsdWUsOTApKTsgZW1pdCBhcHBlYXJhbmNlQ2hhbmdlZCgpOyB9CisgICAgUV9J
TlZPS0FCTEUgYm9vbCBjaG9vc2VCYWNrZ3JvdW5kKFFVcmwgc291cmNlKTsKKyAgICBRX0lOVk9L
QUJMRSB2b2lkIHJlc2V0QmFja2dyb3VuZCgpOworICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50TGlz
dCBiYWNrZ3JvdW5kRmlsZXMoUVVybCBkaXJlY3Rvcnk9UVVybCgpKTsKKyAgICBRX0lOVk9LQUJM
RSBRVXJsIGJhY2tncm91bmRGb2xkZXIoKSBjb25zdDsKKyAgICBRX0lOVk9LQUJMRSBib29sIHNh
dmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUsIFFWYXJpYW50TWFwIHZhbHVlcyk7CisgICAg
UV9JTlZPS0FCTEUgUVZhcmlhbnRNYXAgbG9hZChRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSk7
CisgICAgUV9JTlZPS0FCTEUgYm9vbCByZW1vdmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUs
IGJvb2wgY29uZmlybWVkKTsKKyAgICBRX0lOVk9LQUJMRSBRU3RyaW5nTGlzdCBuYW1lcyhRU3Ry
aW5nIGhvc3QpOworICAgIHN0YXRpYyBib29sIHZhbGlkKGNvbnN0IFFWYXJpYW50TWFwJiB2YWx1
ZXMpOworc2lnbmFsczoKKyAgICB2b2lkIGFwcGVhcmFuY2VDaGFuZ2VkKCk7Citwcml2YXRlOgor
ICAgIHN0YXRpYyBRU3RyaW5nIGtleShRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSk7Cit9Owpk
aWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuY3BwIGIvYXBwL21vb25s
aWdodG9zL2xvY2FsaGFyZHdhcmUuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAw
MDAuLjE5ZjgxOGQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvbG9jYWxoYXJk
d2FyZS5jcHAKQEAgLTAsMCArMSwxMzggQEAKKyNpbmNsdWRlICJsb2NhbGhhcmR3YXJlLmgiCisj
aW5jbHVkZSA8UXRNYXRoPgorI2luY2x1ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFEaXI+CisjaW5j
bHVkZSA8UVNldD4KKyNpbmNsdWRlIDxRU3RvcmFnZUluZm8+CisjaW5jbHVkZSA8UUZpbGVJbmZv
PgorI2luY2x1ZGUgPFFFbGFwc2VkVGltZXI+CisjaW5jbHVkZSA8UU11dGV4PgorI2luY2x1ZGUg
PFFNdXRleExvY2tlcj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFDb3JlQXBw
bGljYXRpb24+CisjaW5jbHVkZSA8UVJlZ3VsYXJFeHByZXNzaW9uPgorCitzdGF0aWMgUVN0cmlu
ZyByZWFkKGNvbnN0IFFTdHJpbmcmIHBhdGgpIHsgUUZpbGUgZihwYXRoKTsgcmV0dXJuIGYub3Bl
bihRSU9EZXZpY2U6OlJlYWRPbmx5KSA/IFFTdHJpbmc6OmZyb21VdGY4KGYucmVhZCgzMjc2OCkp
LnRyaW1tZWQoKSA6IFFTdHJpbmcoKTsgfQorc3RhdGljIGRvdWJsZSBudW1iZXIoY29uc3QgUVN0
cmluZyYgcGF0aCkgeyBib29sIG9rOyBkb3VibGUgbj1yZWFkKHBhdGgpLnRvRG91YmxlKCZvayk7
IHJldHVybiBvayAmJiBxSXNGaW5pdGUobikgPyBuIDogLTE7IH0KK0xvY2FsSGFyZHdhcmU6Okxv
Y2FsSGFyZHdhcmUoUU9iamVjdCogcGFyZW50KTpRT2JqZWN0KHBhcmVudCkgeyBtX3RpbWVyLnNl
dEludGVydmFsKHJlZnJlc2hTZWNvbmRzKCkqMTAwMCk7IGNvbm5lY3QoJm1fdGltZXIsJlFUaW1l
cjo6dGltZW91dCx0aGlzLCZMb2NhbEhhcmR3YXJlOjpyZWZyZXNoKTsgfQordm9pZCBMb2NhbEhh
cmR3YXJlOjpzZXRBY3RpdmUoYm9vbCBhY3RpdmUpIHsgbV9sZWdhY3lBY3RpdmU9YWN0aXZlO3Vw
ZGF0ZVNhbXBsaW5nKCk7IH0KK3ZvaWQgTG9jYWxIYXJkd2FyZTo6dXBkYXRlU2FtcGxpbmcoKSB7
CisgICAgaWYoIW1fbGVnYWN5QWN0aXZlICYmIG1fY29uc3VtZXJzLmlzRW1wdHkoKSkgbV90aW1l
ci5zdG9wKCk7CisgICAgZWxzZSBpZighbV90aW1lci5pc0FjdGl2ZSgpKSB7cmVmcmVzaCgpO21f
dGltZXIuc3RhcnQoKTt9Cit9Cit2b2lkIExvY2FsSGFyZHdhcmU6OnNldENvbnN1bWVyQWN0aXZl
KFFPYmplY3QqIGNvbnN1bWVyLGJvb2wgYWN0aXZlKSB7CisgICAgaWYoIWNvbnN1bWVyKSByZXR1
cm47CisgICAgaWYoYWN0aXZlICYmICFtX2NvbnN1bWVycy5jb250YWlucyhjb25zdW1lcikpIHsK
KyAgICAgICAgbV9jb25zdW1lcnMuaW5zZXJ0KGNvbnN1bWVyKTsKKyAgICAgICAgaWYoIW1fa25v
d25Db25zdW1lcnMuY29udGFpbnMoY29uc3VtZXIpKSB7CisgICAgICAgICAgICBtX2tub3duQ29u
c3VtZXJzLmluc2VydChjb25zdW1lcik7CisgICAgICAgICAgICBjb25uZWN0KGNvbnN1bWVyLCZR
T2JqZWN0OjpkZXN0cm95ZWQsdGhpcyxbdGhpcyxjb25zdW1lcl17bV9rbm93bkNvbnN1bWVycy5y
ZW1vdmUoY29uc3VtZXIpO21fY29uc3VtZXJzLnJlbW92ZShjb25zdW1lcik7dXBkYXRlU2FtcGxp
bmcoKTt9KTsKKyAgICAgICAgfQorICAgIH0gZWxzZSBpZighYWN0aXZlKSBtX2NvbnN1bWVycy5y
ZW1vdmUoY29uc3VtZXIpOworICAgIHVwZGF0ZVNhbXBsaW5nKCk7Cit9Cit2b2lkIExvY2FsSGFy
ZHdhcmU6OnJlZnJlc2goKSB7IG1fcmVhZGluZ3M9c2FtcGxlKCk7IG1faGlzdG9yeS5hcHBlbmQo
bV9yZWFkaW5ncyk7IHdoaWxlKG1faGlzdG9yeS5zaXplKCk+NjApIG1faGlzdG9yeS5yZW1vdmVG
aXJzdCgpOyBlbWl0IGNoYW5nZWQoKTsgfQordm9pZCBMb2NhbEhhcmR3YXJlOjpzZXRGaWVsZHMo
UVN0cmluZ0xpc3QgdikgeyBRU3RyaW5nTGlzdCBjbGVhbjsgZm9yKGNvbnN0IFFTdHJpbmcmIGtl
eTpRU3RyaW5nTGlzdHsiY3B1IiwibWVtb3J5IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3Jr
IiwiYmF0dGVyeSIsInN0b3JhZ2UifSkgaWYodi5jb250YWlucyhrZXkpKSBjbGVhbi5hcHBlbmQo
a2V5KTsgc2F2ZSgibG9jYWxGaWVsZHMiLGNsZWFuKTsgfQorCitRVmFyaWFudE1hcCBMb2NhbEhh
cmR3YXJlOjpzYW1wbGUoY29uc3QgUVN0cmluZyYgcm9vdCkgeworICAgIC8vIFNoYXJlZCBjYWNo
ZTogU2V0dGluZ3MgYW5kIHRoZSBkZWNvZGVyIHJldXNlIG9uZSBib3VuZGVkLCByZWFkLW9ubHkg
c2FtcGxlLgorICAgIHN0YXRpYyBRTXV0ZXggbXV0ZXg7IFFNdXRleExvY2tlciBsb2NrZXIoJm11
dGV4KTsKKyAgICBzdGF0aWMgUUVsYXBzZWRUaW1lciBjbG9jazsgaWYoIWNsb2NrLmlzVmFsaWQo
KSkgY2xvY2suc3RhcnQoKTsKKyAgICBzdGF0aWMgUU1hcDxRU3RyaW5nLFFWYXJpYW50TWFwPiBw
cmV2aW91cywgY2FjaGVkOworICAgIHN0YXRpYyBRTWFwPFFTdHJpbmcscWludDY0PiBsYXN0Owor
ICAgIHFpbnQ2NCBub3c9Y2xvY2suZWxhcHNlZCgpOworICAgIGludCBpbnRlcnZhbD1xQm91bmQo
MSxRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9oYXJkd2FyZVJlZnJlc2giLDIpLnRvSW50KCks
NSkqMTAwMDsKKyAgICBpZihjYWNoZWQuY29udGFpbnMocm9vdCkgJiYgbm93LWxhc3QudmFsdWUo
cm9vdCk8aW50ZXJ2YWwpIHJldHVybiBjYWNoZWQudmFsdWUocm9vdCk7CisgICAgUVZhcmlhbnRN
YXAgcmVzdWx0LCBjb3VudGVyczsKKyAgICBhdXRvIG9sZD1wcmV2aW91cy52YWx1ZShyb290KTsg
ZG91YmxlIHNlY29uZHM9KG5vdy1sYXN0LnZhbHVlKHJvb3QpKS8xMDAwLjA7CisgICAgYXV0byBz
dGF0PXJlYWQocm9vdCsiL3Byb2Mvc3RhdCIpLnNlY3Rpb24oJ1xuJywwLDApLnNpbXBsaWZpZWQo
KS5zcGxpdCgnICcpOworICAgIGlmKHN0YXQuc2l6ZSgpPj05ICYmIHN0YXRbMF09PSJjcHUiKSB7
CisgICAgICAgIHF1aW50NjQgdG90YWw9MDsgZm9yKGludCBpPTE7aTw9ODtpKyspIHRvdGFsKz1z
dGF0W2ldLnRvVUxvbmdMb25nKCk7CisgICAgICAgIHF1aW50NjQgaWRsZT1zdGF0WzRdLnRvVUxv
bmdMb25nKCkrc3RhdFs1XS50b1VMb25nTG9uZygpOworICAgICAgICBjb3VudGVyc1sidG90YWwi
XT10b3RhbDsgY291bnRlcnNbImlkbGUiXT1pZGxlOworICAgICAgICBxdWludDY0IGJlZm9yZT1v
bGQudmFsdWUoInRvdGFsIikudG9VTG9uZ0xvbmcoKTsKKyAgICAgICAgaWYob2xkLmNvbnRhaW5z
KCJ0b3RhbCIpICYmIHRvdGFsPmJlZm9yZSAmJiBpZGxlPj1vbGQudmFsdWUoImlkbGUiKS50b1VM
b25nTG9uZygpKSByZXN1bHRbImNwdVBlcmNlbnQiXT1xQm91bmQoMC4wLDEwMC4wKigxLjAtZG91
YmxlKGlkbGUtb2xkWyJpZGxlIl0udG9VTG9uZ0xvbmcoKSkvZG91YmxlKHRvdGFsLWJlZm9yZSkp
LDEwMC4wKTsKKyAgICB9CisgICAgUU1hcDxRU3RyaW5nLHF1aW50NjQ+IG1lbW9yeTsKKyAgICBm
b3IoY29uc3QgUVN0cmluZyYgbGluZTpyZWFkKHJvb3QrIi9wcm9jL21lbWluZm8iKS5zcGxpdCgn
XG4nKSkgeyBhdXRvIHBhcnRzPWxpbmUuc2ltcGxpZmllZCgpLnNwbGl0KCcgJyk7IGlmKHBhcnRz
LnNpemUoKT49MikgbWVtb3J5W3BhcnRzWzBdXT1wYXJ0c1sxXS50b1VMb25nTG9uZygpKjEwMjQ7
IH0KKyAgICBxdWludDY0IHRvdGFsPW1lbW9yeS52YWx1ZSgiTWVtVG90YWw6IiksIGF2YWlsYWJs
ZT1tZW1vcnkudmFsdWUoIk1lbUF2YWlsYWJsZToiKTsKKyAgICBpZih0b3RhbCAmJiBhdmFpbGFi
bGU8PXRvdGFsICYmIG1lbW9yeS5jb250YWlucygiTWVtQXZhaWxhYmxlOiIpKSB7IHJlc3VsdFsi
bWVtb3J5VXNlZEdpQiJdPWRvdWJsZSh0b3RhbC1hdmFpbGFibGUpLygxMDI0KjEwMjQqMTAyNCk7
IHJlc3VsdFsibWVtb3J5VG90YWxHaUIiXT1kb3VibGUodG90YWwpLygxMDI0KjEwMjQqMTAyNCk7
IHJlc3VsdFsibWVtb3J5UGVyY2VudCJdPTEwMC4wKih0b3RhbC1hdmFpbGFibGUpL3RvdGFsOyB9
CisgICAgaWYobWVtb3J5LmNvbnRhaW5zKCJTd2FwVG90YWw6IikpIHJlc3VsdFsic3dhcFVzZWRN
aUIiXT1kb3VibGUobWVtb3J5LnZhbHVlKCJTd2FwVG90YWw6IiktcU1pbihtZW1vcnkudmFsdWUo
IlN3YXBUb3RhbDoiKSxtZW1vcnkudmFsdWUoIlN3YXBGcmVlOiIpKSkvKDEwMjQqMTAyNCk7Cisg
ICAgZG91YmxlIGZyZXF1ZW5jeT1udW1iZXIocm9vdCsiL3N5cy9kZXZpY2VzL3N5c3RlbS9jcHUv
Y3B1MC9jcHVmcmVxL3NjYWxpbmdfY3VyX2ZyZXEiKTsgaWYoZnJlcXVlbmN5PjApIHJlc3VsdFsi
Y3B1TUh6Il09ZnJlcXVlbmN5LzEwMDA7CisgICAgZG91YmxlIHRlbXBlcmF0dXJlPS0xLCBmYW49
LTE7CisgICAgUURpciBodyhyb290KyIvc3lzL2NsYXNzL2h3bW9uIik7CisgICAgZm9yKGNvbnN0
IFFTdHJpbmcmIGRldmljZTpody5lbnRyeUxpc3QoUURpcjo6RGlyc3xRRGlyOjpOb0RvdEFuZERv
dERvdCkpIHsKKyAgICAgICAgUURpciBzZW5zb3JzKGh3LmZpbGVQYXRoKGRldmljZSkpOyBRU3Ry
aW5nIG5hbWU9cmVhZChzZW5zb3JzLmZpbGVQYXRoKCJuYW1lIikpOworICAgICAgICBmb3IoY29u
c3QgUVN0cmluZyYgZmlsZTpzZW5zb3JzLmVudHJ5TGlzdCh7InRlbXAqX2lucHV0IiwiZmFuKl9p
bnB1dCJ9LFFEaXI6OkZpbGVzKSkgeworICAgICAgICAgICAgZG91YmxlIHZhbHVlPW51bWJlcihz
ZW5zb3JzLmZpbGVQYXRoKGZpbGUpKTsKKyAgICAgICAgICAgIGlmKGZpbGUuc3RhcnRzV2l0aCgi
dGVtcCIpICYmIChuYW1lPT0iY29yZXRlbXAiIHx8IG5hbWU9PSJrMTB0ZW1wIikgJiYgdmFsdWU+
PTAgJiYgdmFsdWU8PTE1MDAwMCkgdGVtcGVyYXR1cmU9cU1heCh0ZW1wZXJhdHVyZSx2YWx1ZS8x
MDAwKTsKKyAgICAgICAgICAgIGlmKGZpbGUuc3RhcnRzV2l0aCgiZmFuIikgJiYgdmFsdWU+PTAg
JiYgdmFsdWU8MzAwMDApIGZhbj1xTWF4KGZhbix2YWx1ZSk7CisgICAgICAgIH0KKyAgICB9Cisg
ICAgaWYodGVtcGVyYXR1cmU+PTApIHJlc3VsdFsidGVtcGVyYXR1cmVDIl09dGVtcGVyYXR1cmU7
CisgICAgaWYoZmFuPj0wKSByZXN1bHRbImZhblJQTSJdPWZhbjsKKyAgICBRRGlyIGRybShyb290
KyIvc3lzL2NsYXNzL2RybSIpOworICAgIGZvcihjb25zdCBRU3RyaW5nJiBjYXJkOmRybS5lbnRy
eUxpc3QoeyJjYXJkWzAtOV0qIn0sUURpcjo6RGlyc3xRRGlyOjpOb0RvdEFuZERvdERvdCkpIHsg
ZG91YmxlIGJ1c3k9bnVtYmVyKGRybS5maWxlUGF0aChjYXJkKyIvZGV2aWNlL2dwdV9idXN5X3Bl
cmNlbnQiKSk7IGlmKGJ1c3k+PTAgJiYgYnVzeTw9MTAwKSB7IHJlc3VsdFsiZ3B1UGVyY2VudCJd
PWJ1c3k7IGJyZWFrOyB9IH0KKyAgICAvLyBEUk0gZmRpbmZvIGlzIHVucHJpdmlsZWdlZCwgcmVh
ZC1vbmx5IGFuZCBzY29wZWQgdG8gdGhpcyBFY2xpcHNlIHByb2Nlc3MuCisgICAgLy8gRGVkdXBs
aWNhdGUgZGVzY3JpcHRvcnMgYmVsb25naW5nIHRvIHRoZSBzYW1lIERSTSBjbGllbnQ7IG5ldmVy
IGNhbGwgdGhpcyBzeXN0ZW0td2lkZSBHUFUgbG9hZC4KKyAgICBxdWludDY0IHZpZGVvPTA7IGJv
b2wgaGFzVmlkZW89ZmFsc2U7IFFTZXQ8UVN0cmluZz4gY2xpZW50czsKKyAgICBRRGlyIGRlc2Ny
aXB0b3JzKHJvb3QrIi9wcm9jL3NlbGYvZmRpbmZvIik7CisgICAgaW50IGluc3BlY3RlZD0wOwor
ICAgIGZvcihjb25zdCBRU3RyaW5nJiBmaWxlOmRlc2NyaXB0b3JzLmVudHJ5TGlzdChRRGlyOjpG
aWxlcykpIHsKKyAgICAgICAgaWYoKytpbnNwZWN0ZWQ+MjU2KSBicmVhazsKKyAgICAgICAgUVN0
cmluZyBpbmZvPXJlYWQoZGVzY3JpcHRvcnMuZmlsZVBhdGgoZmlsZSkpOworICAgICAgICBhdXRv
IGNsaWVudD1RUmVndWxhckV4cHJlc3Npb24oImRybS1jbGllbnQtaWQ6XFxzKihcXGQrKSIpLm1h
dGNoKGluZm8pOworICAgICAgICBpZighY2xpZW50Lmhhc01hdGNoKCkgfHwgY2xpZW50cy5jb250
YWlucyhjbGllbnQuY2FwdHVyZWQoMSkpKSBjb250aW51ZTsKKyAgICAgICAgY2xpZW50cy5pbnNl
cnQoY2xpZW50LmNhcHR1cmVkKDEpKTsKKyAgICAgICAgYXV0byBlbmdpbmVzPVFSZWd1bGFyRXhw
cmVzc2lvbigiZHJtLWVuZ2luZS12aWRlbyg/OlxcZCspPzpcXHMqKFxcZCspXFxzK25zIikuZ2xv
YmFsTWF0Y2goaW5mbyk7CisgICAgICAgIHdoaWxlKGVuZ2luZXMuaGFzTmV4dCgpKSB7IHZpZGVv
Kz1lbmdpbmVzLm5leHQoKS5jYXB0dXJlZCgxKS50b1VMb25nTG9uZygpOyBoYXNWaWRlbz10cnVl
OyB9CisgICAgfQorICAgIGlmKGhhc1ZpZGVvKSB7CisgICAgICAgIGNvdW50ZXJzWyJ2aWRlbyJd
PXZpZGVvOworICAgICAgICBpZihvbGQuY29udGFpbnMoInZpZGVvIikgJiYgc2Vjb25kcz4wICYm
IHZpZGVvPj1vbGQudmFsdWUoInZpZGVvIikudG9VTG9uZ0xvbmcoKSkgcmVzdWx0WyJ2aWRlb1Bl
cmNlbnQiXT1xQm91bmQoMC4wLGRvdWJsZSh2aWRlby1vbGRbInZpZGVvIl0udG9VTG9uZ0xvbmco
KSkvc2Vjb25kcy8xMDAwMDAwMC4wLDEwMC4wKTsKKyAgICB9CisgICAgUVN0cmluZyBuaWM7Cisg
ICAgZm9yKGNvbnN0IFFTdHJpbmcmIGxpbmU6cmVhZChyb290KyIvcHJvYy9uZXQvcm91dGUiKS5z
cGxpdCgnXG4nKSkgeyBhdXRvIHA9bGluZS5zaW1wbGlmaWVkKCkuc3BsaXQoJyAnKTsgaWYocC5z
aXplKCk+MyAmJiBwWzFdPT0iMDAwMDAwMDAiKSB7IG5pYz1wWzBdOyBicmVhazsgfSB9CisgICAg
Zm9yKGNvbnN0IFFTdHJpbmcmIGxpbmU6cmVhZChyb290KyIvcHJvYy9uZXQvZGV2Iikuc3BsaXQo
J1xuJykpIHsKKyAgICAgICAgaWYobGluZS5zZWN0aW9uKCc6JywwLDApLnRyaW1tZWQoKSE9bmlj
IHx8IG5pYy5pc0VtcHR5KCkpIGNvbnRpbnVlOworICAgICAgICBhdXRvIHA9bGluZS5zZWN0aW9u
KCc6JywxKS5zaW1wbGlmaWVkKCkuc3BsaXQoJyAnKTsgaWYocC5zaXplKCk8MTYpIGNvbnRpbnVl
OworICAgICAgICBxdWludDY0IHJ4PXBbMF0udG9VTG9uZ0xvbmcoKSwgdHg9cFs4XS50b1VMb25n
TG9uZygpOyBjb3VudGVyc1sicngiXT1yeDsgY291bnRlcnNbInR4Il09dHg7IGNvdW50ZXJzWyJu
aWMiXT1uaWM7CisgICAgICAgIGlmKHNlY29uZHM+MCAmJiBvbGQudmFsdWUoIm5pYyIpLnRvU3Ry
aW5nKCk9PW5pYyAmJiByeD49b2xkLnZhbHVlKCJyeCIpLnRvVUxvbmdMb25nKCkgJiYgdHg+PW9s
ZC52YWx1ZSgidHgiKS50b1VMb25nTG9uZygpKSB7IHJlc3VsdFsicmVjZWl2ZU1pQiJdPWRvdWJs
ZShyeC1vbGRbInJ4Il0udG9VTG9uZ0xvbmcoKSkvc2Vjb25kcy8oMTAyNCoxMDI0KTsgcmVzdWx0
WyJ0cmFuc21pdE1pQiJdPWRvdWJsZSh0eC1vbGRbInR4Il0udG9VTG9uZ0xvbmcoKSkvc2Vjb25k
cy8oMTAyNCoxMDI0KTsgfQorICAgIH0KKyAgICBRRGlyIHBvd2VyKHJvb3QrIi9zeXMvY2xhc3Mv
cG93ZXJfc3VwcGx5Iik7CisgICAgZm9yKGNvbnN0IFFTdHJpbmcmIG5hbWU6cG93ZXIuZW50cnlM
aXN0KFFEaXI6OkRpcnN8UURpcjo6Tm9Eb3RBbmREb3REb3QpKSB7CisgICAgICAgIFFTdHJpbmcg
cGF0aD1wb3dlci5maWxlUGF0aChuYW1lKTsgaWYocmVhZChwYXRoKyIvdHlwZSIpIT0iQmF0dGVy
eSIpIGNvbnRpbnVlOworICAgICAgICBkb3VibGUgcGVyY2VudD1udW1iZXIocGF0aCsiL2NhcGFj
aXR5Iik7IGlmKHBlcmNlbnQ+PTAgJiYgcGVyY2VudDw9MTAwKSByZXN1bHRbImJhdHRlcnlQZXJj
ZW50Il09cGVyY2VudDsKKyAgICAgICAgcmVzdWx0WyJiYXR0ZXJ5U3RhdGUiXT1yZWFkKHBhdGgr
Ii9zdGF0dXMiKS5sZWZ0KDMyKTsgZG91YmxlIHdhdHRzPW51bWJlcihwYXRoKyIvcG93ZXJfbm93
Iik7IGlmKHdhdHRzPj0wKSByZXN1bHRbImJhdHRlcnlXYXR0cyJdPXdhdHRzLzEwMDAwMDA7IGJy
ZWFrOworICAgIH0KKyAgICBpZihyb290LmlzRW1wdHkoKSkgeyBRU3RvcmFnZUluZm8gZGlzaz1R
U3RvcmFnZUluZm86OnJvb3QoKTsgaWYoZGlzay5pc1ZhbGlkKCkgJiYgZGlzay5pc1JlYWR5KCkg
JiYgZGlzay5ieXRlc1RvdGFsKCk+MCkgeyByZXN1bHRbInN0b3JhZ2VUb3RhbEdpQiJdPWRvdWJs
ZShkaXNrLmJ5dGVzVG90YWwoKSkvKDEwMjQqMTAyNCoxMDI0KTsgcmVzdWx0WyJzdG9yYWdlRnJl
ZUdpQiJdPWRvdWJsZShkaXNrLmJ5dGVzQXZhaWxhYmxlKCkpLygxMDI0KjEwMjQqMTAyNCk7IH0g
fQorICAgIGlmKHJvb3QuaXNFbXB0eSgpKSB7CisgICAgICAgIFFTdHJpbmcgZGV2aWNlPVFGaWxl
SW5mbyhRU3RyaW5nOjpmcm9tVXRmOChRU3RvcmFnZUluZm86OnJvb3QoKS5kZXZpY2UoKSkpLmNh
bm9uaWNhbEZpbGVQYXRoKCkuc2VjdGlvbignLycsLTEpOworICAgICAgICBhdXRvIGlvPXJlYWQo
Ii9zeXMvY2xhc3MvYmxvY2svIitkZXZpY2UrIi9zdGF0Iikuc2ltcGxpZmllZCgpLnNwbGl0KCcg
Jyk7CisgICAgICAgIGlmKCFkZXZpY2UuaXNFbXB0eSgpICYmIGlvLnNpemUoKT49NykgeworICAg
ICAgICAgICAgcXVpbnQ2NCByZWFkcz1pb1syXS50b1VMb25nTG9uZygpLHdyaXRlcz1pb1s2XS50
b1VMb25nTG9uZygpOworICAgICAgICAgICAgY291bnRlcnNbImRpc2siXT1kZXZpY2U7Y291bnRl
cnNbInJlYWRzIl09cmVhZHM7Y291bnRlcnNbIndyaXRlcyJdPXdyaXRlczsKKyAgICAgICAgICAg
IGlmKHNlY29uZHM+MCAmJiBvbGQudmFsdWUoImRpc2siKS50b1N0cmluZygpPT1kZXZpY2UgJiYg
cmVhZHM+PW9sZC52YWx1ZSgicmVhZHMiKS50b1VMb25nTG9uZygpICYmIHdyaXRlcz49b2xkLnZh
bHVlKCJ3cml0ZXMiKS50b1VMb25nTG9uZygpKSB7CisgICAgICAgICAgICAgICAgcmVzdWx0WyJk
aXNrUmVhZE1pQiJdPWRvdWJsZShyZWFkcy1vbGRbInJlYWRzIl0udG9VTG9uZ0xvbmcoKSkqNTEy
L3NlY29uZHMvKDEwMjQqMTAyNCk7CisgICAgICAgICAgICAgICAgcmVzdWx0WyJkaXNrV3JpdGVN
aUIiXT1kb3VibGUod3JpdGVzLW9sZFsid3JpdGVzIl0udG9VTG9uZ0xvbmcoKSkqNTEyL3NlY29u
ZHMvKDEwMjQqMTAyNCk7CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgcHJl
dmlvdXNbcm9vdF09Y291bnRlcnM7IGxhc3Rbcm9vdF09bm93OyBjYWNoZWRbcm9vdF09cmVzdWx0
OyByZXR1cm4gcmVzdWx0OworfQorCitRU3RyaW5nIExvY2FsSGFyZHdhcmU6Om92ZXJsYXlUZXh0
KCkgeworICAgIGF1dG8gcj1zYW1wbGUoKTsgUVNldHRpbmdzIHM7IGF1dG8gZmllbGRzPXMudmFs
dWUoImVjbGlwc2UvbG9jYWxGaWVsZHMiLFFTdHJpbmdMaXN0eyJjcHUiLCJtZW1vcnkiLCJ0ZW1w
ZXJhdHVyZSIsImdwdSIsIm5ldHdvcmsiLCJiYXR0ZXJ5In0pLnRvU3RyaW5nTGlzdCgpOyBib29s
IGRldGFpbD1zLnZhbHVlKCJlY2xpcHNlL2xvY2FsRGV0YWlsZWQiLGZhbHNlKS50b0Jvb2woKTsK
KyAgICBRU3RyaW5nTGlzdCBsaW5lc3siRWNsaXBzZU9TIHwgTE9DQUwgTUFDIn07CisgICAgYXV0
byB2YWx1ZT1bJnJdKFFTdHJpbmcga2V5LFFTdHJpbmcgc3VmZml4LGludCBwcmVjaXNpb249MSkg
eyByZXR1cm4gci5jb250YWlucyhrZXkpID8gUVN0cmluZzo6bnVtYmVyKHJba2V5XS50b0RvdWJs
ZSgpLCdmJyxwcmVjaXNpb24pK3N1ZmZpeCA6IFFTdHJpbmcoIlVuYXZhaWxhYmxlIik7IH07Cisg
ICAgaWYoZmllbGRzLmNvbnRhaW5zKCJjcHUiKSkgeyBsaW5lczw8IkNQVSAgIit2YWx1ZSgiY3B1
UGVyY2VudCIsIiUiKTsgaWYoZGV0YWlsKSBsaW5lczw8IkNQVSBjbG9jayAgIit2YWx1ZSgiY3B1
TUh6IiwiIE1IeiIsMCk7IH0KKyAgICBpZihmaWVsZHMuY29udGFpbnMoIm1lbW9yeSIpKSB7IGxp
bmVzPDwiUkFNICAiK3ZhbHVlKCJtZW1vcnlVc2VkR2lCIiwiIEdpQiIpKyIgLyAiK3ZhbHVlKCJt
ZW1vcnlUb3RhbEdpQiIsIiBHaUIiKTsgaWYoZGV0YWlsKSBsaW5lczw8IlN3YXAgICIrdmFsdWUo
InN3YXBVc2VkTWlCIiwiIE1pQiIpOyB9CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJ0ZW1wZXJh
dHVyZSIpKSB7IGxpbmVzPDwiQ1BVIHRlbXBlcmF0dXJlICAiK3ZhbHVlKCJ0ZW1wZXJhdHVyZUMi
LCIgQyIpOyBpZihkZXRhaWwpIGxpbmVzPDwiRmFuICAiK3ZhbHVlKCJmYW5SUE0iLCIgUlBNIiww
KTsgfQorICAgIGlmKGZpZWxkcy5jb250YWlucygiZ3B1IikpIHsgbGluZXM8PCJHUFUgYnVzeSAg
Iit2YWx1ZSgiZ3B1UGVyY2VudCIsIiUiKTsgbGluZXM8PCJFY2xpcHNlIHZpZGVvIGVuZ2luZSAg
Iit2YWx1ZSgidmlkZW9QZXJjZW50IiwiJSIpOyB9CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJu
ZXR3b3JrIikpIGxpbmVzPDwiTmV0d29yayAgZG93biAiK3ZhbHVlKCJyZWNlaXZlTWlCIiwiIE1p
Qi9zIikrIiB8IHVwICIrdmFsdWUoInRyYW5zbWl0TWlCIiwiIE1pQi9zIik7CisgICAgaWYoZmll
bGRzLmNvbnRhaW5zKCJiYXR0ZXJ5IikpIHsgbGluZXM8PCJCYXR0ZXJ5ICAiK3ZhbHVlKCJiYXR0
ZXJ5UGVyY2VudCIsIiUiLDApOyBpZihkZXRhaWwpIGxpbmVzPDwiQmF0dGVyeSBwb3dlciAgIit2
YWx1ZSgiYmF0dGVyeVdhdHRzIiwiIFciKTsgfQorICAgIGlmKGZpZWxkcy5jb250YWlucygic3Rv
cmFnZSIpKSB7IGxpbmVzPDwiVVNCL3Jvb3QgZnJlZSAgIit2YWx1ZSgic3RvcmFnZUZyZWVHaUIi
LCIgR2lCIik7IGlmKGRldGFpbCkgbGluZXM8PCJSb290IEkvTyAgcmVhZCAiK3ZhbHVlKCJkaXNr
UmVhZE1pQiIsIiBNaUIvcyIpKyIgfCB3cml0ZSAiK3ZhbHVlKCJkaXNrV3JpdGVNaUIiLCIgTWlC
L3MiKTsgfQorICAgIHJldHVybiBsaW5lcy5qb2luKCdcbicpOworfQorc3RhdGljIHZvaWQgcmVn
aXN0ZXJMb2NhbEhhcmR3YXJlKCkgeyBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGU8TG9jYWxIYXJk
d2FyZT4oIkxvY2FsSGFyZHdhcmUiLDEsMCwiTG9jYWxIYXJkd2FyZSIsW10oUVFtbEVuZ2luZSos
UUpTRW5naW5lKiktPlFPYmplY3Qqe3JldHVybiBuZXcgTG9jYWxIYXJkd2FyZSgpO30pOyB9CitR
X0NPUkVBUFBfU1RBUlRVUF9GVU5DVElPTihyZWdpc3RlckxvY2FsSGFyZHdhcmUpCmRpZmYgLS1n
aXQgYS9hcHAvbW9vbmxpZ2h0b3MvbG9jYWxoYXJkd2FyZS5oIGIvYXBwL21vb25saWdodG9zL2xv
Y2FsaGFyZHdhcmUuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi42YjZlYWE2
Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuaApAQCAt
MCwwICsxLDU1IEBACisjcHJhZ21hIG9uY2UKKyNpbmNsdWRlIDxRT2JqZWN0PgorI2luY2x1ZGUg
PFFWYXJpYW50TWFwPgorI2luY2x1ZGUgPFFWYXJpYW50TGlzdD4KKyNpbmNsdWRlIDxRVGltZXI+
CisjaW5jbHVkZSA8UVNldHRpbmdzPgorI2luY2x1ZGUgPFFTZXQ+CisKK2NsYXNzIExvY2FsSGFy
ZHdhcmUgOiBwdWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpFQ1QKKyAgICBRX1BST1BFUlRZKFFW
YXJpYW50TWFwIHJlYWRpbmdzIFJFQUQgcmVhZGluZ3MgTk9USUZZIGNoYW5nZWQpCisgICAgUV9Q
Uk9QRVJUWShRVmFyaWFudExpc3QgaGlzdG9yeSBSRUFEIGhpc3RvcnkgTk9USUZZIGNoYW5nZWQp
CisgICAgUV9QUk9QRVJUWShib29sIG92ZXJsYXkgUkVBRCBvdmVybGF5IFdSSVRFIHNldE92ZXJs
YXkgTk9USUZZIHByZWZlcmVuY2VzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgZGV0YWls
ZWQgUkVBRCBkZXRhaWxlZCBXUklURSBzZXREZXRhaWxlZCBOT1RJRlkgcHJlZmVyZW5jZXNDaGFu
Z2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBzdHJlYW1EZXRhaWxlZCBSRUFEIHN0cmVhbURldGFp
bGVkIFdSSVRFIHNldFN0cmVhbURldGFpbGVkIE5PVElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCisg
ICAgUV9QUk9QRVJUWShpbnQgcG9zaXRpb24gUkVBRCBwb3NpdGlvbiBXUklURSBzZXRQb3NpdGlv
biBOT1RJRlkgcHJlZmVyZW5jZXNDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoaW50IG9wYWNpdHkg
UkVBRCBvcGFjaXR5IFdSSVRFIHNldE9wYWNpdHkgTk9USUZZIHByZWZlcmVuY2VzQ2hhbmdlZCkK
KyAgICBRX1BST1BFUlRZKGludCByZWZyZXNoU2Vjb25kcyBSRUFEIHJlZnJlc2hTZWNvbmRzIFdS
SVRFIHNldFJlZnJlc2hTZWNvbmRzIE5PVElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCisgICAgUV9Q
Uk9QRVJUWShRU3RyaW5nTGlzdCBmaWVsZHMgUkVBRCBmaWVsZHMgV1JJVEUgc2V0RmllbGRzIE5P
VElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCitwdWJsaWM6CisgICAgZXhwbGljaXQgTG9jYWxIYXJk
d2FyZShRT2JqZWN0KiBwYXJlbnQ9bnVsbHB0cik7CisgICAgUVZhcmlhbnRNYXAgcmVhZGluZ3Mo
KSBjb25zdCB7IHJldHVybiBtX3JlYWRpbmdzOyB9CisgICAgUVZhcmlhbnRMaXN0IGhpc3Rvcnko
KSBjb25zdCB7IHJldHVybiBtX2hpc3Rvcnk7IH0KKyAgICBib29sIG92ZXJsYXkoKSBjb25zdCB7
IHJldHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9sb2NhbE92ZXJsYXkiLGZhbHNlKS50
b0Jvb2woKTsgfQorICAgIGJvb2wgZGV0YWlsZWQoKSBjb25zdCB7IHJldHVybiBRU2V0dGluZ3Mo
KS52YWx1ZSgiZWNsaXBzZS9sb2NhbERldGFpbGVkIixmYWxzZSkudG9Cb29sKCk7IH0KKyAgICBi
b29sIHN0cmVhbURldGFpbGVkKCkgY29uc3QgeyByZXR1cm4gUVNldHRpbmdzKCkudmFsdWUoImVj
bGlwc2Uvc3RyZWFtRGV0YWlsZWQiLGZhbHNlKS50b0Jvb2woKTsgfQorICAgIGludCBwb3NpdGlv
bigpIGNvbnN0IHsgcmV0dXJuIHFCb3VuZCgwLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xv
Y2FsUG9zaXRpb24iLDEpLnRvSW50KCksMyk7IH0KKyAgICBpbnQgb3BhY2l0eSgpIGNvbnN0IHsg
cmV0dXJuIHFCb3VuZCg0MCxRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9vdmVybGF5T3BhY2l0
eSIsODUpLnRvSW50KCksMTAwKTsgfQorICAgIGludCByZWZyZXNoU2Vjb25kcygpIGNvbnN0IHsg
cmV0dXJuIHFCb3VuZCgxLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2hhcmR3YXJlUmVmcmVz
aCIsMikudG9JbnQoKSw1KTsgfQorICAgIFFTdHJpbmdMaXN0IGZpZWxkcygpIGNvbnN0IHsgcmV0
dXJuIFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2FsRmllbGRzIixRU3RyaW5nTGlzdHsi
Y3B1IiwibWVtb3J5IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3JrIiwiYmF0dGVyeSJ9KS50
b1N0cmluZ0xpc3QoKTsgfQorICAgIHZvaWQgc2V0T3ZlcmxheShib29sIHYpIHsgc2F2ZSgibG9j
YWxPdmVybGF5Iix2KTsgfQorICAgIHZvaWQgc2V0RGV0YWlsZWQoYm9vbCB2KSB7IHNhdmUoImxv
Y2FsRGV0YWlsZWQiLHYpOyB9CisgICAgdm9pZCBzZXRTdHJlYW1EZXRhaWxlZChib29sIHYpIHsg
c2F2ZSgic3RyZWFtRGV0YWlsZWQiLHYpOyB9CisgICAgdm9pZCBzZXRQb3NpdGlvbihpbnQgdikg
eyBzYXZlKCJsb2NhbFBvc2l0aW9uIixxQm91bmQoMCx2LDMpKTsgfQorICAgIHZvaWQgc2V0T3Bh
Y2l0eShpbnQgdikgeyBzYXZlKCJvdmVybGF5T3BhY2l0eSIscUJvdW5kKDQwLHYsMTAwKSk7IH0K
KyAgICB2b2lkIHNldFJlZnJlc2hTZWNvbmRzKGludCB2KSB7IHNhdmUoImhhcmR3YXJlUmVmcmVz
aCIscUJvdW5kKDEsdiw1KSk7IG1fdGltZXIuc2V0SW50ZXJ2YWwocmVmcmVzaFNlY29uZHMoKSox
MDAwKTsgfQorICAgIHZvaWQgc2V0RmllbGRzKFFTdHJpbmdMaXN0IHYpOworICAgIFFfSU5WT0tB
QkxFIHZvaWQgc2V0QWN0aXZlKGJvb2wgYWN0aXZlKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIHNl
dENvbnN1bWVyQWN0aXZlKFFPYmplY3QqIGNvbnN1bWVyLGJvb2wgYWN0aXZlKTsKKyAgICBzdGF0
aWMgUVZhcmlhbnRNYXAgc2FtcGxlKGNvbnN0IFFTdHJpbmcmIHJvb3Q9UVN0cmluZygpKTsKKyAg
ICBzdGF0aWMgUVN0cmluZyBvdmVybGF5VGV4dCgpOworc2lnbmFsczoKKyAgICB2b2lkIGNoYW5n
ZWQoKTsKKyAgICB2b2lkIHByZWZlcmVuY2VzQ2hhbmdlZCgpOworcHJpdmF0ZToKKyAgICB2b2lk
IHJlZnJlc2goKTsKKyAgICB2b2lkIHVwZGF0ZVNhbXBsaW5nKCk7CisgICAgYm9vbCBtX2xlZ2Fj
eUFjdGl2ZT1mYWxzZTsKKyAgICB2b2lkIHNhdmUoUVN0cmluZyBrZXksIFFWYXJpYW50IHZhbHVl
KSB7IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlLyIra2V5LHZhbHVlKTsgZW1pdCBwcmVm
ZXJlbmNlc0NoYW5nZWQoKTsgfQorICAgIFFTZXQ8UU9iamVjdCo+IG1fY29uc3VtZXJzOworICAg
IFFTZXQ8UU9iamVjdCo+IG1fa25vd25Db25zdW1lcnM7CisgICAgUVRpbWVyIG1fdGltZXI7Cisg
ICAgUVZhcmlhbnRNYXAgbV9yZWFkaW5nczsKKyAgICBRVmFyaWFudExpc3QgbV9oaXN0b3J5Owor
fTsKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9tYW5hZ2VkdXBkYXRlcy5jcHAgYi9hcHAv
bW9vbmxpZ2h0b3MvbWFuYWdlZHVwZGF0ZXMuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4
IDAwMDAwMDAuLjJiZmNiZmQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvbWFu
YWdlZHVwZGF0ZXMuY3BwCkBAIC0wLDAgKzEsMTMyIEBACisvLyBFY2xpcHNlT1Mgb3ducyB0aGlz
IGN1c3RvbWl6ZWQgbmF0aXZlIGNsaWVudC4gTm8gZmVlZCByZXF1ZXN0cywgYXNzZXQKKy8vIGRv
d25sb2Fkcywgc3dhcHMgb3IgcmVsYXVuY2hlcyBhcmUgY29tcGlsZWQgaW50byB0aGlzIHVwZGF0
ZSBpbXBsZW1lbnRhdGlvbi4KKyNpbmNsdWRlICIuLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2Vy
LmgiCisjaW5jbHVkZSA8UUNvcmVBcHBsaWNhdGlvbj4KKyNpbmNsdWRlIDxRSnNvbk9iamVjdD4K
Kworc3RhdGljIFFTdHJpbmcgc3RyaXBCdWlsZE1ldGFkYXRhKGNvbnN0IFFTdHJpbmcmIHZlcnNp
b24pCit7CisgICAgaW50IHBsdXNJZHggPSB2ZXJzaW9uLmluZGV4T2YoJysnKTsKKyAgICByZXR1
cm4gcGx1c0lkeCA+PSAwID8gdmVyc2lvbi5sZWZ0KHBsdXNJZHgpIDogdmVyc2lvbjsKK30KKwor
c3RhdGljIGJvb2wgaXNOdW1lcmljSWRlbnRpZmllcihjb25zdCBRU3RyaW5nJiBzKQoreworICAg
IGlmIChzLmlzRW1wdHkoKSkgeworICAgICAgICByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIGZv
ciAoY29uc3QgUUNoYXImIGMgOiBzKSB7CisgICAgICAgIGlmICghYy5pc0RpZ2l0KCkpIHsKKyAg
ICAgICAgICAgIHJldHVybiBmYWxzZTsKKyAgICAgICAgfQorICAgIH0KKyAgICByZXR1cm4gdHJ1
ZTsKK30KKworaW50IEF1dG9VcGRhdGVDaGVja2VyOjpjb21wYXJlU2VtYW50aWNWZXJzaW9ucyhj
b25zdCBRU3RyaW5nJiB2MSwgY29uc3QgUVN0cmluZyYgdjIpCit7CisgICAgUVN0cmluZyBzMSA9
IHN0cmlwQnVpbGRNZXRhZGF0YSh2MSk7CisgICAgUVN0cmluZyBzMiA9IHN0cmlwQnVpbGRNZXRh
ZGF0YSh2Mik7CisKKyAgICBpbnQgZGFzaDEgPSBzMS5pbmRleE9mKCctJyk7CisgICAgaW50IGRh
c2gyID0gczIuaW5kZXhPZignLScpOworICAgIFFTdHJpbmcgYmFzZTEgPSBkYXNoMSA+PSAwID8g
czEubGVmdChkYXNoMSkgOiBzMTsKKyAgICBRU3RyaW5nIGJhc2UyID0gZGFzaDIgPj0gMCA/IHMy
LmxlZnQoZGFzaDIpIDogczI7CisgICAgUVN0cmluZyBwcmUxID0gZGFzaDEgPj0gMCA/IHMxLm1p
ZChkYXNoMSArIDEpIDogUVN0cmluZygpOworICAgIFFTdHJpbmcgcHJlMiA9IGRhc2gyID49IDAg
PyBzMi5taWQoZGFzaDIgKyAxKSA6IFFTdHJpbmcoKTsKKworICAgIC8vIE51bWVyaWMgYmFzZSB2
ZXJzaW9ucyBjb21wYXJlIGZpcnN0ICgwLjQuMC1iZXRhLjAwMSA+IDAuMy4wKQorICAgIGNvbnN0
IFFTdHJpbmdMaXN0IGJhc2VQYXJ0czEgPSBiYXNlMS5zcGxpdCgnLicpOworICAgIGNvbnN0IFFT
dHJpbmdMaXN0IGJhc2VQYXJ0czIgPSBiYXNlMi5zcGxpdCgnLicpOworICAgIGZvciAoaW50IGkg
PSAwOyBpIDwgcU1heChiYXNlUGFydHMxLmNvdW50KCksIGJhc2VQYXJ0czIuY291bnQoKSk7IGkr
KykgeworICAgICAgICBxbG9uZ2xvbmcgYjEgPSBpIDwgYmFzZVBhcnRzMS5jb3VudCgpID8gYmFz
ZVBhcnRzMVtpXS50b0xvbmdMb25nKCkgOiAwOworICAgICAgICBxbG9uZ2xvbmcgYjIgPSBpIDwg
YmFzZVBhcnRzMi5jb3VudCgpID8gYmFzZVBhcnRzMltpXS50b0xvbmdMb25nKCkgOiAwOworICAg
ICAgICBpZiAoYjEgIT0gYjIpIHsKKyAgICAgICAgICAgIHJldHVybiBiMSA8IGIyID8gLTEgOiAx
OworICAgICAgICB9CisgICAgfQorCisgICAgLy8gRXF1YWwgYmFzZTogYSByZWxlYXNlIHdpdGgg
bm8gcHJlcmVsZWFzZSBzdWZmaXggb3V0cmFua3MgYW55IHByZXJlbGVhc2UKKyAgICBpZiAocHJl
MS5pc0VtcHR5KCkgIT0gcHJlMi5pc0VtcHR5KCkpIHsKKyAgICAgICAgcmV0dXJuIHByZTEuaXNF
bXB0eSgpID8gMSA6IC0xOworICAgIH0KKyAgICBpZiAocHJlMS5pc0VtcHR5KCkpIHsKKyAgICAg
ICAgcmV0dXJuIDA7CisgICAgfQorCisgICAgLy8gVHdvIHByZXJlbGVhc2VzOiBjb21wYXJlIGRv
dC1zZXBhcmF0ZWQgaWRlbnRpZmllcnMgbGVmdCB0byByaWdodC4KKyAgICAvLyBOdW1lcmljIGlk
ZW50aWZpZXJzIGNvbXBhcmUgbnVtZXJpY2FsbHkgKGxlYWRpbmcgemVyb3MgdG9sZXJhdGVkIOKA
lCBvdXIKKyAgICAvLyBDSSB6ZXJvLXBhZHMgY291bnRlcnMpLCBhbHBoYW51bWVyaWMgb25lcyBs
ZXhpY2FsbHkgaW4gQVNDSUkgb3JkZXIsIGFuZAorICAgIC8vIG51bWVyaWMgYWx3YXlzIHJhbmtz
IGJlbG93IGFscGhhbnVtZXJpYy4gVGhpcyBpcyB3aGF0IG9yZGVycworICAgIC8vICJhbHBoYSIg
PCAiYmV0YSIgPCAicmMiIGF0IGFuIGVxdWFsIGJhc2Ug4oCUIHRoZSBwcm9wZXJ0eSB0aGUgcHJl
dmlvdXMKKyAgICAvLyBpbXBsZW1lbnRhdGlvbiBsYWNrZWQgKGl0IHNraXBwZWQgdGhlIHdvcmRz
IGFuZCBjb21wYXJlZCBvbmx5IG51bWJlcnMsCisgICAgLy8gc28gMC4zLjAtYmV0YS4wMDggd3Jv
bmdseSBvdXRyYW5rZWQgMC4zLjAtcmMuMDAyKS4KKyAgICBjb25zdCBRU3RyaW5nTGlzdCBpZHMx
ID0gcHJlMS5zcGxpdCgnLicpOworICAgIGNvbnN0IFFTdHJpbmdMaXN0IGlkczIgPSBwcmUyLnNw
bGl0KCcuJyk7CisgICAgZm9yIChpbnQgaSA9IDA7IGkgPCBxTWF4KGlkczEuY291bnQoKSwgaWRz
Mi5jb3VudCgpKTsgaSsrKSB7CisgICAgICAgIGlmIChpID49IGlkczEuY291bnQoKSkgeworICAg
ICAgICAgICAgLy8gRXF1YWwgcHJlZml4LCBmZXdlciBmaWVsZHMgPSBsb3dlciBwcmVjZWRlbmNl
ICjCpzExLjQuNCkKKyAgICAgICAgICAgIHJldHVybiAtMTsKKyAgICAgICAgfQorICAgICAgICBp
ZiAoaSA+PSBpZHMyLmNvdW50KCkpIHsKKyAgICAgICAgICAgIHJldHVybiAxOworICAgICAgICB9
CisgICAgICAgIGJvb2wgbnVtMSA9IGlzTnVtZXJpY0lkZW50aWZpZXIoaWRzMVtpXSk7CisgICAg
ICAgIGJvb2wgbnVtMiA9IGlzTnVtZXJpY0lkZW50aWZpZXIoaWRzMltpXSk7CisgICAgICAgIGlm
IChudW0xICYmIG51bTIpIHsKKyAgICAgICAgICAgIHFsb25nbG9uZyBwMSA9IGlkczFbaV0udG9M
b25nTG9uZygpOworICAgICAgICAgICAgcWxvbmdsb25nIHAyID0gaWRzMltpXS50b0xvbmdMb25n
KCk7CisgICAgICAgICAgICBpZiAocDEgIT0gcDIpIHsKKyAgICAgICAgICAgICAgICByZXR1cm4g
cDEgPCBwMiA/IC0xIDogMTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgICAgICBlbHNl
IGlmIChudW0xICE9IG51bTIpIHsKKyAgICAgICAgICAgIC8vIE51bWVyaWMgaWRlbnRpZmllcnMg
cmFuayBiZWxvdyBhbHBoYW51bWVyaWMgb25lcyAowqcxMS40LjMpCisgICAgICAgICAgICByZXR1
cm4gbnVtMSA/IC0xIDogMTsKKyAgICAgICAgfQorICAgICAgICBlbHNlIHsKKyAgICAgICAgICAg
IGludCBjbXAgPSBRU3RyaW5nOjpjb21wYXJlKGlkczFbaV0sIGlkczJbaV0pOworICAgICAgICAg
ICAgaWYgKGNtcCAhPSAwKSB7CisgICAgICAgICAgICAgICAgcmV0dXJuIGNtcCA8IDAgPyAtMSA6
IDE7CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgcmV0dXJuIDA7Cit9CisK
K0F1dG9VcGRhdGVDaGVja2VyOjpBdXRvVXBkYXRlQ2hlY2tlcihRT2JqZWN0KiBwYXJlbnQpIDoK
KyAgICBRT2JqZWN0KHBhcmVudCksIG1fQ2hlY2tJbkZsaWdodChmYWxzZSksIG1fQ2hlY2tJc01h
bnVhbChmYWxzZSksCisgICAgbV9VcGRhdGVBdmFpbGFibGUoZmFsc2UpLCBtX09mZmVyQXZhaWxh
YmxlKGZhbHNlKSwgbV9JbnN0YWxsaW5nKGZhbHNlKQoreworICAgIGNsZWFyT2ZmZXIoKTsKKyAg
ICBzZXRTdGF0dXModHIoIiUxLiBVcGRhdGVzIGFyZSBtYW5hZ2VkIGJ5IEVjbGlwc2VPUy4gR2V0
IHRoZSBtYXRjaGluZyBPUyBpbWFnZSBmcm9tICUyOyB1cHN0cmVhbSBWaWJlbWlzIHVwZGF0ZXMg
YXJlIGRpc2FibGVkLiIpLmFyZyhjdXJyZW50VmVyc2lvbigpLCBtX1JlbGVhc2VVcmwpKTsKK30K
K1FTdHJpbmcgQXV0b1VwZGF0ZUNoZWNrZXI6OmN1cnJlbnRWZXJzaW9uKCkgY29uc3QKK3sKKyAg
ICByZXR1cm4gdHIoIkVjbGlwc2UgJTEgwrcgRWNsaXBzZU9TIGN1c3RvbWl6ZWQiKS5hcmcoUUNv
cmVBcHBsaWNhdGlvbjo6YXBwbGljYXRpb25WZXJzaW9uKCkpOworfQordm9pZCBBdXRvVXBkYXRl
Q2hlY2tlcjo6Y2xlYXJPZmZlcigpCit7CisgICAgbV9VcGRhdGVBdmFpbGFibGUgPSBmYWxzZTsg
bV9PZmZlckF2YWlsYWJsZSA9IGZhbHNlOworICAgIG1fT2ZmZXJWZXJzaW9uLmNsZWFyKCk7IG1f
QXNzZXRVcmwuY2xlYXIoKTsgbV9PZmZlclRpZXIgPSAtMTsKKyAgICBtX1JlbGVhc2VVcmwgPSBR
U3RyaW5nTGl0ZXJhbCgiaHR0cHM6Ly9naXRodWIuY29tL3RoM2QzY2szci9Nb29ubGlnaHQtT1Mv
cmVsZWFzZXMiKTsKK30KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6OnNldFN0YXR1cyhjb25zdCBR
U3RyaW5nJiBtZXNzYWdlKQoreworICAgIGlmIChtX1N0YXR1c01lc3NhZ2UgIT0gbWVzc2FnZSkg
eyBtX1N0YXR1c01lc3NhZ2UgPSBtZXNzYWdlOyBlbWl0IHN0YXRlQ2hhbmdlZCgpOyB9Cit9Cit2
b2lkIEF1dG9VcGRhdGVDaGVja2VyOjpzdGFydCgpIHsgLyogTm8gdGltZXIgYW5kIG5vIGJhY2tn
cm91bmQgdXBkYXRlIHJlcXVlc3RzLiAqLyB9Citib29sIEF1dG9VcGRhdGVDaGVja2VyOjpjYW5J
bnN0YWxsVXBkYXRlcygpIGNvbnN0IHsgcmV0dXJuIGZhbHNlOyB9Citib29sIEF1dG9VcGRhdGVD
aGVja2VyOjpjYW5JbnN0YWxsKCkgY29uc3QgeyByZXR1cm4gZmFsc2U7IH0KK3ZvaWQgQXV0b1Vw
ZGF0ZUNoZWNrZXI6OmNoYW5uZWxDaGFuZ2VkKCkgeyBjaGVja05vdygpOyB9Cit2b2lkIEF1dG9V
cGRhdGVDaGVja2VyOjpjaGVja05vdygpCit7CisgICAgY2xlYXJPZmZlcigpOworICAgIHNldFN0
YXR1cyh0cigiVXBkYXRlcyBhcmUgbWFuYWdlZCBieSBFY2xpcHNlT1MuIERvd25sb2FkIHRoZSBt
YXRjaGluZyBPUyBpbWFnZSBmcm9tICUxLiBUaGlzIGNsaWVudCBuZXZlciBpbnN0YWxscyB1cHN0
cmVhbSBWaWJlbWlzIHJlbGVhc2VzLiIpLmFyZyhtX1JlbGVhc2VVcmwpKTsKKyAgICBlbWl0IHN0
YXRlQ2hhbmdlZCgpOyBlbWl0IGNoZWNrQ29tcGxldGVkKHRydWUsIGZhbHNlKTsKK30KK3ZvaWQg
QXV0b1VwZGF0ZUNoZWNrZXI6Omluc3RhbGwoKQoreworICAgIGNoZWNrTm93KCk7CisgICAgZW1p
dCBpbnN0YWxsRmFpbGVkKHRyKCJTdGFuZGFsb25lIFZpYmVtaXMgaW5zdGFsbGF0aW9uIGlzIGRp
c2FibGVkIGluIEVjbGlwc2VPUy4iKSwgbV9SZWxlYXNlVXJsKTsKK30KZGlmZiAtLWdpdCBhL2Fw
cC9tb29ubGlnaHRvcy9vdmVybGF5c3R5bGUuaCBiL2FwcC9tb29ubGlnaHRvcy9vdmVybGF5c3R5
bGUuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi45MTFhNWMzCi0tLSAvZGV2
L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL292ZXJsYXlzdHlsZS5oCkBAIC0wLDAgKzEsMjIg
QEAKKyNwcmFnbWEgb25jZQorI2luY2x1ZGUgPFFJbWFnZT4KKyNpbmNsdWRlIDxRUGFpbnRlcj4K
KyNpbmNsdWRlIDxRQ29sb3I+CisjaW5jbHVkZSA8UUxpbmVhckdyYWRpZW50PgorbmFtZXNwYWNl
IEVjbGlwc2VPdmVybGF5U3R5bGUgeworaW5saW5lIFFDb2xvciBhY2NlbnQoaW50IGluZGV4KSB7
CisgICAgY29uc3QgY2hhciogY29sb3JzW109eyIjMDBDQ0NDIiwiIzdDOENGOCIsIiMzRUQ1OTgi
LCIjRjBBODY4IiwiI0RDMzY1OCIsIiNGMjVENjQiLCIjRjU4MzQ3IiwiI0YxQkM0NSIsIiNCN0RD
NjMiLCIjNjNDQ0FFIiwiIzYzQzRFRCIsIiM2QzlGRkYiLCIjQUQ4NUY1IiwiI0U5NzZCQyIsIiND
QUQwREEiLCIjRDk5NUFDIn07CisgICAgcmV0dXJuIFFDb2xvcihjb2xvcnNbcUJvdW5kKDAsaW5k
ZXgsMTUpXSk7Cit9CitpbmxpbmUgUUltYWdlIHBhbmVsKFFTaXplIHNpemUsaW50IGFjY2VudElu
ZGV4LGludCBvcGFjaXR5KSB7CisgICAgaWYoc2l6ZS53aWR0aCgpPDMyIHx8IHNpemUuaGVpZ2h0
KCk8MzIgfHwgc2l6ZS53aWR0aCgpPjIwNDggfHwgc2l6ZS5oZWlnaHQoKT40MDk2KSByZXR1cm4g
e307CisgICAgUUltYWdlIGltYWdlKHNpemUsUUltYWdlOjpGb3JtYXRfUkdCQTg4ODgpOyBpbWFn
ZS5maWxsKFF0Ojp0cmFuc3BhcmVudCk7CisgICAgUVBhaW50ZXIgcGFpbnRlcigmaW1hZ2UpOyBw
YWludGVyLnNldFJlbmRlckhpbnQoUVBhaW50ZXI6OkFudGlhbGlhc2luZyk7CisgICAgUUNvbG9y
IGJnKCIjMTUxMTE1Iik7IGJnLnNldEFscGhhKHFCb3VuZCg0MCxvcGFjaXR5LDEwMCkqMjU1LzEw
MCk7CisgICAgUUxpbmVhckdyYWRpZW50IGdsYXNzKDAsMCwwLHNpemUuaGVpZ2h0KCkpO1FDb2xv
ciBzaGluZSgiIzI5MjQyQiIpO3NoaW5lLnNldEFscGhhKGJnLmFscGhhKCkpO2dsYXNzLnNldENv
bG9yQXQoMCxzaGluZSk7Z2xhc3Muc2V0Q29sb3JBdCgxLGJnKTsKKyAgICBwYWludGVyLnNldEJy
dXNoKGdsYXNzKTsgcGFpbnRlci5zZXRQZW4oUVBlbihRQ29sb3IoMjU1LDI1NSwyNTUsNDgpLDEp
KTsKKyAgICBwYWludGVyLmRyYXdSb3VuZGVkUmVjdChRUmVjdEYoMSwxLGltYWdlLndpZHRoKCkt
MixpbWFnZS5oZWlnaHQoKS0yKSwxOCwxOCk7CisgICAgcGFpbnRlci5zZXRQZW4oUVBlbihhY2Nl
bnQoYWNjZW50SW5kZXgpLDMpKTsgcGFpbnRlci5kcmF3TGluZSgxNSw4LGltYWdlLndpZHRoKCkt
MTUsOCk7CisgICAgcmV0dXJuIGltYWdlOworfQorfQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdo
dG9zL3N5c3RlbWNvbnRyb2xzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5j
cHAKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uM2VlM2ZmOQotLS0gL2Rldi9u
dWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAKQEAgLTAsMCArMSw4
MiBAQAorI2luY2x1ZGUgInN5c3RlbWNvbnRyb2xzLmgiCisjaW5jbHVkZSA8UUNvcmVBcHBsaWNh
dGlvbj4KKyNpbmNsdWRlIDxRSnNvbkRvY3VtZW50PgorI2luY2x1ZGUgPFFKc29uT2JqZWN0Pgor
I2luY2x1ZGUgPFFKc29uQXJyYXk+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNsdWRlIDxR
RmlsZUluZm8+CitTeXN0ZW1Db250cm9sczo6U3lzdGVtQ29udHJvbHMoUU9iamVjdCogcGFyZW50
KSA6IFFPYmplY3QocGFyZW50KSB7CisgICAgbV90aW1lb3V0LnNldFNpbmdsZVNob3QodHJ1ZSk7
CisgICAgY29ubmVjdCgmbV90aW1lb3V0LCAmUVRpbWVyOjp0aW1lb3V0LCB0aGlzLCBbdGhpc10g
eyBmYWlsKHRyKCJPcGVyYXRpb24gdGltZWQgb3V0LiBSZXRyeSBvciB1c2UgdGhlIGRpYWdub3N0
aWMgc2hlbGwuIikpOyB9KTsKKyAgICBjb25uZWN0KCZtX3Byb2Nlc3MsICZRUHJvY2Vzczo6c3Rh
cnRlZCwgdGhpcywgW3RoaXNdIHsgcmVxdWVzdChtX21vZGUgKyAiLWxpc3QiKTsgfSk7CisgICAg
Y29ubmVjdCgmbV9wcm9jZXNzLCAmUVByb2Nlc3M6OnJlYWR5UmVhZFN0YW5kYXJkRXJyb3IsIHRo
aXMsIFt0aGlzXSB7IG1fcHJvY2Vzcy5yZWFkQWxsU3RhbmRhcmRFcnJvcigpOyB9KTsKKyAgICBj
b25uZWN0KCZtX3Byb2Nlc3MsICZRUHJvY2Vzczo6cmVhZHlSZWFkU3RhbmRhcmRPdXRwdXQsIHRo
aXMsIFt0aGlzXSB7CisgICAgICAgIG1fYnVmZmVyICs9IG1fcHJvY2Vzcy5yZWFkQWxsU3RhbmRh
cmRPdXRwdXQoKTsKKyAgICAgICAgaWYgKG1fYnVmZmVyLnNpemUoKSA+IDY1NTM2KSB7IGZhaWwo
dHIoIkludmFsaWQgc3lzdGVtIHJlc3BvbnNlLiIpKTsgcmV0dXJuOyB9CisgICAgICAgIHdoaWxl
IChtX2J1ZmZlci5jb250YWlucygnXG4nKSkgeworICAgICAgICAgICAgaW50IGVuZCA9IG1fYnVm
ZmVyLmluZGV4T2YoJ1xuJyk7CisgICAgICAgICAgICBRSnNvblBhcnNlRXJyb3IgZXJyb3I7Cisg
ICAgICAgICAgICBhdXRvIGRvY3VtZW50ID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24obV9idWZm
ZXIubGVmdChlbmQpLCAmZXJyb3IpOworICAgICAgICAgICAgbV9idWZmZXIucmVtb3ZlKDAsIGVu
ZCArIDEpOworICAgICAgICAgICAgaWYgKGVycm9yLmVycm9yICE9IFFKc29uUGFyc2VFcnJvcjo6
Tm9FcnJvciB8fCAhZG9jdW1lbnQuaXNPYmplY3QoKSkgeyBmYWlsKHRyKCJJbnZhbGlkIHN5c3Rl
bSByZXNwb25zZS4iKSk7IHJldHVybjsgfQorICAgICAgICAgICAgYXV0byB2YWx1ZSA9IGRvY3Vt
ZW50Lm9iamVjdCgpOworICAgICAgICAgICAgaWYgKHZhbHVlLmNvbnRhaW5zKCJwcm9tcHQiKSkg
eworICAgICAgICAgICAgICAgIG1fcHJvbXB0ID0gdmFsdWUudmFsdWUoInByb21wdCIpLnRvU3Ry
aW5nKCkubGVmdCgxMDI0KTsKKyAgICAgICAgICAgICAgICBtX3RpbWVvdXQuc3RhcnQoMTIwMDAw
KTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGlmICh2YWx1ZS5jb250YWlucygiaXRlbXMi
KSkgeworICAgICAgICAgICAgICAgIGF1dG8gZW50cmllcyA9IHZhbHVlLnZhbHVlKCJpdGVtcyIp
LnRvQXJyYXkoKTsKKyAgICAgICAgICAgICAgICBpZiAoZW50cmllcy5zaXplKCkgPiA2NCkgeyBm
YWlsKHRyKCJJbnZhbGlkIGRldmljZSBsaXN0LiIpKTsgcmV0dXJuOyB9CisgICAgICAgICAgICAg
ICAgbV9pdGVtcyA9IGVudHJpZXMudG9WYXJpYW50TGlzdCgpOworICAgICAgICAgICAgfQorICAg
ICAgICAgICAgaWYgKHZhbHVlLnZhbHVlKCJzdGF0ZSIpLmlzT2JqZWN0KCkpIG1fc3RhdGUgPSB2
YWx1ZS52YWx1ZSgic3RhdGUiKS50b09iamVjdCgpLnRvVmFyaWFudE1hcCgpOworICAgICAgICAg
ICAgaWYodmFsdWUuY29udGFpbnMoInN0YXR1cyIpKSBtX3N0YXR1cz12YWx1ZS52YWx1ZSgic3Rh
dHVzIikudG9TdHJpbmcoKS5sZWZ0KDEwMjQpOworICAgICAgICAgICAgaWYodmFsdWUuY29udGFp
bnMoImVycm9yIikpIG1fc3RhdHVzPXZhbHVlLnZhbHVlKCJlcnJvciIpLnRvU3RyaW5nKCkubGVm
dCgxMDI0KTsKKyAgICAgICAgICAgIGlmICh2YWx1ZS52YWx1ZSgiZG9uZSIpLnRvQm9vbCgpKSB7
IG1fdGltZW91dC5zdG9wKCk7IG1fYnVzeT1mYWxzZTsgbV9wcm9tcHQuY2xlYXIoKTsgfQorICAg
ICAgICAgICAgZW1pdCBjaGFuZ2VkKCk7CisgICAgICAgIH0KKyAgICB9KTsKKyAgICBjb25uZWN0
KCZtX3Byb2Nlc3MsICZRUHJvY2Vzczo6ZXJyb3JPY2N1cnJlZCwgdGhpcywgW3RoaXNdKFFQcm9j
ZXNzOjpQcm9jZXNzRXJyb3IpIHsKKyAgICAgICAgaWYgKCFtX21vZGUuaXNFbXB0eSgpKSBmYWls
KHRyKCJTeXN0ZW0gY29udHJvbHMgYXJlIHVuYXZhaWxhYmxlLiBVc2UgdGhlIGRpYWdub3N0aWMg
c2hlbGwuIikpOworICAgIH0pOworICAgIGNvbm5lY3QoJm1fcHJvY2VzcywgUU92ZXJsb2FkPGlu
dCxRUHJvY2Vzczo6RXhpdFN0YXR1cz46Om9mKCZRUHJvY2Vzczo6ZmluaXNoZWQpLCB0aGlzLCBb
dGhpc10oaW50LCBRUHJvY2Vzczo6RXhpdFN0YXR1cykgeworICAgICAgICBpZiAoIW1fbW9kZS5p
c0VtcHR5KCkpIHsgbV90aW1lb3V0LnN0b3AoKTsgbV9idXN5ID0gZmFsc2U7IG1fcHJvbXB0LmNs
ZWFyKCk7IG1fc3RhdHVzID0gdHIoIlN5c3RlbSBoZWxwZXIgc3RvcHBlZC4gQ2xvc2UgYW5kIHJl
b3BlbiB0aGlzIHBhbmVsLiIpOyBlbWl0IGNoYW5nZWQoKTsgfQorICAgIH0pOworfQorU3lzdGVt
Q29udHJvbHM6On5TeXN0ZW1Db250cm9scygpIHsgY2xvc2UoKTsgaWYgKCFtX3Byb2Nlc3Mud2Fp
dEZvckZpbmlzaGVkKDUwMCkpIHsgbV9wcm9jZXNzLmtpbGwoKTsgbV9wcm9jZXNzLndhaXRGb3JG
aW5pc2hlZCg1MDApOyB9IH0KK3ZvaWQgU3lzdGVtQ29udHJvbHM6OnNlbmQoY29uc3QgUUpzb25P
YmplY3QmIHZhbHVlKSB7IG1fcHJvY2Vzcy53cml0ZShRSnNvbkRvY3VtZW50KHZhbHVlKS50b0pz
b24oUUpzb25Eb2N1bWVudDo6Q29tcGFjdCkgKyAnXG4nKTsgfQordm9pZCBTeXN0ZW1Db250cm9s
czo6b3BlbihRU3RyaW5nIG1vZGUpIHsKKyAgICBpZiAobW9kZSAhPSAid2lmaSIgJiYgbW9kZSAh
PSAiYnQiICYmIG1vZGUgIT0gImNlbnRlciIpIHJldHVybjsKKyAgICBjbG9zZSgpOworICAgIGlm
IChtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgeyBtX3Byb2Nlc3Mu
a2lsbCgpOyBtX3Byb2Nlc3Mud2FpdEZvckZpbmlzaGVkKDUwMCk7IH0KKyAgICBtX21vZGUgPSBt
b2RlOyBtX2l0ZW1zLmNsZWFyKCk7IG1fc3RhdGUuY2xlYXIoKTsgbV9idWZmZXIuY2xlYXIoKTsg
bV9zdGF0dXMgPSB0cigiTG9hZGluZ+KApiIpOyBlbWl0IGNoYW5nZWQoKTsKKyAgICBRU3RyaW5n
IGhlbHBlciA9ICIvdXNyL2xvY2FsL2xpYmV4ZWMvbW9vbmxpZ2h0LW9zL3N5c3RlbS1jb250cm9s
cy5weSI7CisjaWZkZWYgTU9PTkxJR0hUX0NPTlRST0xTX1RFU1QKKyAgICBoZWxwZXIgPSBxRW52
aXJvbm1lbnRWYXJpYWJsZSgiTU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUiLCBoZWxwZXIpOwor
I2VuZGlmCisgICAgbV9wcm9jZXNzLnN0YXJ0KCJweXRob24zIiwge2hlbHBlcn0pOworfQordm9p
ZCBTeXN0ZW1Db250cm9sczo6cmVxdWVzdChRU3RyaW5nIGFjdGlvbiwgUVN0cmluZyBpZCwgYm9v
bCBjb25maXJtKSB7CisgICAgaWYgKG1fYnVzeSB8fCBtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJv
Y2Vzczo6UnVubmluZyB8fCAhYWN0aW9uLnN0YXJ0c1dpdGgobV9tb2RlICsgIi0iKSkgcmV0dXJu
OworICAgIGNvbnN0IFFTdHJpbmdMaXN0IGFsbG93ZWQgPSB7IndpZmktbGlzdCIsICJ3aWZpLXNj
YW4iLCAid2lmaS1jb25uZWN0IiwgIndpZmktZGlzY29ubmVjdCIsICJidC1saXN0IiwgImJ0LXNj
YW4iLCAiYnQtY29ubmVjdCIsICJidC1kaXNjb25uZWN0IiwgImJ0LWZvcmdldCIsICJjZW50ZXIt
d2lmaS1yYWRpbyIsICJjZW50ZXItYnQtcmFkaW8iLCAiY2VudGVyLWFpcnBvZHMiLCAiY2VudGVy
LXRlc3Qtc291bmQiLCAiY2VudGVyLWlkbGUiLCAiY2VudGVyLXBvaW50ZXItc3BlZWQiLCAiY2Vu
dGVyLXBvaW50ZXItbmF0dXJhbCIsICJjZW50ZXItcG9pbnRlci10YXAiLCAiY2VudGVyLWRpc3Bs
YXkiLCAiY2VudGVyLWZyb250ZW5kIiwgImNlbnRlci1yZXN0YXJ0LWZyb250ZW5kIiwgImNlbnRl
ci1saXN0IiwgImNlbnRlci12b2x1bWUiLCAiY2VudGVyLW11dGUiLCAiY2VudGVyLW91dHB1dCIs
ICJjZW50ZXItc2NyZWVuIiwgImNlbnRlci1rZXlib2FyZCIsICJjZW50ZXItcmVib290IiwgImNl
bnRlci1wb3dlcm9mZiIsICJjZW50ZXItc3VzcGVuZCIsICJjZW50ZXItcmVwb3J0In07CisgICAg
aWYgKCFhbGxvd2VkLmNvbnRhaW5zKGFjdGlvbikpIHJldHVybjsKKyAgICBtX2J1c3kgPSB0cnVl
OyBtX3Byb21wdC5jbGVhcigpOyBtX3N0YXR1cyA9IGFjdGlvbi5lbmRzV2l0aCgic2NhbiIpID8g
dHIoIlN0YXJ0aW5nIHNjYW7igKYiKSA6IHRyKCJXb3JraW5n4oCmIik7IG1fdGltZW91dC5zdGFy
dChhY3Rpb24uZW5kc1dpdGgoInNjYW4iKSA/IDMwMDAwIDogMTAwMDAwKTsKKyAgICBzZW5kKHt7
ImFjdGlvbiIsIGFjdGlvbn0sIHsiaWQiLCBpZH0sIHsiY29uZmlybSIsIGNvbmZpcm19fSk7IGVt
aXQgY2hhbmdlZCgpOworfQordm9pZCBTeXN0ZW1Db250cm9sczo6YW5zd2VyKFFTdHJpbmcgdmFs
dWUpIHsKKyAgICBpZiAoIW1fYnVzeSB8fCBtX3Byb21wdC5pc0VtcHR5KCkgfHwgdmFsdWUuc2l6
ZSgpID4gNDA5NiB8fCB2YWx1ZS5jb250YWlucygnXG4nKSB8fCB2YWx1ZS5jb250YWlucygnXHIn
KSB8fCB2YWx1ZS5jb250YWlucyhRQ2hhcigwKSkpIHJldHVybjsKKyAgICBzZW5kKHt7ImFjdGlv
biIsICJhbnN3ZXIifSwgeyJ2YWx1ZSIsIHZhbHVlfX0pOyBtX3Byb21wdC5jbGVhcigpOyBtX3Rp
bWVvdXQuc3RhcnQoMTIwMDAwKTsgZW1pdCBjaGFuZ2VkKCk7Cit9Cit2b2lkIFN5c3RlbUNvbnRy
b2xzOjpjbG9zZSgpIHsKKyAgICBtX21vZGUuY2xlYXIoKTsgbV90aW1lb3V0LnN0b3AoKTsgbV9i
dXN5ID0gZmFsc2U7IG1fcHJvbXB0LmNsZWFyKCk7IG1fYnVmZmVyLmNsZWFyKCk7CisgICAgaWYg
KG1fcHJvY2Vzcy5zdGF0ZSgpICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSB7CisgICAgICAgIG1f
cHJvY2Vzcy50ZXJtaW5hdGUoKTsKKyAgICAgICAgUVRpbWVyOjpzaW5nbGVTaG90KDQwMDAsIHRo
aXMsIFt0aGlzXSB7IGlmIChtX21vZGUuaXNFbXB0eSgpICYmIG1fcHJvY2Vzcy5zdGF0ZSgpICE9
IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSBtX3Byb2Nlc3Mua2lsbCgpOyB9KTsKKyAgICB9CisgICAg
ZW1pdCBjaGFuZ2VkKCk7Cit9Cit2b2lkIFN5c3RlbUNvbnRyb2xzOjpmYWlsKFFTdHJpbmcgbWVz
c2FnZSkgeyBjbG9zZSgpOyBtX3N0YXR1cyA9IG1lc3NhZ2U7IGVtaXQgY2hhbmdlZCgpOyB9Citz
dGF0aWMgdm9pZCByZWdpc3RlclN5c3RlbUNvbnRyb2xzKCkgeworICAgIHFtbFJlZ2lzdGVyU2lu
Z2xldG9uVHlwZTxTeXN0ZW1Db250cm9scz4oIlN5c3RlbUNvbnRyb2xzIiwgMSwgMCwgIlN5c3Rl
bUNvbnRyb2xzIiwgW10oUVFtbEVuZ2luZSosIFFKU0VuZ2luZSopIC0+IFFPYmplY3QqIHsgcmV0
dXJuIG5ldyBTeXN0ZW1Db250cm9scygpOyB9KTsKK30KK1FfQ09SRUFQUF9TVEFSVFVQX0ZVTkNU
SU9OKHJlZ2lzdGVyU3lzdGVtQ29udHJvbHMpCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3Mv
c3lzdGVtY29udHJvbHMuaCBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5oCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjE4ZTlkZWIKLS0tIC9kZXYvbnVsbAorKysg
Yi9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuaApAQCAtMCwwICsxLDM5IEBACisjcHJh
Z21hIG9uY2UKKyNpbmNsdWRlIDxRT2JqZWN0PgorI2luY2x1ZGUgPFFKc29uT2JqZWN0PgorI2lu
Y2x1ZGUgPFFQcm9jZXNzPgorI2luY2x1ZGUgPFFUaW1lcj4KKyNpbmNsdWRlIDxRVmFyaWFudExp
c3Q+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CitjbGFzcyBTeXN0ZW1Db250cm9scyA6IHB1Ymxp
YyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgc3Rh
dGUgUkVBRCBzdGF0ZSBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFWYXJpYW50TGlz
dCBpdGVtcyBSRUFEIGl0ZW1zIE5PVElGWSBjaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmlu
ZyBzdGF0dXMgUkVBRCBzdGF0dXMgTk9USUZZIGNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShRU3Ry
aW5nIHByb21wdCBSRUFEIHByb21wdCBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJv
b2wgYnVzeSBSRUFEIGJ1c3kgTk9USUZZIGNoYW5nZWQpCitwdWJsaWM6CisgICAgZXhwbGljaXQg
U3lzdGVtQ29udHJvbHMoUU9iamVjdCogcGFyZW50ID0gbnVsbHB0cik7CisgICAgflN5c3RlbUNv
bnRyb2xzKCk7CisgICAgUVZhcmlhbnRNYXAgc3RhdGUoKSBjb25zdCB7IHJldHVybiBtX3N0YXRl
OyB9CisgICAgUVZhcmlhbnRMaXN0IGl0ZW1zKCkgY29uc3QgeyByZXR1cm4gbV9pdGVtczsgfQor
ICAgIFFTdHJpbmcgc3RhdHVzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0dXM7IH0KKyAgICBRU3Ry
aW5nIHByb21wdCgpIGNvbnN0IHsgcmV0dXJuIG1fcHJvbXB0OyB9CisgICAgYm9vbCBidXN5KCkg
Y29uc3QgeyByZXR1cm4gbV9idXN5OyB9CisgICAgUV9JTlZPS0FCTEUgdm9pZCBvcGVuKFFTdHJp
bmcgbW9kZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCByZXF1ZXN0KFFTdHJpbmcgYWN0aW9uLCBR
U3RyaW5nIGlkID0gUVN0cmluZygpLCBib29sIGNvbmZpcm0gPSBmYWxzZSk7CisgICAgUV9JTlZP
S0FCTEUgdm9pZCBhbnN3ZXIoUVN0cmluZyB2YWx1ZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCBj
bG9zZSgpOworc2lnbmFsczoKKyAgICB2b2lkIGNoYW5nZWQoKTsKK3ByaXZhdGU6CisgICAgdm9p
ZCBzZW5kKGNvbnN0IFFKc29uT2JqZWN0JiB2YWx1ZSk7CisgICAgdm9pZCBmYWlsKFFTdHJpbmcg
bWVzc2FnZSk7CisgICAgUVByb2Nlc3MgbV9wcm9jZXNzOworICAgIFFUaW1lciBtX3RpbWVvdXQ7
CisgICAgUUJ5dGVBcnJheSBtX2J1ZmZlcjsKKyAgICBRVmFyaWFudExpc3QgbV9pdGVtczsKKyAg
ICBRVmFyaWFudE1hcCBtX3N0YXRlOworICAgIFFTdHJpbmcgbV9tb2RlLCBtX3N0YXR1cywgbV9w
cm9tcHQ7CisgICAgYm9vbCBtX2J1c3kgPSBmYWxzZTsKK307CmRpZmYgLS1naXQgYS9hcHAvbW9v
bmxpZ2h0b3MvdGVzdHMvSGFybmVzcy5xbWwgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvSGFybmVz
cy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMjExZTY5MwotLS0gL2Rl
di9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbApAQCAtMCwwICsx
LDYzIEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQor
aW1wb3J0IFF0UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRl
c2lnbiAxLjAKK2ltcG9ydCBTdHJlYW1pbmdQcmVmZXJlbmNlcyAxLjAKK2ltcG9ydCBFY2xpcHNl
UHJvZmlsZXMgMS4wCitpbXBvcnQgIi4uLy4uL2d1aSIKK0FwcGxpY2F0aW9uV2luZG93IHsKKyAg
ICBNYXRlcmlhbC50aGVtZTogTWF0ZXJpYWwuRGFyaworICAgIE1hdGVyaWFsLmFjY2VudDogVmJU
b2tlbnMuYWNjZW50CisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdXaW5kb3cK
KyAgICBNYXRlcmlhbC5mb3JlZ3JvdW5kOiBWYlRva2Vucy50ZXh0CisgICAgY29sb3I6IFZiVG9r
ZW5zLmJnQXBwCisgICAgd2lkdGg6IDEyODA7IGhlaWdodDogODAwOyB2aXNpYmxlOiB0cnVlCisg
ICAgZnVuY3Rpb24gY2hvb3NlU2NhbGUodmFsdWUpIHsgRWNsaXBzZVByb2ZpbGVzLnRleHRTY2Fs
ZT12YWx1ZSB9CisgICAgZnVuY3Rpb24gY2hvb3NlQWNjZW50KGkpIHsgU3RyZWFtaW5nUHJlZmVy
ZW5jZXMudWlBY2NlbnRJbmRleCA9IGkgfQorICAgIGZ1bmN0aW9uIGNob29zZUFjY2Vzc2liaWxp
dHkoY29udHJhc3QsbW90aW9uKSB7IEVjbGlwc2VQcm9maWxlcy5oaWdoQ29udHJhc3Q9Y29udHJh
c3Q7RWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb249bW90aW9uIH0KKyAgICBmdW5jdGlvbiBj
aG9vc2VXYWxscGFwZXIodXJsKSB7IHJldHVybiBFY2xpcHNlUHJvZmlsZXMuY2hvb3NlQmFja2dy
b3VuZCh1cmwpIH0KKyAgICBmdW5jdGlvbiByZXNldFdhbGxwYXBlcigpIHsgRWNsaXBzZVByb2Zp
bGVzLnJlc2V0QmFja2dyb3VuZCgpIH0KKyAgICBDcmltc29uR2xhc3NCYWNrZHJvcCB7YW5jaG9y
cy5maWxsOnBhcmVudH0KKyAgICBCdXR0b24ge2lkOnNldHRpbmdzQnV0dG9uO3Zpc2libGU6ZmFs
c2V9CisgICAgQnV0dG9uIHtpZDplY2xpcHNlQ2VudGVyQnV0dG9uO3Zpc2libGU6ZmFsc2V9Cisg
ICAgUXRPYmplY3Qge2lkOmNyaW1zb25QYW5lbDtwcm9wZXJ0eSBzdHJpbmcga2luZDoiIjtmdW5j
dGlvbiBvcGVuKCl7fX0KKyAgICBRdE9iamVjdCB7aWQ6YWRkUGNEaWFsb2c7ZnVuY3Rpb24gb3Bl
bigpe319CisgICAgUXRPYmplY3Qge2lkOnF1aWNrTWVudU1hbmFnZXI7cHJvcGVydHkgdmFyIHNl
cnZlckNvbW1hbmRNYW5hZ2VyOm51bGw7ZnVuY3Rpb24gaGlkZSgpe30gZnVuY3Rpb24gZXhlY3V0
ZUFjdGlvbihhY3Rpb24pe30gZnVuY3Rpb24gc2V0VGV4dElucHV0QWN0aXZlKGFjdGl2ZSl7fSB9
CisgICAgTG9hZGVyIHtvYmplY3ROYW1lOiJxdWlja01lbnVMb2FkZXIiO2FjdGl2ZTpmYWxzZTth
bmNob3JzLmNlbnRlckluOnBhcmVudDtzb3VyY2VDb21wb25lbnQ6UXVpY2tNZW51IHt9fQorICAg
IFN0YWNrVmlldyB7IGlkOnN0YWNrVmlldztvYmplY3ROYW1lOiJwcm9kdWN0aW9uU3RhY2siO2Fu
Y2hvcnMuZmlsbDpwYXJlbnQ7dmlzaWJsZTpmYWxzZSB9CisgICAgZnVuY3Rpb24gc2hvd1Byb2R1
Y3Rpb25WaWV3KHZpZXcpIHsKKyAgICAgICAgc3RhY2tWaWV3LnZpc2libGU9dHJ1ZTtzdGFja1Zp
ZXcuY2xlYXIoKQorICAgICAgICB2YXIgcHJvcHM9dmlldz09PSJBcHBWaWV3Ij97Y29tcHV0ZXJJ
bmRleDowLG9iamVjdE5hbWU6IkdhbWluZyBQQyIsaG9zdFR5cGU6IlZJQkVQT0xMTyIsaG9zdFRy
YW5zcG9ydDoiTEFOIixob3N0T25saW5lOnRydWUsc2hvd0dhbWVzOnRydWV9Ont9CisgICAgICAg
IHN0YWNrVmlldy5wdXNoKFF0LnJlc29sdmVkVXJsKCIuLi8uLi9ndWkvIit2aWV3KyIucW1sIiks
cHJvcHMpCisgICAgfQorICAgIGZ1bmN0aW9uIGhpZGVQcm9kdWN0aW9uVmlldygpe3N0YWNrVmll
dy5jbGVhcigpO3N0YWNrVmlldy52aXNpYmxlPWZhbHNlfQorICAgIFF0T2JqZWN0IHsgb2JqZWN0
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
IH0KKyAgICBDcmltc29uQmFja2dyb3VuZFBpY2tlciB7b2JqZWN0TmFtZToiZ2xhc3NCYWNrZ3Jv
dW5kUGlja2VyIn0KKyAgICBJdGVtIHsKKyAgICAgICAgaWQ6ZGFzaGJvYXJkO29iamVjdE5hbWU6
ImdsYXNzRGFzaGJvYXJkIjthbmNob3JzLmZpbGw6cGFyZW50O3Zpc2libGU6ZmFsc2UKKyAgICAg
ICAgQ3JpbXNvbkdsYXNzQmFja2Ryb3Age2FuY2hvcnMuZmlsbDpwYXJlbnR9CisgICAgICAgIENy
aW1zb25HbGFzc1JhaWwge3g6MTY7eToxNjt3aWR0aDo2NDtoZWlnaHQ6cGFyZW50LmhlaWdodC0z
Mn0KKyAgICAgICAgQ3JpbXNvbkhvc3RQYW5lbCB7b2JqZWN0TmFtZToiZ2xhc3NIb3N0Ijt4Ojk2
O3k6MTY7d2lkdGg6cGFyZW50LndpZHRoPj0xNTgwPzI2MDowO2hlaWdodDpwYXJlbnQuaGVpZ2h0
LTMyO3Zpc2libGU6d2lkdGg+MDtob3N0TmFtZToiR2FtaW5nIFBDIjtob3N0VHlwZToiVmliZXBv
bGxvIjt0cmFuc3BvcnQ6IkxBTiI7b25saW5lOnRydWV9CisgICAgICAgIENyaW1zb25Mb2NhbFBh
bmVsIHthY3RpdmU6ZGFzaGJvYXJkLnZpc2libGU7eDpwYXJlbnQud2lkdGgtd2lkdGgtMTY7eTox
Njt3aWR0aDpNYXRoLnJvdW5kKDI1MipWYlRva2Vucy50ZXh0U2NhbGUpO2hlaWdodDpwYXJlbnQu
aGVpZ2h0LTMyO3Zpc2libGU6cGFyZW50LndpZHRoPj0xMjQwfQorICAgICAgICBDb2x1bW4gewor
ICAgICAgICAgICAgeDpwYXJlbnQud2lkdGg+PTE1ODA/Mzc2OjEwNDt5OjI0O3dpZHRoOnBhcmVu
dC53aWR0aC14LShwYXJlbnQud2lkdGg+PTEyNDA/TWF0aC5yb3VuZCgyNTIqVmJUb2tlbnMudGV4
dFNjYWxlKSs0MDoyNCk7c3BhY2luZzoxNgorICAgICAgICAgICAgTGFiZWwge3RleHQ6IkNyaW1z
b24gR2xhc3Mg4oCiIExpYnJhcnkiO2ZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVUaXRsZTtj
b2xvcjpWYlRva2Vucy50ZXh0fQorICAgICAgICAgICAgTGFiZWwge3RleHQ6IlVJIHZlcmlmaWNh
dGlvbiBmaXh0dXJlIOKAoiBpbGx1c3RyYXRpdmUgaG9zdCBhbmQgYXBwIGRhdGEiO2ZvbnQucGl4
ZWxTaXplOlZiVG9rZW5zLnR5cGVMYWJlbDtjb2xvcjpWYlRva2Vucy50ZXh0RGltO3dpZHRoOnBh
cmVudC53aWR0aDt3cmFwTW9kZTpUZXh0LldyYXB9CisgICAgICAgICAgICBGbG93IHt3aWR0aDpw
YXJlbnQud2lkdGg7c3BhY2luZzoxNgorICAgICAgICAgICAgICAgIFJlcGVhdGVyIHttb2RlbDpb
IkRlc2t0b3AiLCJTdGVhbSBCaWcgUGljdHVyZSIsIkdhbWUgbGlicmFyeSIsIk1lZGlhIl0KKyAg
ICAgICAgICAgICAgICAgICAgZGVsZWdhdGU6VmJDYXJkIHt3aWR0aDpNYXRoLm1heCgxODAsTWF0
aC5taW4oMjUwLChwYXJlbnQud2lkdGgtMzIpLzIpKTtoZWlnaHQ6MjIwCisgICAgICAgICAgICAg
ICAgICAgICAgICBJbWFnZSB7YW5jaG9ycy5jZW50ZXJJbjpwYXJlbnQ7d2lkdGg6NjQ7aGVpZ2h0
OjY0O3NvdXJjZToicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyJ9CisgICAgICAgICAgICAgICAg
ICAgICAgICBMYWJlbCB7YW5jaG9ycy5ib3R0b206cGFyZW50LmJvdHRvbTthbmNob3JzLmJvdHRv
bU1hcmdpbjoyMDthbmNob3JzLmhvcml6b250YWxDZW50ZXI6cGFyZW50Lmhvcml6b250YWxDZW50
ZXI7dGV4dDptb2RlbERhdGE7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LnBpeGVsU2l6ZTpWYlRv
a2Vucy50eXBlQm9keX0KKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIH0K
KyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBFY2xpcHNlQWJvdXREaWFsb2cg
eyBvYmplY3ROYW1lOiAiYWJvdXRFY2xpcHNlIiB9Cit9CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxp
Z2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL1ByZWZl
cmVuY2VzLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi4wM2FkYzY4Ci0t
LSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL1ByZWZlcmVuY2VzLnFtbApA
QCAtMCwwICsxLDMgQEAKK3ByYWdtYSBTaW5nbGV0b24KK2ltcG9ydCBRdFF1aWNrIDIuOQorUXRP
YmplY3QgeyBwcm9wZXJ0eSBpbnQgdWlBY2NlbnRJbmRleDogNDsgcHJvcGVydHkgYm9vbCBlbmFi
bGVNZG5zOnRydWU7IHByb3BlcnR5IGJvb2wgdWlTaG93SGludHM6IHRydWU7IHByb3BlcnR5IGlu
dCB3aWR0aDogMTkyMDsgcHJvcGVydHkgaW50IGhlaWdodDogMTA4MDsgcHJvcGVydHkgaW50IGZw
czogNjA7IHByb3BlcnR5IGludCBiaXRyYXRlS2JwczogMjAwMDA7IGZ1bmN0aW9uIHNhdmUoKSB7
fSB9CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvVWlTZXJ2aWNlcy5xbWwgYi9h
cHAvbW9vbmxpZ2h0b3MvdGVzdHMvVWlTZXJ2aWNlcy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQK
aW5kZXggMDAwMDAwMC4uMGMzZjk2NAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRv
cy90ZXN0cy9VaVNlcnZpY2VzLnFtbApAQCAtMCwwICsxLDE3IEBACitwcmFnbWEgU2luZ2xldG9u
CitpbXBvcnQgUXRRdWljayAyLjkKK1F0T2JqZWN0IHsKKyAgICBwcm9wZXJ0eSBib29sIGhhc0Jy
b3dzZXI6IGZhbHNlCisgICAgcHJvcGVydHkgc3RyaW5nIHZlcnNpb25TdHJpbmc6ICJVSSBmaXh0
dXJlIgorICAgIHNpZ25hbCBvdHBTdGFnZTFDb21wbGV0ZWQoc3RyaW5nIHBpbixzdHJpbmcgZXJy
b3IpCisgICAgc2lnbmFsIGNvbXB1dGVyQWRkQ29tcGxldGVkKGJvb2wgc3VjY2Vzcyxib29sIGJs
b2NrZWQpCisgICAgZnVuY3Rpb24gZ2V0Q29ubmVjdGVkR2FtZXBhZHMoKXtyZXR1cm4gMH0KKyAg
ICBmdW5jdGlvbiBhY3RpdmF0ZWQoKXt9CisgICAgZnVuY3Rpb24gZm9jdXNNb3ZlZCgpe30KKyAg
ICBmdW5jdGlvbiBiYWNrKCl7fQorICAgIGZ1bmN0aW9uIHN0YXJ0UG9sbGluZygpe30KKyAgICBm
dW5jdGlvbiBzdG9wUG9sbGluZygpe30KKyAgICBmdW5jdGlvbiBvcGVuVXJsKHVybCl7fQorICAg
IGZ1bmN0aW9uIGhhc1Byb2ZpbGUoaG9zdCxhcHApe3JldHVybiBmYWxzZX0KKyAgICBmdW5jdGlv
biBwcm9maWxlU3VtbWFyeShob3N0LGFwcCl7cmV0dXJuICIifQorfQpkaWZmIC0tZ2l0IGEvYXBw
L21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAgYi9hcHAvbW9vbmxpZ2h0b3MvdGVz
dHMvdGVzdC1jcmltc29uLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5l
MGNlNDVlCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3Jp
bXNvbi5jcHAKQEAgLTAsMCArMSw0NzkgQEAKKyNpbmNsdWRlIDxRdFRlc3Q+CisjaW5jbHVkZSA8
UVRlbXBvcmFyeURpcj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFRbWxDb21w
b25lbnQ+CisjaW5jbHVkZSA8UVFtbENvbnRleHQ+CisjaW5jbHVkZSA8UVF1aWNrU3R5bGU+Cisj
aW5jbHVkZSA8UVF1aWNrV2luZG93PgorI2luY2x1ZGUgPFFRdWlja0l0ZW0+CisjaW5jbHVkZSA8
UUZpbGU+CisjaW5jbHVkZSA8UUltYWdlUmVhZGVyPgorI2luY2x1ZGUgPFFUY3BTZXJ2ZXI+Cisj
aW5jbHVkZSA8UVNzbFNvY2tldD4KKyNpbmNsdWRlIDxRU3NsS2V5PgorI2luY2x1ZGUgPFFTc2xD
ZXJ0aWZpY2F0ZT4KKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVkZSA8bWVt
b3J5PgorI2luY2x1ZGUgPFFTdGFuZGFyZFBhdGhzPgorI2luY2x1ZGUgPFFEaXI+CisjaW5jbHVk
ZSA8UUZpbGVJbmZvPgorI2luY2x1ZGUgIi4uL2NyaW1zb25zdGF0dXMuaCIKKyNpbmNsdWRlICIu
Li9zeXN0ZW1jb250cm9scy5oIgorI2luY2x1ZGUgIi4uL2VjbGlwc2Vwcm9maWxlcy5oIgorI2lu
Y2x1ZGUgIi4uL2xvY2FsaGFyZHdhcmUuaCIKKyNpbmNsdWRlICIuLi9vdmVybGF5c3R5bGUuaCIK
KyNpbmNsdWRlICIuLi9jcmltc29uZ3JhcGhzLmgiCisjaW5jbHVkZSAidWltb2RlbHMuaCIKKyNp
bmNsdWRlICIuLi8uLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgiCisKK2NsYXNzIFRsc0Zp
eHR1cmUgOiBwdWJsaWMgUVRjcFNlcnZlciB7CitwdWJsaWM6CisgICAgUUJ5dGVBcnJheSBib2R5
ID0gUiIoeyJjcHVfcGVyY2VudCI6MzcuNSwicmFtX3VzZWRfYnl0ZXMiOjUwLCJyYW1fdG90YWxf
Ynl0ZXMiOjEwMH0pIjsKKyAgICBpbnQgY29kZSA9IDIwMCwgcmVxdWVzdHMgPSAwOworICAgIGJv
b2wgcmVzcG9uZCA9IHRydWU7CisgICAgUUJ5dGVBcnJheSBhdXRob3JpemF0aW9uOworICAgIFFT
c2xDZXJ0aWZpY2F0ZSBjZXJ0OworICAgIFFTc2xLZXkga2V5OworICAgIFRsc0ZpeHR1cmUoKSB7
CisgICAgICAgIFFGaWxlIGMocUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fVEVTVF9DRVJU
IikpOyBjLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGNlcnQgPSBRU3NsQ2VydGlmaWNhdGUo
Yy5yZWFkQWxsKCkpOworICAgICAgICBRRmlsZSBrKHFFbnZpcm9ubWVudFZhcmlhYmxlKCJDUklN
U09OX1RFU1RfS0VZIikpOyBrLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGtleSA9IFFTc2xL
ZXkoay5yZWFkQWxsKCksIFFTc2w6OlJzYSk7CisgICAgICAgIGxpc3RlbihRSG9zdEFkZHJlc3M6
OkxvY2FsSG9zdCk7CisgICAgfQorICAgIHZvaWQgaW5jb21pbmdDb25uZWN0aW9uKHFpbnRwdHIg
ZGVzY3JpcHRvcikgb3ZlcnJpZGUgeworICAgICAgICBhdXRvIHNvY2tldCA9IG5ldyBRU3NsU29j
a2V0KHRoaXMpOworICAgICAgICBzb2NrZXQtPnNldExvY2FsQ2VydGlmaWNhdGUoY2VydCk7IHNv
Y2tldC0+c2V0UHJpdmF0ZUtleShrZXkpOyBzb2NrZXQtPnNldFBlZXJWZXJpZnlNb2RlKFFTc2xT
b2NrZXQ6OlZlcmlmeU5vbmUpOworICAgICAgICBzb2NrZXQtPnNldFNvY2tldERlc2NyaXB0b3Io
ZGVzY3JpcHRvcik7CisgICAgICAgIGF1dG8gaW5wdXQgPSBzdGQ6Om1ha2Vfc2hhcmVkPFFCeXRl
QXJyYXk+KCk7CisgICAgICAgIGNvbm5lY3Qoc29ja2V0LCAmUVNzbFNvY2tldDo6cmVhZHlSZWFk
LCB0aGlzLCBbdGhpcywgc29ja2V0LCBpbnB1dF0geworICAgICAgICAgICAgaW5wdXQtPmFwcGVu
ZChzb2NrZXQtPnJlYWRBbGwoKSk7CisgICAgICAgICAgICBpZiAoIWlucHV0LT5jb250YWlucygi
XHJcblxyXG4iKSkgcmV0dXJuOworICAgICAgICAgICAgKytyZXF1ZXN0czsgYXV0aG9yaXphdGlv
biA9ICppbnB1dDsKKyAgICAgICAgICAgIGlmIChyZXNwb25kKSB7CisgICAgICAgICAgICAgICAg
UUJ5dGVBcnJheSBoZWFkZXIgPSAiSFRUUC8xLjEgIiArIFFCeXRlQXJyYXk6Om51bWJlcihjb2Rl
KSArICIgRml4dHVyZVxyXG5Db250ZW50LVR5cGU6IGFwcGxpY2F0aW9uL2pzb25cclxuQ29ubmVj
dGlvbjogY2xvc2VcclxuQ29udGVudC1MZW5ndGg6ICIgKyBRQnl0ZUFycmF5OjpudW1iZXIoYm9k
eS5zaXplKCkpICsgIlxyXG4iOworICAgICAgICAgICAgICAgIGlmIChjb2RlID09IDMwMikgaGVh
ZGVyICs9ICJMb2NhdGlvbjogaHR0cHM6Ly8xMjcuMC4wLjI6MTIzNDUvXHJcbiI7CisgICAgICAg
ICAgICAgICAgc29ja2V0LT53cml0ZShoZWFkZXIgKyAiXHJcbiIgKyBib2R5KTsgc29ja2V0LT5k
aXNjb25uZWN0RnJvbUhvc3QoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGlucHV0LT5j
bGVhcigpOworICAgICAgICB9KTsKKyAgICAgICAgY29ubmVjdChzb2NrZXQsICZRU3NsU29ja2V0
OjpkaXNjb25uZWN0ZWQsIHNvY2tldCwgJlFPYmplY3Q6OmRlbGV0ZUxhdGVyKTsKKyAgICAgICAg
c29ja2V0LT5zdGFydFNlcnZlckVuY3J5cHRpb24oKTsKKyAgICB9Cit9OworCitjbGFzcyBDcmlt
c29uVGVzdCA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorcHJpdmF0ZSBzbG90czoK
KyAgICB2b2lkIGluaXRUZXN0Q2FzZSgpIHsKKyAgICAgICAgUUNvcmVBcHBsaWNhdGlvbjo6c2V0
T3JnYW5pemF0aW9uTmFtZSgiRWNsaXBzZU9TIFRlc3QiKTsKKyAgICAgICAgUUNvcmVBcHBsaWNh
dGlvbjo6c2V0QXBwbGljYXRpb25OYW1lKCJFY2xpcHNlRml4dHVyZSIpOworICAgICAgICBRU2V0
dGluZ3M6OnNldERlZmF1bHRGb3JtYXQoUVNldHRpbmdzOjpJbmlGb3JtYXQpOworICAgIH0KKyAg
ICB2b2lkIGhvc3RQcm9maWxlc1JlbWFpbklzb2xhdGVkKCkgeworICAgICAgICBFY2xpcHNlUHJv
ZmlsZXMgcHJvZmlsZXM7CisgICAgICAgIFFWYXJpYW50TWFwIHZhbHVlc3t7IndpZHRoIiwxMjgw
fSx7ImhlaWdodCIsODAwfSx7ImZwcyIsNjB9LHsiYml0cmF0ZUticHMiLDE1MDAwfX07CisgICAg
ICAgIFFWRVJJRlkocHJvZmlsZXMuc2F2ZSgiZml4dHVyZS1ob3N0LWEiLCJEZXNrdG9wIix2YWx1
ZXMpKTsKKyAgICAgICAgUUNPTVBBUkUocHJvZmlsZXMubG9hZCgiZml4dHVyZS1ob3N0LWEiLCJE
ZXNrdG9wIiksdmFsdWVzKTsKKyAgICAgICAgUVZFUklGWShwcm9maWxlcy5sb2FkKCJmaXh0dXJl
LWhvc3QtYiIsIkRlc2t0b3AiKS5pc0VtcHR5KCkpOworICAgICAgICBRVkVSSUZZKHByb2ZpbGVz
Lm5hbWVzKCJmaXh0dXJlLWhvc3QtYSIpLmNvbnRhaW5zKCJEZXNrdG9wIikpOworICAgICAgICBR
VkVSSUZZKCFwcm9maWxlcy5yZW1vdmUoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIsZmFsc2Up
KTsKKyAgICAgICAgdmFsdWVzWyJmcHMiXSA9IDA7IFFWRVJJRlkoIXByb2ZpbGVzLnNhdmUoImZp
eHR1cmUtaG9zdC1hIiwiQmFkIix2YWx1ZXMpKTsKKyAgICAgICAgUVZFUklGWShwcm9maWxlcy5y
ZW1vdmUoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIsdHJ1ZSkpOworICAgICAgICBRVkVSSUZZ
KHByb2ZpbGVzLmxvYWQoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIpLmlzRW1wdHkoKSk7Cisg
ICAgfQorICAgIHZvaWQgc3lzdGVtQ29udHJvbHNQcml2YXRlUGlwZSgpIHsKKyAgICAgICAgUVRl
bXBvcmFyeURpciBkaXI7IFFWRVJJRlkoZGlyLmlzVmFsaWQoKSk7CisgICAgICAgIFFGaWxlIHNj
cmlwdChkaXIuZmlsZVBhdGgoImZpeHR1cmUucHkiKSk7IFFWRVJJRlkoc2NyaXB0Lm9wZW4oUUlP
RGV2aWNlOjpXcml0ZU9ubHkpKTsKKyAgICAgICAgc2NyaXB0LndyaXRlKFIiUFkoaW1wb3J0IGpz
b24sc3lzCitmb3IgbGluZSBpbiBzeXMuc3RkaW46CisgICAgdmFsdWU9anNvbi5sb2FkcyhsaW5l
KQorICAgIGFjdGlvbj12YWx1ZVsnYWN0aW9uJ10KKyAgICBpZiBhY3Rpb249PSd3aWZpLWNvbm5l
Y3QnOgorICAgICAgICBwcmludChqc29uLmR1bXBzKHsncHJvbXB0JzonV2ktRmkgcGFzc3dvcmQn
fSksZmx1c2g9VHJ1ZSkKKyAgICAgICAgcmVwbHk9anNvbi5sb2FkcyhzeXMuc3RkaW4ucmVhZGxp
bmUoKSkKKyAgICAgICAgYXNzZXJ0IHJlcGx5PT17J2FjdGlvbic6J2Fuc3dlcicsJ3ZhbHVlJzon
c2VjcmV0LXZhbHVlJ30KKyAgICBwcmludChqc29uLmR1bXBzKHsnaXRlbXMnOlt7J2lkJzond2xh
bjAvQUE6QkI6Q0M6REQ6RUU6RkYnLCduYW1lJzonPGI+UGxhaW4gU1NJRDwvYj4nLCdkZXRhaWwn
Oic4MCUgV1BBMicsJ2Nvbm5lY3RlZCc6YWN0aW9uPT0nd2lmaS1jb25uZWN0J31dLCdzdGF0dXMn
OidSZWFkeScsJ2RvbmUnOlRydWV9KSxmbHVzaD1UcnVlKQorKVBZIik7IHNjcmlwdC5jbG9zZSgp
OworICAgICAgICBxcHV0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIsIHNjcmlwdC5m
aWxlTmFtZSgpLnRvVXRmOCgpKTsKKyAgICAgICAgU3lzdGVtQ29udHJvbHMgY29udHJvbHM7IGNv
bnRyb2xzLm9wZW4oIndpZmkiKTsKKyAgICAgICAgUVRSWV9DT01QQVJFKGNvbnRyb2xzLml0ZW1z
KCkuc2l6ZSgpLCAxKTsgUVZFUklGWSghY29udHJvbHMuYnVzeSgpKTsKKyAgICAgICAgY29udHJv
bHMucmVxdWVzdCgiYnQtZm9yZ2V0IiwgImludmFsaWQiLCB0cnVlKTsgUVZFUklGWSghY29udHJv
bHMuYnVzeSgpKTsKKyAgICAgICAgY29udHJvbHMucmVxdWVzdCgid2lmaS1jb25uZWN0IiwgInds
YW4wL0FBOkJCOkNDOkREOkVFOkZGIik7CisgICAgICAgIFFUUllfVkVSSUZZKCFjb250cm9scy5w
cm9tcHQoKS5pc0VtcHR5KCkpOyBRVkVSSUZZKGNvbnRyb2xzLmJ1c3koKSk7CisgICAgICAgIGNv
bnRyb2xzLmFuc3dlcigic2VjcmV0LXZhbHVlIik7IFFUUllfVkVSSUZZKCFjb250cm9scy5idXN5
KCkpOworICAgICAgICBRVkVSSUZZKGNvbnRyb2xzLnByb21wdCgpLmlzRW1wdHkoKSk7IFFDT01Q
QVJFKGNvbnRyb2xzLnN0YXR1cygpLCBRU3RyaW5nKCJSZWFkeSIpKTsKKyAgICAgICAgUVZFUklG
WShjb250cm9scy5pdGVtcygpLmZpcnN0KCkudG9NYXAoKS52YWx1ZSgiY29ubmVjdGVkIikudG9C
b29sKCkpOworICAgICAgICBjb250cm9scy5jbG9zZSgpOyBRVkVSSUZZKCFjb250cm9scy5idXN5
KCkpOworICAgICAgICBxdW5zZXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIik7Cisg
ICAgfQorICAgIHZvaWQgbWFuYWdlZFVwZGF0ZXJDYW5ub3RSZXBsYWNlQ3VzdG9taXplZENsaWVu
dCgpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciBkaXI7IFFWRVJJRlkoZGlyLmlzVmFsaWQoKSk7
CisgICAgICAgIGNvbnN0IFFTdHJpbmcgaW1hZ2UgPSBkaXIuZmlsZVBhdGgoImN1c3RvbS5BcHBJ
bWFnZSIpOworICAgICAgICBRRmlsZSBmKGltYWdlKTsgUVZFUklGWShmLm9wZW4oUUlPRGV2aWNl
OjpXcml0ZU9ubHkpKTsgZi53cml0ZSgiY3VzdG9taXplZCBjbGllbnQiKTsgZi5jbG9zZSgpOwor
ICAgICAgICBjb25zdCBRQnl0ZUFycmF5IG9sZCA9IHFnZXRlbnYoIkFQUElNQUdFIik7IGNvbnN0
IGJvb2wgaGFkID0gcUVudmlyb25tZW50VmFyaWFibGVJc1NldCgiQVBQSU1BR0UiKTsKKyAgICAg
ICAgcXB1dGVudigiQVBQSU1BR0UiLCBpbWFnZS50b1V0ZjgoKSk7CisgICAgICAgIEF1dG9VcGRh
dGVDaGVja2VyIGNoZWNrZXI7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5vc01hbmFnZWQoKSk7
IFFWRVJJRlkoIWNoZWNrZXIuY2FuSW5zdGFsbFVwZGF0ZXMoKSk7CisgICAgICAgIFFTaWduYWxT
cHkgY29tcGxldGVkKCZjaGVja2VyLCAmQXV0b1VwZGF0ZUNoZWNrZXI6OmNoZWNrQ29tcGxldGVk
KTsKKyAgICAgICAgUVNpZ25hbFNweSBmYWlsZWQoJmNoZWNrZXIsICZBdXRvVXBkYXRlQ2hlY2tl
cjo6aW5zdGFsbEZhaWxlZCk7CisgICAgICAgIGNoZWNrZXIuc3RhcnQoKTsgY2hlY2tlci5jaGVj
a05vdygpOyBjaGVja2VyLmNoYW5uZWxDaGFuZ2VkKCk7IGNoZWNrZXIuaW5zdGFsbCgpOworICAg
ICAgICBRQ09NUEFSRShjb21wbGV0ZWQuY291bnQoKSwgMyk7IFFDT01QQVJFKGZhaWxlZC5jb3Vu
dCgpLCAxKTsKKyAgICAgICAgUVZFUklGWSghY2hlY2tlci5jaGVja2luZygpKTsgUVZFUklGWSgh
Y2hlY2tlci5pbnN0YWxsaW5nKCkpOworICAgICAgICBRVkVSSUZZKCFjaGVja2VyLmNhbkluc3Rh
bGwoKSk7IFFWRVJJRlkoIWNoZWNrZXIudXBkYXRlQXZhaWxhYmxlKCkpOyBRVkVSSUZZKCFjaGVj
a2VyLm9mZmVyQXZhaWxhYmxlKCkpOworICAgICAgICBRQ09NUEFSRShjaGVja2VyLnJlbGVhc2VV
cmwoKSwgUVN0cmluZygiaHR0cHM6Ly9naXRodWIuY29tL3RoM2QzY2szci9Nb29ubGlnaHQtT1Mv
cmVsZWFzZXMiKSk7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5jdXJyZW50VmVyc2lvbigpLmNv
bnRhaW5zKCJFY2xpcHNlT1MgY3VzdG9taXplZCIpKTsKKyAgICAgICAgUVZFUklGWShmLm9wZW4o
UUlPRGV2aWNlOjpSZWFkT25seSkpOyBRQ09NUEFSRShmLnJlYWRBbGwoKSwgUUJ5dGVBcnJheSgi
Y3VzdG9taXplZCBjbGllbnQiKSk7IGYuY2xvc2UoKTsKKyAgICAgICAgUUNPTVBBUkUoUURpcihk
aXIucGF0aCgpKS5lbnRyeUxpc3QoUURpcjo6RmlsZXMpLCBRU3RyaW5nTGlzdHsiY3VzdG9tLkFw
cEltYWdlIn0pOworICAgICAgICBpZiAoaGFkKSBxcHV0ZW52KCJBUFBJTUFHRSIsIG9sZCk7IGVs
c2UgcXVuc2V0ZW52KCJBUFBJTUFHRSIpOworICAgICAgICBRQ09NUEFSRShBdXRvVXBkYXRlQ2hl
Y2tlcjo6Y29tcGFyZVNlbWFudGljVmVyc2lvbnMoIjAuNS4wIiwgIjAuNC45IiksIDEpOworICAg
IH0KKyAgICB2b2lkIGVuZHBvaW50VmFsaWRhdGlvbigpIHsKKyAgICAgICAgUVZFUklGWShDcmlt
c29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovLzE5Mi4xNjguMS4xMDo0Nzk5MCIpKTsK
KyAgICAgICAgUVZFUklGWShDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovL1tm
ZDAwOjoxXTo0Nzk5MC8iKSk7CisgICAgICAgIGZvciAoYXV0byBiYWQgOiB7Imh0dHA6Ly9ob3N0
IiwgImh0dHBzOi8vdXNlcjpzZWNyZXRAaG9zdCIsICJodHRwczovL2hvc3QvYXBpIiwgImh0dHBz
Oi8vaG9zdC8/dG9rZW49c2VjcmV0IiwgImZpbGU6Ly8vZXRjL3Bhc3N3ZCIsICJodHRwczovL2hv
c3QvI2ZyYWdtZW50In0pCisgICAgICAgICAgICBRVkVSSUZZKCFDcmltc29uU3RhdHVzOjp2YWxp
ZEVuZHBvaW50KGJhZCkpOworICAgIH0KKyAgICB2b2lkIG1pc3NpbmdBbmRJbnZhbGlkTWV0cmlj
cygpIHsKKyAgICAgICAgUVN0cmluZyBlcnJvcjsKKyAgICAgICAgUVZFUklGWShDcmltc29uU3Rh
dHVzOjpwYXJzZVN0YXRzKCJub3QganNvbiIsICZlcnJvcikuaXNFbXB0eSgpKTsgUVZFUklGWSgh
ZXJyb3IuaXNFbXB0eSgpKTsKKyAgICAgICAgYXV0byBzID0gQ3JpbXNvblN0YXR1czo6cGFyc2VT
dGF0cyhSIih7ImNwdV9wZXJjZW50Ijo0Mi41LCJjcHVfdGVtcF9jIjotMSwiZ3B1X3BlcmNlbnQi
Om51bGwsInJhbV90b3RhbF9ieXRlcyI6MCwicmFtX3BlcmNlbnQiOjAsInZyYW1fdG90YWxfYnl0
ZXMiOjEwMCwidnJhbV91c2VkX2J5dGVzIjoxMjB9KSIsICZlcnJvcik7CisgICAgICAgIFFWRVJJ
RlkoZXJyb3IuaXNFbXB0eSgpKTsgUUNPTVBBUkUocy52YWx1ZSgiY3B1X3BlcmNlbnQiKS50b0Rv
dWJsZSgpLCA0Mi41KTsKKyAgICAgICAgUVZFUklGWSghcy5jb250YWlucygiY3B1X3RlbXBfYyIp
KTsgUVZFUklGWSghcy5jb250YWlucygiZ3B1X3BlcmNlbnQiKSk7IFFWRVJJRlkoIXMuY29udGFp
bnMoInJhbV9wZXJjZW50IikpOworICAgICAgICBRQ09NUEFSRShzLnZhbHVlKCJ2cmFtX3BlcmNl
bnQiKS50b0RvdWJsZSgpLCAxMDAuMCk7CisgICAgICAgIGF1dG8gaW52YWxpZCA9IENyaW1zb25T
dGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJjcHVfcGVyY2VudCI6MTAxLCJncHVfcGVyY2VudCI6IjAi
fSkiLCAmZXJyb3IpOworICAgICAgICBRVkVSSUZZKGludmFsaWQuaXNFbXB0eSgpKTsgUVZFUklG
WShlcnJvci5pc0VtcHR5KCkpOworICAgICAgICBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKFFC
eXRlQXJyYXkoNjU1MzcsICdhJyksICZlcnJvcik7IFFWRVJJRlkoIWVycm9yLmlzRW1wdHkoKSk7
CisgICAgICAgIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJlcnJvciI6InVuc3VwcG9y
dGVkIn0pIiwgJmVycm9yKTsgUVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsKKyAgICB9CisgICAg
dm9pZCBsb2NhbEhhcmR3YXJlRml4dHVyZSgpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciB0ZW1w
OyBRVkVSSUZZKHRlbXAuaXNWYWxpZCgpKTsKKyAgICAgICAgYXV0byB3cml0ZSA9IFsmXShRU3Ry
aW5nIHAsIFFCeXRlQXJyYXkgdmFsdWUpIHsgUURpcigpLm1rcGF0aChRRmlsZUluZm8odGVtcC5w
YXRoKCkrcCkuYWJzb2x1dGVQYXRoKCkpOyBRRmlsZSBmKHRlbXAucGF0aCgpK3ApOyBRVkVSSUZZ
KGYub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOyBmLndyaXRlKHZhbHVlKTsgfTsKKyAgICAg
ICAgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC90eXBlIiwgIkJhdHRlcnkiKTsgd3Jp
dGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9jYXBhY2l0eSIsICI3MyIpOyB3cml0ZSgiL2Ns
YXNzL3Bvd2VyX3N1cHBseS9CQVQwL3N0YXR1cyIsICJDaGFyZ2luZyIpOworICAgICAgICB3cml0
ZSgiL2NsYXNzL25ldC93bGFuMC9vcGVyc3RhdGUiLCAidXAiKTsgd3JpdGUoIi9jbGFzcy9uZXQv
bG8vb3BlcnN0YXRlIiwgInVwIik7CisgICAgICAgIGF1dG8gbG9jYWwgPSBDcmltc29uU3RhdHVz
OjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpOyBRQ09NUEFSRShsb2NhbC52YWx1ZSgiYmF0dGVyeVBl
cmNlbnQiKS50b0ludCgpLCA3Myk7IFFDT01QQVJFKGxvY2FsLnZhbHVlKCJiYXR0ZXJ5U3RhdGUi
KS50b1N0cmluZygpLCBRU3RyaW5nKCJDaGFyZ2luZyIpKTsKKyAgICAgICAgUUNPTVBBUkUobG9j
YWwudmFsdWUoIm5ldHdvcmsiKS50b1N0cmluZygpLCBRU3RyaW5nKCJ3bGFuMCIpKTsgUVZFUklG
WShsb2NhbC52YWx1ZSgiY29ubmVjdGVkIikudG9Cb29sKCkpOworICAgICAgICB3cml0ZSgiL2Ns
YXNzL3Bvd2VyX3N1cHBseS9CQVQwL2NhcGFjaXR5IiwgIjEwMSIpOyBRQ09NUEFSRShDcmltc29u
U3RhdHVzOjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpLnZhbHVlKCJiYXR0ZXJ5UGVyY2VudCIpLnRv
SW50KCksIC0xKTsKKyAgICB9CisgICAgdm9pZCBwcml2YXRlU2V0dGluZ3NBbmROb0Nyb3NzSG9z
dENyZWRlbnRpYWxzKCkgeworICAgICAgICBRU3RhbmRhcmRQYXRoczo6c2V0VGVzdE1vZGVFbmFi
bGVkKHRydWUpOworICAgICAgICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVjdEhv
c3QoInRlc3QtYSIsICJodHRwczovLzEyNy4wLjAuMTo0Nzk5MCIpOworICAgICAgICBRVkVSSUZZ
KHN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4xOjQ3OTkwIiwgImZpeHR1cmUtdG9r
ZW4iLCAiIikpOyBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmVkKCkpOworICAgICAgICBhdXRvIHBh
dGggPSBRU3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRhcmRQYXRoczo6QXBw
Q29uZmlnTG9jYXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpzb24iOworICAgICAgICBRVkVSSUZZ
KChRRmlsZTo6cGVybWlzc2lvbnMocGF0aCkgJiAoUUZpbGVEZXZpY2U6OlJlYWRHcm91cCB8IFFG
aWxlRGV2aWNlOjpSZWFkT3RoZXIgfCBRRmlsZURldmljZTo6V3JpdGVHcm91cCB8IFFGaWxlRGV2
aWNlOjpXcml0ZU90aGVyKSkgPT0gMCk7CisgICAgICAgIHN0YXR1cy5zZWxlY3RIb3N0KCJ0ZXN0
LWIiLCAiaHR0cHM6Ly8xMjcuMC4wLjI6NDc5OTAiKTsgUVZFUklGWSghc3RhdHVzLmNvbmZpZ3Vy
ZWQoKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAu
MC4yOjQ3OTkwIiwgIiIsICIiKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUo
Imh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIiwgImZpeHR1cmUtdG9rZW4iLCAiaW52YWxpZC1waW4i
KSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4y
OjQ3OTkwIiwgInRva2VuXG5pbmplY3Rpb24iLCAiIikpOworICAgICAgICBRRmlsZTo6cmVtb3Zl
KHBhdGgpOworICAgIH0KKyAgICB2b2lkIHRsc0F1dGhlbnRpY2F0aW9uQW5kVmlzaWJpbGl0eSgp
IHsKKyAgICAgICAgVGxzRml4dHVyZSBzZXJ2ZXI7IFFWRVJJRlkoc2VydmVyLmlzTGlzdGVuaW5n
KCkpOyBRVkVSSUZZKCFzZXJ2ZXIuY2VydC5pc051bGwoKSk7CisgICAgICAgIFFTdHJpbmcgdXJs
ID0gImh0dHBzOi8vMTI3LjAuMC4xOiIgKyBRU3RyaW5nOjpudW1iZXIoc2VydmVyLnNlcnZlclBv
cnQoKSk7CisgICAgICAgIFFTdHJpbmcgcGluID0gUVN0cmluZzo6ZnJvbUxhdGluMShzZXJ2ZXIu
Y2VydC5kaWdlc3QoUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpOworICAgICAg
ICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVjdEhvc3QoImZpeHR1cmUtdGxzIiwg
dXJsKTsKKyAgICAgICAgUVZFUklGWShzdGF0dXMuY29uZmlndXJlKHVybCwgImZpeHR1cmUtb25s
eS10b2tlbiIsICIiKSk7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAgICBRVFJZX1ZF
UklGWV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0YXR1cygpLmNvbnRhaW5zKCJmaW5nZXJwcmludCIp
LCA1MDAwKTsKKyAgICAgICAgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCAwKTsgLy8gbm8gY3Jl
ZGVudGlhbHMgc2VudCBiZWZvcmUgdHJ1c3Rpbmcgc2VsZi1zaWduZWQgVExTCisgICAgICAgIFFW
RVJJRlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJmaXh0dXJlLW9ubHktdG9rZW4iLCBwaW4pKTsK
KyAgICAgICAgUVRSWV9DT01QQVJFX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS52YWx1ZSgi
Y3B1X3BlcmNlbnQiKS50b0RvdWJsZSgpLCAzNy41LCA1MDAwKTsKKyAgICAgICAgUVZFUklGWShz
ZXJ2ZXIuYXV0aG9yaXphdGlvbi5jb250YWlucygiQXV0aG9yaXphdGlvbjogQmVhcmVyIGZpeHR1
cmUtb25seS10b2tlbiIpKTsKKyAgICAgICAgUVZFUklGWShzZXJ2ZXIuYXV0aG9yaXphdGlvbi5z
dGFydHNXaXRoKCJHRVQgL2FwaS9ob3N0L3N0YXRzICIpKTsKKyAgICAgICAgc3RhdHVzLnNldFZp
c2libGUoZmFsc2UpOyBpbnQgY291bnQgPSBzZXJ2ZXIucmVxdWVzdHM7IFFUZXN0OjpxV2FpdCgy
MTAwKTsgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCBjb3VudCk7CisgICAgICAgIGZvciAoaW50
IGNvZGUgOiB7NDAxLCA0MDMsIDQwNCwgMzAyfSkgeworICAgICAgICAgICAgc2VydmVyLmNvZGUg
PSBjb2RlOyBpbnQgcHJpb3IgPSBzZXJ2ZXIucmVxdWVzdHM7IHN0YXR1cy5zZXRWaXNpYmxlKHRy
dWUpOworICAgICAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHNlcnZlci5yZXF1ZXN0
cyA+IHByaW9yLCA1MDAwKTsKKyAgICAgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9VVChz
dGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOworICAgICAgICAgICAgc3RhdHVzLnNldFZp
c2libGUoZmFsc2UpOworICAgICAgICB9CisgICAgICAgIHNlcnZlci5jb2RlID0gMjAwOyBzZXJ2
ZXIuYm9keSA9IFFCeXRlQXJyYXkoNzAwMDAsICdhJyk7IGludCBwcmlvciA9IHNlcnZlci5yZXF1
ZXN0czsgc3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAgICAgIFFUUllfVkVSSUZZX1dJVEhf
VElNRU9VVChzZXJ2ZXIucmVxdWVzdHMgPiBwcmlvciwgNTAwMCk7CisgICAgICAgIFFUUllfVkVS
SUZZX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOyBzdGF0dXMu
c2V0VmlzaWJsZShmYWxzZSk7CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmws
ICJmaXh0dXJlLW9ubHktdG9rZW4iLCBRU3RyaW5nKDY0LCAnMCcpKSk7IHN0YXR1cy5zZXRWaXNp
YmxlKHRydWUpOworICAgICAgICBjb3VudCA9IHNlcnZlci5yZXF1ZXN0czsgUVRlc3Q6OnFXYWl0
KDUwMCk7IFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywgY291bnQpOyBRVkVSSUZZKHN0YXR1cy5z
dGF0cygpLmlzRW1wdHkoKSk7CisgICAgICAgIHN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsKKyAg
ICB9CisgICAgdm9pZCByb3VuZGVkT3ZlcmxheUFjY2VudHNBbmRPcGFjaXR5KCkgeworICAgICAg
ICBmb3IoaW50IGFjY2VudD0wO2FjY2VudDwxNjsrK2FjY2VudCkgeworICAgICAgICAgICAgYXV0
byBpbWFnZT1FY2xpcHNlT3ZlcmxheVN0eWxlOjpwYW5lbChRU2l6ZSg0MDAsMTgwKSxhY2NlbnQs
ODUpOyBRVkVSSUZZKCFpbWFnZS5pc051bGwoKSk7CisgICAgICAgICAgICBRQ09NUEFSRShpbWFn
ZS5waXhlbENvbG9yKDAsMCkuYWxwaGEoKSwwKTsKKyAgICAgICAgICAgIFFDT01QQVJFKGltYWdl
LnBpeGVsQ29sb3IoMjAwLDkwKS5hbHBoYSgpLDg1KjI1NS8xMDApOworICAgICAgICAgICAgUUNP
TVBBUkUoaW1hZ2UucGl4ZWxDb2xvcigyMDAsOCkucmdiKCksRWNsaXBzZU92ZXJsYXlTdHlsZTo6
YWNjZW50KGFjY2VudCkucmdiKCkpOworICAgICAgICB9CisgICAgICAgIFFWRVJJRlkoRWNsaXBz
ZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNpemUoLTEsMTAwKSwwLDg1KS5pc051bGwoKSk7CisgICAg
ICAgIFFWRVJJRlkoRWNsaXBzZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNpemUoNDA5NiwxMDApLDAs
ODUpLmlzTnVsbCgpKTsKKyAgICB9CisgICAgdm9pZCBncmFwaFNhbXBsZXNQcmVzZXJ2ZU1pc3Np
bmdBbmRXaW5kb3coKSB7CisgICAgICAgIGF1dG8gdmFsdWVzPUNyaW1zb25HcmFwaHM6OnZhbHVl
cygiVmlkZW8gc3RyZWFtOiAxOTIweDEwODAgMTIwLjAwIEZQU1xuUmVuZGVyaW5nIGZyYW1lIHJh
dGU6IDU5LjI1IEZQU1xuQXZlcmFnZSBuZXR3b3JrIGxhdGVuY3k6IDEyIG1zIixmYWxzZSx7eyJj
cHVQZXJjZW50IiwyNS4wfSx7Im1lbW9yeVVzZWRHaUIiLDQuNX19KTsKKyAgICAgICAgUUNPTVBB
UkUodmFsdWVzWyJGUFMiXSw1OS4yNSk7UUNPTVBBUkUodmFsdWVzWyJOZXR3b3JrIGxhdGVuY3ki
XSwxMi4wKTtRQ09NUEFSRSh2YWx1ZXNbIkxvY2FsIENQVSJdLDI1LjApOworICAgICAgICBhdXRv
IGNvbXBhY3Q9Q3JpbXNvbkdyYXBoczo6dmFsdWVzKCI2MCBmcHMgwrcgMTkyMHgxMDgwIEgyNjQg
wrcgbmV0IDcgbXMgwrcgZGVjIDIuMCBtcyIsZmFsc2Use30pOworICAgICAgICBRQ09NUEFSRShj
b21wYWN0WyJGUFMiXSw2MC4wKTtRQ09NUEFSRShjb21wYWN0WyJOZXR3b3JrIGxhdGVuY3kiXSw3
LjApO1FWRVJJRlkocUlzTmFOKGNvbXBhY3RbIkxvY2FsIFJBTSJdKSk7CisgICAgICAgIGF1dG8g
dW5hdmFpbGFibGU9Q3JpbXNvbkdyYXBoczo6dmFsdWVzKCJBdmVyYWdlIG5ldHdvcmsgbGF0ZW5j
eTogTi9BXG5WaWRlbyBzdHJlYW06IDE5MjB4MTA4MCAxMjAuMDAgRlBTIixmYWxzZSx7fSk7Cisg
ICAgICAgIFFWRVJJRlkocUlzTmFOKHVuYXZhaWxhYmxlWyJGUFMiXSkpO1FWRVJJRlkocUlzTmFO
KHVuYXZhaWxhYmxlWyJOZXR3b3JrIGxhdGVuY3kiXSkpOworICAgICAgICBhdXRvIGludmFsaWQ9
Q3JpbXNvbkdyYXBoczo6dmFsdWVzKCIiLHRydWUse3siY3B1UGVyY2VudCIsUVZhcmlhbnQoKX0s
eyJtZW1vcnlVc2VkR2lCIiwiaW52YWxpZCJ9LHsidGVtcGVyYXR1cmVDIiwtMX0seyJyZWNlaXZl
TWlCIiwwLjB9fSk7CisgICAgICAgIFFWRVJJRlkocUlzTmFOKGludmFsaWRbIkxvY2FsIENQVSJd
KSk7UVZFUklGWShxSXNOYU4oaW52YWxpZFsiTG9jYWwgUkFNIl0pKTtRVkVSSUZZKHFJc05hTihp
bnZhbGlkWyJUZW1wZXJhdHVyZSJdKSk7UUNPTVBBUkUoaW52YWxpZFsiRG93bmxvYWQiXSwwLjAp
OworICAgICAgICBDcmltc29uR3JhcGhzOjpIaXN0b3J5IGhpc3Rvcnk7Zm9yKGludCBpPTA7aTw4
MDtpKyspQ3JpbXNvbkdyYXBoczo6cHVzaChoaXN0b3J5LHZhbHVlcyk7CisgICAgICAgIFFDT01Q
QVJFKGhpc3RvcnlbIkZQUyJdLnNpemUoKSw2MCk7Q3JpbXNvbkdyYXBoczo6cHVzaChoaXN0b3J5
LHVuYXZhaWxhYmxlKTtRVkVSSUZZKHFJc05hTihoaXN0b3J5WyJGUFMiXS5sYXN0KCkpKTsKKyAg
ICAgICAgZm9yKGludCBpPTA7aTw2MDtpKyspe3ZhbHVlc1siRlBTIl09NjArcVNpbihpKjAuNCkq
Mjt2YWx1ZXNbIk5ldHdvcmsgbGF0ZW5jeSJdPTEyK3FTaW4oaSowLjMpKjM7dmFsdWVzWyJMb2Nh
bCBDUFUiXT0yNStxU2luKGkqMC41KSoxMDt2YWx1ZXNbIkxvY2FsIFJBTSJdPTQuNStxU2luKGkq
MC4yKSowLjI7Q3JpbXNvbkdyYXBoczo6cHVzaChoaXN0b3J5LHZhbHVlcyk7fQorICAgICAgICBR
SW1hZ2UgaW1hZ2U9RWNsaXBzZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNpemUoNDgwLDI1MCksNCw4
NSk7Q3JpbXNvbkdyYXBoczo6cGFpbnQoaW1hZ2UsNDAsMTgsNCxoaXN0b3J5LGZhbHNlKTsKKyAg
ICAgICAge1FQYWludGVyIHBhaW50ZXIoJmltYWdlKTtwYWludGVyLnNldFBlbihRQ29sb3IoIiNF
Q0VFRjEiKSk7cGFpbnRlci5kcmF3VGV4dCgxNiwyOCwiRWNsaXBzZU9TIHwgU1RSRUFNIOKAlCBn
cmFwaCBmaXh0dXJlIik7fQorICAgICAgICBRU3RyaW5nIG91dD1xRW52aXJvbm1lbnRWYXJpYWJs
ZSgiQ1JJTVNPTl9TQ1JFRU5TSE9UUyIpO2lmKCFvdXQuaXNFbXB0eSgpKXtRRGlyKCkubWtwYXRo
KG91dCk7UVZFUklGWShpbWFnZS5zYXZlKG91dCsiL2NyaW1zb24tZ2xhc3Mtb3ZlcmxheS5wbmci
KSk7fQorICAgIH0KKyAgICB2b2lkIGJhY2tncm91bmRTZWxlY3Rpb25BbmRQZXJzaXN0ZW5jZSgp
IHsKKyAgICAgICAgRWNsaXBzZVByb2ZpbGVzIHByb2ZpbGU7cHJvZmlsZS5yZXNldEJhY2tncm91
bmQoKTtRVGVtcG9yYXJ5RGlyIGZvbGRlcjtRVkVSSUZZKGZvbGRlci5pc1ZhbGlkKCkpOworICAg
ICAgICBRSW1hZ2UgaW5wdXQoMzAwMCwxODAwLFFJbWFnZTo6Rm9ybWF0X1JHQjMyKTtpbnB1dC5m
aWxsKFFDb2xvcigiIzc3MjIzMyIpKTtRU3RyaW5nIHNvdXJjZT1mb2xkZXIuZmlsZVBhdGgoIndh
bGxwYXBlci5wbmciKTtRVkVSSUZZKGlucHV0LnNhdmUoc291cmNlKSk7CisgICAgICAgIFFWRVJJ
RlkoIXByb2ZpbGUuY2hvb3NlQmFja2dyb3VuZChRVXJsKCJodHRwczovL2V4YW1wbGUuY29tL3dh
bGxwYXBlci5wbmciKSkpOworICAgICAgICBRVkVSSUZZKCFwcm9maWxlLmNob29zZUJhY2tncm91
bmQoUVVybDo6ZnJvbUxvY2FsRmlsZShmb2xkZXIuZmlsZVBhdGgoIm1pc3NpbmcucG5nIikpKSk7
CisgICAgICAgIFFGaWxlIGludmFsaWQoZm9sZGVyLmZpbGVQYXRoKCJpbnZhbGlkLnBuZyIpKTtR
VkVSSUZZKGludmFsaWQub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpO2ludmFsaWQud3JpdGUo
Im5vdCBhbiBpbWFnZSIpO2ludmFsaWQuY2xvc2UoKTsKKyAgICAgICAgUVZFUklGWSghcHJvZmls
ZS5jaG9vc2VCYWNrZ3JvdW5kKFFVcmw6OmZyb21Mb2NhbEZpbGUoaW52YWxpZC5maWxlTmFtZSgp
KSkpOworICAgICAgICBRRmlsZSBvdmVyc2l6ZWQoZm9sZGVyLmZpbGVQYXRoKCJvdmVyc2l6ZWQu
cG5nIikpO1FWRVJJRlkob3ZlcnNpemVkLm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTtRVkVS
SUZZKG92ZXJzaXplZC5yZXNpemUoMzIqMTAyNCoxMDI0KzEpKTtvdmVyc2l6ZWQuY2xvc2UoKTsK
KyAgICAgICAgUVZFUklGWSghcHJvZmlsZS5jaG9vc2VCYWNrZ3JvdW5kKFFVcmw6OmZyb21Mb2Nh
bEZpbGUob3ZlcnNpemVkLmZpbGVOYW1lKCkpKSk7CisgICAgICAgIFFWRVJJRlkocHJvZmlsZS5j
aG9vc2VCYWNrZ3JvdW5kKFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNlKSkpO1FWRVJJRlkocHJv
ZmlsZS5iYWNrZ3JvdW5kKCkuaXNMb2NhbEZpbGUoKSk7CisgICAgICAgIFFTdHJpbmcgc2F2ZWQ9
cHJvZmlsZS5iYWNrZ3JvdW5kKCkudG9Mb2NhbEZpbGUoKTtRVkVSSUZZKHNhdmVkIT1zb3VyY2Up
O1FWRVJJRlkoUUZpbGU6OnJlbW92ZShzb3VyY2UpKTtRVkVSSUZZKCFRSW1hZ2Uoc2F2ZWQpLmlz
TnVsbCgpKTtRVkVSSUZZKFFJbWFnZShzYXZlZCkud2lkdGgoKTw9MjU2MCk7CisgICAgICAgIEVj
bGlwc2VQcm9maWxlcyByZWxvYWRlZDtRQ09NUEFSRShyZWxvYWRlZC5iYWNrZ3JvdW5kKCkscHJv
ZmlsZS5iYWNrZ3JvdW5kKCkpO3JlbG9hZGVkLnNldEJhY2tncm91bmREaW0oMCk7UUNPTVBBUkUo
cmVsb2FkZWQuYmFja2dyb3VuZERpbSgpLDMwKTtyZWxvYWRlZC5zZXRCYWNrZ3JvdW5kRGltKDk5
OSk7UUNPTVBBUkUocmVsb2FkZWQuYmFja2dyb3VuZERpbSgpLDkwKTsKKyAgICAgICAgUVZFUklG
WSghcHJvZmlsZS5iYWNrZ3JvdW5kRmlsZXMoUVVybCgiaHR0cHM6Ly9leGFtcGxlLmNvbS8iKSku
c2l6ZSgpKTtwcm9maWxlLnJlc2V0QmFja2dyb3VuZCgpO1FWRVJJRlkocHJvZmlsZS5iYWNrZ3Jv
dW5kKCkuaXNFbXB0eSgpKTtwcm9maWxlLnNldEJhY2tncm91bmREaW0oNjUpOworICAgIH0KKyAg
ICB2b2lkIGhhcmR3YXJlVmlzaWJsZUNvbnN1bWVycygpIHsKKyAgICAgICAgTG9jYWxIYXJkd2Fy
ZSBtb25pdG9yO21vbml0b3Iuc2V0UmVmcmVzaFNlY29uZHMoMSk7UU9iamVjdCBmaXJzdCxzZWNv
bmQ7UVNpZ25hbFNweSBzYW1wbGVzKCZtb25pdG9yLCZMb2NhbEhhcmR3YXJlOjpjaGFuZ2VkKTsK
KyAgICAgICAgbW9uaXRvci5zZXRDb25zdW1lckFjdGl2ZSgmZmlyc3QsdHJ1ZSk7UUNPTVBBUkUo
c2FtcGxlcy5jb3VudCgpLDEpOworICAgICAgICBtb25pdG9yLnNldENvbnN1bWVyQWN0aXZlKCZm
aXJzdCx0cnVlKTtRQ09NUEFSRShzYW1wbGVzLmNvdW50KCksMSk7CisgICAgICAgIG1vbml0b3Iu
c2V0Q29uc3VtZXJBY3RpdmUoJnNlY29uZCx0cnVlKTttb25pdG9yLnNldENvbnN1bWVyQWN0aXZl
KCZmaXJzdCxmYWxzZSk7CisgICAgICAgIG1vbml0b3Iuc2V0QWN0aXZlKHRydWUpO21vbml0b3Iu
c2V0QWN0aXZlKGZhbHNlKTsgLy8gbGVnYWN5IGNhbGxlciBtdXN0IG5vdCByZXZva2UgYW5vdGhl
ciB2aWV3J3MgbGVhc2UKKyAgICAgICAgUVRlc3Q6OnFXYWl0KDIxMDApO1FWRVJJRlkoc2FtcGxl
cy5jb3VudCgpPj0yKTsKKyAgICAgICAgbW9uaXRvci5zZXRDb25zdW1lckFjdGl2ZSgmc2Vjb25k
LGZhbHNlKTtpbnQgY291bnQ9c2FtcGxlcy5jb3VudCgpO1FUZXN0OjpxV2FpdCgyMTAwKTtRQ09N
UEFSRShzYW1wbGVzLmNvdW50KCksY291bnQpOworICAgIH0KKyAgICB2b2lkIGxvY2FsSGFyZHdh
cmVDb3VudGVyc0FuZFNlbnNvcnMoKSB7CisgICAgICAgIFFUZW1wb3JhcnlEaXIgcm9vdDsgUVZF
UklGWShyb290LmlzVmFsaWQoKSk7CisgICAgICAgIGF1dG8gd3JpdGU9WyZdKGNvbnN0IFFTdHJp
bmcmIHBhdGgsY29uc3QgUUJ5dGVBcnJheSYgZGF0YSkgeyBRU3RyaW5nIGZ1bGw9cm9vdC5wYXRo
KCkrcGF0aDsgUURpcigpLm1rcGF0aChRRmlsZUluZm8oZnVsbCkuYWJzb2x1dGVQYXRoKCkpOyBR
RmlsZSBmaWxlKGZ1bGwpOyBRVkVSSUZZKGZpbGUub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkp
OyBRQ09NUEFSRShmaWxlLndyaXRlKGRhdGEpLHFpbnQ2NChkYXRhLnNpemUoKSkpOyB9OworICAg
ICAgICBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS9oYXJkd2FyZVJlZnJlc2giLDEpOwor
ICAgICAgICB3cml0ZSgiL3Byb2Mvc3RhdCIsImNwdSAxMDAgMCAxMDAgODAwIDAgMCAwIDBcbiIp
OworICAgICAgICB3cml0ZSgiL3Byb2MvbWVtaW5mbyIsIk1lbVRvdGFsOiAxMDQ4NTc2IGtCXG5N
ZW1BdmFpbGFibGU6IDI2MjE0NCBrQlxuU3dhcFRvdGFsOiAxMDI0IGtCXG5Td2FwRnJlZTogNTEy
IGtCXG4iKTsKKyAgICAgICAgd3JpdGUoIi9zeXMvY2xhc3MvaHdtb24vaHdtb24wL25hbWUiLCJj
b3JldGVtcCIpOyB3cml0ZSgiL3N5cy9jbGFzcy9od21vbi9od21vbjAvdGVtcDFfaW5wdXQiLCI2
MjUwMCIpOworICAgICAgICB3cml0ZSgiL3N5cy9jbGFzcy9od21vbi9od21vbjAvZmFuMV9pbnB1
dCIsIjI0MDAiKTsKKyAgICAgICAgd3JpdGUoIi9wcm9jL25ldC9yb3V0ZSIsIklmYWNlIERlc3Rp
bmF0aW9uIEdhdGV3YXkgRmxhZ3NcbndsYW4wIDAwMDAwMDAwIDAxMDIwMzA0IDAwMDNcbiIpOwor
ICAgICAgICB3cml0ZSgiL3Byb2MvbmV0L2RldiIsIndsYW4wOiAxMDAwIDAgMCAwIDAgMCAwIDAg
MjAwMCAwIDAgMCAwIDAgMCAwXG4iKTsKKyAgICAgICAgUUJ5dGVBcnJheSB2aWRlbz0iZHJtLWNs
aWVudC1pZDogN1xuZHJtLWVuZ2luZS12aWRlbzogMTAwMDAwMDAwIG5zXG4iOworICAgICAgICB3
cml0ZSgiL3Byb2Mvc2VsZi9mZGluZm8vMSIsdmlkZW8pOyB3cml0ZSgiL3Byb2Mvc2VsZi9mZGlu
Zm8vMiIsdmlkZW8pOworICAgICAgICBhdXRvIGZpcnN0PUxvY2FsSGFyZHdhcmU6OnNhbXBsZShy
b290LnBhdGgoKSk7IFFWRVJJRlkoIWZpcnN0LmNvbnRhaW5zKCJjcHVQZXJjZW50IikpOyBRVkVS
SUZZKCFmaXJzdC5jb250YWlucygidmlkZW9QZXJjZW50IikpOworICAgICAgICBRQ09NUEFSRShm
aXJzdFsibWVtb3J5UGVyY2VudCJdLnRvRG91YmxlKCksNzUuMCk7IFFDT01QQVJFKGZpcnN0WyJ0
ZW1wZXJhdHVyZUMiXS50b0RvdWJsZSgpLDYyLjUpOyBRQ09NUEFSRShmaXJzdFsiZmFuUlBNIl0u
dG9Eb3VibGUoKSwyNDAwLjApOworICAgICAgICBRVGVzdDo6cVdhaXQoMTA1MCk7CisgICAgICAg
IHdyaXRlKCIvcHJvYy9zdGF0IiwiY3B1IDE1MCAwIDE1MCA5MDAgMCAwIDAgMFxuIik7CisgICAg
ICAgIHZpZGVvPSJkcm0tY2xpZW50LWlkOiA3XG5kcm0tZW5naW5lLXZpZGVvOiAyMDAwMDAwMDAg
bnNcbiI7CisgICAgICAgIHdyaXRlKCIvcHJvYy9zZWxmL2ZkaW5mby8xIix2aWRlbyk7IHdyaXRl
KCIvcHJvYy9zZWxmL2ZkaW5mby8yIix2aWRlbyk7CisgICAgICAgIHdyaXRlKCIvcHJvYy9uZXQv
ZGV2Iiwid2xhbjA6IDEwNDk1NzYgMCAwIDAgMCAwIDAgMCA1MjYyODggMCAwIDAgMCAwIDAgMFxu
Iik7CisgICAgICAgIGF1dG8gc2Vjb25kPUxvY2FsSGFyZHdhcmU6OnNhbXBsZShyb290LnBhdGgo
KSk7IFFDT01QQVJFKHNlY29uZFsiY3B1UGVyY2VudCJdLnRvRG91YmxlKCksNTAuMCk7CisgICAg
ICAgIFFWRVJJRlkoc2Vjb25kWyJ2aWRlb1BlcmNlbnQiXS50b0RvdWJsZSgpPjUgJiYgc2Vjb25k
WyJ2aWRlb1BlcmNlbnQiXS50b0RvdWJsZSgpPDExKTsgLy8gZHVwbGljYXRlIGZkIG11c3Qgbm90
IGRvdWJsZS1jb3VudAorICAgICAgICBRVkVSSUZZKHNlY29uZFsicmVjZWl2ZU1pQiJdLnRvRG91
YmxlKCk+LjUgJiYgc2Vjb25kWyJyZWNlaXZlTWlCIl0udG9Eb3VibGUoKTwxLjEpOworICAgICAg
ICBRVGVzdDo6cVdhaXQoMTA1MCk7CisgICAgICAgIHdyaXRlKCIvcHJvYy9zdGF0IiwiY3B1IDEg
MCAxIDEgMCAwIDAgMFxuIik7IHdyaXRlKCIvcHJvYy9uZXQvZGV2Iiwid2xhbjA6IDEgMCAwIDAg
MCAwIDAgMCAxIDAgMCAwIDAgMCAwIDBcbiIpOworICAgICAgICBhdXRvIHJlc2V0PUxvY2FsSGFy
ZHdhcmU6OnNhbXBsZShyb290LnBhdGgoKSk7IFFWRVJJRlkoIXJlc2V0LmNvbnRhaW5zKCJjcHVQ
ZXJjZW50IikpOyBRVkVSSUZZKCFyZXNldC5jb250YWlucygicmVjZWl2ZU1pQiIpKTsKKyAgICAg
ICAgUVNldHRpbmdzKCkuc2V0VmFsdWUoImVjbGlwc2UvaGFyZHdhcmVSZWZyZXNoIiwyKTsKKyAg
ICB9CisgICAgdm9pZCBsb2NhbEhhcmR3YXJlVW5hdmFpbGFibGVBbmRCb3VuZHMoKSB7CisgICAg
ICAgIFFUZW1wb3JhcnlEaXIgcm9vdDsgUVZFUklGWShyb290LmlzVmFsaWQoKSk7CisgICAgICAg
IGF1dG8gZW1wdHk9TG9jYWxIYXJkd2FyZTo6c2FtcGxlKHJvb3QucGF0aCgpKTsgUVZFUklGWShl
bXB0eS5pc0VtcHR5KCkpOworICAgICAgICBMb2NhbEhhcmR3YXJlIG1vbml0b3I7IG1vbml0b3Iu
c2V0UG9zaXRpb24oOTk5KTsgUUNPTVBBUkUobW9uaXRvci5wb3NpdGlvbigpLDMpOworICAgICAg
ICBtb25pdG9yLnNldE9wYWNpdHkoLTUpOyBRQ09NUEFSRShtb25pdG9yLm9wYWNpdHkoKSw0MCk7
CisgICAgICAgIG1vbml0b3Iuc2V0UmVmcmVzaFNlY29uZHMoOTk5KTsgUUNPTVBBUkUobW9uaXRv
ci5yZWZyZXNoU2Vjb25kcygpLDUpOworICAgICAgICBtb25pdG9yLnNldEZpZWxkcyh7ImNwdSIs
InBhc3N3b3JkIiwibWVtb3J5In0pOyBRQ09NUEFSRShtb25pdG9yLmZpZWxkcygpLFFTdHJpbmdM
aXN0KHsiY3B1IiwibWVtb3J5In0pKTsKKyAgICAgICAgbW9uaXRvci5zZXRPdmVybGF5KGZhbHNl
KTsgbW9uaXRvci5zZXRSZWZyZXNoU2Vjb25kcygyKTsgbW9uaXRvci5zZXRPcGFjaXR5KDg1KTsK
KyAgICB9CisgICAgdm9pZCBzY2FuUHJvZ3Jlc3NCZWZvcmVDb21wbGV0aW9uKCkgeworICAgICAg
ICBRVGVtcG9yYXJ5RGlyIGRpcjsgUUZpbGUgc2NyaXB0KGRpci5maWxlUGF0aCgic2Nhbi5weSIp
KTsgUVZFUklGWShzY3JpcHQub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOworICAgICAgICBz
Y3JpcHQud3JpdGUoUiJQWShpbXBvcnQganNvbixzeXMsdGltZQorZm9yIGxpbmUgaW4gc3lzLnN0
ZGluOgorICAgIHJlcXVlc3Q9anNvbi5sb2FkcyhsaW5lKQorICAgIGlmIHJlcXVlc3RbJ2FjdGlv
biddPT0nYnQtc2Nhbic6CisgICAgICAgIHByaW50KGpzb24uZHVtcHMoeydpdGVtcyc6W3snaWQn
OidBQTpCQjpDQzpERDpFRTpGRicsJ25hbWUnOidDb250cm9sbGVyJ31dLCdzdGF0dXMnOidTY2Fu
bmluZyd9KSxmbHVzaD1UcnVlKQorICAgICAgICB0aW1lLnNsZWVwKC41KQorICAgIHByaW50KGpz
b24uZHVtcHMoeydpdGVtcyc6W3snaWQnOidBQTpCQjpDQzpERDpFRTpGRicsJ25hbWUnOidDb250
cm9sbGVyJ31dLCdzdGF0dXMnOidSZWFkeScsJ2RvbmUnOlRydWV9KSxmbHVzaD1UcnVlKQorKVBZ
Iik7IHNjcmlwdC5jbG9zZSgpOyBxcHV0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIs
c2NyaXB0LmZpbGVOYW1lKCkudG9VdGY4KCkpOworICAgICAgICBTeXN0ZW1Db250cm9scyBjOyBj
Lm9wZW4oImJ0Iik7IFFUUllfVkVSSUZZKCFjLmJ1c3koKSAmJiAhYy5pdGVtcygpLmlzRW1wdHko
KSk7CisgICAgICAgIGMucmVxdWVzdCgiYnQtc2NhbiIpOyBRVFJZX0NPTVBBUkUoYy5zdGF0dXMo
KSxRU3RyaW5nKCJTY2FubmluZyIpKTsgUVZFUklGWShjLmJ1c3koKSk7IFFDT01QQVJFKGMuaXRl
bXMoKS5zaXplKCksMSk7CisgICAgICAgIFFUUllfVkVSSUZZKCFjLmJ1c3koKSk7IGMuY2xvc2Uo
KTsgcXVuc2V0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIpOworICAgIH0KKyAgICB2
b2lkIGljb25SZXNvdXJjZXMoKSB7CisgICAgICAgIGZvciAoY29uc3QgUVN0cmluZyYgbmFtZSA6
IHsiZWNsaXBzZS1pY29uIiwgImVjbGlwc2UtY29udHJvbHMiLCAiZWNsaXBzZS1wb3dlciIsICJj
cmltc29uLW5ldHdvcmsiLCAiY3JpbXNvbi1ibHVldG9vdGgiLCAiY3JpbXNvbi1iYXR0ZXJ5Iiwg
ImNyaW1zb24taG9zdCIsICJzZXR0aW5ncyJ9KSB7CisgICAgICAgICAgICBjb25zdCBRU3RyaW5n
IHBhdGggPSAiOi9yZXMvIiArIG5hbWUgKyAiLnN2ZyI7CisgICAgICAgICAgICBRVkVSSUZZMihR
RmlsZTo6ZXhpc3RzKHBhdGgpLCBxUHJpbnRhYmxlKHBhdGgpKTsKKyAgICAgICAgICAgIFFJbWFn
ZVJlYWRlciByZWFkZXIocGF0aCk7CisgICAgICAgICAgICBRVkVSSUZZMighcmVhZGVyLnJlYWQo
KS5pc051bGwoKSwgcVByaW50YWJsZShwYXRoICsgIjogIiArIHJlYWRlci5lcnJvclN0cmluZygp
KSk7CisgICAgICAgIH0KKyAgICB9CisgICAgdm9pZCBxbWxQYWxldHRlQW5kUGFuZWxzKCkgewor
ICAgICAgICBRU3RyaW5nIHNvdXJjZSA9IHFFbnZpcm9ubWVudFZhcmlhYmxlKCJWSUJFTUlTX1RF
U1RfU09VUkNFIik7IFFWRVJJRlkoIXNvdXJjZS5pc0VtcHR5KCkpOworICAgICAgICBRUXVpY2tT
dHlsZTo6c2V0U3R5bGUoIk1hdGVyaWFsIik7CisgICAgICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9u
VHlwZShRVXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSArICIvYXBwL21vb25saWdodG9zL3Rlc3Rz
L1ByZWZlcmVuY2VzLnFtbCIpLCAiU3RyZWFtaW5nUHJlZmVyZW5jZXMiLCAxLCAwLCAiU3RyZWFt
aW5nUHJlZmVyZW5jZXMiKTsKKyAgICAgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlKFFVcmw6
OmZyb21Mb2NhbEZpbGUoc291cmNlICsgIi9hcHAvZ3VpL1ZiVG9rZW5zLnFtbCIpLCAiVmliZW1p
cy5SZWRlc2lnbiIsIDEsIDAsICJWYlRva2VucyIpOworICAgICAgICBRVGVtcG9yYXJ5RGlyIGNv
bnRyb2xzRml4dHVyZTsgUVZFUklGWShjb250cm9sc0ZpeHR1cmUuaXNWYWxpZCgpKTsKKyAgICAg
ICAgUUZpbGUgaGVscGVyKGNvbnRyb2xzRml4dHVyZS5maWxlUGF0aCgiaGVscGVyLnB5IikpOyBR
VkVSSUZZKGhlbHBlci5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7CisgICAgICAgIGhlbHBl
ci53cml0ZShSIlBZKGltcG9ydCBqc29uLHN5cworZm9yIGxpbmUgaW4gc3lzLnN0ZGluOgorICAg
IHZhbHVlPWpzb24ubG9hZHMobGluZSkKKyAgICBwcmludChqc29uLmR1bXBzKHsnc3RhdGUnOnsn
dm9sdW1lJzo1MCwnbXV0ZWQnOkZhbHNlLCd3aWZpX2VuYWJsZWQnOlRydWUsJ2JsdWV0b290aF9l
bmFibGVkJzpUcnVlLCdkaXNwbGF5cyc6W3snaWQnOidlRFAtMXwxMDI0eDY0MHw2MCcsJ25hbWUn
OidlRFAtMSDCtyAxMDI0w5c2NDAgwrcgNjAgSHonLCdjdXJyZW50JzpUcnVlfV0sJ3BvaW50ZXJz
JzpbeydpZCc6JzEyJywnbmFtZSc6J1RvdWNocGFkJywnc3BlZWQnOjAsJ25hdHVyYWwnOlRydWUs
J3RhcCc6VHJ1ZX1dLCdzaW5rcyc6W3snaWQnOic0MicsJ25hbWUnOidTcGVha2VycycsJ2RlZmF1
bHQnOlRydWV9LHsnaWQnOic1NycsJ25hbWUnOidBaXJQb2RzJywnZGVmYXVsdCc6RmFsc2V9XSwn
YnJpZ2h0bmVzcyc6eydzY3JlZW4nOnsnZGV2aWNlJzonaW50ZWxfYmFja2xpZ2h0JywncGVyY2Vu
dCc6NjB9LCdrZXlib2FyZCc6eydkZXZpY2UnOidzcGk6OmtiZF9iYWNrbGlnaHQnLCdwZXJjZW50
JzozMH19LCdvcyc6eydOQU1FJzonRWNsaXBzZU9TJywnVkVSU0lPTic6JzAuMy1kZXYnLCdUQVJH
RVQnOidGaXh0dXJlIGhhcmR3YXJlJywnRkVET1JBJzonNDQnfSwna2VybmVsJzonZml4dHVyZS1r
ZXJuZWwnfSwnaXRlbXMnOlt7J2lkJzonZml4dHVyZScsJ25hbWUnOidGaXh0dXJlIGRldmljZScs
J2RldGFpbCc6J0F2YWlsYWJsZScsJ2Nvbm5lY3RlZCc6VHJ1ZX1dLCdzdGF0dXMnOidSZWFkeScs
J2RvbmUnOlRydWV9KSxmbHVzaD1UcnVlKQorKVBZIik7IGhlbHBlci5jbG9zZSgpOworICAgICAg
ICBxcHV0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIsaGVscGVyLmZpbGVOYW1lKCku
dG9VdGY4KCkpOworICAgICAgICBxbWxSZWdpc3RlclR5cGU8VWlDb21wdXRlck1vZGVsPigiQ29t
cHV0ZXJNb2RlbCIsMSwwLCJDb21wdXRlck1vZGVsIik7CisgICAgICAgIHFtbFJlZ2lzdGVyVHlw
ZTxVaUFwcE1vZGVsPigiQXBwTW9kZWwiLDEsMCwiQXBwTW9kZWwiKTsKKyAgICAgICAgcW1sUmVn
aXN0ZXJTaW5nbGV0b25UeXBlKFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNlKyIvYXBwL2d1aS9U
aGVtZS5xbWwiKSwiVGhlbWUiLDEsMCwiVGhlbWUiKTsKKyAgICAgICAgZm9yKGNvbnN0IFFTdHJp
bmcmIG1vZHVsZTpRU3RyaW5nTGlzdHsiQ29tcHV0ZXJNYW5hZ2VyIiwiQXBwUHJvZmlsZU1hbmFn
ZXIiLCJTeXN0ZW1Qcm9wZXJ0aWVzIiwiU2RsR2FtZXBhZEtleU5hdmlnYXRpb24iLCJVaVNvdW5k
TWFuYWdlciIsIlNlcnZlckNvbW1hbmRNYW5hZ2VyIn0pCisgICAgICAgICAgICBxbWxSZWdpc3Rl
clNpbmdsZXRvblR5cGUoUVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UrIi9hcHAvbW9vbmxpZ2h0
b3MvdGVzdHMvVWlTZXJ2aWNlcy5xbWwiKSxtb2R1bGUudG9VdGY4KCkuY29uc3REYXRhKCksMSww
LG1vZHVsZS50b1V0ZjgoKS5jb25zdERhdGEoKSk7CisgICAgICAgIFFRbWxFbmdpbmUgZW5naW5l
OworICAgICAgICBRU2lnbmFsU3B5IHFtbFdhcm5pbmdzKCZlbmdpbmUsJlFRbWxFbmdpbmU6Ondh
cm5pbmdzKTsKKyAgICAgICAgUVFtbENvbXBvbmVudCBjb21wb25lbnQoJmVuZ2luZSwgUVVybDo6
ZnJvbUxvY2FsRmlsZShzb3VyY2UgKyAiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFt
bCIpKTsKKyAgICAgICAgUVNjb3BlZFBvaW50ZXI8UU9iamVjdD4gcm9vdChjb21wb25lbnQuY3Jl
YXRlKCkpOyBRVkVSSUZZMihyb290LCBxUHJpbnRhYmxlKGNvbXBvbmVudC5lcnJvclN0cmluZygp
KSk7CisgICAgICAgIGF1dG8gcGFuZWwgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJ0ZXN0
UGFuZWwiKTsgUVZFUklGWShwYW5lbCk7CisgICAgICAgIGF1dG8gc3RhdGUgPSByb290LT5maW5k
Q2hpbGQ8UU9iamVjdCo+KCJ0ZXN0U3RhdGUiKTsgUVZFUklGWShzdGF0ZSk7CisgICAgICAgIGZv
ciAoaW50IGkgPSAwOyBpIDwgMTY7ICsraSkgeworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9i
amVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCAiY2hvb3NlQWNjZW50IiwgUV9BUkcoUVZh
cmlhbnQsIGkpKSk7CisgICAgICAgICAgICBRQ09NUEFSRShzdGF0ZS0+cHJvcGVydHkoImFjY2Vu
dCIpLnZhbHVlPFFDb2xvcj4oKS5yZ2IoKSxFY2xpcHNlT3ZlcmxheVN0eWxlOjphY2NlbnQoaSku
cmdiKCkpOworICAgICAgICAgICAgUVZFUklGWShzdGF0ZS0+cHJvcGVydHkoInByZXNzZWQiKS52
YWx1ZTxRQ29sb3I+KCkuaXNWYWxpZCgpKTsKKyAgICAgICAgfQorICAgICAgICBRVkVSSUZZKFFN
ZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksICJjaG9vc2VBY2NlbnQiLCBRX0FS
RyhRVmFyaWFudCwgNCkpKTsKKyAgICAgICAgZm9yIChRU3RyaW5nIGtpbmQgOiB7Im5ldHdvcmsi
LCAiYmF0dGVyeSIsICJob3N0In0pIHsKKyAgICAgICAgICAgIFFWRVJJRlkocGFuZWwtPnNldFBy
b3BlcnR5KCJraW5kIiwga2luZCkpOworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6
aW52b2tlTWV0aG9kKHBhbmVsLCAib3BlbiIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAg
ICAgICBRVkVSSUZZKHBhbmVsLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsKKyAgICAg
ICAgICAgIFFTdHJpbmcgb3V0ID0gcUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fU0NSRUVO
U0hPVFMiKTsKKyAgICAgICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgeworICAgICAgICAgICAg
ICAgIFFEaXIoKS5ta3BhdGgob3V0KTsKKyAgICAgICAgICAgICAgICBhdXRvIHdpbmRvdyA9IHFv
YmplY3RfY2FzdDxRUXVpY2tXaW5kb3cqPihyb290LmRhdGEoKSk7IFFWRVJJRlkod2luZG93KTsK
KyAgICAgICAgICAgICAgICBRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0ICsg
Ii8iICsga2luZCArICIucG5nIikpOworICAgICAgICAgICAgfQorICAgICAgICAgICAgUVZFUklG
WShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHBhbmVsLCAiY2xvc2UiKSk7IFFUZXN0OjpxV2Fp
dCgzMDApOworICAgICAgICB9CisgICAgICAgIGF1dG8gY29ubmVjdGlvbnMgPSByb290LT5maW5k
Q2hpbGQ8UU9iamVjdCo+KCJjb25uZWN0aW9uc1BhbmVsIik7IFFWRVJJRlkoY29ubmVjdGlvbnMp
OworICAgICAgICBmb3IgKFFTdHJpbmcga2luZCA6IHsid2lmaSIsICJidCJ9KSB7CisgICAgICAg
ICAgICByb290LT5zZXRQcm9wZXJ0eSgid2lkdGgiLCAxMDI0KTsgcm9vdC0+c2V0UHJvcGVydHko
ImhlaWdodCIsIDY0MCk7CisgICAgICAgICAgICBRVkVSSUZZKGNvbm5lY3Rpb25zLT5zZXRQcm9w
ZXJ0eSgia2luZCIsIGtpbmQpKTsKKyAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omlu
dm9rZU1ldGhvZChjb25uZWN0aW9ucywgIm9wZW4iKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAg
ICAgICAgICAgUVZFUklGWShjb25uZWN0aW9ucy0+cHJvcGVydHkoInZpc2libGUiKS50b0Jvb2wo
KSk7CisgICAgICAgICAgICBRVkVSSUZZKGNvbm5lY3Rpb25zLT5wcm9wZXJ0eSgid2lkdGgiKS50
b0ludCgpIDw9IDk5Mik7CisgICAgICAgICAgICBRU3RyaW5nIG91dCA9IHFFbnZpcm9ubWVudFZh
cmlhYmxlKCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgICAgICBpZiAoIW91dC5pc0Vt
cHR5KCkpIHsKKyAgICAgICAgICAgICAgICBhdXRvIHdpbmRvdyA9IHFvYmplY3RfY2FzdDxRUXVp
Y2tXaW5kb3cqPihyb290LmRhdGEoKSk7IFFWRVJJRlkod2luZG93KTsKKyAgICAgICAgICAgICAg
ICBRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0ICsgIi8iICsga2luZCArICIt
c2VsZWN0b3IucG5nIikpOworICAgICAgICAgICAgfQorICAgICAgICAgICAgUVZFUklGWShRTWV0
YU9iamVjdDo6aW52b2tlTWV0aG9kKGNvbm5lY3Rpb25zLCAiY2xvc2UiKSk7IFFUZXN0OjpxV2Fp
dCgzMDApOworICAgICAgICB9CisgICAgICAgIGF1dG8gY2xpY2tEaWFsb2dCdXR0b249W10oUU9i
amVjdCogZGlhbG9nLGNvbnN0IFFTdHJpbmcmIHRleHQpIHsKKyAgICAgICAgICAgIGF1dG8gZm9v
dGVyPWRpYWxvZy0+cHJvcGVydHkoImZvb3RlciIpLnZhbHVlPFFPYmplY3QqPigpOyBpZighZm9v
dGVyKSByZXR1cm4gZmFsc2U7CisgICAgICAgICAgICBmb3IoYXV0byBjaGlsZDpmb290ZXItPmZp
bmRDaGlsZHJlbjxRT2JqZWN0Kj4oKSkgaWYoY2hpbGQtPnByb3BlcnR5KCJ0ZXh0IikudG9TdHJp
bmcoKT09dGV4dCAmJiBjaGlsZC0+bWV0YU9iamVjdCgpLT5pbmRleE9mU2lnbmFsKCJjbGlja2Vk
KCkiKT49MCkgcmV0dXJuIFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY2hpbGQsImNsaWNrZWQi
KTsKKyAgICAgICAgICAgIHJldHVybiBmYWxzZTsKKyAgICAgICAgfTsKKyAgICAgICAgUVZFUklG
WShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNvbm5lY3Rpb25zLCJvcGVuIikpOyBRVGVzdDo6
cVdhaXQoMzAwKTsKKyAgICAgICAgZm9yKGNvbnN0IFFTdHJpbmcmIG5hbWU6eyJjb25uZWN0aW9u
Q3JlZGVudGlhbCIsImNvbm5lY3Rpb25Gb3JnZXQifSkgeworICAgICAgICAgICAgYXV0byBkaWFs
b2c9cm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPihuYW1lKTsgUVZFUklGWShkaWFsb2cpOworICAg
ICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGRpYWxvZywib3BlbiIp
KTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICBRVkVSSUZZKGRpYWxvZy0+cHJvcGVy
dHkoInZpc2libGUiKS50b0Jvb2woKSk7CisgICAgICAgICAgICBRU3RyaW5nIGRlc3RpbmF0aW9u
PXFFbnZpcm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgICAg
ICBpZighZGVzdGluYXRpb24uaXNFbXB0eSgpKSBRVkVSSUZZKHFvYmplY3RfY2FzdDxRUXVpY2tX
aW5kb3cqPihyb290LmRhdGEoKSktPmdyYWJXaW5kb3coKS5zYXZlKGRlc3RpbmF0aW9uKyIvIitu
YW1lKyIucG5nIikpOworICAgICAgICAgICAgUVZFUklGWShjbGlja0RpYWxvZ0J1dHRvbihkaWFs
b2csbmFtZT09ImNvbm5lY3Rpb25DcmVkZW50aWFsIj8iQ2FuY2VsIjoiTm8iKSk7CisgICAgICAg
ICAgICBRVGVzdDo6cVdhaXQoNDAwKTsgUVZFUklGWTIoIWRpYWxvZy0+cHJvcGVydHkoInZpc2li
bGUiKS50b0Jvb2woKSxxUHJpbnRhYmxlKG5hbWUpKTsKKyAgICAgICAgfQorICAgICAgICBRVkVS
SUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY29ubmVjdGlvbnMsImNsb3NlIikpOyBRVGVz
dDo6cVdhaXQoMjAwKTsKKyAgICAgICAgUVFtbENvbXBvbmVudCBhY3Rpb25Db21wb25lbnQoJmVu
Z2luZSxRVXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSsiL2FwcC9ndWkvRWNsaXBzZUFjdGlvbkJ1
dHRvbi5xbWwiKSk7CisgICAgICAgIFFTY29wZWRQb2ludGVyPFFPYmplY3Q+IGFjdGlvbihhY3Rp
b25Db21wb25lbnQuY3JlYXRlKCkpOyBRVkVSSUZZMihhY3Rpb24scVByaW50YWJsZShhY3Rpb25D
b21wb25lbnQuZXJyb3JTdHJpbmcoKSkpOworICAgICAgICBhdXRvIGFjdGlvbkl0ZW0gPSBxb2Jq
ZWN0X2Nhc3Q8UVF1aWNrSXRlbSo+KGFjdGlvbi5kYXRhKCkpOyBRVkVSSUZZKGFjdGlvbkl0ZW0p
OworICAgICAgICBhdXRvIGFjdGlvbldpbmRvdyA9IHFvYmplY3RfY2FzdDxRUXVpY2tXaW5kb3cq
Pihyb290LmRhdGEoKSk7IFFWRVJJRlkoYWN0aW9uV2luZG93KTsKKyAgICAgICAgYWN0aW9uSXRl
bS0+c2V0UGFyZW50SXRlbShhY3Rpb25XaW5kb3ctPmNvbnRlbnRJdGVtKCkpOyBhY3Rpb25JdGVt
LT5mb3JjZUFjdGl2ZUZvY3VzKCk7CisgICAgICAgIFFTaWduYWxTcHkgYWN0aXZhdGVkKGFjdGlv
bi5kYXRhKCksU0lHTkFMKGNsaWNrZWQoKSkpOworICAgICAgICBRVGVzdDo6a2V5Q2xpY2soYWN0
aW9uV2luZG93LFF0OjpLZXlfUmV0dXJuKTsgUUNPTVBBUkUoYWN0aXZhdGVkLmNvdW50KCksMSk7
CisgICAgICAgIGFjdGlvbkl0ZW0tPnNldFZpc2libGUoZmFsc2UpOworICAgICAgICBhdXRvIGNl
bnRlciA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oImNvbnRyb2xDZW50ZXIiKTsgUVZFUklG
WShjZW50ZXIpOworICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY2Vu
dGVyLCJvcGVuIikpOyBRVGVzdDo6cVdhaXQoNTAwKTsKKyAgICAgICAgUVZFUklGWShjZW50ZXIt
PnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAgICBRU3RyaW5nIG91dCA9IHFF
bnZpcm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgIGF1dG8g
d2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgpKTsgUVZFUklG
WSh3aW5kb3cpOworICAgICAgICBpZiAoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlkod2luZG93LT5n
cmFiV2luZG93KCkuc2F2ZShvdXQrIi9lY2xpcHNlLWNvbnRyb2wtY2VudGVyLnBuZyIpKTsKKyAg
ICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNlbnRlciwiY2xvc2UiKSk7
IFFUZXN0OjpxV2FpdCgzMDApOworICAgICAgICBmb3IoY29uc3QgUVN0cmluZyYgdmlldzpRU3Ry
aW5nTGlzdHsiUGNWaWV3IiwiQXBwVmlldyJ9KSB7CisgICAgICAgICAgICBmb3IoaW50IHNjYWxl
OnsxMDAsMTEwLDEyNX0pIHsKKyAgICAgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0Ojpp
bnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29zZVNjYWxlIixRX0FSRyhRVmFyaWFudCxzY2Fs
ZSkpKTsKKyAgICAgICAgICAgICAgICBmb3IoUVNpemUgc2l6ZTp7UVNpemUoMTkyMCwxMDgwKSxR
U2l6ZSgxMjgwLDcyMCksUVNpemUoOTAwLDY0MCl9KSB7CisgICAgICAgICAgICAgICAgICAgIHJv
b3QtPnNldFByb3BlcnR5KCJ3aWR0aCIsc2l6ZS53aWR0aCgpKTtyb290LT5zZXRQcm9wZXJ0eSgi
aGVpZ2h0IixzaXplLmhlaWdodCgpKTsKKyAgICAgICAgICAgICAgICAgICAgUVZFUklGWShRTWV0
YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJzaG93UHJvZHVjdGlvblZpZXciLFFf
QVJHKFFWYXJpYW50LHZpZXcpKSk7UVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICAgICAg
ICAgIGF1dG8gc3RhY2s9cm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigicHJvZHVjdGlvblN0YWNr
Iik7UVZFUklGWShzdGFjayk7YXV0byBpdGVtPXN0YWNrLT5wcm9wZXJ0eSgiY3VycmVudEl0ZW0i
KS52YWx1ZTxRT2JqZWN0Kj4oKTtRVkVSSUZZKGl0ZW0pOworICAgICAgICAgICAgICAgICAgICBR
VkVSSUZZKGl0ZW0tPnByb3BlcnR5KCJhdmFpbGFibGVXaWR0aCIpLnRvRG91YmxlKCk+MzAwKTsK
KyAgICAgICAgICAgICAgICAgICAgUUNPTVBBUkUoaXRlbS0+cHJvcGVydHkoImNvdW50IikudG9J
bnQoKSx2aWV3PT0iUGNWaWV3Ij8yOjYpOworICAgICAgICAgICAgICAgICAgICBhdXRvIGdyaWQ9
cW9iamVjdF9jYXN0PFFRdWlja0l0ZW0qPihpdGVtKTtRVkVSSUZZKGdyaWQpOworICAgICAgICAg
ICAgICAgICAgICBncmlkLT5mb3JjZUFjdGl2ZUZvY3VzKCk7aXRlbS0+c2V0UHJvcGVydHkoImN1
cnJlbnRJbmRleCIsMCk7CisgICAgICAgICAgICAgICAgICAgIFFUZXN0OjprZXlDbGljayh3aW5k
b3csUXQ6OktleV9SaWdodCk7CisgICAgICAgICAgICAgICAgICAgIFFWRVJJRlkoaXRlbS0+cHJv
cGVydHkoImN1cnJlbnRJbmRleCIpLnRvSW50KCk+MCk7CisgICAgICAgICAgICAgICAgICAgIGZv
cihhdXRvIGJ1dHRvbjppdGVtLT5maW5kQ2hpbGRyZW48UVF1aWNrSXRlbSo+KCJjcmltc29uUmFp
bEJ1dHRvbiIpKSB7CisgICAgICAgICAgICAgICAgICAgICAgICBRVkVSSUZZKGJ1dHRvbi0+d2lk
dGgoKT49NTYpO2J1dHRvbi0+Zm9yY2VBY3RpdmVGb2N1cygpO1FWRVJJRlkoYnV0dG9uLT5oYXNB
Y3RpdmVGb2N1cygpKTsKKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgICAg
ICBncmlkLT5mb3JjZUFjdGl2ZUZvY3VzKCk7aXRlbS0+c2V0UHJvcGVydHkoImN1cnJlbnRJbmRl
eCIsLTEpOworICAgICAgICAgICAgICAgICAgICBpZighb3V0LmlzRW1wdHkoKSlRVkVSSUZZKHdp
bmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0KyIvY3JpbXNvbi1nbGFzcy0iK3ZpZXcrIi0iK1FT
dHJpbmc6Om51bWJlcihzaXplLndpZHRoKCkpKyItIitRU3RyaW5nOjpudW1iZXIoc2NhbGUpKyIu
cG5nIikpOworICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAg
ICAgICByb290LT5zZXRQcm9wZXJ0eSgid2lkdGgiLDE5MjApO3Jvb3QtPnNldFByb3BlcnR5KCJo
ZWlnaHQiLDEwODApOworICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qo
cm9vdC5kYXRhKCksInNob3dQcm9kdWN0aW9uVmlldyIsUV9BUkcoUVZhcmlhbnQsUVN0cmluZygi
QXBwVmlldyIpKSkpOworICAgICAgICBmb3IoaW50IGFjY2VudD0wO2FjY2VudDwxNjthY2NlbnQr
KykgeworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3Qu
ZGF0YSgpLCJjaG9vc2VBY2NlbnQiLFFfQVJHKFFWYXJpYW50LGFjY2VudCkpKTtRVGVzdDo6cVdh
aXQoMzApOworICAgICAgICAgICAgaWYoIW91dC5pc0VtcHR5KCkpUVZFUklGWSh3aW5kb3ctPmdy
YWJXaW5kb3coKS5zYXZlKG91dCsiL2NyaW1zb24tZ2xhc3MtYWNjZW50LSIrUVN0cmluZzo6bnVt
YmVyKGFjY2VudCkrIi5wbmciKSk7CisgICAgICAgIH0KKyAgICAgICAgUVZFUklGWShRTWV0YU9i
amVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VBY2Nlc3NpYmlsaXR5IixRX0FS
RyhRVmFyaWFudCx0cnVlKSxRX0FSRyhRVmFyaWFudCx0cnVlKSkpO1FUZXN0OjpxV2FpdCgxMDAp
OworICAgICAgICBpZighb3V0LmlzRW1wdHkoKSlRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygp
LnNhdmUob3V0KyIvY3JpbXNvbi1nbGFzcy1oaWdoLWNvbnRyYXN0LnBuZyIpKTsKKyAgICAgICAg
UVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VBY2Nl
c3NpYmlsaXR5IixRX0FSRyhRVmFyaWFudCxmYWxzZSksUV9BUkcoUVZhcmlhbnQsZmFsc2UpKSk7
CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwi
Y2hvb3NlQWNjZW50IixRX0FSRyhRVmFyaWFudCw0KSkpOworICAgICAgICBRVGVtcG9yYXJ5RGly
IHdhbGxwYXBlckZvbGRlcjtRVkVSSUZZKHdhbGxwYXBlckZvbGRlci5pc1ZhbGlkKCkpOworICAg
ICAgICBRSW1hZ2Ugd2FsbHBhcGVyKDE5MjAsMTA4MCxRSW1hZ2U6OkZvcm1hdF9SR0IzMik7Cisg
ICAgICAgIHtRUGFpbnRlciBwYWludGVyKCZ3YWxscGFwZXIpO1FMaW5lYXJHcmFkaWVudCBncmFk
aWVudCgwLDAsMTkyMCwxMDgwKTtncmFkaWVudC5zZXRDb2xvckF0KDAsUUNvbG9yKCIjMzIxMTIy
IikpO2dyYWRpZW50LnNldENvbG9yQXQoMSxRQ29sb3IoIiMxNTFENDIiKSk7cGFpbnRlci5maWxs
UmVjdCh3YWxscGFwZXIucmVjdCgpLGdyYWRpZW50KTtwYWludGVyLnNldFBlbihRUGVuKFFDb2xv
cigiIzlEMzU1NSIpLDgpKTtwYWludGVyLmRyYXdFbGxpcHNlKFFQb2ludEYoMTE1MCw1NTApLDU1
MCw1NTApO30KKyAgICAgICAgUVN0cmluZyB3YWxscGFwZXJQYXRoPXdhbGxwYXBlckZvbGRlci5m
aWxlUGF0aCgiZml4dHVyZS1iYWNrZ3JvdW5kLnBuZyIpO1FWRVJJRlkod2FsbHBhcGVyLnNhdmUo
d2FsbHBhcGVyUGF0aCkpOworICAgICAgICBRVmFyaWFudCBzZWxlY3RlZDtRVkVSSUZZKFFNZXRh
T2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksImNob29zZVdhbGxwYXBlciIsUV9SRVRV
Uk5fQVJHKFFWYXJpYW50LHNlbGVjdGVkKSxRX0FSRyhRVmFyaWFudCxRVXJsOjpmcm9tTG9jYWxG
aWxlKHdhbGxwYXBlclBhdGgpKSkpO1FWRVJJRlkoc2VsZWN0ZWQudG9Cb29sKCkpOworICAgICAg
ICBRVGVzdDo6cVdhaXQoMjUwKTsKKyAgICAgICAgaWYoIW91dC5pc0VtcHR5KCkpUVZFUklGWSh3
aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZlKG91dCsiL2NyaW1zb24tZ2xhc3Mtc2VsZWN0ZWQtYmFj
a2dyb3VuZC5wbmciKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhv
ZChyb290LmRhdGEoKSwicmVzZXRXYWxscGFwZXIiKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFP
YmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiaGlkZVByb2R1Y3Rpb25WaWV3IikpOwor
ICAgICAgICBhdXRvIHF1aWNrTWVudT1yb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJxdWlja01l
bnVMb2FkZXIiKTtRVkVSSUZZKHF1aWNrTWVudSk7cXVpY2tNZW51LT5zZXRQcm9wZXJ0eSgiYWN0
aXZlIix0cnVlKTtRVGVzdDo6cVdhaXQoMTUwKTsKKyAgICAgICAgUVZFUklGWShxdWlja01lbnUt
PnByb3BlcnR5KCJpdGVtIikudmFsdWU8UU9iamVjdCo+KCkpOworICAgICAgICBRVGVzdDo6a2V5
Q2xpY2sod2luZG93LFF0OjpLZXlfRG93bik7CisgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKVFW
RVJJRlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQrIi9jcmltc29uLWdsYXNzLXF1aWNr
LW1lbnUucG5nIikpOworICAgICAgICBxdWlja01lbnUtPnNldFByb3BlcnR5KCJhY3RpdmUiLGZh
bHNlKTsKKyAgICAgICAgUUNPTVBBUkUocW1sV2FybmluZ3MuY291bnQoKSwwKTsKKyAgICAgICAg
YXV0byBkYXNoYm9hcmQ9cm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigiZ2xhc3NEYXNoYm9hcmQi
KTtRVkVSSUZZKGRhc2hib2FyZCk7CisgICAgICAgIGZvcihpbnQgc2NhbGU6ezEwMCwxMTAsMTI1
fSkgeworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3Qu
ZGF0YSgpLCJjaG9vc2VTY2FsZSIsUV9BUkcoUVZhcmlhbnQsc2NhbGUpKSk7CisgICAgICAgICAg
ICBmb3IoUVNpemUgc2l6ZTp7UVNpemUoMTkyMCwxMDgwKSxRU2l6ZSgxMjgwLDcyMCksUVNpemUo
OTAwLDY0MCl9KSB7CisgICAgICAgICAgICAgICAgcm9vdC0+c2V0UHJvcGVydHkoIndpZHRoIixz
aXplLndpZHRoKCkpO3Jvb3QtPnNldFByb3BlcnR5KCJoZWlnaHQiLHNpemUuaGVpZ2h0KCkpO2Rh
c2hib2FyZC0+c2V0UHJvcGVydHkoInZpc2libGUiLHRydWUpO1FUZXN0OjpxV2FpdCgyNTApOwor
ICAgICAgICAgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKVFWRVJJRlkod2luZG93LT5ncmFiV2lu
ZG93KCkuc2F2ZShvdXQrIi9jcmltc29uLWdsYXNzLWRhc2hib2FyZC0iK1FTdHJpbmc6Om51bWJl
cihzaXplLndpZHRoKCkpKyItIitRU3RyaW5nOjpudW1iZXIoc2NhbGUpKyIucG5nIikpOworICAg
ICAgICAgICAgICAgIGF1dG8gY2FyZHM9ZGFzaGJvYXJkLT5maW5kQ2hpbGRyZW48UVF1aWNrSXRl
bSo+KCJjcmltc29uTWV0cmljIik7Zm9yKGF1dG8gY2FyZDpjYXJkcylRVkVSSUZZKGNhcmQtPndp
ZHRoKCk+MTAwKTsKKyAgICAgICAgICAgICAgICBhdXRvIGhvc3Q9ZGFzaGJvYXJkLT5maW5kQ2hp
bGQ8UVF1aWNrSXRlbSo+KCJnbGFzc0hvc3QiKTtRVkVSSUZZKGhvc3QpO1FWRVJJRlkoaG9zdC0+
d2lkdGgoKT49MCk7CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICAgICAgZGFzaGJvYXJk
LT5zZXRQcm9wZXJ0eSgidmlzaWJsZSIsZmFsc2UpOworICAgICAgICBhdXRvIHBpY2tlcj1yb290
LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJnbGFzc0JhY2tncm91bmRQaWNrZXIiKTtRVkVSSUZZKHBp
Y2tlcik7UVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHBpY2tlciwib3BlbiIpKTtR
VGVzdDo6cVdhaXQoMTUwKTtRVkVSSUZZKHBpY2tlci0+cHJvcGVydHkoInZpc2libGUiKS50b0Jv
b2woKSk7CisgICAgICAgIGlmKCFvdXQuaXNFbXB0eSgpKVFWRVJJRlkod2luZG93LT5ncmFiV2lu
ZG93KCkuc2F2ZShvdXQrIi9jcmltc29uLWdsYXNzLWJhY2tncm91bmQtcGlja2VyLnBuZyIpKTsK
KyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHBpY2tlciwiY2xvc2Ui
KSk7CisgICAgICAgIGF1dG8gYWJvdXQgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJhYm91
dEVjbGlwc2UiKTsgUVZFUklGWShhYm91dCk7CisgICAgICAgIGFib3V0LT5zZXRQcm9wZXJ0eSgi
aW5mbyIsIFFWYXJpYW50TWFwe3sib3MiLFFWYXJpYW50TWFwe3siTkFNRSIsIkVjbGlwc2VPUyJ9
LHsiVkVSU0lPTiIsIjAuMy1kZXYifSx7IlRBUkdFVCIsIkZpeHR1cmUgaGFyZHdhcmUifSx7IkZF
RE9SQSIsIjQ0In19fSx7Imtlcm5lbCIsImZpeHR1cmUta2VybmVsIn19KTsKKyAgICAgICAgUVZF
UklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGFib3V0LCJvcGVuIikpOyBRVGVzdDo6cVdh
aXQoMzAwKTsKKyAgICAgICAgUVZFUklGWShhYm91dC0+cHJvcGVydHkoInZpc2libGUiKS50b0Jv
b2woKSk7CisgICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgUVZFUklGWSh3aW5kb3ctPmdyYWJX
aW5kb3coKS5zYXZlKG91dCsiL2VjbGlwc2UtYWJvdXQucG5nIikpOworICAgICAgICBRVkVSSUZZ
KFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoYWJvdXQsImNsb3NlIikpOworICAgICAgICBhdXRv
IHN5c3RlbT1yb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJzeXN0ZW1TZXR0aW5ncyIpOyBRVkVS
SUZZKHN5c3RlbSk7CisgICAgICAgIGZvcihpbnQgc2NhbGU6ezEwMCwxMTAsMTI1fSkgeworICAg
ICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJj
aG9vc2VTY2FsZSIsUV9BUkcoUVZhcmlhbnQsc2NhbGUpKSk7CisgICAgICAgICAgICByb290LT5z
ZXRQcm9wZXJ0eSgid2lkdGgiLDEwMjQpOyByb290LT5zZXRQcm9wZXJ0eSgiaGVpZ2h0Iiw2NDAp
OworICAgICAgICAgICAgc3lzdGVtLT5zZXRQcm9wZXJ0eSgiYWN0aXZlIix0cnVlKTsgUVRlc3Q6
OnFXYWl0KDQwMCk7CisgICAgICAgICAgICBRVkVSSUZZKHN5c3RlbS0+cHJvcGVydHkoIndpZHRo
IikudG9JbnQoKTw9MTAyNCk7CisgICAgICAgICAgICBpZighb3V0LmlzRW1wdHkoKSkgUVZFUklG
WSh3aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZlKG91dCsiL3N5c3RlbS1jb250cm9scy0iK1FTdHJp
bmc6Om51bWJlcihzY2FsZSkrIi5wbmciKSk7CisgICAgICAgICAgICBmb3IoaW50IGFjY2VudD0w
O2FjY2VudDwxNjthY2NlbnQrKykgeworICAgICAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmpl
Y3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiY2hvb3NlQWNjZW50IixRX0FSRyhRVmFyaWFu
dCxhY2NlbnQpKSk7IFFUZXN0OjpxV2FpdCgxMCk7CisgICAgICAgICAgICAgICAgUVZFUklGWShz
dGF0ZS0+cHJvcGVydHkoImFjY2VudCIpLnZhbHVlPFFDb2xvcj4oKS5pc1ZhbGlkKCkpOworICAg
ICAgICAgICAgfQorICAgICAgICAgICAgYXV0byBzY3JvbGw9cm9vdC0+ZmluZENoaWxkPFFPYmpl
Y3QqPigic3lzdGVtU2Nyb2xsIik7IFFWRVJJRlkoc2Nyb2xsKTsKKyAgICAgICAgICAgIGF1dG8g
ZmxpY2s9c2Nyb2xsLT5wcm9wZXJ0eSgiY29udGVudEl0ZW0iKS52YWx1ZTxRUXVpY2tJdGVtKj4o
KTsgUVZFUklGWShmbGljayk7CisgICAgICAgICAgICBhdXRvIG1vbml0b3I9cm9vdC0+ZmluZENo
aWxkPFFPYmplY3QqPigiaGFyZHdhcmVNb25pdG9yIik7IFFWRVJJRlkobW9uaXRvcik7CisgICAg
ICAgICAgICBmbGljay0+c2V0UHJvcGVydHkoImNvbnRlbnRZIixtb25pdG9yLT5wcm9wZXJ0eSgi
eSIpKTsgUVRlc3Q6OnFXYWl0KDIwMCk7CisgICAgICAgICAgICBpZighb3V0LmlzRW1wdHkoKSkg
UVZFUklGWSh3aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZlKG91dCsiL2hhcmR3YXJlLW1vbml0b3It
IitRU3RyaW5nOjpudW1iZXIoc2NhbGUpKyIucG5nIikpOworICAgICAgICAgICAgZmxpY2stPnNl
dFByb3BlcnR5KCJjb250ZW50WSIsMCk7CisgICAgICAgICAgICBzeXN0ZW0tPnNldFByb3BlcnR5
KCJhY3RpdmUiLGZhbHNlKTsgUVRlc3Q6OnFXYWl0KDEwMCk7CisgICAgICAgIH0KKyAgICAgICAg
UVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VTY2Fs
ZSIsUV9BUkcoUVZhcmlhbnQsMTAwKSkpOworICAgICAgICBRQ09NUEFSRShxbWxXYXJuaW5ncy5j
b3VudCgpLDApOworICAgICAgICBxdW5zZXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJF
Iik7CisgICAgfQorfTsKK1FURVNUX01BSU4oQ3JpbXNvblRlc3QpCisjaW5jbHVkZSAidGVzdC1j
cmltc29uLm1vYyIKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1z
b24ucHJvIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5wcm8KbmV3IGZpbGUg
bW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uOTI1N2MzNgotLS0gL2Rldi9udWxsCisrKyBiL2Fw
cC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24ucHJvCkBAIC0wLDAgKzEsMjMgQEAKK1FU
ICs9IGNvcmUgZ3VpIHF1aWNrIG5ldHdvcmsgcXVpY2tjb250cm9sczIgdGVzdGxpYiBzdmcKK0NP
TkZJRyArPSBjKysxNyB0ZXN0Y2FzZQorVEFSR0VUID0gdGVzdC1jcmltc29uCitTT1VSQ0VTICs9
IHRlc3QtY3JpbXNvbi5jcHAgLi4vY3JpbXNvbnN0YXR1cy5jcHAKK0hFQURFUlMgKz0gLi4vY3Jp
bXNvbnN0YXR1cy5oCisKK1NPVVJDRVMgKz0gLi4vbWFuYWdlZHVwZGF0ZXMuY3BwCitIRUFERVJT
ICs9IC4uLy4uL2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaAorCitERUZJTkVTICs9IE1PT05M
SUdIVF9DT05UUk9MU19URVNUCitTT1VSQ0VTICs9IC4uL3N5c3RlbWNvbnRyb2xzLmNwcAorSEVB
REVSUyArPSAuLi9zeXN0ZW1jb250cm9scy5oCisKK1NPVVJDRVMgKz0gLi4vZWNsaXBzZXByb2Zp
bGVzLmNwcAorSEVBREVSUyArPSAuLi9lY2xpcHNlcHJvZmlsZXMuaAorCisjIE1hdGNoIHRoZSBw
cm9kdWN0aW9uIHJlc291cmNlIGJ1bmRsZSBzbyByZW5kZXJlZCBpY29ucyBhcmUgYWN0dWFsbHkg
dGVzdGVkLgorUkVTT1VSQ0VTICs9IC4uLy4uL3Jlc291cmNlcy5xcmMKKworU09VUkNFUyArPSAu
Li9sb2NhbGhhcmR3YXJlLmNwcAorSEVBREVSUyArPSAuLi9sb2NhbGhhcmR3YXJlLmgKKworSEVB
REVSUyArPSB1aW1vZGVscy5oCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvdWlt
b2RlbHMuaCBiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy91aW1vZGVscy5oCm5ldyBmaWxlIG1vZGUg
MTAwNjQ0CmluZGV4IDAwMDAwMDAuLmEwMDFlYjgKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9v
bmxpZ2h0b3MvdGVzdHMvdWltb2RlbHMuaApAQCAtMCwwICsxLDQwIEBACisjcHJhZ21hIG9uY2UK
KyNpbmNsdWRlIDxRQWJzdHJhY3RMaXN0TW9kZWw+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+Citj
bGFzcyBVaUNvbXB1dGVyTW9kZWwgOiBwdWJsaWMgUUFic3RyYWN0TGlzdE1vZGVsIHsKKyAgICBR
X09CSkVDVAorcHVibGljOgorICAgIGVudW0gUm9sZXMge05hbWVSb2xlPVF0OjpVc2VyUm9sZSxP
bmxpbmVSb2xlLFBhaXJlZFJvbGUsQnVzeVJvbGUsV2FrZWFibGVSb2xlLFN0YXR1c1Vua25vd25S
b2xlLFNlcnZlclN1cHBvcnRlZFJvbGUsRGV0YWlsc1JvbGUsQXBvbGxvVmVyc2lvblJvbGUsSXNB
cG9sbG9TZXJ2ZXJSb2xlLFBlcm1pc3Npb25TdW1tYXJ5Um9sZSxIb3N0VHlwZVJvbGUsVHJhbnNw
b3J0Um9sZSxMYXRlbmN5VGV4dFJvbGUsTGFzdFNlZW5UZXh0Um9sZX07UV9FTlVNKFJvbGVzKQor
ICAgIGV4cGxpY2l0IFVpQ29tcHV0ZXJNb2RlbChRT2JqZWN0KiBwYXJlbnQ9bnVsbHB0cik6UUFi
c3RyYWN0TGlzdE1vZGVsKHBhcmVudCl7fQorICAgIFFfSU5WT0tBQkxFIHZvaWQgaW5pdGlhbGl6
ZShRT2JqZWN0Kil7fQorICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50TWFwIGNyaW1zb25Ib3N0KGlu
dCkgY29uc3Qge3JldHVybiB7eyJpZCIsInVpLWZpeHR1cmUifSx7InVybCIsImh0dHBzOi8vMTI3
LjAuMC4xOjQ3OTkwIn19O30KKyAgICBpbnQgcm93Q291bnQoY29uc3QgUU1vZGVsSW5kZXgmID0g
UU1vZGVsSW5kZXgoKSkgY29uc3Qgb3ZlcnJpZGV7cmV0dXJuIDI7fQorICAgIFFIYXNoPGludCxR
Qnl0ZUFycmF5PiByb2xlTmFtZXMoKWNvbnN0IG92ZXJyaWRlIHtyZXR1cm4ge3tOYW1lUm9sZSwi
bmFtZSJ9LHtPbmxpbmVSb2xlLCJvbmxpbmUifSx7UGFpcmVkUm9sZSwicGFpcmVkIn0se0J1c3lS
b2xlLCJidXN5In0se1dha2VhYmxlUm9sZSwid2FrZWFibGUifSx7U3RhdHVzVW5rbm93blJvbGUs
InN0YXR1c1Vua25vd24ifSx7U2VydmVyU3VwcG9ydGVkUm9sZSwic2VydmVyU3VwcG9ydGVkIn0s
e0RldGFpbHNSb2xlLCJkZXRhaWxzIn0se0Fwb2xsb1ZlcnNpb25Sb2xlLCJhcG9sbG9WZXJzaW9u
In0se0lzQXBvbGxvU2VydmVyUm9sZSwiaXNBcG9sbG9TZXJ2ZXIifSx7UGVybWlzc2lvblN1bW1h
cnlSb2xlLCJwZXJtaXNzaW9uU3VtbWFyeSJ9LHtIb3N0VHlwZVJvbGUsImhvc3RUeXBlIn0se1Ry
YW5zcG9ydFJvbGUsInRyYW5zcG9ydCJ9LHtMYXRlbmN5VGV4dFJvbGUsImxhdGVuY3lUZXh0In0s
e0xhc3RTZWVuVGV4dFJvbGUsImxhc3RTZWVuVGV4dCJ9fTt9CisgICAgUV9JTlZPS0FCTEUgUVZh
cmlhbnQgZGF0YShjb25zdCBRTW9kZWxJbmRleCYgaW5kZXgsaW50IHJvbGUpIGNvbnN0IG92ZXJy
aWRlIHsKKyAgICAgICAgaWYocm9sZT09TmFtZVJvbGUpcmV0dXJuIGluZGV4LnJvdygpPyJCYWNr
dXAgUEMiOiJHYW1pbmcgUEMiOworICAgICAgICBpZihyb2xlPT1PbmxpbmVSb2xlfHxyb2xlPT1Q
YWlyZWRSb2xlfHxyb2xlPT1TZXJ2ZXJTdXBwb3J0ZWRSb2xlfHxyb2xlPT1Jc0Fwb2xsb1NlcnZl
clJvbGUpcmV0dXJuIHRydWU7CisgICAgICAgIGlmKHJvbGU9PUhvc3RUeXBlUm9sZSlyZXR1cm4g
IlZJQkVQT0xMTyI7aWYocm9sZT09VHJhbnNwb3J0Um9sZSlyZXR1cm4gIkxBTiI7CisgICAgICAg
IGlmKHJvbGU9PUxhdGVuY3lUZXh0Um9sZSlyZXR1cm4gIjQgbXMiO2lmKHJvbGU9PVBlcm1pc3Np
b25TdW1tYXJ5Um9sZSlyZXR1cm4gIkZ1bGwgYWNjZXNzIjsKKyAgICAgICAgaWYocm9sZT09RGV0
YWlsc1JvbGUpcmV0dXJuIFFWYXJpYW50TGlzdCgpO2lmKHJvbGU9PUxhc3RTZWVuVGV4dFJvbGV8
fHJvbGU9PUFwb2xsb1ZlcnNpb25Sb2xlKXJldHVybiBRU3RyaW5nKCk7cmV0dXJuIGZhbHNlOwor
ICAgIH0KK3NpZ25hbHM6CisgICAgdm9pZCBvdHBTdGFnZTFDb21wbGV0ZWQoKTsKKyAgICB2b2lk
IHBhaXJpbmdDb21wbGV0ZWQoUVZhcmlhbnQgZXJyb3IpOworICAgIHZvaWQgY29ubmVjdGlvblRl
c3RDb21wbGV0ZWQoaW50IHJlc3VsdCk7Cit9OworY2xhc3MgVWlBcHBNb2RlbCA6IHB1YmxpYyBR
QWJzdHJhY3RMaXN0TW9kZWwgeworICAgIFFfT0JKRUNUCitwdWJsaWM6CisgICAgZXhwbGljaXQg
VWlBcHBNb2RlbChRT2JqZWN0KiBwYXJlbnQ9bnVsbHB0cik6UUFic3RyYWN0TGlzdE1vZGVsKHBh
cmVudCl7fQorICAgIFFfSU5WT0tBQkxFIHZvaWQgaW5pdGlhbGl6ZShRT2JqZWN0KixpbnQsYm9v
bCl7fQorICAgIFFfSU5WT0tBQkxFIGludCBnZXRSdW5uaW5nQXBwSWQoKXtyZXR1cm4gMDt9Cisg
ICAgUV9JTlZPS0FCTEUgUVN0cmluZyBnZXRSdW5uaW5nQXBwTmFtZSgpe3JldHVybiB7fTt9Cisg
ICAgUV9JTlZPS0FCTEUgaW50IGdldERpcmVjdExhdW5jaEFwcEluZGV4KCl7cmV0dXJuIC0xO30K
KyAgICBRX0lOVk9LQUJMRSBRU3RyaW5nIGdldENvbXB1dGVyVXVpZCgpe3JldHVybiAidWktZml4
dHVyZSI7fQorICAgIFFfSU5WT0tBQkxFIHZvaWQgcmVzeW5jUnVubmluZ1N0YXRlKCl7fQorICAg
IGludCByb3dDb3VudChjb25zdCBRTW9kZWxJbmRleCYgPSBRTW9kZWxJbmRleCgpKWNvbnN0IG92
ZXJyaWRle3JldHVybiA2O30KKyAgICBRSGFzaDxpbnQsUUJ5dGVBcnJheT4gcm9sZU5hbWVzKClj
b25zdCBvdmVycmlkZXtyZXR1cm4ge3syNTYsIm5hbWUifSx7MjU3LCJydW5uaW5nIn0sezI1OCwi
Ym94YXJ0In0sezI1OSwiaGlkZGVuIn0sezI2MCwiYXBwaWQifSx7MjYxLCJkaXJlY3RMYXVuY2gi
fSx7MjYyLCJpc0FwcENvbGxlY3RvckdhbWUifX07fQorICAgIFFWYXJpYW50IGRhdGEoY29uc3Qg
UU1vZGVsSW5kZXgmIGluZGV4LGludCByb2xlKWNvbnN0IG92ZXJyaWRlIHtpZihyb2xlPT0yNTYp
cmV0dXJuIFFTdHJpbmdMaXN0eyJEZXNrdG9wIiwiU3RlYW0gQmlnIFBpY3R1cmUiLCJHYW1lIGxp
YnJhcnkiLCJNZWRpYSIsIkJyb3dzZXIiLCJUb29scyJ9LnZhbHVlKGluZGV4LnJvdygpKTtpZihy
b2xlPT0yNTgpcmV0dXJuICJxcmM6L3Jlcy9ub19hcHBfaW1hZ2UucG5nIjtpZihyb2xlPT0yNjAp
cmV0dXJuIGluZGV4LnJvdygpKzE7cmV0dXJuIGZhbHNlO30KK3NpZ25hbHM6CisgICAgdm9pZCBj
b21wdXRlckxvc3QoKTsKK307CmRpZmYgLS1naXQgYS9hcHAvcW1sLnFyYyBiL2FwcC9xbWwucXJj
CmluZGV4IGEzYzExZGQuLjQ4ZTlkNTcgMTAwNjQ0Ci0tLSBhL2FwcC9xbWwucXJjCisrKyBiL2Fw
cC9xbWwucXJjCkBAIC0yLDYgKzIsMTQgQEAKICAgICA8cXJlc291cmNlIHByZWZpeD0iLyI+CiAg
ICAgICAgIDxmaWxlPmd1aS9UaGVtZS5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9WYlRv
a2Vucy5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uR2xhc3NQYW5lbC5xbWw8
L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uQmFja2dyb3VuZFBpY2tlci5xbWw8L2Zp
bGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uR2xhc3NCYWNrZHJvcC5xbWw8L2ZpbGU+Cisg
ICAgICAgIDxmaWxlPmd1aS9Dcmltc29uU3BhcmtsaW5lLnFtbDwvZmlsZT4KKyAgICAgICAgPGZp
bGU+Z3VpL0NyaW1zb25Mb2NhbFBhbmVsLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0Ny
aW1zb25HbGFzc1JhaWwucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvQ3JpbXNvbkhvc3RQ
YW5lbC5xbWw8L2ZpbGU+CisKICAgICAgICAgPGZpbGU+Z3VpL1ZiRm9jdXNSaW5nLnFtbDwvZmls
ZT4KICAgICAgICAgPGZpbGU+Z3VpL1ZiRHJvcFNoYWRvdy5xbWw8L2ZpbGU+CiAgICAgICAgIDxm
aWxlPmd1aS9WYkhpbnRCYXIucW1sPC9maWxlPgpAQCAtMTQsNiArMjIsMTEgQEAKICAgICAgICAg
PGZpbGU+Z3VpL1ZiSG9zdENhcmQucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvVmJXZWxj
b21lU2hlZXQucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvbWFpbi5xbWw8L2ZpbGU+Cisg
ICAgICAgIDxmaWxlPmd1aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbDwvZmlsZT4KKyAgICAgICAg
PGZpbGU+Z3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9nLnFtbDwvZmlsZT4KKyAgICAgICAgPGZp
bGU+Z3VpL0VjbGlwc2VDb250cm9sQ2VudGVyLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3Vp
L0VjbGlwc2VBY3Rpb25CdXR0b24ucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBz
ZUFib3V0RGlhbG9nLnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL1BjVmlldy5xbWw8L2Zp
bGU+CiAgICAgICAgIDxmaWxlPmd1aS9BcHBWaWV3LnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+
Z3VpL1NldHRpbmdzVmlldy5xbWw8L2ZpbGU+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1zb24t
YmF0dGVyeS5zdmcgYi9hcHAvcmVzL2NyaW1zb24tYmF0dGVyeS5zdmcKbmV3IGZpbGUgbW9kZSAx
MDA2NDQKaW5kZXggMDAwMDAwMC4uMzc1MzU2NgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMv
Y3JpbXNvbi1iYXR0ZXJ5LnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3
LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQg
MjQiPjxnIGZpbGw9Im5vbmUiIHN0cm9rZT0iI0VDRUVGMSIgc3Ryb2tlLXdpZHRoPSIxLjgiIHN0
cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHJlY3QgeD0iMiIg
eT0iNiIgd2lkdGg9IjE4IiBoZWlnaHQ9IjEyIiByeD0iMiIvPjxwYXRoIGQ9Ik0yMiAxMHY0TTYg
MTB2NE0xMCAxMHY0TTE0IDEwdjQiLz48L2c+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2Ny
aW1zb24tYmx1ZXRvb3RoLnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmNlZjlhYjgKLS0tIC9kZXYvbnVsbAorKysg
Yi9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5z
PSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3
Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik03IDdsMTAgMTAtNSA0VjNsNSA0TDcgMTciIGZpbGw9
Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0i
cm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9y
ZXMvY3JpbXNvbi1ob3N0LnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1ob3N0LnN2ZwpuZXcgZmlsZSBt
b2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5kMWQ1OWIwCi0tLSAvZGV2L251bGwKKysrIGIvYXBw
L3Jlcy9jcmltc29uLWhvc3Quc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93
d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAy
NCAyNCI+PGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRUNFRUYxIiBzdHJva2Utd2lkdGg9IjEuOCIg
c3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cmVjdCB4PSIz
IiB5PSIzIiB3aWR0aD0iMTgiIGhlaWdodD0iMTQiIHJ4PSIyIi8+PHBhdGggZD0iTTggMjFoOE0x
MiAxN3Y0TTYgMTBoM2wyLTQgMyA4IDItNGgyIi8+PC9nPjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBw
L3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnIGIvYXBwL3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnCm5l
dyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmIyYTEwM2EKLS0tIC9kZXYvbnVsbAor
KysgYi9hcHAvcmVzL2NyaW1zb24tbmV0d29yay5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxu
cz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmll
d0JveD0iMCAwIDI0IDI0Ij48ZyBmaWxsPSJub25lIiBzdHJva2U9IiNFQ0VFRjEiIHN0cm9rZS13
aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQi
PjxwYXRoIGQ9Ik0zIDhhMTQgMTQgMCAwIDEgMTggME02IDEyYTkgOSAwIDAgMSAxMiAwTTkgMTZh
NCA0IDAgMCAxIDYgMCIvPjxjaXJjbGUgY3g9IjEyIiBjeT0iMjAiIHI9IjEiLz48L2c+PC9zdmc+
CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtY29udHJvbHMuc3ZnIGIvYXBwL3Jlcy9lY2xp
cHNlLWNvbnRyb2xzLnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi42NTNk
YmQ4Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZwpAQCAt
MCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9
IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik00IDZoMTZNNCAx
MmgxNk00IDE4aDE2TTggM3Y2TTE2IDl2Nk0xMCAxNXY2IiBmaWxsPSJub25lIiBzdHJva2U9Indo
aXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGlu
ZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtaWNvbi5z
dmcgYi9hcHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXgg
MDAwMDAwMC4uNzExNWMzMwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMvZWNsaXBzZS1pY29u
LnN2ZwpAQCAtMCwwICsxLDcgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAv
c3ZnIiB3aWR0aD0iNTEyIiBoZWlnaHQ9IjUxMiIgdmlld0JveD0iMCAwIDUxMiA1MTIiPgorPGRl
ZnM+PGxpbmVhckdyYWRpZW50IGlkPSJyaW0iIHgxPSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj48
c3RvcCBzdG9wLWNvbG9yPSIjZmY3NThiIi8+PHN0b3Agb2Zmc2V0PSIuNDgiIHN0b3AtY29sb3I9
IiNkYzM2NTgiLz48c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiM2MzE1MmIiLz48L2xpbmVh
ckdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0iZ2xhc3MiIHgxPSIwIiB5MT0iMCIgeDI9IjAi
IHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjMjAxNTFjIi8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9w
LWNvbG9yPSIjMDgwODBiIi8+PC9saW5lYXJHcmFkaWVudD48L2RlZnM+Cis8cmVjdCB4PSIxMiIg
eT0iMTIiIHdpZHRoPSI0ODgiIGhlaWdodD0iNDg4IiByeD0iMTEwIiBmaWxsPSJ1cmwoI2dsYXNz
KSIgc3Ryb2tlPSIjZmZmZmZmIiBzdHJva2Utb3BhY2l0eT0iLjEzIiBzdHJva2Utd2lkdGg9IjIi
Lz4KKzxjaXJjbGUgY3g9IjI1NiIgY3k9IjI1NiIgcj0iMTQ0IiBmaWxsPSJ1cmwoI3JpbSkiLz4K
KzxjaXJjbGUgY3g9IjI2OCIgY3k9IjI0OSIgcj0iMTM2IiBmaWxsPSIjMDgwODBiIi8+Cis8cGF0
aCBkPSJNMTUxIDE2MmExNDMgMTQzIDAgMCAxIDEzNS00OCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIj
ZmZlOGVlIiBzdHJva2Utb3BhY2l0eT0iLjU1IiBzdHJva2Utd2lkdGg9IjMiIHN0cm9rZS1saW5l
Y2FwPSJyb3VuZCIvPgorPC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtbWFyay0x
MjgucG5nIGIvYXBwL3Jlcy9lY2xpcHNlLW1hcmstMTI4LnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi4xNTEyMWMw
NGJlN2E0Y2I5ZmI2NWZmMDk5ZDc0NjdiNDQ0YzZlOTBkCkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJh
bCA3MDg3CnpjbVY7ZzgmS3FsUCk8aDszS3xMazAwMGUxTkpMVHEwMDRqaDAwNGpwMV5AczYhIy1p
bDAwMHx5TmtsPFpjJTFFPgp6ZDYtPCliPk0mSi1kQ0B4eUx3ZCUyXyZfSWdwaztnRmgpUlpnYmo4
RWoyRk8tP0hDN2RuMmhsXjhTbjlZPTk1ViMKejZNclU/Y3JyNnkkbWlJMmE2RkZVSTVPaXZqMkZP
UXZ6dlZwbEYrYE9tVV5rYCtUT2VPJXBiMyspb0x8RGZWI1JgCnpzJFlNdktkSE9BLW03PWNKQD1l
KiZwbDc1RjlNK0tgYClDNkJzVkFGaGAyZWpZU2sqVWFePWJaMm1td0g3Y2BBOQp6SyhLUDwlMyMm
MVJSK2ZEI15MMyN6d3hTN3RJVWx6LWVgYiQ/OVl1Z3hZKEluWkBzbGAqU2NMe3h3Nkx8P3NIRlAK
eihxV0lBeT9BIXo+WmBCTCtyV0Q3e1A+cHl0NSZWQEh7TipUMGwjPVg5NXd+JD4rNz90U0ZpUnwm
NmxkbUg2T1U8CnpscFdpKXpIeFlIX3pqaEVkMSlORzxEN0hkcz1nSn47QmNNJGgoSUozRiRIVndL
b0htK1ZMSlZNTWB5PCkkSVlHaAp6JkBEZl88cnh2Rk8kKlozKkpvQypVaE5MY1g8elJmUjBaejxZ
IUxBTkUzUDxlKUF9diU5VWRDR3Z8SzhtPUFFPDcKemRBeGQxdCFsXlhKP2p5UVIwU2V9NXJlZWBX
MzVZUChvZU5AdypUQWx6NEwka1B5Zz5Ia0htM2VUKnV6fipLeHwlCnpefHVDYXNaQCRmUj0palJU
ZW9mZlI2ZHUjSUYySDUmWT1uanVCeUV2YF80Q01iSntlZ0hhLStrUlRVSH4wQGhsQgp6UjclXzAr
SX41QT8lZS0lJDMxdGhpSn1PPTA7ODdxKSQqRElRUFZzeiFzVkE7eys1a3YqTUI4OUpiWGM9UW8q
WXQKek1xKXV+JmRXSUd3a2k5QWJIRmBIbG1ZZVhIODNLQ1ZNdHA/YCk/TVhjKjBseWBEZyQ3RUE+
aHJlUmVnay1XdDNYCnpYO3tHaDsyWW9Re0Aqdj5APmwpK3lSUiNrJTZScU83XkJ0U0g8Pih+X2c7
Kk1Ob08rNW9PUjYyKk1JeilLbHxWKAp6S1JHfVdaTjt6ajI0aWAoM0o/SkNScXdwJjUxeFBhc3FZ
TEE8KDlAU1IlNDgoRGZvS2h5IVI1PXo7dHhCS1l6KzsKenIrKW0wfEdONUtVWm9QZThVP1QtO0Aq
RDIjVUl8aGUjNXMkM2RKLStFRncqQmVoTnw1NyRzPVF3cDMxN3dDSzlxCnpAQTx7fFJNaTU5RyN3
bk8wdDh8dHpHJWUtcFdEMjclVDB4MTVvP1UySXFEayk9ZUBUckVpTHIrX0l9fTQ1OGlXPQp6YGFA
SEtTSW98PldNdj5DQHI1ZmNffXM9I257TyU8aV9SRk0zUmJDbEQ5dk40ND1jdUtwOyZhQUhnRXBn
ZykxKWoKem9RU3hVdGI5ZjVkezcxRz4rNz8zYjllbFFEPSlyZz4qZyZ0bH1hVU5qRzVIYldSdXM3
Ny1MTVNSRW9FNS1nNDkxCnpGU3opX2NYTX4jKlZsSllFQiYkeFB6JmB3Yz09VzV6UE50RiZCYkVU
SC0rRXVoJXY/JWkkJVkyITs5Yms7TkA0SAp6eUwkQyVjUTdUR1A/KEJ9QW9BVnNleilVcXtfRUVz
OXZtMXZMNXo1czNwJiNVdWlsJWs/KFglVWBTS1Vlez5Wb0AKekdPVlp5cXZfO1BDUkJodnVzPTQm
b3BaKW5IfUJsR15JR1IhKTd6aEJzQV9ERDRVVjBBP0I3NTUjR3t8Xi1jUlRoCno5eCRUJnpeKEBP
LXBrJXxMSTNWTypHNFhPaCVfQyhYPzdyREJOd349LUZ2Uj5kKnxoRTIzKzMrUVFKZm96XkUkQQp6
bVlqQyktYVB+N0F2RDlpPjVEX0xHa1NWe2BgRnFpLVlnPUp0UShCN3A5U2NuJmpTOVA3aFVwPmR+
VzFDTVZyRSgKei1kSUlfSzlAV0hUXkM8XkRkNUxEZ3lTdU12RFclaVBkTkc0MU8wbjFZPnhnVDAq
N0x7WFpHQ25eIWpKcz5ZT3UtCnp1Pnp3T3Bqdnc1YGAqKkh5cFNKeHYjTThgIWFvd1FVT2swO3so
fD5pQHhFbiV1Z1YoTy12Ul9jZUQxUWR6cSk8Zgp6anhSZHpWQFpEMldjbXt1Vn1kenpqe0VCVWsz
YWsrI3ctfCheI1BvITJFIytTY1IxJmVYM1QjaVZWclhlPWtvOCsKenEhZSM3OTVnVSR7YEh5PGR8
K3cwVHQwZDFAMHVKRDc9VXVBYm4/fCNVQStYKitCOUdRP3otelAxRiYoXl83JT4jCnpMdGFYM0dP
Y2pWeG5TJG9PKUZyWiVuaVdaY2kjO19GYHItVm9udVN8PkpmI0FBUi11SjR0bXNIY08pU3E+WVph
Rwp6VXN3K05XTHxVZnlzPyYyc2wzI0E5aylxa2BlSkg9UlBmI3QjU3V+TGFOZ2wtNzBUMks3YlU0
JDlhRThPWkdhaUMKejItRWtAaTFTTGhSNmZhQWkrOVAhZ01qMkNjXkFqXzxiQH5BUVB0fExuNFRE
ODVXcVB7cDtEJENNfGZqc1g+RnlhCnpyLSN8eUdkUU5CbGdAMEdiU2d4UTs4ZHgmbX0wcmlOVT16
NkIrdDskRmhqI1JxTm9CMHF2fHEhWktKM3ZRNTROXwp6YWNvN3owczl0c1pvVCFedG9Mek9FdDVQ
fFNOVTN+amF1ZyZgSD5NUy1xRl80JmVEWlRJT2x7RFN1dVlSM3A9XzwKenQxeV8pdjJBRjhaRyhI
K21DdiFhVHdvfXdQKkhgemw1V2l+dWN3UHNKMzg2QmNRMUdUYFl1dnwjZnNUQ0VoemdHCnpWcF5l
aUA0RDhrUzw/I1NVYCg5OVl1JkM7b3dsTSg4fVcrPlJ0KTgrTGNVbGUrdCRWI216fkxGJWcqTUtn
LWUoKAp6QT1gS0M8bGc2PjthbHNVPEkhRFBkMng3dlR3TGJCcDxNZ1czSyhuPGtQZyMwPWE1SitB
X1ReZ3ZYOztXU2QtKykKelJIdXoxMm55PTdiPX5qUnJLdUBecTZvc0Mke3dyZT0+SG9UMGoja1Vx
WTVMJUJKKmE/PUlUR1pnYiR1fDk/TSQwCnpDfmV4eEtpX2REKkZXPHBfd0Mtc2glMTl3TlRtbzxt
ZSNRQ2ZLTkRIakg7Umx6ZEd1akRsVSNGI31PaHolMzlKawp6TUhtRGFHMUVkM0gyRGhsUlFGe254
X19vYHp2YVhSI1RyQkdKJHJ8VFNhfEhRZUQ7ZD5AdTZrc2E5bV9+PjhZcHEKekA8WD9CJVpwRjV3
VXxweGRZQj9CO2klYkcpbnVGNkF1dSkpc0JQSipRSGYoSmFnMj0mPV4jWlcycjtJeTY9NVJUCnpQ
TWNKKDBMRUdkTUBIeU1yfUBHYVM4P3FoeW9FVk1DSExzRmVDNSU1YFIwWnZkOHc0ZzF9VTxjUnpV
SHB4SSt+OQp6dEdiPnNtU0xuKXJXOGVGUVh3cz01RHtyO01IdEpwUHlqMjJOSWlvP0wlaWU2di10
OD1TOTV4KjRXOE0remRaZFkKekgjfmhtJmtWanE1UU1hYUVzNDNGMWZmcmFrU0skcTZlPWFrYVlR
eXU2OSViaXAjJS1EMEQmPiZEcktANXpKQiRgCnpgMCk4RjNEJDA9fEhZQGQ7cHlNO3RyczIjNyFg
YjZDJjVwSWh+VSZRVHE9LUJnPUU3RkdCJCo0SypsTFJWfGY5QQp6dkZ0NjNhN05FOHpXRkRBJHs4
SXEoY2VBSlY9cnl6O304RndNfE4kY0hRZlIqckdnKWVSUUd0N3E2KUVodzFxN00KeiN4I2YkOTRP
b1Vvan4xcE9mYFlBPzlTKFMqV3kkNyl+N3lBK3dMTHMhTjw4e19nNFArLXJNTGU2PT0ofTY4cHZ3
Cnp7Q0dyISpnSit4QlZAeEMhWFRMUERQYmJuSHNsbXd0KSlNZzxLeFREO3Bfa0xLVCYqazlsYGN+
eyZEK3lLNj53TQp6SUU4RX4tTFMmMUFxWERHU0JobEdrWndTfnB5OEgkdHVnRyQ0Umlmaj1rYSZm
ZjEzUWAmeXdBLWhnLUw9PDNzblgKejBmZi1ueDtjNVRtcztSQlFnc2o7WklQKj02ZCo4JEo7ZWVh
Sk0kY0ZgamJ5Rl53YHNNXnlnVWYocT15VG83K2VrCnppIX16e1Y1OF96OEw1PTB4VldLfHBrV2pz
NU1pS0Y7K0BBVzxtO0ZKNXhNNiNrbGkpRkwtfkhMeG5+V0NPbCNyUwp6JGRgLTYmTldRN3dJTVFy
UilwYT07PFQ8fl9+eDdiMUxkX1pWcShXMGFlVX5XcEU2dTIpMCM/ODg/JTJmNmVWOU4KeihWbDY9
UH5VcSFrISt7ZjB3QEFSLWpmWWRlRGo9KD19TSgzI1dBZzZubT5LdVBNI2xsaUVNYWUycDx5MSgw
TkNwCnpRcmZSPz5Rb1d6end9cHM4KDsrbnFZOGd9X0ZHdWliMWVPWkpUbyhge0tNTUVgTyo1UFhp
R1A0c1B8ZUM1aGAmKwp6KzFmZnMySUZOYlEpPmFOMiFtMERPWG49KTwwcVdYUF5teVJOVT1GTCRQ
SkkoTG49dCY4ek87bl96QDlgUVJSPnEKenJZNEk2NmApU0w3ZXlpVk5Ab3pWPld1VThzPkkmWVZn
dnJfc3IlV1VBMCV5cVk0N3dNNERVVXFzRkZCQGI9eCglCnpLbD4+X3l7PHQ0QlppPyRuVTV8JG96
dUgjRjxkRnJrcVVXdV9qYk8me3opPW5yZVZeJWxaQSotaiQ+bHlzTWMlTAp6VD9lTFEzSns+PVYm
LVElX3s4RWZDYE0lcmtpemdrb19tQnNyQSMwVjZRTkVqaWMpZ1hsdlFDKCR6OFQkJGoxQGEKekVJ
TmdHKj4oelhNQW9Ld1YmRW0jWTxWRm0jWDc9QWUrQHkxVCNUQ3tONE0/QEFWQXMyJXhUVD97Xk9U
WWlYdT01Cnp0PnFzI0swfmZ0QVNMRHFiXlJ0clJqSWhDTmZWRCNmWFNiTWowcEwtIVg/S1kmIVRK
PmcqWU5EaFdfRlJLaVRwRQp6Q1AqRjhqXjlMeEJ2d0dSKjdMYzNVTy1VcUVQeilmWjMzPzdVNHJ1
LVJpIWx1YDFRX0J5ZkQwJW1aTU1zMEd4VXYKej8/ezx8JCpMVX5GV1h3WF9xdCgzRDdjN3xKN0A1
UThNNyhHaVRPN09jV21FP0kpYGJIOUNfVlFsNHpqTEFIU3smCnpBUDhtZXhNMD5peD42eUxhfDl2
YFIhWkVyZG1DY3k1dTVtVkJ9OFBAQkchfW9EUyMlPFBBSFopQTJTIXtlS0gtMAp6V2tZVXxiQEBS
O0pNfnBGUTtFfiRwNDQqOz58WVR5aUIzU1c9O041M1kyfnp6OSFoWnhzKVdZeV5pViR8UUhnOVMK
empYUjFKS3ZBNmNTVGppalZGS0NLJT5zeEJDRmVNeXQmNz58Und+WWNDV2BVdyY+cnhPemF5ejBj
d2dVMWE5bG1XCnp6T1R0M1FwZUpjWlpnSkYmPFgmfmQpRFdOS3BNTXp4P1hyWk9wKyV3ayE8VCs2
ZV5zVT9FKzE8WGM/ZCEkODBPKwp6c3xzK21CbTRDJnMwVmRaMDBqYWcleGheJih3P2RhaEp1UzJ0
ZCFzPSReOVA7Zmc/OHhAVCM8IWZTS3RHdkc9R1oKekNvZWgyaD5Je0g0WTQwI3Mrc0lXKzw1QSQw
QkxMS3UmR2ZDMEUrWER2aUZ6PEQzNTlnPktnXnRyemxpTmRYb21tCnprZz50T0RqMShBIz9jKTZQ
ZlhJSztxYnJmNnhJVk1pcDNDQTlVVX47eEB7MXdzaFImfjcrN3NZUGBBXktPOVV5Qwp6d21ERzh6
SktFRUQ0cWJKKWRXZjRCT0xYIWZCLVVDN0k2YUUpLU1zbno3PztVNTsjPmQjP2xeeUI7Q29IKVNK
Mn0KemZLcDhidEVVamgpcEJebmRyIXQjV2A+eitTYUBgIVExX3ljeTZwQFM1c0o8Kzk5MXdYKW19
WUgzU29Yckl+Kms/CnpVPFhJNWpWVUs1RD58aTRwcGolTGN6M3lvbTh1VT00Rnlsa2NHN2VKNlk2
YU4+Z29lVD5lKjd2VktmUTwxYztwRAp6bChyZElZbWRyR3BzQCVeLUB8JClnWF5BdVR7a2pSJT5n
TipOaFdZZlliVWVQdHdpZE5ZQ0RraEUzVTZkPlEpcjAKekNAQiV2PF85UmNDXkBrelckJjBCd3My
LWc1M3pGeEhmS0ljUHswX2UpQW8+aylOTjt3UzAhYUVGQkZFQFJWb21XCnpHKndpdXF7TUxIajUj
blZgTEY0TkhIa1J0QztvYjcwdUAzcnlpX2pvUkJrV25ZT0BDY2lnQ24rLUUoTTlXdkNwYgp6KHx8
eUF7O3gwbEU1SWJIb2Q2WkB4cCFiRVJ0NGBCS2BGWUpCYHV3dC0hKz94aTt1YyNLdUpjd3NuO2dh
RzFTJUwKelA9JD1Le0FUWUMyQkgjeTJ3R2hidkxha0hgLUozbV59TUpDQSZ7d2dMU0oxS3pAdWNX
PEB1Mzg5dlJ3QWk/TWsxCno3JDZzd2RFMU9Sb1lLfXE9X3MtU05ARHUwblZSaXpiPkFLPzJxb3xN
JD9pPjk3K28yUnl3WWh5SzZjeV55bXY+OQp6QTBSLSsyNmVnamh1e1FHe15gQVgrSEFuamA/cz1n
V1NFUjMmWSVUYHFCOEcyPTZGdFBwR29tM3VtV0N7dE8tYnMKend2dyZDM2UtSWpxKEk2VGMyKXxr
ZXJXQChDY3ljYDNkSEpadm5mOD9kKWt6QFBNS18hcSV+ZW9Ebm9lK0JjQ2EkCnojUHE2VVpOTHdB
WkQzT3xONGpQT1IyWWlOVHNDN0tAMEB1Jmd9OHp9MDxDfXtOc0JLQytvKyhVO3FYKmxPV2pjKgp6
WjdpRWhkSCFMP1RDJkZDWUt1YihXIz9HY2RuVThQUnd+e2ZRNSF9REQ2NDA3a2ZBNClxMkhDMFhs
UlBBPUt1dyQKeipEVH56WH0yTV8+e2AjYHhqa2VoaTNrS0pJPiYtXm1jTipQN0xuRn0kTHdVSEI7
Qz1AWmtAXmNYa0BnWl5pKCoyCnpQfHJscnhJO0NXMUJjXj98Ri00SChlckU3QXNtUnhUcnMxVVBh
UyhRZyh3KiUoO2I2UUAtWXsrOW17VENWWHYhQAp6IXFvTT9rSm99Si1IcVc/PT9xZipWc0hvRitx
c1N8bkBYQk9EcCs3SnVKQzdiUFVXKG0xPzEhRC04amwzNm53PF8Keio8PEpxR0NXb3FwakNuPy13
cj9KY2VMZ1plcj8tUkpkKW8teTl0UFd2VEBXYFJ9MjY5ezVTQlhqXm4xUzU/RiowCnpBOH5yN257
JV9yYTdUVXpxMTN4bUBXZjFUSHx1TVU2ZVNSJDtBMXxzPUBBQ3dHTkJrOylnUCMrJEJPV2M8SW15
egp6X1NzYj5tX0V9JVA1MzhnST1RbElLNUtIQERYR0pmZUVLUTF8NGQ8eyRnemozVDdqbnZnTTUw
XkJOJnA1Vk8oPHgKenkoMlcxWiFLRUUrcSZrR2tJUj9fLSVNV1h6Y2I8XiZUUSVDQmkkIShUWWZ1
UjtzUjswYiM/cD5yVURJUFBoKFpPCnpmez1lNytRRkIkSzJBJEBhVWB6cEF9O3dEZ1lma1FaeyRQ
QW9KaGV7YU1lWW1NI0VHK2ArfDNAWUA1d1RYUG0lbwp6YDVpbl85d09UU15acjtHTWdidFAxbD5X
JTVCNjsyaFY0KCNCMDtzNUZsaW85QHM2XjBlMGxFYXs2KzZfR1I4OUUKekJDSXJxSEFxSWlQfUNU
VUBjIS12VC1DWE5lO01BKzFFb0UqSEpJP0IwVXNMV1JHREV6elNxQmpxSWNZUSstYj5VCnoqbklN
bzRUbXhpbSRgRHIwIzBlXjstKCE+YkFONihmaWF8d3ReNTlac1A1KUxofTA5fEk1Rih0JUZiVHFy
ZHMmSAp6Jj9YKSg0PHZieDFgfEZzbTw2Y2VORyFwUl9ITj8oRXNycWJWcD5mPU1TWFAjayszJV52
bW5nIWNNSU9nbSokKyMKenRXPGBQeEkkYz03VjJSV1k5cnBFNm5zcEZPPnQlQ2RfRmFFMzdzfkAt
dyhkWEJqdGdyKj42bDVfUEskdkQmMDJaCnpTSHJ1d3JnQUBqS0lhVGhafFAjZG1HTjViSXB8eylj
PCtuX3lzM1FfS2k8MkVwQUshS3pmIX4pTHN8Pyo0c1h8dQp6K0d0bWxpdSUhTT5uKyl0b1MmVl5h
WHx+dVIpK2NVQEskIWtDMGZLYk95akZWY3k4ZCFoWU0zZHRWKlgxKmlnPUsKej9aeVpBPGc2M3Y+
ejxFQyRAX1RwYnB2c2t0UFN8WXRSLUM1SElGLW9ja3FraDlqcV9zQCFuJl41TFQ2O19SKHI4Cnph
ajtKKykkY1cxOyF6Xj9xZ0d+NHMrRkBeeD4/PmJnSlhqWE1lbiNIemteP24/NHFLY21XREk/Mmc8
aExlMVAjZAp6UmF6diNwP3IxYyk3K2NlJV9uRF8ka0tFTkJSKT1pMH0mJGNEUWFTZHxFT21ubXZ6
cUwkPklSTiZGfCpQO3ZtfjkKejF4aSg9c2NwYjghaTM+dUVraEEySVFCSmY0MkB4U3MpWkI3YzIz
UTd1Xj89di02VCZuZDcrJSsmWEhYX1J+YVRQCnp3aUBhK2xKRjt7O1N+VXFrIU9IVDh9aSRjZWpl
WDZ6PGF2cGFiO0k4JEVJMitjJFh8MWt0QnxhYVoqd0FoVV5UXgp6WnRZPm5TSitlQDtlfUY7Yj4k
cX1xYXU2YkdJPHstaiteU0p1bmE7VkxNV0QyWXc1QmZ2d3tyc1FteW9jUyFVWXwKekV5aC14VU1N
QF82MkJ8LV5JJmxnQ0gxc1EoKDg5UjJwXmAyMD5IazZRSllEdSFUO0hfaylJRm08a0hTTHlzaUNN
Cno9QX5NUkBEI25QJmlQNnVfRXFIKFBFNUQ2R31EMXNDfkN9emleO2l8eXBKZShQb3k1THpCVk8+
N0dyNDxPREtpXwp6Z0JNSy1TRXw/WFFlNUtFKGZ8KD9fY0d1cldVODs5RWBxTnllc3sxb2p0NEw/
ai0rXl5CUzxtaUJFSGtWZmk7OE0Kekk1KnFGJUM9YzcmOXV7UTE3Y041PldEbDxjdUZvQW05QF9u
aWxIWStHbX5eO0B+YytCc2E3OURwWndufCNOeHEyCnpMMVEqbTNPclVDO0Y8QztMb09uMSV4SHJQ
KlUpIXZWKClITDBtM2tKZlVEfmp5KyYlKkFQfUp8Tkt3PzdlO2VNOwp6b3c9Uk40X2k0aSk2SG91
b2c1ISM+OWlAYjFnSzNPRzRFN35RQyMpa0hFVTczRishNVI3bERjQExxMXwjUkE2bC0KeiZrTDB0
SkU5VH1QYmh9MG5PXjM7Tj5yNktGaCY2dUZKND5gQkwkIylOLXBhKVAqVmhwJnsxezl3cDBxTkU5
ZCM/CnpASyhCUCRlZElRXkhReEc3aTU/anEtaSQrODNfblBGeDdBX1FjcWJ1MXNebHlCS0VpbnlQ
X2dIO31XfiNHUSZRPwp6WHxsSTU2b1goVnY3aElwcEA0e3khdCYrSSVlNWEwcXh9aWgmWVJvJl98
Vnxjc1VxVE8mP00wLUF1IXI9RnZnRkQKelpPUFdGV1BWUm89WEZ6Y3w5I2FlajU+cj51aXJ9STVa
WXdsP3RZZUg4c2ImZWJhcig7d1JQTChXZ19BTDJ9bUA8CnoxVlB+RCZGJFJ8b0p3UTYwUzg0UGFu
Plg7PCQ+KH5hOCE+SGRuRj4/QDl6WWBoPiNJT1pHRVloRE52WitxRUFxTwp6QWgwYHZBYUVvRCt9
RVo2PEdsMGZGI1d0Pi1sailGPDM4T2R6PTtATlhxcV5KTX0oa1g0aXlhUEYhUCpxNHlwPlUKeiYm
KEB5dzZ7Tk10VSo7OVZSM0N6SW9LTmNrJSsyX3Y0KDdXK3dhSHoreUphJWw/UGFgWHUqVDJSMW1B
YClhK0RqCnpHRmhtcSs4fnZSN2NYQTtLPVB3Uj0zX14/c0gmWWVYYTRVODFfbjx2WDhKbVVPJUF8
JHVlUTZwYF5sfV9IIVpJXgp6YDNuMEIqb3NLcChiNGZVWVlvdF9FMHw0UUohLTk/dEUyc0FScXVi
KSFqRHd8NTN1QjwjczQ9PGh0N0x2JDM4KSUKemA4OXBOeW12TkNoaT5zbmkrP20kKV5PbVM4eHNW
OXBFSVpUU04qJHBVc3lGMk9AQ2x8PDVibm1vSF9IWj9LYCU8CnpISThHJDd6RyRWJDRlWj9eIUUx
dFo4ezkpTlFlZkhjRHo+ISElKmZnU254TS05SypPbEtUKWA2UkZ3dHU3djleeQp6eVo8fmZgX0ND
b3JXSD1UK0dDRUhgUCs/flV3bWA1MythQm8tOSVvI2g9QFA9bCUtJEhXSE5aP3NaSiRSU0lGS3gK
elVkeTUwY2B9KWRvX3kqX1UjdzImMk1xWF5PWlpyMGo1fjRoKHdueiMtRkJfMiMhUkV5ZmhHWE5B
YDxrQG58dCV4CnpiPGJidHl8K3hUK1dUXkd6VzNnbiZ3VGJqZjQ7TWBiRGo0LXBjeGlVQyVwR1E9
PE11Vl92ejJ4X3l6QyVldmFRKgp6VVFQa0RrM1BCWHk2YzlQRW5qfGhUVSlrViVeJk1qK3FMSExO
KGJ0a0JpcShtS0k2PH5BRys/a3RBX2dNZClhNVAKenlpKDVKMGBBOyUmaSYpKCl+PnkhUjRoNFRq
NSZuQVljZSZjX3Vna1I4R0Yqd0NEK3tsO1FpbUhEI01yaWdJN3hSCnpJdnt4UDtSbjhkIXRvMH5t
cmlHX19rSnt1KnJjSVFANFppX0dqYEYhPDNJbzRMbDFuUCNCViFqbURpejs8aUhwYwp6cEstPDtL
RCUrX2hRQlRyaSYkZnZIcDliKUspXlpnWjY9ZHA7bGYzcWY4dlFwfEdNaDgjZlJ7Pmhsfnt3d18/
VGwKeipRe047X1MrKlBCV1YkZE1XaClXT2QqUUs+TlV0X3YqamdBbVIkRzExSFprY3h8KH1QXl97
T353YT0rKWFSMkBICnotTGhpRSolJFRuXmdKaEcwYEkqWj5kQmZNUi1FQDwxcnlBZUcyezZhRTYl
Oz57YD5Fe01POXpYPzJxTnVGODlXTwp6ejVWdnZAQjdRWXtQWGpBZCpeKy1DRFM2X3RKUzJscVhV
e3JxZSpre2ZoND08KXZJbUV2YEJDN3lsPnhkISskeU4Kel9TPGl9azdVayZNWUJKYSpYcXEleiFf
dEI+cyNOeGFfI2ZhLVooZm95c31hJENsN0AtNT8zRHdVTW83U3FPYXFXCnpNKypuc3FwSkFUZCNg
fkFna2hTX3U4dzxfRUlEYl91WVl+I1U1UV9RYUJ1KFJjczxnbmJ3UDFxbkJ3ZlMmd0pPXwp6JjZ9
PHQmZ0N3eVI0UyZMSCRYJWpBfWFlVUxzSlZUclomIzI8JXVlXz5NVXo1VkhqI2hYVTh3KyY3MSF9
QUEwQ18KekthSFhZNjJaVWIkbjA8a1YpTyFuUktVZC1VQWxiWiMmdVQ/NGkzR2VSNFNid01YYDB4
cTNXdyFsYmFGYiFBVWx5CnpoIzBLM3EqOCYpV1lTTXtiIz91MCFRdz9mez8pKFZAbntye1RLVSZC
Pmkwan07YlQ4ZFI4QEtSeVJTTlYpMjgrMwp6PFp9NzUlSGA1WWFVMzElb1MpJm5aJmh1c0VzUkJr
KmNlbD0qNmE7fSlYc0R8XklTKHFgeT16YEZNNFJybnR5cyQKekx+MHt2KWJidmReQiNeajhIY0dK
cWlRT1duNk1+eyYzQ0BEQ2M5PEpANiFWVm0xWWlNNEJnJEs+K019JHtAQk9mCnpKclY/Z191aD9m
PGA1KT5vSHJpVUhKUW5yaSkoWCFFejxCYjduQlpfKzh9fmBSJmBTNSZVIW16UDNQfj5zR0Zubwpa
e3tpPUlkQEheXktxdnFKMDAyb3ZQREhMa1YxbUVCMihiVkYKCmxpdGVyYWwgMApIY21WP2QwMDAw
MQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTI1Ni5wbmcgYi9hcHAvcmVzL2Vj
bGlwc2UtbWFyay0yNTYucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmExMzVjNTRlMTQ5ZWFhOTBiNjEwYTY5Yzhm
OWJmNmRlYjA2YzBlNjcKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDE1ODI1CnpjbVg5X1dtc0VI
KCs9KHFNVEAoO3lGPjkoK0AqTU40VWl4JDQjbkxJNmZmQFgjaTYqbnlJYzczeXgqVEJDKWJ8Ywp6
Kl9uSDBYR2JENSlEJHBLTmwqYSowRVV2SHRRRyhPMU57akRLdF9hcThNKiFiM0lLP3VEYWxHe2Ao
Jk1VXyt9WF4Kel8/RW5EJmsxPi03YEl1Q3EhNWxvd1hZMkdCZCFwd0lQI21GNjRmRSNCNjVkMTtp
bW47QWQmJWRDYVFudnJHQEVACnpxZWJUbGxebnlSPFQ4c1ViY3wtSlBHQjJwVj1abUNeTHViRlRp
PjhLU1QqX2V0I2EtNzlDJmhkVXtKWnpXYXVybAp6O29OYUlafEVFfXZ+JVNuTioqX35WQExIKk1J
eSpmOXd2TlBNRk1NKk90dXVxbS1oX2VBM2g+dzk8fiUrdUhGdXgKelB7dzEoNGNRbW8haUQ3VUBJ
M3I3bCZiMCRkJSRzVjx+Sj5ZNGdXZ29DK3lZNzN1JlV6ZTx5ZD8hO1ZYfWJad3B8CnpeTTZkTFBp
ekB5SlV7MV9TRmlCSVNVSmt+UEUxKkk2RTkzcDw1Y1JgNihqIVpSVXNPMzZeJm96OCk7enRaeXJ1
MAp6NEQkKE9EY09IJUlQM2k5MHpwKTwrbD8waUN4JlI+LXNqZkp6MFFeY2x2fWpMc3wtcTYlWExe
aj9KJUMjeH5AODkKeipHRE9hRD44PHN4OUQhQ1MyOEJhbGAxazM1TFpVaEJPfkB3a2AzP2tiaEpw
WCV1REJBelY/MWMlVzF4eGk0eTRBCnpWez1+bTclRFh+PXloN25gM29tbCVVJig1JDU4O19pNj5C
KysyU2pFdEwlYH5ASDgyQ1R+e3RwMGxLQW8zd1MlZwp6I0tPIXJGNGZqbXhicComNEpgQHwzaVUr
RCRqV35NQVA9d2QqaVVMbz1GOCpmQ3l9KCs2LV50TTJaSmUqayRLV0IKeiNCKjJ2UDB1fVBPdCRC
RW1RKUp1UkgrQnZDdVlgajV4Q095e0JBK24tS1MrdllhbT44PE8yXlhVSTNERzFXJVVWCno1NSsr
Ql9vWEVROW1VUUVJaUhqVnckdFlmKnpufFY8XyhOP1ZzcigrRCtoa19TMkp0dSlSe2N9TVlVYC1m
clZVdgp6IXdhNCN1fHppfk4qTWltOyZnVHZIKWhFRDkqZF9neEhTWk5AJj51Kl4welhvUU1SMSgq
Nn1qJXQ7a09NKVVpc2sKenJ8ITd0TFJOe3ItO1FIWHlkNzV7S2VvMkVffnpgdCRaM1l3dkUjSTlz
V0l7S0VBZ3pEQiRsKWdJaVJjMmF2P2JKCnpuaUtzVC0jPEooXzRrPEdyanJuVUZLQnB3RS1gKGI0
Sihfby0/NzF7OCQ8cFlyOGtJVERxREwyVHpJS2t7Uyl9cwp6X1ZSR3JRZnRJflZCZiYzYnAyKENp
e3sxQTdtX25DdVNrUHshKTN0NG96RDduRllWTTVqTD8raGMwSUUzYz5WdEgKekFmY2w/SCM7OypM
WChDOFlhZ2wqdURFYVB7UWg+cnw4NE9XKGtUWEhYSEZnTWNOTnZTXzR9R3pIc21mam1AYjc0Cnp6
bCg8T2ZpPjtuQnZHZ0dgSzIwa0xoPTVFWCR+MWh6VW5SQWYqIS1uRGtwZEg7SGlVaiF8bHk3UDdJ
Plo9NngzRQp6VEJfWUUjR3VTbExQV1JANm1eZT93K28mKFhsUThRYV8pSjNuYV4/XmUxQVJ3Sj8o
cTU+fllpNWI2UTY5cnNKansKeldedyZjNHx2QG5kXzUtZ2hRd3ZCRz98SlN2MkpKS1JXQHVZME0q
Xk12Zk9QZUolSz14czhuYEgrJFdCZit1N1d3CnpvNV4+Mlc5NilQK2Y3XjI/JjA0WSlXKiZ9Y1BB
M0J4M2xWUlM1d18pUkkhJVIxfGtWaEBrNnJ9ZihJMy0hNVdeUAp6LWR9V2J7Izx8QmNwUW0/UjRB
MGZlNUU4MiVzfU1pSl9nK2VQO3tRXmRQOXlteXc0WVh5XjZHPz81dlp1QX0oITIKeip8eDcjWGlC
JGJgeT1yWkNsQj1OZVdwVlFQMkh9LS1kfip8JE5VYSktKntjPihZcGFVdmMwNHhGRillRzF6T0F3
CnpBdzQ2eCU/cChgK2BJZCRtczN2JiswXnFKdWRVc0VSdWtKKD98U1JJZlRVfE5RX3FjZ05DWHZm
UDBvWWdvK2Qkbwp6VzYyeUh1ZlJDKitlNGZDKTF5JW8hT0RpN3NFeWZIIz54aVEmRkFONVpZK3Uw
T1BlYWNrLWVyPndeMjQwI2VSdmkKej1kNXA2I05GJCEpOU5OM0MhcDdaZyhsfDxGfV9HQGlEUkpY
M3Z9STc2clFnbUdqeWNZSzZma3x0flozPUl0a08pCno3MHJhQGVtOEtQaSNkWjlKUmpFR0ZMYj54
bWlaPGxedyFjJmZUQjQ4RjU0QTQlZEMzIUV8YmVxXlBNaiY/fml2Tgp6X2p4ciNIOFd2IU50bk96
TEJKSyNqYU82aCpLcyh8JUVrc15aPD1pRyZgdnImUEVCfVBqXz1LfU98e3MyITI1eTcKeiMmYnJA
ai01VkxubXdFYjdgMU98JkYyaWAwKDElUzFjYEJTZzY5cUpaRjRzdGRAeG0oY1k3bjtUZyUlRkN4
am09CnpCcD8lNW9lI1IyX15LQF5EJUpeN0Z3NXxSOVk9UXlVQ3dLN0MhTUBneCMxS1hmcEdfVU4o
fXxjXldYQTc7SU1oSQp6KkhpJSRWQmJwIXJBemRNbm4lQSU1c2E7NmJpZklRYktwV042OFpCPFBm
JWI8T3dLVz1aXnc/Vm88RX19MjxCbikKej9GOTE3Q2VWSWxKVi1SayRfb2hUP0w1ZjcyeigyOXND
PkVaP2dxfitLZCQrYVBzU0o0JiliYHNOc19sLV5sKV9qCnpIdiYjc1JlI19WaHFQTiZWQ0AkU2FD
WWNoPiphIz9gcHE0cnZyfm9TOShWOzV7VHdvNUZ1VHlpOzY5b0M7UXYrfQp6N2pQYHl6MjJ7P1Bf
YVFuUD5RJX0/N2h9LStTUFItKTN5NUNpJmllelp9VEZTVzAjai1ZMFZQNV5xUzVBSWtNSUAKel9N
R0Y3e3Awd2syeFlqa1klaHpjK21tOzA7QnskdnA8dTFELTQ1RWJTazkzbzYqV0lIdGI0QiMhfFUj
V191RG13CnotT3tDYkg5RENSYT13YiREbkBuTko8WClWYHxJNEBAMHszSWxVTVN8VFN+Xzc1ZTJP
UVRUZzcmb20mfFc1KkU+fQp6V0lkOUImNF90MDU3U3RJa0ZfeXomZDtfaitIUThmKWxoK2N0KUZr
eldeUmNnNiRtKDBoZGlwWUJkbl4xbUcxU3EKeiN0eW1+V14pS1YxZEV2WkspJjw5eVZBeDhpSUdv
RU9YN35SbmJ2R2l3PUp4X1hjaGdfKmJ4YzRiX25pIUVjdD5CCnplfndXZGMmNlplelV1amR6QH1r
LTVENVooTDU4VSkrdWR0bkJITn5ZaT84fTY5QSN8QyQmb1pVNy0+OHxjQTNOXwp6N3QrciNGTWp1
TG1WI0I2UypeJCtrVVp8LWtjIXFKV0tWZk8+fjhuLWBgS3JUbXchPTtJJmhkdXZ0ZVk3UUhxWkAK
emg5S1hZJjJCU3NHMDFUQjE1bEpGTGAhKURgVjZfeC1TRGFsQ3YlZXBGLW4qTFVROXZuIz9GZzFs
QEgwVF96VzBnCnp1YV81QlY/P09kK2wqYyFqZHp7TFladnx4QypUV0w8aDQqdGVwcC1IPm9KTUAl
UiZtSzReZlo5OCQwUEFaN1lsUAp6JGlCWFgjUURxMHkzdXxQM1cqJVU4VVhCbTZvOCFIMGxuX0JG
QV9vP3tUcChKY3Rra29nJStBaEY2MXUhWiR6cVMKelJCXzEwdSpqb2ZjOygrdWkoQGp5SEpEUmg1
MX50USpVeEopQztNemlGbzt1OT50b0txVi01bSV5STxDeWEmKnllCnpBOTYxJEBjdVc5S2V8cnNg
UT4/YF5DSjdnN2E7PE1PaylHZDV9K25LVz1ZRTUtZSR5SjdAYWQrSHpyQ3grMFImTAp6Kyt5X2c/
RllzTVp1fXQzdWFgWVpzRjBzYmIwTSE4b3lLanw7WDZjb3IyYW1sYitgel52NmxDej5qNDkle2BY
Tk8KenVHcEkwRnNVI05eUSllZFZnZjEzZCN1WChTNmZ7fUpjZ1EjKX11dms9ZG89VWZyVF5Bbnl4
UWN1PUlRWW40KWZkCnpobjBtS1UmelZ2OXJGbXpuKXYmeyl0RjlfXnFmNmtxd350V3UrMTRebDIo
IVNDPzJaISU7bn4rOXBjczcxP1lXdwp6WWIqYkFIWGd7TGRXaCNgZFAwYnBvWlJGbE5hRDVJZk4x
Vkk2ZjVWSFIzSV8qVTB0bF4+RGEhZ0VKPGZKUCVWOUUKek42ME5ucl9yRll0UiFka204NkpJO05x
WUxqfDNkZm1+Ymk0V3dWZztYLTgxNDQtX31WdiFiYjckezR2PT1sKVBNCnp1fW42aXlkTF9USnB+
WWRKNXB4PnxJaCEzPktvdW09I2AqPUsraC1tdiNkZzFCaGowditfIUNKcVBiZ2Z0Z09Sewp6T3le
RjA3fTRrOUs5MTRfYCtWaFA+PSkkam9wZSZocU5NV3E8OC04WHV9ZlUmJn4rOTV2TTNhRXhWTl9o
Y31ANlAKejU2Km4zKChvSk0maz4pVmgpbHZHVnROdGVhbE9ZQ0hnZ0lKZE5la0Mqam93azY/STF+
TkB8P3Y3VWNCdEF7IylVCnpBQXdWMEs2TTdZdFZFUzFBS1Rsb0p6aGZMPC1xOGBtYU9ifipWSzdl
YDhgcTBtSUJWIT5jI25lYXolSHAoMnJGNwp6Mj9gamNCJn5taTIxQ15zazlTSCg4eEpAKXZkTGk3
Sm08LSgjNm1fYiM9WlYoZlJDczwjJjwzRE5RO2dfPzspbWMKemp4QEBJKy03X3xzVEx6NF9FXl44
ZDt5WiVGO1I+PDNXc05FU1pYRXktJlk0eHVkbWA9bVNlZCZgcTcoP1ItTyQ7CnohdDhjT2JyJi05
K3lGdkVzdkBsO3E2N2J7NElAZFdXVzY+bSUzIT02e1V+PSNobVo0ZzQ5Y1gxKH1RYCooc3R2cgp6
NGFVXkw7aFJ9OVMpVnsqYSkzZlUxQllsWCM+IzFCVXopVCVKc1lNfT1Gd25FJUdtN3lvdHR9cDBE
QHdOMzZfY2YKemBTKHc8e2tuaCZZMjJRMnRFTHA+M0U9YGs+YyRWMj11JClwPDltbjQ9ZngjJGlC
KG5YIXBrQ3U9WkFUUGxgKyFkCno+VzF0Sns5YHsrZGkkfHdIakx3RjNLJEVGRHooYVZoP3JBfG1A
Iz1vampVWDNlK0M3Pyt9fm5wUk8qeH1hR0NvRQp6RHR6KlpNTzA+QHF0LTUpRTdCQz5SeFkpb0NC
ajJmeGooWXJWTGJsOGthc0JwdSEre1pfYC19YU82UGojbXhMXmkKekVROShUbVZ3TSZiVHBOSHVp
MUszRm1RPmhCQ1FMSSY7cENiPExrI1FiUGFwd21pfTktJGVAeTJnU249fSRTVGpeCnpTR0E1Y1hX
M2BHUGFwSEUyPFh2QVowYkROXjtIeXhsJnBBJlMlWi1VNDtWanVUREA2JFgrRnNUQktMNy1vQTZm
UQp6Z0Y0MUFsVy1YcDE8enNLQjwoSH5xSXRqYHtXaGJ8Y1QwPVE+Xj1GZnNHSElHKmgleDAodkVD
JWVqaGNicnE/SHEKejc7PVY+Y1hadDVCZyp5YXU2PChkRjBBdyRDRyplQ24mSUV6KDhiJTVSWWUt
ejVBRiNVbns1fn0hPTlKNCRnQipsCnopQTl7c1RJKnlkYTdEdFIkdkRlI28yRH1+TlR1PTJxS2g+
Y3IpSzk9KXg4REs0a2l5NF9lUG9LJUYqWms/JFNvZAp6bzdXSDhYM0h9JF5UOWhLQGBPPCR5T01j
Vm58NnQjQzZTT2diREcyZERReXl7cFlWRVE+S0BCV2w0ZU5gPz0lYEAKek4/VFlPSyhOVWt8MT5F
WTZ7VGp9Y097MFZoaSEhdFg/O2xnIXpSfmU9LXozeV45fHZBPHEwPEt7PjtxeW94TzJrCnpeamAl
K08mKl9aOz1+QG9HNyZscSV1ZUY+ODJKMmZ2akg1MWwpdjQ4dyYobEozT0YoWUIqcjQtVjZhd1kj
dnxnJAp6NFE5UjR3P1M7JTgyT092aCgyT1R4K2spZz42SH55d09jUj4yNHlzTE9rI0tEIT9ZWXJq
RnZ7fUxoMWE4aHF1Uk4KeiFtUWQzMFl+ZjQpTkVKJkFANH5CLU85ZEx2Q0hBdns8aXgrekxWX1ZS
LVZ6Sns/SzJzSHhadklRQ1RhUkRVIXM8CnpLaUtlZ3k7V1RGMDItPjctLWA/ZD1KTjdQbHRmJlNC
UlgoZCRQSSE4XjFSbnxgNiRRQFJGKCtgTEYoaz5WKHxTZgp6b1k0Zyt5NFVvKTtEbTQtcyQySiMh
ak5lYW9QNTNWJWBEM351RikzMXZuYiFRREFWMnlPUCF5a15BVX09MT59WmQKenEob209JXB8JUYx
NSRGJmVSNCMrb1VET0ckTytNWmk3UTdrTTF3YlJpeD90JFh8UHdyJjBTbXk5flcoVkJRIz07Cnp3
Rnp1X15TUGAtZW9oaDkmbWJBYS1qWG98aGxncXNrKztNQWwxUnlWNmQ4SFdLTiNqUnUjX1dXTyt+
NVNGMkt7aAp6KiZuVW1QOWApT2V3OVlAYV5PZ0FCYlU2eHBxZUFXeDtAKSRUZ2xsREd0OU5QKFZ6
Jlk7ZWAyNERPPm1fVmRCWmsKej51aWxBZjwmPHBqP14tVm5sI2koUldYbEdYfFRgS19PbyhFQ3Qq
X1EhVT4rKi1vcFooJWtGLTxMRytBWlhwbk14CnpKRXFUX3s9cnBqeHlpXyRPfEFsRTxsb3tGVnhO
OFM8eHgqPHZZV2EhIT4xdmVnYDMxbV8wTUhycmItVjlQI01eWAp6dytAQ0c8flpSUHErM2kxM3kh
VCtlIyNAanszWSM0YS0rbX1reXxaUHcxa0tsUnBKNzRhfDFDaUlgOzN7QTFtRFIKejNgIW1zPCZQ
JkZpXnxDaGdEQ0ZBaGY/eyl5UiRfYSY3NCZEJEVJPmRjNUZqJC0zPUtyY3grYDZeMHtfSHE2TEJy
Cnohdig7RlZDdGk0eSRJPzh6d0ZkKDR7aSNkR3RjKFotbCNtQ2xFPzFDZjROSzJLLVMkNUBjWmY9
RWE8S08/YlVJbQp6RT9uP2gzZWdFJj9XP0plMU9hYX1XaTN+SDFDOUpvRXxAQGomSkd7QXc2RD14
e20zJFZ4RnhyJnlFNF9qQUQjVU4KeiR8O2VWQjx8dG9SM3tUaz1oOVFoWnhwUXNLPStGc3tzJjcj
SFM9MS1SKz9hZm88PVl0Ml9GTG4mMlI/VEthRmxgCnpGdGVMPzMmU2tLSHV8fm1qPk1fcEBnbWh8
O0g5YzlDfShkLTE5K0BvN1UkSDlmaipsISR3TEoxZTtuV1RHPXVsUgp6cWdWTThpXm1xdiUrUkI+
IVc8cTclNSZCeU4/SG1sNFBfdXJubmdRfDNZLUN4cXdzTjskQ0MwbE5WYjQwPGRiUlMKejhITHFq
Vl9TYChIP0ZPIUU+SntiPHNMbSgmbHs8MD9HODRiUXBTKXpqOXtVNW48N2VDS3A/cjAjRk8raHZi
JllhCnpybTdrMDYoWipWeXo9TEk5M2Q5fT1MRnFyaChLcUElTjRCaGkyemxjTGAwPnctNlNGN084
OSU9eVZMOTNrQyV2bgp6PjcwPzBVZ3U2Qk5QS310e3sqKS0lViVWcy1NJExiPj5PJCtWS31KWVhD
Zmc2JCNvKEpIeGt0eUBvMSpMMWIxODEKemVOQWd7RF8rfnQxI0tONk5NNm5kMGJNUTBLeU9EWCFt
bElEdnE+V3pyTjZrPzcjQUc9UlRoYVEtbjBaVW5Nb2pTCnp2Y089ZmFBV2RHTCRyIXxNUmFtVVl9
VEtGOUBZQSlQYV84fFNrQUpfKSsrU0JYb2ZGaVJJelVJVXFEaXpOQFlYKAp6eFNLNXFSbFlWWjJE
Ozl0ZFRZMWM7SGVBQVJnUmExJVV3aURBRk0/UlJPfXVgeGREQT83WFBqN14yYWBiRWBxa2EKenNP
YDc3LXJ8RWw2QTl5QVliTElTOV5TSUxSeGJedTMrPlEmIzgpTCROYSZtZnswTDRHPTVWYEJPWW1G
KVp8Qn5xCnpuKzt0UXdDTlhFMUQrfTBeJiQ2ajMrX3YjQ0pMJm9TMEI1KzZNOSp8c1QkSWM9R2NH
VmMpMyU1Smh+eGV2YnhUQAp6RVFIfGFmdDhKaGdjWUU0LWU8R2laJUpOK09+UjFUMmhFYE9eRyFJ
T1kma2dsdSN8TGU/YGIwPHhwZXUkQTVyeEYKeiRjVXh2K3dUY25jUlJySEhHOXhtdUtSOVBieH1S
VEIkTk1wZy1EbFVtVkJSNm9XbilZMlRsK2p3JipDJS1sKWNtCno4MXlkVVk7I3Bhc0l9QXk9ZTwj
PSpySDVFKUVhe1JhSkR7eShlKjRvTnF9VEt4Z1V7QF47OGxmWih7Yl9xPStWdwp6aEk3emFLd1Bt
TWhLeVJDPkE4VHArU3M0V3dCX3BJdT0mdTQqfDJmQDlFY3VhVk5yTzUkLVA9Kmk2I0khZXNRYyQK
enY3Tk4pY3F+YUQ5UT9pSV94KVphUl4hRGxENVIoOU1JMWdGeCtCa1RnOFE8TnQ/fkVvX2heJigq
UVh5PUpLYHY3Cno9eWF3JmV0b3BRYUJ0c0EtNig5KkRQfGs/eHVUIztYbV5+XnJFOzVac3VNd201
PHdkQGYyOzdOJUczYFFeZFJFUQp6Jn4mZC1IcldBd0lWJWp1dmp7eWBOb24pYHdsXnBlQzwpUm9H
P1VJZiU3dUUqNn1zV3MqPzthQFoxOX17TkskI2MKejBlOD8lKUYhK0tvTW9jUz1TVnE/SGZxMGA1
cUthSGxQYDlKa2Jkaj5aYWp6VCVLOyZsaU43VCFzP3otPGo9UlhRCno0IzFTbSEtdnoxVklnRWN4
VHgrN1RLI1Q9Y1h6SWc4O0Y/fDlMejZqTzB2ITc0Rk5rUFEjJUNfek47anJmaTBWTAp6ZExuTj1h
SDZhTz9uNSpxXjk4cG5zLUZEIUF7UzwjVypZdjV7aXh+ayNqcDc9OVZ5QjVxY0Q3PDw3OHQ9dXNR
UmQKemElYUBmMV9reElYUktEb0BvWjR5Q1dhWXF5X1VBKSp0SW0wWH4hVn0+bzZmPipQbzktc08l
Ymsqa1ZsSkYhdXAzCnorTEE/QEJ0OE1ANCtiUGdISSM5ZCh4QzYmen5GNUhWUG9AYWBjejxRMWZg
dUd1Y0omUk8yeUVLUGJ2Q2V5I1ByKwp6eTNIeiFMXjJPPDsjUzktYXtaRFQ5VmN2Rlk/emRwPnxI
fnJsfWYwPj5jX3JHWntTXkcrcVA+ZUdid0JLPWpNN2QKenJMdXtuPGw3P0BEdW1FRXVvO2BqUWl5
ZT5YSHY5QWBLSmpMR19LP3ZES04+PW0wOHFOfEk0cSZRTX4jTD9tJGttCnpfK3pzM2spZGtLeE9+
RUBTP0FOc0xTazA/MzdKMExySTgmTll5RSt6TFVGbHRrWUAhYTtqRGp4MFlUdyVDMX1Wagp6c2Vv
dWYkWSExVG9BYDt2QGpTT002T3FzcFpYckhKO0FXflEmI0huVWY4MVVFZHNiZE5LQzElWGEkUVMm
cElTIWQKem81UHw0Zk43LU5iVH1PPkFAWUZSK1EtVjVTdyZTc3NMVUVXITh5OVhGVl9FJTxEMW5P
UDU1cGshejNwYmAmLVZfCnpsbWFYTyM7TW9CRkJHTl9LOWUoUXcteEhzV0R+O1RBbjVXYDhhLXp+
eXVWQ1cydmpgOyZXOy09NzJ3WHpLNzs0Xgp6VlZuVzlSQnRaJFMySj4+UGtvNyMjZF82cjQ5bEB1
MzIybklfXz08TVlGPGZVQk5eUWNrYlRBJjxzTjEyIWh5UkIKemo2OXNAQ0lxVG5AdFhtd1dGPWY2
UDA2NyZZWUxSQ2huJHNSP182TShIMnVsSyVZb3BDSGYxc1M1U3VaQClIUGRBCnp5JDw/KCszUUZL
VEM+Pn1IPUBJclhlfUNzWkIlSl87YEBKcHtVSjVMc1ktRHhVT2R6PypCRmg9XyU0QzloQ3NrdQp6
cVgmR1JydUtIKT1lR1R1b0gtbEtTZWpkK0Q+eStVQy1kUDJldT1UZEhzQTxDO0NQcTUyQlhFdj8q
WXc+KTlmUH4Kems2WEpEPCErb3BUQENNOHRRPEc7Q15za2NgUHUwJXM9JU5NRT5TKy0/JGxnODEp
fFctUyhVbmN7NGI8OWgmX3JQCnozbzV5bkxBPEw4SU4rYUZaKClWUHNqTWJGY1NEdU1Mfn5Rb2ty
WVpeaUY9O2l8MUg9IUxySUpgbVR1V0JoTk5KKgp6VjgjfWtoeDY4ZSYxTUhjM0QoU2JzMW5idDtO
Tk13aHtic3klb200VDlWd3VNT29jJklCZEpSPFQtZnd4cnhPc1QKel56TU82MzZ7UTMzNkBMKWNV
RFVybUdeaUYpJipIOGszJUtvKShVcHYoSEMzYHt7KFVEYFIhVz5mPkwrXjRBU3pYCno+dmhqNih2
PnlyKi1SK04hUW5zV1U8e1JJVWJfelgmN3Z2WkdQNEk4JT99SnQrYGtGSURJVU1rbkFCYnB2RnEx
bwp6UyFrPVhLIX1MOXZJU0E0eCp1e2poVFVjMGNLem99S2JkNzBvXlBqPVZMQSVJVmRGTXxQRWJt
NGtMeHE0c1VXPUEKelA7fT8lPzdmUyYhQm9EYi0/RGBTR3NZU20tK2FxbzFFWFJqP1MkNj5LZSs4
Qj5AWF5Mc3ViPlgxZjxVa3dmM1MqCnpFTTF7dkopRl4hSnw9QUZOYWNxUTtEfiUkPFBEMkBUbXYm
RGpOTjRJd2VCJVlYQXtyJUQ5QlU1REgkR3QwdzU/Qgp6cX4tPWtZfVd2M3REVz5mVCFvbUZtUjE0
ez8tYVR4ZWlQNUp0QUU9KnlPYiFET2ZMayh3JlUmdFFofCtjTGEtWmEKek8/dykmQSl5Wk9sTzEl
LUZhJnU/I3JSKSotPndxe1lkU0o1QE1EVm9OTTdFdTN3YVdFYlZWQWM0OVZ7K0l9UHY7CnokWjhy
dz18aEViYTR3VTx6ZlBXIWk3bEo9KTlffjljTCQ/aVkwYk0zc2NvSyk/cnBIK1F+bnxYMmw0ZExj
IXZQWgp6NShkMmhlMnUxKm9mWTkwdnp+LV9SU0FxTTJMN1hBK3JJZzBQVlkwbkFXQ0VkZGkyfDkx
fGdAI2hXPipNVHR1Xl4KelZuPDdNIX1lZj1DNFdEYy1OaCsyN2clNHMlU15HQUM0RDl3YGBPI2Bp
KiZMdUd2Z2E/YmJDSyZQKkhBfXZ+TXA7CnpDd2tDPjF7N1FNakBEfXwoeklQTSEyNSlCQSVyYz4+
USRXRVVxNT9gMnYqKnw4QCljdTVePzdHTGR3dHZGezZFQQp6MEJkc1VtQWdLaVNOXjgjZSU+fHhS
SCZoTXZoUmE+KzBFTWwhPCFNOUNFPzc0Iy1zRW9ROU1tUzlzSEIqcy1afTwKenxNTEtoYm4tWCE+
dn49X3F1RlpNdnY7ZEpkVk1yKU0pc18ocS1jSjAxPHpwS1IlaWRsZDZic3V0c1kyclFofjVnCnoq
V0gzbDJHWEFvbWl3MVYobnZuYnN1VkUmKUU/aTdDb2MzPSNzPzJ3d15MbzZyfjJVOVQjb1IyYzM/
NkJuSFQ+ZAp6PTdBVVdRfSROYHQxMSYpPm52TCN5IXs7VHZeS0QhVD1odU4+MjJSRyhrPH1TOTZ5
XzRzWDc0K245QW5lPFFISXQKemAjNk9MWSp2e2l3SUpuNTFeNWIlPG04ZXBKQUVLNVBRTzQmcDFO
R0UmRlN9amNHUmRwI1NZPl5jcDh6XlZ+UHE+Cnp2YWkoQWQzLUI+PC1GJHEhWV94dD1WKWRyeH1f
YkdvI0FePlZoREpgbis7NVZmWTE4MzlAQWp5NEg7MntvdWFaegp6K0UxVU1CcHxpQ1dPKHgldzlJ
X3UtNzRrLVBzOFRAIzlMfG0tNjl4SlFARXx9MXdhaiZhVipEPTdAfGNIQlBYaH0KejVMS1c3ISVm
I0Mwd05idHFIMjlwYzJXRFFZUis+NWZoc1N+O0wycCZkZFpgYjE4a2gwPjJARyYjeXBeMmRFeXB8
CnpKU2pEI2t4b2NRZjl+bUhOSmgrKDJ+KHEkc24yOWtKbEEqMmFycyNpZmFHYXRRNDdEQGE8cyFN
T3JjNGhoVjErZAp6I2dgc2tmWng0NWxXZkw9VXxLT0I7Q3J2SzElU0ErIyZRJXl7QU5IU3lHO35y
RkFqVURxUjM7NHJ8SkwqIzxtfmQKekhpOGtUSnAjMnFsND9xPTJfWVVnNnN6OSlWQ01kRVQyK3lW
SXg0aW8kYTgmRVA9YDlnUTMrU3U2bVF4RF5GbmBKCnp2cGtUJFpEWHl0SH1oVnxLe3JOOGB9UVVo
OyE+WGp0bVplUHt1THZZVkFwLTk/azhIdllhcWB7cXE+Qno5ZT98WAp6Ui1aMzJNbjVEKiRKZSM5
MDtaeD0wKEMxXjxpaHlTbzFmNDNIOUNIdGBxaXk0b3N4ND5rXm51VUstWVEpdnw8IWYKeko5Y2JQ
aiErVWAhdHdkbEZVVzI/fEFRcW1nKn4qQmc4bXo3I2wtbSFtODleNj0hIXVJPzdeaExCeUhedkpI
Pi1DCnpFK1dXVjJfcUA5TkhYK0BOQ3x2XikwUHhXME5BY1czSEQpfVl1NnB2VyRUZTBeY2MkeWsr
SXgpaWQoT1ZkbkFwVQp6UkBPdzhXKnpZYCF8WEplXnh6QG4xN31EZz9ic2I3Y1NtUzZkRmBxYUYr
bExxTEskMG9SVjxDQ2M4SyUya3t4eFIKek0zQig8dlU9dDYwMWBQQSUzKS1SaiE8aS1edz0oYTJC
KmVHYD1BXktQeyQ2cCowWTxMVWQ3JFFQNXNFPjZqQTZDCnpveER2VFc3KCk2cFE9YTlPUVFaQEU/
QzlqJX1XQSVfSiFiM2M5P2xRITRjKlhEY0o5eHU3eTcxcmQ4MDRqJmlLeQp6bSlfM1BkXlJXYys+
Qi1DcGZ7fWpELXx1aGklSiM3OzZIUjkoVnlYNlQtakw7eGBSRVU3eUJeKXVwWEk9Vz5PPXAKemRL
WmBjRTJYV0hLXlZzZjBkbG42di1vOT5pfl5yKVphNVNmbUgze2l5dzk5NTI2LUwqPktWNmp7azdh
MU82JX02CnpvLXBMPGE3Q0YtPmF3I1dVfT5DKSFYXlc/aXpWSUhCZTttSEtkaWNEbilLP3NXYjNl
XjcpYkBDPlhHJmFhTTx2TAp6XyR2PDkkTWZfWTk+RDxzI2FpT3VkMm5pdUMlcTlqKitGOEdac3xt
R158JndAaXZZP2M8YlFeMm5oaGlJWDVYQnoKejcpPEY3a2tXbzh1Qyg/bihjYzNuXlFqbiVHWDFR
NytoS0dvWD5HandUYzxfRkJ3RUN4Xmg8YklQNyF+K25JN2JJCnojan5CdiYoaz5rU19OQVdmZE5S
TT5HR05AYkY1QkFreHprckFuMVpFPEtNNUNLJlZGfHdtNHZjNitAQmRkb1p0bwp6aVhoPy05fDdU
d3cleU9AOEIwdCp2TXckfnhPaks2TF5jPWN7M3UwTWFoeVg8V2RUb08mZUh7ZSl4LXVZTFhxSjEK
eihGfj5oKFI1S2FpV2g/WF85MUdtKFA5VHQ0T2o3IWd6c2JeNCZAWG9BNm5IO1heWk9FRkdTOCti
I0c+cUR3P0leCnp3JDg7fEA+aWtmPHcwQGB7XnhzU0xRanN0RyhjT2YhMShNZFZ9ZTBLZFNgNWpF
PHt4diFHK28/Vy1FUzY0MUteZQp6SXojYV8wP3N4TVMwUVZtPHRLdWo3JnMyYkFoalEkR0smUVZD
SCFaJm1gMjlCTEF1U1Q0RSRmKGtITkZme1FYJEwKenhXOSNsVyptY31mR05LaTVQKWQ1YWAwMmpe
fEU0JHBHZzY8SGdNMmMkJSQ0fil6YSVmTkRmQUhUQH1kO0dZJXgqCnpxIXp3JW5Yez0qP0lLOEco
MVZoQiNPJV8wR1g8TlMmNS15fmNWUzNjRE9kdCFJVGA9Kj97QTtldX0oQi1LRkNTMgp6TWQrWWIm
U0ZATnlKZW0+a2VfR3I+YmcreHMmPT5iN0B3QnVhdyo1R1ZFdD90NzxvXlk5NT5MfVUyZ0dUPWVE
cVUKenZ6THNiMCZBa0t6MExwKHgmaVJXNFBPbF9kcVpUfWg4K19CITleMnZAc2YpeTN0VFJMWEY7
aH5RWHt5cE4wMHBWCnpYdyVqQTY+c18kNW51KWAoK2d+fEF5d1FGbTRzQFdoamxsQWo/fnFCZnFL
Rj1TN0gzZyU4VnNIeHp+MSRgcX4pPgp6P2hvfkQhYDF9az82ZzdgU3lBTnVsbnlkQFpOQDVYXks8
TFIwS0BqSG83cEVFVGxZO1FKeyZmNDBJWEkwKXs9N2sKejMhLTx0SztkVypjUUhOWDZZI24/WCor
eUBUYDwtWEVuQi0lOWckeGBYKnh7K29ScUYrcHltbXk0ZFokNmN2Vz92CnpmUWp+ekJhbTFMbFVh
IXpzTTZTZDdacDQ3WSRyTEpoPnFMUyskQXZVI0JEJGk+cTNwTShwfi1CYmZmSlg/cjUybAp6VDZL
NTIjLXM+Q0t6ZFU9eikmbD1wdGghdGtudXJrbXtCSGc5MHA8NXV8NTw9QDtkKkEhS2A4UldpSFQh
dklKdi0KelBVUVhKMThBcHp2bil6S2BDQGxHTnsja2ZRKnlSSWNLUkRQK1koWWlzVztzRE18YyRK
LX1vQ0ZQaDxnaUJ0MGc0CnpGeH0wZWQ5WUJLSWVrKkkoQzI0RHg4SH1qUlF7az0hZnJ8alBaMyFk
O2hqTjVudzJDK1dkVzJsdnRSe2Y7R143egp6JmF6NTRLfndlUFhaKjtyNyROYjZpTUV0JT4zQGY7
eUxLZT8hUWFodVlOUERkX2Nzen1yNGN6MWdXajhWPzNucTwKemlLbUFtS3gwd2AyMjRNayMjVFAk
NHJqejdqNzw2dnJyansrdkJ6NFEyVDN9VlNyfUBldnByO0ZCUmZmVGNnVHBlCnowTF9yaj1vSmdW
aGA/Oz4zVjNScEJZdTV8JnI9NG0/P2dfaTB5dWk2Vnl3UWRaeXM2dTFwaHN7WGImQVEhdm1NSwp6
TCglQmBZeWIzY09DM2wtI2pkcDh7cXZOdS1FWkJrRGptZVMqTD9uZkpaOD10UypBQko/RVNmNE9T
JGh8PU5GeCsKekghZWN4RCVhSEw4UWUtRFc0OV9SV1pHT1J7Ry0zZTA1UihYeyFEaThJe1pGSyVv
TkQ9PVQ0fDJMKnxLR0V0fk1PCnpPY1YpIyk2TUVweDYkYnJacHFFX05JJUMmWF4lQndvJCRnKVNX
MGU9Mm0xQU1aVjJzeGpNMDIhOGJjd3Fyej19Vwp6P0pSQ0c3Pl9OU2MydDZAaStwKjY0Vlk2WGdF
WjJVaFpvKzNMayE8N05wPn49byNBcEJBJntBS1ZUekhOZUxKfDwKei07TGYoI3drM0RvOTJ6ZT1E
OVdOKyN6dUw7VEhtTnAlWk07KH42ViZsd21iKFdnaTNYZHZoKjkxK29CfU01Zzc8CnpOOV9Rbz9r
d24/aHkmJXVYdF49WEd9KVczTF9RNyYjND5+WEZeSWxSMjxRNm1wSGs4TzF3Vm5mZHNPaCV3dDgy
fQp6RXFZS3s5cVQwaTw3JitUX0FqY1VDaCpkeTlTejIhJV55YGVpeTlPYktxST1zakVhKjxeSDJh
QUYtLUo4I01DJEcKeiZnciZ2VjNebCo2PGsqSHR7OSRxS3s1OytIMlBwTj9USm55e3VTZDM+Qy1Z
O0tVIU1UR3NRdFRDMjx5fURiK2goCno3cU4tTHlkSVUhODZaNmFUZWkmI3k2PzVySGpiOCMhQUNx
fTMjM3tTdzhEcClBQmZBPGgqNlVuVUQ1QSM/aWt0dwp6VG9TbkB4JVNfanhsdD0wdF8hI01FcFF+
OUszKGF1I3hQUURGMzU7SDhDKWNLcTtWPUNfbGo+amhrbE92UUBoV2EKellaezEyPSpkPTB3MURE
SSVqdiskJGMqYzUoSEtKNzdQa3w3JjdLcVN3e1JfQVkjbCh0VE1UUXU0dU9ZP0xuI2E7CnplMEQ3
dTc/c1A1c3YqZjVvNWxabl9tfExCdDI0MWNMZFF7T2l0JTJiWX1YZSFpUSpXK3lsUyM4ciZoRjxD
O0h6Nwp6SCsxKHUtbVRXfW5MaWZfNklhZmJjNlY7OHBNUjFiaVJAPl5hUCMtd0dmNFMqbyNZZ0tN
WVNLREFKblFSdG9venIKemohYSROQXk4dkEodXBAWHtmSSNAJH5PUDM4PnYmQHdWdCQocllLT249
fXdjSTdJQmojKnY1Yjc9UGh8WDt9NkhOCno0MVdPLT1vTWlNdDUhU2ZqLUNeYWNBRjRZYysrVyhN
VG5wRXZUd2BqbWNKSEt3PCg7TnpPczlmWUoqO2JZJURlMAp6Yj9UZXFlQ242TG89Q2pKJH4pfX5Z
aj1obnE9bWpIZURHb2FXLXI7e2g/fFB3aXIkNW5uNG9LR1QjUUFDWmVfJSYKekN8Z3dmcWhjLU8x
eExFUCkpWCR5WlpaUVU0eGkpPjJGNyU/Rj0hPnNZc3lKXyt0bWhALVcyTG5CViRyJkxfKFM7Cno8
aiZCWnskM0gqUVZ3ZippOEh3SFBCOSpEK2IrTzNwOSRzNil+IUomKy0kczdsVFE5O0tYIVlebSQt
MVpkeSMxcQp6VDA/Sl5NMiROWG1UTmsrbFQ1Vy0tQH41fTQyJj9IcHxFR2chZHcqUXUrTj47anFD
YnAkJkh9UWVAKUxCTHlPWHQKek14TUJMY0I4aEw8ajYyN09CYmxVb0hGdDlDS1EobDRmTnVZTnZu
fUlEaURaMnVEK2N7SV8lYXs8KjIrYExhSnR1Cnp4LTxMPEh3M29edmg+cHFSTHdHYDgye3FkUTlK
SEQ+fVBsWHtTJVh8OERzZFBpUTl+KF9ydjs7SD5WSFdCOT19bAp6Q2Y9bzxeLW5DWnVHcS1CUCk1
aCt3fX00Uyl6bipUQX1fQWRJKXFOUVJ8S1Febmp8ZUZnYGY/MlEzVCVncDwzQ2oKel9fT143S1Ek
fVlwTyVZKnskMCg8UE9ieWg0OzFrSyNrTj9ieXxMWVp0XyYyKndWMFdhQjVKXjRIQ284dkxkQClz
Cno3NDI/UWEmUGdqRT9ZaFZTM09zODU8eXNBKUY9KFMoYjQ2VT55KF5pe09KNSt2SkgtSmRuM09P
NjliVlYxaSZHYgp6QU0jZzFVcC10JUxEIyk5akNBbWFeJTJBVStrXkA5emV3YWhoUkhsOFQ5O2g0
U1dad29xdGxza2RnJD9AYGIhdTIKelQwWGNNdEApej1seSM2YHtBTHt4QFlDTj94OHdpfWp9I2I9
bHo+KlRWKVp6XnNpU2ZFLVAjN25SQEhjQkxKfUFPCnpJP2IxZip7MkN7P1FnaD13ZjN3XjxadUs8
ZGslPjBzKHt0SkAlYHZhR2BsfmlxflVSWVlfRDxgVihFcURzfG9MWgp6aCs2UyE9OWlSOFBkVTgr
SDlzUDZWKmYhbHJyITtGPEc1NVhvWSE8dXNvLUFwYy1Wd0c7ajl1PUJYWGlkMzsmJX0KeiZibjI1
NH17c0ZhPSg5bGBZdWtzTkh9bmFuflVlO2ArfmQ5Y1JgIS1VQzc+fGhUN2x6NXJNcSk0dFBhQDJ4
ViEhCnpKbmQhT21XbFl+PilZKUJBRjQxVk5nTUV8PGB2dmduYmRXSWoqPHg9MiNafWpuUy1KJmg0
MT99VyFJISMhcTxBVQp6UDxib3VsKGFxYkFueXMwYyZKZ0R7b1ZGa2MmSTY/QGxVPlooIWBUa1Nm
bHtCdWJiTkE9eDV1ZkhzMSZMRV5Cd3MKekc8SDFQcU9mUWNgb04oMFYoSmU+WmFEd3BhKVoxbk1N
QUdXcWFCbFIkPTIkaCF4eFdNSExhOTE0TGcmJG5yTWwlCnp1RTtNLVlMVTN7VW95bThgdnQ7c1JQ
aDNycXV4Mk01TTkjckxlPW5VT05JTlBrJXkqTHtaKndAJSRsUElHbTkmUgp6e1Y4T3BkfE1qY05E
MDA2JFpCI0JPIWJrOFRCd0ZzcjQya1lMRXNrKTMhSTZgJHBmcnw+aXkpaShIVGA7OTBjbnsKekJi
TXYmOS1FXz5hKzZudTthXkpLXn40ank8OD5VYXR3JmJnTWg5P3spak14ZEl5V2cjTHo7dk5ZcTRH
ITxTZFlCCnpDZ310Z1RVSS1hPCMyKkBlKHtEPW04eFQtemZDVldJfDQ7KE84VHxAenY8UVJgVGNJ
QFdAZGZXTSFhMTBVbzNRTgp6TUU9MGA7bz1ueEd4eDNTaUxEd2UyZ3g4TzVBcSl2YSRBIXJifEw4
QDJyZm8kPiZUZjgjSC00XjR5PEUxbVNKOGkKek01ITBlIXNFfUxPTHZFRUpKVnYyKGdlKXUhPCMk
M3opbT0yUEtwZn16a2I/cTdkMUwoTkoqPX1MezkyZW92UUd0CnpucjdUfU1KOStxbmFhdksrb2Z9
ZzY2OU5tS3hBZ3U3YXdPKVJicVlUcz9ZWUUzKj1WRGkjfVQzVTd+bWEjbDNRRwp6Oz41U04jOUVu
YjxpbVlDMHRGM34lbFB8QGx2WTYzXyFDcEpKeEo4IWJKY2dLUDMwUn11JHdAO0hFPFQ/cXEqV3cK
eiZpWmgqKThuKml4U0VgVD9AO15xWE5DQzBNO19hNzZLclo2aXlDfjdabE5iJUJSIyF0ckYyWiNx
Uzl0N1JBfHNOCno0XyNlT0U+Tl5SK3NTb2k5NyVwZFdIS0lWYnN9dyVUWH5SdVlqdCkqQ01DSz5f
SCg7NDQ/ZD5TSntWO29ge1EyNAp6I2I3N1ZgVVlFTUFQSUpIPUg4JipfIWJCY2Y5dy1eQF5tR2Z7
MSp3dld8c05RdElXa2g2SC0mcWd6UmE8ckNoQH0Kej9DTXZRPjMpNXFONF5qOUpFQ3goOHNONSFa
VD0pQGh2YzIpalotNFJvOVJpeWB4JS1pdnY2RnRVIXtKJSRqKXBvCnpzbjJ8MUg1ekY3UFI9fWBt
Q0RyO2d3b0dKT3sydD9FTUJ+OEE9eygwZ3NDPn09XjhOVXhAeCpVLVo4S3lzenEkMwp6WWxPZjZ1
WitoU3FxSmY/aVhOUzRgNS1KOXN1IXhyWVFXVTBAfXRofVZeO2N3I2gxb0olI1lZbjhVKDVHXjEp
SmcKeiU7UjtNQHJJdXxNMiRIVEd7MEpYczx5RipYMGI0TWl7WjJCY2VtVW1DfDBpbFU5KXc7cShH
Zm8kfXg/NCpYOHNTCnpyMiZiP3l4LTxUVXV1JUY9Km9GSEY3KkNkZkJkd0ZeVHBAKXplJnFFODFp
YiZUQ3A7WDF9O2ZeTD1zZ2sme1VlQQp6aVg1Tyk5enZHQUVRa3Zpe2ZGfUJUKml9Qk5eJn5DK0pz
alBeTkwjMk5TPztPdGZFczMrODlqeXBJPX0/KnRaRmIKektDVClyc1Qhe2lLWDt9PVpsUTdnNEQ1
dXg/cUlkdmRDPjk9ZEsxPmd1SWYkZjRuZylQXmktbEZHKmBNdVE9eH1rCnowV3Q5REZeYTtCO3E1
ZU1TbFV1dDxyWiolSVFBI2JRSW5SM2g8QGd7X05ZYGVIN2FEckpWK1Emc0tpSjd1Mlo8Wgp6MWBP
TD9MYEUydGgjT3FjTm13fFQkJSUrKm0tV1czV28zMFNTeyVHdTsqVWleIWBCOURNR2h9bil2RSg8
Xyk9dSoKemxzfGpOWnBgMWlERUpiSjZmZ0BwJV9MQHMmTyZYdVU5cWRaTWhXSDtgSWtxRjMmY1NG
ZjFgSXxMdkIobHV4YHFsCnp3T2sqRmdeSztEdUxQRmtWfEd5aFFhRGtaajV3NTVvS1UmIXdAWUp2
YW05QlV5Wj0zZ2NFYFE0IUBOPyEtTF52Iwp6OzJLan4qU3tTdUg7N0RwfEl2WnF4ME93eWx6OUBo
IypiaHdrNCR0aWBvMDNucD40X2A9d35xSENwOEEmMnRCZlIKenlmVFp+PW5tPEtVKD48VkNGbkpS
e011cDdiP3MzJDE9SipCNzgheTZhcyMxPkFxMHxYTiYxZzs2d0Q3ZEY0a1p1CnpsQUFrJDJuWUNu
IXt5LUdzUExKT3AqdntkM0R4ckJXKSpAbnJKOy0jMn5TPWxMMFhYJkdnKWI4V31hMEp5TlkhZwp6
ZzJ4dWJ3S3lVQzEtNiFkKl42MVpKYUg9QVdzZXJnMDB3cl8kPkRzfTd6aUp5QEAxQ21pQVJKJms3
bGZCTV9NQXsKejE/P3hlP0xVdmE4dztPfWwhMXdjYntlUzhuSiZKJWNaQUMlQng3ODx6eF4pPHR3
ezQ/SXQzR2F4aVVpelJjJS1LCnomUC1ofF9QeVhuMWdJJTVxbV8wRmVZMXh1cWIlfndxRyNIeFh+
fTJeN2peYHRne3olSTE/P19CRDw7T0xVe1BoUgp6dWhmKH55QDhxUmBod2tDXjgxZkUzRUA0fHt8
Mi0/NkNrNVVKanY3NSM9P0RBR29VNn51OU5iJlJudyFMNXVCfSkKemMkKjhNUnV2UEo9N24oe1Bo
UkVrcjFGPCRFeERlMWZsITstVHB4ZiMqdVlgdFRNVTRuamsyWHYkKCpIKzN7bHdICnolISo+diE9
YTF1ISolaCVwSTQqZEcoaDQoJGhvVWYoQ3NfN0xHS0Fzcks8fXY7JjNUfHE0JTVOVWQ9SyNtZD94
NAp6aGNETyhFblU0QVlxQEhlemN4QFheMFopVkp2eSVgQ09vRV9GVlRkYmg7cXNaZUp2KWpIJEU9
KkxkXmpDSF5icjUKejdCeSh7az1kOSVZTD9jRitMNXBIUVFANTh2b35rIUdOM1RHVHpiQCZxaT05
VzwrK1hTVi1OOFMma04rK0FIZ0k+CnpVUz1fSlJVJFg4Njk8X0pzQTg2aWtOdTItTj91SUgpbG4/
ZT05dV9xLU4xbmR1WDdyWUxeNDBHVnVvMjZiMG4qKAp6PGlLdTxHcXszI0h6fVckT00+RWo/fHho
RDFDcjNoZ3R2UjNJWFEjMSRSUkhrZzd0M15oMHNrRzhYTkBmYDY+cCYKemNTdE1JTlpKT0VffWB6
bUUmVEcmOTw1UntRYkchbihWVTBXSW5+TEZkSzZ6ajJjKWdKST89d3o+d2FCenpmJDNlCnpJYURj
VUxAcSFmKVBAIz5PaVpZaVErfl5qdjhAWV5wQyopUiFeODxTYzgjSUhhQHcpIT53c2R0eXpYUGdo
JHF4cwp6XmR4WDltPn1VTjRNckJLMn09d1ctRlBJcFo0SVdlNihVKkVuWkd+VW5wLWkwcXd5cjd0
NnE/bCYxTGlKMylxIS0KejYwPT5DNTAwJkslMlIjbG5ZcWtwRUw9bUM2RSojUT9RZXVWXk1HTXYl
RUhXakUpbDJaOG1ROyNpUjRTYV5JbV8tCnpESThwITY0WnsyUnZ0NShsM3o3bTkkemIzIT5gWER2
Snp4cDhBTEdgYFA0YERzWlVnbFVnbWN+d3RLI3NGajFUUQp6d3dlLTJSZnQrNTVTRXdQcFhRZXdB
Y2smYTdnKkQ1NjtfQjA9Tmp8VEg1cDNCblFKbmVXOyU/YWRkam42QDVgPGIKemt8aXw7JDFBYjRC
JEpiZT4pcjkodkA4fnA0Uz1+NHBrTWJAWmsmalJRfjJ9RTc9OXRGXjhVUGV0TSpxTXVmWj5rCnpe
NDh9VGchKUF6X051ODllPmpJe0VWKnl0aVR5a2pHY2drc3JBVFo0VippI3UlPD1FX3c1ZWZkVEIh
XiNWJiReNwp6Vk9tYTsoeldUOWh1Iyl8akBqbWZwRENFXmJWQlcxSDNPe0ApcHF0amBGdz5sMjt1
N0tqd0UyUT1QYktJT3NzX2MKekN2QXkxSktaaFBVMTMmQEE7WlolIXsxMzdeXjMteEUqbGtEJUFR
UkFzMiowTUM+Z1hmPk8oNU9MKDRfVDU8RX51CnpIPncxcXYyJWImZ0Y1KERmcHVYK1NDQi1GOTFO
MnVKUGlqZVppQ1YwJnkxTkF6TnMqJkIkeVhvVEh6Q3wzK2Q9UAp6IVRCdTdmWiVXTUtUfVAwSXdF
fnRRYDlxWmZnKD4yZGEyO3w+NiFHQ2cpaWM1ayoqUio5RXNOWDhlPzk3RVVCUHIKendTd3dvKmY2
c2dAOXJZJTlefF5jYGwtLVQ7UFRZejJzcFlGKXl7LSUkQHxnQyQjNiN5UUdRdTdtVTliVlFnKE9g
Cnpick1OUjU/YCo8KiRpKkhYYmwhd209azc2MT0yRm8lQWpmbWZjQGlnXipSKjdpRXFnNFYzfWwh
YV9PYEchNk4mUgp6NT8jT0RjNTg0ajA0UU9iSjhpNjAtbl5nVHo7RGYrS0VvQGExVEN6THZFdHNr
YlRFMHk4MFJjSXQyeU48aXdmNkwKemp0SXdCNk0zb15YPndmaFZAQ35ocmFIZUdxYSh9SFd0R142
VjJ9eko2KHA3TSl7RVVzeUBVJH5mSEN8MnRqXjhlCnp7TnlMVz8pclVsSE9BQyRTOXhAdnstOG5o
Z0Z5MHZFaWxiclRpMkNyYzI+O1VtX0FWfGl7ZWN6cnpLUi1nRmV3NQp6KHc+N2ZMalhvYF9yWEpi
Zml9dERnNmsmNUUrJmxGYi1sTXEmUTcyO3VjciFHZzR2XmNfNkw8Nmh3VDM9JnBicjYKenlhcWhZ
cytxVlNxX0E7aERRTXxARTUxXkttYmpQcFBeUz9MdkF2KUQ3K1VEa1g4TXc4MyZCZDExO21JLVZ5
RkVMCnp7KkhFeistdWcwVUh+b1UzPHdYMEh9NEtjSylYUE97Y01APUJ0YkA1PVVsbjdgPSRLNzww
blZCYD9kbG8mSVdUYwp6aXw0enZsJHlqe0oleFZUYHxCR2Q1fTElSk5xdHQ1KXhOKEAqeXlOVm1+
PWZGMVNONFdHRi1AT0FXfWlWKEZoYzsKelJuYHY9MWR5Q29HeU1pRTZNYiZLRWxMZHA5bUtCbEhU
YlBMcWhJQGM8KVc3NlBxYVImcklYK3NPajFOVlJxNng3CnojcUxpQ3ZBM0tpVCt9eC0mQl52fT5j
V1pVRUpjUWcrY3xKKGJGe3RJVWVKZDFvYVRsUVBiN3lReD0jd2R6aG53SAp6Y04pbVArSm05UiRU
aUFMYiQpWVk2az9aflp3dGtyQDgyKk5rJDc/IWwkcU4wWitTWUc9alZTayVwVSttYk0oVS0KemJl
YjkoVCRoaCp7OGdFKGdeJlgld0JhUmo0WGhSX2dsO0JtYSgoYVJ7d31+biVaRC0wKHZwWCZVJm89
e0E4d151CnpXalg3aGVqTGVWWmotdEJFV2Z8MCVQVDdgNkhoOTZMcClKYENROSFjYFBEP3U+TiVL
LT5geGhQQnZMe01ZR0pZQwp6UG1kZlgrSGFPQGE+WGU4QGkodT1hOVBiX0I/OSpYO14rJU9ZI3J9
bE0zK0F8UHhBTzBWa2hsJlR+cTdwTDNRRyYKem1yKHRrN29NQTVANm9yKHl8R2EpV3NhIUF2VHIh
b2tnSmZCJT58eEUxenpxSms1QE5OPTxnSyo7JW8tN2AkP1J9CnokYFc8bmM3d3RLVXNgIUBLdk9G
WlNWRCE+TnMqPmtrdTJoQ1lpcXt3dzVYVFI7USE8cDwra2tJdHcqWnFPX14/aAp6Rzd8eUNGXjZD
bHJ3TmtPQ2NFIzVidVE+S0tUS1N3UW9DWSkqQHk3YkN6YyU1V24jJWwrPDhMY0Faem1OZGNxVkUK
ekNtOCErY3FnIVFBKFJDbyNXQGxAdERuOF96ZlY3eWwtKXwmcHhMfTQ8NGQzK2xkQmVtRyVONXNg
a1dSaW11Xml2CnplLXNVKVM+QTtnRCo5Mj95blQlfG1NS3Q4VUZCTnczdElHeThaSjIwP2hCPkgq
bUt8fFN4WUE3MT8hSVJxWX1MLQp6NjFAdlkqWHYqUF80alZMVCY4NFk5ZnZjI1ZEZEBjb3ZiPTFD
I1VfX25+OWZ5OU4lNytZJUdDP2BKZk9RRWBWSUUKekk7SDZRWXJ9aTEtT2okbHdxVDwmKEBxRlhv
UTwkWGNzTkZJY1pJbWBULS0oMWQqP30jN0VZbH1FamhPV3gzanVoCnppY1otKkE/V0c9PFQ2JVVM
QEVePmVxJDVpRD5eRyN6e1dNMiFuU2h6b3h9ZnBFbGxmQGhnY3pfKiZXPEBKTSpjagp6WWQ9R2BE
X3xzSEFtQXYpZF8jVjlDKjI/YEpaJkl+QFdENz4reVY0WlIkakZ7MnlfMlRmJlRmK2N1Qkk+YEkk
NTUKejszVXhOMVFjajluSW8xekA1Yz00OGsrcVo/akhNZWIxPWx3d1FjU0V4LVpiPmAkPjM7K19o
ZFQ4Rm8kenlWOz8tCno8Mj43WSYzOGZmPD5oN0NLcD9pQCFBQ1NLT3pffVdObDkxfnZgMj5tKzk+
az9wO305anB3cW45antGPi0ySlUkTgp6UVhSMC1AdiF6SEBiPm0qNXNsKj8xMEhmMDZtK09PSzA0
QVF0bXhRO2xZa3Q+TEZpKzUySndOKSstSU1+Z2pwb04Kem47JXduSnw5MTwxMUFHT3ZrTSM1XzQ4
XiRfWVFGNmxSLSp5TS19ZF5CXyNeO1JtTHdIZnpLNTBrZlB0QGVFZCU7Cno9fUU7anFQayR6LXRM
YjM0Mk8tVSUjR0s1WFlZJmtMYHstJWpaVUBoOVUqOVFmWCk3N3U0JmgxRnh2VntBP1VxRgp6cUpS
MmQ2aCQhdUZKYnE5VyhEWG4xb1pOcHRaVS1nbXE3USlpelVnRjhrKEYwaHdJXnRMNyhyOVRuOSRL
eT40TVMKeitsN1B2X0NqaEA0cHZ3NzltWFp6VyowITAjUjZ7PWIzXjI5K2dGc3hHNDIhRkVaOz9R
SSZjb01wbkBnP3A0TzA3CnpjUl93RV99XnIxdj0xMUZSRXsxaSg4eUg3YyVNYEB2QS0tMWlDPWs3
aXIkPCRMPUU1JCtKYzZ8aFl+ans4ZF5JIwp6dlhmY2otblNVVXVpX3N9eXdeTkFJMXhAPmsreUJ3
cmlsfnFLSn1KWWBSKUEmPmVyb3NmQjt7SDNId1VFP05uNFQKendzN2V6Y1FxQyNLUi1Xdmh4c2Y+
aT1wJHwyO29lPyt2bk58Jn1OQ3Q/R3pYLTgyciVyKDJARmpZU1o7dD9xbXBACnpXWVNmKHQoK0J1
ZTtmJWFYO0M2enBvWCN2XiQ4WT1JQWlaNFltUyU4aDBjNUx1SUxAMip4dW87ZztebmNVZXU3Ugp6
YUYzNEhKPjVYdCorRXMlPmNZYXQqR2h1UWhRMjFFOCh4NzRnWXNaWD9WSjYoQjs5T304UGhlZG0m
eH1NRSZIRi0KekNWPmkwTTU0Pj9FPnZxMGN9WFBnSkZ6UGdja0BqaFB1MnslWnI1MUNaTmRhKlM/
KTFJS0JEOEg/aiFvZnQhLV9GCnorNVhwTTZrUyg/MD4pa2tZaEJPJUx8NXZjaWIwXlUtQmxuaCR1
UXd7SkgmSXJfK2h2JiZmakd5YzBLaCY2ckhSUQp6NGZQYnl0RWdCYHBQWFc3YjtFcEZXbzMrOSlR
MWlDZG0pP21yLSFjaDRpSFB+Qz97TVlNREpfSkFOaDN2NHZLVTAKem1nKyhePShPaEhlNyltaytv
REYxWSQlMi1OSUt1WWNaejQhJlMtUjdSPmNoYz9DZ3h5PSs5PFZxUG9+IWBOcXEtCnpjUEd6Uiho
SlNaNlpKdHkrKiFyPiYkOFVrMFZnNj17PHFVJTh5eVl7SVZfKXdFSU1fe3gzV21OOzFIQypGNUVv
Uwp6R29zM3A2bkliQVIqcVFKKTtBSEJNU1dtdnpwSX5CZG1ucyU+KUxvN04hd3tIdUZyV19PbWwr
T3FPRyFwYWNkI1YKemVjZmVIWkBaaCUtVDMycSgmIU5PPEEpa1k+Wm91ZWIoVEEwayZ6IyVoLSNX
c15+a0lkdVdUbWZiJUM2JExuVFRkCnpgZ2RzKVZHJDd1e1pAfnFJTWRoZGhLO0EwKVhyTyVBfXpi
dSgrWnJ4a1J8NG5fKlZlNUA2eTMoMS1PMmI7fHxeYQp6PiskO2ZNLUcrYFE4cWZ2JCZNVytMazI2
SEBGWWt5ajBreXkteFNtPyhrblRaY3UyOHtyO0RTWEtGXz4oR1cqb2UKejZJbCpoYXFyJGQ4N0w/
V14rN2smPzAkRnI4VDVLcjRjWmc4UkFDeDxpYjEhcFErfnd3K0Q3cyhFZmF4cjVQUWg9CnplMjMh
d0BmZUJSPVdASFY2TE4heWgmV2xMR2d8SkA7SFE4dSpZNnRMZlFiX3A5X3wwelFyc3hjTXZFandS
eVojJgp6WF49PTI4JFElcmt3MjRvO3M3blB3WThOekwha05+c0tIXmY+IWRGQz9SMXxLeG9rZjYt
I0wrZEJDemhoSH1lZFUKekdiTGFRSyMyQG56LWEkKzBEPkdtSExaRUFsc1Q+VnNXWVhyMz8re2lT
d21ZdGwqa207VCopNXZQTF5lZCFEIWh4Cno0VHcxYig8RXJaVDlLXz50QCFYI0FuWmBNQzshZVM0
TXM7NntPZF9KIV5ZaStRSTBQRW4rd1NLI1d+Yz0lS0M4NQp6bn0lMEZGPjFzT3U4SE9nMns9WnEq
TVhPa3RrbDUqcEZaRTYpT0I9cG5CJlZxbn0zWH1HaDNjcCNieT1oRSROVjkKejM0aTFwKT48am1l
O3Y7dChIUTs4PDRRSX1PVUp4cHlQTEQwYlR+QV9EeT1+K1RgUzBXbyM4SlBaJk9CO1k0cmdvCnot
WG53YTBLUTlMK3lhbXxFalp7e29FdjY/JHhVeTUlMFVWM2cjUTFBPXZubUZjUmx7VSE0SyN3MkdD
WSpmUmRiPQpLWT9aV0dAYyNrYmNgQlIkCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1n
aXQgYS9hcHAvcmVzL2VjbGlwc2UtbWFyay01MTIucG5nIGIvYXBwL3Jlcy9lY2xpcHNlLW1hcmst
NTEyLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwLi5lZDY4ZDcxM2E4Mjc1ZjRlY2ZhOTY2MTc0ODk0MWE5MGMwZjk0
MGQ3CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAyMzg5MAp6Y21YVjExeW9lZV9rWCh9LVFCVSZp
WGV6fCQwQ1J6cHA7NH0tUUJgMkFlfHpKKHhISDtxKTR9PGYqez1gQ0RQS2QKenxLYT1scFIpKHZk
Mmk7dm8xYzU8JmIlbXtgKVpeX09oZ2Ffaz18OERKJUF1TXhQKElsYztNZVote0RnVEdHVi1uCnpR
cXVGeSpxcmUoZjNqU1F4M2tLXj5OR0xCN258QTBzVkw2KnhBQShlQkMoKkxtRkdMZitefUNGYihq
WWwhTFFxIwp6P3NkSVNqLVBzTShtUDgqbD8xKURCJHdISlpSTkU3PWA2eXJpO05IekFsR2JRXiE/
WXo/ISZWK25Zb2tyb0RKIzcKeiRqRzlLJGdyQ2phSXUjRjFPSk5QdzsmMmlOX2BHSTIhWTVXYFVX
WVlQPHBgKDVFI0h1ZmRmJWU+UngqV2FVYy1JCnppWDsjVWdgJG84LT13Pk0jc2RULWo1dWshM3o0
WFlPUztYVSZzJms0QHNuZ2tNbjE/VCZ3dnp9a0JpQU49RlVGQwp6NzFAcV41MD54WTt3WlhfSypG
UmxqNCpYKDNGanx6eVFPQE9BNkdsTTlHO3hyPkVPQ21EKTlhT0JWRlRTZ3A5dHYKem10QzRje3N4
N29Sdyo4Mkc4UmA/R0NfM3dJSTsrckZvYn47Unx5WU5xSmY3JUNOdiNFcHs/Xzt4Yng/YmNMUzNL
CnokNmRaWUB8VjVvR3F0dVc9d3VgR2N2IyRUPz5FNkFacGdRP1NDNEI5Um44RFE9OEQoJjtLRGQl
Qit0ZEx0NUpMbgp6TFhGNDAhfF5rbDQ/fXxvbDY/aWxicSRpT14+eXVPXn1+dmhJeUFJdDE8THlS
d3JPTnFgbmgmWWRWLTlAMmQkLWIKeldLQ1ZEV1BUK0k0dVlPbTYodCVAMHRfO2VMWHxTRjcxRV9L
N2lRcHkjIzJ2JTtvU3xmNm1CdDN1OFlPOU5TfUIlCnpgI150bGR8K1ZzY3JjMk82KzZoN2VXRUZt
cXtLblNBLTx6T2d9Iz5US213aWMhT09AcGV5fSRrVyRpQzAkb2JvRAp6Xms7ZzYxaEBQIWtffTJr
K15ETF56K0AhOE90ZUIpa2ZgZUI2cTV7fl5ybEpoYUphI1hNQkJqNlI7MH5WUjdwZioKemhPV31q
JHhHez9jamZpcTRTRG8+MllZe30ldmdkWU1JPjFVMUhvUC1qNio+YWEpZHRKRmY4JUJUdF4zP2VL
K0RXCnopZ3N6K3JPSkp1Snd+dWVhOG5VfXZ2QXxLV0d2MzNzV1YwN2VHKlpwKCE5ZzxnWUxFX0ZT
Vncxck0tQ2lzTUtIbQp6P0B2MHZIMkFITDM4OCZQS1JwV0s0cHFlTThIRCQ4OyRmejU7Z3NRJiU+
fU16Sn5SKzhhZj5iT14zZkVmTn5oUVUKel9HOGVOWDRpPE5MY2srM0UwUkIrZ0Z5SkxydHAmPVdr
diRSPT5sI2FYRFdzXy1Je090dmAmd2UpR3ZnYEwyV3BOCnp6UU54Rz9+eTxnUmA3WXF5bXxrdE9y
ZkF6LTlKeHM+R25UJFFTc3xeYWghQjwyKHw+M0E8MTQ8bHhQTXJTfiRKMAp6JTs8Qk9rem07KSFT
b0VhcWVfcEpwWGtIUmJRZmN3MUE8XktvSlp8WXE3LUcxX0d2c21vM0hzVjJXO1RGdV5BdnwKekQ8
Q2RLN2xvalQ7JFhBITx3MG5LNE8raEZ2a28xeDQoK3BebiV9TCNkTXJMRmxuK2A/Rj8zY0hBJFpY
dWd+UncxCnpRcU57bylTbnNeQUlxJTFgMjl4a05wJl9lNXVQPy1nbVNwNldHcEkjR2JJd3F7S05Y
VHFkMnBwY2ZFRHgpYXpKZwp6aTk/c19eQnB4SShGQigqOTEyX3MlNkROZjRsaStOZ2p7eH48dWBx
SCY9enJFO058fH1WMzc8QjVmPkdpTX1Sen4KelphaEg8XmxebCF6TVUrNldebHRAMXs9OGV3b3Rh
dGNYelE1Zn4mXzk0WnhtM2xFUUVkS1F5OUh2eHxSdz9uJkw+CnpVeTM9e1BwKEwwbUArMykjQWNK
NGFgfX5JXjFRMzBkOXtwYUsqfmtjQk0pbzI7fn0lQERqRyRGQnFkRFc9MGpvVgp6eGQ7cj96SV96
bis7QUJGdS1iOSp4Z1V9eGk8Sm5Fa31PUT5aOS0mRzNyaEZKaF8jQkI3Y0MzZisxfWxVMSt0eiQK
emFnTzklJThrd2U3aUIlMF8mNjwxcShPXjVLXng0NXRjfERiVnNvVXxMaDxvJmx1KEc1JTQycz5z
NUE0KjJfMWN0CnpZWXtVfFpzK2YhbihNR1c8ZyFsWE15RDs1IUdYYDlWQFo1eXRoJmk8PGQlY0hh
aTl2NENUbm5lVFRQVG4oOTtCawp6QGBPR2ErXzI5T0UxVEc0Kkxvd2xGaCtpSExhcSZDQWMyY3dW
Q0xrdnBgKlNyXiFBUj0rI2BQdkJ1eGhHOHU8PmoKejA7TyZnNkE0XmpLWW4/aVVaNyN+WXhka0I4
Xm9UfWcoJmhSZnFKK1FiIS09TllKQkhRZ1UhWT5MbVR5RiV8Q18wCnorWlU5X1I4Z28kPTAxYC1P
UD5aRWlYQVNgQ1ZyYXVjM0dMI0o4fnJ7PD5abDxKeT9oMypwQyRKWWJqaF9lbTJ8dQp6eUxNX1gl
dXNnaTZlblheNFcoeXx0RUF8cUMwNns9MFlSIW9OPE1xSXBNNHFCbnx6JkJlTT9OfENCR1EtMkok
VSEKelVhOHxVWV5Ya3U0Pz4kT0hfd3JXO1YqQ15fI0trQ2IzNH5qVDNSRmhEbUghUm15UDctZkFr
QF9xODZVOzgtZnI0CnpscCY7VzxvXkJRWHhoV2MjXjtEOSRTa3s/RmJJVzg+OURWQVRsWmVTUy0y
NVpZRXBtOVhPa1V4PW5Wenc0YX53Kgp6WHJOZj1QdClvMGpzOHA5aSZPUyVYRTs/cyZEcmYyME1S
dWxhRUIhdzx+XmxrM2JuRk5MJE4xSSt1NSp6STNoO1UKenFHVSt0VnM7OSs+K2pKaT1SYUhQQyht
ODlnfnRCeUFyTWZIMSE7fChiSXRUdDd1dDAtITZpIXA5bUpkekx5JUpDCnpQN2RLZ3ZybjQjRlJy
O1hBRktvZChQRW9SNlM3YUVCNWlTJUQ4UEZiSm5KU2BTWns0bFgzcXAxSnlET3hPV3c/YQp6RlM5
QGJuVkZlIUcwbDViNHdGKztea0BHNUprQT9AaCY9NlFSZ1ZgdzlQazQqSGxKUV9xM2g8PkoteStg
Pzw9fGAKenUkK3wtWGEldiR2Nz8hemtNZEA3RlBsdStee08wSVNTVHMyVWJkUUp4O0IqSkR5QDRL
OWVfWENeZWRwTGR0Rn5DCnopP1J9c0YtS34xJX5yRHhMZH09dlg0JDEzYkVgdDBTfElVLTBPeFk4
byFMfWxeJXxCNGF6QTJxO2l8MVNwQWhZSAp6Q3hXT2pyfXE/Ji1WO2tXUDVLNzdfI31qPlQldTZQ
Z3owXkYpbV94PUdIenw7KmdaN2I0X0E+N1EoK2BwVTx9OTkKelIjc043ZT42TXF7aFhPO1Z6I3hs
Nl49O2xJOCNCUHVKSlBSNDNDY0htRT5OTWxWZ3tKcy0tZ2ZYT04qTCpFKkV4Cno2UihaPiVtdzxL
XlV5IXZ0Ki1hcHltWXJ3PDRhY242MiYySXRvPmE+b3Q0YV9uKXZvI1lje0VNVSZlKkxEdnphbgp6
YykkKVR4P0RCR04qej07VW1tRDUle0hsPW99VEl+bVBTTklNa2pMKzBHVjk8ak07QkNvbypOaylh
fHM5QXtUbXMKei0/S3BXVGVUWXtRcmcoRng3ZFJkfE1hczkrNWxPNjFmbjs7X3olQnRXN1RJSGxq
RkJTQ08kSj4+PEI7MCl9KThVCnp1JEk3OHJ8TGV4dEBZSyo+NnI8V3BESVVHbClDYTB0WXAzcDRn
dlMySHM5VEEhc2I3anlFYjZCbWk5bkQ4ckhITwp6JUlxUylJRmYxX1NXe1IoTUhfYDhHOWthSkgt
TyQ7R09NdmBgU0c+P3o2SiFIOyRkYyQkQzlIVDVKUilmTyRWRHgKenZ3ajtoM1d1SXZRWj8hOWwk
NWtkQmxjbXtDRV9BM3ZrZj00e0Mxaz82T0NgPWEzfXZWZ3xhTzcmR3dwU0dCWHs0CnpKQGl+Ymlr
Wm5ZYEQqcTN3Y05pTWhoYDR9TklUYS1USVczI1dVU0QlanZwYzk3dG9ffUhOcl4xVjlnKHRJU15F
Qwp6TH4/YmJkZF8mU0BKVW1eY1YlY3hkQ1plVGdBPFo7SVU5N15IKyNQT1VhZH4xLWVMU2FEemEj
dFRTYypPWH5mVnAKej15I1hJZypnbmUkI3BtdD9PPW43d31DUHpnZjNUNCljbUZFTztgP3JeRkVg
RT1AXihBZDNkb0dCWk9WZzNmT3V9Cnpte1RfKDdNUyNtNEVvQks8QEBae0x1fUEjIWk8VERZNSN4
WT43ITVzR2N5bSpoODQxV2tJVHtMN0RVbSQ5V0JwRAp6cCN1R24yMzZEOHtXRz5kbzEzaEM3Z3d6
NHktP3ZpZSU+ZlplIWtiTEFZZkFHREZBdW9JIXZaTW48Z0VZS1JRYm4KemwzWUVYXlkten5USEhf
aDRaakR9dm1uYngtciFZTEQhY2JuT3tsY0EpSjYzcnQ3X1QhOVM4LUhyVyg4TWtfWERrCno3NStP
Jm5RcWVuKWdBPDh8QlI1Ji1hZnR8UlFzMH5JKUdqJWtCSihXVXhUKmFYUF5CRkdyOThXJkdxSHJL
dXx8bwp6dUdodDlaTHhXSmR6eU9wZ3FoVmFWNSRlaU5EVmJYajkjZn10NWJ7RldnQ1AqZm44ViRA
SmJ8Q1QwdzRvSkBYVEIKenI7fWE1eGtmOGt3Q3p2S0dlWVJLT300TjFeYk1pTFEtITgxKC07Syho
JjJfY091dDtPMiR7YGQraDtDcUsyKj9fCnpJfmN9PVVNcjhgKHNYZXZoUiR1ZilYeDlkWFdMcUhS
N2lfQjs2ZGNNfE1yeTllUFZ7fiYmUXJsKGZgQGxAUFg/UAp6S2huTXgzaz9TP0ZBND5JQTZ2RTky
ajswKi1ybW58RjVRbW9OSlZkXkJTVEswRmZ3UkYhVkpCMTkpRWIpKEtNU1IKejlnUDRyYUliJVd8
Nm8pNyNoLTFudnphakQmVTFgMTl5SWpwe2tgPExwIzlIaCYqa0xyPkp2Ki1ERlo8OENAIypjCnp1
Mj1KNCY4KiVJK31eQnkwPSomOXpuOGxMZklGPlVALW8/TVlxc2k0X1Uwamdmc304WC11WlVKTWNB
e1NILTRKbgp6bkBlQ0NCJGt4cEFqIyZfPDxnOXFzaV49cWBaRz5NcDJwSkErMkdXYU4yXzc4PWdD
ey16KUt1ck49VmJDO29xSjgKekBCP08tZ00tdFdAdkUzKChIYV88OGo0QWZlfmV2OSU/X3lMTlFW
PHFMSmJQX09ZIUwhTDEtME9IbGRhd1k3azdPCnpoP2p+aj5fenE0VGxGckF1dFRFbUJOan5CTXc0
SGstRkN4NHpuUlJXM350R3g4ZW1ZOU1wYVopZGAqcHxlMjRmKgp6KV8za1Uxb3NRcmRNLXheKiZY
fkRpTXg/blQydUxSdFpQTFo8UHEmNShTSWtXRkgmdzhvP0M4PWVtO09tUFctbz8KejwzVkdlPWp1
O0JVUjw9XjhuaEtuKDd5NypoUCopfUpiMzw/eHVrWkIybTx0Nm4mNm18cFhsQGJaemJfMUhfazNE
CnpXI3hFKStVPDZaNHNzaENKJENjNFhLVDM3JTV6eThGbVRsK0xIMlk7NSM2ayU+emwoNGR9RHp8
Ull7bmxPencwaQp6eVAzNCpSbEAySTsxeWp5cjU5VTBFKUEhRG4hVUZ0Ty1TJjtOQ2R4aDl4fGB8
Z1JhY2hIfG40RE9JdEZnYUVqamIKentwRyNabSZVdDR0RGRqZE9QcmpZVWpZZn40M3p3KjdaOzFh
ZH1kR05BXklkYVE1JHp3c0pPfVJXSzVkflBvPVZMCnohOEpaUjhhVnpKUCsjR093JD5WJmxeO3Qm
QHk3Q29IKnFpJkYmIUJqcWIycD41aHB3ZGd0VHoqQzFnPGdYZ3x8UAp6O1BzRiQjdXlMdD1WUGh5
YkFLZF9ebyNsbk49aSFCSHxwRld1MUx8UHNoRE9qRG9uQWxvT1RLUEtQdV9zJlVJPG8Kem1yLUNA
SE1HNm1ScCsoUW9ibnh6eFB+ZGRCSm1oV2xoJno/MXFeP1B4fDJeM3BeUl5LNno2YlhJZXJFSG47
KzcxCnpuUEBuUEhzXlNnOXw0aiF6WUFiUHtQfnclY1N4KyhfdUxwNG4oNzt5bGF5aEp7fUdLc05j
czgjVUc0ekBxOUJWewp6TDJ1Vj5fZ3lwcGV6PiVYZlFCMllKdit3Vz1sXzc2bFYyKXdMPj9MNSMx
Z3ArNkQ0aiE9MFdxUjxlRWdgQSQrUGUKemIwQUlXLWEjd34xTE44cSY3clpEbU0wOWIye0s0dU5j
TDxfPXRZUFU0KjN5cWZNaUNrQXFwWnFRWHolP15WT0hqCnpDaCRyfD0tWEY4ciskI2JeS183Zi18
Mnl1PmN7Rkpha0dELU8kezlrTmhgKnkhSS19YXI+KjRvMl92fUpSOTdnbQp6MEp8JWNVZWNsdlBx
K0lkMD1LIUxMcXxEaGFVOHtpdWJXZnleZWNzRUFrSFZFaF8+O3NVUT1QK2lgTE5mZGtHZikKelNL
SmFydzV5QD1iYSZwTWYhLSNsPDUzaHU1ZWIqPUV8PGJ2NntSTWxJMjxxNkV2Iz1xbEJXS2JDbSF0
IWlBNVYzCno9TzclQ3dkeldeU2plS1ZDcUlXKWpTczg3azglPmpJRyZfS2UqeGMmM2x1JlZUcClM
YnNZfUFtZTZ8XzhmQmtCaQp6QWI/aDZ3aWBTJjFlaHxEKWgkYG4wbmZKVmlAVER+JUUkaipKc18k
bTw1ZClnVzBxemw9QT5mMlVzNiQwRSpvJUQKendOXi1eV2BxbTtCfjZUaiVyYGE7R1Q4YGtVb0Yj
QEE4QGstbXlZQDFNUlB6VEItayFxX3YzN1VyUFgtaUlHVk5GCnpPPXJCMnUrXlQ/VFJkb14qWEsx
bWI0LVdHYXxZbnsoaTkqby1aTTNHN2wwZ2k2SkVKTllyNisqKU4hY1d8TnBleQp6bVpXaDtQS35R
dzE9b2ZPYFVYTitkZyoyTnc2QVF8VH5lU1NQdDNEJmhQPVVAa2RjcHVIbEJfY08qck50N2F2ezgK
ekw4dHgzQDMjVV9eWjlAJVh9UXQjLWF1KjRaRV82SE9qaSNRYG0qSUgkSXJDOWJMQThBOW5XK2Zy
Xit2b21jcnk1Cnp1T00/V2Q9LXp5M2BpYTUpRFNFUGI5SFJWaD1rIUJPLUhpPHtsM2FzeXgtbUhl
dTg9b1d2OStmNzFfMGYtO0JMSAp6di1ecG9FJiY7X29oKSVoYlhkNUJtaDZ2VG5lWEo/aEJWYn4m
QShJeWQwOEMwbzVVSDtrWnw/cHc3a3NBYE0qfmwKenBiWH1aZXt+OSZPbyNtPGdNdC1wdHp8cF5Z
ak9+UDdzSnI1OyhLeSVpaThnR21BeiZfRXNYUUskWVJ1Kj1ldF5OCnpTN30odyZOcGdwVXN+MH07
Xk1TXjRgM1ZKYTJuTk0jRWs9Tyo8RislcSo2U1dlSUY4VEpmSHFQTGBCJHRjQDwqcwp6UHxCU2ZM
UU51IWNDcWt4dzItdDx3UlZhWDhUSlp3bExZdzY5MU9lay1jZHNETTYtVTxrbCs8XlE7RjJ6Wn4o
ZHMKejswaGptZEEpbXgwQ1M1ZUwyRGlrYFlAPDQ5PkM0K0YkKElgWW5JNVFnempufjEqMVA8UklX
TlBWZnA8MCQqNTtFCnp6dCZiaSM2dHVRcW8yeGU2Zlo4WXtyQnVXbDg4cTJeSVZOdkp9RC0jX28j
cGdpVW0xU3VRQ3NMVTUqZ0kmMm80aQp6dmhEVXkqYFlgcEhQezFFPSl1JVZXP3l2TWU+bD5pc0he
QXJzUUxaMT52JE53WURWP0l6YCVTeHtreXdVa3d8djEKemxyM2ZAOH49TTRUcTx0I2dVK2JXK1VR
ZUhEUDlqamo4dl9BUUhMWW1pJEw8Vl59MjloUyh3JlBWantKVUNGN3RrCnozdmpQO0BZazFRS14t
XlBvTTF0bkE9c1FrV0RLOVA3cW9pams1MUJGRTx4c3o5VHZ2MCMzRHNwQn1gPWpsVzc5SQp6YjFI
RjNuIVJNXntoRXlYa3s9eTc3PkN9RHJPV04yOzE/R2NZeF9zfXJPbzYpWG9jczJmb29mdnN2SHlv
d29hJkoKejRTb0Y9N0Vnczk3P1RRKkd9QXBwUTJOKnZ6aDExUylHaHdPT1U9WkBHJSY3ezVNQyFl
PkBUfWhDI1J3eyVNbj9XCno2a0IlaCZLcCZuQTl5TnpBQ1lZVzhmNlM1IWNtQ1drZipsUmlIfGck
NTImeGZrYGlUMCpPPkg3QEk1KGw/STJJdgp6MG5RQzNzXmFqUDB6fD1lYno3IXEjbkNVbzwlaF4z
cUw2NDN7am9kNCMpZU5+Pkx3PT44bmIqNiFDUm16SXkhdTIKel5NdSk7KVAkSnJlZ0BKYnR5dCtr
XjhSbTBoPUp5am5fVXt3N0xJemQzMG5mUU1jTmJMeTckKyM7eihVKE9vVy1hCnpZcVlGfjhUd3Er
c2FUUS0kJEFKUEVNSlVweilwQU9QXj56bFl2bTA4WX5sWDBhNT1oJkVTO1MxQkw3fipYNmFEVwp6
RD1UXjhVOTg+dkhvIzJTbmpNKWQjSFB9bWdpJn5AczF2MCE9b09oNGA2ajJgVHYkPDxBQD8zIXo/
I19EOD11QUMKejJEcT95dSlwZEpjdTNCQj5iMlM/TGooZ2tUcVBke0pSeE93YC0mYiopUDUxS1hv
N3YpNDs1PnVFP25QWGpQNmYlCnpkWGJ9VDhqPFMjbiM5RzFyZXJtVU0lQiVvOHEhX0NXND9TZEQ5
RTdUUG0qVHJUb1hyRXFpSjJFKjtERz4taTF+QAp6Rm9NPyFLfEJuPmJuKGd3QnBKJC1ZWlcxKj5K
JUZ8QHtTfVkxNTlNT1ZvWnQtKz51fF4zRVR2JG85bzVYTnUzTCsKem9lUFBiUT5vYnNpTDJQaXxK
WFlgdCRoNTdpIXVhKSFTa1lIaTteJSg2cjUyQTZ6NUZuRD1LfCl0KVUkTFYoTUJwCnptPTVqOGB9
SnZEI3BMNFJWdCEyfjF2Wk8yKSNrdDZ4R2ApVj1KWSROV09oWFJTRi1aOUU4Pyk2dEMhamhvVD8w
Kgp6IWAzYzJ6TCpwRWF9ZGJBRz02Y1Q8YiU9QlR4aXZXb1lCfV4lbUl2RHA2SFlVSXF4UW9jdTQ/
JGxpdTV4PDR6O2AKeldXIzxBeH5yZDZNVlVKQTltWm5FYVhBeipOfUEhcHpZVEZuQCg0SnFPd3l6
SDxCTEJlKHZITmpCdFFoa0NIZjliCno1IWZqQ0kxVTJhcVNFJT9ndyhlemRNJHNqJGcjelY8TnhV
c0FBYStMLU5re0JAdiUxaG0pVzRBQ1ZBVW5pWDN+RAp6VT1BZVRQRSN9V2NZbz0hQTdqQnMmc2lm
PTJIMiFQSmJfPCZ3YlJ0PHJuRHpBam1UO284M3JsUmtQMClSKWJudWoKelRVIShyenRDJDk8dlE0
bGYlK3hLZiFCNEJZJXBsVnp3d1F7NjtiP0tEUTB7THZIWUhBWUs8THU/SlptMEQkUX5nCnpASUgz
VD07cG53YjU2eXZUPUhxSXlsJnQ2MEQ5QikkKkFnanBRaiFKV15UNyNKaD5IU1AtMyktPyh7MDUk
VG5OeQp6N05teDdHIzxnKE1CS313WEtUYClDSzgrLURiUGJRc0UmLXdXe1dFQndeeEFoTXE7U2o8
Zm9IMnYqUnpVOXJXRmsKeipmNj1UT1ZAUComVF9tQ2x7YT5raCtve0lEWnA9WEJ0S2U7RC1teFB1
Zj1pa3RsfjZQJmZlS3E5VDY9YDNtO2VICnpOSlFhaUNnSHhhMXVDfHFNKFJFcUBMfm1UYUEkKWNZ
UzY3VkZFP2BTeyUwcll3RHRUKXgtakY/LX1ePn5fS0l9Xgp6RGpSPTtNK2I0PFB2TGhIOWtNQXM4
NXhWP24tWDdJcEx0U3RvMjdnODkrRWheSz4yUF9CdUF+b3lCPn5LJDdGS34KejJEfkRYd0tfN14k
NklQcCZJU3VDQ3RBRiZtWFYmI2l6UXljbGVnMUE+WnYlMVhqJmB6ZWwrfVpCbERsRmA/ZlFJCnpu
MVc1bElgLXE0MzV1UENiKDFHTXMzfjRZdmVXJHdzQH5WZDR3M3dYczEjaDModStxVEV0Yk57aWBg
SmxFeEZvdwp6SDh3YUBMeHx4fDdffEkwN300TFIrUXBKa1l0aDtNUjVZJDN2X05VfFpga0F7Pn5s
Um1nTGd4MD4paClTQkw/akYKekY2Q3dVNXx7WGU/MF9lIT9qc2V3KkgwLV9qa3ZqZjtCbD56PXU5
eEteKz1JSjE3NFpCWTVke3MqNnM4T2ErSXJWCnpleGpaQWpUQT94N3IjeiViYlArNU9wUk8lYlko
cSUzVlNyLSlpQmFYb1p4NUB4O2p+e0crSU9LIzBobG1paWo2cAp6NmxOa1JRfEVuaVNsJFdPe2go
MU91YGh3S1d4ckV2ZF5+I0JXP2A1c3s+OThRSG95RjBDN3xBbEQlIU1DXmx2QWUKenpVQ1dydHox
KjFpPXxVemBHUmQ/SjI2cThpVzVoV0t5dVkyXk91P3x2Xm1rcXJ2eSs5ZnBBS3glOUdDZEN4ekxl
CnpUO3goRE5sSTt6VmN6WSFNTns1TlBFKHtOMkopOU5JVUQwbGY0YlBLS2VZamhEWn0hb0RlNk9G
c05jQUc2KHNyRwp6dF45QXpEUWNOR1F3bHMhTWJ3fjNoKCpDcXkyPFR5OypGVHNXTGNQWFF1NzBV
RyhxblE+JWUzXkVZTXRlJmF+Ty0KelVWISh+N18tNCokS2ZWUEhfeDRqXyFrSlMrLUBNSnUqV3s2
UGpIJDFQKnVpaFBwUmhldVBURnI4LWp6TlUzX2sxCnpBbi0heD4oLTBXS15mc01yM3RvfChpal5i
ciZoVSoqQWBsNkFJeyFGMHBAOTBhfCtUaiN5RFo3KnN6O1hORS0mSQp6MipFMW1qYzd1VGBuflpW
Xz9OcmNlNSZYKFJfQ0FWSldKTGAmdjFBYlpNbCFtdWNURlkpUUoxPit7Q1htKF9NUSsKejR8aj41
YHhZIV9AQ1BNfnxLOW5CZkBxUCNyIT55O3RJOTA/PEQzLVhQVE0xMXRka2Ataz9HWSs8YWg4JlNu
OWxyCnpQSn1rP3kwcGd4VDlkTDgqI0N6MkNnai0+Ym1XNkQ1eEM+YmwoV35DWkN5LTJVN1MmS0B4
fGo3d3VwPUslXms5aAp6O3UoNDUjI2QhPmt8JHY8cjdQSGBRZmhfczlsP2dGcHsmeFI1MFNfO1gm
VChXeXRoK1gzTXlKNE1YUyVmd3IhLXUKeitBWFgxNnt0SllpWWNxQDxRMCsrbytQUFV2PT9yWEkk
VW0rM3ZaZDh2OVptM3JETExSRGZXI24kV3gjVDI0UTNeCnpxQyEoTTJCcUFAZ1pTXnxhbStYRDQh
STVHP0pzMFZsQ3slIXxIezlHV2Q1cWB3ODR9JVVBQH0qSk1+NHV5IU1tUAp6Y15pajBSclN+Vms3
YTBeVWxjM0dlKmd8PiM5ZVl6e2UyVispN3d2M21HMyZteGNZNFI/Xn58JEdjVlAhSXpSa2oKenJf
VGNedCtYZmR2KiswcFJnNFA5SjVGRXJUNGV0YmRZWSl8I2REUShtISllP1RWT1FFYUc7YnBgK1Ah
KUp7aTIjCno+PnlyTHNsenY/JDJSMjJWJDhXfU9JK1J1P1BabWo8LSQkWGR0UzFZNCk8cDUzd3st
QEdsbEZqWHlTI1hVbl9iaQp6NEN5P1FiUTw9WjRqTSgmKmw2T3ZsVCNTPT1mPDxAeUpLdDgqel42
Jl9PZyFiK0BuamE8fEleTlVpO2c9a3l5JHIKekFWU3BqR0ljdG1TUWdUcCNWJHlaPVgzd0ZFXlJV
ZUhvblp+Ukh5YHhIR2grX1RxbkQqM09rdmNWd15HMzhFTWFFCnpyYERrN0hYUyM3RD9iWGxoJj8+
ezw7ajhRTzRQOSQqUF4+QXNIcXdVISlQUXleQnprRDN1azs4IU5xUl8we0BWUQp6YWlZcyRiP0Jl
THspZigmWChkWSUleVY2dDR6SnomZl9rTUBBNXVvRG5Ud0A/O0xFLXdNT18wJTw+fDdoU1M7TCsK
ej99Kn5kZlpYKEV2ZmxmN3ZIbHF+Q31PVEE1QiNIVHNeQ2NtNFhgSDZ8RklIVVNVek8rYDwlYG5R
P2Uxc3lfbCRmCnomSEdpRDJUc3UlKDhnVjwzVEspaXg5UFY8UGxXTTlgV2d5UClTZXxPN351eiYy
QSY9e1U7ZjtoM35gdFh4RTJePwp6V1YldCUla3o9e0dAbysza0ZKRFVUe1RRMFBMSndHOSZDKFZs
LV5BR2sxdkNiQ0xZUDZQUFhBeGVlUzFPaEAwa2IKej40fT5Ed2QmNzdffmNJSyFnS0dibF9LSkdX
UWtyYHpMPkZ2cklPfTYxNSY4RVhqQ3liJWJ1ZSZPQClQfGV2P0RlCnpJcDJ3ck4wQFZ+ZTRjSnd7
M0NPQGQ9ZTY1ZUE8dVIoUU92YG5MLV94dFljWX1NaWtOME9Ca1ooWUtNenlHYFA+egp6bnxuSypa
JDNWWkZXLUxsRE1oaGsma1psZDRSUiR2d0JTRzJmN0kjTntyYypzeUF8e2w+ZkMkQVFpRHcmKCF2
I0cKek4kUjgwYWdwZnt3IWZkUj1qVS1wQSkzVXokZU5fRndoVDV9XyY7I1leZnhlKnFjRSQhZzVS
ai0zc0pRR25DczhGCnpxbiNNOT89fDVIdzUlcmglRFc1I05yZDltTV5yZyY+VC19UGdtTTRqXm1W
PlRzPkA9YiFCMUZ8SVUkI3twY3YwQAp6MWtiaSFgYz4tRChEQG1hdTVzO2VzZk84IXc2VklWMmVj
MlZkYkhyeSNKSH17QVM7ZnpyVk13Ozk5dzlkd3FEWHoKenh8KXFDc0orZWtSZ31ifVJCYjhJQEtm
Kj5JaHBhVGY3IW5+Zi05TUU8YzxIVzQyPzYrUl5tYXJ3X2JfU1VYJndRCnpqM3B5UTY3UVI+QEl3
NGRnPmcmfioqfDRxaFpGY0pwTjteSEdrQnQ1TmlaQXBjemtwQU83a1poaUpOe0tqSz8pRwp6Pj92
PTRAOGFnVXo3YjRCc3BOam9DMjlwMFMtM3x7LWw8aVk1TW5wV05tMHpJR1VvN15IUE8lb19lKmc4
KFByVV4KeiFlQVl4cC1AMjckNVkpTmpWKnFMJl8ydFItLV5BJm0mditIY2s/MmprVWhmMGtZfHh6
UDUhajxvM3hKMVlsc1kpCno/KWBVdEA2N0o5ZEZtTUVkQEBoIW9SKmhWc0c9ckc4NDQxQm43Y2Qy
RzkzOz84KjN1Nm43Vih6clRrU3Z0RTVrNwp6KzFwRiREXzdXWm9ieS0+eXQyWFc9Q2FVST5EMV9R
bTI7a1AleXEpR2Z2MzBBaClzeDZaVUtDWGwjVUBxS2xXdVIKemgtVzNYPm5CbFU4c0dYKnIxUUVv
Y3lnJEV3STc2YmJqZDsqMiE/REtgQ2YrXilDclpMQzghU1NkbWdNa0RBSyRJCno+Q0IydnVwSUJW
NEdCQntsfmtgSipTTlZzMz11TiFSZzRVcjJnfmApc19rcHJAfFBJenYxSDl1QHN4VHxGRiNTJQp6
Jio2SmsjQHQ2eTZDYFpLaHl5TF8kMjFhPTMoMnh0YmpDNmNvKigkYWR3PU48ejtwa2JvV0wqQV5i
ZmY0PEY1WDUKenk4QyhANn4hRnlIZUJDKWtgMEhmWHU7Z1I3eU51fEBfVkE5VXRfflg5WnNgVyp5
RUtTb3BPSFpFfUo8ejk2UyRvCnpodG9IbmFLQXFNNT9Zam1PcERlKnokMUQoREhJPkk+Kz5PbjNT
PTZPSCp7X0MtMlJ6bnBTU0JHd31XOypeZUdmfgp6QUdiWnhFPGJ0TEBqI1JgN2xtcylreWE0fiE/
PHM4NnlsPyRfQyRTfG5LfUQxQEZJSD5nI0FVYzk0YGx0dnQraHkKeih5QGxHV24qfHw+aTNeVz5i
fSQhQzRETUlsekFPZmZkTW5eR3hHNzg2JkNnTSN6dkxYSmEpM1FGTFJOfSlyTFgjCnpgPkE1MnNn
MyZycnB8TE89aH52OGxScChsY0pGRjhhfTVAbkxwZDNZbj88Yz1AelNoU1klY0IhWHVGJmZ3SSFY
YAp6TDZHMktQb0xSeypLPn52ViY5O251VUM1Y087c0Yxaz1qcnwwdHw5cl56byp6P31BO0NQWEs0
MTAqeF41WVdrbUQKeisrLWh4Xkk+Z316K0hzVWoweE0qWiRMMDxnbmk7P0E8VCZkZkh2eSkhJDlg
PT97KFZ9SD5JQE9JQm9NcD1uQTtpCnpndVUlVF9teTtoYk08MzRteDw3KlkoejxTPG48YCFSMylC
aDdeYjJhV1hTOVVTPU9jRThSMzJAaExIQk8xfHxKaAp6RzNXcEFrRVo8O2BtbnBCYVd3Jih6Wnlt
fl4/TEslO2U+M3NGfjB6T0oraCF0b21TWSEpaHpLPWtAbj1ySFQyclUKekdsfCV7XnRUUFgyLXM9
PiFTKmhJelFwdHBMSDxgSUlZYj5ucnV2WkIxVFRkRjU5Jj16Q3gzKHF0SUZxeUZBZzFGCnpXMzRr
YXNsSH5mX0FeVW50TUo1eTxrKz82JHhuYHdKI3QxfWVtcnVYUGhAUTM+MXo7PiZwO3FjbndtWj9e
UlJxbAp6PGc9NWAqUSg5aFg5fDZEc2dhOSQ2NGBlWV97MXBSc3spdXM7QUprXmN3JWEzZ3N1TW0o
X00xdzg9Zz19dHVpc3UKeiE3SkdOU1lMbFE/V1dMWUhZRTFeVnJJNGN3eVl5SGpQa3dha2wyZipU
YXJJVWx+YXtAZlZEK0xoRDtLJmVAZkdGCnp6MitNZXZ2dGJrUWklOWxjIURHQ3tHPHhFYlo9ZkJe
QCE3ZkExSzJofEhIdDBvdE84ZHBmdzJwNEZOUFNfUVZhXwp6dT1HQGZXRz85KWA2Yz9CeytZdWlj
QllEISt8bFVlIylCdys0YjhoUDk4QmgtM2A4YkclWGcmJS0rRGt1ITheTCYKekU8Q2dxOCQwQ3hQ
N2JHR1M4fnxyZSNmSG9HOXRUbT8tUlkjMkZGX0xQRygjOFo7ZWR9fDRrY0NMbVIhXmVQNWxlCnpx
X2N3SE1iK2tQRDVCemJUYT48LWt3RDI2bTEldFFOeFMlQF59Sk9wPGQ4JSZtUkoxUnNyekYtLVMt
ZDA7JTsyfgp6NiRHNDFxcmpsdnQ/TmdBeFhDTzNlWUUhJm9vdDx4KUJPJFp5bXZKU2xAKlFQRlhW
UUF1ZUkxPVFoRWlMYzRETnUKeitVeXo1JWtNVXhSSTkxZjk1eCFkbzhGK0BxYGRvMCpOS3ZvcHNq
SDN0JWx5OHpfKG5HWE56OzFuYEQ3ckpecyEyCnp2KiUoYVVIYlJUbC1iRUdHP0VSYUp6dnl6KGB8
d1hCPG1qWjU8RVZ5Uzt0OXo7QnBEPU92U08hJENacGBqTlYwXgp6NiVfRj03OHxkTDZoI1V7MUJM
R0NnMnhrb15ZUTc8P3Z8ZG81RllPaWlFWGRjSlYyYXNtJXNSN2ZANFIzMHxnPnIKekV0JDZ5bHMt
PntkIXshUnRrLXktZTI7V1BRMFhlSTReUz1fS3VvfCp2KUFeUTNZTHo7MmkyPWpSUGZubT4qJSUq
Cnp8TXEpKjBOZTMyU31NajExPCo0bk1fYjNHZUNjJUU8S15BYD9aX348dnA+fXlDajZBfElTUk9R
Kz02cVdMRSY/RAp6a2dyMFkqSzRhO2V9ZEVFVzdyVDU4Sj08Ul5WZ0F+UDY4aDdHQztRM3txfFdI
WUd5VD87czQ0dz5gYkZycCU7fnwKenpvcV5IVCF9VXdoTFB7STZJb2hlaX5ze0hpZXVUSWNqdXo+
cDMkWFB2RTlmQ3hkamIkUDBMIXFXTypHWGBgOEN8Cno9UjEhRW5hRjtaWCZgISYzbW52NFg+eSp1
Wj13LTRneF8+Zjh4fik8LUE4QGZ7PDEhd2F+ZUM/JVZLYUJIOV9AfAp6TjtyeHRtR0d2US05TXsl
WG4tUD1XNF8/T2NYPmg4cEM1K15gYGt3RzY5Ujdpek9fVUhlXlFaYEBNaHZBfDlwX30KekJASjhM
Ylc/Vjs/cENUNW1Ge2FFeT0lb0tiYWY9WHhBN28ycXtyTT5XQnVvb29aLTh7XklWK2o9UjNTZExj
SUorCnp4Xk1IblErU3U5cGJXVDlSIU4jUEB5JHZlS2hDfXR0Yk4hMHQyJXMxQk1NMVJxWlJoKSEm
UHAqbW4tXmlDeytycwp6JGd1Nll4YWM7Tk1FfWUyNV5eMUB2eSVGaDZ6TU01U3FzcXUmdjBGOC04
Wk17aCl3JmlXX2UlQSlzO2V9ZC1GcFkKenA2YXFPTXh6emRTK0s2TGNRYkJaaSVufUwzcChaRnIp
UmxWIzZra21aY1BvWEQwYiVueVAmPERUQTkjM1dGTlduCnpwNmh6Vy1OUThgenszIVVQbmpmZUlq
Q3tJMHMoUFVWd1V4aER5aihidChvc19mcGw2KygjNyVMaWVufERwUFp+YAp6N3lUJXohJjRuMUdR
bkdCeik9aSlZJFFYcC0kOzVeVmBiS2R3Um5nZFVVSEdHd1FiV1ZqXko7MihXe0diP31CdTQKek9X
c08qZTZ0R05DUjE0YUl+I0ZMKTNwQmpLIWwtO19lem02Zn1pYDVldlVnJCZaaz9EVVhJazN7fTE7
dWErQ1hvCnpTQUlCc0VLZVZYO0oxKXtWRDR1RDYpQzFfVyEmPFZwSU1vc1BGTzQtKXc8RlFrKEw0
Tm4oPGA0QmJmY0JKZjEwSQp6SyR1REt3MnZKRVBLPFhlTlNjRytMRTV3YjhxeHlqVkM1R2Z6N292
fnBxaz4xPEJofEVURVhQVlh5dVJfSUlqaFAKejF8Qz81U209SSNjY3ItYnMoeW5uc3YlT0pRekR+
NzNta01yISFocDNkeE1hbFl8RjJNdTx7e3VOKj5FIT1kZ0w5Cnpzbkx9WmIrRnxgczJYbSR4WjFK
IStUVXpOPH1vS3AyIV47elE+bWJAUyUkN05oSVB1cmZSQj12VUcqVjtEbS03TAp6NGJ0SV58Rypx
fj1WUmJjVDAycW5uKUdHVTU/QS1NI0c5aExIT0xiMURnJF8zWSU3MHRXVU84WjQ1cn15SlVPMnoK
enNfMmNJN0d8IzwodC1XP0E8a2tsbWVHKT92fk07dzd1dShVLVhofTMlWEBGbldRWnFsOCUmLUx4
JUg1UEBZeC1wCnpoQWhYYXE7fiRPcVZiKy09QTJMTzh0OT1UNypZX2QpR0c3JlleSCQ+Pm43PFFk
T1ZhVkBKSVVRdWZmVlRecEc+Tgp6PT81aTdxYEdBKVFyRG5zVkEoU3I4eGQkU1BXUmBoeyMlcURU
LTBSTThnbkpaTzIxPjhAUmQycFMkKDcxdV8jPHUKei1KR2xZb3cwZTV1YjRaYj9vV1hFK3gzaTRC
KGp6Zih+RTxuJFNDdG1oRGVPcHFxN2ZmRiVaR0pwbUBjMVF0ckM2CnpDPnYqKWZIMEk/S0JOfSt2
KnUpRFV7XzxjZjEzNiNpYnJpQlB0aHRFbVpTTlcxYWFUaXd4e0w8I35rOXdxb20xJQp6PCo8TW1B
TXpkMmIqK1JxeWAyOF5EZGNxPE8lNyMhNnAxUnIxdEYxezQlMS02UUc2PzE5YHdVPj9BPEk3X0gm
NnoKenF7cFpiQzI3OGdQWVlRMj5WKUckWTluej4tZGdeQj85d34tNX08M2h3eHM4Ymh4OCtYdFpl
PGBAViVfM1RIZ09sCnpTNGQ9bWFVZHFzK2JBKGZ6QGZ3QU9JUmckdzhPOVI+YSU7QCszQVI9cUlW
ekNJO3xHJnU+ZGhPKmlNOGhTSUYwVgp6T1JHYmg9VFRxR188aXNOPzU/d3VNNV5LTkpDRUY8Q2lD
I1M/RkBrMylJfX02bV47cnMkRFdDTVAtamhxSz5lZVQKejJYNCp9ZmxwMiRxQn4hJGUqci1He3V+
XzN7REwrbiYtcm8tTmBBe0Y4d1pLRlQ7OV5eRDg5Xk0oWjdwWVJ2aHZvCnpCUzttLSEtKDctR1Ji
el5BQV4wYCpqQ0VHenU/SHoxX3dlI0dYcnB2YE43bDAjTW4zVXVEbjgpcGJLaUEoa3ZtTgp6Tn5R
Wn5Bdz08ZzNAaiVXTHxyUWYwaXkmT0khMU9jcGJAOEBFSEk9QVA9ZSpfa01jSkYrP0pQUWIzdiRv
PncwKlkKenF6Knt1aiY7NGduKDBnSHtWXnxkbF5oe0hGKUNmWjF6eWFybHMjJDQ3JXhaaVpiJjVL
e3EzdzkwTDJEXnpwN0tmCnpjd1NhTWp3KSlmdHNfJlNBVHFoNWRhcUVadSEofCNPSHIzO3lDfVRS
VCt7U0ZiZ0Z9e093alY3al9CQHVoKzxkQAp6MnE8MlIkZ1IobG5YPDIqPyZEK25qSXI1fjR7fG87
anZfVlN6X0BSV213I3gwYDxWO29II05CUE1CYU5LJTxuI2YKemtrayowV3Z9IzlTN0txcW9wQHkq
MFhyNTVjXjYzWk9lNXRza08rRjU0e1Z4OyheVW0mUHk/ZzZHVzhXemp+XlBwCnpSMDEwTzh5KVdQ
ZlI4ZVRqfEB1WTEtY1Z7LSY/aCtqMGF7KFRSZGdNITkrZ0QrbVFBKCVKfksyNXdCQ21LRkxNfAp6
ITFWd1ZwO2ZhWWY8SXVJSV9EcDcmUnxgRzBFMDlJJm02OSt7aXFMVDw4IyNmeyh1QVg8U1A0bFZ7
NCQqTEZSPHoKekpRUlo4ZzlMZ1gwbX5yfmVadHkoWENFSkd7JjYqN2kzUmlEM3pBXmFtMVdqbUVs
bWd8TSl0Q2UhSTUkIzVLcTRWCnopNGNlVGllS2ttbX47P2lUQUktTmE5R1pfc198a0QlTVNvUSZr
NXJwM2YoYEYqWnlPcz0xej5EMH0jTlVgYno5IQp6SCFBYj5yeDRRWjx9MGk1X2RuN1VhPTd3JURA
K2lTYGZ3MCEhKz8zbylJbkwtb0JKUmk1Y2REKCVvQkJte3pyeD4KenxKc0U4PHBBdV9MbDBlRSRg
cStYPj1sb1QjPUgrbCgtZmRAU0stZDgzR3R8RDk1OCRDMW01Sm1uUSElTlNyYUAkCnpOYHY8OGB9
aGJQeyFnQmxuXkpJe01mPSEtLTJKIVdYamJWfSEwMk9LQzhRQHxHNkR9bldxNGJkUD8pKGQrWEUw
WQp6bkk8aX1RbD9+I1pUSTc9NkNKJUUlYExfKm56fXAlQHJQdXBGeSozNVFFPmpCTn1OJHBjTi11
MlJrenRRZ2EpZXcKekVTVXtadiFUTTlaNCkzcHk5V215TTVHdHxjcD4qYzByUWQ4RjZxckI/TFZ8
MlI1SUJpSHQ5K1olQDd6NjU0dks9CnplO2oqezk3aSRnUmsmNnwmekY7cGNAX3d2TDU9bEgmUFg8
ZFl1PiFwLU5WK2dmPVI+NUh8dyZ5OEFofnoqKj5HQgp6NDVUdEtjUntgcnk8RVNOa1ZaPnBYUWxh
d3l4U0R1JWU9XjJDMiszeldqKlhRM3QpP1dZfismfFN+MjNgKSM+WUUKelR3dWBxMjM1ZnhaLUoj
PEojYUNSemdsTFh8SzVMWmpqM1lmOU9ldz8kb3VEZD5INDQ5ZGdvZ01EbktCJkBJMHpDCno8XilA
aFQ+bnVWMXtDa1p4JGBeOztadGAlRVhXdXZGODt9Q0tlQz1ZX2tzP3J8OHN7TCF2RXxqKzAyNVVt
PGQ0Mgp6d3BgbCVLU1EkcHpuK159ZW0oe2ZDSCpSezN4Xnt3bkUoZnl8MTBUSzFFY1FIJUdwYWYq
RnZCdW9+SDJjd3whUT0KemZWWDJEWmlTZnVXZVNneXhmeE93SyEpMlRPNGd3ZHRySnRsfDZRTC1T
QmhFK1I+cisrYT5GZ3UwfThoc0tabWpRCnpXI0I4S3VGdFB2ZXwtYiRKYEttbTIjQkpnMzw3bzNe
IyRDUHw4QVp+d01zen5jQShkJFN1eWZFPUsrRz41YkA7aAp6LU5reD9NZGAodHBUeUQ3bzUjeiZP
N0JzNkM4KFFsb2dAWkchYE1McG12ekRjI0dxdyl7JG1sVk1ncylEX1ZsJGYKelFHbDU+SE58LW5s
PW49I21HfCpJMzhhTlA3Sm00RE0oRzhTQWcwdG1FWG8rLWQzUHYzYTx+alZkYj1gajRGVHZ3CnpA
SWtLeUstM1M9ayNlUGprU1AjYEM8YkJrT3dqdzdaRFlvOVRIPzN7TUVnbzkmWU9NXnJUNz53YTM5
Myg3dUFTcwp6U0YpX05EQ3MqSms9bEt4KEwmS0dRe2N1ISQtKyRAUl8zLWRtallNeil9P1RCT184
QnJycVg+b1V4QHdIMkBwZykKens1MDM1e0RlSTE7bHREZTBGJSNtaFJ9OVBeQGV6RzRNWik2NHFk
dGVeck5KdCZtQm03cDlEQmMrX3ZmNGFmJl5ACnpwWn5AQWluTjImSCNPOCoyUE5pTHIlJFAtQmYq
aFg2PENLQWI1bk90NjwzMGxOUSU1SmpXMTBMNi1ac1k7JC1tPAp6MVZEenA7Z0c7NFEyYVhwJX5z
R2dtMlYyUWRpSm1lSiNUeW41TnFEe3NLX3hAMTcpUjFNSCtUOVNSfWJLZXdLPyYKelBEUztaISNu
bjtgciRKaVItYUZCZE1LZTdDMXAqMGNVXkpINmI9fFhERlFNVkxiODJtclUjeHRVMGg8fVJWTUtm
Cno9dVpGLVhUe3dHTE5JbDU1WHIqTDhQKXg4RzE9SWRGKE5laSR7Mn1yPDxFdV9hezEwJVMtY0dz
Vl9CaW1RQUlSXwp6QT5IeWltY1JUSUI7aClEWDMwSXRHcnBTd3BVZ01XZFFfNGVzbGlBTkdpRSEh
YFQ4WH1QTlI7TztLeDJRZUJvQXUKenhJcUlvR0pmOD8yVjZ3KEc1cVYpMEJPMTNeXlZKYWt4PXdi
IV9MPFpIQ2p8VzBuVztlVn1uZzQxQF41SjhObEpGCnoyYSlNfFhKK2oke1hHOzxMXzJtbGJsZFhu
cWQoaWR7QHtoey10QGUjYGlnbmNvZVM3S1B9Xjl+dTVWeUkqPnpqKgp6dndLRHRAfSQzfih2NGF1
I09AYFgpXz5VN2AlIyNQdW8hOHYjIXpsUTNoIWdEaXl2fFRsfX1MO0JkJHMtd3NaRiUKelZJaj99
eyo+SjZRfFV3Rj9ndD52WGphTUdkWUtOMzxmbj9qZWd7eSk9PGd2NlNwcjlSdGZ3RiExNHtjM15P
TS0rCnp0SGNtVV5HQyV7SHJmJEBnT1EjRDhDMyU4ek1kTmMpSnUqe082NnAybkY/Zm08TmBwc2JU
RjJCK0wkcjFEMmFqTAp6XmdHcXVoeyhaJT9VTFZiMTtud2ZHQz9Jemx9RzxAPVBtTHY5PE1qRWZY
TWh6ZUlgOTEjMFM+NjAwfChxVk52dHMKemlMQXpGUUFNXjxBdVhUPT9DYDE1PzVQVmszPFMkbnRK
MEdWfDJeYHlZWD9nZVBsUEZIZEE4MlhudlZObG0jK3BxCnplITAxIztNKlFYTzhzPUA5WTxhVEZB
PHklM3dteENrOzlUXjt2Z3hxRDx3bStOc096KkBqY0l+UDxvQ2VjYCRnKgp6SG82dk1ZS3d9Smgy
X345ejwjTE5PXjNBSkZyfjt8aFUkd3tpS2NxMXQlPSN1VjI9cj5PR3RTM2FhZXc0K0BvU3AKenZQ
WlI+S1doO0pEYnZkTlo4UCFiYWBWeDJeaj08a3NwJFFGZ0FYVkBsLX1XR01YRWQwZU5heH4rcS1v
YVhVQkllCnp6SCM+My0+Y0FFNWM4N2sta0xsY2o0WFBnJiNafnpwZ0deQipaej9DMDBhLXdqP3RK
bXZoSDw1ViNrV1k4Z3QpSgp6Z34xSTxURy1hOUE/NUsrTHJmTm0jTnx9UjxFcnBTalVqKU8pbUl0
X1FQUmR3blRLYkx1SE5NcnlRPHBGR047QEAKeihZOFNXOElRPXktMiljbilXNWYpb1R9KHxScmIm
QmBRKnFeUEkjIWtQUSZJezd7XktlU209MkcpSXBGUll2QWIrCnoxPT9YTCpUNzA3X21BfUROVWZr
Qj1sNEdKJk8oV3VKa3NIU084MFZ2ZDI+TVctMGFwYjB3XnFOd2ZrWFJBPT1ZZgp6NntWalQxNWpL
dHVZaGQ3eFJFMzgqWEA0R0VeblMjV28raSteO1p3PUs+I1Y4cnI+NyVvc3s+S083QkF0OUNma34K
enl9VERlbHxsbmt0ZWdsZzB0O0UxVVhWU0FfRStRa2JpQ3lGdF5uX2UkI0paWT1JOUB1eXk8ajE0
K3s/aj1yfHlNCnpHQz0mQVBoP3thcEtzISVSIXA3YTNrQjZMbkBmXkJGdHsyZzVgKHl0JmEmZ05Y
ViZvKXRrdXhBYX5OWVdrbEpQTQp6KyU5cDxOVUhMV0xpKXM0amFoaDJufU9+SDFaV0xSeTBYdWJB
RmpNUkF2Yk9NQD5IYkw9PG1kaHc4KUJuQypqO2QKeitZVjxRMUpIVEI4YU56VUtibGFKKEZjNj1q
PyVYU0w0MkRKa0hJT2RoYWMwKnhMMG0/R1V7O3YtUF95Y0ZuQD43CnpLeEFibit1d3NneW9YVXw9
RFgmMz0rUERQPFQ9VzhLZnJscStqM3VPWns0UyQwJVZAbnBoa3o4VTxxdWEhVWJBbQp6cFoobEA8
QmJZZk5MWVdnTUQpVUFrYy0yYHliWCstSCRBV0dmelA2N3xBcj0jWn55YSZZWT5TNlNma19jV25R
fDMKekxTMFlxek1FKzd5KlE2NGJRb0JseCprPTNXKiVMdTFlITVmVn51RzRYa1luSW45fERmUSVg
KlJDdWN6SUktcTZfCnpzNXpUX09CZyVmbG1hPE5qcmhFRXQ9KmlDYm1CJXY8TzV6cE0xUWU7WEQ1
bXheWmNJfj0kSF5SK25SKkZjeD88OQp6b2RUdmFpb3V6KVUqcnNwQjNlaE87Ymg9WiZxbGdWRFMp
ckxGciZUPCp0T1pMTilVIy1OcCp5aGJwYFZHXnI/MEUKemREQWAkJiNpTz4rK3UlamUyfGNNMk85
OT58MmBERCQpME4lelk1bDhKejZqWUhhWTcxSi1DUW9fSF5YSj9VQkFuCnpUbUlSbzFHQDhWUXRl
dSlfdDlKc0U9Mkg9aDs2ISZ0PTlmQl5pTTNeeCNocDc2VWV1YldFZzF2PzttU1A2cWpqPwp6SClw
TmAqY0ZZJiNlcW91S0gyYiVzLUVge09XOXRBJlVxK25RVEhGa19iR1J2e0BKWmUlRCVCTHhsPjVo
cDV9YE4KemB3NTZQJn05KV9KTUppe1FWRW8kMmshb1pHQHE7dWJ4KXRKbV5iZ2pQV1o4RlFhK19M
aDh+ZT1NQHMkaExfLWR1CnpAI24oVm1YWkBCfEZfc1BvN3JzelA7P3hadSRmN01VMD5Fd1NvZ2pX
RjMheSZNJmYqcSNTMF5MQDFEVUJZfmFINgp6dTBrMyZUI1dxNnMqfVRAVkF0Vytve0hIV1FAT3B1
RWspb2IlZVNtJHdpeDd5bD99aTxtRWY0NCE9bWpAIWtxN30KemAqTzlacVN1eGZwZndCUztASkFC
UUw9ajhHcihpcmteX15nPmRiRz1kJVNzMTxHK3FzNnhaVE9kcDF5UHApP0pOCnpPe2khJkB1MTFW
KWlkdjxreFIxUTYoezZEd1ooMmtAeD4rST9AWFgqVHwjPC1FbSp0O2F4RyQ1K0IjOFgxM2JEZgp6
TDM4YipGNWluYnEmUTs7XyY2TVFURlJke1AzIVF9dSRKRDNYKl9FQTRIZ2BqcVZte3xhWngyMFBp
WDxofDlRUTEKenlqK3N0SzYhbytqMiheU2xAK35vbF9XTGgyR3pHZ0Q8JnBtJCglOT9KIShlaTB8
ZEVONSotY3A5fEg1eDJVeyk3CnohTko7O1FveGp7UGMrNVAtVHhaRCFNIXgxZGYmIURQfTNyWG1s
ZG9wRjJTcE9vT3BJVlI1KSs7Xyo3M314fFhPaAp6PlpLYWxjVytRTElLUTVXbl5PRHZJfTMpd1NC
RzVoZClAOU5iNXRnXzwyTlBucTR8cEJDblNPWGVLPHspYmF1TE0KekVpem0hSnxVTldVcUNybXcw
YnBSKE5fKH0rOSg1akNEfkhCO1FkMFp8RmxwV3Y8PmxwWFBRZX40cHojb19MO0hRCnpaMSZkbTgy
eDY7JXZfQT45Y0Q/I1NEU1F6YWliR250RFRoelFyPmpiKWVgeyohT1RvdVFpXnhMeGtgVTEwans9
UQp6Pil2KXYxRUoyKCRGQzQhV0d2Wk9Pc0tmJFE9a15ONmxkJTZHJHQ9OHNaO3VzVTVTKUJrNUtP
UTxKdFpjVSgzYXAKeld6cGRvOyVKV0FmTyk2QjI8MVZzaFZpK3E0bnQrViQkflRvKlpYfSkwYDwj
Jlpja0VlVHB5KzdtelZyVHwyMSV2CnpsUmxTSUk4VTZrbWEpUiFodEJidilvNV8xWFdiZCVLUEBV
TnArS0pjLVFwK0tONU0lRiRhM2FWIzQwYlF5WXtRLQp6OCkoZTtuaTZgPjRgek10XzV1dnxCT199
KlRHM2ZnJX1uP2NxSWY9Wip0VW9ELSU3LUZUUlhDTkcjbyl7eXFSI2QKemVQRE5EKXVtPnt3JDxt
aWtEbkM0WUp8ZXNWdzl1NT9ObFByMisjV14ock1ZJShlRVk8SHQxIWpDPnQwVHl3TXV1CnpJTTkz
NTV3R2MqZUhfbzgmPCZqNUJgNCZ3RTVaeXI4fEN8REV4UElONFZDbm1JXlZMP2JXNzEkeUpfIX03
WllXWAp6Wkg5TUJKeFZTfSM9LVBjWXZVQX1eMjlUSG0hT2B6Vz9LWHYoKzk1WW04SWtMWnZAUUF7
KiZWPm5MNjhyeiopTDIKeiNAb3pZYGVVSSpSR1BPOG1rX0lPRDZgTEx3WXJ2YU8kYXRMVENycTFk
YXtMakFtJjZXYDJUYyR0flhGKFVLPkB4Cnp2S3xnZXA1eHpzMXpAVjRKRj0kSWltdzBuJUBEbTZ2
YWdiRUw0OWtLUXxEZiskMWQrIUgjTlRHUk96aypLYVh1Mwp6cE5xJHJreXY+VDspb1ZERW8rYjBA
OHdwYCFMUk0lJFI8IzE3cHoyYWNwa0xZO3hLc2dRdytaUmBqYVIhKERTekgKelU9UjRabkJCemNY
TG1YOVlLfXt9Qn5BLX1WS1VyfiF0V28lUFl1VWRZI3ZERjd1KHE/cGdIX2pMVGxLKz1RWHZfCnpz
IyQ+IVlzSmJjPiZFVUtxIWdGYlNSZVk+RHw8aC0hJH5sclJlKHRaT15MZTNPXkJjeWlTNGA8fEdT
UjlKc3RaUgp6I1VLPGVMdXxtRCFWYjE8bkRvY29KZjxTWDhLeD89LUFtSDNeQ3dGbUgrREQ1Sj8y
SDxoQGQlOSpVVnsyamBLV04KeiRpNUNrMz1gKXYkcVpRfW5+U21OVVZicFN4VTlmQHd8e3dAaihx
aHFEMkhjVD5GOSVRZCZ7UzNlKk4zUGtTRldMCnp0WFZUSE4wXlR2PFEqWV8mVkpwfXRueFhyKWhn
KEVKcCtXP2MmQDxgPElAeHw2SjxMSzVSRWp5Ji0+aE04dmV0Xwp6X2pWOH4+T3tFNUlQOFkodE5H
V2wmPmVBWGtiYjheJFkrQXhvdSpfUXVwMl5jOyFZQ2RCY1BUKmdgYiFXMz1AI2oKejhmZ31yNjww
Y0A0ZmJ2TUFIeStXVSF7JEl2KjU9aG88RWRySUtkYVloOT0pYURXKHdYQlR9UlE8OFFeS0xQfEcl
CnokczA5VFBWNnQrKzFIPV9sJEBScnAoZVcoN2l2bmlvY01ed0UhVHRPZXpBU2F0TzlsKnhVNkl6
OHpRcVhIaHpCSAp6MmU0a34mRChadHUlVXF+WDA9dmxFUC03KEdNZ3t6UCs2aWc1OXhTMExDbzFw
UmNoSHVUWEdsVjRhUVNEKjRndj8KenhAYXUlKlczdVRxa0k8TkFRQDg+I1BpSER1aypGRmVwZG0j
alVpdnJIWiRJNCYtT31LIUdyTV5zUi1VUVVlQ2ZVCnp3VmJ1dEN3Q3lhV09HemFySkNCZHBzKnFh
eVEmP1hNdiZRRDZVbUliWSQtdFkkQ2I3JWBVZWwpNDhJSDFAT1oyVQp6TUl4Xz4+JGFfQ1NoeldC
ZVEheS1XT3VuIyh6NG53WXlnUGVGcCg4R3w0fUNPWCh8Z3xWKUtmXmBLMVN8PkFCbEUKem9KfWB6
Jmw7ZTdYI25yajsjd3g/YU5fKC1wQWsqYFMyMk19TmJ7eE1PQ1dYVzxUQTNVWC1VcDhFYGJEZzBg
akM7CnpXKiVqPTFiY1lMITkoLUtLZiVkZHB3UmlDdVhQO2FBWTEmYykjTXg7ZDxodGxXRnleRCU8
Z21vcE9ecntgTihPJgp6JEcrVWBEcmx2fSomamQwJiVPdF9XO3V2bk5feFlyQ3VaSilUQ2ckcCo1
dDAoNWpUdFRLM1NqNGd5SF9TJmEtMk8KekdPdXNra01mPkJnPnBqSF5yPzxkPEJ4WGs3cytnMkls
QzZgalY9NFBhb2dmLUZZSDVhVUNeVSZUTSFKY19XSU59Cnp5fGdobDxIb043I2p1fjw4UExSQXMy
Nj9OTEAhXyVCSHJTVUhFdkBPelNEQ0NpTkplSUc0WmVMblJYLUdoK1JHUAp6Ty1fWChgNnBAYWlP
fmh7U3ArLSU9MSlHZXpodipjSVFBKGNDQ3ZQT19GJXleakR7Ym5IUmgoaHN5NjtNYXo1U2IKejYk
YzNtQnhWTWZAdSglP28mTSFYRmlZc1lCcihIMGN2SjBtUEB2eEJiUHsycWJlZ2MwWlBGWkRmQ1Nu
RWU+VlBiCnplJCFTdkQyOTZ5QU1FbElWZ0YxO0lyRF80R24wa3IoKEtRa042YTxsXnYyWVpObns7
dndgQilaYjl7MVZeKil0Kwp6I3FsaCtreFhyKFFQe2xue3F4PTNsflAtI0VZZk89S208WUZlK04m
TjQkU0g2bUwtRlJNUkJUPFlCXyorJFojdXQKenZvUkt3WV5zQUw5NkdsQHljRC1SLUJIV2M7RElF
RXxGcmUhWXE+Xi1IX314eiR0cU53O0x8V196d3BVN1N0ejJTCnpPI3J8ZXw1OU5NSFN0QSFHfnY2
cUs+TyE3e0hJXzBPbn0xOT4tWXlGT0dvWl41ez99Qjc2c2ZrUCg4UDY2NSs+Ugp6KGp2PXZKbzVz
dGhlJU4mWFFsYUp7Q3YtVl45IWtvMWIxWCtRXnFVLUw9NyRMRyQqd2pJSSsqV1p+SCMpbSRVeG4K
emJtRGohQWl1Tm0jPHJ5TVhQVjdadHVPMmV8RDJ5djZiVEY3ay0xLUYtLTckZjteKXU3TFF5bnBP
U0NQIURXUStqCno2MXhfXkAtKGlaPmZJcileTzZBSyhLfX51N0U3TXZzdnBkTzM2QHdiS2V1TX5S
cWgwUmlAPEtxTXItWFYpKE80VAp6UF49dGB4QTxIMiN7TDVnZ1g0VGpYd3JAaiomSmAjeXdMancp
K1c7Z2lZTlF0TWEraHFNIzFTITxlazJpalg4a1UKejF6QmFDPig4fGJCYz95QzNlUk8yYUM8ZWMk
WlVHT2RHPio9WmM4eThvbDRkOXM/fXN8eHVQbEFAV1Q8PHB3ayhnCnokfDg4VytpIUs4V1cmPCRs
TXFnamRxdjRVV1NgWChLd0o2RSQlTWw1JnFoPlIzem5AXkpSRyRgU2gjfkE/O0Y7JAp6T1IzV3JF
MlNfYSVLZTJaUnwlU31JcWo/Y1k3SiNqTEZ4UllgeE48YUF2fUQyTjQrM0s5Tlh4VVp2REFhYlZK
RUQKeil4eClQRX05PEI4dEVfe1NWcDVCNSphRlpwVChrN158S3xjRUlUYDIreEMpRXRGPCFNK3d0
eTtKKUsqKy1kQ3JpCno5eD83TmUzV147SUMqTCgqfHMxVXlgdTJeeExUPEtuMXVXSnMySDZQdUpf
Vj1NU1NWbjkzNVNFPHt4aD9KU15megp6YU8hUTNmQiMzMWN+TUUwLWQrdTVHb1N3cFJLaCVrVyt9
VnZHYXBfM3dXeDAlLUItVSkhUXZmfG59KiQ0RXh5SUQKemApSkhJVzdXUEB0KD9QQCpuNj9jb1I1
bHk3S3NleUZpKSQreVohbTU9MnR6SDtmVCsmUURFIWFjeCo/YmhNTjdgCnpkOTY/ZTUrNTg/dzNN
NF9YMT4/bmN6a0QqVGZsUHxqKkpKTUNrfSViSlRBVTlAKndWS2VkbDc4NHhjSGhyQDBMeAp6PElu
Zl5CJSV6MFohOFl4ZytDSTFaRWNhPCRAVDtyP2tJfCVWS05rWXdKcisoOXJ2PlhjJn1oKjdUVWhh
Q1F5PTIKelJCOT1aMjBFUHtgcG1KQ18wfX1+I2YpTDJEQlNIQWI+LWFDYWJIb35ANWVPcEpEcjNy
IWFKaGdpcXJxJGBRQ2tXCnp0OGF5VSpzXzZjdEw9fDNuKFBLJkZGQS1gO19kSyZhe3NPZSN3KUF8
NH54X0IkZ1VecmtAVFVycFFMTXY4XyU8YQp6NT5IIXszOV97JTFxJTt3YzlIR1M0bUF5SFNoRn5+
RSRHQmhBOVZoPDR9P1VWIVFsQHZIdzlCN0ZHUjE/ZyZyP1oKemZhNDNYWXQ0VHFCTW9zZllidn57
SUA0S0lDKGUoODhwP1RQSSVfdE1HWGV5cG15cmYpN2U9ZkhPWU9Hb2NeUzhOCnpxR0NmTCFRLW5I
UkY3VTVaJDQ+RF90JEtARCt1LUY5MWEhXzt9WCp8MShnNE9pYSVJTjg+TipqREpDO0pqRjAkawp6
Jk9mPUx1IUg2Rnhedl5jQE1FezxVTn1eQihGY1EmZUJ8TCVye1JSSkQ5PjtFZEkqP2U9d0xLcTBs
I0xzLXFWYTgKejcmenJ8P0ROQjVLVmdsM21kd1hPXjs1I1ZsTHdGZnVhb29lcnV6Uk1gMXsoNVlt
YmIzJV8xQGkqJmB5XnBYfHNlCnpCVj1TfVRfWnc5QnItIXFYMl8wOUhyWnRGODc/MVdVKyhYOWAr
V2FgLSNQYyhiSS1aMntkflRqdWpndyNBN0dVIQp6fEVTY18pMiNpU1ZZfVY4azE+NlhnPnRFaF5J
PiU1JDxEZFkpbj00KGtyMTE7cnhHZGtEN3tsOFgmRVBEWXI3QVcKenclQTs1O24+OVUlS29QNXBp
e1kzYGo8O3xUNSNqTDxsR21kNzFMTS1eTiNLc3M/diExSH1mSSNgdDZfKE1RITRnCnpLP2oobyFl
QWwpMl5tRGhsJD4la2dabj02TE5jYDluU29OV2JFOCRzQFJ8biVQVzFlXiFxfDdJQ3pyYGc+MWVo
egp6UmpCeX5iTmVRVTJ3QWl3S21mbn0rYWkzR0pRRXozZWhkVkpyeWhKMjAwLUJlNVIjWGBNfHxY
XntFYXVnJCpUSHEKekw1KkRCMW9XYHE5Xll0Qi1LdUdsVzRYTGwkP1BRWFgjbEc+RTM2KWQrUHpC
SnAybylReXdDNlU/SkMjIUN6WE5SCnopJmNIb2Awd0lZUE5ya0pWbTwxR0g9M0BqS1Y3TihpPDFS
R3JGemRxRDVvOFI+Z09uQENBT2xSI0J0QV9HbmE8Ugp6M30oQzFVTndNfEttfmtMYlhMPSZXcilO
Wl57JE4tI09fO31HYCZHSml9bnxPYjV6S0J1YnJ2c2dleVdfVmFvR3QKemg3YX0qMUkyXkU4V0wh
cnMrZEdHTD81UDRZXjl9U29Kakt6TCNxY3ZXVSRMP2hmNXlveTRsPCV5ZSorN15pfjdKCnpXRmFD
VlkqZnN8Rnh6RypMTWNRbS1qWGhINEhINkN1WEhELW5YTE1XWUxYP2tSWDFfeHVPK1deVyVCQXlw
STF3WQp6ZlQ2QXIwU34wd3lRb2Qrb2RZbzlqSEVHPSh+aEZ6eE8zVWVNbF58WihQMEMpbiNyQkNS
SDx5MVQmeFV1dTYlTHEKelBLb3Z8cHNZMWMjbGZZKiNfcEtnOGBObXRHNXt9ZDMreD5xIT19c3E3
PVVfOVIodktgbzgwN3BKRilVcnVqMHpxCnpPMjJ7dz52NExqTVR8WXc8Wil5Y3B1Q1ZsUnFle2hB
ZWFUKVRTSihxRlRWSjNMdjxZTjszYVYyKWR7ZmJzbTJQawp6Rl40JXVGYD0mI3soKGMlc3V1fmdO
cl4mSXYxPE5QeUVTT2FKcEoyP3RweX1MeXRtU0RqZm0zREdfKnhoOFB+NmYKejYrTlcyU3dtZDY4
Rjt3Xj9oTWJVaHY+MFdiNVJ9R1hETD8yJkV5NkxEVVNQMUI0MElGKHRfTTFmKjdRJHU1c1pfCnpi
Kj44YTxpQTFtVHI4WGA1Qz5WdnJLYjIkKF5wWmthUTRFU3pAbihyMStmJVlPI304PV9tTnpzYSNT
emNDbCMjfAp6diglRDtNN0V4PDhgKTRCcXoyRVhDK0hLUjtPcGZhV0YjM35zbj1neVh3OW4hdjFh
YTdUY3YodFE1JHlAP2NXWXAKejdLNmAzXnhfbVYxIVFeXktKcHRnVUFCQlM5bW9Gc04kWD04MTZu
MCYydTk5UFglUSskZmExNnVWaE95WWA9MUUkCnppT2RDMjNhM0BwMzA9VzBtYDd+Uk07fWJad3NY
SWZvIUF3Z3NDaEU1RjJhZ3BOV1YoYWdtan5vUmo3JHoxWXkmcAp6a1A8Y0JrRlRHa0JDbyZ5eWc1
IXlXdndqeE82fDtSLWNvfmRiJG5XfmJ0QkJ0KG5keENYTyl5VWkxIWlHPSM7PUYKej1CdDcyQFVf
Vl80bD9Tbj8/Z34xeGN4PXV0K04zMHVAR3ZIZ2cqU1RaYE8+YWk8bUc9dWBVU19hfjB1fCEwN31F
CnpGLVNgPEd0MXY2YHBRWThRcVFKXkRQX0Buc1pJaVFjNnZoOG9VVE51Yjt6U2ZeZ0Q8NXs3WHd4
ITRNZCFOdWctMwp6UypaSHpidXJkcld6eU8mZV55STNxQH58N2R2I2hsWEAhO1goayR2N3p4cFM+
UjB+U3dpIypUYTNwfHlKdzc7aW0KelJLXyhGIVNINXo5aT5oJCtIVColPDFUKm5KJHVUTmw4fVNQ
bSNIdiUrUHc8ZGpebzhEVyF5Q0ZhSC1kck5WMjJoCnpZdXpab1lgSTZHZk8/elktVkpOQTZnaUNL
MHlsOXQtd2NSM01NWnEmTS1hcnptUnAxbGhTPXMoZnxKbktIeng8Mgp6eld1bzZNM2VLNih9Z141
RnF9NlEmS21gbjNXeEtDQmdFa2Bwe0ZWKSskPHswRHFWNEdxPiNiUWR4M2goSHpBYj8KelVARCFa
cUd0OXdMeCt1dDMwMUVZK2whYmtoXkVYWntkQ29eXmBVSUhpcy0tTHZgPnxQJD17U3NVTDJOe3Bx
VFllCnpGX30jKms5TyZyVXlkdl9GLV5qZ0V5RE9BVlk2Oy1DfUJgVWdySkU/PWRHaWpjezVvMSgm
KER3V15DeklkPzspcwp6RE9Edl4kaTRMTEJTTVZjZns3bG5TUSR6Q0l0UVh0MHE7ZWw/STl1PEVs
fjspSUpPRWF4ZjJaNjhsIW4mMDNMU08KeiQ5dTl7WHtvOV9wIXQ7O0s+YDFBb3kmQzNBQUxQbk0/
LVAtQElfOUBPPWd2UXM+O2FjNGRoTXNWeUJjTztJZlYoCnp3YUJxNitZPlNMRTxZelNoYihiJFNx
K0BXZWQkfCRQfFdCRWNLUlR5JmBwR3kwPkVffEleN14kKn4kfDBneDFHbwp6QW9gRGlQKDQ5K1oy
bFNYaG1VJiF7R19QZXJIKlFLU31eRFU3N0AmSU1GZTF6QnRVRmhyKExHNlpKSlZvQnc7KVYKemIw
JVp2UUl9YXVjbFlBJWZHSzgpSX5wMSVAYm5QXkdTcWJ1XiNsJn1fN2VVRnBIPCMwQnwkSm4oZmpS
JnhsZjc9Cno3YEIpMihjWExzTitJZXV0Nj1kRCZTeVAte1lrb0V5VUQwYyF+PTIpPF8/bFl3fHly
RUZSP3g5ZTE3UHlqOVpHbQp6dWJ+SGx1Nm5SNVQzN1dBIys7enxkazIyUTAyJWNmRzQqfSskO3wr
dVk5UWooP3pKa25ZUEZiKVZ4fE8pTV9YIzsKelpKZyVTJDFIUHJYdSpXXyVgMHcwVSM+azwkeTl8
Iz9uV35uRnZxa3p8SlBJc14jbl8/UkI2VD1yWCEqQk1saG5HCnolTWNYKkhSWG4qKUZsdmFzbjJ9
MWc0e09SaEpFUHg1N2tFYHZeWGoqRjNAWU1rdmdYaCU2JWBBX1MwMT1xWCpWSAp6YmFMVEFzT1U1
dUNNeGpMKjhQOX5mXmtsZnc4Q0QzYzBDI3VGZl56aDthYVM2I1lFQWlrb1orKWUyPTYtV01ofDgK
ejB7VkVSPU5Dc21PZmp3QXdQZW0ocUk4VzlGUkgtekFlS19fLVJTO1d7fSQ8b1B5NVdqMFVxcD9P
aExpeVY/MkpWCnpUZXhFNHdTKFgyckh7NGUkV0IyPnI2VSUzeygwMSljYiplU2puQlpha2ImOz0+
bVdpIXY2K3JlS0ZHey0pSWo0Vwp6cXFgPmtFI0pRWnpgN3ZiKF5fMXVAZl9uS3RRQFFnZVZlR1RK
RE11NEl1Y31iQ2MmM2E4YSt5byoxTmtzXjVwXkgKekpAKyQoY29QVWg8eGVnNyZOeClzOUUqVmRk
dkZ2bjNWY1dDc0o3cX5TNzk5R3xLPH55Sn1mcSkjQENOQGtgUmNNCnpTeHAmeFYrQiFyJFNzQVFS
e2ZOQUlfIzEwdUZ7VWA3QGxOITE1JnxKWlB2fX1nRXV5ZnpONH05UTFOP05Ma1ppUgp6bW90ZHwz
SktRUmdrWCRUNSYmPiU/Qk4qXyVHTnsqMipCbyM+MCQjV28kZGFQMEJgK0ZJOTtzRndoNlFWeyR4
I3EKenBic3tPUl8+M2NDbmx3Tjg4IVVraChNKENCdm9gPGgtamBfc21hQktVbW5jOT1nKTM9QzFL
RmAoIW9VcHhKckJWCno+VW9RRWI8NHd0WC1QVWJoe0krezI/fj8xU2w8ZCNAV0YrU3tXJjxIRmt2
d08hQDxRdmIrUG55WVVFYkd7MkJpZgp6ZSZ+cks5UiFLPnJycEJyJGU0Tn43fm5SYUJ0Uit4T1lk
PH11YihNSz99WXIwcTlISDRDRERyN2EySG8+dDZOYSUKemJBNmojUE4xdiMtRmgjez17aiZvbHd9
cC1SdkxgTXt8ci0md3laR21pJjFeZGg8cGM5SmlpajdJe3ZJR0d3WGNJCnpQTUF7ejQ2cWo9TzJY
O341cWIpOVFyKXU5eCEzfU5qfTMkKFQ0Mj52YD0jJlJ5JGdLdV4kPDUoOT45I0FtJiVlbAp6NSp7
NWp4RC1jP2tFZ3ooTjNVbVl7d2R2Vyk7RXFUOGVofms3fkRZP2B8bkZDJXl7R1pZZkYqQk5fPTUm
SCNRdHoKelUlOXBWZz9GZCVUcFlxb18tfm97WXdsUm97TSRKPEl4P2IyOW1YYXIzbCNIJmp0RGs3
SXg2WWs5SEliUT8+fTh5Cnp2KEd3VG92MnVvb0JkVml0fVYmZCl3VHFwbzBHKXJUVmUtJGJDYlZV
VG1MNVJ7THZsYypFMVNeK0JFVmQ1bThXNQp6KGx5d0VQZ0k/eyFKP18pdiQ2OWdSMHBUSHRxTyUx
M3JkezZCMzZeMWB0P2clajwjeih6NzQxdkx6e0RUd3kqd3YKellJWDg9JitzPHVyXk45R3dpJCZx
KDJSQjJBRlZYYG0xT05hMFd9PlpGbDkzeDlNVihWKXwtIXYxc041ZGdVOXlNCnpGK2cjbDU1OSoq
UWFhVUBtRihUTV89eEROSzJZTVBQY3whaTNfQWZOVUMoZSpQZSpFfU8pTjt+dilucUgoTTRhfQp6
Unt3bnApVDI5TWAxZztXQ0p7NTJvOHM4U2dFKj9XcHs5QWhyWSt5TiVGND5WMSpIJj49Q0ZVa14r
UnAjJUZLJHUKenlHJHhlcnN2R2leOUhqbF89bGIycjhyI0spWEdxZUc+R1hRWXk/KDB4I3RWSmAm
TzkoQGp3SXtJODhwe2hDKjRHCnpnZTNQYSprIXlqKk4pRWljbHwtQGMtdk48VG00KVkjclpnUHY1
cy18NmtjRjc4cyFzPzArLVMoYVBObD09b2E0KQp6MDhMVzgkcjYrQVcqOHd7emM9SXVKS296KEtl
K0AmTWhpRmtfJGV6ZHhueVlEV285TS1iclAjRjZNRjY3KDE7dC0KejVTfTY2JE9KJSlIQzVqXjtx
OC0/OVJONiphKn1YRldhMEpCWDk2UHUqaVJDMiREa2U8NyF9Xyl7bT0pKml9aF53CnolUz9qRG5I
QGBtUWs9bH1VKGV1K2E7PX00ZTUxelpIWEtHeUNrQE5UdnB1djMqaDxfTVh3LTFsWWtlNzZNPDt2
Ygp6Pz9YWVVlNz5AWCo5Zl4pVlY4I1VOcElMei08bXRxOyR4cUZpfkBGLVRgME10I2shMXN7eHw1
KXJHRCRPcnIkLXMKej5yVVJXMkVqa2IlPUtIbWY7ZjxWZHU4P1RPd3NjUUw+JWNmSitSQTNzPzxi
MnZJcjBaX2N+MSpwa0ZlZTw/bXk8CnpDQG8wd2BPQnV5K185MXl2c0omVV9Xa18pRjYkOGpsfndY
LWNxRGZGSFYlWEZvfj1RMlcjak56bD5xRTdtPE8wJgp6LW5hcGIqUnpWTFhUO1kqV0JKZnFVYVYk
OVlxOW10eFpmRDRQOFlSR01LMSgyJGJVcHtlQGF7V1daQ2lpcWYjI1EKemVfJEcleilIJTZIYmJS
amc9fDJpVj93Z2RSIVpSKXF6biNwT3xBI201Sjd2Q1EmbGVMbDhPcXR5U2YwIXFXNm5ECnoxYSo0
KUxYJW5IcUotKHVpKXtweUB2PG43Kj4/VF95SUY+LXBUbF5lK1lOd1JeVWI2e2tvJEI9SE55QUwh
V157RAp6PzsrUEYwdk02MmAxTi1+WVl4NWc8P3dKT3dgSmo4XzluZyZFV2ktOXgzXmI0NDA3JDZT
aitJOWVGMnItOFBsaVcKemg5R0sle2h6bjBHdSYzNlN7JUxEJSg8SFFXIzluVlJoeVRDX0YtY1dT
cnR5K0NOe2R3YG1RfXdxN2UpRjtHK3RXCnpqMCV+NFRmZ2pSU1ghVWcoNz5NaG5WfTg9cGI2aDFi
NiZOI3Q3QGpucE5DKHxeNHwqNUxsRmxaPHs1KHcyZU9DYgp6azh4dzsxSUgwe2I8JClaeF89PWBM
dEpEODh5Z3p+PDBKcHA8MT5gPGc8dmpQNyM+MGNGYn48MktUOFVgRlhhMEQKejhVVyU2YUJ0bysj
JnZ8Nm1MOCNYPFdFfDQtbFhxWj1xcW94Rit6fXtyKnNCfU83P2l1UTVKREBmQk9vTXtpcFdkCno5
elR8TGl8VVMma0lkRlFxYGU3c0ZQUlV8TXV+I2QpX3YoeCNrWGckPUs+Q240S2kjN3Y0MmJWUC1I
V0pgIXI8IQp6K0EjfjdGPTctbnt6fEJyR2EhITlEOHNMKWZ+TWM+X3QpZnVjOVM8Wkh8bEg1TTFW
VWE2VlZifEgraDxRUzs0UlEKejZPKn5lcGVpKFlYWTg5bzh5Zl8xeEd1JWFveTw/KVR7SFd+JFl7
PjRMWD9PYUk5QkJvUFdpPmZuYGNgbVltY3ohCno1N0I0PiNqayZ7UEUoWXdMMXdwU2VVQG5ZV2U+
SjsqKSFQMTJraSQqdUh5LXNWMzl0Y0pqaX5hQlhfY0JmbjgqQgp6QXlebWkoOH5JKDR9fFQqREJP
NWpHaUtwO3VuLSVvJjhpSDEwdFVqdShXdm43KEB3WEpFWjQ1e3FxIXAlUkR4dUMKekskIX54YklE
T0tZMmQrUlM2O2VAcDBhWGlSdklDZ2NtbmA0MnZ8cDw5YytIbiQ9aGdMPENxPi1GT3NqQTJCb3lV
CnpTJjl4XjIqUkVIWGZaZD5EQURDSiE7M0FTMEItPEJONiZ5RG1Oai03ajwjPj4tVDdhUiN3Ozlt
JT5gKGVGVm5CRgp6K2FDSUVPaURvYURoalRYMCoqcEcoKyVtaGVMKEIqUnU5LWk+STEocylNMn0z
c2wpYC1GbjJNd3dqWG5OO3tUV1AKemJSOU1QSjhXIW89QT0jZChldGlARl5lLSFDQDk8VXo4WEkl
MW15PkFtMzNVNV5fdFFObmk/THlsfi1OTyNDdzVuCnoqRkV3T0Q2V0dydTREZktXYnRsbTNjUkA2
UCZqdnV7e1Mja2U7c1UmLTN+aEdOan1mMXVSa2w9LWdlRn1Ga01kdAp6KjxKJkAwWj5YSHs1N1Fp
emhoJVItYH5uKFEyYVJIWF9MYlMjeUFCVjcmTDVSbSpNQkdyZ21teVpmK2lMUSMmOUkKelg2aEJk
cCM8VypgYHwmI1BOeDR9V0VRKiNXQVYxPD5+b0c4JGFXOWZWN2cpSShSX040PURoUiFjWEBhVkZN
QSlUCnp0cUdXcEAzV0p+JVV5fWkwZWY4P05hNnc1MmZeXzc4ZzlhPGIzSkdhLSNMV1RUS2NVJTdi
bUM1LShLfmNXT3VTUgp6IVIoXnRDTD1IdFZxIyVVXlU0WjU8ITYjVFN6WmJ2X3t3VENnYm0oZmZp
YWh5TXFiTmcjd0JLOXwwSyY+PjxyNHUKeiQpeilheGo/RnR6eW5OTSV9bk40O0JpWUQrSD57Mm9p
aWFkcE5JS2BWRj9XUzUxPEZjIylPYGpaOUxuVW9rY2BPCnpsWW9Xais3OyRLQmg/cyhNbkglPUo7
Tzw2XnVoNUtCazN9TD9tPG1abGkhVHo4MmlPdVB3REtgKmN4KGV8SyE2ewp6KTR2Vm47KT56fDRL
KSs4K1l8KiNnfjk4ZjFqX21DVV81VE5UTW5XcWN2TlA2Y1VYTVB8RXhZRWdCYEhJRm4wd0YKei12
ITQ0Uj8oOSg8TX5+bWBHWGZvXmsjfDBHflMjKCljYkxFZ3ZgSEI0bmRZZ3k1NTYjbktFaSRqTWdD
IWoqaUNNCnojWmJUdjB0O3J8Rm5NeSVzTXxRX0VvYX41KGx7KHJtKERwYUkoalpSfDA1N1Iwa28j
ay0jQ0o4ayNWanNzVzA0Mgp6bjROdGpPMXJRZjB2M3JAPWp2dzY7WDB5cFpBU3NTcHRDSmB2aXhg
b2BhX3RYXjRhKCklcmMlRld3Kk9uJGtjZWcKemBjTUg+c3FeUT1VemgmVmZHM2JZOVFhPmclXlZy
Z2NnZDEqbmJrdCQmUnJ+czJNOWtiOHBhaWxLcUMxcyZRQXt4CnpqTGJiVEUwfXVrOHszPXZRLXMw
TD9hUzBPTnFCZWIhMmBtKWltTX1INGtMdTxsVV9ufW1XYjZJcmYlMXhNblokJQp6RnpEVmt8MiRx
NU90KSotakVwP0pKcCV5SUApbDhPX0o0PjtVNHM9Y01UVndAanVJXl97OHV1UCY3T0F8TElIZUIK
elMxdzNIME13RVc+YVJ3aFZgQHRxX2E9THJFJHk5eSZgMntHRmpgXzA3JXhDYShLaitgQGNSK2pG
JjgqeT9wO2hZCnphR0IlTGBlWVEwdSZIQUxSKWdNK0RURGBrY09+byk1ZGB9TnFMSngqX2YrJip3
IUNCPDkyfDVGNDkraV9oeDZvKQp6SjF2bURAR2MhSlJePkpZO0NHVGtZKjR6ek5qRjFCa3krVlp4
R3RZJEUqZ3p8YkJfcG5vMTUjcFB6WG04YUhpXyYKek5XM0RKYT0kI2RjN0QxTGZlZjRrdHtJRmhK
SCsrfiR3enxIeGVCP3FUOGticlNreHxsXnhQYj9LdjI5fjFebyNOCno7blpnMjBlZVAwYFVUZjw7
SFpXSUl0TVNRUFN5cG04eUQ1V0NjdWtKaCg3cmJCcFE1JGpWOFojQSlGUU5jWWFYYQp6STVhbUdX
WE00c2U8eiN6TiR1aHgwLSFTYXp5Pm0rQl5VcmNpVkYlaEQhRjQqYTgwRncyWmM4R3d0TTxAdSVz
d0oKelJ5QmwxZnVZKTI/bStsJFNaRFFuS040ZnY0Wm91bGNFYCNZIU5KdXtxZUttZXF5VCphSzZO
d0JNYChxITMzcF99Cno9fCo4U04zOUk5ZE4mVWc1P343JTBEQ2JDNEVyIW1wOzc2RHpYLUZlNmY/
I0JIfX1GaVNVQFNYKFFPM3ZHd31NRQp6a19wVHFae3BQJCt8LVFzK197O0NoSzUyeTNwUlo7aS1a
TEFsTl45fDNsUlNRSHQpdkM5VWp9Jil4R0Z7KXN7MXkKekpJTUVBS19xOTtLSEN1dDRMQFR2Rn5G
WDkpdzNIR0tHUyt1eWYoNGx1ZG93fEAwTHV3KTJTN2R7d2ZKWmc0KCp0CnpTPDlOZTFiVzdQaFRS
dj05R1JII2VJZCNBVVFZNWxiJlJUJVp+UUJKVlgqMFFzRHo2TDdMSnk4VkdkPmVycmtPZQp6MHlj
fjE9MUA7c3NCLVZYTS1yKGhweFZjKEh6fiQ8elZDMDdtIWRCPSU0VEx9ST5LNThQcylyKFNZbExa
O3lTPWIKeiRfNGN3dVEjbjEmKH0zQXslWlA2RlJrfn5gQzBNTiFRKXR8WkdmU31fQXpjZkohTTwk
MmFVc3VhN3lfT1F+XkJkCnpoVHJ6ZDNicj9gbnZMUG9PV1RnNnZNYWtqVz5JYXtmWFcyZVBPXk1w
UUB7PjM8cX5PREh7U3ojMmwmQklGO1FNdQp6JnxUKWcqYyQyYiRQWTh4MUQ5SGtoZnNqQ2U1fGdw
I3RpTjA1THFoU3EmN0F6Rio3LUBwRjNaTypHaU08YEBLVzsKekdxJWxvKnY2enBobGR1RjlsdHtL
IzNWUn1rQWclK3t8fj88XlFlb2tAR3szLVAwe1IxOUpKczFXLVJFSyhZTHtuCnpjdlpfSnUjTGdP
TD1HVTdBUVc9fnIyPmliYUs4V3Y+SWRETVgqMF8hI3x8JlI/RU1hUWc0bUkmcyRjd29XWTwrQAp6
ezNKKEU7Nl94PTIhOWs4TUw1Zz0wSFV2cFhAITBVTDMhZnFiQENuck87ViZQWipTXyshKzBWI05P
Z2M5MENSXnYKemFxYUZQNnh1OEBAYHFQX2gqeTA+ak9DTD1iWChRTEAxamB8Mm1Tcl9paGxYVz1N
IzJXR3R0WD1yOy1XMUBeQUBrCnoyelVqbE9+UH1WSDNlY09aTUBHYTtxPilsS1B4VjdeMUpUP2NP
NHgmY09LZTw/KCF7Nzl7U3toPilMbnElbkolPwp6QWV6K0FoUUZtJWxtPW9fS1RsbWNiJEZHKHsz
P2ZmJntLKCMkVWV1T2pEVXJMPGNtJU1NRjJfWV42bUVAPCNQd3UKenQwIykmOT1RWmV3TUhnUl85
QF98JV4hVCRqM2tKVSRlPDw2aTt+fWFCbnB+d2c4K0l1LVgtRW5kdnFFVnlnJU9JCnolYXVjempx
IVloSlRCbXpfKF9UYGZaa2VObFNyYSV7PiNAMktKTFB3OH55K0k7e1FSKEtqMjgyK29MU2kldnFp
UwpQO301Q2QpbUFDRlY7UzspSEUoPUUKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdp
dCBhL2FwcC9yZXMvZWNsaXBzZS1wb3dlci5zdmcgYi9hcHAvcmVzL2VjbGlwc2UtcG93ZXIuc3Zn
Cm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmI0MWU1ZmYKLS0tIC9kZXYvbnVs
bAorKysgYi9hcHAvcmVzL2VjbGlwc2UtcG93ZXIuc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1s
bnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZp
ZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZD0iTTEyIDN2OE03IDVhOCA4IDAgMSAwIDEwIDAiIGZp
bGw9Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNh
cD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlmZiAtLWdpdCBhL2Fw
cC9yZXMvaWNvbnMvaGljb2xvci8xMjh4MTI4L2FwcHMvZWNsaXBzZS5wbmcgYi9hcHAvcmVzL2lj
b25zL2hpY29sb3IvMTI4eDEyOC9hcHBzL2VjbGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0
CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLjE1MTIxYzA0
YmU3YTRjYjlmYjY1ZmYwOTlkNzQ2N2I0NDRjNmU5MGQKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFs
IDcwODcKemNtVjtnOCZLcWxQKTxoOzNLfExrMDAwZTFOSkxUcTAwNGpoMDA0anAxXkBzNiEjLWls
MDAwfHlOa2w8WmMlMUU+CnpkNi08KWI+TSZKLWRDQHh5THdkJTJfJl9JZ3BrO2dGaClSWmdiajhF
ajJGTy0/SEM3ZG4yaGxeOFNuOVk9OTVWIwp6Nk1yVT9jcnI2eSRtaUkyYTZGRlVJNU9pdmoyRk9R
dnp2VnBsRitgT21VXmtgK1RPZU8lcGIzKylvTHxEZlYjUmAKenMkWU12S2RIT0EtbTc9Y0pAPWUq
JnBsNzVGOU0rS2BgKUM2QnNWQUZoYDJlallTaypVYV49YloybW13SDdjYEE5CnpLKEtQPCUzIyYx
UlIrZkQjXkwzI3p3eFM3dElVbHotZWBiJD85WXVneFkoSW5aQHNsYCpTY0x7eHc2THw/c0hGUAp6
KHFXSUF5P0Ehej5aYEJMK3JXRDd7UD5weXQ1JlZASHtOKlQwbCM9WDk1d34kPis3P3RTRmlSfCY2
bGRtSDZPVTwKemxwV2kpekh4WUhfempoRWQxKU5HPEQ3SGRzPWdKfjtCY00kaChJSjNGJEhWd0tv
SG0rVkxKVk1NYHk8KSRJWUdoCnomQERmXzxyeHZGTyQqWjMqSm9DKlVoTkxjWDx6UmZSMFp6PFkh
TEFORTNQPGUpQX12JTlVZENHdnxLOG09QUU8Nwp6ZEF4ZDF0IWxeWEo/anlRUjBTZX01cmVlYFcz
NVlQKG9lTkB3KlRBbHo0TCRrUHlnPkhrSG0zZVQqdXp+Kkt4fCUKel58dUNhc1pAJGZSPSlqUlRl
b2ZmUjZkdSNJRjJINSZZPW5qdUJ5RXZgXzRDTWJKe2VnSGEtK2tSVFVIfjBAaGxCCnpSNyVfMCtJ
fjVBPyVlLSUkMzF0aGlKfU89MDs4N3EpJCpESVFQVnN6IXNWQTt7KzVrdipNQjg5SmJYYz1RbypZ
dAp6TXEpdX4mZFdJR3draTlBYkhGYEhsbVllWEg4M0tDVk10cD9gKT9NWGMqMGx5YERnJDdFQT5o
cmVSZWdrLVd0M1gKelg7e0doOzJZb1F7QCp2PkA+bCkreVJSI2slNlJxTzdeQnRTSDw+KH5fZzsq
TU5vTys1b09SNjIqTUl6KUtsfFYoCnpLUkd9V1pOO3pqMjRpYCgzSj9KQ1Jxd3AmNTF4UGFzcVlM
QTwoOUBTUiU0OChEZm9LaHkhUjU9ejt0eEJLWXorOwp6cispbTB8R041S1Vab1BlOFU/VC07QCpE
MiNVSXxoZSM1cyQzZEotK0VGdypCZWhOfDU3JHM9UXdwMzE3d0NLOXEKekBBPHt8Uk1pNTlHI3du
TzB0OHx0ekclZS1wV0QyNyVUMHgxNW8/VTJJcURrKT1lQFRyRWlMcitfSX19NDU4aVc9CnpgYUBI
S1NJb3w+V012PkNAcjVmY199cz0jbntPJTxpX1JGTTNSYkNsRDl2TjQ0PWN1S3A7JmFBSGdFcGdn
KTEpagp6b1FTeFV0YjlmNWR7NzFHPis3PzNiOWVsUUQ9KXJnPipnJnRsfWFVTmpHNUhiV1J1czc3
LUxNU1JFb0U1LWc0OTEKekZTeilfY1hNfiMqVmxKWUVCJiR4UHomYHdjPT1XNXpQTnRGJkJiRVRI
LStFdWgldj8laSQlWTIhOzliaztOQDRICnp5TCRDJWNRN1RHUD8oQn1Bb0FWc2V6KVVxe19FRXM5
dm0xdkw1ejVzM3AmI1V1aWwlaz8oWCVVYFNLVWV7PlZvQAp6R09WWnlxdl87UENSQmh2dXM9NCZv
cFopbkh9QmxHXklHUiEpN3poQnNBX0RENFVWMEE/Qjc1NSNHe3xeLWNSVGgKejl4JFQmel4oQE8t
cGslfExJM1ZPKkc0WE9oJV9DKFg/N3JEQk53fj0tRnZSPmQqfGhFMjMrMytRUUpmb3peRSRBCnpt
WWpDKS1hUH43QXZEOWk+NURfTEdrU1Z7YGBGcWktWWc9SnRRKEI3cDlTY24malM5UDdoVXA+ZH5X
MUNNVnJFKAp6LWRJSV9LOUBXSFReQzxeRGQ1TERneVN1TXZEVyVpUGRORzQxTzBuMVk+eGdUMCo3
THtYWkdDbl4hakpzPllPdS0KenU+endPcGp2dzVgYCoqSHlwU0p4diNNOGAhYW93UVVPazA7eyh8
PmlAeEVuJXVnVihPLXZSX2NlRDFRZHpxKTxmCnpqeFJkelZAWkQyV2Nte3VWfWR6emp7RUJVazNh
aysjdy18KF4jUG8hMkUjK1NjUjEmZVgzVCNpVlZyWGU9a284Kwp6cSFlIzc5NWdVJHtgSHk8ZHwr
dzBUdDBkMUAwdUpENz1VdUFibj98I1VBK1gqK0I5R1E/ei16UDFGJiheXzclPiMKekx0YVgzR09j
alZ4blMkb08pRnJaJW5pV1pjaSM7X0Zgci1Wb251U3w+SmYjQUFSLXVKNHRtc0hjTylTcT5ZWmFH
CnpVc3crTldMfFVmeXM/JjJzbDMjQTlrKXFrYGVKSD1SUGYjdCNTdX5MYU5nbC03MFQySzdiVTQk
OWFFOE9aR2FpQwp6Mi1Fa0BpMVNMaFI2ZmFBaSs5UCFnTWoyQ2NeQWpfPGJAfkFRUHR8TG40VEQ4
NVdxUHtwO0QkQ018ZmpzWD5GeWEKenItI3x5R2RRTkJsZ0AwR2JTZ3hROzhkeCZtfTByaU5VPXo2
Qit0OyRGaGojUnFOb0IwcXZ8cSFaS0ozdlE1NE5fCnphY283ejBzOXRzWm9UIV50b0x6T0V0NVB8
U05VM35qYXVnJmBIPk1TLXFGXzQmZURaVElPbHtEU3V1WVIzcD1fPAp6dDF5Xyl2MkFGOFpHKEgr
bUN2IWFUd299d1AqSGB6bDVXaX51Y3dQc0ozODZCY1ExR1RgWXV2fCNmc1RDRWh6Z0cKelZwXmVp
QDREOGtTPD8jU1VgKDk5WXUmQztvd2xNKDh9Vys+UnQpOCtMY1VsZSt0JFYjbXp+TEYlZypNS2ct
ZSgoCnpBPWBLQzxsZzY+O2Fsc1U8SSFEUGQyeDd2VHdMYkJwPE1nVzNLKG48a1BnIzA9YTVKK0Ff
VF5ndlg7O1dTZC0rKQp6Ukh1ejEybnk9N2I9fmpSckt1QF5xNm9zQyR7d3JlPT5Ib1QwaiNrVXFZ
NUwlQkoqYT89SVRHWmdiJHV8OT9NJDAKekN+ZXh4S2lfZEQqRlc8cF93Qy1zaCUxOXdOVG1vPG1l
I1FDZktOREhqSDtSbHpkR3VqRGxVI0YjfU9oeiUzOUprCnpNSG1EYUcxRWQzSDJEaGxSUUZ7bnhf
X29genZhWFIjVHJCR0okcnxUU2F8SFFlRDtkPkB1NmtzYTltX34+OFlwcQp6QDxYP0IlWnBGNXdV
fHB4ZFlCP0I7aSViRyludUY2QXV1KSlzQlBKKlFIZihKYWcyPSY9XiNaVzJyO0l5Nj01UlQKelBN
Y0ooMExFR2RNQEh5TXJ9QEdhUzg/cWh5b0VWTUNITHNGZUM1JTVgUjBadmQ4dzRnMX1VPGNSelVI
cHhJK345Cnp0R2I+c21TTG4pclc4ZUZRWHdzPTVEe3I7TUh0SnBQeWoyMk5JaW8/TCVpZTZ2LXQ4
PVM5NXgqNFc4TSt6ZFpkWQp6SCN+aG0ma1ZqcTVRTWFhRXM0M0YxZmZyYWtTSyRxNmU9YWthWVF5
dTY5JWJpcCMlLUQwRCY+JkRyS0A1ekpCJGAKemAwKThGM0QkMD18SFlAZDtweU07dHJzMiM3IWBi
NkMmNXBJaH5VJlFUcT0tQmc9RTdGR0IkKjRLKmxMUlZ8ZjlBCnp2RnQ2M2E3TkU4eldGREEkezhJ
cShjZUFKVj1yeXo7fThGd018TiRjSFFmUipyR2cpZVJRR3Q3cTYpRWh3MXE3TQp6I3gjZiQ5NE9v
VW9qfjFwT2ZgWUE/OVMoUypXeSQ3KX43eUErd0xMcyFOPDh7X2c0UCstck1MZTY9PSh9NjhwdncK
entDR3IhKmdKK3hCVkB4QyFYVExQRFBiYm5Ic2xtd3QpKU1nPEt4VEQ7cF9rTEtUJiprOWxgY357
JkQreUs2PndNCnpJRThFfi1MUyYxQXFYREdTQmhsR2tad1N+cHk4SCR0dWdHJDRSaWZqPWthJmZm
MTNRYCZ5d0EtaGctTD08M3NuWAp6MGZmLW54O2M1VG1zO1JCUWdzajtaSVAqPTZkKjgkSjtlZWFK
TSRjRmBqYnlGXndgc01eeWdVZihxPXlUbzcrZWsKemkhfXp7VjU4X3o4TDU9MHhWV0t8cGtXanM1
TWlLRjsrQEFXPG07Rko1eE02I2tsaSlGTC1+SEx4bn5XQ09sI3JTCnokZGAtNiZOV1E3d0lNUXJS
KXBhPTs8VDx+X354N2IxTGRfWlZxKFcwYWVVfldwRTZ1MikwIz84OD8lMmY2ZVY5Tgp6KFZsNj1Q
flVxIWshK3tmMHdAQVItamZZZGVEaj0oPX1NKDMjV0FnNm5tPkt1UE0jbGxpRU1hZTJwPHkxKDBO
Q3AKelFyZlI/PlFvV3p6d31wczgoOytucVk4Z31fRkd1aWIxZU9aSlRvKGB7S01NRWBPKjVQWGlH
UDRzUHxlQzVoYCYrCnorMWZmczJJRk5iUSk+YU4yIW0wRE9Ybj0pPDBxV1hQXm15Uk5VPUZMJFBK
SShMbj10Jjh6TztuX3pAOWBRUlI+cQp6clk0STY2YClTTDdleWlWTkBvelY+V3VVOHM+SSZZVmd2
cl9zciVXVUEwJXlxWTQ3d000RFVVcXNGRkJAYj14KCUKektsPj5feXs8dDRCWmk/JG5VNXwkb3p1
SCNGPGRGcmtxVVd1X2piTyZ7eik9bnJlVl4lbFpBKi1qJD5seXNNYyVMCnpUP2VMUTNKez49ViYt
USVfezhFZkNgTSVya2l6Z2tvX21Cc3JBIzBWNlFORWppYylnWGx2UUMoJHo4VCQkajFAYQp6RUlO
Z0cqPih6WE1Bb0t3ViZFbSNZPFZGbSNYNz1BZStAeTFUI1RDe040TT9AQVZBczIleFRUP3teT1RZ
aVh1PTUKenQ+cXMjSzB+ZnRBU0xEcWJeUnRyUmpJaENOZlZEI2ZYU2JNajBwTC0hWD9LWSYhVEo+
ZypZTkRoV19GUktpVHBFCnpDUCpGOGpeOUx4QnZ3R1IqN0xjM1VPLVVxRVB6KWZaMzM/N1U0cnUt
UmkhbHVgMVFfQnlmRDAlbVpNTXMwR3hVdgp6Pz97PHwkKkxVfkZXWHdYX3F0KDNEN2M3fEo3QDVR
OE03KEdpVE83T2NXbUU/SSlgYkg5Q19WUWw0empMQUhTeyYKekFQOG1leE0wPml4PjZ5TGF8OXZg
UiFaRXJkbUNjeTV1NW1WQn04UEBCRyF9b0RTIyU8UEFIWilBMlMhe2VLSC0wCnpXa1lVfGJAQFI7
Sk1+cEZRO0V+JHA0NCo7PnxZVHlpQjNTVz07TjUzWTJ+eno5IWhaeHMpV1l5XmlWJHxRSGc5Uwp6
alhSMUpLdkE2Y1NUamlqVkZLQ0slPnN4QkNGZU15dCY3PnxSd35ZY0NXYFV3Jj5yeE96YXl6MGN3
Z1UxYTlsbVcKenpPVHQzUXBlSmNaWmdKRiY8WCZ+ZClEV05LcE1Neng/WHJaT3ArJXdrITxUKzZl
XnNVP0UrMTxYYz9kISQ4ME8rCnpzfHMrbUJtNEMmczBWZFowMGphZyV4aF4mKHc/ZGFoSnVTMnRk
IXM9JF45UDtmZz84eEBUIzwhZlNLdEd2Rz1HWgp6Q29laDJoPkl7SDRZNDAjcytzSVcrPDVBJDBC
TExLdSZHZkMwRStYRHZpRno8RDM1OWc+S2dedHJ6bGlOZFhvbW0KemtnPnRPRGoxKEEjP2MpNlBm
WElLO3FicmY2eElWTWlwM0NBOVVVfjt4QHsxd3NoUiZ+Nys3c1lQYEFeS085VXlDCnp3bURHOHpK
S0VFRDRxYkopZFdmNEJPTFghZkItVUM3STZhRSktTXNuejc/O1U1OyM+ZCM/bF55QjtDb0gpU0oy
fQp6ZktwOGJ0RVVqaClwQl5uZHIhdCNXYD56K1NhQGAhUTFfeWN5NnBAUzVzSjwrOTkxd1gpbX1Z
SDNTb1hySX4qaz8KelU8WEk1alZVSzVEPnxpNHBwaiVMY3ozeW9tOHVVPTRGeWxrY0c3ZUo2WTZh
Tj5nb2VUPmUqN3ZWS2ZRPDFjO3BECnpsKHJkSVltZHJHcHNAJV4tQHwkKWdYXkF1VHtralIlPmdO
Kk5oV1lmWWJVZVB0d2lkTllDRGtoRTNVNmQ+USlyMAp6Q0BCJXY8XzlSY0NeQGt6VyQmMEJ3czIt
ZzUzekZ4SGZLSWNQezBfZSlBbz5rKU5OO3dTMCFhRUZCRkVAUlZvbVcKekcqd2l1cXtNTEhqNSNu
VmBMRjROSEhrUnRDO29iNzB1QDNyeWlfam9SQmtXbllPQENjaWdDbistRShNOVd2Q3BiCnoofHx5
QXs7eDBsRTVJYkhvZDZaQHhwIWJFUnQ0YEJLYEZZSkJgdXd0LSErP3hpO3VjI0t1SmN3c247Z2FH
MVMlTAp6UD0kPUt7QVRZQzJCSCN5MndHaGJ2TGFrSGAtSjNtXn1NSkNBJnt3Z0xTSjFLekB1Y1c8
QHUzODl2UndBaT9NazEKejckNnN3ZEUxT1JvWUt9cT1fcy1TTkBEdTBuVlJpemI+QUs/MnFvfE0k
P2k+OTcrbzJSeXdZaHlLNmN5Xnltdj45CnpBMFItKzI2ZWdqaHV7UUd7XmBBWCtIQW5qYD9zPWdX
U0VSMyZZJVRgcUI4RzI9NkZ0UHBHb20zdW1XQ3t0Ty1icwp6d3Z3JkMzZS1JanEoSTZUYzIpfGtl
cldAKENjeWNgM2RISlp2bmY4P2Qpa3pAUE1LXyFxJX5lb0Rub2UrQmNDYSQKeiNQcTZVWk5Md0Fa
RDNPfE40alBPUjJZaU5Uc0M3S0AwQHUmZ304en0wPEN9e05zQktDK28rKFU7cVgqbE9XamMqCnpa
N2lFaGRIIUw/VEMmRkNZS3ViKFcjP0djZG5VOFBSd357ZlE1IX1ERDY0MDdrZkE0KXEySEMwWGxS
UEE9S3V3JAp6KkRUfnpYfTJNXz57YCNgeGprZWhpM2tLSkk+Ji1ebWNOKlA3TG5GfSRMd1VIQjtD
PUBaa0BeY1hrQGdaXmkoKjIKelB8cmxyeEk7Q1cxQmNeP3xGLTRIKGVyRTdBc21SeFRyczFVUGFT
KFFnKHcqJSg7YjZRQC1Zeys5bXtUQ1ZYdiFACnohcW9NP2tKb31KLUhxVz89P3FmKlZzSG9GK3Fz
U3xuQFhCT0RwKzdKdUpDN2JQVVcobTE/MSFELThqbDM2bnc8Xwp6Kjw8SnFHQ1dvcXBqQ24/LXdy
P0pjZUxnWmVyPy1SSmQpby15OXRQV3ZUQFdgUn0yNjl7NVNCWGpebjFTNT9GKjAKekE4fnI3bnsl
X3JhN1RVenExM3htQFdmMVRIfHVNVTZlU1IkO0ExfHM9QEFDd0dOQms7KWdQIyskQk9XYzxJbXl6
CnpfU3NiPm1fRX0lUDUzOGdJPVFsSUs1S0hARFhHSmZlRUtRMXw0ZDx7JGd6ajNUN2pudmdNNTBe
Qk4mcDVWTyg8eAp6eSgyVzFaIUtFRStxJmtHa0lSP18tJU1XWHpjYjxeJlRRJUNCaSQhKFRZZnVS
O3NSOzBiIz9wPnJVRElQUGgoWk8KemZ7PWU3K1FGQiRLMkEkQGFVYHpwQX07d0RnWWZrUVp7JFBB
b0poZXthTWVZbU0jRUcrYCt8M0BZQDV3VFhQbSVvCnpgNWluXzl3T1RTXlpyO0dNZ2J0UDFsPlcl
NUI2OzJoVjQoI0IwO3M1RmxpbzlAczZeMGUwbEVhezYrNl9HUjg5RQp6QkNJcnFIQXFJaVB9Q1RV
QGMhLXZULUNYTmU7TUErMUVvRSpISkk/QjBVc0xXUkdERXp6U3FCanFJY1lRKy1iPlUKeipuSU1v
NFRteGltJGBEcjAjMGVeOy0oIT5iQU42KGZpYXx3dF41OVpzUDUpTGh9MDl8STVGKHQlRmJUcXJk
cyZICnomP1gpKDQ8dmJ4MWB8RnNtPDZjZU5HIXBSX0hOPyhFc3JxYlZwPmY9TVNYUCNrKzMlXnZt
bmchY01JT2dtKiQrIwp6dFc8YFB4SSRjPTdWMlJXWTlycEU2bnNwRk8+dCVDZF9GYUUzN3N+QC13
KGRYQmp0Z3IqPjZsNV9QSyR2RCYwMloKelNIcnV3cmdBQGpLSWFUaFp8UCNkbUdONWJJcHx7KWM8
K25feXMzUV9LaTwyRXBBSyFLemYhfilMc3w/KjRzWHx1CnorR3RtbGl1JSFNPm4rKXRvUyZWXmFY
fH51UikrY1VASyQha0MwZktiT3lqRlZjeThkIWhZTTNkdFYqWDEqaWc9Swp6P1p5WkE8ZzYzdj56
PEVDJEBfVHBicHZza3RQU3xZdFItQzVISUYtb2NrcWtoOWpxX3NAIW4mXjVMVDY7X1IocjgKemFq
O0orKSRjVzE7IXpeP3FnR340cytGQF54Pj8+YmdKWGpYTWVuI0h6a14/bj80cUtjbVdEST8yZzxo
TGUxUCNkCnpSYXp2I3A/cjFjKTcrY2UlX25EXyRrS0VOQlIpPWkwfSYkY0RRYVNkfEVPbW5tdnpx
TCQ+SVJOJkZ8KlA7dm1+OQp6MXhpKD1zY3BiOCFpMz51RWtoQTJJUUJKZjQyQHhTcylaQjdjMjNR
N3VePz12LTZUJm5kNyslKyZYSFhfUn5hVFAKendpQGErbEpGO3s7U35VcWshT0hUOH1pJGNlamVY
Nno8YXZwYWI7STgkRUkyK2MkWHwxa3RCfGFhWip3QWhVXlReCnpadFk+blNKK2VAO2V9RjtiPiRx
fXFhdTZiR0k8ey1qK15TSnVuYTtWTE1XRDJZdzVCZnZ3e3JzUW15b2NTIVVZfAp6RXloLXhVTU1A
XzYyQnwtXkkmbGdDSDFzUSgoODlSMnBeYDIwPkhrNlFKWUR1IVQ7SF9rKUlGbTxrSFNMeXNpQ00K
ej1Bfk1SQEQjblAmaVA2dV9FcUgoUEU1RDZHfUQxc0N+Q316aV47aXx5cEplKFBveTVMekJWTz43
R3I0PE9ES2lfCnpnQk1LLVNFfD9YUWU1S0UoZnwoP19jR3VyV1U4OzlFYHFOeWVzezFvanQ0TD9q
LSteXkJTPG1pQkVIa1ZmaTs4TQp6STUqcUYlQz1jNyY5dXtRMTdjTjU+V0RsPGN1Rm9BbTlAX25p
bEhZK0dtfl47QH5jK0JzYTc5RHBad258I054cTIKekwxUSptM09yVUM7RjxDO0xvT24xJXhIclAq
VSkhdlYoKUhMMG0za0pmVUR+ankrJiUqQVB9SnxOS3c/N2U7ZU07Cnpvdz1STjRfaTRpKTZIb3Vv
ZzUhIz45aUBiMWdLM09HNEU3flFDIylrSEVVNzNGKyE1UjdsRGNATHExfCNSQTZsLQp6JmtMMHRK
RTlUfVBiaH0wbk9eMztOPnI2S0ZoJjZ1Rko0PmBCTCQjKU4tcGEpUCpWaHAmezF7OXdwMHFORTlk
Iz8KekBLKEJQJGVkSVFeSFF4RzdpNT9qcS1pJCs4M19uUEZ4N0FfUWNxYnUxc15seUJLRWlueVBf
Z0g7fVd+I0dRJlE/CnpYfGxJNTZvWChWdjdoSXBwQDR7eSF0JitJJWU1YTBxeH1paCZZUm8mX3xW
fGNzVXFUTyY/TTAtQXUhcj1GdmdGRAp6Wk9QV0ZXUFZSbz1YRnpjfDkjYWVqNT5yPnVpcn1JNVpZ
d2w/dFllSDhzYiZlYmFyKDt3UlBMKFdnX0FMMn1tQDwKejFWUH5EJkYkUnxvSndRNjBTODRQYW4+
WDs8JD4ofmE4IT5IZG5GPj9AOXpZYGg+I0lPWkdFWWhETnZaK3FFQXFPCnpBaDBgdkFhRW9EK31F
WjY8R2wwZkYjV3Q+LWxqKUY8MzhPZHo9O0BOWHFxXkpNfShrWDRpeWFQRiFQKnE0eXA+VQp6JiYo
QHl3NntOTXRVKjs5VlIzQ3pJb0tOY2slKzJfdjQoN1crd2FIeit5SmElbD9QYWBYdSpUMlIxbUFg
KWErRGoKekdGaG1xKzh+dlI3Y1hBO0s9UHdSPTNfXj9zSCZZZVhhNFU4MV9uPHZYOEptVU8lQXwk
dWVRNnBgXmx9X0ghWkleCnpgM24wQipvc0twKGI0ZlVZWW90X0UwfDRRSiEtOT90RTJzQVJxdWIp
IWpEd3w1M3VCPCNzND08aHQ3THYkMzgpJQp6YDg5cE55bXZOQ2hpPnNuaSs/bSQpXk9tUzh4c1Y5
cEVJWlRTTiokcFVzeUYyT0BDbHw8NWJubW9IX0haP0tgJTwKekhJOEckN3pHJFYkNGVaP14hRTF0
Wjh7OSlOUWVmSGNEej4hISUqZmdTbnhNLTlLKk9sS1QpYDZSRnd0dTd2OV55Cnp5Wjx+ZmBfQ0Nv
cldIPVQrR0NFSGBQKz9+VXdtYDUzK2FCby05JW8jaD1AUD1sJS0kSFdITlo/c1pKJFJTSUZLeAp6
VWR5NTBjYH0pZG9feSpfVSN3MiYyTXFYXk9aWnIwajV+NGgod256Iy1GQl8yIyFSRXlmaEdYTkFg
PGtAbnx0JXgKemI8YmJ0eXwreFQrV1ReR3pXM2duJndUYmpmNDtNYGJEajQtcGN4aVVDJXBHUT08
TXVWX3Z6MnhfeXpDJWV2YVEqCnpVUVBrRGszUEJYeTZjOVBFbmp8aFRVKWtWJV4mTWorcUxITE4o
YnRrQmlxKG1LSTY8fkFHKz9rdEFfZ01kKWE1UAp6eWkoNUowYEE7JSZpJikoKX4+eSFSNGg0VGo1
Jm5BWWNlJmNfdWdrUjhHRip3Q0Qre2w7UWltSEQjTXJpZ0k3eFIKekl2e3hQO1JuOGQhdG8wfm1y
aUdfX2tKe3UqcmNJUUA0WmlfR2pgRiE8M0lvNExsMW5QI0JWIWptRGl6OzxpSHBjCnpwSy08O0tE
JStfaFFCVHJpJiRmdkhwOWIpSyleWmdaNj1kcDtsZjNxZjh2UXB8R01oOCNmUns+aGx+e3d3Xz9U
bAp6KlF7TjtfUysqUEJXViRkTVdoKVdPZCpRSz5OVXRfdipqZ0FtUiRHMTFIWmtjeHwofVBeX3tP
fndhPSspYVIyQEgKei1MaGlFKiUkVG5eZ0poRzBgSSpaPmRCZk1SLUVAPDFyeUFlRzJ7NmFFNiU7
PntgPkV7TU85elg/MnFOdUY4OVdPCnp6NVZ2dkBCN1FZe1BYakFkKl4rLUNEUzZfdEpTMmxxWFV7
cnFlKmt7Zmg0PTwpdkltRXZgQkM3eWw+eGQhKyR5Tgp6X1M8aX1rN1VrJk1ZQkphKlhxcSV6IV90
Qj5zI054YV8jZmEtWihmb3lzfWEkQ2w3QC01PzNEd1VNbzdTcU9hcVcKek0rKm5zcXBKQVRkI2B+
QWdraFNfdTh3PF9FSURiX3VZWX4jVTVRX1FhQnUoUmNzPGduYndQMXFuQndmUyZ3Sk9fCnomNn08
dCZnQ3d5UjRTJkxIJFglakF9YWVVTHNKVlRyWiYjMjwldWVfPk1VejVWSGojaFhVOHcrJjcxIX1B
QTBDXwp6S2FIWFk2MlpVYiRuMDxrVilPIW5SS1VkLVVBbGJaIyZ1VD80aTNHZVI0U2J3TVhgMHhx
M1d3IWxiYUZiIUFVbHkKemgjMEszcSo4JilXWVNNe2IjP3UwIVF3P2Z7PykoVkBue3J7VEtVJkI+
aTBqfTtiVDhkUjhAS1J5UlNOVikyOCszCno8Wn03NSVIYDVZYVUzMSVvUykmblomaHVzRXNSQmsq
Y2VsPSo2YTt9KVhzRHxeSVMocWB5PXpgRk00UnJudHlzJAp6TH4we3YpYmJ2ZF5CI15qOEhjR0px
aVFPV242TX57JjNDQERDYzk8SkA2IVZWbTFZaU00QmckSz4rTX0ke0BCT2YKekpyVj9nX3VoP2Y8
YDUpPm9IcmlVSEpRbnJpKShYIUV6PEJiN25CWl8rOH1+YFImYFM1JlUhbXpQM1B+PnNHRm5vClp7
e2k9SWRASF5eS3F2cUowMDJvdlBESExrVjFtRUIyKGJWRgoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAx
CgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzI1NngyNTYvYXBwcy9lY2xpcHNl
LnBuZyBiL2FwcC9yZXMvaWNvbnMvaGljb2xvci8yNTZ4MjU2L2FwcHMvZWNsaXBzZS5wbmcKbmV3
IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMC4uYTEzNWM1NGUxNDllYWE5MGI2MTBhNjljOGY5YmY2ZGViMDZjMGU2NwpHSVQgYmlu
YXJ5IHBhdGNoCmxpdGVyYWwgMTU4MjUKemNtWDlfV21zRUgoKz0ocU1UQCg7eUY+OSgrQCpNTjRV
aXgkNCNuTEk2ZmZAWCNpNipueUljNzN5eCpUQkMpYnxjCnoqX25IMFhHYkQ1KUQkcEtObCphKjBF
VXZIdFFHKE8xTntqREt0X2FxOE0qIWIzSUs/dURhbEd7YCgmTVVfK31YXgp6Xz9FbkQmazE+LTdg
SXVDcSE1bG93WFkyR0JkIXB3SVAjbUY2NGZFI0I2NWQxO2ltbjtBZCYlZENhUW52ckdARUAKenFl
YlRsbF5ueVI8VDhzVWJjfC1KUEdCMnBWPVptQ15MdWJGVGk+OEtTVCpfZXQjYS03OUMmaGRVe0pa
eldhdXJsCno7b05hSVp8RUV9dn4lU25OKipfflZATEgqTUl5KmY5d3ZOUE1GTU0qT3R1dXFtLWhf
ZUEzaD53OTx+JSt1SEZ1eAp6UHt3MSg0Y1FtbyFpRDdVQEkzcjdsJmIwJGQlJHNWPH5KPlk0Z1dn
b0MreVk3M3UmVXplPHlkPyE7Vlh9Ylp3cHwKel5NNmRMUGl6QHlKVXsxX1NGaUJJU1VKa35QRTEq
STZFOTNwPDVjUmA2KGohWlJVc08zNl4mb3o4KTt6dFp5cnUwCno0RCQoT0RjT0glSVAzaTkwenAp
PCtsPzBpQ3gmUj4tc2pmSnowUV5jbHZ9akxzfC1xNiVYTF5qP0olQyN4fkA4OQp6KkdET2FEPjg8
c3g5RCFDUzI4QmFsYDFrMzVMWlVoQk9+QHdrYDM/a2JoSnBYJXVEQkF6Vj8xYyVXMXh4aTR5NEEK
elZ7PX5tNyVEWH49eWg3bmAzb21sJVUmKDUkNTg7X2k2PkIrKzJTakV0TCVgfkBIODJDVH57dHAw
bEtBbzN3UyVnCnojS08hckY0ZmpteGJwKiY0SmBAfDNpVStEJGpXfk1BUD13ZCppVUxvPUY4KmZD
eX0oKzYtXnRNMlpKZSprJEtXQgp6I0IqMnZQMHV9UE90JEJFbVEpSnVSSCtCdkN1WWBqNXhDT3l7
QkErbi1LUyt2WWFtPjg8TzJeWFVJM0RHMVclVVYKejU1KytCX29YRVE5bVVRRUlpSGpWdyR0WWYq
em58VjxfKE4/VnNyKCtEK2hrX1MySnR1KVJ7Y31NWVVgLWZyVlV2Cnohd2E0I3V8eml+TipNaW07
JmdUdkgpaEVEOSpkX2d4SFNaTkAmPnUqXjB6WG9RTVIxKCo2fWoldDtrT00pVWlzawp6cnwhN3RM
Uk57ci07UUhYeWQ3NXtLZW8yRV9+emB0JFozWXd2RSNJOXNXSXtLRUFnekRCJGwpZ0lpUmMyYXY/
YkoKem5pS3NULSM8SihfNGs8R3Jqcm5VRktCcHdFLWAoYjRKKF9vLT83MXs4JDxwWXI4a0lURHFE
TDJUeklLa3tTKX1zCnpfVlJHclFmdEl+VkJmJjNicDIoQ2l7ezFBN21fbkN1U2tQeyEpM3Q0b3pE
N25GWVZNNWpMPytoYzBJRTNjPlZ0SAp6QWZjbD9IIzs7KkxYKEM4WWFnbCp1REVhUHtRaD5yfDg0
T1coa1RYSFhIRmdNY05OdlNfNH1HekhzbWZqbUBiNzQKenpsKDxPZmk+O25CdkdnR2BLMjBrTGg9
NUVYJH4xaHpVblJBZiohLW5Ea3BkSDtIaVVqIXxseTdQN0k+Wj02eDNFCnpUQl9ZRSNHdVNsTFBX
UkA2bV5lP3crbyYoWGxROFFhXylKM25hXj9eZTFBUndKPyhxNT5+WWk1YjZRNjlyc0pqewp6V153
JmM0fHZAbmRfNS1naFF3dkJHP3xKU3YySkpLUldAdVkwTSpeTXZmT1BlSiVLPXhzOG5gSCskV0Jm
K3U3V3cKem81Xj4yVzk2KVArZjdeMj8mMDRZKVcqJn1jUEEzQngzbFZSUzV3XylSSSElUjF8a1Zo
QGs2cn1mKEkzLSE1V15QCnotZH1XYnsjPHxCY3BRbT9SNEEwZmU1RTgyJXN9TWlKX2crZVA7e1Fe
ZFA5eW15dzRZWHleNkc/PzV2WnVBfSghMgp6Knx4NyNYaUIkYmB5PXJaQ2xCPU5lV3BWUVAySH0t
LWR+KnwkTlVhKS0qe2M+KFlwYVV2YzA0eEZGKWVHMXpPQXcKekF3NDZ4JT9wKGArYElkJG1zM3Ym
KzBecUp1ZFVzRVJ1a0ooP3xTUklmVFV8TlFfcWNnTkNYdmZQMG9ZZ28rZCRvCnpXNjJ5SHVmUkMq
K2U0ZkMpMXklbyFPRGk3c0V5ZkgjPnhpUSZGQU41WlkrdTBPUGVhY2stZXI+d14yNDAjZVJ2aQp6
PWQ1cDYjTkYkISk5Tk4zQyFwN1pnKGx8PEZ9X0dAaURSSlgzdn1JNzZyUWdtR2p5Y1lLNmZrfHR+
WjM9SXRrTykKejcwcmFAZW04S1BpI2RaOUpSakVHRkxiPnhtaVo8bF53IWMmZlRCNDhGNTRBNCVk
QzMhRXxiZXFeUE1qJj9+aXZOCnpfanhyI0g4V3YhTnRuT3pMQkpLI2phTzZoKktzKHwlRWtzXlo8
PWlHJmB2ciZQRUJ9UGpfPUt9T3x7czIhMjV5Nwp6IyZickBqLTVWTG5td0ViN2AxT3wmRjJpYDAo
MSVTMWNgQlNnNjlxSlpGNHN0ZEB4bShjWTduO1RnJSVGQ3hqbT0KekJwPyU1b2UjUjJfXktAXkQl
Sl43Rnc1fFI5WT1ReVVDd0s3QyFNQGd4IzFLWGZwR19VTih9fGNeV1hBNztJTWhJCnoqSGklJFZC
YnAhckF6ZE1ubiVBJTVzYTs2YmlmSVFiS3BXTjY4WkI8UGYlYjxPd0tXPVpedz9WbzxFfX0yPEJu
KQp6P0Y5MTdDZVZJbEpWLVJrJF9vaFQ/TDVmNzJ6KDI5c0M+RVo/Z3F+K0tkJCthUHNTSjQmKWJg
c05zX2wtXmwpX2oKekh2JiNzUmUjX1ZocVBOJlZDQCRTYUNZY2g+KmEjP2BwcTRydnJ+b1M5KFY7
NXtUd281RnVUeWk7NjlvQztRdit9Cno3alBgeXoyMns/UF9hUW5QPlElfT83aH0tK1NQUi0pM3k1
Q2kmaWV6Wn1URlNXMCNqLVkwVlA1XnFTNUFJa01JQAp6X01HRjd7cDB3azJ4WWprWSVoemMrbW07
MDtCeyR2cDx1MUQtNDVFYlNrOTNvNipXSUh0YjRCIyF8VSNXX3VEbXcKei1Pe0NiSDlEQ1JhPXdi
JERuQG5OSjxYKVZgfEk0QEAwezNJbFVNU3xUU35fNzVlMk9RVFRnNyZvbSZ8VzUqRT59CnpXSWQ5
QiY0X3QwNTdTdElrRl95eiZkO19qK0hROGYpbGgrY3QpRmt6V15SY2c2JG0oMGhkaXBZQmRuXjFt
RzFTcQp6I3R5bX5XXilLVjFkRXZaSykmPDl5VkF4OGlJR29FT1g3flJuYnZHaXc9SnhfWGNoZ18q
YnhjNGJfbmkhRWN0PkIKemV+d1dkYyY2WmV6VXVqZHpAfWstNUQ1WihMNThVKSt1ZHRuQkhOfllp
Pzh9NjlBI3xDJCZvWlU3LT44fGNBM05fCno3dCtyI0ZNanVMbVYjQjZTKl4kK2tVWnwta2MhcUpX
S1ZmTz5+OG4tYGBLclRtdyE9O0kmaGR1dnRlWTdRSHFaQAp6aDlLWFkmMkJTc0cwMVRCMTVsSkZM
YCEpRGBWNl94LVNEYWxDdiVlcEYtbipMVVE5dm4jP0ZnMWxASDBUX3pXMGcKenVhXzVCVj8/T2Qr
bCpjIWpkentMWVp2fHhDKlRXTDxoNCp0ZXBwLUg+b0pNQCVSJm1LNF5mWjk4JDBQQVo3WWxQCnok
aUJYWCNRRHEweTN1fFAzVyolVThVWEJtNm84IUgwbG5fQkZBX28/e1RwKEpjdGtrb2clK0FoRjYx
dSFaJHpxUwp6UkJfMTB1KmpvZmM7KCt1aShAanlISkRSaDUxfnRRKlV4SilDO016aUZvO3U5PnRv
S3FWLTVtJXlJPEN5YSYqeWUKekE5NjEkQGN1VzlLZXxyc2BRPj9gXkNKN2c3YTs8TU9rKUdkNX0r
bktXPVlFNS1lJHlKN0BhZCtIenJDeCswUiZMCnorK3lfZz9GWXNNWnV9dDN1YWBZWnNGMHNiYjBN
IThveUtqfDtYNmNvcjJhbWxiK2B6XnY2bEN6Pmo0OSV7YFhOTwp6dUdwSTBGc1UjTl5RKWVkVmdm
MTNkI3VYKFM2Znt9SmNnUSMpfXV2az1kbz1VZnJUXkFueXhRY3U9SVFZbjQpZmQKemhuMG1LVSZ6
VnY5ckZtem4pdiZ7KXRGOV9ecWY2a3F3fnRXdSsxNF5sMighU0M/MlohJTtufis5cGNzNzE/WVd3
CnpZYipiQUhYZ3tMZFdoI2BkUDBicG9aUkZsTmFENUlmTjFWSTZmNVZIUjNJXypVMHRsXj5EYSFn
RUo8ZkpQJVY5RQp6TjYwTm5yX3JGWXRSIWRrbTg2Skk7TnFZTGp8M2RmbX5iaTRXd1ZnO1gtODE0
NC1ffVZ2IWJiNyR7NHY9PWwpUE0KenV9bjZpeWRMX1RKcH5ZZEo1cHg+fEloITM+S291bT0jYCo9
SytoLW12I2RnMUJoajB2K18hQ0pxUGJnZnRnT1J7CnpPeV5GMDd9NGs5SzkxNF9gK1ZoUD49KSRq
b3BlJmhxTk1XcTw4LThYdX1mVSYmfis5NXZNM2FFeFZOX2hjfUA2UAp6NTYqbjMoKG9KTSZrPilW
aClsdkdWdE50ZWFsT1lDSGdnSUpkTmVrQypqb3drNj9JMX5OQHw/djdVY0J0QXsjKVUKekFBd1Yw
SzZNN1l0VkVTMUFLVGxvSnpoZkw8LXE4YG1hT2J+KlZLN2VgOGBxMG1JQlYhPmMjbmVheiVIcCgy
ckY3CnoyP2BqY0Imfm1pMjFDXnNrOVNIKDh4SkApdmRMaTdKbTwtKCM2bV9iIz1aVihmUkNzPCMm
PDNETlE7Z18/OyltYwp6anhAQEkrLTdffHNUTHo0X0VeXjhkO3laJUY7Uj48M1dzTkVTWlhFeS0m
WTR4dWRtYD1tU2VkJmBxNyg/Ui1PJDsKeiF0OGNPYnImLTkreUZ2RXN2QGw7cTY3Yns0SUBkV1dX
Nj5tJTMhPTZ7VX49I2htWjRnNDljWDEofVFgKihzdHZyCno0YVVeTDtoUn05UylWeyphKTNmVTFC
WWxYIz4jMUJVeilUJUpzWU19PUZ3bkUlR203eW90dH1wMERAd04zNl9jZgp6YFModzx7a25oJlky
MlEydEVMcD4zRT1gaz5jJFYyPXUkKXA8OW1uND1meCMkaUIoblghcGtDdT1aQVRQbGArIWQKej5X
MXRKezlgeytkaSR8d0hqTHdGM0skRUZEeihhVmg/ckF8bUAjPW9qalVYM2UrQzc/K31+bnBSTyp4
fWFHQ29FCnpEdHoqWk1PMD5AcXQtNSlFN0JDPlJ4WSlvQ0JqMmZ4aihZclZMYmw4a2FzQnB1ISt7
Wl9gLX1hTzZQaiNteExeaQp6RVE5KFRtVndNJmJUcE5IdWkxSzNGbVE+aEJDUUxJJjtwQ2I8TGsj
UWJQYXB3bWl9OS0kZUB5MmdTbj19JFNUal4KelNHQTVjWFczYEdQYXBIRTI8WHZBWjBiRE5eO0h5
eGwmcEEmUyVaLVU0O1ZqdVREQDYkWCtGc1RCS0w3LW9BNmZRCnpnRjQxQWxXLVhwMTx6c0tCPChI
fnFJdGpge1doYnxjVDA9UT5ePUZmc0dISUcqaCV4MCh2RUMlZWpoY2JycT9IcQp6Nzs9Vj5jWFp0
NUJnKnlhdTY8KGRGMEF3JENHKmVDbiZJRXooOGIlNVJZZS16NUFGI1VuezV+fSE9OUo0JGdCKmwK
eilBOXtzVEkqeWRhN0R0UiR2RGUjbzJEfX5OVHU9MnFLaD5jcilLOT0peDhESzRraXk0X2VQb0sl
Ripaaz8kU29kCnpvN1dIOFgzSH0kXlQ5aEtAYE88JHlPTWNWbnw2dCNDNlNPZ2JERzJkRFF5eXtw
WVZFUT5LQEJXbDRlTmA/PSVgQAp6Tj9UWU9LKE5Va3wxPkVZNntUan1jT3swVmhpISF0WD87bGch
elJ+ZT0tejN5Xjl8dkE8cTA8S3s+O3F5b3hPMmsKel5qYCUrTyYqX1o7PX5Ab0c3JmxxJXVlRj44
MkoyZnZqSDUxbCl2NDh3JihsSjNPRihZQipyNC1WNmF3WSN2fGckCno0UTlSNHc/UzslODJPT3Zo
KDJPVHgraylnPjZIfnl3T2NSPjI0eXNMT2sjS0QhP1lZcmpGdnt9TGgxYThocXVSTgp6IW1RZDMw
WX5mNClORUomQUA0fkItTzlkTHZDSEF2ezxpeCt6TFZfVlItVnpKez9LMnNIeFp2SVFDVGFSRFUh
czwKektpS2VneTtXVEYwMi0+Ny0tYD9kPUpON1BsdGYmU0JSWChkJFBJITheMVJufGA2JFFAUkYo
K2BMRihrPlYofFNmCnpvWTRnK3k0VW8pO0RtNC1zJDJKIyFqTmVhb1A1M1YlYEQzfnVGKTMxdm5i
IVFEQVYyeU9QIXlrXkFVfT0xPn1aZAp6cShvbT0lcHwlRjE1JEYmZVI0IytvVURPRyRPK01aaTdR
N2tNMXdiUml4P3QkWHxQd3ImMFNteTl+VyhWQlEjPTsKendGenVfXlNQYC1lb2hoOSZtYkFhLWpY
b3xobGdxc2srO01BbDFSeVY2ZDhIV0tOI2pSdSNfV1dPK341U0YyS3toCnoqJm5VbVA5YClPZXc5
WUBhXk9nQUJiVTZ4cHFlQVd4O0ApJFRnbGxER3Q5TlAoVnomWTtlYDI0RE8+bV9WZEJaawp6PnVp
bEFmPCY8cGo/Xi1WbmwjaShSV1hsR1h8VGBLX09vKEVDdCpfUSFVPisqLW9wWigla0YtPExHK0Fa
WHBuTXgKekpFcVRfez1ycGp4eWlfJE98QWxFPGxve0ZWeE44Uzx4eCo8dllXYSEhPjF2ZWdgMzFt
XzBNSHJyYi1WOVAjTV5YCnp3K0BDRzx+WlJQcSszaTEzeSFUK2UjI0BqezNZIzRhLSttfWt5fFpQ
dzFrS2xScEo3NGF8MUNpSWA7M3tBMW1EUgp6M2AhbXM8JlAmRmlefENoZ0RDRkFoZj97KXlSJF9h
Jjc0JkQkRUk+ZGM1RmokLTM9S3JjeCtgNl4we19IcTZMQnIKeiF2KDtGVkN0aTR5JEk/OHp3RmQo
NHtpI2RHdGMoWi1sI21DbEU/MUNmNE5LMkstUyQ1QGNaZj1FYTxLTz9iVUltCnpFP24/aDNlZ0Um
P1c/SmUxT2FhfVdpM35IMUM5Sm9FfEBAaiZKR3tBdzZEPXh7bTMkVnhGeHImeUU0X2pBRCNVTgp6
JHw7ZVZCPHx0b1Ize1RrPWg5UWhaeHBRc0s9K0Zze3MmNyNIUz0xLVIrP2Fmbzw9WXQyX0ZMbiYy
Uj9US2FGbGAKekZ0ZUw/MyZTa0tIdXx+bWo+TV9wQGdtaHw7SDljOUN9KGQtMTkrQG83VSRIOWZq
KmwhJHdMSjFlO25XVEc9dWxSCnpxZ1ZNOGlebXF2JStSQj4hVzxxNyU1JkJ5Tj9IbWw0UF91cm5u
Z1F8M1ktQ3hxd3NOOyRDQzBsTlZiNDA8ZGJSUwp6OEhMcWpWX1NgKEg/Rk8hRT5Ke2I8c0xtKCZs
ezwwP0c4NGJRcFMpemo5e1U1bjw3ZUNLcD9yMCNGTytodmImWWEKenJtN2swNihaKlZ5ej1MSTkz
ZDl9PUxGcXJoKEtxQSVONEJoaTJ6bGNMYDA+dy02U0Y3Tzg5JT15Vkw5M2tDJXZuCno+NzA/MFVn
dTZCTlBLfXR7eyopLSVWJVZzLU0kTGI+Pk8kK1ZLfUpZWENmZzYkI28oSkh4a3R5QG8xKkwxYjE4
MQp6ZU5BZ3tEXyt+dDEjS042Tk02bmQwYk1RMEt5T0RYIW1sSUR2cT5XenJONms/NyNBRz1SVGhh
US1uMFpVbk1valMKenZjTz1mYUFXZEdMJHIhfE1SYW1VWX1US0Y5QFlBKVBhXzh8U2tBSl8pKytT
QlhvZkZpUkl6VUlVcURpek5AWVgoCnp4U0s1cVJsWVZaMkQ7OXRkVFkxYztIZUFBUmdSYTElVXdp
REFGTT9SUk99dWB4ZERBPzdYUGo3XjJhYGJFYHFrYQp6c09gNzctcnxFbDZBOXlBWWJMSVM5XlNJ
TFJ4Yl51Mys+USYjOClMJE5hJm1mezBMNEc9NVZgQk9ZbUYpWnxCfnEKem4rO3RRd0NOWEUxRCt9
MF4mJDZqMytfdiNDSkwmb1MwQjUrNk05KnxzVCRJYz1HY0dWYykzJTVKaH54ZXZieFRACnpFUUh8
YWZ0OEpoZ2NZRTQtZTxHaVolSk4rT35SMVQyaEVgT15HIUlPWSZrZ2x1I3xMZT9gYjA8eHBldSRB
NXJ4Rgp6JGNVeHYrd1RjbmNSUnJISEc5eG11S1I5UGJ4fVJUQiROTXBnLURsVW1WQlI2b1duKVky
VGwrancmKkMlLWwpY20KejgxeWRVWTsjcGFzSX1BeT1lPCM9KnJINUUpRWF7UmFKRHt5KGUqNG9O
cX1US3hnVXtAXjs4bGZaKHtiX3E9K1Z3CnpoSTd6YUt3UG1NaEt5UkM+QThUcCtTczRXd0JfcEl1
PSZ1NCp8MmZAOUVjdWFWTnJPNSQtUD0qaTYjSSFlc1FjJAp6djdOTiljcX5hRDlRP2lJX3gpWmFS
XiFEbEQ1Uig5TUkxZ0Z4K0JrVGc4UTxOdD9+RW9faF4mKCpRWHk9SktgdjcKej15YXcmZXRvcFFh
QnRzQS02KDkqRFB8az94dVQjO1htXn5eckU7NVpzdU13bTU8d2RAZjI7N04lRzNgUV5kUkVRCnom
fiZkLUhyV0F3SVYlanV2ant5YE5vbilgd2xecGVDPClSb0c/VUlmJTd1RSo2fXNXcyo/O2FAWjE5
fXtOSyQjYwp6MGU4PyUpRiErS29Nb2NTPVNWcT9IZnEwYDVxS2FIbFBgOUprYmRqPlphanpUJUs7
JmxpTjdUIXM/ei08aj1SWFEKejQjMVNtIS12ejFWSWdFY3hUeCs3VEsjVD1jWHpJZzg7Rj98OUx6
NmpPMHYhNzRGTmtQUSMlQ196TjtqcmZpMFZMCnpkTG5OPWFINmFPP241KnFeOThwbnMtRkQhQXtT
PCNXKll2NXtpeH5rI2pwNz05VnlCNXFjRDc8PDc4dD11c1FSZAp6YSVhQGYxX2t4SVhSS0RvQG9a
NHlDV2FZcXlfVUEpKnRJbTBYfiFWfT5vNmY+KlBvOS1zTyViayprVmxKRiF1cDMKeitMQT9AQnQ4
TUA0K2JQZ0hJIzlkKHhDNiZ6fkY1SFZQb0BhYGN6PFExZmB1R3VjSiZSTzJ5RUtQYnZDZXkjUHIr
Cnp5M0h6IUxeMk88OyNTOS1he1pEVDlWY3ZGWT96ZHA+fEh+cmx9ZjA+PmNfckdae1NeRytxUD5l
R2J3Qks9ak03ZAp6ckx1e248bDc/QER1bUVFdW87YGpRaXllPlhIdjlBYEtKakxHX0s/dkRLTj49
bTA4cU58STRxJlFNfiNMP20ka20Kel8renMzaylka0t4T35FQFM/QU5zTFNrMD8zN0owTHJJOCZO
WXlFK3pMVUZsdGtZQCFhO2pEangwWVR3JUMxfVZqCnpzZW91ZiRZITFUb0FgO3ZAalNPTTZPcXNw
WlhySEo7QVd+USYjSG5VZjgxVUVkc2JkTktDMSVYYSRRUyZwSVMhZAp6bzVQfDRmTjctTmJUfU8+
QUBZRlIrUS1WNVN3JlNzc0xVRVchOHk5WEZWX0UlPEQxbk9QNTVwayF6M3BiYCYtVl8KemxtYVhP
IztNb0JGQkdOX0s5ZShRdy14SHNXRH47VEFuNVdgOGEten55dVZDVzJ2amA7Jlc7LT03MndYeks3
OzReCnpWVm5XOVJCdFokUzJKPj5Qa283IyNkXzZyNDlsQHUzMjJuSV9fPTxNWUY8ZlVCTl5RY2ti
VEEmPHNOMTIhaHlSQgp6ajY5c0BDSXFUbkB0WG13V0Y9ZjZQMDY3JllZTFJDaG4kc1I/XzZNKEgy
dWxLJVlvcENIZjFzUzVTdVpAKUhQZEEKenkkPD8oKzNRRktUQz4+fUg9QElyWGV9Q3NaQiVKXztg
QEpwe1VKNUxzWS1EeFVPZHo/KkJGaD1fJTRDOWhDc2t1CnpxWCZHUnJ1S0gpPWVHVHVvSC1sS1Nl
amQrRD55K1VDLWRQMmV1PVRkSHNBPEM7Q1BxNTJCWEV2PypZdz4pOWZQfgp6azZYSkQ8IStvcFRA
Q004dFE8RztDXnNrY2BQdTAlcz0lTk1FPlMrLT8kbGc4MSl8Vy1TKFVuY3s0Yjw5aCZfclAKejNv
NXluTEE8TDhJTithRlooKVZQc2pNYkZjU0R1TUx+flFva3JZWl5pRj07aXwxSD0hTHJJSmBtVHVX
QmhOTkoqCnpWOCN9a2h4NjhlJjFNSGMzRChTYnMxbmJ0O05OTXdoe2JzeSVvbTRUOVZ3dU1Pb2Mm
SUJkSlI8VC1md3hyeE9zVAp6XnpNTzYzNntRMzM2QEwpY1VEVXJtR15pRikmKkg4azMlS28pKFVw
dihIQzNge3soVURgUiFXPmY+TCteNEFTelgKej52aGo2KHY+eXIqLVIrTiFRbnNXVTx7UklVYl96
WCY3dnZaR1A0STglP31KdCtga0ZJRElVTWtuQUJicHZGcTFvCnpTIWs9WEshfUw5dklTQTR4KnV7
amhUVWMwY0t6b31LYmQ3MG9eUGo9VkxBJUlWZEZNfFBFYm00a0x4cTRzVVc9QQp6UDt9PyU/N2ZT
JiFCb0RiLT9EYFNHc1lTbS0rYXFvMUVYUmo/UyQ2PktlKzhCPkBYXkxzdWI+WDFmPFVrd2YzUyoK
ekVNMXt2SilGXiFKfD1BRk5hY3FRO0R+JSQ8UEQyQFRtdiZEak5ONEl3ZUIlWVhBe3IlRDlCVTVE
SCRHdDB3NT9CCnpxfi09a1l9V3YzdERXPmZUIW9tRm1SMTR7Py1hVHhlaVA1SnRBRT0qeU9iIURP
ZkxrKHcmVSZ0UWh8K2NMYS1aYQp6Tz93KSZBKXlaT2xPMSUtRmEmdT8jclIpKi0+d3F7WWRTSjVA
TURWb05NN0V1M3dhV0ViVlZBYzQ5VnsrSX1QdjsKeiRaOHJ3PXxoRWJhNHdVPHpmUFchaTdsSj0p
OV9+OWNMJD9pWTBiTTNzY29LKT9ycEgrUX5ufFgybDRkTGMhdlBaCno1KGQyaGUydTEqb2ZZOTB2
en4tX1JTQXFNMkw3WEErcklnMFBWWTBuQVdDRWRkaTJ8OTF8Z0AjaFc+Kk1UdHVeXgp6Vm48N00h
fWVmPUM0V0RjLU5oKzI3ZyU0cyVTXkdBQzREOXdgYE8jYGkqJkx1R3ZnYT9iYkNLJlAqSEF9dn5N
cDsKekN3a0M+MXs3UU1qQER9fCh6SVBNITI1KUJBJXJjPj5RJFdFVXE1P2AydioqfDhAKWN1NV4/
N0dMZHd0dkZ7NkVBCnowQmRzVW1BZ0tpU05eOCNlJT58eFJIJmhNdmhSYT4rMEVNbCE8IU05Q0U/
NzQjLXNFb1E5TW1TOXNIQipzLVp9PAp6fE1MS2hibi1YIT52fj1fcXVGWk12djtkSmRWTXIpTSlz
XyhxLWNKMDE8enBLUiVpZGxkNmJzdXRzWTJyUWh+NWcKeipXSDNsMkdYQW9taXcxVihudm5ic3VW
RSYpRT9pN0NvYzM9I3M/Mnd3XkxvNnJ+MlU5VCNvUjJjMz82Qm5IVD5kCno9N0FVV1F9JE5gdDEx
Jik+bnZMI3kheztUdl5LRCFUPWh1Tj4yMlJHKGs8fVM5NnlfNHNYNzQrbjlBbmU8UUhJdAp6YCM2
T0xZKnZ7aXdJSm41MV41YiU8bThlcEpBRUs1UFFPNCZwMU5HRSZGU31qY0dSZHAjU1k+XmNwOHpe
Vn5QcT4KenZhaShBZDMtQj48LUYkcSFZX3h0PVYpZHJ4fV9iR28jQV4+VmhESmBuKzs1VmZZMTgz
OUBBank0SDsye291YVp6CnorRTFVTUJwfGlDV08oeCV3OUlfdS03NGstUHM4VEAjOUx8bS02OXhK
UUBFfH0xd2FqJmFWKkQ9N0B8Y0hCUFhofQp6NUxLVzchJWYjQzB3TmJ0cUgyOXBjMldEUVlSKz41
ZmhzU347TDJwJmRkWmBiMThraDA+MkBHJiN5cF4yZEV5cHwKekpTakQja3hvY1FmOX5tSE5KaCso
Mn4ocSRzbjI5a0psQSoyYXJzI2lmYUdhdFE0N0RAYTxzIU1PcmM0aGhWMStkCnojZ2Bza2ZaeDQ1
bFdmTD1VfEtPQjtDcnZLMSVTQSsjJlEleXtBTkhTeUc7fnJGQWpVRHFSMzs0cnxKTCojPG1+ZAp6
SGk4a1RKcCMycWw0P3E9Ml9ZVWc2c3o5KVZDTWRFVDIreVZJeDRpbyRhOCZFUD1gOWdRMytTdTZt
UXhEXkZuYEoKenZwa1QkWkRYeXRIfWhWfEt7ck44YH1RVWg7IT5YanRtWmVQe3VMdllWQXAtOT9r
OEh2WWFxYHtxcT5CejllP3xYCnpSLVozMk1uNUQqJEplIzkwO1p4PTAoQzFePGloeVNvMWY0M0g5
Q0h0YHFpeTRvc3g0PmtebnVVSy1ZUSl2fDwhZgp6SjljYlBqIStVYCF0d2RsRlVXMj98QVFxbWcq
fipCZzhtejcjbC1tIW04OV42PSEhdUk/N15oTEJ5SF52Skg+LUMKekUrV1dWMl9xQDlOSFgrQE5D
fHZeKTBQeFcwTkFjVzNIRCl9WXU2cHZXJFRlMF5jYyR5aytJeClpZChPVmRuQXBVCnpSQE93OFcq
ellgIXxYSmVeeHpAbjE3fURnP2JzYjdjU21TNmRGYHFhRitsTHFMSyQwb1JWPENDYzhLJTJre3h4
Ugp6TTNCKDx2VT10NjAxYFBBJTMpLVJqITxpLV53PShhMkIqZUdgPUFeS1B7JDZwKjBZPExVZDck
UVA1c0U+NmpBNkMKem94RHZUVzcoKTZwUT1hOU9RUVpART9DOWolfVdBJV9KIWIzYzk/bFEhNGMq
WERjSjl4dTd5NzFyZDgwNGomaUt5CnptKV8zUGReUldjKz5CLUNwZnt9akQtfHVoaSVKIzc7NkhS
OShWeVg2VC1qTDt4YFJFVTd5Ql4pdXBYST1XPk89cAp6ZEtaYGNFMlhXSEteVnNmMGRsbjZ2LW85
Pml+XnIpWmE1U2ZtSDN7aXl3OTk1MjYtTCo+S1Y2antrN2ExTzYlfTYKem8tcEw8YTdDRi0+YXcj
V1V9PkMpIVheVz9pelZJSEJlO21IS2RpY0RuKUs/c1diM2VeNyliQEM+WEcmYWFNPHZMCnpfJHY8
OSRNZl9ZOT5EPHMjYWlPdWQybml1QyVxOWoqK0Y4R1pzfG1HXnwmd0Bpdlk/YzxiUV4ybmhoaUlY
NVhCegp6Nyk8Rjdra1dvOHVDKD9uKGNjM25eUWpuJUdYMVE3K2hLR29YPkdqd1RjPF9GQndFQ3he
aDxiSVA3IX4rbkk3YkkKeiNqfkJ2JihrPmtTX05BV2ZkTlJNPkdHTkBiRjVCQWt4emtyQW4xWkU8
S001Q0smVkZ8d200dmM2K0BCZGRvWnRvCnppWGg/LTl8N1R3dyV5T0A4QjB0KnZNdyR+eE9qSzZM
XmM9Y3szdTBNYWh5WDxXZFRvTyZlSHtlKXgtdVlMWHFKMQp6KEZ+PmgoUjVLYWlXaD9YXzkxR20o
UDlUdDRPajchZ3pzYl40JkBYb0E2bkg7WF5aT0VGR1M4K2IjRz5xRHc/SV4KenckODt8QD5pa2Y8
dzBAYHteeHNTTFFqc3RHKGNPZiExKE1kVn1lMEtkU2A1akU8e3h2IUcrbz9XLUVTNjQxS15lCnpJ
eiNhXzA/c3hNUzBRVm08dEt1ajcmczJiQWhqUSRHSyZRVkNIIVombWAyOUJMQXVTVDRFJGYoa0hO
RmZ7UVgkTAp6eFc5I2xXKm1jfWZHTktpNVApZDVhYDAyal58RTQkcEdnNjxIZ00yYyQlJDR+KXph
JWZORGZBSFRAfWQ7R1kleCoKenEhenclblh7PSo/SUs4RygxVmhCI08lXzBHWDxOUyY1LXl+Y1ZT
M2NET2R0IUlUYD0qP3tBO2V1fShCLUtGQ1MyCnpNZCtZYiZTRkBOeUplbT5rZV9Hcj5iZyt4cyY9
PmI3QHdCdWF3KjVHVkV0P3Q3PG9eWTk1Pkx9VTJnR1Q9ZURxVQp6dnpMc2IwJkFrS3owTHAoeCZp
Ulc0UE9sX2RxWlR9aDgrX0IhOV4ydkBzZil5M3RUUkxYRjtoflFYe3lwTjAwcFYKelh3JWpBNj5z
XyQ1bnUpYCgrZ358QXl3UUZtNHNAV2hqbGxBaj9+cUJmcUtGPVM3SDNnJThWc0h4en4xJGBxfik+
Cno/aG9+RCFgMX1rPzZnN2BTeUFOdWxueWRAWk5ANVheSzxMUjBLQGpIbzdwRUVUbFk7UUp7JmY0
MElYSTApez03awp6MyEtPHRLO2RXKmNRSE5YNlkjbj9YKit5QFRgPC1YRW5CLSU5ZyR4YFgqeHsr
b1JxRitweW1teTRkWiQ2Y3ZXP3YKemZRan56QmFtMUxsVWEhenNNNlNkN1pwNDdZJHJMSmg+cUxT
KyRBdlUjQkQkaT5xM3BNKHB+LUJiZmZKWD9yNTJsCnpUNks1MiMtcz5DS3pkVT16KSZsPXB0aCF0
a251cmtte0JIZzkwcDw1dXw1PD1AO2QqQSFLYDhSV2lIVCF2SUp2LQp6UFVRWEoxOEFwenZuKXpL
YENAbEdOeyNrZlEqeVJJY0tSRFArWShZaXNXO3NETXxjJEotfW9DRlBoPGdpQnQwZzQKekZ4fTBl
ZDlZQktJZWsqSShDMjREeDhIfWpSUXtrPSFmcnxqUFozIWQ7aGpONW53MkMrV2RXMmx2dFJ7ZjtH
Xjd6CnomYXo1NEt+d2VQWFoqO3I3JE5iNmlNRXQlPjNAZjt5TEtlPyFRYWh1WU5QRGRfY3N6fXI0
Y3oxZ1dqOFY/M25xPAp6aUttQW1LeDB3YDIyNE1rIyNUUCQ0cmp6N2o3PDZ2cnJqeyt2Qno0UTJU
M31WU3J9QGV2cHI7RkJSZmZUY2dUcGUKejBMX3JqPW9KZ1ZoYD87PjNWM1JwQll1NXwmcj00bT8/
Z19pMHl1aTZWeXdRZFp5czZ1MXBoc3tYYiZBUSF2bU1LCnpMKCVCYFl5YjNjT0MzbC0jamRwOHtx
dk51LUVaQmtEam1lUypMP25mSlo4PXRTKkFCSj9FU2Y0T1MkaHw9TkZ4Kwp6SCFlY3hEJWFITDhR
ZS1EVzQ5X1JXWkdPUntHLTNlMDVSKFh7IURpOEl7WkZLJW9ORD09VDR8MkwqfEtHRXR+TU8Kek9j
VikjKTZNRXB4NiRiclpwcUVfTkklQyZYXiVCd28kJGcpU1cwZT0ybTFBTVpWMnN4ak0wMiE4YmN3
cXJ6PX1XCno/SlJDRzc+X05TYzJ0NkBpK3AqNjRWWTZYZ0VaMlVoWm8rM0xrITw3TnA+fj1vI0Fw
QkEme0FLVlR6SE5lTEp8PAp6LTtMZigjd2szRG85MnplPUQ5V04rI3p1TDtUSG1OcCVaTTsofjZW
Jmx3bWIoV2dpM1hkdmgqOTErb0J9TTVnNzwKek45X1FvP2t3bj9oeSYldVh0Xj1YR30pVzNMX1E3
JiM0Pn5YRl5JbFIyPFE2bXBIazhPMXdWbmZkc09oJXd0ODJ9CnpFcVlLezlxVDBpPDcmK1RfQWpj
VUNoKmR5OVN6MiElXnlgZWl5OU9iS3FJPXNqRWEqPF5IMmFBRi0tSjgjTUMkRwp6JmdyJnZWM15s
KjY8aypIdHs5JHFLezU7K0gyUHBOP1RKbnl7dVNkMz5DLVk7S1UhTVRHc1F0VEMyPHl9RGIraCgK
ejdxTi1MeWRJVSE4Nlo2YVRlaSYjeTY/NXJIamI4IyFBQ3F9MyMze1N3OERwKUFCZkE8aCo2VW5V
RDVBIz9pa3R3CnpUb1NuQHglU19qeGx0PTB0XyEjTUVwUX45SzMoYXUjeFBRREYzNTtIOEMpY0tx
O1Y9Q19saj5qaGtsT3ZRQGhXYQp6WVp7MTI9KmQ9MHcxRERJJWp2KyQkYypjNShIS0o3N1BrfDcm
N0txU3d7Ul9BWSNsKHRUTVRRdTR1T1k/TG4jYTsKemUwRDd1Nz9zUDVzdipmNW81bFpuX218TEJ0
MjQxY0xkUXtPaXQlMmJZfVhlIWlRKlcreWxTIzhyJmhGPEM7SHo3CnpIKzEodS1tVFd9bkxpZl82
SWFmYmM2Vjs4cE1SMWJpUkA+XmFQIy13R2Y0UypvI1lnS01ZU0tEQUpuUVJ0b296cgp6aiFhJE5B
eTh2QSh1cEBYe2ZJI0Akfk9QMzg+diZAd1Z0JChyWUtPbj19d2NJN0lCaiMqdjViNz1QaHxYO302
SE4KejQxV08tPW9NaU10NSFTZmotQ15hY0FGNFljKytXKE1UbnBFdlR3YGptY0pIS3c8KDtOek9z
OWZZSio7YlklRGUwCnpiP1RlcWVDbjZMbz1Dakokfil9fllqPWhucT1takhlREdvYVctcjt7aD98
UHdpciQ1bm40b0tHVCNRQUNaZV8lJgp6Q3xnd2ZxaGMtTzF4TEVQKSlYJHlaWlpRVTR4aSk+MkY3
JT9GPSE+c1lzeUpfK3RtaEAtVzJMbkJWJHImTF8oUzsKejxqJkJaeyQzSCpRVndmKmk4SHdIUEI5
KkQrYitPM3A5JHM2KX4hSiYrLSRzN2xUUTk7S1ghWV5tJC0xWmR5IzFxCnpUMD9KXk0yJE5YbVRO
aytsVDVXLS1AfjV9NDImP0hwfEVHZyFkdypRdStOPjtqcUNicCQmSH1RZUApTEJMeU9YdAp6TXhN
QkxjQjhoTDxqNjI3T0JibFVvSEZ0OUNLUShsNGZOdVlOdm59SURpRFoydUQrY3tJXyVhezwqMitg
TGFKdHUKengtPEw8SHczb152aD5wcVJMd0dgODJ7cWRROUpIRD59UGxYe1MlWHw4RHNkUGlROX4o
X3J2OztIPlZIV0I5PX1sCnpDZj1vPF4tbkNadUdxLUJQKTVoK3d9fTRTKXpuKlRBfV9BZEkpcU5R
UnxLUV5uanxlRmdgZj8yUTNUJWdwPDNDagp6X19PXjdLUSR9WXBPJVkqeyQwKDxQT2J5aDQ7MWtL
I2tOP2J5fExZWnRfJjIqd1YwV2FCNUpeNEhDbzh2TGRAKXMKejc0Mj9RYSZQZ2pFP1loVlMzT3M4
NTx5c0EpRj0oUyhiNDZVPnkoXml7T0o1K3ZKSC1KZG4zT082OWJWVjFpJkdiCnpBTSNnMVVwLXQl
TEQjKTlqQ0FtYV4lMkFVK2teQDl6ZXdhaGhSSGw4VDk7aDRTV1p3b3F0bHNrZGckP0BgYiF1Mgp6
VDBYY010QCl6PWx5IzZge0FMe3hAWUNOP3g4d2l9an0jYj1sej4qVFYpWnpec2lTZkUtUCM3blJA
SGNCTEp9QU8Kekk/YjFmKnsyQ3s/UWdoPXdmM3dePFp1SzxkayU+MHMoe3RKQCVgdmFHYGx+aXF+
VVJZWV9EPGBWKEVxRHN8b0xaCnpoKzZTIT05aVI4UGRVOCtIOXNQNlYqZiFscnIhO0Y8RzU1WG9Z
ITx1c28tQXBjLVZ3RztqOXU9QlhYaWQzOyYlfQp6JmJuMjU0fXtzRmE9KDlsYFl1a3NOSH1uYW5+
VWU7YCt+ZDljUmAhLVVDNz58aFQ3bHo1ck1xKTR0UGFAMnhWISEKekpuZCFPbVdsWX4+KVkpQkFG
NDFWTmdNRXw8YHZ2Z25iZFdJaio8eD0yI1p9am5TLUomaDQxP31XIUkhIyFxPEFVCnpQPGJvdWwo
YXFiQW55czBjJkpnRHtvVkZrYyZJNj9AbFU+WighYFRrU2Zse0J1YmJOQT14NXVmSHMxJkxFXkJ3
cwp6RzxIMVBxT2ZRY2BvTigwVihKZT5aYUR3cGEpWjFuTU1BR1dxYUJsUiQ9MiRoIXh4V01ITGE5
MTRMZyYkbnJNbCUKenVFO00tWUxVM3tVb3ltOGB2dDtzUlBoM3JxdXgyTTVNOSNyTGU9blVPTklO
UGsleSpMe1oqd0AlJGxQSUdtOSZSCnp7VjhPcGR8TWpjTkQwMDYkWkIjQk8hYms4VEJ3RnNyNDJr
WUxFc2spMyFJNmAkcGZyfD5peSlpKEhUYDs5MGNuewp6QmJNdiY5LUVfPmErNm51O2FeSktefjRq
eTw4PlVhdHcmYmdNaDk/eylqTXhkSXlXZyNMejt2TllxNEchPFNkWUIKekNnfXRnVFVJLWE8IzIq
QGUoe0Q9bTh4VC16ZkNWV0l8NDsoTzhUfEB6djxRUmBUY0lAV0BkZldNIWExMFVvM1FOCnpNRT0w
YDtvPW54R3h4M1NpTER3ZTJneDhPNUFxKXZhJEEhcmJ8TDhAMnJmbyQ+JlRmOCNILTReNHk8RTFt
U0o4aQp6TTUhMGUhc0V9TE9MdkVFSkpWdjIoZ2UpdSE8IyQzeiltPTJQS3BmfXprYj9xN2QxTChO
Sio9fUx7OTJlb3ZRR3QKem5yN1R9TUo5K3FuYWF2SytvZn1nNjY5Tm1LeEFndTdhd08pUmJxWVRz
P1lZRTMqPVZEaSN9VDNVN35tYSNsM1FHCno7PjVTTiM5RW5iPGltWUMwdEYzfiVsUHxAbHZZNjNf
IUNwSkp4SjghYkpjZ0tQMzBSfXUkd0A7SEU8VD9xcSpXdwp6JmlaaCopOG4qaXhTRWBUP0A7XnFY
TkNDME07X2E3NktyWjZpeUN+N1psTmIlQlIjIXRyRjJaI3FTOXQ3UkF8c04KejRfI2VPRT5OXlIr
c1NvaTk3JXBkV0hLSVZic313JVRYflJ1WWp0KSpDTUNLPl9IKDs0ND9kPlNKe1Y7b2B7UTI0Cnoj
Yjc3VmBVWUVNQVBJSkg9SDgmKl8hYkJjZjl3LV5AXm1HZnsxKnd2V3xzTlF0SVdraDZILSZxZ3pS
YTxyQ2hAfQp6P0NNdlE+Myk1cU40Xmo5SkVDeCg4c041IVpUPSlAaHZjMilqWi00Um85Uml5YHgl
LWl2djZGdFUhe0olJGopcG8KenNuMnwxSDV6RjdQUj19YG1DRHI7Z3dvR0pPezJ0P0VNQn44QT17
KDBnc0M+fT1eOE5VeEB4KlUtWjhLeXN6cSQzCnpZbE9mNnVaK2hTcXFKZj9pWE5TNGA1LUo5c3Uh
eHJZUVdVMEB9dGh9Vl47Y3cjaDFvSiUjWVluOFUoNUdeMSlKZwp6JTtSO01Ackl1fE0yJEhUR3sw
SlhzPHlGKlgwYjRNaXtaMkJjZW1VbUN8MGlsVTkpdztxKEdmbyR9eD80Klg4c1MKenIyJmI/eXgt
PFRVdXUlRj0qb0ZIRjcqQ2RmQmR3Rl5UcEApemUmcUU4MWliJlRDcDtYMX07Zl5MPXNnayZ7VWVB
CnppWDVPKTl6dkdBRVFrdml7ZkZ9QlQqaX1CTl4mfkMrSnNqUF5OTCMyTlM/O090ZkVzMys4OWp5
cEk9fT8qdFpGYgp6S0NUKXJzVCF7aUtYO309WmxRN2c0RDV1eD9xSWR2ZEM+OT1kSzE+Z3VJZiRm
NG5nKVBeaS1sRkcqYE11UT14fWsKejBXdDlERl5hO0I7cTVlTVNsVXV0PHJaKiVJUUEjYlFJblIz
aDxAZ3tfTllgZUg3YURySlYrUSZzS2lKN3UyWjxaCnoxYE9MP0xgRTJ0aCNPcWNObXd8VCQlJSsq
bS1XVzNXbzMwU1N7JUd1OypVaV4hYEI5RE1HaH1uKXZFKDxfKT11Kgp6bHN8ak5acGAxaURFSmJK
NmZnQHAlX0xAcyZPJlh1VTlxZFpNaFdIO2BJa3FGMyZjU0ZmMWBJfEx2QihsdXhgcWwKendPaypG
Z15LO0R1TFBGa1Z8R3loUWFEa1pqNXc1NW9LVSYhd0BZSnZhbTlCVXlaPTNnY0VgUTQhQE4/IS1M
XnYjCno7MktqfipTe1N1SDs3RHB8SXZacXgwT3d5bHo5QGgjKmJod2s0JHRpYG8wM25wPjRfYD13
fnFIQ3A4QSYydEJmUgp6eWZUWn49bm08S1UoPjxWQ0ZuSlJ7TXVwN2I/czMkMT1KKkI3OCF5NmFz
IzE+QXEwfFhOJjFnOzZ3RDdkRjRrWnUKemxBQWskMm5ZQ24he3ktR3NQTEpPcCp2e2QzRHhyQlcp
KkBucko7LSMyflM9bEwwWFgmR2cpYjhXfWEwSnlOWSFnCnpnMnh1YndLeVVDMS02IWQqXjYxWkph
SD1BV3NlcmcwMHdyXyQ+RHN9N3ppSnlAQDFDbWlBUkomazdsZkJNX01Bewp6MT8/eGU/TFV2YTh3
O099bCExd2Nie2VTOG5KJkolY1pBQyVCeDc4PHp4Xik8dHd7ND9JdDNHYXhpVWl6UmMlLUsKeiZQ
LWh8X1B5WG4xZ0klNXFtXzBGZVkxeHVxYiV+d3FHI0h4WH59Ml43al5gdGd7eiVJMT8/X0JEPDtP
TFV7UGhSCnp1aGYofnlAOHFSYGh3a0NeODFmRTNFQDR8e3wyLT82Q2s1VUpqdjc1Iz0/REFHb1U2
fnU5TmImUm53IUw1dUJ9KQp6YyQqOE1SdXZQSj03bih7UGhSRWtyMUY8JEV4RGUxZmwhOy1UcHhm
Iyp1WWB0VE1VNG5qazJYdiQoKkgrM3tsd0gKeiUhKj52IT1hMXUhKiVoJXBJNCpkRyhoNCgkaG9V
ZihDc183TEdLQXNySzx9djsmM1R8cTQlNU5VZD1LI21kP3g0CnpoY0RPKEVuVTRBWXFASGV6Y3hA
WF4wWilWSnZ5JWBDT29FX0ZWVGRiaDtxc1plSnYpakgkRT0qTGReakNIXmJyNQp6N0J5KHtrPWQ5
JVlMP2NGK0w1cEhRUUA1OHZvfmshR04zVEdUemJAJnFpPTlXPCsrWFNWLU44UyZrTisrQUhnST4K
elVTPV9KUlUkWDg2OTxfSnNBODZpa051Mi1OP3VJSClsbj9lPTl1X3EtTjFuZHVYN3JZTF40MEdW
dW8yNmIwbiooCno8aUt1PEdxezMjSHp9VyRPTT5Faj98eGhEMUNyM2hndHZSM0lYUSMxJFJSSGtn
N3QzXmgwc2tHOFhOQGZgNj5wJgp6Y1N0TUlOWkpPRV99YHptRSZURyY5PDVSe1FiRyFuKFZVMFdJ
bn5MRmRLNnpqMmMpZ0pJPz13ej53YUJ6emYkM2UKeklhRGNVTEBxIWYpUEAjPk9pWllpUSt+Xmp2
OEBZXnBDKilSIV44PFNjOCNJSGFAdykhPndzZHR5elhQZ2gkcXhzCnpeZHhYOW0+fVVONE1yQksy
fT13Vy1GUElwWjRJV2U2KFUqRW5aR35VbnAtaTBxd3lyN3Q2cT9sJjFMaUozKXEhLQp6NjA9PkM1
MDAmSyUyUiNsbllxa3BFTD1tQzZFKiNRP1FldVZeTUdNdiVFSFdqRSlsMlo4bVE7I2lSNFNhXklt
Xy0KekRJOHAhNjRaezJSdnQ1KGwzejdtOSR6YjMhPmBYRHZKenhwOEFMR2BgUDRgRHNaVWdsVWdt
Y353dEsjc0ZqMVRRCnp3d2UtMlJmdCs1NVNFd1BwWFFld0FjayZhN2cqRDU2O19CMD1OanxUSDVw
M0JuUUpuZVc7JT9hZGRqbjZANWA8Ygp6a3xpfDskMUFiNEIkSmJlPilyOSh2QDh+cDRTPX40cGtN
YkBaayZqUlF+Mn1FNz05dEZeOFVQZXRNKnFNdWZaPmsKel40OH1UZyEpQXpfTnU4OWU+akl7RVYq
eXRpVHlrakdjZ2tzckFUWjRWKmkjdSU8PUVfdzVlZmRUQiFeI1YmJF43CnpWT21hOyh6V1Q5aHUj
KXxqQGptZnBEQ0VeYlZCVzFIM097QClwcXRqYEZ3PmwyO3U3S2p3RTJRPVBiS0lPc3NfYwp6Q3ZB
eTFKS1poUFUxMyZAQTtaWiUhezEzN15eMy14RSpsa0QlQVFSQXMyKjBNQz5nWGY+Tyg1T0woNF9U
NTxFfnUKekg+dzFxdjIlYiZnRjUoRGZwdVgrU0NCLUY5MU4ydUpQaWplWmlDVjAmeTFOQXpOcyom
QiR5WG9USHpDfDMrZD1QCnohVEJ1N2ZaJVdNS1R9UDBJd0V+dFFgOXFaZmcoPjJkYTI7fD42IUdD
ZylpYzVrKipSKjlFc05YOGU/OTdFVUJQcgp6d1N3d28qZjZzZ0A5clklOV58XmNgbC0tVDtQVFl6
MnNwWUYpeXstJSRAfGdDJCM2I3lRR1F1N21VOWJWUWcoT2AKemJyTU5SNT9gKjwqJGkqSFhibCF3
bT1rNzYxPTJGbyVBamZtZmNAaWdeKlIqN2lFcWc0VjN9bCFhX09gRyE2TiZSCno1PyNPRGM1ODRq
MDRRT2JKOGk2MC1uXmdUejtEZitLRW9AYTFUQ3pMdkV0c2tiVEUweTgwUmNJdDJ5Tjxpd2Y2TAp6
anRJd0I2TTNvXlg+d2ZoVkBDfmhyYUhlR3FhKH1IV3RHXjZWMn16SjYocDdNKXtFVXN5QFUkfmZI
Q3wydGpeOGUKentOeUxXPylyVWxIT0FDJFM5eEB2ey04bmhnRnkwdkVpbGJyVGkyQ3JjMj47VW1f
QVZ8aXtlY3pyektSLWdGZXc1Cnoodz43ZkxqWG9gX3JYSmJmaX10RGc2ayY1RSsmbEZiLWxNcSZR
NzI7dWNyIUdnNHZeY182TDw2aHdUMz0mcGJyNgp6eWFxaFlzK3FWU3FfQTtoRFFNfEBFNTFeS21i
alBwUF5TP0x2QXYpRDcrVURrWDhNdzgzJkJkMTE7bUktVnlGRUwKensqSEV6Ky11ZzBVSH5vVTM8
d1gwSH00S2NLKVhQT3tjTUA9QnRiQDU9VWxuN2A9JEs3PDBuVkJgP2RsbyZJV1RjCnppfDR6dmwk
eWp7SiV4VlRgfEJHZDV9MSVKTnF0dDUpeE4oQCp5eU5WbX49ZkYxU040V0dGLUBPQVd9aVYoRmhj
Owp6Um5gdj0xZHlDb0d5TWlFNk1iJktFbExkcDltS0JsSFRiUExxaElAYzwpVzc2UHFhUiZySVgr
c09qMU5WUnE2eDcKeiNxTGlDdkEzS2lUK314LSZCXnZ9PmNXWlVFSmNRZytjfEooYkZ7dElVZUpk
MW9hVGxRUGI3eVF4PSN3ZHpobndICnpjTiltUCtKbTlSJFRpQUxiJClZWTZrP1p+Wnd0a3JAODIq
TmskNz8hbCRxTjBaK1NZRz1qVlNrJXBVK21iTShVLQp6YmViOShUJGhoKns4Z0UoZ14mWCV3QmFS
ajRYaFJfZ2w7Qm1hKChhUnt3fX5uJVpELTAodnBYJlUmbz17QTh3XnUKeldqWDdoZWpMZVZaai10
QkVXZnwwJVBUN2A2SGg5NkxwKUpgQ1E5IWNgUEQ/dT5OJUstPmB4aFBCdkx7TVlHSllDCnpQbWRm
WCtIYU9AYT5YZThAaSh1PWE5UGJfQj85Klg7XislT1kjcn1sTTMrQXxQeEFPMFZraGwmVH5xN3BM
M1FHJgp6bXIodGs3b01BNUA2b3IoeXxHYSlXc2EhQXZUciFva2dKZkIlPnx4RTF6enFKazVATk49
PGdLKjslby03YCQ/Un0KeiRgVzxuYzd3dEtVc2AhQEt2T0ZaU1ZEIT5Ocyo+a2t1MmhDWWlxe3d3
NVhUUjtRITxwPCtra0l0dypacU9fXj9oCnpHN3x5Q0ZeNkNscndOa09DY0UjNWJ1UT5LS1RLU3dR
b0NZKSpAeTdiQ3pjJTVXbiMlbCs8OExjQVp6bU5kY3FWRQp6Q204IStjcWchUUEoUkNvI1dAbEB0
RG44X3pmVjd5bC0pfCZweEx9NDw0ZDMrbGRCZW1HJU41c2BrV1JpbXVeaXYKemUtc1UpUz5BO2dE
KjkyP3luVCV8bU1LdDhVRkJOdzN0SUd5OFpKMjA/aEI+SCptS3x8U3hZQTcxPyFJUnFZfUwtCno2
MUB2WSpYdipQXzRqVkxUJjg0WTlmdmMjVkRkQGNvdmI9MUMjVV9fbn45Znk5TiU3K1klR0M/YEpm
T1FFYFZJRQp6STtINlFZcn1pMS1PaiRsd3FUPCYoQHFGWG9RPCRYY3NORkljWkltYFQtLSgxZCo/
fSM3RVlsfUVqaE9XeDNqdWgKemljWi0qQT9XRz08VDYlVUxARV4+ZXEkNWlEPl5HI3p7V00yIW5T
aHpveH1mcEVsbGZAaGdjel8qJlc8QEpNKmNqCnpZZD1HYERffHNIQW1BdilkXyNWOUMqMj9gSlom
SX5AV0Q3Pit5VjRaUiRqRnsyeV8yVGYmVGYrY3VCST5gSSQ1NQp6OzNVeE4xUWNqOW5JbzF6QDVj
PTQ4aytxWj9qSE1lYjE9bHd3UWNTRXgtWmI+YCQ+MzsrX2hkVDhGbyR6eVY7Py0KejwyPjdZJjM4
ZmY8Pmg3Q0twP2lAIUFDU0tPel99V05sOTF+dmAyPm0rOT5rP3A7fTlqcHdxbjlqe0Y+LTJKVSRO
CnpRWFIwLUB2IXpIQGI+bSo1c2wqPzEwSGYwNm0rT09LMDRBUXRteFE7bFlrdD5MRmkrNTJKd04p
Ky1JTX5nanBvTgp6bjsld25KfDkxPDExQUdPdmtNIzVfNDheJF9ZUUY2bFItKnlNLX1kXkJfI147
Um1Md0hmeks1MGtmUHRAZUVkJTsKej19RTtqcVBrJHotdExiMzQyTy1VJSNHSzVYWVkma0xgey0l
alpVQGg5VSo5UWZYKTc3dTQmaDFGeHZWe0E/VXFGCnpxSlIyZDZoJCF1RkpicTlXKERYbjFvWk5w
dFpVLWdtcTdRKWl6VWdGOGsoRjBod0ledEw3KHI5VG45JEt5PjRNUwp6K2w3UHZfQ2poQDRwdnc3
OW1YWnpXKjAhMCNSNns9YjNeMjkrZ0ZzeEc0MiFGRVo7P1FJJmNvTXBuQGc/cDRPMDcKemNSX3dF
X31ecjF2PTExRlJFezFpKDh5SDdjJU1gQHZBLS0xaUM9azdpciQ8JEw9RTUkK0pjNnxoWX5qezhk
XkkjCnp2WGZjai1uU1VVdWlfc315d15OQUkxeEA+ayt5QndyaWx+cUtKfUpZYFIpQSY+ZXJvc2ZC
O3tIM0h3VUU/Tm40VAp6d3M3ZXpjUXFDI0tSLVd2aHhzZj5pPXAkfDI7b2U/K3ZuTnwmfU5DdD9H
elgtODJyJXIoMkBGallTWjt0P3FtcEAKeldZU2YodCgrQnVlO2YlYVg7QzZ6cG9YI3ZeJDhZPUlB
aVo0WW1TJThoMGM1THVJTEAyKnh1bztnO15uY1VldTdSCnphRjM0SEo+NVh0KitFcyU+Y1lhdCpH
aHVRaFEyMUU4KHg3NGdZc1pYP1ZKNihCOzlPfThQaGVkbSZ4fU1FJkhGLQp6Q1Y+aTBNNTQ+P0U+
dnEwY31YUGdKRnpQZ2NrQGpoUHUyeyVacjUxQ1pOZGEqUz8pMUlLQkQ4SD9qIW9mdCEtX0YKeis1
WHBNNmtTKD8wPilra1loQk8lTHw1dmNpYjBeVS1CbG5oJHVRd3tKSCZJcl8raHYmJmZqR3ljMEto
JjZySFJRCno0ZlBieXRFZ0JgcFBYVzdiO0VwRldvMys5KVExaUNkbSk/bXItIWNoNGlIUH5DP3tN
WU1ESl9KQU5oM3Y0dktVMAp6bWcrKF49KE9oSGU3KW1rK29ERjFZJCUyLU5JS3VZY1p6NCEmUy1S
N1I+Y2hjP0NneHk9Kzk8VnFQb34hYE5xcS0KemNQR3pSKGhKU1o2Wkp0eSsqIXI+JiQ4VWswVmc2
PXs8cVUlOHl5WXtJVl8pd0VJTV97eDNXbU47MUhDKkY1RW9TCnpHb3MzcDZuSWJBUipxUUopO0FI
Qk1TV212enBJfkJkbW5zJT4pTG83TiF3e0h1RnJXX09tbCtPcU9HIXBhY2QjVgp6ZWNmZUhaQFpo
JS1UMzJxKCYhTk88QSlrWT5ab3VlYihUQTBrJnojJWgtI1dzXn5rSWR1V1RtZmIlQzYkTG5UVGQK
emBnZHMpVkckN3V7WkB+cUlNZGhkaEs7QTApWHJPJUF9emJ1KCtacnhrUnw0bl8qVmU1QDZ5Mygx
LU8yYjt8fF5hCno+KyQ7Zk0tRytgUThxZnYkJk1XK0xrMjZIQEZZa3lqMGt5eS14U20/KGtuVFpj
dTI4e3I7RFNYS0ZfPihHVypvZQp6NklsKmhhcXIkZDg3TD9XXis3ayY/MCRGcjhUNUtyNGNaZzhS
QUN4PGliMSFwUSt+d3crRDdzKEVmYXhyNVBRaD0KemUyMyF3QGZlQlI9V0BIVjZMTiF5aCZXbExH
Z3xKQDtIUTh1Klk2dExmUWJfcDlffDB6UXJzeGNNdkVqd1J5WiMmCnpYXj09MjgkUSVya3cyNG87
czduUHdZOE56TCFrTn5zS0heZj4hZEZDP1IxfEt4b2tmNi0jTCtkQkN6aGhIfWVkVQp6R2JMYVFL
IzJAbnotYSQrMEQ+R21ITFpFQWxzVD5Wc1dZWHIzPyt7aVN3bVl0bCprbTtUKik1dlBMXmVkIUQh
aHgKejRUdzFiKDxFclpUOUtfPnRAIVgjQW5aYE1DOyFlUzRNczs2e09kX0ohXllpK1FJMFBFbit3
U0sjV35jPSVLQzg1CnpufSUwRkY+MXNPdThIT2cyez1acSpNWE9rdGtsNSpwRlpFNilPQj1wbkIm
VnFufTNYfUdoM2NwI2J5PWhFJE5WOQp6MzRpMXApPjxqbWU7djt0KEhROzg8NFFJfU9VSnhweVBM
RDBiVH5BX0R5PX4rVGBTMFdvIzhKUFomT0I7WTRyZ28Kei1YbndhMEtROUwreWFtfEVqWnt7b0V2
Nj8keFV5NSUwVVYzZyNRMUE9dm5tRmNSbHtVITRLI3cyR0NZKmZSZGI9CktZP1pXR0BjI2tiY2BC
UiQKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvaWNvbnMvaGlj
b2xvci81MTJ4NTEyL2FwcHMvZWNsaXBzZS5wbmcgYi9hcHAvcmVzL2ljb25zL2hpY29sb3IvNTEy
eDUxMi9hcHBzL2VjbGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmVkNjhkNzEzYTgyNzVmNGVjZmE5NjYx
NzQ4OTQxYTkwYzBmOTQwZDcKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDIzODkwCnpjbVhWMTF5
b2VlX2tYKH0tUUJVJmlYZXp8JDBDUnpwcDs0fS1RQmAyQWV8ekooeEhIO3EpNH08Zip7PWBDRFBL
ZAp6fEthPWxwUikodmQyaTt2bzFjNTwmYiVte2ApWl5fT2hnYV9rPXw4REolQXVNeFAoSWxjO01l
Wi17RGdUR0dWLW4KelFxdUZ5KnFyZShmM2pTUXgza0tePk5HTEI3bnxBMHNWTDYqeEFBKGVCQygq
TG1GR0xmK159Q0ZiKGpZbCFMUXEjCno/c2RJU2otUHNNKG1QOCpsPzEpREIkd0hKWlJORTc9YDZ5
cmk7Tkh6QWxHYlFeIT9Zej8hJlYrbllva3JvREojNwp6JGpHOUskZ3JDamFJdSNGMU9KTlB3OyYy
aU5fYEdJMiFZNVdgVVdZWVA8cGAoNUUjSHVmZGYlZT5SeCpXYVVjLUkKemlYOyNVZ2AkbzgtPXc+
TSNzZFQtajV1ayEzejRYWU9TO1hVJnMmazRAc25na01uMT9UJnd2en1rQmlBTj1GVUZDCno3MUBx
XjUwPnhZO3daWF9LKkZSbGo0KlgoM0ZqfHp5UU9AT0E2R2xNOUc7eHI+RU9DbUQpOWFPQlZGVFNn
cDl0dgp6bXRDNGN7c3g3b1J3KjgyRzhSYD9HQ18zd0lJOytyRm9ifjtSfHlZTnFKZjclQ052I0Vw
ez9fO3hieD9iY0xTM0sKeiQ2ZFpZQHxWNW9HcXR1Vz13dWBHY3YjJFQ/PkU2QVpwZ1E/U0M0QjlS
bjhEUT04RCgmO0tEZCVCK3RkTHQ1SkxuCnpMWEY0MCF8XmtsND99fG9sNj9pbGJxJGlPXj55dU9e
fX52aEl5QUl0MTxMeVJ3ck9OcWBuaCZZZFYtOUAyZCQtYgp6V0tDVkRXUFQrSTR1WU9tNih0JUAw
dF87ZUxYfFNGNzFFX0s3aVFweSMjMnYlO29TfGY2bUJ0M3U4WU85TlN9QiUKemAjXnRsZHwrVnNj
cmMyTzYrNmg3ZVdFRm1xe0tuU0EtPHpPZ30jPlRLbXdpYyFPT0BwZXl9JGtXJGlDMCRvYm9ECnpe
aztnNjFoQFAha199MmsrXkRMXnorQCE4T3RlQilrZmBlQjZxNXt+XnJsSmhhSmEjWE1CQmo2Ujsw
flZSN3BmKgp6aE9XfWokeEd7P2NqZmlxNFNEbz4yWVl7fSV2Z2RZTUk+MVUxSG9QLWo2Kj5hYSlk
dEpGZjglQlR0XjM/ZUsrRFcKeilnc3orck9KSnVKd351ZWE4blV9dnZBfEtXR3YzM3NXVjA3ZUcq
WnAoITlnPGdZTEVfRlNWdzFyTS1DaXNNS0htCno/QHYwdkgyQUhMMzg4JlBLUnBXSzRwcWVNOEhE
JDg7JGZ6NTtnc1EmJT59TXpKflIrOGFmPmJPXjNmRWZOfmhRVQp6X0c4ZU5YNGk8TkxjayszRTBS
QitnRnlKTHJ0cCY9V2t2JFI9PmwjYVhEV3NfLUl7T3R2YCZ3ZSlHdmdgTDJXcE4KenpRTnhHP355
PGdSYDdZcXltfGt0T3JmQXotOUp4cz5HblQkUVNzfF5haCFCPDIofD4zQTwxNDxseFBNclN+JEow
CnolOzxCT2t6bTspIVNvRWFxZV9wSnBYa0hSYlFmY3cxQTxeS29KWnxZcTctRzFfR3ZzbW8zSHNW
Mlc7VEZ1XkF2fAp6RDxDZEs3bG9qVDskWEEhPHcwbks0TytoRnZrbzF4NCgrcF5uJX1MI2RNckxG
bG4rYD9GPzNjSEEkWlh1Z35SdzEKelFxTntvKVNuc15BSXElMWAyOXhrTnAmX2U1dVA/LWdtU3A2
V0dwSSNHYkl3cXtLTlhUcWQycHBjZkVEeClhekpnCnppOT9zX15CcHhJKEZCKCo5MTJfcyU2RE5m
NGxpK05nant4fjx1YHFIJj16ckU7Tnx8fVYzNzxCNWY+R2lNfVJ6fgp6WmFoSDxebF5sIXpNVSs2
V15sdEAxez04ZXdvdGF0Y1h6UTVmfiZfOTRaeG0zbEVRRWRLUXk5SHZ4fFJ3P24mTD4KelV5Mz17
UHAoTDBtQCszKSNBY0o0YWB9fkleMVEzMGQ5e3BhSyp+a2NCTSlvMjt+fSVARGpHJEZCcWREVz0w
am9WCnp4ZDtyP3pJX3puKztBQkZ1LWI5KnhnVX14aTxKbkVrfU9RPlo5LSZHM3JoRkpoXyNCQjdj
QzNmKzF9bFUxK3R6JAp6YWdPOSUlOGt3ZTdpQiUwXyY2PDFxKE9eNUteeDQ1dGN8RGJWc29VfExo
PG8mbHUoRzUlNDJzPnM1QTQqMl8xY3QKellZe1V8WnMrZiFuKE1HVzxnIWxYTXlEOzUhR1hgOVZA
WjV5dGgmaTw8ZCVjSGFpOXY0Q1RubmVUVFBUbig5O0JrCnpAYE9HYStfMjlPRTFURzQqTG93bEZo
K2lITGFxJkNBYzJjd1ZDTGt2cGAqU3JeIUFSPSsjYFB2QnV4aEc4dTw+agp6MDtPJmc2QTReaktZ
bj9pVVo3I35ZeGRrQjheb1R9ZygmaFJmcUorUWIhLT1OWUpCSFFnVSFZPkxtVHlGJXxDXzAKeita
VTlfUjhnbyQ9MDFgLU9QPlpFaVhBU2BDVnJhdWMzR0wjSjh+cns8PlpsPEp5P2gzKnBDJEpZYmpo
X2VtMnx1Cnp5TE1fWCV1c2dpNmVuWF40Vyh5fHRFQXxxQzA2ez0wWVIhb048TXFJcE00cUJufHom
QmVNP058Q0JHUS0ySiRVIQp6VWE4fFVZXlhrdTQ/PiRPSF93clc7VipDXl8jS2tDYjM0fmpUM1JG
aERtSCFSbXlQNy1mQWtAX3E4NlU7OC1mcjQKemxwJjtXPG9eQlFYeGhXYyNeO0Q5JFNrez9GYklX
OD45RFZBVGxaZVNTLTI1WllFcG05WE9rVXg9blZ6dzRhfncqCnpYck5mPVB0KW8wanM4cDlpJk9T
JVhFOz9zJkRyZjIwTVJ1bGFFQiF3PH5ebGszYm5GTkwkTjFJK3U1KnpJM2g7VQp6cUdVK3RWczs5
Kz4rakppPVJhSFBDKG04OWd+dEJ5QXJNZkgxITt8KGJJdFR0N3V0MC0hNmkhcDltSmR6THklSkMK
elA3ZEtndnJuNCNGUnI7WEFGS29kKFBFb1I2UzdhRUI1aVMlRDhQRmJKbkpTYFNaezRsWDNxcDFK
eURPeE9Xdz9hCnpGUzlAYm5WRmUhRzBsNWI0d0YrO15rQEc1SmtBP0BoJj02UVJnVmB3OVBrNCpI
bEpRX3EzaDw+Si15K2A/PD18YAp6dSQrfC1YYSV2JHY3PyF6a01kQDdGUGx1K157TzBJU1NUczJV
YmRRSng7QipKRHlANEs5ZV9YQ15lZHBMZHRGfkMKeik/Un1zRi1LfjElfnJEeExkfT12WDQkMTNi
RWB0MFN8SVUtME94WThvIUx9bF4lfEI0YXpBMnE7aXwxU3BBaFlICnpDeFdPanJ9cT8mLVY7a1dQ
NUs3N18jfWo+VCV1NlBnejBeRiltX3g9R0h6fDsqZ1o3YjRfQT43USgrYHBVPH05OQp6UiNzTjdl
PjZNcXtoWE87VnojeGw2Xj07bEk4I0JQdUpKUFI0M0NjSG1FPk5NbFZne0pzLS1nZlhPTipMKkUq
RXgKejZSKFo+JW13PEteVXkhdnQqLWFweW1Zcnc8NGFjbjYyJjJJdG8+YT5vdDRhX24pdm8jWWN7
RU1VJmUqTER2emFuCnpjKSQpVHg/REJHTip6PTtVbW1ENSV7SGw9b31USX5tUFNOSU1rakwrMEdW
OTxqTTtCQ29vKk5rKWF8czlBe1Rtcwp6LT9LcFdUZVRZe1FyZyhGeDdkUmR8TWFzOSs1bE82MWZu
OztfeiVCdFc3VElIbGpGQlNDTyRKPj48QjswKX0pOFUKenUkSTc4cnxMZXh0QFlLKj42cjxXcERJ
VUdsKUNhMHRZcDNwNGd2UzJIczlUQSFzYjdqeUViNkJtaTluRDhySEhPCnolSXFTKUlGZjFfU1d7
UihNSF9gOEc5a2FKSC1PJDtHT012YGBTRz4/ejZKIUg7JGRjJCRDOUhUNUpSKWZPJFZEeAp6dndq
O2gzV3VJdlFaPyE5bCQ1a2RCbGNte0NFX0EzdmtmPTR7QzFrPzZPQ2A9YTN9dlZnfGFPNyZHd3BT
R0JYezQKekpAaX5iaWtabllgRCpxM3djTmlNaGhgNH1OSVRhLVRJVzMjV1VTRCVqdnBjOTd0b199
SE5yXjFWOWcodElTXkVDCnpMfj9iYmRkXyZTQEpVbV5jViVjeGRDWmVUZ0E8WjtJVTk3XkgrI1BP
VWFkfjEtZUxTYUR6YSN0VFNjKk9YfmZWcAp6PXkjWElnKmduZSQjcG10P089bjd3fUNQemdmM1Q0
KWNtRkVPO2A/cl5GRWBFPUBeKEFkM2RvR0JaT1ZnM2ZPdX0Kem17VF8oN01TI200RW9CSzxAQFp7
THV9QSMhaTxURFk1I3hZPjchNXNHY3ltKmg4NDFXa0lUe0w3RFVtJDlXQnBECnpwI3VHbjIzNkQ4
e1dHPmRvMTNoQzdnd3o0eS0/dmllJT5mWmUha2JMQVlmQUdERkF1b0khdlpNbjxnRVlLUlFibgp6
bDNZRVheWS16flRISF9oNFpqRH12bW5ieC1yIVlMRCFjYm5Pe2xjQSlKNjNydDdfVCE5UzgtSHJX
KDhNa19YRGsKejc1K08mblFxZW4pZ0E8OHxCUjUmLWFmdHxSUXMwfkkpR2ola0JKKFdVeFQqYVhQ
XkJGR3I5OFcmR3FIckt1fHxvCnp1R2h0OVpMeFdKZHp5T3BncWhWYVY1JGVpTkRWYlhqOSNmfXQ1
YntGV2dDUCpmbjhWJEBKYnxDVDB3NG9KQFhUQgp6cjt9YTV4a2Y4a3dDenZLR2VZUktPfTROMV5i
TWlMUS0hODEoLTtLKGgmMl9jT3V0O08yJHtgZCtoO0NxSzIqP18Kekl+Y309VU1yOGAoc1hldmhS
JHVmKVh4OWRYV0xxSFI3aV9COzZkY018TXJ5OWVQVnt+JiZRcmwoZmBAbEBQWD9QCnpLaG5NeDNr
P1M/RkE0PklBNnZFOTJqOzAqLXJtbnxGNVFtb05KVmReQlNUSzBGZndSRiFWSkIxOSlFYikoS01T
Ugp6OWdQNHJhSWIlV3w2byk3I2gtMW52emFqRCZVMWAxOXlJanB7a2A8THAjOUhoJiprTHI+SnYq
LURGWjw4Q0AjKmMKenUyPUo0JjgqJUkrfV5CeTA9KiY5em44bExmSUY+VUAtbz9NWXFzaTRfVTBq
Z2ZzfThYLXVaVUpNY0F7U0gtNEpuCnpuQGVDQ0Ika3hwQWojJl88PGc5cXNpXj1xYFpHPk1wMnBK
QSsyR1dhTjJfNzg9Z0N7LXopS3VyTj1WYkM7b3FKOAp6QEI/Ty1nTS10V0B2RTMoKEhhXzw4ajRB
ZmV+ZXY5JT9feUxOUVY8cUxKYlBfT1khTCFMMS0wT0hsZGF3WTdrN08Kemg/an5qPl96cTRUbEZy
QXV0VEVtQk5qfkJNdzRIay1GQ3g0em5SUlczfnRHeDhlbVk5TXBhWilkYCpwfGUyNGYqCnopXzNr
VTFvc1FyZE0teF4qJlh+RGlNeD9uVDJ1TFJ0WlBMWjxQcSY1KFNJa1dGSCZ3OG8/Qzg9ZW07T21Q
Vy1vPwp6PDNWR2U9anU7QlVSPD1eOG5oS24oN3k3KmhQKil9SmIzPD94dWtaQjJtPHQ2biY2bXxw
WGxAYlp6Yl8xSF9rM0QKelcjeEUpK1U8Nlo0c3NoQ0okQ2M0WEtUMzclNXp5OEZtVGwrTEgyWTs1
IzZrJT56bCg0ZH1EenxSWXtubE96dzBpCnp5UDM0KlJsQDJJOzF5anlyNTlVMEUpQSFEbiFVRnRP
LVMmO05DZHhoOXh8YHxnUmFjaEh8bjRET0l0RmdhRWpqYgp6e3BHI1ptJlV0NHREZGpkT1ByallV
allmfjQzencqN1o7MWFkfWRHTkFeSWRhUTUkendzSk99UldLNWR+UG89VkwKeiE4SlpSOGFWekpQ
KyNHT3ckPlYmbF47dCZAeTdDb0gqcWkmRiYhQmpxYjJwPjVocHdkZ3RUeipDMWc8Z1hnfHxQCno7
UHNGJCN1eUx0PVZQaHliQUtkX15vI2xuTj1pIUJIfHBGV3UxTHxQc2hET2pEb25BbG9PVEtQS1B1
X3MmVUk8bwp6bXItQ0BITUc2bVJwKyhRb2JueHp4UH5kZEJKbWhXbGgmej8xcV4/UHh8Ml4zcF5S
Xks2ejZiWEllckVIbjsrNzEKem5QQG5QSHNeU2c5fDRqIXpZQWJQe1B+dyVjU3grKF91THA0big3
O3lsYXloSnt9R0tzTmNzOCNVRzR6QHE5QlZ7CnpMMnVWPl9neXBwZXo+JVhmUUIyWUp2K3dXPWxf
NzZsVjIpd0w+P0w1IzFncCs2RDRqIT0wV3FSPGVFZ2BBJCtQZQp6YjBBSVctYSN3fjFMTjhxJjdy
WkRtTTA5YjJ7SzR1TmNMPF89dFlQVTQqM3lxZk1pQ2tBcXBacVFYeiU/XlZPSGoKekNoJHJ8PS1Y
RjhyKyQjYl5LXzdmLXwyeXU+Y3tGSmFrR0QtTyR7OWtOaGAqeSFJLX1hcj4qNG8yX3Z9SlI5N2dt
CnowSnwlY1VlY2x2UHErSWQwPUshTExxfERoYVU4e2l1YldmeV5lY3NFQWtIVkVoXz47c1VRPVAr
aWBMTmZka0dmKQp6U0tKYXJ3NXlAPWJhJnBNZiEtI2w8NTNodTVlYio9RXw8YnY2e1JNbEkyPHE2
RXYjPXFsQldLYkNtIXQhaUE1VjMKej1PNyVDd2R6V15TamVLVkNxSVcpalNzODdrOCU+aklHJl9L
ZSp4YyYzbHUmVlRwKUxic1l9QW1lNnxfOGZCa0JpCnpBYj9oNndpYFMmMWVofEQpaCRgbjBuZkpW
aUBURH4lRSRqKkpzXyRtPDVkKWdXMHF6bD1BPmYyVXM2JDBFKm8lRAp6d05eLV5XYHFtO0J+NlRq
JXJgYTtHVDhga1VvRiNAQThAay1teVlAMU1SUHpUQi1rIXFfdjM3VXJQWC1pSUdWTkYKek89ckIy
dSteVD9UUmRvXipYSzFtYjQtV0dhfFlueyhpOSpvLVpNM0c3bDBnaTZKRUpOWXI2KyopTiFjV3xO
cGV5CnptWldoO1BLflF3MT1vZk9gVVhOK2RnKjJOdzZBUXxUfmVTU1B0M0QmaFA9VUBrZGNwdUhs
Ql9jTypyTnQ3YXZ7OAp6TDh0eDNAMyNVX15aOUAlWH1RdCMtYXUqNFpFXzZIT2ppI1FgbSpJSCRJ
ckM5YkxBOEE5blcrZnJeK3ZvbWNyeTUKenVPTT9XZD0tenkzYGlhNSlEU0VQYjlIUlZoPWshQk8t
SGk8e2wzYXN5eC1tSGV1OD1vV3Y5K2Y3MV8wZi07QkxICnp2LV5wb0UmJjtfb2gpJWhiWGQ1Qm1o
NnZUbmVYSj9oQlZifiZBKEl5ZDA4QzBvNVVIO2tafD9wdzdrc0FgTSp+bAp6cGJYfVple345Jk9v
I208Z010LXB0enxwXllqT35QN3NKcjU7KEt5JWlpOGdHbUF6Jl9Fc1hRSyRZUnUqPWV0Xk4KelM3
fSh3Jk5wZ3BVc34wfTteTVNeNGAzVkphMm5OTSNFaz1PKjxGKyVxKjZTV2VJRjhUSmZIcVBMYEIk
dGNAPCpzCnpQfEJTZkxRTnUhY0Nxa3h3Mi10PHdSVmFYOFRKWndsTFl3NjkxT2VrLWNkc0RNNi1V
PGtsKzxeUTtGMnpafihkcwp6OzBoam1kQSlteDBDUzVlTDJEaWtgWUA8NDk+QzQrRiQoSWBZbkk1
UWd6am5+MSoxUDxSSVdOUFZmcDwwJCo1O0UKenp0JmJpIzZ0dVFxbzJ4ZTZmWjhZe3JCdVdsODhx
Ml5JVk52Sn1ELSNfbyNwZ2lVbTFTdVFDc0xVNSpnSSYybzRpCnp2aERVeSpgWWBwSFB7MUU9KXUl
Vlc/eXZNZT5sPmlzSF5BcnNRTFoxPnYkTndZRFY/SXpgJVN4e2t5d1Vrd3x2MQp6bHIzZkA4fj1N
NFRxPHQjZ1UrYlcrVVFlSERQOWpqajh2X0FRSExZbWkkTDxWXn0yOWhTKHcmUFZqe0pVQ0Y3dGsK
ejN2alA7QFlrMVFLXi1eUG9NMXRuQT1zUWtXREs5UDdxb2lqazUxQkZFPHhzejlUdnYwIzNEc3BC
fWA9amxXNzlJCnpiMUhGM24hUk1ee2hFeVhrez15Nzc+Q31Eck9XTjI7MT9HY1l4X3N9ck9vNilY
b2NzMmZvb2Z2c3ZIeW93b2EmSgp6NFNvRj03RWdzOTc/VFEqR31BcHBRMk4qdnpoMTFTKUdod09P
VT1aQEclJjd7NU1DIWU+QFR9aEMjUnd7JU1uP1cKejZrQiVoJktwJm5BOXlOekFDWVlXOGY2UzUh
Y21DV2tmKmxSaUh8ZyQ1MiZ4ZmtgaVQwKk8+SDdASTUobD9JMkl2CnowblFDM3NeYWpQMHp8PWVi
ejchcSNuQ1VvPCVoXjNxTDY0M3tqb2Q0IyllTn4+THc9PjhuYio2IUNSbXpJeSF1Mgp6Xk11KTsp
UCRKcmVnQEpidHl0K2teOFJtMGg9Snlqbl9Ve3c3TEl6ZDMwbmZRTWNOYkx5NyQrIzt6KFUoT29X
LWEKellxWUZ+OFR3cStzYVRRLSQkQUpQRU1KVXB6KXBBT1BePnpsWXZtMDhZfmxYMGE1PWgmRVM7
UzFCTDd+Klg2YURXCnpEPVReOFU5OD52SG8jMlNuak0pZCNIUH1tZ2kmfkBzMXYwIT1vT2g0YDZq
MmBUdiQ8PEFAPzMhej8jX0Q4PXVBQwp6MkRxP3l1KXBkSmN1M0JCPmIyUz9Maihna1RxUGR7SlJ4
T3dgLSZiKilQNTFLWG83dik0OzU+dUU/blBYalA2ZiUKemRYYn1UOGo8UyNuIzlHMXJlcm1VTSVC
JW84cSFfQ1c0P1NkRDlFN1RQbSpUclRvWHJFcWlKMkUqO0RHPi1pMX5ACnpGb00/IUt8Qm4+Ym4o
Z3dCcEokLVlaVzEqPkolRnxAe1N9WTE1OU1PVm9adC0rPnV8XjNFVHYkbzlvNVhOdTNMKwp6b2VQ
UGJRPm9ic2lMMlBpfEpYWWB0JGg1N2khdWEpIVNrWUhpO14lKDZyNTJBNno1Rm5EPUt8KXQpVSRM
VihNQnAKem09NWo4YH1KdkQjcEw0UlZ0ITJ+MXZaTzIpI2t0NnhHYClWPUpZJE5XT2hYUlNGLVo5
RTg/KTZ0QyFqaG9UPzAqCnohYDNjMnpMKnBFYX1kYkFHPTZjVDxiJT1CVHhpdldvWUJ9XiVtSXZE
cDZIWVVJcXhRb2N1ND8kbGl1NXg8NHo7YAp6V1cjPEF4fnJkNk1WVUpBOW1abkVhWEF6Kk59QSFw
ellURm5AKDRKcU93eXpIPEJMQmUodkhOakJ0UWhrQ0hmOWIKejUhZmpDSTFVMmFxU0UlP2d3KGV6
ZE0kc2okZyN6VjxOeFVzQUFhK0wtTmt7QkB2JTFobSlXNEFDVkFVbmlYM35ECnpVPUFlVFBFI31X
Y1lvPSFBN2pCcyZzaWY9MkgyIVBKYl88JndiUnQ8cm5EekFqbVQ7bzgzcmxSa1AwKVIpYm51agp6
VFUhKHJ6dEMkOTx2UTRsZiUreEtmIUI0QlklcGxWend3UXs2O2I/S0RRMHtMdkhZSEFZSzxMdT9K
Wm0wRCRRfmcKekBJSDNUPTtwbndiNTZ5dlQ9SHFJeWwmdDYwRDlCKSQqQWdqcFFqIUpXXlQ3I0po
PkhTUC0zKS0/KHswNSRUbk55Cno3Tm14N0cjPGcoTUJLfXdYS1RgKUNLOCstRGJQYlFzRSYtd1d7
V0VCd154QWhNcTtTajxmb0gydipSelU5cldGawp6KmY2PVRPVkBQKiZUX21DbHthPmtoK297SURa
cD1YQnRLZTtELW14UHVmPWlrdGx+NlAmZmVLcTlUNj1gM207ZUgKek5KUWFpQ2dIeGExdUN8cU0o
UkVxQEx+bVRhQSQpY1lTNjdWRkU/YFN7JTByWXdEdFQpeC1qRj8tfV4+fl9LSX1eCnpEalI9O00r
YjQ8UHZMaEg5a01Bczg1eFY/bi1YN0lwTHRTdG8yN2c4OStFaF5LPjJQX0J1QX5veUI+fkskN0ZL
fgp6MkR+RFh3S183XiQ2SVBwJklTdUNDdEFGJm1YViYjaXpReWNsZWcxQT5adiUxWGomYHplbCt9
WkJsRGxGYD9mUUkKem4xVzVsSWAtcTQzNXVQQ2IoMUdNczN+NFl2ZVckd3NAflZkNHczd1hzMSNo
Myh1K3FURXRiTntpYGBKbEV4Rm93CnpIOHdhQEx4fHh8N198STA3fTRMUitRcEprWXRoO01SNVkk
M3ZfTlV8WmBrQXs+fmxSbWdMZ3gwPiloKVNCTD9qRgp6RjZDd1U1fHtYZT8wX2UhP2pzZXcqSDAt
X2prdmpmO0JsPno9dTl4S14rPUlKMTc0WkJZNWR7cyo2czhPYStJclYKemV4alpBalRBP3g3ciN6
JWJiUCs1T3BSTyViWShxJTNWU3ItKWlCYVhvWng1QHg7an57RytJT0sjMGhsbWlpajZwCno2bE5r
UlF8RW5pU2wkV097aCgxT3VgaHdLV3hyRXZkXn4jQlc/YDVzez45OFFIb3lGMEM3fEFsRCUhTUNe
bHZBZQp6elVDV3J0ejEqMWk9fFV6YEdSZD9KMjZxOGlXNWhXS3l1WTJeT3U/fHZebWtxcnZ5Kzlm
cEFLeCU5R0NkQ3h6TGUKelQ7eChETmxJO3pWY3pZIU1OezVOUEUoe04ySik5TklVRDBsZjRiUEtL
ZVlqaERafSFvRGU2T0ZzTmNBRzYoc3JHCnp0XjlBekRRY05HUXdscyFNYnd+M2goKkNxeTI8VHk7
KkZUc1dMY1BYUXU3MFVHKHFuUT4lZTNeRVlNdGUmYX5PLQp6VVYhKH43Xy00KiRLZlZQSF94NGpf
IWtKUystQE1KdSpXezZQakgkMVAqdWloUHBSaGV1UFRGcjgtanpOVTNfazEKekFuLSF4PigtMFdL
XmZzTXIzdG98KGlqXmJyJmhVKipBYGw2QUl7IUYwcEA5MGF8K1RqI3lEWjcqc3o7WE5FLSZJCnoy
KkUxbWpjN3VUYG5+WlZfP05yY2U1JlgoUl9DQVZKV0pMYCZ2MUFiWk1sIW11Y1RGWSlRSjE+K3tD
WG0oX01RKwp6NHxqPjVgeFkhX0BDUE1+fEs5bkJmQHFQI3IhPnk7dEk5MD88RDMtWFBUTTExdGRr
YC1rP0dZKzxhaDgmU245bHIKelBKfWs/eTBwZ3hUOWRMOCojQ3oyQ2dqLT5ibVc2RDV4Qz5ibChX
fkNaQ3ktMlU3UyZLQHh8ajd3dXA9SyVeazloCno7dSg0NSMjZCE+a3wkdjxyN1BIYFFmaF9zOWw/
Z0ZweyZ4UjUwU187WCZUKFd5dGgrWDNNeUo0TVhTJWZ3ciEtdQp6K0FYWDE2e3RKWWlZY3FAPFEw
KytvK1BQVXY9P3JYSSRVbSszdlpkOHY5Wm0zckRMTFJEZlcjbiRXeCNUMjRRM14KenFDIShNMkJx
QUBnWlNefGFtK1hENCFJNUc/SnMwVmxDeyUhfEh7OUdXZDVxYHc4NH0lVUFAfSpKTX40dXkhTW1Q
CnpjXmlqMFJyU35WazdhMF5VbGMzR2UqZ3w+IzllWXp7ZTJWKyk3d3YzbUczJm14Y1k0Uj9efnwk
R2NWUCFJelJragp6cl9UY150K1hmZHYqKzBwUmc0UDlKNUZFclQ0ZXRiZFlZKXwjZERRKG0hKWU/
VFZPUUVhRzticGArUCEpSntpMiMKej4+eXJMc2x6dj8kMlIyMlYkOFd9T0krUnU/UFptajwtJCRY
ZHRTMVk0KTxwNTN3ey1AR2xsRmpYeVMjWFVuX2JpCno0Q3k/UWJRPD1aNGpNKCYqbDZPdmxUI1M9
PWY8PEB5Skt0OCp6XjYmX09nIWIrQG5qYTx8SV5OVWk7Zz1reXkkcgp6QVZTcGpHSWN0bVNRZ1Rw
I1YkeVo9WDN3RkVeUlVlSG9uWn5SSHlgeEhHaCtfVHFuRCozT2t2Y1Z3XkczOEVNYUUKenJgRGs3
SFhTIzdEP2JYbGgmPz57PDtqOFFPNFA5JCpQXj5Bc0hxd1UhKVBReV5CemtEM3VrOzghTnFSXzB7
QFZRCnphaVlzJGI/QmVMeylmKCZYKGRZJSV5VjZ0NHpKeiZmX2tNQEE1dW9EblR3QD87TEUtd01P
XzAlPD58N2hTUztMKwp6P30qfmRmWlgoRXZmbGY3dkhscX5DfU9UQTVCI0hUc15DY200WGBINnxG
SUhVU1V6TytgPCVgblE/ZTFzeV9sJGYKeiZIR2lEMlRzdSUoOGdWPDNUSylpeDlQVjxQbFdNOWBX
Z3lQKVNlfE83fnV6JjJBJj17VTtmO2gzfmB0WHhFMl4/CnpXViV0JSVrej17R0BvKzNrRkpEVVR7
VFEwUExKd0c5JkMoVmwtXkFHazF2Q2JDTFlQNlBQWEF4ZWVTMU9oQDBrYgp6PjR9PkR3ZCY3N19+
Y0lLIWdLR2JsX0tKR1dRa3Jgekw+RnZySU99NjE1JjhFWGpDeWIlYnVlJk9AKVB8ZXY/RGUKeklw
MndyTjBAVn5lNGNKd3szQ09AZD1lNjVlQTx1UihRT3ZgbkwtX3h0WWNZfU1pa04wT0JrWihZS016
eUdgUD56CnpufG5LKlokM1ZaRlctTGxETWhoayZrWmxkNFJSJHZ3QlNHMmY3SSNOe3JjKnN5QXx7
bD5mQyRBUWlEdyYoIXYjRwp6TiRSODBhZ3Bme3chZmRSPWpVLXBBKTNVeiRlTl9Gd2hUNX1fJjsj
WV5meGUqcWNFJCFnNVJqLTNzSlFHbkNzOEYKenFuI005Pz18NUh3NSVyaCVEVzUjTnJkOW1NXnJn
Jj5ULX1QZ21NNGpebVY+VHM+QD1iIUIxRnxJVSQje3BjdjBACnoxa2JpIWBjPi1EKERAbWF1NXM7
ZXNmTzghdzZWSVYyZWMyVmRiSHJ5I0pIfXtBUztmenJWTXc7OTl3OWR3cURYegp6eHwpcUNzSitl
a1JnfWJ9UkJiOElAS2YqPklocGFUZjchbn5mLTlNRTxjPEhXNDI/NitSXm1hcndfYl9TVVgmd1EK
emozcHlRNjdRUj5ASXc0ZGc+ZyZ+Kip8NHFoWkZjSnBOO15IR2tCdDVOaVpBcGN6a3BBTzdrWmhp
Sk57S2pLPylHCno+P3Y9NEA4YWdVejdiNEJzcE5qb0MyOXAwUy0zfHstbDxpWTVNbnBXTm0weklH
VW83XkhQTyVvX2UqZzgoUHJVXgp6IWVBWXhwLUAyNyQ1WSlOalYqcUwmXzJ0Ui0tXkEmbSZ2K0hj
az8yamtVaGYwa1l8eHpQNSFqPG8zeEoxWWxzWSkKej8pYFV0QDY3SjlkRm1NRWRAQGghb1IqaFZz
Rz1yRzg0NDFCbjdjZDJHOTM7PzgqM3U2bjdWKHpyVGtTdnRFNWs3CnorMXBGJERfN1dab2J5LT55
dDJYVz1DYVVJPkQxX1FtMjtrUCV5cSlHZnYzMEFoKXN4NlpVS0NYbCNVQHFLbFd1Ugp6aC1XM1g+
bkJsVThzR1gqcjFRRW9jeWckRXdJNzZiYmpkOyoyIT9ES2BDZiteKUNyWkxDOCFTU2RtZ01rREFL
JEkKej5DQjJ2dXBJQlY0R0JCe2x+a2BKKlNOVnMzPXVOIVJnNFVyMmd+YClzX2twckB8UEl6djFI
OXVAc3hUfEZGI1MlCnomKjZKayNAdDZ5NkNgWktoeXlMXyQyMWE9MygyeHRiakM2Y28qKCRhZHc9
Tjx6O3BrYm9XTCpBXmJmZjQ8RjVYNQp6eThDKEA2fiFGeUhlQkMpa2AwSGZYdTtnUjd5TnV8QF9W
QTlVdF9+WDlac2BXKnlFS1NvcE9IWkV9Sjx6OTZTJG8Kemh0b0huYUtBcU01P1lqbU9wRGUqeiQx
RChESEk+ST4rPk9uM1M9Nk9IKntfQy0yUnpucFNTQkd3fVc7Kl5lR2Z+CnpBR2JaeEU8YnRMQGoj
UmA3bG1zKWt5YTR+IT88czg2eWw/JF9DJFN8bkt9RDFARklIPmcjQVVjOTRgbHR2dCtoeQp6KHlA
bEdXbip8fD5pM15XPmJ9JCFDNERNSWx6QU9mZmRNbl5HeEc3ODYmQ2dNI3p2TFhKYSkzUUZMUk59
KXJMWCMKemA+QTUyc2czJnJycHxMTz1ofnY4bFJwKGxjSkZGOGF9NUBuTHBkM1luPzxjPUB6U2hT
WSVjQiFYdUYmZndJIVhgCnpMNkcyS1BvTFJ7Kks+fnZWJjk7bnVVQzVjTztzRjFrPWpyfDB0fDly
XnpvKno/fUE7Q1BYSzQxMCp4XjVZV2ttRAp6KystaHheST5nfXorSHNVajB4TSpaJEwwPGduaTs/
QTxUJmRmSHZ5KSEkOWA9P3soVn1IPklAT0lCb01wPW5BO2kKemd1VSVUX215O2hiTTwzNG14PDcq
WSh6PFM8bjxgIVIzKUJoN15iMmFXWFM5VVM9T2NFOFIzMkBoTEhCTzF8fEpoCnpHM1dwQWtFWjw7
YG1ucEJhV3cmKHpaeW1+Xj9MSyU7ZT4zc0Z+MHpPSitoIXRvbVNZISloeks9a0BuPXJIVDJyVQp6
R2x8JXtedFRQWDItcz0+IVMqaEl6UXB0cExIPGBJSVliPm5ydXZaQjFUVGRGNTkmPXpDeDMocXRJ
RnF5RkFnMUYKelczNGthc2xIfmZfQV5VbnRNSjV5PGsrPzYkeG5gd0ojdDF9ZW1ydVhQaEBRMz4x
ejs+JnA7cWNud21aP15SUnFsCno8Zz01YCpRKDloWDl8NkRzZ2E5JDY0YGVZX3sxcFJzeyl1cztB
SmteY3clYTNnc3VNbShfTTF3OD1nPX10dWlzdQp6ITdKR05TWUxsUT9XV0xZSFlFMV5Wckk0Y3d5
WXlIalBrd2FrbDJmKlRhcklVbH5he0BmVkQrTGhEO0smZUBmR0YKenoyK01ldnZ0YmtRaSU5bGMh
REdDe0c8eEViWj1mQl5AITdmQTFLMmh8SEh0MG90TzhkcGZ3MnA0Rk5QU19RVmFfCnp1PUdAZldH
PzkpYDZjP0J7K1l1aWNCWUQhK3xsVWUjKUJ3KzRiOGhQOThCaC0zYDhiRyVYZyYlLStEa3UhOF5M
Jgp6RTxDZ3E4JDBDeFA3YkdHUzh+fHJlI2ZIb0c5dFRtPy1SWSMyRkZfTFBHKCM4WjtlZH18NGtj
Q0xtUiFeZVA1bGUKenFfY3dITWIra1BENUJ6YlRhPjwta3dEMjZtMSV0UU54UyVAXn1KT3A8ZDgl
Jm1SSjFSc3J6Ri0tUy1kMDslOzJ+Cno2JEc0MXFyamx2dD9OZ0F4WENPM2VZRSEmb290PHgpQk8k
WnltdkpTbEAqUVBGWFZRQXVlSTE9UWhFaUxjNEROdQp6K1V5ejUla01VeFJJOTFmOTV4IWRvOEYr
QHFgZG8wKk5Ldm9wc2pIM3QlbHk4el8obkdYTno7MW5gRDdySl5zITIKenYqJShhVUhiUlRsLWJF
R0c/RVJhSnp2eXooYHx3WEI8bWpaNTxFVnlTO3Q5ejtCcEQ9T3ZTTyEkQ1pwYGpOVjBeCno2JV9G
PTc4fGRMNmgjVXsxQkxHQ2cyeGtvXllRNzw/dnxkbzVGWU9paUVYZGNKVjJhc20lc1I3ZkA0UjMw
fGc+cgp6RXQkNnlscy0+e2QheyFSdGsteS1lMjtXUFEwWGVJNF5TPV9LdW98KnYpQV5RM1lMejsy
aTI9alJQZm5tPiolJSoKenxNcSkqME5lMzJTfU1qMTE8KjRuTV9iM0dlQ2MlRTxLXkFgP1pffjx2
cD59eUNqNkF8SVNST1ErPTZxV0xFJj9ECnprZ3IwWSpLNGE7ZX1kRUVXN3JUNThKPTxSXlZnQX5Q
NjhoN0dDO1Eze3F8V0hZR3lUPztzNDR3PmBiRnJwJTt+fAp6em9xXkhUIX1Vd2hMUHtJNklvaGVp
fnN7SGlldVRJY2p1ej5wMyRYUHZFOWZDeGRqYiRQMEwhcVdPKkdYYGA4Q3wKej1SMSFFbmFGO1pY
JmAhJjNtbnY0WD55KnVaPXctNGd4Xz5mOHh+KTwtQThAZns8MSF3YX5lQz8lVkthQkg5X0B8CnpO
O3J4dG1HR3ZRLTlNeyVYbi1QPVc0Xz9PY1g+aDhwQzUrXmBga3dHNjlSN2l6T19VSGVeUVpgQE1o
dkF8OXBffQp6QkBKOExiVz9WOz9wQ1Q1bUZ7YUV5PSVvS2JhZj1YeEE3bzJxe3JNPldCdW9vb1ot
OHteSVYraj1SM1NkTGNJSisKenheTUhuUStTdTlwYldUOVIhTiNQQHkkdmVLaEN9dHRiTiEwdDIl
czFCTU0xUnFaUmgpISZQcCptbi1eaUN7K3JzCnokZ3U2WXhhYztOTUV9ZTI1Xl4xQHZ5JUZoNnpN
TTVTcXNxdSZ2MEY4LThaTXtoKXcmaVdfZSVBKXM7ZX1kLUZwWQp6cDZhcU9NeHp6ZFMrSzZMY1Fi
QlppJW59TDNwKFpGcilSbFYjNmtrbVpjUG9YRDBiJW55UCY8RFRBOSMzV0ZOV24KenA2aHpXLU5R
OGB6ezMhVVBuamZlSWpDe0kwcyhQVVZ3VXhoRHlqKGJ0KG9zX2ZwbDYrKCM3JUxpZW58RHBQWn5g
Cno3eVQleiEmNG4xR1FuR0J6KT1pKVkkUVhwLSQ7NV5WYGJLZHdSbmdkVVVIR0d3UWJXVmpeSjsy
KFd7R2I/fUJ1NAp6T1dzTyplNnRHTkNSMTRhSX4jRkwpM3BCakshbC07X2V6bTZmfWlgNWV2VWck
JlprP0RVWElrM3t9MTt1YStDWG8KelNBSUJzRUtlVlg7SjEpe1ZENHVENilDMV9XISY8VnBJTW9z
UEZPNC0pdzxGUWsoTDRObig8YDRCYmZjQkpmMTBJCnpLJHVES3cydkpFUEs8WGVOU2NHK0xFNXdi
OHF4eWpWQzVHZno3b3Z+cHFrPjE8Qmh8RVRFWFBWWHl1Ul9JSWpoUAp6MXxDPzVTbT1JI2Njci1i
cyh5bm5zdiVPSlF6RH43M21rTXIhIWhwM2R4TWFsWXxGMk11PHt7dU4qPkUhPWRnTDkKenNuTH1a
YitGfGBzMlhtJHhaMUohK1RVek48fW9LcDIhXjt6UT5tYkBTJSQ3TmhJUHVyZlJCPXZVRypWO0Rt
LTdMCno0YnRJXnxHKnF+PVZSYmNUMDJxbm4pR0dVNT9BLU0jRzloTEhPTGIxRGckXzNZJTcwdFdV
TzhaNDVyfXlKVU8yegp6c18yY0k3R3wjPCh0LVc/QTxra2xtZUcpP3Z+TTt3N3V1KFUtWGh9MyVY
QEZuV1FacWw4JSYtTHglSDVQQFl4LXAKemhBaFhhcTt+JE9xVmIrLT1BMkxPOHQ5PVQ3KllfZClH
RzcmWV5IJD4+bjc8UWRPVmFWQEpJVVF1ZmZWVF5wRz5OCno9PzVpN3FgR0EpUXJEbnNWQShTcjh4
ZCRTUFdSYGh7IyVxRFQtMFJNOGduSlpPMjE+OEBSZDJwUyQoNzF1XyM8dQp6LUpHbFlvdzBlNXVi
NFpiP29XWEUreDNpNEIoanpmKH5FPG4kU0N0bWhEZU9wcXE3ZmZGJVpHSnBtQGMxUXRyQzYKekM+
diopZkgwST9LQk59K3YqdSlEVXtfPGNmMTM2I2licmlCUHRodEVtWlNOVzFhYVRpd3h7TDwjfms5
d3FvbTElCno8KjxNbUFNemQyYiorUnF5YDI4XkRkY3E8TyU3IyE2cDFScjF0RjF7NCUxLTZRRzY/
MTlgd1U+P0E8STdfSCY2egp6cXtwWmJDMjc4Z1BZWVEyPlYpRyRZOW56Pi1kZ15CPzl3fi01fTwz
aHd4czhiaHg4K1h0WmU8YEBWJV8zVEhnT2wKelM0ZD1tYVVkcXMrYkEoZnpAZndBT0lSZyR3OE85
Uj5hJTtAKzNBUj1xSVZ6Q0k7fEcmdT5kaE8qaU04aFNJRjBWCnpPUkdiaD1UVHFHXzxpc04/NT93
dU01XktOSkNFRjxDaUMjUz9GQGszKUl9fTZtXjtycyREV0NNUC1qaHFLPmVlVAp6Mlg0Kn1mbHAy
JHFCfiEkZSpyLUd7dX5fM3tETCtuJi1yby1OYEF7Rjh3WktGVDs5Xl5EODleTShaN3BZUnZodm8K
ekJTO20tIS0oNy1HUmJ6XkFBXjBgKmpDRUd6dT9IejFfd2UjR1hycHZgTjdsMCNNbjNVdURuOClw
YktpQShrdm1OCnpOflFafkF3PTxnM0BqJVdMfHJRZjBpeSZPSSExT2NwYkA4QEVIST1BUD1lKl9r
TWNKRis/SlBRYjN2JG8+dzAqWQp6cXoqe3VqJjs0Z24oMGdIe1ZefGRsXmh7SEYpQ2ZaMXp5YXJs
cyMkNDcleFppWmImNUt7cTN3OTBMMkReenA3S2YKemN3U2FNancpKWZ0c18mU0FUcWg1ZGFxRVp1
ISh8I09IcjM7eUN9VFJUK3tTRmJnRn17T3dqVjdqX0JAdWgrPGRACnoycTwyUiRnUihsblg8Mio/
JkQrbmpJcjV+NHt8bztqdl9WU3pfQFJXbXcjeDBgPFY7b0gjTkJQTUJhTkslPG4jZgp6a2trKjBX
dn0jOVM3S3Fxb3BAeSowWHI1NWNeNjNaT2U1dHNrTytGNTR7Vng7KF5VbSZQeT9nNkdXOFd6an5e
UHAKelIwMTBPOHkpV1BmUjhlVGp8QHVZMS1jVnstJj9oK2owYXsoVFJkZ00hOStnRCttUUEoJUp+
SzI1d0JDbUtGTE18CnohMVZ3VnA7ZmFZZjxJdUlJX0RwNyZSfGBHMEUwOUkmbTY5K3tpcUxUPDgj
I2Z7KHVBWDxTUDRsVns0JCpMRlI8egp6SlFSWjhnOUxnWDBtfnJ+ZVp0eShYQ0VKR3smNio3aTNS
aUQzekFeYW0xV2ptRWxtZ3xNKXRDZSFJNSQjNUtxNFYKeik0Y2VUaWVLa21tfjs/aVRBSS1OYTlH
Wl9zX3xrRCVNU29RJms1cnAzZihgRipaeU9zPTF6PkQwfSNOVWBiejkhCnpIIUFiPnJ4NFFaPH0w
aTVfZG43VWE9N3clREAraVNgZncwISErPzNvKUluTC1vQkpSaTVjZEQoJW9CQm17enJ4Pgp6fEpz
RTg8cEF1X0xsMGVFJGBxK1g+PWxvVCM9SCtsKC1mZEBTSy1kODNHdHxEOTU4JEMxbTVKbW5RISVO
U3JhQCQKek5gdjw4YH1oYlB7IWdCbG5eSkl7TWY9IS0tMkohV1hqYlZ9ITAyT0tDOFFAfEc2RH1u
V3E0YmRQPykoZCtYRTBZCnpuSTxpfVFsP34jWlRJNz02Q0olRSVgTF8qbnp9cCVAclB1cEZ5KjM1
UUU+akJOfU4kcGNOLXUyUmt6dFFnYSlldwp6RVNVe1p2IVRNOVo0KTNweTlXbXlNNUd0fGNwPipj
MHJRZDhGNnFyQj9MVnwyUjVJQmlIdDkrWiVAN3o2NTR2Sz0KemU7aip7OTdpJGdSayY2fCZ6Rjtw
Y0Bfd3ZMNT1sSCZQWDxkWXU+IXAtTlYrZ2Y9Uj41SHx3Jnk4QWh+eioqPkdCCno0NVR0S2NSe2By
eTxFU05rVlo+cFhRbGF3eXhTRHUlZT1eMkMyKzN6V2oqWFEzdCk/V1l+KyZ8U34yM2ApIz5ZRQp6
VHd1YHEyMzVmeFotSiM8SiNhQ1J6Z2xMWHxLNUxaamozWWY5T2V3PyRvdURkPkg0NDlkZ29nTURu
S0ImQEkwekMKejxeKUBoVD5udVYxe0NrWngkYF47O1p0YCVFWFd1dkY4O31DS2VDPVlfa3M/cnw4
c3tMIXZFfGorMDI1VW08ZDQyCnp3cGBsJUtTUSRwem4rXn1lbSh7ZkNIKlJ7M3hee3duRShmeXwx
MFRLMUVjUUglR3BhZipGdkJ1b35IMmN3fCFRPQp6ZlZYMkRaaVNmdVdlU2d5eGZ4T3dLISkyVE80
Z3dkdHJKdGx8NlFMLVNCaEUrUj5yKythPkZndTB9OGhzS1ptalEKelcjQjhLdUZ0UHZlfC1iJEpg
S21tMiNCSmczPDdvM14jJENQfDhBWn53TXN6fmNBKGQkU3V5ZkU9SytHPjViQDtoCnotTmt4P01k
YCh0cFR5RDdvNSN6Jk83QnM2QzgoUWxvZ0BaRyFgTUxwbXZ6RGMjR3F3KXskbWxWTWdzKURfVmwk
Zgp6UUdsNT5ITnwtbmw9bj0jbUd8KkkzOGFOUDdKbTRETShHOFNBZzB0bUVYbystZDNQdjNhPH5q
VmRiPWBqNEZUdncKekBJa0t5Sy0zUz1rI2VQamtTUCNgQzxiQmtPd2p3N1pEWW85VEg/M3tNRWdv
OSZZT01eclQ3PndhMzkzKDd1QVNzCnpTRilfTkRDcypKaz1sS3goTCZLR1F7Y3UhJC0rJEBSXzMt
ZG1qWU16KX0/VEJPXzhCcnJxWD5vVXhAd0gyQHBnKQp6ezUwMzV7RGVJMTtsdERlMEYlI21oUn05
UF5AZXpHNE1aKTY0cWR0ZV5yTkp0Jm1CbTdwOURCYytfdmY0YWYmXkAKenBafkBBaW5OMiZII084
KjJQTmlMciUkUC1CZipoWDY8Q0tBYjVuT3Q2PDMwbE5RJTVKalcxMEw2LVpzWTskLW08CnoxVkR6
cDtnRzs0UTJhWHAlfnNHZ20yVjJRZGlKbWVKI1R5bjVOcUR7c0tfeEAxNylSMU1IK1Q5U1J9Yktl
d0s/Jgp6UERTO1ohI25uO2ByJEppUi1hRkJkTUtlN0MxcCowY1VeSkg2Yj18WERGUU1WTGI4Mm1y
VSN4dFUwaDx9UlZNS2YKej11WkYtWFR7d0dMTklsNTVYcipMOFApeDhHMT1JZEYoTmVpJHsyfXI8
PEV1X2F7MTAlUy1jR3NWX0JpbVFBSVJfCnpBPkh5aW1jUlRJQjtoKURYMzBJdEdycFN3cFVnTVdk
UV80ZXNsaUFOR2lFISFgVDhYfVBOUjtPO0t4MlFlQm9BdQp6eElxSW9HSmY4PzJWNncoRzVxVikw
Qk8xM15eVkpha3g9d2IhX0w8WkhDanxXMG5XO2VWfW5nNDFAXjVKOE5sSkYKejJhKU18WEoraiR7
WEc7PExfMm1sYmxkWG5xZChpZHtAe2h7LXRAZSNgaWduY29lUzdLUH1eOX51NVZ5SSo+emoqCnp2
d0tEdEB9JDN+KHY0YXUjT0BgWClfPlU3YCUjI1B1byE4diMhemxRM2ghZ0RpeXZ8VGx9fUw7QmQk
cy13c1pGJQp6VklqP317Kj5KNlF8VXdGP2d0PnZYamFNR2RZS04zPGZuP2plZ3t5KT08Z3Y2U3By
OVJ0ZndGITE0e2MzXk9NLSsKenRIY21VXkdDJXtIcmYkQGdPUSNEOEMzJTh6TWROYylKdSp7TzY2
cDJuRj9mbTxOYHBzYlRGMkIrTCRyMUQyYWpMCnpeZ0dxdWh7KFolP1VMVmIxO253ZkdDP0l6bH1H
PEA9UG1Mdjk8TWpFZlhNaHplSWA5MSMwUz42MDB8KHFWTnZ0cwp6aUxBekZRQU1ePEF1WFQ9P0Ng
MTU/NVBWazM8UyRudEowR1Z8Ml5geVlYP2dlUGxQRkhkQTgyWG52Vk5sbSMrcHEKemUhMDEjO00q
UVhPOHM9QDlZPGFURkE8eSUzd214Q2s7OVReO3ZneHFEPHdtK05zT3oqQGpjSX5QPG9DZWNgJGcq
CnpIbzZ2TVlLd31KaDJffjl6PCNMTk9eM0FKRnJ+O3xoVSR3e2lLY3ExdCU9I3VWMj1yPk9HdFMz
YWFldzQrQG9TcAp6dlBaUj5LV2g7SkRidmROWjhQIWJhYFZ4Ml5qPTxrc3AkUUZnQVhWQGwtfVdH
TVhFZDBlTmF4fitxLW9hWFVCSWUKenpIIz4zLT5jQUU1Yzg3ay1rTGxjajRYUGcmI1p+enBnR15C
Klp6P0MwMGEtd2o/dEptdmhIPDVWI2tXWThndClKCnpnfjFJPFRHLWE5QT81SytMcmZObSNOfH1S
PEVycFNqVWopTyltSXRfUVBSZHduVEtiTHVITk1yeVE8cEZHTjtAQAp6KFk4U1c4SVE9eS0yKWNu
KVc1ZilvVH0ofFJyYiZCYFEqcV5QSSMha1BRJkl7N3teS2VTbT0yRylJcEZSWXZBYisKejE9P1hM
KlQ3MDdfbUF9RE5VZmtCPWw0R0omTyhXdUprc0hTTzgwVnZkMj5NVy0wYXBiMHdecU53ZmtYUkE9
PVlmCno2e1ZqVDE1akt0dVloZDd4UkUzOCpYQDRHRV5uUyNXbytpK147Wnc9Sz4jVjhycj43JW9z
ez5LTzdCQXQ5Q2Zrfgp6eX1URGVsfGxua3RlZ2xnMHQ7RTFVWFZTQV9FK1FrYmlDeUZ0Xm5fZSQj
SlpZPUk5QHV5eTxqMTQrez9qPXJ8eU0KekdDPSZBUGg/e2FwS3MhJVIhcDdhM2tCNkxuQGZeQkZ0
ezJnNWAoeXQmYSZnTlhWJm8pdGt1eEFhfk5ZV2tsSlBNCnorJTlwPE5VSExXTGkpczRqYWhoMm59
T35IMVpXTFJ5MFh1YkFGak1SQXZiT01APkhiTD08bWRodzgpQm5DKmo7ZAp6K1lWPFExSkhUQjhh
TnpVS2JsYUooRmM2PWo/JVhTTDQyREprSElPZGhhYzAqeEwwbT9HVXs7di1QX3ljRm5APjcKekt4
QWJuK3V3c2d5b1hVfD1EWCYzPStQRFA8VD1XOEtmcmxxK2ozdU9aezRTJDAlVkBucGhrejhVPHF1
YSFVYkFtCnpwWihsQDxCYllmTkxZV2dNRClVQWtjLTJgeWJYKy1IJEFXR2Z6UDY3fEFyPSNafnlh
JllZPlM2U2ZrX2NXblF8Mwp6TFMwWXF6TUUrN3kqUTY0YlFvQmx4Kms9M1cqJUx1MWUhNWZWfnVH
NFhrWW5Jbjl8RGZRJWAqUkN1Y3pJSS1xNl8KenM1elRfT0JnJWZsbWE8TmpyaEVFdD0qaUNibUIl
djxPNXpwTTFRZTtYRDVteF5aY0l+PSRIXlIrblIqRmN4Pzw5CnpvZFR2YWlvdXopVSpyc3BCM2Vo
TztiaD1aJnFsZ1ZEUylyTEZyJlQ8KnRPWkxOKVUjLU5wKnloYnBgVkdecj8wRQp6ZERBYCQmI2lP
PisrdSVqZTJ8Y00yTzk5PnwyYEREJCkwTiV6WTVsOEp6NmpZSGFZNzFKLUNRb19IXlhKP1VCQW4K
elRtSVJvMUdAOFZRdGV1KV90OUpzRT0ySD1oOzYhJnQ9OWZCXmlNM154I2hwNzZVZXViV0VnMXY/
O21TUDZxamo/CnpIKXBOYCpjRlkmI2Vxb3VLSDJiJXMtRWB7T1c5dEEmVXErblFUSEZrX2JHUnZ7
QEpaZSVEJUJMeGw+NWhwNX1gTgp6YHc1NlAmfTkpX0pNSml7UVZFbyQyayFvWkdAcTt1YngpdEpt
XmJnalBXWjhGUWErX0xoOH5lPU1AcyRoTF8tZHUKekAjbihWbVhaQEJ8Rl9zUG83cnN6UDs/eFp1
JGY3TVUwPkV3U29naldGMyF5Jk0mZipxI1MwXkxAMURVQll+YUg2Cnp1MGszJlQjV3E2cyp9VEBW
QXRXK297SEhXUUBPcHVFaylvYiVlU20kd2l4N3lsP31pPG1FZjQ0IT1takAha3E3fQp6YCpPOVpx
U3V4ZnBmd0JTO0BKQUJRTD1qOEdyKGlya15fXmc+ZGJHPWQlU3MxPEcrcXM2eFpUT2RwMXlQcCk/
Sk4Kek97aSEmQHUxMVYpaWR2PGt4UjFRNih7NkR3Wigya0B4PitJP0BYWCpUfCM8LUVtKnQ7YXhH
JDUrQiM4WDEzYkRmCnpMMzhiKkY1aW5icSZROztfJjZNUVRGUmR7UDMhUX11JEpEM1gqX0VBNEhn
YGpxVm17fGFaeDIwUGlYPGh8OVFRMQp6eWorc3RLNiFvK2oyKF5TbEArfm9sX1dMaDJHekdnRDwm
cG0kKCU5P0ohKGVpMHxkRU41Ki1jcDl8SDV4MlV7KTcKeiFOSjs7UW94antQYys1UC1UeFpEIU0h
eDFkZiYhRFB9M3JYbWxkb3BGMlNwT29PcElWUjUpKztfKjczfXh8WE9oCno+WkthbGNXK1FMSUtR
NVduXk9Edkl9Myl3U0JHNWhkKUA5TmI1dGdfPDJOUG5xNHxwQkNuU09YZUs8eyliYXVMTQp6RWl6
bSFKfFVOV1VxQ3JtdzBicFIoTl8ofSs5KDVqQ0R+SEI7UWQwWnxGbHBXdjw+bHBYUFFlfjRweiNv
X0w7SFEKeloxJmRtODJ4Njsldl9BPjljRD8jU0RTUXphaWJHbnREVGh6UXI+amIpZWB7KiFPVG91
UWleeEx4a2BVMTBqez1RCno+KXYpdjFFSjIoJEZDNCFXR3ZaT09zS2YkUT1rXk42bGQlNkckdD04
c1o7dXNVNVMpQms1S09RPEp0WmNVKDNhcAp6V3pwZG87JUpXQWZPKTZCMjwxVnNoVmkrcTRudCtW
JCR+VG8qWlh9KTBgPCMmWmNrRWVUcHkrN216VnJUfDIxJXYKemxSbFNJSThVNmttYSlSIWh0QmJ2
KW81XzFYV2JkJUtQQFVOcCtLSmMtUXArS041TSVGJGEzYVYjNDBiUXlZe1EtCno4KShlO25pNmA+
NGB6TXRfNXV2fEJPX30qVEczZmclfW4/Y3FJZj1aKnRVb0QtJTctRlRSWENORyNvKXt5cVIjZAp6
ZVBETkQpdW0+e3ckPG1pa0RuQzRZSnxlc1Z3OXU1P05sUHIyKyNXXihyTVklKGVFWTxIdDEhakM+
dDBUeXdNdXUKeklNOTM1NXdHYyplSF9vOCY8Jmo1QmA0JndFNVp5cjh8Q3xERXhQSU40VkNubUle
Vkw/Ylc3MSR5Sl8hfTdaWVdYCnpaSDlNQkp4VlN9Iz0tUGNZdlVBfV4yOVRIbSFPYHpXP0tYdigr
OTVZbThJa0xadkBRQXsqJlY+bkw2OHJ6KilMMgp6I0BvellgZVVJKlJHUE84bWtfSU9ENmBMTHdZ
cnZhTyRhdExUQ3JxMWRhe0xqQW0mNldgMlRjJHR+WEYoVUs+QHgKenZLfGdlcDV4enMxekBWNEpG
PSRJaW13MG4lQERtNnZhZ2JFTDQ5a0tRfERmKyQxZCshSCNOVEdST3prKkthWHUzCnpwTnEkcmt5
dj5UOylvVkRFbytiMEA4d3BgIUxSTSUkUjwjMTdwejJhY3BrTFk7eEtzZ1F3K1pSYGphUiEoRFN6
SAp6VT1SNFpuQkJ6Y1hMbVg5WUt9e31CfkEtfVZLVXJ+IXRXbyVQWXVVZFkjdkRGN3UocT9wZ0hf
akxUbEsrPVFYdl8KenMjJD4hWXNKYmM+JkVVS3EhZ0ZiU1JlWT5EfDxoLSEkfmxyUmUodFpPXkxl
M09eQmN5aVM0YDx8R1NSOUpzdFpSCnojVUs8ZUx1fG1EIVZiMTxuRG9jb0pmPFNYOEt4Pz0tQW1I
M15Dd0ZtSCtERDVKPzJIPGhAZCU5KlVWezJqYEtXTgp6JGk1Q2szPWApdiRxWlF9bn5TbU5VVmJw
U3hVOWZAd3x7d0BqKHFocUQySGNUPkY5JVFkJntTM2UqTjNQa1NGV0wKenRYVlRITjBeVHY8USpZ
XyZWSnB9dG54WHIpaGcoRUpwK1c/YyZAPGA8SUB4fDZKPExLNVJFankmLT5oTTh2ZXRfCnpfalY4
fj5Pe0U1SVA4WSh0TkdXbCY+ZUFYa2JiOF4kWStBeG91Kl9RdXAyXmM7IVlDZEJjUFQqZ2BiIVcz
PUAjagp6OGZnfXI2PDBjQDRmYnZNQUh5K1dVIXskSXYqNT1obzxFZHJJS2RhWWg5PSlhRFcod1hC
VH1SUTw4UV5LTFB8RyUKeiRzMDlUUFY2dCsrMUg9X2wkQFJycChlVyg3aXZuaW9jTV53RSFUdE9l
ekFTYXRPOWwqeFU2SXo4elFxWEhoekJICnoyZTRrfiZEKFp0dSVVcX5YMD12bEVQLTcoR01ne3pQ
KzZpZzU5eFMwTENvMXBSY2hIdVRYR2xWNGFRU0QqNGd2Pwp6eEBhdSUqVzN1VHFrSTxOQVFAOD4j
UGlIRHVrKkZGZXBkbSNqVWl2ckhaJEk0Ji1PfUshR3JNXnNSLVVRVWVDZlUKendWYnV0Q3dDeWFX
T0d6YXJKQ0JkcHMqcWF5USY/WE12JlFENlVtSWJZJC10WSRDYjclYFVlbCk0OElIMUBPWjJVCnpN
SXhfPj4kYV9DU2h6V0JlUSF5LVdPdW4jKHo0bndZeWdQZUZwKDhHfDR9Q09YKHxnfFYpS2ZeYEsx
U3w+QUJsRQp6b0p9YHombDtlN1gjbnJqOyN3eD9hTl8oLXBBaypgUzIyTX1OYnt4TU9DV1hXPFRB
M1VYLVVwOEVgYkRnMGBqQzsKelcqJWo9MWJjWUwhOSgtS0tmJWRkcHdSaUN1WFA7YUFZMSZjKSNN
eDtkPGh0bFdGeV5EJTxnbW9wT15ye2BOKE8mCnokRytVYERybHZ9KiZqZDAmJU90X1c7dXZuTl94
WXJDdVpKKVRDZyRwKjV0MCg1alR0VEszU2o0Z3lIX1MmYS0yTwp6R091c2trTWY+Qmc+cGpIXnI/
PGQ8QnhYazdzK2cySWxDNmBqVj00UGFvZ2YtRllINWFVQ15VJlRNIUpjX1dJTn0Kenl8Z2hsPEhv
TjcjanV+PDhQTFJBczI2P05MQCFfJUJIclNVSEV2QE96U0RDQ2lOSmVJRzRaZUxuUlgtR2grUkdQ
CnpPLV9YKGA2cEBhaU9+aHtTcCstJT0xKUdlemh2KmNJUUEoY0NDdlBPX0YleV5qRHtibkhSaCho
c3k2O01hejVTYgp6NiRjM21CeFZNZkB1KCU/byZNIVhGaVlzWUJyKEgwY3ZKMG1QQHZ4QmJQezJx
YmVnYzBaUEZaRGZDU25FZT5WUGIKemUkIVN2RDI5NnlBTUVsSVZnRjE7SXJEXzRHbjBrcigoS1Fr
TjZhPGxedjJZWk5uezt2d2BCKVpiOXsxVl4qKXQrCnojcWxoK2t4WHIoUVB7bG57cXg9M2x+UC0j
RVlmTz1LbTxZRmUrTiZONCRTSDZtTC1GUk1SQlQ8WUJfKiskWiN1dAp6dm9SS3dZXnNBTDk2R2xA
eWNELVItQkhXYztESUVFfEZyZSFZcT5eLUhffXh6JHRxTnc7THxXX3p3cFU3U3R6MlMKek8jcnxl
fDU5Tk1IU3RBIUd+djZxSz5PITd7SElfME9ufTE5Pi1ZeUZPR29aXjV7P31CNzZzZmtQKDhQNjY1
Kz5SCnooanY9dkpvNXN0aGUlTiZYUWxhSntDdi1WXjkha28xYjFYK1FecVUtTD03JExHJCp3aklJ
KypXWn5IIyltJFV4bgp6Ym1EaiFBaXVObSM8cnlNWFBWN1p0dU8yZXxEMnl2NmJURjdrLTEtRi0t
NyRmO14pdTdMUXlucE9TQ1AhRFdRK2oKejYxeF9eQC0oaVo+ZklyKV5PNkFLKEt9fnU3RTdNdnN2
cGRPMzZAd2JLZXVNflJxaDBSaUA8S3FNci1YVikoTzRUCnpQXj10YHhBPEgyI3tMNWdnWDRUalh3
ckBqKiZKYCN5d0xqdykrVztnaVlOUXRNYStocU0jMVMhPGVrMmlqWDhrVQp6MXpCYUM+KDh8YkJj
P3lDM2VSTzJhQzxlYyRaVUdPZEc+Kj1aYzh5OG9sNGQ5cz99c3x4dVBsQUBXVDw8cHdrKGcKeiR8
ODhXK2khSzhXVyY8JGxNcWdqZHF2NFVXU2BYKEt3SjZFJCVNbDUmcWg+UjN6bkBeSlJHJGBTaCN+
QT87RjskCnpPUjNXckUyU19hJUtlMlpSfCVTfUlxaj9jWTdKI2pMRnhSWWB4TjxhQXZ9RDJONCsz
SzlOWHhVWnZEQWFiVkpFRAp6KXh4KVBFfTk8Qjh0RV97U1ZwNUI1KmFGWnBUKGs3XnxLfGNFSVRg
Mit4QylFdEY8IU0rd3R5O0opSyorLWRDcmkKejl4PzdOZTNXXjtJQypMKCp8czFVeWB1Ml54TFQ8
S24xdVdKczJINlB1Sl9WPU1TU1ZuOTM1U0U8e3hoP0pTXmZ6CnphTyFRM2ZCIzMxY35NRTAtZCt1
NUdvU3dwUktoJWtXK31WdkdhcF8zd1d4MCUtQi1VKSFRdmZ8bn0qJDRFeHlJRAp6YClKSElXN1dQ
QHQoP1BAKm42P2NvUjVseTdLc2V5RmkpJCt5WiFtNT0ydHpIO2ZUKyZRREUhYWN4Kj9iaE1ON2AK
emQ5Nj9lNSs1OD93M000X1gxPj9uY3prRCpUZmxQfGoqSkpNQ2t9JWJKVEFVOUAqd1ZLZWRsNzg0
eGNIaHJAMEx4Cno8SW5mXkIlJXowWiE4WXhnK0NJMVpFY2E8JEBUO3I/a0l8JVZLTmtZd0pyKyg5
cnY+WGMmfWgqN1RVaGFDUXk9Mgp6UkI5PVoyMEVQe2BwbUpDXzB9fX4jZilMMkRCU0hBYj4tYUNh
YkhvfkA1ZU9wSkRyM3IhYUpoZ2lxcnEkYFFDa1cKenQ4YXlVKnNfNmN0TD18M24oUEsmRkZBLWA7
X2RLJmF7c09lI3cpQXw0fnhfQiRnVV5ya0BUVXJwUUxNdjhfJTxhCno1PkghezM5X3slMXElO3dj
OUhHUzRtQXlIU2hGfn5FJEdCaEE5Vmg8NH0/VVYhUWxAdkh3OUI3RkdSMT9nJnI/Wgp6ZmE0M1hZ
dDRUcUJNb3NmWWJ2fntJQDRLSUMoZSg4OHA/VFBJJV90TUdYZXlwbXlyZik3ZT1mSE9ZT0dvY15T
OE4KenFHQ2ZMIVEtbkhSRjdVNVokND5EX3QkS0BEK3UtRjkxYSFfO31YKnwxKGc0T2lhJUlOOD5O
KmpESkM7SmpGMCRrCnomT2Y9THUhSDZGeF52XmNATUV7PFVOfV5CKEZjUSZlQnxMJXJ7UlJKRDk+
O0VkSSo/ZT13TEtxMGwjTHMtcVZhOAp6NyZ6cnw/RE5CNUtWZ2wzbWR3WE9eOzUjVmxMd0ZmdWFv
b2VydXpSTWAxeyg1WW1iYjMlXzFAaSomYHlecFh8c2UKekJWPVN9VF9adzlCci0hcVgyXzA5SHJa
dEY4Nz8xV1UrKFg5YCtXYWAtI1BjKGJJLVoye2R+VGp1amd3I0E3R1UhCnp8RVNjXykyI2lTVll9
VjhrMT42WGc+dEVoXkk+JTUkPERkWSluPTQoa3IxMTtyeEdka0Q3e2w4WCZFUERZcjdBVwp6dyVB
OzU7bj45VSVLb1A1cGl7WTNgajw7fFQ1I2pMPGxHbWQ3MUxNLV5OI0tzcz92ITFIfWZJI2B0Nl8o
TVEhNGcKeks/aihvIWVBbCkyXm1EaGwkPiVrZ1puPTZMTmNgOW5Tb05XYkU4JHNAUnxuJVBXMWVe
IXF8N0lDenJgZz4xZWh6CnpSakJ5fmJOZVFVMndBaXdLbWZufSthaTNHSlFFejNlaGRWSnJ5aEoy
MDAtQmU1UiNYYE18fFhee0VhdWckKlRIcQp6TDUqREIxb1dgcTleWXRCLUt1R2xXNFhMbCQ/UFFY
WCNsRz5FMzYpZCtQekJKcDJvKVF5d0M2VT9KQyMhQ3pYTlIKeikmY0hvYDB3SVlQTnJrSlZtPDFH
SD0zQGpLVjdOKGk8MVJHckZ6ZHFENW84Uj5nT25AQ0FPbFIjQnRBX0duYTxSCnozfShDMVVOd018
S21+a0xiWEw9JldyKU5aXnskTi0jT187fUdgJkdKaX1ufE9iNXpLQnVicnZzZ2V5V19WYW9HdAp6
aDdhfSoxSTJeRThXTCFycytkR0dMPzVQNFleOX1Tb0pqS3pMI3FjdldVJEw/aGY1eW95NGw8JXll
Kis3Xml+N0oKeldGYUNWWSpmc3xGeHpHKkxNY1FtLWpYaEg0SEg2Q3VYSEQtblhMTVdZTFg/a1JY
MV94dU8rV15XJUJBeXBJMXdZCnpmVDZBcjBTfjB3eVFvZCtvZFlvOWpIRUc9KH5oRnp4TzNVZU1s
XnxaKFAwQyluI3JCQ1JIPHkxVCZ4VXV1NiVMcQp6UEtvdnxwc1kxYyNsZlkqI19wS2c4YE5tdEc1
e31kMyt4PnEhPX1zcTc9VV85Uih2S2BvODA3cEpGKVVydWowenEKek8yMnt3PnY0TGpNVHxZdzxa
KXljcHVDVmxScWV7aEFlYVQpVFNKKHFGVFZKM0x2PFlOOzNhVjIpZHtmYnNtMlBrCnpGXjQldUZg
PSYjeygoYyVzdXV+Z05yXiZJdjE8TlB5RVNPYUpwSjI/dHB5fUx5dG1TRGpmbTNER18qeGg4UH42
Zgp6NitOVzJTd21kNjhGO3deP2hNYlVodj4wV2I1Un1HWERMPzImRXk2TERVU1AxQjQwSUYodF9N
MWYqN1EkdTVzWl8KemIqPjhhPGlBMW1UcjhYYDVDPlZ2cktiMiQoXnBaa2FRNEVTekBuKHIxK2Yl
WU8jfTg9X21OenNhI1N6Y0NsIyN8Cnp2KCVEO003RXg8OGApNEJxejJFWEMrSEtSO09wZmFXRiMz
fnNuPWd5WHc5biF2MWFhN1Rjdih0UTUkeUA/Y1dZcAp6N0s2YDNeeF9tVjEhUV5eS0pwdGdVQUJC
Uzltb0ZzTiRYPTgxNm4wJjJ1OTlQWCVRKyRmYTE2dVZoT3lZYD0xRSQKemlPZEMyM2EzQHAzMD1X
MG1gN35STTt9Ylp3c1hJZm8hQXdnc0NoRTVGMmFncE5XVihhZ21qfm9SajckejFZeSZwCnprUDxj
QmtGVEdrQkNvJnl5ZzUheVd2d2p4TzZ8O1ItY29+ZGIkbld+YnRCQnQobmR4Q1hPKXlVaTEhaUc9
Izs9Rgp6PUJ0NzJAVV9WXzRsP1NuPz9nfjF4Y3g9dXQrTjMwdUBHdkhnZypTVFpgTz5haTxtRz11
YFVTX2F+MHV8ITA3fUUKekYtU2A8R3QxdjZgcFFZOFFxUUpeRFBfQG5zWklpUWM2dmg4b1VUTnVi
O3pTZl5nRDw1ezdYd3ghNE1kIU51Zy0zCnpTKlpIemJ1cmRyV3p5TyZlXnlJM3FAfnw3ZHYjaGxY
QCE7WChrJHY3enhwUz5SMH5Td2kjKlRhM3B8eUp3NztpbQp6UktfKEYhU0g1ejlpPmgkK0hUKiU8
MVQqbkokdVRObDh9U1BtI0h2JStQdzxkal5vOERXIXlDRmFILWRyTlYyMmgKell1elpvWWBJNkdm
Tz96WS1WSk5BNmdpQ0sweWw5dC13Y1IzTU1acSZNLWFyem1ScDFsaFM9cyhmfEpuS0h6eDwyCnp6
V3VvNk0zZUs2KH1nXjVGcX02USZLbWBuM1d4S0NCZ0VrYHB7RlYpKyQ8ezBEcVY0R3E+I2JRZHgz
aChIekFiPwp6VUBEIVpxR3Q5d0x4K3V0MzAxRVkrbCFia2heRVhae2RDb15eYFVJSGlzLS1MdmA+
fFAkPXtTc1VMMk57cHFUWWUKekZffSMqazlPJnJVeWR2X0YtXmpnRXlET0FWWTY7LUN9QmBVZ3JK
RT89ZEdpamN7NW8xKCYoRHdXXkN6SWQ/OylzCnpET0R2XiRpNExMQlNNVmNmezdsblNRJHpDSXRR
WHQwcTtlbD9JOXU8RWx+OylJSk9FYXhmMlo2OGwhbiYwM0xTTwp6JDl1OXtYe285X3AhdDs7Sz5g
MUFveSZDM0FBTFBuTT8tUC1ASV85QE89Z3ZRcz47YWM0ZGhNc1Z5QmNPO0lmVigKendhQnE2K1k+
U0xFPFl6U2hiKGIkU3ErQFdlZCR8JFB8V0JFY0tSVHkmYHBHeTA+RV98SV43XiQqfiR8MGd4MUdv
CnpBb2BEaVAoNDkrWjJsU1hobVUmIXtHX1BlckgqUUtTfV5EVTc3QCZJTUZlMXpCdFVGaHIoTEc2
WkpKVm9CdzspVgp6YjAlWnZRSX1hdWNsWUElZkdLOClJfnAxJUBiblBeR1NxYnVeI2wmfV83ZVVG
cEg8IzBCfCRKbihmalImeGxmNz0KejdgQikyKGNYTHNOK0lldXQ2PWREJlN5UC17WWtvRXlVRDBj
IX49Mik8Xz9sWXd8eXJFRlI/eDllMTdQeWo5WkdtCnp1Yn5IbHU2blI1VDM3V0EjKzt6fGRrMjJR
MDIlY2ZHNCp9KyQ7fCt1WTlRaig/ekprbllQRmIpVnh8TylNX1gjOwp6WkpnJVMkMUhQclh1Kldf
JWAwdzBVIz5rPCR5OXwjP25Xfm5GdnFrenxKUElzXiNuXz9SQjZUPXJYISpCTWxobkcKeiVNY1gq
SFJYbiopRmx2YXNuMn0xZzR7T1JoSkVQeDU3a0Vgdl5YaipGM0BZTWt2Z1hoJTYlYEFfUzAxPXFY
KlZICnpiYUxUQXNPVTV1Q014akwqOFA5fmZea2xmdzhDRDNjMEMjdUZmXnpoO2FhUzYjWUVBaWtv
WispZTI9Ni1XTWh8OAp6MHtWRVI9TkNzbU9mandBd1BlbShxSThXOUZSSC16QWVLX18tUlM7V3t9
JDxvUHk1V2owVXFwP09oTGl5Vj8ySlYKelRleEU0d1MoWDJySHs0ZSRXQjI+cjZVJTN7KDAxKWNi
KmVTam5CWmFrYiY7PT5tV2khdjYrcmVLRkd7LSlJajRXCnpxcWA+a0UjSlFaemA3dmIoXl8xdUBm
X25LdFFAUWdlVmVHVEpETXU0SXVjfWJDYyYzYThhK3lvKjFOa3NeNXBeSAp6SkArJChjb1BVaDx4
ZWc3Jk54KXM5RSpWZGR2RnZuM1ZjV0NzSjdxflM3OTlHfEs8fnlKfWZxKSNAQ05Aa2BSY00KelN4
cCZ4VitCIXIkU3NBUVJ7Zk5BSV8jMTB1RntVYDdAbE4hMTUmfEpaUHZ9fWdFdXlmek40fTlRMU4/
TkxrWmlSCnptb3RkfDNKS1FSZ2tYJFQ1JiY+JT9CTipfJUdOeyoyKkJvIz4wJCNXbyRkYVAwQmAr
Rkk5O3NGd2g2UVZ7JHgjcQp6cGJze09SXz4zY0NubHdOODghVWtoKE0oQ0J2b2A8aC1qYF9zbWFC
S1VtbmM5PWcpMz1DMUtGYCghb1VweEpyQlYKej5Vb1FFYjw0d3RYLVBVYmh7SSt7Mj9+PzFTbDxk
I0BXRitTe1cmPEhGa3Z3TyFAPFF2YitQbnlZVUViR3syQmlmCnplJn5ySzlSIUs+cnJwQnIkZTRO
fjd+blJhQnRSK3hPWWQ8fXViKE1LP31ZcjBxOUhINENERHI3YTJIbz50Nk5hJQp6YkE2aiNQTjF2
Iy1GaCN7PXtqJm9sd31wLVJ2TGBNe3xyLSZ3eVpHbWkmMV5kaDxwYzlKaWlqN0l7dklHR3dYY0kK
elBNQXt6NDZxaj1PMlg7fjVxYik5UXIpdTl4ITN9Tmp9MyQoVDQyPnZgPSMmUnkkZ0t1XiQ8NSg5
PjkjQW0mJWVsCno1Kns1anhELWM/a0VneihOM1VtWXt3ZHZXKTtFcVQ4ZWh+azd+RFk/YHxuRkMl
eXtHWllmRipCTl89NSZII1F0egp6VSU5cFZnP0ZkJVRwWXFvXy1+b3tZd2xSb3tNJEo8SXg/YjI5
bVhhcjNsI0gmanREazdJeDZZazlISWJRPz59OHkKenYoR3dUb3YydW9vQmRWaXR9ViZkKXdUcXBv
MEcpclRWZS0kYkNiVlVUbUw1UntMdmxjKkUxU14rQkVWZDVtOFc1CnoobHl3RVBnST97IUo/Xyl2
JDY5Z1IwcFRIdHFPJTEzcmR7NkIzNl4xYHQ/ZyVqPCN6KHo3NDF2THp7RFR3eSp3dgp6WUlYOD0m
K3M8dXJeTjlHd2kkJnEoMlJCMkFGVlhgbTFPTmEwV30+WkZsOTN4OU1WKFYpfC0hdjFzTjVkZ1U5
eU0KekYrZyNsNTU5KipRYWFVQG1GKFRNXz14RE5LMllNUFBjfCFpM19BZk5VQyhlKlBlKkV9TylO
O352KW5xSChNNGF9CnpSe3ducClUMjlNYDFnO1dDSns1Mm84czhTZ0UqP1dwezlBaHJZK3lOJUY0
PlYxKkgmPj1DRlVrXitScCMlRkskdQp6eUckeGVyc3ZHaV45SGpsXz1sYjJyOHIjSylYR3FlRz5H
WFFZeT8oMHgjdFZKYCZPOShAandJe0k4OHB7aEMqNEcKemdlM1BhKmsheWoqTilFaWNsfC1AYy12
TjxUbTQpWSNyWmdQdjVzLXw2a2NGNzhzIXM/MCstUyhhUE5sPT1vYTQpCnowOExXOCRyNitBVyo4
d3t6Yz1JdUpLb3ooS2UrQCZNaGlGa18kZXpkeG55WURXbzlNLWJyUCNGNk1GNjcoMTt0LQp6NVN9
NjYkT0olKUhDNWpeO3E4LT85Uk42KmEqfVhGV2EwSkJYOTZQdSppUkMyJERrZTw3IX1fKXttPSkq
aX1oXncKeiVTP2pEbkhAYG1Raz1sfVUoZXUrYTs9fTRlNTF6WkhYS0d5Q2tATlR2cHV2MypoPF9N
WHctMWxZa2U3Nk08O3ZiCno/P1hZVWU3PkBYKjlmXilWVjgjVU5wSUx6LTxtdHE7JHhxRml+QEYt
VGAwTXQjayExc3t4fDUpckdEJE9yciQtcwp6PnJVUlcyRWprYiU9S0htZjtmPFZkdTg/VE93c2NR
TD4lY2ZKK1JBM3M/PGIydklyMFpfY34xKnBrRmVlPD9teTwKekNAbzB3YE9CdXkrXzkxeXZzSiZV
X1drXylGNiQ4amx+d1gtY3FEZkZIViVYRm9+PVEyVyNqTnpsPnFFN208TzAmCnotbmFwYipSelZM
WFQ7WSpXQkpmcVVhViQ5WXE5bXR4WmZENFA4WVJHTUsxKDIkYlVwe2VAYXtXV1pDaWlxZiMjUQp6
ZV8kRyV6KUglNkhiYlJqZz18MmlWP3dnZFIhWlIpcXpuI3BPfEEjbTVKN3ZDUSZsZUxsOE9xdHlT
ZjAhcVc2bkQKejFhKjQpTFglbkhxSi0odWkpe3B5QHY8bjcqPj9UX3lJRj4tcFRsXmUrWU53Ul5V
YjZ7a28kQj1ITnlBTCFXXntECno/OytQRjB2TTYyYDFOLX5ZWXg1Zzw/d0pPd2BKajhfOW5nJkVX
aS05eDNeYjQ0MDckNlNqK0k5ZUYyci04UGxpVwp6aDlHSyV7aHpuMEd1JjM2U3slTEQlKDxIUVcj
OW5WUmh5VENfRi1jV1NydHkrQ057ZHdgbVF9d3E3ZSlGO0crdFcKemowJX40VGZnalJTWCFVZyg3
Pk1oblZ9OD1wYjZoMWI2Jk4jdDdAam5wTkMofF40fCo1TGxGbFo8ezUodzJlT0NiCnprOHh3OzFJ
SDB7YjwkKVp4Xz09YEx0SkQ4OHlnen48MEpwcDwxPmA8Zzx2alA3Iz4wY0ZifjwyS1Q4VWBGWGEw
RAp6OFVXJTZhQnRvKyMmdnw2bUw4I1g8V0V8NC1sWHFaPXFxb3hGK3p9e3Iqc0J9Tzc/aXVRNUpE
QGZCT29Ne2lwV2QKejl6VHxMaXxVUyZrSWRGUXFgZTdzRlBSVXxNdX4jZClfdih4I2tYZyQ9Sz5D
bjRLaSM3djQyYlZQLUhXSmAhcjwhCnorQSN+N0Y9Ny1ue3p8QnJHYSEhOUQ4c0wpZn5NYz5fdClm
dWM5UzxaSHxsSDVNMVZVYTZWVmJ8SCtoPFFTOzRSUQp6Nk8qfmVwZWkoWVhZODlvOHlmXzF4R3Ul
YW95PD8pVHtIV34kWXs+NExYP09hSTlCQm9QV2k+Zm5gY2BtWW1jeiEKejU3QjQ+I2prJntQRShZ
d0wxd3BTZVVAbllXZT5KOyopIVAxMmtpJCp1SHktc1YzOXRjSmppfmFCWF9jQmZuOCpCCnpBeV5t
aSg4fkkoNH18VCpEQk81akdpS3A7dW4tJW8mOGlIMTB0VWp1KFd2bjcoQHdYSkVaNDV7cXEhcCVS
RHh1Qwp6SyQhfnhiSURPS1kyZCtSUzY7ZUBwMGFYaVJ2SUNnY21uYDQydnxwPDljK0huJD1oZ0w8
Q3E+LUZPc2pBMkJveVUKelMmOXheMipSRUhYZlpkPkRBRENKITszQVMwQi08Qk42JnlEbU5qLTdq
PCM+Pi1UN2FSI3c7OW0lPmAoZUZWbkJGCnorYUNJRU9pRG9hRGhqVFgwKipwRygrJW1oZUwoQipS
dTktaT5JMShzKU0yfTNzbClgLUZuMk13d2pYbk47e1RXUAp6YlI5TVBKOFchbz1BPSNkKGV0aUBG
XmUtIUNAOTxVejhYSSUxbXk+QW0zM1U1Xl90UU5uaT9MeWx+LU5PI0N3NW4KeipGRXdPRDZXR3J1
NERmS1didGxtM2NSQDZQJmp2dXt7UyNrZTtzVSYtM35oR05qfWYxdVJrbD0tZ2VGfUZrTWR0Cnoq
PEomQDBaPlhIezU3UWl6aGglUi1gfm4oUTJhUkhYX0xiUyN5QUJWNyZMNVJtKk1CR3JnbW15WmYr
aUxRIyY5SQp6WDZoQmRwIzxXKmBgfCYjUE54NH1XRVEqI1dBVjE8Pn5vRzgkYVc5ZlY3ZylJKFJf
TjQ9RGhSIWNYQGFWRk1BKVQKenRxR1dwQDNXSn4lVXl9aTBlZjg/TmE2dzUyZl5fNzhnOWE8YjNK
R2EtI0xXVFRLY1UlN2JtQzUtKEt+Y1dPdVNSCnohUihedENMPUh0VnEjJVVeVTRaNTwhNiNUU3pa
YnZfe3dUQ2dibShmZmlhaHlNcWJOZyN3Qks5fDBLJj4+PHI0dQp6JCl6KWF4aj9GdHp5bk5NJX1u
TjQ7QmlZRCtIPnsyb2lpYWRwTklLYFZGP1dTNTE8RmMjKU9galo5TG5Vb2tjYE8KemxZb1dqKzc7
JEtCaD9zKE1uSCU9SjtPPDZedWg1S0JrM31MP208bVpsaSFUejgyaU91UHdES2AqY3goZXxLITZ7
CnopNHZWbjspPnp8NEspKzgrWXwqI2d+OThmMWpfbUNVXzVUTlRNbldxY3ZOUDZjVVhNUHxFeFlF
Z0JgSElGbjB3Rgp6LXYhNDRSPyg5KDxNfn5tYEdYZm9eayN8MEd+UyMoKWNiTEVndmBIQjRuZFln
eTU1NiNuS0VpJGpNZ0MhaippQ00KeiNaYlR2MHQ7cnxGbk15JXNNfFFfRW9hfjUobHsocm0oRHBh
SShqWlJ8MDU3UjBrbyNrLSNDSjhrI1Zqc3NXMDQyCnpuNE50ak8xclFmMHYzckA9anZ3NjtYMHlw
WkFTc1NwdENKYHZpeGBvYGFfdFheNGEoKSVyYyVGV3cqT24ka2NlZwp6YGNNSD5zcV5RPVV6aCZW
ZkczYlk5UWE+ZyVeVnJnY2dkMSpuYmt0JCZScn5zMk05a2I4cGFpbEtxQzFzJlFBe3gKempMYmJU
RTB9dWs4ezM9dlEtczBMP2FTME9OcUJlYiEyYG0paW1NfUg0a0x1PGxVX259bVdiNklyZiUxeE1u
WiQlCnpGekRWa3wyJHE1T3QpKi1qRXA/SkpwJXlJQClsOE9fSjQ+O1U0cz1jTVRWd0BqdUleX3s4
dXVQJjdPQXxMSUhlQgp6UzF3M0gwTXdFVz5hUndoVmBAdHFfYT1MckUkeTl5JmAye0dGamBfMDcl
eENhKEtqK2BAY1IrakYmOCp5P3A7aFkKemFHQiVMYGVZUTB1JkhBTFIpZ00rRFREYGtjT35vKTVk
YH1OcUxKeCpfZismKnchQ0I8OTJ8NUY0OStpX2h4Nm8pCnpKMXZtREBHYyFKUl4+Slk7Q0dUa1kq
NHp6TmpGMUJreStWWnhHdFkkRSpnenxiQl9wbm8xNSNwUHpYbThhSGlfJgp6TlczREphPSQjZGM3
RDFMZmVmNGt0e0lGaEpIKyt+JHd6fEh4ZUI/cVQ4a2JyU2t4fGxeeFBiP0t2Mjl+MV5vI04Kejtu
WmcyMGVlUDBgVVRmPDtIWldJSXRNU1FQU3lwbTh5RDVXQ2N1a0poKDdyYkJwUTUkalY4WiNBKUZR
TmNZYVhhCnpJNWFtR1dYTTRzZTx6I3pOJHVoeDAtIVNhenk+bStCXlVyY2lWRiVoRCFGNCphODBG
dzJaYzhHd3RNPEB1JXN3Sgp6UnlCbDFmdVkpMj9tK2wkU1pEUW5LTjRmdjRab3VsY0VgI1khTkp1
e3FlS21lcXlUKmFLNk53Qk1gKHEhMzNwX30Kej18KjhTTjM5STlkTiZVZzU/fjclMERDYkM0RXIh
bXA7NzZEelgtRmU2Zj8jQkh9fUZpU1VAU1goUU8zdkd3fU1FCnprX3BUcVp7cFAkK3wtUXMrX3s7
Q2hLNTJ5M3BSWjtpLVpMQWxOXjl8M2xSU1FIdCl2QzlVan0mKXhHRnspc3sxeQp6SklNRUFLX3E5
O0tIQ3V0NExAVHZGfkZYOSl3M0hHS0dTK3V5Zig0bHVkb3d8QDBMdXcpMlM3ZHt3ZkpaZzQoKnQK
elM8OU5lMWJXN1BoVFJ2PTlHUkgjZUlkI0FVUVk1bGImUlQlWn5RQkpWWCowUXNEejZMN0xKeThW
R2Q+ZXJya09lCnoweWN+MT0xQDtzc0ItVlhNLXIoaHB4VmMoSHp+JDx6VkMwN20hZEI9JTRUTH1J
Pks1OFBzKXIoU1lsTFo7eVM9Ygp6JF80Y3d1USNuMSYofTNBeyVaUDZGUmt+fmBDME1OIVEpdHxa
R2ZTfV9BemNmSiFNPCQyYVVzdWE3eV9PUX5eQmQKemhUcnpkM2JyP2BudkxQb09XVGc2dk1ha2pX
Pklhe2ZYVzJlUE9eTXBRQHs+Mzxxfk9ESHtTeiMybCZCSUY7UU11CnomfFQpZypjJDJiJFBZOHgx
RDlIa2hmc2pDZTV8Z3AjdGlOMDVMcWhTcSY3QXpGKjctQHBGM1pPKkdpTTxgQEtXOwp6R3ElbG8q
djZ6cGhsZHVGOWx0e0sjM1ZSfWtBZyUre3x+PzxeUWVva0BHezMtUDB7UjE5SkpzMVctUkVLKFlM
e24KemN2Wl9KdSNMZ09MPUdVN0FRVz1+cjI+aWJhSzhXdj5JZERNWCowXyEjfHwmUj9FTWFRZzRt
SSZzJGN3b1dZPCtACnp7M0ooRTs2X3g9MiE5azhNTDVnPTBIVXZwWEAhMFVMMyFmcWJAQ25yTztW
JlBaKlNfKyErMFYjTk9nYzkwQ1Jedgp6YXFhRlA2eHU4QEBgcVBfaCp5MD5qT0NMPWJYKFFMQDFq
YHwybVNyX2lobFhXPU0jMldHdHRYPXI7LVcxQF5BQGsKejJ6VWpsT35QfVZIM2VjT1pNQEdhO3E+
KWxLUHhWN14xSlQ/Y080eCZjT0tlPD8oIXs3OXtTe2g+KUxucSVuSiU/CnpBZXorQWhRRm0lbG09
b19LVGxtY2IkRkcoezM/ZmYme0soIyRVZXVPakRVckw8Y20lTU1GMl9ZXjZtRUA8I1B3dQp6dDAj
KSY5PVFaZXdNSGdSXzlAX3wlXiFUJGoza0pVJGU8PDZpO359YUJucH53ZzgrSXUtWC1FbmR2cUVW
eWclT0kKeiVhdWN6anEhWWhKVEJtel8oX1RgZlprZU5sU3JhJXs+I0AyS0pMUHc4fnkrSTt7UVIo
S2oyODIrb0xTaSV2cWlTClA7fTVDZCltQUNGVjtTOylIRSg9RQoKbGl0ZXJhbCAwCkhjbVY/ZDAw
MDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlLnBuZyBiL2FwcC9yZXMvc3Rl
YW0vZWNsaXBzZS5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uOWIzMjJlOWUwMTNjYTFjYTZlNDlkMDc1NjhjYWZk
ZTU5MTdjZDJhOApHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTE4NDAKemNtZUlZWEg9OHY3Qj43
S2oqSko5bmQyeTtseU58ai1rVVUhailTMl5zblN0STFmJkx0QXB+QEVhN0cwKmZUMUtICnozUENg
SyhuNHJLUUlNYHdBd1gwfUF+bGkjQSVyQ0Zvaks/SHtRaUZIVUdGK1N2YTw1emUpaXQ/RjR3Ozle
NEI+Ugp6ZCUxcmNgVWVDLWE8SD8leDxaaDJFKEEkY2Y0PlZuUyZ1SlEyVmM4bSZVenl0WG01dylC
aD9sQz5AcyskNz1Qd00KenlqJTJAYzt2O241RDFBeD5WLXVgQWM4TihneT09YmclKyQ+QUErRXRB
PXQwfmE9KHNXbyh7ZD9oczNaeXYjO1NpCnplUEVVMHpXdUg1bCFHaG9UVEsmandeeDRucDB9JVVP
OHZucCp4OUltPklNRCRgUEE4RyNrWEReSm9XTzMkemh+Iwp6Tz9xWWlRRSZnfHBfT3BLej80R0dm
eHs3QStKZHZTKmd7ciU4UXpqeHV6R0wzaWA2STImZDwtK21WJSVnOHFiSzYKeighaikrbT48QWdw
cjF8IT9TUDxqLXswSH5LX2Ajd0pPJj45QHhNUipBOVRxPWckKUdWSHtZaz47PyFGTDMlaCN0Cno+
fWQ/PG1gbT0xdCl7SiFrdWY1UGd1TEQ/NXtjck16cSt0OHNeZldVbXhGPkgtKnVCZHh4VSo4KzZ6
bGhQdFArKAp6Y3J5RiliMl9kSjQqWl4xOCtVeml0dUtFcEExM0Q8X04+WW9RK357fSlZVFArYjxs
IW88djhycFZ5eHhkOEx+M1QKelpSNEN2K19SVFJ3JDUhNmlMT09QM19mYjhuaXkmQEVvaXZiLSFv
Y1MpQjNjd3J8MUIqaz9IRUBoQTVwcDRZandLCnptND9KKzxXbWpjUi0han0pWTdWRCshKCZqJXEr
d3FAXm42MCMqTz9gZ0hick1ebVZEe3U1TGxpQzJyZEQ8Kjdtcwp6OG0pJGlASEltc09SR3JjTGVy
ZGgrdkpqKG0mSGYyM04lVjdzN3BRPyZNdTJ7a05VejBoNGFJeyMjUXlFYT9iblcKelhnMVYtOTkz
QVFtNmA7N3Y7K0FzUXxlbHR7VCtoRTxpayVgdjVKemVXYUo/KEZpbEwkaWt0TnJ4LV9HYUhlQyR1
CnpMPncjTWdBejh9Ryp5Pj9TKCQ3empjQnJSOVp+SnY/ZCtfbWcmVV5SaWAyXz9NQCMlUDYmZ35a
Z1Y3U1BJa1FhdAp6Y00lN1FhSSE5RipOajMjRTlZQmBKJnt2YjR6V3J6SSY1JXFxbCQ3eGMjRj5g
aiMzaTJsUz5EY29eUU5eViV+I1YKelJRaCh6Kz8tVnQ+WXQ2WG5aQEh7LW41TFklVSF1REJ4YTlD
X3Etb2xfTkcybl5SbFY0X053d1BxKW5QeHtRZjs4CnpfX0taSXJ5QmA5RSNMOUUzTjBvSSo3TUp1
RGtBI2NjbElrTCNiQTAwWHMjLVVkUHdHVyo8IXl+dWF2cnxrWF9vMAp6QEp2fXEjLXtTIWora34h
QCNZeTZ1VCswPDsrX2t2Sm9WPygrR0U3JV4oT1p1TDJZbyUmdmI4MHB6VjQpUik7PDEKenhxTSNn
KH1RME9xJTRCYHVKXihDcFJAekEmUz5CdCNLOG04Uj1naC1kbn4jczlfcmdANkQ0b21xO1hZeTl9
JEJlCnpRenhKOVhnPmxBK0ZgSWx6YFdUYHsrYmowUE8qJmVYbCo/LVh1ZWdecn0+RGMqTn4wTGdW
ZzMhbUBTR1BgVEN6dwp6ZyVjUFpSZDQzPCZPVHU0NHI9d3hwaTgtSF9qXnBHUURkQzVreDh+WUha
YW1CaSNONCNQWTBvOzFLcFMxdkZ9RH4KejhQVURSc3hhQVFNen1EMzw7KHJDSnlqREFVWkhWaVFf
YkEoOEN4c1crZD19aG8yPTQ4PmREI3hXdlV4VTlyVmZ3CnomJiRfdTZUI3lheWhEJUxVPSRsS2hW
fVNQeHxPPmRvenI4dkB1bXdpWEFwPWM4SlArakUkQUI+TTBOSSpYMThrNQp6TSl0T0ZRRzdoenhH
ZVBRK3NRcE1XRnk1eDR5Q1Qkcj42PDFVT0JzTlhXdWF8dl54fkU2UFEmfFV7aD12KnRrfVkKeitC
KEJKc3V9VyRYeXJDalg5e3lJY2pzZyFYbWlXVntqKHk0bXtIfVFwbzJOPkowRGpSbmwxakJ5azJB
MXptfUVaCnpoKGUldTtpakAyPW1UYDB6MWVyLV98eFAkSDYlU2R1R0V6UWxlJUheVj1tPDBQamc5
JXYpJGI0YnhxeFR6R3NIMgp6Yi1MRzZnQXM/bGQ+Wloqa2goMDdAVEh8YCFGTk9WZiVxVjVXbzNF
eW9nJmR2JVBORTk2dCp6OE1+N24weE1PeHEKelViV1AzbCVoLTg5T2MjMk00KXB0ekpvVD5Ccmsr
bGxMaSZebGZ2fHgpYHFlZEI4KzJaaHE3cjZAP0RJZmhJR15ACnpzay1NO1RjSDtHQUpDSFMmRTQl
TyMtK3VFXnlXRXZMfSN0T2kmb0JCQVVaOzh5MHMmZ3puQzd1KjsqODc2UXFTNgp6ZytEPnB0JHta
TVp+S1VVUTVKXkE4Nn5vVmp5PDsmOCZrcnhTfXxic3RAPldoKng/anhUWENeT3dzaXBUQnFuTygK
ekhnbyRNY0FTLWFaX3MmNVU+d3NpTTlfWH50QXdMWUh2WjxmcXkxa2VnTGJAdE9SXj9zNVI7SCRu
SHA8a0AhO2tuCnp1NEtzMEtuZHFLWH50WTE3b0w8MWRATn4rRzJpbjI9bnZRZCtaPXJTREAkMFVe
UkIzdCs0SGZLQ2tTOEJDb2VqRAp6eSMxdWEzd003dWtvdV54NUUwSXlneGNEYjV6c0NVYCFwX3RG
c2pyKTl0M0lDdlZgLXhmKFMoWkpAKDVfLXE2TmgKelZyfmZuRkB5aUV5ZV8pOHk9SnNMSzM9WFhn
IzlUZjBJQDd6YkgoMDFyKSgjNTdiTXtFRGM/Kng8N2pLPGg8ZVQqCnpKPk9kSHQyP3RidUh8I21q
O1JFek5wcHxybFRjN20ldn5NbWswajNoNHZ1S0pENmdjWlFkNHo1anZtO29RezxsKgp6ST85eFdI
azVEZks2JnY5e09TUGkwTSVnS3Z+Oz9ZRn1hZWwmR3I+RkNyUiZzMWxiXzFla2ZIfXdHekRVeU8j
ZmcKeil+SXdHJDdSeUQpb0VMVDNOeTgqaGVmPHlQLWQyN1JKNWgyJm82JVNePmsrbCktUSRFUHBP
WVFva0ktUGFWUU9rCnpMK3YrUmZfOGtudCEhNm4lQz1kYVNMPFotM0ByMTwxeVBrbEBsZC02cHUr
VzI7U1F6QVl1eVNaI2wlRkdHKnRtdAp6dUFiVUQ9UVhjPD09c3A/fEJqaTdVbjtqbWNZZH5GRkNF
aChgM08jP0deS2NXVG1kdUQyUHJnYl9COGdBaCU7QmwKelptQkozVHZHWnZoe3BOKG1kLTtyZ3c4
O0hxajA/KD8meF5CQldrdD0+dExKMCo3Yz9qZCVXRShid2Rhcz0zNjcpCnpJYFgjdyUqY307WEtP
JUxERHE5US0+PE9+K0F4PCQ9NklEXnRJNnZ4YSZzRzxqYEJhK2tWXyhoOSoxK0tBVkNxeAp6YlEw
bWkyYGRHYWhNJjd2emBJb1FLJVpESSQtNVEqMCU8aWFURjVSZCY3U1RHITZydmQ0NlFabD8xcSUk
S258bEIKemJ6IXd9RHxvKElDa1hNJHdpbnl2KFpmR0wma2d+RjBWdnc7KDJScSlhYCg4PSk0akQ2
UW5OKGFzMllIdFRENDs/CnoxRnxmWVJfO0w1bW0ySWB1ZU5nUSZLc3ZDQ0U2RSY3PWV7KmtLUjlz
bGFIQHM1cEA/VUVxe1R8b2RHM2FTZ3hESAp6c3JXPFZaPChCRlE9WXV0OSFNeihtPVBUSj5ZXjst
JkZ5WXIyNnA+WEY9TzxRSmFrWS1AKC10bS08NWQ/aG01QT4KejMjQDNCcllleFotdFYyRGpqTn5w
Rj8hYjVVaX0lSD1NZE1RbWdBQVg3ZG9nZm5Oc3tLSlVeX3VpakUzM2tNKUtmCnp3V0JwUWBPSGN8
diR1aERuVDY9aF5IJE9LZjU2Y01UTDQ7ITtwc0Jhe2U4Zj1eUHx9Z21kSzZtQTdfbm49OW1vJAp6
aXFFcXZFc3k8TSo+NEY4Qmk/eCota1YoVkpDLXZ3KSRtZjFuNm5hbWFsYVNadVdZTDQyOCMtI29v
a2hueClGT0MKelYxST1NeXZSNyo/QGB0aTElcj9UcDtIJDReR15yWktzZXopRjF4Jip1e15KSUBZ
JjEqc0otekJhT3NFaFM7VWgxCno7Oz1XM1BOaTclaTNVJlBTdHdgPF53YXhTS1YmT0QxJUE8Q1BY
PFViVyVYQn07Pm9AO0NzazhEP0hxQChNNUpmegp6REphTXFweX5hdXg0V3coVzFvV2A/SCN9eVlB
MCQ/NCFfOyZiO3F1XlQyKUJBSHZxaSVuK2Z2RS0xJTlmXjI/NWEKeihLJHFFc1BpeHxGdj5hbHNz
a2MmYGRPQFp4akljfHRIUl82V0gxQVVDcX1wb20pTFpNQFBibWVkUVdAZ3xMfHs7CnomXiRXJShJ
Z3pXV0ckIW5afSg+Y2gwVWZfWkhDP05LdmF4QWVMVl8mYHlUanFJKUMhTDFzRGh1S1dOX3hyUHph
dgp6Xmk0T2R8MnF5ajRvM2tHT0dwRFk5Rl5FJEl4Pj1SMnhtb0o0YyFUQ0R2THYpX05ZLUB4UkRQ
fkdnOGBjcTV9akgKejNtcElKKTMrZ3xTZDtObE9YbWE3IUQ5Z0FzdERzYEJ9PWBtNjBgMlAkdF43
PjVMYkpOP2dpQ0RoZk1YNShebiZ9CnpQT0B2az5pe1ooJFhoQ0hvczZxc3FWN2ZAVnZ6ajRUeGU7
bTtwUG1PQzA2TiFOdGpxM3l6ZU1eS1lXcG0qJk8/Twp6TGVhMTFndG10djE2eDJiNkR1KX5fMGV+
R09SKVRYTzBSWjhpVHsqSE5TaiMhNT15YW5nUnBTWlBCNW48a34hNnsKel5OMH5LS19pViQqa0JE
OFNYSVF1OWdya2ltO0IqZypvUHFEOTFjWSsjPzhIWDZuLUNRSDNuTEx0WGkwezRmcGRACno1d1lA
Z2pWcH4qQSVpd2ErflNlO3cxTEE8LS1LWkNtUz0kN1ZDZVpOK0d0eEJmQ05pTkBJV0g9T1gweEFs
QlMrXgp6YFB7U0p4fFVETURKTT88Q3RaSzdZX2g3VXJ5Xk58QUhUJG58MlRqa0RoQ2piezNtT2xJ
QURGcmt1JC01TTY3az8KemBpcUt3Jn4pVmAzWnxQUGhnQVN4JkVkb0Rndjl3e013dExzO0YzSUZv
RSYydD5iYUdkeWQ7e2pFUyl6VmRsdENYCnorZTFOaztMaUlDV2RGI0NBLVl3I0FNPG1uRXQwdnRB
bEdBU3A1MFN1elQ/dmE1VjM8RTZ4VkpOeHRiUjI9WlZGZQp6Rk1zT2AmcGxWfkVwPWwtOz5yKUJ6
R0YqM0hmK0o2d0JgRVAhX2gtb241Jm5aQloyciZrZmY8U0VzRGsqQyleU34Kej9QT0ZoaFAxX1BK
U15BYlNJeFg0bDNjNGR6SzRfYDJeTmZhc3FfcXpaUj4hNHdEUUkrRyE+a3pvfTlRPDEyQFNECnpI
K0VrWUk2QGx8dTZFMlQlQlF9b2FqSmUtVSZ0TlJ6KDAwUmNwViFaXkZaJX1fV2w0SVY5NThOSDlj
Ulh6M2dneQp6P3loQnQ7SD0+LVFBemNgbTdZdjUmQStEbm05JWpYUXUtT0Yzd0V0YGs5KFc4QUFQ
Xn5QVn01STAkJHlqYF90MDUKenQtczIlQGhZPElBMysyPW1saDh7M1ZxPT5RMjUwTlIoSy1CdnZB
MCRfRTUwdmdXYVcqKkElfjJOPF5LTWgteFMlCnpTPW1rMUJ4U31AQWBCbD5iNXB+XkZQKWk/OSkw
UFlIU0RlVT83IXBDNEM0cWtFTSFrP3A4Q0NHRjFefSozZnZuZQp6d2JoMSlXZElAdnY0T15vbz5y
PnsjXmk8Xj82PUhiZXx0OzFEUX5XQiV5ZmxraU1yJHhtN2t3M1o4TkdPZU05O18KekM8X3YxP1Vq
fEElNHZgU2J0N1lwTDdoIytOJChNcHFyQ00qUHhLeVc/QDhjfCoyTTlRaFYzVnFYX2VXeUBrPU41
CnpeSSFmUDNOSmlReEh6SGhZLSh5cmpFeChVT1l9bmpeellHS2pIaXxDelczaXU0ZWN7fSlpcGh8
UTAkaUJWUnR2Kgp6OUI7KkRtVyVCIylRT2pyJHpVa3YxXy0qZjl4b3chKEE9ISpXM2I7IVEqOFdq
JEBiYCFUWk1zVWE2OyRwdjk7X3cKekg0fFRLQSFgPzRNYnxRQzZkNThvQztwRVcxI0plbnhgRTJx
Qn0/NkZPPSk8VndIMCt+XjF8fFkkbD9ZbFJ1JUh7CnpYKDEpSy0oUyh1WnpXMDhpaCVjamFMKEVn
SmlxX0UrQzIrTClfSkYmYytDa09AQCNTemloKTQjU3w2YypZJjBVcgp6VStjZntyTiRMQFk7MSg3
Q1JAMH4lYms1RWRyYkE9T3dZTVRZanF4eU55WSRVRyluTGVHclVoI15VNnReQDVZYkUKelFXbnAk
NDR0I01IenxQQ3xBOWkpWH4zYGIhPD07fjZ+VTJPPW91eUdIeEZPMEBvelc3PCl6d2hSJCpTKVNA
cW9WCnpvLShyUHt0QUxVSXgoQj9WXnJFO0lHenwpKGJLMXtWZEM2ZnMqNkEqakJufCUqJWNjV2tr
VT8mQWImST4/OW01SQp6O2wwMGlHNzBrY3xBfWladl8td25tTj09VHglSDVtPmQqbCo2SVBCSkd4
VXImISo4MD5DWWpvVXp2PFhCYnJpZFQKelIqUU8hYmMqI3haNjM7SlRQKGU0eHRnQzchWWk5ZGE3
SG4qem5pYiMhe31MZE4mb0ojMShASUtZbD0oI1ItUk1ZCnpIKyRhYTBebT9mI2NYTz9oSHtuYF9G
KD1EdEJRT1ZLfiZDYmEmQGwkKmw9UHg9VCYmLSZofiUzKFg0QGYzaHlgeAp6WiVXJSQrWlp3aTBF
Rn1IezZNfnxDSlVaTkZjblVGJnkwSndld0w0YFVDOEg1ajtSQCE2SyhEMHtjen41NkJSYzkKemdr
JSV9RSZST2xIM31YUDhTR01NayZxZGljUER4cl55dWd3ZTd3OUliRCVKQ15wTm5lRFk/eSg2bHI3
Qlo8O2A8CnpZU3lLR3ljbH5GeH5tfX16MTU0OCs0fkI3WUZAKytmaDVfQ3BLdiR8Jm9mYTJqZldE
X0g1UShwXjRfdkklcHQldQp6QT8xKW16NHNVYGtLTHJjYHxxYEFQfC03V2VoOTE2OHBHLTlkbG9T
aj59UDlxNT8pfG9URHdyZERYOHYwXj51Z0IKeihDdkJEaGlvLWgtLV88MG49OHFZZj9KQWZSWGJp
fU5fTVY8SVp7RElkNDZzPHZCZyVIV217Tn0jQXlxKUlxR0MyCnpuSVJwKWUjZCtAcXZmM1hzWH17
bj9sbGEtJF5MOEQ0T1NFVCpnUDtpQExeJWt4cTVyKVBkYGd+OGpDbj8lQjsxdwp6KGQ4YWEze1hT
cGZiPU1jeWR9LVFsWW5HeVJyaD0zaWB0RF90Qj5keCklO3ckbkN9WCFOcURSdV9fNSZec34qcSQK
ei12IVlATmk4VzxDOFlDSFdke2NVYUM5bCp0a349cDtjfiskZX1wSjd6TSQhflleP09YT0VAMHU9
KSl8MU56OFZACnpfRGZePG9ROWx2OWVIPU8zQTklVmdrTn5ZQXJmUFlud3prSzxDS0hfaiMyTUB1
dTV1UjZwaGh5NWA7RlJUaT8lbQp6MjBKPyErUlQ1JFROV3A1VEtTcDNDK0wkJjR5NTVyUVhrPFVS
fFRWUUArWHNIUl8wTzZJZEFsU1Q9Uyhtc19WZjEKeldxSWJrMDxSTUtoZCVaMClwVDh5WHMlPH1t
MWVONXRqQXZMQXpQXzkxeF9HJHd1PURhe0t5OCh5ZGAxKWhWb3UpCnpYfSNOUFV3eGBNPmFqLUEp
Yjs0NzZTd3Q0amo5PzkyZzU5TkcpKEhPN3B6KTlCR0BoWTtjNztLe3owSk1nVWNEPwp6Xk1AeGlO
KmRmSkQ7dTNzNng9e0A0TnhRNz48VmA2Q0ZFUT05MSZqQWkxSUE3anJ9ZCQmM0pveWtFYSU7M0U+
fkwKejU+fm5LQyMzWDVBfHMqYU8qI001KVVhYERMbzhgRiZnO1FtX1p+YDlGczd7YCFKfWRDaDZu
NGBsRldLKEtIbGBECnpEYSZOZzE+d0I+RygoaF9FeUptYmpIcFFydmFqI2pgUk5BYClNcmckXj5Y
fik0KX1uWk0qcWpmTXh9dGAmczxeQQp6c047NmFBOUxBfWZ0WWk7SjU3cSszKEIxRTU2akYzJm14
P3N6d3VyIUhkOUM+SEx1OWo8SjA/Yk4yREclMGgxKWwKemN9RWA+T1Y+QzloSCtqRj13aGdtXn1W
enh2MGFiMHVMXyFVbVNAYjhGUnpfNkVeRV8tN2FGTEFJXzJpNHhoXzkjCnolT3VGRSRUOU0oKkQw
bVYlYUhJa3E7eVJwdD4/NGNLMkcoNzJJRD8rdFpQM20pNEIkeWV0MV9CciMzXjVwREBuNgp6cmdU
dGpaPnNTcTlLcEZBaDhsVmttZ2heeUoxfkFNbGU3RTZ3WHR9aU1yVTZyKDNNJSRkPDd8OG0ma0xg
P0I8cFkKel5vSk57YzktfjwtTSskfTw/IUhTfEMjWkppem1vKTgtKSRlbSlYXndfT3otO2BDQ2Yj
NW99ZmdrQCs8WlI8MFBaCnpfVnMxI2d1aTBYQ31GWC1yMGN2UilUcygrUkhHP3tYaUxoQXkmUGJY
NUViczRiU2pxcl49V1o4czNvMkdzS000Jgp6V2VTejdSdl5RcFl0YCtHU2czaFhZLXctaSlibGJ1
JWVYQSticUIpYyhoVTd4Wj9WSHNAX0hSMyljXjNYfEFzRysKenRSYXoxZSh9PGhSRnZYQVAtdWMr
Tnk4MkZRcEtoQD5ZIShNUHRmd31yS2kyOD0+JDF4bitjPGpJQSE/SCV0SD5RCnpjPiZ8T2lWNWo/
e15tI1NqS2ttSW59YDQ/ZGFBPXo1WCRlWlB3NGZRJmxTIXJeUyNIQHR8Z3coZm9BY040WClVMAp6
IUglTXN0PUlUYj4oPSo7ZWN6TUgpI3ZyKGlJRmV0ezI4eTdqYFBZOFJ9QzJJNylKM1Ard0Z6anJU
T1lHSClzRisKemh5fG1VP2dpWm0+dj9fXnNaSkpxUmN9dDhtTWtzQyR1e0M/aXM3UDZtcEl5OT5T
c1h3bHh9MlAhKUxSY0V2O0VECnpnO2BzIXtrSGRkS01Pcm80JlVxYE98TmdWKn5yYERmRVY3OyU5
JEQtZTtDT0FuMDtxZz1PRnU2c1VSSD9GUFowSwp6T2BVIXRhVG9OaTxgRVBWb2N7cDRzJTB1TGNF
YWB9JktFdDJoflNPSVhVbEFTQ2h2ai04SXRMRUljUyFfQHNIa1MKelUxN2xiaG1ESmclb2BTUTZL
O0J9bTl8TGxxMldSWGhPakU1Y3RlXjEyMHREO1NKNTR8Jmo7YSZoO1MqZSZ+KiE2Cno/REZ1Nyh3
Q29Xbl5+cm1rPEBzK2dleHl4WFl9Y14oMnw2Ny10eUchLWNFeF8kVlpwQ15NSWtWWmRpRjBvZkpG
YQp6dDxyWihOYnZxWlJfb241UUc0LTQqRnkocnVNYz9SYmtGbXEmYzVpWTE1O190elIyOE0jcnBL
VF5XKWpYZTFpNVgKeituTDVDSl4zcSg9VGFOP1k9ajY7QkZFJmBFKD9RQHBsLWNwZ0xqPHQwNmdq
SjVDSDczMWkyMkpWeEdIaShVei1iCnowP05XI2J0ZFgoIy00MkxjYGY8Tl85JW1DIzthP0dtKkJ7
ZFhHdEI+P0d8OSsyMF9QdmIqYDVJMk45bj4wYV4tdgp6Zl57WVlKcUUtUDlBQklRZis2VDF7fnFf
aEttTERrTnk0WktiWW5Hb1cocX1fYHZaNEJqTWlVWiZNMlVaI3NhQUoKemoqZ0NuaH1Cd2RVNzN4
SXk7OTFySzBlMW4oZjBPX15hQmVRcVpANiMwdWp6elRTO0FZcX5KXiZHbGp0R3ZEbXJjCnpCN1Ne
WVRHfmNacD8lViNEJUdeVXpNbFY5S2Vkb1BnVz1Ae2FNUStIWlR0SlBSSmhrdVE9P1o+Z1M/fCE8
fiFGbQp6R00yZzRMJTtLN0lhbWQlZEtuP2Y9U25+UnEzR3RUWVpGYUo8KldQKTRvNWNgaj8tZ0tQ
bT0zMSF2YytvZ1lVRWgKelM5PVUyWCVpRTlgV1VfPStEMEZgXlhSX14zPGhud0RhPGQpdnozOVch
d3J0PzM7Qz9KUHBJRy1XVnc1ZkA2N2gyCnptUlVJY3B7QVM5WiZURzZVJHBKVVlBPV52QndTTUFx
MmBhYG1+UEBORjstblIpNnomTjZiMldEQjBjcWRBOWtqNwp6WnU4TmlVanEzSFVZJT9DdzVUUmkx
aFk/Wm1BXzBRdnBRNlRGfTRFIVVeKiVUKihNflEjO3dGJjNrJCFBIzJ0KHsKek9BU0tQYWI7eT9e
YzRMYCkmV01vWU0+Mn43Zl9xJVQqejR+JVJxVFRken59RD5mWHpDbH5pOyNHPDV2VyFSVlFtCnp1
cyVVV2QzbT5ucDc/cUk9TD0zOW1WKUxAXlM4e345P0BfKntTQT9rY18tPmtIMzsjUzB5ZWk1RjBV
Rlp1JWhXPQp6V2JpLXdSXzlwTU87aWQoeERMWmtQRVBqT2VFR0JHNkpQKGBOVnl5TDY7JjclelBQ
fjJPQk1JMkBWRz90N1FAdWwKeig5fVk4ZSpnTTc+ejxoWl9XNmFFKjhjdWhNcXA8NipzYnt2ZG8j
ejxwQDJhP2E4Qm02TmZRcFdkMD0zbWJ3JmZhCnpxWEskQjBEb0o3YFhLJFZgR0ZifFN2Kkp2VGcz
S3k7PEl8PCVgUjZ4b2EpUUJKeVZILURuN0BuNFBSITwoQiF9QQp6dk9XSiF1bVUlcXgqbHhIRk5m
UE15aUREQ1pednE7aShFMm5IYT4xb2hfYEIhOEleJHA4T3FhWUReSDJVVzktZGcKenZJWjw9RWxa
V3JBSStiJiRIMypRUXcrI2NOc2MwNnRAej0tM19JSWE4KzdXenZVd1lTZUZgJlpnQkc1RXVCK2VN
CnpoUipFPWxqeWRoaSEjKV4kRW1DOSQjYX1jUUdsUUFxQDRMb0YzWHh0NWskMExEeW12XyNvTTNk
a0hVXlFoWXh0ZQp6bFFfPzRnOVRSbCMtUmZhU2N4VWQ+Knl3NG5feV8xP2x0dVNkWjdTNy0oeilh
eWlIRnxQRVBVUSFGUDVrVXlIaWQKekAqNmY5RnhJMFkxaU9gTDx6b0BMdjI+bXM4Nkt8R1dAQkxS
VihgazI4eVhIbEpJP0tBPT4qYF9EV2JHUi1VNn5mCno9M2NwKkAxMUJRWnwjMjVeNW1WZHo1NEVK
X1Imb2A+RkxnYmNyKW1GJWwwbT9hRSR4I2hlOE9nQXlVbVlse1pjOAp6em5pME5LV3pfXl8oXyhG
M3MlUndzcExJPj9AIygqcXk5NHVOaktncWcob2gzOW9TRSZ7NmIwQHR3ZXlBOEMhdlkKeklKUzVe
bTllISo+Um9va3tscUV3aCZXKVVaTGdmTF9VRUE4d3t7X2dFZk4lYzZNKncjJCZPQnJ5bTBud1Mj
NnMqCnpudlVDI3pBJkZLUktoZWRGO1J5I0xgfVBYeWYhO007QmxHN3RTNnpJWFYlaXBrNF5BdEx5
VFM9ZCRwYnxZIT9fKwp6Q0hNZmlLcDJHJTs5S31MeSZQdCpvK0RQcnc/VzVDeXRkJUNPMztvUVl+
fFRqUHQ1U2wqfjt0dVViX15PaDs0N1gKei1NQXN3VUpRMVhVVSpnVz1TfUFxNTJKcH0rcHExbDlJ
S2l4TjQwdWVPSmFXI0llIWpwNldIKjNrPD9KflV7JXQkCnpTMW0kOXdDWnE1USokJHlYeEYzenct
aFd7aSY2VVQmTHstcmUjY2MlaGg8blliQ25RJWhBMFVQNj5Xfmc9VDU3Tgp6c0F3Q09lKEhNZmRI
cGtBejswVkdYZnorU1EmKH45bC1GZ0s2WE8mMiY8am4laFcwN1gtfXBlSTY9WTtBUV5ZcXoKekQ5
cTZEeHluRjYmb2k5SDFPWkA/cnVqXn4rWUlqfUZORTNXalQleDZXeGtmeGQqPkwpIUozJHZGJG1H
QXAoO0xQCnpKcWNKKXskJnZaWldwfGcreSZTT3I+YnQ+ayNCT140WihCNDxeZ3EpJV5xYS03bDQ5
JHU3bnZtS2RLVTF3QUdhPQp6RCU8WVc1UWh7a3B9OTxGe18zZFJLcWc1UFlyQ0VZWDk/KTdUNWVA
N3tqYH5faFN0NEsoREMwckU9eFZUVE0qU3wKejNGQW1XOFhSdSszQGRGKTBEM1RXbD8laEZEZDsl
PzZ3bEd2QCMhMm1mX1FlOW94PCk+P3wlS0FZfV9scGY7JWV6CnpSITRxKSNHUHBLNXAoejBlP29n
YjA1UGM4Pj5qbUs0NnRCfHd9cDA+JERVODFsbHchV2xaVj8+QksqUnlVT2dDKQp6ZkhWb2tDbmpN
X1lIUEo0bW0+djlJPyhrIVZFTzU+TV4yNmI3al5qIzQtYVFpP0VDc1g9JmVReTBXcUpXOzVlSioK
eng/eWdQS0VfZ1luPG5waGFjSDV5Q0wqeX4kUktlK21oYFRUJjFhKDgrUytWTT0+QTJ7Zj4tTWE3
KVBrO21sSD42CnpwPzIrckt0O2JtTXA1fDxIY2BnTiZuPEBFNFljeTZhYjdLMzl7bFo0eTg9RiEk
I05fYlVvd2xGJT41ZjdtdVdAYAp6SnRJMGtAdmNsMkx2dldvI2c0U3JMZ1oqbyZRbmApZDgpd09j
MmhvO0l4ZCl8T2E0dzNoXlZ+KzVtUUozd2EjZ20Kej05TSkhVExCRXtEPSkrNlB0K24rcXlpZVFk
NWN6eSM5PF8hYyhgYWdLOWh6fD5JfEVSYGAofVkoflZaSmM3OWdqCno4e0tAQWgzN3FRUyp9WE87
OzN0a0pSNVhrQSFoWSQ9SCEqUEp2c2N6YWpJRiVwWiYjR2hNRH4rVVNPKlJzfGNOUAp6ej5iXmU5
WHx3PGRAPzdBcGMlRkNgPWdtMGMoTSo/OEVRK3JwXmQ4bF9PeTBBZHNSJlEtWGc+V3E3eHkxbmJy
XzgKemFoS3N1T35LVDY5V3F+N1R0dk0yZDxRXyFNNG47cm1CZ2l3NUFUZkdXYmZEWnluT1g0KnJT
bihgNGR6KHhERTM5Cno3ZHkkPHw1Y1lse3l2ZGN0VEh3I0UpVXkkJF41SDcmbiZAYmY3eTszd3x4
QnBQclBCRF4hOHJCcXdjSUAlTnJDTAp6YHZSNz5hPjBsdzkycHk5TzApUnwkK09NJDl1a1NGMmpn
dHREPU9IUlZSYTt4UzRgRXZIcSo1QGF6PXh0MzZBK3wKenVNOVk3YiQ5amAjQzdQSkdwb0BsZzUx
YWc0S3ZtQFZ4YSVMWS1VZSh4OS1HOz1eU1RZR3VBK0pZUWEmWVVlKVYwCno9bWk/b0xUdCF+LTVO
eFluN3YtciRDSyQxPDVrV1NLZlBvc2BsLTdYTHExVG5WNz5tbDdRdlMwdkM7fm45azRubAp6Ul5Q
TyZyJC1NWW4yVX1EaVUtS3grIXczdj0wbHZEV15kQlZEPVR9YCR1b0dYTmlzM1MpJHpiVVY2Rmxu
NGlZdEIKelpgeHF4Y3xofkFBfFhmTkE5UXdmUjgjUmMldHtxa3AkSiEybjI9YiN7aDd4ZDQmMSlC
eG1xTSNwbU9vRE1GYSlFCno/V3lPcTdxLS12bTJudWglekEjUSZNQihmRTxqWGxVNihUYmJpKnw0
d3B1SDZQOFowUjktOVpyajNgPXR1NEVTSwp6MHtCQD9seUdiTlRiYlIhVEBQKCF2eWRgKTBncG5r
NzxTYXZRVDZVVk1QcDhuMGAoV1dDWkBnUjt7RHBWZyhxMlYKelpmO3B0RFFHVz1BdyRFJVJAOypy
Z3Y4JGw+e3dHeU1QQGIoMmdedj5CJHBjfntEckw3aW4oNShybDZGXkB7Mml0CnpwcyUxdi1UUCh1
bktzXjIpeXVPKVhCZjdyc21VKXteY15hdXt9ejhqVW8wQD4zZzwkLVNvaHNyYGZDVE4kRWpfaQp6
cnREcnVBS3VWTFQzWHRoZHtHJE96K1BCTCs3NDhLbVpUNXhyOVJ6PXBaUzh8K0xKSkRQM1hrQTA8
VkNGKEU8R0IKej1sPGV6O1AjNX5tazdXZTJ8Jk1UR1dCSiNyaUsjUUZNdWJ4QkprIWZla1lRZTZP
a2dTI1YyJjtwfH16SGpeKndTCnpTUzRpTk9IX3d5aT1NV01VeWdYMj5CWHRuWnAqVnVNU0JzUUA9
bW1uX0dRQFV2OUIrUiZ6QWIzdGB9KyM4QnZiMQp6bFcwfig+enxob15idjMlVlpHelYyXzBxYXd5
eGsoeik8c3dRIWx1TlZ2YCgmbUNVIUNMPmxEa0JfLXdgSXhOZHkKemZyMHtLY1k8KVU4bFB0TiVn
a2BpR2Z+XzMwdElvTnd2QWYtYHc5QDxoezdVWSt6YkczIz1WWH5lRmBfRFlkeXU2CnoqMShodjZi
ezkjQl90Kj0qR1ZhbjhGbXx1USluXjlhXitjWU97QWN+RkxvNHBDbEpBIU0jfENrYXZWXjZQJXR1
Jgp6YmJHMG9SbDc3RW14ZkwpO0VDVlQ9Y1ltbnYkVnlGNjs5Q3YhfGZFY2lKQWwhIXF+XlJIZmVj
YmR0b2FBKEY0PDkKelE1MC03MjVyUyhwOEohe2RPZFhwbXl2cT9KdStUNClxfUUtOzRXeGVRKF5R
NVVHdTU5KjxjbT0lIWh+U21aSUVYCnp4NF4pbkt0RG42c1R1WW9Tfk88bCRHNEpNakpKR3x1TCla
RFUxSTcpVitleGlsOSFKUSshfnM/elMhXjBlVj1iMQp6WEB9VGE+bnBVPjk7ZTVqQ2MrQ3Umb0Nz
Xilrdm1GOzstMH0+U3tDQ2tsbE5gRkZGX0AySnFQP0xoMktOSylgKG8KejdkeUlHdWlWQmJlfGUl
KkE5SGNRSCNyTEFWYXhXYCkqPmdKb2xeT0w0Z0d6TGUtTFJGSiZsaTBjP2tgJEJmYFI5CnoqdCZZ
TTB3O3ltNVM9PEFqSEJRKTF+VGVnWHNHWi1UezFtPyFaPFchYi0zX2hzNy1LZVZtJGpEKShYZHp2
RSFkVgp6KFJ7K1ZHe2dacmNWPntQdUFkfTJuaEFKbmBlQ2QoTDApXyVabVZ3VyRJeXYmS2FqdVFn
MkJsZ2w4JUowdzZQMS0KenQtS3kjYG4zWkhae2dfUVJ2Tis4SnB7Y3FsbE41bVdVKnhEMDYjTkJ4
V3slWEd8e0E0SEx4ISgrN3VYRWQ+eVAoCnpVPWUkJURSRjdmWWxsKi0+aHwwbnslMkZXZnZGREc2
QFdwRW1iWmdGcEFtYXw/UVF3MVlhN2VmendqeGZXSjl2ZQp6cjRMMVBhQD18YXMyTHFSSFJnS0dN
Pj14a3dWSlZzTnckbV5OaFFffXM5LWhRWjNlZ2BrTUZqTzZQPVJtLSZ9bUMKejNobEszMzctZDR4
aFc3Xy0tJW8tSFg3fXg/YyFkJkhaZTF+R015JXVuYmhLXjdySCg8JUtyZFEjUkZXVCoyYWlsCnpr
QnA5bTItRFcqU0xWOWBxP2ohVDt1OGA9eThWJUplUXhsPDdCIXxWbG03P3p6fSgyMHZiamVgJCkj
bjB6YEpAaQp6MyZhWjZ2OUk1IyFeR3xGeHBvQFJRVXFBXzdfMnlqPHpiQ29ZPW5sSFdITEUpRyso
QVJqTFYjZzZJNDtZUFJTMHsKektoLUFkYGVUYlpLP25NTEFHbTgjY3NCKlMxKSstX1c5QG5Kd152
aDVhfTU5YClLYjM8ZDZpOygxPmE4RDRrbVNlCnowWE4mYFppZEtUTXUqeEgkcW1mOGVlZk8tRkN6
PCtUeV8yajs3Pjw9UlAxRDYzQGp5S3hfKUEyOyRnV1BhcWk4bQp6JWh+QVk9JV9afm4waHl2JHxM
Q0QmRiNlOHshfWJtXylWc3h0WDEjQz1NdWxJN0tNXlhVKjkmYVEyUzBPZFpKVysKejtMWXhSaCtl
RjNaT1V4ZzhjK1c2c30+YU0xNlF4Vno1VjIpRGF1P2RyVkR6WkZGQ15ecGEyO1BBKXp7Z1JqQis4
CnotYGElO2FoXkpWVkwkekJiWU5mcj1kfVczemtaVDh3dUQ1bzN2QihlaCEmPk0jajhCVD1ofWZt
KXQwM2s3YEVUSAp6MGojWFd5ZnElJWRjRDU1KmliKXRLdnBGb0A0O3c8bXRGWEd3NHkqa0ZLOV5D
eWVGKT0td158PERhakdFdjFHcygKejU0WGBqT2d4a3FGTHJUOzkwVHhQRXR7bnNfUXojcFdEbype
QmJVR3EldX1BV04rU24wI0dUUXpWNzBYSDZSNkdDCno5SSY4KVV+SmJaZ0xfQ1BXVER4QW02dzxF
VW4rZHJhWU9wbztOYTYmPklWQVd6WWw2P0FjcTkkeUNAUlNuXlA/Owp6TGgyKjxIY2YtdWVtNWt+
STNtJjIhUipAOVg2flo8KnZMcHAhZXBKKCklKnZgJUY2UiFtcCg0ck11ZGtPTVJmTG8KejdHN0Zn
aUZtVnxWbEVpKTJxbzc9SXRTOTxScmIxRTRldUd6YmFUX244RVQ4OWViY09pMzxAb04tYHlAJTFe
Z3BsCnptSEtyenlVZXdHNHs0KnhpVj1yJHZYfHs7I0Y8XjJ2PkBgUEVDcEwmUSglfUBQJm82REM0
RlBIe29qMSZIOEAqUQp6c3lTeGp7QkMhYmEqPlJ1al5sWDhfX0xqbWlydjVPI29+WEZ7b25RMnw2
TDZKfEQ/clYjTH4qP0dFJEVPcDElVjYKUDQ4aEwwezkxaH49PWM4dlBsZSgtCgpsaXRlcmFsIDAK
SGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmcg
Yi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5k
ZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uYTVlZDgwZmMxODQ2
ODcxMzJhYmQ2NzM3MWNkNzgyMTA3NzBmMWNhNQpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTk0
MDUKemNtZUlhaGcqfHBgIygoVVErY2NrUGl2SlR0SUJkUHNfWVQ0UWJsQj40bnojQUdOUDtxMFYw
R0R0V19RZFA9ZjVHCnpNTDxBNldASEE3MCUxaz0zSXFpYkFkbW5kZ3BkJjQ+JVFzeGQleGZSOzYw
OUNhfnZNSSVlQnQmSVh+eGxVRHVzSAp6YG8rT3x8SlI0Vm1YZWElWiokQDIlVGlMKChOYT1oYHV9
QDNfPX09cVEhNG57YkxXQ0hSIVR+eTFeVnx6OHxJWjQKel9Aakt0eCQ3WlVGZ191O1V4VTQrYTUk
WEs/TGFAUT1kWDlYYnVodWA0MzdDPkRYQVolWTx+WGY+Zk94NmlTVyFCCnpmaCQ5WmI5OGQ9QUV3
OFlfT19Fa01AWDt4Unx6RW5afHJ+Y15ZQHFEXzNNR0ltRk5kdm0zeWY9dWxLeXNzITJUYQp6RSY3
TlRSZnFqTTtZfENOaEgoTT1ifU9JP048PFlzXjQkZGY4b19hRUp3N3tJSzMzZj9xT1EwfEcpIVl6
PHd+fXEKenclRjtrdmJ5Y1VzQlZFJVFnKExKUTZNYnpjXnhxckNjRTx9KXg3JGo9cjRBakZQQGN4
UjBXQDdkJXBPNz1qcGxICnp6ZFV4SHFEbFhCe0txXm43WEFVbktjVnBkdVRiel5RaWhQM3stVV99
cS0kMW5OTjhBSUw0bEYwWWdTPXNoPykmXgp6ZiMyMkJsV21GJTMpODhAUjtIejx3eSQ7Qil0PzdD
TTVgWnc9PG05dHNpfHFqP1VzbEIteWlPbllXOEB6VGU+cHAKeikta3JVdzRWTnRzUy0paytXSzBp
VjRCdzU/ZD4wVilOXmBUS0llUGQkb3JwTFRpYiMrPUVAYUshdHx9PGwmSz5kCno/QHptWjB8ZTFo
ZmUxQUVweDwrZj9sP0tISjEkX25sRiZLaSYjMlFqdE1SOUw7RT1tYj4tJmEjKTNXMkApPE9wUQp6
VCRlNnpzcXNvbDdrdmpXbDNyZSRIfDkmTXZIZzA1IT18SypyLXlITzY8d20pPHpfI3N0K2c5TT5y
TEc5MCRKbmQKej9PKUVMKFIhRDE+PVFuWkd0KUNPeUFuTHhnNkhPWDd0UVljS3hTWlozO2MrXkly
MmM1eVQzeEBrMEdrPjFePU9hCnp0Pys2XkQzOXE8Z0dHbkFSX0hsIz4kSj5fMCg8Z0h2Ozd4Mi1N
XnI1eU00M2ZpJG44bzZ1d0w/RT1iS1o2ezFaKQp6WStRWEBTZzJAbUR6ajB3allsODN1KWFeRkdy
Ull8c0Y1ajJIUEtUKEpGQkM3ZXRzWCMwYlAzUTwmQmQzYGckeykKeks0KjQmLURLMDZwdjBDQF9h
TDVxZGNnOUo1LVdDUEt0RlRle3s0QmN1QVc4PlQrd3gpV0o8T3lIKFNpdD01bSlKCno3SnpfTC08
XmEhYXgwQGQhKktTb1lrbHlid3tCO0VsU0B7b1ZMKHEhYzlaYEMkS0tyPE8qKHF9eVczQ1czWElL
Mwp6dCZoc1A7LTA9Vks5JWsxbkh6cCo8QnFidE53VCRkLTBZYD4tMDtZP3lCY2dQT0RyJXQ5QmIj
YHBrYnF0YDFFTlUKenBeZUFGU1Q+JFE4RGN0XnU/bSZwKUE9RG96VHB1OWo9REt5cjhra1VwPE1W
cFBsc052WVNqNG9wcGNedypuTHZCCnpQUiVTclI4ZH1VR315KGNzNysxMUlLOH4wQUUje1Zjfj9L
U3tMI3pGX1I0OV5Vez85QVRIP2tYaihQQTh2VD0kdwp6eHl6KE9WOUZrXnVZTHF5X0t2eyp5dzZX
fmFTRE1RWDZ+VldyU3p6dWJtbz85dC1VUWEzXm5ybU0raVN1VEVgYXoKeiZEPyN3UW1BJD1qXkBC
QmxqVHN8bUZaYSYpMztfWjEpQWdkQmFueit8R09Eez4zXjZ5TCExb25eam0jbClUQ3xYCno1QEtU
Knd3QHtPNV5IQyVXRTU/LXJoMCpWbVY1KFJUdm1HeWhqNFR8YmkxLXZ1PD8lN05ZZXFzbTsyIVNv
QGAlegp6cXVafUVAfD93SDRZenxgUiZTOUpHMU5gYF5USl9JJiliVjtuVlhabGotU2BPdFkma2Bp
IXBRRXFGenVhOS1ZKC0KejlgNDxoNURBPCRDRWYkY3FCWGt0P3cpdlNuXzE3MzNeJHRTRzgoaTg2
VWpJb2plXlVKTW9UX0liajhsaj1MTl5YCnpYaEE0JEQmVUVibWUweCpCT0tQZzAtQHI0UkJEJSQp
U2IhRnY3biEjSnxQJTZXSlV5UHZrcDE9eCVPQ31haWtXMQp6TFVmc2RHZH0pVT9jOE5HPFdte2Vj
R1R0ekB1JGpvPTFBOTc2an5aZ2FyIz8wbCZnIz07c3RUOHBoMzUraz5nbkMKelNacVZPPjhyc241
V0ZsJDZBJDw2bktaczh3PH1xJXZscysrbFVVZVAmYF9vZTg4U2c/cE9qUnlpS3ZNayp0Tll6CnpR
MFc+PmFTdUFaZUNUK3E9NElrZCt5WSkhZ1RNTExyLTNJJmlKTnJ0WUdFNnZkI2ZkOCUqK0BKZSpN
anRrYUtuQwp6eUhuZn0rekgjKHN+dnZzWCYzV0llX25XOyZed1NibWJpKFBNb3V0bUZaQTh8UFBq
TyEkeiNoLVdOViZ9OEFuNz0KejU4OWtxUXZNUjZpPVFGVE9gVTZHeysxPDc7JT9YMTNSQE1mJStG
bVE+QnElO2FtcUZPalUmYjM8WnZDNXhjZVNMCnpJSV8jVl5MfFVyeFdWZFNSUzZpczkwPzEtVjFB
YW81SSskUilpQV5ARm5xeXxeeGM4UEd7UWB3ezw9IUtgd0lUTgp6eEtUODZQZlROb2VWYys3Jnk0
IyhUbkB2YT1jNXo1aSQ+dUQycEA1YEo/ZSZKKW9tVzlqUk50clk3NFMkN3g9O2gKeiRYM1IjRTF0
cClFOEp7OWFOcWUkNGVoeUxYe2kjfWVTZkc0S2hCblFtMkVaNGRRVF4lPFY1QiRqPlotVXlmYFJZ
Cnplcmo1MDtRfnNuR1dOV0w/PHRydVFmYnNZZlVPTTNRVUlmaz9JRmRsUHdVSnBiV3NRYj5ENWhn
bFhfQjlzMTIjTAp6e1dfQ18qWj1VU3dAWV5zcCtyPnEtWGIlbmshPjVeRUUwb3RuOyl3fXV6N3VI
QFM/aDkxYkBHOVA8SCFQMWtOcDAKej9mMyRKSyFzP14yWGE2RDlLTTFKNGx+VFR5SE9nc3UhNEVY
MzhSNVUteURUTz4tVnY5X1lqTGdWZWhLX1JEIVliCnpjMTRuMjJLZ0lmMSZITEVrdzxOXjwlbkY8
M1FObk5Ibn5jP19+IzRfJFhHb09BZ3NKO2phO3RxVGN1STlXQlJ1ewp6SXVrRjNNaCRYWGtUMDk/
K2hfVFJnR0FRal5PN1lgTXB2MlRVQSZKJVkpI0w4RnRrQSokX3lUey0hQ3JxVjQ2UEYKel45YkIx
V1lNXnhgbmtVRXYpYnVLRGh7VmtNPVVmdipicHNfSlE4bSN4d2orUVdVMnl1eikrN00kVnQlI1F3
QXZBCnpGNS1ybk8zKFV1cGhJNTQkPlhIV08xeiQ2SW5reXUzTGc0X0slM0Z6WmslPUthdjwqdlU0
ZSZeTTR2aiN5NHg2ewp6N2klcyEkSUIlemZtNylCO3x0MlU5fTdfeW4hSnAya0h1X2pGMTVeSm5Y
bGlvcCRIYXpWK3p4WmBlNlUxJk5mVXEKekRyKHU0WXQhWn1yKjNuJiYwMD9vRH1CWXpmcnRfLVd2
NnVAPV98cz4rdU1+KGhvUCk8e1YxZzleV1B6IzdCRHMkCnolclQ9em94IUR5TF5ifGFqMkAxZyVP
Z2l4b1JuQ1k4RGAyN2BMeHhOZ3ozS3I/dUtBfGhEdmBFZ3FLWCFQdiRJQAp6SDV3JUd3YEBxOHtq
X2NoMTlLQDdDRWpXKy14OXRuaWAxfnIqQm0hRTRHQyVvdE4zbUJAVk9LZ1pnUW4qVSZESXEKeily
ZE0kZ2xlVjBHUCFsfksySjBBQWtuZzNASkt1WiU8NHJid0xidWBCaF9nR2YkIUwoYygtdD9zTSY2
PWdQXnohCnpTPzVkYl43cjlKe1RTPTEkd1Y1VGx0P0JJJGotPCQzMXtfdGpBZyo2Kk1ZRTxkJkZH
Xk15ITt7amZ3ZTRleTl5dgp6YEBAPUA0fkFtLVZReGdjMm1PSjhNMSZ6TiFXZk02bi1Jd2JlKi1i
cHdlcEszX29rSXRBJDdQeEomV3Y7RjxeU3gKeiZIPXM3WDRzdU5Xa0JxNlVKPHc+QjU7ej9FcTZh
IUdnI30pNiZSXy1TSmtROFZnMEM4JiQ5Mzx6RERqRDE0WUwqCnpAPXhQTWprPEA0IzkwWlk4LXN7
STsmKCNgTz9RQUo+T29QYE1hZl9Rdz4+NT5CRVhtMmFDLWgjSzdpU3hre359ZAp6SjxXM2ReQGl3
QzRFSH1vQWwzNjMqblc9cnEhfVZiczRibDBsVjY3TVBCTiN0P2JtQHV4KnhoMCNXcH1BTSEweFYK
eis8RzVaaDR1akpKb2hld09Sd2s7IWFSa15LVTVreUxqIUBlZmY1OCE2Ryt5ITF0aTtVTmZmWSV3
RjFuVHpCVS1+CnpAZ2lpbjxgYipQUWVyXlZYNUlNWmRWYnkySTx2KDIoWFBwRzteVFJfclhgLS1J
d0h3XnF0KDZPWmJCUjZxbUZhMQp6SV9lZT92LV5jSCE7T2EzczUxTSFHTlpKdCZhTnkkIVNALWRt
WS1nNDsyQTZUaDJgVXhJVDEmO0EjJThKMVNXP3MKenhvX197TUZ9NG88JWRsaDZ6PCF2N0pKQEA4
fiE4VTZ5YnJNI31zQGthO0FtSUwjTCU/MW9YY0xpPThvcEElQncyCnpTMEsrYThyTk90VXRQUTZZ
V2NAXj1YfCZYe2FEbyY3KWFKV2BNZWlwO0BkSnZXWXo3UGtTU2J1cz9jYVRvRElXNgp6R0cpKW1Y
dTgzUSt9SWozeF9zNWxFbzJzeGFDQ2RpbTYqX0c5WUB8N2twLUxsVT1jWXRkN0hoVE9ISXhXKXI8
I2EKek8/RyphO1BwbnZjZnkkIzlKM09pPDNGMVU3SEl6Wl5QIUw2YHthT1RVXnVGRDt0aFlzRWVN
RzhaYkxMSUV0cEFeCnpvZiFSViYhO05aUndQalZxYWtlT3VoKnVYQ1IwXkxMaXlDamxzRjFyXkVe
K3NObTR1RFhndjF2QEA+SnR6O3RTRwp6JEgmLUNyanFjM1F6S18pKHpjQ3B7P2JlVlNOdm9qJjVu
SE1CSXg5eTRreT1aZjVjOFMzTEEkaFgwQyZBbllMbmsKejUraDxRSkNncXFUY1VVWGJpNGp5TjI4
ZW88T1lMcnlhLSNtQkRnbWx2JH1eWGczNzgpSFB8OGx2NVhXfTMoZSUqCno2UkAkQURfRT4+Wllj
LVV4MDQ7RzAxbCVNK1FHajVMVDU+KHFzQClxbiZ+SURQbCNPb1JLTk91PyN8dTxOYVNtIwp6RnQ+
REBvPTZnfWAlekFBV21STTJENjshaXMwR1R+PVRFbDVlWkpWfkJZRD99WH04YSkkLSM8Qzxqekh7
YjlCOUgKemRUO0YqXnUhTzRKWE82UDI9fDIjezRpIyRqU014ND16VWA/Y2pMdmkqbmZrU1VMUz9T
VCFGQmZPIWpkdDtqUF9FCnpgN2d6fkt5ITVeaFR9Z1AzM0BheXpeU2lfRCQ7RXtmZjtTdT4wKj1N
aiRlKkArU09CYT5uIU54UTRMNF8qej5ZVgp6Sjw4b0pIZDRoblc8eFohb0ZIeTFRMVJ7azloJTEl
SGNyKCRuayZKIU16RyReJjlvQTBsZjw3MT8pRj5abV9zMXAKentHSCo/SmFPJGFkSXNwS01jaVoz
JUZ0Q0EkdHFLaEM9SW0mWmtILTFMODxCRU9fbG1qe1EzRDtTeSo1XmFqTy1zCnpDZ2VPTU09MCNa
OCp9O2dXfjxweGJsazZzeEJpbCNnSzZjdnsmcnY8PzclfnRMTyVAWkRwKCZmezApPCVWQzxYNgp6
RmJpbzF2emJjYXlxWUotQ0NYSSowTHNYQTJuUH1NIyM7fHdKX0JDPD09UkxtYVEydSozSXlWVFgr
Z35gUSF2QngKemVMSXVpWkstKihUMn5eY1ZJdFZUWj85TWgkMzhWYFhNUEtNVHdtSmh2NXs2Qj1u
JXxWRipeNUowKkYpVTVMX1ZLCnpzXyt9YWJZI0BIU0c/TSZDa0FXZmpFY1BjcUBuZ30yLXctd3NN
UVhJI0I9VyVZUWk8V2NyVzFSaTliTj1uZDVMawp6K2dDTWBiLTlmanYoOSE5NmVSdDZAbGBPbXBL
SE9aWUhaP0QrKjMqeXMzfnIme303KzM1a296Miole3ZsZTBtMVcKejtrK30pPD5JVG43cSheRDQz
b0J2ajZkN0FkMGowZjNYdGY+NCNGYlhPZzRFczByelIya2pRfTJVMDI0dXp0MDRNCnpfMEJuNGBp
IWI+ejBhaTtCTzZkZVFAYWNnQDkySCgwNmNnUCphKjsySEIwOFR4SW9aRkdFPUwwIXZNMVZGSzF5
Rwp6OXVQT0BJVGhxeXJyIUxfRXVTeHBUdn4zcjdQa2txS1lJJEJ7YS0tNCQ2NllhezBrUDlmPTY4
azFHZ2Q2V0xpUiMKemQhKUlaZFY5bzRIb3lnVj9RIUklPUV9ZTJSXk1yRDZuczg7TlFxYyptPjs+
LUp+Xn0+bykha3ZvMzE5LXBQaDBDCnpmbDFzZ0R8RHheKnVSQlZnLTZPYU0mN1kxUlVFayslJXkr
RWtpPiljQ1ExJU5vOFYpb3slI0spP0AyX2xsITtmPQp6KyUyaksmSy1iJjs7akxObz5uZTdrZGdN
R21Fb3pFQz4pd3dJcGhFQG4qXjZ2YzArQHZ5b0smQHV5VyMyb0QkKj4KenkmaDwhRiROfkEpOFNq
bWQ7NzFIcn4/cFhzRGI4Pk1jK1ZuQ2N6dX1XVTJ6JEV6PklxQVNqcHglT1ExTGQxcVgwCnowNTkl
Yjh6YiQhc3Z5VT51a0h2bT08PzI+Y1hjPD1ySDk5PVVUdlYlIWYhNiMmMVZCdXprXmlLK2Zqdkg2
QD5DRgp6JShTPjh2dG8zN3dmI305Yl9UNUpqKW1wdjYreG87RWJMUnRhZ3oxPHhOM2hXPGVyT1Jh
Q3pVRVpWbGltSm96dWgKelgwYG5scX5HNiUxUm5BKF4tO1YociFnZFJpe09UeEQ0TnhUam5uJU9Z
fDdjMyZZUk8qeVQ8SVRFMW8zXnVyTSYjCnpKc3k/SGszOXBYYH0wQEBFP0E1SWBSUlF5cjw1KHNC
M2l1JFJ0aj1UIzYmT0pgJi01NWV8TXgoO3o4cWViNkFaPgp6eiszdjFeOFcoNjtXZlZVKmw7K0o2
b3YlTlojSDMhK2cyNDVafWtIRnQ9cT91ZWE/VWVrOGIkRER8d0RJY344cF8KenokP3hIU0BYWUlv
P2syVSFFQF9gU3M/Z2N3KWVfST5xdVI5Z0R3ODglZzZEWTgrbW5lel5XenxkSnshMyVeU2R7Cnom
RFZkay1RMy1DNX1LMGNQPDt6ZEg2PVRYZDd1UCF5dkchcSlCZjxyYEFydldOQTsxQmk0NUsmaWNM
YntycHNPcAp6aTBPeUVnfCpzYTcjNW8yMW45Mm9KTn50JkZuSiVAUz5KemQoV0pVRDZ7dVNvVGlH
S0dOZF8wRTkoeFEhWTBeYGAKemhVWkQ2NC1ZbmpoVVFoNkFkQH1iM15oWFhyal5oPllgVEw2azZN
YGhZKEtnIy1JZChLMHlpZjM9Sms8O3BlZWR+CnpyI2t0cWJVfExYeEpPLWJoJHBKUD09ZCtGNG9s
OTBxNVFBdjRyKz1jPitQeipGM1ZBdUklUzU8NEZMbGB0ZDRfRAp6KGR1KFdWT3FZayt+ZW1HMD5B
aik/S2o2JkYhSVNQOFFMJHtlc25KTURMK1pQKHZ7PDBvWE1CRzFBcUhKUFFLfFIKeihPSHhrRmgl
TTgwUkg7TVhVQmElX1BeNE5uQzFSZVU+TEdxPCM4NlljeFY/XjxIMnxJcG51SUolVWJASUN5Qkk+
CnpZayZzKTdaKEVHIVApMT1Pfn1nNC0qejJ9KWR+WkhTO05EU3lgPzxEb3hjRUplZSpCJDxkPlQr
VV9GMSNUPTNwbwp6fEZma1olT2dqLWIjKld2ZUFSLWd8TFQ4QFlRZ3FEYVRDYDY9WldzWkpjanhk
M35MX3liIVIyVHRuM2EqMHJCPXsKenhCbXFmYUVecWFZLWY3e1NHby03ZU4yWlYpV0F2I25Da2oo
b19iZGJhRUhERCRpQ3UpOHd3NG5AJVcjWm5jQz1ECno2U3AzbiMkMH1SakFUM1B7TUctNnZwcTYp
QGl7bjx2NUdnMXM9T1FeNEZkaX44dHdmXmNwRjJsd3VuZ1JONWhiawp6KkA0dExHOFA8WldkYy1Q
big0NUI1Mm03TDtWcX11SkQxK31kKEBSb0JzOFArajsofSQjfTdLI0tndSUhTHtMcjAKenh7c2R8
PUk9PiYhOz9QQiZOZEVtVE9re1ZrSSFYMXRmfF5qSz5QMHFUUGdwPGk9KV5DY1cjeitEP3s5SlUz
Q1pkCno1cUg8Rl9aVWV1JUQ7cHxZcDE7WDdJOFd2R0hUbFZHdkBKM2shMWg7KGtsYnAxeFBkZHpv
JmJAN3lAKzJwYCU+SAp6K0x2RWVVaGVMYF82MVo+Y2I8WEd4dG11VUV2R2AxdDZAfkZ7QzNDPUNm
Xjt6P3JTO354elI5PGZyfWZkJks+TFQKeiM+dUxmSCYoV1R0UkMqbl8wWEFAenFKWXskNUEqcUk7
V1p2YT9gWEF2a25yR2tgeUM8YGVnZEE1V0R2NiNNSFo9CnozNU19OyU0WEcrNWZGLThkUG9vdFBU
bSlIY0s7ZVVDQ2dfczUyaTcwTTx3fmtnMnkpbE1oOGF3ZjN0eVJzTXdpLQp6PkotbDxfSEt5OEVl
dkkxOyFCVlMmQiloYkFPRjhPRV49dyhwNH1pQ3NkRHtpdkZrRllKNEhWbiFwSEwrXjYpPEcKem5B
N1IxJDs5ajtTZ2VxYkoqSnojUlklb0ZwbmlsbENjbThEJHEkPld5I3lBWlBUfXwmM1RFODk8b2tv
NUB6QGRBCnpjayU/YCsrLSQzPn10JjRINkU2Q3FmajR6XzQrcF9Sd2B2Y2gtQVchQD9JTndlP2VL
bkdINFF7aH5PWTMoTV8rYQp6ZGNOfG5pQCZfUUpEJilxR0RoI0xCalE9bnZndFA+IURMSWojJnN8
fG1YelBJPGYyfG9IdVcre3J3eFNadVNTT2sKeiRMVC00PSZtfnZyNDZqe2hUaE56NjUofHByMlcm
Ry1kLTNsMnxYN0xFVVRzO0dpQU9HRnViQmFoNSNNVCUpQFpCCnpVcnVZJDFSNSleOzllKmE/fldn
d0ZCP29aKFd0VV9BRVgoQVVWNEFgWUxte24qdGpBZGpDfSZ3d2E8eSZFfjtARQp6Pk5Ab3o7NHBl
PzhsdXpXbjRLYStJJHZ8dXNCSnhLJS12dEM/WkRZP2syYHNwWEhvZGYmYj5PQmBzWEMpNnpGQEEK
emloO25KS0NfTTNARk1aejBpdTcheGxmWDNgIXRZV21sI1p+KD9Ge3w5NyswQWNjcUR4YH4zJEJX
VktGOWJUVCYlCnokaGw+ZWBkVlhTOXZxVGluQ29+XkowQkpnKWMpbExXVmJWa1Q/Yj51cFk5MUFu
Xl84ZzEqYD5pa3NqPCk0ZG1YRQp6cHI2cGwheiZVQm43SkU8dCRyXztFNHI0Pz0waEh2WXFnQWU9
UXY7ZmIqZl9edyF7cVlxdjV2c0d3OW0wUT9kU1IKej9OaExkaj4pa0ptSEB3MTxXKmBDRmB+ezRn
cFU1OGNoOzc/VXNwOUFhTE0wPUxpKngxVTJ5JWQ/U0NuSXI3YUBmCnpDNWByMG15Uy1LejJZKTdt
e1dqbTgkJHI5SXhgUEAodGRxbzw1QUA3aEQxd1VxRzV4cVI8Kj5mb0pfYVMpZ3Q/egp6czRjPyg3
e2tnUk18fU4leEAjfCs7Wj5ZMzFHQCVCKHBxaFVKLTczTFlNdCFsUHpCITl6QDdSd0FvMkFCRndo
UlkKem9xcXA8OWAqU2IkaF5sJTdmSGxBVVJ9dTU2V3VDQGxZYXVQdXIoN147PX0lJiRPU2BRP30y
VWlNRXFuenBuRHZVCnpjKkNES3RFZ00tKj19WEk8UFlfYGI9bnlZaWglLSVTXk9UdFVPdmtCOSs2
KEFYbkFMfElzODUyTDZvPjNjKlY5KAp6bCNWIzlNTGpzTll5UzBCVWdqV1ZZaS16elJVYXZJLVZ9
OFI1Nm92MWFaKlYqbmBQNypgYG8jKD8hO2gmLV8mMj8KeipeemYpQGNALT9AP3BHYnVRaVg5TXs/
UlpZQW5EJXBJM15kNE94VD8tR0o1aWNjTGJIRFhSNzhIbXBaciNnNnBICnpjY2tDaXRRNFVDdj4/
Q1NzREM1bSR1KnM+a0ohd3goOT4hS14zO34lPyEpMik/Q2p9QT94ajV2UGZGUzwyTE0/KQp6NH0t
JWktQTBxRmdTeT03QHwjN340WT1qY2spaCV7NGc9XmgxYz0/e15sMmxBX1hDIzRNYXRjaHZgNlk2
NysoI3EKem1DfSQpWiEybmR3VjFxODMrR09xRTBqQ2VXRClkc1ZqNDIzNEo/I2BveHlfZUp4N3xQ
cjdoOCtwV21kNmhuO2dYCnpkeXwpQCtGfjJBUjk4fl9DO3JEQWdeNyZPS1lLWXJxd15iPXJLRVA9
MXByZUZzWD9Vait9OzhrZkB9KGpXUWNwZAp6e2Z0Uj9kRUBIcEJVPXBob0dZUFE+OUVgVChvI3U3
ZkNveEJMeiR9RHVleml4NGR9ZmE9RUplTTkwVlRJJTM/WmoKenZmS2ZVbT05ZCkjQmwwTjVRQXx7
bmYrK18ja25wfmoxSlc8SC1RJG43JDdoUE9adWg1LWFSaXVZcGtMfiR7bS1kCnp4cXIjSTU5JlIw
dWJiUVNpUWl1XmFBR2o+JlF7T2JITTc7Y2xgWisoVHtVPCRmT35fVDRPa19eYUBtV2NXTDd0YAp6
UUdhSStLamZZb0A4OSR+UDFUQ0BrfkQrZ3Q9a29NMH4xRGJuQmhGflR2Nyh2I0dATjd0akF1MXFt
U3Q7SUNPJnIKejhIYC0hWipUbk93XzVYVnNhcS0yZlpNJF85XyZpbj9Ee1ROT25ybnZPUjR9JEs1
OVZMWlR8V1ZLRWo7UiNGQVZRCnoqI2NJJllAPCR6cVE9JW5PKn59bz9Aa1oxOzxoJUZXQmY9bm04
eThgWW0wdjdCY1MzMUk2NGthJEgkb2AodiVxVwp6VjhKKG91N3lsQFBKQFlEREJsMzxLbEQ1JGwr
VCpqQzh1VmlvVUtnVnkzIUptNEcxcCF0RFFBaCVoOG15YDt+eD8KekdTTUlxbUIrOE1kJD98NHNJ
WldBIXl3LXcoaTJuQj5PSDwkfER7NSZ3LSQrKGghdk41WWFzSH16TWJMMGVfQ1laCno1RWU+N0M4
Z2ZSXyZrJWRsIVh2bGhFMEd3N0VWNDVTc1REej8yYSo3dn4kVyF1bD0pS0MxKWdZOSp8fV5rbGdx
Xwp6VHJCPVlIO1U0dHRrQ1p9I3twWT9wQXU1bVMpZkEqZVEwVyRWVUY7d0Uqd2Z5YVV0RllGP082
SjlffVRLVnd0fDcKelZEejxyITcxdmkmOXpTanRMfH0yWnBwdyRuK0ZsUWdodXMmMmskdm9YOypX
Xj9HSUQoJTVLO3UldCl4OD16OEk9CnpDcC1iT0VgUGFXdlZ7fUBKdHN5cHJjIVlRX287bWxWSWBk
Q2JXN0IoJmVsTDhvZmx2Nm5idzliJCYkbnMhUEtJYwp6ZzteYldYWWtSVCFNPTV1WGg9azt3TT50
bGhJMGYhQmlhY15qMXA5ZzJtZC07bSl9RU0hMkp+OVlFY3A3Rz9ldn0Kejs+b1dTems0Km48Nloo
YVp1OEB2VjxDP2lLKjNqI2pJQDtxZzdhdFlVdXtaUmpsekxFdkpWPlBldWFoUipFUWdPCnp1eHRu
I0UpPEJmWnRKaEEjTjwjUFpROWphZ0wtRGw0NmIqc3l8dmFyJkphZmt4UD1lU00rRHtvK3sySyRE
VT9Obgp6K0gjQzFSeVcjX14+OHYpSVE2azcjSWZpJk4mb1REWkVyODZPcVlFUFVMVi1kP1d9ZGw1
VDg8bWh3QCFoQ0F5JFoKenVQPkYjbWFiOFVSVF5AZlojUjF3PUMkNEJtN1NeX3omWkVrdm0+ZFk3
SzU1SmQ4MGFiYWRzeDRFendlQ0IxYnleCno7a2RhSG4xWiNsJHgmQk17b1g7SCtEKnRIWCgyJCM/
c3poKDtrRjBydW5pfX1jJk4rUDwxMDJgUS1ZTm9EPjx9KQp6Km1QTnFYYnwteThMND1pP0dOVjJH
PXUkbXUrfnB9RTIybSMrPnoxaHtmUDJHVUsrRDdvfCs9cUg/di1AbnMpcWYKemNmLURHc3FmLT9C
RTRFbHAqJURiQjV3M3R5JndyKl5neUEzaVQ9SmxhQWR9bnRCKEd7P20wUU1VKXhyVUFUK2RwCnpt
PmA3clBwd0J7I248RDgoZHFhanVtND9OeDU9fG8oQ0tXQUReKTkpPURIQGZ0cU9ZeTBhP0lYKEk0
UUR6Vj9FbQp6Z3ZlWlNaTEY9cC01Q1ltVEtBfmQ8MD59JU5iNyNlTj1zV3x5OFMhZ2lwXj8lUS1F
O3QjZ2wmTExOeWE1QkU9LXMKem9NPSVlN0AkRjlUTVg5fFpAeFpnQlotKnQqbGspRHlpfntVSlZj
YmM4Qy1JTWlyUCZeVFJVTW0lOWlRMVhUUjE7CnpkO3dJdXZzRnN9U2J4TlhoYzM5bCR1PlUkLUZt
JmczNVZUQGIkKXJ2ZGBafk1XfmY1NHdqXjZWUUl7KjxqKjFESgp6RFdAaFZyZjJ2clJEVjE/OTNu
Zio0SURgVmstKncreHAhMUp7LXtPeGNfZUJANCVwfTVqJFhDblpFOz84ejNzJiEKekJWOWtTPnhT
XyFDOV9MYld+N1ZpdmRIV1VSPzAzKDVocyt3WDtiSUkkRDd3ZnRgK0hpUG8oSUZKdWlXZHp1dHNe
CnpufDZ5YkkqNiVAUUBiKzRtQDB3d3JoXnh+TT9ybHElLSEzVG92R1paRFhgNDZFXnlIMnAxbUlD
NmVpMD0rP1ZydAp6SzkpOGtXVSNAWkQ+aGV6ck9vc2pJc2dEUj9fM3ZMb1Qtcz8zIyo/NVVVMFYj
N3pMMSk9WUo9cHVRVXBtU3tOTmEKej1UM0hZe2B6UWxRQzlmeSlLfDZuX189ViN3bEUmemRgc29n
I0leJEtGKyl7Zz5yUHVLUD9IPT5JfmxRaW0xLU48CnpHdHxUSmo7RWs0Q1NReWVpcX04MkBzZkoy
MD41dGozKUJ5XzBUYW0kS0AmcjNTQnJzZVozfGMtdlc0Y2dQNF5tUwp6MDxVPXA7aiVgKHMtKTZM
Zyk7TmRyNTc+c1l5OzA2d2xFRG5ucSNgNU9AODJaI0JGRklocFlWZE4wZXpAVngmaz0KemQ/REIp
PkBATDV2SCR0UWx9cXlBdkBBTHdKYGNURVI2TGVJdGxDPExxLXtQKUtTWD96NyhhWD1Le3M8RzEq
dDtOCnowSHNtLVVCYHgwclJ2RUJQWS1MaUE7Y2VsOGpKQXdpMHltU1BtdyskN0BzSFNAdz50Qy19
Nkc0Zj1Ic3R7YzxjYwp6KiomU31WKWdNQUw2PkxjSWFQUFgoSHY7OUhmRFpDbjA7blZeLSFZR1Qw
bDN5UUdxbWJaa3BAZytuJi1ZR1pYaEgKemNqPGRAZkV8NFptVE1eNVh9eSV6cnFmYDdHUSRKOFh5
VVE/TyYxSFozZipudDJ4bEola2BQQ35AdTNeSSR2ejZBCnpZfGM2NzstTXhAVH01SUhUVGh0IzJ7
Q0dCKVNLKUtLeVhWNTQmQiV9P3lGZj1qZThiWm1VR0tqPzBVRHNEezYzXwp6QGw/NWtzNjNmOShM
ZGUmX08kXlRqZHBrSUMjdyZ5P2FLJG45OU5PMzAmLUpNKT9KK3w9Tms5LUxwamtHTSoza00Kel5J
bXxrT3xJYzZWZXJQNFg+T1lQXz1TWX0pO0syZVZOVTEkI0ZwO2JIe1leZlRAQUp1e05selM4XzAj
TllsS1U5CnpsQ3Z1fmZOSHQ2YnloYWpRIyVKQks2LXNlKzI/IWZCNnZ1Z09OTClXT3U5MFc3Uyso
R2NSPXswY2JCajtWYXchRgp6and7RlpXUmlWI1grc2coR3c9cmFsK3xGVlQ7IXp0RiRwSS10OT1g
SDZCJD4oMXZWMVI+M2BxRkNhSDFWaD9nd3QKeldAbnY7ZGxSbWBYWHNKRk5eaX0/bUZFZ3E9a0Mj
cyFwKlN7UVZNTVBUdVllZ29FUCt9eiQ7OyllNDJgdStlV3loCnpuWnlDcVE+ej5JPSU8NDh2K2FT
OSkkc00pXj1aU3dJLWNIbVNxRlFRKztIbylKIypKYEBDVXwmSGs3Z0hQLV5HSQp6dl45XnZxRlJn
bGUwey1CWWQ3diVRN3VSb1dzQS1eUFY0KmZFQmd9RShCPzZeO1FBTzhROTFGUCZPT0NaeiYlNm8K
elUyTD0oa0dvJiZpN0lQUHpKYXV6PThuZVd7eWRkfGlCc3RgKHVgd0NzTUdTOEVeVCZiPjMzfGl4
P3BkYk45bSQrCnpgPmc5TyYwTVpDamItd2xAb0NlfSFtYGRYLVkpMFh5Y21TcVlkZ3FJUVV4SlNX
fi1CWXghSU5zQEc/P0ZASWx8Ygp6VX5hQ3Azbz0yb3ojN1gxdWNAUyZDS1VMem99UEg2JWxMfT8z
bm92c3pEfFU3I3U0Mm40Tj9RTDVDeiE8dGo2dSYKejkmSmdfY2Q+TW5hNVcrIz8zbXVVK3lfbm80
OXlxZTFKdmIhbnRfTl8wb2c2dlhkUG9hXzhsPll2VXlpQjsmTiRiCnpHX0JtKzVSczB0anxHbl9p
c0BNdih+QyhqdGAmT3VtMXhSXmx5PkkxNV5BZHxFZGp0Q3FTbDQ5eytyVm5QISR3VAp6M3FRfUBk
dXIlfCF1fHk1YXYwVnsqQjloK2k+bXApaEVrJjZpUTU/UVJ0PCRXYjgpMmJKVk0wT3MwMXx7dD1u
TnsKem5JMGxUdiE4OUpVKEcrPD9KN1UrUk8wUHZqV1psRnQqcCVqT1koaENCfU9QZUx9NTA5bj5I
TWp5JnxCZGx9ODRKCno1Wjd0O2hXdDlQK1Z3XiNqLX1sQ2wwZk0oKXRYZ1hqcD17PG1fcG44YXhZ
cjBBVUBXPjJrUkFScz4mYUlJPj0mZgp6ZV4mezFXaj58SFBLVTNDXzM1MmMjY0U9NT5DVDF1JC1i
bmNZKlhMREpXYFhkSG9GTUMlb08mcj5fKEBESEZeamEKelFjIVQyRmoqWntBV1ooMm4zSm05NFQ5
ZmB5WkFGJGI7PUJpMkZkbjEkR25HQUBrWCRMKEAxbyN1blc2el9VeU0+CnotfjQ7ZSt2dWFlRTQ2
KDQ8PCZQJVd0V1NwI34kO3FISUNpejMmM0VpenJJbXdKNWpSdCNNP2pxYDwyJTctOUlQKQp6cTRi
fEd5O1A2dndMNl89bXotdzlxKzVReFdPcX5KUn1XSCpLdmMjUFd3OFkyRz9QeWA7ZT9HWDhMMGB3
IWU0KlUKelE5Nyt0SGZPbXdqUWZ8JCtaQk87Q0YpTSZiUFpRQzVaJU40dj5lST8lNFQoVy1DcD0x
bmVUaVlkaUNMPko/dDhoCnp8NWU2QUl+OCpjbVZUVV90RTAqYVMlRFg3QjttWmVUNSVWVDw8S2lF
KmZAViNweEAkTmg+TjFQNEJzTEhkUXxqSAp6KE1FOXtmMjVEOGVkYkQ5OE9jM3liVn5KY0t8c0pv
S1VOJiotN0o5JXM9R1ohbXk/Y2Y/UGdgUlVOUn0pVVM2QXoKekk4KEpEaXVzSm1CYmlVdW18JHhW
U3V0WmJgaCohREtzPFJeIW50QVgpZSp1JUBMMDF8QE1gbG5eNnE5b0psWVY2CnpjcU5uTjIyV31Y
KGVHK3ZOOW0pYDtsTGNjdCZeZjxkfUZ7amBMKzI/PF5ibGQjKm1SbF8pMDR5KVR7PSp2ZCt7Ugp6
dDJ1PlN4K1U1dzE2eVJOaH5KXzV4T3drUUZVRj1LMTlLfTVeRjFrNztxVnBJVjhQdFJfX2dgMnpN
M0plK2wqJjEKejwyTmRQd0hDUUc5UlkqeGEmfHk8cmBuTWE5QWYzRVZZSUwzZWNlNUlDJGs/Mk1N
V3xUOH0qZmFYXnYoIUtJZ2BoCnp3UWk0Ujx9SDxzVVllKUpWNCE9WVlgRkd7YzVgeD8mXitLUExm
PDVLeD9NSz1BIWN9O19BJExxTyomOUtAd082eQp6NEQ7YE55c3FzJEdAMChHZ3o3KUMwbEI5V1VS
TEo5Uip9ZmRLVmJXNTtabiplZzI/LTRkJjB4djByYWgkdjktZEUKenoyNmRYKkdgUFNzWUtZRGpy
VWRNWVd0YmlGc1g0JSZpJj11PDBzOD5RZlEjeWxBXihIbj43RUZYWCs/X2BBV3RvCnpnSFU7VGYj
SSRxemRsTUdhPz9ASjljXkpTQDl2c3RRRnpmY0c/ZXJidi15JWF7TyshRzklKzVpRXwyOFRVRj9k
eAp6c0UjX1JiYkYjITRgcGdyUUMqPjBWaXh3WXdpMk5iUil5fkdpM0A0WD0+YGlhbiFfQEtyfDdk
KzE/ISstZklvQmMKekZ3KCZEbklyI1MyWTQzYHdMZ0g3MHpHe1YtP3V8Zy1AJGIrXm1Hak44VDlu
YXphYW9acFhkTWlYRl8weD0oR1JXCno1UTQpJHV6e0BiUG8lKEJfK1JBVTgtV0txUzFIOXo4Tn1N
aGVGfj1mUnh2WDZ3dz10XkQyZmh5c0QhLX5wdEw0cQp6dylrZUJpcDl8X2stXkt0IXNHViMzVmxe
Q2p3ZkJyQmE7RHZIVTkpKGJRb1ZDaCUkekt7YCE1N0Q4eFJHKVpudz0Kend+cF9vd21JfTFPeGVF
ZVY3YXZSXnNzPyVpZVJ8UkohS1Ioblp+QnpUJSpEVDZRYnw1aU5YRWF4QmRPP05TUlNnCnpgUCtW
JmFWfGtwWVNYNWVzN3FZd3Y/MH1FUzxEVWByRmVXZStpMG1GYXpqUChZZGpZLVImfjdpVDFpSkVt
ZWFaNAp6aTJnQEdNKXFWR0IyRjEkaVhvMWgxK1A1YXQ5U0dMa0BeUDQmfTFeMFVeV0d9ZWNEbmFy
MEVnZ0gzWlRLXms+dG4KekxmVGZGMSRYe29uJGdVKDZYOWt+ODhGMGk5R3FYSjNvcXJLTjdGd3x1
Z3xBJUg5bn4tNUF2eyhedjFMUG53UUhqCnpEKU5uPW1OQSs2PSgxakNpeWRYX2JUPGtuUWUtMlNj
UjUjaCpecjA2SH1tbnxFdnFjPGRaJSpUKHx2R2cydURDNwp6JkM3anJOfGs8bXpVQFl0S0F1PUdC
ail3Y3ElRGBwIVZ5aTJZfjlGfXlgcmt0K0FAVUVhTzZWeksxRX1YYytVbDIKel9HKV5mTHgtUCg+
Mld5KyU4JSR3IWcoXlF0aGppQndlM0xpbil+PWQ2YllyU014KyQ5P1FISUgqNlNZfHN+Wmp5Cno5
Zi1EJFNJK1hJMU8+UjYySGhPNEg2c1MwMH4/b3klKkV8M3FnOTNLYH1nelo0U1lpITVaPUR8XzhH
fTl0UjZCUQp6SE0zTHE+WldFRnIkaCRsNDRlTjR1e15hYWpuS0FPSXtuNDItT1ReKUlkSXkwSEFy
Nm4pdjNAPnpPWVN9VWArN2EKeldhe09KPzh3WVdWVyhTeXVERmZXUHNUN3g0TkJgSmI+PllXeDNn
ViVVWWtRfS1FK09VU28qVyRDYWd2NVkyZ1QhCnpIbX4+RXhsKTY/eXx4fTArbGNBT1dLfV9MWmEy
YzBVJm9yUXgwZ0pfWnc/K25TWVRXT1QkP3VZJTBmT2M5RStXMQp6diQlRHF1XmF8TEZfV0xgRUxe
ckU3IXhKUTxrXzthTU0tWTU+fjFXcHlLe1NNaj1+OSFZTDFyRlpjYU52dUZ8bFgKejZsRHYlbjZK
fkV0MFRCTDE+KVImQkk2KkR2UW1QWHh2I1AqM0pEOWRAYXd1U2klM09iPko2TC1zfCQ5UyM7NEZa
Cno7cDxWdmh3QVk8Uk05cVBteHpEPjAhbFk2T2lxR3REZTJQZnR0TnFZJElOaz8+e0AoQ3RHZTlN
RFQkO3RTc1I3egp6RS0wZnV3ZXw2dT9NVHZuWi17c0ZWPCk9XklYTGg2ekM0QGtONmRjUilUVXdm
TG1Cej4xNCFjfEhocHdAQ1E7bU8KejlybFBxIUI5IStMT1JQKktzTiN8SnlRO3MwQVlVMVF9MlpS
TSgofCNWazBnZElhS084elFrNkVvTz08O20xWW8/CnohQHtRSz1qUGc5RTEqTV9SRSllayt7KXpq
ZUMmI2ZiQSotUjFhO2ZLcH4+fXpCflg/fCVnTXJKPXx0VVBVdVBlTQp6Tkt2RXlfN3hBP21XNWtl
amcjPiZ6RTtNR0t6T3pQKEhLYCZSSjBJKnhjVUNTRU4+KUd3UDZFSm97S3xOJWA3XjkKel5QI2lS
K0dodERuYl9EXipEYFk4Yy1gPkkkIW4hXjVpYDhzU0VqSztYPW5ybnFMUWYodXJFRXg0I3VDN1Qr
M0tKCnpzRTwjfk9wRyVsSXRFSUlKQ243PyomOXFJdiRWZGJ4VHQ3I1A/dzt0QXt2Zm96Q1lrX0Fz
fUZoUnw3NUZhamt6Rwp6ZFNgajZ3d3xBaXg+Nlh6MzhnelZ0dFl3Z3NsQGAqKCRYM290S0hre3Im
PkV4eFFKVSNzamlXfEE1NkJZYHM/RWAKejBPZihNMCRDTnxvaFdsJj4lUFBLI3xXYko/cGFLb2M/
eEJJKXFrU1NWNlU4WiREaWwrVnp+cVg2UCgzbkJffTdkCno4ZmUzcll3MlImNnwwSEVXPW1waDw/
NXAoVERVIXMhMGtGek14RldNdSEzfSRwTm9+MW00SzxCS2orKypmaW1McQp6dk09Z0lqPVpyO0d0
WG5jRWlLaV9KcztaPC1ydip4YlQydyZFMSRiKT1FS1V5YkMtclA8MUhuM2I+N35KREJVQyUKenVQ
ISg+N09eOEtRQ3E9JSNxTD4mWmQoZnRUZV8za0g4bzRNXlVNdEZwa2BTfCNjWmNRcV8/Ji1aZ2ZB
MiVMcWVtCnp1QzA2b1FiZ1p9VSFWVWFJPDMrdHpxJmZLWT98NFZGPGNeeUdMa3IrTkdmRiU1bCs9
bGlUNEotNlV2Ri1vI00lTAp6Yi1LRj1va2FURnpDMnJBVGduIT01TU9valg/PnR+bipaI3w+Nkxj
WEUzUkFQI1FTeDFuPVpqQz5MeSR8Rkw8X3wKemsoM2VHYmVtJClsNVhHXkVKOStxTG5HWjgwdG98
cF5INXFEIXFJYW5sYFY0bz4/MjN5K0RLJH5jZWlVOWFPQ01iCnpRX2JrQ1gpXlFecElhK2BNRzd8
QSphYGx5Y1V6cDIkYmQhPDdvYSV9cUN+WV95VnF6aEp2QztaQl9nUk49JCFzZwp6UnVGK2V1bl43
RHlqbmxWZDlVbnhBXyROREtZPj9tMl5OKStmZVlGQ2t0UEVFMjghJGohck8rX2EkYVRxUHViP30K
eigwPH08ZjZpN3tXbHdkTGUrTGtgZWBzPGoqUlElSmtQMn0hbz9FWiRMfGpOVCFIazkxWlhSJiox
XzQhQVQrKWYoCnpXO1dKLUVeJTYkTzl2fUZgdzFkWTQ+RDZYR3BBNTlob29qQSpfaEB7Uzs/LWkj
emhTRyt1Sik9LU12KXluIXJOXwp6SUBtTVBCUl5xdGtmaEE4Z0BKKmdxNVFfaU15R1h2YHNSRFo1
bkwtVSt1YylqITBtTnpOSmJ9eXVgMTMwQnpwQmsKemt7VjV7dkFxMUwxc2BxPWBZOFQpQyYxYThU
PSQlfnhIdldIej9GUHZZSG1EZFI7bHJBeit7OFRrYGtxSDhwckMlCnpZSjNYP2czUSQmQlVESDU3
d0E5d2BIKWBMKXROJTZMU0o3JE02fiZoc3RuWmBvejBJNztHU2NGWCZlQXxsRHgpaQp6MCZlXklG
M2Mpe1pSNEZFO009VGArO31uMXgmcTlpTXVxJTxYRWZAbFRFfmcrNF98ZTNvUH19e2tyODRXWFVU
YWgKemNRWnBlRlFzOGRVQVR9IU5lM0JnRzFNUXhVcVo5b3ZLP01vRygpMy1ZaVg9P0FlYH1xIThM
ZHpiQzt0LTxZbn5KCno4d3lkTD0mZjdWdTlkaEFtWHJnQ2d0T2huO1owajVldElHODl+O0VwVyRu
NyR3PGo0QTRsYTBuaTlETzI5YDl3PAp6e304MFRBQXZBa2tTI3R4KGRuNCspVS1eQVBzRThvak1w
RERQU0o1cSZtYWMjdXM0ZHlrZylWJmh0QXJ2dFltNEcKemgjeEtNUiRBI3N0ViMzREluVTlOaEV1
endXIWhnUTxPY3Q+TjBYXzkhUTxuTUttUytGI0BnRTJCNHwpXi1MSmRjCnpRPGk0N3lfeip+eFcz
VClOPmtfKGRFRjFYTntFUHVIb3cwX2JJdiFhSWxzTzI2TTVHaWxHY3JlVnskSVcyelNabgp6bCsq
TDZIaWN6bkcqc3pFV3k5PWFPVlJ5ZFpUSXF7SUM/bW1KUz1vbyo8ZihGTHZKJHpZbFlBRUgmZ3Vq
UDk7SmsKekBKZUpyTE4zQiNDI0k5RVdySTZnQHprJHBCQChYMU5KKThUdmFUSFR6UGlqPTx1M3M5
SEBsVHd1UllxfFZgOzx7Cnp2cnA9PUJxc088R2plNjY5KjtAdSN4dTU/R0p9VFgpM0RvX2EoNEAp
PEdua1J5KkpQNHRycSVPQnQzWD9EOEk1Mgp6OH1Fc19WYVBJTFkma2VzdlkqbUpJXlVAQGZhJmlf
dF99X2glR1RDM0FiLThwSDxhbHJQbUpxY3stb01CR0xsKz8KekF+T3M1PzgtWVVlXnBpYWJDI0Jy
b2BMISReTzNjM1Q4b1RBcUdVQHswN1Uza0YhQzgpXiR1VExZM3VMcD9IeHlmCnpsal5BLTtHMUFE
c25tQ1dzWGhsUUw3KUZDSFhEazY2YW1fY29Ma2woN3srQz44RCskV2A7X35oKVByLTA9dl5wIwp6
Mzxlaz94fXJoeSo7ZW1QYk0hPSQ1d1o4VEU+eldYNm1NPDVVc0ZYbUU8MFBOKDNFMXZaOH5XYXtM
WVdvZEZlb1cKemhiMiskOV5wP0JgRXxWWDxQfHcocmRwaj5Cd1p6aUIxPm9wMFY2ez9pYSh7fURI
NT1BXnBGVUleOzY1RV9qZW9tCnpiUGYlQENUPHBMTWF7al95NThfYzQqSzJzOFRoemZEcWBTZVpr
eis3aU5NPmEkVXw1TmlacT9fRGwwNDdTUUIhTgp6aipofmRsKlNgdlFMflQySCt0MTsoTERxa2w4
dj1XN0VVfW05ejVKZz5CMTI9OFhAa1lLNXpYPSpqJiVaTkthM3YKem84Y1N8MV44Y19qJjZOdzg1
eWFROEZta2ZuS1NWKXpzdj1sYlY0TVFNWTFqTjtQaVNEaG01RHltaTEmdG9PaiNtCnpJSDFTTlNI
TzxiRmtEbGpOWGZGaDdMRHYmOF9ySkE5NEA2VSlecUdnNEdSWX5eTWdEKkVqQTB8KGZvQUg5RTBJ
Iwp6MXBQUXY8QkgmYG1GTDVYbWY7czJFUU04MTUxWDdlISpSTTJ7ZjFgcCN7O1Etdno9alBsQ3tK
RnBUKlIyQXYyV1cKekt6alBVZ31MNj1tKWxaT2QoVDR1VWpTay1tNXQ/PDdfcExjQCF0NyVyaU8h
cWdVKU45JF8/Ki0/TFNgQSRSMloyCno2aldxfUZVLXB1ZFI7ZD9uS2s7Yztnbl9sRyVLekNQU2tN
Zm9AdEY0ZFN3c3daRiE4UU98cClBeTBnKT9GPyo7Qwp6Tmc1YSFuNWpsKkNtbHEtWmVPWS0pXiRw
dmY8OzdAY1ZkQ3BTUT19bHI9RUtlKyZpNCNyOy1lcS1uPSVmVFcxPUQKekxKNzd6TERxPCNjKlIr
UTZrUHJzKG1LISZlbFF0alRONX09Vnh1S0w0QWFDPipHaW5UNUBNZHhyd3dBQjh0V2Z1CnpScTcz
T2FZRShmIyR+MjxHTTFUWj58eCNFaVJESzZYNX4xcUJjOyhDZ1hme0hJNjVZJnJFT1NTR2FubmRX
I15xdAp6V0BRWSFYSz0rK25fNXhKX2RyU1gpfl4ocjA3c2U1RGgjPDYpdElDNTU/Rm5iPWZ2JXFh
KnFkNT8hTzVUX0xaeV8KekMqblBpVFhnaz1eRzVTJGVIczYqKUx1YEw4bCpELTZqb3g9ZjcjdD5T
ZHtAMD1pKHpYaHtmaUQ0ITgkPFMqKCYoCnojJTlJQzZrZHJJc0AhfV8jSFQmUT5iQkQjQE9hZ0ps
dTVxaXcrfk8me1RsUTQrWTR6SlYoIVV+emAlKTJPRn5OcQp6dVRORXpgM1dTMCYpKlFBRzN+cEJA
OFNkSj5VPnRMV0o0TkRpOzZuRDw9b1MpUnEkSHc4PUVRaCU8JHo7KCE2LT8Kel9BZF5XdmpiaD9H
OE9OVWtEcHhHT1ZvYVFUN3l5Syt7ZjIwKXUoYXZ0dFdPQyUjbHBvZFRtLTUpMzApWT5LTmBuCnpL
Yj1Pb2ApaEteXihKQGRsMTZHQnshIXJid2dDVVk5dVF+c29rRHdVWjV2WEdxJkghSG9RI1EqSlEr
bilPbTZYNQp6N1ZKMkI/T3Fua3pLclBFOFlgYT9sVlQybig9ekdae29TbUpDdkdXdFJ1QTwrYW45
WUxqYy1+VyZWS3dSV2AtbDsKelB+Uk1CJHU8eGlEMGNHaGRldVR3R2NYe0spUnZUJUBOYD1nOXp9
WUk/QTlYJmxnVlRqISpZOUc1d1lAMDV4QDNRCnpAbDtlflBpak8mazIoSi1ENCQkd0lTO3d+Ynty
NV4+SmZaRyViUDA5Rjk+R1NGcE95dHNLeytkYHhUN1YrYXRnKQp6ZEoqaW1mVWRQT1BeVXhNXzJM
N1loIVZQQD5FfVB9NWM0eWNWWEZpRnFqbDxnNTl4TnI2TjltYTxpSCpmKyV9e3EKenh+VTFeVXdO
bjRaPllxYzxTKmY0KUAyazxoczVLQi1GUSYhOzxBZGJvKFB7eWFHIWwpOWhJYWVLVlc8ZTZTMVht
CnpuKlREZmFfKz9rO2g/SDRtdW9FejVSSFp9eXphZ1dVXkYzWVA2TyltX1pfV0Q+QlNGIXtQP0Rg
SGZuMSNGU0p3ZAp6VUNyZ2ZuS3NNWDwzPHded3lqVDw2SyQtTzY3fS00bFkzUklYQlRMMGlBdz1B
ZGFyMkVrQ0dqfW0mRmFyQDs7ZFkKejwpQ1I8bTdHIUJNRDYkfj4hJiQ/V1NRWjdLNkU3RUd0cE4l
XlhiZGUmTCoxKFl3eTI0T0BITTklb0pmNHg8a1RwCnpJVW9xfkUqRS1yeXJkI2RHY0gqPkw9TFV8
OXlFUSQyP2RjNFZNeTUxKCp1RlVoIUpLUm42dVJuNXU1TWtmTEhnSgp6IUR3OW9EbFI5SXVIc1Rx
VTJVKmVgVERhSXE9fCo2dFVfZ3tYdTIofl5PO1F8Y0tmJlIoSGE3OVdJbTB2JjB0NkUKei0tNnQk
RyRGfFpRb0okWkstSn4qdyo5X30mcjxBN3FFZEpZTXVBPGNuJUJJeHR7YFY2TE0qbXQ5LVM5ej4m
TWh+CnpgNkRhSz5+IUdiK24xTkFFJTc+fDEkP2t7QiFGb2A/T3Z3JGB7aHNKKGA8PmdwJl9SMGJC
eXVAUD1XJHlQU2p8fQp6VGRkelEzPCN2WWQwflpKPn1+VnZ1QiNwYCQ2QXdTbT8jWEQ/YytqPD9N
S2hWKWtoYFIxNCFLY18jQT9tS2t5RWcKek53WChLNXtHMjxxODJ+WnRfQmQob1E8fkx2ZGVvQzw0
aVQ9dk1kbl89fChkI01tPnZUPDlUd2ZCJW9MRF9IVlYkCnptNE58YzxCKnNtRXxIUlImPF55czR8
fl95VzxibTYzRTI1X0xCSyRYPGZpJEB1MDZDZ09RVEstdVVtfnVDZjskYQp6QXk/MUY+b3lwZFE4
eFAyWSl+a0MpN0VgMWhaa1dxOFNMMyh2RERTRChyME55R1V1PUwzJnExdCYoX3pgJTFiVU4KelJM
V2pqUmB6Q0hVOCYhLShpPkBJdHxFVHZiazVlenVvRm89bllmLT42WlV7IWVVRE1WdHF4Z0M9M3Bx
anFFXzlCCnp6K358MTxXcHcmREdqQTs4SFNRc24zdkA5MUwzRHd5LUlJKGFfTElFSFkmWiswaWxZ
aTduYy0qWkxjWE1xQn52Twp6PTByJj8kVmd1b0B9VFIjP0VnX1QtQ1pkdkY3OTRfcDwwMXUjcHdz
b3xBLV5wUmEqcyZ4SnVxOzZORShmNFMhfFYKeiZGa2x0Z0t1MzxkaEpUcU4kUk5Gcms5a0tfSXh+
SSklT2VJNTVPcTVOOWgmZ0NkSXxZKiFKYWI9S0JqWXBqfjdUCno5VjQqTnZSUGV3bXx3TkVOJlgj
SUBTQDQkelZ2PHZrZjAzPmpjfHlnO0Qybys2K3prfFNWeW8mYzVkfEhXM3ZrWQp6cG48M0hrcmFe
N1FNbUUydXJReWMmQ3JQKHl0S3gkYEpzYDNhV1o7KjlsLV5+Zks8ZlVvbHBSZVFxa0Y7eldFNWcK
ejZ7YCp9QzxHNkBQaHN9diNwaEw1U0NoI2dBeFNtREtXYzxKOXtiKDs0RD1XOWBSQSR1SHA0JStF
M2dePHh1SnMxCmZAUEU7em9SfURTT3p2ViVUdWR7aHh5P0M7cEcoaHJ7UHpDPExESXM7CgpsaXRl
cmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaWNv
bi5wbmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaWNvbi5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2
NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uYTEzNWM1
NGUxNDllYWE5MGI2MTBhNjljOGY5YmY2ZGViMDZjMGU2NwpHSVQgYmluYXJ5IHBhdGNoCmxpdGVy
YWwgMTU4MjUKemNtWDlfV21zRUgoKz0ocU1UQCg7eUY+OSgrQCpNTjRVaXgkNCNuTEk2ZmZAWCNp
NipueUljNzN5eCpUQkMpYnxjCnoqX25IMFhHYkQ1KUQkcEtObCphKjBFVXZIdFFHKE8xTntqREt0
X2FxOE0qIWIzSUs/dURhbEd7YCgmTVVfK31YXgp6Xz9FbkQmazE+LTdgSXVDcSE1bG93WFkyR0Jk
IXB3SVAjbUY2NGZFI0I2NWQxO2ltbjtBZCYlZENhUW52ckdARUAKenFlYlRsbF5ueVI8VDhzVWJj
fC1KUEdCMnBWPVptQ15MdWJGVGk+OEtTVCpfZXQjYS03OUMmaGRVe0paeldhdXJsCno7b05hSVp8
RUV9dn4lU25OKipfflZATEgqTUl5KmY5d3ZOUE1GTU0qT3R1dXFtLWhfZUEzaD53OTx+JSt1SEZ1
eAp6UHt3MSg0Y1FtbyFpRDdVQEkzcjdsJmIwJGQlJHNWPH5KPlk0Z1dnb0MreVk3M3UmVXplPHlk
PyE7Vlh9Ylp3cHwKel5NNmRMUGl6QHlKVXsxX1NGaUJJU1VKa35QRTEqSTZFOTNwPDVjUmA2KGoh
WlJVc08zNl4mb3o4KTt6dFp5cnUwCno0RCQoT0RjT0glSVAzaTkwenApPCtsPzBpQ3gmUj4tc2pm
SnowUV5jbHZ9akxzfC1xNiVYTF5qP0olQyN4fkA4OQp6KkdET2FEPjg8c3g5RCFDUzI4QmFsYDFr
MzVMWlVoQk9+QHdrYDM/a2JoSnBYJXVEQkF6Vj8xYyVXMXh4aTR5NEEKelZ7PX5tNyVEWH49eWg3
bmAzb21sJVUmKDUkNTg7X2k2PkIrKzJTakV0TCVgfkBIODJDVH57dHAwbEtBbzN3UyVnCnojS08h
ckY0ZmpteGJwKiY0SmBAfDNpVStEJGpXfk1BUD13ZCppVUxvPUY4KmZDeX0oKzYtXnRNMlpKZSpr
JEtXQgp6I0IqMnZQMHV9UE90JEJFbVEpSnVSSCtCdkN1WWBqNXhDT3l7QkErbi1LUyt2WWFtPjg8
TzJeWFVJM0RHMVclVVYKejU1KytCX29YRVE5bVVRRUlpSGpWdyR0WWYqem58VjxfKE4/VnNyKCtE
K2hrX1MySnR1KVJ7Y31NWVVgLWZyVlV2Cnohd2E0I3V8eml+TipNaW07JmdUdkgpaEVEOSpkX2d4
SFNaTkAmPnUqXjB6WG9RTVIxKCo2fWoldDtrT00pVWlzawp6cnwhN3RMUk57ci07UUhYeWQ3NXtL
ZW8yRV9+emB0JFozWXd2RSNJOXNXSXtLRUFnekRCJGwpZ0lpUmMyYXY/YkoKem5pS3NULSM8Sihf
NGs8R3Jqcm5VRktCcHdFLWAoYjRKKF9vLT83MXs4JDxwWXI4a0lURHFETDJUeklLa3tTKX1zCnpf
VlJHclFmdEl+VkJmJjNicDIoQ2l7ezFBN21fbkN1U2tQeyEpM3Q0b3pEN25GWVZNNWpMPytoYzBJ
RTNjPlZ0SAp6QWZjbD9IIzs7KkxYKEM4WWFnbCp1REVhUHtRaD5yfDg0T1coa1RYSFhIRmdNY05O
dlNfNH1HekhzbWZqbUBiNzQKenpsKDxPZmk+O25CdkdnR2BLMjBrTGg9NUVYJH4xaHpVblJBZioh
LW5Ea3BkSDtIaVVqIXxseTdQN0k+Wj02eDNFCnpUQl9ZRSNHdVNsTFBXUkA2bV5lP3crbyYoWGxR
OFFhXylKM25hXj9eZTFBUndKPyhxNT5+WWk1YjZRNjlyc0pqewp6V153JmM0fHZAbmRfNS1naFF3
dkJHP3xKU3YySkpLUldAdVkwTSpeTXZmT1BlSiVLPXhzOG5gSCskV0JmK3U3V3cKem81Xj4yVzk2
KVArZjdeMj8mMDRZKVcqJn1jUEEzQngzbFZSUzV3XylSSSElUjF8a1ZoQGs2cn1mKEkzLSE1V15Q
CnotZH1XYnsjPHxCY3BRbT9SNEEwZmU1RTgyJXN9TWlKX2crZVA7e1FeZFA5eW15dzRZWHleNkc/
PzV2WnVBfSghMgp6Knx4NyNYaUIkYmB5PXJaQ2xCPU5lV3BWUVAySH0tLWR+KnwkTlVhKS0qe2M+
KFlwYVV2YzA0eEZGKWVHMXpPQXcKekF3NDZ4JT9wKGArYElkJG1zM3YmKzBecUp1ZFVzRVJ1a0oo
P3xTUklmVFV8TlFfcWNnTkNYdmZQMG9ZZ28rZCRvCnpXNjJ5SHVmUkMqK2U0ZkMpMXklbyFPRGk3
c0V5ZkgjPnhpUSZGQU41WlkrdTBPUGVhY2stZXI+d14yNDAjZVJ2aQp6PWQ1cDYjTkYkISk5Tk4z
QyFwN1pnKGx8PEZ9X0dAaURSSlgzdn1JNzZyUWdtR2p5Y1lLNmZrfHR+WjM9SXRrTykKejcwcmFA
ZW04S1BpI2RaOUpSakVHRkxiPnhtaVo8bF53IWMmZlRCNDhGNTRBNCVkQzMhRXxiZXFeUE1qJj9+
aXZOCnpfanhyI0g4V3YhTnRuT3pMQkpLI2phTzZoKktzKHwlRWtzXlo8PWlHJmB2ciZQRUJ9UGpf
PUt9T3x7czIhMjV5Nwp6IyZickBqLTVWTG5td0ViN2AxT3wmRjJpYDAoMSVTMWNgQlNnNjlxSlpG
NHN0ZEB4bShjWTduO1RnJSVGQ3hqbT0KekJwPyU1b2UjUjJfXktAXkQlSl43Rnc1fFI5WT1ReVVD
d0s3QyFNQGd4IzFLWGZwR19VTih9fGNeV1hBNztJTWhJCnoqSGklJFZCYnAhckF6ZE1ubiVBJTVz
YTs2YmlmSVFiS3BXTjY4WkI8UGYlYjxPd0tXPVpedz9WbzxFfX0yPEJuKQp6P0Y5MTdDZVZJbEpW
LVJrJF9vaFQ/TDVmNzJ6KDI5c0M+RVo/Z3F+K0tkJCthUHNTSjQmKWJgc05zX2wtXmwpX2oKekh2
JiNzUmUjX1ZocVBOJlZDQCRTYUNZY2g+KmEjP2BwcTRydnJ+b1M5KFY7NXtUd281RnVUeWk7Njlv
QztRdit9Cno3alBgeXoyMns/UF9hUW5QPlElfT83aH0tK1NQUi0pM3k1Q2kmaWV6Wn1URlNXMCNq
LVkwVlA1XnFTNUFJa01JQAp6X01HRjd7cDB3azJ4WWprWSVoemMrbW07MDtCeyR2cDx1MUQtNDVF
YlNrOTNvNipXSUh0YjRCIyF8VSNXX3VEbXcKei1Pe0NiSDlEQ1JhPXdiJERuQG5OSjxYKVZgfEk0
QEAwezNJbFVNU3xUU35fNzVlMk9RVFRnNyZvbSZ8VzUqRT59CnpXSWQ5QiY0X3QwNTdTdElrRl95
eiZkO19qK0hROGYpbGgrY3QpRmt6V15SY2c2JG0oMGhkaXBZQmRuXjFtRzFTcQp6I3R5bX5XXilL
VjFkRXZaSykmPDl5VkF4OGlJR29FT1g3flJuYnZHaXc9SnhfWGNoZ18qYnhjNGJfbmkhRWN0PkIK
emV+d1dkYyY2WmV6VXVqZHpAfWstNUQ1WihMNThVKSt1ZHRuQkhOfllpPzh9NjlBI3xDJCZvWlU3
LT44fGNBM05fCno3dCtyI0ZNanVMbVYjQjZTKl4kK2tVWnwta2MhcUpXS1ZmTz5+OG4tYGBLclRt
dyE9O0kmaGR1dnRlWTdRSHFaQAp6aDlLWFkmMkJTc0cwMVRCMTVsSkZMYCEpRGBWNl94LVNEYWxD
diVlcEYtbipMVVE5dm4jP0ZnMWxASDBUX3pXMGcKenVhXzVCVj8/T2QrbCpjIWpkentMWVp2fHhD
KlRXTDxoNCp0ZXBwLUg+b0pNQCVSJm1LNF5mWjk4JDBQQVo3WWxQCnokaUJYWCNRRHEweTN1fFAz
VyolVThVWEJtNm84IUgwbG5fQkZBX28/e1RwKEpjdGtrb2clK0FoRjYxdSFaJHpxUwp6UkJfMTB1
KmpvZmM7KCt1aShAanlISkRSaDUxfnRRKlV4SilDO016aUZvO3U5PnRvS3FWLTVtJXlJPEN5YSYq
eWUKekE5NjEkQGN1VzlLZXxyc2BRPj9gXkNKN2c3YTs8TU9rKUdkNX0rbktXPVlFNS1lJHlKN0Bh
ZCtIenJDeCswUiZMCnorK3lfZz9GWXNNWnV9dDN1YWBZWnNGMHNiYjBNIThveUtqfDtYNmNvcjJh
bWxiK2B6XnY2bEN6Pmo0OSV7YFhOTwp6dUdwSTBGc1UjTl5RKWVkVmdmMTNkI3VYKFM2Znt9SmNn
USMpfXV2az1kbz1VZnJUXkFueXhRY3U9SVFZbjQpZmQKemhuMG1LVSZ6VnY5ckZtem4pdiZ7KXRG
OV9ecWY2a3F3fnRXdSsxNF5sMighU0M/MlohJTtufis5cGNzNzE/WVd3CnpZYipiQUhYZ3tMZFdo
I2BkUDBicG9aUkZsTmFENUlmTjFWSTZmNVZIUjNJXypVMHRsXj5EYSFnRUo8ZkpQJVY5RQp6TjYw
Tm5yX3JGWXRSIWRrbTg2Skk7TnFZTGp8M2RmbX5iaTRXd1ZnO1gtODE0NC1ffVZ2IWJiNyR7NHY9
PWwpUE0KenV9bjZpeWRMX1RKcH5ZZEo1cHg+fEloITM+S291bT0jYCo9SytoLW12I2RnMUJoajB2
K18hQ0pxUGJnZnRnT1J7CnpPeV5GMDd9NGs5SzkxNF9gK1ZoUD49KSRqb3BlJmhxTk1XcTw4LThY
dX1mVSYmfis5NXZNM2FFeFZOX2hjfUA2UAp6NTYqbjMoKG9KTSZrPilWaClsdkdWdE50ZWFsT1lD
SGdnSUpkTmVrQypqb3drNj9JMX5OQHw/djdVY0J0QXsjKVUKekFBd1YwSzZNN1l0VkVTMUFLVGxv
SnpoZkw8LXE4YG1hT2J+KlZLN2VgOGBxMG1JQlYhPmMjbmVheiVIcCgyckY3CnoyP2BqY0Imfm1p
MjFDXnNrOVNIKDh4SkApdmRMaTdKbTwtKCM2bV9iIz1aVihmUkNzPCMmPDNETlE7Z18/OyltYwp6
anhAQEkrLTdffHNUTHo0X0VeXjhkO3laJUY7Uj48M1dzTkVTWlhFeS0mWTR4dWRtYD1tU2VkJmBx
Nyg/Ui1PJDsKeiF0OGNPYnImLTkreUZ2RXN2QGw7cTY3Yns0SUBkV1dXNj5tJTMhPTZ7VX49I2ht
WjRnNDljWDEofVFgKihzdHZyCno0YVVeTDtoUn05UylWeyphKTNmVTFCWWxYIz4jMUJVeilUJUpz
WU19PUZ3bkUlR203eW90dH1wMERAd04zNl9jZgp6YFModzx7a25oJlkyMlEydEVMcD4zRT1gaz5j
JFYyPXUkKXA8OW1uND1meCMkaUIoblghcGtDdT1aQVRQbGArIWQKej5XMXRKezlgeytkaSR8d0hq
THdGM0skRUZEeihhVmg/ckF8bUAjPW9qalVYM2UrQzc/K31+bnBSTyp4fWFHQ29FCnpEdHoqWk1P
MD5AcXQtNSlFN0JDPlJ4WSlvQ0JqMmZ4aihZclZMYmw4a2FzQnB1ISt7Wl9gLX1hTzZQaiNteExe
aQp6RVE5KFRtVndNJmJUcE5IdWkxSzNGbVE+aEJDUUxJJjtwQ2I8TGsjUWJQYXB3bWl9OS0kZUB5
MmdTbj19JFNUal4KelNHQTVjWFczYEdQYXBIRTI8WHZBWjBiRE5eO0h5eGwmcEEmUyVaLVU0O1Zq
dVREQDYkWCtGc1RCS0w3LW9BNmZRCnpnRjQxQWxXLVhwMTx6c0tCPChIfnFJdGpge1doYnxjVDA9
UT5ePUZmc0dISUcqaCV4MCh2RUMlZWpoY2JycT9IcQp6Nzs9Vj5jWFp0NUJnKnlhdTY8KGRGMEF3
JENHKmVDbiZJRXooOGIlNVJZZS16NUFGI1VuezV+fSE9OUo0JGdCKmwKeilBOXtzVEkqeWRhN0R0
UiR2RGUjbzJEfX5OVHU9MnFLaD5jcilLOT0peDhESzRraXk0X2VQb0slRipaaz8kU29kCnpvN1dI
OFgzSH0kXlQ5aEtAYE88JHlPTWNWbnw2dCNDNlNPZ2JERzJkRFF5eXtwWVZFUT5LQEJXbDRlTmA/
PSVgQAp6Tj9UWU9LKE5Va3wxPkVZNntUan1jT3swVmhpISF0WD87bGchelJ+ZT0tejN5Xjl8dkE8
cTA8S3s+O3F5b3hPMmsKel5qYCUrTyYqX1o7PX5Ab0c3JmxxJXVlRj44MkoyZnZqSDUxbCl2NDh3
JihsSjNPRihZQipyNC1WNmF3WSN2fGckCno0UTlSNHc/UzslODJPT3ZoKDJPVHgraylnPjZIfnl3
T2NSPjI0eXNMT2sjS0QhP1lZcmpGdnt9TGgxYThocXVSTgp6IW1RZDMwWX5mNClORUomQUA0fkIt
TzlkTHZDSEF2ezxpeCt6TFZfVlItVnpKez9LMnNIeFp2SVFDVGFSRFUhczwKektpS2VneTtXVEYw
Mi0+Ny0tYD9kPUpON1BsdGYmU0JSWChkJFBJITheMVJufGA2JFFAUkYoK2BMRihrPlYofFNmCnpv
WTRnK3k0VW8pO0RtNC1zJDJKIyFqTmVhb1A1M1YlYEQzfnVGKTMxdm5iIVFEQVYyeU9QIXlrXkFV
fT0xPn1aZAp6cShvbT0lcHwlRjE1JEYmZVI0IytvVURPRyRPK01aaTdRN2tNMXdiUml4P3QkWHxQ
d3ImMFNteTl+VyhWQlEjPTsKendGenVfXlNQYC1lb2hoOSZtYkFhLWpYb3xobGdxc2srO01BbDFS
eVY2ZDhIV0tOI2pSdSNfV1dPK341U0YyS3toCnoqJm5VbVA5YClPZXc5WUBhXk9nQUJiVTZ4cHFl
QVd4O0ApJFRnbGxER3Q5TlAoVnomWTtlYDI0RE8+bV9WZEJaawp6PnVpbEFmPCY8cGo/Xi1Wbmwj
aShSV1hsR1h8VGBLX09vKEVDdCpfUSFVPisqLW9wWigla0YtPExHK0FaWHBuTXgKekpFcVRfez1y
cGp4eWlfJE98QWxFPGxve0ZWeE44Uzx4eCo8dllXYSEhPjF2ZWdgMzFtXzBNSHJyYi1WOVAjTV5Y
Cnp3K0BDRzx+WlJQcSszaTEzeSFUK2UjI0BqezNZIzRhLSttfWt5fFpQdzFrS2xScEo3NGF8MUNp
SWA7M3tBMW1EUgp6M2AhbXM8JlAmRmlefENoZ0RDRkFoZj97KXlSJF9hJjc0JkQkRUk+ZGM1Rmok
LTM9S3JjeCtgNl4we19IcTZMQnIKeiF2KDtGVkN0aTR5JEk/OHp3RmQoNHtpI2RHdGMoWi1sI21D
bEU/MUNmNE5LMkstUyQ1QGNaZj1FYTxLTz9iVUltCnpFP24/aDNlZ0UmP1c/SmUxT2FhfVdpM35I
MUM5Sm9FfEBAaiZKR3tBdzZEPXh7bTMkVnhGeHImeUU0X2pBRCNVTgp6JHw7ZVZCPHx0b1Ize1Rr
PWg5UWhaeHBRc0s9K0Zze3MmNyNIUz0xLVIrP2Fmbzw9WXQyX0ZMbiYyUj9US2FGbGAKekZ0ZUw/
MyZTa0tIdXx+bWo+TV9wQGdtaHw7SDljOUN9KGQtMTkrQG83VSRIOWZqKmwhJHdMSjFlO25XVEc9
dWxSCnpxZ1ZNOGlebXF2JStSQj4hVzxxNyU1JkJ5Tj9IbWw0UF91cm5uZ1F8M1ktQ3hxd3NOOyRD
QzBsTlZiNDA8ZGJSUwp6OEhMcWpWX1NgKEg/Rk8hRT5Ke2I8c0xtKCZsezwwP0c4NGJRcFMpemo5
e1U1bjw3ZUNLcD9yMCNGTytodmImWWEKenJtN2swNihaKlZ5ej1MSTkzZDl9PUxGcXJoKEtxQSVO
NEJoaTJ6bGNMYDA+dy02U0Y3Tzg5JT15Vkw5M2tDJXZuCno+NzA/MFVndTZCTlBLfXR7eyopLSVW
JVZzLU0kTGI+Pk8kK1ZLfUpZWENmZzYkI28oSkh4a3R5QG8xKkwxYjE4MQp6ZU5BZ3tEXyt+dDEj
S042Tk02bmQwYk1RMEt5T0RYIW1sSUR2cT5XenJONms/NyNBRz1SVGhhUS1uMFpVbk1valMKenZj
Tz1mYUFXZEdMJHIhfE1SYW1VWX1US0Y5QFlBKVBhXzh8U2tBSl8pKytTQlhvZkZpUkl6VUlVcURp
ek5AWVgoCnp4U0s1cVJsWVZaMkQ7OXRkVFkxYztIZUFBUmdSYTElVXdpREFGTT9SUk99dWB4ZERB
PzdYUGo3XjJhYGJFYHFrYQp6c09gNzctcnxFbDZBOXlBWWJMSVM5XlNJTFJ4Yl51Mys+USYjOClM
JE5hJm1mezBMNEc9NVZgQk9ZbUYpWnxCfnEKem4rO3RRd0NOWEUxRCt9MF4mJDZqMytfdiNDSkwm
b1MwQjUrNk05KnxzVCRJYz1HY0dWYykzJTVKaH54ZXZieFRACnpFUUh8YWZ0OEpoZ2NZRTQtZTxH
aVolSk4rT35SMVQyaEVgT15HIUlPWSZrZ2x1I3xMZT9gYjA8eHBldSRBNXJ4Rgp6JGNVeHYrd1Rj
bmNSUnJISEc5eG11S1I5UGJ4fVJUQiROTXBnLURsVW1WQlI2b1duKVkyVGwrancmKkMlLWwpY20K
ejgxeWRVWTsjcGFzSX1BeT1lPCM9KnJINUUpRWF7UmFKRHt5KGUqNG9OcX1US3hnVXtAXjs4bGZa
KHtiX3E9K1Z3CnpoSTd6YUt3UG1NaEt5UkM+QThUcCtTczRXd0JfcEl1PSZ1NCp8MmZAOUVjdWFW
TnJPNSQtUD0qaTYjSSFlc1FjJAp6djdOTiljcX5hRDlRP2lJX3gpWmFSXiFEbEQ1Uig5TUkxZ0Z4
K0JrVGc4UTxOdD9+RW9faF4mKCpRWHk9SktgdjcKej15YXcmZXRvcFFhQnRzQS02KDkqRFB8az94
dVQjO1htXn5eckU7NVpzdU13bTU8d2RAZjI7N04lRzNgUV5kUkVRCnomfiZkLUhyV0F3SVYlanV2
ant5YE5vbilgd2xecGVDPClSb0c/VUlmJTd1RSo2fXNXcyo/O2FAWjE5fXtOSyQjYwp6MGU4PyUp
RiErS29Nb2NTPVNWcT9IZnEwYDVxS2FIbFBgOUprYmRqPlphanpUJUs7JmxpTjdUIXM/ei08aj1S
WFEKejQjMVNtIS12ejFWSWdFY3hUeCs3VEsjVD1jWHpJZzg7Rj98OUx6NmpPMHYhNzRGTmtQUSMl
Q196TjtqcmZpMFZMCnpkTG5OPWFINmFPP241KnFeOThwbnMtRkQhQXtTPCNXKll2NXtpeH5rI2pw
Nz05VnlCNXFjRDc8PDc4dD11c1FSZAp6YSVhQGYxX2t4SVhSS0RvQG9aNHlDV2FZcXlfVUEpKnRJ
bTBYfiFWfT5vNmY+KlBvOS1zTyViayprVmxKRiF1cDMKeitMQT9AQnQ4TUA0K2JQZ0hJIzlkKHhD
NiZ6fkY1SFZQb0BhYGN6PFExZmB1R3VjSiZSTzJ5RUtQYnZDZXkjUHIrCnp5M0h6IUxeMk88OyNT
OS1he1pEVDlWY3ZGWT96ZHA+fEh+cmx9ZjA+PmNfckdae1NeRytxUD5lR2J3Qks9ak03ZAp6ckx1
e248bDc/QER1bUVFdW87YGpRaXllPlhIdjlBYEtKakxHX0s/dkRLTj49bTA4cU58STRxJlFNfiNM
P20ka20Kel8renMzaylka0t4T35FQFM/QU5zTFNrMD8zN0owTHJJOCZOWXlFK3pMVUZsdGtZQCFh
O2pEangwWVR3JUMxfVZqCnpzZW91ZiRZITFUb0FgO3ZAalNPTTZPcXNwWlhySEo7QVd+USYjSG5V
ZjgxVUVkc2JkTktDMSVYYSRRUyZwSVMhZAp6bzVQfDRmTjctTmJUfU8+QUBZRlIrUS1WNVN3JlNz
c0xVRVchOHk5WEZWX0UlPEQxbk9QNTVwayF6M3BiYCYtVl8KemxtYVhPIztNb0JGQkdOX0s5ZShR
dy14SHNXRH47VEFuNVdgOGEten55dVZDVzJ2amA7Jlc7LT03MndYeks3OzReCnpWVm5XOVJCdFok
UzJKPj5Qa283IyNkXzZyNDlsQHUzMjJuSV9fPTxNWUY8ZlVCTl5RY2tiVEEmPHNOMTIhaHlSQgp6
ajY5c0BDSXFUbkB0WG13V0Y9ZjZQMDY3JllZTFJDaG4kc1I/XzZNKEgydWxLJVlvcENIZjFzUzVT
dVpAKUhQZEEKenkkPD8oKzNRRktUQz4+fUg9QElyWGV9Q3NaQiVKXztgQEpwe1VKNUxzWS1EeFVP
ZHo/KkJGaD1fJTRDOWhDc2t1CnpxWCZHUnJ1S0gpPWVHVHVvSC1sS1NlamQrRD55K1VDLWRQMmV1
PVRkSHNBPEM7Q1BxNTJCWEV2PypZdz4pOWZQfgp6azZYSkQ8IStvcFRAQ004dFE8RztDXnNrY2BQ
dTAlcz0lTk1FPlMrLT8kbGc4MSl8Vy1TKFVuY3s0Yjw5aCZfclAKejNvNXluTEE8TDhJTithRloo
KVZQc2pNYkZjU0R1TUx+flFva3JZWl5pRj07aXwxSD0hTHJJSmBtVHVXQmhOTkoqCnpWOCN9a2h4
NjhlJjFNSGMzRChTYnMxbmJ0O05OTXdoe2JzeSVvbTRUOVZ3dU1Pb2MmSUJkSlI8VC1md3hyeE9z
VAp6XnpNTzYzNntRMzM2QEwpY1VEVXJtR15pRikmKkg4azMlS28pKFVwdihIQzNge3soVURgUiFX
PmY+TCteNEFTelgKej52aGo2KHY+eXIqLVIrTiFRbnNXVTx7UklVYl96WCY3dnZaR1A0STglP31K
dCtga0ZJRElVTWtuQUJicHZGcTFvCnpTIWs9WEshfUw5dklTQTR4KnV7amhUVWMwY0t6b31LYmQ3
MG9eUGo9VkxBJUlWZEZNfFBFYm00a0x4cTRzVVc9QQp6UDt9PyU/N2ZTJiFCb0RiLT9EYFNHc1lT
bS0rYXFvMUVYUmo/UyQ2PktlKzhCPkBYXkxzdWI+WDFmPFVrd2YzUyoKekVNMXt2SilGXiFKfD1B
Rk5hY3FRO0R+JSQ8UEQyQFRtdiZEak5ONEl3ZUIlWVhBe3IlRDlCVTVESCRHdDB3NT9CCnpxfi09
a1l9V3YzdERXPmZUIW9tRm1SMTR7Py1hVHhlaVA1SnRBRT0qeU9iIURPZkxrKHcmVSZ0UWh8K2NM
YS1aYQp6Tz93KSZBKXlaT2xPMSUtRmEmdT8jclIpKi0+d3F7WWRTSjVATURWb05NN0V1M3dhV0Vi
VlZBYzQ5VnsrSX1QdjsKeiRaOHJ3PXxoRWJhNHdVPHpmUFchaTdsSj0pOV9+OWNMJD9pWTBiTTNz
Y29LKT9ycEgrUX5ufFgybDRkTGMhdlBaCno1KGQyaGUydTEqb2ZZOTB2en4tX1JTQXFNMkw3WEEr
cklnMFBWWTBuQVdDRWRkaTJ8OTF8Z0AjaFc+Kk1UdHVeXgp6Vm48N00hfWVmPUM0V0RjLU5oKzI3
ZyU0cyVTXkdBQzREOXdgYE8jYGkqJkx1R3ZnYT9iYkNLJlAqSEF9dn5NcDsKekN3a0M+MXs3UU1q
QER9fCh6SVBNITI1KUJBJXJjPj5RJFdFVXE1P2AydioqfDhAKWN1NV4/N0dMZHd0dkZ7NkVBCnow
QmRzVW1BZ0tpU05eOCNlJT58eFJIJmhNdmhSYT4rMEVNbCE8IU05Q0U/NzQjLXNFb1E5TW1TOXNI
QipzLVp9PAp6fE1MS2hibi1YIT52fj1fcXVGWk12djtkSmRWTXIpTSlzXyhxLWNKMDE8enBLUiVp
ZGxkNmJzdXRzWTJyUWh+NWcKeipXSDNsMkdYQW9taXcxVihudm5ic3VWRSYpRT9pN0NvYzM9I3M/
Mnd3XkxvNnJ+MlU5VCNvUjJjMz82Qm5IVD5kCno9N0FVV1F9JE5gdDExJik+bnZMI3kheztUdl5L
RCFUPWh1Tj4yMlJHKGs8fVM5NnlfNHNYNzQrbjlBbmU8UUhJdAp6YCM2T0xZKnZ7aXdJSm41MV41
YiU8bThlcEpBRUs1UFFPNCZwMU5HRSZGU31qY0dSZHAjU1k+XmNwOHpeVn5QcT4KenZhaShBZDMt
Qj48LUYkcSFZX3h0PVYpZHJ4fV9iR28jQV4+VmhESmBuKzs1VmZZMTgzOUBBank0SDsye291YVp6
CnorRTFVTUJwfGlDV08oeCV3OUlfdS03NGstUHM4VEAjOUx8bS02OXhKUUBFfH0xd2FqJmFWKkQ9
N0B8Y0hCUFhofQp6NUxLVzchJWYjQzB3TmJ0cUgyOXBjMldEUVlSKz41ZmhzU347TDJwJmRkWmBi
MThraDA+MkBHJiN5cF4yZEV5cHwKekpTakQja3hvY1FmOX5tSE5KaCsoMn4ocSRzbjI5a0psQSoy
YXJzI2lmYUdhdFE0N0RAYTxzIU1PcmM0aGhWMStkCnojZ2Bza2ZaeDQ1bFdmTD1VfEtPQjtDcnZL
MSVTQSsjJlEleXtBTkhTeUc7fnJGQWpVRHFSMzs0cnxKTCojPG1+ZAp6SGk4a1RKcCMycWw0P3E9
Ml9ZVWc2c3o5KVZDTWRFVDIreVZJeDRpbyRhOCZFUD1gOWdRMytTdTZtUXhEXkZuYEoKenZwa1Qk
WkRYeXRIfWhWfEt7ck44YH1RVWg7IT5YanRtWmVQe3VMdllWQXAtOT9rOEh2WWFxYHtxcT5Cejll
P3xYCnpSLVozMk1uNUQqJEplIzkwO1p4PTAoQzFePGloeVNvMWY0M0g5Q0h0YHFpeTRvc3g0Pmte
bnVVSy1ZUSl2fDwhZgp6SjljYlBqIStVYCF0d2RsRlVXMj98QVFxbWcqfipCZzhtejcjbC1tIW04
OV42PSEhdUk/N15oTEJ5SF52Skg+LUMKekUrV1dWMl9xQDlOSFgrQE5DfHZeKTBQeFcwTkFjVzNI
RCl9WXU2cHZXJFRlMF5jYyR5aytJeClpZChPVmRuQXBVCnpSQE93OFcqellgIXxYSmVeeHpAbjE3
fURnP2JzYjdjU21TNmRGYHFhRitsTHFMSyQwb1JWPENDYzhLJTJre3h4Ugp6TTNCKDx2VT10NjAx
YFBBJTMpLVJqITxpLV53PShhMkIqZUdgPUFeS1B7JDZwKjBZPExVZDckUVA1c0U+NmpBNkMKem94
RHZUVzcoKTZwUT1hOU9RUVpART9DOWolfVdBJV9KIWIzYzk/bFEhNGMqWERjSjl4dTd5NzFyZDgw
NGomaUt5CnptKV8zUGReUldjKz5CLUNwZnt9akQtfHVoaSVKIzc7NkhSOShWeVg2VC1qTDt4YFJF
VTd5Ql4pdXBYST1XPk89cAp6ZEtaYGNFMlhXSEteVnNmMGRsbjZ2LW85Pml+XnIpWmE1U2ZtSDN7
aXl3OTk1MjYtTCo+S1Y2antrN2ExTzYlfTYKem8tcEw8YTdDRi0+YXcjV1V9PkMpIVheVz9pelZJ
SEJlO21IS2RpY0RuKUs/c1diM2VeNyliQEM+WEcmYWFNPHZMCnpfJHY8OSRNZl9ZOT5EPHMjYWlP
dWQybml1QyVxOWoqK0Y4R1pzfG1HXnwmd0Bpdlk/YzxiUV4ybmhoaUlYNVhCegp6Nyk8Rjdra1dv
OHVDKD9uKGNjM25eUWpuJUdYMVE3K2hLR29YPkdqd1RjPF9GQndFQ3heaDxiSVA3IX4rbkk3YkkK
eiNqfkJ2JihrPmtTX05BV2ZkTlJNPkdHTkBiRjVCQWt4emtyQW4xWkU8S001Q0smVkZ8d200dmM2
K0BCZGRvWnRvCnppWGg/LTl8N1R3dyV5T0A4QjB0KnZNdyR+eE9qSzZMXmM9Y3szdTBNYWh5WDxX
ZFRvTyZlSHtlKXgtdVlMWHFKMQp6KEZ+PmgoUjVLYWlXaD9YXzkxR20oUDlUdDRPajchZ3pzYl40
JkBYb0E2bkg7WF5aT0VGR1M4K2IjRz5xRHc/SV4KenckODt8QD5pa2Y8dzBAYHteeHNTTFFqc3RH
KGNPZiExKE1kVn1lMEtkU2A1akU8e3h2IUcrbz9XLUVTNjQxS15lCnpJeiNhXzA/c3hNUzBRVm08
dEt1ajcmczJiQWhqUSRHSyZRVkNIIVombWAyOUJMQXVTVDRFJGYoa0hORmZ7UVgkTAp6eFc5I2xX
Km1jfWZHTktpNVApZDVhYDAyal58RTQkcEdnNjxIZ00yYyQlJDR+KXphJWZORGZBSFRAfWQ7R1kl
eCoKenEhenclblh7PSo/SUs4RygxVmhCI08lXzBHWDxOUyY1LXl+Y1ZTM2NET2R0IUlUYD0qP3tB
O2V1fShCLUtGQ1MyCnpNZCtZYiZTRkBOeUplbT5rZV9Hcj5iZyt4cyY9PmI3QHdCdWF3KjVHVkV0
P3Q3PG9eWTk1Pkx9VTJnR1Q9ZURxVQp6dnpMc2IwJkFrS3owTHAoeCZpUlc0UE9sX2RxWlR9aDgr
X0IhOV4ydkBzZil5M3RUUkxYRjtoflFYe3lwTjAwcFYKelh3JWpBNj5zXyQ1bnUpYCgrZ358QXl3
UUZtNHNAV2hqbGxBaj9+cUJmcUtGPVM3SDNnJThWc0h4en4xJGBxfik+Cno/aG9+RCFgMX1rPzZn
N2BTeUFOdWxueWRAWk5ANVheSzxMUjBLQGpIbzdwRUVUbFk7UUp7JmY0MElYSTApez03awp6MyEt
PHRLO2RXKmNRSE5YNlkjbj9YKit5QFRgPC1YRW5CLSU5ZyR4YFgqeHsrb1JxRitweW1teTRkWiQ2
Y3ZXP3YKemZRan56QmFtMUxsVWEhenNNNlNkN1pwNDdZJHJMSmg+cUxTKyRBdlUjQkQkaT5xM3BN
KHB+LUJiZmZKWD9yNTJsCnpUNks1MiMtcz5DS3pkVT16KSZsPXB0aCF0a251cmtte0JIZzkwcDw1
dXw1PD1AO2QqQSFLYDhSV2lIVCF2SUp2LQp6UFVRWEoxOEFwenZuKXpLYENAbEdOeyNrZlEqeVJJ
Y0tSRFArWShZaXNXO3NETXxjJEotfW9DRlBoPGdpQnQwZzQKekZ4fTBlZDlZQktJZWsqSShDMjRE
eDhIfWpSUXtrPSFmcnxqUFozIWQ7aGpONW53MkMrV2RXMmx2dFJ7ZjtHXjd6CnomYXo1NEt+d2VQ
WFoqO3I3JE5iNmlNRXQlPjNAZjt5TEtlPyFRYWh1WU5QRGRfY3N6fXI0Y3oxZ1dqOFY/M25xPAp6
aUttQW1LeDB3YDIyNE1rIyNUUCQ0cmp6N2o3PDZ2cnJqeyt2Qno0UTJUM31WU3J9QGV2cHI7RkJS
ZmZUY2dUcGUKejBMX3JqPW9KZ1ZoYD87PjNWM1JwQll1NXwmcj00bT8/Z19pMHl1aTZWeXdRZFp5
czZ1MXBoc3tYYiZBUSF2bU1LCnpMKCVCYFl5YjNjT0MzbC0jamRwOHtxdk51LUVaQmtEam1lUypM
P25mSlo4PXRTKkFCSj9FU2Y0T1MkaHw9TkZ4Kwp6SCFlY3hEJWFITDhRZS1EVzQ5X1JXWkdPUntH
LTNlMDVSKFh7IURpOEl7WkZLJW9ORD09VDR8MkwqfEtHRXR+TU8Kek9jVikjKTZNRXB4NiRiclpw
cUVfTkklQyZYXiVCd28kJGcpU1cwZT0ybTFBTVpWMnN4ak0wMiE4YmN3cXJ6PX1XCno/SlJDRzc+
X05TYzJ0NkBpK3AqNjRWWTZYZ0VaMlVoWm8rM0xrITw3TnA+fj1vI0FwQkEme0FLVlR6SE5lTEp8
PAp6LTtMZigjd2szRG85MnplPUQ5V04rI3p1TDtUSG1OcCVaTTsofjZWJmx3bWIoV2dpM1hkdmgq
OTErb0J9TTVnNzwKek45X1FvP2t3bj9oeSYldVh0Xj1YR30pVzNMX1E3JiM0Pn5YRl5JbFIyPFE2
bXBIazhPMXdWbmZkc09oJXd0ODJ9CnpFcVlLezlxVDBpPDcmK1RfQWpjVUNoKmR5OVN6MiElXnlg
ZWl5OU9iS3FJPXNqRWEqPF5IMmFBRi0tSjgjTUMkRwp6JmdyJnZWM15sKjY8aypIdHs5JHFLezU7
K0gyUHBOP1RKbnl7dVNkMz5DLVk7S1UhTVRHc1F0VEMyPHl9RGIraCgKejdxTi1MeWRJVSE4Nlo2
YVRlaSYjeTY/NXJIamI4IyFBQ3F9MyMze1N3OERwKUFCZkE8aCo2VW5VRDVBIz9pa3R3CnpUb1Nu
QHglU19qeGx0PTB0XyEjTUVwUX45SzMoYXUjeFBRREYzNTtIOEMpY0txO1Y9Q19saj5qaGtsT3ZR
QGhXYQp6WVp7MTI9KmQ9MHcxRERJJWp2KyQkYypjNShIS0o3N1BrfDcmN0txU3d7Ul9BWSNsKHRU
TVRRdTR1T1k/TG4jYTsKemUwRDd1Nz9zUDVzdipmNW81bFpuX218TEJ0MjQxY0xkUXtPaXQlMmJZ
fVhlIWlRKlcreWxTIzhyJmhGPEM7SHo3CnpIKzEodS1tVFd9bkxpZl82SWFmYmM2Vjs4cE1SMWJp
UkA+XmFQIy13R2Y0UypvI1lnS01ZU0tEQUpuUVJ0b296cgp6aiFhJE5BeTh2QSh1cEBYe2ZJI0Ak
fk9QMzg+diZAd1Z0JChyWUtPbj19d2NJN0lCaiMqdjViNz1QaHxYO302SE4KejQxV08tPW9NaU10
NSFTZmotQ15hY0FGNFljKytXKE1UbnBFdlR3YGptY0pIS3c8KDtOek9zOWZZSio7YlklRGUwCnpi
P1RlcWVDbjZMbz1Dakokfil9fllqPWhucT1takhlREdvYVctcjt7aD98UHdpciQ1bm40b0tHVCNR
QUNaZV8lJgp6Q3xnd2ZxaGMtTzF4TEVQKSlYJHlaWlpRVTR4aSk+MkY3JT9GPSE+c1lzeUpfK3Rt
aEAtVzJMbkJWJHImTF8oUzsKejxqJkJaeyQzSCpRVndmKmk4SHdIUEI5KkQrYitPM3A5JHM2KX4h
SiYrLSRzN2xUUTk7S1ghWV5tJC0xWmR5IzFxCnpUMD9KXk0yJE5YbVROaytsVDVXLS1AfjV9NDIm
P0hwfEVHZyFkdypRdStOPjtqcUNicCQmSH1RZUApTEJMeU9YdAp6TXhNQkxjQjhoTDxqNjI3T0Ji
bFVvSEZ0OUNLUShsNGZOdVlOdm59SURpRFoydUQrY3tJXyVhezwqMitgTGFKdHUKengtPEw8SHcz
b152aD5wcVJMd0dgODJ7cWRROUpIRD59UGxYe1MlWHw4RHNkUGlROX4oX3J2OztIPlZIV0I5PX1s
CnpDZj1vPF4tbkNadUdxLUJQKTVoK3d9fTRTKXpuKlRBfV9BZEkpcU5RUnxLUV5uanxlRmdgZj8y
UTNUJWdwPDNDagp6X19PXjdLUSR9WXBPJVkqeyQwKDxQT2J5aDQ7MWtLI2tOP2J5fExZWnRfJjIq
d1YwV2FCNUpeNEhDbzh2TGRAKXMKejc0Mj9RYSZQZ2pFP1loVlMzT3M4NTx5c0EpRj0oUyhiNDZV
PnkoXml7T0o1K3ZKSC1KZG4zT082OWJWVjFpJkdiCnpBTSNnMVVwLXQlTEQjKTlqQ0FtYV4lMkFV
K2teQDl6ZXdhaGhSSGw4VDk7aDRTV1p3b3F0bHNrZGckP0BgYiF1Mgp6VDBYY010QCl6PWx5IzZg
e0FMe3hAWUNOP3g4d2l9an0jYj1sej4qVFYpWnpec2lTZkUtUCM3blJASGNCTEp9QU8Kekk/YjFm
KnsyQ3s/UWdoPXdmM3dePFp1SzxkayU+MHMoe3RKQCVgdmFHYGx+aXF+VVJZWV9EPGBWKEVxRHN8
b0xaCnpoKzZTIT05aVI4UGRVOCtIOXNQNlYqZiFscnIhO0Y8RzU1WG9ZITx1c28tQXBjLVZ3Rztq
OXU9QlhYaWQzOyYlfQp6JmJuMjU0fXtzRmE9KDlsYFl1a3NOSH1uYW5+VWU7YCt+ZDljUmAhLVVD
Nz58aFQ3bHo1ck1xKTR0UGFAMnhWISEKekpuZCFPbVdsWX4+KVkpQkFGNDFWTmdNRXw8YHZ2Z25i
ZFdJaio8eD0yI1p9am5TLUomaDQxP31XIUkhIyFxPEFVCnpQPGJvdWwoYXFiQW55czBjJkpnRHtv
VkZrYyZJNj9AbFU+WighYFRrU2Zse0J1YmJOQT14NXVmSHMxJkxFXkJ3cwp6RzxIMVBxT2ZRY2Bv
TigwVihKZT5aYUR3cGEpWjFuTU1BR1dxYUJsUiQ9MiRoIXh4V01ITGE5MTRMZyYkbnJNbCUKenVF
O00tWUxVM3tVb3ltOGB2dDtzUlBoM3JxdXgyTTVNOSNyTGU9blVPTklOUGsleSpMe1oqd0AlJGxQ
SUdtOSZSCnp7VjhPcGR8TWpjTkQwMDYkWkIjQk8hYms4VEJ3RnNyNDJrWUxFc2spMyFJNmAkcGZy
fD5peSlpKEhUYDs5MGNuewp6QmJNdiY5LUVfPmErNm51O2FeSktefjRqeTw4PlVhdHcmYmdNaDk/
eylqTXhkSXlXZyNMejt2TllxNEchPFNkWUIKekNnfXRnVFVJLWE8IzIqQGUoe0Q9bTh4VC16ZkNW
V0l8NDsoTzhUfEB6djxRUmBUY0lAV0BkZldNIWExMFVvM1FOCnpNRT0wYDtvPW54R3h4M1NpTER3
ZTJneDhPNUFxKXZhJEEhcmJ8TDhAMnJmbyQ+JlRmOCNILTReNHk8RTFtU0o4aQp6TTUhMGUhc0V9
TE9MdkVFSkpWdjIoZ2UpdSE8IyQzeiltPTJQS3BmfXprYj9xN2QxTChOSio9fUx7OTJlb3ZRR3QK
em5yN1R9TUo5K3FuYWF2SytvZn1nNjY5Tm1LeEFndTdhd08pUmJxWVRzP1lZRTMqPVZEaSN9VDNV
N35tYSNsM1FHCno7PjVTTiM5RW5iPGltWUMwdEYzfiVsUHxAbHZZNjNfIUNwSkp4SjghYkpjZ0tQ
MzBSfXUkd0A7SEU8VD9xcSpXdwp6JmlaaCopOG4qaXhTRWBUP0A7XnFYTkNDME07X2E3NktyWjZp
eUN+N1psTmIlQlIjIXRyRjJaI3FTOXQ3UkF8c04KejRfI2VPRT5OXlIrc1NvaTk3JXBkV0hLSVZi
c313JVRYflJ1WWp0KSpDTUNLPl9IKDs0ND9kPlNKe1Y7b2B7UTI0CnojYjc3VmBVWUVNQVBJSkg9
SDgmKl8hYkJjZjl3LV5AXm1HZnsxKnd2V3xzTlF0SVdraDZILSZxZ3pSYTxyQ2hAfQp6P0NNdlE+
Myk1cU40Xmo5SkVDeCg4c041IVpUPSlAaHZjMilqWi00Um85Uml5YHglLWl2djZGdFUhe0olJGop
cG8KenNuMnwxSDV6RjdQUj19YG1DRHI7Z3dvR0pPezJ0P0VNQn44QT17KDBnc0M+fT1eOE5VeEB4
KlUtWjhLeXN6cSQzCnpZbE9mNnVaK2hTcXFKZj9pWE5TNGA1LUo5c3UheHJZUVdVMEB9dGh9Vl47
Y3cjaDFvSiUjWVluOFUoNUdeMSlKZwp6JTtSO01Ackl1fE0yJEhUR3swSlhzPHlGKlgwYjRNaXta
MkJjZW1VbUN8MGlsVTkpdztxKEdmbyR9eD80Klg4c1MKenIyJmI/eXgtPFRVdXUlRj0qb0ZIRjcq
Q2RmQmR3Rl5UcEApemUmcUU4MWliJlRDcDtYMX07Zl5MPXNnayZ7VWVBCnppWDVPKTl6dkdBRVFr
dml7ZkZ9QlQqaX1CTl4mfkMrSnNqUF5OTCMyTlM/O090ZkVzMys4OWp5cEk9fT8qdFpGYgp6S0NU
KXJzVCF7aUtYO309WmxRN2c0RDV1eD9xSWR2ZEM+OT1kSzE+Z3VJZiRmNG5nKVBeaS1sRkcqYE11
UT14fWsKejBXdDlERl5hO0I7cTVlTVNsVXV0PHJaKiVJUUEjYlFJblIzaDxAZ3tfTllgZUg3YURy
SlYrUSZzS2lKN3UyWjxaCnoxYE9MP0xgRTJ0aCNPcWNObXd8VCQlJSsqbS1XVzNXbzMwU1N7JUd1
OypVaV4hYEI5RE1HaH1uKXZFKDxfKT11Kgp6bHN8ak5acGAxaURFSmJKNmZnQHAlX0xAcyZPJlh1
VTlxZFpNaFdIO2BJa3FGMyZjU0ZmMWBJfEx2QihsdXhgcWwKendPaypGZ15LO0R1TFBGa1Z8R3lo
UWFEa1pqNXc1NW9LVSYhd0BZSnZhbTlCVXlaPTNnY0VgUTQhQE4/IS1MXnYjCno7MktqfipTe1N1
SDs3RHB8SXZacXgwT3d5bHo5QGgjKmJod2s0JHRpYG8wM25wPjRfYD13fnFIQ3A4QSYydEJmUgp6
eWZUWn49bm08S1UoPjxWQ0ZuSlJ7TXVwN2I/czMkMT1KKkI3OCF5NmFzIzE+QXEwfFhOJjFnOzZ3
RDdkRjRrWnUKemxBQWskMm5ZQ24he3ktR3NQTEpPcCp2e2QzRHhyQlcpKkBucko7LSMyflM9bEww
WFgmR2cpYjhXfWEwSnlOWSFnCnpnMnh1YndLeVVDMS02IWQqXjYxWkphSD1BV3NlcmcwMHdyXyQ+
RHN9N3ppSnlAQDFDbWlBUkomazdsZkJNX01Bewp6MT8/eGU/TFV2YTh3O099bCExd2Nie2VTOG5K
JkolY1pBQyVCeDc4PHp4Xik8dHd7ND9JdDNHYXhpVWl6UmMlLUsKeiZQLWh8X1B5WG4xZ0klNXFt
XzBGZVkxeHVxYiV+d3FHI0h4WH59Ml43al5gdGd7eiVJMT8/X0JEPDtPTFV7UGhSCnp1aGYofnlA
OHFSYGh3a0NeODFmRTNFQDR8e3wyLT82Q2s1VUpqdjc1Iz0/REFHb1U2fnU5TmImUm53IUw1dUJ9
KQp6YyQqOE1SdXZQSj03bih7UGhSRWtyMUY8JEV4RGUxZmwhOy1UcHhmIyp1WWB0VE1VNG5qazJY
diQoKkgrM3tsd0gKeiUhKj52IT1hMXUhKiVoJXBJNCpkRyhoNCgkaG9VZihDc183TEdLQXNySzx9
djsmM1R8cTQlNU5VZD1LI21kP3g0CnpoY0RPKEVuVTRBWXFASGV6Y3hAWF4wWilWSnZ5JWBDT29F
X0ZWVGRiaDtxc1plSnYpakgkRT0qTGReakNIXmJyNQp6N0J5KHtrPWQ5JVlMP2NGK0w1cEhRUUA1
OHZvfmshR04zVEdUemJAJnFpPTlXPCsrWFNWLU44UyZrTisrQUhnST4KelVTPV9KUlUkWDg2OTxf
SnNBODZpa051Mi1OP3VJSClsbj9lPTl1X3EtTjFuZHVYN3JZTF40MEdWdW8yNmIwbiooCno8aUt1
PEdxezMjSHp9VyRPTT5Faj98eGhEMUNyM2hndHZSM0lYUSMxJFJSSGtnN3QzXmgwc2tHOFhOQGZg
Nj5wJgp6Y1N0TUlOWkpPRV99YHptRSZURyY5PDVSe1FiRyFuKFZVMFdJbn5MRmRLNnpqMmMpZ0pJ
Pz13ej53YUJ6emYkM2UKeklhRGNVTEBxIWYpUEAjPk9pWllpUSt+Xmp2OEBZXnBDKilSIV44PFNj
OCNJSGFAdykhPndzZHR5elhQZ2gkcXhzCnpeZHhYOW0+fVVONE1yQksyfT13Vy1GUElwWjRJV2U2
KFUqRW5aR35VbnAtaTBxd3lyN3Q2cT9sJjFMaUozKXEhLQp6NjA9PkM1MDAmSyUyUiNsbllxa3BF
TD1tQzZFKiNRP1FldVZeTUdNdiVFSFdqRSlsMlo4bVE7I2lSNFNhXkltXy0KekRJOHAhNjRaezJS
dnQ1KGwzejdtOSR6YjMhPmBYRHZKenhwOEFMR2BgUDRgRHNaVWdsVWdtY353dEsjc0ZqMVRRCnp3
d2UtMlJmdCs1NVNFd1BwWFFld0FjayZhN2cqRDU2O19CMD1OanxUSDVwM0JuUUpuZVc7JT9hZGRq
bjZANWA8Ygp6a3xpfDskMUFiNEIkSmJlPilyOSh2QDh+cDRTPX40cGtNYkBaayZqUlF+Mn1FNz05
dEZeOFVQZXRNKnFNdWZaPmsKel40OH1UZyEpQXpfTnU4OWU+akl7RVYqeXRpVHlrakdjZ2tzckFU
WjRWKmkjdSU8PUVfdzVlZmRUQiFeI1YmJF43CnpWT21hOyh6V1Q5aHUjKXxqQGptZnBEQ0VeYlZC
VzFIM097QClwcXRqYEZ3PmwyO3U3S2p3RTJRPVBiS0lPc3NfYwp6Q3ZBeTFKS1poUFUxMyZAQTta
WiUhezEzN15eMy14RSpsa0QlQVFSQXMyKjBNQz5nWGY+Tyg1T0woNF9UNTxFfnUKekg+dzFxdjIl
YiZnRjUoRGZwdVgrU0NCLUY5MU4ydUpQaWplWmlDVjAmeTFOQXpOcyomQiR5WG9USHpDfDMrZD1Q
CnohVEJ1N2ZaJVdNS1R9UDBJd0V+dFFgOXFaZmcoPjJkYTI7fD42IUdDZylpYzVrKipSKjlFc05Y
OGU/OTdFVUJQcgp6d1N3d28qZjZzZ0A5clklOV58XmNgbC0tVDtQVFl6MnNwWUYpeXstJSRAfGdD
JCM2I3lRR1F1N21VOWJWUWcoT2AKemJyTU5SNT9gKjwqJGkqSFhibCF3bT1rNzYxPTJGbyVBamZt
ZmNAaWdeKlIqN2lFcWc0VjN9bCFhX09gRyE2TiZSCno1PyNPRGM1ODRqMDRRT2JKOGk2MC1uXmdU
ejtEZitLRW9AYTFUQ3pMdkV0c2tiVEUweTgwUmNJdDJ5Tjxpd2Y2TAp6anRJd0I2TTNvXlg+d2Zo
VkBDfmhyYUhlR3FhKH1IV3RHXjZWMn16SjYocDdNKXtFVXN5QFUkfmZIQ3wydGpeOGUKentOeUxX
PylyVWxIT0FDJFM5eEB2ey04bmhnRnkwdkVpbGJyVGkyQ3JjMj47VW1fQVZ8aXtlY3pyektSLWdG
ZXc1Cnoodz43ZkxqWG9gX3JYSmJmaX10RGc2ayY1RSsmbEZiLWxNcSZRNzI7dWNyIUdnNHZeY182
TDw2aHdUMz0mcGJyNgp6eWFxaFlzK3FWU3FfQTtoRFFNfEBFNTFeS21ialBwUF5TP0x2QXYpRDcr
VURrWDhNdzgzJkJkMTE7bUktVnlGRUwKensqSEV6Ky11ZzBVSH5vVTM8d1gwSH00S2NLKVhQT3tj
TUA9QnRiQDU9VWxuN2A9JEs3PDBuVkJgP2RsbyZJV1RjCnppfDR6dmwkeWp7SiV4VlRgfEJHZDV9
MSVKTnF0dDUpeE4oQCp5eU5WbX49ZkYxU040V0dGLUBPQVd9aVYoRmhjOwp6Um5gdj0xZHlDb0d5
TWlFNk1iJktFbExkcDltS0JsSFRiUExxaElAYzwpVzc2UHFhUiZySVgrc09qMU5WUnE2eDcKeiNx
TGlDdkEzS2lUK314LSZCXnZ9PmNXWlVFSmNRZytjfEooYkZ7dElVZUpkMW9hVGxRUGI3eVF4PSN3
ZHpobndICnpjTiltUCtKbTlSJFRpQUxiJClZWTZrP1p+Wnd0a3JAODIqTmskNz8hbCRxTjBaK1NZ
Rz1qVlNrJXBVK21iTShVLQp6YmViOShUJGhoKns4Z0UoZ14mWCV3QmFSajRYaFJfZ2w7Qm1hKChh
Unt3fX5uJVpELTAodnBYJlUmbz17QTh3XnUKeldqWDdoZWpMZVZaai10QkVXZnwwJVBUN2A2SGg5
NkxwKUpgQ1E5IWNgUEQ/dT5OJUstPmB4aFBCdkx7TVlHSllDCnpQbWRmWCtIYU9AYT5YZThAaSh1
PWE5UGJfQj85Klg7XislT1kjcn1sTTMrQXxQeEFPMFZraGwmVH5xN3BMM1FHJgp6bXIodGs3b01B
NUA2b3IoeXxHYSlXc2EhQXZUciFva2dKZkIlPnx4RTF6enFKazVATk49PGdLKjslby03YCQ/Un0K
eiRgVzxuYzd3dEtVc2AhQEt2T0ZaU1ZEIT5Ocyo+a2t1MmhDWWlxe3d3NVhUUjtRITxwPCtra0l0
dypacU9fXj9oCnpHN3x5Q0ZeNkNscndOa09DY0UjNWJ1UT5LS1RLU3dRb0NZKSpAeTdiQ3pjJTVX
biMlbCs8OExjQVp6bU5kY3FWRQp6Q204IStjcWchUUEoUkNvI1dAbEB0RG44X3pmVjd5bC0pfCZw
eEx9NDw0ZDMrbGRCZW1HJU41c2BrV1JpbXVeaXYKemUtc1UpUz5BO2dEKjkyP3luVCV8bU1LdDhV
RkJOdzN0SUd5OFpKMjA/aEI+SCptS3x8U3hZQTcxPyFJUnFZfUwtCno2MUB2WSpYdipQXzRqVkxU
Jjg0WTlmdmMjVkRkQGNvdmI9MUMjVV9fbn45Znk5TiU3K1klR0M/YEpmT1FFYFZJRQp6STtINlFZ
cn1pMS1PaiRsd3FUPCYoQHFGWG9RPCRYY3NORkljWkltYFQtLSgxZCo/fSM3RVlsfUVqaE9XeDNq
dWgKemljWi0qQT9XRz08VDYlVUxARV4+ZXEkNWlEPl5HI3p7V00yIW5TaHpveH1mcEVsbGZAaGdj
el8qJlc8QEpNKmNqCnpZZD1HYERffHNIQW1BdilkXyNWOUMqMj9gSlomSX5AV0Q3Pit5VjRaUiRq
RnsyeV8yVGYmVGYrY3VCST5gSSQ1NQp6OzNVeE4xUWNqOW5JbzF6QDVjPTQ4aytxWj9qSE1lYjE9
bHd3UWNTRXgtWmI+YCQ+MzsrX2hkVDhGbyR6eVY7Py0KejwyPjdZJjM4ZmY8Pmg3Q0twP2lAIUFD
U0tPel99V05sOTF+dmAyPm0rOT5rP3A7fTlqcHdxbjlqe0Y+LTJKVSROCnpRWFIwLUB2IXpIQGI+
bSo1c2wqPzEwSGYwNm0rT09LMDRBUXRteFE7bFlrdD5MRmkrNTJKd04pKy1JTX5nanBvTgp6bjsl
d25KfDkxPDExQUdPdmtNIzVfNDheJF9ZUUY2bFItKnlNLX1kXkJfI147Um1Md0hmeks1MGtmUHRA
ZUVkJTsKej19RTtqcVBrJHotdExiMzQyTy1VJSNHSzVYWVkma0xgey0lalpVQGg5VSo5UWZYKTc3
dTQmaDFGeHZWe0E/VXFGCnpxSlIyZDZoJCF1RkpicTlXKERYbjFvWk5wdFpVLWdtcTdRKWl6VWdG
OGsoRjBod0ledEw3KHI5VG45JEt5PjRNUwp6K2w3UHZfQ2poQDRwdnc3OW1YWnpXKjAhMCNSNns9
YjNeMjkrZ0ZzeEc0MiFGRVo7P1FJJmNvTXBuQGc/cDRPMDcKemNSX3dFX31ecjF2PTExRlJFezFp
KDh5SDdjJU1gQHZBLS0xaUM9azdpciQ8JEw9RTUkK0pjNnxoWX5qezhkXkkjCnp2WGZjai1uU1VV
dWlfc315d15OQUkxeEA+ayt5QndyaWx+cUtKfUpZYFIpQSY+ZXJvc2ZCO3tIM0h3VUU/Tm40VAp6
d3M3ZXpjUXFDI0tSLVd2aHhzZj5pPXAkfDI7b2U/K3ZuTnwmfU5DdD9HelgtODJyJXIoMkBGallT
Wjt0P3FtcEAKeldZU2YodCgrQnVlO2YlYVg7QzZ6cG9YI3ZeJDhZPUlBaVo0WW1TJThoMGM1THVJ
TEAyKnh1bztnO15uY1VldTdSCnphRjM0SEo+NVh0KitFcyU+Y1lhdCpHaHVRaFEyMUU4KHg3NGdZ
c1pYP1ZKNihCOzlPfThQaGVkbSZ4fU1FJkhGLQp6Q1Y+aTBNNTQ+P0U+dnEwY31YUGdKRnpQZ2Nr
QGpoUHUyeyVacjUxQ1pOZGEqUz8pMUlLQkQ4SD9qIW9mdCEtX0YKeis1WHBNNmtTKD8wPilra1lo
Qk8lTHw1dmNpYjBeVS1CbG5oJHVRd3tKSCZJcl8raHYmJmZqR3ljMEtoJjZySFJRCno0ZlBieXRF
Z0JgcFBYVzdiO0VwRldvMys5KVExaUNkbSk/bXItIWNoNGlIUH5DP3tNWU1ESl9KQU5oM3Y0dktV
MAp6bWcrKF49KE9oSGU3KW1rK29ERjFZJCUyLU5JS3VZY1p6NCEmUy1SN1I+Y2hjP0NneHk9Kzk8
VnFQb34hYE5xcS0KemNQR3pSKGhKU1o2Wkp0eSsqIXI+JiQ4VWswVmc2PXs8cVUlOHl5WXtJVl8p
d0VJTV97eDNXbU47MUhDKkY1RW9TCnpHb3MzcDZuSWJBUipxUUopO0FIQk1TV212enBJfkJkbW5z
JT4pTG83TiF3e0h1RnJXX09tbCtPcU9HIXBhY2QjVgp6ZWNmZUhaQFpoJS1UMzJxKCYhTk88QSlr
WT5ab3VlYihUQTBrJnojJWgtI1dzXn5rSWR1V1RtZmIlQzYkTG5UVGQKemBnZHMpVkckN3V7WkB+
cUlNZGhkaEs7QTApWHJPJUF9emJ1KCtacnhrUnw0bl8qVmU1QDZ5MygxLU8yYjt8fF5hCno+KyQ7
Zk0tRytgUThxZnYkJk1XK0xrMjZIQEZZa3lqMGt5eS14U20/KGtuVFpjdTI4e3I7RFNYS0ZfPihH
VypvZQp6NklsKmhhcXIkZDg3TD9XXis3ayY/MCRGcjhUNUtyNGNaZzhSQUN4PGliMSFwUSt+d3cr
RDdzKEVmYXhyNVBRaD0KemUyMyF3QGZlQlI9V0BIVjZMTiF5aCZXbExHZ3xKQDtIUTh1Klk2dExm
UWJfcDlffDB6UXJzeGNNdkVqd1J5WiMmCnpYXj09MjgkUSVya3cyNG87czduUHdZOE56TCFrTn5z
S0heZj4hZEZDP1IxfEt4b2tmNi0jTCtkQkN6aGhIfWVkVQp6R2JMYVFLIzJAbnotYSQrMEQ+R21I
TFpFQWxzVD5Wc1dZWHIzPyt7aVN3bVl0bCprbTtUKik1dlBMXmVkIUQhaHgKejRUdzFiKDxFclpU
OUtfPnRAIVgjQW5aYE1DOyFlUzRNczs2e09kX0ohXllpK1FJMFBFbit3U0sjV35jPSVLQzg1Cnpu
fSUwRkY+MXNPdThIT2cyez1acSpNWE9rdGtsNSpwRlpFNilPQj1wbkImVnFufTNYfUdoM2NwI2J5
PWhFJE5WOQp6MzRpMXApPjxqbWU7djt0KEhROzg8NFFJfU9VSnhweVBMRDBiVH5BX0R5PX4rVGBT
MFdvIzhKUFomT0I7WTRyZ28Kei1YbndhMEtROUwreWFtfEVqWnt7b0V2Nj8keFV5NSUwVVYzZyNR
MUE9dm5tRmNSbHtVITRLI3cyR0NZKmZSZGI9CktZP1pXR0BjI2tiY2BCUiQKCmxpdGVyYWwgMApI
Y21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9sb2dvLnBuZyBi
L2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9sb2dvLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi41NThjMTBkOTg0YzBh
OGJlODU4NGMwODQ5OWNmYjBlMDU3ZDZmYWU2CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCA5NTYx
CnpjbWVIdF9nQi13di1Tck8zbkhrMShrKn1wTlJ7M2RERkc9YDFxN3JEZ2tDak4zJmxjPDZpdyg1
ZEkwR3A2Y3QxUwp6PX1vJEhMS1AkKzNGVTc1LWhiZiFhXkxmd2I4YC03IT43IzdKflEqbz59KzE/
PnVReyhXdXR7ND1xeWIwdF5vdjUKelllRW99JUJkNkpOYCZDVWJURkx1KUhMJmZBb155P0FKc1JI
ZTB5K18pbVFDLXVjMyNkWi05LXIwfjhQdEFuZmM4CnpfcCE2X2JQKUZOZXZEcE1WMXVBNTViVy00
cWJEaEE2T1cmODVGMlZYSCFpTX5BVmpKaXdBYXIqNml4bGY7YClpfAp6eCE1YEx1eWF+aGMmTCE/
N343dThUcz5YRGFmJnhRPyZZfSlxQyNQeFVwaylSKz5POHNlYipeUjhKb0pURDJPT3IKemxya1Nk
I3coMFlrcEh5eXQqQEA/YkAtVyRyK3FtM3NnUCFgM04oWUQ1aUhsZ0BkV0wkKTA4andqJGZiKj9A
I2VpCnoyR1IzaWclSUBVU3shQmdib1VBczd7WHF1OUhhY3BgME99a3hjK31IUWVnTz5mRm54Knth
cEhtM2x8YmxEYTk9PAp6Y2szPVpecD5JRG16R3gqIW1oYyVKJmZUTl8mYj8jNG5EYEFuS0o8OUJ+
eVpQMGhAdVNYODdJPC1fPGhQWGtuSXwKeil3bE9CUGNBdDhyN292WUhNbnZtXmghUUdja3p6Q0tJ
ZTN0WXNxbjBNZDNZSDE3bnxUbXo4Q3NpaCRCVzd4P3p+Cnp0JEFefT1IPCgwcD5yPlFlTzEhNj8l
Zi1oYCM5QDZCeGRObHdkQlF5akt8RExIVDh7QUZGUUY2cCEoS0VqVCNLdAp6M3lVaFQmWlMhQkQ1
RGtsaWh0PG8pMkZxeGImUmUydDUzfCZJWTAxXnNqZyEqLWROR15JZCVES0l2c1M1IUlldS0KentP
SV5lPTxnaWB1R29jQyYoe2xTb2B1KD1JU1ImaUdGJGBNPVpneVpYT0tkcWRfO3s+M0FQOC0lMH19
Z19fRXxfCnpEZzNkUDNzNDViSVpZXngra2J5YTN9Pj8taX1ELWFZPEU2OyFeak4jSkkmbSE1Wm1f
JFUlbVZ4NjxzK3o+YHJfUwp6TEU5YDhiZVBlZHh1eG1leFc/ZjFodGNncWFVVE8/cFdfN3YjfE1m
LTZSXllrb2IxTGtaazMzODVFT0hZXjd3Z2wKejR0czhRLWBYWHM7O1hPJStRZTBwe0NjZlVQRUpJ
WVlpZFolKD9tOUVySmBAZ3A8aWNnOyFpLUlZPVlnRXptdWpxCnpPOFBRPitAejY4WTtTczhWWk5f
KTtOTVRIWGhrWThlP2U4R2FVOUNmXkVgZVU+Y1AmdXl7U2tkcUo2aktXfD5CLQp6Ulg9bWk4O0JO
NT88TnFzMX4yRGxiOzV+Skt4dXZ1R0NnWH5DcmFlSVdLMyU7eX44aW1WYDwlZzdKQjBLOTQ0PCUK
emR8Yjl7dXg9UHpLMkhUTFR9clYlM0NYbEF5PihTUT5mQ1Z0YCV7ZHpXVU5yZEEpMm5hJDQ2ZGpD
OS1KSmtVZylUCnozYk9yJmd6dn5wZSNHRDB1e2tNTStNdSNLPktjKXcmIzVNPU5VOEBGdF9fMjtS
OFk/YnV6YzdCUEYrUVhNTyNhYAp6amNlaWxyVUdSU2tAaGRFc3RUOzh7PzFLfWoqZFR+WHZ4NzBz
R3owSkhgJF56WHczcDhIPip1c0pYUHJWdzJEV3kKelhyPDhpWXZkV0BaXyFwJWtrP0M8Vl9gQiQ+
RjxqfXQ7dj9ydk5vdD05bT5ZRkJgez4+WmpuRD5SUFBYKjFQIXhPCnp7bH1CTjNUMWRMT0R6TT81
JS1rVDR8KERDNT49WXcrY1JCNHFeQCFgK0x6NUh2OFNMPF9jZzlpc2NeNipDS2MzcAp6e0IwRUhk
d2MpVUNMOE9kMmBwa1Z8My1nSnZhbXRWbF42KXh7TyhRIWJkKzZtTU5DYl5JXjxuPjN9QGJfYT0l
b3MKek4/USsleVpQMzJ1ajViQG9VKTJ8aURZZSZGMSkmYFVSdiZfKk04IXRkTCo1aj52Jk96QHt7
bUQ0eGshVy1jS3IoCno2aXJfbDt3c15mZ2NRSCFHdipjZk9aTkdAUlYoY2Jta1JsUlJVcXl7JmBw
WTdEU3ppSEtnZUJ1OVFRQFk0Y1VBQgp6eVolcDZVLURMZlFTVSsoTElId0s5TX1DdzlWWCpCVF8l
UEAlISFIOXNmelBfa0YjTVIlYE8tdDhuUypZWiRjMUAKekNAP35sU0Y+UzFAemJqY2Rgb1hUUFQ7
YCV6XyNjY0hTfGQzWTgtU1dxSz1iWkY9VFg0JWotR15sZzRNeTJTLSZpCnolSHUxaXBzPzxMd31U
JiNaPSZBRWB7Ozlna0stRF9YfGJjMWlANnd9RnNldmszPk0/fTM1NkVsXmowb3RGdVFlPAp6KT5A
Zk9Wb3lTISFUXjEleWRARFVLV0tVTEVQYXdlKG9Jdz9hOTRSWmFZTjhHITA9YTJxfjVaQip+T31H
Q3B8V3MKejcjJkQ3UzFiNG1KV0pGUVdQeCpidUVAajFfbERiaEdVOVpFIXwwQms7NH1hSVRJJnkx
YVJXeTJhPEMzNWp8UXUkCnppaXYrfj80aGh0WXpwbGVsbmthKXRhUWVGSXFAd1BmQEdNMF91SUN5
KGxrcigtWVY3UmtvKzVyenxeO2xQRDQ9Qwp6Rl5hTGBKZmM2MF4yWDRxQkRAdyZfUCQoJk1eWnlx
WGFPJnI8RUZqdlBFeWUkVStKPWpJTmJxIV9+TzQ/VEt7ZX0KeiVESlgrTmNwfFdFPkY2U2I8ZU1V
QV9xWlApRjlsJldAZlUpRU4zKjQ3Z3MwU2B6QXM3b3VnZCtfNERuK1h1WGMxCnojbzBEZHk1SSpF
SFV3Nyl5MzB0Pj9OaUY8V0BpNEYoSEIoTSFvX1ZNMmwxTU1zO0J2Nm9Vaio8cz0xWioqSlZFLQp6
PU5PUTRVJTItfU0hfDxZRm9GMkMqQlkxaDwyTUBQWiFTU3U/M0ExOUV2dmBzK3tsTT0lQSNPQj1F
RCEqMWxQP3IKeiN8cCRUPSttWCF6I0l3a0xYWFJHTzF5WlFePG1vQ2lQPT1wSVg/PCstaS1ZfCte
ejg8T2Fvfjw3dkpPbzBDMUY1CnomYTNDPDFpYSNnM0Fpfk1NNGhwUDBRQ1dkdikqXkM+KVk1Q1VL
ODRFJGdVZGM4diNoRjEwP1Qkb2FRSFp8Nzd4ZAp6d1NmcjVTMlk5UztTfU12K3tqemtUSTIyV2Qw
RVE1Qj4rcXBEN3hQS3cpVG9lQmpSZStpVCRMbTZPZjdvI1UpPHoKeiUzdDc3dnprRzNnRjt9Tj4p
JiVEZ3R5PjE5JX50PUhCU0s5UmYrfT1VZjtURSVrZj13dTNZfFI+UkJrdmlRO1FhCnorVTB5VjNe
LXV3aS1aNk8lMj1lIz9HZ3wwJmFzY3xBTUZLTi11YjhIa2lJQipfdHo7PGQxeVFiTlolTmBATFNf
OAp6SD5fUkwoP1coN2ZfZyMwTEFna0dfYnFwYHM4TEZTJVJnSWp8Q2B3Mk11c0xaM1J+S0gwZXEo
O0FxWiYxe19scEgKek1xbXFZeXItK1clKGRAfElZNG1hdDVURjJuO2M+aWlgbWlXWl9BTW8xT2F6
dG5TJChCfEhgTSM1P3t7R1k5ZD9uCno/OUY3WTk/cztiTHM5TSYxO3MqVGE8OzBJcVAqLWBCNlBw
RSlwKnl9K0NOWilLIVR2ZVZ0Wm4+UX5eR21FdkNFOAp6QE9nQzhHOVlkSzVjbn5iZ3QwbTc4dnFt
Pz9ednB3UkFUPXN1b2l7KnYmTHM0bVpROVFabFFFTElxY1dNeWpyQEwKemZkYSZUVyoyMEcmb00q
LTw2SUB3cmBWWHB2TTRXY0xzMUJkN0loJUU3b202NS0qVTQ/d0RSUF5nUz5PVThuI0IzCnplWkJ6
bGA1TlZJc3lGTmMrXnhOaCU1PEZfQkdzT196clF9cDdqcHM1S2wkJmokNiEoYnlNfW05VTdlYkRJ
bSl1aAp6ZHJPY1J2T059eHJkRloqYE9+MVpiMjAqYCNvRiRUbGF6Oy1nKV9FRjtYOEFhSlU9YXFL
flFpUUI/M05YSTA4JloKemtCQncyZH1SP1QlSFJFSnVAdzBsNiMzYFI2eEltWnZ6KHU4aV82QEV2
QzVfTEhqel4tcksoPTRuIzJOM3hXTzcpCnpxUyErNU83OGk8ZjVAZUpJRVNfO1p9USRNcytISlJj
X1RRWDdDTH5BWkpYVVpkZUQtQzY/dldTdjlyNFJHcTZWYgp6JGo7b2JeVkpBQ05hWnJjREk8YWc5
JCpxWEMjRCEtNSEqKSpJYExAVTAmPEkzOGVRVmEoUEEhWXMzKCU1azY1VmkKeilQTmZZdEdMbWU/
b2MkMS1PViZ7NT1RPV4lVVEzcl5IMipMV3YoQmclWXYxNDc9Qnhod2IpJHRHcCtlUS1gUV5GCnpe
c1hpM2EzcXFAU2M8NGB8M3BSUE9zeVlRaj4oQWcpVmNha0RFaHUkeX0yS0p3LXcpU0dfJCktZW9G
PDNnO1ZnXgp6d289N1JtSn1gUm5EYUVwPjF1V00+ZEBFO3JBZCUtPFI3eEZ6KVc5dCEtK1NidW4/
N2hKaU9OPj4yajZebkElSmkKej1nYEJGaWJUTilEWk1RPTcweT1YblVpaD4pZChnP01WYURaPmMq
dDg/V0h1SzNFJnAwez57MThYVkhaPl5UdE1QCnp2UmxtZlVzTWgqOFhMQkd7RjhoS05Ud3JPNDRT
eVAhWUxyZi1rZ2AyQWtGP31PcV9jfSppaWtEXmQ2ZzghWHhCMQp6XiZkcWpLfXZVcSNiJnxeWEVn
YXBLWXFzUFhxYmBsKjdtUDUjKUw8KyEqX1Y+Q1koYDska0kjZjBzUXU1NjRYJE8KemN3fDM7XmxB
fDc5WX1oSEghPnk7TztYPjlAY3toRExwX2c3aytoYURMYEB4UGFELW19ZU8kNGlgMEgoI0tVYH5j
CnptRjl9e1ApMGY+amh4aHl0OGRyd2d4bEp4eDUmYEtye1hkOSpOcmdwN2I8SFZNQjtnekhTWnV4
K0hWWXY/cHpQPAp6dnd7PDRLejY1aXAzS0t1aGYtYjVFfFheK2pBQWkjZjQxP2JWWFNOZlNwVWdN
UklPNX4+cXxqM1ElOXlFZnVFVCkKemxpdU1sNVYmVmpUPElhTkZQRz5FTm8oNGJuMSV2aXl6YSpT
OXxIOyMlQzBDUnJ8ejQpPlEpfVQrPiMkUk96aGY5CnpBRn5HdElLOU1qb3JYTFVEMEhBdnBQQXU0
Kj81bithbWFuUHQqNmx3bTZVPit4fEV2bntOPiNAY31mVVpxXkA0cQp6YTV5Mns8QDhDKENhKn1q
d3tlNFpSOFkoe150WDNFV1R+TlprNiV4R040VH5Xd0VOYXhZd2RrREokSUlkeFQzZzEKek9wfnRt
aChYIT1JOVpXSXFyTE87ZDZAPkwqdEx3bTltR0lhKStzYVIwU3JtMW8zR2VydzNla31ifE1XUU01
TDhZCnpWS21ePzBfUkBqcF8lS0RlbFVfSz00WXpRREg3NEJwTUg9ZypkJiQpRHVWendkKUBwLTcq
YldeYkVAUGNtZ1NBSgp6TXIyfGU5VG9OSyUrVF92bmAha1B3UUsmVkBlZVo/LTwzUE9HdmZVMTk1
VS1LOEEpdnRkamN3PjZ2a2V7VSlLa00Keil4Tj5LNE8qeylGeTNwcEQmJGYha1MlRjMkbjwoTGol
NVlifENJa2xxR090NFpTeiMmVzMrIWhIJUZqRzh3NHFXCnp4KEVXKT8rYyVsPkZmfHR1OypZVUMh
Yjh0WTw7OD5TfUhoYnBfNiNPc0A+dyp0XjEyUF5oMmppeSUpUjdpPnN7Twp6bX1qcG5mfj4qLUxi
MW5MLUs4LV47eDd5RDctIV8kP0I3JXhEN0hJRjRNdDVDWFYzejNYQmZ0cnIldVErYFhSSSQKelRM
YiQjKGVxa2htdmQxbjhVOHs8TnwqSUc2eXljaTw8fUxPKTMwIVdaOUxJYGF5WEA4PXp+Zz49SzJO
QyZYZT9mCno2NF8zKUVxbk4qYj9uOXE8UnRrYHhnWVlNUklfI3spOUlGOEgjbVNrRmhpb0UwUUBs
RjZlO3xJPEhoQ0NsejZSNQp6UyRjTWpZM2hwc3IjZ0NhY05gbHd1dFNrVGdHbXFqLSkoRj14ZnRa
ZVgjWCVNP3t3fn02XllxYmV7aXtHYUgpQzcKekplKTNzPGBfaDs0KURNdyZpYnk5I195dk5PP3Q5
ck1ndER8NCY4RXdeITN4THJDb3dHVVB4Nis3ay0oVjYhQWcwCnoobnRIfHhkMGM9b15XcFchX2xL
MExPSS1hQnYmTGl4Rm8jPlBDLTNxMFlJSilfOz88IzBLTTRPYnFRVl47ck5HNQp6X1c0KW1oSTM7
YSpMSkUzI2R9SCRBSz9wK2FXPiM7Mz9pQl8zVjlsSnJgX2t9NmE+Nl5vJVFiXlRANn55ejkwcHQK
ei1PTDlKRmM7RW1IazNJYW0zeDMoQVZuISZlblYzU2hUI1cjaHw8fTd7TmZrZEJCZVJneiNCS3km
bHx5SWEkLUY3Cnp1ZnA4WG1jblJOVllEVXFAPzkkTHArOS1pPk40Ul9oa1JJa3MoT1htcWVfWnxZ
N3ZvI1JQLW4pVEFAPUMzaEchQAp6QzF1NF9yTzwwcHZyYjFvKEB+anpRSUs0ViZzRllYSD5GWX43
cChEenJteDhFbGhDO2FLKFV8QmNsZyUmbiFBKVoKej1GQjxRJGBBSSo2dz49VThDeGAlKUpWNm4k
NHMqU0pPJmwzMGFRdE08S0Bsems+ISR+LTw5O1A4X0J2PWhlVUhYCnpvJHUyUE1RYTZIeG90QG5p
MSNSO1FHeHpALXxQYykmUT5nNytrZyVDeXlSaSM7byU9NkFUNnU4VXVWYkpJQy0/Pwp6cDtSSVRq
PTJkQ1luPHwkcyFaUj1MckBQUiNnKzBzZjRhOCZBUUlBbC1BN0dTY35HNmV0R2M2Z3hYYEsqYlhB
ZWYKeiVjNVZGUG8xMlh7XkNNXih1bVE/KVV2SHhAZUw/bVhoMEJ3JnZwRERIRCZ5eTAhbG5FeyRJ
bGNTUXZjJUMqMzY3CnpxTFVEJHNkXkBJYEZaS1hvQF9UYjlLSm8/bChzPCglKXd4c3lHOW41NSk1
Pyo8MzZoPEJxYkgqRTt1RzhDQW4tTwp6emFycWgqWTwpcTYtUzRjZGI5bUBSeDVhNnBgPF9RT3Rq
JCQjcU1ZQmhZT3dGRzh+QUZnTWNjVio7Y05HZzs5ODgKeiQ9cUNtYTRoK05hfTxaWXREUClsdGZB
MnpsMTl5WlI8S1gpazhzfXs+fEo2cW5qNXJOOHZGdXs/Xn41JUl3JipvCnp4O1ZLbV4pYEIhYH1t
R3ZsOEhfaHJOYyNgM1ZYM3UtRGpYQjMjbk1Ya3V0PDdDQFBAOE55NChiRD5QU1F0bU1FSwp6K1pj
M01yI007RD5EYUYkSigpQXM3Pk1yY0A1ZkQpV1BaSE9wdEshIXhiQFI2YSQ8NCglKSlafilYe3lV
ayVDTEAKemVuQEVTO3ckPz0qb1NmOW5uUUJlPD5pN3NKPnJzTlE0LWVaX1UrcD4tT2BlaGd2UDFL
eWwtNGI3T3spOTJTYTFUCnpnUnYmUXliNXh0R0ZAYWRPNEs8RWcrPz5ybl9lK3Fjajt5S0FUQmlv
QnlTQUNeM3VqPCY4VlAqN29mQmt7aUx1QAp6aitgZX1gO3ZwKSs7bjFoOWNzcGl6b3s3clN4K3kp
a1cjTVdgSCQwciY1TVNNanFVNmojS3BAY1lgIzFScDBFRVMKemQ3I30tPzhrPT1Xdmo0aFA2bHNT
MkE0bmkkbiQ7TEd2QmxBVHgjZyNVVkI/eGtEX3ZlMjdSN2s9d1V9WDEzckRGCno8UkJ2Qz9+OWAo
OT9HKzZlLXt9QTFPPCg/d1RyeGNkP2Z3YTZTfXl5ck8/PTZwVHFmJk9AK0MrPFJnRXAod2JyTgp6
YWNFbCsoQk8mcC1fcmwkM3lYQCNfU1E4YWkkaCY5eFQ5eGU7d00hRzBTQH1oV25jWlY8XyFqVk8y
aXlwQj82RCkKens7JWZYdHd4UTBCdTFNVXNkNERwVzdwS1VEfiV2bmlAMG5yXl4hakNoR2dVfEM+
SVAzUmxEIW4pUXRJITEkWlIjCnpHI29DaDs1S3RUeFZCfjIjO1hoa08tZyNLeHlWSlcoVlJzd0pD
b19TLUJxNyVyYGNTY2g3ZUJaKk9EITA1az1qbgp6cGBwUDY7Q1chKDNnb3h6cH0lVTwtKDxmS0dR
JTE5YlJCSDx2WHhwN04pTjBeP0BrRTl2fHpCSSYzO3soeGdGciEKejBAQmlZJG5BbXN5fnpDKERV
WHFCPX5LZjImQnZlPHw4fmQmIT07VnQhcFlqdFI4KlI5eVY4bVhvblh+cVdqKCliCnoqVTl+blVl
eHBiZU8zM0ImMDZeO2BzMnFBcSFeKGB6cWwjMlYmezckT0p3RGY/PXgxR0hCNXJRUiZxYDVhMVo2
Vgp6PlVyayopSDZFY28pYmlHeXlBZnpKOXVHK2pSI19SKVApTDhWcTw1PTJaemtJbylzOHRKY3VL
Z2prdXlAcmRlUXAKenM0NihneDYjUktkYn0+eCtHRV56M0RhejBGfUQ1WGptWG1Maj94fnBpdGZH
ezJJWmtJcCtePlBFYD01ayFpVHJOCnpPV05HWk8pb2ptdD9wMFd1WGVNamEjJEc+KjtqKFhMP1M+
WE4zfTMlJX1NZ0QjZk9zWTU7K3wpYnFOWGZicXxHTQp6MjleXyhOQCV4P3Y2fFBHbkkoPE8wK3M9
NShtWlNVPmNZeSg/WHVFP3NyM0JeQUl2X1dlMERnUG5WNlBaUzR4TVkKemhwazBtMHtyfkY3OUxI
UU9JQVUqKE5aMnRTdEI3cSEkKHxPZG5kVU5EbnxpRiE1V253a2pmT3ViZFNRIXdzIXpJCnpPbyR4
UXVNWWxadnBla3s/RW1fR19vY0RuZiZIWnpkMUFLd2ByRShiRnskIT9Ee0QxN1BSZWQ+Wm4qVmA2
fkRlJAp6ZTlRR2QtTlItVGtCZ2loZkZnQXV8Mn5fZk85RipXNVB4P1dSd2xgWnJOY2dyTjF3QCY1
OEtoJTh2aUxLTF9oOFMKeikoOGxpSHBIUEMoa0VJWmN6TmdGIzR0KDkkO2wwamtMT149dj9gWlUp
bGYmPGhMSH5ePCZsNkBvQylPKXEpb2skCno7Xy0wPjlXKX12dV5XWVhCWkFYKHVoRlFQTGZ7MjxS
dGNNRC1GRVNkbXYrbTNOSkRxMkN8ajdnc1NRJiV3YGd5bAp6S044KzhyOzVIMk9xKW9acjlgfill
dT8jdHJHLVZkXmR2Jm5xbjtTU3dmODV6QDtBbWJBd0U5UyFvM2tRNDAyVHoKemVLRmBSaW4pd3ol
X0RPUmIhQ21FKDQ4flJTPVA/WjF6ZSNzVWEtRjNHcXhCRSMhVFRubCVZJjFQUDQ1TFBvTUQ9Cnop
YUdrZWJmcXxLTl8/fmxjPX5qNHhhND9wXyZjeUFwdFAjUm1PRT1FU0w9VHRCYFk2PVoqOT5CUn5X
JT9od1FffAp6LTNRZGpqYGAoPiMwfnZpLUx6fTRFcmY7YmF4TTtad0VqczM/ZTBlNjhoVVZZdmdG
SXZhS3Q9QDJCaXIxWnxQc1YKenU5dWRUY2V0NmV6REgySmMrYUlfemRrNTxgIUV1Pk5tQHh2T2BN
cURkLT9MWHJPJSl3WmV+bDYyWEA5ZlNaJigjCnp1VCQpNE5RVS03NGkjWEchNDZZU2ZBcDdgT2h3
WT0/TXtwOHI5TUk3O25gVGxUcFFJJCFzU0B5T2Njcm1ZZ0oocQp6dHJPakArMT1DZmlxU3xXTTt+
Y3FZJl5LfkckNFY0bHZAPzZLI0UlNWBgUjdZRnFNdDwpWFdTKT5+P1JAO0A1ezMKemdlKXJFIyFS
WkpzYCNhKVAyYV8mPUlya1dZeThzRSglTFNYK1EkdShMJj0+cjRFV0JSZl9HS1lHM3lwSTVjUFFx
CnpOYmQ4NiVxWHVgMCZhZjZnSFV1UylPY0BpUGl9RndmPytoKm1GJXkwQFN7S1YmQUFwZFlTZXNV
USNvTXkkQWB4Kgp6cX55ak5LO2NkXkZIZkl6PitrdVF2NnZSOSViPjhJMG9XWnMhVSRhJTlSYTYw
JkM2Rm9BPTJGeiZuO1F8RDZhMzgKel9gdHg9ZH1PKFN2NUFTZjshcyQ4VHdLUTA3YmdYa205MXJF
PnM7TDJqSzhNUUNNRzhHR3RydFVhe1h0STF+VDt7CnozYSRNUUdkM3Vqen5fSlk7T0pNPlBna2pW
YH1ySGF2eEswVnZpeFFyU1UrNlVyMipadyotOFljejxUYCU7bUoyNwp6ZDNrNGlpaip6MGpuaGpB
eSYpWCprcztvVG1XVW45QjVgXnFtS1V+fGRmKlZ2ZW9JI3d6cT1TTHdHb2UhKmtublMKelNpM3R2
eld8RmN2YjR6TjYtO3REJFVTUld0KXJfb154PkFIJWlZYVduN3JKQUR5KjdoQWlUPGJfNXt8Zlg2
UU1BCnozTm9RPSp0X209Tkx6dH01YGhWO3ArJk9ybHdwYWQlPWpYQz9KVlYtQkE3Xjw4bnBqdndC
RF5LPjhBQns3KW1Dagp6LXU8dk9uKUhPZ2hna1QhPSllLWUhPj1mMDg4RShNP0pidlRqYE9abGE/
M1h+KkZ3RkhXTF48bU8hP1BAcmM2Vj4KekNOUEVsbWJNPzV6T25ueEw3Tm5tLXIlPmVlYW0taWxo
NVRkezB3bT9hS2wmV3U8UFZlWndqY0ZfQThvLTZeIz1TCnpOMyNzUEZnX2ptYF8yVzxxKFNRNCFZ
dUZaK2hpQG1mK2puMyNVSmReIWB5WGJ7Z0lBb3s8c3MmT2dFVGxvJUl8cgp6UilPVFJpRUJUKHl2
UUgmYmNURHJXUmV5dXtfdyk7V015JSNsTmR5Qj99fVc9QCtKa2hrdjBFZG9LM15VYGtuSTgKekY/
bCZfZEFCWDJSOVU7K0A+PjxtUWVPJV5Uemx9Qj4rPSVmclVDQV4+WVp2QWUjbUw3c1liJCg/Zndh
YmBDKTVnCnpLYj5mdj8qIWxGKW14OTk3dVFufWl3OCUoQTJ2RHpDaUAyTF95e1N0eTg5eUVENFdQ
fG43SGQhQUExKElWYFNfPAp6KHVsIyN3PCMrP0RuPUIpUmt7MjRVVX50ME51I2RZOFchUkhgMyg0
TEdPe3d1ZHx2PEQtVEdaSnheIUJOVGRwWXAKenVmUWdhY3cxNjg8SEYwIU9CaEtgOF9vKXQ+ZkpQ
cT9UPEZLN0QwRGpocTJ2cXNWciZPVm9Pe2Ima1ItQ08tS3V3CnptY0A+aFNyR2BWc2J0RV8/KWJl
aUBoPWd3LURraj1TcFRqXm9ldH1RemdvQ3pWb0V9PjxqU3lMK01SJGEmN3poNQp6MlhZdXBaaEB5
fkNRa3RfUn4+a1UrLXxZWW9FTSV2UzN3UWs2XlF8VDchSX51LWp4KSR2O0A+aztId0g9cjAzPTEK
elUzbzZNPXNaNjxofWJYU2xTe1gqU251YVhHfnF+YzJmPkhSYUBrK1VXKEoyI1l0OEw2VnRXXmA3
N35zdkh6Y0piCnptJX5sMW1WLUtSKEpTJnopZyFLPzw/dilEMyltfko7RjsxP0A8YGQhN3dkPTlt
WiZgcHROSEhAKH1kSy17PUpaaQp6NXNSOVF4fEhJWnpAc24+N2VqT0dfJkJtZnkzP3xLeClkenQx
S1cpYU9iUTJBaEZyKjlvRXFESWp6TCtNMEV2MCEKelhNVmh8WkV8eU0+eHJSSDEme007ZXleNk1X
PjRWZGhBRjt7OGUzeGZpPHFWMmhqPz5TTzliWE0/VkhNe0Q7Skc3Cnp1KlR8JGgoQF94VE9ySDNo
aj5CJSVheV9Jez8lSlBlPTQ3aFR5U3tvYyk0PDhmX1l3bUwqZyFTJlIzMkhie04oKQp6Vyk+OFo0
dk5iMFVCUkE+LUlkU0UyZkROMC11OD5sXjEwbWdgcT1lZSQ/JFFQak91MEshdzIxcytkPTY7QyFu
dzsKek57Zng3NUwrfnVNU1c1OVorJkhAMWs0fjxSVy1mZCtSbXs1X0Vjb0VqYnREP0Z8bHJBcHE5
REZSNnRvO3VVfTdBCnpDb2YmZjY2PU9GdVctaiYxXkBBVFlFaUdIcj04NFdgREJzP19xK1pLWm5k
YyNyLWh1OEVNO3gpYG15WXZia0dlUgp6TnNSQDRtU190cD1oLUEzPFBPI35VPVU7S01CPmpRXmhk
OCRJKElCXkFNe2N8X2QpRmdgUyRqSF53QGtra2lhQTwKekRiNEEpKHlWPiYtczt1XjB8VFZGYDdU
WWc0R1dAWnd4Ync9aipuNykzcWI0fi1YNmA4SGo9NTtYWil0cSFgaVBtCnp7T2tFYCt6fHNxTDM3
UFVSTEBpejshWTkkZ1VhYlkpZj1Pa28tKU5WSGVYWVYyNylKfVd+T1B3P35LO0xPPjQtYAp6RjdB
RVdySCNkI1E8dzltbl9yJj5lTnBiNGVWYE1hPCt8dCheb0I5VXVEdl5tVz47THUqb2VIdStfQn5q
KkUxZngKejlTWj1XeFdlI01pMFZmRChQZEBeIUtENmFCTGAjNT07KVpfe0xrLV5MRnF8SjdxTW5Y
MXU8dnw1V2hfUlBhQl4mCnojYjRKXkZjQk9vSFZEK2ZnQ0xJRF9YdmwqZisyWkF1a181T0dlWU1N
V1MjQEp4ZEYoe2tXWXVPXitaK21oNXpiZwp6MG15UkwyTXE+fko1dy04TGw/MjtjPWIkQWVLcGxM
SmszMXxaV2UqVzVXfD8ldFRwKW5td0ErTmQqfUR3IzdvdkMKejV2PnRqO1ZpbiFaYUFQKDcxa2Im
c18kJj9ZVlFNSGtxP2FZU3pqTnlQMEV0Py1LNjw1O0NWPHhgWlhJbkZ6MDVYCnpqPTs2WHZnWENh
Jjxqfk43JENQeGxkWCs1ZHUmS3UoTmxkTHI0NkdgTjVAO2Q3JHRWY3t9QGpfRDd8el5jcXdISwp6
U0AkTyk7ZThHPitAdWdsNGhkQk8+c3xpaHZuWCl4bHY1ezhRZSZIeThwQCpsN3tiZUdEZWpKQz13
T3Y0bXZ0aW8KejxGOWFfMmtZQ3ZseDdeK28lZzJFSjUjdmZfWFFaVGR2Tz9DQk1gfCNMM1d2cj1e
P28jXj5nQWRnU0UqOVF2WW1kCnp7OFpEJWZOWExIdylCVldRSERjeEs7bmorNkhQO2FHUXY5SXs3
YFo/RCU8UTwqSkBCYlVeZnhycHQ/VX5NfntraQp6XjElei0teygocHpMUV41SEtMdz4mTSt5cEM8
NG1zISE2KjhKR141WjY3V2A1KyRPMyFpOERGcGItUn0wUippQiUKejNGMElhI1E9N3lidH09PXp+
O1BlTEtxfWMwVmRrUWwxIV4tUnc+PmwhMURxbzUyK1JSbW84VWdpfF43ci05emRXCno3TTg0Z3Io
ZVRRbG9iRUMkQlZjeUk1MXg5PTs2fjZKaTZ2VEtSPyQjP2Ikdnl2KndUUWNBVG5Ob3xxKWJmcjdp
Iwp6SiRZJksyRGMoOzJJLXVRaiF3PHtNTDcpQzBMYGIheGolY3hfc3VyTGNrTml6N2hRYmZVcDd5
M2FiaXpMSFd3QmEKenRvSGA0cVpgVUsjO09CK15CYzBzZCpIPFBuSHU9NTQ5TSMoe1FqVmt7JSMz
MlAlQ0N2MShYdzdQPCN5elJAP3ImCnApOE9AKl5aITlMXjFvbUl7Q19zJXB8YWlIUmhCNn15ZWBF
JEZnNHd+QzNoWUB8MVc7VFo4ODc9CgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQg
YS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfcC5wbmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfcC5w
bmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMC4uNGRiZmRkZTc2NzQ1YjcxMWQ2NGE4YjNiMzQzNjc0YjBkZTk1MzEzNApH
SVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTg0MTQKemNtZUlhZzxJNm03ZUJneWg+QylXMCNZS1dr
fE4jR0E+RUMxY1Eqem9oe3omfnZgRSp8b3Ita1Yoald+PkVWVjRQCnphMGtEPz1SV3NPeGM1RkVB
OXM9Ml9uYkwlOyZzbFBHd1VaK1chWEVvQ35pUkBrVVIyblF0QSowdH1YPEVfeHtGcAp6RmNQP31B
YEVgcWJkbDNAaGRfdjB1VTxHRSZiYnl+QFI1aEt1N2AlUm01MjhtSCVvfU93PlBgM2xmQXE3OHk4
RDwKelhFKkRsOWJwT3hnY2MkJV4tOXd4ZDI3fT9mQ2A7KnhyZm5xUjZ8dipJNCEtNmBvJWpEQkth
YWtsfCtzP3MoemtoCnoxXjJ5VHYhPVM3VFN3TmNrKH1JcTQ8aUdDdGJfI1o2TmJBSEZVWlohQ14y
KTZsU3MkUHpAWHFsaE1zb21gcUxkYQp6X25EdDQ/JWJuM3hHM345dyEzJWhiTCQkUkp9dnxqQH1m
VjA3X2V4e2NhMFNNX1U2QyR8ME05QTFwYnIyZS1pa0EKek4/XyotQmNZbmg9PXtRcCpPcG1yYClC
OS1ldiEqKXBKbFkpR1JKPGBDYzFsYnVYQVpuNCFaZDF5OzxvKiVmWnJ+Cno0PkM8a0xMezlBe29a
ZUVifGg7aiklYiYtTW8qVW9teCYyWTIoRnxsUFVwPj5rLVlvfWd7WnMmRWw8bFYxd3tvZAp6V0J2
VTdHT29CZFNVMmpSYVkyQTRUIVNjRjYxd2JPI357QzhBcHkwfWdQQ2Rqe1RpSmUkQHRSRyZRbzJM
VFUja0QKem5gbSVLUX5tdEByYHJjQypGckw9TGA/Pn1GP1MoYlo3N1dXWXNWc197aWRkZ0t8dnxu
R3JzXz9tTiFzKnpnbVpwCnpyZFZPZDd+aGNRV1FQNERuZj01TnlnUXYzSXs3OW09VXU4V14qfHAr
RCg9LTNgYmNRZzw+fUk7dDgmM31kKHR5QQp6ITlVP3J1VStGTSkjVDtsSEEqY2NWbDMxYkVEWTBx
NEFaNHYkMjlRXiNxYDZTc0JON1BXamUrUCohSHlobytHWlEKemBQTUk3UEtVTiVBeHRYWWJHdH5H
WT59RHJpSzE0OGA0USomJi1lMyZIKzU+TzwrN1pMWFpvOClMfU92bGdeemAqCnp5NG91OVZoYlBk
cnlLS0JSb2dsSDdhVnoyKntqR1Y5ZUdyNGlhU145fDdeNjJre0tuOWQ8eS1UPTA7T0lVaHJlUwp6
Y3laQVQ5fWZvfmktWjNUQys9RkxtWU9sVmwhcXQzczFRMWBwe0A+RilLPEA4WTx0ZjNPanw3YHlh
ak17alduYkoKejl+VmF7aUNhRkZgU29aK3AwJGxydEl5YjNxfUNkNz8oZmFganM/dzJfTk43V0tQ
P1FaMyV8JW4zKU93d1QzMEtwCnptISUjbTtxfkNRKk5gcFheeyV2JmwjUShOcygkdCRJXntIJF8h
VCNXN1dpdSorYVhgPUR3eSh8Z0dFRDBFNnklSQp6VSgtbDAzbjtlODVRfSplOTBkNyRfZXNjO1hE
bjwoVFE5QkY3ayReKC0jI2ttO1pePFY3cCZVbWdjXiE2YjdmNEwKemomcmNwX31RcVRaNT59SVhY
aVlVbm8zbVVVXn1gPXQpeEZXbGp9Klh2YEc5STs/K2pPM1NyaCMpNlJDYz5PKWkjCnpsRyFoZVpy
SSZgPHpfI24mMnpyZ3EpV0hadXQlb0JoIzAyQHZuKFdGbmU4c283bDwwMlY0KCZiNHhZIUYySGVS
NQp6OVFZOG9oISRMeitzKlVFZyNEcmhDX31lQVFzcT9tVWctVD0wX3VINUZVKFdkVD19bHtSWlVn
Qnp8Qn5ndjc8PDQKekd1MmR2YkBiTClgeGxzUyZfbD5xNld9Y0ohPXF1PjghPUU4UHhObztMfll8
fCl2WXxjcjU0YFJQPWRzNyFaVnB0Cnp7eUtKK0NjMklyNHJCRUcpa3JANz5mOUdJdkMlXn5yaGxI
NGd5M3FjUTtpQzc4MExHTWM7dX5xUEk1VWszVzl5eAp6TFRafmlYRiNMRUV6JDRLYlFHYWdvPmQj
O14/Yi11PzZoWXx3VUFoQXZedEN0WjhTdn41X0x+azk0QXJOcGdeZCYKelIqZihEbDQ8TihNMDV+
c2pPTmMkeS0kcTxhU25FSTdJIXFZXyt0aTVENy1pMGd+c2hDVzNiNlRRbEJpfGRWMmRCCnpzajR7
YWJ5fVdeMn1hdzk2WGo1d0IxPz47emlwKGpDR3o5PWY/bURobDBxWXxXQD5nTUZVYFRFO0J2Tkhu
KShJWQp6aXdHazUkYGw5eFpfeHFTTXB8KWpMNFVISzVuZz5KNmIyPEFXQCQxdkxBdUBRKm4qWkZg
YzI9JWBiPS0wJk5ld2wKejxvR0k1SyVSUEJCUUAxZjR3dDtOLWpsOTdTZ3AzNWBDYn1gVj00ZFh7
cnhrZFhRayQ4enkrV0BjWGVReVYkPjdxCnptb3NKaCNnKTlQJk9RK0dsXmQpclZOU19CRGtsRVpq
KjB3XmBJJHw4PVdSPDBUVmxDP2p2Q0FTRzZEQH5xNil9fQp6UCROM3lqZkxhVyhhVi1ya1A7R0gh
amMmSz9FWWNDSWpeTWItbyQ2Sl5PS3w2K31YIVJBX2BqcS12eWlQeztIWmoKemhhMi1ac0xibSZP
Qjc1S3R2TmJETitgaiFRMmFgQkdgNzBZI0dTTV56Qk5WQWNVRk5aWmVsJDU0fik4dUUpYXZFCnpl
NHcqQW0zYTd9dmdjNUo8WDEhUVpIU2tRRE5jczJXc0hlUUdtQCFzc2c4MWF8NGZ+UVA0U2JZUWlT
dXx2alMhaAp6a0VOeT55VH5LdEpUSDg3cHNIQm9fbzVqZzxtO1ZscUAxP14wdE1SaSpQZD4lcHx0
bXdfd1k3ajlqTyVAcnFaUHAKeiE/fStZdnx0YUVtPTJkNT9HSUN3M1B2QUJIdGs4e0stJXg+d21m
dz1NdzRUWVZIbiV9K0psdXtLTCZZaWhXejk5CnpaM1A8c2ZXejZoU1hOdURvK3E9fHNyaWM5Mz83
YmBjO2V+NjxrV3RTWmpRd2RHXjs8Wip8VnkoZHJwOTBDWmJVQAp6ISlvZ2RPOzlmOF5PMjQ7SXxn
VzdSLSNjPE1BdCY3PSlqRD4tTEEzZGNMczk+RlY9ZUYzPEhAPCErJUU8UFp3SGYKejd9JVpFKWM3
M0A4ZTxSYTJrZTQjVWxObnhpTkIjUTNBdERKWEs1Xk8lX09WM0BrQ0lkMTk0UFRgRTZvNF9jK1de
CnpvaTBaSTx4fXxZUGM7e3dTT3g0RnFNND0zbTw3XkZoKVlQR1BPMkYtcSo1R00mJX5qfUFXTXJU
ZGQyY1UrbzRaSgp6dVpTOU5gcCVidktJKT49VF4xRXZOcT1gNXJna3xxeSV9QUtQRyZJaSY1VXg2
c0d4aE9YbUQlTV5GJEhIenNfQSEKej1ILWk8UmRPKklEOUJiY2l7Znh9NiZ4YFJqNi1oVG5DJGBZ
OztseyZGejsxNnpRVy1fa0pFNSV5Zkt9JVcwci15CnpIZUxFM0FpeW49JXdPSVhKSkFJQHkwNSgo
UElXe3xnSnRKZHVTMkxKVFgxRFE5QHV3bXRtKH1ESlM4T1NRcmw4Iwp6KUFFKXA5aXoxTF5oKUR8
Uzl3PSU7YExuU3ZaV1hYO1hxe1dnSD4/bV8jRUwpZm9Pd2U2SGNBfDhVe3MkRXVxWmcKenU8Ym1P
TnRMQGdEbGAqJChUJTQlby0oeUlQYSZWVnVhU1AwZUhBUyRydDZYQVJKVGk0SkNNdlNLJj9Lazk8
YSZJCnpTY090QF5le0JrRD8yUGd2bUI7RzYtUXVoO0k/IzFuZDExV3VNczIxPDdhWURCMXdDQWlj
bnNCZCsqSChfQDRYTAp6RmpmV184Y041eSZaM2JvUHkxNVllN309Skk1b2o0MW0pY1lobDdeUlZ9
QShBdlhyZks8ezhQZ2koPHpuVzJlP0AKellMRmo0cHF0MXBiSz9fPG1kITA3O3VKU25YKjx+QVgr
UDNUKyt2P3w3fUNtMD1QYDhJWkU4QTxgUlFUZlA1SWczCnpNQEpRIylFd3VwcnQ3QjtVVHtIWm1C
MVIzc0FNaktgUHlCSTZTOUhXajZ4fnNIe3ByUWk5e3VKdTdzO3Fyc2xANwp6NE59aWloPnBEMHUy
IzdZUipAQ3UjSWdwU293S1lNMXlvVUd5Xj5kVnlMezd6YTF5MV4+UyFCLV5eP3gtJiE5WnsKejBm
eHJsS3BwfH1xXmRETGtfZztyJGEzUklXUntmfGhrbCFKUzFtPFBEXnV0Y1M1cVUzMkU/K2ZaMV5B
MzwzWWtnCnpUWDQmXnpEeUZMdmtvfW8mbC1IKXU0IU4leXh5OX5JYkthK2p3O1klQlMwVUtVSHBL
UGtKc1JhNDFFTW91Y3d9bgp6WkRidHUkTlRTMXgqYk97JGJXTTVlPXVMaFF1KnIjQzY4aVdqc0U7
eHJaPH5eR0koQz9Ha0FYNHtlWFE/Yn5UdzkKejw3LVZGUm5SQiZATnJHWmRQfW88V0ZUYHpHeG5y
b2xxUEM5JG5eZ2xLcXJSNnQkTjMyLTNRe1c3bWBFVztyOShOCnokeXsoUlp8YC1zMGc/UHt4dStP
QkpqaUZkNT1pVUNufDkkcSQ2c3gzMTQrK2hFZld9Pyl2a1NBRypBaUItSWM0Ngp6YnE+N253JWJ+
bmVHNCVxMDJuKGNsKyVsN0IhcVF+YyF3cE09UUR5Uk0lc3BPUiZzUUNUWjJea2JKKDtKSmxkNG4K
ektTTypRKHM+Silra2RsbT0tck1HaE8yaHFKTH1yOXBnZVNKNyhPeDJjUX5KPSpVX09odGJtbHt4
UmZyZzxYKk01CnpmcnhBMCllWFVVKjs4O0IkIUFwajZQWGBNJCFDeDw4dilsKHRDS2pweHV7VX40
LX1Wd1FKO2BNZl8jOzNoYGRYbAp6RWZ9bXlZIW5jeUFSP3tLJkJTPVc/RHZaez9JIWxOTUlpRHRO
MFNfYUR0Tzw+c0pJYGlxOHRDZDJ0S0REZT9aZEAKeiYobDZndmZTWCg1Sn4pT2UobDRgS3pyNyU2
PEZOc1JKVmIjZTMpZTIjXm42NyNNakZ+ZkYocEowYiVEPyR6all1Cnp7cipIdjgzUE49Vl9qaTJM
bXB7fkkmNzkwaTRNZm5Kb3oySSNkPTBMPjNhTGtrdXpBfiNwTkI9KVRlTj51RlEqdAp6RU4wSyNZ
TjdaSFQhPFNgQVhpQnl7OGdJUj1JXkdnXnRMI0xLK0EybiN1KlB6WWo8NDh7PHt8M1ZRek5TcEp+
UiYKelI8JFkwU3RMM0dKVWU0fSh9LW1jWkhSYyNVMHJic2ZJfnJiJWxjWG1QdlZwZkRgaT93QyVT
Vjgwdnx3M3Qke095CnpzVSs5UjVmLSNST3tzeHEpQHpHcXc3emtBaFg/dWF3Z29xQXkjZXsrXmYr
UGQqPSlAellJX3NDX0Q7eTFtbDtCUAp6ZDR0dlQjI0BAYDMtYFMtSC1UXjNoU2NqRCEjYXFAQDh0
cUc1UEd+JntNKX5wKiYxSFFEa19YYnU7PmsyWWx7YHsKej0oMWsxRHt+IX1rVXhzMExrVXE3WW40
ZkAoPnolJnR3S0UkX2lyTFdEMU5mVXI7ZFZQZ0J0R2I4b1FgNGJYI1NRCno4KDdmUDApejtTPEth
bX5aaUdwKXd4UnFtKipMMylkbk88QU9GKXRha288SW9ldHtabSswOzc0bHtDWmp7PTkxegp6R0xV
fkQjSF9tUHdqbzV3QXlqQWYoYmNrUkkzQl5lX1Z5PTRfM3NWVnp0PT5DJjZ+MWUrTEAkYjxUfXRT
U3VmfEkKelprVkolIWFXRzUrZGJWRFNHeGU1KiUkVjI/NENyYCstZnRjXktPa3U/ITVzYXA5RTkr
T19JSVM2QD0kMTdRNCRiCnpBM0teOTtIQVRwYCkpJFdZa19kUyl+QGpRTz1zJWFjNCUzJT0wQTRR
T1ptNCFOKzIwRylMWEA2JjNVWkxYKS0mVQp6VkkkbD9yJEJfWHRNNGwkPFgmX08/eTJEbXVRRjF0
WHN0VGVHMTVEbXExKk91RkJ1QEZuelNWbGNfUjVWVmZVRWYKekM+SHRDWHRyUC1HN1JONCRaWkt6
OTRQenxwVkZFcGZ7Mnh2MlZRNVVoQmFGfHJGc3E2Ukp5X1hwa1p7YjtOVXRlCnpvQzBqbVdYckkp
VXpkQkQ5dGlDYkUrSWF1ZVEkJig9Y201OXBYKTxLMkp7SF5yVytTTSNNSStTaVIkam9fbXNMXgp6
OCRua19NTCZtMlVic0kjZyNRVmN2aS1BZUZWVm1fKShod1dKQj9VMWxZK0U3bGA+OEw1JE13e0BU
aEdwQTBibUAKekA3JiQ/NWZZO0l1fD91bnFPcEVAN0NRRXVsYzY0eld+VEI1MFNRPX0xclhaSWMp
OGpXXlVCYighfGImNlYqOClTCnoxQEd4VG1DSCh7bi12Wl45ZU9ERjhFa1pXdGBHVWl7ZiEhPXJS
KFpMKU9UVHhwbGFzSXVRRztSV3J1JXZseG9SPQp6c3ZgZFA1d3tTVXd5JE9pRzFsTDs0RzleY0Re
WWJKKXM3bFUtYllwfURMe2pvb2VoKyZ1MGNMS1RfZTVLQDJGdkEKentYaHFMYyNOYSRMO3kqcTNI
fFcpeks2ZXV4I1ZUbl9EMClTYHdeKyp3cTRIISgyODFnaV5RdjF3X1hlVThKYTlnCnpvd0NkaEF7
VT4jNUthJmhaKj9uP1dJdjBvZndFI3gyNnFZdjJwfVp7VX4zckBPR0F2RkJ3UF4lYyNYNEQhO15g
VAp6Rkt7NWQ7LT19UWhBK0okMCtjYTdjcUFpMUBFP2l0Y1k4cXhYPC02dGBuPWgkTHxNVW8yej0w
Kjd9YXkrMUEkTmkKekhRWVVDdVYjbGt0e1coRHp8QjVvOHJ6OX17WVVKVFgqI1c7PlB0OFohTjFX
SyRHVEJqKXIkTnE/YXV1UyhuMThOCnp6MFgzRSNLezh7YjtJNVhlN180WldkX1h0d25QSi1TaH5Q
cWB4ZnlITlhiSzchWWFOZXk3XnRkeGEyb0Y7dzxIWAp6PWspKmoyN3c0WURLWWhyQTU7MUlFeSVE
N1RJRXJkMlEyamV7dmZpVCF8RE1AaHFXQlR1Z3M7el95KzY1VCY8UzUKeklgSl5qbkV2PSZeMUdX
ajVIQ3M3VWtEYGpSVFBAK08zK3pSRFFwND5Cb0lATVlvcmQyWUdkQyZGOUVrPEdueHMkCnozOzhN
djd+eXNDUUJgMXBUZ2FiRHEjel5PK187JGtNfG4hJUF4fEVHWkY/TXA8Q1pEdkEleWxOQWtlZW5W
cTt+aQp6Q0Y5QntLa1l5REA3VzswMXRRWmw/PTVeM09FM2FfV05MYU80KkxXTFFZQl5qdEk4QClg
YEppTThMUSUlMVVNYmgKenpQemQtU285UUBieXFCUFF5aE0yWkF8WlhoejI1Z2M2OVl7eWpCKkMj
WnxgdFpiMjFjZUdNYH01e2ZeYU5LeDROCno2Z2FHbGIyUXkycFFDVXZkPjsoaz9VRz9jZk9haDht
Rl51RzwzUEElT0BHMWlCaFBRdVhyTzNjXlQ4UHUqQGolJAp6K3JpVGhMaCVnfT8+XlBhMjMkSj1F
PTxWKiVmclh3dUk7WHRAXit1MyUweilNb0JsVXUrWVRKaEUqZ1hvJFg1WCUKejlaaUQ9Pjs2QytA
LVY/MHRkSkpZeVNnUD0tRT9WT1Y0dF5gcD9ZY2VBZzE4aD1hNHNTQFhaeWQldUpoWjZDbVNPCnpX
WG9HTkV1UjNxPXFySWxGaXBQMGhqZFpfSHU0WCVhYW0kUFA/RH5WNWMoZUA+YWB2NXU3SkstaFpx
P29nIV5pTgp6a1JII2kyPH1BJSpmK3JYemxxYlhMZGtBfFJJKW1tazk0NVJ1RGZhMUErK3gyWWBE
e1ZNMDVVZXVNRmooe3dfYW8KekFZWWpQJVAmaFgmc3VBc21VKjROR2YhazdrWVJEdFV0WXE+WWJB
QCUoRyp1b2EwZClgWTxrJTh5SVNVUDNffkVECnpjWWBCYXM7Oyo1K3s/RjJqMjY7VDElI29Ab2p8
Uyl3KTkqP1N9elVRJigkYFdWWHRxcTBMaVheQElffDBNQ1NEaAp6a1hGYXM+bEtEKUhZR3twYnFj
YDA7P35vYW08cDklUTFWeTxXWV5yO3Z2IXcpZyFKOWhFbEhffik4ckUxfDFsaU4KeihnU0BpSlhi
aHk2SCleNT95NkNlWGxwODlzLTtjaHxJfHdnQnhNKGNlbSgtNkdHcnR9QSh+P29NNmooLUsmWHsl
Cnp6YU1wSVUyQCNIU1M7KVpjSnBzSyNWMERHUEZnc0ZFJClATD9xMUR+e0dkVjFeJT9qYXxLcUUl
K3lCTzchWEUwdAp6Nz9wXj1TQF4kKGdlVT0pdmdqQVNYNyZQKnZWdiheVD01QWAmP1EtY2pZaDJ6
RWJAWiV4PWhVUmFuflVoQXo8YjAKeiYyNDNvUEVOM1VvU2JseVMmKGMzWEhgNyZzfFE0fWtKSWln
YjNURjQyNDJ8JEJaYW4jRm1GaytKYislU2hhfGQ/CnprVjhQVjJ5YkVaJkZ8TXMzTlF+WlRUZlVI
RndBP3ZqSGlaMVVLOWMjPipGWWhpTSUzZk9JS29Ra1dARnRvZVh3PQp6emdsK1dvI2lBb05FdzZ4
WD9xUEZkKnJKeSpSZmB8UzkqPnxWZ0pWIXJlPGFadypVPmNyditXQi12Tk1Laz9AeF4KekxWb0V1
Z0s9RlUtZU9zdUwtWnwzMj8jel9taHd9R1NWM1lJQVlIfldHSkl9Ji1CZkhTYTk1eTlnbXlMRzlU
eGJoCnpqPEtjeVF+ZighaHtLMUx3PyMhcmVsREE1PCQjPz9tSlVtSUFpNiRhcklsTFMqdzhwJVU/
SFMxTURFMFB8OSVBbwp6YTsxQ3dhUVl8SUhAcEVJUihZQm40WUZfVTAwXiY4K3JlNE9LTmQoa0tY
X3AoQCNlb3hRVGBofVRYQHB9dShZaCgKel47UWkoaEBiby1mSzd+SFBkWFQ4eiZDVTwoKXsmQzBA
QVZwcX1Ue19HeFpRRFR1MWs9TXVBUGc0c0s8fUR+a2BBCnp4Q1l8THUzPUI7PSh7KDY7dXRwO0JW
SUhsLUcjWDVVJX5HfDVrVkw9YTJ4TWhQZSZnQVFWMWtSMkIzSk1qWm9wNwp6bCFMRDgqeVYhdnM3
bHZyWmIqXjlhd3ExN3hiamB5ciNFNk9CenA5VD8rNXtYVFIrc1heKHZ1RFRFZWFKb0MoJG4KemFS
Z0QxSlhwOWEyY0A+XkkpLV5OdEtWVkZOXjcpTEZZeUZLNCRmNUQkem01ZW1fRTQtaHkhPGNOTEpQ
b2I7YjNtCnppMCVgOWNuMVJXeThJdD4hMVVHREViPk9UaFlha1BFWnElVHlyODd2MVp3O3NnblZO
ckxlWTJgcUElVWZDTFghJQp6VTNQeygqJUw1MnB+Mn5WMjE0QSpCO3AtWHt0d1IjKDhnWXE4Q3d4
fmU0OCFLKis7I3VmTjAzX2dSNXcmQENUaWYKeko9Xi1GVXtxNEVJeXhtTE9DSU5KU0hNc0sxVylg
aHo8fUBpLSFCPTJ0c2c7dGNuKkRAcU1ARXJzZlEhPGJhOXZWCnopP0Z+YUppOTxJJCFgaXMzQGdn
KDxifC1wbSNHZ0tEZiVNQ0ojUCpYa09oKHhha0cpTmE8eSNTbjwtKmtAZjBrcwp6VV4yK1MmQ3Jp
M2NzZnJIQHg2K1dCN1EjY2VrNk9ONWB3Tmd5N09nPjh9TDIlR1ZXKWJlc1RPRmNBdnUhTTZRMSYK
ejFEYTlTcTA4PF9Jd0pvQnFMLT4rKExzLTBJWDRAcHB3aUx4aG8kI1ZYejtHODBRajVDWE1FMmxG
XklpfEtVJT89CnpmZW1rbnMmUjJuSFJ+RCQkeChlNmFgOEUhRW5PbDFgb248ZkMtZVp9NThsU3Ih
UjtpeCF0aUFoMWYqQiZ6UjIhXwp6PHY/VGEpfDNqZCE7VXw5TGs7cUJnPUFeJVheWTQkd1pHWHVr
KEVNLVNrI008MjlVUTVZSXslKFpPLT1QZVIkSXoKeiRFZklPLTBWfj1NejEpNk9QezdlKVE4Y3Ji
Xmd7TzBWKjEqeUVHSGNsWDhZPWooT3dZdXkjS0B5K2wmLSReSlc8CnpjN1poX0t1KjN1UEpjemwl
MW58WkB8eTM0UTNDNjg3ZXY/SWJUOComPVFQN2xhcTJzWXdeeilocFU/UTtxazdQJAp6WDc5JEI4
ZjVkUUwoNyNWNTl5TiRocDV9MTwoJTI2YjU+QFIlOU5YKm5maE5OclFPJi07UTJNeXVkR01CYEo7
OFkKek5YREY2cSNuO35LI3hiP3tZYVdJLV5JNnJaOCFtPzdJRl85WkJOZmxGV1gxKUBQSklsY0lY
MHNoTyN1WVVQTDQtCno4fGUpSCRmPjg4XnY2RjAkLVVANkhUN0Atd0d1UyF1P3t4SU9BKmIkIz1h
bz5wYF5PIW8ldnx1TTtxQStBOzJYNAp6YiZ4PnNTSSFuWnRpRGQ1eGU3PVUkenpsZ2lAQXMlez81
KlI3LSNlOWhrRWRpPT1aQ29LZVhVcHBMfTM5aiFOe1IKens4VFhkR2ZPYnExb0srPmljNFAtbXBW
XigranF1PG0zYzRQbH5PYH5VRkd3YlpLRTh4NHxnU0padz1DMGRReHsqCnp4NjlHUF5mOGU8VW1T
MWVpVkpkYk5BaVMqZlpYLSEqYG1GVkt8VV8hcjhVVTtVQld4b3dxfE9hZ2R9KmktY0NPaAp6dFJL
VzdZajt8Mj4zc0BfI3swfkZqbm9DVlMtOFBTJGdsbyRUYnhBfiU1N3R3SWZXJXtCcll4PylHKktj
JXV7LWcKem9jZEVaK1JuTFdCTXRJXjc5M19tWk1mMTBjSiNCQlUrQDVBTCNHWSVqRkBDfE01Vj1O
PCVNbj8ycFJoTXBHZWhHCnpEfnJ0NG50V1F+NyRnKTJpQWVKMylERWRnZlJFMW5AR2dNMWxkeT5F
allXM1FKPk82VmNSNEBCJCFsNlE0Zl4tJgp6NUtYJGtKI2dxalkpayRmY3M4RSpWIz1IcWVqMG9k
QDlPVE1UKjN1KkY8RCt3Vj59WTZGcS07dHkqOVB8WThOKE8KejdxQDBWKWloUTNNLUEwTDhSQT4+
JlhgekxpI25gKiV4SHpJJGxgM31PU0VDRUI5b3FTRiYxMWBeZUYpU181PG9ECnp6ZH1vQXlJPG1s
ZFYkM25ufG05d3YxQTIqUntEUkJoNnRGPzs+O1RJOGJoPGo4akdmV1czUHZUZ2d4WCpqV3g8ewp6
ZHFkPWltJHZtJkxDe0Q1PExTfFJkXlo4QVl9eENkYjZ0R1ZJfSE0M0xSNUIyUXNAV2M0WSo8TiE2
QjlRbzdfNHsKenl8TERlMHlYSzJkcGcpP2NHa1FodmlBUEktPWkoTiRKRmVOXiNOdEwlSkhFMVl0
dGMwYk8lPioqeyMwT3EjdHYpCnojbTBxITZ4T3BhU2xjIXh0MyZoPlVmNUs9V197Wjg/UTIjdXJv
emhGSUtBclp8R289QXQ3SUltZnkoPi1eUigmVQp6KzllYFRpdF9paVp8V15fayVAUXNuRzUwSlJX
X2MlKkIoVV9UJnpTUmBVZD9BYXg1JkpYc094NUM5N2RkbihzT3wKejxmb3smaFpJR1d1STNubGcz
X0l2SjtOek4rRE4mSSVsMGEoI2N0I28jPm1gaTFKP2FYRk9ofntCIXxrK2UpNV9VCnolWDFpbUMq
elZ8MSpsO0V0Y1Fld1RFT3JxNzRhdEFofjs3VmVWTF9oYik+fFh2YDdCZ0BNbn1zalR7akVQb3Ay
Qwp6SV8kTzhAKSh7dT43NlFfKFJlYk5wSFNaPnxHKkViNSNye0JJX1hqcGlWQWpUaH0mWkQpM244
fWw0UzcrZCo9I1MKekF2JllVR3JFdmgkIV9iYldxWE5CRWItcT84JkJlUUImUndWQUJCN2RSZkk0
XipjQTYxPD4+OFQ8bUduSyRBU3lBCnphPTNAUVVQX3xiSng4SmdHT0R0azZfPDZgeyFQSVY5ajBl
IWYwc2IjYHFaNk95S1Y3b2EyX1QlLW14Mm80cFdTUQp6dGhqPmZve2xVcm5QNWRgZykqPXkxWklE
UyVfNGt5VllKQVNncl4pO0BgR3sxbHJ7NW1kIW9sej1QSmB9O3J2c1cKem5Zd0s9czxtUlN3WTUo
a1MjVigpcDRyd203Tkd9MnlxX3ZOans5LTxwK0poQ19sYnFsd292KmtiZCk5PE53IWA4Cnpwejho
IUhQS2EtLXRAYWYqTCEyNih7Tkh4TV8lVSEpUGYxRnsjWnBzVSlMfjhLVSMmdWxkbl8tTjlHJjlO
TGBVeAp6Y1N7eUl0TmVuTEk8ZVE1eDw2Z3dgfnJqJG9XMWQ7N1MpUkdSQmxXfnhWano5OTxeJSUk
UXteP3hCYiM9KmkjcSUKeilYSjV8KEV7R1RKI3pMdUpHYX0yMHFtYk9yc0J8TGpmVlE7aGtZUmBR
eFpAQj4tP28jT3d7aEBYeyM0I191Jl5uCnpmNndJY1YjMnBQYGc2MEhzVFJWN0NpcSlVYFBJNnBY
SzZufUhyTUMwZCFSd3tsX216aDlraXcoWnpRa2FuYU1seQp6a3kyRFpVUG1NVkl9PFRgeElAUnJS
eTItT1AxMFlDREdaPTQkIVFDPHlZaWA+KDhqe05gUkhKelV+Yzdge3luX2MKelNHNzY+I3coWlEt
cEJ7VyU2NVBjMClPMiQ2WmNFKTZzME9aXnppQFhvKn5NQ2I1UTUtO29CMSsmP1hGK2dkTGZwCnpF
eXc8OGhZJXlzJXBvbkBiY31DKCFnZ0RtQkQmekJENDhmNl99Q2JeaWEza0V7eHxZTkJBRmoxU3Y+
e1EtOG5YWAp6WUYjYTt4e0RlPV99V0x+K3RnaX4wc2pjVjNYISVrMTFwSGgmfDZFY0pwNURIQ2to
cHV4X01lNk1hYjAjKjR0ZD0Kenh0Z2Z3WEAkM3tGP1U9bWctMHtqe0R7XihNTypyVHFlTjxaQFVj
SyYrb2AjRllBQHpyKHZRKWshUClGcEhHflZQCnpWfEVHeSp2TGgkY3hRYy1RSn5QP3oydVYwMn5T
O2t6QWRmfCpvR0N8dGp5eX04MnFgMjRFMURNJUQrdFMqY2c+Jgp6Xmh7aTRMRkRne080b2pxZTNr
RWNjOV49fm1BSnRZQ24/QVRYSGA3NCQyPyklVHF2UmEzSnomc0AkQXAkX1BwUTcKek4yIWxuXkhK
KSYzcjw8U2dNPCRJSW98WH0kX1hjYkQ4NWJ+QlJQeThOLT9YP2AtK2kwSStMJGBPazxWK3QmcXpZ
CnpFUXlRJVhXOy19OzNhOGlqRDFoWCM9KzhSY1R0OU90a31gYExSKHk2IyUzKF5WeHF8ZV5MUjJ9
NipgP2RwX2tIOwp6diNIb18rcmFGemc8Xztge0ozc3piWEY8YUU1YTZQMnRwKjQwZVJ0WUhGS31k
OzBFa2xOKTUkJUJIUH1fcnR1by0Kem9fWWFSM3FBbGZZWG8qNHdrNnQ1O1JvK3NBMVg1KXheJlFO
ZT56JXJSUV89bk5RMzR6YCpWYWg2VDUwN0d3bX5mCnpTRHhlQTs3eit4dFpZP1lUeDlJalp3Nj04
QHAjX2NEYkdWTXpDNHJZYn1mSjVkPXV8Mj9VIVFpdn0tXlFEKX0/Zwp6YjxUXnBlWTxnMUJKazYz
NEFZV2RyZWBzWShgPXZvWmlaJUZQZXhCPGhmUWo4eitWRllwRVpLeWdkNCRBNyNCckcKelNgeyFr
YGRxbk1ST3NsbmsrR25SeTRSQjN1MVM7OVVkZV5ZMiQ5SDBtalBPcUZ1RkM1QHN+Y15PK0BGQ09Z
OzYmCnpKLXBnVCNlQDI5X0ZyKXRQPX53V1YmM0w2WWIyKVY2aSZiQz5VcD5YMTdMKGNTZiFxTnUp
fSNnKSZjQGp5OEMldAp6VH02I0RxakVJRVd+U0t1ZHNkTllQdSg2I0NFdFhIRW96e2hDNldCXz45
YEpNempqPnhRKWFPSGxMRT0yUXtNdysKeiRFQnQpYFlfNGlnZUVRe1ZffEpBKERROWZWbT4rWFZx
UTlSPkBlUDV3ZVR7UHE2TipQJXFnU0g7P0ZfYCo3KTZWCnoxO0JtQiUyPG9tWkhKMnV5ekg1RS1W
SVFPWDlfZ0F2OVpCKkQqYm5GWlpTc30lbnMzRHRJUnA3Nj53JGxVYlRhTwp6K3N4PyskWEFjUTdU
R0RuYm42PlpVKUU5ajNtcW1eaVJoMXcmfFFSZC1sPVpRNjk5WnI2PjNEKXVTWXJpQCY2aiYKemQj
MT43Tkh0V3AhXkMoWmszKVllNiN1aG9kNFQyVmN9PWF8P3NZY2BvcDtxVTQ+dTVMZjwoeTRld2pK
WD9+SmM8CnozP2d5STFqVGdPbnArdCt1QSFjYXsySGhoeGleK1VlT0FGaStQJlFaeHImPUlCX1No
T0xQK1prPG5SbEQ9el54NAp6RjZiIWlCUWx8MSh5Izh8RH4wKD9rYVowZUgyYzlyYH1BZ29eMnFL
bGYkcHNAbnA2NFYrTCRXamZLbThJVzdCSigKenI+MTc9PlJLc2slJXtqaGxhQEt0S0RNeyVFbUw9
PkRWdCV1RT9SaF9gbWVsVj18fjN0ZyN6MWMlYDlhQHY5Vz0qCnpZcCFEbnBPR3BsO1N+YkU+cVNG
ano1cmZzcmoyQV92e2k8UjkrRTV6X2ohS0otMTs7MmNZSXIreXxTIWN1ZzU+Sgp6cU4mPkdXfjcq
Y0Aqa0FUNzNqSkx0fFRKYVY2OCpKPDw3UmJwbmw/NFI0cEM2RXQpOUBaUGFlRDVlSHEqVVdlZT8K
ejllN2ZmeWZreERZNEpCfmpvYCZlTzRvT1FDYnJWdjwtQjErdz93UFhpUT10Sng7PGRVNStlfWAl
TCtWV2dGJkw4CnpvZkc0dThAeFZLajdfJTN8TlEpXzZBRl44U3lmU0dSOGVZdiRVek5CaEM3dWBo
d0xrN3U1YHkzX0Ngez5xNU0+Qgp6b3tzSXtld2dJMnU4S0l3b3ckb35yRDg/ZS0wbWRuIzRUV2s2
bTBhb1Z+c1opd1VnYjhMZSMqTzJidDNRSWtLcHsKeilJIVFgJUlubTt5KFdlIT5uQ1VRUGx7MDZn
SD58alJxeUxaNlVuaUJHK3kyNWUkZ3RpamN0amBZPjB9Vlg4NmZZCnpAKlFicEBmVm1PWGEoO35j
QyFjZHFVaFV9cj1aUXQlYkFyY14qQkVQVVhIcyR7flVoMyszOFlOZS1YckhaIyZydgp6TVNwc2NE
YXQjfnhQTUZqOU07TndWY2d0YWhmUTMqV0FgPmtTMlg4ZjlyTUd2ZXhaRX5aY318UjZacUJKNGl9
VXcKemFkX1Jibl9yYGZRfWJWOVNELVMraFNYPE12ZWt9Q1FXWUUmIXh1SmtRRzNRYlpGSnlaMU0+
NmJ0cEdTKGp6JTF1CnpQT0NPamI3TWFydXt7RjkxS0tKMGQzTkRhNkpKTkxRUn5Ob3ojKkUoIUk0
YjFkcm4le0NoJFk/Q2s2I1Y2JmoxSgp6QkNgRHpXZGFOdjdrSTlWQEk2czwtMjBlRnFVT25MaEUo
YDduKTExVDwoYGZUeGIrZ0pJLSY1P0htbTltXkt+UU0Kei18MytUQmY+O0VHajUkSWtBakh9d1pS
cDJmUSQxQj5IdnN0ZEI7UmhAOStmP0QrezFAbXlqLW5Jcz19TTUkJHB2CnpLVHU+NEFyUWAhK35v
QUIzSzclIU9tX05lZDZgMkdiKG97Uy09PHNGRUVkfGBuYHMrcyh2NjBweG96RlFtKjglSgp6Pmxu
OU05RCk8ejlMfEYkem1USnotIy0+Q1NAajFRR0JQXmVAa1h4OUY+VXt+bmhNI3p5N09TV2QpPnBf
X1o+U3MKekphJkJKZS01NUUtcH4wfk1qaTtTbEUjUnY5SThKJW9nRldzV2NNWmQhZG4lV29DMjVk
c1c/dUtBXyhncVRERlokCnpXTn50SUBVWmlgaiRZNUwoflFVRTl7ZTsyPFEjOSZ0OypjLU1WUTNE
VU82cnd1JiNLSng1Pkt9MSQzQkhSR3tZbgp6ajE3ViZkQ2NnUE9RaU9QREckIzZ4YmFYNFU9Jnsm
ZTVzWEY5XzlraD9OWjFKKW5aMVRFZ34pNHNmYHwmTCNPVS0KejRBOzRZXlMmMilWQ25vMmEhKGhj
K19MNmo4fXZoY2psa1htKUAmJF49VT9AYU1OeGU7IXJuZzlwY3FxU3RDKj53Cno9NDZUWTdvMktC
RyhjOUtzSUI/KUJ2aGdBJk51cz8pdypBQktObGRScV45WU5ybD5ZWHRLYFRxMWxMPj91SX4wfAp6
KSZ+bXFuN3wpM3NlX0RHRXYzVntydn0oZkNHJThLJGBGbFhsdChgT0omX1lXZTg/QVk2Tj88PzdP
ISpWTGFpcUcKelUyfHFVS0RacXp0WVo2MWBGc2haM3FIazFmQlkmfmhPPFA1elNjb1lKKD9kdkk3
Mz0rT318TzFNQHtFa2NVSFkpCnorKVVBYzZYa2xNd1FgaVFkY0E4aHkxPDFpNDw7b0EhVk81aSM+
aTEpemlmKTk/JSYlWmNtano5d053RihFc3VoIQp6Wkg+NjswPXNJSjc1Mz0yJUdKMmEpZSVOY18k
ZjRUe0lqeHtrVUtCbjY1MH44cFQ1X3t6Q2JmOUIxYFl6VnFDT1MKemtzMz88bjlFM2BXbHh1eyU5
VDEmT2VWZW5AfnFGZyNeSClQTyZ2SiN2ZTQwM0lxRXReSW03IW5FZ3oqI2FVYy0jCnopbXt2Xi0r
TlVZenhvWCo9KWQ+PkI9RGFFeyhtRVopcVZeX3tLQFZhY0hnaEBrcTkzfVJETn4hY3FmJWNfVW9i
RQp6TT0hTkJqRVdXKT9AUUNZc2pSNTdUV1leRVJUV3FkP1hyKzVybzRUOSp+XzBuSzFOUHohRFhW
ZTBvITApZD4rKXkKeiZ7ZjlqPkUpRztKfDc5WnRnbysrbFZiP3VTXkQoKChNdVdZR3wjSGAmdzI2
bGs1ISRXPC0oKD4pWkU9O3k+X09HCnp2YXsoUUhHOD9iczxQYD8xLX1uKHkoZGopNilYZSF2YSk7
ZlI9WCkydmI4Z1JpNTZ7SytEM0oqKkVhaj9sQVpSaAp6aTYtcj4hMyVSb1drdHs1N3pOTHdEZHNz
WkdOKE5+SmwwRCk5Kj98aEs4LV4tPiF1O3JqP287IVMmSG1VUXFhVDQKem0qfmYqP1I9O3twRTs3
K2lASHM4IyR9eGViYVomP1hSVVF3OU9CPi1vaXZaQXBHV1UjSUV+RUNXKyl9YCotYnxGCno5RXVU
KFcjU1BLU3FQKGViY2B+aGdPKnpwZ1p0bFZJOH1SWVlCd0dheU5SNXZpUEBlZ2ElNzxlWGFia2oq
by1UbAp6V31OSnRPekMpRE14ekdTWWF3QV9sSjcmSjAoWV5HMlAwTms0cjdQfG0lbzhKcHJ4Z3lB
SWc4T0FtYCVIOGk7Q00KeiFgSWpNT0UlU2BoeyQoPi1WMyNMWFlsJlVeQWpAayFzWGRRZy1QcVMq
WEckZ0hafHo5TU1XN0BNTHBVZFMrQm9DCnpVNWQtMzV3Pik7S2Fyc0FJQz94JCV3dnpaP1IpMEFJ
V25FWkFnYFJHZmVBUkZ4bXVaQUgocms2QE9LJjY7bXBCKwp6LTVQdz4mZWshbXhVLTxIJlgzS29M
ey1Qd14rUCt+PWxJcnpLe25ARlg9MEp7dWZ+MlNELX5pR3hvVWZpNlB3QSEKejspfjdhRUcjX2t0
RUBeMSFnfWgrdWdoYz9EK2tZP0tPZ3BQek1PczFkP2FHaEJ3TzlFMHQ7UDk1JU5hSCV3TmJECnpS
NV8/RSNrNUFxe0xhclc5UFVrY1MhcHc1WDVfY1doIS12elpyKzBebnlQWiN7OH5MPFl1YH5LI3ZH
eW5RZ2JTUQp6JU4zVD5pNDw9T3dFSylfaGYmOSR2MkdvY0Y+NnRidD5hd1QlS0tAdHF3dFF5SGpa
R21hZDAwbEBSVEhOX31lcCQKekdDPnAzQkU1M2B3OX5CfG1FK1AjanltMT4lWUpWeTRHazd+QWph
clQ7JUtxI2x6T2p9QlR3c3IjNEpxSFQyPClFCno8OzRvZUtUNCYjVFgmfH00SzlBdDlCLSZCQURu
b01NRGZ7OWpwaldIOyg0Wld6SVNzTGxYNGJAcmh4UD0taEU+Rgp6YSplfmRGblpwMXlrJWJfXyN8
QGZxUTUkZzgtQSg+JWohdDtGXm8zfXsxOX1vP3AhOWFgdGs2YmE5fWdBSSM/QUoKekMmKTdmdzNt
WU5TXkp2bS0tX256KzwxK1JzV2F+JjNTM1kkO2VUVXpobTxIQko9alhUVkx5TC14X2d+fmF9bkdQ
Cno+SSpvSE9eZk1TZmlpNFFIPi1GRG9TUjJUKE10dmVAbHpxRnk9VXtyRlBhMW09KWMoNUJNSzJj
RVpWbk9pUDJLfgp6a0YweUNlOXBISDJBPEpHUT5OVyVTcUIkUGRBVGw9QGRaJmM/Z1RJdDdRcl8q
SGtMQUV8OFJmJG5ENGU5bldkMnQKel9HX3cheDtuSlQ3NGpLMG5vYTQpNEZrdG9tSm42aUF9N25T
elI2YUg1cEJebFF3TjdlXlAzKTEpNj5eISglZ0BQCnptdE52cmw+fVI0dTBRVkFGRXh8YTU1TWpA
bmtnU2tLKkx3Zk99cnQlcVNHazI+K3xkVSF8OSpkJWZnPkBYP3Y1OQp6JnFVeDNRKWcrIXs7ZD1x
P3slezduRmArI1ROVCgyLSYoSCNVaTVnT1FQUHBhKlpjeHxrMWxDNFZ6Mz0zTVlRbiMKeiRETzdG
ciNNKFAoWmpqR0BtYXJkcH04ekUoRyV2eiEobTFKNlFsd0ZCQDReZHNsPiE1bSNHUiZ2OT4wMXF+
ZlJHCnpAWkpHNHVHM1dIRmNNdGU5eCYhTmteTXA/eTZxSnp7YGIyR2xjWD12N2pVfmZvbllzKDZn
UllgckF8ekVAQXp4Iwp6Ry01NzB4YjdoQnVtdmtkYVYjKThLRThRRzlIM2Vxe1AhSkhlTyVtc3lL
PWxARzRBMiVRbWpnVFpFYVdRT20qV0wKej89MHs3e2QrbVhCUDdGemRMdk4qI3Q+IyVBYUt8N3hi
Y3hqNk8oanVLS0x0T3IqLUJDRWxvfEVxciVDJGpXOXxyCnpaRWZDPzN5eHJIMGojbWNwfGNvIV8p
PXhfR3w2ZEhyK0h0Q08lVDw8N3Rydj1ARXRgdiZ3NHdoYG4yJUhwUVNwQwp6IVRqaDItcjM4YHd+
KV9ycHV9VHRQfnxpPkdIfndNSVVPI00mYDdCMldecFgrRjllaHY/VkdkRylsZF5xZCRHfFUKem9z
QikrPFNRS1N0RFkmV2J6ZW9jUSN1WGVNLUdmOTMlSVglSndFRnduJStrQUB5IS15I2p9cVFUPCpR
PUZyPVV9CnpWbGZIU0R1KEx8V0lBUkgqfGV0LXY8IWslIWs0MT81QG5OUzN9dzRYYno+djtgXnRy
VEQ1dTlLREc3VE1sWj94WQp6SGpjeVRkNjllenU3b31OQjc8aC1PKzt9bCElMlc+VSRUSldUOGNs
TS1NfXdfR3tydl5NMk81JDUhJkZSbUkwNXAKekYmKFEwV190anpIQmNlVy1AeEZOLWIqfUByZHRS
LTJvQ2VaVz1vWHNrTGpSZSkzRDNtSnctJUI/M19gOTIqOyRjCno1ZlpLb2YhMmkqTTQ/XzBrRz1N
MDJsMlVYRVZJJXU5fHtZYl5Ie2hxcFZ3S3BgOSVvKk5oTnNyYzx1VnYkNSRwQAp6VHheaXpQTEBw
Kys/VWkqYENXT3JCXjJ3bzdfR0FHOEQ+PVB5KHhrVWpLMGBpTkFXbiVPK3F2NjtrN2JYSTEqa3QK
emUhSGRmbXVDcnRRZzUkJj0pa0FucShON0Q/eChRd0pCPzNtV35WNUVWMVdgdFVgSSR+cU9rSXs3
S1c9aygjJmFvCnpjN0kpXmVjTEdLKnVyQmhGRTBXK1NqaDxSbT8hVkkqbnM/Kng2Rz1+dUU9TDRF
Xzd1ZTA2RnB+V295VFVlO0lTOAp6XmQqY1dIIW59YnM8eEk8aD5RO1pEYDs0bXpNTVpEY1lZb3RD
a0poaHFSZT81ZkZhbUYyQEMzaG5SNU8oeUYzVU4KelQteiF5PWxSSyY7QGJZbU8+cEZsOT9peCNF
ND1IMk5man15emc9PDx1Iz0jcDRJZDRoS2YjMnF1Jl81dkgyV1MwCnpeTFkycVhvd0RNY3B6Y2JH
ZTR+X19DTGQkY1RPRm1aSDNZciZQZT1EXkt2e2w0VihwNTY/VH55ejNTMDxEZ287OAp6WT5mYDR2
bC0yMmojYVlQekRvWXs7WWU3NkpuYGplYFY7NSo7bythcjBqIU9MI3pCezJPfm54cjNmUUlYWURN
VTMKelREaUUyPXBKeT97VHshYWxlRyU+SDZxfXcmJmhBKyE+aENqUzIrZSg7Kkg+XnJ3Yi1pMyYx
VyU4X0w1amh9dyQtCnomQDU5bXdqKDhDQ149NXxfUz1DZHE0XlFNQ2E+YURsY05VaHJhSlpNWUcp
bUxnQ3l2dV9lZG50MTJJJFhhUjkpJgp6YGBhX1RmJDIqQj5Xal5iJDUhWFEmYzIlbDtVMFVWTDZw
MnNnQ1p0cGNJfDF6UzNQaj9GSnEmbE8kIyRnOFVqQU0KenJjLUozMzlwZmdDTVEzdTlPcHMlc2Ry
Nk5UYmxgZHItcVR0STJYS3B5NFR2NVQoU0UpIzYqUytGTzhOYyt3QjhkCnprRG9ZOzlWNTZpNS1q
IWJxVGxAcmZqNkV+ODJPYGxhc3VhOCokaDBVJnp2PSRlbWctfEdidy0xe1kxaDw8bSheKQp6P2o0
elUpamkjaUQzUmo9MGB4SVNeeWNNeHN+OXFEKGBqJXRQZVl8e0pCQl9TeV5hZGJBcVluUTBPP1Il
PiRCfkoKekZWWFhQXkl9Sy1NeEpBMWItVSs7KytKR344Y3hrYG1hYno1QnJoe2VFfDlPPCV1MT0w
WnFuKnBlUGMldVlYI1oqCnowYnMrYkZFT2gtO3VnVDA9TVFlPjw+a3BJQGo4JDBpMV9ifHEhc344
dnAqZlJ3SWRmWlpmazE7KkllcHpXQ0A2PAp6MkRBSDsjenM5RD1JTD1lPjJMYGw7STBuUUFINHRm
PGhQdl47alFWJlpvOEFmcmNscGM7O0lpPDl7TUtWZnxMIVUKenBsfjNjZ2BNaitOYUclbXJSfHkq
MDVFRTlabkJhcVVVSThGMVRKUHdlN1NSdiZFTDB7VldVc1NJM3ZOamNUe0JsCnpCQyp1PnI2KGY2
eX41Xn5aKz1sOHhJVz1CYTw1MWk5ZjVHMys2e0FqN3kxS2M/Q35sNGI+aCE1czU8KDZvbzhtUAp6
ezNiQUBMe0l3elBMWXJwKDlxaHdacnp7RTd+UFJeSVh7O3w7QT1HUk8lPT1yY2dyUG9eTGJtU2VP
S3hSKC0pPW8KenBDT25jdnxPZCNOT3BmXyRMRXhhaz01d2xpYzhQejUjPHMzKmk2fmBfTV5GS0Za
MmlmTyFsUDI4PWVeQTU8WHwkCnpWI2cmczU1blRqZWs2PXFedmB+ST5UX1AlSmIqYm4zdXRiaGU9
SWJCSDlxVWZRdFZ6Y3VKeUJ8aD58JkpOUnZgagp6UjFDdUd2bUM2RHNCfntlJmhAPz01UX1GPjtD
M31AK0IrTHgkK0hmUU50XlRhUHdjYVRURyZodm97eW59UXhPUCsKenVuXns/VllIVXJrKVI/QStq
KFRAZzdDIzlUbkU5Y3pTMztQO0E5fX15ZTQ0SUw+VGs+QnNwIWcqWUBUOTc1VHpSCnolPD9iVSQ0
SldIXn1UVFNxWWRrb15PcGwlTkZIazZ0dnFIWkwtUj5pPzY4LXEhTnQrek9aRWFtWjR9b3lqejlr
fQp6S3xzP0AqMXNBRmcxIXBiWCNzWGJMV2hHfTZRJVM4TFZ7ZHB6c3x9bUNXbUw/ViVUTmRNPSQr
ZUoyandKOE08O34Kej1udXZlO2hvNkB0SUt+I2x6WUYpY1VaVEM7UGBJRCNsTiZhbndATyRSaDsq
NEtLd3chYj98TkRrP1lfYD8hPjZWCnpgTjBIUG5xWTJzdmZmUkR3Y0p3S205M0hmJldSVllPITY+
UjE4RHUpT2o0ekRhfChtNHFobnZmT08+QWVZUz56Twp6MmhDMShGaD1aOU95Skdfd2A4NyEmJSUz
JDhuKWFOazlnZHFzdk1fYldBPWlsTWVgI2c8cm92MS1HbWk3WmAwencKekA0Tzx4SzdFZ3U4fmMq
bnJWRTlARTZ2aWZCY0lBfEh7Q3lBOzh6QXdtenNJPmo9elhZXlEjMC1ydlB+NGUmWCMlCnpUbnlF
N3A4aG1HJWp3Qkp6c2NOWmN9IUcqLWs9dWVGUDhRejMqZGR3bF4oWXhONF4hOWtXPGZaOXBuRE5e
dyFoVwp6I0g7Qy0/UC1+bEhjaWM5LWtJQWlSUklVbCNSRGFuYVlgWS0qR0dAYmY+KWF4Tj5DNX1o
VnZ4I3ZISk1GbklkeE4KelMjT25QbVBhJlV5XmR6Uj1hYz4wXiZXQSVuMDkjKzFYS3lVI290MDQm
eSZZRHBDR0V3cVVLJENSTFZSfiVDXktUCnpFKTlLLWQ9dShUamV8VCE/Z2FMJWFSa15GUzUtUzw+
Jn1sP0ZPaVh7SkU9UzhiOCtMIzZSdH1LciVCRWg9UitNOQp6dD9oU2VtKTUrfGpuKWVWOTJvNChA
RyFLOHFscTw9bCV0PjY9e1VOeypWcT51Y2FBbSo1Kmk4S3tNTEpsTzApajYKejh4dUdeOXFUPjVa
T0gzKHlqIVNTT0JYR013UDFTZTluZGQ7LTJ3e2VFaWBROGlpfCghSXZ7MjU5QTQ9O0xMVDZ6CnpJ
cFB2ZDYhcVZzLTB2a0VJSEhgTjc+aT5OSVFzNTc9eytCS3VwUyM3PVlhYSk+K1VWXmxpVH1PZ0pF
RXMpKn5UNQp6MmprI19zS1ApQCU1NiRQKV80O1MrdGllXmZIezNNZl8qY1o7c3NzIVhGK315RzBi
WmpEc0hwKitJanMtdF8pJSEKekl7RCRMSXUmVDl3KmlVPFZgK348Rm0jQykyP2F8WjlVWkwtJjBv
ZzlyVkBNN3BfMlM5Vnx4MGZgUDU7cnUlJTNACnomdVFMXy19cEE7SmtJVlVYbWAhfVM8ZWRqeypA
I1AzRHpfKUZvMFNGVDNkRz1AakFAWl5sWnZ4I0szcHB4NWFHTQp6QCoycmpgfSY/XzVjTzlTQ25z
eURxezVVP2pAez1VMjtFUnZfdTwpKmx5cGJRU08mNSo/PkZxQ3NOWD5jLWkxYzcKejM+IWgwaUZ4
LTM/I3dTVzEoWCFsPWhRbkZQQ0JmUEBmcjZOSTUpczcpPjF5YG43Q1NJMmQqcVA5M3A9PTlKTyF5
CnpiN2c2cktwK0k+U058YC0qLSs+Slo3QlgkOUdpaWNhWGA+dDkwQ2pUQHBoQilxaGRhdi1NPk5S
bDN9O3kyZU1PTQp6alhMblVxcDs7SyZxQnwqUElyZUF4RUVAQXprQXNjaTUtQGx3fFpZYkdwTzFU
cmJEK1RJZHcpcHUzTmB1en5IKHQKenUoS29qPjlke3Q9ZVpmdihjTkZEZ358ZmpCMUhQak9ZT35m
Pk0lUjYmc1gxNWQwTiFCO0NkfXd4ZSUqZjZMKzgwCnpPQVJJXl81fG5PSEdCMDlxSU00YypMVjBo
MyZzbTRFZ09ieEVaVnZzQ0xIXz9eaiQ5djl8Xk1YKlQ+aUBidEhhaQp6c1A9V3dSPSlVc1MofW9Z
biVXekRrYD5fRUpeRVJ8JSVnY18rcX5WWEpHMEM4JXwreTdnUVl0KCg9JT1NbDE8UUoKel9iWT11
cz48PjRuTEJQOEBmVXpeSlFhPk0lSE8jdj1ZNmNMdHpuSW8hcF9ZSCVFc1VNX15lLXh2NTYlND9K
dkdQCnpuSC11KEVqNGR2PmEjTDdJYjNDKW5qN3VYREVCem8/QGhUaGxabTJBQ303OD9jc1ErWilx
bGx+I14kVTVDQDhudAp6YHt9VD8pQlNPdykmMmE+KHJ+R2xRV2FfPGxfQkF2Qzl3QUp4OGt0eCNS
dVE+Sm0mSiFkWTBCT3FQezxTQnhSTzgKekZrdnhnQytNPVpfazY8OTMpeGtiOzxKbnlrK1pwYGsp
VCo2c2AkdSQ1aXlYeTUyUnB2azwtO1o+fiMjMSpOTTliCno1N3g1SHctWFBLb08maStuN2klT2wz
N2t5SVZMcGtFe1JPaTlHYD1gMlRvQnlCMjdXKUB6Vz9WS3AhXmlXKTU5bQp6Nj57bz42JlZ+JWxO
bHpudXM1O0Ztd0RQZEoyZnJrcjF8KGBYMXJDRCNYUE94YnoyNFVRMTdgd3pXS3xjPUEzSHAKendZ
K0JSNSNATEF0PEs+MTRoRzxfWDdOSmdrQTMkYHhzIyVqLVA8UHh3IWI5PUVgZTtuQ2p+UHppPldL
OVg5PlA2CnpwNnwqY0dsc0lUKkgpbHpqMiYlSHpqUilCSkw1WjA9LX10OUZARzh2JikjTDUpNyRB
ZWV0fDUjQ3RzR0lLfGc9Qwp6KDJTbi15cztZIWQtZClKYnhCSmVxR0l+RDE8VTFqb0NgdlEkZm5A
OV4peGZUQmA+aFo2R1IkVGByP0ZPelY5YnYKenIyRzE+YTBhJW4jN2dAIWtzTGJeQXwzP3x6SXI1
VjxIR0Nabk4/NzRVK3FwciZQaHVVTyUpZS1XVUooQGZ9dDVkCno4KjQlfVowXnBZSF9KUlhRJkg/
eCFaeGE1Y2NAfERrQjhJNXAhY25OZT4xM2w7Zmh1azhUZ215bn4md0I9MWUqcQp6JjJDbzxNYWU5
Z1E/dUR8UXxLS1dPK3tEc3JKVClPLXJUTSlfdzlpPiUkMlFTQHMyfHhYSyl9OTBANjNtbjwpU2oK
ek9yT1BnQlZudlohUHQtaWEybz1tK1dTbGI1QEg1MnRSTFQ3YTNOMmJOKzZKa28yPnMwe1U/ZTRZ
fnVnUnU1aT4wClhiKk5OU1ZTK3huWUx2LUtEQCh5OE95Qi1yc1p+dFQKCmxpdGVyYWwgMApIY21W
P2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvdmliZW1pcy5zdmcgYi9hcHAvcmVzL3ZpYmVt
aXMuc3ZnCmluZGV4IGMzZjNjODEuLjcxMTVjMzMgMTAwNjQ0Ci0tLSBhL2FwcC9yZXMvdmliZW1p
cy5zdmcKKysrIGIvYXBwL3Jlcy92aWJlbWlzLnN2ZwpAQCAtMSwxOSArMSw3IEBACi08P3htbCB2
ZXJzaW9uPSIxLjAiIGVuY29kaW5nPSJVVEYtOCIgc3RhbmRhbG9uZT0ibm8iPz4KLTwhLS0gVmli
ZW1pcyBicmFuZCBtYXJrOiBhIGN1dC1nZW0gZGlhbW9uZCBjcmFkbGluZyBhIHBsYXkgdHJpYW5n
bGUuCi0gICAgIERyYXduIGZyb20gdGhlIGRlc2lnbi1raXQgdG9rZW5zIChkb2NzL2Rlc2lnbi9y
ZWRlc2lnbi9sb2dvL1JFQURNRS5tZCk6Ci0gICAgIGRpYW1vbmQgaGFsZi1kaWFnb25hbCB+Mzcl
IG9mIHRoZSBib3gsIHN0cm9rZSB+Ny44JSBvZiB0aGUgYm94LCBmaWxsZWQKLSAgICAgcGxheSB0
cmlhbmdsZSB+MzAlIHRhbGwgY2VudGVyZWQgaW5zaWRlLCBhY2NlbnQgZ3JhZGllbnQKLSAgICAg
IzZBRERFNyAtPiAjMkZDNkQwLiBUaGUgc29mdCBnbG93IGlzIG9taXR0ZWQgc28gdGhlIG1hcmsg
c3RheXMgY3Jpc3AgYXQKLSAgICAgdGhlIHNtYWxsIHNpemVzIHRoaXMgU1ZHIGlzIHJhc3Rlcml6
ZWQgYXQgKFNETCBzdHJlYW0td2luZG93IGljb24pLiAtLT4KLTxzdmcgeG1sbnM9Imh0dHA6Ly93
d3cudzMub3JnLzIwMDAvc3ZnIiB2aWV3Qm94PSIwIDAgMjU2IDI1NiIgd2lkdGg9IjI1NiIgaGVp
Z2h0PSIyNTYiPgotICA8ZGVmcz4KLSAgICA8bGluZWFyR3JhZGllbnQgaWQ9InZiQWNjZW50IiB4
MT0iMCIgeTE9IjAiIHgyPSIxIiB5Mj0iMSI+Ci0gICAgICA8c3RvcCBvZmZzZXQ9IjAiIHN0b3At
Y29sb3I9IiM2QURERTciLz4KLSAgICAgIDxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzJG
QzZEMCIvPgotICAgIDwvbGluZWFyR3JhZGllbnQ+Ci0gIDwvZGVmcz4KLSAgPHBhdGggZD0iTSAx
MjggMzMuMyBMIDIyMi43IDEyOCBMIDEyOCAyMjIuNyBMIDMzLjMgMTI4IFoiIGZpbGw9Im5vbmUi
Ci0gICAgICAgIHN0cm9rZT0idXJsKCN2YkFjY2VudCkiIHN0cm9rZS13aWR0aD0iMjAiIHN0cm9r
ZS1saW5lam9pbj0icm91bmQiLz4KLSAgPHBhdGggZD0iTSAxMDcgOTIuNiBMIDEwNyAxNjMuNCBM
IDE2OCAxMjggWiIgZmlsbD0idXJsKCN2YkFjY2VudCkiCi0gICAgICAgIHN0cm9rZT0idXJsKCN2
YkFjY2VudCkiIHN0cm9rZS13aWR0aD0iMTIiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KKzxz
dmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iNTEyIiBoZWlnaHQ9
IjUxMiIgdmlld0JveD0iMCAwIDUxMiA1MTIiPgorPGRlZnM+PGxpbmVhckdyYWRpZW50IGlkPSJy
aW0iIHgxPSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjZmY3NThi
Ii8+PHN0b3Agb2Zmc2V0PSIuNDgiIHN0b3AtY29sb3I9IiNkYzM2NTgiLz48c3RvcCBvZmZzZXQ9
IjEiIHN0b3AtY29sb3I9IiM2MzE1MmIiLz48L2xpbmVhckdyYWRpZW50PjxsaW5lYXJHcmFkaWVu
dCBpZD0iZ2xhc3MiIHgxPSIwIiB5MT0iMCIgeDI9IjAiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9y
PSIjMjAxNTFjIi8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjMDgwODBiIi8+PC9saW5l
YXJHcmFkaWVudD48L2RlZnM+Cis8cmVjdCB4PSIxMiIgeT0iMTIiIHdpZHRoPSI0ODgiIGhlaWdo
dD0iNDg4IiByeD0iMTEwIiBmaWxsPSJ1cmwoI2dsYXNzKSIgc3Ryb2tlPSIjZmZmZmZmIiBzdHJv
a2Utb3BhY2l0eT0iLjEzIiBzdHJva2Utd2lkdGg9IjIiLz4KKzxjaXJjbGUgY3g9IjI1NiIgY3k9
IjI1NiIgcj0iMTQ0IiBmaWxsPSJ1cmwoI3JpbSkiLz4KKzxjaXJjbGUgY3g9IjI2OCIgY3k9IjI0
OSIgcj0iMTM2IiBmaWxsPSIjMDgwODBiIi8+Cis8cGF0aCBkPSJNMTUxIDE2MmExNDMgMTQzIDAg
MCAxIDEzNS00OCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZlOGVlIiBzdHJva2Utb3BhY2l0eT0i
LjU1IiBzdHJva2Utd2lkdGg9IjMiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPgogPC9zdmc+CmRp
ZmYgLS1naXQgYS9hcHAvcmVzb3VyY2VzLnFyYyBiL2FwcC9yZXNvdXJjZXMucXJjCmluZGV4IGI1
ZDRlZTcuLjA4YmRmMmIgMTAwNjQ0Ci0tLSBhL2FwcC9yZXNvdXJjZXMucXJjCisrKyBiL2FwcC9y
ZXNvdXJjZXMucXJjCkBAIC0xLDEzICsxLDIzIEBACiA8UkNDPgogICAgIDxxcmVzb3VyY2UgcHJl
Zml4PSIvIj4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX3AucG5nIj5y
ZXMvc3RlYW0vdmliZW1pc19wLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9z
dGVhbS92aWJlbWlzLnBuZyI+cmVzL3N0ZWFtL3ZpYmVtaXMucG5nPC9maWxlPgotICAgICAgICA8
ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfaGVyby5wbmciPnJlcy9zdGVhbS92aWJlbWlz
X2hlcm8ucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNf
bG9nby5wbmciPnJlcy9zdGVhbS92aWJlbWlzX2xvZ28ucG5nPC9maWxlPgotICAgICAgICA8Zmls
ZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfaWNvbi5wbmciPnJlcy9zdGVhbS92aWJlbWlzX2lj
b24ucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay01MTIu
cG5nIj5yZXMvdmliZW1pcy1tYXJrLTUxMi5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFsaWFz
PSJyZXMvdmliZW1pcy1tYXJrLTI1Ni5wbmciPnJlcy92aWJlbWlzLW1hcmstMjU2LnBuZzwvZmls
ZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstMTI4LnBuZyI+cmVzL3Zp
YmVtaXMtbWFyay0xMjgucG5nPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUhhcmR3
YXJlTW9uaXRvci5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9FY2xpcHNlU3lzdGVtU2V0
dGluZ3MucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUNvbWJvQm94LnFtbDwv
ZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2NyaW1zb24tbmV0d29yay5zdmc8L2ZpbGU+CisgICAg
ICAgIDxmaWxlPnJlcy9jcmltc29uLWJsdWV0b290aC5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxl
PnJlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2VjbGlw
c2UtaWNvbi5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9lY2xpcHNlLXBvd2VyLnN2Zzwv
ZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2NyaW1zb24tYmF0dGVyeS5zdmc8L2ZpbGU+CisgICAg
ICAgIDxmaWxlPnJlcy9jcmltc29uLWhvc3Quc3ZnPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlh
cz0icmVzL3N0ZWFtL3ZpYmVtaXNfcC5wbmciPnJlcy9zdGVhbS9lY2xpcHNlX3AucG5nPC9maWxl
PgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXMucG5nIj5yZXMvc3RlYW0v
ZWNsaXBzZS5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1p
c19oZXJvLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmc8L2ZpbGU+CisgICAgICAgIDxm
aWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19sb2dvLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2Vf
bG9nby5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19p
Y29uLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfaWNvbi5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxl
IGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTUxMi5wbmciPnJlcy9lY2xpcHNlLW1hcmstNTEyLnBu
ZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstMjU2LnBuZyI+
cmVzL2VjbGlwc2UtbWFyay0yNTYucG5nPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVz
L3ZpYmVtaXMtbWFyay0xMjgucG5nIj5yZXMvZWNsaXBzZS1tYXJrLTEyOC5wbmc8L2ZpbGU+CiAg
ICAgICAgIDxmaWxlIGFsaWFzPSJmb250cy9Tb3JhLnR0ZiI+Zm9udHMvU29yYS50dGY8L2ZpbGU+
CiAgICAgICAgIDxmaWxlIGFsaWFzPSJmb250cy9NYW5yb3BlLnR0ZiI+Zm9udHMvTWFucm9wZS50
dGY8L2ZpbGU+CiAgICAgICAgIDxmaWxlPnJlcy9zb3VuZHMvbmF2X3RpY2sud2F2PC9maWxlPgpk
aWZmIC0tZ2l0IGEvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2VzLmNwcCBiL2FwcC9z
ZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5jcHAKaW5kZXggZDY5YTkxMy4uNjAyMmIyNSAx
MDA2NDQKLS0tIGEvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2VzLmNwcAorKysgYi9h
cHAvc2V0dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuY3BwCkBAIC0yMjksNyArMjI5LDcgQEAg
dm9pZCBTdHJlYW1pbmdQcmVmZXJlbmNlczo6cmVsb2FkKCkKICAgICBzZWVuV2VsY29tZUhpbnQg
PSBzZXR0aW5ncy52YWx1ZShTRVJfU0VFTldFTENPTUVISU5ULCBmYWxzZSkudG9Cb29sKCk7CiAg
ICAgZW5hYmxlSGRyID0gc2V0dGluZ3MudmFsdWUoU0VSX0hEUiwgZmFsc2UpLnRvQm9vbCgpOwog
ICAgIHVpU2hvd0hpbnRzID0gc2V0dGluZ3MudmFsdWUoU0VSX1VJX1NIT1dISU5UUywgdHJ1ZSku
dG9Cb29sKCk7Ci0gICAgdWlBY2NlbnRJbmRleCA9IHFCb3VuZCgwLCBzZXR0aW5ncy52YWx1ZShT
RVJfVUlfQUNDRU5USU5ERVgsIDApLnRvSW50KCksIDMpOworICAgIHVpQWNjZW50SW5kZXggPSBx
Qm91bmQoMCwgc2V0dGluZ3MudmFsdWUoU0VSX1VJX0FDQ0VOVElOREVYLCA0KS50b0ludCgpLCAx
NSk7CiAgICAgdWlTb3VuZHMgPSBzZXR0aW5ncy52YWx1ZShTRVJfVUlTT1VORFMsIHRydWUpLnRv
Qm9vbCgpOwogICAgIGRpc3BsYXlIZHJDYXBhYmlsaXR5ID0gc2V0dGluZ3MudmFsdWUoU0VSX0RJ
U1BMQVlfSERSX0NBUEFCSUxJVFksIHRydWUpLnRvQm9vbCgpOwogICAgIGhkclRvbmVtYXBwaW5n
ID0gc2V0dGluZ3MudmFsdWUoU0VSX0hEUl9UT05FTUFQLCBmYWxzZSkudG9Cb29sKCk7CmRpZmYg
LS1naXQgYS9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmNwcCBiL2FwcC9zdHJlYW1pbmcvaW5w
dXQvaW5wdXQuY3BwCmluZGV4IDEwNTA1ZWYuLjNmYWY4N2YgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJl
YW1pbmcvaW5wdXQvaW5wdXQuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvaW5wdXQvaW5wdXQuY3Bw
CkBAIC04OCw2ICs4OCwxMCBAQCBTZGxJbnB1dEhhbmRsZXI6OlNkbElucHV0SGFuZGxlcihTdHJl
YW1pbmdQcmVmZXJlbmNlcyYgcHJlZnMsIGludCBzdHJlYW1XaWR0aCwgaQogICAgIG1fU3BlY2lh
bEtleUNvbWJvc1tLZXlDb21ib1RvZ2dsZVN0YXRzT3ZlcmxheV0ua2V5Q29kZSA9IFNETEtfczsK
ICAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVTdGF0c092ZXJsYXldLnNjYW5D
b2RlID0gU0RMX1NDQU5DT0RFX1M7CiAgICAgbV9TcGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9n
Z2xlU3RhdHNPdmVybGF5XS5lbmFibGVkID0gdHJ1ZTsKKyAgICBtX1NwZWNpYWxLZXlDb21ib3Nb
S2V5Q29tYm9Ub2dnbGVMb2NhbEhhcmR3YXJlXS5rZXlDb21ibyA9IEtleUNvbWJvVG9nZ2xlTG9j
YWxIYXJkd2FyZTsKKyAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVMb2NhbEhh
cmR3YXJlXS5rZXlDb2RlID0gU0RMS19oOworICAgIG1fU3BlY2lhbEtleUNvbWJvc1tLZXlDb21i
b1RvZ2dsZUxvY2FsSGFyZHdhcmVdLnNjYW5Db2RlID0gU0RMX1NDQU5DT0RFX0g7CisgICAgbV9T
cGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlTG9jYWxIYXJkd2FyZV0uZW5hYmxlZCA9IHRy
dWU7CiAKICAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVNb3VzZU1vZGVdLmtl
eUNvbWJvID0gS2V5Q29tYm9Ub2dnbGVNb3VzZU1vZGU7CiAgICAgbV9TcGVjaWFsS2V5Q29tYm9z
W0tleUNvbWJvVG9nZ2xlTW91c2VNb2RlXS5rZXlDb2RlID0gU0RMS19tOwpkaWZmIC0tZ2l0IGEv
YXBwL3N0cmVhbWluZy9pbnB1dC9pbnB1dC5oIGIvYXBwL3N0cmVhbWluZy9pbnB1dC9pbnB1dC5o
CmluZGV4IGY4MjhjMDQuLjdkNWIxZGEgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvaW5wdXQv
aW5wdXQuaAorKysgYi9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmgKQEAgLTE4OCw2ICsxODgs
NyBAQCBwcml2YXRlOgogICAgICAgICBLZXlDb21ib1VuZ3JhYklucHV0LAogICAgICAgICBLZXlD
b21ib1RvZ2dsZUZ1bGxTY3JlZW4sCiAgICAgICAgIEtleUNvbWJvVG9nZ2xlU3RhdHNPdmVybGF5
LAorICAgICAgICBLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmUsCiAgICAgICAgIEtleUNvbWJv
VG9nZ2xlTW91c2VNb2RlLAogICAgICAgICBLZXlDb21ib1RvZ2dsZUN1cnNvckhpZGUsCiAgICAg
ICAgIEtleUNvbWJvVG9nZ2xlTWluaW1pemUsCmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL2lu
cHV0L2tleWJvYXJkLmNwcCBiL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9hcmQuY3BwCmluZGV4
IDk5M2U1MzQuLjk0MjU2MmUgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9h
cmQuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvaW5wdXQva2V5Ym9hcmQuY3BwCkBAIC01MSw2ICs1
MSwxMSBAQCB2b2lkIFNkbElucHV0SGFuZGxlcjo6cGVyZm9ybVNwZWNpYWxLZXlDb21ibyhLZXlD
b21ibyBjb21ibykKICAgICAgICAgcmFpc2VBbGxLZXlzKCk7CiAgICAgICAgIGJyZWFrOwogCisg
ICAgY2FzZSBLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmU6CisgICAgICAgIFNlc3Npb246Omdl
dCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLnNldE92ZXJsYXlTdGF0ZShPdmVybGF5OjpPdmVybGF5
TG9jYWxIYXJkd2FyZSwKKyAgICAgICAgICAgICAhU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlN
YW5hZ2VyKCkuaXNPdmVybGF5RW5hYmxlZChPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkp
OworICAgICAgICBicmVhazsKKwogICAgIGNhc2UgS2V5Q29tYm9Ub2dnbGVTdGF0c092ZXJsYXk6
CiAgICAgICAgIFNETF9Mb2dJbmZvKFNETF9MT0dfQ0FURUdPUllfQVBQTElDQVRJT04sCiAgICAg
ICAgICAgICAgICAgICAgICJEZXRlY3RlZCBzdGF0cyB0b2dnbGUgY29tYm8iKTsKZGlmZiAtLWdp
dCBhL2FwcC9zdHJlYW1pbmcvc2Vzc2lvbi5jcHAgYi9hcHAvc3RyZWFtaW5nL3Nlc3Npb24uY3Bw
CmluZGV4IDU4ZmViOTYuLjc5MWVmNGMgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvc2Vzc2lv
bi5jcHAKKysrIGIvYXBwL3N0cmVhbWluZy9zZXNzaW9uLmNwcApAQCAtMSw0ICsxLDUgQEAKICNp
bmNsdWRlICJzZXNzaW9uLmgiDQorI2luY2x1ZGUgPFFTZXR0aW5ncz4NCiAjaW5jbHVkZSAic2V0
dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuaCINCiAjaW5jbHVkZSAic3RyZWFtaW5nL3N0cmVh
bXV0aWxzLmgiDQogI2luY2x1ZGUgInN0cmVhbWluZy92cnJyYXRlcG9saWN5LmgiDQpAQCAtMjY2
OSw2ICsyNjcwLDcgQEAgdm9pZCBTZXNzaW9uOjpleGVjSW50ZXJuYWwoKQogDQogICAgIC8vIFRv
Z2dsZSB0aGUgc3RhdHMgb3ZlcmxheSBpZiByZXF1ZXN0ZWQgYnkgdGhlIHVzZXINCiAgICAgbV9P
dmVybGF5TWFuYWdlci5zZXRPdmVybGF5U3RhdGUoT3ZlcmxheTo6T3ZlcmxheURlYnVnLCBtX1By
ZWZlcmVuY2VzLT5zaG93UGVyZm9ybWFuY2VPdmVybGF5KTsNCisgICAgbV9PdmVybGF5TWFuYWdl
ci5zZXRPdmVybGF5U3RhdGUoT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUsIFFTZXR0aW5n
cygpLnZhbHVlKCJlY2xpcHNlL2xvY2FsT3ZlcmxheSIsZmFsc2UpLnRvQm9vbCgpKTsNCiANCiAg
ICAgLy8gVmliZW1pczogb3B0LWluIG9uLXNjcmVlbiB0b3VjaCBjb250cm9scyBvdmVybGF5IOKA
lA0KICAgICAvLyB0aHJlZSBpY29uLW9ubHkgYnV0dG9ucyAoTUVOVSBvcGVucyB0aGUgUXVpY2sg
TWVudSwgS0JEIHJlcXVlc3RzIHRoZSBTdGVhbU9TDQpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWlu
Zy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2QzZDExdmEuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRl
by9mZm1wZWctcmVuZGVyZXJzL2QzZDExdmEuY3BwCmluZGV4IDM4OGUzMDcuLmY4NTMyMzkgMTAw
NjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9kM2QxMXZhLmNw
cAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZDNkMTF2YS5jcHAK
QEAgLTk2NCw3ICs5NjQsNyBAQCB2b2lkIEQzRDExVkFSZW5kZXJlcjo6bm90aWZ5T3ZlcmxheVVw
ZGF0ZWQoT3ZlcmxheTo6T3ZlcmxheVR5cGUgdHlwZSkKICAgICAgICAgcmVuZGVyUmVjdC54ID0g
MDsKICAgICAgICAgcmVuZGVyUmVjdC55ID0gMDsKICAgICB9Ci0gICAgZWxzZSBpZiAodHlwZSA9
PSBPdmVybGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6
Ok92ZXJsYXlEZWJ1ZyB8fCB0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlKSB7
CiAgICAgICAgIC8vIFRvcCBsZWZ0CiAgICAgICAgIHJlbmRlclJlY3QueCA9IDA7CiAgICAgICAg
IHJlbmRlclJlY3QueSA9IG1fRGlzcGxheUhlaWdodCAtIG5ld1N1cmZhY2UtPmg7CmRpZmYgLS1n
aXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZHh2YTIuY3BwIGIvYXBw
L3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2R4dmEyLmNwcAppbmRleCAzMjYxOGQ4
Li4wNGI1ZDE3IDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJl
cnMvZHh2YTIuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9k
eHZhMi5jcHAKQEAgLTg2Miw3ICs4NjIsNyBAQCB2b2lkIERYVkEyUmVuZGVyZXI6Om5vdGlmeU92
ZXJsYXlVcGRhdGVkKE92ZXJsYXk6Ok92ZXJsYXlUeXBlIHR5cGUpCiAgICAgICAgIHJlbmRlclJl
Y3QueCA9IDA7CiAgICAgICAgIHJlbmRlclJlY3QueSA9IG1fRGlzcGxheUhlaWdodCAtIG5ld1N1
cmZhY2UtPmg7CiAgICAgfQotICAgIGVsc2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURl
YnVnKSB7CisgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgdHlw
ZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAvLyBUb3AgbGVm
dAogICAgICAgICByZW5kZXJSZWN0LnggPSAwOwogICAgICAgICByZW5kZXJSZWN0LnkgPSAwOwpk
aWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2VnbHZpZC5j
cHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZWdsdmlkLmNwcAppbmRl
eCA5NTg3YTM1Li4yMDY4MGQ4IDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBl
Zy1yZW5kZXJlcnMvZWdsdmlkLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1y
ZW5kZXJlcnMvZWdsdmlkLmNwcApAQCAtMjM0LDEwICsyMzQsMTAgQEAgdm9pZCBFR0xSZW5kZXJl
cjo6cmVuZGVyT3ZlcmxheShPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBlLCBpbnQgdmlld3BvcnRX
aWR0aCwgaW4KICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnggPSAwOwogICAgICAgICAgICAgb3Zl
cmxheVJlY3QueSA9IDA7CiAgICAgICAgIH0KLSAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVy
bGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpP
dmVybGF5RGVidWcgfHwgdHlwZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewog
ICAgICAgICAgICAgLy8gVmliZW1pczogdXNlci1jb25maWd1cmFibGUgY29ybmVyLiBOQjogT3Bl
bkdMIG9yaWdpbiBpcyBsb3dlci1sZWZ0LAogICAgICAgICAgICAgLy8gc28gInRvcCIgaXMgdGhl
IGhpZ2gtWSBlZGdlIGhlcmUuCi0gICAgICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0
KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAgICAg
ICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0
T3ZlcmxheUFuY2hvcih0eXBlKTsKICAgICAgICAgICAgIGJvb2wgcmlnaHQgPSAoYW5jaG9yID09
IDEgfHwgYW5jaG9yID09IDMpOyAgLy8gVFIgb3IgQlIKICAgICAgICAgICAgIGJvb2wgYm90dG9t
ID0gKGFuY2hvciA9PSAyIHx8IGFuY2hvciA9PSAzKTsgLy8gQkwgb3IgQlIKICAgICAgICAgICAg
IG92ZXJsYXlSZWN0LnggPSByaWdodCA/ICh2aWV3cG9ydFdpZHRoIC0gbmV3U3VyZmFjZS0+dykg
OiAwOwpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3Bs
dmsuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3BsdmsuY3BwCmlu
ZGV4IGJjMTZmZjIuLmJhYzE4NWIgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZt
cGVnLXJlbmRlcmVycy9wbHZrLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1y
ZW5kZXJlcnMvcGx2ay5jcHAKQEAgLTEzODIsMTAgKzEzODIsMTAgQEAgdm9pZCBQbFZrUmVuZGVy
ZXI6OnJlbmRlckZyYW1lKEFWRnJhbWUgKmZyYW1lKQogICAgICAgICAgICAgICAgIG92ZXJsYXlQ
YXJ0c1tpXS5kc3QueDAgPSAwOw0KICAgICAgICAgICAgICAgICBvdmVybGF5UGFydHNbaV0uZHN0
LnkwID0gU0RMX21heCgwLCB0YXJnZXRGcmFtZS5jcm9wLnkxIC0gb3ZlcmxheVBhcnRzW2ldLnNy
Yy55MSk7DQogICAgICAgICAgICAgfQ0KLSAgICAgICAgICAgIGVsc2UgaWYgKGkgPT0gT3Zlcmxh
eTo6T3ZlcmxheURlYnVnKSB7DQotICAgICAgICAgICAgICAgIC8vIFRvcCBsZWZ0DQotICAgICAg
ICAgICAgICAgIG92ZXJsYXlQYXJ0c1tpXS5kc3QueDAgPSAwOw0KLSAgICAgICAgICAgICAgICBv
dmVybGF5UGFydHNbaV0uZHN0LnkwID0gMDsNCisgICAgICAgICAgICBlbHNlIGlmIChpID09IE92
ZXJsYXk6Ok92ZXJsYXlEZWJ1ZyB8fCBpID09IE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJl
KSB7DQorICAgICAgICAgICAgICAgIGludCBhbmNob3I9U2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJs
YXlNYW5hZ2VyKCkuZ2V0T3ZlcmxheUFuY2hvcihzdGF0aWNfY2FzdDxPdmVybGF5OjpPdmVybGF5
VHlwZT4oaSkpOw0KKyAgICAgICAgICAgICAgICBvdmVybGF5UGFydHNbaV0uZHN0LngwPShhbmNo
b3I9PTEgfHwgYW5jaG9yPT0zKSA/IFNETF9tYXgoMCx0YXJnZXRGcmFtZS5jcm9wLngxLW92ZXJs
YXlQYXJ0c1tpXS5zcmMueDEpIDogMDsNCisgICAgICAgICAgICAgICAgb3ZlcmxheVBhcnRzW2ld
LmRzdC55MD0oYW5jaG9yPT0yIHx8IGFuY2hvcj09MykgPyBTRExfbWF4KDAsdGFyZ2V0RnJhbWUu
Y3JvcC55MS1vdmVybGF5UGFydHNbaV0uc3JjLnkxKSA6IDA7DQogICAgICAgICAgICAgfQ0KICAg
ICAgICAgICAgIGVsc2UgaWYgKGkgPT0gT3ZlcmxheTo6T3ZlcmxheVRvdWNoQnV0dG9uTWVudSB8
fCBpID09IE92ZXJsYXk6Ok92ZXJsYXlUb3VjaEJ1dHRvbktiZCB8fA0KICAgICAgICAgICAgICAg
ICAgICAgIGkgPT0gT3ZlcmxheTo6T3ZlcmxheVRvdWNoQnV0dG9uVG91Y2hNb2RlKSB7DQpkaWZm
IC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3NkbHZpZC5jcHAg
Yi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvc2RsdmlkLmNwcAppbmRleCA1
NjdiZjE5Li5mMTMyNWVkIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1y
ZW5kZXJlcnMvc2RsdmlkLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5k
ZXJlcnMvc2RsdmlkLmNwcApAQCAtMjQxLDExICsyNDEsMTEgQEAgdm9pZCBTZGxSZW5kZXJlcjo6
cmVuZGVyT3ZlcmxheShPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBlKQogICAgICAgICAgICAgICAg
IG1fT3ZlcmxheVJlY3RzW3R5cGVdLnggPSAwOwogICAgICAgICAgICAgICAgIG1fT3ZlcmxheVJl
Y3RzW3R5cGVdLnkgPSB2aWV3cG9ydFJlY3QuaCAtIG5ld1N1cmZhY2UtPmg7CiAgICAgICAgICAg
ICB9Ci0gICAgICAgICAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1Zykg
eworICAgICAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwg
dHlwZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAgICAgICAg
IC8vIFZpYmVtaXM6IHVzZXItY29uZmlndXJhYmxlIGNvcm5lciAoU0RMIG9yaWdpbiBpcyB1cHBl
ci1sZWZ0KS4KICAgICAgICAgICAgICAgICBTRExfUmVjdCB2aWV3cG9ydFJlY3Q7CiAgICAgICAg
ICAgICAgICAgU0RMX1JlbmRlckdldFZpZXdwb3J0KG1fUmVuZGVyZXIsICZ2aWV3cG9ydFJlY3Qp
OwotICAgICAgICAgICAgICAgIGludCBhbmNob3IgPSBTZXNzaW9uOjpnZXQoKS0+Z2V0T3Zlcmxh
eU1hbmFnZXIoKS5nZXREZWJ1Z092ZXJsYXlBbmNob3IoKTsKKyAgICAgICAgICAgICAgICBpbnQg
YW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0T3ZlcmxheUFu
Y2hvcih0eXBlKTsKICAgICAgICAgICAgICAgICBib29sIHJpZ2h0ID0gKGFuY2hvciA9PSAxIHx8
IGFuY2hvciA9PSAzKTsgIC8vIFRSIG9yIEJSCiAgICAgICAgICAgICAgICAgYm9vbCBib3R0b20g
PSAoYW5jaG9yID09IDIgfHwgYW5jaG9yID09IDMpOyAvLyBCTCBvciBCUgogICAgICAgICAgICAg
ICAgIG1fT3ZlcmxheVJlY3RzW3R5cGVdLnggPSByaWdodCA/ICh2aWV3cG9ydFJlY3QudyAtIG5l
d1N1cmZhY2UtPncpIDogMDsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVn
LXJlbmRlcmVycy92YWFwaS5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJl
cnMvdmFhcGkuY3BwCmluZGV4IGFiNjVlMGIuLjI4NDNmZDYgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJl
YW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92YWFwaS5jcHAKKysrIGIvYXBwL3N0cmVhbWlu
Zy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3ZhYXBpLmNwcApAQCAtNzQxLDkgKzc0MSw5IEBAIHZv
aWQgVkFBUElSZW5kZXJlcjo6bm90aWZ5T3ZlcmxheVVwZGF0ZWQoT3ZlcmxheTo6T3ZlcmxheVR5
cGUgdHlwZSkKICAgICAgICAgICAgIG92ZXJsYXlSZWN0LnggPSAwOwogICAgICAgICAgICAgb3Zl
cmxheVJlY3QueSA9IC1uZXdTdXJmYWNlLT5oOwogICAgICAgICB9Ci0gICAgICAgIGVsc2UgaWYg
KHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7CisgICAgICAgIGVsc2UgaWYgKHR5cGUg
PT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8IHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheUxvY2Fs
SGFyZHdhcmUpIHsKICAgICAgICAgICAgIC8vIFZpYmVtaXM6IHVzZXItY29uZmlndXJhYmxlIGNv
cm5lciAodXBwZXItbGVmdCBvcmlnaW4pLgotICAgICAgICAgICAgaW50IGFuY2hvciA9IFNlc3Np
b246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmdldERlYnVnT3ZlcmxheUFuY2hvcigpOwor
ICAgICAgICAgICAgaW50IGFuY2hvciA9IFNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdl
cigpLmdldE92ZXJsYXlBbmNob3IodHlwZSk7CiAgICAgICAgICAgICBib29sIHJpZ2h0ID0gKGFu
Y2hvciA9PSAxIHx8IGFuY2hvciA9PSAzKTsgIC8vIFRSIG9yIEJSCiAgICAgICAgICAgICBib29s
IGJvdHRvbSA9IChhbmNob3IgPT0gMiB8fCBhbmNob3IgPT0gMyk7IC8vIEJMIG9yIEJSCiAgICAg
ICAgICAgICBvdmVybGF5UmVjdC54ID0gcmlnaHQgPyAobV9EaXNwbGF5V2lkdGggLSBuZXdTdXJm
YWNlLT53KSA6IDA7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5k
ZXJlcnMvdmRwYXUuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3Zk
cGF1LmNwcAppbmRleCAyZjllMGMzLi45MDZhY2NjIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5n
L3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdmRwYXUuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlk
ZW8vZmZtcGVnLXJlbmRlcmVycy92ZHBhdS5jcHAKQEAgLTQzNiw5ICs0MzYsOSBAQCB2b2lkIFZE
UEFVUmVuZGVyZXI6Om5vdGlmeU92ZXJsYXlVcGRhdGVkKE92ZXJsYXk6Ok92ZXJsYXlUeXBlIHR5
cGUpCiAgICAgICAgICAgICBvdmVybGF5UmVjdC54MCA9IDA7CiAgICAgICAgICAgICBvdmVybGF5
UmVjdC55MCA9IG1fRGlzcGxheUhlaWdodCAtIG5ld1N1cmZhY2UtPmg7CiAgICAgICAgIH0KLSAg
ICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICAgICAg
ZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgdHlwZSA9PSBPdmVybGF5
OjpPdmVybGF5TG9jYWxIYXJkd2FyZSkgewogICAgICAgICAgICAgLy8gVmliZW1pczogdXNlci1j
b25maWd1cmFibGUgY29ybmVyICh1cHBlci1sZWZ0IG9yaWdpbikuCi0gICAgICAgICAgICBpbnQg
YW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuZ2V0RGVidWdPdmVy
bGF5QW5jaG9yKCk7CisgICAgICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdl
dE92ZXJsYXlNYW5hZ2VyKCkuZ2V0T3ZlcmxheUFuY2hvcih0eXBlKTsKICAgICAgICAgICAgIGJv
b2wgcmlnaHQgPSAoYW5jaG9yID09IDEgfHwgYW5jaG9yID09IDMpOyAgLy8gVFIgb3IgQlIKICAg
ICAgICAgICAgIGJvb2wgYm90dG9tID0gKGFuY2hvciA9PSAyIHx8IGFuY2hvciA9PSAzKTsgLy8g
Qkwgb3IgQlIKICAgICAgICAgICAgIG92ZXJsYXlSZWN0LngwID0gcmlnaHQgPyAobV9EaXNwbGF5
V2lkdGggLSBuZXdTdXJmYWNlLT53KSA6IDA7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3Zp
ZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdnRfYXZzYW1wbGVsYXllci5tbSBiL2FwcC9zdHJlYW1pbmcv
dmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9hdnNhbXBsZWxheWVyLm1tCmluZGV4IGJkNTUyODEu
LjEzZDg4YzYgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVy
cy92dF9hdnNhbXBsZWxheWVyLm1tCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJl
bmRlcmVycy92dF9hdnNhbXBsZWxheWVyLm1tCkBAIC00OTYsNiArNDk2LDcgQEAgcHVibGljOgog
ICAgICAgICAgICAgW21fT3ZlcmxheVRleHRGaWVsZHNbdHlwZV0gc2V0U2VsZWN0YWJsZTpOT107
CiAKICAgICAgICAgICAgIHN3aXRjaCAodHlwZSkgeworICAgICAgICAgICAgY2FzZSBPdmVybGF5
OjpPdmVybGF5TG9jYWxIYXJkd2FyZToKICAgICAgICAgICAgIGNhc2UgT3ZlcmxheTo6T3Zlcmxh
eURlYnVnOgogICAgICAgICAgICAgICAgIFttX092ZXJsYXlUZXh0RmllbGRzW3R5cGVdIHNldEFs
aWdubWVudDpOU1RleHRBbGlnbm1lbnRMZWZ0XTsKICAgICAgICAgICAgICAgICBicmVhazsKZGlm
ZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9tZXRhbC5t
bSBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92dF9tZXRhbC5tbQppbmRl
eCA3OWIxNjVkLi4zMzRlZWZmIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBl
Zy1yZW5kZXJlcnMvdnRfbWV0YWwubW0KKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWct
cmVuZGVyZXJzL3Z0X21ldGFsLm1tCkBAIC02MDAsNyArNjAwLDcgQEAgcHVibGljOgogICAgICAg
ICAgICAgICAgICAgICByZW5kZXJSZWN0LnggPSAwOwogICAgICAgICAgICAgICAgICAgICByZW5k
ZXJSZWN0LnkgPSAwOwogICAgICAgICAgICAgICAgIH0KLSAgICAgICAgICAgICAgICBlbHNlIGlm
IChpID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZykgeworICAgICAgICAgICAgICAgIGVsc2UgaWYg
KGkgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8IGkgPT0gT3ZlcmxheTo6T3ZlcmxheUxvY2Fs
SGFyZHdhcmUpIHsKICAgICAgICAgICAgICAgICAgICAgLy8gVG9wIGxlZnQKICAgICAgICAgICAg
ICAgICAgICAgcmVuZGVyUmVjdC54ID0gMDsKICAgICAgICAgICAgICAgICAgICAgcmVuZGVyUmVj
dC55ID0gbV9MYXN0RHJhd2FibGVIZWlnaHQgLSBvdmVybGF5VGV4dHVyZS5oZWlnaHQ7CmRpZmYg
LS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy5jcHAgYi9hcHAvc3RyZWFtaW5nL3Zp
ZGVvL2ZmbXBlZy5jcHAKaW5kZXggMmFjMWE2ZS4uNGE2ZTBjMCAxMDA2NDQKLS0tIGEvYXBwL3N0
cmVhbWluZy92aWRlby9mZm1wZWcuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVn
LmNwcApAQCAtMSw1ICsxLDYgQEAKICNpbmNsdWRlIDxMaW1lbGlnaHQuaD4KICNpbmNsdWRlICJm
Zm1wZWcuaCIKKyNpbmNsdWRlICJtb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmgiCiAjaW5jbHVk
ZSAic3RyZWFtaW5nL3Nlc3Npb24uaCIKICNpbmNsdWRlICJiYWNrZW5kL3N5c3RlbXByb3BlcnRp
ZXMuaCIKICNpbmNsdWRlICJzZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5oIgpAQCAtMjQ0
MCw2ICsyNDQxLDExIEBAIGludCBGRm1wZWdWaWRlb0RlY29kZXI6OnN1Ym1pdERlY29kZVVuaXQo
UERFQ09ERV9VTklUIGR1KQogICAgICAgICAgICAgU2Vzc2lvbjo6Z2V0KCktPmdldE92ZXJsYXlN
YW5hZ2VyKCkuc2V0T3ZlcmxheVRleHRVcGRhdGVkKE92ZXJsYXk6Ok92ZXJsYXlEZWJ1Zyk7CiAg
ICAgICAgIH0KIAorICAgICAgICBpZihTZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIo
KS5pc092ZXJsYXlFbmFibGVkKE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlKSkgeworICAg
ICAgICAgICAgUUJ5dGVBcnJheSB0ZXh0PUxvY2FsSGFyZHdhcmU6Om92ZXJsYXlUZXh0KCkudG9V
dGY4KCk7CisgICAgICAgICAgICBTZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS51
cGRhdGVPdmVybGF5VGV4dChPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2FyZSx0ZXh0LmNvbnN0
RGF0YSgpKTsKKyAgICAgICAgfQorCiAgICAgICAgIC8vIEFjY3VtdWxhdGUgdGhlc2UgdmFsdWVz
IGludG8gdGhlIGdsb2JhbCBzdGF0cwogICAgICAgICBhZGRWaWRlb1N0YXRzKG1fQWN0aXZlV25k
VmlkZW9TdGF0cywgbV9HbG9iYWxWaWRlb1N0YXRzKTsKIApkaWZmIC0tZ2l0IGEvYXBwL3N0cmVh
bWluZy92aWRlby9vdmVybGF5bWFuYWdlci5jcHAgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJs
YXltYW5hZ2VyLmNwcAppbmRleCA5MmU2YzZkLi40ODNmZmRiIDEwMDY0NAotLS0gYS9hcHAvc3Ry
ZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5hZ2VyLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVv
L292ZXJsYXltYW5hZ2VyLmNwcApAQCAtMSw2ICsxLDEyIEBACiAjaW5jbHVkZSAib3ZlcmxheW1h
bmFnZXIuaCIKICNpbmNsdWRlICJwYXRoLmgiCiAjaW5jbHVkZSAic2V0dGluZ3Mvc3RyZWFtaW5n
cHJlZmVyZW5jZXMuaCIKKyNpbmNsdWRlICJtb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmgiCisj
aW5jbHVkZSAibW9vbmxpZ2h0b3Mvb3ZlcmxheXN0eWxlLmgiCisjaW5jbHVkZSA8UVNldHRpbmdz
PgorI2luY2x1ZGUgPFFJbWFnZT4KKyNpbmNsdWRlIDxRUGFpbnRlcj4KKyNpbmNsdWRlIDxRQ29s
b3I+CiAKIHVzaW5nIG5hbWVzcGFjZSBPdmVybGF5OwogCkBAIC05LDYgKzE1LDEzIEBAIGludCBP
dmVybGF5TWFuYWdlcjo6Z2V0RGVidWdPdmVybGF5QW5jaG9yKCkKICAgICByZXR1cm4gc3RhdGlj
X2Nhc3Q8aW50PihTdHJlYW1pbmdQcmVmZXJlbmNlczo6Z2V0KCktPnBlcmZPdmVybGF5UG9zaXRp
b24pOwogfQogCitpbnQgT3ZlcmxheU1hbmFnZXI6OmdldE92ZXJsYXlBbmNob3IoT3ZlcmxheVR5
cGUgdHlwZSkgeworICAgIGludCBzdHJlYW09Z2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAg
aWYodHlwZSE9T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHJldHVybiBzdHJlYW07CisgICAgaW50IGxv
Y2FsPXFCb3VuZCgwLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL2xvY2FsUG9zaXRpb24iLDEp
LnRvSW50KCksMyk7CisgICAgcmV0dXJuIGlzT3ZlcmxheUVuYWJsZWQoT3ZlcmxheURlYnVnKSAm
JiBsb2NhbD09c3RyZWFtID8gKGxvY2FsIF4gMSkgOiBsb2NhbDsKK30KKwogT3ZlcmxheU1hbmFn
ZXI6Ok92ZXJsYXlNYW5hZ2VyKCkgOgogICAgIG1fUmVuZGVyZXIobnVsbHB0ciksCiAgICAgbV9G
b250RGF0YShQYXRoOjpyZWFkRGF0YUZpbGUoIk1vZGVTZXZlbi50dGYiKSkKQEAgLTMyLDggKzQ1
LDEwIEBAIE92ZXJsYXlNYW5hZ2VyOjpPdmVybGF5TWFuYWdlcigpIDoKICAgICAgICAgYnJlYWs7
CiAgICAgfQogCi0gICAgbV9PdmVybGF5c1tPdmVybGF5VHlwZTo6T3ZlcmxheURlYnVnXS5jb2xv
ciA9IHsweEQwLCAweEQwLCAweDAwLCAweEZGfTsKKyAgICBtX092ZXJsYXlzW092ZXJsYXlUeXBl
OjpPdmVybGF5RGVidWddLmNvbG9yID0gezB4RUMsIDB4RUUsIDB4RjEsIDB4RkZ9OwogICAgIG1f
T3ZlcmxheXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlEZWJ1Z10uZm9udFNpemUgPSBkZWJ1Z0ZvbnRT
aXplOworICAgIG1fT3ZlcmxheXNbT3ZlcmxheUxvY2FsSGFyZHdhcmVdLmNvbG9yID0gezB4RUMs
MHhFRSwweEYxLDB4RkZ9OworICAgIG1fT3ZlcmxheXNbT3ZlcmxheUxvY2FsSGFyZHdhcmVdLmZv
bnRTaXplID0gZGVidWdGb250U2l6ZTsKIAogICAgIG1fT3ZlcmxheXNbT3ZlcmxheVR5cGU6Ok92
ZXJsYXlTdGF0dXNVcGRhdGVdLmNvbG9yID0gezB4Q0MsIDB4MDAsIDB4MDAsIDB4RkZ9OwogICAg
IG1fT3ZlcmxheXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlTdGF0dXNVcGRhdGVdLmZvbnRTaXplID0g
MzY7CkBAIC0xMjYsNiArMTQxLDEwIEBAIFNETF9TdXJmYWNlKiBPdmVybGF5TWFuYWdlcjo6Z2V0
VXBkYXRlZE92ZXJsYXlTdXJmYWNlKE92ZXJsYXlUeXBlIHR5cGUpCiAKIHZvaWQgT3ZlcmxheU1h
bmFnZXI6OnNldE92ZXJsYXlUZXh0VXBkYXRlZChPdmVybGF5VHlwZSB0eXBlKQogeworICAgIGlm
KG1fT3ZlcmxheXNbdHlwZV0uZW5hYmxlZCAmJiAodHlwZT09T3ZlcmxheURlYnVnIHx8IHR5cGU9
PU92ZXJsYXlMb2NhbEhhcmR3YXJlKSkgeworICAgICAgICBRTXV0ZXhMb2NrZXIgZ3JhcGhMb2Nr
KCZtX0dyYXBoTG9jayk7CisgICAgICAgIENyaW1zb25HcmFwaHM6OnB1c2gobV9HcmFwaEhpc3Rv
cnlbdHlwZV0sQ3JpbXNvbkdyYXBoczo6dmFsdWVzKFFTdHJpbmc6OmZyb21VdGY4KG1fT3Zlcmxh
eXNbdHlwZV0udGV4dCksdHlwZT09T3ZlcmxheUxvY2FsSGFyZHdhcmUsTG9jYWxIYXJkd2FyZTo6
c2FtcGxlKCkpKTsKKyAgICB9CiAgICAgLy8gT25seSB1cGRhdGUgdGhlIG92ZXJsYXkgc3RhdGUg
aWYgaXQncyBlbmFibGVkLiBJZiBpdCdzIG5vdCBlbmFibGVkLAogICAgIC8vIHRoZSByZW5kZXJl
ciBoYXMgYWxyZWFkeSBiZWVuIG5vdGlmaWVkIGJ5IHNldE92ZXJsYXlTdGF0ZSgpLgogICAgIGlm
IChtX092ZXJsYXlzW3R5cGVdLmVuYWJsZWQpIHsKQEAgLTE0Myw2ICsxNjIsNyBAQCB2b2lkIE92
ZXJsYXlNYW5hZ2VyOjpzZXRPdmVybGF5U3RhdGUoT3ZlcmxheVR5cGUgdHlwZSwgYm9vbCBlbmFi
bGVkKQogICAgICAgICBpZiAoIWVuYWJsZWQpIHsKICAgICAgICAgICAgIC8vIFNldCB0aGUgdGV4
dCB0byBlbXB0eSBzdHJpbmcgb24gZGlzYWJsZQogICAgICAgICAgICAgbV9PdmVybGF5c1t0eXBl
XS50ZXh0WzBdID0gMDsKKyAgICAgICAgICAgIHsgUU11dGV4TG9ja2VyIGdyYXBoTG9jaygmbV9H
cmFwaExvY2spO21fR3JhcGhIaXN0b3J5W3R5cGVdLmNsZWFyKCk7IH0KICAgICAgICAgfQogCiAg
ICAgICAgIG5vdGlmeU92ZXJsYXlVcGRhdGVkKHR5cGUpOwpAQCAtMzY4LDExICszODgsMjcgQEAg
dm9pZCBPdmVybGF5TWFuYWdlcjo6bm90aWZ5T3ZlcmxheVVwZGF0ZWQoT3ZlcmxheVR5cGUgdHlw
ZSkKICAgICB9CiAKICAgICBpZiAobV9PdmVybGF5c1t0eXBlXS5lbmFibGVkKSB7Ci0gICAgICAg
IC8vIFRoZSBfV3JhcHBlZCB2YXJpYW50IGlzIHJlcXVpcmVkIGZvciBsaW5lIGJyZWFrcyB0byB3
b3JrCi0gICAgICAgIFNETF9TdXJmYWNlKiBzdXJmYWNlID0gVFRGX1JlbmRlclRleHRfQmxlbmRl
ZF9XcmFwcGVkKG1fT3ZlcmxheXNbdHlwZV0uZm9udCwKLSAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgbV9PdmVybGF5c1t0eXBlXS50
ZXh0LAotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICBtX092ZXJsYXlzW3R5cGVdLmNvbG9yLAotICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAxMDI0KTsKKyAgICAgICAg
UUJ5dGVBcnJheSB0ZXh0KG1fT3ZlcmxheXNbdHlwZV0udGV4dCk7CisgICAgICAgIGNvbnN0IGJv
b2wgY2FyZD10eXBlPT1PdmVybGF5RGVidWcgfHwgdHlwZT09T3ZlcmxheUxvY2FsSGFyZHdhcmU7
CisgICAgICAgIGNvbnN0IGJvb2wgZGV0YWlsZWQ9UVNldHRpbmdzKCkudmFsdWUodHlwZT09T3Zl
cmxheURlYnVnPyJlY2xpcHNlL3N0cmVhbURldGFpbGVkIjoiZWNsaXBzZS9sb2NhbERldGFpbGVk
IixmYWxzZSkudG9Cb29sKCk7CisgICAgICAgIGlmKGNhcmQgJiYgIWRldGFpbGVkKSB0ZXh0PSh0
eXBlPT1PdmVybGF5RGVidWc/IkVjbGlwc2VPUyB8IFNUUkVBTSI6IkVjbGlwc2VPUyB8IExPQ0FM
Iik7CisgICAgICAgIGVsc2UgaWYodHlwZT09T3ZlcmxheURlYnVnKSB0ZXh0LnByZXBlbmQoIkVj
bGlwc2VPUyB8IFNUUkVBTVxuIik7CisgICAgICAgIFNETF9TdXJmYWNlKiBzdXJmYWNlPVRURl9S
ZW5kZXJVVEY4X0JsZW5kZWRfV3JhcHBlZChtX092ZXJsYXlzW3R5cGVdLmZvbnQsdGV4dC5jb25z
dERhdGEoKSxtX092ZXJsYXlzW3R5cGVdLmNvbG9yLGNhcmQ/NDgwOjEwMjQpOworICAgICAgICBp
ZihjYXJkICYmIHN1cmZhY2UpIHsKKyAgICAgICAgICAgIGludCBmb250U2l6ZT1tX092ZXJsYXlz
W3R5cGVdLmZvbnRTaXplOworICAgICAgICAgICAgaW50IGdyYXBoSGVpZ2h0PTQqKGZvbnRTaXpl
KzIyKSsxMjsKKyAgICAgICAgICAgIGludCB3aWR0aD1xTWF4KHN1cmZhY2UtPncrMzIsNDgwKTsK
KyAgICAgICAgICAgIFFJbWFnZSBpbWFnZT1FY2xpcHNlT3ZlcmxheVN0eWxlOjpwYW5lbChRU2l6
ZSh3aWR0aCxzdXJmYWNlLT5oKzMyK2dyYXBoSGVpZ2h0KSxTdHJlYW1pbmdQcmVmZXJlbmNlczo6
Z2V0KCktPnVpQWNjZW50SW5kZXgsUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2Uvb3ZlcmxheU9w
YWNpdHkiLDg1KS50b0ludCgpKTsKKyAgICAgICAgICAgIENyaW1zb25HcmFwaHM6Okhpc3Rvcnkg
aGlzdG9yeTsKKyAgICAgICAgICAgIHsgUU11dGV4TG9ja2VyIGdyYXBoTG9jaygmbV9HcmFwaExv
Y2spO2hpc3Rvcnk9bV9HcmFwaEhpc3RvcnlbdHlwZV07IH0KKyAgICAgICAgICAgIGlmKCFpbWFn
ZS5pc051bGwoKSkgQ3JpbXNvbkdyYXBoczo6cGFpbnQoaW1hZ2Usc3VyZmFjZS0+aCsyNCxxTWlu
KGZvbnRTaXplLDIwKSxTdHJlYW1pbmdQcmVmZXJlbmNlczo6Z2V0KCktPnVpQWNjZW50SW5kZXgs
aGlzdG9yeSx0eXBlPT1PdmVybGF5TG9jYWxIYXJkd2FyZSk7CisgICAgICAgICAgICBTRExfU3Vy
ZmFjZSogcGFuZWw9aW1hZ2UuaXNOdWxsKCk/bnVsbHB0cjpTRExfQ3JlYXRlUkdCU3VyZmFjZVdp
dGhGb3JtYXQoMCxpbWFnZS53aWR0aCgpLGltYWdlLmhlaWdodCgpLDMyLFNETF9QSVhFTEZPUk1B
VF9SR0JBMzIpOworICAgICAgICAgICAgaWYocGFuZWwpIHsKKyAgICAgICAgICAgICAgICBmb3Io
aW50IHJvdz0wO3JvdzxpbWFnZS5oZWlnaHQoKTsrK3JvdykgbWVtY3B5KHN0YXRpY19jYXN0PGNo
YXIqPihwYW5lbC0+cGl4ZWxzKStyb3cqcGFuZWwtPnBpdGNoLGltYWdlLmNvbnN0U2NhbkxpbmUo
cm93KSxpbWFnZS53aWR0aCgpKjQpOworICAgICAgICAgICAgICAgIFNETF9SZWN0IGRlc3Q9ezE2
LDE2LHN1cmZhY2UtPncsc3VyZmFjZS0+aH07U0RMX0JsaXRTdXJmYWNlKHN1cmZhY2UsbnVsbHB0
cixwYW5lbCwmZGVzdCk7CisgICAgICAgICAgICAgICAgU0RMX0ZyZWVTdXJmYWNlKHN1cmZhY2Up
O3N1cmZhY2U9cGFuZWw7CisgICAgICAgICAgICB9CisgICAgICAgIH0KIAogICAgICAgICBTRExf
QXRvbWljU2V0UHRyKCh2b2lkKiopJm1fT3ZlcmxheXNbdHlwZV0uc3VyZmFjZSwgc3VyZmFjZSk7
CiAgICAgfQpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9vdmVybGF5bWFuYWdlci5o
IGIvYXBwL3N0cmVhbWluZy92aWRlby9vdmVybGF5bWFuYWdlci5oCmluZGV4IGUxOWZjMGMuLjQx
MTJhMWQgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vb3ZlcmxheW1hbmFnZXIuaAor
KysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5hZ2VyLmgKQEAgLTIsNiArMiw3IEBA
CiAKICNpbmNsdWRlIDxRU3RyaW5nPgogI2luY2x1ZGUgPFFNdXRleD4KKyNpbmNsdWRlICJtb29u
bGlnaHRvcy9jcmltc29uZ3JhcGhzLmgiCiAKICNpbmNsdWRlICJTRExfY29tcGF0LmgiCiAjaW5j
bHVkZSA8U0RMX3R0Zi5oPgpAQCAtMTAsNiArMTEsNyBAQCBuYW1lc3BhY2UgT3ZlcmxheSB7CiAK
IGVudW0gT3ZlcmxheVR5cGUgewogICAgIE92ZXJsYXlEZWJ1ZywKKyAgICBPdmVybGF5TG9jYWxI
YXJkd2FyZSwKICAgICBPdmVybGF5U3RhdHVzVXBkYXRlLAogICAgIE92ZXJsYXlTZXJ2ZXJDb21t
YW5kcywKICAgICBPdmVybGF5UXVpY2tNZW51LApAQCAtNzAsNiArNzIsNyBAQCBwdWJsaWM6CiAg
ICAgLy8gcHJlZmVyZW5jZS4gUmV0dXJucyBTdHJlYW1pbmdQcmVmZXJlbmNlczo6UGVyZk92ZXJs
YXlQb3NpdGlvbiBhcyBhbiBpbnQKICAgICAvLyAoMD1UTCwgMT1UUiwgMj1CTCwgMz1CUikuIFJl
bmRlcmVycyBtYXAgdGhpcyB0byB0aGVpciBvd24gY29vcmRpbmF0ZSBzcGFjZS4KICAgICBpbnQg
Z2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAgaW50IGdldE92ZXJsYXlBbmNob3IoT3Zlcmxh
eVR5cGUgdHlwZSk7CiAKICAgICB2b2lkIHNldE92ZXJsYXlSZW5kZXJlcihJT3ZlcmxheVJlbmRl
cmVyKiByZW5kZXJlcik7CiAKQEAgLTExNyw2ICsxMjAsOCBAQCBwcml2YXRlOgogICAgIElPdmVy
bGF5UmVuZGVyZXIqIG1fUmVuZGVyZXI7CiAgICAgUU11dGV4IG1fUmVuZGVyZXJMb2NrOyAgIC8v
IGd1YXJkcyBtX1JlbmRlcmVyIHN3YXAgdnMgY3Jvc3MtdGhyZWFkIG5vdGlmeQogICAgIFFCeXRl
QXJyYXkgbV9Gb250RGF0YTsKKyAgICBRTXV0ZXggbV9HcmFwaExvY2s7CisgICAgQ3JpbXNvbkdy
YXBoczo6SGlzdG9yeSBtX0dyYXBoSGlzdG9yeVtPdmVybGF5TWF4XTsKIH07CiAKIH0KZGlmZiAt
LWdpdCBhL3BhY2thZ2luZy9mbGF0cGFrL2lvLmdpdGh1Yi5uYXZ5YXMzMjEuVmliZW1pcy5kZXNr
dG9wIGIvcGFja2FnaW5nL2ZsYXRwYWsvaW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0
b3AKaW5kZXggMDQ1YWRiZS4uZjEyZGE1ZCAxMDA2NDQKLS0tIGEvcGFja2FnaW5nL2ZsYXRwYWsv
aW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AKKysrIGIvcGFja2FnaW5nL2ZsYXRw
YWsvaW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AKQEAgLTEsNiArMSw2IEBACiBb
RGVza3RvcCBFbnRyeV0KIFR5cGU9QXBwbGljYXRpb24KLU5hbWU9VmliZW1pcworTmFtZT1FY2xp
cHNlCiBHZW5lcmljTmFtZT1HYW1lIFN0cmVhbWluZyBDbGllbnQKIENvbW1lbnQ9U3RyZWFtIGdh
bWVzIGFuZCBhcHBsaWNhdGlvbnMgZnJvbSBhIFN1bnNoaW5lIC8gQXBvbGxvIC8gVmliZXBvbGxv
IGhvc3QKIEV4ZWM9dmliZW1pcwo=
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
