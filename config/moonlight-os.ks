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
    return state


def percent(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{1,3}', value) or not 0 <= int(value) <= 100:
        raise ValueError('Choose a value from 0 to 100.')
    return int(value)


def execute(request, state):
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


def answer(prompt):
    emit(prompt=prompt)
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
        self.mode = "bt"
        result = []
        for address, name in self.bt.devices(self.bt.ctl('devices'))[:64]:
            state = self.bt.properties(address)
            result.append(dict(id=address, address=address, name=name,
                               detail='Paired' if state.get('Paired') == 'yes' else 'Not paired',
                               connected=state.get('Connected') == 'yes'))
        self.items = result
        return result

    def bt_scan(self):
        self.bt.ready()
        if self.agent is None:
            self.agent = self.bt.Agent()
        child = self.agent.child
        child.sendline('scan on')
        event = child.expect(['Discovery started', r'Failed to start discovery:[^\r\n]*',
                              pexpect.EOF, pexpect.TIMEOUT], timeout=15)
        if event != 0:
            raise RuntimeError('Bluetooth discovery did not start. Check the radio and retry.')
        try:
            end = time.monotonic() + 6
            while time.monotonic() < end:
                try:
                    child.read_nonblocking(4096, timeout=min(1, end-time.monotonic()))
                except pexpect.TIMEOUT:
                    pass
        finally:
            child.sendline('scan off')
        return self.bt_list()

    def execute(self, request):
        action = request.get('action')
        if isinstance(action, str) and action.startswith('center-'):
            import importlib.util
            source = Path(__file__).with_name('control-center.py')
            spec = importlib.util.spec_from_file_location('eclipse_control_center', source)
            module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
            result = module.execute(request, self.center_state)
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
                if not self.agent.pair(item['address'], answer=answer):
                    raise RuntimeError('Pairing was not completed. No saved bond was removed.')
                if self.bt.properties(item['address']).get('Paired') != 'yes':
                    raise RuntimeError('Pairing was not saved. Put the device back in pairing mode.')
            if not self.bt.connect(item['address']):
                raise RuntimeError('The device did not connect. Wake it and retry.')
        elif action == 'bt-disconnect':
            self.bt.ctl('disconnect', item['address'])
            if self.bt.properties(item['address']).get('Connected') == 'yes':
                raise RuntimeError('The device is still connected.')
        elif action == 'bt-forget':
            if request.get('confirm') is not True:
                raise ValueError('Forgetting a device requires confirmation.')
            self.bt.ctl('remove', item['address'])
            if any(address == item['address'] for address, _ in self.bt.devices(self.bt.ctl('devices'))):
                raise RuntimeError('The device could not be forgotten.')
        else:
            raise ValueError('Unsupported operation')
        return self.bt_list()

    def close(self):
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
                emit(**items, done=True) if isinstance(items, dict) else emit(items=items, status='Ready', done=True)
            except (EOFError, KeyboardInterrupt):
                break
            except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError, pexpect.ExceptionPexpect) as error:
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
    text = ctl('info', valid_mac(address))
    return dict(re.findall(r'^\s*(Paired|Trusted|Connected):\s*(yes|no)\s*$', text, re.M))


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
    subprocess.run(['sudo', 'systemctl', 'start', 'bluetooth.service'], check=True)
    subprocess.run(['sudo', 'rfkill', 'unblock', 'bluetooth'], check=True)
    shown = ctl('show')
    if not re.search(r'^Controller ' + MAC, shown, re.M):
        raise RuntimeError('No Bluetooth adapter found. Open Status to inspect the service/radio.')
    for command in [('power', 'on'), ('pairable', 'on')]:
        output = ctl(*command)
        if 'succeeded' not in output.lower() and 'successful' not in output.lower():
            raise RuntimeError(output.strip() or 'Unable to configure Bluetooth adapter')


def connect(address):
    print(ctl('trust', address).strip())
    print(ctl('connect', address).strip())
    state = properties(address)
    if state.get('Connected') != 'yes':
        print('Device is not connected. Pairing may be saved; wake the device and use Reconnect.')
        return False
    if state.get('Trusted') != 'yes':
        print('Connected, but trust was not saved. Reconnection may need confirmation.')
        return False
    print('Connected and trusted.')
    return True


def pair_device(airpods=False):
    ready()
    print('Put the device in pairing mode. Examples:')
    print('  PS4: SHARE + PS; PS5: CREATE + PS; Xbox: pairing button; Switch Pro: SYNC.')
    print('  AirPods: open the case and activate its setup control until the light flashes white.')
    print('Controllers, headphones, keyboards and mice all appear in the same list.')
    agent = Agent()
    try:
        # Keep this process and its default agent alive throughout discovery/selection/pairing.
        agent.child.sendline('scan on')
        event = agent.child.expect(['Discovery started', r'Failed to start discovery:[^\r\n]*',
                                   pexpect.EOF, pexpect.TIMEOUT], timeout=15)
        if event != 0:
            raise RuntimeError(clean(str(agent.child.after)) if event == 1 else 'Bluetooth discovery did not start')
        print('Scanning for 6 seconds... If your device is not listed, keep it in pairing mode and scan again.')
        end = time.monotonic() + 6
        while time.monotonic() < end:
            try:
                agent.child.read_nonblocking(4096, timeout=min(1, end-time.monotonic()))
            except pexpect.TIMEOUT:
                pass
        address = select_device(devices(ctl('devices')))
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
        try:
            agent.child.sendline('scan off')
        finally:
            agent.close()


def saved():
    return devices(ctl('devices', 'Paired'))


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
                        print(ctl('disconnect', address))
                    elif input('Forget this device and its saved pairing? Type yes: ').strip().lower() == 'yes':
                        print(ctl('remove', address))
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
VIBEMIS_PATCH_SHA256=2c002f07f89d74df200285aed2c74af5072a3e029f0023ec87e7478f55e8eaaf
FRONTENDS_LOCK
base64 -d > /usr/local/share/moonlight-os/vibemis-crimson.patch <<'VIBEMIS_PATCH_B64'
ZGlmZiAtLWdpdCBhL2FwcC9hcHAucHJvIGIvYXBwL2FwcC5wcm8KaW5kZXggYzE4ODZhNC4uZGQ4
NzcwMSAxMDA2NDQKLS0tIGEvYXBwL2FwcC5wcm8KKysrIGIvYXBwL2FwcC5wcm8KQEAgLTU3OSwx
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
LDMgKzYzMSwxNyBAQCBtYWN4IHsKICMgY291bnRzKSBvciB0aGUgc21hcnQtYnVpbGQgY2hlY2sg
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
c2Vwcm9maWxlcy5oCmRpZmYgLS1naXQgYS9hcHAvYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5o
IGIvYXBwL2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaAppbmRleCA1ZWI5OGNiLi43YmFlYTk4
IDEwMDY0NAotLS0gYS9hcHAvYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5oCisrKyBiL2FwcC9i
YWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgKQEAgLTI5LDYgKzI5LDkgQEAgY2xhc3MgQXV0b1Vw
ZGF0ZUNoZWNrZXIgOiBwdWJsaWMgUU9iamVjdAogewogICAgIFFfT0JKRUNUCiAKKyAgICAvLyBU
aGlzIGN1c3RvbWl6ZWQgYXBwbGlhbmNlIGlzIHVwZGF0ZWQgd2l0aCBFY2xpcHNlT1MsIG5ldmVy
IHVwc3RyZWFtIEFwcEltYWdlcy4KKyAgICBRX1BST1BFUlRZKGJvb2wgb3NNYW5hZ2VkIFJFQUQg
b3NNYW5hZ2VkIENPTlNUQU5UKQorCiAgICAgLy8gQSBzdHJpY3RseS1uZXdlciBidWlsZCBleGlz
dHMgb24gdGhlIGNoYW5uZWwg4oCUIHBvd2VycyB0aGUgdG9vbGJhciBiYW5uZXIuCiAgICAgUV9Q
Uk9QRVJUWShib29sIHVwZGF0ZUF2YWlsYWJsZSBSRUFEIHVwZGF0ZUF2YWlsYWJsZSBOT1RJRlkg
c3RhdGVDaGFuZ2VkKQogICAgIC8vIFRoZSBjaGFubmVsJ3MgbmV3ZXN0IGJ1aWxkIGRpZmZlcnMg
ZnJvbSB0aGUgcnVubmluZyBvbmUgKG1heSBiZSBvbGRlciDigJQKQEAgLTUxLDYgKzU0LDcgQEAg
Y2xhc3MgQXV0b1VwZGF0ZUNoZWNrZXIgOiBwdWJsaWMgUU9iamVjdAogCiBwdWJsaWM6CiAgICAg
ZXhwbGljaXQgQXV0b1VwZGF0ZUNoZWNrZXIoUU9iamVjdCAqcGFyZW50ID0gbnVsbHB0cik7Cisg
ICAgYm9vbCBvc01hbmFnZWQoKSBjb25zdCB7IHJldHVybiB0cnVlOyB9CiAKICAgICAvLyBMYXVu
Y2gtdGltZSBlbnRyeSBwb2ludDogcXVpZXQgY2hlY2sgbm93LCB0aGVuIGEgcGVyaW9kaWMgcmUt
Y2hlY2sgZXZlcnkKICAgICAvLyBSRUNIRUNLX0lOVEVSVkFMX01TIChhIGxhdW5jaC1vbmx5IGNo
ZWNrIGtlcHQgdXNlcnMgYmxpbmQgdG8gYW55dGhpbmcKZGlmZiAtLWdpdCBhL2FwcC9kZXBsb3kv
bGludXgvY29tLnZpYmVtaXMuVmliZW1pcy5kZXNrdG9wIGIvYXBwL2RlcGxveS9saW51eC9jb20u
dmliZW1pcy5WaWJlbWlzLmRlc2t0b3AKaW5kZXggMzRiOGZhZS4uMDM5ODg2OCAxMDA2NDQKLS0t
IGEvYXBwL2RlcGxveS9saW51eC9jb20udmliZW1pcy5WaWJlbWlzLmRlc2t0b3AKKysrIGIvYXBw
L2RlcGxveS9saW51eC9jb20udmliZW1pcy5WaWJlbWlzLmRlc2t0b3AKQEAgLTEsOCArMSw4IEBA
CiBbRGVza3RvcCBFbnRyeV0KLU5hbWU9VmliZW1pcwotQ29tbWVudD1MaW51eC1mb2N1c2VkIFZp
YmVtaXMgUXQgZm9yayB0dW5lZCBmb3IgcGFpcmluZyB3aXRoIFZpYmVwb2xsby4gU3RyZWFtcyBn
YW1lcyBhbmQgYXBwbGljYXRpb25zIGZyb20gYSBTdW5zaGluZSAvIEFwb2xsbyAvIFZpYmVwb2xs
byBob3N0LgorTmFtZT1FY2xpcHNlCitDb21tZW50PUVjbGlwc2Ug4oCUIHRoZSBFY2xpcHNlT1Mg
ZnJvbnRlbmQuIFN0cmVhbXMgZ2FtZXMgYW5kIGFwcGxpY2F0aW9ucyBmcm9tIGEgU3Vuc2hpbmUg
LyBBcG9sbG8gLyBWaWJlcG9sbG8gaG9zdC4KIEV4ZWM9dmliZW1pcwotSWNvbj12aWJlbWlzCitJ
Y29uPWVjbGlwc2UKIFN0YXJ0dXBXTUNsYXNzPWNvbS52aWJlbWlzLlZpYmVtaXMKIFRlcm1pbmFs
PWZhbHNlCiBUeXBlPUFwcGxpY2F0aW9uCmRpZmYgLS1naXQgYS9hcHAvZ3VpL0FwcFZpZXcucW1s
IGIvYXBwL2d1aS9BcHBWaWV3LnFtbAppbmRleCA2M2Y2NDVkLi4zODNhZGI3IDEwMDY0NAotLS0g
YS9hcHAvZ3VpL0FwcFZpZXcucW1sCisrKyBiL2FwcC9ndWkvQXBwVmlldy5xbWwKQEAgLTExLDYg
KzExLDcgQEAgaW1wb3J0IENvbXB1dGVyTWFuYWdlciAxLjAKIGltcG9ydCBTZGxHYW1lcGFkS2V5
TmF2aWdhdGlvbiAxLjAKIAogQ2VudGVyZWRHcmlkVmlldyB7CisgICAgcHJvcGVydHkgdmFyIGNy
aW1zb25Ib3N0OiAoe30pCiAgICAgcHJvcGVydHkgaW50IGNvbXB1dGVySW5kZXgKICAgICBwcm9w
ZXJ0eSBBcHBNb2RlbCBhcHBNb2RlbCA6IGNyZWF0ZU1vZGVsKCkKICAgICBwcm9wZXJ0eSBib29s
IGFjdGl2YXRlZApkaWZmIC0tZ2l0IGEvYXBwL2d1aS9BdXRvUmVzaXppbmdDb21ib0JveC5xbWwg
Yi9hcHAvZ3VpL0F1dG9SZXNpemluZ0NvbWJvQm94LnFtbAppbmRleCA1M2FmY2FmLi5mMTIzOTMy
IDEwMDY0NAotLS0gYS9hcHAvZ3VpL0F1dG9SZXNpemluZ0NvbWJvQm94LnFtbAorKysgYi9hcHAv
Z3VpL0F1dG9SZXNpemluZ0NvbWJvQm94LnFtbApAQCAtMSw1ICsxLDYgQEAKIGltcG9ydCBRdFF1
aWNrIDIuOQogaW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRl
c2lnbiAxLjAKIAogaW1wb3J0IFNkbEdhbWVwYWRLZXlOYXZpZ2F0aW9uIDEuMAogaW1wb3J0IFN5
c3RlbVByb3BlcnRpZXMgMS4wCkBAIC05Miw3ICs5Myw3IEBAIENvbWJvQm94IHsKICAgICAgICAg
Ly8gT3ZlcnJpZGUgdGhlIHBvcHVwIGNvbG9yIHRvIGltcHJvdmUgY29udHJhc3Qgd2l0aCB0aGUg
b3ZlcnJpZGRlbgogICAgICAgICAvLyBNYXRlcmlhbCAyIGJhY2tncm91bmQgY29sb3Igc2V0IGlu
IG1haW4ucW1sLgogICAgICAgICBpZiAoU3lzdGVtUHJvcGVydGllcy51c2VzTWF0ZXJpYWwzVGhl
bWUpIHsKLSAgICAgICAgICAgIHBvcHVwLmJhY2tncm91bmQuY29sb3IgPSAiIzQyNDI0MiIKKyAg
ICAgICAgICAgIHBvcHVwLmJhY2tncm91bmQuY29sb3IgPSBRdC5iaW5kaW5nKGZ1bmN0aW9uKCkg
eyByZXR1cm4gVmJUb2tlbnMuYmdFbGV2MiB9KQogICAgICAgICB9CiAgICAgfQogCmRpZmYgLS1n
aXQgYS9hcHAvZ3VpL0NyaW1zb25TdGF0dXNEaWFsb2cucW1sIGIvYXBwL2d1aS9Dcmltc29uU3Rh
dHVzRGlhbG9nLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi42ODcwZjlj
Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbApAQCAt
MCwwICsxLDkwIEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xz
IDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xz
Lk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgQ3JpbXNv
blN0YXR1cyAxLjAKKworTmF2aWdhYmxlRGlhbG9nIHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9w
ZXJ0eSBzdHJpbmcga2luZDogImhvc3QiCisgICAgd2lkdGg6IE1hdGgubWluKDYyMCwgcGFyZW50
LndpZHRoIC0gMzIpCisgICAgaGVpZ2h0OiBNYXRoLm1pbihraW5kID09PSAiaG9zdCIgPyA2NTAg
OiAyODAsIHBhcmVudC5oZWlnaHQgLSAzMikKKyAgICB0aXRsZToga2luZCA9PT0gImhvc3QiID8g
cXNUcigiVmliZXBvbGxvIOKAoiBIb3N0IGhhcmR3YXJlIikgOiBraW5kID09PSAibmV0d29yayIg
PyBxc1RyKCJOZXR3b3JrIHN0YXR1cyIpIDogcXNUcigiQmF0dGVyeSBzdGF0dXMiKQorICAgIHN0
YW5kYXJkQnV0dG9uczogRGlhbG9nLkNsb3NlCisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJU
b2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBi
YWNrZ3JvdW5kOiBSZWN0YW5nbGUgeyBjb2xvcjogVmJUb2tlbnMuYmdFbGV2OyByYWRpdXM6IFZi
VG9rZW5zLnJhZGl1c0RpYWxvZzsgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2U7IGJvcmRl
ci53aWR0aDogMSB9CisgICAgb25PcGVuZWQ6IHsKKyAgICAgICAgdXJsSW5wdXQudGV4dCA9IENy
aW1zb25TdGF0dXMuZW5kcG9pbnQKKyAgICAgICAgcGluSW5wdXQudGV4dCA9IENyaW1zb25TdGF0
dXMuZmluZ2VycHJpbnQKKyAgICAgICAgdG9rZW5JbnB1dC50ZXh0ID0gIiIKKyAgICAgICAgQ3Jp
bXNvblN0YXR1cy5zZXRWaXNpYmxlKGtpbmQgPT09ICJob3N0IikKKyAgICB9CisgICAgb25DbG9z
ZWQ6IHsgQ3JpbXNvblN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsgdG9rZW5JbnB1dC50ZXh0ID0g
IiI7IHN0YWNrVmlldy5mb3JjZUFjdGl2ZUZvY3VzKCkgfQorICAgIGZ1bmN0aW9uIG1ldHJpYyhr
ZXksIHN1ZmZpeCkgeworICAgICAgICB2YXIgbiA9IENyaW1zb25TdGF0dXMuc3RhdHNba2V5XQor
ICAgICAgICByZXR1cm4gbiA9PT0gdW5kZWZpbmVkID8gcXNUcigiTi9BIikgOiBOdW1iZXIobiku
dG9GaXhlZCgxKSArIHN1ZmZpeAorICAgIH0KKyAgICBmdW5jdGlvbiBtZW1vcnkocHJlZml4KSB7
CisgICAgICAgIHZhciBzID0gQ3JpbXNvblN0YXR1cy5zdGF0cworICAgICAgICByZXR1cm4gc1tw
cmVmaXggKyAiX3VzZWRfYnl0ZXMiXSA9PT0gdW5kZWZpbmVkIHx8ICFzW3ByZWZpeCArICJfdG90
YWxfYnl0ZXMiXSA/IHFzVHIoIk4vQSIpCisgICAgICAgICAgICAgOiAoc1twcmVmaXggKyAiX3Vz
ZWRfYnl0ZXMiXSAvIDEwNzM3NDE4MjQpLnRvRml4ZWQoMSkgKyAiIC8gIiArIChzW3ByZWZpeCAr
ICJfdG90YWxfYnl0ZXMiXSAvIDEwNzM3NDE4MjQpLnRvRml4ZWQoMSkgKyAiIEdpQiIKKyAgICB9
CisgICAgY29udGVudEl0ZW06IFNjcm9sbFZpZXcgeworICAgICAgICBjbGlwOiB0cnVlCisgICAg
ICAgIGNvbnRlbnRXaWR0aDogYXZhaWxhYmxlV2lkdGgKKyAgICAgICAgQ29sdW1uTGF5b3V0IHsK
KyAgICAgICAgICAgIHdpZHRoOiBwYW5lbC5hdmFpbGFibGVXaWR0aAorICAgICAgICAgICAgc3Bh
Y2luZzogVmJUb2tlbnMuc3BhY2UzCisgICAgICAgICAgICBMYWJlbCB7CisgICAgICAgICAgICAg
ICAgdmlzaWJsZTogcGFuZWwua2luZCAhPT0gImhvc3QiCisgICAgICAgICAgICAgICAgTGF5b3V0
LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcAorICAgICAgICAgICAgICAgIHRl
eHQ6IHBhbmVsLmtpbmQgPT09ICJuZXR3b3JrIiA/IChDcmltc29uU3RhdHVzLmxvY2FsLm5ldHdv
cmsgKyAoQ3JpbXNvblN0YXR1cy5sb2NhbC53aWZpU2lnbmFsID49IDAgPyAiIOKAoiAiICsgQ3Jp
bXNvblN0YXR1cy5sb2NhbC53aWZpU2lnbmFsICsgIiUgc2lnbmFsIiA6ICIiKSArICJcbiIgKyBx
c1RyKCJBY3RpdmUgbGluayBzdGF0dXM7IGludGVybmV0IGFjY2VzcyBpcyBub3QgYXNzdW1lZC4i
KSkKKyAgICAgICAgICAgICAgICAgICAgOiAoQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVy
Y2VudCA+PSAwID8gQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCArICIlIOKAoiAi
IDogIiIpICsgQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5U3RhdGUKKyAgICAgICAgICAgICAg
ICBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVCb2R5
CisgICAgICAgICAgICB9CisgICAgICAgICAgICBMYWJlbCB7CisgICAgICAgICAgICAgICAgdmlz
aWJsZTogcGFuZWwua2luZCA9PT0gImhvc3QiCisgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxX
aWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcAorICAgICAgICAgICAgICAgIHRleHQ6IENy
aW1zb25TdGF0dXMuc3RhdHVzCisgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLnRleHRE
aW0KKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIFJlcGVhdGVyIHsKKyAgICAgICAgICAgICAg
ICBtb2RlbDogcGFuZWwua2luZCA9PT0gImhvc3QiID8gWworICAgICAgICAgICAgICAgICAgICBb
cXNUcigiQ1BVIiksIHBhbmVsLm1ldHJpYygiY3B1X3BlcmNlbnQiLCAiJSIpLCBwYW5lbC5tZXRy
aWMoImNwdV90ZW1wX2MiLCAiIMKwQyIpXSwKKyAgICAgICAgICAgICAgICAgICAgW3FzVHIoIlJB
TSIpLCBwYW5lbC5tZW1vcnkoInJhbSIpLCBwYW5lbC5tZXRyaWMoInJhbV9wZXJjZW50IiwgIiUi
KV0sCisgICAgICAgICAgICAgICAgICAgIFtxc1RyKCJHUFUiKSwgcGFuZWwubWV0cmljKCJncHVf
cGVyY2VudCIsICIlIiksIHBhbmVsLm1ldHJpYygiZ3B1X3RlbXBfYyIsICIgwrBDIildLAorICAg
ICAgICAgICAgICAgICAgICBbcXNUcigiVlJBTSIpLCBwYW5lbC5tZW1vcnkoInZyYW0iKSwgcGFu
ZWwubWV0cmljKCJ2cmFtX3BlcmNlbnQiLCAiJSIpXSwKKyAgICAgICAgICAgICAgICAgICAgW3Fz
VHIoIkdQVSBlbmNvZGVyIiksIHBhbmVsLm1ldHJpYygiZ3B1X2VuY29kZXJfcGVyY2VudCIsICIl
IiksICIiXSwKKyAgICAgICAgICAgICAgICAgICAgW3FzVHIoIkhvc3QgbmV0d29yayIpLCBwYW5l
bC5tZXRyaWMoIm5ldF9yeF9icHMiLCAiIEIvcyBSWCIpLCBwYW5lbC5tZXRyaWMoIm5ldF90eF9i
cHMiLCAiIEIvcyBUWCIpXQorICAgICAgICAgICAgICAgIF0gOiBbXQorICAgICAgICAgICAgICAg
IGRlbGVnYXRlOiBSZWN0YW5nbGUgeworICAgICAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyBpbXBsaWNpdEhlaWdodDogNTgKKyAgICAgICAgICAgICAgICAgICAgY29sb3I6
IFZiVG9rZW5zLmJnV2luZG93OyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0NvbnRyb2wKKyAgICAg
ICAgICAgICAgICAgICAgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2U7IGJvcmRlci53aWR0
aDogMQorICAgICAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAgICAg
ICAgICAgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGFuY2hvcnMubWFyZ2luczogMTIKKyAgICAgICAg
ICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogbW9kZWxEYXRhWzBdOyBjb2xvcjogVmJUb2tl
bnMudGV4dERpbTsgTGF5b3V0LnByZWZlcnJlZFdpZHRoOiAxMTUgfQorICAgICAgICAgICAgICAg
ICAgICAgICAgTGFiZWwgeyB0ZXh0OiBtb2RlbERhdGFbMV07IGNvbG9yOiBWYlRva2Vucy50ZXh0
OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExhYmVs
IHsgdGV4dDogbW9kZWxEYXRhWzJdOyBjb2xvcjogVmJUb2tlbnMuYWNjZW50IH0KKyAgICAgICAg
ICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAg
ICAgIEdyb3VwQm94IHsKKyAgICAgICAgICAgICAgICB2aXNpYmxlOiBwYW5lbC5raW5kID09PSAi
aG9zdCIKKyAgICAgICAgICAgICAgICB0aXRsZTogcXNUcigiQ29uZmlndXJlIGhvc3Qgc3RhdHMi
KQorICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgICAg
ICBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVu
dAorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdy
YXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIlNlbGVjdCBhIGhvc3QgZmlyc3QuIEVuYWJs
ZSByZWFsdGltZSBzdGF0cyBpbiBWaWJlcG9sbG8gYW5kIGNyZWF0ZSBhIHJlYWQtb25seSB0b2tl
biBmb3IgR0VUIC9hcGkvaG9zdC9zdGF0cy4gR2FtZVN0cmVhbSBwYWlyaW5nIGRvZXMgbm90IGdy
YW50IHRoaXMgYWNjZXNzLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAg
ICAgICAgICAgIFRleHRGaWVsZCB7IGlkOiB1cmxJbnB1dDsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1
ZTsgcGxhY2Vob2xkZXJUZXh0OiBxc1RyKCJIVFRQUyBob3N0IFVSTCwgZS5nLiBodHRwczovLzE5
Mi4xNjguMS4xMDo0Nzk5MCIpOyBzZWxlY3RCeU1vdXNlOiB0cnVlIH0KKyAgICAgICAgICAgICAg
ICAgICAgVGV4dEZpZWxkIHsgaWQ6IHRva2VuSW5wdXQ7IExheW91dC5maWxsV2lkdGg6IHRydWU7
IHBsYWNlaG9sZGVyVGV4dDogcXNUcigiUmVhZC1vbmx5IEFQSSB0b2tlbiAoYmxhbmsga2VlcHMg
c2F2ZWQgdG9rZW4pIik7IGVjaG9Nb2RlOiBUZXh0SW5wdXQuUGFzc3dvcmQ7IHNlbGVjdEJ5TW91
c2U6IHRydWUgfQorICAgICAgICAgICAgICAgICAgICBUZXh0RmllbGQgeyBpZDogcGluSW5wdXQ7
IExheW91dC5maWxsV2lkdGg6IHRydWU7IHBsYWNlaG9sZGVyVGV4dDogcXNUcigiU0hBLTI1NiBj
ZXJ0aWZpY2F0ZSBmaW5nZXJwcmludCBmb3IgYSBzZWxmLXNpZ25lZCBob3N0Iik7IHNlbGVjdEJ5
TW91c2U6IHRydWUgfQorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lk
dGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIlZlcmlmeSBhIHNlbGYt
c2lnbmVkIGNlcnRpZmljYXRlJ3MgU0hBLTI1NiBmaW5nZXJwcmludCBvbiB0aGUgaG9zdCBiZWZv
cmUgc2F2aW5nIGl0LiBUb2tlbiBpcyBzdG9yZWQgcHJpdmF0ZWx5IG9uIHRoaXMgVVNCOyBpdCBp
cyBub3QgZW5jcnlwdGVkLiBVbnN1cHBvcnRlZCBvciBtaXNzaW5nIHNlbnNvcnMgc2hvdyBOL0Eu
Iik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICAgICAgQnV0dG9u
IHsgdGV4dDogcXNUcigiU2F2ZSAmIGNvbm5lY3QiKTsgb25DbGlja2VkOiB7IGlmIChDcmltc29u
U3RhdHVzLmNvbmZpZ3VyZSh1cmxJbnB1dC50ZXh0LCB0b2tlbklucHV0LnRleHQsIHBpbklucHV0
LnRleHQpKSB0b2tlbklucHV0LnRleHQgPSAiIiB9IH0KKyAgICAgICAgICAgICAgICB9CisgICAg
ICAgICAgICB9CisgICAgICAgIH0KKyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0VjbGlw
c2VBYm91dERpYWxvZy5xbWwgYi9hcHAvZ3VpL0VjbGlwc2VBYm91dERpYWxvZy5xbWwKbmV3IGZp
bGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uM2FiNzgwNQotLS0gL2Rldi9udWxsCisrKyBi
L2FwcC9ndWkvRWNsaXBzZUFib3V0RGlhbG9nLnFtbApAQCAtMCwwICsxLDM0IEBACitpbXBvcnQg
UXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2su
TGF5b3V0cyAxLjMKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0
IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitOYXZpZ2FibGVEaWFsb2cgeworICAgIGlkOiBwYW5lbAor
ICAgIHByb3BlcnR5IHZhciBpbmZvOiAoe30pCisgICAgd2lkdGg6IE1hdGgubWluKDUyMCxwYXJl
bnQud2lkdGgtMzIpCisgICAgdGl0bGU6IHFzVHIoIkFib3V0IEVjbGlwc2UiKQorICAgIHN0YW5k
YXJkQnV0dG9uczogRGlhbG9nLkNsb3NlCisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tl
bnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBiYWNr
Z3JvdW5kOiBSZWN0YW5nbGUgeyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0RpYWxvZzsgY29sb3I6
IFZiVG9rZW5zLmJnRWxldjsgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UKKyAgICAgICAg
UmVjdGFuZ2xlIHsgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGNvbG9yOiAidHJhbnNwYXJlbnQiOyBn
cmFkaWVudDogR3JhZGllbnQgeyBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjogMDsgY29sb3I6IFF0
LnJnYmEoMSwxLDEsMC4wMzUpIH0gR3JhZGllbnRTdG9wIHsgcG9zaXRpb246IDE7IGNvbG9yOiAi
dHJhbnNwYXJlbnQiIH0gfSB9CisgICAgfQorICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQg
eworICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICAgICAgSW1hZ2UgeyBzb3Vy
Y2U6ICJxcmM6L3Jlcy9lY2xpcHNlLWljb24uc3ZnIjsgc291cmNlU2l6ZS53aWR0aDogOTY7IHNv
dXJjZVNpemUuaGVpZ2h0OiA5NjsgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25IQ2VudGVyOyBM
YXlvdXQucHJlZmVycmVkV2lkdGg6IDk2OyBMYXlvdXQucHJlZmVycmVkSGVpZ2h0OiA5NiB9Cisg
ICAgICAgIExhYmVsIHsgdGV4dDogIkVDTElQU0UiOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9u
dC5mYW1pbHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5OyBmb250LnBpeGVsU2l6ZTogMjQ7IGZvbnQu
bGV0dGVyU3BhY2luZzogNDsgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25IQ2VudGVyIH0KKyAg
ICAgICAgTGFiZWwgeyB0ZXh0OiBxc1RyKCJNYWRlIGJ5IFRoM0QzY2szciIpOyBjb2xvcjogVmJU
b2tlbnMuYWNjZW50OyBMYXlvdXQuYWxpZ25tZW50OiBRdC5BbGlnbkhDZW50ZXIgfQorICAgICAg
ICBMYWJlbCB7CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0
OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgY29sb3I6IFZiVG9rZW5zLnRl
eHREaW0KKyAgICAgICAgICAgIHRleHQ6IHFzVHIoIk9TOiAlMSAlMlxuVGFyZ2V0OiAlM1xuRmVk
b3JhOiAlNFxuS2VybmVsOiAlNVxuRWNsaXBzZSBmcm9udGVuZDogJTYg4oCiIGN1c3RvbWl6ZWQi
KQorICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3MgfHwge30pLk5BTUUgfHwgIkVj
bGlwc2VPUyIpCisgICAgICAgICAgICAgICAgLmFyZygocGFuZWwuaW5mby5vcyB8fCB7fSkuVkVS
U0lPTiB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVs
LmluZm8ub3MgfHwge30pLlRBUkdFVCB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAg
ICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3MgfHwge30pLkZFRE9SQSB8fCBxc1RyKCJVbmF2YWls
YWJsZSIpKQorICAgICAgICAgICAgICAgIC5hcmcocGFuZWwuaW5mby5rZXJuZWwgfHwgcXNUcigi
VW5hdmFpbGFibGUiKSkKKyAgICAgICAgICAgICAgICAuYXJnKFF0LmFwcGxpY2F0aW9uLnZlcnNp
b24gfHwgIjAuNS4wIikKKyAgICAgICAgfQorICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lk
dGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltOyB0
ZXh0OiBxc1RyKCJBIGxpZ2h0d2VpZ2h0IEVjbGlwc2VPUyBmcm9udGVuZC4gQmFzZWQgb24gVmli
ZW1pcyBhbmQgTW9vbmxpZ2h0OyBvcmlnaW5hbCBvcGVuLXNvdXJjZSBjcmVkaXRzIGFuZCBsaWNl
bnNlcyByZW1haW4gYXZhaWxhYmxlIGluIFNldHRpbmdzLiBVcGRhdGVzIGFyZSBtYW5hZ2VkIGJ5
IEVjbGlwc2VPUy4iKSB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlQWN0
aW9uQnV0dG9uLnFtbCBiL2FwcC9ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5xbWwKbmV3IGZpbGUg
bW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uNjMxMzI3MgotLS0gL2Rldi9udWxsCisrKyBiL2Fw
cC9ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5xbWwKQEAgLTAsMCArMSwzMiBAQAoraW1wb3J0IFF0
UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBWaWJlbWlzLlJl
ZGVzaWduIDEuMAorQnV0dG9uIHsKKyAgICBpZDogYnV0dG9uCisgICAgcHJvcGVydHkgc3RyaW5n
IGljb25Tb3VyY2U6ICIiCisgICAgaW1wbGljaXRIZWlnaHQ6IDQ0CisgICAgaW1wbGljaXRXaWR0
aDogTWF0aC5tYXgoMTAwLCBjb250ZW50SXRlbS5pbXBsaWNpdFdpZHRoICsgMjgpCisgICAgZm9u
dC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRCb2R5CisgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5z
LnR5cGVMYWJlbAorICAgIEFjY2Vzc2libGUubmFtZTogdGV4dAorICAgIGFjdGl2ZUZvY3VzT25U
YWI6IHRydWUKKyAgICBLZXlzLm9uUmV0dXJuUHJlc3NlZDogaWYgKGVuYWJsZWQpIGNsaWNrZWQo
KQorICAgIEtleXMub25FbnRlclByZXNzZWQ6IGlmIChlbmFibGVkKSBjbGlja2VkKCkKKyAgICBL
ZXlzLm9uUmlnaHRQcmVzc2VkOiBuZXh0SXRlbUluRm9jdXNDaGFpbih0cnVlKS5mb3JjZUFjdGl2
ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgIEtleXMub25MZWZ0UHJlc3NlZDogbmV4dEl0ZW1JbkZv
Y3VzQ2hhaW4oZmFsc2UpLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgS2V5cy5v
bkRvd25QcmVzc2VkOiBuZXh0SXRlbUluRm9jdXNDaGFpbih0cnVlKS5mb3JjZUFjdGl2ZUZvY3Vz
KFF0LlRhYkZvY3VzKQorICAgIEtleXMub25VcFByZXNzZWQ6IG5leHRJdGVtSW5Gb2N1c0NoYWlu
KGZhbHNlKS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgIGJhY2tncm91bmQ6IFJl
Y3RhbmdsZSB7CisgICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ29udHJvbAorICAgICAg
ICBjb2xvcjogYnV0dG9uLmRvd24gPyBWYlRva2Vucy5iZ0VsZXYyIDogYnV0dG9uLmhvdmVyZWQg
PyBWYlRva2Vucy5iZ0VsZXYyIDogVmJUb2tlbnMuYmdXaW5kb3cKKyAgICAgICAgYm9yZGVyLndp
ZHRoOiBidXR0b24uYWN0aXZlRm9jdXMgPyAyIDogMQorICAgICAgICBib3JkZXIuY29sb3I6IGJ1
dHRvbi5hY3RpdmVGb2N1cyB8fCBidXR0b24uaG92ZXJlZCA/IFZiVG9rZW5zLmFjY2VudCA6IFZi
VG9rZW5zLnN0cm9rZQorICAgICAgICBvcGFjaXR5OiBidXR0b24uZW5hYmxlZCA/IDEgOiAwLjUK
KyAgICB9CisgICAgY29udGVudEl0ZW06IFJvdyB7CisgICAgICAgIHNwYWNpbmc6IDgKKyAgICAg
ICAgb3BhY2l0eTogYnV0dG9uLmVuYWJsZWQgPyAxIDogMC41CisgICAgICAgIEltYWdlIHsgdmlz
aWJsZTogYnV0dG9uLmljb25Tb3VyY2UgIT09ICIiOyBzb3VyY2U6IGJ1dHRvbi5pY29uU291cmNl
OyB3aWR0aDogdmlzaWJsZSA/IDIwIDogMDsgaGVpZ2h0OiAyMDsgYW5jaG9ycy52ZXJ0aWNhbENl
bnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVyIH0KKyAgICAgICAgTGFiZWwgeyB0ZXh0OiBidXR0
b24udGV4dDsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IGNvbG9yOiBWYlRva2Vucy50ZXh0
OyBmb250OiBidXR0b24uZm9udDsgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRp
Y2FsQ2VudGVyIH0KKyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0VjbGlwc2VDb250cm9s
Q2VudGVyLnFtbCBiL2FwcC9ndWkvRWNsaXBzZUNvbnRyb2xDZW50ZXIucW1sCm5ldyBmaWxlIG1v
ZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmVmZjAyZWQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAv
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
ICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBDb21ib0JveCB7CisgICAgICAgICAgICAgICAg
ICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgICAgICAgICAgbW9kZWw6IFN5
c3RlbUNvbnRyb2xzLnN0YXRlLnNpbmtzIHx8IFtdOyB0ZXh0Um9sZTogIm5hbWUiCisgICAgICAg
ICAgICAgICAgICAgIGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5ICYmIGNvdW50ID4gMAor
ICAgICAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIkF1ZGlvIG91dHB1dCIp
CisgICAgICAgICAgICAgICAgICAgIGN1cnJlbnRJbmRleDogeyB2YXIgbGlzdCA9IFN5c3RlbUNv
bnRyb2xzLnN0YXRlLnNpbmtzIHx8IFtdOyBmb3IgKHZhciBpPTA7aTxsaXN0Lmxlbmd0aDtpKysp
IGlmIChsaXN0W2ldLmRlZmF1bHQpIHJldHVybiBpOyByZXR1cm4gLTEgfQorICAgICAgICAgICAg
ICAgICAgICBjb250ZW50SXRlbTogTGFiZWwgeyB0ZXh0OiBwYXJlbnQuZGlzcGxheVRleHQ7IHRl
eHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgdmVydGljYWxB
bGlnbm1lbnQ6IFRleHQuQWxpZ25WQ2VudGVyOyBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0IH0KKyAg
ICAgICAgICAgICAgICAgICAgZGVsZWdhdGU6IEl0ZW1EZWxlZ2F0ZSB7IHdpZHRoOiBwYXJlbnQu
d2lkdGg7IGNvbnRlbnRJdGVtOiBMYWJlbCB7IHRleHQ6IG1vZGVsRGF0YS5uYW1lOyB0ZXh0Rm9y
bWF0OiBUZXh0LlBsYWluVGV4dDsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGVsaWRlOiBUZXh0LkVs
aWRlUmlnaHQgfSB9CisgICAgICAgICAgICAgICAgICAgIG9uQWN0aXZhdGVkOiBTeXN0ZW1Db250
cm9scy5yZXF1ZXN0KCJjZW50ZXItb3V0cHV0IiwgbW9kZWxbaW5kZXhdLmlkKQorICAgICAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgICAgICBSZXBlYXRlciB7CisgICAgICAgICAgICAgICAgICAg
IG1vZGVsOiBbe2tpbmQ6InNjcmVlbiIsbGFiZWw6cXNUcigiU2NyZWVuIGJyaWdodG5lc3MiKX0s
e2tpbmQ6ImtleWJvYXJkIixsYWJlbDpxc1RyKCJLZXlib2FyZCBicmlnaHRuZXNzIil9XQorICAg
ICAgICAgICAgICAgICAgICBkZWxlZ2F0ZTogQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAgICAg
ICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgICAgICAgICAgICAg
IHByb3BlcnR5IHZhciBoYXJkd2FyZTogKFN5c3RlbUNvbnRyb2xzLnN0YXRlLmJyaWdodG5lc3Mg
fHwge30pW21vZGVsRGF0YS5raW5kXQorICAgICAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0
ZXh0OiBtb2RlbERhdGEubGFiZWwgKyAoaGFyZHdhcmUgPyAiIOKAoiAiICsgaGFyZHdhcmUucGVy
Y2VudCArICIlIiA6ICIg4oCiICIgKyBxc1RyKCJVbmF2YWlsYWJsZSIpKTsgY29sb3I6IFZiVG9r
ZW5zLnRleHQgfQorICAgICAgICAgICAgICAgICAgICAgICAgU2xpZGVyIHsKKyAgICAgICAgICAg
ICAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBmcm9tOiBtb2RlbERhdGEu
a2luZCA9PT0gInNjcmVlbiIgPyA1IDogMDsgdG86IDEwMDsgc3RlcFNpemU6IDEKKyAgICAgICAg
ICAgICAgICAgICAgICAgICAgICB2YWx1ZTogaGFyZHdhcmUgPyBoYXJkd2FyZS5wZXJjZW50IDog
MDsgZW5hYmxlZDogISFoYXJkd2FyZSAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAgICAg
ICAgICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogbW9kZWxEYXRhLmxhYmVsCisgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgb25Nb3ZlZDogaWYgKCFwcmVzc2VkICYmIGVuYWJsZWQp
IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImNlbnRlci0iK21vZGVsRGF0YS5raW5kLCBTdHJpbmco
TWF0aC5yb3VuZCh2YWx1ZSkpKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgIG9uUHJlc3Nl
ZENoYW5nZWQ6IGlmICghcHJlc3NlZCAmJiBlbmFibGVkKSBTeXN0ZW1Db250cm9scy5yZXF1ZXN0
KCJjZW50ZXItIittb2RlbERhdGEua2luZCwgU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSkKKyAg
ICAgICAgICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNU
cigiUmVmcmVzaCBjb250cm9scyIpOyBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25D
bGlja2VkOiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItbGlzdCIpIH0KKyAgICAgICAg
ICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIkhvc3QiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7
IGZvbnQuYm9sZDogdHJ1ZSB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdp
ZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3Jh
cDsgdGV4dDogcGFuZWwuaG9zdC51cmwgfHwgcXNUcigiU2VsZWN0IGEgaG9zdCBpbiB0aGUgbGF1
bmNoZXIuIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICBSb3dM
YXlvdXQgeworICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDog
cXNUcigiSG9zdCBzdGF0cyIpOyBlbmFibGVkOiAhIXBhbmVsLmhvc3QuaWQ7IGljb25Tb3VyY2U6
ICJxcmM6L3Jlcy9jcmltc29uLWhvc3Quc3ZnIjsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigiaG9z
dCIpIH0KKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFz
VHIoIldha2UgaG9zdCIpOyBlbmFibGVkOiAhIXBhbmVsLmhvc3QuaWQgJiYgcGFuZWwuY2FuV2Fr
ZTsgb25DbGlja2VkOiB7IHBhbmVsLndha2VSZXF1ZXN0ZWQoKTsgcGFuZWwubWVzc2FnZSA9IHFz
VHIoIldha2UgcmVxdWVzdCBzZW50OyB0aGUgaG9zdCBtdXN0IHN1cHBvcnQgV2FrZS1vbi1MQU4u
IikgfSB9CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25C
dXR0b24geyB0ZXh0OiBxc1RyKCJPcGVuIGhvc3QgbWFuYWdlbWVudCIpOyBlbmFibGVkOiAhIXBh
bmVsLmhvc3QudXJsICYmIHBhbmVsLmNhbk1hbmFnZTsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigi
bWFuYWdlbWVudCIpIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIlN0cmVh
bSBwcm9maWxlcyIpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAg
ICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBU
ZXh0LldyYXA7IHRleHQ6IHBhbmVsLmhvc3QuaWQgPyBxc1RyKCJTYXZlZCBmb3IgdGhlIHNlbGVj
dGVkIGhvc3QuIEFwcGx5IGJlZm9yZSBzdGFydGluZyBhIHN0cmVhbS4iKSA6IHFzVHIoIkdsb2Jh
bCBwcm9maWxlcy4gQXBwbHkgYmVmb3JlIHN0YXJ0aW5nIGEgc3RyZWFtLiIpOyBjb2xvcjogVmJU
b2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICAgICAgQ29tYm9Cb3ggeyBMYXlvdXQuZmlsbFdp
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
YlRva2Vucy50ZXh0OyBmb250LmJvbGQ6IHRydWUgfQorICAgICAgICAgICAgICAgIENvbWJvQm94
IHsKKyAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgbW9kZWw6IFtx
c1RyKCJUZXh0IDEwMCUiKSxxc1RyKCJUZXh0IDExMCUiKSxxc1RyKCJUZXh0IDEyNSUiKV0KKyAg
ICAgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJUZXh0IHNpemUiKQorICAg
ICAgICAgICAgICAgICAgICBjdXJyZW50SW5kZXg6IEVjbGlwc2VQcm9maWxlcy50ZXh0U2NhbGUg
PT09IDEyNSA/IDIgOiBFY2xpcHNlUHJvZmlsZXMudGV4dFNjYWxlID09PSAxMTAgPyAxIDogMAor
ICAgICAgICAgICAgICAgICAgICBvbkFjdGl2YXRlZDogRWNsaXBzZVByb2ZpbGVzLnRleHRTY2Fs
ZSA9IFsxMDAsMTEwLDEyNV1baW5kZXhdCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAg
ICAgIFN3aXRjaCB7IHRleHQ6IHFzVHIoIlJlZHVjZSBtb3Rpb24iKTsgY2hlY2tlZDogRWNsaXBz
ZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb247IG9uVG9nZ2xlZDogRWNsaXBzZVByb2ZpbGVzLnJlZHVj
ZWRNb3Rpb24gPSBjaGVja2VkIH0KKyAgICAgICAgICAgICAgICBTd2l0Y2ggeyB0ZXh0OiBxc1Ry
KCJIaWdoZXIgY29udHJhc3QiKTsgY2hlY2tlZDogRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFz
dDsgb25Ub2dnbGVkOiBFY2xpcHNlUHJvZmlsZXMuaGlnaENvbnRyYXN0ID0gY2hlY2tlZCB9Cisg
ICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBxc1RyKCJUb29scyAmIHJlY292ZXJ5Iik7IGNv
bG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmJvbGQ6IHRydWUgfQorICAgICAgICAgICAgICAgIFJv
d0xheW91dCB7CisgICAgICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0
OiBxc1RyKCJBbGwgc2V0dGluZ3MiKTsgaWNvblNvdXJjZTogInFyYzovcmVzL3NldHRpbmdzLnN2
ZyI7IG9uQ2xpY2tlZDogcGFuZWwuZGVmZXIoInNldHRpbmdzIikgfQorICAgICAgICAgICAgICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiU3VwcG9ydCByZXBvcnQiKTsg
ZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogU3lzdGVtQ29udHJvbHMu
cmVxdWVzdCgiY2VudGVyLXJlcG9ydCIpIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAg
ICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFw
OyB0ZXh0OiBxc1RyKCJSZWNvdmVyeTogQ3RybCtBbHQrRjIgb3BlbnMgdGhlIGRpYWdub3N0aWMg
Y29uc29sZS4gTWFjIGJyaWdodG5lc3MsIGtleWJvYXJkLWxpZ2h0IGFuZCB2b2x1bWUga2V5cyBy
ZW1haW4gYXZhaWxhYmxlLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAg
ICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgUmVwZWF0ZXIgeworICAgICAg
ICAgICAgICAgICAgICAgICAgbW9kZWw6IFt7YWN0aW9uOiJyZWJvb3QiLGxhYmVsOnFzVHIoIlJl
c3RhcnQiKX0se2FjdGlvbjoicG93ZXJvZmYiLGxhYmVsOnFzVHIoIlNodXQgZG93biIpfV0KKyAg
ICAgICAgICAgICAgICAgICAgICAgIGRlbGVnYXRlOiBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4
dDogbW9kZWxEYXRhLmxhYmVsOyBpY29uU291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1wb3dlci5z
dmciOyBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiB7IHBhbmVsLnBv
d2VyQWN0aW9uID0gbW9kZWxEYXRhLmFjdGlvbjsgcG93ZXJEaWFsb2cub3BlbigpIH0gfQorICAg
ICAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEVj
bGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJBYm91dCBFY2xpcHNlIik7IGVuYWJsZWQ6
ICFTeXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJhYm91dCIpIH0K
KyAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHRleHRGb3Jt
YXQ6IFRleHQuUGxhaW5UZXh0OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBwYW5lbC5tZXNz
YWdlIHx8IFN5c3RlbUNvbnRyb2xzLnN0YXR1czsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQor
ICAgICAgICAgICAgICAgIEJ1c3lJbmRpY2F0b3IgeyBydW5uaW5nOiBTeXN0ZW1Db250cm9scy5i
dXN5OyB2aXNpYmxlOiBydW5uaW5nOyBMYXlvdXQuYWxpZ25tZW50OiBRdC5BbGlnbkhDZW50ZXIg
fQorICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQorICAgIE5hdmlnYWJsZURpYWxvZyB7
CisgICAgICAgIGlkOiBwb3dlckRpYWxvZworICAgICAgICB3aWR0aDogTWF0aC5taW4oNDQwLCBw
YW5lbC53aWR0aCAtIDMyKQorICAgICAgICB0aXRsZTogcGFuZWwucG93ZXJBY3Rpb24gPT09ICJy
ZWJvb3QiID8gcXNUcigiUmVzdGFydCBFY2xpcHNlT1M/IikgOiBxc1RyKCJTaHV0IGRvd24gRWNs
aXBzZU9TPyIpCisgICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLlllcyB8IERpYWxvZy5O
bworICAgICAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAgICAg
b25BY2NlcHRlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLSIrcGFuZWwucG93ZXJB
Y3Rpb24sIiIsdHJ1ZSkKKyAgICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgdGV4dDogcXNUcigi
VGhpcyBlbmRzIHRoZSBjdXJyZW50IGxvY2FsIHNlc3Npb24uIik7IGNvbG9yOiBWYlRva2Vucy50
ZXh0IH0KKyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1BjVmlldy5xbWwgYi9hcHAvZ3Vp
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
aWV3LnFtbAppbmRleCA0OTRlMzViLi40NmM2ZDI2IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1NldHRp
bmdzVmlldy5xbWwKKysrIGIvYXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sCkBAIC0xNjgxLDcgKzE2
ODEsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAog
ICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAg
ICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xU
aXAudGV4dDogcXNUcigiV2hlbiB0aGUgbmV0d29yayBjYW4ndCBzdXN0YWluIHRoZSBjb25maWd1
cmVkIGJpdHJhdGUgYW5kIHRoZSBzdHJlYW0gY29sbGFwc2VzLCBWaWJlbWlzIGF1dG9tYXRpY2Fs
bHkgcmVjb25uZWN0cyBhdCBhIGxvd2VyIGJpdHJhdGUgdW50aWwgdGhlIHN0cmVhbSBpcyB1c2Fi
bGUuIFlvdXIgc2F2ZWQgYml0cmF0ZSBzZXR0aW5nIGlzIG5ldmVyIGNoYW5nZWQuIikKKyAgICAg
ICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJXaGVuIHRoZSBuZXR3b3JrIGNhbid0
IHN1c3RhaW4gdGhlIGNvbmZpZ3VyZWQgYml0cmF0ZSBhbmQgdGhlIHN0cmVhbSBjb2xsYXBzZXMs
IEVjbGlwc2UgYXV0b21hdGljYWxseSByZWNvbm5lY3RzIGF0IGEgbG93ZXIgYml0cmF0ZSB1bnRp
bCB0aGUgc3RyZWFtIGlzIHVzYWJsZS4gWW91ciBzYXZlZCBiaXRyYXRlIHNldHRpbmcgaXMgbmV2
ZXIgY2hhbmdlZC4iKQogICAgICAgICAgICAgICAgIH0KIAogICAgICAgICAgICAgICAgIC8vIFZp
YmVtaXMgKHBlcmYgZ3VpZGFuY2UpOiBhZHZpc2Ugd2hlbiB0aGUgYml0cmF0ZSBpcyBzZXQgd2Vs
bCBhYm92ZSB0aGUgcmVjb21tZW5kZWQKQEAgLTI0ODIsNyArMjQ4Miw3IEBAIEl0ZW0gewogICAg
ICAgICAgICAgICAgICAgICBUb29sVGlwLmRlbGF5OiAxMDAwCiAgICAgICAgICAgICAgICAgICAg
IFRvb2xUaXAudGltZW91dDogNTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2li
bGU6IGhvdmVyZWQKLSAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJJZiBh
IHN0cmVhbSBlbmRzIHVuZXhwZWN0ZWRseSAoYSBuZXR3b3JrIGJsaXAgb3IgdGhlIGhvc3Qgd2Fr
aW5nKSwgVmliZW1pcyB3aWxsIHRyeSB0byByZWNvbm5lY3QgYXV0b21hdGljYWxseS4iKQorICAg
ICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIklmIGEgc3RyZWFtIGVuZHMgdW5l
eHBlY3RlZGx5IChhIG5ldHdvcmsgYmxpcCBvciB0aGUgaG9zdCB3YWtpbmcpLCBFY2xpcHNlIHdp
bGwgdHJ5IHRvIHJlY29ubmVjdCBhdXRvbWF0aWNhbGx5LiIpCiAgICAgICAgICAgICAgICAgfQog
ICAgICAgICAgICAgfQogICAgICAgICB9CkBAIC0yNTQ2LDcgKzI1NDYsNyBAQCBJdGVtIHsKICAg
ICAgICAgICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKIAogICAgICAgICAgICAgICAg
IFZiU2VjdGlvbkhlYWRlciB7Ci0gICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpYmVt
aXMgU3RyZWFtaW5nIEVuaGFuY2VtZW50cyIpCisgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFz
VHIoIkVjbGlwc2UgU3RyZWFtaW5nIEVuaGFuY2VtZW50cyIpCiAgICAgICAgICAgICAgICAgfQog
CiAgICAgICAgICAgICAgICAgTGFiZWwgewpAQCAtMjc3Niw3ICsyNzc2LDcgQEAgSXRlbSB7CiAK
ICAgICAgICAgICAgICAgICBWYlRvZ2dsZVJvdyB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiBt
dXRlT25Gb2N1c0xvc3NDaGVjawotICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJNdXRl
IGF1ZGlvIHN0cmVhbSB3aGVuIFZpYmVtaXMgaXMgbm90IHRoZSBhY3RpdmUgd2luZG93IikKKyAg
ICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiTXV0ZSBhdWRpbyBzdHJlYW0gd2hlbiBFY2xp
cHNlIGlzIG5vdCB0aGUgYWN0aXZlIHdpbmRvdyIpCiAgICAgICAgICAgICAgICAgICAgIHZpc2li
bGU6IFN5c3RlbVByb3BlcnRpZXMuaGFzRGVza3RvcEVudmlyb25tZW50CiAgICAgICAgICAgICAg
ICAgICAgIGNoZWNrZWQ6IFN0cmVhbWluZ1ByZWZlcmVuY2VzLm11dGVPbkZvY3VzTG9zcwogICAg
ICAgICAgICAgICAgICAgICBvbkNoZWNrZWRDaGFuZ2VkOiB7CkBAIC0yNzg2LDcgKzI3ODYsNyBA
QCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAg
ICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAg
VG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4
dDogcXNUcigiTXV0ZXMgVmliZW1pcydzIGF1ZGlvIHdoZW4geW91IEFsdCtUYWIgb3V0IG9mIHRo
ZSBzdHJlYW0gb3IgY2xpY2sgb24gYSBkaWZmZXJlbnQgd2luZG93LiIpCisgICAgICAgICAgICAg
ICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiTXV0ZXMgRWNsaXBzZSdzIGF1ZGlvIHdoZW4geW91
IEFsdCtUYWIgb3V0IG9mIHRoZSBzdHJlYW0gb3IgY2xpY2sgb24gYSBkaWZmZXJlbnQgd2luZG93
LiIpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgfQogICAgICAgICB9CkBAIC0yOTcx
LDcgKzI5NzEsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgICAgIGlmIChTdHJlYW1p
bmdQcmVmZXJlbmNlcy5sYW5ndWFnZSAhPT0gbmV3X2xhbmd1YWdlKSB7CiAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMubGFuZ3VhZ2UgPSBsYW5ndWFnZUxp
c3RNb2RlbC5nZXQoY3VycmVudEluZGV4KS52YWwKICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICBpZiAoIVN0cmVhbWluZ1ByZWZlcmVuY2VzLnJldHJhbnNsYXRlKCkpIHsKLSAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5zaG93KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQg
VmliZW1pcyBmb3IgdGhpcyBjaGFuZ2UgdG8gdGFrZSBlZmZlY3QiKSwgNTAwMCkKKyAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5zaG93KHFzVHIoIllvdSBtdXN0IHJlc3Rh
cnQgRWNsaXBzZSBmb3IgdGhpcyBjaGFuZ2UgdG8gdGFrZSBlZmZlY3QiKSwgNTAwMCkKICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZWxz
ZSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIC8vIEZvcmNlIHRoZSBiYWNrIG9w
ZXJhdGlvbiB0byBwb3AgYW55IEFwcFZpZXcgcGFnZXMgdGhhdCBleGlzdC4KQEAgLTMwNTUsMTQg
KzMwNTUsMjYgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgIHRleHRSb2xlOiAidGV4dCIK
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
ICAgICAgICAgICAgICAgICB9CkBAIC0zMTQ3LDcgKzMxNTksNyBAQCBJdGVtIHsKICAgICAgICAg
ICAgICAgICAgICAgICAgIFRvb2xUaXAuZGVsYXk6IDEwMDAKICAgICAgICAgICAgICAgICAgICAg
ICAgIFRvb2xUaXAudGltZW91dDogNTAwMAogICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRp
cC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6
IHFzVHIoIlNhdmUgYWxsIFZpYmVtaXMgc2V0dGluZ3MgdG8gfi92aWJlbWlzLXNldHRpbmdzLmlu
aSBmb3IgYmFja3VwIG9yIHRvIGNvcHkgdG8gYW5vdGhlciBkZXZpY2UuIikKKyAgICAgICAgICAg
ICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiU2F2ZSBhbGwgRWNsaXBzZSBzZXR0aW5n
cyB0byB+L3ZpYmVtaXMtc2V0dGluZ3MuaW5pIGZvciBiYWNrdXAgb3IgdG8gY29weSB0byBhbm90
aGVyIGRldmljZS4iKQogICAgICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICAg
ICAgQnV0dG9uIHsKQEAgLTM0MDIsNyArMzQxNCw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAg
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
ICAgICAgICBBdXRvUmVzaXppbmdDb21ib0JveCB7CkBAIC0zNjQzLDcgKzM2NTUsNyBAQCBJdGVt
IHsKIAogICAgICAgICAgICAgICAgIFZiVG9nZ2xlUm93IHsKICAgICAgICAgICAgICAgICAgICAg
aWQ6IGJhY2tncm91bmRHYW1lcGFkQ2hlY2sKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiUHJvY2VzcyBnYW1lcGFkIGlucHV0IHdoZW4gVmliZW1pcyBpcyBpbiB0aGUgYmFja2dyb3Vu
ZCIpCisgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlByb2Nlc3MgZ2FtZXBhZCBpbnB1
dCB3aGVuIEVjbGlwc2UgaXMgaW4gdGhlIGJhY2tncm91bmQiKQogICAgICAgICAgICAgICAgICAg
ICB2aXNpYmxlOiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Rlc2t0b3BFbnZpcm9ubWVudAogICAgICAg
ICAgICAgICAgICAgICBjaGVja2VkOiBTdHJlYW1pbmdQcmVmZXJlbmNlcy5iYWNrZ3JvdW5kR2Ft
ZXBhZAogICAgICAgICAgICAgICAgICAgICBvbkNoZWNrZWRDaGFuZ2VkOiB7CkBAIC0zNjUzLDcg
KzM2NjUsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAw
MAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAg
ICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRv
b2xUaXAudGV4dDogcXNUcigiQWxsb3dzIFZpYmVtaXMgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0
cyBldmVuIGlmIGl0J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBmb2N1cyIpCisgICAgICAg
ICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiQWxsb3dzIEVjbGlwc2UgdG8gY2FwdHVy
ZSBnYW1lcGFkIGlucHV0cyBldmVuIGlmIGl0J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBm
b2N1cyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgVmJUb2dnbGVSb3cg
ewpAQCAtMzcyNCw3ICszNzM2LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgTGFiZWwgewog
ICAgICAgICAgICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAg
ICAgIGlkOiB1cGRhdGVDaGFubmVsVGl0bGUKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNU
cigiU29mdHdhcmUgdXBkYXRlcyIpCisgICAgICAgICAgICAgICAgICAgIHRleHQ6IEF1dG9VcGRh
dGVDaGVja2VyLm9zTWFuYWdlZCA/IHFzVHIoIkVjbGlwc2VPUyB1cGRhdGVzIikgOiBxc1RyKCJT
b2Z0d2FyZSB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZi
VG9rZW5zLnR5cGVMYWJlbAogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tl
bnMuZm9udEJvZHkKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAt
MzczMyw2ICszNzQ1LDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBBdXRvUmVzaXppbmdD
b21ib0JveCB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsQ29tYm9Cb3gK
KyAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogIUF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdl
ZAogICAgICAgICAgICAgICAgICAgICB0ZXh0Um9sZTogInRleHQiCiAgICAgICAgICAgICAgICAg
ICAgIG1vZGVsOiBMaXN0TW9kZWwgewogICAgICAgICAgICAgICAgICAgICAgICAgaWQ6IHVwZGF0
ZUNoYW5uZWxMaXN0TW9kZWwKQEAgLTM3ODcsNiArMzgwMCw3IEBAIEl0ZW0gewogICAgICAgICAg
ICAgICAgICAgICAvLyBpbnN0YWxsIGluIGZsaWdodCBhdCBhIHRpbWUpLCBzbyBidXR0b25zIHN0
YXkgZW5hYmxlZC4KICAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsKICAgICAgICAgICAgICAg
ICAgICAgICAgIGlkOiBjaGVja1VwZGF0ZXNCdXR0b24KKyAgICAgICAgICAgICAgICAgICAgICAg
IHZpc2libGU6ICFBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFnZWQKICAgICAgICAgICAgICAgICAg
ICAgICAgIHRleHQ6IHFzVHIoIkNoZWNrIGZvciB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAg
ICAgICAgIG9uQ2xpY2tlZDogewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIEF1dG9VcGRh
dGVDaGVja2VyLmNoZWNrTm93KCkKQEAgLTM4MDQsOCArMzgxOCw4IEBAIEl0ZW0gewogCiAgICAg
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
Y2tlZDogewpAQCAtMzg0Miw3ICszODU2LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgc3Bh
Y2luZzogVmJUb2tlbnMuc3BhY2UzCiAKICAgICAgICAgICAgICAgICBWYlNlY3Rpb25IZWFkZXIg
ewotICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWJlbWlzIEZlYXR1cmVzIikKKyAg
ICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBGZWF0dXJlcyIpCiAgICAgICAg
ICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgQ2xpcGJvYXJkU2V0dGluZ3MgewpAQCAtMzk0
Nyw3ICszOTYxLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgUmVwZWF0ZXIgewogICAgICAg
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
ICJYMTEiIH0sCkBAIC00MDEzLDcgKzQwMjcsNyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAg
IExhYmVsIHsKICAgICAgICAgICAgICAgICAgICAgd2lkdGg6IHBhcmVudC53aWR0aAotICAgICAg
ICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWJlbWlzICUxIikuYXJnKFN5c3RlbVByb3BlcnRp
ZXMudmVyc2lvblN0cmluZykKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBz
ZSAlMSIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcpCiAgICAgICAgICAgICAg
ICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQm9keQogICAgICAgICAgICAgICAg
ICAgICBmb250LmJvbGQ6IHRydWUKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQu
V3JhcApAQCAtNDA1OCw3ICs0MDcyLDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBMYWJl
bCB7CiAgICAgICAgICAgICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lkdGgKLSAgICAgICAgICAg
ICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBpcyB0aGUgTGludXgvU3RlYW1PUyBjbGllbnQg
Zm9yIEFwb2xsbyAmIFN1bnNoaW5lIGhvc3RzLiBUaGVzZSBvcGVuIGluIHlvdXIgYnJvd3Nlci4i
KQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIGlzIHRoZSBMaW51eC9T
dGVhbU9TIGNsaWVudCBmb3IgQXBvbGxvICYgU3Vuc2hpbmUgaG9zdHMuIFRoZXNlIG9wZW4gaW4g
eW91ciBicm93c2VyLiIpCiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRv
a2Vucy50eXBlQ2FwdGlvbgogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tl
bnMuZm9udEJvZHkKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAt
NDA2Niw3ICs0MDgwLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAg
ICAgICAgQnV0dG9uIHsKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBv
biBHaXRIdWIiKQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIG9uIEdp
dEh1YiIpCiAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogU3lzdGVtUHJvcGVydGllcy5v
cGVuVXJsKCJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3ZpYmVtaXMiKQogICAgICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgICAgICBCdXR0b24gewpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9T
eXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwgYi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlh
bG9nLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5jZmY0YzY2Ci0tLSAv
ZGV2L251bGwKKysrIGIvYXBwL2d1aS9TeXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwKQEAgLTAs
MCArMSwxMDcgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMg
Mi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0IFF0UXVpY2suQ29udHJvbHMu
TWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBTeXN0ZW1D
b250cm9scyAxLjAKKworTmF2aWdhYmxlRGlhbG9nIHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9w
ZXJ0eSBzdHJpbmcga2luZDogIndpZmkiCisgICAgcHJvcGVydHkgdmFyIHNlbGVjdGVkOiAoe30p
CisgICAgd2lkdGg6IE1hdGgubWluKDYyMCwgcGFyZW50LndpZHRoIC0gMzIpCisgICAgaGVpZ2h0
OiBNYXRoLm1pbig1NjAsIHBhcmVudC5oZWlnaHQgLSAzMikKKyAgICB0aXRsZToga2luZCA9PT0g
IndpZmkiID8gcXNUcigiV2ktRmkgbmV0d29ya3MiKSA6IHFzVHIoIkJsdWV0b290aCBkZXZpY2Vz
IikKKyAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5DbG9zZQorICAgIE1hdGVyaWFsLmJhY2tn
cm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNj
ZW50CisgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsgY29sb3I6IFZiVG9rZW5zLmJnRWxldjsg
cmFkaXVzOiBWYlRva2Vucy5yYWRpdXNEaWFsb2c7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ry
b2tlIH0KKyAgICBvbk9wZW5lZDogeyBzZWxlY3RlZCA9ICh7fSk7IFN5c3RlbUNvbnRyb2xzLm9w
ZW4oa2luZCkgfQorICAgIG9uQ2xvc2VkOiB7IGNyZWRlbnRpYWwuY2xvc2UoKTsgc2VjcmV0LnRl
eHQgPSAiIjsgZm9yZ2V0LmNsb3NlKCk7IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCkgfQorICAgIGNv
bnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFj
ZTMKKyAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRy
dWUKKyAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6
IFRleHQuV3JhcDsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHRleHQ6IFN5c3RlbUNvbnRy
b2xzLnN0YXR1czsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgQnVzeUlu
ZGljYXRvciB7IHJ1bm5pbmc6IFN5c3RlbUNvbnRyb2xzLmJ1c3k7IHZpc2libGU6IHJ1bm5pbmc7
IGltcGxpY2l0V2lkdGg6IDMyOyBpbXBsaWNpdEhlaWdodDogMzIgfQorICAgICAgICAgICAgRWNs
aXBzZUFjdGlvbkJ1dHRvbiB7IGlkOiBzY2FuQnV0dG9uOyB0ZXh0OiBxc1RyKCJTY2FuIik7IGVu
YWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6IHsgcGFuZWwuc2VsZWN0ZWQg
PSAoe30pOyBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KHBhbmVsLmtpbmQgKyAiLXNjYW4iKSB9IH0K
KyAgICAgICAgfQorICAgICAgICBMYWJlbCB7CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRo
OiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFwOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbQorICAg
ICAgICAgICAgdGV4dDogcGFuZWwua2luZCA9PT0gIndpZmkiID8gcXNUcigiU2VsZWN0IGEgbmV0
d29yaywgdGhlbiBDb25uZWN0LiBBZHZhbmNlZCBvciBoaWRkZW4gbmV0d29ya3MgYXJlIGF2YWls
YWJsZSBpbiB0aGUgZGlhZ25vc3RpYyBzaGVsbC4iKSA6IHFzVHIoIlB1dCB5b3VyIGNvbnRyb2xs
ZXIgb3IgaGVhZHBob25lcyBpbiBwYWlyaW5nIG1vZGUsIHRoZW4gU2Nhbi4gUGFpcmluZyBtYXkg
dGFrZSB1cCB0byBhIG1pbnV0ZS4iKQorICAgICAgICB9CisgICAgICAgIExpc3RWaWV3IHsKKyAg
ICAgICAgICAgIGlkOiBkZXZpY2VzCisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVl
OyBMYXlvdXQuZmlsbEhlaWdodDogdHJ1ZQorICAgICAgICAgICAgY2xpcDogdHJ1ZTsgc3BhY2lu
ZzogNDsgbW9kZWw6IFN5c3RlbUNvbnRyb2xzLml0ZW1zCisgICAgICAgICAgICBTY3JvbGxCYXIu
dmVydGljYWw6IFNjcm9sbEJhciB7fQorICAgICAgICAgICAgZGVsZWdhdGU6IEl0ZW1EZWxlZ2F0
ZSB7CisgICAgICAgICAgICAgICAgd2lkdGg6IGRldmljZXMud2lkdGgKKyAgICAgICAgICAgICAg
ICBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAgICAgICAgICAgIGhpZ2hsaWdo
dGVkOiBwYW5lbC5zZWxlY3RlZC5pZCA9PT0gbW9kZWxEYXRhLmlkCisgICAgICAgICAgICAgICAg
YWN0aXZlRm9jdXNPblRhYjogdHJ1ZQorICAgICAgICAgICAgICAgIEtleXMub25SZXR1cm5QcmVz
c2VkOiBpZiAoZW5hYmxlZCkgY2xpY2tlZCgpCisgICAgICAgICAgICAgICAgS2V5cy5vbkVudGVy
UHJlc3NlZDogaWYgKGVuYWJsZWQpIGNsaWNrZWQoKQorICAgICAgICAgICAgICAgIEtleXMub25E
b3duUHJlc3NlZDogeyBpZiAoaW5kZXggKyAxIDwgZGV2aWNlcy5jb3VudCkgeyBkZXZpY2VzLmlu
Y3JlbWVudEN1cnJlbnRJbmRleCgpOyBpZiAoZGV2aWNlcy5jdXJyZW50SXRlbSkgZGV2aWNlcy5j
dXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKSB9IGVsc2UgaWYgKGNvbm5l
Y3RCdXR0b24uZW5hYmxlZCkgY29ubmVjdEJ1dHRvbi5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZv
Y3VzKTsgZWxzZSBzY2FuQnV0dG9uLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpIH0KKyAg
ICAgICAgICAgICAgICBLZXlzLm9uVXBQcmVzc2VkOiB7IGlmIChpbmRleCA+IDApIHsgZGV2aWNl
cy5kZWNyZW1lbnRDdXJyZW50SW5kZXgoKTsgaWYgKGRldmljZXMuY3VycmVudEl0ZW0pIGRldmlj
ZXMuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykgfSBlbHNlIHNjYW5C
dXR0b24uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykgfQorICAgICAgICAgICAgICAgIGNv
bnRlbnRJdGVtOiBMYWJlbCB7CisgICAgICAgICAgICAgICAgICAgIHRleHRGb3JtYXQ6IFRleHQu
UGxhaW5UZXh0OyBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0OyBjb2xvcjogVmJUb2tlbnMudGV4dAor
ICAgICAgICAgICAgICAgICAgICB0ZXh0OiBtb2RlbERhdGEubmFtZSArICIgwrcgIiArIG1vZGVs
RGF0YS5kZXRhaWwgKyAobW9kZWxEYXRhLmNvbm5lY3RlZCA/ICIgwrcgIiArIHFzVHIoIkNvbm5l
Y3RlZCIpIDogIiIpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIG9uQ2xpY2tl
ZDogeyBwYW5lbC5zZWxlY3RlZCA9IG1vZGVsRGF0YTsgZGV2aWNlcy5jdXJyZW50SW5kZXggPSBp
bmRleCB9CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICAgICAgUm93TGF5b3V0IHsKKyAg
ICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgIEVjbGlwc2VBY3Rp
b25CdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBjb25uZWN0QnV0dG9uCisgICAgICAgICAg
ICAgICAgdGV4dDogcGFuZWwua2luZCA9PT0gIndpZmkiID8gcXNUcigiQ29ubmVjdCIpIDogcXNU
cigiUGFpciAvIENvbm5lY3QiKQorICAgICAgICAgICAgICAgIGVuYWJsZWQ6ICEhcGFuZWwuc2Vs
ZWN0ZWQuaWQgJiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3kKKyAgICAgICAgICAgICAgICBvbkNsaWNr
ZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QocGFuZWwua2luZCArICItY29ubmVjdCIsIHBhbmVs
LnNlbGVjdGVkLmlkKQorICAgICAgICAgICAgfQorICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1
dHRvbiB7CisgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRGlzY29ubmVjdCIpOyBlbmFibGVk
OiAhIXBhbmVsLnNlbGVjdGVkLmlkICYmIHBhbmVsLnNlbGVjdGVkLmNvbm5lY3RlZCAmJiAhU3lz
dGVtQ29udHJvbHMuYnVzeQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogU3lzdGVtQ29udHJv
bHMucmVxdWVzdChwYW5lbC5raW5kICsgIi1kaXNjb25uZWN0IiwgcGFuZWwuc2VsZWN0ZWQuaWQp
CisgICAgICAgICAgICB9CisgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDog
cXNUcigiRm9yZ2V0Iik7IHZpc2libGU6IHBhbmVsLmtpbmQgPT09ICJidCI7IGVuYWJsZWQ6ICEh
cGFuZWwuc2VsZWN0ZWQuaWQgJiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogZm9y
Z2V0Lm9wZW4oKSB9CisgICAgICAgIH0KKyAgICB9CisgICAgQ29ubmVjdGlvbnMgeworICAgICAg
ICB0YXJnZXQ6IFN5c3RlbUNvbnRyb2xzCisgICAgICAgIG9uQ2hhbmdlZDogeworICAgICAgICAg
ICAgaWYgKFN5c3RlbUNvbnRyb2xzLnByb21wdC5sZW5ndGggPiAwICYmIHBhbmVsLm9wZW5lZCAm
JiAhY3JlZGVudGlhbC5vcGVuZWQpIGNyZWRlbnRpYWwub3BlbigpCisgICAgICAgICAgICBpZiAo
IVN5c3RlbUNvbnRyb2xzLmJ1c3kpIHsKKyAgICAgICAgICAgICAgICBjcmVkZW50aWFsLmNsb3Nl
KCk7IHNlY3JldC50ZXh0ID0gIiIKKyAgICAgICAgICAgICAgICB2YXIgaWQgPSBwYW5lbC5zZWxl
Y3RlZC5pZAorICAgICAgICAgICAgICAgIHBhbmVsLnNlbGVjdGVkID0gKHt9KQorICAgICAgICAg
ICAgICAgIGZvciAodmFyIGkgPSAwOyBpIDwgU3lzdGVtQ29udHJvbHMuaXRlbXMubGVuZ3RoOyBp
KyspCisgICAgICAgICAgICAgICAgICAgIGlmIChTeXN0ZW1Db250cm9scy5pdGVtc1tpXS5pZCA9
PT0gaWQpIHBhbmVsLnNlbGVjdGVkID0gU3lzdGVtQ29udHJvbHMuaXRlbXNbaV0KKyAgICAgICAg
ICAgIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBOYXZpZ2FibGVEaWFsb2cgeworICAgICAgICBp
ZDogY3JlZGVudGlhbAorICAgICAgICB0aXRsZTogcXNUcigiQ29ubmVjdGlvbiBhdXRoZW50aWNh
dGlvbiIpCisgICAgICAgIHdpZHRoOiBNYXRoLm1pbig0ODAsIHBhbmVsLndpZHRoKQorICAgICAg
ICBjbG9zZVBvbGljeTogUG9wdXAuTm9BdXRvQ2xvc2UKKyAgICAgICAgc3RhbmRhcmRCdXR0b25z
OiBEaWFsb2cuT2sgfCBEaWFsb2cuQ2FuY2VsCisgICAgICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6
IFZiVG9rZW5zLmJnRWxldgorICAgICAgICBvbk9wZW5lZDogeyBzZWNyZXQudGV4dCA9ICIiOyBz
ZWNyZXQuZm9yY2VBY3RpdmVGb2N1cygpIH0KKyAgICAgICAgb25BY2NlcHRlZDogeyBTeXN0ZW1D
b250cm9scy5hbnN3ZXIoc2VjcmV0LnRleHQpOyBzZWNyZXQudGV4dCA9ICIiIH0KKyAgICAgICAg
b25SZWplY3RlZDogeyBzZWNyZXQudGV4dCA9ICIiOyBTeXN0ZW1Db250cm9scy5jbG9zZSgpIH0K
KyAgICAgICAgY29udGVudEl0ZW06IENvbHVtbkxheW91dCB7CisgICAgICAgICAgICBMYWJlbCB7
IExheW91dC5maWxsV2lkdGg6IHRydWU7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB3cmFw
TW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBTeXN0ZW1Db250cm9scy5wcm9tcHQ7IGNvbG9yOiBWYlRv
a2Vucy50ZXh0IH0KKyAgICAgICAgICAgIFRleHRGaWVsZCB7IGlkOiBzZWNyZXQ7IExheW91dC5m
aWxsV2lkdGg6IHRydWU7IGVjaG9Nb2RlOiBUZXh0SW5wdXQuUGFzc3dvcmQ7IG1heGltdW1MZW5n
dGg6IDQwOTY7IHNlbGVjdEJ5TW91c2U6IHRydWU7IG9uQWNjZXB0ZWQ6IGNyZWRlbnRpYWwuYWNj
ZXB0KCkgfQorICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFw
TW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJFbnRlciB0aGUgcmVxdWVzdGVkIHBhc3N3b3Jk
IG9yIFBJTi4gRm9yIGEgeWVzL25vIGNvbmZpcm1hdGlvbiwgdHlwZSB5ZXMgb3Igbm8uIik7IGNv
bG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBOYXZpZ2FibGVE
aWFsb2cgeworICAgICAgICBpZDogZm9yZ2V0CisgICAgICAgIHRpdGxlOiBxc1RyKCJGb3JnZXQg
Qmx1ZXRvb3RoIGRldmljZT8iKQorICAgICAgICB3aWR0aDogTWF0aC5taW4oNDgwLCBwYW5lbC53
aWR0aCkKKyAgICAgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuWWVzIHwgRGlhbG9nLk5vCisg
ICAgICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgICAgICBvbkFj
Y2VwdGVkOiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJidC1mb3JnZXQiLCBwYW5lbC5zZWxlY3Rl
ZC5pZCwgdHJ1ZSkKKyAgICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgdGV4dEZvcm1hdDogVGV4
dC5QbGFpblRleHQ7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIlJlbW92ZSB0aGUg
c2F2ZWQgcGFpcmluZyBmb3IgJTE/IFlvdSB3aWxsIG5lZWQgdG8gcGFpciBpdCBhZ2Fpbi4iKS5h
cmcocGFuZWwuc2VsZWN0ZWQubmFtZSB8fCAiIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0KKyAg
ICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1RoZW1lLnFtbCBiL2FwcC9ndWkvVGhlbWUucW1s
CmluZGV4IGZiOTFjODUuLjU3YzlmODQgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVGhlbWUucW1sCisr
KyBiL2FwcC9ndWkvVGhlbWUucW1sCkBAIC0xMSwyMCArMTEsMjAgQEAgaW1wb3J0IFZpYmVtaXMu
UmVkZXNpZ24gMS4wCiBRdE9iamVjdCB7CiAgICAgLy8gLS0tLSBDb2xvciAtLS0tCiAgICAgcmVh
ZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50OiAgICAgICAgVmJUb2tlbnMuYWNjZW50ICAvLyBC
TC0yMDc3OiBzaW5nbGUgc291cmNlIG9mIHRydXRoIChWYlRva2VucyBicmFuZCBhY2NlbnQsIGRl
ZmF1bHQgIzAwQ0NDQykKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2Vk
OiAiIzAwQTNBMyIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiYWNrZ3JvdW5kOiAgICAi
IzMwMzAzMCIgIC8vIGFwcCByb290Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3VyZmFj
ZTogICAgICAgIiMyRDJEMkQiICAvLyByYWlzZWQgc3VyZmFjZXMgLyBvdmVybGF5cwotICAgIHJl
YWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZhY2VBbHQ6ICAgICIjNDI0MjQyIiAgLy8gcG9wdXBz
IC8gY29tYm8gZHJvcGRvd25zCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYm9yZGVyOiAg
ICAgICAgIiM0NDQ0NDQiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFByaW1hcnk6
ICAgIiNGRkZGRkYiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFNlY29uZGFyeTog
IiNDQ0NDQ0MiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFRlcnRpYXJ5OiAgIiNB
QUFBQUEiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpc2FibGVkOiAgIiM3Nzc3
NzciCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3VjY2VzczogICAgICAgIiM0Q0FGNTAi
Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igd2FybmluZzogICAgICAgIiNFMEEwMzAiICAv
LyB0aGUgc2luZ2xlIGFtYmVyCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZXJyb3I6ICAg
ICAgICAgIiNGNDQzMzYiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW5mbzogICAgICAg
ICAgIiM4MEEwQzAiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc2NyaW06ICAgICAgICAg
IiNEMDAwMDAwMCIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2VkOiBW
YlRva2Vucy5hY2NlbnRQcmVzc2VkCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmFja2dy
b3VuZDogICAgVmJUb2tlbnMuYmdXaW5kb3cgIC8vIGFwcCByb290CisgICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3Igc3VyZmFjZTogICAgICAgVmJUb2tlbnMuYmdFbGV2ICAvLyByYWlzZWQgc3Vy
ZmFjZXMgLyBvdmVybGF5cworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZhY2VBbHQ6
ICAgIFZiVG9rZW5zLmJnRWxldjIgIC8vIHBvcHVwcyAvIGNvbWJvIGRyb3Bkb3ducworICAgIHJl
YWRvbmx5IHByb3BlcnR5IGNvbG9yIGJvcmRlcjogICAgICAgIFZiVG9rZW5zLnN0cm9rZQorICAg
IHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRQcmltYXJ5OiAgIFZiVG9rZW5zLnRleHRQcmlt
YXJ5CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFNlY29uZGFyeTogVmJUb2tlbnMu
dGV4dFNlY29uZGFyeQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRUZXJ0aWFyeTog
IFZiVG9rZW5zLnRleHRUZXJ0aWFyeQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRE
aXNhYmxlZDogIFZiVG9rZW5zLnRleHREaXNhYmxlZAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIHN1Y2Nlc3M6ICAgICAgIFZiVG9rZW5zLnN0YXR1c1N1Y2Nlc3MKKyAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciB3YXJuaW5nOiAgICAgICBWYlRva2Vucy5zdGF0dXNXYXJuaW5nICAvLyB0
aGUgc2luZ2xlIGFtYmVyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZXJyb3I6ICAgICAg
ICAgVmJUb2tlbnMuc3RhdHVzRGFuZ2VyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW5m
bzogICAgICAgICAgVmJUb2tlbnMuc3RhdHVzSW5mbworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIHNjcmltOiAgICAgICAgIFZiVG9rZW5zLmRpYWxvZ1NjcmltCiAKICAgICAvLyAtLS0tIFR5
cG9ncmFwaHkgKHBvaW50U2l6ZTsgcGFpciB3aXRoIGJvbGQgd2hlcmUgbm90ZWQgaW4gREVTSUdO
X1NZU1RFTS5tZCkgLS0tLQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBmb250RGlzcGxheTog
MjQgIC8vIG92ZXJsYXkvUXVpY2sgTWVudSB0aXRsZSAoYm9sZCkKZGlmZiAtLWdpdCBhL2FwcC9n
dWkvVmJDYXJkLnFtbCBiL2FwcC9ndWkvVmJDYXJkLnFtbAppbmRleCAzN2YyZTMyLi4xZTkwYTAy
IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiQ2FyZC5xbWwKKysrIGIvYXBwL2d1aS9WYkNhcmQucW1s
CkBAIC0yNyw3ICsyNyw3IEBAIEl0ZW0gewogICAgICAgICBib3JkZXIud2lkdGg6IDEKICAgICAg
ICAgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UKICAgICAgICAgb3BhY2l0eTogY2FyZC5j
b250ZW50T3BhY2l0eQotICAgICAgICBCZWhhdmlvciBvbiBjb2xvciB7IENvbG9yQW5pbWF0aW9u
IHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAgICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xvckFu
aW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8gMTIwIDogMCB9IH0K
ICAgICB9CiAKICAgICBJdGVtIHsKZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFt
bCBiL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbAppbmRleCA4OWM0NzcwLi5jNzI4ZjA1IDEwMDY0
NAotLS0gYS9hcHAvZ3VpL1ZiU3RhdHVzUGlsbC5xbWwKKysrIGIvYXBwL2d1aS9WYlN0YXR1c1Bp
bGwucW1sCkBAIC0yNCw3ICsyNCw3IEBAIFJlY3RhbmdsZSB7CiAgICAgICAgICAgICBjb2xvcjog
cGlsbC5vbmxpbmUgPyBWYlRva2Vucy5zdGF0dXNPbmxpbmUgOiBWYlRva2Vucy5zdGF0dXNPZmZs
aW5lCiAgICAgICAgICAgICAvLyBQdWxzZSBvbmx5IHdoZW4gb25saW5lLgogICAgICAgICAgICAg
U2VxdWVudGlhbEFuaW1hdGlvbiBvbiBvcGFjaXR5IHsKLSAgICAgICAgICAgICAgICBydW5uaW5n
OiBwaWxsLm9ubGluZQorICAgICAgICAgICAgICAgIHJ1bm5pbmc6IHBpbGwub25saW5lICYmIFZi
VG9rZW5zLm1vdGlvbkVuYWJsZWQKICAgICAgICAgICAgICAgICBsb29wczogQW5pbWF0aW9uLklu
ZmluaXRlCiAgICAgICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJvbTogMS4wOyB0bzog
MC40NTsgZHVyYXRpb246IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAyOyBlYXNpbmcudHlwZTog
RWFzaW5nLkluT3V0U2luZSB9CiAgICAgICAgICAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsgZnJv
bTogMC40NTsgdG86IDEuMDsgZHVyYXRpb246IFZiVG9rZW5zLm9ubGluZVB1bHNlTXMgLyAyOyBl
YXNpbmcudHlwZTogRWFzaW5nLkluT3V0U2luZSB9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1ZiVG9r
ZW5zLnFtbCBiL2FwcC9ndWkvVmJUb2tlbnMucW1sCmluZGV4IDUyYTM0ZGUuLmNiZjc5ODUgMTAw
NjQ0Ci0tLSBhL2FwcC9ndWkvVmJUb2tlbnMucW1sCisrKyBiL2FwcC9ndWkvVmJUb2tlbnMucW1s
CkBAIC0xLDYgKzEsNyBAQAogcHJhZ21hIFNpbmdsZXRvbgogaW1wb3J0IFF0UXVpY2sgMi45CiBp
bXBvcnQgU3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCitpbXBvcnQgRWNsaXBzZVByb2ZpbGVzIDEu
MAogCiAvLyBWaWJlbWlzIHJlZGVzaWduIGRlc2lnbiB0b2tlbnMuCiAvLyBEYXJrIHRoZW1lIG9u
bHkuIENhbnZhcyAxOTIweDEyMDAgKExlZ2lvbiBHbyBTKSwKQEAgLTksNDMgKzEwLDQ0IEBAIGlt
cG9ydCBTdHJlYW1pbmdQcmVmZXJlbmNlcyAxLjAKIFF0T2JqZWN0IHsKICAgICBpZDogdAogCisg
ICAgcmVhZG9ubHkgcHJvcGVydHkgcmVhbCB0ZXh0U2NhbGU6IEVjbGlwc2VQcm9maWxlcy50ZXh0
U2NhbGUgLyAxMDAKKyAgICByZWFkb25seSBwcm9wZXJ0eSBib29sIG1vdGlvbkVuYWJsZWQ6ICFF
Y2xpcHNlUHJvZmlsZXMucmVkdWNlZE1vdGlvbgorCiAgICAgLy8gLS0tLSBDb2xvciAtLS0tCi0g
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdBcHA6ICAgICAgICAiIzA4MDkwQiIgIC8vIG91
dGVybW9zdCBhcHAgYmcgYmVoaW5kIHRoZSByb3VuZGVkIHdpbmRvdwotICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGNvbG9yIGJnV2luZG93OiAgICAgIiMwRTEwMTMiICAvLyBtYWluIHNjcmVlbiBiYWNr
Z3JvdW5kCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdFbGV2OiAgICAgICAiIzE1MTgx
RCIgIC8vIGNhcmRzLCBwYW5lbHMsIGRpYWxvZ3MsIHNpZGViYXIgcm93cwotICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIGJnRWxldjI6ICAgICAgIiMxQjFGMjYiICAvLyBmb2N1c2VkL3NlbGVj
dGVkIHN1cmZhY2UgZmlsbCwgY2hpcHMKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0Zv
b3RlcjogICAgICIjMEIwRDEwIiAgLy8gYm90dG9tIGdhbWVwYWQgaGludCBiYXIKLSAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciBzdHJva2U6ICAgICAgIFF0LnJnYmEoMSwgMSwgMSwgMC4wOCkg
IC8vIGRlZmF1bHQgMXB4IGNhcmQgYm9yZGVyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
YmdBcHA6ICAgICAgICAiIzA2MDYwNyIgIC8vIG91dGVybW9zdCBhcHAgYmcgYmVoaW5kIHRoZSBy
b3VuZGVkIHdpbmRvdworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnV2luZG93OiAgICAg
IiMwQjBCMEUiICAvLyBtYWluIHNjcmVlbiBiYWNrZ3JvdW5kCisgICAgcmVhZG9ubHkgcHJvcGVy
dHkgY29sb3IgYmdFbGV2OiAgICAgICAiIzE1MTExNSIgIC8vIGNhcmRzLCBwYW5lbHMsIGRpYWxv
Z3MsIHNpZGViYXIgcm93cworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxldjI6ICAg
ICAgIiMyMTE3MUMiICAvLyBmb2N1c2VkL3NlbGVjdGVkIHN1cmZhY2UgZmlsbCwgY2hpcHMKKyAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0Zvb3RlcjogICAgICIjMDkwODBCIiAgLy8gYm90
dG9tIGdhbWVwYWQgaGludCBiYXIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdHJva2U6
ICAgICAgIFF0LnJnYmEoMSwgMSwgMSwgRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdCA/IDAu
MjUgOiAwLjA4KSAgLy8gZGVmYXVsdCAxcHggY2FyZCBib3JkZXIKICAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBzdHJva2VTb2Z0OiAgIFF0LnJnYmEoMSwgMSwgMSwgMC4wNikgIC8vIGhlYWRl
ci9mb290ZXIgZGl2aWRlcnMKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0OiAgICAg
ICAgICIjRUNFRUYxIiAgLy8gcHJpbWFyeSB0ZXh0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29s
b3IgdGV4dERpbTogICAgICAiIzk4QTFBQiIgIC8vIHNlY29uZGFyeSAvIGxhYmVsIHRleHQKKyAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0RGltOiAgICAgIChFY2xpcHNlUHJvZmlsZXMu
aGlnaENvbnRyYXN0ID8gIiNEM0Q1REMiIDogIiM5OEExQUIiKSAgLy8gc2Vjb25kYXJ5IC8gbGFi
ZWwgdGV4dAogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRNdXRlOiAgICAgIiNCOUMw
QzgiICAvLyB0ZXJ0aWFyeSAvIGluYWN0aXZlIGl0ZW0gbGFiZWxzCiAKLSAgICAvLyBBY2NlbnQg
aXMgc3dhcHBhYmxlIOKAlCBvbmUgb2YgdGhlIDQgY3VyYXRlZCB2YWx1ZXMuIEluZGV4IDAgaXMg
dGhlIFZpYmVtaXMgYnJhbmQKLSAgICAvLyB0ZWFsICMwMENDQ0MgKEJMLTIwNzcpOiB0aGUgc2lu
Z2xlIGNhbm9uaWNhbCBhY2NlbnQgdGhhdCBUaGVtZS5xbWwgKyBhbGwgbGl0ZXJhbHMgbm93Ci0g
ICAgLy8gcmVzb2x2ZSB0aHJvdWdoLCBhbmQgdGhlIGFuY2hvciBmb3IgdGhlIFAzLjE3L1AzLjE4
IGRlc2lnbiB3b3JrLgotICAgIHJlYWRvbmx5IHByb3BlcnR5IHZhciBhY2NlbnRPcHRpb25zOiAg
WyIjMDBDQ0NDIiwgIiM3QzhDRjgiLCAiIzNFRDU5OCIsICIjRjBBODY4Il0KKyAgICAvLyBQcmVz
ZXJ2ZSBsZWdhY3kgaW5kaWNlcyAwLi4zOyBhcHBlbmQgY29sb3JzIGFuZCBkZWZhdWx0IG5ldyBw
cmVmZXJlbmNlcyB0byBjcmltc29uLgorICAgIHJlYWRvbmx5IHByb3BlcnR5IHZhciBhY2NlbnRP
cHRpb25zOiAgWyIjMDBDQ0NDIiwgIiM3QzhDRjgiLCAiIzNFRDU5OCIsICIjRjBBODY4IiwgIiNE
QzM2NTgiLCAiI0YyNUQ2NCIsICIjRjU4MzQ3IiwgIiNGMUJDNDUiLCAiI0I3REM2MyIsICIjNjND
Q0FFIiwgIiM2M0M0RUQiLCAiIzZDOUZGRiIsICIjQUQ4NUY1IiwgIiNFOTc2QkMiLCAiI0NBRDBE
QSIsICIjRDk5NUFDIl0KICAgICAvLyBCb3VuZCB0byB0aGUgc2F2ZWQgcHJlZmVyZW5jZSAoU2V0
dGluZ3MgPiBhY2NlbnQgcGlja2VyKTsgcGVyc2lzdHMgYWNyb3NzIHJlc3RhcnRzLgogICAgIHBy
b3BlcnR5IGludCBhY2NlbnRJbmRleDogU3RyZWFtaW5nUHJlZmVyZW5jZXMudWlBY2NlbnRJbmRl
eAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAgICAgYWNjZW50T3B0aW9u
c1thY2NlbnRJbmRleF0KLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRIaTogICAg
ICIjNkFEREU3IiAgLy8gYWNjZW50IGdyYWRpZW50IGxpZ2h0IHN0b3AgLyBsaW5rIGhvdmVyCisg
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50OiAgICAgICBhY2NlbnRPcHRpb25zW01h
dGgubWF4KDAsIE1hdGgubWluKGFjY2VudE9wdGlvbnMubGVuZ3RoIC0gMSwgYWNjZW50SW5kZXgp
KV0KKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRIaTogICAgIFF0LmxpZ2h0ZXIo
YWNjZW50LCAxLjE4KSAgLy8gYWNjZW50IGdyYWRpZW50IGxpZ2h0IHN0b3AgLyBsaW5rIGhvdmVy
CiAKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNPbmxpbmU6ICAiIzNFRDU5OCIg
IC8vIG9ubGluZSBkb3QsIFJFU1VNRSBiYWRnZQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9y
IHN0YXR1c09mZmxpbmU6ICIjNUE2MjZDIiAgLy8gb2ZmbGluZSBkb3QgLyBncmV5ZWQgbW9uaXRv
cgogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN0YXR1c0RhbmdlcjogICIjRjI2RDZEIiAg
Ly8gZGVzdHJ1Y3RpdmUgKERlbGV0ZSBQQykKIAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9y
IHRleHRPbkFjY2VudDogIiMwODA5MEIiICAvLyB0ZXh0IG9uIGFuIGFjY2VudC1maWxsZWQgYnV0
dG9uCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dE9uQWNjZW50OiAiIzA2MDYwNyIg
IC8vIHRleHQgb24gYW4gYWNjZW50LWZpbGxlZCBidXR0b24KIAogICAgIC8vIC0tLS0gVHlwb2dy
YXBoeSAoZmFtaWxpZXMgKyBzaXplczsgd2VpZ2h0cyBwZXIgdGhlIHR5cGUgc2NhbGUpIC0tLS0K
ICAgICByZWFkb25seSBwcm9wZXJ0eSBzdHJpbmcgZm9udERpc3BsYXk6ICJTb3JhIiAgICAgLy8g
dGl0bGVzLCBjYXJkIG5hbWVzLCB3b3JkbWFyaywgYWxsLWNhcHMgbGFiZWxzCiAgICAgcmVhZG9u
bHkgcHJvcGVydHkgc3RyaW5nIGZvbnRCb2R5OiAgICAiTWFucm9wZSIgIC8vIGJvZHkgKyBVSSB0
ZXh0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVTY3JlZW5UaXRsZTogIDM0Ci0gICAg
cmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVTZWN0aW9uVGl0bGU6IDI4Ci0gICAgcmVhZG9ubHkg
cHJvcGVydHkgaW50IHNpemVDYXJkTmFtZTogICAgIDI3Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkg
aW50IHNpemVCb2R5OiAgICAgICAgIDE2Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVM
YWJlbDogICAgICAgIDE0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVCYWRnZTogICAg
ICAgIDEzCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVXb3JkbWFyazogICAgIDIxCisg
ICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVTY3JlZW5UaXRsZTogIE1hdGgucm91bmQoMzQg
KiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVTZWN0aW9uVGl0bGU6
IE1hdGgucm91bmQoMjggKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNp
emVDYXJkTmFtZTogICAgIE1hdGgucm91bmQoMjcgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkg
cHJvcGVydHkgaW50IHNpemVCb2R5OiAgICAgICAgIE1hdGgucm91bmQoMTYgKiB0ZXh0U2NhbGUp
CisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVMYWJlbDogICAgICAgIE1hdGgucm91bmQo
MTQgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVCYWRnZTogICAg
ICAgIE1hdGgucm91bmQoMTMgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50
IHNpemVXb3JkbWFyazogICAgIE1hdGgucm91bmQoMjEgKiB0ZXh0U2NhbGUpCiAgICAgcmVhZG9u
bHkgcHJvcGVydHkgcmVhbCB3b3JkbWFya1NwYWNpbmc6IDMuMAogICAgIHJlYWRvbmx5IHByb3Bl
cnR5IHJlYWwgYmFkZ2VTcGFjaW5nOiAgICAxLjIKIApAQCAtODMsNyArODUsNyBAQCBRdE9iamVj
dCB7CiAgICAgLy8gLS0tLSBNb3Rpb24gKG1zKSAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVydHkg
aW50IG9ubGluZVB1bHNlTXM6IDI0MDAgICAvLyBvcGFjaXR5IDEgLT4gMC40NSAtPiAxLCBpbmZp
bml0ZQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBjYXJldEJsaW5rTXM6ICAxMDAwICAgLy8g
QWRkLVBDIGlucHV0IGNhcmV0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNoZWV0SW5Nczog
ICAgIDIyMCAgICAvLyBzaWRlLXNoZWV0IHNsaWRlLWluCisgICAgcmVhZG9ubHkgcHJvcGVydHkg
aW50IHNoZWV0SW5NczogICAgIG1vdGlvbkVuYWJsZWQgPyAyMjAgOiAwICAgIC8vIHNpZGUtc2hl
ZXQgc2xpZGUtaW4KICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBkaWFsb2dTY3JpbTogUXQu
cmdiYSg0LzI1NSwgNS8yNTUsIDcvMjU1LCAwLjcyKQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIHNoZWV0U2NyaW06ICBRdC5yZ2JhKDQvMjU1LCA1LzI1NSwgNy8yNTUsIDAuNjApCiAKQEAg
LTExOSw3ICsxMjEsNyBAQCBRdE9iamVjdCB7CiAgICAgLy8gdGV4dE9uQWNjZW50ICgjMDgwOTBC
KSBpcyBkZWZpbmVkIGluIHRoZSBiYXNlIGJsb2NrIGFib3ZlIOKAlCB0ZXh0IG9uIGFuIGFjY2Vu
dCBmaWxsLgogCiAgICAgLy8gLS0tLSBJbnRlcmFjdGl2ZSBzdGF0ZXM6IG5vcm1hbCAvIGhvdmVy
IC8gZm9jdXMgLyBwcmVzc2VkIC8gZGlzYWJsZWQgLS0tLQotICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIGFjY2VudFByZXNzZWQ6ICAgICAgIiMwMEEzQTMiIC8vIHByZXNzZWQgYWNjZW50ZWQg
Y29udHJvbCAobWF0Y2hlcyBsZWdhY3kgVGhlbWUuYWNjZW50UHJlc3NlZCkKKyAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2VkOiAgICAgIFF0LmRhcmtlcihhY2NlbnQsIDEu
MTgpIC8vIHByZXNzZWQgYWNjZW50ZWQgY29udHJvbCAobWF0Y2hlcyBsZWdhY3kgVGhlbWUuYWNj
ZW50UHJlc3NlZCkKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZUhvdmVy
OiAgIGJnRWxldjIgICAgLy8gcm93IC8gbGlzdC1pdGVtIC8gaWNvbi1idXR0b24gaG92ZXIgZmls
bAogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGludGVyYWN0aXZlRm9jdXM6ICAgZm9jdXNl
ZEZpbGwvLyBmb2N1c2VkIGZpbGwgKD0gYmdFbGV2Mikg4oCUIHBhaXIgd2l0aCB0aGUgZm9jdXMg
cmluZwogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGludGVyYWN0aXZlUHJlc3NlZDogYmdF
bGV2ICAgICAvLyBwcmVzc2VkIG5ldXRyYWwgZmlsbCAocmVjZWRlcyB1bmRlciB0aGUgcHJlc3Mp
CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFtbCBiL2FwcC9ndWkvVmJXZWxj
b21lU2hlZXQucW1sCmluZGV4IDE3MzExOWIuLjQzODNjYjAgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkv
VmJXZWxjb21lU2hlZXQucW1sCisrKyBiL2FwcC9ndWkvVmJXZWxjb21lU2hlZXQucW1sCkBAIC0x
MDgsMTQgKzEwOCwxMyBAQCBOYXZpZ2FibGVEaWFsb2cgewogICAgICAgICAgICAgc3BhY2luZzog
VmJUb2tlbnMuc3BhY2UyICAvLyA4CiAgICAgICAgICAgICBSb3dMYXlvdXQgewogICAgICAgICAg
ICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMgotICAgICAgICAgICAgICAgIFJlY3Rhbmds
ZSB7Ci0gICAgICAgICAgICAgICAgICAgIHdpZHRoOiAxMzsgaGVpZ2h0OiAxMwotICAgICAgICAg
ICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYWNjZW50Ci0gICAgICAgICAgICAgICAgICAgIHJv
dGF0aW9uOiA0NQorICAgICAgICAgICAgICAgIEltYWdlIHsKKyAgICAgICAgICAgICAgICAgICAg
c291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyIKKyAgICAgICAgICAgICAgICAgICAg
TGF5b3V0LnByZWZlcnJlZFdpZHRoOiAyODsgTGF5b3V0LnByZWZlcnJlZEhlaWdodDogMjgKICAg
ICAgICAgICAgICAgICAgICAgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25WQ2VudGVyCiAgICAg
ICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgIFRleHQgewotICAgICAgICAgICAgICAgICAg
ICB0ZXh0OiAiVklCRU1JUyIKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogIkVDTElQU0UiCiAg
ICAgICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250RGlzcGxheQogICAg
ICAgICAgICAgICAgICAgICBmb250LndlaWdodDogRm9udC5FeHRyYUJvbGQKICAgICAgICAgICAg
ICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnNpemVXb3JkbWFyayAgICAgIC8vIDIx
CkBAIC0xMjUsNyArMTI0LDcgQEAgTmF2aWdhYmxlRGlhbG9nIHsKICAgICAgICAgICAgICAgICB9
CiAgICAgICAgICAgICB9CiAgICAgICAgICAgICBUZXh0IHsKLSAgICAgICAgICAgICAgICB0ZXh0
OiBxc1RyKCJXZWxjb21lIHRvIFZpYmVtaXMiKQorICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIo
IldlbGNvbWUgdG8gRWNsaXBzZSIpCiAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9r
ZW5zLmZvbnREaXNwbGF5CiAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZvbnQuQm9sZAog
ICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlRGlzcGxheSAgICAg
ICAgICAgLy8gMzQKQEAgLTE5NSw3ICsxOTQsNyBAQCBOYXZpZ2FibGVEaWFsb2cgewogICAgICAg
ICAgICAgSW5mb1JvdyB7CiAgICAgICAgICAgICAgICAgZ2x5cGg6ICJhcHBzIgogICAgICAgICAg
ICAgICAgIHRpdGxlOiBxc1RyKCJBZGQgdG8gU3RlYW0iKQotICAgICAgICAgICAgICAgIHN1Yjog
cXNUcigiT24gU3RlYW0gRGVjayAvIFN0ZWFtT1MsIGFkZCBWaWJlbWlzIHRvIFN0ZWFtIGZyb20g
RGVza3RvcCBNb2RlIHNvIGl0IGFwcGVhcnMgaW4gR2FtZSBNb2RlLiIpCisgICAgICAgICAgICAg
ICAgc3ViOiBxc1RyKCJPbiBTdGVhbSBEZWNrIC8gU3RlYW1PUywgYWRkIEVjbGlwc2UgdG8gU3Rl
YW0gZnJvbSBEZXNrdG9wIE1vZGUgc28gaXQgYXBwZWFycyBpbiBHYW1lIE1vZGUuIikKICAgICAg
ICAgICAgIH0KIAogICAgICAgICAgICAgLy8gMykgU2V0dGluZ3MuCmRpZmYgLS1naXQgYS9hcHAv
Z3VpL2NvbXB1dGVybW9kZWwuY3BwIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmNwcAppbmRleCA2
M2M3MTE1Li4yZDQ4N2ZmIDEwMDY0NAotLS0gYS9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuY3BwCisr
KyBiL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5jcHAKQEAgLTEsMyArMSw0IEBACisjaW5jbHVkZSA8
UVVybD4KICNpbmNsdWRlICJjb21wdXRlcm1vZGVsLmgiCiAjaW5jbHVkZSAiYmFja2VuZC9zZXJ2
ZXJwZXJtaXNzaW9ucy5oIgogI2luY2x1ZGUgInNldHRpbmdzL3ZpYmVtaXNzZXR0aW5ncy5oIgpA
QCAtNDIwLDMgKzQyMSwxMyBAQCB2b2lkIENvbXB1dGVyTW9kZWw6OmhhbmRsZUNvbXB1dGVyU3Rh
dGVDaGFuZ2VkKE52Q29tcHV0ZXIqIGNvbXB1dGVyKQogfQogCiAjaW5jbHVkZSAiY29tcHV0ZXJt
b2RlbC5tb2MiCisKK1FWYXJpYW50TWFwIENvbXB1dGVyTW9kZWw6OmNyaW1zb25Ib3N0KGludCBp
bmRleCkgY29uc3QKK3sKKyAgICBpZiAoaW5kZXggPCAwIHx8IGluZGV4ID49IG1fQ29tcHV0ZXJz
LmNvdW50KCkpIHJldHVybiB7fTsKKyAgICBhdXRvIGNvbXB1dGVyID0gbV9Db21wdXRlcnNbaW5k
ZXhdOworICAgIFFSZWFkTG9ja2VyIGxvY2soJmNvbXB1dGVyLT5sb2NrKTsKKyAgICBRVXJsIHVy
bDsgdXJsLnNldFNjaGVtZSgiaHR0cHMiKTsgdXJsLnNldEhvc3QoY29tcHV0ZXItPmFjdGl2ZUFk
ZHJlc3MuYWRkcmVzcygpKTsKKyAgICB1cmwuc2V0UG9ydChjb21wdXRlci0+YWN0aXZlQWRkcmVz
cy5wb3J0KCkgPiAwID8gY29tcHV0ZXItPmFjdGl2ZUFkZHJlc3MucG9ydCgpICsgMSA6IDQ3OTkw
KTsKKyAgICByZXR1cm4ge3siaWQiLCBjb21wdXRlci0+dXVpZH0sIHsidXJsIiwgdXJsLnRvU3Ry
aW5nKCl9fTsKK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5oIGIvYXBwL2d1
aS9jb21wdXRlcm1vZGVsLmgKaW5kZXggNmVjYWUzMC4uMmVlNzNjMSAxMDA2NDQKLS0tIGEvYXBw
L2d1aS9jb21wdXRlcm1vZGVsLmgKKysrIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmgKQEAgLTQz
LDYgKzQzLDggQEAgcHVibGljOgogCiAgICAgdmlydHVhbCBRSGFzaDxpbnQsIFFCeXRlQXJyYXk+
IHJvbGVOYW1lcygpIGNvbnN0IG92ZXJyaWRlOwogCisgICAgUV9JTlZPS0FCTEUgUVZhcmlhbnRN
YXAgY3JpbXNvbkhvc3QoaW50IGNvbXB1dGVySW5kZXgpIGNvbnN0OworCiAgICAgUV9JTlZPS0FC
TEUgdm9pZCBkZWxldGVDb21wdXRlcihpbnQgY29tcHV0ZXJJbmRleCk7CiAKICAgICBRX0lOVk9L
QUJMRSBRU3RyaW5nIGdlbmVyYXRlUGluU3RyaW5nKCk7CmRpZmYgLS1naXQgYS9hcHAvZ3VpL21h
aW4ucW1sIGIvYXBwL2d1aS9tYWluLnFtbAppbmRleCA5YmNlNTEwLi44NDhmYzE0IDEwMDY0NAot
LS0gYS9hcHAvZ3VpL21haW4ucW1sCisrKyBiL2FwcC9ndWkvbWFpbi5xbWwKQEAgLTEyLDggKzEy
LDI1IEBAIGltcG9ydCBTeXN0ZW1Qcm9wZXJ0aWVzIDEuMAogaW1wb3J0IFNkbEdhbWVwYWRLZXlO
YXZpZ2F0aW9uIDEuMAogaW1wb3J0IFVpU291bmRNYW5hZ2VyIDEuMAogaW1wb3J0IFRoZW1lIDEu
MAoraW1wb3J0IENyaW1zb25TdGF0dXMgMS4wCitpbXBvcnQgU3lzdGVtQ29udHJvbHMgMS4wCiAK
IEFwcGxpY2F0aW9uV2luZG93IHsKKyAgICBNYXRlcmlhbC50aGVtZTogTWF0ZXJpYWwuRGFyawor
ICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAgTWF0ZXJpYWwucHJpbWFy
eTogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdX
aW5kb3cKKyAgICBNYXRlcmlhbC5mb3JlZ3JvdW5kOiBWYlRva2Vucy50ZXh0CisgICAgY29sb3I6
IFZiVG9rZW5zLmJnQXBwCisgICAgcGFsZXR0ZS53aW5kb3c6IFZiVG9rZW5zLmJnV2luZG93Cisg
ICAgcGFsZXR0ZS53aW5kb3dUZXh0OiBWYlRva2Vucy50ZXh0CisgICAgcGFsZXR0ZS5iYXNlOiBW
YlRva2Vucy5iZ0FwcAorICAgIHBhbGV0dGUuYWx0ZXJuYXRlQmFzZTogVmJUb2tlbnMuYmdFbGV2
CisgICAgcGFsZXR0ZS50ZXh0OiBWYlRva2Vucy50ZXh0CisgICAgcGFsZXR0ZS5idXR0b246IFZi
VG9rZW5zLmJnRWxldgorICAgIHBhbGV0dGUuYnV0dG9uVGV4dDogVmJUb2tlbnMudGV4dAorICAg
IHBhbGV0dGUuaGlnaGxpZ2h0OiBWYlRva2Vucy5hY2NlbnQKKyAgICBwYWxldHRlLmhpZ2hsaWdo
dGVkVGV4dDogVmJUb2tlbnMudGV4dE9uQWNjZW50CiAgICAgcHJvcGVydHkgYm9vbCBwb2xsaW5n
QWN0aXZlOiBmYWxzZQogCiAgICAgLy8gU2V0IGJ5IFNldHRpbmdzVmlldyB0byBmb3JjZSB0aGUg
YmFjayBvcGVyYXRpb24gdG8gcG9wIGFsbApAQCAtNDYsMTQgKzYzLDEzIEBAIEFwcGxpY2F0aW9u
V2luZG93IHsKICAgICAgICAgLy8gaW4gb3JkZXIgdG8gaW1wcm92ZSBjb250cmFzdCBiZXR3ZWVu
IEdGRSdzIHBsYWNlaG9sZGVyIGJveCBhcnQKICAgICAgICAgLy8gYW5kIHRoZSBiYWNrZ3JvdW5k
IG9mIHRoZSBhcHAgZ3JpZC4KICAgICAgICAgaWYgKFN5c3RlbVByb3BlcnRpZXMudXNlc01hdGVy
aWFsM1RoZW1lKSB7Ci0gICAgICAgICAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kID0gVGhlbWUuYmFj
a2dyb3VuZAorICAgICAgICAgICAgLy8gVGhlbWUgcmVtYWlucyBhIGxpdmUgYmluZGluZyB0byB0
aGUgc2hhcmVkIHBhbGV0dGUuCiAgICAgICAgIH0KIAogICAgICAgICAvLyBCcmlkZ2UgdGhlIE1h
dGVyaWFsIHN0eWxlIHRvIHRoZSBWaWJlbWlzIGRlc2lnbiB0b2tlbnMgc28gdGhlCiAgICAgICAg
IC8vIE1hdGVyaWFsLXN0eWxlZCBwYWdlcyAoQ29tcHV0ZXJzIGdyaWQsIEFwcCBncmlkLCBkaWFs
b2dzKSBzaGFyZSB0aGUgc2FtZQogICAgICAgICAvLyBhY2NlbnQvYmFja2dyb3VuZCBzeXN0ZW0g
YXMgdGhlIHRva2VuLW5hdGl2ZSBwYWdlcy4gU2VlIGRvY3MvREVTSUdOX1NZU1RFTS5tZC4KLSAg
ICAgICAgTWF0ZXJpYWwudGhlbWUgPSBNYXRlcmlhbC5EYXJrCi0gICAgICAgIE1hdGVyaWFsLmFj
Y2VudCA9IFRoZW1lLmFjY2VudAorICAgICAgICAvLyBNYXRlcmlhbCB0aGVtZS9hY2NlbnQgYXJl
IGJvdW5kIGF0IHRoZSByb290LCBpbmNsdWRpbmcgYWZ0ZXIgY2hhbmdlcy4KIAogICAgICAgICBT
ZGxHYW1lcGFkS2V5TmF2aWdhdGlvbi5lbmFibGUoKQogICAgIH0KQEAgLTI2Nyw2ICsyODMsMjUg
QEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICB9CiAgICAgfQogCisgICAgQ3JpbXNvblN0
YXR1c0RpYWxvZyB7IGlkOiBjcmltc29uUGFuZWwgfQorICAgIFN5c3RlbUNvbm5lY3Rpb25zRGlh
bG9nIHsgaWQ6IGNvbm5lY3Rpb25QYW5lbCB9CisgICAgRWNsaXBzZUFib3V0RGlhbG9nIHsgaWQ6
IGVjbGlwc2VBYm91dCB9CisgICAgRWNsaXBzZUNvbnRyb2xDZW50ZXIgeworICAgICAgICBpZDog
ZWNsaXBzZUNlbnRlcgorICAgICAgICBjYW5NYW5hZ2U6IFN5c3RlbVByb3BlcnRpZXMuaGFzQnJv
d3NlcgorICAgICAgICBjYW5XYWtlOiB0b29sQmFyLm9uUGNWaWV3CisgICAgICAgIG9uV2FrZVJl
cXVlc3RlZDogeworICAgICAgICAgICAgaWYgKHRvb2xCYXIub25QY1ZpZXcpIHN0YWNrVmlldy5j
dXJyZW50SXRlbS5jb21wdXRlck1vZGVsLndha2VDb21wdXRlcihzdGFja1ZpZXcuY3VycmVudEl0
ZW0uY3VycmVudEluZGV4KQorICAgICAgICB9CisgICAgICAgIG9uTmF2aWdhdGVSZXF1ZXN0ZWQ6
IHsKKyAgICAgICAgICAgIGlmIChkZXN0aW5hdGlvbiA9PT0gIndpZmkiIHx8IGRlc3RpbmF0aW9u
ID09PSAiYnQiKSB7IGNvbm5lY3Rpb25QYW5lbC5raW5kID0gZGVzdGluYXRpb247IGNvbm5lY3Rp
b25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJz
ZXR0aW5ncyIpIG5hdmlnYXRlVG8oInFyYzovZ3VpL1NldHRpbmdzVmlldy5xbWwiLCAiU2V0dGlu
Z3NWaWV3IikKKyAgICAgICAgICAgIGVsc2UgaWYgKGRlc3RpbmF0aW9uID09PSAiaG9zdCIpIHsg
Q3JpbXNvblN0YXR1cy5zZWxlY3RIb3N0KGVjbGlwc2VDZW50ZXIuaG9zdC5pZCB8fCAiIiwgZWNs
aXBzZUNlbnRlci5ob3N0LnVybCB8fCAiIik7IGNyaW1zb25QYW5lbC5raW5kID0gImhvc3QiOyBj
cmltc29uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAgIGVsc2UgaWYgKGRlc3RpbmF0aW9uID09
PSAiYWJvdXQiKSB7IGVjbGlwc2VBYm91dC5pbmZvID0gU3lzdGVtQ29udHJvbHMuc3RhdGU7IGVj
bGlwc2VBYm91dC5vcGVuKCkgfQorICAgICAgICAgICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09
ICJtYW5hZ2VtZW50IiAmJiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIpIFN5c3RlbVByb3Bl
cnRpZXMub3BlblVybChlY2xpcHNlQ2VudGVyLmhvc3QudXJsKQorICAgICAgICB9CisgICAgfQor
CiAgICAgaGVhZGVyOiBUb29sQmFyIHsKICAgICAgICAgaWQ6IHRvb2xCYXIKICAgICAgICAgLy8g
UmVkZXNpZ246IEVWRVJZIHJlZGVzaWduZWQgbGF1bmNoZXIgc2NyZWVuIChDb21wdXRlcnMsIEFw
cCBncmlkLCBTZXR0aW5ncywgSGVscCkKQEAgLTMzOCwyMCArMzczLDE5IEBAIEFwcGxpY2F0aW9u
V2luZG93IHsKICAgICAgICAgLy8gVklCRU1JUyB3b3JkbWFyayAoZGlhbW9uZCArIHdvcmRtYXJr
KSwgc2hvd24gb24gdGhlIENvbXB1dGVycyBzY3JlZW4gaW4gcGxhY2Ugb2YgYSB0aXRsZSwKICAg
ICAgICAgLy8gbWF0Y2hpbmcgdGhlIGRlc2lnbiBoZWFkZXIuIExlZnQtYWxpZ25lZCBhdCB0aGUg
SFRNTCdzIDQwcHggcGFkZGluZy4KICAgICAgICAgUm93IHsKLSAgICAgICAgICAgIHZpc2libGU6
IHRvb2xCYXIub25QY1ZpZXcKKyAgICAgICAgICAgIHZpc2libGU6IHRvb2xCYXIub25QY1ZpZXcg
JiYgdG9vbEJhci53aWR0aCA+IDgyMAogICAgICAgICAgICAgYW5jaG9ycy5sZWZ0OiBwYXJlbnQu
bGVmdAogICAgICAgICAgICAgYW5jaG9ycy5sZWZ0TWFyZ2luOiA0MAogICAgICAgICAgICAgYW5j
aG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVyCiAgICAgICAgICAgICBz
cGFjaW5nOiAxMQotICAgICAgICAgICAgUmVjdGFuZ2xlIHsKKyAgICAgICAgICAgIEltYWdlIHsK
ICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxD
ZW50ZXIKLSAgICAgICAgICAgICAgICB3aWR0aDogMTM7IGhlaWdodDogMTMKLSAgICAgICAgICAg
ICAgICBjb2xvcjogVmJUb2tlbnMuYWNjZW50Ci0gICAgICAgICAgICAgICAgcm90YXRpb246IDQ1
CisgICAgICAgICAgICAgICAgd2lkdGg6IDI4OyBoZWlnaHQ6IDI4CisgICAgICAgICAgICAgICAg
c291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyIKICAgICAgICAgICAgIH0KICAgICAg
ICAgICAgIFRleHQgewogICAgICAgICAgICAgICAgIGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBh
cmVudC52ZXJ0aWNhbENlbnRlcgotICAgICAgICAgICAgICAgIHRleHQ6ICJWSUJFTUlTIgorICAg
ICAgICAgICAgICAgIHRleHQ6ICJFQ0xJUFNFIgogICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5
OiBWYlRva2Vucy5mb250RGlzcGxheQogICAgICAgICAgICAgICAgIGZvbnQud2VpZ2h0OiBGb250
LkV4dHJhQm9sZAogICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiAyMQpAQCAtMzY1LDcg
KzM5OSw3IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgICAgIC8vIEhpZGRlbiBvbiBD
b21wdXRlcnMgKHRoZSB3b3JkbWFyayBzdGFuZHMgaW4pIGFuZCBvbiB0aGUgQXBwIGdyaWQgKHdo
aWNoIHNob3dzIGEKICAgICAgICAgICAgIC8vIGxlZnQtYWxpZ25lZCBob3N0ICsgc3RhdHVzIGJs
b2NrIGluc3RlYWQpLiBPbiBTZXR0aW5ncy9IZWxwIGl0IHNob3dzIHRoZSBzY3JlZW4gbmFtZTsK
ICAgICAgICAgICAgIC8vIHRoZSBzdHJlYW1pbmcgc2VndWVzIGtlZXAgdGhlaXIgZGVmYXVsdCBv
YmplY3ROYW1lIHRpdGxlLgotICAgICAgICAgICAgdmlzaWJsZTogIXRvb2xCYXIub25QY1ZpZXcg
JiYgIXRvb2xCYXIub25BcHBWaWV3ICYmIHRvb2xCYXIud2lkdGggPiA3MDAKKyAgICAgICAgICAg
IHZpc2libGU6ICF0b29sQmFyLm9uUGNWaWV3ICYmICF0b29sQmFyLm9uQXBwVmlldyAmJiB0b29s
QmFyLndpZHRoID4gODIwCiAgICAgICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAogICAgICAg
ICAgICAgdGV4dDogdG9vbEJhci5vblNldHRpbmdzID8gcXNUcigiU2V0dGluZ3MiKQogICAgICAg
ICAgICAgICAgIDogdG9vbEJhci5vbkhlbHAgPyBxc1RyKCJIZWxwIikKQEAgLTQ4Nyw2ICs1MjEs
NTQgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAg
IH0KIAorICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAg
aWQ6IG5ldHdvcmtTdGF0dXNCdXR0b24KKyAgICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJj
Oi9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZyIKKyAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5h
bWU6IHFzVHIoIldpLUZpIHNldHRpbmdzIikKKyAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2li
bGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIk5ldHdvcms6
ICUxIikuYXJnKENyaW1zb25TdGF0dXMubG9jYWwubmV0d29yayB8fCBxc1RyKCJVbmF2YWlsYWJs
ZSIpKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9
ICJ3aWZpIjsgY29ubmVjdGlvblBhbmVsLm9wZW4oKSB9CisgICAgICAgICAgICAgICAgS2V5cy5v
bkRvd25QcmVzc2VkOiBzdGFja1ZpZXcuY3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5U
YWJGb2N1cykKKyAgICAgICAgICAgICAgICBSZWN0YW5nbGUgeworICAgICAgICAgICAgICAgICAg
ICBhbmNob3JzLnJpZ2h0OiBwYXJlbnQucmlnaHQ7IGFuY2hvcnMuYm90dG9tOiBwYXJlbnQuYm90
dG9tOyBhbmNob3JzLm1hcmdpbnM6IDUKKyAgICAgICAgICAgICAgICAgICAgd2lkdGg6IDg7IGhl
aWdodDogODsgcmFkaXVzOiA0CisgICAgICAgICAgICAgICAgICAgIGNvbG9yOiBDcmltc29uU3Rh
dHVzLmxvY2FsLmNvbm5lY3RlZCA/IFZiVG9rZW5zLnN0YXR1c09ubGluZSA6IFZiVG9rZW5zLnN0
YXR1c09mZmxpbmUKKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICB9CisgICAgICAgICAg
ICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogYmx1ZXRvb3RoU2V0
dGluZ3NCdXR0b24KKyAgICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNv
bi1ibHVldG9vdGguc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigi
Qmx1ZXRvb3RoIHNldHRpbmdzIikKKyAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhv
dmVyZWQKKyAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlBhaXIgY29udHJvbGxl
cnMgYW5kIGhlYWRwaG9uZXMiKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBjb25uZWN0
aW9uUGFuZWwua2luZCA9ICJidCI7IGNvbm5lY3Rpb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAg
ICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0
aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2Fi
bGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogYmF0dGVyeVN0YXR1c0J1dHRvbgor
ICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWJhdHRlcnkuc3Zn
IgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiQmF0dGVyeSBzdGF0dXMi
KQorICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAg
ICAgIFRvb2xUaXAudGV4dDogQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAw
ID8gcXNUcigiQmF0dGVyeTogJTElIOKAoiAlMiIpLmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLmJh
dHRlcnlQZXJjZW50KS5hcmcoQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5U3RhdGUpIDogcXNU
cigiQmF0dGVyeSB1bmF2YWlsYWJsZSIpCisgICAgICAgICAgICAgICAgb25DbGlja2VkOiB7IGNy
aW1zb25QYW5lbC5raW5kID0gImJhdHRlcnkiOyBjcmltc29uUGFuZWwub3BlbigpIH0KKyAgICAg
ICAgICAgICAgICBLZXlzLm9uRG93blByZXNzZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRlbS5mb3Jj
ZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgICAgICAgICAgfQorICAgICAgICAgICAgTmF2
aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IGhvc3RIYXJkd2FyZUJ1dHRv
bgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWhvc3Quc3Zn
IgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiVmliZXBvbGxvIGhvc3Qg
aGFyZHdhcmUgc3RhdHMiKQorICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJl
ZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiSG9zdCBDUFUsIFJBTSwgR1BV
IGFuZCB0ZW1wZXJhdHVyZXMiKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeworICAgICAg
ICAgICAgICAgICAgICB2YXIgaXRlbSA9IHN0YWNrVmlldy5jdXJyZW50SXRlbQorICAgICAgICAg
ICAgICAgICAgICB2YXIgaG9zdCA9IHRvb2xCYXIub25BcHBWaWV3ID8gaXRlbS5jcmltc29uSG9z
dAorICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6ICh0b29sQmFyLm9uUGNWaWV3ID8gaXRl
bS5jb21wdXRlck1vZGVsLmNyaW1zb25Ib3N0KGl0ZW0uY3VycmVudEluZGV4KSA6IHt9KQorICAg
ICAgICAgICAgICAgICAgICBDcmltc29uU3RhdHVzLnNlbGVjdEhvc3QoaG9zdC5pZCB8fCAiIiwg
aG9zdC51cmwgfHwgIiIpCisgICAgICAgICAgICAgICAgICAgIGNyaW1zb25QYW5lbC5raW5kID0g
Imhvc3QiOyBjcmltc29uUGFuZWwub3BlbigpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAg
ICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0
aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAgICB9CisKICAgICAgICAgICAgIE5hdmln
YWJsZVRvb2xCdXR0b24gewogICAgICAgICAgICAgICAgIGlkOiBkaXNjb3JkQnV0dG9uCiAgICAg
ICAgICAgICAgICAgdmlzaWJsZTogZmFsc2UgLy8gVGVtcG9yYXJpbHkgZGlzYWJsZWQgZm9yIFZp
YmVtaXMKQEAgLTU2NCw3ICs2NDYsNyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgICAg
ICAgICAgLy8gYW4gaW5zdGFsbCBmYWlsdXJlIGZhbGxzIGJhY2sgdG8gdGhlIHJlbGVhc2UgcGFn
ZSBvbiBpdHMgb3duLgogICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogQXV0b1VwZGF0ZUNo
ZWNrZXIuaW5zdGFsbGluZwogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPyBxc1RyKCJE
b3dubG9hZGluZyB1cGRhdGXigKYiKQotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBx
c1RyKCJVcGRhdGUgYXZhaWxhYmxlIGZvciBWaWJlbWlzOiBWZXJzaW9uICUxIOKAlCB0YXAgdG8g
aW5zdGFsbCIpLmFyZyhBdXRvVXBkYXRlQ2hlY2tlci5hdmFpbGFibGVWZXJzaW9uKQorICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgOiBxc1RyKCJVcGRhdGUgYXZhaWxhYmxlIGZvciBFY2xp
cHNlOiBWZXJzaW9uICUxIOKAlCB0YXAgdG8gaW5zdGFsbCIpLmFyZyhBdXRvVXBkYXRlQ2hlY2tl
ci5hdmFpbGFibGVWZXJzaW9uKQogCiAgICAgICAgICAgICAgICAgLy8gU3RyaWN0bHktbmV3ZXIg
YnVpbGRzIG9ubHkgKGEgY2hhbm5lbC1zd2l0Y2ggZG93bmdyYWRlIG9mZmVyCiAgICAgICAgICAg
ICAgICAgLy8gbGl2ZXMgaW4gU2V0dGluZ3MsIG5vdCBvbiB0aGUgdG9vbGJhcikuCkBAIC02NDYs
NiArNzI4LDIxIEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgICAgICAgICB9CiAgICAg
ICAgICAgICB9CiAKKyAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24geworICAgICAgICAg
ICAgICAgIGlkOiBlY2xpcHNlQ2VudGVyQnV0dG9uCisgICAgICAgICAgICAgICAgaWNvblNvdXJj
ZTogInFyYzovcmVzL2VjbGlwc2UtY29udHJvbHMuc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vz
c2libGUubmFtZTogcXNUcigiRWNsaXBzZSBjb250cm9sIGNlbnRlciIpCisgICAgICAgICAgICAg
ICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCisgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0
OiBxc1RyKCJDb250cm9sIGNlbnRlciDigKIgQ3RybCtTaGlmdCtDIikKKyAgICAgICAgICAgICAg
ICBvbkNsaWNrZWQ6IHsKKyAgICAgICAgICAgICAgICAgICAgdmFyIGl0ZW0gPSBzdGFja1ZpZXcu
Y3VycmVudEl0ZW0KKyAgICAgICAgICAgICAgICAgICAgZWNsaXBzZUNlbnRlci5ob3N0ID0gdG9v
bEJhci5vbkFwcFZpZXcgPyBpdGVtLmNyaW1zb25Ib3N0IDogKHRvb2xCYXIub25QY1ZpZXcgPyBp
dGVtLmNvbXB1dGVyTW9kZWwuY3JpbXNvbkhvc3QoaXRlbS5jdXJyZW50SW5kZXgpIDoge30pCisg
ICAgICAgICAgICAgICAgICAgIGVjbGlwc2VDZW50ZXIub3BlbigpCisgICAgICAgICAgICAgICAg
fQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJ
dGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAgICAgICAgU2hvcnRj
dXQgeyBzZXF1ZW5jZTogIkN0cmwrU2hpZnQrQyI7IGVuYWJsZWQ6IHRvb2xCYXIub25QY1ZpZXcg
fHwgdG9vbEJhci5vbkFwcFZpZXc7IG9uQWN0aXZhdGVkOiBlY2xpcHNlQ2VudGVyQnV0dG9uLmNs
aWNrZWQoKSB9CisgICAgICAgICAgICB9CisKICAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0
b24gewogICAgICAgICAgICAgICAgIGlkOiBzZXR0aW5nc0J1dHRvbgogCkBAIC02NzMsNyArNzcw
LDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogCiAgICAgRXJyb3JNZXNzYWdlRGlhbG9nIHsKICAg
ICAgICAgaWQ6IG5vSHdEZWNvZGVyRGlhbG9nCi0gICAgICAgIHRleHQ6IHFzVHIoIk5vIGZ1bmN0
aW9uaW5nIGhhcmR3YXJlIGFjY2VsZXJhdGVkIHZpZGVvIGRlY29kZXIgd2FzIGRldGVjdGVkIGJ5
IFZpYmVtaXMuICIgKworICAgICAgICB0ZXh0OiBxc1RyKCJObyBmdW5jdGlvbmluZyBoYXJkd2Fy
ZSBhY2NlbGVyYXRlZCB2aWRlbyBkZWNvZGVyIHdhcyBkZXRlY3RlZCBieSBFY2xpcHNlLiAiICsK
ICAgICAgICAgICAgICAgICAgICAiWW91ciBzdHJlYW1pbmcgcGVyZm9ybWFuY2UgbWF5IGJlIHNl
dmVyZWx5IGRlZ3JhZGVkIGluIHRoaXMgY29uZmlndXJhdGlvbi4iKQogICAgICAgICBoZWxwVGV4
dDogcXNUcigiQ2xpY2sgdGhlIEhlbHAgYnV0dG9uIGZvciBtb3JlIGluZm9ybWF0aW9uIG9uIHNv
bHZpbmcgdGhpcyBwcm9ibGVtLiIpCiAgICAgICAgIGhlbHBVcmw6ICJodHRwczovL2dpdGh1Yi5j
b20vbmF2eWFzMzIxL3ZpYmVtaXMiCkBAIC02OTAsNyArNzg3LDcgQEAgQXBwbGljYXRpb25XaW5k
b3cgewogICAgIE5hdmlnYWJsZU1lc3NhZ2VEaWFsb2cgewogICAgICAgICBpZDogd293NjREaWFs
b2cKICAgICAgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuT2sgfCBEaWFsb2cuQ2FuY2VsCi0g
ICAgICAgIHRleHQ6IHFzVHIoIlRoaXMgdmVyc2lvbiBvZiBWaWJlbWlzIGlzbid0IG9wdGltaXpl
ZCBmb3IgeW91ciBQQy4gUGxlYXNlIGRvd25sb2FkIHRoZSAnJTEnIHZlcnNpb24gb2YgVmliZW1p
cyBmb3IgdGhlIGJlc3Qgc3RyZWFtaW5nIHBlcmZvcm1hbmNlLiIpLmFyZyhTeXN0ZW1Qcm9wZXJ0
aWVzLmZyaWVuZGx5TmF0aXZlQXJjaE5hbWUpCisgICAgICAgIHRleHQ6IHFzVHIoIlRoaXMgdmVy
c2lvbiBvZiBFY2xpcHNlIGlzbid0IG9wdGltaXplZCBmb3IgeW91ciBQQy4gUGxlYXNlIGRvd25s
b2FkIHRoZSAnJTEnIHZlcnNpb24gb2YgRWNsaXBzZSBmb3IgdGhlIGJlc3Qgc3RyZWFtaW5nIHBl
cmZvcm1hbmNlLiIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLmZyaWVuZGx5TmF0aXZlQXJjaE5hbWUp
CiAgICAgICAgIG9uQWNjZXB0ZWQ6IHsKICAgICAgICAgICAgIFN5c3RlbVByb3BlcnRpZXMub3Bl
blVybCgiaHR0cHM6Ly9naXRodWIuY29tL25hdnlhczMyMS92aWJlbWlzL3JlbGVhc2VzIik7CiAg
ICAgICAgIH0KQEAgLTY5OSw3ICs3OTYsNyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgRXJy
b3JNZXNzYWdlRGlhbG9nIHsKICAgICAgICAgaWQ6IHVubWFwcGVkR2FtZXBhZERpYWxvZwogICAg
ICAgICBwcm9wZXJ0eSBzdHJpbmcgdW5tYXBwZWRHYW1lcGFkcyA6ICIiCi0gICAgICAgIHRleHQ6
IHFzVHIoIlZpYmVtaXMgZGV0ZWN0ZWQgZ2FtZXBhZHMgd2l0aG91dCBhIG1hcHBpbmc6IikgKyAi
XG4iICsgdW5tYXBwZWRHYW1lcGFkcworICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIGRldGVj
dGVkIGdhbWVwYWRzIHdpdGhvdXQgYSBtYXBwaW5nOiIpICsgIlxuIiArIHVubWFwcGVkR2FtZXBh
ZHMKICAgICAgICAgaGVscFRleHRTZXBhcmF0b3I6ICJcblxuIgogICAgICAgICBoZWxwVGV4dDog
cXNUcigiQ2xpY2sgdGhlIEhlbHAgYnV0dG9uIGZvciBpbmZvcm1hdGlvbiBvbiBob3cgdG8gbWFw
IHlvdXIgZ2FtZXBhZHMuIikKICAgICAgICAgaGVscFVybDogImh0dHBzOi8vZ2l0aHViLmNvbS9u
YXZ5YXMzMjEvdmliZW1pcyIKZGlmZiAtLWdpdCBhL2FwcC9tYWluLmNwcCBiL2FwcC9tYWluLmNw
cAppbmRleCAyOTIyMjc3Li4zZWM5NGRiIDEwMDY0NAotLS0gYS9hcHAvbWFpbi5jcHAKKysrIGIv
YXBwL21haW4uY3BwCkBAIC04NjksNiArODY5LDcgQEAgaW50IG1haW4oaW50IGFyZ2MsIGNoYXIg
KmFyZ3ZbXSkKICAgICB9DQogDQogICAgIFFHdWlBcHBsaWNhdGlvbiBhcHAoYXJnYywgYXJndik7
DQorICAgIFFHdWlBcHBsaWNhdGlvbjo6c2V0QXBwbGljYXRpb25EaXNwbGF5TmFtZSgiRWNsaXBz
ZSIpOwogDQogICAgIC8vIFZpYmVtaXM6IHRoZSBRdCBRdWljayBDb250cm9scyBNYXRlcmlhbCBz
dHlsZSByZW5kZXJzIGJ1dHRvbiB0ZXh0IGluIEFMTCBDQVBTIGJ5IGRlZmF1bHQNCiAgICAgLy8g
KGUuZy4gdGhlIGJpdHJhdGUgIlVTRSBERUZBVUxUICgzMCBNQlBTKSIgYnV0dG9uKSwgd2hpY2gg
bG9va3Mgb2ZmLiBGb3JjZSBtaXhlZCBjYXNlIGZvciB0aGUNCmRpZmYgLS1naXQgYS9hcHAvbW9v
bmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5jcHAgYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1
cy5jcHAKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uZGFmY2EyZQotLS0gL2Rl
di9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcApAQCAtMCwwICsx
LDIyMiBAQAorI2luY2x1ZGUgImNyaW1zb25zdGF0dXMuaCIKKyNpbmNsdWRlIDxRRGF0ZVRpbWU+
CisjaW5jbHVkZSA8UURpcj4KKyNpbmNsdWRlIDxRRmlsZT4KKyNpbmNsdWRlIDxRSnNvbkRvY3Vt
ZW50PgorI2luY2x1ZGUgPFFKc29uT2JqZWN0PgorI2luY2x1ZGUgPFFOZXR3b3JrSW50ZXJmYWNl
PgorI2luY2x1ZGUgPFFOZXR3b3JrUmVxdWVzdD4KKyNpbmNsdWRlIDxRU2F2ZUZpbGU+CisjaW5j
bHVkZSA8UVNzbENlcnRpZmljYXRlPgorI2luY2x1ZGUgPFFTc2xFcnJvcj4KKyNpbmNsdWRlIDxR
U3RhbmRhcmRQYXRocz4KKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVkZSA8
UVVybD4KKyNpbmNsdWRlIDxjbWF0aD4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUg
PFFDb3JlQXBwbGljYXRpb24+CisjaW5jbHVkZSA8bWVtb3J5PgorI2luY2x1ZGUgPFFSZWd1bGFy
RXhwcmVzc2lvbj4KKyNpbmNsdWRlIDxRRmlsZUluZm8+CisjaW5jbHVkZSA8UVNzbENvbmZpZ3Vy
YXRpb24+CisKK25hbWVzcGFjZSB7CitRU3RyaW5nIHJlYWQoY29uc3QgUVN0cmluZyYgcGF0aCkg
eworICAgIFFGaWxlIGYocGF0aCk7IHJldHVybiBmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkg
PyBRU3RyaW5nOjpmcm9tVXRmOChmLnJlYWRBbGwoKSkudHJpbW1lZCgpIDogUVN0cmluZygpOwor
fQorY29uc3QgYXV0byB1c2VyT25seSA9IFFGaWxlRGV2aWNlOjpSZWFkT3duZXIgfCBRRmlsZURl
dmljZTo6V3JpdGVPd25lcjsKK30KK0NyaW1zb25TdGF0dXM6OkNyaW1zb25TdGF0dXMoUU9iamVj
dCogcGFyZW50KSA6IFFPYmplY3QocGFyZW50KSB7CisgICAgY29ubmVjdCgmbV9sb2NhbFRpbWVy
LCAmUVRpbWVyOjp0aW1lb3V0LCB0aGlzLCAmQ3JpbXNvblN0YXR1czo6cmVmcmVzaExvY2FsKTsK
KyAgICBjb25uZWN0KCZtX3N0YXRzVGltZXIsICZRVGltZXI6OnRpbWVvdXQsIHRoaXMsICZDcmlt
c29uU3RhdHVzOjpyZWZyZXNoKTsKKyAgICBjb25uZWN0KCZtX3dpZmksICZRUHJvY2Vzczo6Zmlu
aXNoZWQsIHRoaXMsIFt0aGlzXShpbnQgZXhpdCwgUVByb2Nlc3M6OkV4aXRTdGF0dXMpIHsKKyAg
ICAgICAgaWYgKGV4aXQgPT0gMCkgeworICAgICAgICAgICAgY29uc3QgYXV0byBsaW5lcyA9IFFT
dHJpbmc6OmZyb21VdGY4KG1fd2lmaS5yZWFkQWxsU3RhbmRhcmRPdXRwdXQoKSkuc3BsaXQoJ1xu
Jyk7CisgICAgICAgICAgICBmb3IgKGNvbnN0IGF1dG8mIGxpbmUgOiBsaW5lcykgeworICAgICAg
ICAgICAgICAgIGlmICghbGluZS5zdGFydHNXaXRoKCJ5ZXM6IikpIGNvbnRpbnVlOworICAgICAg
ICAgICAgICAgIGludCBzZXBhcmF0b3IgPSBsaW5lLmluZGV4T2YoJzonLCA0KTsgYm9vbCBvayA9
IGZhbHNlOworICAgICAgICAgICAgICAgIGludCBzaWduYWwgPSBsaW5lLm1pZCg0LCBzZXBhcmF0
b3IgLSA0KS50b0ludCgmb2spOworICAgICAgICAgICAgICAgIGlmIChvayAmJiBzaWduYWwgPj0g
MCAmJiBzaWduYWwgPD0gMTAwKSBtX2xvY2FsWyJ3aWZpU2lnbmFsIl0gPSBzaWduYWw7CisgICAg
ICAgICAgICAgICAgaWYgKHNlcGFyYXRvciA+PSAwKSBtX2xvY2FsWyJuZXR3b3JrIl0gPSB0cigi
V2ktRmk6ICUxIikuYXJnKGxpbmUubWlkKHNlcGFyYXRvciArIDEpKTsKKyAgICAgICAgICAgICAg
ICBicmVhazsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGVtaXQgbG9jYWxDaGFuZ2VkKCk7
CisgICAgICAgIH0KKyAgICB9KTsKKyAgICBtX2xvY2FsVGltZXIuc3RhcnQoMTAwMDApOyBtX3N0
YXRzVGltZXIuc2V0SW50ZXJ2YWwoMjAwMCk7IHJlZnJlc2hMb2NhbCgpOworfQorQ3JpbXNvblN0
YXR1czo6fkNyaW1zb25TdGF0dXMoKSB7CisgICAgbV9zdGF0c1RpbWVyLnN0b3AoKTsgbV9sb2Nh
bFRpbWVyLnN0b3AoKTsgY2FuY2VsKCk7CisgICAgaWYgKG1fd2lmaS5zdGF0ZSgpICE9IFFQcm9j
ZXNzOjpOb3RSdW5uaW5nKSB7IG1fd2lmaS5raWxsKCk7IG1fd2lmaS53YWl0Rm9yRmluaXNoZWQo
NTAwKTsgfQorfQorUVN0cmluZyBDcmltc29uU3RhdHVzOjpjb25maWdGaWxlKCkgY29uc3Qgewor
ICAgIHJldHVybiBRU3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRhcmRQYXRo
czo6QXBwQ29uZmlnTG9jYXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpzb24iOworfQorUVN0cmlu
ZyBDcmltc29uU3RhdHVzOjpub3JtYWxpemVkUGluKFFTdHJpbmcgcGluKSB7CisgICAgcGluLnJl
bW92ZSgnOicpOyBwaW4ucmVtb3ZlKCcgJyk7IHJldHVybiBwaW4udG9Mb3dlcigpOworfQorYm9v
bCBDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KGNvbnN0IFFTdHJpbmcmIHZhbHVlKSB7Cisg
ICAgUVVybCB1KHZhbHVlLCBRVXJsOjpTdHJpY3RNb2RlKTsKKyAgICByZXR1cm4gdS5pc1ZhbGlk
KCkgJiYgdS5zY2hlbWUoKSA9PSAiaHR0cHMiICYmICF1Lmhvc3QoKS5pc0VtcHR5KCkgJiYKKyAg
ICAgICAgdS51c2VySW5mbygpLmlzRW1wdHkoKSAmJiB1LnF1ZXJ5KCkuaXNFbXB0eSgpICYmIHUu
ZnJhZ21lbnQoKS5pc0VtcHR5KCkgJiYKKyAgICAgICAgKHUucGF0aCgpLmlzRW1wdHkoKSB8fCB1
LnBhdGgoKSA9PSAiLyIpICYmIHUucG9ydCg0Nzk5MCkgPiAwOworfQordm9pZCBDcmltc29uU3Rh
dHVzOjpjYW5jZWwoKSB7CisgICAgaWYgKG1fcmVwbHkpIHsgZGlzY29ubmVjdChtX3JlcGx5LCBu
dWxscHRyLCB0aGlzLCBudWxscHRyKTsgbV9yZXBseS0+YWJvcnQoKTsgbV9yZXBseS0+ZGVsZXRl
TGF0ZXIoKTsgbV9yZXBseSA9IG51bGxwdHI7IH0KK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6c2Vs
ZWN0SG9zdChRU3RyaW5nIGlkLCBRU3RyaW5nIHN1Z2dlc3RlZFVybCkgeworICAgIGlmIChpZCA9
PSBtX2hvc3QpIHJldHVybjsKKyAgICBjYW5jZWwoKTsgbV9uZXR3b3JrLmNsZWFyQ29ubmVjdGlv
bkNhY2hlKCk7IG1faG9zdCA9IGlkOyBtX3Rva2VuLmNsZWFyKCk7IG1fcGluLmNsZWFyKCk7Cisg
ICAgbV9lbmRwb2ludCA9IHZhbGlkRW5kcG9pbnQoc3VnZ2VzdGVkVXJsKSA/IHN1Z2dlc3RlZFVy
bCA6IFFTdHJpbmcoKTsKKyAgICBRRmlsZSBmKGNvbmZpZ0ZpbGUoKSk7CisgICAgaWYgKGYub3Bl
bihRSU9EZXZpY2U6OlJlYWRPbmx5KSkgeworICAgICAgICBhdXRvIGMgPSBRSnNvbkRvY3VtZW50
Ojpmcm9tSnNvbihmLnJlYWRBbGwoKSkub2JqZWN0KCkudmFsdWUoaWQpLnRvT2JqZWN0KCk7Cisg
ICAgICAgIGlmICh2YWxpZEVuZHBvaW50KGMudmFsdWUoInVybCIpLnRvU3RyaW5nKCkpKSB7Cisg
ICAgICAgICAgICBtX2VuZHBvaW50ID0gYy52YWx1ZSgidXJsIikudG9TdHJpbmcoKTsgbV90b2tl
biA9IGMudmFsdWUoInRva2VuIikudG9TdHJpbmcoKTsgbV9waW4gPSBjLnZhbHVlKCJwaW4iKS50
b1N0cmluZygpOworICAgICAgICB9CisgICAgfQorICAgIG1fc3RhdHMuY2xlYXIoKTsgbV9zdGF0
dXMgPSBpZC5pc0VtcHR5KCkgPyB0cigiQ2hvb3NlIGEgaG9zdCB0byB2aWV3IGhhcmR3YXJlIHN0
YXRzIikgOiB0cigiQ29uZmlndXJlIGEgVmliZXBvbGxvIHJlYWQtb25seSBzdGF0cyB0b2tlbiIp
OworICAgIGVtaXQgY29uZmlnQ2hhbmdlZCgpOyBlbWl0IHN0YXRzQ2hhbmdlZCgpOyBpZiAobV92
aXNpYmxlKSByZWZyZXNoKCk7Cit9Citib29sIENyaW1zb25TdGF0dXM6OmNvbmZpZ3VyZShRU3Ry
aW5nIHVybCwgUVN0cmluZyB0b2tlbiwgUVN0cmluZyBwaW4pIHsKKyAgICBwaW4gPSBub3JtYWxp
emVkUGluKHBpbik7CisgICAgaWYgKG1faG9zdC5pc0VtcHR5KCkgfHwgIXZhbGlkRW5kcG9pbnQo
dXJsKSB8fCAoIXBpbi5pc0VtcHR5KCkgJiYKKyAgICAgICAgKHBpbi5zaXplKCkgIT0gNjQgfHwg
cGluLmNvbnRhaW5zKFFSZWd1bGFyRXhwcmVzc2lvbigiW14wLTlhLWZdIikpKSkpIHsKKyAgICAg
ICAgZmFpbCh0cigiVXNlIGFuIEhUVFBTIGhvc3QgVVJMIGFuZCBhbiBvcHRpb25hbCA2NC1kaWdp
dCBTSEEtMjU2IGNlcnRpZmljYXRlIGZpbmdlcnByaW50IikpOyByZXR1cm4gZmFsc2U7CisgICAg
fQorICAgIC8vIEEgYmxhbmsgdG9rZW4ga2VlcHMgdGhlIG9sZCB0b2tlbiBvbmx5IGZvciB0aGUg
c2FtZSBlbmRwb2ludC4KKyAgICBpZiAodG9rZW4uaXNFbXB0eSgpICYmIFFVcmwodXJsKSA9PSBR
VXJsKG1fZW5kcG9pbnQpKSB0b2tlbiA9IG1fdG9rZW47CisgICAgaWYgKHRva2VuLmlzRW1wdHko
KSB8fCB0b2tlbi5jb250YWlucygnXHInKSB8fCB0b2tlbi5jb250YWlucygnXG4nKSB8fCB0b2tl
bi5zaXplKCkgPiA0MDk2KSB7CisgICAgICAgIGZhaWwodHIoIkEgcmVhZC1vbmx5IFZpYmVwb2xs
byBBUEkgdG9rZW4gaXMgcmVxdWlyZWQiKSk7IHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgUUZp
bGUgZihjb25maWdGaWxlKCkpOyBRSnNvbk9iamVjdCBhbGw7CisgICAgaWYgKGYub3BlbihRSU9E
ZXZpY2U6OlJlYWRPbmx5KSkgYWxsID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24oZi5yZWFkQWxs
KCkpLm9iamVjdCgpOworICAgIGFsbFttX2hvc3RdID0gUUpzb25PYmplY3R7eyJ1cmwiLCB1cmx9
LCB7InRva2VuIiwgdG9rZW59LCB7InBpbiIsIHBpbn19OworICAgIFFEaXIoKS5ta3BhdGgoUUZp
bGVJbmZvKGNvbmZpZ0ZpbGUoKSkuYWJzb2x1dGVQYXRoKCkpOworICAgIFFTYXZlRmlsZSBvdXQo
Y29uZmlnRmlsZSgpKTsKKyAgICBpZiAoIW91dC5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSB8
fCAhb3V0LnNldFBlcm1pc3Npb25zKHVzZXJPbmx5KSB8fAorICAgICAgICBvdXQud3JpdGUoUUpz
b25Eb2N1bWVudChhbGwpLnRvSnNvbigpKSA8IDAgfHwgIW91dC5jb21taXQoKSkgeworICAgICAg
ICBmYWlsKHRyKCJDb3VsZCBub3Qgc2F2ZSBob3N0IGFjY2VzcyBzZXR0aW5ncyIpKTsgcmV0dXJu
IGZhbHNlOworICAgIH0KKyAgICBjYW5jZWwoKTsgbV9uZXR3b3JrLmNsZWFyQ29ubmVjdGlvbkNh
Y2hlKCk7IG1fZW5kcG9pbnQgPSB1cmw7IG1fdG9rZW4gPSB0b2tlbjsgbV9waW4gPSBwaW47Cisg
ICAgbV9zdGF0c1RpbWVyLnNldEludGVydmFsKDIwMDApOworICAgIG1fc3RhdHMuY2xlYXIoKTsg
bV9zdGF0dXMgPSB0cigiQ29ubmVjdGluZyB0byBob3N0IHN0YXRz4oCmIik7CisgICAgZW1pdCBj
b25maWdDaGFuZ2VkKCk7IGVtaXQgc3RhdHNDaGFuZ2VkKCk7IHJlZnJlc2goKTsgcmV0dXJuIHRy
dWU7Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OnNldFZpc2libGUoYm9vbCB2aXNpYmxlKSB7Cisg
ICAgbV92aXNpYmxlID0gdmlzaWJsZTsKKyAgICBpZiAodmlzaWJsZSkgeyByZWZyZXNoTG9jYWwo
KTsgbV9zdGF0c1RpbWVyLnN0YXJ0KCk7IHJlZnJlc2goKTsgfQorICAgIGVsc2UgeyBtX3N0YXRz
VGltZXIuc3RvcCgpOyBjYW5jZWwoKTsgfQorfQordm9pZCBDcmltc29uU3RhdHVzOjpmYWlsKFFT
dHJpbmcgbWVzc2FnZSkgeworICAgIG1fc3RhdHMuY2xlYXIoKTsgbV9zdGF0dXMgPSBtZXNzYWdl
OworICAgIG1fc3RhdHNUaW1lci5zZXRJbnRlcnZhbChxTWluKDMwMDAwLCBxTWF4KDQwMDAsIG1f
c3RhdHNUaW1lci5pbnRlcnZhbCgpICogMikpKTsKKyAgICBlbWl0IHN0YXRzQ2hhbmdlZCgpOwor
fQorUVZhcmlhbnRNYXAgQ3JpbXNvblN0YXR1czo6cGFyc2VTdGF0cyhjb25zdCBRQnl0ZUFycmF5
JiBieXRlcywgUVN0cmluZyogZXJyb3IpIHsKKyAgICBpZiAoYnl0ZXMuc2l6ZSgpID4gNjU1MzYp
IHsgKmVycm9yID0gIk92ZXJzaXplZCBob3N0IHN0YXRzIHJlc3BvbnNlIjsgcmV0dXJuIHt9OyB9
CisgICAgUUpzb25QYXJzZUVycm9yIGU7IGF1dG8gZG9jID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpz
b24oYnl0ZXMsICZlKTsKKyAgICBpZiAoZS5lcnJvciAhPSBRSnNvblBhcnNlRXJyb3I6Ok5vRXJy
b3IgfHwgIWRvYy5pc09iamVjdCgpKSB7ICplcnJvciA9ICJJbnZhbGlkIGhvc3Qgc3RhdHMgcmVz
cG9uc2UiOyByZXR1cm4ge307IH0KKyAgICBhdXRvIG9iaiA9IGRvYy5vYmplY3QoKTsgUVZhcmlh
bnRNYXAgcmVzdWx0OworICAgIGNvbnN0IFFTdHJpbmdMaXN0IGtleXMgPSB7ImNwdV9wZXJjZW50
IiwiY3B1X3RlbXBfYyIsInJhbV91c2VkX2J5dGVzIiwicmFtX3RvdGFsX2J5dGVzIiwicmFtX3Bl
cmNlbnQiLAorICAgICAgICAiZ3B1X3BlcmNlbnQiLCJncHVfZW5jb2Rlcl9wZXJjZW50IiwiZ3B1
X3RlbXBfYyIsInZyYW1fdXNlZF9ieXRlcyIsInZyYW1fdG90YWxfYnl0ZXMiLCJ2cmFtX3BlcmNl
bnQiLCJuZXRfcnhfYnBzIiwibmV0X3R4X2JwcyJ9OworICAgIGJvb2wgcmVjb2duaXplZCA9IGZh
bHNlOworICAgIGZvciAoY29uc3QgYXV0byYga2V5IDoga2V5cykgeworICAgICAgICBhdXRvIHYg
PSBvYmoudmFsdWUoa2V5KTsgcmVjb2duaXplZCB8PSBvYmouY29udGFpbnMoa2V5KTsKKyAgICAg
ICAgZG91YmxlIG4gPSB2LnRvRG91YmxlKC0xKTsKKyAgICAgICAgaWYgKCF2LmlzRG91YmxlKCkg
fHwgIXN0ZDo6aXNmaW5pdGUobikgfHwgbiA8IDAgfHwgKGtleS5lbmRzV2l0aCgicGVyY2VudCIp
ICYmIG4gPiAxMDApKSBjb250aW51ZTsKKyAgICAgICAgcmVzdWx0W2tleV0gPSBuOworICAgIH0K
KyAgICBmb3IgKGNvbnN0IGF1dG8mIHByZWZpeCA6IHtRU3RyaW5nKCJyYW0iKSwgUVN0cmluZygi
dnJhbSIpfSkgeworICAgICAgICBkb3VibGUgdG90YWwgPSByZXN1bHQudmFsdWUocHJlZml4ICsg
Il90b3RhbF9ieXRlcyIpLnRvRG91YmxlKCk7CisgICAgICAgIGlmICh0b3RhbCA8PSAwKSB7IHJl
c3VsdC5yZW1vdmUocHJlZml4ICsgIl9wZXJjZW50Iik7IHJlc3VsdC5yZW1vdmUocHJlZml4ICsg
Il91c2VkX2J5dGVzIik7IH0KKyAgICAgICAgZWxzZSBpZiAocmVzdWx0LmNvbnRhaW5zKHByZWZp
eCArICJfdXNlZF9ieXRlcyIpKSB7CisgICAgICAgICAgICBkb3VibGUgdXNlZCA9IHFNaW4ocmVz
dWx0LnZhbHVlKHByZWZpeCArICJfdXNlZF9ieXRlcyIpLnRvRG91YmxlKCksIHRvdGFsKTsKKyAg
ICAgICAgICAgIHJlc3VsdFtwcmVmaXggKyAiX3VzZWRfYnl0ZXMiXSA9IHVzZWQ7IHJlc3VsdFtw
cmVmaXggKyAiX3BlcmNlbnQiXSA9IHVzZWQgKiAxMDAgLyB0b3RhbDsKKyAgICAgICAgfQorICAg
IH0KKyAgICBpZiAoIXJlY29nbml6ZWQpIHsgKmVycm9yID0gIkhvc3QgZG9lcyBub3QgZXhwb3Nl
IHRoZSBleHBlY3RlZCBWaWJlcG9sbG8gc3RhdHMgZmllbGRzIjsgcmV0dXJuIHt9OyB9CisgICAg
ZXJyb3ItPmNsZWFyKCk7IHJldHVybiByZXN1bHQ7Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OnJl
ZnJlc2goKSB7CisgICAgaWYgKCFtX3Zpc2libGUgfHwgbV9yZXBseSB8fCAhY29uZmlndXJlZCgp
KSByZXR1cm47CisgICAgUVVybCB1cmwobV9lbmRwb2ludCk7IHVybC5zZXRQYXRoKCIvYXBpL2hv
c3Qvc3RhdHMiKTsKKyAgICBRTmV0d29ya1JlcXVlc3QgcmVxKHVybCk7CisgICAgcmVxLnNldEF0
dHJpYnV0ZShRTmV0d29ya1JlcXVlc3Q6OlJlZGlyZWN0UG9saWN5QXR0cmlidXRlLCBRTmV0d29y
a1JlcXVlc3Q6Ok1hbnVhbFJlZGlyZWN0UG9saWN5KTsKKyAgICByZXEuc2V0VHJhbnNmZXJUaW1l
b3V0KDMwMDApOworICAgIHJlcS5zZXRSYXdIZWFkZXIoIkF1dGhvcml6YXRpb24iLCAiQmVhcmVy
ICIgKyBtX3Rva2VuLnRvVXRmOCgpKTsKKyAgICByZXEuc2V0UmF3SGVhZGVyKCJBY2NlcHQiLCAi
YXBwbGljYXRpb24vanNvbiIpOworICAgIGF1dG8gcmVwbHkgPSBtX25ldHdvcmsuZ2V0KHJlcSk7
IHJlcGx5LT5zZXRSZWFkQnVmZmVyU2l6ZSg2NTUzNik7IG1fcmVwbHkgPSByZXBseTsKKyAgICBh
dXRvIGRhdGEgPSBzdGQ6Om1ha2Vfc2hhcmVkPFFCeXRlQXJyYXk+KCk7CisgICAgYXV0byBpbnZh
bGlkUGluID0gc3RkOjptYWtlX3NoYXJlZDxib29sPihmYWxzZSk7CisgICAgYXV0byBvdmVyc2l6
ZWQgPSBzdGQ6Om1ha2Vfc2hhcmVkPGJvb2w+KGZhbHNlKTsKKyAgICBhdXRvIGNlcnRNYXRjaGVz
ID0gW3RoaXMsIHJlcGx5XSB7CisgICAgICAgIHJldHVybiBub3JtYWxpemVkUGluKFFTdHJpbmc6
OmZyb21MYXRpbjEocmVwbHktPnNzbENvbmZpZ3VyYXRpb24oKS5wZWVyQ2VydGlmaWNhdGUoKS5k
aWdlc3QoUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpKSA9PSBtX3BpbjsKKyAg
ICB9OworICAgIGNvbm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5OjplbmNyeXB0ZWQsIHRoaXMs
IFt0aGlzLCByZXBseSwgY2VydE1hdGNoZXMsIGludmFsaWRQaW5dIHsKKyAgICAgICAgaWYgKCFt
X3Bpbi5pc0VtcHR5KCkgJiYgIWNlcnRNYXRjaGVzKCkpIHsgKmludmFsaWRQaW4gPSB0cnVlOyBy
ZXBseS0+YWJvcnQoKTsgfQorICAgIH0pOworICAgIGNvbm5lY3QocmVwbHksICZRTmV0d29ya1Jl
cGx5Ojpzc2xFcnJvcnMsIHRoaXMsIFt0aGlzLCByZXBseSwgY2VydE1hdGNoZXNdKGNvbnN0IFFM
aXN0PFFTc2xFcnJvcj4mIGVycm9ycykgeworICAgICAgICBpZiAobV9waW4uaXNFbXB0eSgpIHx8
ICFjZXJ0TWF0Y2hlcygpKSByZXR1cm47CisgICAgICAgIGZvciAoY29uc3QgYXV0byYgZSA6IGVy
cm9ycykgeworICAgICAgICAgICAgaWYgKGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6OlNlbGZTaWdu
ZWRDZXJ0aWZpY2F0ZSAmJiBlLmVycm9yKCkgIT0gUVNzbEVycm9yOjpTZWxmU2lnbmVkQ2VydGlm
aWNhdGVJbkNoYWluICYmCisgICAgICAgICAgICAgICAgZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6
Q2VydGlmaWNhdGVVbnRydXN0ZWQgJiYgZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6SG9zdE5hbWVN
aXNtYXRjaCkgcmV0dXJuOworICAgICAgICB9CisgICAgICAgIHJlcGx5LT5pZ25vcmVTc2xFcnJv
cnMoZXJyb3JzKTsgLy8gT25seSB0aGlzIGV4cGxpY2l0bHkgcGlubmVkIGhvc3QgY2VydGlmaWNh
dGUuCisgICAgfSk7CisgICAgY29ubmVjdChyZXBseSwgJlFOZXR3b3JrUmVwbHk6OnJlYWR5UmVh
ZCwgdGhpcywgW3JlcGx5LCBkYXRhLCBvdmVyc2l6ZWRdIHsKKyAgICAgICAgaWYgKCpvdmVyc2l6
ZWQgfHwgcmVwbHktPmlzRmluaXNoZWQoKSkgcmV0dXJuOworICAgICAgICBpZiAoZGF0YS0+c2l6
ZSgpICsgcmVwbHktPmJ5dGVzQXZhaWxhYmxlKCkgPiA2NTUzNikgeyAqb3ZlcnNpemVkID0gdHJ1
ZTsgcmVwbHktPmFib3J0KCk7IHJldHVybjsgfQorICAgICAgICBkYXRhLT5hcHBlbmQocmVwbHkt
PnJlYWRBbGwoKSk7CisgICAgfSk7CisgICAgY29ubmVjdChyZXBseSwgJlFOZXR3b3JrUmVwbHk6
OmZpbmlzaGVkLCB0aGlzLCBbdGhpcywgcmVwbHksIGRhdGEsIGludmFsaWRQaW4sIG92ZXJzaXpl
ZF0geworICAgICAgICBtX3JlcGx5ID0gbnVsbHB0cjsKKyAgICAgICAgaW50IHN0YXR1cyA9IHJl
cGx5LT5hdHRyaWJ1dGUoUU5ldHdvcmtSZXF1ZXN0OjpIdHRwU3RhdHVzQ29kZUF0dHJpYnV0ZSku
dG9JbnQoKTsKKyAgICAgICAgaWYgKCpvdmVyc2l6ZWQpIGZhaWwodHIoIkhvc3Qgc3RhdHMgcmVz
cG9uc2UgZXhjZWVkZWQgdGhlIHNpemUgbGltaXQiKSk7CisgICAgICAgIGVsc2UgaWYgKCppbnZh
bGlkUGluKSBmYWlsKHRyKCJIb3N0IGNlcnRpZmljYXRlIGNoYW5nZWQ7IHZlcmlmeSB0aGUgc2F2
ZWQgZmluZ2VycHJpbnQiKSk7CisgICAgICAgIGVsc2UgaWYgKHN0YXR1cyA9PSA0MDEgfHwgc3Rh
dHVzID09IDQwMykgZmFpbCh0cigiSG9zdCBzdGF0cyBhY2Nlc3MgZGVuaWVkOiBjaGVjayB0aGUg
cmVhZC1vbmx5IHRva2VuIikpOworICAgICAgICBlbHNlIGlmIChzdGF0dXMgPT0gNDA0KSBmYWls
KHRyKCJUaGlzIGhvc3QgZG9lcyBub3QgcHJvdmlkZSBWaWJlcG9sbG8gaGFyZHdhcmUgc3RhdHMi
KSk7CisgICAgICAgIGVsc2UgaWYgKHJlcGx5LT5lcnJvcigpID09IFFOZXR3b3JrUmVwbHk6OlNz
bEhhbmRzaGFrZUZhaWxlZEVycm9yKSBmYWlsKHRyKCJWZXJpZnkgdGhlIGhvc3QgY2VydGlmaWNh
dGUgZmluZ2VycHJpbnQgaW4gQ29uZmlndXJlIikpOworICAgICAgICBlbHNlIGlmIChyZXBseS0+
ZXJyb3IoKSAhPSBRTmV0d29ya1JlcGx5OjpOb0Vycm9yIHx8IHN0YXR1cyAhPSAyMDApIGZhaWwo
dHIoIkhvc3Qgc3RhdHMgdW5hdmFpbGFibGU6IGNoZWNrIGNvbm5lY3Rpb24gYW5kIHJlYWx0aW1l
IHN0YXRzIHNldHRpbmciKSk7CisgICAgICAgIGVsc2UgeworICAgICAgICAgICAgZGF0YS0+YXBw
ZW5kKHJlcGx5LT5yZWFkQWxsKCkpOyBRU3RyaW5nIGVycm9yOworICAgICAgICAgICAgYXV0byBw
YXJzZWQgPSBwYXJzZVN0YXRzKCpkYXRhLCAmZXJyb3IpOworICAgICAgICAgICAgaWYgKCFlcnJv
ci5pc0VtcHR5KCkpIGZhaWwoZXJyb3IpOworICAgICAgICAgICAgZWxzZSB7IG1fc3RhdHNUaW1l
ci5zZXRJbnRlcnZhbCgyMDAwKTsgbV9zdGF0cyA9IHBhcnNlZDsgbV9zdGF0dXMgPSB0cigiSE9T
VCDigKIgcmVjZWl2ZWQgJTEiKS5hcmcoUURhdGVUaW1lOjpjdXJyZW50RGF0ZVRpbWUoKS50b1N0
cmluZygiaGg6bW06c3MiKSk7IGVtaXQgc3RhdHNDaGFuZ2VkKCk7IH0KKyAgICAgICAgfQorICAg
ICAgICByZXBseS0+ZGVsZXRlTGF0ZXIoKTsKKyAgICB9KTsKKyAgICAvLyBBYnNvbHV0ZSByZXF1
ZXN0IGJvdW5kIGV2ZW4gaWYgYSBwZWVyIGtlZXBzIHNlbmRpbmcgb2NjYXNpb25hbCBieXRlcy4K
KyAgICBRVGltZXI6OnNpbmdsZVNob3QoMzUwMCwgcmVwbHksIFtyZXBseV0geyBpZiAoIXJlcGx5
LT5pc0ZpbmlzaGVkKCkpIHJlcGx5LT5hYm9ydCgpOyB9KTsKK30KK1FWYXJpYW50TWFwIENyaW1z
b25TdGF0dXM6OnJlYWRMb2NhbChjb25zdCBRU3RyaW5nJiByb290KSB7CisgICAgUVZhcmlhbnRN
YXAgb3V0OyBRU3RyaW5nTGlzdCBuZXR3b3JrczsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIG5hbWUg
OiBRRGlyKHJvb3QgKyAiL2NsYXNzL25ldCIpLmVudHJ5TGlzdChRRGlyOjpEaXJzIHwgUURpcjo6
Tm9Eb3RBbmREb3REb3QpKSB7CisgICAgICAgIGlmIChuYW1lID09ICJsbyIgfHwgcmVhZChyb290
ICsgIi9jbGFzcy9uZXQvIiArIG5hbWUgKyAiL29wZXJzdGF0ZSIpICE9ICJ1cCIpIGNvbnRpbnVl
OworICAgICAgICBuZXR3b3JrcyA8PCBuYW1lOworICAgIH0KKyAgICBvdXRbImNvbm5lY3RlZCJd
ID0gIW5ldHdvcmtzLmlzRW1wdHkoKTsgb3V0WyJuZXR3b3JrIl0gPSBuZXR3b3Jrcy5pc0VtcHR5
KCkgPyB0cigiTm8gYWN0aXZlIG5ldHdvcmsgbGluayIpIDogbmV0d29ya3Muam9pbigiLCAiKTsK
KyAgICAvLyBMaW5rIHN0YXR1cyBpcyBpbnRlbnRpb25hbGx5IG5vdCBwcmVzZW50ZWQgYXMgaW50
ZXJuZXQgcmVhY2hhYmlsaXR5LgorICAgIG91dFsiYmF0dGVyeVBlcmNlbnQiXSA9IC0xOyBvdXRb
ImJhdHRlcnlTdGF0ZSJdID0gdHIoIkJhdHRlcnkgdW5hdmFpbGFibGUiKTsKKyAgICBmb3IgKGNv
bnN0IGF1dG8mIG5hbWUgOiBRRGlyKHJvb3QgKyAiL2NsYXNzL3Bvd2VyX3N1cHBseSIpLmVudHJ5
TGlzdChRRGlyOjpEaXJzIHwgUURpcjo6Tm9Eb3RBbmREb3REb3QpKSB7CisgICAgICAgIGNvbnN0
IGF1dG8gYmFzZSA9IHJvb3QgKyAiL2NsYXNzL3Bvd2VyX3N1cHBseS8iICsgbmFtZSArICIvIjsK
KyAgICAgICAgaWYgKHJlYWQoYmFzZSArICJ0eXBlIikgIT0gIkJhdHRlcnkiIHx8IHJlYWQoYmFz
ZSArICJwcmVzZW50IikgPT0gIjAiKSBjb250aW51ZTsKKyAgICAgICAgYm9vbCBvazsgaW50IGNh
cCA9IHJlYWQoYmFzZSArICJjYXBhY2l0eSIpLnRvSW50KCZvayk7CisgICAgICAgIGlmIChvayAm
JiBjYXAgPj0gMCAmJiBjYXAgPD0gMTAwKSBvdXRbImJhdHRlcnlQZXJjZW50Il0gPSBjYXA7Cisg
ICAgICAgIGNvbnN0IGF1dG8gc3RhdGUgPSByZWFkKGJhc2UgKyAic3RhdHVzIik7IG91dFsiYmF0
dGVyeVN0YXRlIl0gPSBzdGF0ZS5pc0VtcHR5KCkgPyB0cigiVW5rbm93biIpIDogc3RhdGU7IGJy
ZWFrOworICAgIH0KKyAgICByZXR1cm4gb3V0OworfQordm9pZCBDcmltc29uU3RhdHVzOjpyZWZy
ZXNoTG9jYWwoKSB7CisgICAgbV9sb2NhbCA9IHJlYWRMb2NhbCgpOyBtX2xvY2FsWyJ3aWZpU2ln
bmFsIl0gPSAtMTsgZW1pdCBsb2NhbENoYW5nZWQoKTsKKyAgICBpZiAobV93aWZpLnN0YXRlKCkg
PT0gUVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIHsKKyAgICAgICAgbV93aWZpLnN0YXJ0KCJubWNsaSIs
IHsiLXQiLCAiLS1lc2NhcGUiLCAibm8iLCAiLWYiLCAiQUNUSVZFLFNJR05BTCxTU0lEIiwgImRl
dmljZSIsICJ3aWZpIiwgImxpc3QiLCAiLS1yZXNjYW4iLCAibm8ifSk7CisgICAgICAgIFFUaW1l
cjo6c2luZ2xlU2hvdCgyMDAwLCAmbV93aWZpLCBbdGhpc10geyBpZiAobV93aWZpLnN0YXRlKCkg
IT0gUVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIG1fd2lmaS5raWxsKCk7IH0pOworICAgIH0KK30KKwor
c3RhdGljIHZvaWQgcmVnaXN0ZXJDcmltc29uU3RhdHVzKCkgeworICAgIHFtbFJlZ2lzdGVyU2lu
Z2xldG9uVHlwZTxDcmltc29uU3RhdHVzPigiQ3JpbXNvblN0YXR1cyIsIDEsIDAsICJDcmltc29u
U3RhdHVzIiwKKyAgICAgICAgW10oUVFtbEVuZ2luZSosIFFKU0VuZ2luZSopIC0+IFFPYmplY3Qq
IHsgcmV0dXJuIG5ldyBDcmltc29uU3RhdHVzKCk7IH0pOworfQorUV9DT1JFQVBQX1NUQVJUVVBf
RlVOQ1RJT04ocmVnaXN0ZXJDcmltc29uU3RhdHVzKQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdo
dG9zL2NyaW1zb25zdGF0dXMuaCBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmgKbmV3
IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMmRhYzBkMQotLS0gL2Rldi9udWxsCisr
KyBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmgKQEAgLTAsMCArMSw1MiBAQAorI3By
YWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4KKyNp
bmNsdWRlIDxRVGltZXI+CisjaW5jbHVkZSA8UU5ldHdvcmtBY2Nlc3NNYW5hZ2VyPgorI2luY2x1
ZGUgPFFQb2ludGVyPgorI2luY2x1ZGUgPFFOZXR3b3JrUmVwbHk+CisjaW5jbHVkZSA8UVByb2Nl
c3M+CisKKy8vIE9wdGlvbmFsIGxhdW5jaGVyIHN0YXR1cy4gTmV2ZXIgcGFydGljaXBhdGVzIGlu
IHRoZSBzdHJlYW1pbmcvZGVjb2RlciBwYXRoLgorY2xhc3MgQ3JpbXNvblN0YXR1cyA6IHB1Ymxp
YyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgbG9j
YWwgUkVBRCBsb2NhbCBOT1RJRlkgbG9jYWxDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVZhcmlh
bnRNYXAgc3RhdHMgUkVBRCBzdGF0cyBOT1RJRlkgc3RhdHNDaGFuZ2VkKQorICAgIFFfUFJPUEVS
VFkoUVN0cmluZyBzdGF0dXMgUkVBRCBzdGF0dXMgTk9USUZZIHN0YXRzQ2hhbmdlZCkKKyAgICBR
X1BST1BFUlRZKFFTdHJpbmcgZW5kcG9pbnQgUkVBRCBlbmRwb2ludCBOT1RJRlkgY29uZmlnQ2hh
bmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgZmluZ2VycHJpbnQgUkVBRCBmaW5nZXJwcmlu
dCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgY29uZmlndXJlZCBS
RUFEIGNvbmZpZ3VyZWQgTk9USUZZIGNvbmZpZ0NoYW5nZWQpCitwdWJsaWM6CisgICAgZXhwbGlj
aXQgQ3JpbXNvblN0YXR1cyhRT2JqZWN0KiBwYXJlbnQgPSBudWxscHRyKTsKKyAgICB+Q3JpbXNv
blN0YXR1cygpIG92ZXJyaWRlOworICAgIFFWYXJpYW50TWFwIGxvY2FsKCkgY29uc3QgeyByZXR1
cm4gbV9sb2NhbDsgfQorICAgIFFWYXJpYW50TWFwIHN0YXRzKCkgY29uc3QgeyByZXR1cm4gbV9z
dGF0czsgfQorICAgIFFTdHJpbmcgc3RhdHVzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0dXM7IH0K
KyAgICBRU3RyaW5nIGVuZHBvaW50KCkgY29uc3QgeyByZXR1cm4gbV9lbmRwb2ludDsgfQorICAg
IFFTdHJpbmcgZmluZ2VycHJpbnQoKSBjb25zdCB7IHJldHVybiBtX3BpbjsgfQorICAgIGJvb2wg
Y29uZmlndXJlZCgpIGNvbnN0IHsgcmV0dXJuICFtX2VuZHBvaW50LmlzRW1wdHkoKSAmJiAhbV90
b2tlbi5pc0VtcHR5KCk7IH0KKyAgICBRX0lOVk9LQUJMRSB2b2lkIHNlbGVjdEhvc3QoUVN0cmlu
ZyBpZCwgUVN0cmluZyBzdWdnZXN0ZWRVcmwpOworICAgIFFfSU5WT0tBQkxFIGJvb2wgY29uZmln
dXJlKFFTdHJpbmcgdXJsLCBRU3RyaW5nIHRva2VuLCBRU3RyaW5nIHBpbik7CisgICAgUV9JTlZP
S0FCTEUgdm9pZCBzZXRWaXNpYmxlKGJvb2wgdmlzaWJsZSk7CisgICAgUV9JTlZPS0FCTEUgdm9p
ZCByZWZyZXNoKCk7CisgICAgc3RhdGljIFFWYXJpYW50TWFwIHBhcnNlU3RhdHMoY29uc3QgUUJ5
dGVBcnJheSYgYnl0ZXMsIFFTdHJpbmcqIGVycm9yKTsKKyAgICBzdGF0aWMgYm9vbCB2YWxpZEVu
ZHBvaW50KGNvbnN0IFFTdHJpbmcmIHVybCk7CisgICAgc3RhdGljIFFTdHJpbmcgbm9ybWFsaXpl
ZFBpbihRU3RyaW5nIHBpbik7CisgICAgc3RhdGljIFFWYXJpYW50TWFwIHJlYWRMb2NhbChjb25z
dCBRU3RyaW5nJiBzeXNSb290ID0gIi9zeXMiKTsKK3NpZ25hbHM6CisgICAgdm9pZCBsb2NhbENo
YW5nZWQoKTsKKyAgICB2b2lkIHN0YXRzQ2hhbmdlZCgpOworICAgIHZvaWQgY29uZmlnQ2hhbmdl
ZCgpOworcHJpdmF0ZToKKyAgICB2b2lkIHJlZnJlc2hMb2NhbCgpOworICAgIHZvaWQgZmFpbChR
U3RyaW5nIG1lc3NhZ2UpOworICAgIHZvaWQgY2FuY2VsKCk7CisgICAgUVN0cmluZyBjb25maWdG
aWxlKCkgY29uc3Q7CisgICAgUVN0cmluZyBtX2hvc3QsIG1fZW5kcG9pbnQsIG1fdG9rZW4sIG1f
cGluLCBtX3N0YXR1cyA9ICJDaG9vc2UgYSBob3N0IHRvIHZpZXcgaGFyZHdhcmUgc3RhdHMiOwor
ICAgIFFWYXJpYW50TWFwIG1fbG9jYWwsIG1fc3RhdHM7CisgICAgUVRpbWVyIG1fbG9jYWxUaW1l
ciwgbV9zdGF0c1RpbWVyOworICAgIFFQcm9jZXNzIG1fd2lmaTsKKyAgICBRTmV0d29ya0FjY2Vz
c01hbmFnZXIgbV9uZXR3b3JrOworICAgIFFQb2ludGVyPFFOZXR3b3JrUmVwbHk+IG1fcmVwbHk7
CisgICAgYm9vbCBtX3Zpc2libGUgPSBmYWxzZTsKK307CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxp
Z2h0b3MvZWNsaXBzZXByb2ZpbGVzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmls
ZXMuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmE2M2Q1MmQKLS0tIC9k
ZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmNwcApAQCAtMCww
ICsxLDQxIEBACisjaW5jbHVkZSAiZWNsaXBzZXByb2ZpbGVzLmgiCisjaW5jbHVkZSA8UUNyeXB0
b2dyYXBoaWNIYXNoPgorI2luY2x1ZGUgPFFDb3JlQXBwbGljYXRpb24+CisjaW5jbHVkZSA8UVFt
bEVuZ2luZT4KK1FTdHJpbmcgRWNsaXBzZVByb2ZpbGVzOjprZXkoUVN0cmluZyBob3N0LCBRU3Ry
aW5nIG5hbWUpIHsKKyAgICByZXR1cm4gImVjbGlwc2UvcHJvZmlsZXMvIiArIFFTdHJpbmc6OmZy
b21MYXRpbjEoUUNyeXB0b2dyYXBoaWNIYXNoOjpoYXNoKGhvc3QudG9VdGY4KCksIFFDcnlwdG9n
cmFwaGljSGFzaDo6U2hhMjU2KS50b0hleCgpKSArICIvIiArIFFTdHJpbmc6OmZyb21MYXRpbjEo
UUNyeXB0b2dyYXBoaWNIYXNoOjpoYXNoKG5hbWUudHJpbW1lZCgpLnRvVXRmOCgpLCBRQ3J5cHRv
Z3JhcGhpY0hhc2g6OlNoYTI1NikudG9IZXgoKSk7Cit9Citib29sIEVjbGlwc2VQcm9maWxlczo6
dmFsaWQoY29uc3QgUVZhcmlhbnRNYXAmIHZhbHVlcykgeworICAgIGNvbnN0IFFNYXA8UVN0cmlu
ZyxRUGFpcjxpbnQsaW50Pj4gcmFuZ2VzID0ge3sid2lkdGgiLHszMjAsNzY4MH19LCB7ImhlaWdo
dCIsezIwMCw0MzIwfX0sIHsiZnBzIix7MSwyNDB9fSwgeyJiaXRyYXRlS2JwcyIsezUwMCwxNTAw
MDB9fX07CisgICAgaWYgKHZhbHVlcy5zaXplKCkgIT0gcmFuZ2VzLnNpemUoKSkgcmV0dXJuIGZh
bHNlOworICAgIGZvciAoYXV0byBpID0gcmFuZ2VzLmJlZ2luKCk7IGkgIT0gcmFuZ2VzLmVuZCgp
OyArK2kpIHsKKyAgICAgICAgYm9vbCBvazsgYXV0byBuID0gdmFsdWVzLnZhbHVlKGkua2V5KCkp
LnRvSW50KCZvayk7CisgICAgICAgIGlmICghb2sgfHwgbiA8IGkudmFsdWUoKS5maXJzdCB8fCBu
ID4gaS52YWx1ZSgpLnNlY29uZCkgcmV0dXJuIGZhbHNlOworICAgIH0KKyAgICByZXR1cm4gdHJ1
ZTsKK30KK2Jvb2wgRWNsaXBzZVByb2ZpbGVzOjpzYXZlKFFTdHJpbmcgaG9zdCwgUVN0cmluZyBu
YW1lLCBRVmFyaWFudE1hcCB2YWx1ZXMpIHsKKyAgICBuYW1lID0gbmFtZS50cmltbWVkKCk7Cisg
ICAgaWYgKGhvc3Quc2l6ZSgpID4gMjU2IHx8IG5hbWUuaXNFbXB0eSgpIHx8IG5hbWUuc2l6ZSgp
ID4gNDggfHwgIXZhbGlkKHZhbHVlcykpIHJldHVybiBmYWxzZTsKKyAgICBpZiAoIW5hbWVzKGhv
c3QpLmNvbnRhaW5zKG5hbWUpICYmIG5hbWVzKGhvc3QpLnNpemUoKSA+PSAzMikgcmV0dXJuIGZh
bHNlOworICAgIFFTZXR0aW5ncyBzZXR0aW5nczsgc2V0dGluZ3Muc2V0VmFsdWUoa2V5KGhvc3Qs
bmFtZSkrIi9uYW1lIixuYW1lKTsgc2V0dGluZ3Muc2V0VmFsdWUoa2V5KGhvc3QsbmFtZSkrIi92
YWx1ZXMiLHZhbHVlcyk7IHNldHRpbmdzLnN5bmMoKTsKKyAgICByZXR1cm4gc2V0dGluZ3Muc3Rh
dHVzKCkgPT0gUVNldHRpbmdzOjpOb0Vycm9yOworfQorUVZhcmlhbnRNYXAgRWNsaXBzZVByb2Zp
bGVzOjpsb2FkKFFTdHJpbmcgaG9zdCwgUVN0cmluZyBuYW1lKSB7CisgICAgUVNldHRpbmdzIHNl
dHRpbmdzOyBhdXRvIHZhbHVlID0gc2V0dGluZ3MudmFsdWUoa2V5KGhvc3QsbmFtZSkrIi92YWx1
ZXMiKS50b01hcCgpOworICAgIHJldHVybiB2YWxpZCh2YWx1ZSkgPyB2YWx1ZSA6IFFWYXJpYW50
TWFwKCk7Cit9Citib29sIEVjbGlwc2VQcm9maWxlczo6cmVtb3ZlKFFTdHJpbmcgaG9zdCwgUVN0
cmluZyBuYW1lLCBib29sIGNvbmZpcm1lZCkgeworICAgIGlmICghY29uZmlybWVkKSByZXR1cm4g
ZmFsc2U7CisgICAgUVNldHRpbmdzIHNldHRpbmdzOyBzZXR0aW5ncy5yZW1vdmUoa2V5KGhvc3Qs
bmFtZSkpOyBzZXR0aW5ncy5zeW5jKCk7IHJldHVybiBzZXR0aW5ncy5zdGF0dXMoKSA9PSBRU2V0
dGluZ3M6Ok5vRXJyb3I7Cit9CitRU3RyaW5nTGlzdCBFY2xpcHNlUHJvZmlsZXM6Om5hbWVzKFFT
dHJpbmcgaG9zdCkgeworICAgIFFTZXR0aW5ncyBzZXR0aW5nczsgc2V0dGluZ3MuYmVnaW5Hcm91
cChrZXkoaG9zdCwgIiIpLnNlY3Rpb24oJy8nLDAsLTIpKTsKKyAgICBRU3RyaW5nTGlzdCByZXN1
bHQ7CisgICAgZm9yIChjb25zdCBhdXRvJiBjaGlsZCA6IHNldHRpbmdzLmNoaWxkR3JvdXBzKCkp
IHsgYXV0byBuYW1lID0gc2V0dGluZ3MudmFsdWUoY2hpbGQrIi9uYW1lIikudG9TdHJpbmcoKTsg
aWYgKCFuYW1lLmlzRW1wdHkoKSkgcmVzdWx0LmFwcGVuZChuYW1lKTsgfQorICAgIHJlc3VsdC5z
b3J0KCk7IHJldHVybiByZXN1bHQ7Cit9CitzdGF0aWMgdm9pZCByZWdpc3RlckVjbGlwc2VQcm9m
aWxlcygpIHsKKyAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGU8RWNsaXBzZVByb2ZpbGVzPigi
RWNsaXBzZVByb2ZpbGVzIiwxLDAsIkVjbGlwc2VQcm9maWxlcyIsW10oUVFtbEVuZ2luZSosUUpT
RW5naW5lKikgLT4gUU9iamVjdCogeyByZXR1cm4gbmV3IEVjbGlwc2VQcm9maWxlcygpOyB9KTsK
K30KK1FfQ09SRUFQUF9TVEFSVFVQX0ZVTkNUSU9OKHJlZ2lzdGVyRWNsaXBzZVByb2ZpbGVzKQpk
aWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5oIGIvYXBwL21vb25s
aWdodG9zL2VjbGlwc2Vwcm9maWxlcy5oCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAw
MDAuLmQzOTgzODcKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXBy
b2ZpbGVzLmgKQEAgLTAsMCArMSwyNyBAQAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVj
dD4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRU2V0dGluZ3M+CitjbGFzcyBF
Y2xpcHNlUHJvZmlsZXMgOiBwdWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpFQ1QKKyAgICBRX1BS
T1BFUlRZKGludCB0ZXh0U2NhbGUgUkVBRCB0ZXh0U2NhbGUgV1JJVEUgc2V0VGV4dFNjYWxlIE5P
VElGWSBhcHBlYXJhbmNlQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgcmVkdWNlZE1vdGlv
biBSRUFEIHJlZHVjZWRNb3Rpb24gV1JJVEUgc2V0UmVkdWNlZE1vdGlvbiBOT1RJRlkgYXBwZWFy
YW5jZUNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShib29sIGhpZ2hDb250cmFzdCBSRUFEIGhpZ2hD
b250cmFzdCBXUklURSBzZXRIaWdoQ29udHJhc3QgTk9USUZZIGFwcGVhcmFuY2VDaGFuZ2VkKQor
cHVibGljOgorICAgIGV4cGxpY2l0IEVjbGlwc2VQcm9maWxlcyhRT2JqZWN0KiBwYXJlbnQgPSBu
dWxscHRyKSA6IFFPYmplY3QocGFyZW50KSB7fQorICAgIGludCB0ZXh0U2NhbGUoKSBjb25zdCB7
IHJldHVybiBxQm91bmQoMTAwLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL3RleHRTY2FsZSIs
MTAwKS50b0ludCgpLDEyNSk7IH0KKyAgICBib29sIHJlZHVjZWRNb3Rpb24oKSBjb25zdCB7IHJl
dHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9yZWR1Y2VkTW90aW9uIixmYWxzZSkudG9C
b29sKCk7IH0KKyAgICBib29sIGhpZ2hDb250cmFzdCgpIGNvbnN0IHsgcmV0dXJuIFFTZXR0aW5n
cygpLnZhbHVlKCJlY2xpcHNlL2hpZ2hDb250cmFzdCIsZmFsc2UpLnRvQm9vbCgpOyB9CisgICAg
dm9pZCBzZXRUZXh0U2NhbGUoaW50IHZhbHVlKSB7IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xp
cHNlL3RleHRTY2FsZSIscUJvdW5kKDEwMCx2YWx1ZSwxMjUpKTsgZW1pdCBhcHBlYXJhbmNlQ2hh
bmdlZCgpOyB9CisgICAgdm9pZCBzZXRSZWR1Y2VkTW90aW9uKGJvb2wgdmFsdWUpIHsgUVNldHRp
bmdzKCkuc2V0VmFsdWUoImVjbGlwc2UvcmVkdWNlZE1vdGlvbiIsdmFsdWUpOyBlbWl0IGFwcGVh
cmFuY2VDaGFuZ2VkKCk7IH0KKyAgICB2b2lkIHNldEhpZ2hDb250cmFzdChib29sIHZhbHVlKSB7
IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlL2hpZ2hDb250cmFzdCIsdmFsdWUpOyBlbWl0
IGFwcGVhcmFuY2VDaGFuZ2VkKCk7IH0KKyAgICBRX0lOVk9LQUJMRSBib29sIHNhdmUoUVN0cmlu
ZyBob3N0LCBRU3RyaW5nIG5hbWUsIFFWYXJpYW50TWFwIHZhbHVlcyk7CisgICAgUV9JTlZPS0FC
TEUgUVZhcmlhbnRNYXAgbG9hZChRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSk7CisgICAgUV9J
TlZPS0FCTEUgYm9vbCByZW1vdmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUsIGJvb2wgY29u
ZmlybWVkKTsKKyAgICBRX0lOVk9LQUJMRSBRU3RyaW5nTGlzdCBuYW1lcyhRU3RyaW5nIGhvc3Qp
OworICAgIHN0YXRpYyBib29sIHZhbGlkKGNvbnN0IFFWYXJpYW50TWFwJiB2YWx1ZXMpOworc2ln
bmFsczoKKyAgICB2b2lkIGFwcGVhcmFuY2VDaGFuZ2VkKCk7Citwcml2YXRlOgorICAgIHN0YXRp
YyBRU3RyaW5nIGtleShRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSk7Cit9OwpkaWZmIC0tZ2l0
IGEvYXBwL21vb25saWdodG9zL21hbmFnZWR1cGRhdGVzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9t
YW5hZ2VkdXBkYXRlcy5jcHAKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMmJm
Y2JmZAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9tYW5hZ2VkdXBkYXRlcy5j
cHAKQEAgLTAsMCArMSwxMzIgQEAKKy8vIEVjbGlwc2VPUyBvd25zIHRoaXMgY3VzdG9taXplZCBu
YXRpdmUgY2xpZW50LiBObyBmZWVkIHJlcXVlc3RzLCBhc3NldAorLy8gZG93bmxvYWRzLCBzd2Fw
cyBvciByZWxhdW5jaGVzIGFyZSBjb21waWxlZCBpbnRvIHRoaXMgdXBkYXRlIGltcGxlbWVudGF0
aW9uLgorI2luY2x1ZGUgIi4uL2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaCIKKyNpbmNsdWRl
IDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUgPFFKc29uT2JqZWN0PgorCitzdGF0aWMgUVN0
cmluZyBzdHJpcEJ1aWxkTWV0YWRhdGEoY29uc3QgUVN0cmluZyYgdmVyc2lvbikKK3sKKyAgICBp
bnQgcGx1c0lkeCA9IHZlcnNpb24uaW5kZXhPZignKycpOworICAgIHJldHVybiBwbHVzSWR4ID49
IDAgPyB2ZXJzaW9uLmxlZnQocGx1c0lkeCkgOiB2ZXJzaW9uOworfQorCitzdGF0aWMgYm9vbCBp
c051bWVyaWNJZGVudGlmaWVyKGNvbnN0IFFTdHJpbmcmIHMpCit7CisgICAgaWYgKHMuaXNFbXB0
eSgpKSB7CisgICAgICAgIHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgZm9yIChjb25zdCBRQ2hh
ciYgYyA6IHMpIHsKKyAgICAgICAgaWYgKCFjLmlzRGlnaXQoKSkgeworICAgICAgICAgICAgcmV0
dXJuIGZhbHNlOworICAgICAgICB9CisgICAgfQorICAgIHJldHVybiB0cnVlOworfQorCitpbnQg
QXV0b1VwZGF0ZUNoZWNrZXI6OmNvbXBhcmVTZW1hbnRpY1ZlcnNpb25zKGNvbnN0IFFTdHJpbmcm
IHYxLCBjb25zdCBRU3RyaW5nJiB2MikKK3sKKyAgICBRU3RyaW5nIHMxID0gc3RyaXBCdWlsZE1l
dGFkYXRhKHYxKTsKKyAgICBRU3RyaW5nIHMyID0gc3RyaXBCdWlsZE1ldGFkYXRhKHYyKTsKKwor
ICAgIGludCBkYXNoMSA9IHMxLmluZGV4T2YoJy0nKTsKKyAgICBpbnQgZGFzaDIgPSBzMi5pbmRl
eE9mKCctJyk7CisgICAgUVN0cmluZyBiYXNlMSA9IGRhc2gxID49IDAgPyBzMS5sZWZ0KGRhc2gx
KSA6IHMxOworICAgIFFTdHJpbmcgYmFzZTIgPSBkYXNoMiA+PSAwID8gczIubGVmdChkYXNoMikg
OiBzMjsKKyAgICBRU3RyaW5nIHByZTEgPSBkYXNoMSA+PSAwID8gczEubWlkKGRhc2gxICsgMSkg
OiBRU3RyaW5nKCk7CisgICAgUVN0cmluZyBwcmUyID0gZGFzaDIgPj0gMCA/IHMyLm1pZChkYXNo
MiArIDEpIDogUVN0cmluZygpOworCisgICAgLy8gTnVtZXJpYyBiYXNlIHZlcnNpb25zIGNvbXBh
cmUgZmlyc3QgKDAuNC4wLWJldGEuMDAxID4gMC4zLjApCisgICAgY29uc3QgUVN0cmluZ0xpc3Qg
YmFzZVBhcnRzMSA9IGJhc2UxLnNwbGl0KCcuJyk7CisgICAgY29uc3QgUVN0cmluZ0xpc3QgYmFz
ZVBhcnRzMiA9IGJhc2UyLnNwbGl0KCcuJyk7CisgICAgZm9yIChpbnQgaSA9IDA7IGkgPCBxTWF4
KGJhc2VQYXJ0czEuY291bnQoKSwgYmFzZVBhcnRzMi5jb3VudCgpKTsgaSsrKSB7CisgICAgICAg
IHFsb25nbG9uZyBiMSA9IGkgPCBiYXNlUGFydHMxLmNvdW50KCkgPyBiYXNlUGFydHMxW2ldLnRv
TG9uZ0xvbmcoKSA6IDA7CisgICAgICAgIHFsb25nbG9uZyBiMiA9IGkgPCBiYXNlUGFydHMyLmNv
dW50KCkgPyBiYXNlUGFydHMyW2ldLnRvTG9uZ0xvbmcoKSA6IDA7CisgICAgICAgIGlmIChiMSAh
PSBiMikgeworICAgICAgICAgICAgcmV0dXJuIGIxIDwgYjIgPyAtMSA6IDE7CisgICAgICAgIH0K
KyAgICB9CisKKyAgICAvLyBFcXVhbCBiYXNlOiBhIHJlbGVhc2Ugd2l0aCBubyBwcmVyZWxlYXNl
IHN1ZmZpeCBvdXRyYW5rcyBhbnkgcHJlcmVsZWFzZQorICAgIGlmIChwcmUxLmlzRW1wdHkoKSAh
PSBwcmUyLmlzRW1wdHkoKSkgeworICAgICAgICByZXR1cm4gcHJlMS5pc0VtcHR5KCkgPyAxIDog
LTE7CisgICAgfQorICAgIGlmIChwcmUxLmlzRW1wdHkoKSkgeworICAgICAgICByZXR1cm4gMDsK
KyAgICB9CisKKyAgICAvLyBUd28gcHJlcmVsZWFzZXM6IGNvbXBhcmUgZG90LXNlcGFyYXRlZCBp
ZGVudGlmaWVycyBsZWZ0IHRvIHJpZ2h0LgorICAgIC8vIE51bWVyaWMgaWRlbnRpZmllcnMgY29t
cGFyZSBudW1lcmljYWxseSAobGVhZGluZyB6ZXJvcyB0b2xlcmF0ZWQg4oCUIG91cgorICAgIC8v
IENJIHplcm8tcGFkcyBjb3VudGVycyksIGFscGhhbnVtZXJpYyBvbmVzIGxleGljYWxseSBpbiBB
U0NJSSBvcmRlciwgYW5kCisgICAgLy8gbnVtZXJpYyBhbHdheXMgcmFua3MgYmVsb3cgYWxwaGFu
dW1lcmljLiBUaGlzIGlzIHdoYXQgb3JkZXJzCisgICAgLy8gImFscGhhIiA8ICJiZXRhIiA8ICJy
YyIgYXQgYW4gZXF1YWwgYmFzZSDigJQgdGhlIHByb3BlcnR5IHRoZSBwcmV2aW91cworICAgIC8v
IGltcGxlbWVudGF0aW9uIGxhY2tlZCAoaXQgc2tpcHBlZCB0aGUgd29yZHMgYW5kIGNvbXBhcmVk
IG9ubHkgbnVtYmVycywKKyAgICAvLyBzbyAwLjMuMC1iZXRhLjAwOCB3cm9uZ2x5IG91dHJhbmtl
ZCAwLjMuMC1yYy4wMDIpLgorICAgIGNvbnN0IFFTdHJpbmdMaXN0IGlkczEgPSBwcmUxLnNwbGl0
KCcuJyk7CisgICAgY29uc3QgUVN0cmluZ0xpc3QgaWRzMiA9IHByZTIuc3BsaXQoJy4nKTsKKyAg
ICBmb3IgKGludCBpID0gMDsgaSA8IHFNYXgoaWRzMS5jb3VudCgpLCBpZHMyLmNvdW50KCkpOyBp
KyspIHsKKyAgICAgICAgaWYgKGkgPj0gaWRzMS5jb3VudCgpKSB7CisgICAgICAgICAgICAvLyBF
cXVhbCBwcmVmaXgsIGZld2VyIGZpZWxkcyA9IGxvd2VyIHByZWNlZGVuY2UgKMKnMTEuNC40KQor
ICAgICAgICAgICAgcmV0dXJuIC0xOworICAgICAgICB9CisgICAgICAgIGlmIChpID49IGlkczIu
Y291bnQoKSkgeworICAgICAgICAgICAgcmV0dXJuIDE7CisgICAgICAgIH0KKyAgICAgICAgYm9v
bCBudW0xID0gaXNOdW1lcmljSWRlbnRpZmllcihpZHMxW2ldKTsKKyAgICAgICAgYm9vbCBudW0y
ID0gaXNOdW1lcmljSWRlbnRpZmllcihpZHMyW2ldKTsKKyAgICAgICAgaWYgKG51bTEgJiYgbnVt
MikgeworICAgICAgICAgICAgcWxvbmdsb25nIHAxID0gaWRzMVtpXS50b0xvbmdMb25nKCk7Cisg
ICAgICAgICAgICBxbG9uZ2xvbmcgcDIgPSBpZHMyW2ldLnRvTG9uZ0xvbmcoKTsKKyAgICAgICAg
ICAgIGlmIChwMSAhPSBwMikgeworICAgICAgICAgICAgICAgIHJldHVybiBwMSA8IHAyID8gLTEg
OiAxOworICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgICAgIGVsc2UgaWYgKG51bTEgIT0g
bnVtMikgeworICAgICAgICAgICAgLy8gTnVtZXJpYyBpZGVudGlmaWVycyByYW5rIGJlbG93IGFs
cGhhbnVtZXJpYyBvbmVzICjCpzExLjQuMykKKyAgICAgICAgICAgIHJldHVybiBudW0xID8gLTEg
OiAxOworICAgICAgICB9CisgICAgICAgIGVsc2UgeworICAgICAgICAgICAgaW50IGNtcCA9IFFT
dHJpbmc6OmNvbXBhcmUoaWRzMVtpXSwgaWRzMltpXSk7CisgICAgICAgICAgICBpZiAoY21wICE9
IDApIHsKKyAgICAgICAgICAgICAgICByZXR1cm4gY21wIDwgMCA/IC0xIDogMTsKKyAgICAgICAg
ICAgIH0KKyAgICAgICAgfQorICAgIH0KKyAgICByZXR1cm4gMDsKK30KKworQXV0b1VwZGF0ZUNo
ZWNrZXI6OkF1dG9VcGRhdGVDaGVja2VyKFFPYmplY3QqIHBhcmVudCkgOgorICAgIFFPYmplY3Qo
cGFyZW50KSwgbV9DaGVja0luRmxpZ2h0KGZhbHNlKSwgbV9DaGVja0lzTWFudWFsKGZhbHNlKSwK
KyAgICBtX1VwZGF0ZUF2YWlsYWJsZShmYWxzZSksIG1fT2ZmZXJBdmFpbGFibGUoZmFsc2UpLCBt
X0luc3RhbGxpbmcoZmFsc2UpCit7CisgICAgY2xlYXJPZmZlcigpOworICAgIHNldFN0YXR1cyh0
cigiJTEuIFVwZGF0ZXMgYXJlIG1hbmFnZWQgYnkgRWNsaXBzZU9TLiBHZXQgdGhlIG1hdGNoaW5n
IE9TIGltYWdlIGZyb20gJTI7IHVwc3RyZWFtIFZpYmVtaXMgdXBkYXRlcyBhcmUgZGlzYWJsZWQu
IikuYXJnKGN1cnJlbnRWZXJzaW9uKCksIG1fUmVsZWFzZVVybCkpOworfQorUVN0cmluZyBBdXRv
VXBkYXRlQ2hlY2tlcjo6Y3VycmVudFZlcnNpb24oKSBjb25zdAoreworICAgIHJldHVybiB0cigi
RWNsaXBzZSAlMSDCtyBFY2xpcHNlT1MgY3VzdG9taXplZCIpLmFyZyhRQ29yZUFwcGxpY2F0aW9u
OjphcHBsaWNhdGlvblZlcnNpb24oKSk7Cit9Cit2b2lkIEF1dG9VcGRhdGVDaGVja2VyOjpjbGVh
ck9mZmVyKCkKK3sKKyAgICBtX1VwZGF0ZUF2YWlsYWJsZSA9IGZhbHNlOyBtX09mZmVyQXZhaWxh
YmxlID0gZmFsc2U7CisgICAgbV9PZmZlclZlcnNpb24uY2xlYXIoKTsgbV9Bc3NldFVybC5jbGVh
cigpOyBtX09mZmVyVGllciA9IC0xOworICAgIG1fUmVsZWFzZVVybCA9IFFTdHJpbmdMaXRlcmFs
KCJodHRwczovL2dpdGh1Yi5jb20vdGgzZDNjazNyL01vb25saWdodC1PUy9yZWxlYXNlcyIpOwor
fQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6c2V0U3RhdHVzKGNvbnN0IFFTdHJpbmcmIG1lc3Nh
Z2UpCit7CisgICAgaWYgKG1fU3RhdHVzTWVzc2FnZSAhPSBtZXNzYWdlKSB7IG1fU3RhdHVzTWVz
c2FnZSA9IG1lc3NhZ2U7IGVtaXQgc3RhdGVDaGFuZ2VkKCk7IH0KK30KK3ZvaWQgQXV0b1VwZGF0
ZUNoZWNrZXI6OnN0YXJ0KCkgeyAvKiBObyB0aW1lciBhbmQgbm8gYmFja2dyb3VuZCB1cGRhdGUg
cmVxdWVzdHMuICovIH0KK2Jvb2wgQXV0b1VwZGF0ZUNoZWNrZXI6OmNhbkluc3RhbGxVcGRhdGVz
KCkgY29uc3QgeyByZXR1cm4gZmFsc2U7IH0KK2Jvb2wgQXV0b1VwZGF0ZUNoZWNrZXI6OmNhbklu
c3RhbGwoKSBjb25zdCB7IHJldHVybiBmYWxzZTsgfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6
Y2hhbm5lbENoYW5nZWQoKSB7IGNoZWNrTm93KCk7IH0KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6
OmNoZWNrTm93KCkKK3sKKyAgICBjbGVhck9mZmVyKCk7CisgICAgc2V0U3RhdHVzKHRyKCJVcGRh
dGVzIGFyZSBtYW5hZ2VkIGJ5IEVjbGlwc2VPUy4gRG93bmxvYWQgdGhlIG1hdGNoaW5nIE9TIGlt
YWdlIGZyb20gJTEuIFRoaXMgY2xpZW50IG5ldmVyIGluc3RhbGxzIHVwc3RyZWFtIFZpYmVtaXMg
cmVsZWFzZXMuIikuYXJnKG1fUmVsZWFzZVVybCkpOworICAgIGVtaXQgc3RhdGVDaGFuZ2VkKCk7
IGVtaXQgY2hlY2tDb21wbGV0ZWQodHJ1ZSwgZmFsc2UpOworfQordm9pZCBBdXRvVXBkYXRlQ2hl
Y2tlcjo6aW5zdGFsbCgpCit7CisgICAgY2hlY2tOb3coKTsKKyAgICBlbWl0IGluc3RhbGxGYWls
ZWQodHIoIlN0YW5kYWxvbmUgVmliZW1pcyBpbnN0YWxsYXRpb24gaXMgZGlzYWJsZWQgaW4gRWNs
aXBzZU9TLiIpLCBtX1JlbGVhc2VVcmwpOworfQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9z
L3N5c3RlbWNvbnRyb2xzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAK
bmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uNzdlYzRjOAotLS0gL2Rldi9udWxs
CisrKyBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAKQEAgLTAsMCArMSw4MyBA
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
KyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGlmICh2YWx1ZS52YWx1ZSgiZG9uZSIpLnRvQm9v
bCgpKSB7CisgICAgICAgICAgICAgICAgbV90aW1lb3V0LnN0b3AoKTsgbV9idXN5ID0gZmFsc2U7
IG1fcHJvbXB0LmNsZWFyKCk7CisgICAgICAgICAgICAgICAgaWYgKHZhbHVlLmNvbnRhaW5zKCJp
dGVtcyIpKSB7CisgICAgICAgICAgICAgICAgICAgIGF1dG8gZW50cmllcyA9IHZhbHVlLnZhbHVl
KCJpdGVtcyIpLnRvQXJyYXkoKTsKKyAgICAgICAgICAgICAgICAgICAgaWYgKGVudHJpZXMuc2l6
ZSgpID4gNjQpIHsgZmFpbCh0cigiSW52YWxpZCBkZXZpY2UgbGlzdC4iKSk7IHJldHVybjsgfQor
ICAgICAgICAgICAgICAgICAgICBtX2l0ZW1zID0gZW50cmllcy50b1ZhcmlhbnRMaXN0KCk7Cisg
ICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIGlmICh2YWx1ZS52YWx1ZSgic3RhdGUi
KS5pc09iamVjdCgpKSBtX3N0YXRlID0gdmFsdWUudmFsdWUoInN0YXRlIikudG9PYmplY3QoKS50
b1ZhcmlhbnRNYXAoKTsKKyAgICAgICAgICAgICAgICBtX3N0YXR1cyA9IHZhbHVlLmNvbnRhaW5z
KCJlcnJvciIpID8gdmFsdWUudmFsdWUoImVycm9yIikudG9TdHJpbmcoKS5sZWZ0KDEwMjQpIDog
dmFsdWUudmFsdWUoInN0YXR1cyIpLnRvU3RyaW5nKCk7CisgICAgICAgICAgICB9CisgICAgICAg
ICAgICBlbWl0IGNoYW5nZWQoKTsKKyAgICAgICAgfQorICAgIH0pOworICAgIGNvbm5lY3QoJm1f
cHJvY2VzcywgJlFQcm9jZXNzOjplcnJvck9jY3VycmVkLCB0aGlzLCBbdGhpc10oUVByb2Nlc3M6
OlByb2Nlc3NFcnJvcikgeworICAgICAgICBpZiAoIW1fbW9kZS5pc0VtcHR5KCkpIGZhaWwodHIo
IlN5c3RlbSBjb250cm9scyBhcmUgdW5hdmFpbGFibGUuIFVzZSB0aGUgZGlhZ25vc3RpYyBzaGVs
bC4iKSk7CisgICAgfSk7CisgICAgY29ubmVjdCgmbV9wcm9jZXNzLCBRT3ZlcmxvYWQ8aW50LFFQ
cm9jZXNzOjpFeGl0U3RhdHVzPjo6b2YoJlFQcm9jZXNzOjpmaW5pc2hlZCksIHRoaXMsIFt0aGlz
XShpbnQsIFFQcm9jZXNzOjpFeGl0U3RhdHVzKSB7CisgICAgICAgIGlmICghbV9tb2RlLmlzRW1w
dHkoKSkgeyBtX3RpbWVvdXQuc3RvcCgpOyBtX2J1c3kgPSBmYWxzZTsgbV9wcm9tcHQuY2xlYXIo
KTsgbV9zdGF0dXMgPSB0cigiU3lzdGVtIGhlbHBlciBzdG9wcGVkLiBDbG9zZSBhbmQgcmVvcGVu
IHRoaXMgcGFuZWwuIik7IGVtaXQgY2hhbmdlZCgpOyB9CisgICAgfSk7Cit9CitTeXN0ZW1Db250
cm9sczo6flN5c3RlbUNvbnRyb2xzKCkgeyBjbG9zZSgpOyBpZiAoIW1fcHJvY2Vzcy53YWl0Rm9y
RmluaXNoZWQoNTAwKSkgeyBtX3Byb2Nlc3Mua2lsbCgpOyBtX3Byb2Nlc3Mud2FpdEZvckZpbmlz
aGVkKDUwMCk7IH0gfQordm9pZCBTeXN0ZW1Db250cm9sczo6c2VuZChjb25zdCBRSnNvbk9iamVj
dCYgdmFsdWUpIHsgbV9wcm9jZXNzLndyaXRlKFFKc29uRG9jdW1lbnQodmFsdWUpLnRvSnNvbihR
SnNvbkRvY3VtZW50OjpDb21wYWN0KSArICdcbicpOyB9Cit2b2lkIFN5c3RlbUNvbnRyb2xzOjpv
cGVuKFFTdHJpbmcgbW9kZSkgeworICAgIGlmIChtb2RlICE9ICJ3aWZpIiAmJiBtb2RlICE9ICJi
dCIgJiYgbW9kZSAhPSAiY2VudGVyIikgcmV0dXJuOworICAgIGNsb3NlKCk7CisgICAgaWYgKG1f
cHJvY2Vzcy5zdGF0ZSgpICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSB7IG1fcHJvY2Vzcy5raWxs
KCk7IG1fcHJvY2Vzcy53YWl0Rm9yRmluaXNoZWQoNTAwKTsgfQorICAgIG1fbW9kZSA9IG1vZGU7
IG1faXRlbXMuY2xlYXIoKTsgbV9zdGF0ZS5jbGVhcigpOyBtX2J1ZmZlci5jbGVhcigpOyBtX3N0
YXR1cyA9IHRyKCJMb2FkaW5n4oCmIik7IGVtaXQgY2hhbmdlZCgpOworICAgIFFTdHJpbmcgaGVs
cGVyID0gIi91c3IvbG9jYWwvbGliZXhlYy9tb29ubGlnaHQtb3Mvc3lzdGVtLWNvbnRyb2xzLnB5
IjsKKyNpZmRlZiBNT09OTElHSFRfQ09OVFJPTFNfVEVTVAorICAgIGhlbHBlciA9IHFFbnZpcm9u
bWVudFZhcmlhYmxlKCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIsIGhlbHBlcik7CisjZW5k
aWYKKyAgICBtX3Byb2Nlc3Muc3RhcnQoInB5dGhvbjMiLCB7aGVscGVyfSk7Cit9Cit2b2lkIFN5
c3RlbUNvbnRyb2xzOjpyZXF1ZXN0KFFTdHJpbmcgYWN0aW9uLCBRU3RyaW5nIGlkLCBib29sIGNv
bmZpcm0pIHsKKyAgICBpZiAobV9idXN5IHx8IG1fcHJvY2Vzcy5zdGF0ZSgpICE9IFFQcm9jZXNz
OjpSdW5uaW5nIHx8ICFhY3Rpb24uc3RhcnRzV2l0aChtX21vZGUgKyAiLSIpKSByZXR1cm47Cisg
ICAgY29uc3QgUVN0cmluZ0xpc3QgYWxsb3dlZCA9IHsid2lmaS1saXN0IiwgIndpZmktc2NhbiIs
ICJ3aWZpLWNvbm5lY3QiLCAid2lmaS1kaXNjb25uZWN0IiwgImJ0LWxpc3QiLCAiYnQtc2NhbiIs
ICJidC1jb25uZWN0IiwgImJ0LWRpc2Nvbm5lY3QiLCAiYnQtZm9yZ2V0IiwgImNlbnRlci1saXN0
IiwgImNlbnRlci12b2x1bWUiLCAiY2VudGVyLW11dGUiLCAiY2VudGVyLW91dHB1dCIsICJjZW50
ZXItc2NyZWVuIiwgImNlbnRlci1rZXlib2FyZCIsICJjZW50ZXItcmVib290IiwgImNlbnRlci1w
b3dlcm9mZiIsICJjZW50ZXItc3VzcGVuZCIsICJjZW50ZXItcmVwb3J0In07CisgICAgaWYgKCFh
bGxvd2VkLmNvbnRhaW5zKGFjdGlvbikpIHJldHVybjsKKyAgICBtX2J1c3kgPSB0cnVlOyBtX3By
b21wdC5jbGVhcigpOyBtX3N0YXR1cyA9IHRyKCJXb3JraW5n4oCmIik7IG1fdGltZW91dC5zdGFy
dCgxMjAwMDApOworICAgIHNlbmQoe3siYWN0aW9uIiwgYWN0aW9ufSwgeyJpZCIsIGlkfSwgeyJj
b25maXJtIiwgY29uZmlybX19KTsgZW1pdCBjaGFuZ2VkKCk7Cit9Cit2b2lkIFN5c3RlbUNvbnRy
b2xzOjphbnN3ZXIoUVN0cmluZyB2YWx1ZSkgeworICAgIGlmICghbV9idXN5IHx8IG1fcHJvbXB0
LmlzRW1wdHkoKSB8fCB2YWx1ZS5zaXplKCkgPiA0MDk2IHx8IHZhbHVlLmNvbnRhaW5zKCdcbicp
IHx8IHZhbHVlLmNvbnRhaW5zKCdccicpIHx8IHZhbHVlLmNvbnRhaW5zKFFDaGFyKDApKSkgcmV0
dXJuOworICAgIHNlbmQoe3siYWN0aW9uIiwgImFuc3dlciJ9LCB7InZhbHVlIiwgdmFsdWV9fSk7
IG1fcHJvbXB0LmNsZWFyKCk7IG1fdGltZW91dC5zdGFydCgxMjAwMDApOyBlbWl0IGNoYW5nZWQo
KTsKK30KK3ZvaWQgU3lzdGVtQ29udHJvbHM6OmNsb3NlKCkgeworICAgIG1fbW9kZS5jbGVhcigp
OyBtX3RpbWVvdXQuc3RvcCgpOyBtX2J1c3kgPSBmYWxzZTsgbV9wcm9tcHQuY2xlYXIoKTsgbV9i
dWZmZXIuY2xlYXIoKTsKKyAgICBpZiAobV9wcm9jZXNzLnN0YXRlKCkgIT0gUVByb2Nlc3M6Ok5v
dFJ1bm5pbmcpIHsKKyAgICAgICAgbV9wcm9jZXNzLnRlcm1pbmF0ZSgpOworICAgICAgICBRVGlt
ZXI6OnNpbmdsZVNob3QoNDAwMCwgdGhpcywgW3RoaXNdIHsgaWYgKG1fbW9kZS5pc0VtcHR5KCkg
JiYgbV9wcm9jZXNzLnN0YXRlKCkgIT0gUVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIG1fcHJvY2Vzcy5r
aWxsKCk7IH0pOworICAgIH0KKyAgICBlbWl0IGNoYW5nZWQoKTsKK30KK3ZvaWQgU3lzdGVtQ29u
dHJvbHM6OmZhaWwoUVN0cmluZyBtZXNzYWdlKSB7IGNsb3NlKCk7IG1fc3RhdHVzID0gbWVzc2Fn
ZTsgZW1pdCBjaGFuZ2VkKCk7IH0KK3N0YXRpYyB2b2lkIHJlZ2lzdGVyU3lzdGVtQ29udHJvbHMo
KSB7CisgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlPFN5c3RlbUNvbnRyb2xzPigiU3lzdGVt
Q29udHJvbHMiLCAxLCAwLCAiU3lzdGVtQ29udHJvbHMiLCBbXShRUW1sRW5naW5lKiwgUUpTRW5n
aW5lKikgLT4gUU9iamVjdCogeyByZXR1cm4gbmV3IFN5c3RlbUNvbnRyb2xzKCk7IH0pOworfQor
UV9DT1JFQVBQX1NUQVJUVVBfRlVOQ1RJT04ocmVnaXN0ZXJTeXN0ZW1Db250cm9scykKZGlmZiAt
LWdpdCBhL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5oIGIvYXBwL21vb25saWdodG9z
L3N5c3RlbWNvbnRyb2xzLmgKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMThl
OWRlYgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5o
CkBAIC0wLDAgKzEsMzkgQEAKKyNwcmFnbWEgb25jZQorI2luY2x1ZGUgPFFPYmplY3Q+CisjaW5j
bHVkZSA8UUpzb25PYmplY3Q+CisjaW5jbHVkZSA8UVByb2Nlc3M+CisjaW5jbHVkZSA8UVRpbWVy
PgorI2luY2x1ZGUgPFFWYXJpYW50TGlzdD4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4KK2NsYXNz
IFN5c3RlbUNvbnRyb2xzIDogcHVibGljIFFPYmplY3QgeworICAgIFFfT0JKRUNUCisgICAgUV9Q
Uk9QRVJUWShRVmFyaWFudE1hcCBzdGF0ZSBSRUFEIHN0YXRlIE5PVElGWSBjaGFuZ2VkKQorICAg
IFFfUFJPUEVSVFkoUVZhcmlhbnRMaXN0IGl0ZW1zIFJFQUQgaXRlbXMgTk9USUZZIGNoYW5nZWQp
CisgICAgUV9QUk9QRVJUWShRU3RyaW5nIHN0YXR1cyBSRUFEIHN0YXR1cyBOT1RJRlkgY2hhbmdl
ZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgcHJvbXB0IFJFQUQgcHJvbXB0IE5PVElGWSBjaGFu
Z2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBidXN5IFJFQUQgYnVzeSBOT1RJRlkgY2hhbmdlZCkK
K3B1YmxpYzoKKyAgICBleHBsaWNpdCBTeXN0ZW1Db250cm9scyhRT2JqZWN0KiBwYXJlbnQgPSBu
dWxscHRyKTsKKyAgICB+U3lzdGVtQ29udHJvbHMoKTsKKyAgICBRVmFyaWFudE1hcCBzdGF0ZSgp
IGNvbnN0IHsgcmV0dXJuIG1fc3RhdGU7IH0KKyAgICBRVmFyaWFudExpc3QgaXRlbXMoKSBjb25z
dCB7IHJldHVybiBtX2l0ZW1zOyB9CisgICAgUVN0cmluZyBzdGF0dXMoKSBjb25zdCB7IHJldHVy
biBtX3N0YXR1czsgfQorICAgIFFTdHJpbmcgcHJvbXB0KCkgY29uc3QgeyByZXR1cm4gbV9wcm9t
cHQ7IH0KKyAgICBib29sIGJ1c3koKSBjb25zdCB7IHJldHVybiBtX2J1c3k7IH0KKyAgICBRX0lO
Vk9LQUJMRSB2b2lkIG9wZW4oUVN0cmluZyBtb2RlKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIHJl
cXVlc3QoUVN0cmluZyBhY3Rpb24sIFFTdHJpbmcgaWQgPSBRU3RyaW5nKCksIGJvb2wgY29uZmly
bSA9IGZhbHNlKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIGFuc3dlcihRU3RyaW5nIHZhbHVlKTsK
KyAgICBRX0lOVk9LQUJMRSB2b2lkIGNsb3NlKCk7CitzaWduYWxzOgorICAgIHZvaWQgY2hhbmdl
ZCgpOworcHJpdmF0ZToKKyAgICB2b2lkIHNlbmQoY29uc3QgUUpzb25PYmplY3QmIHZhbHVlKTsK
KyAgICB2b2lkIGZhaWwoUVN0cmluZyBtZXNzYWdlKTsKKyAgICBRUHJvY2VzcyBtX3Byb2Nlc3M7
CisgICAgUVRpbWVyIG1fdGltZW91dDsKKyAgICBRQnl0ZUFycmF5IG1fYnVmZmVyOworICAgIFFW
YXJpYW50TGlzdCBtX2l0ZW1zOworICAgIFFWYXJpYW50TWFwIG1fc3RhdGU7CisgICAgUVN0cmlu
ZyBtX21vZGUsIG1fc3RhdHVzLCBtX3Byb21wdDsKKyAgICBib29sIG1fYnVzeSA9IGZhbHNlOwor
fTsKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbCBiL2FwcC9t
b29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAw
MDAwMDAwLi42OTlhZjdmCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3Rz
L0hhcm5lc3MucW1sCkBAIC0wLDAgKzEsMjEgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0
IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5Db250cm9scy5NYXRlcmlhbCAy
LjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFN0cmVhbWluZ1ByZWZlcmVu
Y2VzIDEuMAoraW1wb3J0ICIuLi8uLi9ndWkiCitBcHBsaWNhdGlvbldpbmRvdyB7CisgICAgTWF0
ZXJpYWwudGhlbWU6IE1hdGVyaWFsLkRhcmsKKyAgICBNYXRlcmlhbC5hY2NlbnQ6IFZiVG9rZW5z
LmFjY2VudAorICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnV2luZG93CisgICAg
TWF0ZXJpYWwuZm9yZWdyb3VuZDogVmJUb2tlbnMudGV4dAorICAgIGNvbG9yOiBWYlRva2Vucy5i
Z0FwcAorICAgIHdpZHRoOiAxMjgwOyBoZWlnaHQ6IDgwMDsgdmlzaWJsZTogdHJ1ZQorICAgIGZ1
bmN0aW9uIGNob29zZUFjY2VudChpKSB7IFN0cmVhbWluZ1ByZWZlcmVuY2VzLnVpQWNjZW50SW5k
ZXggPSBpIH0KKyAgICBJdGVtIHsgaWQ6IHN0YWNrVmlldyB9CisgICAgUXRPYmplY3QgeyBvYmpl
Y3ROYW1lOiAidGVzdFN0YXRlIjsgcHJvcGVydHkgY29sb3IgYWNjZW50OiBWYlRva2Vucy5hY2Nl
bnQ7IHByb3BlcnR5IGNvbG9yIHByZXNzZWQ6IFZiVG9rZW5zLmFjY2VudFByZXNzZWQgfQorICAg
IENyaW1zb25TdGF0dXNEaWFsb2cgeyBvYmplY3ROYW1lOiAidGVzdFBhbmVsIiB9CisgICAgU3lz
dGVtQ29ubmVjdGlvbnNEaWFsb2cgeyBvYmplY3ROYW1lOiAiY29ubmVjdGlvbnNQYW5lbCIgfQor
ICAgIEVjbGlwc2VDb250cm9sQ2VudGVyIHsgb2JqZWN0TmFtZTogImNvbnRyb2xDZW50ZXIiIH0K
KyAgICBFY2xpcHNlQWJvdXREaWFsb2cgeyBvYmplY3ROYW1lOiAiYWJvdXRFY2xpcHNlIiB9Cit9
CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sIGIvYXBw
L21vb25saWdodG9zL3Rlc3RzL1ByZWZlcmVuY2VzLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NApp
bmRleCAwMDAwMDAwLi45OTZlNWFjCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9z
L3Rlc3RzL1ByZWZlcmVuY2VzLnFtbApAQCAtMCwwICsxLDMgQEAKK3ByYWdtYSBTaW5nbGV0b24K
K2ltcG9ydCBRdFF1aWNrIDIuOQorUXRPYmplY3QgeyBwcm9wZXJ0eSBpbnQgdWlBY2NlbnRJbmRl
eDogNDsgcHJvcGVydHkgYm9vbCB1aVNob3dIaW50czogdHJ1ZTsgcHJvcGVydHkgaW50IHdpZHRo
OiAxOTIwOyBwcm9wZXJ0eSBpbnQgaGVpZ2h0OiAxMDgwOyBwcm9wZXJ0eSBpbnQgZnBzOiA2MDsg
cHJvcGVydHkgaW50IGJpdHJhdGVLYnBzOiAyMDAwMDsgZnVuY3Rpb24gc2F2ZSgpIHt9IH0KZGlm
ZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24uY3BwIGIvYXBwL21v
b25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5k
ZXggMDAwMDAwMC4uZDliNzFlZQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy90
ZXN0cy90ZXN0LWNyaW1zb24uY3BwCkBAIC0wLDAgKzEsMjczIEBACisjaW5jbHVkZSA8UXRUZXN0
PgorI2luY2x1ZGUgPFFUZW1wb3JhcnlEaXI+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNs
dWRlIDxRUW1sQ29tcG9uZW50PgorI2luY2x1ZGUgPFFRbWxDb250ZXh0PgorI2luY2x1ZGUgPFFR
dWlja1N0eWxlPgorI2luY2x1ZGUgPFFRdWlja1dpbmRvdz4KKyNpbmNsdWRlIDxRUXVpY2tJdGVt
PgorI2luY2x1ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFJbWFnZVJlYWRlcj4KKyNpbmNsdWRlIDxR
VGNwU2VydmVyPgorI2luY2x1ZGUgPFFTc2xTb2NrZXQ+CisjaW5jbHVkZSA8UVNzbEtleT4KKyNp
bmNsdWRlIDxRU3NsQ2VydGlmaWNhdGU+CisjaW5jbHVkZSA8UUNyeXB0b2dyYXBoaWNIYXNoPgor
I2luY2x1ZGUgPG1lbW9yeT4KKyNpbmNsdWRlIDxRU3RhbmRhcmRQYXRocz4KKyNpbmNsdWRlIDxR
RGlyPgorI2luY2x1ZGUgPFFGaWxlSW5mbz4KKyNpbmNsdWRlICIuLi9jcmltc29uc3RhdHVzLmgi
CisjaW5jbHVkZSAiLi4vc3lzdGVtY29udHJvbHMuaCIKKyNpbmNsdWRlICIuLi9lY2xpcHNlcHJv
ZmlsZXMuaCIKKyNpbmNsdWRlICIuLi8uLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgiCisK
K2NsYXNzIFRsc0ZpeHR1cmUgOiBwdWJsaWMgUVRjcFNlcnZlciB7CitwdWJsaWM6CisgICAgUUJ5
dGVBcnJheSBib2R5ID0gUiIoeyJjcHVfcGVyY2VudCI6MzcuNSwicmFtX3VzZWRfYnl0ZXMiOjUw
LCJyYW1fdG90YWxfYnl0ZXMiOjEwMH0pIjsKKyAgICBpbnQgY29kZSA9IDIwMCwgcmVxdWVzdHMg
PSAwOworICAgIGJvb2wgcmVzcG9uZCA9IHRydWU7CisgICAgUUJ5dGVBcnJheSBhdXRob3JpemF0
aW9uOworICAgIFFTc2xDZXJ0aWZpY2F0ZSBjZXJ0OworICAgIFFTc2xLZXkga2V5OworICAgIFRs
c0ZpeHR1cmUoKSB7CisgICAgICAgIFFGaWxlIGMocUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1T
T05fVEVTVF9DRVJUIikpOyBjLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGNlcnQgPSBRU3Ns
Q2VydGlmaWNhdGUoYy5yZWFkQWxsKCkpOworICAgICAgICBRRmlsZSBrKHFFbnZpcm9ubWVudFZh
cmlhYmxlKCJDUklNU09OX1RFU1RfS0VZIikpOyBrLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7
IGtleSA9IFFTc2xLZXkoay5yZWFkQWxsKCksIFFTc2w6OlJzYSk7CisgICAgICAgIGxpc3RlbihR
SG9zdEFkZHJlc3M6OkxvY2FsSG9zdCk7CisgICAgfQorICAgIHZvaWQgaW5jb21pbmdDb25uZWN0
aW9uKHFpbnRwdHIgZGVzY3JpcHRvcikgb3ZlcnJpZGUgeworICAgICAgICBhdXRvIHNvY2tldCA9
IG5ldyBRU3NsU29ja2V0KHRoaXMpOworICAgICAgICBzb2NrZXQtPnNldExvY2FsQ2VydGlmaWNh
dGUoY2VydCk7IHNvY2tldC0+c2V0UHJpdmF0ZUtleShrZXkpOyBzb2NrZXQtPnNldFBlZXJWZXJp
ZnlNb2RlKFFTc2xTb2NrZXQ6OlZlcmlmeU5vbmUpOworICAgICAgICBzb2NrZXQtPnNldFNvY2tl
dERlc2NyaXB0b3IoZGVzY3JpcHRvcik7CisgICAgICAgIGF1dG8gaW5wdXQgPSBzdGQ6Om1ha2Vf
c2hhcmVkPFFCeXRlQXJyYXk+KCk7CisgICAgICAgIGNvbm5lY3Qoc29ja2V0LCAmUVNzbFNvY2tl
dDo6cmVhZHlSZWFkLCB0aGlzLCBbdGhpcywgc29ja2V0LCBpbnB1dF0geworICAgICAgICAgICAg
aW5wdXQtPmFwcGVuZChzb2NrZXQtPnJlYWRBbGwoKSk7CisgICAgICAgICAgICBpZiAoIWlucHV0
LT5jb250YWlucygiXHJcblxyXG4iKSkgcmV0dXJuOworICAgICAgICAgICAgKytyZXF1ZXN0czsg
YXV0aG9yaXphdGlvbiA9ICppbnB1dDsKKyAgICAgICAgICAgIGlmIChyZXNwb25kKSB7CisgICAg
ICAgICAgICAgICAgUUJ5dGVBcnJheSBoZWFkZXIgPSAiSFRUUC8xLjEgIiArIFFCeXRlQXJyYXk6
Om51bWJlcihjb2RlKSArICIgRml4dHVyZVxyXG5Db250ZW50LVR5cGU6IGFwcGxpY2F0aW9uL2pz
b25cclxuQ29ubmVjdGlvbjogY2xvc2VcclxuQ29udGVudC1MZW5ndGg6ICIgKyBRQnl0ZUFycmF5
OjpudW1iZXIoYm9keS5zaXplKCkpICsgIlxyXG4iOworICAgICAgICAgICAgICAgIGlmIChjb2Rl
ID09IDMwMikgaGVhZGVyICs9ICJMb2NhdGlvbjogaHR0cHM6Ly8xMjcuMC4wLjI6MTIzNDUvXHJc
biI7CisgICAgICAgICAgICAgICAgc29ja2V0LT53cml0ZShoZWFkZXIgKyAiXHJcbiIgKyBib2R5
KTsgc29ja2V0LT5kaXNjb25uZWN0RnJvbUhvc3QoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAg
ICAgIGlucHV0LT5jbGVhcigpOworICAgICAgICB9KTsKKyAgICAgICAgY29ubmVjdChzb2NrZXQs
ICZRU3NsU29ja2V0OjpkaXNjb25uZWN0ZWQsIHNvY2tldCwgJlFPYmplY3Q6OmRlbGV0ZUxhdGVy
KTsKKyAgICAgICAgc29ja2V0LT5zdGFydFNlcnZlckVuY3J5cHRpb24oKTsKKyAgICB9Cit9Owor
CitjbGFzcyBDcmltc29uVGVzdCA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorcHJp
dmF0ZSBzbG90czoKKyAgICB2b2lkIGluaXRUZXN0Q2FzZSgpIHsKKyAgICAgICAgUUNvcmVBcHBs
aWNhdGlvbjo6c2V0T3JnYW5pemF0aW9uTmFtZSgiRWNsaXBzZU9TIFRlc3QiKTsKKyAgICAgICAg
UUNvcmVBcHBsaWNhdGlvbjo6c2V0QXBwbGljYXRpb25OYW1lKCJFY2xpcHNlRml4dHVyZSIpOwor
ICAgICAgICBRU2V0dGluZ3M6OnNldERlZmF1bHRGb3JtYXQoUVNldHRpbmdzOjpJbmlGb3JtYXQp
OworICAgIH0KKyAgICB2b2lkIGhvc3RQcm9maWxlc1JlbWFpbklzb2xhdGVkKCkgeworICAgICAg
ICBFY2xpcHNlUHJvZmlsZXMgcHJvZmlsZXM7CisgICAgICAgIFFWYXJpYW50TWFwIHZhbHVlc3t7
IndpZHRoIiwxMjgwfSx7ImhlaWdodCIsODAwfSx7ImZwcyIsNjB9LHsiYml0cmF0ZUticHMiLDE1
MDAwfX07CisgICAgICAgIFFWRVJJRlkocHJvZmlsZXMuc2F2ZSgiZml4dHVyZS1ob3N0LWEiLCJE
ZXNrdG9wIix2YWx1ZXMpKTsKKyAgICAgICAgUUNPTVBBUkUocHJvZmlsZXMubG9hZCgiZml4dHVy
ZS1ob3N0LWEiLCJEZXNrdG9wIiksdmFsdWVzKTsKKyAgICAgICAgUVZFUklGWShwcm9maWxlcy5s
b2FkKCJmaXh0dXJlLWhvc3QtYiIsIkRlc2t0b3AiKS5pc0VtcHR5KCkpOworICAgICAgICBRVkVS
SUZZKHByb2ZpbGVzLm5hbWVzKCJmaXh0dXJlLWhvc3QtYSIpLmNvbnRhaW5zKCJEZXNrdG9wIikp
OworICAgICAgICBRVkVSSUZZKCFwcm9maWxlcy5yZW1vdmUoImZpeHR1cmUtaG9zdC1hIiwiRGVz
a3RvcCIsZmFsc2UpKTsKKyAgICAgICAgdmFsdWVzWyJmcHMiXSA9IDA7IFFWRVJJRlkoIXByb2Zp
bGVzLnNhdmUoImZpeHR1cmUtaG9zdC1hIiwiQmFkIix2YWx1ZXMpKTsKKyAgICAgICAgUVZFUklG
WShwcm9maWxlcy5yZW1vdmUoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIsdHJ1ZSkpOworICAg
ICAgICBRVkVSSUZZKHByb2ZpbGVzLmxvYWQoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIpLmlz
RW1wdHkoKSk7CisgICAgfQorICAgIHZvaWQgc3lzdGVtQ29udHJvbHNQcml2YXRlUGlwZSgpIHsK
KyAgICAgICAgUVRlbXBvcmFyeURpciBkaXI7IFFWRVJJRlkoZGlyLmlzVmFsaWQoKSk7CisgICAg
ICAgIFFGaWxlIHNjcmlwdChkaXIuZmlsZVBhdGgoImZpeHR1cmUucHkiKSk7IFFWRVJJRlkoc2Ny
aXB0Lm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsKKyAgICAgICAgc2NyaXB0LndyaXRlKFIi
UFkoaW1wb3J0IGpzb24sc3lzCitmb3IgbGluZSBpbiBzeXMuc3RkaW46CisgICAgdmFsdWU9anNv
bi5sb2FkcyhsaW5lKQorICAgIGFjdGlvbj12YWx1ZVsnYWN0aW9uJ10KKyAgICBpZiBhY3Rpb249
PSd3aWZpLWNvbm5lY3QnOgorICAgICAgICBwcmludChqc29uLmR1bXBzKHsncHJvbXB0JzonV2kt
RmkgcGFzc3dvcmQnfSksZmx1c2g9VHJ1ZSkKKyAgICAgICAgcmVwbHk9anNvbi5sb2FkcyhzeXMu
c3RkaW4ucmVhZGxpbmUoKSkKKyAgICAgICAgYXNzZXJ0IHJlcGx5PT17J2FjdGlvbic6J2Fuc3dl
cicsJ3ZhbHVlJzonc2VjcmV0LXZhbHVlJ30KKyAgICBwcmludChqc29uLmR1bXBzKHsnaXRlbXMn
Olt7J2lkJzond2xhbjAvQUE6QkI6Q0M6REQ6RUU6RkYnLCduYW1lJzonPGI+UGxhaW4gU1NJRDwv
Yj4nLCdkZXRhaWwnOic4MCUgV1BBMicsJ2Nvbm5lY3RlZCc6YWN0aW9uPT0nd2lmaS1jb25uZWN0
J31dLCdzdGF0dXMnOidSZWFkeScsJ2RvbmUnOlRydWV9KSxmbHVzaD1UcnVlKQorKVBZIik7IHNj
cmlwdC5jbG9zZSgpOworICAgICAgICBxcHV0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVS
RSIsIHNjcmlwdC5maWxlTmFtZSgpLnRvVXRmOCgpKTsKKyAgICAgICAgU3lzdGVtQ29udHJvbHMg
Y29udHJvbHM7IGNvbnRyb2xzLm9wZW4oIndpZmkiKTsKKyAgICAgICAgUVRSWV9DT01QQVJFKGNv
bnRyb2xzLml0ZW1zKCkuc2l6ZSgpLCAxKTsgUVZFUklGWSghY29udHJvbHMuYnVzeSgpKTsKKyAg
ICAgICAgY29udHJvbHMucmVxdWVzdCgiYnQtZm9yZ2V0IiwgImludmFsaWQiLCB0cnVlKTsgUVZF
UklGWSghY29udHJvbHMuYnVzeSgpKTsKKyAgICAgICAgY29udHJvbHMucmVxdWVzdCgid2lmaS1j
b25uZWN0IiwgIndsYW4wL0FBOkJCOkNDOkREOkVFOkZGIik7CisgICAgICAgIFFUUllfVkVSSUZZ
KCFjb250cm9scy5wcm9tcHQoKS5pc0VtcHR5KCkpOyBRVkVSSUZZKGNvbnRyb2xzLmJ1c3koKSk7
CisgICAgICAgIGNvbnRyb2xzLmFuc3dlcigic2VjcmV0LXZhbHVlIik7IFFUUllfVkVSSUZZKCFj
b250cm9scy5idXN5KCkpOworICAgICAgICBRVkVSSUZZKGNvbnRyb2xzLnByb21wdCgpLmlzRW1w
dHkoKSk7IFFDT01QQVJFKGNvbnRyb2xzLnN0YXR1cygpLCBRU3RyaW5nKCJSZWFkeSIpKTsKKyAg
ICAgICAgUVZFUklGWShjb250cm9scy5pdGVtcygpLmZpcnN0KCkudG9NYXAoKS52YWx1ZSgiY29u
bmVjdGVkIikudG9Cb29sKCkpOworICAgICAgICBjb250cm9scy5jbG9zZSgpOyBRVkVSSUZZKCFj
b250cm9scy5idXN5KCkpOworICAgICAgICBxdW5zZXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19G
SVhUVVJFIik7CisgICAgfQorICAgIHZvaWQgbWFuYWdlZFVwZGF0ZXJDYW5ub3RSZXBsYWNlQ3Vz
dG9taXplZENsaWVudCgpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciBkaXI7IFFWRVJJRlkoZGly
LmlzVmFsaWQoKSk7CisgICAgICAgIGNvbnN0IFFTdHJpbmcgaW1hZ2UgPSBkaXIuZmlsZVBhdGgo
ImN1c3RvbS5BcHBJbWFnZSIpOworICAgICAgICBRRmlsZSBmKGltYWdlKTsgUVZFUklGWShmLm9w
ZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsgZi53cml0ZSgiY3VzdG9taXplZCBjbGllbnQiKTsg
Zi5jbG9zZSgpOworICAgICAgICBjb25zdCBRQnl0ZUFycmF5IG9sZCA9IHFnZXRlbnYoIkFQUElN
QUdFIik7IGNvbnN0IGJvb2wgaGFkID0gcUVudmlyb25tZW50VmFyaWFibGVJc1NldCgiQVBQSU1B
R0UiKTsKKyAgICAgICAgcXB1dGVudigiQVBQSU1BR0UiLCBpbWFnZS50b1V0ZjgoKSk7CisgICAg
ICAgIEF1dG9VcGRhdGVDaGVja2VyIGNoZWNrZXI7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5v
c01hbmFnZWQoKSk7IFFWRVJJRlkoIWNoZWNrZXIuY2FuSW5zdGFsbFVwZGF0ZXMoKSk7CisgICAg
ICAgIFFTaWduYWxTcHkgY29tcGxldGVkKCZjaGVja2VyLCAmQXV0b1VwZGF0ZUNoZWNrZXI6OmNo
ZWNrQ29tcGxldGVkKTsKKyAgICAgICAgUVNpZ25hbFNweSBmYWlsZWQoJmNoZWNrZXIsICZBdXRv
VXBkYXRlQ2hlY2tlcjo6aW5zdGFsbEZhaWxlZCk7CisgICAgICAgIGNoZWNrZXIuc3RhcnQoKTsg
Y2hlY2tlci5jaGVja05vdygpOyBjaGVja2VyLmNoYW5uZWxDaGFuZ2VkKCk7IGNoZWNrZXIuaW5z
dGFsbCgpOworICAgICAgICBRQ09NUEFSRShjb21wbGV0ZWQuY291bnQoKSwgMyk7IFFDT01QQVJF
KGZhaWxlZC5jb3VudCgpLCAxKTsKKyAgICAgICAgUVZFUklGWSghY2hlY2tlci5jaGVja2luZygp
KTsgUVZFUklGWSghY2hlY2tlci5pbnN0YWxsaW5nKCkpOworICAgICAgICBRVkVSSUZZKCFjaGVj
a2VyLmNhbkluc3RhbGwoKSk7IFFWRVJJRlkoIWNoZWNrZXIudXBkYXRlQXZhaWxhYmxlKCkpOyBR
VkVSSUZZKCFjaGVja2VyLm9mZmVyQXZhaWxhYmxlKCkpOworICAgICAgICBRQ09NUEFSRShjaGVj
a2VyLnJlbGVhc2VVcmwoKSwgUVN0cmluZygiaHR0cHM6Ly9naXRodWIuY29tL3RoM2QzY2szci9N
b29ubGlnaHQtT1MvcmVsZWFzZXMiKSk7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5jdXJyZW50
VmVyc2lvbigpLmNvbnRhaW5zKCJFY2xpcHNlT1MgY3VzdG9taXplZCIpKTsKKyAgICAgICAgUVZF
UklGWShmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkpOyBRQ09NUEFSRShmLnJlYWRBbGwoKSwg
UUJ5dGVBcnJheSgiY3VzdG9taXplZCBjbGllbnQiKSk7IGYuY2xvc2UoKTsKKyAgICAgICAgUUNP
TVBBUkUoUURpcihkaXIucGF0aCgpKS5lbnRyeUxpc3QoUURpcjo6RmlsZXMpLCBRU3RyaW5nTGlz
dHsiY3VzdG9tLkFwcEltYWdlIn0pOworICAgICAgICBpZiAoaGFkKSBxcHV0ZW52KCJBUFBJTUFH
RSIsIG9sZCk7IGVsc2UgcXVuc2V0ZW52KCJBUFBJTUFHRSIpOworICAgICAgICBRQ09NUEFSRShB
dXRvVXBkYXRlQ2hlY2tlcjo6Y29tcGFyZVNlbWFudGljVmVyc2lvbnMoIjAuNS4wIiwgIjAuNC45
IiksIDEpOworICAgIH0KKyAgICB2b2lkIGVuZHBvaW50VmFsaWRhdGlvbigpIHsKKyAgICAgICAg
UVZFUklGWShDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovLzE5Mi4xNjguMS4x
MDo0Nzk5MCIpKTsKKyAgICAgICAgUVZFUklGWShDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50
KCJodHRwczovL1tmZDAwOjoxXTo0Nzk5MC8iKSk7CisgICAgICAgIGZvciAoYXV0byBiYWQgOiB7
Imh0dHA6Ly9ob3N0IiwgImh0dHBzOi8vdXNlcjpzZWNyZXRAaG9zdCIsICJodHRwczovL2hvc3Qv
YXBpIiwgImh0dHBzOi8vaG9zdC8/dG9rZW49c2VjcmV0IiwgImZpbGU6Ly8vZXRjL3Bhc3N3ZCIs
ICJodHRwczovL2hvc3QvI2ZyYWdtZW50In0pCisgICAgICAgICAgICBRVkVSSUZZKCFDcmltc29u
U3RhdHVzOjp2YWxpZEVuZHBvaW50KGJhZCkpOworICAgIH0KKyAgICB2b2lkIG1pc3NpbmdBbmRJ
bnZhbGlkTWV0cmljcygpIHsKKyAgICAgICAgUVN0cmluZyBlcnJvcjsKKyAgICAgICAgUVZFUklG
WShDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKCJub3QganNvbiIsICZlcnJvcikuaXNFbXB0eSgp
KTsgUVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsKKyAgICAgICAgYXV0byBzID0gQ3JpbXNvblN0
YXR1czo6cGFyc2VTdGF0cyhSIih7ImNwdV9wZXJjZW50Ijo0Mi41LCJjcHVfdGVtcF9jIjotMSwi
Z3B1X3BlcmNlbnQiOm51bGwsInJhbV90b3RhbF9ieXRlcyI6MCwicmFtX3BlcmNlbnQiOjAsInZy
YW1fdG90YWxfYnl0ZXMiOjEwMCwidnJhbV91c2VkX2J5dGVzIjoxMjB9KSIsICZlcnJvcik7Cisg
ICAgICAgIFFWRVJJRlkoZXJyb3IuaXNFbXB0eSgpKTsgUUNPTVBBUkUocy52YWx1ZSgiY3B1X3Bl
cmNlbnQiKS50b0RvdWJsZSgpLCA0Mi41KTsKKyAgICAgICAgUVZFUklGWSghcy5jb250YWlucygi
Y3B1X3RlbXBfYyIpKTsgUVZFUklGWSghcy5jb250YWlucygiZ3B1X3BlcmNlbnQiKSk7IFFWRVJJ
RlkoIXMuY29udGFpbnMoInJhbV9wZXJjZW50IikpOworICAgICAgICBRQ09NUEFSRShzLnZhbHVl
KCJ2cmFtX3BlcmNlbnQiKS50b0RvdWJsZSgpLCAxMDAuMCk7CisgICAgICAgIGF1dG8gaW52YWxp
ZCA9IENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJjcHVfcGVyY2VudCI6MTAxLCJncHVf
cGVyY2VudCI6IjAifSkiLCAmZXJyb3IpOworICAgICAgICBRVkVSSUZZKGludmFsaWQuaXNFbXB0
eSgpKTsgUVZFUklGWShlcnJvci5pc0VtcHR5KCkpOworICAgICAgICBDcmltc29uU3RhdHVzOjpw
YXJzZVN0YXRzKFFCeXRlQXJyYXkoNjU1MzcsICdhJyksICZlcnJvcik7IFFWRVJJRlkoIWVycm9y
LmlzRW1wdHkoKSk7CisgICAgICAgIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJlcnJv
ciI6InVuc3VwcG9ydGVkIn0pIiwgJmVycm9yKTsgUVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsK
KyAgICB9CisgICAgdm9pZCBsb2NhbEhhcmR3YXJlRml4dHVyZSgpIHsKKyAgICAgICAgUVRlbXBv
cmFyeURpciB0ZW1wOyBRVkVSSUZZKHRlbXAuaXNWYWxpZCgpKTsKKyAgICAgICAgYXV0byB3cml0
ZSA9IFsmXShRU3RyaW5nIHAsIFFCeXRlQXJyYXkgdmFsdWUpIHsgUURpcigpLm1rcGF0aChRRmls
ZUluZm8odGVtcC5wYXRoKCkrcCkuYWJzb2x1dGVQYXRoKCkpOyBRRmlsZSBmKHRlbXAucGF0aCgp
K3ApOyBRVkVSSUZZKGYub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOyBmLndyaXRlKHZhbHVl
KTsgfTsKKyAgICAgICAgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC90eXBlIiwgIkJh
dHRlcnkiKTsgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9jYXBhY2l0eSIsICI3MyIp
OyB3cml0ZSgiL2NsYXNzL3Bvd2VyX3N1cHBseS9CQVQwL3N0YXR1cyIsICJDaGFyZ2luZyIpOwor
ICAgICAgICB3cml0ZSgiL2NsYXNzL25ldC93bGFuMC9vcGVyc3RhdGUiLCAidXAiKTsgd3JpdGUo
Ii9jbGFzcy9uZXQvbG8vb3BlcnN0YXRlIiwgInVwIik7CisgICAgICAgIGF1dG8gbG9jYWwgPSBD
cmltc29uU3RhdHVzOjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpOyBRQ09NUEFSRShsb2NhbC52YWx1
ZSgiYmF0dGVyeVBlcmNlbnQiKS50b0ludCgpLCA3Myk7IFFDT01QQVJFKGxvY2FsLnZhbHVlKCJi
YXR0ZXJ5U3RhdGUiKS50b1N0cmluZygpLCBRU3RyaW5nKCJDaGFyZ2luZyIpKTsKKyAgICAgICAg
UUNPTVBBUkUobG9jYWwudmFsdWUoIm5ldHdvcmsiKS50b1N0cmluZygpLCBRU3RyaW5nKCJ3bGFu
MCIpKTsgUVZFUklGWShsb2NhbC52YWx1ZSgiY29ubmVjdGVkIikudG9Cb29sKCkpOworICAgICAg
ICB3cml0ZSgiL2NsYXNzL3Bvd2VyX3N1cHBseS9CQVQwL2NhcGFjaXR5IiwgIjEwMSIpOyBRQ09N
UEFSRShDcmltc29uU3RhdHVzOjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpLnZhbHVlKCJiYXR0ZXJ5
UGVyY2VudCIpLnRvSW50KCksIC0xKTsKKyAgICB9CisgICAgdm9pZCBwcml2YXRlU2V0dGluZ3NB
bmROb0Nyb3NzSG9zdENyZWRlbnRpYWxzKCkgeworICAgICAgICBRU3RhbmRhcmRQYXRoczo6c2V0
VGVzdE1vZGVFbmFibGVkKHRydWUpOworICAgICAgICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3Rh
dHVzLnNlbGVjdEhvc3QoInRlc3QtYSIsICJodHRwczovLzEyNy4wLjAuMTo0Nzk5MCIpOworICAg
ICAgICBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4xOjQ3OTkwIiwg
ImZpeHR1cmUtdG9rZW4iLCAiIikpOyBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmVkKCkpOworICAg
ICAgICBhdXRvIHBhdGggPSBRU3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRh
cmRQYXRoczo6QXBwQ29uZmlnTG9jYXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpzb24iOworICAg
ICAgICBRVkVSSUZZKChRRmlsZTo6cGVybWlzc2lvbnMocGF0aCkgJiAoUUZpbGVEZXZpY2U6OlJl
YWRHcm91cCB8IFFGaWxlRGV2aWNlOjpSZWFkT3RoZXIgfCBRRmlsZURldmljZTo6V3JpdGVHcm91
cCB8IFFGaWxlRGV2aWNlOjpXcml0ZU90aGVyKSkgPT0gMCk7CisgICAgICAgIHN0YXR1cy5zZWxl
Y3RIb3N0KCJ0ZXN0LWIiLCAiaHR0cHM6Ly8xMjcuMC4wLjI6NDc5OTAiKTsgUVZFUklGWSghc3Rh
dHVzLmNvbmZpZ3VyZWQoKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0
dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIiwgIiIsICIiKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1
cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIiwgImZpeHR1cmUtdG9rZW4iLCAi
aW52YWxpZC1waW4iKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBz
Oi8vMTI3LjAuMC4yOjQ3OTkwIiwgInRva2VuXG5pbmplY3Rpb24iLCAiIikpOworICAgICAgICBR
RmlsZTo6cmVtb3ZlKHBhdGgpOworICAgIH0KKyAgICB2b2lkIHRsc0F1dGhlbnRpY2F0aW9uQW5k
VmlzaWJpbGl0eSgpIHsKKyAgICAgICAgVGxzRml4dHVyZSBzZXJ2ZXI7IFFWRVJJRlkoc2VydmVy
LmlzTGlzdGVuaW5nKCkpOyBRVkVSSUZZKCFzZXJ2ZXIuY2VydC5pc051bGwoKSk7CisgICAgICAg
IFFTdHJpbmcgdXJsID0gImh0dHBzOi8vMTI3LjAuMC4xOiIgKyBRU3RyaW5nOjpudW1iZXIoc2Vy
dmVyLnNlcnZlclBvcnQoKSk7CisgICAgICAgIFFTdHJpbmcgcGluID0gUVN0cmluZzo6ZnJvbUxh
dGluMShzZXJ2ZXIuY2VydC5kaWdlc3QoUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4
KCkpOworICAgICAgICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVjdEhvc3QoImZp
eHR1cmUtdGxzIiwgdXJsKTsKKyAgICAgICAgUVZFUklGWShzdGF0dXMuY29uZmlndXJlKHVybCwg
ImZpeHR1cmUtb25seS10b2tlbiIsICIiKSk7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAg
ICAgICBRVFJZX1ZFUklGWV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0YXR1cygpLmNvbnRhaW5zKCJm
aW5nZXJwcmludCIpLCA1MDAwKTsKKyAgICAgICAgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCAw
KTsgLy8gbm8gY3JlZGVudGlhbHMgc2VudCBiZWZvcmUgdHJ1c3Rpbmcgc2VsZi1zaWduZWQgVExT
CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJmaXh0dXJlLW9ubHktdG9r
ZW4iLCBwaW4pKTsKKyAgICAgICAgUVRSWV9DT01QQVJFX1dJVEhfVElNRU9VVChzdGF0dXMuc3Rh
dHMoKS52YWx1ZSgiY3B1X3BlcmNlbnQiKS50b0RvdWJsZSgpLCAzNy41LCA1MDAwKTsKKyAgICAg
ICAgUVZFUklGWShzZXJ2ZXIuYXV0aG9yaXphdGlvbi5jb250YWlucygiQXV0aG9yaXphdGlvbjog
QmVhcmVyIGZpeHR1cmUtb25seS10b2tlbiIpKTsKKyAgICAgICAgUVZFUklGWShzZXJ2ZXIuYXV0
aG9yaXphdGlvbi5zdGFydHNXaXRoKCJHRVQgL2FwaS9ob3N0L3N0YXRzICIpKTsKKyAgICAgICAg
c3RhdHVzLnNldFZpc2libGUoZmFsc2UpOyBpbnQgY291bnQgPSBzZXJ2ZXIucmVxdWVzdHM7IFFU
ZXN0OjpxV2FpdCgyMTAwKTsgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCBjb3VudCk7CisgICAg
ICAgIGZvciAoaW50IGNvZGUgOiB7NDAxLCA0MDMsIDQwNCwgMzAyfSkgeworICAgICAgICAgICAg
c2VydmVyLmNvZGUgPSBjb2RlOyBpbnQgcHJpb3IgPSBzZXJ2ZXIucmVxdWVzdHM7IHN0YXR1cy5z
ZXRWaXNpYmxlKHRydWUpOworICAgICAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHNl
cnZlci5yZXF1ZXN0cyA+IHByaW9yLCA1MDAwKTsKKyAgICAgICAgICAgIFFUUllfVkVSSUZZX1dJ
VEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOworICAgICAgICAgICAg
c3RhdHVzLnNldFZpc2libGUoZmFsc2UpOworICAgICAgICB9CisgICAgICAgIHNlcnZlci5jb2Rl
ID0gMjAwOyBzZXJ2ZXIuYm9keSA9IFFCeXRlQXJyYXkoNzAwMDAsICdhJyk7IGludCBwcmlvciA9
IHNlcnZlci5yZXF1ZXN0czsgc3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAgICAgIFFUUllf
VkVSSUZZX1dJVEhfVElNRU9VVChzZXJ2ZXIucmVxdWVzdHMgPiBwcmlvciwgNTAwMCk7CisgICAg
ICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUw
MDApOyBzdGF0dXMuc2V0VmlzaWJsZShmYWxzZSk7CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNv
bmZpZ3VyZSh1cmwsICJmaXh0dXJlLW9ubHktdG9rZW4iLCBRU3RyaW5nKDY0LCAnMCcpKSk7IHN0
YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAgICBjb3VudCA9IHNlcnZlci5yZXF1ZXN0czsg
UVRlc3Q6OnFXYWl0KDUwMCk7IFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywgY291bnQpOyBRVkVS
SUZZKHN0YXR1cy5zdGF0cygpLmlzRW1wdHkoKSk7CisgICAgICAgIHN0YXR1cy5zZXRWaXNpYmxl
KGZhbHNlKTsKKyAgICB9CisgICAgdm9pZCBpY29uUmVzb3VyY2VzKCkgeworICAgICAgICBmb3Ig
KGNvbnN0IFFTdHJpbmcmIG5hbWUgOiB7ImVjbGlwc2UtaWNvbiIsICJlY2xpcHNlLWNvbnRyb2xz
IiwgImVjbGlwc2UtcG93ZXIiLCAiY3JpbXNvbi1uZXR3b3JrIiwgImNyaW1zb24tYmx1ZXRvb3Ro
IiwgImNyaW1zb24tYmF0dGVyeSIsICJjcmltc29uLWhvc3QiLCAic2V0dGluZ3MifSkgeworICAg
ICAgICAgICAgY29uc3QgUVN0cmluZyBwYXRoID0gIjovcmVzLyIgKyBuYW1lICsgIi5zdmciOwor
ICAgICAgICAgICAgUVZFUklGWTIoUUZpbGU6OmV4aXN0cyhwYXRoKSwgcVByaW50YWJsZShwYXRo
KSk7CisgICAgICAgICAgICBRSW1hZ2VSZWFkZXIgcmVhZGVyKHBhdGgpOworICAgICAgICAgICAg
UVZFUklGWTIoIXJlYWRlci5yZWFkKCkuaXNOdWxsKCksIHFQcmludGFibGUocGF0aCArICI6ICIg
KyByZWFkZXIuZXJyb3JTdHJpbmcoKSkpOworICAgICAgICB9CisgICAgfQorICAgIHZvaWQgcW1s
UGFsZXR0ZUFuZFBhbmVscygpIHsKKyAgICAgICAgUVN0cmluZyBzb3VyY2UgPSBxRW52aXJvbm1l
bnRWYXJpYWJsZSgiVklCRU1JU19URVNUX1NPVVJDRSIpOyBRVkVSSUZZKCFzb3VyY2UuaXNFbXB0
eSgpKTsKKyAgICAgICAgUVF1aWNrU3R5bGU6OnNldFN0eWxlKCJNYXRlcmlhbCIpOworICAgICAg
ICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGUoUVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UgKyAi
L2FwcC9tb29ubGlnaHRvcy90ZXN0cy9QcmVmZXJlbmNlcy5xbWwiKSwgIlN0cmVhbWluZ1ByZWZl
cmVuY2VzIiwgMSwgMCwgIlN0cmVhbWluZ1ByZWZlcmVuY2VzIik7CisgICAgICAgIHFtbFJlZ2lz
dGVyU2luZ2xldG9uVHlwZShRVXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSArICIvYXBwL2d1aS9W
YlRva2Vucy5xbWwiKSwgIlZpYmVtaXMuUmVkZXNpZ24iLCAxLCAwLCAiVmJUb2tlbnMiKTsKKyAg
ICAgICAgUVRlbXBvcmFyeURpciBjb250cm9sc0ZpeHR1cmU7IFFWRVJJRlkoY29udHJvbHNGaXh0
dXJlLmlzVmFsaWQoKSk7CisgICAgICAgIFFGaWxlIGhlbHBlcihjb250cm9sc0ZpeHR1cmUuZmls
ZVBhdGgoImhlbHBlci5weSIpKTsgUVZFUklGWShoZWxwZXIub3BlbihRSU9EZXZpY2U6OldyaXRl
T25seSkpOworICAgICAgICBoZWxwZXIud3JpdGUoUiJQWShpbXBvcnQganNvbixzeXMKK2ZvciBs
aW5lIGluIHN5cy5zdGRpbjoKKyAgICB2YWx1ZT1qc29uLmxvYWRzKGxpbmUpCisgICAgcHJpbnQo
anNvbi5kdW1wcyh7J3N0YXRlJzp7J3ZvbHVtZSc6NTAsJ211dGVkJzpGYWxzZSwnc2lua3MnOlt7
J2lkJzonNDInLCduYW1lJzonU3BlYWtlcnMnLCdkZWZhdWx0JzpUcnVlfSx7J2lkJzonNTcnLCdu
YW1lJzonQWlyUG9kcycsJ2RlZmF1bHQnOkZhbHNlfV0sJ2JyaWdodG5lc3MnOnsnc2NyZWVuJzp7
J2RldmljZSc6J2ludGVsX2JhY2tsaWdodCcsJ3BlcmNlbnQnOjYwfSwna2V5Ym9hcmQnOnsnZGV2
aWNlJzonc3BpOjprYmRfYmFja2xpZ2h0JywncGVyY2VudCc6MzB9fSwnb3MnOnsnTkFNRSc6J0Vj
bGlwc2VPUycsJ1ZFUlNJT04nOicwLjMtZGV2JywnVEFSR0VUJzonRml4dHVyZSBoYXJkd2FyZScs
J0ZFRE9SQSc6JzQ0J30sJ2tlcm5lbCc6J2ZpeHR1cmUta2VybmVsJ30sJ2l0ZW1zJzpbeydpZCc6
J2ZpeHR1cmUnLCduYW1lJzonRml4dHVyZSBkZXZpY2UnLCdkZXRhaWwnOidBdmFpbGFibGUnLCdj
b25uZWN0ZWQnOlRydWV9XSwnc3RhdHVzJzonUmVhZHknLCdkb25lJzpUcnVlfSksZmx1c2g9VHJ1
ZSkKKylQWSIpOyBoZWxwZXIuY2xvc2UoKTsKKyAgICAgICAgcXB1dGVudigiTU9PTkxJR0hUX0NP
TlRST0xTX0ZJWFRVUkUiLGhlbHBlci5maWxlTmFtZSgpLnRvVXRmOCgpKTsKKyAgICAgICAgUVFt
bEVuZ2luZSBlbmdpbmU7CisgICAgICAgIFFRbWxDb21wb25lbnQgY29tcG9uZW50KCZlbmdpbmUs
IFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNlICsgIi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvSGFy
bmVzcy5xbWwiKSk7CisgICAgICAgIFFTY29wZWRQb2ludGVyPFFPYmplY3Q+IHJvb3QoY29tcG9u
ZW50LmNyZWF0ZSgpKTsgUVZFUklGWTIocm9vdCwgcVByaW50YWJsZShjb21wb25lbnQuZXJyb3JT
dHJpbmcoKSkpOworICAgICAgICBhdXRvIHBhbmVsID0gcm9vdC0+ZmluZENoaWxkPFFPYmplY3Qq
PigidGVzdFBhbmVsIik7IFFWRVJJRlkocGFuZWwpOworICAgICAgICBhdXRvIHN0YXRlID0gcm9v
dC0+ZmluZENoaWxkPFFPYmplY3QqPigidGVzdFN0YXRlIik7IFFWRVJJRlkoc3RhdGUpOworICAg
ICAgICBmb3IgKGludCBpID0gMDsgaSA8IDE2OyArK2kpIHsKKyAgICAgICAgICAgIFFWRVJJRlko
UU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwgImNob29zZUFjY2VudCIsIFFf
QVJHKFFWYXJpYW50LCBpKSkpOworICAgICAgICAgICAgUVZFUklGWShzdGF0ZS0+cHJvcGVydHko
ImFjY2VudCIpLnZhbHVlPFFDb2xvcj4oKS5pc1ZhbGlkKCkpOworICAgICAgICAgICAgUVZFUklG
WShzdGF0ZS0+cHJvcGVydHkoInByZXNzZWQiKS52YWx1ZTxRQ29sb3I+KCkuaXNWYWxpZCgpKTsK
KyAgICAgICAgfQorICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9v
dC5kYXRhKCksICJjaG9vc2VBY2NlbnQiLCBRX0FSRyhRVmFyaWFudCwgNCkpKTsKKyAgICAgICAg
Zm9yIChRU3RyaW5nIGtpbmQgOiB7Im5ldHdvcmsiLCAiYmF0dGVyeSIsICJob3N0In0pIHsKKyAg
ICAgICAgICAgIFFWRVJJRlkocGFuZWwtPnNldFByb3BlcnR5KCJraW5kIiwga2luZCkpOworICAg
ICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHBhbmVsLCAib3BlbiIp
KTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICBRVkVSSUZZKHBhbmVsLT5wcm9wZXJ0
eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsKKyAgICAgICAgICAgIFFTdHJpbmcgb3V0ID0gcUVudmly
b25tZW50VmFyaWFibGUoIkNSSU1TT05fU0NSRUVOU0hPVFMiKTsKKyAgICAgICAgICAgIGlmICgh
b3V0LmlzRW1wdHkoKSkgeworICAgICAgICAgICAgICAgIFFEaXIoKS5ta3BhdGgob3V0KTsKKyAg
ICAgICAgICAgICAgICBhdXRvIHdpbmRvdyA9IHFvYmplY3RfY2FzdDxRUXVpY2tXaW5kb3cqPihy
b290LmRhdGEoKSk7IFFWRVJJRlkod2luZG93KTsKKyAgICAgICAgICAgICAgICBRVkVSSUZZKHdp
bmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0ICsgIi8iICsga2luZCArICIucG5nIikpOworICAg
ICAgICAgICAgfQorICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9k
KHBhbmVsLCAiY2xvc2UiKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAgICAgICB9CisgICAgICAg
IGF1dG8gY29ubmVjdGlvbnMgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJjb25uZWN0aW9u
c1BhbmVsIik7IFFWRVJJRlkoY29ubmVjdGlvbnMpOworICAgICAgICBmb3IgKFFTdHJpbmcga2lu
ZCA6IHsid2lmaSIsICJidCJ9KSB7CisgICAgICAgICAgICByb290LT5zZXRQcm9wZXJ0eSgid2lk
dGgiLCAxMDI0KTsgcm9vdC0+c2V0UHJvcGVydHkoImhlaWdodCIsIDY0MCk7CisgICAgICAgICAg
ICBRVkVSSUZZKGNvbm5lY3Rpb25zLT5zZXRQcm9wZXJ0eSgia2luZCIsIGtpbmQpKTsKKyAgICAg
ICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChjb25uZWN0aW9ucywgIm9w
ZW4iKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAgICAgICAgICAgUVZFUklGWShjb25uZWN0aW9u
cy0+cHJvcGVydHkoInZpc2libGUiKS50b0Jvb2woKSk7CisgICAgICAgICAgICBRVkVSSUZZKGNv
bm5lY3Rpb25zLT5wcm9wZXJ0eSgid2lkdGgiKS50b0ludCgpIDw9IDk5Mik7CisgICAgICAgICAg
ICBRU3RyaW5nIG91dCA9IHFFbnZpcm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1NDUkVFTlNIT1RT
Iik7CisgICAgICAgICAgICBpZiAoIW91dC5pc0VtcHR5KCkpIHsKKyAgICAgICAgICAgICAgICBh
dXRvIHdpbmRvdyA9IHFvYmplY3RfY2FzdDxRUXVpY2tXaW5kb3cqPihyb290LmRhdGEoKSk7IFFW
RVJJRlkod2luZG93KTsKKyAgICAgICAgICAgICAgICBRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRv
dygpLnNhdmUob3V0ICsgIi8iICsga2luZCArICItc2VsZWN0b3IucG5nIikpOworICAgICAgICAg
ICAgfQorICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNvbm5l
Y3Rpb25zLCAiY2xvc2UiKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAgICAgICB9CisgICAgICAg
IFFRbWxDb21wb25lbnQgYWN0aW9uQ29tcG9uZW50KCZlbmdpbmUsUVVybDo6ZnJvbUxvY2FsRmls
ZShzb3VyY2UrIi9hcHAvZ3VpL0VjbGlwc2VBY3Rpb25CdXR0b24ucW1sIikpOworICAgICAgICBR
U2NvcGVkUG9pbnRlcjxRT2JqZWN0PiBhY3Rpb24oYWN0aW9uQ29tcG9uZW50LmNyZWF0ZSgpKTsg
UVZFUklGWTIoYWN0aW9uLHFQcmludGFibGUoYWN0aW9uQ29tcG9uZW50LmVycm9yU3RyaW5nKCkp
KTsKKyAgICAgICAgYXV0byBhY3Rpb25JdGVtID0gcW9iamVjdF9jYXN0PFFRdWlja0l0ZW0qPihh
Y3Rpb24uZGF0YSgpKTsgUVZFUklGWShhY3Rpb25JdGVtKTsKKyAgICAgICAgYXV0byBhY3Rpb25X
aW5kb3cgPSBxb2JqZWN0X2Nhc3Q8UVF1aWNrV2luZG93Kj4ocm9vdC5kYXRhKCkpOyBRVkVSSUZZ
KGFjdGlvbldpbmRvdyk7CisgICAgICAgIGFjdGlvbkl0ZW0tPnNldFBhcmVudEl0ZW0oYWN0aW9u
V2luZG93LT5jb250ZW50SXRlbSgpKTsgYWN0aW9uSXRlbS0+Zm9yY2VBY3RpdmVGb2N1cygpOwor
ICAgICAgICBRU2lnbmFsU3B5IGFjdGl2YXRlZChhY3Rpb24uZGF0YSgpLFNJR05BTChjbGlja2Vk
KCkpKTsKKyAgICAgICAgUVRlc3Q6OmtleUNsaWNrKGFjdGlvbldpbmRvdyxRdDo6S2V5X1JldHVy
bik7IFFDT01QQVJFKGFjdGl2YXRlZC5jb3VudCgpLDEpOworICAgICAgICBhY3Rpb25JdGVtLT5z
ZXRWaXNpYmxlKGZhbHNlKTsKKyAgICAgICAgYXV0byBjZW50ZXIgPSByb290LT5maW5kQ2hpbGQ8
UU9iamVjdCo+KCJjb250cm9sQ2VudGVyIik7IFFWRVJJRlkoY2VudGVyKTsKKyAgICAgICAgUVZF
UklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNlbnRlciwib3BlbiIpKTsgUVRlc3Q6OnFX
YWl0KDUwMCk7CisgICAgICAgIFFWRVJJRlkoY2VudGVyLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRv
Qm9vbCgpKTsKKyAgICAgICAgUVN0cmluZyBvdXQgPSBxRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJ
TVNPTl9TQ1JFRU5TSE9UUyIpOworICAgICAgICBhdXRvIHdpbmRvdyA9IHFvYmplY3RfY2FzdDxR
UXVpY2tXaW5kb3cqPihyb290LmRhdGEoKSk7IFFWRVJJRlkod2luZG93KTsKKyAgICAgICAgaWYg
KCFvdXQuaXNFbXB0eSgpKSBRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0KyIv
ZWNsaXBzZS1jb250cm9sLWNlbnRlci5wbmciKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmpl
Y3Q6Omludm9rZU1ldGhvZChjZW50ZXIsImNsb3NlIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAg
ICAgICAgYXV0byBhYm91dCA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oImFib3V0RWNsaXBz
ZSIpOyBRVkVSSUZZKGFib3V0KTsKKyAgICAgICAgYWJvdXQtPnNldFByb3BlcnR5KCJpbmZvIiwg
UVZhcmlhbnRNYXB7eyJvcyIsUVZhcmlhbnRNYXB7eyJOQU1FIiwiRWNsaXBzZU9TIn0seyJWRVJT
SU9OIiwiMC4zLWRldiJ9LHsiVEFSR0VUIiwiRml4dHVyZSBoYXJkd2FyZSJ9LHsiRkVET1JBIiwi
NDQifX19LHsia2VybmVsIiwiZml4dHVyZS1rZXJuZWwifX0pOworICAgICAgICBRVkVSSUZZKFFN
ZXRhT2JqZWN0OjppbnZva2VNZXRob2QoYWJvdXQsIm9wZW4iKSk7IFFUZXN0OjpxV2FpdCgzMDAp
OworICAgICAgICBRVkVSSUZZKGFib3V0LT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsK
KyAgICAgICAgaWYgKCFvdXQuaXNFbXB0eSgpKSBRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygp
LnNhdmUob3V0KyIvZWNsaXBzZS1hYm91dC5wbmciKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFP
YmplY3Q6Omludm9rZU1ldGhvZChhYm91dCwiY2xvc2UiKSk7CisgICAgICAgIHF1bnNldGVudigi
TU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUiKTsKKyAgICB9Cit9OworUVRFU1RfTUFJTihDcmlt
c29uVGVzdCkKKyNpbmNsdWRlICJ0ZXN0LWNyaW1zb24ubW9jIgpkaWZmIC0tZ2l0IGEvYXBwL21v
b25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5wcm8gYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMv
dGVzdC1jcmltc29uLnBybwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi41MDFj
ZTY1Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNv
bi5wcm8KQEAgLTAsMCArMSwxOCBAQAorUVQgKz0gY29yZSBndWkgcXVpY2sgbmV0d29yayBxdWlj
a2NvbnRyb2xzMiB0ZXN0bGliIHN2ZworQ09ORklHICs9IGMrKzE3IHRlc3RjYXNlCitUQVJHRVQg
PSB0ZXN0LWNyaW1zb24KK1NPVVJDRVMgKz0gdGVzdC1jcmltc29uLmNwcCAuLi9jcmltc29uc3Rh
dHVzLmNwcAorSEVBREVSUyArPSAuLi9jcmltc29uc3RhdHVzLmgKKworU09VUkNFUyArPSAuLi9t
YW5hZ2VkdXBkYXRlcy5jcHAKK0hFQURFUlMgKz0gLi4vLi4vYmFja2VuZC9hdXRvdXBkYXRlY2hl
Y2tlci5oCisKK0RFRklORVMgKz0gTU9PTkxJR0hUX0NPTlRST0xTX1RFU1QKK1NPVVJDRVMgKz0g
Li4vc3lzdGVtY29udHJvbHMuY3BwCitIRUFERVJTICs9IC4uL3N5c3RlbWNvbnRyb2xzLmgKKwor
U09VUkNFUyArPSAuLi9lY2xpcHNlcHJvZmlsZXMuY3BwCitIRUFERVJTICs9IC4uL2VjbGlwc2Vw
cm9maWxlcy5oCisKKyMgTWF0Y2ggdGhlIHByb2R1Y3Rpb24gcmVzb3VyY2UgYnVuZGxlIHNvIHJl
bmRlcmVkIGljb25zIGFyZSBhY3R1YWxseSB0ZXN0ZWQuCitSRVNPVVJDRVMgKz0gLi4vLi4vcmVz
b3VyY2VzLnFyYwpkaWZmIC0tZ2l0IGEvYXBwL3FtbC5xcmMgYi9hcHAvcW1sLnFyYwppbmRleCBh
M2MxMWRkLi43MTRjNjUxIDEwMDY0NAotLS0gYS9hcHAvcW1sLnFyYworKysgYi9hcHAvcW1sLnFy
YwpAQCAtMTQsNiArMTQsMTEgQEAKICAgICAgICAgPGZpbGU+Z3VpL1ZiSG9zdENhcmQucW1sPC9m
aWxlPgogICAgICAgICA8ZmlsZT5ndWkvVmJXZWxjb21lU2hlZXQucW1sPC9maWxlPgogICAgICAg
ICA8ZmlsZT5ndWkvbWFpbi5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uU3Rh
dHVzRGlhbG9nLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL1N5c3RlbUNvbm5lY3Rpb25z
RGlhbG9nLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0VjbGlwc2VDb250cm9sQ2VudGVy
LnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0VjbGlwc2VBY3Rpb25CdXR0b24ucW1sPC9m
aWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUFib3V0RGlhbG9nLnFtbDwvZmlsZT4KICAg
ICAgICAgPGZpbGU+Z3VpL1BjVmlldy5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9BcHBW
aWV3LnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL1NldHRpbmdzVmlldy5xbWw8L2ZpbGU+
CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1zb24tYmF0dGVyeS5zdmcgYi9hcHAvcmVzL2NyaW1z
b24tYmF0dGVyeS5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uMzc1MzU2
NgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMvY3JpbXNvbi1iYXR0ZXJ5LnN2ZwpAQCAtMCww
ICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0
IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxnIGZpbGw9Im5vbmUiIHN0cm9rZT0i
I0VDRUVGMSIgc3Ryb2tlLXdpZHRoPSIxLjgiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tl
LWxpbmVqb2luPSJyb3VuZCI+PHJlY3QgeD0iMiIgeT0iNiIgd2lkdGg9IjE4IiBoZWlnaHQ9IjEy
IiByeD0iMiIvPjxwYXRoIGQ9Ik0yMiAxMHY0TTYgMTB2NE0xMCAxMHY0TTE0IDEwdjQiLz48L2c+
PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZyBiL2FwcC9y
ZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAw
MDAuLmNlZjlhYjgKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3Ro
LnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2
ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik03
IDdsMTAgMTAtNSA0VjNsNSA0TDcgMTciIGZpbGw9Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9r
ZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91
bmQiLz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1ob3N0LnN2ZyBiL2FwcC9y
ZXMvY3JpbXNvbi1ob3N0LnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5k
MWQ1OWIwCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9jcmltc29uLWhvc3Quc3ZnCkBAIC0w
LDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0i
MjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCI+PGcgZmlsbD0ibm9uZSIgc3Ryb2tl
PSIjRUNFRUYxIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJv
a2UtbGluZWpvaW49InJvdW5kIj48cmVjdCB4PSIzIiB5PSIzIiB3aWR0aD0iMTgiIGhlaWdodD0i
MTQiIHJ4PSIyIi8+PHBhdGggZD0iTTggMjFoOE0xMiAxN3Y0TTYgMTBoM2wyLTQgMyA4IDItNGgy
Ii8+PC9nPjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnIGIv
YXBwL3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAw
MDAwMDAuLmIyYTEwM2EKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2NyaW1zb24tbmV0d29y
ay5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9z
dmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48ZyBmaWxsPSJu
b25lIiBzdHJva2U9IiNFQ0VFRjEiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0i
cm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxwYXRoIGQ9Ik0zIDhhMTQgMTQgMCAwIDEg
MTggME02IDEyYTkgOSAwIDAgMSAxMiAwTTkgMTZhNCA0IDAgMCAxIDYgMCIvPjxjaXJjbGUgY3g9
IjEyIiBjeT0iMjAiIHI9IjEiLz48L2c+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlw
c2UtY29udHJvbHMuc3ZnIGIvYXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZwpuZXcgZmlsZSBt
b2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi42NTNkYmQ4Ci0tLSAvZGV2L251bGwKKysrIGIvYXBw
L3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRw
Oi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIw
IDAgMjQgMjQiPjxwYXRoIGQ9Ik00IDZoMTZNNCAxMmgxNk00IDE4aDE2TTggM3Y2TTE2IDl2Nk0x
MCAxNXY2IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ry
b2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYg
LS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcgYi9hcHAvcmVzL2VjbGlwc2UtaWNvbi5z
dmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uNzExNWMzMwotLS0gL2Rldi9u
dWxsCisrKyBiL2FwcC9yZXMvZWNsaXBzZS1pY29uLnN2ZwpAQCAtMCwwICsxLDcgQEAKKzxzdmcg
eG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iNTEyIiBoZWlnaHQ9IjUx
MiIgdmlld0JveD0iMCAwIDUxMiA1MTIiPgorPGRlZnM+PGxpbmVhckdyYWRpZW50IGlkPSJyaW0i
IHgxPSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjZmY3NThiIi8+
PHN0b3Agb2Zmc2V0PSIuNDgiIHN0b3AtY29sb3I9IiNkYzM2NTgiLz48c3RvcCBvZmZzZXQ9IjEi
IHN0b3AtY29sb3I9IiM2MzE1MmIiLz48L2xpbmVhckdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBp
ZD0iZ2xhc3MiIHgxPSIwIiB5MT0iMCIgeDI9IjAiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIj
MjAxNTFjIi8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjMDgwODBiIi8+PC9saW5lYXJH
cmFkaWVudD48L2RlZnM+Cis8cmVjdCB4PSIxMiIgeT0iMTIiIHdpZHRoPSI0ODgiIGhlaWdodD0i
NDg4IiByeD0iMTEwIiBmaWxsPSJ1cmwoI2dsYXNzKSIgc3Ryb2tlPSIjZmZmZmZmIiBzdHJva2Ut
b3BhY2l0eT0iLjEzIiBzdHJva2Utd2lkdGg9IjIiLz4KKzxjaXJjbGUgY3g9IjI1NiIgY3k9IjI1
NiIgcj0iMTQ0IiBmaWxsPSJ1cmwoI3JpbSkiLz4KKzxjaXJjbGUgY3g9IjI2OCIgY3k9IjI0OSIg
cj0iMTM2IiBmaWxsPSIjMDgwODBiIi8+Cis8cGF0aCBkPSJNMTUxIDE2MmExNDMgMTQzIDAgMCAx
IDEzNS00OCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZlOGVlIiBzdHJva2Utb3BhY2l0eT0iLjU1
IiBzdHJva2Utd2lkdGg9IjMiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPgorPC9zdmc+CmRpZmYg
LS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtbWFyay0xMjgucG5nIGIvYXBwL3Jlcy9lY2xpcHNlLW1h
cmstMTI4LnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwLi4xNTEyMWMwNGJlN2E0Y2I5ZmI2NWZmMDk5ZDc0NjdiNDQ0
YzZlOTBkCkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCA3MDg3CnpjbVY7ZzgmS3FsUCk8aDszS3xM
azAwMGUxTkpMVHEwMDRqaDAwNGpwMV5AczYhIy1pbDAwMHx5TmtsPFpjJTFFPgp6ZDYtPCliPk0m
Si1kQ0B4eUx3ZCUyXyZfSWdwaztnRmgpUlpnYmo4RWoyRk8tP0hDN2RuMmhsXjhTbjlZPTk1ViMK
ejZNclU/Y3JyNnkkbWlJMmE2RkZVSTVPaXZqMkZPUXZ6dlZwbEYrYE9tVV5rYCtUT2VPJXBiMysp
b0x8RGZWI1JgCnpzJFlNdktkSE9BLW03PWNKQD1lKiZwbDc1RjlNK0tgYClDNkJzVkFGaGAyZWpZ
U2sqVWFePWJaMm1td0g3Y2BBOQp6SyhLUDwlMyMmMVJSK2ZEI15MMyN6d3hTN3RJVWx6LWVgYiQ/
OVl1Z3hZKEluWkBzbGAqU2NMe3h3Nkx8P3NIRlAKeihxV0lBeT9BIXo+WmBCTCtyV0Q3e1A+cHl0
NSZWQEh7TipUMGwjPVg5NXd+JD4rNz90U0ZpUnwmNmxkbUg2T1U8CnpscFdpKXpIeFlIX3pqaEVk
MSlORzxEN0hkcz1nSn47QmNNJGgoSUozRiRIVndLb0htK1ZMSlZNTWB5PCkkSVlHaAp6JkBEZl88
cnh2Rk8kKlozKkpvQypVaE5MY1g8elJmUjBaejxZIUxBTkUzUDxlKUF9diU5VWRDR3Z8SzhtPUFF
PDcKemRBeGQxdCFsXlhKP2p5UVIwU2V9NXJlZWBXMzVZUChvZU5AdypUQWx6NEwka1B5Zz5Ia0ht
M2VUKnV6fipLeHwlCnpefHVDYXNaQCRmUj0palJUZW9mZlI2ZHUjSUYySDUmWT1uanVCeUV2YF80
Q01iSntlZ0hhLStrUlRVSH4wQGhsQgp6UjclXzArSX41QT8lZS0lJDMxdGhpSn1PPTA7ODdxKSQq
RElRUFZzeiFzVkE7eys1a3YqTUI4OUpiWGM9UW8qWXQKek1xKXV+JmRXSUd3a2k5QWJIRmBIbG1Z
ZVhIODNLQ1ZNdHA/YCk/TVhjKjBseWBEZyQ3RUE+aHJlUmVnay1XdDNYCnpYO3tHaDsyWW9Re0Aq
dj5APmwpK3lSUiNrJTZScU83XkJ0U0g8Pih+X2c7Kk1Ob08rNW9PUjYyKk1JeilLbHxWKAp6S1JH
fVdaTjt6ajI0aWAoM0o/SkNScXdwJjUxeFBhc3FZTEE8KDlAU1IlNDgoRGZvS2h5IVI1PXo7dHhC
S1l6KzsKenIrKW0wfEdONUtVWm9QZThVP1QtO0AqRDIjVUl8aGUjNXMkM2RKLStFRncqQmVoTnw1
NyRzPVF3cDMxN3dDSzlxCnpAQTx7fFJNaTU5RyN3bk8wdDh8dHpHJWUtcFdEMjclVDB4MTVvP1Uy
SXFEayk9ZUBUckVpTHIrX0l9fTQ1OGlXPQp6YGFASEtTSW98PldNdj5DQHI1ZmNffXM9I257TyU8
aV9SRk0zUmJDbEQ5dk40ND1jdUtwOyZhQUhnRXBnZykxKWoKem9RU3hVdGI5ZjVkezcxRz4rNz8z
YjllbFFEPSlyZz4qZyZ0bH1hVU5qRzVIYldSdXM3Ny1MTVNSRW9FNS1nNDkxCnpGU3opX2NYTX4j
KlZsSllFQiYkeFB6JmB3Yz09VzV6UE50RiZCYkVUSC0rRXVoJXY/JWkkJVkyITs5Yms7TkA0SAp6
eUwkQyVjUTdUR1A/KEJ9QW9BVnNleilVcXtfRUVzOXZtMXZMNXo1czNwJiNVdWlsJWs/KFglVWBT
S1Vlez5Wb0AKekdPVlp5cXZfO1BDUkJodnVzPTQmb3BaKW5IfUJsR15JR1IhKTd6aEJzQV9ERDRV
VjBBP0I3NTUjR3t8Xi1jUlRoCno5eCRUJnpeKEBPLXBrJXxMSTNWTypHNFhPaCVfQyhYPzdyREJO
d349LUZ2Uj5kKnxoRTIzKzMrUVFKZm96XkUkQQp6bVlqQyktYVB+N0F2RDlpPjVEX0xHa1NWe2Bg
RnFpLVlnPUp0UShCN3A5U2NuJmpTOVA3aFVwPmR+VzFDTVZyRSgKei1kSUlfSzlAV0hUXkM8XkRk
NUxEZ3lTdU12RFclaVBkTkc0MU8wbjFZPnhnVDAqN0x7WFpHQ25eIWpKcz5ZT3UtCnp1Pnp3T3Bq
dnc1YGAqKkh5cFNKeHYjTThgIWFvd1FVT2swO3sofD5pQHhFbiV1Z1YoTy12Ul9jZUQxUWR6cSk8
Zgp6anhSZHpWQFpEMldjbXt1Vn1kenpqe0VCVWszYWsrI3ctfCheI1BvITJFIytTY1IxJmVYM1Qj
aVZWclhlPWtvOCsKenEhZSM3OTVnVSR7YEh5PGR8K3cwVHQwZDFAMHVKRDc9VXVBYm4/fCNVQStY
KitCOUdRP3otelAxRiYoXl83JT4jCnpMdGFYM0dPY2pWeG5TJG9PKUZyWiVuaVdaY2kjO19GYHIt
Vm9udVN8PkpmI0FBUi11SjR0bXNIY08pU3E+WVphRwp6VXN3K05XTHxVZnlzPyYyc2wzI0E5aylx
a2BlSkg9UlBmI3QjU3V+TGFOZ2wtNzBUMks3YlU0JDlhRThPWkdhaUMKejItRWtAaTFTTGhSNmZh
QWkrOVAhZ01qMkNjXkFqXzxiQH5BUVB0fExuNFREODVXcVB7cDtEJENNfGZqc1g+RnlhCnpyLSN8
eUdkUU5CbGdAMEdiU2d4UTs4ZHgmbX0wcmlOVT16NkIrdDskRmhqI1JxTm9CMHF2fHEhWktKM3ZR
NTROXwp6YWNvN3owczl0c1pvVCFedG9Mek9FdDVQfFNOVTN+amF1ZyZgSD5NUy1xRl80JmVEWlRJ
T2x7RFN1dVlSM3A9XzwKenQxeV8pdjJBRjhaRyhIK21DdiFhVHdvfXdQKkhgemw1V2l+dWN3UHNK
Mzg2QmNRMUdUYFl1dnwjZnNUQ0VoemdHCnpWcF5laUA0RDhrUzw/I1NVYCg5OVl1JkM7b3dsTSg4
fVcrPlJ0KTgrTGNVbGUrdCRWI216fkxGJWcqTUtnLWUoKAp6QT1gS0M8bGc2PjthbHNVPEkhRFBk
Mng3dlR3TGJCcDxNZ1czSyhuPGtQZyMwPWE1SitBX1ReZ3ZYOztXU2QtKykKelJIdXoxMm55PTdi
PX5qUnJLdUBecTZvc0Mke3dyZT0+SG9UMGoja1VxWTVMJUJKKmE/PUlUR1pnYiR1fDk/TSQwCnpD
fmV4eEtpX2REKkZXPHBfd0Mtc2glMTl3TlRtbzxtZSNRQ2ZLTkRIakg7Umx6ZEd1akRsVSNGI31P
aHolMzlKawp6TUhtRGFHMUVkM0gyRGhsUlFGe254X19vYHp2YVhSI1RyQkdKJHJ8VFNhfEhRZUQ7
ZD5AdTZrc2E5bV9+PjhZcHEKekA8WD9CJVpwRjV3VXxweGRZQj9CO2klYkcpbnVGNkF1dSkpc0JQ
SipRSGYoSmFnMj0mPV4jWlcycjtJeTY9NVJUCnpQTWNKKDBMRUdkTUBIeU1yfUBHYVM4P3FoeW9F
Vk1DSExzRmVDNSU1YFIwWnZkOHc0ZzF9VTxjUnpVSHB4SSt+OQp6dEdiPnNtU0xuKXJXOGVGUVh3
cz01RHtyO01IdEpwUHlqMjJOSWlvP0wlaWU2di10OD1TOTV4KjRXOE0remRaZFkKekgjfmhtJmtW
anE1UU1hYUVzNDNGMWZmcmFrU0skcTZlPWFrYVlReXU2OSViaXAjJS1EMEQmPiZEcktANXpKQiRg
CnpgMCk4RjNEJDA9fEhZQGQ7cHlNO3RyczIjNyFgYjZDJjVwSWh+VSZRVHE9LUJnPUU3RkdCJCo0
SypsTFJWfGY5QQp6dkZ0NjNhN05FOHpXRkRBJHs4SXEoY2VBSlY9cnl6O304RndNfE4kY0hRZlIq
ckdnKWVSUUd0N3E2KUVodzFxN00KeiN4I2YkOTRPb1Vvan4xcE9mYFlBPzlTKFMqV3kkNyl+N3lB
K3dMTHMhTjw4e19nNFArLXJNTGU2PT0ofTY4cHZ3Cnp7Q0dyISpnSit4QlZAeEMhWFRMUERQYmJu
SHNsbXd0KSlNZzxLeFREO3Bfa0xLVCYqazlsYGN+eyZEK3lLNj53TQp6SUU4RX4tTFMmMUFxWERH
U0JobEdrWndTfnB5OEgkdHVnRyQ0Umlmaj1rYSZmZjEzUWAmeXdBLWhnLUw9PDNzblgKejBmZi1u
eDtjNVRtcztSQlFnc2o7WklQKj02ZCo4JEo7ZWVhSk0kY0ZgamJ5Rl53YHNNXnlnVWYocT15VG83
K2VrCnppIX16e1Y1OF96OEw1PTB4VldLfHBrV2pzNU1pS0Y7K0BBVzxtO0ZKNXhNNiNrbGkpRkwt
fkhMeG5+V0NPbCNyUwp6JGRgLTYmTldRN3dJTVFyUilwYT07PFQ8fl9+eDdiMUxkX1pWcShXMGFl
VX5XcEU2dTIpMCM/ODg/JTJmNmVWOU4KeihWbDY9UH5VcSFrISt7ZjB3QEFSLWpmWWRlRGo9KD19
TSgzI1dBZzZubT5LdVBNI2xsaUVNYWUycDx5MSgwTkNwCnpRcmZSPz5Rb1d6end9cHM4KDsrbnFZ
OGd9X0ZHdWliMWVPWkpUbyhge0tNTUVgTyo1UFhpR1A0c1B8ZUM1aGAmKwp6KzFmZnMySUZOYlEp
PmFOMiFtMERPWG49KTwwcVdYUF5teVJOVT1GTCRQSkkoTG49dCY4ek87bl96QDlgUVJSPnEKenJZ
NEk2NmApU0w3ZXlpVk5Ab3pWPld1VThzPkkmWVZndnJfc3IlV1VBMCV5cVk0N3dNNERVVXFzRkZC
QGI9eCglCnpLbD4+X3l7PHQ0QlppPyRuVTV8JG96dUgjRjxkRnJrcVVXdV9qYk8me3opPW5yZVZe
JWxaQSotaiQ+bHlzTWMlTAp6VD9lTFEzSns+PVYmLVElX3s4RWZDYE0lcmtpemdrb19tQnNyQSMw
VjZRTkVqaWMpZ1hsdlFDKCR6OFQkJGoxQGEKekVJTmdHKj4oelhNQW9Ld1YmRW0jWTxWRm0jWDc9
QWUrQHkxVCNUQ3tONE0/QEFWQXMyJXhUVD97Xk9UWWlYdT01Cnp0PnFzI0swfmZ0QVNMRHFiXlJ0
clJqSWhDTmZWRCNmWFNiTWowcEwtIVg/S1kmIVRKPmcqWU5EaFdfRlJLaVRwRQp6Q1AqRjhqXjlM
eEJ2d0dSKjdMYzNVTy1VcUVQeilmWjMzPzdVNHJ1LVJpIWx1YDFRX0J5ZkQwJW1aTU1zMEd4VXYK
ej8/ezx8JCpMVX5GV1h3WF9xdCgzRDdjN3xKN0A1UThNNyhHaVRPN09jV21FP0kpYGJIOUNfVlFs
NHpqTEFIU3smCnpBUDhtZXhNMD5peD42eUxhfDl2YFIhWkVyZG1DY3k1dTVtVkJ9OFBAQkchfW9E
UyMlPFBBSFopQTJTIXtlS0gtMAp6V2tZVXxiQEBSO0pNfnBGUTtFfiRwNDQqOz58WVR5aUIzU1c9
O041M1kyfnp6OSFoWnhzKVdZeV5pViR8UUhnOVMKempYUjFKS3ZBNmNTVGppalZGS0NLJT5zeEJD
RmVNeXQmNz58Und+WWNDV2BVdyY+cnhPemF5ejBjd2dVMWE5bG1XCnp6T1R0M1FwZUpjWlpnSkYm
PFgmfmQpRFdOS3BNTXp4P1hyWk9wKyV3ayE8VCs2ZV5zVT9FKzE8WGM/ZCEkODBPKwp6c3xzK21C
bTRDJnMwVmRaMDBqYWcleGheJih3P2RhaEp1UzJ0ZCFzPSReOVA7Zmc/OHhAVCM8IWZTS3RHdkc9
R1oKekNvZWgyaD5Je0g0WTQwI3Mrc0lXKzw1QSQwQkxMS3UmR2ZDMEUrWER2aUZ6PEQzNTlnPktn
XnRyemxpTmRYb21tCnprZz50T0RqMShBIz9jKTZQZlhJSztxYnJmNnhJVk1pcDNDQTlVVX47eEB7
MXdzaFImfjcrN3NZUGBBXktPOVV5Qwp6d21ERzh6SktFRUQ0cWJKKWRXZjRCT0xYIWZCLVVDN0k2
YUUpLU1zbno3PztVNTsjPmQjP2xeeUI7Q29IKVNKMn0KemZLcDhidEVVamgpcEJebmRyIXQjV2A+
eitTYUBgIVExX3ljeTZwQFM1c0o8Kzk5MXdYKW19WUgzU29Yckl+Kms/CnpVPFhJNWpWVUs1RD58
aTRwcGolTGN6M3lvbTh1VT00Rnlsa2NHN2VKNlk2YU4+Z29lVD5lKjd2VktmUTwxYztwRAp6bChy
ZElZbWRyR3BzQCVeLUB8JClnWF5BdVR7a2pSJT5nTipOaFdZZlliVWVQdHdpZE5ZQ0RraEUzVTZk
PlEpcjAKekNAQiV2PF85UmNDXkBrelckJjBCd3MyLWc1M3pGeEhmS0ljUHswX2UpQW8+aylOTjt3
UzAhYUVGQkZFQFJWb21XCnpHKndpdXF7TUxIajUjblZgTEY0TkhIa1J0QztvYjcwdUAzcnlpX2pv
UkJrV25ZT0BDY2lnQ24rLUUoTTlXdkNwYgp6KHx8eUF7O3gwbEU1SWJIb2Q2WkB4cCFiRVJ0NGBC
S2BGWUpCYHV3dC0hKz94aTt1YyNLdUpjd3NuO2dhRzFTJUwKelA9JD1Le0FUWUMyQkgjeTJ3R2hi
dkxha0hgLUozbV59TUpDQSZ7d2dMU0oxS3pAdWNXPEB1Mzg5dlJ3QWk/TWsxCno3JDZzd2RFMU9S
b1lLfXE9X3MtU05ARHUwblZSaXpiPkFLPzJxb3xNJD9pPjk3K28yUnl3WWh5SzZjeV55bXY+OQp6
QTBSLSsyNmVnamh1e1FHe15gQVgrSEFuamA/cz1nV1NFUjMmWSVUYHFCOEcyPTZGdFBwR29tM3Vt
V0N7dE8tYnMKend2dyZDM2UtSWpxKEk2VGMyKXxrZXJXQChDY3ljYDNkSEpadm5mOD9kKWt6QFBN
S18hcSV+ZW9Ebm9lK0JjQ2EkCnojUHE2VVpOTHdBWkQzT3xONGpQT1IyWWlOVHNDN0tAMEB1Jmd9
OHp9MDxDfXtOc0JLQytvKyhVO3FYKmxPV2pjKgp6WjdpRWhkSCFMP1RDJkZDWUt1YihXIz9HY2Ru
VThQUnd+e2ZRNSF9REQ2NDA3a2ZBNClxMkhDMFhsUlBBPUt1dyQKeipEVH56WH0yTV8+e2AjYHhq
a2VoaTNrS0pJPiYtXm1jTipQN0xuRn0kTHdVSEI7Qz1AWmtAXmNYa0BnWl5pKCoyCnpQfHJscnhJ
O0NXMUJjXj98Ri00SChlckU3QXNtUnhUcnMxVVBhUyhRZyh3KiUoO2I2UUAtWXsrOW17VENWWHYh
QAp6IXFvTT9rSm99Si1IcVc/PT9xZipWc0hvRitxc1N8bkBYQk9EcCs3SnVKQzdiUFVXKG0xPzEh
RC04amwzNm53PF8Keio8PEpxR0NXb3FwakNuPy13cj9KY2VMZ1plcj8tUkpkKW8teTl0UFd2VEBX
YFJ9MjY5ezVTQlhqXm4xUzU/RiowCnpBOH5yN257JV9yYTdUVXpxMTN4bUBXZjFUSHx1TVU2ZVNS
JDtBMXxzPUBBQ3dHTkJrOylnUCMrJEJPV2M8SW15egp6X1NzYj5tX0V9JVA1MzhnST1RbElLNUtI
QERYR0pmZUVLUTF8NGQ8eyRnemozVDdqbnZnTTUwXkJOJnA1Vk8oPHgKenkoMlcxWiFLRUUrcSZr
R2tJUj9fLSVNV1h6Y2I8XiZUUSVDQmkkIShUWWZ1UjtzUjswYiM/cD5yVURJUFBoKFpPCnpmez1l
NytRRkIkSzJBJEBhVWB6cEF9O3dEZ1lma1FaeyRQQW9KaGV7YU1lWW1NI0VHK2ArfDNAWUA1d1RY
UG0lbwp6YDVpbl85d09UU15acjtHTWdidFAxbD5XJTVCNjsyaFY0KCNCMDtzNUZsaW85QHM2XjBl
MGxFYXs2KzZfR1I4OUUKekJDSXJxSEFxSWlQfUNUVUBjIS12VC1DWE5lO01BKzFFb0UqSEpJP0Iw
VXNMV1JHREV6elNxQmpxSWNZUSstYj5VCnoqbklNbzRUbXhpbSRgRHIwIzBlXjstKCE+YkFONihm
aWF8d3ReNTlac1A1KUxofTA5fEk1Rih0JUZiVHFyZHMmSAp6Jj9YKSg0PHZieDFgfEZzbTw2Y2VO
RyFwUl9ITj8oRXNycWJWcD5mPU1TWFAjayszJV52bW5nIWNNSU9nbSokKyMKenRXPGBQeEkkYz03
VjJSV1k5cnBFNm5zcEZPPnQlQ2RfRmFFMzdzfkAtdyhkWEJqdGdyKj42bDVfUEskdkQmMDJaCnpT
SHJ1d3JnQUBqS0lhVGhafFAjZG1HTjViSXB8eyljPCtuX3lzM1FfS2k8MkVwQUshS3pmIX4pTHN8
Pyo0c1h8dQp6K0d0bWxpdSUhTT5uKyl0b1MmVl5hWHx+dVIpK2NVQEskIWtDMGZLYk95akZWY3k4
ZCFoWU0zZHRWKlgxKmlnPUsKej9aeVpBPGc2M3Y+ejxFQyRAX1RwYnB2c2t0UFN8WXRSLUM1SElG
LW9ja3FraDlqcV9zQCFuJl41TFQ2O19SKHI4CnphajtKKykkY1cxOyF6Xj9xZ0d+NHMrRkBeeD4/
PmJnSlhqWE1lbiNIemteP24/NHFLY21XREk/Mmc8aExlMVAjZAp6UmF6diNwP3IxYyk3K2NlJV9u
RF8ka0tFTkJSKT1pMH0mJGNEUWFTZHxFT21ubXZ6cUwkPklSTiZGfCpQO3ZtfjkKejF4aSg9c2Nw
YjghaTM+dUVraEEySVFCSmY0MkB4U3MpWkI3YzIzUTd1Xj89di02VCZuZDcrJSsmWEhYX1J+YVRQ
Cnp3aUBhK2xKRjt7O1N+VXFrIU9IVDh9aSRjZWplWDZ6PGF2cGFiO0k4JEVJMitjJFh8MWt0Qnxh
YVoqd0FoVV5UXgp6WnRZPm5TSitlQDtlfUY7Yj4kcX1xYXU2YkdJPHstaiteU0p1bmE7VkxNV0Qy
WXc1QmZ2d3tyc1FteW9jUyFVWXwKekV5aC14VU1NQF82MkJ8LV5JJmxnQ0gxc1EoKDg5UjJwXmAy
MD5IazZRSllEdSFUO0hfaylJRm08a0hTTHlzaUNNCno9QX5NUkBEI25QJmlQNnVfRXFIKFBFNUQ2
R31EMXNDfkN9emleO2l8eXBKZShQb3k1THpCVk8+N0dyNDxPREtpXwp6Z0JNSy1TRXw/WFFlNUtF
KGZ8KD9fY0d1cldVODs5RWBxTnllc3sxb2p0NEw/ai0rXl5CUzxtaUJFSGtWZmk7OE0Kekk1KnFG
JUM9YzcmOXV7UTE3Y041PldEbDxjdUZvQW05QF9uaWxIWStHbX5eO0B+YytCc2E3OURwWndufCNO
eHEyCnpMMVEqbTNPclVDO0Y8QztMb09uMSV4SHJQKlUpIXZWKClITDBtM2tKZlVEfmp5KyYlKkFQ
fUp8Tkt3PzdlO2VNOwp6b3c9Uk40X2k0aSk2SG91b2c1ISM+OWlAYjFnSzNPRzRFN35RQyMpa0hF
VTczRishNVI3bERjQExxMXwjUkE2bC0KeiZrTDB0SkU5VH1QYmh9MG5PXjM7Tj5yNktGaCY2dUZK
ND5gQkwkIylOLXBhKVAqVmhwJnsxezl3cDBxTkU5ZCM/CnpASyhCUCRlZElRXkhReEc3aTU/anEt
aSQrODNfblBGeDdBX1FjcWJ1MXNebHlCS0VpbnlQX2dIO31XfiNHUSZRPwp6WHxsSTU2b1goVnY3
aElwcEA0e3khdCYrSSVlNWEwcXh9aWgmWVJvJl98Vnxjc1VxVE8mP00wLUF1IXI9RnZnRkQKelpP
UFdGV1BWUm89WEZ6Y3w5I2FlajU+cj51aXJ9STVaWXdsP3RZZUg4c2ImZWJhcig7d1JQTChXZ19B
TDJ9bUA8CnoxVlB+RCZGJFJ8b0p3UTYwUzg0UGFuPlg7PCQ+KH5hOCE+SGRuRj4/QDl6WWBoPiNJ
T1pHRVloRE52WitxRUFxTwp6QWgwYHZBYUVvRCt9RVo2PEdsMGZGI1d0Pi1sailGPDM4T2R6PTtA
TlhxcV5KTX0oa1g0aXlhUEYhUCpxNHlwPlUKeiYmKEB5dzZ7Tk10VSo7OVZSM0N6SW9LTmNrJSsy
X3Y0KDdXK3dhSHoreUphJWw/UGFgWHUqVDJSMW1BYClhK0RqCnpHRmhtcSs4fnZSN2NYQTtLPVB3
Uj0zX14/c0gmWWVYYTRVODFfbjx2WDhKbVVPJUF8JHVlUTZwYF5sfV9IIVpJXgp6YDNuMEIqb3NL
cChiNGZVWVlvdF9FMHw0UUohLTk/dEUyc0FScXViKSFqRHd8NTN1QjwjczQ9PGh0N0x2JDM4KSUK
emA4OXBOeW12TkNoaT5zbmkrP20kKV5PbVM4eHNWOXBFSVpUU04qJHBVc3lGMk9AQ2x8PDVibm1v
SF9IWj9LYCU8CnpISThHJDd6RyRWJDRlWj9eIUUxdFo4ezkpTlFlZkhjRHo+ISElKmZnU254TS05
SypPbEtUKWA2UkZ3dHU3djleeQp6eVo8fmZgX0NDb3JXSD1UK0dDRUhgUCs/flV3bWA1MythQm8t
OSVvI2g9QFA9bCUtJEhXSE5aP3NaSiRSU0lGS3gKelVkeTUwY2B9KWRvX3kqX1UjdzImMk1xWF5P
WlpyMGo1fjRoKHdueiMtRkJfMiMhUkV5ZmhHWE5BYDxrQG58dCV4CnpiPGJidHl8K3hUK1dUXkd6
VzNnbiZ3VGJqZjQ7TWBiRGo0LXBjeGlVQyVwR1E9PE11Vl92ejJ4X3l6QyVldmFRKgp6VVFQa0Rr
M1BCWHk2YzlQRW5qfGhUVSlrViVeJk1qK3FMSExOKGJ0a0JpcShtS0k2PH5BRys/a3RBX2dNZClh
NVAKenlpKDVKMGBBOyUmaSYpKCl+PnkhUjRoNFRqNSZuQVljZSZjX3Vna1I4R0Yqd0NEK3tsO1Fp
bUhEI01yaWdJN3hSCnpJdnt4UDtSbjhkIXRvMH5tcmlHX19rSnt1KnJjSVFANFppX0dqYEYhPDNJ
bzRMbDFuUCNCViFqbURpejs8aUhwYwp6cEstPDtLRCUrX2hRQlRyaSYkZnZIcDliKUspXlpnWjY9
ZHA7bGYzcWY4dlFwfEdNaDgjZlJ7Pmhsfnt3d18/VGwKeipRe047X1MrKlBCV1YkZE1XaClXT2Qq
UUs+TlV0X3YqamdBbVIkRzExSFprY3h8KH1QXl97T353YT0rKWFSMkBICnotTGhpRSolJFRuXmdK
aEcwYEkqWj5kQmZNUi1FQDwxcnlBZUcyezZhRTYlOz57YD5Fe01POXpYPzJxTnVGODlXTwp6ejVW
dnZAQjdRWXtQWGpBZCpeKy1DRFM2X3RKUzJscVhVe3JxZSpre2ZoND08KXZJbUV2YEJDN3lsPnhk
ISskeU4Kel9TPGl9azdVayZNWUJKYSpYcXEleiFfdEI+cyNOeGFfI2ZhLVooZm95c31hJENsN0At
NT8zRHdVTW83U3FPYXFXCnpNKypuc3FwSkFUZCNgfkFna2hTX3U4dzxfRUlEYl91WVl+I1U1UV9R
YUJ1KFJjczxnbmJ3UDFxbkJ3ZlMmd0pPXwp6JjZ9PHQmZ0N3eVI0UyZMSCRYJWpBfWFlVUxzSlZU
clomIzI8JXVlXz5NVXo1VkhqI2hYVTh3KyY3MSF9QUEwQ18KekthSFhZNjJaVWIkbjA8a1YpTyFu
UktVZC1VQWxiWiMmdVQ/NGkzR2VSNFNid01YYDB4cTNXdyFsYmFGYiFBVWx5CnpoIzBLM3EqOCYp
V1lTTXtiIz91MCFRdz9mez8pKFZAbntye1RLVSZCPmkwan07YlQ4ZFI4QEtSeVJTTlYpMjgrMwp6
PFp9NzUlSGA1WWFVMzElb1MpJm5aJmh1c0VzUkJrKmNlbD0qNmE7fSlYc0R8XklTKHFgeT16YEZN
NFJybnR5cyQKekx+MHt2KWJidmReQiNeajhIY0dKcWlRT1duNk1+eyYzQ0BEQ2M5PEpANiFWVm0x
WWlNNEJnJEs+K019JHtAQk9mCnpKclY/Z191aD9mPGA1KT5vSHJpVUhKUW5yaSkoWCFFejxCYjdu
QlpfKzh9fmBSJmBTNSZVIW16UDNQfj5zR0Zubwpae3tpPUlkQEheXktxdnFKMDAyb3ZQREhMa1Yx
bUVCMihiVkYKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNs
aXBzZS1tYXJrLTI1Ni5wbmcgYi9hcHAvcmVzL2VjbGlwc2UtbWFyay0yNTYucG5nCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAuLmExMzVjNTRlMTQ5ZWFhOTBiNjEwYTY5YzhmOWJmNmRlYjA2YzBlNjcKR0lUIGJpbmFyeSBw
YXRjaApsaXRlcmFsIDE1ODI1CnpjbVg5X1dtc0VIKCs9KHFNVEAoO3lGPjkoK0AqTU40VWl4JDQj
bkxJNmZmQFgjaTYqbnlJYzczeXgqVEJDKWJ8Ywp6Kl9uSDBYR2JENSlEJHBLTmwqYSowRVV2SHRR
RyhPMU57akRLdF9hcThNKiFiM0lLP3VEYWxHe2AoJk1VXyt9WF4Kel8/RW5EJmsxPi03YEl1Q3Eh
NWxvd1hZMkdCZCFwd0lQI21GNjRmRSNCNjVkMTtpbW47QWQmJWRDYVFudnJHQEVACnpxZWJUbGxe
bnlSPFQ4c1ViY3wtSlBHQjJwVj1abUNeTHViRlRpPjhLU1QqX2V0I2EtNzlDJmhkVXtKWnpXYXVy
bAp6O29OYUlafEVFfXZ+JVNuTioqX35WQExIKk1JeSpmOXd2TlBNRk1NKk90dXVxbS1oX2VBM2g+
dzk8fiUrdUhGdXgKelB7dzEoNGNRbW8haUQ3VUBJM3I3bCZiMCRkJSRzVjx+Sj5ZNGdXZ29DK3lZ
NzN1JlV6ZTx5ZD8hO1ZYfWJad3B8CnpeTTZkTFBpekB5SlV7MV9TRmlCSVNVSmt+UEUxKkk2RTkz
cDw1Y1JgNihqIVpSVXNPMzZeJm96OCk7enRaeXJ1MAp6NEQkKE9EY09IJUlQM2k5MHpwKTwrbD8w
aUN4JlI+LXNqZkp6MFFeY2x2fWpMc3wtcTYlWExeaj9KJUMjeH5AODkKeipHRE9hRD44PHN4OUQh
Q1MyOEJhbGAxazM1TFpVaEJPfkB3a2AzP2tiaEpwWCV1REJBelY/MWMlVzF4eGk0eTRBCnpWez1+
bTclRFh+PXloN25gM29tbCVVJig1JDU4O19pNj5CKysyU2pFdEwlYH5ASDgyQ1R+e3RwMGxLQW8z
d1MlZwp6I0tPIXJGNGZqbXhicComNEpgQHwzaVUrRCRqV35NQVA9d2QqaVVMbz1GOCpmQ3l9KCs2
LV50TTJaSmUqayRLV0IKeiNCKjJ2UDB1fVBPdCRCRW1RKUp1UkgrQnZDdVlgajV4Q095e0JBK24t
S1MrdllhbT44PE8yXlhVSTNERzFXJVVWCno1NSsrQl9vWEVROW1VUUVJaUhqVnckdFlmKnpufFY8
XyhOP1ZzcigrRCtoa19TMkp0dSlSe2N9TVlVYC1mclZVdgp6IXdhNCN1fHppfk4qTWltOyZnVHZI
KWhFRDkqZF9neEhTWk5AJj51Kl4welhvUU1SMSgqNn1qJXQ7a09NKVVpc2sKenJ8ITd0TFJOe3It
O1FIWHlkNzV7S2VvMkVffnpgdCRaM1l3dkUjSTlzV0l7S0VBZ3pEQiRsKWdJaVJjMmF2P2JKCnpu
aUtzVC0jPEooXzRrPEdyanJuVUZLQnB3RS1gKGI0Sihfby0/NzF7OCQ8cFlyOGtJVERxREwyVHpJ
S2t7Uyl9cwp6X1ZSR3JRZnRJflZCZiYzYnAyKENpe3sxQTdtX25DdVNrUHshKTN0NG96RDduRllW
TTVqTD8raGMwSUUzYz5WdEgKekFmY2w/SCM7OypMWChDOFlhZ2wqdURFYVB7UWg+cnw4NE9XKGtU
WEhYSEZnTWNOTnZTXzR9R3pIc21mam1AYjc0Cnp6bCg8T2ZpPjtuQnZHZ0dgSzIwa0xoPTVFWCR+
MWh6VW5SQWYqIS1uRGtwZEg7SGlVaiF8bHk3UDdJPlo9NngzRQp6VEJfWUUjR3VTbExQV1JANm1e
ZT93K28mKFhsUThRYV8pSjNuYV4/XmUxQVJ3Sj8ocTU+fllpNWI2UTY5cnNKansKeldedyZjNHx2
QG5kXzUtZ2hRd3ZCRz98SlN2MkpKS1JXQHVZME0qXk12Zk9QZUolSz14czhuYEgrJFdCZit1N1d3
CnpvNV4+Mlc5NilQK2Y3XjI/JjA0WSlXKiZ9Y1BBM0J4M2xWUlM1d18pUkkhJVIxfGtWaEBrNnJ9
ZihJMy0hNVdeUAp6LWR9V2J7Izx8QmNwUW0/UjRBMGZlNUU4MiVzfU1pSl9nK2VQO3tRXmRQOXlt
eXc0WVh5XjZHPz81dlp1QX0oITIKeip8eDcjWGlCJGJgeT1yWkNsQj1OZVdwVlFQMkh9LS1kfip8
JE5VYSktKntjPihZcGFVdmMwNHhGRillRzF6T0F3CnpBdzQ2eCU/cChgK2BJZCRtczN2JiswXnFK
dWRVc0VSdWtKKD98U1JJZlRVfE5RX3FjZ05DWHZmUDBvWWdvK2Qkbwp6VzYyeUh1ZlJDKitlNGZD
KTF5JW8hT0RpN3NFeWZIIz54aVEmRkFONVpZK3UwT1BlYWNrLWVyPndeMjQwI2VSdmkKej1kNXA2
I05GJCEpOU5OM0MhcDdaZyhsfDxGfV9HQGlEUkpYM3Z9STc2clFnbUdqeWNZSzZma3x0flozPUl0
a08pCno3MHJhQGVtOEtQaSNkWjlKUmpFR0ZMYj54bWlaPGxedyFjJmZUQjQ4RjU0QTQlZEMzIUV8
YmVxXlBNaiY/fml2Tgp6X2p4ciNIOFd2IU50bk96TEJKSyNqYU82aCpLcyh8JUVrc15aPD1pRyZg
dnImUEVCfVBqXz1LfU98e3MyITI1eTcKeiMmYnJAai01VkxubXdFYjdgMU98JkYyaWAwKDElUzFj
YEJTZzY5cUpaRjRzdGRAeG0oY1k3bjtUZyUlRkN4am09CnpCcD8lNW9lI1IyX15LQF5EJUpeN0Z3
NXxSOVk9UXlVQ3dLN0MhTUBneCMxS1hmcEdfVU4ofXxjXldYQTc7SU1oSQp6KkhpJSRWQmJwIXJB
emRNbm4lQSU1c2E7NmJpZklRYktwV042OFpCPFBmJWI8T3dLVz1aXnc/Vm88RX19MjxCbikKej9G
OTE3Q2VWSWxKVi1SayRfb2hUP0w1ZjcyeigyOXNDPkVaP2dxfitLZCQrYVBzU0o0JiliYHNOc19s
LV5sKV9qCnpIdiYjc1JlI19WaHFQTiZWQ0AkU2FDWWNoPiphIz9gcHE0cnZyfm9TOShWOzV7VHdv
NUZ1VHlpOzY5b0M7UXYrfQp6N2pQYHl6MjJ7P1BfYVFuUD5RJX0/N2h9LStTUFItKTN5NUNpJmll
elp9VEZTVzAjai1ZMFZQNV5xUzVBSWtNSUAKel9NR0Y3e3Awd2syeFlqa1klaHpjK21tOzA7Qnsk
dnA8dTFELTQ1RWJTazkzbzYqV0lIdGI0QiMhfFUjV191RG13CnotT3tDYkg5RENSYT13YiREbkBu
Tko8WClWYHxJNEBAMHszSWxVTVN8VFN+Xzc1ZTJPUVRUZzcmb20mfFc1KkU+fQp6V0lkOUImNF90
MDU3U3RJa0ZfeXomZDtfaitIUThmKWxoK2N0KUZreldeUmNnNiRtKDBoZGlwWUJkbl4xbUcxU3EK
eiN0eW1+V14pS1YxZEV2WkspJjw5eVZBeDhpSUdvRU9YN35SbmJ2R2l3PUp4X1hjaGdfKmJ4YzRi
X25pIUVjdD5CCnplfndXZGMmNlplelV1amR6QH1rLTVENVooTDU4VSkrdWR0bkJITn5ZaT84fTY5
QSN8QyQmb1pVNy0+OHxjQTNOXwp6N3QrciNGTWp1TG1WI0I2UypeJCtrVVp8LWtjIXFKV0tWZk8+
fjhuLWBgS3JUbXchPTtJJmhkdXZ0ZVk3UUhxWkAKemg5S1hZJjJCU3NHMDFUQjE1bEpGTGAhKURg
VjZfeC1TRGFsQ3YlZXBGLW4qTFVROXZuIz9GZzFsQEgwVF96VzBnCnp1YV81QlY/P09kK2wqYyFq
ZHp7TFladnx4QypUV0w8aDQqdGVwcC1IPm9KTUAlUiZtSzReZlo5OCQwUEFaN1lsUAp6JGlCWFgj
UURxMHkzdXxQM1cqJVU4VVhCbTZvOCFIMGxuX0JGQV9vP3tUcChKY3Rra29nJStBaEY2MXUhWiR6
cVMKelJCXzEwdSpqb2ZjOygrdWkoQGp5SEpEUmg1MX50USpVeEopQztNemlGbzt1OT50b0txVi01
bSV5STxDeWEmKnllCnpBOTYxJEBjdVc5S2V8cnNgUT4/YF5DSjdnN2E7PE1PaylHZDV9K25LVz1Z
RTUtZSR5SjdAYWQrSHpyQ3grMFImTAp6Kyt5X2c/RllzTVp1fXQzdWFgWVpzRjBzYmIwTSE4b3lL
anw7WDZjb3IyYW1sYitgel52NmxDej5qNDkle2BYTk8KenVHcEkwRnNVI05eUSllZFZnZjEzZCN1
WChTNmZ7fUpjZ1EjKX11dms9ZG89VWZyVF5Bbnl4UWN1PUlRWW40KWZkCnpobjBtS1UmelZ2OXJG
bXpuKXYmeyl0RjlfXnFmNmtxd350V3UrMTRebDIoIVNDPzJaISU7bn4rOXBjczcxP1lXdwp6WWIq
YkFIWGd7TGRXaCNgZFAwYnBvWlJGbE5hRDVJZk4xVkk2ZjVWSFIzSV8qVTB0bF4+RGEhZ0VKPGZK
UCVWOUUKek42ME5ucl9yRll0UiFka204NkpJO05xWUxqfDNkZm1+Ymk0V3dWZztYLTgxNDQtX31W
diFiYjckezR2PT1sKVBNCnp1fW42aXlkTF9USnB+WWRKNXB4PnxJaCEzPktvdW09I2AqPUsraC1t
diNkZzFCaGowditfIUNKcVBiZ2Z0Z09Sewp6T3leRjA3fTRrOUs5MTRfYCtWaFA+PSkkam9wZSZo
cU5NV3E8OC04WHV9ZlUmJn4rOTV2TTNhRXhWTl9oY31ANlAKejU2Km4zKChvSk0maz4pVmgpbHZH
VnROdGVhbE9ZQ0hnZ0lKZE5la0Mqam93azY/STF+TkB8P3Y3VWNCdEF7IylVCnpBQXdWMEs2TTdZ
dFZFUzFBS1Rsb0p6aGZMPC1xOGBtYU9ifipWSzdlYDhgcTBtSUJWIT5jI25lYXolSHAoMnJGNwp6
Mj9gamNCJn5taTIxQ15zazlTSCg4eEpAKXZkTGk3Sm08LSgjNm1fYiM9WlYoZlJDczwjJjwzRE5R
O2dfPzspbWMKemp4QEBJKy03X3xzVEx6NF9FXl44ZDt5WiVGO1I+PDNXc05FU1pYRXktJlk0eHVk
bWA9bVNlZCZgcTcoP1ItTyQ7CnohdDhjT2JyJi05K3lGdkVzdkBsO3E2N2J7NElAZFdXVzY+bSUz
IT02e1V+PSNobVo0ZzQ5Y1gxKH1RYCooc3R2cgp6NGFVXkw7aFJ9OVMpVnsqYSkzZlUxQllsWCM+
IzFCVXopVCVKc1lNfT1Gd25FJUdtN3lvdHR9cDBEQHdOMzZfY2YKemBTKHc8e2tuaCZZMjJRMnRF
THA+M0U9YGs+YyRWMj11JClwPDltbjQ9ZngjJGlCKG5YIXBrQ3U9WkFUUGxgKyFkCno+VzF0Sns5
YHsrZGkkfHdIakx3RjNLJEVGRHooYVZoP3JBfG1AIz1vampVWDNlK0M3Pyt9fm5wUk8qeH1hR0Nv
RQp6RHR6KlpNTzA+QHF0LTUpRTdCQz5SeFkpb0NCajJmeGooWXJWTGJsOGthc0JwdSEre1pfYC19
YU82UGojbXhMXmkKekVROShUbVZ3TSZiVHBOSHVpMUszRm1RPmhCQ1FMSSY7cENiPExrI1FiUGFw
d21pfTktJGVAeTJnU249fSRTVGpeCnpTR0E1Y1hXM2BHUGFwSEUyPFh2QVowYkROXjtIeXhsJnBB
JlMlWi1VNDtWanVUREA2JFgrRnNUQktMNy1vQTZmUQp6Z0Y0MUFsVy1YcDE8enNLQjwoSH5xSXRq
YHtXaGJ8Y1QwPVE+Xj1GZnNHSElHKmgleDAodkVDJWVqaGNicnE/SHEKejc7PVY+Y1hadDVCZyp5
YXU2PChkRjBBdyRDRyplQ24mSUV6KDhiJTVSWWUtejVBRiNVbns1fn0hPTlKNCRnQipsCnopQTl7
c1RJKnlkYTdEdFIkdkRlI28yRH1+TlR1PTJxS2g+Y3IpSzk9KXg4REs0a2l5NF9lUG9LJUYqWms/
JFNvZAp6bzdXSDhYM0h9JF5UOWhLQGBPPCR5T01jVm58NnQjQzZTT2diREcyZERReXl7cFlWRVE+
S0BCV2w0ZU5gPz0lYEAKek4/VFlPSyhOVWt8MT5FWTZ7VGp9Y097MFZoaSEhdFg/O2xnIXpSfmU9
LXozeV45fHZBPHEwPEt7PjtxeW94TzJrCnpeamAlK08mKl9aOz1+QG9HNyZscSV1ZUY+ODJKMmZ2
akg1MWwpdjQ4dyYobEozT0YoWUIqcjQtVjZhd1kjdnxnJAp6NFE5UjR3P1M7JTgyT092aCgyT1R4
K2spZz42SH55d09jUj4yNHlzTE9rI0tEIT9ZWXJqRnZ7fUxoMWE4aHF1Uk4KeiFtUWQzMFl+ZjQp
TkVKJkFANH5CLU85ZEx2Q0hBdns8aXgrekxWX1ZSLVZ6Sns/SzJzSHhadklRQ1RhUkRVIXM8CnpL
aUtlZ3k7V1RGMDItPjctLWA/ZD1KTjdQbHRmJlNCUlgoZCRQSSE4XjFSbnxgNiRRQFJGKCtgTEYo
az5WKHxTZgp6b1k0Zyt5NFVvKTtEbTQtcyQySiMhak5lYW9QNTNWJWBEM351RikzMXZuYiFRREFW
MnlPUCF5a15BVX09MT59WmQKenEob209JXB8JUYxNSRGJmVSNCMrb1VET0ckTytNWmk3UTdrTTF3
YlJpeD90JFh8UHdyJjBTbXk5flcoVkJRIz07Cnp3Rnp1X15TUGAtZW9oaDkmbWJBYS1qWG98aGxn
cXNrKztNQWwxUnlWNmQ4SFdLTiNqUnUjX1dXTyt+NVNGMkt7aAp6KiZuVW1QOWApT2V3OVlAYV5P
Z0FCYlU2eHBxZUFXeDtAKSRUZ2xsREd0OU5QKFZ6Jlk7ZWAyNERPPm1fVmRCWmsKej51aWxBZjwm
PHBqP14tVm5sI2koUldYbEdYfFRgS19PbyhFQ3QqX1EhVT4rKi1vcFooJWtGLTxMRytBWlhwbk14
CnpKRXFUX3s9cnBqeHlpXyRPfEFsRTxsb3tGVnhOOFM8eHgqPHZZV2EhIT4xdmVnYDMxbV8wTUhy
cmItVjlQI01eWAp6dytAQ0c8flpSUHErM2kxM3khVCtlIyNAanszWSM0YS0rbX1reXxaUHcxa0ts
UnBKNzRhfDFDaUlgOzN7QTFtRFIKejNgIW1zPCZQJkZpXnxDaGdEQ0ZBaGY/eyl5UiRfYSY3NCZE
JEVJPmRjNUZqJC0zPUtyY3grYDZeMHtfSHE2TEJyCnohdig7RlZDdGk0eSRJPzh6d0ZkKDR7aSNk
R3RjKFotbCNtQ2xFPzFDZjROSzJLLVMkNUBjWmY9RWE8S08/YlVJbQp6RT9uP2gzZWdFJj9XP0pl
MU9hYX1XaTN+SDFDOUpvRXxAQGomSkd7QXc2RD14e20zJFZ4RnhyJnlFNF9qQUQjVU4KeiR8O2VW
Qjx8dG9SM3tUaz1oOVFoWnhwUXNLPStGc3tzJjcjSFM9MS1SKz9hZm88PVl0Ml9GTG4mMlI/VEth
RmxgCnpGdGVMPzMmU2tLSHV8fm1qPk1fcEBnbWh8O0g5YzlDfShkLTE5K0BvN1UkSDlmaipsISR3
TEoxZTtuV1RHPXVsUgp6cWdWTThpXm1xdiUrUkI+IVc8cTclNSZCeU4/SG1sNFBfdXJubmdRfDNZ
LUN4cXdzTjskQ0MwbE5WYjQwPGRiUlMKejhITHFqVl9TYChIP0ZPIUU+SntiPHNMbSgmbHs8MD9H
ODRiUXBTKXpqOXtVNW48N2VDS3A/cjAjRk8raHZiJllhCnpybTdrMDYoWipWeXo9TEk5M2Q5fT1M
RnFyaChLcUElTjRCaGkyemxjTGAwPnctNlNGN084OSU9eVZMOTNrQyV2bgp6PjcwPzBVZ3U2Qk5Q
S310e3sqKS0lViVWcy1NJExiPj5PJCtWS31KWVhDZmc2JCNvKEpIeGt0eUBvMSpMMWIxODEKemVO
QWd7RF8rfnQxI0tONk5NNm5kMGJNUTBLeU9EWCFtbElEdnE+V3pyTjZrPzcjQUc9UlRoYVEtbjBa
VW5Nb2pTCnp2Y089ZmFBV2RHTCRyIXxNUmFtVVl9VEtGOUBZQSlQYV84fFNrQUpfKSsrU0JYb2ZG
aVJJelVJVXFEaXpOQFlYKAp6eFNLNXFSbFlWWjJEOzl0ZFRZMWM7SGVBQVJnUmExJVV3aURBRk0/
UlJPfXVgeGREQT83WFBqN14yYWBiRWBxa2EKenNPYDc3LXJ8RWw2QTl5QVliTElTOV5TSUxSeGJe
dTMrPlEmIzgpTCROYSZtZnswTDRHPTVWYEJPWW1GKVp8Qn5xCnpuKzt0UXdDTlhFMUQrfTBeJiQ2
ajMrX3YjQ0pMJm9TMEI1KzZNOSp8c1QkSWM9R2NHVmMpMyU1Smh+eGV2YnhUQAp6RVFIfGFmdDhK
aGdjWUU0LWU8R2laJUpOK09+UjFUMmhFYE9eRyFJT1kma2dsdSN8TGU/YGIwPHhwZXUkQTVyeEYK
eiRjVXh2K3dUY25jUlJySEhHOXhtdUtSOVBieH1SVEIkTk1wZy1EbFVtVkJSNm9XbilZMlRsK2p3
JipDJS1sKWNtCno4MXlkVVk7I3Bhc0l9QXk9ZTwjPSpySDVFKUVhe1JhSkR7eShlKjRvTnF9VEt4
Z1V7QF47OGxmWih7Yl9xPStWdwp6aEk3emFLd1BtTWhLeVJDPkE4VHArU3M0V3dCX3BJdT0mdTQq
fDJmQDlFY3VhVk5yTzUkLVA9Kmk2I0khZXNRYyQKenY3Tk4pY3F+YUQ5UT9pSV94KVphUl4hRGxE
NVIoOU1JMWdGeCtCa1RnOFE8TnQ/fkVvX2heJigqUVh5PUpLYHY3Cno9eWF3JmV0b3BRYUJ0c0Et
Nig5KkRQfGs/eHVUIztYbV5+XnJFOzVac3VNd201PHdkQGYyOzdOJUczYFFeZFJFUQp6Jn4mZC1I
cldBd0lWJWp1dmp7eWBOb24pYHdsXnBlQzwpUm9HP1VJZiU3dUUqNn1zV3MqPzthQFoxOX17Tksk
I2MKejBlOD8lKUYhK0tvTW9jUz1TVnE/SGZxMGA1cUthSGxQYDlKa2Jkaj5aYWp6VCVLOyZsaU43
VCFzP3otPGo9UlhRCno0IzFTbSEtdnoxVklnRWN4VHgrN1RLI1Q9Y1h6SWc4O0Y/fDlMejZqTzB2
ITc0Rk5rUFEjJUNfek47anJmaTBWTAp6ZExuTj1hSDZhTz9uNSpxXjk4cG5zLUZEIUF7UzwjVypZ
djV7aXh+ayNqcDc9OVZ5QjVxY0Q3PDw3OHQ9dXNRUmQKemElYUBmMV9reElYUktEb0BvWjR5Q1dh
WXF5X1VBKSp0SW0wWH4hVn0+bzZmPipQbzktc08lYmsqa1ZsSkYhdXAzCnorTEE/QEJ0OE1ANCti
UGdISSM5ZCh4QzYmen5GNUhWUG9AYWBjejxRMWZgdUd1Y0omUk8yeUVLUGJ2Q2V5I1ByKwp6eTNI
eiFMXjJPPDsjUzktYXtaRFQ5VmN2Rlk/emRwPnxIfnJsfWYwPj5jX3JHWntTXkcrcVA+ZUdid0JL
PWpNN2QKenJMdXtuPGw3P0BEdW1FRXVvO2BqUWl5ZT5YSHY5QWBLSmpMR19LP3ZES04+PW0wOHFO
fEk0cSZRTX4jTD9tJGttCnpfK3pzM2spZGtLeE9+RUBTP0FOc0xTazA/MzdKMExySTgmTll5RSt6
TFVGbHRrWUAhYTtqRGp4MFlUdyVDMX1Wagp6c2VvdWYkWSExVG9BYDt2QGpTT002T3FzcFpYckhK
O0FXflEmI0huVWY4MVVFZHNiZE5LQzElWGEkUVMmcElTIWQKem81UHw0Zk43LU5iVH1PPkFAWUZS
K1EtVjVTdyZTc3NMVUVXITh5OVhGVl9FJTxEMW5PUDU1cGshejNwYmAmLVZfCnpsbWFYTyM7TW9C
RkJHTl9LOWUoUXcteEhzV0R+O1RBbjVXYDhhLXp+eXVWQ1cydmpgOyZXOy09NzJ3WHpLNzs0Xgp6
VlZuVzlSQnRaJFMySj4+UGtvNyMjZF82cjQ5bEB1MzIybklfXz08TVlGPGZVQk5eUWNrYlRBJjxz
TjEyIWh5UkIKemo2OXNAQ0lxVG5AdFhtd1dGPWY2UDA2NyZZWUxSQ2huJHNSP182TShIMnVsSyVZ
b3BDSGYxc1M1U3VaQClIUGRBCnp5JDw/KCszUUZLVEM+Pn1IPUBJclhlfUNzWkIlSl87YEBKcHtV
SjVMc1ktRHhVT2R6PypCRmg9XyU0QzloQ3NrdQp6cVgmR1JydUtIKT1lR1R1b0gtbEtTZWpkK0Q+
eStVQy1kUDJldT1UZEhzQTxDO0NQcTUyQlhFdj8qWXc+KTlmUH4Kems2WEpEPCErb3BUQENNOHRR
PEc7Q15za2NgUHUwJXM9JU5NRT5TKy0/JGxnODEpfFctUyhVbmN7NGI8OWgmX3JQCnozbzV5bkxB
PEw4SU4rYUZaKClWUHNqTWJGY1NEdU1Mfn5Rb2tyWVpeaUY9O2l8MUg9IUxySUpgbVR1V0JoTk5K
Kgp6VjgjfWtoeDY4ZSYxTUhjM0QoU2JzMW5idDtOTk13aHtic3klb200VDlWd3VNT29jJklCZEpS
PFQtZnd4cnhPc1QKel56TU82MzZ7UTMzNkBMKWNVRFVybUdeaUYpJipIOGszJUtvKShVcHYoSEMz
YHt7KFVEYFIhVz5mPkwrXjRBU3pYCno+dmhqNih2PnlyKi1SK04hUW5zV1U8e1JJVWJfelgmN3Z2
WkdQNEk4JT99SnQrYGtGSURJVU1rbkFCYnB2RnExbwp6UyFrPVhLIX1MOXZJU0E0eCp1e2poVFVj
MGNLem99S2JkNzBvXlBqPVZMQSVJVmRGTXxQRWJtNGtMeHE0c1VXPUEKelA7fT8lPzdmUyYhQm9E
Yi0/RGBTR3NZU20tK2FxbzFFWFJqP1MkNj5LZSs4Qj5AWF5Mc3ViPlgxZjxVa3dmM1MqCnpFTTF7
dkopRl4hSnw9QUZOYWNxUTtEfiUkPFBEMkBUbXYmRGpOTjRJd2VCJVlYQXtyJUQ5QlU1REgkR3Qw
dzU/Qgp6cX4tPWtZfVd2M3REVz5mVCFvbUZtUjE0ez8tYVR4ZWlQNUp0QUU9KnlPYiFET2ZMayh3
JlUmdFFofCtjTGEtWmEKek8/dykmQSl5Wk9sTzElLUZhJnU/I3JSKSotPndxe1lkU0o1QE1EVm9O
TTdFdTN3YVdFYlZWQWM0OVZ7K0l9UHY7CnokWjhydz18aEViYTR3VTx6ZlBXIWk3bEo9KTlffjlj
TCQ/aVkwYk0zc2NvSyk/cnBIK1F+bnxYMmw0ZExjIXZQWgp6NShkMmhlMnUxKm9mWTkwdnp+LV9S
U0FxTTJMN1hBK3JJZzBQVlkwbkFXQ0VkZGkyfDkxfGdAI2hXPipNVHR1Xl4KelZuPDdNIX1lZj1D
NFdEYy1OaCsyN2clNHMlU15HQUM0RDl3YGBPI2BpKiZMdUd2Z2E/YmJDSyZQKkhBfXZ+TXA7CnpD
d2tDPjF7N1FNakBEfXwoeklQTSEyNSlCQSVyYz4+USRXRVVxNT9gMnYqKnw4QCljdTVePzdHTGR3
dHZGezZFQQp6MEJkc1VtQWdLaVNOXjgjZSU+fHhSSCZoTXZoUmE+KzBFTWwhPCFNOUNFPzc0Iy1z
RW9ROU1tUzlzSEIqcy1afTwKenxNTEtoYm4tWCE+dn49X3F1RlpNdnY7ZEpkVk1yKU0pc18ocS1j
SjAxPHpwS1IlaWRsZDZic3V0c1kyclFofjVnCnoqV0gzbDJHWEFvbWl3MVYobnZuYnN1VkUmKUU/
aTdDb2MzPSNzPzJ3d15MbzZyfjJVOVQjb1IyYzM/NkJuSFQ+ZAp6PTdBVVdRfSROYHQxMSYpPm52
TCN5IXs7VHZeS0QhVD1odU4+MjJSRyhrPH1TOTZ5XzRzWDc0K245QW5lPFFISXQKemAjNk9MWSp2
e2l3SUpuNTFeNWIlPG04ZXBKQUVLNVBRTzQmcDFOR0UmRlN9amNHUmRwI1NZPl5jcDh6XlZ+UHE+
Cnp2YWkoQWQzLUI+PC1GJHEhWV94dD1WKWRyeH1fYkdvI0FePlZoREpgbis7NVZmWTE4MzlAQWp5
NEg7MntvdWFaegp6K0UxVU1CcHxpQ1dPKHgldzlJX3UtNzRrLVBzOFRAIzlMfG0tNjl4SlFARXx9
MXdhaiZhVipEPTdAfGNIQlBYaH0KejVMS1c3ISVmI0Mwd05idHFIMjlwYzJXRFFZUis+NWZoc1N+
O0wycCZkZFpgYjE4a2gwPjJARyYjeXBeMmRFeXB8CnpKU2pEI2t4b2NRZjl+bUhOSmgrKDJ+KHEk
c24yOWtKbEEqMmFycyNpZmFHYXRRNDdEQGE8cyFNT3JjNGhoVjErZAp6I2dgc2tmWng0NWxXZkw9
VXxLT0I7Q3J2SzElU0ErIyZRJXl7QU5IU3lHO35yRkFqVURxUjM7NHJ8SkwqIzxtfmQKekhpOGtU
SnAjMnFsND9xPTJfWVVnNnN6OSlWQ01kRVQyK3lWSXg0aW8kYTgmRVA9YDlnUTMrU3U2bVF4RF5G
bmBKCnp2cGtUJFpEWHl0SH1oVnxLe3JOOGB9UVVoOyE+WGp0bVplUHt1THZZVkFwLTk/azhIdllh
cWB7cXE+Qno5ZT98WAp6Ui1aMzJNbjVEKiRKZSM5MDtaeD0wKEMxXjxpaHlTbzFmNDNIOUNIdGBx
aXk0b3N4ND5rXm51VUstWVEpdnw8IWYKeko5Y2JQaiErVWAhdHdkbEZVVzI/fEFRcW1nKn4qQmc4
bXo3I2wtbSFtODleNj0hIXVJPzdeaExCeUhedkpIPi1DCnpFK1dXVjJfcUA5TkhYK0BOQ3x2Xikw
UHhXME5BY1czSEQpfVl1NnB2VyRUZTBeY2MkeWsrSXgpaWQoT1ZkbkFwVQp6UkBPdzhXKnpZYCF8
WEplXnh6QG4xN31EZz9ic2I3Y1NtUzZkRmBxYUYrbExxTEskMG9SVjxDQ2M4SyUya3t4eFIKek0z
Qig8dlU9dDYwMWBQQSUzKS1SaiE8aS1edz0oYTJCKmVHYD1BXktQeyQ2cCowWTxMVWQ3JFFQNXNF
PjZqQTZDCnpveER2VFc3KCk2cFE9YTlPUVFaQEU/QzlqJX1XQSVfSiFiM2M5P2xRITRjKlhEY0o5
eHU3eTcxcmQ4MDRqJmlLeQp6bSlfM1BkXlJXYys+Qi1DcGZ7fWpELXx1aGklSiM3OzZIUjkoVnlY
NlQtakw7eGBSRVU3eUJeKXVwWEk9Vz5PPXAKemRLWmBjRTJYV0hLXlZzZjBkbG42di1vOT5pfl5y
KVphNVNmbUgze2l5dzk5NTI2LUwqPktWNmp7azdhMU82JX02CnpvLXBMPGE3Q0YtPmF3I1dVfT5D
KSFYXlc/aXpWSUhCZTttSEtkaWNEbilLP3NXYjNlXjcpYkBDPlhHJmFhTTx2TAp6XyR2PDkkTWZf
WTk+RDxzI2FpT3VkMm5pdUMlcTlqKitGOEdac3xtR158JndAaXZZP2M8YlFeMm5oaGlJWDVYQnoK
ejcpPEY3a2tXbzh1Qyg/bihjYzNuXlFqbiVHWDFRNytoS0dvWD5HandUYzxfRkJ3RUN4Xmg8YklQ
NyF+K25JN2JJCnojan5CdiYoaz5rU19OQVdmZE5STT5HR05AYkY1QkFreHprckFuMVpFPEtNNUNL
JlZGfHdtNHZjNitAQmRkb1p0bwp6aVhoPy05fDdUd3cleU9AOEIwdCp2TXckfnhPaks2TF5jPWN7
M3UwTWFoeVg8V2RUb08mZUh7ZSl4LXVZTFhxSjEKeihGfj5oKFI1S2FpV2g/WF85MUdtKFA5VHQ0
T2o3IWd6c2JeNCZAWG9BNm5IO1heWk9FRkdTOCtiI0c+cUR3P0leCnp3JDg7fEA+aWtmPHcwQGB7
XnhzU0xRanN0RyhjT2YhMShNZFZ9ZTBLZFNgNWpFPHt4diFHK28/Vy1FUzY0MUteZQp6SXojYV8w
P3N4TVMwUVZtPHRLdWo3JnMyYkFoalEkR0smUVZDSCFaJm1gMjlCTEF1U1Q0RSRmKGtITkZme1FY
JEwKenhXOSNsVyptY31mR05LaTVQKWQ1YWAwMmpefEU0JHBHZzY8SGdNMmMkJSQ0fil6YSVmTkRm
QUhUQH1kO0dZJXgqCnpxIXp3JW5Yez0qP0lLOEcoMVZoQiNPJV8wR1g8TlMmNS15fmNWUzNjRE9k
dCFJVGA9Kj97QTtldX0oQi1LRkNTMgp6TWQrWWImU0ZATnlKZW0+a2VfR3I+YmcreHMmPT5iN0B3
QnVhdyo1R1ZFdD90NzxvXlk5NT5MfVUyZ0dUPWVEcVUKenZ6THNiMCZBa0t6MExwKHgmaVJXNFBP
bF9kcVpUfWg4K19CITleMnZAc2YpeTN0VFJMWEY7aH5RWHt5cE4wMHBWCnpYdyVqQTY+c18kNW51
KWAoK2d+fEF5d1FGbTRzQFdoamxsQWo/fnFCZnFLRj1TN0gzZyU4VnNIeHp+MSRgcX4pPgp6P2hv
fkQhYDF9az82ZzdgU3lBTnVsbnlkQFpOQDVYXks8TFIwS0BqSG83cEVFVGxZO1FKeyZmNDBJWEkw
KXs9N2sKejMhLTx0SztkVypjUUhOWDZZI24/WCoreUBUYDwtWEVuQi0lOWckeGBYKnh7K29ScUYr
cHltbXk0ZFokNmN2Vz92CnpmUWp+ekJhbTFMbFVhIXpzTTZTZDdacDQ3WSRyTEpoPnFMUyskQXZV
I0JEJGk+cTNwTShwfi1CYmZmSlg/cjUybAp6VDZLNTIjLXM+Q0t6ZFU9eikmbD1wdGghdGtudXJr
bXtCSGc5MHA8NXV8NTw9QDtkKkEhS2A4UldpSFQhdklKdi0KelBVUVhKMThBcHp2bil6S2BDQGxH
Tnsja2ZRKnlSSWNLUkRQK1koWWlzVztzRE18YyRKLX1vQ0ZQaDxnaUJ0MGc0CnpGeH0wZWQ5WUJL
SWVrKkkoQzI0RHg4SH1qUlF7az0hZnJ8alBaMyFkO2hqTjVudzJDK1dkVzJsdnRSe2Y7R143egp6
JmF6NTRLfndlUFhaKjtyNyROYjZpTUV0JT4zQGY7eUxLZT8hUWFodVlOUERkX2Nzen1yNGN6MWdX
ajhWPzNucTwKemlLbUFtS3gwd2AyMjRNayMjVFAkNHJqejdqNzw2dnJyansrdkJ6NFEyVDN9VlNy
fUBldnByO0ZCUmZmVGNnVHBlCnowTF9yaj1vSmdWaGA/Oz4zVjNScEJZdTV8JnI9NG0/P2dfaTB5
dWk2Vnl3UWRaeXM2dTFwaHN7WGImQVEhdm1NSwp6TCglQmBZeWIzY09DM2wtI2pkcDh7cXZOdS1F
WkJrRGptZVMqTD9uZkpaOD10UypBQko/RVNmNE9TJGh8PU5GeCsKekghZWN4RCVhSEw4UWUtRFc0
OV9SV1pHT1J7Ry0zZTA1UihYeyFEaThJe1pGSyVvTkQ9PVQ0fDJMKnxLR0V0fk1PCnpPY1YpIyk2
TUVweDYkYnJacHFFX05JJUMmWF4lQndvJCRnKVNXMGU9Mm0xQU1aVjJzeGpNMDIhOGJjd3Fyej19
Vwp6P0pSQ0c3Pl9OU2MydDZAaStwKjY0Vlk2WGdFWjJVaFpvKzNMayE8N05wPn49byNBcEJBJntB
S1ZUekhOZUxKfDwKei07TGYoI3drM0RvOTJ6ZT1EOVdOKyN6dUw7VEhtTnAlWk07KH42ViZsd21i
KFdnaTNYZHZoKjkxK29CfU01Zzc8CnpOOV9Rbz9rd24/aHkmJXVYdF49WEd9KVczTF9RNyYjND5+
WEZeSWxSMjxRNm1wSGs4TzF3Vm5mZHNPaCV3dDgyfQp6RXFZS3s5cVQwaTw3JitUX0FqY1VDaCpk
eTlTejIhJV55YGVpeTlPYktxST1zakVhKjxeSDJhQUYtLUo4I01DJEcKeiZnciZ2VjNebCo2PGsq
SHR7OSRxS3s1OytIMlBwTj9USm55e3VTZDM+Qy1ZO0tVIU1UR3NRdFRDMjx5fURiK2goCno3cU4t
THlkSVUhODZaNmFUZWkmI3k2PzVySGpiOCMhQUNxfTMjM3tTdzhEcClBQmZBPGgqNlVuVUQ1QSM/
aWt0dwp6VG9TbkB4JVNfanhsdD0wdF8hI01FcFF+OUszKGF1I3hQUURGMzU7SDhDKWNLcTtWPUNf
bGo+amhrbE92UUBoV2EKellaezEyPSpkPTB3MURESSVqdiskJGMqYzUoSEtKNzdQa3w3JjdLcVN3
e1JfQVkjbCh0VE1UUXU0dU9ZP0xuI2E7CnplMEQ3dTc/c1A1c3YqZjVvNWxabl9tfExCdDI0MWNM
ZFF7T2l0JTJiWX1YZSFpUSpXK3lsUyM4ciZoRjxDO0h6Nwp6SCsxKHUtbVRXfW5MaWZfNklhZmJj
NlY7OHBNUjFiaVJAPl5hUCMtd0dmNFMqbyNZZ0tNWVNLREFKblFSdG9venIKemohYSROQXk4dkEo
dXBAWHtmSSNAJH5PUDM4PnYmQHdWdCQocllLT249fXdjSTdJQmojKnY1Yjc9UGh8WDt9NkhOCno0
MVdPLT1vTWlNdDUhU2ZqLUNeYWNBRjRZYysrVyhNVG5wRXZUd2BqbWNKSEt3PCg7TnpPczlmWUoq
O2JZJURlMAp6Yj9UZXFlQ242TG89Q2pKJH4pfX5Zaj1obnE9bWpIZURHb2FXLXI7e2g/fFB3aXIk
NW5uNG9LR1QjUUFDWmVfJSYKekN8Z3dmcWhjLU8xeExFUCkpWCR5WlpaUVU0eGkpPjJGNyU/Rj0h
PnNZc3lKXyt0bWhALVcyTG5CViRyJkxfKFM7Cno8aiZCWnskM0gqUVZ3ZippOEh3SFBCOSpEK2Ir
TzNwOSRzNil+IUomKy0kczdsVFE5O0tYIVlebSQtMVpkeSMxcQp6VDA/Sl5NMiROWG1UTmsrbFQ1
Vy0tQH41fTQyJj9IcHxFR2chZHcqUXUrTj47anFDYnAkJkh9UWVAKUxCTHlPWHQKek14TUJMY0I4
aEw8ajYyN09CYmxVb0hGdDlDS1EobDRmTnVZTnZufUlEaURaMnVEK2N7SV8lYXs8KjIrYExhSnR1
Cnp4LTxMPEh3M29edmg+cHFSTHdHYDgye3FkUTlKSEQ+fVBsWHtTJVh8OERzZFBpUTl+KF9ydjs7
SD5WSFdCOT19bAp6Q2Y9bzxeLW5DWnVHcS1CUCk1aCt3fX00Uyl6bipUQX1fQWRJKXFOUVJ8S1Fe
bmp8ZUZnYGY/MlEzVCVncDwzQ2oKel9fT143S1EkfVlwTyVZKnskMCg8UE9ieWg0OzFrSyNrTj9i
eXxMWVp0XyYyKndWMFdhQjVKXjRIQ284dkxkQClzCno3NDI/UWEmUGdqRT9ZaFZTM09zODU8eXNB
KUY9KFMoYjQ2VT55KF5pe09KNSt2SkgtSmRuM09PNjliVlYxaSZHYgp6QU0jZzFVcC10JUxEIyk5
akNBbWFeJTJBVStrXkA5emV3YWhoUkhsOFQ5O2g0U1dad29xdGxza2RnJD9AYGIhdTIKelQwWGNN
dEApej1seSM2YHtBTHt4QFlDTj94OHdpfWp9I2I9bHo+KlRWKVp6XnNpU2ZFLVAjN25SQEhjQkxK
fUFPCnpJP2IxZip7MkN7P1FnaD13ZjN3XjxadUs8ZGslPjBzKHt0SkAlYHZhR2BsfmlxflVSWVlf
RDxgVihFcURzfG9MWgp6aCs2UyE9OWlSOFBkVTgrSDlzUDZWKmYhbHJyITtGPEc1NVhvWSE8dXNv
LUFwYy1Wd0c7ajl1PUJYWGlkMzsmJX0KeiZibjI1NH17c0ZhPSg5bGBZdWtzTkh9bmFuflVlO2Ar
fmQ5Y1JgIS1VQzc+fGhUN2x6NXJNcSk0dFBhQDJ4ViEhCnpKbmQhT21XbFl+PilZKUJBRjQxVk5n
TUV8PGB2dmduYmRXSWoqPHg9MiNafWpuUy1KJmg0MT99VyFJISMhcTxBVQp6UDxib3VsKGFxYkFu
eXMwYyZKZ0R7b1ZGa2MmSTY/QGxVPlooIWBUa1NmbHtCdWJiTkE9eDV1ZkhzMSZMRV5Cd3MKekc8
SDFQcU9mUWNgb04oMFYoSmU+WmFEd3BhKVoxbk1NQUdXcWFCbFIkPTIkaCF4eFdNSExhOTE0TGcm
JG5yTWwlCnp1RTtNLVlMVTN7VW95bThgdnQ7c1JQaDNycXV4Mk01TTkjckxlPW5VT05JTlBrJXkq
THtaKndAJSRsUElHbTkmUgp6e1Y4T3BkfE1qY05EMDA2JFpCI0JPIWJrOFRCd0ZzcjQya1lMRXNr
KTMhSTZgJHBmcnw+aXkpaShIVGA7OTBjbnsKekJiTXYmOS1FXz5hKzZudTthXkpLXn40ank8OD5V
YXR3JmJnTWg5P3spak14ZEl5V2cjTHo7dk5ZcTRHITxTZFlCCnpDZ310Z1RVSS1hPCMyKkBlKHtE
PW04eFQtemZDVldJfDQ7KE84VHxAenY8UVJgVGNJQFdAZGZXTSFhMTBVbzNRTgp6TUU9MGA7bz1u
eEd4eDNTaUxEd2UyZ3g4TzVBcSl2YSRBIXJifEw4QDJyZm8kPiZUZjgjSC00XjR5PEUxbVNKOGkK
ek01ITBlIXNFfUxPTHZFRUpKVnYyKGdlKXUhPCMkM3opbT0yUEtwZn16a2I/cTdkMUwoTkoqPX1M
ezkyZW92UUd0CnpucjdUfU1KOStxbmFhdksrb2Z9ZzY2OU5tS3hBZ3U3YXdPKVJicVlUcz9ZWUUz
Kj1WRGkjfVQzVTd+bWEjbDNRRwp6Oz41U04jOUVuYjxpbVlDMHRGM34lbFB8QGx2WTYzXyFDcEpK
eEo4IWJKY2dLUDMwUn11JHdAO0hFPFQ/cXEqV3cKeiZpWmgqKThuKml4U0VgVD9AO15xWE5DQzBN
O19hNzZLclo2aXlDfjdabE5iJUJSIyF0ckYyWiNxUzl0N1JBfHNOCno0XyNlT0U+Tl5SK3NTb2k5
NyVwZFdIS0lWYnN9dyVUWH5SdVlqdCkqQ01DSz5fSCg7NDQ/ZD5TSntWO29ge1EyNAp6I2I3N1Zg
VVlFTUFQSUpIPUg4JipfIWJCY2Y5dy1eQF5tR2Z7MSp3dld8c05RdElXa2g2SC0mcWd6UmE8ckNo
QH0Kej9DTXZRPjMpNXFONF5qOUpFQ3goOHNONSFaVD0pQGh2YzIpalotNFJvOVJpeWB4JS1pdnY2
RnRVIXtKJSRqKXBvCnpzbjJ8MUg1ekY3UFI9fWBtQ0RyO2d3b0dKT3sydD9FTUJ+OEE9eygwZ3ND
Pn09XjhOVXhAeCpVLVo4S3lzenEkMwp6WWxPZjZ1WitoU3FxSmY/aVhOUzRgNS1KOXN1IXhyWVFX
VTBAfXRofVZeO2N3I2gxb0olI1lZbjhVKDVHXjEpSmcKeiU7UjtNQHJJdXxNMiRIVEd7MEpYczx5
RipYMGI0TWl7WjJCY2VtVW1DfDBpbFU5KXc7cShHZm8kfXg/NCpYOHNTCnpyMiZiP3l4LTxUVXV1
JUY9Km9GSEY3KkNkZkJkd0ZeVHBAKXplJnFFODFpYiZUQ3A7WDF9O2ZeTD1zZ2sme1VlQQp6aVg1
Tyk5enZHQUVRa3Zpe2ZGfUJUKml9Qk5eJn5DK0pzalBeTkwjMk5TPztPdGZFczMrODlqeXBJPX0/
KnRaRmIKektDVClyc1Qhe2lLWDt9PVpsUTdnNEQ1dXg/cUlkdmRDPjk9ZEsxPmd1SWYkZjRuZylQ
XmktbEZHKmBNdVE9eH1rCnowV3Q5REZeYTtCO3E1ZU1TbFV1dDxyWiolSVFBI2JRSW5SM2g8QGd7
X05ZYGVIN2FEckpWK1Emc0tpSjd1Mlo8Wgp6MWBPTD9MYEUydGgjT3FjTm13fFQkJSUrKm0tV1cz
V28zMFNTeyVHdTsqVWleIWBCOURNR2h9bil2RSg8Xyk9dSoKemxzfGpOWnBgMWlERUpiSjZmZ0Bw
JV9MQHMmTyZYdVU5cWRaTWhXSDtgSWtxRjMmY1NGZjFgSXxMdkIobHV4YHFsCnp3T2sqRmdeSztE
dUxQRmtWfEd5aFFhRGtaajV3NTVvS1UmIXdAWUp2YW05QlV5Wj0zZ2NFYFE0IUBOPyEtTF52Iwp6
OzJLan4qU3tTdUg7N0RwfEl2WnF4ME93eWx6OUBoIypiaHdrNCR0aWBvMDNucD40X2A9d35xSENw
OEEmMnRCZlIKenlmVFp+PW5tPEtVKD48VkNGbkpSe011cDdiP3MzJDE9SipCNzgheTZhcyMxPkFx
MHxYTiYxZzs2d0Q3ZEY0a1p1CnpsQUFrJDJuWUNuIXt5LUdzUExKT3AqdntkM0R4ckJXKSpAbnJK
Oy0jMn5TPWxMMFhYJkdnKWI4V31hMEp5TlkhZwp6ZzJ4dWJ3S3lVQzEtNiFkKl42MVpKYUg9QVdz
ZXJnMDB3cl8kPkRzfTd6aUp5QEAxQ21pQVJKJms3bGZCTV9NQXsKejE/P3hlP0xVdmE4dztPfWwh
MXdjYntlUzhuSiZKJWNaQUMlQng3ODx6eF4pPHR3ezQ/SXQzR2F4aVVpelJjJS1LCnomUC1ofF9Q
eVhuMWdJJTVxbV8wRmVZMXh1cWIlfndxRyNIeFh+fTJeN2peYHRne3olSTE/P19CRDw7T0xVe1Bo
Ugp6dWhmKH55QDhxUmBod2tDXjgxZkUzRUA0fHt8Mi0/NkNrNVVKanY3NSM9P0RBR29VNn51OU5i
JlJudyFMNXVCfSkKemMkKjhNUnV2UEo9N24oe1BoUkVrcjFGPCRFeERlMWZsITstVHB4ZiMqdVlg
dFRNVTRuamsyWHYkKCpIKzN7bHdICnolISo+diE9YTF1ISolaCVwSTQqZEcoaDQoJGhvVWYoQ3Nf
N0xHS0Fzcks8fXY7JjNUfHE0JTVOVWQ9SyNtZD94NAp6aGNETyhFblU0QVlxQEhlemN4QFheMFop
Vkp2eSVgQ09vRV9GVlRkYmg7cXNaZUp2KWpIJEU9KkxkXmpDSF5icjUKejdCeSh7az1kOSVZTD9j
RitMNXBIUVFANTh2b35rIUdOM1RHVHpiQCZxaT05VzwrK1hTVi1OOFMma04rK0FIZ0k+CnpVUz1f
SlJVJFg4Njk8X0pzQTg2aWtOdTItTj91SUgpbG4/ZT05dV9xLU4xbmR1WDdyWUxeNDBHVnVvMjZi
MG4qKAp6PGlLdTxHcXszI0h6fVckT00+RWo/fHhoRDFDcjNoZ3R2UjNJWFEjMSRSUkhrZzd0M15o
MHNrRzhYTkBmYDY+cCYKemNTdE1JTlpKT0VffWB6bUUmVEcmOTw1UntRYkchbihWVTBXSW5+TEZk
SzZ6ajJjKWdKST89d3o+d2FCenpmJDNlCnpJYURjVUxAcSFmKVBAIz5PaVpZaVErfl5qdjhAWV5w
QyopUiFeODxTYzgjSUhhQHcpIT53c2R0eXpYUGdoJHF4cwp6XmR4WDltPn1VTjRNckJLMn09d1ct
RlBJcFo0SVdlNihVKkVuWkd+VW5wLWkwcXd5cjd0NnE/bCYxTGlKMylxIS0KejYwPT5DNTAwJksl
MlIjbG5ZcWtwRUw9bUM2RSojUT9RZXVWXk1HTXYlRUhXakUpbDJaOG1ROyNpUjRTYV5JbV8tCnpE
SThwITY0WnsyUnZ0NShsM3o3bTkkemIzIT5gWER2Snp4cDhBTEdgYFA0YERzWlVnbFVnbWN+d3RL
I3NGajFUUQp6d3dlLTJSZnQrNTVTRXdQcFhRZXdBY2smYTdnKkQ1NjtfQjA9Tmp8VEg1cDNCblFK
bmVXOyU/YWRkam42QDVgPGIKemt8aXw7JDFBYjRCJEpiZT4pcjkodkA4fnA0Uz1+NHBrTWJAWmsm
alJRfjJ9RTc9OXRGXjhVUGV0TSpxTXVmWj5rCnpeNDh9VGchKUF6X051ODllPmpJe0VWKnl0aVR5
a2pHY2drc3JBVFo0VippI3UlPD1FX3c1ZWZkVEIhXiNWJiReNwp6Vk9tYTsoeldUOWh1Iyl8akBq
bWZwRENFXmJWQlcxSDNPe0ApcHF0amBGdz5sMjt1N0tqd0UyUT1QYktJT3NzX2MKekN2QXkxSkta
aFBVMTMmQEE7WlolIXsxMzdeXjMteEUqbGtEJUFRUkFzMiowTUM+Z1hmPk8oNU9MKDRfVDU8RX51
CnpIPncxcXYyJWImZ0Y1KERmcHVYK1NDQi1GOTFOMnVKUGlqZVppQ1YwJnkxTkF6TnMqJkIkeVhv
VEh6Q3wzK2Q9UAp6IVRCdTdmWiVXTUtUfVAwSXdFfnRRYDlxWmZnKD4yZGEyO3w+NiFHQ2cpaWM1
ayoqUio5RXNOWDhlPzk3RVVCUHIKendTd3dvKmY2c2dAOXJZJTlefF5jYGwtLVQ7UFRZejJzcFlG
KXl7LSUkQHxnQyQjNiN5UUdRdTdtVTliVlFnKE9gCnpick1OUjU/YCo8KiRpKkhYYmwhd209azc2
MT0yRm8lQWpmbWZjQGlnXipSKjdpRXFnNFYzfWwhYV9PYEchNk4mUgp6NT8jT0RjNTg0ajA0UU9i
SjhpNjAtbl5nVHo7RGYrS0VvQGExVEN6THZFdHNrYlRFMHk4MFJjSXQyeU48aXdmNkwKemp0SXdC
Nk0zb15YPndmaFZAQ35ocmFIZUdxYSh9SFd0R142VjJ9eko2KHA3TSl7RVVzeUBVJH5mSEN8MnRq
XjhlCnp7TnlMVz8pclVsSE9BQyRTOXhAdnstOG5oZ0Z5MHZFaWxiclRpMkNyYzI+O1VtX0FWfGl7
ZWN6cnpLUi1nRmV3NQp6KHc+N2ZMalhvYF9yWEpiZml9dERnNmsmNUUrJmxGYi1sTXEmUTcyO3Vj
ciFHZzR2XmNfNkw8Nmh3VDM9JnBicjYKenlhcWhZcytxVlNxX0E7aERRTXxARTUxXkttYmpQcFBe
Uz9MdkF2KUQ3K1VEa1g4TXc4MyZCZDExO21JLVZ5RkVMCnp7KkhFeistdWcwVUh+b1UzPHdYMEh9
NEtjSylYUE97Y01APUJ0YkA1PVVsbjdgPSRLNzwwblZCYD9kbG8mSVdUYwp6aXw0enZsJHlqe0ol
eFZUYHxCR2Q1fTElSk5xdHQ1KXhOKEAqeXlOVm1+PWZGMVNONFdHRi1AT0FXfWlWKEZoYzsKelJu
YHY9MWR5Q29HeU1pRTZNYiZLRWxMZHA5bUtCbEhUYlBMcWhJQGM8KVc3NlBxYVImcklYK3NPajFO
VlJxNng3CnojcUxpQ3ZBM0tpVCt9eC0mQl52fT5jV1pVRUpjUWcrY3xKKGJGe3RJVWVKZDFvYVRs
UVBiN3lReD0jd2R6aG53SAp6Y04pbVArSm05UiRUaUFMYiQpWVk2az9aflp3dGtyQDgyKk5rJDc/
IWwkcU4wWitTWUc9alZTayVwVSttYk0oVS0KemJlYjkoVCRoaCp7OGdFKGdeJlgld0JhUmo0WGhS
X2dsO0JtYSgoYVJ7d31+biVaRC0wKHZwWCZVJm89e0E4d151CnpXalg3aGVqTGVWWmotdEJFV2Z8
MCVQVDdgNkhoOTZMcClKYENROSFjYFBEP3U+TiVLLT5geGhQQnZMe01ZR0pZQwp6UG1kZlgrSGFP
QGE+WGU4QGkodT1hOVBiX0I/OSpYO14rJU9ZI3J9bE0zK0F8UHhBTzBWa2hsJlR+cTdwTDNRRyYK
em1yKHRrN29NQTVANm9yKHl8R2EpV3NhIUF2VHIhb2tnSmZCJT58eEUxenpxSms1QE5OPTxnSyo7
JW8tN2AkP1J9CnokYFc8bmM3d3RLVXNgIUBLdk9GWlNWRCE+TnMqPmtrdTJoQ1lpcXt3dzVYVFI7
USE8cDwra2tJdHcqWnFPX14/aAp6Rzd8eUNGXjZDbHJ3TmtPQ2NFIzVidVE+S0tUS1N3UW9DWSkq
QHk3YkN6YyU1V24jJWwrPDhMY0Faem1OZGNxVkUKekNtOCErY3FnIVFBKFJDbyNXQGxAdERuOF96
ZlY3eWwtKXwmcHhMfTQ8NGQzK2xkQmVtRyVONXNga1dSaW11Xml2CnplLXNVKVM+QTtnRCo5Mj95
blQlfG1NS3Q4VUZCTnczdElHeThaSjIwP2hCPkgqbUt8fFN4WUE3MT8hSVJxWX1MLQp6NjFAdlkq
WHYqUF80alZMVCY4NFk5ZnZjI1ZEZEBjb3ZiPTFDI1VfX25+OWZ5OU4lNytZJUdDP2BKZk9RRWBW
SUUKekk7SDZRWXJ9aTEtT2okbHdxVDwmKEBxRlhvUTwkWGNzTkZJY1pJbWBULS0oMWQqP30jN0VZ
bH1FamhPV3gzanVoCnppY1otKkE/V0c9PFQ2JVVMQEVePmVxJDVpRD5eRyN6e1dNMiFuU2h6b3h9
ZnBFbGxmQGhnY3pfKiZXPEBKTSpjagp6WWQ9R2BEX3xzSEFtQXYpZF8jVjlDKjI/YEpaJkl+QFdE
Nz4reVY0WlIkakZ7MnlfMlRmJlRmK2N1Qkk+YEkkNTUKejszVXhOMVFjajluSW8xekA1Yz00OGsr
cVo/akhNZWIxPWx3d1FjU0V4LVpiPmAkPjM7K19oZFQ4Rm8kenlWOz8tCno8Mj43WSYzOGZmPD5o
N0NLcD9pQCFBQ1NLT3pffVdObDkxfnZgMj5tKzk+az9wO305anB3cW45antGPi0ySlUkTgp6UVhS
MC1AdiF6SEBiPm0qNXNsKj8xMEhmMDZtK09PSzA0QVF0bXhRO2xZa3Q+TEZpKzUySndOKSstSU1+
Z2pwb04Kem47JXduSnw5MTwxMUFHT3ZrTSM1XzQ4XiRfWVFGNmxSLSp5TS19ZF5CXyNeO1JtTHdI
ZnpLNTBrZlB0QGVFZCU7Cno9fUU7anFQayR6LXRMYjM0Mk8tVSUjR0s1WFlZJmtMYHstJWpaVUBo
OVUqOVFmWCk3N3U0JmgxRnh2VntBP1VxRgp6cUpSMmQ2aCQhdUZKYnE5VyhEWG4xb1pOcHRaVS1n
bXE3USlpelVnRjhrKEYwaHdJXnRMNyhyOVRuOSRLeT40TVMKeitsN1B2X0NqaEA0cHZ3NzltWFp6
VyowITAjUjZ7PWIzXjI5K2dGc3hHNDIhRkVaOz9RSSZjb01wbkBnP3A0TzA3CnpjUl93RV99XnIx
dj0xMUZSRXsxaSg4eUg3YyVNYEB2QS0tMWlDPWs3aXIkPCRMPUU1JCtKYzZ8aFl+ans4ZF5JIwp6
dlhmY2otblNVVXVpX3N9eXdeTkFJMXhAPmsreUJ3cmlsfnFLSn1KWWBSKUEmPmVyb3NmQjt7SDNI
d1VFP05uNFQKendzN2V6Y1FxQyNLUi1Xdmh4c2Y+aT1wJHwyO29lPyt2bk58Jn1OQ3Q/R3pYLTgy
ciVyKDJARmpZU1o7dD9xbXBACnpXWVNmKHQoK0J1ZTtmJWFYO0M2enBvWCN2XiQ4WT1JQWlaNFlt
UyU4aDBjNUx1SUxAMip4dW87ZztebmNVZXU3Ugp6YUYzNEhKPjVYdCorRXMlPmNZYXQqR2h1UWhR
MjFFOCh4NzRnWXNaWD9WSjYoQjs5T304UGhlZG0meH1NRSZIRi0KekNWPmkwTTU0Pj9FPnZxMGN9
WFBnSkZ6UGdja0BqaFB1MnslWnI1MUNaTmRhKlM/KTFJS0JEOEg/aiFvZnQhLV9GCnorNVhwTTZr
Uyg/MD4pa2tZaEJPJUx8NXZjaWIwXlUtQmxuaCR1UXd7SkgmSXJfK2h2JiZmakd5YzBLaCY2ckhS
UQp6NGZQYnl0RWdCYHBQWFc3YjtFcEZXbzMrOSlRMWlDZG0pP21yLSFjaDRpSFB+Qz97TVlNREpf
SkFOaDN2NHZLVTAKem1nKyhePShPaEhlNyltaytvREYxWSQlMi1OSUt1WWNaejQhJlMtUjdSPmNo
Yz9DZ3h5PSs5PFZxUG9+IWBOcXEtCnpjUEd6UihoSlNaNlpKdHkrKiFyPiYkOFVrMFZnNj17PHFV
JTh5eVl7SVZfKXdFSU1fe3gzV21OOzFIQypGNUVvUwp6R29zM3A2bkliQVIqcVFKKTtBSEJNU1dt
dnpwSX5CZG1ucyU+KUxvN04hd3tIdUZyV19PbWwrT3FPRyFwYWNkI1YKemVjZmVIWkBaaCUtVDMy
cSgmIU5PPEEpa1k+Wm91ZWIoVEEwayZ6IyVoLSNXc15+a0lkdVdUbWZiJUM2JExuVFRkCnpgZ2Rz
KVZHJDd1e1pAfnFJTWRoZGhLO0EwKVhyTyVBfXpidSgrWnJ4a1J8NG5fKlZlNUA2eTMoMS1PMmI7
fHxeYQp6PiskO2ZNLUcrYFE4cWZ2JCZNVytMazI2SEBGWWt5ajBreXkteFNtPyhrblRaY3UyOHty
O0RTWEtGXz4oR1cqb2UKejZJbCpoYXFyJGQ4N0w/V14rN2smPzAkRnI4VDVLcjRjWmc4UkFDeDxp
YjEhcFErfnd3K0Q3cyhFZmF4cjVQUWg9CnplMjMhd0BmZUJSPVdASFY2TE4heWgmV2xMR2d8SkA7
SFE4dSpZNnRMZlFiX3A5X3wwelFyc3hjTXZFandSeVojJgp6WF49PTI4JFElcmt3MjRvO3M3blB3
WThOekwha05+c0tIXmY+IWRGQz9SMXxLeG9rZjYtI0wrZEJDemhoSH1lZFUKekdiTGFRSyMyQG56
LWEkKzBEPkdtSExaRUFsc1Q+VnNXWVhyMz8re2lTd21ZdGwqa207VCopNXZQTF5lZCFEIWh4Cno0
VHcxYig8RXJaVDlLXz50QCFYI0FuWmBNQzshZVM0TXM7NntPZF9KIV5ZaStRSTBQRW4rd1NLI1d+
Yz0lS0M4NQp6bn0lMEZGPjFzT3U4SE9nMns9WnEqTVhPa3RrbDUqcEZaRTYpT0I9cG5CJlZxbn0z
WH1HaDNjcCNieT1oRSROVjkKejM0aTFwKT48am1lO3Y7dChIUTs4PDRRSX1PVUp4cHlQTEQwYlR+
QV9EeT1+K1RgUzBXbyM4SlBaJk9CO1k0cmdvCnotWG53YTBLUTlMK3lhbXxFalp7e29FdjY/JHhV
eTUlMFVWM2cjUTFBPXZubUZjUmx7VSE0SyN3MkdDWSpmUmRiPQpLWT9aV0dAYyNrYmNgQlIkCgps
aXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtbWFyay01
MTIucG5nIGIvYXBwL3Jlcy9lY2xpcHNlLW1hcmstNTEyLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi5lZDY4ZDcx
M2E4Mjc1ZjRlY2ZhOTY2MTc0ODk0MWE5MGMwZjk0MGQ3CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJh
bCAyMzg5MAp6Y21YVjExeW9lZV9rWCh9LVFCVSZpWGV6fCQwQ1J6cHA7NH0tUUJgMkFlfHpKKHhI
SDtxKTR9PGYqez1gQ0RQS2QKenxLYT1scFIpKHZkMmk7dm8xYzU8JmIlbXtgKVpeX09oZ2Ffaz18
OERKJUF1TXhQKElsYztNZVote0RnVEdHVi1uCnpRcXVGeSpxcmUoZjNqU1F4M2tLXj5OR0xCN258
QTBzVkw2KnhBQShlQkMoKkxtRkdMZitefUNGYihqWWwhTFFxIwp6P3NkSVNqLVBzTShtUDgqbD8x
KURCJHdISlpSTkU3PWA2eXJpO05IekFsR2JRXiE/WXo/ISZWK25Zb2tyb0RKIzcKeiRqRzlLJGdy
Q2phSXUjRjFPSk5QdzsmMmlOX2BHSTIhWTVXYFVXWVlQPHBgKDVFI0h1ZmRmJWU+UngqV2FVYy1J
CnppWDsjVWdgJG84LT13Pk0jc2RULWo1dWshM3o0WFlPUztYVSZzJms0QHNuZ2tNbjE/VCZ3dnp9
a0JpQU49RlVGQwp6NzFAcV41MD54WTt3WlhfSypGUmxqNCpYKDNGanx6eVFPQE9BNkdsTTlHO3hy
PkVPQ21EKTlhT0JWRlRTZ3A5dHYKem10QzRje3N4N29Sdyo4Mkc4UmA/R0NfM3dJSTsrckZvYn47
Unx5WU5xSmY3JUNOdiNFcHs/Xzt4Yng/YmNMUzNLCnokNmRaWUB8VjVvR3F0dVc9d3VgR2N2IyRU
Pz5FNkFacGdRP1NDNEI5Um44RFE9OEQoJjtLRGQlQit0ZEx0NUpMbgp6TFhGNDAhfF5rbDQ/fXxv
bDY/aWxicSRpT14+eXVPXn1+dmhJeUFJdDE8THlSd3JPTnFgbmgmWWRWLTlAMmQkLWIKeldLQ1ZE
V1BUK0k0dVlPbTYodCVAMHRfO2VMWHxTRjcxRV9LN2lRcHkjIzJ2JTtvU3xmNm1CdDN1OFlPOU5T
fUIlCnpgI150bGR8K1ZzY3JjMk82KzZoN2VXRUZtcXtLblNBLTx6T2d9Iz5US213aWMhT09AcGV5
fSRrVyRpQzAkb2JvRAp6Xms7ZzYxaEBQIWtffTJrK15ETF56K0AhOE90ZUIpa2ZgZUI2cTV7fl5y
bEpoYUphI1hNQkJqNlI7MH5WUjdwZioKemhPV31qJHhHez9jamZpcTRTRG8+MllZe30ldmdkWU1J
PjFVMUhvUC1qNio+YWEpZHRKRmY4JUJUdF4zP2VLK0RXCnopZ3N6K3JPSkp1Snd+dWVhOG5VfXZ2
QXxLV0d2MzNzV1YwN2VHKlpwKCE5ZzxnWUxFX0ZTVncxck0tQ2lzTUtIbQp6P0B2MHZIMkFITDM4
OCZQS1JwV0s0cHFlTThIRCQ4OyRmejU7Z3NRJiU+fU16Sn5SKzhhZj5iT14zZkVmTn5oUVUKel9H
OGVOWDRpPE5MY2srM0UwUkIrZ0Z5SkxydHAmPVdrdiRSPT5sI2FYRFdzXy1Je090dmAmd2UpR3Zn
YEwyV3BOCnp6UU54Rz9+eTxnUmA3WXF5bXxrdE9yZkF6LTlKeHM+R25UJFFTc3xeYWghQjwyKHw+
M0E8MTQ8bHhQTXJTfiRKMAp6JTs8Qk9rem07KSFTb0VhcWVfcEpwWGtIUmJRZmN3MUE8XktvSlp8
WXE3LUcxX0d2c21vM0hzVjJXO1RGdV5BdnwKekQ8Q2RLN2xvalQ7JFhBITx3MG5LNE8raEZ2a28x
eDQoK3BebiV9TCNkTXJMRmxuK2A/Rj8zY0hBJFpYdWd+UncxCnpRcU57bylTbnNeQUlxJTFgMjl4
a05wJl9lNXVQPy1nbVNwNldHcEkjR2JJd3F7S05YVHFkMnBwY2ZFRHgpYXpKZwp6aTk/c19eQnB4
SShGQigqOTEyX3MlNkROZjRsaStOZ2p7eH48dWBxSCY9enJFO058fH1WMzc8QjVmPkdpTX1Sen4K
elphaEg8XmxebCF6TVUrNldebHRAMXs9OGV3b3RhdGNYelE1Zn4mXzk0WnhtM2xFUUVkS1F5OUh2
eHxSdz9uJkw+CnpVeTM9e1BwKEwwbUArMykjQWNKNGFgfX5JXjFRMzBkOXtwYUsqfmtjQk0pbzI7
fn0lQERqRyRGQnFkRFc9MGpvVgp6eGQ7cj96SV96bis7QUJGdS1iOSp4Z1V9eGk8Sm5Fa31PUT5a
OS0mRzNyaEZKaF8jQkI3Y0MzZisxfWxVMSt0eiQKemFnTzklJThrd2U3aUIlMF8mNjwxcShPXjVL
Xng0NXRjfERiVnNvVXxMaDxvJmx1KEc1JTQycz5zNUE0KjJfMWN0CnpZWXtVfFpzK2YhbihNR1c8
ZyFsWE15RDs1IUdYYDlWQFo1eXRoJmk8PGQlY0hhaTl2NENUbm5lVFRQVG4oOTtCawp6QGBPR2Er
XzI5T0UxVEc0Kkxvd2xGaCtpSExhcSZDQWMyY3dWQ0xrdnBgKlNyXiFBUj0rI2BQdkJ1eGhHOHU8
PmoKejA7TyZnNkE0XmpLWW4/aVVaNyN+WXhka0I4Xm9UfWcoJmhSZnFKK1FiIS09TllKQkhRZ1Uh
WT5MbVR5RiV8Q18wCnorWlU5X1I4Z28kPTAxYC1PUD5aRWlYQVNgQ1ZyYXVjM0dMI0o4fnJ7PD5a
bDxKeT9oMypwQyRKWWJqaF9lbTJ8dQp6eUxNX1gldXNnaTZlblheNFcoeXx0RUF8cUMwNns9MFlS
IW9OPE1xSXBNNHFCbnx6JkJlTT9OfENCR1EtMkokVSEKelVhOHxVWV5Ya3U0Pz4kT0hfd3JXO1Yq
Q15fI0trQ2IzNH5qVDNSRmhEbUghUm15UDctZkFrQF9xODZVOzgtZnI0CnpscCY7VzxvXkJRWHho
V2MjXjtEOSRTa3s/RmJJVzg+OURWQVRsWmVTUy0yNVpZRXBtOVhPa1V4PW5Wenc0YX53Kgp6WHJO
Zj1QdClvMGpzOHA5aSZPUyVYRTs/cyZEcmYyME1SdWxhRUIhdzx+XmxrM2JuRk5MJE4xSSt1NSp6
STNoO1UKenFHVSt0VnM7OSs+K2pKaT1SYUhQQyhtODlnfnRCeUFyTWZIMSE7fChiSXRUdDd1dDAt
ITZpIXA5bUpkekx5JUpDCnpQN2RLZ3ZybjQjRlJyO1hBRktvZChQRW9SNlM3YUVCNWlTJUQ4UEZi
Sm5KU2BTWns0bFgzcXAxSnlET3hPV3c/YQp6RlM5QGJuVkZlIUcwbDViNHdGKztea0BHNUprQT9A
aCY9NlFSZ1ZgdzlQazQqSGxKUV9xM2g8PkoteStgPzw9fGAKenUkK3wtWGEldiR2Nz8hemtNZEA3
RlBsdStee08wSVNTVHMyVWJkUUp4O0IqSkR5QDRLOWVfWENeZWRwTGR0Rn5DCnopP1J9c0YtS34x
JX5yRHhMZH09dlg0JDEzYkVgdDBTfElVLTBPeFk4byFMfWxeJXxCNGF6QTJxO2l8MVNwQWhZSAp6
Q3hXT2pyfXE/Ji1WO2tXUDVLNzdfI31qPlQldTZQZ3owXkYpbV94PUdIenw7KmdaN2I0X0E+N1Eo
K2BwVTx9OTkKelIjc043ZT42TXF7aFhPO1Z6I3hsNl49O2xJOCNCUHVKSlBSNDNDY0htRT5OTWxW
Z3tKcy0tZ2ZYT04qTCpFKkV4Cno2UihaPiVtdzxLXlV5IXZ0Ki1hcHltWXJ3PDRhY242MiYySXRv
PmE+b3Q0YV9uKXZvI1lje0VNVSZlKkxEdnphbgp6YykkKVR4P0RCR04qej07VW1tRDUle0hsPW99
VEl+bVBTTklNa2pMKzBHVjk8ak07QkNvbypOaylhfHM5QXtUbXMKei0/S3BXVGVUWXtRcmcoRng3
ZFJkfE1hczkrNWxPNjFmbjs7X3olQnRXN1RJSGxqRkJTQ08kSj4+PEI7MCl9KThVCnp1JEk3OHJ8
TGV4dEBZSyo+NnI8V3BESVVHbClDYTB0WXAzcDRndlMySHM5VEEhc2I3anlFYjZCbWk5bkQ4ckhI
Twp6JUlxUylJRmYxX1NXe1IoTUhfYDhHOWthSkgtTyQ7R09NdmBgU0c+P3o2SiFIOyRkYyQkQzlI
VDVKUilmTyRWRHgKenZ3ajtoM1d1SXZRWj8hOWwkNWtkQmxjbXtDRV9BM3ZrZj00e0Mxaz82T0Ng
PWEzfXZWZ3xhTzcmR3dwU0dCWHs0CnpKQGl+YmlrWm5ZYEQqcTN3Y05pTWhoYDR9TklUYS1USVcz
I1dVU0QlanZwYzk3dG9ffUhOcl4xVjlnKHRJU15FQwp6TH4/YmJkZF8mU0BKVW1eY1YlY3hkQ1pl
VGdBPFo7SVU5N15IKyNQT1VhZH4xLWVMU2FEemEjdFRTYypPWH5mVnAKej15I1hJZypnbmUkI3Bt
dD9PPW43d31DUHpnZjNUNCljbUZFTztgP3JeRkVgRT1AXihBZDNkb0dCWk9WZzNmT3V9Cnpte1Rf
KDdNUyNtNEVvQks8QEBae0x1fUEjIWk8VERZNSN4WT43ITVzR2N5bSpoODQxV2tJVHtMN0RVbSQ5
V0JwRAp6cCN1R24yMzZEOHtXRz5kbzEzaEM3Z3d6NHktP3ZpZSU+ZlplIWtiTEFZZkFHREZBdW9J
IXZaTW48Z0VZS1JRYm4KemwzWUVYXlkten5USEhfaDRaakR9dm1uYngtciFZTEQhY2JuT3tsY0Ep
SjYzcnQ3X1QhOVM4LUhyVyg4TWtfWERrCno3NStPJm5RcWVuKWdBPDh8QlI1Ji1hZnR8UlFzMH5J
KUdqJWtCSihXVXhUKmFYUF5CRkdyOThXJkdxSHJLdXx8bwp6dUdodDlaTHhXSmR6eU9wZ3FoVmFW
NSRlaU5EVmJYajkjZn10NWJ7RldnQ1AqZm44ViRASmJ8Q1QwdzRvSkBYVEIKenI7fWE1eGtmOGt3
Q3p2S0dlWVJLT300TjFeYk1pTFEtITgxKC07SyhoJjJfY091dDtPMiR7YGQraDtDcUsyKj9fCnpJ
fmN9PVVNcjhgKHNYZXZoUiR1ZilYeDlkWFdMcUhSN2lfQjs2ZGNNfE1yeTllUFZ7fiYmUXJsKGZg
QGxAUFg/UAp6S2huTXgzaz9TP0ZBND5JQTZ2RTkyajswKi1ybW58RjVRbW9OSlZkXkJTVEswRmZ3
UkYhVkpCMTkpRWIpKEtNU1IKejlnUDRyYUliJVd8Nm8pNyNoLTFudnphakQmVTFgMTl5SWpwe2tg
PExwIzlIaCYqa0xyPkp2Ki1ERlo8OENAIypjCnp1Mj1KNCY4KiVJK31eQnkwPSomOXpuOGxMZklG
PlVALW8/TVlxc2k0X1Uwamdmc304WC11WlVKTWNBe1NILTRKbgp6bkBlQ0NCJGt4cEFqIyZfPDxn
OXFzaV49cWBaRz5NcDJwSkErMkdXYU4yXzc4PWdDey16KUt1ck49VmJDO29xSjgKekBCP08tZ00t
dFdAdkUzKChIYV88OGo0QWZlfmV2OSU/X3lMTlFWPHFMSmJQX09ZIUwhTDEtME9IbGRhd1k3azdP
CnpoP2p+aj5fenE0VGxGckF1dFRFbUJOan5CTXc0SGstRkN4NHpuUlJXM350R3g4ZW1ZOU1wYVop
ZGAqcHxlMjRmKgp6KV8za1Uxb3NRcmRNLXheKiZYfkRpTXg/blQydUxSdFpQTFo8UHEmNShTSWtX
RkgmdzhvP0M4PWVtO09tUFctbz8KejwzVkdlPWp1O0JVUjw9XjhuaEtuKDd5NypoUCopfUpiMzw/
eHVrWkIybTx0Nm4mNm18cFhsQGJaemJfMUhfazNECnpXI3hFKStVPDZaNHNzaENKJENjNFhLVDM3
JTV6eThGbVRsK0xIMlk7NSM2ayU+emwoNGR9RHp8Ull7bmxPencwaQp6eVAzNCpSbEAySTsxeWp5
cjU5VTBFKUEhRG4hVUZ0Ty1TJjtOQ2R4aDl4fGB8Z1JhY2hIfG40RE9JdEZnYUVqamIKentwRyNa
bSZVdDR0RGRqZE9QcmpZVWpZZn40M3p3KjdaOzFhZH1kR05BXklkYVE1JHp3c0pPfVJXSzVkflBv
PVZMCnohOEpaUjhhVnpKUCsjR093JD5WJmxeO3QmQHk3Q29IKnFpJkYmIUJqcWIycD41aHB3ZGd0
VHoqQzFnPGdYZ3x8UAp6O1BzRiQjdXlMdD1WUGh5YkFLZF9ebyNsbk49aSFCSHxwRld1MUx8UHNo
RE9qRG9uQWxvT1RLUEtQdV9zJlVJPG8Kem1yLUNASE1HNm1ScCsoUW9ibnh6eFB+ZGRCSm1oV2xo
Jno/MXFeP1B4fDJeM3BeUl5LNno2YlhJZXJFSG47KzcxCnpuUEBuUEhzXlNnOXw0aiF6WUFiUHtQ
fnclY1N4KyhfdUxwNG4oNzt5bGF5aEp7fUdLc05jczgjVUc0ekBxOUJWewp6TDJ1Vj5fZ3lwcGV6
PiVYZlFCMllKdit3Vz1sXzc2bFYyKXdMPj9MNSMxZ3ArNkQ0aiE9MFdxUjxlRWdgQSQrUGUKemIw
QUlXLWEjd34xTE44cSY3clpEbU0wOWIye0s0dU5jTDxfPXRZUFU0KjN5cWZNaUNrQXFwWnFRWHol
P15WT0hqCnpDaCRyfD0tWEY4ciskI2JeS183Zi18Mnl1PmN7Rkpha0dELU8kezlrTmhgKnkhSS19
YXI+KjRvMl92fUpSOTdnbQp6MEp8JWNVZWNsdlBxK0lkMD1LIUxMcXxEaGFVOHtpdWJXZnleZWNz
RUFrSFZFaF8+O3NVUT1QK2lgTE5mZGtHZikKelNLSmFydzV5QD1iYSZwTWYhLSNsPDUzaHU1ZWIq
PUV8PGJ2NntSTWxJMjxxNkV2Iz1xbEJXS2JDbSF0IWlBNVYzCno9TzclQ3dkeldeU2plS1ZDcUlX
KWpTczg3azglPmpJRyZfS2UqeGMmM2x1JlZUcClMYnNZfUFtZTZ8XzhmQmtCaQp6QWI/aDZ3aWBT
JjFlaHxEKWgkYG4wbmZKVmlAVER+JUUkaipKc18kbTw1ZClnVzBxemw9QT5mMlVzNiQwRSpvJUQK
endOXi1eV2BxbTtCfjZUaiVyYGE7R1Q4YGtVb0YjQEE4QGstbXlZQDFNUlB6VEItayFxX3YzN1Vy
UFgtaUlHVk5GCnpPPXJCMnUrXlQ/VFJkb14qWEsxbWI0LVdHYXxZbnsoaTkqby1aTTNHN2wwZ2k2
SkVKTllyNisqKU4hY1d8TnBleQp6bVpXaDtQS35RdzE9b2ZPYFVYTitkZyoyTnc2QVF8VH5lU1NQ
dDNEJmhQPVVAa2RjcHVIbEJfY08qck50N2F2ezgKekw4dHgzQDMjVV9eWjlAJVh9UXQjLWF1KjRa
RV82SE9qaSNRYG0qSUgkSXJDOWJMQThBOW5XK2ZyXit2b21jcnk1Cnp1T00/V2Q9LXp5M2BpYTUp
RFNFUGI5SFJWaD1rIUJPLUhpPHtsM2FzeXgtbUhldTg9b1d2OStmNzFfMGYtO0JMSAp6di1ecG9F
JiY7X29oKSVoYlhkNUJtaDZ2VG5lWEo/aEJWYn4mQShJeWQwOEMwbzVVSDtrWnw/cHc3a3NBYE0q
fmwKenBiWH1aZXt+OSZPbyNtPGdNdC1wdHp8cF5Zak9+UDdzSnI1OyhLeSVpaThnR21BeiZfRXNY
UUskWVJ1Kj1ldF5OCnpTN30odyZOcGdwVXN+MH07Xk1TXjRgM1ZKYTJuTk0jRWs9Tyo8RislcSo2
U1dlSUY4VEpmSHFQTGBCJHRjQDwqcwp6UHxCU2ZMUU51IWNDcWt4dzItdDx3UlZhWDhUSlp3bExZ
dzY5MU9lay1jZHNETTYtVTxrbCs8XlE7RjJ6Wn4oZHMKejswaGptZEEpbXgwQ1M1ZUwyRGlrYFlA
PDQ5PkM0K0YkKElgWW5JNVFnempufjEqMVA8UklXTlBWZnA8MCQqNTtFCnp6dCZiaSM2dHVRcW8y
eGU2Zlo4WXtyQnVXbDg4cTJeSVZOdkp9RC0jX28jcGdpVW0xU3VRQ3NMVTUqZ0kmMm80aQp6dmhE
VXkqYFlgcEhQezFFPSl1JVZXP3l2TWU+bD5pc0heQXJzUUxaMT52JE53WURWP0l6YCVTeHtreXdV
a3d8djEKemxyM2ZAOH49TTRUcTx0I2dVK2JXK1VRZUhEUDlqamo4dl9BUUhMWW1pJEw8Vl59Mjlo
Uyh3JlBWantKVUNGN3RrCnozdmpQO0BZazFRS14tXlBvTTF0bkE9c1FrV0RLOVA3cW9pams1MUJG
RTx4c3o5VHZ2MCMzRHNwQn1gPWpsVzc5SQp6YjFIRjNuIVJNXntoRXlYa3s9eTc3PkN9RHJPV04y
OzE/R2NZeF9zfXJPbzYpWG9jczJmb29mdnN2SHlvd29hJkoKejRTb0Y9N0Vnczk3P1RRKkd9QXBw
UTJOKnZ6aDExUylHaHdPT1U9WkBHJSY3ezVNQyFlPkBUfWhDI1J3eyVNbj9XCno2a0IlaCZLcCZu
QTl5TnpBQ1lZVzhmNlM1IWNtQ1drZipsUmlIfGckNTImeGZrYGlUMCpPPkg3QEk1KGw/STJJdgp6
MG5RQzNzXmFqUDB6fD1lYno3IXEjbkNVbzwlaF4zcUw2NDN7am9kNCMpZU5+Pkx3PT44bmIqNiFD
Um16SXkhdTIKel5NdSk7KVAkSnJlZ0BKYnR5dCtrXjhSbTBoPUp5am5fVXt3N0xJemQzMG5mUU1j
TmJMeTckKyM7eihVKE9vVy1hCnpZcVlGfjhUd3Erc2FUUS0kJEFKUEVNSlVweilwQU9QXj56bFl2
bTA4WX5sWDBhNT1oJkVTO1MxQkw3fipYNmFEVwp6RD1UXjhVOTg+dkhvIzJTbmpNKWQjSFB9bWdp
Jn5AczF2MCE9b09oNGA2ajJgVHYkPDxBQD8zIXo/I19EOD11QUMKejJEcT95dSlwZEpjdTNCQj5i
MlM/TGooZ2tUcVBke0pSeE93YC0mYiopUDUxS1hvN3YpNDs1PnVFP25QWGpQNmYlCnpkWGJ9VDhq
PFMjbiM5RzFyZXJtVU0lQiVvOHEhX0NXND9TZEQ5RTdUUG0qVHJUb1hyRXFpSjJFKjtERz4taTF+
QAp6Rm9NPyFLfEJuPmJuKGd3QnBKJC1ZWlcxKj5KJUZ8QHtTfVkxNTlNT1ZvWnQtKz51fF4zRVR2
JG85bzVYTnUzTCsKem9lUFBiUT5vYnNpTDJQaXxKWFlgdCRoNTdpIXVhKSFTa1lIaTteJSg2cjUy
QTZ6NUZuRD1LfCl0KVUkTFYoTUJwCnptPTVqOGB9SnZEI3BMNFJWdCEyfjF2Wk8yKSNrdDZ4R2Ap
Vj1KWSROV09oWFJTRi1aOUU4Pyk2dEMhamhvVD8wKgp6IWAzYzJ6TCpwRWF9ZGJBRz02Y1Q8YiU9
QlR4aXZXb1lCfV4lbUl2RHA2SFlVSXF4UW9jdTQ/JGxpdTV4PDR6O2AKeldXIzxBeH5yZDZNVlVK
QTltWm5FYVhBeipOfUEhcHpZVEZuQCg0SnFPd3l6SDxCTEJlKHZITmpCdFFoa0NIZjliCno1IWZq
Q0kxVTJhcVNFJT9ndyhlemRNJHNqJGcjelY8TnhVc0FBYStMLU5re0JAdiUxaG0pVzRBQ1ZBVW5p
WDN+RAp6VT1BZVRQRSN9V2NZbz0hQTdqQnMmc2lmPTJIMiFQSmJfPCZ3YlJ0PHJuRHpBam1UO284
M3JsUmtQMClSKWJudWoKelRVIShyenRDJDk8dlE0bGYlK3hLZiFCNEJZJXBsVnp3d1F7NjtiP0tE
UTB7THZIWUhBWUs8THU/SlptMEQkUX5nCnpASUgzVD07cG53YjU2eXZUPUhxSXlsJnQ2MEQ5Qikk
KkFnanBRaiFKV15UNyNKaD5IU1AtMyktPyh7MDUkVG5OeQp6N05teDdHIzxnKE1CS313WEtUYClD
SzgrLURiUGJRc0UmLXdXe1dFQndeeEFoTXE7U2o8Zm9IMnYqUnpVOXJXRmsKeipmNj1UT1ZAUCom
VF9tQ2x7YT5raCtve0lEWnA9WEJ0S2U7RC1teFB1Zj1pa3RsfjZQJmZlS3E5VDY9YDNtO2VICnpO
SlFhaUNnSHhhMXVDfHFNKFJFcUBMfm1UYUEkKWNZUzY3VkZFP2BTeyUwcll3RHRUKXgtakY/LX1e
Pn5fS0l9Xgp6RGpSPTtNK2I0PFB2TGhIOWtNQXM4NXhWP24tWDdJcEx0U3RvMjdnODkrRWheSz4y
UF9CdUF+b3lCPn5LJDdGS34KejJEfkRYd0tfN14kNklQcCZJU3VDQ3RBRiZtWFYmI2l6UXljbGVn
MUE+WnYlMVhqJmB6ZWwrfVpCbERsRmA/ZlFJCnpuMVc1bElgLXE0MzV1UENiKDFHTXMzfjRZdmVX
JHdzQH5WZDR3M3dYczEjaDModStxVEV0Yk57aWBgSmxFeEZvdwp6SDh3YUBMeHx4fDdffEkwN300
TFIrUXBKa1l0aDtNUjVZJDN2X05VfFpga0F7Pn5sUm1nTGd4MD4paClTQkw/akYKekY2Q3dVNXx7
WGU/MF9lIT9qc2V3KkgwLV9qa3ZqZjtCbD56PXU5eEteKz1JSjE3NFpCWTVke3MqNnM4T2ErSXJW
CnpleGpaQWpUQT94N3IjeiViYlArNU9wUk8lYlkocSUzVlNyLSlpQmFYb1p4NUB4O2p+e0crSU9L
IzBobG1paWo2cAp6NmxOa1JRfEVuaVNsJFdPe2goMU91YGh3S1d4ckV2ZF5+I0JXP2A1c3s+OThR
SG95RjBDN3xBbEQlIU1DXmx2QWUKenpVQ1dydHoxKjFpPXxVemBHUmQ/SjI2cThpVzVoV0t5dVky
Xk91P3x2Xm1rcXJ2eSs5ZnBBS3glOUdDZEN4ekxlCnpUO3goRE5sSTt6VmN6WSFNTns1TlBFKHtO
MkopOU5JVUQwbGY0YlBLS2VZamhEWn0hb0RlNk9Gc05jQUc2KHNyRwp6dF45QXpEUWNOR1F3bHMh
TWJ3fjNoKCpDcXkyPFR5OypGVHNXTGNQWFF1NzBVRyhxblE+JWUzXkVZTXRlJmF+Ty0KelVWISh+
N18tNCokS2ZWUEhfeDRqXyFrSlMrLUBNSnUqV3s2UGpIJDFQKnVpaFBwUmhldVBURnI4LWp6TlUz
X2sxCnpBbi0heD4oLTBXS15mc01yM3RvfChpal5iciZoVSoqQWBsNkFJeyFGMHBAOTBhfCtUaiN5
RFo3KnN6O1hORS0mSQp6MipFMW1qYzd1VGBuflpWXz9OcmNlNSZYKFJfQ0FWSldKTGAmdjFBYlpN
bCFtdWNURlkpUUoxPit7Q1htKF9NUSsKejR8aj41YHhZIV9AQ1BNfnxLOW5CZkBxUCNyIT55O3RJ
OTA/PEQzLVhQVE0xMXRka2Ataz9HWSs8YWg4JlNuOWxyCnpQSn1rP3kwcGd4VDlkTDgqI0N6MkNn
ai0+Ym1XNkQ1eEM+YmwoV35DWkN5LTJVN1MmS0B4fGo3d3VwPUslXms5aAp6O3UoNDUjI2QhPmt8
JHY8cjdQSGBRZmhfczlsP2dGcHsmeFI1MFNfO1gmVChXeXRoK1gzTXlKNE1YUyVmd3IhLXUKeitB
WFgxNnt0SllpWWNxQDxRMCsrbytQUFV2PT9yWEkkVW0rM3ZaZDh2OVptM3JETExSRGZXI24kV3gj
VDI0UTNeCnpxQyEoTTJCcUFAZ1pTXnxhbStYRDQhSTVHP0pzMFZsQ3slIXxIezlHV2Q1cWB3ODR9
JVVBQH0qSk1+NHV5IU1tUAp6Y15pajBSclN+Vms3YTBeVWxjM0dlKmd8PiM5ZVl6e2UyVispN3d2
M21HMyZteGNZNFI/Xn58JEdjVlAhSXpSa2oKenJfVGNedCtYZmR2KiswcFJnNFA5SjVGRXJUNGV0
YmRZWSl8I2REUShtISllP1RWT1FFYUc7YnBgK1AhKUp7aTIjCno+PnlyTHNsenY/JDJSMjJWJDhX
fU9JK1J1P1BabWo8LSQkWGR0UzFZNCk8cDUzd3stQEdsbEZqWHlTI1hVbl9iaQp6NEN5P1FiUTw9
WjRqTSgmKmw2T3ZsVCNTPT1mPDxAeUpLdDgqel42Jl9PZyFiK0BuamE8fEleTlVpO2c9a3l5JHIK
ekFWU3BqR0ljdG1TUWdUcCNWJHlaPVgzd0ZFXlJVZUhvblp+Ukh5YHhIR2grX1RxbkQqM09rdmNW
d15HMzhFTWFFCnpyYERrN0hYUyM3RD9iWGxoJj8+ezw7ajhRTzRQOSQqUF4+QXNIcXdVISlQUXle
QnprRDN1azs4IU5xUl8we0BWUQp6YWlZcyRiP0JlTHspZigmWChkWSUleVY2dDR6SnomZl9rTUBB
NXVvRG5Ud0A/O0xFLXdNT18wJTw+fDdoU1M7TCsKej99Kn5kZlpYKEV2ZmxmN3ZIbHF+Q31PVEE1
QiNIVHNeQ2NtNFhgSDZ8RklIVVNVek8rYDwlYG5RP2Uxc3lfbCRmCnomSEdpRDJUc3UlKDhnVjwz
VEspaXg5UFY8UGxXTTlgV2d5UClTZXxPN351eiYyQSY9e1U7ZjtoM35gdFh4RTJePwp6V1YldCUl
a3o9e0dAbysza0ZKRFVUe1RRMFBMSndHOSZDKFZsLV5BR2sxdkNiQ0xZUDZQUFhBeGVlUzFPaEAw
a2IKej40fT5Ed2QmNzdffmNJSyFnS0dibF9LSkdXUWtyYHpMPkZ2cklPfTYxNSY4RVhqQ3liJWJ1
ZSZPQClQfGV2P0RlCnpJcDJ3ck4wQFZ+ZTRjSnd7M0NPQGQ9ZTY1ZUE8dVIoUU92YG5MLV94dFlj
WX1NaWtOME9Ca1ooWUtNenlHYFA+egp6bnxuSypaJDNWWkZXLUxsRE1oaGsma1psZDRSUiR2d0JT
RzJmN0kjTntyYypzeUF8e2w+ZkMkQVFpRHcmKCF2I0cKek4kUjgwYWdwZnt3IWZkUj1qVS1wQSkz
VXokZU5fRndoVDV9XyY7I1leZnhlKnFjRSQhZzVSai0zc0pRR25DczhGCnpxbiNNOT89fDVIdzUl
cmglRFc1I05yZDltTV5yZyY+VC19UGdtTTRqXm1WPlRzPkA9YiFCMUZ8SVUkI3twY3YwQAp6MWti
aSFgYz4tRChEQG1hdTVzO2VzZk84IXc2VklWMmVjMlZkYkhyeSNKSH17QVM7ZnpyVk13Ozk5dzlk
d3FEWHoKenh8KXFDc0orZWtSZ31ifVJCYjhJQEtmKj5JaHBhVGY3IW5+Zi05TUU8YzxIVzQyPzYr
Ul5tYXJ3X2JfU1VYJndRCnpqM3B5UTY3UVI+QEl3NGRnPmcmfioqfDRxaFpGY0pwTjteSEdrQnQ1
TmlaQXBjemtwQU83a1poaUpOe0tqSz8pRwp6Pj92PTRAOGFnVXo3YjRCc3BOam9DMjlwMFMtM3x7
LWw8aVk1TW5wV05tMHpJR1VvN15IUE8lb19lKmc4KFByVV4KeiFlQVl4cC1AMjckNVkpTmpWKnFM
Jl8ydFItLV5BJm0mditIY2s/MmprVWhmMGtZfHh6UDUhajxvM3hKMVlsc1kpCno/KWBVdEA2N0o5
ZEZtTUVkQEBoIW9SKmhWc0c9ckc4NDQxQm43Y2QyRzkzOz84KjN1Nm43Vih6clRrU3Z0RTVrNwp6
KzFwRiREXzdXWm9ieS0+eXQyWFc9Q2FVST5EMV9RbTI7a1AleXEpR2Z2MzBBaClzeDZaVUtDWGwj
VUBxS2xXdVIKemgtVzNYPm5CbFU4c0dYKnIxUUVvY3lnJEV3STc2YmJqZDsqMiE/REtgQ2YrXilD
clpMQzghU1NkbWdNa0RBSyRJCno+Q0IydnVwSUJWNEdCQntsfmtgSipTTlZzMz11TiFSZzRVcjJn
fmApc19rcHJAfFBJenYxSDl1QHN4VHxGRiNTJQp6Jio2SmsjQHQ2eTZDYFpLaHl5TF8kMjFhPTMo
Mnh0YmpDNmNvKigkYWR3PU48ejtwa2JvV0wqQV5iZmY0PEY1WDUKenk4QyhANn4hRnlIZUJDKWtg
MEhmWHU7Z1I3eU51fEBfVkE5VXRfflg5WnNgVyp5RUtTb3BPSFpFfUo8ejk2UyRvCnpodG9IbmFL
QXFNNT9Zam1PcERlKnokMUQoREhJPkk+Kz5PbjNTPTZPSCp7X0MtMlJ6bnBTU0JHd31XOypeZUdm
fgp6QUdiWnhFPGJ0TEBqI1JgN2xtcylreWE0fiE/PHM4NnlsPyRfQyRTfG5LfUQxQEZJSD5nI0FV
Yzk0YGx0dnQraHkKeih5QGxHV24qfHw+aTNeVz5ifSQhQzRETUlsekFPZmZkTW5eR3hHNzg2JkNn
TSN6dkxYSmEpM1FGTFJOfSlyTFgjCnpgPkE1MnNnMyZycnB8TE89aH52OGxScChsY0pGRjhhfTVA
bkxwZDNZbj88Yz1AelNoU1klY0IhWHVGJmZ3SSFYYAp6TDZHMktQb0xSeypLPn52ViY5O251VUM1
Y087c0Yxaz1qcnwwdHw5cl56byp6P31BO0NQWEs0MTAqeF41WVdrbUQKeisrLWh4Xkk+Z316K0hz
VWoweE0qWiRMMDxnbmk7P0E8VCZkZkh2eSkhJDlgPT97KFZ9SD5JQE9JQm9NcD1uQTtpCnpndVUl
VF9teTtoYk08MzRteDw3KlkoejxTPG48YCFSMylCaDdeYjJhV1hTOVVTPU9jRThSMzJAaExIQk8x
fHxKaAp6RzNXcEFrRVo8O2BtbnBCYVd3Jih6Wnltfl4/TEslO2U+M3NGfjB6T0oraCF0b21TWSEp
aHpLPWtAbj1ySFQyclUKekdsfCV7XnRUUFgyLXM9PiFTKmhJelFwdHBMSDxgSUlZYj5ucnV2WkIx
VFRkRjU5Jj16Q3gzKHF0SUZxeUZBZzFGCnpXMzRrYXNsSH5mX0FeVW50TUo1eTxrKz82JHhuYHdK
I3QxfWVtcnVYUGhAUTM+MXo7PiZwO3FjbndtWj9eUlJxbAp6PGc9NWAqUSg5aFg5fDZEc2dhOSQ2
NGBlWV97MXBSc3spdXM7QUprXmN3JWEzZ3N1TW0oX00xdzg9Zz19dHVpc3UKeiE3SkdOU1lMbFE/
V1dMWUhZRTFeVnJJNGN3eVl5SGpQa3dha2wyZipUYXJJVWx+YXtAZlZEK0xoRDtLJmVAZkdGCnp6
MitNZXZ2dGJrUWklOWxjIURHQ3tHPHhFYlo9ZkJeQCE3ZkExSzJofEhIdDBvdE84ZHBmdzJwNEZO
UFNfUVZhXwp6dT1HQGZXRz85KWA2Yz9CeytZdWljQllEISt8bFVlIylCdys0YjhoUDk4QmgtM2A4
YkclWGcmJS0rRGt1ITheTCYKekU8Q2dxOCQwQ3hQN2JHR1M4fnxyZSNmSG9HOXRUbT8tUlkjMkZG
X0xQRygjOFo7ZWR9fDRrY0NMbVIhXmVQNWxlCnpxX2N3SE1iK2tQRDVCemJUYT48LWt3RDI2bTEl
dFFOeFMlQF59Sk9wPGQ4JSZtUkoxUnNyekYtLVMtZDA7JTsyfgp6NiRHNDFxcmpsdnQ/TmdBeFhD
TzNlWUUhJm9vdDx4KUJPJFp5bXZKU2xAKlFQRlhWUUF1ZUkxPVFoRWlMYzRETnUKeitVeXo1JWtN
VXhSSTkxZjk1eCFkbzhGK0BxYGRvMCpOS3ZvcHNqSDN0JWx5OHpfKG5HWE56OzFuYEQ3ckpecyEy
Cnp2KiUoYVVIYlJUbC1iRUdHP0VSYUp6dnl6KGB8d1hCPG1qWjU8RVZ5Uzt0OXo7QnBEPU92U08h
JENacGBqTlYwXgp6NiVfRj03OHxkTDZoI1V7MUJMR0NnMnhrb15ZUTc8P3Z8ZG81RllPaWlFWGRj
SlYyYXNtJXNSN2ZANFIzMHxnPnIKekV0JDZ5bHMtPntkIXshUnRrLXktZTI7V1BRMFhlSTReUz1f
S3VvfCp2KUFeUTNZTHo7MmkyPWpSUGZubT4qJSUqCnp8TXEpKjBOZTMyU31NajExPCo0bk1fYjNH
ZUNjJUU8S15BYD9aX348dnA+fXlDajZBfElTUk9RKz02cVdMRSY/RAp6a2dyMFkqSzRhO2V9ZEVF
VzdyVDU4Sj08Ul5WZ0F+UDY4aDdHQztRM3txfFdIWUd5VD87czQ0dz5gYkZycCU7fnwKenpvcV5I
VCF9VXdoTFB7STZJb2hlaX5ze0hpZXVUSWNqdXo+cDMkWFB2RTlmQ3hkamIkUDBMIXFXTypHWGBg
OEN8Cno9UjEhRW5hRjtaWCZgISYzbW52NFg+eSp1Wj13LTRneF8+Zjh4fik8LUE4QGZ7PDEhd2F+
ZUM/JVZLYUJIOV9AfAp6TjtyeHRtR0d2US05TXslWG4tUD1XNF8/T2NYPmg4cEM1K15gYGt3RzY5
Ujdpek9fVUhlXlFaYEBNaHZBfDlwX30KekJASjhMYlc/Vjs/cENUNW1Ge2FFeT0lb0tiYWY9WHhB
N28ycXtyTT5XQnVvb29aLTh7XklWK2o9UjNTZExjSUorCnp4Xk1IblErU3U5cGJXVDlSIU4jUEB5
JHZlS2hDfXR0Yk4hMHQyJXMxQk1NMVJxWlJoKSEmUHAqbW4tXmlDeytycwp6JGd1Nll4YWM7Tk1F
fWUyNV5eMUB2eSVGaDZ6TU01U3FzcXUmdjBGOC04Wk17aCl3JmlXX2UlQSlzO2V9ZC1GcFkKenA2
YXFPTXh6emRTK0s2TGNRYkJaaSVufUwzcChaRnIpUmxWIzZra21aY1BvWEQwYiVueVAmPERUQTkj
M1dGTlduCnpwNmh6Vy1OUThgenszIVVQbmpmZUlqQ3tJMHMoUFVWd1V4aER5aihidChvc19mcGw2
KygjNyVMaWVufERwUFp+YAp6N3lUJXohJjRuMUdRbkdCeik9aSlZJFFYcC0kOzVeVmBiS2R3Um5n
ZFVVSEdHd1FiV1ZqXko7MihXe0diP31CdTQKek9Xc08qZTZ0R05DUjE0YUl+I0ZMKTNwQmpLIWwt
O19lem02Zn1pYDVldlVnJCZaaz9EVVhJazN7fTE7dWErQ1hvCnpTQUlCc0VLZVZYO0oxKXtWRDR1
RDYpQzFfVyEmPFZwSU1vc1BGTzQtKXc8RlFrKEw0Tm4oPGA0QmJmY0JKZjEwSQp6SyR1REt3MnZK
RVBLPFhlTlNjRytMRTV3YjhxeHlqVkM1R2Z6N292fnBxaz4xPEJofEVURVhQVlh5dVJfSUlqaFAK
ejF8Qz81U209SSNjY3ItYnMoeW5uc3YlT0pRekR+NzNta01yISFocDNkeE1hbFl8RjJNdTx7e3VO
Kj5FIT1kZ0w5Cnpzbkx9WmIrRnxgczJYbSR4WjFKIStUVXpOPH1vS3AyIV47elE+bWJAUyUkN05o
SVB1cmZSQj12VUcqVjtEbS03TAp6NGJ0SV58Rypxfj1WUmJjVDAycW5uKUdHVTU/QS1NI0c5aExI
T0xiMURnJF8zWSU3MHRXVU84WjQ1cn15SlVPMnoKenNfMmNJN0d8IzwodC1XP0E8a2tsbWVHKT92
fk07dzd1dShVLVhofTMlWEBGbldRWnFsOCUmLUx4JUg1UEBZeC1wCnpoQWhYYXE7fiRPcVZiKy09
QTJMTzh0OT1UNypZX2QpR0c3JlleSCQ+Pm43PFFkT1ZhVkBKSVVRdWZmVlRecEc+Tgp6PT81aTdx
YEdBKVFyRG5zVkEoU3I4eGQkU1BXUmBoeyMlcURULTBSTThnbkpaTzIxPjhAUmQycFMkKDcxdV8j
PHUKei1KR2xZb3cwZTV1YjRaYj9vV1hFK3gzaTRCKGp6Zih+RTxuJFNDdG1oRGVPcHFxN2ZmRiVa
R0pwbUBjMVF0ckM2CnpDPnYqKWZIMEk/S0JOfSt2KnUpRFV7XzxjZjEzNiNpYnJpQlB0aHRFbVpT
TlcxYWFUaXd4e0w8I35rOXdxb20xJQp6PCo8TW1BTXpkMmIqK1JxeWAyOF5EZGNxPE8lNyMhNnAx
UnIxdEYxezQlMS02UUc2PzE5YHdVPj9BPEk3X0gmNnoKenF7cFpiQzI3OGdQWVlRMj5WKUckWTlu
ej4tZGdeQj85d34tNX08M2h3eHM4Ymh4OCtYdFplPGBAViVfM1RIZ09sCnpTNGQ9bWFVZHFzK2JB
KGZ6QGZ3QU9JUmckdzhPOVI+YSU7QCszQVI9cUlWekNJO3xHJnU+ZGhPKmlNOGhTSUYwVgp6T1JH
Ymg9VFRxR188aXNOPzU/d3VNNV5LTkpDRUY8Q2lDI1M/RkBrMylJfX02bV47cnMkRFdDTVAtamhx
Sz5lZVQKejJYNCp9ZmxwMiRxQn4hJGUqci1He3V+XzN7REwrbiYtcm8tTmBBe0Y4d1pLRlQ7OV5e
RDg5Xk0oWjdwWVJ2aHZvCnpCUzttLSEtKDctR1Jiel5BQV4wYCpqQ0VHenU/SHoxX3dlI0dYcnB2
YE43bDAjTW4zVXVEbjgpcGJLaUEoa3ZtTgp6Tn5RWn5Bdz08ZzNAaiVXTHxyUWYwaXkmT0khMU9j
cGJAOEBFSEk9QVA9ZSpfa01jSkYrP0pQUWIzdiRvPncwKlkKenF6Knt1aiY7NGduKDBnSHtWXnxk
bF5oe0hGKUNmWjF6eWFybHMjJDQ3JXhaaVpiJjVLe3EzdzkwTDJEXnpwN0tmCnpjd1NhTWp3KSlm
dHNfJlNBVHFoNWRhcUVadSEofCNPSHIzO3lDfVRSVCt7U0ZiZ0Z9e093alY3al9CQHVoKzxkQAp6
MnE8MlIkZ1IobG5YPDIqPyZEK25qSXI1fjR7fG87anZfVlN6X0BSV213I3gwYDxWO29II05CUE1C
YU5LJTxuI2YKemtrayowV3Z9IzlTN0txcW9wQHkqMFhyNTVjXjYzWk9lNXRza08rRjU0e1Z4Oyhe
VW0mUHk/ZzZHVzhXemp+XlBwCnpSMDEwTzh5KVdQZlI4ZVRqfEB1WTEtY1Z7LSY/aCtqMGF7KFRS
ZGdNITkrZ0QrbVFBKCVKfksyNXdCQ21LRkxNfAp6ITFWd1ZwO2ZhWWY8SXVJSV9EcDcmUnxgRzBF
MDlJJm02OSt7aXFMVDw4IyNmeyh1QVg8U1A0bFZ7NCQqTEZSPHoKekpRUlo4ZzlMZ1gwbX5yfmVa
dHkoWENFSkd7JjYqN2kzUmlEM3pBXmFtMVdqbUVsbWd8TSl0Q2UhSTUkIzVLcTRWCnopNGNlVGll
S2ttbX47P2lUQUktTmE5R1pfc198a0QlTVNvUSZrNXJwM2YoYEYqWnlPcz0xej5EMH0jTlVgYno5
IQp6SCFBYj5yeDRRWjx9MGk1X2RuN1VhPTd3JURAK2lTYGZ3MCEhKz8zbylJbkwtb0JKUmk1Y2RE
KCVvQkJte3pyeD4KenxKc0U4PHBBdV9MbDBlRSRgcStYPj1sb1QjPUgrbCgtZmRAU0stZDgzR3R8
RDk1OCRDMW01Sm1uUSElTlNyYUAkCnpOYHY8OGB9aGJQeyFnQmxuXkpJe01mPSEtLTJKIVdYamJW
fSEwMk9LQzhRQHxHNkR9bldxNGJkUD8pKGQrWEUwWQp6bkk8aX1RbD9+I1pUSTc9NkNKJUUlYExf
Km56fXAlQHJQdXBGeSozNVFFPmpCTn1OJHBjTi11MlJrenRRZ2EpZXcKekVTVXtadiFUTTlaNCkz
cHk5V215TTVHdHxjcD4qYzByUWQ4RjZxckI/TFZ8MlI1SUJpSHQ5K1olQDd6NjU0dks9CnplO2oq
ezk3aSRnUmsmNnwmekY7cGNAX3d2TDU9bEgmUFg8ZFl1PiFwLU5WK2dmPVI+NUh8dyZ5OEFofnoq
Kj5HQgp6NDVUdEtjUntgcnk8RVNOa1ZaPnBYUWxhd3l4U0R1JWU9XjJDMiszeldqKlhRM3QpP1dZ
fismfFN+MjNgKSM+WUUKelR3dWBxMjM1ZnhaLUojPEojYUNSemdsTFh8SzVMWmpqM1lmOU9ldz8k
b3VEZD5INDQ5ZGdvZ01EbktCJkBJMHpDCno8XilAaFQ+bnVWMXtDa1p4JGBeOztadGAlRVhXdXZG
ODt9Q0tlQz1ZX2tzP3J8OHN7TCF2RXxqKzAyNVVtPGQ0Mgp6d3BgbCVLU1EkcHpuK159ZW0oe2ZD
SCpSezN4Xnt3bkUoZnl8MTBUSzFFY1FIJUdwYWYqRnZCdW9+SDJjd3whUT0KemZWWDJEWmlTZnVX
ZVNneXhmeE93SyEpMlRPNGd3ZHRySnRsfDZRTC1TQmhFK1I+cisrYT5GZ3UwfThoc0tabWpRCnpX
I0I4S3VGdFB2ZXwtYiRKYEttbTIjQkpnMzw3bzNeIyRDUHw4QVp+d01zen5jQShkJFN1eWZFPUsr
Rz41YkA7aAp6LU5reD9NZGAodHBUeUQ3bzUjeiZPN0JzNkM4KFFsb2dAWkchYE1McG12ekRjI0dx
dyl7JG1sVk1ncylEX1ZsJGYKelFHbDU+SE58LW5sPW49I21HfCpJMzhhTlA3Sm00RE0oRzhTQWcw
dG1FWG8rLWQzUHYzYTx+alZkYj1gajRGVHZ3CnpASWtLeUstM1M9ayNlUGprU1AjYEM8YkJrT3dq
dzdaRFlvOVRIPzN7TUVnbzkmWU9NXnJUNz53YTM5Myg3dUFTcwp6U0YpX05EQ3MqSms9bEt4KEwm
S0dRe2N1ISQtKyRAUl8zLWRtallNeil9P1RCT184QnJycVg+b1V4QHdIMkBwZykKens1MDM1e0Rl
STE7bHREZTBGJSNtaFJ9OVBeQGV6RzRNWik2NHFkdGVeck5KdCZtQm03cDlEQmMrX3ZmNGFmJl5A
CnpwWn5AQWluTjImSCNPOCoyUE5pTHIlJFAtQmYqaFg2PENLQWI1bk90NjwzMGxOUSU1SmpXMTBM
Ni1ac1k7JC1tPAp6MVZEenA7Z0c7NFEyYVhwJX5zR2dtMlYyUWRpSm1lSiNUeW41TnFEe3NLX3hA
MTcpUjFNSCtUOVNSfWJLZXdLPyYKelBEUztaISNubjtgciRKaVItYUZCZE1LZTdDMXAqMGNVXkpI
NmI9fFhERlFNVkxiODJtclUjeHRVMGg8fVJWTUtmCno9dVpGLVhUe3dHTE5JbDU1WHIqTDhQKXg4
RzE9SWRGKE5laSR7Mn1yPDxFdV9hezEwJVMtY0dzVl9CaW1RQUlSXwp6QT5IeWltY1JUSUI7aClE
WDMwSXRHcnBTd3BVZ01XZFFfNGVzbGlBTkdpRSEhYFQ4WH1QTlI7TztLeDJRZUJvQXUKenhJcUlv
R0pmOD8yVjZ3KEc1cVYpMEJPMTNeXlZKYWt4PXdiIV9MPFpIQ2p8VzBuVztlVn1uZzQxQF41SjhO
bEpGCnoyYSlNfFhKK2oke1hHOzxMXzJtbGJsZFhucWQoaWR7QHtoey10QGUjYGlnbmNvZVM3S1B9
Xjl+dTVWeUkqPnpqKgp6dndLRHRAfSQzfih2NGF1I09AYFgpXz5VN2AlIyNQdW8hOHYjIXpsUTNo
IWdEaXl2fFRsfX1MO0JkJHMtd3NaRiUKelZJaj99eyo+SjZRfFV3Rj9ndD52WGphTUdkWUtOMzxm
bj9qZWd7eSk9PGd2NlNwcjlSdGZ3RiExNHtjM15PTS0rCnp0SGNtVV5HQyV7SHJmJEBnT1EjRDhD
MyU4ek1kTmMpSnUqe082NnAybkY/Zm08TmBwc2JURjJCK0wkcjFEMmFqTAp6XmdHcXVoeyhaJT9V
TFZiMTtud2ZHQz9Jemx9RzxAPVBtTHY5PE1qRWZYTWh6ZUlgOTEjMFM+NjAwfChxVk52dHMKemlM
QXpGUUFNXjxBdVhUPT9DYDE1PzVQVmszPFMkbnRKMEdWfDJeYHlZWD9nZVBsUEZIZEE4MlhudlZO
bG0jK3BxCnplITAxIztNKlFYTzhzPUA5WTxhVEZBPHklM3dteENrOzlUXjt2Z3hxRDx3bStOc096
KkBqY0l+UDxvQ2VjYCRnKgp6SG82dk1ZS3d9SmgyX345ejwjTE5PXjNBSkZyfjt8aFUkd3tpS2Nx
MXQlPSN1VjI9cj5PR3RTM2FhZXc0K0BvU3AKenZQWlI+S1doO0pEYnZkTlo4UCFiYWBWeDJeaj08
a3NwJFFGZ0FYVkBsLX1XR01YRWQwZU5heH4rcS1vYVhVQkllCnp6SCM+My0+Y0FFNWM4N2sta0xs
Y2o0WFBnJiNafnpwZ0deQipaej9DMDBhLXdqP3RKbXZoSDw1ViNrV1k4Z3QpSgp6Z34xSTxURy1h
OUE/NUsrTHJmTm0jTnx9UjxFcnBTalVqKU8pbUl0X1FQUmR3blRLYkx1SE5NcnlRPHBGR047QEAK
eihZOFNXOElRPXktMiljbilXNWYpb1R9KHxScmImQmBRKnFeUEkjIWtQUSZJezd7XktlU209Mkcp
SXBGUll2QWIrCnoxPT9YTCpUNzA3X21BfUROVWZrQj1sNEdKJk8oV3VKa3NIU084MFZ2ZDI+TVct
MGFwYjB3XnFOd2ZrWFJBPT1ZZgp6NntWalQxNWpLdHVZaGQ3eFJFMzgqWEA0R0VeblMjV28raSte
O1p3PUs+I1Y4cnI+NyVvc3s+S083QkF0OUNma34Kenl9VERlbHxsbmt0ZWdsZzB0O0UxVVhWU0Ff
RStRa2JpQ3lGdF5uX2UkI0paWT1JOUB1eXk8ajE0K3s/aj1yfHlNCnpHQz0mQVBoP3thcEtzISVS
IXA3YTNrQjZMbkBmXkJGdHsyZzVgKHl0JmEmZ05YViZvKXRrdXhBYX5OWVdrbEpQTQp6KyU5cDxO
VUhMV0xpKXM0amFoaDJufU9+SDFaV0xSeTBYdWJBRmpNUkF2Yk9NQD5IYkw9PG1kaHc4KUJuQypq
O2QKeitZVjxRMUpIVEI4YU56VUtibGFKKEZjNj1qPyVYU0w0MkRKa0hJT2RoYWMwKnhMMG0/R1V7
O3YtUF95Y0ZuQD43CnpLeEFibit1d3NneW9YVXw9RFgmMz0rUERQPFQ9VzhLZnJscStqM3VPWns0
UyQwJVZAbnBoa3o4VTxxdWEhVWJBbQp6cFoobEA8QmJZZk5MWVdnTUQpVUFrYy0yYHliWCstSCRB
V0dmelA2N3xBcj0jWn55YSZZWT5TNlNma19jV25RfDMKekxTMFlxek1FKzd5KlE2NGJRb0JseCpr
PTNXKiVMdTFlITVmVn51RzRYa1luSW45fERmUSVgKlJDdWN6SUktcTZfCnpzNXpUX09CZyVmbG1h
PE5qcmhFRXQ9KmlDYm1CJXY8TzV6cE0xUWU7WEQ1bXheWmNJfj0kSF5SK25SKkZjeD88OQp6b2RU
dmFpb3V6KVUqcnNwQjNlaE87Ymg9WiZxbGdWRFMpckxGciZUPCp0T1pMTilVIy1OcCp5aGJwYFZH
XnI/MEUKemREQWAkJiNpTz4rK3UlamUyfGNNMk85OT58MmBERCQpME4lelk1bDhKejZqWUhhWTcx
Si1DUW9fSF5YSj9VQkFuCnpUbUlSbzFHQDhWUXRldSlfdDlKc0U9Mkg9aDs2ISZ0PTlmQl5pTTNe
eCNocDc2VWV1YldFZzF2PzttU1A2cWpqPwp6SClwTmAqY0ZZJiNlcW91S0gyYiVzLUVge09XOXRB
JlVxK25RVEhGa19iR1J2e0BKWmUlRCVCTHhsPjVocDV9YE4KemB3NTZQJn05KV9KTUppe1FWRW8k
Mmshb1pHQHE7dWJ4KXRKbV5iZ2pQV1o4RlFhK19MaDh+ZT1NQHMkaExfLWR1CnpAI24oVm1YWkBC
fEZfc1BvN3JzelA7P3hadSRmN01VMD5Fd1NvZ2pXRjMheSZNJmYqcSNTMF5MQDFEVUJZfmFINgp6
dTBrMyZUI1dxNnMqfVRAVkF0Vytve0hIV1FAT3B1RWspb2IlZVNtJHdpeDd5bD99aTxtRWY0NCE9
bWpAIWtxN30KemAqTzlacVN1eGZwZndCUztASkFCUUw9ajhHcihpcmteX15nPmRiRz1kJVNzMTxH
K3FzNnhaVE9kcDF5UHApP0pOCnpPe2khJkB1MTFWKWlkdjxreFIxUTYoezZEd1ooMmtAeD4rST9A
WFgqVHwjPC1FbSp0O2F4RyQ1K0IjOFgxM2JEZgp6TDM4YipGNWluYnEmUTs7XyY2TVFURlJke1Az
IVF9dSRKRDNYKl9FQTRIZ2BqcVZte3xhWngyMFBpWDxofDlRUTEKenlqK3N0SzYhbytqMiheU2xA
K35vbF9XTGgyR3pHZ0Q8JnBtJCglOT9KIShlaTB8ZEVONSotY3A5fEg1eDJVeyk3CnohTko7O1Fv
eGp7UGMrNVAtVHhaRCFNIXgxZGYmIURQfTNyWG1sZG9wRjJTcE9vT3BJVlI1KSs7Xyo3M314fFhP
aAp6PlpLYWxjVytRTElLUTVXbl5PRHZJfTMpd1NCRzVoZClAOU5iNXRnXzwyTlBucTR8cEJDblNP
WGVLPHspYmF1TE0KekVpem0hSnxVTldVcUNybXcwYnBSKE5fKH0rOSg1akNEfkhCO1FkMFp8Rmxw
V3Y8PmxwWFBRZX40cHojb19MO0hRCnpaMSZkbTgyeDY7JXZfQT45Y0Q/I1NEU1F6YWliR250RFRo
elFyPmpiKWVgeyohT1RvdVFpXnhMeGtgVTEwans9UQp6Pil2KXYxRUoyKCRGQzQhV0d2Wk9Pc0tm
JFE9a15ONmxkJTZHJHQ9OHNaO3VzVTVTKUJrNUtPUTxKdFpjVSgzYXAKeld6cGRvOyVKV0FmTyk2
QjI8MVZzaFZpK3E0bnQrViQkflRvKlpYfSkwYDwjJlpja0VlVHB5KzdtelZyVHwyMSV2CnpsUmxT
SUk4VTZrbWEpUiFodEJidilvNV8xWFdiZCVLUEBVTnArS0pjLVFwK0tONU0lRiRhM2FWIzQwYlF5
WXtRLQp6OCkoZTtuaTZgPjRgek10XzV1dnxCT199KlRHM2ZnJX1uP2NxSWY9Wip0VW9ELSU3LUZU
UlhDTkcjbyl7eXFSI2QKemVQRE5EKXVtPnt3JDxtaWtEbkM0WUp8ZXNWdzl1NT9ObFByMisjV14o
ck1ZJShlRVk8SHQxIWpDPnQwVHl3TXV1CnpJTTkzNTV3R2MqZUhfbzgmPCZqNUJgNCZ3RTVaeXI4
fEN8REV4UElONFZDbm1JXlZMP2JXNzEkeUpfIX03WllXWAp6Wkg5TUJKeFZTfSM9LVBjWXZVQX1e
MjlUSG0hT2B6Vz9LWHYoKzk1WW04SWtMWnZAUUF7KiZWPm5MNjhyeiopTDIKeiNAb3pZYGVVSSpS
R1BPOG1rX0lPRDZgTEx3WXJ2YU8kYXRMVENycTFkYXtMakFtJjZXYDJUYyR0flhGKFVLPkB4Cnp2
S3xnZXA1eHpzMXpAVjRKRj0kSWltdzBuJUBEbTZ2YWdiRUw0OWtLUXxEZiskMWQrIUgjTlRHUk96
aypLYVh1Mwp6cE5xJHJreXY+VDspb1ZERW8rYjBAOHdwYCFMUk0lJFI8IzE3cHoyYWNwa0xZO3hL
c2dRdytaUmBqYVIhKERTekgKelU9UjRabkJCemNYTG1YOVlLfXt9Qn5BLX1WS1VyfiF0V28lUFl1
VWRZI3ZERjd1KHE/cGdIX2pMVGxLKz1RWHZfCnpzIyQ+IVlzSmJjPiZFVUtxIWdGYlNSZVk+RHw8
aC0hJH5sclJlKHRaT15MZTNPXkJjeWlTNGA8fEdTUjlKc3RaUgp6I1VLPGVMdXxtRCFWYjE8bkRv
Y29KZjxTWDhLeD89LUFtSDNeQ3dGbUgrREQ1Sj8ySDxoQGQlOSpVVnsyamBLV04KeiRpNUNrMz1g
KXYkcVpRfW5+U21OVVZicFN4VTlmQHd8e3dAaihxaHFEMkhjVD5GOSVRZCZ7UzNlKk4zUGtTRldM
Cnp0WFZUSE4wXlR2PFEqWV8mVkpwfXRueFhyKWhnKEVKcCtXP2MmQDxgPElAeHw2SjxMSzVSRWp5
Ji0+aE04dmV0Xwp6X2pWOH4+T3tFNUlQOFkodE5HV2wmPmVBWGtiYjheJFkrQXhvdSpfUXVwMl5j
OyFZQ2RCY1BUKmdgYiFXMz1AI2oKejhmZ31yNjwwY0A0ZmJ2TUFIeStXVSF7JEl2KjU9aG88RWRy
SUtkYVloOT0pYURXKHdYQlR9UlE8OFFeS0xQfEclCnokczA5VFBWNnQrKzFIPV9sJEBScnAoZVco
N2l2bmlvY01ed0UhVHRPZXpBU2F0TzlsKnhVNkl6OHpRcVhIaHpCSAp6MmU0a34mRChadHUlVXF+
WDA9dmxFUC03KEdNZ3t6UCs2aWc1OXhTMExDbzFwUmNoSHVUWEdsVjRhUVNEKjRndj8KenhAYXUl
KlczdVRxa0k8TkFRQDg+I1BpSER1aypGRmVwZG0jalVpdnJIWiRJNCYtT31LIUdyTV5zUi1VUVVl
Q2ZVCnp3VmJ1dEN3Q3lhV09HemFySkNCZHBzKnFheVEmP1hNdiZRRDZVbUliWSQtdFkkQ2I3JWBV
ZWwpNDhJSDFAT1oyVQp6TUl4Xz4+JGFfQ1NoeldCZVEheS1XT3VuIyh6NG53WXlnUGVGcCg4R3w0
fUNPWCh8Z3xWKUtmXmBLMVN8PkFCbEUKem9KfWB6Jmw7ZTdYI25yajsjd3g/YU5fKC1wQWsqYFMy
Mk19TmJ7eE1PQ1dYVzxUQTNVWC1VcDhFYGJEZzBgakM7CnpXKiVqPTFiY1lMITkoLUtLZiVkZHB3
UmlDdVhQO2FBWTEmYykjTXg7ZDxodGxXRnleRCU8Z21vcE9ecntgTihPJgp6JEcrVWBEcmx2fSom
amQwJiVPdF9XO3V2bk5feFlyQ3VaSilUQ2ckcCo1dDAoNWpUdFRLM1NqNGd5SF9TJmEtMk8KekdP
dXNra01mPkJnPnBqSF5yPzxkPEJ4WGs3cytnMklsQzZgalY9NFBhb2dmLUZZSDVhVUNeVSZUTSFK
Y19XSU59Cnp5fGdobDxIb043I2p1fjw4UExSQXMyNj9OTEAhXyVCSHJTVUhFdkBPelNEQ0NpTkpl
SUc0WmVMblJYLUdoK1JHUAp6Ty1fWChgNnBAYWlPfmh7U3ArLSU9MSlHZXpodipjSVFBKGNDQ3ZQ
T19GJXleakR7Ym5IUmgoaHN5NjtNYXo1U2IKejYkYzNtQnhWTWZAdSglP28mTSFYRmlZc1lCcihI
MGN2SjBtUEB2eEJiUHsycWJlZ2MwWlBGWkRmQ1NuRWU+VlBiCnplJCFTdkQyOTZ5QU1FbElWZ0Yx
O0lyRF80R24wa3IoKEtRa042YTxsXnYyWVpObns7dndgQilaYjl7MVZeKil0Kwp6I3FsaCtreFhy
KFFQe2xue3F4PTNsflAtI0VZZk89S208WUZlK04mTjQkU0g2bUwtRlJNUkJUPFlCXyorJFojdXQK
enZvUkt3WV5zQUw5NkdsQHljRC1SLUJIV2M7RElFRXxGcmUhWXE+Xi1IX314eiR0cU53O0x8V196
d3BVN1N0ejJTCnpPI3J8ZXw1OU5NSFN0QSFHfnY2cUs+TyE3e0hJXzBPbn0xOT4tWXlGT0dvWl41
ez99Qjc2c2ZrUCg4UDY2NSs+Ugp6KGp2PXZKbzVzdGhlJU4mWFFsYUp7Q3YtVl45IWtvMWIxWCtR
XnFVLUw9NyRMRyQqd2pJSSsqV1p+SCMpbSRVeG4KemJtRGohQWl1Tm0jPHJ5TVhQVjdadHVPMmV8
RDJ5djZiVEY3ay0xLUYtLTckZjteKXU3TFF5bnBPU0NQIURXUStqCno2MXhfXkAtKGlaPmZJcile
TzZBSyhLfX51N0U3TXZzdnBkTzM2QHdiS2V1TX5ScWgwUmlAPEtxTXItWFYpKE80VAp6UF49dGB4
QTxIMiN7TDVnZ1g0VGpYd3JAaiomSmAjeXdMancpK1c7Z2lZTlF0TWEraHFNIzFTITxlazJpalg4
a1UKejF6QmFDPig4fGJCYz95QzNlUk8yYUM8ZWMkWlVHT2RHPio9WmM4eThvbDRkOXM/fXN8eHVQ
bEFAV1Q8PHB3ayhnCnokfDg4VytpIUs4V1cmPCRsTXFnamRxdjRVV1NgWChLd0o2RSQlTWw1JnFo
PlIzem5AXkpSRyRgU2gjfkE/O0Y7JAp6T1IzV3JFMlNfYSVLZTJaUnwlU31JcWo/Y1k3SiNqTEZ4
UllgeE48YUF2fUQyTjQrM0s5Tlh4VVp2REFhYlZKRUQKeil4eClQRX05PEI4dEVfe1NWcDVCNSph
RlpwVChrN158S3xjRUlUYDIreEMpRXRGPCFNK3d0eTtKKUsqKy1kQ3JpCno5eD83TmUzV147SUMq
TCgqfHMxVXlgdTJeeExUPEtuMXVXSnMySDZQdUpfVj1NU1NWbjkzNVNFPHt4aD9KU15megp6YU8h
UTNmQiMzMWN+TUUwLWQrdTVHb1N3cFJLaCVrVyt9VnZHYXBfM3dXeDAlLUItVSkhUXZmfG59KiQ0
RXh5SUQKemApSkhJVzdXUEB0KD9QQCpuNj9jb1I1bHk3S3NleUZpKSQreVohbTU9MnR6SDtmVCsm
UURFIWFjeCo/YmhNTjdgCnpkOTY/ZTUrNTg/dzNNNF9YMT4/bmN6a0QqVGZsUHxqKkpKTUNrfSVi
SlRBVTlAKndWS2VkbDc4NHhjSGhyQDBMeAp6PEluZl5CJSV6MFohOFl4ZytDSTFaRWNhPCRAVDty
P2tJfCVWS05rWXdKcisoOXJ2PlhjJn1oKjdUVWhhQ1F5PTIKelJCOT1aMjBFUHtgcG1KQ18wfX1+
I2YpTDJEQlNIQWI+LWFDYWJIb35ANWVPcEpEcjNyIWFKaGdpcXJxJGBRQ2tXCnp0OGF5VSpzXzZj
dEw9fDNuKFBLJkZGQS1gO19kSyZhe3NPZSN3KUF8NH54X0IkZ1VecmtAVFVycFFMTXY4XyU8YQp6
NT5IIXszOV97JTFxJTt3YzlIR1M0bUF5SFNoRn5+RSRHQmhBOVZoPDR9P1VWIVFsQHZIdzlCN0ZH
UjE/ZyZyP1oKemZhNDNYWXQ0VHFCTW9zZllidn57SUA0S0lDKGUoODhwP1RQSSVfdE1HWGV5cG15
cmYpN2U9ZkhPWU9Hb2NeUzhOCnpxR0NmTCFRLW5IUkY3VTVaJDQ+RF90JEtARCt1LUY5MWEhXzt9
WCp8MShnNE9pYSVJTjg+TipqREpDO0pqRjAkawp6Jk9mPUx1IUg2Rnhedl5jQE1FezxVTn1eQihG
Y1EmZUJ8TCVye1JSSkQ5PjtFZEkqP2U9d0xLcTBsI0xzLXFWYTgKejcmenJ8P0ROQjVLVmdsM21k
d1hPXjs1I1ZsTHdGZnVhb29lcnV6Uk1gMXsoNVltYmIzJV8xQGkqJmB5XnBYfHNlCnpCVj1TfVRf
Wnc5QnItIXFYMl8wOUhyWnRGODc/MVdVKyhYOWArV2FgLSNQYyhiSS1aMntkflRqdWpndyNBN0dV
IQp6fEVTY18pMiNpU1ZZfVY4azE+NlhnPnRFaF5JPiU1JDxEZFkpbj00KGtyMTE7cnhHZGtEN3ts
OFgmRVBEWXI3QVcKenclQTs1O24+OVUlS29QNXBpe1kzYGo8O3xUNSNqTDxsR21kNzFMTS1eTiNL
c3M/diExSH1mSSNgdDZfKE1RITRnCnpLP2oobyFlQWwpMl5tRGhsJD4la2dabj02TE5jYDluU29O
V2JFOCRzQFJ8biVQVzFlXiFxfDdJQ3pyYGc+MWVoegp6UmpCeX5iTmVRVTJ3QWl3S21mbn0rYWkz
R0pRRXozZWhkVkpyeWhKMjAwLUJlNVIjWGBNfHxYXntFYXVnJCpUSHEKekw1KkRCMW9XYHE5Xll0
Qi1LdUdsVzRYTGwkP1BRWFgjbEc+RTM2KWQrUHpCSnAybylReXdDNlU/SkMjIUN6WE5SCnopJmNI
b2Awd0lZUE5ya0pWbTwxR0g9M0BqS1Y3TihpPDFSR3JGemRxRDVvOFI+Z09uQENBT2xSI0J0QV9H
bmE8Ugp6M30oQzFVTndNfEttfmtMYlhMPSZXcilOWl57JE4tI09fO31HYCZHSml9bnxPYjV6S0J1
YnJ2c2dleVdfVmFvR3QKemg3YX0qMUkyXkU4V0whcnMrZEdHTD81UDRZXjl9U29Kakt6TCNxY3ZX
VSRMP2hmNXlveTRsPCV5ZSorN15pfjdKCnpXRmFDVlkqZnN8Rnh6RypMTWNRbS1qWGhINEhINkN1
WEhELW5YTE1XWUxYP2tSWDFfeHVPK1deVyVCQXlwSTF3WQp6ZlQ2QXIwU34wd3lRb2Qrb2RZbzlq
SEVHPSh+aEZ6eE8zVWVNbF58WihQMEMpbiNyQkNSSDx5MVQmeFV1dTYlTHEKelBLb3Z8cHNZMWMj
bGZZKiNfcEtnOGBObXRHNXt9ZDMreD5xIT19c3E3PVVfOVIodktgbzgwN3BKRilVcnVqMHpxCnpP
MjJ7dz52NExqTVR8WXc8Wil5Y3B1Q1ZsUnFle2hBZWFUKVRTSihxRlRWSjNMdjxZTjszYVYyKWR7
ZmJzbTJQawp6Rl40JXVGYD0mI3soKGMlc3V1fmdOcl4mSXYxPE5QeUVTT2FKcEoyP3RweX1MeXRt
U0RqZm0zREdfKnhoOFB+NmYKejYrTlcyU3dtZDY4Rjt3Xj9oTWJVaHY+MFdiNVJ9R1hETD8yJkV5
NkxEVVNQMUI0MElGKHRfTTFmKjdRJHU1c1pfCnpiKj44YTxpQTFtVHI4WGA1Qz5WdnJLYjIkKF5w
WmthUTRFU3pAbihyMStmJVlPI304PV9tTnpzYSNTemNDbCMjfAp6diglRDtNN0V4PDhgKTRCcXoy
RVhDK0hLUjtPcGZhV0YjM35zbj1neVh3OW4hdjFhYTdUY3YodFE1JHlAP2NXWXAKejdLNmAzXnhf
bVYxIVFeXktKcHRnVUFCQlM5bW9Gc04kWD04MTZuMCYydTk5UFglUSskZmExNnVWaE95WWA9MUUk
CnppT2RDMjNhM0BwMzA9VzBtYDd+Uk07fWJad3NYSWZvIUF3Z3NDaEU1RjJhZ3BOV1YoYWdtan5v
Umo3JHoxWXkmcAp6a1A8Y0JrRlRHa0JDbyZ5eWc1IXlXdndqeE82fDtSLWNvfmRiJG5XfmJ0QkJ0
KG5keENYTyl5VWkxIWlHPSM7PUYKej1CdDcyQFVfVl80bD9Tbj8/Z34xeGN4PXV0K04zMHVAR3ZI
Z2cqU1RaYE8+YWk8bUc9dWBVU19hfjB1fCEwN31FCnpGLVNgPEd0MXY2YHBRWThRcVFKXkRQX0Bu
c1pJaVFjNnZoOG9VVE51Yjt6U2ZeZ0Q8NXs3WHd4ITRNZCFOdWctMwp6UypaSHpidXJkcld6eU8m
ZV55STNxQH58N2R2I2hsWEAhO1goayR2N3p4cFM+UjB+U3dpIypUYTNwfHlKdzc7aW0KelJLXyhG
IVNINXo5aT5oJCtIVColPDFUKm5KJHVUTmw4fVNQbSNIdiUrUHc8ZGpebzhEVyF5Q0ZhSC1kck5W
MjJoCnpZdXpab1lgSTZHZk8/elktVkpOQTZnaUNLMHlsOXQtd2NSM01NWnEmTS1hcnptUnAxbGhT
PXMoZnxKbktIeng8Mgp6eld1bzZNM2VLNih9Z141RnF9NlEmS21gbjNXeEtDQmdFa2Bwe0ZWKSsk
PHswRHFWNEdxPiNiUWR4M2goSHpBYj8KelVARCFacUd0OXdMeCt1dDMwMUVZK2whYmtoXkVYWntk
Q29eXmBVSUhpcy0tTHZgPnxQJD17U3NVTDJOe3BxVFllCnpGX30jKms5TyZyVXlkdl9GLV5qZ0V5
RE9BVlk2Oy1DfUJgVWdySkU/PWRHaWpjezVvMSgmKER3V15DeklkPzspcwp6RE9Edl4kaTRMTEJT
TVZjZns3bG5TUSR6Q0l0UVh0MHE7ZWw/STl1PEVsfjspSUpPRWF4ZjJaNjhsIW4mMDNMU08KeiQ5
dTl7WHtvOV9wIXQ7O0s+YDFBb3kmQzNBQUxQbk0/LVAtQElfOUBPPWd2UXM+O2FjNGRoTXNWeUJj
TztJZlYoCnp3YUJxNitZPlNMRTxZelNoYihiJFNxK0BXZWQkfCRQfFdCRWNLUlR5JmBwR3kwPkVf
fEleN14kKn4kfDBneDFHbwp6QW9gRGlQKDQ5K1oybFNYaG1VJiF7R19QZXJIKlFLU31eRFU3N0Am
SU1GZTF6QnRVRmhyKExHNlpKSlZvQnc7KVYKemIwJVp2UUl9YXVjbFlBJWZHSzgpSX5wMSVAYm5Q
XkdTcWJ1XiNsJn1fN2VVRnBIPCMwQnwkSm4oZmpSJnhsZjc9Cno3YEIpMihjWExzTitJZXV0Nj1k
RCZTeVAte1lrb0V5VUQwYyF+PTIpPF8/bFl3fHlyRUZSP3g5ZTE3UHlqOVpHbQp6dWJ+SGx1Nm5S
NVQzN1dBIys7enxkazIyUTAyJWNmRzQqfSskO3wrdVk5UWooP3pKa25ZUEZiKVZ4fE8pTV9YIzsK
elpKZyVTJDFIUHJYdSpXXyVgMHcwVSM+azwkeTl8Iz9uV35uRnZxa3p8SlBJc14jbl8/UkI2VD1y
WCEqQk1saG5HCnolTWNYKkhSWG4qKUZsdmFzbjJ9MWc0e09SaEpFUHg1N2tFYHZeWGoqRjNAWU1r
dmdYaCU2JWBBX1MwMT1xWCpWSAp6YmFMVEFzT1U1dUNNeGpMKjhQOX5mXmtsZnc4Q0QzYzBDI3VG
Zl56aDthYVM2I1lFQWlrb1orKWUyPTYtV01ofDgKejB7VkVSPU5Dc21PZmp3QXdQZW0ocUk4VzlG
UkgtekFlS19fLVJTO1d7fSQ8b1B5NVdqMFVxcD9PaExpeVY/MkpWCnpUZXhFNHdTKFgyckh7NGUk
V0IyPnI2VSUzeygwMSljYiplU2puQlpha2ImOz0+bVdpIXY2K3JlS0ZHey0pSWo0Vwp6cXFgPmtF
I0pRWnpgN3ZiKF5fMXVAZl9uS3RRQFFnZVZlR1RKRE11NEl1Y31iQ2MmM2E4YSt5byoxTmtzXjVw
XkgKekpAKyQoY29QVWg8eGVnNyZOeClzOUUqVmRkdkZ2bjNWY1dDc0o3cX5TNzk5R3xLPH55Sn1m
cSkjQENOQGtgUmNNCnpTeHAmeFYrQiFyJFNzQVFSe2ZOQUlfIzEwdUZ7VWA3QGxOITE1JnxKWlB2
fX1nRXV5ZnpONH05UTFOP05Ma1ppUgp6bW90ZHwzSktRUmdrWCRUNSYmPiU/Qk4qXyVHTnsqMipC
byM+MCQjV28kZGFQMEJgK0ZJOTtzRndoNlFWeyR4I3EKenBic3tPUl8+M2NDbmx3Tjg4IVVraChN
KENCdm9gPGgtamBfc21hQktVbW5jOT1nKTM9QzFLRmAoIW9VcHhKckJWCno+VW9RRWI8NHd0WC1Q
VWJoe0krezI/fj8xU2w8ZCNAV0YrU3tXJjxIRmt2d08hQDxRdmIrUG55WVVFYkd7MkJpZgp6ZSZ+
cks5UiFLPnJycEJyJGU0Tn43fm5SYUJ0Uit4T1lkPH11YihNSz99WXIwcTlISDRDRERyN2EySG8+
dDZOYSUKemJBNmojUE4xdiMtRmgjez17aiZvbHd9cC1SdkxgTXt8ci0md3laR21pJjFeZGg8cGM5
SmlpajdJe3ZJR0d3WGNJCnpQTUF7ejQ2cWo9TzJYO341cWIpOVFyKXU5eCEzfU5qfTMkKFQ0Mj52
YD0jJlJ5JGdLdV4kPDUoOT45I0FtJiVlbAp6NSp7NWp4RC1jP2tFZ3ooTjNVbVl7d2R2Vyk7RXFU
OGVofms3fkRZP2B8bkZDJXl7R1pZZkYqQk5fPTUmSCNRdHoKelUlOXBWZz9GZCVUcFlxb18tfm97
WXdsUm97TSRKPEl4P2IyOW1YYXIzbCNIJmp0RGs3SXg2WWs5SEliUT8+fTh5Cnp2KEd3VG92MnVv
b0JkVml0fVYmZCl3VHFwbzBHKXJUVmUtJGJDYlZVVG1MNVJ7THZsYypFMVNeK0JFVmQ1bThXNQp6
KGx5d0VQZ0k/eyFKP18pdiQ2OWdSMHBUSHRxTyUxM3JkezZCMzZeMWB0P2clajwjeih6NzQxdkx6
e0RUd3kqd3YKellJWDg9JitzPHVyXk45R3dpJCZxKDJSQjJBRlZYYG0xT05hMFd9PlpGbDkzeDlN
VihWKXwtIXYxc041ZGdVOXlNCnpGK2cjbDU1OSoqUWFhVUBtRihUTV89eEROSzJZTVBQY3whaTNf
QWZOVUMoZSpQZSpFfU8pTjt+dilucUgoTTRhfQp6Unt3bnApVDI5TWAxZztXQ0p7NTJvOHM4U2dF
Kj9XcHs5QWhyWSt5TiVGND5WMSpIJj49Q0ZVa14rUnAjJUZLJHUKenlHJHhlcnN2R2leOUhqbF89
bGIycjhyI0spWEdxZUc+R1hRWXk/KDB4I3RWSmAmTzkoQGp3SXtJODhwe2hDKjRHCnpnZTNQYSpr
IXlqKk4pRWljbHwtQGMtdk48VG00KVkjclpnUHY1cy18NmtjRjc4cyFzPzArLVMoYVBObD09b2E0
KQp6MDhMVzgkcjYrQVcqOHd7emM9SXVKS296KEtlK0AmTWhpRmtfJGV6ZHhueVlEV285TS1iclAj
RjZNRjY3KDE7dC0KejVTfTY2JE9KJSlIQzVqXjtxOC0/OVJONiphKn1YRldhMEpCWDk2UHUqaVJD
MiREa2U8NyF9Xyl7bT0pKml9aF53CnolUz9qRG5IQGBtUWs9bH1VKGV1K2E7PX00ZTUxelpIWEtH
eUNrQE5UdnB1djMqaDxfTVh3LTFsWWtlNzZNPDt2Ygp6Pz9YWVVlNz5AWCo5Zl4pVlY4I1VOcElM
ei08bXRxOyR4cUZpfkBGLVRgME10I2shMXN7eHw1KXJHRCRPcnIkLXMKej5yVVJXMkVqa2IlPUtI
bWY7ZjxWZHU4P1RPd3NjUUw+JWNmSitSQTNzPzxiMnZJcjBaX2N+MSpwa0ZlZTw/bXk8CnpDQG8w
d2BPQnV5K185MXl2c0omVV9Xa18pRjYkOGpsfndYLWNxRGZGSFYlWEZvfj1RMlcjak56bD5xRTdt
PE8wJgp6LW5hcGIqUnpWTFhUO1kqV0JKZnFVYVYkOVlxOW10eFpmRDRQOFlSR01LMSgyJGJVcHtl
QGF7V1daQ2lpcWYjI1EKemVfJEcleilIJTZIYmJSamc9fDJpVj93Z2RSIVpSKXF6biNwT3xBI201
Sjd2Q1EmbGVMbDhPcXR5U2YwIXFXNm5ECnoxYSo0KUxYJW5IcUotKHVpKXtweUB2PG43Kj4/VF95
SUY+LXBUbF5lK1lOd1JeVWI2e2tvJEI9SE55QUwhV157RAp6PzsrUEYwdk02MmAxTi1+WVl4NWc8
P3dKT3dgSmo4XzluZyZFV2ktOXgzXmI0NDA3JDZTaitJOWVGMnItOFBsaVcKemg5R0sle2h6bjBH
dSYzNlN7JUxEJSg8SFFXIzluVlJoeVRDX0YtY1dTcnR5K0NOe2R3YG1RfXdxN2UpRjtHK3RXCnpq
MCV+NFRmZ2pSU1ghVWcoNz5NaG5WfTg9cGI2aDFiNiZOI3Q3QGpucE5DKHxeNHwqNUxsRmxaPHs1
KHcyZU9DYgp6azh4dzsxSUgwe2I8JClaeF89PWBMdEpEODh5Z3p+PDBKcHA8MT5gPGc8dmpQNyM+
MGNGYn48MktUOFVgRlhhMEQKejhVVyU2YUJ0bysjJnZ8Nm1MOCNYPFdFfDQtbFhxWj1xcW94Rit6
fXtyKnNCfU83P2l1UTVKREBmQk9vTXtpcFdkCno5elR8TGl8VVMma0lkRlFxYGU3c0ZQUlV8TXV+
I2QpX3YoeCNrWGckPUs+Q240S2kjN3Y0MmJWUC1IV0pgIXI8IQp6K0EjfjdGPTctbnt6fEJyR2Eh
ITlEOHNMKWZ+TWM+X3QpZnVjOVM8Wkh8bEg1TTFWVWE2VlZifEgraDxRUzs0UlEKejZPKn5lcGVp
KFlYWTg5bzh5Zl8xeEd1JWFveTw/KVR7SFd+JFl7PjRMWD9PYUk5QkJvUFdpPmZuYGNgbVltY3oh
Cno1N0I0PiNqayZ7UEUoWXdMMXdwU2VVQG5ZV2U+SjsqKSFQMTJraSQqdUh5LXNWMzl0Y0pqaX5h
QlhfY0JmbjgqQgp6QXlebWkoOH5JKDR9fFQqREJPNWpHaUtwO3VuLSVvJjhpSDEwdFVqdShXdm43
KEB3WEpFWjQ1e3FxIXAlUkR4dUMKekskIX54YklET0tZMmQrUlM2O2VAcDBhWGlSdklDZ2NtbmA0
MnZ8cDw5YytIbiQ9aGdMPENxPi1GT3NqQTJCb3lVCnpTJjl4XjIqUkVIWGZaZD5EQURDSiE7M0FT
MEItPEJONiZ5RG1Oai03ajwjPj4tVDdhUiN3OzltJT5gKGVGVm5CRgp6K2FDSUVPaURvYURoalRY
MCoqcEcoKyVtaGVMKEIqUnU5LWk+STEocylNMn0zc2wpYC1GbjJNd3dqWG5OO3tUV1AKemJSOU1Q
SjhXIW89QT0jZChldGlARl5lLSFDQDk8VXo4WEklMW15PkFtMzNVNV5fdFFObmk/THlsfi1OTyND
dzVuCnoqRkV3T0Q2V0dydTREZktXYnRsbTNjUkA2UCZqdnV7e1Mja2U7c1UmLTN+aEdOan1mMXVS
a2w9LWdlRn1Ga01kdAp6KjxKJkAwWj5YSHs1N1FpemhoJVItYH5uKFEyYVJIWF9MYlMjeUFCVjcm
TDVSbSpNQkdyZ21teVpmK2lMUSMmOUkKelg2aEJkcCM8VypgYHwmI1BOeDR9V0VRKiNXQVYxPD5+
b0c4JGFXOWZWN2cpSShSX040PURoUiFjWEBhVkZNQSlUCnp0cUdXcEAzV0p+JVV5fWkwZWY4P05h
Nnc1MmZeXzc4ZzlhPGIzSkdhLSNMV1RUS2NVJTdibUM1LShLfmNXT3VTUgp6IVIoXnRDTD1IdFZx
IyVVXlU0WjU8ITYjVFN6WmJ2X3t3VENnYm0oZmZpYWh5TXFiTmcjd0JLOXwwSyY+PjxyNHUKeiQp
eilheGo/RnR6eW5OTSV9bk40O0JpWUQrSD57Mm9paWFkcE5JS2BWRj9XUzUxPEZjIylPYGpaOUxu
VW9rY2BPCnpsWW9Xais3OyRLQmg/cyhNbkglPUo7Tzw2XnVoNUtCazN9TD9tPG1abGkhVHo4MmlP
dVB3REtgKmN4KGV8SyE2ewp6KTR2Vm47KT56fDRLKSs4K1l8KiNnfjk4ZjFqX21DVV81VE5UTW5X
cWN2TlA2Y1VYTVB8RXhZRWdCYEhJRm4wd0YKei12ITQ0Uj8oOSg8TX5+bWBHWGZvXmsjfDBHflMj
KCljYkxFZ3ZgSEI0bmRZZ3k1NTYjbktFaSRqTWdDIWoqaUNNCnojWmJUdjB0O3J8Rm5NeSVzTXxR
X0VvYX41KGx7KHJtKERwYUkoalpSfDA1N1Iwa28jay0jQ0o4ayNWanNzVzA0Mgp6bjROdGpPMXJR
ZjB2M3JAPWp2dzY7WDB5cFpBU3NTcHRDSmB2aXhgb2BhX3RYXjRhKCklcmMlRld3Kk9uJGtjZWcK
emBjTUg+c3FeUT1VemgmVmZHM2JZOVFhPmclXlZyZ2NnZDEqbmJrdCQmUnJ+czJNOWtiOHBhaWxL
cUMxcyZRQXt4CnpqTGJiVEUwfXVrOHszPXZRLXMwTD9hUzBPTnFCZWIhMmBtKWltTX1INGtMdTxs
VV9ufW1XYjZJcmYlMXhNblokJQp6RnpEVmt8MiRxNU90KSotakVwP0pKcCV5SUApbDhPX0o0PjtV
NHM9Y01UVndAanVJXl97OHV1UCY3T0F8TElIZUIKelMxdzNIME13RVc+YVJ3aFZgQHRxX2E9THJF
JHk5eSZgMntHRmpgXzA3JXhDYShLaitgQGNSK2pGJjgqeT9wO2hZCnphR0IlTGBlWVEwdSZIQUxS
KWdNK0RURGBrY09+byk1ZGB9TnFMSngqX2YrJip3IUNCPDkyfDVGNDkraV9oeDZvKQp6SjF2bURA
R2MhSlJePkpZO0NHVGtZKjR6ek5qRjFCa3krVlp4R3RZJEUqZ3p8YkJfcG5vMTUjcFB6WG04YUhp
XyYKek5XM0RKYT0kI2RjN0QxTGZlZjRrdHtJRmhKSCsrfiR3enxIeGVCP3FUOGticlNreHxsXnhQ
Yj9LdjI5fjFebyNOCno7blpnMjBlZVAwYFVUZjw7SFpXSUl0TVNRUFN5cG04eUQ1V0NjdWtKaCg3
cmJCcFE1JGpWOFojQSlGUU5jWWFYYQp6STVhbUdXWE00c2U8eiN6TiR1aHgwLSFTYXp5Pm0rQl5V
cmNpVkYlaEQhRjQqYTgwRncyWmM4R3d0TTxAdSVzd0oKelJ5QmwxZnVZKTI/bStsJFNaRFFuS040
ZnY0Wm91bGNFYCNZIU5KdXtxZUttZXF5VCphSzZOd0JNYChxITMzcF99Cno9fCo4U04zOUk5ZE4m
VWc1P343JTBEQ2JDNEVyIW1wOzc2RHpYLUZlNmY/I0JIfX1GaVNVQFNYKFFPM3ZHd31NRQp6a19w
VHFae3BQJCt8LVFzK197O0NoSzUyeTNwUlo7aS1aTEFsTl45fDNsUlNRSHQpdkM5VWp9Jil4R0Z7
KXN7MXkKekpJTUVBS19xOTtLSEN1dDRMQFR2Rn5GWDkpdzNIR0tHUyt1eWYoNGx1ZG93fEAwTHV3
KTJTN2R7d2ZKWmc0KCp0CnpTPDlOZTFiVzdQaFRSdj05R1JII2VJZCNBVVFZNWxiJlJUJVp+UUJK
VlgqMFFzRHo2TDdMSnk4VkdkPmVycmtPZQp6MHljfjE9MUA7c3NCLVZYTS1yKGhweFZjKEh6fiQ8
elZDMDdtIWRCPSU0VEx9ST5LNThQcylyKFNZbExaO3lTPWIKeiRfNGN3dVEjbjEmKH0zQXslWlA2
RlJrfn5gQzBNTiFRKXR8WkdmU31fQXpjZkohTTwkMmFVc3VhN3lfT1F+XkJkCnpoVHJ6ZDNicj9g
bnZMUG9PV1RnNnZNYWtqVz5JYXtmWFcyZVBPXk1wUUB7PjM8cX5PREh7U3ojMmwmQklGO1FNdQp6
JnxUKWcqYyQyYiRQWTh4MUQ5SGtoZnNqQ2U1fGdwI3RpTjA1THFoU3EmN0F6Rio3LUBwRjNaTypH
aU08YEBLVzsKekdxJWxvKnY2enBobGR1RjlsdHtLIzNWUn1rQWclK3t8fj88XlFlb2tAR3szLVAw
e1IxOUpKczFXLVJFSyhZTHtuCnpjdlpfSnUjTGdPTD1HVTdBUVc9fnIyPmliYUs4V3Y+SWRETVgq
MF8hI3x8JlI/RU1hUWc0bUkmcyRjd29XWTwrQAp6ezNKKEU7Nl94PTIhOWs4TUw1Zz0wSFV2cFhA
ITBVTDMhZnFiQENuck87ViZQWipTXyshKzBWI05PZ2M5MENSXnYKemFxYUZQNnh1OEBAYHFQX2gq
eTA+ak9DTD1iWChRTEAxamB8Mm1Tcl9paGxYVz1NIzJXR3R0WD1yOy1XMUBeQUBrCnoyelVqbE9+
UH1WSDNlY09aTUBHYTtxPilsS1B4VjdeMUpUP2NPNHgmY09LZTw/KCF7Nzl7U3toPilMbnElbkol
Pwp6QWV6K0FoUUZtJWxtPW9fS1RsbWNiJEZHKHszP2ZmJntLKCMkVWV1T2pEVXJMPGNtJU1NRjJf
WV42bUVAPCNQd3UKenQwIykmOT1RWmV3TUhnUl85QF98JV4hVCRqM2tKVSRlPDw2aTt+fWFCbnB+
d2c4K0l1LVgtRW5kdnFFVnlnJU9JCnolYXVjempxIVloSlRCbXpfKF9UYGZaa2VObFNyYSV7PiNA
MktKTFB3OH55K0k7e1FSKEtqMjgyK29MU2kldnFpUwpQO301Q2QpbUFDRlY7UzspSEUoPUUKCmxp
dGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1wb3dlci5z
dmcgYi9hcHAvcmVzL2VjbGlwc2UtcG93ZXIuc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4
IDAwMDAwMDAuLmI0MWU1ZmYKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2VjbGlwc2UtcG93
ZXIuc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAv
c3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZD0i
TTEyIDN2OE03IDVhOCA4IDAgMSAwIDEwIDAiIGZpbGw9Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0
cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0i
cm91bmQiLz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvaWNvbnMvaGljb2xvci8xMjh4MTI4
L2FwcHMvZWNsaXBzZS5wbmcgYi9hcHAvcmVzL2ljb25zL2hpY29sb3IvMTI4eDEyOC9hcHBzL2Vj
bGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAuLjE1MTIxYzA0YmU3YTRjYjlmYjY1ZmYwOTlkNzQ2N2I0NDRj
NmU5MGQKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDcwODcKemNtVjtnOCZLcWxQKTxoOzNLfExr
MDAwZTFOSkxUcTAwNGpoMDA0anAxXkBzNiEjLWlsMDAwfHlOa2w8WmMlMUU+CnpkNi08KWI+TSZK
LWRDQHh5THdkJTJfJl9JZ3BrO2dGaClSWmdiajhFajJGTy0/SEM3ZG4yaGxeOFNuOVk9OTVWIwp6
Nk1yVT9jcnI2eSRtaUkyYTZGRlVJNU9pdmoyRk9Rdnp2VnBsRitgT21VXmtgK1RPZU8lcGIzKylv
THxEZlYjUmAKenMkWU12S2RIT0EtbTc9Y0pAPWUqJnBsNzVGOU0rS2BgKUM2QnNWQUZoYDJlallT
aypVYV49YloybW13SDdjYEE5CnpLKEtQPCUzIyYxUlIrZkQjXkwzI3p3eFM3dElVbHotZWBiJD85
WXVneFkoSW5aQHNsYCpTY0x7eHc2THw/c0hGUAp6KHFXSUF5P0Ehej5aYEJMK3JXRDd7UD5weXQ1
JlZASHtOKlQwbCM9WDk1d34kPis3P3RTRmlSfCY2bGRtSDZPVTwKemxwV2kpekh4WUhfempoRWQx
KU5HPEQ3SGRzPWdKfjtCY00kaChJSjNGJEhWd0tvSG0rVkxKVk1NYHk8KSRJWUdoCnomQERmXzxy
eHZGTyQqWjMqSm9DKlVoTkxjWDx6UmZSMFp6PFkhTEFORTNQPGUpQX12JTlVZENHdnxLOG09QUU8
Nwp6ZEF4ZDF0IWxeWEo/anlRUjBTZX01cmVlYFczNVlQKG9lTkB3KlRBbHo0TCRrUHlnPkhrSG0z
ZVQqdXp+Kkt4fCUKel58dUNhc1pAJGZSPSlqUlRlb2ZmUjZkdSNJRjJINSZZPW5qdUJ5RXZgXzRD
TWJKe2VnSGEtK2tSVFVIfjBAaGxCCnpSNyVfMCtJfjVBPyVlLSUkMzF0aGlKfU89MDs4N3EpJCpE
SVFQVnN6IXNWQTt7KzVrdipNQjg5SmJYYz1RbypZdAp6TXEpdX4mZFdJR3draTlBYkhGYEhsbVll
WEg4M0tDVk10cD9gKT9NWGMqMGx5YERnJDdFQT5ocmVSZWdrLVd0M1gKelg7e0doOzJZb1F7QCp2
PkA+bCkreVJSI2slNlJxTzdeQnRTSDw+KH5fZzsqTU5vTys1b09SNjIqTUl6KUtsfFYoCnpLUkd9
V1pOO3pqMjRpYCgzSj9KQ1Jxd3AmNTF4UGFzcVlMQTwoOUBTUiU0OChEZm9LaHkhUjU9ejt0eEJL
WXorOwp6cispbTB8R041S1Vab1BlOFU/VC07QCpEMiNVSXxoZSM1cyQzZEotK0VGdypCZWhOfDU3
JHM9UXdwMzE3d0NLOXEKekBBPHt8Uk1pNTlHI3duTzB0OHx0ekclZS1wV0QyNyVUMHgxNW8/VTJJ
cURrKT1lQFRyRWlMcitfSX19NDU4aVc9CnpgYUBIS1NJb3w+V012PkNAcjVmY199cz0jbntPJTxp
X1JGTTNSYkNsRDl2TjQ0PWN1S3A7JmFBSGdFcGdnKTEpagp6b1FTeFV0YjlmNWR7NzFHPis3PzNi
OWVsUUQ9KXJnPipnJnRsfWFVTmpHNUhiV1J1czc3LUxNU1JFb0U1LWc0OTEKekZTeilfY1hNfiMq
VmxKWUVCJiR4UHomYHdjPT1XNXpQTnRGJkJiRVRILStFdWgldj8laSQlWTIhOzliaztOQDRICnp5
TCRDJWNRN1RHUD8oQn1Bb0FWc2V6KVVxe19FRXM5dm0xdkw1ejVzM3AmI1V1aWwlaz8oWCVVYFNL
VWV7PlZvQAp6R09WWnlxdl87UENSQmh2dXM9NCZvcFopbkh9QmxHXklHUiEpN3poQnNBX0RENFVW
MEE/Qjc1NSNHe3xeLWNSVGgKejl4JFQmel4oQE8tcGslfExJM1ZPKkc0WE9oJV9DKFg/N3JEQk53
fj0tRnZSPmQqfGhFMjMrMytRUUpmb3peRSRBCnptWWpDKS1hUH43QXZEOWk+NURfTEdrU1Z7YGBG
cWktWWc9SnRRKEI3cDlTY24malM5UDdoVXA+ZH5XMUNNVnJFKAp6LWRJSV9LOUBXSFReQzxeRGQ1
TERneVN1TXZEVyVpUGRORzQxTzBuMVk+eGdUMCo3THtYWkdDbl4hakpzPllPdS0KenU+endPcGp2
dzVgYCoqSHlwU0p4diNNOGAhYW93UVVPazA7eyh8PmlAeEVuJXVnVihPLXZSX2NlRDFRZHpxKTxm
CnpqeFJkelZAWkQyV2Nte3VWfWR6emp7RUJVazNhaysjdy18KF4jUG8hMkUjK1NjUjEmZVgzVCNp
VlZyWGU9a284Kwp6cSFlIzc5NWdVJHtgSHk8ZHwrdzBUdDBkMUAwdUpENz1VdUFibj98I1VBK1gq
K0I5R1E/ei16UDFGJiheXzclPiMKekx0YVgzR09jalZ4blMkb08pRnJaJW5pV1pjaSM7X0Zgci1W
b251U3w+SmYjQUFSLXVKNHRtc0hjTylTcT5ZWmFHCnpVc3crTldMfFVmeXM/JjJzbDMjQTlrKXFr
YGVKSD1SUGYjdCNTdX5MYU5nbC03MFQySzdiVTQkOWFFOE9aR2FpQwp6Mi1Fa0BpMVNMaFI2ZmFB
aSs5UCFnTWoyQ2NeQWpfPGJAfkFRUHR8TG40VEQ4NVdxUHtwO0QkQ018ZmpzWD5GeWEKenItI3x5
R2RRTkJsZ0AwR2JTZ3hROzhkeCZtfTByaU5VPXo2Qit0OyRGaGojUnFOb0IwcXZ8cSFaS0ozdlE1
NE5fCnphY283ejBzOXRzWm9UIV50b0x6T0V0NVB8U05VM35qYXVnJmBIPk1TLXFGXzQmZURaVElP
bHtEU3V1WVIzcD1fPAp6dDF5Xyl2MkFGOFpHKEgrbUN2IWFUd299d1AqSGB6bDVXaX51Y3dQc0oz
ODZCY1ExR1RgWXV2fCNmc1RDRWh6Z0cKelZwXmVpQDREOGtTPD8jU1VgKDk5WXUmQztvd2xNKDh9
Vys+UnQpOCtMY1VsZSt0JFYjbXp+TEYlZypNS2ctZSgoCnpBPWBLQzxsZzY+O2Fsc1U8SSFEUGQy
eDd2VHdMYkJwPE1nVzNLKG48a1BnIzA9YTVKK0FfVF5ndlg7O1dTZC0rKQp6Ukh1ejEybnk9N2I9
fmpSckt1QF5xNm9zQyR7d3JlPT5Ib1QwaiNrVXFZNUwlQkoqYT89SVRHWmdiJHV8OT9NJDAKekN+
ZXh4S2lfZEQqRlc8cF93Qy1zaCUxOXdOVG1vPG1lI1FDZktOREhqSDtSbHpkR3VqRGxVI0YjfU9o
eiUzOUprCnpNSG1EYUcxRWQzSDJEaGxSUUZ7bnhfX29genZhWFIjVHJCR0okcnxUU2F8SFFlRDtk
PkB1NmtzYTltX34+OFlwcQp6QDxYP0IlWnBGNXdVfHB4ZFlCP0I7aSViRyludUY2QXV1KSlzQlBK
KlFIZihKYWcyPSY9XiNaVzJyO0l5Nj01UlQKelBNY0ooMExFR2RNQEh5TXJ9QEdhUzg/cWh5b0VW
TUNITHNGZUM1JTVgUjBadmQ4dzRnMX1VPGNSelVIcHhJK345Cnp0R2I+c21TTG4pclc4ZUZRWHdz
PTVEe3I7TUh0SnBQeWoyMk5JaW8/TCVpZTZ2LXQ4PVM5NXgqNFc4TSt6ZFpkWQp6SCN+aG0ma1Zq
cTVRTWFhRXM0M0YxZmZyYWtTSyRxNmU9YWthWVF5dTY5JWJpcCMlLUQwRCY+JkRyS0A1ekpCJGAK
emAwKThGM0QkMD18SFlAZDtweU07dHJzMiM3IWBiNkMmNXBJaH5VJlFUcT0tQmc9RTdGR0IkKjRL
KmxMUlZ8ZjlBCnp2RnQ2M2E3TkU4eldGREEkezhJcShjZUFKVj1yeXo7fThGd018TiRjSFFmUipy
R2cpZVJRR3Q3cTYpRWh3MXE3TQp6I3gjZiQ5NE9vVW9qfjFwT2ZgWUE/OVMoUypXeSQ3KX43eUEr
d0xMcyFOPDh7X2c0UCstck1MZTY9PSh9NjhwdncKentDR3IhKmdKK3hCVkB4QyFYVExQRFBiYm5I
c2xtd3QpKU1nPEt4VEQ7cF9rTEtUJiprOWxgY357JkQreUs2PndNCnpJRThFfi1MUyYxQXFYREdT
QmhsR2tad1N+cHk4SCR0dWdHJDRSaWZqPWthJmZmMTNRYCZ5d0EtaGctTD08M3NuWAp6MGZmLW54
O2M1VG1zO1JCUWdzajtaSVAqPTZkKjgkSjtlZWFKTSRjRmBqYnlGXndgc01eeWdVZihxPXlUbzcr
ZWsKemkhfXp7VjU4X3o4TDU9MHhWV0t8cGtXanM1TWlLRjsrQEFXPG07Rko1eE02I2tsaSlGTC1+
SEx4bn5XQ09sI3JTCnokZGAtNiZOV1E3d0lNUXJSKXBhPTs8VDx+X354N2IxTGRfWlZxKFcwYWVV
fldwRTZ1MikwIz84OD8lMmY2ZVY5Tgp6KFZsNj1QflVxIWshK3tmMHdAQVItamZZZGVEaj0oPX1N
KDMjV0FnNm5tPkt1UE0jbGxpRU1hZTJwPHkxKDBOQ3AKelFyZlI/PlFvV3p6d31wczgoOytucVk4
Z31fRkd1aWIxZU9aSlRvKGB7S01NRWBPKjVQWGlHUDRzUHxlQzVoYCYrCnorMWZmczJJRk5iUSk+
YU4yIW0wRE9Ybj0pPDBxV1hQXm15Uk5VPUZMJFBKSShMbj10Jjh6TztuX3pAOWBRUlI+cQp6clk0
STY2YClTTDdleWlWTkBvelY+V3VVOHM+SSZZVmd2cl9zciVXVUEwJXlxWTQ3d000RFVVcXNGRkJA
Yj14KCUKektsPj5feXs8dDRCWmk/JG5VNXwkb3p1SCNGPGRGcmtxVVd1X2piTyZ7eik9bnJlVl4l
bFpBKi1qJD5seXNNYyVMCnpUP2VMUTNKez49ViYtUSVfezhFZkNgTSVya2l6Z2tvX21Cc3JBIzBW
NlFORWppYylnWGx2UUMoJHo4VCQkajFAYQp6RUlOZ0cqPih6WE1Bb0t3ViZFbSNZPFZGbSNYNz1B
ZStAeTFUI1RDe040TT9AQVZBczIleFRUP3teT1RZaVh1PTUKenQ+cXMjSzB+ZnRBU0xEcWJeUnRy
UmpJaENOZlZEI2ZYU2JNajBwTC0hWD9LWSYhVEo+ZypZTkRoV19GUktpVHBFCnpDUCpGOGpeOUx4
QnZ3R1IqN0xjM1VPLVVxRVB6KWZaMzM/N1U0cnUtUmkhbHVgMVFfQnlmRDAlbVpNTXMwR3hVdgp6
Pz97PHwkKkxVfkZXWHdYX3F0KDNEN2M3fEo3QDVROE03KEdpVE83T2NXbUU/SSlgYkg5Q19WUWw0
empMQUhTeyYKekFQOG1leE0wPml4PjZ5TGF8OXZgUiFaRXJkbUNjeTV1NW1WQn04UEBCRyF9b0RT
IyU8UEFIWilBMlMhe2VLSC0wCnpXa1lVfGJAQFI7Sk1+cEZRO0V+JHA0NCo7PnxZVHlpQjNTVz07
TjUzWTJ+eno5IWhaeHMpV1l5XmlWJHxRSGc5Uwp6alhSMUpLdkE2Y1NUamlqVkZLQ0slPnN4QkNG
ZU15dCY3PnxSd35ZY0NXYFV3Jj5yeE96YXl6MGN3Z1UxYTlsbVcKenpPVHQzUXBlSmNaWmdKRiY8
WCZ+ZClEV05LcE1Neng/WHJaT3ArJXdrITxUKzZlXnNVP0UrMTxYYz9kISQ4ME8rCnpzfHMrbUJt
NEMmczBWZFowMGphZyV4aF4mKHc/ZGFoSnVTMnRkIXM9JF45UDtmZz84eEBUIzwhZlNLdEd2Rz1H
Wgp6Q29laDJoPkl7SDRZNDAjcytzSVcrPDVBJDBCTExLdSZHZkMwRStYRHZpRno8RDM1OWc+S2de
dHJ6bGlOZFhvbW0KemtnPnRPRGoxKEEjP2MpNlBmWElLO3FicmY2eElWTWlwM0NBOVVVfjt4QHsx
d3NoUiZ+Nys3c1lQYEFeS085VXlDCnp3bURHOHpKS0VFRDRxYkopZFdmNEJPTFghZkItVUM3STZh
RSktTXNuejc/O1U1OyM+ZCM/bF55QjtDb0gpU0oyfQp6ZktwOGJ0RVVqaClwQl5uZHIhdCNXYD56
K1NhQGAhUTFfeWN5NnBAUzVzSjwrOTkxd1gpbX1ZSDNTb1hySX4qaz8KelU8WEk1alZVSzVEPnxp
NHBwaiVMY3ozeW9tOHVVPTRGeWxrY0c3ZUo2WTZhTj5nb2VUPmUqN3ZWS2ZRPDFjO3BECnpsKHJk
SVltZHJHcHNAJV4tQHwkKWdYXkF1VHtralIlPmdOKk5oV1lmWWJVZVB0d2lkTllDRGtoRTNVNmQ+
USlyMAp6Q0BCJXY8XzlSY0NeQGt6VyQmMEJ3czItZzUzekZ4SGZLSWNQezBfZSlBbz5rKU5OO3dT
MCFhRUZCRkVAUlZvbVcKekcqd2l1cXtNTEhqNSNuVmBMRjROSEhrUnRDO29iNzB1QDNyeWlfam9S
QmtXbllPQENjaWdDbistRShNOVd2Q3BiCnoofHx5QXs7eDBsRTVJYkhvZDZaQHhwIWJFUnQ0YEJL
YEZZSkJgdXd0LSErP3hpO3VjI0t1SmN3c247Z2FHMVMlTAp6UD0kPUt7QVRZQzJCSCN5MndHaGJ2
TGFrSGAtSjNtXn1NSkNBJnt3Z0xTSjFLekB1Y1c8QHUzODl2UndBaT9NazEKejckNnN3ZEUxT1Jv
WUt9cT1fcy1TTkBEdTBuVlJpemI+QUs/MnFvfE0kP2k+OTcrbzJSeXdZaHlLNmN5Xnltdj45CnpB
MFItKzI2ZWdqaHV7UUd7XmBBWCtIQW5qYD9zPWdXU0VSMyZZJVRgcUI4RzI9NkZ0UHBHb20zdW1X
Q3t0Ty1icwp6d3Z3JkMzZS1JanEoSTZUYzIpfGtlcldAKENjeWNgM2RISlp2bmY4P2Qpa3pAUE1L
XyFxJX5lb0Rub2UrQmNDYSQKeiNQcTZVWk5Md0FaRDNPfE40alBPUjJZaU5Uc0M3S0AwQHUmZ304
en0wPEN9e05zQktDK28rKFU7cVgqbE9XamMqCnpaN2lFaGRIIUw/VEMmRkNZS3ViKFcjP0djZG5V
OFBSd357ZlE1IX1ERDY0MDdrZkE0KXEySEMwWGxSUEE9S3V3JAp6KkRUfnpYfTJNXz57YCNgeGpr
ZWhpM2tLSkk+Ji1ebWNOKlA3TG5GfSRMd1VIQjtDPUBaa0BeY1hrQGdaXmkoKjIKelB8cmxyeEk7
Q1cxQmNeP3xGLTRIKGVyRTdBc21SeFRyczFVUGFTKFFnKHcqJSg7YjZRQC1Zeys5bXtUQ1ZYdiFA
CnohcW9NP2tKb31KLUhxVz89P3FmKlZzSG9GK3FzU3xuQFhCT0RwKzdKdUpDN2JQVVcobTE/MSFE
LThqbDM2bnc8Xwp6Kjw8SnFHQ1dvcXBqQ24/LXdyP0pjZUxnWmVyPy1SSmQpby15OXRQV3ZUQFdg
Un0yNjl7NVNCWGpebjFTNT9GKjAKekE4fnI3bnslX3JhN1RVenExM3htQFdmMVRIfHVNVTZlU1Ik
O0ExfHM9QEFDd0dOQms7KWdQIyskQk9XYzxJbXl6CnpfU3NiPm1fRX0lUDUzOGdJPVFsSUs1S0hA
RFhHSmZlRUtRMXw0ZDx7JGd6ajNUN2pudmdNNTBeQk4mcDVWTyg8eAp6eSgyVzFaIUtFRStxJmtH
a0lSP18tJU1XWHpjYjxeJlRRJUNCaSQhKFRZZnVSO3NSOzBiIz9wPnJVRElQUGgoWk8KemZ7PWU3
K1FGQiRLMkEkQGFVYHpwQX07d0RnWWZrUVp7JFBBb0poZXthTWVZbU0jRUcrYCt8M0BZQDV3VFhQ
bSVvCnpgNWluXzl3T1RTXlpyO0dNZ2J0UDFsPlclNUI2OzJoVjQoI0IwO3M1RmxpbzlAczZeMGUw
bEVhezYrNl9HUjg5RQp6QkNJcnFIQXFJaVB9Q1RVQGMhLXZULUNYTmU7TUErMUVvRSpISkk/QjBV
c0xXUkdERXp6U3FCanFJY1lRKy1iPlUKeipuSU1vNFRteGltJGBEcjAjMGVeOy0oIT5iQU42KGZp
YXx3dF41OVpzUDUpTGh9MDl8STVGKHQlRmJUcXJkcyZICnomP1gpKDQ8dmJ4MWB8RnNtPDZjZU5H
IXBSX0hOPyhFc3JxYlZwPmY9TVNYUCNrKzMlXnZtbmchY01JT2dtKiQrIwp6dFc8YFB4SSRjPTdW
MlJXWTlycEU2bnNwRk8+dCVDZF9GYUUzN3N+QC13KGRYQmp0Z3IqPjZsNV9QSyR2RCYwMloKelNI
cnV3cmdBQGpLSWFUaFp8UCNkbUdONWJJcHx7KWM8K25feXMzUV9LaTwyRXBBSyFLemYhfilMc3w/
KjRzWHx1CnorR3RtbGl1JSFNPm4rKXRvUyZWXmFYfH51UikrY1VASyQha0MwZktiT3lqRlZjeThk
IWhZTTNkdFYqWDEqaWc9Swp6P1p5WkE8ZzYzdj56PEVDJEBfVHBicHZza3RQU3xZdFItQzVISUYt
b2NrcWtoOWpxX3NAIW4mXjVMVDY7X1IocjgKemFqO0orKSRjVzE7IXpeP3FnR340cytGQF54Pj8+
YmdKWGpYTWVuI0h6a14/bj80cUtjbVdEST8yZzxoTGUxUCNkCnpSYXp2I3A/cjFjKTcrY2UlX25E
XyRrS0VOQlIpPWkwfSYkY0RRYVNkfEVPbW5tdnpxTCQ+SVJOJkZ8KlA7dm1+OQp6MXhpKD1zY3Bi
OCFpMz51RWtoQTJJUUJKZjQyQHhTcylaQjdjMjNRN3VePz12LTZUJm5kNyslKyZYSFhfUn5hVFAK
endpQGErbEpGO3s7U35VcWshT0hUOH1pJGNlamVYNno8YXZwYWI7STgkRUkyK2MkWHwxa3RCfGFh
Wip3QWhVXlReCnpadFk+blNKK2VAO2V9RjtiPiRxfXFhdTZiR0k8ey1qK15TSnVuYTtWTE1XRDJZ
dzVCZnZ3e3JzUW15b2NTIVVZfAp6RXloLXhVTU1AXzYyQnwtXkkmbGdDSDFzUSgoODlSMnBeYDIw
PkhrNlFKWUR1IVQ7SF9rKUlGbTxrSFNMeXNpQ00Kej1Bfk1SQEQjblAmaVA2dV9FcUgoUEU1RDZH
fUQxc0N+Q316aV47aXx5cEplKFBveTVMekJWTz43R3I0PE9ES2lfCnpnQk1LLVNFfD9YUWU1S0Uo
ZnwoP19jR3VyV1U4OzlFYHFOeWVzezFvanQ0TD9qLSteXkJTPG1pQkVIa1ZmaTs4TQp6STUqcUYl
Qz1jNyY5dXtRMTdjTjU+V0RsPGN1Rm9BbTlAX25pbEhZK0dtfl47QH5jK0JzYTc5RHBad258I054
cTIKekwxUSptM09yVUM7RjxDO0xvT24xJXhIclAqVSkhdlYoKUhMMG0za0pmVUR+ankrJiUqQVB9
SnxOS3c/N2U7ZU07Cnpvdz1STjRfaTRpKTZIb3VvZzUhIz45aUBiMWdLM09HNEU3flFDIylrSEVV
NzNGKyE1UjdsRGNATHExfCNSQTZsLQp6JmtMMHRKRTlUfVBiaH0wbk9eMztOPnI2S0ZoJjZ1Rko0
PmBCTCQjKU4tcGEpUCpWaHAmezF7OXdwMHFORTlkIz8KekBLKEJQJGVkSVFeSFF4RzdpNT9qcS1p
JCs4M19uUEZ4N0FfUWNxYnUxc15seUJLRWlueVBfZ0g7fVd+I0dRJlE/CnpYfGxJNTZvWChWdjdo
SXBwQDR7eSF0JitJJWU1YTBxeH1paCZZUm8mX3xWfGNzVXFUTyY/TTAtQXUhcj1GdmdGRAp6Wk9Q
V0ZXUFZSbz1YRnpjfDkjYWVqNT5yPnVpcn1JNVpZd2w/dFllSDhzYiZlYmFyKDt3UlBMKFdnX0FM
Mn1tQDwKejFWUH5EJkYkUnxvSndRNjBTODRQYW4+WDs8JD4ofmE4IT5IZG5GPj9AOXpZYGg+I0lP
WkdFWWhETnZaK3FFQXFPCnpBaDBgdkFhRW9EK31FWjY8R2wwZkYjV3Q+LWxqKUY8MzhPZHo9O0BO
WHFxXkpNfShrWDRpeWFQRiFQKnE0eXA+VQp6JiYoQHl3NntOTXRVKjs5VlIzQ3pJb0tOY2slKzJf
djQoN1crd2FIeit5SmElbD9QYWBYdSpUMlIxbUFgKWErRGoKekdGaG1xKzh+dlI3Y1hBO0s9UHdS
PTNfXj9zSCZZZVhhNFU4MV9uPHZYOEptVU8lQXwkdWVRNnBgXmx9X0ghWkleCnpgM24wQipvc0tw
KGI0ZlVZWW90X0UwfDRRSiEtOT90RTJzQVJxdWIpIWpEd3w1M3VCPCNzND08aHQ3THYkMzgpJQp6
YDg5cE55bXZOQ2hpPnNuaSs/bSQpXk9tUzh4c1Y5cEVJWlRTTiokcFVzeUYyT0BDbHw8NWJubW9I
X0haP0tgJTwKekhJOEckN3pHJFYkNGVaP14hRTF0Wjh7OSlOUWVmSGNEej4hISUqZmdTbnhNLTlL
Kk9sS1QpYDZSRnd0dTd2OV55Cnp5Wjx+ZmBfQ0NvcldIPVQrR0NFSGBQKz9+VXdtYDUzK2FCby05
JW8jaD1AUD1sJS0kSFdITlo/c1pKJFJTSUZLeAp6VWR5NTBjYH0pZG9feSpfVSN3MiYyTXFYXk9a
WnIwajV+NGgod256Iy1GQl8yIyFSRXlmaEdYTkFgPGtAbnx0JXgKemI8YmJ0eXwreFQrV1ReR3pX
M2duJndUYmpmNDtNYGJEajQtcGN4aVVDJXBHUT08TXVWX3Z6MnhfeXpDJWV2YVEqCnpVUVBrRGsz
UEJYeTZjOVBFbmp8aFRVKWtWJV4mTWorcUxITE4oYnRrQmlxKG1LSTY8fkFHKz9rdEFfZ01kKWE1
UAp6eWkoNUowYEE7JSZpJikoKX4+eSFSNGg0VGo1Jm5BWWNlJmNfdWdrUjhHRip3Q0Qre2w7UWlt
SEQjTXJpZ0k3eFIKekl2e3hQO1JuOGQhdG8wfm1yaUdfX2tKe3UqcmNJUUA0WmlfR2pgRiE8M0lv
NExsMW5QI0JWIWptRGl6OzxpSHBjCnpwSy08O0tEJStfaFFCVHJpJiRmdkhwOWIpSyleWmdaNj1k
cDtsZjNxZjh2UXB8R01oOCNmUns+aGx+e3d3Xz9UbAp6KlF7TjtfUysqUEJXViRkTVdoKVdPZCpR
Sz5OVXRfdipqZ0FtUiRHMTFIWmtjeHwofVBeX3tPfndhPSspYVIyQEgKei1MaGlFKiUkVG5eZ0po
RzBgSSpaPmRCZk1SLUVAPDFyeUFlRzJ7NmFFNiU7PntgPkV7TU85elg/MnFOdUY4OVdPCnp6NVZ2
dkBCN1FZe1BYakFkKl4rLUNEUzZfdEpTMmxxWFV7cnFlKmt7Zmg0PTwpdkltRXZgQkM3eWw+eGQh
KyR5Tgp6X1M8aX1rN1VrJk1ZQkphKlhxcSV6IV90Qj5zI054YV8jZmEtWihmb3lzfWEkQ2w3QC01
PzNEd1VNbzdTcU9hcVcKek0rKm5zcXBKQVRkI2B+QWdraFNfdTh3PF9FSURiX3VZWX4jVTVRX1Fh
QnUoUmNzPGduYndQMXFuQndmUyZ3Sk9fCnomNn08dCZnQ3d5UjRTJkxIJFglakF9YWVVTHNKVlRy
WiYjMjwldWVfPk1VejVWSGojaFhVOHcrJjcxIX1BQTBDXwp6S2FIWFk2MlpVYiRuMDxrVilPIW5S
S1VkLVVBbGJaIyZ1VD80aTNHZVI0U2J3TVhgMHhxM1d3IWxiYUZiIUFVbHkKemgjMEszcSo4JilX
WVNNe2IjP3UwIVF3P2Z7PykoVkBue3J7VEtVJkI+aTBqfTtiVDhkUjhAS1J5UlNOVikyOCszCno8
Wn03NSVIYDVZYVUzMSVvUykmblomaHVzRXNSQmsqY2VsPSo2YTt9KVhzRHxeSVMocWB5PXpgRk00
UnJudHlzJAp6TH4we3YpYmJ2ZF5CI15qOEhjR0pxaVFPV242TX57JjNDQERDYzk8SkA2IVZWbTFZ
aU00QmckSz4rTX0ke0BCT2YKekpyVj9nX3VoP2Y8YDUpPm9IcmlVSEpRbnJpKShYIUV6PEJiN25C
Wl8rOH1+YFImYFM1JlUhbXpQM1B+PnNHRm5vClp7e2k9SWRASF5eS3F2cUowMDJvdlBESExrVjFt
RUIyKGJWRgoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9pY29u
cy9oaWNvbG9yLzI1NngyNTYvYXBwcy9lY2xpcHNlLnBuZyBiL2FwcC9yZXMvaWNvbnMvaGljb2xv
ci8yNTZ4MjU2L2FwcHMvZWNsaXBzZS5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uYTEzNWM1NGUxNDllYWE5MGI2
MTBhNjljOGY5YmY2ZGViMDZjMGU2NwpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTU4MjUKemNt
WDlfV21zRUgoKz0ocU1UQCg7eUY+OSgrQCpNTjRVaXgkNCNuTEk2ZmZAWCNpNipueUljNzN5eCpU
QkMpYnxjCnoqX25IMFhHYkQ1KUQkcEtObCphKjBFVXZIdFFHKE8xTntqREt0X2FxOE0qIWIzSUs/
dURhbEd7YCgmTVVfK31YXgp6Xz9FbkQmazE+LTdgSXVDcSE1bG93WFkyR0JkIXB3SVAjbUY2NGZF
I0I2NWQxO2ltbjtBZCYlZENhUW52ckdARUAKenFlYlRsbF5ueVI8VDhzVWJjfC1KUEdCMnBWPVpt
Q15MdWJGVGk+OEtTVCpfZXQjYS03OUMmaGRVe0paeldhdXJsCno7b05hSVp8RUV9dn4lU25OKipf
flZATEgqTUl5KmY5d3ZOUE1GTU0qT3R1dXFtLWhfZUEzaD53OTx+JSt1SEZ1eAp6UHt3MSg0Y1Ft
byFpRDdVQEkzcjdsJmIwJGQlJHNWPH5KPlk0Z1dnb0MreVk3M3UmVXplPHlkPyE7Vlh9Ylp3cHwK
el5NNmRMUGl6QHlKVXsxX1NGaUJJU1VKa35QRTEqSTZFOTNwPDVjUmA2KGohWlJVc08zNl4mb3o4
KTt6dFp5cnUwCno0RCQoT0RjT0glSVAzaTkwenApPCtsPzBpQ3gmUj4tc2pmSnowUV5jbHZ9akxz
fC1xNiVYTF5qP0olQyN4fkA4OQp6KkdET2FEPjg8c3g5RCFDUzI4QmFsYDFrMzVMWlVoQk9+QHdr
YDM/a2JoSnBYJXVEQkF6Vj8xYyVXMXh4aTR5NEEKelZ7PX5tNyVEWH49eWg3bmAzb21sJVUmKDUk
NTg7X2k2PkIrKzJTakV0TCVgfkBIODJDVH57dHAwbEtBbzN3UyVnCnojS08hckY0ZmpteGJwKiY0
SmBAfDNpVStEJGpXfk1BUD13ZCppVUxvPUY4KmZDeX0oKzYtXnRNMlpKZSprJEtXQgp6I0IqMnZQ
MHV9UE90JEJFbVEpSnVSSCtCdkN1WWBqNXhDT3l7QkErbi1LUyt2WWFtPjg8TzJeWFVJM0RHMVcl
VVYKejU1KytCX29YRVE5bVVRRUlpSGpWdyR0WWYqem58VjxfKE4/VnNyKCtEK2hrX1MySnR1KVJ7
Y31NWVVgLWZyVlV2Cnohd2E0I3V8eml+TipNaW07JmdUdkgpaEVEOSpkX2d4SFNaTkAmPnUqXjB6
WG9RTVIxKCo2fWoldDtrT00pVWlzawp6cnwhN3RMUk57ci07UUhYeWQ3NXtLZW8yRV9+emB0JFoz
WXd2RSNJOXNXSXtLRUFnekRCJGwpZ0lpUmMyYXY/YkoKem5pS3NULSM8SihfNGs8R3Jqcm5VRktC
cHdFLWAoYjRKKF9vLT83MXs4JDxwWXI4a0lURHFETDJUeklLa3tTKX1zCnpfVlJHclFmdEl+VkJm
JjNicDIoQ2l7ezFBN21fbkN1U2tQeyEpM3Q0b3pEN25GWVZNNWpMPytoYzBJRTNjPlZ0SAp6QWZj
bD9IIzs7KkxYKEM4WWFnbCp1REVhUHtRaD5yfDg0T1coa1RYSFhIRmdNY05OdlNfNH1HekhzbWZq
bUBiNzQKenpsKDxPZmk+O25CdkdnR2BLMjBrTGg9NUVYJH4xaHpVblJBZiohLW5Ea3BkSDtIaVVq
IXxseTdQN0k+Wj02eDNFCnpUQl9ZRSNHdVNsTFBXUkA2bV5lP3crbyYoWGxROFFhXylKM25hXj9e
ZTFBUndKPyhxNT5+WWk1YjZRNjlyc0pqewp6V153JmM0fHZAbmRfNS1naFF3dkJHP3xKU3YySkpL
UldAdVkwTSpeTXZmT1BlSiVLPXhzOG5gSCskV0JmK3U3V3cKem81Xj4yVzk2KVArZjdeMj8mMDRZ
KVcqJn1jUEEzQngzbFZSUzV3XylSSSElUjF8a1ZoQGs2cn1mKEkzLSE1V15QCnotZH1XYnsjPHxC
Y3BRbT9SNEEwZmU1RTgyJXN9TWlKX2crZVA7e1FeZFA5eW15dzRZWHleNkc/PzV2WnVBfSghMgp6
Knx4NyNYaUIkYmB5PXJaQ2xCPU5lV3BWUVAySH0tLWR+KnwkTlVhKS0qe2M+KFlwYVV2YzA0eEZG
KWVHMXpPQXcKekF3NDZ4JT9wKGArYElkJG1zM3YmKzBecUp1ZFVzRVJ1a0ooP3xTUklmVFV8TlFf
cWNnTkNYdmZQMG9ZZ28rZCRvCnpXNjJ5SHVmUkMqK2U0ZkMpMXklbyFPRGk3c0V5ZkgjPnhpUSZG
QU41WlkrdTBPUGVhY2stZXI+d14yNDAjZVJ2aQp6PWQ1cDYjTkYkISk5Tk4zQyFwN1pnKGx8PEZ9
X0dAaURSSlgzdn1JNzZyUWdtR2p5Y1lLNmZrfHR+WjM9SXRrTykKejcwcmFAZW04S1BpI2RaOUpS
akVHRkxiPnhtaVo8bF53IWMmZlRCNDhGNTRBNCVkQzMhRXxiZXFeUE1qJj9+aXZOCnpfanhyI0g4
V3YhTnRuT3pMQkpLI2phTzZoKktzKHwlRWtzXlo8PWlHJmB2ciZQRUJ9UGpfPUt9T3x7czIhMjV5
Nwp6IyZickBqLTVWTG5td0ViN2AxT3wmRjJpYDAoMSVTMWNgQlNnNjlxSlpGNHN0ZEB4bShjWTdu
O1RnJSVGQ3hqbT0KekJwPyU1b2UjUjJfXktAXkQlSl43Rnc1fFI5WT1ReVVDd0s3QyFNQGd4IzFL
WGZwR19VTih9fGNeV1hBNztJTWhJCnoqSGklJFZCYnAhckF6ZE1ubiVBJTVzYTs2YmlmSVFiS3BX
TjY4WkI8UGYlYjxPd0tXPVpedz9WbzxFfX0yPEJuKQp6P0Y5MTdDZVZJbEpWLVJrJF9vaFQ/TDVm
NzJ6KDI5c0M+RVo/Z3F+K0tkJCthUHNTSjQmKWJgc05zX2wtXmwpX2oKekh2JiNzUmUjX1ZocVBO
JlZDQCRTYUNZY2g+KmEjP2BwcTRydnJ+b1M5KFY7NXtUd281RnVUeWk7NjlvQztRdit9Cno3alBg
eXoyMns/UF9hUW5QPlElfT83aH0tK1NQUi0pM3k1Q2kmaWV6Wn1URlNXMCNqLVkwVlA1XnFTNUFJ
a01JQAp6X01HRjd7cDB3azJ4WWprWSVoemMrbW07MDtCeyR2cDx1MUQtNDVFYlNrOTNvNipXSUh0
YjRCIyF8VSNXX3VEbXcKei1Pe0NiSDlEQ1JhPXdiJERuQG5OSjxYKVZgfEk0QEAwezNJbFVNU3xU
U35fNzVlMk9RVFRnNyZvbSZ8VzUqRT59CnpXSWQ5QiY0X3QwNTdTdElrRl95eiZkO19qK0hROGYp
bGgrY3QpRmt6V15SY2c2JG0oMGhkaXBZQmRuXjFtRzFTcQp6I3R5bX5XXilLVjFkRXZaSykmPDl5
VkF4OGlJR29FT1g3flJuYnZHaXc9SnhfWGNoZ18qYnhjNGJfbmkhRWN0PkIKemV+d1dkYyY2WmV6
VXVqZHpAfWstNUQ1WihMNThVKSt1ZHRuQkhOfllpPzh9NjlBI3xDJCZvWlU3LT44fGNBM05fCno3
dCtyI0ZNanVMbVYjQjZTKl4kK2tVWnwta2MhcUpXS1ZmTz5+OG4tYGBLclRtdyE9O0kmaGR1dnRl
WTdRSHFaQAp6aDlLWFkmMkJTc0cwMVRCMTVsSkZMYCEpRGBWNl94LVNEYWxDdiVlcEYtbipMVVE5
dm4jP0ZnMWxASDBUX3pXMGcKenVhXzVCVj8/T2QrbCpjIWpkentMWVp2fHhDKlRXTDxoNCp0ZXBw
LUg+b0pNQCVSJm1LNF5mWjk4JDBQQVo3WWxQCnokaUJYWCNRRHEweTN1fFAzVyolVThVWEJtNm84
IUgwbG5fQkZBX28/e1RwKEpjdGtrb2clK0FoRjYxdSFaJHpxUwp6UkJfMTB1KmpvZmM7KCt1aShA
anlISkRSaDUxfnRRKlV4SilDO016aUZvO3U5PnRvS3FWLTVtJXlJPEN5YSYqeWUKekE5NjEkQGN1
VzlLZXxyc2BRPj9gXkNKN2c3YTs8TU9rKUdkNX0rbktXPVlFNS1lJHlKN0BhZCtIenJDeCswUiZM
CnorK3lfZz9GWXNNWnV9dDN1YWBZWnNGMHNiYjBNIThveUtqfDtYNmNvcjJhbWxiK2B6XnY2bEN6
Pmo0OSV7YFhOTwp6dUdwSTBGc1UjTl5RKWVkVmdmMTNkI3VYKFM2Znt9SmNnUSMpfXV2az1kbz1V
ZnJUXkFueXhRY3U9SVFZbjQpZmQKemhuMG1LVSZ6VnY5ckZtem4pdiZ7KXRGOV9ecWY2a3F3fnRX
dSsxNF5sMighU0M/MlohJTtufis5cGNzNzE/WVd3CnpZYipiQUhYZ3tMZFdoI2BkUDBicG9aUkZs
TmFENUlmTjFWSTZmNVZIUjNJXypVMHRsXj5EYSFnRUo8ZkpQJVY5RQp6TjYwTm5yX3JGWXRSIWRr
bTg2Skk7TnFZTGp8M2RmbX5iaTRXd1ZnO1gtODE0NC1ffVZ2IWJiNyR7NHY9PWwpUE0KenV9bjZp
eWRMX1RKcH5ZZEo1cHg+fEloITM+S291bT0jYCo9SytoLW12I2RnMUJoajB2K18hQ0pxUGJnZnRn
T1J7CnpPeV5GMDd9NGs5SzkxNF9gK1ZoUD49KSRqb3BlJmhxTk1XcTw4LThYdX1mVSYmfis5NXZN
M2FFeFZOX2hjfUA2UAp6NTYqbjMoKG9KTSZrPilWaClsdkdWdE50ZWFsT1lDSGdnSUpkTmVrQypq
b3drNj9JMX5OQHw/djdVY0J0QXsjKVUKekFBd1YwSzZNN1l0VkVTMUFLVGxvSnpoZkw8LXE4YG1h
T2J+KlZLN2VgOGBxMG1JQlYhPmMjbmVheiVIcCgyckY3CnoyP2BqY0Imfm1pMjFDXnNrOVNIKDh4
SkApdmRMaTdKbTwtKCM2bV9iIz1aVihmUkNzPCMmPDNETlE7Z18/OyltYwp6anhAQEkrLTdffHNU
THo0X0VeXjhkO3laJUY7Uj48M1dzTkVTWlhFeS0mWTR4dWRtYD1tU2VkJmBxNyg/Ui1PJDsKeiF0
OGNPYnImLTkreUZ2RXN2QGw7cTY3Yns0SUBkV1dXNj5tJTMhPTZ7VX49I2htWjRnNDljWDEofVFg
KihzdHZyCno0YVVeTDtoUn05UylWeyphKTNmVTFCWWxYIz4jMUJVeilUJUpzWU19PUZ3bkUlR203
eW90dH1wMERAd04zNl9jZgp6YFModzx7a25oJlkyMlEydEVMcD4zRT1gaz5jJFYyPXUkKXA8OW1u
ND1meCMkaUIoblghcGtDdT1aQVRQbGArIWQKej5XMXRKezlgeytkaSR8d0hqTHdGM0skRUZEeihh
Vmg/ckF8bUAjPW9qalVYM2UrQzc/K31+bnBSTyp4fWFHQ29FCnpEdHoqWk1PMD5AcXQtNSlFN0JD
PlJ4WSlvQ0JqMmZ4aihZclZMYmw4a2FzQnB1ISt7Wl9gLX1hTzZQaiNteExeaQp6RVE5KFRtVndN
JmJUcE5IdWkxSzNGbVE+aEJDUUxJJjtwQ2I8TGsjUWJQYXB3bWl9OS0kZUB5MmdTbj19JFNUal4K
elNHQTVjWFczYEdQYXBIRTI8WHZBWjBiRE5eO0h5eGwmcEEmUyVaLVU0O1ZqdVREQDYkWCtGc1RC
S0w3LW9BNmZRCnpnRjQxQWxXLVhwMTx6c0tCPChIfnFJdGpge1doYnxjVDA9UT5ePUZmc0dISUcq
aCV4MCh2RUMlZWpoY2JycT9IcQp6Nzs9Vj5jWFp0NUJnKnlhdTY8KGRGMEF3JENHKmVDbiZJRXoo
OGIlNVJZZS16NUFGI1VuezV+fSE9OUo0JGdCKmwKeilBOXtzVEkqeWRhN0R0UiR2RGUjbzJEfX5O
VHU9MnFLaD5jcilLOT0peDhESzRraXk0X2VQb0slRipaaz8kU29kCnpvN1dIOFgzSH0kXlQ5aEtA
YE88JHlPTWNWbnw2dCNDNlNPZ2JERzJkRFF5eXtwWVZFUT5LQEJXbDRlTmA/PSVgQAp6Tj9UWU9L
KE5Va3wxPkVZNntUan1jT3swVmhpISF0WD87bGchelJ+ZT0tejN5Xjl8dkE8cTA8S3s+O3F5b3hP
MmsKel5qYCUrTyYqX1o7PX5Ab0c3JmxxJXVlRj44MkoyZnZqSDUxbCl2NDh3JihsSjNPRihZQipy
NC1WNmF3WSN2fGckCno0UTlSNHc/UzslODJPT3ZoKDJPVHgraylnPjZIfnl3T2NSPjI0eXNMT2sj
S0QhP1lZcmpGdnt9TGgxYThocXVSTgp6IW1RZDMwWX5mNClORUomQUA0fkItTzlkTHZDSEF2ezxp
eCt6TFZfVlItVnpKez9LMnNIeFp2SVFDVGFSRFUhczwKektpS2VneTtXVEYwMi0+Ny0tYD9kPUpO
N1BsdGYmU0JSWChkJFBJITheMVJufGA2JFFAUkYoK2BMRihrPlYofFNmCnpvWTRnK3k0VW8pO0Rt
NC1zJDJKIyFqTmVhb1A1M1YlYEQzfnVGKTMxdm5iIVFEQVYyeU9QIXlrXkFVfT0xPn1aZAp6cShv
bT0lcHwlRjE1JEYmZVI0IytvVURPRyRPK01aaTdRN2tNMXdiUml4P3QkWHxQd3ImMFNteTl+VyhW
QlEjPTsKendGenVfXlNQYC1lb2hoOSZtYkFhLWpYb3xobGdxc2srO01BbDFSeVY2ZDhIV0tOI2pS
dSNfV1dPK341U0YyS3toCnoqJm5VbVA5YClPZXc5WUBhXk9nQUJiVTZ4cHFlQVd4O0ApJFRnbGxE
R3Q5TlAoVnomWTtlYDI0RE8+bV9WZEJaawp6PnVpbEFmPCY8cGo/Xi1WbmwjaShSV1hsR1h8VGBL
X09vKEVDdCpfUSFVPisqLW9wWigla0YtPExHK0FaWHBuTXgKekpFcVRfez1ycGp4eWlfJE98QWxF
PGxve0ZWeE44Uzx4eCo8dllXYSEhPjF2ZWdgMzFtXzBNSHJyYi1WOVAjTV5YCnp3K0BDRzx+WlJQ
cSszaTEzeSFUK2UjI0BqezNZIzRhLSttfWt5fFpQdzFrS2xScEo3NGF8MUNpSWA7M3tBMW1EUgp6
M2AhbXM8JlAmRmlefENoZ0RDRkFoZj97KXlSJF9hJjc0JkQkRUk+ZGM1RmokLTM9S3JjeCtgNl4w
e19IcTZMQnIKeiF2KDtGVkN0aTR5JEk/OHp3RmQoNHtpI2RHdGMoWi1sI21DbEU/MUNmNE5LMkst
UyQ1QGNaZj1FYTxLTz9iVUltCnpFP24/aDNlZ0UmP1c/SmUxT2FhfVdpM35IMUM5Sm9FfEBAaiZK
R3tBdzZEPXh7bTMkVnhGeHImeUU0X2pBRCNVTgp6JHw7ZVZCPHx0b1Ize1RrPWg5UWhaeHBRc0s9
K0Zze3MmNyNIUz0xLVIrP2Fmbzw9WXQyX0ZMbiYyUj9US2FGbGAKekZ0ZUw/MyZTa0tIdXx+bWo+
TV9wQGdtaHw7SDljOUN9KGQtMTkrQG83VSRIOWZqKmwhJHdMSjFlO25XVEc9dWxSCnpxZ1ZNOGle
bXF2JStSQj4hVzxxNyU1JkJ5Tj9IbWw0UF91cm5uZ1F8M1ktQ3hxd3NOOyRDQzBsTlZiNDA8ZGJS
Uwp6OEhMcWpWX1NgKEg/Rk8hRT5Ke2I8c0xtKCZsezwwP0c4NGJRcFMpemo5e1U1bjw3ZUNLcD9y
MCNGTytodmImWWEKenJtN2swNihaKlZ5ej1MSTkzZDl9PUxGcXJoKEtxQSVONEJoaTJ6bGNMYDA+
dy02U0Y3Tzg5JT15Vkw5M2tDJXZuCno+NzA/MFVndTZCTlBLfXR7eyopLSVWJVZzLU0kTGI+Pk8k
K1ZLfUpZWENmZzYkI28oSkh4a3R5QG8xKkwxYjE4MQp6ZU5BZ3tEXyt+dDEjS042Tk02bmQwYk1R
MEt5T0RYIW1sSUR2cT5XenJONms/NyNBRz1SVGhhUS1uMFpVbk1valMKenZjTz1mYUFXZEdMJHIh
fE1SYW1VWX1US0Y5QFlBKVBhXzh8U2tBSl8pKytTQlhvZkZpUkl6VUlVcURpek5AWVgoCnp4U0s1
cVJsWVZaMkQ7OXRkVFkxYztIZUFBUmdSYTElVXdpREFGTT9SUk99dWB4ZERBPzdYUGo3XjJhYGJF
YHFrYQp6c09gNzctcnxFbDZBOXlBWWJMSVM5XlNJTFJ4Yl51Mys+USYjOClMJE5hJm1mezBMNEc9
NVZgQk9ZbUYpWnxCfnEKem4rO3RRd0NOWEUxRCt9MF4mJDZqMytfdiNDSkwmb1MwQjUrNk05Knxz
VCRJYz1HY0dWYykzJTVKaH54ZXZieFRACnpFUUh8YWZ0OEpoZ2NZRTQtZTxHaVolSk4rT35SMVQy
aEVgT15HIUlPWSZrZ2x1I3xMZT9gYjA8eHBldSRBNXJ4Rgp6JGNVeHYrd1RjbmNSUnJISEc5eG11
S1I5UGJ4fVJUQiROTXBnLURsVW1WQlI2b1duKVkyVGwrancmKkMlLWwpY20KejgxeWRVWTsjcGFz
SX1BeT1lPCM9KnJINUUpRWF7UmFKRHt5KGUqNG9OcX1US3hnVXtAXjs4bGZaKHtiX3E9K1Z3Cnpo
STd6YUt3UG1NaEt5UkM+QThUcCtTczRXd0JfcEl1PSZ1NCp8MmZAOUVjdWFWTnJPNSQtUD0qaTYj
SSFlc1FjJAp6djdOTiljcX5hRDlRP2lJX3gpWmFSXiFEbEQ1Uig5TUkxZ0Z4K0JrVGc4UTxOdD9+
RW9faF4mKCpRWHk9SktgdjcKej15YXcmZXRvcFFhQnRzQS02KDkqRFB8az94dVQjO1htXn5eckU7
NVpzdU13bTU8d2RAZjI7N04lRzNgUV5kUkVRCnomfiZkLUhyV0F3SVYlanV2ant5YE5vbilgd2xe
cGVDPClSb0c/VUlmJTd1RSo2fXNXcyo/O2FAWjE5fXtOSyQjYwp6MGU4PyUpRiErS29Nb2NTPVNW
cT9IZnEwYDVxS2FIbFBgOUprYmRqPlphanpUJUs7JmxpTjdUIXM/ei08aj1SWFEKejQjMVNtIS12
ejFWSWdFY3hUeCs3VEsjVD1jWHpJZzg7Rj98OUx6NmpPMHYhNzRGTmtQUSMlQ196TjtqcmZpMFZM
CnpkTG5OPWFINmFPP241KnFeOThwbnMtRkQhQXtTPCNXKll2NXtpeH5rI2pwNz05VnlCNXFjRDc8
PDc4dD11c1FSZAp6YSVhQGYxX2t4SVhSS0RvQG9aNHlDV2FZcXlfVUEpKnRJbTBYfiFWfT5vNmY+
KlBvOS1zTyViayprVmxKRiF1cDMKeitMQT9AQnQ4TUA0K2JQZ0hJIzlkKHhDNiZ6fkY1SFZQb0Bh
YGN6PFExZmB1R3VjSiZSTzJ5RUtQYnZDZXkjUHIrCnp5M0h6IUxeMk88OyNTOS1he1pEVDlWY3ZG
WT96ZHA+fEh+cmx9ZjA+PmNfckdae1NeRytxUD5lR2J3Qks9ak03ZAp6ckx1e248bDc/QER1bUVF
dW87YGpRaXllPlhIdjlBYEtKakxHX0s/dkRLTj49bTA4cU58STRxJlFNfiNMP20ka20Kel8renMz
aylka0t4T35FQFM/QU5zTFNrMD8zN0owTHJJOCZOWXlFK3pMVUZsdGtZQCFhO2pEangwWVR3JUMx
fVZqCnpzZW91ZiRZITFUb0FgO3ZAalNPTTZPcXNwWlhySEo7QVd+USYjSG5VZjgxVUVkc2JkTktD
MSVYYSRRUyZwSVMhZAp6bzVQfDRmTjctTmJUfU8+QUBZRlIrUS1WNVN3JlNzc0xVRVchOHk5WEZW
X0UlPEQxbk9QNTVwayF6M3BiYCYtVl8KemxtYVhPIztNb0JGQkdOX0s5ZShRdy14SHNXRH47VEFu
NVdgOGEten55dVZDVzJ2amA7Jlc7LT03MndYeks3OzReCnpWVm5XOVJCdFokUzJKPj5Qa283IyNk
XzZyNDlsQHUzMjJuSV9fPTxNWUY8ZlVCTl5RY2tiVEEmPHNOMTIhaHlSQgp6ajY5c0BDSXFUbkB0
WG13V0Y9ZjZQMDY3JllZTFJDaG4kc1I/XzZNKEgydWxLJVlvcENIZjFzUzVTdVpAKUhQZEEKenkk
PD8oKzNRRktUQz4+fUg9QElyWGV9Q3NaQiVKXztgQEpwe1VKNUxzWS1EeFVPZHo/KkJGaD1fJTRD
OWhDc2t1CnpxWCZHUnJ1S0gpPWVHVHVvSC1sS1NlamQrRD55K1VDLWRQMmV1PVRkSHNBPEM7Q1Bx
NTJCWEV2PypZdz4pOWZQfgp6azZYSkQ8IStvcFRAQ004dFE8RztDXnNrY2BQdTAlcz0lTk1FPlMr
LT8kbGc4MSl8Vy1TKFVuY3s0Yjw5aCZfclAKejNvNXluTEE8TDhJTithRlooKVZQc2pNYkZjU0R1
TUx+flFva3JZWl5pRj07aXwxSD0hTHJJSmBtVHVXQmhOTkoqCnpWOCN9a2h4NjhlJjFNSGMzRChT
YnMxbmJ0O05OTXdoe2JzeSVvbTRUOVZ3dU1Pb2MmSUJkSlI8VC1md3hyeE9zVAp6XnpNTzYzNntR
MzM2QEwpY1VEVXJtR15pRikmKkg4azMlS28pKFVwdihIQzNge3soVURgUiFXPmY+TCteNEFTelgK
ej52aGo2KHY+eXIqLVIrTiFRbnNXVTx7UklVYl96WCY3dnZaR1A0STglP31KdCtga0ZJRElVTWtu
QUJicHZGcTFvCnpTIWs9WEshfUw5dklTQTR4KnV7amhUVWMwY0t6b31LYmQ3MG9eUGo9VkxBJUlW
ZEZNfFBFYm00a0x4cTRzVVc9QQp6UDt9PyU/N2ZTJiFCb0RiLT9EYFNHc1lTbS0rYXFvMUVYUmo/
UyQ2PktlKzhCPkBYXkxzdWI+WDFmPFVrd2YzUyoKekVNMXt2SilGXiFKfD1BRk5hY3FRO0R+JSQ8
UEQyQFRtdiZEak5ONEl3ZUIlWVhBe3IlRDlCVTVESCRHdDB3NT9CCnpxfi09a1l9V3YzdERXPmZU
IW9tRm1SMTR7Py1hVHhlaVA1SnRBRT0qeU9iIURPZkxrKHcmVSZ0UWh8K2NMYS1aYQp6Tz93KSZB
KXlaT2xPMSUtRmEmdT8jclIpKi0+d3F7WWRTSjVATURWb05NN0V1M3dhV0ViVlZBYzQ5VnsrSX1Q
djsKeiRaOHJ3PXxoRWJhNHdVPHpmUFchaTdsSj0pOV9+OWNMJD9pWTBiTTNzY29LKT9ycEgrUX5u
fFgybDRkTGMhdlBaCno1KGQyaGUydTEqb2ZZOTB2en4tX1JTQXFNMkw3WEErcklnMFBWWTBuQVdD
RWRkaTJ8OTF8Z0AjaFc+Kk1UdHVeXgp6Vm48N00hfWVmPUM0V0RjLU5oKzI3ZyU0cyVTXkdBQzRE
OXdgYE8jYGkqJkx1R3ZnYT9iYkNLJlAqSEF9dn5NcDsKekN3a0M+MXs3UU1qQER9fCh6SVBNITI1
KUJBJXJjPj5RJFdFVXE1P2AydioqfDhAKWN1NV4/N0dMZHd0dkZ7NkVBCnowQmRzVW1BZ0tpU05e
OCNlJT58eFJIJmhNdmhSYT4rMEVNbCE8IU05Q0U/NzQjLXNFb1E5TW1TOXNIQipzLVp9PAp6fE1M
S2hibi1YIT52fj1fcXVGWk12djtkSmRWTXIpTSlzXyhxLWNKMDE8enBLUiVpZGxkNmJzdXRzWTJy
UWh+NWcKeipXSDNsMkdYQW9taXcxVihudm5ic3VWRSYpRT9pN0NvYzM9I3M/Mnd3XkxvNnJ+MlU5
VCNvUjJjMz82Qm5IVD5kCno9N0FVV1F9JE5gdDExJik+bnZMI3kheztUdl5LRCFUPWh1Tj4yMlJH
KGs8fVM5NnlfNHNYNzQrbjlBbmU8UUhJdAp6YCM2T0xZKnZ7aXdJSm41MV41YiU8bThlcEpBRUs1
UFFPNCZwMU5HRSZGU31qY0dSZHAjU1k+XmNwOHpeVn5QcT4KenZhaShBZDMtQj48LUYkcSFZX3h0
PVYpZHJ4fV9iR28jQV4+VmhESmBuKzs1VmZZMTgzOUBBank0SDsye291YVp6CnorRTFVTUJwfGlD
V08oeCV3OUlfdS03NGstUHM4VEAjOUx8bS02OXhKUUBFfH0xd2FqJmFWKkQ9N0B8Y0hCUFhofQp6
NUxLVzchJWYjQzB3TmJ0cUgyOXBjMldEUVlSKz41ZmhzU347TDJwJmRkWmBiMThraDA+MkBHJiN5
cF4yZEV5cHwKekpTakQja3hvY1FmOX5tSE5KaCsoMn4ocSRzbjI5a0psQSoyYXJzI2lmYUdhdFE0
N0RAYTxzIU1PcmM0aGhWMStkCnojZ2Bza2ZaeDQ1bFdmTD1VfEtPQjtDcnZLMSVTQSsjJlEleXtB
TkhTeUc7fnJGQWpVRHFSMzs0cnxKTCojPG1+ZAp6SGk4a1RKcCMycWw0P3E9Ml9ZVWc2c3o5KVZD
TWRFVDIreVZJeDRpbyRhOCZFUD1gOWdRMytTdTZtUXhEXkZuYEoKenZwa1QkWkRYeXRIfWhWfEt7
ck44YH1RVWg7IT5YanRtWmVQe3VMdllWQXAtOT9rOEh2WWFxYHtxcT5CejllP3xYCnpSLVozMk1u
NUQqJEplIzkwO1p4PTAoQzFePGloeVNvMWY0M0g5Q0h0YHFpeTRvc3g0PmtebnVVSy1ZUSl2fDwh
Zgp6SjljYlBqIStVYCF0d2RsRlVXMj98QVFxbWcqfipCZzhtejcjbC1tIW04OV42PSEhdUk/N15o
TEJ5SF52Skg+LUMKekUrV1dWMl9xQDlOSFgrQE5DfHZeKTBQeFcwTkFjVzNIRCl9WXU2cHZXJFRl
MF5jYyR5aytJeClpZChPVmRuQXBVCnpSQE93OFcqellgIXxYSmVeeHpAbjE3fURnP2JzYjdjU21T
NmRGYHFhRitsTHFMSyQwb1JWPENDYzhLJTJre3h4Ugp6TTNCKDx2VT10NjAxYFBBJTMpLVJqITxp
LV53PShhMkIqZUdgPUFeS1B7JDZwKjBZPExVZDckUVA1c0U+NmpBNkMKem94RHZUVzcoKTZwUT1h
OU9RUVpART9DOWolfVdBJV9KIWIzYzk/bFEhNGMqWERjSjl4dTd5NzFyZDgwNGomaUt5CnptKV8z
UGReUldjKz5CLUNwZnt9akQtfHVoaSVKIzc7NkhSOShWeVg2VC1qTDt4YFJFVTd5Ql4pdXBYST1X
Pk89cAp6ZEtaYGNFMlhXSEteVnNmMGRsbjZ2LW85Pml+XnIpWmE1U2ZtSDN7aXl3OTk1MjYtTCo+
S1Y2antrN2ExTzYlfTYKem8tcEw8YTdDRi0+YXcjV1V9PkMpIVheVz9pelZJSEJlO21IS2RpY0Ru
KUs/c1diM2VeNyliQEM+WEcmYWFNPHZMCnpfJHY8OSRNZl9ZOT5EPHMjYWlPdWQybml1QyVxOWoq
K0Y4R1pzfG1HXnwmd0Bpdlk/YzxiUV4ybmhoaUlYNVhCegp6Nyk8Rjdra1dvOHVDKD9uKGNjM25e
UWpuJUdYMVE3K2hLR29YPkdqd1RjPF9GQndFQ3heaDxiSVA3IX4rbkk3YkkKeiNqfkJ2JihrPmtT
X05BV2ZkTlJNPkdHTkBiRjVCQWt4emtyQW4xWkU8S001Q0smVkZ8d200dmM2K0BCZGRvWnRvCnpp
WGg/LTl8N1R3dyV5T0A4QjB0KnZNdyR+eE9qSzZMXmM9Y3szdTBNYWh5WDxXZFRvTyZlSHtlKXgt
dVlMWHFKMQp6KEZ+PmgoUjVLYWlXaD9YXzkxR20oUDlUdDRPajchZ3pzYl40JkBYb0E2bkg7WF5a
T0VGR1M4K2IjRz5xRHc/SV4KenckODt8QD5pa2Y8dzBAYHteeHNTTFFqc3RHKGNPZiExKE1kVn1l
MEtkU2A1akU8e3h2IUcrbz9XLUVTNjQxS15lCnpJeiNhXzA/c3hNUzBRVm08dEt1ajcmczJiQWhq
USRHSyZRVkNIIVombWAyOUJMQXVTVDRFJGYoa0hORmZ7UVgkTAp6eFc5I2xXKm1jfWZHTktpNVAp
ZDVhYDAyal58RTQkcEdnNjxIZ00yYyQlJDR+KXphJWZORGZBSFRAfWQ7R1kleCoKenEhenclblh7
PSo/SUs4RygxVmhCI08lXzBHWDxOUyY1LXl+Y1ZTM2NET2R0IUlUYD0qP3tBO2V1fShCLUtGQ1My
CnpNZCtZYiZTRkBOeUplbT5rZV9Hcj5iZyt4cyY9PmI3QHdCdWF3KjVHVkV0P3Q3PG9eWTk1Pkx9
VTJnR1Q9ZURxVQp6dnpMc2IwJkFrS3owTHAoeCZpUlc0UE9sX2RxWlR9aDgrX0IhOV4ydkBzZil5
M3RUUkxYRjtoflFYe3lwTjAwcFYKelh3JWpBNj5zXyQ1bnUpYCgrZ358QXl3UUZtNHNAV2hqbGxB
aj9+cUJmcUtGPVM3SDNnJThWc0h4en4xJGBxfik+Cno/aG9+RCFgMX1rPzZnN2BTeUFOdWxueWRA
Wk5ANVheSzxMUjBLQGpIbzdwRUVUbFk7UUp7JmY0MElYSTApez03awp6MyEtPHRLO2RXKmNRSE5Y
Nlkjbj9YKit5QFRgPC1YRW5CLSU5ZyR4YFgqeHsrb1JxRitweW1teTRkWiQ2Y3ZXP3YKemZRan56
QmFtMUxsVWEhenNNNlNkN1pwNDdZJHJMSmg+cUxTKyRBdlUjQkQkaT5xM3BNKHB+LUJiZmZKWD9y
NTJsCnpUNks1MiMtcz5DS3pkVT16KSZsPXB0aCF0a251cmtte0JIZzkwcDw1dXw1PD1AO2QqQSFL
YDhSV2lIVCF2SUp2LQp6UFVRWEoxOEFwenZuKXpLYENAbEdOeyNrZlEqeVJJY0tSRFArWShZaXNX
O3NETXxjJEotfW9DRlBoPGdpQnQwZzQKekZ4fTBlZDlZQktJZWsqSShDMjREeDhIfWpSUXtrPSFm
cnxqUFozIWQ7aGpONW53MkMrV2RXMmx2dFJ7ZjtHXjd6CnomYXo1NEt+d2VQWFoqO3I3JE5iNmlN
RXQlPjNAZjt5TEtlPyFRYWh1WU5QRGRfY3N6fXI0Y3oxZ1dqOFY/M25xPAp6aUttQW1LeDB3YDIy
NE1rIyNUUCQ0cmp6N2o3PDZ2cnJqeyt2Qno0UTJUM31WU3J9QGV2cHI7RkJSZmZUY2dUcGUKejBM
X3JqPW9KZ1ZoYD87PjNWM1JwQll1NXwmcj00bT8/Z19pMHl1aTZWeXdRZFp5czZ1MXBoc3tYYiZB
USF2bU1LCnpMKCVCYFl5YjNjT0MzbC0jamRwOHtxdk51LUVaQmtEam1lUypMP25mSlo4PXRTKkFC
Sj9FU2Y0T1MkaHw9TkZ4Kwp6SCFlY3hEJWFITDhRZS1EVzQ5X1JXWkdPUntHLTNlMDVSKFh7IURp
OEl7WkZLJW9ORD09VDR8MkwqfEtHRXR+TU8Kek9jVikjKTZNRXB4NiRiclpwcUVfTkklQyZYXiVC
d28kJGcpU1cwZT0ybTFBTVpWMnN4ak0wMiE4YmN3cXJ6PX1XCno/SlJDRzc+X05TYzJ0NkBpK3Aq
NjRWWTZYZ0VaMlVoWm8rM0xrITw3TnA+fj1vI0FwQkEme0FLVlR6SE5lTEp8PAp6LTtMZigjd2sz
RG85MnplPUQ5V04rI3p1TDtUSG1OcCVaTTsofjZWJmx3bWIoV2dpM1hkdmgqOTErb0J9TTVnNzwK
ek45X1FvP2t3bj9oeSYldVh0Xj1YR30pVzNMX1E3JiM0Pn5YRl5JbFIyPFE2bXBIazhPMXdWbmZk
c09oJXd0ODJ9CnpFcVlLezlxVDBpPDcmK1RfQWpjVUNoKmR5OVN6MiElXnlgZWl5OU9iS3FJPXNq
RWEqPF5IMmFBRi0tSjgjTUMkRwp6JmdyJnZWM15sKjY8aypIdHs5JHFLezU7K0gyUHBOP1RKbnl7
dVNkMz5DLVk7S1UhTVRHc1F0VEMyPHl9RGIraCgKejdxTi1MeWRJVSE4Nlo2YVRlaSYjeTY/NXJI
amI4IyFBQ3F9MyMze1N3OERwKUFCZkE8aCo2VW5VRDVBIz9pa3R3CnpUb1NuQHglU19qeGx0PTB0
XyEjTUVwUX45SzMoYXUjeFBRREYzNTtIOEMpY0txO1Y9Q19saj5qaGtsT3ZRQGhXYQp6WVp7MTI9
KmQ9MHcxRERJJWp2KyQkYypjNShIS0o3N1BrfDcmN0txU3d7Ul9BWSNsKHRUTVRRdTR1T1k/TG4j
YTsKemUwRDd1Nz9zUDVzdipmNW81bFpuX218TEJ0MjQxY0xkUXtPaXQlMmJZfVhlIWlRKlcreWxT
IzhyJmhGPEM7SHo3CnpIKzEodS1tVFd9bkxpZl82SWFmYmM2Vjs4cE1SMWJpUkA+XmFQIy13R2Y0
UypvI1lnS01ZU0tEQUpuUVJ0b296cgp6aiFhJE5BeTh2QSh1cEBYe2ZJI0Akfk9QMzg+diZAd1Z0
JChyWUtPbj19d2NJN0lCaiMqdjViNz1QaHxYO302SE4KejQxV08tPW9NaU10NSFTZmotQ15hY0FG
NFljKytXKE1UbnBFdlR3YGptY0pIS3c8KDtOek9zOWZZSio7YlklRGUwCnpiP1RlcWVDbjZMbz1D
akokfil9fllqPWhucT1takhlREdvYVctcjt7aD98UHdpciQ1bm40b0tHVCNRQUNaZV8lJgp6Q3xn
d2ZxaGMtTzF4TEVQKSlYJHlaWlpRVTR4aSk+MkY3JT9GPSE+c1lzeUpfK3RtaEAtVzJMbkJWJHIm
TF8oUzsKejxqJkJaeyQzSCpRVndmKmk4SHdIUEI5KkQrYitPM3A5JHM2KX4hSiYrLSRzN2xUUTk7
S1ghWV5tJC0xWmR5IzFxCnpUMD9KXk0yJE5YbVROaytsVDVXLS1AfjV9NDImP0hwfEVHZyFkdypR
dStOPjtqcUNicCQmSH1RZUApTEJMeU9YdAp6TXhNQkxjQjhoTDxqNjI3T0JibFVvSEZ0OUNLUShs
NGZOdVlOdm59SURpRFoydUQrY3tJXyVhezwqMitgTGFKdHUKengtPEw8SHczb152aD5wcVJMd0dg
ODJ7cWRROUpIRD59UGxYe1MlWHw4RHNkUGlROX4oX3J2OztIPlZIV0I5PX1sCnpDZj1vPF4tbkNa
dUdxLUJQKTVoK3d9fTRTKXpuKlRBfV9BZEkpcU5RUnxLUV5uanxlRmdgZj8yUTNUJWdwPDNDagp6
X19PXjdLUSR9WXBPJVkqeyQwKDxQT2J5aDQ7MWtLI2tOP2J5fExZWnRfJjIqd1YwV2FCNUpeNEhD
bzh2TGRAKXMKejc0Mj9RYSZQZ2pFP1loVlMzT3M4NTx5c0EpRj0oUyhiNDZVPnkoXml7T0o1K3ZK
SC1KZG4zT082OWJWVjFpJkdiCnpBTSNnMVVwLXQlTEQjKTlqQ0FtYV4lMkFVK2teQDl6ZXdhaGhS
SGw4VDk7aDRTV1p3b3F0bHNrZGckP0BgYiF1Mgp6VDBYY010QCl6PWx5IzZge0FMe3hAWUNOP3g4
d2l9an0jYj1sej4qVFYpWnpec2lTZkUtUCM3blJASGNCTEp9QU8Kekk/YjFmKnsyQ3s/UWdoPXdm
M3dePFp1SzxkayU+MHMoe3RKQCVgdmFHYGx+aXF+VVJZWV9EPGBWKEVxRHN8b0xaCnpoKzZTIT05
aVI4UGRVOCtIOXNQNlYqZiFscnIhO0Y8RzU1WG9ZITx1c28tQXBjLVZ3RztqOXU9QlhYaWQzOyYl
fQp6JmJuMjU0fXtzRmE9KDlsYFl1a3NOSH1uYW5+VWU7YCt+ZDljUmAhLVVDNz58aFQ3bHo1ck1x
KTR0UGFAMnhWISEKekpuZCFPbVdsWX4+KVkpQkFGNDFWTmdNRXw8YHZ2Z25iZFdJaio8eD0yI1p9
am5TLUomaDQxP31XIUkhIyFxPEFVCnpQPGJvdWwoYXFiQW55czBjJkpnRHtvVkZrYyZJNj9AbFU+
WighYFRrU2Zse0J1YmJOQT14NXVmSHMxJkxFXkJ3cwp6RzxIMVBxT2ZRY2BvTigwVihKZT5aYUR3
cGEpWjFuTU1BR1dxYUJsUiQ9MiRoIXh4V01ITGE5MTRMZyYkbnJNbCUKenVFO00tWUxVM3tVb3lt
OGB2dDtzUlBoM3JxdXgyTTVNOSNyTGU9blVPTklOUGsleSpMe1oqd0AlJGxQSUdtOSZSCnp7VjhP
cGR8TWpjTkQwMDYkWkIjQk8hYms4VEJ3RnNyNDJrWUxFc2spMyFJNmAkcGZyfD5peSlpKEhUYDs5
MGNuewp6QmJNdiY5LUVfPmErNm51O2FeSktefjRqeTw4PlVhdHcmYmdNaDk/eylqTXhkSXlXZyNM
ejt2TllxNEchPFNkWUIKekNnfXRnVFVJLWE8IzIqQGUoe0Q9bTh4VC16ZkNWV0l8NDsoTzhUfEB6
djxRUmBUY0lAV0BkZldNIWExMFVvM1FOCnpNRT0wYDtvPW54R3h4M1NpTER3ZTJneDhPNUFxKXZh
JEEhcmJ8TDhAMnJmbyQ+JlRmOCNILTReNHk8RTFtU0o4aQp6TTUhMGUhc0V9TE9MdkVFSkpWdjIo
Z2UpdSE8IyQzeiltPTJQS3BmfXprYj9xN2QxTChOSio9fUx7OTJlb3ZRR3QKem5yN1R9TUo5K3Fu
YWF2SytvZn1nNjY5Tm1LeEFndTdhd08pUmJxWVRzP1lZRTMqPVZEaSN9VDNVN35tYSNsM1FHCno7
PjVTTiM5RW5iPGltWUMwdEYzfiVsUHxAbHZZNjNfIUNwSkp4SjghYkpjZ0tQMzBSfXUkd0A7SEU8
VD9xcSpXdwp6JmlaaCopOG4qaXhTRWBUP0A7XnFYTkNDME07X2E3NktyWjZpeUN+N1psTmIlQlIj
IXRyRjJaI3FTOXQ3UkF8c04KejRfI2VPRT5OXlIrc1NvaTk3JXBkV0hLSVZic313JVRYflJ1WWp0
KSpDTUNLPl9IKDs0ND9kPlNKe1Y7b2B7UTI0CnojYjc3VmBVWUVNQVBJSkg9SDgmKl8hYkJjZjl3
LV5AXm1HZnsxKnd2V3xzTlF0SVdraDZILSZxZ3pSYTxyQ2hAfQp6P0NNdlE+Myk1cU40Xmo5SkVD
eCg4c041IVpUPSlAaHZjMilqWi00Um85Uml5YHglLWl2djZGdFUhe0olJGopcG8KenNuMnwxSDV6
RjdQUj19YG1DRHI7Z3dvR0pPezJ0P0VNQn44QT17KDBnc0M+fT1eOE5VeEB4KlUtWjhLeXN6cSQz
CnpZbE9mNnVaK2hTcXFKZj9pWE5TNGA1LUo5c3UheHJZUVdVMEB9dGh9Vl47Y3cjaDFvSiUjWVlu
OFUoNUdeMSlKZwp6JTtSO01Ackl1fE0yJEhUR3swSlhzPHlGKlgwYjRNaXtaMkJjZW1VbUN8MGls
VTkpdztxKEdmbyR9eD80Klg4c1MKenIyJmI/eXgtPFRVdXUlRj0qb0ZIRjcqQ2RmQmR3Rl5UcEAp
emUmcUU4MWliJlRDcDtYMX07Zl5MPXNnayZ7VWVBCnppWDVPKTl6dkdBRVFrdml7ZkZ9QlQqaX1C
Tl4mfkMrSnNqUF5OTCMyTlM/O090ZkVzMys4OWp5cEk9fT8qdFpGYgp6S0NUKXJzVCF7aUtYO309
WmxRN2c0RDV1eD9xSWR2ZEM+OT1kSzE+Z3VJZiRmNG5nKVBeaS1sRkcqYE11UT14fWsKejBXdDlE
Rl5hO0I7cTVlTVNsVXV0PHJaKiVJUUEjYlFJblIzaDxAZ3tfTllgZUg3YURySlYrUSZzS2lKN3Uy
WjxaCnoxYE9MP0xgRTJ0aCNPcWNObXd8VCQlJSsqbS1XVzNXbzMwU1N7JUd1OypVaV4hYEI5RE1H
aH1uKXZFKDxfKT11Kgp6bHN8ak5acGAxaURFSmJKNmZnQHAlX0xAcyZPJlh1VTlxZFpNaFdIO2BJ
a3FGMyZjU0ZmMWBJfEx2QihsdXhgcWwKendPaypGZ15LO0R1TFBGa1Z8R3loUWFEa1pqNXc1NW9L
VSYhd0BZSnZhbTlCVXlaPTNnY0VgUTQhQE4/IS1MXnYjCno7MktqfipTe1N1SDs3RHB8SXZacXgw
T3d5bHo5QGgjKmJod2s0JHRpYG8wM25wPjRfYD13fnFIQ3A4QSYydEJmUgp6eWZUWn49bm08S1Uo
PjxWQ0ZuSlJ7TXVwN2I/czMkMT1KKkI3OCF5NmFzIzE+QXEwfFhOJjFnOzZ3RDdkRjRrWnUKemxB
QWskMm5ZQ24he3ktR3NQTEpPcCp2e2QzRHhyQlcpKkBucko7LSMyflM9bEwwWFgmR2cpYjhXfWEw
SnlOWSFnCnpnMnh1YndLeVVDMS02IWQqXjYxWkphSD1BV3NlcmcwMHdyXyQ+RHN9N3ppSnlAQDFD
bWlBUkomazdsZkJNX01Bewp6MT8/eGU/TFV2YTh3O099bCExd2Nie2VTOG5KJkolY1pBQyVCeDc4
PHp4Xik8dHd7ND9JdDNHYXhpVWl6UmMlLUsKeiZQLWh8X1B5WG4xZ0klNXFtXzBGZVkxeHVxYiV+
d3FHI0h4WH59Ml43al5gdGd7eiVJMT8/X0JEPDtPTFV7UGhSCnp1aGYofnlAOHFSYGh3a0NeODFm
RTNFQDR8e3wyLT82Q2s1VUpqdjc1Iz0/REFHb1U2fnU5TmImUm53IUw1dUJ9KQp6YyQqOE1SdXZQ
Sj03bih7UGhSRWtyMUY8JEV4RGUxZmwhOy1UcHhmIyp1WWB0VE1VNG5qazJYdiQoKkgrM3tsd0gK
eiUhKj52IT1hMXUhKiVoJXBJNCpkRyhoNCgkaG9VZihDc183TEdLQXNySzx9djsmM1R8cTQlNU5V
ZD1LI21kP3g0CnpoY0RPKEVuVTRBWXFASGV6Y3hAWF4wWilWSnZ5JWBDT29FX0ZWVGRiaDtxc1pl
SnYpakgkRT0qTGReakNIXmJyNQp6N0J5KHtrPWQ5JVlMP2NGK0w1cEhRUUA1OHZvfmshR04zVEdU
emJAJnFpPTlXPCsrWFNWLU44UyZrTisrQUhnST4KelVTPV9KUlUkWDg2OTxfSnNBODZpa051Mi1O
P3VJSClsbj9lPTl1X3EtTjFuZHVYN3JZTF40MEdWdW8yNmIwbiooCno8aUt1PEdxezMjSHp9VyRP
TT5Faj98eGhEMUNyM2hndHZSM0lYUSMxJFJSSGtnN3QzXmgwc2tHOFhOQGZgNj5wJgp6Y1N0TUlO
WkpPRV99YHptRSZURyY5PDVSe1FiRyFuKFZVMFdJbn5MRmRLNnpqMmMpZ0pJPz13ej53YUJ6emYk
M2UKeklhRGNVTEBxIWYpUEAjPk9pWllpUSt+Xmp2OEBZXnBDKilSIV44PFNjOCNJSGFAdykhPndz
ZHR5elhQZ2gkcXhzCnpeZHhYOW0+fVVONE1yQksyfT13Vy1GUElwWjRJV2U2KFUqRW5aR35VbnAt
aTBxd3lyN3Q2cT9sJjFMaUozKXEhLQp6NjA9PkM1MDAmSyUyUiNsbllxa3BFTD1tQzZFKiNRP1Fl
dVZeTUdNdiVFSFdqRSlsMlo4bVE7I2lSNFNhXkltXy0KekRJOHAhNjRaezJSdnQ1KGwzejdtOSR6
YjMhPmBYRHZKenhwOEFMR2BgUDRgRHNaVWdsVWdtY353dEsjc0ZqMVRRCnp3d2UtMlJmdCs1NVNF
d1BwWFFld0FjayZhN2cqRDU2O19CMD1OanxUSDVwM0JuUUpuZVc7JT9hZGRqbjZANWA8Ygp6a3xp
fDskMUFiNEIkSmJlPilyOSh2QDh+cDRTPX40cGtNYkBaayZqUlF+Mn1FNz05dEZeOFVQZXRNKnFN
dWZaPmsKel40OH1UZyEpQXpfTnU4OWU+akl7RVYqeXRpVHlrakdjZ2tzckFUWjRWKmkjdSU8PUVf
dzVlZmRUQiFeI1YmJF43CnpWT21hOyh6V1Q5aHUjKXxqQGptZnBEQ0VeYlZCVzFIM097QClwcXRq
YEZ3PmwyO3U3S2p3RTJRPVBiS0lPc3NfYwp6Q3ZBeTFKS1poUFUxMyZAQTtaWiUhezEzN15eMy14
RSpsa0QlQVFSQXMyKjBNQz5nWGY+Tyg1T0woNF9UNTxFfnUKekg+dzFxdjIlYiZnRjUoRGZwdVgr
U0NCLUY5MU4ydUpQaWplWmlDVjAmeTFOQXpOcyomQiR5WG9USHpDfDMrZD1QCnohVEJ1N2ZaJVdN
S1R9UDBJd0V+dFFgOXFaZmcoPjJkYTI7fD42IUdDZylpYzVrKipSKjlFc05YOGU/OTdFVUJQcgp6
d1N3d28qZjZzZ0A5clklOV58XmNgbC0tVDtQVFl6MnNwWUYpeXstJSRAfGdDJCM2I3lRR1F1N21V
OWJWUWcoT2AKemJyTU5SNT9gKjwqJGkqSFhibCF3bT1rNzYxPTJGbyVBamZtZmNAaWdeKlIqN2lF
cWc0VjN9bCFhX09gRyE2TiZSCno1PyNPRGM1ODRqMDRRT2JKOGk2MC1uXmdUejtEZitLRW9AYTFU
Q3pMdkV0c2tiVEUweTgwUmNJdDJ5Tjxpd2Y2TAp6anRJd0I2TTNvXlg+d2ZoVkBDfmhyYUhlR3Fh
KH1IV3RHXjZWMn16SjYocDdNKXtFVXN5QFUkfmZIQ3wydGpeOGUKentOeUxXPylyVWxIT0FDJFM5
eEB2ey04bmhnRnkwdkVpbGJyVGkyQ3JjMj47VW1fQVZ8aXtlY3pyektSLWdGZXc1Cnoodz43Zkxq
WG9gX3JYSmJmaX10RGc2ayY1RSsmbEZiLWxNcSZRNzI7dWNyIUdnNHZeY182TDw2aHdUMz0mcGJy
Ngp6eWFxaFlzK3FWU3FfQTtoRFFNfEBFNTFeS21ialBwUF5TP0x2QXYpRDcrVURrWDhNdzgzJkJk
MTE7bUktVnlGRUwKensqSEV6Ky11ZzBVSH5vVTM8d1gwSH00S2NLKVhQT3tjTUA9QnRiQDU9VWxu
N2A9JEs3PDBuVkJgP2RsbyZJV1RjCnppfDR6dmwkeWp7SiV4VlRgfEJHZDV9MSVKTnF0dDUpeE4o
QCp5eU5WbX49ZkYxU040V0dGLUBPQVd9aVYoRmhjOwp6Um5gdj0xZHlDb0d5TWlFNk1iJktFbExk
cDltS0JsSFRiUExxaElAYzwpVzc2UHFhUiZySVgrc09qMU5WUnE2eDcKeiNxTGlDdkEzS2lUK314
LSZCXnZ9PmNXWlVFSmNRZytjfEooYkZ7dElVZUpkMW9hVGxRUGI3eVF4PSN3ZHpobndICnpjTilt
UCtKbTlSJFRpQUxiJClZWTZrP1p+Wnd0a3JAODIqTmskNz8hbCRxTjBaK1NZRz1qVlNrJXBVK21i
TShVLQp6YmViOShUJGhoKns4Z0UoZ14mWCV3QmFSajRYaFJfZ2w7Qm1hKChhUnt3fX5uJVpELTAo
dnBYJlUmbz17QTh3XnUKeldqWDdoZWpMZVZaai10QkVXZnwwJVBUN2A2SGg5NkxwKUpgQ1E5IWNg
UEQ/dT5OJUstPmB4aFBCdkx7TVlHSllDCnpQbWRmWCtIYU9AYT5YZThAaSh1PWE5UGJfQj85Klg7
XislT1kjcn1sTTMrQXxQeEFPMFZraGwmVH5xN3BMM1FHJgp6bXIodGs3b01BNUA2b3IoeXxHYSlX
c2EhQXZUciFva2dKZkIlPnx4RTF6enFKazVATk49PGdLKjslby03YCQ/Un0KeiRgVzxuYzd3dEtV
c2AhQEt2T0ZaU1ZEIT5Ocyo+a2t1MmhDWWlxe3d3NVhUUjtRITxwPCtra0l0dypacU9fXj9oCnpH
N3x5Q0ZeNkNscndOa09DY0UjNWJ1UT5LS1RLU3dRb0NZKSpAeTdiQ3pjJTVXbiMlbCs8OExjQVp6
bU5kY3FWRQp6Q204IStjcWchUUEoUkNvI1dAbEB0RG44X3pmVjd5bC0pfCZweEx9NDw0ZDMrbGRC
ZW1HJU41c2BrV1JpbXVeaXYKemUtc1UpUz5BO2dEKjkyP3luVCV8bU1LdDhVRkJOdzN0SUd5OFpK
MjA/aEI+SCptS3x8U3hZQTcxPyFJUnFZfUwtCno2MUB2WSpYdipQXzRqVkxUJjg0WTlmdmMjVkRk
QGNvdmI9MUMjVV9fbn45Znk5TiU3K1klR0M/YEpmT1FFYFZJRQp6STtINlFZcn1pMS1PaiRsd3FU
PCYoQHFGWG9RPCRYY3NORkljWkltYFQtLSgxZCo/fSM3RVlsfUVqaE9XeDNqdWgKemljWi0qQT9X
Rz08VDYlVUxARV4+ZXEkNWlEPl5HI3p7V00yIW5TaHpveH1mcEVsbGZAaGdjel8qJlc8QEpNKmNq
CnpZZD1HYERffHNIQW1BdilkXyNWOUMqMj9gSlomSX5AV0Q3Pit5VjRaUiRqRnsyeV8yVGYmVGYr
Y3VCST5gSSQ1NQp6OzNVeE4xUWNqOW5JbzF6QDVjPTQ4aytxWj9qSE1lYjE9bHd3UWNTRXgtWmI+
YCQ+MzsrX2hkVDhGbyR6eVY7Py0KejwyPjdZJjM4ZmY8Pmg3Q0twP2lAIUFDU0tPel99V05sOTF+
dmAyPm0rOT5rP3A7fTlqcHdxbjlqe0Y+LTJKVSROCnpRWFIwLUB2IXpIQGI+bSo1c2wqPzEwSGYw
Nm0rT09LMDRBUXRteFE7bFlrdD5MRmkrNTJKd04pKy1JTX5nanBvTgp6bjsld25KfDkxPDExQUdP
dmtNIzVfNDheJF9ZUUY2bFItKnlNLX1kXkJfI147Um1Md0hmeks1MGtmUHRAZUVkJTsKej19RTtq
cVBrJHotdExiMzQyTy1VJSNHSzVYWVkma0xgey0lalpVQGg5VSo5UWZYKTc3dTQmaDFGeHZWe0E/
VXFGCnpxSlIyZDZoJCF1RkpicTlXKERYbjFvWk5wdFpVLWdtcTdRKWl6VWdGOGsoRjBod0ledEw3
KHI5VG45JEt5PjRNUwp6K2w3UHZfQ2poQDRwdnc3OW1YWnpXKjAhMCNSNns9YjNeMjkrZ0ZzeEc0
MiFGRVo7P1FJJmNvTXBuQGc/cDRPMDcKemNSX3dFX31ecjF2PTExRlJFezFpKDh5SDdjJU1gQHZB
LS0xaUM9azdpciQ8JEw9RTUkK0pjNnxoWX5qezhkXkkjCnp2WGZjai1uU1VVdWlfc315d15OQUkx
eEA+ayt5QndyaWx+cUtKfUpZYFIpQSY+ZXJvc2ZCO3tIM0h3VUU/Tm40VAp6d3M3ZXpjUXFDI0tS
LVd2aHhzZj5pPXAkfDI7b2U/K3ZuTnwmfU5DdD9HelgtODJyJXIoMkBGallTWjt0P3FtcEAKeldZ
U2YodCgrQnVlO2YlYVg7QzZ6cG9YI3ZeJDhZPUlBaVo0WW1TJThoMGM1THVJTEAyKnh1bztnO15u
Y1VldTdSCnphRjM0SEo+NVh0KitFcyU+Y1lhdCpHaHVRaFEyMUU4KHg3NGdZc1pYP1ZKNihCOzlP
fThQaGVkbSZ4fU1FJkhGLQp6Q1Y+aTBNNTQ+P0U+dnEwY31YUGdKRnpQZ2NrQGpoUHUyeyVacjUx
Q1pOZGEqUz8pMUlLQkQ4SD9qIW9mdCEtX0YKeis1WHBNNmtTKD8wPilra1loQk8lTHw1dmNpYjBe
VS1CbG5oJHVRd3tKSCZJcl8raHYmJmZqR3ljMEtoJjZySFJRCno0ZlBieXRFZ0JgcFBYVzdiO0Vw
RldvMys5KVExaUNkbSk/bXItIWNoNGlIUH5DP3tNWU1ESl9KQU5oM3Y0dktVMAp6bWcrKF49KE9o
SGU3KW1rK29ERjFZJCUyLU5JS3VZY1p6NCEmUy1SN1I+Y2hjP0NneHk9Kzk8VnFQb34hYE5xcS0K
emNQR3pSKGhKU1o2Wkp0eSsqIXI+JiQ4VWswVmc2PXs8cVUlOHl5WXtJVl8pd0VJTV97eDNXbU47
MUhDKkY1RW9TCnpHb3MzcDZuSWJBUipxUUopO0FIQk1TV212enBJfkJkbW5zJT4pTG83TiF3e0h1
RnJXX09tbCtPcU9HIXBhY2QjVgp6ZWNmZUhaQFpoJS1UMzJxKCYhTk88QSlrWT5ab3VlYihUQTBr
JnojJWgtI1dzXn5rSWR1V1RtZmIlQzYkTG5UVGQKemBnZHMpVkckN3V7WkB+cUlNZGhkaEs7QTAp
WHJPJUF9emJ1KCtacnhrUnw0bl8qVmU1QDZ5MygxLU8yYjt8fF5hCno+KyQ7Zk0tRytgUThxZnYk
Jk1XK0xrMjZIQEZZa3lqMGt5eS14U20/KGtuVFpjdTI4e3I7RFNYS0ZfPihHVypvZQp6NklsKmhh
cXIkZDg3TD9XXis3ayY/MCRGcjhUNUtyNGNaZzhSQUN4PGliMSFwUSt+d3crRDdzKEVmYXhyNVBR
aD0KemUyMyF3QGZlQlI9V0BIVjZMTiF5aCZXbExHZ3xKQDtIUTh1Klk2dExmUWJfcDlffDB6UXJz
eGNNdkVqd1J5WiMmCnpYXj09MjgkUSVya3cyNG87czduUHdZOE56TCFrTn5zS0heZj4hZEZDP1Ix
fEt4b2tmNi0jTCtkQkN6aGhIfWVkVQp6R2JMYVFLIzJAbnotYSQrMEQ+R21ITFpFQWxzVD5Wc1dZ
WHIzPyt7aVN3bVl0bCprbTtUKik1dlBMXmVkIUQhaHgKejRUdzFiKDxFclpUOUtfPnRAIVgjQW5a
YE1DOyFlUzRNczs2e09kX0ohXllpK1FJMFBFbit3U0sjV35jPSVLQzg1CnpufSUwRkY+MXNPdThI
T2cyez1acSpNWE9rdGtsNSpwRlpFNilPQj1wbkImVnFufTNYfUdoM2NwI2J5PWhFJE5WOQp6MzRp
MXApPjxqbWU7djt0KEhROzg8NFFJfU9VSnhweVBMRDBiVH5BX0R5PX4rVGBTMFdvIzhKUFomT0I7
WTRyZ28Kei1YbndhMEtROUwreWFtfEVqWnt7b0V2Nj8keFV5NSUwVVYzZyNRMUE9dm5tRmNSbHtV
ITRLI3cyR0NZKmZSZGI9CktZP1pXR0BjI2tiY2BCUiQKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoK
ZGlmZiAtLWdpdCBhL2FwcC9yZXMvaWNvbnMvaGljb2xvci81MTJ4NTEyL2FwcHMvZWNsaXBzZS5w
bmcgYi9hcHAvcmVzL2ljb25zL2hpY29sb3IvNTEyeDUxMi9hcHBzL2VjbGlwc2UucG5nCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAuLmVkNjhkNzEzYTgyNzVmNGVjZmE5NjYxNzQ4OTQxYTkwYzBmOTQwZDcKR0lUIGJpbmFy
eSBwYXRjaApsaXRlcmFsIDIzODkwCnpjbVhWMTF5b2VlX2tYKH0tUUJVJmlYZXp8JDBDUnpwcDs0
fS1RQmAyQWV8ekooeEhIO3EpNH08Zip7PWBDRFBLZAp6fEthPWxwUikodmQyaTt2bzFjNTwmYiVt
e2ApWl5fT2hnYV9rPXw4REolQXVNeFAoSWxjO01lWi17RGdUR0dWLW4KelFxdUZ5KnFyZShmM2pT
UXgza0tePk5HTEI3bnxBMHNWTDYqeEFBKGVCQygqTG1GR0xmK159Q0ZiKGpZbCFMUXEjCno/c2RJ
U2otUHNNKG1QOCpsPzEpREIkd0hKWlJORTc9YDZ5cmk7Tkh6QWxHYlFeIT9Zej8hJlYrbllva3Jv
REojNwp6JGpHOUskZ3JDamFJdSNGMU9KTlB3OyYyaU5fYEdJMiFZNVdgVVdZWVA8cGAoNUUjSHVm
ZGYlZT5SeCpXYVVjLUkKemlYOyNVZ2AkbzgtPXc+TSNzZFQtajV1ayEzejRYWU9TO1hVJnMmazRA
c25na01uMT9UJnd2en1rQmlBTj1GVUZDCno3MUBxXjUwPnhZO3daWF9LKkZSbGo0KlgoM0ZqfHp5
UU9AT0E2R2xNOUc7eHI+RU9DbUQpOWFPQlZGVFNncDl0dgp6bXRDNGN7c3g3b1J3KjgyRzhSYD9H
Q18zd0lJOytyRm9ifjtSfHlZTnFKZjclQ052I0Vwez9fO3hieD9iY0xTM0sKeiQ2ZFpZQHxWNW9H
cXR1Vz13dWBHY3YjJFQ/PkU2QVpwZ1E/U0M0QjlSbjhEUT04RCgmO0tEZCVCK3RkTHQ1SkxuCnpM
WEY0MCF8XmtsND99fG9sNj9pbGJxJGlPXj55dU9efX52aEl5QUl0MTxMeVJ3ck9OcWBuaCZZZFYt
OUAyZCQtYgp6V0tDVkRXUFQrSTR1WU9tNih0JUAwdF87ZUxYfFNGNzFFX0s3aVFweSMjMnYlO29T
fGY2bUJ0M3U4WU85TlN9QiUKemAjXnRsZHwrVnNjcmMyTzYrNmg3ZVdFRm1xe0tuU0EtPHpPZ30j
PlRLbXdpYyFPT0BwZXl9JGtXJGlDMCRvYm9ECnpeaztnNjFoQFAha199MmsrXkRMXnorQCE4T3Rl
QilrZmBlQjZxNXt+XnJsSmhhSmEjWE1CQmo2UjswflZSN3BmKgp6aE9XfWokeEd7P2NqZmlxNFNE
bz4yWVl7fSV2Z2RZTUk+MVUxSG9QLWo2Kj5hYSlkdEpGZjglQlR0XjM/ZUsrRFcKeilnc3orck9K
SnVKd351ZWE4blV9dnZBfEtXR3YzM3NXVjA3ZUcqWnAoITlnPGdZTEVfRlNWdzFyTS1DaXNNS0ht
Cno/QHYwdkgyQUhMMzg4JlBLUnBXSzRwcWVNOEhEJDg7JGZ6NTtnc1EmJT59TXpKflIrOGFmPmJP
XjNmRWZOfmhRVQp6X0c4ZU5YNGk8TkxjayszRTBSQitnRnlKTHJ0cCY9V2t2JFI9PmwjYVhEV3Nf
LUl7T3R2YCZ3ZSlHdmdgTDJXcE4KenpRTnhHP355PGdSYDdZcXltfGt0T3JmQXotOUp4cz5HblQk
UVNzfF5haCFCPDIofD4zQTwxNDxseFBNclN+JEowCnolOzxCT2t6bTspIVNvRWFxZV9wSnBYa0hS
YlFmY3cxQTxeS29KWnxZcTctRzFfR3ZzbW8zSHNWMlc7VEZ1XkF2fAp6RDxDZEs3bG9qVDskWEEh
PHcwbks0TytoRnZrbzF4NCgrcF5uJX1MI2RNckxGbG4rYD9GPzNjSEEkWlh1Z35SdzEKelFxTntv
KVNuc15BSXElMWAyOXhrTnAmX2U1dVA/LWdtU3A2V0dwSSNHYkl3cXtLTlhUcWQycHBjZkVEeClh
ekpnCnppOT9zX15CcHhJKEZCKCo5MTJfcyU2RE5mNGxpK05nant4fjx1YHFIJj16ckU7Tnx8fVYz
NzxCNWY+R2lNfVJ6fgp6WmFoSDxebF5sIXpNVSs2V15sdEAxez04ZXdvdGF0Y1h6UTVmfiZfOTRa
eG0zbEVRRWRLUXk5SHZ4fFJ3P24mTD4KelV5Mz17UHAoTDBtQCszKSNBY0o0YWB9fkleMVEzMGQ5
e3BhSyp+a2NCTSlvMjt+fSVARGpHJEZCcWREVz0wam9WCnp4ZDtyP3pJX3puKztBQkZ1LWI5Knhn
VX14aTxKbkVrfU9RPlo5LSZHM3JoRkpoXyNCQjdjQzNmKzF9bFUxK3R6JAp6YWdPOSUlOGt3ZTdp
QiUwXyY2PDFxKE9eNUteeDQ1dGN8RGJWc29VfExoPG8mbHUoRzUlNDJzPnM1QTQqMl8xY3QKellZ
e1V8WnMrZiFuKE1HVzxnIWxYTXlEOzUhR1hgOVZAWjV5dGgmaTw8ZCVjSGFpOXY0Q1RubmVUVFBU
big5O0JrCnpAYE9HYStfMjlPRTFURzQqTG93bEZoK2lITGFxJkNBYzJjd1ZDTGt2cGAqU3JeIUFS
PSsjYFB2QnV4aEc4dTw+agp6MDtPJmc2QTReaktZbj9pVVo3I35ZeGRrQjheb1R9ZygmaFJmcUor
UWIhLT1OWUpCSFFnVSFZPkxtVHlGJXxDXzAKeitaVTlfUjhnbyQ9MDFgLU9QPlpFaVhBU2BDVnJh
dWMzR0wjSjh+cns8PlpsPEp5P2gzKnBDJEpZYmpoX2VtMnx1Cnp5TE1fWCV1c2dpNmVuWF40Vyh5
fHRFQXxxQzA2ez0wWVIhb048TXFJcE00cUJufHomQmVNP058Q0JHUS0ySiRVIQp6VWE4fFVZXlhr
dTQ/PiRPSF93clc7VipDXl8jS2tDYjM0fmpUM1JGaERtSCFSbXlQNy1mQWtAX3E4NlU7OC1mcjQK
emxwJjtXPG9eQlFYeGhXYyNeO0Q5JFNrez9GYklXOD45RFZBVGxaZVNTLTI1WllFcG05WE9rVXg9
blZ6dzRhfncqCnpYck5mPVB0KW8wanM4cDlpJk9TJVhFOz9zJkRyZjIwTVJ1bGFFQiF3PH5ebGsz
Ym5GTkwkTjFJK3U1KnpJM2g7VQp6cUdVK3RWczs5Kz4rakppPVJhSFBDKG04OWd+dEJ5QXJNZkgx
ITt8KGJJdFR0N3V0MC0hNmkhcDltSmR6THklSkMKelA3ZEtndnJuNCNGUnI7WEFGS29kKFBFb1I2
UzdhRUI1aVMlRDhQRmJKbkpTYFNaezRsWDNxcDFKeURPeE9Xdz9hCnpGUzlAYm5WRmUhRzBsNWI0
d0YrO15rQEc1SmtBP0BoJj02UVJnVmB3OVBrNCpIbEpRX3EzaDw+Si15K2A/PD18YAp6dSQrfC1Y
YSV2JHY3PyF6a01kQDdGUGx1K157TzBJU1NUczJVYmRRSng7QipKRHlANEs5ZV9YQ15lZHBMZHRG
fkMKeik/Un1zRi1LfjElfnJEeExkfT12WDQkMTNiRWB0MFN8SVUtME94WThvIUx9bF4lfEI0YXpB
MnE7aXwxU3BBaFlICnpDeFdPanJ9cT8mLVY7a1dQNUs3N18jfWo+VCV1NlBnejBeRiltX3g9R0h6
fDsqZ1o3YjRfQT43USgrYHBVPH05OQp6UiNzTjdlPjZNcXtoWE87VnojeGw2Xj07bEk4I0JQdUpK
UFI0M0NjSG1FPk5NbFZne0pzLS1nZlhPTipMKkUqRXgKejZSKFo+JW13PEteVXkhdnQqLWFweW1Z
cnc8NGFjbjYyJjJJdG8+YT5vdDRhX24pdm8jWWN7RU1VJmUqTER2emFuCnpjKSQpVHg/REJHTip6
PTtVbW1ENSV7SGw9b31USX5tUFNOSU1rakwrMEdWOTxqTTtCQ29vKk5rKWF8czlBe1Rtcwp6LT9L
cFdUZVRZe1FyZyhGeDdkUmR8TWFzOSs1bE82MWZuOztfeiVCdFc3VElIbGpGQlNDTyRKPj48Qjsw
KX0pOFUKenUkSTc4cnxMZXh0QFlLKj42cjxXcERJVUdsKUNhMHRZcDNwNGd2UzJIczlUQSFzYjdq
eUViNkJtaTluRDhySEhPCnolSXFTKUlGZjFfU1d7UihNSF9gOEc5a2FKSC1PJDtHT012YGBTRz4/
ejZKIUg7JGRjJCRDOUhUNUpSKWZPJFZEeAp6dndqO2gzV3VJdlFaPyE5bCQ1a2RCbGNte0NFX0Ez
dmtmPTR7QzFrPzZPQ2A9YTN9dlZnfGFPNyZHd3BTR0JYezQKekpAaX5iaWtabllgRCpxM3djTmlN
aGhgNH1OSVRhLVRJVzMjV1VTRCVqdnBjOTd0b199SE5yXjFWOWcodElTXkVDCnpMfj9iYmRkXyZT
QEpVbV5jViVjeGRDWmVUZ0E8WjtJVTk3XkgrI1BPVWFkfjEtZUxTYUR6YSN0VFNjKk9YfmZWcAp6
PXkjWElnKmduZSQjcG10P089bjd3fUNQemdmM1Q0KWNtRkVPO2A/cl5GRWBFPUBeKEFkM2RvR0Ja
T1ZnM2ZPdX0Kem17VF8oN01TI200RW9CSzxAQFp7THV9QSMhaTxURFk1I3hZPjchNXNHY3ltKmg4
NDFXa0lUe0w3RFVtJDlXQnBECnpwI3VHbjIzNkQ4e1dHPmRvMTNoQzdnd3o0eS0/dmllJT5mWmUh
a2JMQVlmQUdERkF1b0khdlpNbjxnRVlLUlFibgp6bDNZRVheWS16flRISF9oNFpqRH12bW5ieC1y
IVlMRCFjYm5Pe2xjQSlKNjNydDdfVCE5UzgtSHJXKDhNa19YRGsKejc1K08mblFxZW4pZ0E8OHxC
UjUmLWFmdHxSUXMwfkkpR2ola0JKKFdVeFQqYVhQXkJGR3I5OFcmR3FIckt1fHxvCnp1R2h0OVpM
eFdKZHp5T3BncWhWYVY1JGVpTkRWYlhqOSNmfXQ1YntGV2dDUCpmbjhWJEBKYnxDVDB3NG9KQFhU
Qgp6cjt9YTV4a2Y4a3dDenZLR2VZUktPfTROMV5iTWlMUS0hODEoLTtLKGgmMl9jT3V0O08yJHtg
ZCtoO0NxSzIqP18Kekl+Y309VU1yOGAoc1hldmhSJHVmKVh4OWRYV0xxSFI3aV9COzZkY018TXJ5
OWVQVnt+JiZRcmwoZmBAbEBQWD9QCnpLaG5NeDNrP1M/RkE0PklBNnZFOTJqOzAqLXJtbnxGNVFt
b05KVmReQlNUSzBGZndSRiFWSkIxOSlFYikoS01TUgp6OWdQNHJhSWIlV3w2byk3I2gtMW52emFq
RCZVMWAxOXlJanB7a2A8THAjOUhoJiprTHI+SnYqLURGWjw4Q0AjKmMKenUyPUo0JjgqJUkrfV5C
eTA9KiY5em44bExmSUY+VUAtbz9NWXFzaTRfVTBqZ2ZzfThYLXVaVUpNY0F7U0gtNEpuCnpuQGVD
Q0Ika3hwQWojJl88PGc5cXNpXj1xYFpHPk1wMnBKQSsyR1dhTjJfNzg9Z0N7LXopS3VyTj1WYkM7
b3FKOAp6QEI/Ty1nTS10V0B2RTMoKEhhXzw4ajRBZmV+ZXY5JT9feUxOUVY8cUxKYlBfT1khTCFM
MS0wT0hsZGF3WTdrN08Kemg/an5qPl96cTRUbEZyQXV0VEVtQk5qfkJNdzRIay1GQ3g0em5SUlcz
fnRHeDhlbVk5TXBhWilkYCpwfGUyNGYqCnopXzNrVTFvc1FyZE0teF4qJlh+RGlNeD9uVDJ1TFJ0
WlBMWjxQcSY1KFNJa1dGSCZ3OG8/Qzg9ZW07T21QVy1vPwp6PDNWR2U9anU7QlVSPD1eOG5oS24o
N3k3KmhQKil9SmIzPD94dWtaQjJtPHQ2biY2bXxwWGxAYlp6Yl8xSF9rM0QKelcjeEUpK1U8Nlo0
c3NoQ0okQ2M0WEtUMzclNXp5OEZtVGwrTEgyWTs1IzZrJT56bCg0ZH1EenxSWXtubE96dzBpCnp5
UDM0KlJsQDJJOzF5anlyNTlVMEUpQSFEbiFVRnRPLVMmO05DZHhoOXh8YHxnUmFjaEh8bjRET0l0
RmdhRWpqYgp6e3BHI1ptJlV0NHREZGpkT1ByallVallmfjQzencqN1o7MWFkfWRHTkFeSWRhUTUk
endzSk99UldLNWR+UG89VkwKeiE4SlpSOGFWekpQKyNHT3ckPlYmbF47dCZAeTdDb0gqcWkmRiYh
QmpxYjJwPjVocHdkZ3RUeipDMWc8Z1hnfHxQCno7UHNGJCN1eUx0PVZQaHliQUtkX15vI2xuTj1p
IUJIfHBGV3UxTHxQc2hET2pEb25BbG9PVEtQS1B1X3MmVUk8bwp6bXItQ0BITUc2bVJwKyhRb2Ju
eHp4UH5kZEJKbWhXbGgmej8xcV4/UHh8Ml4zcF5SXks2ejZiWEllckVIbjsrNzEKem5QQG5QSHNe
U2c5fDRqIXpZQWJQe1B+dyVjU3grKF91THA0big3O3lsYXloSnt9R0tzTmNzOCNVRzR6QHE5QlZ7
CnpMMnVWPl9neXBwZXo+JVhmUUIyWUp2K3dXPWxfNzZsVjIpd0w+P0w1IzFncCs2RDRqIT0wV3FS
PGVFZ2BBJCtQZQp6YjBBSVctYSN3fjFMTjhxJjdyWkRtTTA5YjJ7SzR1TmNMPF89dFlQVTQqM3lx
Zk1pQ2tBcXBacVFYeiU/XlZPSGoKekNoJHJ8PS1YRjhyKyQjYl5LXzdmLXwyeXU+Y3tGSmFrR0Qt
TyR7OWtOaGAqeSFJLX1hcj4qNG8yX3Z9SlI5N2dtCnowSnwlY1VlY2x2UHErSWQwPUshTExxfERo
YVU4e2l1YldmeV5lY3NFQWtIVkVoXz47c1VRPVAraWBMTmZka0dmKQp6U0tKYXJ3NXlAPWJhJnBN
ZiEtI2w8NTNodTVlYio9RXw8YnY2e1JNbEkyPHE2RXYjPXFsQldLYkNtIXQhaUE1VjMKej1PNyVD
d2R6V15TamVLVkNxSVcpalNzODdrOCU+aklHJl9LZSp4YyYzbHUmVlRwKUxic1l9QW1lNnxfOGZC
a0JpCnpBYj9oNndpYFMmMWVofEQpaCRgbjBuZkpWaUBURH4lRSRqKkpzXyRtPDVkKWdXMHF6bD1B
PmYyVXM2JDBFKm8lRAp6d05eLV5XYHFtO0J+NlRqJXJgYTtHVDhga1VvRiNAQThAay1teVlAMU1S
UHpUQi1rIXFfdjM3VXJQWC1pSUdWTkYKek89ckIydSteVD9UUmRvXipYSzFtYjQtV0dhfFlueyhp
OSpvLVpNM0c3bDBnaTZKRUpOWXI2KyopTiFjV3xOcGV5CnptWldoO1BLflF3MT1vZk9gVVhOK2Rn
KjJOdzZBUXxUfmVTU1B0M0QmaFA9VUBrZGNwdUhsQl9jTypyTnQ3YXZ7OAp6TDh0eDNAMyNVX15a
OUAlWH1RdCMtYXUqNFpFXzZIT2ppI1FgbSpJSCRJckM5YkxBOEE5blcrZnJeK3ZvbWNyeTUKenVP
TT9XZD0tenkzYGlhNSlEU0VQYjlIUlZoPWshQk8tSGk8e2wzYXN5eC1tSGV1OD1vV3Y5K2Y3MV8w
Zi07QkxICnp2LV5wb0UmJjtfb2gpJWhiWGQ1Qm1oNnZUbmVYSj9oQlZifiZBKEl5ZDA4QzBvNVVI
O2tafD9wdzdrc0FgTSp+bAp6cGJYfVple345Jk9vI208Z010LXB0enxwXllqT35QN3NKcjU7KEt5
JWlpOGdHbUF6Jl9Fc1hRSyRZUnUqPWV0Xk4KelM3fSh3Jk5wZ3BVc34wfTteTVNeNGAzVkphMm5O
TSNFaz1PKjxGKyVxKjZTV2VJRjhUSmZIcVBMYEIkdGNAPCpzCnpQfEJTZkxRTnUhY0Nxa3h3Mi10
PHdSVmFYOFRKWndsTFl3NjkxT2VrLWNkc0RNNi1VPGtsKzxeUTtGMnpafihkcwp6OzBoam1kQSlt
eDBDUzVlTDJEaWtgWUA8NDk+QzQrRiQoSWBZbkk1UWd6am5+MSoxUDxSSVdOUFZmcDwwJCo1O0UK
enp0JmJpIzZ0dVFxbzJ4ZTZmWjhZe3JCdVdsODhxMl5JVk52Sn1ELSNfbyNwZ2lVbTFTdVFDc0xV
NSpnSSYybzRpCnp2aERVeSpgWWBwSFB7MUU9KXUlVlc/eXZNZT5sPmlzSF5BcnNRTFoxPnYkTndZ
RFY/SXpgJVN4e2t5d1Vrd3x2MQp6bHIzZkA4fj1NNFRxPHQjZ1UrYlcrVVFlSERQOWpqajh2X0FR
SExZbWkkTDxWXn0yOWhTKHcmUFZqe0pVQ0Y3dGsKejN2alA7QFlrMVFLXi1eUG9NMXRuQT1zUWtX
REs5UDdxb2lqazUxQkZFPHhzejlUdnYwIzNEc3BCfWA9amxXNzlJCnpiMUhGM24hUk1ee2hFeVhr
ez15Nzc+Q31Eck9XTjI7MT9HY1l4X3N9ck9vNilYb2NzMmZvb2Z2c3ZIeW93b2EmSgp6NFNvRj03
RWdzOTc/VFEqR31BcHBRMk4qdnpoMTFTKUdod09PVT1aQEclJjd7NU1DIWU+QFR9aEMjUnd7JU1u
P1cKejZrQiVoJktwJm5BOXlOekFDWVlXOGY2UzUhY21DV2tmKmxSaUh8ZyQ1MiZ4ZmtgaVQwKk8+
SDdASTUobD9JMkl2CnowblFDM3NeYWpQMHp8PWViejchcSNuQ1VvPCVoXjNxTDY0M3tqb2Q0Iyll
Tn4+THc9PjhuYio2IUNSbXpJeSF1Mgp6Xk11KTspUCRKcmVnQEpidHl0K2teOFJtMGg9Snlqbl9V
e3c3TEl6ZDMwbmZRTWNOYkx5NyQrIzt6KFUoT29XLWEKellxWUZ+OFR3cStzYVRRLSQkQUpQRU1K
VXB6KXBBT1BePnpsWXZtMDhZfmxYMGE1PWgmRVM7UzFCTDd+Klg2YURXCnpEPVReOFU5OD52SG8j
MlNuak0pZCNIUH1tZ2kmfkBzMXYwIT1vT2g0YDZqMmBUdiQ8PEFAPzMhej8jX0Q4PXVBQwp6MkRx
P3l1KXBkSmN1M0JCPmIyUz9Maihna1RxUGR7SlJ4T3dgLSZiKilQNTFLWG83dik0OzU+dUU/blBY
alA2ZiUKemRYYn1UOGo8UyNuIzlHMXJlcm1VTSVCJW84cSFfQ1c0P1NkRDlFN1RQbSpUclRvWHJF
cWlKMkUqO0RHPi1pMX5ACnpGb00/IUt8Qm4+Ym4oZ3dCcEokLVlaVzEqPkolRnxAe1N9WTE1OU1P
Vm9adC0rPnV8XjNFVHYkbzlvNVhOdTNMKwp6b2VQUGJRPm9ic2lMMlBpfEpYWWB0JGg1N2khdWEp
IVNrWUhpO14lKDZyNTJBNno1Rm5EPUt8KXQpVSRMVihNQnAKem09NWo4YH1KdkQjcEw0UlZ0ITJ+
MXZaTzIpI2t0NnhHYClWPUpZJE5XT2hYUlNGLVo5RTg/KTZ0QyFqaG9UPzAqCnohYDNjMnpMKnBF
YX1kYkFHPTZjVDxiJT1CVHhpdldvWUJ9XiVtSXZEcDZIWVVJcXhRb2N1ND8kbGl1NXg8NHo7YAp6
V1cjPEF4fnJkNk1WVUpBOW1abkVhWEF6Kk59QSFwellURm5AKDRKcU93eXpIPEJMQmUodkhOakJ0
UWhrQ0hmOWIKejUhZmpDSTFVMmFxU0UlP2d3KGV6ZE0kc2okZyN6VjxOeFVzQUFhK0wtTmt7QkB2
JTFobSlXNEFDVkFVbmlYM35ECnpVPUFlVFBFI31XY1lvPSFBN2pCcyZzaWY9MkgyIVBKYl88Jndi
UnQ8cm5EekFqbVQ7bzgzcmxSa1AwKVIpYm51agp6VFUhKHJ6dEMkOTx2UTRsZiUreEtmIUI0Qlkl
cGxWend3UXs2O2I/S0RRMHtMdkhZSEFZSzxMdT9KWm0wRCRRfmcKekBJSDNUPTtwbndiNTZ5dlQ9
SHFJeWwmdDYwRDlCKSQqQWdqcFFqIUpXXlQ3I0poPkhTUC0zKS0/KHswNSRUbk55Cno3Tm14N0cj
PGcoTUJLfXdYS1RgKUNLOCstRGJQYlFzRSYtd1d7V0VCd154QWhNcTtTajxmb0gydipSelU5cldG
awp6KmY2PVRPVkBQKiZUX21DbHthPmtoK297SURacD1YQnRLZTtELW14UHVmPWlrdGx+NlAmZmVL
cTlUNj1gM207ZUgKek5KUWFpQ2dIeGExdUN8cU0oUkVxQEx+bVRhQSQpY1lTNjdWRkU/YFN7JTBy
WXdEdFQpeC1qRj8tfV4+fl9LSX1eCnpEalI9O00rYjQ8UHZMaEg5a01Bczg1eFY/bi1YN0lwTHRT
dG8yN2c4OStFaF5LPjJQX0J1QX5veUI+fkskN0ZLfgp6MkR+RFh3S183XiQ2SVBwJklTdUNDdEFG
Jm1YViYjaXpReWNsZWcxQT5adiUxWGomYHplbCt9WkJsRGxGYD9mUUkKem4xVzVsSWAtcTQzNXVQ
Q2IoMUdNczN+NFl2ZVckd3NAflZkNHczd1hzMSNoMyh1K3FURXRiTntpYGBKbEV4Rm93CnpIOHdh
QEx4fHh8N198STA3fTRMUitRcEprWXRoO01SNVkkM3ZfTlV8WmBrQXs+fmxSbWdMZ3gwPiloKVNC
TD9qRgp6RjZDd1U1fHtYZT8wX2UhP2pzZXcqSDAtX2prdmpmO0JsPno9dTl4S14rPUlKMTc0WkJZ
NWR7cyo2czhPYStJclYKemV4alpBalRBP3g3ciN6JWJiUCs1T3BSTyViWShxJTNWU3ItKWlCYVhv
Wng1QHg7an57RytJT0sjMGhsbWlpajZwCno2bE5rUlF8RW5pU2wkV097aCgxT3VgaHdLV3hyRXZk
Xn4jQlc/YDVzez45OFFIb3lGMEM3fEFsRCUhTUNebHZBZQp6elVDV3J0ejEqMWk9fFV6YEdSZD9K
MjZxOGlXNWhXS3l1WTJeT3U/fHZebWtxcnZ5KzlmcEFLeCU5R0NkQ3h6TGUKelQ7eChETmxJO3pW
Y3pZIU1OezVOUEUoe04ySik5TklVRDBsZjRiUEtLZVlqaERafSFvRGU2T0ZzTmNBRzYoc3JHCnp0
XjlBekRRY05HUXdscyFNYnd+M2goKkNxeTI8VHk7KkZUc1dMY1BYUXU3MFVHKHFuUT4lZTNeRVlN
dGUmYX5PLQp6VVYhKH43Xy00KiRLZlZQSF94NGpfIWtKUystQE1KdSpXezZQakgkMVAqdWloUHBS
aGV1UFRGcjgtanpOVTNfazEKekFuLSF4PigtMFdLXmZzTXIzdG98KGlqXmJyJmhVKipBYGw2QUl7
IUYwcEA5MGF8K1RqI3lEWjcqc3o7WE5FLSZJCnoyKkUxbWpjN3VUYG5+WlZfP05yY2U1JlgoUl9D
QVZKV0pMYCZ2MUFiWk1sIW11Y1RGWSlRSjE+K3tDWG0oX01RKwp6NHxqPjVgeFkhX0BDUE1+fEs5
bkJmQHFQI3IhPnk7dEk5MD88RDMtWFBUTTExdGRrYC1rP0dZKzxhaDgmU245bHIKelBKfWs/eTBw
Z3hUOWRMOCojQ3oyQ2dqLT5ibVc2RDV4Qz5ibChXfkNaQ3ktMlU3UyZLQHh8ajd3dXA9SyVeazlo
Cno7dSg0NSMjZCE+a3wkdjxyN1BIYFFmaF9zOWw/Z0ZweyZ4UjUwU187WCZUKFd5dGgrWDNNeUo0
TVhTJWZ3ciEtdQp6K0FYWDE2e3RKWWlZY3FAPFEwKytvK1BQVXY9P3JYSSRVbSszdlpkOHY5Wm0z
ckRMTFJEZlcjbiRXeCNUMjRRM14KenFDIShNMkJxQUBnWlNefGFtK1hENCFJNUc/SnMwVmxDeyUh
fEh7OUdXZDVxYHc4NH0lVUFAfSpKTX40dXkhTW1QCnpjXmlqMFJyU35WazdhMF5VbGMzR2UqZ3w+
IzllWXp7ZTJWKyk3d3YzbUczJm14Y1k0Uj9efnwkR2NWUCFJelJragp6cl9UY150K1hmZHYqKzBw
Umc0UDlKNUZFclQ0ZXRiZFlZKXwjZERRKG0hKWU/VFZPUUVhRzticGArUCEpSntpMiMKej4+eXJM
c2x6dj8kMlIyMlYkOFd9T0krUnU/UFptajwtJCRYZHRTMVk0KTxwNTN3ey1AR2xsRmpYeVMjWFVu
X2JpCno0Q3k/UWJRPD1aNGpNKCYqbDZPdmxUI1M9PWY8PEB5Skt0OCp6XjYmX09nIWIrQG5qYTx8
SV5OVWk7Zz1reXkkcgp6QVZTcGpHSWN0bVNRZ1RwI1YkeVo9WDN3RkVeUlVlSG9uWn5SSHlgeEhH
aCtfVHFuRCozT2t2Y1Z3XkczOEVNYUUKenJgRGs3SFhTIzdEP2JYbGgmPz57PDtqOFFPNFA5JCpQ
Xj5Bc0hxd1UhKVBReV5CemtEM3VrOzghTnFSXzB7QFZRCnphaVlzJGI/QmVMeylmKCZYKGRZJSV5
VjZ0NHpKeiZmX2tNQEE1dW9EblR3QD87TEUtd01PXzAlPD58N2hTUztMKwp6P30qfmRmWlgoRXZm
bGY3dkhscX5DfU9UQTVCI0hUc15DY200WGBINnxGSUhVU1V6TytgPCVgblE/ZTFzeV9sJGYKeiZI
R2lEMlRzdSUoOGdWPDNUSylpeDlQVjxQbFdNOWBXZ3lQKVNlfE83fnV6JjJBJj17VTtmO2gzfmB0
WHhFMl4/CnpXViV0JSVrej17R0BvKzNrRkpEVVR7VFEwUExKd0c5JkMoVmwtXkFHazF2Q2JDTFlQ
NlBQWEF4ZWVTMU9oQDBrYgp6PjR9PkR3ZCY3N19+Y0lLIWdLR2JsX0tKR1dRa3Jgekw+RnZySU99
NjE1JjhFWGpDeWIlYnVlJk9AKVB8ZXY/RGUKeklwMndyTjBAVn5lNGNKd3szQ09AZD1lNjVlQTx1
UihRT3ZgbkwtX3h0WWNZfU1pa04wT0JrWihZS016eUdgUD56CnpufG5LKlokM1ZaRlctTGxETWho
ayZrWmxkNFJSJHZ3QlNHMmY3SSNOe3JjKnN5QXx7bD5mQyRBUWlEdyYoIXYjRwp6TiRSODBhZ3Bm
e3chZmRSPWpVLXBBKTNVeiRlTl9Gd2hUNX1fJjsjWV5meGUqcWNFJCFnNVJqLTNzSlFHbkNzOEYK
enFuI005Pz18NUh3NSVyaCVEVzUjTnJkOW1NXnJnJj5ULX1QZ21NNGpebVY+VHM+QD1iIUIxRnxJ
VSQje3BjdjBACnoxa2JpIWBjPi1EKERAbWF1NXM7ZXNmTzghdzZWSVYyZWMyVmRiSHJ5I0pIfXtB
UztmenJWTXc7OTl3OWR3cURYegp6eHwpcUNzSitla1JnfWJ9UkJiOElAS2YqPklocGFUZjchbn5m
LTlNRTxjPEhXNDI/NitSXm1hcndfYl9TVVgmd1EKemozcHlRNjdRUj5ASXc0ZGc+ZyZ+Kip8NHFo
WkZjSnBOO15IR2tCdDVOaVpBcGN6a3BBTzdrWmhpSk57S2pLPylHCno+P3Y9NEA4YWdVejdiNEJz
cE5qb0MyOXAwUy0zfHstbDxpWTVNbnBXTm0weklHVW83XkhQTyVvX2UqZzgoUHJVXgp6IWVBWXhw
LUAyNyQ1WSlOalYqcUwmXzJ0Ui0tXkEmbSZ2K0hjaz8yamtVaGYwa1l8eHpQNSFqPG8zeEoxWWxz
WSkKej8pYFV0QDY3SjlkRm1NRWRAQGghb1IqaFZzRz1yRzg0NDFCbjdjZDJHOTM7PzgqM3U2bjdW
KHpyVGtTdnRFNWs3CnorMXBGJERfN1dab2J5LT55dDJYVz1DYVVJPkQxX1FtMjtrUCV5cSlHZnYz
MEFoKXN4NlpVS0NYbCNVQHFLbFd1Ugp6aC1XM1g+bkJsVThzR1gqcjFRRW9jeWckRXdJNzZiYmpk
OyoyIT9ES2BDZiteKUNyWkxDOCFTU2RtZ01rREFLJEkKej5DQjJ2dXBJQlY0R0JCe2x+a2BKKlNO
VnMzPXVOIVJnNFVyMmd+YClzX2twckB8UEl6djFIOXVAc3hUfEZGI1MlCnomKjZKayNAdDZ5NkNg
WktoeXlMXyQyMWE9MygyeHRiakM2Y28qKCRhZHc9Tjx6O3BrYm9XTCpBXmJmZjQ8RjVYNQp6eThD
KEA2fiFGeUhlQkMpa2AwSGZYdTtnUjd5TnV8QF9WQTlVdF9+WDlac2BXKnlFS1NvcE9IWkV9Sjx6
OTZTJG8Kemh0b0huYUtBcU01P1lqbU9wRGUqeiQxRChESEk+ST4rPk9uM1M9Nk9IKntfQy0yUnpu
cFNTQkd3fVc7Kl5lR2Z+CnpBR2JaeEU8YnRMQGojUmA3bG1zKWt5YTR+IT88czg2eWw/JF9DJFN8
bkt9RDFARklIPmcjQVVjOTRgbHR2dCtoeQp6KHlAbEdXbip8fD5pM15XPmJ9JCFDNERNSWx6QU9m
ZmRNbl5HeEc3ODYmQ2dNI3p2TFhKYSkzUUZMUk59KXJMWCMKemA+QTUyc2czJnJycHxMTz1ofnY4
bFJwKGxjSkZGOGF9NUBuTHBkM1luPzxjPUB6U2hTWSVjQiFYdUYmZndJIVhgCnpMNkcyS1BvTFJ7
Kks+fnZWJjk7bnVVQzVjTztzRjFrPWpyfDB0fDlyXnpvKno/fUE7Q1BYSzQxMCp4XjVZV2ttRAp6
KystaHheST5nfXorSHNVajB4TSpaJEwwPGduaTs/QTxUJmRmSHZ5KSEkOWA9P3soVn1IPklAT0lC
b01wPW5BO2kKemd1VSVUX215O2hiTTwzNG14PDcqWSh6PFM8bjxgIVIzKUJoN15iMmFXWFM5VVM9
T2NFOFIzMkBoTEhCTzF8fEpoCnpHM1dwQWtFWjw7YG1ucEJhV3cmKHpaeW1+Xj9MSyU7ZT4zc0Z+
MHpPSitoIXRvbVNZISloeks9a0BuPXJIVDJyVQp6R2x8JXtedFRQWDItcz0+IVMqaEl6UXB0cExI
PGBJSVliPm5ydXZaQjFUVGRGNTkmPXpDeDMocXRJRnF5RkFnMUYKelczNGthc2xIfmZfQV5VbnRN
SjV5PGsrPzYkeG5gd0ojdDF9ZW1ydVhQaEBRMz4xejs+JnA7cWNud21aP15SUnFsCno8Zz01YCpR
KDloWDl8NkRzZ2E5JDY0YGVZX3sxcFJzeyl1cztBSmteY3clYTNnc3VNbShfTTF3OD1nPX10dWlz
dQp6ITdKR05TWUxsUT9XV0xZSFlFMV5Wckk0Y3d5WXlIalBrd2FrbDJmKlRhcklVbH5he0BmVkQr
TGhEO0smZUBmR0YKenoyK01ldnZ0YmtRaSU5bGMhREdDe0c8eEViWj1mQl5AITdmQTFLMmh8SEh0
MG90TzhkcGZ3MnA0Rk5QU19RVmFfCnp1PUdAZldHPzkpYDZjP0J7K1l1aWNCWUQhK3xsVWUjKUJ3
KzRiOGhQOThCaC0zYDhiRyVYZyYlLStEa3UhOF5MJgp6RTxDZ3E4JDBDeFA3YkdHUzh+fHJlI2ZI
b0c5dFRtPy1SWSMyRkZfTFBHKCM4WjtlZH18NGtjQ0xtUiFeZVA1bGUKenFfY3dITWIra1BENUJ6
YlRhPjwta3dEMjZtMSV0UU54UyVAXn1KT3A8ZDglJm1SSjFSc3J6Ri0tUy1kMDslOzJ+Cno2JEc0
MXFyamx2dD9OZ0F4WENPM2VZRSEmb290PHgpQk8kWnltdkpTbEAqUVBGWFZRQXVlSTE9UWhFaUxj
NEROdQp6K1V5ejUla01VeFJJOTFmOTV4IWRvOEYrQHFgZG8wKk5Ldm9wc2pIM3QlbHk4el8obkdY
Tno7MW5gRDdySl5zITIKenYqJShhVUhiUlRsLWJFR0c/RVJhSnp2eXooYHx3WEI8bWpaNTxFVnlT
O3Q5ejtCcEQ9T3ZTTyEkQ1pwYGpOVjBeCno2JV9GPTc4fGRMNmgjVXsxQkxHQ2cyeGtvXllRNzw/
dnxkbzVGWU9paUVYZGNKVjJhc20lc1I3ZkA0UjMwfGc+cgp6RXQkNnlscy0+e2QheyFSdGsteS1l
MjtXUFEwWGVJNF5TPV9LdW98KnYpQV5RM1lMejsyaTI9alJQZm5tPiolJSoKenxNcSkqME5lMzJT
fU1qMTE8KjRuTV9iM0dlQ2MlRTxLXkFgP1pffjx2cD59eUNqNkF8SVNST1ErPTZxV0xFJj9ECnpr
Z3IwWSpLNGE7ZX1kRUVXN3JUNThKPTxSXlZnQX5QNjhoN0dDO1Eze3F8V0hZR3lUPztzNDR3PmBi
RnJwJTt+fAp6em9xXkhUIX1Vd2hMUHtJNklvaGVpfnN7SGlldVRJY2p1ej5wMyRYUHZFOWZDeGRq
YiRQMEwhcVdPKkdYYGA4Q3wKej1SMSFFbmFGO1pYJmAhJjNtbnY0WD55KnVaPXctNGd4Xz5mOHh+
KTwtQThAZns8MSF3YX5lQz8lVkthQkg5X0B8CnpOO3J4dG1HR3ZRLTlNeyVYbi1QPVc0Xz9PY1g+
aDhwQzUrXmBga3dHNjlSN2l6T19VSGVeUVpgQE1odkF8OXBffQp6QkBKOExiVz9WOz9wQ1Q1bUZ7
YUV5PSVvS2JhZj1YeEE3bzJxe3JNPldCdW9vb1otOHteSVYraj1SM1NkTGNJSisKenheTUhuUStT
dTlwYldUOVIhTiNQQHkkdmVLaEN9dHRiTiEwdDIlczFCTU0xUnFaUmgpISZQcCptbi1eaUN7K3Jz
CnokZ3U2WXhhYztOTUV9ZTI1Xl4xQHZ5JUZoNnpNTTVTcXNxdSZ2MEY4LThaTXtoKXcmaVdfZSVB
KXM7ZX1kLUZwWQp6cDZhcU9NeHp6ZFMrSzZMY1FiQlppJW59TDNwKFpGcilSbFYjNmtrbVpjUG9Y
RDBiJW55UCY8RFRBOSMzV0ZOV24KenA2aHpXLU5ROGB6ezMhVVBuamZlSWpDe0kwcyhQVVZ3VXho
RHlqKGJ0KG9zX2ZwbDYrKCM3JUxpZW58RHBQWn5gCno3eVQleiEmNG4xR1FuR0J6KT1pKVkkUVhw
LSQ7NV5WYGJLZHdSbmdkVVVIR0d3UWJXVmpeSjsyKFd7R2I/fUJ1NAp6T1dzTyplNnRHTkNSMTRh
SX4jRkwpM3BCakshbC07X2V6bTZmfWlgNWV2VWckJlprP0RVWElrM3t9MTt1YStDWG8KelNBSUJz
RUtlVlg7SjEpe1ZENHVENilDMV9XISY8VnBJTW9zUEZPNC0pdzxGUWsoTDRObig8YDRCYmZjQkpm
MTBJCnpLJHVES3cydkpFUEs8WGVOU2NHK0xFNXdiOHF4eWpWQzVHZno3b3Z+cHFrPjE8Qmh8RVRF
WFBWWHl1Ul9JSWpoUAp6MXxDPzVTbT1JI2Njci1icyh5bm5zdiVPSlF6RH43M21rTXIhIWhwM2R4
TWFsWXxGMk11PHt7dU4qPkUhPWRnTDkKenNuTH1aYitGfGBzMlhtJHhaMUohK1RVek48fW9LcDIh
Xjt6UT5tYkBTJSQ3TmhJUHVyZlJCPXZVRypWO0RtLTdMCno0YnRJXnxHKnF+PVZSYmNUMDJxbm4p
R0dVNT9BLU0jRzloTEhPTGIxRGckXzNZJTcwdFdVTzhaNDVyfXlKVU8yegp6c18yY0k3R3wjPCh0
LVc/QTxra2xtZUcpP3Z+TTt3N3V1KFUtWGh9MyVYQEZuV1FacWw4JSYtTHglSDVQQFl4LXAKemhB
aFhhcTt+JE9xVmIrLT1BMkxPOHQ5PVQ3KllfZClHRzcmWV5IJD4+bjc8UWRPVmFWQEpJVVF1ZmZW
VF5wRz5OCno9PzVpN3FgR0EpUXJEbnNWQShTcjh4ZCRTUFdSYGh7IyVxRFQtMFJNOGduSlpPMjE+
OEBSZDJwUyQoNzF1XyM8dQp6LUpHbFlvdzBlNXViNFpiP29XWEUreDNpNEIoanpmKH5FPG4kU0N0
bWhEZU9wcXE3ZmZGJVpHSnBtQGMxUXRyQzYKekM+diopZkgwST9LQk59K3YqdSlEVXtfPGNmMTM2
I2licmlCUHRodEVtWlNOVzFhYVRpd3h7TDwjfms5d3FvbTElCno8KjxNbUFNemQyYiorUnF5YDI4
XkRkY3E8TyU3IyE2cDFScjF0RjF7NCUxLTZRRzY/MTlgd1U+P0E8STdfSCY2egp6cXtwWmJDMjc4
Z1BZWVEyPlYpRyRZOW56Pi1kZ15CPzl3fi01fTwzaHd4czhiaHg4K1h0WmU8YEBWJV8zVEhnT2wK
elM0ZD1tYVVkcXMrYkEoZnpAZndBT0lSZyR3OE85Uj5hJTtAKzNBUj1xSVZ6Q0k7fEcmdT5kaE8q
aU04aFNJRjBWCnpPUkdiaD1UVHFHXzxpc04/NT93dU01XktOSkNFRjxDaUMjUz9GQGszKUl9fTZt
XjtycyREV0NNUC1qaHFLPmVlVAp6Mlg0Kn1mbHAyJHFCfiEkZSpyLUd7dX5fM3tETCtuJi1yby1O
YEF7Rjh3WktGVDs5Xl5EODleTShaN3BZUnZodm8KekJTO20tIS0oNy1HUmJ6XkFBXjBgKmpDRUd6
dT9IejFfd2UjR1hycHZgTjdsMCNNbjNVdURuOClwYktpQShrdm1OCnpOflFafkF3PTxnM0BqJVdM
fHJRZjBpeSZPSSExT2NwYkA4QEVIST1BUD1lKl9rTWNKRis/SlBRYjN2JG8+dzAqWQp6cXoqe3Vq
Jjs0Z24oMGdIe1ZefGRsXmh7SEYpQ2ZaMXp5YXJscyMkNDcleFppWmImNUt7cTN3OTBMMkReenA3
S2YKemN3U2FNancpKWZ0c18mU0FUcWg1ZGFxRVp1ISh8I09IcjM7eUN9VFJUK3tTRmJnRn17T3dq
VjdqX0JAdWgrPGRACnoycTwyUiRnUihsblg8Mio/JkQrbmpJcjV+NHt8bztqdl9WU3pfQFJXbXcj
eDBgPFY7b0gjTkJQTUJhTkslPG4jZgp6a2trKjBXdn0jOVM3S3Fxb3BAeSowWHI1NWNeNjNaT2U1
dHNrTytGNTR7Vng7KF5VbSZQeT9nNkdXOFd6an5eUHAKelIwMTBPOHkpV1BmUjhlVGp8QHVZMS1j
VnstJj9oK2owYXsoVFJkZ00hOStnRCttUUEoJUp+SzI1d0JDbUtGTE18CnohMVZ3VnA7ZmFZZjxJ
dUlJX0RwNyZSfGBHMEUwOUkmbTY5K3tpcUxUPDgjI2Z7KHVBWDxTUDRsVns0JCpMRlI8egp6SlFS
WjhnOUxnWDBtfnJ+ZVp0eShYQ0VKR3smNio3aTNSaUQzekFeYW0xV2ptRWxtZ3xNKXRDZSFJNSQj
NUtxNFYKeik0Y2VUaWVLa21tfjs/aVRBSS1OYTlHWl9zX3xrRCVNU29RJms1cnAzZihgRipaeU9z
PTF6PkQwfSNOVWBiejkhCnpIIUFiPnJ4NFFaPH0waTVfZG43VWE9N3clREAraVNgZncwISErPzNv
KUluTC1vQkpSaTVjZEQoJW9CQm17enJ4Pgp6fEpzRTg8cEF1X0xsMGVFJGBxK1g+PWxvVCM9SCts
KC1mZEBTSy1kODNHdHxEOTU4JEMxbTVKbW5RISVOU3JhQCQKek5gdjw4YH1oYlB7IWdCbG5eSkl7
TWY9IS0tMkohV1hqYlZ9ITAyT0tDOFFAfEc2RH1uV3E0YmRQPykoZCtYRTBZCnpuSTxpfVFsP34j
WlRJNz02Q0olRSVgTF8qbnp9cCVAclB1cEZ5KjM1UUU+akJOfU4kcGNOLXUyUmt6dFFnYSlldwp6
RVNVe1p2IVRNOVo0KTNweTlXbXlNNUd0fGNwPipjMHJRZDhGNnFyQj9MVnwyUjVJQmlIdDkrWiVA
N3o2NTR2Sz0KemU7aip7OTdpJGdSayY2fCZ6RjtwY0Bfd3ZMNT1sSCZQWDxkWXU+IXAtTlYrZ2Y9
Uj41SHx3Jnk4QWh+eioqPkdCCno0NVR0S2NSe2ByeTxFU05rVlo+cFhRbGF3eXhTRHUlZT1eMkMy
KzN6V2oqWFEzdCk/V1l+KyZ8U34yM2ApIz5ZRQp6VHd1YHEyMzVmeFotSiM8SiNhQ1J6Z2xMWHxL
NUxaamozWWY5T2V3PyRvdURkPkg0NDlkZ29nTURuS0ImQEkwekMKejxeKUBoVD5udVYxe0NrWngk
YF47O1p0YCVFWFd1dkY4O31DS2VDPVlfa3M/cnw4c3tMIXZFfGorMDI1VW08ZDQyCnp3cGBsJUtT
USRwem4rXn1lbSh7ZkNIKlJ7M3hee3duRShmeXwxMFRLMUVjUUglR3BhZipGdkJ1b35IMmN3fCFR
PQp6ZlZYMkRaaVNmdVdlU2d5eGZ4T3dLISkyVE80Z3dkdHJKdGx8NlFMLVNCaEUrUj5yKythPkZn
dTB9OGhzS1ptalEKelcjQjhLdUZ0UHZlfC1iJEpgS21tMiNCSmczPDdvM14jJENQfDhBWn53TXN6
fmNBKGQkU3V5ZkU9SytHPjViQDtoCnotTmt4P01kYCh0cFR5RDdvNSN6Jk83QnM2QzgoUWxvZ0Ba
RyFgTUxwbXZ6RGMjR3F3KXskbWxWTWdzKURfVmwkZgp6UUdsNT5ITnwtbmw9bj0jbUd8KkkzOGFO
UDdKbTRETShHOFNBZzB0bUVYbystZDNQdjNhPH5qVmRiPWBqNEZUdncKekBJa0t5Sy0zUz1rI2VQ
amtTUCNgQzxiQmtPd2p3N1pEWW85VEg/M3tNRWdvOSZZT01eclQ3PndhMzkzKDd1QVNzCnpTRilf
TkRDcypKaz1sS3goTCZLR1F7Y3UhJC0rJEBSXzMtZG1qWU16KX0/VEJPXzhCcnJxWD5vVXhAd0gy
QHBnKQp6ezUwMzV7RGVJMTtsdERlMEYlI21oUn05UF5AZXpHNE1aKTY0cWR0ZV5yTkp0Jm1CbTdw
OURCYytfdmY0YWYmXkAKenBafkBBaW5OMiZII084KjJQTmlMciUkUC1CZipoWDY8Q0tBYjVuT3Q2
PDMwbE5RJTVKalcxMEw2LVpzWTskLW08CnoxVkR6cDtnRzs0UTJhWHAlfnNHZ20yVjJRZGlKbWVK
I1R5bjVOcUR7c0tfeEAxNylSMU1IK1Q5U1J9Yktld0s/Jgp6UERTO1ohI25uO2ByJEppUi1hRkJk
TUtlN0MxcCowY1VeSkg2Yj18WERGUU1WTGI4Mm1yVSN4dFUwaDx9UlZNS2YKej11WkYtWFR7d0dM
TklsNTVYcipMOFApeDhHMT1JZEYoTmVpJHsyfXI8PEV1X2F7MTAlUy1jR3NWX0JpbVFBSVJfCnpB
Pkh5aW1jUlRJQjtoKURYMzBJdEdycFN3cFVnTVdkUV80ZXNsaUFOR2lFISFgVDhYfVBOUjtPO0t4
MlFlQm9BdQp6eElxSW9HSmY4PzJWNncoRzVxVikwQk8xM15eVkpha3g9d2IhX0w8WkhDanxXMG5X
O2VWfW5nNDFAXjVKOE5sSkYKejJhKU18WEoraiR7WEc7PExfMm1sYmxkWG5xZChpZHtAe2h7LXRA
ZSNgaWduY29lUzdLUH1eOX51NVZ5SSo+emoqCnp2d0tEdEB9JDN+KHY0YXUjT0BgWClfPlU3YCUj
I1B1byE4diMhemxRM2ghZ0RpeXZ8VGx9fUw7QmQkcy13c1pGJQp6VklqP317Kj5KNlF8VXdGP2d0
PnZYamFNR2RZS04zPGZuP2plZ3t5KT08Z3Y2U3ByOVJ0ZndGITE0e2MzXk9NLSsKenRIY21VXkdD
JXtIcmYkQGdPUSNEOEMzJTh6TWROYylKdSp7TzY2cDJuRj9mbTxOYHBzYlRGMkIrTCRyMUQyYWpM
CnpeZ0dxdWh7KFolP1VMVmIxO253ZkdDP0l6bH1HPEA9UG1Mdjk8TWpFZlhNaHplSWA5MSMwUz42
MDB8KHFWTnZ0cwp6aUxBekZRQU1ePEF1WFQ9P0NgMTU/NVBWazM8UyRudEowR1Z8Ml5geVlYP2dl
UGxQRkhkQTgyWG52Vk5sbSMrcHEKemUhMDEjO00qUVhPOHM9QDlZPGFURkE8eSUzd214Q2s7OVRe
O3ZneHFEPHdtK05zT3oqQGpjSX5QPG9DZWNgJGcqCnpIbzZ2TVlLd31KaDJffjl6PCNMTk9eM0FK
RnJ+O3xoVSR3e2lLY3ExdCU9I3VWMj1yPk9HdFMzYWFldzQrQG9TcAp6dlBaUj5LV2g7SkRidmRO
WjhQIWJhYFZ4Ml5qPTxrc3AkUUZnQVhWQGwtfVdHTVhFZDBlTmF4fitxLW9hWFVCSWUKenpIIz4z
LT5jQUU1Yzg3ay1rTGxjajRYUGcmI1p+enBnR15CKlp6P0MwMGEtd2o/dEptdmhIPDVWI2tXWThn
dClKCnpnfjFJPFRHLWE5QT81SytMcmZObSNOfH1SPEVycFNqVWopTyltSXRfUVBSZHduVEtiTHVI
Tk1yeVE8cEZHTjtAQAp6KFk4U1c4SVE9eS0yKWNuKVc1ZilvVH0ofFJyYiZCYFEqcV5QSSMha1BR
Jkl7N3teS2VTbT0yRylJcEZSWXZBYisKejE9P1hMKlQ3MDdfbUF9RE5VZmtCPWw0R0omTyhXdUpr
c0hTTzgwVnZkMj5NVy0wYXBiMHdecU53ZmtYUkE9PVlmCno2e1ZqVDE1akt0dVloZDd4UkUzOCpY
QDRHRV5uUyNXbytpK147Wnc9Sz4jVjhycj43JW9zez5LTzdCQXQ5Q2Zrfgp6eX1URGVsfGxua3Rl
Z2xnMHQ7RTFVWFZTQV9FK1FrYmlDeUZ0Xm5fZSQjSlpZPUk5QHV5eTxqMTQrez9qPXJ8eU0KekdD
PSZBUGg/e2FwS3MhJVIhcDdhM2tCNkxuQGZeQkZ0ezJnNWAoeXQmYSZnTlhWJm8pdGt1eEFhfk5Z
V2tsSlBNCnorJTlwPE5VSExXTGkpczRqYWhoMm59T35IMVpXTFJ5MFh1YkFGak1SQXZiT01APkhi
TD08bWRodzgpQm5DKmo7ZAp6K1lWPFExSkhUQjhhTnpVS2JsYUooRmM2PWo/JVhTTDQyREprSElP
ZGhhYzAqeEwwbT9HVXs7di1QX3ljRm5APjcKekt4QWJuK3V3c2d5b1hVfD1EWCYzPStQRFA8VD1X
OEtmcmxxK2ozdU9aezRTJDAlVkBucGhrejhVPHF1YSFVYkFtCnpwWihsQDxCYllmTkxZV2dNRClV
QWtjLTJgeWJYKy1IJEFXR2Z6UDY3fEFyPSNafnlhJllZPlM2U2ZrX2NXblF8Mwp6TFMwWXF6TUUr
N3kqUTY0YlFvQmx4Kms9M1cqJUx1MWUhNWZWfnVHNFhrWW5Jbjl8RGZRJWAqUkN1Y3pJSS1xNl8K
enM1elRfT0JnJWZsbWE8TmpyaEVFdD0qaUNibUIldjxPNXpwTTFRZTtYRDVteF5aY0l+PSRIXlIr
blIqRmN4Pzw5CnpvZFR2YWlvdXopVSpyc3BCM2VoTztiaD1aJnFsZ1ZEUylyTEZyJlQ8KnRPWkxO
KVUjLU5wKnloYnBgVkdecj8wRQp6ZERBYCQmI2lPPisrdSVqZTJ8Y00yTzk5PnwyYEREJCkwTiV6
WTVsOEp6NmpZSGFZNzFKLUNRb19IXlhKP1VCQW4KelRtSVJvMUdAOFZRdGV1KV90OUpzRT0ySD1o
OzYhJnQ9OWZCXmlNM154I2hwNzZVZXViV0VnMXY/O21TUDZxamo/CnpIKXBOYCpjRlkmI2Vxb3VL
SDJiJXMtRWB7T1c5dEEmVXErblFUSEZrX2JHUnZ7QEpaZSVEJUJMeGw+NWhwNX1gTgp6YHc1NlAm
fTkpX0pNSml7UVZFbyQyayFvWkdAcTt1YngpdEptXmJnalBXWjhGUWErX0xoOH5lPU1AcyRoTF8t
ZHUKekAjbihWbVhaQEJ8Rl9zUG83cnN6UDs/eFp1JGY3TVUwPkV3U29naldGMyF5Jk0mZipxI1Mw
XkxAMURVQll+YUg2Cnp1MGszJlQjV3E2cyp9VEBWQXRXK297SEhXUUBPcHVFaylvYiVlU20kd2l4
N3lsP31pPG1FZjQ0IT1takAha3E3fQp6YCpPOVpxU3V4ZnBmd0JTO0BKQUJRTD1qOEdyKGlya15f
Xmc+ZGJHPWQlU3MxPEcrcXM2eFpUT2RwMXlQcCk/Sk4Kek97aSEmQHUxMVYpaWR2PGt4UjFRNih7
NkR3Wigya0B4PitJP0BYWCpUfCM8LUVtKnQ7YXhHJDUrQiM4WDEzYkRmCnpMMzhiKkY1aW5icSZR
OztfJjZNUVRGUmR7UDMhUX11JEpEM1gqX0VBNEhnYGpxVm17fGFaeDIwUGlYPGh8OVFRMQp6eWor
c3RLNiFvK2oyKF5TbEArfm9sX1dMaDJHekdnRDwmcG0kKCU5P0ohKGVpMHxkRU41Ki1jcDl8SDV4
MlV7KTcKeiFOSjs7UW94antQYys1UC1UeFpEIU0heDFkZiYhRFB9M3JYbWxkb3BGMlNwT29PcElW
UjUpKztfKjczfXh8WE9oCno+WkthbGNXK1FMSUtRNVduXk9Edkl9Myl3U0JHNWhkKUA5TmI1dGdf
PDJOUG5xNHxwQkNuU09YZUs8eyliYXVMTQp6RWl6bSFKfFVOV1VxQ3JtdzBicFIoTl8ofSs5KDVq
Q0R+SEI7UWQwWnxGbHBXdjw+bHBYUFFlfjRweiNvX0w7SFEKeloxJmRtODJ4Njsldl9BPjljRD8j
U0RTUXphaWJHbnREVGh6UXI+amIpZWB7KiFPVG91UWleeEx4a2BVMTBqez1RCno+KXYpdjFFSjIo
JEZDNCFXR3ZaT09zS2YkUT1rXk42bGQlNkckdD04c1o7dXNVNVMpQms1S09RPEp0WmNVKDNhcAp6
V3pwZG87JUpXQWZPKTZCMjwxVnNoVmkrcTRudCtWJCR+VG8qWlh9KTBgPCMmWmNrRWVUcHkrN216
VnJUfDIxJXYKemxSbFNJSThVNmttYSlSIWh0QmJ2KW81XzFYV2JkJUtQQFVOcCtLSmMtUXArS041
TSVGJGEzYVYjNDBiUXlZe1EtCno4KShlO25pNmA+NGB6TXRfNXV2fEJPX30qVEczZmclfW4/Y3FJ
Zj1aKnRVb0QtJTctRlRSWENORyNvKXt5cVIjZAp6ZVBETkQpdW0+e3ckPG1pa0RuQzRZSnxlc1Z3
OXU1P05sUHIyKyNXXihyTVklKGVFWTxIdDEhakM+dDBUeXdNdXUKeklNOTM1NXdHYyplSF9vOCY8
Jmo1QmA0JndFNVp5cjh8Q3xERXhQSU40VkNubUleVkw/Ylc3MSR5Sl8hfTdaWVdYCnpaSDlNQkp4
VlN9Iz0tUGNZdlVBfV4yOVRIbSFPYHpXP0tYdigrOTVZbThJa0xadkBRQXsqJlY+bkw2OHJ6KilM
Mgp6I0BvellgZVVJKlJHUE84bWtfSU9ENmBMTHdZcnZhTyRhdExUQ3JxMWRhe0xqQW0mNldgMlRj
JHR+WEYoVUs+QHgKenZLfGdlcDV4enMxekBWNEpGPSRJaW13MG4lQERtNnZhZ2JFTDQ5a0tRfERm
KyQxZCshSCNOVEdST3prKkthWHUzCnpwTnEkcmt5dj5UOylvVkRFbytiMEA4d3BgIUxSTSUkUjwj
MTdwejJhY3BrTFk7eEtzZ1F3K1pSYGphUiEoRFN6SAp6VT1SNFpuQkJ6Y1hMbVg5WUt9e31CfkEt
fVZLVXJ+IXRXbyVQWXVVZFkjdkRGN3UocT9wZ0hfakxUbEsrPVFYdl8KenMjJD4hWXNKYmM+JkVV
S3EhZ0ZiU1JlWT5EfDxoLSEkfmxyUmUodFpPXkxlM09eQmN5aVM0YDx8R1NSOUpzdFpSCnojVUs8
ZUx1fG1EIVZiMTxuRG9jb0pmPFNYOEt4Pz0tQW1IM15Dd0ZtSCtERDVKPzJIPGhAZCU5KlVWezJq
YEtXTgp6JGk1Q2szPWApdiRxWlF9bn5TbU5VVmJwU3hVOWZAd3x7d0BqKHFocUQySGNUPkY5JVFk
JntTM2UqTjNQa1NGV0wKenRYVlRITjBeVHY8USpZXyZWSnB9dG54WHIpaGcoRUpwK1c/YyZAPGA8
SUB4fDZKPExLNVJFankmLT5oTTh2ZXRfCnpfalY4fj5Pe0U1SVA4WSh0TkdXbCY+ZUFYa2JiOF4k
WStBeG91Kl9RdXAyXmM7IVlDZEJjUFQqZ2BiIVczPUAjagp6OGZnfXI2PDBjQDRmYnZNQUh5K1dV
IXskSXYqNT1obzxFZHJJS2RhWWg5PSlhRFcod1hCVH1SUTw4UV5LTFB8RyUKeiRzMDlUUFY2dCsr
MUg9X2wkQFJycChlVyg3aXZuaW9jTV53RSFUdE9lekFTYXRPOWwqeFU2SXo4elFxWEhoekJICnoy
ZTRrfiZEKFp0dSVVcX5YMD12bEVQLTcoR01ne3pQKzZpZzU5eFMwTENvMXBSY2hIdVRYR2xWNGFR
U0QqNGd2Pwp6eEBhdSUqVzN1VHFrSTxOQVFAOD4jUGlIRHVrKkZGZXBkbSNqVWl2ckhaJEk0Ji1P
fUshR3JNXnNSLVVRVWVDZlUKendWYnV0Q3dDeWFXT0d6YXJKQ0JkcHMqcWF5USY/WE12JlFENlVt
SWJZJC10WSRDYjclYFVlbCk0OElIMUBPWjJVCnpNSXhfPj4kYV9DU2h6V0JlUSF5LVdPdW4jKHo0
bndZeWdQZUZwKDhHfDR9Q09YKHxnfFYpS2ZeYEsxU3w+QUJsRQp6b0p9YHombDtlN1gjbnJqOyN3
eD9hTl8oLXBBaypgUzIyTX1OYnt4TU9DV1hXPFRBM1VYLVVwOEVgYkRnMGBqQzsKelcqJWo9MWJj
WUwhOSgtS0tmJWRkcHdSaUN1WFA7YUFZMSZjKSNNeDtkPGh0bFdGeV5EJTxnbW9wT15ye2BOKE8m
CnokRytVYERybHZ9KiZqZDAmJU90X1c7dXZuTl94WXJDdVpKKVRDZyRwKjV0MCg1alR0VEszU2o0
Z3lIX1MmYS0yTwp6R091c2trTWY+Qmc+cGpIXnI/PGQ8QnhYazdzK2cySWxDNmBqVj00UGFvZ2Yt
RllINWFVQ15VJlRNIUpjX1dJTn0Kenl8Z2hsPEhvTjcjanV+PDhQTFJBczI2P05MQCFfJUJIclNV
SEV2QE96U0RDQ2lOSmVJRzRaZUxuUlgtR2grUkdQCnpPLV9YKGA2cEBhaU9+aHtTcCstJT0xKUdl
emh2KmNJUUEoY0NDdlBPX0YleV5qRHtibkhSaChoc3k2O01hejVTYgp6NiRjM21CeFZNZkB1KCU/
byZNIVhGaVlzWUJyKEgwY3ZKMG1QQHZ4QmJQezJxYmVnYzBaUEZaRGZDU25FZT5WUGIKemUkIVN2
RDI5NnlBTUVsSVZnRjE7SXJEXzRHbjBrcigoS1FrTjZhPGxedjJZWk5uezt2d2BCKVpiOXsxVl4q
KXQrCnojcWxoK2t4WHIoUVB7bG57cXg9M2x+UC0jRVlmTz1LbTxZRmUrTiZONCRTSDZtTC1GUk1S
QlQ8WUJfKiskWiN1dAp6dm9SS3dZXnNBTDk2R2xAeWNELVItQkhXYztESUVFfEZyZSFZcT5eLUhf
fXh6JHRxTnc7THxXX3p3cFU3U3R6MlMKek8jcnxlfDU5Tk1IU3RBIUd+djZxSz5PITd7SElfME9u
fTE5Pi1ZeUZPR29aXjV7P31CNzZzZmtQKDhQNjY1Kz5SCnooanY9dkpvNXN0aGUlTiZYUWxhSntD
di1WXjkha28xYjFYK1FecVUtTD03JExHJCp3aklJKypXWn5IIyltJFV4bgp6Ym1EaiFBaXVObSM8
cnlNWFBWN1p0dU8yZXxEMnl2NmJURjdrLTEtRi0tNyRmO14pdTdMUXlucE9TQ1AhRFdRK2oKejYx
eF9eQC0oaVo+ZklyKV5PNkFLKEt9fnU3RTdNdnN2cGRPMzZAd2JLZXVNflJxaDBSaUA8S3FNci1Y
VikoTzRUCnpQXj10YHhBPEgyI3tMNWdnWDRUalh3ckBqKiZKYCN5d0xqdykrVztnaVlOUXRNYSto
cU0jMVMhPGVrMmlqWDhrVQp6MXpCYUM+KDh8YkJjP3lDM2VSTzJhQzxlYyRaVUdPZEc+Kj1aYzh5
OG9sNGQ5cz99c3x4dVBsQUBXVDw8cHdrKGcKeiR8ODhXK2khSzhXVyY8JGxNcWdqZHF2NFVXU2BY
KEt3SjZFJCVNbDUmcWg+UjN6bkBeSlJHJGBTaCN+QT87RjskCnpPUjNXckUyU19hJUtlMlpSfCVT
fUlxaj9jWTdKI2pMRnhSWWB4TjxhQXZ9RDJONCszSzlOWHhVWnZEQWFiVkpFRAp6KXh4KVBFfTk8
Qjh0RV97U1ZwNUI1KmFGWnBUKGs3XnxLfGNFSVRgMit4QylFdEY8IU0rd3R5O0opSyorLWRDcmkK
ejl4PzdOZTNXXjtJQypMKCp8czFVeWB1Ml54TFQ8S24xdVdKczJINlB1Sl9WPU1TU1ZuOTM1U0U8
e3hoP0pTXmZ6CnphTyFRM2ZCIzMxY35NRTAtZCt1NUdvU3dwUktoJWtXK31WdkdhcF8zd1d4MCUt
Qi1VKSFRdmZ8bn0qJDRFeHlJRAp6YClKSElXN1dQQHQoP1BAKm42P2NvUjVseTdLc2V5RmkpJCt5
WiFtNT0ydHpIO2ZUKyZRREUhYWN4Kj9iaE1ON2AKemQ5Nj9lNSs1OD93M000X1gxPj9uY3prRCpU
ZmxQfGoqSkpNQ2t9JWJKVEFVOUAqd1ZLZWRsNzg0eGNIaHJAMEx4Cno8SW5mXkIlJXowWiE4WXhn
K0NJMVpFY2E8JEBUO3I/a0l8JVZLTmtZd0pyKyg5cnY+WGMmfWgqN1RVaGFDUXk9Mgp6UkI5PVoy
MEVQe2BwbUpDXzB9fX4jZilMMkRCU0hBYj4tYUNhYkhvfkA1ZU9wSkRyM3IhYUpoZ2lxcnEkYFFD
a1cKenQ4YXlVKnNfNmN0TD18M24oUEsmRkZBLWA7X2RLJmF7c09lI3cpQXw0fnhfQiRnVV5ya0BU
VXJwUUxNdjhfJTxhCno1PkghezM5X3slMXElO3djOUhHUzRtQXlIU2hGfn5FJEdCaEE5Vmg8NH0/
VVYhUWxAdkh3OUI3RkdSMT9nJnI/Wgp6ZmE0M1hZdDRUcUJNb3NmWWJ2fntJQDRLSUMoZSg4OHA/
VFBJJV90TUdYZXlwbXlyZik3ZT1mSE9ZT0dvY15TOE4KenFHQ2ZMIVEtbkhSRjdVNVokND5EX3Qk
S0BEK3UtRjkxYSFfO31YKnwxKGc0T2lhJUlOOD5OKmpESkM7SmpGMCRrCnomT2Y9THUhSDZGeF52
XmNATUV7PFVOfV5CKEZjUSZlQnxMJXJ7UlJKRDk+O0VkSSo/ZT13TEtxMGwjTHMtcVZhOAp6NyZ6
cnw/RE5CNUtWZ2wzbWR3WE9eOzUjVmxMd0ZmdWFvb2VydXpSTWAxeyg1WW1iYjMlXzFAaSomYHle
cFh8c2UKekJWPVN9VF9adzlCci0hcVgyXzA5SHJadEY4Nz8xV1UrKFg5YCtXYWAtI1BjKGJJLVoy
e2R+VGp1amd3I0E3R1UhCnp8RVNjXykyI2lTVll9VjhrMT42WGc+dEVoXkk+JTUkPERkWSluPTQo
a3IxMTtyeEdka0Q3e2w4WCZFUERZcjdBVwp6dyVBOzU7bj45VSVLb1A1cGl7WTNgajw7fFQ1I2pM
PGxHbWQ3MUxNLV5OI0tzcz92ITFIfWZJI2B0Nl8oTVEhNGcKeks/aihvIWVBbCkyXm1EaGwkPiVr
Z1puPTZMTmNgOW5Tb05XYkU4JHNAUnxuJVBXMWVeIXF8N0lDenJgZz4xZWh6CnpSakJ5fmJOZVFV
MndBaXdLbWZufSthaTNHSlFFejNlaGRWSnJ5aEoyMDAtQmU1UiNYYE18fFhee0VhdWckKlRIcQp6
TDUqREIxb1dgcTleWXRCLUt1R2xXNFhMbCQ/UFFYWCNsRz5FMzYpZCtQekJKcDJvKVF5d0M2VT9K
QyMhQ3pYTlIKeikmY0hvYDB3SVlQTnJrSlZtPDFHSD0zQGpLVjdOKGk8MVJHckZ6ZHFENW84Uj5n
T25AQ0FPbFIjQnRBX0duYTxSCnozfShDMVVOd018S21+a0xiWEw9JldyKU5aXnskTi0jT187fUdg
JkdKaX1ufE9iNXpLQnVicnZzZ2V5V19WYW9HdAp6aDdhfSoxSTJeRThXTCFycytkR0dMPzVQNFle
OX1Tb0pqS3pMI3FjdldVJEw/aGY1eW95NGw8JXllKis3Xml+N0oKeldGYUNWWSpmc3xGeHpHKkxN
Y1FtLWpYaEg0SEg2Q3VYSEQtblhMTVdZTFg/a1JYMV94dU8rV15XJUJBeXBJMXdZCnpmVDZBcjBT
fjB3eVFvZCtvZFlvOWpIRUc9KH5oRnp4TzNVZU1sXnxaKFAwQyluI3JCQ1JIPHkxVCZ4VXV1NiVM
cQp6UEtvdnxwc1kxYyNsZlkqI19wS2c4YE5tdEc1e31kMyt4PnEhPX1zcTc9VV85Uih2S2BvODA3
cEpGKVVydWowenEKek8yMnt3PnY0TGpNVHxZdzxaKXljcHVDVmxScWV7aEFlYVQpVFNKKHFGVFZK
M0x2PFlOOzNhVjIpZHtmYnNtMlBrCnpGXjQldUZgPSYjeygoYyVzdXV+Z05yXiZJdjE8TlB5RVNP
YUpwSjI/dHB5fUx5dG1TRGpmbTNER18qeGg4UH42Zgp6NitOVzJTd21kNjhGO3deP2hNYlVodj4w
V2I1Un1HWERMPzImRXk2TERVU1AxQjQwSUYodF9NMWYqN1EkdTVzWl8KemIqPjhhPGlBMW1UcjhY
YDVDPlZ2cktiMiQoXnBaa2FRNEVTekBuKHIxK2YlWU8jfTg9X21OenNhI1N6Y0NsIyN8Cnp2KCVE
O003RXg8OGApNEJxejJFWEMrSEtSO09wZmFXRiMzfnNuPWd5WHc5biF2MWFhN1Rjdih0UTUkeUA/
Y1dZcAp6N0s2YDNeeF9tVjEhUV5eS0pwdGdVQUJCUzltb0ZzTiRYPTgxNm4wJjJ1OTlQWCVRKyRm
YTE2dVZoT3lZYD0xRSQKemlPZEMyM2EzQHAzMD1XMG1gN35STTt9Ylp3c1hJZm8hQXdnc0NoRTVG
MmFncE5XVihhZ21qfm9SajckejFZeSZwCnprUDxjQmtGVEdrQkNvJnl5ZzUheVd2d2p4TzZ8O1It
Y29+ZGIkbld+YnRCQnQobmR4Q1hPKXlVaTEhaUc9Izs9Rgp6PUJ0NzJAVV9WXzRsP1NuPz9nfjF4
Y3g9dXQrTjMwdUBHdkhnZypTVFpgTz5haTxtRz11YFVTX2F+MHV8ITA3fUUKekYtU2A8R3QxdjZg
cFFZOFFxUUpeRFBfQG5zWklpUWM2dmg4b1VUTnViO3pTZl5nRDw1ezdYd3ghNE1kIU51Zy0zCnpT
KlpIemJ1cmRyV3p5TyZlXnlJM3FAfnw3ZHYjaGxYQCE7WChrJHY3enhwUz5SMH5Td2kjKlRhM3B8
eUp3NztpbQp6UktfKEYhU0g1ejlpPmgkK0hUKiU8MVQqbkokdVRObDh9U1BtI0h2JStQdzxkal5v
OERXIXlDRmFILWRyTlYyMmgKell1elpvWWBJNkdmTz96WS1WSk5BNmdpQ0sweWw5dC13Y1IzTU1a
cSZNLWFyem1ScDFsaFM9cyhmfEpuS0h6eDwyCnp6V3VvNk0zZUs2KH1nXjVGcX02USZLbWBuM1d4
S0NCZ0VrYHB7RlYpKyQ8ezBEcVY0R3E+I2JRZHgzaChIekFiPwp6VUBEIVpxR3Q5d0x4K3V0MzAx
RVkrbCFia2heRVhae2RDb15eYFVJSGlzLS1MdmA+fFAkPXtTc1VMMk57cHFUWWUKekZffSMqazlP
JnJVeWR2X0YtXmpnRXlET0FWWTY7LUN9QmBVZ3JKRT89ZEdpamN7NW8xKCYoRHdXXkN6SWQ/Oylz
CnpET0R2XiRpNExMQlNNVmNmezdsblNRJHpDSXRRWHQwcTtlbD9JOXU8RWx+OylJSk9FYXhmMlo2
OGwhbiYwM0xTTwp6JDl1OXtYe285X3AhdDs7Sz5gMUFveSZDM0FBTFBuTT8tUC1ASV85QE89Z3ZR
cz47YWM0ZGhNc1Z5QmNPO0lmVigKendhQnE2K1k+U0xFPFl6U2hiKGIkU3ErQFdlZCR8JFB8V0JF
Y0tSVHkmYHBHeTA+RV98SV43XiQqfiR8MGd4MUdvCnpBb2BEaVAoNDkrWjJsU1hobVUmIXtHX1Bl
ckgqUUtTfV5EVTc3QCZJTUZlMXpCdFVGaHIoTEc2WkpKVm9CdzspVgp6YjAlWnZRSX1hdWNsWUEl
ZkdLOClJfnAxJUBiblBeR1NxYnVeI2wmfV83ZVVGcEg8IzBCfCRKbihmalImeGxmNz0KejdgQiky
KGNYTHNOK0lldXQ2PWREJlN5UC17WWtvRXlVRDBjIX49Mik8Xz9sWXd8eXJFRlI/eDllMTdQeWo5
WkdtCnp1Yn5IbHU2blI1VDM3V0EjKzt6fGRrMjJRMDIlY2ZHNCp9KyQ7fCt1WTlRaig/ekprbllQ
RmIpVnh8TylNX1gjOwp6WkpnJVMkMUhQclh1KldfJWAwdzBVIz5rPCR5OXwjP25Xfm5GdnFrenxK
UElzXiNuXz9SQjZUPXJYISpCTWxobkcKeiVNY1gqSFJYbiopRmx2YXNuMn0xZzR7T1JoSkVQeDU3
a0Vgdl5YaipGM0BZTWt2Z1hoJTYlYEFfUzAxPXFYKlZICnpiYUxUQXNPVTV1Q014akwqOFA5fmZe
a2xmdzhDRDNjMEMjdUZmXnpoO2FhUzYjWUVBaWtvWispZTI9Ni1XTWh8OAp6MHtWRVI9TkNzbU9m
andBd1BlbShxSThXOUZSSC16QWVLX18tUlM7V3t9JDxvUHk1V2owVXFwP09oTGl5Vj8ySlYKelRl
eEU0d1MoWDJySHs0ZSRXQjI+cjZVJTN7KDAxKWNiKmVTam5CWmFrYiY7PT5tV2khdjYrcmVLRkd7
LSlJajRXCnpxcWA+a0UjSlFaemA3dmIoXl8xdUBmX25LdFFAUWdlVmVHVEpETXU0SXVjfWJDYyYz
YThhK3lvKjFOa3NeNXBeSAp6SkArJChjb1BVaDx4ZWc3Jk54KXM5RSpWZGR2RnZuM1ZjV0NzSjdx
flM3OTlHfEs8fnlKfWZxKSNAQ05Aa2BSY00KelN4cCZ4VitCIXIkU3NBUVJ7Zk5BSV8jMTB1RntV
YDdAbE4hMTUmfEpaUHZ9fWdFdXlmek40fTlRMU4/TkxrWmlSCnptb3RkfDNKS1FSZ2tYJFQ1JiY+
JT9CTipfJUdOeyoyKkJvIz4wJCNXbyRkYVAwQmArRkk5O3NGd2g2UVZ7JHgjcQp6cGJze09SXz4z
Y0NubHdOODghVWtoKE0oQ0J2b2A8aC1qYF9zbWFCS1VtbmM5PWcpMz1DMUtGYCghb1VweEpyQlYK
ej5Vb1FFYjw0d3RYLVBVYmh7SSt7Mj9+PzFTbDxkI0BXRitTe1cmPEhGa3Z3TyFAPFF2YitQbnlZ
VUViR3syQmlmCnplJn5ySzlSIUs+cnJwQnIkZTROfjd+blJhQnRSK3hPWWQ8fXViKE1LP31ZcjBx
OUhINENERHI3YTJIbz50Nk5hJQp6YkE2aiNQTjF2Iy1GaCN7PXtqJm9sd31wLVJ2TGBNe3xyLSZ3
eVpHbWkmMV5kaDxwYzlKaWlqN0l7dklHR3dYY0kKelBNQXt6NDZxaj1PMlg7fjVxYik5UXIpdTl4
ITN9Tmp9MyQoVDQyPnZgPSMmUnkkZ0t1XiQ8NSg5PjkjQW0mJWVsCno1Kns1anhELWM/a0VneihO
M1VtWXt3ZHZXKTtFcVQ4ZWh+azd+RFk/YHxuRkMleXtHWllmRipCTl89NSZII1F0egp6VSU5cFZn
P0ZkJVRwWXFvXy1+b3tZd2xSb3tNJEo8SXg/YjI5bVhhcjNsI0gmanREazdJeDZZazlISWJRPz59
OHkKenYoR3dUb3YydW9vQmRWaXR9ViZkKXdUcXBvMEcpclRWZS0kYkNiVlVUbUw1UntMdmxjKkUx
U14rQkVWZDVtOFc1CnoobHl3RVBnST97IUo/Xyl2JDY5Z1IwcFRIdHFPJTEzcmR7NkIzNl4xYHQ/
ZyVqPCN6KHo3NDF2THp7RFR3eSp3dgp6WUlYOD0mK3M8dXJeTjlHd2kkJnEoMlJCMkFGVlhgbTFP
TmEwV30+WkZsOTN4OU1WKFYpfC0hdjFzTjVkZ1U5eU0KekYrZyNsNTU5KipRYWFVQG1GKFRNXz14
RE5LMllNUFBjfCFpM19BZk5VQyhlKlBlKkV9TylOO352KW5xSChNNGF9CnpSe3ducClUMjlNYDFn
O1dDSns1Mm84czhTZ0UqP1dwezlBaHJZK3lOJUY0PlYxKkgmPj1DRlVrXitScCMlRkskdQp6eUck
eGVyc3ZHaV45SGpsXz1sYjJyOHIjSylYR3FlRz5HWFFZeT8oMHgjdFZKYCZPOShAandJe0k4OHB7
aEMqNEcKemdlM1BhKmsheWoqTilFaWNsfC1AYy12TjxUbTQpWSNyWmdQdjVzLXw2a2NGNzhzIXM/
MCstUyhhUE5sPT1vYTQpCnowOExXOCRyNitBVyo4d3t6Yz1JdUpLb3ooS2UrQCZNaGlGa18kZXpk
eG55WURXbzlNLWJyUCNGNk1GNjcoMTt0LQp6NVN9NjYkT0olKUhDNWpeO3E4LT85Uk42KmEqfVhG
V2EwSkJYOTZQdSppUkMyJERrZTw3IX1fKXttPSkqaX1oXncKeiVTP2pEbkhAYG1Raz1sfVUoZXUr
YTs9fTRlNTF6WkhYS0d5Q2tATlR2cHV2MypoPF9NWHctMWxZa2U3Nk08O3ZiCno/P1hZVWU3PkBY
KjlmXilWVjgjVU5wSUx6LTxtdHE7JHhxRml+QEYtVGAwTXQjayExc3t4fDUpckdEJE9yciQtcwp6
PnJVUlcyRWprYiU9S0htZjtmPFZkdTg/VE93c2NRTD4lY2ZKK1JBM3M/PGIydklyMFpfY34xKnBr
RmVlPD9teTwKekNAbzB3YE9CdXkrXzkxeXZzSiZVX1drXylGNiQ4amx+d1gtY3FEZkZIViVYRm9+
PVEyVyNqTnpsPnFFN208TzAmCnotbmFwYipSelZMWFQ7WSpXQkpmcVVhViQ5WXE5bXR4WmZENFA4
WVJHTUsxKDIkYlVwe2VAYXtXV1pDaWlxZiMjUQp6ZV8kRyV6KUglNkhiYlJqZz18MmlWP3dnZFIh
WlIpcXpuI3BPfEEjbTVKN3ZDUSZsZUxsOE9xdHlTZjAhcVc2bkQKejFhKjQpTFglbkhxSi0odWkp
e3B5QHY8bjcqPj9UX3lJRj4tcFRsXmUrWU53Ul5VYjZ7a28kQj1ITnlBTCFXXntECno/OytQRjB2
TTYyYDFOLX5ZWXg1Zzw/d0pPd2BKajhfOW5nJkVXaS05eDNeYjQ0MDckNlNqK0k5ZUYyci04UGxp
Vwp6aDlHSyV7aHpuMEd1JjM2U3slTEQlKDxIUVcjOW5WUmh5VENfRi1jV1NydHkrQ057ZHdgbVF9
d3E3ZSlGO0crdFcKemowJX40VGZnalJTWCFVZyg3Pk1oblZ9OD1wYjZoMWI2Jk4jdDdAam5wTkMo
fF40fCo1TGxGbFo8ezUodzJlT0NiCnprOHh3OzFJSDB7YjwkKVp4Xz09YEx0SkQ4OHlnen48MEpw
cDwxPmA8Zzx2alA3Iz4wY0ZifjwyS1Q4VWBGWGEwRAp6OFVXJTZhQnRvKyMmdnw2bUw4I1g8V0V8
NC1sWHFaPXFxb3hGK3p9e3Iqc0J9Tzc/aXVRNUpEQGZCT29Ne2lwV2QKejl6VHxMaXxVUyZrSWRG
UXFgZTdzRlBSVXxNdX4jZClfdih4I2tYZyQ9Sz5DbjRLaSM3djQyYlZQLUhXSmAhcjwhCnorQSN+
N0Y9Ny1ue3p8QnJHYSEhOUQ4c0wpZn5NYz5fdClmdWM5UzxaSHxsSDVNMVZVYTZWVmJ8SCtoPFFT
OzRSUQp6Nk8qfmVwZWkoWVhZODlvOHlmXzF4R3UlYW95PD8pVHtIV34kWXs+NExYP09hSTlCQm9Q
V2k+Zm5gY2BtWW1jeiEKejU3QjQ+I2prJntQRShZd0wxd3BTZVVAbllXZT5KOyopIVAxMmtpJCp1
SHktc1YzOXRjSmppfmFCWF9jQmZuOCpCCnpBeV5taSg4fkkoNH18VCpEQk81akdpS3A7dW4tJW8m
OGlIMTB0VWp1KFd2bjcoQHdYSkVaNDV7cXEhcCVSRHh1Qwp6SyQhfnhiSURPS1kyZCtSUzY7ZUBw
MGFYaVJ2SUNnY21uYDQydnxwPDljK0huJD1oZ0w8Q3E+LUZPc2pBMkJveVUKelMmOXheMipSRUhY
ZlpkPkRBRENKITszQVMwQi08Qk42JnlEbU5qLTdqPCM+Pi1UN2FSI3c7OW0lPmAoZUZWbkJGCnor
YUNJRU9pRG9hRGhqVFgwKipwRygrJW1oZUwoQipSdTktaT5JMShzKU0yfTNzbClgLUZuMk13d2pY
bk47e1RXUAp6YlI5TVBKOFchbz1BPSNkKGV0aUBGXmUtIUNAOTxVejhYSSUxbXk+QW0zM1U1Xl90
UU5uaT9MeWx+LU5PI0N3NW4KeipGRXdPRDZXR3J1NERmS1didGxtM2NSQDZQJmp2dXt7UyNrZTtz
VSYtM35oR05qfWYxdVJrbD0tZ2VGfUZrTWR0CnoqPEomQDBaPlhIezU3UWl6aGglUi1gfm4oUTJh
UkhYX0xiUyN5QUJWNyZMNVJtKk1CR3JnbW15WmYraUxRIyY5SQp6WDZoQmRwIzxXKmBgfCYjUE54
NH1XRVEqI1dBVjE8Pn5vRzgkYVc5ZlY3ZylJKFJfTjQ9RGhSIWNYQGFWRk1BKVQKenRxR1dwQDNX
Sn4lVXl9aTBlZjg/TmE2dzUyZl5fNzhnOWE8YjNKR2EtI0xXVFRLY1UlN2JtQzUtKEt+Y1dPdVNS
CnohUihedENMPUh0VnEjJVVeVTRaNTwhNiNUU3paYnZfe3dUQ2dibShmZmlhaHlNcWJOZyN3Qks5
fDBLJj4+PHI0dQp6JCl6KWF4aj9GdHp5bk5NJX1uTjQ7QmlZRCtIPnsyb2lpYWRwTklLYFZGP1dT
NTE8RmMjKU9galo5TG5Vb2tjYE8KemxZb1dqKzc7JEtCaD9zKE1uSCU9SjtPPDZedWg1S0JrM31M
P208bVpsaSFUejgyaU91UHdES2AqY3goZXxLITZ7CnopNHZWbjspPnp8NEspKzgrWXwqI2d+OThm
MWpfbUNVXzVUTlRNbldxY3ZOUDZjVVhNUHxFeFlFZ0JgSElGbjB3Rgp6LXYhNDRSPyg5KDxNfn5t
YEdYZm9eayN8MEd+UyMoKWNiTEVndmBIQjRuZFlneTU1NiNuS0VpJGpNZ0MhaippQ00KeiNaYlR2
MHQ7cnxGbk15JXNNfFFfRW9hfjUobHsocm0oRHBhSShqWlJ8MDU3UjBrbyNrLSNDSjhrI1Zqc3NX
MDQyCnpuNE50ak8xclFmMHYzckA9anZ3NjtYMHlwWkFTc1NwdENKYHZpeGBvYGFfdFheNGEoKSVy
YyVGV3cqT24ka2NlZwp6YGNNSD5zcV5RPVV6aCZWZkczYlk5UWE+ZyVeVnJnY2dkMSpuYmt0JCZS
cn5zMk05a2I4cGFpbEtxQzFzJlFBe3gKempMYmJURTB9dWs4ezM9dlEtczBMP2FTME9OcUJlYiEy
YG0paW1NfUg0a0x1PGxVX259bVdiNklyZiUxeE1uWiQlCnpGekRWa3wyJHE1T3QpKi1qRXA/Skpw
JXlJQClsOE9fSjQ+O1U0cz1jTVRWd0BqdUleX3s4dXVQJjdPQXxMSUhlQgp6UzF3M0gwTXdFVz5h
UndoVmBAdHFfYT1MckUkeTl5JmAye0dGamBfMDcleENhKEtqK2BAY1IrakYmOCp5P3A7aFkKemFH
QiVMYGVZUTB1JkhBTFIpZ00rRFREYGtjT35vKTVkYH1OcUxKeCpfZismKnchQ0I8OTJ8NUY0OStp
X2h4Nm8pCnpKMXZtREBHYyFKUl4+Slk7Q0dUa1kqNHp6TmpGMUJreStWWnhHdFkkRSpnenxiQl9w
bm8xNSNwUHpYbThhSGlfJgp6TlczREphPSQjZGM3RDFMZmVmNGt0e0lGaEpIKyt+JHd6fEh4ZUI/
cVQ4a2JyU2t4fGxeeFBiP0t2Mjl+MV5vI04KejtuWmcyMGVlUDBgVVRmPDtIWldJSXRNU1FQU3lw
bTh5RDVXQ2N1a0poKDdyYkJwUTUkalY4WiNBKUZRTmNZYVhhCnpJNWFtR1dYTTRzZTx6I3pOJHVo
eDAtIVNhenk+bStCXlVyY2lWRiVoRCFGNCphODBGdzJaYzhHd3RNPEB1JXN3Sgp6UnlCbDFmdVkp
Mj9tK2wkU1pEUW5LTjRmdjRab3VsY0VgI1khTkp1e3FlS21lcXlUKmFLNk53Qk1gKHEhMzNwX30K
ej18KjhTTjM5STlkTiZVZzU/fjclMERDYkM0RXIhbXA7NzZEelgtRmU2Zj8jQkh9fUZpU1VAU1go
UU8zdkd3fU1FCnprX3BUcVp7cFAkK3wtUXMrX3s7Q2hLNTJ5M3BSWjtpLVpMQWxOXjl8M2xSU1FI
dCl2QzlVan0mKXhHRnspc3sxeQp6SklNRUFLX3E5O0tIQ3V0NExAVHZGfkZYOSl3M0hHS0dTK3V5
Zig0bHVkb3d8QDBMdXcpMlM3ZHt3ZkpaZzQoKnQKelM8OU5lMWJXN1BoVFJ2PTlHUkgjZUlkI0FV
UVk1bGImUlQlWn5RQkpWWCowUXNEejZMN0xKeThWR2Q+ZXJya09lCnoweWN+MT0xQDtzc0ItVlhN
LXIoaHB4VmMoSHp+JDx6VkMwN20hZEI9JTRUTH1JPks1OFBzKXIoU1lsTFo7eVM9Ygp6JF80Y3d1
USNuMSYofTNBeyVaUDZGUmt+fmBDME1OIVEpdHxaR2ZTfV9BemNmSiFNPCQyYVVzdWE3eV9PUX5e
QmQKemhUcnpkM2JyP2BudkxQb09XVGc2dk1ha2pXPklhe2ZYVzJlUE9eTXBRQHs+Mzxxfk9ESHtT
eiMybCZCSUY7UU11CnomfFQpZypjJDJiJFBZOHgxRDlIa2hmc2pDZTV8Z3AjdGlOMDVMcWhTcSY3
QXpGKjctQHBGM1pPKkdpTTxgQEtXOwp6R3ElbG8qdjZ6cGhsZHVGOWx0e0sjM1ZSfWtBZyUre3x+
PzxeUWVva0BHezMtUDB7UjE5SkpzMVctUkVLKFlMe24KemN2Wl9KdSNMZ09MPUdVN0FRVz1+cjI+
aWJhSzhXdj5JZERNWCowXyEjfHwmUj9FTWFRZzRtSSZzJGN3b1dZPCtACnp7M0ooRTs2X3g9MiE5
azhNTDVnPTBIVXZwWEAhMFVMMyFmcWJAQ25yTztWJlBaKlNfKyErMFYjTk9nYzkwQ1Jedgp6YXFh
RlA2eHU4QEBgcVBfaCp5MD5qT0NMPWJYKFFMQDFqYHwybVNyX2lobFhXPU0jMldHdHRYPXI7LVcx
QF5BQGsKejJ6VWpsT35QfVZIM2VjT1pNQEdhO3E+KWxLUHhWN14xSlQ/Y080eCZjT0tlPD8oIXs3
OXtTe2g+KUxucSVuSiU/CnpBZXorQWhRRm0lbG09b19LVGxtY2IkRkcoezM/ZmYme0soIyRVZXVP
akRVckw8Y20lTU1GMl9ZXjZtRUA8I1B3dQp6dDAjKSY5PVFaZXdNSGdSXzlAX3wlXiFUJGoza0pV
JGU8PDZpO359YUJucH53ZzgrSXUtWC1FbmR2cUVWeWclT0kKeiVhdWN6anEhWWhKVEJtel8oX1Rg
ZlprZU5sU3JhJXs+I0AyS0pMUHc4fnkrSTt7UVIoS2oyODIrb0xTaSV2cWlTClA7fTVDZCltQUNG
VjtTOylIRSg9RQoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9z
dGVhbS9lY2xpcHNlLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNsaXBzZS5wbmcKbmV3IGZpbGUgbW9k
ZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4u
OWIzMjJlOWUwMTNjYTFjYTZlNDlkMDc1NjhjYWZkZTU5MTdjZDJhOApHSVQgYmluYXJ5IHBhdGNo
CmxpdGVyYWwgMTE4NDAKemNtZUlZWEg9OHY3Qj43S2oqSko5bmQyeTtseU58ai1rVVUhailTMl5z
blN0STFmJkx0QXB+QEVhN0cwKmZUMUtICnozUENgSyhuNHJLUUlNYHdBd1gwfUF+bGkjQSVyQ0Zv
aks/SHtRaUZIVUdGK1N2YTw1emUpaXQ/RjR3OzleNEI+Ugp6ZCUxcmNgVWVDLWE8SD8leDxaaDJF
KEEkY2Y0PlZuUyZ1SlEyVmM4bSZVenl0WG01dylCaD9sQz5AcyskNz1Qd00KenlqJTJAYzt2O241
RDFBeD5WLXVgQWM4TihneT09YmclKyQ+QUErRXRBPXQwfmE9KHNXbyh7ZD9oczNaeXYjO1NpCnpl
UEVVMHpXdUg1bCFHaG9UVEsmandeeDRucDB9JVVPOHZucCp4OUltPklNRCRgUEE4RyNrWEReSm9X
TzMkemh+Iwp6Tz9xWWlRRSZnfHBfT3BLej80R0dmeHs3QStKZHZTKmd7ciU4UXpqeHV6R0wzaWA2
STImZDwtK21WJSVnOHFiSzYKeighaikrbT48QWdwcjF8IT9TUDxqLXswSH5LX2Ajd0pPJj45QHhN
UipBOVRxPWckKUdWSHtZaz47PyFGTDMlaCN0Cno+fWQ/PG1gbT0xdCl7SiFrdWY1UGd1TEQ/NXtj
ck16cSt0OHNeZldVbXhGPkgtKnVCZHh4VSo4KzZ6bGhQdFArKAp6Y3J5RiliMl9kSjQqWl4xOCtV
eml0dUtFcEExM0Q8X04+WW9RK357fSlZVFArYjxsIW88djhycFZ5eHhkOEx+M1QKelpSNEN2K19S
VFJ3JDUhNmlMT09QM19mYjhuaXkmQEVvaXZiLSFvY1MpQjNjd3J8MUIqaz9IRUBoQTVwcDRZandL
CnptND9KKzxXbWpjUi0han0pWTdWRCshKCZqJXErd3FAXm42MCMqTz9gZ0hick1ebVZEe3U1TGxp
QzJyZEQ8Kjdtcwp6OG0pJGlASEltc09SR3JjTGVyZGgrdkpqKG0mSGYyM04lVjdzN3BRPyZNdTJ7
a05VejBoNGFJeyMjUXlFYT9iblcKelhnMVYtOTkzQVFtNmA7N3Y7K0FzUXxlbHR7VCtoRTxpayVg
djVKemVXYUo/KEZpbEwkaWt0TnJ4LV9HYUhlQyR1CnpMPncjTWdBejh9Ryp5Pj9TKCQ3empjQnJS
OVp+SnY/ZCtfbWcmVV5SaWAyXz9NQCMlUDYmZ35aZ1Y3U1BJa1FhdAp6Y00lN1FhSSE5RipOajMj
RTlZQmBKJnt2YjR6V3J6SSY1JXFxbCQ3eGMjRj5gaiMzaTJsUz5EY29eUU5eViV+I1YKelJRaCh6
Kz8tVnQ+WXQ2WG5aQEh7LW41TFklVSF1REJ4YTlDX3Etb2xfTkcybl5SbFY0X053d1BxKW5QeHtR
Zjs4CnpfX0taSXJ5QmA5RSNMOUUzTjBvSSo3TUp1RGtBI2NjbElrTCNiQTAwWHMjLVVkUHdHVyo8
IXl+dWF2cnxrWF9vMAp6QEp2fXEjLXtTIWora34hQCNZeTZ1VCswPDsrX2t2Sm9WPygrR0U3JV4o
T1p1TDJZbyUmdmI4MHB6VjQpUik7PDEKenhxTSNnKH1RME9xJTRCYHVKXihDcFJAekEmUz5CdCNL
OG04Uj1naC1kbn4jczlfcmdANkQ0b21xO1hZeTl9JEJlCnpRenhKOVhnPmxBK0ZgSWx6YFdUYHsr
YmowUE8qJmVYbCo/LVh1ZWdecn0+RGMqTn4wTGdWZzMhbUBTR1BgVEN6dwp6ZyVjUFpSZDQzPCZP
VHU0NHI9d3hwaTgtSF9qXnBHUURkQzVreDh+WUhaYW1CaSNONCNQWTBvOzFLcFMxdkZ9RH4KejhQ
VURSc3hhQVFNen1EMzw7KHJDSnlqREFVWkhWaVFfYkEoOEN4c1crZD19aG8yPTQ4PmREI3hXdlV4
VTlyVmZ3CnomJiRfdTZUI3lheWhEJUxVPSRsS2hWfVNQeHxPPmRvenI4dkB1bXdpWEFwPWM4SlAr
akUkQUI+TTBOSSpYMThrNQp6TSl0T0ZRRzdoenhHZVBRK3NRcE1XRnk1eDR5Q1Qkcj42PDFVT0Jz
TlhXdWF8dl54fkU2UFEmfFV7aD12KnRrfVkKeitCKEJKc3V9VyRYeXJDalg5e3lJY2pzZyFYbWlX
VntqKHk0bXtIfVFwbzJOPkowRGpSbmwxakJ5azJBMXptfUVaCnpoKGUldTtpakAyPW1UYDB6MWVy
LV98eFAkSDYlU2R1R0V6UWxlJUheVj1tPDBQamc5JXYpJGI0YnhxeFR6R3NIMgp6Yi1MRzZnQXM/
bGQ+Wloqa2goMDdAVEh8YCFGTk9WZiVxVjVXbzNFeW9nJmR2JVBORTk2dCp6OE1+N24weE1PeHEK
elViV1AzbCVoLTg5T2MjMk00KXB0ekpvVD5CcmsrbGxMaSZebGZ2fHgpYHFlZEI4KzJaaHE3cjZA
P0RJZmhJR15ACnpzay1NO1RjSDtHQUpDSFMmRTQlTyMtK3VFXnlXRXZMfSN0T2kmb0JCQVVaOzh5
MHMmZ3puQzd1KjsqODc2UXFTNgp6ZytEPnB0JHtaTVp+S1VVUTVKXkE4Nn5vVmp5PDsmOCZrcnhT
fXxic3RAPldoKng/anhUWENeT3dzaXBUQnFuTygKekhnbyRNY0FTLWFaX3MmNVU+d3NpTTlfWH50
QXdMWUh2WjxmcXkxa2VnTGJAdE9SXj9zNVI7SCRuSHA8a0AhO2tuCnp1NEtzMEtuZHFLWH50WTE3
b0w8MWRATn4rRzJpbjI9bnZRZCtaPXJTREAkMFVeUkIzdCs0SGZLQ2tTOEJDb2VqRAp6eSMxdWEz
d003dWtvdV54NUUwSXlneGNEYjV6c0NVYCFwX3RGc2pyKTl0M0lDdlZgLXhmKFMoWkpAKDVfLXE2
TmgKelZyfmZuRkB5aUV5ZV8pOHk9SnNMSzM9WFhnIzlUZjBJQDd6YkgoMDFyKSgjNTdiTXtFRGM/
Kng8N2pLPGg8ZVQqCnpKPk9kSHQyP3RidUh8I21qO1JFek5wcHxybFRjN20ldn5NbWswajNoNHZ1
S0pENmdjWlFkNHo1anZtO29RezxsKgp6ST85eFdIazVEZks2JnY5e09TUGkwTSVnS3Z+Oz9ZRn1h
ZWwmR3I+RkNyUiZzMWxiXzFla2ZIfXdHekRVeU8jZmcKeil+SXdHJDdSeUQpb0VMVDNOeTgqaGVm
PHlQLWQyN1JKNWgyJm82JVNePmsrbCktUSRFUHBPWVFva0ktUGFWUU9rCnpMK3YrUmZfOGtudCEh
Nm4lQz1kYVNMPFotM0ByMTwxeVBrbEBsZC02cHUrVzI7U1F6QVl1eVNaI2wlRkdHKnRtdAp6dUFi
VUQ9UVhjPD09c3A/fEJqaTdVbjtqbWNZZH5GRkNFaChgM08jP0deS2NXVG1kdUQyUHJnYl9COGdB
aCU7QmwKelptQkozVHZHWnZoe3BOKG1kLTtyZ3c4O0hxajA/KD8meF5CQldrdD0+dExKMCo3Yz9q
ZCVXRShid2Rhcz0zNjcpCnpJYFgjdyUqY307WEtPJUxERHE5US0+PE9+K0F4PCQ9NklEXnRJNnZ4
YSZzRzxqYEJhK2tWXyhoOSoxK0tBVkNxeAp6YlEwbWkyYGRHYWhNJjd2emBJb1FLJVpESSQtNVEq
MCU8aWFURjVSZCY3U1RHITZydmQ0NlFabD8xcSUkS258bEIKemJ6IXd9RHxvKElDa1hNJHdpbnl2
KFpmR0wma2d+RjBWdnc7KDJScSlhYCg4PSk0akQ2UW5OKGFzMllIdFRENDs/CnoxRnxmWVJfO0w1
bW0ySWB1ZU5nUSZLc3ZDQ0U2RSY3PWV7KmtLUjlzbGFIQHM1cEA/VUVxe1R8b2RHM2FTZ3hESAp6
c3JXPFZaPChCRlE9WXV0OSFNeihtPVBUSj5ZXjstJkZ5WXIyNnA+WEY9TzxRSmFrWS1AKC10bS08
NWQ/aG01QT4KejMjQDNCcllleFotdFYyRGpqTn5wRj8hYjVVaX0lSD1NZE1RbWdBQVg3ZG9nZm5O
c3tLSlVeX3VpakUzM2tNKUtmCnp3V0JwUWBPSGN8diR1aERuVDY9aF5IJE9LZjU2Y01UTDQ7ITtw
c0Jhe2U4Zj1eUHx9Z21kSzZtQTdfbm49OW1vJAp6aXFFcXZFc3k8TSo+NEY4Qmk/eCota1YoVkpD
LXZ3KSRtZjFuNm5hbWFsYVNadVdZTDQyOCMtI29va2hueClGT0MKelYxST1NeXZSNyo/QGB0aTEl
cj9UcDtIJDReR15yWktzZXopRjF4Jip1e15KSUBZJjEqc0otekJhT3NFaFM7VWgxCno7Oz1XM1BO
aTclaTNVJlBTdHdgPF53YXhTS1YmT0QxJUE8Q1BYPFViVyVYQn07Pm9AO0NzazhEP0hxQChNNUpm
egp6REphTXFweX5hdXg0V3coVzFvV2A/SCN9eVlBMCQ/NCFfOyZiO3F1XlQyKUJBSHZxaSVuK2Z2
RS0xJTlmXjI/NWEKeihLJHFFc1BpeHxGdj5hbHNza2MmYGRPQFp4akljfHRIUl82V0gxQVVDcX1w
b20pTFpNQFBibWVkUVdAZ3xMfHs7CnomXiRXJShJZ3pXV0ckIW5afSg+Y2gwVWZfWkhDP05LdmF4
QWVMVl8mYHlUanFJKUMhTDFzRGh1S1dOX3hyUHphdgp6Xmk0T2R8MnF5ajRvM2tHT0dwRFk5Rl5F
JEl4Pj1SMnhtb0o0YyFUQ0R2THYpX05ZLUB4UkRQfkdnOGBjcTV9akgKejNtcElKKTMrZ3xTZDtO
bE9YbWE3IUQ5Z0FzdERzYEJ9PWBtNjBgMlAkdF43PjVMYkpOP2dpQ0RoZk1YNShebiZ9CnpQT0B2
az5pe1ooJFhoQ0hvczZxc3FWN2ZAVnZ6ajRUeGU7bTtwUG1PQzA2TiFOdGpxM3l6ZU1eS1lXcG0q
Jk8/Twp6TGVhMTFndG10djE2eDJiNkR1KX5fMGV+R09SKVRYTzBSWjhpVHsqSE5TaiMhNT15YW5n
UnBTWlBCNW48a34hNnsKel5OMH5LS19pViQqa0JEOFNYSVF1OWdya2ltO0IqZypvUHFEOTFjWSsj
PzhIWDZuLUNRSDNuTEx0WGkwezRmcGRACno1d1lAZ2pWcH4qQSVpd2ErflNlO3cxTEE8LS1LWkNt
Uz0kN1ZDZVpOK0d0eEJmQ05pTkBJV0g9T1gweEFsQlMrXgp6YFB7U0p4fFVETURKTT88Q3RaSzdZ
X2g3VXJ5Xk58QUhUJG58MlRqa0RoQ2piezNtT2xJQURGcmt1JC01TTY3az8KemBpcUt3Jn4pVmAz
WnxQUGhnQVN4JkVkb0Rndjl3e013dExzO0YzSUZvRSYydD5iYUdkeWQ7e2pFUyl6VmRsdENYCnor
ZTFOaztMaUlDV2RGI0NBLVl3I0FNPG1uRXQwdnRBbEdBU3A1MFN1elQ/dmE1VjM8RTZ4VkpOeHRi
UjI9WlZGZQp6Rk1zT2AmcGxWfkVwPWwtOz5yKUJ6R0YqM0hmK0o2d0JgRVAhX2gtb241Jm5aQloy
ciZrZmY8U0VzRGsqQyleU34Kej9QT0ZoaFAxX1BKU15BYlNJeFg0bDNjNGR6SzRfYDJeTmZhc3Ff
cXpaUj4hNHdEUUkrRyE+a3pvfTlRPDEyQFNECnpIK0VrWUk2QGx8dTZFMlQlQlF9b2FqSmUtVSZ0
TlJ6KDAwUmNwViFaXkZaJX1fV2w0SVY5NThOSDljUlh6M2dneQp6P3loQnQ7SD0+LVFBemNgbTdZ
djUmQStEbm05JWpYUXUtT0Yzd0V0YGs5KFc4QUFQXn5QVn01STAkJHlqYF90MDUKenQtczIlQGhZ
PElBMysyPW1saDh7M1ZxPT5RMjUwTlIoSy1CdnZBMCRfRTUwdmdXYVcqKkElfjJOPF5LTWgteFMl
CnpTPW1rMUJ4U31AQWBCbD5iNXB+XkZQKWk/OSkwUFlIU0RlVT83IXBDNEM0cWtFTSFrP3A4Q0NH
RjFefSozZnZuZQp6d2JoMSlXZElAdnY0T15vbz5yPnsjXmk8Xj82PUhiZXx0OzFEUX5XQiV5Zmxr
aU1yJHhtN2t3M1o4TkdPZU05O18KekM8X3YxP1VqfEElNHZgU2J0N1lwTDdoIytOJChNcHFyQ00q
UHhLeVc/QDhjfCoyTTlRaFYzVnFYX2VXeUBrPU41CnpeSSFmUDNOSmlReEh6SGhZLSh5cmpFeChV
T1l9bmpeellHS2pIaXxDelczaXU0ZWN7fSlpcGh8UTAkaUJWUnR2Kgp6OUI7KkRtVyVCIylRT2py
JHpVa3YxXy0qZjl4b3chKEE9ISpXM2I7IVEqOFdqJEBiYCFUWk1zVWE2OyRwdjk7X3cKekg0fFRL
QSFgPzRNYnxRQzZkNThvQztwRVcxI0plbnhgRTJxQn0/NkZPPSk8VndIMCt+XjF8fFkkbD9ZbFJ1
JUh7CnpYKDEpSy0oUyh1WnpXMDhpaCVjamFMKEVnSmlxX0UrQzIrTClfSkYmYytDa09AQCNTemlo
KTQjU3w2YypZJjBVcgp6VStjZntyTiRMQFk7MSg3Q1JAMH4lYms1RWRyYkE9T3dZTVRZanF4eU55
WSRVRyluTGVHclVoI15VNnReQDVZYkUKelFXbnAkNDR0I01IenxQQ3xBOWkpWH4zYGIhPD07fjZ+
VTJPPW91eUdIeEZPMEBvelc3PCl6d2hSJCpTKVNAcW9WCnpvLShyUHt0QUxVSXgoQj9WXnJFO0lH
enwpKGJLMXtWZEM2ZnMqNkEqakJufCUqJWNjV2trVT8mQWImST4/OW01SQp6O2wwMGlHNzBrY3xB
fWladl8td25tTj09VHglSDVtPmQqbCo2SVBCSkd4VXImISo4MD5DWWpvVXp2PFhCYnJpZFQKelIq
UU8hYmMqI3haNjM7SlRQKGU0eHRnQzchWWk5ZGE3SG4qem5pYiMhe31MZE4mb0ojMShASUtZbD0o
I1ItUk1ZCnpIKyRhYTBebT9mI2NYTz9oSHtuYF9GKD1EdEJRT1ZLfiZDYmEmQGwkKmw9UHg9VCYm
LSZofiUzKFg0QGYzaHlgeAp6WiVXJSQrWlp3aTBFRn1IezZNfnxDSlVaTkZjblVGJnkwSndld0w0
YFVDOEg1ajtSQCE2SyhEMHtjen41NkJSYzkKemdrJSV9RSZST2xIM31YUDhTR01NayZxZGljUER4
cl55dWd3ZTd3OUliRCVKQ15wTm5lRFk/eSg2bHI3Qlo8O2A8CnpZU3lLR3ljbH5GeH5tfX16MTU0
OCs0fkI3WUZAKytmaDVfQ3BLdiR8Jm9mYTJqZldEX0g1UShwXjRfdkklcHQldQp6QT8xKW16NHNV
YGtLTHJjYHxxYEFQfC03V2VoOTE2OHBHLTlkbG9Taj59UDlxNT8pfG9URHdyZERYOHYwXj51Z0IK
eihDdkJEaGlvLWgtLV88MG49OHFZZj9KQWZSWGJpfU5fTVY8SVp7RElkNDZzPHZCZyVIV217Tn0j
QXlxKUlxR0MyCnpuSVJwKWUjZCtAcXZmM1hzWH17bj9sbGEtJF5MOEQ0T1NFVCpnUDtpQExeJWt4
cTVyKVBkYGd+OGpDbj8lQjsxdwp6KGQ4YWEze1hTcGZiPU1jeWR9LVFsWW5HeVJyaD0zaWB0RF90
Qj5keCklO3ckbkN9WCFOcURSdV9fNSZec34qcSQKei12IVlATmk4VzxDOFlDSFdke2NVYUM5bCp0
a349cDtjfiskZX1wSjd6TSQhflleP09YT0VAMHU9KSl8MU56OFZACnpfRGZePG9ROWx2OWVIPU8z
QTklVmdrTn5ZQXJmUFlud3prSzxDS0hfaiMyTUB1dTV1UjZwaGh5NWA7RlJUaT8lbQp6MjBKPyEr
UlQ1JFROV3A1VEtTcDNDK0wkJjR5NTVyUVhrPFVSfFRWUUArWHNIUl8wTzZJZEFsU1Q9Uyhtc19W
ZjEKeldxSWJrMDxSTUtoZCVaMClwVDh5WHMlPH1tMWVONXRqQXZMQXpQXzkxeF9HJHd1PURhe0t5
OCh5ZGAxKWhWb3UpCnpYfSNOUFV3eGBNPmFqLUEpYjs0NzZTd3Q0amo5PzkyZzU5TkcpKEhPN3B6
KTlCR0BoWTtjNztLe3owSk1nVWNEPwp6Xk1AeGlOKmRmSkQ7dTNzNng9e0A0TnhRNz48VmA2Q0ZF
UT05MSZqQWkxSUE3anJ9ZCQmM0pveWtFYSU7M0U+fkwKejU+fm5LQyMzWDVBfHMqYU8qI001KVVh
YERMbzhgRiZnO1FtX1p+YDlGczd7YCFKfWRDaDZuNGBsRldLKEtIbGBECnpEYSZOZzE+d0I+Rygo
aF9FeUptYmpIcFFydmFqI2pgUk5BYClNcmckXj5Yfik0KX1uWk0qcWpmTXh9dGAmczxeQQp6c047
NmFBOUxBfWZ0WWk7SjU3cSszKEIxRTU2akYzJm14P3N6d3VyIUhkOUM+SEx1OWo8SjA/Yk4yREcl
MGgxKWwKemN9RWA+T1Y+QzloSCtqRj13aGdtXn1Wenh2MGFiMHVMXyFVbVNAYjhGUnpfNkVeRV8t
N2FGTEFJXzJpNHhoXzkjCnolT3VGRSRUOU0oKkQwbVYlYUhJa3E7eVJwdD4/NGNLMkcoNzJJRD8r
dFpQM20pNEIkeWV0MV9CciMzXjVwREBuNgp6cmdUdGpaPnNTcTlLcEZBaDhsVmttZ2heeUoxfkFN
bGU3RTZ3WHR9aU1yVTZyKDNNJSRkPDd8OG0ma0xgP0I8cFkKel5vSk57YzktfjwtTSskfTw/IUhT
fEMjWkppem1vKTgtKSRlbSlYXndfT3otO2BDQ2YjNW99ZmdrQCs8WlI8MFBaCnpfVnMxI2d1aTBY
Q31GWC1yMGN2UilUcygrUkhHP3tYaUxoQXkmUGJYNUViczRiU2pxcl49V1o4czNvMkdzS000Jgp6
V2VTejdSdl5RcFl0YCtHU2czaFhZLXctaSlibGJ1JWVYQSticUIpYyhoVTd4Wj9WSHNAX0hSMylj
XjNYfEFzRysKenRSYXoxZSh9PGhSRnZYQVAtdWMrTnk4MkZRcEtoQD5ZIShNUHRmd31yS2kyOD0+
JDF4bitjPGpJQSE/SCV0SD5RCnpjPiZ8T2lWNWo/e15tI1NqS2ttSW59YDQ/ZGFBPXo1WCRlWlB3
NGZRJmxTIXJeUyNIQHR8Z3coZm9BY040WClVMAp6IUglTXN0PUlUYj4oPSo7ZWN6TUgpI3ZyKGlJ
RmV0ezI4eTdqYFBZOFJ9QzJJNylKM1Ard0Z6anJUT1lHSClzRisKemh5fG1VP2dpWm0+dj9fXnNa
SkpxUmN9dDhtTWtzQyR1e0M/aXM3UDZtcEl5OT5Tc1h3bHh9MlAhKUxSY0V2O0VECnpnO2BzIXtr
SGRkS01Pcm80JlVxYE98TmdWKn5yYERmRVY3OyU5JEQtZTtDT0FuMDtxZz1PRnU2c1VSSD9GUFow
Swp6T2BVIXRhVG9OaTxgRVBWb2N7cDRzJTB1TGNFYWB9JktFdDJoflNPSVhVbEFTQ2h2ai04SXRM
RUljUyFfQHNIa1MKelUxN2xiaG1ESmclb2BTUTZLO0J9bTl8TGxxMldSWGhPakU1Y3RlXjEyMHRE
O1NKNTR8Jmo7YSZoO1MqZSZ+KiE2Cno/REZ1Nyh3Q29Xbl5+cm1rPEBzK2dleHl4WFl9Y14oMnw2
Ny10eUchLWNFeF8kVlpwQ15NSWtWWmRpRjBvZkpGYQp6dDxyWihOYnZxWlJfb241UUc0LTQqRnko
cnVNYz9SYmtGbXEmYzVpWTE1O190elIyOE0jcnBLVF5XKWpYZTFpNVgKeituTDVDSl4zcSg9VGFO
P1k9ajY7QkZFJmBFKD9RQHBsLWNwZ0xqPHQwNmdqSjVDSDczMWkyMkpWeEdIaShVei1iCnowP05X
I2J0ZFgoIy00MkxjYGY8Tl85JW1DIzthP0dtKkJ7ZFhHdEI+P0d8OSsyMF9QdmIqYDVJMk45bj4w
YV4tdgp6Zl57WVlKcUUtUDlBQklRZis2VDF7fnFfaEttTERrTnk0WktiWW5Hb1cocX1fYHZaNEJq
TWlVWiZNMlVaI3NhQUoKemoqZ0NuaH1Cd2RVNzN4SXk7OTFySzBlMW4oZjBPX15hQmVRcVpANiMw
dWp6elRTO0FZcX5KXiZHbGp0R3ZEbXJjCnpCN1NeWVRHfmNacD8lViNEJUdeVXpNbFY5S2Vkb1Bn
Vz1Ae2FNUStIWlR0SlBSSmhrdVE9P1o+Z1M/fCE8fiFGbQp6R00yZzRMJTtLN0lhbWQlZEtuP2Y9
U25+UnEzR3RUWVpGYUo8KldQKTRvNWNgaj8tZ0tQbT0zMSF2YytvZ1lVRWgKelM5PVUyWCVpRTlg
V1VfPStEMEZgXlhSX14zPGhud0RhPGQpdnozOVchd3J0PzM7Qz9KUHBJRy1XVnc1ZkA2N2gyCnpt
UlVJY3B7QVM5WiZURzZVJHBKVVlBPV52QndTTUFxMmBhYG1+UEBORjstblIpNnomTjZiMldEQjBj
cWRBOWtqNwp6WnU4TmlVanEzSFVZJT9DdzVUUmkxaFk/Wm1BXzBRdnBRNlRGfTRFIVVeKiVUKihN
flEjO3dGJjNrJCFBIzJ0KHsKek9BU0tQYWI7eT9eYzRMYCkmV01vWU0+Mn43Zl9xJVQqejR+JVJx
VFRken59RD5mWHpDbH5pOyNHPDV2VyFSVlFtCnp1cyVVV2QzbT5ucDc/cUk9TD0zOW1WKUxAXlM4
e345P0BfKntTQT9rY18tPmtIMzsjUzB5ZWk1RjBVRlp1JWhXPQp6V2JpLXdSXzlwTU87aWQoeERM
WmtQRVBqT2VFR0JHNkpQKGBOVnl5TDY7JjclelBQfjJPQk1JMkBWRz90N1FAdWwKeig5fVk4ZSpn
TTc+ejxoWl9XNmFFKjhjdWhNcXA8NipzYnt2ZG8jejxwQDJhP2E4Qm02TmZRcFdkMD0zbWJ3JmZh
CnpxWEskQjBEb0o3YFhLJFZgR0ZifFN2Kkp2VGczS3k7PEl8PCVgUjZ4b2EpUUJKeVZILURuN0Bu
NFBSITwoQiF9QQp6dk9XSiF1bVUlcXgqbHhIRk5mUE15aUREQ1pednE7aShFMm5IYT4xb2hfYEIh
OEleJHA4T3FhWUReSDJVVzktZGcKenZJWjw9RWxaV3JBSStiJiRIMypRUXcrI2NOc2MwNnRAej0t
M19JSWE4KzdXenZVd1lTZUZgJlpnQkc1RXVCK2VNCnpoUipFPWxqeWRoaSEjKV4kRW1DOSQjYX1j
UUdsUUFxQDRMb0YzWHh0NWskMExEeW12XyNvTTNka0hVXlFoWXh0ZQp6bFFfPzRnOVRSbCMtUmZh
U2N4VWQ+Knl3NG5feV8xP2x0dVNkWjdTNy0oeilheWlIRnxQRVBVUSFGUDVrVXlIaWQKekAqNmY5
RnhJMFkxaU9gTDx6b0BMdjI+bXM4Nkt8R1dAQkxSVihgazI4eVhIbEpJP0tBPT4qYF9EV2JHUi1V
Nn5mCno9M2NwKkAxMUJRWnwjMjVeNW1WZHo1NEVKX1Imb2A+RkxnYmNyKW1GJWwwbT9hRSR4I2hl
OE9nQXlVbVlse1pjOAp6em5pME5LV3pfXl8oXyhGM3MlUndzcExJPj9AIygqcXk5NHVOaktncWco
b2gzOW9TRSZ7NmIwQHR3ZXlBOEMhdlkKeklKUzVebTllISo+Um9va3tscUV3aCZXKVVaTGdmTF9V
RUE4d3t7X2dFZk4lYzZNKncjJCZPQnJ5bTBud1MjNnMqCnpudlVDI3pBJkZLUktoZWRGO1J5I0xg
fVBYeWYhO007QmxHN3RTNnpJWFYlaXBrNF5BdEx5VFM9ZCRwYnxZIT9fKwp6Q0hNZmlLcDJHJTs5
S31MeSZQdCpvK0RQcnc/VzVDeXRkJUNPMztvUVl+fFRqUHQ1U2wqfjt0dVViX15PaDs0N1gKei1N
QXN3VUpRMVhVVSpnVz1TfUFxNTJKcH0rcHExbDlJS2l4TjQwdWVPSmFXI0llIWpwNldIKjNrPD9K
flV7JXQkCnpTMW0kOXdDWnE1USokJHlYeEYzenctaFd7aSY2VVQmTHstcmUjY2MlaGg8blliQ25R
JWhBMFVQNj5Xfmc9VDU3Tgp6c0F3Q09lKEhNZmRIcGtBejswVkdYZnorU1EmKH45bC1GZ0s2WE8m
MiY8am4laFcwN1gtfXBlSTY9WTtBUV5ZcXoKekQ5cTZEeHluRjYmb2k5SDFPWkA/cnVqXn4rWUlq
fUZORTNXalQleDZXeGtmeGQqPkwpIUozJHZGJG1HQXAoO0xQCnpKcWNKKXskJnZaWldwfGcreSZT
T3I+YnQ+ayNCT140WihCNDxeZ3EpJV5xYS03bDQ5JHU3bnZtS2RLVTF3QUdhPQp6RCU8WVc1UWh7
a3B9OTxGe18zZFJLcWc1UFlyQ0VZWDk/KTdUNWVAN3tqYH5faFN0NEsoREMwckU9eFZUVE0qU3wK
ejNGQW1XOFhSdSszQGRGKTBEM1RXbD8laEZEZDslPzZ3bEd2QCMhMm1mX1FlOW94PCk+P3wlS0FZ
fV9scGY7JWV6CnpSITRxKSNHUHBLNXAoejBlP29nYjA1UGM4Pj5qbUs0NnRCfHd9cDA+JERVODFs
bHchV2xaVj8+QksqUnlVT2dDKQp6ZkhWb2tDbmpNX1lIUEo0bW0+djlJPyhrIVZFTzU+TV4yNmI3
al5qIzQtYVFpP0VDc1g9JmVReTBXcUpXOzVlSioKeng/eWdQS0VfZ1luPG5waGFjSDV5Q0wqeX4k
UktlK21oYFRUJjFhKDgrUytWTT0+QTJ7Zj4tTWE3KVBrO21sSD42CnpwPzIrckt0O2JtTXA1fDxI
Y2BnTiZuPEBFNFljeTZhYjdLMzl7bFo0eTg9RiEkI05fYlVvd2xGJT41ZjdtdVdAYAp6SnRJMGtA
dmNsMkx2dldvI2c0U3JMZ1oqbyZRbmApZDgpd09jMmhvO0l4ZCl8T2E0dzNoXlZ+KzVtUUozd2Ej
Z20Kej05TSkhVExCRXtEPSkrNlB0K24rcXlpZVFkNWN6eSM5PF8hYyhgYWdLOWh6fD5JfEVSYGAo
fVkoflZaSmM3OWdqCno4e0tAQWgzN3FRUyp9WE87OzN0a0pSNVhrQSFoWSQ9SCEqUEp2c2N6YWpJ
RiVwWiYjR2hNRH4rVVNPKlJzfGNOUAp6ej5iXmU5WHx3PGRAPzdBcGMlRkNgPWdtMGMoTSo/OEVR
K3JwXmQ4bF9PeTBBZHNSJlEtWGc+V3E3eHkxbmJyXzgKemFoS3N1T35LVDY5V3F+N1R0dk0yZDxR
XyFNNG47cm1CZ2l3NUFUZkdXYmZEWnluT1g0KnJTbihgNGR6KHhERTM5Cno3ZHkkPHw1Y1lse3l2
ZGN0VEh3I0UpVXkkJF41SDcmbiZAYmY3eTszd3x4QnBQclBCRF4hOHJCcXdjSUAlTnJDTAp6YHZS
Nz5hPjBsdzkycHk5TzApUnwkK09NJDl1a1NGMmpndHREPU9IUlZSYTt4UzRgRXZIcSo1QGF6PXh0
MzZBK3wKenVNOVk3YiQ5amAjQzdQSkdwb0BsZzUxYWc0S3ZtQFZ4YSVMWS1VZSh4OS1HOz1eU1RZ
R3VBK0pZUWEmWVVlKVYwCno9bWk/b0xUdCF+LTVOeFluN3YtciRDSyQxPDVrV1NLZlBvc2BsLTdY
THExVG5WNz5tbDdRdlMwdkM7fm45azRubAp6Ul5QTyZyJC1NWW4yVX1EaVUtS3grIXczdj0wbHZE
V15kQlZEPVR9YCR1b0dYTmlzM1MpJHpiVVY2RmxuNGlZdEIKelpgeHF4Y3xofkFBfFhmTkE5UXdm
UjgjUmMldHtxa3AkSiEybjI9YiN7aDd4ZDQmMSlCeG1xTSNwbU9vRE1GYSlFCno/V3lPcTdxLS12
bTJudWglekEjUSZNQihmRTxqWGxVNihUYmJpKnw0d3B1SDZQOFowUjktOVpyajNgPXR1NEVTSwp6
MHtCQD9seUdiTlRiYlIhVEBQKCF2eWRgKTBncG5rNzxTYXZRVDZVVk1QcDhuMGAoV1dDWkBnUjt7
RHBWZyhxMlYKelpmO3B0RFFHVz1BdyRFJVJAOypyZ3Y4JGw+e3dHeU1QQGIoMmdedj5CJHBjfntE
ckw3aW4oNShybDZGXkB7Mml0CnpwcyUxdi1UUCh1bktzXjIpeXVPKVhCZjdyc21VKXteY15hdXt9
ejhqVW8wQD4zZzwkLVNvaHNyYGZDVE4kRWpfaQp6cnREcnVBS3VWTFQzWHRoZHtHJE96K1BCTCs3
NDhLbVpUNXhyOVJ6PXBaUzh8K0xKSkRQM1hrQTA8VkNGKEU8R0IKej1sPGV6O1AjNX5tazdXZTJ8
Jk1UR1dCSiNyaUsjUUZNdWJ4QkprIWZla1lRZTZPa2dTI1YyJjtwfH16SGpeKndTCnpTUzRpTk9I
X3d5aT1NV01VeWdYMj5CWHRuWnAqVnVNU0JzUUA9bW1uX0dRQFV2OUIrUiZ6QWIzdGB9KyM4QnZi
MQp6bFcwfig+enxob15idjMlVlpHelYyXzBxYXd5eGsoeik8c3dRIWx1TlZ2YCgmbUNVIUNMPmxE
a0JfLXdgSXhOZHkKemZyMHtLY1k8KVU4bFB0TiVna2BpR2Z+XzMwdElvTnd2QWYtYHc5QDxoezdV
WSt6YkczIz1WWH5lRmBfRFlkeXU2CnoqMShodjZiezkjQl90Kj0qR1ZhbjhGbXx1USluXjlhXitj
WU97QWN+RkxvNHBDbEpBIU0jfENrYXZWXjZQJXR1Jgp6YmJHMG9SbDc3RW14ZkwpO0VDVlQ9Y1lt
bnYkVnlGNjs5Q3YhfGZFY2lKQWwhIXF+XlJIZmVjYmR0b2FBKEY0PDkKelE1MC03MjVyUyhwOEoh
e2RPZFhwbXl2cT9KdStUNClxfUUtOzRXeGVRKF5RNVVHdTU5KjxjbT0lIWh+U21aSUVYCnp4NF4p
bkt0RG42c1R1WW9Tfk88bCRHNEpNakpKR3x1TClaRFUxSTcpVitleGlsOSFKUSshfnM/elMhXjBl
Vj1iMQp6WEB9VGE+bnBVPjk7ZTVqQ2MrQ3Umb0NzXilrdm1GOzstMH0+U3tDQ2tsbE5gRkZGX0Ay
SnFQP0xoMktOSylgKG8KejdkeUlHdWlWQmJlfGUlKkE5SGNRSCNyTEFWYXhXYCkqPmdKb2xeT0w0
Z0d6TGUtTFJGSiZsaTBjP2tgJEJmYFI5CnoqdCZZTTB3O3ltNVM9PEFqSEJRKTF+VGVnWHNHWi1U
ezFtPyFaPFchYi0zX2hzNy1LZVZtJGpEKShYZHp2RSFkVgp6KFJ7K1ZHe2dacmNWPntQdUFkfTJu
aEFKbmBlQ2QoTDApXyVabVZ3VyRJeXYmS2FqdVFnMkJsZ2w4JUowdzZQMS0KenQtS3kjYG4zWkha
e2dfUVJ2Tis4SnB7Y3FsbE41bVdVKnhEMDYjTkJ4V3slWEd8e0E0SEx4ISgrN3VYRWQ+eVAoCnpV
PWUkJURSRjdmWWxsKi0+aHwwbnslMkZXZnZGREc2QFdwRW1iWmdGcEFtYXw/UVF3MVlhN2Vmendq
eGZXSjl2ZQp6cjRMMVBhQD18YXMyTHFSSFJnS0dNPj14a3dWSlZzTnckbV5OaFFffXM5LWhRWjNl
Z2BrTUZqTzZQPVJtLSZ9bUMKejNobEszMzctZDR4aFc3Xy0tJW8tSFg3fXg/YyFkJkhaZTF+R015
JXVuYmhLXjdySCg8JUtyZFEjUkZXVCoyYWlsCnprQnA5bTItRFcqU0xWOWBxP2ohVDt1OGA9eThW
JUplUXhsPDdCIXxWbG03P3p6fSgyMHZiamVgJCkjbjB6YEpAaQp6MyZhWjZ2OUk1IyFeR3xGeHBv
QFJRVXFBXzdfMnlqPHpiQ29ZPW5sSFdITEUpRysoQVJqTFYjZzZJNDtZUFJTMHsKektoLUFkYGVU
YlpLP25NTEFHbTgjY3NCKlMxKSstX1c5QG5Kd152aDVhfTU5YClLYjM8ZDZpOygxPmE4RDRrbVNl
CnowWE4mYFppZEtUTXUqeEgkcW1mOGVlZk8tRkN6PCtUeV8yajs3Pjw9UlAxRDYzQGp5S3hfKUEy
OyRnV1BhcWk4bQp6JWh+QVk9JV9afm4waHl2JHxMQ0QmRiNlOHshfWJtXylWc3h0WDEjQz1NdWxJ
N0tNXlhVKjkmYVEyUzBPZFpKVysKejtMWXhSaCtlRjNaT1V4ZzhjK1c2c30+YU0xNlF4Vno1VjIp
RGF1P2RyVkR6WkZGQ15ecGEyO1BBKXp7Z1JqQis4CnotYGElO2FoXkpWVkwkekJiWU5mcj1kfVcz
emtaVDh3dUQ1bzN2QihlaCEmPk0jajhCVD1ofWZtKXQwM2s3YEVUSAp6MGojWFd5ZnElJWRjRDU1
KmliKXRLdnBGb0A0O3c8bXRGWEd3NHkqa0ZLOV5DeWVGKT0td158PERhakdFdjFHcygKejU0WGBq
T2d4a3FGTHJUOzkwVHhQRXR7bnNfUXojcFdEbypeQmJVR3EldX1BV04rU24wI0dUUXpWNzBYSDZS
NkdDCno5SSY4KVV+SmJaZ0xfQ1BXVER4QW02dzxFVW4rZHJhWU9wbztOYTYmPklWQVd6WWw2P0Fj
cTkkeUNAUlNuXlA/Owp6TGgyKjxIY2YtdWVtNWt+STNtJjIhUipAOVg2flo8KnZMcHAhZXBKKCkl
KnZgJUY2UiFtcCg0ck11ZGtPTVJmTG8KejdHN0ZnaUZtVnxWbEVpKTJxbzc9SXRTOTxScmIxRTRl
dUd6YmFUX244RVQ4OWViY09pMzxAb04tYHlAJTFeZ3BsCnptSEtyenlVZXdHNHs0KnhpVj1yJHZY
fHs7I0Y8XjJ2PkBgUEVDcEwmUSglfUBQJm82REM0RlBIe29qMSZIOEAqUQp6c3lTeGp7QkMhYmEq
PlJ1al5sWDhfX0xqbWlydjVPI29+WEZ7b25RMnw2TDZKfEQ/clYjTH4qP0dFJEVPcDElVjYKUDQ4
aEwwezkxaH49PWM4dlBsZSgtCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9h
cHAvcmVzL3N0ZWFtL2VjbGlwc2VfaGVyby5wbmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaGVy
by5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMC4uYTVlZDgwZmMxODQ2ODcxMzJhYmQ2NzM3MWNkNzgyMTA3NzBmMWNh
NQpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTk0MDUKemNtZUlhaGcqfHBgIygoVVErY2NrUGl2
SlR0SUJkUHNfWVQ0UWJsQj40bnojQUdOUDtxMFYwR0R0V19RZFA9ZjVHCnpNTDxBNldASEE3MCUx
az0zSXFpYkFkbW5kZ3BkJjQ+JVFzeGQleGZSOzYwOUNhfnZNSSVlQnQmSVh+eGxVRHVzSAp6YG8r
T3x8SlI0Vm1YZWElWiokQDIlVGlMKChOYT1oYHV9QDNfPX09cVEhNG57YkxXQ0hSIVR+eTFeVnx6
OHxJWjQKel9Aakt0eCQ3WlVGZ191O1V4VTQrYTUkWEs/TGFAUT1kWDlYYnVodWA0MzdDPkRYQVol
WTx+WGY+Zk94NmlTVyFCCnpmaCQ5WmI5OGQ9QUV3OFlfT19Fa01AWDt4Unx6RW5afHJ+Y15ZQHFE
XzNNR0ltRk5kdm0zeWY9dWxLeXNzITJUYQp6RSY3TlRSZnFqTTtZfENOaEgoTT1ifU9JP048PFlz
XjQkZGY4b19hRUp3N3tJSzMzZj9xT1EwfEcpIVl6PHd+fXEKenclRjtrdmJ5Y1VzQlZFJVFnKExK
UTZNYnpjXnhxckNjRTx9KXg3JGo9cjRBakZQQGN4UjBXQDdkJXBPNz1qcGxICnp6ZFV4SHFEbFhC
e0txXm43WEFVbktjVnBkdVRiel5RaWhQM3stVV99cS0kMW5OTjhBSUw0bEYwWWdTPXNoPykmXgp6
ZiMyMkJsV21GJTMpODhAUjtIejx3eSQ7Qil0PzdDTTVgWnc9PG05dHNpfHFqP1VzbEIteWlPbllX
OEB6VGU+cHAKeikta3JVdzRWTnRzUy0paytXSzBpVjRCdzU/ZD4wVilOXmBUS0llUGQkb3JwTFRp
YiMrPUVAYUshdHx9PGwmSz5kCno/QHptWjB8ZTFoZmUxQUVweDwrZj9sP0tISjEkX25sRiZLaSYj
MlFqdE1SOUw7RT1tYj4tJmEjKTNXMkApPE9wUQp6VCRlNnpzcXNvbDdrdmpXbDNyZSRIfDkmTXZI
ZzA1IT18SypyLXlITzY8d20pPHpfI3N0K2c5TT5yTEc5MCRKbmQKej9PKUVMKFIhRDE+PVFuWkd0
KUNPeUFuTHhnNkhPWDd0UVljS3hTWlozO2MrXklyMmM1eVQzeEBrMEdrPjFePU9hCnp0Pys2XkQz
OXE8Z0dHbkFSX0hsIz4kSj5fMCg8Z0h2Ozd4Mi1NXnI1eU00M2ZpJG44bzZ1d0w/RT1iS1o2ezFa
KQp6WStRWEBTZzJAbUR6ajB3allsODN1KWFeRkdyUll8c0Y1ajJIUEtUKEpGQkM3ZXRzWCMwYlAz
UTwmQmQzYGckeykKeks0KjQmLURLMDZwdjBDQF9hTDVxZGNnOUo1LVdDUEt0RlRle3s0QmN1QVc4
PlQrd3gpV0o8T3lIKFNpdD01bSlKCno3SnpfTC08XmEhYXgwQGQhKktTb1lrbHlid3tCO0VsU0B7
b1ZMKHEhYzlaYEMkS0tyPE8qKHF9eVczQ1czWElLMwp6dCZoc1A7LTA9Vks5JWsxbkh6cCo8QnFi
dE53VCRkLTBZYD4tMDtZP3lCY2dQT0RyJXQ5QmIjYHBrYnF0YDFFTlUKenBeZUFGU1Q+JFE4RGN0
XnU/bSZwKUE9RG96VHB1OWo9REt5cjhra1VwPE1WcFBsc052WVNqNG9wcGNedypuTHZCCnpQUiVT
clI4ZH1VR315KGNzNysxMUlLOH4wQUUje1Zjfj9LU3tMI3pGX1I0OV5Vez85QVRIP2tYaihQQTh2
VD0kdwp6eHl6KE9WOUZrXnVZTHF5X0t2eyp5dzZXfmFTRE1RWDZ+VldyU3p6dWJtbz85dC1VUWEz
Xm5ybU0raVN1VEVgYXoKeiZEPyN3UW1BJD1qXkBCQmxqVHN8bUZaYSYpMztfWjEpQWdkQmFueit8
R09Eez4zXjZ5TCExb25eam0jbClUQ3xYCno1QEtUKnd3QHtPNV5IQyVXRTU/LXJoMCpWbVY1KFJU
dm1HeWhqNFR8YmkxLXZ1PD8lN05ZZXFzbTsyIVNvQGAlegp6cXVafUVAfD93SDRZenxgUiZTOUpH
MU5gYF5USl9JJiliVjtuVlhabGotU2BPdFkma2BpIXBRRXFGenVhOS1ZKC0KejlgNDxoNURBPCRD
RWYkY3FCWGt0P3cpdlNuXzE3MzNeJHRTRzgoaTg2VWpJb2plXlVKTW9UX0liajhsaj1MTl5YCnpY
aEE0JEQmVUVibWUweCpCT0tQZzAtQHI0UkJEJSQpU2IhRnY3biEjSnxQJTZXSlV5UHZrcDE9eCVP
Q31haWtXMQp6TFVmc2RHZH0pVT9jOE5HPFdte2VjR1R0ekB1JGpvPTFBOTc2an5aZ2FyIz8wbCZn
Iz07c3RUOHBoMzUraz5nbkMKelNacVZPPjhyc241V0ZsJDZBJDw2bktaczh3PH1xJXZscysrbFVV
ZVAmYF9vZTg4U2c/cE9qUnlpS3ZNayp0Tll6CnpRMFc+PmFTdUFaZUNUK3E9NElrZCt5WSkhZ1RN
TExyLTNJJmlKTnJ0WUdFNnZkI2ZkOCUqK0BKZSpNanRrYUtuQwp6eUhuZn0rekgjKHN+dnZzWCYz
V0llX25XOyZed1NibWJpKFBNb3V0bUZaQTh8UFBqTyEkeiNoLVdOViZ9OEFuNz0KejU4OWtxUXZN
UjZpPVFGVE9gVTZHeysxPDc7JT9YMTNSQE1mJStGbVE+QnElO2FtcUZPalUmYjM8WnZDNXhjZVNM
CnpJSV8jVl5MfFVyeFdWZFNSUzZpczkwPzEtVjFBYW81SSskUilpQV5ARm5xeXxeeGM4UEd7UWB3
ezw9IUtgd0lUTgp6eEtUODZQZlROb2VWYys3Jnk0IyhUbkB2YT1jNXo1aSQ+dUQycEA1YEo/ZSZK
KW9tVzlqUk50clk3NFMkN3g9O2gKeiRYM1IjRTF0cClFOEp7OWFOcWUkNGVoeUxYe2kjfWVTZkc0
S2hCblFtMkVaNGRRVF4lPFY1QiRqPlotVXlmYFJZCnplcmo1MDtRfnNuR1dOV0w/PHRydVFmYnNZ
ZlVPTTNRVUlmaz9JRmRsUHdVSnBiV3NRYj5ENWhnbFhfQjlzMTIjTAp6e1dfQ18qWj1VU3dAWV5z
cCtyPnEtWGIlbmshPjVeRUUwb3RuOyl3fXV6N3VIQFM/aDkxYkBHOVA8SCFQMWtOcDAKej9mMyRK
SyFzP14yWGE2RDlLTTFKNGx+VFR5SE9nc3UhNEVYMzhSNVUteURUTz4tVnY5X1lqTGdWZWhLX1JE
IVliCnpjMTRuMjJLZ0lmMSZITEVrdzxOXjwlbkY8M1FObk5Ibn5jP19+IzRfJFhHb09BZ3NKO2ph
O3RxVGN1STlXQlJ1ewp6SXVrRjNNaCRYWGtUMDk/K2hfVFJnR0FRal5PN1lgTXB2MlRVQSZKJVkp
I0w4RnRrQSokX3lUey0hQ3JxVjQ2UEYKel45YkIxV1lNXnhgbmtVRXYpYnVLRGh7VmtNPVVmdipi
cHNfSlE4bSN4d2orUVdVMnl1eikrN00kVnQlI1F3QXZBCnpGNS1ybk8zKFV1cGhJNTQkPlhIV08x
eiQ2SW5reXUzTGc0X0slM0Z6WmslPUthdjwqdlU0ZSZeTTR2aiN5NHg2ewp6N2klcyEkSUIlemZt
NylCO3x0MlU5fTdfeW4hSnAya0h1X2pGMTVeSm5YbGlvcCRIYXpWK3p4WmBlNlUxJk5mVXEKekRy
KHU0WXQhWn1yKjNuJiYwMD9vRH1CWXpmcnRfLVd2NnVAPV98cz4rdU1+KGhvUCk8e1YxZzleV1B6
IzdCRHMkCnolclQ9em94IUR5TF5ifGFqMkAxZyVPZ2l4b1JuQ1k4RGAyN2BMeHhOZ3ozS3I/dUtB
fGhEdmBFZ3FLWCFQdiRJQAp6SDV3JUd3YEBxOHtqX2NoMTlLQDdDRWpXKy14OXRuaWAxfnIqQm0h
RTRHQyVvdE4zbUJAVk9LZ1pnUW4qVSZESXEKeilyZE0kZ2xlVjBHUCFsfksySjBBQWtuZzNASkt1
WiU8NHJid0xidWBCaF9nR2YkIUwoYygtdD9zTSY2PWdQXnohCnpTPzVkYl43cjlKe1RTPTEkd1Y1
VGx0P0JJJGotPCQzMXtfdGpBZyo2Kk1ZRTxkJkZHXk15ITt7amZ3ZTRleTl5dgp6YEBAPUA0fkFt
LVZReGdjMm1PSjhNMSZ6TiFXZk02bi1Jd2JlKi1icHdlcEszX29rSXRBJDdQeEomV3Y7RjxeU3gK
eiZIPXM3WDRzdU5Xa0JxNlVKPHc+QjU7ej9FcTZhIUdnI30pNiZSXy1TSmtROFZnMEM4JiQ5Mzx6
RERqRDE0WUwqCnpAPXhQTWprPEA0IzkwWlk4LXN7STsmKCNgTz9RQUo+T29QYE1hZl9Rdz4+NT5C
RVhtMmFDLWgjSzdpU3hre359ZAp6SjxXM2ReQGl3QzRFSH1vQWwzNjMqblc9cnEhfVZiczRibDBs
VjY3TVBCTiN0P2JtQHV4KnhoMCNXcH1BTSEweFYKeis8RzVaaDR1akpKb2hld09Sd2s7IWFSa15L
VTVreUxqIUBlZmY1OCE2Ryt5ITF0aTtVTmZmWSV3RjFuVHpCVS1+CnpAZ2lpbjxgYipQUWVyXlZY
NUlNWmRWYnkySTx2KDIoWFBwRzteVFJfclhgLS1Jd0h3XnF0KDZPWmJCUjZxbUZhMQp6SV9lZT92
LV5jSCE7T2EzczUxTSFHTlpKdCZhTnkkIVNALWRtWS1nNDsyQTZUaDJgVXhJVDEmO0EjJThKMVNX
P3MKenhvX197TUZ9NG88JWRsaDZ6PCF2N0pKQEA4fiE4VTZ5YnJNI31zQGthO0FtSUwjTCU/MW9Y
Y0xpPThvcEElQncyCnpTMEsrYThyTk90VXRQUTZZV2NAXj1YfCZYe2FEbyY3KWFKV2BNZWlwO0Bk
SnZXWXo3UGtTU2J1cz9jYVRvRElXNgp6R0cpKW1YdTgzUSt9SWozeF9zNWxFbzJzeGFDQ2RpbTYq
X0c5WUB8N2twLUxsVT1jWXRkN0hoVE9ISXhXKXI8I2EKek8/RyphO1BwbnZjZnkkIzlKM09pPDNG
MVU3SEl6Wl5QIUw2YHthT1RVXnVGRDt0aFlzRWVNRzhaYkxMSUV0cEFeCnpvZiFSViYhO05aUndQ
alZxYWtlT3VoKnVYQ1IwXkxMaXlDamxzRjFyXkVeK3NObTR1RFhndjF2QEA+SnR6O3RTRwp6JEgm
LUNyanFjM1F6S18pKHpjQ3B7P2JlVlNOdm9qJjVuSE1CSXg5eTRreT1aZjVjOFMzTEEkaFgwQyZB
bllMbmsKejUraDxRSkNncXFUY1VVWGJpNGp5TjI4ZW88T1lMcnlhLSNtQkRnbWx2JH1eWGczNzgp
SFB8OGx2NVhXfTMoZSUqCno2UkAkQURfRT4+WlljLVV4MDQ7RzAxbCVNK1FHajVMVDU+KHFzQClx
biZ+SURQbCNPb1JLTk91PyN8dTxOYVNtIwp6RnQ+REBvPTZnfWAlekFBV21STTJENjshaXMwR1R+
PVRFbDVlWkpWfkJZRD99WH04YSkkLSM8Qzxqekh7YjlCOUgKemRUO0YqXnUhTzRKWE82UDI9fDIj
ezRpIyRqU014ND16VWA/Y2pMdmkqbmZrU1VMUz9TVCFGQmZPIWpkdDtqUF9FCnpgN2d6fkt5ITVe
aFR9Z1AzM0BheXpeU2lfRCQ7RXtmZjtTdT4wKj1NaiRlKkArU09CYT5uIU54UTRMNF8qej5ZVgp6
Sjw4b0pIZDRoblc8eFohb0ZIeTFRMVJ7azloJTElSGNyKCRuayZKIU16RyReJjlvQTBsZjw3MT8p
Rj5abV9zMXAKentHSCo/SmFPJGFkSXNwS01jaVozJUZ0Q0EkdHFLaEM9SW0mWmtILTFMODxCRU9f
bG1qe1EzRDtTeSo1XmFqTy1zCnpDZ2VPTU09MCNaOCp9O2dXfjxweGJsazZzeEJpbCNnSzZjdnsm
cnY8PzclfnRMTyVAWkRwKCZmezApPCVWQzxYNgp6RmJpbzF2emJjYXlxWUotQ0NYSSowTHNYQTJu
UH1NIyM7fHdKX0JDPD09UkxtYVEydSozSXlWVFgrZ35gUSF2QngKemVMSXVpWkstKihUMn5eY1ZJ
dFZUWj85TWgkMzhWYFhNUEtNVHdtSmh2NXs2Qj1uJXxWRipeNUowKkYpVTVMX1ZLCnpzXyt9YWJZ
I0BIU0c/TSZDa0FXZmpFY1BjcUBuZ30yLXctd3NNUVhJI0I9VyVZUWk8V2NyVzFSaTliTj1uZDVM
awp6K2dDTWBiLTlmanYoOSE5NmVSdDZAbGBPbXBLSE9aWUhaP0QrKjMqeXMzfnIme303KzM1a296
Miole3ZsZTBtMVcKejtrK30pPD5JVG43cSheRDQzb0J2ajZkN0FkMGowZjNYdGY+NCNGYlhPZzRF
czByelIya2pRfTJVMDI0dXp0MDRNCnpfMEJuNGBpIWI+ejBhaTtCTzZkZVFAYWNnQDkySCgwNmNn
UCphKjsySEIwOFR4SW9aRkdFPUwwIXZNMVZGSzF5Rwp6OXVQT0BJVGhxeXJyIUxfRXVTeHBUdn4z
cjdQa2txS1lJJEJ7YS0tNCQ2NllhezBrUDlmPTY4azFHZ2Q2V0xpUiMKemQhKUlaZFY5bzRIb3ln
Vj9RIUklPUV9ZTJSXk1yRDZuczg7TlFxYyptPjs+LUp+Xn0+bykha3ZvMzE5LXBQaDBDCnpmbDFz
Z0R8RHheKnVSQlZnLTZPYU0mN1kxUlVFayslJXkrRWtpPiljQ1ExJU5vOFYpb3slI0spP0AyX2xs
ITtmPQp6KyUyaksmSy1iJjs7akxObz5uZTdrZGdNR21Fb3pFQz4pd3dJcGhFQG4qXjZ2YzArQHZ5
b0smQHV5VyMyb0QkKj4KenkmaDwhRiROfkEpOFNqbWQ7NzFIcn4/cFhzRGI4Pk1jK1ZuQ2N6dX1X
VTJ6JEV6PklxQVNqcHglT1ExTGQxcVgwCnowNTklYjh6YiQhc3Z5VT51a0h2bT08PzI+Y1hjPD1y
SDk5PVVUdlYlIWYhNiMmMVZCdXprXmlLK2Zqdkg2QD5DRgp6JShTPjh2dG8zN3dmI305Yl9UNUpq
KW1wdjYreG87RWJMUnRhZ3oxPHhOM2hXPGVyT1JhQ3pVRVpWbGltSm96dWgKelgwYG5scX5HNiUx
Um5BKF4tO1YociFnZFJpe09UeEQ0TnhUam5uJU9ZfDdjMyZZUk8qeVQ8SVRFMW8zXnVyTSYjCnpK
c3k/SGszOXBYYH0wQEBFP0E1SWBSUlF5cjw1KHNCM2l1JFJ0aj1UIzYmT0pgJi01NWV8TXgoO3o4
cWViNkFaPgp6eiszdjFeOFcoNjtXZlZVKmw7K0o2b3YlTlojSDMhK2cyNDVafWtIRnQ9cT91ZWE/
VWVrOGIkRER8d0RJY344cF8KenokP3hIU0BYWUlvP2syVSFFQF9gU3M/Z2N3KWVfST5xdVI5Z0R3
ODglZzZEWTgrbW5lel5XenxkSnshMyVeU2R7CnomRFZkay1RMy1DNX1LMGNQPDt6ZEg2PVRYZDd1
UCF5dkchcSlCZjxyYEFydldOQTsxQmk0NUsmaWNMYntycHNPcAp6aTBPeUVnfCpzYTcjNW8yMW45
Mm9KTn50JkZuSiVAUz5KemQoV0pVRDZ7dVNvVGlHS0dOZF8wRTkoeFEhWTBeYGAKemhVWkQ2NC1Z
bmpoVVFoNkFkQH1iM15oWFhyal5oPllgVEw2azZNYGhZKEtnIy1JZChLMHlpZjM9Sms8O3BlZWR+
CnpyI2t0cWJVfExYeEpPLWJoJHBKUD09ZCtGNG9sOTBxNVFBdjRyKz1jPitQeipGM1ZBdUklUzU8
NEZMbGB0ZDRfRAp6KGR1KFdWT3FZayt+ZW1HMD5Baik/S2o2JkYhSVNQOFFMJHtlc25KTURMK1pQ
KHZ7PDBvWE1CRzFBcUhKUFFLfFIKeihPSHhrRmglTTgwUkg7TVhVQmElX1BeNE5uQzFSZVU+TEdx
PCM4NlljeFY/XjxIMnxJcG51SUolVWJASUN5Qkk+CnpZayZzKTdaKEVHIVApMT1Pfn1nNC0qejJ9
KWR+WkhTO05EU3lgPzxEb3hjRUplZSpCJDxkPlQrVV9GMSNUPTNwbwp6fEZma1olT2dqLWIjKld2
ZUFSLWd8TFQ4QFlRZ3FEYVRDYDY9WldzWkpjanhkM35MX3liIVIyVHRuM2EqMHJCPXsKenhCbXFm
YUVecWFZLWY3e1NHby03ZU4yWlYpV0F2I25Da2oob19iZGJhRUhERCRpQ3UpOHd3NG5AJVcjWm5j
Qz1ECno2U3AzbiMkMH1SakFUM1B7TUctNnZwcTYpQGl7bjx2NUdnMXM9T1FeNEZkaX44dHdmXmNw
RjJsd3VuZ1JONWhiawp6KkA0dExHOFA8WldkYy1Qbig0NUI1Mm03TDtWcX11SkQxK31kKEBSb0Jz
OFArajsofSQjfTdLI0tndSUhTHtMcjAKenh7c2R8PUk9PiYhOz9QQiZOZEVtVE9re1ZrSSFYMXRm
fF5qSz5QMHFUUGdwPGk9KV5DY1cjeitEP3s5SlUzQ1pkCno1cUg8Rl9aVWV1JUQ7cHxZcDE7WDdJ
OFd2R0hUbFZHdkBKM2shMWg7KGtsYnAxeFBkZHpvJmJAN3lAKzJwYCU+SAp6K0x2RWVVaGVMYF82
MVo+Y2I8WEd4dG11VUV2R2AxdDZAfkZ7QzNDPUNmXjt6P3JTO354elI5PGZyfWZkJks+TFQKeiM+
dUxmSCYoV1R0UkMqbl8wWEFAenFKWXskNUEqcUk7V1p2YT9gWEF2a25yR2tgeUM8YGVnZEE1V0R2
NiNNSFo9CnozNU19OyU0WEcrNWZGLThkUG9vdFBUbSlIY0s7ZVVDQ2dfczUyaTcwTTx3fmtnMnkp
bE1oOGF3ZjN0eVJzTXdpLQp6PkotbDxfSEt5OEVldkkxOyFCVlMmQiloYkFPRjhPRV49dyhwNH1p
Q3NkRHtpdkZrRllKNEhWbiFwSEwrXjYpPEcKem5BN1IxJDs5ajtTZ2VxYkoqSnojUlklb0Zwbmls
bENjbThEJHEkPld5I3lBWlBUfXwmM1RFODk8b2tvNUB6QGRBCnpjayU/YCsrLSQzPn10JjRINkU2
Q3FmajR6XzQrcF9Sd2B2Y2gtQVchQD9JTndlP2VLbkdINFF7aH5PWTMoTV8rYQp6ZGNOfG5pQCZf
UUpEJilxR0RoI0xCalE9bnZndFA+IURMSWojJnN8fG1YelBJPGYyfG9IdVcre3J3eFNadVNTT2sK
eiRMVC00PSZtfnZyNDZqe2hUaE56NjUofHByMlcmRy1kLTNsMnxYN0xFVVRzO0dpQU9HRnViQmFo
NSNNVCUpQFpCCnpVcnVZJDFSNSleOzllKmE/fldnd0ZCP29aKFd0VV9BRVgoQVVWNEFgWUxte24q
dGpBZGpDfSZ3d2E8eSZFfjtARQp6Pk5Ab3o7NHBlPzhsdXpXbjRLYStJJHZ8dXNCSnhLJS12dEM/
WkRZP2syYHNwWEhvZGYmYj5PQmBzWEMpNnpGQEEKemloO25KS0NfTTNARk1aejBpdTcheGxmWDNg
IXRZV21sI1p+KD9Ge3w5NyswQWNjcUR4YH4zJEJXVktGOWJUVCYlCnokaGw+ZWBkVlhTOXZxVGlu
Q29+XkowQkpnKWMpbExXVmJWa1Q/Yj51cFk5MUFuXl84ZzEqYD5pa3NqPCk0ZG1YRQp6cHI2cGwh
eiZVQm43SkU8dCRyXztFNHI0Pz0waEh2WXFnQWU9UXY7ZmIqZl9edyF7cVlxdjV2c0d3OW0wUT9k
U1IKej9OaExkaj4pa0ptSEB3MTxXKmBDRmB+ezRncFU1OGNoOzc/VXNwOUFhTE0wPUxpKngxVTJ5
JWQ/U0NuSXI3YUBmCnpDNWByMG15Uy1LejJZKTdte1dqbTgkJHI5SXhgUEAodGRxbzw1QUA3aEQx
d1VxRzV4cVI8Kj5mb0pfYVMpZ3Q/egp6czRjPyg3e2tnUk18fU4leEAjfCs7Wj5ZMzFHQCVCKHBx
aFVKLTczTFlNdCFsUHpCITl6QDdSd0FvMkFCRndoUlkKem9xcXA8OWAqU2IkaF5sJTdmSGxBVVJ9
dTU2V3VDQGxZYXVQdXIoN147PX0lJiRPU2BRP30yVWlNRXFuenBuRHZVCnpjKkNES3RFZ00tKj19
WEk8UFlfYGI9bnlZaWglLSVTXk9UdFVPdmtCOSs2KEFYbkFMfElzODUyTDZvPjNjKlY5KAp6bCNW
IzlNTGpzTll5UzBCVWdqV1ZZaS16elJVYXZJLVZ9OFI1Nm92MWFaKlYqbmBQNypgYG8jKD8hO2gm
LV8mMj8KeipeemYpQGNALT9AP3BHYnVRaVg5TXs/UlpZQW5EJXBJM15kNE94VD8tR0o1aWNjTGJI
RFhSNzhIbXBaciNnNnBICnpjY2tDaXRRNFVDdj4/Q1NzREM1bSR1KnM+a0ohd3goOT4hS14zO34l
PyEpMik/Q2p9QT94ajV2UGZGUzwyTE0/KQp6NH0tJWktQTBxRmdTeT03QHwjN340WT1qY2spaCV7
NGc9XmgxYz0/e15sMmxBX1hDIzRNYXRjaHZgNlk2NysoI3EKem1DfSQpWiEybmR3VjFxODMrR09x
RTBqQ2VXRClkc1ZqNDIzNEo/I2BveHlfZUp4N3xQcjdoOCtwV21kNmhuO2dYCnpkeXwpQCtGfjJB
Ujk4fl9DO3JEQWdeNyZPS1lLWXJxd15iPXJLRVA9MXByZUZzWD9Vait9OzhrZkB9KGpXUWNwZAp6
e2Z0Uj9kRUBIcEJVPXBob0dZUFE+OUVgVChvI3U3ZkNveEJMeiR9RHVleml4NGR9ZmE9RUplTTkw
VlRJJTM/WmoKenZmS2ZVbT05ZCkjQmwwTjVRQXx7bmYrK18ja25wfmoxSlc8SC1RJG43JDdoUE9a
dWg1LWFSaXVZcGtMfiR7bS1kCnp4cXIjSTU5JlIwdWJiUVNpUWl1XmFBR2o+JlF7T2JITTc7Y2xg
WisoVHtVPCRmT35fVDRPa19eYUBtV2NXTDd0YAp6UUdhSStLamZZb0A4OSR+UDFUQ0BrfkQrZ3Q9
a29NMH4xRGJuQmhGflR2Nyh2I0dATjd0akF1MXFtU3Q7SUNPJnIKejhIYC0hWipUbk93XzVYVnNh
cS0yZlpNJF85XyZpbj9Ee1ROT25ybnZPUjR9JEs1OVZMWlR8V1ZLRWo7UiNGQVZRCnoqI2NJJllA
PCR6cVE9JW5PKn59bz9Aa1oxOzxoJUZXQmY9bm04eThgWW0wdjdCY1MzMUk2NGthJEgkb2AodiVx
Vwp6VjhKKG91N3lsQFBKQFlEREJsMzxLbEQ1JGwrVCpqQzh1VmlvVUtnVnkzIUptNEcxcCF0RFFB
aCVoOG15YDt+eD8KekdTTUlxbUIrOE1kJD98NHNJWldBIXl3LXcoaTJuQj5PSDwkfER7NSZ3LSQr
KGghdk41WWFzSH16TWJMMGVfQ1laCno1RWU+N0M4Z2ZSXyZrJWRsIVh2bGhFMEd3N0VWNDVTc1RE
ej8yYSo3dn4kVyF1bD0pS0MxKWdZOSp8fV5rbGdxXwp6VHJCPVlIO1U0dHRrQ1p9I3twWT9wQXU1
bVMpZkEqZVEwVyRWVUY7d0Uqd2Z5YVV0RllGP082SjlffVRLVnd0fDcKelZEejxyITcxdmkmOXpT
anRMfH0yWnBwdyRuK0ZsUWdodXMmMmskdm9YOypXXj9HSUQoJTVLO3UldCl4OD16OEk9CnpDcC1i
T0VgUGFXdlZ7fUBKdHN5cHJjIVlRX287bWxWSWBkQ2JXN0IoJmVsTDhvZmx2Nm5idzliJCYkbnMh
UEtJYwp6ZzteYldYWWtSVCFNPTV1WGg9azt3TT50bGhJMGYhQmlhY15qMXA5ZzJtZC07bSl9RU0h
Mkp+OVlFY3A3Rz9ldn0Kejs+b1dTems0Km48NlooYVp1OEB2VjxDP2lLKjNqI2pJQDtxZzdhdFlV
dXtaUmpsekxFdkpWPlBldWFoUipFUWdPCnp1eHRuI0UpPEJmWnRKaEEjTjwjUFpROWphZ0wtRGw0
NmIqc3l8dmFyJkphZmt4UD1lU00rRHtvK3sySyREVT9Obgp6K0gjQzFSeVcjX14+OHYpSVE2azcj
SWZpJk4mb1REWkVyODZPcVlFUFVMVi1kP1d9ZGw1VDg8bWh3QCFoQ0F5JFoKenVQPkYjbWFiOFVS
VF5AZlojUjF3PUMkNEJtN1NeX3omWkVrdm0+ZFk3SzU1SmQ4MGFiYWRzeDRFendlQ0IxYnleCno7
a2RhSG4xWiNsJHgmQk17b1g7SCtEKnRIWCgyJCM/c3poKDtrRjBydW5pfX1jJk4rUDwxMDJgUS1Z
Tm9EPjx9KQp6Km1QTnFYYnwteThMND1pP0dOVjJHPXUkbXUrfnB9RTIybSMrPnoxaHtmUDJHVUsr
RDdvfCs9cUg/di1AbnMpcWYKemNmLURHc3FmLT9CRTRFbHAqJURiQjV3M3R5JndyKl5neUEzaVQ9
SmxhQWR9bnRCKEd7P20wUU1VKXhyVUFUK2RwCnptPmA3clBwd0J7I248RDgoZHFhanVtND9OeDU9
fG8oQ0tXQUReKTkpPURIQGZ0cU9ZeTBhP0lYKEk0UUR6Vj9FbQp6Z3ZlWlNaTEY9cC01Q1ltVEtB
fmQ8MD59JU5iNyNlTj1zV3x5OFMhZ2lwXj8lUS1FO3QjZ2wmTExOeWE1QkU9LXMKem9NPSVlN0Ak
RjlUTVg5fFpAeFpnQlotKnQqbGspRHlpfntVSlZjYmM4Qy1JTWlyUCZeVFJVTW0lOWlRMVhUUjE7
CnpkO3dJdXZzRnN9U2J4TlhoYzM5bCR1PlUkLUZtJmczNVZUQGIkKXJ2ZGBafk1XfmY1NHdqXjZW
UUl7KjxqKjFESgp6RFdAaFZyZjJ2clJEVjE/OTNuZio0SURgVmstKncreHAhMUp7LXtPeGNfZUJA
NCVwfTVqJFhDblpFOz84ejNzJiEKekJWOWtTPnhTXyFDOV9MYld+N1ZpdmRIV1VSPzAzKDVocyt3
WDtiSUkkRDd3ZnRgK0hpUG8oSUZKdWlXZHp1dHNeCnpufDZ5YkkqNiVAUUBiKzRtQDB3d3JoXnh+
TT9ybHElLSEzVG92R1paRFhgNDZFXnlIMnAxbUlDNmVpMD0rP1ZydAp6SzkpOGtXVSNAWkQ+aGV6
ck9vc2pJc2dEUj9fM3ZMb1Qtcz8zIyo/NVVVMFYjN3pMMSk9WUo9cHVRVXBtU3tOTmEKej1UM0hZ
e2B6UWxRQzlmeSlLfDZuX189ViN3bEUmemRgc29nI0leJEtGKyl7Zz5yUHVLUD9IPT5JfmxRaW0x
LU48CnpHdHxUSmo7RWs0Q1NReWVpcX04MkBzZkoyMD41dGozKUJ5XzBUYW0kS0AmcjNTQnJzZVoz
fGMtdlc0Y2dQNF5tUwp6MDxVPXA7aiVgKHMtKTZMZyk7TmRyNTc+c1l5OzA2d2xFRG5ucSNgNU9A
ODJaI0JGRklocFlWZE4wZXpAVngmaz0KemQ/REIpPkBATDV2SCR0UWx9cXlBdkBBTHdKYGNURVI2
TGVJdGxDPExxLXtQKUtTWD96NyhhWD1Le3M8RzEqdDtOCnowSHNtLVVCYHgwclJ2RUJQWS1MaUE7
Y2VsOGpKQXdpMHltU1BtdyskN0BzSFNAdz50Qy19Nkc0Zj1Ic3R7YzxjYwp6KiomU31WKWdNQUw2
PkxjSWFQUFgoSHY7OUhmRFpDbjA7blZeLSFZR1QwbDN5UUdxbWJaa3BAZytuJi1ZR1pYaEgKemNq
PGRAZkV8NFptVE1eNVh9eSV6cnFmYDdHUSRKOFh5VVE/TyYxSFozZipudDJ4bEola2BQQ35AdTNe
SSR2ejZBCnpZfGM2NzstTXhAVH01SUhUVGh0IzJ7Q0dCKVNLKUtLeVhWNTQmQiV9P3lGZj1qZThi
Wm1VR0tqPzBVRHNEezYzXwp6QGw/NWtzNjNmOShMZGUmX08kXlRqZHBrSUMjdyZ5P2FLJG45OU5P
MzAmLUpNKT9KK3w9Tms5LUxwamtHTSoza00Kel5JbXxrT3xJYzZWZXJQNFg+T1lQXz1TWX0pO0sy
ZVZOVTEkI0ZwO2JIe1leZlRAQUp1e05selM4XzAjTllsS1U5CnpsQ3Z1fmZOSHQ2YnloYWpRIyVK
Qks2LXNlKzI/IWZCNnZ1Z09OTClXT3U5MFc3UysoR2NSPXswY2JCajtWYXchRgp6and7RlpXUmlW
I1grc2coR3c9cmFsK3xGVlQ7IXp0RiRwSS10OT1gSDZCJD4oMXZWMVI+M2BxRkNhSDFWaD9nd3QK
eldAbnY7ZGxSbWBYWHNKRk5eaX0/bUZFZ3E9a0MjcyFwKlN7UVZNTVBUdVllZ29FUCt9eiQ7Oyll
NDJgdStlV3loCnpuWnlDcVE+ej5JPSU8NDh2K2FTOSkkc00pXj1aU3dJLWNIbVNxRlFRKztIbylK
IypKYEBDVXwmSGs3Z0hQLV5HSQp6dl45XnZxRlJnbGUwey1CWWQ3diVRN3VSb1dzQS1eUFY0KmZF
Qmd9RShCPzZeO1FBTzhROTFGUCZPT0NaeiYlNm8KelUyTD0oa0dvJiZpN0lQUHpKYXV6PThuZVd7
eWRkfGlCc3RgKHVgd0NzTUdTOEVeVCZiPjMzfGl4P3BkYk45bSQrCnpgPmc5TyYwTVpDamItd2xA
b0NlfSFtYGRYLVkpMFh5Y21TcVlkZ3FJUVV4SlNXfi1CWXghSU5zQEc/P0ZASWx8Ygp6VX5hQ3Az
bz0yb3ojN1gxdWNAUyZDS1VMem99UEg2JWxMfT8zbm92c3pEfFU3I3U0Mm40Tj9RTDVDeiE8dGo2
dSYKejkmSmdfY2Q+TW5hNVcrIz8zbXVVK3lfbm80OXlxZTFKdmIhbnRfTl8wb2c2dlhkUG9hXzhs
Pll2VXlpQjsmTiRiCnpHX0JtKzVSczB0anxHbl9pc0BNdih+QyhqdGAmT3VtMXhSXmx5PkkxNV5B
ZHxFZGp0Q3FTbDQ5eytyVm5QISR3VAp6M3FRfUBkdXIlfCF1fHk1YXYwVnsqQjloK2k+bXApaEVr
JjZpUTU/UVJ0PCRXYjgpMmJKVk0wT3MwMXx7dD1uTnsKem5JMGxUdiE4OUpVKEcrPD9KN1UrUk8w
UHZqV1psRnQqcCVqT1koaENCfU9QZUx9NTA5bj5ITWp5JnxCZGx9ODRKCno1Wjd0O2hXdDlQK1Z3
XiNqLX1sQ2wwZk0oKXRYZ1hqcD17PG1fcG44YXhZcjBBVUBXPjJrUkFScz4mYUlJPj0mZgp6ZV4m
ezFXaj58SFBLVTNDXzM1MmMjY0U9NT5DVDF1JC1ibmNZKlhMREpXYFhkSG9GTUMlb08mcj5fKEBE
SEZeamEKelFjIVQyRmoqWntBV1ooMm4zSm05NFQ5ZmB5WkFGJGI7PUJpMkZkbjEkR25HQUBrWCRM
KEAxbyN1blc2el9VeU0+CnotfjQ7ZSt2dWFlRTQ2KDQ8PCZQJVd0V1NwI34kO3FISUNpejMmM0Vp
enJJbXdKNWpSdCNNP2pxYDwyJTctOUlQKQp6cTRifEd5O1A2dndMNl89bXotdzlxKzVReFdPcX5K
Un1XSCpLdmMjUFd3OFkyRz9QeWA7ZT9HWDhMMGB3IWU0KlUKelE5Nyt0SGZPbXdqUWZ8JCtaQk87
Q0YpTSZiUFpRQzVaJU40dj5lST8lNFQoVy1DcD0xbmVUaVlkaUNMPko/dDhoCnp8NWU2QUl+OCpj
bVZUVV90RTAqYVMlRFg3QjttWmVUNSVWVDw8S2lFKmZAViNweEAkTmg+TjFQNEJzTEhkUXxqSAp6
KE1FOXtmMjVEOGVkYkQ5OE9jM3liVn5KY0t8c0pvS1VOJiotN0o5JXM9R1ohbXk/Y2Y/UGdgUlVO
Un0pVVM2QXoKekk4KEpEaXVzSm1CYmlVdW18JHhWU3V0WmJgaCohREtzPFJeIW50QVgpZSp1JUBM
MDF8QE1gbG5eNnE5b0psWVY2CnpjcU5uTjIyV31YKGVHK3ZOOW0pYDtsTGNjdCZeZjxkfUZ7amBM
KzI/PF5ibGQjKm1SbF8pMDR5KVR7PSp2ZCt7Ugp6dDJ1PlN4K1U1dzE2eVJOaH5KXzV4T3drUUZV
Rj1LMTlLfTVeRjFrNztxVnBJVjhQdFJfX2dgMnpNM0plK2wqJjEKejwyTmRQd0hDUUc5UlkqeGEm
fHk8cmBuTWE5QWYzRVZZSUwzZWNlNUlDJGs/Mk1NV3xUOH0qZmFYXnYoIUtJZ2BoCnp3UWk0Ujx9
SDxzVVllKUpWNCE9WVlgRkd7YzVgeD8mXitLUExmPDVLeD9NSz1BIWN9O19BJExxTyomOUtAd082
eQp6NEQ7YE55c3FzJEdAMChHZ3o3KUMwbEI5V1VSTEo5Uip9ZmRLVmJXNTtabiplZzI/LTRkJjB4
djByYWgkdjktZEUKenoyNmRYKkdgUFNzWUtZRGpyVWRNWVd0YmlGc1g0JSZpJj11PDBzOD5RZlEj
eWxBXihIbj43RUZYWCs/X2BBV3RvCnpnSFU7VGYjSSRxemRsTUdhPz9ASjljXkpTQDl2c3RRRnpm
Y0c/ZXJidi15JWF7TyshRzklKzVpRXwyOFRVRj9keAp6c0UjX1JiYkYjITRgcGdyUUMqPjBWaXh3
WXdpMk5iUil5fkdpM0A0WD0+YGlhbiFfQEtyfDdkKzE/ISstZklvQmMKekZ3KCZEbklyI1MyWTQz
YHdMZ0g3MHpHe1YtP3V8Zy1AJGIrXm1Hak44VDluYXphYW9acFhkTWlYRl8weD0oR1JXCno1UTQp
JHV6e0BiUG8lKEJfK1JBVTgtV0txUzFIOXo4Tn1NaGVGfj1mUnh2WDZ3dz10XkQyZmh5c0QhLX5w
dEw0cQp6dylrZUJpcDl8X2stXkt0IXNHViMzVmxeQ2p3ZkJyQmE7RHZIVTkpKGJRb1ZDaCUkekt7
YCE1N0Q4eFJHKVpudz0Kend+cF9vd21JfTFPeGVFZVY3YXZSXnNzPyVpZVJ8UkohS1Ioblp+QnpU
JSpEVDZRYnw1aU5YRWF4QmRPP05TUlNnCnpgUCtWJmFWfGtwWVNYNWVzN3FZd3Y/MH1FUzxEVWBy
RmVXZStpMG1GYXpqUChZZGpZLVImfjdpVDFpSkVtZWFaNAp6aTJnQEdNKXFWR0IyRjEkaVhvMWgx
K1A1YXQ5U0dMa0BeUDQmfTFeMFVeV0d9ZWNEbmFyMEVnZ0gzWlRLXms+dG4KekxmVGZGMSRYe29u
JGdVKDZYOWt+ODhGMGk5R3FYSjNvcXJLTjdGd3x1Z3xBJUg5bn4tNUF2eyhedjFMUG53UUhqCnpE
KU5uPW1OQSs2PSgxakNpeWRYX2JUPGtuUWUtMlNjUjUjaCpecjA2SH1tbnxFdnFjPGRaJSpUKHx2
R2cydURDNwp6JkM3anJOfGs8bXpVQFl0S0F1PUdCail3Y3ElRGBwIVZ5aTJZfjlGfXlgcmt0K0FA
VUVhTzZWeksxRX1YYytVbDIKel9HKV5mTHgtUCg+Mld5KyU4JSR3IWcoXlF0aGppQndlM0xpbil+
PWQ2YllyU014KyQ5P1FISUgqNlNZfHN+Wmp5Cno5Zi1EJFNJK1hJMU8+UjYySGhPNEg2c1MwMH4/
b3klKkV8M3FnOTNLYH1nelo0U1lpITVaPUR8XzhHfTl0UjZCUQp6SE0zTHE+WldFRnIkaCRsNDRl
TjR1e15hYWpuS0FPSXtuNDItT1ReKUlkSXkwSEFyNm4pdjNAPnpPWVN9VWArN2EKeldhe09KPzh3
WVdWVyhTeXVERmZXUHNUN3g0TkJgSmI+PllXeDNnViVVWWtRfS1FK09VU28qVyRDYWd2NVkyZ1Qh
CnpIbX4+RXhsKTY/eXx4fTArbGNBT1dLfV9MWmEyYzBVJm9yUXgwZ0pfWnc/K25TWVRXT1QkP3VZ
JTBmT2M5RStXMQp6diQlRHF1XmF8TEZfV0xgRUxeckU3IXhKUTxrXzthTU0tWTU+fjFXcHlLe1NN
aj1+OSFZTDFyRlpjYU52dUZ8bFgKejZsRHYlbjZKfkV0MFRCTDE+KVImQkk2KkR2UW1QWHh2I1Aq
M0pEOWRAYXd1U2klM09iPko2TC1zfCQ5UyM7NEZaCno7cDxWdmh3QVk8Uk05cVBteHpEPjAhbFk2
T2lxR3REZTJQZnR0TnFZJElOaz8+e0AoQ3RHZTlNRFQkO3RTc1I3egp6RS0wZnV3ZXw2dT9NVHZu
Wi17c0ZWPCk9XklYTGg2ekM0QGtONmRjUilUVXdmTG1Cej4xNCFjfEhocHdAQ1E7bU8KejlybFBx
IUI5IStMT1JQKktzTiN8SnlRO3MwQVlVMVF9MlpSTSgofCNWazBnZElhS084elFrNkVvTz08O20x
WW8/CnohQHtRSz1qUGc5RTEqTV9SRSllayt7KXpqZUMmI2ZiQSotUjFhO2ZLcH4+fXpCflg/fCVn
TXJKPXx0VVBVdVBlTQp6Tkt2RXlfN3hBP21XNWtlamcjPiZ6RTtNR0t6T3pQKEhLYCZSSjBJKnhj
VUNTRU4+KUd3UDZFSm97S3xOJWA3XjkKel5QI2lSK0dodERuYl9EXipEYFk4Yy1gPkkkIW4hXjVp
YDhzU0VqSztYPW5ybnFMUWYodXJFRXg0I3VDN1QrM0tKCnpzRTwjfk9wRyVsSXRFSUlKQ243Pyom
OXFJdiRWZGJ4VHQ3I1A/dzt0QXt2Zm96Q1lrX0FzfUZoUnw3NUZhamt6Rwp6ZFNgajZ3d3xBaXg+
Nlh6MzhnelZ0dFl3Z3NsQGAqKCRYM290S0hre3ImPkV4eFFKVSNzamlXfEE1NkJZYHM/RWAKejBP
ZihNMCRDTnxvaFdsJj4lUFBLI3xXYko/cGFLb2M/eEJJKXFrU1NWNlU4WiREaWwrVnp+cVg2UCgz
bkJffTdkCno4ZmUzcll3MlImNnwwSEVXPW1waDw/NXAoVERVIXMhMGtGek14RldNdSEzfSRwTm9+
MW00SzxCS2orKypmaW1McQp6dk09Z0lqPVpyO0d0WG5jRWlLaV9KcztaPC1ydip4YlQydyZFMSRi
KT1FS1V5YkMtclA8MUhuM2I+N35KREJVQyUKenVQISg+N09eOEtRQ3E9JSNxTD4mWmQoZnRUZV8z
a0g4bzRNXlVNdEZwa2BTfCNjWmNRcV8/Ji1aZ2ZBMiVMcWVtCnp1QzA2b1FiZ1p9VSFWVWFJPDMr
dHpxJmZLWT98NFZGPGNeeUdMa3IrTkdmRiU1bCs9bGlUNEotNlV2Ri1vI00lTAp6Yi1LRj1va2FU
RnpDMnJBVGduIT01TU9valg/PnR+bipaI3w+NkxjWEUzUkFQI1FTeDFuPVpqQz5MeSR8Rkw8X3wK
emsoM2VHYmVtJClsNVhHXkVKOStxTG5HWjgwdG98cF5INXFEIXFJYW5sYFY0bz4/MjN5K0RLJH5j
ZWlVOWFPQ01iCnpRX2JrQ1gpXlFecElhK2BNRzd8QSphYGx5Y1V6cDIkYmQhPDdvYSV9cUN+WV95
VnF6aEp2QztaQl9nUk49JCFzZwp6UnVGK2V1bl43RHlqbmxWZDlVbnhBXyROREtZPj9tMl5OKStm
ZVlGQ2t0UEVFMjghJGohck8rX2EkYVRxUHViP30KeigwPH08ZjZpN3tXbHdkTGUrTGtgZWBzPGoq
UlElSmtQMn0hbz9FWiRMfGpOVCFIazkxWlhSJioxXzQhQVQrKWYoCnpXO1dKLUVeJTYkTzl2fUZg
dzFkWTQ+RDZYR3BBNTlob29qQSpfaEB7Uzs/LWkjemhTRyt1Sik9LU12KXluIXJOXwp6SUBtTVBC
Ul5xdGtmaEE4Z0BKKmdxNVFfaU15R1h2YHNSRFo1bkwtVSt1YylqITBtTnpOSmJ9eXVgMTMwQnpw
QmsKemt7VjV7dkFxMUwxc2BxPWBZOFQpQyYxYThUPSQlfnhIdldIej9GUHZZSG1EZFI7bHJBeit7
OFRrYGtxSDhwckMlCnpZSjNYP2czUSQmQlVESDU3d0E5d2BIKWBMKXROJTZMU0o3JE02fiZoc3Ru
WmBvejBJNztHU2NGWCZlQXxsRHgpaQp6MCZlXklGM2Mpe1pSNEZFO009VGArO31uMXgmcTlpTXVx
JTxYRWZAbFRFfmcrNF98ZTNvUH19e2tyODRXWFVUYWgKemNRWnBlRlFzOGRVQVR9IU5lM0JnRzFN
UXhVcVo5b3ZLP01vRygpMy1ZaVg9P0FlYH1xIThMZHpiQzt0LTxZbn5KCno4d3lkTD0mZjdWdTlk
aEFtWHJnQ2d0T2huO1owajVldElHODl+O0VwVyRuNyR3PGo0QTRsYTBuaTlETzI5YDl3PAp6e304
MFRBQXZBa2tTI3R4KGRuNCspVS1eQVBzRThvak1wRERQU0o1cSZtYWMjdXM0ZHlrZylWJmh0QXJ2
dFltNEcKemgjeEtNUiRBI3N0ViMzREluVTlOaEV1endXIWhnUTxPY3Q+TjBYXzkhUTxuTUttUytG
I0BnRTJCNHwpXi1MSmRjCnpRPGk0N3lfeip+eFczVClOPmtfKGRFRjFYTntFUHVIb3cwX2JJdiFh
SWxzTzI2TTVHaWxHY3JlVnskSVcyelNabgp6bCsqTDZIaWN6bkcqc3pFV3k5PWFPVlJ5ZFpUSXF7
SUM/bW1KUz1vbyo8ZihGTHZKJHpZbFlBRUgmZ3VqUDk7SmsKekBKZUpyTE4zQiNDI0k5RVdySTZn
QHprJHBCQChYMU5KKThUdmFUSFR6UGlqPTx1M3M5SEBsVHd1UllxfFZgOzx7Cnp2cnA9PUJxc088
R2plNjY5KjtAdSN4dTU/R0p9VFgpM0RvX2EoNEApPEdua1J5KkpQNHRycSVPQnQzWD9EOEk1Mgp6
OH1Fc19WYVBJTFkma2VzdlkqbUpJXlVAQGZhJmlfdF99X2glR1RDM0FiLThwSDxhbHJQbUpxY3st
b01CR0xsKz8KekF+T3M1PzgtWVVlXnBpYWJDI0Jyb2BMISReTzNjM1Q4b1RBcUdVQHswN1Uza0Yh
QzgpXiR1VExZM3VMcD9IeHlmCnpsal5BLTtHMUFEc25tQ1dzWGhsUUw3KUZDSFhEazY2YW1fY29M
a2woN3srQz44RCskV2A7X35oKVByLTA9dl5wIwp6Mzxlaz94fXJoeSo7ZW1QYk0hPSQ1d1o4VEU+
eldYNm1NPDVVc0ZYbUU8MFBOKDNFMXZaOH5XYXtMWVdvZEZlb1cKemhiMiskOV5wP0JgRXxWWDxQ
fHcocmRwaj5Cd1p6aUIxPm9wMFY2ez9pYSh7fURINT1BXnBGVUleOzY1RV9qZW9tCnpiUGYlQENU
PHBMTWF7al95NThfYzQqSzJzOFRoemZEcWBTZVpreis3aU5NPmEkVXw1TmlacT9fRGwwNDdTUUIh
Tgp6aipofmRsKlNgdlFMflQySCt0MTsoTERxa2w4dj1XN0VVfW05ejVKZz5CMTI9OFhAa1lLNXpY
PSpqJiVaTkthM3YKem84Y1N8MV44Y19qJjZOdzg1eWFROEZta2ZuS1NWKXpzdj1sYlY0TVFNWTFq
TjtQaVNEaG01RHltaTEmdG9PaiNtCnpJSDFTTlNITzxiRmtEbGpOWGZGaDdMRHYmOF9ySkE5NEA2
VSlecUdnNEdSWX5eTWdEKkVqQTB8KGZvQUg5RTBJIwp6MXBQUXY8QkgmYG1GTDVYbWY7czJFUU04
MTUxWDdlISpSTTJ7ZjFgcCN7O1Etdno9alBsQ3tKRnBUKlIyQXYyV1cKekt6alBVZ31MNj1tKWxa
T2QoVDR1VWpTay1tNXQ/PDdfcExjQCF0NyVyaU8hcWdVKU45JF8/Ki0/TFNgQSRSMloyCno2aldx
fUZVLXB1ZFI7ZD9uS2s7Yztnbl9sRyVLekNQU2tNZm9AdEY0ZFN3c3daRiE4UU98cClBeTBnKT9G
Pyo7Qwp6Tmc1YSFuNWpsKkNtbHEtWmVPWS0pXiRwdmY8OzdAY1ZkQ3BTUT19bHI9RUtlKyZpNCNy
Oy1lcS1uPSVmVFcxPUQKekxKNzd6TERxPCNjKlIrUTZrUHJzKG1LISZlbFF0alRONX09Vnh1S0w0
QWFDPipHaW5UNUBNZHhyd3dBQjh0V2Z1CnpScTczT2FZRShmIyR+MjxHTTFUWj58eCNFaVJESzZY
NX4xcUJjOyhDZ1hme0hJNjVZJnJFT1NTR2FubmRXI15xdAp6V0BRWSFYSz0rK25fNXhKX2RyU1gp
fl4ocjA3c2U1RGgjPDYpdElDNTU/Rm5iPWZ2JXFhKnFkNT8hTzVUX0xaeV8KekMqblBpVFhnaz1e
RzVTJGVIczYqKUx1YEw4bCpELTZqb3g9ZjcjdD5TZHtAMD1pKHpYaHtmaUQ0ITgkPFMqKCYoCnoj
JTlJQzZrZHJJc0AhfV8jSFQmUT5iQkQjQE9hZ0psdTVxaXcrfk8me1RsUTQrWTR6SlYoIVV+emAl
KTJPRn5OcQp6dVRORXpgM1dTMCYpKlFBRzN+cEJAOFNkSj5VPnRMV0o0TkRpOzZuRDw9b1MpUnEk
SHc4PUVRaCU8JHo7KCE2LT8Kel9BZF5XdmpiaD9HOE9OVWtEcHhHT1ZvYVFUN3l5Syt7ZjIwKXUo
YXZ0dFdPQyUjbHBvZFRtLTUpMzApWT5LTmBuCnpLYj1Pb2ApaEteXihKQGRsMTZHQnshIXJid2dD
VVk5dVF+c29rRHdVWjV2WEdxJkghSG9RI1EqSlErbilPbTZYNQp6N1ZKMkI/T3Fua3pLclBFOFlg
YT9sVlQybig9ekdae29TbUpDdkdXdFJ1QTwrYW45WUxqYy1+VyZWS3dSV2AtbDsKelB+Uk1CJHU8
eGlEMGNHaGRldVR3R2NYe0spUnZUJUBOYD1nOXp9WUk/QTlYJmxnVlRqISpZOUc1d1lAMDV4QDNR
CnpAbDtlflBpak8mazIoSi1ENCQkd0lTO3d+YntyNV4+SmZaRyViUDA5Rjk+R1NGcE95dHNLeytk
YHhUN1YrYXRnKQp6ZEoqaW1mVWRQT1BeVXhNXzJMN1loIVZQQD5FfVB9NWM0eWNWWEZpRnFqbDxn
NTl4TnI2TjltYTxpSCpmKyV9e3EKenh+VTFeVXdObjRaPllxYzxTKmY0KUAyazxoczVLQi1GUSYh
OzxBZGJvKFB7eWFHIWwpOWhJYWVLVlc8ZTZTMVhtCnpuKlREZmFfKz9rO2g/SDRtdW9FejVSSFp9
eXphZ1dVXkYzWVA2TyltX1pfV0Q+QlNGIXtQP0RgSGZuMSNGU0p3ZAp6VUNyZ2ZuS3NNWDwzPHde
d3lqVDw2SyQtTzY3fS00bFkzUklYQlRMMGlBdz1BZGFyMkVrQ0dqfW0mRmFyQDs7ZFkKejwpQ1I8
bTdHIUJNRDYkfj4hJiQ/V1NRWjdLNkU3RUd0cE4lXlhiZGUmTCoxKFl3eTI0T0BITTklb0pmNHg8
a1RwCnpJVW9xfkUqRS1yeXJkI2RHY0gqPkw9TFV8OXlFUSQyP2RjNFZNeTUxKCp1RlVoIUpLUm42
dVJuNXU1TWtmTEhnSgp6IUR3OW9EbFI5SXVIc1RxVTJVKmVgVERhSXE9fCo2dFVfZ3tYdTIofl5P
O1F8Y0tmJlIoSGE3OVdJbTB2JjB0NkUKei0tNnQkRyRGfFpRb0okWkstSn4qdyo5X30mcjxBN3FF
ZEpZTXVBPGNuJUJJeHR7YFY2TE0qbXQ5LVM5ej4mTWh+CnpgNkRhSz5+IUdiK24xTkFFJTc+fDEk
P2t7QiFGb2A/T3Z3JGB7aHNKKGA8PmdwJl9SMGJCeXVAUD1XJHlQU2p8fQp6VGRkelEzPCN2WWQw
flpKPn1+VnZ1QiNwYCQ2QXdTbT8jWEQ/YytqPD9NS2hWKWtoYFIxNCFLY18jQT9tS2t5RWcKek53
WChLNXtHMjxxODJ+WnRfQmQob1E8fkx2ZGVvQzw0aVQ9dk1kbl89fChkI01tPnZUPDlUd2ZCJW9M
RF9IVlYkCnptNE58YzxCKnNtRXxIUlImPF55czR8fl95VzxibTYzRTI1X0xCSyRYPGZpJEB1MDZD
Z09RVEstdVVtfnVDZjskYQp6QXk/MUY+b3lwZFE4eFAyWSl+a0MpN0VgMWhaa1dxOFNMMyh2RERT
RChyME55R1V1PUwzJnExdCYoX3pgJTFiVU4KelJMV2pqUmB6Q0hVOCYhLShpPkBJdHxFVHZiazVl
enVvRm89bllmLT42WlV7IWVVRE1WdHF4Z0M9M3BxanFFXzlCCnp6K358MTxXcHcmREdqQTs4SFNR
c24zdkA5MUwzRHd5LUlJKGFfTElFSFkmWiswaWxZaTduYy0qWkxjWE1xQn52Twp6PTByJj8kVmd1
b0B9VFIjP0VnX1QtQ1pkdkY3OTRfcDwwMXUjcHdzb3xBLV5wUmEqcyZ4SnVxOzZORShmNFMhfFYK
eiZGa2x0Z0t1MzxkaEpUcU4kUk5Gcms5a0tfSXh+SSklT2VJNTVPcTVOOWgmZ0NkSXxZKiFKYWI9
S0JqWXBqfjdUCno5VjQqTnZSUGV3bXx3TkVOJlgjSUBTQDQkelZ2PHZrZjAzPmpjfHlnO0Qybys2
K3prfFNWeW8mYzVkfEhXM3ZrWQp6cG48M0hrcmFeN1FNbUUydXJReWMmQ3JQKHl0S3gkYEpzYDNh
V1o7KjlsLV5+Zks8ZlVvbHBSZVFxa0Y7eldFNWcKejZ7YCp9QzxHNkBQaHN9diNwaEw1U0NoI2dB
eFNtREtXYzxKOXtiKDs0RD1XOWBSQSR1SHA0JStFM2dePHh1SnMxCmZAUEU7em9SfURTT3p2ViVU
dWR7aHh5P0M7cEcoaHJ7UHpDPExESXM7CgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1n
aXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfaWNvbi5wbmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlw
c2VfaWNvbi5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uYTEzNWM1NGUxNDllYWE5MGI2MTBhNjljOGY5YmY2ZGVi
MDZjMGU2NwpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTU4MjUKemNtWDlfV21zRUgoKz0ocU1U
QCg7eUY+OSgrQCpNTjRVaXgkNCNuTEk2ZmZAWCNpNipueUljNzN5eCpUQkMpYnxjCnoqX25IMFhH
YkQ1KUQkcEtObCphKjBFVXZIdFFHKE8xTntqREt0X2FxOE0qIWIzSUs/dURhbEd7YCgmTVVfK31Y
Xgp6Xz9FbkQmazE+LTdgSXVDcSE1bG93WFkyR0JkIXB3SVAjbUY2NGZFI0I2NWQxO2ltbjtBZCYl
ZENhUW52ckdARUAKenFlYlRsbF5ueVI8VDhzVWJjfC1KUEdCMnBWPVptQ15MdWJGVGk+OEtTVCpf
ZXQjYS03OUMmaGRVe0paeldhdXJsCno7b05hSVp8RUV9dn4lU25OKipfflZATEgqTUl5KmY5d3ZO
UE1GTU0qT3R1dXFtLWhfZUEzaD53OTx+JSt1SEZ1eAp6UHt3MSg0Y1FtbyFpRDdVQEkzcjdsJmIw
JGQlJHNWPH5KPlk0Z1dnb0MreVk3M3UmVXplPHlkPyE7Vlh9Ylp3cHwKel5NNmRMUGl6QHlKVXsx
X1NGaUJJU1VKa35QRTEqSTZFOTNwPDVjUmA2KGohWlJVc08zNl4mb3o4KTt6dFp5cnUwCno0RCQo
T0RjT0glSVAzaTkwenApPCtsPzBpQ3gmUj4tc2pmSnowUV5jbHZ9akxzfC1xNiVYTF5qP0olQyN4
fkA4OQp6KkdET2FEPjg8c3g5RCFDUzI4QmFsYDFrMzVMWlVoQk9+QHdrYDM/a2JoSnBYJXVEQkF6
Vj8xYyVXMXh4aTR5NEEKelZ7PX5tNyVEWH49eWg3bmAzb21sJVUmKDUkNTg7X2k2PkIrKzJTakV0
TCVgfkBIODJDVH57dHAwbEtBbzN3UyVnCnojS08hckY0ZmpteGJwKiY0SmBAfDNpVStEJGpXfk1B
UD13ZCppVUxvPUY4KmZDeX0oKzYtXnRNMlpKZSprJEtXQgp6I0IqMnZQMHV9UE90JEJFbVEpSnVS
SCtCdkN1WWBqNXhDT3l7QkErbi1LUyt2WWFtPjg8TzJeWFVJM0RHMVclVVYKejU1KytCX29YRVE5
bVVRRUlpSGpWdyR0WWYqem58VjxfKE4/VnNyKCtEK2hrX1MySnR1KVJ7Y31NWVVgLWZyVlV2Cnoh
d2E0I3V8eml+TipNaW07JmdUdkgpaEVEOSpkX2d4SFNaTkAmPnUqXjB6WG9RTVIxKCo2fWoldDtr
T00pVWlzawp6cnwhN3RMUk57ci07UUhYeWQ3NXtLZW8yRV9+emB0JFozWXd2RSNJOXNXSXtLRUFn
ekRCJGwpZ0lpUmMyYXY/YkoKem5pS3NULSM8SihfNGs8R3Jqcm5VRktCcHdFLWAoYjRKKF9vLT83
MXs4JDxwWXI4a0lURHFETDJUeklLa3tTKX1zCnpfVlJHclFmdEl+VkJmJjNicDIoQ2l7ezFBN21f
bkN1U2tQeyEpM3Q0b3pEN25GWVZNNWpMPytoYzBJRTNjPlZ0SAp6QWZjbD9IIzs7KkxYKEM4WWFn
bCp1REVhUHtRaD5yfDg0T1coa1RYSFhIRmdNY05OdlNfNH1HekhzbWZqbUBiNzQKenpsKDxPZmk+
O25CdkdnR2BLMjBrTGg9NUVYJH4xaHpVblJBZiohLW5Ea3BkSDtIaVVqIXxseTdQN0k+Wj02eDNF
CnpUQl9ZRSNHdVNsTFBXUkA2bV5lP3crbyYoWGxROFFhXylKM25hXj9eZTFBUndKPyhxNT5+WWk1
YjZRNjlyc0pqewp6V153JmM0fHZAbmRfNS1naFF3dkJHP3xKU3YySkpLUldAdVkwTSpeTXZmT1Bl
SiVLPXhzOG5gSCskV0JmK3U3V3cKem81Xj4yVzk2KVArZjdeMj8mMDRZKVcqJn1jUEEzQngzbFZS
UzV3XylSSSElUjF8a1ZoQGs2cn1mKEkzLSE1V15QCnotZH1XYnsjPHxCY3BRbT9SNEEwZmU1RTgy
JXN9TWlKX2crZVA7e1FeZFA5eW15dzRZWHleNkc/PzV2WnVBfSghMgp6Knx4NyNYaUIkYmB5PXJa
Q2xCPU5lV3BWUVAySH0tLWR+KnwkTlVhKS0qe2M+KFlwYVV2YzA0eEZGKWVHMXpPQXcKekF3NDZ4
JT9wKGArYElkJG1zM3YmKzBecUp1ZFVzRVJ1a0ooP3xTUklmVFV8TlFfcWNnTkNYdmZQMG9ZZ28r
ZCRvCnpXNjJ5SHVmUkMqK2U0ZkMpMXklbyFPRGk3c0V5ZkgjPnhpUSZGQU41WlkrdTBPUGVhY2st
ZXI+d14yNDAjZVJ2aQp6PWQ1cDYjTkYkISk5Tk4zQyFwN1pnKGx8PEZ9X0dAaURSSlgzdn1JNzZy
UWdtR2p5Y1lLNmZrfHR+WjM9SXRrTykKejcwcmFAZW04S1BpI2RaOUpSakVHRkxiPnhtaVo8bF53
IWMmZlRCNDhGNTRBNCVkQzMhRXxiZXFeUE1qJj9+aXZOCnpfanhyI0g4V3YhTnRuT3pMQkpLI2ph
TzZoKktzKHwlRWtzXlo8PWlHJmB2ciZQRUJ9UGpfPUt9T3x7czIhMjV5Nwp6IyZickBqLTVWTG5t
d0ViN2AxT3wmRjJpYDAoMSVTMWNgQlNnNjlxSlpGNHN0ZEB4bShjWTduO1RnJSVGQ3hqbT0KekJw
PyU1b2UjUjJfXktAXkQlSl43Rnc1fFI5WT1ReVVDd0s3QyFNQGd4IzFLWGZwR19VTih9fGNeV1hB
NztJTWhJCnoqSGklJFZCYnAhckF6ZE1ubiVBJTVzYTs2YmlmSVFiS3BXTjY4WkI8UGYlYjxPd0tX
PVpedz9WbzxFfX0yPEJuKQp6P0Y5MTdDZVZJbEpWLVJrJF9vaFQ/TDVmNzJ6KDI5c0M+RVo/Z3F+
K0tkJCthUHNTSjQmKWJgc05zX2wtXmwpX2oKekh2JiNzUmUjX1ZocVBOJlZDQCRTYUNZY2g+KmEj
P2BwcTRydnJ+b1M5KFY7NXtUd281RnVUeWk7NjlvQztRdit9Cno3alBgeXoyMns/UF9hUW5QPlEl
fT83aH0tK1NQUi0pM3k1Q2kmaWV6Wn1URlNXMCNqLVkwVlA1XnFTNUFJa01JQAp6X01HRjd7cDB3
azJ4WWprWSVoemMrbW07MDtCeyR2cDx1MUQtNDVFYlNrOTNvNipXSUh0YjRCIyF8VSNXX3VEbXcK
ei1Pe0NiSDlEQ1JhPXdiJERuQG5OSjxYKVZgfEk0QEAwezNJbFVNU3xUU35fNzVlMk9RVFRnNyZv
bSZ8VzUqRT59CnpXSWQ5QiY0X3QwNTdTdElrRl95eiZkO19qK0hROGYpbGgrY3QpRmt6V15SY2c2
JG0oMGhkaXBZQmRuXjFtRzFTcQp6I3R5bX5XXilLVjFkRXZaSykmPDl5VkF4OGlJR29FT1g3flJu
YnZHaXc9SnhfWGNoZ18qYnhjNGJfbmkhRWN0PkIKemV+d1dkYyY2WmV6VXVqZHpAfWstNUQ1WihM
NThVKSt1ZHRuQkhOfllpPzh9NjlBI3xDJCZvWlU3LT44fGNBM05fCno3dCtyI0ZNanVMbVYjQjZT
Kl4kK2tVWnwta2MhcUpXS1ZmTz5+OG4tYGBLclRtdyE9O0kmaGR1dnRlWTdRSHFaQAp6aDlLWFkm
MkJTc0cwMVRCMTVsSkZMYCEpRGBWNl94LVNEYWxDdiVlcEYtbipMVVE5dm4jP0ZnMWxASDBUX3pX
MGcKenVhXzVCVj8/T2QrbCpjIWpkentMWVp2fHhDKlRXTDxoNCp0ZXBwLUg+b0pNQCVSJm1LNF5m
Wjk4JDBQQVo3WWxQCnokaUJYWCNRRHEweTN1fFAzVyolVThVWEJtNm84IUgwbG5fQkZBX28/e1Rw
KEpjdGtrb2clK0FoRjYxdSFaJHpxUwp6UkJfMTB1KmpvZmM7KCt1aShAanlISkRSaDUxfnRRKlV4
SilDO016aUZvO3U5PnRvS3FWLTVtJXlJPEN5YSYqeWUKekE5NjEkQGN1VzlLZXxyc2BRPj9gXkNK
N2c3YTs8TU9rKUdkNX0rbktXPVlFNS1lJHlKN0BhZCtIenJDeCswUiZMCnorK3lfZz9GWXNNWnV9
dDN1YWBZWnNGMHNiYjBNIThveUtqfDtYNmNvcjJhbWxiK2B6XnY2bEN6Pmo0OSV7YFhOTwp6dUdw
STBGc1UjTl5RKWVkVmdmMTNkI3VYKFM2Znt9SmNnUSMpfXV2az1kbz1VZnJUXkFueXhRY3U9SVFZ
bjQpZmQKemhuMG1LVSZ6VnY5ckZtem4pdiZ7KXRGOV9ecWY2a3F3fnRXdSsxNF5sMighU0M/Mloh
JTtufis5cGNzNzE/WVd3CnpZYipiQUhYZ3tMZFdoI2BkUDBicG9aUkZsTmFENUlmTjFWSTZmNVZI
UjNJXypVMHRsXj5EYSFnRUo8ZkpQJVY5RQp6TjYwTm5yX3JGWXRSIWRrbTg2Skk7TnFZTGp8M2Rm
bX5iaTRXd1ZnO1gtODE0NC1ffVZ2IWJiNyR7NHY9PWwpUE0KenV9bjZpeWRMX1RKcH5ZZEo1cHg+
fEloITM+S291bT0jYCo9SytoLW12I2RnMUJoajB2K18hQ0pxUGJnZnRnT1J7CnpPeV5GMDd9NGs5
SzkxNF9gK1ZoUD49KSRqb3BlJmhxTk1XcTw4LThYdX1mVSYmfis5NXZNM2FFeFZOX2hjfUA2UAp6
NTYqbjMoKG9KTSZrPilWaClsdkdWdE50ZWFsT1lDSGdnSUpkTmVrQypqb3drNj9JMX5OQHw/djdV
Y0J0QXsjKVUKekFBd1YwSzZNN1l0VkVTMUFLVGxvSnpoZkw8LXE4YG1hT2J+KlZLN2VgOGBxMG1J
QlYhPmMjbmVheiVIcCgyckY3CnoyP2BqY0Imfm1pMjFDXnNrOVNIKDh4SkApdmRMaTdKbTwtKCM2
bV9iIz1aVihmUkNzPCMmPDNETlE7Z18/OyltYwp6anhAQEkrLTdffHNUTHo0X0VeXjhkO3laJUY7
Uj48M1dzTkVTWlhFeS0mWTR4dWRtYD1tU2VkJmBxNyg/Ui1PJDsKeiF0OGNPYnImLTkreUZ2RXN2
QGw7cTY3Yns0SUBkV1dXNj5tJTMhPTZ7VX49I2htWjRnNDljWDEofVFgKihzdHZyCno0YVVeTDto
Un05UylWeyphKTNmVTFCWWxYIz4jMUJVeilUJUpzWU19PUZ3bkUlR203eW90dH1wMERAd04zNl9j
Zgp6YFModzx7a25oJlkyMlEydEVMcD4zRT1gaz5jJFYyPXUkKXA8OW1uND1meCMkaUIoblghcGtD
dT1aQVRQbGArIWQKej5XMXRKezlgeytkaSR8d0hqTHdGM0skRUZEeihhVmg/ckF8bUAjPW9qalVY
M2UrQzc/K31+bnBSTyp4fWFHQ29FCnpEdHoqWk1PMD5AcXQtNSlFN0JDPlJ4WSlvQ0JqMmZ4aihZ
clZMYmw4a2FzQnB1ISt7Wl9gLX1hTzZQaiNteExeaQp6RVE5KFRtVndNJmJUcE5IdWkxSzNGbVE+
aEJDUUxJJjtwQ2I8TGsjUWJQYXB3bWl9OS0kZUB5MmdTbj19JFNUal4KelNHQTVjWFczYEdQYXBI
RTI8WHZBWjBiRE5eO0h5eGwmcEEmUyVaLVU0O1ZqdVREQDYkWCtGc1RCS0w3LW9BNmZRCnpnRjQx
QWxXLVhwMTx6c0tCPChIfnFJdGpge1doYnxjVDA9UT5ePUZmc0dISUcqaCV4MCh2RUMlZWpoY2Jy
cT9IcQp6Nzs9Vj5jWFp0NUJnKnlhdTY8KGRGMEF3JENHKmVDbiZJRXooOGIlNVJZZS16NUFGI1Vu
ezV+fSE9OUo0JGdCKmwKeilBOXtzVEkqeWRhN0R0UiR2RGUjbzJEfX5OVHU9MnFLaD5jcilLOT0p
eDhESzRraXk0X2VQb0slRipaaz8kU29kCnpvN1dIOFgzSH0kXlQ5aEtAYE88JHlPTWNWbnw2dCND
NlNPZ2JERzJkRFF5eXtwWVZFUT5LQEJXbDRlTmA/PSVgQAp6Tj9UWU9LKE5Va3wxPkVZNntUan1j
T3swVmhpISF0WD87bGchelJ+ZT0tejN5Xjl8dkE8cTA8S3s+O3F5b3hPMmsKel5qYCUrTyYqX1o7
PX5Ab0c3JmxxJXVlRj44MkoyZnZqSDUxbCl2NDh3JihsSjNPRihZQipyNC1WNmF3WSN2fGckCno0
UTlSNHc/UzslODJPT3ZoKDJPVHgraylnPjZIfnl3T2NSPjI0eXNMT2sjS0QhP1lZcmpGdnt9TGgx
YThocXVSTgp6IW1RZDMwWX5mNClORUomQUA0fkItTzlkTHZDSEF2ezxpeCt6TFZfVlItVnpKez9L
MnNIeFp2SVFDVGFSRFUhczwKektpS2VneTtXVEYwMi0+Ny0tYD9kPUpON1BsdGYmU0JSWChkJFBJ
ITheMVJufGA2JFFAUkYoK2BMRihrPlYofFNmCnpvWTRnK3k0VW8pO0RtNC1zJDJKIyFqTmVhb1A1
M1YlYEQzfnVGKTMxdm5iIVFEQVYyeU9QIXlrXkFVfT0xPn1aZAp6cShvbT0lcHwlRjE1JEYmZVI0
IytvVURPRyRPK01aaTdRN2tNMXdiUml4P3QkWHxQd3ImMFNteTl+VyhWQlEjPTsKendGenVfXlNQ
YC1lb2hoOSZtYkFhLWpYb3xobGdxc2srO01BbDFSeVY2ZDhIV0tOI2pSdSNfV1dPK341U0YyS3to
CnoqJm5VbVA5YClPZXc5WUBhXk9nQUJiVTZ4cHFlQVd4O0ApJFRnbGxER3Q5TlAoVnomWTtlYDI0
RE8+bV9WZEJaawp6PnVpbEFmPCY8cGo/Xi1WbmwjaShSV1hsR1h8VGBLX09vKEVDdCpfUSFVPisq
LW9wWigla0YtPExHK0FaWHBuTXgKekpFcVRfez1ycGp4eWlfJE98QWxFPGxve0ZWeE44Uzx4eCo8
dllXYSEhPjF2ZWdgMzFtXzBNSHJyYi1WOVAjTV5YCnp3K0BDRzx+WlJQcSszaTEzeSFUK2UjI0Bq
ezNZIzRhLSttfWt5fFpQdzFrS2xScEo3NGF8MUNpSWA7M3tBMW1EUgp6M2AhbXM8JlAmRmlefENo
Z0RDRkFoZj97KXlSJF9hJjc0JkQkRUk+ZGM1RmokLTM9S3JjeCtgNl4we19IcTZMQnIKeiF2KDtG
VkN0aTR5JEk/OHp3RmQoNHtpI2RHdGMoWi1sI21DbEU/MUNmNE5LMkstUyQ1QGNaZj1FYTxLTz9i
VUltCnpFP24/aDNlZ0UmP1c/SmUxT2FhfVdpM35IMUM5Sm9FfEBAaiZKR3tBdzZEPXh7bTMkVnhG
eHImeUU0X2pBRCNVTgp6JHw7ZVZCPHx0b1Ize1RrPWg5UWhaeHBRc0s9K0Zze3MmNyNIUz0xLVIr
P2Fmbzw9WXQyX0ZMbiYyUj9US2FGbGAKekZ0ZUw/MyZTa0tIdXx+bWo+TV9wQGdtaHw7SDljOUN9
KGQtMTkrQG83VSRIOWZqKmwhJHdMSjFlO25XVEc9dWxSCnpxZ1ZNOGlebXF2JStSQj4hVzxxNyU1
JkJ5Tj9IbWw0UF91cm5uZ1F8M1ktQ3hxd3NOOyRDQzBsTlZiNDA8ZGJSUwp6OEhMcWpWX1NgKEg/
Rk8hRT5Ke2I8c0xtKCZsezwwP0c4NGJRcFMpemo5e1U1bjw3ZUNLcD9yMCNGTytodmImWWEKenJt
N2swNihaKlZ5ej1MSTkzZDl9PUxGcXJoKEtxQSVONEJoaTJ6bGNMYDA+dy02U0Y3Tzg5JT15Vkw5
M2tDJXZuCno+NzA/MFVndTZCTlBLfXR7eyopLSVWJVZzLU0kTGI+Pk8kK1ZLfUpZWENmZzYkI28o
Skh4a3R5QG8xKkwxYjE4MQp6ZU5BZ3tEXyt+dDEjS042Tk02bmQwYk1RMEt5T0RYIW1sSUR2cT5X
enJONms/NyNBRz1SVGhhUS1uMFpVbk1valMKenZjTz1mYUFXZEdMJHIhfE1SYW1VWX1US0Y5QFlB
KVBhXzh8U2tBSl8pKytTQlhvZkZpUkl6VUlVcURpek5AWVgoCnp4U0s1cVJsWVZaMkQ7OXRkVFkx
YztIZUFBUmdSYTElVXdpREFGTT9SUk99dWB4ZERBPzdYUGo3XjJhYGJFYHFrYQp6c09gNzctcnxF
bDZBOXlBWWJMSVM5XlNJTFJ4Yl51Mys+USYjOClMJE5hJm1mezBMNEc9NVZgQk9ZbUYpWnxCfnEK
em4rO3RRd0NOWEUxRCt9MF4mJDZqMytfdiNDSkwmb1MwQjUrNk05KnxzVCRJYz1HY0dWYykzJTVK
aH54ZXZieFRACnpFUUh8YWZ0OEpoZ2NZRTQtZTxHaVolSk4rT35SMVQyaEVgT15HIUlPWSZrZ2x1
I3xMZT9gYjA8eHBldSRBNXJ4Rgp6JGNVeHYrd1RjbmNSUnJISEc5eG11S1I5UGJ4fVJUQiROTXBn
LURsVW1WQlI2b1duKVkyVGwrancmKkMlLWwpY20KejgxeWRVWTsjcGFzSX1BeT1lPCM9KnJINUUp
RWF7UmFKRHt5KGUqNG9OcX1US3hnVXtAXjs4bGZaKHtiX3E9K1Z3CnpoSTd6YUt3UG1NaEt5UkM+
QThUcCtTczRXd0JfcEl1PSZ1NCp8MmZAOUVjdWFWTnJPNSQtUD0qaTYjSSFlc1FjJAp6djdOTilj
cX5hRDlRP2lJX3gpWmFSXiFEbEQ1Uig5TUkxZ0Z4K0JrVGc4UTxOdD9+RW9faF4mKCpRWHk9Sktg
djcKej15YXcmZXRvcFFhQnRzQS02KDkqRFB8az94dVQjO1htXn5eckU7NVpzdU13bTU8d2RAZjI7
N04lRzNgUV5kUkVRCnomfiZkLUhyV0F3SVYlanV2ant5YE5vbilgd2xecGVDPClSb0c/VUlmJTd1
RSo2fXNXcyo/O2FAWjE5fXtOSyQjYwp6MGU4PyUpRiErS29Nb2NTPVNWcT9IZnEwYDVxS2FIbFBg
OUprYmRqPlphanpUJUs7JmxpTjdUIXM/ei08aj1SWFEKejQjMVNtIS12ejFWSWdFY3hUeCs3VEsj
VD1jWHpJZzg7Rj98OUx6NmpPMHYhNzRGTmtQUSMlQ196TjtqcmZpMFZMCnpkTG5OPWFINmFPP241
KnFeOThwbnMtRkQhQXtTPCNXKll2NXtpeH5rI2pwNz05VnlCNXFjRDc8PDc4dD11c1FSZAp6YSVh
QGYxX2t4SVhSS0RvQG9aNHlDV2FZcXlfVUEpKnRJbTBYfiFWfT5vNmY+KlBvOS1zTyViayprVmxK
RiF1cDMKeitMQT9AQnQ4TUA0K2JQZ0hJIzlkKHhDNiZ6fkY1SFZQb0BhYGN6PFExZmB1R3VjSiZS
TzJ5RUtQYnZDZXkjUHIrCnp5M0h6IUxeMk88OyNTOS1he1pEVDlWY3ZGWT96ZHA+fEh+cmx9ZjA+
PmNfckdae1NeRytxUD5lR2J3Qks9ak03ZAp6ckx1e248bDc/QER1bUVFdW87YGpRaXllPlhIdjlB
YEtKakxHX0s/dkRLTj49bTA4cU58STRxJlFNfiNMP20ka20Kel8renMzaylka0t4T35FQFM/QU5z
TFNrMD8zN0owTHJJOCZOWXlFK3pMVUZsdGtZQCFhO2pEangwWVR3JUMxfVZqCnpzZW91ZiRZITFU
b0FgO3ZAalNPTTZPcXNwWlhySEo7QVd+USYjSG5VZjgxVUVkc2JkTktDMSVYYSRRUyZwSVMhZAp6
bzVQfDRmTjctTmJUfU8+QUBZRlIrUS1WNVN3JlNzc0xVRVchOHk5WEZWX0UlPEQxbk9QNTVwayF6
M3BiYCYtVl8KemxtYVhPIztNb0JGQkdOX0s5ZShRdy14SHNXRH47VEFuNVdgOGEten55dVZDVzJ2
amA7Jlc7LT03MndYeks3OzReCnpWVm5XOVJCdFokUzJKPj5Qa283IyNkXzZyNDlsQHUzMjJuSV9f
PTxNWUY8ZlVCTl5RY2tiVEEmPHNOMTIhaHlSQgp6ajY5c0BDSXFUbkB0WG13V0Y9ZjZQMDY3JllZ
TFJDaG4kc1I/XzZNKEgydWxLJVlvcENIZjFzUzVTdVpAKUhQZEEKenkkPD8oKzNRRktUQz4+fUg9
QElyWGV9Q3NaQiVKXztgQEpwe1VKNUxzWS1EeFVPZHo/KkJGaD1fJTRDOWhDc2t1CnpxWCZHUnJ1
S0gpPWVHVHVvSC1sS1NlamQrRD55K1VDLWRQMmV1PVRkSHNBPEM7Q1BxNTJCWEV2PypZdz4pOWZQ
fgp6azZYSkQ8IStvcFRAQ004dFE8RztDXnNrY2BQdTAlcz0lTk1FPlMrLT8kbGc4MSl8Vy1TKFVu
Y3s0Yjw5aCZfclAKejNvNXluTEE8TDhJTithRlooKVZQc2pNYkZjU0R1TUx+flFva3JZWl5pRj07
aXwxSD0hTHJJSmBtVHVXQmhOTkoqCnpWOCN9a2h4NjhlJjFNSGMzRChTYnMxbmJ0O05OTXdoe2Jz
eSVvbTRUOVZ3dU1Pb2MmSUJkSlI8VC1md3hyeE9zVAp6XnpNTzYzNntRMzM2QEwpY1VEVXJtR15p
RikmKkg4azMlS28pKFVwdihIQzNge3soVURgUiFXPmY+TCteNEFTelgKej52aGo2KHY+eXIqLVIr
TiFRbnNXVTx7UklVYl96WCY3dnZaR1A0STglP31KdCtga0ZJRElVTWtuQUJicHZGcTFvCnpTIWs9
WEshfUw5dklTQTR4KnV7amhUVWMwY0t6b31LYmQ3MG9eUGo9VkxBJUlWZEZNfFBFYm00a0x4cTRz
VVc9QQp6UDt9PyU/N2ZTJiFCb0RiLT9EYFNHc1lTbS0rYXFvMUVYUmo/UyQ2PktlKzhCPkBYXkxz
dWI+WDFmPFVrd2YzUyoKekVNMXt2SilGXiFKfD1BRk5hY3FRO0R+JSQ8UEQyQFRtdiZEak5ONEl3
ZUIlWVhBe3IlRDlCVTVESCRHdDB3NT9CCnpxfi09a1l9V3YzdERXPmZUIW9tRm1SMTR7Py1hVHhl
aVA1SnRBRT0qeU9iIURPZkxrKHcmVSZ0UWh8K2NMYS1aYQp6Tz93KSZBKXlaT2xPMSUtRmEmdT8j
clIpKi0+d3F7WWRTSjVATURWb05NN0V1M3dhV0ViVlZBYzQ5VnsrSX1QdjsKeiRaOHJ3PXxoRWJh
NHdVPHpmUFchaTdsSj0pOV9+OWNMJD9pWTBiTTNzY29LKT9ycEgrUX5ufFgybDRkTGMhdlBaCno1
KGQyaGUydTEqb2ZZOTB2en4tX1JTQXFNMkw3WEErcklnMFBWWTBuQVdDRWRkaTJ8OTF8Z0AjaFc+
Kk1UdHVeXgp6Vm48N00hfWVmPUM0V0RjLU5oKzI3ZyU0cyVTXkdBQzREOXdgYE8jYGkqJkx1R3Zn
YT9iYkNLJlAqSEF9dn5NcDsKekN3a0M+MXs3UU1qQER9fCh6SVBNITI1KUJBJXJjPj5RJFdFVXE1
P2AydioqfDhAKWN1NV4/N0dMZHd0dkZ7NkVBCnowQmRzVW1BZ0tpU05eOCNlJT58eFJIJmhNdmhS
YT4rMEVNbCE8IU05Q0U/NzQjLXNFb1E5TW1TOXNIQipzLVp9PAp6fE1MS2hibi1YIT52fj1fcXVG
Wk12djtkSmRWTXIpTSlzXyhxLWNKMDE8enBLUiVpZGxkNmJzdXRzWTJyUWh+NWcKeipXSDNsMkdY
QW9taXcxVihudm5ic3VWRSYpRT9pN0NvYzM9I3M/Mnd3XkxvNnJ+MlU5VCNvUjJjMz82Qm5IVD5k
Cno9N0FVV1F9JE5gdDExJik+bnZMI3kheztUdl5LRCFUPWh1Tj4yMlJHKGs8fVM5NnlfNHNYNzQr
bjlBbmU8UUhJdAp6YCM2T0xZKnZ7aXdJSm41MV41YiU8bThlcEpBRUs1UFFPNCZwMU5HRSZGU31q
Y0dSZHAjU1k+XmNwOHpeVn5QcT4KenZhaShBZDMtQj48LUYkcSFZX3h0PVYpZHJ4fV9iR28jQV4+
VmhESmBuKzs1VmZZMTgzOUBBank0SDsye291YVp6CnorRTFVTUJwfGlDV08oeCV3OUlfdS03NGst
UHM4VEAjOUx8bS02OXhKUUBFfH0xd2FqJmFWKkQ9N0B8Y0hCUFhofQp6NUxLVzchJWYjQzB3TmJ0
cUgyOXBjMldEUVlSKz41ZmhzU347TDJwJmRkWmBiMThraDA+MkBHJiN5cF4yZEV5cHwKekpTakQj
a3hvY1FmOX5tSE5KaCsoMn4ocSRzbjI5a0psQSoyYXJzI2lmYUdhdFE0N0RAYTxzIU1PcmM0aGhW
MStkCnojZ2Bza2ZaeDQ1bFdmTD1VfEtPQjtDcnZLMSVTQSsjJlEleXtBTkhTeUc7fnJGQWpVRHFS
Mzs0cnxKTCojPG1+ZAp6SGk4a1RKcCMycWw0P3E9Ml9ZVWc2c3o5KVZDTWRFVDIreVZJeDRpbyRh
OCZFUD1gOWdRMytTdTZtUXhEXkZuYEoKenZwa1QkWkRYeXRIfWhWfEt7ck44YH1RVWg7IT5YanRt
WmVQe3VMdllWQXAtOT9rOEh2WWFxYHtxcT5CejllP3xYCnpSLVozMk1uNUQqJEplIzkwO1p4PTAo
QzFePGloeVNvMWY0M0g5Q0h0YHFpeTRvc3g0PmtebnVVSy1ZUSl2fDwhZgp6SjljYlBqIStVYCF0
d2RsRlVXMj98QVFxbWcqfipCZzhtejcjbC1tIW04OV42PSEhdUk/N15oTEJ5SF52Skg+LUMKekUr
V1dWMl9xQDlOSFgrQE5DfHZeKTBQeFcwTkFjVzNIRCl9WXU2cHZXJFRlMF5jYyR5aytJeClpZChP
VmRuQXBVCnpSQE93OFcqellgIXxYSmVeeHpAbjE3fURnP2JzYjdjU21TNmRGYHFhRitsTHFMSyQw
b1JWPENDYzhLJTJre3h4Ugp6TTNCKDx2VT10NjAxYFBBJTMpLVJqITxpLV53PShhMkIqZUdgPUFe
S1B7JDZwKjBZPExVZDckUVA1c0U+NmpBNkMKem94RHZUVzcoKTZwUT1hOU9RUVpART9DOWolfVdB
JV9KIWIzYzk/bFEhNGMqWERjSjl4dTd5NzFyZDgwNGomaUt5CnptKV8zUGReUldjKz5CLUNwZnt9
akQtfHVoaSVKIzc7NkhSOShWeVg2VC1qTDt4YFJFVTd5Ql4pdXBYST1XPk89cAp6ZEtaYGNFMlhX
SEteVnNmMGRsbjZ2LW85Pml+XnIpWmE1U2ZtSDN7aXl3OTk1MjYtTCo+S1Y2antrN2ExTzYlfTYK
em8tcEw8YTdDRi0+YXcjV1V9PkMpIVheVz9pelZJSEJlO21IS2RpY0RuKUs/c1diM2VeNyliQEM+
WEcmYWFNPHZMCnpfJHY8OSRNZl9ZOT5EPHMjYWlPdWQybml1QyVxOWoqK0Y4R1pzfG1HXnwmd0Bp
dlk/YzxiUV4ybmhoaUlYNVhCegp6Nyk8Rjdra1dvOHVDKD9uKGNjM25eUWpuJUdYMVE3K2hLR29Y
Pkdqd1RjPF9GQndFQ3heaDxiSVA3IX4rbkk3YkkKeiNqfkJ2JihrPmtTX05BV2ZkTlJNPkdHTkBi
RjVCQWt4emtyQW4xWkU8S001Q0smVkZ8d200dmM2K0BCZGRvWnRvCnppWGg/LTl8N1R3dyV5T0A4
QjB0KnZNdyR+eE9qSzZMXmM9Y3szdTBNYWh5WDxXZFRvTyZlSHtlKXgtdVlMWHFKMQp6KEZ+Pmgo
UjVLYWlXaD9YXzkxR20oUDlUdDRPajchZ3pzYl40JkBYb0E2bkg7WF5aT0VGR1M4K2IjRz5xRHc/
SV4KenckODt8QD5pa2Y8dzBAYHteeHNTTFFqc3RHKGNPZiExKE1kVn1lMEtkU2A1akU8e3h2IUcr
bz9XLUVTNjQxS15lCnpJeiNhXzA/c3hNUzBRVm08dEt1ajcmczJiQWhqUSRHSyZRVkNIIVombWAy
OUJMQXVTVDRFJGYoa0hORmZ7UVgkTAp6eFc5I2xXKm1jfWZHTktpNVApZDVhYDAyal58RTQkcEdn
NjxIZ00yYyQlJDR+KXphJWZORGZBSFRAfWQ7R1kleCoKenEhenclblh7PSo/SUs4RygxVmhCI08l
XzBHWDxOUyY1LXl+Y1ZTM2NET2R0IUlUYD0qP3tBO2V1fShCLUtGQ1MyCnpNZCtZYiZTRkBOeUpl
bT5rZV9Hcj5iZyt4cyY9PmI3QHdCdWF3KjVHVkV0P3Q3PG9eWTk1Pkx9VTJnR1Q9ZURxVQp6dnpM
c2IwJkFrS3owTHAoeCZpUlc0UE9sX2RxWlR9aDgrX0IhOV4ydkBzZil5M3RUUkxYRjtoflFYe3lw
TjAwcFYKelh3JWpBNj5zXyQ1bnUpYCgrZ358QXl3UUZtNHNAV2hqbGxBaj9+cUJmcUtGPVM3SDNn
JThWc0h4en4xJGBxfik+Cno/aG9+RCFgMX1rPzZnN2BTeUFOdWxueWRAWk5ANVheSzxMUjBLQGpI
bzdwRUVUbFk7UUp7JmY0MElYSTApez03awp6MyEtPHRLO2RXKmNRSE5YNlkjbj9YKit5QFRgPC1Y
RW5CLSU5ZyR4YFgqeHsrb1JxRitweW1teTRkWiQ2Y3ZXP3YKemZRan56QmFtMUxsVWEhenNNNlNk
N1pwNDdZJHJMSmg+cUxTKyRBdlUjQkQkaT5xM3BNKHB+LUJiZmZKWD9yNTJsCnpUNks1MiMtcz5D
S3pkVT16KSZsPXB0aCF0a251cmtte0JIZzkwcDw1dXw1PD1AO2QqQSFLYDhSV2lIVCF2SUp2LQp6
UFVRWEoxOEFwenZuKXpLYENAbEdOeyNrZlEqeVJJY0tSRFArWShZaXNXO3NETXxjJEotfW9DRlBo
PGdpQnQwZzQKekZ4fTBlZDlZQktJZWsqSShDMjREeDhIfWpSUXtrPSFmcnxqUFozIWQ7aGpONW53
MkMrV2RXMmx2dFJ7ZjtHXjd6CnomYXo1NEt+d2VQWFoqO3I3JE5iNmlNRXQlPjNAZjt5TEtlPyFR
YWh1WU5QRGRfY3N6fXI0Y3oxZ1dqOFY/M25xPAp6aUttQW1LeDB3YDIyNE1rIyNUUCQ0cmp6N2o3
PDZ2cnJqeyt2Qno0UTJUM31WU3J9QGV2cHI7RkJSZmZUY2dUcGUKejBMX3JqPW9KZ1ZoYD87PjNW
M1JwQll1NXwmcj00bT8/Z19pMHl1aTZWeXdRZFp5czZ1MXBoc3tYYiZBUSF2bU1LCnpMKCVCYFl5
YjNjT0MzbC0jamRwOHtxdk51LUVaQmtEam1lUypMP25mSlo4PXRTKkFCSj9FU2Y0T1MkaHw9TkZ4
Kwp6SCFlY3hEJWFITDhRZS1EVzQ5X1JXWkdPUntHLTNlMDVSKFh7IURpOEl7WkZLJW9ORD09VDR8
MkwqfEtHRXR+TU8Kek9jVikjKTZNRXB4NiRiclpwcUVfTkklQyZYXiVCd28kJGcpU1cwZT0ybTFB
TVpWMnN4ak0wMiE4YmN3cXJ6PX1XCno/SlJDRzc+X05TYzJ0NkBpK3AqNjRWWTZYZ0VaMlVoWm8r
M0xrITw3TnA+fj1vI0FwQkEme0FLVlR6SE5lTEp8PAp6LTtMZigjd2szRG85MnplPUQ5V04rI3p1
TDtUSG1OcCVaTTsofjZWJmx3bWIoV2dpM1hkdmgqOTErb0J9TTVnNzwKek45X1FvP2t3bj9oeSYl
dVh0Xj1YR30pVzNMX1E3JiM0Pn5YRl5JbFIyPFE2bXBIazhPMXdWbmZkc09oJXd0ODJ9CnpFcVlL
ezlxVDBpPDcmK1RfQWpjVUNoKmR5OVN6MiElXnlgZWl5OU9iS3FJPXNqRWEqPF5IMmFBRi0tSjgj
TUMkRwp6JmdyJnZWM15sKjY8aypIdHs5JHFLezU7K0gyUHBOP1RKbnl7dVNkMz5DLVk7S1UhTVRH
c1F0VEMyPHl9RGIraCgKejdxTi1MeWRJVSE4Nlo2YVRlaSYjeTY/NXJIamI4IyFBQ3F9MyMze1N3
OERwKUFCZkE8aCo2VW5VRDVBIz9pa3R3CnpUb1NuQHglU19qeGx0PTB0XyEjTUVwUX45SzMoYXUj
eFBRREYzNTtIOEMpY0txO1Y9Q19saj5qaGtsT3ZRQGhXYQp6WVp7MTI9KmQ9MHcxRERJJWp2KyQk
YypjNShIS0o3N1BrfDcmN0txU3d7Ul9BWSNsKHRUTVRRdTR1T1k/TG4jYTsKemUwRDd1Nz9zUDVz
dipmNW81bFpuX218TEJ0MjQxY0xkUXtPaXQlMmJZfVhlIWlRKlcreWxTIzhyJmhGPEM7SHo3CnpI
KzEodS1tVFd9bkxpZl82SWFmYmM2Vjs4cE1SMWJpUkA+XmFQIy13R2Y0UypvI1lnS01ZU0tEQUpu
UVJ0b296cgp6aiFhJE5BeTh2QSh1cEBYe2ZJI0Akfk9QMzg+diZAd1Z0JChyWUtPbj19d2NJN0lC
aiMqdjViNz1QaHxYO302SE4KejQxV08tPW9NaU10NSFTZmotQ15hY0FGNFljKytXKE1UbnBFdlR3
YGptY0pIS3c8KDtOek9zOWZZSio7YlklRGUwCnpiP1RlcWVDbjZMbz1Dakokfil9fllqPWhucT1t
akhlREdvYVctcjt7aD98UHdpciQ1bm40b0tHVCNRQUNaZV8lJgp6Q3xnd2ZxaGMtTzF4TEVQKSlY
JHlaWlpRVTR4aSk+MkY3JT9GPSE+c1lzeUpfK3RtaEAtVzJMbkJWJHImTF8oUzsKejxqJkJaeyQz
SCpRVndmKmk4SHdIUEI5KkQrYitPM3A5JHM2KX4hSiYrLSRzN2xUUTk7S1ghWV5tJC0xWmR5IzFx
CnpUMD9KXk0yJE5YbVROaytsVDVXLS1AfjV9NDImP0hwfEVHZyFkdypRdStOPjtqcUNicCQmSH1R
ZUApTEJMeU9YdAp6TXhNQkxjQjhoTDxqNjI3T0JibFVvSEZ0OUNLUShsNGZOdVlOdm59SURpRFoy
dUQrY3tJXyVhezwqMitgTGFKdHUKengtPEw8SHczb152aD5wcVJMd0dgODJ7cWRROUpIRD59UGxY
e1MlWHw4RHNkUGlROX4oX3J2OztIPlZIV0I5PX1sCnpDZj1vPF4tbkNadUdxLUJQKTVoK3d9fTRT
KXpuKlRBfV9BZEkpcU5RUnxLUV5uanxlRmdgZj8yUTNUJWdwPDNDagp6X19PXjdLUSR9WXBPJVkq
eyQwKDxQT2J5aDQ7MWtLI2tOP2J5fExZWnRfJjIqd1YwV2FCNUpeNEhDbzh2TGRAKXMKejc0Mj9R
YSZQZ2pFP1loVlMzT3M4NTx5c0EpRj0oUyhiNDZVPnkoXml7T0o1K3ZKSC1KZG4zT082OWJWVjFp
JkdiCnpBTSNnMVVwLXQlTEQjKTlqQ0FtYV4lMkFVK2teQDl6ZXdhaGhSSGw4VDk7aDRTV1p3b3F0
bHNrZGckP0BgYiF1Mgp6VDBYY010QCl6PWx5IzZge0FMe3hAWUNOP3g4d2l9an0jYj1sej4qVFYp
Wnpec2lTZkUtUCM3blJASGNCTEp9QU8Kekk/YjFmKnsyQ3s/UWdoPXdmM3dePFp1SzxkayU+MHMo
e3RKQCVgdmFHYGx+aXF+VVJZWV9EPGBWKEVxRHN8b0xaCnpoKzZTIT05aVI4UGRVOCtIOXNQNlYq
ZiFscnIhO0Y8RzU1WG9ZITx1c28tQXBjLVZ3RztqOXU9QlhYaWQzOyYlfQp6JmJuMjU0fXtzRmE9
KDlsYFl1a3NOSH1uYW5+VWU7YCt+ZDljUmAhLVVDNz58aFQ3bHo1ck1xKTR0UGFAMnhWISEKekpu
ZCFPbVdsWX4+KVkpQkFGNDFWTmdNRXw8YHZ2Z25iZFdJaio8eD0yI1p9am5TLUomaDQxP31XIUkh
IyFxPEFVCnpQPGJvdWwoYXFiQW55czBjJkpnRHtvVkZrYyZJNj9AbFU+WighYFRrU2Zse0J1YmJO
QT14NXVmSHMxJkxFXkJ3cwp6RzxIMVBxT2ZRY2BvTigwVihKZT5aYUR3cGEpWjFuTU1BR1dxYUJs
UiQ9MiRoIXh4V01ITGE5MTRMZyYkbnJNbCUKenVFO00tWUxVM3tVb3ltOGB2dDtzUlBoM3JxdXgy
TTVNOSNyTGU9blVPTklOUGsleSpMe1oqd0AlJGxQSUdtOSZSCnp7VjhPcGR8TWpjTkQwMDYkWkIj
Qk8hYms4VEJ3RnNyNDJrWUxFc2spMyFJNmAkcGZyfD5peSlpKEhUYDs5MGNuewp6QmJNdiY5LUVf
PmErNm51O2FeSktefjRqeTw4PlVhdHcmYmdNaDk/eylqTXhkSXlXZyNMejt2TllxNEchPFNkWUIK
ekNnfXRnVFVJLWE8IzIqQGUoe0Q9bTh4VC16ZkNWV0l8NDsoTzhUfEB6djxRUmBUY0lAV0BkZldN
IWExMFVvM1FOCnpNRT0wYDtvPW54R3h4M1NpTER3ZTJneDhPNUFxKXZhJEEhcmJ8TDhAMnJmbyQ+
JlRmOCNILTReNHk8RTFtU0o4aQp6TTUhMGUhc0V9TE9MdkVFSkpWdjIoZ2UpdSE8IyQzeiltPTJQ
S3BmfXprYj9xN2QxTChOSio9fUx7OTJlb3ZRR3QKem5yN1R9TUo5K3FuYWF2SytvZn1nNjY5Tm1L
eEFndTdhd08pUmJxWVRzP1lZRTMqPVZEaSN9VDNVN35tYSNsM1FHCno7PjVTTiM5RW5iPGltWUMw
dEYzfiVsUHxAbHZZNjNfIUNwSkp4SjghYkpjZ0tQMzBSfXUkd0A7SEU8VD9xcSpXdwp6JmlaaCop
OG4qaXhTRWBUP0A7XnFYTkNDME07X2E3NktyWjZpeUN+N1psTmIlQlIjIXRyRjJaI3FTOXQ3UkF8
c04KejRfI2VPRT5OXlIrc1NvaTk3JXBkV0hLSVZic313JVRYflJ1WWp0KSpDTUNLPl9IKDs0ND9k
PlNKe1Y7b2B7UTI0CnojYjc3VmBVWUVNQVBJSkg9SDgmKl8hYkJjZjl3LV5AXm1HZnsxKnd2V3xz
TlF0SVdraDZILSZxZ3pSYTxyQ2hAfQp6P0NNdlE+Myk1cU40Xmo5SkVDeCg4c041IVpUPSlAaHZj
MilqWi00Um85Uml5YHglLWl2djZGdFUhe0olJGopcG8KenNuMnwxSDV6RjdQUj19YG1DRHI7Z3dv
R0pPezJ0P0VNQn44QT17KDBnc0M+fT1eOE5VeEB4KlUtWjhLeXN6cSQzCnpZbE9mNnVaK2hTcXFK
Zj9pWE5TNGA1LUo5c3UheHJZUVdVMEB9dGh9Vl47Y3cjaDFvSiUjWVluOFUoNUdeMSlKZwp6JTtS
O01Ackl1fE0yJEhUR3swSlhzPHlGKlgwYjRNaXtaMkJjZW1VbUN8MGlsVTkpdztxKEdmbyR9eD80
Klg4c1MKenIyJmI/eXgtPFRVdXUlRj0qb0ZIRjcqQ2RmQmR3Rl5UcEApemUmcUU4MWliJlRDcDtY
MX07Zl5MPXNnayZ7VWVBCnppWDVPKTl6dkdBRVFrdml7ZkZ9QlQqaX1CTl4mfkMrSnNqUF5OTCMy
TlM/O090ZkVzMys4OWp5cEk9fT8qdFpGYgp6S0NUKXJzVCF7aUtYO309WmxRN2c0RDV1eD9xSWR2
ZEM+OT1kSzE+Z3VJZiRmNG5nKVBeaS1sRkcqYE11UT14fWsKejBXdDlERl5hO0I7cTVlTVNsVXV0
PHJaKiVJUUEjYlFJblIzaDxAZ3tfTllgZUg3YURySlYrUSZzS2lKN3UyWjxaCnoxYE9MP0xgRTJ0
aCNPcWNObXd8VCQlJSsqbS1XVzNXbzMwU1N7JUd1OypVaV4hYEI5RE1HaH1uKXZFKDxfKT11Kgp6
bHN8ak5acGAxaURFSmJKNmZnQHAlX0xAcyZPJlh1VTlxZFpNaFdIO2BJa3FGMyZjU0ZmMWBJfEx2
QihsdXhgcWwKendPaypGZ15LO0R1TFBGa1Z8R3loUWFEa1pqNXc1NW9LVSYhd0BZSnZhbTlCVXla
PTNnY0VgUTQhQE4/IS1MXnYjCno7MktqfipTe1N1SDs3RHB8SXZacXgwT3d5bHo5QGgjKmJod2s0
JHRpYG8wM25wPjRfYD13fnFIQ3A4QSYydEJmUgp6eWZUWn49bm08S1UoPjxWQ0ZuSlJ7TXVwN2I/
czMkMT1KKkI3OCF5NmFzIzE+QXEwfFhOJjFnOzZ3RDdkRjRrWnUKemxBQWskMm5ZQ24he3ktR3NQ
TEpPcCp2e2QzRHhyQlcpKkBucko7LSMyflM9bEwwWFgmR2cpYjhXfWEwSnlOWSFnCnpnMnh1YndL
eVVDMS02IWQqXjYxWkphSD1BV3NlcmcwMHdyXyQ+RHN9N3ppSnlAQDFDbWlBUkomazdsZkJNX01B
ewp6MT8/eGU/TFV2YTh3O099bCExd2Nie2VTOG5KJkolY1pBQyVCeDc4PHp4Xik8dHd7ND9JdDNH
YXhpVWl6UmMlLUsKeiZQLWh8X1B5WG4xZ0klNXFtXzBGZVkxeHVxYiV+d3FHI0h4WH59Ml43al5g
dGd7eiVJMT8/X0JEPDtPTFV7UGhSCnp1aGYofnlAOHFSYGh3a0NeODFmRTNFQDR8e3wyLT82Q2s1
VUpqdjc1Iz0/REFHb1U2fnU5TmImUm53IUw1dUJ9KQp6YyQqOE1SdXZQSj03bih7UGhSRWtyMUY8
JEV4RGUxZmwhOy1UcHhmIyp1WWB0VE1VNG5qazJYdiQoKkgrM3tsd0gKeiUhKj52IT1hMXUhKiVo
JXBJNCpkRyhoNCgkaG9VZihDc183TEdLQXNySzx9djsmM1R8cTQlNU5VZD1LI21kP3g0CnpoY0RP
KEVuVTRBWXFASGV6Y3hAWF4wWilWSnZ5JWBDT29FX0ZWVGRiaDtxc1plSnYpakgkRT0qTGReakNI
XmJyNQp6N0J5KHtrPWQ5JVlMP2NGK0w1cEhRUUA1OHZvfmshR04zVEdUemJAJnFpPTlXPCsrWFNW
LU44UyZrTisrQUhnST4KelVTPV9KUlUkWDg2OTxfSnNBODZpa051Mi1OP3VJSClsbj9lPTl1X3Et
TjFuZHVYN3JZTF40MEdWdW8yNmIwbiooCno8aUt1PEdxezMjSHp9VyRPTT5Faj98eGhEMUNyM2hn
dHZSM0lYUSMxJFJSSGtnN3QzXmgwc2tHOFhOQGZgNj5wJgp6Y1N0TUlOWkpPRV99YHptRSZURyY5
PDVSe1FiRyFuKFZVMFdJbn5MRmRLNnpqMmMpZ0pJPz13ej53YUJ6emYkM2UKeklhRGNVTEBxIWYp
UEAjPk9pWllpUSt+Xmp2OEBZXnBDKilSIV44PFNjOCNJSGFAdykhPndzZHR5elhQZ2gkcXhzCnpe
ZHhYOW0+fVVONE1yQksyfT13Vy1GUElwWjRJV2U2KFUqRW5aR35VbnAtaTBxd3lyN3Q2cT9sJjFM
aUozKXEhLQp6NjA9PkM1MDAmSyUyUiNsbllxa3BFTD1tQzZFKiNRP1FldVZeTUdNdiVFSFdqRSls
Mlo4bVE7I2lSNFNhXkltXy0KekRJOHAhNjRaezJSdnQ1KGwzejdtOSR6YjMhPmBYRHZKenhwOEFM
R2BgUDRgRHNaVWdsVWdtY353dEsjc0ZqMVRRCnp3d2UtMlJmdCs1NVNFd1BwWFFld0FjayZhN2cq
RDU2O19CMD1OanxUSDVwM0JuUUpuZVc7JT9hZGRqbjZANWA8Ygp6a3xpfDskMUFiNEIkSmJlPily
OSh2QDh+cDRTPX40cGtNYkBaayZqUlF+Mn1FNz05dEZeOFVQZXRNKnFNdWZaPmsKel40OH1UZyEp
QXpfTnU4OWU+akl7RVYqeXRpVHlrakdjZ2tzckFUWjRWKmkjdSU8PUVfdzVlZmRUQiFeI1YmJF43
CnpWT21hOyh6V1Q5aHUjKXxqQGptZnBEQ0VeYlZCVzFIM097QClwcXRqYEZ3PmwyO3U3S2p3RTJR
PVBiS0lPc3NfYwp6Q3ZBeTFKS1poUFUxMyZAQTtaWiUhezEzN15eMy14RSpsa0QlQVFSQXMyKjBN
Qz5nWGY+Tyg1T0woNF9UNTxFfnUKekg+dzFxdjIlYiZnRjUoRGZwdVgrU0NCLUY5MU4ydUpQaWpl
WmlDVjAmeTFOQXpOcyomQiR5WG9USHpDfDMrZD1QCnohVEJ1N2ZaJVdNS1R9UDBJd0V+dFFgOXFa
ZmcoPjJkYTI7fD42IUdDZylpYzVrKipSKjlFc05YOGU/OTdFVUJQcgp6d1N3d28qZjZzZ0A5clkl
OV58XmNgbC0tVDtQVFl6MnNwWUYpeXstJSRAfGdDJCM2I3lRR1F1N21VOWJWUWcoT2AKemJyTU5S
NT9gKjwqJGkqSFhibCF3bT1rNzYxPTJGbyVBamZtZmNAaWdeKlIqN2lFcWc0VjN9bCFhX09gRyE2
TiZSCno1PyNPRGM1ODRqMDRRT2JKOGk2MC1uXmdUejtEZitLRW9AYTFUQ3pMdkV0c2tiVEUweTgw
UmNJdDJ5Tjxpd2Y2TAp6anRJd0I2TTNvXlg+d2ZoVkBDfmhyYUhlR3FhKH1IV3RHXjZWMn16SjYo
cDdNKXtFVXN5QFUkfmZIQ3wydGpeOGUKentOeUxXPylyVWxIT0FDJFM5eEB2ey04bmhnRnkwdkVp
bGJyVGkyQ3JjMj47VW1fQVZ8aXtlY3pyektSLWdGZXc1Cnoodz43ZkxqWG9gX3JYSmJmaX10RGc2
ayY1RSsmbEZiLWxNcSZRNzI7dWNyIUdnNHZeY182TDw2aHdUMz0mcGJyNgp6eWFxaFlzK3FWU3Ff
QTtoRFFNfEBFNTFeS21ialBwUF5TP0x2QXYpRDcrVURrWDhNdzgzJkJkMTE7bUktVnlGRUwKensq
SEV6Ky11ZzBVSH5vVTM8d1gwSH00S2NLKVhQT3tjTUA9QnRiQDU9VWxuN2A9JEs3PDBuVkJgP2Rs
byZJV1RjCnppfDR6dmwkeWp7SiV4VlRgfEJHZDV9MSVKTnF0dDUpeE4oQCp5eU5WbX49ZkYxU040
V0dGLUBPQVd9aVYoRmhjOwp6Um5gdj0xZHlDb0d5TWlFNk1iJktFbExkcDltS0JsSFRiUExxaElA
YzwpVzc2UHFhUiZySVgrc09qMU5WUnE2eDcKeiNxTGlDdkEzS2lUK314LSZCXnZ9PmNXWlVFSmNR
ZytjfEooYkZ7dElVZUpkMW9hVGxRUGI3eVF4PSN3ZHpobndICnpjTiltUCtKbTlSJFRpQUxiJClZ
WTZrP1p+Wnd0a3JAODIqTmskNz8hbCRxTjBaK1NZRz1qVlNrJXBVK21iTShVLQp6YmViOShUJGho
Kns4Z0UoZ14mWCV3QmFSajRYaFJfZ2w7Qm1hKChhUnt3fX5uJVpELTAodnBYJlUmbz17QTh3XnUK
eldqWDdoZWpMZVZaai10QkVXZnwwJVBUN2A2SGg5NkxwKUpgQ1E5IWNgUEQ/dT5OJUstPmB4aFBC
dkx7TVlHSllDCnpQbWRmWCtIYU9AYT5YZThAaSh1PWE5UGJfQj85Klg7XislT1kjcn1sTTMrQXxQ
eEFPMFZraGwmVH5xN3BMM1FHJgp6bXIodGs3b01BNUA2b3IoeXxHYSlXc2EhQXZUciFva2dKZkIl
Pnx4RTF6enFKazVATk49PGdLKjslby03YCQ/Un0KeiRgVzxuYzd3dEtVc2AhQEt2T0ZaU1ZEIT5O
cyo+a2t1MmhDWWlxe3d3NVhUUjtRITxwPCtra0l0dypacU9fXj9oCnpHN3x5Q0ZeNkNscndOa09D
Y0UjNWJ1UT5LS1RLU3dRb0NZKSpAeTdiQ3pjJTVXbiMlbCs8OExjQVp6bU5kY3FWRQp6Q204IStj
cWchUUEoUkNvI1dAbEB0RG44X3pmVjd5bC0pfCZweEx9NDw0ZDMrbGRCZW1HJU41c2BrV1JpbXVe
aXYKemUtc1UpUz5BO2dEKjkyP3luVCV8bU1LdDhVRkJOdzN0SUd5OFpKMjA/aEI+SCptS3x8U3hZ
QTcxPyFJUnFZfUwtCno2MUB2WSpYdipQXzRqVkxUJjg0WTlmdmMjVkRkQGNvdmI9MUMjVV9fbn45
Znk5TiU3K1klR0M/YEpmT1FFYFZJRQp6STtINlFZcn1pMS1PaiRsd3FUPCYoQHFGWG9RPCRYY3NO
RkljWkltYFQtLSgxZCo/fSM3RVlsfUVqaE9XeDNqdWgKemljWi0qQT9XRz08VDYlVUxARV4+ZXEk
NWlEPl5HI3p7V00yIW5TaHpveH1mcEVsbGZAaGdjel8qJlc8QEpNKmNqCnpZZD1HYERffHNIQW1B
dilkXyNWOUMqMj9gSlomSX5AV0Q3Pit5VjRaUiRqRnsyeV8yVGYmVGYrY3VCST5gSSQ1NQp6OzNV
eE4xUWNqOW5JbzF6QDVjPTQ4aytxWj9qSE1lYjE9bHd3UWNTRXgtWmI+YCQ+MzsrX2hkVDhGbyR6
eVY7Py0KejwyPjdZJjM4ZmY8Pmg3Q0twP2lAIUFDU0tPel99V05sOTF+dmAyPm0rOT5rP3A7fTlq
cHdxbjlqe0Y+LTJKVSROCnpRWFIwLUB2IXpIQGI+bSo1c2wqPzEwSGYwNm0rT09LMDRBUXRteFE7
bFlrdD5MRmkrNTJKd04pKy1JTX5nanBvTgp6bjsld25KfDkxPDExQUdPdmtNIzVfNDheJF9ZUUY2
bFItKnlNLX1kXkJfI147Um1Md0hmeks1MGtmUHRAZUVkJTsKej19RTtqcVBrJHotdExiMzQyTy1V
JSNHSzVYWVkma0xgey0lalpVQGg5VSo5UWZYKTc3dTQmaDFGeHZWe0E/VXFGCnpxSlIyZDZoJCF1
RkpicTlXKERYbjFvWk5wdFpVLWdtcTdRKWl6VWdGOGsoRjBod0ledEw3KHI5VG45JEt5PjRNUwp6
K2w3UHZfQ2poQDRwdnc3OW1YWnpXKjAhMCNSNns9YjNeMjkrZ0ZzeEc0MiFGRVo7P1FJJmNvTXBu
QGc/cDRPMDcKemNSX3dFX31ecjF2PTExRlJFezFpKDh5SDdjJU1gQHZBLS0xaUM9azdpciQ8JEw9
RTUkK0pjNnxoWX5qezhkXkkjCnp2WGZjai1uU1VVdWlfc315d15OQUkxeEA+ayt5QndyaWx+cUtK
fUpZYFIpQSY+ZXJvc2ZCO3tIM0h3VUU/Tm40VAp6d3M3ZXpjUXFDI0tSLVd2aHhzZj5pPXAkfDI7
b2U/K3ZuTnwmfU5DdD9HelgtODJyJXIoMkBGallTWjt0P3FtcEAKeldZU2YodCgrQnVlO2YlYVg7
QzZ6cG9YI3ZeJDhZPUlBaVo0WW1TJThoMGM1THVJTEAyKnh1bztnO15uY1VldTdSCnphRjM0SEo+
NVh0KitFcyU+Y1lhdCpHaHVRaFEyMUU4KHg3NGdZc1pYP1ZKNihCOzlPfThQaGVkbSZ4fU1FJkhG
LQp6Q1Y+aTBNNTQ+P0U+dnEwY31YUGdKRnpQZ2NrQGpoUHUyeyVacjUxQ1pOZGEqUz8pMUlLQkQ4
SD9qIW9mdCEtX0YKeis1WHBNNmtTKD8wPilra1loQk8lTHw1dmNpYjBeVS1CbG5oJHVRd3tKSCZJ
cl8raHYmJmZqR3ljMEtoJjZySFJRCno0ZlBieXRFZ0JgcFBYVzdiO0VwRldvMys5KVExaUNkbSk/
bXItIWNoNGlIUH5DP3tNWU1ESl9KQU5oM3Y0dktVMAp6bWcrKF49KE9oSGU3KW1rK29ERjFZJCUy
LU5JS3VZY1p6NCEmUy1SN1I+Y2hjP0NneHk9Kzk8VnFQb34hYE5xcS0KemNQR3pSKGhKU1o2Wkp0
eSsqIXI+JiQ4VWswVmc2PXs8cVUlOHl5WXtJVl8pd0VJTV97eDNXbU47MUhDKkY1RW9TCnpHb3Mz
cDZuSWJBUipxUUopO0FIQk1TV212enBJfkJkbW5zJT4pTG83TiF3e0h1RnJXX09tbCtPcU9HIXBh
Y2QjVgp6ZWNmZUhaQFpoJS1UMzJxKCYhTk88QSlrWT5ab3VlYihUQTBrJnojJWgtI1dzXn5rSWR1
V1RtZmIlQzYkTG5UVGQKemBnZHMpVkckN3V7WkB+cUlNZGhkaEs7QTApWHJPJUF9emJ1KCtacnhr
Unw0bl8qVmU1QDZ5MygxLU8yYjt8fF5hCno+KyQ7Zk0tRytgUThxZnYkJk1XK0xrMjZIQEZZa3lq
MGt5eS14U20/KGtuVFpjdTI4e3I7RFNYS0ZfPihHVypvZQp6NklsKmhhcXIkZDg3TD9XXis3ayY/
MCRGcjhUNUtyNGNaZzhSQUN4PGliMSFwUSt+d3crRDdzKEVmYXhyNVBRaD0KemUyMyF3QGZlQlI9
V0BIVjZMTiF5aCZXbExHZ3xKQDtIUTh1Klk2dExmUWJfcDlffDB6UXJzeGNNdkVqd1J5WiMmCnpY
Xj09MjgkUSVya3cyNG87czduUHdZOE56TCFrTn5zS0heZj4hZEZDP1IxfEt4b2tmNi0jTCtkQkN6
aGhIfWVkVQp6R2JMYVFLIzJAbnotYSQrMEQ+R21ITFpFQWxzVD5Wc1dZWHIzPyt7aVN3bVl0bCpr
bTtUKik1dlBMXmVkIUQhaHgKejRUdzFiKDxFclpUOUtfPnRAIVgjQW5aYE1DOyFlUzRNczs2e09k
X0ohXllpK1FJMFBFbit3U0sjV35jPSVLQzg1CnpufSUwRkY+MXNPdThIT2cyez1acSpNWE9rdGts
NSpwRlpFNilPQj1wbkImVnFufTNYfUdoM2NwI2J5PWhFJE5WOQp6MzRpMXApPjxqbWU7djt0KEhR
Ozg8NFFJfU9VSnhweVBMRDBiVH5BX0R5PX4rVGBTMFdvIzhKUFomT0I7WTRyZ28Kei1YbndhMEtR
OUwreWFtfEVqWnt7b0V2Nj8keFV5NSUwVVYzZyNRMUE9dm5tRmNSbHtVITRLI3cyR0NZKmZSZGI9
CktZP1pXR0BjI2tiY2BCUiQKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2Fw
cC9yZXMvc3RlYW0vZWNsaXBzZV9sb2dvLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9sb2dv
LnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwLi41NThjMTBkOTg0YzBhOGJlODU4NGMwODQ5OWNmYjBlMDU3ZDZmYWU2
CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCA5NTYxCnpjbWVIdF9nQi13di1Tck8zbkhrMShrKn1w
TlJ7M2RERkc9YDFxN3JEZ2tDak4zJmxjPDZpdyg1ZEkwR3A2Y3QxUwp6PX1vJEhMS1AkKzNGVTc1
LWhiZiFhXkxmd2I4YC03IT43IzdKflEqbz59KzE/PnVReyhXdXR7ND1xeWIwdF5vdjUKelllRW99
JUJkNkpOYCZDVWJURkx1KUhMJmZBb155P0FKc1JIZTB5K18pbVFDLXVjMyNkWi05LXIwfjhQdEFu
ZmM4CnpfcCE2X2JQKUZOZXZEcE1WMXVBNTViVy00cWJEaEE2T1cmODVGMlZYSCFpTX5BVmpKaXdB
YXIqNml4bGY7YClpfAp6eCE1YEx1eWF+aGMmTCE/N343dThUcz5YRGFmJnhRPyZZfSlxQyNQeFVw
aylSKz5POHNlYipeUjhKb0pURDJPT3IKemxya1NkI3coMFlrcEh5eXQqQEA/YkAtVyRyK3FtM3Nn
UCFgM04oWUQ1aUhsZ0BkV0wkKTA4andqJGZiKj9AI2VpCnoyR1IzaWclSUBVU3shQmdib1VBczd7
WHF1OUhhY3BgME99a3hjK31IUWVnTz5mRm54KnthcEhtM2x8YmxEYTk9PAp6Y2szPVpecD5JRG16
R3gqIW1oYyVKJmZUTl8mYj8jNG5EYEFuS0o8OUJ+eVpQMGhAdVNYODdJPC1fPGhQWGtuSXwKeil3
bE9CUGNBdDhyN292WUhNbnZtXmghUUdja3p6Q0tJZTN0WXNxbjBNZDNZSDE3bnxUbXo4Q3NpaCRC
Vzd4P3p+Cnp0JEFefT1IPCgwcD5yPlFlTzEhNj8lZi1oYCM5QDZCeGRObHdkQlF5akt8RExIVDh7
QUZGUUY2cCEoS0VqVCNLdAp6M3lVaFQmWlMhQkQ1RGtsaWh0PG8pMkZxeGImUmUydDUzfCZJWTAx
XnNqZyEqLWROR15JZCVES0l2c1M1IUlldS0KentPSV5lPTxnaWB1R29jQyYoe2xTb2B1KD1JU1Im
aUdGJGBNPVpneVpYT0tkcWRfO3s+M0FQOC0lMH19Z19fRXxfCnpEZzNkUDNzNDViSVpZXngra2J5
YTN9Pj8taX1ELWFZPEU2OyFeak4jSkkmbSE1Wm1fJFUlbVZ4NjxzK3o+YHJfUwp6TEU5YDhiZVBl
ZHh1eG1leFc/ZjFodGNncWFVVE8/cFdfN3YjfE1mLTZSXllrb2IxTGtaazMzODVFT0hZXjd3Z2wK
ejR0czhRLWBYWHM7O1hPJStRZTBwe0NjZlVQRUpJWVlpZFolKD9tOUVySmBAZ3A8aWNnOyFpLUlZ
PVlnRXptdWpxCnpPOFBRPitAejY4WTtTczhWWk5fKTtOTVRIWGhrWThlP2U4R2FVOUNmXkVgZVU+
Y1AmdXl7U2tkcUo2aktXfD5CLQp6Ulg9bWk4O0JONT88TnFzMX4yRGxiOzV+Skt4dXZ1R0NnWH5D
cmFlSVdLMyU7eX44aW1WYDwlZzdKQjBLOTQ0PCUKemR8Yjl7dXg9UHpLMkhUTFR9clYlM0NYbEF5
PihTUT5mQ1Z0YCV7ZHpXVU5yZEEpMm5hJDQ2ZGpDOS1KSmtVZylUCnozYk9yJmd6dn5wZSNHRDB1
e2tNTStNdSNLPktjKXcmIzVNPU5VOEBGdF9fMjtSOFk/YnV6YzdCUEYrUVhNTyNhYAp6amNlaWxy
VUdSU2tAaGRFc3RUOzh7PzFLfWoqZFR+WHZ4NzBzR3owSkhgJF56WHczcDhIPip1c0pYUHJWdzJE
V3kKelhyPDhpWXZkV0BaXyFwJWtrP0M8Vl9gQiQ+RjxqfXQ7dj9ydk5vdD05bT5ZRkJgez4+Wmpu
RD5SUFBYKjFQIXhPCnp7bH1CTjNUMWRMT0R6TT81JS1rVDR8KERDNT49WXcrY1JCNHFeQCFgK0x6
NUh2OFNMPF9jZzlpc2NeNipDS2MzcAp6e0IwRUhkd2MpVUNMOE9kMmBwa1Z8My1nSnZhbXRWbF42
KXh7TyhRIWJkKzZtTU5DYl5JXjxuPjN9QGJfYT0lb3MKek4/USsleVpQMzJ1ajViQG9VKTJ8aURZ
ZSZGMSkmYFVSdiZfKk04IXRkTCo1aj52Jk96QHt7bUQ0eGshVy1jS3IoCno2aXJfbDt3c15mZ2NR
SCFHdipjZk9aTkdAUlYoY2Jta1JsUlJVcXl7JmBwWTdEU3ppSEtnZUJ1OVFRQFk0Y1VBQgp6eVol
cDZVLURMZlFTVSsoTElId0s5TX1DdzlWWCpCVF8lUEAlISFIOXNmelBfa0YjTVIlYE8tdDhuUypZ
WiRjMUAKekNAP35sU0Y+UzFAemJqY2Rgb1hUUFQ7YCV6XyNjY0hTfGQzWTgtU1dxSz1iWkY9VFg0
JWotR15sZzRNeTJTLSZpCnolSHUxaXBzPzxMd31UJiNaPSZBRWB7Ozlna0stRF9YfGJjMWlANnd9
RnNldmszPk0/fTM1NkVsXmowb3RGdVFlPAp6KT5AZk9Wb3lTISFUXjEleWRARFVLV0tVTEVQYXdl
KG9Jdz9hOTRSWmFZTjhHITA9YTJxfjVaQip+T31HQ3B8V3MKejcjJkQ3UzFiNG1KV0pGUVdQeCpi
dUVAajFfbERiaEdVOVpFIXwwQms7NH1hSVRJJnkxYVJXeTJhPEMzNWp8UXUkCnppaXYrfj80aGh0
WXpwbGVsbmthKXRhUWVGSXFAd1BmQEdNMF91SUN5KGxrcigtWVY3UmtvKzVyenxeO2xQRDQ9Qwp6
Rl5hTGBKZmM2MF4yWDRxQkRAdyZfUCQoJk1eWnlxWGFPJnI8RUZqdlBFeWUkVStKPWpJTmJxIV9+
TzQ/VEt7ZX0KeiVESlgrTmNwfFdFPkY2U2I8ZU1VQV9xWlApRjlsJldAZlUpRU4zKjQ3Z3MwU2B6
QXM3b3VnZCtfNERuK1h1WGMxCnojbzBEZHk1SSpFSFV3Nyl5MzB0Pj9OaUY8V0BpNEYoSEIoTSFv
X1ZNMmwxTU1zO0J2Nm9Vaio8cz0xWioqSlZFLQp6PU5PUTRVJTItfU0hfDxZRm9GMkMqQlkxaDwy
TUBQWiFTU3U/M0ExOUV2dmBzK3tsTT0lQSNPQj1FRCEqMWxQP3IKeiN8cCRUPSttWCF6I0l3a0xY
WFJHTzF5WlFePG1vQ2lQPT1wSVg/PCstaS1ZfCteejg8T2Fvfjw3dkpPbzBDMUY1CnomYTNDPDFp
YSNnM0Fpfk1NNGhwUDBRQ1dkdikqXkM+KVk1Q1VLODRFJGdVZGM4diNoRjEwP1Qkb2FRSFp8Nzd4
ZAp6d1NmcjVTMlk5UztTfU12K3tqemtUSTIyV2QwRVE1Qj4rcXBEN3hQS3cpVG9lQmpSZStpVCRM
bTZPZjdvI1UpPHoKeiUzdDc3dnprRzNnRjt9Tj4pJiVEZ3R5PjE5JX50PUhCU0s5UmYrfT1VZjtU
RSVrZj13dTNZfFI+UkJrdmlRO1FhCnorVTB5VjNeLXV3aS1aNk8lMj1lIz9HZ3wwJmFzY3xBTUZL
Ti11YjhIa2lJQipfdHo7PGQxeVFiTlolTmBATFNfOAp6SD5fUkwoP1coN2ZfZyMwTEFna0dfYnFw
YHM4TEZTJVJnSWp8Q2B3Mk11c0xaM1J+S0gwZXEoO0FxWiYxe19scEgKek1xbXFZeXItK1clKGRA
fElZNG1hdDVURjJuO2M+aWlgbWlXWl9BTW8xT2F6dG5TJChCfEhgTSM1P3t7R1k5ZD9uCno/OUY3
WTk/cztiTHM5TSYxO3MqVGE8OzBJcVAqLWBCNlBwRSlwKnl9K0NOWilLIVR2ZVZ0Wm4+UX5eR21F
dkNFOAp6QE9nQzhHOVlkSzVjbn5iZ3QwbTc4dnFtPz9ednB3UkFUPXN1b2l7KnYmTHM0bVpROVFa
bFFFTElxY1dNeWpyQEwKemZkYSZUVyoyMEcmb00qLTw2SUB3cmBWWHB2TTRXY0xzMUJkN0loJUU3
b202NS0qVTQ/d0RSUF5nUz5PVThuI0IzCnplWkJ6bGA1TlZJc3lGTmMrXnhOaCU1PEZfQkdzT196
clF9cDdqcHM1S2wkJmokNiEoYnlNfW05VTdlYkRJbSl1aAp6ZHJPY1J2T059eHJkRloqYE9+MVpi
MjAqYCNvRiRUbGF6Oy1nKV9FRjtYOEFhSlU9YXFLflFpUUI/M05YSTA4JloKemtCQncyZH1SP1Ql
SFJFSnVAdzBsNiMzYFI2eEltWnZ6KHU4aV82QEV2QzVfTEhqel4tcksoPTRuIzJOM3hXTzcpCnpx
UyErNU83OGk8ZjVAZUpJRVNfO1p9USRNcytISlJjX1RRWDdDTH5BWkpYVVpkZUQtQzY/dldTdjly
NFJHcTZWYgp6JGo7b2JeVkpBQ05hWnJjREk8YWc5JCpxWEMjRCEtNSEqKSpJYExAVTAmPEkzOGVR
VmEoUEEhWXMzKCU1azY1VmkKeilQTmZZdEdMbWU/b2MkMS1PViZ7NT1RPV4lVVEzcl5IMipMV3Yo
QmclWXYxNDc9Qnhod2IpJHRHcCtlUS1gUV5GCnpec1hpM2EzcXFAU2M8NGB8M3BSUE9zeVlRaj4o
QWcpVmNha0RFaHUkeX0yS0p3LXcpU0dfJCktZW9GPDNnO1ZnXgp6d289N1JtSn1gUm5EYUVwPjF1
V00+ZEBFO3JBZCUtPFI3eEZ6KVc5dCEtK1NidW4/N2hKaU9OPj4yajZebkElSmkKej1nYEJGaWJU
TilEWk1RPTcweT1YblVpaD4pZChnP01WYURaPmMqdDg/V0h1SzNFJnAwez57MThYVkhaPl5UdE1Q
Cnp2UmxtZlVzTWgqOFhMQkd7RjhoS05Ud3JPNDRTeVAhWUxyZi1rZ2AyQWtGP31PcV9jfSppaWtE
XmQ2ZzghWHhCMQp6XiZkcWpLfXZVcSNiJnxeWEVnYXBLWXFzUFhxYmBsKjdtUDUjKUw8KyEqX1Y+
Q1koYDska0kjZjBzUXU1NjRYJE8KemN3fDM7XmxBfDc5WX1oSEghPnk7TztYPjlAY3toRExwX2c3
aytoYURMYEB4UGFELW19ZU8kNGlgMEgoI0tVYH5jCnptRjl9e1ApMGY+amh4aHl0OGRyd2d4bEp4
eDUmYEtye1hkOSpOcmdwN2I8SFZNQjtnekhTWnV4K0hWWXY/cHpQPAp6dnd7PDRLejY1aXAzS0t1
aGYtYjVFfFheK2pBQWkjZjQxP2JWWFNOZlNwVWdNUklPNX4+cXxqM1ElOXlFZnVFVCkKemxpdU1s
NVYmVmpUPElhTkZQRz5FTm8oNGJuMSV2aXl6YSpTOXxIOyMlQzBDUnJ8ejQpPlEpfVQrPiMkUk96
aGY5CnpBRn5HdElLOU1qb3JYTFVEMEhBdnBQQXU0Kj81bithbWFuUHQqNmx3bTZVPit4fEV2bntO
PiNAY31mVVpxXkA0cQp6YTV5Mns8QDhDKENhKn1qd3tlNFpSOFkoe150WDNFV1R+TlprNiV4R040
VH5Xd0VOYXhZd2RrREokSUlkeFQzZzEKek9wfnRtaChYIT1JOVpXSXFyTE87ZDZAPkwqdEx3bTlt
R0lhKStzYVIwU3JtMW8zR2VydzNla31ifE1XUU01TDhZCnpWS21ePzBfUkBqcF8lS0RlbFVfSz00
WXpRREg3NEJwTUg9ZypkJiQpRHVWendkKUBwLTcqYldeYkVAUGNtZ1NBSgp6TXIyfGU5VG9OSyUr
VF92bmAha1B3UUsmVkBlZVo/LTwzUE9HdmZVMTk1VS1LOEEpdnRkamN3PjZ2a2V7VSlLa00Keil4
Tj5LNE8qeylGeTNwcEQmJGYha1MlRjMkbjwoTGolNVlifENJa2xxR090NFpTeiMmVzMrIWhIJUZq
Rzh3NHFXCnp4KEVXKT8rYyVsPkZmfHR1OypZVUMhYjh0WTw7OD5TfUhoYnBfNiNPc0A+dyp0XjEy
UF5oMmppeSUpUjdpPnN7Twp6bX1qcG5mfj4qLUxiMW5MLUs4LV47eDd5RDctIV8kP0I3JXhEN0hJ
RjRNdDVDWFYzejNYQmZ0cnIldVErYFhSSSQKelRMYiQjKGVxa2htdmQxbjhVOHs8TnwqSUc2eXlj
aTw8fUxPKTMwIVdaOUxJYGF5WEA4PXp+Zz49SzJOQyZYZT9mCno2NF8zKUVxbk4qYj9uOXE8UnRr
YHhnWVlNUklfI3spOUlGOEgjbVNrRmhpb0UwUUBsRjZlO3xJPEhoQ0NsejZSNQp6UyRjTWpZM2hw
c3IjZ0NhY05gbHd1dFNrVGdHbXFqLSkoRj14ZnRaZVgjWCVNP3t3fn02XllxYmV7aXtHYUgpQzcK
ekplKTNzPGBfaDs0KURNdyZpYnk5I195dk5PP3Q5ck1ndER8NCY4RXdeITN4THJDb3dHVVB4Nis3
ay0oVjYhQWcwCnoobnRIfHhkMGM9b15XcFchX2xLMExPSS1hQnYmTGl4Rm8jPlBDLTNxMFlJSilf
Oz88IzBLTTRPYnFRVl47ck5HNQp6X1c0KW1oSTM7YSpMSkUzI2R9SCRBSz9wK2FXPiM7Mz9pQl8z
VjlsSnJgX2t9NmE+Nl5vJVFiXlRANn55ejkwcHQKei1PTDlKRmM7RW1IazNJYW0zeDMoQVZuISZl
blYzU2hUI1cjaHw8fTd7TmZrZEJCZVJneiNCS3kmbHx5SWEkLUY3Cnp1ZnA4WG1jblJOVllEVXFA
PzkkTHArOS1pPk40Ul9oa1JJa3MoT1htcWVfWnxZN3ZvI1JQLW4pVEFAPUMzaEchQAp6QzF1NF9y
TzwwcHZyYjFvKEB+anpRSUs0ViZzRllYSD5GWX43cChEenJteDhFbGhDO2FLKFV8QmNsZyUmbiFB
KVoKej1GQjxRJGBBSSo2dz49VThDeGAlKUpWNm4kNHMqU0pPJmwzMGFRdE08S0Bsems+ISR+LTw5
O1A4X0J2PWhlVUhYCnpvJHUyUE1RYTZIeG90QG5pMSNSO1FHeHpALXxQYykmUT5nNytrZyVDeXlS
aSM7byU9NkFUNnU4VXVWYkpJQy0/Pwp6cDtSSVRqPTJkQ1luPHwkcyFaUj1MckBQUiNnKzBzZjRh
OCZBUUlBbC1BN0dTY35HNmV0R2M2Z3hYYEsqYlhBZWYKeiVjNVZGUG8xMlh7XkNNXih1bVE/KVV2
SHhAZUw/bVhoMEJ3JnZwRERIRCZ5eTAhbG5FeyRJbGNTUXZjJUMqMzY3CnpxTFVEJHNkXkBJYEZa
S1hvQF9UYjlLSm8/bChzPCglKXd4c3lHOW41NSk1Pyo8MzZoPEJxYkgqRTt1RzhDQW4tTwp6emFy
cWgqWTwpcTYtUzRjZGI5bUBSeDVhNnBgPF9RT3RqJCQjcU1ZQmhZT3dGRzh+QUZnTWNjVio7Y05H
Zzs5ODgKeiQ9cUNtYTRoK05hfTxaWXREUClsdGZBMnpsMTl5WlI8S1gpazhzfXs+fEo2cW5qNXJO
OHZGdXs/Xn41JUl3JipvCnp4O1ZLbV4pYEIhYH1tR3ZsOEhfaHJOYyNgM1ZYM3UtRGpYQjMjbk1Y
a3V0PDdDQFBAOE55NChiRD5QU1F0bU1FSwp6K1pjM01yI007RD5EYUYkSigpQXM3Pk1yY0A1ZkQp
V1BaSE9wdEshIXhiQFI2YSQ8NCglKSlafilYe3lVayVDTEAKemVuQEVTO3ckPz0qb1NmOW5uUUJl
PD5pN3NKPnJzTlE0LWVaX1UrcD4tT2BlaGd2UDFLeWwtNGI3T3spOTJTYTFUCnpnUnYmUXliNXh0
R0ZAYWRPNEs8RWcrPz5ybl9lK3Fjajt5S0FUQmlvQnlTQUNeM3VqPCY4VlAqN29mQmt7aUx1QAp6
aitgZX1gO3ZwKSs7bjFoOWNzcGl6b3s3clN4K3kpa1cjTVdgSCQwciY1TVNNanFVNmojS3BAY1lg
IzFScDBFRVMKemQ3I30tPzhrPT1Xdmo0aFA2bHNTMkE0bmkkbiQ7TEd2QmxBVHgjZyNVVkI/eGtE
X3ZlMjdSN2s9d1V9WDEzckRGCno8UkJ2Qz9+OWAoOT9HKzZlLXt9QTFPPCg/d1RyeGNkP2Z3YTZT
fXl5ck8/PTZwVHFmJk9AK0MrPFJnRXAod2JyTgp6YWNFbCsoQk8mcC1fcmwkM3lYQCNfU1E4YWkk
aCY5eFQ5eGU7d00hRzBTQH1oV25jWlY8XyFqVk8yaXlwQj82RCkKens7JWZYdHd4UTBCdTFNVXNk
NERwVzdwS1VEfiV2bmlAMG5yXl4hakNoR2dVfEM+SVAzUmxEIW4pUXRJITEkWlIjCnpHI29DaDs1
S3RUeFZCfjIjO1hoa08tZyNLeHlWSlcoVlJzd0pDb19TLUJxNyVyYGNTY2g3ZUJaKk9EITA1az1q
bgp6cGBwUDY7Q1chKDNnb3h6cH0lVTwtKDxmS0dRJTE5YlJCSDx2WHhwN04pTjBeP0BrRTl2fHpC
SSYzO3soeGdGciEKejBAQmlZJG5BbXN5fnpDKERVWHFCPX5LZjImQnZlPHw4fmQmIT07VnQhcFlq
dFI4KlI5eVY4bVhvblh+cVdqKCliCnoqVTl+blVleHBiZU8zM0ImMDZeO2BzMnFBcSFeKGB6cWwj
MlYmezckT0p3RGY/PXgxR0hCNXJRUiZxYDVhMVo2Vgp6PlVyayopSDZFY28pYmlHeXlBZnpKOXVH
K2pSI19SKVApTDhWcTw1PTJaemtJbylzOHRKY3VLZ2prdXlAcmRlUXAKenM0NihneDYjUktkYn0+
eCtHRV56M0RhejBGfUQ1WGptWG1Maj94fnBpdGZHezJJWmtJcCtePlBFYD01ayFpVHJOCnpPV05H
Wk8pb2ptdD9wMFd1WGVNamEjJEc+KjtqKFhMP1M+WE4zfTMlJX1NZ0QjZk9zWTU7K3wpYnFOWGZi
cXxHTQp6MjleXyhOQCV4P3Y2fFBHbkkoPE8wK3M9NShtWlNVPmNZeSg/WHVFP3NyM0JeQUl2X1dl
MERnUG5WNlBaUzR4TVkKemhwazBtMHtyfkY3OUxIUU9JQVUqKE5aMnRTdEI3cSEkKHxPZG5kVU5E
bnxpRiE1V253a2pmT3ViZFNRIXdzIXpJCnpPbyR4UXVNWWxadnBla3s/RW1fR19vY0RuZiZIWnpk
MUFLd2ByRShiRnskIT9Ee0QxN1BSZWQ+Wm4qVmA2fkRlJAp6ZTlRR2QtTlItVGtCZ2loZkZnQXV8
Mn5fZk85RipXNVB4P1dSd2xgWnJOY2dyTjF3QCY1OEtoJTh2aUxLTF9oOFMKeikoOGxpSHBIUEMo
a0VJWmN6TmdGIzR0KDkkO2wwamtMT149dj9gWlUpbGYmPGhMSH5ePCZsNkBvQylPKXEpb2skCno7
Xy0wPjlXKX12dV5XWVhCWkFYKHVoRlFQTGZ7MjxSdGNNRC1GRVNkbXYrbTNOSkRxMkN8ajdnc1NR
JiV3YGd5bAp6S044KzhyOzVIMk9xKW9acjlgfilldT8jdHJHLVZkXmR2Jm5xbjtTU3dmODV6QDtB
bWJBd0U5UyFvM2tRNDAyVHoKemVLRmBSaW4pd3olX0RPUmIhQ21FKDQ4flJTPVA/WjF6ZSNzVWEt
RjNHcXhCRSMhVFRubCVZJjFQUDQ1TFBvTUQ9CnopYUdrZWJmcXxLTl8/fmxjPX5qNHhhND9wXyZj
eUFwdFAjUm1PRT1FU0w9VHRCYFk2PVoqOT5CUn5XJT9od1FffAp6LTNRZGpqYGAoPiMwfnZpLUx6
fTRFcmY7YmF4TTtad0VqczM/ZTBlNjhoVVZZdmdGSXZhS3Q9QDJCaXIxWnxQc1YKenU5dWRUY2V0
NmV6REgySmMrYUlfemRrNTxgIUV1Pk5tQHh2T2BNcURkLT9MWHJPJSl3WmV+bDYyWEA5ZlNaJigj
Cnp1VCQpNE5RVS03NGkjWEchNDZZU2ZBcDdgT2h3WT0/TXtwOHI5TUk3O25gVGxUcFFJJCFzU0B5
T2Njcm1ZZ0oocQp6dHJPakArMT1DZmlxU3xXTTt+Y3FZJl5LfkckNFY0bHZAPzZLI0UlNWBgUjdZ
RnFNdDwpWFdTKT5+P1JAO0A1ezMKemdlKXJFIyFSWkpzYCNhKVAyYV8mPUlya1dZeThzRSglTFNY
K1EkdShMJj0+cjRFV0JSZl9HS1lHM3lwSTVjUFFxCnpOYmQ4NiVxWHVgMCZhZjZnSFV1UylPY0Bp
UGl9RndmPytoKm1GJXkwQFN7S1YmQUFwZFlTZXNVUSNvTXkkQWB4Kgp6cX55ak5LO2NkXkZIZkl6
PitrdVF2NnZSOSViPjhJMG9XWnMhVSRhJTlSYTYwJkM2Rm9BPTJGeiZuO1F8RDZhMzgKel9gdHg9
ZH1PKFN2NUFTZjshcyQ4VHdLUTA3YmdYa205MXJFPnM7TDJqSzhNUUNNRzhHR3RydFVhe1h0STF+
VDt7CnozYSRNUUdkM3Vqen5fSlk7T0pNPlBna2pWYH1ySGF2eEswVnZpeFFyU1UrNlVyMipadyot
OFljejxUYCU7bUoyNwp6ZDNrNGlpaip6MGpuaGpBeSYpWCprcztvVG1XVW45QjVgXnFtS1V+fGRm
KlZ2ZW9JI3d6cT1TTHdHb2UhKmtublMKelNpM3R2eld8RmN2YjR6TjYtO3REJFVTUld0KXJfb154
PkFIJWlZYVduN3JKQUR5KjdoQWlUPGJfNXt8Zlg2UU1BCnozTm9RPSp0X209Tkx6dH01YGhWO3Ar
Jk9ybHdwYWQlPWpYQz9KVlYtQkE3Xjw4bnBqdndCRF5LPjhBQns3KW1Dagp6LXU8dk9uKUhPZ2hn
a1QhPSllLWUhPj1mMDg4RShNP0pidlRqYE9abGE/M1h+KkZ3RkhXTF48bU8hP1BAcmM2Vj4KekNO
UEVsbWJNPzV6T25ueEw3Tm5tLXIlPmVlYW0taWxoNVRkezB3bT9hS2wmV3U8UFZlWndqY0ZfQThv
LTZeIz1TCnpOMyNzUEZnX2ptYF8yVzxxKFNRNCFZdUZaK2hpQG1mK2puMyNVSmReIWB5WGJ7Z0lB
b3s8c3MmT2dFVGxvJUl8cgp6UilPVFJpRUJUKHl2UUgmYmNURHJXUmV5dXtfdyk7V015JSNsTmR5
Qj99fVc9QCtKa2hrdjBFZG9LM15VYGtuSTgKekY/bCZfZEFCWDJSOVU7K0A+PjxtUWVPJV5Uemx9
Qj4rPSVmclVDQV4+WVp2QWUjbUw3c1liJCg/ZndhYmBDKTVnCnpLYj5mdj8qIWxGKW14OTk3dVFu
fWl3OCUoQTJ2RHpDaUAyTF95e1N0eTg5eUVENFdQfG43SGQhQUExKElWYFNfPAp6KHVsIyN3PCMr
P0RuPUIpUmt7MjRVVX50ME51I2RZOFchUkhgMyg0TEdPe3d1ZHx2PEQtVEdaSnheIUJOVGRwWXAK
enVmUWdhY3cxNjg8SEYwIU9CaEtgOF9vKXQ+ZkpQcT9UPEZLN0QwRGpocTJ2cXNWciZPVm9Pe2Im
a1ItQ08tS3V3CnptY0A+aFNyR2BWc2J0RV8/KWJlaUBoPWd3LURraj1TcFRqXm9ldH1RemdvQ3pW
b0V9PjxqU3lMK01SJGEmN3poNQp6MlhZdXBaaEB5fkNRa3RfUn4+a1UrLXxZWW9FTSV2UzN3UWs2
XlF8VDchSX51LWp4KSR2O0A+aztId0g9cjAzPTEKelUzbzZNPXNaNjxofWJYU2xTe1gqU251YVhH
fnF+YzJmPkhSYUBrK1VXKEoyI1l0OEw2VnRXXmA3N35zdkh6Y0piCnptJX5sMW1WLUtSKEpTJnop
ZyFLPzw/dilEMyltfko7RjsxP0A8YGQhN3dkPTltWiZgcHROSEhAKH1kSy17PUpaaQp6NXNSOVF4
fEhJWnpAc24+N2VqT0dfJkJtZnkzP3xLeClkenQxS1cpYU9iUTJBaEZyKjlvRXFESWp6TCtNMEV2
MCEKelhNVmh8WkV8eU0+eHJSSDEme007ZXleNk1XPjRWZGhBRjt7OGUzeGZpPHFWMmhqPz5TTzli
WE0/VkhNe0Q7Skc3Cnp1KlR8JGgoQF94VE9ySDNoaj5CJSVheV9Jez8lSlBlPTQ3aFR5U3tvYyk0
PDhmX1l3bUwqZyFTJlIzMkhie04oKQp6Vyk+OFo0dk5iMFVCUkE+LUlkU0UyZkROMC11OD5sXjEw
bWdgcT1lZSQ/JFFQak91MEshdzIxcytkPTY7QyFudzsKek57Zng3NUwrfnVNU1c1OVorJkhAMWs0
fjxSVy1mZCtSbXs1X0Vjb0VqYnREP0Z8bHJBcHE5REZSNnRvO3VVfTdBCnpDb2YmZjY2PU9GdVct
aiYxXkBBVFlFaUdIcj04NFdgREJzP19xK1pLWm5kYyNyLWh1OEVNO3gpYG15WXZia0dlUgp6TnNS
QDRtU190cD1oLUEzPFBPI35VPVU7S01CPmpRXmhkOCRJKElCXkFNe2N8X2QpRmdgUyRqSF53QGtr
a2lhQTwKekRiNEEpKHlWPiYtczt1XjB8VFZGYDdUWWc0R1dAWnd4Ync9aipuNykzcWI0fi1YNmA4
SGo9NTtYWil0cSFgaVBtCnp7T2tFYCt6fHNxTDM3UFVSTEBpejshWTkkZ1VhYlkpZj1Pa28tKU5W
SGVYWVYyNylKfVd+T1B3P35LO0xPPjQtYAp6RjdBRVdySCNkI1E8dzltbl9yJj5lTnBiNGVWYE1h
PCt8dCheb0I5VXVEdl5tVz47THUqb2VIdStfQn5qKkUxZngKejlTWj1XeFdlI01pMFZmRChQZEBe
IUtENmFCTGAjNT07KVpfe0xrLV5MRnF8SjdxTW5YMXU8dnw1V2hfUlBhQl4mCnojYjRKXkZjQk9v
SFZEK2ZnQ0xJRF9YdmwqZisyWkF1a181T0dlWU1NV1MjQEp4ZEYoe2tXWXVPXitaK21oNXpiZwp6
MG15UkwyTXE+fko1dy04TGw/MjtjPWIkQWVLcGxMSmszMXxaV2UqVzVXfD8ldFRwKW5td0ErTmQq
fUR3IzdvdkMKejV2PnRqO1ZpbiFaYUFQKDcxa2Imc18kJj9ZVlFNSGtxP2FZU3pqTnlQMEV0Py1L
Njw1O0NWPHhgWlhJbkZ6MDVYCnpqPTs2WHZnWENhJjxqfk43JENQeGxkWCs1ZHUmS3UoTmxkTHI0
NkdgTjVAO2Q3JHRWY3t9QGpfRDd8el5jcXdISwp6U0AkTyk7ZThHPitAdWdsNGhkQk8+c3xpaHZu
WCl4bHY1ezhRZSZIeThwQCpsN3tiZUdEZWpKQz13T3Y0bXZ0aW8KejxGOWFfMmtZQ3ZseDdeK28l
ZzJFSjUjdmZfWFFaVGR2Tz9DQk1gfCNMM1d2cj1eP28jXj5nQWRnU0UqOVF2WW1kCnp7OFpEJWZO
WExIdylCVldRSERjeEs7bmorNkhQO2FHUXY5SXs3YFo/RCU8UTwqSkBCYlVeZnhycHQ/VX5Nfntr
aQp6XjElei0teygocHpMUV41SEtMdz4mTSt5cEM8NG1zISE2KjhKR141WjY3V2A1KyRPMyFpOERG
cGItUn0wUippQiUKejNGMElhI1E9N3lidH09PXp+O1BlTEtxfWMwVmRrUWwxIV4tUnc+PmwhMURx
bzUyK1JSbW84VWdpfF43ci05emRXCno3TTg0Z3IoZVRRbG9iRUMkQlZjeUk1MXg5PTs2fjZKaTZ2
VEtSPyQjP2Ikdnl2KndUUWNBVG5Ob3xxKWJmcjdpIwp6SiRZJksyRGMoOzJJLXVRaiF3PHtNTDcp
QzBMYGIheGolY3hfc3VyTGNrTml6N2hRYmZVcDd5M2FiaXpMSFd3QmEKenRvSGA0cVpgVUsjO09C
K15CYzBzZCpIPFBuSHU9NTQ5TSMoe1FqVmt7JSMzMlAlQ0N2MShYdzdQPCN5elJAP3ImCnApOE9A
Kl5aITlMXjFvbUl7Q19zJXB8YWlIUmhCNn15ZWBFJEZnNHd+QzNoWUB8MVc7VFo4ODc9CgpsaXRl
cmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfcC5w
bmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfcC5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5k
ZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uNGRiZmRkZTc2NzQ1
YjcxMWQ2NGE4YjNiMzQzNjc0YjBkZTk1MzEzNApHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTg0
MTQKemNtZUlhZzxJNm03ZUJneWg+QylXMCNZS1drfE4jR0E+RUMxY1Eqem9oe3omfnZgRSp8b3It
a1Yoald+PkVWVjRQCnphMGtEPz1SV3NPeGM1RkVBOXM9Ml9uYkwlOyZzbFBHd1VaK1chWEVvQ35p
UkBrVVIyblF0QSowdH1YPEVfeHtGcAp6RmNQP31BYEVgcWJkbDNAaGRfdjB1VTxHRSZiYnl+QFI1
aEt1N2AlUm01MjhtSCVvfU93PlBgM2xmQXE3OHk4RDwKelhFKkRsOWJwT3hnY2MkJV4tOXd4ZDI3
fT9mQ2A7KnhyZm5xUjZ8dipJNCEtNmBvJWpEQkthYWtsfCtzP3MoemtoCnoxXjJ5VHYhPVM3VFN3
TmNrKH1JcTQ8aUdDdGJfI1o2TmJBSEZVWlohQ14yKTZsU3MkUHpAWHFsaE1zb21gcUxkYQp6X25E
dDQ/JWJuM3hHM345dyEzJWhiTCQkUkp9dnxqQH1mVjA3X2V4e2NhMFNNX1U2QyR8ME05QTFwYnIy
ZS1pa0EKek4/XyotQmNZbmg9PXtRcCpPcG1yYClCOS1ldiEqKXBKbFkpR1JKPGBDYzFsYnVYQVpu
NCFaZDF5OzxvKiVmWnJ+Cno0PkM8a0xMezlBe29aZUVifGg7aiklYiYtTW8qVW9teCYyWTIoRnxs
UFVwPj5rLVlvfWd7WnMmRWw8bFYxd3tvZAp6V0J2VTdHT29CZFNVMmpSYVkyQTRUIVNjRjYxd2JP
I357QzhBcHkwfWdQQ2Rqe1RpSmUkQHRSRyZRbzJMVFUja0QKem5gbSVLUX5tdEByYHJjQypGckw9
TGA/Pn1GP1MoYlo3N1dXWXNWc197aWRkZ0t8dnxuR3JzXz9tTiFzKnpnbVpwCnpyZFZPZDd+aGNR
V1FQNERuZj01TnlnUXYzSXs3OW09VXU4V14qfHArRCg9LTNgYmNRZzw+fUk7dDgmM31kKHR5QQp6
ITlVP3J1VStGTSkjVDtsSEEqY2NWbDMxYkVEWTBxNEFaNHYkMjlRXiNxYDZTc0JON1BXamUrUCoh
SHlobytHWlEKemBQTUk3UEtVTiVBeHRYWWJHdH5HWT59RHJpSzE0OGA0USomJi1lMyZIKzU+Tzwr
N1pMWFpvOClMfU92bGdeemAqCnp5NG91OVZoYlBkcnlLS0JSb2dsSDdhVnoyKntqR1Y5ZUdyNGlh
U145fDdeNjJre0tuOWQ8eS1UPTA7T0lVaHJlUwp6Y3laQVQ5fWZvfmktWjNUQys9RkxtWU9sVmwh
cXQzczFRMWBwe0A+RilLPEA4WTx0ZjNPanw3YHlhak17alduYkoKejl+VmF7aUNhRkZgU29aK3Aw
JGxydEl5YjNxfUNkNz8oZmFganM/dzJfTk43V0tQP1FaMyV8JW4zKU93d1QzMEtwCnptISUjbTtx
fkNRKk5gcFheeyV2JmwjUShOcygkdCRJXntIJF8hVCNXN1dpdSorYVhgPUR3eSh8Z0dFRDBFNnkl
SQp6VSgtbDAzbjtlODVRfSplOTBkNyRfZXNjO1hEbjwoVFE5QkY3ayReKC0jI2ttO1pePFY3cCZV
bWdjXiE2YjdmNEwKemomcmNwX31RcVRaNT59SVhYaVlVbm8zbVVVXn1gPXQpeEZXbGp9Klh2YEc5
STs/K2pPM1NyaCMpNlJDYz5PKWkjCnpsRyFoZVpySSZgPHpfI24mMnpyZ3EpV0hadXQlb0JoIzAy
QHZuKFdGbmU4c283bDwwMlY0KCZiNHhZIUYySGVSNQp6OVFZOG9oISRMeitzKlVFZyNEcmhDX31l
QVFzcT9tVWctVD0wX3VINUZVKFdkVD19bHtSWlVnQnp8Qn5ndjc8PDQKekd1MmR2YkBiTClgeGxz
UyZfbD5xNld9Y0ohPXF1PjghPUU4UHhObztMfll8fCl2WXxjcjU0YFJQPWRzNyFaVnB0Cnp7eUtK
K0NjMklyNHJCRUcpa3JANz5mOUdJdkMlXn5yaGxINGd5M3FjUTtpQzc4MExHTWM7dX5xUEk1VWsz
Vzl5eAp6TFRafmlYRiNMRUV6JDRLYlFHYWdvPmQjO14/Yi11PzZoWXx3VUFoQXZedEN0WjhTdn41
X0x+azk0QXJOcGdeZCYKelIqZihEbDQ8TihNMDV+c2pPTmMkeS0kcTxhU25FSTdJIXFZXyt0aTVE
Ny1pMGd+c2hDVzNiNlRRbEJpfGRWMmRCCnpzajR7YWJ5fVdeMn1hdzk2WGo1d0IxPz47emlwKGpD
R3o5PWY/bURobDBxWXxXQD5nTUZVYFRFO0J2TkhuKShJWQp6aXdHazUkYGw5eFpfeHFTTXB8KWpM
NFVISzVuZz5KNmIyPEFXQCQxdkxBdUBRKm4qWkZgYzI9JWBiPS0wJk5ld2wKejxvR0k1SyVSUEJC
UUAxZjR3dDtOLWpsOTdTZ3AzNWBDYn1gVj00ZFh7cnhrZFhRayQ4enkrV0BjWGVReVYkPjdxCnpt
b3NKaCNnKTlQJk9RK0dsXmQpclZOU19CRGtsRVpqKjB3XmBJJHw4PVdSPDBUVmxDP2p2Q0FTRzZE
QH5xNil9fQp6UCROM3lqZkxhVyhhVi1ya1A7R0ghamMmSz9FWWNDSWpeTWItbyQ2Sl5PS3w2K31Y
IVJBX2BqcS12eWlQeztIWmoKemhhMi1ac0xibSZPQjc1S3R2TmJETitgaiFRMmFgQkdgNzBZI0dT
TV56Qk5WQWNVRk5aWmVsJDU0fik4dUUpYXZFCnplNHcqQW0zYTd9dmdjNUo8WDEhUVpIU2tRRE5j
czJXc0hlUUdtQCFzc2c4MWF8NGZ+UVA0U2JZUWlTdXx2alMhaAp6a0VOeT55VH5LdEpUSDg3cHNI
Qm9fbzVqZzxtO1ZscUAxP14wdE1SaSpQZD4lcHx0bXdfd1k3ajlqTyVAcnFaUHAKeiE/fStZdnx0
YUVtPTJkNT9HSUN3M1B2QUJIdGs4e0stJXg+d21mdz1NdzRUWVZIbiV9K0psdXtLTCZZaWhXejk5
CnpaM1A8c2ZXejZoU1hOdURvK3E9fHNyaWM5Mz83YmBjO2V+NjxrV3RTWmpRd2RHXjs8Wip8Vnko
ZHJwOTBDWmJVQAp6ISlvZ2RPOzlmOF5PMjQ7SXxnVzdSLSNjPE1BdCY3PSlqRD4tTEEzZGNMczk+
RlY9ZUYzPEhAPCErJUU8UFp3SGYKejd9JVpFKWM3M0A4ZTxSYTJrZTQjVWxObnhpTkIjUTNBdERK
WEs1Xk8lX09WM0BrQ0lkMTk0UFRgRTZvNF9jK1deCnpvaTBaSTx4fXxZUGM7e3dTT3g0RnFNND0z
bTw3XkZoKVlQR1BPMkYtcSo1R00mJX5qfUFXTXJUZGQyY1UrbzRaSgp6dVpTOU5gcCVidktJKT49
VF4xRXZOcT1gNXJna3xxeSV9QUtQRyZJaSY1VXg2c0d4aE9YbUQlTV5GJEhIenNfQSEKej1ILWk8
UmRPKklEOUJiY2l7Znh9NiZ4YFJqNi1oVG5DJGBZOztseyZGejsxNnpRVy1fa0pFNSV5Zkt9JVcw
ci15CnpIZUxFM0FpeW49JXdPSVhKSkFJQHkwNSgoUElXe3xnSnRKZHVTMkxKVFgxRFE5QHV3bXRt
KH1ESlM4T1NRcmw4Iwp6KUFFKXA5aXoxTF5oKUR8Uzl3PSU7YExuU3ZaV1hYO1hxe1dnSD4/bV8j
RUwpZm9Pd2U2SGNBfDhVe3MkRXVxWmcKenU8Ym1PTnRMQGdEbGAqJChUJTQlby0oeUlQYSZWVnVh
U1AwZUhBUyRydDZYQVJKVGk0SkNNdlNLJj9Lazk8YSZJCnpTY090QF5le0JrRD8yUGd2bUI7RzYt
UXVoO0k/IzFuZDExV3VNczIxPDdhWURCMXdDQWljbnNCZCsqSChfQDRYTAp6RmpmV184Y041eSZa
M2JvUHkxNVllN309Skk1b2o0MW0pY1lobDdeUlZ9QShBdlhyZks8ezhQZ2koPHpuVzJlP0AKellM
Rmo0cHF0MXBiSz9fPG1kITA3O3VKU25YKjx+QVgrUDNUKyt2P3w3fUNtMD1QYDhJWkU4QTxgUlFU
ZlA1SWczCnpNQEpRIylFd3VwcnQ3QjtVVHtIWm1CMVIzc0FNaktgUHlCSTZTOUhXajZ4fnNIe3By
UWk5e3VKdTdzO3Fyc2xANwp6NE59aWloPnBEMHUyIzdZUipAQ3UjSWdwU293S1lNMXlvVUd5Xj5k
VnlMezd6YTF5MV4+UyFCLV5eP3gtJiE5WnsKejBmeHJsS3BwfH1xXmRETGtfZztyJGEzUklXUntm
fGhrbCFKUzFtPFBEXnV0Y1M1cVUzMkU/K2ZaMV5BMzwzWWtnCnpUWDQmXnpEeUZMdmtvfW8mbC1I
KXU0IU4leXh5OX5JYkthK2p3O1klQlMwVUtVSHBLUGtKc1JhNDFFTW91Y3d9bgp6WkRidHUkTlRT
MXgqYk97JGJXTTVlPXVMaFF1KnIjQzY4aVdqc0U7eHJaPH5eR0koQz9Ha0FYNHtlWFE/Yn5UdzkK
ejw3LVZGUm5SQiZATnJHWmRQfW88V0ZUYHpHeG5yb2xxUEM5JG5eZ2xLcXJSNnQkTjMyLTNRe1c3
bWBFVztyOShOCnokeXsoUlp8YC1zMGc/UHt4dStPQkpqaUZkNT1pVUNufDkkcSQ2c3gzMTQrK2hF
Zld9Pyl2a1NBRypBaUItSWM0Ngp6YnE+N253JWJ+bmVHNCVxMDJuKGNsKyVsN0IhcVF+YyF3cE09
UUR5Uk0lc3BPUiZzUUNUWjJea2JKKDtKSmxkNG4KektTTypRKHM+Silra2RsbT0tck1HaE8yaHFK
TH1yOXBnZVNKNyhPeDJjUX5KPSpVX09odGJtbHt4UmZyZzxYKk01CnpmcnhBMCllWFVVKjs4O0Ik
IUFwajZQWGBNJCFDeDw4dilsKHRDS2pweHV7VX40LX1Wd1FKO2BNZl8jOzNoYGRYbAp6RWZ9bXlZ
IW5jeUFSP3tLJkJTPVc/RHZaez9JIWxOTUlpRHROMFNfYUR0Tzw+c0pJYGlxOHRDZDJ0S0REZT9a
ZEAKeiYobDZndmZTWCg1Sn4pT2UobDRgS3pyNyU2PEZOc1JKVmIjZTMpZTIjXm42NyNNakZ+ZkYo
cEowYiVEPyR6all1Cnp7cipIdjgzUE49Vl9qaTJMbXB7fkkmNzkwaTRNZm5Kb3oySSNkPTBMPjNh
TGtrdXpBfiNwTkI9KVRlTj51RlEqdAp6RU4wSyNZTjdaSFQhPFNgQVhpQnl7OGdJUj1JXkdnXnRM
I0xLK0EybiN1KlB6WWo8NDh7PHt8M1ZRek5TcEp+UiYKelI8JFkwU3RMM0dKVWU0fSh9LW1jWkhS
YyNVMHJic2ZJfnJiJWxjWG1QdlZwZkRgaT93QyVTVjgwdnx3M3Qke095CnpzVSs5UjVmLSNST3tz
eHEpQHpHcXc3emtBaFg/dWF3Z29xQXkjZXsrXmYrUGQqPSlAellJX3NDX0Q7eTFtbDtCUAp6ZDR0
dlQjI0BAYDMtYFMtSC1UXjNoU2NqRCEjYXFAQDh0cUc1UEd+JntNKX5wKiYxSFFEa19YYnU7Pmsy
WWx7YHsKej0oMWsxRHt+IX1rVXhzMExrVXE3WW40ZkAoPnolJnR3S0UkX2lyTFdEMU5mVXI7ZFZQ
Z0J0R2I4b1FgNGJYI1NRCno4KDdmUDApejtTPEthbX5aaUdwKXd4UnFtKipMMylkbk88QU9GKXRh
a288SW9ldHtabSswOzc0bHtDWmp7PTkxegp6R0xVfkQjSF9tUHdqbzV3QXlqQWYoYmNrUkkzQl5l
X1Z5PTRfM3NWVnp0PT5DJjZ+MWUrTEAkYjxUfXRTU3VmfEkKelprVkolIWFXRzUrZGJWRFNHeGU1
KiUkVjI/NENyYCstZnRjXktPa3U/ITVzYXA5RTkrT19JSVM2QD0kMTdRNCRiCnpBM0teOTtIQVRw
YCkpJFdZa19kUyl+QGpRTz1zJWFjNCUzJT0wQTRRT1ptNCFOKzIwRylMWEA2JjNVWkxYKS0mVQp6
VkkkbD9yJEJfWHRNNGwkPFgmX08/eTJEbXVRRjF0WHN0VGVHMTVEbXExKk91RkJ1QEZuelNWbGNf
UjVWVmZVRWYKekM+SHRDWHRyUC1HN1JONCRaWkt6OTRQenxwVkZFcGZ7Mnh2MlZRNVVoQmFGfHJG
c3E2Ukp5X1hwa1p7YjtOVXRlCnpvQzBqbVdYckkpVXpkQkQ5dGlDYkUrSWF1ZVEkJig9Y201OXBY
KTxLMkp7SF5yVytTTSNNSStTaVIkam9fbXNMXgp6OCRua19NTCZtMlVic0kjZyNRVmN2aS1BZUZW
Vm1fKShod1dKQj9VMWxZK0U3bGA+OEw1JE13e0BUaEdwQTBibUAKekA3JiQ/NWZZO0l1fD91bnFP
cEVAN0NRRXVsYzY0eld+VEI1MFNRPX0xclhaSWMpOGpXXlVCYighfGImNlYqOClTCnoxQEd4VG1D
SCh7bi12Wl45ZU9ERjhFa1pXdGBHVWl7ZiEhPXJSKFpMKU9UVHhwbGFzSXVRRztSV3J1JXZseG9S
PQp6c3ZgZFA1d3tTVXd5JE9pRzFsTDs0RzleY0ReWWJKKXM3bFUtYllwfURMe2pvb2VoKyZ1MGNM
S1RfZTVLQDJGdkEKentYaHFMYyNOYSRMO3kqcTNIfFcpeks2ZXV4I1ZUbl9EMClTYHdeKyp3cTRI
ISgyODFnaV5RdjF3X1hlVThKYTlnCnpvd0NkaEF7VT4jNUthJmhaKj9uP1dJdjBvZndFI3gyNnFZ
djJwfVp7VX4zckBPR0F2RkJ3UF4lYyNYNEQhO15gVAp6Rkt7NWQ7LT19UWhBK0okMCtjYTdjcUFp
MUBFP2l0Y1k4cXhYPC02dGBuPWgkTHxNVW8yej0wKjd9YXkrMUEkTmkKekhRWVVDdVYjbGt0e1co
RHp8QjVvOHJ6OX17WVVKVFgqI1c7PlB0OFohTjFXSyRHVEJqKXIkTnE/YXV1UyhuMThOCnp6MFgz
RSNLezh7YjtJNVhlN180WldkX1h0d25QSi1TaH5QcWB4ZnlITlhiSzchWWFOZXk3XnRkeGEyb0Y7
dzxIWAp6PWspKmoyN3c0WURLWWhyQTU7MUlFeSVEN1RJRXJkMlEyamV7dmZpVCF8RE1AaHFXQlR1
Z3M7el95KzY1VCY8UzUKeklgSl5qbkV2PSZeMUdXajVIQ3M3VWtEYGpSVFBAK08zK3pSRFFwND5C
b0lATVlvcmQyWUdkQyZGOUVrPEdueHMkCnozOzhNdjd+eXNDUUJgMXBUZ2FiRHEjel5PK187JGtN
fG4hJUF4fEVHWkY/TXA8Q1pEdkEleWxOQWtlZW5WcTt+aQp6Q0Y5QntLa1l5REA3VzswMXRRWmw/
PTVeM09FM2FfV05MYU80KkxXTFFZQl5qdEk4QClgYEppTThMUSUlMVVNYmgKenpQemQtU285UUBi
eXFCUFF5aE0yWkF8WlhoejI1Z2M2OVl7eWpCKkMjWnxgdFpiMjFjZUdNYH01e2ZeYU5LeDROCno2
Z2FHbGIyUXkycFFDVXZkPjsoaz9VRz9jZk9haDhtRl51RzwzUEElT0BHMWlCaFBRdVhyTzNjXlQ4
UHUqQGolJAp6K3JpVGhMaCVnfT8+XlBhMjMkSj1FPTxWKiVmclh3dUk7WHRAXit1MyUweilNb0Js
VXUrWVRKaEUqZ1hvJFg1WCUKejlaaUQ9Pjs2QytALVY/MHRkSkpZeVNnUD0tRT9WT1Y0dF5gcD9Z
Y2VBZzE4aD1hNHNTQFhaeWQldUpoWjZDbVNPCnpXWG9HTkV1UjNxPXFySWxGaXBQMGhqZFpfSHU0
WCVhYW0kUFA/RH5WNWMoZUA+YWB2NXU3SkstaFpxP29nIV5pTgp6a1JII2kyPH1BJSpmK3JYemxx
YlhMZGtBfFJJKW1tazk0NVJ1RGZhMUErK3gyWWBEe1ZNMDVVZXVNRmooe3dfYW8KekFZWWpQJVAm
aFgmc3VBc21VKjROR2YhazdrWVJEdFV0WXE+WWJBQCUoRyp1b2EwZClgWTxrJTh5SVNVUDNffkVE
CnpjWWBCYXM7Oyo1K3s/RjJqMjY7VDElI29Ab2p8Uyl3KTkqP1N9elVRJigkYFdWWHRxcTBMaVhe
QElffDBNQ1NEaAp6a1hGYXM+bEtEKUhZR3twYnFjYDA7P35vYW08cDklUTFWeTxXWV5yO3Z2IXcp
ZyFKOWhFbEhffik4ckUxfDFsaU4KeihnU0BpSlhiaHk2SCleNT95NkNlWGxwODlzLTtjaHxJfHdn
QnhNKGNlbSgtNkdHcnR9QSh+P29NNmooLUsmWHslCnp6YU1wSVUyQCNIU1M7KVpjSnBzSyNWMERH
UEZnc0ZFJClATD9xMUR+e0dkVjFeJT9qYXxLcUUlK3lCTzchWEUwdAp6Nz9wXj1TQF4kKGdlVT0p
dmdqQVNYNyZQKnZWdiheVD01QWAmP1EtY2pZaDJ6RWJAWiV4PWhVUmFuflVoQXo8YjAKeiYyNDNv
UEVOM1VvU2JseVMmKGMzWEhgNyZzfFE0fWtKSWlnYjNURjQyNDJ8JEJaYW4jRm1GaytKYislU2hh
fGQ/CnprVjhQVjJ5YkVaJkZ8TXMzTlF+WlRUZlVIRndBP3ZqSGlaMVVLOWMjPipGWWhpTSUzZk9J
S29Ra1dARnRvZVh3PQp6emdsK1dvI2lBb05FdzZ4WD9xUEZkKnJKeSpSZmB8UzkqPnxWZ0pWIXJl
PGFadypVPmNyditXQi12Tk1Laz9AeF4KekxWb0V1Z0s9RlUtZU9zdUwtWnwzMj8jel9taHd9R1NW
M1lJQVlIfldHSkl9Ji1CZkhTYTk1eTlnbXlMRzlUeGJoCnpqPEtjeVF+ZighaHtLMUx3PyMhcmVs
REE1PCQjPz9tSlVtSUFpNiRhcklsTFMqdzhwJVU/SFMxTURFMFB8OSVBbwp6YTsxQ3dhUVl8SUhA
cEVJUihZQm40WUZfVTAwXiY4K3JlNE9LTmQoa0tYX3AoQCNlb3hRVGBofVRYQHB9dShZaCgKel47
UWkoaEBiby1mSzd+SFBkWFQ4eiZDVTwoKXsmQzBAQVZwcX1Ue19HeFpRRFR1MWs9TXVBUGc0c0s8
fUR+a2BBCnp4Q1l8THUzPUI7PSh7KDY7dXRwO0JWSUhsLUcjWDVVJX5HfDVrVkw9YTJ4TWhQZSZn
QVFWMWtSMkIzSk1qWm9wNwp6bCFMRDgqeVYhdnM3bHZyWmIqXjlhd3ExN3hiamB5ciNFNk9CenA5
VD8rNXtYVFIrc1heKHZ1RFRFZWFKb0MoJG4KemFSZ0QxSlhwOWEyY0A+XkkpLV5OdEtWVkZOXjcp
TEZZeUZLNCRmNUQkem01ZW1fRTQtaHkhPGNOTEpQb2I7YjNtCnppMCVgOWNuMVJXeThJdD4hMVVH
REViPk9UaFlha1BFWnElVHlyODd2MVp3O3NnblZOckxlWTJgcUElVWZDTFghJQp6VTNQeygqJUw1
MnB+Mn5WMjE0QSpCO3AtWHt0d1IjKDhnWXE4Q3d4fmU0OCFLKis7I3VmTjAzX2dSNXcmQENUaWYK
eko9Xi1GVXtxNEVJeXhtTE9DSU5KU0hNc0sxVylgaHo8fUBpLSFCPTJ0c2c7dGNuKkRAcU1ARXJz
ZlEhPGJhOXZWCnopP0Z+YUppOTxJJCFgaXMzQGdnKDxifC1wbSNHZ0tEZiVNQ0ojUCpYa09oKHhh
a0cpTmE8eSNTbjwtKmtAZjBrcwp6VV4yK1MmQ3JpM2NzZnJIQHg2K1dCN1EjY2VrNk9ONWB3Tmd5
N09nPjh9TDIlR1ZXKWJlc1RPRmNBdnUhTTZRMSYKejFEYTlTcTA4PF9Jd0pvQnFMLT4rKExzLTBJ
WDRAcHB3aUx4aG8kI1ZYejtHODBRajVDWE1FMmxGXklpfEtVJT89CnpmZW1rbnMmUjJuSFJ+RCQk
eChlNmFgOEUhRW5PbDFgb248ZkMtZVp9NThsU3IhUjtpeCF0aUFoMWYqQiZ6UjIhXwp6PHY/VGEp
fDNqZCE7VXw5TGs7cUJnPUFeJVheWTQkd1pHWHVrKEVNLVNrI008MjlVUTVZSXslKFpPLT1QZVIk
SXoKeiRFZklPLTBWfj1NejEpNk9QezdlKVE4Y3JiXmd7TzBWKjEqeUVHSGNsWDhZPWooT3dZdXkj
S0B5K2wmLSReSlc8CnpjN1poX0t1KjN1UEpjemwlMW58WkB8eTM0UTNDNjg3ZXY/SWJUOComPVFQ
N2xhcTJzWXdeeilocFU/UTtxazdQJAp6WDc5JEI4ZjVkUUwoNyNWNTl5TiRocDV9MTwoJTI2YjU+
QFIlOU5YKm5maE5OclFPJi07UTJNeXVkR01CYEo7OFkKek5YREY2cSNuO35LI3hiP3tZYVdJLV5J
NnJaOCFtPzdJRl85WkJOZmxGV1gxKUBQSklsY0lYMHNoTyN1WVVQTDQtCno4fGUpSCRmPjg4XnY2
RjAkLVVANkhUN0Atd0d1UyF1P3t4SU9BKmIkIz1hbz5wYF5PIW8ldnx1TTtxQStBOzJYNAp6YiZ4
PnNTSSFuWnRpRGQ1eGU3PVUkenpsZ2lAQXMlez81KlI3LSNlOWhrRWRpPT1aQ29LZVhVcHBMfTM5
aiFOe1IKens4VFhkR2ZPYnExb0srPmljNFAtbXBWXigranF1PG0zYzRQbH5PYH5VRkd3YlpLRTh4
NHxnU0padz1DMGRReHsqCnp4NjlHUF5mOGU8VW1TMWVpVkpkYk5BaVMqZlpYLSEqYG1GVkt8VV8h
cjhVVTtVQld4b3dxfE9hZ2R9KmktY0NPaAp6dFJLVzdZajt8Mj4zc0BfI3swfkZqbm9DVlMtOFBT
JGdsbyRUYnhBfiU1N3R3SWZXJXtCcll4PylHKktjJXV7LWcKem9jZEVaK1JuTFdCTXRJXjc5M19t
Wk1mMTBjSiNCQlUrQDVBTCNHWSVqRkBDfE01Vj1OPCVNbj8ycFJoTXBHZWhHCnpEfnJ0NG50V1F+
NyRnKTJpQWVKMylERWRnZlJFMW5AR2dNMWxkeT5FallXM1FKPk82VmNSNEBCJCFsNlE0Zl4tJgp6
NUtYJGtKI2dxalkpayRmY3M4RSpWIz1IcWVqMG9kQDlPVE1UKjN1KkY8RCt3Vj59WTZGcS07dHkq
OVB8WThOKE8KejdxQDBWKWloUTNNLUEwTDhSQT4+JlhgekxpI25gKiV4SHpJJGxgM31PU0VDRUI5
b3FTRiYxMWBeZUYpU181PG9ECnp6ZH1vQXlJPG1sZFYkM25ufG05d3YxQTIqUntEUkJoNnRGPzs+
O1RJOGJoPGo4akdmV1czUHZUZ2d4WCpqV3g8ewp6ZHFkPWltJHZtJkxDe0Q1PExTfFJkXlo4QVl9
eENkYjZ0R1ZJfSE0M0xSNUIyUXNAV2M0WSo8TiE2QjlRbzdfNHsKenl8TERlMHlYSzJkcGcpP2NH
a1FodmlBUEktPWkoTiRKRmVOXiNOdEwlSkhFMVl0dGMwYk8lPioqeyMwT3EjdHYpCnojbTBxITZ4
T3BhU2xjIXh0MyZoPlVmNUs9V197Wjg/UTIjdXJvemhGSUtBclp8R289QXQ3SUltZnkoPi1eUigm
VQp6KzllYFRpdF9paVp8V15fayVAUXNuRzUwSlJXX2MlKkIoVV9UJnpTUmBVZD9BYXg1JkpYc094
NUM5N2RkbihzT3wKejxmb3smaFpJR1d1STNubGczX0l2SjtOek4rRE4mSSVsMGEoI2N0I28jPm1g
aTFKP2FYRk9ofntCIXxrK2UpNV9VCnolWDFpbUMqelZ8MSpsO0V0Y1Fld1RFT3JxNzRhdEFofjs3
VmVWTF9oYik+fFh2YDdCZ0BNbn1zalR7akVQb3AyQwp6SV8kTzhAKSh7dT43NlFfKFJlYk5wSFNa
PnxHKkViNSNye0JJX1hqcGlWQWpUaH0mWkQpM244fWw0UzcrZCo9I1MKekF2JllVR3JFdmgkIV9i
YldxWE5CRWItcT84JkJlUUImUndWQUJCN2RSZkk0XipjQTYxPD4+OFQ8bUduSyRBU3lBCnphPTNA
UVVQX3xiSng4SmdHT0R0azZfPDZgeyFQSVY5ajBlIWYwc2IjYHFaNk95S1Y3b2EyX1QlLW14Mm80
cFdTUQp6dGhqPmZve2xVcm5QNWRgZykqPXkxWklEUyVfNGt5VllKQVNncl4pO0BgR3sxbHJ7NW1k
IW9sej1QSmB9O3J2c1cKem5Zd0s9czxtUlN3WTUoa1MjVigpcDRyd203Tkd9MnlxX3ZOans5LTxw
K0poQ19sYnFsd292KmtiZCk5PE53IWA4CnpwejhoIUhQS2EtLXRAYWYqTCEyNih7Tkh4TV8lVSEp
UGYxRnsjWnBzVSlMfjhLVSMmdWxkbl8tTjlHJjlOTGBVeAp6Y1N7eUl0TmVuTEk8ZVE1eDw2Z3dg
fnJqJG9XMWQ7N1MpUkdSQmxXfnhWano5OTxeJSUkUXteP3hCYiM9KmkjcSUKeilYSjV8KEV7R1RK
I3pMdUpHYX0yMHFtYk9yc0J8TGpmVlE7aGtZUmBReFpAQj4tP28jT3d7aEBYeyM0I191Jl5uCnpm
NndJY1YjMnBQYGc2MEhzVFJWN0NpcSlVYFBJNnBYSzZufUhyTUMwZCFSd3tsX216aDlraXcoWnpR
a2FuYU1seQp6a3kyRFpVUG1NVkl9PFRgeElAUnJSeTItT1AxMFlDREdaPTQkIVFDPHlZaWA+KDhq
e05gUkhKelV+Yzdge3luX2MKelNHNzY+I3coWlEtcEJ7VyU2NVBjMClPMiQ2WmNFKTZzME9aXnpp
QFhvKn5NQ2I1UTUtO29CMSsmP1hGK2dkTGZwCnpFeXc8OGhZJXlzJXBvbkBiY31DKCFnZ0RtQkQm
ekJENDhmNl99Q2JeaWEza0V7eHxZTkJBRmoxU3Y+e1EtOG5YWAp6WUYjYTt4e0RlPV99V0x+K3Rn
aX4wc2pjVjNYISVrMTFwSGgmfDZFY0pwNURIQ2tocHV4X01lNk1hYjAjKjR0ZD0Kenh0Z2Z3WEAk
M3tGP1U9bWctMHtqe0R7XihNTypyVHFlTjxaQFVjSyYrb2AjRllBQHpyKHZRKWshUClGcEhHflZQ
CnpWfEVHeSp2TGgkY3hRYy1RSn5QP3oydVYwMn5TO2t6QWRmfCpvR0N8dGp5eX04MnFgMjRFMURN
JUQrdFMqY2c+Jgp6Xmh7aTRMRkRne080b2pxZTNrRWNjOV49fm1BSnRZQ24/QVRYSGA3NCQyPykl
VHF2UmEzSnomc0AkQXAkX1BwUTcKek4yIWxuXkhKKSYzcjw8U2dNPCRJSW98WH0kX1hjYkQ4NWJ+
QlJQeThOLT9YP2AtK2kwSStMJGBPazxWK3QmcXpZCnpFUXlRJVhXOy19OzNhOGlqRDFoWCM9KzhS
Y1R0OU90a31gYExSKHk2IyUzKF5WeHF8ZV5MUjJ9NipgP2RwX2tIOwp6diNIb18rcmFGemc8Xztg
e0ozc3piWEY8YUU1YTZQMnRwKjQwZVJ0WUhGS31kOzBFa2xOKTUkJUJIUH1fcnR1by0Kem9fWWFS
M3FBbGZZWG8qNHdrNnQ1O1JvK3NBMVg1KXheJlFOZT56JXJSUV89bk5RMzR6YCpWYWg2VDUwN0d3
bX5mCnpTRHhlQTs3eit4dFpZP1lUeDlJalp3Nj04QHAjX2NEYkdWTXpDNHJZYn1mSjVkPXV8Mj9V
IVFpdn0tXlFEKX0/Zwp6YjxUXnBlWTxnMUJKazYzNEFZV2RyZWBzWShgPXZvWmlaJUZQZXhCPGhm
UWo4eitWRllwRVpLeWdkNCRBNyNCckcKelNgeyFrYGRxbk1ST3NsbmsrR25SeTRSQjN1MVM7OVVk
ZV5ZMiQ5SDBtalBPcUZ1RkM1QHN+Y15PK0BGQ09ZOzYmCnpKLXBnVCNlQDI5X0ZyKXRQPX53V1Ym
M0w2WWIyKVY2aSZiQz5VcD5YMTdMKGNTZiFxTnUpfSNnKSZjQGp5OEMldAp6VH02I0RxakVJRVd+
U0t1ZHNkTllQdSg2I0NFdFhIRW96e2hDNldCXz45YEpNempqPnhRKWFPSGxMRT0yUXtNdysKeiRF
QnQpYFlfNGlnZUVRe1ZffEpBKERROWZWbT4rWFZxUTlSPkBlUDV3ZVR7UHE2TipQJXFnU0g7P0Zf
YCo3KTZWCnoxO0JtQiUyPG9tWkhKMnV5ekg1RS1WSVFPWDlfZ0F2OVpCKkQqYm5GWlpTc30lbnMz
RHRJUnA3Nj53JGxVYlRhTwp6K3N4PyskWEFjUTdUR0RuYm42PlpVKUU5ajNtcW1eaVJoMXcmfFFS
ZC1sPVpRNjk5WnI2PjNEKXVTWXJpQCY2aiYKemQjMT43Tkh0V3AhXkMoWmszKVllNiN1aG9kNFQy
VmN9PWF8P3NZY2BvcDtxVTQ+dTVMZjwoeTRld2pKWD9+SmM8CnozP2d5STFqVGdPbnArdCt1QSFj
YXsySGhoeGleK1VlT0FGaStQJlFaeHImPUlCX1NoT0xQK1prPG5SbEQ9el54NAp6RjZiIWlCUWx8
MSh5Izh8RH4wKD9rYVowZUgyYzlyYH1BZ29eMnFLbGYkcHNAbnA2NFYrTCRXamZLbThJVzdCSigK
enI+MTc9PlJLc2slJXtqaGxhQEt0S0RNeyVFbUw9PkRWdCV1RT9SaF9gbWVsVj18fjN0ZyN6MWMl
YDlhQHY5Vz0qCnpZcCFEbnBPR3BsO1N+YkU+cVNGano1cmZzcmoyQV92e2k8UjkrRTV6X2ohS0ot
MTs7MmNZSXIreXxTIWN1ZzU+Sgp6cU4mPkdXfjcqY0Aqa0FUNzNqSkx0fFRKYVY2OCpKPDw3UmJw
bmw/NFI0cEM2RXQpOUBaUGFlRDVlSHEqVVdlZT8KejllN2ZmeWZreERZNEpCfmpvYCZlTzRvT1FD
YnJWdjwtQjErdz93UFhpUT10Sng7PGRVNStlfWAlTCtWV2dGJkw4CnpvZkc0dThAeFZLajdfJTN8
TlEpXzZBRl44U3lmU0dSOGVZdiRVek5CaEM3dWBod0xrN3U1YHkzX0Ngez5xNU0+Qgp6b3tzSXtl
d2dJMnU4S0l3b3ckb35yRDg/ZS0wbWRuIzRUV2s2bTBhb1Z+c1opd1VnYjhMZSMqTzJidDNRSWtL
cHsKeilJIVFgJUlubTt5KFdlIT5uQ1VRUGx7MDZnSD58alJxeUxaNlVuaUJHK3kyNWUkZ3RpamN0
amBZPjB9Vlg4NmZZCnpAKlFicEBmVm1PWGEoO35jQyFjZHFVaFV9cj1aUXQlYkFyY14qQkVQVVhI
cyR7flVoMyszOFlOZS1YckhaIyZydgp6TVNwc2NEYXQjfnhQTUZqOU07TndWY2d0YWhmUTMqV0Fg
PmtTMlg4ZjlyTUd2ZXhaRX5aY318UjZacUJKNGl9VXcKemFkX1Jibl9yYGZRfWJWOVNELVMraFNY
PE12ZWt9Q1FXWUUmIXh1SmtRRzNRYlpGSnlaMU0+NmJ0cEdTKGp6JTF1CnpQT0NPamI3TWFydXt7
RjkxS0tKMGQzTkRhNkpKTkxRUn5Ob3ojKkUoIUk0YjFkcm4le0NoJFk/Q2s2I1Y2JmoxSgp6QkNg
RHpXZGFOdjdrSTlWQEk2czwtMjBlRnFVT25MaEUoYDduKTExVDwoYGZUeGIrZ0pJLSY1P0htbTlt
Xkt+UU0Kei18MytUQmY+O0VHajUkSWtBakh9d1pScDJmUSQxQj5IdnN0ZEI7UmhAOStmP0QrezFA
bXlqLW5Jcz19TTUkJHB2CnpLVHU+NEFyUWAhK35vQUIzSzclIU9tX05lZDZgMkdiKG97Uy09PHNG
RUVkfGBuYHMrcyh2NjBweG96RlFtKjglSgp6PmxuOU05RCk8ejlMfEYkem1USnotIy0+Q1NAajFR
R0JQXmVAa1h4OUY+VXt+bmhNI3p5N09TV2QpPnBfX1o+U3MKekphJkJKZS01NUUtcH4wfk1qaTtT
bEUjUnY5SThKJW9nRldzV2NNWmQhZG4lV29DMjVkc1c/dUtBXyhncVRERlokCnpXTn50SUBVWmlg
aiRZNUwoflFVRTl7ZTsyPFEjOSZ0OypjLU1WUTNEVU82cnd1JiNLSng1Pkt9MSQzQkhSR3tZbgp6
ajE3ViZkQ2NnUE9RaU9QREckIzZ4YmFYNFU9JnsmZTVzWEY5XzlraD9OWjFKKW5aMVRFZ34pNHNm
YHwmTCNPVS0KejRBOzRZXlMmMilWQ25vMmEhKGhjK19MNmo4fXZoY2psa1htKUAmJF49VT9AYU1O
eGU7IXJuZzlwY3FxU3RDKj53Cno9NDZUWTdvMktCRyhjOUtzSUI/KUJ2aGdBJk51cz8pdypBQktO
bGRScV45WU5ybD5ZWHRLYFRxMWxMPj91SX4wfAp6KSZ+bXFuN3wpM3NlX0RHRXYzVntydn0oZkNH
JThLJGBGbFhsdChgT0omX1lXZTg/QVk2Tj88PzdPISpWTGFpcUcKelUyfHFVS0RacXp0WVo2MWBG
c2haM3FIazFmQlkmfmhPPFA1elNjb1lKKD9kdkk3Mz0rT318TzFNQHtFa2NVSFkpCnorKVVBYzZY
a2xNd1FgaVFkY0E4aHkxPDFpNDw7b0EhVk81aSM+aTEpemlmKTk/JSYlWmNtano5d053RihFc3Vo
IQp6Wkg+NjswPXNJSjc1Mz0yJUdKMmEpZSVOY18kZjRUe0lqeHtrVUtCbjY1MH44cFQ1X3t6Q2Jm
OUIxYFl6VnFDT1MKemtzMz88bjlFM2BXbHh1eyU5VDEmT2VWZW5AfnFGZyNeSClQTyZ2SiN2ZTQw
M0lxRXReSW03IW5FZ3oqI2FVYy0jCnopbXt2Xi0rTlVZenhvWCo9KWQ+PkI9RGFFeyhtRVopcVZe
X3tLQFZhY0hnaEBrcTkzfVJETn4hY3FmJWNfVW9iRQp6TT0hTkJqRVdXKT9AUUNZc2pSNTdUV1le
RVJUV3FkP1hyKzVybzRUOSp+XzBuSzFOUHohRFhWZTBvITApZD4rKXkKeiZ7ZjlqPkUpRztKfDc5
WnRnbysrbFZiP3VTXkQoKChNdVdZR3wjSGAmdzI2bGs1ISRXPC0oKD4pWkU9O3k+X09HCnp2YXso
UUhHOD9iczxQYD8xLX1uKHkoZGopNilYZSF2YSk7ZlI9WCkydmI4Z1JpNTZ7SytEM0oqKkVhaj9s
QVpSaAp6aTYtcj4hMyVSb1drdHs1N3pOTHdEZHNzWkdOKE5+SmwwRCk5Kj98aEs4LV4tPiF1O3Jq
P287IVMmSG1VUXFhVDQKem0qfmYqP1I9O3twRTs3K2lASHM4IyR9eGViYVomP1hSVVF3OU9CPi1v
aXZaQXBHV1UjSUV+RUNXKyl9YCotYnxGCno5RXVUKFcjU1BLU3FQKGViY2B+aGdPKnpwZ1p0bFZJ
OH1SWVlCd0dheU5SNXZpUEBlZ2ElNzxlWGFia2oqby1UbAp6V31OSnRPekMpRE14ekdTWWF3QV9s
SjcmSjAoWV5HMlAwTms0cjdQfG0lbzhKcHJ4Z3lBSWc4T0FtYCVIOGk7Q00KeiFgSWpNT0UlU2Bo
eyQoPi1WMyNMWFlsJlVeQWpAayFzWGRRZy1QcVMqWEckZ0hafHo5TU1XN0BNTHBVZFMrQm9DCnpV
NWQtMzV3Pik7S2Fyc0FJQz94JCV3dnpaP1IpMEFJV25FWkFnYFJHZmVBUkZ4bXVaQUgocms2QE9L
JjY7bXBCKwp6LTVQdz4mZWshbXhVLTxIJlgzS29Mey1Qd14rUCt+PWxJcnpLe25ARlg9MEp7dWZ+
MlNELX5pR3hvVWZpNlB3QSEKejspfjdhRUcjX2t0RUBeMSFnfWgrdWdoYz9EK2tZP0tPZ3BQek1P
czFkP2FHaEJ3TzlFMHQ7UDk1JU5hSCV3TmJECnpSNV8/RSNrNUFxe0xhclc5UFVrY1MhcHc1WDVf
Y1doIS12elpyKzBebnlQWiN7OH5MPFl1YH5LI3ZHeW5RZ2JTUQp6JU4zVD5pNDw9T3dFSylfaGYm
OSR2MkdvY0Y+NnRidD5hd1QlS0tAdHF3dFF5SGpaR21hZDAwbEBSVEhOX31lcCQKekdDPnAzQkU1
M2B3OX5CfG1FK1AjanltMT4lWUpWeTRHazd+QWphclQ7JUtxI2x6T2p9QlR3c3IjNEpxSFQyPClF
Cno8OzRvZUtUNCYjVFgmfH00SzlBdDlCLSZCQURub01NRGZ7OWpwaldIOyg0Wld6SVNzTGxYNGJA
cmh4UD0taEU+Rgp6YSplfmRGblpwMXlrJWJfXyN8QGZxUTUkZzgtQSg+JWohdDtGXm8zfXsxOX1v
P3AhOWFgdGs2YmE5fWdBSSM/QUoKekMmKTdmdzNtWU5TXkp2bS0tX256KzwxK1JzV2F+JjNTM1kk
O2VUVXpobTxIQko9alhUVkx5TC14X2d+fmF9bkdQCno+SSpvSE9eZk1TZmlpNFFIPi1GRG9TUjJU
KE10dmVAbHpxRnk9VXtyRlBhMW09KWMoNUJNSzJjRVpWbk9pUDJLfgp6a0YweUNlOXBISDJBPEpH
UT5OVyVTcUIkUGRBVGw9QGRaJmM/Z1RJdDdRcl8qSGtMQUV8OFJmJG5ENGU5bldkMnQKel9HX3ch
eDtuSlQ3NGpLMG5vYTQpNEZrdG9tSm42aUF9N25TelI2YUg1cEJebFF3TjdlXlAzKTEpNj5eISgl
Z0BQCnptdE52cmw+fVI0dTBRVkFGRXh8YTU1TWpAbmtnU2tLKkx3Zk99cnQlcVNHazI+K3xkVSF8
OSpkJWZnPkBYP3Y1OQp6JnFVeDNRKWcrIXs7ZD1xP3slezduRmArI1ROVCgyLSYoSCNVaTVnT1FQ
UHBhKlpjeHxrMWxDNFZ6Mz0zTVlRbiMKeiRETzdGciNNKFAoWmpqR0BtYXJkcH04ekUoRyV2eiEo
bTFKNlFsd0ZCQDReZHNsPiE1bSNHUiZ2OT4wMXF+ZlJHCnpAWkpHNHVHM1dIRmNNdGU5eCYhTmte
TXA/eTZxSnp7YGIyR2xjWD12N2pVfmZvbllzKDZnUllgckF8ekVAQXp4Iwp6Ry01NzB4YjdoQnVt
dmtkYVYjKThLRThRRzlIM2Vxe1AhSkhlTyVtc3lLPWxARzRBMiVRbWpnVFpFYVdRT20qV0wKej89
MHs3e2QrbVhCUDdGemRMdk4qI3Q+IyVBYUt8N3hiY3hqNk8oanVLS0x0T3IqLUJDRWxvfEVxciVD
JGpXOXxyCnpaRWZDPzN5eHJIMGojbWNwfGNvIV8pPXhfR3w2ZEhyK0h0Q08lVDw8N3Rydj1ARXRg
diZ3NHdoYG4yJUhwUVNwQwp6IVRqaDItcjM4YHd+KV9ycHV9VHRQfnxpPkdIfndNSVVPI00mYDdC
MldecFgrRjllaHY/VkdkRylsZF5xZCRHfFUKem9zQikrPFNRS1N0RFkmV2J6ZW9jUSN1WGVNLUdm
OTMlSVglSndFRnduJStrQUB5IS15I2p9cVFUPCpRPUZyPVV9CnpWbGZIU0R1KEx8V0lBUkgqfGV0
LXY8IWslIWs0MT81QG5OUzN9dzRYYno+djtgXnRyVEQ1dTlLREc3VE1sWj94WQp6SGpjeVRkNjll
enU3b31OQjc8aC1PKzt9bCElMlc+VSRUSldUOGNsTS1NfXdfR3tydl5NMk81JDUhJkZSbUkwNXAK
ekYmKFEwV190anpIQmNlVy1AeEZOLWIqfUByZHRSLTJvQ2VaVz1vWHNrTGpSZSkzRDNtSnctJUI/
M19gOTIqOyRjCno1ZlpLb2YhMmkqTTQ/XzBrRz1NMDJsMlVYRVZJJXU5fHtZYl5Ie2hxcFZ3S3Bg
OSVvKk5oTnNyYzx1VnYkNSRwQAp6VHheaXpQTEBwKys/VWkqYENXT3JCXjJ3bzdfR0FHOEQ+PVB5
KHhrVWpLMGBpTkFXbiVPK3F2NjtrN2JYSTEqa3QKemUhSGRmbXVDcnRRZzUkJj0pa0FucShON0Q/
eChRd0pCPzNtV35WNUVWMVdgdFVgSSR+cU9rSXs3S1c9aygjJmFvCnpjN0kpXmVjTEdLKnVyQmhG
RTBXK1NqaDxSbT8hVkkqbnM/Kng2Rz1+dUU9TDRFXzd1ZTA2RnB+V295VFVlO0lTOAp6XmQqY1dI
IW59YnM8eEk8aD5RO1pEYDs0bXpNTVpEY1lZb3RDa0poaHFSZT81ZkZhbUYyQEMzaG5SNU8oeUYz
VU4KelQteiF5PWxSSyY7QGJZbU8+cEZsOT9peCNFND1IMk5man15emc9PDx1Iz0jcDRJZDRoS2Yj
MnF1Jl81dkgyV1MwCnpeTFkycVhvd0RNY3B6Y2JHZTR+X19DTGQkY1RPRm1aSDNZciZQZT1EXkt2
e2w0VihwNTY/VH55ejNTMDxEZ287OAp6WT5mYDR2bC0yMmojYVlQekRvWXs7WWU3NkpuYGplYFY7
NSo7bythcjBqIU9MI3pCezJPfm54cjNmUUlYWURNVTMKelREaUUyPXBKeT97VHshYWxlRyU+SDZx
fXcmJmhBKyE+aENqUzIrZSg7Kkg+XnJ3Yi1pMyYxVyU4X0w1amh9dyQtCnomQDU5bXdqKDhDQ149
NXxfUz1DZHE0XlFNQ2E+YURsY05VaHJhSlpNWUcpbUxnQ3l2dV9lZG50MTJJJFhhUjkpJgp6YGBh
X1RmJDIqQj5Xal5iJDUhWFEmYzIlbDtVMFVWTDZwMnNnQ1p0cGNJfDF6UzNQaj9GSnEmbE8kIyRn
OFVqQU0KenJjLUozMzlwZmdDTVEzdTlPcHMlc2RyNk5UYmxgZHItcVR0STJYS3B5NFR2NVQoU0Up
IzYqUytGTzhOYyt3QjhkCnprRG9ZOzlWNTZpNS1qIWJxVGxAcmZqNkV+ODJPYGxhc3VhOCokaDBV
Jnp2PSRlbWctfEdidy0xe1kxaDw8bSheKQp6P2o0elUpamkjaUQzUmo9MGB4SVNeeWNNeHN+OXFE
KGBqJXRQZVl8e0pCQl9TeV5hZGJBcVluUTBPP1IlPiRCfkoKekZWWFhQXkl9Sy1NeEpBMWItVSs7
KytKR344Y3hrYG1hYno1QnJoe2VFfDlPPCV1MT0wWnFuKnBlUGMldVlYI1oqCnowYnMrYkZFT2gt
O3VnVDA9TVFlPjw+a3BJQGo4JDBpMV9ifHEhc344dnAqZlJ3SWRmWlpmazE7KkllcHpXQ0A2PAp6
MkRBSDsjenM5RD1JTD1lPjJMYGw7STBuUUFINHRmPGhQdl47alFWJlpvOEFmcmNscGM7O0lpPDl7
TUtWZnxMIVUKenBsfjNjZ2BNaitOYUclbXJSfHkqMDVFRTlabkJhcVVVSThGMVRKUHdlN1NSdiZF
TDB7VldVc1NJM3ZOamNUe0JsCnpCQyp1PnI2KGY2eX41Xn5aKz1sOHhJVz1CYTw1MWk5ZjVHMys2
e0FqN3kxS2M/Q35sNGI+aCE1czU8KDZvbzhtUAp6ezNiQUBMe0l3elBMWXJwKDlxaHdacnp7RTd+
UFJeSVh7O3w7QT1HUk8lPT1yY2dyUG9eTGJtU2VPS3hSKC0pPW8KenBDT25jdnxPZCNOT3BmXyRM
RXhhaz01d2xpYzhQejUjPHMzKmk2fmBfTV5GS0ZaMmlmTyFsUDI4PWVeQTU8WHwkCnpWI2cmczU1
blRqZWs2PXFedmB+ST5UX1AlSmIqYm4zdXRiaGU9SWJCSDlxVWZRdFZ6Y3VKeUJ8aD58JkpOUnZg
agp6UjFDdUd2bUM2RHNCfntlJmhAPz01UX1GPjtDM31AK0IrTHgkK0hmUU50XlRhUHdjYVRURyZo
dm97eW59UXhPUCsKenVuXns/VllIVXJrKVI/QStqKFRAZzdDIzlUbkU5Y3pTMztQO0E5fX15ZTQ0
SUw+VGs+QnNwIWcqWUBUOTc1VHpSCnolPD9iVSQ0SldIXn1UVFNxWWRrb15PcGwlTkZIazZ0dnFI
WkwtUj5pPzY4LXEhTnQrek9aRWFtWjR9b3lqejlrfQp6S3xzP0AqMXNBRmcxIXBiWCNzWGJMV2hH
fTZRJVM4TFZ7ZHB6c3x9bUNXbUw/ViVUTmRNPSQrZUoyandKOE08O34Kej1udXZlO2hvNkB0SUt+
I2x6WUYpY1VaVEM7UGBJRCNsTiZhbndATyRSaDsqNEtLd3chYj98TkRrP1lfYD8hPjZWCnpgTjBI
UG5xWTJzdmZmUkR3Y0p3S205M0hmJldSVllPITY+UjE4RHUpT2o0ekRhfChtNHFobnZmT08+QWVZ
Uz56Twp6MmhDMShGaD1aOU95Skdfd2A4NyEmJSUzJDhuKWFOazlnZHFzdk1fYldBPWlsTWVgI2c8
cm92MS1HbWk3WmAwencKekA0Tzx4SzdFZ3U4fmMqbnJWRTlARTZ2aWZCY0lBfEh7Q3lBOzh6QXdt
enNJPmo9elhZXlEjMC1ydlB+NGUmWCMlCnpUbnlFN3A4aG1HJWp3Qkp6c2NOWmN9IUcqLWs9dWVG
UDhRejMqZGR3bF4oWXhONF4hOWtXPGZaOXBuRE5edyFoVwp6I0g7Qy0/UC1+bEhjaWM5LWtJQWlS
UklVbCNSRGFuYVlgWS0qR0dAYmY+KWF4Tj5DNX1oVnZ4I3ZISk1GbklkeE4KelMjT25QbVBhJlV5
XmR6Uj1hYz4wXiZXQSVuMDkjKzFYS3lVI290MDQmeSZZRHBDR0V3cVVLJENSTFZSfiVDXktUCnpF
KTlLLWQ9dShUamV8VCE/Z2FMJWFSa15GUzUtUzw+Jn1sP0ZPaVh7SkU9UzhiOCtMIzZSdH1LciVC
RWg9UitNOQp6dD9oU2VtKTUrfGpuKWVWOTJvNChARyFLOHFscTw9bCV0PjY9e1VOeypWcT51Y2FB
bSo1Kmk4S3tNTEpsTzApajYKejh4dUdeOXFUPjVaT0gzKHlqIVNTT0JYR013UDFTZTluZGQ7LTJ3
e2VFaWBROGlpfCghSXZ7MjU5QTQ9O0xMVDZ6CnpJcFB2ZDYhcVZzLTB2a0VJSEhgTjc+aT5OSVFz
NTc9eytCS3VwUyM3PVlhYSk+K1VWXmxpVH1PZ0pFRXMpKn5UNQp6MmprI19zS1ApQCU1NiRQKV80
O1MrdGllXmZIezNNZl8qY1o7c3NzIVhGK315RzBiWmpEc0hwKitJanMtdF8pJSEKekl7RCRMSXUm
VDl3KmlVPFZgK348Rm0jQykyP2F8WjlVWkwtJjBvZzlyVkBNN3BfMlM5Vnx4MGZgUDU7cnUlJTNA
CnomdVFMXy19cEE7SmtJVlVYbWAhfVM8ZWRqeypAI1AzRHpfKUZvMFNGVDNkRz1AakFAWl5sWnZ4
I0szcHB4NWFHTQp6QCoycmpgfSY/XzVjTzlTQ25zeURxezVVP2pAez1VMjtFUnZfdTwpKmx5cGJR
U08mNSo/PkZxQ3NOWD5jLWkxYzcKejM+IWgwaUZ4LTM/I3dTVzEoWCFsPWhRbkZQQ0JmUEBmcjZO
STUpczcpPjF5YG43Q1NJMmQqcVA5M3A9PTlKTyF5CnpiN2c2cktwK0k+U058YC0qLSs+Slo3Qlgk
OUdpaWNhWGA+dDkwQ2pUQHBoQilxaGRhdi1NPk5SbDN9O3kyZU1PTQp6alhMblVxcDs7SyZxQnwq
UElyZUF4RUVAQXprQXNjaTUtQGx3fFpZYkdwTzFUcmJEK1RJZHcpcHUzTmB1en5IKHQKenUoS29q
Pjlke3Q9ZVpmdihjTkZEZ358ZmpCMUhQak9ZT35mPk0lUjYmc1gxNWQwTiFCO0NkfXd4ZSUqZjZM
KzgwCnpPQVJJXl81fG5PSEdCMDlxSU00YypMVjBoMyZzbTRFZ09ieEVaVnZzQ0xIXz9eaiQ5djl8
Xk1YKlQ+aUBidEhhaQp6c1A9V3dSPSlVc1MofW9ZbiVXekRrYD5fRUpeRVJ8JSVnY18rcX5WWEpH
MEM4JXwreTdnUVl0KCg9JT1NbDE8UUoKel9iWT11cz48PjRuTEJQOEBmVXpeSlFhPk0lSE8jdj1Z
NmNMdHpuSW8hcF9ZSCVFc1VNX15lLXh2NTYlND9KdkdQCnpuSC11KEVqNGR2PmEjTDdJYjNDKW5q
N3VYREVCem8/QGhUaGxabTJBQ303OD9jc1ErWilxbGx+I14kVTVDQDhudAp6YHt9VD8pQlNPdykm
MmE+KHJ+R2xRV2FfPGxfQkF2Qzl3QUp4OGt0eCNSdVE+Sm0mSiFkWTBCT3FQezxTQnhSTzgKekZr
dnhnQytNPVpfazY8OTMpeGtiOzxKbnlrK1pwYGspVCo2c2AkdSQ1aXlYeTUyUnB2azwtO1o+fiMj
MSpOTTliCno1N3g1SHctWFBLb08maStuN2klT2wzN2t5SVZMcGtFe1JPaTlHYD1gMlRvQnlCMjdX
KUB6Vz9WS3AhXmlXKTU5bQp6Nj57bz42JlZ+JWxObHpudXM1O0Ztd0RQZEoyZnJrcjF8KGBYMXJD
RCNYUE94YnoyNFVRMTdgd3pXS3xjPUEzSHAKendZK0JSNSNATEF0PEs+MTRoRzxfWDdOSmdrQTMk
YHhzIyVqLVA8UHh3IWI5PUVgZTtuQ2p+UHppPldLOVg5PlA2CnpwNnwqY0dsc0lUKkgpbHpqMiYl
SHpqUilCSkw1WjA9LX10OUZARzh2JikjTDUpNyRBZWV0fDUjQ3RzR0lLfGc9Qwp6KDJTbi15cztZ
IWQtZClKYnhCSmVxR0l+RDE8VTFqb0NgdlEkZm5AOV4peGZUQmA+aFo2R1IkVGByP0ZPelY5YnYK
enIyRzE+YTBhJW4jN2dAIWtzTGJeQXwzP3x6SXI1VjxIR0Nabk4/NzRVK3FwciZQaHVVTyUpZS1X
VUooQGZ9dDVkCno4KjQlfVowXnBZSF9KUlhRJkg/eCFaeGE1Y2NAfERrQjhJNXAhY25OZT4xM2w7
Zmh1azhUZ215bn4md0I9MWUqcQp6JjJDbzxNYWU5Z1E/dUR8UXxLS1dPK3tEc3JKVClPLXJUTSlf
dzlpPiUkMlFTQHMyfHhYSyl9OTBANjNtbjwpU2oKek9yT1BnQlZudlohUHQtaWEybz1tK1dTbGI1
QEg1MnRSTFQ3YTNOMmJOKzZKa28yPnMwe1U/ZTRZfnVnUnU1aT4wClhiKk5OU1ZTK3huWUx2LUtE
QCh5OE95Qi1yc1p+dFQKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9y
ZXMvdmliZW1pcy5zdmcgYi9hcHAvcmVzL3ZpYmVtaXMuc3ZnCmluZGV4IGMzZjNjODEuLjcxMTVj
MzMgMTAwNjQ0Ci0tLSBhL2FwcC9yZXMvdmliZW1pcy5zdmcKKysrIGIvYXBwL3Jlcy92aWJlbWlz
LnN2ZwpAQCAtMSwxOSArMSw3IEBACi08P3htbCB2ZXJzaW9uPSIxLjAiIGVuY29kaW5nPSJVVEYt
OCIgc3RhbmRhbG9uZT0ibm8iPz4KLTwhLS0gVmliZW1pcyBicmFuZCBtYXJrOiBhIGN1dC1nZW0g
ZGlhbW9uZCBjcmFkbGluZyBhIHBsYXkgdHJpYW5nbGUuCi0gICAgIERyYXduIGZyb20gdGhlIGRl
c2lnbi1raXQgdG9rZW5zIChkb2NzL2Rlc2lnbi9yZWRlc2lnbi9sb2dvL1JFQURNRS5tZCk6Ci0g
ICAgIGRpYW1vbmQgaGFsZi1kaWFnb25hbCB+MzclIG9mIHRoZSBib3gsIHN0cm9rZSB+Ny44JSBv
ZiB0aGUgYm94LCBmaWxsZWQKLSAgICAgcGxheSB0cmlhbmdsZSB+MzAlIHRhbGwgY2VudGVyZWQg
aW5zaWRlLCBhY2NlbnQgZ3JhZGllbnQKLSAgICAgIzZBRERFNyAtPiAjMkZDNkQwLiBUaGUgc29m
dCBnbG93IGlzIG9taXR0ZWQgc28gdGhlIG1hcmsgc3RheXMgY3Jpc3AgYXQKLSAgICAgdGhlIHNt
YWxsIHNpemVzIHRoaXMgU1ZHIGlzIHJhc3Rlcml6ZWQgYXQgKFNETCBzdHJlYW0td2luZG93IGlj
b24pLiAtLT4KLTxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB2aWV3Qm94
PSIwIDAgMjU2IDI1NiIgd2lkdGg9IjI1NiIgaGVpZ2h0PSIyNTYiPgotICA8ZGVmcz4KLSAgICA8
bGluZWFyR3JhZGllbnQgaWQ9InZiQWNjZW50IiB4MT0iMCIgeTE9IjAiIHgyPSIxIiB5Mj0iMSI+
Ci0gICAgICA8c3RvcCBvZmZzZXQ9IjAiIHN0b3AtY29sb3I9IiM2QURERTciLz4KLSAgICAgIDxz
dG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzJGQzZEMCIvPgotICAgIDwvbGluZWFyR3JhZGll
bnQ+Ci0gIDwvZGVmcz4KLSAgPHBhdGggZD0iTSAxMjggMzMuMyBMIDIyMi43IDEyOCBMIDEyOCAy
MjIuNyBMIDMzLjMgMTI4IFoiIGZpbGw9Im5vbmUiCi0gICAgICAgIHN0cm9rZT0idXJsKCN2YkFj
Y2VudCkiIHN0cm9rZS13aWR0aD0iMjAiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KLSAgPHBh
dGggZD0iTSAxMDcgOTIuNiBMIDEwNyAxNjMuNCBMIDE2OCAxMjggWiIgZmlsbD0idXJsKCN2YkFj
Y2VudCkiCi0gICAgICAgIHN0cm9rZT0idXJsKCN2YkFjY2VudCkiIHN0cm9rZS13aWR0aD0iMTIi
IHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3Jn
LzIwMDAvc3ZnIiB3aWR0aD0iNTEyIiBoZWlnaHQ9IjUxMiIgdmlld0JveD0iMCAwIDUxMiA1MTIi
PgorPGRlZnM+PGxpbmVhckdyYWRpZW50IGlkPSJyaW0iIHgxPSIwIiB5MT0iMCIgeDI9IjEiIHky
PSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjZmY3NThiIi8+PHN0b3Agb2Zmc2V0PSIuNDgiIHN0b3At
Y29sb3I9IiNkYzM2NTgiLz48c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiM2MzE1MmIiLz48
L2xpbmVhckdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0iZ2xhc3MiIHgxPSIwIiB5MT0iMCIg
eDI9IjAiIHkyPSIxIj48c3RvcCBzdG9wLWNvbG9yPSIjMjAxNTFjIi8+PHN0b3Agb2Zmc2V0PSIx
IiBzdG9wLWNvbG9yPSIjMDgwODBiIi8+PC9saW5lYXJHcmFkaWVudD48L2RlZnM+Cis8cmVjdCB4
PSIxMiIgeT0iMTIiIHdpZHRoPSI0ODgiIGhlaWdodD0iNDg4IiByeD0iMTEwIiBmaWxsPSJ1cmwo
I2dsYXNzKSIgc3Ryb2tlPSIjZmZmZmZmIiBzdHJva2Utb3BhY2l0eT0iLjEzIiBzdHJva2Utd2lk
dGg9IjIiLz4KKzxjaXJjbGUgY3g9IjI1NiIgY3k9IjI1NiIgcj0iMTQ0IiBmaWxsPSJ1cmwoI3Jp
bSkiLz4KKzxjaXJjbGUgY3g9IjI2OCIgY3k9IjI0OSIgcj0iMTM2IiBmaWxsPSIjMDgwODBiIi8+
Cis8cGF0aCBkPSJNMTUxIDE2MmExNDMgMTQzIDAgMCAxIDEzNS00OCIgZmlsbD0ibm9uZSIgc3Ry
b2tlPSIjZmZlOGVlIiBzdHJva2Utb3BhY2l0eT0iLjU1IiBzdHJva2Utd2lkdGg9IjMiIHN0cm9r
ZS1saW5lY2FwPSJyb3VuZCIvPgogPC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzb3VyY2VzLnFy
YyBiL2FwcC9yZXNvdXJjZXMucXJjCmluZGV4IGI1ZDRlZTcuLmYzY2FlMGIgMTAwNjQ0Ci0tLSBh
L2FwcC9yZXNvdXJjZXMucXJjCisrKyBiL2FwcC9yZXNvdXJjZXMucXJjCkBAIC0xLDEzICsxLDIw
IEBACiA8UkNDPgogICAgIDxxcmVzb3VyY2UgcHJlZml4PSIvIj4KLSAgICAgICAgPGZpbGUgYWxp
YXM9InJlcy9zdGVhbS92aWJlbWlzX3AucG5nIj5yZXMvc3RlYW0vdmliZW1pc19wLnBuZzwvZmls
ZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzLnBuZyI+cmVzL3N0ZWFt
L3ZpYmVtaXMucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVt
aXNfaGVyby5wbmciPnJlcy9zdGVhbS92aWJlbWlzX2hlcm8ucG5nPC9maWxlPgotICAgICAgICA8
ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfbG9nby5wbmciPnJlcy9zdGVhbS92aWJlbWlz
X2xvZ28ucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNf
aWNvbi5wbmciPnJlcy9zdGVhbS92aWJlbWlzX2ljb24ucG5nPC9maWxlPgotICAgICAgICA8Zmls
ZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay01MTIucG5nIj5yZXMvdmliZW1pcy1tYXJrLTUxMi5w
bmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTI1Ni5wbmci
PnJlcy92aWJlbWlzLW1hcmstMjU2LnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJl
cy92aWJlbWlzLW1hcmstMTI4LnBuZyI+cmVzL3ZpYmVtaXMtbWFyay0xMjgucG5nPC9maWxlPgor
ICAgICAgICA8ZmlsZT5yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZp
bGU+cmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2Vj
bGlwc2UtY29udHJvbHMuc3ZnPC9maWxlPgorICAgICAgICA8ZmlsZT5yZXMvZWNsaXBzZS1pY29u
LnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2VjbGlwc2UtcG93ZXIuc3ZnPC9maWxlPgor
ICAgICAgICA8ZmlsZT5yZXMvY3JpbXNvbi1iYXR0ZXJ5LnN2ZzwvZmlsZT4KKyAgICAgICAgPGZp
bGU+cmVzL2NyaW1zb24taG9zdC5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMv
c3RlYW0vdmliZW1pc19wLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfcC5wbmc8L2ZpbGU+CisgICAg
ICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pcy5wbmciPnJlcy9zdGVhbS9lY2xpcHNl
LnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2hlcm8u
cG5nIj5yZXMvc3RlYW0vZWNsaXBzZV9oZXJvLnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxp
YXM9InJlcy9zdGVhbS92aWJlbWlzX2xvZ28ucG5nIj5yZXMvc3RlYW0vZWNsaXBzZV9sb2dvLnBu
ZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2ljb24ucG5n
Ij5yZXMvc3RlYW0vZWNsaXBzZV9pY29uLnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9
InJlcy92aWJlbWlzLW1hcmstNTEyLnBuZyI+cmVzL2VjbGlwc2UtbWFyay01MTIucG5nPC9maWxl
PgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay0yNTYucG5nIj5yZXMvZWNs
aXBzZS1tYXJrLTI1Ni5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvdmliZW1p
cy1tYXJrLTEyOC5wbmciPnJlcy9lY2xpcHNlLW1hcmstMTI4LnBuZzwvZmlsZT4KICAgICAgICAg
PGZpbGUgYWxpYXM9ImZvbnRzL1NvcmEudHRmIj5mb250cy9Tb3JhLnR0ZjwvZmlsZT4KICAgICAg
ICAgPGZpbGUgYWxpYXM9ImZvbnRzL01hbnJvcGUudHRmIj5mb250cy9NYW5yb3BlLnR0ZjwvZmls
ZT4KICAgICAgICAgPGZpbGU+cmVzL3NvdW5kcy9uYXZfdGljay53YXY8L2ZpbGU+CmRpZmYgLS1n
aXQgYS9hcHAvc2V0dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuY3BwIGIvYXBwL3NldHRpbmdz
L3N0cmVhbWluZ3ByZWZlcmVuY2VzLmNwcAppbmRleCBkNjlhOTEzLi42MDIyYjI1IDEwMDY0NAot
LS0gYS9hcHAvc2V0dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuY3BwCisrKyBiL2FwcC9zZXR0
aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5jcHAKQEAgLTIyOSw3ICsyMjksNyBAQCB2b2lkIFN0
cmVhbWluZ1ByZWZlcmVuY2VzOjpyZWxvYWQoKQogICAgIHNlZW5XZWxjb21lSGludCA9IHNldHRp
bmdzLnZhbHVlKFNFUl9TRUVOV0VMQ09NRUhJTlQsIGZhbHNlKS50b0Jvb2woKTsKICAgICBlbmFi
bGVIZHIgPSBzZXR0aW5ncy52YWx1ZShTRVJfSERSLCBmYWxzZSkudG9Cb29sKCk7CiAgICAgdWlT
aG93SGludHMgPSBzZXR0aW5ncy52YWx1ZShTRVJfVUlfU0hPV0hJTlRTLCB0cnVlKS50b0Jvb2wo
KTsKLSAgICB1aUFjY2VudEluZGV4ID0gcUJvdW5kKDAsIHNldHRpbmdzLnZhbHVlKFNFUl9VSV9B
Q0NFTlRJTkRFWCwgMCkudG9JbnQoKSwgMyk7CisgICAgdWlBY2NlbnRJbmRleCA9IHFCb3VuZCgw
LCBzZXR0aW5ncy52YWx1ZShTRVJfVUlfQUNDRU5USU5ERVgsIDQpLnRvSW50KCksIDE1KTsKICAg
ICB1aVNvdW5kcyA9IHNldHRpbmdzLnZhbHVlKFNFUl9VSVNPVU5EUywgdHJ1ZSkudG9Cb29sKCk7
CiAgICAgZGlzcGxheUhkckNhcGFiaWxpdHkgPSBzZXR0aW5ncy52YWx1ZShTRVJfRElTUExBWV9I
RFJfQ0FQQUJJTElUWSwgdHJ1ZSkudG9Cb29sKCk7CiAgICAgaGRyVG9uZW1hcHBpbmcgPSBzZXR0
aW5ncy52YWx1ZShTRVJfSERSX1RPTkVNQVAsIGZhbHNlKS50b0Jvb2woKTsKZGlmZiAtLWdpdCBh
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
