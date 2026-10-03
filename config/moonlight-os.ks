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
NAME="Moonlight-OS"
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
echo "Moonlight-OS DualSense check"
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

# Recovery/debug consoles use the Moonlight-OS black + red theme.
cat > /etc/profile.d/00-moonlight-red-terminal.sh <<'THEME'
# Moonlight-OS console theme: black background, red foreground.
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

# AirPods Pro 2 are playback-only on Moonlight-OS.
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
    Identifier "Moonlight-OS Apple SPI Touchpad"
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
    result, active = [], False
    for line in text.splitlines():
        clean = re.sub(r'[│├└─┬┼]', '', line).strip()
        if clean.startswith('Sinks:'):
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
        command(['sudo', 'brightnessctl', '-d', device['device'], 'set', str(percent(value))+'%'])
    elif action in ('center-reboot', 'center-poweroff', 'center-suspend'):
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
MOONLIGHT-OS SETTINGS
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
GXRFWHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAIABJREFUeJzs3Xec3Ad95//3zFZt
VZdlS7Jk44Z7pRgHbLAxzeDQDBwkIT3hcnD5EUhyvySkECCdJJdy98tdQg5CkqMlgE1vARtccO9Y
tnrfou07M78/1pI72l1pZ1b7fT4fD9DM7ndmPyPr8ZA+r5n5Tqm9vbMWAAAAYEErN3oAAAAAYO4J
AAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAA
AFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAA
AgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAA
AAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAU
gAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAA
AAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAA
BSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAA
AAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAA
QAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEI
AAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAA
AFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAA
AgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAA
AAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAU
gAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAA
AAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAA
BSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAA
AAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABdDc6AEA
gCOvubk5PV1d6e3pTXtba1paWtPe1pa2tta0trSmtbUlrS2tGR8fP3ibyUol4xNT18fGxjI4NJSh
4eEMDQ1naGQ4w8PDjXo4AMARIAAAwFGqvb09x6xcmdUrV2b50mVZ3NOT3p6e9HT3pKe7K+VSKe3l
pjSXyimXSmkuTb3wr6U89etEtZokmaxVU6nVUqlVM1qtpFqrPe3Pq1ar2T80nN1792T3nj3ZvXdv
du3dk12792Rff18qlUp9HjgAMCul9vbOp/9bHgCYN7q7OrN+7bqsXrUqx6xclQ2rj8265SvT3dya
7pbWdDe3pLu5NYuam9Pe1Jz2clNaUkptdDy1sbFksppatZLx0bEMjo5kcHQ4faOjGZqcyFg5GatN
xYCJWi2T5VJqzeWU29rStmhRyu2tmSyXMlGtZqJayUhlMhOPHn9ApVLJw5s35e8+9rFMTk424rcI
ADgErwAAgHmou6szG9atz4nHH58LTz41pxy7JstaF2VpW3uWtbWns6klSVIbHU+1fzC1vv2pDu9N
bWQko/uHcuvO7bl959b8YLAvm4YH88jwYDaNDGb32Mis5mltbU3nokXp6e7J8qVLs2LZsix79NdV
y5anrbk5a1Yfm5aWFgEAAOYprwAAgHmgVCrl+DVrc96zT88Lzzg7zz5uTVa1d+aY9s60NjUlSWoD
+1PtG0x1YDDVvv2pDezP2Mhwbu/ble/t3ZGb9u7I3QN7snFoIJVneBn/XM2+uLc3lcpkBgb31+3n
AgAzIwAAQIOUy+WsO25NXnzu+bnivIty6spjsrajO02lUmpJakMjqe7am+revlR39aU6MpKJajXf
27M9X92xKd/duzW39u3OWMUz7gDAoXkLAADU2Ya1a/PGSy7NledemJOWrkhXc2uSWmqTk6lu3Znx
7btT3bUntbGJJMmOkeF8YftD+eqOR/LNXZszODHR2AcwR2q1pFRq9BQAsHAJAABQB4va2/OG516S
a1744px9/Pp0NrcmtaQ2MZHK5m2pbt+dys49qU1WklotfRNj+eK2jfm3LQ/mK9sfyeSTTrq3EFn+
AWBuCQAAMIfOftZJ+ZkXvyxXnnthlnd0JklqlWoqm3eksmlbqrv3JtWpd+ONVSu5dutD+ejGu/LN
nZvr+j5+AGDhEwAA4AgrlUp583Muyc++7FU5Y/0JaXr0qe3a4FAqm7en8vDW1MYnMvUSgOSBwb78
40N35Z8fvid7xmd3ln4AgEMRAADgCGlpbs7PXvrS/PyVr8yaFcckqSXVaiqbtqf68JZU+gaSg0/q
13LD7m35i3tvzhe3bYzn+gGAuSYAAMBh6mlrz//7itfmmhdfnp7u3qkvTk6m8vCWVH6wKbXRsakF
v5ZMVKv59Ob78t/v/X7u7N/dyLEBgIIRAABgltqamvLOF70sv/Sa16V7cW9qtSTj46ls3JLKQ5tS
G59MUkstSbVay2e3PJj33/Gd/GB/f4MnBwCKSAAAgBlqa2rKu57/krzjNa9Lz8rlSZLa2EQmH9iY
ysNbk0olB57yryb5900P5AN3Xp8HBvsaOTYAUHACAADMwOtOOycfePNPZOX6dUmSWqWSykObM/nA
I8nExNRBjy7/N+/dkV+/5Zu5ae/2hs0LAHCAAAAA03DWkpX58OvemnMvfl5KTU1JrZbKtl2ZvPvB
1IZHc/DsfrVk68hgfu/27+RfH77Xyf0AgHlDAACAH6K3pS0fvOyVeeMrX52mxd1Jkuqevkze+UCq
/YOPHjW15k9UqvnwPTfmw/fclJHKZIMmBgB4egIAADyDV6w7KX92zduz4vSTUyqXU5uspHLvD1LZ
uCW16oHn9qd+vX3frrzze1/O7X27GjcwAMAPIQAAwJOsbO/Mn19xda58+ctS6uxIklS3787kHfdN
faTfwdf11zIyOZHfu/36/H8P3JpKzQv+AYD5SwAAgMd5zfEn58/f+OPpPf2UpFxObWw8k3c/mOrm
qRP5PX75v6tvT37hhutyV/+ehs0LADBdAgAAJOlqacn7n3N53vajr015xdIkSXXH7kzcem8yPp7k
seW/llr+x3235rdv+4+MVyuNGhkAYEYEAAAK74Jlq/N3V70pxz//OSm1t6ZWraby4KZU7tuY1KpJ
Hlv+d44O5eeuvy7f2rm5cQMDAMyCAABAof3Ys87MH7zhbWk/7cQkpdSGRjJxy12p9Q3mwAn+Diz/
3929NT/1nc9n+8hQw+YFAJgtAQCAQmpvas4fXPTivPWqq1NeuyqpJZUtOzJ5x/3JxGSevPz/w4O3
59du+YaX/AMARy0BAIDCWd/Vm3+47OqcddmLUl7em9Rqmbz/kVTue+jRvf+x5X+iWs27b/pKPvrQ
XY0cGQDgsAkAABTKBctX56Mve0NWXXxRSl0dyWQlE7fcneqO3U9Z/vdPTOSnr/9cvrzt4YbODABw
JAgAABTGK9c+K3/7imvSddHZSWtzasNjmbjxjtQGBp+y/G8b2Z+3fPPfckffrobOTCPUkpQaPQQA
HHECAACF8LOnnpvfe/FVab3wrKS5nFr/4NTyPzL2lOX/rr49eeM3PpUdo072V0yWfwAWJgEAgAWt
lOR3z39hfv6Sy9N87mlJUznVXXszceOdSaXylOX/9r6def3XPpW946ONHBsA4IgTAABYsEpJfv/8
S/MzL3xJms85LSmXUt25NxM33pFUq09Z/m/YvS1v+danMzA+3sixAQDmhAAAwILUVCrlz55zed58
8YvSfM6pSamU6tZdmfj+3U+7/P/Hzi15y7c+k+HJiYbODQAwVwQAABac5nI5/+Pil+XVF1089cx/
Kalu3pGJW++Z2vaftPzfvHd73vofln8AYGETAABYUEpJ/vDCy/Lqcy9K89mnTi3/m7Zn4rZ7n3b5
v6Nvd675xqezf8LyDwAsbOVGDwAAR0opyYcuvCxvPe95aT7vjKn3/G/f84zL/70De/P6r38yfeNj
jRwbAKAuBAAAFozfPf+FeftZF6X5gjOnPupvd18mbr7zaZf/HaNDedM3PpM9YyMNnRkAoF4EAAAW
hF969gX5ubOek+bnnpNSW0tqA0MZv+npz/Y/UpnMj33rs9k8PNDQmQEA6kkAAOCod9W6k/Lfzro4
TWefltKittSGRjPx3VuTicmnLP/VWi0/953rcvPe7Q2dGQCg3pwEEICj2nnLjslfPOeKlEulZGg4
tfbWTHzv9tRGx5+y/CfJb936rXx+64MNmxcAoFFK7e2dtUYPAQCzsb6rN1+44posbVs09YVaLQf/
Unua5f+Tm+7Lz37n2jpPCQAwP3gLAABHpUVNzfm7F7xi2sv//QN788s3frnOUwIAzB8CAABHpT+4
8LKctWTl1JVDLP8D42N563/8W/ZPTNR5SgCA+UMAAOCo8zOnnJNrNjx76sohlv+klnff/NX8YLC/
rjMCAMw3AgAAR5ULl6/O+875kakr01j+/+Xhe/LJR+6r64wAAPORAADAUaOzpSV/+dyXpqVcntby
/8hQf95789frPicAwHwkAABw1Pjg+ZfmhO7F01r+q7VafuGGL2ZwYrzucwIAzEcCAABHhVeufdbU
+/6nsfwnyf+8/7Z8d/e2+g4JADCPCQAAzHvHLOrKnz3n8mkv/1uGBvOBO79T3yEBAOY5AQCAee+D
F7wovc2tT7v8P6Z28Jf33vJ1H/kHAPAkAgAA89qr1p6UVxx34jMu/7XHX68ln3jk3ly39aG6zggA
cDQQAACYt3paW/P+835k2sv/yOR4fud2L/0HAHg6AgAA89ZvnX1JjlnUNXXlEMt/Usuf3nNztgwP
1nVGAICjhQAAwLx0xuIVecsJp09dmcbyv2V4MH99//frOiMAwNFEAABgXvq9816Ycqk0reW/luS3
b/tORiad+A8A4JkIAADMO1etPSnPX3nctJf/e/r25tOb76/3mAAARxUBAIB5pa2pKb95zsXTXv5T
Sz545w2p1p78sYAAADyeAADAvPJjJ56ZdR29me7yf3vfrnx+64P1HhMA4KgjAAAwb7Q3Necdp56f
6S7/SfKhO2+I5/4BAA5NAABg3vjJZ52V1Ys6D14/1PJ/d/+efHHbxjpOCABw9BIAAJgXOptb8o7T
zj94/VDLf1LL39z/fc/+AwBMkwAAwLzw4yeemeVti5JMb/nfPTqST25y5n8AgOkSAABouJZyOT91
8tlJprf8p5b8zwduy2hlss6TAgAcvQQAABruNWtPzpqO7mkv/xPVaj668e76DwoAcBQTAABouJ8/
9dxpL/9Jcu22h7JjdKi+QwIAHOUEAAAa6gUr1+SM3hWZ7vJfS/KPD91Z3yEBABYAAQCAhnrbiWdm
Jsv/I/v7842dm+s7JADAAiAAANAwS1rb87JjN0xdmcbyn1ot//zIvanWfPgfAMBMCQAANMw1609L
W1PTtJf/JPm3LQ/UeUoAgIVBAACgYd58wrNntPzf3b8n9w7sq/OUAAALgwAAQEOcv+yYnNK9NNNd
/pPkM5sfrOeIAAALigAAQENcvfbkzGT5Ty35t61e/g8AMFsCAAB1Vy6V8qo1J8xo+d841J8HBvvq
OSYAwIIiAABQd89ZvjrHLOqa9vJfSy1f2v5wfYcEAFhgBAAA6u5Va06a0fKfJF/duamOEwIALDwC
AAB199LV6x+9NL3lf3RyMt/etbWOEwIALDwCAAB1dWrv0qzp6M50l//Ukhv37shIZaLOkwIALCwC
AAB1denK4zOT5T9JvrvXs/8AAIdLAACgrl68et2Mlv+klhv37KjfgAAAC5QAAEDddDS35KJlq5NM
f/mvVmu5aZ8AAABwuAQAAOrmvKWr0lZumvbyn1pyz+C+DEyM13dQAIAFSAAAoG4uWrZ6Rst/Lclt
fTvrOiMAwEIlAABQNxcuO2ZGy39Sy939e+s6IwDAQiUAAFAX5VIp5y9Z9dgXprH8p5bcPbinrnMC
ACxUAgAAdXFS95L0tLROXZnm8p/EKwAAAI4QAQCAujhr8YqpCzNY/veMj2b3+Ehd5wQAWKgEAADq
4rTepTNa/pPk4aH+us4IALCQCQAA1MVp3ctmtPzXarU8MjxY1xkBABYyAQCAunh277KpC9Nc/pNk
0/BA/QYEAFjgBAAA5tzilrasbO+Y0fKfJJuG99dvSACABU4AAGDOre/snfHyn1qydUQAAAA4UgQA
AObcus7uRy9Nf/lPatk9NlqvEQEAFjwBAIA5t7ajJzNd/pOkb0IAAAA4UgQAAObc2o7uGS//tVqy
TwAAADhiBAAA5tyaRV0zXv4nqtXsn5io35AAAAucAADAnFvevigzWf6TZH9l/PGHAwBwmAQAAObc
kpa2GS3/SS3j1UqdpgMAKAYBAIA5t7Rl0cHL01n+k2S8IgAAABxJAgAAc6qt3JTO5uYk01/+U0vG
q9V6jQgAUAgCAABzqrelLcnMlv9a4i0AAABHmAAAwJzqbG6e8fL/5BMGAgBw+AQAAOZUS7npsSsz
WP5byv6KAgA4kvzrCoA51Vp6NADM8Jn/VgEAAOCI8q8rAOZUS7k8q5f9t5RK9RoRAKAQBAAA5tTU
M/kzfM9/rZbWx791AACAwyYAAFAXM1n+a0k6m1rqOB0AwMInAAAwp8ar1Rkv/0nSWiqns7m5TlMC
ACx8AgAAc2qsWnn00vSX/wPFYHFLez1GBAAoBAEAgDk1WatkNst/kiwVAAAAjhgBAIA5NV6tTl2Y
4fJfqyVLWlrrMiMAQBEIAADMqeHJyVkt/0ktx7R31mlKAICFTwAAYE71TYxl6jUAM1v+k2Rte1c9
RgQAKAQBAIA5NV6tZGhyfMbLf2rJmkUCAEVUO/QhADALAgAAc27f+OhjV55h+c+Tlv8kWSsAUEil
Rg8AwAIlAAAw5/aNj01d+CHLf+1Jy39S8xYAAIAjSAAAYM7tHhuZ8fJfqyWr2jqyuKWtfoMCACxg
AgAAc27TyP4ZL/8HnNy5eO4HBAAoAAEAgDm3eWRw6sIMl//UajmtWwAAADgSBAAA5tymkcFZLf9J
ckrnknqMCACw4AkAAMy5zcP7H7syg+U/SU7vXjrX4wEAFIIAAMCce/jgWwBmtvzXaslpXUuyqKm5
HmMCACxoAgAAc65vYizbR4dnvPwntbSUyjmre1l9BgUAWMAEAADq4q7BPVMXZrD8Hzj+gt4Vcz8g
AMACJwAAUBf37N83q+U/qeU8AQAA4LAJAADUxT0D+x69NLPlv5bkgp6VaSn5KwsA4HD41xQAdXHX
/r2ZzfKfWtLd3JLzepfXaVIAgIVJAACgLu7f35e+ifHHvjDN5f/AF1+09Ng6TAkAsHAJAADURS3J
LX27Hr0ys+U/SV645Lg6TAmN8YRXxgDAHBEAAKibG/t3zmr5Ty05uWtxVrd11GlSqK9SqdETAFAE
AgAAdXNj346Dl2ey/NeSlFLLlcvX1WdQAIAFSAAAoG5uHdiTsWplxsv/gQuvWLG2jtMCACwsAgAA
dTNSmcwN+3ZmNst/kpzTsyJr2rvqNS4AwIIiAABQV1/fs3nqwgyX/6mrtVy5bE09xgQAWHAEAADq
6ut7t85q+a89evLAq1dtqM+gMMdKceY/AOpLAACgrh4Y6s+m0cFZLf9JckrH4pzdvaweo8Kcqj3h
5S0AMPcEAADq7ku7t8xq+T9QDd54zIl1mBIAYGERAACou8/u3PjopZkv/0nyimXr0tXcPNdjwpxp
Lnn5PwD1JwAAUHc39+/KltH9U1dmuPzXaklHU1Nes2J9XWaFuVCpefk/APUnAABQd7Uk1+5+ZFbL
/4HLb199Spo8i8pRqLlU8u5/ABpCAACgIT6745FZL/+pJWvbu3LZkuPqMSocUe0lb18BoDEEAAAa
4vuDu3PfUN+slv+pX2r5yWNPqcOkcOSUS6Xsr040egwACkoAAKBh/nnbgwcvz3T5Ty05r3tZzvWR
gBxFljW1NnoEAApMAACgYT6546GMVSuzWv4P+KU1p9dhUjh85ZQyUJls9BgAFJgAAEDD9E2O5Qu7
Nz32hRku/6nVcnHvqlzUs2Luh4XDtK61M2O1SqPHAKDABAAAGupj2x6YujCL5f/At9+55oy5HxQO
Q1OplEnLPwANJgAA0FA39O/MbYN7MtvlP7Xk/O5leUHvqvoMDLNwWltPNk+MNHoMAApOAACg4f7X
lnuTzG75P/DNX113dppLpbkfFmaovVzO5OPPcwEADSIAANBwn9+9KZtHhzLb5T+15MRFPXndig11
mRdm4jkdK3Lf+GCjxwAAAQCAxpusVfP3W++bujKL5f/Ad9615vT0+pg15pGlTa0ZrU6m6hUAAMwD
AgAA88LHdzyYPeOjSWa3/KeW9Da15hePO61eI8MhvahrVW4e2dfoMQAgiQAAwDwxXJnM32y5Z9bL
/wFvWXFCTu9YUoeJ4Yc7vb03WyeGM1GrNnoUAEgiAAAwj3x0+wPZMfa4M6XPcPlPrZZyqZTfW39e
mkv+iqNx2svlXNK5Ijd59h+AecS/jgCYN8aqlfzt1runrsxi+T9w9ZSOnrx91UlzPzA8gyu6js2N
I/s8+w/AvCIAADCvfHzHQ3lkZH+S2S3/B773C6tPyQntXfUYGZ5gQ2tX1rd05ZaRvY0eBQCeQAAA
YF4Zr1bywYdvPazlP0nayk350IYL0uKtANRRe6kpV/esybX7t6bizP8AzDP+VQTAvPPFfVvyH307
Mtvlf+pbtTx70eL852N9KgD186qeNdldGc99YwONHgUAnkIAAGBe+v1Hvp/JWm3Wy/8Bb1/5rDyn
e/lcjws5b9HSnNbek2sHtzZ6FAB4WgIAAPPS/cMD+fiOhw5r+U9t6i+63z/+vCxtbpvbgSm0Fc1t
ubL72NwwvCc7J0cbPQ4APC0BAIB5648335bt48OzXv6TqWNXNS/KH62/IE2l0hxPTBG1lsp5Q+/6
DFcn87Wh7Y0eBwCekQAAwLy1vzKZ39p4y2NfmMXyf+CYi7qW5V2rnz2H01JEpSSv6V2b5c1t+fzg
1oxVfewfAPOXAADAvPa1vm25bt+Ww1r+Dxz/4ytOzBW9x875zBTH8ztW5rS23twxui/3OvEfAPOc
AADAvPc7D38/fZXxR6/Nbvk/4P1rz8lZHUvmcFqK4uS2nlzWvSrDtclcO7it0eMAwCEJAADMe7sn
RvPfHrolh7P8T329lvZyU/5iw0VZ29ox53OzcK1uXpTX9q5LOcln+7dkqDrZ6JEA4JAEAACOCl/q
25L/u+vhg9dns/wfuLykqTV/vv6i9DS1zPHULESLm1rz5iUb0loq5XvDe3LXWH+jRwKAaREAADhq
vH/zbdk4uv+wlv8DR5/Q1pU/Of6CtJWb5n5wFoyOUlPevHhDuspN2VMZz5f2O+s/AEcPAQCAo8Zw
ZTLvfujGTNQePdP6LJf/A4dc0Lksf7ru/LSW/HXIobWVy3nL0g1Z0dyaiVo1/9r3SMZrzvoPwNGj
qbm59bcaPQQATNfOidH0Vcbywp5jcjjL/4Hra9o686z27nxpYPvjTy8AT9BSKufNizdkbUtHakk+
N7g1948PNnosAJgRAQCAo84dw31Z3dqeUzsWH9byf+Dy+taurG5dlG8M7BQBeIrmUjnXLF6fDa2d
qSW5eXhvvj60s9FjAcCMec0jAEel39l8e+4c7nv02uyX/wOnE3jl4uPyu2vPSbO3A/A4raVy3rR4
fU58dPnfPjGS6/b7yD8Ajk7+lQPAUWmsWsm7Hvpe9k6OHvbyf+BrV/SuzofWnufEgCRJ2ktNeeuS
DTnh0eV/f2UyH+9/5LFzUADAUUYAAOCotWV8OD/34A0Zrk4e9vJ/4HaXdK/MH6w9L+0iQKF1lpvz
40tPyJpH3/M/Ua3m4/0Pp78y3ujRAGDWBAAAjmp3jvTl3Y/cnEp16lnZw1n+p46v5bldy/PX65+T
pc1tdXkMzC9Lm1rzE0uelVXN7all6s/LJ/o3Z8vEcKNHA4DD4iSAABz1No7tz0i1kud3r0hyeMv/
gevLW9pzWe+q3LB/d/oqE/V5IDTcmpbOvG3JCeltaj745+K6/Vtz2+i+Ro8GAIdNAABgQbh1eF86
ys05u3PJYS//By51NbXkpb3H5q6R/mybGKnPA6FhzmxfnDcuPj5t5fLBPxffGt6Zbw3tavRoAHBE
CAAALBjX79+VpU1tOb1jcZLDW/4PfK+11JSX9h6biVo1t40c+NQBFpJySnlJ9zG5vPvYNJUe+3Px
3eG9+aIz/gOwgAgAACwo3xrcmZUt7Tl1Uc9hL/8Hji2Vkgu6lmVdW2du2L8nk84Cv2B0lJpyzZL1
Oat9SUqP+29/6+i+fG5wS6PHA4AjSgAAYMH51v6dWd/WlRPbuw97+X/87Ta0dud5XSty0/CeDDgv
wFFvTUtnfmzJCVnVsiiP/29/x1h/PjOw+eB/dwBYKAQAABacWpKvDmzPyub2nLqo93Er/NMv/0/9
3oHrT30LwZLm1rxy8XEZqVVy10j/XD4M5kjC13zrAAAgAElEQVQpyXM7lue1vese/bjHx5b/20b7
8umBzala/wFYgAQAABakWpJvDO5IV7klZ3YsfuxZ/qdZ/qe+N71PDkiSplI5F3Utz4ntXblpaG/G
vCXgqNHb1Jo3L16f8zuWpVQq5fHL//dG9uazg575B2DhEgAAWNCu378r7eWmnNWx5Igs/7XH3XZd
a2cu712dTePD2TzuM+Lns1KScxctyZt6N2RZc9tT3vLxreGdTvgHwIJXam/vFLoBWPDetGx9/ssx
p6ac0hFZ/mu1J4aErw3uyIe335O+yvicPg5mbklTa17VsyYntnY95XwP1VotX9i/Ld8d3tPQGQGg
HgQAAArjhd2r8ttrzk57uemILv8HbjcwOZG/2nlfvjSwzcvI54FySnle5/Jc2rkqLaXyU5b/8Wo1
nxzYlHvHBho6JwDUiwAAQKE8e9Hi/OG687KkufWILv+Pv697R/vzlzvvy91OEtgwJ7R25WXdx2Zl
c3uSp37Sw/7KZD7WtzHbJkcaNyQA1JkAAEDhrG5ZlN9fe25Obu9JcmSX/wO3qyb55uDO/O3O+7Nr
cnTuHgxPsKy5NS/pOjant/c87r/lE5f/rRPD+Zf+Ten3dg0ACkYAAKCQWstN+a+rTs2rlqw54st/
7XH3NVSdzKf2PZJP7NuUoerknD2eouspt+RHulbl/EVL01TKMy7/t4305bODWzLhkxsAKCABAIBC
e/WStXnnMaemOeUkR3b5f/zXhquVfLZ/c/5578YMVSpz+IiKpaPcnBd0rshzO5anuVROUnva5X+i
Vs11g9ty08jehs0KAI0mAABQeKe29+Y3jzsrx7UuSnLkl/+Dt6slg9WJfHrflnyuf3MGKhNz96AW
uMVNrbm4c0XOW7QkraWmx57lf5rlf9fkWD7Rvynbvd8fgIITAAAgSVu5KT+74qS8dum6OVv+H/+1
8Vol3xzcmf+775FsGh+ek8e0EK1uXpSLO1fkzPbFKZdKSfJDl/9bR/vyuYEtGfeSfwAQAADg8S7p
Xpl3rz493eXmJHOz/D/+vqqp5cahvfniwLbcNLwnlZq/lp+suVTOGe29uaBjWTa0dD7xFRqP/v+T
l//h2mT+bWBz7hn1EX8AcIAAAABPsqSpNT+38uRc3rs6ydwt/0++rz2VsXylf0e+PLg9Oya8XH11
y6Kcv2hZzutYkrZSU1KrTWv5v2+sP/8+sDWDVW+xAIDHEwAA4Bk8t2tF/suqU7KipX3Ol//H7mvq
K5vGh/Pt/bvyzf07sn2iOB8juLSpLae19+TcRUtybEtHkkd/r6ax/A9UJ/K5ga25Z6y/zlMDwNFB
AACAH6KzqSlvX3ZSXrn4uJRLpbos/4+/XTW13DsykO8N7cmtI/vyyPjQkX+QDVRKsqalM6e09eTZ
7b05tmXRY79Xmd7yX0ktNwzvydeGtmes6r3+APBMBAAAmIZ1rR35mZUn56LOZXVb/p/uvvZMjub7
w/ty6/C+3Ds2kP6j8JMEFje15oTWrpzS3pOT27rTUWp+6u9Vprf8Pzi+P9cNbs2OyeK8SgIAZksA
AIAZOLdzaX5+xclZ19pZ9+X/4O1qjy3C2yZGc//YQO4bHcwPxgezZXwkk/PojPctpXKOaV6U49s6
sr6lK+tbO9PT1Jo8w+/LdJf/PZXxfGlwW+7ycn8AmDYBAABmqLlUzuU9q/OWZeuztLktSWOW/6fc
rlbLZK2WrRMj2TwxnEfGh7JjYiS7J8eya3Isw9XJI/Mb8DS6ys1Z2tSWZc2tWdHcnmNbOnJMy6Is
a25JqfbYx/U9YfZZLP/9lYl8e2hXvjeyd16FDgA4GggAADBLB0LAm5etz5Km1iSNXf6f7r4O/Pxa
kuHqZPZMjqW/MpH91ckMViYzVB3PUHUyE7VaKqlltFpJakklSdOjt+toakpSSmuplI5SczrKzelq
mvq1u9ycJeXWtJWbnrrEP+mxHM7yP1ydyLf27871I7st/gAwSwIAABym9nJTXtqzOlctWZuVze3z
cvl/wu1mdF9PfCxPd18HZ3/y7Y7A8r+3Mpbrh3fnxuG9mbD4A8BhEQAA4AgppZQLu5bldUvW5ZS2
Hst/nuZ201z+t02O5NtDu3LbaF+qB+4MADgsAgAAzIHTFy3OS3uOzXO6lqW1VLb8P+6+nvZ2tVom
atXcMdafG4f3ZOMC+7hDAJgPBAAAmEMd5ea8oHtlXtqzOutbOy3/T3O7nROjuXlkb24a2TunJyoE
gKITAACgTk5s687FXSvyvK7lWX7gXAEFXf73VcZz+2hfbhvel62TI8/8mwYAHDECAADUWSnJSe09
eV7X8py/aGlWtixKsvCX/92TY7l7rD+3jfRl88TQwa8DAPUhAABAg61sWZQzF/XmzEWLc2b7krSX
pz6A72hf/ieq1WwcH8r9Y4N5YHwwWyaGZ/g7AwAcSQIAAMwjLaVyTmjrysltPTm5vTsntfeks9x8
VCz/Q9XJbBzfn43jQ9k4vj+bJ0Yy6aP7AGDeEAAAYB4rJTm2dVHWtnRmbWtn1rR0ZG1rR5Y0tzZ0
+d9XGcvW8ZFsnxzJ1omp/+2aHPWyfgCYxwQAADgKLSo1ZWVLe5Y1t2V5c1uWN7VnWXNrupta0llu
SWe5KYvKTUlmvvwPVyvZX53MUGUi+6uT2TM5nj2VseydHMveynj2VsYyUq3U8+ECAEeAAAAAC1RT
qZTOcnNaS00pp5b2UnOSpLVcTpKMVadenj9am0wtpYxVKxmqTaZa808DAFiIBAAAAAAogHKjBwAA
AADmngAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAU
gAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAA
AAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAA
BSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAA
AAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAA
QAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEI
AAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAA
AFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAA
AgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAA
AAAUgAAAAAAABdDc6AEAYC68+U1vTrk8/c49PjaWf/7Xf5n1z1u9enVe+CMvzIXnX5Dly5enp6c3
Q0P7s3379tx0y8358le+kp07d8zoPl/y4pfkmGOOSZJ87J8+lkqlMuv5Duju7sqrr3pNkuQHP3gw
3/7Od6Z929e8+jXp6up62u8NDg5m48MP5+6778r4+Pis51u1alWueuUrc9ZZZ2flipVpbW3Lnj27
s2Pnzmx8eGO+/e1v5+577k61Wp32fS5ftjxXXnnljObYtGlTvv6Nr890fACY10rt7Z21Rg8BAEfa
xgceSmtr67SP7+vry7PPOn3GP+fYY4/Nu3/53Xndj742TU1Nz3jc5ORkvvClL+b9H3h/fvCDH0zr
vj/+0X/KJS+4JEmy4VknZGx8bMbzPdnx647Pd7717an7/5d/zrt++V3Tvu0N374+a9es/aHH9Pf3
5yP/5yP54z/9k4yOjk77vltbW/PeX3lPfurtP5Xm5h/+/MS+vn15wzVvzJ133Tmt+z7v3PPz75/+
zLRnSZJrv3Bt3v5TPzmj2wDAfOcVAAAsaJOTkxkaGjrkcf0D/TO+7/PPuyD/++/+LsuWLjv4s266
+ebcededGRjoT2dnd9auXZNLLr4knZ0defmVL8tLLntx1j9rw4x/1nwyOTmZLVu3HLze2tKaVatW
pVwup7e3N+/4hXfkkhdcktdf8/rs33/o3/tSqZT//ud/mZe/7OVJkvHx8Vx/w/W5/4EHsnv37nR0
LMoJG07IRRdemBUrVmbJ4iXp7n76VyIcytjYaEZHDx1ShoeGZ3X/ADCfCQAALGi333FbXnHVq474
/Z5y8sn5+Ec/lo6OjiRTz6Z/4EMfyI4dT32Zf1trW66++ur88jv/a4477rgjPku97dixI897wfOf
8LW21rZc+qJL84H3vz8rV67K2WednV/5f96T3/it3zjk/b38ZS8/uPzffc89+cmffns2PvzwU45r
amrKpS+6NG98/RsyPj45q9n/7n//r/zO7/3urG4LAEc7JwEEgBlqbW3N3/7V3x5c/j/4Bx/Ku375
XU+7/CfJ2PhY/unj/5RLL780n/v85+o5at2MjY/l2i9cm//0Y287+P78N1/zpmm9DeO1P/rag5d/
8T//wtMu/0lSqVTypS9/KT/9cz+Tm2+56cgMDgAFIgAAwAxd/erX5KSTTkqSfOWrX8mH/+LD07rd
/v1D+emf+5m5HK3h7rjzjoPvze/o6Mhpp552yNs864QTkyR79u7JPffeO6fzAUCRCQAAMEM/8eM/
cfDyH/3Jn6RWm/75dGdy7NHq8Sc5XLp06SGPb3r0pH/dXd1paWmZs7kAoOgEAACYgd7e3pxx+hlJ
kocfeTi3fP/mBk80/yxbtvzg5eHhQ58E8KGHpoJBa2trfvxtb5uzuQCg6JwEEIAFrampOb29vYc8
bmxsbFofW3fuOeemXJ7q5zffbPl/ss7Ojpx5xplJpl7t8OCDh/7Iw09+6lO57NLLkiTv+83fzgsu
viSf+NQn8x/f/nZ27951ROdrbW2b1p+H4eHhTExMHNGfDQCNJgAAsKCddeZZufv2uw553B//6R/n
D//4jw553Irljz27vXnL5sOabaFpb2/Pn/zhn6S3tydJcsN3v5vde3Yf8naf+NQn8uLLLstrXv2a
JMnlL7k8l7/k8iTJI5seyS233JLv3fi9fP66a7Nt27bDmvEnf+Lt+cmfePshj3vjm6/JN7/1zcP6
WQAw3wgAADADixc/9uzxdD7jfiHq6urOL/78Lx683t7enhM2bMjFz39+Vq5clSQZGxvN+373t6d1
f7VaLb/4S+/IDd+9Ie/4hXc84aMS161dl3Vr1+XVV7067/vN9+XfP/vved/v/na2b99+ZB8UABSA
AADAgvbAAw/k13/jvx3yuE2bHpnW/Y2PP/ay8KKesK63tye//qu/9ozf37ZtW975X9+ZW2/9/rTv
s1ar5e8/8g/5+4/8Q844/Yy8+LIX53nPfW7OPPPMLFm8JEnS1NSUV1/16jzvuc/Nj77+tfnBQw/N
ePZ//+y/5yP/5x8Pedztd9w+4/sGgPlOAABgQRvcP3BEX8q9r6/v4OXenp4jdr9Hk/Hx8dxz7z0H
r1crlfQPDOShjRtz/Q3X57rrrsvY+Nis7/+OO+/IHXfekT/78z9LqVTKmWecmVdfdVXe/hNvT1tr
W1auXJU//7MP5xVXvWrG971p8yYv7QegsAQAAJiBhx957JUCp5xySgMnaZxdu3blyle8rC4/q1ar
5bbbb8ttt9+WT3360/nMpz6dtta2nHvOeTn7rLNz62231mUOAFgIfAwgAMzAnXfekaGh4STJueec
l/b29gZPVBy333F7PvGJTxy8ftZZZzVwGgA4+ggAADADk5OT+dKXv5gk6e7uyqtfdVWDJyqWe++/
7+Dljo6OBk4CAEcfAQAAZuiv/uavD17+1fe89+BJ6qbj+HXHz8VIhbF61TEHL+/ZvaeBkwDA0UcA
AIAZuu322/KRf/xIkmTlylX56Ef+McuWLjvk7V5+5cty7Wc/P9fjHXV++qd++gkf/fdMVq1alde/
/vVJps4NcP0N18/1aACwoDgJIAALWm/vkrzyFa+c1rHf+ObXMzAwOK1jf+N9v5XTTjs1F5x/Yc4+
+5x882vfyF/9zV/nc9d+Lg8++ODB45YuWZpLX3Rp3vbWt+bCCy6c1WNIkpe//OWZmJj4ocdUK5V8
7tqjLzC84XWvz6+/99fyla99JZ/81Kdyw3e/m507dxz8fnd3V654yUvznl/5lSxdsjRJ8pl/+0w2
b9k84591woYTp/XnYXJiItd+4boZ3z8AzGcCAAAL2gkbNuRv/+pvpnXsi694cQYG7jn0gUnGxkbz
hjddkz/60B/m6tdcncWLF+dX3/Pe/Op73pux8bHs27svPT09T3mf+le/9tUZP4Yk+csP/8W0Ztpw
0omzuv9Ga21tzZVXXJkrr7gySdLfP5C+/n1Zsnhpenq6n3DszbfclPf82ntn9XNeesUVeekVVxzy
uP7+/lx75rNn9TMAYL7yFgAAmKXR0dH84i+9I1e/7up8+StfzujoaJKkrbUtxxxzzMHlf2x8LJ+/
7vN545uvyVve9p8aOfK89Evv/KX8/gc/kO9+73upVCpJkt7enhy/7vgnLP/3339/fvN9v5GrX/fa
DAwMNGpcADhqldrbO2uNHgIAFoK2tvaccfoZWbF8WZYsXZr+/v5s3bYtd991V8bGxxo93lGhu7sr
J554Uo479tgsXrw4Q0ND6e/vzz333pNt27Y1ejwAOKoJAAAAAFAA3gIAAAAABSAAAAAAQAEIAAAA
AFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAA
AgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAA
AAAUgAAAAAAABSAAAAAAQAEIAAAAAFAAAgAAAAAUQHOjBwCARnrehc/Ns085NUPDQ/mnT/zLU75/
8okn5ZLnXZwk+ei/fjwjoyMHv1cqlXLW6WfmOedfkBXLVya1ZNvO7fnOd6/P3ffd87Q/r2NRR170
gh/JqSedkp7unuwf3p/7H3wgX/3m1zMwOPCEY59/0fNy2smnZNOWLfnCV7/4hO+tOXZNXnrZS/LZ
L3w+23fuSJJc8ryLc8LxG/L3//SPz/h4L7/0JVnSuyT//KknPtZyuZzzzz4355x1dlYsW/H/t3en
8VFVCd7H/5VaslWqspKEhLAJhCQsMREQXEBAQBFt1HFrbFHo1taemefpeT79vJgX86KfWXqmZ3qm
HWfpxZ5ut7bdQBBFQVHZwhJICNlYEiAs2ZfKVlWpel4Ei9RUBZBWp9vz+34+eVH3nHvuOVUv4P7v
OefKIova2tvUdP6syg7s04WW5rB+5U+dpl++8KuI9nOyx2r54tv1/kfb1ePp0eqVd4/al880njmt
Dz7aNmq5w27XgrnzNaOwSMnuFHm9AzrR0KgdO3eE9WtkH267ZaGyM7PkcMSqx+PR6abT2ndwv043
nblifwAA+LoiAAAAGC13bI5mz5glSdq9r0yNpxvDyhfdfKsK8wsUExOj3214IxQAxMTE6FsPrVHJ
rGIdra3W7n17FRMToxnTC/X0uif10acf67WNb4S1NTYrW8+sf0p2m0N7D5Spta1FyckpurF0rhbM
na9/f/4/daLh5Ii+5ap45mzNKpqpyupKnTt/PlTmdrlUPHO2duz8RNJwAJCXO06zimZedryTx09U
dna29NalY/Hx8Xpy7bc1afwE1dTV6sChcvl8XqWmpKpkdrGWLlysv/vnH6vpXNOlfl38zv47V9Jw
v/aV71ePpyesLCYmRrOKZqq5pSXU1pW4klx6Zv1TGpOeobKD+1VxpEJOZ5JKZ5do/ty5+vXLL+hg
xaFQ/ZmFRVq35nFdaG5WeeUh9Q/0KS01Q0XTiySJAAAAYDQCAACA8bxen5rONWluyZywACDJmaTC
/ALV1tdp+rT8sHNuv22pSmYV67UNr+ujnZ+Ejn/w0TbdtfxOLbttqc6eP6tdZXskDT/FXv/oEwoG
g/rbn/xIbR3tl87ZsV3/68k/1fpHH9cP/+Fv1dvXO6JvXvX29equZXfoP//rl1/K+Nf8ySManztO
z/3iPyJmLryx6S3deMO8a2q3o7NDvxgxS8But+uf/t/f60hNld54+63RTxzhsYfXKC01Vf/0bz8N
+222bn9fTz7+ba154BGdu3Be5y4MhyOLb12s1vZ2/f1Pfyyvzxeqb7FYlJiYeE3jAADg64I9AAAA
kLRnf5lKi4tls13Kxm+4vlTdPd2qqa8LqxvriNXimxep/sTxsJv/z2zeukUXmpu1fPHtslgskqTS
4lJlpKfrjU0bwm7+Jcnj8ei3b/1OSc4k3TRvfljZUCCgLR+8pxkFMzQhb8IXNNpLxuWM08zCIm3/
5MOoyxYCgYB27t111U/sv0jXTZysqZOnaNuODyNmZnh9Pr346suyWq1asvC20PEx6ek6d/5s2M2/
JAWDQXk8nq+k3wAA/KEiAAAAQFJ5RblsVptmFBSFjs0rnaOyg/sUDAbC6k6cMEHx8XGqqDocta1A
IKCKo5VKTUlVVmamJKkwf7qCwaAqqyqjnlN//Jj6+vtVkF8QUbZnf5maW1q0asWd1zq8URVMmy5J
OnDo0BVqfvUK84f7dvhI9O+5raNdZ86eCY1Bks43Nyt/Sr6KCgoVE8N/cwAAGIklAAAASOofGNDh
IxWaVzpH5RWHlJebp+zMLP38N79UUX5hWN20lDRJUlt7e7SmJEmtbW2SpPTUdJ07f15pqanq7umO
eDL9mWAwqLb2NqWnpkaUBQIBvf3eZq1bs1bTp+Wrujb6BoPXIi01Zbi/7S1hxx0Oh6xWa+jzkN8f
MaX+r/7vX0a057A7vsC+pV3sW9uodVrb2pSXm6dYR6wGvYN6feObeurx9XrysfXqHxhQ4+lTqq2v
1YHD5WrvGP33AgDABAQAAABctGd/mZ5e96RcSS7NK52jhlMNam5pkcKX/8tmG74xHhz0jtqW1zso
SbJah59Cx8RY5fVGv/kPnePzhS1BGOnwkQqdOnNKq5bfqZq62qsd0hVZrcPXs8gSdvy+Vd/Q/Dk3
hj6//+EH2rBlU+hzMBjUzj27I9rLSM/Q/DnXtmdARN9sVgUCAfl8/lHrDIa+5+Hf5MzZM/rhP/yN
ZhXN1PRp0zUxb7zyp0zViiXL9JtXX1J5xR/eTAcAAL4qBAAAAFxUd7xenV2dmj/3RpUWX68N77wd
tV5Pz/Du9mlRntZ/JvXiLIHP6no8Hk2aMFEWi0XBYDDqOWkpKerq7o5aFgwGtXHLJj2z/rsqnjFL
g97Rw4fPw9N7aSxN586Fjr+77X19snuXbDabvv/0n0U99/0or+6bPjX/cwUADodD//jDH4Ud++t/
/DudPX9O3d09iomJUUpyitpGmQWQlpImn88X9nrG/oEB7dlfpj37yyRJE8dP1BNrHtPD9z6oo7VH
LxvcAADwdcbiOAAALgoGgyo7uF/Lb1sqm9WmgxXlUeudPNWoYDCoCXnjR21r4vjx8vl8On12ePO8
E40nZbPZlDs2N2r9lOQUuV1unWw8GbVckmrq61R7rE4rl90Zmlnw+zrR0CBJGpebF3a8vaNdp5tO
68zZL/e1eX6/X8/+7Lmwv7aO4Zv9hlPDfRvte7bb7RqXk6uGi7/HaE42ntSOTz9WfHycMjOyvvAx
AADwx4IAAACAEfbs36tjJ09o+8cfqr9/IGqdjs4OHamu0g3FpRqblR1RPmXSZBXmF2jvgTJ5Lz6p
371vr/xDfq1acWfUzelWrVgpSfp0z67L9m/jls3KSE/XvNI5n3doUVVVH1VHZ4eW33a74uPjv5A2
P49AIKCa+rqwv8+e0JdXHpbH49GKJcsU64iNOHfpwsWKj4/XJ7s/DR2zWaNPbkxMSJAk+fw8/QcA
mIsAAACAEVrb2vTsz57Tpq1bLlvvt2++pt7+Pn3v29/V3JI5crvcSklO0S3zF+jb31qv5tYWbXjn
0pr5tvY2vfH2m8qfMk3feWydJo6fqMSEROXl5mntw4/qhuISbfngPZ1uuvwT98bTjaqoqtSMghlR
y2NiYlQ8c3bE3/hx0Z+i+4f8+tVLv1ZSklP/53vf19ySOcpIT5cryaWc7BwtuXWxJCmo0Z+wf1m8
Xq9+8+qLSk9L0589+bTyp06TM9Gp7Mws3XvXPVqxZJkOHDqogyPW9f/gz/9Cd99xl6ZMvk5ul1vp
aWlauOBm3brgFp05e0bnL1z4yscBAMAfCvYAAADgGnR2derHz/5E9951jx6+74HQJnQ+n08HDpfr
zU0bwtalS9LHu3aqq7tHq1asDFtX39HZoRd+97L27Nt7Vdd++93NmlFQJIvFElFms9n0xDcfizi+
7+B+/dcrjVHbO95wUj9+9idatWKlHrn/wbAZCh2dHdq89V1t//jDq+rbF62qplo//Y9/1eq77tEz
654KHe/t69Wm996J2Iegpq5GpbOv19KFi0PHAoGAjlRX6dU3X7vsUgEAAL7uLHFxifxLCADA7yEu
NvbiK+uCamlrC037v5yU5BQ5E53q7+9Xa3vrl9/JqxQb61BaSpqsVpu6e7rV1d31P92lEKfTqRR3
srxer1raWhUIBEat60pyyZWUJK93UB1dXfKN8vpFAABMQgAAAAAAAIAB2AMAAAAAAAADEAAAAAAA
AGAAAgAAAAAAAAxAAAAAAAAAgAEIAAAAAAAAMAABAAAAAAAABiAAAAAAAADAAAQAAAAAAAAYgAAA
AAAAAAADEAAAAAAAAGAAAgAAAAAAAAxAAAAAAAAAgAEIAAAAAAAAMAABAAAAAAAABiAAAAAAAADA
AAQAAAAAAAAYgAAAAAAAAAADEAAAAAEXQWAAAA5uSURBVAAAAGAAAgAAAAAAAAxAAAAAAAAAgAEI
AAAAAAAAMAABAAAAAAAABiAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAAADEAAAAAAAAGAAAgAAAAAA
AAxAAAAAAAAAgAEIAAAAAAAAMAABAAAAAAAABiAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAAADEAAA
AAAAAGAAAgAAAAAAAAxAAAAAAAAAgAEIAAAAAAAAMAABAAAAAAAABiAAAAAAAADAAAQAAAAAAAAY
gAAAAAAAAAADEAAAAAAAAGAAAgAAAAAAAAxAAAAAAAAAgAEIAAAAAAAAMAABAAAAAAAABiAAAAAA
AADAAAQAAAAAAAAYgAAAAAAAAAADEAAAAAAAAGAAAgAAAAAAAAxAAAAAAAAAgAEIAAAAAAAAMAAB
AAAAAAAABiAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAAADEAAAAAAAAGAAAgAAAAAAAAxAAAAAAAAA
gAEIAAAAAAAAMAABAAAAAAAABiAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAAADEAAAAAAAAGAAAgAA
AAAAAAxAAAAAAAAAgAEIAAAAAAAAMAABAAAAAAAABiAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAAAD
EAAAAAAAAGAAAgAAAAAAAAxAAAAAAAAAgAEIAAAAAAAAMAABAAAAAAAABiAAAAAAAADAAAQAAAAA
AAAYgAAAAAAAAAADEAAAAAAAAGAA2/90BwAA+KrZrDbdWFwq/9CQdpfvCyvLyhijKeMn6UJrs+oa
TlxT+7mZY7Vq8e167qVfXdP5i2+8SZK0bfen13T+SDOmTleyyz1qeVV9jWblF8lus2rrzh1R68TF
xmrmtAKNSc2Qw25Ta2eHDlZVyNPXG6qz4Po5iokZfq7gH/Kro6tTDU2nNTA4GNZW0ZR85WZlKyEu
Xr39faqoq9G55vNXNZblNy9SX/+APt6/O6LMIotm5hdo7JhMxcfGydPfq8M1R3WhteWq2gYAwATM
AAAAGMdms2rZTQu1/OaFGpeVE1a2cM58LZl/swqvm3bN7dvt1svedF9JQlyiEuISr/n8kZyJTqW6
k5XqTtaU8ZO0eN5Noc+p7mTZ7XYlxMUpIS5+1DbS3KmaOmGy+gf71NrZoSnjJ+p7a56Qy5kUqrNk
/s2anDdBqe5k5WXnaPGNt+gH657RTSVzw9q6YcZsSVJLR7sS4xP01EOPavrkqVc1lsT4BCXEx0Uv
tEhzZhYrEAiopaNdbqdLTz+8VpPzJlxV2wAAmIAZAAAAY9WdPK7igiKdPt8kSYqPjdOU8ZN0/FRD
RN205BS5nEnq9vSorbMjojw+Ll5Z6elqaW+Pei2LxaIUl1vOxEQ1t7VGPBmPxmazKSczS57e3tA1
Y2JilJzkUmdPtwKBQKhuXGys7Da7eno9YW2MnOEwe3qRsjMytGHbu1GvZ42xKicrS16vVxdaWxVU
UJLU1HxOL2x8LVTv0wN79f21T6rguinac+hg6HhZxUEdPVYX+jx98lQ9dOc96vb0qKL2qCTp+Tde
CbtmUFJp0UxVH790XowlRilul1zOJLV3damrpztqfy2yKMXtVt9AvwYGB/WzV18I//6sNpUWzQr9
ni5nkga9A7JYrMrOGKMLrS3qG+iP2jYAAF9HBAAAAGOVVx/R6qV36J2Pt8nv92tWfoGOn2qQ1+cN
q7d29UNyOZ3q6fUoIzVNF9pa9cKG1+Qf8ksanmZ/z5I7dKG1Wc7ERJ083Rh2vsuZpEfvvk8OR6x6
PB5lpqdr4/atoZviaFLcLn334bXq7etTVnq6ak8e1+tbNysYDGrt6gf1/q6Pw86/9/aVauts17uf
fHhN34Uz0amnHnpUviG/0lPSdPxUg17Z/FbUularVVarVb19l795rj5epyP1NZo3q2TUscY6HOrr
v9ROWnKyHll1v2LtdrV3dSk9JUXv7NimyrrqiD58Y+kdSklyh4UTIzkcDrV2XApkvvWNB9R0/qyu
Gz9Rnr5ebd+zUzUn6i87BgAAvk4IAAAAxmrv6tK5lhZNnzRFlXXVKi6coQ/37FLRlPDp/69v3aRu
T4+k4afK6+5/WCWFM7S3olzxsXG6e/Fyvfn+Zh2pr5HNZtMT9z0Udv5di5bozIXz2rDtXQWDQeVm
jdVj33hAJ043hq2jH2nyuAl67qXndaGtVc6ERD3zzcdVNCVflXXV2ld5WDfMKA7dVLucSZo6cZL+
5dfbr/m7mJg7Xv/28vNq7WiXy5mk//3Yd5QzJltNzedCdW6/6VY5E5zKzczWoeojqqqvvWK7TRfO
a9rE68KOzc4v1ITcPGWkpmnQ69Xmjz4Ila1eulLnms/r9a2bFQgEFGOJkcPhCDs/LjZWD69crb6B
fj3/5ivy+/2hstKiWRqXNVaZ6Rnq6fVo+57wfRRyMrP1L7/5+VXNwAAA4OuGPQAAAEYrP1qh6wtn
KjM9Q26nS3UNxyPqePp6lT9piuYX36Abi0vl8/uVPSZLkjQhN09en1dH6mskSX6/X/sqDoXOtdvs
yp80VccaTyo7I1Njx2QpEAiob6Bf47JzIq71mWOnGnShrTV0/craauVPGr6RPlB1WOOyspWRmiZJ
KimcqcamM1GXJlytY6dOhJ6Wd3t61NrRpvTU1LA6Xd3d6uzuUv/ggCaOy1NiQsIV2x30Dspms4Yd
6xvoV8fFqf3ZGWNC40hKdGp8Tq627f4ktLwhEAxoYHAgdK47yaV1939T51ub9dt3NoTd/EtSb3+f
Orq71NnTrZzMbKWnhI/hQFUFN/8AAGMRAAAAjFZ1rEbjsnK0cM58Ha6pCltXLw2vw//OA2u04Po5
stvs8voG5fV5FRcbK0lyJiREPMUfuQ7f5UyUxWLR3FklWnbTwtBfR1engsHwa40U2WavnAlOScM3
uVXHalVaNEsWi0UlhTO1r/JQtGauWn9/+HR+35BfNlv4RMG9FeXavudT/fx3L2poaEi3lM67Yrsp
brc8veFjqWs4oR37dunVLRu1r/KQVt22TJLkShzeVLDb44lo5zN52TlKTnKprKJcwWAworz6eL0+
KtulVza/pcq6aq1ctCSsfLQZFwAAmIAlAAAAow16fao+Xqvighn66Qu/iCjPyx4rd5JLP/rZvypw
8YZ9XFZO6Oa42+ORy5kki8USuiF1j3gDQJfHo0AwoHc/2a6mC+ci2h+NO8kV9jnZ5VJ3b0/oc1lF
uR5Zda8amppkt9t1dMQmel+2YDCo1vZ2ORMv/6YCm82mwuvyVRtlVsVnmi8ucZCkzp4uSVKq263m
9rao9SvrqtXT26t19z+i59945bKv+Wtpb1PRlPyIvgMAYCpmAAAAjLfl4+169sXno95MDg0FZLc5
QtPdc8Zkq3DEHgENTY2yWCyh19vFxcZq3qySULnf71ftiXotu2mR4mMvvcIuN2tsaBZBNJPG5Slv
7PASgbTkZM2YWqAjdTWh8sazZ9Tt8eieJct0sKpCQ0ND1zj6KxuXlaNUd3Lo88TccZo+eZqO/7fN
Dh12h+Ji45TqTlb+pOu0dvWDctjt+mjvLknDoUZedo4sFoskKdnl1oKSG3TiYju9/X2qOXFMt9+0
SA67I9RmUqIz7Do7D5bpwz2f6vF7HwotxUh1Jys3c6wssoQ+z51VEtFHAABMxgwAAIDx+gb6R30d
3KmzTao9Wa8//9Z31O3pln9oSBW11Yq9uDHdoNenV7ds1IN33K0F18+V3WbV4ZoqlRTNCrXx+tYt
Wr30Dv3FE0+ry9M9vGygt1e/fP1lSdHXo1cfr9ddC5fKbnfI7UzSnsMHVHvyWFid/ZXlunPRUu0/
8vtN/7+S7DFjtOLm2xQISjEWKRCUdh8q04HKw2H17lu2UpI06PWqvatTxxpP6MWNr4e+2/jYWD18
12rFx8bJ6/MrLtah6uP1Ya8l3LDtXf3JilX6wfrvqdvTraTERL323uaI3fr3VpTL5/fr8dUP6Ncb
XpOC0pp77pPDbpffPySHw64jdTV6Z8cHAgAAwyxxcYnMhQMA4AqSEp2y22zq6OpSUJH/dMbExCjF
5VJ3b698Pl/UNmxWm5JdLvX1jx44jGSRRanJbnn6+jTo9UaUL11wi3Iyx+pXb7zy+Qf0OVmtVrmd
SQoEg+r29ETslXC1LLLImZioWIdDXT098vmjf1dxsQ45E5yXrRPRtsWipESnHHa7Onu6IzYIBADA
dAQAAAD8kUlxJ2vC2FytXLRML216TcdPMc0dAABcGXsAAADwRyYvO0cF103TOzve5+YfAABcNWYA
AAAAAABgAGYAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAA
wAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAA
AAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIAB
CAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAA
AAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAA
AAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAAAAAAwAAEAAAAAAAA
GIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAAAQAAAAAAAAYgAAAA
AAAAwAAEAAAAAAAAGIAAAAAAAAAAAxAAAAAAAABgAAIAAAAAAAAMQAAAAAAAAIABCAAAAAAAADAA
AQAAAAAAAAYgAAAAAAAAwAD/H8GWivRqb+BXAAAAAElFTkSuQmCC
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
Name=Moonlight-OS Eclipse
Description=Minimal black and crimson eclipse with a subtle orbital light
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/crimson-apollo
ScriptFile=/usr/share/plymouth/themes/crimson-apollo/crimson-apollo.script
APOLLO_THEME
cat > /usr/share/plymouth/themes/crimson-apollo/crimson-apollo.script <<'APOLLO_SCRIPT'
# Moonlight-OS Eclipse boot theme. Internal paths stay compatible.
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

# Reviewed Moonlight-OS Vibemis theme/status patch.
VIBEMIS_PATCH_SHA256=2e577766c16e059deb04cdf2a286c4a28bf271737eeb3874e4b29995c93a8a6c
FRONTENDS_LOCK
base64 -d > /usr/local/share/moonlight-os/vibemis-crimson.patch <<'VIBEMIS_PATCH_B64'
ZGlmZiAtLWdpdCBhL2FwcC9hcHAucHJvIGIvYXBwL2FwcC5wcm8KaW5kZXggYzE4ODZhNDguLmVm
MWIxOWMyIDEwMDY0NAotLS0gYS9hcHAvYXBwLnBybworKysgYi9hcHAvYXBwLnBybwpAQCAtNTc5
LDExICs1NzksMTEgQEAgdW5peDohbWFjeDogewogICAgICMgVmliZW1pcyBtYXJrIGluc3RlYWQg
b2YgYSBnZW5lcmljIGljb24uIFRoZSAuZGVza3RvcCBJY29uPSBrZXkgaXMKICAgICAjICJ2aWJl
bWlzIiwgd2hpY2ggbWF0Y2hlcyB0aGVzZSBmaWxlcycgYmFzZW5hbWUuIFdlIHNoaXAgcmVhbCBQ
TkdzIGF0CiAgICAgIyAxMjgvMjU2LzUxMiAodGhlcmUgaXMgbm8gdmVjdG9yIG1hc3RlciBmb3Ig
dGhlIHJhc3RlciBicmFuZCBtYXJrKS4KLSAgICBpY29uMTI4LmZpbGVzID0gcmVzL2ljb25zL2hp
Y29sb3IvMTI4eDEyOC9hcHBzL3ZpYmVtaXMucG5nCisgICAgaWNvbjEyOC5maWxlcyA9IHJlcy9p
Y29ucy9oaWNvbG9yLzEyOHgxMjgvYXBwcy9lY2xpcHNlLnBuZwogICAgIGljb24xMjgucGF0aCA9
ICQkUFJFRklYLyQkREFUQURJUi9pY29ucy9oaWNvbG9yLzEyOHgxMjgvYXBwcy8KLSAgICBpY29u
MjU2LmZpbGVzID0gcmVzL2ljb25zL2hpY29sb3IvMjU2eDI1Ni9hcHBzL3ZpYmVtaXMucG5nCisg
ICAgaWNvbjI1Ni5maWxlcyA9IHJlcy9pY29ucy9oaWNvbG9yLzI1NngyNTYvYXBwcy9lY2xpcHNl
LnBuZwogICAgIGljb24yNTYucGF0aCA9ICQkUFJFRklYLyQkREFUQURJUi9pY29ucy9oaWNvbG9y
LzI1NngyNTYvYXBwcy8KLSAgICBpY29uNTEyLmZpbGVzID0gcmVzL2ljb25zL2hpY29sb3IvNTEy
eDUxMi9hcHBzL3ZpYmVtaXMucG5nCisgICAgaWNvbjUxMi5maWxlcyA9IHJlcy9pY29ucy9oaWNv
bG9yLzUxMng1MTIvYXBwcy9lY2xpcHNlLnBuZwogICAgIGljb241MTIucGF0aCA9ICQkUFJFRklY
LyQkREFUQURJUi9pY29ucy9oaWNvbG9yLzUxMng1MTIvYXBwcy8KIAogICAgIGFwcHN0cmVhbS5m
aWxlcyA9IGRlcGxveS9saW51eC9jb20udmliZW1pcy5WaWJlbWlzLmFwcGRhdGEueG1sCkBAIC02
MzEsMyArNjMxLDE3IEBAIG1hY3ggewogIyBjb3VudHMpIG9yIHRoZSBzbWFydC1idWlsZCBjaGVj
ayBza2lwcyB0aGUgcmVsZWFzZS4KIFZFUlNJT04gPSAiJCRjYXQodmVyc2lvbi50eHQpIgogREVG
SU5FUyArPSBWRVJTSU9OX1NUUj1cXFwiJCRjYXQodmVyc2lvbi50eHQpXFxcIgorCisjIE1vb25s
aWdodC1PUyBvcHRpb25hbCBsYXVuY2hlciBzdGF0dXMgYW5kIGhvc3Qgc3RhdHMuCitTT1VSQ0VT
ICs9IG1vb25saWdodG9zL2NyaW1zb25zdGF0dXMuY3BwCitIRUFERVJTICs9IG1vb25saWdodG9z
L2NyaW1zb25zdGF0dXMuaAorCisjIENvbXBpbGUgdGhlIGFwcGxpYW5jZS1vd25lZCB1cGRhdGVy
LCBub3QgdGhlIHVwc3RyZWFtIGZlZWQvQXBwSW1hZ2UgaW5zdGFsbGVyLgorU09VUkNFUyAtPSBi
YWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmNwcAorU09VUkNFUyArPSBtb29ubGlnaHRvcy9tYW5h
Z2VkdXBkYXRlcy5jcHAKKworU09VUkNFUyArPSBtb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5j
cHAKK0hFQURFUlMgKz0gbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuaAorCitTT1VSQ0VTICs9
IG1vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5jcHAKK0hFQURFUlMgKz0gbW9vbmxpZ2h0b3Mv
ZWNsaXBzZXByb2ZpbGVzLmgKZGlmZiAtLWdpdCBhL2FwcC9iYWNrZW5kL2F1dG91cGRhdGVjaGVj
a2VyLmggYi9hcHAvYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5oCmluZGV4IDVlYjk4Y2I4Li42
OWJlNDFjYyAxMDA2NDQKLS0tIGEvYXBwL2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaAorKysg
Yi9hcHAvYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5oCkBAIC0yOSw2ICsyOSw5IEBAIGNsYXNz
IEF1dG9VcGRhdGVDaGVja2VyIDogcHVibGljIFFPYmplY3QKIHsKICAgICBRX09CSkVDVAogCisg
ICAgLy8gVGhpcyBjdXN0b21pemVkIGFwcGxpYW5jZSBpcyB1cGRhdGVkIHdpdGggTW9vbmxpZ2h0
LU9TLCBuZXZlciB1cHN0cmVhbSBBcHBJbWFnZXMuCisgICAgUV9QUk9QRVJUWShib29sIG9zTWFu
YWdlZCBSRUFEIG9zTWFuYWdlZCBDT05TVEFOVCkKKwogICAgIC8vIEEgc3RyaWN0bHktbmV3ZXIg
YnVpbGQgZXhpc3RzIG9uIHRoZSBjaGFubmVsIOKAlCBwb3dlcnMgdGhlIHRvb2xiYXIgYmFubmVy
LgogICAgIFFfUFJPUEVSVFkoYm9vbCB1cGRhdGVBdmFpbGFibGUgUkVBRCB1cGRhdGVBdmFpbGFi
bGUgTk9USUZZIHN0YXRlQ2hhbmdlZCkKICAgICAvLyBUaGUgY2hhbm5lbCdzIG5ld2VzdCBidWls
ZCBkaWZmZXJzIGZyb20gdGhlIHJ1bm5pbmcgb25lIChtYXkgYmUgb2xkZXIg4oCUCkBAIC01MSw2
ICs1NCw3IEBAIGNsYXNzIEF1dG9VcGRhdGVDaGVja2VyIDogcHVibGljIFFPYmplY3QKIAogcHVi
bGljOgogICAgIGV4cGxpY2l0IEF1dG9VcGRhdGVDaGVja2VyKFFPYmplY3QgKnBhcmVudCA9IG51
bGxwdHIpOworICAgIGJvb2wgb3NNYW5hZ2VkKCkgY29uc3QgeyByZXR1cm4gdHJ1ZTsgfQogCiAg
ICAgLy8gTGF1bmNoLXRpbWUgZW50cnkgcG9pbnQ6IHF1aWV0IGNoZWNrIG5vdywgdGhlbiBhIHBl
cmlvZGljIHJlLWNoZWNrIGV2ZXJ5CiAgICAgLy8gUkVDSEVDS19JTlRFUlZBTF9NUyAoYSBsYXVu
Y2gtb25seSBjaGVjayBrZXB0IHVzZXJzIGJsaW5kIHRvIGFueXRoaW5nCmRpZmYgLS1naXQgYS9h
cHAvZGVwbG95L2xpbnV4L2NvbS52aWJlbWlzLlZpYmVtaXMuZGVza3RvcCBiL2FwcC9kZXBsb3kv
bGludXgvY29tLnZpYmVtaXMuVmliZW1pcy5kZXNrdG9wCmluZGV4IDM0YjhmYWU4Li41MTZkY2Y5
NSAxMDA2NDQKLS0tIGEvYXBwL2RlcGxveS9saW51eC9jb20udmliZW1pcy5WaWJlbWlzLmRlc2t0
b3AKKysrIGIvYXBwL2RlcGxveS9saW51eC9jb20udmliZW1pcy5WaWJlbWlzLmRlc2t0b3AKQEAg
LTEsOCArMSw4IEBACiBbRGVza3RvcCBFbnRyeV0KLU5hbWU9VmliZW1pcwotQ29tbWVudD1MaW51
eC1mb2N1c2VkIFZpYmVtaXMgUXQgZm9yayB0dW5lZCBmb3IgcGFpcmluZyB3aXRoIFZpYmVwb2xs
by4gU3RyZWFtcyBnYW1lcyBhbmQgYXBwbGljYXRpb25zIGZyb20gYSBTdW5zaGluZSAvIEFwb2xs
byAvIFZpYmVwb2xsbyBob3N0LgorTmFtZT1FY2xpcHNlCitDb21tZW50PUVjbGlwc2Ug4oCUIHRo
ZSBNb29ubGlnaHQtT1MgZnJvbnRlbmQuIFN0cmVhbXMgZ2FtZXMgYW5kIGFwcGxpY2F0aW9ucyBm
cm9tIGEgU3Vuc2hpbmUgLyBBcG9sbG8gLyBWaWJlcG9sbG8gaG9zdC4KIEV4ZWM9dmliZW1pcwot
SWNvbj12aWJlbWlzCitJY29uPWVjbGlwc2UKIFN0YXJ0dXBXTUNsYXNzPWNvbS52aWJlbWlzLlZp
YmVtaXMKIFRlcm1pbmFsPWZhbHNlCiBUeXBlPUFwcGxpY2F0aW9uCmRpZmYgLS1naXQgYS9hcHAv
Z3VpL0FwcFZpZXcucW1sIGIvYXBwL2d1aS9BcHBWaWV3LnFtbAppbmRleCA2M2Y2NDVkOC4uMzgz
YWRiNzUgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvQXBwVmlldy5xbWwKKysrIGIvYXBwL2d1aS9BcHBW
aWV3LnFtbApAQCAtMTEsNiArMTEsNyBAQCBpbXBvcnQgQ29tcHV0ZXJNYW5hZ2VyIDEuMAogaW1w
b3J0IFNkbEdhbWVwYWRLZXlOYXZpZ2F0aW9uIDEuMAogCiBDZW50ZXJlZEdyaWRWaWV3IHsKKyAg
ICBwcm9wZXJ0eSB2YXIgY3JpbXNvbkhvc3Q6ICh7fSkKICAgICBwcm9wZXJ0eSBpbnQgY29tcHV0
ZXJJbmRleAogICAgIHByb3BlcnR5IEFwcE1vZGVsIGFwcE1vZGVsIDogY3JlYXRlTW9kZWwoKQog
ICAgIHByb3BlcnR5IGJvb2wgYWN0aXZhdGVkCmRpZmYgLS1naXQgYS9hcHAvZ3VpL0F1dG9SZXNp
emluZ0NvbWJvQm94LnFtbCBiL2FwcC9ndWkvQXV0b1Jlc2l6aW5nQ29tYm9Cb3gucW1sCmluZGV4
IDUzYWZjYWY4Li5mMTIzOTMyMCAxMDA2NDQKLS0tIGEvYXBwL2d1aS9BdXRvUmVzaXppbmdDb21i
b0JveC5xbWwKKysrIGIvYXBwL2d1aS9BdXRvUmVzaXppbmdDb21ib0JveC5xbWwKQEAgLTEsNSAr
MSw2IEBACiBpbXBvcnQgUXRRdWljayAyLjkKIGltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuMgor
aW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCiAKIGltcG9ydCBTZGxHYW1lcGFkS2V5TmF2aWdh
dGlvbiAxLjAKIGltcG9ydCBTeXN0ZW1Qcm9wZXJ0aWVzIDEuMApAQCAtOTIsNyArOTMsNyBAQCBD
b21ib0JveCB7CiAgICAgICAgIC8vIE92ZXJyaWRlIHRoZSBwb3B1cCBjb2xvciB0byBpbXByb3Zl
IGNvbnRyYXN0IHdpdGggdGhlIG92ZXJyaWRkZW4KICAgICAgICAgLy8gTWF0ZXJpYWwgMiBiYWNr
Z3JvdW5kIGNvbG9yIHNldCBpbiBtYWluLnFtbC4KICAgICAgICAgaWYgKFN5c3RlbVByb3BlcnRp
ZXMudXNlc01hdGVyaWFsM1RoZW1lKSB7Ci0gICAgICAgICAgICBwb3B1cC5iYWNrZ3JvdW5kLmNv
bG9yID0gIiM0MjQyNDIiCisgICAgICAgICAgICBwb3B1cC5iYWNrZ3JvdW5kLmNvbG9yID0gUXQu
YmluZGluZyhmdW5jdGlvbigpIHsgcmV0dXJuIFZiVG9rZW5zLmJnRWxldjIgfSkKICAgICAgICAg
fQogICAgIH0KIApkaWZmIC0tZ2l0IGEvYXBwL2d1aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbCBi
L2FwcC9ndWkvQ3JpbXNvblN0YXR1c0RpYWxvZy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5k
ZXggMDAwMDAwMDAuLjY4NzBmOWMzCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9Dcmltc29u
U3RhdHVzRGlhbG9nLnFtbApAQCAtMCwwICsxLDkwIEBACitpbXBvcnQgUXRRdWljayAyLjkKK2lt
cG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2lt
cG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNp
Z24gMS4wCitpbXBvcnQgQ3JpbXNvblN0YXR1cyAxLjAKKworTmF2aWdhYmxlRGlhbG9nIHsKKyAg
ICBpZDogcGFuZWwKKyAgICBwcm9wZXJ0eSBzdHJpbmcga2luZDogImhvc3QiCisgICAgd2lkdGg6
IE1hdGgubWluKDYyMCwgcGFyZW50LndpZHRoIC0gMzIpCisgICAgaGVpZ2h0OiBNYXRoLm1pbihr
aW5kID09PSAiaG9zdCIgPyA2NTAgOiAyODAsIHBhcmVudC5oZWlnaHQgLSAzMikKKyAgICB0aXRs
ZToga2luZCA9PT0gImhvc3QiID8gcXNUcigiVmliZXBvbGxvIOKAoiBIb3N0IGhhcmR3YXJlIikg
OiBraW5kID09PSAibmV0d29yayIgPyBxc1RyKCJOZXR3b3JrIHN0YXR1cyIpIDogcXNUcigiQmF0
dGVyeSBzdGF0dXMiKQorICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLkNsb3NlCisgICAgTWF0
ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYWNjZW50OiBW
YlRva2Vucy5hY2NlbnQKKyAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgeyBjb2xvcjogVmJUb2tl
bnMuYmdFbGV2OyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0RpYWxvZzsgYm9yZGVyLmNvbG9yOiBW
YlRva2Vucy5zdHJva2U7IGJvcmRlci53aWR0aDogMSB9CisgICAgb25PcGVuZWQ6IHsKKyAgICAg
ICAgdXJsSW5wdXQudGV4dCA9IENyaW1zb25TdGF0dXMuZW5kcG9pbnQKKyAgICAgICAgcGluSW5w
dXQudGV4dCA9IENyaW1zb25TdGF0dXMuZmluZ2VycHJpbnQKKyAgICAgICAgdG9rZW5JbnB1dC50
ZXh0ID0gIiIKKyAgICAgICAgQ3JpbXNvblN0YXR1cy5zZXRWaXNpYmxlKGtpbmQgPT09ICJob3N0
IikKKyAgICB9CisgICAgb25DbG9zZWQ6IHsgQ3JpbXNvblN0YXR1cy5zZXRWaXNpYmxlKGZhbHNl
KTsgdG9rZW5JbnB1dC50ZXh0ID0gIiI7IHN0YWNrVmlldy5mb3JjZUFjdGl2ZUZvY3VzKCkgfQor
ICAgIGZ1bmN0aW9uIG1ldHJpYyhrZXksIHN1ZmZpeCkgeworICAgICAgICB2YXIgbiA9IENyaW1z
b25TdGF0dXMuc3RhdHNba2V5XQorICAgICAgICByZXR1cm4gbiA9PT0gdW5kZWZpbmVkID8gcXNU
cigiTi9BIikgOiBOdW1iZXIobikudG9GaXhlZCgxKSArIHN1ZmZpeAorICAgIH0KKyAgICBmdW5j
dGlvbiBtZW1vcnkocHJlZml4KSB7CisgICAgICAgIHZhciBzID0gQ3JpbXNvblN0YXR1cy5zdGF0
cworICAgICAgICByZXR1cm4gc1twcmVmaXggKyAiX3VzZWRfYnl0ZXMiXSA9PT0gdW5kZWZpbmVk
IHx8ICFzW3ByZWZpeCArICJfdG90YWxfYnl0ZXMiXSA/IHFzVHIoIk4vQSIpCisgICAgICAgICAg
ICAgOiAoc1twcmVmaXggKyAiX3VzZWRfYnl0ZXMiXSAvIDEwNzM3NDE4MjQpLnRvRml4ZWQoMSkg
KyAiIC8gIiArIChzW3ByZWZpeCArICJfdG90YWxfYnl0ZXMiXSAvIDEwNzM3NDE4MjQpLnRvRml4
ZWQoMSkgKyAiIEdpQiIKKyAgICB9CisgICAgY29udGVudEl0ZW06IFNjcm9sbFZpZXcgeworICAg
ICAgICBjbGlwOiB0cnVlCisgICAgICAgIGNvbnRlbnRXaWR0aDogYXZhaWxhYmxlV2lkdGgKKyAg
ICAgICAgQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAgIHdpZHRoOiBwYW5lbC5hdmFpbGFibGVX
aWR0aAorICAgICAgICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCisgICAgICAgICAgICBM
YWJlbCB7CisgICAgICAgICAgICAgICAgdmlzaWJsZTogcGFuZWwua2luZCAhPT0gImhvc3QiCisg
ICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3Jh
cAorICAgICAgICAgICAgICAgIHRleHQ6IHBhbmVsLmtpbmQgPT09ICJuZXR3b3JrIiA/IChDcmlt
c29uU3RhdHVzLmxvY2FsLm5ldHdvcmsgKyAoQ3JpbXNvblN0YXR1cy5sb2NhbC53aWZpU2lnbmFs
ID49IDAgPyAiIOKAoiAiICsgQ3JpbXNvblN0YXR1cy5sb2NhbC53aWZpU2lnbmFsICsgIiUgc2ln
bmFsIiA6ICIiKSArICJcbiIgKyBxc1RyKCJBY3RpdmUgbGluayBzdGF0dXM7IGludGVybmV0IGFj
Y2VzcyBpcyBub3QgYXNzdW1lZC4iKSkKKyAgICAgICAgICAgICAgICAgICAgOiAoQ3JpbXNvblN0
YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAwID8gQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0
ZXJ5UGVyY2VudCArICIlIOKAoiAiIDogIiIpICsgQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5
U3RhdGUKKyAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5waXhlbFNp
emU6IFZiVG9rZW5zLnR5cGVCb2R5CisgICAgICAgICAgICB9CisgICAgICAgICAgICBMYWJlbCB7
CisgICAgICAgICAgICAgICAgdmlzaWJsZTogcGFuZWwua2luZCA9PT0gImhvc3QiCisgICAgICAg
ICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcAorICAg
ICAgICAgICAgICAgIHRleHQ6IENyaW1zb25TdGF0dXMuc3RhdHVzCisgICAgICAgICAgICAgICAg
Y29sb3I6IFZiVG9rZW5zLnRleHREaW0KKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIFJlcGVh
dGVyIHsKKyAgICAgICAgICAgICAgICBtb2RlbDogcGFuZWwua2luZCA9PT0gImhvc3QiID8gWwor
ICAgICAgICAgICAgICAgICAgICBbcXNUcigiQ1BVIiksIHBhbmVsLm1ldHJpYygiY3B1X3BlcmNl
bnQiLCAiJSIpLCBwYW5lbC5tZXRyaWMoImNwdV90ZW1wX2MiLCAiIMKwQyIpXSwKKyAgICAgICAg
ICAgICAgICAgICAgW3FzVHIoIlJBTSIpLCBwYW5lbC5tZW1vcnkoInJhbSIpLCBwYW5lbC5tZXRy
aWMoInJhbV9wZXJjZW50IiwgIiUiKV0sCisgICAgICAgICAgICAgICAgICAgIFtxc1RyKCJHUFUi
KSwgcGFuZWwubWV0cmljKCJncHVfcGVyY2VudCIsICIlIiksIHBhbmVsLm1ldHJpYygiZ3B1X3Rl
bXBfYyIsICIgwrBDIildLAorICAgICAgICAgICAgICAgICAgICBbcXNUcigiVlJBTSIpLCBwYW5l
bC5tZW1vcnkoInZyYW0iKSwgcGFuZWwubWV0cmljKCJ2cmFtX3BlcmNlbnQiLCAiJSIpXSwKKyAg
ICAgICAgICAgICAgICAgICAgW3FzVHIoIkdQVSBlbmNvZGVyIiksIHBhbmVsLm1ldHJpYygiZ3B1
X2VuY29kZXJfcGVyY2VudCIsICIlIiksICIiXSwKKyAgICAgICAgICAgICAgICAgICAgW3FzVHIo
Ikhvc3QgbmV0d29yayIpLCBwYW5lbC5tZXRyaWMoIm5ldF9yeF9icHMiLCAiIEIvcyBSWCIpLCBw
YW5lbC5tZXRyaWMoIm5ldF90eF9icHMiLCAiIEIvcyBUWCIpXQorICAgICAgICAgICAgICAgIF0g
OiBbXQorICAgICAgICAgICAgICAgIGRlbGVnYXRlOiBSZWN0YW5nbGUgeworICAgICAgICAgICAg
ICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBpbXBsaWNpdEhlaWdodDogNTgKKyAgICAg
ICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLmJnV2luZG93OyByYWRpdXM6IFZiVG9rZW5z
LnJhZGl1c0NvbnRyb2wKKyAgICAgICAgICAgICAgICAgICAgYm9yZGVyLmNvbG9yOiBWYlRva2Vu
cy5zdHJva2U7IGJvcmRlci53aWR0aDogMQorICAgICAgICAgICAgICAgICAgICBSb3dMYXlvdXQg
eworICAgICAgICAgICAgICAgICAgICAgICAgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGFuY2hvcnMu
bWFyZ2luczogMTIKKyAgICAgICAgICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogbW9kZWxE
YXRhWzBdOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbTsgTGF5b3V0LnByZWZlcnJlZFdpZHRoOiAx
MTUgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBtb2RlbERhdGFbMV07
IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlIH0KKyAgICAgICAg
ICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogbW9kZWxEYXRhWzJdOyBjb2xvcjogVmJUb2tl
bnMuYWNjZW50IH0KKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIH0KKyAg
ICAgICAgICAgIH0KKyAgICAgICAgICAgIEdyb3VwQm94IHsKKyAgICAgICAgICAgICAgICB2aXNp
YmxlOiBwYW5lbC5raW5kID09PSAiaG9zdCIKKyAgICAgICAgICAgICAgICB0aXRsZTogcXNUcigi
Q29uZmlndXJlIGhvc3Qgc3RhdHMiKQorICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6
IHRydWUKKyAgICAgICAgICAgICAgICBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgICAgICAg
ICBhbmNob3JzLmZpbGw6IHBhcmVudAorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91
dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIlNlbGVj
dCBhIGhvc3QgZmlyc3QuIEVuYWJsZSByZWFsdGltZSBzdGF0cyBpbiBWaWJlcG9sbG8gYW5kIGNy
ZWF0ZSBhIHJlYWQtb25seSB0b2tlbiBmb3IgR0VUIC9hcGkvaG9zdC9zdGF0cy4gR2FtZVN0cmVh
bSBwYWlyaW5nIGRvZXMgbm90IGdyYW50IHRoaXMgYWNjZXNzLiIpOyBjb2xvcjogVmJUb2tlbnMu
dGV4dERpbSB9CisgICAgICAgICAgICAgICAgICAgIFRleHRGaWVsZCB7IGlkOiB1cmxJbnB1dDsg
TGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgcGxhY2Vob2xkZXJUZXh0OiBxc1RyKCJIVFRQUyBob3N0
IFVSTCwgZS5nLiBodHRwczovLzE5Mi4xNjguMS4xMDo0Nzk5MCIpOyBzZWxlY3RCeU1vdXNlOiB0
cnVlIH0KKyAgICAgICAgICAgICAgICAgICAgVGV4dEZpZWxkIHsgaWQ6IHRva2VuSW5wdXQ7IExh
eW91dC5maWxsV2lkdGg6IHRydWU7IHBsYWNlaG9sZGVyVGV4dDogcXNUcigiUmVhZC1vbmx5IEFQ
SSB0b2tlbiAoYmxhbmsga2VlcHMgc2F2ZWQgdG9rZW4pIik7IGVjaG9Nb2RlOiBUZXh0SW5wdXQu
UGFzc3dvcmQ7IHNlbGVjdEJ5TW91c2U6IHRydWUgfQorICAgICAgICAgICAgICAgICAgICBUZXh0
RmllbGQgeyBpZDogcGluSW5wdXQ7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHBsYWNlaG9sZGVy
VGV4dDogcXNUcigiU0hBLTI1NiBjZXJ0aWZpY2F0ZSBmaW5nZXJwcmludCBmb3IgYSBzZWxmLXNp
Z25lZCBob3N0Iik7IHNlbGVjdEJ5TW91c2U6IHRydWUgfQorICAgICAgICAgICAgICAgICAgICBM
YWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6
IHFzVHIoIlZlcmlmeSBhIHNlbGYtc2lnbmVkIGNlcnRpZmljYXRlJ3MgU0hBLTI1NiBmaW5nZXJw
cmludCBvbiB0aGUgaG9zdCBiZWZvcmUgc2F2aW5nIGl0LiBUb2tlbiBpcyBzdG9yZWQgcHJpdmF0
ZWx5IG9uIHRoaXMgVVNCOyBpdCBpcyBub3QgZW5jcnlwdGVkLiBVbnN1cHBvcnRlZCBvciBtaXNz
aW5nIHNlbnNvcnMgc2hvdyBOL0EuIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAg
ICAgICAgICAgICAgICAgQnV0dG9uIHsgdGV4dDogcXNUcigiU2F2ZSAmIGNvbm5lY3QiKTsgb25D
bGlja2VkOiB7IGlmIChDcmltc29uU3RhdHVzLmNvbmZpZ3VyZSh1cmxJbnB1dC50ZXh0LCB0b2tl
bklucHV0LnRleHQsIHBpbklucHV0LnRleHQpKSB0b2tlbklucHV0LnRleHQgPSAiIiB9IH0KKyAg
ICAgICAgICAgICAgICB9CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9Cit9CmRpZmYg
LS1naXQgYS9hcHAvZ3VpL0VjbGlwc2VBYm91dERpYWxvZy5xbWwgYi9hcHAvZ3VpL0VjbGlwc2VB
Ym91dERpYWxvZy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLmYzZmZi
MmM2Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9FY2xpcHNlQWJvdXREaWFsb2cucW1sCkBA
IC0wLDAgKzEsMzQgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJv
bHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0IFF0UXVpY2suQ29udHJv
bHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK05hdmlnYWJsZURp
YWxvZyB7CisgICAgaWQ6IHBhbmVsCisgICAgcHJvcGVydHkgdmFyIGluZm86ICh7fSkKKyAgICB3
aWR0aDogTWF0aC5taW4oNTIwLHBhcmVudC53aWR0aC0zMikKKyAgICB0aXRsZTogcXNUcigiQWJv
dXQgRWNsaXBzZSIpCisgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuQ2xvc2UKKyAgICBNYXRl
cmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICBNYXRlcmlhbC5hY2NlbnQ6IFZi
VG9rZW5zLmFjY2VudAorICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7IHJhZGl1czogVmJUb2tl
bnMucmFkaXVzRGlhbG9nOyBjb2xvcjogVmJUb2tlbnMuYmdFbGV2OyBib3JkZXIuY29sb3I6IFZi
VG9rZW5zLnN0cm9rZQorICAgICAgICBSZWN0YW5nbGUgeyBhbmNob3JzLmZpbGw6IHBhcmVudDsg
Y29sb3I6ICJ0cmFuc3BhcmVudCI7IGdyYWRpZW50OiBHcmFkaWVudCB7IEdyYWRpZW50U3RvcCB7
IHBvc2l0aW9uOiAwOyBjb2xvcjogUXQucmdiYSgxLDEsMSwwLjAzNSkgfSBHcmFkaWVudFN0b3Ag
eyBwb3NpdGlvbjogMTsgY29sb3I6ICJ0cmFuc3BhcmVudCIgfSB9IH0KKyAgICB9CisgICAgY29u
dGVudEl0ZW06IENvbHVtbkxheW91dCB7CisgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNl
MworICAgICAgICBJbWFnZSB7IHNvdXJjZTogInFyYzovcmVzL2VjbGlwc2UtaWNvbi5zdmciOyBz
b3VyY2VTaXplLndpZHRoOiA5Njsgc291cmNlU2l6ZS5oZWlnaHQ6IDk2OyBMYXlvdXQuYWxpZ25t
ZW50OiBRdC5BbGlnbkhDZW50ZXI7IExheW91dC5wcmVmZXJyZWRXaWR0aDogOTY7IExheW91dC5w
cmVmZXJyZWRIZWlnaHQ6IDk2IH0KKyAgICAgICAgTGFiZWwgeyB0ZXh0OiAiRUNMSVBTRSI7IGNv
bG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmZhbWlseTogVmJUb2tlbnMuZm9udERpc3BsYXk7IGZv
bnQucGl4ZWxTaXplOiAyNDsgZm9udC5sZXR0ZXJTcGFjaW5nOiA0OyBMYXlvdXQuYWxpZ25tZW50
OiBRdC5BbGlnbkhDZW50ZXIgfQorICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIk1hZGUgYnkg
VGgzRDNjazNyIik7IGNvbG9yOiBWYlRva2Vucy5hY2NlbnQ7IExheW91dC5hbGlnbm1lbnQ6IFF0
LkFsaWduSENlbnRlciB9CisgICAgICAgIExhYmVsIHsKKyAgICAgICAgICAgIExheW91dC5maWxs
V2lkdGg6IHRydWU7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB3cmFwTW9kZTogVGV4dC5X
cmFwOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbQorICAgICAgICAgICAgdGV4dDogcXNUcigiT1M6
ICUxICUyXG5UYXJnZXQ6ICUzXG5GZWRvcmE6ICU0XG5LZXJuZWw6ICU1XG5FY2xpcHNlIGZyb250
ZW5kOiAlNiDigKIgY3VzdG9taXplZCIpCisgICAgICAgICAgICAgICAgLmFyZygocGFuZWwuaW5m
by5vcyB8fCB7fSkuTkFNRSB8fCAiTW9vbmxpZ2h0LU9TIikKKyAgICAgICAgICAgICAgICAuYXJn
KChwYW5lbC5pbmZvLm9zIHx8IHt9KS5WRVJTSU9OIHx8IHFzVHIoIlVuYXZhaWxhYmxlIikpCisg
ICAgICAgICAgICAgICAgLmFyZygocGFuZWwuaW5mby5vcyB8fCB7fSkuVEFSR0VUIHx8IHFzVHIo
IlVuYXZhaWxhYmxlIikpCisgICAgICAgICAgICAgICAgLmFyZygocGFuZWwuaW5mby5vcyB8fCB7
fSkuRkVET1JBIHx8IHFzVHIoIlVuYXZhaWxhYmxlIikpCisgICAgICAgICAgICAgICAgLmFyZyhw
YW5lbC5pbmZvLmtlcm5lbCB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAg
IC5hcmcoUXQuYXBwbGljYXRpb24udmVyc2lvbiB8fCAiMC41LjAiKQorICAgICAgICB9CisgICAg
ICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsg
Y29sb3I6IFZiVG9rZW5zLnRleHREaW07IHRleHQ6IHFzVHIoIkEgbGlnaHR3ZWlnaHQgTW9vbmxp
Z2h0LU9TIGZyb250ZW5kLiBCYXNlZCBvbiBWaWJlbWlzIGFuZCBNb29ubGlnaHQ7IG9yaWdpbmFs
IG9wZW4tc291cmNlIGNyZWRpdHMgYW5kIGxpY2Vuc2VzIHJlbWFpbiBhdmFpbGFibGUgaW4gU2V0
dGluZ3MuIFVwZGF0ZXMgYXJlIG1hbmFnZWQgYnkgTW9vbmxpZ2h0LU9TLiIpIH0KKyAgICB9Cit9
CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0VjbGlwc2VBY3Rpb25CdXR0b24ucW1sIGIvYXBwL2d1aS9F
Y2xpcHNlQWN0aW9uQnV0dG9uLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
MC4uNjMxMzI3MjgKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0VjbGlwc2VBY3Rpb25CdXR0
b24ucW1sCkBAIC0wLDAgKzEsMzIgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVp
Y2suQ29udHJvbHMgMi41CitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK0J1dHRvbiB7Cisg
ICAgaWQ6IGJ1dHRvbgorICAgIHByb3BlcnR5IHN0cmluZyBpY29uU291cmNlOiAiIgorICAgIGlt
cGxpY2l0SGVpZ2h0OiA0NAorICAgIGltcGxpY2l0V2lkdGg6IE1hdGgubWF4KDEwMCwgY29udGVu
dEl0ZW0uaW1wbGljaXRXaWR0aCArIDI4KQorICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250
Qm9keQorICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlTGFiZWwKKyAgICBBY2Nlc3Np
YmxlLm5hbWU6IHRleHQKKyAgICBhY3RpdmVGb2N1c09uVGFiOiB0cnVlCisgICAgS2V5cy5vblJl
dHVyblByZXNzZWQ6IGlmIChlbmFibGVkKSBjbGlja2VkKCkKKyAgICBLZXlzLm9uRW50ZXJQcmVz
c2VkOiBpZiAoZW5hYmxlZCkgY2xpY2tlZCgpCisgICAgS2V5cy5vblJpZ2h0UHJlc3NlZDogbmV4
dEl0ZW1JbkZvY3VzQ2hhaW4odHJ1ZSkuZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAg
ICBLZXlzLm9uTGVmdFByZXNzZWQ6IG5leHRJdGVtSW5Gb2N1c0NoYWluKGZhbHNlKS5mb3JjZUFj
dGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgIEtleXMub25Eb3duUHJlc3NlZDogbmV4dEl0ZW1J
bkZvY3VzQ2hhaW4odHJ1ZSkuZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICBLZXlz
Lm9uVXBQcmVzc2VkOiBuZXh0SXRlbUluRm9jdXNDaGFpbihmYWxzZSkuZm9yY2VBY3RpdmVGb2N1
cyhRdC5UYWJGb2N1cykKKyAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgeworICAgICAgICByYWRp
dXM6IFZiVG9rZW5zLnJhZGl1c0NvbnRyb2wKKyAgICAgICAgY29sb3I6IGJ1dHRvbi5kb3duID8g
VmJUb2tlbnMuYmdFbGV2MiA6IGJ1dHRvbi5ob3ZlcmVkID8gVmJUb2tlbnMuYmdFbGV2MiA6IFZi
VG9rZW5zLmJnV2luZG93CisgICAgICAgIGJvcmRlci53aWR0aDogYnV0dG9uLmFjdGl2ZUZvY3Vz
ID8gMiA6IDEKKyAgICAgICAgYm9yZGVyLmNvbG9yOiBidXR0b24uYWN0aXZlRm9jdXMgfHwgYnV0
dG9uLmhvdmVyZWQgPyBWYlRva2Vucy5hY2NlbnQgOiBWYlRva2Vucy5zdHJva2UKKyAgICAgICAg
b3BhY2l0eTogYnV0dG9uLmVuYWJsZWQgPyAxIDogMC41CisgICAgfQorICAgIGNvbnRlbnRJdGVt
OiBSb3cgeworICAgICAgICBzcGFjaW5nOiA4CisgICAgICAgIG9wYWNpdHk6IGJ1dHRvbi5lbmFi
bGVkID8gMSA6IDAuNQorICAgICAgICBJbWFnZSB7IHZpc2libGU6IGJ1dHRvbi5pY29uU291cmNl
ICE9PSAiIjsgc291cmNlOiBidXR0b24uaWNvblNvdXJjZTsgd2lkdGg6IHZpc2libGUgPyAyMCA6
IDA7IGhlaWdodDogMjA7IGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENl
bnRlciB9CisgICAgICAgIExhYmVsIHsgdGV4dDogYnV0dG9uLnRleHQ7IHRleHRGb3JtYXQ6IFRl
eHQuUGxhaW5UZXh0OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udDogYnV0dG9uLmZvbnQ7IGFu
Y2hvcnMudmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlciB9CisgICAgfQorfQpk
aWZmIC0tZ2l0IGEvYXBwL2d1aS9FY2xpcHNlQ29udHJvbENlbnRlci5xbWwgYi9hcHAvZ3VpL0Vj
bGlwc2VDb250cm9sQ2VudGVyLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
MC4uYzI1ZDE1ZmIKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0VjbGlwc2VDb250cm9sQ2Vu
dGVyLnFtbApAQCAtMCwwICsxLDE2MyBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRR
dWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkxheW91dHMgMS4zCitpbXBvcnQgUXRR
dWljay5Db250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAor
aW1wb3J0IFN5c3RlbUNvbnRyb2xzIDEuMAoraW1wb3J0IENyaW1zb25TdGF0dXMgMS4wCitpbXBv
cnQgU3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCitpbXBvcnQgRWNsaXBzZVByb2ZpbGVzIDEuMAor
CitEcmF3ZXIgeworICAgIGlkOiBwYW5lbAorICAgIGVkZ2U6IFF0LlJpZ2h0RWRnZQorICAgIHdp
ZHRoOiBNYXRoLm1pbig1NjAsIHBhcmVudC53aWR0aCAtIDI0KQorICAgIGhlaWdodDogcGFyZW50
LmhlaWdodAorICAgIG1vZGFsOiB0cnVlCisgICAgZW50ZXI6IFRyYW5zaXRpb24geyBOdW1iZXJB
bmltYXRpb24geyBwcm9wZXJ0eTogInBvc2l0aW9uIjsgZnJvbTogMDsgdG86IDE7IGR1cmF0aW9u
OiBWYlRva2Vucy5zaGVldEluTXMgfSB9CisgICAgZXhpdDogVHJhbnNpdGlvbiB7IE51bWJlckFu
aW1hdGlvbiB7IHByb3BlcnR5OiAicG9zaXRpb24iOyBmcm9tOiAxOyB0bzogMDsgZHVyYXRpb246
IFZiVG9rZW5zLnNoZWV0SW5NcyB9IH0KKyAgICBwcm9wZXJ0eSB2YXIgaG9zdDogKHt9KQorICAg
IHByb3BlcnR5IGJvb2wgY2FuV2FrZTogZmFsc2UKKyAgICBwcm9wZXJ0eSBib29sIGNhbk1hbmFn
ZTogZmFsc2UKKyAgICBwcm9wZXJ0eSBzdHJpbmcgbmV4dFBhbmVsOiAiIgorICAgIHByb3BlcnR5
IHN0cmluZyBtZXNzYWdlOiAiIgorICAgIHByb3BlcnR5IHZhciBzYXZlZE5hbWVzOiBbXQorICAg
IHByb3BlcnR5IHN0cmluZyBwb3dlckFjdGlvbjogIiIKKyAgICBzaWduYWwgbmF2aWdhdGVSZXF1
ZXN0ZWQoc3RyaW5nIGRlc3RpbmF0aW9uKQorICAgIHNpZ25hbCB3YWtlUmVxdWVzdGVkKCkKKyAg
ICBNYXRlcmlhbC50aGVtZTogTWF0ZXJpYWwuRGFyaworICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6
IFZiVG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50Cisg
ICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsgY29sb3I6IFZiVG9rZW5zLmJnRWxldjsgYm9yZGVy
LmNvbG9yOiBWYlRva2Vucy5zdHJva2UKKyAgICAgICAgUmVjdGFuZ2xlIHsgYW5jaG9ycy5maWxs
OiBwYXJlbnQ7IGNvbG9yOiAidHJhbnNwYXJlbnQiOyBncmFkaWVudDogR3JhZGllbnQgeyBHcmFk
aWVudFN0b3AgeyBwb3NpdGlvbjogMDsgY29sb3I6IFF0LnJnYmEoMSwxLDEsMC4wMzUpIH0gR3Jh
ZGllbnRTdG9wIHsgcG9zaXRpb246IDE7IGNvbG9yOiAidHJhbnNwYXJlbnQiIH0gfSB9CisgICAg
fQorICAgIGZ1bmN0aW9uIGRlZmVyKGRlc3RpbmF0aW9uKSB7IG5leHRQYW5lbCA9IGRlc3RpbmF0
aW9uOyBjbG9zZSgpIH0KKyAgICBmdW5jdGlvbiBhcHBseSh2YWx1ZXMpIHsKKyAgICAgICAgaWYg
KCF2YWx1ZXMud2lkdGgpIHsgbWVzc2FnZSA9IHFzVHIoIlNhdmUgdGhpcyBwcm9maWxlIGZpcnN0
LiIpOyByZXR1cm4gfQorICAgICAgICBTdHJlYW1pbmdQcmVmZXJlbmNlcy53aWR0aCA9IHZhbHVl
cy53aWR0aAorICAgICAgICBTdHJlYW1pbmdQcmVmZXJlbmNlcy5oZWlnaHQgPSB2YWx1ZXMuaGVp
Z2h0CisgICAgICAgIFN0cmVhbWluZ1ByZWZlcmVuY2VzLmZwcyA9IHZhbHVlcy5mcHMKKyAgICAg
ICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMuYml0cmF0ZUticHMgPSB2YWx1ZXMuYml0cmF0ZUticHMK
KyAgICAgICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMuc2F2ZSgpCisgICAgICAgIG1lc3NhZ2UgPSBx
c1RyKCJQcm9maWxlIGFwcGxpZWQgZm9yIHRoZSBuZXh0IHN0cmVhbS4iKQorICAgIH0KKyAgICBv
bk9wZW5lZDogeyBtZXNzYWdlID0gIiI7IFN5c3RlbUNvbnRyb2xzLm9wZW4oImNlbnRlciIpOyBw
cm9maWxlTmFtZS50ZXh0ID0gIkdhbWluZyI7IHNhdmVkTmFtZXMgPSBFY2xpcHNlUHJvZmlsZXMu
bmFtZXMoaG9zdC5pZCB8fCAiIikgfQorICAgIG9uQ2xvc2VkOiB7CisgICAgICAgIHBvd2VyRGlh
bG9nLmNsb3NlKCk7IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCk7IHN0YWNrVmlldy5mb3JjZUFjdGl2
ZUZvY3VzKCkKKyAgICAgICAgaWYgKG5leHRQYW5lbCAhPT0gIiIpIHsgdmFyIGRlc3RpbmF0aW9u
ID0gbmV4dFBhbmVsOyBuZXh0UGFuZWwgPSAiIjsgbmF2aWdhdGVSZXF1ZXN0ZWQoZGVzdGluYXRp
b24pIH0KKyAgICB9CisgICAgY29udGVudEl0ZW06IENvbHVtbkxheW91dCB7CisgICAgICAgIGFu
Y2hvcnMuZmlsbDogcGFyZW50OyBhbmNob3JzLm1hcmdpbnM6IDIwOyBzcGFjaW5nOiBWYlRva2Vu
cy5zcGFjZTMKKyAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lk
dGg6IHRydWUKKyAgICAgICAgICAgIExhYmVsIHsgdGV4dDogcXNUcigiRWNsaXBzZSDigKIgQ29u
dHJvbCBjZW50ZXIiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQuZmFtaWx5OiBWYlRva2Vu
cy5mb250RGlzcGxheTsgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQu
ZmlsbFdpZHRoOiB0cnVlIH0KKyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0
OiBxc1RyKCJDbG9zZSIpOyBvbkNsaWNrZWQ6IHBhbmVsLmNsb3NlKCkgfQorICAgICAgICB9Cisg
ICAgICAgIFNjcm9sbFZpZXcgeworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsg
TGF5b3V0LmZpbGxIZWlnaHQ6IHRydWUKKyAgICAgICAgICAgIGNsaXA6IHRydWU7IGNvbnRlbnRX
aWR0aDogYXZhaWxhYmxlV2lkdGgKKyAgICAgICAgICAgIENvbHVtbkxheW91dCB7CisgICAgICAg
ICAgICAgICAgd2lkdGg6IHBhcmVudC53aWR0aDsgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCisg
ICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0
OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogQ3JpbXNvblN0YXR1
cy5sb2NhbC5uZXR3b3JrIHx8IHFzVHIoIk5ldHdvcmsgdW5hdmFpbGFibGUiKTsgY29sb3I6IFZi
VG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0
aDogdHJ1ZTsgdGV4dDogQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAwID8g
cXNUcigiQmF0dGVyeSAlMSUg4oCiICUyIikuYXJnKENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVy
eVBlcmNlbnQpLmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlTdGF0ZSkgOiBxc1RyKCJC
YXR0ZXJ5IHVuYXZhaWxhYmxlIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltOyB3cmFwTW9kZTog
VGV4dC5XcmFwIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiV2ktRmkiKTsgaWNvblNvdXJj
ZTogInFyYzovcmVzL2NyaW1zb24tbmV0d29yay5zdmciOyBvbkNsaWNrZWQ6IHBhbmVsLmRlZmVy
KCJ3aWZpIikgfQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4
dDogcXNUcigiQmx1ZXRvb3RoIik7IGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWJsdWV0
b290aC5zdmciOyBvbkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJidCIpIH0KKyAgICAgICAgICAgICAg
ICB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBxc1RyKCJBdWRpbyIpOyBjb2xvcjog
VmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlv
dXQgeworICAgICAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisgICAgICAg
ICAgICAgICAgICAgIFNsaWRlciB7CisgICAgICAgICAgICAgICAgICAgICAgICBpZDogdm9sdW1l
U2xpZGVyCisgICAgICAgICAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBm
cm9tOiAwOyB0bzogMTAwOyBzdGVwU2l6ZTogMQorICAgICAgICAgICAgICAgICAgICAgICAgdmFs
dWU6IFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSA9PT0gdW5kZWZpbmVkIHx8IFN5c3RlbUNv
bnRyb2xzLnN0YXRlLnZvbHVtZSA9PT0gbnVsbCA/IDAgOiBTeXN0ZW1Db250cm9scy5zdGF0ZS52
b2x1bWUKKyAgICAgICAgICAgICAgICAgICAgICAgIGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5i
dXN5ICYmIFN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVtZSAhPT0gdW5kZWZpbmVkICYmIFN5c3Rl
bUNvbnRyb2xzLnN0YXRlLnZvbHVtZSAhPT0gbnVsbAorICAgICAgICAgICAgICAgICAgICAgICAg
QWNjZXNzaWJsZS5uYW1lOiBxc1RyKCJTcGVha2VyIHZvbHVtZSIpCisgICAgICAgICAgICAgICAg
ICAgICAgICBvbk1vdmVkOiBpZiAoIXByZXNzZWQgJiYgZW5hYmxlZCkgU3lzdGVtQ29udHJvbHMu
cmVxdWVzdCgiY2VudGVyLXZvbHVtZSIsIFN0cmluZyhNYXRoLnJvdW5kKHZhbHVlKSkpCisgICAg
ICAgICAgICAgICAgICAgICAgICBvblByZXNzZWRDaGFuZ2VkOiBpZiAoIXByZXNzZWQgJiYgZW5h
YmxlZCkgU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLXZvbHVtZSIsIFN0cmluZyhNYXRo
LnJvdW5kKHZhbHVlKSkpCisgICAgICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICAg
ICAgTGFiZWwgeyBpZDogdm9sdW1lUmVhZG91dDsgdGV4dDogTWF0aC5yb3VuZCh2b2x1bWVTbGlk
ZXIudmFsdWUpKyIlIjsgY29sb3I6IFZiVG9rZW5zLnRleHQgfQorICAgICAgICAgICAgICAgICAg
ICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogU3lzdGVtQ29udHJvbHMuc3RhdGUubXV0ZWQg
PyBxc1RyKCJVbm11dGUiKSA6IHFzVHIoIk11dGUiKTsgZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xz
LmJ1c3kgJiYgU3lzdGVtQ29udHJvbHMuc3RhdGUudm9sdW1lICE9PSBudWxsICYmIFN5c3RlbUNv
bnRyb2xzLnN0YXRlLnZvbHVtZSAhPT0gdW5kZWZpbmVkOyBvbkNsaWNrZWQ6IFN5c3RlbUNvbnRy
b2xzLnJlcXVlc3QoImNlbnRlci1tdXRlIikgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAg
ICAgICAgICBDb21ib0JveCB7CisgICAgICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6
IHRydWUKKyAgICAgICAgICAgICAgICAgICAgbW9kZWw6IFN5c3RlbUNvbnRyb2xzLnN0YXRlLnNp
bmtzIHx8IFtdOyB0ZXh0Um9sZTogIm5hbWUiCisgICAgICAgICAgICAgICAgICAgIGVuYWJsZWQ6
ICFTeXN0ZW1Db250cm9scy5idXN5ICYmIGNvdW50ID4gMAorICAgICAgICAgICAgICAgICAgICBB
Y2Nlc3NpYmxlLm5hbWU6IHFzVHIoIkF1ZGlvIG91dHB1dCIpCisgICAgICAgICAgICAgICAgICAg
IGN1cnJlbnRJbmRleDogeyB2YXIgbGlzdCA9IFN5c3RlbUNvbnRyb2xzLnN0YXRlLnNpbmtzIHx8
IFtdOyBmb3IgKHZhciBpPTA7aTxsaXN0Lmxlbmd0aDtpKyspIGlmIChsaXN0W2ldLmRlZmF1bHQp
IHJldHVybiBpOyByZXR1cm4gLTEgfQorICAgICAgICAgICAgICAgICAgICBjb250ZW50SXRlbTog
TGFiZWwgeyB0ZXh0OiBwYXJlbnQuZGlzcGxheVRleHQ7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5U
ZXh0OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgdmVydGljYWxBbGlnbm1lbnQ6IFRleHQuQWxpZ25W
Q2VudGVyOyBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0IH0KKyAgICAgICAgICAgICAgICAgICAgZGVs
ZWdhdGU6IEl0ZW1EZWxlZ2F0ZSB7IHdpZHRoOiBwYXJlbnQud2lkdGg7IGNvbnRlbnRJdGVtOiBM
YWJlbCB7IHRleHQ6IG1vZGVsRGF0YS5uYW1lOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsg
Y29sb3I6IFZiVG9rZW5zLnRleHQ7IGVsaWRlOiBUZXh0LkVsaWRlUmlnaHQgfSB9CisgICAgICAg
ICAgICAgICAgICAgIG9uQWN0aXZhdGVkOiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXIt
b3V0cHV0IiwgbW9kZWxbaW5kZXhdLmlkKQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAg
ICAgICBSZXBlYXRlciB7CisgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBbe2tpbmQ6InNjcmVl
biIsbGFiZWw6cXNUcigiU2NyZWVuIGJyaWdodG5lc3MiKX0se2tpbmQ6ImtleWJvYXJkIixsYWJl
bDpxc1RyKCJLZXlib2FyZCBicmlnaHRuZXNzIil9XQorICAgICAgICAgICAgICAgICAgICBkZWxl
Z2F0ZTogQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgICAgIExheW91dC5maWxs
V2lkdGg6IHRydWUKKyAgICAgICAgICAgICAgICAgICAgICAgIHByb3BlcnR5IHZhciBoYXJkd2Fy
ZTogKFN5c3RlbUNvbnRyb2xzLnN0YXRlLmJyaWdodG5lc3MgfHwge30pW21vZGVsRGF0YS5raW5k
XQorICAgICAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBtb2RlbERhdGEubGFiZWwg
KyAoaGFyZHdhcmUgPyAiIOKAoiAiICsgaGFyZHdhcmUucGVyY2VudCArICIlIiA6ICIg4oCiICIg
KyBxc1RyKCJVbmF2YWlsYWJsZSIpKTsgY29sb3I6IFZiVG9rZW5zLnRleHQgfQorICAgICAgICAg
ICAgICAgICAgICAgICAgU2xpZGVyIHsKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICBMYXlv
dXQuZmlsbFdpZHRoOiB0cnVlOyBmcm9tOiBtb2RlbERhdGEua2luZCA9PT0gInNjcmVlbiIgPyA1
IDogMDsgdG86IDEwMDsgc3RlcFNpemU6IDEKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICB2
YWx1ZTogaGFyZHdhcmUgPyBoYXJkd2FyZS5wZXJjZW50IDogMDsgZW5hYmxlZDogISFoYXJkd2Fy
ZSAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAgICAgICAgICAgICAgICAgICAgICAgIEFj
Y2Vzc2libGUubmFtZTogbW9kZWxEYXRhLmxhYmVsCisgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgb25Nb3ZlZDogaWYgKCFwcmVzc2VkICYmIGVuYWJsZWQpIFN5c3RlbUNvbnRyb2xzLnJlcXVl
c3QoImNlbnRlci0iK21vZGVsRGF0YS5raW5kLCBTdHJpbmcoTWF0aC5yb3VuZCh2YWx1ZSkpKQor
ICAgICAgICAgICAgICAgICAgICAgICAgICAgIG9uUHJlc3NlZENoYW5nZWQ6IGlmICghcHJlc3Nl
ZCAmJiBlbmFibGVkKSBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItIittb2RlbERhdGEu
a2luZCwgU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSkKKyAgICAgICAgICAgICAgICAgICAgICAg
IH0KKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiUmVmcmVzaCBjb250cm9scyIp
OyBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiBTeXN0ZW1Db250cm9s
cy5yZXF1ZXN0KCJjZW50ZXItbGlzdCIpIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6
IHFzVHIoIkhvc3QiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQuYm9sZDogdHJ1ZSB9Cisg
ICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0
OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcGFuZWwuaG9zdC51
cmwgfHwgcXNUcigiU2VsZWN0IGEgaG9zdCBpbiB0aGUgbGF1bmNoZXIuIik7IGNvbG9yOiBWYlRv
a2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAg
ICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiSG9zdCBzdGF0cyIpOyBl
bmFibGVkOiAhIXBhbmVsLmhvc3QuaWQ7IGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWhv
c3Quc3ZnIjsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigiaG9zdCIpIH0KKyAgICAgICAgICAgICAg
ICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIldha2UgaG9zdCIpOyBlbmFi
bGVkOiAhIXBhbmVsLmhvc3QuaWQgJiYgcGFuZWwuY2FuV2FrZTsgb25DbGlja2VkOiB7IHBhbmVs
Lndha2VSZXF1ZXN0ZWQoKTsgcGFuZWwubWVzc2FnZSA9IHFzVHIoIldha2UgcmVxdWVzdCBzZW50
OyB0aGUgaG9zdCBtdXN0IHN1cHBvcnQgV2FrZS1vbi1MQU4uIikgfSB9CisgICAgICAgICAgICAg
ICAgfQorICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJP
cGVuIGhvc3QgbWFuYWdlbWVudCIpOyBlbmFibGVkOiAhIXBhbmVsLmhvc3QudXJsICYmIHBhbmVs
LmNhbk1hbmFnZTsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigibWFuYWdlbWVudCIpIH0KKyAgICAg
ICAgICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIlN0cmVhbSBwcm9maWxlcyIpOyBjb2xvcjog
VmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7
IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHBhbmVs
Lmhvc3QuaWQgPyBxc1RyKCJTYXZlZCBmb3IgdGhlIHNlbGVjdGVkIGhvc3QuIEFwcGx5IGJlZm9y
ZSBzdGFydGluZyBhIHN0cmVhbS4iKSA6IHFzVHIoIkdsb2JhbCBwcm9maWxlcy4gQXBwbHkgYmVm
b3JlIHN0YXJ0aW5nIGEgc3RyZWFtLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAg
ICAgICAgICAgICAgQ29tYm9Cb3ggeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBtb2RlbDogcGFu
ZWwuc2F2ZWROYW1lczsgdmlzaWJsZTogY291bnQgPiAwOyBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIo
IlNhdmVkIHByb2ZpbGVzIik7IG9uQWN0aXZhdGVkOiBwcm9maWxlTmFtZS50ZXh0ID0gbW9kZWxb
aW5kZXhdIH0KKyAgICAgICAgICAgICAgICBUZXh0RmllbGQgeyBpZDogcHJvZmlsZU5hbWU7IExh
eW91dC5maWxsV2lkdGg6IHRydWU7IG1heGltdW1MZW5ndGg6IDQ4OyBwbGFjZWhvbGRlclRleHQ6
IHFzVHIoIlByb2ZpbGUgbmFtZSIpOyBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIlByb2ZpbGUgbmFt
ZSIpIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAgICAgICBF
Y2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiU2F2ZSBjdXJyZW50Iik7IG9uQ2xpY2tl
ZDogeyBwYW5lbC5tZXNzYWdlID0gRWNsaXBzZVByb2ZpbGVzLnNhdmUocGFuZWwuaG9zdC5pZCB8
fCAiIiwgcHJvZmlsZU5hbWUudGV4dCwge3dpZHRoOlN0cmVhbWluZ1ByZWZlcmVuY2VzLndpZHRo
LGhlaWdodDpTdHJlYW1pbmdQcmVmZXJlbmNlcy5oZWlnaHQsZnBzOlN0cmVhbWluZ1ByZWZlcmVu
Y2VzLmZwcyxiaXRyYXRlS2JwczpTdHJlYW1pbmdQcmVmZXJlbmNlcy5iaXRyYXRlS2Jwc30pID8g
cXNUcigiUHJvZmlsZSBzYXZlZC4iKSA6IHFzVHIoIlByb2ZpbGUgY291bGQgbm90IGJlIHNhdmVk
LiIpOyBwYW5lbC5zYXZlZE5hbWVzID0gRWNsaXBzZVByb2ZpbGVzLm5hbWVzKHBhbmVsLmhvc3Qu
aWQgfHwgIiIpIH0gfQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsg
dGV4dDogcXNUcigiQXBwbHkgc2F2ZWQiKTsgb25DbGlja2VkOiBwYW5lbC5hcHBseShFY2xpcHNl
UHJvZmlsZXMubG9hZChwYW5lbC5ob3N0LmlkIHx8ICIiLCBwcm9maWxlTmFtZS50ZXh0KSkgfQor
ICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAg
ICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiRGVza3RvcCBwcmVz
ZXQiKTsgb25DbGlja2VkOiBwYW5lbC5hcHBseSh7d2lkdGg6MTI4MCxoZWlnaHQ6ODAwLGZwczo2
MCxiaXRyYXRlS2JwczoxNTAwMH0pIH0KKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlv
bkJ1dHRvbiB7IHRleHQ6IHFzVHIoIkxvdyBiYW5kd2lkdGgiKTsgb25DbGlja2VkOiBwYW5lbC5h
cHBseSh7d2lkdGg6MTI4MCxoZWlnaHQ6NzIwLGZwczozMCxiaXRyYXRlS2Jwczo1MDAwfSkgfQor
ICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIkFw
cGVhcmFuY2UgJiBhY2Nlc3NpYmlsaXR5Iik7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmJv
bGQ6IHRydWUgfQorICAgICAgICAgICAgICAgIENvbWJvQm94IHsKKyAgICAgICAgICAgICAgICAg
ICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgbW9kZWw6IFtxc1RyKCJUZXh0IDEwMCUiKSxxc1Ry
KCJUZXh0IDExMCUiKSxxc1RyKCJUZXh0IDEyNSUiKV0KKyAgICAgICAgICAgICAgICAgICAgQWNj
ZXNzaWJsZS5uYW1lOiBxc1RyKCJUZXh0IHNpemUiKQorICAgICAgICAgICAgICAgICAgICBjdXJy
ZW50SW5kZXg6IEVjbGlwc2VQcm9maWxlcy50ZXh0U2NhbGUgPT09IDEyNSA/IDIgOiBFY2xpcHNl
UHJvZmlsZXMudGV4dFNjYWxlID09PSAxMTAgPyAxIDogMAorICAgICAgICAgICAgICAgICAgICBv
bkFjdGl2YXRlZDogRWNsaXBzZVByb2ZpbGVzLnRleHRTY2FsZSA9IFsxMDAsMTEwLDEyNV1baW5k
ZXhdCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIFN3aXRjaCB7IHRleHQ6IHFz
VHIoIlJlZHVjZSBtb3Rpb24iKTsgY2hlY2tlZDogRWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rp
b247IG9uVG9nZ2xlZDogRWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb24gPSBjaGVja2VkIH0K
KyAgICAgICAgICAgICAgICBTd2l0Y2ggeyB0ZXh0OiBxc1RyKCJIaWdoZXIgY29udHJhc3QiKTsg
Y2hlY2tlZDogRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdDsgb25Ub2dnbGVkOiBFY2xpcHNl
UHJvZmlsZXMuaGlnaENvbnRyYXN0ID0gY2hlY2tlZCB9CisgICAgICAgICAgICAgICAgTGFiZWwg
eyB0ZXh0OiBxc1RyKCJUb29scyAmIHJlY292ZXJ5Iik7IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBm
b250LmJvbGQ6IHRydWUgfQorICAgICAgICAgICAgICAgIFJvd0xheW91dCB7CisgICAgICAgICAg
ICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJBbGwgc2V0dGluZ3Mi
KTsgaWNvblNvdXJjZTogInFyYzovcmVzL3NldHRpbmdzLnN2ZyI7IG9uQ2xpY2tlZDogcGFuZWwu
ZGVmZXIoInNldHRpbmdzIikgfQorICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0
dG9uIHsgdGV4dDogcXNUcigiU3VwcG9ydCByZXBvcnQiKTsgZW5hYmxlZDogIVN5c3RlbUNvbnRy
b2xzLmJ1c3k7IG9uQ2xpY2tlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLXJlcG9y
dCIpIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQu
ZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBxc1RyKCJSZWNvdmVy
eTogQ3RybCtBbHQrRjIgb3BlbnMgdGhlIGRpYWdub3N0aWMgY29uc29sZS4gTWFjIGJyaWdodG5l
c3MsIGtleWJvYXJkLWxpZ2h0IGFuZCB2b2x1bWUga2V5cyByZW1haW4gYXZhaWxhYmxlLiIpOyBj
b2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICAgICAgUm93TGF5b3V0IHsKKyAg
ICAgICAgICAgICAgICAgICAgUmVwZWF0ZXIgeworICAgICAgICAgICAgICAgICAgICAgICAgbW9k
ZWw6IFt7YWN0aW9uOiJyZWJvb3QiLGxhYmVsOnFzVHIoIlJlc3RhcnQiKX0se2FjdGlvbjoicG93
ZXJvZmYiLGxhYmVsOnFzVHIoIlNodXQgZG93biIpfV0KKyAgICAgICAgICAgICAgICAgICAgICAg
IGRlbGVnYXRlOiBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogbW9kZWxEYXRhLmxhYmVsOyBp
Y29uU291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1wb3dlci5zdmciOyBlbmFibGVkOiAhU3lzdGVt
Q29udHJvbHMuYnVzeTsgb25DbGlja2VkOiB7IHBhbmVsLnBvd2VyQWN0aW9uID0gbW9kZWxEYXRh
LmFjdGlvbjsgcG93ZXJEaWFsb2cub3BlbigpIH0gfQorICAgICAgICAgICAgICAgICAgICB9Cisg
ICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0
ZXh0OiBxc1RyKCJBYm91dCBFY2xpcHNlIik7IGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5
OyBvbkNsaWNrZWQ6IHBhbmVsLmRlZmVyKCJhYm91dCIpIH0KKyAgICAgICAgICAgICAgICBMYWJl
bCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB3
cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBwYW5lbC5tZXNzYWdlIHx8IFN5c3RlbUNvbnRyb2xz
LnN0YXR1czsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAgICAgICAgIEJ1c3lJ
bmRpY2F0b3IgeyBydW5uaW5nOiBTeXN0ZW1Db250cm9scy5idXN5OyB2aXNpYmxlOiBydW5uaW5n
OyBMYXlvdXQuYWxpZ25tZW50OiBRdC5BbGlnbkhDZW50ZXIgfQorICAgICAgICAgICAgfQorICAg
ICAgICB9CisgICAgfQorICAgIE5hdmlnYWJsZURpYWxvZyB7CisgICAgICAgIGlkOiBwb3dlckRp
YWxvZworICAgICAgICB3aWR0aDogTWF0aC5taW4oNDQwLCBwYW5lbC53aWR0aCAtIDMyKQorICAg
ICAgICB0aXRsZTogcGFuZWwucG93ZXJBY3Rpb24gPT09ICJyZWJvb3QiID8gcXNUcigiUmVzdGFy
dCBNb29ubGlnaHQtT1M/IikgOiBxc1RyKCJTaHV0IGRvd24gTW9vbmxpZ2h0LU9TPyIpCisgICAg
ICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLlllcyB8IERpYWxvZy5ObworICAgICAgICBNYXRl
cmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAgICAgb25BY2NlcHRlZDogU3lz
dGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLSIrcGFuZWwucG93ZXJBY3Rpb24sIiIsdHJ1ZSkK
KyAgICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgdGV4dDogcXNUcigiVGhpcyBlbmRzIHRoZSBj
dXJyZW50IGxvY2FsIHNlc3Npb24uIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0KKyAgICB9Cit9
CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1BjVmlldy5xbWwgYi9hcHAvZ3VpL1BjVmlldy5xbWwKaW5k
ZXggZjBlNzM5YTguLmY0ZDAxMmI4IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1BjVmlldy5xbWwKKysr
IGIvYXBwL2d1aS9QY1ZpZXcucW1sCkBAIC00NDQsNyArNDQ0LDcgQEAgQ2VudGVyZWRHcmlkVmll
dyB7CiAgICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBtb2RlbC5vbmxpbmUgJiYgbW9k
ZWwucGFpcmVkLAogICAgICAgICAgICAgICAgICAgICAgICAgdHJpZ2dlcjogZnVuY3Rpb24oKSB7
CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdmFyIGNvbXBvbmVudCA9IFF0LmNyZWF0ZUNv
bXBvbmVudCgiQXBwVmlldy5xbWwiKQotICAgICAgICAgICAgICAgICAgICAgICAgICAgIHZhciBh
cHBWaWV3ID0gY29tcG9uZW50LmNyZWF0ZU9iamVjdChzdGFja1ZpZXcsIHsiY29tcHV0ZXJJbmRl
eCI6IGluZGV4LCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUsICJzaG93SGlkZGVuR2FtZXMiOiB0
cnVlLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhvc3RUeXBlIjogbW9kZWwuaG9zdFR5
cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0fSkKKyAgICAgICAgICAgICAgICAg
ICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3
LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgImNyaW1zb25Ib3N0IjogY29tcHV0ZXJNb2RlbC5j
cmltc29uSG9zdChpbmRleCksICJvYmplY3ROYW1lIjogbW9kZWwubmFtZSwgInNob3dIaWRkZW5H
YW1lcyI6IHRydWUsICJob3N0T25saW5lIjogbW9kZWwub25saW5lLCAiaG9zdFR5cGUiOiBtb2Rl
bC5ob3N0VHlwZSwgImhvc3RUcmFuc3BvcnQiOiBtb2RlbC50cmFuc3BvcnR9KQogICAgICAgICAg
ICAgICAgICAgICAgICAgICAgIHN0YWNrVmlldy5wdXNoKGFwcFZpZXcpCiAgICAgICAgICAgICAg
ICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgIH0sCkBAIC01MzUsNyArNTM1LDcgQEAg
Q2VudGVyZWRHcmlkVmlldyB7CiAgICAgICAgICAgICAgICAgZWxzZSBpZiAobW9kZWwucGFpcmVk
KSB7CiAgICAgICAgICAgICAgICAgICAgIC8vIGdvIHRvIGdhbWUgdmlldwogICAgICAgICAgICAg
ICAgICAgICB2YXIgY29tcG9uZW50ID0gUXQuY3JlYXRlQ29tcG9uZW50KCJBcHBWaWV3LnFtbCIp
Ci0gICAgICAgICAgICAgICAgICAgIHZhciBhcHBWaWV3ID0gY29tcG9uZW50LmNyZWF0ZU9iamVj
dChzdGFja1ZpZXcsIHsiY29tcHV0ZXJJbmRleCI6IGluZGV4LCAib2JqZWN0TmFtZSI6IG1vZGVs
Lm5hbWUsICJob3N0T25saW5lIjogbW9kZWwub25saW5lLCAiaG9zdFR5cGUiOiBtb2RlbC5ob3N0
VHlwZSwgImhvc3RUcmFuc3BvcnQiOiBtb2RlbC50cmFuc3BvcnR9KQorICAgICAgICAgICAgICAg
ICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3LCB7ImNv
bXB1dGVySW5kZXgiOiBpbmRleCwgImNyaW1zb25Ib3N0IjogY29tcHV0ZXJNb2RlbC5jcmltc29u
SG9zdChpbmRleCksICJvYmplY3ROYW1lIjogbW9kZWwubmFtZSwgImhvc3RPbmxpbmUiOiBtb2Rl
bC5vbmxpbmUsICJob3N0VHlwZSI6IG1vZGVsLmhvc3RUeXBlLCAiaG9zdFRyYW5zcG9ydCI6IG1v
ZGVsLnRyYW5zcG9ydH0pCiAgICAgICAgICAgICAgICAgICAgIHN0YWNrVmlldy5wdXNoKGFwcFZp
ZXcpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgIGVsc2UgewpkaWZmIC0tZ2l0
IGEvYXBwL2d1aS9RdWlja01lbnUucW1sIGIvYXBwL2d1aS9RdWlja01lbnUucW1sCmluZGV4IGIw
MzNkMjY4Li4wZDk3OTRkZSAxMDA2NDQKLS0tIGEvYXBwL2d1aS9RdWlja01lbnUucW1sCisrKyBi
L2FwcC9ndWkvUXVpY2tNZW51LnFtbApAQCAtNDQ5LDcgKzQ0OSw3IEBAIFJlY3RhbmdsZSB7CiAg
ICAgICAgICAgICB0ZXh0OiBxc1RyKCJRdWl0IGdhbWUiKQogICAgICAgICAgICAgaWNvbjogInBv
d2VyIgogICAgICAgICAgICAgYWN0aW9uOiAicXVpdCIKLSAgICAgICAgICAgIGRlc2NyaXB0aW9u
OiBxc1RyKCJRdWl0IHRoZSBnYW1lIG9uIHRoZSBob3N0IGFuZCByZXR1cm4gdG8gVmliZW1pcyIp
CisgICAgICAgICAgICBkZXNjcmlwdGlvbjogcXNUcigiUXVpdCB0aGUgZ2FtZSBvbiB0aGUgaG9z
dCBhbmQgcmV0dXJuIHRvIEVjbGlwc2UiKQogICAgICAgICB9CiAgICAgICAgIExpc3RFbGVtZW50
IHsKICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlNlcnZlciBjb21tYW5kcyIpCmRpZmYgLS1naXQg
YS9hcHAvZ3VpL1NldHRpbmdzVmlldy5xbWwgYi9hcHAvZ3VpL1NldHRpbmdzVmlldy5xbWwKaW5k
ZXggNDk0ZTM1YmEuLjk0YTBhOWE5IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1NldHRpbmdzVmlldy5x
bWwKKysrIGIvYXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sCkBAIC0xNjgxLDcgKzE2ODEsNyBAQCBJ
dGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAg
ICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9v
bFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDog
cXNUcigiV2hlbiB0aGUgbmV0d29yayBjYW4ndCBzdXN0YWluIHRoZSBjb25maWd1cmVkIGJpdHJh
dGUgYW5kIHRoZSBzdHJlYW0gY29sbGFwc2VzLCBWaWJlbWlzIGF1dG9tYXRpY2FsbHkgcmVjb25u
ZWN0cyBhdCBhIGxvd2VyIGJpdHJhdGUgdW50aWwgdGhlIHN0cmVhbSBpcyB1c2FibGUuIFlvdXIg
c2F2ZWQgYml0cmF0ZSBzZXR0aW5nIGlzIG5ldmVyIGNoYW5nZWQuIikKKyAgICAgICAgICAgICAg
ICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJXaGVuIHRoZSBuZXR3b3JrIGNhbid0IHN1c3RhaW4g
dGhlIGNvbmZpZ3VyZWQgYml0cmF0ZSBhbmQgdGhlIHN0cmVhbSBjb2xsYXBzZXMsIEVjbGlwc2Ug
YXV0b21hdGljYWxseSByZWNvbm5lY3RzIGF0IGEgbG93ZXIgYml0cmF0ZSB1bnRpbCB0aGUgc3Ry
ZWFtIGlzIHVzYWJsZS4gWW91ciBzYXZlZCBiaXRyYXRlIHNldHRpbmcgaXMgbmV2ZXIgY2hhbmdl
ZC4iKQogICAgICAgICAgICAgICAgIH0KIAogICAgICAgICAgICAgICAgIC8vIFZpYmVtaXMgKHBl
cmYgZ3VpZGFuY2UpOiBhZHZpc2Ugd2hlbiB0aGUgYml0cmF0ZSBpcyBzZXQgd2VsbCBhYm92ZSB0
aGUgcmVjb21tZW5kZWQKQEAgLTI0ODIsNyArMjQ4Miw3IEBAIEl0ZW0gewogICAgICAgICAgICAg
ICAgICAgICBUb29sVGlwLmRlbGF5OiAxMDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAu
dGltZW91dDogNTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVy
ZWQKLSAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJJZiBhIHN0cmVhbSBl
bmRzIHVuZXhwZWN0ZWRseSAoYSBuZXR3b3JrIGJsaXAgb3IgdGhlIGhvc3Qgd2FraW5nKSwgVmli
ZW1pcyB3aWxsIHRyeSB0byByZWNvbm5lY3QgYXV0b21hdGljYWxseS4iKQorICAgICAgICAgICAg
ICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIklmIGEgc3RyZWFtIGVuZHMgdW5leHBlY3RlZGx5
IChhIG5ldHdvcmsgYmxpcCBvciB0aGUgaG9zdCB3YWtpbmcpLCBFY2xpcHNlIHdpbGwgdHJ5IHRv
IHJlY29ubmVjdCBhdXRvbWF0aWNhbGx5LiIpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAg
ICAgfQogICAgICAgICB9CkBAIC0yNTQ2LDcgKzI1NDYsNyBAQCBJdGVtIHsKICAgICAgICAgICAg
ICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKIAogICAgICAgICAgICAgICAgIFZiU2VjdGlv
bkhlYWRlciB7Ci0gICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMgU3RyZWFt
aW5nIEVuaGFuY2VtZW50cyIpCisgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkVjbGlw
c2UgU3RyZWFtaW5nIEVuaGFuY2VtZW50cyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAg
ICAgICAgICAgTGFiZWwgewpAQCAtMjc3Niw3ICsyNzc2LDcgQEAgSXRlbSB7CiAKICAgICAgICAg
ICAgICAgICBWYlRvZ2dsZVJvdyB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiBtdXRlT25Gb2N1
c0xvc3NDaGVjawotICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJNdXRlIGF1ZGlvIHN0
cmVhbSB3aGVuIFZpYmVtaXMgaXMgbm90IHRoZSBhY3RpdmUgd2luZG93IikKKyAgICAgICAgICAg
ICAgICAgICAgdGV4dDogcXNUcigiTXV0ZSBhdWRpbyBzdHJlYW0gd2hlbiBFY2xpcHNlIGlzIG5v
dCB0aGUgYWN0aXZlIHdpbmRvdyIpCiAgICAgICAgICAgICAgICAgICAgIHZpc2libGU6IFN5c3Rl
bVByb3BlcnRpZXMuaGFzRGVza3RvcEVudmlyb25tZW50CiAgICAgICAgICAgICAgICAgICAgIGNo
ZWNrZWQ6IFN0cmVhbWluZ1ByZWZlcmVuY2VzLm11dGVPbkZvY3VzTG9zcwogICAgICAgICAgICAg
ICAgICAgICBvbkNoZWNrZWRDaGFuZ2VkOiB7CkBAIC0yNzg2LDcgKzI3ODYsNyBAQCBJdGVtIHsK
ICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAg
ICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52
aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigi
TXV0ZXMgVmliZW1pcydzIGF1ZGlvIHdoZW4geW91IEFsdCtUYWIgb3V0IG9mIHRoZSBzdHJlYW0g
b3IgY2xpY2sgb24gYSBkaWZmZXJlbnQgd2luZG93LiIpCisgICAgICAgICAgICAgICAgICAgIFRv
b2xUaXAudGV4dDogcXNUcigiTXV0ZXMgRWNsaXBzZSdzIGF1ZGlvIHdoZW4geW91IEFsdCtUYWIg
b3V0IG9mIHRoZSBzdHJlYW0gb3IgY2xpY2sgb24gYSBkaWZmZXJlbnQgd2luZG93LiIpCiAgICAg
ICAgICAgICAgICAgfQogICAgICAgICAgICAgfQogICAgICAgICB9CkBAIC0yOTcxLDcgKzI5NzEs
NyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgICAgIGlmIChTdHJlYW1pbmdQcmVmZXJl
bmNlcy5sYW5ndWFnZSAhPT0gbmV3X2xhbmd1YWdlKSB7CiAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMubGFuZ3VhZ2UgPSBsYW5ndWFnZUxpc3RNb2RlbC5n
ZXQoY3VycmVudEluZGV4KS52YWwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiAoIVN0
cmVhbWluZ1ByZWZlcmVuY2VzLnJldHJhbnNsYXRlKCkpIHsKLSAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgVG9vbFRpcC5zaG93KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQgVmliZW1pcyBm
b3IgdGhpcyBjaGFuZ2UgdG8gdGFrZSBlZmZlY3QiKSwgNTAwMCkKKyAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgVG9vbFRpcC5zaG93KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQgRWNsaXBz
ZSBmb3IgdGhpcyBjaGFuZ2UgdG8gdGFrZSBlZmZlY3QiKSwgNTAwMCkKICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZWxzZSB7CiAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgIC8vIEZvcmNlIHRoZSBiYWNrIG9wZXJhdGlvbiB0
byBwb3AgYW55IEFwcFZpZXcgcGFnZXMgdGhhdCBleGlzdC4KQEAgLTMwNTUsMTQgKzMwNTUsMjYg
QEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgIHRleHRSb2xlOiAidGV4dCIKICAgICAgICAg
ICAgICAgICAgICAgaG92ZXJFbmFibGVkOiB0cnVlCiAgICAgICAgICAgICAgICAgICAgIG1vZGVs
OiBMaXN0TW9kZWwgewotICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0
OiBxc1RyKCJUZWFsIChkZWZhdWx0KSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RF
bGVtZW50IHsgdGV4dDogcXNUcigiVGVhbCIpIH0KICAgICAgICAgICAgICAgICAgICAgICAgIExp
c3RFbGVtZW50IHsgdGV4dDogcXNUcigiSW5kaWdvIikgfQogICAgICAgICAgICAgICAgICAgICAg
ICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJHcmVlbiIpIH0KICAgICAgICAgICAgICAgICAg
ICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiQW1iZXIiKSB9CisgICAgICAgICAgICAg
ICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIkNyaW1zb24gKGRlZmF1bHQpIikg
fQorICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJSZWQi
KSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIk9y
YW5nZSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNU
cigiR29sZCIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDog
cXNUcigiTGltZSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4
dDogcXNUcigiTWludCIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsg
dGV4dDogcXNUcigiQ3lhbiIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50
IHsgdGV4dDogcXNUcigiQmx1ZSIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVt
ZW50IHsgdGV4dDogcXNUcigiVmlvbGV0IikgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGlz
dEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJQaW5rIikgfQorICAgICAgICAgICAgICAgICAgICAgICAg
TGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJTaWx2ZXIiKSB9CisgICAgICAgICAgICAgICAgICAg
ICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIlJvc2UiKSB9CiAgICAgICAgICAgICAgICAg
ICAgIH0KICAgICAgICAgICAgICAgICAgICAgQ29tcG9uZW50Lm9uQ29tcGxldGVkOiBjdXJyZW50
SW5kZXggPSBTdHJlYW1pbmdQcmVmZXJlbmNlcy51aUFjY2VudEluZGV4CiAgICAgICAgICAgICAg
ICAgICAgIG9uQWN0aXZhdGVkOiBTdHJlYW1pbmdQcmVmZXJlbmNlcy51aUFjY2VudEluZGV4ID0g
Y3VycmVudEluZGV4Ci0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiVGhl
IGFjY2VudCBjb2xvciB1c2VkIGFjcm9zcyB0aGUgcmVkZXNpZ25lZCBVSS4iKQorICAgICAgICAg
ICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlRoZSBhY2NlbnQgY29sb3IgdXNlZCB0aHJv
dWdob3V0IEVjbGlwc2UuIikKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAw
MAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKICAgICAgICAg
ICAgICAgICB9CkBAIC0zMTQ3LDcgKzMxNTksNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAg
ICAgICAgIFRvb2xUaXAuZGVsYXk6IDEwMDAKICAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xU
aXAudGltZW91dDogNTAwMAogICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxl
OiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlNh
dmUgYWxsIFZpYmVtaXMgc2V0dGluZ3MgdG8gfi92aWJlbWlzLXNldHRpbmdzLmluaSBmb3IgYmFj
a3VwIG9yIHRvIGNvcHkgdG8gYW5vdGhlciBkZXZpY2UuIikKKyAgICAgICAgICAgICAgICAgICAg
ICAgIFRvb2xUaXAudGV4dDogcXNUcigiU2F2ZSBhbGwgRWNsaXBzZSBzZXR0aW5ncyB0byB+L3Zp
YmVtaXMtc2V0dGluZ3MuaW5pIGZvciBiYWNrdXAgb3IgdG8gY29weSB0byBhbm90aGVyIGRldmlj
ZS4iKQogICAgICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICAgICAgQnV0dG9u
IHsKQEAgLTM0MDIsNyArMzQxNCw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICBUb29s
VGlwLnRpbWVvdXQ6IDEwMDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTog
aG92ZXJlZAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlRoaXMgZW5h
YmxlcyB0aGUgY2FwdHVyZSBvZiBzeXN0ZW0td2lkZSBrZXlib2FyZCBzaG9ydGN1dHMgbGlrZSBB
bHQrVGFiIHRoYXQgd291bGQgbm9ybWFsbHkgYmUgaGFuZGxlZCBieSB0aGUgY2xpZW50IE9TIHdo
aWxlIHN0cmVhbWluZy4iKSArICJcblxuIiArCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgcXNUcigiTk9URTogQ2VydGFpbiBrZXlib2FyZCBzaG9ydGN1dHMgbGlrZSBDdHJsK0Fs
dCtEZWwgb24gV2luZG93cyBjYW5ub3QgYmUgaW50ZXJjZXB0ZWQgYnkgYW55IGFwcGxpY2F0aW9u
LCBpbmNsdWRpbmcgVmliZW1pcy4iKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
IHFzVHIoIk5PVEU6IENlcnRhaW4ga2V5Ym9hcmQgc2hvcnRjdXRzIGxpa2UgQ3RybCtBbHQrRGVs
IG9uIFdpbmRvd3MgY2Fubm90IGJlIGludGVyY2VwdGVkIGJ5IGFueSBhcHBsaWNhdGlvbiwgaW5j
bHVkaW5nIEVjbGlwc2UuIikKICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICBB
dXRvUmVzaXppbmdDb21ib0JveCB7CkBAIC0zNjQzLDcgKzM2NTUsNyBAQCBJdGVtIHsKIAogICAg
ICAgICAgICAgICAgIFZiVG9nZ2xlUm93IHsKICAgICAgICAgICAgICAgICAgICAgaWQ6IGJhY2tn
cm91bmRHYW1lcGFkQ2hlY2sKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiUHJvY2Vz
cyBnYW1lcGFkIGlucHV0IHdoZW4gVmliZW1pcyBpcyBpbiB0aGUgYmFja2dyb3VuZCIpCisgICAg
ICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlByb2Nlc3MgZ2FtZXBhZCBpbnB1dCB3aGVuIEVj
bGlwc2UgaXMgaW4gdGhlIGJhY2tncm91bmQiKQogICAgICAgICAgICAgICAgICAgICB2aXNpYmxl
OiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Rlc2t0b3BFbnZpcm9ubWVudAogICAgICAgICAgICAgICAg
ICAgICBjaGVja2VkOiBTdHJlYW1pbmdQcmVmZXJlbmNlcy5iYWNrZ3JvdW5kR2FtZXBhZAogICAg
ICAgICAgICAgICAgICAgICBvbkNoZWNrZWRDaGFuZ2VkOiB7CkBAIC0zNjUzLDcgKzM2NjUsNyBA
QCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5kZWxheTogMTAwMAogICAgICAg
ICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAg
VG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4
dDogcXNUcigiQWxsb3dzIFZpYmVtaXMgdG8gY2FwdHVyZSBnYW1lcGFkIGlucHV0cyBldmVuIGlm
IGl0J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBmb2N1cyIpCisgICAgICAgICAgICAgICAg
ICAgIFRvb2xUaXAudGV4dDogcXNUcigiQWxsb3dzIEVjbGlwc2UgdG8gY2FwdHVyZSBnYW1lcGFk
IGlucHV0cyBldmVuIGlmIGl0J3Mgbm90IHRoZSBjdXJyZW50IHdpbmRvdyBpbiBmb2N1cyIpCiAg
ICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgVmJUb2dnbGVSb3cgewpAQCAtMzcy
NCw3ICszNzM2LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgTGFiZWwgewogICAgICAgICAg
ICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIGlkOiB1
cGRhdGVDaGFubmVsVGl0bGUKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiU29mdHdh
cmUgdXBkYXRlcyIpCisgICAgICAgICAgICAgICAgICAgIHRleHQ6IEF1dG9VcGRhdGVDaGVja2Vy
Lm9zTWFuYWdlZCA/IHFzVHIoIk1vb25saWdodC1PUyB1cGRhdGVzIikgOiBxc1RyKCJTb2Z0d2Fy
ZSB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5z
LnR5cGVMYWJlbAogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMuZm9u
dEJvZHkKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtMzczMyw2
ICszNzQ1LDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBBdXRvUmVzaXppbmdDb21ib0Jv
eCB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsQ29tYm9Cb3gKKyAgICAg
ICAgICAgICAgICAgICAgdmlzaWJsZTogIUF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZAogICAg
ICAgICAgICAgICAgICAgICB0ZXh0Um9sZTogInRleHQiCiAgICAgICAgICAgICAgICAgICAgIG1v
ZGVsOiBMaXN0TW9kZWwgewogICAgICAgICAgICAgICAgICAgICAgICAgaWQ6IHVwZGF0ZUNoYW5u
ZWxMaXN0TW9kZWwKQEAgLTM3ODcsNiArMzgwMCw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAg
ICAgICAvLyBpbnN0YWxsIGluIGZsaWdodCBhdCBhIHRpbWUpLCBzbyBidXR0b25zIHN0YXkgZW5h
YmxlZC4KICAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsKICAgICAgICAgICAgICAgICAgICAg
ICAgIGlkOiBjaGVja1VwZGF0ZXNCdXR0b24KKyAgICAgICAgICAgICAgICAgICAgICAgIHZpc2li
bGU6ICFBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFnZWQKICAgICAgICAgICAgICAgICAgICAgICAg
IHRleHQ6IHFzVHIoIkNoZWNrIGZvciB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAgICAgICAg
IG9uQ2xpY2tlZDogewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIEF1dG9VcGRhdGVDaGVj
a2VyLmNoZWNrTm93KCkKQEAgLTM4MDQsOCArMzgxOCw4IEBAIEl0ZW0gewogCiAgICAgICAgICAg
ICAgICAgICAgIEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAgICAgICAgICBpZDogdmlld1JlbGVh
c2VCdXR0b24KLSAgICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpZXcgcmVsZWFz
ZSIpCi0gICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBBdXRvVXBkYXRlQ2hlY2tlci5v
ZmZlckF2YWlsYWJsZQorICAgICAgICAgICAgICAgICAgICAgICAgdGV4dDogQXV0b1VwZGF0ZUNo
ZWNrZXIub3NNYW5hZ2VkID8gcXNUcigiTW9vbmxpZ2h0LU9TIHJlbGVhc2VzIikgOiBxc1RyKCJW
aWV3IHJlbGVhc2UiKQorICAgICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogKEF1dG9VcGRh
dGVDaGVja2VyLm9zTWFuYWdlZCB8fCBBdXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2YWlsYWJsZSkK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICYmIEF1dG9VcGRhdGVDaGVja2VyLnJl
bGVhc2VVcmwgIT09ICIiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAmJiBTeXN0
ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIKICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tl
ZDogewpAQCAtMzg0Miw3ICszODU2LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgc3BhY2lu
ZzogVmJUb2tlbnMuc3BhY2UzCiAKICAgICAgICAgICAgICAgICBWYlNlY3Rpb25IZWFkZXIgewot
ICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWJlbWlzIEZlYXR1cmVzIikKKyAgICAg
ICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBGZWF0dXJlcyIpCiAgICAgICAgICAg
ICAgICAgfQogCiAgICAgICAgICAgICAgICAgQ2xpcGJvYXJkU2V0dGluZ3MgewpAQCAtMzk0Nyw3
ICszOTYxLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgUmVwZWF0ZXIgewogICAgICAgICAg
ICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIG1vZGVs
OiBbCi0gICAgICAgICAgICAgICAgICAgICAgICB7IGs6IHFzVHIoIlZpYmVtaXMgdmVyc2lvbiIp
LCB2OiBTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcgfSwKKyAgICAgICAgICAgICAgICAg
ICAgICAgIHsgazogcXNUcigiRWNsaXBzZSB2ZXJzaW9uIiksIHY6IFN5c3RlbVByb3BlcnRpZXMu
dmVyc2lvblN0cmluZyB9LAogICAgICAgICAgICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJBcmNo
aXRlY3R1cmUiKSwgICAgdjogU3lzdGVtUHJvcGVydGllcy5mcmllbmRseU5hdGl2ZUFyY2hOYW1l
IH0sCiAgICAgICAgICAgICAgICAgICAgICAgICB7IGs6IHFzVHIoIlN0ZWFtT1MgLyBnYW1lc2Nv
cGUiKSwgdjogU3lzdGVtUHJvcGVydGllcy5pc1N0ZWFtRGVjayA/IHFzVHIoIlllcyIpIDogcXNU
cigiTm8iKSB9LAogICAgICAgICAgICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJEaXNwbGF5IHNl
cnZlciIpLCAgdjogU3lzdGVtUHJvcGVydGllcy5pc1J1bm5pbmdXYXlsYW5kID8gKFN5c3RlbVBy
b3BlcnRpZXMuaXNSdW5uaW5nWFdheWxhbmQgPyAiWFdheWxhbmQiIDogIldheWxhbmQiKSA6ICJY
MTEiIH0sCkBAIC00MDEzLDcgKzQwMjcsNyBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgIExh
YmVsIHsKICAgICAgICAgICAgICAgICAgICAgd2lkdGg6IHBhcmVudC53aWR0aAotICAgICAgICAg
ICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWJlbWlzICUxIikuYXJnKFN5c3RlbVByb3BlcnRpZXMu
dmVyc2lvblN0cmluZykKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSAl
MSIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcpCiAgICAgICAgICAgICAgICAg
ICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQm9keQogICAgICAgICAgICAgICAgICAg
ICBmb250LmJvbGQ6IHRydWUKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3Jh
cApAQCAtNDA1OCw3ICs0MDcyLDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBMYWJlbCB7
CiAgICAgICAgICAgICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lkdGgKLSAgICAgICAgICAgICAg
ICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBpcyB0aGUgTGludXgvU3RlYW1PUyBjbGllbnQgZm9y
IEFwb2xsbyAmIFN1bnNoaW5lIGhvc3RzLiBUaGVzZSBvcGVuIGluIHlvdXIgYnJvd3Nlci4iKQor
ICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIGlzIHRoZSBMaW51eC9TdGVh
bU9TIGNsaWVudCBmb3IgQXBvbGxvICYgU3Vuc2hpbmUgaG9zdHMuIFRoZXNlIG9wZW4gaW4geW91
ciBicm93c2VyLiIpCiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vu
cy50eXBlQ2FwdGlvbgogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJUb2tlbnMu
Zm9udEJvZHkKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApAQCAtNDA2
Niw3ICs0MDgwLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAg
ICAgQnV0dG9uIHsKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBvbiBH
aXRIdWIiKQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIG9uIEdpdEh1
YiIpCiAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogU3lzdGVtUHJvcGVydGllcy5vcGVu
VXJsKCJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3ZpYmVtaXMiKQogICAgICAgICAgICAg
ICAgIH0KICAgICAgICAgICAgICAgICBCdXR0b24gewpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9TeXN0
ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwgYi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9n
LnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uY2ZmNGM2NjAKLS0tIC9k
ZXYvbnVsbAorKysgYi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9nLnFtbApAQCAtMCww
ICsxLDEwNyBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAy
LjUKK2ltcG9ydCBRdFF1aWNrLkxheW91dHMgMS4zCitpbXBvcnQgUXRRdWljay5Db250cm9scy5N
YXRlcmlhbCAyLjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFN5c3RlbUNv
bnRyb2xzIDEuMAorCitOYXZpZ2FibGVEaWFsb2cgeworICAgIGlkOiBwYW5lbAorICAgIHByb3Bl
cnR5IHN0cmluZyBraW5kOiAid2lmaSIKKyAgICBwcm9wZXJ0eSB2YXIgc2VsZWN0ZWQ6ICh7fSkK
KyAgICB3aWR0aDogTWF0aC5taW4oNjIwLCBwYXJlbnQud2lkdGggLSAzMikKKyAgICBoZWlnaHQ6
IE1hdGgubWluKDU2MCwgcGFyZW50LmhlaWdodCAtIDMyKQorICAgIHRpdGxlOiBraW5kID09PSAi
d2lmaSIgPyBxc1RyKCJXaS1GaSBuZXR3b3JrcyIpIDogcXNUcigiQmx1ZXRvb3RoIGRldmljZXMi
KQorICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLkNsb3NlCisgICAgTWF0ZXJpYWwuYmFja2dy
b3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2Nl
bnQKKyAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgeyBjb2xvcjogVmJUb2tlbnMuYmdFbGV2OyBy
YWRpdXM6IFZiVG9rZW5zLnJhZGl1c0RpYWxvZzsgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJv
a2UgfQorICAgIG9uT3BlbmVkOiB7IHNlbGVjdGVkID0gKHt9KTsgU3lzdGVtQ29udHJvbHMub3Bl
bihraW5kKSB9CisgICAgb25DbG9zZWQ6IHsgY3JlZGVudGlhbC5jbG9zZSgpOyBzZWNyZXQudGV4
dCA9ICIiOyBmb3JnZXQuY2xvc2UoKTsgU3lzdGVtQ29udHJvbHMuY2xvc2UoKSB9CisgICAgY29u
dGVudEl0ZW06IENvbHVtbkxheW91dCB7CisgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNl
MworICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1
ZQorICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTog
VGV4dC5XcmFwOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgdGV4dDogU3lzdGVtQ29udHJv
bHMuc3RhdHVzOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICBCdXN5SW5k
aWNhdG9yIHsgcnVubmluZzogU3lzdGVtQ29udHJvbHMuYnVzeTsgdmlzaWJsZTogcnVubmluZzsg
aW1wbGljaXRXaWR0aDogMzI7IGltcGxpY2l0SGVpZ2h0OiAzMiB9CisgICAgICAgICAgICBFY2xp
cHNlQWN0aW9uQnV0dG9uIHsgaWQ6IHNjYW5CdXR0b247IHRleHQ6IHFzVHIoIlNjYW4iKTsgZW5h
YmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogeyBwYW5lbC5zZWxlY3RlZCA9
ICh7fSk7IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QocGFuZWwua2luZCArICItc2NhbiIpIH0gfQor
ICAgICAgICB9CisgICAgICAgIExhYmVsIHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6
IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltCisgICAg
ICAgICAgICB0ZXh0OiBwYW5lbC5raW5kID09PSAid2lmaSIgPyBxc1RyKCJTZWxlY3QgYSBuZXR3
b3JrLCB0aGVuIENvbm5lY3QuIEFkdmFuY2VkIG9yIGhpZGRlbiBuZXR3b3JrcyBhcmUgYXZhaWxh
YmxlIGluIHRoZSBkaWFnbm9zdGljIHNoZWxsLiIpIDogcXNUcigiUHV0IHlvdXIgY29udHJvbGxl
ciBvciBoZWFkcGhvbmVzIGluIHBhaXJpbmcgbW9kZSwgdGhlbiBTY2FuLiBQYWlyaW5nIG1heSB0
YWtlIHVwIHRvIGEgbWludXRlLiIpCisgICAgICAgIH0KKyAgICAgICAgTGlzdFZpZXcgeworICAg
ICAgICAgICAgaWQ6IGRldmljZXMKKyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7
IExheW91dC5maWxsSGVpZ2h0OiB0cnVlCisgICAgICAgICAgICBjbGlwOiB0cnVlOyBzcGFjaW5n
OiA0OyBtb2RlbDogU3lzdGVtQ29udHJvbHMuaXRlbXMKKyAgICAgICAgICAgIFNjcm9sbEJhci52
ZXJ0aWNhbDogU2Nyb2xsQmFyIHt9CisgICAgICAgICAgICBkZWxlZ2F0ZTogSXRlbURlbGVnYXRl
IHsKKyAgICAgICAgICAgICAgICB3aWR0aDogZGV2aWNlcy53aWR0aAorICAgICAgICAgICAgICAg
IGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5CisgICAgICAgICAgICAgICAgaGlnaGxpZ2h0
ZWQ6IHBhbmVsLnNlbGVjdGVkLmlkID09PSBtb2RlbERhdGEuaWQKKyAgICAgICAgICAgICAgICBh
Y3RpdmVGb2N1c09uVGFiOiB0cnVlCisgICAgICAgICAgICAgICAgS2V5cy5vblJldHVyblByZXNz
ZWQ6IGlmIChlbmFibGVkKSBjbGlja2VkKCkKKyAgICAgICAgICAgICAgICBLZXlzLm9uRW50ZXJQ
cmVzc2VkOiBpZiAoZW5hYmxlZCkgY2xpY2tlZCgpCisgICAgICAgICAgICAgICAgS2V5cy5vbkRv
d25QcmVzc2VkOiB7IGlmIChpbmRleCArIDEgPCBkZXZpY2VzLmNvdW50KSB7IGRldmljZXMuaW5j
cmVtZW50Q3VycmVudEluZGV4KCk7IGlmIChkZXZpY2VzLmN1cnJlbnRJdGVtKSBkZXZpY2VzLmN1
cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpIH0gZWxzZSBpZiAoY29ubmVj
dEJ1dHRvbi5lbmFibGVkKSBjb25uZWN0QnV0dG9uLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9j
dXMpOyBlbHNlIHNjYW5CdXR0b24uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykgfQorICAg
ICAgICAgICAgICAgIEtleXMub25VcFByZXNzZWQ6IHsgaWYgKGluZGV4ID4gMCkgeyBkZXZpY2Vz
LmRlY3JlbWVudEN1cnJlbnRJbmRleCgpOyBpZiAoZGV2aWNlcy5jdXJyZW50SXRlbSkgZGV2aWNl
cy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKSB9IGVsc2Ugc2NhbkJ1
dHRvbi5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKSB9CisgICAgICAgICAgICAgICAgY29u
dGVudEl0ZW06IExhYmVsIHsKKyAgICAgICAgICAgICAgICAgICAgdGV4dEZvcm1hdDogVGV4dC5Q
bGFpblRleHQ7IGVsaWRlOiBUZXh0LkVsaWRlUmlnaHQ7IGNvbG9yOiBWYlRva2Vucy50ZXh0Cisg
ICAgICAgICAgICAgICAgICAgIHRleHQ6IG1vZGVsRGF0YS5uYW1lICsgIiDCtyAiICsgbW9kZWxE
YXRhLmRldGFpbCArIChtb2RlbERhdGEuY29ubmVjdGVkID8gIiDCtyAiICsgcXNUcigiQ29ubmVj
dGVkIikgOiAiIikKKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgb25DbGlja2Vk
OiB7IHBhbmVsLnNlbGVjdGVkID0gbW9kZWxEYXRhOyBkZXZpY2VzLmN1cnJlbnRJbmRleCA9IGlu
ZGV4IH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgICAgICBSb3dMYXlvdXQgeworICAg
ICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQorICAgICAgICAgICAgRWNsaXBzZUFjdGlv
bkJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IGNvbm5lY3RCdXR0b24KKyAgICAgICAgICAg
ICAgICB0ZXh0OiBwYW5lbC5raW5kID09PSAid2lmaSIgPyBxc1RyKCJDb25uZWN0IikgOiBxc1Ry
KCJQYWlyIC8gQ29ubmVjdCIpCisgICAgICAgICAgICAgICAgZW5hYmxlZDogISFwYW5lbC5zZWxl
Y3RlZC5pZCAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAgICAgICAgICAgIG9uQ2xpY2tl
ZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdChwYW5lbC5raW5kICsgIi1jb25uZWN0IiwgcGFuZWwu
c2VsZWN0ZWQuaWQpCisgICAgICAgICAgICB9CisgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0
dG9uIHsKKyAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJEaXNjb25uZWN0Iik7IGVuYWJsZWQ6
ICEhcGFuZWwuc2VsZWN0ZWQuaWQgJiYgcGFuZWwuc2VsZWN0ZWQuY29ubmVjdGVkICYmICFTeXN0
ZW1Db250cm9scy5idXN5CisgICAgICAgICAgICAgICAgb25DbGlja2VkOiBTeXN0ZW1Db250cm9s
cy5yZXF1ZXN0KHBhbmVsLmtpbmQgKyAiLWRpc2Nvbm5lY3QiLCBwYW5lbC5zZWxlY3RlZC5pZCkK
KyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBx
c1RyKCJGb3JnZXQiKTsgdmlzaWJsZTogcGFuZWwua2luZCA9PT0gImJ0IjsgZW5hYmxlZDogISFw
YW5lbC5zZWxlY3RlZC5pZCAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiBmb3Jn
ZXQub3BlbigpIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBDb25uZWN0aW9ucyB7CisgICAgICAg
IHRhcmdldDogU3lzdGVtQ29udHJvbHMKKyAgICAgICAgb25DaGFuZ2VkOiB7CisgICAgICAgICAg
ICBpZiAoU3lzdGVtQ29udHJvbHMucHJvbXB0Lmxlbmd0aCA+IDAgJiYgcGFuZWwub3BlbmVkICYm
ICFjcmVkZW50aWFsLm9wZW5lZCkgY3JlZGVudGlhbC5vcGVuKCkKKyAgICAgICAgICAgIGlmICgh
U3lzdGVtQ29udHJvbHMuYnVzeSkgeworICAgICAgICAgICAgICAgIGNyZWRlbnRpYWwuY2xvc2Uo
KTsgc2VjcmV0LnRleHQgPSAiIgorICAgICAgICAgICAgICAgIHZhciBpZCA9IHBhbmVsLnNlbGVj
dGVkLmlkCisgICAgICAgICAgICAgICAgcGFuZWwuc2VsZWN0ZWQgPSAoe30pCisgICAgICAgICAg
ICAgICAgZm9yICh2YXIgaSA9IDA7IGkgPCBTeXN0ZW1Db250cm9scy5pdGVtcy5sZW5ndGg7IGkr
KykKKyAgICAgICAgICAgICAgICAgICAgaWYgKFN5c3RlbUNvbnRyb2xzLml0ZW1zW2ldLmlkID09
PSBpZCkgcGFuZWwuc2VsZWN0ZWQgPSBTeXN0ZW1Db250cm9scy5pdGVtc1tpXQorICAgICAgICAg
ICAgfQorICAgICAgICB9CisgICAgfQorICAgIE5hdmlnYWJsZURpYWxvZyB7CisgICAgICAgIGlk
OiBjcmVkZW50aWFsCisgICAgICAgIHRpdGxlOiBxc1RyKCJDb25uZWN0aW9uIGF1dGhlbnRpY2F0
aW9uIikKKyAgICAgICAgd2lkdGg6IE1hdGgubWluKDQ4MCwgcGFuZWwud2lkdGgpCisgICAgICAg
IGNsb3NlUG9saWN5OiBQb3B1cC5Ob0F1dG9DbG9zZQorICAgICAgICBzdGFuZGFyZEJ1dHRvbnM6
IERpYWxvZy5PayB8IERpYWxvZy5DYW5jZWwKKyAgICAgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDog
VmJUb2tlbnMuYmdFbGV2CisgICAgICAgIG9uT3BlbmVkOiB7IHNlY3JldC50ZXh0ID0gIiI7IHNl
Y3JldC5mb3JjZUFjdGl2ZUZvY3VzKCkgfQorICAgICAgICBvbkFjY2VwdGVkOiB7IFN5c3RlbUNv
bnRyb2xzLmFuc3dlcihzZWNyZXQudGV4dCk7IHNlY3JldC50ZXh0ID0gIiIgfQorICAgICAgICBv
blJlamVjdGVkOiB7IHNlY3JldC50ZXh0ID0gIiI7IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCkgfQor
ICAgICAgICBjb250ZW50SXRlbTogQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAgIExhYmVsIHsg
TGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHdyYXBN
b2RlOiBUZXh0LldyYXA7IHRleHQ6IFN5c3RlbUNvbnRyb2xzLnByb21wdDsgY29sb3I6IFZiVG9r
ZW5zLnRleHQgfQorICAgICAgICAgICAgVGV4dEZpZWxkIHsgaWQ6IHNlY3JldDsgTGF5b3V0LmZp
bGxXaWR0aDogdHJ1ZTsgZWNob01vZGU6IFRleHRJbnB1dC5QYXNzd29yZDsgbWF4aW11bUxlbmd0
aDogNDA5Njsgc2VsZWN0QnlNb3VzZTogdHJ1ZTsgb25BY2NlcHRlZDogY3JlZGVudGlhbC5hY2Nl
cHQoKSB9CisgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBN
b2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIkVudGVyIHRoZSByZXF1ZXN0ZWQgcGFzc3dvcmQg
b3IgUElOLiBGb3IgYSB5ZXMvbm8gY29uZmlybWF0aW9uLCB0eXBlIHllcyBvciBuby4iKTsgY29s
b3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICB9CisgICAgfQorICAgIE5hdmlnYWJsZURp
YWxvZyB7CisgICAgICAgIGlkOiBmb3JnZXQKKyAgICAgICAgdGl0bGU6IHFzVHIoIkZvcmdldCBC
bHVldG9vdGggZGV2aWNlPyIpCisgICAgICAgIHdpZHRoOiBNYXRoLm1pbig0ODAsIHBhbmVsLndp
ZHRoKQorICAgICAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5ZZXMgfCBEaWFsb2cuTm8KKyAg
ICAgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgICAgIG9uQWNj
ZXB0ZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImJ0LWZvcmdldCIsIHBhbmVsLnNlbGVjdGVk
LmlkLCB0cnVlKQorICAgICAgICBjb250ZW50SXRlbTogTGFiZWwgeyB0ZXh0Rm9ybWF0OiBUZXh0
LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcXNUcigiUmVtb3ZlIHRoZSBz
YXZlZCBwYWlyaW5nIGZvciAlMT8gWW91IHdpbGwgbmVlZCB0byBwYWlyIGl0IGFnYWluLiIpLmFy
ZyhwYW5lbC5zZWxlY3RlZC5uYW1lIHx8ICIiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQgfQorICAg
IH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvVGhlbWUucW1sIGIvYXBwL2d1aS9UaGVtZS5xbWwK
aW5kZXggZmI5MWM4NTAuLjU3YzlmODQ4IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1RoZW1lLnFtbAor
KysgYi9hcHAvZ3VpL1RoZW1lLnFtbApAQCAtMTEsMjAgKzExLDIwIEBAIGltcG9ydCBWaWJlbWlz
LlJlZGVzaWduIDEuMAogUXRPYmplY3QgewogICAgIC8vIC0tLS0gQ29sb3IgLS0tLQogICAgIHJl
YWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAgICAgIFZiVG9rZW5zLmFjY2VudCAgLy8g
QkwtMjA3Nzogc2luZ2xlIHNvdXJjZSBvZiB0cnV0aCAoVmJUb2tlbnMgYnJhbmQgYWNjZW50LCBk
ZWZhdWx0ICMwMENDQ0MpCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3Nl
ZDogIiMwMEEzQTMiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmFja2dyb3VuZDogICAg
IiMzMDMwMzAiICAvLyBhcHAgcm9vdAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZh
Y2U6ICAgICAgICIjMkQyRDJEIiAgLy8gcmFpc2VkIHN1cmZhY2VzIC8gb3ZlcmxheXMKLSAgICBy
ZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdXJmYWNlQWx0OiAgICAiIzQyNDI0MiIgIC8vIHBvcHVw
cyAvIGNvbWJvIGRyb3Bkb3ducwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJvcmRlcjog
ICAgICAgICIjNDQ0NDQ0IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRQcmltYXJ5
OiAgICIjRkZGRkZGIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRTZWNvbmRhcnk6
ICIjQ0NDQ0NDIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRUZXJ0aWFyeTogICIj
QUFBQUFBIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHREaXNhYmxlZDogICIjNzc3
Nzc3IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1Y2Nlc3M6ICAgICAgICIjNENBRjUw
IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHdhcm5pbmc6ICAgICAgICIjRTBBMDMwIiAg
Ly8gdGhlIHNpbmdsZSBhbWJlcgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGVycm9yOiAg
ICAgICAgICIjRjQ0MzM2IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGluZm86ICAgICAg
ICAgICIjODBBMEMwIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHNjcmltOiAgICAgICAg
ICIjRDAwMDAwMDAiCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDog
VmJUb2tlbnMuYWNjZW50UHJlc3NlZAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJhY2tn
cm91bmQ6ICAgIFZiVG9rZW5zLmJnV2luZG93ICAvLyBhcHAgcm9vdAorICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGNvbG9yIHN1cmZhY2U6ICAgICAgIFZiVG9rZW5zLmJnRWxldiAgLy8gcmFpc2VkIHN1
cmZhY2VzIC8gb3ZlcmxheXMKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdXJmYWNlQWx0
OiAgICBWYlRva2Vucy5iZ0VsZXYyICAvLyBwb3B1cHMgLyBjb21ibyBkcm9wZG93bnMKKyAgICBy
ZWFkb25seSBwcm9wZXJ0eSBjb2xvciBib3JkZXI6ICAgICAgICBWYlRva2Vucy5zdHJva2UKKyAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0UHJpbWFyeTogICBWYlRva2Vucy50ZXh0UHJp
bWFyeQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRTZWNvbmRhcnk6IFZiVG9rZW5z
LnRleHRTZWNvbmRhcnkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0VGVydGlhcnk6
ICBWYlRva2Vucy50ZXh0VGVydGlhcnkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0
RGlzYWJsZWQ6ICBWYlRva2Vucy50ZXh0RGlzYWJsZWQKKyAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciBzdWNjZXNzOiAgICAgICBWYlRva2Vucy5zdGF0dXNTdWNjZXNzCisgICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3Igd2FybmluZzogICAgICAgVmJUb2tlbnMuc3RhdHVzV2FybmluZyAgLy8g
dGhlIHNpbmdsZSBhbWJlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGVycm9yOiAgICAg
ICAgIFZiVG9rZW5zLnN0YXR1c0RhbmdlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGlu
Zm86ICAgICAgICAgIFZiVG9rZW5zLnN0YXR1c0luZm8KKyAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciBzY3JpbTogICAgICAgICBWYlRva2Vucy5kaWFsb2dTY3JpbQogCiAgICAgLy8gLS0tLSBU
eXBvZ3JhcGh5IChwb2ludFNpemU7IHBhaXIgd2l0aCBib2xkIHdoZXJlIG5vdGVkIGluIERFU0lH
Tl9TWVNURU0ubWQpIC0tLS0KICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgZm9udERpc3BsYXk6
IDI0ICAvLyBvdmVybGF5L1F1aWNrIE1lbnUgdGl0bGUgKGJvbGQpCmRpZmYgLS1naXQgYS9hcHAv
Z3VpL1ZiQ2FyZC5xbWwgYi9hcHAvZ3VpL1ZiQ2FyZC5xbWwKaW5kZXggMzdmMmUzMmQuLjFlOTBh
MDJkIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiQ2FyZC5xbWwKKysrIGIvYXBwL2d1aS9WYkNhcmQu
cW1sCkBAIC0yNyw3ICsyNyw3IEBAIEl0ZW0gewogICAgICAgICBib3JkZXIud2lkdGg6IDEKICAg
ICAgICAgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UKICAgICAgICAgb3BhY2l0eTogY2Fy
ZC5jb250ZW50T3BhY2l0eQotICAgICAgICBCZWhhdmlvciBvbiBjb2xvciB7IENvbG9yQW5pbWF0
aW9uIHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAgICAgQmVoYXZpb3Igb24gY29sb3IgeyBDb2xv
ckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8gMTIwIDogMCB9
IH0KICAgICB9CiAKICAgICBJdGVtIHsKZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJTdGF0dXNQaWxs
LnFtbCBiL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbAppbmRleCA4OWM0NzcwYS4uYzcyOGYwNTIg
MTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbAorKysgYi9hcHAvZ3VpL1ZiU3Rh
dHVzUGlsbC5xbWwKQEAgLTI0LDcgKzI0LDcgQEAgUmVjdGFuZ2xlIHsKICAgICAgICAgICAgIGNv
bG9yOiBwaWxsLm9ubGluZSA/IFZiVG9rZW5zLnN0YXR1c09ubGluZSA6IFZiVG9rZW5zLnN0YXR1
c09mZmxpbmUKICAgICAgICAgICAgIC8vIFB1bHNlIG9ubHkgd2hlbiBvbmxpbmUuCiAgICAgICAg
ICAgICBTZXF1ZW50aWFsQW5pbWF0aW9uIG9uIG9wYWNpdHkgewotICAgICAgICAgICAgICAgIHJ1
bm5pbmc6IHBpbGwub25saW5lCisgICAgICAgICAgICAgICAgcnVubmluZzogcGlsbC5vbmxpbmUg
JiYgVmJUb2tlbnMubW90aW9uRW5hYmxlZAogICAgICAgICAgICAgICAgIGxvb3BzOiBBbmltYXRp
b24uSW5maW5pdGUKICAgICAgICAgICAgICAgICBOdW1iZXJBbmltYXRpb24geyBmcm9tOiAxLjA7
IHRvOiAwLjQ1OyBkdXJhdGlvbjogVmJUb2tlbnMub25saW5lUHVsc2VNcyAvIDI7IGVhc2luZy50
eXBlOiBFYXNpbmcuSW5PdXRTaW5lIH0KICAgICAgICAgICAgICAgICBOdW1iZXJBbmltYXRpb24g
eyBmcm9tOiAwLjQ1OyB0bzogMS4wOyBkdXJhdGlvbjogVmJUb2tlbnMub25saW5lUHVsc2VNcyAv
IDI7IGVhc2luZy50eXBlOiBFYXNpbmcuSW5PdXRTaW5lIH0KZGlmZiAtLWdpdCBhL2FwcC9ndWkv
VmJUb2tlbnMucW1sIGIvYXBwL2d1aS9WYlRva2Vucy5xbWwKaW5kZXggNTJhMzRkZTQuLmNiZjc5
ODVmIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiVG9rZW5zLnFtbAorKysgYi9hcHAvZ3VpL1ZiVG9r
ZW5zLnFtbApAQCAtMSw2ICsxLDcgQEAKIHByYWdtYSBTaW5nbGV0b24KIGltcG9ydCBRdFF1aWNr
IDIuOQogaW1wb3J0IFN0cmVhbWluZ1ByZWZlcmVuY2VzIDEuMAoraW1wb3J0IEVjbGlwc2VQcm9m
aWxlcyAxLjAKIAogLy8gVmliZW1pcyByZWRlc2lnbiBkZXNpZ24gdG9rZW5zLgogLy8gRGFyayB0
aGVtZSBvbmx5LiBDYW52YXMgMTkyMHgxMjAwIChMZWdpb24gR28gUyksCkBAIC05LDQzICsxMCw0
NCBAQCBpbXBvcnQgU3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCiBRdE9iamVjdCB7CiAgICAgaWQ6
IHQKIAorICAgIHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgdGV4dFNjYWxlOiBFY2xpcHNlUHJvZmls
ZXMudGV4dFNjYWxlIC8gMTAwCisgICAgcmVhZG9ubHkgcHJvcGVydHkgYm9vbCBtb3Rpb25FbmFi
bGVkOiAhRWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb24KKwogICAgIC8vIC0tLS0gQ29sb3Ig
LS0tLQotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnQXBwOiAgICAgICAgIiMwODA5MEIi
ICAvLyBvdXRlcm1vc3QgYXBwIGJnIGJlaGluZCB0aGUgcm91bmRlZCB3aW5kb3cKLSAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciBiZ1dpbmRvdzogICAgICIjMEUxMDEzIiAgLy8gbWFpbiBzY3Jl
ZW4gYmFja2dyb3VuZAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxldjogICAgICAg
IiMxNTE4MUQiICAvLyBjYXJkcywgcGFuZWxzLCBkaWFsb2dzLCBzaWRlYmFyIHJvd3MKLSAgICBy
ZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0VsZXYyOiAgICAgICIjMUIxRjI2IiAgLy8gZm9jdXNl
ZC9zZWxlY3RlZCBzdXJmYWNlIGZpbGwsIGNoaXBzCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29s
b3IgYmdGb290ZXI6ICAgICAiIzBCMEQxMCIgIC8vIGJvdHRvbSBnYW1lcGFkIGhpbnQgYmFyCi0g
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Ryb2tlOiAgICAgICBRdC5yZ2JhKDEsIDEsIDEs
IDAuMDgpICAvLyBkZWZhdWx0IDFweCBjYXJkIGJvcmRlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIGJnQXBwOiAgICAgICAgIiMwNjA2MDciICAvLyBvdXRlcm1vc3QgYXBwIGJnIGJlaGlu
ZCB0aGUgcm91bmRlZCB3aW5kb3cKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ1dpbmRv
dzogICAgICIjMEIwQjBFIiAgLy8gbWFpbiBzY3JlZW4gYmFja2dyb3VuZAorICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIGJnRWxldjogICAgICAgIiMxNTExMTUiICAvLyBjYXJkcywgcGFuZWxz
LCBkaWFsb2dzLCBzaWRlYmFyIHJvd3MKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0Vs
ZXYyOiAgICAgICIjMjExNzFDIiAgLy8gZm9jdXNlZC9zZWxlY3RlZCBzdXJmYWNlIGZpbGwsIGNo
aXBzCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdGb290ZXI6ICAgICAiIzA5MDgwQiIg
IC8vIGJvdHRvbSBnYW1lcGFkIGhpbnQgYmFyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
c3Ryb2tlOiAgICAgICBRdC5yZ2JhKDEsIDEsIDEsIEVjbGlwc2VQcm9maWxlcy5oaWdoQ29udHJh
c3QgPyAwLjI1IDogMC4wOCkgIC8vIGRlZmF1bHQgMXB4IGNhcmQgYm9yZGVyCiAgICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3Igc3Ryb2tlU29mdDogICBRdC5yZ2JhKDEsIDEsIDEsIDAuMDYpICAv
LyBoZWFkZXIvZm9vdGVyIGRpdmlkZXJzCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4
dDogICAgICAgICAiI0VDRUVGMSIgIC8vIHByaW1hcnkgdGV4dAotICAgIHJlYWRvbmx5IHByb3Bl
cnR5IGNvbG9yIHRleHREaW06ICAgICAgIiM5OEExQUIiICAvLyBzZWNvbmRhcnkgLyBsYWJlbCB0
ZXh0CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpbTogICAgICAoRWNsaXBzZVBy
b2ZpbGVzLmhpZ2hDb250cmFzdCA/ICIjRDNENURDIiA6ICIjOThBMUFCIikgIC8vIHNlY29uZGFy
eSAvIGxhYmVsIHRleHQKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0TXV0ZTogICAg
ICIjQjlDMEM4IiAgLy8gdGVydGlhcnkgLyBpbmFjdGl2ZSBpdGVtIGxhYmVscwogCi0gICAgLy8g
QWNjZW50IGlzIHN3YXBwYWJsZSDigJQgb25lIG9mIHRoZSA0IGN1cmF0ZWQgdmFsdWVzLiBJbmRl
eCAwIGlzIHRoZSBWaWJlbWlzIGJyYW5kCi0gICAgLy8gdGVhbCAjMDBDQ0NDIChCTC0yMDc3KTog
dGhlIHNpbmdsZSBjYW5vbmljYWwgYWNjZW50IHRoYXQgVGhlbWUucW1sICsgYWxsIGxpdGVyYWxz
IG5vdwotICAgIC8vIHJlc29sdmUgdGhyb3VnaCwgYW5kIHRoZSBhbmNob3IgZm9yIHRoZSBQMy4x
Ny9QMy4xOCBkZXNpZ24gd29yay4KLSAgICByZWFkb25seSBwcm9wZXJ0eSB2YXIgYWNjZW50T3B0
aW9uczogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1OTgiLCAiI0YwQTg2OCJdCisgICAg
Ly8gUHJlc2VydmUgbGVnYWN5IGluZGljZXMgMC4uMzsgYXBwZW5kIGNvbG9ycyBhbmQgZGVmYXVs
dCBuZXcgcHJlZmVyZW5jZXMgdG8gY3JpbXNvbi4KKyAgICByZWFkb25seSBwcm9wZXJ0eSB2YXIg
YWNjZW50T3B0aW9uczogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1OTgiLCAiI0YwQTg2
OCIsICIjREMzNjU4IiwgIiNGMjVENjQiLCAiI0Y1ODM0NyIsICIjRjFCQzQ1IiwgIiNCN0RDNjMi
LCAiIzYzQ0NBRSIsICIjNjNDNEVEIiwgIiM2QzlGRkYiLCAiI0FEODVGNSIsICIjRTk3NkJDIiwg
IiNDQUQwREEiLCAiI0Q5OTVBQyJdCiAgICAgLy8gQm91bmQgdG8gdGhlIHNhdmVkIHByZWZlcmVu
Y2UgKFNldHRpbmdzID4gYWNjZW50IHBpY2tlcik7IHBlcnNpc3RzIGFjcm9zcyByZXN0YXJ0cy4K
ICAgICBwcm9wZXJ0eSBpbnQgYWNjZW50SW5kZXg6IFN0cmVhbWluZ1ByZWZlcmVuY2VzLnVpQWNj
ZW50SW5kZXgKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnQ6ICAgICAgIGFjY2Vu
dE9wdGlvbnNbYWNjZW50SW5kZXhdCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50
SGk6ICAgICAiIzZBRERFNyIgIC8vIGFjY2VudCBncmFkaWVudCBsaWdodCBzdG9wIC8gbGluayBo
b3ZlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAgICAgYWNjZW50T3B0
aW9uc1tNYXRoLm1heCgwLCBNYXRoLm1pbihhY2NlbnRPcHRpb25zLmxlbmd0aCAtIDEsIGFjY2Vu
dEluZGV4KSldCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50SGk6ICAgICBRdC5s
aWdodGVyKGFjY2VudCwgMS4xOCkgIC8vIGFjY2VudCBncmFkaWVudCBsaWdodCBzdG9wIC8gbGlu
ayBob3ZlcgogCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3RhdHVzT25saW5lOiAgIiMz
RUQ1OTgiICAvLyBvbmxpbmUgZG90LCBSRVNVTUUgYmFkZ2UKICAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciBzdGF0dXNPZmZsaW5lOiAiIzVBNjI2QyIgIC8vIG9mZmxpbmUgZG90IC8gZ3JleWVk
IG1vbml0b3IKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNEYW5nZXI6ICAiI0Yy
NkQ2RCIgIC8vIGRlc3RydWN0aXZlIChEZWxldGUgUEMpCiAKLSAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciB0ZXh0T25BY2NlbnQ6ICIjMDgwOTBCIiAgLy8gdGV4dCBvbiBhbiBhY2NlbnQtZmls
bGVkIGJ1dHRvbgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRPbkFjY2VudDogIiMw
NjA2MDciICAvLyB0ZXh0IG9uIGFuIGFjY2VudC1maWxsZWQgYnV0dG9uCiAKICAgICAvLyAtLS0t
IFR5cG9ncmFwaHkgKGZhbWlsaWVzICsgc2l6ZXM7IHdlaWdodHMgcGVyIHRoZSB0eXBlIHNjYWxl
KSAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgc3RyaW5nIGZvbnREaXNwbGF5OiAiU29yYSIg
ICAgIC8vIHRpdGxlcywgY2FyZCBuYW1lcywgd29yZG1hcmssIGFsbC1jYXBzIGxhYmVscwogICAg
IHJlYWRvbmx5IHByb3BlcnR5IHN0cmluZyBmb250Qm9keTogICAgIk1hbnJvcGUiICAvLyBib2R5
ICsgVUkgdGV4dAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2NyZWVuVGl0bGU6ICAz
NAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2VjdGlvblRpdGxlOiAyOAotICAgIHJl
YWRvbmx5IHByb3BlcnR5IGludCBzaXplQ2FyZE5hbWU6ICAgICAyNwotICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGludCBzaXplQm9keTogICAgICAgICAxNgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGlu
dCBzaXplTGFiZWw6ICAgICAgICAxNAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplQmFk
Z2U6ICAgICAgICAxMwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplV29yZG1hcms6ICAg
ICAyMQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2NyZWVuVGl0bGU6ICBNYXRoLnJv
dW5kKDM0ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2VjdGlv
blRpdGxlOiBNYXRoLnJvdW5kKDI4ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5
IGludCBzaXplQ2FyZE5hbWU6ICAgICBNYXRoLnJvdW5kKDI3ICogdGV4dFNjYWxlKQorICAgIHJl
YWRvbmx5IHByb3BlcnR5IGludCBzaXplQm9keTogICAgICAgICBNYXRoLnJvdW5kKDE2ICogdGV4
dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplTGFiZWw6ICAgICAgICBNYXRo
LnJvdW5kKDE0ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplQmFk
Z2U6ICAgICAgICBNYXRoLnJvdW5kKDEzICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3Bl
cnR5IGludCBzaXplV29yZG1hcms6ICAgICBNYXRoLnJvdW5kKDIxICogdGV4dFNjYWxlKQogICAg
IHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgd29yZG1hcmtTcGFjaW5nOiAzLjAKICAgICByZWFkb25s
eSBwcm9wZXJ0eSByZWFsIGJhZGdlU3BhY2luZzogICAgMS4yCiAKQEAgLTgzLDcgKzg1LDcgQEAg
UXRPYmplY3QgewogICAgIC8vIC0tLS0gTW90aW9uIChtcykgLS0tLQogICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGludCBvbmxpbmVQdWxzZU1zOiAyNDAwICAgLy8gb3BhY2l0eSAxIC0+IDAuNDUgLT4g
MSwgaW5maW5pdGUKICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgY2FyZXRCbGlua01zOiAgMTAw
MCAgIC8vIEFkZC1QQyBpbnB1dCBjYXJldAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaGVl
dEluTXM6ICAgICAyMjAgICAgLy8gc2lkZS1zaGVldCBzbGlkZS1pbgorICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGludCBzaGVldEluTXM6ICAgICBtb3Rpb25FbmFibGVkID8gMjIwIDogMCAgICAvLyBz
aWRlLXNoZWV0IHNsaWRlLWluCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZGlhbG9nU2Ny
aW06IFF0LnJnYmEoNC8yNTUsIDUvMjU1LCA3LzI1NSwgMC43MikKICAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBzaGVldFNjcmltOiAgUXQucmdiYSg0LzI1NSwgNS8yNTUsIDcvMjU1LCAwLjYw
KQogCkBAIC0xMTksNyArMTIxLDcgQEAgUXRPYmplY3QgewogICAgIC8vIHRleHRPbkFjY2VudCAo
IzA4MDkwQikgaXMgZGVmaW5lZCBpbiB0aGUgYmFzZSBibG9jayBhYm92ZSDigJQgdGV4dCBvbiBh
biBhY2NlbnQgZmlsbC4KIAogICAgIC8vIC0tLS0gSW50ZXJhY3RpdmUgc3RhdGVzOiBub3JtYWwg
LyBob3ZlciAvIGZvY3VzIC8gcHJlc3NlZCAvIGRpc2FibGVkIC0tLS0KLSAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2VkOiAgICAgICIjMDBBM0EzIiAvLyBwcmVzc2VkIGFj
Y2VudGVkIGNvbnRyb2wgKG1hdGNoZXMgbGVnYWN5IFRoZW1lLmFjY2VudFByZXNzZWQpCisgICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDogICAgICBRdC5kYXJrZXIoYWNj
ZW50LCAxLjE4KSAvLyBwcmVzc2VkIGFjY2VudGVkIGNvbnRyb2wgKG1hdGNoZXMgbGVnYWN5IFRo
ZW1lLmFjY2VudFByZXNzZWQpCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW50ZXJhY3Rp
dmVIb3ZlcjogICBiZ0VsZXYyICAgIC8vIHJvdyAvIGxpc3QtaXRlbSAvIGljb24tYnV0dG9uIGhv
dmVyIGZpbGwKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZUZvY3VzOiAg
IGZvY3VzZWRGaWxsLy8gZm9jdXNlZCBmaWxsICg9IGJnRWxldjIpIOKAlCBwYWlyIHdpdGggdGhl
IGZvY3VzIHJpbmcKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2ZVByZXNz
ZWQ6IGJnRWxldiAgICAgLy8gcHJlc3NlZCBuZXV0cmFsIGZpbGwgKHJlY2VkZXMgdW5kZXIgdGhl
IHByZXNzKQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9WYldlbGNvbWVTaGVldC5xbWwgYi9hcHAvZ3Vp
L1ZiV2VsY29tZVNoZWV0LnFtbAppbmRleCAxNzMxMTliOC4uNDM4M2NiMDcgMTAwNjQ0Ci0tLSBh
L2FwcC9ndWkvVmJXZWxjb21lU2hlZXQucW1sCisrKyBiL2FwcC9ndWkvVmJXZWxjb21lU2hlZXQu
cW1sCkBAIC0xMDgsMTQgKzEwOCwxMyBAQCBOYXZpZ2FibGVEaWFsb2cgewogICAgICAgICAgICAg
c3BhY2luZzogVmJUb2tlbnMuc3BhY2UyICAvLyA4CiAgICAgICAgICAgICBSb3dMYXlvdXQgewog
ICAgICAgICAgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMgotICAgICAgICAgICAgICAg
IFJlY3RhbmdsZSB7Ci0gICAgICAgICAgICAgICAgICAgIHdpZHRoOiAxMzsgaGVpZ2h0OiAxMwot
ICAgICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYWNjZW50Ci0gICAgICAgICAgICAg
ICAgICAgIHJvdGF0aW9uOiA0NQorICAgICAgICAgICAgICAgIEltYWdlIHsKKyAgICAgICAgICAg
ICAgICAgICAgc291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyIKKyAgICAgICAgICAg
ICAgICAgICAgTGF5b3V0LnByZWZlcnJlZFdpZHRoOiAyODsgTGF5b3V0LnByZWZlcnJlZEhlaWdo
dDogMjgKICAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25WQ2Vu
dGVyCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgIFRleHQgewotICAgICAgICAg
ICAgICAgICAgICB0ZXh0OiAiVklCRU1JUyIKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogIkVD
TElQU0UiCiAgICAgICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250RGlz
cGxheQogICAgICAgICAgICAgICAgICAgICBmb250LndlaWdodDogRm9udC5FeHRyYUJvbGQKICAg
ICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnNpemVXb3JkbWFyayAg
ICAgIC8vIDIxCkBAIC0xMjUsNyArMTI0LDcgQEAgTmF2aWdhYmxlRGlhbG9nIHsKICAgICAgICAg
ICAgICAgICB9CiAgICAgICAgICAgICB9CiAgICAgICAgICAgICBUZXh0IHsKLSAgICAgICAgICAg
ICAgICB0ZXh0OiBxc1RyKCJXZWxjb21lIHRvIFZpYmVtaXMiKQorICAgICAgICAgICAgICAgIHRl
eHQ6IHFzVHIoIldlbGNvbWUgdG8gRWNsaXBzZSIpCiAgICAgICAgICAgICAgICAgZm9udC5mYW1p
bHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5CiAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZv
bnQuQm9sZAogICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlRGlz
cGxheSAgICAgICAgICAgLy8gMzQKQEAgLTE5NSw3ICsxOTQsNyBAQCBOYXZpZ2FibGVEaWFsb2cg
ewogICAgICAgICAgICAgSW5mb1JvdyB7CiAgICAgICAgICAgICAgICAgZ2x5cGg6ICJhcHBzIgog
ICAgICAgICAgICAgICAgIHRpdGxlOiBxc1RyKCJBZGQgdG8gU3RlYW0iKQotICAgICAgICAgICAg
ICAgIHN1YjogcXNUcigiT24gU3RlYW0gRGVjayAvIFN0ZWFtT1MsIGFkZCBWaWJlbWlzIHRvIFN0
ZWFtIGZyb20gRGVza3RvcCBNb2RlIHNvIGl0IGFwcGVhcnMgaW4gR2FtZSBNb2RlLiIpCisgICAg
ICAgICAgICAgICAgc3ViOiBxc1RyKCJPbiBTdGVhbSBEZWNrIC8gU3RlYW1PUywgYWRkIEVjbGlw
c2UgdG8gU3RlYW0gZnJvbSBEZXNrdG9wIE1vZGUgc28gaXQgYXBwZWFycyBpbiBHYW1lIE1vZGUu
IikKICAgICAgICAgICAgIH0KIAogICAgICAgICAgICAgLy8gMykgU2V0dGluZ3MuCmRpZmYgLS1n
aXQgYS9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuY3BwIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmNw
cAppbmRleCA2M2M3MTE1OC4uMmQ0ODdmZjUgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvY29tcHV0ZXJt
b2RlbC5jcHAKKysrIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmNwcApAQCAtMSwzICsxLDQgQEAK
KyNpbmNsdWRlIDxRVXJsPgogI2luY2x1ZGUgImNvbXB1dGVybW9kZWwuaCIKICNpbmNsdWRlICJi
YWNrZW5kL3NlcnZlcnBlcm1pc3Npb25zLmgiCiAjaW5jbHVkZSAic2V0dGluZ3MvdmliZW1pc3Nl
dHRpbmdzLmgiCkBAIC00MjAsMyArNDIxLDEzIEBAIHZvaWQgQ29tcHV0ZXJNb2RlbDo6aGFuZGxl
Q29tcHV0ZXJTdGF0ZUNoYW5nZWQoTnZDb21wdXRlciogY29tcHV0ZXIpCiB9CiAKICNpbmNsdWRl
ICJjb21wdXRlcm1vZGVsLm1vYyIKKworUVZhcmlhbnRNYXAgQ29tcHV0ZXJNb2RlbDo6Y3JpbXNv
bkhvc3QoaW50IGluZGV4KSBjb25zdAoreworICAgIGlmIChpbmRleCA8IDAgfHwgaW5kZXggPj0g
bV9Db21wdXRlcnMuY291bnQoKSkgcmV0dXJuIHt9OworICAgIGF1dG8gY29tcHV0ZXIgPSBtX0Nv
bXB1dGVyc1tpbmRleF07CisgICAgUVJlYWRMb2NrZXIgbG9jaygmY29tcHV0ZXItPmxvY2spOwor
ICAgIFFVcmwgdXJsOyB1cmwuc2V0U2NoZW1lKCJodHRwcyIpOyB1cmwuc2V0SG9zdChjb21wdXRl
ci0+YWN0aXZlQWRkcmVzcy5hZGRyZXNzKCkpOworICAgIHVybC5zZXRQb3J0KGNvbXB1dGVyLT5h
Y3RpdmVBZGRyZXNzLnBvcnQoKSA+IDAgPyBjb21wdXRlci0+YWN0aXZlQWRkcmVzcy5wb3J0KCkg
KyAxIDogNDc5OTApOworICAgIHJldHVybiB7eyJpZCIsIGNvbXB1dGVyLT51dWlkfSwgeyJ1cmwi
LCB1cmwudG9TdHJpbmcoKX19OworfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9jb21wdXRlcm1vZGVs
LmggYi9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuaAppbmRleCA2ZWNhZTMwZC4uMmVlNzNjMWQgMTAw
NjQ0Ci0tLSBhL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5oCisrKyBiL2FwcC9ndWkvY29tcHV0ZXJt
b2RlbC5oCkBAIC00Myw2ICs0Myw4IEBAIHB1YmxpYzoKIAogICAgIHZpcnR1YWwgUUhhc2g8aW50
LCBRQnl0ZUFycmF5PiByb2xlTmFtZXMoKSBjb25zdCBvdmVycmlkZTsKIAorICAgIFFfSU5WT0tB
QkxFIFFWYXJpYW50TWFwIGNyaW1zb25Ib3N0KGludCBjb21wdXRlckluZGV4KSBjb25zdDsKKwog
ICAgIFFfSU5WT0tBQkxFIHZvaWQgZGVsZXRlQ29tcHV0ZXIoaW50IGNvbXB1dGVySW5kZXgpOwog
CiAgICAgUV9JTlZPS0FCTEUgUVN0cmluZyBnZW5lcmF0ZVBpblN0cmluZygpOwpkaWZmIC0tZ2l0
IGEvYXBwL2d1aS9tYWluLnFtbCBiL2FwcC9ndWkvbWFpbi5xbWwKaW5kZXggOWJjZTUxMDUuLjg0
OGZjMTRlIDEwMDY0NAotLS0gYS9hcHAvZ3VpL21haW4ucW1sCisrKyBiL2FwcC9ndWkvbWFpbi5x
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
LTI2Nyw2ICsyODMsMjUgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICB9CiAgICAgfQog
CisgICAgQ3JpbXNvblN0YXR1c0RpYWxvZyB7IGlkOiBjcmltc29uUGFuZWwgfQorICAgIFN5c3Rl
bUNvbm5lY3Rpb25zRGlhbG9nIHsgaWQ6IGNvbm5lY3Rpb25QYW5lbCB9CisgICAgRWNsaXBzZUFi
b3V0RGlhbG9nIHsgaWQ6IGVjbGlwc2VBYm91dCB9CisgICAgRWNsaXBzZUNvbnRyb2xDZW50ZXIg
eworICAgICAgICBpZDogZWNsaXBzZUNlbnRlcgorICAgICAgICBjYW5NYW5hZ2U6IFN5c3RlbVBy
b3BlcnRpZXMuaGFzQnJvd3NlcgorICAgICAgICBjYW5XYWtlOiB0b29sQmFyLm9uUGNWaWV3Cisg
ICAgICAgIG9uV2FrZVJlcXVlc3RlZDogeworICAgICAgICAgICAgaWYgKHRvb2xCYXIub25QY1Zp
ZXcpIHN0YWNrVmlldy5jdXJyZW50SXRlbS5jb21wdXRlck1vZGVsLndha2VDb21wdXRlcihzdGFj
a1ZpZXcuY3VycmVudEl0ZW0uY3VycmVudEluZGV4KQorICAgICAgICB9CisgICAgICAgIG9uTmF2
aWdhdGVSZXF1ZXN0ZWQ6IHsKKyAgICAgICAgICAgIGlmIChkZXN0aW5hdGlvbiA9PT0gIndpZmki
IHx8IGRlc3RpbmF0aW9uID09PSAiYnQiKSB7IGNvbm5lY3Rpb25QYW5lbC5raW5kID0gZGVzdGlu
YXRpb247IGNvbm5lY3Rpb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgZWxzZSBpZiAoZGVz
dGluYXRpb24gPT09ICJzZXR0aW5ncyIpIG5hdmlnYXRlVG8oInFyYzovZ3VpL1NldHRpbmdzVmll
dy5xbWwiLCAiU2V0dGluZ3NWaWV3IikKKyAgICAgICAgICAgIGVsc2UgaWYgKGRlc3RpbmF0aW9u
ID09PSAiaG9zdCIpIHsgQ3JpbXNvblN0YXR1cy5zZWxlY3RIb3N0KGVjbGlwc2VDZW50ZXIuaG9z
dC5pZCB8fCAiIiwgZWNsaXBzZUNlbnRlci5ob3N0LnVybCB8fCAiIik7IGNyaW1zb25QYW5lbC5r
aW5kID0gImhvc3QiOyBjcmltc29uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAgIGVsc2UgaWYg
KGRlc3RpbmF0aW9uID09PSAiYWJvdXQiKSB7IGVjbGlwc2VBYm91dC5pbmZvID0gU3lzdGVtQ29u
dHJvbHMuc3RhdGU7IGVjbGlwc2VBYm91dC5vcGVuKCkgfQorICAgICAgICAgICAgZWxzZSBpZiAo
ZGVzdGluYXRpb24gPT09ICJtYW5hZ2VtZW50IiAmJiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dz
ZXIpIFN5c3RlbVByb3BlcnRpZXMub3BlblVybChlY2xpcHNlQ2VudGVyLmhvc3QudXJsKQorICAg
ICAgICB9CisgICAgfQorCiAgICAgaGVhZGVyOiBUb29sQmFyIHsKICAgICAgICAgaWQ6IHRvb2xC
YXIKICAgICAgICAgLy8gUmVkZXNpZ246IEVWRVJZIHJlZGVzaWduZWQgbGF1bmNoZXIgc2NyZWVu
IChDb21wdXRlcnMsIEFwcCBncmlkLCBTZXR0aW5ncywgSGVscCkKQEAgLTMzOCwyMCArMzczLDE5
IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgLy8gVklCRU1JUyB3b3JkbWFyayAoZGlh
bW9uZCArIHdvcmRtYXJrKSwgc2hvd24gb24gdGhlIENvbXB1dGVycyBzY3JlZW4gaW4gcGxhY2Ug
b2YgYSB0aXRsZSwKICAgICAgICAgLy8gbWF0Y2hpbmcgdGhlIGRlc2lnbiBoZWFkZXIuIExlZnQt
YWxpZ25lZCBhdCB0aGUgSFRNTCdzIDQwcHggcGFkZGluZy4KICAgICAgICAgUm93IHsKLSAgICAg
ICAgICAgIHZpc2libGU6IHRvb2xCYXIub25QY1ZpZXcKKyAgICAgICAgICAgIHZpc2libGU6IHRv
b2xCYXIub25QY1ZpZXcgJiYgdG9vbEJhci53aWR0aCA+IDgyMAogICAgICAgICAgICAgYW5jaG9y
cy5sZWZ0OiBwYXJlbnQubGVmdAogICAgICAgICAgICAgYW5jaG9ycy5sZWZ0TWFyZ2luOiA0MAog
ICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVy
CiAgICAgICAgICAgICBzcGFjaW5nOiAxMQotICAgICAgICAgICAgUmVjdGFuZ2xlIHsKKyAgICAg
ICAgICAgIEltYWdlIHsKICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBw
YXJlbnQudmVydGljYWxDZW50ZXIKLSAgICAgICAgICAgICAgICB3aWR0aDogMTM7IGhlaWdodDog
MTMKLSAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYWNjZW50Ci0gICAgICAgICAgICAg
ICAgcm90YXRpb246IDQ1CisgICAgICAgICAgICAgICAgd2lkdGg6IDI4OyBoZWlnaHQ6IDI4Cisg
ICAgICAgICAgICAgICAgc291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyIKICAgICAg
ICAgICAgIH0KICAgICAgICAgICAgIFRleHQgewogICAgICAgICAgICAgICAgIGFuY2hvcnMudmVy
dGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlcgotICAgICAgICAgICAgICAgIHRleHQ6
ICJWSUJFTUlTIgorICAgICAgICAgICAgICAgIHRleHQ6ICJFQ0xJUFNFIgogICAgICAgICAgICAg
ICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250RGlzcGxheQogICAgICAgICAgICAgICAgIGZv
bnQud2VpZ2h0OiBGb250LkV4dHJhQm9sZAogICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXpl
OiAyMQpAQCAtMzY1LDcgKzM5OSw3IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgICAg
IC8vIEhpZGRlbiBvbiBDb21wdXRlcnMgKHRoZSB3b3JkbWFyayBzdGFuZHMgaW4pIGFuZCBvbiB0
aGUgQXBwIGdyaWQgKHdoaWNoIHNob3dzIGEKICAgICAgICAgICAgIC8vIGxlZnQtYWxpZ25lZCBo
b3N0ICsgc3RhdHVzIGJsb2NrIGluc3RlYWQpLiBPbiBTZXR0aW5ncy9IZWxwIGl0IHNob3dzIHRo
ZSBzY3JlZW4gbmFtZTsKICAgICAgICAgICAgIC8vIHRoZSBzdHJlYW1pbmcgc2VndWVzIGtlZXAg
dGhlaXIgZGVmYXVsdCBvYmplY3ROYW1lIHRpdGxlLgotICAgICAgICAgICAgdmlzaWJsZTogIXRv
b2xCYXIub25QY1ZpZXcgJiYgIXRvb2xCYXIub25BcHBWaWV3ICYmIHRvb2xCYXIud2lkdGggPiA3
MDAKKyAgICAgICAgICAgIHZpc2libGU6ICF0b29sQmFyLm9uUGNWaWV3ICYmICF0b29sQmFyLm9u
QXBwVmlldyAmJiB0b29sQmFyLndpZHRoID4gODIwCiAgICAgICAgICAgICBhbmNob3JzLmZpbGw6
IHBhcmVudAogICAgICAgICAgICAgdGV4dDogdG9vbEJhci5vblNldHRpbmdzID8gcXNUcigiU2V0
dGluZ3MiKQogICAgICAgICAgICAgICAgIDogdG9vbEJhci5vbkhlbHAgPyBxc1RyKCJIZWxwIikK
QEAgLTQ4Nyw2ICs1MjEsNTQgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICAgICAgICAg
IH0KICAgICAgICAgICAgIH0KIAorICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7Cisg
ICAgICAgICAgICAgICAgaWQ6IG5ldHdvcmtTdGF0dXNCdXR0b24KKyAgICAgICAgICAgICAgICBp
Y29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZyIKKyAgICAgICAgICAgICAg
ICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIldpLUZpIHNldHRpbmdzIikKKyAgICAgICAgICAgICAg
ICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6
IHFzVHIoIk5ldHdvcms6ICUxIikuYXJnKENyaW1zb25TdGF0dXMubG9jYWwubmV0d29yayB8fCBx
c1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBjb25uZWN0
aW9uUGFuZWwua2luZCA9ICJ3aWZpIjsgY29ubmVjdGlvblBhbmVsLm9wZW4oKSB9CisgICAgICAg
ICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1ZpZXcuY3VycmVudEl0ZW0uZm9yY2VB
Y3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAgICAgICBSZWN0YW5nbGUgeworICAg
ICAgICAgICAgICAgICAgICBhbmNob3JzLnJpZ2h0OiBwYXJlbnQucmlnaHQ7IGFuY2hvcnMuYm90
dG9tOiBwYXJlbnQuYm90dG9tOyBhbmNob3JzLm1hcmdpbnM6IDUKKyAgICAgICAgICAgICAgICAg
ICAgd2lkdGg6IDg7IGhlaWdodDogODsgcmFkaXVzOiA0CisgICAgICAgICAgICAgICAgICAgIGNv
bG9yOiBDcmltc29uU3RhdHVzLmxvY2FsLmNvbm5lY3RlZCA/IFZiVG9rZW5zLnN0YXR1c09ubGlu
ZSA6IFZiVG9rZW5zLnN0YXR1c09mZmxpbmUKKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAg
ICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAgICAgICBp
ZDogYmx1ZXRvb3RoU2V0dGluZ3NCdXR0b24KKyAgICAgICAgICAgICAgICBpY29uU291cmNlOiAi
cXJjOi9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2li
bGUubmFtZTogcXNUcigiQmx1ZXRvb3RoIHNldHRpbmdzIikKKyAgICAgICAgICAgICAgICBUb29s
VGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIo
IlBhaXIgY29udHJvbGxlcnMgYW5kIGhlYWRwaG9uZXMiKQorICAgICAgICAgICAgICAgIG9uQ2xp
Y2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9ICJidCI7IGNvbm5lY3Rpb25QYW5lbC5vcGVu
KCkgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJl
bnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAgICB9CisgICAg
ICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogYmF0dGVy
eVN0YXR1c0J1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9jcmlt
c29uLWJhdHRlcnkuc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigi
QmF0dGVyeSBzdGF0dXMiKQorICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJl
ZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0
ZXJ5UGVyY2VudCA+PSAwID8gcXNUcigiQmF0dGVyeTogJTElIOKAoiAlMiIpLmFyZyhDcmltc29u
U3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50KS5hcmcoQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0
ZXJ5U3RhdGUpIDogcXNUcigiQmF0dGVyeSB1bmF2YWlsYWJsZSIpCisgICAgICAgICAgICAgICAg
b25DbGlja2VkOiB7IGNyaW1zb25QYW5lbC5raW5kID0gImJhdHRlcnkiOyBjcmltc29uUGFuZWwu
b3BlbigpIH0KKyAgICAgICAgICAgICAgICBLZXlzLm9uRG93blByZXNzZWQ6IHN0YWNrVmlldy5j
dXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgICAgICAgICAgfQor
ICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IGhv
c3RIYXJkd2FyZUJ1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9j
cmltc29uLWhvc3Quc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigi
VmliZXBvbGxvIGhvc3QgaGFyZHdhcmUgc3RhdHMiKQorICAgICAgICAgICAgICAgIFRvb2xUaXAu
dmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiSG9z
dCBDUFUsIFJBTSwgR1BVIGFuZCB0ZW1wZXJhdHVyZXMiKQorICAgICAgICAgICAgICAgIG9uQ2xp
Y2tlZDogeworICAgICAgICAgICAgICAgICAgICB2YXIgaXRlbSA9IHN0YWNrVmlldy5jdXJyZW50
SXRlbQorICAgICAgICAgICAgICAgICAgICB2YXIgaG9zdCA9IHRvb2xCYXIub25BcHBWaWV3ID8g
aXRlbS5jcmltc29uSG9zdAorICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6ICh0b29sQmFy
Lm9uUGNWaWV3ID8gaXRlbS5jb21wdXRlck1vZGVsLmNyaW1zb25Ib3N0KGl0ZW0uY3VycmVudElu
ZGV4KSA6IHt9KQorICAgICAgICAgICAgICAgICAgICBDcmltc29uU3RhdHVzLnNlbGVjdEhvc3Qo
aG9zdC5pZCB8fCAiIiwgaG9zdC51cmwgfHwgIiIpCisgICAgICAgICAgICAgICAgICAgIGNyaW1z
b25QYW5lbC5raW5kID0gImhvc3QiOyBjcmltc29uUGFuZWwub3BlbigpCisgICAgICAgICAgICAg
ICAgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJl
bnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAgICB9CisKICAg
ICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24gewogICAgICAgICAgICAgICAgIGlkOiBkaXNj
b3JkQnV0dG9uCiAgICAgICAgICAgICAgICAgdmlzaWJsZTogZmFsc2UgLy8gVGVtcG9yYXJpbHkg
ZGlzYWJsZWQgZm9yIFZpYmVtaXMKQEAgLTU2NCw3ICs2NDYsNyBAQCBBcHBsaWNhdGlvbldpbmRv
dyB7CiAgICAgICAgICAgICAgICAgLy8gYW4gaW5zdGFsbCBmYWlsdXJlIGZhbGxzIGJhY2sgdG8g
dGhlIHJlbGVhc2UgcGFnZSBvbiBpdHMgb3duLgogICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4
dDogQXV0b1VwZGF0ZUNoZWNrZXIuaW5zdGFsbGluZwogICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgPyBxc1RyKCJEb3dubG9hZGluZyB1cGRhdGXigKYiKQotICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgOiBxc1RyKCJVcGRhdGUgYXZhaWxhYmxlIGZvciBWaWJlbWlzOiBWZXJzaW9u
ICUxIOKAlCB0YXAgdG8gaW5zdGFsbCIpLmFyZyhBdXRvVXBkYXRlQ2hlY2tlci5hdmFpbGFibGVW
ZXJzaW9uKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBxc1RyKCJVcGRhdGUgYXZh
aWxhYmxlIGZvciBFY2xpcHNlOiBWZXJzaW9uICUxIOKAlCB0YXAgdG8gaW5zdGFsbCIpLmFyZyhB
dXRvVXBkYXRlQ2hlY2tlci5hdmFpbGFibGVWZXJzaW9uKQogCiAgICAgICAgICAgICAgICAgLy8g
U3RyaWN0bHktbmV3ZXIgYnVpbGRzIG9ubHkgKGEgY2hhbm5lbC1zd2l0Y2ggZG93bmdyYWRlIG9m
ZmVyCiAgICAgICAgICAgICAgICAgLy8gbGl2ZXMgaW4gU2V0dGluZ3MsIG5vdCBvbiB0aGUgdG9v
bGJhcikuCkBAIC02NDYsNiArNzI4LDIxIEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAg
ICAgICAgICB9CiAgICAgICAgICAgICB9CiAKKyAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0
b24geworICAgICAgICAgICAgICAgIGlkOiBlY2xpcHNlQ2VudGVyQnV0dG9uCisgICAgICAgICAg
ICAgICAgaWNvblNvdXJjZTogInFyYzovcmVzL2VjbGlwc2UtY29udHJvbHMuc3ZnIgorICAgICAg
ICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiRWNsaXBzZSBjb250cm9sIGNlbnRlciIp
CisgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCisgICAgICAgICAgICAg
ICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJDb250cm9sIGNlbnRlciDigKIgQ3RybCtTaGlmdCtDIikK
KyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsKKyAgICAgICAgICAgICAgICAgICAgdmFyIGl0
ZW0gPSBzdGFja1ZpZXcuY3VycmVudEl0ZW0KKyAgICAgICAgICAgICAgICAgICAgZWNsaXBzZUNl
bnRlci5ob3N0ID0gdG9vbEJhci5vbkFwcFZpZXcgPyBpdGVtLmNyaW1zb25Ib3N0IDogKHRvb2xC
YXIub25QY1ZpZXcgPyBpdGVtLmNvbXB1dGVyTW9kZWwuY3JpbXNvbkhvc3QoaXRlbS5jdXJyZW50
SW5kZXgpIDoge30pCisgICAgICAgICAgICAgICAgICAgIGVjbGlwc2VDZW50ZXIub3BlbigpCisg
ICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3Rh
Y2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAg
ICAgICAgICAgU2hvcnRjdXQgeyBzZXF1ZW5jZTogIkN0cmwrU2hpZnQrQyI7IGVuYWJsZWQ6IHRv
b2xCYXIub25QY1ZpZXcgfHwgdG9vbEJhci5vbkFwcFZpZXc7IG9uQWN0aXZhdGVkOiBlY2xpcHNl
Q2VudGVyQnV0dG9uLmNsaWNrZWQoKSB9CisgICAgICAgICAgICB9CisKICAgICAgICAgICAgIE5h
dmlnYWJsZVRvb2xCdXR0b24gewogICAgICAgICAgICAgICAgIGlkOiBzZXR0aW5nc0J1dHRvbgog
CkBAIC02NzMsNyArNzcwLDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogCiAgICAgRXJyb3JNZXNz
YWdlRGlhbG9nIHsKICAgICAgICAgaWQ6IG5vSHdEZWNvZGVyRGlhbG9nCi0gICAgICAgIHRleHQ6
IHFzVHIoIk5vIGZ1bmN0aW9uaW5nIGhhcmR3YXJlIGFjY2VsZXJhdGVkIHZpZGVvIGRlY29kZXIg
d2FzIGRldGVjdGVkIGJ5IFZpYmVtaXMuICIgKworICAgICAgICB0ZXh0OiBxc1RyKCJObyBmdW5j
dGlvbmluZyBoYXJkd2FyZSBhY2NlbGVyYXRlZCB2aWRlbyBkZWNvZGVyIHdhcyBkZXRlY3RlZCBi
eSBFY2xpcHNlLiAiICsKICAgICAgICAgICAgICAgICAgICAiWW91ciBzdHJlYW1pbmcgcGVyZm9y
bWFuY2UgbWF5IGJlIHNldmVyZWx5IGRlZ3JhZGVkIGluIHRoaXMgY29uZmlndXJhdGlvbi4iKQog
ICAgICAgICBoZWxwVGV4dDogcXNUcigiQ2xpY2sgdGhlIEhlbHAgYnV0dG9uIGZvciBtb3JlIGlu
Zm9ybWF0aW9uIG9uIHNvbHZpbmcgdGhpcyBwcm9ibGVtLiIpCiAgICAgICAgIGhlbHBVcmw6ICJo
dHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3ZpYmVtaXMiCkBAIC02OTAsNyArNzg3LDcgQEAg
QXBwbGljYXRpb25XaW5kb3cgewogICAgIE5hdmlnYWJsZU1lc3NhZ2VEaWFsb2cgewogICAgICAg
ICBpZDogd293NjREaWFsb2cKICAgICAgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuT2sgfCBE
aWFsb2cuQ2FuY2VsCi0gICAgICAgIHRleHQ6IHFzVHIoIlRoaXMgdmVyc2lvbiBvZiBWaWJlbWlz
IGlzbid0IG9wdGltaXplZCBmb3IgeW91ciBQQy4gUGxlYXNlIGRvd25sb2FkIHRoZSAnJTEnIHZl
cnNpb24gb2YgVmliZW1pcyBmb3IgdGhlIGJlc3Qgc3RyZWFtaW5nIHBlcmZvcm1hbmNlLiIpLmFy
ZyhTeXN0ZW1Qcm9wZXJ0aWVzLmZyaWVuZGx5TmF0aXZlQXJjaE5hbWUpCisgICAgICAgIHRleHQ6
IHFzVHIoIlRoaXMgdmVyc2lvbiBvZiBFY2xpcHNlIGlzbid0IG9wdGltaXplZCBmb3IgeW91ciBQ
Qy4gUGxlYXNlIGRvd25sb2FkIHRoZSAnJTEnIHZlcnNpb24gb2YgRWNsaXBzZSBmb3IgdGhlIGJl
c3Qgc3RyZWFtaW5nIHBlcmZvcm1hbmNlLiIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLmZyaWVuZGx5
TmF0aXZlQXJjaE5hbWUpCiAgICAgICAgIG9uQWNjZXB0ZWQ6IHsKICAgICAgICAgICAgIFN5c3Rl
bVByb3BlcnRpZXMub3BlblVybCgiaHR0cHM6Ly9naXRodWIuY29tL25hdnlhczMyMS92aWJlbWlz
L3JlbGVhc2VzIik7CiAgICAgICAgIH0KQEAgLTY5OSw3ICs3OTYsNyBAQCBBcHBsaWNhdGlvbldp
bmRvdyB7CiAgICAgRXJyb3JNZXNzYWdlRGlhbG9nIHsKICAgICAgICAgaWQ6IHVubWFwcGVkR2Ft
ZXBhZERpYWxvZwogICAgICAgICBwcm9wZXJ0eSBzdHJpbmcgdW5tYXBwZWRHYW1lcGFkcyA6ICIi
Ci0gICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMgZGV0ZWN0ZWQgZ2FtZXBhZHMgd2l0aG91dCBh
IG1hcHBpbmc6IikgKyAiXG4iICsgdW5tYXBwZWRHYW1lcGFkcworICAgICAgICB0ZXh0OiBxc1Ry
KCJFY2xpcHNlIGRldGVjdGVkIGdhbWVwYWRzIHdpdGhvdXQgYSBtYXBwaW5nOiIpICsgIlxuIiAr
IHVubWFwcGVkR2FtZXBhZHMKICAgICAgICAgaGVscFRleHRTZXBhcmF0b3I6ICJcblxuIgogICAg
ICAgICBoZWxwVGV4dDogcXNUcigiQ2xpY2sgdGhlIEhlbHAgYnV0dG9uIGZvciBpbmZvcm1hdGlv
biBvbiBob3cgdG8gbWFwIHlvdXIgZ2FtZXBhZHMuIikKICAgICAgICAgaGVscFVybDogImh0dHBz
Oi8vZ2l0aHViLmNvbS9uYXZ5YXMzMjEvdmliZW1pcyIKZGlmZiAtLWdpdCBhL2FwcC9tYWluLmNw
cCBiL2FwcC9tYWluLmNwcAppbmRleCAyOTIyMjc3Ny4uM2VjOTRkYmYgMTAwNjQ0Ci0tLSBhL2Fw
cC9tYWluLmNwcAorKysgYi9hcHAvbWFpbi5jcHAKQEAgLTg2OSw2ICs4NjksNyBAQCBpbnQgbWFp
bihpbnQgYXJnYywgY2hhciAqYXJndltdKQogICAgIH0NCiANCiAgICAgUUd1aUFwcGxpY2F0aW9u
IGFwcChhcmdjLCBhcmd2KTsNCisgICAgUUd1aUFwcGxpY2F0aW9uOjpzZXRBcHBsaWNhdGlvbkRp
c3BsYXlOYW1lKCJFY2xpcHNlIik7CiANCiAgICAgLy8gVmliZW1pczogdGhlIFF0IFF1aWNrIENv
bnRyb2xzIE1hdGVyaWFsIHN0eWxlIHJlbmRlcnMgYnV0dG9uIHRleHQgaW4gQUxMIENBUFMgYnkg
ZGVmYXVsdA0KICAgICAvLyAoZS5nLiB0aGUgYml0cmF0ZSAiVVNFIERFRkFVTFQgKDMwIE1CUFMp
IiBidXR0b24pLCB3aGljaCBsb29rcyBvZmYuIEZvcmNlIG1peGVkIGNhc2UgZm9yIHRoZQ0KZGlm
ZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcCBiL2FwcC9tb29ubGln
aHRvcy9jcmltc29uc3RhdHVzLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
MC4uZGFmY2EyZWUKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0
YXR1cy5jcHAKQEAgLTAsMCArMSwyMjIgQEAKKyNpbmNsdWRlICJjcmltc29uc3RhdHVzLmgiCisj
aW5jbHVkZSA8UURhdGVUaW1lPgorI2luY2x1ZGUgPFFEaXI+CisjaW5jbHVkZSA8UUZpbGU+Cisj
aW5jbHVkZSA8UUpzb25Eb2N1bWVudD4KKyNpbmNsdWRlIDxRSnNvbk9iamVjdD4KKyNpbmNsdWRl
IDxRTmV0d29ya0ludGVyZmFjZT4KKyNpbmNsdWRlIDxRTmV0d29ya1JlcXVlc3Q+CisjaW5jbHVk
ZSA8UVNhdmVGaWxlPgorI2luY2x1ZGUgPFFTc2xDZXJ0aWZpY2F0ZT4KKyNpbmNsdWRlIDxRU3Ns
RXJyb3I+CisjaW5jbHVkZSA8UVN0YW5kYXJkUGF0aHM+CisjaW5jbHVkZSA8UUNyeXB0b2dyYXBo
aWNIYXNoPgorI2luY2x1ZGUgPFFVcmw+CisjaW5jbHVkZSA8Y21hdGg+CisjaW5jbHVkZSA8UVFt
bEVuZ2luZT4KKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUgPG1lbW9yeT4K
KyNpbmNsdWRlIDxRUmVndWxhckV4cHJlc3Npb24+CisjaW5jbHVkZSA8UUZpbGVJbmZvPgorI2lu
Y2x1ZGUgPFFTc2xDb25maWd1cmF0aW9uPgorCituYW1lc3BhY2UgeworUVN0cmluZyByZWFkKGNv
bnN0IFFTdHJpbmcmIHBhdGgpIHsKKyAgICBRRmlsZSBmKHBhdGgpOyByZXR1cm4gZi5vcGVuKFFJ
T0RldmljZTo6UmVhZE9ubHkpID8gUVN0cmluZzo6ZnJvbVV0ZjgoZi5yZWFkQWxsKCkpLnRyaW1t
ZWQoKSA6IFFTdHJpbmcoKTsKK30KK2NvbnN0IGF1dG8gdXNlck9ubHkgPSBRRmlsZURldmljZTo6
UmVhZE93bmVyIHwgUUZpbGVEZXZpY2U6OldyaXRlT3duZXI7Cit9CitDcmltc29uU3RhdHVzOjpD
cmltc29uU3RhdHVzKFFPYmplY3QqIHBhcmVudCkgOiBRT2JqZWN0KHBhcmVudCkgeworICAgIGNv
bm5lY3QoJm1fbG9jYWxUaW1lciwgJlFUaW1lcjo6dGltZW91dCwgdGhpcywgJkNyaW1zb25TdGF0
dXM6OnJlZnJlc2hMb2NhbCk7CisgICAgY29ubmVjdCgmbV9zdGF0c1RpbWVyLCAmUVRpbWVyOjp0
aW1lb3V0LCB0aGlzLCAmQ3JpbXNvblN0YXR1czo6cmVmcmVzaCk7CisgICAgY29ubmVjdCgmbV93
aWZpLCAmUVByb2Nlc3M6OmZpbmlzaGVkLCB0aGlzLCBbdGhpc10oaW50IGV4aXQsIFFQcm9jZXNz
OjpFeGl0U3RhdHVzKSB7CisgICAgICAgIGlmIChleGl0ID09IDApIHsKKyAgICAgICAgICAgIGNv
bnN0IGF1dG8gbGluZXMgPSBRU3RyaW5nOjpmcm9tVXRmOChtX3dpZmkucmVhZEFsbFN0YW5kYXJk
T3V0cHV0KCkpLnNwbGl0KCdcbicpOworICAgICAgICAgICAgZm9yIChjb25zdCBhdXRvJiBsaW5l
IDogbGluZXMpIHsKKyAgICAgICAgICAgICAgICBpZiAoIWxpbmUuc3RhcnRzV2l0aCgieWVzOiIp
KSBjb250aW51ZTsKKyAgICAgICAgICAgICAgICBpbnQgc2VwYXJhdG9yID0gbGluZS5pbmRleE9m
KCc6JywgNCk7IGJvb2wgb2sgPSBmYWxzZTsKKyAgICAgICAgICAgICAgICBpbnQgc2lnbmFsID0g
bGluZS5taWQoNCwgc2VwYXJhdG9yIC0gNCkudG9JbnQoJm9rKTsKKyAgICAgICAgICAgICAgICBp
ZiAob2sgJiYgc2lnbmFsID49IDAgJiYgc2lnbmFsIDw9IDEwMCkgbV9sb2NhbFsid2lmaVNpZ25h
bCJdID0gc2lnbmFsOworICAgICAgICAgICAgICAgIGlmIChzZXBhcmF0b3IgPj0gMCkgbV9sb2Nh
bFsibmV0d29yayJdID0gdHIoIldpLUZpOiAlMSIpLmFyZyhsaW5lLm1pZChzZXBhcmF0b3IgKyAx
KSk7CisgICAgICAgICAgICAgICAgYnJlYWs7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBl
bWl0IGxvY2FsQ2hhbmdlZCgpOworICAgICAgICB9CisgICAgfSk7CisgICAgbV9sb2NhbFRpbWVy
LnN0YXJ0KDEwMDAwKTsgbV9zdGF0c1RpbWVyLnNldEludGVydmFsKDIwMDApOyByZWZyZXNoTG9j
YWwoKTsKK30KK0NyaW1zb25TdGF0dXM6On5Dcmltc29uU3RhdHVzKCkgeworICAgIG1fc3RhdHNU
aW1lci5zdG9wKCk7IG1fbG9jYWxUaW1lci5zdG9wKCk7IGNhbmNlbCgpOworICAgIGlmIChtX3dp
Zmkuc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgeyBtX3dpZmkua2lsbCgpOyBtX3dp
Zmkud2FpdEZvckZpbmlzaGVkKDUwMCk7IH0KK30KK1FTdHJpbmcgQ3JpbXNvblN0YXR1czo6Y29u
ZmlnRmlsZSgpIGNvbnN0IHsKKyAgICByZXR1cm4gUVN0YW5kYXJkUGF0aHM6OndyaXRhYmxlTG9j
YXRpb24oUVN0YW5kYXJkUGF0aHM6OkFwcENvbmZpZ0xvY2F0aW9uKSArICIvY3JpbXNvbi1ob3N0
cy5qc29uIjsKK30KK1FTdHJpbmcgQ3JpbXNvblN0YXR1czo6bm9ybWFsaXplZFBpbihRU3RyaW5n
IHBpbikgeworICAgIHBpbi5yZW1vdmUoJzonKTsgcGluLnJlbW92ZSgnICcpOyByZXR1cm4gcGlu
LnRvTG93ZXIoKTsKK30KK2Jvb2wgQ3JpbXNvblN0YXR1czo6dmFsaWRFbmRwb2ludChjb25zdCBR
U3RyaW5nJiB2YWx1ZSkgeworICAgIFFVcmwgdSh2YWx1ZSwgUVVybDo6U3RyaWN0TW9kZSk7Cisg
ICAgcmV0dXJuIHUuaXNWYWxpZCgpICYmIHUuc2NoZW1lKCkgPT0gImh0dHBzIiAmJiAhdS5ob3N0
KCkuaXNFbXB0eSgpICYmCisgICAgICAgIHUudXNlckluZm8oKS5pc0VtcHR5KCkgJiYgdS5xdWVy
eSgpLmlzRW1wdHkoKSAmJiB1LmZyYWdtZW50KCkuaXNFbXB0eSgpICYmCisgICAgICAgICh1LnBh
dGgoKS5pc0VtcHR5KCkgfHwgdS5wYXRoKCkgPT0gIi8iKSAmJiB1LnBvcnQoNDc5OTApID4gMDsK
K30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6Y2FuY2VsKCkgeworICAgIGlmIChtX3JlcGx5KSB7IGRp
c2Nvbm5lY3QobV9yZXBseSwgbnVsbHB0ciwgdGhpcywgbnVsbHB0cik7IG1fcmVwbHktPmFib3J0
KCk7IG1fcmVwbHktPmRlbGV0ZUxhdGVyKCk7IG1fcmVwbHkgPSBudWxscHRyOyB9Cit9Cit2b2lk
IENyaW1zb25TdGF0dXM6OnNlbGVjdEhvc3QoUVN0cmluZyBpZCwgUVN0cmluZyBzdWdnZXN0ZWRV
cmwpIHsKKyAgICBpZiAoaWQgPT0gbV9ob3N0KSByZXR1cm47CisgICAgY2FuY2VsKCk7IG1fbmV0
d29yay5jbGVhckNvbm5lY3Rpb25DYWNoZSgpOyBtX2hvc3QgPSBpZDsgbV90b2tlbi5jbGVhcigp
OyBtX3Bpbi5jbGVhcigpOworICAgIG1fZW5kcG9pbnQgPSB2YWxpZEVuZHBvaW50KHN1Z2dlc3Rl
ZFVybCkgPyBzdWdnZXN0ZWRVcmwgOiBRU3RyaW5nKCk7CisgICAgUUZpbGUgZihjb25maWdGaWxl
KCkpOworICAgIGlmIChmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkpIHsKKyAgICAgICAgYXV0
byBjID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24oZi5yZWFkQWxsKCkpLm9iamVjdCgpLnZhbHVl
KGlkKS50b09iamVjdCgpOworICAgICAgICBpZiAodmFsaWRFbmRwb2ludChjLnZhbHVlKCJ1cmwi
KS50b1N0cmluZygpKSkgeworICAgICAgICAgICAgbV9lbmRwb2ludCA9IGMudmFsdWUoInVybCIp
LnRvU3RyaW5nKCk7IG1fdG9rZW4gPSBjLnZhbHVlKCJ0b2tlbiIpLnRvU3RyaW5nKCk7IG1fcGlu
ID0gYy52YWx1ZSgicGluIikudG9TdHJpbmcoKTsKKyAgICAgICAgfQorICAgIH0KKyAgICBtX3N0
YXRzLmNsZWFyKCk7IG1fc3RhdHVzID0gaWQuaXNFbXB0eSgpID8gdHIoIkNob29zZSBhIGhvc3Qg
dG8gdmlldyBoYXJkd2FyZSBzdGF0cyIpIDogdHIoIkNvbmZpZ3VyZSBhIFZpYmVwb2xsbyByZWFk
LW9ubHkgc3RhdHMgdG9rZW4iKTsKKyAgICBlbWl0IGNvbmZpZ0NoYW5nZWQoKTsgZW1pdCBzdGF0
c0NoYW5nZWQoKTsgaWYgKG1fdmlzaWJsZSkgcmVmcmVzaCgpOworfQorYm9vbCBDcmltc29uU3Rh
dHVzOjpjb25maWd1cmUoUVN0cmluZyB1cmwsIFFTdHJpbmcgdG9rZW4sIFFTdHJpbmcgcGluKSB7
CisgICAgcGluID0gbm9ybWFsaXplZFBpbihwaW4pOworICAgIGlmIChtX2hvc3QuaXNFbXB0eSgp
IHx8ICF2YWxpZEVuZHBvaW50KHVybCkgfHwgKCFwaW4uaXNFbXB0eSgpICYmCisgICAgICAgIChw
aW4uc2l6ZSgpICE9IDY0IHx8IHBpbi5jb250YWlucyhRUmVndWxhckV4cHJlc3Npb24oIlteMC05
YS1mXSIpKSkpKSB7CisgICAgICAgIGZhaWwodHIoIlVzZSBhbiBIVFRQUyBob3N0IFVSTCBhbmQg
YW4gb3B0aW9uYWwgNjQtZGlnaXQgU0hBLTI1NiBjZXJ0aWZpY2F0ZSBmaW5nZXJwcmludCIpKTsg
cmV0dXJuIGZhbHNlOworICAgIH0KKyAgICAvLyBBIGJsYW5rIHRva2VuIGtlZXBzIHRoZSBvbGQg
dG9rZW4gb25seSBmb3IgdGhlIHNhbWUgZW5kcG9pbnQuCisgICAgaWYgKHRva2VuLmlzRW1wdHko
KSAmJiBRVXJsKHVybCkgPT0gUVVybChtX2VuZHBvaW50KSkgdG9rZW4gPSBtX3Rva2VuOworICAg
IGlmICh0b2tlbi5pc0VtcHR5KCkgfHwgdG9rZW4uY29udGFpbnMoJ1xyJykgfHwgdG9rZW4uY29u
dGFpbnMoJ1xuJykgfHwgdG9rZW4uc2l6ZSgpID4gNDA5NikgeworICAgICAgICBmYWlsKHRyKCJB
IHJlYWQtb25seSBWaWJlcG9sbG8gQVBJIHRva2VuIGlzIHJlcXVpcmVkIikpOyByZXR1cm4gZmFs
c2U7CisgICAgfQorICAgIFFGaWxlIGYoY29uZmlnRmlsZSgpKTsgUUpzb25PYmplY3QgYWxsOwor
ICAgIGlmIChmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkpIGFsbCA9IFFKc29uRG9jdW1lbnQ6
OmZyb21Kc29uKGYucmVhZEFsbCgpKS5vYmplY3QoKTsKKyAgICBhbGxbbV9ob3N0XSA9IFFKc29u
T2JqZWN0e3sidXJsIiwgdXJsfSwgeyJ0b2tlbiIsIHRva2VufSwgeyJwaW4iLCBwaW59fTsKKyAg
ICBRRGlyKCkubWtwYXRoKFFGaWxlSW5mbyhjb25maWdGaWxlKCkpLmFic29sdXRlUGF0aCgpKTsK
KyAgICBRU2F2ZUZpbGUgb3V0KGNvbmZpZ0ZpbGUoKSk7CisgICAgaWYgKCFvdXQub3BlbihRSU9E
ZXZpY2U6OldyaXRlT25seSkgfHwgIW91dC5zZXRQZXJtaXNzaW9ucyh1c2VyT25seSkgfHwKKyAg
ICAgICAgb3V0LndyaXRlKFFKc29uRG9jdW1lbnQoYWxsKS50b0pzb24oKSkgPCAwIHx8ICFvdXQu
Y29tbWl0KCkpIHsKKyAgICAgICAgZmFpbCh0cigiQ291bGQgbm90IHNhdmUgaG9zdCBhY2Nlc3Mg
c2V0dGluZ3MiKSk7IHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgY2FuY2VsKCk7IG1fbmV0d29y
ay5jbGVhckNvbm5lY3Rpb25DYWNoZSgpOyBtX2VuZHBvaW50ID0gdXJsOyBtX3Rva2VuID0gdG9r
ZW47IG1fcGluID0gcGluOworICAgIG1fc3RhdHNUaW1lci5zZXRJbnRlcnZhbCgyMDAwKTsKKyAg
ICBtX3N0YXRzLmNsZWFyKCk7IG1fc3RhdHVzID0gdHIoIkNvbm5lY3RpbmcgdG8gaG9zdCBzdGF0
c+KApiIpOworICAgIGVtaXQgY29uZmlnQ2hhbmdlZCgpOyBlbWl0IHN0YXRzQ2hhbmdlZCgpOyBy
ZWZyZXNoKCk7IHJldHVybiB0cnVlOworfQordm9pZCBDcmltc29uU3RhdHVzOjpzZXRWaXNpYmxl
KGJvb2wgdmlzaWJsZSkgeworICAgIG1fdmlzaWJsZSA9IHZpc2libGU7CisgICAgaWYgKHZpc2li
bGUpIHsgcmVmcmVzaExvY2FsKCk7IG1fc3RhdHNUaW1lci5zdGFydCgpOyByZWZyZXNoKCk7IH0K
KyAgICBlbHNlIHsgbV9zdGF0c1RpbWVyLnN0b3AoKTsgY2FuY2VsKCk7IH0KK30KK3ZvaWQgQ3Jp
bXNvblN0YXR1czo6ZmFpbChRU3RyaW5nIG1lc3NhZ2UpIHsKKyAgICBtX3N0YXRzLmNsZWFyKCk7
IG1fc3RhdHVzID0gbWVzc2FnZTsKKyAgICBtX3N0YXRzVGltZXIuc2V0SW50ZXJ2YWwocU1pbigz
MDAwMCwgcU1heCg0MDAwLCBtX3N0YXRzVGltZXIuaW50ZXJ2YWwoKSAqIDIpKSk7CisgICAgZW1p
dCBzdGF0c0NoYW5nZWQoKTsKK30KK1FWYXJpYW50TWFwIENyaW1zb25TdGF0dXM6OnBhcnNlU3Rh
dHMoY29uc3QgUUJ5dGVBcnJheSYgYnl0ZXMsIFFTdHJpbmcqIGVycm9yKSB7CisgICAgaWYgKGJ5
dGVzLnNpemUoKSA+IDY1NTM2KSB7ICplcnJvciA9ICJPdmVyc2l6ZWQgaG9zdCBzdGF0cyByZXNw
b25zZSI7IHJldHVybiB7fTsgfQorICAgIFFKc29uUGFyc2VFcnJvciBlOyBhdXRvIGRvYyA9IFFK
c29uRG9jdW1lbnQ6OmZyb21Kc29uKGJ5dGVzLCAmZSk7CisgICAgaWYgKGUuZXJyb3IgIT0gUUpz
b25QYXJzZUVycm9yOjpOb0Vycm9yIHx8ICFkb2MuaXNPYmplY3QoKSkgeyAqZXJyb3IgPSAiSW52
YWxpZCBob3N0IHN0YXRzIHJlc3BvbnNlIjsgcmV0dXJuIHt9OyB9CisgICAgYXV0byBvYmogPSBk
b2Mub2JqZWN0KCk7IFFWYXJpYW50TWFwIHJlc3VsdDsKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBr
ZXlzID0geyJjcHVfcGVyY2VudCIsImNwdV90ZW1wX2MiLCJyYW1fdXNlZF9ieXRlcyIsInJhbV90
b3RhbF9ieXRlcyIsInJhbV9wZXJjZW50IiwKKyAgICAgICAgImdwdV9wZXJjZW50IiwiZ3B1X2Vu
Y29kZXJfcGVyY2VudCIsImdwdV90ZW1wX2MiLCJ2cmFtX3VzZWRfYnl0ZXMiLCJ2cmFtX3RvdGFs
X2J5dGVzIiwidnJhbV9wZXJjZW50IiwibmV0X3J4X2JwcyIsIm5ldF90eF9icHMifTsKKyAgICBi
b29sIHJlY29nbml6ZWQgPSBmYWxzZTsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIGtleSA6IGtleXMp
IHsKKyAgICAgICAgYXV0byB2ID0gb2JqLnZhbHVlKGtleSk7IHJlY29nbml6ZWQgfD0gb2JqLmNv
bnRhaW5zKGtleSk7CisgICAgICAgIGRvdWJsZSBuID0gdi50b0RvdWJsZSgtMSk7CisgICAgICAg
IGlmICghdi5pc0RvdWJsZSgpIHx8ICFzdGQ6OmlzZmluaXRlKG4pIHx8IG4gPCAwIHx8IChrZXku
ZW5kc1dpdGgoInBlcmNlbnQiKSAmJiBuID4gMTAwKSkgY29udGludWU7CisgICAgICAgIHJlc3Vs
dFtrZXldID0gbjsKKyAgICB9CisgICAgZm9yIChjb25zdCBhdXRvJiBwcmVmaXggOiB7UVN0cmlu
ZygicmFtIiksIFFTdHJpbmcoInZyYW0iKX0pIHsKKyAgICAgICAgZG91YmxlIHRvdGFsID0gcmVz
dWx0LnZhbHVlKHByZWZpeCArICJfdG90YWxfYnl0ZXMiKS50b0RvdWJsZSgpOworICAgICAgICBp
ZiAodG90YWwgPD0gMCkgeyByZXN1bHQucmVtb3ZlKHByZWZpeCArICJfcGVyY2VudCIpOyByZXN1
bHQucmVtb3ZlKHByZWZpeCArICJfdXNlZF9ieXRlcyIpOyB9CisgICAgICAgIGVsc2UgaWYgKHJl
c3VsdC5jb250YWlucyhwcmVmaXggKyAiX3VzZWRfYnl0ZXMiKSkgeworICAgICAgICAgICAgZG91
YmxlIHVzZWQgPSBxTWluKHJlc3VsdC52YWx1ZShwcmVmaXggKyAiX3VzZWRfYnl0ZXMiKS50b0Rv
dWJsZSgpLCB0b3RhbCk7CisgICAgICAgICAgICByZXN1bHRbcHJlZml4ICsgIl91c2VkX2J5dGVz
Il0gPSB1c2VkOyByZXN1bHRbcHJlZml4ICsgIl9wZXJjZW50Il0gPSB1c2VkICogMTAwIC8gdG90
YWw7CisgICAgICAgIH0KKyAgICB9CisgICAgaWYgKCFyZWNvZ25pemVkKSB7ICplcnJvciA9ICJI
b3N0IGRvZXMgbm90IGV4cG9zZSB0aGUgZXhwZWN0ZWQgVmliZXBvbGxvIHN0YXRzIGZpZWxkcyI7
IHJldHVybiB7fTsgfQorICAgIGVycm9yLT5jbGVhcigpOyByZXR1cm4gcmVzdWx0OworfQordm9p
ZCBDcmltc29uU3RhdHVzOjpyZWZyZXNoKCkgeworICAgIGlmICghbV92aXNpYmxlIHx8IG1fcmVw
bHkgfHwgIWNvbmZpZ3VyZWQoKSkgcmV0dXJuOworICAgIFFVcmwgdXJsKG1fZW5kcG9pbnQpOyB1
cmwuc2V0UGF0aCgiL2FwaS9ob3N0L3N0YXRzIik7CisgICAgUU5ldHdvcmtSZXF1ZXN0IHJlcSh1
cmwpOworICAgIHJlcS5zZXRBdHRyaWJ1dGUoUU5ldHdvcmtSZXF1ZXN0OjpSZWRpcmVjdFBvbGlj
eUF0dHJpYnV0ZSwgUU5ldHdvcmtSZXF1ZXN0OjpNYW51YWxSZWRpcmVjdFBvbGljeSk7CisgICAg
cmVxLnNldFRyYW5zZmVyVGltZW91dCgzMDAwKTsKKyAgICByZXEuc2V0UmF3SGVhZGVyKCJBdXRo
b3JpemF0aW9uIiwgIkJlYXJlciAiICsgbV90b2tlbi50b1V0ZjgoKSk7CisgICAgcmVxLnNldFJh
d0hlYWRlcigiQWNjZXB0IiwgImFwcGxpY2F0aW9uL2pzb24iKTsKKyAgICBhdXRvIHJlcGx5ID0g
bV9uZXR3b3JrLmdldChyZXEpOyByZXBseS0+c2V0UmVhZEJ1ZmZlclNpemUoNjU1MzYpOyBtX3Jl
cGx5ID0gcmVwbHk7CisgICAgYXV0byBkYXRhID0gc3RkOjptYWtlX3NoYXJlZDxRQnl0ZUFycmF5
PigpOworICAgIGF1dG8gaW52YWxpZFBpbiA9IHN0ZDo6bWFrZV9zaGFyZWQ8Ym9vbD4oZmFsc2Up
OworICAgIGF1dG8gb3ZlcnNpemVkID0gc3RkOjptYWtlX3NoYXJlZDxib29sPihmYWxzZSk7Cisg
ICAgYXV0byBjZXJ0TWF0Y2hlcyA9IFt0aGlzLCByZXBseV0geworICAgICAgICByZXR1cm4gbm9y
bWFsaXplZFBpbihRU3RyaW5nOjpmcm9tTGF0aW4xKHJlcGx5LT5zc2xDb25maWd1cmF0aW9uKCku
cGVlckNlcnRpZmljYXRlKCkuZGlnZXN0KFFDcnlwdG9ncmFwaGljSGFzaDo6U2hhMjU2KS50b0hl
eCgpKSkgPT0gbV9waW47CisgICAgfTsKKyAgICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtSZXBs
eTo6ZW5jcnlwdGVkLCB0aGlzLCBbdGhpcywgcmVwbHksIGNlcnRNYXRjaGVzLCBpbnZhbGlkUGlu
XSB7CisgICAgICAgIGlmICghbV9waW4uaXNFbXB0eSgpICYmICFjZXJ0TWF0Y2hlcygpKSB7ICpp
bnZhbGlkUGluID0gdHJ1ZTsgcmVwbHktPmFib3J0KCk7IH0KKyAgICB9KTsKKyAgICBjb25uZWN0
KHJlcGx5LCAmUU5ldHdvcmtSZXBseTo6c3NsRXJyb3JzLCB0aGlzLCBbdGhpcywgcmVwbHksIGNl
cnRNYXRjaGVzXShjb25zdCBRTGlzdDxRU3NsRXJyb3I+JiBlcnJvcnMpIHsKKyAgICAgICAgaWYg
KG1fcGluLmlzRW1wdHkoKSB8fCAhY2VydE1hdGNoZXMoKSkgcmV0dXJuOworICAgICAgICBmb3Ig
KGNvbnN0IGF1dG8mIGUgOiBlcnJvcnMpIHsKKyAgICAgICAgICAgIGlmIChlLmVycm9yKCkgIT0g
UVNzbEVycm9yOjpTZWxmU2lnbmVkQ2VydGlmaWNhdGUgJiYgZS5lcnJvcigpICE9IFFTc2xFcnJv
cjo6U2VsZlNpZ25lZENlcnRpZmljYXRlSW5DaGFpbiAmJgorICAgICAgICAgICAgICAgIGUuZXJy
b3IoKSAhPSBRU3NsRXJyb3I6OkNlcnRpZmljYXRlVW50cnVzdGVkICYmIGUuZXJyb3IoKSAhPSBR
U3NsRXJyb3I6Okhvc3ROYW1lTWlzbWF0Y2gpIHJldHVybjsKKyAgICAgICAgfQorICAgICAgICBy
ZXBseS0+aWdub3JlU3NsRXJyb3JzKGVycm9ycyk7IC8vIE9ubHkgdGhpcyBleHBsaWNpdGx5IHBp
bm5lZCBob3N0IGNlcnRpZmljYXRlLgorICAgIH0pOworICAgIGNvbm5lY3QocmVwbHksICZRTmV0
d29ya1JlcGx5OjpyZWFkeVJlYWQsIHRoaXMsIFtyZXBseSwgZGF0YSwgb3ZlcnNpemVkXSB7Cisg
ICAgICAgIGlmICgqb3ZlcnNpemVkIHx8IHJlcGx5LT5pc0ZpbmlzaGVkKCkpIHJldHVybjsKKyAg
ICAgICAgaWYgKGRhdGEtPnNpemUoKSArIHJlcGx5LT5ieXRlc0F2YWlsYWJsZSgpID4gNjU1MzYp
IHsgKm92ZXJzaXplZCA9IHRydWU7IHJlcGx5LT5hYm9ydCgpOyByZXR1cm47IH0KKyAgICAgICAg
ZGF0YS0+YXBwZW5kKHJlcGx5LT5yZWFkQWxsKCkpOworICAgIH0pOworICAgIGNvbm5lY3QocmVw
bHksICZRTmV0d29ya1JlcGx5OjpmaW5pc2hlZCwgdGhpcywgW3RoaXMsIHJlcGx5LCBkYXRhLCBp
bnZhbGlkUGluLCBvdmVyc2l6ZWRdIHsKKyAgICAgICAgbV9yZXBseSA9IG51bGxwdHI7CisgICAg
ICAgIGludCBzdGF0dXMgPSByZXBseS0+YXR0cmlidXRlKFFOZXR3b3JrUmVxdWVzdDo6SHR0cFN0
YXR1c0NvZGVBdHRyaWJ1dGUpLnRvSW50KCk7CisgICAgICAgIGlmICgqb3ZlcnNpemVkKSBmYWls
KHRyKCJIb3N0IHN0YXRzIHJlc3BvbnNlIGV4Y2VlZGVkIHRoZSBzaXplIGxpbWl0IikpOworICAg
ICAgICBlbHNlIGlmICgqaW52YWxpZFBpbikgZmFpbCh0cigiSG9zdCBjZXJ0aWZpY2F0ZSBjaGFu
Z2VkOyB2ZXJpZnkgdGhlIHNhdmVkIGZpbmdlcnByaW50IikpOworICAgICAgICBlbHNlIGlmIChz
dGF0dXMgPT0gNDAxIHx8IHN0YXR1cyA9PSA0MDMpIGZhaWwodHIoIkhvc3Qgc3RhdHMgYWNjZXNz
IGRlbmllZDogY2hlY2sgdGhlIHJlYWQtb25seSB0b2tlbiIpKTsKKyAgICAgICAgZWxzZSBpZiAo
c3RhdHVzID09IDQwNCkgZmFpbCh0cigiVGhpcyBob3N0IGRvZXMgbm90IHByb3ZpZGUgVmliZXBv
bGxvIGhhcmR3YXJlIHN0YXRzIikpOworICAgICAgICBlbHNlIGlmIChyZXBseS0+ZXJyb3IoKSA9
PSBRTmV0d29ya1JlcGx5OjpTc2xIYW5kc2hha2VGYWlsZWRFcnJvcikgZmFpbCh0cigiVmVyaWZ5
IHRoZSBob3N0IGNlcnRpZmljYXRlIGZpbmdlcnByaW50IGluIENvbmZpZ3VyZSIpKTsKKyAgICAg
ICAgZWxzZSBpZiAocmVwbHktPmVycm9yKCkgIT0gUU5ldHdvcmtSZXBseTo6Tm9FcnJvciB8fCBz
dGF0dXMgIT0gMjAwKSBmYWlsKHRyKCJIb3N0IHN0YXRzIHVuYXZhaWxhYmxlOiBjaGVjayBjb25u
ZWN0aW9uIGFuZCByZWFsdGltZSBzdGF0cyBzZXR0aW5nIikpOworICAgICAgICBlbHNlIHsKKyAg
ICAgICAgICAgIGRhdGEtPmFwcGVuZChyZXBseS0+cmVhZEFsbCgpKTsgUVN0cmluZyBlcnJvcjsK
KyAgICAgICAgICAgIGF1dG8gcGFyc2VkID0gcGFyc2VTdGF0cygqZGF0YSwgJmVycm9yKTsKKyAg
ICAgICAgICAgIGlmICghZXJyb3IuaXNFbXB0eSgpKSBmYWlsKGVycm9yKTsKKyAgICAgICAgICAg
IGVsc2UgeyBtX3N0YXRzVGltZXIuc2V0SW50ZXJ2YWwoMjAwMCk7IG1fc3RhdHMgPSBwYXJzZWQ7
IG1fc3RhdHVzID0gdHIoIkhPU1Qg4oCiIHJlY2VpdmVkICUxIikuYXJnKFFEYXRlVGltZTo6Y3Vy
cmVudERhdGVUaW1lKCkudG9TdHJpbmcoImhoOm1tOnNzIikpOyBlbWl0IHN0YXRzQ2hhbmdlZCgp
OyB9CisgICAgICAgIH0KKyAgICAgICAgcmVwbHktPmRlbGV0ZUxhdGVyKCk7CisgICAgfSk7Cisg
ICAgLy8gQWJzb2x1dGUgcmVxdWVzdCBib3VuZCBldmVuIGlmIGEgcGVlciBrZWVwcyBzZW5kaW5n
IG9jY2FzaW9uYWwgYnl0ZXMuCisgICAgUVRpbWVyOjpzaW5nbGVTaG90KDM1MDAsIHJlcGx5LCBb
cmVwbHldIHsgaWYgKCFyZXBseS0+aXNGaW5pc2hlZCgpKSByZXBseS0+YWJvcnQoKTsgfSk7Cit9
CitRVmFyaWFudE1hcCBDcmltc29uU3RhdHVzOjpyZWFkTG9jYWwoY29uc3QgUVN0cmluZyYgcm9v
dCkgeworICAgIFFWYXJpYW50TWFwIG91dDsgUVN0cmluZ0xpc3QgbmV0d29ya3M7CisgICAgZm9y
IChjb25zdCBhdXRvJiBuYW1lIDogUURpcihyb290ICsgIi9jbGFzcy9uZXQiKS5lbnRyeUxpc3Qo
UURpcjo6RGlycyB8IFFEaXI6Ok5vRG90QW5kRG90RG90KSkgeworICAgICAgICBpZiAobmFtZSA9
PSAibG8iIHx8IHJlYWQocm9vdCArICIvY2xhc3MvbmV0LyIgKyBuYW1lICsgIi9vcGVyc3RhdGUi
KSAhPSAidXAiKSBjb250aW51ZTsKKyAgICAgICAgbmV0d29ya3MgPDwgbmFtZTsKKyAgICB9Cisg
ICAgb3V0WyJjb25uZWN0ZWQiXSA9ICFuZXR3b3Jrcy5pc0VtcHR5KCk7IG91dFsibmV0d29yayJd
ID0gbmV0d29ya3MuaXNFbXB0eSgpID8gdHIoIk5vIGFjdGl2ZSBuZXR3b3JrIGxpbmsiKSA6IG5l
dHdvcmtzLmpvaW4oIiwgIik7CisgICAgLy8gTGluayBzdGF0dXMgaXMgaW50ZW50aW9uYWxseSBu
b3QgcHJlc2VudGVkIGFzIGludGVybmV0IHJlYWNoYWJpbGl0eS4KKyAgICBvdXRbImJhdHRlcnlQ
ZXJjZW50Il0gPSAtMTsgb3V0WyJiYXR0ZXJ5U3RhdGUiXSA9IHRyKCJCYXR0ZXJ5IHVuYXZhaWxh
YmxlIik7CisgICAgZm9yIChjb25zdCBhdXRvJiBuYW1lIDogUURpcihyb290ICsgIi9jbGFzcy9w
b3dlcl9zdXBwbHkiKS5lbnRyeUxpc3QoUURpcjo6RGlycyB8IFFEaXI6Ok5vRG90QW5kRG90RG90
KSkgeworICAgICAgICBjb25zdCBhdXRvIGJhc2UgPSByb290ICsgIi9jbGFzcy9wb3dlcl9zdXBw
bHkvIiArIG5hbWUgKyAiLyI7CisgICAgICAgIGlmIChyZWFkKGJhc2UgKyAidHlwZSIpICE9ICJC
YXR0ZXJ5IiB8fCByZWFkKGJhc2UgKyAicHJlc2VudCIpID09ICIwIikgY29udGludWU7CisgICAg
ICAgIGJvb2wgb2s7IGludCBjYXAgPSByZWFkKGJhc2UgKyAiY2FwYWNpdHkiKS50b0ludCgmb2sp
OworICAgICAgICBpZiAob2sgJiYgY2FwID49IDAgJiYgY2FwIDw9IDEwMCkgb3V0WyJiYXR0ZXJ5
UGVyY2VudCJdID0gY2FwOworICAgICAgICBjb25zdCBhdXRvIHN0YXRlID0gcmVhZChiYXNlICsg
InN0YXR1cyIpOyBvdXRbImJhdHRlcnlTdGF0ZSJdID0gc3RhdGUuaXNFbXB0eSgpID8gdHIoIlVu
a25vd24iKSA6IHN0YXRlOyBicmVhazsKKyAgICB9CisgICAgcmV0dXJuIG91dDsKK30KK3ZvaWQg
Q3JpbXNvblN0YXR1czo6cmVmcmVzaExvY2FsKCkgeworICAgIG1fbG9jYWwgPSByZWFkTG9jYWwo
KTsgbV9sb2NhbFsid2lmaVNpZ25hbCJdID0gLTE7IGVtaXQgbG9jYWxDaGFuZ2VkKCk7CisgICAg
aWYgKG1fd2lmaS5zdGF0ZSgpID09IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSB7CisgICAgICAgIG1f
d2lmaS5zdGFydCgibm1jbGkiLCB7Ii10IiwgIi0tZXNjYXBlIiwgIm5vIiwgIi1mIiwgIkFDVElW
RSxTSUdOQUwsU1NJRCIsICJkZXZpY2UiLCAid2lmaSIsICJsaXN0IiwgIi0tcmVzY2FuIiwgIm5v
In0pOworICAgICAgICBRVGltZXI6OnNpbmdsZVNob3QoMjAwMCwgJm1fd2lmaSwgW3RoaXNdIHsg
aWYgKG1fd2lmaS5zdGF0ZSgpICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSBtX3dpZmkua2lsbCgp
OyB9KTsKKyAgICB9Cit9CisKK3N0YXRpYyB2b2lkIHJlZ2lzdGVyQ3JpbXNvblN0YXR1cygpIHsK
KyAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGU8Q3JpbXNvblN0YXR1cz4oIkNyaW1zb25TdGF0
dXMiLCAxLCAwLCAiQ3JpbXNvblN0YXR1cyIsCisgICAgICAgIFtdKFFRbWxFbmdpbmUqLCBRSlNF
bmdpbmUqKSAtPiBRT2JqZWN0KiB7IHJldHVybiBuZXcgQ3JpbXNvblN0YXR1cygpOyB9KTsKK30K
K1FfQ09SRUFQUF9TVEFSVFVQX0ZVTkNUSU9OKHJlZ2lzdGVyQ3JpbXNvblN0YXR1cykKZGlmZiAt
LWdpdCBhL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmggYi9hcHAvbW9vbmxpZ2h0b3Mv
Y3JpbXNvbnN0YXR1cy5oCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwLi4yZGFj
MGQxYwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmgK
QEAgLTAsMCArMSw1MiBAQAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4KKyNpbmNs
dWRlIDxRVmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRVGltZXI+CisjaW5jbHVkZSA8UU5ldHdvcmtB
Y2Nlc3NNYW5hZ2VyPgorI2luY2x1ZGUgPFFQb2ludGVyPgorI2luY2x1ZGUgPFFOZXR3b3JrUmVw
bHk+CisjaW5jbHVkZSA8UVByb2Nlc3M+CisKKy8vIE9wdGlvbmFsIGxhdW5jaGVyIHN0YXR1cy4g
TmV2ZXIgcGFydGljaXBhdGVzIGluIHRoZSBzdHJlYW1pbmcvZGVjb2RlciBwYXRoLgorY2xhc3Mg
Q3JpbXNvblN0YXR1cyA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorICAgIFFfUFJP
UEVSVFkoUVZhcmlhbnRNYXAgbG9jYWwgUkVBRCBsb2NhbCBOT1RJRlkgbG9jYWxDaGFuZ2VkKQor
ICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgc3RhdHMgUkVBRCBzdGF0cyBOT1RJRlkgc3RhdHND
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBzdGF0dXMgUkVBRCBzdGF0dXMgTk9USUZZ
IHN0YXRzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgZW5kcG9pbnQgUkVBRCBlbmRw
b2ludCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgZmluZ2Vy
cHJpbnQgUkVBRCBmaW5nZXJwcmludCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKKyAgICBRX1BST1BF
UlRZKGJvb2wgY29uZmlndXJlZCBSRUFEIGNvbmZpZ3VyZWQgTk9USUZZIGNvbmZpZ0NoYW5nZWQp
CitwdWJsaWM6CisgICAgZXhwbGljaXQgQ3JpbXNvblN0YXR1cyhRT2JqZWN0KiBwYXJlbnQgPSBu
dWxscHRyKTsKKyAgICB+Q3JpbXNvblN0YXR1cygpIG92ZXJyaWRlOworICAgIFFWYXJpYW50TWFw
IGxvY2FsKCkgY29uc3QgeyByZXR1cm4gbV9sb2NhbDsgfQorICAgIFFWYXJpYW50TWFwIHN0YXRz
KCkgY29uc3QgeyByZXR1cm4gbV9zdGF0czsgfQorICAgIFFTdHJpbmcgc3RhdHVzKCkgY29uc3Qg
eyByZXR1cm4gbV9zdGF0dXM7IH0KKyAgICBRU3RyaW5nIGVuZHBvaW50KCkgY29uc3QgeyByZXR1
cm4gbV9lbmRwb2ludDsgfQorICAgIFFTdHJpbmcgZmluZ2VycHJpbnQoKSBjb25zdCB7IHJldHVy
biBtX3BpbjsgfQorICAgIGJvb2wgY29uZmlndXJlZCgpIGNvbnN0IHsgcmV0dXJuICFtX2VuZHBv
aW50LmlzRW1wdHkoKSAmJiAhbV90b2tlbi5pc0VtcHR5KCk7IH0KKyAgICBRX0lOVk9LQUJMRSB2
b2lkIHNlbGVjdEhvc3QoUVN0cmluZyBpZCwgUVN0cmluZyBzdWdnZXN0ZWRVcmwpOworICAgIFFf
SU5WT0tBQkxFIGJvb2wgY29uZmlndXJlKFFTdHJpbmcgdXJsLCBRU3RyaW5nIHRva2VuLCBRU3Ry
aW5nIHBpbik7CisgICAgUV9JTlZPS0FCTEUgdm9pZCBzZXRWaXNpYmxlKGJvb2wgdmlzaWJsZSk7
CisgICAgUV9JTlZPS0FCTEUgdm9pZCByZWZyZXNoKCk7CisgICAgc3RhdGljIFFWYXJpYW50TWFw
IHBhcnNlU3RhdHMoY29uc3QgUUJ5dGVBcnJheSYgYnl0ZXMsIFFTdHJpbmcqIGVycm9yKTsKKyAg
ICBzdGF0aWMgYm9vbCB2YWxpZEVuZHBvaW50KGNvbnN0IFFTdHJpbmcmIHVybCk7CisgICAgc3Rh
dGljIFFTdHJpbmcgbm9ybWFsaXplZFBpbihRU3RyaW5nIHBpbik7CisgICAgc3RhdGljIFFWYXJp
YW50TWFwIHJlYWRMb2NhbChjb25zdCBRU3RyaW5nJiBzeXNSb290ID0gIi9zeXMiKTsKK3NpZ25h
bHM6CisgICAgdm9pZCBsb2NhbENoYW5nZWQoKTsKKyAgICB2b2lkIHN0YXRzQ2hhbmdlZCgpOwor
ICAgIHZvaWQgY29uZmlnQ2hhbmdlZCgpOworcHJpdmF0ZToKKyAgICB2b2lkIHJlZnJlc2hMb2Nh
bCgpOworICAgIHZvaWQgZmFpbChRU3RyaW5nIG1lc3NhZ2UpOworICAgIHZvaWQgY2FuY2VsKCk7
CisgICAgUVN0cmluZyBjb25maWdGaWxlKCkgY29uc3Q7CisgICAgUVN0cmluZyBtX2hvc3QsIG1f
ZW5kcG9pbnQsIG1fdG9rZW4sIG1fcGluLCBtX3N0YXR1cyA9ICJDaG9vc2UgYSBob3N0IHRvIHZp
ZXcgaGFyZHdhcmUgc3RhdHMiOworICAgIFFWYXJpYW50TWFwIG1fbG9jYWwsIG1fc3RhdHM7Cisg
ICAgUVRpbWVyIG1fbG9jYWxUaW1lciwgbV9zdGF0c1RpbWVyOworICAgIFFQcm9jZXNzIG1fd2lm
aTsKKyAgICBRTmV0d29ya0FjY2Vzc01hbmFnZXIgbV9uZXR3b3JrOworICAgIFFQb2ludGVyPFFO
ZXR3b3JrUmVwbHk+IG1fcmVwbHk7CisgICAgYm9vbCBtX3Zpc2libGUgPSBmYWxzZTsKK307CmRp
ZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmNwcCBiL2FwcC9tb29u
bGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAw
MDAwMDAwLi5hNjNkNTJkYwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9lY2xp
cHNlcHJvZmlsZXMuY3BwCkBAIC0wLDAgKzEsNDEgQEAKKyNpbmNsdWRlICJlY2xpcHNlcHJvZmls
ZXMuaCIKKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVkZSA8UUNvcmVBcHBs
aWNhdGlvbj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorUVN0cmluZyBFY2xpcHNlUHJvZmlsZXM6
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
aXN0ZXJFY2xpcHNlUHJvZmlsZXMpCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBz
ZXByb2ZpbGVzLmggYi9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmgKbmV3IGZpbGUg
bW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLmQzOTgzODdhCi0tLSAvZGV2L251bGwKKysrIGIv
YXBwL21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5oCkBAIC0wLDAgKzEsMjcgQEAKKyNwcmFn
bWEgb25jZQorI2luY2x1ZGUgPFFPYmplY3Q+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CisjaW5j
bHVkZSA8UVNldHRpbmdzPgorY2xhc3MgRWNsaXBzZVByb2ZpbGVzIDogcHVibGljIFFPYmplY3Qg
eworICAgIFFfT0JKRUNUCisgICAgUV9QUk9QRVJUWShpbnQgdGV4dFNjYWxlIFJFQUQgdGV4dFNj
YWxlIFdSSVRFIHNldFRleHRTY2FsZSBOT1RJRlkgYXBwZWFyYW5jZUNoYW5nZWQpCisgICAgUV9Q
Uk9QRVJUWShib29sIHJlZHVjZWRNb3Rpb24gUkVBRCByZWR1Y2VkTW90aW9uIFdSSVRFIHNldFJl
ZHVjZWRNb3Rpb24gTk9USUZZIGFwcGVhcmFuY2VDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoYm9v
bCBoaWdoQ29udHJhc3QgUkVBRCBoaWdoQ29udHJhc3QgV1JJVEUgc2V0SGlnaENvbnRyYXN0IE5P
VElGWSBhcHBlYXJhbmNlQ2hhbmdlZCkKK3B1YmxpYzoKKyAgICBleHBsaWNpdCBFY2xpcHNlUHJv
ZmlsZXMoUU9iamVjdCogcGFyZW50ID0gbnVsbHB0cikgOiBRT2JqZWN0KHBhcmVudCkge30KKyAg
ICBpbnQgdGV4dFNjYWxlKCkgY29uc3QgeyByZXR1cm4gcUJvdW5kKDEwMCxRU2V0dGluZ3MoKS52
YWx1ZSgiZWNsaXBzZS90ZXh0U2NhbGUiLDEwMCkudG9JbnQoKSwxMjUpOyB9CisgICAgYm9vbCBy
ZWR1Y2VkTW90aW9uKCkgY29uc3QgeyByZXR1cm4gUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2Uv
cmVkdWNlZE1vdGlvbiIsZmFsc2UpLnRvQm9vbCgpOyB9CisgICAgYm9vbCBoaWdoQ29udHJhc3Qo
KSBjb25zdCB7IHJldHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9oaWdoQ29udHJhc3Qi
LGZhbHNlKS50b0Jvb2woKTsgfQorICAgIHZvaWQgc2V0VGV4dFNjYWxlKGludCB2YWx1ZSkgeyBR
U2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS90ZXh0U2NhbGUiLHFCb3VuZCgxMDAsdmFsdWUs
MTI1KSk7IGVtaXQgYXBwZWFyYW5jZUNoYW5nZWQoKTsgfQorICAgIHZvaWQgc2V0UmVkdWNlZE1v
dGlvbihib29sIHZhbHVlKSB7IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlL3JlZHVjZWRN
b3Rpb24iLHZhbHVlKTsgZW1pdCBhcHBlYXJhbmNlQ2hhbmdlZCgpOyB9CisgICAgdm9pZCBzZXRI
aWdoQ29udHJhc3QoYm9vbCB2YWx1ZSkgeyBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS9o
aWdoQ29udHJhc3QiLHZhbHVlKTsgZW1pdCBhcHBlYXJhbmNlQ2hhbmdlZCgpOyB9CisgICAgUV9J
TlZPS0FCTEUgYm9vbCBzYXZlKFFTdHJpbmcgaG9zdCwgUVN0cmluZyBuYW1lLCBRVmFyaWFudE1h
cCB2YWx1ZXMpOworICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50TWFwIGxvYWQoUVN0cmluZyBob3N0
LCBRU3RyaW5nIG5hbWUpOworICAgIFFfSU5WT0tBQkxFIGJvb2wgcmVtb3ZlKFFTdHJpbmcgaG9z
dCwgUVN0cmluZyBuYW1lLCBib29sIGNvbmZpcm1lZCk7CisgICAgUV9JTlZPS0FCTEUgUVN0cmlu
Z0xpc3QgbmFtZXMoUVN0cmluZyBob3N0KTsKKyAgICBzdGF0aWMgYm9vbCB2YWxpZChjb25zdCBR
VmFyaWFudE1hcCYgdmFsdWVzKTsKK3NpZ25hbHM6CisgICAgdm9pZCBhcHBlYXJhbmNlQ2hhbmdl
ZCgpOworcHJpdmF0ZToKKyAgICBzdGF0aWMgUVN0cmluZyBrZXkoUVN0cmluZyBob3N0LCBRU3Ry
aW5nIG5hbWUpOworfTsKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9tYW5hZ2VkdXBkYXRl
cy5jcHAgYi9hcHAvbW9vbmxpZ2h0b3MvbWFuYWdlZHVwZGF0ZXMuY3BwCm5ldyBmaWxlIG1vZGUg
MTAwNjQ0CmluZGV4IDAwMDAwMDAwLi43MDFkZjUyMQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9t
b29ubGlnaHRvcy9tYW5hZ2VkdXBkYXRlcy5jcHAKQEAgLTAsMCArMSwxMzIgQEAKKy8vIE1vb25s
aWdodC1PUyBvd25zIHRoaXMgY3VzdG9taXplZCBuYXRpdmUgY2xpZW50LiBObyBmZWVkIHJlcXVl
c3RzLCBhc3NldAorLy8gZG93bmxvYWRzLCBzd2FwcyBvciByZWxhdW5jaGVzIGFyZSBjb21waWxl
ZCBpbnRvIHRoaXMgdXBkYXRlIGltcGxlbWVudGF0aW9uLgorI2luY2x1ZGUgIi4uL2JhY2tlbmQv
YXV0b3VwZGF0ZWNoZWNrZXIuaCIKKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1
ZGUgPFFKc29uT2JqZWN0PgorCitzdGF0aWMgUVN0cmluZyBzdHJpcEJ1aWxkTWV0YWRhdGEoY29u
c3QgUVN0cmluZyYgdmVyc2lvbikKK3sKKyAgICBpbnQgcGx1c0lkeCA9IHZlcnNpb24uaW5kZXhP
ZignKycpOworICAgIHJldHVybiBwbHVzSWR4ID49IDAgPyB2ZXJzaW9uLmxlZnQocGx1c0lkeCkg
OiB2ZXJzaW9uOworfQorCitzdGF0aWMgYm9vbCBpc051bWVyaWNJZGVudGlmaWVyKGNvbnN0IFFT
dHJpbmcmIHMpCit7CisgICAgaWYgKHMuaXNFbXB0eSgpKSB7CisgICAgICAgIHJldHVybiBmYWxz
ZTsKKyAgICB9CisgICAgZm9yIChjb25zdCBRQ2hhciYgYyA6IHMpIHsKKyAgICAgICAgaWYgKCFj
LmlzRGlnaXQoKSkgeworICAgICAgICAgICAgcmV0dXJuIGZhbHNlOworICAgICAgICB9CisgICAg
fQorICAgIHJldHVybiB0cnVlOworfQorCitpbnQgQXV0b1VwZGF0ZUNoZWNrZXI6OmNvbXBhcmVT
ZW1hbnRpY1ZlcnNpb25zKGNvbnN0IFFTdHJpbmcmIHYxLCBjb25zdCBRU3RyaW5nJiB2MikKK3sK
KyAgICBRU3RyaW5nIHMxID0gc3RyaXBCdWlsZE1ldGFkYXRhKHYxKTsKKyAgICBRU3RyaW5nIHMy
ID0gc3RyaXBCdWlsZE1ldGFkYXRhKHYyKTsKKworICAgIGludCBkYXNoMSA9IHMxLmluZGV4T2Yo
Jy0nKTsKKyAgICBpbnQgZGFzaDIgPSBzMi5pbmRleE9mKCctJyk7CisgICAgUVN0cmluZyBiYXNl
MSA9IGRhc2gxID49IDAgPyBzMS5sZWZ0KGRhc2gxKSA6IHMxOworICAgIFFTdHJpbmcgYmFzZTIg
PSBkYXNoMiA+PSAwID8gczIubGVmdChkYXNoMikgOiBzMjsKKyAgICBRU3RyaW5nIHByZTEgPSBk
YXNoMSA+PSAwID8gczEubWlkKGRhc2gxICsgMSkgOiBRU3RyaW5nKCk7CisgICAgUVN0cmluZyBw
cmUyID0gZGFzaDIgPj0gMCA/IHMyLm1pZChkYXNoMiArIDEpIDogUVN0cmluZygpOworCisgICAg
Ly8gTnVtZXJpYyBiYXNlIHZlcnNpb25zIGNvbXBhcmUgZmlyc3QgKDAuNC4wLWJldGEuMDAxID4g
MC4zLjApCisgICAgY29uc3QgUVN0cmluZ0xpc3QgYmFzZVBhcnRzMSA9IGJhc2UxLnNwbGl0KCcu
Jyk7CisgICAgY29uc3QgUVN0cmluZ0xpc3QgYmFzZVBhcnRzMiA9IGJhc2UyLnNwbGl0KCcuJyk7
CisgICAgZm9yIChpbnQgaSA9IDA7IGkgPCBxTWF4KGJhc2VQYXJ0czEuY291bnQoKSwgYmFzZVBh
cnRzMi5jb3VudCgpKTsgaSsrKSB7CisgICAgICAgIHFsb25nbG9uZyBiMSA9IGkgPCBiYXNlUGFy
dHMxLmNvdW50KCkgPyBiYXNlUGFydHMxW2ldLnRvTG9uZ0xvbmcoKSA6IDA7CisgICAgICAgIHFs
b25nbG9uZyBiMiA9IGkgPCBiYXNlUGFydHMyLmNvdW50KCkgPyBiYXNlUGFydHMyW2ldLnRvTG9u
Z0xvbmcoKSA6IDA7CisgICAgICAgIGlmIChiMSAhPSBiMikgeworICAgICAgICAgICAgcmV0dXJu
IGIxIDwgYjIgPyAtMSA6IDE7CisgICAgICAgIH0KKyAgICB9CisKKyAgICAvLyBFcXVhbCBiYXNl
OiBhIHJlbGVhc2Ugd2l0aCBubyBwcmVyZWxlYXNlIHN1ZmZpeCBvdXRyYW5rcyBhbnkgcHJlcmVs
ZWFzZQorICAgIGlmIChwcmUxLmlzRW1wdHkoKSAhPSBwcmUyLmlzRW1wdHkoKSkgeworICAgICAg
ICByZXR1cm4gcHJlMS5pc0VtcHR5KCkgPyAxIDogLTE7CisgICAgfQorICAgIGlmIChwcmUxLmlz
RW1wdHkoKSkgeworICAgICAgICByZXR1cm4gMDsKKyAgICB9CisKKyAgICAvLyBUd28gcHJlcmVs
ZWFzZXM6IGNvbXBhcmUgZG90LXNlcGFyYXRlZCBpZGVudGlmaWVycyBsZWZ0IHRvIHJpZ2h0Lgor
ICAgIC8vIE51bWVyaWMgaWRlbnRpZmllcnMgY29tcGFyZSBudW1lcmljYWxseSAobGVhZGluZyB6
ZXJvcyB0b2xlcmF0ZWQg4oCUIG91cgorICAgIC8vIENJIHplcm8tcGFkcyBjb3VudGVycyksIGFs
cGhhbnVtZXJpYyBvbmVzIGxleGljYWxseSBpbiBBU0NJSSBvcmRlciwgYW5kCisgICAgLy8gbnVt
ZXJpYyBhbHdheXMgcmFua3MgYmVsb3cgYWxwaGFudW1lcmljLiBUaGlzIGlzIHdoYXQgb3JkZXJz
CisgICAgLy8gImFscGhhIiA8ICJiZXRhIiA8ICJyYyIgYXQgYW4gZXF1YWwgYmFzZSDigJQgdGhl
IHByb3BlcnR5IHRoZSBwcmV2aW91cworICAgIC8vIGltcGxlbWVudGF0aW9uIGxhY2tlZCAoaXQg
c2tpcHBlZCB0aGUgd29yZHMgYW5kIGNvbXBhcmVkIG9ubHkgbnVtYmVycywKKyAgICAvLyBzbyAw
LjMuMC1iZXRhLjAwOCB3cm9uZ2x5IG91dHJhbmtlZCAwLjMuMC1yYy4wMDIpLgorICAgIGNvbnN0
IFFTdHJpbmdMaXN0IGlkczEgPSBwcmUxLnNwbGl0KCcuJyk7CisgICAgY29uc3QgUVN0cmluZ0xp
c3QgaWRzMiA9IHByZTIuc3BsaXQoJy4nKTsKKyAgICBmb3IgKGludCBpID0gMDsgaSA8IHFNYXgo
aWRzMS5jb3VudCgpLCBpZHMyLmNvdW50KCkpOyBpKyspIHsKKyAgICAgICAgaWYgKGkgPj0gaWRz
MS5jb3VudCgpKSB7CisgICAgICAgICAgICAvLyBFcXVhbCBwcmVmaXgsIGZld2VyIGZpZWxkcyA9
IGxvd2VyIHByZWNlZGVuY2UgKMKnMTEuNC40KQorICAgICAgICAgICAgcmV0dXJuIC0xOworICAg
ICAgICB9CisgICAgICAgIGlmIChpID49IGlkczIuY291bnQoKSkgeworICAgICAgICAgICAgcmV0
dXJuIDE7CisgICAgICAgIH0KKyAgICAgICAgYm9vbCBudW0xID0gaXNOdW1lcmljSWRlbnRpZmll
cihpZHMxW2ldKTsKKyAgICAgICAgYm9vbCBudW0yID0gaXNOdW1lcmljSWRlbnRpZmllcihpZHMy
W2ldKTsKKyAgICAgICAgaWYgKG51bTEgJiYgbnVtMikgeworICAgICAgICAgICAgcWxvbmdsb25n
IHAxID0gaWRzMVtpXS50b0xvbmdMb25nKCk7CisgICAgICAgICAgICBxbG9uZ2xvbmcgcDIgPSBp
ZHMyW2ldLnRvTG9uZ0xvbmcoKTsKKyAgICAgICAgICAgIGlmIChwMSAhPSBwMikgeworICAgICAg
ICAgICAgICAgIHJldHVybiBwMSA8IHAyID8gLTEgOiAxOworICAgICAgICAgICAgfQorICAgICAg
ICB9CisgICAgICAgIGVsc2UgaWYgKG51bTEgIT0gbnVtMikgeworICAgICAgICAgICAgLy8gTnVt
ZXJpYyBpZGVudGlmaWVycyByYW5rIGJlbG93IGFscGhhbnVtZXJpYyBvbmVzICjCpzExLjQuMykK
KyAgICAgICAgICAgIHJldHVybiBudW0xID8gLTEgOiAxOworICAgICAgICB9CisgICAgICAgIGVs
c2UgeworICAgICAgICAgICAgaW50IGNtcCA9IFFTdHJpbmc6OmNvbXBhcmUoaWRzMVtpXSwgaWRz
MltpXSk7CisgICAgICAgICAgICBpZiAoY21wICE9IDApIHsKKyAgICAgICAgICAgICAgICByZXR1
cm4gY21wIDwgMCA/IC0xIDogMTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgIH0KKyAg
ICByZXR1cm4gMDsKK30KKworQXV0b1VwZGF0ZUNoZWNrZXI6OkF1dG9VcGRhdGVDaGVja2VyKFFP
YmplY3QqIHBhcmVudCkgOgorICAgIFFPYmplY3QocGFyZW50KSwgbV9DaGVja0luRmxpZ2h0KGZh
bHNlKSwgbV9DaGVja0lzTWFudWFsKGZhbHNlKSwKKyAgICBtX1VwZGF0ZUF2YWlsYWJsZShmYWxz
ZSksIG1fT2ZmZXJBdmFpbGFibGUoZmFsc2UpLCBtX0luc3RhbGxpbmcoZmFsc2UpCit7CisgICAg
Y2xlYXJPZmZlcigpOworICAgIHNldFN0YXR1cyh0cigiJTEuIFVwZGF0ZXMgYXJlIG1hbmFnZWQg
YnkgTW9vbmxpZ2h0LU9TLiBHZXQgdGhlIG1hdGNoaW5nIE9TIGltYWdlIGZyb20gJTI7IHVwc3Ry
ZWFtIFZpYmVtaXMgdXBkYXRlcyBhcmUgZGlzYWJsZWQuIikuYXJnKGN1cnJlbnRWZXJzaW9uKCks
IG1fUmVsZWFzZVVybCkpOworfQorUVN0cmluZyBBdXRvVXBkYXRlQ2hlY2tlcjo6Y3VycmVudFZl
cnNpb24oKSBjb25zdAoreworICAgIHJldHVybiB0cigiRWNsaXBzZSAlMSDCtyBNb29ubGlnaHQt
T1MgY3VzdG9taXplZCIpLmFyZyhRQ29yZUFwcGxpY2F0aW9uOjphcHBsaWNhdGlvblZlcnNpb24o
KSk7Cit9Cit2b2lkIEF1dG9VcGRhdGVDaGVja2VyOjpjbGVhck9mZmVyKCkKK3sKKyAgICBtX1Vw
ZGF0ZUF2YWlsYWJsZSA9IGZhbHNlOyBtX09mZmVyQXZhaWxhYmxlID0gZmFsc2U7CisgICAgbV9P
ZmZlclZlcnNpb24uY2xlYXIoKTsgbV9Bc3NldFVybC5jbGVhcigpOyBtX09mZmVyVGllciA9IC0x
OworICAgIG1fUmVsZWFzZVVybCA9IFFTdHJpbmdMaXRlcmFsKCJodHRwczovL2dpdGh1Yi5jb20v
dGgzZDNjazNyL01vb25saWdodC1PUy9yZWxlYXNlcyIpOworfQordm9pZCBBdXRvVXBkYXRlQ2hl
Y2tlcjo6c2V0U3RhdHVzKGNvbnN0IFFTdHJpbmcmIG1lc3NhZ2UpCit7CisgICAgaWYgKG1fU3Rh
dHVzTWVzc2FnZSAhPSBtZXNzYWdlKSB7IG1fU3RhdHVzTWVzc2FnZSA9IG1lc3NhZ2U7IGVtaXQg
c3RhdGVDaGFuZ2VkKCk7IH0KK30KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6OnN0YXJ0KCkgeyAv
KiBObyB0aW1lciBhbmQgbm8gYmFja2dyb3VuZCB1cGRhdGUgcmVxdWVzdHMuICovIH0KK2Jvb2wg
QXV0b1VwZGF0ZUNoZWNrZXI6OmNhbkluc3RhbGxVcGRhdGVzKCkgY29uc3QgeyByZXR1cm4gZmFs
c2U7IH0KK2Jvb2wgQXV0b1VwZGF0ZUNoZWNrZXI6OmNhbkluc3RhbGwoKSBjb25zdCB7IHJldHVy
biBmYWxzZTsgfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6Y2hhbm5lbENoYW5nZWQoKSB7IGNo
ZWNrTm93KCk7IH0KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6OmNoZWNrTm93KCkKK3sKKyAgICBj
bGVhck9mZmVyKCk7CisgICAgc2V0U3RhdHVzKHRyKCJVcGRhdGVzIGFyZSBtYW5hZ2VkIGJ5IE1v
b25saWdodC1PUy4gRG93bmxvYWQgdGhlIG1hdGNoaW5nIE9TIGltYWdlIGZyb20gJTEuIFRoaXMg
Y2xpZW50IG5ldmVyIGluc3RhbGxzIHVwc3RyZWFtIFZpYmVtaXMgcmVsZWFzZXMuIikuYXJnKG1f
UmVsZWFzZVVybCkpOworICAgIGVtaXQgc3RhdGVDaGFuZ2VkKCk7IGVtaXQgY2hlY2tDb21wbGV0
ZWQodHJ1ZSwgZmFsc2UpOworfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6aW5zdGFsbCgpCit7
CisgICAgY2hlY2tOb3coKTsKKyAgICBlbWl0IGluc3RhbGxGYWlsZWQodHIoIlN0YW5kYWxvbmUg
VmliZW1pcyBpbnN0YWxsYXRpb24gaXMgZGlzYWJsZWQgaW4gTW9vbmxpZ2h0LU9TLiIpLCBtX1Jl
bGVhc2VVcmwpOworfQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3N5c3RlbWNvbnRyb2xz
LmNwcCBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAKbmV3IGZpbGUgbW9kZSAx
MDA2NDQKaW5kZXggMDAwMDAwMDAuLjc3ZWM0YzgyCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21v
b25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmNwcApAQCAtMCwwICsxLDgzIEBACisjaW5jbHVkZSAi
c3lzdGVtY29udHJvbHMuaCIKKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUg
PFFKc29uRG9jdW1lbnQ+CisjaW5jbHVkZSA8UUpzb25PYmplY3Q+CisjaW5jbHVkZSA8UUpzb25B
cnJheT4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFGaWxlSW5mbz4KK1N5c3Rl
bUNvbnRyb2xzOjpTeXN0ZW1Db250cm9scyhRT2JqZWN0KiBwYXJlbnQpIDogUU9iamVjdChwYXJl
bnQpIHsKKyAgICBtX3RpbWVvdXQuc2V0U2luZ2xlU2hvdCh0cnVlKTsKKyAgICBjb25uZWN0KCZt
X3RpbWVvdXQsICZRVGltZXI6OnRpbWVvdXQsIHRoaXMsIFt0aGlzXSB7IGZhaWwodHIoIk9wZXJh
dGlvbiB0aW1lZCBvdXQuIFJldHJ5IG9yIHVzZSB0aGUgZGlhZ25vc3RpYyBzaGVsbC4iKSk7IH0p
OworICAgIGNvbm5lY3QoJm1fcHJvY2VzcywgJlFQcm9jZXNzOjpzdGFydGVkLCB0aGlzLCBbdGhp
c10geyByZXF1ZXN0KG1fbW9kZSArICItbGlzdCIpOyB9KTsKKyAgICBjb25uZWN0KCZtX3Byb2Nl
c3MsICZRUHJvY2Vzczo6cmVhZHlSZWFkU3RhbmRhcmRFcnJvciwgdGhpcywgW3RoaXNdIHsgbV9w
cm9jZXNzLnJlYWRBbGxTdGFuZGFyZEVycm9yKCk7IH0pOworICAgIGNvbm5lY3QoJm1fcHJvY2Vz
cywgJlFQcm9jZXNzOjpyZWFkeVJlYWRTdGFuZGFyZE91dHB1dCwgdGhpcywgW3RoaXNdIHsKKyAg
ICAgICAgbV9idWZmZXIgKz0gbV9wcm9jZXNzLnJlYWRBbGxTdGFuZGFyZE91dHB1dCgpOworICAg
ICAgICBpZiAobV9idWZmZXIuc2l6ZSgpID4gNjU1MzYpIHsgZmFpbCh0cigiSW52YWxpZCBzeXN0
ZW0gcmVzcG9uc2UuIikpOyByZXR1cm47IH0KKyAgICAgICAgd2hpbGUgKG1fYnVmZmVyLmNvbnRh
aW5zKCdcbicpKSB7CisgICAgICAgICAgICBpbnQgZW5kID0gbV9idWZmZXIuaW5kZXhPZignXG4n
KTsKKyAgICAgICAgICAgIFFKc29uUGFyc2VFcnJvciBlcnJvcjsKKyAgICAgICAgICAgIGF1dG8g
ZG9jdW1lbnQgPSBRSnNvbkRvY3VtZW50Ojpmcm9tSnNvbihtX2J1ZmZlci5sZWZ0KGVuZCksICZl
cnJvcik7CisgICAgICAgICAgICBtX2J1ZmZlci5yZW1vdmUoMCwgZW5kICsgMSk7CisgICAgICAg
ICAgICBpZiAoZXJyb3IuZXJyb3IgIT0gUUpzb25QYXJzZUVycm9yOjpOb0Vycm9yIHx8ICFkb2N1
bWVudC5pc09iamVjdCgpKSB7IGZhaWwodHIoIkludmFsaWQgc3lzdGVtIHJlc3BvbnNlLiIpKTsg
cmV0dXJuOyB9CisgICAgICAgICAgICBhdXRvIHZhbHVlID0gZG9jdW1lbnQub2JqZWN0KCk7Cisg
ICAgICAgICAgICBpZiAodmFsdWUuY29udGFpbnMoInByb21wdCIpKSB7CisgICAgICAgICAgICAg
ICAgbV9wcm9tcHQgPSB2YWx1ZS52YWx1ZSgicHJvbXB0IikudG9TdHJpbmcoKS5sZWZ0KDEwMjQp
OworICAgICAgICAgICAgICAgIG1fdGltZW91dC5zdGFydCgxMjAwMDApOworICAgICAgICAgICAg
fQorICAgICAgICAgICAgaWYgKHZhbHVlLnZhbHVlKCJkb25lIikudG9Cb29sKCkpIHsKKyAgICAg
ICAgICAgICAgICBtX3RpbWVvdXQuc3RvcCgpOyBtX2J1c3kgPSBmYWxzZTsgbV9wcm9tcHQuY2xl
YXIoKTsKKyAgICAgICAgICAgICAgICBpZiAodmFsdWUuY29udGFpbnMoIml0ZW1zIikpIHsKKyAg
ICAgICAgICAgICAgICAgICAgYXV0byBlbnRyaWVzID0gdmFsdWUudmFsdWUoIml0ZW1zIikudG9B
cnJheSgpOworICAgICAgICAgICAgICAgICAgICBpZiAoZW50cmllcy5zaXplKCkgPiA2NCkgeyBm
YWlsKHRyKCJJbnZhbGlkIGRldmljZSBsaXN0LiIpKTsgcmV0dXJuOyB9CisgICAgICAgICAgICAg
ICAgICAgIG1faXRlbXMgPSBlbnRyaWVzLnRvVmFyaWFudExpc3QoKTsKKyAgICAgICAgICAgICAg
ICB9CisgICAgICAgICAgICAgICAgaWYgKHZhbHVlLnZhbHVlKCJzdGF0ZSIpLmlzT2JqZWN0KCkp
IG1fc3RhdGUgPSB2YWx1ZS52YWx1ZSgic3RhdGUiKS50b09iamVjdCgpLnRvVmFyaWFudE1hcCgp
OworICAgICAgICAgICAgICAgIG1fc3RhdHVzID0gdmFsdWUuY29udGFpbnMoImVycm9yIikgPyB2
YWx1ZS52YWx1ZSgiZXJyb3IiKS50b1N0cmluZygpLmxlZnQoMTAyNCkgOiB2YWx1ZS52YWx1ZSgi
c3RhdHVzIikudG9TdHJpbmcoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGVtaXQgY2hh
bmdlZCgpOworICAgICAgICB9CisgICAgfSk7CisgICAgY29ubmVjdCgmbV9wcm9jZXNzLCAmUVBy
b2Nlc3M6OmVycm9yT2NjdXJyZWQsIHRoaXMsIFt0aGlzXShRUHJvY2Vzczo6UHJvY2Vzc0Vycm9y
KSB7CisgICAgICAgIGlmICghbV9tb2RlLmlzRW1wdHkoKSkgZmFpbCh0cigiU3lzdGVtIGNvbnRy
b2xzIGFyZSB1bmF2YWlsYWJsZS4gVXNlIHRoZSBkaWFnbm9zdGljIHNoZWxsLiIpKTsKKyAgICB9
KTsKKyAgICBjb25uZWN0KCZtX3Byb2Nlc3MsIFFPdmVybG9hZDxpbnQsUVByb2Nlc3M6OkV4aXRT
dGF0dXM+OjpvZigmUVByb2Nlc3M6OmZpbmlzaGVkKSwgdGhpcywgW3RoaXNdKGludCwgUVByb2Nl
c3M6OkV4aXRTdGF0dXMpIHsKKyAgICAgICAgaWYgKCFtX21vZGUuaXNFbXB0eSgpKSB7IG1fdGlt
ZW91dC5zdG9wKCk7IG1fYnVzeSA9IGZhbHNlOyBtX3Byb21wdC5jbGVhcigpOyBtX3N0YXR1cyA9
IHRyKCJTeXN0ZW0gaGVscGVyIHN0b3BwZWQuIENsb3NlIGFuZCByZW9wZW4gdGhpcyBwYW5lbC4i
KTsgZW1pdCBjaGFuZ2VkKCk7IH0KKyAgICB9KTsKK30KK1N5c3RlbUNvbnRyb2xzOjp+U3lzdGVt
Q29udHJvbHMoKSB7IGNsb3NlKCk7IGlmICghbV9wcm9jZXNzLndhaXRGb3JGaW5pc2hlZCg1MDAp
KSB7IG1fcHJvY2Vzcy5raWxsKCk7IG1fcHJvY2Vzcy53YWl0Rm9yRmluaXNoZWQoNTAwKTsgfSB9
Cit2b2lkIFN5c3RlbUNvbnRyb2xzOjpzZW5kKGNvbnN0IFFKc29uT2JqZWN0JiB2YWx1ZSkgeyBt
X3Byb2Nlc3Mud3JpdGUoUUpzb25Eb2N1bWVudCh2YWx1ZSkudG9Kc29uKFFKc29uRG9jdW1lbnQ6
OkNvbXBhY3QpICsgJ1xuJyk7IH0KK3ZvaWQgU3lzdGVtQ29udHJvbHM6Om9wZW4oUVN0cmluZyBt
b2RlKSB7CisgICAgaWYgKG1vZGUgIT0gIndpZmkiICYmIG1vZGUgIT0gImJ0IiAmJiBtb2RlICE9
ICJjZW50ZXIiKSByZXR1cm47CisgICAgY2xvc2UoKTsKKyAgICBpZiAobV9wcm9jZXNzLnN0YXRl
KCkgIT0gUVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIHsgbV9wcm9jZXNzLmtpbGwoKTsgbV9wcm9jZXNz
LndhaXRGb3JGaW5pc2hlZCg1MDApOyB9CisgICAgbV9tb2RlID0gbW9kZTsgbV9pdGVtcy5jbGVh
cigpOyBtX3N0YXRlLmNsZWFyKCk7IG1fYnVmZmVyLmNsZWFyKCk7IG1fc3RhdHVzID0gdHIoIkxv
YWRpbmfigKYiKTsgZW1pdCBjaGFuZ2VkKCk7CisgICAgUVN0cmluZyBoZWxwZXIgPSAiL3Vzci9s
b2NhbC9saWJleGVjL21vb25saWdodC1vcy9zeXN0ZW0tY29udHJvbHMucHkiOworI2lmZGVmIE1P
T05MSUdIVF9DT05UUk9MU19URVNUCisgICAgaGVscGVyID0gcUVudmlyb25tZW50VmFyaWFibGUo
Ik1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIiwgaGVscGVyKTsKKyNlbmRpZgorICAgIG1fcHJv
Y2Vzcy5zdGFydCgicHl0aG9uMyIsIHtoZWxwZXJ9KTsKK30KK3ZvaWQgU3lzdGVtQ29udHJvbHM6
OnJlcXVlc3QoUVN0cmluZyBhY3Rpb24sIFFTdHJpbmcgaWQsIGJvb2wgY29uZmlybSkgeworICAg
IGlmIChtX2J1c3kgfHwgbV9wcm9jZXNzLnN0YXRlKCkgIT0gUVByb2Nlc3M6OlJ1bm5pbmcgfHwg
IWFjdGlvbi5zdGFydHNXaXRoKG1fbW9kZSArICItIikpIHJldHVybjsKKyAgICBjb25zdCBRU3Ry
aW5nTGlzdCBhbGxvd2VkID0geyJ3aWZpLWxpc3QiLCAid2lmaS1zY2FuIiwgIndpZmktY29ubmVj
dCIsICJ3aWZpLWRpc2Nvbm5lY3QiLCAiYnQtbGlzdCIsICJidC1zY2FuIiwgImJ0LWNvbm5lY3Qi
LCAiYnQtZGlzY29ubmVjdCIsICJidC1mb3JnZXQiLCAiY2VudGVyLWxpc3QiLCAiY2VudGVyLXZv
bHVtZSIsICJjZW50ZXItbXV0ZSIsICJjZW50ZXItb3V0cHV0IiwgImNlbnRlci1zY3JlZW4iLCAi
Y2VudGVyLWtleWJvYXJkIiwgImNlbnRlci1yZWJvb3QiLCAiY2VudGVyLXBvd2Vyb2ZmIiwgImNl
bnRlci1zdXNwZW5kIiwgImNlbnRlci1yZXBvcnQifTsKKyAgICBpZiAoIWFsbG93ZWQuY29udGFp
bnMoYWN0aW9uKSkgcmV0dXJuOworICAgIG1fYnVzeSA9IHRydWU7IG1fcHJvbXB0LmNsZWFyKCk7
IG1fc3RhdHVzID0gdHIoIldvcmtpbmfigKYiKTsgbV90aW1lb3V0LnN0YXJ0KDEyMDAwMCk7Cisg
ICAgc2VuZCh7eyJhY3Rpb24iLCBhY3Rpb259LCB7ImlkIiwgaWR9LCB7ImNvbmZpcm0iLCBjb25m
aXJtfX0pOyBlbWl0IGNoYW5nZWQoKTsKK30KK3ZvaWQgU3lzdGVtQ29udHJvbHM6OmFuc3dlcihR
U3RyaW5nIHZhbHVlKSB7CisgICAgaWYgKCFtX2J1c3kgfHwgbV9wcm9tcHQuaXNFbXB0eSgpIHx8
IHZhbHVlLnNpemUoKSA+IDQwOTYgfHwgdmFsdWUuY29udGFpbnMoJ1xuJykgfHwgdmFsdWUuY29u
dGFpbnMoJ1xyJykgfHwgdmFsdWUuY29udGFpbnMoUUNoYXIoMCkpKSByZXR1cm47CisgICAgc2Vu
ZCh7eyJhY3Rpb24iLCAiYW5zd2VyIn0sIHsidmFsdWUiLCB2YWx1ZX19KTsgbV9wcm9tcHQuY2xl
YXIoKTsgbV90aW1lb3V0LnN0YXJ0KDEyMDAwMCk7IGVtaXQgY2hhbmdlZCgpOworfQordm9pZCBT
eXN0ZW1Db250cm9sczo6Y2xvc2UoKSB7CisgICAgbV9tb2RlLmNsZWFyKCk7IG1fdGltZW91dC5z
dG9wKCk7IG1fYnVzeSA9IGZhbHNlOyBtX3Byb21wdC5jbGVhcigpOyBtX2J1ZmZlci5jbGVhcigp
OworICAgIGlmIChtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgewor
ICAgICAgICBtX3Byb2Nlc3MudGVybWluYXRlKCk7CisgICAgICAgIFFUaW1lcjo6c2luZ2xlU2hv
dCg0MDAwLCB0aGlzLCBbdGhpc10geyBpZiAobV9tb2RlLmlzRW1wdHkoKSAmJiBtX3Byb2Nlc3Mu
c3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgbV9wcm9jZXNzLmtpbGwoKTsgfSk7Cisg
ICAgfQorICAgIGVtaXQgY2hhbmdlZCgpOworfQordm9pZCBTeXN0ZW1Db250cm9sczo6ZmFpbChR
U3RyaW5nIG1lc3NhZ2UpIHsgY2xvc2UoKTsgbV9zdGF0dXMgPSBtZXNzYWdlOyBlbWl0IGNoYW5n
ZWQoKTsgfQorc3RhdGljIHZvaWQgcmVnaXN0ZXJTeXN0ZW1Db250cm9scygpIHsKKyAgICBxbWxS
ZWdpc3RlclNpbmdsZXRvblR5cGU8U3lzdGVtQ29udHJvbHM+KCJTeXN0ZW1Db250cm9scyIsIDEs
IDAsICJTeXN0ZW1Db250cm9scyIsIFtdKFFRbWxFbmdpbmUqLCBRSlNFbmdpbmUqKSAtPiBRT2Jq
ZWN0KiB7IHJldHVybiBuZXcgU3lzdGVtQ29udHJvbHMoKTsgfSk7Cit9CitRX0NPUkVBUFBfU1RB
UlRVUF9GVU5DVElPTihyZWdpc3RlclN5c3RlbUNvbnRyb2xzKQpkaWZmIC0tZ2l0IGEvYXBwL21v
b25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmggYi9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJv
bHMuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uMThlOWRlYjIKLS0tIC9k
ZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuaApAQCAtMCwwICsx
LDM5IEBACisjcHJhZ21hIG9uY2UKKyNpbmNsdWRlIDxRT2JqZWN0PgorI2luY2x1ZGUgPFFKc29u
T2JqZWN0PgorI2luY2x1ZGUgPFFQcm9jZXNzPgorI2luY2x1ZGUgPFFUaW1lcj4KKyNpbmNsdWRl
IDxRVmFyaWFudExpc3Q+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CitjbGFzcyBTeXN0ZW1Db250
cm9scyA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorICAgIFFfUFJPUEVSVFkoUVZh
cmlhbnRNYXAgc3RhdGUgUkVBRCBzdGF0ZSBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZ
KFFWYXJpYW50TGlzdCBpdGVtcyBSRUFEIGl0ZW1zIE5PVElGWSBjaGFuZ2VkKQorICAgIFFfUFJP
UEVSVFkoUVN0cmluZyBzdGF0dXMgUkVBRCBzdGF0dXMgTk9USUZZIGNoYW5nZWQpCisgICAgUV9Q
Uk9QRVJUWShRU3RyaW5nIHByb21wdCBSRUFEIHByb21wdCBOT1RJRlkgY2hhbmdlZCkKKyAgICBR
X1BST1BFUlRZKGJvb2wgYnVzeSBSRUFEIGJ1c3kgTk9USUZZIGNoYW5nZWQpCitwdWJsaWM6Cisg
ICAgZXhwbGljaXQgU3lzdGVtQ29udHJvbHMoUU9iamVjdCogcGFyZW50ID0gbnVsbHB0cik7Cisg
ICAgflN5c3RlbUNvbnRyb2xzKCk7CisgICAgUVZhcmlhbnRNYXAgc3RhdGUoKSBjb25zdCB7IHJl
dHVybiBtX3N0YXRlOyB9CisgICAgUVZhcmlhbnRMaXN0IGl0ZW1zKCkgY29uc3QgeyByZXR1cm4g
bV9pdGVtczsgfQorICAgIFFTdHJpbmcgc3RhdHVzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0dXM7
IH0KKyAgICBRU3RyaW5nIHByb21wdCgpIGNvbnN0IHsgcmV0dXJuIG1fcHJvbXB0OyB9CisgICAg
Ym9vbCBidXN5KCkgY29uc3QgeyByZXR1cm4gbV9idXN5OyB9CisgICAgUV9JTlZPS0FCTEUgdm9p
ZCBvcGVuKFFTdHJpbmcgbW9kZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCByZXF1ZXN0KFFTdHJp
bmcgYWN0aW9uLCBRU3RyaW5nIGlkID0gUVN0cmluZygpLCBib29sIGNvbmZpcm0gPSBmYWxzZSk7
CisgICAgUV9JTlZPS0FCTEUgdm9pZCBhbnN3ZXIoUVN0cmluZyB2YWx1ZSk7CisgICAgUV9JTlZP
S0FCTEUgdm9pZCBjbG9zZSgpOworc2lnbmFsczoKKyAgICB2b2lkIGNoYW5nZWQoKTsKK3ByaXZh
dGU6CisgICAgdm9pZCBzZW5kKGNvbnN0IFFKc29uT2JqZWN0JiB2YWx1ZSk7CisgICAgdm9pZCBm
YWlsKFFTdHJpbmcgbWVzc2FnZSk7CisgICAgUVByb2Nlc3MgbV9wcm9jZXNzOworICAgIFFUaW1l
ciBtX3RpbWVvdXQ7CisgICAgUUJ5dGVBcnJheSBtX2J1ZmZlcjsKKyAgICBRVmFyaWFudExpc3Qg
bV9pdGVtczsKKyAgICBRVmFyaWFudE1hcCBtX3N0YXRlOworICAgIFFTdHJpbmcgbV9tb2RlLCBt
X3N0YXR1cywgbV9wcm9tcHQ7CisgICAgYm9vbCBtX2J1c3kgPSBmYWxzZTsKK307CmRpZmYgLS1n
aXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvSGFybmVzcy5xbWwgYi9hcHAvbW9vbmxpZ2h0b3Mv
dGVzdHMvSGFybmVzcy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLjY5
OWFmN2ZmCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL0hhcm5lc3Mu
cW1sCkBAIC0wLDAgKzEsMjEgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2su
Q29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5Db250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9y
dCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFN0cmVhbWluZ1ByZWZlcmVuY2VzIDEuMAor
aW1wb3J0ICIuLi8uLi9ndWkiCitBcHBsaWNhdGlvbldpbmRvdyB7CisgICAgTWF0ZXJpYWwudGhl
bWU6IE1hdGVyaWFsLkRhcmsKKyAgICBNYXRlcmlhbC5hY2NlbnQ6IFZiVG9rZW5zLmFjY2VudAor
ICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnV2luZG93CisgICAgTWF0ZXJpYWwu
Zm9yZWdyb3VuZDogVmJUb2tlbnMudGV4dAorICAgIGNvbG9yOiBWYlRva2Vucy5iZ0FwcAorICAg
IHdpZHRoOiAxMjgwOyBoZWlnaHQ6IDgwMDsgdmlzaWJsZTogdHJ1ZQorICAgIGZ1bmN0aW9uIGNo
b29zZUFjY2VudChpKSB7IFN0cmVhbWluZ1ByZWZlcmVuY2VzLnVpQWNjZW50SW5kZXggPSBpIH0K
KyAgICBJdGVtIHsgaWQ6IHN0YWNrVmlldyB9CisgICAgUXRPYmplY3QgeyBvYmplY3ROYW1lOiAi
dGVzdFN0YXRlIjsgcHJvcGVydHkgY29sb3IgYWNjZW50OiBWYlRva2Vucy5hY2NlbnQ7IHByb3Bl
cnR5IGNvbG9yIHByZXNzZWQ6IFZiVG9rZW5zLmFjY2VudFByZXNzZWQgfQorICAgIENyaW1zb25T
dGF0dXNEaWFsb2cgeyBvYmplY3ROYW1lOiAidGVzdFBhbmVsIiB9CisgICAgU3lzdGVtQ29ubmVj
dGlvbnNEaWFsb2cgeyBvYmplY3ROYW1lOiAiY29ubmVjdGlvbnNQYW5lbCIgfQorICAgIEVjbGlw
c2VDb250cm9sQ2VudGVyIHsgb2JqZWN0TmFtZTogImNvbnRyb2xDZW50ZXIiIH0KKyAgICBFY2xp
cHNlQWJvdXREaWFsb2cgeyBvYmplY3ROYW1lOiAiYWJvdXRFY2xpcHNlIiB9Cit9CmRpZmYgLS1n
aXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sIGIvYXBwL21vb25saWdo
dG9zL3Rlc3RzL1ByZWZlcmVuY2VzLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAw
MDAwMC4uOTk2ZTVhYzQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMv
UHJlZmVyZW5jZXMucW1sCkBAIC0wLDAgKzEsMyBAQAorcHJhZ21hIFNpbmdsZXRvbgoraW1wb3J0
IFF0UXVpY2sgMi45CitRdE9iamVjdCB7IHByb3BlcnR5IGludCB1aUFjY2VudEluZGV4OiA0OyBw
cm9wZXJ0eSBib29sIHVpU2hvd0hpbnRzOiB0cnVlOyBwcm9wZXJ0eSBpbnQgd2lkdGg6IDE5MjA7
IHByb3BlcnR5IGludCBoZWlnaHQ6IDEwODA7IHByb3BlcnR5IGludCBmcHM6IDYwOyBwcm9wZXJ0
eSBpbnQgYml0cmF0ZUticHM6IDIwMDAwOyBmdW5jdGlvbiBzYXZlKCkge30gfQpkaWZmIC0tZ2l0
IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAgYi9hcHAvbW9vbmxpZ2h0
b3MvdGVzdHMvdGVzdC1jcmltc29uLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAw
MDAwMC4uYmM3ODU4YzAKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMv
dGVzdC1jcmltc29uLmNwcApAQCAtMCwwICsxLDI3MyBAQAorI2luY2x1ZGUgPFF0VGVzdD4KKyNp
bmNsdWRlIDxRVGVtcG9yYXJ5RGlyPgorI2luY2x1ZGUgPFFRbWxFbmdpbmU+CisjaW5jbHVkZSA8
UVFtbENvbXBvbmVudD4KKyNpbmNsdWRlIDxRUW1sQ29udGV4dD4KKyNpbmNsdWRlIDxRUXVpY2tT
dHlsZT4KKyNpbmNsdWRlIDxRUXVpY2tXaW5kb3c+CisjaW5jbHVkZSA8UVF1aWNrSXRlbT4KKyNp
bmNsdWRlIDxRRmlsZT4KKyNpbmNsdWRlIDxRSW1hZ2VSZWFkZXI+CisjaW5jbHVkZSA8UVRjcFNl
cnZlcj4KKyNpbmNsdWRlIDxRU3NsU29ja2V0PgorI2luY2x1ZGUgPFFTc2xLZXk+CisjaW5jbHVk
ZSA8UVNzbENlcnRpZmljYXRlPgorI2luY2x1ZGUgPFFDcnlwdG9ncmFwaGljSGFzaD4KKyNpbmNs
dWRlIDxtZW1vcnk+CisjaW5jbHVkZSA8UVN0YW5kYXJkUGF0aHM+CisjaW5jbHVkZSA8UURpcj4K
KyNpbmNsdWRlIDxRRmlsZUluZm8+CisjaW5jbHVkZSAiLi4vY3JpbXNvbnN0YXR1cy5oIgorI2lu
Y2x1ZGUgIi4uL3N5c3RlbWNvbnRyb2xzLmgiCisjaW5jbHVkZSAiLi4vZWNsaXBzZXByb2ZpbGVz
LmgiCisjaW5jbHVkZSAiLi4vLi4vYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5oIgorCitjbGFz
cyBUbHNGaXh0dXJlIDogcHVibGljIFFUY3BTZXJ2ZXIgeworcHVibGljOgorICAgIFFCeXRlQXJy
YXkgYm9keSA9IFIiKHsiY3B1X3BlcmNlbnQiOjM3LjUsInJhbV91c2VkX2J5dGVzIjo1MCwicmFt
X3RvdGFsX2J5dGVzIjoxMDB9KSI7CisgICAgaW50IGNvZGUgPSAyMDAsIHJlcXVlc3RzID0gMDsK
KyAgICBib29sIHJlc3BvbmQgPSB0cnVlOworICAgIFFCeXRlQXJyYXkgYXV0aG9yaXphdGlvbjsK
KyAgICBRU3NsQ2VydGlmaWNhdGUgY2VydDsKKyAgICBRU3NsS2V5IGtleTsKKyAgICBUbHNGaXh0
dXJlKCkgeworICAgICAgICBRRmlsZSBjKHFFbnZpcm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1RF
U1RfQ0VSVCIpKTsgYy5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpOyBjZXJ0ID0gUVNzbENlcnRp
ZmljYXRlKGMucmVhZEFsbCgpKTsKKyAgICAgICAgUUZpbGUgayhxRW52aXJvbm1lbnRWYXJpYWJs
ZSgiQ1JJTVNPTl9URVNUX0tFWSIpKTsgay5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpOyBrZXkg
PSBRU3NsS2V5KGsucmVhZEFsbCgpLCBRU3NsOjpSc2EpOworICAgICAgICBsaXN0ZW4oUUhvc3RB
ZGRyZXNzOjpMb2NhbEhvc3QpOworICAgIH0KKyAgICB2b2lkIGluY29taW5nQ29ubmVjdGlvbihx
aW50cHRyIGRlc2NyaXB0b3IpIG92ZXJyaWRlIHsKKyAgICAgICAgYXV0byBzb2NrZXQgPSBuZXcg
UVNzbFNvY2tldCh0aGlzKTsKKyAgICAgICAgc29ja2V0LT5zZXRMb2NhbENlcnRpZmljYXRlKGNl
cnQpOyBzb2NrZXQtPnNldFByaXZhdGVLZXkoa2V5KTsgc29ja2V0LT5zZXRQZWVyVmVyaWZ5TW9k
ZShRU3NsU29ja2V0OjpWZXJpZnlOb25lKTsKKyAgICAgICAgc29ja2V0LT5zZXRTb2NrZXREZXNj
cmlwdG9yKGRlc2NyaXB0b3IpOworICAgICAgICBhdXRvIGlucHV0ID0gc3RkOjptYWtlX3NoYXJl
ZDxRQnl0ZUFycmF5PigpOworICAgICAgICBjb25uZWN0KHNvY2tldCwgJlFTc2xTb2NrZXQ6OnJl
YWR5UmVhZCwgdGhpcywgW3RoaXMsIHNvY2tldCwgaW5wdXRdIHsKKyAgICAgICAgICAgIGlucHV0
LT5hcHBlbmQoc29ja2V0LT5yZWFkQWxsKCkpOworICAgICAgICAgICAgaWYgKCFpbnB1dC0+Y29u
dGFpbnMoIlxyXG5cclxuIikpIHJldHVybjsKKyAgICAgICAgICAgICsrcmVxdWVzdHM7IGF1dGhv
cml6YXRpb24gPSAqaW5wdXQ7CisgICAgICAgICAgICBpZiAocmVzcG9uZCkgeworICAgICAgICAg
ICAgICAgIFFCeXRlQXJyYXkgaGVhZGVyID0gIkhUVFAvMS4xICIgKyBRQnl0ZUFycmF5OjpudW1i
ZXIoY29kZSkgKyAiIEZpeHR1cmVcclxuQ29udGVudC1UeXBlOiBhcHBsaWNhdGlvbi9qc29uXHJc
bkNvbm5lY3Rpb246IGNsb3NlXHJcbkNvbnRlbnQtTGVuZ3RoOiAiICsgUUJ5dGVBcnJheTo6bnVt
YmVyKGJvZHkuc2l6ZSgpKSArICJcclxuIjsKKyAgICAgICAgICAgICAgICBpZiAoY29kZSA9PSAz
MDIpIGhlYWRlciArPSAiTG9jYXRpb246IGh0dHBzOi8vMTI3LjAuMC4yOjEyMzQ1L1xyXG4iOwor
ICAgICAgICAgICAgICAgIHNvY2tldC0+d3JpdGUoaGVhZGVyICsgIlxyXG4iICsgYm9keSk7IHNv
Y2tldC0+ZGlzY29ubmVjdEZyb21Ib3N0KCk7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBp
bnB1dC0+Y2xlYXIoKTsKKyAgICAgICAgfSk7CisgICAgICAgIGNvbm5lY3Qoc29ja2V0LCAmUVNz
bFNvY2tldDo6ZGlzY29ubmVjdGVkLCBzb2NrZXQsICZRT2JqZWN0OjpkZWxldGVMYXRlcik7Cisg
ICAgICAgIHNvY2tldC0+c3RhcnRTZXJ2ZXJFbmNyeXB0aW9uKCk7CisgICAgfQorfTsKKworY2xh
c3MgQ3JpbXNvblRlc3QgOiBwdWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpFQ1QKK3ByaXZhdGUg
c2xvdHM6CisgICAgdm9pZCBpbml0VGVzdENhc2UoKSB7CisgICAgICAgIFFDb3JlQXBwbGljYXRp
b246OnNldE9yZ2FuaXphdGlvbk5hbWUoIk1vb25saWdodC1PUyBUZXN0Iik7CisgICAgICAgIFFD
b3JlQXBwbGljYXRpb246OnNldEFwcGxpY2F0aW9uTmFtZSgiRWNsaXBzZUZpeHR1cmUiKTsKKyAg
ICAgICAgUVNldHRpbmdzOjpzZXREZWZhdWx0Rm9ybWF0KFFTZXR0aW5nczo6SW5pRm9ybWF0KTsK
KyAgICB9CisgICAgdm9pZCBob3N0UHJvZmlsZXNSZW1haW5Jc29sYXRlZCgpIHsKKyAgICAgICAg
RWNsaXBzZVByb2ZpbGVzIHByb2ZpbGVzOworICAgICAgICBRVmFyaWFudE1hcCB2YWx1ZXN7eyJ3
aWR0aCIsMTI4MH0seyJoZWlnaHQiLDgwMH0seyJmcHMiLDYwfSx7ImJpdHJhdGVLYnBzIiwxNTAw
MH19OworICAgICAgICBRVkVSSUZZKHByb2ZpbGVzLnNhdmUoImZpeHR1cmUtaG9zdC1hIiwiRGVz
a3RvcCIsdmFsdWVzKSk7CisgICAgICAgIFFDT01QQVJFKHByb2ZpbGVzLmxvYWQoImZpeHR1cmUt
aG9zdC1hIiwiRGVza3RvcCIpLHZhbHVlcyk7CisgICAgICAgIFFWRVJJRlkocHJvZmlsZXMubG9h
ZCgiZml4dHVyZS1ob3N0LWIiLCJEZXNrdG9wIikuaXNFbXB0eSgpKTsKKyAgICAgICAgUVZFUklG
WShwcm9maWxlcy5uYW1lcygiZml4dHVyZS1ob3N0LWEiKS5jb250YWlucygiRGVza3RvcCIpKTsK
KyAgICAgICAgUVZFUklGWSghcHJvZmlsZXMucmVtb3ZlKCJmaXh0dXJlLWhvc3QtYSIsIkRlc2t0
b3AiLGZhbHNlKSk7CisgICAgICAgIHZhbHVlc1siZnBzIl0gPSAwOyBRVkVSSUZZKCFwcm9maWxl
cy5zYXZlKCJmaXh0dXJlLWhvc3QtYSIsIkJhZCIsdmFsdWVzKSk7CisgICAgICAgIFFWRVJJRlko
cHJvZmlsZXMucmVtb3ZlKCJmaXh0dXJlLWhvc3QtYSIsIkRlc2t0b3AiLHRydWUpKTsKKyAgICAg
ICAgUVZFUklGWShwcm9maWxlcy5sb2FkKCJmaXh0dXJlLWhvc3QtYSIsIkRlc2t0b3AiKS5pc0Vt
cHR5KCkpOworICAgIH0KKyAgICB2b2lkIHN5c3RlbUNvbnRyb2xzUHJpdmF0ZVBpcGUoKSB7Cisg
ICAgICAgIFFUZW1wb3JhcnlEaXIgZGlyOyBRVkVSSUZZKGRpci5pc1ZhbGlkKCkpOworICAgICAg
ICBRRmlsZSBzY3JpcHQoZGlyLmZpbGVQYXRoKCJmaXh0dXJlLnB5IikpOyBRVkVSSUZZKHNjcmlw
dC5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7CisgICAgICAgIHNjcmlwdC53cml0ZShSIlBZ
KGltcG9ydCBqc29uLHN5cworZm9yIGxpbmUgaW4gc3lzLnN0ZGluOgorICAgIHZhbHVlPWpzb24u
bG9hZHMobGluZSkKKyAgICBhY3Rpb249dmFsdWVbJ2FjdGlvbiddCisgICAgaWYgYWN0aW9uPT0n
d2lmaS1jb25uZWN0JzoKKyAgICAgICAgcHJpbnQoanNvbi5kdW1wcyh7J3Byb21wdCc6J1dpLUZp
IHBhc3N3b3JkJ30pLGZsdXNoPVRydWUpCisgICAgICAgIHJlcGx5PWpzb24ubG9hZHMoc3lzLnN0
ZGluLnJlYWRsaW5lKCkpCisgICAgICAgIGFzc2VydCByZXBseT09eydhY3Rpb24nOidhbnN3ZXIn
LCd2YWx1ZSc6J3NlY3JldC12YWx1ZSd9CisgICAgcHJpbnQoanNvbi5kdW1wcyh7J2l0ZW1zJzpb
eydpZCc6J3dsYW4wL0FBOkJCOkNDOkREOkVFOkZGJywnbmFtZSc6JzxiPlBsYWluIFNTSUQ8L2I+
JywnZGV0YWlsJzonODAlIFdQQTInLCdjb25uZWN0ZWQnOmFjdGlvbj09J3dpZmktY29ubmVjdCd9
XSwnc3RhdHVzJzonUmVhZHknLCdkb25lJzpUcnVlfSksZmx1c2g9VHJ1ZSkKKylQWSIpOyBzY3Jp
cHQuY2xvc2UoKTsKKyAgICAgICAgcXB1dGVudigiTU9PTkxJR0hUX0NPTlRST0xTX0ZJWFRVUkUi
LCBzY3JpcHQuZmlsZU5hbWUoKS50b1V0ZjgoKSk7CisgICAgICAgIFN5c3RlbUNvbnRyb2xzIGNv
bnRyb2xzOyBjb250cm9scy5vcGVuKCJ3aWZpIik7CisgICAgICAgIFFUUllfQ09NUEFSRShjb250
cm9scy5pdGVtcygpLnNpemUoKSwgMSk7IFFWRVJJRlkoIWNvbnRyb2xzLmJ1c3koKSk7CisgICAg
ICAgIGNvbnRyb2xzLnJlcXVlc3QoImJ0LWZvcmdldCIsICJpbnZhbGlkIiwgdHJ1ZSk7IFFWRVJJ
RlkoIWNvbnRyb2xzLmJ1c3koKSk7CisgICAgICAgIGNvbnRyb2xzLnJlcXVlc3QoIndpZmktY29u
bmVjdCIsICJ3bGFuMC9BQTpCQjpDQzpERDpFRTpGRiIpOworICAgICAgICBRVFJZX1ZFUklGWSgh
Y29udHJvbHMucHJvbXB0KCkuaXNFbXB0eSgpKTsgUVZFUklGWShjb250cm9scy5idXN5KCkpOwor
ICAgICAgICBjb250cm9scy5hbnN3ZXIoInNlY3JldC12YWx1ZSIpOyBRVFJZX1ZFUklGWSghY29u
dHJvbHMuYnVzeSgpKTsKKyAgICAgICAgUVZFUklGWShjb250cm9scy5wcm9tcHQoKS5pc0VtcHR5
KCkpOyBRQ09NUEFSRShjb250cm9scy5zdGF0dXMoKSwgUVN0cmluZygiUmVhZHkiKSk7CisgICAg
ICAgIFFWRVJJRlkoY29udHJvbHMuaXRlbXMoKS5maXJzdCgpLnRvTWFwKCkudmFsdWUoImNvbm5l
Y3RlZCIpLnRvQm9vbCgpKTsKKyAgICAgICAgY29udHJvbHMuY2xvc2UoKTsgUVZFUklGWSghY29u
dHJvbHMuYnVzeSgpKTsKKyAgICAgICAgcXVuc2V0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklY
VFVSRSIpOworICAgIH0KKyAgICB2b2lkIG1hbmFnZWRVcGRhdGVyQ2Fubm90UmVwbGFjZUN1c3Rv
bWl6ZWRDbGllbnQoKSB7CisgICAgICAgIFFUZW1wb3JhcnlEaXIgZGlyOyBRVkVSSUZZKGRpci5p
c1ZhbGlkKCkpOworICAgICAgICBjb25zdCBRU3RyaW5nIGltYWdlID0gZGlyLmZpbGVQYXRoKCJj
dXN0b20uQXBwSW1hZ2UiKTsKKyAgICAgICAgUUZpbGUgZihpbWFnZSk7IFFWRVJJRlkoZi5vcGVu
KFFJT0RldmljZTo6V3JpdGVPbmx5KSk7IGYud3JpdGUoImN1c3RvbWl6ZWQgY2xpZW50Iik7IGYu
Y2xvc2UoKTsKKyAgICAgICAgY29uc3QgUUJ5dGVBcnJheSBvbGQgPSBxZ2V0ZW52KCJBUFBJTUFH
RSIpOyBjb25zdCBib29sIGhhZCA9IHFFbnZpcm9ubWVudFZhcmlhYmxlSXNTZXQoIkFQUElNQUdF
Iik7CisgICAgICAgIHFwdXRlbnYoIkFQUElNQUdFIiwgaW1hZ2UudG9VdGY4KCkpOworICAgICAg
ICBBdXRvVXBkYXRlQ2hlY2tlciBjaGVja2VyOworICAgICAgICBRVkVSSUZZKGNoZWNrZXIub3NN
YW5hZ2VkKCkpOyBRVkVSSUZZKCFjaGVja2VyLmNhbkluc3RhbGxVcGRhdGVzKCkpOworICAgICAg
ICBRU2lnbmFsU3B5IGNvbXBsZXRlZCgmY2hlY2tlciwgJkF1dG9VcGRhdGVDaGVja2VyOjpjaGVj
a0NvbXBsZXRlZCk7CisgICAgICAgIFFTaWduYWxTcHkgZmFpbGVkKCZjaGVja2VyLCAmQXV0b1Vw
ZGF0ZUNoZWNrZXI6Omluc3RhbGxGYWlsZWQpOworICAgICAgICBjaGVja2VyLnN0YXJ0KCk7IGNo
ZWNrZXIuY2hlY2tOb3coKTsgY2hlY2tlci5jaGFubmVsQ2hhbmdlZCgpOyBjaGVja2VyLmluc3Rh
bGwoKTsKKyAgICAgICAgUUNPTVBBUkUoY29tcGxldGVkLmNvdW50KCksIDMpOyBRQ09NUEFSRShm
YWlsZWQuY291bnQoKSwgMSk7CisgICAgICAgIFFWRVJJRlkoIWNoZWNrZXIuY2hlY2tpbmcoKSk7
IFFWRVJJRlkoIWNoZWNrZXIuaW5zdGFsbGluZygpKTsKKyAgICAgICAgUVZFUklGWSghY2hlY2tl
ci5jYW5JbnN0YWxsKCkpOyBRVkVSSUZZKCFjaGVja2VyLnVwZGF0ZUF2YWlsYWJsZSgpKTsgUVZF
UklGWSghY2hlY2tlci5vZmZlckF2YWlsYWJsZSgpKTsKKyAgICAgICAgUUNPTVBBUkUoY2hlY2tl
ci5yZWxlYXNlVXJsKCksIFFTdHJpbmcoImh0dHBzOi8vZ2l0aHViLmNvbS90aDNkM2NrM3IvTW9v
bmxpZ2h0LU9TL3JlbGVhc2VzIikpOworICAgICAgICBRVkVSSUZZKGNoZWNrZXIuY3VycmVudFZl
cnNpb24oKS5jb250YWlucygiTW9vbmxpZ2h0LU9TIGN1c3RvbWl6ZWQiKSk7CisgICAgICAgIFFW
RVJJRlkoZi5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpKTsgUUNPTVBBUkUoZi5yZWFkQWxsKCks
IFFCeXRlQXJyYXkoImN1c3RvbWl6ZWQgY2xpZW50IikpOyBmLmNsb3NlKCk7CisgICAgICAgIFFD
T01QQVJFKFFEaXIoZGlyLnBhdGgoKSkuZW50cnlMaXN0KFFEaXI6OkZpbGVzKSwgUVN0cmluZ0xp
c3R7ImN1c3RvbS5BcHBJbWFnZSJ9KTsKKyAgICAgICAgaWYgKGhhZCkgcXB1dGVudigiQVBQSU1B
R0UiLCBvbGQpOyBlbHNlIHF1bnNldGVudigiQVBQSU1BR0UiKTsKKyAgICAgICAgUUNPTVBBUkUo
QXV0b1VwZGF0ZUNoZWNrZXI6OmNvbXBhcmVTZW1hbnRpY1ZlcnNpb25zKCIwLjUuMCIsICIwLjQu
OSIpLCAxKTsKKyAgICB9CisgICAgdm9pZCBlbmRwb2ludFZhbGlkYXRpb24oKSB7CisgICAgICAg
IFFWRVJJRlkoQ3JpbXNvblN0YXR1czo6dmFsaWRFbmRwb2ludCgiaHR0cHM6Ly8xOTIuMTY4LjEu
MTA6NDc5OTAiKSk7CisgICAgICAgIFFWRVJJRlkoQ3JpbXNvblN0YXR1czo6dmFsaWRFbmRwb2lu
dCgiaHR0cHM6Ly9bZmQwMDo6MV06NDc5OTAvIikpOworICAgICAgICBmb3IgKGF1dG8gYmFkIDog
eyJodHRwOi8vaG9zdCIsICJodHRwczovL3VzZXI6c2VjcmV0QGhvc3QiLCAiaHR0cHM6Ly9ob3N0
L2FwaSIsICJodHRwczovL2hvc3QvP3Rva2VuPXNlY3JldCIsICJmaWxlOi8vL2V0Yy9wYXNzd2Qi
LCAiaHR0cHM6Ly9ob3N0LyNmcmFnbWVudCJ9KQorICAgICAgICAgICAgUVZFUklGWSghQ3JpbXNv
blN0YXR1czo6dmFsaWRFbmRwb2ludChiYWQpKTsKKyAgICB9CisgICAgdm9pZCBtaXNzaW5nQW5k
SW52YWxpZE1ldHJpY3MoKSB7CisgICAgICAgIFFTdHJpbmcgZXJyb3I7CisgICAgICAgIFFWRVJJ
RlkoQ3JpbXNvblN0YXR1czo6cGFyc2VTdGF0cygibm90IGpzb24iLCAmZXJyb3IpLmlzRW1wdHko
KSk7IFFWRVJJRlkoIWVycm9yLmlzRW1wdHkoKSk7CisgICAgICAgIGF1dG8gcyA9IENyaW1zb25T
dGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJjcHVfcGVyY2VudCI6NDIuNSwiY3B1X3RlbXBfYyI6LTEs
ImdwdV9wZXJjZW50IjpudWxsLCJyYW1fdG90YWxfYnl0ZXMiOjAsInJhbV9wZXJjZW50IjowLCJ2
cmFtX3RvdGFsX2J5dGVzIjoxMDAsInZyYW1fdXNlZF9ieXRlcyI6MTIwfSkiLCAmZXJyb3IpOwor
ICAgICAgICBRVkVSSUZZKGVycm9yLmlzRW1wdHkoKSk7IFFDT01QQVJFKHMudmFsdWUoImNwdV9w
ZXJjZW50IikudG9Eb3VibGUoKSwgNDIuNSk7CisgICAgICAgIFFWRVJJRlkoIXMuY29udGFpbnMo
ImNwdV90ZW1wX2MiKSk7IFFWRVJJRlkoIXMuY29udGFpbnMoImdwdV9wZXJjZW50IikpOyBRVkVS
SUZZKCFzLmNvbnRhaW5zKCJyYW1fcGVyY2VudCIpKTsKKyAgICAgICAgUUNPTVBBUkUocy52YWx1
ZSgidnJhbV9wZXJjZW50IikudG9Eb3VibGUoKSwgMTAwLjApOworICAgICAgICBhdXRvIGludmFs
aWQgPSBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKFIiKHsiY3B1X3BlcmNlbnQiOjEwMSwiZ3B1
X3BlcmNlbnQiOiIwIn0pIiwgJmVycm9yKTsKKyAgICAgICAgUVZFUklGWShpbnZhbGlkLmlzRW1w
dHkoKSk7IFFWRVJJRlkoZXJyb3IuaXNFbXB0eSgpKTsKKyAgICAgICAgQ3JpbXNvblN0YXR1czo6
cGFyc2VTdGF0cyhRQnl0ZUFycmF5KDY1NTM3LCAnYScpLCAmZXJyb3IpOyBRVkVSSUZZKCFlcnJv
ci5pc0VtcHR5KCkpOworICAgICAgICBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKFIiKHsiZXJy
b3IiOiJ1bnN1cHBvcnRlZCJ9KSIsICZlcnJvcik7IFFWRVJJRlkoIWVycm9yLmlzRW1wdHkoKSk7
CisgICAgfQorICAgIHZvaWQgbG9jYWxIYXJkd2FyZUZpeHR1cmUoKSB7CisgICAgICAgIFFUZW1w
b3JhcnlEaXIgdGVtcDsgUVZFUklGWSh0ZW1wLmlzVmFsaWQoKSk7CisgICAgICAgIGF1dG8gd3Jp
dGUgPSBbJl0oUVN0cmluZyBwLCBRQnl0ZUFycmF5IHZhbHVlKSB7IFFEaXIoKS5ta3BhdGgoUUZp
bGVJbmZvKHRlbXAucGF0aCgpK3ApLmFic29sdXRlUGF0aCgpKTsgUUZpbGUgZih0ZW1wLnBhdGgo
KStwKTsgUVZFUklGWShmLm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsgZi53cml0ZSh2YWx1
ZSk7IH07CisgICAgICAgIHdyaXRlKCIvY2xhc3MvcG93ZXJfc3VwcGx5L0JBVDAvdHlwZSIsICJC
YXR0ZXJ5Iik7IHdyaXRlKCIvY2xhc3MvcG93ZXJfc3VwcGx5L0JBVDAvY2FwYWNpdHkiLCAiNzMi
KTsgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9zdGF0dXMiLCAiQ2hhcmdpbmciKTsK
KyAgICAgICAgd3JpdGUoIi9jbGFzcy9uZXQvd2xhbjAvb3BlcnN0YXRlIiwgInVwIik7IHdyaXRl
KCIvY2xhc3MvbmV0L2xvL29wZXJzdGF0ZSIsICJ1cCIpOworICAgICAgICBhdXRvIGxvY2FsID0g
Q3JpbXNvblN0YXR1czo6cmVhZExvY2FsKHRlbXAucGF0aCgpKTsgUUNPTVBBUkUobG9jYWwudmFs
dWUoImJhdHRlcnlQZXJjZW50IikudG9JbnQoKSwgNzMpOyBRQ09NUEFSRShsb2NhbC52YWx1ZSgi
YmF0dGVyeVN0YXRlIikudG9TdHJpbmcoKSwgUVN0cmluZygiQ2hhcmdpbmciKSk7CisgICAgICAg
IFFDT01QQVJFKGxvY2FsLnZhbHVlKCJuZXR3b3JrIikudG9TdHJpbmcoKSwgUVN0cmluZygid2xh
bjAiKSk7IFFWRVJJRlkobG9jYWwudmFsdWUoImNvbm5lY3RlZCIpLnRvQm9vbCgpKTsKKyAgICAg
ICAgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9jYXBhY2l0eSIsICIxMDEiKTsgUUNP
TVBBUkUoQ3JpbXNvblN0YXR1czo6cmVhZExvY2FsKHRlbXAucGF0aCgpKS52YWx1ZSgiYmF0dGVy
eVBlcmNlbnQiKS50b0ludCgpLCAtMSk7CisgICAgfQorICAgIHZvaWQgcHJpdmF0ZVNldHRpbmdz
QW5kTm9Dcm9zc0hvc3RDcmVkZW50aWFscygpIHsKKyAgICAgICAgUVN0YW5kYXJkUGF0aHM6OnNl
dFRlc3RNb2RlRW5hYmxlZCh0cnVlKTsKKyAgICAgICAgQ3JpbXNvblN0YXR1cyBzdGF0dXM7IHN0
YXR1cy5zZWxlY3RIb3N0KCJ0ZXN0LWEiLCAiaHR0cHM6Ly8xMjcuMC4wLjE6NDc5OTAiKTsKKyAg
ICAgICAgUVZFUklGWShzdGF0dXMuY29uZmlndXJlKCJodHRwczovLzEyNy4wLjAuMTo0Nzk5MCIs
ICJmaXh0dXJlLXRva2VuIiwgIiIpKTsgUVZFUklGWShzdGF0dXMuY29uZmlndXJlZCgpKTsKKyAg
ICAgICAgYXV0byBwYXRoID0gUVN0YW5kYXJkUGF0aHM6OndyaXRhYmxlTG9jYXRpb24oUVN0YW5k
YXJkUGF0aHM6OkFwcENvbmZpZ0xvY2F0aW9uKSArICIvY3JpbXNvbi1ob3N0cy5qc29uIjsKKyAg
ICAgICAgUVZFUklGWSgoUUZpbGU6OnBlcm1pc3Npb25zKHBhdGgpICYgKFFGaWxlRGV2aWNlOjpS
ZWFkR3JvdXAgfCBRRmlsZURldmljZTo6UmVhZE90aGVyIHwgUUZpbGVEZXZpY2U6OldyaXRlR3Jv
dXAgfCBRRmlsZURldmljZTo6V3JpdGVPdGhlcikpID09IDApOworICAgICAgICBzdGF0dXMuc2Vs
ZWN0SG9zdCgidGVzdC1iIiwgImh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIik7IFFWRVJJRlkoIXN0
YXR1cy5jb25maWd1cmVkKCkpOworICAgICAgICBRVkVSSUZZKCFzdGF0dXMuY29uZmlndXJlKCJo
dHRwczovLzEyNy4wLjAuMjo0Nzk5MCIsICIiLCAiIikpOworICAgICAgICBRVkVSSUZZKCFzdGF0
dXMuY29uZmlndXJlKCJodHRwczovLzEyNy4wLjAuMjo0Nzk5MCIsICJmaXh0dXJlLXRva2VuIiwg
ImludmFsaWQtcGluIikpOworICAgICAgICBRVkVSSUZZKCFzdGF0dXMuY29uZmlndXJlKCJodHRw
czovLzEyNy4wLjAuMjo0Nzk5MCIsICJ0b2tlblxuaW5qZWN0aW9uIiwgIiIpKTsKKyAgICAgICAg
UUZpbGU6OnJlbW92ZShwYXRoKTsKKyAgICB9CisgICAgdm9pZCB0bHNBdXRoZW50aWNhdGlvbkFu
ZFZpc2liaWxpdHkoKSB7CisgICAgICAgIFRsc0ZpeHR1cmUgc2VydmVyOyBRVkVSSUZZKHNlcnZl
ci5pc0xpc3RlbmluZygpKTsgUVZFUklGWSghc2VydmVyLmNlcnQuaXNOdWxsKCkpOworICAgICAg
ICBRU3RyaW5nIHVybCA9ICJodHRwczovLzEyNy4wLjAuMToiICsgUVN0cmluZzo6bnVtYmVyKHNl
cnZlci5zZXJ2ZXJQb3J0KCkpOworICAgICAgICBRU3RyaW5nIHBpbiA9IFFTdHJpbmc6OmZyb21M
YXRpbjEoc2VydmVyLmNlcnQuZGlnZXN0KFFDcnlwdG9ncmFwaGljSGFzaDo6U2hhMjU2KS50b0hl
eCgpKTsKKyAgICAgICAgQ3JpbXNvblN0YXR1cyBzdGF0dXM7IHN0YXR1cy5zZWxlY3RIb3N0KCJm
aXh0dXJlLXRscyIsIHVybCk7CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmws
ICJmaXh0dXJlLW9ubHktdG9rZW4iLCAiIikpOyBzdGF0dXMuc2V0VmlzaWJsZSh0cnVlKTsKKyAg
ICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHN0YXR1cy5zdGF0dXMoKS5jb250YWlucygi
ZmluZ2VycHJpbnQiKSwgNTAwMCk7CisgICAgICAgIFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywg
MCk7IC8vIG5vIGNyZWRlbnRpYWxzIHNlbnQgYmVmb3JlIHRydXN0aW5nIHNlbGYtc2lnbmVkIFRM
UworICAgICAgICBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmUodXJsLCAiZml4dHVyZS1vbmx5LXRv
a2VuIiwgcGluKSk7CisgICAgICAgIFFUUllfQ09NUEFSRV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0
YXRzKCkudmFsdWUoImNwdV9wZXJjZW50IikudG9Eb3VibGUoKSwgMzcuNSwgNTAwMCk7CisgICAg
ICAgIFFWRVJJRlkoc2VydmVyLmF1dGhvcml6YXRpb24uY29udGFpbnMoIkF1dGhvcml6YXRpb246
IEJlYXJlciBmaXh0dXJlLW9ubHktdG9rZW4iKSk7CisgICAgICAgIFFWRVJJRlkoc2VydmVyLmF1
dGhvcml6YXRpb24uc3RhcnRzV2l0aCgiR0VUIC9hcGkvaG9zdC9zdGF0cyAiKSk7CisgICAgICAg
IHN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsgaW50IGNvdW50ID0gc2VydmVyLnJlcXVlc3RzOyBR
VGVzdDo6cVdhaXQoMjEwMCk7IFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywgY291bnQpOworICAg
ICAgICBmb3IgKGludCBjb2RlIDogezQwMSwgNDAzLCA0MDQsIDMwMn0pIHsKKyAgICAgICAgICAg
IHNlcnZlci5jb2RlID0gY29kZTsgaW50IHByaW9yID0gc2VydmVyLnJlcXVlc3RzOyBzdGF0dXMu
c2V0VmlzaWJsZSh0cnVlKTsKKyAgICAgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9VVChz
ZXJ2ZXIucmVxdWVzdHMgPiBwcmlvciwgNTAwMCk7CisgICAgICAgICAgICBRVFJZX1ZFUklGWV9X
SVRIX1RJTUVPVVQoc3RhdHVzLnN0YXRzKCkuaXNFbXB0eSgpLCA1MDAwKTsKKyAgICAgICAgICAg
IHN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsKKyAgICAgICAgfQorICAgICAgICBzZXJ2ZXIuY29k
ZSA9IDIwMDsgc2VydmVyLmJvZHkgPSBRQnl0ZUFycmF5KDcwMDAwLCAnYScpOyBpbnQgcHJpb3Ig
PSBzZXJ2ZXIucmVxdWVzdHM7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAgICBRVFJZ
X1ZFUklGWV9XSVRIX1RJTUVPVVQoc2VydmVyLnJlcXVlc3RzID4gcHJpb3IsIDUwMDApOworICAg
ICAgICBRVFJZX1ZFUklGWV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0YXRzKCkuaXNFbXB0eSgpLCA1
MDAwKTsgc3RhdHVzLnNldFZpc2libGUoZmFsc2UpOworICAgICAgICBRVkVSSUZZKHN0YXR1cy5j
b25maWd1cmUodXJsLCAiZml4dHVyZS1vbmx5LXRva2VuIiwgUVN0cmluZyg2NCwgJzAnKSkpOyBz
dGF0dXMuc2V0VmlzaWJsZSh0cnVlKTsKKyAgICAgICAgY291bnQgPSBzZXJ2ZXIucmVxdWVzdHM7
IFFUZXN0OjpxV2FpdCg1MDApOyBRQ09NUEFSRShzZXJ2ZXIucmVxdWVzdHMsIGNvdW50KTsgUVZF
UklGWShzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCkpOworICAgICAgICBzdGF0dXMuc2V0VmlzaWJs
ZShmYWxzZSk7CisgICAgfQorICAgIHZvaWQgaWNvblJlc291cmNlcygpIHsKKyAgICAgICAgZm9y
IChjb25zdCBRU3RyaW5nJiBuYW1lIDogeyJlY2xpcHNlLWljb24iLCAiZWNsaXBzZS1jb250cm9s
cyIsICJlY2xpcHNlLXBvd2VyIiwgImNyaW1zb24tbmV0d29yayIsICJjcmltc29uLWJsdWV0b290
aCIsICJjcmltc29uLWJhdHRlcnkiLCAiY3JpbXNvbi1ob3N0IiwgInNldHRpbmdzIn0pIHsKKyAg
ICAgICAgICAgIGNvbnN0IFFTdHJpbmcgcGF0aCA9ICI6L3Jlcy8iICsgbmFtZSArICIuc3ZnIjsK
KyAgICAgICAgICAgIFFWRVJJRlkyKFFGaWxlOjpleGlzdHMocGF0aCksIHFQcmludGFibGUocGF0
aCkpOworICAgICAgICAgICAgUUltYWdlUmVhZGVyIHJlYWRlcihwYXRoKTsKKyAgICAgICAgICAg
IFFWRVJJRlkyKCFyZWFkZXIucmVhZCgpLmlzTnVsbCgpLCBxUHJpbnRhYmxlKHBhdGggKyAiOiAi
ICsgcmVhZGVyLmVycm9yU3RyaW5nKCkpKTsKKyAgICAgICAgfQorICAgIH0KKyAgICB2b2lkIHFt
bFBhbGV0dGVBbmRQYW5lbHMoKSB7CisgICAgICAgIFFTdHJpbmcgc291cmNlID0gcUVudmlyb25t
ZW50VmFyaWFibGUoIlZJQkVNSVNfVEVTVF9TT1VSQ0UiKTsgUVZFUklGWSghc291cmNlLmlzRW1w
dHkoKSk7CisgICAgICAgIFFRdWlja1N0eWxlOjpzZXRTdHlsZSgiTWF0ZXJpYWwiKTsKKyAgICAg
ICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlKFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNlICsg
Ii9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sIiksICJTdHJlYW1pbmdQcmVm
ZXJlbmNlcyIsIDEsIDAsICJTdHJlYW1pbmdQcmVmZXJlbmNlcyIpOworICAgICAgICBxbWxSZWdp
c3RlclNpbmdsZXRvblR5cGUoUVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UgKyAiL2FwcC9ndWkv
VmJUb2tlbnMucW1sIiksICJWaWJlbWlzLlJlZGVzaWduIiwgMSwgMCwgIlZiVG9rZW5zIik7Cisg
ICAgICAgIFFUZW1wb3JhcnlEaXIgY29udHJvbHNGaXh0dXJlOyBRVkVSSUZZKGNvbnRyb2xzRml4
dHVyZS5pc1ZhbGlkKCkpOworICAgICAgICBRRmlsZSBoZWxwZXIoY29udHJvbHNGaXh0dXJlLmZp
bGVQYXRoKCJoZWxwZXIucHkiKSk7IFFWRVJJRlkoaGVscGVyLm9wZW4oUUlPRGV2aWNlOjpXcml0
ZU9ubHkpKTsKKyAgICAgICAgaGVscGVyLndyaXRlKFIiUFkoaW1wb3J0IGpzb24sc3lzCitmb3Ig
bGluZSBpbiBzeXMuc3RkaW46CisgICAgdmFsdWU9anNvbi5sb2FkcyhsaW5lKQorICAgIHByaW50
KGpzb24uZHVtcHMoeydzdGF0ZSc6eyd2b2x1bWUnOjUwLCdtdXRlZCc6RmFsc2UsJ3NpbmtzJzpb
eydpZCc6JzQyJywnbmFtZSc6J1NwZWFrZXJzJywnZGVmYXVsdCc6VHJ1ZX0seydpZCc6JzU3Jywn
bmFtZSc6J0FpclBvZHMnLCdkZWZhdWx0JzpGYWxzZX1dLCdicmlnaHRuZXNzJzp7J3NjcmVlbic6
eydkZXZpY2UnOidpbnRlbF9iYWNrbGlnaHQnLCdwZXJjZW50Jzo2MH0sJ2tleWJvYXJkJzp7J2Rl
dmljZSc6J3NwaTo6a2JkX2JhY2tsaWdodCcsJ3BlcmNlbnQnOjMwfX0sJ29zJzp7J05BTUUnOidN
b29ubGlnaHQtT1MnLCdWRVJTSU9OJzonMC4zLWRldicsJ1RBUkdFVCc6J0ZpeHR1cmUgaGFyZHdh
cmUnLCdGRURPUkEnOic0NCd9LCdrZXJuZWwnOidmaXh0dXJlLWtlcm5lbCd9LCdpdGVtcyc6W3sn
aWQnOidmaXh0dXJlJywnbmFtZSc6J0ZpeHR1cmUgZGV2aWNlJywnZGV0YWlsJzonQXZhaWxhYmxl
JywnY29ubmVjdGVkJzpUcnVlfV0sJ3N0YXR1cyc6J1JlYWR5JywnZG9uZSc6VHJ1ZX0pLGZsdXNo
PVRydWUpCispUFkiKTsgaGVscGVyLmNsb3NlKCk7CisgICAgICAgIHFwdXRlbnYoIk1PT05MSUdI
VF9DT05UUk9MU19GSVhUVVJFIixoZWxwZXIuZmlsZU5hbWUoKS50b1V0ZjgoKSk7CisgICAgICAg
IFFRbWxFbmdpbmUgZW5naW5lOworICAgICAgICBRUW1sQ29tcG9uZW50IGNvbXBvbmVudCgmZW5n
aW5lLCBRVXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSArICIvYXBwL21vb25saWdodG9zL3Rlc3Rz
L0hhcm5lc3MucW1sIikpOworICAgICAgICBRU2NvcGVkUG9pbnRlcjxRT2JqZWN0PiByb290KGNv
bXBvbmVudC5jcmVhdGUoKSk7IFFWRVJJRlkyKHJvb3QsIHFQcmludGFibGUoY29tcG9uZW50LmVy
cm9yU3RyaW5nKCkpKTsKKyAgICAgICAgYXV0byBwYW5lbCA9IHJvb3QtPmZpbmRDaGlsZDxRT2Jq
ZWN0Kj4oInRlc3RQYW5lbCIpOyBRVkVSSUZZKHBhbmVsKTsKKyAgICAgICAgYXV0byBzdGF0ZSA9
IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oInRlc3RTdGF0ZSIpOyBRVkVSSUZZKHN0YXRlKTsK
KyAgICAgICAgZm9yIChpbnQgaSA9IDA7IGkgPCAxNjsgKytpKSB7CisgICAgICAgICAgICBRVkVS
SUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksICJjaG9vc2VBY2NlbnQi
LCBRX0FSRyhRVmFyaWFudCwgaSkpKTsKKyAgICAgICAgICAgIFFWRVJJRlkoc3RhdGUtPnByb3Bl
cnR5KCJhY2NlbnQiKS52YWx1ZTxRQ29sb3I+KCkuaXNWYWxpZCgpKTsKKyAgICAgICAgICAgIFFW
RVJJRlkoc3RhdGUtPnByb3BlcnR5KCJwcmVzc2VkIikudmFsdWU8UUNvbG9yPigpLmlzVmFsaWQo
KSk7CisgICAgICAgIH0KKyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9k
KHJvb3QuZGF0YSgpLCAiY2hvb3NlQWNjZW50IiwgUV9BUkcoUVZhcmlhbnQsIDQpKSk7CisgICAg
ICAgIGZvciAoUVN0cmluZyBraW5kIDogeyJuZXR3b3JrIiwgImJhdHRlcnkiLCAiaG9zdCJ9KSB7
CisgICAgICAgICAgICBRVkVSSUZZKHBhbmVsLT5zZXRQcm9wZXJ0eSgia2luZCIsIGtpbmQpKTsK
KyAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChwYW5lbCwgIm9w
ZW4iKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAgICAgICAgICAgUVZFUklGWShwYW5lbC0+cHJv
cGVydHkoInZpc2libGUiKS50b0Jvb2woKSk7CisgICAgICAgICAgICBRU3RyaW5nIG91dCA9IHFF
bnZpcm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgICAgICBp
ZiAoIW91dC5pc0VtcHR5KCkpIHsKKyAgICAgICAgICAgICAgICBRRGlyKCkubWtwYXRoKG91dCk7
CisgICAgICAgICAgICAgICAgYXV0byB3aW5kb3cgPSBxb2JqZWN0X2Nhc3Q8UVF1aWNrV2luZG93
Kj4ocm9vdC5kYXRhKCkpOyBRVkVSSUZZKHdpbmRvdyk7CisgICAgICAgICAgICAgICAgUVZFUklG
WSh3aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZlKG91dCArICIvIiArIGtpbmQgKyAiLnBuZyIpKTsK
KyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1l
dGhvZChwYW5lbCwgImNsb3NlIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgfQorICAg
ICAgICBhdXRvIGNvbm5lY3Rpb25zID0gcm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigiY29ubmVj
dGlvbnNQYW5lbCIpOyBRVkVSSUZZKGNvbm5lY3Rpb25zKTsKKyAgICAgICAgZm9yIChRU3RyaW5n
IGtpbmQgOiB7IndpZmkiLCAiYnQifSkgeworICAgICAgICAgICAgcm9vdC0+c2V0UHJvcGVydHko
IndpZHRoIiwgMTAyNCk7IHJvb3QtPnNldFByb3BlcnR5KCJoZWlnaHQiLCA2NDApOworICAgICAg
ICAgICAgUVZFUklGWShjb25uZWN0aW9ucy0+c2V0UHJvcGVydHkoImtpbmQiLCBraW5kKSk7Cisg
ICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY29ubmVjdGlvbnMs
ICJvcGVuIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgICAgIFFWRVJJRlkoY29ubmVj
dGlvbnMtPnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAgICAgICAgUVZFUklG
WShjb25uZWN0aW9ucy0+cHJvcGVydHkoIndpZHRoIikudG9JbnQoKSA8PSA5OTIpOworICAgICAg
ICAgICAgUVN0cmluZyBvdXQgPSBxRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9TQ1JFRU5T
SE9UUyIpOworICAgICAgICAgICAgaWYgKCFvdXQuaXNFbXB0eSgpKSB7CisgICAgICAgICAgICAg
ICAgYXV0byB3aW5kb3cgPSBxb2JqZWN0X2Nhc3Q8UVF1aWNrV2luZG93Kj4ocm9vdC5kYXRhKCkp
OyBRVkVSSUZZKHdpbmRvdyk7CisgICAgICAgICAgICAgICAgUVZFUklGWSh3aW5kb3ctPmdyYWJX
aW5kb3coKS5zYXZlKG91dCArICIvIiArIGtpbmQgKyAiLXNlbGVjdG9yLnBuZyIpKTsKKyAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChj
b25uZWN0aW9ucywgImNsb3NlIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgfQorICAg
ICAgICBRUW1sQ29tcG9uZW50IGFjdGlvbkNvbXBvbmVudCgmZW5naW5lLFFVcmw6OmZyb21Mb2Nh
bEZpbGUoc291cmNlKyIvYXBwL2d1aS9FY2xpcHNlQWN0aW9uQnV0dG9uLnFtbCIpKTsKKyAgICAg
ICAgUVNjb3BlZFBvaW50ZXI8UU9iamVjdD4gYWN0aW9uKGFjdGlvbkNvbXBvbmVudC5jcmVhdGUo
KSk7IFFWRVJJRlkyKGFjdGlvbixxUHJpbnRhYmxlKGFjdGlvbkNvbXBvbmVudC5lcnJvclN0cmlu
ZygpKSk7CisgICAgICAgIGF1dG8gYWN0aW9uSXRlbSA9IHFvYmplY3RfY2FzdDxRUXVpY2tJdGVt
Kj4oYWN0aW9uLmRhdGEoKSk7IFFWRVJJRlkoYWN0aW9uSXRlbSk7CisgICAgICAgIGF1dG8gYWN0
aW9uV2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgpKTsgUVZF
UklGWShhY3Rpb25XaW5kb3cpOworICAgICAgICBhY3Rpb25JdGVtLT5zZXRQYXJlbnRJdGVtKGFj
dGlvbldpbmRvdy0+Y29udGVudEl0ZW0oKSk7IGFjdGlvbkl0ZW0tPmZvcmNlQWN0aXZlRm9jdXMo
KTsKKyAgICAgICAgUVNpZ25hbFNweSBhY3RpdmF0ZWQoYWN0aW9uLmRhdGEoKSxTSUdOQUwoY2xp
Y2tlZCgpKSk7CisgICAgICAgIFFUZXN0OjprZXlDbGljayhhY3Rpb25XaW5kb3csUXQ6OktleV9S
ZXR1cm4pOyBRQ09NUEFSRShhY3RpdmF0ZWQuY291bnQoKSwxKTsKKyAgICAgICAgYWN0aW9uSXRl
bS0+c2V0VmlzaWJsZShmYWxzZSk7CisgICAgICAgIGF1dG8gY2VudGVyID0gcm9vdC0+ZmluZENo
aWxkPFFPYmplY3QqPigiY29udHJvbENlbnRlciIpOyBRVkVSSUZZKGNlbnRlcik7CisgICAgICAg
IFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChjZW50ZXIsIm9wZW4iKSk7IFFUZXN0
OjpxV2FpdCg1MDApOworICAgICAgICBRVkVSSUZZKGNlbnRlci0+cHJvcGVydHkoInZpc2libGUi
KS50b0Jvb2woKSk7CisgICAgICAgIFFTdHJpbmcgb3V0ID0gcUVudmlyb25tZW50VmFyaWFibGUo
IkNSSU1TT05fU0NSRUVOU0hPVFMiKTsKKyAgICAgICAgYXV0byB3aW5kb3cgPSBxb2JqZWN0X2Nh
c3Q8UVF1aWNrV2luZG93Kj4ocm9vdC5kYXRhKCkpOyBRVkVSSUZZKHdpbmRvdyk7CisgICAgICAg
IGlmICghb3V0LmlzRW1wdHkoKSkgUVZFUklGWSh3aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZlKG91
dCsiL2VjbGlwc2UtY29udHJvbC1jZW50ZXIucG5nIikpOworICAgICAgICBRVkVSSUZZKFFNZXRh
T2JqZWN0OjppbnZva2VNZXRob2QoY2VudGVyLCJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7
CisgICAgICAgIGF1dG8gYWJvdXQgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJhYm91dEVj
bGlwc2UiKTsgUVZFUklGWShhYm91dCk7CisgICAgICAgIGFib3V0LT5zZXRQcm9wZXJ0eSgiaW5m
byIsIFFWYXJpYW50TWFwe3sib3MiLFFWYXJpYW50TWFwe3siTkFNRSIsIk1vb25saWdodC1PUyJ9
LHsiVkVSU0lPTiIsIjAuMy1kZXYifSx7IlRBUkdFVCIsIkZpeHR1cmUgaGFyZHdhcmUifSx7IkZF
RE9SQSIsIjQ0In19fSx7Imtlcm5lbCIsImZpeHR1cmUta2VybmVsIn19KTsKKyAgICAgICAgUVZF
UklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGFib3V0LCJvcGVuIikpOyBRVGVzdDo6cVdh
aXQoMzAwKTsKKyAgICAgICAgUVZFUklGWShhYm91dC0+cHJvcGVydHkoInZpc2libGUiKS50b0Jv
b2woKSk7CisgICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgUVZFUklGWSh3aW5kb3ctPmdyYWJX
aW5kb3coKS5zYXZlKG91dCsiL2VjbGlwc2UtYWJvdXQucG5nIikpOworICAgICAgICBRVkVSSUZZ
KFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoYWJvdXQsImNsb3NlIikpOworICAgICAgICBxdW5z
ZXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIik7CisgICAgfQorfTsKK1FURVNUX01B
SU4oQ3JpbXNvblRlc3QpCisjaW5jbHVkZSAidGVzdC1jcmltc29uLm1vYyIKZGlmZiAtLWdpdCBh
L2FwcC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24ucHJvIGIvYXBwL21vb25saWdodG9z
L3Rlc3RzL3Rlc3QtY3JpbXNvbi5wcm8KbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAw
MDAuLjUwMWNlNjU3Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rl
c3QtY3JpbXNvbi5wcm8KQEAgLTAsMCArMSwxOCBAQAorUVQgKz0gY29yZSBndWkgcXVpY2sgbmV0
d29yayBxdWlja2NvbnRyb2xzMiB0ZXN0bGliIHN2ZworQ09ORklHICs9IGMrKzE3IHRlc3RjYXNl
CitUQVJHRVQgPSB0ZXN0LWNyaW1zb24KK1NPVVJDRVMgKz0gdGVzdC1jcmltc29uLmNwcCAuLi9j
cmltc29uc3RhdHVzLmNwcAorSEVBREVSUyArPSAuLi9jcmltc29uc3RhdHVzLmgKKworU09VUkNF
UyArPSAuLi9tYW5hZ2VkdXBkYXRlcy5jcHAKK0hFQURFUlMgKz0gLi4vLi4vYmFja2VuZC9hdXRv
dXBkYXRlY2hlY2tlci5oCisKK0RFRklORVMgKz0gTU9PTkxJR0hUX0NPTlRST0xTX1RFU1QKK1NP
VVJDRVMgKz0gLi4vc3lzdGVtY29udHJvbHMuY3BwCitIRUFERVJTICs9IC4uL3N5c3RlbWNvbnRy
b2xzLmgKKworU09VUkNFUyArPSAuLi9lY2xpcHNlcHJvZmlsZXMuY3BwCitIRUFERVJTICs9IC4u
L2VjbGlwc2Vwcm9maWxlcy5oCisKKyMgTWF0Y2ggdGhlIHByb2R1Y3Rpb24gcmVzb3VyY2UgYnVu
ZGxlIHNvIHJlbmRlcmVkIGljb25zIGFyZSBhY3R1YWxseSB0ZXN0ZWQuCitSRVNPVVJDRVMgKz0g
Li4vLi4vcmVzb3VyY2VzLnFyYwpkaWZmIC0tZ2l0IGEvYXBwL3FtbC5xcmMgYi9hcHAvcW1sLnFy
YwppbmRleCBhM2MxMWRkNy4uNzE0YzY1MWYgMTAwNjQ0Ci0tLSBhL2FwcC9xbWwucXJjCisrKyBi
L2FwcC9xbWwucXJjCkBAIC0xNCw2ICsxNCwxMSBAQAogICAgICAgICA8ZmlsZT5ndWkvVmJIb3N0
Q2FyZC5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9WYldlbGNvbWVTaGVldC5xbWw8L2Zp
bGU+CiAgICAgICAgIDxmaWxlPmd1aS9tYWluLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3Vp
L0NyaW1zb25TdGF0dXNEaWFsb2cucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvU3lzdGVt
Q29ubmVjdGlvbnNEaWFsb2cucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUNv
bnRyb2xDZW50ZXIucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZUFjdGlvbkJ1
dHRvbi5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9FY2xpcHNlQWJvdXREaWFsb2cucW1s
PC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvUGNWaWV3LnFtbDwvZmlsZT4KICAgICAgICAgPGZp
bGU+Z3VpL0FwcFZpZXcucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvU2V0dGluZ3NWaWV3
LnFtbDwvZmlsZT4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1iYXR0ZXJ5LnN2ZyBiL2Fw
cC9yZXMvY3JpbXNvbi1iYXR0ZXJ5LnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAw
MDAwMC4uMzc1MzU2NmEKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2NyaW1zb24tYmF0dGVy
eS5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9z
dmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48ZyBmaWxsPSJu
b25lIiBzdHJva2U9IiNFQ0VFRjEiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0i
cm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxyZWN0IHg9IjIiIHk9IjYiIHdpZHRoPSIx
OCIgaGVpZ2h0PSIxMiIgcng9IjIiLz48cGF0aCBkPSJNMjIgMTB2NE02IDEwdjRNMTAgMTB2NE0x
NCAxMHY0Ii8+PC9nPjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9jcmltc29uLWJsdWV0b290
aC5zdmcgYi9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwMC4uY2VmOWFiODYKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2Ny
aW1zb24tYmx1ZXRvb3RoLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3
LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQg
MjQiPjxwYXRoIGQ9Ik03IDdsMTAgMTAtNSA0VjNsNSA0TDcgMTciIGZpbGw9Im5vbmUiIHN0cm9r
ZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9r
ZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1o
b3N0LnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1ob3N0LnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NApp
bmRleCAwMDAwMDAwMC4uZDFkNTliMGMKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2NyaW1z
b24taG9zdC5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcv
MjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48ZyBm
aWxsPSJub25lIiBzdHJva2U9IiNFQ0VFRjEiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGlu
ZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxyZWN0IHg9IjMiIHk9IjMiIHdp
ZHRoPSIxOCIgaGVpZ2h0PSIxNCIgcng9IjIiLz48cGF0aCBkPSJNOCAyMWg4TTEyIDE3djRNNiAx
MGgzbDItNCAzIDggMi00aDIiLz48L2c+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1z
b24tbmV0d29yay5zdmcgYi9hcHAvcmVzL2NyaW1zb24tbmV0d29yay5zdmcKbmV3IGZpbGUgbW9k
ZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLmIyYTEwM2E2Ci0tLSAvZGV2L251bGwKKysrIGIvYXBw
L3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6
Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAg
MCAyNCAyNCI+PGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRUNFRUYxIiBzdHJva2Utd2lkdGg9IjEu
OCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBk
PSJNMyA4YTE0IDE0IDAgMCAxIDE4IDBNNiAxMmE5IDkgMCAwIDEgMTIgME05IDE2YTQgNCAwIDAg
MSA2IDAiLz48Y2lyY2xlIGN4PSIxMiIgY3k9IjIwIiByPSIxIi8+PC9nPjwvc3ZnPgpkaWZmIC0t
Z2l0IGEvYXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZyBiL2FwcC9yZXMvZWNsaXBzZS1jb250
cm9scy5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLjY1M2RiZDgyCi0t
LSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZwpAQCAtMCwwICsx
IEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBo
ZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik00IDZoMTZNNCAxMmgxNk00
IDE4aDE2TTggM3Y2TTE2IDl2Nk0xMCAxNXY2IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBz
dHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49
InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcgYi9h
cHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAw
MDAuLjcxMTVjMzM2Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9lY2xpcHNlLWljb24uc3Zn
CkBAIC0wLDAgKzEsNyBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmci
IHdpZHRoPSI1MTIiIGhlaWdodD0iNTEyIiB2aWV3Qm94PSIwIDAgNTEyIDUxMiI+Cis8ZGVmcz48
bGluZWFyR3JhZGllbnQgaWQ9InJpbSIgeDE9IjAiIHkxPSIwIiB4Mj0iMSIgeTI9IjEiPjxzdG9w
IHN0b3AtY29sb3I9IiNmZjc1OGIiLz48c3RvcCBvZmZzZXQ9Ii40OCIgc3RvcC1jb2xvcj0iI2Rj
MzY1OCIvPjxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzYzMTUyYiIvPjwvbGluZWFyR3Jh
ZGllbnQ+PGxpbmVhckdyYWRpZW50IGlkPSJnbGFzcyIgeDE9IjAiIHkxPSIwIiB4Mj0iMCIgeTI9
IjEiPjxzdG9wIHN0b3AtY29sb3I9IiMyMDE1MWMiLz48c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29s
b3I9IiMwODA4MGIiLz48L2xpbmVhckdyYWRpZW50PjwvZGVmcz4KKzxyZWN0IHg9IjEyIiB5PSIx
MiIgd2lkdGg9IjQ4OCIgaGVpZ2h0PSI0ODgiIHJ4PSIxMTAiIGZpbGw9InVybCgjZ2xhc3MpIiBz
dHJva2U9IiNmZmZmZmYiIHN0cm9rZS1vcGFjaXR5PSIuMTMiIHN0cm9rZS13aWR0aD0iMiIvPgor
PGNpcmNsZSBjeD0iMjU2IiBjeT0iMjU2IiByPSIxNDQiIGZpbGw9InVybCgjcmltKSIvPgorPGNp
cmNsZSBjeD0iMjY4IiBjeT0iMjQ5IiByPSIxMzYiIGZpbGw9IiMwODA4MGIiLz4KKzxwYXRoIGQ9
Ik0xNTEgMTYyYTE0MyAxNDMgMCAwIDEgMTM1LTQ4IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmU4
ZWUiIHN0cm9rZS1vcGFjaXR5PSIuNTUiIHN0cm9rZS13aWR0aD0iMyIgc3Ryb2tlLWxpbmVjYXA9
InJvdW5kIi8+Cis8L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTEyOC5w
bmcgYi9hcHAvcmVzL2VjbGlwc2UtbWFyay0xMjgucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0Cmlu
ZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLjE1MTIxYzA0YmU3
YTRjYjlmYjY1ZmYwOTlkNzQ2N2I0NDRjNmU5MGQKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDcw
ODcKemNtVjtnOCZLcWxQKTxoOzNLfExrMDAwZTFOSkxUcTAwNGpoMDA0anAxXkBzNiEjLWlsMDAw
fHlOa2w8WmMlMUU+CnpkNi08KWI+TSZKLWRDQHh5THdkJTJfJl9JZ3BrO2dGaClSWmdiajhFajJG
Ty0/SEM3ZG4yaGxeOFNuOVk9OTVWIwp6Nk1yVT9jcnI2eSRtaUkyYTZGRlVJNU9pdmoyRk9Rdnp2
VnBsRitgT21VXmtgK1RPZU8lcGIzKylvTHxEZlYjUmAKenMkWU12S2RIT0EtbTc9Y0pAPWUqJnBs
NzVGOU0rS2BgKUM2QnNWQUZoYDJlallTaypVYV49YloybW13SDdjYEE5CnpLKEtQPCUzIyYxUlIr
ZkQjXkwzI3p3eFM3dElVbHotZWBiJD85WXVneFkoSW5aQHNsYCpTY0x7eHc2THw/c0hGUAp6KHFX
SUF5P0Ehej5aYEJMK3JXRDd7UD5weXQ1JlZASHtOKlQwbCM9WDk1d34kPis3P3RTRmlSfCY2bGRt
SDZPVTwKemxwV2kpekh4WUhfempoRWQxKU5HPEQ3SGRzPWdKfjtCY00kaChJSjNGJEhWd0tvSG0r
VkxKVk1NYHk8KSRJWUdoCnomQERmXzxyeHZGTyQqWjMqSm9DKlVoTkxjWDx6UmZSMFp6PFkhTEFO
RTNQPGUpQX12JTlVZENHdnxLOG09QUU8Nwp6ZEF4ZDF0IWxeWEo/anlRUjBTZX01cmVlYFczNVlQ
KG9lTkB3KlRBbHo0TCRrUHlnPkhrSG0zZVQqdXp+Kkt4fCUKel58dUNhc1pAJGZSPSlqUlRlb2Zm
UjZkdSNJRjJINSZZPW5qdUJ5RXZgXzRDTWJKe2VnSGEtK2tSVFVIfjBAaGxCCnpSNyVfMCtJfjVB
PyVlLSUkMzF0aGlKfU89MDs4N3EpJCpESVFQVnN6IXNWQTt7KzVrdipNQjg5SmJYYz1RbypZdAp6
TXEpdX4mZFdJR3draTlBYkhGYEhsbVllWEg4M0tDVk10cD9gKT9NWGMqMGx5YERnJDdFQT5ocmVS
ZWdrLVd0M1gKelg7e0doOzJZb1F7QCp2PkA+bCkreVJSI2slNlJxTzdeQnRTSDw+KH5fZzsqTU5v
Tys1b09SNjIqTUl6KUtsfFYoCnpLUkd9V1pOO3pqMjRpYCgzSj9KQ1Jxd3AmNTF4UGFzcVlMQTwo
OUBTUiU0OChEZm9LaHkhUjU9ejt0eEJLWXorOwp6cispbTB8R041S1Vab1BlOFU/VC07QCpEMiNV
SXxoZSM1cyQzZEotK0VGdypCZWhOfDU3JHM9UXdwMzE3d0NLOXEKekBBPHt8Uk1pNTlHI3duTzB0
OHx0ekclZS1wV0QyNyVUMHgxNW8/VTJJcURrKT1lQFRyRWlMcitfSX19NDU4aVc9CnpgYUBIS1NJ
b3w+V012PkNAcjVmY199cz0jbntPJTxpX1JGTTNSYkNsRDl2TjQ0PWN1S3A7JmFBSGdFcGdnKTEp
agp6b1FTeFV0YjlmNWR7NzFHPis3PzNiOWVsUUQ9KXJnPipnJnRsfWFVTmpHNUhiV1J1czc3LUxN
U1JFb0U1LWc0OTEKekZTeilfY1hNfiMqVmxKWUVCJiR4UHomYHdjPT1XNXpQTnRGJkJiRVRILStF
dWgldj8laSQlWTIhOzliaztOQDRICnp5TCRDJWNRN1RHUD8oQn1Bb0FWc2V6KVVxe19FRXM5dm0x
dkw1ejVzM3AmI1V1aWwlaz8oWCVVYFNLVWV7PlZvQAp6R09WWnlxdl87UENSQmh2dXM9NCZvcFop
bkh9QmxHXklHUiEpN3poQnNBX0RENFVWMEE/Qjc1NSNHe3xeLWNSVGgKejl4JFQmel4oQE8tcGsl
fExJM1ZPKkc0WE9oJV9DKFg/N3JEQk53fj0tRnZSPmQqfGhFMjMrMytRUUpmb3peRSRBCnptWWpD
KS1hUH43QXZEOWk+NURfTEdrU1Z7YGBGcWktWWc9SnRRKEI3cDlTY24malM5UDdoVXA+ZH5XMUNN
VnJFKAp6LWRJSV9LOUBXSFReQzxeRGQ1TERneVN1TXZEVyVpUGRORzQxTzBuMVk+eGdUMCo3THtY
WkdDbl4hakpzPllPdS0KenU+endPcGp2dzVgYCoqSHlwU0p4diNNOGAhYW93UVVPazA7eyh8PmlA
eEVuJXVnVihPLXZSX2NlRDFRZHpxKTxmCnpqeFJkelZAWkQyV2Nte3VWfWR6emp7RUJVazNhaysj
dy18KF4jUG8hMkUjK1NjUjEmZVgzVCNpVlZyWGU9a284Kwp6cSFlIzc5NWdVJHtgSHk8ZHwrdzBU
dDBkMUAwdUpENz1VdUFibj98I1VBK1gqK0I5R1E/ei16UDFGJiheXzclPiMKekx0YVgzR09jalZ4
blMkb08pRnJaJW5pV1pjaSM7X0Zgci1Wb251U3w+SmYjQUFSLXVKNHRtc0hjTylTcT5ZWmFHCnpV
c3crTldMfFVmeXM/JjJzbDMjQTlrKXFrYGVKSD1SUGYjdCNTdX5MYU5nbC03MFQySzdiVTQkOWFF
OE9aR2FpQwp6Mi1Fa0BpMVNMaFI2ZmFBaSs5UCFnTWoyQ2NeQWpfPGJAfkFRUHR8TG40VEQ4NVdx
UHtwO0QkQ018ZmpzWD5GeWEKenItI3x5R2RRTkJsZ0AwR2JTZ3hROzhkeCZtfTByaU5VPXo2Qit0
OyRGaGojUnFOb0IwcXZ8cSFaS0ozdlE1NE5fCnphY283ejBzOXRzWm9UIV50b0x6T0V0NVB8U05V
M35qYXVnJmBIPk1TLXFGXzQmZURaVElPbHtEU3V1WVIzcD1fPAp6dDF5Xyl2MkFGOFpHKEgrbUN2
IWFUd299d1AqSGB6bDVXaX51Y3dQc0ozODZCY1ExR1RgWXV2fCNmc1RDRWh6Z0cKelZwXmVpQDRE
OGtTPD8jU1VgKDk5WXUmQztvd2xNKDh9Vys+UnQpOCtMY1VsZSt0JFYjbXp+TEYlZypNS2ctZSgo
CnpBPWBLQzxsZzY+O2Fsc1U8SSFEUGQyeDd2VHdMYkJwPE1nVzNLKG48a1BnIzA9YTVKK0FfVF5n
dlg7O1dTZC0rKQp6Ukh1ejEybnk9N2I9fmpSckt1QF5xNm9zQyR7d3JlPT5Ib1QwaiNrVXFZNUwl
QkoqYT89SVRHWmdiJHV8OT9NJDAKekN+ZXh4S2lfZEQqRlc8cF93Qy1zaCUxOXdOVG1vPG1lI1FD
ZktOREhqSDtSbHpkR3VqRGxVI0YjfU9oeiUzOUprCnpNSG1EYUcxRWQzSDJEaGxSUUZ7bnhfX29g
enZhWFIjVHJCR0okcnxUU2F8SFFlRDtkPkB1NmtzYTltX34+OFlwcQp6QDxYP0IlWnBGNXdVfHB4
ZFlCP0I7aSViRyludUY2QXV1KSlzQlBKKlFIZihKYWcyPSY9XiNaVzJyO0l5Nj01UlQKelBNY0oo
MExFR2RNQEh5TXJ9QEdhUzg/cWh5b0VWTUNITHNGZUM1JTVgUjBadmQ4dzRnMX1VPGNSelVIcHhJ
K345Cnp0R2I+c21TTG4pclc4ZUZRWHdzPTVEe3I7TUh0SnBQeWoyMk5JaW8/TCVpZTZ2LXQ4PVM5
NXgqNFc4TSt6ZFpkWQp6SCN+aG0ma1ZqcTVRTWFhRXM0M0YxZmZyYWtTSyRxNmU9YWthWVF5dTY5
JWJpcCMlLUQwRCY+JkRyS0A1ekpCJGAKemAwKThGM0QkMD18SFlAZDtweU07dHJzMiM3IWBiNkMm
NXBJaH5VJlFUcT0tQmc9RTdGR0IkKjRLKmxMUlZ8ZjlBCnp2RnQ2M2E3TkU4eldGREEkezhJcShj
ZUFKVj1yeXo7fThGd018TiRjSFFmUipyR2cpZVJRR3Q3cTYpRWh3MXE3TQp6I3gjZiQ5NE9vVW9q
fjFwT2ZgWUE/OVMoUypXeSQ3KX43eUErd0xMcyFOPDh7X2c0UCstck1MZTY9PSh9NjhwdncKentD
R3IhKmdKK3hCVkB4QyFYVExQRFBiYm5Ic2xtd3QpKU1nPEt4VEQ7cF9rTEtUJiprOWxgY357JkQr
eUs2PndNCnpJRThFfi1MUyYxQXFYREdTQmhsR2tad1N+cHk4SCR0dWdHJDRSaWZqPWthJmZmMTNR
YCZ5d0EtaGctTD08M3NuWAp6MGZmLW54O2M1VG1zO1JCUWdzajtaSVAqPTZkKjgkSjtlZWFKTSRj
RmBqYnlGXndgc01eeWdVZihxPXlUbzcrZWsKemkhfXp7VjU4X3o4TDU9MHhWV0t8cGtXanM1TWlL
RjsrQEFXPG07Rko1eE02I2tsaSlGTC1+SEx4bn5XQ09sI3JTCnokZGAtNiZOV1E3d0lNUXJSKXBh
PTs8VDx+X354N2IxTGRfWlZxKFcwYWVVfldwRTZ1MikwIz84OD8lMmY2ZVY5Tgp6KFZsNj1QflVx
IWshK3tmMHdAQVItamZZZGVEaj0oPX1NKDMjV0FnNm5tPkt1UE0jbGxpRU1hZTJwPHkxKDBOQ3AK
elFyZlI/PlFvV3p6d31wczgoOytucVk4Z31fRkd1aWIxZU9aSlRvKGB7S01NRWBPKjVQWGlHUDRz
UHxlQzVoYCYrCnorMWZmczJJRk5iUSk+YU4yIW0wRE9Ybj0pPDBxV1hQXm15Uk5VPUZMJFBKSShM
bj10Jjh6TztuX3pAOWBRUlI+cQp6clk0STY2YClTTDdleWlWTkBvelY+V3VVOHM+SSZZVmd2cl9z
ciVXVUEwJXlxWTQ3d000RFVVcXNGRkJAYj14KCUKektsPj5feXs8dDRCWmk/JG5VNXwkb3p1SCNG
PGRGcmtxVVd1X2piTyZ7eik9bnJlVl4lbFpBKi1qJD5seXNNYyVMCnpUP2VMUTNKez49ViYtUSVf
ezhFZkNgTSVya2l6Z2tvX21Cc3JBIzBWNlFORWppYylnWGx2UUMoJHo4VCQkajFAYQp6RUlOZ0cq
Pih6WE1Bb0t3ViZFbSNZPFZGbSNYNz1BZStAeTFUI1RDe040TT9AQVZBczIleFRUP3teT1RZaVh1
PTUKenQ+cXMjSzB+ZnRBU0xEcWJeUnRyUmpJaENOZlZEI2ZYU2JNajBwTC0hWD9LWSYhVEo+ZypZ
TkRoV19GUktpVHBFCnpDUCpGOGpeOUx4QnZ3R1IqN0xjM1VPLVVxRVB6KWZaMzM/N1U0cnUtUmkh
bHVgMVFfQnlmRDAlbVpNTXMwR3hVdgp6Pz97PHwkKkxVfkZXWHdYX3F0KDNEN2M3fEo3QDVROE03
KEdpVE83T2NXbUU/SSlgYkg5Q19WUWw0empMQUhTeyYKekFQOG1leE0wPml4PjZ5TGF8OXZgUiFa
RXJkbUNjeTV1NW1WQn04UEBCRyF9b0RTIyU8UEFIWilBMlMhe2VLSC0wCnpXa1lVfGJAQFI7Sk1+
cEZRO0V+JHA0NCo7PnxZVHlpQjNTVz07TjUzWTJ+eno5IWhaeHMpV1l5XmlWJHxRSGc5Uwp6alhS
MUpLdkE2Y1NUamlqVkZLQ0slPnN4QkNGZU15dCY3PnxSd35ZY0NXYFV3Jj5yeE96YXl6MGN3Z1Ux
YTlsbVcKenpPVHQzUXBlSmNaWmdKRiY8WCZ+ZClEV05LcE1Neng/WHJaT3ArJXdrITxUKzZlXnNV
P0UrMTxYYz9kISQ4ME8rCnpzfHMrbUJtNEMmczBWZFowMGphZyV4aF4mKHc/ZGFoSnVTMnRkIXM9
JF45UDtmZz84eEBUIzwhZlNLdEd2Rz1HWgp6Q29laDJoPkl7SDRZNDAjcytzSVcrPDVBJDBCTExL
dSZHZkMwRStYRHZpRno8RDM1OWc+S2dedHJ6bGlOZFhvbW0KemtnPnRPRGoxKEEjP2MpNlBmWElL
O3FicmY2eElWTWlwM0NBOVVVfjt4QHsxd3NoUiZ+Nys3c1lQYEFeS085VXlDCnp3bURHOHpKS0VF
RDRxYkopZFdmNEJPTFghZkItVUM3STZhRSktTXNuejc/O1U1OyM+ZCM/bF55QjtDb0gpU0oyfQp6
ZktwOGJ0RVVqaClwQl5uZHIhdCNXYD56K1NhQGAhUTFfeWN5NnBAUzVzSjwrOTkxd1gpbX1ZSDNT
b1hySX4qaz8KelU8WEk1alZVSzVEPnxpNHBwaiVMY3ozeW9tOHVVPTRGeWxrY0c3ZUo2WTZhTj5n
b2VUPmUqN3ZWS2ZRPDFjO3BECnpsKHJkSVltZHJHcHNAJV4tQHwkKWdYXkF1VHtralIlPmdOKk5o
V1lmWWJVZVB0d2lkTllDRGtoRTNVNmQ+USlyMAp6Q0BCJXY8XzlSY0NeQGt6VyQmMEJ3czItZzUz
ekZ4SGZLSWNQezBfZSlBbz5rKU5OO3dTMCFhRUZCRkVAUlZvbVcKekcqd2l1cXtNTEhqNSNuVmBM
RjROSEhrUnRDO29iNzB1QDNyeWlfam9SQmtXbllPQENjaWdDbistRShNOVd2Q3BiCnoofHx5QXs7
eDBsRTVJYkhvZDZaQHhwIWJFUnQ0YEJLYEZZSkJgdXd0LSErP3hpO3VjI0t1SmN3c247Z2FHMVMl
TAp6UD0kPUt7QVRZQzJCSCN5MndHaGJ2TGFrSGAtSjNtXn1NSkNBJnt3Z0xTSjFLekB1Y1c8QHUz
ODl2UndBaT9NazEKejckNnN3ZEUxT1JvWUt9cT1fcy1TTkBEdTBuVlJpemI+QUs/MnFvfE0kP2k+
OTcrbzJSeXdZaHlLNmN5Xnltdj45CnpBMFItKzI2ZWdqaHV7UUd7XmBBWCtIQW5qYD9zPWdXU0VS
MyZZJVRgcUI4RzI9NkZ0UHBHb20zdW1XQ3t0Ty1icwp6d3Z3JkMzZS1JanEoSTZUYzIpfGtlcldA
KENjeWNgM2RISlp2bmY4P2Qpa3pAUE1LXyFxJX5lb0Rub2UrQmNDYSQKeiNQcTZVWk5Md0FaRDNP
fE40alBPUjJZaU5Uc0M3S0AwQHUmZ304en0wPEN9e05zQktDK28rKFU7cVgqbE9XamMqCnpaN2lF
aGRIIUw/VEMmRkNZS3ViKFcjP0djZG5VOFBSd357ZlE1IX1ERDY0MDdrZkE0KXEySEMwWGxSUEE9
S3V3JAp6KkRUfnpYfTJNXz57YCNgeGprZWhpM2tLSkk+Ji1ebWNOKlA3TG5GfSRMd1VIQjtDPUBa
a0BeY1hrQGdaXmkoKjIKelB8cmxyeEk7Q1cxQmNeP3xGLTRIKGVyRTdBc21SeFRyczFVUGFTKFFn
KHcqJSg7YjZRQC1Zeys5bXtUQ1ZYdiFACnohcW9NP2tKb31KLUhxVz89P3FmKlZzSG9GK3FzU3xu
QFhCT0RwKzdKdUpDN2JQVVcobTE/MSFELThqbDM2bnc8Xwp6Kjw8SnFHQ1dvcXBqQ24/LXdyP0pj
ZUxnWmVyPy1SSmQpby15OXRQV3ZUQFdgUn0yNjl7NVNCWGpebjFTNT9GKjAKekE4fnI3bnslX3Jh
N1RVenExM3htQFdmMVRIfHVNVTZlU1IkO0ExfHM9QEFDd0dOQms7KWdQIyskQk9XYzxJbXl6Cnpf
U3NiPm1fRX0lUDUzOGdJPVFsSUs1S0hARFhHSmZlRUtRMXw0ZDx7JGd6ajNUN2pudmdNNTBeQk4m
cDVWTyg8eAp6eSgyVzFaIUtFRStxJmtHa0lSP18tJU1XWHpjYjxeJlRRJUNCaSQhKFRZZnVSO3NS
OzBiIz9wPnJVRElQUGgoWk8KemZ7PWU3K1FGQiRLMkEkQGFVYHpwQX07d0RnWWZrUVp7JFBBb0po
ZXthTWVZbU0jRUcrYCt8M0BZQDV3VFhQbSVvCnpgNWluXzl3T1RTXlpyO0dNZ2J0UDFsPlclNUI2
OzJoVjQoI0IwO3M1RmxpbzlAczZeMGUwbEVhezYrNl9HUjg5RQp6QkNJcnFIQXFJaVB9Q1RVQGMh
LXZULUNYTmU7TUErMUVvRSpISkk/QjBVc0xXUkdERXp6U3FCanFJY1lRKy1iPlUKeipuSU1vNFRt
eGltJGBEcjAjMGVeOy0oIT5iQU42KGZpYXx3dF41OVpzUDUpTGh9MDl8STVGKHQlRmJUcXJkcyZI
CnomP1gpKDQ8dmJ4MWB8RnNtPDZjZU5HIXBSX0hOPyhFc3JxYlZwPmY9TVNYUCNrKzMlXnZtbmch
Y01JT2dtKiQrIwp6dFc8YFB4SSRjPTdWMlJXWTlycEU2bnNwRk8+dCVDZF9GYUUzN3N+QC13KGRY
Qmp0Z3IqPjZsNV9QSyR2RCYwMloKelNIcnV3cmdBQGpLSWFUaFp8UCNkbUdONWJJcHx7KWM8K25f
eXMzUV9LaTwyRXBBSyFLemYhfilMc3w/KjRzWHx1CnorR3RtbGl1JSFNPm4rKXRvUyZWXmFYfH51
UikrY1VASyQha0MwZktiT3lqRlZjeThkIWhZTTNkdFYqWDEqaWc9Swp6P1p5WkE8ZzYzdj56PEVD
JEBfVHBicHZza3RQU3xZdFItQzVISUYtb2NrcWtoOWpxX3NAIW4mXjVMVDY7X1IocjgKemFqO0or
KSRjVzE7IXpeP3FnR340cytGQF54Pj8+YmdKWGpYTWVuI0h6a14/bj80cUtjbVdEST8yZzxoTGUx
UCNkCnpSYXp2I3A/cjFjKTcrY2UlX25EXyRrS0VOQlIpPWkwfSYkY0RRYVNkfEVPbW5tdnpxTCQ+
SVJOJkZ8KlA7dm1+OQp6MXhpKD1zY3BiOCFpMz51RWtoQTJJUUJKZjQyQHhTcylaQjdjMjNRN3Ve
Pz12LTZUJm5kNyslKyZYSFhfUn5hVFAKendpQGErbEpGO3s7U35VcWshT0hUOH1pJGNlamVYNno8
YXZwYWI7STgkRUkyK2MkWHwxa3RCfGFhWip3QWhVXlReCnpadFk+blNKK2VAO2V9RjtiPiRxfXFh
dTZiR0k8ey1qK15TSnVuYTtWTE1XRDJZdzVCZnZ3e3JzUW15b2NTIVVZfAp6RXloLXhVTU1AXzYy
QnwtXkkmbGdDSDFzUSgoODlSMnBeYDIwPkhrNlFKWUR1IVQ7SF9rKUlGbTxrSFNMeXNpQ00Kej1B
fk1SQEQjblAmaVA2dV9FcUgoUEU1RDZHfUQxc0N+Q316aV47aXx5cEplKFBveTVMekJWTz43R3I0
PE9ES2lfCnpnQk1LLVNFfD9YUWU1S0UoZnwoP19jR3VyV1U4OzlFYHFOeWVzezFvanQ0TD9qLSte
XkJTPG1pQkVIa1ZmaTs4TQp6STUqcUYlQz1jNyY5dXtRMTdjTjU+V0RsPGN1Rm9BbTlAX25pbEhZ
K0dtfl47QH5jK0JzYTc5RHBad258I054cTIKekwxUSptM09yVUM7RjxDO0xvT24xJXhIclAqVSkh
dlYoKUhMMG0za0pmVUR+ankrJiUqQVB9SnxOS3c/N2U7ZU07Cnpvdz1STjRfaTRpKTZIb3VvZzUh
Iz45aUBiMWdLM09HNEU3flFDIylrSEVVNzNGKyE1UjdsRGNATHExfCNSQTZsLQp6JmtMMHRKRTlU
fVBiaH0wbk9eMztOPnI2S0ZoJjZ1Rko0PmBCTCQjKU4tcGEpUCpWaHAmezF7OXdwMHFORTlkIz8K
ekBLKEJQJGVkSVFeSFF4RzdpNT9qcS1pJCs4M19uUEZ4N0FfUWNxYnUxc15seUJLRWlueVBfZ0g7
fVd+I0dRJlE/CnpYfGxJNTZvWChWdjdoSXBwQDR7eSF0JitJJWU1YTBxeH1paCZZUm8mX3xWfGNz
VXFUTyY/TTAtQXUhcj1GdmdGRAp6Wk9QV0ZXUFZSbz1YRnpjfDkjYWVqNT5yPnVpcn1JNVpZd2w/
dFllSDhzYiZlYmFyKDt3UlBMKFdnX0FMMn1tQDwKejFWUH5EJkYkUnxvSndRNjBTODRQYW4+WDs8
JD4ofmE4IT5IZG5GPj9AOXpZYGg+I0lPWkdFWWhETnZaK3FFQXFPCnpBaDBgdkFhRW9EK31FWjY8
R2wwZkYjV3Q+LWxqKUY8MzhPZHo9O0BOWHFxXkpNfShrWDRpeWFQRiFQKnE0eXA+VQp6JiYoQHl3
NntOTXRVKjs5VlIzQ3pJb0tOY2slKzJfdjQoN1crd2FIeit5SmElbD9QYWBYdSpUMlIxbUFgKWEr
RGoKekdGaG1xKzh+dlI3Y1hBO0s9UHdSPTNfXj9zSCZZZVhhNFU4MV9uPHZYOEptVU8lQXwkdWVR
NnBgXmx9X0ghWkleCnpgM24wQipvc0twKGI0ZlVZWW90X0UwfDRRSiEtOT90RTJzQVJxdWIpIWpE
d3w1M3VCPCNzND08aHQ3THYkMzgpJQp6YDg5cE55bXZOQ2hpPnNuaSs/bSQpXk9tUzh4c1Y5cEVJ
WlRTTiokcFVzeUYyT0BDbHw8NWJubW9IX0haP0tgJTwKekhJOEckN3pHJFYkNGVaP14hRTF0Wjh7
OSlOUWVmSGNEej4hISUqZmdTbnhNLTlLKk9sS1QpYDZSRnd0dTd2OV55Cnp5Wjx+ZmBfQ0NvcldI
PVQrR0NFSGBQKz9+VXdtYDUzK2FCby05JW8jaD1AUD1sJS0kSFdITlo/c1pKJFJTSUZLeAp6VWR5
NTBjYH0pZG9feSpfVSN3MiYyTXFYXk9aWnIwajV+NGgod256Iy1GQl8yIyFSRXlmaEdYTkFgPGtA
bnx0JXgKemI8YmJ0eXwreFQrV1ReR3pXM2duJndUYmpmNDtNYGJEajQtcGN4aVVDJXBHUT08TXVW
X3Z6MnhfeXpDJWV2YVEqCnpVUVBrRGszUEJYeTZjOVBFbmp8aFRVKWtWJV4mTWorcUxITE4oYnRr
QmlxKG1LSTY8fkFHKz9rdEFfZ01kKWE1UAp6eWkoNUowYEE7JSZpJikoKX4+eSFSNGg0VGo1Jm5B
WWNlJmNfdWdrUjhHRip3Q0Qre2w7UWltSEQjTXJpZ0k3eFIKekl2e3hQO1JuOGQhdG8wfm1yaUdf
X2tKe3UqcmNJUUA0WmlfR2pgRiE8M0lvNExsMW5QI0JWIWptRGl6OzxpSHBjCnpwSy08O0tEJStf
aFFCVHJpJiRmdkhwOWIpSyleWmdaNj1kcDtsZjNxZjh2UXB8R01oOCNmUns+aGx+e3d3Xz9UbAp6
KlF7TjtfUysqUEJXViRkTVdoKVdPZCpRSz5OVXRfdipqZ0FtUiRHMTFIWmtjeHwofVBeX3tPfndh
PSspYVIyQEgKei1MaGlFKiUkVG5eZ0poRzBgSSpaPmRCZk1SLUVAPDFyeUFlRzJ7NmFFNiU7Pntg
PkV7TU85elg/MnFOdUY4OVdPCnp6NVZ2dkBCN1FZe1BYakFkKl4rLUNEUzZfdEpTMmxxWFV7cnFl
Kmt7Zmg0PTwpdkltRXZgQkM3eWw+eGQhKyR5Tgp6X1M8aX1rN1VrJk1ZQkphKlhxcSV6IV90Qj5z
I054YV8jZmEtWihmb3lzfWEkQ2w3QC01PzNEd1VNbzdTcU9hcVcKek0rKm5zcXBKQVRkI2B+QWdr
aFNfdTh3PF9FSURiX3VZWX4jVTVRX1FhQnUoUmNzPGduYndQMXFuQndmUyZ3Sk9fCnomNn08dCZn
Q3d5UjRTJkxIJFglakF9YWVVTHNKVlRyWiYjMjwldWVfPk1VejVWSGojaFhVOHcrJjcxIX1BQTBD
Xwp6S2FIWFk2MlpVYiRuMDxrVilPIW5SS1VkLVVBbGJaIyZ1VD80aTNHZVI0U2J3TVhgMHhxM1d3
IWxiYUZiIUFVbHkKemgjMEszcSo4JilXWVNNe2IjP3UwIVF3P2Z7PykoVkBue3J7VEtVJkI+aTBq
fTtiVDhkUjhAS1J5UlNOVikyOCszCno8Wn03NSVIYDVZYVUzMSVvUykmblomaHVzRXNSQmsqY2Vs
PSo2YTt9KVhzRHxeSVMocWB5PXpgRk00UnJudHlzJAp6TH4we3YpYmJ2ZF5CI15qOEhjR0pxaVFP
V242TX57JjNDQERDYzk8SkA2IVZWbTFZaU00QmckSz4rTX0ke0BCT2YKekpyVj9nX3VoP2Y8YDUp
Pm9IcmlVSEpRbnJpKShYIUV6PEJiN25CWl8rOH1+YFImYFM1JlUhbXpQM1B+PnNHRm5vClp7e2k9
SWRASF5eS3F2cUowMDJvdlBESExrVjFtRUIyKGJWRgoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpk
aWZmIC0tZ2l0IGEvYXBwL3Jlcy9lY2xpcHNlLW1hcmstMjU2LnBuZyBiL2FwcC9yZXMvZWNsaXBz
ZS1tYXJrLTI1Ni5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uYTEzNWM1NGUxNDllYWE5MGI2MTBhNjljOGY5YmY2
ZGViMDZjMGU2NwpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgMTU4MjUKemNtWDlfV21zRUgoKz0o
cU1UQCg7eUY+OSgrQCpNTjRVaXgkNCNuTEk2ZmZAWCNpNipueUljNzN5eCpUQkMpYnxjCnoqX25I
MFhHYkQ1KUQkcEtObCphKjBFVXZIdFFHKE8xTntqREt0X2FxOE0qIWIzSUs/dURhbEd7YCgmTVVf
K31YXgp6Xz9FbkQmazE+LTdgSXVDcSE1bG93WFkyR0JkIXB3SVAjbUY2NGZFI0I2NWQxO2ltbjtB
ZCYlZENhUW52ckdARUAKenFlYlRsbF5ueVI8VDhzVWJjfC1KUEdCMnBWPVptQ15MdWJGVGk+OEtT
VCpfZXQjYS03OUMmaGRVe0paeldhdXJsCno7b05hSVp8RUV9dn4lU25OKipfflZATEgqTUl5KmY5
d3ZOUE1GTU0qT3R1dXFtLWhfZUEzaD53OTx+JSt1SEZ1eAp6UHt3MSg0Y1FtbyFpRDdVQEkzcjds
JmIwJGQlJHNWPH5KPlk0Z1dnb0MreVk3M3UmVXplPHlkPyE7Vlh9Ylp3cHwKel5NNmRMUGl6QHlK
VXsxX1NGaUJJU1VKa35QRTEqSTZFOTNwPDVjUmA2KGohWlJVc08zNl4mb3o4KTt6dFp5cnUwCno0
RCQoT0RjT0glSVAzaTkwenApPCtsPzBpQ3gmUj4tc2pmSnowUV5jbHZ9akxzfC1xNiVYTF5qP0ol
QyN4fkA4OQp6KkdET2FEPjg8c3g5RCFDUzI4QmFsYDFrMzVMWlVoQk9+QHdrYDM/a2JoSnBYJXVE
QkF6Vj8xYyVXMXh4aTR5NEEKelZ7PX5tNyVEWH49eWg3bmAzb21sJVUmKDUkNTg7X2k2PkIrKzJT
akV0TCVgfkBIODJDVH57dHAwbEtBbzN3UyVnCnojS08hckY0ZmpteGJwKiY0SmBAfDNpVStEJGpX
fk1BUD13ZCppVUxvPUY4KmZDeX0oKzYtXnRNMlpKZSprJEtXQgp6I0IqMnZQMHV9UE90JEJFbVEp
SnVSSCtCdkN1WWBqNXhDT3l7QkErbi1LUyt2WWFtPjg8TzJeWFVJM0RHMVclVVYKejU1KytCX29Y
RVE5bVVRRUlpSGpWdyR0WWYqem58VjxfKE4/VnNyKCtEK2hrX1MySnR1KVJ7Y31NWVVgLWZyVlV2
Cnohd2E0I3V8eml+TipNaW07JmdUdkgpaEVEOSpkX2d4SFNaTkAmPnUqXjB6WG9RTVIxKCo2fWol
dDtrT00pVWlzawp6cnwhN3RMUk57ci07UUhYeWQ3NXtLZW8yRV9+emB0JFozWXd2RSNJOXNXSXtL
RUFnekRCJGwpZ0lpUmMyYXY/YkoKem5pS3NULSM8SihfNGs8R3Jqcm5VRktCcHdFLWAoYjRKKF9v
LT83MXs4JDxwWXI4a0lURHFETDJUeklLa3tTKX1zCnpfVlJHclFmdEl+VkJmJjNicDIoQ2l7ezFB
N21fbkN1U2tQeyEpM3Q0b3pEN25GWVZNNWpMPytoYzBJRTNjPlZ0SAp6QWZjbD9IIzs7KkxYKEM4
WWFnbCp1REVhUHtRaD5yfDg0T1coa1RYSFhIRmdNY05OdlNfNH1HekhzbWZqbUBiNzQKenpsKDxP
Zmk+O25CdkdnR2BLMjBrTGg9NUVYJH4xaHpVblJBZiohLW5Ea3BkSDtIaVVqIXxseTdQN0k+Wj02
eDNFCnpUQl9ZRSNHdVNsTFBXUkA2bV5lP3crbyYoWGxROFFhXylKM25hXj9eZTFBUndKPyhxNT5+
WWk1YjZRNjlyc0pqewp6V153JmM0fHZAbmRfNS1naFF3dkJHP3xKU3YySkpLUldAdVkwTSpeTXZm
T1BlSiVLPXhzOG5gSCskV0JmK3U3V3cKem81Xj4yVzk2KVArZjdeMj8mMDRZKVcqJn1jUEEzQngz
bFZSUzV3XylSSSElUjF8a1ZoQGs2cn1mKEkzLSE1V15QCnotZH1XYnsjPHxCY3BRbT9SNEEwZmU1
RTgyJXN9TWlKX2crZVA7e1FeZFA5eW15dzRZWHleNkc/PzV2WnVBfSghMgp6Knx4NyNYaUIkYmB5
PXJaQ2xCPU5lV3BWUVAySH0tLWR+KnwkTlVhKS0qe2M+KFlwYVV2YzA0eEZGKWVHMXpPQXcKekF3
NDZ4JT9wKGArYElkJG1zM3YmKzBecUp1ZFVzRVJ1a0ooP3xTUklmVFV8TlFfcWNnTkNYdmZQMG9Z
Z28rZCRvCnpXNjJ5SHVmUkMqK2U0ZkMpMXklbyFPRGk3c0V5ZkgjPnhpUSZGQU41WlkrdTBPUGVh
Y2stZXI+d14yNDAjZVJ2aQp6PWQ1cDYjTkYkISk5Tk4zQyFwN1pnKGx8PEZ9X0dAaURSSlgzdn1J
NzZyUWdtR2p5Y1lLNmZrfHR+WjM9SXRrTykKejcwcmFAZW04S1BpI2RaOUpSakVHRkxiPnhtaVo8
bF53IWMmZlRCNDhGNTRBNCVkQzMhRXxiZXFeUE1qJj9+aXZOCnpfanhyI0g4V3YhTnRuT3pMQkpL
I2phTzZoKktzKHwlRWtzXlo8PWlHJmB2ciZQRUJ9UGpfPUt9T3x7czIhMjV5Nwp6IyZickBqLTVW
TG5td0ViN2AxT3wmRjJpYDAoMSVTMWNgQlNnNjlxSlpGNHN0ZEB4bShjWTduO1RnJSVGQ3hqbT0K
ekJwPyU1b2UjUjJfXktAXkQlSl43Rnc1fFI5WT1ReVVDd0s3QyFNQGd4IzFLWGZwR19VTih9fGNe
V1hBNztJTWhJCnoqSGklJFZCYnAhckF6ZE1ubiVBJTVzYTs2YmlmSVFiS3BXTjY4WkI8UGYlYjxP
d0tXPVpedz9WbzxFfX0yPEJuKQp6P0Y5MTdDZVZJbEpWLVJrJF9vaFQ/TDVmNzJ6KDI5c0M+RVo/
Z3F+K0tkJCthUHNTSjQmKWJgc05zX2wtXmwpX2oKekh2JiNzUmUjX1ZocVBOJlZDQCRTYUNZY2g+
KmEjP2BwcTRydnJ+b1M5KFY7NXtUd281RnVUeWk7NjlvQztRdit9Cno3alBgeXoyMns/UF9hUW5Q
PlElfT83aH0tK1NQUi0pM3k1Q2kmaWV6Wn1URlNXMCNqLVkwVlA1XnFTNUFJa01JQAp6X01HRjd7
cDB3azJ4WWprWSVoemMrbW07MDtCeyR2cDx1MUQtNDVFYlNrOTNvNipXSUh0YjRCIyF8VSNXX3VE
bXcKei1Pe0NiSDlEQ1JhPXdiJERuQG5OSjxYKVZgfEk0QEAwezNJbFVNU3xUU35fNzVlMk9RVFRn
NyZvbSZ8VzUqRT59CnpXSWQ5QiY0X3QwNTdTdElrRl95eiZkO19qK0hROGYpbGgrY3QpRmt6V15S
Y2c2JG0oMGhkaXBZQmRuXjFtRzFTcQp6I3R5bX5XXilLVjFkRXZaSykmPDl5VkF4OGlJR29FT1g3
flJuYnZHaXc9SnhfWGNoZ18qYnhjNGJfbmkhRWN0PkIKemV+d1dkYyY2WmV6VXVqZHpAfWstNUQ1
WihMNThVKSt1ZHRuQkhOfllpPzh9NjlBI3xDJCZvWlU3LT44fGNBM05fCno3dCtyI0ZNanVMbVYj
QjZTKl4kK2tVWnwta2MhcUpXS1ZmTz5+OG4tYGBLclRtdyE9O0kmaGR1dnRlWTdRSHFaQAp6aDlL
WFkmMkJTc0cwMVRCMTVsSkZMYCEpRGBWNl94LVNEYWxDdiVlcEYtbipMVVE5dm4jP0ZnMWxASDBU
X3pXMGcKenVhXzVCVj8/T2QrbCpjIWpkentMWVp2fHhDKlRXTDxoNCp0ZXBwLUg+b0pNQCVSJm1L
NF5mWjk4JDBQQVo3WWxQCnokaUJYWCNRRHEweTN1fFAzVyolVThVWEJtNm84IUgwbG5fQkZBX28/
e1RwKEpjdGtrb2clK0FoRjYxdSFaJHpxUwp6UkJfMTB1KmpvZmM7KCt1aShAanlISkRSaDUxfnRR
KlV4SilDO016aUZvO3U5PnRvS3FWLTVtJXlJPEN5YSYqeWUKekE5NjEkQGN1VzlLZXxyc2BRPj9g
XkNKN2c3YTs8TU9rKUdkNX0rbktXPVlFNS1lJHlKN0BhZCtIenJDeCswUiZMCnorK3lfZz9GWXNN
WnV9dDN1YWBZWnNGMHNiYjBNIThveUtqfDtYNmNvcjJhbWxiK2B6XnY2bEN6Pmo0OSV7YFhOTwp6
dUdwSTBGc1UjTl5RKWVkVmdmMTNkI3VYKFM2Znt9SmNnUSMpfXV2az1kbz1VZnJUXkFueXhRY3U9
SVFZbjQpZmQKemhuMG1LVSZ6VnY5ckZtem4pdiZ7KXRGOV9ecWY2a3F3fnRXdSsxNF5sMighU0M/
MlohJTtufis5cGNzNzE/WVd3CnpZYipiQUhYZ3tMZFdoI2BkUDBicG9aUkZsTmFENUlmTjFWSTZm
NVZIUjNJXypVMHRsXj5EYSFnRUo8ZkpQJVY5RQp6TjYwTm5yX3JGWXRSIWRrbTg2Skk7TnFZTGp8
M2RmbX5iaTRXd1ZnO1gtODE0NC1ffVZ2IWJiNyR7NHY9PWwpUE0KenV9bjZpeWRMX1RKcH5ZZEo1
cHg+fEloITM+S291bT0jYCo9SytoLW12I2RnMUJoajB2K18hQ0pxUGJnZnRnT1J7CnpPeV5GMDd9
NGs5SzkxNF9gK1ZoUD49KSRqb3BlJmhxTk1XcTw4LThYdX1mVSYmfis5NXZNM2FFeFZOX2hjfUA2
UAp6NTYqbjMoKG9KTSZrPilWaClsdkdWdE50ZWFsT1lDSGdnSUpkTmVrQypqb3drNj9JMX5OQHw/
djdVY0J0QXsjKVUKekFBd1YwSzZNN1l0VkVTMUFLVGxvSnpoZkw8LXE4YG1hT2J+KlZLN2VgOGBx
MG1JQlYhPmMjbmVheiVIcCgyckY3CnoyP2BqY0Imfm1pMjFDXnNrOVNIKDh4SkApdmRMaTdKbTwt
KCM2bV9iIz1aVihmUkNzPCMmPDNETlE7Z18/OyltYwp6anhAQEkrLTdffHNUTHo0X0VeXjhkO3la
JUY7Uj48M1dzTkVTWlhFeS0mWTR4dWRtYD1tU2VkJmBxNyg/Ui1PJDsKeiF0OGNPYnImLTkreUZ2
RXN2QGw7cTY3Yns0SUBkV1dXNj5tJTMhPTZ7VX49I2htWjRnNDljWDEofVFgKihzdHZyCno0YVVe
TDtoUn05UylWeyphKTNmVTFCWWxYIz4jMUJVeilUJUpzWU19PUZ3bkUlR203eW90dH1wMERAd04z
Nl9jZgp6YFModzx7a25oJlkyMlEydEVMcD4zRT1gaz5jJFYyPXUkKXA8OW1uND1meCMkaUIoblgh
cGtDdT1aQVRQbGArIWQKej5XMXRKezlgeytkaSR8d0hqTHdGM0skRUZEeihhVmg/ckF8bUAjPW9q
alVYM2UrQzc/K31+bnBSTyp4fWFHQ29FCnpEdHoqWk1PMD5AcXQtNSlFN0JDPlJ4WSlvQ0JqMmZ4
aihZclZMYmw4a2FzQnB1ISt7Wl9gLX1hTzZQaiNteExeaQp6RVE5KFRtVndNJmJUcE5IdWkxSzNG
bVE+aEJDUUxJJjtwQ2I8TGsjUWJQYXB3bWl9OS0kZUB5MmdTbj19JFNUal4KelNHQTVjWFczYEdQ
YXBIRTI8WHZBWjBiRE5eO0h5eGwmcEEmUyVaLVU0O1ZqdVREQDYkWCtGc1RCS0w3LW9BNmZRCnpn
RjQxQWxXLVhwMTx6c0tCPChIfnFJdGpge1doYnxjVDA9UT5ePUZmc0dISUcqaCV4MCh2RUMlZWpo
Y2JycT9IcQp6Nzs9Vj5jWFp0NUJnKnlhdTY8KGRGMEF3JENHKmVDbiZJRXooOGIlNVJZZS16NUFG
I1VuezV+fSE9OUo0JGdCKmwKeilBOXtzVEkqeWRhN0R0UiR2RGUjbzJEfX5OVHU9MnFLaD5jcilL
OT0peDhESzRraXk0X2VQb0slRipaaz8kU29kCnpvN1dIOFgzSH0kXlQ5aEtAYE88JHlPTWNWbnw2
dCNDNlNPZ2JERzJkRFF5eXtwWVZFUT5LQEJXbDRlTmA/PSVgQAp6Tj9UWU9LKE5Va3wxPkVZNntU
an1jT3swVmhpISF0WD87bGchelJ+ZT0tejN5Xjl8dkE8cTA8S3s+O3F5b3hPMmsKel5qYCUrTyYq
X1o7PX5Ab0c3JmxxJXVlRj44MkoyZnZqSDUxbCl2NDh3JihsSjNPRihZQipyNC1WNmF3WSN2fGck
Cno0UTlSNHc/UzslODJPT3ZoKDJPVHgraylnPjZIfnl3T2NSPjI0eXNMT2sjS0QhP1lZcmpGdnt9
TGgxYThocXVSTgp6IW1RZDMwWX5mNClORUomQUA0fkItTzlkTHZDSEF2ezxpeCt6TFZfVlItVnpK
ez9LMnNIeFp2SVFDVGFSRFUhczwKektpS2VneTtXVEYwMi0+Ny0tYD9kPUpON1BsdGYmU0JSWChk
JFBJITheMVJufGA2JFFAUkYoK2BMRihrPlYofFNmCnpvWTRnK3k0VW8pO0RtNC1zJDJKIyFqTmVh
b1A1M1YlYEQzfnVGKTMxdm5iIVFEQVYyeU9QIXlrXkFVfT0xPn1aZAp6cShvbT0lcHwlRjE1JEYm
ZVI0IytvVURPRyRPK01aaTdRN2tNMXdiUml4P3QkWHxQd3ImMFNteTl+VyhWQlEjPTsKendGenVf
XlNQYC1lb2hoOSZtYkFhLWpYb3xobGdxc2srO01BbDFSeVY2ZDhIV0tOI2pSdSNfV1dPK341U0Yy
S3toCnoqJm5VbVA5YClPZXc5WUBhXk9nQUJiVTZ4cHFlQVd4O0ApJFRnbGxER3Q5TlAoVnomWTtl
YDI0RE8+bV9WZEJaawp6PnVpbEFmPCY8cGo/Xi1WbmwjaShSV1hsR1h8VGBLX09vKEVDdCpfUSFV
PisqLW9wWigla0YtPExHK0FaWHBuTXgKekpFcVRfez1ycGp4eWlfJE98QWxFPGxve0ZWeE44Uzx4
eCo8dllXYSEhPjF2ZWdgMzFtXzBNSHJyYi1WOVAjTV5YCnp3K0BDRzx+WlJQcSszaTEzeSFUK2Uj
I0BqezNZIzRhLSttfWt5fFpQdzFrS2xScEo3NGF8MUNpSWA7M3tBMW1EUgp6M2AhbXM8JlAmRmle
fENoZ0RDRkFoZj97KXlSJF9hJjc0JkQkRUk+ZGM1RmokLTM9S3JjeCtgNl4we19IcTZMQnIKeiF2
KDtGVkN0aTR5JEk/OHp3RmQoNHtpI2RHdGMoWi1sI21DbEU/MUNmNE5LMkstUyQ1QGNaZj1FYTxL
Tz9iVUltCnpFP24/aDNlZ0UmP1c/SmUxT2FhfVdpM35IMUM5Sm9FfEBAaiZKR3tBdzZEPXh7bTMk
VnhGeHImeUU0X2pBRCNVTgp6JHw7ZVZCPHx0b1Ize1RrPWg5UWhaeHBRc0s9K0Zze3MmNyNIUz0x
LVIrP2Fmbzw9WXQyX0ZMbiYyUj9US2FGbGAKekZ0ZUw/MyZTa0tIdXx+bWo+TV9wQGdtaHw7SDlj
OUN9KGQtMTkrQG83VSRIOWZqKmwhJHdMSjFlO25XVEc9dWxSCnpxZ1ZNOGlebXF2JStSQj4hVzxx
NyU1JkJ5Tj9IbWw0UF91cm5uZ1F8M1ktQ3hxd3NOOyRDQzBsTlZiNDA8ZGJSUwp6OEhMcWpWX1Ng
KEg/Rk8hRT5Ke2I8c0xtKCZsezwwP0c4NGJRcFMpemo5e1U1bjw3ZUNLcD9yMCNGTytodmImWWEK
enJtN2swNihaKlZ5ej1MSTkzZDl9PUxGcXJoKEtxQSVONEJoaTJ6bGNMYDA+dy02U0Y3Tzg5JT15
Vkw5M2tDJXZuCno+NzA/MFVndTZCTlBLfXR7eyopLSVWJVZzLU0kTGI+Pk8kK1ZLfUpZWENmZzYk
I28oSkh4a3R5QG8xKkwxYjE4MQp6ZU5BZ3tEXyt+dDEjS042Tk02bmQwYk1RMEt5T0RYIW1sSUR2
cT5XenJONms/NyNBRz1SVGhhUS1uMFpVbk1valMKenZjTz1mYUFXZEdMJHIhfE1SYW1VWX1US0Y5
QFlBKVBhXzh8U2tBSl8pKytTQlhvZkZpUkl6VUlVcURpek5AWVgoCnp4U0s1cVJsWVZaMkQ7OXRk
VFkxYztIZUFBUmdSYTElVXdpREFGTT9SUk99dWB4ZERBPzdYUGo3XjJhYGJFYHFrYQp6c09gNzct
cnxFbDZBOXlBWWJMSVM5XlNJTFJ4Yl51Mys+USYjOClMJE5hJm1mezBMNEc9NVZgQk9ZbUYpWnxC
fnEKem4rO3RRd0NOWEUxRCt9MF4mJDZqMytfdiNDSkwmb1MwQjUrNk05KnxzVCRJYz1HY0dWYykz
JTVKaH54ZXZieFRACnpFUUh8YWZ0OEpoZ2NZRTQtZTxHaVolSk4rT35SMVQyaEVgT15HIUlPWSZr
Z2x1I3xMZT9gYjA8eHBldSRBNXJ4Rgp6JGNVeHYrd1RjbmNSUnJISEc5eG11S1I5UGJ4fVJUQiRO
TXBnLURsVW1WQlI2b1duKVkyVGwrancmKkMlLWwpY20KejgxeWRVWTsjcGFzSX1BeT1lPCM9KnJI
NUUpRWF7UmFKRHt5KGUqNG9OcX1US3hnVXtAXjs4bGZaKHtiX3E9K1Z3CnpoSTd6YUt3UG1NaEt5
UkM+QThUcCtTczRXd0JfcEl1PSZ1NCp8MmZAOUVjdWFWTnJPNSQtUD0qaTYjSSFlc1FjJAp6djdO
TiljcX5hRDlRP2lJX3gpWmFSXiFEbEQ1Uig5TUkxZ0Z4K0JrVGc4UTxOdD9+RW9faF4mKCpRWHk9
SktgdjcKej15YXcmZXRvcFFhQnRzQS02KDkqRFB8az94dVQjO1htXn5eckU7NVpzdU13bTU8d2RA
ZjI7N04lRzNgUV5kUkVRCnomfiZkLUhyV0F3SVYlanV2ant5YE5vbilgd2xecGVDPClSb0c/VUlm
JTd1RSo2fXNXcyo/O2FAWjE5fXtOSyQjYwp6MGU4PyUpRiErS29Nb2NTPVNWcT9IZnEwYDVxS2FI
bFBgOUprYmRqPlphanpUJUs7JmxpTjdUIXM/ei08aj1SWFEKejQjMVNtIS12ejFWSWdFY3hUeCs3
VEsjVD1jWHpJZzg7Rj98OUx6NmpPMHYhNzRGTmtQUSMlQ196TjtqcmZpMFZMCnpkTG5OPWFINmFP
P241KnFeOThwbnMtRkQhQXtTPCNXKll2NXtpeH5rI2pwNz05VnlCNXFjRDc8PDc4dD11c1FSZAp6
YSVhQGYxX2t4SVhSS0RvQG9aNHlDV2FZcXlfVUEpKnRJbTBYfiFWfT5vNmY+KlBvOS1zTyViaypr
VmxKRiF1cDMKeitMQT9AQnQ4TUA0K2JQZ0hJIzlkKHhDNiZ6fkY1SFZQb0BhYGN6PFExZmB1R3Vj
SiZSTzJ5RUtQYnZDZXkjUHIrCnp5M0h6IUxeMk88OyNTOS1he1pEVDlWY3ZGWT96ZHA+fEh+cmx9
ZjA+PmNfckdae1NeRytxUD5lR2J3Qks9ak03ZAp6ckx1e248bDc/QER1bUVFdW87YGpRaXllPlhI
djlBYEtKakxHX0s/dkRLTj49bTA4cU58STRxJlFNfiNMP20ka20Kel8renMzaylka0t4T35FQFM/
QU5zTFNrMD8zN0owTHJJOCZOWXlFK3pMVUZsdGtZQCFhO2pEangwWVR3JUMxfVZqCnpzZW91ZiRZ
ITFUb0FgO3ZAalNPTTZPcXNwWlhySEo7QVd+USYjSG5VZjgxVUVkc2JkTktDMSVYYSRRUyZwSVMh
ZAp6bzVQfDRmTjctTmJUfU8+QUBZRlIrUS1WNVN3JlNzc0xVRVchOHk5WEZWX0UlPEQxbk9QNTVw
ayF6M3BiYCYtVl8KemxtYVhPIztNb0JGQkdOX0s5ZShRdy14SHNXRH47VEFuNVdgOGEten55dVZD
VzJ2amA7Jlc7LT03MndYeks3OzReCnpWVm5XOVJCdFokUzJKPj5Qa283IyNkXzZyNDlsQHUzMjJu
SV9fPTxNWUY8ZlVCTl5RY2tiVEEmPHNOMTIhaHlSQgp6ajY5c0BDSXFUbkB0WG13V0Y9ZjZQMDY3
JllZTFJDaG4kc1I/XzZNKEgydWxLJVlvcENIZjFzUzVTdVpAKUhQZEEKenkkPD8oKzNRRktUQz4+
fUg9QElyWGV9Q3NaQiVKXztgQEpwe1VKNUxzWS1EeFVPZHo/KkJGaD1fJTRDOWhDc2t1CnpxWCZH
UnJ1S0gpPWVHVHVvSC1sS1NlamQrRD55K1VDLWRQMmV1PVRkSHNBPEM7Q1BxNTJCWEV2PypZdz4p
OWZQfgp6azZYSkQ8IStvcFRAQ004dFE8RztDXnNrY2BQdTAlcz0lTk1FPlMrLT8kbGc4MSl8Vy1T
KFVuY3s0Yjw5aCZfclAKejNvNXluTEE8TDhJTithRlooKVZQc2pNYkZjU0R1TUx+flFva3JZWl5p
Rj07aXwxSD0hTHJJSmBtVHVXQmhOTkoqCnpWOCN9a2h4NjhlJjFNSGMzRChTYnMxbmJ0O05OTXdo
e2JzeSVvbTRUOVZ3dU1Pb2MmSUJkSlI8VC1md3hyeE9zVAp6XnpNTzYzNntRMzM2QEwpY1VEVXJt
R15pRikmKkg4azMlS28pKFVwdihIQzNge3soVURgUiFXPmY+TCteNEFTelgKej52aGo2KHY+eXIq
LVIrTiFRbnNXVTx7UklVYl96WCY3dnZaR1A0STglP31KdCtga0ZJRElVTWtuQUJicHZGcTFvCnpT
IWs9WEshfUw5dklTQTR4KnV7amhUVWMwY0t6b31LYmQ3MG9eUGo9VkxBJUlWZEZNfFBFYm00a0x4
cTRzVVc9QQp6UDt9PyU/N2ZTJiFCb0RiLT9EYFNHc1lTbS0rYXFvMUVYUmo/UyQ2PktlKzhCPkBY
XkxzdWI+WDFmPFVrd2YzUyoKekVNMXt2SilGXiFKfD1BRk5hY3FRO0R+JSQ8UEQyQFRtdiZEak5O
NEl3ZUIlWVhBe3IlRDlCVTVESCRHdDB3NT9CCnpxfi09a1l9V3YzdERXPmZUIW9tRm1SMTR7Py1h
VHhlaVA1SnRBRT0qeU9iIURPZkxrKHcmVSZ0UWh8K2NMYS1aYQp6Tz93KSZBKXlaT2xPMSUtRmEm
dT8jclIpKi0+d3F7WWRTSjVATURWb05NN0V1M3dhV0ViVlZBYzQ5VnsrSX1QdjsKeiRaOHJ3PXxo
RWJhNHdVPHpmUFchaTdsSj0pOV9+OWNMJD9pWTBiTTNzY29LKT9ycEgrUX5ufFgybDRkTGMhdlBa
Cno1KGQyaGUydTEqb2ZZOTB2en4tX1JTQXFNMkw3WEErcklnMFBWWTBuQVdDRWRkaTJ8OTF8Z0Aj
aFc+Kk1UdHVeXgp6Vm48N00hfWVmPUM0V0RjLU5oKzI3ZyU0cyVTXkdBQzREOXdgYE8jYGkqJkx1
R3ZnYT9iYkNLJlAqSEF9dn5NcDsKekN3a0M+MXs3UU1qQER9fCh6SVBNITI1KUJBJXJjPj5RJFdF
VXE1P2AydioqfDhAKWN1NV4/N0dMZHd0dkZ7NkVBCnowQmRzVW1BZ0tpU05eOCNlJT58eFJIJmhN
dmhSYT4rMEVNbCE8IU05Q0U/NzQjLXNFb1E5TW1TOXNIQipzLVp9PAp6fE1MS2hibi1YIT52fj1f
cXVGWk12djtkSmRWTXIpTSlzXyhxLWNKMDE8enBLUiVpZGxkNmJzdXRzWTJyUWh+NWcKeipXSDNs
MkdYQW9taXcxVihudm5ic3VWRSYpRT9pN0NvYzM9I3M/Mnd3XkxvNnJ+MlU5VCNvUjJjMz82Qm5I
VD5kCno9N0FVV1F9JE5gdDExJik+bnZMI3kheztUdl5LRCFUPWh1Tj4yMlJHKGs8fVM5NnlfNHNY
NzQrbjlBbmU8UUhJdAp6YCM2T0xZKnZ7aXdJSm41MV41YiU8bThlcEpBRUs1UFFPNCZwMU5HRSZG
U31qY0dSZHAjU1k+XmNwOHpeVn5QcT4KenZhaShBZDMtQj48LUYkcSFZX3h0PVYpZHJ4fV9iR28j
QV4+VmhESmBuKzs1VmZZMTgzOUBBank0SDsye291YVp6CnorRTFVTUJwfGlDV08oeCV3OUlfdS03
NGstUHM4VEAjOUx8bS02OXhKUUBFfH0xd2FqJmFWKkQ9N0B8Y0hCUFhofQp6NUxLVzchJWYjQzB3
TmJ0cUgyOXBjMldEUVlSKz41ZmhzU347TDJwJmRkWmBiMThraDA+MkBHJiN5cF4yZEV5cHwKekpT
akQja3hvY1FmOX5tSE5KaCsoMn4ocSRzbjI5a0psQSoyYXJzI2lmYUdhdFE0N0RAYTxzIU1PcmM0
aGhWMStkCnojZ2Bza2ZaeDQ1bFdmTD1VfEtPQjtDcnZLMSVTQSsjJlEleXtBTkhTeUc7fnJGQWpV
RHFSMzs0cnxKTCojPG1+ZAp6SGk4a1RKcCMycWw0P3E9Ml9ZVWc2c3o5KVZDTWRFVDIreVZJeDRp
byRhOCZFUD1gOWdRMytTdTZtUXhEXkZuYEoKenZwa1QkWkRYeXRIfWhWfEt7ck44YH1RVWg7IT5Y
anRtWmVQe3VMdllWQXAtOT9rOEh2WWFxYHtxcT5CejllP3xYCnpSLVozMk1uNUQqJEplIzkwO1p4
PTAoQzFePGloeVNvMWY0M0g5Q0h0YHFpeTRvc3g0PmtebnVVSy1ZUSl2fDwhZgp6SjljYlBqIStV
YCF0d2RsRlVXMj98QVFxbWcqfipCZzhtejcjbC1tIW04OV42PSEhdUk/N15oTEJ5SF52Skg+LUMK
ekUrV1dWMl9xQDlOSFgrQE5DfHZeKTBQeFcwTkFjVzNIRCl9WXU2cHZXJFRlMF5jYyR5aytJeClp
ZChPVmRuQXBVCnpSQE93OFcqellgIXxYSmVeeHpAbjE3fURnP2JzYjdjU21TNmRGYHFhRitsTHFM
SyQwb1JWPENDYzhLJTJre3h4Ugp6TTNCKDx2VT10NjAxYFBBJTMpLVJqITxpLV53PShhMkIqZUdg
PUFeS1B7JDZwKjBZPExVZDckUVA1c0U+NmpBNkMKem94RHZUVzcoKTZwUT1hOU9RUVpART9DOWol
fVdBJV9KIWIzYzk/bFEhNGMqWERjSjl4dTd5NzFyZDgwNGomaUt5CnptKV8zUGReUldjKz5CLUNw
Znt9akQtfHVoaSVKIzc7NkhSOShWeVg2VC1qTDt4YFJFVTd5Ql4pdXBYST1XPk89cAp6ZEtaYGNF
MlhXSEteVnNmMGRsbjZ2LW85Pml+XnIpWmE1U2ZtSDN7aXl3OTk1MjYtTCo+S1Y2antrN2ExTzYl
fTYKem8tcEw8YTdDRi0+YXcjV1V9PkMpIVheVz9pelZJSEJlO21IS2RpY0RuKUs/c1diM2VeNyli
QEM+WEcmYWFNPHZMCnpfJHY8OSRNZl9ZOT5EPHMjYWlPdWQybml1QyVxOWoqK0Y4R1pzfG1HXnwm
d0Bpdlk/YzxiUV4ybmhoaUlYNVhCegp6Nyk8Rjdra1dvOHVDKD9uKGNjM25eUWpuJUdYMVE3K2hL
R29YPkdqd1RjPF9GQndFQ3heaDxiSVA3IX4rbkk3YkkKeiNqfkJ2JihrPmtTX05BV2ZkTlJNPkdH
TkBiRjVCQWt4emtyQW4xWkU8S001Q0smVkZ8d200dmM2K0BCZGRvWnRvCnppWGg/LTl8N1R3dyV5
T0A4QjB0KnZNdyR+eE9qSzZMXmM9Y3szdTBNYWh5WDxXZFRvTyZlSHtlKXgtdVlMWHFKMQp6KEZ+
PmgoUjVLYWlXaD9YXzkxR20oUDlUdDRPajchZ3pzYl40JkBYb0E2bkg7WF5aT0VGR1M4K2IjRz5x
RHc/SV4KenckODt8QD5pa2Y8dzBAYHteeHNTTFFqc3RHKGNPZiExKE1kVn1lMEtkU2A1akU8e3h2
IUcrbz9XLUVTNjQxS15lCnpJeiNhXzA/c3hNUzBRVm08dEt1ajcmczJiQWhqUSRHSyZRVkNIIVom
bWAyOUJMQXVTVDRFJGYoa0hORmZ7UVgkTAp6eFc5I2xXKm1jfWZHTktpNVApZDVhYDAyal58RTQk
cEdnNjxIZ00yYyQlJDR+KXphJWZORGZBSFRAfWQ7R1kleCoKenEhenclblh7PSo/SUs4RygxVmhC
I08lXzBHWDxOUyY1LXl+Y1ZTM2NET2R0IUlUYD0qP3tBO2V1fShCLUtGQ1MyCnpNZCtZYiZTRkBO
eUplbT5rZV9Hcj5iZyt4cyY9PmI3QHdCdWF3KjVHVkV0P3Q3PG9eWTk1Pkx9VTJnR1Q9ZURxVQp6
dnpMc2IwJkFrS3owTHAoeCZpUlc0UE9sX2RxWlR9aDgrX0IhOV4ydkBzZil5M3RUUkxYRjtoflFY
e3lwTjAwcFYKelh3JWpBNj5zXyQ1bnUpYCgrZ358QXl3UUZtNHNAV2hqbGxBaj9+cUJmcUtGPVM3
SDNnJThWc0h4en4xJGBxfik+Cno/aG9+RCFgMX1rPzZnN2BTeUFOdWxueWRAWk5ANVheSzxMUjBL
QGpIbzdwRUVUbFk7UUp7JmY0MElYSTApez03awp6MyEtPHRLO2RXKmNRSE5YNlkjbj9YKit5QFRg
PC1YRW5CLSU5ZyR4YFgqeHsrb1JxRitweW1teTRkWiQ2Y3ZXP3YKemZRan56QmFtMUxsVWEhenNN
NlNkN1pwNDdZJHJMSmg+cUxTKyRBdlUjQkQkaT5xM3BNKHB+LUJiZmZKWD9yNTJsCnpUNks1MiMt
cz5DS3pkVT16KSZsPXB0aCF0a251cmtte0JIZzkwcDw1dXw1PD1AO2QqQSFLYDhSV2lIVCF2SUp2
LQp6UFVRWEoxOEFwenZuKXpLYENAbEdOeyNrZlEqeVJJY0tSRFArWShZaXNXO3NETXxjJEotfW9D
RlBoPGdpQnQwZzQKekZ4fTBlZDlZQktJZWsqSShDMjREeDhIfWpSUXtrPSFmcnxqUFozIWQ7aGpO
NW53MkMrV2RXMmx2dFJ7ZjtHXjd6CnomYXo1NEt+d2VQWFoqO3I3JE5iNmlNRXQlPjNAZjt5TEtl
PyFRYWh1WU5QRGRfY3N6fXI0Y3oxZ1dqOFY/M25xPAp6aUttQW1LeDB3YDIyNE1rIyNUUCQ0cmp6
N2o3PDZ2cnJqeyt2Qno0UTJUM31WU3J9QGV2cHI7RkJSZmZUY2dUcGUKejBMX3JqPW9KZ1ZoYD87
PjNWM1JwQll1NXwmcj00bT8/Z19pMHl1aTZWeXdRZFp5czZ1MXBoc3tYYiZBUSF2bU1LCnpMKCVC
YFl5YjNjT0MzbC0jamRwOHtxdk51LUVaQmtEam1lUypMP25mSlo4PXRTKkFCSj9FU2Y0T1MkaHw9
TkZ4Kwp6SCFlY3hEJWFITDhRZS1EVzQ5X1JXWkdPUntHLTNlMDVSKFh7IURpOEl7WkZLJW9ORD09
VDR8MkwqfEtHRXR+TU8Kek9jVikjKTZNRXB4NiRiclpwcUVfTkklQyZYXiVCd28kJGcpU1cwZT0y
bTFBTVpWMnN4ak0wMiE4YmN3cXJ6PX1XCno/SlJDRzc+X05TYzJ0NkBpK3AqNjRWWTZYZ0VaMlVo
Wm8rM0xrITw3TnA+fj1vI0FwQkEme0FLVlR6SE5lTEp8PAp6LTtMZigjd2szRG85MnplPUQ5V04r
I3p1TDtUSG1OcCVaTTsofjZWJmx3bWIoV2dpM1hkdmgqOTErb0J9TTVnNzwKek45X1FvP2t3bj9o
eSYldVh0Xj1YR30pVzNMX1E3JiM0Pn5YRl5JbFIyPFE2bXBIazhPMXdWbmZkc09oJXd0ODJ9CnpF
cVlLezlxVDBpPDcmK1RfQWpjVUNoKmR5OVN6MiElXnlgZWl5OU9iS3FJPXNqRWEqPF5IMmFBRi0t
SjgjTUMkRwp6JmdyJnZWM15sKjY8aypIdHs5JHFLezU7K0gyUHBOP1RKbnl7dVNkMz5DLVk7S1Uh
TVRHc1F0VEMyPHl9RGIraCgKejdxTi1MeWRJVSE4Nlo2YVRlaSYjeTY/NXJIamI4IyFBQ3F9MyMz
e1N3OERwKUFCZkE8aCo2VW5VRDVBIz9pa3R3CnpUb1NuQHglU19qeGx0PTB0XyEjTUVwUX45SzMo
YXUjeFBRREYzNTtIOEMpY0txO1Y9Q19saj5qaGtsT3ZRQGhXYQp6WVp7MTI9KmQ9MHcxRERJJWp2
KyQkYypjNShIS0o3N1BrfDcmN0txU3d7Ul9BWSNsKHRUTVRRdTR1T1k/TG4jYTsKemUwRDd1Nz9z
UDVzdipmNW81bFpuX218TEJ0MjQxY0xkUXtPaXQlMmJZfVhlIWlRKlcreWxTIzhyJmhGPEM7SHo3
CnpIKzEodS1tVFd9bkxpZl82SWFmYmM2Vjs4cE1SMWJpUkA+XmFQIy13R2Y0UypvI1lnS01ZU0tE
QUpuUVJ0b296cgp6aiFhJE5BeTh2QSh1cEBYe2ZJI0Akfk9QMzg+diZAd1Z0JChyWUtPbj19d2NJ
N0lCaiMqdjViNz1QaHxYO302SE4KejQxV08tPW9NaU10NSFTZmotQ15hY0FGNFljKytXKE1UbnBF
dlR3YGptY0pIS3c8KDtOek9zOWZZSio7YlklRGUwCnpiP1RlcWVDbjZMbz1Dakokfil9fllqPWhu
cT1takhlREdvYVctcjt7aD98UHdpciQ1bm40b0tHVCNRQUNaZV8lJgp6Q3xnd2ZxaGMtTzF4TEVQ
KSlYJHlaWlpRVTR4aSk+MkY3JT9GPSE+c1lzeUpfK3RtaEAtVzJMbkJWJHImTF8oUzsKejxqJkJa
eyQzSCpRVndmKmk4SHdIUEI5KkQrYitPM3A5JHM2KX4hSiYrLSRzN2xUUTk7S1ghWV5tJC0xWmR5
IzFxCnpUMD9KXk0yJE5YbVROaytsVDVXLS1AfjV9NDImP0hwfEVHZyFkdypRdStOPjtqcUNicCQm
SH1RZUApTEJMeU9YdAp6TXhNQkxjQjhoTDxqNjI3T0JibFVvSEZ0OUNLUShsNGZOdVlOdm59SURp
RFoydUQrY3tJXyVhezwqMitgTGFKdHUKengtPEw8SHczb152aD5wcVJMd0dgODJ7cWRROUpIRD59
UGxYe1MlWHw4RHNkUGlROX4oX3J2OztIPlZIV0I5PX1sCnpDZj1vPF4tbkNadUdxLUJQKTVoK3d9
fTRTKXpuKlRBfV9BZEkpcU5RUnxLUV5uanxlRmdgZj8yUTNUJWdwPDNDagp6X19PXjdLUSR9WXBP
JVkqeyQwKDxQT2J5aDQ7MWtLI2tOP2J5fExZWnRfJjIqd1YwV2FCNUpeNEhDbzh2TGRAKXMKejc0
Mj9RYSZQZ2pFP1loVlMzT3M4NTx5c0EpRj0oUyhiNDZVPnkoXml7T0o1K3ZKSC1KZG4zT082OWJW
VjFpJkdiCnpBTSNnMVVwLXQlTEQjKTlqQ0FtYV4lMkFVK2teQDl6ZXdhaGhSSGw4VDk7aDRTV1p3
b3F0bHNrZGckP0BgYiF1Mgp6VDBYY010QCl6PWx5IzZge0FMe3hAWUNOP3g4d2l9an0jYj1sej4q
VFYpWnpec2lTZkUtUCM3blJASGNCTEp9QU8Kekk/YjFmKnsyQ3s/UWdoPXdmM3dePFp1SzxkayU+
MHMoe3RKQCVgdmFHYGx+aXF+VVJZWV9EPGBWKEVxRHN8b0xaCnpoKzZTIT05aVI4UGRVOCtIOXNQ
NlYqZiFscnIhO0Y8RzU1WG9ZITx1c28tQXBjLVZ3RztqOXU9QlhYaWQzOyYlfQp6JmJuMjU0fXtz
RmE9KDlsYFl1a3NOSH1uYW5+VWU7YCt+ZDljUmAhLVVDNz58aFQ3bHo1ck1xKTR0UGFAMnhWISEK
ekpuZCFPbVdsWX4+KVkpQkFGNDFWTmdNRXw8YHZ2Z25iZFdJaio8eD0yI1p9am5TLUomaDQxP31X
IUkhIyFxPEFVCnpQPGJvdWwoYXFiQW55czBjJkpnRHtvVkZrYyZJNj9AbFU+WighYFRrU2Zse0J1
YmJOQT14NXVmSHMxJkxFXkJ3cwp6RzxIMVBxT2ZRY2BvTigwVihKZT5aYUR3cGEpWjFuTU1BR1dx
YUJsUiQ9MiRoIXh4V01ITGE5MTRMZyYkbnJNbCUKenVFO00tWUxVM3tVb3ltOGB2dDtzUlBoM3Jx
dXgyTTVNOSNyTGU9blVPTklOUGsleSpMe1oqd0AlJGxQSUdtOSZSCnp7VjhPcGR8TWpjTkQwMDYk
WkIjQk8hYms4VEJ3RnNyNDJrWUxFc2spMyFJNmAkcGZyfD5peSlpKEhUYDs5MGNuewp6QmJNdiY5
LUVfPmErNm51O2FeSktefjRqeTw4PlVhdHcmYmdNaDk/eylqTXhkSXlXZyNMejt2TllxNEchPFNk
WUIKekNnfXRnVFVJLWE8IzIqQGUoe0Q9bTh4VC16ZkNWV0l8NDsoTzhUfEB6djxRUmBUY0lAV0Bk
ZldNIWExMFVvM1FOCnpNRT0wYDtvPW54R3h4M1NpTER3ZTJneDhPNUFxKXZhJEEhcmJ8TDhAMnJm
byQ+JlRmOCNILTReNHk8RTFtU0o4aQp6TTUhMGUhc0V9TE9MdkVFSkpWdjIoZ2UpdSE8IyQzeilt
PTJQS3BmfXprYj9xN2QxTChOSio9fUx7OTJlb3ZRR3QKem5yN1R9TUo5K3FuYWF2SytvZn1nNjY5
Tm1LeEFndTdhd08pUmJxWVRzP1lZRTMqPVZEaSN9VDNVN35tYSNsM1FHCno7PjVTTiM5RW5iPGlt
WUMwdEYzfiVsUHxAbHZZNjNfIUNwSkp4SjghYkpjZ0tQMzBSfXUkd0A7SEU8VD9xcSpXdwp6Jmla
aCopOG4qaXhTRWBUP0A7XnFYTkNDME07X2E3NktyWjZpeUN+N1psTmIlQlIjIXRyRjJaI3FTOXQ3
UkF8c04KejRfI2VPRT5OXlIrc1NvaTk3JXBkV0hLSVZic313JVRYflJ1WWp0KSpDTUNLPl9IKDs0
ND9kPlNKe1Y7b2B7UTI0CnojYjc3VmBVWUVNQVBJSkg9SDgmKl8hYkJjZjl3LV5AXm1HZnsxKnd2
V3xzTlF0SVdraDZILSZxZ3pSYTxyQ2hAfQp6P0NNdlE+Myk1cU40Xmo5SkVDeCg4c041IVpUPSlA
aHZjMilqWi00Um85Uml5YHglLWl2djZGdFUhe0olJGopcG8KenNuMnwxSDV6RjdQUj19YG1DRHI7
Z3dvR0pPezJ0P0VNQn44QT17KDBnc0M+fT1eOE5VeEB4KlUtWjhLeXN6cSQzCnpZbE9mNnVaK2hT
cXFKZj9pWE5TNGA1LUo5c3UheHJZUVdVMEB9dGh9Vl47Y3cjaDFvSiUjWVluOFUoNUdeMSlKZwp6
JTtSO01Ackl1fE0yJEhUR3swSlhzPHlGKlgwYjRNaXtaMkJjZW1VbUN8MGlsVTkpdztxKEdmbyR9
eD80Klg4c1MKenIyJmI/eXgtPFRVdXUlRj0qb0ZIRjcqQ2RmQmR3Rl5UcEApemUmcUU4MWliJlRD
cDtYMX07Zl5MPXNnayZ7VWVBCnppWDVPKTl6dkdBRVFrdml7ZkZ9QlQqaX1CTl4mfkMrSnNqUF5O
TCMyTlM/O090ZkVzMys4OWp5cEk9fT8qdFpGYgp6S0NUKXJzVCF7aUtYO309WmxRN2c0RDV1eD9x
SWR2ZEM+OT1kSzE+Z3VJZiRmNG5nKVBeaS1sRkcqYE11UT14fWsKejBXdDlERl5hO0I7cTVlTVNs
VXV0PHJaKiVJUUEjYlFJblIzaDxAZ3tfTllgZUg3YURySlYrUSZzS2lKN3UyWjxaCnoxYE9MP0xg
RTJ0aCNPcWNObXd8VCQlJSsqbS1XVzNXbzMwU1N7JUd1OypVaV4hYEI5RE1HaH1uKXZFKDxfKT11
Kgp6bHN8ak5acGAxaURFSmJKNmZnQHAlX0xAcyZPJlh1VTlxZFpNaFdIO2BJa3FGMyZjU0ZmMWBJ
fEx2QihsdXhgcWwKendPaypGZ15LO0R1TFBGa1Z8R3loUWFEa1pqNXc1NW9LVSYhd0BZSnZhbTlC
VXlaPTNnY0VgUTQhQE4/IS1MXnYjCno7MktqfipTe1N1SDs3RHB8SXZacXgwT3d5bHo5QGgjKmJo
d2s0JHRpYG8wM25wPjRfYD13fnFIQ3A4QSYydEJmUgp6eWZUWn49bm08S1UoPjxWQ0ZuSlJ7TXVw
N2I/czMkMT1KKkI3OCF5NmFzIzE+QXEwfFhOJjFnOzZ3RDdkRjRrWnUKemxBQWskMm5ZQ24he3kt
R3NQTEpPcCp2e2QzRHhyQlcpKkBucko7LSMyflM9bEwwWFgmR2cpYjhXfWEwSnlOWSFnCnpnMnh1
YndLeVVDMS02IWQqXjYxWkphSD1BV3NlcmcwMHdyXyQ+RHN9N3ppSnlAQDFDbWlBUkomazdsZkJN
X01Bewp6MT8/eGU/TFV2YTh3O099bCExd2Nie2VTOG5KJkolY1pBQyVCeDc4PHp4Xik8dHd7ND9J
dDNHYXhpVWl6UmMlLUsKeiZQLWh8X1B5WG4xZ0klNXFtXzBGZVkxeHVxYiV+d3FHI0h4WH59Ml43
al5gdGd7eiVJMT8/X0JEPDtPTFV7UGhSCnp1aGYofnlAOHFSYGh3a0NeODFmRTNFQDR8e3wyLT82
Q2s1VUpqdjc1Iz0/REFHb1U2fnU5TmImUm53IUw1dUJ9KQp6YyQqOE1SdXZQSj03bih7UGhSRWty
MUY8JEV4RGUxZmwhOy1UcHhmIyp1WWB0VE1VNG5qazJYdiQoKkgrM3tsd0gKeiUhKj52IT1hMXUh
KiVoJXBJNCpkRyhoNCgkaG9VZihDc183TEdLQXNySzx9djsmM1R8cTQlNU5VZD1LI21kP3g0Cnpo
Y0RPKEVuVTRBWXFASGV6Y3hAWF4wWilWSnZ5JWBDT29FX0ZWVGRiaDtxc1plSnYpakgkRT0qTGRe
akNIXmJyNQp6N0J5KHtrPWQ5JVlMP2NGK0w1cEhRUUA1OHZvfmshR04zVEdUemJAJnFpPTlXPCsr
WFNWLU44UyZrTisrQUhnST4KelVTPV9KUlUkWDg2OTxfSnNBODZpa051Mi1OP3VJSClsbj9lPTl1
X3EtTjFuZHVYN3JZTF40MEdWdW8yNmIwbiooCno8aUt1PEdxezMjSHp9VyRPTT5Faj98eGhEMUNy
M2hndHZSM0lYUSMxJFJSSGtnN3QzXmgwc2tHOFhOQGZgNj5wJgp6Y1N0TUlOWkpPRV99YHptRSZU
RyY5PDVSe1FiRyFuKFZVMFdJbn5MRmRLNnpqMmMpZ0pJPz13ej53YUJ6emYkM2UKeklhRGNVTEBx
IWYpUEAjPk9pWllpUSt+Xmp2OEBZXnBDKilSIV44PFNjOCNJSGFAdykhPndzZHR5elhQZ2gkcXhz
CnpeZHhYOW0+fVVONE1yQksyfT13Vy1GUElwWjRJV2U2KFUqRW5aR35VbnAtaTBxd3lyN3Q2cT9s
JjFMaUozKXEhLQp6NjA9PkM1MDAmSyUyUiNsbllxa3BFTD1tQzZFKiNRP1FldVZeTUdNdiVFSFdq
RSlsMlo4bVE7I2lSNFNhXkltXy0KekRJOHAhNjRaezJSdnQ1KGwzejdtOSR6YjMhPmBYRHZKenhw
OEFMR2BgUDRgRHNaVWdsVWdtY353dEsjc0ZqMVRRCnp3d2UtMlJmdCs1NVNFd1BwWFFld0FjayZh
N2cqRDU2O19CMD1OanxUSDVwM0JuUUpuZVc7JT9hZGRqbjZANWA8Ygp6a3xpfDskMUFiNEIkSmJl
PilyOSh2QDh+cDRTPX40cGtNYkBaayZqUlF+Mn1FNz05dEZeOFVQZXRNKnFNdWZaPmsKel40OH1U
ZyEpQXpfTnU4OWU+akl7RVYqeXRpVHlrakdjZ2tzckFUWjRWKmkjdSU8PUVfdzVlZmRUQiFeI1Ym
JF43CnpWT21hOyh6V1Q5aHUjKXxqQGptZnBEQ0VeYlZCVzFIM097QClwcXRqYEZ3PmwyO3U3S2p3
RTJRPVBiS0lPc3NfYwp6Q3ZBeTFKS1poUFUxMyZAQTtaWiUhezEzN15eMy14RSpsa0QlQVFSQXMy
KjBNQz5nWGY+Tyg1T0woNF9UNTxFfnUKekg+dzFxdjIlYiZnRjUoRGZwdVgrU0NCLUY5MU4ydUpQ
aWplWmlDVjAmeTFOQXpOcyomQiR5WG9USHpDfDMrZD1QCnohVEJ1N2ZaJVdNS1R9UDBJd0V+dFFg
OXFaZmcoPjJkYTI7fD42IUdDZylpYzVrKipSKjlFc05YOGU/OTdFVUJQcgp6d1N3d28qZjZzZ0A5
clklOV58XmNgbC0tVDtQVFl6MnNwWUYpeXstJSRAfGdDJCM2I3lRR1F1N21VOWJWUWcoT2AKemJy
TU5SNT9gKjwqJGkqSFhibCF3bT1rNzYxPTJGbyVBamZtZmNAaWdeKlIqN2lFcWc0VjN9bCFhX09g
RyE2TiZSCno1PyNPRGM1ODRqMDRRT2JKOGk2MC1uXmdUejtEZitLRW9AYTFUQ3pMdkV0c2tiVEUw
eTgwUmNJdDJ5Tjxpd2Y2TAp6anRJd0I2TTNvXlg+d2ZoVkBDfmhyYUhlR3FhKH1IV3RHXjZWMn16
SjYocDdNKXtFVXN5QFUkfmZIQ3wydGpeOGUKentOeUxXPylyVWxIT0FDJFM5eEB2ey04bmhnRnkw
dkVpbGJyVGkyQ3JjMj47VW1fQVZ8aXtlY3pyektSLWdGZXc1Cnoodz43ZkxqWG9gX3JYSmJmaX10
RGc2ayY1RSsmbEZiLWxNcSZRNzI7dWNyIUdnNHZeY182TDw2aHdUMz0mcGJyNgp6eWFxaFlzK3FW
U3FfQTtoRFFNfEBFNTFeS21ialBwUF5TP0x2QXYpRDcrVURrWDhNdzgzJkJkMTE7bUktVnlGRUwK
ensqSEV6Ky11ZzBVSH5vVTM8d1gwSH00S2NLKVhQT3tjTUA9QnRiQDU9VWxuN2A9JEs3PDBuVkJg
P2RsbyZJV1RjCnppfDR6dmwkeWp7SiV4VlRgfEJHZDV9MSVKTnF0dDUpeE4oQCp5eU5WbX49ZkYx
U040V0dGLUBPQVd9aVYoRmhjOwp6Um5gdj0xZHlDb0d5TWlFNk1iJktFbExkcDltS0JsSFRiUExx
aElAYzwpVzc2UHFhUiZySVgrc09qMU5WUnE2eDcKeiNxTGlDdkEzS2lUK314LSZCXnZ9PmNXWlVF
SmNRZytjfEooYkZ7dElVZUpkMW9hVGxRUGI3eVF4PSN3ZHpobndICnpjTiltUCtKbTlSJFRpQUxi
JClZWTZrP1p+Wnd0a3JAODIqTmskNz8hbCRxTjBaK1NZRz1qVlNrJXBVK21iTShVLQp6YmViOShU
JGhoKns4Z0UoZ14mWCV3QmFSajRYaFJfZ2w7Qm1hKChhUnt3fX5uJVpELTAodnBYJlUmbz17QTh3
XnUKeldqWDdoZWpMZVZaai10QkVXZnwwJVBUN2A2SGg5NkxwKUpgQ1E5IWNgUEQ/dT5OJUstPmB4
aFBCdkx7TVlHSllDCnpQbWRmWCtIYU9AYT5YZThAaSh1PWE5UGJfQj85Klg7XislT1kjcn1sTTMr
QXxQeEFPMFZraGwmVH5xN3BMM1FHJgp6bXIodGs3b01BNUA2b3IoeXxHYSlXc2EhQXZUciFva2dK
ZkIlPnx4RTF6enFKazVATk49PGdLKjslby03YCQ/Un0KeiRgVzxuYzd3dEtVc2AhQEt2T0ZaU1ZE
IT5Ocyo+a2t1MmhDWWlxe3d3NVhUUjtRITxwPCtra0l0dypacU9fXj9oCnpHN3x5Q0ZeNkNscndO
a09DY0UjNWJ1UT5LS1RLU3dRb0NZKSpAeTdiQ3pjJTVXbiMlbCs8OExjQVp6bU5kY3FWRQp6Q204
IStjcWchUUEoUkNvI1dAbEB0RG44X3pmVjd5bC0pfCZweEx9NDw0ZDMrbGRCZW1HJU41c2BrV1Jp
bXVeaXYKemUtc1UpUz5BO2dEKjkyP3luVCV8bU1LdDhVRkJOdzN0SUd5OFpKMjA/aEI+SCptS3x8
U3hZQTcxPyFJUnFZfUwtCno2MUB2WSpYdipQXzRqVkxUJjg0WTlmdmMjVkRkQGNvdmI9MUMjVV9f
bn45Znk5TiU3K1klR0M/YEpmT1FFYFZJRQp6STtINlFZcn1pMS1PaiRsd3FUPCYoQHFGWG9RPCRY
Y3NORkljWkltYFQtLSgxZCo/fSM3RVlsfUVqaE9XeDNqdWgKemljWi0qQT9XRz08VDYlVUxARV4+
ZXEkNWlEPl5HI3p7V00yIW5TaHpveH1mcEVsbGZAaGdjel8qJlc8QEpNKmNqCnpZZD1HYERffHNI
QW1BdilkXyNWOUMqMj9gSlomSX5AV0Q3Pit5VjRaUiRqRnsyeV8yVGYmVGYrY3VCST5gSSQ1NQp6
OzNVeE4xUWNqOW5JbzF6QDVjPTQ4aytxWj9qSE1lYjE9bHd3UWNTRXgtWmI+YCQ+MzsrX2hkVDhG
byR6eVY7Py0KejwyPjdZJjM4ZmY8Pmg3Q0twP2lAIUFDU0tPel99V05sOTF+dmAyPm0rOT5rP3A7
fTlqcHdxbjlqe0Y+LTJKVSROCnpRWFIwLUB2IXpIQGI+bSo1c2wqPzEwSGYwNm0rT09LMDRBUXRt
eFE7bFlrdD5MRmkrNTJKd04pKy1JTX5nanBvTgp6bjsld25KfDkxPDExQUdPdmtNIzVfNDheJF9Z
UUY2bFItKnlNLX1kXkJfI147Um1Md0hmeks1MGtmUHRAZUVkJTsKej19RTtqcVBrJHotdExiMzQy
Ty1VJSNHSzVYWVkma0xgey0lalpVQGg5VSo5UWZYKTc3dTQmaDFGeHZWe0E/VXFGCnpxSlIyZDZo
JCF1RkpicTlXKERYbjFvWk5wdFpVLWdtcTdRKWl6VWdGOGsoRjBod0ledEw3KHI5VG45JEt5PjRN
Uwp6K2w3UHZfQ2poQDRwdnc3OW1YWnpXKjAhMCNSNns9YjNeMjkrZ0ZzeEc0MiFGRVo7P1FJJmNv
TXBuQGc/cDRPMDcKemNSX3dFX31ecjF2PTExRlJFezFpKDh5SDdjJU1gQHZBLS0xaUM9azdpciQ8
JEw9RTUkK0pjNnxoWX5qezhkXkkjCnp2WGZjai1uU1VVdWlfc315d15OQUkxeEA+ayt5QndyaWx+
cUtKfUpZYFIpQSY+ZXJvc2ZCO3tIM0h3VUU/Tm40VAp6d3M3ZXpjUXFDI0tSLVd2aHhzZj5pPXAk
fDI7b2U/K3ZuTnwmfU5DdD9HelgtODJyJXIoMkBGallTWjt0P3FtcEAKeldZU2YodCgrQnVlO2Yl
YVg7QzZ6cG9YI3ZeJDhZPUlBaVo0WW1TJThoMGM1THVJTEAyKnh1bztnO15uY1VldTdSCnphRjM0
SEo+NVh0KitFcyU+Y1lhdCpHaHVRaFEyMUU4KHg3NGdZc1pYP1ZKNihCOzlPfThQaGVkbSZ4fU1F
JkhGLQp6Q1Y+aTBNNTQ+P0U+dnEwY31YUGdKRnpQZ2NrQGpoUHUyeyVacjUxQ1pOZGEqUz8pMUlL
QkQ4SD9qIW9mdCEtX0YKeis1WHBNNmtTKD8wPilra1loQk8lTHw1dmNpYjBeVS1CbG5oJHVRd3tK
SCZJcl8raHYmJmZqR3ljMEtoJjZySFJRCno0ZlBieXRFZ0JgcFBYVzdiO0VwRldvMys5KVExaUNk
bSk/bXItIWNoNGlIUH5DP3tNWU1ESl9KQU5oM3Y0dktVMAp6bWcrKF49KE9oSGU3KW1rK29ERjFZ
JCUyLU5JS3VZY1p6NCEmUy1SN1I+Y2hjP0NneHk9Kzk8VnFQb34hYE5xcS0KemNQR3pSKGhKU1o2
Wkp0eSsqIXI+JiQ4VWswVmc2PXs8cVUlOHl5WXtJVl8pd0VJTV97eDNXbU47MUhDKkY1RW9TCnpH
b3MzcDZuSWJBUipxUUopO0FIQk1TV212enBJfkJkbW5zJT4pTG83TiF3e0h1RnJXX09tbCtPcU9H
IXBhY2QjVgp6ZWNmZUhaQFpoJS1UMzJxKCYhTk88QSlrWT5ab3VlYihUQTBrJnojJWgtI1dzXn5r
SWR1V1RtZmIlQzYkTG5UVGQKemBnZHMpVkckN3V7WkB+cUlNZGhkaEs7QTApWHJPJUF9emJ1KCta
cnhrUnw0bl8qVmU1QDZ5MygxLU8yYjt8fF5hCno+KyQ7Zk0tRytgUThxZnYkJk1XK0xrMjZIQEZZ
a3lqMGt5eS14U20/KGtuVFpjdTI4e3I7RFNYS0ZfPihHVypvZQp6NklsKmhhcXIkZDg3TD9XXis3
ayY/MCRGcjhUNUtyNGNaZzhSQUN4PGliMSFwUSt+d3crRDdzKEVmYXhyNVBRaD0KemUyMyF3QGZl
QlI9V0BIVjZMTiF5aCZXbExHZ3xKQDtIUTh1Klk2dExmUWJfcDlffDB6UXJzeGNNdkVqd1J5WiMm
CnpYXj09MjgkUSVya3cyNG87czduUHdZOE56TCFrTn5zS0heZj4hZEZDP1IxfEt4b2tmNi0jTCtk
QkN6aGhIfWVkVQp6R2JMYVFLIzJAbnotYSQrMEQ+R21ITFpFQWxzVD5Wc1dZWHIzPyt7aVN3bVl0
bCprbTtUKik1dlBMXmVkIUQhaHgKejRUdzFiKDxFclpUOUtfPnRAIVgjQW5aYE1DOyFlUzRNczs2
e09kX0ohXllpK1FJMFBFbit3U0sjV35jPSVLQzg1CnpufSUwRkY+MXNPdThIT2cyez1acSpNWE9r
dGtsNSpwRlpFNilPQj1wbkImVnFufTNYfUdoM2NwI2J5PWhFJE5WOQp6MzRpMXApPjxqbWU7djt0
KEhROzg8NFFJfU9VSnhweVBMRDBiVH5BX0R5PX4rVGBTMFdvIzhKUFomT0I7WTRyZ28Kei1Ybndh
MEtROUwreWFtfEVqWnt7b0V2Nj8keFV5NSUwVVYzZyNRMUE9dm5tRmNSbHtVITRLI3cyR0NZKmZS
ZGI9CktZP1pXR0BjI2tiY2BCUiQKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBh
L2FwcC9yZXMvZWNsaXBzZS1tYXJrLTUxMi5wbmcgYi9hcHAvcmVzL2VjbGlwc2UtbWFyay01MTIu
cG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAuLmVkNjhkNzEzYTgyNzVmNGVjZmE5NjYxNzQ4OTQxYTkwYzBmOTQwZDcK
R0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDIzODkwCnpjbVhWMTF5b2VlX2tYKH0tUUJVJmlYZXp8
JDBDUnpwcDs0fS1RQmAyQWV8ekooeEhIO3EpNH08Zip7PWBDRFBLZAp6fEthPWxwUikodmQyaTt2
bzFjNTwmYiVte2ApWl5fT2hnYV9rPXw4REolQXVNeFAoSWxjO01lWi17RGdUR0dWLW4KelFxdUZ5
KnFyZShmM2pTUXgza0tePk5HTEI3bnxBMHNWTDYqeEFBKGVCQygqTG1GR0xmK159Q0ZiKGpZbCFM
UXEjCno/c2RJU2otUHNNKG1QOCpsPzEpREIkd0hKWlJORTc9YDZ5cmk7Tkh6QWxHYlFeIT9Zej8h
JlYrbllva3JvREojNwp6JGpHOUskZ3JDamFJdSNGMU9KTlB3OyYyaU5fYEdJMiFZNVdgVVdZWVA8
cGAoNUUjSHVmZGYlZT5SeCpXYVVjLUkKemlYOyNVZ2AkbzgtPXc+TSNzZFQtajV1ayEzejRYWU9T
O1hVJnMmazRAc25na01uMT9UJnd2en1rQmlBTj1GVUZDCno3MUBxXjUwPnhZO3daWF9LKkZSbGo0
KlgoM0ZqfHp5UU9AT0E2R2xNOUc7eHI+RU9DbUQpOWFPQlZGVFNncDl0dgp6bXRDNGN7c3g3b1J3
KjgyRzhSYD9HQ18zd0lJOytyRm9ifjtSfHlZTnFKZjclQ052I0Vwez9fO3hieD9iY0xTM0sKeiQ2
ZFpZQHxWNW9HcXR1Vz13dWBHY3YjJFQ/PkU2QVpwZ1E/U0M0QjlSbjhEUT04RCgmO0tEZCVCK3Rk
THQ1SkxuCnpMWEY0MCF8XmtsND99fG9sNj9pbGJxJGlPXj55dU9efX52aEl5QUl0MTxMeVJ3ck9O
cWBuaCZZZFYtOUAyZCQtYgp6V0tDVkRXUFQrSTR1WU9tNih0JUAwdF87ZUxYfFNGNzFFX0s3aVFw
eSMjMnYlO29TfGY2bUJ0M3U4WU85TlN9QiUKemAjXnRsZHwrVnNjcmMyTzYrNmg3ZVdFRm1xe0tu
U0EtPHpPZ30jPlRLbXdpYyFPT0BwZXl9JGtXJGlDMCRvYm9ECnpeaztnNjFoQFAha199MmsrXkRM
XnorQCE4T3RlQilrZmBlQjZxNXt+XnJsSmhhSmEjWE1CQmo2UjswflZSN3BmKgp6aE9XfWokeEd7
P2NqZmlxNFNEbz4yWVl7fSV2Z2RZTUk+MVUxSG9QLWo2Kj5hYSlkdEpGZjglQlR0XjM/ZUsrRFcK
eilnc3orck9KSnVKd351ZWE4blV9dnZBfEtXR3YzM3NXVjA3ZUcqWnAoITlnPGdZTEVfRlNWdzFy
TS1DaXNNS0htCno/QHYwdkgyQUhMMzg4JlBLUnBXSzRwcWVNOEhEJDg7JGZ6NTtnc1EmJT59TXpK
flIrOGFmPmJPXjNmRWZOfmhRVQp6X0c4ZU5YNGk8TkxjayszRTBSQitnRnlKTHJ0cCY9V2t2JFI9
PmwjYVhEV3NfLUl7T3R2YCZ3ZSlHdmdgTDJXcE4KenpRTnhHP355PGdSYDdZcXltfGt0T3JmQXot
OUp4cz5HblQkUVNzfF5haCFCPDIofD4zQTwxNDxseFBNclN+JEowCnolOzxCT2t6bTspIVNvRWFx
ZV9wSnBYa0hSYlFmY3cxQTxeS29KWnxZcTctRzFfR3ZzbW8zSHNWMlc7VEZ1XkF2fAp6RDxDZEs3
bG9qVDskWEEhPHcwbks0TytoRnZrbzF4NCgrcF5uJX1MI2RNckxGbG4rYD9GPzNjSEEkWlh1Z35S
dzEKelFxTntvKVNuc15BSXElMWAyOXhrTnAmX2U1dVA/LWdtU3A2V0dwSSNHYkl3cXtLTlhUcWQy
cHBjZkVEeClhekpnCnppOT9zX15CcHhJKEZCKCo5MTJfcyU2RE5mNGxpK05nant4fjx1YHFIJj16
ckU7Tnx8fVYzNzxCNWY+R2lNfVJ6fgp6WmFoSDxebF5sIXpNVSs2V15sdEAxez04ZXdvdGF0Y1h6
UTVmfiZfOTRaeG0zbEVRRWRLUXk5SHZ4fFJ3P24mTD4KelV5Mz17UHAoTDBtQCszKSNBY0o0YWB9
fkleMVEzMGQ5e3BhSyp+a2NCTSlvMjt+fSVARGpHJEZCcWREVz0wam9WCnp4ZDtyP3pJX3puKztB
QkZ1LWI5KnhnVX14aTxKbkVrfU9RPlo5LSZHM3JoRkpoXyNCQjdjQzNmKzF9bFUxK3R6JAp6YWdP
OSUlOGt3ZTdpQiUwXyY2PDFxKE9eNUteeDQ1dGN8RGJWc29VfExoPG8mbHUoRzUlNDJzPnM1QTQq
Ml8xY3QKellZe1V8WnMrZiFuKE1HVzxnIWxYTXlEOzUhR1hgOVZAWjV5dGgmaTw8ZCVjSGFpOXY0
Q1RubmVUVFBUbig5O0JrCnpAYE9HYStfMjlPRTFURzQqTG93bEZoK2lITGFxJkNBYzJjd1ZDTGt2
cGAqU3JeIUFSPSsjYFB2QnV4aEc4dTw+agp6MDtPJmc2QTReaktZbj9pVVo3I35ZeGRrQjheb1R9
ZygmaFJmcUorUWIhLT1OWUpCSFFnVSFZPkxtVHlGJXxDXzAKeitaVTlfUjhnbyQ9MDFgLU9QPlpF
aVhBU2BDVnJhdWMzR0wjSjh+cns8PlpsPEp5P2gzKnBDJEpZYmpoX2VtMnx1Cnp5TE1fWCV1c2dp
NmVuWF40Vyh5fHRFQXxxQzA2ez0wWVIhb048TXFJcE00cUJufHomQmVNP058Q0JHUS0ySiRVIQp6
VWE4fFVZXlhrdTQ/PiRPSF93clc7VipDXl8jS2tDYjM0fmpUM1JGaERtSCFSbXlQNy1mQWtAX3E4
NlU7OC1mcjQKemxwJjtXPG9eQlFYeGhXYyNeO0Q5JFNrez9GYklXOD45RFZBVGxaZVNTLTI1WllF
cG05WE9rVXg9blZ6dzRhfncqCnpYck5mPVB0KW8wanM4cDlpJk9TJVhFOz9zJkRyZjIwTVJ1bGFF
QiF3PH5ebGszYm5GTkwkTjFJK3U1KnpJM2g7VQp6cUdVK3RWczs5Kz4rakppPVJhSFBDKG04OWd+
dEJ5QXJNZkgxITt8KGJJdFR0N3V0MC0hNmkhcDltSmR6THklSkMKelA3ZEtndnJuNCNGUnI7WEFG
S29kKFBFb1I2UzdhRUI1aVMlRDhQRmJKbkpTYFNaezRsWDNxcDFKeURPeE9Xdz9hCnpGUzlAYm5W
RmUhRzBsNWI0d0YrO15rQEc1SmtBP0BoJj02UVJnVmB3OVBrNCpIbEpRX3EzaDw+Si15K2A/PD18
YAp6dSQrfC1YYSV2JHY3PyF6a01kQDdGUGx1K157TzBJU1NUczJVYmRRSng7QipKRHlANEs5ZV9Y
Q15lZHBMZHRGfkMKeik/Un1zRi1LfjElfnJEeExkfT12WDQkMTNiRWB0MFN8SVUtME94WThvIUx9
bF4lfEI0YXpBMnE7aXwxU3BBaFlICnpDeFdPanJ9cT8mLVY7a1dQNUs3N18jfWo+VCV1NlBnejBe
RiltX3g9R0h6fDsqZ1o3YjRfQT43USgrYHBVPH05OQp6UiNzTjdlPjZNcXtoWE87VnojeGw2Xj07
bEk4I0JQdUpKUFI0M0NjSG1FPk5NbFZne0pzLS1nZlhPTipMKkUqRXgKejZSKFo+JW13PEteVXkh
dnQqLWFweW1Zcnc8NGFjbjYyJjJJdG8+YT5vdDRhX24pdm8jWWN7RU1VJmUqTER2emFuCnpjKSQp
VHg/REJHTip6PTtVbW1ENSV7SGw9b31USX5tUFNOSU1rakwrMEdWOTxqTTtCQ29vKk5rKWF8czlB
e1Rtcwp6LT9LcFdUZVRZe1FyZyhGeDdkUmR8TWFzOSs1bE82MWZuOztfeiVCdFc3VElIbGpGQlND
TyRKPj48QjswKX0pOFUKenUkSTc4cnxMZXh0QFlLKj42cjxXcERJVUdsKUNhMHRZcDNwNGd2UzJI
czlUQSFzYjdqeUViNkJtaTluRDhySEhPCnolSXFTKUlGZjFfU1d7UihNSF9gOEc5a2FKSC1PJDtH
T012YGBTRz4/ejZKIUg7JGRjJCRDOUhUNUpSKWZPJFZEeAp6dndqO2gzV3VJdlFaPyE5bCQ1a2RC
bGNte0NFX0EzdmtmPTR7QzFrPzZPQ2A9YTN9dlZnfGFPNyZHd3BTR0JYezQKekpAaX5iaWtabllg
RCpxM3djTmlNaGhgNH1OSVRhLVRJVzMjV1VTRCVqdnBjOTd0b199SE5yXjFWOWcodElTXkVDCnpM
fj9iYmRkXyZTQEpVbV5jViVjeGRDWmVUZ0E8WjtJVTk3XkgrI1BPVWFkfjEtZUxTYUR6YSN0VFNj
Kk9YfmZWcAp6PXkjWElnKmduZSQjcG10P089bjd3fUNQemdmM1Q0KWNtRkVPO2A/cl5GRWBFPUBe
KEFkM2RvR0JaT1ZnM2ZPdX0Kem17VF8oN01TI200RW9CSzxAQFp7THV9QSMhaTxURFk1I3hZPjch
NXNHY3ltKmg4NDFXa0lUe0w3RFVtJDlXQnBECnpwI3VHbjIzNkQ4e1dHPmRvMTNoQzdnd3o0eS0/
dmllJT5mWmUha2JMQVlmQUdERkF1b0khdlpNbjxnRVlLUlFibgp6bDNZRVheWS16flRISF9oNFpq
RH12bW5ieC1yIVlMRCFjYm5Pe2xjQSlKNjNydDdfVCE5UzgtSHJXKDhNa19YRGsKejc1K08mblFx
ZW4pZ0E8OHxCUjUmLWFmdHxSUXMwfkkpR2ola0JKKFdVeFQqYVhQXkJGR3I5OFcmR3FIckt1fHxv
Cnp1R2h0OVpMeFdKZHp5T3BncWhWYVY1JGVpTkRWYlhqOSNmfXQ1YntGV2dDUCpmbjhWJEBKYnxD
VDB3NG9KQFhUQgp6cjt9YTV4a2Y4a3dDenZLR2VZUktPfTROMV5iTWlMUS0hODEoLTtLKGgmMl9j
T3V0O08yJHtgZCtoO0NxSzIqP18Kekl+Y309VU1yOGAoc1hldmhSJHVmKVh4OWRYV0xxSFI3aV9C
OzZkY018TXJ5OWVQVnt+JiZRcmwoZmBAbEBQWD9QCnpLaG5NeDNrP1M/RkE0PklBNnZFOTJqOzAq
LXJtbnxGNVFtb05KVmReQlNUSzBGZndSRiFWSkIxOSlFYikoS01TUgp6OWdQNHJhSWIlV3w2byk3
I2gtMW52emFqRCZVMWAxOXlJanB7a2A8THAjOUhoJiprTHI+SnYqLURGWjw4Q0AjKmMKenUyPUo0
JjgqJUkrfV5CeTA9KiY5em44bExmSUY+VUAtbz9NWXFzaTRfVTBqZ2ZzfThYLXVaVUpNY0F7U0gt
NEpuCnpuQGVDQ0Ika3hwQWojJl88PGc5cXNpXj1xYFpHPk1wMnBKQSsyR1dhTjJfNzg9Z0N7LXop
S3VyTj1WYkM7b3FKOAp6QEI/Ty1nTS10V0B2RTMoKEhhXzw4ajRBZmV+ZXY5JT9feUxOUVY8cUxK
YlBfT1khTCFMMS0wT0hsZGF3WTdrN08Kemg/an5qPl96cTRUbEZyQXV0VEVtQk5qfkJNdzRIay1G
Q3g0em5SUlczfnRHeDhlbVk5TXBhWilkYCpwfGUyNGYqCnopXzNrVTFvc1FyZE0teF4qJlh+RGlN
eD9uVDJ1TFJ0WlBMWjxQcSY1KFNJa1dGSCZ3OG8/Qzg9ZW07T21QVy1vPwp6PDNWR2U9anU7QlVS
PD1eOG5oS24oN3k3KmhQKil9SmIzPD94dWtaQjJtPHQ2biY2bXxwWGxAYlp6Yl8xSF9rM0QKelcj
eEUpK1U8Nlo0c3NoQ0okQ2M0WEtUMzclNXp5OEZtVGwrTEgyWTs1IzZrJT56bCg0ZH1EenxSWXtu
bE96dzBpCnp5UDM0KlJsQDJJOzF5anlyNTlVMEUpQSFEbiFVRnRPLVMmO05DZHhoOXh8YHxnUmFj
aEh8bjRET0l0RmdhRWpqYgp6e3BHI1ptJlV0NHREZGpkT1ByallVallmfjQzencqN1o7MWFkfWRH
TkFeSWRhUTUkendzSk99UldLNWR+UG89VkwKeiE4SlpSOGFWekpQKyNHT3ckPlYmbF47dCZAeTdD
b0gqcWkmRiYhQmpxYjJwPjVocHdkZ3RUeipDMWc8Z1hnfHxQCno7UHNGJCN1eUx0PVZQaHliQUtk
X15vI2xuTj1pIUJIfHBGV3UxTHxQc2hET2pEb25BbG9PVEtQS1B1X3MmVUk8bwp6bXItQ0BITUc2
bVJwKyhRb2JueHp4UH5kZEJKbWhXbGgmej8xcV4/UHh8Ml4zcF5SXks2ejZiWEllckVIbjsrNzEK
em5QQG5QSHNeU2c5fDRqIXpZQWJQe1B+dyVjU3grKF91THA0big3O3lsYXloSnt9R0tzTmNzOCNV
RzR6QHE5QlZ7CnpMMnVWPl9neXBwZXo+JVhmUUIyWUp2K3dXPWxfNzZsVjIpd0w+P0w1IzFncCs2
RDRqIT0wV3FSPGVFZ2BBJCtQZQp6YjBBSVctYSN3fjFMTjhxJjdyWkRtTTA5YjJ7SzR1TmNMPF89
dFlQVTQqM3lxZk1pQ2tBcXBacVFYeiU/XlZPSGoKekNoJHJ8PS1YRjhyKyQjYl5LXzdmLXwyeXU+
Y3tGSmFrR0QtTyR7OWtOaGAqeSFJLX1hcj4qNG8yX3Z9SlI5N2dtCnowSnwlY1VlY2x2UHErSWQw
PUshTExxfERoYVU4e2l1YldmeV5lY3NFQWtIVkVoXz47c1VRPVAraWBMTmZka0dmKQp6U0tKYXJ3
NXlAPWJhJnBNZiEtI2w8NTNodTVlYio9RXw8YnY2e1JNbEkyPHE2RXYjPXFsQldLYkNtIXQhaUE1
VjMKej1PNyVDd2R6V15TamVLVkNxSVcpalNzODdrOCU+aklHJl9LZSp4YyYzbHUmVlRwKUxic1l9
QW1lNnxfOGZCa0JpCnpBYj9oNndpYFMmMWVofEQpaCRgbjBuZkpWaUBURH4lRSRqKkpzXyRtPDVk
KWdXMHF6bD1BPmYyVXM2JDBFKm8lRAp6d05eLV5XYHFtO0J+NlRqJXJgYTtHVDhga1VvRiNAQThA
ay1teVlAMU1SUHpUQi1rIXFfdjM3VXJQWC1pSUdWTkYKek89ckIydSteVD9UUmRvXipYSzFtYjQt
V0dhfFlueyhpOSpvLVpNM0c3bDBnaTZKRUpOWXI2KyopTiFjV3xOcGV5CnptWldoO1BLflF3MT1v
Zk9gVVhOK2RnKjJOdzZBUXxUfmVTU1B0M0QmaFA9VUBrZGNwdUhsQl9jTypyTnQ3YXZ7OAp6TDh0
eDNAMyNVX15aOUAlWH1RdCMtYXUqNFpFXzZIT2ppI1FgbSpJSCRJckM5YkxBOEE5blcrZnJeK3Zv
bWNyeTUKenVPTT9XZD0tenkzYGlhNSlEU0VQYjlIUlZoPWshQk8tSGk8e2wzYXN5eC1tSGV1OD1v
V3Y5K2Y3MV8wZi07QkxICnp2LV5wb0UmJjtfb2gpJWhiWGQ1Qm1oNnZUbmVYSj9oQlZifiZBKEl5
ZDA4QzBvNVVIO2tafD9wdzdrc0FgTSp+bAp6cGJYfVple345Jk9vI208Z010LXB0enxwXllqT35Q
N3NKcjU7KEt5JWlpOGdHbUF6Jl9Fc1hRSyRZUnUqPWV0Xk4KelM3fSh3Jk5wZ3BVc34wfTteTVNe
NGAzVkphMm5OTSNFaz1PKjxGKyVxKjZTV2VJRjhUSmZIcVBMYEIkdGNAPCpzCnpQfEJTZkxRTnUh
Y0Nxa3h3Mi10PHdSVmFYOFRKWndsTFl3NjkxT2VrLWNkc0RNNi1VPGtsKzxeUTtGMnpafihkcwp6
OzBoam1kQSlteDBDUzVlTDJEaWtgWUA8NDk+QzQrRiQoSWBZbkk1UWd6am5+MSoxUDxSSVdOUFZm
cDwwJCo1O0UKenp0JmJpIzZ0dVFxbzJ4ZTZmWjhZe3JCdVdsODhxMl5JVk52Sn1ELSNfbyNwZ2lV
bTFTdVFDc0xVNSpnSSYybzRpCnp2aERVeSpgWWBwSFB7MUU9KXUlVlc/eXZNZT5sPmlzSF5BcnNR
TFoxPnYkTndZRFY/SXpgJVN4e2t5d1Vrd3x2MQp6bHIzZkA4fj1NNFRxPHQjZ1UrYlcrVVFlSERQ
OWpqajh2X0FRSExZbWkkTDxWXn0yOWhTKHcmUFZqe0pVQ0Y3dGsKejN2alA7QFlrMVFLXi1eUG9N
MXRuQT1zUWtXREs5UDdxb2lqazUxQkZFPHhzejlUdnYwIzNEc3BCfWA9amxXNzlJCnpiMUhGM24h
Uk1ee2hFeVhrez15Nzc+Q31Eck9XTjI7MT9HY1l4X3N9ck9vNilYb2NzMmZvb2Z2c3ZIeW93b2Em
Sgp6NFNvRj03RWdzOTc/VFEqR31BcHBRMk4qdnpoMTFTKUdod09PVT1aQEclJjd7NU1DIWU+QFR9
aEMjUnd7JU1uP1cKejZrQiVoJktwJm5BOXlOekFDWVlXOGY2UzUhY21DV2tmKmxSaUh8ZyQ1MiZ4
ZmtgaVQwKk8+SDdASTUobD9JMkl2CnowblFDM3NeYWpQMHp8PWViejchcSNuQ1VvPCVoXjNxTDY0
M3tqb2Q0IyllTn4+THc9PjhuYio2IUNSbXpJeSF1Mgp6Xk11KTspUCRKcmVnQEpidHl0K2teOFJt
MGg9Snlqbl9Ve3c3TEl6ZDMwbmZRTWNOYkx5NyQrIzt6KFUoT29XLWEKellxWUZ+OFR3cStzYVRR
LSQkQUpQRU1KVXB6KXBBT1BePnpsWXZtMDhZfmxYMGE1PWgmRVM7UzFCTDd+Klg2YURXCnpEPVRe
OFU5OD52SG8jMlNuak0pZCNIUH1tZ2kmfkBzMXYwIT1vT2g0YDZqMmBUdiQ8PEFAPzMhej8jX0Q4
PXVBQwp6MkRxP3l1KXBkSmN1M0JCPmIyUz9Maihna1RxUGR7SlJ4T3dgLSZiKilQNTFLWG83dik0
OzU+dUU/blBYalA2ZiUKemRYYn1UOGo8UyNuIzlHMXJlcm1VTSVCJW84cSFfQ1c0P1NkRDlFN1RQ
bSpUclRvWHJFcWlKMkUqO0RHPi1pMX5ACnpGb00/IUt8Qm4+Ym4oZ3dCcEokLVlaVzEqPkolRnxA
e1N9WTE1OU1PVm9adC0rPnV8XjNFVHYkbzlvNVhOdTNMKwp6b2VQUGJRPm9ic2lMMlBpfEpYWWB0
JGg1N2khdWEpIVNrWUhpO14lKDZyNTJBNno1Rm5EPUt8KXQpVSRMVihNQnAKem09NWo4YH1KdkQj
cEw0UlZ0ITJ+MXZaTzIpI2t0NnhHYClWPUpZJE5XT2hYUlNGLVo5RTg/KTZ0QyFqaG9UPzAqCnoh
YDNjMnpMKnBFYX1kYkFHPTZjVDxiJT1CVHhpdldvWUJ9XiVtSXZEcDZIWVVJcXhRb2N1ND8kbGl1
NXg8NHo7YAp6V1cjPEF4fnJkNk1WVUpBOW1abkVhWEF6Kk59QSFwellURm5AKDRKcU93eXpIPEJM
QmUodkhOakJ0UWhrQ0hmOWIKejUhZmpDSTFVMmFxU0UlP2d3KGV6ZE0kc2okZyN6VjxOeFVzQUFh
K0wtTmt7QkB2JTFobSlXNEFDVkFVbmlYM35ECnpVPUFlVFBFI31XY1lvPSFBN2pCcyZzaWY9Mkgy
IVBKYl88JndiUnQ8cm5EekFqbVQ7bzgzcmxSa1AwKVIpYm51agp6VFUhKHJ6dEMkOTx2UTRsZiUr
eEtmIUI0QlklcGxWend3UXs2O2I/S0RRMHtMdkhZSEFZSzxMdT9KWm0wRCRRfmcKekBJSDNUPTtw
bndiNTZ5dlQ9SHFJeWwmdDYwRDlCKSQqQWdqcFFqIUpXXlQ3I0poPkhTUC0zKS0/KHswNSRUbk55
Cno3Tm14N0cjPGcoTUJLfXdYS1RgKUNLOCstRGJQYlFzRSYtd1d7V0VCd154QWhNcTtTajxmb0gy
dipSelU5cldGawp6KmY2PVRPVkBQKiZUX21DbHthPmtoK297SURacD1YQnRLZTtELW14UHVmPWlr
dGx+NlAmZmVLcTlUNj1gM207ZUgKek5KUWFpQ2dIeGExdUN8cU0oUkVxQEx+bVRhQSQpY1lTNjdW
RkU/YFN7JTByWXdEdFQpeC1qRj8tfV4+fl9LSX1eCnpEalI9O00rYjQ8UHZMaEg5a01Bczg1eFY/
bi1YN0lwTHRTdG8yN2c4OStFaF5LPjJQX0J1QX5veUI+fkskN0ZLfgp6MkR+RFh3S183XiQ2SVBw
JklTdUNDdEFGJm1YViYjaXpReWNsZWcxQT5adiUxWGomYHplbCt9WkJsRGxGYD9mUUkKem4xVzVs
SWAtcTQzNXVQQ2IoMUdNczN+NFl2ZVckd3NAflZkNHczd1hzMSNoMyh1K3FURXRiTntpYGBKbEV4
Rm93CnpIOHdhQEx4fHh8N198STA3fTRMUitRcEprWXRoO01SNVkkM3ZfTlV8WmBrQXs+fmxSbWdM
Z3gwPiloKVNCTD9qRgp6RjZDd1U1fHtYZT8wX2UhP2pzZXcqSDAtX2prdmpmO0JsPno9dTl4S14r
PUlKMTc0WkJZNWR7cyo2czhPYStJclYKemV4alpBalRBP3g3ciN6JWJiUCs1T3BSTyViWShxJTNW
U3ItKWlCYVhvWng1QHg7an57RytJT0sjMGhsbWlpajZwCno2bE5rUlF8RW5pU2wkV097aCgxT3Vg
aHdLV3hyRXZkXn4jQlc/YDVzez45OFFIb3lGMEM3fEFsRCUhTUNebHZBZQp6elVDV3J0ejEqMWk9
fFV6YEdSZD9KMjZxOGlXNWhXS3l1WTJeT3U/fHZebWtxcnZ5KzlmcEFLeCU5R0NkQ3h6TGUKelQ7
eChETmxJO3pWY3pZIU1OezVOUEUoe04ySik5TklVRDBsZjRiUEtLZVlqaERafSFvRGU2T0ZzTmNB
RzYoc3JHCnp0XjlBekRRY05HUXdscyFNYnd+M2goKkNxeTI8VHk7KkZUc1dMY1BYUXU3MFVHKHFu
UT4lZTNeRVlNdGUmYX5PLQp6VVYhKH43Xy00KiRLZlZQSF94NGpfIWtKUystQE1KdSpXezZQakgk
MVAqdWloUHBSaGV1UFRGcjgtanpOVTNfazEKekFuLSF4PigtMFdLXmZzTXIzdG98KGlqXmJyJmhV
KipBYGw2QUl7IUYwcEA5MGF8K1RqI3lEWjcqc3o7WE5FLSZJCnoyKkUxbWpjN3VUYG5+WlZfP05y
Y2U1JlgoUl9DQVZKV0pMYCZ2MUFiWk1sIW11Y1RGWSlRSjE+K3tDWG0oX01RKwp6NHxqPjVgeFkh
X0BDUE1+fEs5bkJmQHFQI3IhPnk7dEk5MD88RDMtWFBUTTExdGRrYC1rP0dZKzxhaDgmU245bHIK
elBKfWs/eTBwZ3hUOWRMOCojQ3oyQ2dqLT5ibVc2RDV4Qz5ibChXfkNaQ3ktMlU3UyZLQHh8ajd3
dXA9SyVeazloCno7dSg0NSMjZCE+a3wkdjxyN1BIYFFmaF9zOWw/Z0ZweyZ4UjUwU187WCZUKFd5
dGgrWDNNeUo0TVhTJWZ3ciEtdQp6K0FYWDE2e3RKWWlZY3FAPFEwKytvK1BQVXY9P3JYSSRVbSsz
dlpkOHY5Wm0zckRMTFJEZlcjbiRXeCNUMjRRM14KenFDIShNMkJxQUBnWlNefGFtK1hENCFJNUc/
SnMwVmxDeyUhfEh7OUdXZDVxYHc4NH0lVUFAfSpKTX40dXkhTW1QCnpjXmlqMFJyU35WazdhMF5V
bGMzR2UqZ3w+IzllWXp7ZTJWKyk3d3YzbUczJm14Y1k0Uj9efnwkR2NWUCFJelJragp6cl9UY150
K1hmZHYqKzBwUmc0UDlKNUZFclQ0ZXRiZFlZKXwjZERRKG0hKWU/VFZPUUVhRzticGArUCEpSntp
MiMKej4+eXJMc2x6dj8kMlIyMlYkOFd9T0krUnU/UFptajwtJCRYZHRTMVk0KTxwNTN3ey1AR2xs
RmpYeVMjWFVuX2JpCno0Q3k/UWJRPD1aNGpNKCYqbDZPdmxUI1M9PWY8PEB5Skt0OCp6XjYmX09n
IWIrQG5qYTx8SV5OVWk7Zz1reXkkcgp6QVZTcGpHSWN0bVNRZ1RwI1YkeVo9WDN3RkVeUlVlSG9u
Wn5SSHlgeEhHaCtfVHFuRCozT2t2Y1Z3XkczOEVNYUUKenJgRGs3SFhTIzdEP2JYbGgmPz57PDtq
OFFPNFA5JCpQXj5Bc0hxd1UhKVBReV5CemtEM3VrOzghTnFSXzB7QFZRCnphaVlzJGI/QmVMeylm
KCZYKGRZJSV5VjZ0NHpKeiZmX2tNQEE1dW9EblR3QD87TEUtd01PXzAlPD58N2hTUztMKwp6P30q
fmRmWlgoRXZmbGY3dkhscX5DfU9UQTVCI0hUc15DY200WGBINnxGSUhVU1V6TytgPCVgblE/ZTFz
eV9sJGYKeiZIR2lEMlRzdSUoOGdWPDNUSylpeDlQVjxQbFdNOWBXZ3lQKVNlfE83fnV6JjJBJj17
VTtmO2gzfmB0WHhFMl4/CnpXViV0JSVrej17R0BvKzNrRkpEVVR7VFEwUExKd0c5JkMoVmwtXkFH
azF2Q2JDTFlQNlBQWEF4ZWVTMU9oQDBrYgp6PjR9PkR3ZCY3N19+Y0lLIWdLR2JsX0tKR1dRa3Jg
ekw+RnZySU99NjE1JjhFWGpDeWIlYnVlJk9AKVB8ZXY/RGUKeklwMndyTjBAVn5lNGNKd3szQ09A
ZD1lNjVlQTx1UihRT3ZgbkwtX3h0WWNZfU1pa04wT0JrWihZS016eUdgUD56CnpufG5LKlokM1Za
RlctTGxETWhoayZrWmxkNFJSJHZ3QlNHMmY3SSNOe3JjKnN5QXx7bD5mQyRBUWlEdyYoIXYjRwp6
TiRSODBhZ3Bme3chZmRSPWpVLXBBKTNVeiRlTl9Gd2hUNX1fJjsjWV5meGUqcWNFJCFnNVJqLTNz
SlFHbkNzOEYKenFuI005Pz18NUh3NSVyaCVEVzUjTnJkOW1NXnJnJj5ULX1QZ21NNGpebVY+VHM+
QD1iIUIxRnxJVSQje3BjdjBACnoxa2JpIWBjPi1EKERAbWF1NXM7ZXNmTzghdzZWSVYyZWMyVmRi
SHJ5I0pIfXtBUztmenJWTXc7OTl3OWR3cURYegp6eHwpcUNzSitla1JnfWJ9UkJiOElAS2YqPklo
cGFUZjchbn5mLTlNRTxjPEhXNDI/NitSXm1hcndfYl9TVVgmd1EKemozcHlRNjdRUj5ASXc0ZGc+
ZyZ+Kip8NHFoWkZjSnBOO15IR2tCdDVOaVpBcGN6a3BBTzdrWmhpSk57S2pLPylHCno+P3Y9NEA4
YWdVejdiNEJzcE5qb0MyOXAwUy0zfHstbDxpWTVNbnBXTm0weklHVW83XkhQTyVvX2UqZzgoUHJV
Xgp6IWVBWXhwLUAyNyQ1WSlOalYqcUwmXzJ0Ui0tXkEmbSZ2K0hjaz8yamtVaGYwa1l8eHpQNSFq
PG8zeEoxWWxzWSkKej8pYFV0QDY3SjlkRm1NRWRAQGghb1IqaFZzRz1yRzg0NDFCbjdjZDJHOTM7
PzgqM3U2bjdWKHpyVGtTdnRFNWs3CnorMXBGJERfN1dab2J5LT55dDJYVz1DYVVJPkQxX1FtMjtr
UCV5cSlHZnYzMEFoKXN4NlpVS0NYbCNVQHFLbFd1Ugp6aC1XM1g+bkJsVThzR1gqcjFRRW9jeWck
RXdJNzZiYmpkOyoyIT9ES2BDZiteKUNyWkxDOCFTU2RtZ01rREFLJEkKej5DQjJ2dXBJQlY0R0JC
e2x+a2BKKlNOVnMzPXVOIVJnNFVyMmd+YClzX2twckB8UEl6djFIOXVAc3hUfEZGI1MlCnomKjZK
ayNAdDZ5NkNgWktoeXlMXyQyMWE9MygyeHRiakM2Y28qKCRhZHc9Tjx6O3BrYm9XTCpBXmJmZjQ8
RjVYNQp6eThDKEA2fiFGeUhlQkMpa2AwSGZYdTtnUjd5TnV8QF9WQTlVdF9+WDlac2BXKnlFS1Nv
cE9IWkV9Sjx6OTZTJG8Kemh0b0huYUtBcU01P1lqbU9wRGUqeiQxRChESEk+ST4rPk9uM1M9Nk9I
KntfQy0yUnpucFNTQkd3fVc7Kl5lR2Z+CnpBR2JaeEU8YnRMQGojUmA3bG1zKWt5YTR+IT88czg2
eWw/JF9DJFN8bkt9RDFARklIPmcjQVVjOTRgbHR2dCtoeQp6KHlAbEdXbip8fD5pM15XPmJ9JCFD
NERNSWx6QU9mZmRNbl5HeEc3ODYmQ2dNI3p2TFhKYSkzUUZMUk59KXJMWCMKemA+QTUyc2czJnJy
cHxMTz1ofnY4bFJwKGxjSkZGOGF9NUBuTHBkM1luPzxjPUB6U2hTWSVjQiFYdUYmZndJIVhgCnpM
NkcyS1BvTFJ7Kks+fnZWJjk7bnVVQzVjTztzRjFrPWpyfDB0fDlyXnpvKno/fUE7Q1BYSzQxMCp4
XjVZV2ttRAp6KystaHheST5nfXorSHNVajB4TSpaJEwwPGduaTs/QTxUJmRmSHZ5KSEkOWA9P3so
Vn1IPklAT0lCb01wPW5BO2kKemd1VSVUX215O2hiTTwzNG14PDcqWSh6PFM8bjxgIVIzKUJoN15i
MmFXWFM5VVM9T2NFOFIzMkBoTEhCTzF8fEpoCnpHM1dwQWtFWjw7YG1ucEJhV3cmKHpaeW1+Xj9M
SyU7ZT4zc0Z+MHpPSitoIXRvbVNZISloeks9a0BuPXJIVDJyVQp6R2x8JXtedFRQWDItcz0+IVMq
aEl6UXB0cExIPGBJSVliPm5ydXZaQjFUVGRGNTkmPXpDeDMocXRJRnF5RkFnMUYKelczNGthc2xI
fmZfQV5VbnRNSjV5PGsrPzYkeG5gd0ojdDF9ZW1ydVhQaEBRMz4xejs+JnA7cWNud21aP15SUnFs
Cno8Zz01YCpRKDloWDl8NkRzZ2E5JDY0YGVZX3sxcFJzeyl1cztBSmteY3clYTNnc3VNbShfTTF3
OD1nPX10dWlzdQp6ITdKR05TWUxsUT9XV0xZSFlFMV5Wckk0Y3d5WXlIalBrd2FrbDJmKlRhcklV
bH5he0BmVkQrTGhEO0smZUBmR0YKenoyK01ldnZ0YmtRaSU5bGMhREdDe0c8eEViWj1mQl5AITdm
QTFLMmh8SEh0MG90TzhkcGZ3MnA0Rk5QU19RVmFfCnp1PUdAZldHPzkpYDZjP0J7K1l1aWNCWUQh
K3xsVWUjKUJ3KzRiOGhQOThCaC0zYDhiRyVYZyYlLStEa3UhOF5MJgp6RTxDZ3E4JDBDeFA3YkdH
Uzh+fHJlI2ZIb0c5dFRtPy1SWSMyRkZfTFBHKCM4WjtlZH18NGtjQ0xtUiFeZVA1bGUKenFfY3dI
TWIra1BENUJ6YlRhPjwta3dEMjZtMSV0UU54UyVAXn1KT3A8ZDglJm1SSjFSc3J6Ri0tUy1kMDsl
OzJ+Cno2JEc0MXFyamx2dD9OZ0F4WENPM2VZRSEmb290PHgpQk8kWnltdkpTbEAqUVBGWFZRQXVl
STE9UWhFaUxjNEROdQp6K1V5ejUla01VeFJJOTFmOTV4IWRvOEYrQHFgZG8wKk5Ldm9wc2pIM3Ql
bHk4el8obkdYTno7MW5gRDdySl5zITIKenYqJShhVUhiUlRsLWJFR0c/RVJhSnp2eXooYHx3WEI8
bWpaNTxFVnlTO3Q5ejtCcEQ9T3ZTTyEkQ1pwYGpOVjBeCno2JV9GPTc4fGRMNmgjVXsxQkxHQ2cy
eGtvXllRNzw/dnxkbzVGWU9paUVYZGNKVjJhc20lc1I3ZkA0UjMwfGc+cgp6RXQkNnlscy0+e2Qh
eyFSdGsteS1lMjtXUFEwWGVJNF5TPV9LdW98KnYpQV5RM1lMejsyaTI9alJQZm5tPiolJSoKenxN
cSkqME5lMzJTfU1qMTE8KjRuTV9iM0dlQ2MlRTxLXkFgP1pffjx2cD59eUNqNkF8SVNST1ErPTZx
V0xFJj9ECnprZ3IwWSpLNGE7ZX1kRUVXN3JUNThKPTxSXlZnQX5QNjhoN0dDO1Eze3F8V0hZR3lU
PztzNDR3PmBiRnJwJTt+fAp6em9xXkhUIX1Vd2hMUHtJNklvaGVpfnN7SGlldVRJY2p1ej5wMyRY
UHZFOWZDeGRqYiRQMEwhcVdPKkdYYGA4Q3wKej1SMSFFbmFGO1pYJmAhJjNtbnY0WD55KnVaPXct
NGd4Xz5mOHh+KTwtQThAZns8MSF3YX5lQz8lVkthQkg5X0B8CnpOO3J4dG1HR3ZRLTlNeyVYbi1Q
PVc0Xz9PY1g+aDhwQzUrXmBga3dHNjlSN2l6T19VSGVeUVpgQE1odkF8OXBffQp6QkBKOExiVz9W
Oz9wQ1Q1bUZ7YUV5PSVvS2JhZj1YeEE3bzJxe3JNPldCdW9vb1otOHteSVYraj1SM1NkTGNJSisK
enheTUhuUStTdTlwYldUOVIhTiNQQHkkdmVLaEN9dHRiTiEwdDIlczFCTU0xUnFaUmgpISZQcCpt
bi1eaUN7K3JzCnokZ3U2WXhhYztOTUV9ZTI1Xl4xQHZ5JUZoNnpNTTVTcXNxdSZ2MEY4LThaTXto
KXcmaVdfZSVBKXM7ZX1kLUZwWQp6cDZhcU9NeHp6ZFMrSzZMY1FiQlppJW59TDNwKFpGcilSbFYj
NmtrbVpjUG9YRDBiJW55UCY8RFRBOSMzV0ZOV24KenA2aHpXLU5ROGB6ezMhVVBuamZlSWpDe0kw
cyhQVVZ3VXhoRHlqKGJ0KG9zX2ZwbDYrKCM3JUxpZW58RHBQWn5gCno3eVQleiEmNG4xR1FuR0J6
KT1pKVkkUVhwLSQ7NV5WYGJLZHdSbmdkVVVIR0d3UWJXVmpeSjsyKFd7R2I/fUJ1NAp6T1dzTypl
NnRHTkNSMTRhSX4jRkwpM3BCakshbC07X2V6bTZmfWlgNWV2VWckJlprP0RVWElrM3t9MTt1YStD
WG8KelNBSUJzRUtlVlg7SjEpe1ZENHVENilDMV9XISY8VnBJTW9zUEZPNC0pdzxGUWsoTDRObig8
YDRCYmZjQkpmMTBJCnpLJHVES3cydkpFUEs8WGVOU2NHK0xFNXdiOHF4eWpWQzVHZno3b3Z+cHFr
PjE8Qmh8RVRFWFBWWHl1Ul9JSWpoUAp6MXxDPzVTbT1JI2Njci1icyh5bm5zdiVPSlF6RH43M21r
TXIhIWhwM2R4TWFsWXxGMk11PHt7dU4qPkUhPWRnTDkKenNuTH1aYitGfGBzMlhtJHhaMUohK1RV
ek48fW9LcDIhXjt6UT5tYkBTJSQ3TmhJUHVyZlJCPXZVRypWO0RtLTdMCno0YnRJXnxHKnF+PVZS
YmNUMDJxbm4pR0dVNT9BLU0jRzloTEhPTGIxRGckXzNZJTcwdFdVTzhaNDVyfXlKVU8yegp6c18y
Y0k3R3wjPCh0LVc/QTxra2xtZUcpP3Z+TTt3N3V1KFUtWGh9MyVYQEZuV1FacWw4JSYtTHglSDVQ
QFl4LXAKemhBaFhhcTt+JE9xVmIrLT1BMkxPOHQ5PVQ3KllfZClHRzcmWV5IJD4+bjc8UWRPVmFW
QEpJVVF1ZmZWVF5wRz5OCno9PzVpN3FgR0EpUXJEbnNWQShTcjh4ZCRTUFdSYGh7IyVxRFQtMFJN
OGduSlpPMjE+OEBSZDJwUyQoNzF1XyM8dQp6LUpHbFlvdzBlNXViNFpiP29XWEUreDNpNEIoanpm
KH5FPG4kU0N0bWhEZU9wcXE3ZmZGJVpHSnBtQGMxUXRyQzYKekM+diopZkgwST9LQk59K3YqdSlE
VXtfPGNmMTM2I2licmlCUHRodEVtWlNOVzFhYVRpd3h7TDwjfms5d3FvbTElCno8KjxNbUFNemQy
YiorUnF5YDI4XkRkY3E8TyU3IyE2cDFScjF0RjF7NCUxLTZRRzY/MTlgd1U+P0E8STdfSCY2egp6
cXtwWmJDMjc4Z1BZWVEyPlYpRyRZOW56Pi1kZ15CPzl3fi01fTwzaHd4czhiaHg4K1h0WmU8YEBW
JV8zVEhnT2wKelM0ZD1tYVVkcXMrYkEoZnpAZndBT0lSZyR3OE85Uj5hJTtAKzNBUj1xSVZ6Q0k7
fEcmdT5kaE8qaU04aFNJRjBWCnpPUkdiaD1UVHFHXzxpc04/NT93dU01XktOSkNFRjxDaUMjUz9G
QGszKUl9fTZtXjtycyREV0NNUC1qaHFLPmVlVAp6Mlg0Kn1mbHAyJHFCfiEkZSpyLUd7dX5fM3tE
TCtuJi1yby1OYEF7Rjh3WktGVDs5Xl5EODleTShaN3BZUnZodm8KekJTO20tIS0oNy1HUmJ6XkFB
XjBgKmpDRUd6dT9IejFfd2UjR1hycHZgTjdsMCNNbjNVdURuOClwYktpQShrdm1OCnpOflFafkF3
PTxnM0BqJVdMfHJRZjBpeSZPSSExT2NwYkA4QEVIST1BUD1lKl9rTWNKRis/SlBRYjN2JG8+dzAq
WQp6cXoqe3VqJjs0Z24oMGdIe1ZefGRsXmh7SEYpQ2ZaMXp5YXJscyMkNDcleFppWmImNUt7cTN3
OTBMMkReenA3S2YKemN3U2FNancpKWZ0c18mU0FUcWg1ZGFxRVp1ISh8I09IcjM7eUN9VFJUK3tT
RmJnRn17T3dqVjdqX0JAdWgrPGRACnoycTwyUiRnUihsblg8Mio/JkQrbmpJcjV+NHt8bztqdl9W
U3pfQFJXbXcjeDBgPFY7b0gjTkJQTUJhTkslPG4jZgp6a2trKjBXdn0jOVM3S3Fxb3BAeSowWHI1
NWNeNjNaT2U1dHNrTytGNTR7Vng7KF5VbSZQeT9nNkdXOFd6an5eUHAKelIwMTBPOHkpV1BmUjhl
VGp8QHVZMS1jVnstJj9oK2owYXsoVFJkZ00hOStnRCttUUEoJUp+SzI1d0JDbUtGTE18CnohMVZ3
VnA7ZmFZZjxJdUlJX0RwNyZSfGBHMEUwOUkmbTY5K3tpcUxUPDgjI2Z7KHVBWDxTUDRsVns0JCpM
RlI8egp6SlFSWjhnOUxnWDBtfnJ+ZVp0eShYQ0VKR3smNio3aTNSaUQzekFeYW0xV2ptRWxtZ3xN
KXRDZSFJNSQjNUtxNFYKeik0Y2VUaWVLa21tfjs/aVRBSS1OYTlHWl9zX3xrRCVNU29RJms1cnAz
ZihgRipaeU9zPTF6PkQwfSNOVWBiejkhCnpIIUFiPnJ4NFFaPH0waTVfZG43VWE9N3clREAraVNg
ZncwISErPzNvKUluTC1vQkpSaTVjZEQoJW9CQm17enJ4Pgp6fEpzRTg8cEF1X0xsMGVFJGBxK1g+
PWxvVCM9SCtsKC1mZEBTSy1kODNHdHxEOTU4JEMxbTVKbW5RISVOU3JhQCQKek5gdjw4YH1oYlB7
IWdCbG5eSkl7TWY9IS0tMkohV1hqYlZ9ITAyT0tDOFFAfEc2RH1uV3E0YmRQPykoZCtYRTBZCnpu
STxpfVFsP34jWlRJNz02Q0olRSVgTF8qbnp9cCVAclB1cEZ5KjM1UUU+akJOfU4kcGNOLXUyUmt6
dFFnYSlldwp6RVNVe1p2IVRNOVo0KTNweTlXbXlNNUd0fGNwPipjMHJRZDhGNnFyQj9MVnwyUjVJ
QmlIdDkrWiVAN3o2NTR2Sz0KemU7aip7OTdpJGdSayY2fCZ6RjtwY0Bfd3ZMNT1sSCZQWDxkWXU+
IXAtTlYrZ2Y9Uj41SHx3Jnk4QWh+eioqPkdCCno0NVR0S2NSe2ByeTxFU05rVlo+cFhRbGF3eXhT
RHUlZT1eMkMyKzN6V2oqWFEzdCk/V1l+KyZ8U34yM2ApIz5ZRQp6VHd1YHEyMzVmeFotSiM8SiNh
Q1J6Z2xMWHxLNUxaamozWWY5T2V3PyRvdURkPkg0NDlkZ29nTURuS0ImQEkwekMKejxeKUBoVD5u
dVYxe0NrWngkYF47O1p0YCVFWFd1dkY4O31DS2VDPVlfa3M/cnw4c3tMIXZFfGorMDI1VW08ZDQy
Cnp3cGBsJUtTUSRwem4rXn1lbSh7ZkNIKlJ7M3hee3duRShmeXwxMFRLMUVjUUglR3BhZipGdkJ1
b35IMmN3fCFRPQp6ZlZYMkRaaVNmdVdlU2d5eGZ4T3dLISkyVE80Z3dkdHJKdGx8NlFMLVNCaEUr
Uj5yKythPkZndTB9OGhzS1ptalEKelcjQjhLdUZ0UHZlfC1iJEpgS21tMiNCSmczPDdvM14jJENQ
fDhBWn53TXN6fmNBKGQkU3V5ZkU9SytHPjViQDtoCnotTmt4P01kYCh0cFR5RDdvNSN6Jk83QnM2
QzgoUWxvZ0BaRyFgTUxwbXZ6RGMjR3F3KXskbWxWTWdzKURfVmwkZgp6UUdsNT5ITnwtbmw9bj0j
bUd8KkkzOGFOUDdKbTRETShHOFNBZzB0bUVYbystZDNQdjNhPH5qVmRiPWBqNEZUdncKekBJa0t5
Sy0zUz1rI2VQamtTUCNgQzxiQmtPd2p3N1pEWW85VEg/M3tNRWdvOSZZT01eclQ3PndhMzkzKDd1
QVNzCnpTRilfTkRDcypKaz1sS3goTCZLR1F7Y3UhJC0rJEBSXzMtZG1qWU16KX0/VEJPXzhCcnJx
WD5vVXhAd0gyQHBnKQp6ezUwMzV7RGVJMTtsdERlMEYlI21oUn05UF5AZXpHNE1aKTY0cWR0ZV5y
Tkp0Jm1CbTdwOURCYytfdmY0YWYmXkAKenBafkBBaW5OMiZII084KjJQTmlMciUkUC1CZipoWDY8
Q0tBYjVuT3Q2PDMwbE5RJTVKalcxMEw2LVpzWTskLW08CnoxVkR6cDtnRzs0UTJhWHAlfnNHZ20y
VjJRZGlKbWVKI1R5bjVOcUR7c0tfeEAxNylSMU1IK1Q5U1J9Yktld0s/Jgp6UERTO1ohI25uO2By
JEppUi1hRkJkTUtlN0MxcCowY1VeSkg2Yj18WERGUU1WTGI4Mm1yVSN4dFUwaDx9UlZNS2YKej11
WkYtWFR7d0dMTklsNTVYcipMOFApeDhHMT1JZEYoTmVpJHsyfXI8PEV1X2F7MTAlUy1jR3NWX0Jp
bVFBSVJfCnpBPkh5aW1jUlRJQjtoKURYMzBJdEdycFN3cFVnTVdkUV80ZXNsaUFOR2lFISFgVDhY
fVBOUjtPO0t4MlFlQm9BdQp6eElxSW9HSmY4PzJWNncoRzVxVikwQk8xM15eVkpha3g9d2IhX0w8
WkhDanxXMG5XO2VWfW5nNDFAXjVKOE5sSkYKejJhKU18WEoraiR7WEc7PExfMm1sYmxkWG5xZChp
ZHtAe2h7LXRAZSNgaWduY29lUzdLUH1eOX51NVZ5SSo+emoqCnp2d0tEdEB9JDN+KHY0YXUjT0Bg
WClfPlU3YCUjI1B1byE4diMhemxRM2ghZ0RpeXZ8VGx9fUw7QmQkcy13c1pGJQp6VklqP317Kj5K
NlF8VXdGP2d0PnZYamFNR2RZS04zPGZuP2plZ3t5KT08Z3Y2U3ByOVJ0ZndGITE0e2MzXk9NLSsK
enRIY21VXkdDJXtIcmYkQGdPUSNEOEMzJTh6TWROYylKdSp7TzY2cDJuRj9mbTxOYHBzYlRGMkIr
TCRyMUQyYWpMCnpeZ0dxdWh7KFolP1VMVmIxO253ZkdDP0l6bH1HPEA9UG1Mdjk8TWpFZlhNaHpl
SWA5MSMwUz42MDB8KHFWTnZ0cwp6aUxBekZRQU1ePEF1WFQ9P0NgMTU/NVBWazM8UyRudEowR1Z8
Ml5geVlYP2dlUGxQRkhkQTgyWG52Vk5sbSMrcHEKemUhMDEjO00qUVhPOHM9QDlZPGFURkE8eSUz
d214Q2s7OVReO3ZneHFEPHdtK05zT3oqQGpjSX5QPG9DZWNgJGcqCnpIbzZ2TVlLd31KaDJffjl6
PCNMTk9eM0FKRnJ+O3xoVSR3e2lLY3ExdCU9I3VWMj1yPk9HdFMzYWFldzQrQG9TcAp6dlBaUj5L
V2g7SkRidmROWjhQIWJhYFZ4Ml5qPTxrc3AkUUZnQVhWQGwtfVdHTVhFZDBlTmF4fitxLW9hWFVC
SWUKenpIIz4zLT5jQUU1Yzg3ay1rTGxjajRYUGcmI1p+enBnR15CKlp6P0MwMGEtd2o/dEptdmhI
PDVWI2tXWThndClKCnpnfjFJPFRHLWE5QT81SytMcmZObSNOfH1SPEVycFNqVWopTyltSXRfUVBS
ZHduVEtiTHVITk1yeVE8cEZHTjtAQAp6KFk4U1c4SVE9eS0yKWNuKVc1ZilvVH0ofFJyYiZCYFEq
cV5QSSMha1BRJkl7N3teS2VTbT0yRylJcEZSWXZBYisKejE9P1hMKlQ3MDdfbUF9RE5VZmtCPWw0
R0omTyhXdUprc0hTTzgwVnZkMj5NVy0wYXBiMHdecU53ZmtYUkE9PVlmCno2e1ZqVDE1akt0dVlo
ZDd4UkUzOCpYQDRHRV5uUyNXbytpK147Wnc9Sz4jVjhycj43JW9zez5LTzdCQXQ5Q2Zrfgp6eX1U
RGVsfGxua3RlZ2xnMHQ7RTFVWFZTQV9FK1FrYmlDeUZ0Xm5fZSQjSlpZPUk5QHV5eTxqMTQrez9q
PXJ8eU0KekdDPSZBUGg/e2FwS3MhJVIhcDdhM2tCNkxuQGZeQkZ0ezJnNWAoeXQmYSZnTlhWJm8p
dGt1eEFhfk5ZV2tsSlBNCnorJTlwPE5VSExXTGkpczRqYWhoMm59T35IMVpXTFJ5MFh1YkFGak1S
QXZiT01APkhiTD08bWRodzgpQm5DKmo7ZAp6K1lWPFExSkhUQjhhTnpVS2JsYUooRmM2PWo/JVhT
TDQyREprSElPZGhhYzAqeEwwbT9HVXs7di1QX3ljRm5APjcKekt4QWJuK3V3c2d5b1hVfD1EWCYz
PStQRFA8VD1XOEtmcmxxK2ozdU9aezRTJDAlVkBucGhrejhVPHF1YSFVYkFtCnpwWihsQDxCYllm
TkxZV2dNRClVQWtjLTJgeWJYKy1IJEFXR2Z6UDY3fEFyPSNafnlhJllZPlM2U2ZrX2NXblF8Mwp6
TFMwWXF6TUUrN3kqUTY0YlFvQmx4Kms9M1cqJUx1MWUhNWZWfnVHNFhrWW5Jbjl8RGZRJWAqUkN1
Y3pJSS1xNl8KenM1elRfT0JnJWZsbWE8TmpyaEVFdD0qaUNibUIldjxPNXpwTTFRZTtYRDVteF5a
Y0l+PSRIXlIrblIqRmN4Pzw5CnpvZFR2YWlvdXopVSpyc3BCM2VoTztiaD1aJnFsZ1ZEUylyTEZy
JlQ8KnRPWkxOKVUjLU5wKnloYnBgVkdecj8wRQp6ZERBYCQmI2lPPisrdSVqZTJ8Y00yTzk5Pnwy
YEREJCkwTiV6WTVsOEp6NmpZSGFZNzFKLUNRb19IXlhKP1VCQW4KelRtSVJvMUdAOFZRdGV1KV90
OUpzRT0ySD1oOzYhJnQ9OWZCXmlNM154I2hwNzZVZXViV0VnMXY/O21TUDZxamo/CnpIKXBOYCpj
RlkmI2Vxb3VLSDJiJXMtRWB7T1c5dEEmVXErblFUSEZrX2JHUnZ7QEpaZSVEJUJMeGw+NWhwNX1g
Tgp6YHc1NlAmfTkpX0pNSml7UVZFbyQyayFvWkdAcTt1YngpdEptXmJnalBXWjhGUWErX0xoOH5l
PU1AcyRoTF8tZHUKekAjbihWbVhaQEJ8Rl9zUG83cnN6UDs/eFp1JGY3TVUwPkV3U29naldGMyF5
Jk0mZipxI1MwXkxAMURVQll+YUg2Cnp1MGszJlQjV3E2cyp9VEBWQXRXK297SEhXUUBPcHVFaylv
YiVlU20kd2l4N3lsP31pPG1FZjQ0IT1takAha3E3fQp6YCpPOVpxU3V4ZnBmd0JTO0BKQUJRTD1q
OEdyKGlya15fXmc+ZGJHPWQlU3MxPEcrcXM2eFpUT2RwMXlQcCk/Sk4Kek97aSEmQHUxMVYpaWR2
PGt4UjFRNih7NkR3Wigya0B4PitJP0BYWCpUfCM8LUVtKnQ7YXhHJDUrQiM4WDEzYkRmCnpMMzhi
KkY1aW5icSZROztfJjZNUVRGUmR7UDMhUX11JEpEM1gqX0VBNEhnYGpxVm17fGFaeDIwUGlYPGh8
OVFRMQp6eWorc3RLNiFvK2oyKF5TbEArfm9sX1dMaDJHekdnRDwmcG0kKCU5P0ohKGVpMHxkRU41
Ki1jcDl8SDV4MlV7KTcKeiFOSjs7UW94antQYys1UC1UeFpEIU0heDFkZiYhRFB9M3JYbWxkb3BG
MlNwT29PcElWUjUpKztfKjczfXh8WE9oCno+WkthbGNXK1FMSUtRNVduXk9Edkl9Myl3U0JHNWhk
KUA5TmI1dGdfPDJOUG5xNHxwQkNuU09YZUs8eyliYXVMTQp6RWl6bSFKfFVOV1VxQ3JtdzBicFIo
Tl8ofSs5KDVqQ0R+SEI7UWQwWnxGbHBXdjw+bHBYUFFlfjRweiNvX0w7SFEKeloxJmRtODJ4Njsl
dl9BPjljRD8jU0RTUXphaWJHbnREVGh6UXI+amIpZWB7KiFPVG91UWleeEx4a2BVMTBqez1RCno+
KXYpdjFFSjIoJEZDNCFXR3ZaT09zS2YkUT1rXk42bGQlNkckdD04c1o7dXNVNVMpQms1S09RPEp0
WmNVKDNhcAp6V3pwZG87JUpXQWZPKTZCMjwxVnNoVmkrcTRudCtWJCR+VG8qWlh9KTBgPCMmWmNr
RWVUcHkrN216VnJUfDIxJXYKemxSbFNJSThVNmttYSlSIWh0QmJ2KW81XzFYV2JkJUtQQFVOcCtL
SmMtUXArS041TSVGJGEzYVYjNDBiUXlZe1EtCno4KShlO25pNmA+NGB6TXRfNXV2fEJPX30qVEcz
ZmclfW4/Y3FJZj1aKnRVb0QtJTctRlRSWENORyNvKXt5cVIjZAp6ZVBETkQpdW0+e3ckPG1pa0Ru
QzRZSnxlc1Z3OXU1P05sUHIyKyNXXihyTVklKGVFWTxIdDEhakM+dDBUeXdNdXUKeklNOTM1NXdH
YyplSF9vOCY8Jmo1QmA0JndFNVp5cjh8Q3xERXhQSU40VkNubUleVkw/Ylc3MSR5Sl8hfTdaWVdY
CnpaSDlNQkp4VlN9Iz0tUGNZdlVBfV4yOVRIbSFPYHpXP0tYdigrOTVZbThJa0xadkBRQXsqJlY+
bkw2OHJ6KilMMgp6I0BvellgZVVJKlJHUE84bWtfSU9ENmBMTHdZcnZhTyRhdExUQ3JxMWRhe0xq
QW0mNldgMlRjJHR+WEYoVUs+QHgKenZLfGdlcDV4enMxekBWNEpGPSRJaW13MG4lQERtNnZhZ2JF
TDQ5a0tRfERmKyQxZCshSCNOVEdST3prKkthWHUzCnpwTnEkcmt5dj5UOylvVkRFbytiMEA4d3Bg
IUxSTSUkUjwjMTdwejJhY3BrTFk7eEtzZ1F3K1pSYGphUiEoRFN6SAp6VT1SNFpuQkJ6Y1hMbVg5
WUt9e31CfkEtfVZLVXJ+IXRXbyVQWXVVZFkjdkRGN3UocT9wZ0hfakxUbEsrPVFYdl8KenMjJD4h
WXNKYmM+JkVVS3EhZ0ZiU1JlWT5EfDxoLSEkfmxyUmUodFpPXkxlM09eQmN5aVM0YDx8R1NSOUpz
dFpSCnojVUs8ZUx1fG1EIVZiMTxuRG9jb0pmPFNYOEt4Pz0tQW1IM15Dd0ZtSCtERDVKPzJIPGhA
ZCU5KlVWezJqYEtXTgp6JGk1Q2szPWApdiRxWlF9bn5TbU5VVmJwU3hVOWZAd3x7d0BqKHFocUQy
SGNUPkY5JVFkJntTM2UqTjNQa1NGV0wKenRYVlRITjBeVHY8USpZXyZWSnB9dG54WHIpaGcoRUpw
K1c/YyZAPGA8SUB4fDZKPExLNVJFankmLT5oTTh2ZXRfCnpfalY4fj5Pe0U1SVA4WSh0TkdXbCY+
ZUFYa2JiOF4kWStBeG91Kl9RdXAyXmM7IVlDZEJjUFQqZ2BiIVczPUAjagp6OGZnfXI2PDBjQDRm
YnZNQUh5K1dVIXskSXYqNT1obzxFZHJJS2RhWWg5PSlhRFcod1hCVH1SUTw4UV5LTFB8RyUKeiRz
MDlUUFY2dCsrMUg9X2wkQFJycChlVyg3aXZuaW9jTV53RSFUdE9lekFTYXRPOWwqeFU2SXo4elFx
WEhoekJICnoyZTRrfiZEKFp0dSVVcX5YMD12bEVQLTcoR01ne3pQKzZpZzU5eFMwTENvMXBSY2hI
dVRYR2xWNGFRU0QqNGd2Pwp6eEBhdSUqVzN1VHFrSTxOQVFAOD4jUGlIRHVrKkZGZXBkbSNqVWl2
ckhaJEk0Ji1PfUshR3JNXnNSLVVRVWVDZlUKendWYnV0Q3dDeWFXT0d6YXJKQ0JkcHMqcWF5USY/
WE12JlFENlVtSWJZJC10WSRDYjclYFVlbCk0OElIMUBPWjJVCnpNSXhfPj4kYV9DU2h6V0JlUSF5
LVdPdW4jKHo0bndZeWdQZUZwKDhHfDR9Q09YKHxnfFYpS2ZeYEsxU3w+QUJsRQp6b0p9YHombDtl
N1gjbnJqOyN3eD9hTl8oLXBBaypgUzIyTX1OYnt4TU9DV1hXPFRBM1VYLVVwOEVgYkRnMGBqQzsK
elcqJWo9MWJjWUwhOSgtS0tmJWRkcHdSaUN1WFA7YUFZMSZjKSNNeDtkPGh0bFdGeV5EJTxnbW9w
T15ye2BOKE8mCnokRytVYERybHZ9KiZqZDAmJU90X1c7dXZuTl94WXJDdVpKKVRDZyRwKjV0MCg1
alR0VEszU2o0Z3lIX1MmYS0yTwp6R091c2trTWY+Qmc+cGpIXnI/PGQ8QnhYazdzK2cySWxDNmBq
Vj00UGFvZ2YtRllINWFVQ15VJlRNIUpjX1dJTn0Kenl8Z2hsPEhvTjcjanV+PDhQTFJBczI2P05M
QCFfJUJIclNVSEV2QE96U0RDQ2lOSmVJRzRaZUxuUlgtR2grUkdQCnpPLV9YKGA2cEBhaU9+aHtT
cCstJT0xKUdlemh2KmNJUUEoY0NDdlBPX0YleV5qRHtibkhSaChoc3k2O01hejVTYgp6NiRjM21C
eFZNZkB1KCU/byZNIVhGaVlzWUJyKEgwY3ZKMG1QQHZ4QmJQezJxYmVnYzBaUEZaRGZDU25FZT5W
UGIKemUkIVN2RDI5NnlBTUVsSVZnRjE7SXJEXzRHbjBrcigoS1FrTjZhPGxedjJZWk5uezt2d2BC
KVpiOXsxVl4qKXQrCnojcWxoK2t4WHIoUVB7bG57cXg9M2x+UC0jRVlmTz1LbTxZRmUrTiZONCRT
SDZtTC1GUk1SQlQ8WUJfKiskWiN1dAp6dm9SS3dZXnNBTDk2R2xAeWNELVItQkhXYztESUVFfEZy
ZSFZcT5eLUhffXh6JHRxTnc7THxXX3p3cFU3U3R6MlMKek8jcnxlfDU5Tk1IU3RBIUd+djZxSz5P
ITd7SElfME9ufTE5Pi1ZeUZPR29aXjV7P31CNzZzZmtQKDhQNjY1Kz5SCnooanY9dkpvNXN0aGUl
TiZYUWxhSntDdi1WXjkha28xYjFYK1FecVUtTD03JExHJCp3aklJKypXWn5IIyltJFV4bgp6Ym1E
aiFBaXVObSM8cnlNWFBWN1p0dU8yZXxEMnl2NmJURjdrLTEtRi0tNyRmO14pdTdMUXlucE9TQ1Ah
RFdRK2oKejYxeF9eQC0oaVo+ZklyKV5PNkFLKEt9fnU3RTdNdnN2cGRPMzZAd2JLZXVNflJxaDBS
aUA8S3FNci1YVikoTzRUCnpQXj10YHhBPEgyI3tMNWdnWDRUalh3ckBqKiZKYCN5d0xqdykrVztn
aVlOUXRNYStocU0jMVMhPGVrMmlqWDhrVQp6MXpCYUM+KDh8YkJjP3lDM2VSTzJhQzxlYyRaVUdP
ZEc+Kj1aYzh5OG9sNGQ5cz99c3x4dVBsQUBXVDw8cHdrKGcKeiR8ODhXK2khSzhXVyY8JGxNcWdq
ZHF2NFVXU2BYKEt3SjZFJCVNbDUmcWg+UjN6bkBeSlJHJGBTaCN+QT87RjskCnpPUjNXckUyU19h
JUtlMlpSfCVTfUlxaj9jWTdKI2pMRnhSWWB4TjxhQXZ9RDJONCszSzlOWHhVWnZEQWFiVkpFRAp6
KXh4KVBFfTk8Qjh0RV97U1ZwNUI1KmFGWnBUKGs3XnxLfGNFSVRgMit4QylFdEY8IU0rd3R5O0op
SyorLWRDcmkKejl4PzdOZTNXXjtJQypMKCp8czFVeWB1Ml54TFQ8S24xdVdKczJINlB1Sl9WPU1T
U1ZuOTM1U0U8e3hoP0pTXmZ6CnphTyFRM2ZCIzMxY35NRTAtZCt1NUdvU3dwUktoJWtXK31Wdkdh
cF8zd1d4MCUtQi1VKSFRdmZ8bn0qJDRFeHlJRAp6YClKSElXN1dQQHQoP1BAKm42P2NvUjVseTdL
c2V5RmkpJCt5WiFtNT0ydHpIO2ZUKyZRREUhYWN4Kj9iaE1ON2AKemQ5Nj9lNSs1OD93M000X1gx
Pj9uY3prRCpUZmxQfGoqSkpNQ2t9JWJKVEFVOUAqd1ZLZWRsNzg0eGNIaHJAMEx4Cno8SW5mXkIl
JXowWiE4WXhnK0NJMVpFY2E8JEBUO3I/a0l8JVZLTmtZd0pyKyg5cnY+WGMmfWgqN1RVaGFDUXk9
Mgp6UkI5PVoyMEVQe2BwbUpDXzB9fX4jZilMMkRCU0hBYj4tYUNhYkhvfkA1ZU9wSkRyM3IhYUpo
Z2lxcnEkYFFDa1cKenQ4YXlVKnNfNmN0TD18M24oUEsmRkZBLWA7X2RLJmF7c09lI3cpQXw0fnhf
QiRnVV5ya0BUVXJwUUxNdjhfJTxhCno1PkghezM5X3slMXElO3djOUhHUzRtQXlIU2hGfn5FJEdC
aEE5Vmg8NH0/VVYhUWxAdkh3OUI3RkdSMT9nJnI/Wgp6ZmE0M1hZdDRUcUJNb3NmWWJ2fntJQDRL
SUMoZSg4OHA/VFBJJV90TUdYZXlwbXlyZik3ZT1mSE9ZT0dvY15TOE4KenFHQ2ZMIVEtbkhSRjdV
NVokND5EX3QkS0BEK3UtRjkxYSFfO31YKnwxKGc0T2lhJUlOOD5OKmpESkM7SmpGMCRrCnomT2Y9
THUhSDZGeF52XmNATUV7PFVOfV5CKEZjUSZlQnxMJXJ7UlJKRDk+O0VkSSo/ZT13TEtxMGwjTHMt
cVZhOAp6NyZ6cnw/RE5CNUtWZ2wzbWR3WE9eOzUjVmxMd0ZmdWFvb2VydXpSTWAxeyg1WW1iYjMl
XzFAaSomYHlecFh8c2UKekJWPVN9VF9adzlCci0hcVgyXzA5SHJadEY4Nz8xV1UrKFg5YCtXYWAt
I1BjKGJJLVoye2R+VGp1amd3I0E3R1UhCnp8RVNjXykyI2lTVll9VjhrMT42WGc+dEVoXkk+JTUk
PERkWSluPTQoa3IxMTtyeEdka0Q3e2w4WCZFUERZcjdBVwp6dyVBOzU7bj45VSVLb1A1cGl7WTNg
ajw7fFQ1I2pMPGxHbWQ3MUxNLV5OI0tzcz92ITFIfWZJI2B0Nl8oTVEhNGcKeks/aihvIWVBbCky
Xm1EaGwkPiVrZ1puPTZMTmNgOW5Tb05XYkU4JHNAUnxuJVBXMWVeIXF8N0lDenJgZz4xZWh6CnpS
akJ5fmJOZVFVMndBaXdLbWZufSthaTNHSlFFejNlaGRWSnJ5aEoyMDAtQmU1UiNYYE18fFhee0Vh
dWckKlRIcQp6TDUqREIxb1dgcTleWXRCLUt1R2xXNFhMbCQ/UFFYWCNsRz5FMzYpZCtQekJKcDJv
KVF5d0M2VT9KQyMhQ3pYTlIKeikmY0hvYDB3SVlQTnJrSlZtPDFHSD0zQGpLVjdOKGk8MVJHckZ6
ZHFENW84Uj5nT25AQ0FPbFIjQnRBX0duYTxSCnozfShDMVVOd018S21+a0xiWEw9JldyKU5aXnsk
Ti0jT187fUdgJkdKaX1ufE9iNXpLQnVicnZzZ2V5V19WYW9HdAp6aDdhfSoxSTJeRThXTCFycytk
R0dMPzVQNFleOX1Tb0pqS3pMI3FjdldVJEw/aGY1eW95NGw8JXllKis3Xml+N0oKeldGYUNWWSpm
c3xGeHpHKkxNY1FtLWpYaEg0SEg2Q3VYSEQtblhMTVdZTFg/a1JYMV94dU8rV15XJUJBeXBJMXdZ
CnpmVDZBcjBTfjB3eVFvZCtvZFlvOWpIRUc9KH5oRnp4TzNVZU1sXnxaKFAwQyluI3JCQ1JIPHkx
VCZ4VXV1NiVMcQp6UEtvdnxwc1kxYyNsZlkqI19wS2c4YE5tdEc1e31kMyt4PnEhPX1zcTc9VV85
Uih2S2BvODA3cEpGKVVydWowenEKek8yMnt3PnY0TGpNVHxZdzxaKXljcHVDVmxScWV7aEFlYVQp
VFNKKHFGVFZKM0x2PFlOOzNhVjIpZHtmYnNtMlBrCnpGXjQldUZgPSYjeygoYyVzdXV+Z05yXiZJ
djE8TlB5RVNPYUpwSjI/dHB5fUx5dG1TRGpmbTNER18qeGg4UH42Zgp6NitOVzJTd21kNjhGO3de
P2hNYlVodj4wV2I1Un1HWERMPzImRXk2TERVU1AxQjQwSUYodF9NMWYqN1EkdTVzWl8KemIqPjhh
PGlBMW1UcjhYYDVDPlZ2cktiMiQoXnBaa2FRNEVTekBuKHIxK2YlWU8jfTg9X21OenNhI1N6Y0Ns
IyN8Cnp2KCVEO003RXg8OGApNEJxejJFWEMrSEtSO09wZmFXRiMzfnNuPWd5WHc5biF2MWFhN1Rj
dih0UTUkeUA/Y1dZcAp6N0s2YDNeeF9tVjEhUV5eS0pwdGdVQUJCUzltb0ZzTiRYPTgxNm4wJjJ1
OTlQWCVRKyRmYTE2dVZoT3lZYD0xRSQKemlPZEMyM2EzQHAzMD1XMG1gN35STTt9Ylp3c1hJZm8h
QXdnc0NoRTVGMmFncE5XVihhZ21qfm9SajckejFZeSZwCnprUDxjQmtGVEdrQkNvJnl5ZzUheVd2
d2p4TzZ8O1ItY29+ZGIkbld+YnRCQnQobmR4Q1hPKXlVaTEhaUc9Izs9Rgp6PUJ0NzJAVV9WXzRs
P1NuPz9nfjF4Y3g9dXQrTjMwdUBHdkhnZypTVFpgTz5haTxtRz11YFVTX2F+MHV8ITA3fUUKekYt
U2A8R3QxdjZgcFFZOFFxUUpeRFBfQG5zWklpUWM2dmg4b1VUTnViO3pTZl5nRDw1ezdYd3ghNE1k
IU51Zy0zCnpTKlpIemJ1cmRyV3p5TyZlXnlJM3FAfnw3ZHYjaGxYQCE7WChrJHY3enhwUz5SMH5T
d2kjKlRhM3B8eUp3NztpbQp6UktfKEYhU0g1ejlpPmgkK0hUKiU8MVQqbkokdVRObDh9U1BtI0h2
JStQdzxkal5vOERXIXlDRmFILWRyTlYyMmgKell1elpvWWBJNkdmTz96WS1WSk5BNmdpQ0sweWw5
dC13Y1IzTU1acSZNLWFyem1ScDFsaFM9cyhmfEpuS0h6eDwyCnp6V3VvNk0zZUs2KH1nXjVGcX02
USZLbWBuM1d4S0NCZ0VrYHB7RlYpKyQ8ezBEcVY0R3E+I2JRZHgzaChIekFiPwp6VUBEIVpxR3Q5
d0x4K3V0MzAxRVkrbCFia2heRVhae2RDb15eYFVJSGlzLS1MdmA+fFAkPXtTc1VMMk57cHFUWWUK
ekZffSMqazlPJnJVeWR2X0YtXmpnRXlET0FWWTY7LUN9QmBVZ3JKRT89ZEdpamN7NW8xKCYoRHdX
XkN6SWQ/OylzCnpET0R2XiRpNExMQlNNVmNmezdsblNRJHpDSXRRWHQwcTtlbD9JOXU8RWx+OylJ
Sk9FYXhmMlo2OGwhbiYwM0xTTwp6JDl1OXtYe285X3AhdDs7Sz5gMUFveSZDM0FBTFBuTT8tUC1A
SV85QE89Z3ZRcz47YWM0ZGhNc1Z5QmNPO0lmVigKendhQnE2K1k+U0xFPFl6U2hiKGIkU3ErQFdl
ZCR8JFB8V0JFY0tSVHkmYHBHeTA+RV98SV43XiQqfiR8MGd4MUdvCnpBb2BEaVAoNDkrWjJsU1ho
bVUmIXtHX1BlckgqUUtTfV5EVTc3QCZJTUZlMXpCdFVGaHIoTEc2WkpKVm9CdzspVgp6YjAlWnZR
SX1hdWNsWUElZkdLOClJfnAxJUBiblBeR1NxYnVeI2wmfV83ZVVGcEg8IzBCfCRKbihmalImeGxm
Nz0KejdgQikyKGNYTHNOK0lldXQ2PWREJlN5UC17WWtvRXlVRDBjIX49Mik8Xz9sWXd8eXJFRlI/
eDllMTdQeWo5WkdtCnp1Yn5IbHU2blI1VDM3V0EjKzt6fGRrMjJRMDIlY2ZHNCp9KyQ7fCt1WTlR
aig/ekprbllQRmIpVnh8TylNX1gjOwp6WkpnJVMkMUhQclh1KldfJWAwdzBVIz5rPCR5OXwjP25X
fm5GdnFrenxKUElzXiNuXz9SQjZUPXJYISpCTWxobkcKeiVNY1gqSFJYbiopRmx2YXNuMn0xZzR7
T1JoSkVQeDU3a0Vgdl5YaipGM0BZTWt2Z1hoJTYlYEFfUzAxPXFYKlZICnpiYUxUQXNPVTV1Q014
akwqOFA5fmZea2xmdzhDRDNjMEMjdUZmXnpoO2FhUzYjWUVBaWtvWispZTI9Ni1XTWh8OAp6MHtW
RVI9TkNzbU9mandBd1BlbShxSThXOUZSSC16QWVLX18tUlM7V3t9JDxvUHk1V2owVXFwP09oTGl5
Vj8ySlYKelRleEU0d1MoWDJySHs0ZSRXQjI+cjZVJTN7KDAxKWNiKmVTam5CWmFrYiY7PT5tV2kh
djYrcmVLRkd7LSlJajRXCnpxcWA+a0UjSlFaemA3dmIoXl8xdUBmX25LdFFAUWdlVmVHVEpETXU0
SXVjfWJDYyYzYThhK3lvKjFOa3NeNXBeSAp6SkArJChjb1BVaDx4ZWc3Jk54KXM5RSpWZGR2RnZu
M1ZjV0NzSjdxflM3OTlHfEs8fnlKfWZxKSNAQ05Aa2BSY00KelN4cCZ4VitCIXIkU3NBUVJ7Zk5B
SV8jMTB1RntVYDdAbE4hMTUmfEpaUHZ9fWdFdXlmek40fTlRMU4/TkxrWmlSCnptb3RkfDNKS1FS
Z2tYJFQ1JiY+JT9CTipfJUdOeyoyKkJvIz4wJCNXbyRkYVAwQmArRkk5O3NGd2g2UVZ7JHgjcQp6
cGJze09SXz4zY0NubHdOODghVWtoKE0oQ0J2b2A8aC1qYF9zbWFCS1VtbmM5PWcpMz1DMUtGYCgh
b1VweEpyQlYKej5Vb1FFYjw0d3RYLVBVYmh7SSt7Mj9+PzFTbDxkI0BXRitTe1cmPEhGa3Z3TyFA
PFF2YitQbnlZVUViR3syQmlmCnplJn5ySzlSIUs+cnJwQnIkZTROfjd+blJhQnRSK3hPWWQ8fXVi
KE1LP31ZcjBxOUhINENERHI3YTJIbz50Nk5hJQp6YkE2aiNQTjF2Iy1GaCN7PXtqJm9sd31wLVJ2
TGBNe3xyLSZ3eVpHbWkmMV5kaDxwYzlKaWlqN0l7dklHR3dYY0kKelBNQXt6NDZxaj1PMlg7fjVx
Yik5UXIpdTl4ITN9Tmp9MyQoVDQyPnZgPSMmUnkkZ0t1XiQ8NSg5PjkjQW0mJWVsCno1Kns1anhE
LWM/a0VneihOM1VtWXt3ZHZXKTtFcVQ4ZWh+azd+RFk/YHxuRkMleXtHWllmRipCTl89NSZII1F0
egp6VSU5cFZnP0ZkJVRwWXFvXy1+b3tZd2xSb3tNJEo8SXg/YjI5bVhhcjNsI0gmanREazdJeDZZ
azlISWJRPz59OHkKenYoR3dUb3YydW9vQmRWaXR9ViZkKXdUcXBvMEcpclRWZS0kYkNiVlVUbUw1
UntMdmxjKkUxU14rQkVWZDVtOFc1CnoobHl3RVBnST97IUo/Xyl2JDY5Z1IwcFRIdHFPJTEzcmR7
NkIzNl4xYHQ/ZyVqPCN6KHo3NDF2THp7RFR3eSp3dgp6WUlYOD0mK3M8dXJeTjlHd2kkJnEoMlJC
MkFGVlhgbTFPTmEwV30+WkZsOTN4OU1WKFYpfC0hdjFzTjVkZ1U5eU0KekYrZyNsNTU5KipRYWFV
QG1GKFRNXz14RE5LMllNUFBjfCFpM19BZk5VQyhlKlBlKkV9TylOO352KW5xSChNNGF9CnpSe3du
cClUMjlNYDFnO1dDSns1Mm84czhTZ0UqP1dwezlBaHJZK3lOJUY0PlYxKkgmPj1DRlVrXitScCMl
RkskdQp6eUckeGVyc3ZHaV45SGpsXz1sYjJyOHIjSylYR3FlRz5HWFFZeT8oMHgjdFZKYCZPOShA
andJe0k4OHB7aEMqNEcKemdlM1BhKmsheWoqTilFaWNsfC1AYy12TjxUbTQpWSNyWmdQdjVzLXw2
a2NGNzhzIXM/MCstUyhhUE5sPT1vYTQpCnowOExXOCRyNitBVyo4d3t6Yz1JdUpLb3ooS2UrQCZN
aGlGa18kZXpkeG55WURXbzlNLWJyUCNGNk1GNjcoMTt0LQp6NVN9NjYkT0olKUhDNWpeO3E4LT85
Uk42KmEqfVhGV2EwSkJYOTZQdSppUkMyJERrZTw3IX1fKXttPSkqaX1oXncKeiVTP2pEbkhAYG1R
az1sfVUoZXUrYTs9fTRlNTF6WkhYS0d5Q2tATlR2cHV2MypoPF9NWHctMWxZa2U3Nk08O3ZiCno/
P1hZVWU3PkBYKjlmXilWVjgjVU5wSUx6LTxtdHE7JHhxRml+QEYtVGAwTXQjayExc3t4fDUpckdE
JE9yciQtcwp6PnJVUlcyRWprYiU9S0htZjtmPFZkdTg/VE93c2NRTD4lY2ZKK1JBM3M/PGIydkly
MFpfY34xKnBrRmVlPD9teTwKekNAbzB3YE9CdXkrXzkxeXZzSiZVX1drXylGNiQ4amx+d1gtY3FE
ZkZIViVYRm9+PVEyVyNqTnpsPnFFN208TzAmCnotbmFwYipSelZMWFQ7WSpXQkpmcVVhViQ5WXE5
bXR4WmZENFA4WVJHTUsxKDIkYlVwe2VAYXtXV1pDaWlxZiMjUQp6ZV8kRyV6KUglNkhiYlJqZz18
MmlWP3dnZFIhWlIpcXpuI3BPfEEjbTVKN3ZDUSZsZUxsOE9xdHlTZjAhcVc2bkQKejFhKjQpTFgl
bkhxSi0odWkpe3B5QHY8bjcqPj9UX3lJRj4tcFRsXmUrWU53Ul5VYjZ7a28kQj1ITnlBTCFXXntE
Cno/OytQRjB2TTYyYDFOLX5ZWXg1Zzw/d0pPd2BKajhfOW5nJkVXaS05eDNeYjQ0MDckNlNqK0k5
ZUYyci04UGxpVwp6aDlHSyV7aHpuMEd1JjM2U3slTEQlKDxIUVcjOW5WUmh5VENfRi1jV1NydHkr
Q057ZHdgbVF9d3E3ZSlGO0crdFcKemowJX40VGZnalJTWCFVZyg3Pk1oblZ9OD1wYjZoMWI2Jk4j
dDdAam5wTkMofF40fCo1TGxGbFo8ezUodzJlT0NiCnprOHh3OzFJSDB7YjwkKVp4Xz09YEx0SkQ4
OHlnen48MEpwcDwxPmA8Zzx2alA3Iz4wY0ZifjwyS1Q4VWBGWGEwRAp6OFVXJTZhQnRvKyMmdnw2
bUw4I1g8V0V8NC1sWHFaPXFxb3hGK3p9e3Iqc0J9Tzc/aXVRNUpEQGZCT29Ne2lwV2QKejl6VHxM
aXxVUyZrSWRGUXFgZTdzRlBSVXxNdX4jZClfdih4I2tYZyQ9Sz5DbjRLaSM3djQyYlZQLUhXSmAh
cjwhCnorQSN+N0Y9Ny1ue3p8QnJHYSEhOUQ4c0wpZn5NYz5fdClmdWM5UzxaSHxsSDVNMVZVYTZW
VmJ8SCtoPFFTOzRSUQp6Nk8qfmVwZWkoWVhZODlvOHlmXzF4R3UlYW95PD8pVHtIV34kWXs+NExY
P09hSTlCQm9QV2k+Zm5gY2BtWW1jeiEKejU3QjQ+I2prJntQRShZd0wxd3BTZVVAbllXZT5KOyop
IVAxMmtpJCp1SHktc1YzOXRjSmppfmFCWF9jQmZuOCpCCnpBeV5taSg4fkkoNH18VCpEQk81akdp
S3A7dW4tJW8mOGlIMTB0VWp1KFd2bjcoQHdYSkVaNDV7cXEhcCVSRHh1Qwp6SyQhfnhiSURPS1ky
ZCtSUzY7ZUBwMGFYaVJ2SUNnY21uYDQydnxwPDljK0huJD1oZ0w8Q3E+LUZPc2pBMkJveVUKelMm
OXheMipSRUhYZlpkPkRBRENKITszQVMwQi08Qk42JnlEbU5qLTdqPCM+Pi1UN2FSI3c7OW0lPmAo
ZUZWbkJGCnorYUNJRU9pRG9hRGhqVFgwKipwRygrJW1oZUwoQipSdTktaT5JMShzKU0yfTNzbClg
LUZuMk13d2pYbk47e1RXUAp6YlI5TVBKOFchbz1BPSNkKGV0aUBGXmUtIUNAOTxVejhYSSUxbXk+
QW0zM1U1Xl90UU5uaT9MeWx+LU5PI0N3NW4KeipGRXdPRDZXR3J1NERmS1didGxtM2NSQDZQJmp2
dXt7UyNrZTtzVSYtM35oR05qfWYxdVJrbD0tZ2VGfUZrTWR0CnoqPEomQDBaPlhIezU3UWl6aGgl
Ui1gfm4oUTJhUkhYX0xiUyN5QUJWNyZMNVJtKk1CR3JnbW15WmYraUxRIyY5SQp6WDZoQmRwIzxX
KmBgfCYjUE54NH1XRVEqI1dBVjE8Pn5vRzgkYVc5ZlY3ZylJKFJfTjQ9RGhSIWNYQGFWRk1BKVQK
enRxR1dwQDNXSn4lVXl9aTBlZjg/TmE2dzUyZl5fNzhnOWE8YjNKR2EtI0xXVFRLY1UlN2JtQzUt
KEt+Y1dPdVNSCnohUihedENMPUh0VnEjJVVeVTRaNTwhNiNUU3paYnZfe3dUQ2dibShmZmlhaHlN
cWJOZyN3Qks5fDBLJj4+PHI0dQp6JCl6KWF4aj9GdHp5bk5NJX1uTjQ7QmlZRCtIPnsyb2lpYWRw
TklLYFZGP1dTNTE8RmMjKU9galo5TG5Vb2tjYE8KemxZb1dqKzc7JEtCaD9zKE1uSCU9SjtPPDZe
dWg1S0JrM31MP208bVpsaSFUejgyaU91UHdES2AqY3goZXxLITZ7CnopNHZWbjspPnp8NEspKzgr
WXwqI2d+OThmMWpfbUNVXzVUTlRNbldxY3ZOUDZjVVhNUHxFeFlFZ0JgSElGbjB3Rgp6LXYhNDRS
Pyg5KDxNfn5tYEdYZm9eayN8MEd+UyMoKWNiTEVndmBIQjRuZFlneTU1NiNuS0VpJGpNZ0Mhaipp
Q00KeiNaYlR2MHQ7cnxGbk15JXNNfFFfRW9hfjUobHsocm0oRHBhSShqWlJ8MDU3UjBrbyNrLSND
SjhrI1Zqc3NXMDQyCnpuNE50ak8xclFmMHYzckA9anZ3NjtYMHlwWkFTc1NwdENKYHZpeGBvYGFf
dFheNGEoKSVyYyVGV3cqT24ka2NlZwp6YGNNSD5zcV5RPVV6aCZWZkczYlk5UWE+ZyVeVnJnY2dk
MSpuYmt0JCZScn5zMk05a2I4cGFpbEtxQzFzJlFBe3gKempMYmJURTB9dWs4ezM9dlEtczBMP2FT
ME9OcUJlYiEyYG0paW1NfUg0a0x1PGxVX259bVdiNklyZiUxeE1uWiQlCnpGekRWa3wyJHE1T3Qp
Ki1qRXA/SkpwJXlJQClsOE9fSjQ+O1U0cz1jTVRWd0BqdUleX3s4dXVQJjdPQXxMSUhlQgp6UzF3
M0gwTXdFVz5hUndoVmBAdHFfYT1MckUkeTl5JmAye0dGamBfMDcleENhKEtqK2BAY1IrakYmOCp5
P3A7aFkKemFHQiVMYGVZUTB1JkhBTFIpZ00rRFREYGtjT35vKTVkYH1OcUxKeCpfZismKnchQ0I8
OTJ8NUY0OStpX2h4Nm8pCnpKMXZtREBHYyFKUl4+Slk7Q0dUa1kqNHp6TmpGMUJreStWWnhHdFkk
RSpnenxiQl9wbm8xNSNwUHpYbThhSGlfJgp6TlczREphPSQjZGM3RDFMZmVmNGt0e0lGaEpIKyt+
JHd6fEh4ZUI/cVQ4a2JyU2t4fGxeeFBiP0t2Mjl+MV5vI04KejtuWmcyMGVlUDBgVVRmPDtIWldJ
SXRNU1FQU3lwbTh5RDVXQ2N1a0poKDdyYkJwUTUkalY4WiNBKUZRTmNZYVhhCnpJNWFtR1dYTTRz
ZTx6I3pOJHVoeDAtIVNhenk+bStCXlVyY2lWRiVoRCFGNCphODBGdzJaYzhHd3RNPEB1JXN3Sgp6
UnlCbDFmdVkpMj9tK2wkU1pEUW5LTjRmdjRab3VsY0VgI1khTkp1e3FlS21lcXlUKmFLNk53Qk1g
KHEhMzNwX30Kej18KjhTTjM5STlkTiZVZzU/fjclMERDYkM0RXIhbXA7NzZEelgtRmU2Zj8jQkh9
fUZpU1VAU1goUU8zdkd3fU1FCnprX3BUcVp7cFAkK3wtUXMrX3s7Q2hLNTJ5M3BSWjtpLVpMQWxO
Xjl8M2xSU1FIdCl2QzlVan0mKXhHRnspc3sxeQp6SklNRUFLX3E5O0tIQ3V0NExAVHZGfkZYOSl3
M0hHS0dTK3V5Zig0bHVkb3d8QDBMdXcpMlM3ZHt3ZkpaZzQoKnQKelM8OU5lMWJXN1BoVFJ2PTlH
UkgjZUlkI0FVUVk1bGImUlQlWn5RQkpWWCowUXNEejZMN0xKeThWR2Q+ZXJya09lCnoweWN+MT0x
QDtzc0ItVlhNLXIoaHB4VmMoSHp+JDx6VkMwN20hZEI9JTRUTH1JPks1OFBzKXIoU1lsTFo7eVM9
Ygp6JF80Y3d1USNuMSYofTNBeyVaUDZGUmt+fmBDME1OIVEpdHxaR2ZTfV9BemNmSiFNPCQyYVVz
dWE3eV9PUX5eQmQKemhUcnpkM2JyP2BudkxQb09XVGc2dk1ha2pXPklhe2ZYVzJlUE9eTXBRQHs+
Mzxxfk9ESHtTeiMybCZCSUY7UU11CnomfFQpZypjJDJiJFBZOHgxRDlIa2hmc2pDZTV8Z3AjdGlO
MDVMcWhTcSY3QXpGKjctQHBGM1pPKkdpTTxgQEtXOwp6R3ElbG8qdjZ6cGhsZHVGOWx0e0sjM1ZS
fWtBZyUre3x+PzxeUWVva0BHezMtUDB7UjE5SkpzMVctUkVLKFlMe24KemN2Wl9KdSNMZ09MPUdV
N0FRVz1+cjI+aWJhSzhXdj5JZERNWCowXyEjfHwmUj9FTWFRZzRtSSZzJGN3b1dZPCtACnp7M0oo
RTs2X3g9MiE5azhNTDVnPTBIVXZwWEAhMFVMMyFmcWJAQ25yTztWJlBaKlNfKyErMFYjTk9nYzkw
Q1Jedgp6YXFhRlA2eHU4QEBgcVBfaCp5MD5qT0NMPWJYKFFMQDFqYHwybVNyX2lobFhXPU0jMldH
dHRYPXI7LVcxQF5BQGsKejJ6VWpsT35QfVZIM2VjT1pNQEdhO3E+KWxLUHhWN14xSlQ/Y080eCZj
T0tlPD8oIXs3OXtTe2g+KUxucSVuSiU/CnpBZXorQWhRRm0lbG09b19LVGxtY2IkRkcoezM/ZmYm
e0soIyRVZXVPakRVckw8Y20lTU1GMl9ZXjZtRUA8I1B3dQp6dDAjKSY5PVFaZXdNSGdSXzlAX3wl
XiFUJGoza0pVJGU8PDZpO359YUJucH53ZzgrSXUtWC1FbmR2cUVWeWclT0kKeiVhdWN6anEhWWhK
VEJtel8oX1RgZlprZU5sU3JhJXs+I0AyS0pMUHc4fnkrSTt7UVIoS2oyODIrb0xTaSV2cWlTClA7
fTVDZCltQUNGVjtTOylIRSg9RQoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEv
YXBwL3Jlcy9lY2xpcHNlLXBvd2VyLnN2ZyBiL2FwcC9yZXMvZWNsaXBzZS1wb3dlci5zdmcKbmV3
IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLmI0MWU1ZmY3Ci0tLSAvZGV2L251bGwK
KysrIGIvYXBwL3Jlcy9lY2xpcHNlLXBvd2VyLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5z
PSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3
Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik0xMiAzdjhNNyA1YTggOCAwIDEgMCAxMCAwIiBmaWxs
PSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9
InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAv
cmVzL2ljb25zL2hpY29sb3IvMTI4eDEyOC9hcHBzL2VjbGlwc2UucG5nIGIvYXBwL3Jlcy9pY29u
cy9oaWNvbG9yLzEyOHgxMjgvYXBwcy9lY2xpcHNlLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NApp
bmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi4xNTEyMWMwNGJl
N2E0Y2I5ZmI2NWZmMDk5ZDc0NjdiNDQ0YzZlOTBkCkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCA3
MDg3CnpjbVY7ZzgmS3FsUCk8aDszS3xMazAwMGUxTkpMVHEwMDRqaDAwNGpwMV5AczYhIy1pbDAw
MHx5TmtsPFpjJTFFPgp6ZDYtPCliPk0mSi1kQ0B4eUx3ZCUyXyZfSWdwaztnRmgpUlpnYmo4RWoy
Rk8tP0hDN2RuMmhsXjhTbjlZPTk1ViMKejZNclU/Y3JyNnkkbWlJMmE2RkZVSTVPaXZqMkZPUXZ6
dlZwbEYrYE9tVV5rYCtUT2VPJXBiMyspb0x8RGZWI1JgCnpzJFlNdktkSE9BLW03PWNKQD1lKiZw
bDc1RjlNK0tgYClDNkJzVkFGaGAyZWpZU2sqVWFePWJaMm1td0g3Y2BBOQp6SyhLUDwlMyMmMVJS
K2ZEI15MMyN6d3hTN3RJVWx6LWVgYiQ/OVl1Z3hZKEluWkBzbGAqU2NMe3h3Nkx8P3NIRlAKeihx
V0lBeT9BIXo+WmBCTCtyV0Q3e1A+cHl0NSZWQEh7TipUMGwjPVg5NXd+JD4rNz90U0ZpUnwmNmxk
bUg2T1U8CnpscFdpKXpIeFlIX3pqaEVkMSlORzxEN0hkcz1nSn47QmNNJGgoSUozRiRIVndLb0ht
K1ZMSlZNTWB5PCkkSVlHaAp6JkBEZl88cnh2Rk8kKlozKkpvQypVaE5MY1g8elJmUjBaejxZIUxB
TkUzUDxlKUF9diU5VWRDR3Z8SzhtPUFFPDcKemRBeGQxdCFsXlhKP2p5UVIwU2V9NXJlZWBXMzVZ
UChvZU5AdypUQWx6NEwka1B5Zz5Ia0htM2VUKnV6fipLeHwlCnpefHVDYXNaQCRmUj0palJUZW9m
ZlI2ZHUjSUYySDUmWT1uanVCeUV2YF80Q01iSntlZ0hhLStrUlRVSH4wQGhsQgp6UjclXzArSX41
QT8lZS0lJDMxdGhpSn1PPTA7ODdxKSQqRElRUFZzeiFzVkE7eys1a3YqTUI4OUpiWGM9UW8qWXQK
ek1xKXV+JmRXSUd3a2k5QWJIRmBIbG1ZZVhIODNLQ1ZNdHA/YCk/TVhjKjBseWBEZyQ3RUE+aHJl
UmVnay1XdDNYCnpYO3tHaDsyWW9Re0Aqdj5APmwpK3lSUiNrJTZScU83XkJ0U0g8Pih+X2c7Kk1O
b08rNW9PUjYyKk1JeilLbHxWKAp6S1JHfVdaTjt6ajI0aWAoM0o/SkNScXdwJjUxeFBhc3FZTEE8
KDlAU1IlNDgoRGZvS2h5IVI1PXo7dHhCS1l6KzsKenIrKW0wfEdONUtVWm9QZThVP1QtO0AqRDIj
VUl8aGUjNXMkM2RKLStFRncqQmVoTnw1NyRzPVF3cDMxN3dDSzlxCnpAQTx7fFJNaTU5RyN3bk8w
dDh8dHpHJWUtcFdEMjclVDB4MTVvP1UySXFEayk9ZUBUckVpTHIrX0l9fTQ1OGlXPQp6YGFASEtT
SW98PldNdj5DQHI1ZmNffXM9I257TyU8aV9SRk0zUmJDbEQ5dk40ND1jdUtwOyZhQUhnRXBnZykx
KWoKem9RU3hVdGI5ZjVkezcxRz4rNz8zYjllbFFEPSlyZz4qZyZ0bH1hVU5qRzVIYldSdXM3Ny1M
TVNSRW9FNS1nNDkxCnpGU3opX2NYTX4jKlZsSllFQiYkeFB6JmB3Yz09VzV6UE50RiZCYkVUSC0r
RXVoJXY/JWkkJVkyITs5Yms7TkA0SAp6eUwkQyVjUTdUR1A/KEJ9QW9BVnNleilVcXtfRUVzOXZt
MXZMNXo1czNwJiNVdWlsJWs/KFglVWBTS1Vlez5Wb0AKekdPVlp5cXZfO1BDUkJodnVzPTQmb3Ba
KW5IfUJsR15JR1IhKTd6aEJzQV9ERDRVVjBBP0I3NTUjR3t8Xi1jUlRoCno5eCRUJnpeKEBPLXBr
JXxMSTNWTypHNFhPaCVfQyhYPzdyREJOd349LUZ2Uj5kKnxoRTIzKzMrUVFKZm96XkUkQQp6bVlq
QyktYVB+N0F2RDlpPjVEX0xHa1NWe2BgRnFpLVlnPUp0UShCN3A5U2NuJmpTOVA3aFVwPmR+VzFD
TVZyRSgKei1kSUlfSzlAV0hUXkM8XkRkNUxEZ3lTdU12RFclaVBkTkc0MU8wbjFZPnhnVDAqN0x7
WFpHQ25eIWpKcz5ZT3UtCnp1Pnp3T3Bqdnc1YGAqKkh5cFNKeHYjTThgIWFvd1FVT2swO3sofD5p
QHhFbiV1Z1YoTy12Ul9jZUQxUWR6cSk8Zgp6anhSZHpWQFpEMldjbXt1Vn1kenpqe0VCVWszYWsr
I3ctfCheI1BvITJFIytTY1IxJmVYM1QjaVZWclhlPWtvOCsKenEhZSM3OTVnVSR7YEh5PGR8K3cw
VHQwZDFAMHVKRDc9VXVBYm4/fCNVQStYKitCOUdRP3otelAxRiYoXl83JT4jCnpMdGFYM0dPY2pW
eG5TJG9PKUZyWiVuaVdaY2kjO19GYHItVm9udVN8PkpmI0FBUi11SjR0bXNIY08pU3E+WVphRwp6
VXN3K05XTHxVZnlzPyYyc2wzI0E5aylxa2BlSkg9UlBmI3QjU3V+TGFOZ2wtNzBUMks3YlU0JDlh
RThPWkdhaUMKejItRWtAaTFTTGhSNmZhQWkrOVAhZ01qMkNjXkFqXzxiQH5BUVB0fExuNFREODVX
cVB7cDtEJENNfGZqc1g+RnlhCnpyLSN8eUdkUU5CbGdAMEdiU2d4UTs4ZHgmbX0wcmlOVT16NkIr
dDskRmhqI1JxTm9CMHF2fHEhWktKM3ZRNTROXwp6YWNvN3owczl0c1pvVCFedG9Mek9FdDVQfFNO
VTN+amF1ZyZgSD5NUy1xRl80JmVEWlRJT2x7RFN1dVlSM3A9XzwKenQxeV8pdjJBRjhaRyhIK21D
diFhVHdvfXdQKkhgemw1V2l+dWN3UHNKMzg2QmNRMUdUYFl1dnwjZnNUQ0VoemdHCnpWcF5laUA0
RDhrUzw/I1NVYCg5OVl1JkM7b3dsTSg4fVcrPlJ0KTgrTGNVbGUrdCRWI216fkxGJWcqTUtnLWUo
KAp6QT1gS0M8bGc2PjthbHNVPEkhRFBkMng3dlR3TGJCcDxNZ1czSyhuPGtQZyMwPWE1SitBX1Re
Z3ZYOztXU2QtKykKelJIdXoxMm55PTdiPX5qUnJLdUBecTZvc0Mke3dyZT0+SG9UMGoja1VxWTVM
JUJKKmE/PUlUR1pnYiR1fDk/TSQwCnpDfmV4eEtpX2REKkZXPHBfd0Mtc2glMTl3TlRtbzxtZSNR
Q2ZLTkRIakg7Umx6ZEd1akRsVSNGI31PaHolMzlKawp6TUhtRGFHMUVkM0gyRGhsUlFGe254X19v
YHp2YVhSI1RyQkdKJHJ8VFNhfEhRZUQ7ZD5AdTZrc2E5bV9+PjhZcHEKekA8WD9CJVpwRjV3VXxw
eGRZQj9CO2klYkcpbnVGNkF1dSkpc0JQSipRSGYoSmFnMj0mPV4jWlcycjtJeTY9NVJUCnpQTWNK
KDBMRUdkTUBIeU1yfUBHYVM4P3FoeW9FVk1DSExzRmVDNSU1YFIwWnZkOHc0ZzF9VTxjUnpVSHB4
SSt+OQp6dEdiPnNtU0xuKXJXOGVGUVh3cz01RHtyO01IdEpwUHlqMjJOSWlvP0wlaWU2di10OD1T
OTV4KjRXOE0remRaZFkKekgjfmhtJmtWanE1UU1hYUVzNDNGMWZmcmFrU0skcTZlPWFrYVlReXU2
OSViaXAjJS1EMEQmPiZEcktANXpKQiRgCnpgMCk4RjNEJDA9fEhZQGQ7cHlNO3RyczIjNyFgYjZD
JjVwSWh+VSZRVHE9LUJnPUU3RkdCJCo0SypsTFJWfGY5QQp6dkZ0NjNhN05FOHpXRkRBJHs4SXEo
Y2VBSlY9cnl6O304RndNfE4kY0hRZlIqckdnKWVSUUd0N3E2KUVodzFxN00KeiN4I2YkOTRPb1Vv
an4xcE9mYFlBPzlTKFMqV3kkNyl+N3lBK3dMTHMhTjw4e19nNFArLXJNTGU2PT0ofTY4cHZ3Cnp7
Q0dyISpnSit4QlZAeEMhWFRMUERQYmJuSHNsbXd0KSlNZzxLeFREO3Bfa0xLVCYqazlsYGN+eyZE
K3lLNj53TQp6SUU4RX4tTFMmMUFxWERHU0JobEdrWndTfnB5OEgkdHVnRyQ0Umlmaj1rYSZmZjEz
UWAmeXdBLWhnLUw9PDNzblgKejBmZi1ueDtjNVRtcztSQlFnc2o7WklQKj02ZCo4JEo7ZWVhSk0k
Y0ZgamJ5Rl53YHNNXnlnVWYocT15VG83K2VrCnppIX16e1Y1OF96OEw1PTB4VldLfHBrV2pzNU1p
S0Y7K0BBVzxtO0ZKNXhNNiNrbGkpRkwtfkhMeG5+V0NPbCNyUwp6JGRgLTYmTldRN3dJTVFyUilw
YT07PFQ8fl9+eDdiMUxkX1pWcShXMGFlVX5XcEU2dTIpMCM/ODg/JTJmNmVWOU4KeihWbDY9UH5V
cSFrISt7ZjB3QEFSLWpmWWRlRGo9KD19TSgzI1dBZzZubT5LdVBNI2xsaUVNYWUycDx5MSgwTkNw
CnpRcmZSPz5Rb1d6end9cHM4KDsrbnFZOGd9X0ZHdWliMWVPWkpUbyhge0tNTUVgTyo1UFhpR1A0
c1B8ZUM1aGAmKwp6KzFmZnMySUZOYlEpPmFOMiFtMERPWG49KTwwcVdYUF5teVJOVT1GTCRQSkko
TG49dCY4ek87bl96QDlgUVJSPnEKenJZNEk2NmApU0w3ZXlpVk5Ab3pWPld1VThzPkkmWVZndnJf
c3IlV1VBMCV5cVk0N3dNNERVVXFzRkZCQGI9eCglCnpLbD4+X3l7PHQ0QlppPyRuVTV8JG96dUgj
RjxkRnJrcVVXdV9qYk8me3opPW5yZVZeJWxaQSotaiQ+bHlzTWMlTAp6VD9lTFEzSns+PVYmLVEl
X3s4RWZDYE0lcmtpemdrb19tQnNyQSMwVjZRTkVqaWMpZ1hsdlFDKCR6OFQkJGoxQGEKekVJTmdH
Kj4oelhNQW9Ld1YmRW0jWTxWRm0jWDc9QWUrQHkxVCNUQ3tONE0/QEFWQXMyJXhUVD97Xk9UWWlY
dT01Cnp0PnFzI0swfmZ0QVNMRHFiXlJ0clJqSWhDTmZWRCNmWFNiTWowcEwtIVg/S1kmIVRKPmcq
WU5EaFdfRlJLaVRwRQp6Q1AqRjhqXjlMeEJ2d0dSKjdMYzNVTy1VcUVQeilmWjMzPzdVNHJ1LVJp
IWx1YDFRX0J5ZkQwJW1aTU1zMEd4VXYKej8/ezx8JCpMVX5GV1h3WF9xdCgzRDdjN3xKN0A1UThN
NyhHaVRPN09jV21FP0kpYGJIOUNfVlFsNHpqTEFIU3smCnpBUDhtZXhNMD5peD42eUxhfDl2YFIh
WkVyZG1DY3k1dTVtVkJ9OFBAQkchfW9EUyMlPFBBSFopQTJTIXtlS0gtMAp6V2tZVXxiQEBSO0pN
fnBGUTtFfiRwNDQqOz58WVR5aUIzU1c9O041M1kyfnp6OSFoWnhzKVdZeV5pViR8UUhnOVMKempY
UjFKS3ZBNmNTVGppalZGS0NLJT5zeEJDRmVNeXQmNz58Und+WWNDV2BVdyY+cnhPemF5ejBjd2dV
MWE5bG1XCnp6T1R0M1FwZUpjWlpnSkYmPFgmfmQpRFdOS3BNTXp4P1hyWk9wKyV3ayE8VCs2ZV5z
VT9FKzE8WGM/ZCEkODBPKwp6c3xzK21CbTRDJnMwVmRaMDBqYWcleGheJih3P2RhaEp1UzJ0ZCFz
PSReOVA7Zmc/OHhAVCM8IWZTS3RHdkc9R1oKekNvZWgyaD5Je0g0WTQwI3Mrc0lXKzw1QSQwQkxM
S3UmR2ZDMEUrWER2aUZ6PEQzNTlnPktnXnRyemxpTmRYb21tCnprZz50T0RqMShBIz9jKTZQZlhJ
SztxYnJmNnhJVk1pcDNDQTlVVX47eEB7MXdzaFImfjcrN3NZUGBBXktPOVV5Qwp6d21ERzh6SktF
RUQ0cWJKKWRXZjRCT0xYIWZCLVVDN0k2YUUpLU1zbno3PztVNTsjPmQjP2xeeUI7Q29IKVNKMn0K
emZLcDhidEVVamgpcEJebmRyIXQjV2A+eitTYUBgIVExX3ljeTZwQFM1c0o8Kzk5MXdYKW19WUgz
U29Yckl+Kms/CnpVPFhJNWpWVUs1RD58aTRwcGolTGN6M3lvbTh1VT00Rnlsa2NHN2VKNlk2YU4+
Z29lVD5lKjd2VktmUTwxYztwRAp6bChyZElZbWRyR3BzQCVeLUB8JClnWF5BdVR7a2pSJT5nTipO
aFdZZlliVWVQdHdpZE5ZQ0RraEUzVTZkPlEpcjAKekNAQiV2PF85UmNDXkBrelckJjBCd3MyLWc1
M3pGeEhmS0ljUHswX2UpQW8+aylOTjt3UzAhYUVGQkZFQFJWb21XCnpHKndpdXF7TUxIajUjblZg
TEY0TkhIa1J0QztvYjcwdUAzcnlpX2pvUkJrV25ZT0BDY2lnQ24rLUUoTTlXdkNwYgp6KHx8eUF7
O3gwbEU1SWJIb2Q2WkB4cCFiRVJ0NGBCS2BGWUpCYHV3dC0hKz94aTt1YyNLdUpjd3NuO2dhRzFT
JUwKelA9JD1Le0FUWUMyQkgjeTJ3R2hidkxha0hgLUozbV59TUpDQSZ7d2dMU0oxS3pAdWNXPEB1
Mzg5dlJ3QWk/TWsxCno3JDZzd2RFMU9Sb1lLfXE9X3MtU05ARHUwblZSaXpiPkFLPzJxb3xNJD9p
Pjk3K28yUnl3WWh5SzZjeV55bXY+OQp6QTBSLSsyNmVnamh1e1FHe15gQVgrSEFuamA/cz1nV1NF
UjMmWSVUYHFCOEcyPTZGdFBwR29tM3VtV0N7dE8tYnMKend2dyZDM2UtSWpxKEk2VGMyKXxrZXJX
QChDY3ljYDNkSEpadm5mOD9kKWt6QFBNS18hcSV+ZW9Ebm9lK0JjQ2EkCnojUHE2VVpOTHdBWkQz
T3xONGpQT1IyWWlOVHNDN0tAMEB1Jmd9OHp9MDxDfXtOc0JLQytvKyhVO3FYKmxPV2pjKgp6Wjdp
RWhkSCFMP1RDJkZDWUt1YihXIz9HY2RuVThQUnd+e2ZRNSF9REQ2NDA3a2ZBNClxMkhDMFhsUlBB
PUt1dyQKeipEVH56WH0yTV8+e2AjYHhqa2VoaTNrS0pJPiYtXm1jTipQN0xuRn0kTHdVSEI7Qz1A
WmtAXmNYa0BnWl5pKCoyCnpQfHJscnhJO0NXMUJjXj98Ri00SChlckU3QXNtUnhUcnMxVVBhUyhR
Zyh3KiUoO2I2UUAtWXsrOW17VENWWHYhQAp6IXFvTT9rSm99Si1IcVc/PT9xZipWc0hvRitxc1N8
bkBYQk9EcCs3SnVKQzdiUFVXKG0xPzEhRC04amwzNm53PF8Keio8PEpxR0NXb3FwakNuPy13cj9K
Y2VMZ1plcj8tUkpkKW8teTl0UFd2VEBXYFJ9MjY5ezVTQlhqXm4xUzU/RiowCnpBOH5yN257JV9y
YTdUVXpxMTN4bUBXZjFUSHx1TVU2ZVNSJDtBMXxzPUBBQ3dHTkJrOylnUCMrJEJPV2M8SW15egp6
X1NzYj5tX0V9JVA1MzhnST1RbElLNUtIQERYR0pmZUVLUTF8NGQ8eyRnemozVDdqbnZnTTUwXkJO
JnA1Vk8oPHgKenkoMlcxWiFLRUUrcSZrR2tJUj9fLSVNV1h6Y2I8XiZUUSVDQmkkIShUWWZ1Ujtz
UjswYiM/cD5yVURJUFBoKFpPCnpmez1lNytRRkIkSzJBJEBhVWB6cEF9O3dEZ1lma1FaeyRQQW9K
aGV7YU1lWW1NI0VHK2ArfDNAWUA1d1RYUG0lbwp6YDVpbl85d09UU15acjtHTWdidFAxbD5XJTVC
NjsyaFY0KCNCMDtzNUZsaW85QHM2XjBlMGxFYXs2KzZfR1I4OUUKekJDSXJxSEFxSWlQfUNUVUBj
IS12VC1DWE5lO01BKzFFb0UqSEpJP0IwVXNMV1JHREV6elNxQmpxSWNZUSstYj5VCnoqbklNbzRU
bXhpbSRgRHIwIzBlXjstKCE+YkFONihmaWF8d3ReNTlac1A1KUxofTA5fEk1Rih0JUZiVHFyZHMm
SAp6Jj9YKSg0PHZieDFgfEZzbTw2Y2VORyFwUl9ITj8oRXNycWJWcD5mPU1TWFAjayszJV52bW5n
IWNNSU9nbSokKyMKenRXPGBQeEkkYz03VjJSV1k5cnBFNm5zcEZPPnQlQ2RfRmFFMzdzfkAtdyhk
WEJqdGdyKj42bDVfUEskdkQmMDJaCnpTSHJ1d3JnQUBqS0lhVGhafFAjZG1HTjViSXB8eyljPCtu
X3lzM1FfS2k8MkVwQUshS3pmIX4pTHN8Pyo0c1h8dQp6K0d0bWxpdSUhTT5uKyl0b1MmVl5hWHx+
dVIpK2NVQEskIWtDMGZLYk95akZWY3k4ZCFoWU0zZHRWKlgxKmlnPUsKej9aeVpBPGc2M3Y+ejxF
QyRAX1RwYnB2c2t0UFN8WXRSLUM1SElGLW9ja3FraDlqcV9zQCFuJl41TFQ2O19SKHI4CnphajtK
KykkY1cxOyF6Xj9xZ0d+NHMrRkBeeD4/PmJnSlhqWE1lbiNIemteP24/NHFLY21XREk/Mmc8aExl
MVAjZAp6UmF6diNwP3IxYyk3K2NlJV9uRF8ka0tFTkJSKT1pMH0mJGNEUWFTZHxFT21ubXZ6cUwk
PklSTiZGfCpQO3ZtfjkKejF4aSg9c2NwYjghaTM+dUVraEEySVFCSmY0MkB4U3MpWkI3YzIzUTd1
Xj89di02VCZuZDcrJSsmWEhYX1J+YVRQCnp3aUBhK2xKRjt7O1N+VXFrIU9IVDh9aSRjZWplWDZ6
PGF2cGFiO0k4JEVJMitjJFh8MWt0QnxhYVoqd0FoVV5UXgp6WnRZPm5TSitlQDtlfUY7Yj4kcX1x
YXU2YkdJPHstaiteU0p1bmE7VkxNV0QyWXc1QmZ2d3tyc1FteW9jUyFVWXwKekV5aC14VU1NQF82
MkJ8LV5JJmxnQ0gxc1EoKDg5UjJwXmAyMD5IazZRSllEdSFUO0hfaylJRm08a0hTTHlzaUNNCno9
QX5NUkBEI25QJmlQNnVfRXFIKFBFNUQ2R31EMXNDfkN9emleO2l8eXBKZShQb3k1THpCVk8+N0dy
NDxPREtpXwp6Z0JNSy1TRXw/WFFlNUtFKGZ8KD9fY0d1cldVODs5RWBxTnllc3sxb2p0NEw/ai0r
Xl5CUzxtaUJFSGtWZmk7OE0Kekk1KnFGJUM9YzcmOXV7UTE3Y041PldEbDxjdUZvQW05QF9uaWxI
WStHbX5eO0B+YytCc2E3OURwWndufCNOeHEyCnpMMVEqbTNPclVDO0Y8QztMb09uMSV4SHJQKlUp
IXZWKClITDBtM2tKZlVEfmp5KyYlKkFQfUp8Tkt3PzdlO2VNOwp6b3c9Uk40X2k0aSk2SG91b2c1
ISM+OWlAYjFnSzNPRzRFN35RQyMpa0hFVTczRishNVI3bERjQExxMXwjUkE2bC0KeiZrTDB0SkU5
VH1QYmh9MG5PXjM7Tj5yNktGaCY2dUZKND5gQkwkIylOLXBhKVAqVmhwJnsxezl3cDBxTkU5ZCM/
CnpASyhCUCRlZElRXkhReEc3aTU/anEtaSQrODNfblBGeDdBX1FjcWJ1MXNebHlCS0VpbnlQX2dI
O31XfiNHUSZRPwp6WHxsSTU2b1goVnY3aElwcEA0e3khdCYrSSVlNWEwcXh9aWgmWVJvJl98Vnxj
c1VxVE8mP00wLUF1IXI9RnZnRkQKelpPUFdGV1BWUm89WEZ6Y3w5I2FlajU+cj51aXJ9STVaWXds
P3RZZUg4c2ImZWJhcig7d1JQTChXZ19BTDJ9bUA8CnoxVlB+RCZGJFJ8b0p3UTYwUzg0UGFuPlg7
PCQ+KH5hOCE+SGRuRj4/QDl6WWBoPiNJT1pHRVloRE52WitxRUFxTwp6QWgwYHZBYUVvRCt9RVo2
PEdsMGZGI1d0Pi1sailGPDM4T2R6PTtATlhxcV5KTX0oa1g0aXlhUEYhUCpxNHlwPlUKeiYmKEB5
dzZ7Tk10VSo7OVZSM0N6SW9LTmNrJSsyX3Y0KDdXK3dhSHoreUphJWw/UGFgWHUqVDJSMW1BYClh
K0RqCnpHRmhtcSs4fnZSN2NYQTtLPVB3Uj0zX14/c0gmWWVYYTRVODFfbjx2WDhKbVVPJUF8JHVl
UTZwYF5sfV9IIVpJXgp6YDNuMEIqb3NLcChiNGZVWVlvdF9FMHw0UUohLTk/dEUyc0FScXViKSFq
RHd8NTN1QjwjczQ9PGh0N0x2JDM4KSUKemA4OXBOeW12TkNoaT5zbmkrP20kKV5PbVM4eHNWOXBF
SVpUU04qJHBVc3lGMk9AQ2x8PDVibm1vSF9IWj9LYCU8CnpISThHJDd6RyRWJDRlWj9eIUUxdFo4
ezkpTlFlZkhjRHo+ISElKmZnU254TS05SypPbEtUKWA2UkZ3dHU3djleeQp6eVo8fmZgX0NDb3JX
SD1UK0dDRUhgUCs/flV3bWA1MythQm8tOSVvI2g9QFA9bCUtJEhXSE5aP3NaSiRSU0lGS3gKelVk
eTUwY2B9KWRvX3kqX1UjdzImMk1xWF5PWlpyMGo1fjRoKHdueiMtRkJfMiMhUkV5ZmhHWE5BYDxr
QG58dCV4CnpiPGJidHl8K3hUK1dUXkd6VzNnbiZ3VGJqZjQ7TWBiRGo0LXBjeGlVQyVwR1E9PE11
Vl92ejJ4X3l6QyVldmFRKgp6VVFQa0RrM1BCWHk2YzlQRW5qfGhUVSlrViVeJk1qK3FMSExOKGJ0
a0JpcShtS0k2PH5BRys/a3RBX2dNZClhNVAKenlpKDVKMGBBOyUmaSYpKCl+PnkhUjRoNFRqNSZu
QVljZSZjX3Vna1I4R0Yqd0NEK3tsO1FpbUhEI01yaWdJN3hSCnpJdnt4UDtSbjhkIXRvMH5tcmlH
X19rSnt1KnJjSVFANFppX0dqYEYhPDNJbzRMbDFuUCNCViFqbURpejs8aUhwYwp6cEstPDtLRCUr
X2hRQlRyaSYkZnZIcDliKUspXlpnWjY9ZHA7bGYzcWY4dlFwfEdNaDgjZlJ7Pmhsfnt3d18/VGwK
eipRe047X1MrKlBCV1YkZE1XaClXT2QqUUs+TlV0X3YqamdBbVIkRzExSFprY3h8KH1QXl97T353
YT0rKWFSMkBICnotTGhpRSolJFRuXmdKaEcwYEkqWj5kQmZNUi1FQDwxcnlBZUcyezZhRTYlOz57
YD5Fe01POXpYPzJxTnVGODlXTwp6ejVWdnZAQjdRWXtQWGpBZCpeKy1DRFM2X3RKUzJscVhVe3Jx
ZSpre2ZoND08KXZJbUV2YEJDN3lsPnhkISskeU4Kel9TPGl9azdVayZNWUJKYSpYcXEleiFfdEI+
cyNOeGFfI2ZhLVooZm95c31hJENsN0AtNT8zRHdVTW83U3FPYXFXCnpNKypuc3FwSkFUZCNgfkFn
a2hTX3U4dzxfRUlEYl91WVl+I1U1UV9RYUJ1KFJjczxnbmJ3UDFxbkJ3ZlMmd0pPXwp6JjZ9PHQm
Z0N3eVI0UyZMSCRYJWpBfWFlVUxzSlZUclomIzI8JXVlXz5NVXo1VkhqI2hYVTh3KyY3MSF9QUEw
Q18KekthSFhZNjJaVWIkbjA8a1YpTyFuUktVZC1VQWxiWiMmdVQ/NGkzR2VSNFNid01YYDB4cTNX
dyFsYmFGYiFBVWx5CnpoIzBLM3EqOCYpV1lTTXtiIz91MCFRdz9mez8pKFZAbntye1RLVSZCPmkw
an07YlQ4ZFI4QEtSeVJTTlYpMjgrMwp6PFp9NzUlSGA1WWFVMzElb1MpJm5aJmh1c0VzUkJrKmNl
bD0qNmE7fSlYc0R8XklTKHFgeT16YEZNNFJybnR5cyQKekx+MHt2KWJidmReQiNeajhIY0dKcWlR
T1duNk1+eyYzQ0BEQ2M5PEpANiFWVm0xWWlNNEJnJEs+K019JHtAQk9mCnpKclY/Z191aD9mPGA1
KT5vSHJpVUhKUW5yaSkoWCFFejxCYjduQlpfKzh9fmBSJmBTNSZVIW16UDNQfj5zR0Zubwpae3tp
PUlkQEheXktxdnFKMDAyb3ZQREhMa1YxbUVCMihiVkYKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoK
ZGlmZiAtLWdpdCBhL2FwcC9yZXMvaWNvbnMvaGljb2xvci8yNTZ4MjU2L2FwcHMvZWNsaXBzZS5w
bmcgYi9hcHAvcmVzL2ljb25zL2hpY29sb3IvMjU2eDI1Ni9hcHBzL2VjbGlwc2UucG5nCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAuLmExMzVjNTRlMTQ5ZWFhOTBiNjEwYTY5YzhmOWJmNmRlYjA2YzBlNjcKR0lUIGJpbmFy
eSBwYXRjaApsaXRlcmFsIDE1ODI1CnpjbVg5X1dtc0VIKCs9KHFNVEAoO3lGPjkoK0AqTU40VWl4
JDQjbkxJNmZmQFgjaTYqbnlJYzczeXgqVEJDKWJ8Ywp6Kl9uSDBYR2JENSlEJHBLTmwqYSowRVV2
SHRRRyhPMU57akRLdF9hcThNKiFiM0lLP3VEYWxHe2AoJk1VXyt9WF4Kel8/RW5EJmsxPi03YEl1
Q3EhNWxvd1hZMkdCZCFwd0lQI21GNjRmRSNCNjVkMTtpbW47QWQmJWRDYVFudnJHQEVACnpxZWJU
bGxebnlSPFQ4c1ViY3wtSlBHQjJwVj1abUNeTHViRlRpPjhLU1QqX2V0I2EtNzlDJmhkVXtKWnpX
YXVybAp6O29OYUlafEVFfXZ+JVNuTioqX35WQExIKk1JeSpmOXd2TlBNRk1NKk90dXVxbS1oX2VB
M2g+dzk8fiUrdUhGdXgKelB7dzEoNGNRbW8haUQ3VUBJM3I3bCZiMCRkJSRzVjx+Sj5ZNGdXZ29D
K3lZNzN1JlV6ZTx5ZD8hO1ZYfWJad3B8CnpeTTZkTFBpekB5SlV7MV9TRmlCSVNVSmt+UEUxKkk2
RTkzcDw1Y1JgNihqIVpSVXNPMzZeJm96OCk7enRaeXJ1MAp6NEQkKE9EY09IJUlQM2k5MHpwKTwr
bD8waUN4JlI+LXNqZkp6MFFeY2x2fWpMc3wtcTYlWExeaj9KJUMjeH5AODkKeipHRE9hRD44PHN4
OUQhQ1MyOEJhbGAxazM1TFpVaEJPfkB3a2AzP2tiaEpwWCV1REJBelY/MWMlVzF4eGk0eTRBCnpW
ez1+bTclRFh+PXloN25gM29tbCVVJig1JDU4O19pNj5CKysyU2pFdEwlYH5ASDgyQ1R+e3RwMGxL
QW8zd1MlZwp6I0tPIXJGNGZqbXhicComNEpgQHwzaVUrRCRqV35NQVA9d2QqaVVMbz1GOCpmQ3l9
KCs2LV50TTJaSmUqayRLV0IKeiNCKjJ2UDB1fVBPdCRCRW1RKUp1UkgrQnZDdVlgajV4Q095e0JB
K24tS1MrdllhbT44PE8yXlhVSTNERzFXJVVWCno1NSsrQl9vWEVROW1VUUVJaUhqVnckdFlmKnpu
fFY8XyhOP1ZzcigrRCtoa19TMkp0dSlSe2N9TVlVYC1mclZVdgp6IXdhNCN1fHppfk4qTWltOyZn
VHZIKWhFRDkqZF9neEhTWk5AJj51Kl4welhvUU1SMSgqNn1qJXQ7a09NKVVpc2sKenJ8ITd0TFJO
e3ItO1FIWHlkNzV7S2VvMkVffnpgdCRaM1l3dkUjSTlzV0l7S0VBZ3pEQiRsKWdJaVJjMmF2P2JK
CnpuaUtzVC0jPEooXzRrPEdyanJuVUZLQnB3RS1gKGI0Sihfby0/NzF7OCQ8cFlyOGtJVERxREwy
VHpJS2t7Uyl9cwp6X1ZSR3JRZnRJflZCZiYzYnAyKENpe3sxQTdtX25DdVNrUHshKTN0NG96RDdu
RllWTTVqTD8raGMwSUUzYz5WdEgKekFmY2w/SCM7OypMWChDOFlhZ2wqdURFYVB7UWg+cnw4NE9X
KGtUWEhYSEZnTWNOTnZTXzR9R3pIc21mam1AYjc0Cnp6bCg8T2ZpPjtuQnZHZ0dgSzIwa0xoPTVF
WCR+MWh6VW5SQWYqIS1uRGtwZEg7SGlVaiF8bHk3UDdJPlo9NngzRQp6VEJfWUUjR3VTbExQV1JA
Nm1eZT93K28mKFhsUThRYV8pSjNuYV4/XmUxQVJ3Sj8ocTU+fllpNWI2UTY5cnNKansKeldedyZj
NHx2QG5kXzUtZ2hRd3ZCRz98SlN2MkpKS1JXQHVZME0qXk12Zk9QZUolSz14czhuYEgrJFdCZit1
N1d3CnpvNV4+Mlc5NilQK2Y3XjI/JjA0WSlXKiZ9Y1BBM0J4M2xWUlM1d18pUkkhJVIxfGtWaEBr
NnJ9ZihJMy0hNVdeUAp6LWR9V2J7Izx8QmNwUW0/UjRBMGZlNUU4MiVzfU1pSl9nK2VQO3tRXmRQ
OXlteXc0WVh5XjZHPz81dlp1QX0oITIKeip8eDcjWGlCJGJgeT1yWkNsQj1OZVdwVlFQMkh9LS1k
fip8JE5VYSktKntjPihZcGFVdmMwNHhGRillRzF6T0F3CnpBdzQ2eCU/cChgK2BJZCRtczN2Jisw
XnFKdWRVc0VSdWtKKD98U1JJZlRVfE5RX3FjZ05DWHZmUDBvWWdvK2Qkbwp6VzYyeUh1ZlJDKitl
NGZDKTF5JW8hT0RpN3NFeWZIIz54aVEmRkFONVpZK3UwT1BlYWNrLWVyPndeMjQwI2VSdmkKej1k
NXA2I05GJCEpOU5OM0MhcDdaZyhsfDxGfV9HQGlEUkpYM3Z9STc2clFnbUdqeWNZSzZma3x0floz
PUl0a08pCno3MHJhQGVtOEtQaSNkWjlKUmpFR0ZMYj54bWlaPGxedyFjJmZUQjQ4RjU0QTQlZEMz
IUV8YmVxXlBNaiY/fml2Tgp6X2p4ciNIOFd2IU50bk96TEJKSyNqYU82aCpLcyh8JUVrc15aPD1p
RyZgdnImUEVCfVBqXz1LfU98e3MyITI1eTcKeiMmYnJAai01VkxubXdFYjdgMU98JkYyaWAwKDEl
UzFjYEJTZzY5cUpaRjRzdGRAeG0oY1k3bjtUZyUlRkN4am09CnpCcD8lNW9lI1IyX15LQF5EJUpe
N0Z3NXxSOVk9UXlVQ3dLN0MhTUBneCMxS1hmcEdfVU4ofXxjXldYQTc7SU1oSQp6KkhpJSRWQmJw
IXJBemRNbm4lQSU1c2E7NmJpZklRYktwV042OFpCPFBmJWI8T3dLVz1aXnc/Vm88RX19MjxCbikK
ej9GOTE3Q2VWSWxKVi1SayRfb2hUP0w1ZjcyeigyOXNDPkVaP2dxfitLZCQrYVBzU0o0JiliYHNO
c19sLV5sKV9qCnpIdiYjc1JlI19WaHFQTiZWQ0AkU2FDWWNoPiphIz9gcHE0cnZyfm9TOShWOzV7
VHdvNUZ1VHlpOzY5b0M7UXYrfQp6N2pQYHl6MjJ7P1BfYVFuUD5RJX0/N2h9LStTUFItKTN5NUNp
Jmllelp9VEZTVzAjai1ZMFZQNV5xUzVBSWtNSUAKel9NR0Y3e3Awd2syeFlqa1klaHpjK21tOzA7
QnskdnA8dTFELTQ1RWJTazkzbzYqV0lIdGI0QiMhfFUjV191RG13CnotT3tDYkg5RENSYT13YiRE
bkBuTko8WClWYHxJNEBAMHszSWxVTVN8VFN+Xzc1ZTJPUVRUZzcmb20mfFc1KkU+fQp6V0lkOUIm
NF90MDU3U3RJa0ZfeXomZDtfaitIUThmKWxoK2N0KUZreldeUmNnNiRtKDBoZGlwWUJkbl4xbUcx
U3EKeiN0eW1+V14pS1YxZEV2WkspJjw5eVZBeDhpSUdvRU9YN35SbmJ2R2l3PUp4X1hjaGdfKmJ4
YzRiX25pIUVjdD5CCnplfndXZGMmNlplelV1amR6QH1rLTVENVooTDU4VSkrdWR0bkJITn5ZaT84
fTY5QSN8QyQmb1pVNy0+OHxjQTNOXwp6N3QrciNGTWp1TG1WI0I2UypeJCtrVVp8LWtjIXFKV0tW
Zk8+fjhuLWBgS3JUbXchPTtJJmhkdXZ0ZVk3UUhxWkAKemg5S1hZJjJCU3NHMDFUQjE1bEpGTGAh
KURgVjZfeC1TRGFsQ3YlZXBGLW4qTFVROXZuIz9GZzFsQEgwVF96VzBnCnp1YV81QlY/P09kK2wq
YyFqZHp7TFladnx4QypUV0w8aDQqdGVwcC1IPm9KTUAlUiZtSzReZlo5OCQwUEFaN1lsUAp6JGlC
WFgjUURxMHkzdXxQM1cqJVU4VVhCbTZvOCFIMGxuX0JGQV9vP3tUcChKY3Rra29nJStBaEY2MXUh
WiR6cVMKelJCXzEwdSpqb2ZjOygrdWkoQGp5SEpEUmg1MX50USpVeEopQztNemlGbzt1OT50b0tx
Vi01bSV5STxDeWEmKnllCnpBOTYxJEBjdVc5S2V8cnNgUT4/YF5DSjdnN2E7PE1PaylHZDV9K25L
Vz1ZRTUtZSR5SjdAYWQrSHpyQ3grMFImTAp6Kyt5X2c/RllzTVp1fXQzdWFgWVpzRjBzYmIwTSE4
b3lLanw7WDZjb3IyYW1sYitgel52NmxDej5qNDkle2BYTk8KenVHcEkwRnNVI05eUSllZFZnZjEz
ZCN1WChTNmZ7fUpjZ1EjKX11dms9ZG89VWZyVF5Bbnl4UWN1PUlRWW40KWZkCnpobjBtS1UmelZ2
OXJGbXpuKXYmeyl0RjlfXnFmNmtxd350V3UrMTRebDIoIVNDPzJaISU7bn4rOXBjczcxP1lXdwp6
WWIqYkFIWGd7TGRXaCNgZFAwYnBvWlJGbE5hRDVJZk4xVkk2ZjVWSFIzSV8qVTB0bF4+RGEhZ0VK
PGZKUCVWOUUKek42ME5ucl9yRll0UiFka204NkpJO05xWUxqfDNkZm1+Ymk0V3dWZztYLTgxNDQt
X31WdiFiYjckezR2PT1sKVBNCnp1fW42aXlkTF9USnB+WWRKNXB4PnxJaCEzPktvdW09I2AqPUsr
aC1tdiNkZzFCaGowditfIUNKcVBiZ2Z0Z09Sewp6T3leRjA3fTRrOUs5MTRfYCtWaFA+PSkkam9w
ZSZocU5NV3E8OC04WHV9ZlUmJn4rOTV2TTNhRXhWTl9oY31ANlAKejU2Km4zKChvSk0maz4pVmgp
bHZHVnROdGVhbE9ZQ0hnZ0lKZE5la0Mqam93azY/STF+TkB8P3Y3VWNCdEF7IylVCnpBQXdWMEs2
TTdZdFZFUzFBS1Rsb0p6aGZMPC1xOGBtYU9ifipWSzdlYDhgcTBtSUJWIT5jI25lYXolSHAoMnJG
Nwp6Mj9gamNCJn5taTIxQ15zazlTSCg4eEpAKXZkTGk3Sm08LSgjNm1fYiM9WlYoZlJDczwjJjwz
RE5RO2dfPzspbWMKemp4QEBJKy03X3xzVEx6NF9FXl44ZDt5WiVGO1I+PDNXc05FU1pYRXktJlk0
eHVkbWA9bVNlZCZgcTcoP1ItTyQ7CnohdDhjT2JyJi05K3lGdkVzdkBsO3E2N2J7NElAZFdXVzY+
bSUzIT02e1V+PSNobVo0ZzQ5Y1gxKH1RYCooc3R2cgp6NGFVXkw7aFJ9OVMpVnsqYSkzZlUxQlls
WCM+IzFCVXopVCVKc1lNfT1Gd25FJUdtN3lvdHR9cDBEQHdOMzZfY2YKemBTKHc8e2tuaCZZMjJR
MnRFTHA+M0U9YGs+YyRWMj11JClwPDltbjQ9ZngjJGlCKG5YIXBrQ3U9WkFUUGxgKyFkCno+VzF0
Sns5YHsrZGkkfHdIakx3RjNLJEVGRHooYVZoP3JBfG1AIz1vampVWDNlK0M3Pyt9fm5wUk8qeH1h
R0NvRQp6RHR6KlpNTzA+QHF0LTUpRTdCQz5SeFkpb0NCajJmeGooWXJWTGJsOGthc0JwdSEre1pf
YC19YU82UGojbXhMXmkKekVROShUbVZ3TSZiVHBOSHVpMUszRm1RPmhCQ1FMSSY7cENiPExrI1Fi
UGFwd21pfTktJGVAeTJnU249fSRTVGpeCnpTR0E1Y1hXM2BHUGFwSEUyPFh2QVowYkROXjtIeXhs
JnBBJlMlWi1VNDtWanVUREA2JFgrRnNUQktMNy1vQTZmUQp6Z0Y0MUFsVy1YcDE8enNLQjwoSH5x
SXRqYHtXaGJ8Y1QwPVE+Xj1GZnNHSElHKmgleDAodkVDJWVqaGNicnE/SHEKejc7PVY+Y1hadDVC
Zyp5YXU2PChkRjBBdyRDRyplQ24mSUV6KDhiJTVSWWUtejVBRiNVbns1fn0hPTlKNCRnQipsCnop
QTl7c1RJKnlkYTdEdFIkdkRlI28yRH1+TlR1PTJxS2g+Y3IpSzk9KXg4REs0a2l5NF9lUG9LJUYq
Wms/JFNvZAp6bzdXSDhYM0h9JF5UOWhLQGBPPCR5T01jVm58NnQjQzZTT2diREcyZERReXl7cFlW
RVE+S0BCV2w0ZU5gPz0lYEAKek4/VFlPSyhOVWt8MT5FWTZ7VGp9Y097MFZoaSEhdFg/O2xnIXpS
fmU9LXozeV45fHZBPHEwPEt7PjtxeW94TzJrCnpeamAlK08mKl9aOz1+QG9HNyZscSV1ZUY+ODJK
MmZ2akg1MWwpdjQ4dyYobEozT0YoWUIqcjQtVjZhd1kjdnxnJAp6NFE5UjR3P1M7JTgyT092aCgy
T1R4K2spZz42SH55d09jUj4yNHlzTE9rI0tEIT9ZWXJqRnZ7fUxoMWE4aHF1Uk4KeiFtUWQzMFl+
ZjQpTkVKJkFANH5CLU85ZEx2Q0hBdns8aXgrekxWX1ZSLVZ6Sns/SzJzSHhadklRQ1RhUkRVIXM8
CnpLaUtlZ3k7V1RGMDItPjctLWA/ZD1KTjdQbHRmJlNCUlgoZCRQSSE4XjFSbnxgNiRRQFJGKCtg
TEYoaz5WKHxTZgp6b1k0Zyt5NFVvKTtEbTQtcyQySiMhak5lYW9QNTNWJWBEM351RikzMXZuYiFR
REFWMnlPUCF5a15BVX09MT59WmQKenEob209JXB8JUYxNSRGJmVSNCMrb1VET0ckTytNWmk3UTdr
TTF3YlJpeD90JFh8UHdyJjBTbXk5flcoVkJRIz07Cnp3Rnp1X15TUGAtZW9oaDkmbWJBYS1qWG98
aGxncXNrKztNQWwxUnlWNmQ4SFdLTiNqUnUjX1dXTyt+NVNGMkt7aAp6KiZuVW1QOWApT2V3OVlA
YV5PZ0FCYlU2eHBxZUFXeDtAKSRUZ2xsREd0OU5QKFZ6Jlk7ZWAyNERPPm1fVmRCWmsKej51aWxB
ZjwmPHBqP14tVm5sI2koUldYbEdYfFRgS19PbyhFQ3QqX1EhVT4rKi1vcFooJWtGLTxMRytBWlhw
bk14CnpKRXFUX3s9cnBqeHlpXyRPfEFsRTxsb3tGVnhOOFM8eHgqPHZZV2EhIT4xdmVnYDMxbV8w
TUhycmItVjlQI01eWAp6dytAQ0c8flpSUHErM2kxM3khVCtlIyNAanszWSM0YS0rbX1reXxaUHcx
a0tsUnBKNzRhfDFDaUlgOzN7QTFtRFIKejNgIW1zPCZQJkZpXnxDaGdEQ0ZBaGY/eyl5UiRfYSY3
NCZEJEVJPmRjNUZqJC0zPUtyY3grYDZeMHtfSHE2TEJyCnohdig7RlZDdGk0eSRJPzh6d0ZkKDR7
aSNkR3RjKFotbCNtQ2xFPzFDZjROSzJLLVMkNUBjWmY9RWE8S08/YlVJbQp6RT9uP2gzZWdFJj9X
P0plMU9hYX1XaTN+SDFDOUpvRXxAQGomSkd7QXc2RD14e20zJFZ4RnhyJnlFNF9qQUQjVU4KeiR8
O2VWQjx8dG9SM3tUaz1oOVFoWnhwUXNLPStGc3tzJjcjSFM9MS1SKz9hZm88PVl0Ml9GTG4mMlI/
VEthRmxgCnpGdGVMPzMmU2tLSHV8fm1qPk1fcEBnbWh8O0g5YzlDfShkLTE5K0BvN1UkSDlmaips
ISR3TEoxZTtuV1RHPXVsUgp6cWdWTThpXm1xdiUrUkI+IVc8cTclNSZCeU4/SG1sNFBfdXJubmdR
fDNZLUN4cXdzTjskQ0MwbE5WYjQwPGRiUlMKejhITHFqVl9TYChIP0ZPIUU+SntiPHNMbSgmbHs8
MD9HODRiUXBTKXpqOXtVNW48N2VDS3A/cjAjRk8raHZiJllhCnpybTdrMDYoWipWeXo9TEk5M2Q5
fT1MRnFyaChLcUElTjRCaGkyemxjTGAwPnctNlNGN084OSU9eVZMOTNrQyV2bgp6PjcwPzBVZ3U2
Qk5QS310e3sqKS0lViVWcy1NJExiPj5PJCtWS31KWVhDZmc2JCNvKEpIeGt0eUBvMSpMMWIxODEK
emVOQWd7RF8rfnQxI0tONk5NNm5kMGJNUTBLeU9EWCFtbElEdnE+V3pyTjZrPzcjQUc9UlRoYVEt
bjBaVW5Nb2pTCnp2Y089ZmFBV2RHTCRyIXxNUmFtVVl9VEtGOUBZQSlQYV84fFNrQUpfKSsrU0JY
b2ZGaVJJelVJVXFEaXpOQFlYKAp6eFNLNXFSbFlWWjJEOzl0ZFRZMWM7SGVBQVJnUmExJVV3aURB
Rk0/UlJPfXVgeGREQT83WFBqN14yYWBiRWBxa2EKenNPYDc3LXJ8RWw2QTl5QVliTElTOV5TSUxS
eGJedTMrPlEmIzgpTCROYSZtZnswTDRHPTVWYEJPWW1GKVp8Qn5xCnpuKzt0UXdDTlhFMUQrfTBe
JiQ2ajMrX3YjQ0pMJm9TMEI1KzZNOSp8c1QkSWM9R2NHVmMpMyU1Smh+eGV2YnhUQAp6RVFIfGFm
dDhKaGdjWUU0LWU8R2laJUpOK09+UjFUMmhFYE9eRyFJT1kma2dsdSN8TGU/YGIwPHhwZXUkQTVy
eEYKeiRjVXh2K3dUY25jUlJySEhHOXhtdUtSOVBieH1SVEIkTk1wZy1EbFVtVkJSNm9XbilZMlRs
K2p3JipDJS1sKWNtCno4MXlkVVk7I3Bhc0l9QXk9ZTwjPSpySDVFKUVhe1JhSkR7eShlKjRvTnF9
VEt4Z1V7QF47OGxmWih7Yl9xPStWdwp6aEk3emFLd1BtTWhLeVJDPkE4VHArU3M0V3dCX3BJdT0m
dTQqfDJmQDlFY3VhVk5yTzUkLVA9Kmk2I0khZXNRYyQKenY3Tk4pY3F+YUQ5UT9pSV94KVphUl4h
RGxENVIoOU1JMWdGeCtCa1RnOFE8TnQ/fkVvX2heJigqUVh5PUpLYHY3Cno9eWF3JmV0b3BRYUJ0
c0EtNig5KkRQfGs/eHVUIztYbV5+XnJFOzVac3VNd201PHdkQGYyOzdOJUczYFFeZFJFUQp6Jn4m
ZC1IcldBd0lWJWp1dmp7eWBOb24pYHdsXnBlQzwpUm9HP1VJZiU3dUUqNn1zV3MqPzthQFoxOX17
TkskI2MKejBlOD8lKUYhK0tvTW9jUz1TVnE/SGZxMGA1cUthSGxQYDlKa2Jkaj5aYWp6VCVLOyZs
aU43VCFzP3otPGo9UlhRCno0IzFTbSEtdnoxVklnRWN4VHgrN1RLI1Q9Y1h6SWc4O0Y/fDlMejZq
TzB2ITc0Rk5rUFEjJUNfek47anJmaTBWTAp6ZExuTj1hSDZhTz9uNSpxXjk4cG5zLUZEIUF7Uzwj
VypZdjV7aXh+ayNqcDc9OVZ5QjVxY0Q3PDw3OHQ9dXNRUmQKemElYUBmMV9reElYUktEb0BvWjR5
Q1dhWXF5X1VBKSp0SW0wWH4hVn0+bzZmPipQbzktc08lYmsqa1ZsSkYhdXAzCnorTEE/QEJ0OE1A
NCtiUGdISSM5ZCh4QzYmen5GNUhWUG9AYWBjejxRMWZgdUd1Y0omUk8yeUVLUGJ2Q2V5I1ByKwp6
eTNIeiFMXjJPPDsjUzktYXtaRFQ5VmN2Rlk/emRwPnxIfnJsfWYwPj5jX3JHWntTXkcrcVA+ZUdi
d0JLPWpNN2QKenJMdXtuPGw3P0BEdW1FRXVvO2BqUWl5ZT5YSHY5QWBLSmpMR19LP3ZES04+PW0w
OHFOfEk0cSZRTX4jTD9tJGttCnpfK3pzM2spZGtLeE9+RUBTP0FOc0xTazA/MzdKMExySTgmTll5
RSt6TFVGbHRrWUAhYTtqRGp4MFlUdyVDMX1Wagp6c2VvdWYkWSExVG9BYDt2QGpTT002T3FzcFpY
ckhKO0FXflEmI0huVWY4MVVFZHNiZE5LQzElWGEkUVMmcElTIWQKem81UHw0Zk43LU5iVH1PPkFA
WUZSK1EtVjVTdyZTc3NMVUVXITh5OVhGVl9FJTxEMW5PUDU1cGshejNwYmAmLVZfCnpsbWFYTyM7
TW9CRkJHTl9LOWUoUXcteEhzV0R+O1RBbjVXYDhhLXp+eXVWQ1cydmpgOyZXOy09NzJ3WHpLNzs0
Xgp6VlZuVzlSQnRaJFMySj4+UGtvNyMjZF82cjQ5bEB1MzIybklfXz08TVlGPGZVQk5eUWNrYlRB
JjxzTjEyIWh5UkIKemo2OXNAQ0lxVG5AdFhtd1dGPWY2UDA2NyZZWUxSQ2huJHNSP182TShIMnVs
SyVZb3BDSGYxc1M1U3VaQClIUGRBCnp5JDw/KCszUUZLVEM+Pn1IPUBJclhlfUNzWkIlSl87YEBK
cHtVSjVMc1ktRHhVT2R6PypCRmg9XyU0QzloQ3NrdQp6cVgmR1JydUtIKT1lR1R1b0gtbEtTZWpk
K0Q+eStVQy1kUDJldT1UZEhzQTxDO0NQcTUyQlhFdj8qWXc+KTlmUH4Kems2WEpEPCErb3BUQENN
OHRRPEc7Q15za2NgUHUwJXM9JU5NRT5TKy0/JGxnODEpfFctUyhVbmN7NGI8OWgmX3JQCnozbzV5
bkxBPEw4SU4rYUZaKClWUHNqTWJGY1NEdU1Mfn5Rb2tyWVpeaUY9O2l8MUg9IUxySUpgbVR1V0Jo
Tk5KKgp6VjgjfWtoeDY4ZSYxTUhjM0QoU2JzMW5idDtOTk13aHtic3klb200VDlWd3VNT29jJklC
ZEpSPFQtZnd4cnhPc1QKel56TU82MzZ7UTMzNkBMKWNVRFVybUdeaUYpJipIOGszJUtvKShVcHYo
SEMzYHt7KFVEYFIhVz5mPkwrXjRBU3pYCno+dmhqNih2PnlyKi1SK04hUW5zV1U8e1JJVWJfelgm
N3Z2WkdQNEk4JT99SnQrYGtGSURJVU1rbkFCYnB2RnExbwp6UyFrPVhLIX1MOXZJU0E0eCp1e2po
VFVjMGNLem99S2JkNzBvXlBqPVZMQSVJVmRGTXxQRWJtNGtMeHE0c1VXPUEKelA7fT8lPzdmUyYh
Qm9EYi0/RGBTR3NZU20tK2FxbzFFWFJqP1MkNj5LZSs4Qj5AWF5Mc3ViPlgxZjxVa3dmM1MqCnpF
TTF7dkopRl4hSnw9QUZOYWNxUTtEfiUkPFBEMkBUbXYmRGpOTjRJd2VCJVlYQXtyJUQ5QlU1REgk
R3QwdzU/Qgp6cX4tPWtZfVd2M3REVz5mVCFvbUZtUjE0ez8tYVR4ZWlQNUp0QUU9KnlPYiFET2ZM
ayh3JlUmdFFofCtjTGEtWmEKek8/dykmQSl5Wk9sTzElLUZhJnU/I3JSKSotPndxe1lkU0o1QE1E
Vm9OTTdFdTN3YVdFYlZWQWM0OVZ7K0l9UHY7CnokWjhydz18aEViYTR3VTx6ZlBXIWk3bEo9KTlf
fjljTCQ/aVkwYk0zc2NvSyk/cnBIK1F+bnxYMmw0ZExjIXZQWgp6NShkMmhlMnUxKm9mWTkwdnp+
LV9SU0FxTTJMN1hBK3JJZzBQVlkwbkFXQ0VkZGkyfDkxfGdAI2hXPipNVHR1Xl4KelZuPDdNIX1l
Zj1DNFdEYy1OaCsyN2clNHMlU15HQUM0RDl3YGBPI2BpKiZMdUd2Z2E/YmJDSyZQKkhBfXZ+TXA7
CnpDd2tDPjF7N1FNakBEfXwoeklQTSEyNSlCQSVyYz4+USRXRVVxNT9gMnYqKnw4QCljdTVePzdH
TGR3dHZGezZFQQp6MEJkc1VtQWdLaVNOXjgjZSU+fHhSSCZoTXZoUmE+KzBFTWwhPCFNOUNFPzc0
Iy1zRW9ROU1tUzlzSEIqcy1afTwKenxNTEtoYm4tWCE+dn49X3F1RlpNdnY7ZEpkVk1yKU0pc18o
cS1jSjAxPHpwS1IlaWRsZDZic3V0c1kyclFofjVnCnoqV0gzbDJHWEFvbWl3MVYobnZuYnN1VkUm
KUU/aTdDb2MzPSNzPzJ3d15MbzZyfjJVOVQjb1IyYzM/NkJuSFQ+ZAp6PTdBVVdRfSROYHQxMSYp
Pm52TCN5IXs7VHZeS0QhVD1odU4+MjJSRyhrPH1TOTZ5XzRzWDc0K245QW5lPFFISXQKemAjNk9M
WSp2e2l3SUpuNTFeNWIlPG04ZXBKQUVLNVBRTzQmcDFOR0UmRlN9amNHUmRwI1NZPl5jcDh6XlZ+
UHE+Cnp2YWkoQWQzLUI+PC1GJHEhWV94dD1WKWRyeH1fYkdvI0FePlZoREpgbis7NVZmWTE4MzlA
QWp5NEg7MntvdWFaegp6K0UxVU1CcHxpQ1dPKHgldzlJX3UtNzRrLVBzOFRAIzlMfG0tNjl4SlFA
RXx9MXdhaiZhVipEPTdAfGNIQlBYaH0KejVMS1c3ISVmI0Mwd05idHFIMjlwYzJXRFFZUis+NWZo
c1N+O0wycCZkZFpgYjE4a2gwPjJARyYjeXBeMmRFeXB8CnpKU2pEI2t4b2NRZjl+bUhOSmgrKDJ+
KHEkc24yOWtKbEEqMmFycyNpZmFHYXRRNDdEQGE8cyFNT3JjNGhoVjErZAp6I2dgc2tmWng0NWxX
Zkw9VXxLT0I7Q3J2SzElU0ErIyZRJXl7QU5IU3lHO35yRkFqVURxUjM7NHJ8SkwqIzxtfmQKekhp
OGtUSnAjMnFsND9xPTJfWVVnNnN6OSlWQ01kRVQyK3lWSXg0aW8kYTgmRVA9YDlnUTMrU3U2bVF4
RF5GbmBKCnp2cGtUJFpEWHl0SH1oVnxLe3JOOGB9UVVoOyE+WGp0bVplUHt1THZZVkFwLTk/azhI
dllhcWB7cXE+Qno5ZT98WAp6Ui1aMzJNbjVEKiRKZSM5MDtaeD0wKEMxXjxpaHlTbzFmNDNIOUNI
dGBxaXk0b3N4ND5rXm51VUstWVEpdnw8IWYKeko5Y2JQaiErVWAhdHdkbEZVVzI/fEFRcW1nKn4q
Qmc4bXo3I2wtbSFtODleNj0hIXVJPzdeaExCeUhedkpIPi1DCnpFK1dXVjJfcUA5TkhYK0BOQ3x2
XikwUHhXME5BY1czSEQpfVl1NnB2VyRUZTBeY2MkeWsrSXgpaWQoT1ZkbkFwVQp6UkBPdzhXKnpZ
YCF8WEplXnh6QG4xN31EZz9ic2I3Y1NtUzZkRmBxYUYrbExxTEskMG9SVjxDQ2M4SyUya3t4eFIK
ek0zQig8dlU9dDYwMWBQQSUzKS1SaiE8aS1edz0oYTJCKmVHYD1BXktQeyQ2cCowWTxMVWQ3JFFQ
NXNFPjZqQTZDCnpveER2VFc3KCk2cFE9YTlPUVFaQEU/QzlqJX1XQSVfSiFiM2M5P2xRITRjKlhE
Y0o5eHU3eTcxcmQ4MDRqJmlLeQp6bSlfM1BkXlJXYys+Qi1DcGZ7fWpELXx1aGklSiM3OzZIUjko
VnlYNlQtakw7eGBSRVU3eUJeKXVwWEk9Vz5PPXAKemRLWmBjRTJYV0hLXlZzZjBkbG42di1vOT5p
fl5yKVphNVNmbUgze2l5dzk5NTI2LUwqPktWNmp7azdhMU82JX02CnpvLXBMPGE3Q0YtPmF3I1dV
fT5DKSFYXlc/aXpWSUhCZTttSEtkaWNEbilLP3NXYjNlXjcpYkBDPlhHJmFhTTx2TAp6XyR2PDkk
TWZfWTk+RDxzI2FpT3VkMm5pdUMlcTlqKitGOEdac3xtR158JndAaXZZP2M8YlFeMm5oaGlJWDVY
QnoKejcpPEY3a2tXbzh1Qyg/bihjYzNuXlFqbiVHWDFRNytoS0dvWD5HandUYzxfRkJ3RUN4Xmg8
YklQNyF+K25JN2JJCnojan5CdiYoaz5rU19OQVdmZE5STT5HR05AYkY1QkFreHprckFuMVpFPEtN
NUNLJlZGfHdtNHZjNitAQmRkb1p0bwp6aVhoPy05fDdUd3cleU9AOEIwdCp2TXckfnhPaks2TF5j
PWN7M3UwTWFoeVg8V2RUb08mZUh7ZSl4LXVZTFhxSjEKeihGfj5oKFI1S2FpV2g/WF85MUdtKFA5
VHQ0T2o3IWd6c2JeNCZAWG9BNm5IO1heWk9FRkdTOCtiI0c+cUR3P0leCnp3JDg7fEA+aWtmPHcw
QGB7XnhzU0xRanN0RyhjT2YhMShNZFZ9ZTBLZFNgNWpFPHt4diFHK28/Vy1FUzY0MUteZQp6SXoj
YV8wP3N4TVMwUVZtPHRLdWo3JnMyYkFoalEkR0smUVZDSCFaJm1gMjlCTEF1U1Q0RSRmKGtITkZm
e1FYJEwKenhXOSNsVyptY31mR05LaTVQKWQ1YWAwMmpefEU0JHBHZzY8SGdNMmMkJSQ0fil6YSVm
TkRmQUhUQH1kO0dZJXgqCnpxIXp3JW5Yez0qP0lLOEcoMVZoQiNPJV8wR1g8TlMmNS15fmNWUzNj
RE9kdCFJVGA9Kj97QTtldX0oQi1LRkNTMgp6TWQrWWImU0ZATnlKZW0+a2VfR3I+YmcreHMmPT5i
N0B3QnVhdyo1R1ZFdD90NzxvXlk5NT5MfVUyZ0dUPWVEcVUKenZ6THNiMCZBa0t6MExwKHgmaVJX
NFBPbF9kcVpUfWg4K19CITleMnZAc2YpeTN0VFJMWEY7aH5RWHt5cE4wMHBWCnpYdyVqQTY+c18k
NW51KWAoK2d+fEF5d1FGbTRzQFdoamxsQWo/fnFCZnFLRj1TN0gzZyU4VnNIeHp+MSRgcX4pPgp6
P2hvfkQhYDF9az82ZzdgU3lBTnVsbnlkQFpOQDVYXks8TFIwS0BqSG83cEVFVGxZO1FKeyZmNDBJ
WEkwKXs9N2sKejMhLTx0SztkVypjUUhOWDZZI24/WCoreUBUYDwtWEVuQi0lOWckeGBYKnh7K29S
cUYrcHltbXk0ZFokNmN2Vz92CnpmUWp+ekJhbTFMbFVhIXpzTTZTZDdacDQ3WSRyTEpoPnFMUysk
QXZVI0JEJGk+cTNwTShwfi1CYmZmSlg/cjUybAp6VDZLNTIjLXM+Q0t6ZFU9eikmbD1wdGghdGtu
dXJrbXtCSGc5MHA8NXV8NTw9QDtkKkEhS2A4UldpSFQhdklKdi0KelBVUVhKMThBcHp2bil6S2BD
QGxHTnsja2ZRKnlSSWNLUkRQK1koWWlzVztzRE18YyRKLX1vQ0ZQaDxnaUJ0MGc0CnpGeH0wZWQ5
WUJLSWVrKkkoQzI0RHg4SH1qUlF7az0hZnJ8alBaMyFkO2hqTjVudzJDK1dkVzJsdnRSe2Y7R143
egp6JmF6NTRLfndlUFhaKjtyNyROYjZpTUV0JT4zQGY7eUxLZT8hUWFodVlOUERkX2Nzen1yNGN6
MWdXajhWPzNucTwKemlLbUFtS3gwd2AyMjRNayMjVFAkNHJqejdqNzw2dnJyansrdkJ6NFEyVDN9
VlNyfUBldnByO0ZCUmZmVGNnVHBlCnowTF9yaj1vSmdWaGA/Oz4zVjNScEJZdTV8JnI9NG0/P2df
aTB5dWk2Vnl3UWRaeXM2dTFwaHN7WGImQVEhdm1NSwp6TCglQmBZeWIzY09DM2wtI2pkcDh7cXZO
dS1FWkJrRGptZVMqTD9uZkpaOD10UypBQko/RVNmNE9TJGh8PU5GeCsKekghZWN4RCVhSEw4UWUt
RFc0OV9SV1pHT1J7Ry0zZTA1UihYeyFEaThJe1pGSyVvTkQ9PVQ0fDJMKnxLR0V0fk1PCnpPY1Yp
Iyk2TUVweDYkYnJacHFFX05JJUMmWF4lQndvJCRnKVNXMGU9Mm0xQU1aVjJzeGpNMDIhOGJjd3Fy
ej19Vwp6P0pSQ0c3Pl9OU2MydDZAaStwKjY0Vlk2WGdFWjJVaFpvKzNMayE8N05wPn49byNBcEJB
JntBS1ZUekhOZUxKfDwKei07TGYoI3drM0RvOTJ6ZT1EOVdOKyN6dUw7VEhtTnAlWk07KH42ViZs
d21iKFdnaTNYZHZoKjkxK29CfU01Zzc8CnpOOV9Rbz9rd24/aHkmJXVYdF49WEd9KVczTF9RNyYj
ND5+WEZeSWxSMjxRNm1wSGs4TzF3Vm5mZHNPaCV3dDgyfQp6RXFZS3s5cVQwaTw3JitUX0FqY1VD
aCpkeTlTejIhJV55YGVpeTlPYktxST1zakVhKjxeSDJhQUYtLUo4I01DJEcKeiZnciZ2VjNebCo2
PGsqSHR7OSRxS3s1OytIMlBwTj9USm55e3VTZDM+Qy1ZO0tVIU1UR3NRdFRDMjx5fURiK2goCno3
cU4tTHlkSVUhODZaNmFUZWkmI3k2PzVySGpiOCMhQUNxfTMjM3tTdzhEcClBQmZBPGgqNlVuVUQ1
QSM/aWt0dwp6VG9TbkB4JVNfanhsdD0wdF8hI01FcFF+OUszKGF1I3hQUURGMzU7SDhDKWNLcTtW
PUNfbGo+amhrbE92UUBoV2EKellaezEyPSpkPTB3MURESSVqdiskJGMqYzUoSEtKNzdQa3w3JjdL
cVN3e1JfQVkjbCh0VE1UUXU0dU9ZP0xuI2E7CnplMEQ3dTc/c1A1c3YqZjVvNWxabl9tfExCdDI0
MWNMZFF7T2l0JTJiWX1YZSFpUSpXK3lsUyM4ciZoRjxDO0h6Nwp6SCsxKHUtbVRXfW5MaWZfNklh
ZmJjNlY7OHBNUjFiaVJAPl5hUCMtd0dmNFMqbyNZZ0tNWVNLREFKblFSdG9venIKemohYSROQXk4
dkEodXBAWHtmSSNAJH5PUDM4PnYmQHdWdCQocllLT249fXdjSTdJQmojKnY1Yjc9UGh8WDt9NkhO
Cno0MVdPLT1vTWlNdDUhU2ZqLUNeYWNBRjRZYysrVyhNVG5wRXZUd2BqbWNKSEt3PCg7TnpPczlm
WUoqO2JZJURlMAp6Yj9UZXFlQ242TG89Q2pKJH4pfX5Zaj1obnE9bWpIZURHb2FXLXI7e2g/fFB3
aXIkNW5uNG9LR1QjUUFDWmVfJSYKekN8Z3dmcWhjLU8xeExFUCkpWCR5WlpaUVU0eGkpPjJGNyU/
Rj0hPnNZc3lKXyt0bWhALVcyTG5CViRyJkxfKFM7Cno8aiZCWnskM0gqUVZ3ZippOEh3SFBCOSpE
K2IrTzNwOSRzNil+IUomKy0kczdsVFE5O0tYIVlebSQtMVpkeSMxcQp6VDA/Sl5NMiROWG1UTmsr
bFQ1Vy0tQH41fTQyJj9IcHxFR2chZHcqUXUrTj47anFDYnAkJkh9UWVAKUxCTHlPWHQKek14TUJM
Y0I4aEw8ajYyN09CYmxVb0hGdDlDS1EobDRmTnVZTnZufUlEaURaMnVEK2N7SV8lYXs8KjIrYExh
SnR1Cnp4LTxMPEh3M29edmg+cHFSTHdHYDgye3FkUTlKSEQ+fVBsWHtTJVh8OERzZFBpUTl+KF9y
djs7SD5WSFdCOT19bAp6Q2Y9bzxeLW5DWnVHcS1CUCk1aCt3fX00Uyl6bipUQX1fQWRJKXFOUVJ8
S1Febmp8ZUZnYGY/MlEzVCVncDwzQ2oKel9fT143S1EkfVlwTyVZKnskMCg8UE9ieWg0OzFrSyNr
Tj9ieXxMWVp0XyYyKndWMFdhQjVKXjRIQ284dkxkQClzCno3NDI/UWEmUGdqRT9ZaFZTM09zODU8
eXNBKUY9KFMoYjQ2VT55KF5pe09KNSt2SkgtSmRuM09PNjliVlYxaSZHYgp6QU0jZzFVcC10JUxE
Iyk5akNBbWFeJTJBVStrXkA5emV3YWhoUkhsOFQ5O2g0U1dad29xdGxza2RnJD9AYGIhdTIKelQw
WGNNdEApej1seSM2YHtBTHt4QFlDTj94OHdpfWp9I2I9bHo+KlRWKVp6XnNpU2ZFLVAjN25SQEhj
QkxKfUFPCnpJP2IxZip7MkN7P1FnaD13ZjN3XjxadUs8ZGslPjBzKHt0SkAlYHZhR2BsfmlxflVS
WVlfRDxgVihFcURzfG9MWgp6aCs2UyE9OWlSOFBkVTgrSDlzUDZWKmYhbHJyITtGPEc1NVhvWSE8
dXNvLUFwYy1Wd0c7ajl1PUJYWGlkMzsmJX0KeiZibjI1NH17c0ZhPSg5bGBZdWtzTkh9bmFuflVl
O2ArfmQ5Y1JgIS1VQzc+fGhUN2x6NXJNcSk0dFBhQDJ4ViEhCnpKbmQhT21XbFl+PilZKUJBRjQx
Vk5nTUV8PGB2dmduYmRXSWoqPHg9MiNafWpuUy1KJmg0MT99VyFJISMhcTxBVQp6UDxib3VsKGFx
YkFueXMwYyZKZ0R7b1ZGa2MmSTY/QGxVPlooIWBUa1NmbHtCdWJiTkE9eDV1ZkhzMSZMRV5Cd3MK
ekc8SDFQcU9mUWNgb04oMFYoSmU+WmFEd3BhKVoxbk1NQUdXcWFCbFIkPTIkaCF4eFdNSExhOTE0
TGcmJG5yTWwlCnp1RTtNLVlMVTN7VW95bThgdnQ7c1JQaDNycXV4Mk01TTkjckxlPW5VT05JTlBr
JXkqTHtaKndAJSRsUElHbTkmUgp6e1Y4T3BkfE1qY05EMDA2JFpCI0JPIWJrOFRCd0ZzcjQya1lM
RXNrKTMhSTZgJHBmcnw+aXkpaShIVGA7OTBjbnsKekJiTXYmOS1FXz5hKzZudTthXkpLXn40ank8
OD5VYXR3JmJnTWg5P3spak14ZEl5V2cjTHo7dk5ZcTRHITxTZFlCCnpDZ310Z1RVSS1hPCMyKkBl
KHtEPW04eFQtemZDVldJfDQ7KE84VHxAenY8UVJgVGNJQFdAZGZXTSFhMTBVbzNRTgp6TUU9MGA7
bz1ueEd4eDNTaUxEd2UyZ3g4TzVBcSl2YSRBIXJifEw4QDJyZm8kPiZUZjgjSC00XjR5PEUxbVNK
OGkKek01ITBlIXNFfUxPTHZFRUpKVnYyKGdlKXUhPCMkM3opbT0yUEtwZn16a2I/cTdkMUwoTkoq
PX1MezkyZW92UUd0CnpucjdUfU1KOStxbmFhdksrb2Z9ZzY2OU5tS3hBZ3U3YXdPKVJicVlUcz9Z
WUUzKj1WRGkjfVQzVTd+bWEjbDNRRwp6Oz41U04jOUVuYjxpbVlDMHRGM34lbFB8QGx2WTYzXyFD
cEpKeEo4IWJKY2dLUDMwUn11JHdAO0hFPFQ/cXEqV3cKeiZpWmgqKThuKml4U0VgVD9AO15xWE5D
QzBNO19hNzZLclo2aXlDfjdabE5iJUJSIyF0ckYyWiNxUzl0N1JBfHNOCno0XyNlT0U+Tl5SK3NT
b2k5NyVwZFdIS0lWYnN9dyVUWH5SdVlqdCkqQ01DSz5fSCg7NDQ/ZD5TSntWO29ge1EyNAp6I2I3
N1ZgVVlFTUFQSUpIPUg4JipfIWJCY2Y5dy1eQF5tR2Z7MSp3dld8c05RdElXa2g2SC0mcWd6UmE8
ckNoQH0Kej9DTXZRPjMpNXFONF5qOUpFQ3goOHNONSFaVD0pQGh2YzIpalotNFJvOVJpeWB4JS1p
dnY2RnRVIXtKJSRqKXBvCnpzbjJ8MUg1ekY3UFI9fWBtQ0RyO2d3b0dKT3sydD9FTUJ+OEE9eygw
Z3NDPn09XjhOVXhAeCpVLVo4S3lzenEkMwp6WWxPZjZ1WitoU3FxSmY/aVhOUzRgNS1KOXN1IXhy
WVFXVTBAfXRofVZeO2N3I2gxb0olI1lZbjhVKDVHXjEpSmcKeiU7UjtNQHJJdXxNMiRIVEd7MEpY
czx5RipYMGI0TWl7WjJCY2VtVW1DfDBpbFU5KXc7cShHZm8kfXg/NCpYOHNTCnpyMiZiP3l4LTxU
VXV1JUY9Km9GSEY3KkNkZkJkd0ZeVHBAKXplJnFFODFpYiZUQ3A7WDF9O2ZeTD1zZ2sme1VlQQp6
aVg1Tyk5enZHQUVRa3Zpe2ZGfUJUKml9Qk5eJn5DK0pzalBeTkwjMk5TPztPdGZFczMrODlqeXBJ
PX0/KnRaRmIKektDVClyc1Qhe2lLWDt9PVpsUTdnNEQ1dXg/cUlkdmRDPjk9ZEsxPmd1SWYkZjRu
ZylQXmktbEZHKmBNdVE9eH1rCnowV3Q5REZeYTtCO3E1ZU1TbFV1dDxyWiolSVFBI2JRSW5SM2g8
QGd7X05ZYGVIN2FEckpWK1Emc0tpSjd1Mlo8Wgp6MWBPTD9MYEUydGgjT3FjTm13fFQkJSUrKm0t
V1czV28zMFNTeyVHdTsqVWleIWBCOURNR2h9bil2RSg8Xyk9dSoKemxzfGpOWnBgMWlERUpiSjZm
Z0BwJV9MQHMmTyZYdVU5cWRaTWhXSDtgSWtxRjMmY1NGZjFgSXxMdkIobHV4YHFsCnp3T2sqRmde
SztEdUxQRmtWfEd5aFFhRGtaajV3NTVvS1UmIXdAWUp2YW05QlV5Wj0zZ2NFYFE0IUBOPyEtTF52
Iwp6OzJLan4qU3tTdUg7N0RwfEl2WnF4ME93eWx6OUBoIypiaHdrNCR0aWBvMDNucD40X2A9d35x
SENwOEEmMnRCZlIKenlmVFp+PW5tPEtVKD48VkNGbkpSe011cDdiP3MzJDE9SipCNzgheTZhcyMx
PkFxMHxYTiYxZzs2d0Q3ZEY0a1p1CnpsQUFrJDJuWUNuIXt5LUdzUExKT3AqdntkM0R4ckJXKSpA
bnJKOy0jMn5TPWxMMFhYJkdnKWI4V31hMEp5TlkhZwp6ZzJ4dWJ3S3lVQzEtNiFkKl42MVpKYUg9
QVdzZXJnMDB3cl8kPkRzfTd6aUp5QEAxQ21pQVJKJms3bGZCTV9NQXsKejE/P3hlP0xVdmE4dztP
fWwhMXdjYntlUzhuSiZKJWNaQUMlQng3ODx6eF4pPHR3ezQ/SXQzR2F4aVVpelJjJS1LCnomUC1o
fF9QeVhuMWdJJTVxbV8wRmVZMXh1cWIlfndxRyNIeFh+fTJeN2peYHRne3olSTE/P19CRDw7T0xV
e1BoUgp6dWhmKH55QDhxUmBod2tDXjgxZkUzRUA0fHt8Mi0/NkNrNVVKanY3NSM9P0RBR29VNn51
OU5iJlJudyFMNXVCfSkKemMkKjhNUnV2UEo9N24oe1BoUkVrcjFGPCRFeERlMWZsITstVHB4ZiMq
dVlgdFRNVTRuamsyWHYkKCpIKzN7bHdICnolISo+diE9YTF1ISolaCVwSTQqZEcoaDQoJGhvVWYo
Q3NfN0xHS0Fzcks8fXY7JjNUfHE0JTVOVWQ9SyNtZD94NAp6aGNETyhFblU0QVlxQEhlemN4QFhe
MFopVkp2eSVgQ09vRV9GVlRkYmg7cXNaZUp2KWpIJEU9KkxkXmpDSF5icjUKejdCeSh7az1kOSVZ
TD9jRitMNXBIUVFANTh2b35rIUdOM1RHVHpiQCZxaT05VzwrK1hTVi1OOFMma04rK0FIZ0k+CnpV
Uz1fSlJVJFg4Njk8X0pzQTg2aWtOdTItTj91SUgpbG4/ZT05dV9xLU4xbmR1WDdyWUxeNDBHVnVv
MjZiMG4qKAp6PGlLdTxHcXszI0h6fVckT00+RWo/fHhoRDFDcjNoZ3R2UjNJWFEjMSRSUkhrZzd0
M15oMHNrRzhYTkBmYDY+cCYKemNTdE1JTlpKT0VffWB6bUUmVEcmOTw1UntRYkchbihWVTBXSW5+
TEZkSzZ6ajJjKWdKST89d3o+d2FCenpmJDNlCnpJYURjVUxAcSFmKVBAIz5PaVpZaVErfl5qdjhA
WV5wQyopUiFeODxTYzgjSUhhQHcpIT53c2R0eXpYUGdoJHF4cwp6XmR4WDltPn1VTjRNckJLMn09
d1ctRlBJcFo0SVdlNihVKkVuWkd+VW5wLWkwcXd5cjd0NnE/bCYxTGlKMylxIS0KejYwPT5DNTAw
JkslMlIjbG5ZcWtwRUw9bUM2RSojUT9RZXVWXk1HTXYlRUhXakUpbDJaOG1ROyNpUjRTYV5JbV8t
CnpESThwITY0WnsyUnZ0NShsM3o3bTkkemIzIT5gWER2Snp4cDhBTEdgYFA0YERzWlVnbFVnbWN+
d3RLI3NGajFUUQp6d3dlLTJSZnQrNTVTRXdQcFhRZXdBY2smYTdnKkQ1NjtfQjA9Tmp8VEg1cDNC
blFKbmVXOyU/YWRkam42QDVgPGIKemt8aXw7JDFBYjRCJEpiZT4pcjkodkA4fnA0Uz1+NHBrTWJA
WmsmalJRfjJ9RTc9OXRGXjhVUGV0TSpxTXVmWj5rCnpeNDh9VGchKUF6X051ODllPmpJe0VWKnl0
aVR5a2pHY2drc3JBVFo0VippI3UlPD1FX3c1ZWZkVEIhXiNWJiReNwp6Vk9tYTsoeldUOWh1Iyl8
akBqbWZwRENFXmJWQlcxSDNPe0ApcHF0amBGdz5sMjt1N0tqd0UyUT1QYktJT3NzX2MKekN2QXkx
SktaaFBVMTMmQEE7WlolIXsxMzdeXjMteEUqbGtEJUFRUkFzMiowTUM+Z1hmPk8oNU9MKDRfVDU8
RX51CnpIPncxcXYyJWImZ0Y1KERmcHVYK1NDQi1GOTFOMnVKUGlqZVppQ1YwJnkxTkF6TnMqJkIk
eVhvVEh6Q3wzK2Q9UAp6IVRCdTdmWiVXTUtUfVAwSXdFfnRRYDlxWmZnKD4yZGEyO3w+NiFHQ2cp
aWM1ayoqUio5RXNOWDhlPzk3RVVCUHIKendTd3dvKmY2c2dAOXJZJTlefF5jYGwtLVQ7UFRZejJz
cFlGKXl7LSUkQHxnQyQjNiN5UUdRdTdtVTliVlFnKE9gCnpick1OUjU/YCo8KiRpKkhYYmwhd209
azc2MT0yRm8lQWpmbWZjQGlnXipSKjdpRXFnNFYzfWwhYV9PYEchNk4mUgp6NT8jT0RjNTg0ajA0
UU9iSjhpNjAtbl5nVHo7RGYrS0VvQGExVEN6THZFdHNrYlRFMHk4MFJjSXQyeU48aXdmNkwKemp0
SXdCNk0zb15YPndmaFZAQ35ocmFIZUdxYSh9SFd0R142VjJ9eko2KHA3TSl7RVVzeUBVJH5mSEN8
MnRqXjhlCnp7TnlMVz8pclVsSE9BQyRTOXhAdnstOG5oZ0Z5MHZFaWxiclRpMkNyYzI+O1VtX0FW
fGl7ZWN6cnpLUi1nRmV3NQp6KHc+N2ZMalhvYF9yWEpiZml9dERnNmsmNUUrJmxGYi1sTXEmUTcy
O3VjciFHZzR2XmNfNkw8Nmh3VDM9JnBicjYKenlhcWhZcytxVlNxX0E7aERRTXxARTUxXkttYmpQ
cFBeUz9MdkF2KUQ3K1VEa1g4TXc4MyZCZDExO21JLVZ5RkVMCnp7KkhFeistdWcwVUh+b1UzPHdY
MEh9NEtjSylYUE97Y01APUJ0YkA1PVVsbjdgPSRLNzwwblZCYD9kbG8mSVdUYwp6aXw0enZsJHlq
e0oleFZUYHxCR2Q1fTElSk5xdHQ1KXhOKEAqeXlOVm1+PWZGMVNONFdHRi1AT0FXfWlWKEZoYzsK
elJuYHY9MWR5Q29HeU1pRTZNYiZLRWxMZHA5bUtCbEhUYlBMcWhJQGM8KVc3NlBxYVImcklYK3NP
ajFOVlJxNng3CnojcUxpQ3ZBM0tpVCt9eC0mQl52fT5jV1pVRUpjUWcrY3xKKGJGe3RJVWVKZDFv
YVRsUVBiN3lReD0jd2R6aG53SAp6Y04pbVArSm05UiRUaUFMYiQpWVk2az9aflp3dGtyQDgyKk5r
JDc/IWwkcU4wWitTWUc9alZTayVwVSttYk0oVS0KemJlYjkoVCRoaCp7OGdFKGdeJlgld0JhUmo0
WGhSX2dsO0JtYSgoYVJ7d31+biVaRC0wKHZwWCZVJm89e0E4d151CnpXalg3aGVqTGVWWmotdEJF
V2Z8MCVQVDdgNkhoOTZMcClKYENROSFjYFBEP3U+TiVLLT5geGhQQnZMe01ZR0pZQwp6UG1kZlgr
SGFPQGE+WGU4QGkodT1hOVBiX0I/OSpYO14rJU9ZI3J9bE0zK0F8UHhBTzBWa2hsJlR+cTdwTDNR
RyYKem1yKHRrN29NQTVANm9yKHl8R2EpV3NhIUF2VHIhb2tnSmZCJT58eEUxenpxSms1QE5OPTxn
Syo7JW8tN2AkP1J9CnokYFc8bmM3d3RLVXNgIUBLdk9GWlNWRCE+TnMqPmtrdTJoQ1lpcXt3dzVY
VFI7USE8cDwra2tJdHcqWnFPX14/aAp6Rzd8eUNGXjZDbHJ3TmtPQ2NFIzVidVE+S0tUS1N3UW9D
WSkqQHk3YkN6YyU1V24jJWwrPDhMY0Faem1OZGNxVkUKekNtOCErY3FnIVFBKFJDbyNXQGxAdERu
OF96ZlY3eWwtKXwmcHhMfTQ8NGQzK2xkQmVtRyVONXNga1dSaW11Xml2CnplLXNVKVM+QTtnRCo5
Mj95blQlfG1NS3Q4VUZCTnczdElHeThaSjIwP2hCPkgqbUt8fFN4WUE3MT8hSVJxWX1MLQp6NjFA
dlkqWHYqUF80alZMVCY4NFk5ZnZjI1ZEZEBjb3ZiPTFDI1VfX25+OWZ5OU4lNytZJUdDP2BKZk9R
RWBWSUUKekk7SDZRWXJ9aTEtT2okbHdxVDwmKEBxRlhvUTwkWGNzTkZJY1pJbWBULS0oMWQqP30j
N0VZbH1FamhPV3gzanVoCnppY1otKkE/V0c9PFQ2JVVMQEVePmVxJDVpRD5eRyN6e1dNMiFuU2h6
b3h9ZnBFbGxmQGhnY3pfKiZXPEBKTSpjagp6WWQ9R2BEX3xzSEFtQXYpZF8jVjlDKjI/YEpaJkl+
QFdENz4reVY0WlIkakZ7MnlfMlRmJlRmK2N1Qkk+YEkkNTUKejszVXhOMVFjajluSW8xekA1Yz00
OGsrcVo/akhNZWIxPWx3d1FjU0V4LVpiPmAkPjM7K19oZFQ4Rm8kenlWOz8tCno8Mj43WSYzOGZm
PD5oN0NLcD9pQCFBQ1NLT3pffVdObDkxfnZgMj5tKzk+az9wO305anB3cW45antGPi0ySlUkTgp6
UVhSMC1AdiF6SEBiPm0qNXNsKj8xMEhmMDZtK09PSzA0QVF0bXhRO2xZa3Q+TEZpKzUySndOKSst
SU1+Z2pwb04Kem47JXduSnw5MTwxMUFHT3ZrTSM1XzQ4XiRfWVFGNmxSLSp5TS19ZF5CXyNeO1Jt
THdIZnpLNTBrZlB0QGVFZCU7Cno9fUU7anFQayR6LXRMYjM0Mk8tVSUjR0s1WFlZJmtMYHstJWpa
VUBoOVUqOVFmWCk3N3U0JmgxRnh2VntBP1VxRgp6cUpSMmQ2aCQhdUZKYnE5VyhEWG4xb1pOcHRa
VS1nbXE3USlpelVnRjhrKEYwaHdJXnRMNyhyOVRuOSRLeT40TVMKeitsN1B2X0NqaEA0cHZ3Nzlt
WFp6VyowITAjUjZ7PWIzXjI5K2dGc3hHNDIhRkVaOz9RSSZjb01wbkBnP3A0TzA3CnpjUl93RV99
XnIxdj0xMUZSRXsxaSg4eUg3YyVNYEB2QS0tMWlDPWs3aXIkPCRMPUU1JCtKYzZ8aFl+ans4ZF5J
Iwp6dlhmY2otblNVVXVpX3N9eXdeTkFJMXhAPmsreUJ3cmlsfnFLSn1KWWBSKUEmPmVyb3NmQjt7
SDNId1VFP05uNFQKendzN2V6Y1FxQyNLUi1Xdmh4c2Y+aT1wJHwyO29lPyt2bk58Jn1OQ3Q/R3pY
LTgyciVyKDJARmpZU1o7dD9xbXBACnpXWVNmKHQoK0J1ZTtmJWFYO0M2enBvWCN2XiQ4WT1JQWla
NFltUyU4aDBjNUx1SUxAMip4dW87ZztebmNVZXU3Ugp6YUYzNEhKPjVYdCorRXMlPmNZYXQqR2h1
UWhRMjFFOCh4NzRnWXNaWD9WSjYoQjs5T304UGhlZG0meH1NRSZIRi0KekNWPmkwTTU0Pj9FPnZx
MGN9WFBnSkZ6UGdja0BqaFB1MnslWnI1MUNaTmRhKlM/KTFJS0JEOEg/aiFvZnQhLV9GCnorNVhw
TTZrUyg/MD4pa2tZaEJPJUx8NXZjaWIwXlUtQmxuaCR1UXd7SkgmSXJfK2h2JiZmakd5YzBLaCY2
ckhSUQp6NGZQYnl0RWdCYHBQWFc3YjtFcEZXbzMrOSlRMWlDZG0pP21yLSFjaDRpSFB+Qz97TVlN
REpfSkFOaDN2NHZLVTAKem1nKyhePShPaEhlNyltaytvREYxWSQlMi1OSUt1WWNaejQhJlMtUjdS
PmNoYz9DZ3h5PSs5PFZxUG9+IWBOcXEtCnpjUEd6UihoSlNaNlpKdHkrKiFyPiYkOFVrMFZnNj17
PHFVJTh5eVl7SVZfKXdFSU1fe3gzV21OOzFIQypGNUVvUwp6R29zM3A2bkliQVIqcVFKKTtBSEJN
U1dtdnpwSX5CZG1ucyU+KUxvN04hd3tIdUZyV19PbWwrT3FPRyFwYWNkI1YKemVjZmVIWkBaaCUt
VDMycSgmIU5PPEEpa1k+Wm91ZWIoVEEwayZ6IyVoLSNXc15+a0lkdVdUbWZiJUM2JExuVFRkCnpg
Z2RzKVZHJDd1e1pAfnFJTWRoZGhLO0EwKVhyTyVBfXpidSgrWnJ4a1J8NG5fKlZlNUA2eTMoMS1P
MmI7fHxeYQp6PiskO2ZNLUcrYFE4cWZ2JCZNVytMazI2SEBGWWt5ajBreXkteFNtPyhrblRaY3Uy
OHtyO0RTWEtGXz4oR1cqb2UKejZJbCpoYXFyJGQ4N0w/V14rN2smPzAkRnI4VDVLcjRjWmc4UkFD
eDxpYjEhcFErfnd3K0Q3cyhFZmF4cjVQUWg9CnplMjMhd0BmZUJSPVdASFY2TE4heWgmV2xMR2d8
SkA7SFE4dSpZNnRMZlFiX3A5X3wwelFyc3hjTXZFandSeVojJgp6WF49PTI4JFElcmt3MjRvO3M3
blB3WThOekwha05+c0tIXmY+IWRGQz9SMXxLeG9rZjYtI0wrZEJDemhoSH1lZFUKekdiTGFRSyMy
QG56LWEkKzBEPkdtSExaRUFsc1Q+VnNXWVhyMz8re2lTd21ZdGwqa207VCopNXZQTF5lZCFEIWh4
Cno0VHcxYig8RXJaVDlLXz50QCFYI0FuWmBNQzshZVM0TXM7NntPZF9KIV5ZaStRSTBQRW4rd1NL
I1d+Yz0lS0M4NQp6bn0lMEZGPjFzT3U4SE9nMns9WnEqTVhPa3RrbDUqcEZaRTYpT0I9cG5CJlZx
bn0zWH1HaDNjcCNieT1oRSROVjkKejM0aTFwKT48am1lO3Y7dChIUTs4PDRRSX1PVUp4cHlQTEQw
YlR+QV9EeT1+K1RgUzBXbyM4SlBaJk9CO1k0cmdvCnotWG53YTBLUTlMK3lhbXxFalp7e29FdjY/
JHhVeTUlMFVWM2cjUTFBPXZubUZjUmx7VSE0SyN3MkdDWSpmUmRiPQpLWT9aV0dAYyNrYmNgQlIk
CgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL2ljb25zL2hpY29s
b3IvNTEyeDUxMi9hcHBzL2VjbGlwc2UucG5nIGIvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzUxMng1
MTIvYXBwcy9lY2xpcHNlLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAw
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
MQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZS5wbmcgYi9hcHAvcmVzL3N0ZWFt
L2VjbGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLjg1ZWFiM2Q3OTMwMGZmZmYxNmVhMTJkMzFlYTgwMWI2
MWJiM2FlNWEKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDEyNTUzCnpjbWVIdGlDNUZ0X1V7Kk0l
ZTUtQipJRnRGKUdKQzYyK0FOY1h8K25qNnc0SG1RNWhuJEJ0UXJkcU5QZiEwdmhIcAp6PjZKbGJr
fS1yU0M8O1A9Q15KYlFHOUB3dzJ2WjBOQDVLOUM+I2c8dmYlbiMxbSRrQUlsSm5oWHBTP2Yodi1k
Z3MKentDJm1GXjY9TStVcWNYZDgxZFYkXzdKb2A2TXwkYXtfeiN+VytTe3I0Wkl6PV5fdlM4ZzU9
dHpGUFlCSj1SVi1lCnpXOHMmc2hDNzclaDJ5U2NkPzZlVDJsRWRKI0NsKTk8cUhlTnB0RzBGNmR+
d0cyPVZKTGohYCpGPE1eRTEyKlRGaAp6UitmMnw1NlE7KU40MnRseyZVbW0kflB7S0ZhOH0tIWZa
VHd6YUVDOypWbmclbVclIVEmWlJmWGhsaWNaenUhX3UKendIXk5iJlApQ20pekJDUHB7dGlnPW81
OyspJV8rYk9VdGIqPnJiOXdfMmE4N3RVSGcpRmN6THstdUI9JVRHYHQ2CnpyVUN1aDkyXn4lV1dX
Y2J2O1ZMR1oocEF7Mzt6NComJGNmaD0qYyh4anpHfXUzOytHJHwzaX5SNDU+ZysyWUdlNgp6dilL
M2JwWmZheDF5NVRvcmFLZEAzR1JlfGZXUUczT1J2QHd7RnpXOTMldnU7amczdE05RkZKUDV9N0FF
VXp+PUoKeilgXkxVU3E2bTVlIVpFRzxOZi0yKm1IV0FUTUw2ZG5mPkdnaGkoMHptKWpDYlA4JF4z
K2FwTDtYQW8hN3RhZGJLCnoqVkFQT15vJC0mdGE7VlQ5ViNkYGRvPEQ3OFdoQXpKc2hsNV5FQjlk
SUN3UEVIYHlYYmRyOD9UanNtPzVPKG0xYgp6bm5ObzRwdmApT183VXV4b09hQ2N4bFY1Q3YqZk54
Si1APWJEdmd1P3JHQj5GcXNIPWE0Y3dNYnBkfnN6PFo0RlkKeiFpZGtNJlVDWnBMVCRSfmN7Qmxx
Vz02O0txWnw7Ty1rTkVOaFl4M3Nud3t3Rm9nT2ZgZSZkPll5XnIoNHBpTTU1Cnp0V2pSPmVeVzdv
d007V2EjVnVxeiNjY3IlMFBeTDJFNDBfWnE4V1Ykaz4pM1BgTTBjKyRQcmlrMz1FMiZtS3gzOwp6
JmVtKTIkM2AxY2MrMGMkPSpkUFdteGkjMjwrMTg+XmRfZG1weSRKQkdGa1UzdGhsbUwyVnc4fTB6
dEtoRXA5XysKemhveGVGVnIxJFdSK3tzdSlRQGkqdXJzdzt7KSNgTFohTyhSOVNPRjx3LT1SLSl9
OS13aCpQN3ZaUVlFa2lNcz9XCno8ezBBeDhGXyhjSClEPXVYSmhCRXV4YHp+aCFDemE9SGA1fnRa
cVpKZHcxIUdAMiU8ZHZJJUJoc1dZdDBOaSUoPgp6elRVdzM4eVBSMVohQDdxTilrTGdNNnp+Q2h3
KWBgVWl5S0UjQTl3djdWKmh0YzZmcW9jWUhpR1BUYWxBPSNOPVQKemFpWiY5KExsd3hLfUh7YF9x
OEJWdHt+YXYoTl5uQm56OHEqUmdIfWVec1R4Mz5sVGU/KCgrbl5sc18/V0QoPE5hCnp2dkFBd0BT
dXYjPWc+Oyt6c3x+eGhQcCkhPyM4WXBkdGBxcDsxO3NTdnRObDYmP31RZUM1UG1FdFYyQnw7LUBU
dQp6PUw1Yj80QUhhQl4yXilCcnx1a1IlZnhrQHpeKis7d1ZZR1drR2ojJSU4OzA8eldhRkowNmBe
SHlwcnM4I15ZdU4KejkpdWk4aHB6YlVKOTdKNlg8ZTlgI3BXOGtPVndrMkh9eT1+QXl+QjBldE5v
a2RfM1ptYUhEWm54V0l9X2R1dzwxCnolaUhJRUAhRUhtSkQ2JlAtPHNvYlRQcEdIOW12NG1rODF8
VXFQITVAPH1CeCpQYEMqME1jZntZNllLTVBuKTtWZQp6LWYhVEVxVD9UUWpYaClBUz1pVjkjaXp6
dz00aCpac2ZJeVRoNHUme0hIVj9xWHMkfXo8QXh0ek41d2NvQUdkJk8Kekl7dmdMUVN6ZXZFWXxO
KTNjX3s8NTVlM1ktPz5DNXk/VyglQ2FyOTd7djlpJSsybypNbmJifmd7e1ZzSFdRY1hjCnpOPF5u
Qj4wPTchaDZvTXVMQjFWK3loOUM5WHh9d2RubShJKnUoRnJpSXgjUXpIVDJOUll1XjxvYmd6K2BD
dmBuSAp6JVZoN0VNa09jcGpfRVM4NVhadTRpfEZ5eHNhRHN1RCQofnZaWTdSKmQmbW5kb2p7TnpF
YXRfQkh0MjgyR1R5YnQKeiVjRjB0SzB7RCopTGFJfXZrWjUrb3ooSlIrcUJ7QHB2YmhnRlRDPGdP
R347ZThGNnRGPilvaEFlZio2YmUkPGIlCnpYQE0hNyZLaiFBcWRELU1qamZ0OHRoTGxja3FPY1Yw
eEJ2UTNPZG52U2FnQFF7ZmtRNUp6SEU2eVdhT0Y3KGQ4MAp6OEAwRmRCSXdnbiNhYVE+dyl7XjNM
QT99M01TPDhfcU5XYnQheV5od3RzRk1sM2RPa009MFNfWlBwcSgxMyFsKnsKenlIb1otRiZEaHt5
K3FvQ0QoMDdadG5LdkJSO1VSNGs3N2YxbUtCbkojWjdZUz9VWTtHXnc2QzBAaU05R0pnTXZtCnp5
LW92T1hHWmYwT0xLbTZMOFhxXmFEdXZJUmg5Zzl3c0hpZmtPQUYtejUlMTAkYGh5OFN7YF8mSm5N
dDJBTnojZAp6SkIleW5BQXhfRGZ2WVg9UmYtY2AzX0FlSC1YO2dnTHY0MmdaeEFsRmlrZVk9a31y
OXU+a1FeLWF9fi17ODI/VzAKej9ySjZSUUorTHwyS2hEZzlsK0wwKVpvYkFqRFFoJC1PaH45UFZH
cHgtaDE1PyszPHVoVSh3ZSopeVZmSGdyY00tCnp5RmN9djMkJUhFND55bTtGUEJrRWZ8eG15eDUt
OFE2VU5fVm5ENV9AVWtaKU9vT05aRG53XjVLc05GZzZeQ1MkOwp6Tz5MZmdldVUoeGAhWSZjdWRl
IWxaZEZLPFhYNlJXJS1WfFJ7bEhMbjllaVlkOGtgJUQ+Km5PSEZSRzwyKi18Z00Kek54YUBwI2ZH
ZW9KN3ZwNXFjSCNtY2U5S3VqNkY/d1olWm1RNGw4QTdIWmxkWVB+b01HdWZCamImdyFhdVNScExK
CnpJX19wbz0hYzlwRWIzJW4kTV9YfTBDK0VZLStqNiNWTUFXPjJXKzZQU0w/bSl4LVFBOG8pMjw2
LUYwK3BKamF6YQp6P0M1VjJkOHgjND0+Um0hMGJ9eTJ5LShNMTNGPip+SHs0KGdxYT50dVc0WUNV
Mz8jYldfUWdreTV7PE9BKWQ4S34KekY0YHtEdEg8ZlU5MXMkUUdSPTxoQCNuUERLJER8QDFSVTE1
JnllcXE0YWlNd3d4MTJkNThZMiNzfk02PGBKUldvCnpJOHJ4UGA2b15iM19Fak1tSitUe1JYP05Z
QFNDTyRveWM7fj1tPVA2JTtIfG9FJDNeQml1ViVmUiVlNzZ2TFJqYgp6JVlBMzt7c0FwbzFJe3FW
dXY3aTx6MjY/WntFJUtoa3J4fSs8P2ZYOCZIcD8pNlBpcVBSJXQzQHEpaDNpJV5jYXsKemtic0x7
XnZYaHVHMnFlaE5YJFp5VGh4MkRUNj9GanQwJUl4YzBFcmoqRClUMTBZJHZEaVlgb0BvWXFCSCg2
Oy0rCnpvM3N4PVc9bnQmQkkkb1Nfe311Q1Y4TWlXY088KThxP2w1fUFFN0ctUWkqRnhffk01QFdS
eTUhaFBxRj1hOUI9dAp6TGdAQ3FsJlkmUWJ8OEJtcGpEfSM3Zkc3d19JMXtnYDhXcHs7M2VINz1G
UlM0U155QjN6JT14b3lmLXYtezlFWXgKenprdW1yQ0U5NmdeWCpCPj1VQCZjR2Zpflc8SSMjeClR
KGdqPjdibTZSPkgkPHFaYDA7QCtlcnphMV8rYCE7Z1RkCnpQZ1ExT2QhQzJrSW93NDJPSypwfGp7
USZ2MWNjY29tWDxRXiVKeGN5QXU4TiElQXtXT3o2JXl4NDloZjdAMiVUbAp6I3I8I15yZGN3PjNz
ZiF0RURxRjtxYV9kSUVwRCpsem4jSldtSmJQWk1VfTVZeDZnclNLS3BgZnVmZ2xoKFl4VlIKekx9
SWgrJitKZGI3PDdLfHBVSXh2V3R5RUZQJFl2ejZfQiE3IV9Ke1VMdFpAflVMVmZxOUlMVFJxJnQj
YW5adTYlCnpgYGgpQm4jK2xGNDVeN3lSeXAtMilPSG9qe2xvN1hVSDt7STYhQlJiSClvUHJWfSFO
SWo7UGQ3NExhKXdKYUlZdgp6JjdUUFc7RzJxe2pVKEFpOTgmJSNebilKMiUqa3RLe2g4MGh2ZWN8
aUQyYHpsQVRLUm92NEB7VjVle0h0NU49MV4Kem04QnMwIUNFPyZZKi1hQiprRDdOMSt7VjFMdHU/
eDZBWTJ2SF5aezVzdkZVUHBSTS07dS07I08kQHhZQlpsfWAjCnp7Z3cyRzB8aWU0MSYwVWs3M3El
KkNueyM3U3lkTyhDe3s9SUxFZWMjJGtpSjE9fHoyNSheb3RGRDMhOCk+NEshPQp6b2RkbEdmTVNt
UXR9djlwMn5aM0t6QGIxWmY7Wnskdn5GNGZYWntxbEAmIVFCYj0jMWUjfD5hOTEpKjJHX0NkKTwK
enpeS3h5cURaTTVzX2piKGlYMzBgLUdiVU8pdWJYcD1zZ2RrMkNFVmlBdCtoa2A0dCUyPlhgQ2pP
MUdve1J5VEFeCno0KkRUUXg9dXhIbX1YaTV3VzgwejhmeUNudG10TF5JMHJLV1I/YnZBNjFZJSRS
djl8YEomNTt2THh4NlJwJmBXZwp6JT1maG5HeXU8Tz5FTE05cnEwPSRWSjs8KHkwJWk0ZkpGfWxW
dT1ocDVGdjhAPGReJmVGY01IKStlX3c3dmBVT1YKejI3dXpZTnl3QiV7JGMyY1lAazNwYkM4cHJg
X3xYS0Q8e25QdGp6NlQ+MzchIzJJPllIJHtiMWZCZDFaYFd7fXEqCnpzWDxFMUU3ZiFOaT1URCls
OCYzbCokMGR0Sk9jZCVqUVUrXnFpTT4rO34+OEp1ZXhUbWNUeWFzazM5VkIre3BAVQp6Rm4rZCpu
QlRBNGF6KzQ8e1hwdT10dlg2QCV2bWNDQk58ZEdmY1defj9mJV5DTlgzajJ3UExXXkFBenhkWExH
N0YKek9hVCN9Rn1+cXVFJDFJbChmMEAjUnw+IW4/ZTByc3FhIXMtMj59MTF1WCQ3bHgmUXMrQDI5
JVR2cSQqKUFlezBCCnpxT1N+YjBydE5GN0krPnEtVyphSz03UFgxcl5mNDZSa1F8Ul9kIUdJSy1e
RiQlVUw/VXFAYiRrSlJeZDxDe3VwRQp6RmQhS08/Jm5geWEpWmEta0xVJXNhalNAKVcoMiM5dVk0
PCZZPHpqOUdBcCZHIVEpTztgPnFXbylSSTAtNk9tXisKemA/MlRkNTIhajluY01TSDhYWXVITzg+
ME95ajlgdTxpcXctZ1ZRa3x3I2lKWF9fJl98JnA2UTc0WjZ6djNDfXVhCnpIJH1kITBvPShGNFBu
S15vZyN7VCNVYExyU3pzVTJBeTxfaTltNUs/S1MyNiVycUt4bjh7LTAjXy1kNFhUN2Nmdwp6Umsx
WWBYJE00RXdeRWlUYkFnPHxIbi1ATmI1NUMkVDZgfUF5VnFHbFVUYFVBb1Q3IWVyYTg1XjstcW5M
c0BOdW4Kej5+UHd5ZUU5aXkmI04zJDYyKmllbUhvSEhVYHkoaWsqYiolOGBJa2xXTz5XNEVzdTNO
ZEUweSljfXUrUVhsMGxECnpyUHFqKmFLfWM1d1lxKyQ8XmIlRiUmYDNyYkg7UkE2dXM+cWcldlZg
S0ptKnBlfUVQKGYkQntgd3hPdUY9RSlDSQp6eSZsTWpoak5iQ0EzPiMjZG4lOVhwSG9oZzFTSEZ9
I3IrRERjZVFBbWt+bGA1ZlRqNG4rU1UtQis8TUVfdjhAZDMKelZhaytkSyNNQkNmZ3lPVzFANWxq
MDlveD49al42YUEzVUduYzVPaiVPUEZKMyZ9bUBYJENOQzhtVWJDUFZfOFZ2CnpqY2YyUDBKenI8
NCR0Yml0KU9ZdVB5RnFfLXcxYiVJUnRIOXtHNGVSIX1ZclgxMjZ1Z1QxejtTb3BVYmlURXNuSAp6
aXZHfnglPTM9RlRAMm5rRSZVRlNOfFc7RHlIMz4+KUEpOzlaO2wlUzI1PkJ5QXRkQ2I3TGwxUmRi
JXJgcU5Zdj0KeiRBPnBRVFFDKF5GajtHIU52Zj1MWjUoSnxPRnE2VUl2YHw/Yil2NEBNLUZ2T1Vt
SXsmPjR7ZEBsS0d0TUglRV5xCnpQbyF3YTZIRjg3T0E3bT0td3c4ODVEUVA4R0U7TjJ1OGxrcmtr
UT02elBjZm1GSz4lOHJHa1R4RXoqekRgQ1Mhbgp6VztkN2sqQE8jOExGQVZWdzY5TUBBLVRFUUh6
Y2t1QkRoZ0Flbj5fM144KzY+Z2daPU1ZOVlacEApVGVpcElGO3EKeml9UEZJb1grREhKQGkpfXR2
aH4md1p5c0JTO34wOTBvYkZneD1VdW4kIXYxb3Q0YDxFJVlXMENHOz1LdFk8cHo9CnpAKm1rQjxA
I0N7Q3hgYSM3TnhybHdmLXdEbW9Fb0JkckA4KnhjemZvMF8zJDxAQmMpe21BPkQmKnc+SHJWSHpX
SAp6TGcjLU5CcThiJmd8P2xJRk00Y3JFQik7fmBnS2k1IVlsZW50JGhLPmBgY3RkMVlHJjZpNHhO
TjJVakRESFFLIU4Kel93T0wweHppb0NSeWgxd1R6SyR7aig1bncxT3Q3WlF3ckN8cEVLKz5QfVJ0
c2hIbC15YnpjaipgJjxwclh7VnFHCnpMPGEwRlY0MFlrdCllSTFmX3t3KHR0T3FgdmNUQHIpNGpH
Ui0/SlJuKVprVTxLQWAlYWRoWHJIWW1TK0Z5Xmlfewp6cnZhbkQxdz1VdTMhWXQkT1lZTnJ6aVdY
P1lmTyFWO3RJITwoOWslMl9xMDAhJHpRYXx5d1J3Sno2LUQ9OyFJPl4KekY/UkhheGwlQFI+WFlW
S0JzcHVBO09eNFRgbl9kUnsrOFo2ZDk4N3tVR0hnOzFxeFR6RXBBeUZRYU55WUtTKkNzCnpaczgo
PXRwYkMrbGElMjI7O15odmxAWUtAU310JnpRI300fGRfMjM8VWBIa31sN1JJWGlIOyUlJlNQOXJ1
NW9vawp6Wl99V2tAX15HVHd9V3wmJDYxNDxjMTNsTno3cCYqJHtqSj5LbUdtN05fdz9qNFY/cW1f
eENqeUFAQ2JCI3tOR0kKemBHcH1aVE5sI1JwdjYtRjx0X2d2JWBfJn04T0tibSttcj9aMkMrRXpH
eDlqeFNaX1hpdCpMTTAhWTIpcjI9LXVlCnpjPmpxSz9JOW0wQkM1NDxfVkotQE4xMEo7PkVWP21V
QjtfMj4jOVM+cDI9Ri1AZDE3UjRCKCQzdj9kfmlBMyZGTgp6V35YaUpIK0xlKD9Lej1kYmxwQVRI
YH14NztERCZFcj5UMX5ZeFQjfFVJaXE3KWgxJkRCNjdzR0pnfHFDV1RjNXoKenRSRnYjTUZCQXUq
fEl3VmBPQFhTIT9fRWtgZUYkPiEyUDAhdjQ0byl1dDZjbyREMEBgaTRwViVYKmI9X2Y/X2cmCno4
Uy14ZTVqNXE8JVNqPlIyNmBCRWk1SHdxOGBge1NRTTNIJmtZbCR+akp6bWJuMyNlPSg0WUYzWCNm
IWZWclRgcwp6U3hiMnEoOUJuRDFHbDl6dksoRldrKmFZV14jaWBSYkZoPzdAQVpvMVVTYVhqbVhE
SnN1NVJMVz1GbkEjNmR1eVoKenNRNileXjNFYUQyNXo/N1I9Jjg/elkxREIzRzdKLWtjTjx2c0s2
e3s+ZiFpKGBxRFdqTmB1R0JSX1JoMChYcWBSCno+UVU9RG0jQkBPZD1vIWwmcE53KTNedXBhTHQm
flNMZFZjd3c2eXtWamA5TFBEaUQ/bEBzfTIhSFhZNENIaDtiSgp6TGI0bml5fG13RFRmYTU4RTB4
Kk57QUJoP1B2Rmg1TnhrT3NRZj5KMSl3SnI7eEJGZnUxMEgoOE8pSk4pXjxAZHsKelVDJTV6eVBa
eiU5MUp4WD1EfjtJbkdzQFN6R208RjtsWV80P2xJJC0tUCp3LXpmVSNDbzt6WX1KNzJLYjxJWVJw
CnolMCFWdFImcEYjb21TXz8qQzR3R25IfVJ2XnJjXnpvKkYjej04JGx7QmNVZWozQkBHVE5BPGJS
JmBqLVd4aUpPcgp6TS1CfFlUQD9yR1oxSitRR3RpZ3poNjlvaHY8KDB7ZE5OLSRjenp+UyZIfjJC
SVU3dXcjKGNXKU9QVz01Y2Y4Tz0KeiNFZDE8cFVEcDF6MUApKGZhUHhjPE5YQStgWGhzZjJgVmdq
X05BNjNZNT1gRSs9K2VmaV9lTWo7ZWtSbW94dDFfCnppbW1DSDRUSEtTPHFSYTc9MmtMT1JJYXBe
cUZzdFhrOHEhK2VHdkRTP0cpdSRnan07ekYqSDcwJFcqcFM0cHVOegp6PzVXRXcjYWczU2FYV0d7
TSg/SFAxRjcqITlrVUV7QUVUP2NKbSRMJHF9IU1eJHZgfFYjRVp5bzlJOGQyczhqTlMKenlLTnR3
cS0xIWlJNFBlcnckV1NTbjBKZjBhJTYmWVF0VD4tLSNqe1kzKEVpSnAqRCU3XmhfZ18pTz40Zyhh
bDhzCnorLTVZKz5TaVB5TSUpVyRvb1pQVTI2eF9MUG1IR0BDQWJlbzEtMXYybHJZWk9ZOHpNaFcw
SGIwQUNhRnZQJSRAIwp6SEp5cDQ3SXtaM2YydDJTJl45V3FJQlFOMTVBeH47PFFOYXM4RnNjLU5E
VWF5P1hjfnp7UTY4JWcpUk9gdkFPKGEKekVuM3t4K1Z1NihIbzVXbUBjVyMwclBESz9Je3dhYkdG
K35yPUFHczktX0NqIWwzMHpiSDk9cTkrITt+RERhYm5vCnowS0NWdnRqYWh2R3kyIVElKERkNjUj
JXxic1g+fXJfRSkwbnZmYDdQSjU2Z2hKeUZCIUlDVDVacTRnR2JHWHNBYgp6QChGUEZFKmRpTV5C
WnFDP2dvZHwlIyhHP0Q+UFdlXzxxOUFIUXNMTjRxYWslUzFeciUzcVNsUylMe2cyYW9xSCQKempg
WkN3a2dLaTwxfXt3T29AXzI2Nl9sRGlzPXcxM28tU0ttJEllSzRidGczaTk3WERfakZ4dCQxKDRL
aTRJPXoyCnpPNmI3b3ItejVvSCVjVWtOdSUwKk8oX2pwPk1ueSNyKVp6OVcpSlE2LWZNYVdKcHZ4
d3lxSThVX2ZGTnUjRTU1YAp6bGVTfnU+K3lqOGJsTiVaXz8/VEQ8QzB5ekQoPXNiTUo8QERXKlZF
ciUzR2pSKDdQcDcwJnxlOGtBZmYtSXxzVVoKeiF2YyhkUW1GMGVzY2tIfUZwWWB2U1QxY34+JVkl
LVo4RHI0dTFOSVArMlglTjkpPm9ockExdDJzPWJ7ZXsxbmU3CnpeUll2QXY3ZWk1WihKMi0lcEp5
U28jPkBMaSpaT19rOV8wIzRxRGBjbDE0VzVwMXJOekBlJVI+KiVkcHJ0cE9NWAp6VUlnfUdSUVFB
RmBXZVpAcnI5WCNAZnxDQ2VrPUBuc1JQeWBjZVBMcnQ5YVZ5bXdeSm5weXc8Tj5Jdz8kPE1LT3YK
ekUlODRsdVNmWCFeTXwjVG0pPz1AZ2xNS2ckNnRhZWtlWWgpaWg5TFFqY2IoMWRRSTEzaS15a29V
Mn1JSjJoX1ZDCnpoKHUwVDE0fTJ5NlVOVEkmbUkhSHk5e3gxaHhXVVY4TkVqKFFWdXspcHcjO2pm
d2dybjhaPGFHPyZvdE1tQHNjJAp6STU9Q2k1KnRMNXF6LXNpNng2V3UlVitPfHJeIzAxcFhqKSF5
XyFFUDR8KUdqRlR5fjJVPTd7ZzU0UEw/WkI2YE4Kelpwc1dnI2VuOFA+cVdGRysxZXd2MyUxbDBD
dko/TGNJQntfSTNOMV5OZVg2c3E0N2RsNGZmcnVnbn5sZjh9K3BtCnpiUWtGcWIrU1ZWKF8xJUVN
NF9ORmt8TmVXU259YCs3Q01NRWUhaDY/a2V1QXxyV3JDXj0mRk1aNGkxaXM3fXZxXwp6MzBxNzNm
ZkwoMWg2UG1vPnkka0ghYWBUUHltcGBNIUI4dENxb081V29vdEVAQHpfa3pxNXJMKGxYK35ReFVp
RD0KenF0Zn0xY2lsJWRGJDFyJkczfCtsZWdqPEZydG1VPGh2SGMkO2AkNEJDZ3NfKWxiKCVoKT1s
Tyo1S15iR3NFQkpOCnp0ckxTeGQxSmhwMXkzT3B3aUxzMiQ4bzA9I0lJbmdPXiM8fmdFTHlSYEVr
NF5KJTQtcFUhcWBVdnF0YFFoVVF2Kwp6ektDcz9FRkBXYmtRbE1eOUZrZ3NhenhiNSZRMnNnWiZK
JihTd0hiYHFMNUNMbCpTNCpKdHFvQiohMyZKSiFGSHgKekglcVNkTDB5KGAkJW9rR2daWjNVO3xX
MjwpKG5GcXB4TDdnKlk7Rmw4VDJnVD5weUJLNiNqYkRMOVdpYkkoVW07CnpNJT5vZ1E5NzE4IyRl
QzckVjVkfnt7YzIwIWtKPT10Zlp2QVp6K3xZdzIrS3NDa0taVnF7cGZiZW9WRGgzeE5VVgp6bite
MmIza2FjMl9YU09gKTROaCFeQHgleHtPVW9eUkJScj5QOW90O1h6cE00Ukx4fTJjNntTLT9Tfk8w
Q1g/QT8Kekc0clZUKF9Oa0puWFZNVUU4M257enszMzYqeHY0PFU5eH57KnM0TD9QI3xXaDNDOWxg
Jk9GIT95dyE0VlJMamtFCnopZyRiej1mdzZTRV4xfk0rV1MqQHk5fGFISEMoUEZXSz13Uj0xcXwl
PTQ2bHRENnh8ZF9IeWUyTjUwM0Q7bHlLMgp6X29tam9RTCRSNlVBbnFHRUY9R0FYRWklZ1I4QyFe
cXF0ZTx5ZXdxZ1JMYjRtM0JwYFFjMVUrSVRyajdjQ25gPmsKekhSNmJlYVRxQ3BiUjs5NUdqdmE/
dH03KW5HM3BeYDg4d1M/YEJ0UmVuZmQmZ1lEIUIpMCVQdjZyRH5UcFdyRFB+CnolTz82eG9hLXpv
akBkJUNoPDZOSSg/IWNQQkU/ZXtMZUJnUDRtckxwYkUjUiYhP2w8cSo2SiNXK053PWMoPT4kKQp6
KTVnYEo/NnA3TzROO3puNmpXVnMwNmhWfF5Ie0N4JmpZPjJPTT9USjw5cU1ONjh2YDdrMEQ0cCM5
N1R9YWR6QHIKeipIUn4xQyNMUndkM3prM0F3MGl0KnUxPnFmQWkqVkw/VGhMZFF1Z0RwKkE+eE1S
ITstbHtaYDI0d3gqPCh6Nl89CnpsJDM7aDNMX0h0SmhCZiFkRDJyXnI8fEJSVisyVmxyMT82Zm00
YmhnWC0xOXM2byRmV0pyYEE2clFZfi07Wmk3Rwp6UTBOfk4jNE4zbVkwRnp2bUw1MT5RdChMYSV7
RU1LNVZ3ayFkOzVMcW0oNEdpSUNsUmI+Xnl+N1pWKTcwO0lUWkwKeipIN3NqaTttQHBwSyo0NDdL
U1RnTVcmcC1LbzJxNUVxd0E0YiNqTnBtNCl5ODk/fiNMcF5FIVZ6WlRqcFFoOD9UCnptZEM/cHsk
aTt7ZXxuYEF6NEVHZkh3SDMjMmBheHh4fV92K2VaWGFKbmF7fkRHXk9AMDBMd15NT0EyQilKYmdM
Vgp6KEhNKytvU1FxK3ZSUXswQ347REtTVUJxcEV0bCRua3lpZUdKfGxIbDFPSDBrQHlNbWRaP0BX
NnJgST5iZ1JKSiMKejkySGd9OTVXRFo7I3pZPnMhPzlhZWxkR3sxa1E2LXI4TSN3cy1qT1MlMVhE
MzwpITs/Pkx3YSszVTIxWEoxeklrCno2fSNqUXFidTdRY2BZcm5vNEJ2e3hHbHQ3OGxMWWQtP1RK
b3NuWFIxZzNhQjs0dXdLWj81MH58eHlSNW1jWm48aQp6Mko2MD8xLU9KWF5aWiMtX3dTYTxYPj85
Qi1hPVN7PGVwUiZeVHpXOGpoPiF7XlgwI2xkRio/c0RMcEAhdCgwKEUKemtpeWlTJjd7cXpva3Zk
Rk03PW48V0VkU0MtOU9RS081VVFAWGhnRWhqR1ptQFJOMl42WXA0Mjh6R20wbng8MFhZCnpYQTJG
V1YhU2NxZlNMU0tWUDtrKiN6aiNuZG85b1Jgd2JAdWBzVGokRSYjNFlUQHpLX29rM2ZoOVhEQikt
SjZVTAp6YW9FQDkwMWtDVmQ0T040MG8mVC1UYiM2MTNIIUNLYkY1VWQrUDtAYzZ0Qn5rKTRUeEB6
fkMrMVYmUit0eWNjYUQKejt0T0JsRG5DYlo1fWl9VXhebj0hYm5CPUteeTA+M3VjMTFrJnR6ZFMp
dkU5ZXZTIWI8KzZVM1BAPldMO0FxUVc0CnpTekJBe2kyb09xbWpzc1R2XnZmdz5MNChxWXx5T1NK
QH4/YF9zKF9Ve2k3Rj9tRkFVUjcjKUMrQ3tXcUZYeEpmXwp6Q2N1c2hfQUopcnYoOTtRP0w0dF8q
JVFyX1BEUmwzUU1efnRYaTgyJm5yUl5WS1lZbGx3KylWbyhTb0E+RGFBTS0KemUobi02OHNGSHxx
JGhlYk14QWZzKEM7ZF44NzxDTHRMSGA4eDklMmRlckJQZ3Jee1FqXiEmSm5Ca3VXaFNjfEBjCnpZ
cTVvWTQxcXhLKmtnfEgzQFlQbk5pKHdXPH08U3h5bDMoTzIpNEdyWko4P092TFlLOWl8dW1iZz44
N1I1QzdpJQp6NWFeTXM2VDZKZiFoWHQkb2pkNSsoLTt3bTYpRUhWMW5JcTVYOHhHKHdLRFVeNV87
QE5mQ35JNUpWTWxKXzNzb1MKejdqQlV2RktKSlI2Zzd5TGl4PlRQe0pySHB4QGVFam5aMHhBIVBA
KGFAPHBZa25naGoxIyh+Y0tNX0dFNWEhQUxjCnoqPVRRamxFXz98LWRtaXtVa2NBWlZyT3dxRGV2
LUBfTHA4OyhoYng2RmV7e3Mke15USGdiNyYhO0I4JCFiWUc3awp6ZjImen0pMUApVXJGRXlTUXFL
SmljZ31Cb1g5TGdZTkZ3Xit7TXtWRUF7elpfU0xrdzxEM0tFZGZuM0RkP2w4bz4KelJmaipgK30h
KiY9P2Y/WlJaPnp5d089e2Bje1FDKEhxKGA1bkVhRy04cmhmTG5fVXclTT1KQVpYPUhqUTleMlUx
CnpGck43c3VaUUxLKmtxcUtjY3B+JWJ+fGEtZ3dPUUBrMnVHZUwzdiFAZDxlUkc+I14kcGkjSjAp
N2FeTkU9dit4cAp6NThUaEFKfkZzPnEqYyhYOSElX2JZe3w+MSR4QmxjYzJpcE9taCthTTI3QE5Q
eHxXZHpJeHFUSzVpPEwrQldZLTEKemM7PzwrTCN7K3ReQHEpXkx7Jm96cDFGd0tXNGU9QllaSFYo
cXRHaFhzKlB5UGxFendHRSZuQmQ0NHNxYW9nWmVDCnpVZz8kPDc+OGV5V0JJOT9uS0l5ZXVYaklA
Xkw9Xzc+a3VTdFUkaz5sVz12RztjQWNoV0VLUnxEPiRPZG17d2REKAp6TD13TlFzT1dUWVVLR2E4
V2Ilem96S01CWllJUmt4d3t3THsrRmk7LVBUailEKCVGJF9eempzaXI7dmoqayhgaUsKeiZRV2sl
WD83RXBkS05zWklqSXgjIVROSEpaPEQzNzdLMEpEQV40VkpJNUAme0xGZVU4RDsmQDBOK35MK3RX
PnZGCnpqWismRFojRjcocW8pcT5APyQqWSRpfHc3ND0ydWpUSV5YJXFoa2ZaNmR6JnRRUFcmbXMy
O1FrN1NxUk1SWUBzSAp6QE4pPUVkKyROUHlFVihtUTMpSEhtalhLVyNYdylxdF57eylVayYmYThy
OGRpbmczZ3oqTHJELWNQfjI+OUtoSG4KeiE2U2M+dFpRZlJQJjhwZ1lzMyZQKHJFWnFqYSt4V2B7
dzUwaGB+JmV0QWJ5OSQzflZKLW0xQEpzbUUtZ3IkKWZ7CnorenZ7JlhrSSl9KTcjZ2pvfEFlYys0
S2FDTCZQfih5NkR2ZytnbkBQU3hncVZaTHQ8b2YpNGY9KlUweiYtSTtySwp6VVN5NzBvOzNkU0Il
WmBLbSNgYmNyWkt8bzNHenY8TzFpOXlUZEZJKyFDV2pSX34tVk05Z3JyKjNjMHZuRU92RU4Kej5E
QHpgc2AoMzVqSyFAdzh9fDg7VUo4ZWwpUiZ9T0tRdVR2XkpkIWFVRXtfPUxRPFdjXzdUQExiVmlI
MFVYZDsxCnpISGImfEVxMjwwQmQ1OHdEUiNZTXBhOVYhWTs/MEROMGN2JEA/VTt6WHI3Ry0/UEVx
UFVffDQlZn5JMGt6KEtxUQp6P19fSTBXTmpnIXY5TVUqK0Exaz9ZdGFRaj55VyErOVFPSytSO0Q1
UmZsQm4qUDhHZS1nYl8zVD90eztrYm1pPHQKeiMlLV9gNjd1JU9EJno3TFhkbXo1QnwtKD9BK25R
antJeWFfa243IzEjZl4rMmA7d1ZfaWBCPEw/N198THp6V2VOCnokO2QzZitxYVU0d09JY14+PmpR
dE1gbzdteEhpPnUtIWteJVY+Y2g8YjJSeVQ1eVctJUVLfHxAVF4zST1qbkomKgp6MnEoOE4hKmRN
d3YqezNOQGYhMmAzPnB3OyNkWlIqJnM/NkomRU5lUGJDUn1sVX1DJG9sMEc7Kj82I1VrOUdfJXgK
eiQpMFo2Yms2UUBeUmczPkchIWBFdiV3NXJDQWBBSS1yY0xPLXhiaX12PFBESE1OeClUcH13SVp8
QVBxbkk3aTJVCnpCejRrb3FXV3hjWlkqWWdVUypHJVItQkt5I3ghTEwrQWhqM3pZTyloPW5YVUNR
U21xRE5UOGVFcjBPbjZEUlphNQp6YlEoVjVIUFdtUXF5YWslP1NXIWpJeGNRb3RVUlRRRmZsYjFa
MTQkc043UVk0WVZ6QCRhOyZmRHYlNTJCNm1NSkQKeiQkTSM+YUNBTEg3NUN7eDB7NzFeSjcqT31f
QXNMWihlem5OVCs5R0o2OTJhOUglc0w+cFMtWXs0Pzx4Q0V3O1pLCno8NEdqOD9qfXxpKXpfYV8k
aXFxQTN4TXpHXjlING5mNj4pUzlNOC14RjAkM0pgKV9AZVVLZT1HO3kwUXspSX1KXwp6TnkwOE4l
bXVaMilocVNjNGtmOSQoWEV3c0llSjV3RXA9aFNHe019Tj5lbERKSEomQEhRSiFVaF4mfFBiWVc4
KmoKem8helkjb1Y8dmZrZ2pFaSFyezEjPzdmMHVzY3t5REQ7Y0wwWHQkN0BpTkNuMipkV3IodTw3
ej5TRHQ5JTQ/TjRTCnpOc3U9UT1PdHp7dDhXYjVmNGNRWkVwV0o7LXUjUj0rYU5xPj89VEhOMnRA
X3R7T2UkdyVHfmw/UzF2Iy1JeHE1YQp6MnlHIyRDKEIlMndsXm5qWnpyRkBZcnIzajlMM0cybUxO
IXAhTktqeVhBc3JiciNzWlRZS1EkQFRLc0ltYGlva2cKemk0bUhDRVQ9UFI7MzhKMGV8YjVRPT91
I2QjRnI5TkRiMzVhIysjWFZEKUdhTCFaKncjME9+PjZsd2gkTyF3XzUrCnp0Rk1weiNDdnQ7aihS
Ujs9TUdJbUx6O004QndWfnhWQG45Q1BkdkY/MTE2SHswKEwtaU9BRWJ9JUFKcjIzNzN1JAp6RChQ
NmBrVnE5NSQ8NlEwWWsjNmw7QTVFUTZMKSFFTGhhSiVzWnQ3YyQlR1Q9djtKQTVCPFkkfDs/Xmgy
VHhrfCMKenN8eSg9ckw2QmdUM1FHdlJaMSU+NFooJH5yckBMSE1NZFdjZyFhemFfa2xZaW9ZQUdO
em43Yk42PXNjN0FLY2RkCnpQfmhIP1JhbHlMV3RLM1IhTC1XTWVtTXFoaVVqV2dUeUMlfnNINSQ9
d0M8Ji0lODl7a25LaFBEWGpLMHlORFg7NAp6akx7bD9rY0VHSkJRdXBneVNecD11bVE8YCZ1ZDt7
X2BIMl9SUVRSPEAwX3t7P24wNnxjbDVYZzhlRzI7S1hpK28KejZiUnMpWkwxSms7OX5qVXpPI2Bh
eT5FYGpUZFE8KXdYP0NDUz9KbD82bEIqSGFYMD9AKjIxVUokY1Z2YF9Pa09LCnpCUml2S2MkKS1N
USZhNGw+an1rPFhBMTMwNHZFTW00bjtvSkZgfTAmYUJaJClyJVBTe2AwMXAmRClDME49eURRawp6
YH4hN2tiKm1iKUc1P2ZEK3p8dn4jZk5GdT8oWGlBdF5DJVEoR2ReUnA3S2pjZ3BUSSV1WTJ5QHlC
RThBUUZVeVIKenkwXjZ8an4qZnFgR0BqPDFLZUY/bFNmS0NTJDR4TlNKeXgrN01ycHlpa2dibXJN
USY3NVNWUnRKOWNoaUFgPjFiCnpFWDh2RUV4SWdMLTRDdCYrOFFMJnJjJnk3I3dDaVNqZWpMbkQ2
Rlc1UU58LWdGR2JvaD55Tjw9cnttfColWVN2Ngp6IzRmWWZ4Mzx2MjdyX2RoRTw1azQyWng0eUgo
JTh4ajEjK09HX25TREhSdmlYPU5DOENARUBQYio0JGk7JEExdWIKejhyQUNWSUJGQk5DKUsqMSo2
PGNyVnAmRD9UQW94aFAzTlU/UmBqN21oaGBsMWdyVE9wSERMcXduWCVnK2ZAPjFqCnpqWW1kQ2M8
KF9xSHJYakx5SWo1YSpxNkYmTmIzVkpuUHA2SHA1KThpLVZjdUZLV2IxeykzZDlpI2A8QHNNcmJ4
VAp6OU9MRVp2VDJKPTQ3R3lgWW1ie1BKVyZzWkBCRFNMIyVwNGk5bHIyLS1NcWQocz1lM0gqWCEx
ZzhFKDY7dWpeUH4KenlXWi02TyhuTzNsVzQrbWYodzVLUClQPn0/TzFORHlGTVBYTTtOUWNKOXls
WjJ5e2MoNEh1SEFycm9tYG04ZWd6CnpscUYtV3VjSlY9RDV8Tl5RfUVwMClqekxxRjteJGVRWFBw
KDg0SUQ/ejM7SVJiP3h+KmdKeUJEcXlsMGE9Oz0zcwp6cnMreSomfWhUQ3syZDA3RT8rNl5kTStZ
fW4+Z0xXJU41T25he2p4bDs9SVFRP0cjPCN3YlkhTCY2PjRnTCR+d0AKenJEMnszOT1CYHlLIzZz
cFlZTns2KmQqOVlZPDVzKVI7VVRaXypoV3I8KXMqa1J+Tjg1VUJ6NT1jI3tib21ER0E7Cno4emc/
ck5ERUYlcn05bExBbDw5eS18QTExV1d7YDFERng/a2AtU3w8U2RBbTxjSkRrfTF3Pnd0MUxOSmd8
M0pUUAp6KXYxS3o7bElJUmBAUkhzSlRINWtWN3IyPyRyPWEpT3AkRmE4UnNifSZmMHFEdEB7KnpM
MFg2QzVMZDBTdDlLY1UKemF2VkZJbUFCSDt6MTdPb1N0RyV0IWpkZjNwNCRYdXJHZ1YwWlprU0pn
PWU8RkYxdVJ5dWZYQW9hVUxKRWVseiU+CnpQbEY3YXM1VnY9NFhVckxEYlZ6WnlaMkZ0LUY9RV5H
YE4mUlQxRC1Be3peLW1uczk/M21rbi1eUWZIPFZtUjRGaQp6WV9rbiN5Rj1wKTNAMmctVkIlJWYt
RjNeKVJLN0pEYHxybGFNejxaTnB+YWpxSkdBTVA9UHZVa0dUSChHRXs8d1IKenJAO1ZeY2pxXis0
VmpqYGxxT0FoQmlLfkV0dDMqZFltUDJXJFN5TnpsRm5qNXdOI2hRYmMoej10dThQeUVAfnE9Cnpm
OEc0T3RWLTtVI2t0e0RGY2JiQ1BrOF9lJWhiSnoqeSQjWTspZGZqWHF5MWVvY3hHYj1xMXY/O0pp
aG9iKXdhOQp6REJDRmYrVHUtVlU+QGlfKG15XykzdlJgM04qKjttdWN8dVhQOzZyeDlQQUVLWGlY
dSh5M1NIal94a0hVTDF9M1cKemE8fmdFPnwqIXErRnpvMlBgMStGezVgakAmfDlTSys3RXhkYlJG
ezJ8SVpFWFpNbn5kSlY8QnxeY31kMTEzXzIqCnQwZHw3VyZuTnk8O3M1dUN8QzszZzBLP1J0WV49
cSFfQkZjfmg1JDRXOyojQzM2Jkprel8rTT8pJGhaSWkKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoK
ZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9oZXJvLnBuZyBiL2FwcC9yZXMvc3Rl
YW0vZWNsaXBzZV9oZXJvLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi43ODdkNWJmMWMwM2I1MmIxMzRjNTUxOWMy
YmExOWIzZTJmNDUzOWQzCkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAyMDA5Mgp6Y21lSWFoZ1h5
NWAjKDxXVFh8Ym9UZFJsJlJBc21UbF9mS19SRlBkcEx9VWFEZzNKZzMhVSNsYm1BNGB3UH13OVoK
ejNiSHwjTnF9SGNjOEtndiY7Vmcza05fZTNjUnZzUGVhMVE4S2ozQDVyI1opeTJjQ09lPDh7NVI+
bUs7JVM2bE80CnoteUhsI01uLTByI2lkYGEkakhkdm02Nz97fEtIb2Radz8pNU5DI2lyP182PzEl
Z0YzKmc4cUhnZl9tYyNla21Wdgp6O2QrUVkkfTBxT0d4KE1hMjd9U2AzR19wSStgTXkzNkJYPjgj
V0ZyOUJsRHctI1Y8Y3k0Yk5VMmtJMF9seHpoTzwKejJTO1NAOzg8KkZjV1pMIVA7emxFQyVQbnsr
fiV+T3pyWEMzbnxuSn4/bXFDVyt8ajA0eXVKS1hQMElRMnkkXmV+CnpYKWdRYGVaS1c7eUBZX0Ir
WjNHaE9ONEtgPGYra1h0SS1iUF4rWV5nSzM+JT9sMmxZRTlIY1NMYXdYeXpAakBvOAp6ajNoMEhx
NEZHYDtxZVZlZlV3WX5JST0lJSYqcX57Qmo/K0BVdWB+SHt3eEVqM08+aVNlfDJFPD5BQXxrKyY3
PUAKekNqWm0kQU0/T2lfeS1qS2d1PyRfcTJSbHUxUipvP01OIWQ3KlBRQiooNkhDfWBURE18SVIm
OTFEaSQ7SVluQCRQCnpjdGNFQm19VnVxRzl4e2BiK3l4KWQ9Y255UzlMRSRmN2N4aDRHcko9RyhH
ZWBhSWsleyhmIzJ6Kn4qeVAjfTtIfAp6d1JLTFhPQyR9ZT4jTnkzMjh+TCs8JlFuJCFDPVN9NCR5
YF57TDxYcTYxKns2YW1YTXskMj51KVpEYH1lUy0wPGkKekFnN2NlMD0+Sj4/PlIrbHZeSjJNNUhN
TzktNygtI0N1dGJmX193KVo/NncoX2RqYDhSQENnYTRBJD5pck9QQVBmCnppSGdyR2VmdXF3VXRP
QyF3PGEtMV9pN2dtOFlXd3c5bFkmWGMkc0ZNaStAQlVTYFQ8QGtLZ3RMUz5xUyF1TlM/Jgp6d0oj
SEZsRD5AMldNKmV+Q1Y4fDMmKDN4KThyfUpebVg1fkV1U009NCRPQj0qWiRqamMhbH57NktXSlBs
eGNXQWYKekpMNko9XzZ+RD50TD99cG9pZnI3PzgrO31gIUJNbnpqfFl+YFIyP09oMzRIVGMkSHEx
cFBwXlZfY3J7dmFySlJRCnohNkROIys0VjxUeE1NPz8pXntwKjtKZnpAPmwtRT9QNFNTJj1kQFNN
JkYhU3dkWTlnUWIpekpZT2c2SVVhYXczNAp6TypFfFhPMDRMbDJaOy0zYHcma3slb1p2R2RTYGEt
K1YlUikpdzlsaF9GQUAtWT41fmxYZmpAJSYwVUl8MkxldzEKemExISMhP0pSMVItdD1RdmEmWjRH
dCZSWGtteiltMGZVWCpSZ2ExNnMyNUloe2U4bEdtcEM8fFY9WnVxXkE2MFpGCnpKYjg4UTRCbz5k
SHsjQzU5Vkt+I1JDRHUkPkNae0k1IWxzbXdGTlgmI00zXypaKjZPPFd9JWt5PFZpd3czenZ5UAp6
KVNxJElMJCVNdUReeH0+QDxJbERCTy1ZJFJiJDlYPD1BMjw3ZTBUaklhWUMwenk4WlVLMSg1eGRR
eXZ8VmlZTlMKelRTMzxFQDEoeWFybChzbm1SRUVWbCZuMCRiPmJAP3lfI3NQV1QqIS1FNEMxRTgr
VGE3ITlWVXZJQW9FI29WKl9sCnorMnkoUUgyQVZ7MFFUcDhpUV5fSDFoeUw/TDtYc31WdCYkYFU5
dkwyV3hBb0ttZSlISntiUXdoVnQmdzZfflZyVgp6bD93P3BUVn5sRlJ2U2BqRVFlekYmTH1vdGVL
aEpZQjtxJiFaVWtSQ0ExQllfQ0wlaWdJNHxAWUgxdTZVRWNDK0cKenZxaGFFalU0OWdMbCl4NlpY
aDNHT18hRkMoQEoxUEFDWlBpRH5ZXn5fc257bENne0gwMUx5WnRvOVlgPnpmJFo0CnpRJFk+OGVX
OHFPbmlWLWYjbDVfQSg4SSVMKEl7SW12RX0kaF4oIWhDbXAkb0kqRzxYMTBAM2g8ZGhsVFBtTHgy
Mgp6KX0mfVZCK0lFYCFUV242djI9I2FsPz5KIVh3bUM1YGNyQiNucml1MT09RiMtNlFSQWV3YnUp
bHReUGI7KVI0fj0Keis5Q2NkSX1+WlZ4KXBAVnRzXnA5V011QTRsI1RAYjYhWTFIUE49MHZJdHhn
NDZKTG5PZGReYF90Jkl6PiZAdHpaCnpLVVRTTE1hQXlQWmwqTHdASXYmdEdJM184XlF5REFFRXdZ
S19pIWp6PX5HMVdxRmkyYFIjYHBFcH0/V1lCS2JGOAp6d1k3WlNzfHMpMiFDcX5IYHJfSkZNZX10
Z0okaikqI0JhIzJFN083dW5JeUFRTXlBbX4qc3VgVERQNF9MPyg5IVAKejJBeTVyZjRvYCEzaHA8
fGVBRkpiSE5qdD5ge0l0XjFZQDxGZikqQjQrIVEtdmJQallie19ibll4bXQ3N0dgQSNWCnp3QTdy
Xz91WDI8ZTRZSUEoJk1EPUtFZzxmMDQtfWJLMTAwSmJOZEpXOylGVlBWYjNeVHtiS0I+Tm8zblRp
eFcjcQp6VXFmezkzazE1ITMtdlI8PWtUQWdyRFAoJVM7Mm04X0VORz1MWlQ8RExjUkFLUnVvWWlw
X3dlQS1aU0EzWjkjVjIKelo7Qm4mPHMzWEowc1dWO3VuX2NfRk9uQ2NJMzcqfmclZ0FCXlZaMmY+
YGxwdG8rezg7U0kkSlBMfHFpczN5MUVCCnpYbXBXcEwodDsrUTc/JGdWSGs5TWEkTS03UUNJPXxN
e0tEKFg8KDE0I3A4QCZBYnQpcEE4JDNrI0B9biNPeTZTZgp6IVFVeyRPIW9yIVVBJGJebmhVMHVE
U19TaFJFN1UoeH4jS0krXz5pITw1P08zT1EwVyMmKnlvdm9OME9LODY1QGwKeiZNS0FoN2JSO1J5
ZVdPPGRpQX5OJTc3ZE4oRUZTWHIxKjcpPUExJCZDN0xKODUhNSFRSzVHY0lOTiNTdUtFc09BCnpg
U19eMlEpfCZnNXZQMj5HQERTclU9YDZRNm9HamdBMExIYVErJkRLUVdYKW93dXw0dE18d0xGPENk
OytlMTVHQAp6OEUzYyM8Yk0xbVZnKFolcmJoX2hEODxnTnBrQUBVWGtnT3ZCUVIrRks2UHZ4VkEz
ZklUWm9AYVAhX2piP1VHKncKemBKWTRjT2ozV3Q5PGpqNztuOz82NXMwN2B4eW1UZkZJajRrdkFQ
fldTU2ZHREYyRDhUJj93VF9VVEokcmllK2RfCnpLZkI1OVJZUjJZPVFXZGtJT2dNdmt8aHMlWEJp
P3ElMWFAPnJmVjFJVEJpZUwyS1Y+X2k7Rz5UaFI8WWZHJnt6dwp6YTh5dEFMZUdKbSktaW8kK2NS
ZSk9aiRHOTJwNU1RaThodnl0dEt0SXN7KmAwU045O3VOcTJROGIpQl8zYVRgWDsKelVGKU5Qd3kq
T345IzBsak1ycmV3USFNSVo7STFFfFg7YlIjamh9NWhaRUg4WHVFMVRCZ2BZZGhzNGFCaWkmWW5s
CnohPENYKHokcygqNlowJEJwOS04ISl3eCswOSpZKnQqPT1RfSVXRkRhODs4Szg8JVRmTHNQXnw+
P3IxP3BJTDlvegp6dk1wTH0kKkVjI1klJG03I21tfVQrdjEhPml1akNueVJqOE0pPDteb2JQJm9x
Kk47R29LS30jcVgrQioqcEJkNHcKeipYJj0pTj5OITgkNypCUHghaFc7PX1DI0hrelYjNSshfkVq
bEVuREM8MkRHIT1pQTIwZ1E2c3A8TyN4M1MtdE1GCnpITCpwcXBxRUNhJnszRE0mTFZNaGdfIUBv
NDZBMElyI2BCQzc4MkFOUmBMNlkhMyR8aiUqMEI9JmJzeUh0QzZKUwp6JGZLMSFMfjhUSWVYZUA7
SnsqRn5kbkIzeVg3ITlOd2I9YD5CaHo2NGYkIUwoTTdJZERtfXg1OG1SRDN9TkFoaiEKel4hSC1O
b1IwVFVwUnFmNFFYLWt5eUp0JFNmal9PJmIjNkU0UlU4T1F4bjB6JHRJdGZFKmNoTH51N3o1N1lr
WFhfCnpfQ2lxKkE3X1V8K3IyOzE/TSVZI092QzgoaXZvemBnMT5fcD5STj9tR099U01wNUhjRHI8
em1pbEdTSDsjb0U/Owp6ZVN2TyQ9OFBfYCQ3ekwhRz5PRFdoUSZ4ZlN8Z2IyeWdpSzZxTn1RSCh5
KDQ8ano/TDl5e3xxcHRGUTM1VEhlX3gKelZaR0t0OUJ4YGRwYHVKOD9WYDNwMitnI0dCa0Rvbkdm
UFEtMEp9OWRGZnpjbXcoamlRbj4reHNNTVlqLWRTKFY8Cnp1NlJURUQzPCojNG9MTlUzYnZtXlVo
KSk8IXE/eld1R1BLQDxEUSZodXZAUEtqa0c+P0V7WklHTSlVfkxnc0F5Rwp6cnBudEwlPTckS0F6
WFVoe202ZjxGITVCbW87QT1ITkRQI2k7TTlSK0VuKjs8dj8remgjMVZPQDVnaVRDPEM3KDEKenhX
Kkc0eUhaPzBqRFIkSGd9Zz8oTi18MkI4fTZLbHomKU9tWWdwcFN0KCFiVVpac3FGITtATWRBR0tl
QSlsb0gjCnpvWmlLYzlqdz1AYn1xQWRVOGJMcik2dHAzJVJpOG5qYCY9PjVrKzZRJiN4Rm81RiFz
dEEjJThKNyQlM1crMylUKwp6I18lOE49WT10SjN3R3tPaU5FTkBqeU1mQ2d9PUEhRihzPG1abUoy
I18wQ0FvM2g0YStDT2RCZ0w7bUYwbm5MWH4Kenk/KSh3PyMock9TSCNtRkVfa3R7Yj5mZFUhOVgo
aSVIekgkNlohMTZ2I2F2PzRLanU2VykqckA0cjQpZ21yVUJ3Cnp2bD96TnVeWndNe1ZQfEUrKE0+
Tk5rXm4mUzZvdHljfHpAR2p+ditLYHdEQXdRPjY+TCpsbnIhUTF3Sm0qNUU0Jgp6ZEJxITlLayVv
VEZmKX09MXBuIURGaFMhdFUtb3xqLXpXUmoxMCRTRSRJSThJKz03NWU/PkJebHZiP0YzSj4kY0YK
elpVMD13Nmt+eiVwWSZpZWYzd1BQb0pkejUzU0RjZlBmTVVnc2JBI29YXjteNjlMfGxyeTVodDg3
Wl4/alp1bDc4CnpGezgtOz12ZEYxbnlfbDJVJVdoKCZsYmgpcSo+U0F1Pl82V1JwSTElP1A+Z1lK
LT5kQ1Ymdk1Oa1ptUWhOdjIxeAp6OzwwTz0mP1NmVmZAYXJXWS0lKk14Myo0cUcpam1yVUUkcWgj
QiNRP2ctfV9RdHBZcGJUTGhNMCV7UCltQ1pYZGcKel9HbVBKYzhMSiQrbGxydzBFYyg/UztNfm1O
Xj9vTXl+Uzs8SW9uVFVsWjU0YkNVWldfLXIxMjRpRzBsdjxgJH5xCnppRCNtOUtndm1RUEJsNyN2
UyppYVRmVU8/Oz5pfWMlfnpYa0I9MCo9dHV8UlQxaGw5YD9uMkJ1T1kycm1fdzd4Qwp6cDc7QHhy
PmdzN15uTHlWS2E+JTNCVEkhTXs3X0cxWkBqbmB8OEZvO0BldyU4Nnsweip3Tysweit8XyQmfERs
LVkKenQ4LVJqU15tUlYoNHVpM1BKTEJ2TGFxN31zTnNncUNLZ0dec081d3dvbjJNOGUrR0AqdEty
QldkMHRrak8kaXEtCnoqZVJjai00SVNMQ3k4M31tM19QYWZYNEJLalpeaVc8e0U4UCEmfDRhdiZ9
PnIkKVlkT05FPmtrWUNsTGdlYG9tZgp6YWpyZjNlKihIezVfSzZnKTN1YWBhPnxxPE9HQ3xvK2h2
TjlxMTUjMEgpWm5Zd1lqLUJJY1EpIVFMYERRQ2dkVXsKek09MCNaOD8kKmZNalUqY0NpMUZDe0Zs
VCNte3pnblp3SjFIOWteZT5fZF97ZjFAbDlPemhRNiReZXVsM3Z5ZXZjCnohaS1gQnc8Z1lSaUU8
U0hmSEVXdlZWVDV+LV9uTXMmd3s1dkJBcHI7I0UrUCFLX0twOUBNPi13ZilTcVkrI0VjLQp6c1Yw
cz9Edj90JjtCNz1uU0lxYiRwWClXVXpYdlVARkt4RWkkUzRaNTRROCRBVW5ySVU7KntBQjdZTWlD
YFZGQWsKenZ1Y29VLSl4WF4hS1ZuckxRZytnPT4wVmwqeDc5e29PWHFqM21Abnp7OGpCbFB2R2JB
cntMfVI8OFZPUlJNcHBOCnp2RmtVY292YX0hTlA0dnN0Nio/SEtMeVhLQ1d1Tnlyal5kT3JNV1Ng
I2xALU1MZnRYPXRPRWdgfEFmWUgrOHBDYgp6KE4qcFh0MT4qQHBrKldMV3ZpNmkqO0p3Y2lHRk0h
RVB9O0VnTkd3PHBULUh2WmN3Xnc/S2JaMUZAUnZieHpDbjQKemJ5U1AmYiRMYkswdTw0MG9xN2ox
XioqKjI/enxsPTFaZDdST1U2VkBBWlF8KUJDNmxlZz4zKXAmb0IpNGlXKi0jCno9STM1JWB8Uyg2
Vnkqell3QV5xbFZMTiNMPU0maU17e3FAUUtCWHFmeUpUOSlkKF5vdlB6cz9ZOHZ6YU9wNWMxdAp6
LUNAVCkwV1FGNmtGbFF7RUJ9XlRiQE9kS0A1eztraW4jb1BZZ2xwWCNLMTBpU1F0I0BvZWoqRjlk
aTRDTnN4JVEKelNgME0kWj1zTEVKPn4xTWNnI3U7NFRUNEAkRylKRk1nOH4yT0FiUGQ7QTNiMGVq
aHM4bUV6MSkhcjd9Sk97Py1SCno/MWd9R09BUUxXUUBPUSlebyk8cWJQdyRtez1uP1llcGA2alhL
O0NDSjx4QitvdWBoMW5OeUJuNml1RkxjUkBZUgp6cDx1IX44ekR+SihROTkjM1A2O2wwJHpWQXsw
XzJuR1E2TnFaQndYcSVrflRjMm51R3hhPiFnKStVIVJSOzNpeVgKenA9VnE/JHxJY1hBc3ZQflVE
QHBQb14tPnpeeCNPPG4rPDFgaH5FfiZeQT49cktSfkt6Wj5sbUA3M0F6JmtacFFyCnpfbG97O1BW
MXZ3alZ4SHhPJCpEOXkkdXIxPClFS1hqd2hSNk9zTXZVTGhpVzsyR159U2pPR0JZTGZuNVM3TSN7
TQp6a2Jad302MWRCfGtZbChuOEtgN3EpOE0rekQ0Skc+am5uLVFFWG8mSDlsdFR5KjdiTz95Kz9A
eEVEUXtHX2VaN2oKekJZeShaeSomMDc2TVNteiVhaStIT2NeVmZNTlcwPW5rbVJCOyEtP21BOHI/
MntLS0oqa19jWDJILV49QzFpWW1+CnpzclYxRFRhPztYX1lLPDwmJSo0JD52OTIlYWpVOCMtMGcw
RnpqZDMwVENlbHFnKno0QUBKZ0xjcDE1flA1NU96SQp6KX5ARCV5P0s3RXokPVBQO14lPGlkKTMt
NDU2dlRVLTNfKypfYiM3QzJ7JkdvV2BSYD1PdHJAZ1ZWYyo0Y2JsKk8KelpZOXsoYnJLcXFXP093
NVBCa1QpbGVzKGROWmlMMWk/amFsIW53UT93eGpDTSgwQ1UyNXlje0BLO1dgTjRQeUYlCno/X3NV
Qj54RzM5OTBBPlJ7OytvSzJ+NklISHxPYENUe05oIVBZM0UmIyNlVTlMWHlHN3Nyej1sUEAzIXt1
O0luegp6O2ZNUGchSFklP09wdk1XPHBjR1F5Y3MzNWp7K29rO1pCNnYmKzMhd1FuPShFOG5galpf
ak9NKUFIMkYteTsrXzcKelVPRiRZUm4oO18rMFBZTFRSUXY7cz40IXFVP341cXkxZ3lVZiUlVFp2
KDluUVlNVjRkPVoxaWVBMzM5LShPdVFxCnohbXZ9bSk5bTlIa147WHY7UCQlJTJsUn1hdTclYk1S
LWM+LXllZHhPPl5sal9xVTwldmQrQHZlYWBKREU2M3haawp6ZVRMNTNLWjQodWR1X1YhYm5oRmok
WjdVcGBGYkppUnFqODdIfGBuKilsdU80Wm9oeGNXZHcyVT55dFFJJFRkSSUKenspX1gwQDhScm88
MlQ2NGpvKXxmazNTVSNJeGAwY0EkIVpYTT51XjJ6Kl96PD99QEprRT9fPT8pTkpzTSt5Qz1UCnpG
UGQ5PipSOFhpeyRPajlHa05SKD5lWW5xamRTQ1p6bTN6SHBGXzFoMG9AdSRaZj8kV0M8b3NURElr
KTVhcjw5egp6MHNCWk02ZS0+VnhZREloYCVAK3lwfUotPXoqTl9OX3QzVl8kTCMrT0FsdSMlR1l9
ZTU8TmlNfUdyN15aRHIhRSQKekt3V3V0RVpKKCVZM3UpcHYrY1hCNkEyaVF2NUV4eFJpM3R4MV82
SH5qckwoRXFKXiRQRVd9MGtkYyU7fnkkUHZ4Cnp5TGhtcmw/X21KZDgqd00tazc+TzRLRiFReT81
enV6MU95cVozbTRneUo7KV8tfF4hZT4+dU5pMVJ8Jj1XWmxjcAp6NSV1Pz0rdSVWVDtxbTghKypX
R09NVTJqN0oqPXRQUjZ5aEoyd1NRNiV1UyRKMWF9QlpzN2VzR1R0QipyYF5mT3MKej5zfFUxd1Rp
RmQoQXE1VHpCZjQ9aUglX3hlP2RLLUR3T1ArVFk5NjV4ZGRydV5ZP0hjN0RJcHpnZlY5cWs7YXUq
CnpsfjxfTFloT1ZIYjtvKHdvWkdsWGNqYzZFYXk5Zy1tRVpTVSF7b2IoKnFzZSR1cDR5QDZrT2NN
YlpsQ0c4KWxFUAp6YWVaWWckbSRWSlk8SkIkYFAmPmdJUyN8WShKfFNPbCQpVihraHU/TUNyUSl5
QURoVSQzOSlPPlc9eV5SQzBae3IKekxDTDZeRzZYYEFKcil3Z2dfRjFDPUlVUCFxbG94KD5IITFn
YzBgaFFFTz1COUZ4KXJYYEAwMSshclJSZSs4aCh2Cnp4YjYrMXNFTXdHT0wrd25wOzdJMSp2SjJX
aj45ZigrX1VjWXdvfF9UaV56NEVNTlFMKmZiajhybFJSI25icyUpTwp6cz9WVWRNNFBWRTkoejF5
ezclKUc5Ty0tLVRBMktMYVdnKiVJTml9cUslTTsyXkF5elJ0JiMpI3p7X0tZVmMqRnwKel5KZ2Ny
UTZrcktZZzxPY1VmKEZ0aU1vM0l5QXZ5d3lGckwjITtaU08rVnxtLWteJi1WMDtHdUdBVW05IWMy
KUlVCno8ekpTK3o2emc5MFlqYmgta2U5c0hLWENqWmVZUCtPSXQ9WVFKYT5PLT9aZVNifVlXXzNQ
YDdRKFR1SWIxTzIwOAp6S2ZSIW1QUSsqY1ltfEBHXj8qY3AtT0pBQSR5OWVZakYrUz9PSTxgMjxN
R1Z5WnZ5bn1idyo0O2dZJERSOUJxfn0Kem4kJl5ETi1MTmJoajhKZWB7djV9R1khPExZPkBwbEo8
dit+P15aM2MxazNzclFHYXxLVkFtZVVnO3JzVyVSdUx1Cno3WGImbyNTRGx9USk0JWE0QjAkJmoo
KkV9JklyPDlxKyFkRndrRGpzIVpqYFUoOzhXdytWKm1TYnEySnhZKHFpZAp6Jjc2eyZZPE1QZjY5
Si1jVnZyTkgoPi1jLS08MFQxdUc3Rjw4I3QxNStLYElsWTQ+fmc9ST1SbVItJjFgdX4qSjUKenJf
fFJSOXM2THZ7UVBZRDMqdVpAQjJmRis4PDVAM3IqIVUlN2skM1JjVzdpUDAyVk9raytBTHlyRH1G
Tk5gaWohCnp3bVl+WXBANU84Rmw9P1kqPSpzcHlvRUskVzMkYk9uRC04STcybCpnMWZvbGZxUCox
SDFpeWYkVTdIb19GWG1xUAp6OVBlMHlNWCZfOz9kfEpJYnNTM0FrITdOKCh8Oz5SRWJyR0A5Ujt9
TD8/TkdTUTk4IUVlJGVWYWxwVjZCaz8pQGsKemNVUEFWR2smJnI4UiNlRWQkKXwzMElFN2EyWWI/
SGVQaVBoYzZ2aXtOPiFwfVZPTTw9Zm11MTNYe3ZScSo3cFJsCnpGelIkSEdqRyk3b0J3TEF2MX1C
aj5+c2EjSDRzWnt3aEghOzxeazBAN0UoaE14UlpUJSRTcHdQPnc5Nks/U0lHawp6QE0wfEglZGUx
bWswKUN1PDQ5YW0ka2h7NjwlNmp8MGFzV1YyYGkoKlVYSkkyRjImbm4rcl4zRSMoNyVEMGcyYlcK
eiNGKWswVVlNcFQkKSRjSVpfe2swK2EzeiFMQ29VITVjY3ZCYFQ+Kjd2T3xiRmcyc3BzXmFuQWJV
Zj5sZ2t9JVdjCno/NVZiVzw2R3Y2dVgzfmRBek4jfVVhYX49OFJKZzI0TVlMK1N3eDt4PFdKfTVI
XilEQkRqPVFjdWspTXlPRWYrNwp6Sn1lUVN2T0V2UW81cEo2UHo5Rk4lMkh0aHtgczt9QiYpfWEm
ZTk2dGU3Ri1jKE0+ckBfSElHRDJmcDJ1e2BqVyEKelZuSFIoYD14Ml5zfHw4RnBEV2pKbUstVV9H
U3hvUzRDRW59VighREAxWj1NOWhWRXJONT19XjJEKkZJZ0lTcW8lCnpFM0pCaW9QQXBDPisqdWE+
Tj9FdzdpXzVMaiV9YSFoelc/QCMhUUFqI1FPb3VxZTNPQkI7JTNsTkJZKm0pbCE8Pgp6KCEwMEJF
bG1iKlIzZ311N1lnSnFHPylneDgpclohd1NhfEV1LTJYRGVfK1dicFZFK01qJElUYE0jQzwrOElg
fXoKeklORD90eGtNQDx6S2w5ZVAjRGh8ZSVafG04bEt5QEF8dGJUN1hTPH5wYVBNfmF+bzUxaCtS
Vm5tTS1mMHt0R0pVCnopczNzMU1ePm58MyREPnIjZTs0aU49cWVtMHEpTDlTeFJrM2R5ZyhEJHBV
KCghaEFSfk9FOEgtSDhXPnlTdmcyUgp6QmdURH5KNVZmPWZrfVZEJTxmJkBAezY7YiFkVDVWPilh
JC0hZVJqTDlHS0VDNlpZOyFwfD17eFMqWDswZ345JHkKejQleDUkQ3ozUVBASmlnMy0qPSlQZHE+
PjBkZC1PUWRQT1luKF4oVXgwJnVVcHhkNXhBQmJHZmBpYmtaVjRmMzdZCnpyfnpicHFKS2tpIyE8
ODZTSUpYUitxNjBwWmxKPHd3b3xNfTkhcDlmbzQ4WnEhZ3swX1k8KTI3RzJWNWl3Vj56bgp6bnNu
b0xLVGdnMkM4fWIhRX1KU0k0Uiltb0kpOHs0d0xMUU5tUSg/aGR7VHB+K3hTZytSSFFNYmZobjtV
U14td04KelZ4ZFpqWF5TVnVqNmE7Jk1hPkt8Vj5qMVRwIXx9akR2dzU/aSVvbEg5c3cwRSFPXmpn
ayhna2RMUXx4WiFHemBnCnp0XzNxbFItSilkPSRiQ3RmOGNwcT1vKWk7aT0ydnU1Py1sSVl+S2Bz
Mkx5TF8+KmshQzNVNWxye1l0PGArMT8tIQp6bH00e0diZ3x2U29XbnhhXkA0bHtsSCZ9OG9PXjNW
eV9YOS0tPGhUJE9qY2FUPTBOMWhvdHhjKlV6JW5TcVVURk4KekM4Z1J6fDF3MmIkfSE8MSFwNlpG
M29ET2lNK3smdVFlKldPdHNQJXk1P3s2fDZOWGFlMEJLZUwkPE4ofmleYWRqCnpea1lzQFI+dGwt
Qj4tQztOREM/SiRrJlZ4ZVEwUXlXbyZZKng/dGQkdkoxYCEjTXRwPChPYEc8Rm5ZIX02IWdDSwp6
RkV+WVE2fDg+Rj1PN2M3Kyl7eSQxcDc/M0BiJEBvYHxkZWFYO2lhQnRxOz4pbSkpPlJudiU0QTlA
Q0J9OWBednUKenk4UUt+JD4hNXxWfXd9cyp2ZG1JbjlyXktDVDlIYzQhMERJWVBfMUFvenZvKndI
YjNnbXNDbTAzVTZ9Sik2fEdtCnp5Vj8yM1dAbGcwV3R5RXlzUUs8TFljOzF4ZkpTZGUzQChRRWJ+
TzByQVN0aGxIam51IXp9NTZea21FcWs2TjwrZwp6UVN8PU5JRzI0SClWUGgwSEBBaHtWKnYlKit0
RCp0QkJQell1PldkTiUmRikxeXtgNTAjdnR2UC1mTl9+czI+cV4Kekw0eVQ2UUkzeGVNPiY/el9E
RW4mSFY1XzBxIUM+MlR6aEEoVztjWiFpcEk9O2JVTXM0MkgrbHEldVMmej5KbHFaCno5JSF3KjQk
T3hXQCUraDhUX0Z5SSRDR3MpQUNjYmp3QTxaalF4bH5GWjBQcDBkQzk7VXI2dmw+Y01YLV5gN1BR
Iwp6PjFfK0xITDk+bTB9Z1lvTWkwWTBySmJKbWJmb34raDRMPkIkI3ExT15NcGI5KFNGUDZzZXFP
Z2d6YDgrSHQqcjYKenVfNzNQeHcqKHVSWjJmI3RKKzQ1JlBxT0kwIW5zPWxoNWpXKz9AfHZ1KEhr
I2JYdkpAVD54d3ZaNj9QfDRiOF9qCnpUdjVVNCMrPElUSkxJJEE1NX53Z2c4ak9XPXFJYHpTKlJH
e0t5U1lGaTFKWmg3QnhTYnAycGlid08oO0Y8TT1ecAp6LU9nKzI/LVJQUG89djR0OS0wYWYpcThM
Kk5yRCZNb3hPcEh7eXNmJG1gU0tPSXtmUUcqVTVvaDhkZjVjPSheVUEKejxJeGVsbGp+VHQ9ejdB
U2NWXlYjOyh3RCMwPE17WVc9Q15Fc1kqVkI/VjhmVTtkZSZ8PE4kQm97Um9IandIRmpjCnpsazZx
ZWRnNUVtb25oZHViQHlzKl9NeTdkSDBsIyhNI2pwRitySTxzRWpXMSUwc00mPGFsSzlqRGg3JTtp
YjFGYAp6JlhtT0txZHthXzFsSlNnLXxWeEhMezdQSEdiOUJzaz04byk8SyV0fEYxZ1g+eXNnJlQr
ITRpNkxTenp1e15uSDUKejMhdkheYXB+QTZAP2l0NmNtNT83LXVNSmA+USgkMzlDanp4KkQ5TGtP
MlZjRHAkZSVRNjE7cWg3RilqNklXfXluCnpxQWxyQVd8ckBLXnswYl9BJHo5VGZrViRnQnJ2NS1f
bTEjS0Eyc3A2NDheUi0wc0hMUilRZFJVbEhmX3xaWT5oKAp6WXgjKj5IX3JXOUdRREpHbHgoVEcj
fTBxVk92JlkwPE8jKEgrVD98WihaPTxWWWxUX3xhMUA9ZT1PeGhnUzl1NkgKelgqVnEhMTJKVmV4
Z3slWE1tZG1kKmwmNGo3fVYkZCsjTjBXWV40ciQ5d09VMy0mVGtIXll0KnR1c3QmLV92TzV2Cnpr
N1B7bz0/aEBmNmBkPFkpMjYhaFl5a2lwSDspU31yKW5mcmVzeF5uQzhULTRGbzNsRCs3SkEobTNz
YkM2VFNWSAp6Kz08U1BufiR+Pz0wcHJtWllBYkwlfF82cns2dldKNWxYYDtFJjFqbmRQamsrSkZI
fHRPPiEqYldhS3Rabl5qPWYKektveyMpQkV7UXU7PkI9KlgjSH53X2dTfUQ7NVlTdWYlPF9NRnJI
YyRHKE5DO3dGdjBlR0xQb2xIUEprIVcxZ2NrCnp6LSNWJnhVNW1GRHloXzByYzZDXz17NmJxYjBj
YkkoOXwmVzIqR2VlcXhPTkBWWWgqQzAkYl9iWD1nKUgzUmNKfgp6eClrZ2xiezJQOTxiVXlDPCZy
JHVFeFZmcz99dTZ6N0w2cH5zPkpoSG5qa0s3S1ExbU1hcXY9LVJgeVZ1b3BRN3EKekQyKzExOXFR
NSp0MChGXyt8QXR2T3JFfHhDeWFgVWwtX0ltalAoalpkQnQ2Zis2SzEmbyleRnJscXtVc0NDQnV4
CnpNTHo0WXRVa1dOPi00QythMT9vSG07ZXBkR0x4NFRXfExpMEomPlptOGJEcEVTNGZfXnorbjQj
eDI4NGtvPVNMPgp6eUwxMy1WQmcmaiVRYk08YWxNcSpxRkhDXlkhbjZMcUtRVzQxVExtVlo/JlpT
QT1YWTFCcTB1ZHFYUmNFNkZuNEAKenZSTm1CPF5CZUJ0d1hyajEjTiFyWE9tJGd7cTlzSjBEe3wh
YU9sUip2Zm9USVltaG0kZHN3JTlNWHVwPm8tekclCnpeZTBOfklIaWY0QG0+Yj9VOXFtV3c+USRR
d15uczxiIVEkWj1HY2REJHs7cnBhPjZ6M0ZWeWVxZz5zQFZqUCEldAp6blJAfko3UC0xMyhmdjI8
OFNEKD89JXBsYmJIYT8+THFmOz5scU0+JXtRSEdCU0ElVk16cS0rRGI+K2c9KWdtTloKeiQ8SGVv
Zk5Ic3hidGI7ZUx4VFZpZXxMUlQrMj1iKmt6Nn5CT097X2BZXkQ7OTdFQFFSeV9YLT95QGxWQUJz
UkVBCnphQWpHWWR9ZFEhVDM2YHA1cVA4YWo5R3VGOUNpWUVPdjF3RnZgUjYqKihIJDBVP0lfJWBT
KTR1R1puVFE/eUBPcQp6ZGZJOFFKTCVkN3g7Nz1PXiE4TGpNSn1IK2R2OG9YIVdqSl5FI0lRWXdQ
WXJmXjx1MGwmXnwxNWppITljWjZnOTwKekIoVmtjNmxkZSEqcUk8NXliVGJ0OGF8JTgmZH0+OGFr
V1J3Kzd8QDFiKz9PY1gwfEtgZjIyUVhhWHgxX2tsciFRCnpGejJxVjkzXjdEVCVZJGx3R0RIdmtP
LTFSKmBnRHthZVpmQVdseGZkd3tmZiVJNmVrTjZke3EtdkFyazt4TXUpOQp6aUBtR0RXJHpNc0lH
NDRpLW10U2B1IWo+ZEZWQUc1NXxsZ2kpZjFTS0hpa1ReUSkzfnReb0lvX1F0Jk9CZCtETjUKej4k
S3xAXjwxX1NqY00/S3sjanNjaVhiNXB0cUhnMUw/RzBQdHN5dGI8Y0J5S2FWRk59cmtrP0JXdShh
OWVaRCl1CnoqbGNxYnlDbjV8YjJKLVZRXl96KSVKKnRNSk5gekN6UDB2TylhIz5Va2BWMkwhTVJR
N3JVJkdoPG0yPDFfMHIlagp6NE4yRHpAblolTkRtYXN7VzctI1RBMjxScUcrTSROc0xLSTBlVVRo
cXRzN297OWM0QjAxQ0JydWdpRDU4RT44Xy0KelIyYmAtV1RJXjEhUTt4SSVwNm4zOzxGZG0zT3hO
dilhNjEtSjZeais2UlJvXzBOfVBVPndIQDhad3dUdTNKTXRmCnpGU0daYT15XkcjZX1aJjUyPHhL
ZDN2Iyg+KW0lP3FEYkRZTjRAeEFpcD5VQHhoWUJ2NTJ4cnRQTDUpVkUrRDxLeAp6aDN1eDtPdCsz
KiV7eGVTbF49QzF4I2VNdyhIayhWQjw2eEMqU3dyZF5xdWBvM2gqWkVqS0x1TTNhPjRyMHZpOzkK
elRjX0ZSdCZ6Wk4qWHlBO21UfktPMjE8e348e1YtKnNgdjNAM1Q/LSQ5b307SmlTZkUjWHdOe3lx
aWUlWWBrNkQqCnpBMWNBQiUmWVgrKiQ3VHBrTUBQNVhtd1FYbXtVUHNzJkRkPDF3LUcwKlUxZ084
VmlOc0dFPjtBdkt0LWw9SDNJQwp6a29eMkIoRyU0JWBUVyVIYWZFYXdEaFBnMF9UbiNLKT00OE04
WUkkbm1UYEwtc1hAQm9tKWh4PjxONWFBK2khMEYKel5WXyQtN3ZEQDh8TXRoUFlMVVhxdHdCRmt5
cC1IMXNpfj02PVQoTW9ES1dQaUEzZFNAZUJZNipae0ZOfT4tcGRoCnotQW50RXBNSU5Pb0QkJTVt
UUdocnhfNCVLI3ZpSX0+V003fDJIcCs0Nyo7KTdzM14oY1BRXzRVTFdiV2NNUk56NQp6QDF3MkR6
UVRuYzM4JSRWYU0lV0JaT0FsTWtzSFh5RClMMTBBTCo5S0VxYk0wczZoPnl7YTshQFVSU3RpRCh+
SGYKelN4REw7KmhNd2lDQ3FPcXllTH13aSUmWDs4JEkhP2JOSmx9T3FueCZJelIhV2U7RmZxMyYl
WmV0KkQ/UUIwNj96CnpAIUAtKTt1NVBQNSpBPmotaWdlKWd7LXJvKGV8MDZxWDFucFdWbXBkeWo1
aUIoN2U4d2hDYUJCeCM3ME96SVd4VAp6P2t7WEJBZFBCN2FQTnJxPSgzQl9hRnlCOzRHRzs5Mjsw
MHViRiMxXiZvcUI2IXF0fGdlSnIrYiZHdnt5dmNnWlQKekR4b2N8Nj4lQ0xLNjR0SzA5VEBBIWU3
SEghOCtlPHtiOTdBZFJiMl8/VmtLWntvJUYtMXN1VT1HfkdiS0B6KG1vCnpYQXcwNHl+LTJeJnwm
IzhUOyt3XkVZZUcmNjZTe3k9NC1iKmxTfmQ/YWRmWmA1c2hFPHExRCs/R2UrTVVDSTtMewp6KiV6
UTs2ZG50RE8te3AhSilHTF8mX0M2eHZgZkE+N3h7M0kqWS1aTi1ybkEhK09kVUJlWVNvbygzJFdj
WXYyfHUKenVSM0Z9QyVlV3tYal52QG52dyZqeVQhMXplcUglJWdEMEVGYGN2aGszND1HS2opSzdm
XjxneEYtQT5ockFjZE9rCnp1UE4+anJPdW9SYlJ9R1M1MyVid2UyKGQhKmpHdFhsTzAlVnwzdCNl
a0NiPnIkfktPJD04KlBqblQyJn5EO1ZfYQp6PGI3R3JKeWo5Km5JbjMpZD0+PTg8REBmSSZpYkFu
eDQxPlliViFJYCppZWZPaDQjO3lNQFQhMU9ZQTZfcX05Pz0Kem8zaT1MKW5ab2FnbF9lbWdLSmpp
KXo9THFMeUh+Xy0yJD1NPkE8M15KO35JOXRJNj84T0ZsKGMtIX1BUSZRUC18CnpPWTN6UFA2bUoq
PkslcGFzbH5WYitVQlZ4SzhjN2R6PXVPb0BIfThmbkZudHMjdiMtfHBYR01nPzlrJmtAUUZJfgp6
XmFCaEs9O18hVyg1ZU9je1E3U3ctOWV3ey1APzJCcDNXYkpWO1ZmJntyU0h+fDdTcVJPOD9qcHZj
ZjtHZnZ4YVEKenEtPmYmPUR+bEghKH1wQTdXfiRvVH02KSgtYTBScCUrVj5oZm51akQ/Xkh5Skgk
SzcobFVPfXlHPGtRKyoqbFpaCnpTTGNWMStTdTZtX30pbSQraDxkN14jbURTKHl4Q0ZTSXV0b3ZV
RmswISg5cUJfQU9VV3Z7fmZpdDJ6YmBYLThVWAp6KT13IUtoXnU8RiE8USNaKjBxb2xZZ1YwKjwt
JWs1cD10RnoqM35NfU0tN0NYblZESmcpVCViRUg4MGhNWXxNO3sKektXSzI0RUAtWXpSPyt0QVl+
ODBVYVpnTGtJZH02blErfWZLLU1Gfk92OD9PTSQyaGRLcyg+Z0ZFTzE/VihQU09RCnopNUIoKmg3
THtJZyV0SCRwUG1sfVJPOVNCQDtjTWNYIUZMUj58KEBPYmtCaDsrR0gjJSRmSVQyJnIjWjlPQThW
Mgp6OGYwPUVWe1lhckxROGxheXpSR3M8LVk4bXcpZTclYkBuWmJeWSpXSD9UWTVgWDt7K34mR2JK
RDNrI1BAcXNBQjMKeko0UG9zMTllTHBENX1eI2V9K05XMiVxVzc4R1k/ez0tZ2BLPmNTd1pCUUVW
LWI1fil9IW8tVEgjKk0xKntEaEAoCnpeNUFZZHFyIyhrcnRUNFFkYXRyezZ1WjhJS3BVajJ0bVRs
Smk2fj16cUAqWFVIe1h1RVI5YUEwTTYrUERGa2hgTwp6d0M4QGVGa21jZGxkdXdqZlJyTyl0NV50
bFkpV3FuQExhaE5QTT0lZi1FODBHNkJzITBuZEd7PyhkXjtRSFhjUE4Keks2Q35mLWNtIXhNUFVO
VDt1Xz1pNEcqWEtOU255alNeV0ZedX5XUDl2b3A4dlJlT2M9a1k/V3p0ej84cXdpMTA9CnphdWA4
bylYUHw8bX04aVVRMTZ6N2lGKURHcjwrWUAhI2R4c0V7IzRGMnc0MWwrPWVIcUtkaSZDT3labD8j
VFZvegp6d2hjLWRlc2NwUSZNbXM3XntmJE4xQyQleU8lTVYjMHhtZmx4SHkhSlVOP319al9tOXAj
bEUmbW5ASz45Y2ZZUS0KeiYkbyRrOFUpcGxJfWU4QkhfSThjWHVZYG9UOUZAViZQWWNCOF9PTTRU
KjBnKWY4O21IbWJGJlJqVjljO2tJXz5sCnpoP3NVV0NnNUpaR1U/QGxhJj9gNGBXZHZCV0xqSEY+
UitGemtENHh8QSlpXnVTejlKIXJePSo7YHFzcTVhY1BTaQp6SmBDSygyUmh+aG8kYmFRJDlfP2tt
QFh8WDxxUX4kVEFQU1Y+IVpRYmElSnR5cFBTSUA4UXlHO05vVndMZnVgI2kKelclQEomTzU5dXJI
VmJecTQ1N3RUYjNgV2FxMXJIS2IjX1lNXzEqWX11cjczQWZaMmlNMmRoemhnN0p+XzEldG5KCnpq
dSNSbVR1VjJXV3dsV2didD12O2BDRk9EQCtPOHJmMVMze3FMYC1RUlBFfl5uWEBPMW9SQ049aC1s
YF9lM2A0NQp6NkFMeUdvP25NXmApRlNvbDJYVWBWckFxZT9LaFZpY0JFPTdhOH52cElHMThYMnQ+
cF93TlkrV09ec0szeXVHMVkKenFKbUxhWXxCblhMIUpKOVhVUW9YbU5uK0BKR0AjKjE8fkV1dXZ3
VTlPe0A+cHpJSDZiVE9gWFdyOVVJSDh2T0xfCnpzPVNAK0pTfCNpQCR2Q1NFPVVLNXt1Uz0/cFlG
Um8lWWJ5eyFTI2ZIWnlVcG93WlJ1MEE3blJNdG5jMm5ZbkxMVAp6ajl3bFN5QzcjO1VDdWE0aCpi
PX0pTWR5bWJfQFdrUkdEP2ZQNFBwPGY/QzJ2I3ZVX1UkVSh7Vk8keFJLKWVJKHwKeiVWZ2dYN2Rq
TGY7dE5YKTMpP1hiezNZeDw1fFA0NEd8fihXNEp7a1YyMUVRPTV7QjZXejhnQypxY29KJj56OzxE
CnpQYFpTTVZ6ejYhUlgyc01nfDdLNV44UlckcG1ue1JAdG1rZHA4WUU+U20yWTdzY1FnXkIhIUcy
ViYrcWJhfU8xSQp6WWY8ISZnI25FOyhNTUl7bCRLX2pVflBkcnhqMzkqQjc4ckZTZCl5UT5HZSpQ
VWVwZGVfdGxFfWJoa2xiaHxrZz0KeislQnFwOTZvWSo1YlZaR1I7JFZZVikpX3RpeCtsajE4Y00w
eHFpJXIoYzBkSFlOe1Y1R091VW5xMD5LbHZeLWV+CnpjU1J4ekA5KWNjZkI2SGc5bm13RHorU0VB
bUt2ZXlWamdCTCtzPjVsKitwNlktR3hzKWlUPCkoSjthfHFUPFA2Ugp6Mj4lV0dIXkgwVy1Sak1Z
Q3IlR0lxWDd5I01PJH0tQHMmdVMzI2twYlJxe0FLXlB1dVVmUXhje240UH00KUFYbDgKeiYpOFU5
UT5lQ0EqSjJPZj9VM311R3NfbENLZFlrKSE0X3JYQ2lxJUpGVGl3TSR3XjZZZXdQc2RVPiFkSSlw
ZSF9CnpwX2lnPSheWmg0byV9Z2c4OXpUUzdiQ20ySHFPbjlvQX5uKSkzeV8kKitBbDJzX1h4WlFv
bGpnMjFPbG10VEUpKwp6Xkl3XkFpOFFiN0ZCaSYmX301QnFec2teRDkyXjl6Ykc8JGFUREpvTnNF
WT1CWDNQZyYpQk1XRmRJMTNlPFBmflAKemNEe0ZXPWJTfHsyK211NXQoT2decnxnNWZoTTZKODVv
N2dISmR4MGBBK3RAK0hRaXRqYiRISjJ6YXNCN2JvWE91CnpeUkI0PkVrPCpeUG9QXkc3KCYlel9r
ckw+UXt9cztoVXBwWEdAVVp5R24lUGVSMmVlJjc2U2Nhdzt+WEVFUHxtZgp6Jm5fcGtzQTJWXmJA
dTVxaj90Z24wV0U2Kj9DQEtXKEpFO1QhWEMlZk9iQmQwJHBHV0pYTCpeTkpESEVpU3woNHUKeiR4
VWMpTjtJeV5RWGk/dWB9d3ZuOGRQRkJzIWAmUEI/VXtAdmRXTytZTHp4MClIeiolUzA1anJWR1Mt
QXJKUHdmCnp1PnY7VVdZI2I2I3hja2luJXY/Zjg1T1pNOXg8MiRRbCYpPVIoLWtnLVdDaU9TXyZe
ZGBqPFFTcytsN1pUKyMqeAp6MjJ8UkJPRVF6cG01NS08KzdlZj9vPEBuNUBkYFBESjJRUmBZemZP
bW9xITdleTgkPWVkUm1rY2cyOERKaURVPlQKemkoSzxXTz1aT0dQWWJ+VjhRJTNiNykkN2pOKWV2
KDMtYyl8M1ZReVI/Q3BDNDtpREltJjgxXmxedD8zWWdqTVAoCnppe3ZLPDROZjI9LVBPWjVzVGoj
ZzJaPTNQZjJCXnVOaEw3ZjFUb3k9JmhSV182fm5HS2E3KTtwaXxHfGNFfjgqQgp6NWR8aitYPDBD
MEgpc1JqbWQlN2krUHdDfkBXOGlCOVg4RGM4dzQ7aDQhOWxnYlg/amdSP21uLShZNUp1Y0M9bTAK
ejlWKU12UWh7XkJ0KTN3PU9YPF9IMipKJWozUy1eYWwoJGxSYCRtIyF3N15wOz1GdVFxI0EoKUBf
UENmQlZOamRXCnpLXkhiP1p0VmlMbT54aW0zRXF9Z2xkbjJCT3BvYz93aH5kPFBoKnVNJkxQTXYm
REo/I0lER2dRbylnamM3Qz5YcAp6ZCpQbjBwY1h8IWhnS0FGeDU/QCE2JD9LPHpsSjswYSQkM3N2
UCQ4PG5sNE5CZk19b0JFa2FYeVd5N3gqZkNBLTAKem5ETXNHYHUxNVIlWCVYfE9Aa1k/bUNWakFl
dWAjbVpObXhgdmVgSHBMbkNXT2RyeVNVODZpM0V3KGdMZERKOFI2CnpvS1V3IzI5OF55U3dmeT4q
MFFSPCtXMkBlez9OMF9ONm5ZK2o1byhDcGcrY3p3Jm9fOSlMMER+Z2JiQzcjUHNOdwp6Uig/I2E+
K29edjtzZmx6cHp7JTxzXngrUThGd2EjezZeNWNZT2MzTjchbnYyNzNJfkhuVXNpSyVyIyZYWW84
NGUKelIxSnByKVZHTkVUPWU/fkRjc2p1eFpgYGVWb3JtNkh0SV9EcUs9NGAlQExoKi1aQEZtRiUz
TGY2ZDJkZCM5Xkd3CnpEX21xOTIwc2p1YiN6d1NXLXNTemdRYHdQTjVAa3ZTYz9lYmJCeGIxLXhv
Vm9oRzd6RzlwP3dqa1BucSghZ3JyQAp6emE2PFl8Nz9BSXo0ISs0RUxYMFIjd0s5VG1Yd3JgcWFZ
fTZSKTYzRGwtSFhvej5oRyMhUEVjcVl0bXttYm5pPlgKeiVeNClIR2U7OC1CIXc7dlBNYWdkRTd5
ZHYlMzxOUWluIXE5RE9tKGpQZUN0bWNGNTdlO2FOcCleVkE8NjNEb0VKCnolQilWYl4tT21Kdi1e
YWMqfEM8SWg8ZHo5PGprdTUjTUFGJG02SU50PyglVj9YUkc1eShKfDR5OU4tdDV7QXpWWQp6Z3NK
JiUjRjRudlEqQnpmWHleUUJ2KUctfktlVENHUjcjejAyZExVcjNfP1kxMkNJYGRgRHxzXiU1azl5
XkdSanoKelEwPHcpQGxTbFdxTXs7bj1ldH5WLSV5YWVqe0MyTFNEdH1OLXMkYilvT1I5XzRWcDJ6
dUdpKTBMKipwNDNtNTV9CnpCZmIwSEVTVGtsPkl8VXA5Un5FdXM5OVI/P3ZOe3VRSj1xREFkMi1k
e3VyRVZaSitgRmtDZH1zZVkyfHpxdkAlcwp6QGZvJTVIKDg/Ym9TZDErbTdVJVZwSTNLSXBybjJN
e29WbStebk1NZUtZYyhoPXVaQTxsbnBBQXlQTWxDIXRAdHIKenlJVWBOR148KiRhYGJkfSRaMEhB
TnVTdTtiLWVsUnM2RkAtUSlONThrR1Zgflg9I157ZyFqP0ZZcGdxQlk2V2NZCnpSdGNmRVhVcjRZ
V2hjLVBHMkJyeUN4cmtPOHBNWi1oO3hvRWVKYG5nO0N+dWVmJk8yQmJ4QkIzTnJ6WkZaLSR1WAp6
LUNLdEFYallFOysxQiopRTk/QDJrYCVGSGhIfF4rZytiKXZXcUpLYnt+MlJMYipuVXVnYHZVUDds
K0xnTy1eN1cKekVTOEclKlVMWWQ/ZGcyaT9TYlVQPkBmPHp6SE5fRV9Tb2BZSEEqSXRReWZmI2V5
a0dxbDJWcDEre15nJSQmd097CnpJcjxReTx4cHJ5bXd+dCMlaiQ1dil6K2hgKXd2ZVNUVElrbDlY
PmwpPDx3aFE2QV9SZi1RVjkyJjY8aTNgbk0zbgp6VWNJbjBEfUE+cGp1PnpKRFo+eVE+NG5mUzB5
KG0rIWR4KlcjckU3YHk3O3FoaEpvOzIha1VNOWR7PmxhajNlSHUKeiFNSms5X358WiVMR1NhQHBY
OCZiVz53JkdoeEllPyFwIXV8Pih7emdzaFZ4dVRNcDVXJWtidkwpcElYQz4xNWItCnpRal5TfCUh
WUktKDJVaHZvKXtTLUdCXmw2bUNhJWUjUnlUWCk+bWo2NEZJZEh3KiVqMFYkWmdFSkFIaGhMbykm
Ywp6WTdKOCVpZVQ1PHpFQTVBbnB3dGlPdjQ+WmJMRXNgMT9ARGlhWTNrN1d7Syo7S3Z+REQ/YVhO
ZnNXYGBSVEIwUkUKejtfJnhsbUN9blM7PFhhSWkpN0E1LSV9SyUmZ3pNOUVXTUZ8cVJieHU5NV95
end2dXVsN19TYUJAI29fOHtpVGdeCnojTUxEXnBwPUIpZ1R1Yj1XelZFaE5FJklCZz9pJEtveiZR
aDtGUzhCPUtxTXtvZkNFcT9fNjtOeHpYPDY7fWZ1Uwp6OVRjKzktMENCamRaSXlTbWgoN0Bqb0A0
T013bit1dHVSOzQ4NXhuMiY/Z3lnSVJBbFNhUG8+ekFOMmB7YzglXmIKelR6Z2BDaFRVZW4haSYo
Q2F0NGVtdUBQTSszLUpZb2dfZztPcUU7KjliPyYmd01FM3FeM3ZTP0tXQFZ3NWJ8R3ZECno2VmJ1
I2tKTGopWUtpcUd3RykhS0MtTWVydjQ9dWhQbG5XTG9tOy1VTUxWby1SeTVCLXFQUU1LcW9iby12
WERLOwp6Ki1Je2FnXiYtc3t0IT9FPm03SHsqKDc3VVhDI3gyPFRkczZeLVY0SShpVnAjcTxkUWBM
eHl7RXokTFktQyFYbygKej5yPlJ3cGNYQT4haSVOIyVhdlg8JUspMno8fGx7N0UwI1daQit+amFk
YW8yelZRdl5MSn5pdmZIUnBCNFlgaFBeCno3dURDQlI0UWtyTmFEcW4oaW93dCNsYHFAWFA7VEJx
THVLS1IxYlZPaHYhN09YPzhLOzBJfE9UdkpsNmNLJUlLVAp6V1h+QEo0N01Ja3V1a3BfcFMtNzdq
OXJSOVNhR1hIUihXSnlJOTMmV1ZMemgmOVlaUEViQ0AkTkFHR25HQ3JTbjwKemB1aW9GQWdxVDVg
VHhFUnFDMnxwVkxaNTBXbWJ2KVFxa2YpdXFZZSs+Q15xUTtTQDJiRDVCTUsmN2FJeWdgSD5JCnpS
azclT3lsPlJkQSRmfEptIzVPIUQxbyRveUt8T35ARWEle29eUmA4SXNvbFVabnJsfCNJKy1YNkJC
cF5UbzhIIQp6eTwmdShgdEIlYW1mPyZqQVF4PzBNVTk8aEtsVX5YQ0BVKG0wXjFaVjMpRnhCPWpk
MFFlOTV8VWpVbSN0bWdJUCsKejx8fHghaTRXTmlzX0g7QVRMUTFeUnJ8TH5NVD4kdXNjWUlhJDRh
WE0yd2khbitkZXx7czcwSWMtcFEjVlNWKytWCnpfLVRqRjB+VldEUypFKG07azBSPSsxe3NuNkhR
RWE7QlAjZ3JrUTRpTkNmbzBmeHp2I1N6dCg+aS10eTR2V2wqKgp6R3lkbjIob3plbmp2NUI0PHhF
TFFqX0wxJGs0bzZ2VmZZKU90Nz9SKDc+Rl8pUTlpTjB6Qk1qb0NtZUVXRDUwRkoKejtHUHdSa3NF
enxWTmBwMUFqe0NyNSZSdHZ0MEFoXmtwQkdNZWVqYUpwN1krQmRkKWNucS1DJU80OFR6SDVfbDBF
CnpZfG9ZNklQVG1ATGBxT0AlTTVUe1haaWl6VUhAcntfNUwhdm1zN3RHXlZGJTVTRXJyPlI8aHgx
YUglNktDKSR9Tgp6SVRTZmd6dU1jKDlMaHghakBPUjhxbFdxb21mOXJtOUJTPyooSDVrIWBGe3xR
cWhuKilXXyNwUUw3ZlFEN0AoeTYKenl5OHNKVkRhIXcxTmJYayFnIT1UVUBhfjVZSUBMYy0mXnJV
b3AkRDZ7VChlcEo0LV9udTJFcGVJQnowbFdNbCs4Cnp3TUJWaXJsTTlubFRjRWxYbl80LXlMRk84
QjRKbTAzR0F2UkJ4UXFXVDxgQSM/TGZgWCYrRHhGU0Aod0Z6Z0dIbQp6P25oOD80M2BJKXdiYmxW
KDRUM1R2cSNmYzNvTWR2JUlAaFBZYz1TZ2EyPHJ7cSEjNmZ3bVY/bWMteyRYQEdWJDkKem5pZ0x2
QFNOfFFHdklaaXVRPU9oV21KTUpHJW17RHBMZUJUPmdvTzY2RDtDR01lTG0kJmQheXliRSsxfTVq
JlhxCnpIOHB4NXFtSXVBbnElVlVNbkNDdTwrfHVCMUxkZ1MwK3BvVkZfK1Z5TUc1TTAka0s9JWAm
Qkc8QUJ5fW5mOWQ0NAp6KCQ8JSVhYz8pfks5O3FIKjVtezNNfll8cWIwb1NZVzhYKX44Q1R6YFMq
b1h2bFJgVzAkP2x+N2p1NHNGY3VXNGAKejZTPWpSKlhEXz1WYm11eypAZyozUkxzcllyeSFtVTF3
a1Bvdj8hIzchUXR8bzQ4NmYobStHXjdPYXlsbGowOGhGCnpoakdpLWduSk9IPHhkV3RJbUBHXlhR
bT5JMyEqP2U/NSFiY3FeUlF3XlliTkFRTVUyUT88I0Y1SGtxbCk2Yl9mQAp6ZHcqKVlYUnRFRnpe
bzZ7JXpaWGpaZmtjcWlEcVM+dFBfPD8rPiszJkNqZCZ1Pm1TQiFyRmgpV24xTzhCVWZ9UlkKei1n
Y0x3VUIlYTBATXdZNFR6OVRIdEFTVW1JT14rSEJtTjhzY0hLSTtzd1A0SlVHNn1fN2VXXnFQLUhu
JEIwPldOCnooPE5GJioybkBiSWFGYlFkN214ciRpQ0NMMCt9PmtlMzFKdiNrTVBvOV57bVk7UThs
YGFzSTswPXokMmdMKURvYwp6MT1TNmt5bE5zSndwPFEmOThiI2JHQzlWXjNSTWtRdm1VXzxPQjcm
aEUlQXE/emJAPzE3SmRlTU8yTTZhSlYhQEkKej00XiN8eiM0bVVPUmV+YWZZRiY2KGNxcWpFWXMq
bkNkemFwMzdRIXE/fUd4SnNrYHJHMGwjKXhDU1FGa1JgKkEwCnpmRGVCbmx1bTI+WTc2SWMyamJ+
Pk9eS0otWnVReV9Qby1NTy0yI3p3bVRAbTVnYTRBZkNmPDxwWikrTih1SXhyRQp6K1YjfUZLeUJO
NztBeVgmc2N3RmI9OzVpRCRlPmdjWmxfPDJHSH5YaVh+UHoxJClAUjQ5cUNYaW41UnJAcS1lSH0K
eihncGJpMXB2NnYmUTBfRSUzIWdMeTx4T2dLPU4yOWpyfSV+SSUxNnZ8MCRvez8rTyslclRtcFdY
bkt7OTlJflc8CnppJE1kTCZqR1BsdmZlKjFGZil6fG4hN2ZkUHRDP2xDRWI0bztNcnxreCMpZ0pE
Ujk1clF2YDA1NUV9ViYjQnx7Xgp6QjBtajVEYE4+bCk0Wlp5bn1+KlRgUiMqSjZCSXQ9YSVuaENY
akRfP093clVBZUBRS0FofjIwbENRYzlLeClJUX0KemgkMFZYdTt4JlRUPmIyVjUhPDxPYSRmPypJ
QS1VLVc3VWdQcF5HIU5iOGJrJlM3S1J9Zn5uIVd5b0FLKW5CJX4hCnp5PHx0V3w0e2oxVDFoeW9V
LUBtXntLQ1Q3PVJ4T3ZlU0lzdm1OSlhvRGtDdzhlSj9RVjM3XkdMRW54U0VubUotcwp6WjdtOERV
YEJZVHZwU2NPbnJoPWpqMF48PGlFTShkcjRRTnZfbGVkcm9XeX07fEw2WW9LY3s3b0xIOz0pZ3Nr
dy0Kcm5KOD85fE0hPk5AYilzJF81WGJHeSY/NVc8JVdkfVViVGhIVlI2Q3NtKHJpemZCKmpnbiU7
JE8KCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNs
aXBzZV9pY29uLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9pY29uLnBuZwpuZXcgZmlsZSBt
b2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
Li5hMTM1YzU0ZTE0OWVhYTkwYjYxMGE2OWM4ZjliZjZkZWIwNmMwZTY3CkdJVCBiaW5hcnkgcGF0
Y2gKbGl0ZXJhbCAxNTgyNQp6Y21YOV9XbXNFSCgrPShxTVRAKDt5Rj45KCtAKk1ONFVpeCQ0I25M
STZmZkBYI2k2Km55SWM3M3l4KlRCQylifGMKeipfbkgwWEdiRDUpRCRwS05sKmEqMEVVdkh0UUco
TzFOe2pES3RfYXE4TSohYjNJSz91RGFsR3tgKCZNVV8rfVheCnpfP0VuRCZrMT4tN2BJdUNxITVs
b3dYWTJHQmQhcHdJUCNtRjY0ZkUjQjY1ZDE7aW1uO0FkJiVkQ2FRbnZyR0BFQAp6cWViVGxsXm55
UjxUOHNVYmN8LUpQR0IycFY9Wm1DXkx1YkZUaT44S1NUKl9ldCNhLTc5QyZoZFV7Slp6V2F1cmwK
ejtvTmFJWnxFRX12fiVTbk4qKl9+VkBMSCpNSXkqZjl3dk5QTUZNTSpPdHV1cW0taF9lQTNoPnc5
PH4lK3VIRnV4CnpQe3cxKDRjUW1vIWlEN1VASTNyN2wmYjAkZCUkc1Y8fko+WTRnV2dvQyt5WTcz
dSZVemU8eWQ/ITtWWH1iWndwfAp6Xk02ZExQaXpAeUpVezFfU0ZpQklTVUprflBFMSpJNkU5M3A8
NWNSYDYoaiFaUlVzTzM2XiZvejgpO3p0WnlydTAKejREJChPRGNPSCVJUDNpOTB6cCk8K2w/MGlD
eCZSPi1zamZKejBRXmNsdn1qTHN8LXE2JVhMXmo/SiVDI3h+QDg5CnoqR0RPYUQ+ODxzeDlEIUNT
MjhCYWxgMWszNUxaVWhCT35Ad2tgMz9rYmhKcFgldURCQXpWPzFjJVcxeHhpNHk0QQp6Vns9fm03
JURYfj15aDduYDNvbWwlVSYoNSQ1ODtfaTY+QisrMlNqRXRMJWB+QEg4MkNUfnt0cDBsS0FvM3dT
JWcKeiNLTyFyRjRmam14YnAqJjRKYEB8M2lVK0Qkald+TUFQPXdkKmlVTG89RjgqZkN5fSgrNi1e
dE0yWkplKmskS1dCCnojQioydlAwdX1QT3QkQkVtUSlKdVJIK0J2Q3VZYGo1eENPeXtCQStuLUtT
K3ZZYW0+ODxPMl5YVUkzREcxVyVVVgp6NTUrK0Jfb1hFUTltVVFFSWlIalZ3JHRZZip6bnxWPF8o
Tj9Wc3IoK0QraGtfUzJKdHUpUntjfU1ZVWAtZnJWVXYKeiF3YTQjdXx6aX5OKk1pbTsmZ1R2SClo
RUQ5KmRfZ3hIU1pOQCY+dSpeMHpYb1FNUjEoKjZ9aiV0O2tPTSlVaXNrCnpyfCE3dExSTntyLTtR
SFh5ZDc1e0tlbzJFX356YHQkWjNZd3ZFI0k5c1dJe0tFQWd6REIkbClnSWlSYzJhdj9iSgp6bmlL
c1QtIzxKKF80azxHcmpyblVGS0Jwd0UtYChiNEooX28tPzcxezgkPHBZcjhrSVREcURMMlR6SUtr
e1MpfXMKel9WUkdyUWZ0SX5WQmYmM2JwMihDaXt7MUE3bV9uQ3VTa1B7ISkzdDRvekQ3bkZZVk01
akw/K2hjMElFM2M+VnRICnpBZmNsP0gjOzsqTFgoQzhZYWdsKnVERWFQe1FoPnJ8ODRPVyhrVFhI
WEhGZ01jTk52U180fUd6SHNtZmptQGI3NAp6emwoPE9maT47bkJ2R2dHYEsyMGtMaD01RVgkfjFo
elVuUkFmKiEtbkRrcGRIO0hpVWohfGx5N1A3ST5aPTZ4M0UKelRCX1lFI0d1U2xMUFdSQDZtXmU/
dytvJihYbFE4UWFfKUozbmFeP15lMUFSd0o/KHE1Pn5ZaTViNlE2OXJzSmp7CnpXXncmYzR8dkBu
ZF81LWdoUXd2Qkc/fEpTdjJKSktSV0B1WTBNKl5NdmZPUGVKJUs9eHM4bmBIKyRXQmYrdTdXdwp6
bzVePjJXOTYpUCtmN14yPyYwNFkpVyomfWNQQTNCeDNsVlJTNXdfKVJJISVSMXxrVmhAazZyfWYo
STMtITVXXlAKei1kfVdieyM8fEJjcFFtP1I0QTBmZTVFODIlc31NaUpfZytlUDt7UV5kUDl5bXl3
NFlYeV42Rz8/NXZadUF9KCEyCnoqfHg3I1hpQiRiYHk9clpDbEI9TmVXcFZRUDJIfS0tZH4qfCRO
VWEpLSp7Yz4oWXBhVXZjMDR4RkYpZUcxek9Bdwp6QXc0NnglP3AoYCtgSWQkbXMzdiYrMF5xSnVk
VXNFUnVrSig/fFNSSWZUVXxOUV9xY2dOQ1h2ZlAwb1lnbytkJG8Kelc2MnlIdWZSQyorZTRmQykx
eSVvIU9EaTdzRXlmSCM+eGlRJkZBTjVaWSt1ME9QZWFjay1lcj53XjI0MCNlUnZpCno9ZDVwNiNO
RiQhKTlOTjNDIXA3WmcobHw8Rn1fR0BpRFJKWDN2fUk3NnJRZ21HanljWUs2Zmt8dH5aMz1JdGtP
KQp6NzByYUBlbThLUGkjZFo5SlJqRUdGTGI+eG1pWjxsXnchYyZmVEI0OEY1NEE0JWRDMyFFfGJl
cV5QTWomP35pdk4Kel9qeHIjSDhXdiFOdG5PekxCSksjamFPNmgqS3MofCVFa3NeWjw9aUcmYHZy
JlBFQn1Qal89S31PfHtzMiEyNXk3CnojJmJyQGotNVZMbm13RWI3YDFPfCZGMmlgMCgxJVMxY2BC
U2c2OXFKWkY0c3RkQHhtKGNZN247VGclJUZDeGptPQp6QnA/JTVvZSNSMl9eS0BeRCVKXjdGdzV8
UjlZPVF5VUN3SzdDIU1AZ3gjMUtYZnBHX1VOKH18Y15XWEE3O0lNaEkKeipIaSUkVkJicCFyQXpk
TW5uJUElNXNhOzZiaWZJUWJLcFdONjhaQjxQZiViPE93S1c9Wl53P1ZvPEV9fTI8Qm4pCno/Rjkx
N0NlVklsSlYtUmskX29oVD9MNWY3MnooMjlzQz5FWj9ncX4rS2QkK2FQc1NKNCYpYmBzTnNfbC1e
bClfagp6SHYmI3NSZSNfVmhxUE4mVkNAJFNhQ1ljaD4qYSM/YHBxNHJ2cn5vUzkoVjs1e1R3bzVG
dVR5aTs2OW9DO1F2K30KejdqUGB5ejIyez9QX2FRblA+USV9PzdofS0rU1BSLSkzeTVDaSZpZXpa
fVRGU1cwI2otWTBWUDVecVM1QUlrTUlACnpfTUdGN3twMHdrMnhZamtZJWh6YyttbTswO0J7JHZw
PHUxRC00NUViU2s5M282KldJSHRiNEIjIXxVI1dfdURtdwp6LU97Q2JIOURDUmE9d2IkRG5Abk5K
PFgpVmB8STRAQDB7M0lsVU1TfFRTfl83NWUyT1FUVGc3Jm9tJnxXNSpFPn0KeldJZDlCJjRfdDA1
N1N0SWtGX3l6JmQ7X2orSFE4ZilsaCtjdClGa3pXXlJjZzYkbSgwaGRpcFlCZG5eMW1HMVNxCnoj
dHltfldeKUtWMWRFdlpLKSY8OXlWQXg4aUlHb0VPWDd+Um5idkdpdz1KeF9YY2hnXypieGM0Yl9u
aSFFY3Q+Qgp6ZX53V2RjJjZaZXpVdWpkekB9ay01RDVaKEw1OFUpK3VkdG5CSE5+WWk/OH02OUEj
fEMkJm9aVTctPjh8Y0EzTl8Kejd0K3IjRk1qdUxtViNCNlMqXiQra1VafC1rYyFxSldLVmZPPn44
bi1gYEtyVG13IT07SSZoZHV2dGVZN1FIcVpACnpoOUtYWSYyQlNzRzAxVEIxNWxKRkxgISlEYFY2
X3gtU0RhbEN2JWVwRi1uKkxVUTl2biM/RmcxbEBIMFRfelcwZwp6dWFfNUJWPz9PZCtsKmMhamR6
e0xZWnZ8eEMqVFdMPGg0KnRlcHAtSD5vSk1AJVImbUs0XmZaOTgkMFBBWjdZbFAKeiRpQlhYI1FE
cTB5M3V8UDNXKiVVOFVYQm02bzghSDBsbl9CRkFfbz97VHAoSmN0a2tvZyUrQWhGNjF1IVokenFT
CnpSQl8xMHUqam9mYzsoK3VpKEBqeUhKRFJoNTF+dFEqVXhKKUM7TXppRm87dTk+dG9LcVYtNW0l
eUk8Q3lhJip5ZQp6QTk2MSRAY3VXOUtlfHJzYFE+P2BeQ0o3ZzdhOzxNT2spR2Q1fStuS1c9WUU1
LWUkeUo3QGFkK0h6ckN4KzBSJkwKeisreV9nP0ZZc01adX10M3VhYFlac0Ywc2JiME0hOG95S2p8
O1g2Y29yMmFtbGIrYHpedjZsQ3o+ajQ5JXtgWE5PCnp1R3BJMEZzVSNOXlEpZWRWZ2YxM2QjdVgo
UzZme31KY2dRIyl9dXZrPWRvPVVmclReQW55eFFjdT1JUVluNClmZAp6aG4wbUtVJnpWdjlyRm16
bil2JnspdEY5X15xZjZrcXd+dFd1KzE0XmwyKCFTQz8yWiElO25+KzlwY3M3MT9ZV3cKelliKmJB
SFhne0xkV2gjYGRQMGJwb1pSRmxOYUQ1SWZOMVZJNmY1VkhSM0lfKlUwdGxePkRhIWdFSjxmSlAl
VjlFCnpONjBObnJfckZZdFIhZGttODZKSTtOcVlManwzZGZtfmJpNFd3Vmc7WC04MTQ0LV99VnYh
YmI3JHs0dj09bClQTQp6dX1uNml5ZExfVEpwfllkSjVweD58SWghMz5Lb3VtPSNgKj1LK2gtbXYj
ZGcxQmhqMHYrXyFDSnFQYmdmdGdPUnsKek95XkYwN300azlLOTE0X2ArVmhQPj0pJGpvcGUmaHFO
TVdxPDgtOFh1fWZVJiZ+Kzk1dk0zYUV4Vk5faGN9QDZQCno1NipuMygob0pNJms+KVZoKWx2R1Z0
TnRlYWxPWUNIZ2dJSmROZWtDKmpvd2s2P0kxfk5AfD92N1VjQnRBeyMpVQp6QUF3VjBLNk03WXRW
RVMxQUtUbG9KemhmTDwtcThgbWFPYn4qVks3ZWA4YHEwbUlCViE+YyNuZWF6JUhwKDJyRjcKejI/
YGpjQiZ+bWkyMUNec2s5U0goOHhKQCl2ZExpN0ptPC0oIzZtX2IjPVpWKGZSQ3M8IyY8M0ROUTtn
Xz87KW1jCnpqeEBASSstN198c1RMejRfRV5eOGQ7eVolRjtSPjwzV3NORVNaWEV5LSZZNHh1ZG1g
PW1TZWQmYHE3KD9SLU8kOwp6IXQ4Y09iciYtOSt5RnZFc3ZAbDtxNjdiezRJQGRXV1c2Pm0lMyE9
NntVfj0jaG1aNGc0OWNYMSh9UWAqKHN0dnIKejRhVV5MO2hSfTlTKVZ7KmEpM2ZVMUJZbFgjPiMx
QlV6KVQlSnNZTX09RnduRSVHbTd5b3R0fXAwREB3TjM2X2NmCnpgUyh3PHtrbmgmWTIyUTJ0RUxw
PjNFPWBrPmMkVjI9dSQpcDw5bW40PWZ4IyRpQihuWCFwa0N1PVpBVFBsYCshZAp6PlcxdEp7OWB7
K2RpJHx3SGpMd0YzSyRFRkR6KGFWaD9yQXxtQCM9b2pqVVgzZStDNz8rfX5ucFJPKnh9YUdDb0UK
ekR0eipaTU8wPkBxdC01KUU3QkM+UnhZKW9DQmoyZnhqKFlyVkxibDhrYXNCcHUhK3taX2AtfWFP
NlBqI214TF5pCnpFUTkoVG1Wd00mYlRwTkh1aTFLM0ZtUT5oQkNRTEkmO3BDYjxMayNRYlBhcHdt
aX05LSRlQHkyZ1NuPX0kU1RqXgp6U0dBNWNYVzNgR1BhcEhFMjxYdkFaMGJETl47SHl4bCZwQSZT
JVotVTQ7Vmp1VERANiRYK0ZzVEJLTDctb0E2ZlEKemdGNDFBbFctWHAxPHpzS0I8KEh+cUl0amB7
V2hifGNUMD1RPl49RmZzR0hJRypoJXgwKHZFQyVlamhjYnJxP0hxCno3Oz1WPmNYWnQ1QmcqeWF1
NjwoZEYwQXckQ0cqZUNuJklFeig4YiU1UlllLXo1QUYjVW57NX59IT05SjQkZ0IqbAp6KUE5e3NU
SSp5ZGE3RHRSJHZEZSNvMkR9fk5UdT0ycUtoPmNyKUs5PSl4OERLNGtpeTRfZVBvSyVGKlprPyRT
b2QKem83V0g4WDNIfSReVDloS0BgTzwkeU9NY1ZufDZ0I0M2U09nYkRHMmREUXl5e3BZVkVRPktA
QldsNGVOYD89JWBACnpOP1RZT0soTlVrfDE+RVk2e1RqfWNPezBWaGkhIXRYPztsZyF6Un5lPS16
M3leOXx2QTxxMDxLez47cXlveE8yawp6XmpgJStPJipfWjs9fkBvRzcmbHEldWVGPjgySjJmdmpI
NTFsKXY0OHcmKGxKM09GKFlCKnI0LVY2YXdZI3Z8ZyQKejRROVI0dz9TOyU4Mk9PdmgoMk9UeCtr
KWc+Nkh+eXdPY1I+MjR5c0xPayNLRCE/WVlyakZ2e31MaDFhOGhxdVJOCnohbVFkMzBZfmY0KU5F
SiZBQDR+Qi1POWRMdkNIQXZ7PGl4K3pMVl9WUi1Wekp7P0syc0h4WnZJUUNUYVJEVSFzPAp6S2lL
ZWd5O1dURjAyLT43LS1gP2Q9Sk43UGx0ZiZTQlJYKGQkUEkhOF4xUm58YDYkUUBSRigrYExGKGs+
Vih8U2YKem9ZNGcreTRVbyk7RG00LXMkMkojIWpOZWFvUDUzViVgRDN+dUYpMzF2bmIhUURBVjJ5
T1AheWteQVV9PTE+fVpkCnpxKG9tPSVwfCVGMTUkRiZlUjQjK29VRE9HJE8rTVppN1E3a00xd2JS
aXg/dCRYfFB3ciYwU215OX5XKFZCUSM9Owp6d0Z6dV9eU1BgLWVvaGg5Jm1iQWEtalhvfGhsZ3Fz
ays7TUFsMVJ5VjZkOEhXS04jalJ1I19XV08rfjVTRjJLe2gKeiomblVtUDlgKU9ldzlZQGFeT2dB
QmJVNnhwcWVBV3g7QCkkVGdsbERHdDlOUChWeiZZO2VgMjRETz5tX1ZkQlprCno+dWlsQWY8Jjxw
aj9eLVZubCNpKFJXWGxHWHxUYEtfT28oRUN0Kl9RIVU+Kyotb3BaKCVrRi08TEcrQVpYcG5NeAp6
SkVxVF97PXJwanh5aV8kT3xBbEU8bG97RlZ4TjhTPHh4Kjx2WVdhISE+MXZlZ2AzMW1fME1IcnJi
LVY5UCNNXlgKencrQENHPH5aUlBxKzNpMTN5IVQrZSMjQGp7M1kjNGEtK219a3l8WlB3MWtLbFJw
Sjc0YXwxQ2lJYDsze0ExbURSCnozYCFtczwmUCZGaV58Q2hnRENGQWhmP3speVIkX2EmNzQmRCRF
ST5kYzVGaiQtMz1LcmN4K2A2XjB7X0hxNkxCcgp6IXYoO0ZWQ3RpNHkkST84endGZCg0e2kjZEd0
YyhaLWwjbUNsRT8xQ2Y0TksySy1TJDVAY1pmPUVhPEtPP2JVSW0KekU/bj9oM2VnRSY/Vz9KZTFP
YWF9V2kzfkgxQzlKb0V8QEBqJkpHe0F3NkQ9eHttMyRWeEZ4ciZ5RTRfakFEI1VOCnokfDtlVkI8
fHRvUjN7VGs9aDlRaFp4cFFzSz0rRnN7cyY3I0hTPTEtUis/YWZvPD1ZdDJfRkxuJjJSP1RLYUZs
YAp6RnRlTD8zJlNrS0h1fH5taj5NX3BAZ21ofDtIOWM5Q30oZC0xOStAbzdVJEg5ZmoqbCEkd0xK
MWU7bldURz11bFIKenFnVk04aV5tcXYlK1JCPiFXPHE3JTUmQnlOP0htbDRQX3Vybm5nUXwzWS1D
eHF3c047JENDMGxOVmI0MDxkYlJTCno4SExxalZfU2AoSD9GTyFFPkp7YjxzTG0oJmx7PDA/Rzg0
YlFwUyl6ajl7VTVuPDdlQ0twP3IwI0ZPK2h2YiZZYQp6cm03azA2KFoqVnl6PUxJOTNkOX09TEZx
cmgoS3FBJU40QmhpMnpsY0xgMD53LTZTRjdPODklPXlWTDkza0Mldm4Kej43MD8wVWd1NkJOUEt9
dHt7KiktJVYlVnMtTSRMYj4+TyQrVkt9SllYQ2ZnNiQjbyhKSHhrdHlAbzEqTDFiMTgxCnplTkFn
e0RfK350MSNLTjZOTTZuZDBiTVEwS3lPRFghbWxJRHZxPld6ck42az83I0FHPVJUaGFRLW4wWlVu
TW9qUwp6dmNPPWZhQVdkR0wkciF8TVJhbVVZfVRLRjlAWUEpUGFfOHxTa0FKXykrK1NCWG9mRmlS
SXpVSVVxRGl6TkBZWCgKenhTSzVxUmxZVloyRDs5dGRUWTFjO0hlQUFSZ1JhMSVVd2lEQUZNP1JS
T311YHhkREE/N1hQajdeMmFgYkVgcWthCnpzT2A3Ny1yfEVsNkE5eUFZYkxJUzleU0lMUnhiXnUz
Kz5RJiM4KUwkTmEmbWZ7MEw0Rz01VmBCT1ltRilafEJ+cQp6bis7dFF3Q05YRTFEK30wXiYkNmoz
K192I0NKTCZvUzBCNSs2TTkqfHNUJEljPUdjR1ZjKTMlNUpofnhldmJ4VEAKekVRSHxhZnQ4Smhn
Y1lFNC1lPEdpWiVKTitPflIxVDJoRWBPXkchSU9ZJmtnbHUjfExlP2BiMDx4cGV1JEE1cnhGCnok
Y1V4dit3VGNuY1JSckhIRzl4bXVLUjlQYnh9UlRCJE5NcGctRGxVbVZCUjZvV24pWTJUbCtqdyYq
QyUtbCljbQp6ODF5ZFVZOyNwYXNJfUF5PWU8Iz0qckg1RSlFYXtSYUpEe3koZSo0b05xfVRLeGdV
e0BeOzhsZlooe2JfcT0rVncKemhJN3phS3dQbU1oS3lSQz5BOFRwK1NzNFd3Ql9wSXU9JnU0Knwy
ZkA5RWN1YVZOck81JC1QPSppNiNJIWVzUWMkCnp2N05OKWNxfmFEOVE/aUlfeClaYVJeIURsRDVS
KDlNSTFnRngrQmtUZzhRPE50P35Fb19oXiYoKlFYeT1KS2B2Nwp6PXlhdyZldG9wUWFCdHNBLTYo
OSpEUHxrP3h1VCM7WG1efl5yRTs1WnN1TXdtNTx3ZEBmMjs3TiVHM2BRXmRSRVEKeiZ+JmQtSHJX
QXdJViVqdXZqe3lgTm9uKWB3bF5wZUM8KVJvRz9VSWYlN3VFKjZ9c1dzKj87YUBaMTl9e05LJCNj
CnowZTg/JSlGIStLb01vY1M9U1ZxP0hmcTBgNXFLYUhsUGA5SmtiZGo+WmFqelQlSzsmbGlON1Qh
cz96LTxqPVJYUQp6NCMxU20hLXZ6MVZJZ0VjeFR4KzdUSyNUPWNYeklnODtGP3w5THo2ak8wdiE3
NEZOa1BRIyVDX3pOO2pyZmkwVkwKemRMbk49YUg2YU8/bjUqcV45OHBucy1GRCFBe1M8I1cqWXY1
e2l4fmsjanA3PTlWeUI1cWNENzw8Nzh0PXVzUVJkCnphJWFAZjFfa3hJWFJLRG9Ab1o0eUNXYVlx
eV9VQSkqdEltMFh+IVZ9Pm82Zj4qUG85LXNPJWJrKmtWbEpGIXVwMwp6K0xBP0BCdDhNQDQrYlBn
SEkjOWQoeEM2Jnp+RjVIVlBvQGFgY3o8UTFmYHVHdWNKJlJPMnlFS1BidkNleSNQcisKenkzSHoh
TF4yTzw7I1M5LWF7WkRUOVZjdkZZP3pkcD58SH5ybH1mMD4+Y19yR1p7U15HK3FQPmVHYndCSz1q
TTdkCnpyTHV7bjxsNz9ARHVtRUV1bztgalFpeWU+WEh2OUFgS0pqTEdfSz92REtOPj1tMDhxTnxJ
NHEmUU1+I0w/bSRrbQp6Xyt6czNrKWRrS3hPfkVAUz9BTnNMU2swPzM3SjBMckk4Jk5ZeUUrekxV
Rmx0a1lAIWE7akRqeDBZVHclQzF9VmoKenNlb3VmJFkhMVRvQWA7dkBqU09NNk9xc3BaWHJISjtB
V35RJiNIblVmODFVRWRzYmROS0MxJVhhJFFTJnBJUyFkCnpvNVB8NGZONy1OYlR9Tz5BQFlGUitR
LVY1U3cmU3NzTFVFVyE4eTlYRlZfRSU8RDFuT1A1NXBrIXozcGJgJi1WXwp6bG1hWE8jO01vQkZC
R05fSzllKFF3LXhIc1dEfjtUQW41V2A4YS16fnl1VkNXMnZqYDsmVzstPTcyd1h6Szc7NF4KelZW
blc5UkJ0WiRTMko+PlBrbzcjI2RfNnI0OWxAdTMyMm5JX189PE1ZRjxmVUJOXlFja2JUQSY8c04x
MiFoeVJCCnpqNjlzQENJcVRuQHRYbXdXRj1mNlAwNjcmWVlMUkNobiRzUj9fNk0oSDJ1bEslWW9w
Q0hmMXNTNVN1WkApSFBkQQp6eSQ8PygrM1FGS1RDPj59SD1ASXJYZX1Dc1pCJUpfO2BASnB7VUo1
THNZLUR4VU9kej8qQkZoPV8lNEM5aENza3UKenFYJkdScnVLSCk9ZUdUdW9ILWxLU2VqZCtEPnkr
VUMtZFAyZXU9VGRIc0E8QztDUHE1MkJYRXY/Kll3Pik5ZlB+CnprNlhKRDwhK29wVEBDTTh0UTxH
O0Nec2tjYFB1MCVzPSVOTUU+UystPyRsZzgxKXxXLVMoVW5jezRiPDloJl9yUAp6M281eW5MQTxM
OElOK2FGWigpVlBzak1iRmNTRHVNTH5+UW9rcllaXmlGPTtpfDFIPSFMcklKYG1UdVdCaE5OSioK
elY4I31raHg2OGUmMU1IYzNEKFNiczFuYnQ7Tk5Nd2h7YnN5JW9tNFQ5Vnd1TU9vYyZJQmRKUjxU
LWZ3eHJ4T3NUCnpeek1PNjM2e1EzMzZATCljVURVcm1HXmlGKSYqSDhrMyVLbykoVXB2KEhDM2B7
eyhVRGBSIVc+Zj5MK140QVN6WAp6PnZoajYodj55ciotUitOIVFuc1dVPHtSSVViX3pYJjd2dlpH
UDRJOCU/fUp0K2BrRklESVVNa25BQmJwdkZxMW8KelMhaz1YSyF9TDl2SVNBNHgqdXtqaFRVYzBj
S3pvfUtiZDcwb15Qaj1WTEElSVZkRk18UEVibTRrTHhxNHNVVz1BCnpQO30/JT83ZlMmIUJvRGIt
P0RgU0dzWVNtLSthcW8xRVhSaj9TJDY+S2UrOEI+QFheTHN1Yj5YMWY8VWt3ZjNTKgp6RU0xe3ZK
KUZeIUp8PUFGTmFjcVE7RH4lJDxQRDJAVG12JkRqTk40SXdlQiVZWEF7ciVEOUJVNURIJEd0MHc1
P0IKenF+LT1rWX1XdjN0RFc+ZlQhb21GbVIxNHs/LWFUeGVpUDVKdEFFPSp5T2IhRE9mTGsodyZV
JnRRaHwrY0xhLVphCnpPP3cpJkEpeVpPbE8xJS1GYSZ1PyNyUikqLT53cXtZZFNKNUBNRFZvTk03
RXUzd2FXRWJWVkFjNDlWeytJfVB2Owp6JFo4cnc9fGhFYmE0d1U8emZQVyFpN2xKPSk5X345Y0wk
P2lZMGJNM3Njb0spP3JwSCtRfm58WDJsNGRMYyF2UFoKejUoZDJoZTJ1MSpvZlk5MHZ6fi1fUlNB
cU0yTDdYQStySWcwUFZZMG5BV0NFZGRpMnw5MXxnQCNoVz4qTVR0dV5eCnpWbjw3TSF9ZWY9QzRX
RGMtTmgrMjdnJTRzJVNeR0FDNEQ5d2BgTyNgaSomTHVHdmdhP2JiQ0smUCpIQX12fk1wOwp6Q3dr
Qz4xezdRTWpARH18KHpJUE0hMjUpQkElcmM+PlEkV0VVcTU/YDJ2Kip8OEApY3U1Xj83R0xkd3R2
Rns2RUEKejBCZHNVbUFnS2lTTl44I2UlPnx4UkgmaE12aFJhPiswRU1sITwhTTlDRT83NCMtc0Vv
UTlNbVM5c0hCKnMtWn08Cnp8TUxLaGJuLVghPnZ+PV9xdUZaTXZ2O2RKZFZNcilNKXNfKHEtY0ow
MTx6cEtSJWlkbGQ2YnN1dHNZMnJRaH41Zwp6KldIM2wyR1hBb21pdzFWKG52bmJzdVZFJilFP2k3
Q29jMz0jcz8yd3deTG82cn4yVTlUI29SMmMzPzZCbkhUPmQKej03QVVXUX0kTmB0MTEmKT5udkwj
eSF7O1R2XktEIVQ9aHVOPjIyUkcoazx9Uzk2eV80c1g3NCtuOUFuZTxRSEl0CnpgIzZPTFkqdntp
d0lKbjUxXjViJTxtOGVwSkFFSzVQUU80JnAxTkdFJkZTfWpjR1JkcCNTWT5eY3A4el5WflBxPgp6
dmFpKEFkMy1CPjwtRiRxIVlfeHQ9Vilkcnh9X2JHbyNBXj5WaERKYG4rOzVWZlkxODM5QEFqeTRI
OzJ7b3VhWnoKeitFMVVNQnB8aUNXTyh4JXc5SV91LTc0ay1QczhUQCM5THxtLTY5eEpRQEV8fTF3
YWomYVYqRD03QHxjSEJQWGh9Cno1TEtXNyElZiNDMHdOYnRxSDI5cGMyV0RRWVIrPjVmaHNTfjtM
MnAmZGRaYGIxOGtoMD4yQEcmI3lwXjJkRXlwfAp6SlNqRCNreG9jUWY5fm1ITkpoKygyfihxJHNu
MjlrSmxBKjJhcnMjaWZhR2F0UTQ3REBhPHMhTU9yYzRoaFYxK2QKeiNnYHNrZlp4NDVsV2ZMPVV8
S09CO0NydksxJVNBKyMmUSV5e0FOSFN5Rzt+ckZBalVEcVIzOzRyfEpMKiM8bX5kCnpIaThrVEpw
IzJxbDQ/cT0yX1lVZzZzejkpVkNNZEVUMit5Vkl4NGlvJGE4JkVQPWA5Z1EzK1N1Nm1ReEReRm5g
Sgp6dnBrVCRaRFh5dEh9aFZ8S3tyTjhgfVFVaDshPlhqdG1aZVB7dUx2WVZBcC05P2s4SHZZYXFg
e3FxPkJ6OWU/fFgKelItWjMyTW41RCokSmUjOTA7Wng9MChDMV48aWh5U28xZjQzSDlDSHRgcWl5
NG9zeDQ+a15udVVLLVlRKXZ8PCFmCnpKOWNiUGohK1VgIXR3ZGxGVVcyP3xBUXFtZyp+KkJnOG16
NyNsLW0hbTg5XjY9ISF1ST83XmhMQnlIXnZKSD4tQwp6RStXV1YyX3FAOU5IWCtATkN8dl4pMFB4
VzBOQWNXM0hEKX1ZdTZwdlckVGUwXmNjJHlrK0l4KWlkKE9WZG5BcFUKelJAT3c4Vyp6WWAhfFhK
ZV54ekBuMTd9RGc/YnNiN2NTbVM2ZEZgcWFGK2xMcUxLJDBvUlY8Q0NjOEslMmt7eHhSCnpNM0Io
PHZVPXQ2MDFgUEElMyktUmohPGktXnc9KGEyQiplR2A9QV5LUHskNnAqMFk8TFVkNyRRUDVzRT42
akE2Qwp6b3hEdlRXNygpNnBRPWE5T1FRWkBFP0M5aiV9V0ElX0ohYjNjOT9sUSE0YypYRGNKOXh1
N3k3MXJkODA0aiZpS3kKem0pXzNQZF5SV2MrPkItQ3Bme31qRC18dWhpJUojNzs2SFI5KFZ5WDZU
LWpMO3hgUkVVN3lCXil1cFhJPVc+Tz1wCnpkS1pgY0UyWFdIS15Wc2YwZGxuNnYtbzk+aX5ecila
YTVTZm1IM3tpeXc5OTUyNi1MKj5LVjZqe2s3YTFPNiV9Ngp6by1wTDxhN0NGLT5hdyNXVX0+Qykh
WF5XP2l6VklIQmU7bUhLZGljRG4pSz9zV2IzZV43KWJAQz5YRyZhYU08dkwKel8kdjw5JE1mX1k5
PkQ8cyNhaU91ZDJuaXVDJXE5aiorRjhHWnN8bUdefCZ3QGl2WT9jPGJRXjJuaGhpSVg1WEJ6Cno3
KTxGN2trV284dUMoP24oY2Mzbl5Ram4lR1gxUTcraEtHb1g+R2p3VGM8X0ZCd0VDeF5oPGJJUDch
fituSTdiSQp6I2p+QnYmKGs+a1NfTkFXZmROUk0+R0dOQGJGNUJBa3h6a3JBbjFaRTxLTTVDSyZW
Rnx3bTR2YzYrQEJkZG9adG8KemlYaD8tOXw3VHd3JXlPQDhCMHQqdk13JH54T2pLNkxeYz1jezN1
ME1haHlYPFdkVG9PJmVIe2UpeC11WUxYcUoxCnooRn4+aChSNUthaVdoP1hfOTFHbShQOVR0NE9q
NyFnenNiXjQmQFhvQTZuSDtYXlpPRUZHUzgrYiNHPnFEdz9JXgp6dyQ4O3xAPmlrZjx3MEBge154
c1NMUWpzdEcoY09mITEoTWRWfWUwS2RTYDVqRTx7eHYhRytvP1ctRVM2NDFLXmUKekl6I2FfMD9z
eE1TMFFWbTx0S3VqNyZzMmJBaGpRJEdLJlFWQ0ghWiZtYDI5QkxBdVNUNEUkZihrSE5GZntRWCRM
Cnp4VzkjbFcqbWN9ZkdOS2k1UClkNWFgMDJqXnxFNCRwR2c2PEhnTTJjJCUkNH4pemElZk5EZkFI
VEB9ZDtHWSV4Kgp6cSF6dyVuWHs9Kj9JSzhHKDFWaEIjTyVfMEdYPE5TJjUteX5jVlMzY0RPZHQh
SVRgPSo/e0E7ZXV9KEItS0ZDUzIKek1kK1liJlNGQE55SmVtPmtlX0dyPmJnK3hzJj0+YjdAd0J1
YXcqNUdWRXQ/dDc8b15ZOTU+TH1VMmdHVD1lRHFVCnp2ekxzYjAmQWtLejBMcCh4JmlSVzRQT2xf
ZHFaVH1oOCtfQiE5XjJ2QHNmKXkzdFRSTFhGO2h+UVh7eXBOMDBwVgp6WHclakE2PnNfJDVudSlg
KCtnfnxBeXdRRm00c0BXaGpsbEFqP35xQmZxS0Y9UzdIM2clOFZzSHh6fjEkYHF+KT4Kej9ob35E
IWAxfWs/Nmc3YFN5QU51bG55ZEBaTkA1WF5LPExSMEtAakhvN3BFRVRsWTtRSnsmZjQwSVhJMCl7
PTdrCnozIS08dEs7ZFcqY1FITlg2WSNuP1gqK3lAVGA8LVhFbkItJTlnJHhgWCp4eytvUnFGK3B5
bW15NGRaJDZjdlc/dgp6ZlFqfnpCYW0xTGxVYSF6c002U2Q3WnA0N1kkckxKaD5xTFMrJEF2VSNC
RCRpPnEzcE0ocH4tQmJmZkpYP3I1MmwKelQ2SzUyIy1zPkNLemRVPXopJmw9cHRoIXRrbnVya217
QkhnOTBwPDV1fDU8PUA7ZCpBIUtgOFJXaUhUIXZJSnYtCnpQVVFYSjE4QXB6dm4pektgQ0BsR057
I2tmUSp5UkljS1JEUCtZKFlpc1c7c0RNfGMkSi19b0NGUGg8Z2lCdDBnNAp6Rnh9MGVkOVlCS0ll
aypJKEMyNER4OEh9alJRe2s9IWZyfGpQWjMhZDtoak41bncyQytXZFcybHZ0UntmO0deN3oKeiZh
ejU0S353ZVBYWio7cjckTmI2aU1FdCU+M0BmO3lMS2U/IVFhaHVZTlBEZF9jc3p9cjRjejFnV2o4
Vj8zbnE8CnppS21BbUt4MHdgMjI0TWsjI1RQJDRyano3ajc8NnZycmp7K3ZCejRRMlQzfVZTcn1A
ZXZwcjtGQlJmZlRjZ1RwZQp6MExfcmo9b0pnVmhgPzs+M1YzUnBCWXU1fCZyPTRtPz9nX2kweXVp
NlZ5d1FkWnlzNnUxcGhze1hiJkFRIXZtTUsKekwoJUJgWXliM2NPQzNsLSNqZHA4e3F2TnUtRVpC
a0RqbWVTKkw/bmZKWjg9dFMqQUJKP0VTZjRPUyRofD1ORngrCnpIIWVjeEQlYUhMOFFlLURXNDlf
UldaR09Se0ctM2UwNVIoWHshRGk4SXtaRkslb05EPT1UNHwyTCp8S0dFdH5NTwp6T2NWKSMpNk1F
cHg2JGJyWnBxRV9OSSVDJlheJUJ3byQkZylTVzBlPTJtMUFNWlYyc3hqTTAyIThiY3dxcno9fVcK
ej9KUkNHNz5fTlNjMnQ2QGkrcCo2NFZZNlhnRVoyVWhabyszTGshPDdOcD5+PW8jQXBCQSZ7QUtW
VHpITmVMSnw8CnotO0xmKCN3azNEbzkyemU9RDlXTisjenVMO1RIbU5wJVpNOyh+NlYmbHdtYihX
Z2kzWGR2aCo5MStvQn1NNWc3PAp6TjlfUW8/a3duP2h5JiV1WHRePVhHfSlXM0xfUTcmIzQ+flhG
XklsUjI8UTZtcEhrOE8xd1ZuZmRzT2gld3Q4Mn0KekVxWUt7OXFUMGk8NyYrVF9BamNVQ2gqZHk5
U3oyISVeeWBlaXk5T2JLcUk9c2pFYSo8XkgyYUFGLS1KOCNNQyRHCnomZ3ImdlYzXmwqNjxrKkh0
ezkkcUt7NTsrSDJQcE4/VEpueXt1U2QzPkMtWTtLVSFNVEdzUXRUQzI8eX1EYitoKAp6N3FOLUx5
ZElVITg2WjZhVGVpJiN5Nj81ckhqYjgjIUFDcX0zIzN7U3c4RHApQUJmQTxoKjZVblVENUEjP2lr
dHcKelRvU25AeCVTX2p4bHQ9MHRfISNNRXBRfjlLMyhhdSN4UFFERjM1O0g4QyljS3E7Vj1DX2xq
Pmpoa2xPdlFAaFdhCnpZWnsxMj0qZD0wdzFEREklanYrJCRjKmM1KEhLSjc3UGt8NyY3S3FTd3tS
X0FZI2wodFRNVFF1NHVPWT9MbiNhOwp6ZTBEN3U3P3NQNXN2KmY1bzVsWm5fbXxMQnQyNDFjTGRR
e09pdCUyYll9WGUhaVEqVyt5bFMjOHImaEY8QztIejcKekgrMSh1LW1UV31uTGlmXzZJYWZiYzZW
OzhwTVIxYmlSQD5eYVAjLXdHZjRTKm8jWWdLTVlTS0RBSm5RUnRvb3pyCnpqIWEkTkF5OHZBKHVw
QFh7ZkkjQCR+T1AzOD52JkB3VnQkKHJZS09uPX13Y0k3SUJqIyp2NWI3PVBofFg7fTZITgp6NDFX
Ty09b01pTXQ1IVNmai1DXmFjQUY0WWMrK1coTVRucEV2VHdgam1jSkhLdzwoO056T3M5ZllKKjti
WSVEZTAKemI/VGVxZUNuNkxvPUNqSiR+KX1+WWo9aG5xPW1qSGVER29hVy1yO3toP3xQd2lyJDVu
bjRvS0dUI1FBQ1plXyUmCnpDfGd3ZnFoYy1PMXhMRVApKVgkeVpaWlFVNHhpKT4yRjclP0Y9IT5z
WXN5Sl8rdG1oQC1XMkxuQlYkciZMXyhTOwp6PGomQlp7JDNIKlFWd2YqaThId0hQQjkqRCtiK08z
cDkkczYpfiFKJistJHM3bFRROTtLWCFZXm0kLTFaZHkjMXEKelQwP0peTTIkTlhtVE5rK2xUNVct
LUB+NX00MiY/SHB8RUdnIWR3KlF1K04+O2pxQ2JwJCZIfVFlQClMQkx5T1h0CnpNeE1CTGNCOGhM
PGo2MjdPQmJsVW9IRnQ5Q0tRKGw0Zk51WU52bn1JRGlEWjJ1RCtje0lfJWF7PCoyK2BMYUp0dQp6
eC08TDxIdzNvXnZoPnBxUkx3R2A4MntxZFE5SkhEPn1QbFh7UyVYfDhEc2RQaVE5fihfcnY7O0g+
VkhXQjk9fWwKekNmPW88Xi1uQ1p1R3EtQlApNWgrd319NFMpem4qVEF9X0FkSSlxTlFSfEtRXm5q
fGVGZ2BmPzJRM1QlZ3A8M0NqCnpfX09eN0tRJH1ZcE8lWSp7JDAoPFBPYnloNDsxa0sja04/Ynl8
TFladF8mMip3VjBXYUI1Sl40SENvOHZMZEApcwp6NzQyP1FhJlBnakU/WWhWUzNPczg1PHlzQSlG
PShTKGI0NlU+eSheaXtPSjUrdkpILUpkbjNPTzY5YlZWMWkmR2IKekFNI2cxVXAtdCVMRCMpOWpD
QW1hXiUyQVUra15AOXpld2FoaFJIbDhUOTtoNFNXWndvcXRsc2tkZyQ/QGBiIXUyCnpUMFhjTXRA
KXo9bHkjNmB7QUx7eEBZQ04/eDh3aX1qfSNiPWx6PipUVilael5zaVNmRS1QIzduUkBIY0JMSn1B
Twp6ST9iMWYqezJDez9RZ2g9d2Yzd148WnVLPGRrJT4wcyh7dEpAJWB2YUdgbH5pcX5VUllZX0Q8
YFYoRXFEc3xvTFoKemgrNlMhPTlpUjhQZFU4K0g5c1A2VipmIWxyciE7RjxHNTVYb1khPHVzby1B
cGMtVndHO2o5dT1CWFhpZDM7JiV9CnomYm4yNTR9e3NGYT0oOWxgWXVrc05IfW5hbn5VZTtgK35k
OWNSYCEtVUM3PnxoVDdsejVyTXEpNHRQYUAyeFYhIQp6Sm5kIU9tV2xZfj4pWSlCQUY0MVZOZ01F
fDxgdnZnbmJkV0lqKjx4PTIjWn1qblMtSiZoNDE/fVchSSEjIXE8QVUKelA8Ym91bChhcWJBbnlz
MGMmSmdEe29WRmtjJkk2P0BsVT5aKCFgVGtTZmx7QnViYk5BPXg1dWZIczEmTEVeQndzCnpHPEgx
UHFPZlFjYG9OKDBWKEplPlphRHdwYSlaMW5NTUFHV3FhQmxSJD0yJGgheHhXTUhMYTkxNExnJiRu
ck1sJQp6dUU7TS1ZTFUze1VveW04YHZ0O3NSUGgzcnF1eDJNNU05I3JMZT1uVU9OSU5QayV5Kkx7
Wip3QCUkbFBJR205JlIKentWOE9wZHxNamNORDAwNiRaQiNCTyFiazhUQndGc3I0MmtZTEVzaykz
IUk2YCRwZnJ8Pml5KWkoSFRgOzkwY257CnpCYk12JjktRV8+YSs2bnU7YV5KS15+NGp5PDg+VWF0
dyZiZ01oOT97KWpNeGRJeVdnI0x6O3ZOWXE0RyE8U2RZQgp6Q2d9dGdUVUktYTwjMipAZSh7RD1t
OHhULXpmQ1ZXSXw0OyhPOFR8QHp2PFFSYFRjSUBXQGRmV00hYTEwVW8zUU4Kek1FPTBgO289bnhH
eHgzU2lMRHdlMmd4OE81QXEpdmEkQSFyYnxMOEAycmZvJD4mVGY4I0gtNF40eTxFMW1TSjhpCnpN
NSEwZSFzRX1MT0x2RUVKSlZ2MihnZSl1ITwjJDN6KW09MlBLcGZ9emtiP3E3ZDFMKE5KKj19THs5
MmVvdlFHdAp6bnI3VH1NSjkrcW5hYXZLK29mfWc2NjlObUt4QWd1N2F3TylSYnFZVHM/WVlFMyo9
VkRpI31UM1U3fm1hI2wzUUcKejs+NVNOIzlFbmI8aW1ZQzB0RjN+JWxQfEBsdlk2M18hQ3BKSnhK
OCFiSmNnS1AzMFJ9dSR3QDtIRTxUP3FxKld3CnomaVpoKik4bippeFNFYFQ/QDtecVhOQ0MwTTtf
YTc2S3JaNml5Q343WmxOYiVCUiMhdHJGMlojcVM5dDdSQXxzTgp6NF8jZU9FPk5eUitzU29pOTcl
cGRXSEtJVmJzfXclVFh+UnVZanQpKkNNQ0s+X0goOzQ0P2Q+U0p7VjtvYHtRMjQKeiNiNzdWYFVZ
RU1BUElKSD1IOCYqXyFiQmNmOXctXkBebUdmezEqd3ZXfHNOUXRJV2toNkgtJnFnelJhPHJDaEB9
Cno/Q012UT4zKTVxTjReajlKRUN4KDhzTjUhWlQ9KUBodmMyKWpaLTRSbzlSaXlgeCUtaXZ2NkZ0
VSF7SiUkailwbwp6c24yfDFINXpGN1BSPX1gbUNEcjtnd29HSk97MnQ/RU1CfjhBPXsoMGdzQz59
PV44TlV4QHgqVS1aOEt5c3pxJDMKellsT2Y2dVoraFNxcUpmP2lYTlM0YDUtSjlzdSF4cllRV1Uw
QH10aH1WXjtjdyNoMW9KJSNZWW44VSg1R14xKUpnCnolO1I7TUBySXV8TTIkSFRHezBKWHM8eUYq
WDBiNE1pe1oyQmNlbVVtQ3wwaWxVOSl3O3EoR2ZvJH14PzQqWDhzUwp6cjImYj95eC08VFV1dSVG
PSpvRkhGNypDZGZCZHdGXlRwQCl6ZSZxRTgxaWImVENwO1gxfTtmXkw9c2drJntVZUEKemlYNU8p
OXp2R0FFUWt2aXtmRn1CVCppfUJOXiZ+QytKc2pQXk5MIzJOUz87T3RmRXMzKzg5anlwST19Pyp0
WkZiCnpLQ1QpcnNUIXtpS1g7fT1abFE3ZzRENXV4P3FJZHZkQz45PWRLMT5ndUlmJGY0bmcpUF5p
LWxGRypgTXVRPXh9awp6MFd0OURGXmE7QjtxNWVNU2xVdXQ8cloqJUlRQSNiUUluUjNoPEBne19O
WWBlSDdhRHJKVitRJnNLaUo3dTJaPFoKejFgT0w/TGBFMnRoI09xY05td3xUJCUlKyptLVdXM1dv
MzBTU3slR3U7KlVpXiFgQjlETUdofW4pdkUoPF8pPXUqCnpsc3xqTlpwYDFpREVKYko2ZmdAcCVf
TEBzJk8mWHVVOXFkWk1oV0g7YElrcUYzJmNTRmYxYEl8THZCKGx1eGBxbAp6d09rKkZnXks7RHVM
UEZrVnxHeWhRYURrWmo1dzU1b0tVJiF3QFlKdmFtOUJVeVo9M2djRWBRNCFATj8hLUxediMKejsy
S2p+KlN7U3VIOzdEcHxJdlpxeDBPd3lsejlAaCMqYmh3azQkdGlgbzAzbnA+NF9gPXd+cUhDcDhB
JjJ0QmZSCnp5ZlRafj1ubTxLVSg+PFZDRm5KUntNdXA3Yj9zMyQxPUoqQjc4IXk2YXMjMT5BcTB8
WE4mMWc7NndEN2RGNGtadQp6bEFBayQybllDbiF7eS1Hc1BMSk9wKnZ7ZDNEeHJCVykqQG5ySjst
IzJ+Uz1sTDBYWCZHZyliOFd9YTBKeU5ZIWcKemcyeHVid0t5VUMxLTYhZCpeNjFaSmFIPUFXc2Vy
ZzAwd3JfJD5Ec303emlKeUBAMUNtaUFSSiZrN2xmQk1fTUF7CnoxPz94ZT9MVXZhOHc7T31sITF3
Y2J7ZVM4bkomSiVjWkFDJUJ4Nzg8enheKTx0d3s0P0l0M0dheGlVaXpSYyUtSwp6JlAtaHxfUHlY
bjFnSSU1cW1fMEZlWTF4dXFiJX53cUcjSHhYfn0yXjdqXmB0Z3t6JUkxPz9fQkQ8O09MVXtQaFIK
enVoZih+eUA4cVJgaHdrQ144MWZFM0VANHx7fDItPzZDazVVSmp2NzUjPT9EQUdvVTZ+dTlOYiZS
bnchTDV1Qn0pCnpjJCo4TVJ1dlBKPTduKHtQaFJFa3IxRjwkRXhEZTFmbCE7LVRweGYjKnVZYHRU
TVU0bmprMlh2JCgqSCsze2x3SAp6JSEqPnYhPWExdSEqJWglcEk0KmRHKGg0KCRob1VmKENzXzdM
R0tBc3JLPH12OyYzVHxxNCU1TlVkPUsjbWQ/eDQKemhjRE8oRW5VNEFZcUBIZXpjeEBYXjBaKVZK
dnklYENPb0VfRlZUZGJoO3FzWmVKdilqSCRFPSpMZF5qQ0heYnI1Cno3Qnkoe2s9ZDklWUw/Y0Yr
TDVwSFFRQDU4dm9+ayFHTjNUR1R6YkAmcWk9OVc8KytYU1YtTjhTJmtOKytBSGdJPgp6VVM9X0pS
VSRYODY5PF9Kc0E4NmlrTnUyLU4/dUlIKWxuP2U9OXVfcS1OMW5kdVg3cllMXjQwR1Z1bzI2YjBu
KigKejxpS3U8R3F7MyNIen1XJE9NPkVqP3x4aEQxQ3IzaGd0dlIzSVhRIzEkUlJIa2c3dDNeaDBz
a0c4WE5AZmA2PnAmCnpjU3RNSU5aSk9FX31gem1FJlRHJjk8NVJ7UWJHIW4oVlUwV0lufkxGZEs2
emoyYylnSkk/PXd6PndhQnp6ZiQzZQp6SWFEY1VMQHEhZilQQCM+T2laWWlRK35eanY4QFlecEMq
KVIhXjg8U2M4I0lIYUB3KSE+d3NkdHl6WFBnaCRxeHMKel5keFg5bT59VU40TXJCSzJ9PXdXLUZQ
SXBaNElXZTYoVSpFblpHflVucC1pMHF3eXI3dDZxP2wmMUxpSjMpcSEtCno2MD0+QzUwMCZLJTJS
I2xuWXFrcEVMPW1DNkUqI1E/UWV1Vl5NR012JUVIV2pFKWwyWjhtUTsjaVI0U2FeSW1fLQp6REk4
cCE2NFp7MlJ2dDUobDN6N205JHpiMyE+YFhEdkp6eHA4QUxHYGBQNGBEc1pVZ2xVZ21jfnd0SyNz
RmoxVFEKend3ZS0yUmZ0KzU1U0V3UHBYUWV3QWNrJmE3ZypENTY7X0IwPU5qfFRINXAzQm5RSm5l
VzslP2FkZGpuNkA1YDxiCnprfGl8OyQxQWI0QiRKYmU+KXI5KHZAOH5wNFM9fjRwa01iQFprJmpS
UX4yfUU3PTl0Rl44VVBldE0qcU11Zlo+awp6XjQ4fVRnISlBel9OdTg5ZT5qSXtFVip5dGlUeWtq
R2Nna3NyQVRaNFYqaSN1JTw9RV93NWVmZFRCIV4jViYkXjcKelZPbWE7KHpXVDlodSMpfGpAam1m
cERDRV5iVkJXMUgzT3tAKXBxdGpgRnc+bDI7dTdLandFMlE9UGJLSU9zc19jCnpDdkF5MUpLWmhQ
VTEzJkBBO1paJSF7MTM3Xl4zLXhFKmxrRCVBUVJBczIqME1DPmdYZj5PKDVPTCg0X1Q1PEV+dQp6
SD53MXF2MiViJmdGNShEZnB1WCtTQ0ItRjkxTjJ1SlBpamVaaUNWMCZ5MU5Bek5zKiZCJHlYb1RI
ekN8MytkPVAKeiFUQnU3ZlolV01LVH1QMEl3RX50UWA5cVpmZyg+MmRhMjt8PjYhR0NnKWljNWsq
KlIqOUVzTlg4ZT85N0VVQlByCnp3U3d3bypmNnNnQDlyWSU5XnxeY2BsLS1UO1BUWXoyc3BZRil5
ey0lJEB8Z0MkIzYjeVFHUXU3bVU5YlZRZyhPYAp6YnJNTlI1P2AqPCokaSpIWGJsIXdtPWs3NjE9
MkZvJUFqZm1mY0BpZ14qUio3aUVxZzRWM31sIWFfT2BHITZOJlIKejU/I09EYzU4NGowNFFPYko4
aTYwLW5eZ1R6O0RmK0tFb0BhMVRDekx2RXRza2JURTB5ODBSY0l0MnlOPGl3ZjZMCnpqdEl3QjZN
M29eWD53ZmhWQEN+aHJhSGVHcWEofUhXdEdeNlYyfXpKNihwN00pe0VVc3lAVSR+ZkhDfDJ0al44
ZQp6e055TFc/KXJVbEhPQUMkUzl4QHZ7LThuaGdGeTB2RWlsYnJUaTJDcmMyPjtVbV9BVnxpe2Vj
enJ6S1ItZ0ZldzUKeih3PjdmTGpYb2BfclhKYmZpfXREZzZrJjVFKyZsRmItbE1xJlE3Mjt1Y3Ih
R2c0dl5jXzZMPDZod1QzPSZwYnI2Cnp5YXFoWXMrcVZTcV9BO2hEUU18QEU1MV5LbWJqUHBQXlM/
THZBdilENytVRGtYOE13ODMmQmQxMTttSS1WeUZFTAp6eypIRXorLXVnMFVIfm9VMzx3WDBIfTRL
Y0spWFBPe2NNQD1CdGJANT1VbG43YD0kSzc8MG5WQmA/ZGxvJklXVGMKeml8NHp2bCR5antKJXhW
VGB8QkdkNX0xJUpOcXR0NSl4TihAKnl5TlZtfj1mRjFTTjRXR0YtQE9BV31pVihGaGM7CnpSbmB2
PTFkeUNvR3lNaUU2TWImS0VsTGRwOW1LQmxIVGJQTHFoSUBjPClXNzZQcWFSJnJJWCtzT2oxTlZS
cTZ4Nwp6I3FMaUN2QTNLaVQrfXgtJkJedn0+Y1daVUVKY1FnK2N8SihiRnt0SVVlSmQxb2FUbFFQ
Yjd5UXg9I3dkemhud0gKemNOKW1QK0ptOVIkVGlBTGIkKVlZNms/Wn5ad3RrckA4MipOayQ3PyFs
JHFOMForU1lHPWpWU2slcFUrbWJNKFUtCnpiZWI5KFQkaGgqezhnRShnXiZYJXdCYVJqNFhoUl9n
bDtCbWEoKGFSe3d9fm4lWkQtMCh2cFgmVSZvPXtBOHdedQp6V2pYN2hlakxlVlpqLXRCRVdmfDAl
UFQ3YDZIaDk2THApSmBDUTkhY2BQRD91Pk4lSy0+YHhoUEJ2THtNWUdKWUMKelBtZGZYK0hhT0Bh
PlhlOEBpKHU9YTlQYl9CPzkqWDteKyVPWSNyfWxNMytBfFB4QU8wVmtobCZUfnE3cEwzUUcmCnpt
cih0azdvTUE1QDZvcih5fEdhKVdzYSFBdlRyIW9rZ0pmQiU+fHhFMXp6cUprNUBOTj08Z0sqOyVv
LTdgJD9SfQp6JGBXPG5jN3d0S1VzYCFAS3ZPRlpTVkQhPk5zKj5ra3UyaENZaXF7d3c1WFRSO1Eh
PHA8K2trSXR3KlpxT19eP2gKekc3fHlDRl42Q2xyd05rT0NjRSM1YnVRPktLVEtTd1FvQ1kpKkB5
N2JDemMlNVduIyVsKzw4TGNBWnptTmRjcVZFCnpDbTghK2NxZyFRQShSQ28jV0BsQHREbjhfemZW
N3lsLSl8JnB4TH00PDRkMytsZEJlbUclTjVzYGtXUmltdV5pdgp6ZS1zVSlTPkE7Z0QqOTI/eW5U
JXxtTUt0OFVGQk53M3RJR3k4WkoyMD9oQj5IKm1LfHxTeFlBNzE/IUlScVl9TC0KejYxQHZZKlh2
KlBfNGpWTFQmODRZOWZ2YyNWRGRAY292Yj0xQyNVX19ufjlmeTlOJTcrWSVHQz9gSmZPUUVgVklF
CnpJO0g2UVlyfWkxLU9qJGx3cVQ8JihAcUZYb1E8JFhjc05GSWNaSW1gVC0tKDFkKj99IzdFWWx9
RWpoT1d4M2p1aAp6aWNaLSpBP1dHPTxUNiVVTEBFXj5lcSQ1aUQ+XkcjentXTTIhblNoem94fWZw
RWxsZkBoZ2N6XyomVzxASk0qY2oKellkPUdgRF98c0hBbUF2KWRfI1Y5QyoyP2BKWiZJfkBXRDc+
K3lWNFpSJGpGezJ5XzJUZiZUZitjdUJJPmBJJDU1Cno7M1V4TjFRY2o5bklvMXpANWM9NDhrK3Fa
P2pITWViMT1sd3dRY1NFeC1aYj5gJD4zOytfaGRUOEZvJHp5Vjs/LQp6PDI+N1kmMzhmZjw+aDdD
S3A/aUAhQUNTS096X31XTmw5MX52YDI+bSs5Pms/cDt9OWpwd3FuOWp7Rj4tMkpVJE4KelFYUjAt
QHYhekhAYj5tKjVzbCo/MTBIZjA2bStPT0swNEFRdG14UTtsWWt0PkxGaSs1Mkp3TikrLUlNfmdq
cG9OCnpuOyV3bkp8OTE8MTFBR092a00jNV80OF4kX1lRRjZsUi0qeU0tfWReQl8jXjtSbUx3SGZ6
SzUwa2ZQdEBlRWQlOwp6PX1FO2pxUGskei10TGIzNDJPLVUlI0dLNVhZWSZrTGB7LSVqWlVAaDlV
KjlRZlgpNzd1NCZoMUZ4dlZ7QT9VcUYKenFKUjJkNmgkIXVGSmJxOVcoRFhuMW9aTnB0WlUtZ21x
N1EpaXpVZ0Y4ayhGMGh3SV50TDcocjlUbjkkS3k+NE1TCnorbDdQdl9DamhANHB2dzc5bVhaelcq
MCEwI1I2ez1iM14yOStnRnN4RzQyIUZFWjs/UUkmY29NcG5AZz9wNE8wNwp6Y1Jfd0VffV5yMXY9
MTFGUkV7MWkoOHlIN2MlTWBAdkEtLTFpQz1rN2lyJDwkTD1FNSQrSmM2fGhZfmp7OGReSSMKenZY
ZmNqLW5TVVV1aV9zfXl3Xk5BSTF4QD5rK3lCd3JpbH5xS0p9SllgUilBJj5lcm9zZkI7e0gzSHdV
RT9ObjRUCnp3czdlemNRcUMjS1ItV3ZoeHNmPmk9cCR8MjtvZT8rdm5OfCZ9TkN0P0d6WC04MnIl
cigyQEZqWVNaO3Q/cW1wQAp6V1lTZih0KCtCdWU7ZiVhWDtDNnpwb1gjdl4kOFk9SUFpWjRZbVMl
OGgwYzVMdUlMQDIqeHVvO2c7Xm5jVWV1N1IKemFGMzRISj41WHQqK0VzJT5jWWF0KkdodVFoUTIx
RTgoeDc0Z1lzWlg/Vko2KEI7OU99OFBoZWRtJnh9TUUmSEYtCnpDVj5pME01ND4/RT52cTBjfVhQ
Z0pGelBnY2tAamhQdTJ7JVpyNTFDWk5kYSpTPykxSUtCRDhIP2ohb2Z0IS1fRgp6KzVYcE02a1Mo
PzA+KWtrWWhCTyVMfDV2Y2liMF5VLUJsbmgkdVF3e0pIJklyXytodiYmZmpHeWMwS2gmNnJIUlEK
ejRmUGJ5dEVnQmBwUFhXN2I7RXBGV28zKzkpUTFpQ2RtKT9tci0hY2g0aUhQfkM/e01ZTURKX0pB
TmgzdjR2S1UwCnptZysoXj0oT2hIZTcpbWsrb0RGMVkkJTItTklLdVljWno0ISZTLVI3Uj5jaGM/
Q2d4eT0rOTxWcVBvfiFgTnFxLQp6Y1BHelIoaEpTWjZaSnR5Kyohcj4mJDhVazBWZzY9ezxxVSU4
eXlZe0lWXyl3RUlNX3t4M1dtTjsxSEMqRjVFb1MKekdvczNwNm5JYkFSKnFRSik7QUhCTVNXbXZ6
cEl+QmRtbnMlPilMbzdOIXd7SHVGcldfT21sK09xT0chcGFjZCNWCnplY2ZlSFpAWmglLVQzMnEo
JiFOTzxBKWtZPlpvdWViKFRBMGsmeiMlaC0jV3NefmtJZHVXVG1mYiVDNiRMblRUZAp6YGdkcylW
RyQ3dXtaQH5xSU1kaGRoSztBMClYck8lQX16YnUoK1pyeGtSfDRuXypWZTVANnkzKDEtTzJiO3x8
XmEKej4rJDtmTS1HK2BROHFmdiQmTVcrTGsyNkhARllreWowa3l5LXhTbT8oa25UWmN1Mjh7cjtE
U1hLRl8+KEdXKm9lCno2SWwqaGFxciRkODdMP1deKzdrJj8wJEZyOFQ1S3I0Y1pnOFJBQ3g8aWIx
IXBRK353dytEN3MoRWZheHI1UFFoPQp6ZTIzIXdAZmVCUj1XQEhWNkxOIXloJldsTEdnfEpAO0hR
OHUqWTZ0TGZRYl9wOV98MHpRcnN4Y012RWp3UnlaIyYKelhePT0yOCRRJXJrdzI0bztzN25Qd1k4
TnpMIWtOfnNLSF5mPiFkRkM/UjF8S3hva2Y2LSNMK2RCQ3poaEh9ZWRVCnpHYkxhUUsjMkBuei1h
JCswRD5HbUhMWkVBbHNUPlZzV1lYcjM/K3tpU3dtWXRsKmttO1QqKTV2UExeZWQhRCFoeAp6NFR3
MWIoPEVyWlQ5S18+dEAhWCNBblpgTUM7IWVTNE1zOzZ7T2RfSiFeWWkrUUkwUEVuK3dTSyNXfmM9
JUtDODUKem59JTBGRj4xc091OEhPZzJ7PVpxKk1YT2t0a2w1KnBGWkU2KU9CPXBuQiZWcW59M1h9
R2gzY3AjYnk9aEUkTlY5CnozNGkxcCk+PGptZTt2O3QoSFE7ODw0UUl9T1VKeHB5UExEMGJUfkFf
RHk9fitUYFMwV28jOEpQWiZPQjtZNHJnbwp6LVhud2EwS1E5TCt5YW18RWpae3tvRXY2PyR4VXk1
JTBVVjNnI1ExQT12bm1GY1Jse1UhNEsjdzJHQ1kqZlJkYj0KS1k/WldHQGMja2JjYEJSJAoKbGl0
ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlX2xv
Z28ucG5nIGIvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlX2xvZ28ucG5nCm5ldyBmaWxlIG1vZGUgMTAw
NjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLjM1ZGRh
ZjY5NzZhNzUyODRiOTMyZWUwNzIxZjFiYjMwZjU4ODE3NmEKR0lUIGJpbmFyeSBwYXRjaApsaXRl
cmFsIDEwMjA4CnpjbWVIdFgqZ1QkKlk4SDMobXV2Jil2UFY1Qz80fHx3NXE3MD05IX1BbEE1TylJ
eV9WckhQQGBCQVM1KmVIS2xDfgp6RWsjN2tRJWo4emJFcUtSb3UyRHwmZ2JfIUFJfHlrLXEpNGZX
YmI/THdTSEBALSYqKERKTnwqODQlMno9XjhmJWEKej5GTTR2MFJURSgwSEQhaUkxQnl+RHtmWl5Q
VW9LSlNfYzNDR2x1JTE+NDg9fTApT05SKVYyeVZnfU1jWElRaEUqCnpBdDUxPnAxJDR6RT4ySGVD
ODdUQXhmXlFTMEJ7QSt5S35EZEc+PHFGQC0lfXFiR20pTnI3Uks9Y1pUNnkjN2hiTgp6MlgtO2Q/
cn1DSyQle0g4dm12JXFNYEt9QT8/PiV6O3E1Z2VFdlJQcmI5MSYhM19NJntTPjB9UE9kTTRjNHM7
fjEKek5zRi1sXlJyaHUzP2poN2V8QD1TQVkpTEVwSmhJUSg5K1N2IU51am0wMTVfTlgmc0BYJllJ
OSRTN15YRkNTSEA0CnpgYWs9I0d0fXVpP0skZG58STd2SV5vfkpASXttezJZN0dEbnVmMyZDcFlI
dDZMTWpnYjlkS1kmKDg9WW1VTkxsYQp6Yj4wdll5TjYpTjshVjt6P0hfbSRzZz1mXiVaPG01MyEm
JHI2TH47UCRHQE9PXzl8WmZSJH1fVGc4YVRtO1Z6VzcKejV8a2x9M3JwK09yV25ocElaUWxfYGJO
bTtBKCs7KUp4SDVfRXlYeDBTaWEwbGt3bEdgcmNRY2dTZWpMPWYxPTRxCnomc3QzfGhkPChzOWck
KUpTWXRzYFlCcyVve1RrUDRUcHx5aDdScHowWmE5MVd4X0ozZSQ7PDE9OUMjSX48NiV9fgp6Q1Nx
c19jZmtqI1QqT0NgN2xWNFA/fWY2bHZBc0BDRmghP2RCcERINSkjK3dGQXYlP0hXIUNDflBrMEA8
ZkZofDYKeitJUEZSakdoMjdQJDN4XmxnbWNBbTRDemZhVzk9UD43JjJXaD8qI3lVYV5MIUpxblEp
RWs9YnxtcHZuY3ZmR3wqCnpCPEM+WCtCLU8oMUYlZT5XU152U1JoJnpHbTMlc3VeOFBXZVdPNnU2
KDchYjloXlNjPDRpQUVNSTg0QD8pNyNgIQp6XlJvam5sN2dUWT5VNm8pdU83KTdqbnBqTFJzOGhp
bEchSV9MN314Py1kPzJqMGZUVS0wfWYmWnlmT1NmMDNAOVEKejllZD9NWllodTM7ODZaJGA+Sk97
ZW1rNHZCR0ZGcVViKHJYPyptZEtTUjFOcHp0SVlFOVJUSlM2NkMtJkQtbWYlCnpjJlV6dkdPfnpw
VW5AJHA7M1RaLXBrZHs2NFYpRENgTDZ1JEhqODhpNVh+UXE3bDB6dTd3bD1JJkkyZWVwNTVxZQp6
XnBXcGpAYTIwUUczdylKUXd7cnIlR2NiNFlKTjUjIyNiOCo4a0pXY3JoPiorbXNnVVlfSn4oNFhB
YyNZI2oqSX0KensyPSlqWihAJilQMFFkSzh4NjMrWDZILX5jKH50amUobGh7OW1nJT5Scj1JJXNu
NkUjSV85NmYtVkw+ck0/P3s/CnpVO1prOUNNT2pOcE4/RXZ6Mnc9enhhbkFmU3RIOW40X31MdEwz
a24zd21mPWNgVmxEPDBRUXU/cGYwKSpYUFI2UAp6Uk1gPSpFeGZaU28qNlJiYDtGbFN5NCsrZVk4
JGNSNGdWd00hZ0VkOTc8SXxkaT0oITR0PTRIcSVHUj82aHZ6UzUKei1qaXVTNnlNMmBpbTwpWkhZ
NSVkdjBReCVlKDVLXzklPnlzKSlhJnBxPWJ5entZJVZDaHw5Kk4mVHtQT0hlIylQCno4VmNmVzMp
KigyPFpSRk5tQVNFKl9zYGdTelNUUm96c1UqTGl7JjZybHUhOSplZFNAV2Y/TlpEOXpNYGFrPVUp
QAp6TFhufUVYaS11Myh6ZD5fejYkVFJrNSoyS15JTCl6RkJ+JD9HWFBre2k1aCtZYz1GV3NQUzt3
MHBSZFd6QDFkUWcKenMwamBvSUxrI3NgNlU1WDlVdytNaypiQno+PntvPjBYYlU0NCpTfGwqNXtI
Qk5AZXReUjQ/ak5rNCFqRjB3WE1wCnozVWxQMGJXQ05JUU0qLTFHNWF0M19EWXt5dkF2bnM/UTdT
NE1uWXw9bTtpa3NgQylhQXFrMjdhR0FBOU1rPyglPAp6TlBsJFdBIWtkI05WRk49JUtaPCo9bEAq
bWxlVj5CKDh2Y3I4QWRHYHA+Sj1VSUxaMzZIdG0pVCEpeDBCdXAkcCkKeiE0Uk18ZV87PjFfbU9Z
aiEkM1BlM2hudUVXUHR8MiFkWjB6KjZ3Tk14Qn5UNndKc0lHJCp2U0JSJXxxcV42RWZeCno3V207
IVVGeT01U1dzMFBVckMoVGpva35TKiFXYWRlaDYwc2ZOKHoweWtFQFIwYHEoWVdYclU4RlVnT3Rl
VV5hTgp6QFVzOWg0antZN3sxWV5vSzc1aCozajV3cWg+THRrOT5qay07LWRqckZNXk9lY35DeVIm
KFV+VChaUjJpVGc5PzYKenJ+TWEpNWp+KX0zSHF6JXlJTVZScGBSPj9xJEk8KmBiXj91Tyg4ODFR
JCY/VCl9NHZCSmcrbUkqe2A3O1ZYe2VfCnpiTnZIQDdubjkpVyh6RmNDJGozS3pTbjYpNz1RWTQz
fVA2azF6d0YpODZ2MmttUCF0S1JVJjRURmVeNmdNMF40Twp6RjlFOWJVOzcwYExTNn1DLWZ8R1hT
P1lnK3srfWF2P3dZLUVKSyFscl9NfFhzQSZFMD9lLTFIRjdqLXQoLXxjZlUKempaPlBtYn1SYHBG
WigwNyRDYkNobUhUISVrVUF9MUpzaSlgamBidURORSVAM3kyQUx6PT5HNyMteG5oeE5zSmg1Cnot
T2U/QWNSSnVvSXUtaH0xS2pgSWA4OzNvWkZ5dyFvK09lRUQxdVlmcSFTX1dqOSpROXF6ZjAqd2B5
a3dWb0VlWQp6TVA0UU4tfVVlfTM2RTFzV3NHI19uOFF0d3VneFowMjUkMyFmTGA/dHpaV34qSUVv
JSVOZCkhanNGckxCWjB6e3oKelJ2JTZhZHtQOCt1STRMTShWJj5wQnRJYnhIaV8mZHRePjtPaXo+
cj5fd359aDU9JUpITW59MTg1KFZKaHUoenFGCnpeS2omMXVPPG1xN0lvWj5AX2pgRXtIVU93e2x6
WGdQTnJvMzteWCt1ODc1VGJ6KiNgXjIzNShJT3p7UzlHMzc9Mgp6UGM2ZjlzYDxkSHUhOHdvbFl4
Z2pqWi1kM05RPFA3JXFSaGtwR3d1d3NkRDNNaz40WHVsTlZ6eXRCKmxyVG14fnYKelpTX1gqdyNr
LW9od19VdnpeNVVRVzNJZ0hRcCYlekBieFlKIWpgb3ZGOTJNOTEtY2IwMmpMOV53fmg/cyQ5M2pF
CnpOTH5hWmg0bzdAaz9sTihQVT13YkFzXmBVRCUxPHdZPUk2VytXb1UzNyRuISp0Vz1iJEtYM2pH
dTJySm1xTHltMQp6bW0/OTdUTU4zVzdYK3N7M18pYyl7d09uWSlDUyk3QTRhQzZyMjBTd2E1M0FU
I1kzQ3NBQ3l3QkdSNDE2bntsZlQKelIwal8qe1c7TH5RUGhLMUZaTFNJKDZ6YXdoOEsqMHdeWXwt
bT5SS1NtckcqNEpOI2lLUkpgWHVoPF4hSTlSMjJnCno9NlFGRFAtNDc2cWtvJXZkOyZNa200LWlo
c0xgTyReQUtLaXIjTnh1V1dWIVc0Mj97NkI3eVoxXmQoaHlPWURQXgp6MFM+UXNJcGFvYjNZMDIo
JnwhWXBvQ0JAelpMZmAwbDZpRWFkanRQbE53V1N3cDUpZ0R6WHg5SHlHS3EyZXJ9VEgKemgqZFFO
bDxPLU0rfEMrPVdTWW5pN0gqeGAoZzQlP1lXfntJcUdacX5zOFk9NTlJTXlCbTA5Skk5JnZKV3I0
Pm1fCno+djAlT0Q0dD09Xlo7VFc9enkydHZ+bj0jbH1vWllieT1DO2BeO2ZEcmcmJFAmbXRMd3t3
eV5acExIJCVvOE8obgp6eGNhNXh2OWZoUExQejs5PDI+Tj40QmJ6Mmg0RkRFKCMqbCQ5MUhyZnU8
QUBzdUcqKEI9UDxjNVpsO2wreWgpczMKeih4UTYleVU+IXltUktjfi1gb0EhJUdGbn5TfnktYHhE
RWdXdmoyJWVwMGRfb2lmPSRDYGlnekdhd29xeGIjNylyCnpHSXh6RzNmfVhkYk05b3JeYT9GNihJ
PUw/STFyaFVkR2U7cUdgOEB1PHMwdGlIZkc/PFM8ckEhemJlMHwxI3k0Pwp6Izdsb3U1dGhjeGko
PXcxWmZScCtheVNiVkBsY18tc303ZU8lOSRMUFc3bXRfSkZVQ150dj9rJTw4MWUrXzxWYiEKek1L
WUsrQEJTZWxrLXdYUUtfblNuVFV7RWl4Umlwbz5OcGRwJmxJJSpwXmJTJF5AVnFiNj9NOHtCPjd0
bEQtWSEpCnp6SChONlBPMFRFOyt9TjczIzxCTWBvSHdQT0ZkNm8yK3xDN2YlIWVzXmBCVExqfSs8
RSlvJmUwYjFmdXxGJm8odgp6NG1iZjszdSs4JDZgRVpsVXx0cytaZmVVZ2RmdjZHXjZsa3gtN2JB
RV43JHZPO19EZnJNYGVCWk1MPzZ+ND08ZXIKejR+RVBDWlU9cShycE9Ffnk0MDxeJXYjMCRoVHIo
KDdBMTk0ZnczJGIkYSRiQmp2QzxRdU9XJXkmWm11clZCQjQ4CnpiczgzXnlEbVBsKzg4e31EbE9I
Qi1telVYVFI1PSMtKURESTk4IUBJaTZmdl5LZUVmclY3QWQqR1dKOHZuSDJScgp6UURhZj1VI359
ZCVqcW5WWEBRa25SRzZmWll9b3cyI0xicz9NWGgtR2p6YkB0NzRyfHxsciErNElpN1BaQ1hNQmQK
ejJURH1VaWxhWns3eTtHK1VQQm1SJXpfMlBTWG4qX3hnVytZcntWVnl0S0BacCN7IWxPO0M7eD1q
cC12MyVxZClLCnpDNEtEbUJ0djJwYWErTCghVkliY25oczA5P3R3NzFkMT5vWGFeWGR7djFXflhX
XkMoMWBqMSFHOVd2ZFcpWTR+Ywp6TG9HNlg5fjkoOVJ1YW5uO1hPMH1GRmgjYTkkTyFRI2x6PFFZ
WjwhfkRoV3VUYHtFN3BBSElmMCtFfFhscShwZXUKelVYTlVnZV89bEZKPDFkR0BBPGNIMEliTjlU
NGl2WjFQJDdFMChFO1QkNGV6cWFDYzJMcEpVOTM8JmxCJDg7c3tSCnplKUp0e2NCJUxVZGlkbiNQ
flMrekZJaWZQPFRIU2hBIXk0THQraXV5aVJsYkBhYl8kQ2B2WSQhZ0x1N0JteDx3WQp6SGE2Rjdk
ezQzZ3UyT29uPDtHUTA1PjI1KSNjWWltMjE+RjVWaXZ4RitiZkpiOWYwaiY0RE1OfWR8I2piPmpf
QloKelRBMGQjJjApeHE7JVp2VVIjWDdxQlVrSVAkUnAyWVJTUXk3QTtzOWQ9PXwmXjEzPX5sMUJx
TzUtP0QrQzdUUipRCnpyQzFkVmwlRSZoelBBKVZTY3xXRjhpdntPdUxyfVdCamF0RVJqYUFGZFU2
NEJxVU85fiFpV25FYUZaSU0wLTAtcAp6Z3BfcXBaWkB1dlBXPXI9JSE0VFg4aClfPlEtXkBXdUN4
JUFyV3dTcmk7TnNaTU8jNnlZP2g8X0xBeVNSMX5+JHoKemZ0JUN9QlhIUn1XUjA/M25adWJNSXUz
R0lsJmBNN1J8NHNkYiUpcFNkITdwPSpBe3wmKk1ZOXdFVXR9eHhzfUQ3Cno4ODdDU2I2aGZqPGBg
JlAwQSZBfVMhamMjO2Vncz5VTX43OWBtRmF9Z19mcmtIP1o/TF5LV2V5QmB7b05oa2tUJgp6XylF
azRIdlQrZnNNNHpxNGpeQjtnSDlmITBQOEZ4eFlLb3VjNWYmPj1LWUlWZER2X2JJei00Zys2eSpG
djd2MWIKej4xdmAzK3tvdzdNTSRUZFRncUwkKkg0MzxNTSZWNkdQanhedT54RURwYWUwJkdTYGF0
O0xxNlFSQWVaeGB+cGBSCno/P29yZlIqQih0UHtMSmYhZl5EMmszd1Eja0VjYW9QSGM8d2wodTZu
KGlteTZZMz9lT2VGP3ktUXBJNC1RKXJkRQp6LTswOzgjOVZYQDtGVjZJamt+JFFgdTJUfDBte2I0
dmRXY0ltTmA5fncoJG80WWVndVpIS1Vwe2NRfihCSzF1RGEKeld9I3hIcj91OXs8RmphNThofVda
Izt7Q2ZyYlhTU2Q4eU1xUCZDUEEoQH57NDhVTiRKKTVSMn1BYUNnelYyWE9KCnpXJm58S0ZZU050
dzR1WmwpYUNWMyl4cCF5dmVsWm8rdEArQmhHTzYzRDQhPSEzan43MklLVnM5QGIwMzBuI3o1eAp6
PjAwfXc2M3dgeUVKcEp+JG1GQ1FKV18mNVkrcz9XYkZCME5ibDE0TyQpcCVsN0IhJC1ycm4mZV52
Yk1KK34hMkUKeipmczY+ej1nTUY+cHU4WUAmJUJKMm94d1lhSFgyNnZ0O2hZezhEayNTUCEjRFV5
T1Q8LUtTe0pTS3V+eyg9PmBXCnpGdEZHZCQ5fGZePEo0KHxSeSYwX0pCMyM4NTlofipBSl9NaDVS
TEk4TUhIcCE+c1lBfjtVMjIyP0N4PEw5VDR+egp6TmFJUmc+P0xWfFBWLWpgLXJQJj9jVC0oYlFm
WmM4bTF8JlQqTm1IM1FseT1uSEd2SXNfbzlZUHEyQ1ZaMG9FMlUKejx+flg1YCFAJWcqeVJ8OzZK
YnwzbD1LJVdATUcxZSMwO0E7diQ3Vj1tNXlmO3okWTchNHZLNmF3WXRhJnQ3dDJ5CnpvYTZxUGxz
ND19NypnOGQxZXIjenM7SkQrKjRFMnhvdFhYQzYjJDYqODxiQHdTVGZnTUBZO2doYih2Yyl0YCVw
bgp6dkRJOUo9PzcwRmk2JE0jek5lI2JXUTY2S3xNRD89MjZLb3xXNzB1MmdCeF52WUQqO1BAM3tW
UUR2bW1MI0FZfFYKej58O0p9eXEkNzBFJHpSbTZgTW0jQmhOITRQeWNqPmxWOz4+bzdrPkc8KEpL
JGtPWGw1TGUoRH0qWi0lekBfKmV6CnpHS0E5dWZiSSghYHFrJlZRWSpOUSNZTlpmTVUtVlMqfUpv
K2hmcG9NPzdqNWVucF4yJShmcT1LblctKU9gRXl6Ywp6JDZDOUR0ZWVMQWBUPCE8XjNJKE1gTnt8
UF4+QmBiJE1FQipReyV5YWlobVUpKD1rNz5CS2pKbU9BQHYlZHdKZG4Kek57NiR2diNRJDB3dyFx
TTVwJklWYF51I3lNMDxnanRHZz45SDk9fnFeQm50I2whUTR5KHVpSit4dVc5MzFNdlYkCnp1Znh9
dXM7VXJjeExPbGE2VmxBKSg8YzMrKFVGbldpUkEqd1N7TXk1KD97KkpTd1lTS2RxTVJeMXZPY1lw
X1RlYQp6elQ/ZmUrelVldHZ5eSU0Q2p5NmA9TFl0JFkmXkpxYHpoP20rfXZ7WXJ3JWBFdHt7QnZS
WnJYMl5TPz5JVTd9TmoKem5FMksyQEYmQ2ljRil2JV9aV1YoX2RXUnkoLV8qN1FreUdWdUl7JWxk
R3FGdFZiZDVNemUxdGs5NVhkS1pTTT0xCno0bS0qeEJVUGhzITBMQ1NINWt2KF9HYlRNZmtMNWwp
TW0lP1lIZkJYXk9CTG8kYlhPSVR0PyZWM3FiQ1pySXozQQp6LSVGQXFSVl4pSyE9fGpQdGVgYHk7
OHkhJl59U2I7QUFldWEhK31gcztyZ1YhWDI/dWMyIXhybGJEaDZgX3NWZz0KejtQODV5SjMkZG1v
fEY4YDFpR149QjB4eDM+PVZ7d2o/PkRmcWhEKGE3JkxXdUY1YU5AJi1nM2xod25nKl9fdmtECno+
O3IwfGMxaV5GUSMtNlc+O3tpX3hybyEmTVAlflh2YSZNSW9sLXA/X3NxdSVRXnRkYk8pIWQpdDg0
ITBgcjZ1Qgp6NjhSa3Z2cTd6TnJGUXBaUGFrLUNkTiVQQV9OUlFJMl9eTFc7aEhSdm9lIzluSzMk
RGkkNHYlIz9Aakx4dTZBPEMKej95WD53Z1pzdUgxczJ0SWxeUG45PD4ySSpmVnVZWTZPPVokd0Ra
ZlRKJmVIVztwR0JURWlEJlYmeGF7dSVMMDlxCnplKExQZTR+UnRiWUlwRCkzPShuUkxDUDUrUG5u
Kj1oRHo+TWVxM0ZWbnUkMmYkWkJ2VWpGdj80MTMhS3tyPD9eQwp6T3U0d1lUNlh0VWg0aUdfazVs
PFdTM1Y9VmozZE0/NVAwazV5dlZrMGZebWo8TSN9LV5OSnlgP1J5cyQ7YjwqaVQKekFZRUQ0KUFL
fH5aeEZycCNSK1dgSHF9XyFISD9lSSY7c0Y/czZ7cFkwTkcrQW5XZ1c1dzJXQHZvUngmWT5aPERF
CnpVQEIyTkl+Xip2WCg8SSE8QkBgYkdkPTxsP1gmIzNVPD5VQ09neWFSaFM/Qz8pUHw+QkowJmVw
UTlHZ1EqUDl9egp6JE1KI1ZrJCkkZ3BXP2BBe0BGclU0QSQ5U2M/YHROQ1BhVzhvVUNsY2tiKXtX
VHk+X3l3YTwrPmpVcyZMYDdyVUEKeko2Rn4pd0lLPmFfUldfdnZrVXpCdWE1dzlCSyZ0NWhLSE0q
Z3cjSThFb1J2eCFVQzIoNTk8YT1gPm1UXmhkWUJQCnpVLTB5Z0JKMWZCRnN+Sj9RQC16OTJnR3F8
WEJXTGFNZ3UmUnJJdkZ0MlBaJGJ2TT91V2lmSF9SVjcxKDM5djtDZwp6Jn1GSkJsKDBWYXF+SUYo
eGEoUyNJMShRO1crekBybnlxXk57SkVnfCFEVGUxRUh5UFBhNVVScFI4VWFzWnZAKGIKemBibGtZ
PjB5P2pKZ0tGaVJ2YWdEdk9AMEhwWEBCN21EY3k7X2BgSWdwWj1oQHMzLXRNTV97Vk1fVDQ7dTVe
ck9wCno7JnxyYUdHYXpZRXEwMURCSjM8N0BpV3E+ZXtoM2I4NUtOY151bCtsLTk2YkN5fUt7VDJk
a3wkOS1EZDY/c21Ucgp6NWlxRTF3N1dFNTkmRkpsPG9TRStDJTV8M1d7JW5CMmcmT0Q2JnRPbSR2
VGlfb0tZNWt1cWJxWnBHST8mVDg+SFcKenJXTVlSNX5XdEZZTDM8bj96XzBTcGpVT1RtVkVxWmpZ
NyV5JlVJKyVRfGorWHdmI1BKJH5zX25iTS19N0VHP35OCnpmb2tHI1dZNkFUPn5iTGt5IVBTV2cj
Qjl1Z08tVVFSVVc0bE4lVlctdCZyMFYtXnwwYUZ8NT5eYVBFWXZpQWhQQgp6K1NxNj9AdT1YfXtL
RH05OHxeeUw8bFZ5WFUqbEJEak5VJV9eRXYqOFVMJWdwblNrLT1ZYVFCV09uKDhtQktQNG4KekFN
bW5yKzhpI1ZDK2p8dCtWNTUkbnVFMWBAU3E0Kjctb3x5X2h7PjNTNUo/djhYSGd+MHdUeS0/aHc3
cHE9KTtsCnp7PHZTK0M4PXhwV25BUkhwaikoRnYqUiFYX1l8VmtKdyt1OE0+SUJnO2RDP2xOUj5u
Z2BLX3AqUUEkOXpCVmF2aQp6OEZyR0VRJnJKJXZTSVQ9ZE01VnZreWg9TWxFNHBmPk1+TEU5NU5T
YlVyfUN1LUllKH0tV0d7fHwxbl9jWjJQcUQKemU1WVBHV253dy0wSl9vbSgxY0tTcGctb1dwWEs/
UEckdDtyVCF6XlB5WHAza2l6NiteYilYa1AoWXUpLTR7VT1pCno7d1FXeGJtPjVVQlVzY3g9R0Mp
YiY8Q3dYVnxOPlVoQz9MTF9sLTEyPjIrc2FTMGBZRiNANSFBcWN3OXlZZEshUgp6Kk0rPiskOVh7
ayh1RmU4KHxKajR0cyVTPTE4OyVvZEIyJkgpO1dIWFV2a3M7WFc4VV9CKmhZYWUyN2VNXjJ1JDQK
ejRxQ2RubDtDaFVJajc/QFd3NTQjWEgmSDxhZy07VTVTXz9sN0xESXF1YTU0JlEhfU9+Vn47Rm9H
QDtaISVzYm9xCnpWM2VXcWlQPW91bVJzWno0a2B8VCp6WFJpKXo3R19oN2ZUSFF0amk3NDdWSWpF
Z1RUN2x4M0w4TFc4V18oWFRYbAp6MXJaJlcwUktzJXNrd2NicjkrckQzeHhjXiVpQ0wzODhqdy07
K21pZkJSbWNPY3JgR3dPdjVwNkRFRDtsbjs4VjUKemc0Yl84QGJqeDNhVXBTb1UzQFRRI144cEJH
amVqdVZgSS09QjErKX5APkxmUGo7TmhORUMjSF8hMH1IbDJwdV43CnpJfWJOTiReeXMjZ0dXWXgz
V1d5NmZYVm4/RV9vWktNNWJgaEF2ai1TR094bnpkaU1lJHozYHU/dFAlVil6N2NlOQp6Jm9BVEtJ
bnU2R0lGbHAyU1RqM3w7PkN+UjRlfWFORGBOPnN1U1kjYTNYNnZYP34xQlJJKjx9Y2xNV3hXMWYq
PU0KekNSLStoanxPdG9PPG5GTDtXfj0xTmwtJWRUNzl6VldhTGxaZDwrbFNqdH48UyZrKlZfMnVx
RTFWO1BjX2Z7ZCphCnpAPFlnVyFvb3RVOEgkcj1pYEUmMEQ3JU9eP3EmUXZlWjRkVDEjPmZ0aWkk
XlF8RkxRbCZvSnhPazlVKUslZ2BESgp6JDs+P2g8SXluI0lSV0xGUGpeeiopKEM7JCFZJjdeXnhj
WCRmM1MpJXE3MUpGVGkkdFRtP04jZigzNTI5ZF49VUcKejBIb2A3OWVvWVFObmVEUHlWNjRYRmtT
PHFDN0VSI0w/VFVFSFc8TjI1dStXJlVqenJ9MEhyQUUqNDk7cW8pS1RWCnolYFU5aFhTd0ojKmEw
Q243T0VlYUNHekQ5Zj5LKH0rMkp7SyFPVEMwSntCe2BSPGdFal5jbVNQN2s2ISVsOF5kcwp6SDR+
MXg5bDB8QjNuJGlTNk8taHhsJVJjV3BWVks9bGRRMnpnVlNBRnltJFhUP3Q3KGRBbnVKZG5Ke2VS
d1kqXjsKel9kVD1uOH5iKDdgUX4kRWU/cGQrcV5SZHFDYVZDRmByR1BxcEFoUC1pTig/dDE3NXxT
QUNNdGRgPmRxUkltaHE/CnpjdSNTMGFsX1Vta0d4I09objx9ISZ3Z155UEJgU0E7bDBzeHkpXm1G
MklaRTY2blpsPXlTKSorckdzX0N7RFJIMAp6NGF5ZTxMTkA3QktTaihAQF9wWGgrYyVYSUIoJnxm
LVF4NFBlPVJHZ2Q+UkV1YDM+TGc+aEFWakQ7M1I9Y1puXkMKeisqWW9jWTN9ZWpKP0dOMThWZzY1
ZFJrfFhNdCpjSz11ZjwtWEVAdn15Jnl6d29qYiUqenJIU1BTNS05WSU5aGBVCnpVZUApaV8yWDdt
KFYxI29fV29XbUxAV3FjO0BYdlNvcXlFNnpsN2ZWdyVqKyNmNFlAK3heaTRVRm1mIXI8UWVAZgp6
RGwoPEB3aDYpZD9PJkZUUWtaYE4yUWRlZyNaXjEtPChudEU4Z2ArcjlDbmZVUTR5eVFGT1NEY2p9
KCUqeHBATDkKeiN7cWw0V1RRN3ojLWN8O0kkLVBIWjt8XjxqUktXK1E3aWUxYS1oSFcxV3M0Mmk5
diRDVDJyNFhMaVNvVXlpOH1eCnpCKktwcDJNUi05Y19XKGRpR0tTUXpPdD0+SS0wbWlAcmRWZTJx
ezYzSHhBNn5ZPk1ZYHFvSHtMWXJLM0YpcCZ1Xgp6eSU7cUk9b0NkRSpGYWlZeEBTKVgwM2RPSFk2
RntFNi0hZVFxcy15TTV3eHA7cyNCRjAhN0hOKWZ9Wkt7JjlWKH0KekQ/fGBnfERObWB5MHN9OFdt
TStzc15VRzZUe3JQS3dYYHd+Q01GP29vLWk5JFpfbGV8NSpnWDw1VmNfNSl6IVdGCnppYF5ZSHda
dzh9WiNHV0E8TE4qcygqWENoMGRpbWIjYVUrRCVpNHYjcH1PUTM0amh+ZVhaOCt6ckNPZUwhJkkz
Qgp6V2JPO2JDMVJzOXFvI2o7RlgkblI+Pn1INCM5YGlsZ3lqJElob2JSam0kS0hPbXZ2SVhyPGBq
OUxVUHxVNVE2fUYKenN6cTVnT0A4QCMlJl9qfEh7S0VKb3Q0OEd0LSU/TGY+X19WdDFzeHEjbCVj
XzZybHteKXRYbXw1Xlghb3s3dmQpCnphS3BsU0U7YDl6eDBtZHtue30oT3pXcmV3Y1d6Ril0T15Y
JWNuS2IwNGw/ckoxTF9BPmp0KCZZeU5NfTZIUCZiZgp6TGotQGNpJSEhKHFtJHtAV2BNU04rNCtP
WmpxUFhrS3djUExWSm5mQmJneTB5anZ+QChMVkpYUjBqJDJmeXJNVXoKekpXPDdPRXdFOykqfSoj
N2RRR2VSMkd+cmNjY1EpdlArMEsoXmt7aWItZ2o/Ml9eNGN7T2dCfGJPI0I3a3owfDs+Cno7QGhk
fEllQXN7c1RhekdNQnQ1eE1vZjAlMyRXM24/ZlMxdFRBSiRQenQ3TnlBSDRfKCFrQ1lGZm8/aDNC
SnJEKwp6d2RiMCFhJUlxTD9Abi1YdERVNFdaJktzbmlNbkgpeyVGKzZhQUFtMmYldW5eI1FMJiNf
Mnoqc2dVPz17Y1hmNjkKek0pWmV3NEhya1psVWpUYGU0bFlSKU4yfl9fZk9WQ2smUWxjPD89a0Vt
MzM5U2dfblUoK3wtS0JTPT9mSVpJcCpZCno0NVVwRiErZ1h7TDxxZFAmQ1Y8T0M/IylUXm9mVihj
M305O1dTRG05dU98JSFUXzJ8U2MwIS1gNyo3U1glPzQtdgp6PUpOdVBuNnohU3lxcCg9MDdFXjlC
K1FxQjg2dU0mKlAkWWdaNzx0WlRNeFQ4TXQxeUtVP0Q5PFkmSnl0YT5sQVYKeioweTFgYVZFb1ot
c0lZdWRjMmJZT3pXQVpyVU1jPTlCREp6Rjw3SUtfVH1WWEdWdnJEK3YmJEg9WjVFR2BxbiRUCnoh
WF9CQktZZDdFN01KcHY+N0VUS1g5VVBIVkEyWSZKJF9FQ0xSNX1jYklIbUY/VkpuV29yQldQQVE2
YjVwdkxxbwp6P2goeFE2YjVEWnJrZ3JDOUpKX0pRdV5KfW9IJWI0cmxxRXI9MWZpJk9AWXNsWSZZ
OVdyWn1kSHpiJU1WYnEkQioKekBnPFVEa3EtTENldHVJNm8yVHlhbkcmYkI0UG1DSWtwI1k1Z3s/
d2dhbm9RWFFMb2JVfDdhSiEpcFVUMFNVK0h5CnpnYFdzX1JuXnBfJkc9ZkhJSCF1S0M/fSsrcmU4
eWpQNUI7QCU5cT9+dG4lVFl7fFcxOSl5MXVsO2ZTRzJTcXxrQQp6UTtvYXxrNzxDTyVhXnQyR15O
fSlXQnRidnF0QD08KH1zV0lDbGQrSkg9NFhSYE1GfT5mM317Oz1sOWtQWmZ0V3YKej9oflEqKCtg
Jm0/RU97cGR3SmgtMSlpMzYzSkdfTGMjSVg7LSlobn5uY2FXdEduSW5lVGBIVWtjM2FEeHsyMCtC
Cno8b1VxT3FQMGdIRWB+eVM2ck1qZ1NnI3ZiRkVtTyVBeGFTYFdAZX52Pl8mU3tlYjlibih5TGU0
cUcjRVlKYF4+VAp6ZGhiQz1pSWE2eFpFYkJhaCh5VmhCT1VOIzlOZUtgYClhSihPO20lNGMlOHpp
PmhraVhxOVplTk9WOG9he3Yzc3sKenM8ViZ3SGF8cG1WeDZlJERuOW5CKlFIPDs+X0M9MWpWaEU+
SStgdkBwdHBPbkFDXzc9WHp8bzx7QlNtVyk0cl4lCnpkPF9pazxvJlkwUCs8ZlA+UTFeXmNFQWlB
T314N3ZYSn1+X2VGbVdpJVJqZ1pmKmdHeGZKOEo8cHo3JEcpcnR2Tgp6JlI1VmVIYTUwdEpnI3It
JHhIZmkqfUw8T2ooJSNKSTw8eX1RaFRDT0F6O1crKWVMdnZqKTxHdFRwVipXKWlOIUsKemRhQHRe
UnVMXjE9R29LSi08NnVXPChLbEgoVkRMR3lgJntIeTJUdzxUejVOUkhwOyQ0PU1CemFZYFc7YGd3
e29OCnp6TE0oaUh8LTwzTW5FLVImbUx7UDViUWA8RXJeVjBAWX5KZUV8Z1ZZMj9qR1RtPX1ZN3Ik
S0p+dyZwQ0hnR0lNKAp6Um5Ofm1sTkpQeW84MGJhQk8zNSNUfEhnaTReTi12TTZCYFpyTUAyKyNP
X144P2tTMXgqbDdiaDVySThsWX57bSQKei1SU0Q+dGNuaGdtNHV2TCVaRyQ/ajg7Mk5aNnJFeHco
UlAoWX59NkJKQzhwQj9SYFVEU1IwbHZYQTNJYGQ8X3ktCnpSY1hVc0dueUlEVHlDWlpIPWxRYzN7
ZD1gPnJWRko2eiFJSStjX1V3cC0lKm9TQVQzIV8oe0l2KVhaZjt5fjMjTgp6azZ2RGN6fFJ4UXM4
JUdic14jOGJKR3QxUitHZTUqZDlyYEI+R2dEPXgkKGVDQzRHMW1QcUs2dns8JkBMWkFyK14Keis3
QXIxT0ZiWEZpSzl6flJEKXp7RzxVU2BOKnM3WHdjSmVDQ1pXVmdWKn5laSN3VEZiOyQkXm1nT0l1
X2g0V0ZJCnpwNTcxRGEoT1goXyt5VDU8MyhAWjs0b2ZLI0FEVm9WM0hxWHl+JjI0ZFdXelI2dnA4
LUopbEgrb1JUN2ErfExMJgp6VUI/aj52UHU9cTlFXnY4dCFJNzszMTFnZ3hOYyEhVjQoNkt0WXxy
SXthVnZoUyRnUzNXblJPUChVR2UxI19xTTAKeiQ8RlI+RzEwNVd7Sy0wdG0qXzd0b0tjeGsxZXRC
eSZ1PUh4Iz8wSlE1R3Y5S3J2c3t+dVgwZGRvQzREJUlSNTgjCmpDQD5YKDxOeGEmTC17R29eIWJ4
SlErfkQ7UjlXQDM0ZXVhc0tZYWRRQjhKTEgKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAt
LWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9wLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNsaXBz
ZV9wLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwLi4xMjE2MzhhYzEwMjcxMDBhMjI1ZTM4NzRjYjc3YTkwN2U3MjM5
MzI0CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAxOTExNQp6Y21lSWFoZ1ZadyZeSD51aVY4TUJz
VlgyITZfTVVsNUNvKFhMSTxUdT8/Z0syQlBka0BwJTt9VmdvTkc9cGglTm0KejU7e21QMFV7Kj9M
aTt3KWQrKXBNcEsjWj1wMHk7d2JJdmFGbzA7RnRwMWx0cndLU0EzKEs2RlFBZHBLYyZsUG5iCno1
TlpQbWd5eEBmWFRYKCFIQkF9dGI+OCo0cCQ3eSkqTDNuaikjfiFpM1M3TURgT0xzbSpUdSNZez9n
cVYwKkF1fAp6P1ZLR3ZFTUt9PjMlYT01cm1vOHtMbTs7eER2RDNeLWxWTmchMk1aQz5CayNuZUo1
Pn4xZ0R5QFk3MHgoQTdiQTMKemE8QURfRks0QHZfajYyd1U2Jkl4T3JFPjk9MWlEQWY0LUA5VFQ8
Zk9kOCgoa0V7RVQ1Tmc4ZnghTk52WG9HSm5XCnpnOV5EaVRBdE5XKS1qTHZlZFZZfVorNUsqYV4y
aVJyak9oVj50UU5DMT9GYSV3I04+PjhsQkphZ1JpRmxLTDExRAp6S0xxfG07NkRXWnpYKig8YTNv
aUw4diR4KW07NzViVnhHSj1QaHhCKllfdChiWlJUQHZMaj5mfFk7NWFuRUxaY2oKel5VYmVIamBt
dztId05XRHshXjxrdXxofXNoTnt5d29zZ3ZeV2hjYjdUaC1VZ0t1KDc/UWgmT3BrKjVufktyK2h+
Cno9O00kYFVWLX5pQUdgZUQ5bCFQVGpkJlkrJGhyRyhTVCFWQj1+TklzJUx1T2JhcHpTSylgc0RS
JWNwZj1AVHlVMQp6RGNvUnhWUXp2QW8xT2hTY0gtLUV1N3wmaEU8PlctY20xRjZPKHtUJW5Icnt3
YFlJfDRQOzVFMXFlZkJyRUlIYVoKelFDYHY+YllgZEUqRFVubzclSTRmR2pvaFBiQVVVdTFBR2Mo
Yl9tMV8rJFNCe2w9MiZ2Ujl9emoyPE5mbE11Yy07CnpyUkFPdHVWcXpMMTs0Sm1fO25wRmNedyg9
RGFvTEFfcXhobTI4fFltQEt5JVpVKVB0VCVDMFJodEBnKn0tYktIZQp6d3t7dy1tdH5yfDNsVkdL
R2t9Ql5PNUV0cC1ualAyP20kc0pTd2VlMkRNbExfWVl1JVQybFlNVkJ7U3ZedHw3LXAKentEeTcm
YnNuPERHU0dJY3RSTTJRWVRwXm0zYXc7WmI4X2dMajIydDdiSFFiRmk/SjsmPnYpdGEzLW88M3Zi
XiVfCno+VnxJakVYa0spZG1uMElRZlA3T15Kbj9iNzdzb25FSn1FUGNabFpaRHBlcSU/b3lfenpq
ZWt7MyhCKCVhPTRwJAp6Y3tlWUU4QVNwR1I2ZjQtSXNZMXVlZ0UkSDZ6VGJrVUhLZSZRYjhxM2Rv
JUBxRGY0YTtJUCVxYSslQGdlM04/TWQKemNWRX1pUlYoM3FCUktUVllYZ15aYVhWZVYycitvJlFx
KyEoKTAjYz45PWtMdGp7Zk4qVys/ZFE7SjI/Kjx0Q05SCnpFNXhVKDRuXjcqNnpHezY9NF9UZUw+
cTA5Wl9DUj1pWCQjSmV2VV5ieXZFLWdAY0o/QztXQGMmJGI5WGRjRG5xeAp6UzVAUkNySUtvZHh8
NkN7Nj5sSEBIWSFWM3BObktha2dAS0t3cy1DJnRWSjImMjB4UzVxR2w1NUEkMm5oezE2X2YKend0
bFhNTz9OLV4wOzl1XmMpSjRuZ20xYWBac242bmBIRH41VE1gRTR5VmdgSXlgUSlMIT5AOF8rVzhS
dXZncFlCCnpPXzc8cylIblFWaUEtfV4kbFVkaSh8PkxSSGtkRF8yVUpkQ1NNTFpVSnlNXmc9NjB0
YW89O3B8KFZ4LUVMUj9iTQp6fDZKLWojM08obWIkX25PS0FMNDR5XjNxdVMmI3syZlA2QVAjUnlV
OWtFaSV6a0FIU31Ib3R3QVZxfHV8c3RJPm8KelYrQmhAb01sR0pqREolIXd6YW8qRj5xUmItQUNo
Qndla2FOSmF+RCV5TEFjalZEKy1XVj1CSjtiU28yVGkzSUdUCnpkRz81OURAUTxMQ081WnFVSHRJ
YVhSREB7aDc7NUVJN0dHKzg9NWspOV85UHkqcWQjMmBGR0Q+JlVrQVRZfkJ2Rgp6aDI8JG10PkMr
Wl8/MWUmcUphdnYkKihEb0h+S1dXNVVQKEotN2dgM01ubmw5M1hja0NkOU0xRnpOYHU/XkxWR3YK
ekk/X1k2YWBPJSpffiZCX3M/JH5APHVAcy1JRn0oR2tEaTF2QTVXJndJREchRU50JHE/e0dJMGda
ZWU2TllHUShvCnpHUDJgRW5VWGFnV1NAMGhnZ20kYjI4QiRAeHhebXJyQm8zKj8rKitmQmxQLXBI
dmhiQWhPZXJuWWZMOTRYN2dodwp6ZUhHOz1jNTA3YFR+Y1Q0JW4pWkZ2fV9AI2h2TnNQZHlmdE0+
eihWUypfZnEkVSR7SXIpVmNISlNHfEpqPk0jJUEKel4jbShZRTBUTTs9ZEFacUx1Rnh+Z1RTUmQ3
SXVofDFvZWdERjllJXpvY05TbSsxKGZFY2s7PVhmO090Sj8kaCZACnoxUVpvIXllMXxuJiN2cT4/
UWNoc2diMVdjUE1fcVBra3gtMHNVN0VqLXhuZEY7cDJ0dkJEUVVQZXZje2BxVkNyUgp6Izlafkcl
WilCdG5QTnheTT1qRDUyZGN5aDJVR0EoS0IrOF9SWHxkWDdKK0x3NCojLW80NmcyTiZBSH4kbk49
WkYKenhPWVZGbH57KXJKfH5oNiYtfXRzQEphITg2U1VhREh4R25GWG9BelA3Jk07S0g9Ry00RmJs
Kl5kWFh5Sl9YNl5mCnoyfDImTUNeZEB7PDhmP0t3UWVwWjYtc3tGTD5BYUcpN1RLLU9TalV+a2hV
fF83akFeZVh5bk5+XiFwK2dIMHVZSQp6dWBAWlFTVUo+UFA0JkxsSCFnVGRNaTxIYkViamNGPWFe
QXwlWWVPQyVVNzJgRWw5Qk5EYUhwcyh+TTx9PGdwdHgKekRkbnlpdFkkRz4/Y3NfSFFgTSZKRyt7
Q0kjPkZ3KlhsSj0+WHx3JVF2OHQqJFlhN1ZETjEpTnVjd2ExSzE8fHFuCnpoMlo9Tm0wS0RWRiFT
ZE14MG9aNkFxc21SPE5IZVphSzhtY25sZTdfVVZqV315QTdzQ0NDRFBKQjQ0fDQkUTtuawp6K0sl
KFA/MDJ0bG0ocnl3UisqYSs2TT9kJlRmQG1XPl9xTl9Ob190NWhGbGl8TzxHaUMlcUEtNCtfQUgw
U2NoYjgKekJeO2dlWXd9RjwpYkwmSXRORWZkR3JWYVoydmNIKHtYdEhMYiVeaXdyeSlMMUVVMjBX
NCt7RHlkcjt6RndzcGtaCnp4JE1jP3VpeVUrTV5EXkM8elIjQUxmazU5dStLT0c9RmVtTUBiT19F
aDBfY2VuRygpeWVyJSk7eTsoSm9BSmRhbQp6QnhMM243akMxemM1TTh4dVF6Kl9CQV8kM0Jue2Mw
YEhrMylMcHk5MjV6T19vJHh3bW9WbCVYRExTVUxvRW9XND4KekowZ21QZW50cSFtc1JTTmFgREEj
eV8pc3ItZUs9PTxhPGJOaFFqIUJqbS1+SD49Ty1+RSo+PEg9eDFQPnpZd0QoCnpsPSpxXzBfV3ZC
bEhySD4paG8zM0R7Wm4wcWNQVzdhNjg+JTBaWXhUPHZIJkxnZG1Oc1ByPnR6WExHeXo7Ni1tegp6
NTRJTWN2bk5gcWQ8K1A/OSVTamFAXzZVa0ZXbEB8QDBEdnNNXkg5eDRZMF4reClnR0hQUD0hdUZO
Vj1IbXlubnQKekx7MSp5JTJRQV4zVWBedmBMJT0xa0JXfXFRJWs1WGR6bipUd0VeOD1lKihGWWFn
UDYlcnFiUiElRWJGMnlVRE4zCno/JkBwVWFkbnc1IXpvZCE/OUxoajk4OW8yRTBkfVFOOyYmQDg4
YGhrOHB4VDVNKFJ4cTh6MUMpLVJAZFN2OFZRbQp6ZypQZVY/TXNyY0E9fHtzNVUzcGsxQ0JTLSFv
YSQzYWQ2VD1gVDwhO2RPdytYYkdaNEYwSWwoP1hKeURpYUdAI2AKek5ebVN6cjFaRGIpenpiODZT
OzhOVjsoMT5WQEdRbkI+MiU0Z1U1N096Zkp4Q211MkxwUHpJbH07WVk2ZktFPks0Cno2eyo9KTQ9
ZWlJKyR5a1RQO3Q1YXZuUWw+KCZRcHcjQXlINXFsVDFxTTh9K3xlPGY/cTZCUWx6PENvMk5DcGwo
bAp6WWNubigrR2IqUm1CVU03SlV1M3MzVWMjS2FXSEdPN29JdmBldGgwdEQxfWQxPHVNfEQrKFdE
Nih3R0pfdGYtMHwKenVpaGhEMj5BWClofHU2aD5lNXhiO2V+QV5jVmIoPnh7Mmk1ZDxXWFEtbUFM
KVRpdE9qeFJyJT56S2RIeUk8fUQ+CnpDUkJ+ajYpbVU/d0BFJldnanRXb0h0ZXBXPGlSc1VfT0Q5
V2FGLUZ9czcyJVpscEgtMXJgSGFIZSk9KmAhU207bwp6ITFKNSRZWmpMKyVYKk9lPDdMcTt4UHxt
XmFefmFtV0Fwc3hOdCk1QXo0MGRkMnFreTwyYXZgYXcpSk5ydDRveyUKemlfNmlIWUlCQVU+Vy02
OHp3b2tvaypFcE5IUSV1XmBoNE41ellpTkJrZ1JrM2ptMUdwYTxIa2lwcGJENytjc14oCnp5REY7
ZGxHKGZYSTNsQ1cpcGgoPj1LZWNvLSMxbWFBajRFNHIqQ1lweDBpVj85P1pNPEJudkpzKntrVDNl
bGFZJAp6V1VSfVFiXz9Uc1JYRUBldStFfTdQQklNKnIxV2hnXitpTG0weURWNGNZfTQyeVh9KEJA
bSVmcCZicTVhbXU9Rz0KeiFgND00enY+RjdrYk00NzNkXlIqQmdpZDJGcWAwO15IMilPN15BSzIx
d0RTQmlqRWUxMjZLNnl7Xmp0TDhAQ34pCnp6bX4hRzs3XyFGPFY4cl5veWxrQ0Y4MTlFKGp1Rj5W
cFYwST17eTRkVTswekhTc3lGZEppYC0oR0l1bURAfmd5agp6Mz1CVEA8eVVpOypweGx9eitKKz57
PDlhUTN6R0k2XygyeGFSSko1VDE9Zk1UZUxleUNCNFpQWSFnWW10OSpQOE0Kekp4WHBuPzFjbXUm
TkFAZFFsTHxqbW0heTAmaStPZXpXRS1zcTNETFlhZWdAPUBkJjZVSUxocko8RUprJUohd1VSCno3
RU9YX0RkbExXO216MFRhUEJ4dFNSKHQtbWtmK2FHJWNofW5FRkNuVzJyV1lHR25PYm13MUs9aFM7
dn41P1l5Vwp6Y18qMkE0ZjJXTzZ5dkFkbDh+IzF7PiNTbS1jbT5uNldPdDE3fT9Qe2ItPDdjdklo
dnYmUSZee3ZSOGBJZ1UtUkUKeis7Q1NmNXc0KiFuRXg2PVBOS3RPVzt3NWdJfEFSQihWakReMnhv
SXJJYkIlSU1MTmlKVDBsaEU5dz1vKG9OV2ZtCnpiOU16YkNjWSRlN1FXITkwZU80YHFST3BQdmgw
VUxHa2tPSV90NGMreSVZSUc9JUN4UzlATFB+diFMWmFMRlRSewp6Y2FpYkE0NnhHZDk8K34hWF5C
RGkhWVJsX2Bjc1VxJSF5SXkqe09GbUdeSGBYXmBCfDdqdzh6P3NVU15mTHIka1gKentuJn5NR0Ix
YHt0RzUzYk59QmlMYX5JPSpTaUhHaTlJVShoZCEqeDBpK1AmOWlBc09zNUpwUWtufTxnUGpLQEtK
CnpMRTxCS2coV0hFekRJdkZZUkhJZ0lZYyhxO35eKCMyUiFsR0pAPVl6Pn1lKHJRe2xHaVFtYlY/
MmxLZ3F6Q3lKQQp6b2E2czxOPV87dUJSNV9Ab0FKeXw3JFdEYXdAWThhZmBWbDc3MDNnQkFmdWJU
S2g9YmsjfW9WOFFQczR+dVdHbFYKemtwSkhNZXNacn4yQTsxZkdnJl9LeUVIcX4oTDlnbE9MdG49
ZEJ+MFdiTm0qO2xKbGF6dC1xNChUQXxBUDFzcERoCnphc0xYKTVfMDtZPipCJE1jfDlWQClpKyVi
IT9vT01Kb0hVfnZBeWRQQj19YGFCZWshb2xuc0lyOGx6cTdoR1ZgJgp6JFhJam01YUVKWURCZGNE
c0wtaW8lNll7ME5BYW1wZElXLUNKVlB1MVByIWYoNDY4SkJRNGhaKExAJFBzdmVaOEcKelQ/fVA/
YVNuMXI8c0FSQD99STRWOz1neWUpRVh2aHAwSmc/dTJlbitpRnxPMWsjXkUrSHJMTWtTdzs1dDN+
JDJvCnpsfF5hJXFMbVYpdkYpa0ZtcD5DeWR8bzx6eiRPeTV7fmtHfGshY35XUGVHSD55e3J+SDRJ
bE1VSCpPV1VpKmFKYQp6NilGaGw8JmdKcGNsd3FXdCoqbVIjPzBtUVhrakshWUtZUDs+STxoR2pP
XllnNDV7bll4Pj44IyFpUVNeb21XMVgKelM3RDUxQ1hlek5IeWxJNnZnVXIoe3x1flhAI1BsTUh7
NyRTK0Q7akVAZ2FiUj4/ZStyPyo5MFUzY3tsZFpla3QhCnpGWVpsYjNfZkxjPEw+Q2spYGAhKlFp
UG12K3t2dyghb2pGVnYtWlplRU44MXxBUX07a1BrJEl7aTVpdTRwYSFBPQp6WDAhRTl8MD1LYWlv
cmJ6YW1AXipIbjFia3ZsNyo4NUxhSXlucmlQX3BCRXxNWSppaTtqQWJtUHFNfVQ2VWpjfEEKejFI
X213P1RmcWE+S0VeOSh2RCE0WWd+VDxZNWE1OTtOSEVWbjlQQ35HcGVRQWkzKVhQYXZZRkdifDZ+
aHN+QmFiCnpYeSMwOTZSPHcmUGwhJTFpOThQfXJVS299e3VZaiNfb3pLdmMrPHFoNVJxWCY5Q3cx
QipifEV7N0FDVVpFNVNLRwp6VDlJNmA5JmdNbVRXS0p9PUshcEs7NUEtUG9DMWhDekhTVV5UcUs9
PWtiZ1RuND8zSXZvPkdFTVkqNyl5U2c5ME0KenU8SS1Icih+JjZMQSlPV0YhK203S1pBSzheaEcm
M2ZCWFoxTlomNWp4LTV1YzBkckRHJj0oY0EzVkk5KU1xZjU0CnojJX0hM1FLd0IlUUkqSD10TkVo
bVVGbVg5TDU5elZvRjEjSWNLKThkSiolMmZvfDZUMkR0WjNESDtoZVc/YEJuKAp6YS1wNE48S3Uy
cEwzVzs2e01jZENrSjZaVUVgczUqM296RUR5OUBkTjhHfHV1PiNRaG4qcG9yVXlkTiFFWCtWT3AK
elY5PChaJkA3UT96NzltQ3J+QmEoJFlhVm17JFpvel4oWGh5KWQ9cGozdHJ6dTcoM2UyQVB+Ulgj
VEV7V2RWfEB7CnoqfXl4P09WVkxRNUopbihYc2kqWUFmayRUN3x5M01JeXNSTjJncVliIVF3fmQt
N3sob287ZXUjQnhqKTckQFQ3NAp6ZEhfNSheQFUyJnZVMWhyN05vVnxEQVMheygxK1dpQUxOIz9P
IyhFUjRUY1lmdiN3d0F2aHFgZTFnbWUqR0NEZncKejgkd3I8JkgjJip4PE98aHBhY24peTwkKnx6
VyphVTU8cDV2X1Qpbyt1bmw/KzJeS2lIPj5LMXBMfmpFPjhONHgjCno8QVhlMjBLKHthI2hPI1dT
Sj9ocFpiNGUqT0VQeWlDcVc+b2NaeDA0V0AmUE1LZi1ZM0JPOXE5N2VRRHdXQGZ0QQp6RXJIPXo+
NTZAaHcqe348e20tPjczN31PY1ZZNDY5NVVjM013Km9sRSk0bmJfOUR0KnxzVl9odG9JMXRtbXx4
bksKel9oTUVSQCQ7a0F8RiRnSFgwJkRuakdLZ1BxZU1hPWB6SiModSR2I1JkNGRQT3N7Qyh2UCsj
MjtxemJVWHVXOEx9Cnp8NCg9MHZtRnVgRjEzPGI7c3daSzxgWEZ6PWNULSMwWiZzPzRGfVVibmE1
ZitufSNHP2JRV0tLQiVqS3IjSTdhewp6PGRmdFBXNjBXQHYtUTVuQ25oUWdLYTA7KWtXWTYzPF4j
dG94fW1eTGJ6LS13T35HV2NMcVBqQ1kyQ00qcCkxMG0KenB6fCtNKEw+QXFTfklfT1QoVXV7K25e
XldZaTFaaVoqfXV1M3Z+aGpyQHd3RW9ESiooPktrNHYjeysydV5nNjc7CnpwTHwwSDd9Zjlke0lg
VDhUN18yTWcwOGJNb0psPz1EcDtuN0dvTCl0WmxDc2tWKTRXS1JSRUtIX1g3YTxfLXhPQAp6MmNR
SmJWaGQ/RXpJLWNwaV5uLWt1bW89Q285fjkxKkJ9O1AoZD9LbiZFOWhZZnUoPVF6bV84YXEhXyRQ
KDlRKjkKek4wcTBIV0gta3owdUB+WUR6Y0F5RkF8TmFyemFpRjZuM0EzNm9hJUtKbz1IPHdDeHR+
MGh0aTZndTQ3Y2tMaWooCnpqTzEoWUh7ZHdBY0piZTlOfTw9bSRtK0U1Uig+eWwlPmZ+RUlIeH5s
Y0xFKlIjT3FtazA3SHlBeGZtZHV0XmlEMgp6aXFxZ09QYWc2TiMzfnFBIVd2OyZiKXBUM3EoK3Em
TWwlN2pQMmRufWBAVHxQKklAeWZuZTB+THc7e0l6UE5iMSEKeilgIWRCOGA0aG5Ze1BpWDAxfmA/
Vno0eVJnVSZ5SjtVc3VeK2olQUEwZkRYbmNPVUpXa09NSURjayFXT0JUbC10CnoxR1p6RkRyR0Ro
VXlhRFZUQlNWailfUjJQST5iVTZiblQjUHRHMSNQPlZ+VXc0PldZejI/YyN6Sj9VY3tfaSpsewp6
NDxTX2gwPGRfTmxQPiVlKHBTUDt7U3FJNzF3I0shc3JDcHYxSD9pRWJrY3orTUB4SUw+SH5EdTNp
eFBXYHhlWFcKemdYR1dnVUVeQ2MrUmxNaCRBcEJJWD5qLVNLNkBINk9iZFdCbyhReVIpVWc0fFZB
Nn4zSXZGN0tnZGs5MzZsJVVMCnpVP0JxYyhBcChxPkdPN2cxY0MxSGJqbllxRjBYQHIzPXY9QCtz
JFZTa2c7JEQ8fTxsY3NpY3pKM1o0MjE2YGRgVQp6ejZXVShgPTZeIzNla0xxe21uPkEyR14zKiVt
MFEyTjgtcVcwPVRSflRSa3EtQE9JKUtOYm1yI0F3S3xrMT5jflgKej1kJnx6TlRZSTN1ZGFVX0w5
JGwtRkVOaVMoQiFpeWQ7cyNFWDJ8alpxeTh4ZVZkMC1lQmY1KXs3X040ckpFNmVkCnp0ZUZ+OyN0
YXl+eFJnfXZkJGswMyNaPXhEUjlyR09pQEl7KjZYejVzTD13Yj5UWilNRD0rfX51UEdDKWtuJmNT
JQp6MnpRTFdGcFBJUWhFaTJOMTkzeWYrZSh2Jj93bDxrPig8JmBGTTM2X0pYNjdVe3B2fXVTemI3
IzwkMEM9e2BNfjwKem0jTU1IbGZkcWVyP1o9PFo8VDBDb0o2VTBNVSRRaWM0bHxyTjIoTC1TaFVT
NnZEVlgkSmEjMzFtKjJsQGVFUCZeCnpgfHRXfjA4Kkg3JVp0UV9WYGFMRjtYVFgwJD4kenhmQjxe
MHI8XyN9ZWgyZlYxPDRoKSNvKng2Smp9MGdWT1k2Uwp6Yjswa3t0dnR8d3l3KTl6eSFibDF5R2Yz
LVFMVDA3SG9yUlVhOUdjQCZmQUgxX2ZFMnA/dHJzIVI/ezAjS31jT2QKej5NZkBzUnRtZGxobzQt
akpGNldHK05We2R0QigjJk5YPUVSWTwoOyNEOzQ4PSgwQEEzeHF8Mkc5eT84JkJvSl5wCnpMX3Ih
QDZgYHh1UyU4bHQkM3hBYlJGd0NAUzZwQFlyWSFYKkNOTTw1TEtyLXM9WmRDNF9COXZ7TnpmU0sl
cG9xVgp6N0R2cXFgIzZ2bGBiSntQQD8/ZW88KEFqb1NIOVY5Rnxva1hfbkw3PUl7SytPYnxKQkwy
PVErcGtadDR9a0lnYD0Kekg7XkF8UC0mbTZpbCpuclEwfWI3azstYldwWCl7U3VpPHtZKFg0TlVZ
PShrLVZ7fkw3ZjY8OGs9MGByMjZxZHE0Cno5Q1dyIWcjVz9NUEM7SW50XypARzlRKyp3O0AtZU8z
bEFkdDMoJEMmVz5oS35HSVVRZEJ6MDgpeml0M089X25rNAp6WiMpdkhTT2djJVZHTytpT1c9PiVx
PEU9SyslIXlLeW02R357eUwqVSloYFEoI3skZDstZ0RIWUcqalRSbXJ5SjYKenNELTdpenI2OHA8
cFp0IU9WZ0c5RjtzSkc7MVJPb1ItaEFZJmU3OHdfSkUqIW1Jcyt5ZGZNXlRqbH5SfXdXMXk3Cno3
PWhSd3t9fTNqQUdLQVhPaXh8e3tTb2k8R2JQNjBhXkB7ZE1JUyFrJDV3YjJueXVRJGRye1A+I3lD
TVBzIyhGPgp6T0VCI01TPXd6M2d8Ul9xKzdWZVJHczFsSGhKTj13VWhWZkNTeCZMaHB3bypOUEJI
Y3BsPXNEUm9ve15MUXpgSWYKelRHbDB7T3wkTDU8fiZ6YzVXY2R3a3d6NWtGPHtSbmtfcTg5YzY5
UWQtSTUhUSR4ZDhmYjh6TT1NKSNhdzloWmNXCnp6e2R+WGlnbFpedj0xQ0Y4I0Y/dSM8NUNuNGk9
QkMqPHB5ZVBvOWd2ZTBWS2t3O2s+NndMZFBMPHN+SXotdERvVQp6ek0rNFRocFRAUEpOKThTNjxl
KDtWOGxHWEtfRmJ+WnBYSmhvOztRMkpmVVMmSDFyZzB8R2BiJCkma19KNjVYYkwKekxuc2s7YiVC
ZSo3PmJGSm45Pmxge1UrT1JtX2sxKGh2WTdxPTleMjxzJkF6VldkcU1Ac0w2Y2c7MjN4MCQ1Nngk
CnpiUGYkdXc2MXNse1BsUVU7Ryo3ZzxYMFdwRil4R0xlNmQ4ZztGbj5JKUVhLXAhPlN5VkhTPDZ6
blNha3pAVVpwUQp6YCVPdHghe25RN05VMTlHTTgrNj0+Pkdva29reThSYmRSWXttTWtDY1VaV2dm
YUh7T094K2dxIStmP01obikxODQKeiN4UkFzT3xHRlMyY0RxJFg+NTlzbFdpWDxhZFpqYDtRfFgx
NipSI2ZlOzVXUTMweylMUCFmdkotLWVfTT9sTmFHCnp3VFhwZ1MwU1RkPz5rVilGTCYxPi1memxZ
ZWMlWE0rI2p6OSFaTHJJWGFWfGVZS1RsbmQlUSYmQ2YjVnVtflp3PAp6KGJ4TjBzaUBmRkVrNVZS
WUdKPyQpP1o3aXpldmFsaGJaOWtITE15RnFKajFIdlR7dz1YaHd1bC0oR2FRdHBJRFEKempjJGMt
dURDdCteRWRFZGJAZUYyIUtKc1UlVE0+aG5WSGAhMGNsMXRuKTFvejJIYipoI0BzV1ZIKXJYVkxR
Q0JjCnp7T0QhN0sxUGlBeGltKHdKby02QSNgSS1tU1BJY1JqSVVsMSFOSS1+cWNlcFBuX2xgX0hH
Wkg/Z2J+cTZfb3x3ewp6QnEtYD54XzB3ZlhhT1ooZSl7bnJ4ZTVaYjg5bkhIPChlQX4/cUhgOVJz
WUNGMUI/PmRMVWRpbSZWJUg9SGE8UWwKelk/TkgkYVFPeVQ7QEh9dWVTSHsyPWBDa1R1P2J4bUJP
e0UlUlB0QUtzYyVlMT1DcUxSKH1iaFIzNHtiS1l5U1V4Cno3OWYyKDxkRn1YMkRhIWA+NTZhNndG
QmQhRTcmV305YjA7aFo5bitIQjBBOWpicChGPCp7M2huRTU9OD0tPEV4WQp6Tk9PZ3FtJElBWVU2
Km84Jmxpdyl4bURgMkNWY2JqZ25NK1VJNF57cCZjNk45dS0yKVNtK2orQD1gajk8aTZRcDUKeks0
QU9CZ257STN3RT4jRSNkcmw1QShvPjJYVSZOMFpZdll8M1poIU5Dc1g1UnV3cVkxblJ6KTs/fF4p
enxNUnRwCnpwPXheRGhLRlZNQWt4fmhsemJZKDZEdCtGQis8cHNpe3hxK1BAfUowKTMkdz5GIWR3
JiRfTEJoO0VSdWJgQ2VEJAp6RGxnMmdnbT9BTTc3enZMQnQ0KGxyU0ItIVJkRHR2Vn0rPTFHfk4k
JHpRPlhgUXR6JmtGUTJPRSZETzdeKEdJWiEKek1lQiM8ZmBiS2FsYj5fPGImcC05NmhVLWBPSiFm
XlB8Nm8oPnwxeWNeeTc5TksrPjY/cWV2dmM4bGUrKE10citgCnpJYlgwRlBpRjxQJEl3NlgtQVYj
e1h6ZUl6a19PKjNIIW5+NDdsalUwPCRTJj9MIXM9RyohUWNoKHJMQiVqJkUoWQp6KkJRJlgqZHBJ
PUg+fitkdUc4TTIyR3hZT055dEh3d00oXyV7VWdJbyopMmlkdkhHZEp5NHB5JXFrbU0oZndBSDAK
el57O3BHYmNxNikrNHIkJCVaKEFFR3Vucj5QS2lKRD89Jjx+YWsydWwoIVE3NnQ3YVBJPiMlM1FB
WmQhfGB+X1h2CnokflYzY2o/eUQrRWF6YTkleWZnVmFCSVhrVzBKOyRjK2FUbU5XPjBlKlhqbG5K
fWtmYDhxYl9tbSspYCYydjU8cQp6MStOT3p1ISZlPDIzU0RIekBjQEBuJFM9PGhCTXFTT2BSb35X
cXhPd2g5TTMqRk5sYnpoJEs4V3MlQH4wcTVKaTgKemtCI21tRj9jWCVRSyk+QFFudlA2cDx1O04z
bG1aUkR9aEEjWlY/NVRSUyo2ITw5IWpld3xLTDBBc01OdS17YGZDCnopOSprVzRjQ3woYD9USiYw
RXkjYGE/JFpHbTJWVX5SRnowWUI0R1RZNTc2cH1eNiV2dTR1SGo/bH1rNmg4WiNLcgp6N0ktTylO
WXcwYFRkTj1YOUMkMX5MMHxCUTxnZnRnKl5TQ0NkOFgrZmxNKWdKblBYNyheVDhjeHpLKyYhcUV+
UT8KejhuZUx6Qy1+PWo3RVdGKlRyKGVuQmdYVVVuOUI/RD96QHl4ZDR1WSpWUjN6KUkkYz0jRWR4
Nmw0NWlYdGlxKihTCnoyaTJEbXRuVmV4QztXI2tAXlBrV0IxfTl7NkpQIW5hVXx+Kjs2YCNKVSVf
Nk1MSmFMZT5Id3dqOCV8OHtYTGd7PQp6WGMkXiU/SmRnSE55eWh2aWdpJFIjKUhqbmhCcXZmd0RU
dSo8eTA3KWlLI095JjAxTCpZalNDenNXYyFTZXhuZ3cKel9WYjZwNj54P2hRVDA3fmUqVSF1Zz1T
RzMjb21nd3JKRUhOYjA+Mnp2Pz49QXkyJTtTPG55IUlIPklxYyNfKGo/CnptMTJWaDhDRmp0IWNx
R30kJnNrflJRNWRHI2wqO2RNZWBEVXhHM042ZHskWj1eaklFJXkjSnprSzVNX1FvMyZ4VAp6Y14j
ZUlHeDU2OUEmeXtsUillQWE9IVA2X1FQdVIhMn1oR2wyTkhjT2dZUj5eTXo1fi0jPWVvYlYxNmwt
R2MwP0gKelNgPTlDY1UyUjE2XztvZlBjN1hGUXBAOGdeYzN4ZnJve3tIUntXbmhWYU9POVEpX3B1
dkdVYTJwdy1xZCZCKCRtCnpMTDdxS1ZYVVl3I3UwazItQ0E/aUZ9Xmo9TEFBdmBqcHhtM0NPNGJ4
JEVCdzl7ZmdWMnE1PmYlcGFSQmZlN1VlNgp6LXJBJHZ5UE9jOFVkX0NsKVYxKjt1KCRZYGthdmwz
bj1eMn5najRwTytRc19MVk8jJldGPSpXTjRCQlUzYHs9I3MKenIxQU1PQVApOHl5dTVody1BLTZL
JiNuN0BabFp0ZGc5d2hqNlV2cU9AOGpZfGU9NTNZNGFNVjhxaDh6WTtgdVNrCnp2anFhfElOflRB
XilYWk9sTHgzV0A8NytgT28rYSQmKXJ1b1Z9fUowezE5JWt5YD9hNikjfTJuLTc1dXleTF5hUwp6
Uyl4UGNsZ0lDNUxHMSYkdSlMRkJiQHRVeUpmTnwxVjRpVSVoZXhqOWVLdnZuYnpwM3ZzZ15lZSQz
PD5vOFM4KTAKejZ3ZGRwKH1TZko9IURZX2I4WnFFZHQwVmMxRyZvNV5zZF5qd18qVXQtPkFtQ04/
WlN5M2lkSCROITN5bUEycV5MCnpDeU1tfG9mQjtwJVluVEdxR1AmT0A8YFFHUGV2OEVGJjgwUWUo
RTI3KiNSRXxwLXw/bmhrVWBIVHkycGchS2EwQgp6OE8laVUhbkhNSz9FZjROe2JSSjxrKClsKzsm
bXpQUWRsPE50PWpCMmtwPChFU3crcW5iQmtsaE5DSjd5dU9qdWAKek5YV3wmeit0aVdAWXM1Pjlt
ak5yZG9UPSRuT1c5YE1rNXA3cmJMTiZqcVdwPDsmZHV5MHJOJj9DVkJTY013KCR3Cnpie0pyTU8y
RUZFQW9BMmpQTyEoLURaeGdFdCNra0NvUypESVpjSWQwUjcpTVhpU0x2WGUmQSh8Zk9gWiFuRnxG
YAp6LU8pVCpATGFTYFJOWWRTaT83Nnc5YFhCWEojZGJgYUV1YzdvKGZlSFNQRVUjMSNfaiQzYC1W
fSYkdShnWHNYNTsKem1pc2Z1PXZSYFgmckV0SGFYLW0zai1iWEZUYGYkUW5ucmxPZ353PDdTc1k5
RnU8flVtVjNnXj95dGY3OS1OX0QrCnpMRX5+aStEcFhpKzQ1M2FFMGoyNHJEQ3RITmIrcEdFc0p3
fGVvMHVjS30zJkVCYHpZb3FSfjlaQFJAYU1lYSY9SQp6M3tOeWxSOTFrWndzYHcxKH5UQVk+blFe
aDZTUVZATjxNUnByakdPTSR9VU5vR3VgKHFfREsoJVA1JlJZenU3cyUKeiVZRlZxSWdGPFliazFU
alJ+OXxxUjxBcilBfXZOTWpJdklmVztWSmlUVHBUUykzZTtha0shVFpoSHRvTUVYWHw5CnpAZGde
Ml59YWk2Z3VgVnMpdjs4MyR4fVpjVmIwQW4xRndFR1d7IzFwY1VSd0Y/M2lBdjg/SmdaNDlaYmh7
Nkp4WQp6SD03UHVKNChPdElWZypBY0pjPyt0bHRwVHkld1MyfEkrO2F6TUkjPHApXjdteT1wKUI4
KnxzYFZpbDlXO350d30KeipFVnZRLX40P3BCZUQmZzQpfTVDNUI4WmpIO1J1Mk9VKEJyQHc3THpQ
aEBsbDN7Jll9SUI3MlhqQjMmQ3RrUitjCnpDT1lPVlYzeDV2PkFuSmtnfTRhO2B8ej5qQiFSR087
ZiZ5MTJJT215ak5iSkxwST8jM0BIUD4la2k5XkMqIzNjUgp6aUI9O2pQUCZsT2tydSNDQ3Q8UUdM
a1VDbCElaiZKKWx6K2pXYVghJHkjcEFoU1p9QkVAQihoKE8oQmBwY20qJV4KeiUpMzRqcUo3NE5m
QzZiSENKQG9gZmBXJntFTihsfllOKTArYDs2NHZmNDZ6VzlAS25PPGo3Q1hFdSlAcTs+RGJpCnpi
RHB3SW5aNHBmMlk7PHh1SXRBK0cwSmwzey1hS1h1bD47TUtDXzBGPmNmPCFPWk1PTTRDTH4qbWRL
eXNiemZSPQp6bkFlRiV7YSZCb19TOWtrTE5XSztoOEctIzhEQipYPU1rYWlDVCNufCUyaUcoaXNl
R2d7WVM1I1Upbz83Wk1rQ34KenR+YGtORnRfPiExN2FgfGF8Yz16cHxgd1FmTHxNVXRAK3I/SWZ5
czZhSkY4JkhPTiVxMTFnfTtTJDFtVG80XiU4Cno9JjlrO1ZCQGA0R0RKMXR2clRFUGs2TEplMzNn
ZmQlKChiJUhUMUBabCZqaWErXkBoOW1xQkRDTzVfUip7dCl2Rwp6c1dxJjYmbn5DKDYzPn01djdj
WCNXKFE+R14yWGlVaEBQbjdXJG9VMTlsKG9JKD5uUGJTK3d4amFKRl52QWJKZisKelYoO3ZWWW9U
KEZIeWdnP2BGPTJ3Ml9nLU8+OGI5fGphVW91QVZDSS0lRm04dmZicW02VUEoaVQ3YytMZUh7T2he
CnpIPmxHMDZ1MCtDRHlDaXE9P2lUbWVeNF4hZSRmIVohZlFxNSNWPyRqaF47JlpmdjYwWC1nZWlf
QF4lJD1ZVFAtOwp6fDJjVGprRVJ5JC1IaHBhM31SXmN3fi0wa2FkbSFjX2sqYGUmakVOOT81MGQq
MiV+fDRnMmJtJF9UZSFIYTRxVF4KenRrZjZvSipMVzIxN1VyNnZ0TFNgbXA0fD88UHlhI0NZZGx5
UWtKKH1jOWtnPGx8PnR8KzNVd05iSDVMTXNzSWoxCnpJME5ldnlwSjl6b2lXO3JtYmJHYkhoZV89
WG9oT3UkQGlNSkxETjtOU2ZxJiooWXkhZVlIcTEpTn5LQmhYP0B9VAp6VlZ9LVlzMnd8U2VgZHdY
Z1V5dHEzXjk2VGQ2NDItSCtpbSM/PjdueDBYdkhsUkc5LWdKfFVfQz1rWkl4ZCVgS14KekJYPlk/
UWt4SGhqdXBnQzRpcEgpKG1rdCp6WjUoUmpfcWkpJiUyKE9gTkM7bFE2NFNLYE4+ejN2PTE7d1NG
Ym9sCnpjLW5ocEQqKUZwO2tldip8QjM7bVV1U0orOEZVQ2poaUp0JiNWaT4pO30pb3tPbzQybDs5
OGAmZ0cwOCQrUSs1Iwp6aFdpaiMwN3Y3ZV9gMl5XPnlQQ2w5cmFCeylae2daYiZJYGU0dyE2dkhl
SVY8SVMoRmY4bXFEUEY/MjlGR0dgd1IKejJAVjdZVWIwdmJfVHpGbXpqcDs+M1kyKjFiJExlLVp4
IShvKUFRfj9sbE81ZHFDOXUoQmc0RU47Szh5I2hFQjxFCnpGeStHc15NND5PS3M5Km9NYWNsI3pE
Zzc3VHZSWTJocGR5S202YHh2I19MX2Y7T1ZQMzxILT9sK1ZQVmNMK1JCTwp6KWV+ZFBtJWFrNExU
Y1QrMHlEbC1rZjVtOHdlaWo5c2BoKXRNcF9eaUxKUHtiN1E+clRDaHBgKHhAczlqX1BWMHwKemtt
PUt6XztaakBQKSE2IWRtbyhhdXRGZmtFZFRTcnwzM2RpOzZEV1paJGJiTHtGXnBwaWtMVj09dnUx
cGQjeHVjCnpFMzM0U0I7IStSXkNJKDAlOEVTJFF7dWc9PVRTOHwmc2ZDa3pjYEltQGc9e28qez1S
IUB6fVhhOEZCcmk7JnI7UAp6c0xydWcwX2l1QXRjS3c0JnswLWFIWF9TVWtRLTFhd1UzSWdve01D
KEUlangyP0hKbFJZJWZYZTlhNTNEfE1BPnkKenlDTnpvWVFLbj91eT5SfVkqO2Nlb3Q8fkwtcjx2
QmpsT3FQY3dkQ3RtSCpeNWdINzJ9N1Z6VEA3eD1PJShJMktuCnpKfHRscUBRZHwtX2FaYXZPMjZ1
Rz5ATypNYj5XNnluO2NmaElTKS12ViF9OWw0OUdgMlJpbDRmTGQhRXw7U0dDZQp6IVM4PmJzYExq
UGslTHhAcnxMeSFlS2hBJVAoXiozTkJobnlJdiMzZTN1eXVSTSYjb3ZtbW5CMXB2TzxNTWpaeUwK
ejVfNmpUI3ZvTUtkcHNWTE55alNqWTIhUTBFSEZwenMzZ1hJUWdUYlBXJikya0NqQz9zVEc/bmdG
Y2hsYSktbWVZCno9JXR+eit4WXRJVyozPns1fnUoXy1kPk1memhMMXl7T3NLRGFHM249Wk00NXpq
QChYY09naCpxJk16IXtLQDZKTwp6QztpR2l7PmwrfWUzbjs4c0haUSFOeHt1Yz5qRCUxQVkwWWM3
cDY/VkNtZT9qOVAwYlI8SVl1cXlONFcwaXt5alYKemE8SFhmbzh9Zk9ja3FNV2RmTm1ORCgtIVNU
QyghRUYlV0g5PWlOSjJIMSVsYHJHbDlBbHA+TGUwIT14TnspQUQ2Cnp4VVpnPFpKNjxxLTUoYmp0
I1BQSUYqY2d4K3E1NzJDTUEmNkBIby1iSEBeaUo2VzI3fDh8Nn1gT2BadEtIMXBrPwp6RlZGTz05
O0ApSEdWfFlmWjs2Tk0+KVc/UENhMXtRQStpU3IrbDNCMG40byVrKn5IXyZgfGtvKmktSmdtKzZe
YzEKejlVPGEpalZ9R2MoRyNiVShyMV5IPkcrdD5xWTZxQE1RbDJJemRub2I+TzBNfUwhX3tWM204
fH5rNSFgSU8kSUp2CnoqYzFYYUFiSF5Ba0wxcXAwQChKKUczVHhva01UZ2xUSSgtZDBuOGkrXmxq
KWdTdnZwRW5FWExyNy1feUomPUElQAp6dkpjcU4mRnFfTmsxTFpobWpqWTNXJHFvPVlWT3V0PXgl
cntlPXRkZz5nd3tUKVh3ZmB1NHUtezZzRmdDcnwtRGcKemNCU1EkODtBPT5eWDcqT0x6R1FlTCFr
bHhQT2NOfGB8aktJeX1oMmZ0diR+fXVPV3coYDE+fmxNZW9QUj9SO0NPCnpPcXdlQVVXQ3xgTHxp
VVQ9OGorQCM4cGo5SFhRdGwoX0JkPjF9PmAxN1F8UV5gcCkkIWQkdXpxdUtXbU5AN3pnaAp6Pmk2
aTgmIVpwVGR9KmteKHlMY0JoSzRyfkNmP04mRH4zJD9APGQye1VhaXE9bHp2I2Y9ZyheOWQjclNY
YGhEVm4KemNtdF9PZnJZaVA3XkY7TVRPKm81OGlJKnhoO28tPnhkfT9VPURuKj83YiE+NnRfRD87
ZnZJTnVgemVsNTVgYHlYCnozbCo3K0d7Xzlvd0M4MENYQzNjfF52SSYjJFQ8NnBLeyZ3eW1FcEdV
OXQodT1fWlJqUGkzaTxQeFJEV0xwQyFaUQp6KnpWTWd6azxLRHZzVFZ7V2ctdj0kMCE8JFF5e3J1
c280emcqbXRRYXVVeShfPD47QXgjMGxkTV5jPjJfQk9qUk0KejRkQyZrTEhsV0NpX0RxbFBmbEc+
aTlLfE08OXtSaDIxWjNjV1psKEI4d3skO3VkJmwyOCYqKG9NYEsleTA9Oz9iCnp5UzVBcmR5emU3
RVVmO1J7X3s4KjhWXzQ0bHpiPHp5XiEwTHNeTTRjbktAJEh6MjFRSm9+U0xpZVd6ej9uc3VTNAp6
O2Q3OHJhbypzWUtPdHY1VGI8ekYkeyRzcnt6aWB4ZDtLTyE/Nk56JW5XVE8tQXYrdWpIOHxkJWhE
PiZGdXM/SFgKeiViV1puSHtneVRXY2oyOVZqUzQjRjN8OUw/e2smQi13em8hTiUhNkl2RDRIY21T
KH4/SXxFemAhIzhPc0pqanwxCno9VDE/RTR3dzZzJnY7R1lFQTxadG9RfHtvKXtqKDxkJWo+Vzhk
ZCZGT3x8bjE5MH5ES1hHYX4xdShgO2ghYT5Vegp6Yz8+dWkmZ242QVBAbjN4NnxBZTZyVjU4WUFG
JEM3KzU4VUNoejVzVlhMZCEzXjhCIyVQbGRmNXY2dyZ0dUMpO0wKej9PU2hRYSsmOTAjU24xJiFs
MSpycGhKfVlfdV5OKkZeN1cjbiMoREtxNTwqeG9sNjJ6PFo8elVgYW5uUU4tTGdGCno+ITNSKHYk
QDFzeUNwcV5LY2QrZUllclZkczBMfmltZDJJTkk5PChTdWltaytyXihuMFRKQmJGPG8lQEsoPzJh
SQp6P1Iqe3plYyUwaHZ8SmdKY2V1K2tJc0JRJGBURytPbzFRK2VBdjRxI3FmcD1LaHt2MmEkMzZr
Uz0xbUFDeGIkdkQKekJvTGE4Y2MoMmlGMiFQP01mQytSU1B9REpXIzgqWnZ4YCZALWtnbGJHSEZt
MGd4eFozO2l5OFIqT0tQekVraG8+CnpgS2I3bVV9bGFvS2NveSU0bXNGJDl3dkEwbWYmM3NpYnlQ
WUhINSFocmNHeTN6Nlg9d1V+YDhNe19GZTItdnBBWAp6c3d2R1Q2WnpuMnFNNGd2T09YfSYmQ0Fv
YT9xQEA5ZmBpRSl3ZURwPD1OYjw+PSZ8VVQodEU5c3I0JDcyTH1hcCsKelZlMENQb3QpTjJZbntx
IT5sOWl0TU9mKF4pPCM4Kj5iIz1AZVMwKVQ/UGU0TV9QZEVvMCYwbVdzP1lGaVJnPH16CnowWHFY
Tm5Ka1kzRkI9MyRlWGtHMUc3M0lsSjQlc0deYmsmTzMhJkwzRW1fN2FjIWlxUSEzaER4cHY8R35V
Smc8Qwp6YFVvUE11anNxWjM1JGVuN3UqYjxlenlmb3ltUytwKXc7b05ffSQ+eTxYMEp1Y2UpPiZV
cn0oX2hHbGNpeSZeM3kKekZMaWJ2PlhVTmlhTkRlPU9rWXNsKlk3angjRHUyNXI5c0VfbUkpRT5M
Z0YwSFRWJnFgdTRNPmp0WTUjV2RjMyhQCnp3PjEoOz1NOSUmLVB9TEN0SzQqY2FCel5sWTx3Xit7
YVAkX249QypoblJxWihnPyFHJXJERTl7amY8JjI9R15tdAp6Kkk9ZGc7NzBHbkcwOElCVmBwVDl4
aTZ0eFYpbWtCYHRxU196ISp0PGR1a0dFT1RRPmM8OUtwcGRqU2JXY0BCfH0KenZWISpkKWRYP3gk
ajN6c29mI2cjX2EpT2NDVXpAWE5aV0NtMVB9KD5jYWtjJW1aangjQC1wNzJpZW5GM0VXMXd5Cnot
RXBvbSZmRlchXlYtO3EqZExQSjR4NiRDJDR3LUUpdHc3cmxAMXkpX0I8eDh2dXk4bGIjK21PZEhT
V049am81UAp6IVYxMjk4PGR9UGtLblFjMGd8K3Y2QCp0NFlBQ2VMXndYRHl1V05hek1aRXAtU3FY
PT9LbDs4YEoyI2BJMk5VMWMKemx7U0h8ZDhQUV98NGpZWnQjSSpJWEF5VHwtclMtKUUwVWBATHw7
IykyX1U0eFM4NW5+UFExTjVWQmZvPHlwbEtoCnpgUmw9TitFTmJQaFBCaFIxV30qT3h1Z0JIUUxP
UUMwNjloXmFGUyl9WHktfH5PaHBlMSVUKGBCIShMUW1DVmteRgp6Qz9gaGExXyRleGhme1NXLX42
PjA/VExNSG14TD98RmRWQ04hOFExPVUqUDVBaXlLJVRFWGA0P2E5ci0hb2ZLen0KekEmNTYldEIk
I25temlQbThuWXt7bXdmal81XzUwMV5MTU4/dXc2WGtpRFE3UjYhMmtXKSgqdjdNIXUlWHpiU2tB
CnpyTCg2Jl55UkBSXiY5ZHBkJmlfJVNIRDlfcWt1WUFDI05QKyVJcEQoJEJQX0MrQ3lkbT0tZH57
PyleP050ZGZPYwp6TjRzWXlfUSg3eEpjY2w9OGd9JG1mdHpCNzhgSlZEbjtre0h7b0lSb29rX3ha
PDN+fFpFPXhoe2B5N1cwUmIqYnEKemkyMnY1a2VacGxkdkVjfTt4cmEjTnRPZ3JrQSlYZGVaNm1B
enZfSV5kTDkpT0hDcGJJPHhMIWtCV15oNjA3ZV9nCnplRX5oSmNIPFFrT3lFfkRvdFRodntTeXEq
b1dobkMmT1A9a2p+VChqN1hrP187Uk5xMUg5cStOUG1YKCVwPzwzOAp6elFFKnctQGRzKj1TOFJ3
Vn1DUVMqcHV7Ny1ObXB9NTN5WiRtSSV8ViZPNyM/M3NiTzdtc0V+ZTVZa2ZqTFIrYlgKek1MJH1h
aHdAZH01Zi1rPW5LeUZ1elZHTkJpbkpTbTh0RHtadj1TQFZoQjNES0dJYFA2KFV6NjYjQnVIdnBC
QiRHCnpZMWhZXmEkN0B8YXhuUV52cVlmPSNUZVBXWVVYSXgxVEwmfnlOLUlzMUNAcWE7JkdLbm9e
fk1lSnpIeH5hYEtCMAp6aENGZlNMT3h4LWxDPThxe1B9LSlwQVgtTygwOGdaeEVgeEB4cDF2U2J9
Z2NRPkIzbTttITBRTUlEMW5xekJ8JSkKel9VVWYoYWgpblhyXyFkMVh0enJLV09jVypMNVB9V0Fv
PUNpbGs8VWNpPTdjUTxRak8hZXI4O25PTk82RShkdiRgCnpYMjl8TmQ9ey1sNm8mOHk0VFZDSldu
U3Zzam40ZFpvMjFhc0RjZklOQXhzZCVeclk+MVleXlMrdm59OVV3fXRuOQp6QW12diprRDVaK1Ek
JWRpNjJeISVlQTIxI2cobG04OzwxfFZ1U3VoI0hNMUdnYnJhQGVXd3NoZ1Z6UlI+a3pJe2MKelVV
cWdQYWR8THdIPG9eSz80X0FkVz5ZJitgbzAzYTk5S21Kd3pSQjkoZ0JaZEEzd2NTWUJNbmtPUS0q
ZnpmPTROCnpAQFRjVT43bT5CS1Ywb2k5KmI2XzZkYz01ISFlZX09MCgkejl1enZDSUFsSitaVUFQ
ekgpeClnKm5hS3F7Nn1sZQp6aDNUNEA/MUJRYFMqNTc8OTQ1MGdLbFctTipwI2IhbTxPQTBUZCM+
MjBrS199LV5JRExYcihzMGFGTnZAYVc/Tm8KeiRON1FXI2ZHRUJJdi0hJEA1Qy1BZ1MlMGdOI2B3
Rlo4emN+JTNqWDQ+OyV3SSRVV2VGRiVSTjlHUzNLeUt+b3I4CnoyRHNsYUx0PllGV2ZlLXRtU1JI
ZzJRTW81RXpXM34kSFN1fT94LWFTYnNRKSY8eUtVMXpnc3pEejQ9UTtsOVlYTwp6Wj9uTlghOzF4
dmVOQENHUzlWKyEpTnJfIVFzLSpzRWs7fXxFJntXQCkpTChWbDk7Z2BsMEFoPyRuM0ImTVpvRlUK
ejV0MGBjdG92cG9gbTA8VFVMO0ZNNCY8cUshfl9MZUd4R2JFMk9SN1FUWTYwVUZ3S3BxcjxTXklX
UXx9S1lYPDM9Cno1aFluSWNSeDExclRHTVled2lXR0BKPEdhYzUhKiQ9TCFQQF9OQFZne0toM1JT
PCFZJnVBTyF+bkpGam10cV84Ywp6ZShje0gwYH1SKzxIPTxgNStacS17YFBubWxnek0lUEwwd2Ex
eyp3JmU0Sl95TE1VTDEmKDNqXyhsMVAmTF5mYnwKemkkbi08T21oK0RgI1JwVFJSbjdmaGp6QE9f
eCRSQnszcWhrKHBpX15xKWhUK1g0ezlDVlQpcl4jfk9MYURoS0NVCnohQiE1eGFUWTA7ZnkhTH1W
ezRSJnRsdihqX3xaSmQkQTF9Tjt4WCRyIUxqPnJHMUpkJTw/TjszO3p3Sj9ZPVBvYwp6NkpDQ1Re
PyR5bWt4TWtLbiN4JHByYmlBcEJ4aXIhOTRZbTNzSGRQaTJLcS13PD81QVYqcH48TGRSU2Bkez9L
PWIKejdgUUBHV25EQ0tVIT1zUnEkRDFwSnktcDV0eTtVOzN+T0tjZ3EyfEp7ajZMM3JaTzJjPCNE
JCRXfWFKNFJWUDVZCnp3P3EhflhETmdDY0gmaVpBNm90V1c4eUpEVnc+U3JObDh1SmlYYTNnMH1T
VWlxZjtrZVBIajBrKXl6ajVpI1Rzcgp6dmtEKTRjbmFHYEd8QH1UJShnfiRuVWJkXz1BRjdLRD1U
R28rWjJqP24pOT5hRil8TzhJZWhmaXptd05CXyN5PCoKej0pR21BeXIhM3pteGtvPit8Qy0yUlly
bkUzYDR2T1FfOyFTPm1NSUtASmtsZ04mcT8+e2B1Xkp1QzhnRVRVS2tPCnppP3M5YSFBYD5tO3oo
OEZ1b0JKfmk5MSs3amAoTTQ/MVc3ZENucVB2P08hdCYzc35ZNj07UzArOV9HSCg8Myp9Ngp6M0tA
PmkzLWVgQW9IRTkrKHBmQUBAS0pIVSR1ITUmP347cTFHRndxKlc+cmNZQkReWE9rTmNGKHQ+PWhT
TnVoQHgKemV5Ylo4YE5mdTh2fChNSyk4Pn0tQV9QS3Y+KlZoTz8yQkA+eDJVSn55WHE7bE02PF5n
QENGR3FqZkVLaDt8ZHdXCnorRz9gPGBEO2d+SmB9eWNCJTNuYjZsJU5sQlckaUFYIUJqOSh+V19i
anNkMHRoLV4wazk7MVFlOHRFVFM7PF9wRwp6K0V2VlBKYzt0O1U4Jl9fdjw0cmFQPU93PS1TfXdJ
azlUTGhNdStoRDFRcipwQnZTQD9JWmBWM3d4JUZ+TFBaaCgKejhtS2pLd0M2bEF7P1pTS1QhMkUy
SDNTN3Qpb1dDWkFNSjQqPU1VYEpgezViV2oxTW4oSUlNYmlDYllDJTxQZWlOCnpRTVhJUzxpU2Qp
Z0djLTZHV1UoV3ZRb2RFajYkPW03WVMmQ2d1TkpuUEpIZnFrYT9xVkI3bDUrKXlLbnFgOGB1IQp6
UHtXWlZLKWxlYDFgMnsobnkzRSh1Yyt2TGxPPUk3IU1PKzVVbjtKbVZ+UCE4JFNFazA1KWQkTGgz
KlRaKFFNQXoKel8yWlQ/TGNje0VHVFM5Pih+QCZLNjB2d1NVbm1aQEE3bURAeTtPWGR3Um04Y3Qw
YE41eElhZCQ9TnlgSCpXRCowCnpSa2BXQTFGSHgyTE5Cci1tVVg5d01VMnhJXm1Xc0w1dFVjMjZU
Q1lvY1kxdHxpQkBacmlvS2JrQllfamZfLTNoTwp6SkBAeURveTV2Z3JfQjhKIUNYUDZfNEw9T05t
YUpMemZVbzt7ejtJcHhDMnM+aiV+WUUrdXp5YklnMHR6QE8qVzsKekgySWlWTyVjPmpIRzghNTkq
U1hWNiUhWDxHKnltIzV5TEpFaklVTkV3O20lbjI0N3VySF95PiZ6Zj82SS0oZUZWCno3VDJRUUhr
cShLeUgwdk5OJFJnQzk0cjEzdTx4P3xVNnczPXBrOzR3enhpSEdlcm1wPzNjZ3xnVVJ6b0dKRXBN
IQp6anFWejEqaFNLZjlnenM7LUlPU25RcD90RXp+REt+N04qUX5oUnA+PENgfF9raHAte3IpeVhv
UnZjO307MDZjPD0KelEjckVKd3AmXyRGPnIzeT1oZXV5cThseFojeGJkZnVFOGloLXNDYjF2dT1z
SyE5bCR0c349ekFuP0BWJmIqPXpJCnpYQkdCV3RYZ0UyZTVHaClZK1BuQGNvZiFAWEAtM1c+T3dj
WW14PXtqaGJ8UiUxUnYzcXh8NG5qbDZsKHU4OUteVgp6dDIjWEolZUl3OGsleVFKdmtHMW5fdWIt
WXduYFZMKEcqYnY5dzA0RnR+aiY1dih+e2R3ZUtCUClSS0VCVChPZFQKej1ze1RiU1JXfn5ySVU5
dyg4dkRXVStWc2k8TVNaV2thT1V+Y2tYe2JEVEpIVHs5VStlQEtAfUMtejRZVytWNEQlCnpwI1pv
b2Qwb350K0hNcGQtPG9OSHU7ZnYxe31PZ190XkR7S29HbkBTUXIxQDZmdXg8ISViYUJwIzttNWNf
VDlUWAp6TWU2KV9EUVVeSiskIXV6aHJOOD0jODZ9Qj9vVTc3ZDVwKkI3bUBwRyVqZXA4YHBlUHha
UFdhWGU5N3lrYjdANyYKeiM+VTE4Nz15YGFMTmkwfGB2P3YtNC1YSFU0MG01Jit8RypVWUNjY2Ji
SyllezxHNnt3K3kjfXRQTyo4SzNJRVFpCnoocUclTiFvZDNhNnl4X3hqJl9jbkMoPTZDdHxoPSYk
cV4xay1JJDQ8Y0BMJWx2NE9qcVQ+d0JHQG5TKEBZVCMycgp6JTN6YDZYc1A3VEYodDx+ZndAWC1B
JSYkI3ktQi11dUJmfT0wWmAkS08hIypELTxNNVclTzNLe0s7Q1d2XyZCOU4Kej0lKSRSIyowekZG
YihqVFM0eyhtZVFfPEN0SnxWOGU9KUYtOW9Zc1VgR2IqfGZnPHklZ1R1eDhQYXRzRndFZys5CnpK
WEk3IyRLcT9DQT9jPXMkVlJOZ0sxfWlwMm5nKThMKj17dlAkPlJLR2luMU1NT2h4cGF8dmJsZT1n
Xn42WlVXYAp6ZW44fjc/PStqKUJNTj1jN0pUb3wrM3MjXzwkN3J2M1ZqPUJsaml4OyZ0djkxdjE2
M3ZQX3s4KjgkPXdVSSZoWUcKemNSRVAxKHJHSDhxaUVPV3EjTzVqV3FKSjNDb2Y+ODMtWGxAaDkq
NCYhV1EybT0wTSlxeHgqJnkoY01gbEJ7TVYjCnopQnJvJFR1aGNGI3x+fG14ZzJ6TC00eXFBKz9U
RjIxNTVuN25SXnt1KG9VSW03R3tDbDRKY19STys9blB4Xm9gcAp6RjlJbC1GTFNwbjI1I2B1MGht
VXIlZjktMEVwZEo1UUJ7OGVmNTV7ak5fV3MpbFdvd3dNQUo3YWAjWXZSWXJvYTIKemolbyl5RUle
Km83NXxhZzRzYGxAM0o7al8jSHZzakVRUF5ebzd6UVBtUUx6aGpDez5zPCl6UE5TaEZgZGtHV0c+
CnpTakpvfilGV3lgeWlRPjlDUWhiPHZmMX4mSVI3WUxRaF89az1LXz8mMkBOfD1sXm9LYD02REN9
QDJGMSVodUdRSwp6d0opPj8qZn1eNXlkOTRONCtrMnw4X0xVOSlkek9nP0E4YFlIeVZ2SSEyJFZ1
b2d5SU5lfUE0STY4c2JGTklpWkQKelF2U35tel9EK3dxPzVaWkVUfHlZP31FMXZYdShuSnt+cjRm
a3BDPj98MkFKWnFUajtEaE57SzZvXjBfI1JHdylsCkpWeEMmT3tYZk5+djZ9ekAKCmxpdGVyYWwg
MApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvdmliZW1pcy5zdmcgYi9hcHAvcmVz
L3ZpYmVtaXMuc3ZnCmluZGV4IGMzZjNjODE5Li43MTE1YzMzNiAxMDA2NDQKLS0tIGEvYXBwL3Jl
cy92aWJlbWlzLnN2ZworKysgYi9hcHAvcmVzL3ZpYmVtaXMuc3ZnCkBAIC0xLDE5ICsxLDcgQEAK
LTw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rpbmc9IlVURi04IiBzdGFuZGFsb25lPSJubyI/Pgot
PCEtLSBWaWJlbWlzIGJyYW5kIG1hcms6IGEgY3V0LWdlbSBkaWFtb25kIGNyYWRsaW5nIGEgcGxh
eSB0cmlhbmdsZS4KLSAgICAgRHJhd24gZnJvbSB0aGUgZGVzaWduLWtpdCB0b2tlbnMgKGRvY3Mv
ZGVzaWduL3JlZGVzaWduL2xvZ28vUkVBRE1FLm1kKToKLSAgICAgZGlhbW9uZCBoYWxmLWRpYWdv
bmFsIH4zNyUgb2YgdGhlIGJveCwgc3Ryb2tlIH43LjglIG9mIHRoZSBib3gsIGZpbGxlZAotICAg
ICBwbGF5IHRyaWFuZ2xlIH4zMCUgdGFsbCBjZW50ZXJlZCBpbnNpZGUsIGFjY2VudCBncmFkaWVu
dAotICAgICAjNkFEREU3IC0+ICMyRkM2RDAuIFRoZSBzb2Z0IGdsb3cgaXMgb21pdHRlZCBzbyB0
aGUgbWFyayBzdGF5cyBjcmlzcCBhdAotICAgICB0aGUgc21hbGwgc2l6ZXMgdGhpcyBTVkcgaXMg
cmFzdGVyaXplZCBhdCAoU0RMIHN0cmVhbS13aW5kb3cgaWNvbikuIC0tPgotPHN2ZyB4bWxucz0i
aHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNTYgMjU2IiB3aWR0aD0i
MjU2IiBoZWlnaHQ9IjI1NiI+Ci0gIDxkZWZzPgotICAgIDxsaW5lYXJHcmFkaWVudCBpZD0idmJB
Y2NlbnQiIHgxPSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj4KLSAgICAgIDxzdG9wIG9mZnNldD0i
MCIgc3RvcC1jb2xvcj0iIzZBRERFNyIvPgotICAgICAgPHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNv
bG9yPSIjMkZDNkQwIi8+Ci0gICAgPC9saW5lYXJHcmFkaWVudD4KLSAgPC9kZWZzPgotICA8cGF0
aCBkPSJNIDEyOCAzMy4zIEwgMjIyLjcgMTI4IEwgMTI4IDIyMi43IEwgMzMuMyAxMjggWiIgZmls
bD0ibm9uZSIKLSAgICAgICAgc3Ryb2tlPSJ1cmwoI3ZiQWNjZW50KSIgc3Ryb2tlLXdpZHRoPSIy
MCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIvPgotICA8cGF0aCBkPSJNIDEwNyA5Mi42IEwgMTA3
IDE2My40IEwgMTY4IDEyOCBaIiBmaWxsPSJ1cmwoI3ZiQWNjZW50KSIKLSAgICAgICAgc3Ryb2tl
PSJ1cmwoI3ZiQWNjZW50KSIgc3Ryb2tlLXdpZHRoPSIxMiIgc3Ryb2tlLWxpbmVqb2luPSJyb3Vu
ZCIvPgorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI1MTIi
IGhlaWdodD0iNTEyIiB2aWV3Qm94PSIwIDAgNTEyIDUxMiI+Cis8ZGVmcz48bGluZWFyR3JhZGll
bnQgaWQ9InJpbSIgeDE9IjAiIHkxPSIwIiB4Mj0iMSIgeTI9IjEiPjxzdG9wIHN0b3AtY29sb3I9
IiNmZjc1OGIiLz48c3RvcCBvZmZzZXQ9Ii40OCIgc3RvcC1jb2xvcj0iI2RjMzY1OCIvPjxzdG9w
IG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzYzMTUyYiIvPjwvbGluZWFyR3JhZGllbnQ+PGxpbmVh
ckdyYWRpZW50IGlkPSJnbGFzcyIgeDE9IjAiIHkxPSIwIiB4Mj0iMCIgeTI9IjEiPjxzdG9wIHN0
b3AtY29sb3I9IiMyMDE1MWMiLz48c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiMwODA4MGIi
Lz48L2xpbmVhckdyYWRpZW50PjwvZGVmcz4KKzxyZWN0IHg9IjEyIiB5PSIxMiIgd2lkdGg9IjQ4
OCIgaGVpZ2h0PSI0ODgiIHJ4PSIxMTAiIGZpbGw9InVybCgjZ2xhc3MpIiBzdHJva2U9IiNmZmZm
ZmYiIHN0cm9rZS1vcGFjaXR5PSIuMTMiIHN0cm9rZS13aWR0aD0iMiIvPgorPGNpcmNsZSBjeD0i
MjU2IiBjeT0iMjU2IiByPSIxNDQiIGZpbGw9InVybCgjcmltKSIvPgorPGNpcmNsZSBjeD0iMjY4
IiBjeT0iMjQ5IiByPSIxMzYiIGZpbGw9IiMwODA4MGIiLz4KKzxwYXRoIGQ9Ik0xNTEgMTYyYTE0
MyAxNDMgMCAwIDEgMTM1LTQ4IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmU4ZWUiIHN0cm9rZS1v
cGFjaXR5PSIuNTUiIHN0cm9rZS13aWR0aD0iMyIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIi8+CiA8
L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXNvdXJjZXMucXJjIGIvYXBwL3Jlc291cmNlcy5xcmMK
aW5kZXggYjVkNGVlNzkuLmYzY2FlMGI0IDEwMDY0NAotLS0gYS9hcHAvcmVzb3VyY2VzLnFyYwor
KysgYi9hcHAvcmVzb3VyY2VzLnFyYwpAQCAtMSwxMyArMSwyMCBAQAogPFJDQz4KICAgICA8cXJl
c291cmNlIHByZWZpeD0iLyI+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1p
c19wLnBuZyI+cmVzL3N0ZWFtL3ZpYmVtaXNfcC5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFs
aWFzPSJyZXMvc3RlYW0vdmliZW1pcy5wbmciPnJlcy9zdGVhbS92aWJlbWlzLnBuZzwvZmlsZT4K
LSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2hlcm8ucG5nIj5yZXMvc3Rl
YW0vdmliZW1pc19oZXJvLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVh
bS92aWJlbWlzX2xvZ28ucG5nIj5yZXMvc3RlYW0vdmliZW1pc19sb2dvLnBuZzwvZmlsZT4KLSAg
ICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2ljb24ucG5nIj5yZXMvc3RlYW0v
dmliZW1pc19pY29uLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlz
LW1hcmstNTEyLnBuZyI+cmVzL3ZpYmVtaXMtbWFyay01MTIucG5nPC9maWxlPgotICAgICAgICA8
ZmlsZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay0yNTYucG5nIj5yZXMvdmliZW1pcy1tYXJrLTI1
Ni5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTEyOC5w
bmciPnJlcy92aWJlbWlzLW1hcmstMTI4LnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2Ny
aW1zb24tbmV0d29yay5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9jcmltc29uLWJsdWV0
b290aC5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9lY2xpcHNlLWNvbnRyb2xzLnN2Zzwv
ZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2VjbGlwc2UtaWNvbi5zdmc8L2ZpbGU+CisgICAgICAg
IDxmaWxlPnJlcy9lY2xpcHNlLXBvd2VyLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2Ny
aW1zb24tYmF0dGVyeS5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9jcmltc29uLWhvc3Qu
c3ZnPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfcC5wbmci
PnJlcy9zdGVhbS9lY2xpcHNlX3AucG5nPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVz
L3N0ZWFtL3ZpYmVtaXMucG5nIj5yZXMvc3RlYW0vZWNsaXBzZS5wbmc8L2ZpbGU+CisgICAgICAg
IDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19oZXJvLnBuZyI+cmVzL3N0ZWFtL2VjbGlw
c2VfaGVyby5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1p
c19sb2dvLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfbG9nby5wbmc8L2ZpbGU+CisgICAgICAgIDxm
aWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19pY29uLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2Vf
aWNvbi5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTUx
Mi5wbmciPnJlcy9lY2xpcHNlLW1hcmstNTEyLnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxp
YXM9InJlcy92aWJlbWlzLW1hcmstMjU2LnBuZyI+cmVzL2VjbGlwc2UtbWFyay0yNTYucG5nPC9m
aWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay0xMjgucG5nIj5yZXMv
ZWNsaXBzZS1tYXJrLTEyOC5wbmc8L2ZpbGU+CiAgICAgICAgIDxmaWxlIGFsaWFzPSJmb250cy9T
b3JhLnR0ZiI+Zm9udHMvU29yYS50dGY8L2ZpbGU+CiAgICAgICAgIDxmaWxlIGFsaWFzPSJmb250
cy9NYW5yb3BlLnR0ZiI+Zm9udHMvTWFucm9wZS50dGY8L2ZpbGU+CiAgICAgICAgIDxmaWxlPnJl
cy9zb3VuZHMvbmF2X3RpY2sud2F2PC9maWxlPgpkaWZmIC0tZ2l0IGEvYXBwL3NldHRpbmdzL3N0
cmVhbWluZ3ByZWZlcmVuY2VzLmNwcCBiL2FwcC9zZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNl
cy5jcHAKaW5kZXggZDY5YTkxMzEuLjYwMjJiMjUzIDEwMDY0NAotLS0gYS9hcHAvc2V0dGluZ3Mv
c3RyZWFtaW5ncHJlZmVyZW5jZXMuY3BwCisrKyBiL2FwcC9zZXR0aW5ncy9zdHJlYW1pbmdwcmVm
ZXJlbmNlcy5jcHAKQEAgLTIyOSw3ICsyMjksNyBAQCB2b2lkIFN0cmVhbWluZ1ByZWZlcmVuY2Vz
OjpyZWxvYWQoKQogICAgIHNlZW5XZWxjb21lSGludCA9IHNldHRpbmdzLnZhbHVlKFNFUl9TRUVO
V0VMQ09NRUhJTlQsIGZhbHNlKS50b0Jvb2woKTsKICAgICBlbmFibGVIZHIgPSBzZXR0aW5ncy52
YWx1ZShTRVJfSERSLCBmYWxzZSkudG9Cb29sKCk7CiAgICAgdWlTaG93SGludHMgPSBzZXR0aW5n
cy52YWx1ZShTRVJfVUlfU0hPV0hJTlRTLCB0cnVlKS50b0Jvb2woKTsKLSAgICB1aUFjY2VudElu
ZGV4ID0gcUJvdW5kKDAsIHNldHRpbmdzLnZhbHVlKFNFUl9VSV9BQ0NFTlRJTkRFWCwgMCkudG9J
bnQoKSwgMyk7CisgICAgdWlBY2NlbnRJbmRleCA9IHFCb3VuZCgwLCBzZXR0aW5ncy52YWx1ZShT
RVJfVUlfQUNDRU5USU5ERVgsIDQpLnRvSW50KCksIDE1KTsKICAgICB1aVNvdW5kcyA9IHNldHRp
bmdzLnZhbHVlKFNFUl9VSVNPVU5EUywgdHJ1ZSkudG9Cb29sKCk7CiAgICAgZGlzcGxheUhkckNh
cGFiaWxpdHkgPSBzZXR0aW5ncy52YWx1ZShTRVJfRElTUExBWV9IRFJfQ0FQQUJJTElUWSwgdHJ1
ZSkudG9Cb29sKCk7CiAgICAgaGRyVG9uZW1hcHBpbmcgPSBzZXR0aW5ncy52YWx1ZShTRVJfSERS
X1RPTkVNQVAsIGZhbHNlKS50b0Jvb2woKTsKZGlmZiAtLWdpdCBhL3BhY2thZ2luZy9mbGF0cGFr
L2lvLmdpdGh1Yi5uYXZ5YXMzMjEuVmliZW1pcy5kZXNrdG9wIGIvcGFja2FnaW5nL2ZsYXRwYWsv
aW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AKaW5kZXggMDQ1YWRiZTYuLmYxMmRh
NWQ0IDEwMDY0NAotLS0gYS9wYWNrYWdpbmcvZmxhdHBhay9pby5naXRodWIubmF2eWFzMzIxLlZp
YmVtaXMuZGVza3RvcAorKysgYi9wYWNrYWdpbmcvZmxhdHBhay9pby5naXRodWIubmF2eWFzMzIx
LlZpYmVtaXMuZGVza3RvcApAQCAtMSw2ICsxLDYgQEAKIFtEZXNrdG9wIEVudHJ5XQogVHlwZT1B
cHBsaWNhdGlvbgotTmFtZT1WaWJlbWlzCitOYW1lPUVjbGlwc2UKIEdlbmVyaWNOYW1lPUdhbWUg
U3RyZWFtaW5nIENsaWVudAogQ29tbWVudD1TdHJlYW0gZ2FtZXMgYW5kIGFwcGxpY2F0aW9ucyBm
cm9tIGEgU3Vuc2hpbmUgLyBBcG9sbG8gLyBWaWJlcG9sbG8gaG9zdAogRXhlYz12aWJlbWlzCg==
VIBEMIS_PATCH_B64
cat > /usr/local/share/moonlight-os/install-frontends.sh <<'FRONTENDS_INSTALL'
#!/usr/bin/env bash
# Run in Anaconda's installed root or a disposable Fedora test container.
set -euo pipefail
source "${FRONTENDS_LOCK:-/usr/local/share/moonlight-os/FRONTENDS.lock}"
DEST=${FRONTENDS_DEST:-/usr/local/libexec/moonlight-os/frontends}
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
printf '\033[40m\033[1;31m\n🌑 MOONLIGHT-OS • FRONTEND\033[0;31m\n'
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
collection: Moonlight-OS Streaming
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

game: Vibemis
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
Description=Restore saved Moonlight-OS hardware mixer levels
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

echo "Moonlight-OS verification"
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
Description=Expand Moonlight-OS root filesystem to fill USB
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
Description=Moonlight-OS boot verification marker
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
# Moonlight-OS diagnostic console theme: black background, red text.
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
