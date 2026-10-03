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
VIBEMIS_PATCH_SHA256=414658c32a591cc0c4b4d899a91d97be5c6b84e8fafc1c7be66b8500ba5c23e2
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
Ym91dERpYWxvZy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLjgxMGJk
ZmJlCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9FY2xpcHNlQWJvdXREaWFsb2cucW1sCkBA
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
Z2h0LU9TIGZyb250ZW5kLiBCYXNlZCBvbiBFY2xpcHNlIGFuZCBNb29ubGlnaHQ7IG9yaWdpbmFs
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
MC4uZDczZWM5ZjIKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0VjbGlwc2VDb250cm9sQ2Vu
dGVyLnFtbApAQCAtMCwwICsxLDE2MiBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRR
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
YWxvZworICAgICAgICB0aXRsZTogcGFuZWwucG93ZXJBY3Rpb24gPT09ICJyZWJvb3QiID8gcXNU
cigiUmVzdGFydCBNb29ubGlnaHQtT1M/IikgOiBxc1RyKCJTaHV0IGRvd24gTW9vbmxpZ2h0LU9T
PyIpCisgICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLlllcyB8IERpYWxvZy5ObworICAg
ICAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAgICAgb25BY2Nl
cHRlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLSIrcGFuZWwucG93ZXJBY3Rpb24s
IiIsdHJ1ZSkKKyAgICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgdGV4dDogcXNUcigiVGhpcyBl
bmRzIHRoZSBjdXJyZW50IGxvY2FsIHNlc3Npb24uIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0K
KyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1BjVmlldy5xbWwgYi9hcHAvZ3VpL1BjVmll
dy5xbWwKaW5kZXggZjBlNzM5YTguLmY0ZDAxMmI4IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1BjVmll
dy5xbWwKKysrIGIvYXBwL2d1aS9QY1ZpZXcucW1sCkBAIC00NDQsNyArNDQ0LDcgQEAgQ2VudGVy
ZWRHcmlkVmlldyB7CiAgICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBtb2RlbC5vbmxp
bmUgJiYgbW9kZWwucGFpcmVkLAogICAgICAgICAgICAgICAgICAgICAgICAgdHJpZ2dlcjogZnVu
Y3Rpb24oKSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdmFyIGNvbXBvbmVudCA9IFF0
LmNyZWF0ZUNvbXBvbmVudCgiQXBwVmlldy5xbWwiKQotICAgICAgICAgICAgICAgICAgICAgICAg
ICAgIHZhciBhcHBWaWV3ID0gY29tcG9uZW50LmNyZWF0ZU9iamVjdChzdGFja1ZpZXcsIHsiY29t
cHV0ZXJJbmRleCI6IGluZGV4LCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUsICJzaG93SGlkZGVu
R2FtZXMiOiB0cnVlLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhvc3RUeXBlIjogbW9k
ZWwuaG9zdFR5cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0fSkKKyAgICAgICAg
ICAgICAgICAgICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qo
c3RhY2tWaWV3LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgImNyaW1zb25Ib3N0IjogY29tcHV0
ZXJNb2RlbC5jcmltc29uSG9zdChpbmRleCksICJvYmplY3ROYW1lIjogbW9kZWwubmFtZSwgInNo
b3dIaWRkZW5HYW1lcyI6IHRydWUsICJob3N0T25saW5lIjogbW9kZWwub25saW5lLCAiaG9zdFR5
cGUiOiBtb2RlbC5ob3N0VHlwZSwgImhvc3RUcmFuc3BvcnQiOiBtb2RlbC50cmFuc3BvcnR9KQog
ICAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0YWNrVmlldy5wdXNoKGFwcFZpZXcpCiAgICAg
ICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgIH0sCkBAIC01MzUsNyAr
NTM1LDcgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAgICAgICAgICAgICAgZWxzZSBpZiAobW9k
ZWwucGFpcmVkKSB7CiAgICAgICAgICAgICAgICAgICAgIC8vIGdvIHRvIGdhbWUgdmlldwogICAg
ICAgICAgICAgICAgICAgICB2YXIgY29tcG9uZW50ID0gUXQuY3JlYXRlQ29tcG9uZW50KCJBcHBW
aWV3LnFtbCIpCi0gICAgICAgICAgICAgICAgICAgIHZhciBhcHBWaWV3ID0gY29tcG9uZW50LmNy
ZWF0ZU9iamVjdChzdGFja1ZpZXcsIHsiY29tcHV0ZXJJbmRleCI6IGluZGV4LCAib2JqZWN0TmFt
ZSI6IG1vZGVsLm5hbWUsICJob3N0T25saW5lIjogbW9kZWwub25saW5lLCAiaG9zdFR5cGUiOiBt
b2RlbC5ob3N0VHlwZSwgImhvc3RUcmFuc3BvcnQiOiBtb2RlbC50cmFuc3BvcnR9KQorICAgICAg
ICAgICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qoc3RhY2tW
aWV3LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgImNyaW1zb25Ib3N0IjogY29tcHV0ZXJNb2Rl
bC5jcmltc29uSG9zdChpbmRleCksICJvYmplY3ROYW1lIjogbW9kZWwubmFtZSwgImhvc3RPbmxp
bmUiOiBtb2RlbC5vbmxpbmUsICJob3N0VHlwZSI6IG1vZGVsLmhvc3RUeXBlLCAiaG9zdFRyYW5z
cG9ydCI6IG1vZGVsLnRyYW5zcG9ydH0pCiAgICAgICAgICAgICAgICAgICAgIHN0YWNrVmlldy5w
dXNoKGFwcFZpZXcpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgIGVsc2Ugewpk
aWZmIC0tZ2l0IGEvYXBwL2d1aS9RdWlja01lbnUucW1sIGIvYXBwL2d1aS9RdWlja01lbnUucW1s
CmluZGV4IGIwMzNkMjY4Li4wZDk3OTRkZSAxMDA2NDQKLS0tIGEvYXBwL2d1aS9RdWlja01lbnUu
cW1sCisrKyBiL2FwcC9ndWkvUXVpY2tNZW51LnFtbApAQCAtNDQ5LDcgKzQ0OSw3IEBAIFJlY3Rh
bmdsZSB7CiAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJRdWl0IGdhbWUiKQogICAgICAgICAgICAg
aWNvbjogInBvd2VyIgogICAgICAgICAgICAgYWN0aW9uOiAicXVpdCIKLSAgICAgICAgICAgIGRl
c2NyaXB0aW9uOiBxc1RyKCJRdWl0IHRoZSBnYW1lIG9uIHRoZSBob3N0IGFuZCByZXR1cm4gdG8g
VmliZW1pcyIpCisgICAgICAgICAgICBkZXNjcmlwdGlvbjogcXNUcigiUXVpdCB0aGUgZ2FtZSBv
biB0aGUgaG9zdCBhbmQgcmV0dXJuIHRvIEVjbGlwc2UiKQogICAgICAgICB9CiAgICAgICAgIExp
c3RFbGVtZW50IHsKICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlNlcnZlciBjb21tYW5kcyIpCmRp
ZmYgLS1naXQgYS9hcHAvZ3VpL1NldHRpbmdzVmlldy5xbWwgYi9hcHAvZ3VpL1NldHRpbmdzVmll
dy5xbWwKaW5kZXggNDk0ZTM1YmEuLjk0YTBhOWE5IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1NldHRp
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
dGVDaGVja2VyLm9zTWFuYWdlZCA/IHFzVHIoIk1vb25saWdodC1PUyB1cGRhdGVzIikgOiBxc1Ry
KCJTb2Z0d2FyZSB1cGRhdGVzIikKICAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6
IFZiVG9rZW5zLnR5cGVMYWJlbAogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTogVmJU
b2tlbnMuZm9udEJvZHkKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3JhcApA
QCAtMzczMyw2ICszNzQ1LDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBBdXRvUmVzaXpp
bmdDb21ib0JveCB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsQ29tYm9C
b3gKKyAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogIUF1dG9VcGRhdGVDaGVja2VyLm9zTWFu
YWdlZAogICAgICAgICAgICAgICAgICAgICB0ZXh0Um9sZTogInRleHQiCiAgICAgICAgICAgICAg
ICAgICAgIG1vZGVsOiBMaXN0TW9kZWwgewogICAgICAgICAgICAgICAgICAgICAgICAgaWQ6IHVw
ZGF0ZUNoYW5uZWxMaXN0TW9kZWwKQEAgLTM3ODcsNiArMzgwMCw3IEBAIEl0ZW0gewogICAgICAg
ICAgICAgICAgICAgICAvLyBpbnN0YWxsIGluIGZsaWdodCBhdCBhIHRpbWUpLCBzbyBidXR0b25z
IHN0YXkgZW5hYmxlZC4KICAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsKICAgICAgICAgICAg
ICAgICAgICAgICAgIGlkOiBjaGVja1VwZGF0ZXNCdXR0b24KKyAgICAgICAgICAgICAgICAgICAg
ICAgIHZpc2libGU6ICFBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFnZWQKICAgICAgICAgICAgICAg
ICAgICAgICAgIHRleHQ6IHFzVHIoIkNoZWNrIGZvciB1cGRhdGVzIikKICAgICAgICAgICAgICAg
ICAgICAgICAgIG9uQ2xpY2tlZDogewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIEF1dG9V
cGRhdGVDaGVja2VyLmNoZWNrTm93KCkKQEAgLTM4MDQsOCArMzgxOCw4IEBAIEl0ZW0gewogCiAg
ICAgICAgICAgICAgICAgICAgIEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAgICAgICAgICBpZDog
dmlld1JlbGVhc2VCdXR0b24KLSAgICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZp
ZXcgcmVsZWFzZSIpCi0gICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiBBdXRvVXBkYXRl
Q2hlY2tlci5vZmZlckF2YWlsYWJsZQorICAgICAgICAgICAgICAgICAgICAgICAgdGV4dDogQXV0
b1VwZGF0ZUNoZWNrZXIub3NNYW5hZ2VkID8gcXNUcigiTW9vbmxpZ2h0LU9TIHJlbGVhc2VzIikg
OiBxc1RyKCJWaWV3IHJlbGVhc2UiKQorICAgICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTog
KEF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZCB8fCBBdXRvVXBkYXRlQ2hlY2tlci5vZmZlckF2
YWlsYWJsZSkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICYmIEF1dG9VcGRhdGVD
aGVja2VyLnJlbGVhc2VVcmwgIT09ICIiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAmJiBTeXN0ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIKICAgICAgICAgICAgICAgICAgICAgICAg
IG9uQ2xpY2tlZDogewpAQCAtMzg0Miw3ICszODU2LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAg
ICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCiAKICAgICAgICAgICAgICAgICBWYlNlY3Rpb25I
ZWFkZXIgewotICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWJlbWlzIEZlYXR1cmVz
IikKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBGZWF0dXJlcyIpCiAg
ICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgQ2xpcGJvYXJkU2V0dGluZ3MgewpA
QCAtMzk0Nyw3ICszOTYxLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgUmVwZWF0ZXIgewog
ICAgICAgICAgICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAg
ICAgIG1vZGVsOiBbCi0gICAgICAgICAgICAgICAgICAgICAgICB7IGs6IHFzVHIoIlZpYmVtaXMg
dmVyc2lvbiIpLCB2OiBTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcgfSwKKyAgICAgICAg
ICAgICAgICAgICAgICAgIHsgazogcXNUcigiRWNsaXBzZSB2ZXJzaW9uIiksIHY6IFN5c3RlbVBy
b3BlcnRpZXMudmVyc2lvblN0cmluZyB9LAogICAgICAgICAgICAgICAgICAgICAgICAgeyBrOiBx
c1RyKCJBcmNoaXRlY3R1cmUiKSwgICAgdjogU3lzdGVtUHJvcGVydGllcy5mcmllbmRseU5hdGl2
ZUFyY2hOYW1lIH0sCiAgICAgICAgICAgICAgICAgICAgICAgICB7IGs6IHFzVHIoIlN0ZWFtT1Mg
LyBnYW1lc2NvcGUiKSwgdjogU3lzdGVtUHJvcGVydGllcy5pc1N0ZWFtRGVjayA/IHFzVHIoIlll
cyIpIDogcXNUcigiTm8iKSB9LAogICAgICAgICAgICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJE
aXNwbGF5IHNlcnZlciIpLCAgdjogU3lzdGVtUHJvcGVydGllcy5pc1J1bm5pbmdXYXlsYW5kID8g
KFN5c3RlbVByb3BlcnRpZXMuaXNSdW5uaW5nWFdheWxhbmQgPyAiWFdheWxhbmQiIDogIldheWxh
bmQiKSA6ICJYMTEiIH0sCkBAIC00MDEzLDcgKzQwMjcsNyBAQCBJdGVtIHsKIAogICAgICAgICAg
ICAgICAgIExhYmVsIHsKICAgICAgICAgICAgICAgICAgICAgd2lkdGg6IHBhcmVudC53aWR0aAot
ICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWJlbWlzICUxIikuYXJnKFN5c3RlbVBy
b3BlcnRpZXMudmVyc2lvblN0cmluZykKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigi
RWNsaXBzZSAlMSIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcpCiAgICAgICAg
ICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlQm9keQogICAgICAgICAg
ICAgICAgICAgICBmb250LmJvbGQ6IHRydWUKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6
IFRleHQuV3JhcApAQCAtNDA1OCw3ICs0MDcyLDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAg
ICBMYWJlbCB7CiAgICAgICAgICAgICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lkdGgKLSAgICAg
ICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBpcyB0aGUgTGludXgvU3RlYW1PUyBj
bGllbnQgZm9yIEFwb2xsbyAmIFN1bnNoaW5lIGhvc3RzLiBUaGVzZSBvcGVuIGluIHlvdXIgYnJv
d3Nlci4iKQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIGlzIHRoZSBM
aW51eC9TdGVhbU9TIGNsaWVudCBmb3IgQXBvbGxvICYgU3Vuc2hpbmUgaG9zdHMuIFRoZXNlIG9w
ZW4gaW4geW91ciBicm93c2VyLiIpCiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXpl
OiBWYlRva2Vucy50eXBlQ2FwdGlvbgogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTog
VmJUb2tlbnMuZm9udEJvZHkKICAgICAgICAgICAgICAgICAgICAgd3JhcE1vZGU6IFRleHQuV3Jh
cApAQCAtNDA2Niw3ICs0MDgwLDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgfQogCiAgICAg
ICAgICAgICAgICAgQnV0dG9uIHsKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiVmli
ZW1pcyBvbiBHaXRIdWIiKQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNl
IG9uIEdpdEh1YiIpCiAgICAgICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogU3lzdGVtUHJvcGVy
dGllcy5vcGVuVXJsKCJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3ZpYmVtaXMiKQogICAg
ICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICBCdXR0b24gewpkaWZmIC0tZ2l0IGEvYXBw
L2d1aS9TeXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwgYi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rp
b25zRGlhbG9nLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uY2ZmNGM2
NjAKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9nLnFt
bApAQCAtMCwwICsxLDEwNyBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5D
b250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkxheW91dHMgMS4zCitpbXBvcnQgUXRRdWljay5D
b250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0
IFN5c3RlbUNvbnRyb2xzIDEuMAorCitOYXZpZ2FibGVEaWFsb2cgeworICAgIGlkOiBwYW5lbAor
ICAgIHByb3BlcnR5IHN0cmluZyBraW5kOiAid2lmaSIKKyAgICBwcm9wZXJ0eSB2YXIgc2VsZWN0
ZWQ6ICh7fSkKKyAgICB3aWR0aDogTWF0aC5taW4oNjIwLCBwYXJlbnQud2lkdGggLSAzMikKKyAg
ICBoZWlnaHQ6IE1hdGgubWluKDU2MCwgcGFyZW50LmhlaWdodCAtIDMyKQorICAgIHRpdGxlOiBr
aW5kID09PSAid2lmaSIgPyBxc1RyKCJXaS1GaSBuZXR3b3JrcyIpIDogcXNUcigiQmx1ZXRvb3Ro
IGRldmljZXMiKQorICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLkNsb3NlCisgICAgTWF0ZXJp
YWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRv
a2Vucy5hY2NlbnQKKyAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgeyBjb2xvcjogVmJUb2tlbnMu
YmdFbGV2OyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0RpYWxvZzsgYm9yZGVyLmNvbG9yOiBWYlRv
a2Vucy5zdHJva2UgfQorICAgIG9uT3BlbmVkOiB7IHNlbGVjdGVkID0gKHt9KTsgU3lzdGVtQ29u
dHJvbHMub3BlbihraW5kKSB9CisgICAgb25DbG9zZWQ6IHsgY3JlZGVudGlhbC5jbG9zZSgpOyBz
ZWNyZXQudGV4dCA9ICIiOyBmb3JnZXQuY2xvc2UoKTsgU3lzdGVtQ29udHJvbHMuY2xvc2UoKSB9
CisgICAgY29udGVudEl0ZW06IENvbHVtbkxheW91dCB7CisgICAgICAgIHNwYWNpbmc6IFZiVG9r
ZW5zLnNwYWNlMworICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgTGF5b3V0LmZpbGxX
aWR0aDogdHJ1ZQorICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3
cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgdGV4dDogU3lz
dGVtQ29udHJvbHMuc3RhdHVzOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAg
ICBCdXN5SW5kaWNhdG9yIHsgcnVubmluZzogU3lzdGVtQ29udHJvbHMuYnVzeTsgdmlzaWJsZTog
cnVubmluZzsgaW1wbGljaXRXaWR0aDogMzI7IGltcGxpY2l0SGVpZ2h0OiAzMiB9CisgICAgICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgaWQ6IHNjYW5CdXR0b247IHRleHQ6IHFzVHIoIlNj
YW4iKTsgZW5hYmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogeyBwYW5lbC5z
ZWxlY3RlZCA9ICh7fSk7IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QocGFuZWwua2luZCArICItc2Nh
biIpIH0gfQorICAgICAgICB9CisgICAgICAgIExhYmVsIHsKKyAgICAgICAgICAgIExheW91dC5m
aWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IGNvbG9yOiBWYlRva2Vucy50ZXh0
RGltCisgICAgICAgICAgICB0ZXh0OiBwYW5lbC5raW5kID09PSAid2lmaSIgPyBxc1RyKCJTZWxl
Y3QgYSBuZXR3b3JrLCB0aGVuIENvbm5lY3QuIEFkdmFuY2VkIG9yIGhpZGRlbiBuZXR3b3JrcyBh
cmUgYXZhaWxhYmxlIGluIHRoZSBkaWFnbm9zdGljIHNoZWxsLiIpIDogcXNUcigiUHV0IHlvdXIg
Y29udHJvbGxlciBvciBoZWFkcGhvbmVzIGluIHBhaXJpbmcgbW9kZSwgdGhlbiBTY2FuLiBQYWly
aW5nIG1heSB0YWtlIHVwIHRvIGEgbWludXRlLiIpCisgICAgICAgIH0KKyAgICAgICAgTGlzdFZp
ZXcgeworICAgICAgICAgICAgaWQ6IGRldmljZXMKKyAgICAgICAgICAgIExheW91dC5maWxsV2lk
dGg6IHRydWU7IExheW91dC5maWxsSGVpZ2h0OiB0cnVlCisgICAgICAgICAgICBjbGlwOiB0cnVl
OyBzcGFjaW5nOiA0OyBtb2RlbDogU3lzdGVtQ29udHJvbHMuaXRlbXMKKyAgICAgICAgICAgIFNj
cm9sbEJhci52ZXJ0aWNhbDogU2Nyb2xsQmFyIHt9CisgICAgICAgICAgICBkZWxlZ2F0ZTogSXRl
bURlbGVnYXRlIHsKKyAgICAgICAgICAgICAgICB3aWR0aDogZGV2aWNlcy53aWR0aAorICAgICAg
ICAgICAgICAgIGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5CisgICAgICAgICAgICAgICAg
aGlnaGxpZ2h0ZWQ6IHBhbmVsLnNlbGVjdGVkLmlkID09PSBtb2RlbERhdGEuaWQKKyAgICAgICAg
ICAgICAgICBhY3RpdmVGb2N1c09uVGFiOiB0cnVlCisgICAgICAgICAgICAgICAgS2V5cy5vblJl
dHVyblByZXNzZWQ6IGlmIChlbmFibGVkKSBjbGlja2VkKCkKKyAgICAgICAgICAgICAgICBLZXlz
Lm9uRW50ZXJQcmVzc2VkOiBpZiAoZW5hYmxlZCkgY2xpY2tlZCgpCisgICAgICAgICAgICAgICAg
S2V5cy5vbkRvd25QcmVzc2VkOiB7IGlmIChpbmRleCArIDEgPCBkZXZpY2VzLmNvdW50KSB7IGRl
dmljZXMuaW5jcmVtZW50Q3VycmVudEluZGV4KCk7IGlmIChkZXZpY2VzLmN1cnJlbnRJdGVtKSBk
ZXZpY2VzLmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpIH0gZWxzZSBp
ZiAoY29ubmVjdEJ1dHRvbi5lbmFibGVkKSBjb25uZWN0QnV0dG9uLmZvcmNlQWN0aXZlRm9jdXMo
UXQuVGFiRm9jdXMpOyBlbHNlIHNjYW5CdXR0b24uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1
cykgfQorICAgICAgICAgICAgICAgIEtleXMub25VcFByZXNzZWQ6IHsgaWYgKGluZGV4ID4gMCkg
eyBkZXZpY2VzLmRlY3JlbWVudEN1cnJlbnRJbmRleCgpOyBpZiAoZGV2aWNlcy5jdXJyZW50SXRl
bSkgZGV2aWNlcy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKSB9IGVs
c2Ugc2NhbkJ1dHRvbi5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKSB9CisgICAgICAgICAg
ICAgICAgY29udGVudEl0ZW06IExhYmVsIHsKKyAgICAgICAgICAgICAgICAgICAgdGV4dEZvcm1h
dDogVGV4dC5QbGFpblRleHQ7IGVsaWRlOiBUZXh0LkVsaWRlUmlnaHQ7IGNvbG9yOiBWYlRva2Vu
cy50ZXh0CisgICAgICAgICAgICAgICAgICAgIHRleHQ6IG1vZGVsRGF0YS5uYW1lICsgIiDCtyAi
ICsgbW9kZWxEYXRhLmRldGFpbCArIChtb2RlbERhdGEuY29ubmVjdGVkID8gIiDCtyAiICsgcXNU
cigiQ29ubmVjdGVkIikgOiAiIikKKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAg
b25DbGlja2VkOiB7IHBhbmVsLnNlbGVjdGVkID0gbW9kZWxEYXRhOyBkZXZpY2VzLmN1cnJlbnRJ
bmRleCA9IGluZGV4IH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgICAgICBSb3dMYXlv
dXQgeworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQorICAgICAgICAgICAgRWNs
aXBzZUFjdGlvbkJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IGNvbm5lY3RCdXR0b24KKyAg
ICAgICAgICAgICAgICB0ZXh0OiBwYW5lbC5raW5kID09PSAid2lmaSIgPyBxc1RyKCJDb25uZWN0
IikgOiBxc1RyKCJQYWlyIC8gQ29ubmVjdCIpCisgICAgICAgICAgICAgICAgZW5hYmxlZDogISFw
YW5lbC5zZWxlY3RlZC5pZCAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAgICAgICAgICAg
IG9uQ2xpY2tlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdChwYW5lbC5raW5kICsgIi1jb25uZWN0
IiwgcGFuZWwuc2VsZWN0ZWQuaWQpCisgICAgICAgICAgICB9CisgICAgICAgICAgICBFY2xpcHNl
QWN0aW9uQnV0dG9uIHsKKyAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJEaXNjb25uZWN0Iik7
IGVuYWJsZWQ6ICEhcGFuZWwuc2VsZWN0ZWQuaWQgJiYgcGFuZWwuc2VsZWN0ZWQuY29ubmVjdGVk
ICYmICFTeXN0ZW1Db250cm9scy5idXN5CisgICAgICAgICAgICAgICAgb25DbGlja2VkOiBTeXN0
ZW1Db250cm9scy5yZXF1ZXN0KHBhbmVsLmtpbmQgKyAiLWRpc2Nvbm5lY3QiLCBwYW5lbC5zZWxl
Y3RlZC5pZCkKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24g
eyB0ZXh0OiBxc1RyKCJGb3JnZXQiKTsgdmlzaWJsZTogcGFuZWwua2luZCA9PT0gImJ0IjsgZW5h
YmxlZDogISFwYW5lbC5zZWxlY3RlZC5pZCAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlj
a2VkOiBmb3JnZXQub3BlbigpIH0KKyAgICAgICAgfQorICAgIH0KKyAgICBDb25uZWN0aW9ucyB7
CisgICAgICAgIHRhcmdldDogU3lzdGVtQ29udHJvbHMKKyAgICAgICAgb25DaGFuZ2VkOiB7Cisg
ICAgICAgICAgICBpZiAoU3lzdGVtQ29udHJvbHMucHJvbXB0Lmxlbmd0aCA+IDAgJiYgcGFuZWwu
b3BlbmVkICYmICFjcmVkZW50aWFsLm9wZW5lZCkgY3JlZGVudGlhbC5vcGVuKCkKKyAgICAgICAg
ICAgIGlmICghU3lzdGVtQ29udHJvbHMuYnVzeSkgeworICAgICAgICAgICAgICAgIGNyZWRlbnRp
YWwuY2xvc2UoKTsgc2VjcmV0LnRleHQgPSAiIgorICAgICAgICAgICAgICAgIHZhciBpZCA9IHBh
bmVsLnNlbGVjdGVkLmlkCisgICAgICAgICAgICAgICAgcGFuZWwuc2VsZWN0ZWQgPSAoe30pCisg
ICAgICAgICAgICAgICAgZm9yICh2YXIgaSA9IDA7IGkgPCBTeXN0ZW1Db250cm9scy5pdGVtcy5s
ZW5ndGg7IGkrKykKKyAgICAgICAgICAgICAgICAgICAgaWYgKFN5c3RlbUNvbnRyb2xzLml0ZW1z
W2ldLmlkID09PSBpZCkgcGFuZWwuc2VsZWN0ZWQgPSBTeXN0ZW1Db250cm9scy5pdGVtc1tpXQor
ICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQorICAgIE5hdmlnYWJsZURpYWxvZyB7Cisg
ICAgICAgIGlkOiBjcmVkZW50aWFsCisgICAgICAgIHRpdGxlOiBxc1RyKCJDb25uZWN0aW9uIGF1
dGhlbnRpY2F0aW9uIikKKyAgICAgICAgd2lkdGg6IE1hdGgubWluKDQ4MCwgcGFuZWwud2lkdGgp
CisgICAgICAgIGNsb3NlUG9saWN5OiBQb3B1cC5Ob0F1dG9DbG9zZQorICAgICAgICBzdGFuZGFy
ZEJ1dHRvbnM6IERpYWxvZy5PayB8IERpYWxvZy5DYW5jZWwKKyAgICAgICAgTWF0ZXJpYWwuYmFj
a2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgICAgIG9uT3BlbmVkOiB7IHNlY3JldC50ZXh0
ID0gIiI7IHNlY3JldC5mb3JjZUFjdGl2ZUZvY3VzKCkgfQorICAgICAgICBvbkFjY2VwdGVkOiB7
IFN5c3RlbUNvbnRyb2xzLmFuc3dlcihzZWNyZXQudGV4dCk7IHNlY3JldC50ZXh0ID0gIiIgfQor
ICAgICAgICBvblJlamVjdGVkOiB7IHNlY3JldC50ZXh0ID0gIiI7IFN5c3RlbUNvbnRyb2xzLmNs
b3NlKCkgfQorICAgICAgICBjb250ZW50SXRlbTogQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAg
IExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRl
eHQ7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IFN5c3RlbUNvbnRyb2xzLnByb21wdDsgY29s
b3I6IFZiVG9rZW5zLnRleHQgfQorICAgICAgICAgICAgVGV4dEZpZWxkIHsgaWQ6IHNlY3JldDsg
TGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgZWNob01vZGU6IFRleHRJbnB1dC5QYXNzd29yZDsgbWF4
aW11bUxlbmd0aDogNDA5Njsgc2VsZWN0QnlNb3VzZTogdHJ1ZTsgb25BY2NlcHRlZDogY3JlZGVu
dGlhbC5hY2NlcHQoKSB9CisgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRy
dWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIkVudGVyIHRoZSByZXF1ZXN0ZWQg
cGFzc3dvcmQgb3IgUElOLiBGb3IgYSB5ZXMvbm8gY29uZmlybWF0aW9uLCB0eXBlIHllcyBvciBu
by4iKTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICB9CisgICAgfQorICAgIE5h
dmlnYWJsZURpYWxvZyB7CisgICAgICAgIGlkOiBmb3JnZXQKKyAgICAgICAgdGl0bGU6IHFzVHIo
IkZvcmdldCBCbHVldG9vdGggZGV2aWNlPyIpCisgICAgICAgIHdpZHRoOiBNYXRoLm1pbig0ODAs
IHBhbmVsLndpZHRoKQorICAgICAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5ZZXMgfCBEaWFs
b2cuTm8KKyAgICAgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAg
ICAgIG9uQWNjZXB0ZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QoImJ0LWZvcmdldCIsIHBhbmVs
LnNlbGVjdGVkLmlkLCB0cnVlKQorICAgICAgICBjb250ZW50SXRlbTogTGFiZWwgeyB0ZXh0Rm9y
bWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcXNUcigiUmVt
b3ZlIHRoZSBzYXZlZCBwYWlyaW5nIGZvciAlMT8gWW91IHdpbGwgbmVlZCB0byBwYWlyIGl0IGFn
YWluLiIpLmFyZyhwYW5lbC5zZWxlY3RlZC5uYW1lIHx8ICIiKTsgY29sb3I6IFZiVG9rZW5zLnRl
eHQgfQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvVGhlbWUucW1sIGIvYXBwL2d1aS9U
aGVtZS5xbWwKaW5kZXggZmI5MWM4NTAuLjU3YzlmODQ4IDEwMDY0NAotLS0gYS9hcHAvZ3VpL1Ro
ZW1lLnFtbAorKysgYi9hcHAvZ3VpL1RoZW1lLnFtbApAQCAtMTEsMjAgKzExLDIwIEBAIGltcG9y
dCBWaWJlbWlzLlJlZGVzaWduIDEuMAogUXRPYmplY3QgewogICAgIC8vIC0tLS0gQ29sb3IgLS0t
LQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAgICAgIFZiVG9rZW5zLmFj
Y2VudCAgLy8gQkwtMjA3Nzogc2luZ2xlIHNvdXJjZSBvZiB0cnV0aCAoVmJUb2tlbnMgYnJhbmQg
YWNjZW50LCBkZWZhdWx0ICMwMENDQ0MpCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNj
ZW50UHJlc3NlZDogIiMwMEEzQTMiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmFja2dy
b3VuZDogICAgIiMzMDMwMzAiICAvLyBhcHAgcm9vdAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIHN1cmZhY2U6ICAgICAgICIjMkQyRDJEIiAgLy8gcmFpc2VkIHN1cmZhY2VzIC8gb3Zlcmxh
eXMKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdXJmYWNlQWx0OiAgICAiIzQyNDI0MiIg
IC8vIHBvcHVwcyAvIGNvbWJvIGRyb3Bkb3ducwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9y
IGJvcmRlcjogICAgICAgICIjNDQ0NDQ0IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRl
eHRQcmltYXJ5OiAgICIjRkZGRkZGIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRT
ZWNvbmRhcnk6ICIjQ0NDQ0NDIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRUZXJ0
aWFyeTogICIjQUFBQUFBIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHREaXNhYmxl
ZDogICIjNzc3Nzc3IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1Y2Nlc3M6ICAgICAg
ICIjNENBRjUwIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHdhcm5pbmc6ICAgICAgICIj
RTBBMDMwIiAgLy8gdGhlIHNpbmdsZSBhbWJlcgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9y
IGVycm9yOiAgICAgICAgICIjRjQ0MzM2IgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGlu
Zm86ICAgICAgICAgICIjODBBMEMwIgotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHNjcmlt
OiAgICAgICAgICIjRDAwMDAwMDAiCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50
UHJlc3NlZDogVmJUb2tlbnMuYWNjZW50UHJlc3NlZAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIGJhY2tncm91bmQ6ICAgIFZiVG9rZW5zLmJnV2luZG93ICAvLyBhcHAgcm9vdAorICAgIHJl
YWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZhY2U6ICAgICAgIFZiVG9rZW5zLmJnRWxldiAgLy8g
cmFpc2VkIHN1cmZhY2VzIC8gb3ZlcmxheXMKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBz
dXJmYWNlQWx0OiAgICBWYlRva2Vucy5iZ0VsZXYyICAvLyBwb3B1cHMgLyBjb21ibyBkcm9wZG93
bnMKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBib3JkZXI6ICAgICAgICBWYlRva2Vucy5z
dHJva2UKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0UHJpbWFyeTogICBWYlRva2Vu
cy50ZXh0UHJpbWFyeQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRTZWNvbmRhcnk6
IFZiVG9rZW5zLnRleHRTZWNvbmRhcnkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0
VGVydGlhcnk6ICBWYlRva2Vucy50ZXh0VGVydGlhcnkKKyAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciB0ZXh0RGlzYWJsZWQ6ICBWYlRva2Vucy50ZXh0RGlzYWJsZWQKKyAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciBzdWNjZXNzOiAgICAgICBWYlRva2Vucy5zdGF0dXNTdWNjZXNzCisgICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3Igd2FybmluZzogICAgICAgVmJUb2tlbnMuc3RhdHVzV2Fy
bmluZyAgLy8gdGhlIHNpbmdsZSBhbWJlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGVy
cm9yOiAgICAgICAgIFZiVG9rZW5zLnN0YXR1c0RhbmdlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIGluZm86ICAgICAgICAgIFZiVG9rZW5zLnN0YXR1c0luZm8KKyAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciBzY3JpbTogICAgICAgICBWYlRva2Vucy5kaWFsb2dTY3JpbQogCiAgICAg
Ly8gLS0tLSBUeXBvZ3JhcGh5IChwb2ludFNpemU7IHBhaXIgd2l0aCBib2xkIHdoZXJlIG5vdGVk
IGluIERFU0lHTl9TWVNURU0ubWQpIC0tLS0KICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgZm9u
dERpc3BsYXk6IDI0ICAvLyBvdmVybGF5L1F1aWNrIE1lbnUgdGl0bGUgKGJvbGQpCmRpZmYgLS1n
aXQgYS9hcHAvZ3VpL1ZiQ2FyZC5xbWwgYi9hcHAvZ3VpL1ZiQ2FyZC5xbWwKaW5kZXggMzdmMmUz
MmQuLjFlOTBhMDJkIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiQ2FyZC5xbWwKKysrIGIvYXBwL2d1
aS9WYkNhcmQucW1sCkBAIC0yNyw3ICsyNyw3IEBAIEl0ZW0gewogICAgICAgICBib3JkZXIud2lk
dGg6IDEKICAgICAgICAgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UKICAgICAgICAgb3Bh
Y2l0eTogY2FyZC5jb250ZW50T3BhY2l0eQotICAgICAgICBCZWhhdmlvciBvbiBjb2xvciB7IENv
bG9yQW5pbWF0aW9uIHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAgICAgQmVoYXZpb3Igb24gY29s
b3IgeyBDb2xvckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFibGVkID8g
MTIwIDogMCB9IH0KICAgICB9CiAKICAgICBJdGVtIHsKZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJT
dGF0dXNQaWxsLnFtbCBiL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbAppbmRleCA4OWM0NzcwYS4u
YzcyOGYwNTIgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbAorKysgYi9hcHAv
Z3VpL1ZiU3RhdHVzUGlsbC5xbWwKQEAgLTI0LDcgKzI0LDcgQEAgUmVjdGFuZ2xlIHsKICAgICAg
ICAgICAgIGNvbG9yOiBwaWxsLm9ubGluZSA/IFZiVG9rZW5zLnN0YXR1c09ubGluZSA6IFZiVG9r
ZW5zLnN0YXR1c09mZmxpbmUKICAgICAgICAgICAgIC8vIFB1bHNlIG9ubHkgd2hlbiBvbmxpbmUu
CiAgICAgICAgICAgICBTZXF1ZW50aWFsQW5pbWF0aW9uIG9uIG9wYWNpdHkgewotICAgICAgICAg
ICAgICAgIHJ1bm5pbmc6IHBpbGwub25saW5lCisgICAgICAgICAgICAgICAgcnVubmluZzogcGls
bC5vbmxpbmUgJiYgVmJUb2tlbnMubW90aW9uRW5hYmxlZAogICAgICAgICAgICAgICAgIGxvb3Bz
OiBBbmltYXRpb24uSW5maW5pdGUKICAgICAgICAgICAgICAgICBOdW1iZXJBbmltYXRpb24geyBm
cm9tOiAxLjA7IHRvOiAwLjQ1OyBkdXJhdGlvbjogVmJUb2tlbnMub25saW5lUHVsc2VNcyAvIDI7
IGVhc2luZy50eXBlOiBFYXNpbmcuSW5PdXRTaW5lIH0KICAgICAgICAgICAgICAgICBOdW1iZXJB
bmltYXRpb24geyBmcm9tOiAwLjQ1OyB0bzogMS4wOyBkdXJhdGlvbjogVmJUb2tlbnMub25saW5l
UHVsc2VNcyAvIDI7IGVhc2luZy50eXBlOiBFYXNpbmcuSW5PdXRTaW5lIH0KZGlmZiAtLWdpdCBh
L2FwcC9ndWkvVmJUb2tlbnMucW1sIGIvYXBwL2d1aS9WYlRva2Vucy5xbWwKaW5kZXggNTJhMzRk
ZTQuLmNiZjc5ODVmIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiVG9rZW5zLnFtbAorKysgYi9hcHAv
Z3VpL1ZiVG9rZW5zLnFtbApAQCAtMSw2ICsxLDcgQEAKIHByYWdtYSBTaW5nbGV0b24KIGltcG9y
dCBRdFF1aWNrIDIuOQogaW1wb3J0IFN0cmVhbWluZ1ByZWZlcmVuY2VzIDEuMAoraW1wb3J0IEVj
bGlwc2VQcm9maWxlcyAxLjAKIAogLy8gVmliZW1pcyByZWRlc2lnbiBkZXNpZ24gdG9rZW5zLgog
Ly8gRGFyayB0aGVtZSBvbmx5LiBDYW52YXMgMTkyMHgxMjAwIChMZWdpb24gR28gUyksCkBAIC05
LDQzICsxMCw0NCBAQCBpbXBvcnQgU3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCiBRdE9iamVjdCB7
CiAgICAgaWQ6IHQKIAorICAgIHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgdGV4dFNjYWxlOiBFY2xp
cHNlUHJvZmlsZXMudGV4dFNjYWxlIC8gMTAwCisgICAgcmVhZG9ubHkgcHJvcGVydHkgYm9vbCBt
b3Rpb25FbmFibGVkOiAhRWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb24KKwogICAgIC8vIC0t
LS0gQ29sb3IgLS0tLQotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnQXBwOiAgICAgICAg
IiMwODA5MEIiICAvLyBvdXRlcm1vc3QgYXBwIGJnIGJlaGluZCB0aGUgcm91bmRlZCB3aW5kb3cK
LSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ1dpbmRvdzogICAgICIjMEUxMDEzIiAgLy8g
bWFpbiBzY3JlZW4gYmFja2dyb3VuZAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxl
djogICAgICAgIiMxNTE4MUQiICAvLyBjYXJkcywgcGFuZWxzLCBkaWFsb2dzLCBzaWRlYmFyIHJv
d3MKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0VsZXYyOiAgICAgICIjMUIxRjI2IiAg
Ly8gZm9jdXNlZC9zZWxlY3RlZCBzdXJmYWNlIGZpbGwsIGNoaXBzCi0gICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3IgYmdGb290ZXI6ICAgICAiIzBCMEQxMCIgIC8vIGJvdHRvbSBnYW1lcGFkIGhp
bnQgYmFyCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Ryb2tlOiAgICAgICBRdC5yZ2Jh
KDEsIDEsIDEsIDAuMDgpICAvLyBkZWZhdWx0IDFweCBjYXJkIGJvcmRlcgorICAgIHJlYWRvbmx5
IHByb3BlcnR5IGNvbG9yIGJnQXBwOiAgICAgICAgIiMwNjA2MDciICAvLyBvdXRlcm1vc3QgYXBw
IGJnIGJlaGluZCB0aGUgcm91bmRlZCB3aW5kb3cKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xv
ciBiZ1dpbmRvdzogICAgICIjMEIwQjBFIiAgLy8gbWFpbiBzY3JlZW4gYmFja2dyb3VuZAorICAg
IHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxldjogICAgICAgIiMxNTExMTUiICAvLyBjYXJk
cywgcGFuZWxzLCBkaWFsb2dzLCBzaWRlYmFyIHJvd3MKKyAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciBiZ0VsZXYyOiAgICAgICIjMjExNzFDIiAgLy8gZm9jdXNlZC9zZWxlY3RlZCBzdXJmYWNl
IGZpbGwsIGNoaXBzCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdGb290ZXI6ICAgICAi
IzA5MDgwQiIgIC8vIGJvdHRvbSBnYW1lcGFkIGhpbnQgYmFyCisgICAgcmVhZG9ubHkgcHJvcGVy
dHkgY29sb3Igc3Ryb2tlOiAgICAgICBRdC5yZ2JhKDEsIDEsIDEsIEVjbGlwc2VQcm9maWxlcy5o
aWdoQ29udHJhc3QgPyAwLjI1IDogMC4wOCkgIC8vIGRlZmF1bHQgMXB4IGNhcmQgYm9yZGVyCiAg
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Ryb2tlU29mdDogICBRdC5yZ2JhKDEsIDEsIDEs
IDAuMDYpICAvLyBoZWFkZXIvZm9vdGVyIGRpdmlkZXJzCiAgICAgcmVhZG9ubHkgcHJvcGVydHkg
Y29sb3IgdGV4dDogICAgICAgICAiI0VDRUVGMSIgIC8vIHByaW1hcnkgdGV4dAotICAgIHJlYWRv
bmx5IHByb3BlcnR5IGNvbG9yIHRleHREaW06ICAgICAgIiM5OEExQUIiICAvLyBzZWNvbmRhcnkg
LyBsYWJlbCB0ZXh0CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpbTogICAgICAo
RWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdCA/ICIjRDNENURDIiA6ICIjOThBMUFCIikgIC8v
IHNlY29uZGFyeSAvIGxhYmVsIHRleHQKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0
TXV0ZTogICAgICIjQjlDMEM4IiAgLy8gdGVydGlhcnkgLyBpbmFjdGl2ZSBpdGVtIGxhYmVscwog
Ci0gICAgLy8gQWNjZW50IGlzIHN3YXBwYWJsZSDigJQgb25lIG9mIHRoZSA0IGN1cmF0ZWQgdmFs
dWVzLiBJbmRleCAwIGlzIHRoZSBWaWJlbWlzIGJyYW5kCi0gICAgLy8gdGVhbCAjMDBDQ0NDIChC
TC0yMDc3KTogdGhlIHNpbmdsZSBjYW5vbmljYWwgYWNjZW50IHRoYXQgVGhlbWUucW1sICsgYWxs
IGxpdGVyYWxzIG5vdwotICAgIC8vIHJlc29sdmUgdGhyb3VnaCwgYW5kIHRoZSBhbmNob3IgZm9y
IHRoZSBQMy4xNy9QMy4xOCBkZXNpZ24gd29yay4KLSAgICByZWFkb25seSBwcm9wZXJ0eSB2YXIg
YWNjZW50T3B0aW9uczogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1OTgiLCAiI0YwQTg2
OCJdCisgICAgLy8gUHJlc2VydmUgbGVnYWN5IGluZGljZXMgMC4uMzsgYXBwZW5kIGNvbG9ycyBh
bmQgZGVmYXVsdCBuZXcgcHJlZmVyZW5jZXMgdG8gY3JpbXNvbi4KKyAgICByZWFkb25seSBwcm9w
ZXJ0eSB2YXIgYWNjZW50T3B0aW9uczogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1OTgi
LCAiI0YwQTg2OCIsICIjREMzNjU4IiwgIiNGMjVENjQiLCAiI0Y1ODM0NyIsICIjRjFCQzQ1Iiwg
IiNCN0RDNjMiLCAiIzYzQ0NBRSIsICIjNjNDNEVEIiwgIiM2QzlGRkYiLCAiI0FEODVGNSIsICIj
RTk3NkJDIiwgIiNDQUQwREEiLCAiI0Q5OTVBQyJdCiAgICAgLy8gQm91bmQgdG8gdGhlIHNhdmVk
IHByZWZlcmVuY2UgKFNldHRpbmdzID4gYWNjZW50IHBpY2tlcik7IHBlcnNpc3RzIGFjcm9zcyBy
ZXN0YXJ0cy4KICAgICBwcm9wZXJ0eSBpbnQgYWNjZW50SW5kZXg6IFN0cmVhbWluZ1ByZWZlcmVu
Y2VzLnVpQWNjZW50SW5kZXgKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnQ6ICAg
ICAgIGFjY2VudE9wdGlvbnNbYWNjZW50SW5kZXhdCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29s
b3IgYWNjZW50SGk6ICAgICAiIzZBRERFNyIgIC8vIGFjY2VudCBncmFkaWVudCBsaWdodCBzdG9w
IC8gbGluayBob3ZlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAgICAg
YWNjZW50T3B0aW9uc1tNYXRoLm1heCgwLCBNYXRoLm1pbihhY2NlbnRPcHRpb25zLmxlbmd0aCAt
IDEsIGFjY2VudEluZGV4KSldCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50SGk6
ICAgICBRdC5saWdodGVyKGFjY2VudCwgMS4xOCkgIC8vIGFjY2VudCBncmFkaWVudCBsaWdodCBz
dG9wIC8gbGluayBob3ZlcgogCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3RhdHVzT25s
aW5lOiAgIiMzRUQ1OTgiICAvLyBvbmxpbmUgZG90LCBSRVNVTUUgYmFkZ2UKICAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNPZmZsaW5lOiAiIzVBNjI2QyIgIC8vIG9mZmxpbmUgZG90
IC8gZ3JleWVkIG1vbml0b3IKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNEYW5n
ZXI6ICAiI0YyNkQ2RCIgIC8vIGRlc3RydWN0aXZlIChEZWxldGUgUEMpCiAKLSAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciB0ZXh0T25BY2NlbnQ6ICIjMDgwOTBCIiAgLy8gdGV4dCBvbiBhbiBh
Y2NlbnQtZmlsbGVkIGJ1dHRvbgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRPbkFj
Y2VudDogIiMwNjA2MDciICAvLyB0ZXh0IG9uIGFuIGFjY2VudC1maWxsZWQgYnV0dG9uCiAKICAg
ICAvLyAtLS0tIFR5cG9ncmFwaHkgKGZhbWlsaWVzICsgc2l6ZXM7IHdlaWdodHMgcGVyIHRoZSB0
eXBlIHNjYWxlKSAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgc3RyaW5nIGZvbnREaXNwbGF5
OiAiU29yYSIgICAgIC8vIHRpdGxlcywgY2FyZCBuYW1lcywgd29yZG1hcmssIGFsbC1jYXBzIGxh
YmVscwogICAgIHJlYWRvbmx5IHByb3BlcnR5IHN0cmluZyBmb250Qm9keTogICAgIk1hbnJvcGUi
ICAvLyBib2R5ICsgVUkgdGV4dAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2NyZWVu
VGl0bGU6ICAzNAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2VjdGlvblRpdGxlOiAy
OAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplQ2FyZE5hbWU6ICAgICAyNwotICAgIHJl
YWRvbmx5IHByb3BlcnR5IGludCBzaXplQm9keTogICAgICAgICAxNgotICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGludCBzaXplTGFiZWw6ICAgICAgICAxNAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGlu
dCBzaXplQmFkZ2U6ICAgICAgICAxMwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplV29y
ZG1hcms6ICAgICAyMQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplU2NyZWVuVGl0bGU6
ICBNYXRoLnJvdW5kKDM0ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBz
aXplU2VjdGlvblRpdGxlOiBNYXRoLnJvdW5kKDI4ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5
IHByb3BlcnR5IGludCBzaXplQ2FyZE5hbWU6ICAgICBNYXRoLnJvdW5kKDI3ICogdGV4dFNjYWxl
KQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplQm9keTogICAgICAgICBNYXRoLnJvdW5k
KDE2ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBzaXplTGFiZWw6ICAg
ICAgICBNYXRoLnJvdW5kKDE0ICogdGV4dFNjYWxlKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGlu
dCBzaXplQmFkZ2U6ICAgICAgICBNYXRoLnJvdW5kKDEzICogdGV4dFNjYWxlKQorICAgIHJlYWRv
bmx5IHByb3BlcnR5IGludCBzaXplV29yZG1hcms6ICAgICBNYXRoLnJvdW5kKDIxICogdGV4dFNj
YWxlKQogICAgIHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgd29yZG1hcmtTcGFjaW5nOiAzLjAKICAg
ICByZWFkb25seSBwcm9wZXJ0eSByZWFsIGJhZGdlU3BhY2luZzogICAgMS4yCiAKQEAgLTgzLDcg
Kzg1LDcgQEAgUXRPYmplY3QgewogICAgIC8vIC0tLS0gTW90aW9uIChtcykgLS0tLQogICAgIHJl
YWRvbmx5IHByb3BlcnR5IGludCBvbmxpbmVQdWxzZU1zOiAyNDAwICAgLy8gb3BhY2l0eSAxIC0+
IDAuNDUgLT4gMSwgaW5maW5pdGUKICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgY2FyZXRCbGlu
a01zOiAgMTAwMCAgIC8vIEFkZC1QQyBpbnB1dCBjYXJldAotICAgIHJlYWRvbmx5IHByb3BlcnR5
IGludCBzaGVldEluTXM6ICAgICAyMjAgICAgLy8gc2lkZS1zaGVldCBzbGlkZS1pbgorICAgIHJl
YWRvbmx5IHByb3BlcnR5IGludCBzaGVldEluTXM6ICAgICBtb3Rpb25FbmFibGVkID8gMjIwIDog
MCAgICAvLyBzaWRlLXNoZWV0IHNsaWRlLWluCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
ZGlhbG9nU2NyaW06IFF0LnJnYmEoNC8yNTUsIDUvMjU1LCA3LzI1NSwgMC43MikKICAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciBzaGVldFNjcmltOiAgUXQucmdiYSg0LzI1NSwgNS8yNTUsIDcv
MjU1LCAwLjYwKQogCkBAIC0xMTksNyArMTIxLDcgQEAgUXRPYmplY3QgewogICAgIC8vIHRleHRP
bkFjY2VudCAoIzA4MDkwQikgaXMgZGVmaW5lZCBpbiB0aGUgYmFzZSBibG9jayBhYm92ZSDigJQg
dGV4dCBvbiBhbiBhY2NlbnQgZmlsbC4KIAogICAgIC8vIC0tLS0gSW50ZXJhY3RpdmUgc3RhdGVz
OiBub3JtYWwgLyBob3ZlciAvIGZvY3VzIC8gcHJlc3NlZCAvIGRpc2FibGVkIC0tLS0KLSAgICBy
ZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2VkOiAgICAgICIjMDBBM0EzIiAvLyBw
cmVzc2VkIGFjY2VudGVkIGNvbnRyb2wgKG1hdGNoZXMgbGVnYWN5IFRoZW1lLmFjY2VudFByZXNz
ZWQpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDogICAgICBRdC5k
YXJrZXIoYWNjZW50LCAxLjE4KSAvLyBwcmVzc2VkIGFjY2VudGVkIGNvbnRyb2wgKG1hdGNoZXMg
bGVnYWN5IFRoZW1lLmFjY2VudFByZXNzZWQpCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
aW50ZXJhY3RpdmVIb3ZlcjogICBiZ0VsZXYyICAgIC8vIHJvdyAvIGxpc3QtaXRlbSAvIGljb24t
YnV0dG9uIGhvdmVyIGZpbGwKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFjdGl2
ZUZvY3VzOiAgIGZvY3VzZWRGaWxsLy8gZm9jdXNlZCBmaWxsICg9IGJnRWxldjIpIOKAlCBwYWly
IHdpdGggdGhlIGZvY3VzIHJpbmcKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBpbnRlcmFj
dGl2ZVByZXNzZWQ6IGJnRWxldiAgICAgLy8gcHJlc3NlZCBuZXV0cmFsIGZpbGwgKHJlY2VkZXMg
dW5kZXIgdGhlIHByZXNzKQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9WYldlbGNvbWVTaGVldC5xbWwg
Yi9hcHAvZ3VpL1ZiV2VsY29tZVNoZWV0LnFtbAppbmRleCAxNzMxMTliOC4uNDM4M2NiMDcgMTAw
NjQ0Ci0tLSBhL2FwcC9ndWkvVmJXZWxjb21lU2hlZXQucW1sCisrKyBiL2FwcC9ndWkvVmJXZWxj
b21lU2hlZXQucW1sCkBAIC0xMDgsMTQgKzEwOCwxMyBAQCBOYXZpZ2FibGVEaWFsb2cgewogICAg
ICAgICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UyICAvLyA4CiAgICAgICAgICAgICBSb3dM
YXlvdXQgewogICAgICAgICAgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMgotICAgICAg
ICAgICAgICAgIFJlY3RhbmdsZSB7Ci0gICAgICAgICAgICAgICAgICAgIHdpZHRoOiAxMzsgaGVp
Z2h0OiAxMwotICAgICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYWNjZW50Ci0gICAg
ICAgICAgICAgICAgICAgIHJvdGF0aW9uOiA0NQorICAgICAgICAgICAgICAgIEltYWdlIHsKKyAg
ICAgICAgICAgICAgICAgICAgc291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2ZyIKKyAg
ICAgICAgICAgICAgICAgICAgTGF5b3V0LnByZWZlcnJlZFdpZHRoOiAyODsgTGF5b3V0LnByZWZl
cnJlZEhlaWdodDogMjgKICAgICAgICAgICAgICAgICAgICAgTGF5b3V0LmFsaWdubWVudDogUXQu
QWxpZ25WQ2VudGVyCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgIFRleHQgewot
ICAgICAgICAgICAgICAgICAgICB0ZXh0OiAiVklCRU1JUyIKKyAgICAgICAgICAgICAgICAgICAg
dGV4dDogIkVDTElQU0UiCiAgICAgICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vu
cy5mb250RGlzcGxheQogICAgICAgICAgICAgICAgICAgICBmb250LndlaWdodDogRm9udC5FeHRy
YUJvbGQKICAgICAgICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnNpemVX
b3JkbWFyayAgICAgIC8vIDIxCkBAIC0xMjUsNyArMTI0LDcgQEAgTmF2aWdhYmxlRGlhbG9nIHsK
ICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAgICAgICAgICAgICBUZXh0IHsKLSAg
ICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJXZWxjb21lIHRvIFZpYmVtaXMiKQorICAgICAgICAg
ICAgICAgIHRleHQ6IHFzVHIoIldlbGNvbWUgdG8gRWNsaXBzZSIpCiAgICAgICAgICAgICAgICAg
Zm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnREaXNwbGF5CiAgICAgICAgICAgICAgICAgZm9udC53
ZWlnaHQ6IEZvbnQuQm9sZAogICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vu
cy50eXBlRGlzcGxheSAgICAgICAgICAgLy8gMzQKQEAgLTE5NSw3ICsxOTQsNyBAQCBOYXZpZ2Fi
bGVEaWFsb2cgewogICAgICAgICAgICAgSW5mb1JvdyB7CiAgICAgICAgICAgICAgICAgZ2x5cGg6
ICJhcHBzIgogICAgICAgICAgICAgICAgIHRpdGxlOiBxc1RyKCJBZGQgdG8gU3RlYW0iKQotICAg
ICAgICAgICAgICAgIHN1YjogcXNUcigiT24gU3RlYW0gRGVjayAvIFN0ZWFtT1MsIGFkZCBWaWJl
bWlzIHRvIFN0ZWFtIGZyb20gRGVza3RvcCBNb2RlIHNvIGl0IGFwcGVhcnMgaW4gR2FtZSBNb2Rl
LiIpCisgICAgICAgICAgICAgICAgc3ViOiBxc1RyKCJPbiBTdGVhbSBEZWNrIC8gU3RlYW1PUywg
YWRkIEVjbGlwc2UgdG8gU3RlYW0gZnJvbSBEZXNrdG9wIE1vZGUgc28gaXQgYXBwZWFycyBpbiBH
YW1lIE1vZGUuIikKICAgICAgICAgICAgIH0KIAogICAgICAgICAgICAgLy8gMykgU2V0dGluZ3Mu
CmRpZmYgLS1naXQgYS9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuY3BwIGIvYXBwL2d1aS9jb21wdXRl
cm1vZGVsLmNwcAppbmRleCA2M2M3MTE1OC4uMmQ0ODdmZjUgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkv
Y29tcHV0ZXJtb2RlbC5jcHAKKysrIGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmNwcApAQCAtMSwz
ICsxLDQgQEAKKyNpbmNsdWRlIDxRVXJsPgogI2luY2x1ZGUgImNvbXB1dGVybW9kZWwuaCIKICNp
bmNsdWRlICJiYWNrZW5kL3NlcnZlcnBlcm1pc3Npb25zLmgiCiAjaW5jbHVkZSAic2V0dGluZ3Mv
dmliZW1pc3NldHRpbmdzLmgiCkBAIC00MjAsMyArNDIxLDEzIEBAIHZvaWQgQ29tcHV0ZXJNb2Rl
bDo6aGFuZGxlQ29tcHV0ZXJTdGF0ZUNoYW5nZWQoTnZDb21wdXRlciogY29tcHV0ZXIpCiB9CiAK
ICNpbmNsdWRlICJjb21wdXRlcm1vZGVsLm1vYyIKKworUVZhcmlhbnRNYXAgQ29tcHV0ZXJNb2Rl
bDo6Y3JpbXNvbkhvc3QoaW50IGluZGV4KSBjb25zdAoreworICAgIGlmIChpbmRleCA8IDAgfHwg
aW5kZXggPj0gbV9Db21wdXRlcnMuY291bnQoKSkgcmV0dXJuIHt9OworICAgIGF1dG8gY29tcHV0
ZXIgPSBtX0NvbXB1dGVyc1tpbmRleF07CisgICAgUVJlYWRMb2NrZXIgbG9jaygmY29tcHV0ZXIt
PmxvY2spOworICAgIFFVcmwgdXJsOyB1cmwuc2V0U2NoZW1lKCJodHRwcyIpOyB1cmwuc2V0SG9z
dChjb21wdXRlci0+YWN0aXZlQWRkcmVzcy5hZGRyZXNzKCkpOworICAgIHVybC5zZXRQb3J0KGNv
bXB1dGVyLT5hY3RpdmVBZGRyZXNzLnBvcnQoKSA+IDAgPyBjb21wdXRlci0+YWN0aXZlQWRkcmVz
cy5wb3J0KCkgKyAxIDogNDc5OTApOworICAgIHJldHVybiB7eyJpZCIsIGNvbXB1dGVyLT51dWlk
fSwgeyJ1cmwiLCB1cmwudG9TdHJpbmcoKX19OworfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9jb21w
dXRlcm1vZGVsLmggYi9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuaAppbmRleCA2ZWNhZTMwZC4uMmVl
NzNjMWQgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5oCisrKyBiL2FwcC9ndWkv
Y29tcHV0ZXJtb2RlbC5oCkBAIC00Myw2ICs0Myw4IEBAIHB1YmxpYzoKIAogICAgIHZpcnR1YWwg
UUhhc2g8aW50LCBRQnl0ZUFycmF5PiByb2xlTmFtZXMoKSBjb25zdCBvdmVycmlkZTsKIAorICAg
IFFfSU5WT0tBQkxFIFFWYXJpYW50TWFwIGNyaW1zb25Ib3N0KGludCBjb21wdXRlckluZGV4KSBj
b25zdDsKKwogICAgIFFfSU5WT0tBQkxFIHZvaWQgZGVsZXRlQ29tcHV0ZXIoaW50IGNvbXB1dGVy
SW5kZXgpOwogCiAgICAgUV9JTlZPS0FCTEUgUVN0cmluZyBnZW5lcmF0ZVBpblN0cmluZygpOwpk
aWZmIC0tZ2l0IGEvYXBwL2d1aS9tYWluLnFtbCBiL2FwcC9ndWkvbWFpbi5xbWwKaW5kZXggOWJj
ZTUxMDUuLjg0OGZjMTRlIDEwMDY0NAotLS0gYS9hcHAvZ3VpL21haW4ucW1sCisrKyBiL2FwcC9n
dWkvbWFpbi5xbWwKQEAgLTEyLDggKzEyLDI1IEBAIGltcG9ydCBTeXN0ZW1Qcm9wZXJ0aWVzIDEu
MAogaW1wb3J0IFNkbEdhbWVwYWRLZXlOYXZpZ2F0aW9uIDEuMAogaW1wb3J0IFVpU291bmRNYW5h
Z2VyIDEuMAogaW1wb3J0IFRoZW1lIDEuMAoraW1wb3J0IENyaW1zb25TdGF0dXMgMS4wCitpbXBv
cnQgU3lzdGVtQ29udHJvbHMgMS4wCiAKIEFwcGxpY2F0aW9uV2luZG93IHsKKyAgICBNYXRlcmlh
bC50aGVtZTogTWF0ZXJpYWwuRGFyaworICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNj
ZW50CisgICAgTWF0ZXJpYWwucHJpbWFyeTogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwu
YmFja2dyb3VuZDogVmJUb2tlbnMuYmdXaW5kb3cKKyAgICBNYXRlcmlhbC5mb3JlZ3JvdW5kOiBW
YlRva2Vucy50ZXh0CisgICAgY29sb3I6IFZiVG9rZW5zLmJnQXBwCisgICAgcGFsZXR0ZS53aW5k
b3c6IFZiVG9rZW5zLmJnV2luZG93CisgICAgcGFsZXR0ZS53aW5kb3dUZXh0OiBWYlRva2Vucy50
ZXh0CisgICAgcGFsZXR0ZS5iYXNlOiBWYlRva2Vucy5iZ0FwcAorICAgIHBhbGV0dGUuYWx0ZXJu
YXRlQmFzZTogVmJUb2tlbnMuYmdFbGV2CisgICAgcGFsZXR0ZS50ZXh0OiBWYlRva2Vucy50ZXh0
CisgICAgcGFsZXR0ZS5idXR0b246IFZiVG9rZW5zLmJnRWxldgorICAgIHBhbGV0dGUuYnV0dG9u
VGV4dDogVmJUb2tlbnMudGV4dAorICAgIHBhbGV0dGUuaGlnaGxpZ2h0OiBWYlRva2Vucy5hY2Nl
bnQKKyAgICBwYWxldHRlLmhpZ2hsaWdodGVkVGV4dDogVmJUb2tlbnMudGV4dE9uQWNjZW50CiAg
ICAgcHJvcGVydHkgYm9vbCBwb2xsaW5nQWN0aXZlOiBmYWxzZQogCiAgICAgLy8gU2V0IGJ5IFNl
dHRpbmdzVmlldyB0byBmb3JjZSB0aGUgYmFjayBvcGVyYXRpb24gdG8gcG9wIGFsbApAQCAtNDYs
MTQgKzYzLDEzIEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgLy8gaW4gb3JkZXIgdG8g
aW1wcm92ZSBjb250cmFzdCBiZXR3ZWVuIEdGRSdzIHBsYWNlaG9sZGVyIGJveCBhcnQKICAgICAg
ICAgLy8gYW5kIHRoZSBiYWNrZ3JvdW5kIG9mIHRoZSBhcHAgZ3JpZC4KICAgICAgICAgaWYgKFN5
c3RlbVByb3BlcnRpZXMudXNlc01hdGVyaWFsM1RoZW1lKSB7Ci0gICAgICAgICAgICBNYXRlcmlh
bC5iYWNrZ3JvdW5kID0gVGhlbWUuYmFja2dyb3VuZAorICAgICAgICAgICAgLy8gVGhlbWUgcmVt
YWlucyBhIGxpdmUgYmluZGluZyB0byB0aGUgc2hhcmVkIHBhbGV0dGUuCiAgICAgICAgIH0KIAog
ICAgICAgICAvLyBCcmlkZ2UgdGhlIE1hdGVyaWFsIHN0eWxlIHRvIHRoZSBWaWJlbWlzIGRlc2ln
biB0b2tlbnMgc28gdGhlCiAgICAgICAgIC8vIE1hdGVyaWFsLXN0eWxlZCBwYWdlcyAoQ29tcHV0
ZXJzIGdyaWQsIEFwcCBncmlkLCBkaWFsb2dzKSBzaGFyZSB0aGUgc2FtZQogICAgICAgICAvLyBh
Y2NlbnQvYmFja2dyb3VuZCBzeXN0ZW0gYXMgdGhlIHRva2VuLW5hdGl2ZSBwYWdlcy4gU2VlIGRv
Y3MvREVTSUdOX1NZU1RFTS5tZC4KLSAgICAgICAgTWF0ZXJpYWwudGhlbWUgPSBNYXRlcmlhbC5E
YXJrCi0gICAgICAgIE1hdGVyaWFsLmFjY2VudCA9IFRoZW1lLmFjY2VudAorICAgICAgICAvLyBN
YXRlcmlhbCB0aGVtZS9hY2NlbnQgYXJlIGJvdW5kIGF0IHRoZSByb290LCBpbmNsdWRpbmcgYWZ0
ZXIgY2hhbmdlcy4KIAogICAgICAgICBTZGxHYW1lcGFkS2V5TmF2aWdhdGlvbi5lbmFibGUoKQog
ICAgIH0KQEAgLTI2Nyw2ICsyODMsMjUgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICB9
CiAgICAgfQogCisgICAgQ3JpbXNvblN0YXR1c0RpYWxvZyB7IGlkOiBjcmltc29uUGFuZWwgfQor
ICAgIFN5c3RlbUNvbm5lY3Rpb25zRGlhbG9nIHsgaWQ6IGNvbm5lY3Rpb25QYW5lbCB9CisgICAg
RWNsaXBzZUFib3V0RGlhbG9nIHsgaWQ6IGVjbGlwc2VBYm91dCB9CisgICAgRWNsaXBzZUNvbnRy
b2xDZW50ZXIgeworICAgICAgICBpZDogZWNsaXBzZUNlbnRlcgorICAgICAgICBjYW5NYW5hZ2U6
IFN5c3RlbVByb3BlcnRpZXMuaGFzQnJvd3NlcgorICAgICAgICBjYW5XYWtlOiB0b29sQmFyLm9u
UGNWaWV3CisgICAgICAgIG9uV2FrZVJlcXVlc3RlZDogeworICAgICAgICAgICAgaWYgKHRvb2xC
YXIub25QY1ZpZXcpIHN0YWNrVmlldy5jdXJyZW50SXRlbS5jb21wdXRlck1vZGVsLndha2VDb21w
dXRlcihzdGFja1ZpZXcuY3VycmVudEl0ZW0uY3VycmVudEluZGV4KQorICAgICAgICB9CisgICAg
ICAgIG9uTmF2aWdhdGVSZXF1ZXN0ZWQ6IHsKKyAgICAgICAgICAgIGlmIChkZXN0aW5hdGlvbiA9
PT0gIndpZmkiIHx8IGRlc3RpbmF0aW9uID09PSAiYnQiKSB7IGNvbm5lY3Rpb25QYW5lbC5raW5k
ID0gZGVzdGluYXRpb247IGNvbm5lY3Rpb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgZWxz
ZSBpZiAoZGVzdGluYXRpb24gPT09ICJzZXR0aW5ncyIpIG5hdmlnYXRlVG8oInFyYzovZ3VpL1Nl
dHRpbmdzVmlldy5xbWwiLCAiU2V0dGluZ3NWaWV3IikKKyAgICAgICAgICAgIGVsc2UgaWYgKGRl
c3RpbmF0aW9uID09PSAiaG9zdCIpIHsgQ3JpbXNvblN0YXR1cy5zZWxlY3RIb3N0KGVjbGlwc2VD
ZW50ZXIuaG9zdC5pZCB8fCAiIiwgZWNsaXBzZUNlbnRlci5ob3N0LnVybCB8fCAiIik7IGNyaW1z
b25QYW5lbC5raW5kID0gImhvc3QiOyBjcmltc29uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAg
IGVsc2UgaWYgKGRlc3RpbmF0aW9uID09PSAiYWJvdXQiKSB7IGVjbGlwc2VBYm91dC5pbmZvID0g
U3lzdGVtQ29udHJvbHMuc3RhdGU7IGVjbGlwc2VBYm91dC5vcGVuKCkgfQorICAgICAgICAgICAg
ZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJtYW5hZ2VtZW50IiAmJiBTeXN0ZW1Qcm9wZXJ0aWVz
Lmhhc0Jyb3dzZXIpIFN5c3RlbVByb3BlcnRpZXMub3BlblVybChlY2xpcHNlQ2VudGVyLmhvc3Qu
dXJsKQorICAgICAgICB9CisgICAgfQorCiAgICAgaGVhZGVyOiBUb29sQmFyIHsKICAgICAgICAg
aWQ6IHRvb2xCYXIKICAgICAgICAgLy8gUmVkZXNpZ246IEVWRVJZIHJlZGVzaWduZWQgbGF1bmNo
ZXIgc2NyZWVuIChDb21wdXRlcnMsIEFwcCBncmlkLCBTZXR0aW5ncywgSGVscCkKQEAgLTMzOCwy
MCArMzczLDE5IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgLy8gVklCRU1JUyB3b3Jk
bWFyayAoZGlhbW9uZCArIHdvcmRtYXJrKSwgc2hvd24gb24gdGhlIENvbXB1dGVycyBzY3JlZW4g
aW4gcGxhY2Ugb2YgYSB0aXRsZSwKICAgICAgICAgLy8gbWF0Y2hpbmcgdGhlIGRlc2lnbiBoZWFk
ZXIuIExlZnQtYWxpZ25lZCBhdCB0aGUgSFRNTCdzIDQwcHggcGFkZGluZy4KICAgICAgICAgUm93
IHsKLSAgICAgICAgICAgIHZpc2libGU6IHRvb2xCYXIub25QY1ZpZXcKKyAgICAgICAgICAgIHZp
c2libGU6IHRvb2xCYXIub25QY1ZpZXcgJiYgdG9vbEJhci53aWR0aCA+IDgyMAogICAgICAgICAg
ICAgYW5jaG9ycy5sZWZ0OiBwYXJlbnQubGVmdAogICAgICAgICAgICAgYW5jaG9ycy5sZWZ0TWFy
Z2luOiA0MAogICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRp
Y2FsQ2VudGVyCiAgICAgICAgICAgICBzcGFjaW5nOiAxMQotICAgICAgICAgICAgUmVjdGFuZ2xl
IHsKKyAgICAgICAgICAgIEltYWdlIHsKICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2Fs
Q2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIKLSAgICAgICAgICAgICAgICB3aWR0aDogMTM7
IGhlaWdodDogMTMKLSAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYWNjZW50Ci0gICAg
ICAgICAgICAgICAgcm90YXRpb246IDQ1CisgICAgICAgICAgICAgICAgd2lkdGg6IDI4OyBoZWln
aHQ6IDI4CisgICAgICAgICAgICAgICAgc291cmNlOiAicXJjOi9yZXMvZWNsaXBzZS1pY29uLnN2
ZyIKICAgICAgICAgICAgIH0KICAgICAgICAgICAgIFRleHQgewogICAgICAgICAgICAgICAgIGFu
Y2hvcnMudmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlcgotICAgICAgICAgICAg
ICAgIHRleHQ6ICJWSUJFTUlTIgorICAgICAgICAgICAgICAgIHRleHQ6ICJFQ0xJUFNFIgogICAg
ICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250RGlzcGxheQogICAgICAgICAg
ICAgICAgIGZvbnQud2VpZ2h0OiBGb250LkV4dHJhQm9sZAogICAgICAgICAgICAgICAgIGZvbnQu
cGl4ZWxTaXplOiAyMQpAQCAtMzY1LDcgKzM5OSw3IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAg
ICAgICAgICAgIC8vIEhpZGRlbiBvbiBDb21wdXRlcnMgKHRoZSB3b3JkbWFyayBzdGFuZHMgaW4p
IGFuZCBvbiB0aGUgQXBwIGdyaWQgKHdoaWNoIHNob3dzIGEKICAgICAgICAgICAgIC8vIGxlZnQt
YWxpZ25lZCBob3N0ICsgc3RhdHVzIGJsb2NrIGluc3RlYWQpLiBPbiBTZXR0aW5ncy9IZWxwIGl0
IHNob3dzIHRoZSBzY3JlZW4gbmFtZTsKICAgICAgICAgICAgIC8vIHRoZSBzdHJlYW1pbmcgc2Vn
dWVzIGtlZXAgdGhlaXIgZGVmYXVsdCBvYmplY3ROYW1lIHRpdGxlLgotICAgICAgICAgICAgdmlz
aWJsZTogIXRvb2xCYXIub25QY1ZpZXcgJiYgIXRvb2xCYXIub25BcHBWaWV3ICYmIHRvb2xCYXIu
d2lkdGggPiA3MDAKKyAgICAgICAgICAgIHZpc2libGU6ICF0b29sQmFyLm9uUGNWaWV3ICYmICF0
b29sQmFyLm9uQXBwVmlldyAmJiB0b29sQmFyLndpZHRoID4gODIwCiAgICAgICAgICAgICBhbmNo
b3JzLmZpbGw6IHBhcmVudAogICAgICAgICAgICAgdGV4dDogdG9vbEJhci5vblNldHRpbmdzID8g
cXNUcigiU2V0dGluZ3MiKQogICAgICAgICAgICAgICAgIDogdG9vbEJhci5vbkhlbHAgPyBxc1Ry
KCJIZWxwIikKQEAgLTQ4Nyw2ICs1MjEsNTQgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAg
ICAgICAgICAgIH0KICAgICAgICAgICAgIH0KIAorICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1
dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IG5ldHdvcmtTdGF0dXNCdXR0b24KKyAgICAgICAg
ICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZyIKKyAgICAg
ICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIldpLUZpIHNldHRpbmdzIikKKyAgICAg
ICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBUb29s
VGlwLnRleHQ6IHFzVHIoIk5ldHdvcms6ICUxIikuYXJnKENyaW1zb25TdGF0dXMubG9jYWwubmV0
d29yayB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDog
eyBjb25uZWN0aW9uUGFuZWwua2luZCA9ICJ3aWZpIjsgY29ubmVjdGlvblBhbmVsLm9wZW4oKSB9
CisgICAgICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1ZpZXcuY3VycmVudEl0
ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAgICAgICBSZWN0YW5n
bGUgeworICAgICAgICAgICAgICAgICAgICBhbmNob3JzLnJpZ2h0OiBwYXJlbnQucmlnaHQ7IGFu
Y2hvcnMuYm90dG9tOiBwYXJlbnQuYm90dG9tOyBhbmNob3JzLm1hcmdpbnM6IDUKKyAgICAgICAg
ICAgICAgICAgICAgd2lkdGg6IDg7IGhlaWdodDogODsgcmFkaXVzOiA0CisgICAgICAgICAgICAg
ICAgICAgIGNvbG9yOiBDcmltc29uU3RhdHVzLmxvY2FsLmNvbm5lY3RlZCA/IFZiVG9rZW5zLnN0
YXR1c09ubGluZSA6IFZiVG9rZW5zLnN0YXR1c09mZmxpbmUKKyAgICAgICAgICAgICAgICB9Cisg
ICAgICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAg
ICAgICAgICBpZDogYmx1ZXRvb3RoU2V0dGluZ3NCdXR0b24KKyAgICAgICAgICAgICAgICBpY29u
U291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnIgorICAgICAgICAgICAgICAg
IEFjY2Vzc2libGUubmFtZTogcXNUcigiQmx1ZXRvb3RoIHNldHRpbmdzIikKKyAgICAgICAgICAg
ICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBUb29sVGlwLnRl
eHQ6IHFzVHIoIlBhaXIgY29udHJvbGxlcnMgYW5kIGhlYWRwaG9uZXMiKQorICAgICAgICAgICAg
ICAgIG9uQ2xpY2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9ICJidCI7IGNvbm5lY3Rpb25Q
YW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tW
aWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAg
ICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAgICAgICBp
ZDogYmF0dGVyeVN0YXR1c0J1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJxcmM6
L3Jlcy9jcmltc29uLWJhdHRlcnkuc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFt
ZTogcXNUcigiQmF0dGVyeSBzdGF0dXMiKQorICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJs
ZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogQ3JpbXNvblN0YXR1cy5s
b2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAwID8gcXNUcigiQmF0dGVyeTogJTElIOKAoiAlMiIpLmFy
ZyhDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50KS5hcmcoQ3JpbXNvblN0YXR1cy5s
b2NhbC5iYXR0ZXJ5U3RhdGUpIDogcXNUcigiQmF0dGVyeSB1bmF2YWlsYWJsZSIpCisgICAgICAg
ICAgICAgICAgb25DbGlja2VkOiB7IGNyaW1zb25QYW5lbC5raW5kID0gImJhdHRlcnkiOyBjcmlt
c29uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAgICAgICBLZXlzLm9uRG93blByZXNzZWQ6IHN0
YWNrVmlldy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgICAg
ICAgICAgfQorICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAg
ICAgaWQ6IGhvc3RIYXJkd2FyZUJ1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6ICJx
cmM6L3Jlcy9jcmltc29uLWhvc3Quc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFt
ZTogcXNUcigiVmliZXBvbGxvIGhvc3QgaGFyZHdhcmUgc3RhdHMiKQorICAgICAgICAgICAgICAg
IFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDog
cXNUcigiSG9zdCBDUFUsIFJBTSwgR1BVIGFuZCB0ZW1wZXJhdHVyZXMiKQorICAgICAgICAgICAg
ICAgIG9uQ2xpY2tlZDogeworICAgICAgICAgICAgICAgICAgICB2YXIgaXRlbSA9IHN0YWNrVmll
dy5jdXJyZW50SXRlbQorICAgICAgICAgICAgICAgICAgICB2YXIgaG9zdCA9IHRvb2xCYXIub25B
cHBWaWV3ID8gaXRlbS5jcmltc29uSG9zdAorICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6
ICh0b29sQmFyLm9uUGNWaWV3ID8gaXRlbS5jb21wdXRlck1vZGVsLmNyaW1zb25Ib3N0KGl0ZW0u
Y3VycmVudEluZGV4KSA6IHt9KQorICAgICAgICAgICAgICAgICAgICBDcmltc29uU3RhdHVzLnNl
bGVjdEhvc3QoaG9zdC5pZCB8fCAiIiwgaG9zdC51cmwgfHwgIiIpCisgICAgICAgICAgICAgICAg
ICAgIGNyaW1zb25QYW5lbC5raW5kID0gImhvc3QiOyBjcmltc29uUGFuZWwub3BlbigpCisgICAg
ICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDogc3RhY2tW
aWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAgICAgICAg
ICB9CisKICAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24gewogICAgICAgICAgICAgICAg
IGlkOiBkaXNjb3JkQnV0dG9uCiAgICAgICAgICAgICAgICAgdmlzaWJsZTogZmFsc2UgLy8gVGVt
cG9yYXJpbHkgZGlzYWJsZWQgZm9yIFZpYmVtaXMKQEAgLTU2NCw3ICs2NDYsNyBAQCBBcHBsaWNh
dGlvbldpbmRvdyB7CiAgICAgICAgICAgICAgICAgLy8gYW4gaW5zdGFsbCBmYWlsdXJlIGZhbGxz
IGJhY2sgdG8gdGhlIHJlbGVhc2UgcGFnZSBvbiBpdHMgb3duLgogICAgICAgICAgICAgICAgIFRv
b2xUaXAudGV4dDogQXV0b1VwZGF0ZUNoZWNrZXIuaW5zdGFsbGluZwogICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgPyBxc1RyKCJEb3dubG9hZGluZyB1cGRhdGXigKYiKQotICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgOiBxc1RyKCJVcGRhdGUgYXZhaWxhYmxlIGZvciBWaWJlbWlz
OiBWZXJzaW9uICUxIOKAlCB0YXAgdG8gaW5zdGFsbCIpLmFyZyhBdXRvVXBkYXRlQ2hlY2tlci5h
dmFpbGFibGVWZXJzaW9uKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBxc1RyKCJV
cGRhdGUgYXZhaWxhYmxlIGZvciBFY2xpcHNlOiBWZXJzaW9uICUxIOKAlCB0YXAgdG8gaW5zdGFs
bCIpLmFyZyhBdXRvVXBkYXRlQ2hlY2tlci5hdmFpbGFibGVWZXJzaW9uKQogCiAgICAgICAgICAg
ICAgICAgLy8gU3RyaWN0bHktbmV3ZXIgYnVpbGRzIG9ubHkgKGEgY2hhbm5lbC1zd2l0Y2ggZG93
bmdyYWRlIG9mZmVyCiAgICAgICAgICAgICAgICAgLy8gbGl2ZXMgaW4gU2V0dGluZ3MsIG5vdCBv
biB0aGUgdG9vbGJhcikuCkBAIC02NDYsNiArNzI4LDIxIEBAIEFwcGxpY2F0aW9uV2luZG93IHsK
ICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAKKyAgICAgICAgICAgIE5hdmlnYWJs
ZVRvb2xCdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBlY2xpcHNlQ2VudGVyQnV0dG9uCisg
ICAgICAgICAgICAgICAgaWNvblNvdXJjZTogInFyYzovcmVzL2VjbGlwc2UtY29udHJvbHMuc3Zn
IgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiRWNsaXBzZSBjb250cm9s
IGNlbnRlciIpCisgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCisgICAg
ICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJDb250cm9sIGNlbnRlciDigKIgQ3RybCtT
aGlmdCtDIikKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsKKyAgICAgICAgICAgICAgICAg
ICAgdmFyIGl0ZW0gPSBzdGFja1ZpZXcuY3VycmVudEl0ZW0KKyAgICAgICAgICAgICAgICAgICAg
ZWNsaXBzZUNlbnRlci5ob3N0ID0gdG9vbEJhci5vbkFwcFZpZXcgPyBpdGVtLmNyaW1zb25Ib3N0
IDogKHRvb2xCYXIub25QY1ZpZXcgPyBpdGVtLmNvbXB1dGVyTW9kZWwuY3JpbXNvbkhvc3QoaXRl
bS5jdXJyZW50SW5kZXgpIDoge30pCisgICAgICAgICAgICAgICAgICAgIGVjbGlwc2VDZW50ZXIu
b3BlbigpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJl
c3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMp
CisgICAgICAgICAgICAgICAgU2hvcnRjdXQgeyBzZXF1ZW5jZTogIkN0cmwrU2hpZnQrQyI7IGVu
YWJsZWQ6IHRvb2xCYXIub25QY1ZpZXcgfHwgdG9vbEJhci5vbkFwcFZpZXc7IG9uQWN0aXZhdGVk
OiBlY2xpcHNlQ2VudGVyQnV0dG9uLmNsaWNrZWQoKSB9CisgICAgICAgICAgICB9CisKICAgICAg
ICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24gewogICAgICAgICAgICAgICAgIGlkOiBzZXR0aW5n
c0J1dHRvbgogCkBAIC02NzMsNyArNzcwLDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogCiAgICAg
RXJyb3JNZXNzYWdlRGlhbG9nIHsKICAgICAgICAgaWQ6IG5vSHdEZWNvZGVyRGlhbG9nCi0gICAg
ICAgIHRleHQ6IHFzVHIoIk5vIGZ1bmN0aW9uaW5nIGhhcmR3YXJlIGFjY2VsZXJhdGVkIHZpZGVv
IGRlY29kZXIgd2FzIGRldGVjdGVkIGJ5IFZpYmVtaXMuICIgKworICAgICAgICB0ZXh0OiBxc1Ry
KCJObyBmdW5jdGlvbmluZyBoYXJkd2FyZSBhY2NlbGVyYXRlZCB2aWRlbyBkZWNvZGVyIHdhcyBk
ZXRlY3RlZCBieSBFY2xpcHNlLiAiICsKICAgICAgICAgICAgICAgICAgICAiWW91ciBzdHJlYW1p
bmcgcGVyZm9ybWFuY2UgbWF5IGJlIHNldmVyZWx5IGRlZ3JhZGVkIGluIHRoaXMgY29uZmlndXJh
dGlvbi4iKQogICAgICAgICBoZWxwVGV4dDogcXNUcigiQ2xpY2sgdGhlIEhlbHAgYnV0dG9uIGZv
ciBtb3JlIGluZm9ybWF0aW9uIG9uIHNvbHZpbmcgdGhpcyBwcm9ibGVtLiIpCiAgICAgICAgIGhl
bHBVcmw6ICJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3ZpYmVtaXMiCkBAIC02OTAsNyAr
Nzg3LDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgIE5hdmlnYWJsZU1lc3NhZ2VEaWFsb2cg
ewogICAgICAgICBpZDogd293NjREaWFsb2cKICAgICAgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFs
b2cuT2sgfCBEaWFsb2cuQ2FuY2VsCi0gICAgICAgIHRleHQ6IHFzVHIoIlRoaXMgdmVyc2lvbiBv
ZiBWaWJlbWlzIGlzbid0IG9wdGltaXplZCBmb3IgeW91ciBQQy4gUGxlYXNlIGRvd25sb2FkIHRo
ZSAnJTEnIHZlcnNpb24gb2YgVmliZW1pcyBmb3IgdGhlIGJlc3Qgc3RyZWFtaW5nIHBlcmZvcm1h
bmNlLiIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLmZyaWVuZGx5TmF0aXZlQXJjaE5hbWUpCisgICAg
ICAgIHRleHQ6IHFzVHIoIlRoaXMgdmVyc2lvbiBvZiBFY2xpcHNlIGlzbid0IG9wdGltaXplZCBm
b3IgeW91ciBQQy4gUGxlYXNlIGRvd25sb2FkIHRoZSAnJTEnIHZlcnNpb24gb2YgRWNsaXBzZSBm
b3IgdGhlIGJlc3Qgc3RyZWFtaW5nIHBlcmZvcm1hbmNlLiIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVz
LmZyaWVuZGx5TmF0aXZlQXJjaE5hbWUpCiAgICAgICAgIG9uQWNjZXB0ZWQ6IHsKICAgICAgICAg
ICAgIFN5c3RlbVByb3BlcnRpZXMub3BlblVybCgiaHR0cHM6Ly9naXRodWIuY29tL25hdnlhczMy
MS92aWJlbWlzL3JlbGVhc2VzIik7CiAgICAgICAgIH0KQEAgLTY5OSw3ICs3OTYsNyBAQCBBcHBs
aWNhdGlvbldpbmRvdyB7CiAgICAgRXJyb3JNZXNzYWdlRGlhbG9nIHsKICAgICAgICAgaWQ6IHVu
bWFwcGVkR2FtZXBhZERpYWxvZwogICAgICAgICBwcm9wZXJ0eSBzdHJpbmcgdW5tYXBwZWRHYW1l
cGFkcyA6ICIiCi0gICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMgZGV0ZWN0ZWQgZ2FtZXBhZHMg
d2l0aG91dCBhIG1hcHBpbmc6IikgKyAiXG4iICsgdW5tYXBwZWRHYW1lcGFkcworICAgICAgICB0
ZXh0OiBxc1RyKCJFY2xpcHNlIGRldGVjdGVkIGdhbWVwYWRzIHdpdGhvdXQgYSBtYXBwaW5nOiIp
ICsgIlxuIiArIHVubWFwcGVkR2FtZXBhZHMKICAgICAgICAgaGVscFRleHRTZXBhcmF0b3I6ICJc
blxuIgogICAgICAgICBoZWxwVGV4dDogcXNUcigiQ2xpY2sgdGhlIEhlbHAgYnV0dG9uIGZvciBp
bmZvcm1hdGlvbiBvbiBob3cgdG8gbWFwIHlvdXIgZ2FtZXBhZHMuIikKICAgICAgICAgaGVscFVy
bDogImh0dHBzOi8vZ2l0aHViLmNvbS9uYXZ5YXMzMjEvdmliZW1pcyIKZGlmZiAtLWdpdCBhL2Fw
cC9tYWluLmNwcCBiL2FwcC9tYWluLmNwcAppbmRleCAyOTIyMjc3Ny4uM2VjOTRkYmYgMTAwNjQ0
Ci0tLSBhL2FwcC9tYWluLmNwcAorKysgYi9hcHAvbWFpbi5jcHAKQEAgLTg2OSw2ICs4NjksNyBA
QCBpbnQgbWFpbihpbnQgYXJnYywgY2hhciAqYXJndltdKQogICAgIH0NCiANCiAgICAgUUd1aUFw
cGxpY2F0aW9uIGFwcChhcmdjLCBhcmd2KTsNCisgICAgUUd1aUFwcGxpY2F0aW9uOjpzZXRBcHBs
aWNhdGlvbkRpc3BsYXlOYW1lKCJFY2xpcHNlIik7CiANCiAgICAgLy8gVmliZW1pczogdGhlIFF0
IFF1aWNrIENvbnRyb2xzIE1hdGVyaWFsIHN0eWxlIHJlbmRlcnMgYnV0dG9uIHRleHQgaW4gQUxM
IENBUFMgYnkgZGVmYXVsdA0KICAgICAvLyAoZS5nLiB0aGUgYml0cmF0ZSAiVVNFIERFRkFVTFQg
KDMwIE1CUFMpIiBidXR0b24pLCB3aGljaCBsb29rcyBvZmYuIEZvcmNlIG1peGVkIGNhc2UgZm9y
IHRoZQ0KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcCBiL2Fw
cC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwMC4uZGFmY2EyZWUKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3Mv
Y3JpbXNvbnN0YXR1cy5jcHAKQEAgLTAsMCArMSwyMjIgQEAKKyNpbmNsdWRlICJjcmltc29uc3Rh
dHVzLmgiCisjaW5jbHVkZSA8UURhdGVUaW1lPgorI2luY2x1ZGUgPFFEaXI+CisjaW5jbHVkZSA8
UUZpbGU+CisjaW5jbHVkZSA8UUpzb25Eb2N1bWVudD4KKyNpbmNsdWRlIDxRSnNvbk9iamVjdD4K
KyNpbmNsdWRlIDxRTmV0d29ya0ludGVyZmFjZT4KKyNpbmNsdWRlIDxRTmV0d29ya1JlcXVlc3Q+
CisjaW5jbHVkZSA8UVNhdmVGaWxlPgorI2luY2x1ZGUgPFFTc2xDZXJ0aWZpY2F0ZT4KKyNpbmNs
dWRlIDxRU3NsRXJyb3I+CisjaW5jbHVkZSA8UVN0YW5kYXJkUGF0aHM+CisjaW5jbHVkZSA8UUNy
eXB0b2dyYXBoaWNIYXNoPgorI2luY2x1ZGUgPFFVcmw+CisjaW5jbHVkZSA8Y21hdGg+CisjaW5j
bHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUg
PG1lbW9yeT4KKyNpbmNsdWRlIDxRUmVndWxhckV4cHJlc3Npb24+CisjaW5jbHVkZSA8UUZpbGVJ
bmZvPgorI2luY2x1ZGUgPFFTc2xDb25maWd1cmF0aW9uPgorCituYW1lc3BhY2UgeworUVN0cmlu
ZyByZWFkKGNvbnN0IFFTdHJpbmcmIHBhdGgpIHsKKyAgICBRRmlsZSBmKHBhdGgpOyByZXR1cm4g
Zi5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkpID8gUVN0cmluZzo6ZnJvbVV0ZjgoZi5yZWFkQWxs
KCkpLnRyaW1tZWQoKSA6IFFTdHJpbmcoKTsKK30KK2NvbnN0IGF1dG8gdXNlck9ubHkgPSBRRmls
ZURldmljZTo6UmVhZE93bmVyIHwgUUZpbGVEZXZpY2U6OldyaXRlT3duZXI7Cit9CitDcmltc29u
U3RhdHVzOjpDcmltc29uU3RhdHVzKFFPYmplY3QqIHBhcmVudCkgOiBRT2JqZWN0KHBhcmVudCkg
eworICAgIGNvbm5lY3QoJm1fbG9jYWxUaW1lciwgJlFUaW1lcjo6dGltZW91dCwgdGhpcywgJkNy
aW1zb25TdGF0dXM6OnJlZnJlc2hMb2NhbCk7CisgICAgY29ubmVjdCgmbV9zdGF0c1RpbWVyLCAm
UVRpbWVyOjp0aW1lb3V0LCB0aGlzLCAmQ3JpbXNvblN0YXR1czo6cmVmcmVzaCk7CisgICAgY29u
bmVjdCgmbV93aWZpLCAmUVByb2Nlc3M6OmZpbmlzaGVkLCB0aGlzLCBbdGhpc10oaW50IGV4aXQs
IFFQcm9jZXNzOjpFeGl0U3RhdHVzKSB7CisgICAgICAgIGlmIChleGl0ID09IDApIHsKKyAgICAg
ICAgICAgIGNvbnN0IGF1dG8gbGluZXMgPSBRU3RyaW5nOjpmcm9tVXRmOChtX3dpZmkucmVhZEFs
bFN0YW5kYXJkT3V0cHV0KCkpLnNwbGl0KCdcbicpOworICAgICAgICAgICAgZm9yIChjb25zdCBh
dXRvJiBsaW5lIDogbGluZXMpIHsKKyAgICAgICAgICAgICAgICBpZiAoIWxpbmUuc3RhcnRzV2l0
aCgieWVzOiIpKSBjb250aW51ZTsKKyAgICAgICAgICAgICAgICBpbnQgc2VwYXJhdG9yID0gbGlu
ZS5pbmRleE9mKCc6JywgNCk7IGJvb2wgb2sgPSBmYWxzZTsKKyAgICAgICAgICAgICAgICBpbnQg
c2lnbmFsID0gbGluZS5taWQoNCwgc2VwYXJhdG9yIC0gNCkudG9JbnQoJm9rKTsKKyAgICAgICAg
ICAgICAgICBpZiAob2sgJiYgc2lnbmFsID49IDAgJiYgc2lnbmFsIDw9IDEwMCkgbV9sb2NhbFsi
d2lmaVNpZ25hbCJdID0gc2lnbmFsOworICAgICAgICAgICAgICAgIGlmIChzZXBhcmF0b3IgPj0g
MCkgbV9sb2NhbFsibmV0d29yayJdID0gdHIoIldpLUZpOiAlMSIpLmFyZyhsaW5lLm1pZChzZXBh
cmF0b3IgKyAxKSk7CisgICAgICAgICAgICAgICAgYnJlYWs7CisgICAgICAgICAgICB9CisgICAg
ICAgICAgICBlbWl0IGxvY2FsQ2hhbmdlZCgpOworICAgICAgICB9CisgICAgfSk7CisgICAgbV9s
b2NhbFRpbWVyLnN0YXJ0KDEwMDAwKTsgbV9zdGF0c1RpbWVyLnNldEludGVydmFsKDIwMDApOyBy
ZWZyZXNoTG9jYWwoKTsKK30KK0NyaW1zb25TdGF0dXM6On5Dcmltc29uU3RhdHVzKCkgeworICAg
IG1fc3RhdHNUaW1lci5zdG9wKCk7IG1fbG9jYWxUaW1lci5zdG9wKCk7IGNhbmNlbCgpOworICAg
IGlmIChtX3dpZmkuc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgeyBtX3dpZmkua2ls
bCgpOyBtX3dpZmkud2FpdEZvckZpbmlzaGVkKDUwMCk7IH0KK30KK1FTdHJpbmcgQ3JpbXNvblN0
YXR1czo6Y29uZmlnRmlsZSgpIGNvbnN0IHsKKyAgICByZXR1cm4gUVN0YW5kYXJkUGF0aHM6Ondy
aXRhYmxlTG9jYXRpb24oUVN0YW5kYXJkUGF0aHM6OkFwcENvbmZpZ0xvY2F0aW9uKSArICIvY3Jp
bXNvbi1ob3N0cy5qc29uIjsKK30KK1FTdHJpbmcgQ3JpbXNvblN0YXR1czo6bm9ybWFsaXplZFBp
bihRU3RyaW5nIHBpbikgeworICAgIHBpbi5yZW1vdmUoJzonKTsgcGluLnJlbW92ZSgnICcpOyBy
ZXR1cm4gcGluLnRvTG93ZXIoKTsKK30KK2Jvb2wgQ3JpbXNvblN0YXR1czo6dmFsaWRFbmRwb2lu
dChjb25zdCBRU3RyaW5nJiB2YWx1ZSkgeworICAgIFFVcmwgdSh2YWx1ZSwgUVVybDo6U3RyaWN0
TW9kZSk7CisgICAgcmV0dXJuIHUuaXNWYWxpZCgpICYmIHUuc2NoZW1lKCkgPT0gImh0dHBzIiAm
JiAhdS5ob3N0KCkuaXNFbXB0eSgpICYmCisgICAgICAgIHUudXNlckluZm8oKS5pc0VtcHR5KCkg
JiYgdS5xdWVyeSgpLmlzRW1wdHkoKSAmJiB1LmZyYWdtZW50KCkuaXNFbXB0eSgpICYmCisgICAg
ICAgICh1LnBhdGgoKS5pc0VtcHR5KCkgfHwgdS5wYXRoKCkgPT0gIi8iKSAmJiB1LnBvcnQoNDc5
OTApID4gMDsKK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6Y2FuY2VsKCkgeworICAgIGlmIChtX3Jl
cGx5KSB7IGRpc2Nvbm5lY3QobV9yZXBseSwgbnVsbHB0ciwgdGhpcywgbnVsbHB0cik7IG1fcmVw
bHktPmFib3J0KCk7IG1fcmVwbHktPmRlbGV0ZUxhdGVyKCk7IG1fcmVwbHkgPSBudWxscHRyOyB9
Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OnNlbGVjdEhvc3QoUVN0cmluZyBpZCwgUVN0cmluZyBz
dWdnZXN0ZWRVcmwpIHsKKyAgICBpZiAoaWQgPT0gbV9ob3N0KSByZXR1cm47CisgICAgY2FuY2Vs
KCk7IG1fbmV0d29yay5jbGVhckNvbm5lY3Rpb25DYWNoZSgpOyBtX2hvc3QgPSBpZDsgbV90b2tl
bi5jbGVhcigpOyBtX3Bpbi5jbGVhcigpOworICAgIG1fZW5kcG9pbnQgPSB2YWxpZEVuZHBvaW50
KHN1Z2dlc3RlZFVybCkgPyBzdWdnZXN0ZWRVcmwgOiBRU3RyaW5nKCk7CisgICAgUUZpbGUgZihj
b25maWdGaWxlKCkpOworICAgIGlmIChmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkpIHsKKyAg
ICAgICAgYXV0byBjID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24oZi5yZWFkQWxsKCkpLm9iamVj
dCgpLnZhbHVlKGlkKS50b09iamVjdCgpOworICAgICAgICBpZiAodmFsaWRFbmRwb2ludChjLnZh
bHVlKCJ1cmwiKS50b1N0cmluZygpKSkgeworICAgICAgICAgICAgbV9lbmRwb2ludCA9IGMudmFs
dWUoInVybCIpLnRvU3RyaW5nKCk7IG1fdG9rZW4gPSBjLnZhbHVlKCJ0b2tlbiIpLnRvU3RyaW5n
KCk7IG1fcGluID0gYy52YWx1ZSgicGluIikudG9TdHJpbmcoKTsKKyAgICAgICAgfQorICAgIH0K
KyAgICBtX3N0YXRzLmNsZWFyKCk7IG1fc3RhdHVzID0gaWQuaXNFbXB0eSgpID8gdHIoIkNob29z
ZSBhIGhvc3QgdG8gdmlldyBoYXJkd2FyZSBzdGF0cyIpIDogdHIoIkNvbmZpZ3VyZSBhIFZpYmVw
b2xsbyByZWFkLW9ubHkgc3RhdHMgdG9rZW4iKTsKKyAgICBlbWl0IGNvbmZpZ0NoYW5nZWQoKTsg
ZW1pdCBzdGF0c0NoYW5nZWQoKTsgaWYgKG1fdmlzaWJsZSkgcmVmcmVzaCgpOworfQorYm9vbCBD
cmltc29uU3RhdHVzOjpjb25maWd1cmUoUVN0cmluZyB1cmwsIFFTdHJpbmcgdG9rZW4sIFFTdHJp
bmcgcGluKSB7CisgICAgcGluID0gbm9ybWFsaXplZFBpbihwaW4pOworICAgIGlmIChtX2hvc3Qu
aXNFbXB0eSgpIHx8ICF2YWxpZEVuZHBvaW50KHVybCkgfHwgKCFwaW4uaXNFbXB0eSgpICYmCisg
ICAgICAgIChwaW4uc2l6ZSgpICE9IDY0IHx8IHBpbi5jb250YWlucyhRUmVndWxhckV4cHJlc3Np
b24oIlteMC05YS1mXSIpKSkpKSB7CisgICAgICAgIGZhaWwodHIoIlVzZSBhbiBIVFRQUyBob3N0
IFVSTCBhbmQgYW4gb3B0aW9uYWwgNjQtZGlnaXQgU0hBLTI1NiBjZXJ0aWZpY2F0ZSBmaW5nZXJw
cmludCIpKTsgcmV0dXJuIGZhbHNlOworICAgIH0KKyAgICAvLyBBIGJsYW5rIHRva2VuIGtlZXBz
IHRoZSBvbGQgdG9rZW4gb25seSBmb3IgdGhlIHNhbWUgZW5kcG9pbnQuCisgICAgaWYgKHRva2Vu
LmlzRW1wdHkoKSAmJiBRVXJsKHVybCkgPT0gUVVybChtX2VuZHBvaW50KSkgdG9rZW4gPSBtX3Rv
a2VuOworICAgIGlmICh0b2tlbi5pc0VtcHR5KCkgfHwgdG9rZW4uY29udGFpbnMoJ1xyJykgfHwg
dG9rZW4uY29udGFpbnMoJ1xuJykgfHwgdG9rZW4uc2l6ZSgpID4gNDA5NikgeworICAgICAgICBm
YWlsKHRyKCJBIHJlYWQtb25seSBWaWJlcG9sbG8gQVBJIHRva2VuIGlzIHJlcXVpcmVkIikpOyBy
ZXR1cm4gZmFsc2U7CisgICAgfQorICAgIFFGaWxlIGYoY29uZmlnRmlsZSgpKTsgUUpzb25PYmpl
Y3QgYWxsOworICAgIGlmIChmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkpIGFsbCA9IFFKc29u
RG9jdW1lbnQ6OmZyb21Kc29uKGYucmVhZEFsbCgpKS5vYmplY3QoKTsKKyAgICBhbGxbbV9ob3N0
XSA9IFFKc29uT2JqZWN0e3sidXJsIiwgdXJsfSwgeyJ0b2tlbiIsIHRva2VufSwgeyJwaW4iLCBw
aW59fTsKKyAgICBRRGlyKCkubWtwYXRoKFFGaWxlSW5mbyhjb25maWdGaWxlKCkpLmFic29sdXRl
UGF0aCgpKTsKKyAgICBRU2F2ZUZpbGUgb3V0KGNvbmZpZ0ZpbGUoKSk7CisgICAgaWYgKCFvdXQu
b3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkgfHwgIW91dC5zZXRQZXJtaXNzaW9ucyh1c2VyT25s
eSkgfHwKKyAgICAgICAgb3V0LndyaXRlKFFKc29uRG9jdW1lbnQoYWxsKS50b0pzb24oKSkgPCAw
IHx8ICFvdXQuY29tbWl0KCkpIHsKKyAgICAgICAgZmFpbCh0cigiQ291bGQgbm90IHNhdmUgaG9z
dCBhY2Nlc3Mgc2V0dGluZ3MiKSk7IHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgY2FuY2VsKCk7
IG1fbmV0d29yay5jbGVhckNvbm5lY3Rpb25DYWNoZSgpOyBtX2VuZHBvaW50ID0gdXJsOyBtX3Rv
a2VuID0gdG9rZW47IG1fcGluID0gcGluOworICAgIG1fc3RhdHNUaW1lci5zZXRJbnRlcnZhbCgy
MDAwKTsKKyAgICBtX3N0YXRzLmNsZWFyKCk7IG1fc3RhdHVzID0gdHIoIkNvbm5lY3RpbmcgdG8g
aG9zdCBzdGF0c+KApiIpOworICAgIGVtaXQgY29uZmlnQ2hhbmdlZCgpOyBlbWl0IHN0YXRzQ2hh
bmdlZCgpOyByZWZyZXNoKCk7IHJldHVybiB0cnVlOworfQordm9pZCBDcmltc29uU3RhdHVzOjpz
ZXRWaXNpYmxlKGJvb2wgdmlzaWJsZSkgeworICAgIG1fdmlzaWJsZSA9IHZpc2libGU7CisgICAg
aWYgKHZpc2libGUpIHsgcmVmcmVzaExvY2FsKCk7IG1fc3RhdHNUaW1lci5zdGFydCgpOyByZWZy
ZXNoKCk7IH0KKyAgICBlbHNlIHsgbV9zdGF0c1RpbWVyLnN0b3AoKTsgY2FuY2VsKCk7IH0KK30K
K3ZvaWQgQ3JpbXNvblN0YXR1czo6ZmFpbChRU3RyaW5nIG1lc3NhZ2UpIHsKKyAgICBtX3N0YXRz
LmNsZWFyKCk7IG1fc3RhdHVzID0gbWVzc2FnZTsKKyAgICBtX3N0YXRzVGltZXIuc2V0SW50ZXJ2
YWwocU1pbigzMDAwMCwgcU1heCg0MDAwLCBtX3N0YXRzVGltZXIuaW50ZXJ2YWwoKSAqIDIpKSk7
CisgICAgZW1pdCBzdGF0c0NoYW5nZWQoKTsKK30KK1FWYXJpYW50TWFwIENyaW1zb25TdGF0dXM6
OnBhcnNlU3RhdHMoY29uc3QgUUJ5dGVBcnJheSYgYnl0ZXMsIFFTdHJpbmcqIGVycm9yKSB7Cisg
ICAgaWYgKGJ5dGVzLnNpemUoKSA+IDY1NTM2KSB7ICplcnJvciA9ICJPdmVyc2l6ZWQgaG9zdCBz
dGF0cyByZXNwb25zZSI7IHJldHVybiB7fTsgfQorICAgIFFKc29uUGFyc2VFcnJvciBlOyBhdXRv
IGRvYyA9IFFKc29uRG9jdW1lbnQ6OmZyb21Kc29uKGJ5dGVzLCAmZSk7CisgICAgaWYgKGUuZXJy
b3IgIT0gUUpzb25QYXJzZUVycm9yOjpOb0Vycm9yIHx8ICFkb2MuaXNPYmplY3QoKSkgeyAqZXJy
b3IgPSAiSW52YWxpZCBob3N0IHN0YXRzIHJlc3BvbnNlIjsgcmV0dXJuIHt9OyB9CisgICAgYXV0
byBvYmogPSBkb2Mub2JqZWN0KCk7IFFWYXJpYW50TWFwIHJlc3VsdDsKKyAgICBjb25zdCBRU3Ry
aW5nTGlzdCBrZXlzID0geyJjcHVfcGVyY2VudCIsImNwdV90ZW1wX2MiLCJyYW1fdXNlZF9ieXRl
cyIsInJhbV90b3RhbF9ieXRlcyIsInJhbV9wZXJjZW50IiwKKyAgICAgICAgImdwdV9wZXJjZW50
IiwiZ3B1X2VuY29kZXJfcGVyY2VudCIsImdwdV90ZW1wX2MiLCJ2cmFtX3VzZWRfYnl0ZXMiLCJ2
cmFtX3RvdGFsX2J5dGVzIiwidnJhbV9wZXJjZW50IiwibmV0X3J4X2JwcyIsIm5ldF90eF9icHMi
fTsKKyAgICBib29sIHJlY29nbml6ZWQgPSBmYWxzZTsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIGtl
eSA6IGtleXMpIHsKKyAgICAgICAgYXV0byB2ID0gb2JqLnZhbHVlKGtleSk7IHJlY29nbml6ZWQg
fD0gb2JqLmNvbnRhaW5zKGtleSk7CisgICAgICAgIGRvdWJsZSBuID0gdi50b0RvdWJsZSgtMSk7
CisgICAgICAgIGlmICghdi5pc0RvdWJsZSgpIHx8ICFzdGQ6OmlzZmluaXRlKG4pIHx8IG4gPCAw
IHx8IChrZXkuZW5kc1dpdGgoInBlcmNlbnQiKSAmJiBuID4gMTAwKSkgY29udGludWU7CisgICAg
ICAgIHJlc3VsdFtrZXldID0gbjsKKyAgICB9CisgICAgZm9yIChjb25zdCBhdXRvJiBwcmVmaXgg
OiB7UVN0cmluZygicmFtIiksIFFTdHJpbmcoInZyYW0iKX0pIHsKKyAgICAgICAgZG91YmxlIHRv
dGFsID0gcmVzdWx0LnZhbHVlKHByZWZpeCArICJfdG90YWxfYnl0ZXMiKS50b0RvdWJsZSgpOwor
ICAgICAgICBpZiAodG90YWwgPD0gMCkgeyByZXN1bHQucmVtb3ZlKHByZWZpeCArICJfcGVyY2Vu
dCIpOyByZXN1bHQucmVtb3ZlKHByZWZpeCArICJfdXNlZF9ieXRlcyIpOyB9CisgICAgICAgIGVs
c2UgaWYgKHJlc3VsdC5jb250YWlucyhwcmVmaXggKyAiX3VzZWRfYnl0ZXMiKSkgeworICAgICAg
ICAgICAgZG91YmxlIHVzZWQgPSBxTWluKHJlc3VsdC52YWx1ZShwcmVmaXggKyAiX3VzZWRfYnl0
ZXMiKS50b0RvdWJsZSgpLCB0b3RhbCk7CisgICAgICAgICAgICByZXN1bHRbcHJlZml4ICsgIl91
c2VkX2J5dGVzIl0gPSB1c2VkOyByZXN1bHRbcHJlZml4ICsgIl9wZXJjZW50Il0gPSB1c2VkICog
MTAwIC8gdG90YWw7CisgICAgICAgIH0KKyAgICB9CisgICAgaWYgKCFyZWNvZ25pemVkKSB7ICpl
cnJvciA9ICJIb3N0IGRvZXMgbm90IGV4cG9zZSB0aGUgZXhwZWN0ZWQgVmliZXBvbGxvIHN0YXRz
IGZpZWxkcyI7IHJldHVybiB7fTsgfQorICAgIGVycm9yLT5jbGVhcigpOyByZXR1cm4gcmVzdWx0
OworfQordm9pZCBDcmltc29uU3RhdHVzOjpyZWZyZXNoKCkgeworICAgIGlmICghbV92aXNpYmxl
IHx8IG1fcmVwbHkgfHwgIWNvbmZpZ3VyZWQoKSkgcmV0dXJuOworICAgIFFVcmwgdXJsKG1fZW5k
cG9pbnQpOyB1cmwuc2V0UGF0aCgiL2FwaS9ob3N0L3N0YXRzIik7CisgICAgUU5ldHdvcmtSZXF1
ZXN0IHJlcSh1cmwpOworICAgIHJlcS5zZXRBdHRyaWJ1dGUoUU5ldHdvcmtSZXF1ZXN0OjpSZWRp
cmVjdFBvbGljeUF0dHJpYnV0ZSwgUU5ldHdvcmtSZXF1ZXN0OjpNYW51YWxSZWRpcmVjdFBvbGlj
eSk7CisgICAgcmVxLnNldFRyYW5zZmVyVGltZW91dCgzMDAwKTsKKyAgICByZXEuc2V0UmF3SGVh
ZGVyKCJBdXRob3JpemF0aW9uIiwgIkJlYXJlciAiICsgbV90b2tlbi50b1V0ZjgoKSk7CisgICAg
cmVxLnNldFJhd0hlYWRlcigiQWNjZXB0IiwgImFwcGxpY2F0aW9uL2pzb24iKTsKKyAgICBhdXRv
IHJlcGx5ID0gbV9uZXR3b3JrLmdldChyZXEpOyByZXBseS0+c2V0UmVhZEJ1ZmZlclNpemUoNjU1
MzYpOyBtX3JlcGx5ID0gcmVwbHk7CisgICAgYXV0byBkYXRhID0gc3RkOjptYWtlX3NoYXJlZDxR
Qnl0ZUFycmF5PigpOworICAgIGF1dG8gaW52YWxpZFBpbiA9IHN0ZDo6bWFrZV9zaGFyZWQ8Ym9v
bD4oZmFsc2UpOworICAgIGF1dG8gb3ZlcnNpemVkID0gc3RkOjptYWtlX3NoYXJlZDxib29sPihm
YWxzZSk7CisgICAgYXV0byBjZXJ0TWF0Y2hlcyA9IFt0aGlzLCByZXBseV0geworICAgICAgICBy
ZXR1cm4gbm9ybWFsaXplZFBpbihRU3RyaW5nOjpmcm9tTGF0aW4xKHJlcGx5LT5zc2xDb25maWd1
cmF0aW9uKCkucGVlckNlcnRpZmljYXRlKCkuZGlnZXN0KFFDcnlwdG9ncmFwaGljSGFzaDo6U2hh
MjU2KS50b0hleCgpKSkgPT0gbV9waW47CisgICAgfTsKKyAgICBjb25uZWN0KHJlcGx5LCAmUU5l
dHdvcmtSZXBseTo6ZW5jcnlwdGVkLCB0aGlzLCBbdGhpcywgcmVwbHksIGNlcnRNYXRjaGVzLCBp
bnZhbGlkUGluXSB7CisgICAgICAgIGlmICghbV9waW4uaXNFbXB0eSgpICYmICFjZXJ0TWF0Y2hl
cygpKSB7ICppbnZhbGlkUGluID0gdHJ1ZTsgcmVwbHktPmFib3J0KCk7IH0KKyAgICB9KTsKKyAg
ICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtSZXBseTo6c3NsRXJyb3JzLCB0aGlzLCBbdGhpcywg
cmVwbHksIGNlcnRNYXRjaGVzXShjb25zdCBRTGlzdDxRU3NsRXJyb3I+JiBlcnJvcnMpIHsKKyAg
ICAgICAgaWYgKG1fcGluLmlzRW1wdHkoKSB8fCAhY2VydE1hdGNoZXMoKSkgcmV0dXJuOworICAg
ICAgICBmb3IgKGNvbnN0IGF1dG8mIGUgOiBlcnJvcnMpIHsKKyAgICAgICAgICAgIGlmIChlLmVy
cm9yKCkgIT0gUVNzbEVycm9yOjpTZWxmU2lnbmVkQ2VydGlmaWNhdGUgJiYgZS5lcnJvcigpICE9
IFFTc2xFcnJvcjo6U2VsZlNpZ25lZENlcnRpZmljYXRlSW5DaGFpbiAmJgorICAgICAgICAgICAg
ICAgIGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6OkNlcnRpZmljYXRlVW50cnVzdGVkICYmIGUuZXJy
b3IoKSAhPSBRU3NsRXJyb3I6Okhvc3ROYW1lTWlzbWF0Y2gpIHJldHVybjsKKyAgICAgICAgfQor
ICAgICAgICByZXBseS0+aWdub3JlU3NsRXJyb3JzKGVycm9ycyk7IC8vIE9ubHkgdGhpcyBleHBs
aWNpdGx5IHBpbm5lZCBob3N0IGNlcnRpZmljYXRlLgorICAgIH0pOworICAgIGNvbm5lY3QocmVw
bHksICZRTmV0d29ya1JlcGx5OjpyZWFkeVJlYWQsIHRoaXMsIFtyZXBseSwgZGF0YSwgb3ZlcnNp
emVkXSB7CisgICAgICAgIGlmICgqb3ZlcnNpemVkIHx8IHJlcGx5LT5pc0ZpbmlzaGVkKCkpIHJl
dHVybjsKKyAgICAgICAgaWYgKGRhdGEtPnNpemUoKSArIHJlcGx5LT5ieXRlc0F2YWlsYWJsZSgp
ID4gNjU1MzYpIHsgKm92ZXJzaXplZCA9IHRydWU7IHJlcGx5LT5hYm9ydCgpOyByZXR1cm47IH0K
KyAgICAgICAgZGF0YS0+YXBwZW5kKHJlcGx5LT5yZWFkQWxsKCkpOworICAgIH0pOworICAgIGNv
bm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5OjpmaW5pc2hlZCwgdGhpcywgW3RoaXMsIHJlcGx5
LCBkYXRhLCBpbnZhbGlkUGluLCBvdmVyc2l6ZWRdIHsKKyAgICAgICAgbV9yZXBseSA9IG51bGxw
dHI7CisgICAgICAgIGludCBzdGF0dXMgPSByZXBseS0+YXR0cmlidXRlKFFOZXR3b3JrUmVxdWVz
dDo6SHR0cFN0YXR1c0NvZGVBdHRyaWJ1dGUpLnRvSW50KCk7CisgICAgICAgIGlmICgqb3ZlcnNp
emVkKSBmYWlsKHRyKCJIb3N0IHN0YXRzIHJlc3BvbnNlIGV4Y2VlZGVkIHRoZSBzaXplIGxpbWl0
IikpOworICAgICAgICBlbHNlIGlmICgqaW52YWxpZFBpbikgZmFpbCh0cigiSG9zdCBjZXJ0aWZp
Y2F0ZSBjaGFuZ2VkOyB2ZXJpZnkgdGhlIHNhdmVkIGZpbmdlcnByaW50IikpOworICAgICAgICBl
bHNlIGlmIChzdGF0dXMgPT0gNDAxIHx8IHN0YXR1cyA9PSA0MDMpIGZhaWwodHIoIkhvc3Qgc3Rh
dHMgYWNjZXNzIGRlbmllZDogY2hlY2sgdGhlIHJlYWQtb25seSB0b2tlbiIpKTsKKyAgICAgICAg
ZWxzZSBpZiAoc3RhdHVzID09IDQwNCkgZmFpbCh0cigiVGhpcyBob3N0IGRvZXMgbm90IHByb3Zp
ZGUgVmliZXBvbGxvIGhhcmR3YXJlIHN0YXRzIikpOworICAgICAgICBlbHNlIGlmIChyZXBseS0+
ZXJyb3IoKSA9PSBRTmV0d29ya1JlcGx5OjpTc2xIYW5kc2hha2VGYWlsZWRFcnJvcikgZmFpbCh0
cigiVmVyaWZ5IHRoZSBob3N0IGNlcnRpZmljYXRlIGZpbmdlcnByaW50IGluIENvbmZpZ3VyZSIp
KTsKKyAgICAgICAgZWxzZSBpZiAocmVwbHktPmVycm9yKCkgIT0gUU5ldHdvcmtSZXBseTo6Tm9F
cnJvciB8fCBzdGF0dXMgIT0gMjAwKSBmYWlsKHRyKCJIb3N0IHN0YXRzIHVuYXZhaWxhYmxlOiBj
aGVjayBjb25uZWN0aW9uIGFuZCByZWFsdGltZSBzdGF0cyBzZXR0aW5nIikpOworICAgICAgICBl
bHNlIHsKKyAgICAgICAgICAgIGRhdGEtPmFwcGVuZChyZXBseS0+cmVhZEFsbCgpKTsgUVN0cmlu
ZyBlcnJvcjsKKyAgICAgICAgICAgIGF1dG8gcGFyc2VkID0gcGFyc2VTdGF0cygqZGF0YSwgJmVy
cm9yKTsKKyAgICAgICAgICAgIGlmICghZXJyb3IuaXNFbXB0eSgpKSBmYWlsKGVycm9yKTsKKyAg
ICAgICAgICAgIGVsc2UgeyBtX3N0YXRzVGltZXIuc2V0SW50ZXJ2YWwoMjAwMCk7IG1fc3RhdHMg
PSBwYXJzZWQ7IG1fc3RhdHVzID0gdHIoIkhPU1Qg4oCiIHJlY2VpdmVkICUxIikuYXJnKFFEYXRl
VGltZTo6Y3VycmVudERhdGVUaW1lKCkudG9TdHJpbmcoImhoOm1tOnNzIikpOyBlbWl0IHN0YXRz
Q2hhbmdlZCgpOyB9CisgICAgICAgIH0KKyAgICAgICAgcmVwbHktPmRlbGV0ZUxhdGVyKCk7Cisg
ICAgfSk7CisgICAgLy8gQWJzb2x1dGUgcmVxdWVzdCBib3VuZCBldmVuIGlmIGEgcGVlciBrZWVw
cyBzZW5kaW5nIG9jY2FzaW9uYWwgYnl0ZXMuCisgICAgUVRpbWVyOjpzaW5nbGVTaG90KDM1MDAs
IHJlcGx5LCBbcmVwbHldIHsgaWYgKCFyZXBseS0+aXNGaW5pc2hlZCgpKSByZXBseS0+YWJvcnQo
KTsgfSk7Cit9CitRVmFyaWFudE1hcCBDcmltc29uU3RhdHVzOjpyZWFkTG9jYWwoY29uc3QgUVN0
cmluZyYgcm9vdCkgeworICAgIFFWYXJpYW50TWFwIG91dDsgUVN0cmluZ0xpc3QgbmV0d29ya3M7
CisgICAgZm9yIChjb25zdCBhdXRvJiBuYW1lIDogUURpcihyb290ICsgIi9jbGFzcy9uZXQiKS5l
bnRyeUxpc3QoUURpcjo6RGlycyB8IFFEaXI6Ok5vRG90QW5kRG90RG90KSkgeworICAgICAgICBp
ZiAobmFtZSA9PSAibG8iIHx8IHJlYWQocm9vdCArICIvY2xhc3MvbmV0LyIgKyBuYW1lICsgIi9v
cGVyc3RhdGUiKSAhPSAidXAiKSBjb250aW51ZTsKKyAgICAgICAgbmV0d29ya3MgPDwgbmFtZTsK
KyAgICB9CisgICAgb3V0WyJjb25uZWN0ZWQiXSA9ICFuZXR3b3Jrcy5pc0VtcHR5KCk7IG91dFsi
bmV0d29yayJdID0gbmV0d29ya3MuaXNFbXB0eSgpID8gdHIoIk5vIGFjdGl2ZSBuZXR3b3JrIGxp
bmsiKSA6IG5ldHdvcmtzLmpvaW4oIiwgIik7CisgICAgLy8gTGluayBzdGF0dXMgaXMgaW50ZW50
aW9uYWxseSBub3QgcHJlc2VudGVkIGFzIGludGVybmV0IHJlYWNoYWJpbGl0eS4KKyAgICBvdXRb
ImJhdHRlcnlQZXJjZW50Il0gPSAtMTsgb3V0WyJiYXR0ZXJ5U3RhdGUiXSA9IHRyKCJCYXR0ZXJ5
IHVuYXZhaWxhYmxlIik7CisgICAgZm9yIChjb25zdCBhdXRvJiBuYW1lIDogUURpcihyb290ICsg
Ii9jbGFzcy9wb3dlcl9zdXBwbHkiKS5lbnRyeUxpc3QoUURpcjo6RGlycyB8IFFEaXI6Ok5vRG90
QW5kRG90RG90KSkgeworICAgICAgICBjb25zdCBhdXRvIGJhc2UgPSByb290ICsgIi9jbGFzcy9w
b3dlcl9zdXBwbHkvIiArIG5hbWUgKyAiLyI7CisgICAgICAgIGlmIChyZWFkKGJhc2UgKyAidHlw
ZSIpICE9ICJCYXR0ZXJ5IiB8fCByZWFkKGJhc2UgKyAicHJlc2VudCIpID09ICIwIikgY29udGlu
dWU7CisgICAgICAgIGJvb2wgb2s7IGludCBjYXAgPSByZWFkKGJhc2UgKyAiY2FwYWNpdHkiKS50
b0ludCgmb2spOworICAgICAgICBpZiAob2sgJiYgY2FwID49IDAgJiYgY2FwIDw9IDEwMCkgb3V0
WyJiYXR0ZXJ5UGVyY2VudCJdID0gY2FwOworICAgICAgICBjb25zdCBhdXRvIHN0YXRlID0gcmVh
ZChiYXNlICsgInN0YXR1cyIpOyBvdXRbImJhdHRlcnlTdGF0ZSJdID0gc3RhdGUuaXNFbXB0eSgp
ID8gdHIoIlVua25vd24iKSA6IHN0YXRlOyBicmVhazsKKyAgICB9CisgICAgcmV0dXJuIG91dDsK
K30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6cmVmcmVzaExvY2FsKCkgeworICAgIG1fbG9jYWwgPSBy
ZWFkTG9jYWwoKTsgbV9sb2NhbFsid2lmaVNpZ25hbCJdID0gLTE7IGVtaXQgbG9jYWxDaGFuZ2Vk
KCk7CisgICAgaWYgKG1fd2lmaS5zdGF0ZSgpID09IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSB7Cisg
ICAgICAgIG1fd2lmaS5zdGFydCgibm1jbGkiLCB7Ii10IiwgIi0tZXNjYXBlIiwgIm5vIiwgIi1m
IiwgIkFDVElWRSxTSUdOQUwsU1NJRCIsICJkZXZpY2UiLCAid2lmaSIsICJsaXN0IiwgIi0tcmVz
Y2FuIiwgIm5vIn0pOworICAgICAgICBRVGltZXI6OnNpbmdsZVNob3QoMjAwMCwgJm1fd2lmaSwg
W3RoaXNdIHsgaWYgKG1fd2lmaS5zdGF0ZSgpICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSBtX3dp
Zmkua2lsbCgpOyB9KTsKKyAgICB9Cit9CisKK3N0YXRpYyB2b2lkIHJlZ2lzdGVyQ3JpbXNvblN0
YXR1cygpIHsKKyAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGU8Q3JpbXNvblN0YXR1cz4oIkNy
aW1zb25TdGF0dXMiLCAxLCAwLCAiQ3JpbXNvblN0YXR1cyIsCisgICAgICAgIFtdKFFRbWxFbmdp
bmUqLCBRSlNFbmdpbmUqKSAtPiBRT2JqZWN0KiB7IHJldHVybiBuZXcgQ3JpbXNvblN0YXR1cygp
OyB9KTsKK30KK1FfQ09SRUFQUF9TVEFSVFVQX0ZVTkNUSU9OKHJlZ2lzdGVyQ3JpbXNvblN0YXR1
cykKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmggYi9hcHAvbW9v
bmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5oCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAw
MDAwLi4yZGFjMGQxYwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29u
c3RhdHVzLmgKQEAgLTAsMCArMSw1MiBAQAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVj
dD4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRVGltZXI+CisjaW5jbHVkZSA8
UU5ldHdvcmtBY2Nlc3NNYW5hZ2VyPgorI2luY2x1ZGUgPFFQb2ludGVyPgorI2luY2x1ZGUgPFFO
ZXR3b3JrUmVwbHk+CisjaW5jbHVkZSA8UVByb2Nlc3M+CisKKy8vIE9wdGlvbmFsIGxhdW5jaGVy
IHN0YXR1cy4gTmV2ZXIgcGFydGljaXBhdGVzIGluIHRoZSBzdHJlYW1pbmcvZGVjb2RlciBwYXRo
LgorY2xhc3MgQ3JpbXNvblN0YXR1cyA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAor
ICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgbG9jYWwgUkVBRCBsb2NhbCBOT1RJRlkgbG9jYWxD
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgc3RhdHMgUkVBRCBzdGF0cyBOT1RJ
Rlkgc3RhdHNDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBzdGF0dXMgUkVBRCBzdGF0
dXMgTk9USUZZIHN0YXRzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgZW5kcG9pbnQg
UkVBRCBlbmRwb2ludCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJp
bmcgZmluZ2VycHJpbnQgUkVBRCBmaW5nZXJwcmludCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKKyAg
ICBRX1BST1BFUlRZKGJvb2wgY29uZmlndXJlZCBSRUFEIGNvbmZpZ3VyZWQgTk9USUZZIGNvbmZp
Z0NoYW5nZWQpCitwdWJsaWM6CisgICAgZXhwbGljaXQgQ3JpbXNvblN0YXR1cyhRT2JqZWN0KiBw
YXJlbnQgPSBudWxscHRyKTsKKyAgICB+Q3JpbXNvblN0YXR1cygpIG92ZXJyaWRlOworICAgIFFW
YXJpYW50TWFwIGxvY2FsKCkgY29uc3QgeyByZXR1cm4gbV9sb2NhbDsgfQorICAgIFFWYXJpYW50
TWFwIHN0YXRzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0czsgfQorICAgIFFTdHJpbmcgc3RhdHVz
KCkgY29uc3QgeyByZXR1cm4gbV9zdGF0dXM7IH0KKyAgICBRU3RyaW5nIGVuZHBvaW50KCkgY29u
c3QgeyByZXR1cm4gbV9lbmRwb2ludDsgfQorICAgIFFTdHJpbmcgZmluZ2VycHJpbnQoKSBjb25z
dCB7IHJldHVybiBtX3BpbjsgfQorICAgIGJvb2wgY29uZmlndXJlZCgpIGNvbnN0IHsgcmV0dXJu
ICFtX2VuZHBvaW50LmlzRW1wdHkoKSAmJiAhbV90b2tlbi5pc0VtcHR5KCk7IH0KKyAgICBRX0lO
Vk9LQUJMRSB2b2lkIHNlbGVjdEhvc3QoUVN0cmluZyBpZCwgUVN0cmluZyBzdWdnZXN0ZWRVcmwp
OworICAgIFFfSU5WT0tBQkxFIGJvb2wgY29uZmlndXJlKFFTdHJpbmcgdXJsLCBRU3RyaW5nIHRv
a2VuLCBRU3RyaW5nIHBpbik7CisgICAgUV9JTlZPS0FCTEUgdm9pZCBzZXRWaXNpYmxlKGJvb2wg
dmlzaWJsZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCByZWZyZXNoKCk7CisgICAgc3RhdGljIFFW
YXJpYW50TWFwIHBhcnNlU3RhdHMoY29uc3QgUUJ5dGVBcnJheSYgYnl0ZXMsIFFTdHJpbmcqIGVy
cm9yKTsKKyAgICBzdGF0aWMgYm9vbCB2YWxpZEVuZHBvaW50KGNvbnN0IFFTdHJpbmcmIHVybCk7
CisgICAgc3RhdGljIFFTdHJpbmcgbm9ybWFsaXplZFBpbihRU3RyaW5nIHBpbik7CisgICAgc3Rh
dGljIFFWYXJpYW50TWFwIHJlYWRMb2NhbChjb25zdCBRU3RyaW5nJiBzeXNSb290ID0gIi9zeXMi
KTsKK3NpZ25hbHM6CisgICAgdm9pZCBsb2NhbENoYW5nZWQoKTsKKyAgICB2b2lkIHN0YXRzQ2hh
bmdlZCgpOworICAgIHZvaWQgY29uZmlnQ2hhbmdlZCgpOworcHJpdmF0ZToKKyAgICB2b2lkIHJl
ZnJlc2hMb2NhbCgpOworICAgIHZvaWQgZmFpbChRU3RyaW5nIG1lc3NhZ2UpOworICAgIHZvaWQg
Y2FuY2VsKCk7CisgICAgUVN0cmluZyBjb25maWdGaWxlKCkgY29uc3Q7CisgICAgUVN0cmluZyBt
X2hvc3QsIG1fZW5kcG9pbnQsIG1fdG9rZW4sIG1fcGluLCBtX3N0YXR1cyA9ICJDaG9vc2UgYSBo
b3N0IHRvIHZpZXcgaGFyZHdhcmUgc3RhdHMiOworICAgIFFWYXJpYW50TWFwIG1fbG9jYWwsIG1f
c3RhdHM7CisgICAgUVRpbWVyIG1fbG9jYWxUaW1lciwgbV9zdGF0c1RpbWVyOworICAgIFFQcm9j
ZXNzIG1fd2lmaTsKKyAgICBRTmV0d29ya0FjY2Vzc01hbmFnZXIgbV9uZXR3b3JrOworICAgIFFQ
b2ludGVyPFFOZXR3b3JrUmVwbHk+IG1fcmVwbHk7CisgICAgYm9vbCBtX3Zpc2libGUgPSBmYWxz
ZTsKK307CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmNwcCBi
L2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0
CmluZGV4IDAwMDAwMDAwLi5hNjNkNTJkYwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGln
aHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwCkBAIC0wLDAgKzEsNDEgQEAKKyNpbmNsdWRlICJlY2xp
cHNlcHJvZmlsZXMuaCIKKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVkZSA8
UUNvcmVBcHBsaWNhdGlvbj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorUVN0cmluZyBFY2xpcHNl
UHJvZmlsZXM6OmtleShRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSkgeworICAgIHJldHVybiAi
ZWNsaXBzZS9wcm9maWxlcy8iICsgUVN0cmluZzo6ZnJvbUxhdGluMShRQ3J5cHRvZ3JhcGhpY0hh
c2g6Omhhc2goaG9zdC50b1V0ZjgoKSwgUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4
KCkpICsgIi8iICsgUVN0cmluZzo6ZnJvbUxhdGluMShRQ3J5cHRvZ3JhcGhpY0hhc2g6Omhhc2go
bmFtZS50cmltbWVkKCkudG9VdGY4KCksIFFDcnlwdG9ncmFwaGljSGFzaDo6U2hhMjU2KS50b0hl
eCgpKTsKK30KK2Jvb2wgRWNsaXBzZVByb2ZpbGVzOjp2YWxpZChjb25zdCBRVmFyaWFudE1hcCYg
dmFsdWVzKSB7CisgICAgY29uc3QgUU1hcDxRU3RyaW5nLFFQYWlyPGludCxpbnQ+PiByYW5nZXMg
PSB7eyJ3aWR0aCIsezMyMCw3NjgwfX0sIHsiaGVpZ2h0Iix7MjAwLDQzMjB9fSwgeyJmcHMiLHsx
LDI0MH19LCB7ImJpdHJhdGVLYnBzIix7NTAwLDE1MDAwMH19fTsKKyAgICBpZiAodmFsdWVzLnNp
emUoKSAhPSByYW5nZXMuc2l6ZSgpKSByZXR1cm4gZmFsc2U7CisgICAgZm9yIChhdXRvIGkgPSBy
YW5nZXMuYmVnaW4oKTsgaSAhPSByYW5nZXMuZW5kKCk7ICsraSkgeworICAgICAgICBib29sIG9r
OyBhdXRvIG4gPSB2YWx1ZXMudmFsdWUoaS5rZXkoKSkudG9JbnQoJm9rKTsKKyAgICAgICAgaWYg
KCFvayB8fCBuIDwgaS52YWx1ZSgpLmZpcnN0IHx8IG4gPiBpLnZhbHVlKCkuc2Vjb25kKSByZXR1
cm4gZmFsc2U7CisgICAgfQorICAgIHJldHVybiB0cnVlOworfQorYm9vbCBFY2xpcHNlUHJvZmls
ZXM6OnNhdmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUsIFFWYXJpYW50TWFwIHZhbHVlcykg
eworICAgIG5hbWUgPSBuYW1lLnRyaW1tZWQoKTsKKyAgICBpZiAoaG9zdC5zaXplKCkgPiAyNTYg
fHwgbmFtZS5pc0VtcHR5KCkgfHwgbmFtZS5zaXplKCkgPiA0OCB8fCAhdmFsaWQodmFsdWVzKSkg
cmV0dXJuIGZhbHNlOworICAgIGlmICghbmFtZXMoaG9zdCkuY29udGFpbnMobmFtZSkgJiYgbmFt
ZXMoaG9zdCkuc2l6ZSgpID49IDMyKSByZXR1cm4gZmFsc2U7CisgICAgUVNldHRpbmdzIHNldHRp
bmdzOyBzZXR0aW5ncy5zZXRWYWx1ZShrZXkoaG9zdCxuYW1lKSsiL25hbWUiLG5hbWUpOyBzZXR0
aW5ncy5zZXRWYWx1ZShrZXkoaG9zdCxuYW1lKSsiL3ZhbHVlcyIsdmFsdWVzKTsgc2V0dGluZ3Mu
c3luYygpOworICAgIHJldHVybiBzZXR0aW5ncy5zdGF0dXMoKSA9PSBRU2V0dGluZ3M6Ok5vRXJy
b3I7Cit9CitRVmFyaWFudE1hcCBFY2xpcHNlUHJvZmlsZXM6OmxvYWQoUVN0cmluZyBob3N0LCBR
U3RyaW5nIG5hbWUpIHsKKyAgICBRU2V0dGluZ3Mgc2V0dGluZ3M7IGF1dG8gdmFsdWUgPSBzZXR0
aW5ncy52YWx1ZShrZXkoaG9zdCxuYW1lKSsiL3ZhbHVlcyIpLnRvTWFwKCk7CisgICAgcmV0dXJu
IHZhbGlkKHZhbHVlKSA/IHZhbHVlIDogUVZhcmlhbnRNYXAoKTsKK30KK2Jvb2wgRWNsaXBzZVBy
b2ZpbGVzOjpyZW1vdmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUsIGJvb2wgY29uZmlybWVk
KSB7CisgICAgaWYgKCFjb25maXJtZWQpIHJldHVybiBmYWxzZTsKKyAgICBRU2V0dGluZ3Mgc2V0
dGluZ3M7IHNldHRpbmdzLnJlbW92ZShrZXkoaG9zdCxuYW1lKSk7IHNldHRpbmdzLnN5bmMoKTsg
cmV0dXJuIHNldHRpbmdzLnN0YXR1cygpID09IFFTZXR0aW5nczo6Tm9FcnJvcjsKK30KK1FTdHJp
bmdMaXN0IEVjbGlwc2VQcm9maWxlczo6bmFtZXMoUVN0cmluZyBob3N0KSB7CisgICAgUVNldHRp
bmdzIHNldHRpbmdzOyBzZXR0aW5ncy5iZWdpbkdyb3VwKGtleShob3N0LCAiIikuc2VjdGlvbign
LycsMCwtMikpOworICAgIFFTdHJpbmdMaXN0IHJlc3VsdDsKKyAgICBmb3IgKGNvbnN0IGF1dG8m
IGNoaWxkIDogc2V0dGluZ3MuY2hpbGRHcm91cHMoKSkgeyBhdXRvIG5hbWUgPSBzZXR0aW5ncy52
YWx1ZShjaGlsZCsiL25hbWUiKS50b1N0cmluZygpOyBpZiAoIW5hbWUuaXNFbXB0eSgpKSByZXN1
bHQuYXBwZW5kKG5hbWUpOyB9CisgICAgcmVzdWx0LnNvcnQoKTsgcmV0dXJuIHJlc3VsdDsKK30K
K3N0YXRpYyB2b2lkIHJlZ2lzdGVyRWNsaXBzZVByb2ZpbGVzKCkgeworICAgIHFtbFJlZ2lzdGVy
U2luZ2xldG9uVHlwZTxFY2xpcHNlUHJvZmlsZXM+KCJFY2xpcHNlUHJvZmlsZXMiLDEsMCwiRWNs
aXBzZVByb2ZpbGVzIixbXShRUW1sRW5naW5lKixRSlNFbmdpbmUqKSAtPiBRT2JqZWN0KiB7IHJl
dHVybiBuZXcgRWNsaXBzZVByb2ZpbGVzKCk7IH0pOworfQorUV9DT1JFQVBQX1NUQVJUVVBfRlVO
Q1RJT04ocmVnaXN0ZXJFY2xpcHNlUHJvZmlsZXMpCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0
b3MvZWNsaXBzZXByb2ZpbGVzLmggYi9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmgK
bmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLmQzOTgzODdhCi0tLSAvZGV2L251
bGwKKysrIGIvYXBwL21vb25saWdodG9zL2VjbGlwc2Vwcm9maWxlcy5oCkBAIC0wLDAgKzEsMjcg
QEAKKyNwcmFnbWEgb25jZQorI2luY2x1ZGUgPFFPYmplY3Q+CisjaW5jbHVkZSA8UVZhcmlhbnRN
YXA+CisjaW5jbHVkZSA8UVNldHRpbmdzPgorY2xhc3MgRWNsaXBzZVByb2ZpbGVzIDogcHVibGlj
IFFPYmplY3QgeworICAgIFFfT0JKRUNUCisgICAgUV9QUk9QRVJUWShpbnQgdGV4dFNjYWxlIFJF
QUQgdGV4dFNjYWxlIFdSSVRFIHNldFRleHRTY2FsZSBOT1RJRlkgYXBwZWFyYW5jZUNoYW5nZWQp
CisgICAgUV9QUk9QRVJUWShib29sIHJlZHVjZWRNb3Rpb24gUkVBRCByZWR1Y2VkTW90aW9uIFdS
SVRFIHNldFJlZHVjZWRNb3Rpb24gTk9USUZZIGFwcGVhcmFuY2VDaGFuZ2VkKQorICAgIFFfUFJP
UEVSVFkoYm9vbCBoaWdoQ29udHJhc3QgUkVBRCBoaWdoQ29udHJhc3QgV1JJVEUgc2V0SGlnaENv
bnRyYXN0IE5PVElGWSBhcHBlYXJhbmNlQ2hhbmdlZCkKK3B1YmxpYzoKKyAgICBleHBsaWNpdCBF
Y2xpcHNlUHJvZmlsZXMoUU9iamVjdCogcGFyZW50ID0gbnVsbHB0cikgOiBRT2JqZWN0KHBhcmVu
dCkge30KKyAgICBpbnQgdGV4dFNjYWxlKCkgY29uc3QgeyByZXR1cm4gcUJvdW5kKDEwMCxRU2V0
dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS90ZXh0U2NhbGUiLDEwMCkudG9JbnQoKSwxMjUpOyB9Cisg
ICAgYm9vbCByZWR1Y2VkTW90aW9uKCkgY29uc3QgeyByZXR1cm4gUVNldHRpbmdzKCkudmFsdWUo
ImVjbGlwc2UvcmVkdWNlZE1vdGlvbiIsZmFsc2UpLnRvQm9vbCgpOyB9CisgICAgYm9vbCBoaWdo
Q29udHJhc3QoKSBjb25zdCB7IHJldHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9oaWdo
Q29udHJhc3QiLGZhbHNlKS50b0Jvb2woKTsgfQorICAgIHZvaWQgc2V0VGV4dFNjYWxlKGludCB2
YWx1ZSkgeyBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS90ZXh0U2NhbGUiLHFCb3VuZCgx
MDAsdmFsdWUsMTI1KSk7IGVtaXQgYXBwZWFyYW5jZUNoYW5nZWQoKTsgfQorICAgIHZvaWQgc2V0
UmVkdWNlZE1vdGlvbihib29sIHZhbHVlKSB7IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNl
L3JlZHVjZWRNb3Rpb24iLHZhbHVlKTsgZW1pdCBhcHBlYXJhbmNlQ2hhbmdlZCgpOyB9CisgICAg
dm9pZCBzZXRIaWdoQ29udHJhc3QoYm9vbCB2YWx1ZSkgeyBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgi
ZWNsaXBzZS9oaWdoQ29udHJhc3QiLHZhbHVlKTsgZW1pdCBhcHBlYXJhbmNlQ2hhbmdlZCgpOyB9
CisgICAgUV9JTlZPS0FCTEUgYm9vbCBzYXZlKFFTdHJpbmcgaG9zdCwgUVN0cmluZyBuYW1lLCBR
VmFyaWFudE1hcCB2YWx1ZXMpOworICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50TWFwIGxvYWQoUVN0
cmluZyBob3N0LCBRU3RyaW5nIG5hbWUpOworICAgIFFfSU5WT0tBQkxFIGJvb2wgcmVtb3ZlKFFT
dHJpbmcgaG9zdCwgUVN0cmluZyBuYW1lLCBib29sIGNvbmZpcm1lZCk7CisgICAgUV9JTlZPS0FC
TEUgUVN0cmluZ0xpc3QgbmFtZXMoUVN0cmluZyBob3N0KTsKKyAgICBzdGF0aWMgYm9vbCB2YWxp
ZChjb25zdCBRVmFyaWFudE1hcCYgdmFsdWVzKTsKK3NpZ25hbHM6CisgICAgdm9pZCBhcHBlYXJh
bmNlQ2hhbmdlZCgpOworcHJpdmF0ZToKKyAgICBzdGF0aWMgUVN0cmluZyBrZXkoUVN0cmluZyBo
b3N0LCBRU3RyaW5nIG5hbWUpOworfTsKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9tYW5h
Z2VkdXBkYXRlcy5jcHAgYi9hcHAvbW9vbmxpZ2h0b3MvbWFuYWdlZHVwZGF0ZXMuY3BwCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwLi43MDFkZjUyMQotLS0gL2Rldi9udWxsCisr
KyBiL2FwcC9tb29ubGlnaHRvcy9tYW5hZ2VkdXBkYXRlcy5jcHAKQEAgLTAsMCArMSwxMzIgQEAK
Ky8vIE1vb25saWdodC1PUyBvd25zIHRoaXMgY3VzdG9taXplZCBuYXRpdmUgY2xpZW50LiBObyBm
ZWVkIHJlcXVlc3RzLCBhc3NldAorLy8gZG93bmxvYWRzLCBzd2FwcyBvciByZWxhdW5jaGVzIGFy
ZSBjb21waWxlZCBpbnRvIHRoaXMgdXBkYXRlIGltcGxlbWVudGF0aW9uLgorI2luY2x1ZGUgIi4u
L2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaCIKKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9u
PgorI2luY2x1ZGUgPFFKc29uT2JqZWN0PgorCitzdGF0aWMgUVN0cmluZyBzdHJpcEJ1aWxkTWV0
YWRhdGEoY29uc3QgUVN0cmluZyYgdmVyc2lvbikKK3sKKyAgICBpbnQgcGx1c0lkeCA9IHZlcnNp
b24uaW5kZXhPZignKycpOworICAgIHJldHVybiBwbHVzSWR4ID49IDAgPyB2ZXJzaW9uLmxlZnQo
cGx1c0lkeCkgOiB2ZXJzaW9uOworfQorCitzdGF0aWMgYm9vbCBpc051bWVyaWNJZGVudGlmaWVy
KGNvbnN0IFFTdHJpbmcmIHMpCit7CisgICAgaWYgKHMuaXNFbXB0eSgpKSB7CisgICAgICAgIHJl
dHVybiBmYWxzZTsKKyAgICB9CisgICAgZm9yIChjb25zdCBRQ2hhciYgYyA6IHMpIHsKKyAgICAg
ICAgaWYgKCFjLmlzRGlnaXQoKSkgeworICAgICAgICAgICAgcmV0dXJuIGZhbHNlOworICAgICAg
ICB9CisgICAgfQorICAgIHJldHVybiB0cnVlOworfQorCitpbnQgQXV0b1VwZGF0ZUNoZWNrZXI6
OmNvbXBhcmVTZW1hbnRpY1ZlcnNpb25zKGNvbnN0IFFTdHJpbmcmIHYxLCBjb25zdCBRU3RyaW5n
JiB2MikKK3sKKyAgICBRU3RyaW5nIHMxID0gc3RyaXBCdWlsZE1ldGFkYXRhKHYxKTsKKyAgICBR
U3RyaW5nIHMyID0gc3RyaXBCdWlsZE1ldGFkYXRhKHYyKTsKKworICAgIGludCBkYXNoMSA9IHMx
LmluZGV4T2YoJy0nKTsKKyAgICBpbnQgZGFzaDIgPSBzMi5pbmRleE9mKCctJyk7CisgICAgUVN0
cmluZyBiYXNlMSA9IGRhc2gxID49IDAgPyBzMS5sZWZ0KGRhc2gxKSA6IHMxOworICAgIFFTdHJp
bmcgYmFzZTIgPSBkYXNoMiA+PSAwID8gczIubGVmdChkYXNoMikgOiBzMjsKKyAgICBRU3RyaW5n
IHByZTEgPSBkYXNoMSA+PSAwID8gczEubWlkKGRhc2gxICsgMSkgOiBRU3RyaW5nKCk7CisgICAg
UVN0cmluZyBwcmUyID0gZGFzaDIgPj0gMCA/IHMyLm1pZChkYXNoMiArIDEpIDogUVN0cmluZygp
OworCisgICAgLy8gTnVtZXJpYyBiYXNlIHZlcnNpb25zIGNvbXBhcmUgZmlyc3QgKDAuNC4wLWJl
dGEuMDAxID4gMC4zLjApCisgICAgY29uc3QgUVN0cmluZ0xpc3QgYmFzZVBhcnRzMSA9IGJhc2Ux
LnNwbGl0KCcuJyk7CisgICAgY29uc3QgUVN0cmluZ0xpc3QgYmFzZVBhcnRzMiA9IGJhc2UyLnNw
bGl0KCcuJyk7CisgICAgZm9yIChpbnQgaSA9IDA7IGkgPCBxTWF4KGJhc2VQYXJ0czEuY291bnQo
KSwgYmFzZVBhcnRzMi5jb3VudCgpKTsgaSsrKSB7CisgICAgICAgIHFsb25nbG9uZyBiMSA9IGkg
PCBiYXNlUGFydHMxLmNvdW50KCkgPyBiYXNlUGFydHMxW2ldLnRvTG9uZ0xvbmcoKSA6IDA7Cisg
ICAgICAgIHFsb25nbG9uZyBiMiA9IGkgPCBiYXNlUGFydHMyLmNvdW50KCkgPyBiYXNlUGFydHMy
W2ldLnRvTG9uZ0xvbmcoKSA6IDA7CisgICAgICAgIGlmIChiMSAhPSBiMikgeworICAgICAgICAg
ICAgcmV0dXJuIGIxIDwgYjIgPyAtMSA6IDE7CisgICAgICAgIH0KKyAgICB9CisKKyAgICAvLyBF
cXVhbCBiYXNlOiBhIHJlbGVhc2Ugd2l0aCBubyBwcmVyZWxlYXNlIHN1ZmZpeCBvdXRyYW5rcyBh
bnkgcHJlcmVsZWFzZQorICAgIGlmIChwcmUxLmlzRW1wdHkoKSAhPSBwcmUyLmlzRW1wdHkoKSkg
eworICAgICAgICByZXR1cm4gcHJlMS5pc0VtcHR5KCkgPyAxIDogLTE7CisgICAgfQorICAgIGlm
IChwcmUxLmlzRW1wdHkoKSkgeworICAgICAgICByZXR1cm4gMDsKKyAgICB9CisKKyAgICAvLyBU
d28gcHJlcmVsZWFzZXM6IGNvbXBhcmUgZG90LXNlcGFyYXRlZCBpZGVudGlmaWVycyBsZWZ0IHRv
IHJpZ2h0LgorICAgIC8vIE51bWVyaWMgaWRlbnRpZmllcnMgY29tcGFyZSBudW1lcmljYWxseSAo
bGVhZGluZyB6ZXJvcyB0b2xlcmF0ZWQg4oCUIG91cgorICAgIC8vIENJIHplcm8tcGFkcyBjb3Vu
dGVycyksIGFscGhhbnVtZXJpYyBvbmVzIGxleGljYWxseSBpbiBBU0NJSSBvcmRlciwgYW5kCisg
ICAgLy8gbnVtZXJpYyBhbHdheXMgcmFua3MgYmVsb3cgYWxwaGFudW1lcmljLiBUaGlzIGlzIHdo
YXQgb3JkZXJzCisgICAgLy8gImFscGhhIiA8ICJiZXRhIiA8ICJyYyIgYXQgYW4gZXF1YWwgYmFz
ZSDigJQgdGhlIHByb3BlcnR5IHRoZSBwcmV2aW91cworICAgIC8vIGltcGxlbWVudGF0aW9uIGxh
Y2tlZCAoaXQgc2tpcHBlZCB0aGUgd29yZHMgYW5kIGNvbXBhcmVkIG9ubHkgbnVtYmVycywKKyAg
ICAvLyBzbyAwLjMuMC1iZXRhLjAwOCB3cm9uZ2x5IG91dHJhbmtlZCAwLjMuMC1yYy4wMDIpLgor
ICAgIGNvbnN0IFFTdHJpbmdMaXN0IGlkczEgPSBwcmUxLnNwbGl0KCcuJyk7CisgICAgY29uc3Qg
UVN0cmluZ0xpc3QgaWRzMiA9IHByZTIuc3BsaXQoJy4nKTsKKyAgICBmb3IgKGludCBpID0gMDsg
aSA8IHFNYXgoaWRzMS5jb3VudCgpLCBpZHMyLmNvdW50KCkpOyBpKyspIHsKKyAgICAgICAgaWYg
KGkgPj0gaWRzMS5jb3VudCgpKSB7CisgICAgICAgICAgICAvLyBFcXVhbCBwcmVmaXgsIGZld2Vy
IGZpZWxkcyA9IGxvd2VyIHByZWNlZGVuY2UgKMKnMTEuNC40KQorICAgICAgICAgICAgcmV0dXJu
IC0xOworICAgICAgICB9CisgICAgICAgIGlmIChpID49IGlkczIuY291bnQoKSkgeworICAgICAg
ICAgICAgcmV0dXJuIDE7CisgICAgICAgIH0KKyAgICAgICAgYm9vbCBudW0xID0gaXNOdW1lcmlj
SWRlbnRpZmllcihpZHMxW2ldKTsKKyAgICAgICAgYm9vbCBudW0yID0gaXNOdW1lcmljSWRlbnRp
ZmllcihpZHMyW2ldKTsKKyAgICAgICAgaWYgKG51bTEgJiYgbnVtMikgeworICAgICAgICAgICAg
cWxvbmdsb25nIHAxID0gaWRzMVtpXS50b0xvbmdMb25nKCk7CisgICAgICAgICAgICBxbG9uZ2xv
bmcgcDIgPSBpZHMyW2ldLnRvTG9uZ0xvbmcoKTsKKyAgICAgICAgICAgIGlmIChwMSAhPSBwMikg
eworICAgICAgICAgICAgICAgIHJldHVybiBwMSA8IHAyID8gLTEgOiAxOworICAgICAgICAgICAg
fQorICAgICAgICB9CisgICAgICAgIGVsc2UgaWYgKG51bTEgIT0gbnVtMikgeworICAgICAgICAg
ICAgLy8gTnVtZXJpYyBpZGVudGlmaWVycyByYW5rIGJlbG93IGFscGhhbnVtZXJpYyBvbmVzICjC
pzExLjQuMykKKyAgICAgICAgICAgIHJldHVybiBudW0xID8gLTEgOiAxOworICAgICAgICB9Cisg
ICAgICAgIGVsc2UgeworICAgICAgICAgICAgaW50IGNtcCA9IFFTdHJpbmc6OmNvbXBhcmUoaWRz
MVtpXSwgaWRzMltpXSk7CisgICAgICAgICAgICBpZiAoY21wICE9IDApIHsKKyAgICAgICAgICAg
ICAgICByZXR1cm4gY21wIDwgMCA/IC0xIDogMTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgfQor
ICAgIH0KKyAgICByZXR1cm4gMDsKK30KKworQXV0b1VwZGF0ZUNoZWNrZXI6OkF1dG9VcGRhdGVD
aGVja2VyKFFPYmplY3QqIHBhcmVudCkgOgorICAgIFFPYmplY3QocGFyZW50KSwgbV9DaGVja0lu
RmxpZ2h0KGZhbHNlKSwgbV9DaGVja0lzTWFudWFsKGZhbHNlKSwKKyAgICBtX1VwZGF0ZUF2YWls
YWJsZShmYWxzZSksIG1fT2ZmZXJBdmFpbGFibGUoZmFsc2UpLCBtX0luc3RhbGxpbmcoZmFsc2Up
Cit7CisgICAgY2xlYXJPZmZlcigpOworICAgIHNldFN0YXR1cyh0cigiJTEuIFVwZGF0ZXMgYXJl
IG1hbmFnZWQgYnkgTW9vbmxpZ2h0LU9TLiBHZXQgdGhlIG1hdGNoaW5nIE9TIGltYWdlIGZyb20g
JTI7IHVwc3RyZWFtIFZpYmVtaXMgdXBkYXRlcyBhcmUgZGlzYWJsZWQuIikuYXJnKGN1cnJlbnRW
ZXJzaW9uKCksIG1fUmVsZWFzZVVybCkpOworfQorUVN0cmluZyBBdXRvVXBkYXRlQ2hlY2tlcjo6
Y3VycmVudFZlcnNpb24oKSBjb25zdAoreworICAgIHJldHVybiB0cigiRWNsaXBzZSAlMSDCtyBN
b29ubGlnaHQtT1MgY3VzdG9taXplZCIpLmFyZyhRQ29yZUFwcGxpY2F0aW9uOjphcHBsaWNhdGlv
blZlcnNpb24oKSk7Cit9Cit2b2lkIEF1dG9VcGRhdGVDaGVja2VyOjpjbGVhck9mZmVyKCkKK3sK
KyAgICBtX1VwZGF0ZUF2YWlsYWJsZSA9IGZhbHNlOyBtX09mZmVyQXZhaWxhYmxlID0gZmFsc2U7
CisgICAgbV9PZmZlclZlcnNpb24uY2xlYXIoKTsgbV9Bc3NldFVybC5jbGVhcigpOyBtX09mZmVy
VGllciA9IC0xOworICAgIG1fUmVsZWFzZVVybCA9IFFTdHJpbmdMaXRlcmFsKCJodHRwczovL2dp
dGh1Yi5jb20vdGgzZDNjazNyL01vb25saWdodC1PUy9yZWxlYXNlcyIpOworfQordm9pZCBBdXRv
VXBkYXRlQ2hlY2tlcjo6c2V0U3RhdHVzKGNvbnN0IFFTdHJpbmcmIG1lc3NhZ2UpCit7CisgICAg
aWYgKG1fU3RhdHVzTWVzc2FnZSAhPSBtZXNzYWdlKSB7IG1fU3RhdHVzTWVzc2FnZSA9IG1lc3Nh
Z2U7IGVtaXQgc3RhdGVDaGFuZ2VkKCk7IH0KK30KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6OnN0
YXJ0KCkgeyAvKiBObyB0aW1lciBhbmQgbm8gYmFja2dyb3VuZCB1cGRhdGUgcmVxdWVzdHMuICov
IH0KK2Jvb2wgQXV0b1VwZGF0ZUNoZWNrZXI6OmNhbkluc3RhbGxVcGRhdGVzKCkgY29uc3QgeyBy
ZXR1cm4gZmFsc2U7IH0KK2Jvb2wgQXV0b1VwZGF0ZUNoZWNrZXI6OmNhbkluc3RhbGwoKSBjb25z
dCB7IHJldHVybiBmYWxzZTsgfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6Y2hhbm5lbENoYW5n
ZWQoKSB7IGNoZWNrTm93KCk7IH0KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6OmNoZWNrTm93KCkK
K3sKKyAgICBjbGVhck9mZmVyKCk7CisgICAgc2V0U3RhdHVzKHRyKCJVcGRhdGVzIGFyZSBtYW5h
Z2VkIGJ5IE1vb25saWdodC1PUy4gRG93bmxvYWQgdGhlIG1hdGNoaW5nIE9TIGltYWdlIGZyb20g
JTEuIFRoaXMgY2xpZW50IG5ldmVyIGluc3RhbGxzIHVwc3RyZWFtIFZpYmVtaXMgcmVsZWFzZXMu
IikuYXJnKG1fUmVsZWFzZVVybCkpOworICAgIGVtaXQgc3RhdGVDaGFuZ2VkKCk7IGVtaXQgY2hl
Y2tDb21wbGV0ZWQodHJ1ZSwgZmFsc2UpOworfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6aW5z
dGFsbCgpCit7CisgICAgY2hlY2tOb3coKTsKKyAgICBlbWl0IGluc3RhbGxGYWlsZWQodHIoIlN0
YW5kYWxvbmUgVmliZW1pcyBpbnN0YWxsYXRpb24gaXMgZGlzYWJsZWQgaW4gTW9vbmxpZ2h0LU9T
LiIpLCBtX1JlbGVhc2VVcmwpOworfQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3N5c3Rl
bWNvbnRyb2xzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAKbmV3IGZp
bGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLjc3ZWM0YzgyCi0tLSAvZGV2L251bGwKKysr
IGIvYXBwL21vb25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmNwcApAQCAtMCwwICsxLDgzIEBACisj
aW5jbHVkZSAic3lzdGVtY29udHJvbHMuaCIKKyNpbmNsdWRlIDxRQ29yZUFwcGxpY2F0aW9uPgor
I2luY2x1ZGUgPFFKc29uRG9jdW1lbnQ+CisjaW5jbHVkZSA8UUpzb25PYmplY3Q+CisjaW5jbHVk
ZSA8UUpzb25BcnJheT4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFGaWxlSW5m
bz4KK1N5c3RlbUNvbnRyb2xzOjpTeXN0ZW1Db250cm9scyhRT2JqZWN0KiBwYXJlbnQpIDogUU9i
amVjdChwYXJlbnQpIHsKKyAgICBtX3RpbWVvdXQuc2V0U2luZ2xlU2hvdCh0cnVlKTsKKyAgICBj
b25uZWN0KCZtX3RpbWVvdXQsICZRVGltZXI6OnRpbWVvdXQsIHRoaXMsIFt0aGlzXSB7IGZhaWwo
dHIoIk9wZXJhdGlvbiB0aW1lZCBvdXQuIFJldHJ5IG9yIHVzZSB0aGUgZGlhZ25vc3RpYyBzaGVs
bC4iKSk7IH0pOworICAgIGNvbm5lY3QoJm1fcHJvY2VzcywgJlFQcm9jZXNzOjpzdGFydGVkLCB0
aGlzLCBbdGhpc10geyByZXF1ZXN0KG1fbW9kZSArICItbGlzdCIpOyB9KTsKKyAgICBjb25uZWN0
KCZtX3Byb2Nlc3MsICZRUHJvY2Vzczo6cmVhZHlSZWFkU3RhbmRhcmRFcnJvciwgdGhpcywgW3Ro
aXNdIHsgbV9wcm9jZXNzLnJlYWRBbGxTdGFuZGFyZEVycm9yKCk7IH0pOworICAgIGNvbm5lY3Qo
Jm1fcHJvY2VzcywgJlFQcm9jZXNzOjpyZWFkeVJlYWRTdGFuZGFyZE91dHB1dCwgdGhpcywgW3Ro
aXNdIHsKKyAgICAgICAgbV9idWZmZXIgKz0gbV9wcm9jZXNzLnJlYWRBbGxTdGFuZGFyZE91dHB1
dCgpOworICAgICAgICBpZiAobV9idWZmZXIuc2l6ZSgpID4gNjU1MzYpIHsgZmFpbCh0cigiSW52
YWxpZCBzeXN0ZW0gcmVzcG9uc2UuIikpOyByZXR1cm47IH0KKyAgICAgICAgd2hpbGUgKG1fYnVm
ZmVyLmNvbnRhaW5zKCdcbicpKSB7CisgICAgICAgICAgICBpbnQgZW5kID0gbV9idWZmZXIuaW5k
ZXhPZignXG4nKTsKKyAgICAgICAgICAgIFFKc29uUGFyc2VFcnJvciBlcnJvcjsKKyAgICAgICAg
ICAgIGF1dG8gZG9jdW1lbnQgPSBRSnNvbkRvY3VtZW50Ojpmcm9tSnNvbihtX2J1ZmZlci5sZWZ0
KGVuZCksICZlcnJvcik7CisgICAgICAgICAgICBtX2J1ZmZlci5yZW1vdmUoMCwgZW5kICsgMSk7
CisgICAgICAgICAgICBpZiAoZXJyb3IuZXJyb3IgIT0gUUpzb25QYXJzZUVycm9yOjpOb0Vycm9y
IHx8ICFkb2N1bWVudC5pc09iamVjdCgpKSB7IGZhaWwodHIoIkludmFsaWQgc3lzdGVtIHJlc3Bv
bnNlLiIpKTsgcmV0dXJuOyB9CisgICAgICAgICAgICBhdXRvIHZhbHVlID0gZG9jdW1lbnQub2Jq
ZWN0KCk7CisgICAgICAgICAgICBpZiAodmFsdWUuY29udGFpbnMoInByb21wdCIpKSB7CisgICAg
ICAgICAgICAgICAgbV9wcm9tcHQgPSB2YWx1ZS52YWx1ZSgicHJvbXB0IikudG9TdHJpbmcoKS5s
ZWZ0KDEwMjQpOworICAgICAgICAgICAgICAgIG1fdGltZW91dC5zdGFydCgxMjAwMDApOworICAg
ICAgICAgICAgfQorICAgICAgICAgICAgaWYgKHZhbHVlLnZhbHVlKCJkb25lIikudG9Cb29sKCkp
IHsKKyAgICAgICAgICAgICAgICBtX3RpbWVvdXQuc3RvcCgpOyBtX2J1c3kgPSBmYWxzZTsgbV9w
cm9tcHQuY2xlYXIoKTsKKyAgICAgICAgICAgICAgICBpZiAodmFsdWUuY29udGFpbnMoIml0ZW1z
IikpIHsKKyAgICAgICAgICAgICAgICAgICAgYXV0byBlbnRyaWVzID0gdmFsdWUudmFsdWUoIml0
ZW1zIikudG9BcnJheSgpOworICAgICAgICAgICAgICAgICAgICBpZiAoZW50cmllcy5zaXplKCkg
PiA2NCkgeyBmYWlsKHRyKCJJbnZhbGlkIGRldmljZSBsaXN0LiIpKTsgcmV0dXJuOyB9CisgICAg
ICAgICAgICAgICAgICAgIG1faXRlbXMgPSBlbnRyaWVzLnRvVmFyaWFudExpc3QoKTsKKyAgICAg
ICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgaWYgKHZhbHVlLnZhbHVlKCJzdGF0ZSIpLmlz
T2JqZWN0KCkpIG1fc3RhdGUgPSB2YWx1ZS52YWx1ZSgic3RhdGUiKS50b09iamVjdCgpLnRvVmFy
aWFudE1hcCgpOworICAgICAgICAgICAgICAgIG1fc3RhdHVzID0gdmFsdWUuY29udGFpbnMoImVy
cm9yIikgPyB2YWx1ZS52YWx1ZSgiZXJyb3IiKS50b1N0cmluZygpLmxlZnQoMTAyNCkgOiB2YWx1
ZS52YWx1ZSgic3RhdHVzIikudG9TdHJpbmcoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAg
IGVtaXQgY2hhbmdlZCgpOworICAgICAgICB9CisgICAgfSk7CisgICAgY29ubmVjdCgmbV9wcm9j
ZXNzLCAmUVByb2Nlc3M6OmVycm9yT2NjdXJyZWQsIHRoaXMsIFt0aGlzXShRUHJvY2Vzczo6UHJv
Y2Vzc0Vycm9yKSB7CisgICAgICAgIGlmICghbV9tb2RlLmlzRW1wdHkoKSkgZmFpbCh0cigiU3lz
dGVtIGNvbnRyb2xzIGFyZSB1bmF2YWlsYWJsZS4gVXNlIHRoZSBkaWFnbm9zdGljIHNoZWxsLiIp
KTsKKyAgICB9KTsKKyAgICBjb25uZWN0KCZtX3Byb2Nlc3MsIFFPdmVybG9hZDxpbnQsUVByb2Nl
c3M6OkV4aXRTdGF0dXM+OjpvZigmUVByb2Nlc3M6OmZpbmlzaGVkKSwgdGhpcywgW3RoaXNdKGlu
dCwgUVByb2Nlc3M6OkV4aXRTdGF0dXMpIHsKKyAgICAgICAgaWYgKCFtX21vZGUuaXNFbXB0eSgp
KSB7IG1fdGltZW91dC5zdG9wKCk7IG1fYnVzeSA9IGZhbHNlOyBtX3Byb21wdC5jbGVhcigpOyBt
X3N0YXR1cyA9IHRyKCJTeXN0ZW0gaGVscGVyIHN0b3BwZWQuIENsb3NlIGFuZCByZW9wZW4gdGhp
cyBwYW5lbC4iKTsgZW1pdCBjaGFuZ2VkKCk7IH0KKyAgICB9KTsKK30KK1N5c3RlbUNvbnRyb2xz
Ojp+U3lzdGVtQ29udHJvbHMoKSB7IGNsb3NlKCk7IGlmICghbV9wcm9jZXNzLndhaXRGb3JGaW5p
c2hlZCg1MDApKSB7IG1fcHJvY2Vzcy5raWxsKCk7IG1fcHJvY2Vzcy53YWl0Rm9yRmluaXNoZWQo
NTAwKTsgfSB9Cit2b2lkIFN5c3RlbUNvbnRyb2xzOjpzZW5kKGNvbnN0IFFKc29uT2JqZWN0JiB2
YWx1ZSkgeyBtX3Byb2Nlc3Mud3JpdGUoUUpzb25Eb2N1bWVudCh2YWx1ZSkudG9Kc29uKFFKc29u
RG9jdW1lbnQ6OkNvbXBhY3QpICsgJ1xuJyk7IH0KK3ZvaWQgU3lzdGVtQ29udHJvbHM6Om9wZW4o
UVN0cmluZyBtb2RlKSB7CisgICAgaWYgKG1vZGUgIT0gIndpZmkiICYmIG1vZGUgIT0gImJ0IiAm
JiBtb2RlICE9ICJjZW50ZXIiKSByZXR1cm47CisgICAgY2xvc2UoKTsKKyAgICBpZiAobV9wcm9j
ZXNzLnN0YXRlKCkgIT0gUVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIHsgbV9wcm9jZXNzLmtpbGwoKTsg
bV9wcm9jZXNzLndhaXRGb3JGaW5pc2hlZCg1MDApOyB9CisgICAgbV9tb2RlID0gbW9kZTsgbV9p
dGVtcy5jbGVhcigpOyBtX3N0YXRlLmNsZWFyKCk7IG1fYnVmZmVyLmNsZWFyKCk7IG1fc3RhdHVz
ID0gdHIoIkxvYWRpbmfigKYiKTsgZW1pdCBjaGFuZ2VkKCk7CisgICAgUVN0cmluZyBoZWxwZXIg
PSAiL3Vzci9sb2NhbC9saWJleGVjL21vb25saWdodC1vcy9zeXN0ZW0tY29udHJvbHMucHkiOwor
I2lmZGVmIE1PT05MSUdIVF9DT05UUk9MU19URVNUCisgICAgaGVscGVyID0gcUVudmlyb25tZW50
VmFyaWFibGUoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIiwgaGVscGVyKTsKKyNlbmRpZgor
ICAgIG1fcHJvY2Vzcy5zdGFydCgicHl0aG9uMyIsIHtoZWxwZXJ9KTsKK30KK3ZvaWQgU3lzdGVt
Q29udHJvbHM6OnJlcXVlc3QoUVN0cmluZyBhY3Rpb24sIFFTdHJpbmcgaWQsIGJvb2wgY29uZmly
bSkgeworICAgIGlmIChtX2J1c3kgfHwgbV9wcm9jZXNzLnN0YXRlKCkgIT0gUVByb2Nlc3M6OlJ1
bm5pbmcgfHwgIWFjdGlvbi5zdGFydHNXaXRoKG1fbW9kZSArICItIikpIHJldHVybjsKKyAgICBj
b25zdCBRU3RyaW5nTGlzdCBhbGxvd2VkID0geyJ3aWZpLWxpc3QiLCAid2lmaS1zY2FuIiwgIndp
ZmktY29ubmVjdCIsICJ3aWZpLWRpc2Nvbm5lY3QiLCAiYnQtbGlzdCIsICJidC1zY2FuIiwgImJ0
LWNvbm5lY3QiLCAiYnQtZGlzY29ubmVjdCIsICJidC1mb3JnZXQiLCAiY2VudGVyLWxpc3QiLCAi
Y2VudGVyLXZvbHVtZSIsICJjZW50ZXItbXV0ZSIsICJjZW50ZXItb3V0cHV0IiwgImNlbnRlci1z
Y3JlZW4iLCAiY2VudGVyLWtleWJvYXJkIiwgImNlbnRlci1yZWJvb3QiLCAiY2VudGVyLXBvd2Vy
b2ZmIiwgImNlbnRlci1zdXNwZW5kIiwgImNlbnRlci1yZXBvcnQifTsKKyAgICBpZiAoIWFsbG93
ZWQuY29udGFpbnMoYWN0aW9uKSkgcmV0dXJuOworICAgIG1fYnVzeSA9IHRydWU7IG1fcHJvbXB0
LmNsZWFyKCk7IG1fc3RhdHVzID0gdHIoIldvcmtpbmfigKYiKTsgbV90aW1lb3V0LnN0YXJ0KDEy
MDAwMCk7CisgICAgc2VuZCh7eyJhY3Rpb24iLCBhY3Rpb259LCB7ImlkIiwgaWR9LCB7ImNvbmZp
cm0iLCBjb25maXJtfX0pOyBlbWl0IGNoYW5nZWQoKTsKK30KK3ZvaWQgU3lzdGVtQ29udHJvbHM6
OmFuc3dlcihRU3RyaW5nIHZhbHVlKSB7CisgICAgaWYgKCFtX2J1c3kgfHwgbV9wcm9tcHQuaXNF
bXB0eSgpIHx8IHZhbHVlLnNpemUoKSA+IDQwOTYgfHwgdmFsdWUuY29udGFpbnMoJ1xuJykgfHwg
dmFsdWUuY29udGFpbnMoJ1xyJykgfHwgdmFsdWUuY29udGFpbnMoUUNoYXIoMCkpKSByZXR1cm47
CisgICAgc2VuZCh7eyJhY3Rpb24iLCAiYW5zd2VyIn0sIHsidmFsdWUiLCB2YWx1ZX19KTsgbV9w
cm9tcHQuY2xlYXIoKTsgbV90aW1lb3V0LnN0YXJ0KDEyMDAwMCk7IGVtaXQgY2hhbmdlZCgpOwor
fQordm9pZCBTeXN0ZW1Db250cm9sczo6Y2xvc2UoKSB7CisgICAgbV9tb2RlLmNsZWFyKCk7IG1f
dGltZW91dC5zdG9wKCk7IG1fYnVzeSA9IGZhbHNlOyBtX3Byb21wdC5jbGVhcigpOyBtX2J1ZmZl
ci5jbGVhcigpOworICAgIGlmIChtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVu
bmluZykgeworICAgICAgICBtX3Byb2Nlc3MudGVybWluYXRlKCk7CisgICAgICAgIFFUaW1lcjo6
c2luZ2xlU2hvdCg0MDAwLCB0aGlzLCBbdGhpc10geyBpZiAobV9tb2RlLmlzRW1wdHkoKSAmJiBt
X3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgbV9wcm9jZXNzLmtpbGwo
KTsgfSk7CisgICAgfQorICAgIGVtaXQgY2hhbmdlZCgpOworfQordm9pZCBTeXN0ZW1Db250cm9s
czo6ZmFpbChRU3RyaW5nIG1lc3NhZ2UpIHsgY2xvc2UoKTsgbV9zdGF0dXMgPSBtZXNzYWdlOyBl
bWl0IGNoYW5nZWQoKTsgfQorc3RhdGljIHZvaWQgcmVnaXN0ZXJTeXN0ZW1Db250cm9scygpIHsK
KyAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGU8U3lzdGVtQ29udHJvbHM+KCJTeXN0ZW1Db250
cm9scyIsIDEsIDAsICJTeXN0ZW1Db250cm9scyIsIFtdKFFRbWxFbmdpbmUqLCBRSlNFbmdpbmUq
KSAtPiBRT2JqZWN0KiB7IHJldHVybiBuZXcgU3lzdGVtQ29udHJvbHMoKTsgfSk7Cit9CitRX0NP
UkVBUFBfU1RBUlRVUF9GVU5DVElPTihyZWdpc3RlclN5c3RlbUNvbnRyb2xzKQpkaWZmIC0tZ2l0
IGEvYXBwL21vb25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmggYi9hcHAvbW9vbmxpZ2h0b3Mvc3lz
dGVtY29udHJvbHMuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uMThlOWRl
YjIKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuaApA
QCAtMCwwICsxLDM5IEBACisjcHJhZ21hIG9uY2UKKyNpbmNsdWRlIDxRT2JqZWN0PgorI2luY2x1
ZGUgPFFKc29uT2JqZWN0PgorI2luY2x1ZGUgPFFQcm9jZXNzPgorI2luY2x1ZGUgPFFUaW1lcj4K
KyNpbmNsdWRlIDxRVmFyaWFudExpc3Q+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CitjbGFzcyBT
eXN0ZW1Db250cm9scyA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorICAgIFFfUFJP
UEVSVFkoUVZhcmlhbnRNYXAgc3RhdGUgUkVBRCBzdGF0ZSBOT1RJRlkgY2hhbmdlZCkKKyAgICBR
X1BST1BFUlRZKFFWYXJpYW50TGlzdCBpdGVtcyBSRUFEIGl0ZW1zIE5PVElGWSBjaGFuZ2VkKQor
ICAgIFFfUFJPUEVSVFkoUVN0cmluZyBzdGF0dXMgUkVBRCBzdGF0dXMgTk9USUZZIGNoYW5nZWQp
CisgICAgUV9QUk9QRVJUWShRU3RyaW5nIHByb21wdCBSRUFEIHByb21wdCBOT1RJRlkgY2hhbmdl
ZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgYnVzeSBSRUFEIGJ1c3kgTk9USUZZIGNoYW5nZWQpCitw
dWJsaWM6CisgICAgZXhwbGljaXQgU3lzdGVtQ29udHJvbHMoUU9iamVjdCogcGFyZW50ID0gbnVs
bHB0cik7CisgICAgflN5c3RlbUNvbnRyb2xzKCk7CisgICAgUVZhcmlhbnRNYXAgc3RhdGUoKSBj
b25zdCB7IHJldHVybiBtX3N0YXRlOyB9CisgICAgUVZhcmlhbnRMaXN0IGl0ZW1zKCkgY29uc3Qg
eyByZXR1cm4gbV9pdGVtczsgfQorICAgIFFTdHJpbmcgc3RhdHVzKCkgY29uc3QgeyByZXR1cm4g
bV9zdGF0dXM7IH0KKyAgICBRU3RyaW5nIHByb21wdCgpIGNvbnN0IHsgcmV0dXJuIG1fcHJvbXB0
OyB9CisgICAgYm9vbCBidXN5KCkgY29uc3QgeyByZXR1cm4gbV9idXN5OyB9CisgICAgUV9JTlZP
S0FCTEUgdm9pZCBvcGVuKFFTdHJpbmcgbW9kZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCByZXF1
ZXN0KFFTdHJpbmcgYWN0aW9uLCBRU3RyaW5nIGlkID0gUVN0cmluZygpLCBib29sIGNvbmZpcm0g
PSBmYWxzZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCBhbnN3ZXIoUVN0cmluZyB2YWx1ZSk7Cisg
ICAgUV9JTlZPS0FCTEUgdm9pZCBjbG9zZSgpOworc2lnbmFsczoKKyAgICB2b2lkIGNoYW5nZWQo
KTsKK3ByaXZhdGU6CisgICAgdm9pZCBzZW5kKGNvbnN0IFFKc29uT2JqZWN0JiB2YWx1ZSk7Cisg
ICAgdm9pZCBmYWlsKFFTdHJpbmcgbWVzc2FnZSk7CisgICAgUVByb2Nlc3MgbV9wcm9jZXNzOwor
ICAgIFFUaW1lciBtX3RpbWVvdXQ7CisgICAgUUJ5dGVBcnJheSBtX2J1ZmZlcjsKKyAgICBRVmFy
aWFudExpc3QgbV9pdGVtczsKKyAgICBRVmFyaWFudE1hcCBtX3N0YXRlOworICAgIFFTdHJpbmcg
bV9tb2RlLCBtX3N0YXR1cywgbV9wcm9tcHQ7CisgICAgYm9vbCBtX2J1c3kgPSBmYWxzZTsKK307
CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvSGFybmVzcy5xbWwgYi9hcHAvbW9v
bmxpZ2h0b3MvdGVzdHMvSGFybmVzcy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAw
MDAwMDAuLjY5OWFmN2ZmCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3Rz
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
bmRleCAwMDAwMDAwMC4uOTk2ZTVhYzQKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0
b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sCkBAIC0wLDAgKzEsMyBAQAorcHJhZ21hIFNpbmdsZXRv
bgoraW1wb3J0IFF0UXVpY2sgMi45CitRdE9iamVjdCB7IHByb3BlcnR5IGludCB1aUFjY2VudElu
ZGV4OiA0OyBwcm9wZXJ0eSBib29sIHVpU2hvd0hpbnRzOiB0cnVlOyBwcm9wZXJ0eSBpbnQgd2lk
dGg6IDE5MjA7IHByb3BlcnR5IGludCBoZWlnaHQ6IDEwODA7IHByb3BlcnR5IGludCBmcHM6IDYw
OyBwcm9wZXJ0eSBpbnQgYml0cmF0ZUticHM6IDIwMDAwOyBmdW5jdGlvbiBzYXZlKCkge30gfQpk
aWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAgYi9hcHAv
bW9vbmxpZ2h0b3MvdGVzdHMvdGVzdC1jcmltc29uLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NApp
bmRleCAwMDAwMDAwMC4uYzk3MzZiZTUKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0
b3MvdGVzdHMvdGVzdC1jcmltc29uLmNwcApAQCAtMCwwICsxLDI2NCBAQAorI2luY2x1ZGUgPFF0
VGVzdD4KKyNpbmNsdWRlIDxRVGVtcG9yYXJ5RGlyPgorI2luY2x1ZGUgPFFRbWxFbmdpbmU+Cisj
aW5jbHVkZSA8UVFtbENvbXBvbmVudD4KKyNpbmNsdWRlIDxRUW1sQ29udGV4dD4KKyNpbmNsdWRl
IDxRUXVpY2tTdHlsZT4KKyNpbmNsdWRlIDxRUXVpY2tXaW5kb3c+CisjaW5jbHVkZSA8UVF1aWNr
SXRlbT4KKyNpbmNsdWRlIDxRRmlsZT4KKyNpbmNsdWRlIDxRVGNwU2VydmVyPgorI2luY2x1ZGUg
PFFTc2xTb2NrZXQ+CisjaW5jbHVkZSA8UVNzbEtleT4KKyNpbmNsdWRlIDxRU3NsQ2VydGlmaWNh
dGU+CisjaW5jbHVkZSA8UUNyeXB0b2dyYXBoaWNIYXNoPgorI2luY2x1ZGUgPG1lbW9yeT4KKyNp
bmNsdWRlIDxRU3RhbmRhcmRQYXRocz4KKyNpbmNsdWRlIDxRRGlyPgorI2luY2x1ZGUgPFFGaWxl
SW5mbz4KKyNpbmNsdWRlICIuLi9jcmltc29uc3RhdHVzLmgiCisjaW5jbHVkZSAiLi4vc3lzdGVt
Y29udHJvbHMuaCIKKyNpbmNsdWRlICIuLi9lY2xpcHNlcHJvZmlsZXMuaCIKKyNpbmNsdWRlICIu
Li8uLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgiCisKK2NsYXNzIFRsc0ZpeHR1cmUgOiBw
dWJsaWMgUVRjcFNlcnZlciB7CitwdWJsaWM6CisgICAgUUJ5dGVBcnJheSBib2R5ID0gUiIoeyJj
cHVfcGVyY2VudCI6MzcuNSwicmFtX3VzZWRfYnl0ZXMiOjUwLCJyYW1fdG90YWxfYnl0ZXMiOjEw
MH0pIjsKKyAgICBpbnQgY29kZSA9IDIwMCwgcmVxdWVzdHMgPSAwOworICAgIGJvb2wgcmVzcG9u
ZCA9IHRydWU7CisgICAgUUJ5dGVBcnJheSBhdXRob3JpemF0aW9uOworICAgIFFTc2xDZXJ0aWZp
Y2F0ZSBjZXJ0OworICAgIFFTc2xLZXkga2V5OworICAgIFRsc0ZpeHR1cmUoKSB7CisgICAgICAg
IFFGaWxlIGMocUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fVEVTVF9DRVJUIikpOyBjLm9w
ZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGNlcnQgPSBRU3NsQ2VydGlmaWNhdGUoYy5yZWFkQWxs
KCkpOworICAgICAgICBRRmlsZSBrKHFFbnZpcm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1RFU1Rf
S0VZIikpOyBrLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGtleSA9IFFTc2xLZXkoay5yZWFk
QWxsKCksIFFTc2w6OlJzYSk7CisgICAgICAgIGxpc3RlbihRSG9zdEFkZHJlc3M6OkxvY2FsSG9z
dCk7CisgICAgfQorICAgIHZvaWQgaW5jb21pbmdDb25uZWN0aW9uKHFpbnRwdHIgZGVzY3JpcHRv
cikgb3ZlcnJpZGUgeworICAgICAgICBhdXRvIHNvY2tldCA9IG5ldyBRU3NsU29ja2V0KHRoaXMp
OworICAgICAgICBzb2NrZXQtPnNldExvY2FsQ2VydGlmaWNhdGUoY2VydCk7IHNvY2tldC0+c2V0
UHJpdmF0ZUtleShrZXkpOyBzb2NrZXQtPnNldFBlZXJWZXJpZnlNb2RlKFFTc2xTb2NrZXQ6OlZl
cmlmeU5vbmUpOworICAgICAgICBzb2NrZXQtPnNldFNvY2tldERlc2NyaXB0b3IoZGVzY3JpcHRv
cik7CisgICAgICAgIGF1dG8gaW5wdXQgPSBzdGQ6Om1ha2Vfc2hhcmVkPFFCeXRlQXJyYXk+KCk7
CisgICAgICAgIGNvbm5lY3Qoc29ja2V0LCAmUVNzbFNvY2tldDo6cmVhZHlSZWFkLCB0aGlzLCBb
dGhpcywgc29ja2V0LCBpbnB1dF0geworICAgICAgICAgICAgaW5wdXQtPmFwcGVuZChzb2NrZXQt
PnJlYWRBbGwoKSk7CisgICAgICAgICAgICBpZiAoIWlucHV0LT5jb250YWlucygiXHJcblxyXG4i
KSkgcmV0dXJuOworICAgICAgICAgICAgKytyZXF1ZXN0czsgYXV0aG9yaXphdGlvbiA9ICppbnB1
dDsKKyAgICAgICAgICAgIGlmIChyZXNwb25kKSB7CisgICAgICAgICAgICAgICAgUUJ5dGVBcnJh
eSBoZWFkZXIgPSAiSFRUUC8xLjEgIiArIFFCeXRlQXJyYXk6Om51bWJlcihjb2RlKSArICIgRml4
dHVyZVxyXG5Db250ZW50LVR5cGU6IGFwcGxpY2F0aW9uL2pzb25cclxuQ29ubmVjdGlvbjogY2xv
c2VcclxuQ29udGVudC1MZW5ndGg6ICIgKyBRQnl0ZUFycmF5OjpudW1iZXIoYm9keS5zaXplKCkp
ICsgIlxyXG4iOworICAgICAgICAgICAgICAgIGlmIChjb2RlID09IDMwMikgaGVhZGVyICs9ICJM
b2NhdGlvbjogaHR0cHM6Ly8xMjcuMC4wLjI6MTIzNDUvXHJcbiI7CisgICAgICAgICAgICAgICAg
c29ja2V0LT53cml0ZShoZWFkZXIgKyAiXHJcbiIgKyBib2R5KTsgc29ja2V0LT5kaXNjb25uZWN0
RnJvbUhvc3QoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGlucHV0LT5jbGVhcigpOwor
ICAgICAgICB9KTsKKyAgICAgICAgY29ubmVjdChzb2NrZXQsICZRU3NsU29ja2V0OjpkaXNjb25u
ZWN0ZWQsIHNvY2tldCwgJlFPYmplY3Q6OmRlbGV0ZUxhdGVyKTsKKyAgICAgICAgc29ja2V0LT5z
dGFydFNlcnZlckVuY3J5cHRpb24oKTsKKyAgICB9Cit9OworCitjbGFzcyBDcmltc29uVGVzdCA6
IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorcHJpdmF0ZSBzbG90czoKKyAgICB2b2lk
IGluaXRUZXN0Q2FzZSgpIHsKKyAgICAgICAgUUNvcmVBcHBsaWNhdGlvbjo6c2V0T3JnYW5pemF0
aW9uTmFtZSgiTW9vbmxpZ2h0LU9TIFRlc3QiKTsKKyAgICAgICAgUUNvcmVBcHBsaWNhdGlvbjo6
c2V0QXBwbGljYXRpb25OYW1lKCJFY2xpcHNlRml4dHVyZSIpOworICAgICAgICBRU2V0dGluZ3M6
OnNldERlZmF1bHRGb3JtYXQoUVNldHRpbmdzOjpJbmlGb3JtYXQpOworICAgIH0KKyAgICB2b2lk
IGhvc3RQcm9maWxlc1JlbWFpbklzb2xhdGVkKCkgeworICAgICAgICBFY2xpcHNlUHJvZmlsZXMg
cHJvZmlsZXM7CisgICAgICAgIFFWYXJpYW50TWFwIHZhbHVlc3t7IndpZHRoIiwxMjgwfSx7Imhl
aWdodCIsODAwfSx7ImZwcyIsNjB9LHsiYml0cmF0ZUticHMiLDE1MDAwfX07CisgICAgICAgIFFW
RVJJRlkocHJvZmlsZXMuc2F2ZSgiZml4dHVyZS1ob3N0LWEiLCJEZXNrdG9wIix2YWx1ZXMpKTsK
KyAgICAgICAgUUNPTVBBUkUocHJvZmlsZXMubG9hZCgiZml4dHVyZS1ob3N0LWEiLCJEZXNrdG9w
IiksdmFsdWVzKTsKKyAgICAgICAgUVZFUklGWShwcm9maWxlcy5sb2FkKCJmaXh0dXJlLWhvc3Qt
YiIsIkRlc2t0b3AiKS5pc0VtcHR5KCkpOworICAgICAgICBRVkVSSUZZKHByb2ZpbGVzLm5hbWVz
KCJmaXh0dXJlLWhvc3QtYSIpLmNvbnRhaW5zKCJEZXNrdG9wIikpOworICAgICAgICBRVkVSSUZZ
KCFwcm9maWxlcy5yZW1vdmUoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIsZmFsc2UpKTsKKyAg
ICAgICAgdmFsdWVzWyJmcHMiXSA9IDA7IFFWRVJJRlkoIXByb2ZpbGVzLnNhdmUoImZpeHR1cmUt
aG9zdC1hIiwiQmFkIix2YWx1ZXMpKTsKKyAgICAgICAgUVZFUklGWShwcm9maWxlcy5yZW1vdmUo
ImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIsdHJ1ZSkpOworICAgICAgICBRVkVSSUZZKHByb2Zp
bGVzLmxvYWQoImZpeHR1cmUtaG9zdC1hIiwiRGVza3RvcCIpLmlzRW1wdHkoKSk7CisgICAgfQor
ICAgIHZvaWQgc3lzdGVtQ29udHJvbHNQcml2YXRlUGlwZSgpIHsKKyAgICAgICAgUVRlbXBvcmFy
eURpciBkaXI7IFFWRVJJRlkoZGlyLmlzVmFsaWQoKSk7CisgICAgICAgIFFGaWxlIHNjcmlwdChk
aXIuZmlsZVBhdGgoImZpeHR1cmUucHkiKSk7IFFWRVJJRlkoc2NyaXB0Lm9wZW4oUUlPRGV2aWNl
OjpXcml0ZU9ubHkpKTsKKyAgICAgICAgc2NyaXB0LndyaXRlKFIiUFkoaW1wb3J0IGpzb24sc3lz
Citmb3IgbGluZSBpbiBzeXMuc3RkaW46CisgICAgdmFsdWU9anNvbi5sb2FkcyhsaW5lKQorICAg
IGFjdGlvbj12YWx1ZVsnYWN0aW9uJ10KKyAgICBpZiBhY3Rpb249PSd3aWZpLWNvbm5lY3QnOgor
ICAgICAgICBwcmludChqc29uLmR1bXBzKHsncHJvbXB0JzonV2ktRmkgcGFzc3dvcmQnfSksZmx1
c2g9VHJ1ZSkKKyAgICAgICAgcmVwbHk9anNvbi5sb2FkcyhzeXMuc3RkaW4ucmVhZGxpbmUoKSkK
KyAgICAgICAgYXNzZXJ0IHJlcGx5PT17J2FjdGlvbic6J2Fuc3dlcicsJ3ZhbHVlJzonc2VjcmV0
LXZhbHVlJ30KKyAgICBwcmludChqc29uLmR1bXBzKHsnaXRlbXMnOlt7J2lkJzond2xhbjAvQUE6
QkI6Q0M6REQ6RUU6RkYnLCduYW1lJzonPGI+UGxhaW4gU1NJRDwvYj4nLCdkZXRhaWwnOic4MCUg
V1BBMicsJ2Nvbm5lY3RlZCc6YWN0aW9uPT0nd2lmaS1jb25uZWN0J31dLCdzdGF0dXMnOidSZWFk
eScsJ2RvbmUnOlRydWV9KSxmbHVzaD1UcnVlKQorKVBZIik7IHNjcmlwdC5jbG9zZSgpOworICAg
ICAgICBxcHV0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIsIHNjcmlwdC5maWxlTmFt
ZSgpLnRvVXRmOCgpKTsKKyAgICAgICAgU3lzdGVtQ29udHJvbHMgY29udHJvbHM7IGNvbnRyb2xz
Lm9wZW4oIndpZmkiKTsKKyAgICAgICAgUVRSWV9DT01QQVJFKGNvbnRyb2xzLml0ZW1zKCkuc2l6
ZSgpLCAxKTsgUVZFUklGWSghY29udHJvbHMuYnVzeSgpKTsKKyAgICAgICAgY29udHJvbHMucmVx
dWVzdCgiYnQtZm9yZ2V0IiwgImludmFsaWQiLCB0cnVlKTsgUVZFUklGWSghY29udHJvbHMuYnVz
eSgpKTsKKyAgICAgICAgY29udHJvbHMucmVxdWVzdCgid2lmaS1jb25uZWN0IiwgIndsYW4wL0FB
OkJCOkNDOkREOkVFOkZGIik7CisgICAgICAgIFFUUllfVkVSSUZZKCFjb250cm9scy5wcm9tcHQo
KS5pc0VtcHR5KCkpOyBRVkVSSUZZKGNvbnRyb2xzLmJ1c3koKSk7CisgICAgICAgIGNvbnRyb2xz
LmFuc3dlcigic2VjcmV0LXZhbHVlIik7IFFUUllfVkVSSUZZKCFjb250cm9scy5idXN5KCkpOwor
ICAgICAgICBRVkVSSUZZKGNvbnRyb2xzLnByb21wdCgpLmlzRW1wdHkoKSk7IFFDT01QQVJFKGNv
bnRyb2xzLnN0YXR1cygpLCBRU3RyaW5nKCJSZWFkeSIpKTsKKyAgICAgICAgUVZFUklGWShjb250
cm9scy5pdGVtcygpLmZpcnN0KCkudG9NYXAoKS52YWx1ZSgiY29ubmVjdGVkIikudG9Cb29sKCkp
OworICAgICAgICBjb250cm9scy5jbG9zZSgpOyBRVkVSSUZZKCFjb250cm9scy5idXN5KCkpOwor
ICAgICAgICBxdW5zZXRlbnYoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIik7CisgICAgfQor
ICAgIHZvaWQgbWFuYWdlZFVwZGF0ZXJDYW5ub3RSZXBsYWNlQ3VzdG9taXplZENsaWVudCgpIHsK
KyAgICAgICAgUVRlbXBvcmFyeURpciBkaXI7IFFWRVJJRlkoZGlyLmlzVmFsaWQoKSk7CisgICAg
ICAgIGNvbnN0IFFTdHJpbmcgaW1hZ2UgPSBkaXIuZmlsZVBhdGgoImN1c3RvbS5BcHBJbWFnZSIp
OworICAgICAgICBRRmlsZSBmKGltYWdlKTsgUVZFUklGWShmLm9wZW4oUUlPRGV2aWNlOjpXcml0
ZU9ubHkpKTsgZi53cml0ZSgiY3VzdG9taXplZCBjbGllbnQiKTsgZi5jbG9zZSgpOworICAgICAg
ICBjb25zdCBRQnl0ZUFycmF5IG9sZCA9IHFnZXRlbnYoIkFQUElNQUdFIik7IGNvbnN0IGJvb2wg
aGFkID0gcUVudmlyb25tZW50VmFyaWFibGVJc1NldCgiQVBQSU1BR0UiKTsKKyAgICAgICAgcXB1
dGVudigiQVBQSU1BR0UiLCBpbWFnZS50b1V0ZjgoKSk7CisgICAgICAgIEF1dG9VcGRhdGVDaGVj
a2VyIGNoZWNrZXI7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5vc01hbmFnZWQoKSk7IFFWRVJJ
RlkoIWNoZWNrZXIuY2FuSW5zdGFsbFVwZGF0ZXMoKSk7CisgICAgICAgIFFTaWduYWxTcHkgY29t
cGxldGVkKCZjaGVja2VyLCAmQXV0b1VwZGF0ZUNoZWNrZXI6OmNoZWNrQ29tcGxldGVkKTsKKyAg
ICAgICAgUVNpZ25hbFNweSBmYWlsZWQoJmNoZWNrZXIsICZBdXRvVXBkYXRlQ2hlY2tlcjo6aW5z
dGFsbEZhaWxlZCk7CisgICAgICAgIGNoZWNrZXIuc3RhcnQoKTsgY2hlY2tlci5jaGVja05vdygp
OyBjaGVja2VyLmNoYW5uZWxDaGFuZ2VkKCk7IGNoZWNrZXIuaW5zdGFsbCgpOworICAgICAgICBR
Q09NUEFSRShjb21wbGV0ZWQuY291bnQoKSwgMyk7IFFDT01QQVJFKGZhaWxlZC5jb3VudCgpLCAx
KTsKKyAgICAgICAgUVZFUklGWSghY2hlY2tlci5jaGVja2luZygpKTsgUVZFUklGWSghY2hlY2tl
ci5pbnN0YWxsaW5nKCkpOworICAgICAgICBRVkVSSUZZKCFjaGVja2VyLmNhbkluc3RhbGwoKSk7
IFFWRVJJRlkoIWNoZWNrZXIudXBkYXRlQXZhaWxhYmxlKCkpOyBRVkVSSUZZKCFjaGVja2VyLm9m
ZmVyQXZhaWxhYmxlKCkpOworICAgICAgICBRQ09NUEFSRShjaGVja2VyLnJlbGVhc2VVcmwoKSwg
UVN0cmluZygiaHR0cHM6Ly9naXRodWIuY29tL3RoM2QzY2szci9Nb29ubGlnaHQtT1MvcmVsZWFz
ZXMiKSk7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5jdXJyZW50VmVyc2lvbigpLmNvbnRhaW5z
KCJNb29ubGlnaHQtT1MgY3VzdG9taXplZCIpKTsKKyAgICAgICAgUVZFUklGWShmLm9wZW4oUUlP
RGV2aWNlOjpSZWFkT25seSkpOyBRQ09NUEFSRShmLnJlYWRBbGwoKSwgUUJ5dGVBcnJheSgiY3Vz
dG9taXplZCBjbGllbnQiKSk7IGYuY2xvc2UoKTsKKyAgICAgICAgUUNPTVBBUkUoUURpcihkaXIu
cGF0aCgpKS5lbnRyeUxpc3QoUURpcjo6RmlsZXMpLCBRU3RyaW5nTGlzdHsiY3VzdG9tLkFwcElt
YWdlIn0pOworICAgICAgICBpZiAoaGFkKSBxcHV0ZW52KCJBUFBJTUFHRSIsIG9sZCk7IGVsc2Ug
cXVuc2V0ZW52KCJBUFBJTUFHRSIpOworICAgICAgICBRQ09NUEFSRShBdXRvVXBkYXRlQ2hlY2tl
cjo6Y29tcGFyZVNlbWFudGljVmVyc2lvbnMoIjAuNS4wIiwgIjAuNC45IiksIDEpOworICAgIH0K
KyAgICB2b2lkIGVuZHBvaW50VmFsaWRhdGlvbigpIHsKKyAgICAgICAgUVZFUklGWShDcmltc29u
U3RhdHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovLzE5Mi4xNjguMS4xMDo0Nzk5MCIpKTsKKyAg
ICAgICAgUVZFUklGWShDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovL1tmZDAw
OjoxXTo0Nzk5MC8iKSk7CisgICAgICAgIGZvciAoYXV0byBiYWQgOiB7Imh0dHA6Ly9ob3N0Iiwg
Imh0dHBzOi8vdXNlcjpzZWNyZXRAaG9zdCIsICJodHRwczovL2hvc3QvYXBpIiwgImh0dHBzOi8v
aG9zdC8/dG9rZW49c2VjcmV0IiwgImZpbGU6Ly8vZXRjL3Bhc3N3ZCIsICJodHRwczovL2hvc3Qv
I2ZyYWdtZW50In0pCisgICAgICAgICAgICBRVkVSSUZZKCFDcmltc29uU3RhdHVzOjp2YWxpZEVu
ZHBvaW50KGJhZCkpOworICAgIH0KKyAgICB2b2lkIG1pc3NpbmdBbmRJbnZhbGlkTWV0cmljcygp
IHsKKyAgICAgICAgUVN0cmluZyBlcnJvcjsKKyAgICAgICAgUVZFUklGWShDcmltc29uU3RhdHVz
OjpwYXJzZVN0YXRzKCJub3QganNvbiIsICZlcnJvcikuaXNFbXB0eSgpKTsgUVZFUklGWSghZXJy
b3IuaXNFbXB0eSgpKTsKKyAgICAgICAgYXV0byBzID0gQ3JpbXNvblN0YXR1czo6cGFyc2VTdGF0
cyhSIih7ImNwdV9wZXJjZW50Ijo0Mi41LCJjcHVfdGVtcF9jIjotMSwiZ3B1X3BlcmNlbnQiOm51
bGwsInJhbV90b3RhbF9ieXRlcyI6MCwicmFtX3BlcmNlbnQiOjAsInZyYW1fdG90YWxfYnl0ZXMi
OjEwMCwidnJhbV91c2VkX2J5dGVzIjoxMjB9KSIsICZlcnJvcik7CisgICAgICAgIFFWRVJJRlko
ZXJyb3IuaXNFbXB0eSgpKTsgUUNPTVBBUkUocy52YWx1ZSgiY3B1X3BlcmNlbnQiKS50b0RvdWJs
ZSgpLCA0Mi41KTsKKyAgICAgICAgUVZFUklGWSghcy5jb250YWlucygiY3B1X3RlbXBfYyIpKTsg
UVZFUklGWSghcy5jb250YWlucygiZ3B1X3BlcmNlbnQiKSk7IFFWRVJJRlkoIXMuY29udGFpbnMo
InJhbV9wZXJjZW50IikpOworICAgICAgICBRQ09NUEFSRShzLnZhbHVlKCJ2cmFtX3BlcmNlbnQi
KS50b0RvdWJsZSgpLCAxMDAuMCk7CisgICAgICAgIGF1dG8gaW52YWxpZCA9IENyaW1zb25TdGF0
dXM6OnBhcnNlU3RhdHMoUiIoeyJjcHVfcGVyY2VudCI6MTAxLCJncHVfcGVyY2VudCI6IjAifSki
LCAmZXJyb3IpOworICAgICAgICBRVkVSSUZZKGludmFsaWQuaXNFbXB0eSgpKTsgUVZFUklGWShl
cnJvci5pc0VtcHR5KCkpOworICAgICAgICBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKFFCeXRl
QXJyYXkoNjU1MzcsICdhJyksICZlcnJvcik7IFFWRVJJRlkoIWVycm9yLmlzRW1wdHkoKSk7Cisg
ICAgICAgIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJlcnJvciI6InVuc3VwcG9ydGVk
In0pIiwgJmVycm9yKTsgUVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsKKyAgICB9CisgICAgdm9p
ZCBsb2NhbEhhcmR3YXJlRml4dHVyZSgpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciB0ZW1wOyBR
VkVSSUZZKHRlbXAuaXNWYWxpZCgpKTsKKyAgICAgICAgYXV0byB3cml0ZSA9IFsmXShRU3RyaW5n
IHAsIFFCeXRlQXJyYXkgdmFsdWUpIHsgUURpcigpLm1rcGF0aChRRmlsZUluZm8odGVtcC5wYXRo
KCkrcCkuYWJzb2x1dGVQYXRoKCkpOyBRRmlsZSBmKHRlbXAucGF0aCgpK3ApOyBRVkVSSUZZKGYu
b3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOyBmLndyaXRlKHZhbHVlKTsgfTsKKyAgICAgICAg
d3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC90eXBlIiwgIkJhdHRlcnkiKTsgd3JpdGUo
Ii9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9jYXBhY2l0eSIsICI3MyIpOyB3cml0ZSgiL2NsYXNz
L3Bvd2VyX3N1cHBseS9CQVQwL3N0YXR1cyIsICJDaGFyZ2luZyIpOworICAgICAgICB3cml0ZSgi
L2NsYXNzL25ldC93bGFuMC9vcGVyc3RhdGUiLCAidXAiKTsgd3JpdGUoIi9jbGFzcy9uZXQvbG8v
b3BlcnN0YXRlIiwgInVwIik7CisgICAgICAgIGF1dG8gbG9jYWwgPSBDcmltc29uU3RhdHVzOjpy
ZWFkTG9jYWwodGVtcC5wYXRoKCkpOyBRQ09NUEFSRShsb2NhbC52YWx1ZSgiYmF0dGVyeVBlcmNl
bnQiKS50b0ludCgpLCA3Myk7IFFDT01QQVJFKGxvY2FsLnZhbHVlKCJiYXR0ZXJ5U3RhdGUiKS50
b1N0cmluZygpLCBRU3RyaW5nKCJDaGFyZ2luZyIpKTsKKyAgICAgICAgUUNPTVBBUkUobG9jYWwu
dmFsdWUoIm5ldHdvcmsiKS50b1N0cmluZygpLCBRU3RyaW5nKCJ3bGFuMCIpKTsgUVZFUklGWShs
b2NhbC52YWx1ZSgiY29ubmVjdGVkIikudG9Cb29sKCkpOworICAgICAgICB3cml0ZSgiL2NsYXNz
L3Bvd2VyX3N1cHBseS9CQVQwL2NhcGFjaXR5IiwgIjEwMSIpOyBRQ09NUEFSRShDcmltc29uU3Rh
dHVzOjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpLnZhbHVlKCJiYXR0ZXJ5UGVyY2VudCIpLnRvSW50
KCksIC0xKTsKKyAgICB9CisgICAgdm9pZCBwcml2YXRlU2V0dGluZ3NBbmROb0Nyb3NzSG9zdENy
ZWRlbnRpYWxzKCkgeworICAgICAgICBRU3RhbmRhcmRQYXRoczo6c2V0VGVzdE1vZGVFbmFibGVk
KHRydWUpOworICAgICAgICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVjdEhvc3Qo
InRlc3QtYSIsICJodHRwczovLzEyNy4wLjAuMTo0Nzk5MCIpOworICAgICAgICBRVkVSSUZZKHN0
YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4xOjQ3OTkwIiwgImZpeHR1cmUtdG9rZW4i
LCAiIikpOyBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmVkKCkpOworICAgICAgICBhdXRvIHBhdGgg
PSBRU3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRhcmRQYXRoczo6QXBwQ29u
ZmlnTG9jYXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpzb24iOworICAgICAgICBRVkVSSUZZKChR
RmlsZTo6cGVybWlzc2lvbnMocGF0aCkgJiAoUUZpbGVEZXZpY2U6OlJlYWRHcm91cCB8IFFGaWxl
RGV2aWNlOjpSZWFkT3RoZXIgfCBRRmlsZURldmljZTo6V3JpdGVHcm91cCB8IFFGaWxlRGV2aWNl
OjpXcml0ZU90aGVyKSkgPT0gMCk7CisgICAgICAgIHN0YXR1cy5zZWxlY3RIb3N0KCJ0ZXN0LWIi
LCAiaHR0cHM6Ly8xMjcuMC4wLjI6NDc5OTAiKTsgUVZFUklGWSghc3RhdHVzLmNvbmZpZ3VyZWQo
KSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4y
OjQ3OTkwIiwgIiIsICIiKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0
dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIiwgImZpeHR1cmUtdG9rZW4iLCAiaW52YWxpZC1waW4iKSk7
CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4yOjQ3
OTkwIiwgInRva2VuXG5pbmplY3Rpb24iLCAiIikpOworICAgICAgICBRRmlsZTo6cmVtb3ZlKHBh
dGgpOworICAgIH0KKyAgICB2b2lkIHRsc0F1dGhlbnRpY2F0aW9uQW5kVmlzaWJpbGl0eSgpIHsK
KyAgICAgICAgVGxzRml4dHVyZSBzZXJ2ZXI7IFFWRVJJRlkoc2VydmVyLmlzTGlzdGVuaW5nKCkp
OyBRVkVSSUZZKCFzZXJ2ZXIuY2VydC5pc051bGwoKSk7CisgICAgICAgIFFTdHJpbmcgdXJsID0g
Imh0dHBzOi8vMTI3LjAuMC4xOiIgKyBRU3RyaW5nOjpudW1iZXIoc2VydmVyLnNlcnZlclBvcnQo
KSk7CisgICAgICAgIFFTdHJpbmcgcGluID0gUVN0cmluZzo6ZnJvbUxhdGluMShzZXJ2ZXIuY2Vy
dC5kaWdlc3QoUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpOworICAgICAgICBD
cmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVjdEhvc3QoImZpeHR1cmUtdGxzIiwgdXJs
KTsKKyAgICAgICAgUVZFUklGWShzdGF0dXMuY29uZmlndXJlKHVybCwgImZpeHR1cmUtb25seS10
b2tlbiIsICIiKSk7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAgICBRVFJZX1ZFUklG
WV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0YXR1cygpLmNvbnRhaW5zKCJmaW5nZXJwcmludCIpLCA1
MDAwKTsKKyAgICAgICAgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCAwKTsgLy8gbm8gY3JlZGVu
dGlhbHMgc2VudCBiZWZvcmUgdHJ1c3Rpbmcgc2VsZi1zaWduZWQgVExTCisgICAgICAgIFFWRVJJ
Rlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJmaXh0dXJlLW9ubHktdG9rZW4iLCBwaW4pKTsKKyAg
ICAgICAgUVRSWV9DT01QQVJFX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS52YWx1ZSgiY3B1
X3BlcmNlbnQiKS50b0RvdWJsZSgpLCAzNy41LCA1MDAwKTsKKyAgICAgICAgUVZFUklGWShzZXJ2
ZXIuYXV0aG9yaXphdGlvbi5jb250YWlucygiQXV0aG9yaXphdGlvbjogQmVhcmVyIGZpeHR1cmUt
b25seS10b2tlbiIpKTsKKyAgICAgICAgUVZFUklGWShzZXJ2ZXIuYXV0aG9yaXphdGlvbi5zdGFy
dHNXaXRoKCJHRVQgL2FwaS9ob3N0L3N0YXRzICIpKTsKKyAgICAgICAgc3RhdHVzLnNldFZpc2li
bGUoZmFsc2UpOyBpbnQgY291bnQgPSBzZXJ2ZXIucmVxdWVzdHM7IFFUZXN0OjpxV2FpdCgyMTAw
KTsgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCBjb3VudCk7CisgICAgICAgIGZvciAoaW50IGNv
ZGUgOiB7NDAxLCA0MDMsIDQwNCwgMzAyfSkgeworICAgICAgICAgICAgc2VydmVyLmNvZGUgPSBj
b2RlOyBpbnQgcHJpb3IgPSBzZXJ2ZXIucmVxdWVzdHM7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUp
OworICAgICAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHNlcnZlci5yZXF1ZXN0cyA+
IHByaW9yLCA1MDAwKTsKKyAgICAgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9VVChzdGF0
dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOworICAgICAgICAgICAgc3RhdHVzLnNldFZpc2li
bGUoZmFsc2UpOworICAgICAgICB9CisgICAgICAgIHNlcnZlci5jb2RlID0gMjAwOyBzZXJ2ZXIu
Ym9keSA9IFFCeXRlQXJyYXkoNzAwMDAsICdhJyk7IGludCBwcmlvciA9IHNlcnZlci5yZXF1ZXN0
czsgc3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElN
RU9VVChzZXJ2ZXIucmVxdWVzdHMgPiBwcmlvciwgNTAwMCk7CisgICAgICAgIFFUUllfVkVSSUZZ
X1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOyBzdGF0dXMuc2V0
VmlzaWJsZShmYWxzZSk7CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJm
aXh0dXJlLW9ubHktdG9rZW4iLCBRU3RyaW5nKDY0LCAnMCcpKSk7IHN0YXR1cy5zZXRWaXNpYmxl
KHRydWUpOworICAgICAgICBjb3VudCA9IHNlcnZlci5yZXF1ZXN0czsgUVRlc3Q6OnFXYWl0KDUw
MCk7IFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywgY291bnQpOyBRVkVSSUZZKHN0YXR1cy5zdGF0
cygpLmlzRW1wdHkoKSk7CisgICAgICAgIHN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsKKyAgICB9
CisgICAgdm9pZCBxbWxQYWxldHRlQW5kUGFuZWxzKCkgeworICAgICAgICBRU3RyaW5nIHNvdXJj
ZSA9IHFFbnZpcm9ubWVudFZhcmlhYmxlKCJWSUJFTUlTX1RFU1RfU09VUkNFIik7IFFWRVJJRlko
IXNvdXJjZS5pc0VtcHR5KCkpOworICAgICAgICBRUXVpY2tTdHlsZTo6c2V0U3R5bGUoIk1hdGVy
aWFsIik7CisgICAgICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9uVHlwZShRVXJsOjpmcm9tTG9jYWxG
aWxlKHNvdXJjZSArICIvYXBwL21vb25saWdodG9zL3Rlc3RzL1ByZWZlcmVuY2VzLnFtbCIpLCAi
U3RyZWFtaW5nUHJlZmVyZW5jZXMiLCAxLCAwLCAiU3RyZWFtaW5nUHJlZmVyZW5jZXMiKTsKKyAg
ICAgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlKFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNl
ICsgIi9hcHAvZ3VpL1ZiVG9rZW5zLnFtbCIpLCAiVmliZW1pcy5SZWRlc2lnbiIsIDEsIDAsICJW
YlRva2VucyIpOworICAgICAgICBRVGVtcG9yYXJ5RGlyIGNvbnRyb2xzRml4dHVyZTsgUVZFUklG
WShjb250cm9sc0ZpeHR1cmUuaXNWYWxpZCgpKTsKKyAgICAgICAgUUZpbGUgaGVscGVyKGNvbnRy
b2xzRml4dHVyZS5maWxlUGF0aCgiaGVscGVyLnB5IikpOyBRVkVSSUZZKGhlbHBlci5vcGVuKFFJ
T0RldmljZTo6V3JpdGVPbmx5KSk7CisgICAgICAgIGhlbHBlci53cml0ZShSIlBZKGltcG9ydCBq
c29uLHN5cworZm9yIGxpbmUgaW4gc3lzLnN0ZGluOgorICAgIHZhbHVlPWpzb24ubG9hZHMobGlu
ZSkKKyAgICBwcmludChqc29uLmR1bXBzKHsnc3RhdGUnOnsndm9sdW1lJzo1MCwnbXV0ZWQnOkZh
bHNlLCdzaW5rcyc6W3snaWQnOic0MicsJ25hbWUnOidTcGVha2VycycsJ2RlZmF1bHQnOlRydWV9
LHsnaWQnOic1NycsJ25hbWUnOidBaXJQb2RzJywnZGVmYXVsdCc6RmFsc2V9XSwnYnJpZ2h0bmVz
cyc6eydzY3JlZW4nOnsnZGV2aWNlJzonaW50ZWxfYmFja2xpZ2h0JywncGVyY2VudCc6NjB9LCdr
ZXlib2FyZCc6eydkZXZpY2UnOidzcGk6OmtiZF9iYWNrbGlnaHQnLCdwZXJjZW50JzozMH19LCdv
cyc6eydOQU1FJzonTW9vbmxpZ2h0LU9TJywnVkVSU0lPTic6JzAuMy1kZXYnLCdUQVJHRVQnOidG
aXh0dXJlIGhhcmR3YXJlJywnRkVET1JBJzonNDQnfSwna2VybmVsJzonZml4dHVyZS1rZXJuZWwn
fSwnaXRlbXMnOlt7J2lkJzonZml4dHVyZScsJ25hbWUnOidGaXh0dXJlIGRldmljZScsJ2RldGFp
bCc6J0F2YWlsYWJsZScsJ2Nvbm5lY3RlZCc6VHJ1ZX1dLCdzdGF0dXMnOidSZWFkeScsJ2RvbmUn
OlRydWV9KSxmbHVzaD1UcnVlKQorKVBZIik7IGhlbHBlci5jbG9zZSgpOworICAgICAgICBxcHV0
ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIsaGVscGVyLmZpbGVOYW1lKCkudG9VdGY4
KCkpOworICAgICAgICBRUW1sRW5naW5lIGVuZ2luZTsKKyAgICAgICAgUVFtbENvbXBvbmVudCBj
b21wb25lbnQoJmVuZ2luZSwgUVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UgKyAiL2FwcC9tb29u
bGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbCIpKTsKKyAgICAgICAgUVNjb3BlZFBvaW50ZXI8UU9i
amVjdD4gcm9vdChjb21wb25lbnQuY3JlYXRlKCkpOyBRVkVSSUZZMihyb290LCBxUHJpbnRhYmxl
KGNvbXBvbmVudC5lcnJvclN0cmluZygpKSk7CisgICAgICAgIGF1dG8gcGFuZWwgPSByb290LT5m
aW5kQ2hpbGQ8UU9iamVjdCo+KCJ0ZXN0UGFuZWwiKTsgUVZFUklGWShwYW5lbCk7CisgICAgICAg
IGF1dG8gc3RhdGUgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJ0ZXN0U3RhdGUiKTsgUVZF
UklGWShzdGF0ZSk7CisgICAgICAgIGZvciAoaW50IGkgPSAwOyBpIDwgMTY7ICsraSkgeworICAg
ICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCAi
Y2hvb3NlQWNjZW50IiwgUV9BUkcoUVZhcmlhbnQsIGkpKSk7CisgICAgICAgICAgICBRVkVSSUZZ
KHN0YXRlLT5wcm9wZXJ0eSgiYWNjZW50IikudmFsdWU8UUNvbG9yPigpLmlzVmFsaWQoKSk7Cisg
ICAgICAgICAgICBRVkVSSUZZKHN0YXRlLT5wcm9wZXJ0eSgicHJlc3NlZCIpLnZhbHVlPFFDb2xv
cj4oKS5pc1ZhbGlkKCkpOworICAgICAgICB9CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6
Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwgImNob29zZUFjY2VudCIsIFFfQVJHKFFWYXJpYW50
LCA0KSkpOworICAgICAgICBmb3IgKFFTdHJpbmcga2luZCA6IHsibmV0d29yayIsICJiYXR0ZXJ5
IiwgImhvc3QifSkgeworICAgICAgICAgICAgUVZFUklGWShwYW5lbC0+c2V0UHJvcGVydHkoImtp
bmQiLCBraW5kKSk7CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRo
b2QocGFuZWwsICJvcGVuIikpOyBRVGVzdDo6cVdhaXQoMzAwKTsKKyAgICAgICAgICAgIFFWRVJJ
RlkocGFuZWwtPnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAgICAgICAgUVN0
cmluZyBvdXQgPSBxRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJTVNPTl9TQ1JFRU5TSE9UUyIpOwor
ICAgICAgICAgICAgaWYgKCFvdXQuaXNFbXB0eSgpKSB7CisgICAgICAgICAgICAgICAgUURpcigp
Lm1rcGF0aChvdXQpOworICAgICAgICAgICAgICAgIGF1dG8gd2luZG93ID0gcW9iamVjdF9jYXN0
PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgpKTsgUVZFUklGWSh3aW5kb3cpOworICAgICAgICAg
ICAgICAgIFFWRVJJRlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQgKyAiLyIgKyBraW5k
ICsgIi5wbmciKSk7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2Jq
ZWN0OjppbnZva2VNZXRob2QocGFuZWwsICJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7Cisg
ICAgICAgIH0KKyAgICAgICAgYXV0byBjb25uZWN0aW9ucyA9IHJvb3QtPmZpbmRDaGlsZDxRT2Jq
ZWN0Kj4oImNvbm5lY3Rpb25zUGFuZWwiKTsgUVZFUklGWShjb25uZWN0aW9ucyk7CisgICAgICAg
IGZvciAoUVN0cmluZyBraW5kIDogeyJ3aWZpIiwgImJ0In0pIHsKKyAgICAgICAgICAgIHJvb3Qt
PnNldFByb3BlcnR5KCJ3aWR0aCIsIDEwMjQpOyByb290LT5zZXRQcm9wZXJ0eSgiaGVpZ2h0Iiwg
NjQwKTsKKyAgICAgICAgICAgIFFWRVJJRlkoY29ubmVjdGlvbnMtPnNldFByb3BlcnR5KCJraW5k
Iiwga2luZCkpOworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9k
KGNvbm5lY3Rpb25zLCAib3BlbiIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICBR
VkVSSUZZKGNvbm5lY3Rpb25zLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsKKyAgICAg
ICAgICAgIFFWRVJJRlkoY29ubmVjdGlvbnMtPnByb3BlcnR5KCJ3aWR0aCIpLnRvSW50KCkgPD0g
OTkyKTsKKyAgICAgICAgICAgIFFTdHJpbmcgb3V0ID0gcUVudmlyb25tZW50VmFyaWFibGUoIkNS
SU1TT05fU0NSRUVOU0hPVFMiKTsKKyAgICAgICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgewor
ICAgICAgICAgICAgICAgIGF1dG8gd2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+
KHJvb3QuZGF0YSgpKTsgUVZFUklGWSh3aW5kb3cpOworICAgICAgICAgICAgICAgIFFWRVJJRlko
d2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQgKyAiLyIgKyBraW5kICsgIi1zZWxlY3Rvci5w
bmciKSk7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0Ojpp
bnZva2VNZXRob2QoY29ubmVjdGlvbnMsICJjbG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7Cisg
ICAgICAgIH0KKyAgICAgICAgUVFtbENvbXBvbmVudCBhY3Rpb25Db21wb25lbnQoJmVuZ2luZSxR
VXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSsiL2FwcC9ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5x
bWwiKSk7CisgICAgICAgIFFTY29wZWRQb2ludGVyPFFPYmplY3Q+IGFjdGlvbihhY3Rpb25Db21w
b25lbnQuY3JlYXRlKCkpOyBRVkVSSUZZMihhY3Rpb24scVByaW50YWJsZShhY3Rpb25Db21wb25l
bnQuZXJyb3JTdHJpbmcoKSkpOworICAgICAgICBhdXRvIGFjdGlvbkl0ZW0gPSBxb2JqZWN0X2Nh
c3Q8UVF1aWNrSXRlbSo+KGFjdGlvbi5kYXRhKCkpOyBRVkVSSUZZKGFjdGlvbkl0ZW0pOworICAg
ICAgICBhdXRvIGFjdGlvbldpbmRvdyA9IHFvYmplY3RfY2FzdDxRUXVpY2tXaW5kb3cqPihyb290
LmRhdGEoKSk7IFFWRVJJRlkoYWN0aW9uV2luZG93KTsKKyAgICAgICAgYWN0aW9uSXRlbS0+c2V0
UGFyZW50SXRlbShhY3Rpb25XaW5kb3ctPmNvbnRlbnRJdGVtKCkpOyBhY3Rpb25JdGVtLT5mb3Jj
ZUFjdGl2ZUZvY3VzKCk7CisgICAgICAgIFFTaWduYWxTcHkgYWN0aXZhdGVkKGFjdGlvbi5kYXRh
KCksU0lHTkFMKGNsaWNrZWQoKSkpOworICAgICAgICBRVGVzdDo6a2V5Q2xpY2soYWN0aW9uV2lu
ZG93LFF0OjpLZXlfUmV0dXJuKTsgUUNPTVBBUkUoYWN0aXZhdGVkLmNvdW50KCksMSk7CisgICAg
ICAgIGFjdGlvbkl0ZW0tPnNldFZpc2libGUoZmFsc2UpOworICAgICAgICBhdXRvIGNlbnRlciA9
IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oImNvbnRyb2xDZW50ZXIiKTsgUVZFUklGWShjZW50
ZXIpOworICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY2VudGVyLCJv
cGVuIikpOyBRVGVzdDo6cVdhaXQoNTAwKTsKKyAgICAgICAgUVZFUklGWShjZW50ZXItPnByb3Bl
cnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAgICBRU3RyaW5nIG91dCA9IHFFbnZpcm9u
bWVudFZhcmlhYmxlKCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgIGF1dG8gd2luZG93
ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgpKTsgUVZFUklGWSh3aW5k
b3cpOworICAgICAgICBpZiAoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlkod2luZG93LT5ncmFiV2lu
ZG93KCkuc2F2ZShvdXQrIi9lY2xpcHNlLWNvbnRyb2wtY2VudGVyLnBuZyIpKTsKKyAgICAgICAg
UVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNlbnRlciwiY2xvc2UiKSk7IFFUZXN0
OjpxV2FpdCgzMDApOworICAgICAgICBhdXRvIGFib3V0ID0gcm9vdC0+ZmluZENoaWxkPFFPYmpl
Y3QqPigiYWJvdXRFY2xpcHNlIik7IFFWRVJJRlkoYWJvdXQpOworICAgICAgICBhYm91dC0+c2V0
UHJvcGVydHkoImluZm8iLCBRVmFyaWFudE1hcHt7Im9zIixRVmFyaWFudE1hcHt7Ik5BTUUiLCJN
b29ubGlnaHQtT1MifSx7IlZFUlNJT04iLCIwLjMtZGV2In0seyJUQVJHRVQiLCJGaXh0dXJlIGhh
cmR3YXJlIn0seyJGRURPUkEiLCI0NCJ9fX0seyJrZXJuZWwiLCJmaXh0dXJlLWtlcm5lbCJ9fSk7
CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChhYm91dCwib3BlbiIp
KTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgIFFWRVJJRlkoYWJvdXQtPnByb3BlcnR5KCJ2
aXNpYmxlIikudG9Cb29sKCkpOworICAgICAgICBpZiAoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlko
d2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShvdXQrIi9lY2xpcHNlLWFib3V0LnBuZyIpKTsKKyAg
ICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGFib3V0LCJjbG9zZSIpKTsK
KyAgICAgICAgcXVuc2V0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIpOworICAgIH0K
K307CitRVEVTVF9NQUlOKENyaW1zb25UZXN0KQorI2luY2x1ZGUgInRlc3QtY3JpbXNvbi5tb2Mi
CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvdGVzdC1jcmltc29uLnBybyBiL2Fw
cC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24ucHJvCm5ldyBmaWxlIG1vZGUgMTAwNjQ0
CmluZGV4IDAwMDAwMDAwLi42ZmIxNzRiYwotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGln
aHRvcy90ZXN0cy90ZXN0LWNyaW1zb24ucHJvCkBAIC0wLDAgKzEsMTUgQEAKK1FUICs9IGNvcmUg
Z3VpIHF1aWNrIG5ldHdvcmsgcXVpY2tjb250cm9sczIgdGVzdGxpYiBzdmcKK0NPTkZJRyArPSBj
KysxNyB0ZXN0Y2FzZQorVEFSR0VUID0gdGVzdC1jcmltc29uCitTT1VSQ0VTICs9IHRlc3QtY3Jp
bXNvbi5jcHAgLi4vY3JpbXNvbnN0YXR1cy5jcHAKK0hFQURFUlMgKz0gLi4vY3JpbXNvbnN0YXR1
cy5oCisKK1NPVVJDRVMgKz0gLi4vbWFuYWdlZHVwZGF0ZXMuY3BwCitIRUFERVJTICs9IC4uLy4u
L2JhY2tlbmQvYXV0b3VwZGF0ZWNoZWNrZXIuaAorCitERUZJTkVTICs9IE1PT05MSUdIVF9DT05U
Uk9MU19URVNUCitTT1VSQ0VTICs9IC4uL3N5c3RlbWNvbnRyb2xzLmNwcAorSEVBREVSUyArPSAu
Li9zeXN0ZW1jb250cm9scy5oCisKK1NPVVJDRVMgKz0gLi4vZWNsaXBzZXByb2ZpbGVzLmNwcAor
SEVBREVSUyArPSAuLi9lY2xpcHNlcHJvZmlsZXMuaApkaWZmIC0tZ2l0IGEvYXBwL3FtbC5xcmMg
Yi9hcHAvcW1sLnFyYwppbmRleCBhM2MxMWRkNy4uNzE0YzY1MWYgMTAwNjQ0Ci0tLSBhL2FwcC9x
bWwucXJjCisrKyBiL2FwcC9xbWwucXJjCkBAIC0xNCw2ICsxNCwxMSBAQAogICAgICAgICA8Zmls
ZT5ndWkvVmJIb3N0Q2FyZC5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9WYldlbGNvbWVT
aGVldC5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9tYWluLnFtbDwvZmlsZT4KKyAgICAg
ICAgPGZpbGU+Z3VpL0NyaW1zb25TdGF0dXNEaWFsb2cucW1sPC9maWxlPgorICAgICAgICA8Zmls
ZT5ndWkvU3lzdGVtQ29ubmVjdGlvbnNEaWFsb2cucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5n
dWkvRWNsaXBzZUNvbnRyb2xDZW50ZXIucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNs
aXBzZUFjdGlvbkJ1dHRvbi5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9FY2xpcHNlQWJv
dXREaWFsb2cucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvUGNWaWV3LnFtbDwvZmlsZT4K
ICAgICAgICAgPGZpbGU+Z3VpL0FwcFZpZXcucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkv
U2V0dGluZ3NWaWV3LnFtbDwvZmlsZT4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1iYXR0
ZXJ5LnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1iYXR0ZXJ5LnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwMC4uMzc1MzU2NmEKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2Ny
aW1zb24tYmF0dGVyeS5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53
My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0
Ij48ZyBmaWxsPSJub25lIiBzdHJva2U9IiNFQ0VFRjEiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJv
a2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxyZWN0IHg9IjIiIHk9
IjYiIHdpZHRoPSIxOCIgaGVpZ2h0PSIxMiIgcng9IjIiLz48cGF0aCBkPSJNMjIgMTB2NE02IDEw
djRNMTAgMTB2NE0xNCAxMHY0Ii8+PC9nPjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9jcmlt
c29uLWJsdWV0b290aC5zdmcgYi9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZwpuZXcgZmls
ZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uY2VmOWFiODYKLS0tIC9kZXYvbnVsbAorKysg
Yi9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5z
PSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3
Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik03IDdsMTAgMTAtNSA0VjNsNSA0TDcgMTciIGZpbGw9
Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0i
cm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9y
ZXMvY3JpbXNvbi1ob3N0LnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1ob3N0LnN2ZwpuZXcgZmlsZSBt
b2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uZDFkNTliMGMKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvcmVzL2NyaW1zb24taG9zdC5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDov
L3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAw
IDI0IDI0Ij48ZyBmaWxsPSJub25lIiBzdHJva2U9IiNFQ0VFRjEiIHN0cm9rZS13aWR0aD0iMS44
IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxyZWN0IHg9
IjMiIHk9IjMiIHdpZHRoPSIxOCIgaGVpZ2h0PSIxNCIgcng9IjIiLz48cGF0aCBkPSJNOCAyMWg4
TTEyIDE3djRNNiAxMGgzbDItNCAzIDggMi00aDIiLz48L2c+PC9zdmc+CmRpZmYgLS1naXQgYS9h
cHAvcmVzL2NyaW1zb24tbmV0d29yay5zdmcgYi9hcHAvcmVzL2NyaW1zb24tbmV0d29yay5zdmcK
bmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLmIyYTEwM2E2Ci0tLSAvZGV2L251
bGwKKysrIGIvYXBwL3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcg
eG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQi
IHZpZXdCb3g9IjAgMCAyNCAyNCI+PGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRUNFRUYxIiBzdHJv
a2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJv
dW5kIj48cGF0aCBkPSJNMyA4YTE0IDE0IDAgMCAxIDE4IDBNNiAxMmE5IDkgMCAwIDEgMTIgME05
IDE2YTQgNCAwIDAgMSA2IDAiLz48Y2lyY2xlIGN4PSIxMiIgY3k9IjIwIiByPSIxIi8+PC9nPjwv
c3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZyBiL2FwcC9yZXMv
ZWNsaXBzZS1jb250cm9scy5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAu
LjY1M2RiZDgyCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2
ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIg
d2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik00IDZo
MTZNNCAxMmgxNk00IDE4aDE2TTggM3Y2TTE2IDl2Nk0xMCAxNXY2IiBmaWxsPSJub25lIiBzdHJv
a2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJv
a2UtbGluZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2VjbGlwc2Ut
aWNvbi5zdmcgYi9hcHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQK
aW5kZXggMDAwMDAwMDAuLjcxMTVjMzM2Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9lY2xp
cHNlLWljb24uc3ZnCkBAIC0wLDAgKzEsNyBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5v
cmcvMjAwMC9zdmciIHdpZHRoPSI1MTIiIGhlaWdodD0iNTEyIiB2aWV3Qm94PSIwIDAgNTEyIDUx
MiI+Cis8ZGVmcz48bGluZWFyR3JhZGllbnQgaWQ9InJpbSIgeDE9IjAiIHkxPSIwIiB4Mj0iMSIg
eTI9IjEiPjxzdG9wIHN0b3AtY29sb3I9IiNmZjc1OGIiLz48c3RvcCBvZmZzZXQ9Ii40OCIgc3Rv
cC1jb2xvcj0iI2RjMzY1OCIvPjxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzYzMTUyYiIv
PjwvbGluZWFyR3JhZGllbnQ+PGxpbmVhckdyYWRpZW50IGlkPSJnbGFzcyIgeDE9IjAiIHkxPSIw
IiB4Mj0iMCIgeTI9IjEiPjxzdG9wIHN0b3AtY29sb3I9IiMyMDE1MWMiLz48c3RvcCBvZmZzZXQ9
IjEiIHN0b3AtY29sb3I9IiMwODA4MGIiLz48L2xpbmVhckdyYWRpZW50PjwvZGVmcz4KKzxyZWN0
IHg9IjEyIiB5PSIxMiIgd2lkdGg9IjQ4OCIgaGVpZ2h0PSI0ODgiIHJ4PSIxMTAiIGZpbGw9InVy
bCgjZ2xhc3MpIiBzdHJva2U9IiNmZmZmZmYiIHN0cm9rZS1vcGFjaXR5PSIuMTMiIHN0cm9rZS13
aWR0aD0iMiIvPgorPGNpcmNsZSBjeD0iMjU2IiBjeT0iMjU2IiByPSIxNDQiIGZpbGw9InVybCgj
cmltKSIvPgorPGNpcmNsZSBjeD0iMjY4IiBjeT0iMjQ5IiByPSIxMzYiIGZpbGw9IiMwODA4MGIi
Lz4KKzxwYXRoIGQ9Ik0xNTEgMTYyYTE0MyAxNDMgMCAwIDEgMTM1LTQ4IiBmaWxsPSJub25lIiBz
dHJva2U9IiNmZmU4ZWUiIHN0cm9rZS1vcGFjaXR5PSIuNTUiIHN0cm9rZS13aWR0aD0iMyIgc3Ry
b2tlLWxpbmVjYXA9InJvdW5kIi8+Cis8L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBz
ZS1tYXJrLTEyOC5wbmcgYi9hcHAvcmVzL2VjbGlwc2UtbWFyay0xMjgucG5nCm5ldyBmaWxlIG1v
ZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAu
LjE1MTIxYzA0YmU3YTRjYjlmYjY1ZmYwOTlkNzQ2N2I0NDRjNmU5MGQKR0lUIGJpbmFyeSBwYXRj
aApsaXRlcmFsIDcwODcKemNtVjtnOCZLcWxQKTxoOzNLfExrMDAwZTFOSkxUcTAwNGpoMDA0anAx
XkBzNiEjLWlsMDAwfHlOa2w8WmMlMUU+CnpkNi08KWI+TSZKLWRDQHh5THdkJTJfJl9JZ3BrO2dG
aClSWmdiajhFajJGTy0/SEM3ZG4yaGxeOFNuOVk9OTVWIwp6Nk1yVT9jcnI2eSRtaUkyYTZGRlVJ
NU9pdmoyRk9Rdnp2VnBsRitgT21VXmtgK1RPZU8lcGIzKylvTHxEZlYjUmAKenMkWU12S2RIT0Et
bTc9Y0pAPWUqJnBsNzVGOU0rS2BgKUM2QnNWQUZoYDJlallTaypVYV49YloybW13SDdjYEE5CnpL
KEtQPCUzIyYxUlIrZkQjXkwzI3p3eFM3dElVbHotZWBiJD85WXVneFkoSW5aQHNsYCpTY0x7eHc2
THw/c0hGUAp6KHFXSUF5P0Ehej5aYEJMK3JXRDd7UD5weXQ1JlZASHtOKlQwbCM9WDk1d34kPis3
P3RTRmlSfCY2bGRtSDZPVTwKemxwV2kpekh4WUhfempoRWQxKU5HPEQ3SGRzPWdKfjtCY00kaChJ
SjNGJEhWd0tvSG0rVkxKVk1NYHk8KSRJWUdoCnomQERmXzxyeHZGTyQqWjMqSm9DKlVoTkxjWDx6
UmZSMFp6PFkhTEFORTNQPGUpQX12JTlVZENHdnxLOG09QUU8Nwp6ZEF4ZDF0IWxeWEo/anlRUjBT
ZX01cmVlYFczNVlQKG9lTkB3KlRBbHo0TCRrUHlnPkhrSG0zZVQqdXp+Kkt4fCUKel58dUNhc1pA
JGZSPSlqUlRlb2ZmUjZkdSNJRjJINSZZPW5qdUJ5RXZgXzRDTWJKe2VnSGEtK2tSVFVIfjBAaGxC
CnpSNyVfMCtJfjVBPyVlLSUkMzF0aGlKfU89MDs4N3EpJCpESVFQVnN6IXNWQTt7KzVrdipNQjg5
SmJYYz1RbypZdAp6TXEpdX4mZFdJR3draTlBYkhGYEhsbVllWEg4M0tDVk10cD9gKT9NWGMqMGx5
YERnJDdFQT5ocmVSZWdrLVd0M1gKelg7e0doOzJZb1F7QCp2PkA+bCkreVJSI2slNlJxTzdeQnRT
SDw+KH5fZzsqTU5vTys1b09SNjIqTUl6KUtsfFYoCnpLUkd9V1pOO3pqMjRpYCgzSj9KQ1Jxd3Am
NTF4UGFzcVlMQTwoOUBTUiU0OChEZm9LaHkhUjU9ejt0eEJLWXorOwp6cispbTB8R041S1Vab1Bl
OFU/VC07QCpEMiNVSXxoZSM1cyQzZEotK0VGdypCZWhOfDU3JHM9UXdwMzE3d0NLOXEKekBBPHt8
Uk1pNTlHI3duTzB0OHx0ekclZS1wV0QyNyVUMHgxNW8/VTJJcURrKT1lQFRyRWlMcitfSX19NDU4
aVc9CnpgYUBIS1NJb3w+V012PkNAcjVmY199cz0jbntPJTxpX1JGTTNSYkNsRDl2TjQ0PWN1S3A7
JmFBSGdFcGdnKTEpagp6b1FTeFV0YjlmNWR7NzFHPis3PzNiOWVsUUQ9KXJnPipnJnRsfWFVTmpH
NUhiV1J1czc3LUxNU1JFb0U1LWc0OTEKekZTeilfY1hNfiMqVmxKWUVCJiR4UHomYHdjPT1XNXpQ
TnRGJkJiRVRILStFdWgldj8laSQlWTIhOzliaztOQDRICnp5TCRDJWNRN1RHUD8oQn1Bb0FWc2V6
KVVxe19FRXM5dm0xdkw1ejVzM3AmI1V1aWwlaz8oWCVVYFNLVWV7PlZvQAp6R09WWnlxdl87UENS
Qmh2dXM9NCZvcFopbkh9QmxHXklHUiEpN3poQnNBX0RENFVWMEE/Qjc1NSNHe3xeLWNSVGgKejl4
JFQmel4oQE8tcGslfExJM1ZPKkc0WE9oJV9DKFg/N3JEQk53fj0tRnZSPmQqfGhFMjMrMytRUUpm
b3peRSRBCnptWWpDKS1hUH43QXZEOWk+NURfTEdrU1Z7YGBGcWktWWc9SnRRKEI3cDlTY24malM5
UDdoVXA+ZH5XMUNNVnJFKAp6LWRJSV9LOUBXSFReQzxeRGQ1TERneVN1TXZEVyVpUGRORzQxTzBu
MVk+eGdUMCo3THtYWkdDbl4hakpzPllPdS0KenU+endPcGp2dzVgYCoqSHlwU0p4diNNOGAhYW93
UVVPazA7eyh8PmlAeEVuJXVnVihPLXZSX2NlRDFRZHpxKTxmCnpqeFJkelZAWkQyV2Nte3VWfWR6
emp7RUJVazNhaysjdy18KF4jUG8hMkUjK1NjUjEmZVgzVCNpVlZyWGU9a284Kwp6cSFlIzc5NWdV
JHtgSHk8ZHwrdzBUdDBkMUAwdUpENz1VdUFibj98I1VBK1gqK0I5R1E/ei16UDFGJiheXzclPiMK
ekx0YVgzR09jalZ4blMkb08pRnJaJW5pV1pjaSM7X0Zgci1Wb251U3w+SmYjQUFSLXVKNHRtc0hj
TylTcT5ZWmFHCnpVc3crTldMfFVmeXM/JjJzbDMjQTlrKXFrYGVKSD1SUGYjdCNTdX5MYU5nbC03
MFQySzdiVTQkOWFFOE9aR2FpQwp6Mi1Fa0BpMVNMaFI2ZmFBaSs5UCFnTWoyQ2NeQWpfPGJAfkFR
UHR8TG40VEQ4NVdxUHtwO0QkQ018ZmpzWD5GeWEKenItI3x5R2RRTkJsZ0AwR2JTZ3hROzhkeCZt
fTByaU5VPXo2Qit0OyRGaGojUnFOb0IwcXZ8cSFaS0ozdlE1NE5fCnphY283ejBzOXRzWm9UIV50
b0x6T0V0NVB8U05VM35qYXVnJmBIPk1TLXFGXzQmZURaVElPbHtEU3V1WVIzcD1fPAp6dDF5Xyl2
MkFGOFpHKEgrbUN2IWFUd299d1AqSGB6bDVXaX51Y3dQc0ozODZCY1ExR1RgWXV2fCNmc1RDRWh6
Z0cKelZwXmVpQDREOGtTPD8jU1VgKDk5WXUmQztvd2xNKDh9Vys+UnQpOCtMY1VsZSt0JFYjbXp+
TEYlZypNS2ctZSgoCnpBPWBLQzxsZzY+O2Fsc1U8SSFEUGQyeDd2VHdMYkJwPE1nVzNLKG48a1Bn
IzA9YTVKK0FfVF5ndlg7O1dTZC0rKQp6Ukh1ejEybnk9N2I9fmpSckt1QF5xNm9zQyR7d3JlPT5I
b1QwaiNrVXFZNUwlQkoqYT89SVRHWmdiJHV8OT9NJDAKekN+ZXh4S2lfZEQqRlc8cF93Qy1zaCUx
OXdOVG1vPG1lI1FDZktOREhqSDtSbHpkR3VqRGxVI0YjfU9oeiUzOUprCnpNSG1EYUcxRWQzSDJE
aGxSUUZ7bnhfX29genZhWFIjVHJCR0okcnxUU2F8SFFlRDtkPkB1NmtzYTltX34+OFlwcQp6QDxY
P0IlWnBGNXdVfHB4ZFlCP0I7aSViRyludUY2QXV1KSlzQlBKKlFIZihKYWcyPSY9XiNaVzJyO0l5
Nj01UlQKelBNY0ooMExFR2RNQEh5TXJ9QEdhUzg/cWh5b0VWTUNITHNGZUM1JTVgUjBadmQ4dzRn
MX1VPGNSelVIcHhJK345Cnp0R2I+c21TTG4pclc4ZUZRWHdzPTVEe3I7TUh0SnBQeWoyMk5JaW8/
TCVpZTZ2LXQ4PVM5NXgqNFc4TSt6ZFpkWQp6SCN+aG0ma1ZqcTVRTWFhRXM0M0YxZmZyYWtTSyRx
NmU9YWthWVF5dTY5JWJpcCMlLUQwRCY+JkRyS0A1ekpCJGAKemAwKThGM0QkMD18SFlAZDtweU07
dHJzMiM3IWBiNkMmNXBJaH5VJlFUcT0tQmc9RTdGR0IkKjRLKmxMUlZ8ZjlBCnp2RnQ2M2E3TkU4
eldGREEkezhJcShjZUFKVj1yeXo7fThGd018TiRjSFFmUipyR2cpZVJRR3Q3cTYpRWh3MXE3TQp6
I3gjZiQ5NE9vVW9qfjFwT2ZgWUE/OVMoUypXeSQ3KX43eUErd0xMcyFOPDh7X2c0UCstck1MZTY9
PSh9NjhwdncKentDR3IhKmdKK3hCVkB4QyFYVExQRFBiYm5Ic2xtd3QpKU1nPEt4VEQ7cF9rTEtU
JiprOWxgY357JkQreUs2PndNCnpJRThFfi1MUyYxQXFYREdTQmhsR2tad1N+cHk4SCR0dWdHJDRS
aWZqPWthJmZmMTNRYCZ5d0EtaGctTD08M3NuWAp6MGZmLW54O2M1VG1zO1JCUWdzajtaSVAqPTZk
KjgkSjtlZWFKTSRjRmBqYnlGXndgc01eeWdVZihxPXlUbzcrZWsKemkhfXp7VjU4X3o4TDU9MHhW
V0t8cGtXanM1TWlLRjsrQEFXPG07Rko1eE02I2tsaSlGTC1+SEx4bn5XQ09sI3JTCnokZGAtNiZO
V1E3d0lNUXJSKXBhPTs8VDx+X354N2IxTGRfWlZxKFcwYWVVfldwRTZ1MikwIz84OD8lMmY2ZVY5
Tgp6KFZsNj1QflVxIWshK3tmMHdAQVItamZZZGVEaj0oPX1NKDMjV0FnNm5tPkt1UE0jbGxpRU1h
ZTJwPHkxKDBOQ3AKelFyZlI/PlFvV3p6d31wczgoOytucVk4Z31fRkd1aWIxZU9aSlRvKGB7S01N
RWBPKjVQWGlHUDRzUHxlQzVoYCYrCnorMWZmczJJRk5iUSk+YU4yIW0wRE9Ybj0pPDBxV1hQXm15
Uk5VPUZMJFBKSShMbj10Jjh6TztuX3pAOWBRUlI+cQp6clk0STY2YClTTDdleWlWTkBvelY+V3VV
OHM+SSZZVmd2cl9zciVXVUEwJXlxWTQ3d000RFVVcXNGRkJAYj14KCUKektsPj5feXs8dDRCWmk/
JG5VNXwkb3p1SCNGPGRGcmtxVVd1X2piTyZ7eik9bnJlVl4lbFpBKi1qJD5seXNNYyVMCnpUP2VM
UTNKez49ViYtUSVfezhFZkNgTSVya2l6Z2tvX21Cc3JBIzBWNlFORWppYylnWGx2UUMoJHo4VCQk
ajFAYQp6RUlOZ0cqPih6WE1Bb0t3ViZFbSNZPFZGbSNYNz1BZStAeTFUI1RDe040TT9AQVZBczIl
eFRUP3teT1RZaVh1PTUKenQ+cXMjSzB+ZnRBU0xEcWJeUnRyUmpJaENOZlZEI2ZYU2JNajBwTC0h
WD9LWSYhVEo+ZypZTkRoV19GUktpVHBFCnpDUCpGOGpeOUx4QnZ3R1IqN0xjM1VPLVVxRVB6KWZa
MzM/N1U0cnUtUmkhbHVgMVFfQnlmRDAlbVpNTXMwR3hVdgp6Pz97PHwkKkxVfkZXWHdYX3F0KDNE
N2M3fEo3QDVROE03KEdpVE83T2NXbUU/SSlgYkg5Q19WUWw0empMQUhTeyYKekFQOG1leE0wPml4
PjZ5TGF8OXZgUiFaRXJkbUNjeTV1NW1WQn04UEBCRyF9b0RTIyU8UEFIWilBMlMhe2VLSC0wCnpX
a1lVfGJAQFI7Sk1+cEZRO0V+JHA0NCo7PnxZVHlpQjNTVz07TjUzWTJ+eno5IWhaeHMpV1l5XmlW
JHxRSGc5Uwp6alhSMUpLdkE2Y1NUamlqVkZLQ0slPnN4QkNGZU15dCY3PnxSd35ZY0NXYFV3Jj5y
eE96YXl6MGN3Z1UxYTlsbVcKenpPVHQzUXBlSmNaWmdKRiY8WCZ+ZClEV05LcE1Neng/WHJaT3Ar
JXdrITxUKzZlXnNVP0UrMTxYYz9kISQ4ME8rCnpzfHMrbUJtNEMmczBWZFowMGphZyV4aF4mKHc/
ZGFoSnVTMnRkIXM9JF45UDtmZz84eEBUIzwhZlNLdEd2Rz1HWgp6Q29laDJoPkl7SDRZNDAjcytz
SVcrPDVBJDBCTExLdSZHZkMwRStYRHZpRno8RDM1OWc+S2dedHJ6bGlOZFhvbW0KemtnPnRPRGox
KEEjP2MpNlBmWElLO3FicmY2eElWTWlwM0NBOVVVfjt4QHsxd3NoUiZ+Nys3c1lQYEFeS085VXlD
Cnp3bURHOHpKS0VFRDRxYkopZFdmNEJPTFghZkItVUM3STZhRSktTXNuejc/O1U1OyM+ZCM/bF55
QjtDb0gpU0oyfQp6ZktwOGJ0RVVqaClwQl5uZHIhdCNXYD56K1NhQGAhUTFfeWN5NnBAUzVzSjwr
OTkxd1gpbX1ZSDNTb1hySX4qaz8KelU8WEk1alZVSzVEPnxpNHBwaiVMY3ozeW9tOHVVPTRGeWxr
Y0c3ZUo2WTZhTj5nb2VUPmUqN3ZWS2ZRPDFjO3BECnpsKHJkSVltZHJHcHNAJV4tQHwkKWdYXkF1
VHtralIlPmdOKk5oV1lmWWJVZVB0d2lkTllDRGtoRTNVNmQ+USlyMAp6Q0BCJXY8XzlSY0NeQGt6
VyQmMEJ3czItZzUzekZ4SGZLSWNQezBfZSlBbz5rKU5OO3dTMCFhRUZCRkVAUlZvbVcKekcqd2l1
cXtNTEhqNSNuVmBMRjROSEhrUnRDO29iNzB1QDNyeWlfam9SQmtXbllPQENjaWdDbistRShNOVd2
Q3BiCnoofHx5QXs7eDBsRTVJYkhvZDZaQHhwIWJFUnQ0YEJLYEZZSkJgdXd0LSErP3hpO3VjI0t1
SmN3c247Z2FHMVMlTAp6UD0kPUt7QVRZQzJCSCN5MndHaGJ2TGFrSGAtSjNtXn1NSkNBJnt3Z0xT
SjFLekB1Y1c8QHUzODl2UndBaT9NazEKejckNnN3ZEUxT1JvWUt9cT1fcy1TTkBEdTBuVlJpemI+
QUs/MnFvfE0kP2k+OTcrbzJSeXdZaHlLNmN5Xnltdj45CnpBMFItKzI2ZWdqaHV7UUd7XmBBWCtI
QW5qYD9zPWdXU0VSMyZZJVRgcUI4RzI9NkZ0UHBHb20zdW1XQ3t0Ty1icwp6d3Z3JkMzZS1JanEo
STZUYzIpfGtlcldAKENjeWNgM2RISlp2bmY4P2Qpa3pAUE1LXyFxJX5lb0Rub2UrQmNDYSQKeiNQ
cTZVWk5Md0FaRDNPfE40alBPUjJZaU5Uc0M3S0AwQHUmZ304en0wPEN9e05zQktDK28rKFU7cVgq
bE9XamMqCnpaN2lFaGRIIUw/VEMmRkNZS3ViKFcjP0djZG5VOFBSd357ZlE1IX1ERDY0MDdrZkE0
KXEySEMwWGxSUEE9S3V3JAp6KkRUfnpYfTJNXz57YCNgeGprZWhpM2tLSkk+Ji1ebWNOKlA3TG5G
fSRMd1VIQjtDPUBaa0BeY1hrQGdaXmkoKjIKelB8cmxyeEk7Q1cxQmNeP3xGLTRIKGVyRTdBc21S
eFRyczFVUGFTKFFnKHcqJSg7YjZRQC1Zeys5bXtUQ1ZYdiFACnohcW9NP2tKb31KLUhxVz89P3Fm
KlZzSG9GK3FzU3xuQFhCT0RwKzdKdUpDN2JQVVcobTE/MSFELThqbDM2bnc8Xwp6Kjw8SnFHQ1dv
cXBqQ24/LXdyP0pjZUxnWmVyPy1SSmQpby15OXRQV3ZUQFdgUn0yNjl7NVNCWGpebjFTNT9GKjAK
ekE4fnI3bnslX3JhN1RVenExM3htQFdmMVRIfHVNVTZlU1IkO0ExfHM9QEFDd0dOQms7KWdQIysk
Qk9XYzxJbXl6CnpfU3NiPm1fRX0lUDUzOGdJPVFsSUs1S0hARFhHSmZlRUtRMXw0ZDx7JGd6ajNU
N2pudmdNNTBeQk4mcDVWTyg8eAp6eSgyVzFaIUtFRStxJmtHa0lSP18tJU1XWHpjYjxeJlRRJUNC
aSQhKFRZZnVSO3NSOzBiIz9wPnJVRElQUGgoWk8KemZ7PWU3K1FGQiRLMkEkQGFVYHpwQX07d0Rn
WWZrUVp7JFBBb0poZXthTWVZbU0jRUcrYCt8M0BZQDV3VFhQbSVvCnpgNWluXzl3T1RTXlpyO0dN
Z2J0UDFsPlclNUI2OzJoVjQoI0IwO3M1RmxpbzlAczZeMGUwbEVhezYrNl9HUjg5RQp6QkNJcnFI
QXFJaVB9Q1RVQGMhLXZULUNYTmU7TUErMUVvRSpISkk/QjBVc0xXUkdERXp6U3FCanFJY1lRKy1i
PlUKeipuSU1vNFRteGltJGBEcjAjMGVeOy0oIT5iQU42KGZpYXx3dF41OVpzUDUpTGh9MDl8STVG
KHQlRmJUcXJkcyZICnomP1gpKDQ8dmJ4MWB8RnNtPDZjZU5HIXBSX0hOPyhFc3JxYlZwPmY9TVNY
UCNrKzMlXnZtbmchY01JT2dtKiQrIwp6dFc8YFB4SSRjPTdWMlJXWTlycEU2bnNwRk8+dCVDZF9G
YUUzN3N+QC13KGRYQmp0Z3IqPjZsNV9QSyR2RCYwMloKelNIcnV3cmdBQGpLSWFUaFp8UCNkbUdO
NWJJcHx7KWM8K25feXMzUV9LaTwyRXBBSyFLemYhfilMc3w/KjRzWHx1CnorR3RtbGl1JSFNPm4r
KXRvUyZWXmFYfH51UikrY1VASyQha0MwZktiT3lqRlZjeThkIWhZTTNkdFYqWDEqaWc9Swp6P1p5
WkE8ZzYzdj56PEVDJEBfVHBicHZza3RQU3xZdFItQzVISUYtb2NrcWtoOWpxX3NAIW4mXjVMVDY7
X1IocjgKemFqO0orKSRjVzE7IXpeP3FnR340cytGQF54Pj8+YmdKWGpYTWVuI0h6a14/bj80cUtj
bVdEST8yZzxoTGUxUCNkCnpSYXp2I3A/cjFjKTcrY2UlX25EXyRrS0VOQlIpPWkwfSYkY0RRYVNk
fEVPbW5tdnpxTCQ+SVJOJkZ8KlA7dm1+OQp6MXhpKD1zY3BiOCFpMz51RWtoQTJJUUJKZjQyQHhT
cylaQjdjMjNRN3VePz12LTZUJm5kNyslKyZYSFhfUn5hVFAKendpQGErbEpGO3s7U35VcWshT0hU
OH1pJGNlamVYNno8YXZwYWI7STgkRUkyK2MkWHwxa3RCfGFhWip3QWhVXlReCnpadFk+blNKK2VA
O2V9RjtiPiRxfXFhdTZiR0k8ey1qK15TSnVuYTtWTE1XRDJZdzVCZnZ3e3JzUW15b2NTIVVZfAp6
RXloLXhVTU1AXzYyQnwtXkkmbGdDSDFzUSgoODlSMnBeYDIwPkhrNlFKWUR1IVQ7SF9rKUlGbTxr
SFNMeXNpQ00Kej1Bfk1SQEQjblAmaVA2dV9FcUgoUEU1RDZHfUQxc0N+Q316aV47aXx5cEplKFBv
eTVMekJWTz43R3I0PE9ES2lfCnpnQk1LLVNFfD9YUWU1S0UoZnwoP19jR3VyV1U4OzlFYHFOeWVz
ezFvanQ0TD9qLSteXkJTPG1pQkVIa1ZmaTs4TQp6STUqcUYlQz1jNyY5dXtRMTdjTjU+V0RsPGN1
Rm9BbTlAX25pbEhZK0dtfl47QH5jK0JzYTc5RHBad258I054cTIKekwxUSptM09yVUM7RjxDO0xv
T24xJXhIclAqVSkhdlYoKUhMMG0za0pmVUR+ankrJiUqQVB9SnxOS3c/N2U7ZU07Cnpvdz1STjRf
aTRpKTZIb3VvZzUhIz45aUBiMWdLM09HNEU3flFDIylrSEVVNzNGKyE1UjdsRGNATHExfCNSQTZs
LQp6JmtMMHRKRTlUfVBiaH0wbk9eMztOPnI2S0ZoJjZ1Rko0PmBCTCQjKU4tcGEpUCpWaHAmezF7
OXdwMHFORTlkIz8KekBLKEJQJGVkSVFeSFF4RzdpNT9qcS1pJCs4M19uUEZ4N0FfUWNxYnUxc15s
eUJLRWlueVBfZ0g7fVd+I0dRJlE/CnpYfGxJNTZvWChWdjdoSXBwQDR7eSF0JitJJWU1YTBxeH1p
aCZZUm8mX3xWfGNzVXFUTyY/TTAtQXUhcj1GdmdGRAp6Wk9QV0ZXUFZSbz1YRnpjfDkjYWVqNT5y
PnVpcn1JNVpZd2w/dFllSDhzYiZlYmFyKDt3UlBMKFdnX0FMMn1tQDwKejFWUH5EJkYkUnxvSndR
NjBTODRQYW4+WDs8JD4ofmE4IT5IZG5GPj9AOXpZYGg+I0lPWkdFWWhETnZaK3FFQXFPCnpBaDBg
dkFhRW9EK31FWjY8R2wwZkYjV3Q+LWxqKUY8MzhPZHo9O0BOWHFxXkpNfShrWDRpeWFQRiFQKnE0
eXA+VQp6JiYoQHl3NntOTXRVKjs5VlIzQ3pJb0tOY2slKzJfdjQoN1crd2FIeit5SmElbD9QYWBY
dSpUMlIxbUFgKWErRGoKekdGaG1xKzh+dlI3Y1hBO0s9UHdSPTNfXj9zSCZZZVhhNFU4MV9uPHZY
OEptVU8lQXwkdWVRNnBgXmx9X0ghWkleCnpgM24wQipvc0twKGI0ZlVZWW90X0UwfDRRSiEtOT90
RTJzQVJxdWIpIWpEd3w1M3VCPCNzND08aHQ3THYkMzgpJQp6YDg5cE55bXZOQ2hpPnNuaSs/bSQp
Xk9tUzh4c1Y5cEVJWlRTTiokcFVzeUYyT0BDbHw8NWJubW9IX0haP0tgJTwKekhJOEckN3pHJFYk
NGVaP14hRTF0Wjh7OSlOUWVmSGNEej4hISUqZmdTbnhNLTlLKk9sS1QpYDZSRnd0dTd2OV55Cnp5
Wjx+ZmBfQ0NvcldIPVQrR0NFSGBQKz9+VXdtYDUzK2FCby05JW8jaD1AUD1sJS0kSFdITlo/c1pK
JFJTSUZLeAp6VWR5NTBjYH0pZG9feSpfVSN3MiYyTXFYXk9aWnIwajV+NGgod256Iy1GQl8yIyFS
RXlmaEdYTkFgPGtAbnx0JXgKemI8YmJ0eXwreFQrV1ReR3pXM2duJndUYmpmNDtNYGJEajQtcGN4
aVVDJXBHUT08TXVWX3Z6MnhfeXpDJWV2YVEqCnpVUVBrRGszUEJYeTZjOVBFbmp8aFRVKWtWJV4m
TWorcUxITE4oYnRrQmlxKG1LSTY8fkFHKz9rdEFfZ01kKWE1UAp6eWkoNUowYEE7JSZpJikoKX4+
eSFSNGg0VGo1Jm5BWWNlJmNfdWdrUjhHRip3Q0Qre2w7UWltSEQjTXJpZ0k3eFIKekl2e3hQO1Ju
OGQhdG8wfm1yaUdfX2tKe3UqcmNJUUA0WmlfR2pgRiE8M0lvNExsMW5QI0JWIWptRGl6OzxpSHBj
CnpwSy08O0tEJStfaFFCVHJpJiRmdkhwOWIpSyleWmdaNj1kcDtsZjNxZjh2UXB8R01oOCNmUns+
aGx+e3d3Xz9UbAp6KlF7TjtfUysqUEJXViRkTVdoKVdPZCpRSz5OVXRfdipqZ0FtUiRHMTFIWmtj
eHwofVBeX3tPfndhPSspYVIyQEgKei1MaGlFKiUkVG5eZ0poRzBgSSpaPmRCZk1SLUVAPDFyeUFl
RzJ7NmFFNiU7PntgPkV7TU85elg/MnFOdUY4OVdPCnp6NVZ2dkBCN1FZe1BYakFkKl4rLUNEUzZf
dEpTMmxxWFV7cnFlKmt7Zmg0PTwpdkltRXZgQkM3eWw+eGQhKyR5Tgp6X1M8aX1rN1VrJk1ZQkph
KlhxcSV6IV90Qj5zI054YV8jZmEtWihmb3lzfWEkQ2w3QC01PzNEd1VNbzdTcU9hcVcKek0rKm5z
cXBKQVRkI2B+QWdraFNfdTh3PF9FSURiX3VZWX4jVTVRX1FhQnUoUmNzPGduYndQMXFuQndmUyZ3
Sk9fCnomNn08dCZnQ3d5UjRTJkxIJFglakF9YWVVTHNKVlRyWiYjMjwldWVfPk1VejVWSGojaFhV
OHcrJjcxIX1BQTBDXwp6S2FIWFk2MlpVYiRuMDxrVilPIW5SS1VkLVVBbGJaIyZ1VD80aTNHZVI0
U2J3TVhgMHhxM1d3IWxiYUZiIUFVbHkKemgjMEszcSo4JilXWVNNe2IjP3UwIVF3P2Z7PykoVkBu
e3J7VEtVJkI+aTBqfTtiVDhkUjhAS1J5UlNOVikyOCszCno8Wn03NSVIYDVZYVUzMSVvUykmblom
aHVzRXNSQmsqY2VsPSo2YTt9KVhzRHxeSVMocWB5PXpgRk00UnJudHlzJAp6TH4we3YpYmJ2ZF5C
I15qOEhjR0pxaVFPV242TX57JjNDQERDYzk8SkA2IVZWbTFZaU00QmckSz4rTX0ke0BCT2YKekpy
Vj9nX3VoP2Y8YDUpPm9IcmlVSEpRbnJpKShYIUV6PEJiN25CWl8rOH1+YFImYFM1JlUhbXpQM1B+
PnNHRm5vClp7e2k9SWRASF5eS3F2cUowMDJvdlBESExrVjFtRUIyKGJWRgoKbGl0ZXJhbCAwCkhj
bVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9lY2xpcHNlLW1hcmstMjU2LnBuZyBiL2Fw
cC9yZXMvZWNsaXBzZS1tYXJrLTI1Ni5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAw
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
ZGlmZiAtLWdpdCBhL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTUxMi5wbmcgYi9hcHAvcmVzL2VjbGlw
c2UtbWFyay01MTIucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAw
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
aWZmIC0tZ2l0IGEvYXBwL3Jlcy9lY2xpcHNlLXBvd2VyLnN2ZyBiL2FwcC9yZXMvZWNsaXBzZS1w
b3dlci5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLmI0MWU1ZmY3Ci0t
LSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9lY2xpcHNlLXBvd2VyLnN2ZwpAQCAtMCwwICsxIEBA
Cis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWln
aHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxwYXRoIGQ9Ik0xMiAzdjhNNyA1YTggOCAwIDEg
MCAxMCAwIiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ry
b2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYg
LS1naXQgYS9hcHAvcmVzL2ljb25zL2hpY29sb3IvMTI4eDEyOC9hcHBzL2VjbGlwc2UucG5nIGIv
YXBwL3Jlcy9pY29ucy9oaWNvbG9yLzEyOHgxMjgvYXBwcy9lY2xpcHNlLnBuZwpuZXcgZmlsZSBt
b2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
Li4xNTEyMWMwNGJlN2E0Y2I5ZmI2NWZmMDk5ZDc0NjdiNDQ0YzZlOTBkCkdJVCBiaW5hcnkgcGF0
Y2gKbGl0ZXJhbCA3MDg3CnpjbVY7ZzgmS3FsUCk8aDszS3xMazAwMGUxTkpMVHEwMDRqaDAwNGpw
MV5AczYhIy1pbDAwMHx5TmtsPFpjJTFFPgp6ZDYtPCliPk0mSi1kQ0B4eUx3ZCUyXyZfSWdwaztn
RmgpUlpnYmo4RWoyRk8tP0hDN2RuMmhsXjhTbjlZPTk1ViMKejZNclU/Y3JyNnkkbWlJMmE2RkZV
STVPaXZqMkZPUXZ6dlZwbEYrYE9tVV5rYCtUT2VPJXBiMyspb0x8RGZWI1JgCnpzJFlNdktkSE9B
LW03PWNKQD1lKiZwbDc1RjlNK0tgYClDNkJzVkFGaGAyZWpZU2sqVWFePWJaMm1td0g3Y2BBOQp6
SyhLUDwlMyMmMVJSK2ZEI15MMyN6d3hTN3RJVWx6LWVgYiQ/OVl1Z3hZKEluWkBzbGAqU2NMe3h3
Nkx8P3NIRlAKeihxV0lBeT9BIXo+WmBCTCtyV0Q3e1A+cHl0NSZWQEh7TipUMGwjPVg5NXd+JD4r
Nz90U0ZpUnwmNmxkbUg2T1U8CnpscFdpKXpIeFlIX3pqaEVkMSlORzxEN0hkcz1nSn47QmNNJGgo
SUozRiRIVndLb0htK1ZMSlZNTWB5PCkkSVlHaAp6JkBEZl88cnh2Rk8kKlozKkpvQypVaE5MY1g8
elJmUjBaejxZIUxBTkUzUDxlKUF9diU5VWRDR3Z8SzhtPUFFPDcKemRBeGQxdCFsXlhKP2p5UVIw
U2V9NXJlZWBXMzVZUChvZU5AdypUQWx6NEwka1B5Zz5Ia0htM2VUKnV6fipLeHwlCnpefHVDYXNa
QCRmUj0palJUZW9mZlI2ZHUjSUYySDUmWT1uanVCeUV2YF80Q01iSntlZ0hhLStrUlRVSH4wQGhs
Qgp6UjclXzArSX41QT8lZS0lJDMxdGhpSn1PPTA7ODdxKSQqRElRUFZzeiFzVkE7eys1a3YqTUI4
OUpiWGM9UW8qWXQKek1xKXV+JmRXSUd3a2k5QWJIRmBIbG1ZZVhIODNLQ1ZNdHA/YCk/TVhjKjBs
eWBEZyQ3RUE+aHJlUmVnay1XdDNYCnpYO3tHaDsyWW9Re0Aqdj5APmwpK3lSUiNrJTZScU83XkJ0
U0g8Pih+X2c7Kk1Ob08rNW9PUjYyKk1JeilLbHxWKAp6S1JHfVdaTjt6ajI0aWAoM0o/SkNScXdw
JjUxeFBhc3FZTEE8KDlAU1IlNDgoRGZvS2h5IVI1PXo7dHhCS1l6KzsKenIrKW0wfEdONUtVWm9Q
ZThVP1QtO0AqRDIjVUl8aGUjNXMkM2RKLStFRncqQmVoTnw1NyRzPVF3cDMxN3dDSzlxCnpAQTx7
fFJNaTU5RyN3bk8wdDh8dHpHJWUtcFdEMjclVDB4MTVvP1UySXFEayk9ZUBUckVpTHIrX0l9fTQ1
OGlXPQp6YGFASEtTSW98PldNdj5DQHI1ZmNffXM9I257TyU8aV9SRk0zUmJDbEQ5dk40ND1jdUtw
OyZhQUhnRXBnZykxKWoKem9RU3hVdGI5ZjVkezcxRz4rNz8zYjllbFFEPSlyZz4qZyZ0bH1hVU5q
RzVIYldSdXM3Ny1MTVNSRW9FNS1nNDkxCnpGU3opX2NYTX4jKlZsSllFQiYkeFB6JmB3Yz09VzV6
UE50RiZCYkVUSC0rRXVoJXY/JWkkJVkyITs5Yms7TkA0SAp6eUwkQyVjUTdUR1A/KEJ9QW9BVnNl
eilVcXtfRUVzOXZtMXZMNXo1czNwJiNVdWlsJWs/KFglVWBTS1Vlez5Wb0AKekdPVlp5cXZfO1BD
UkJodnVzPTQmb3BaKW5IfUJsR15JR1IhKTd6aEJzQV9ERDRVVjBBP0I3NTUjR3t8Xi1jUlRoCno5
eCRUJnpeKEBPLXBrJXxMSTNWTypHNFhPaCVfQyhYPzdyREJOd349LUZ2Uj5kKnxoRTIzKzMrUVFK
Zm96XkUkQQp6bVlqQyktYVB+N0F2RDlpPjVEX0xHa1NWe2BgRnFpLVlnPUp0UShCN3A5U2NuJmpT
OVA3aFVwPmR+VzFDTVZyRSgKei1kSUlfSzlAV0hUXkM8XkRkNUxEZ3lTdU12RFclaVBkTkc0MU8w
bjFZPnhnVDAqN0x7WFpHQ25eIWpKcz5ZT3UtCnp1Pnp3T3Bqdnc1YGAqKkh5cFNKeHYjTThgIWFv
d1FVT2swO3sofD5pQHhFbiV1Z1YoTy12Ul9jZUQxUWR6cSk8Zgp6anhSZHpWQFpEMldjbXt1Vn1k
enpqe0VCVWszYWsrI3ctfCheI1BvITJFIytTY1IxJmVYM1QjaVZWclhlPWtvOCsKenEhZSM3OTVn
VSR7YEh5PGR8K3cwVHQwZDFAMHVKRDc9VXVBYm4/fCNVQStYKitCOUdRP3otelAxRiYoXl83JT4j
CnpMdGFYM0dPY2pWeG5TJG9PKUZyWiVuaVdaY2kjO19GYHItVm9udVN8PkpmI0FBUi11SjR0bXNI
Y08pU3E+WVphRwp6VXN3K05XTHxVZnlzPyYyc2wzI0E5aylxa2BlSkg9UlBmI3QjU3V+TGFOZ2wt
NzBUMks3YlU0JDlhRThPWkdhaUMKejItRWtAaTFTTGhSNmZhQWkrOVAhZ01qMkNjXkFqXzxiQH5B
UVB0fExuNFREODVXcVB7cDtEJENNfGZqc1g+RnlhCnpyLSN8eUdkUU5CbGdAMEdiU2d4UTs4ZHgm
bX0wcmlOVT16NkIrdDskRmhqI1JxTm9CMHF2fHEhWktKM3ZRNTROXwp6YWNvN3owczl0c1pvVCFe
dG9Mek9FdDVQfFNOVTN+amF1ZyZgSD5NUy1xRl80JmVEWlRJT2x7RFN1dVlSM3A9XzwKenQxeV8p
djJBRjhaRyhIK21DdiFhVHdvfXdQKkhgemw1V2l+dWN3UHNKMzg2QmNRMUdUYFl1dnwjZnNUQ0Vo
emdHCnpWcF5laUA0RDhrUzw/I1NVYCg5OVl1JkM7b3dsTSg4fVcrPlJ0KTgrTGNVbGUrdCRWI216
fkxGJWcqTUtnLWUoKAp6QT1gS0M8bGc2PjthbHNVPEkhRFBkMng3dlR3TGJCcDxNZ1czSyhuPGtQ
ZyMwPWE1SitBX1ReZ3ZYOztXU2QtKykKelJIdXoxMm55PTdiPX5qUnJLdUBecTZvc0Mke3dyZT0+
SG9UMGoja1VxWTVMJUJKKmE/PUlUR1pnYiR1fDk/TSQwCnpDfmV4eEtpX2REKkZXPHBfd0Mtc2gl
MTl3TlRtbzxtZSNRQ2ZLTkRIakg7Umx6ZEd1akRsVSNGI31PaHolMzlKawp6TUhtRGFHMUVkM0gy
RGhsUlFGe254X19vYHp2YVhSI1RyQkdKJHJ8VFNhfEhRZUQ7ZD5AdTZrc2E5bV9+PjhZcHEKekA8
WD9CJVpwRjV3VXxweGRZQj9CO2klYkcpbnVGNkF1dSkpc0JQSipRSGYoSmFnMj0mPV4jWlcycjtJ
eTY9NVJUCnpQTWNKKDBMRUdkTUBIeU1yfUBHYVM4P3FoeW9FVk1DSExzRmVDNSU1YFIwWnZkOHc0
ZzF9VTxjUnpVSHB4SSt+OQp6dEdiPnNtU0xuKXJXOGVGUVh3cz01RHtyO01IdEpwUHlqMjJOSWlv
P0wlaWU2di10OD1TOTV4KjRXOE0remRaZFkKekgjfmhtJmtWanE1UU1hYUVzNDNGMWZmcmFrU0sk
cTZlPWFrYVlReXU2OSViaXAjJS1EMEQmPiZEcktANXpKQiRgCnpgMCk4RjNEJDA9fEhZQGQ7cHlN
O3RyczIjNyFgYjZDJjVwSWh+VSZRVHE9LUJnPUU3RkdCJCo0SypsTFJWfGY5QQp6dkZ0NjNhN05F
OHpXRkRBJHs4SXEoY2VBSlY9cnl6O304RndNfE4kY0hRZlIqckdnKWVSUUd0N3E2KUVodzFxN00K
eiN4I2YkOTRPb1Vvan4xcE9mYFlBPzlTKFMqV3kkNyl+N3lBK3dMTHMhTjw4e19nNFArLXJNTGU2
PT0ofTY4cHZ3Cnp7Q0dyISpnSit4QlZAeEMhWFRMUERQYmJuSHNsbXd0KSlNZzxLeFREO3Bfa0xL
VCYqazlsYGN+eyZEK3lLNj53TQp6SUU4RX4tTFMmMUFxWERHU0JobEdrWndTfnB5OEgkdHVnRyQ0
Umlmaj1rYSZmZjEzUWAmeXdBLWhnLUw9PDNzblgKejBmZi1ueDtjNVRtcztSQlFnc2o7WklQKj02
ZCo4JEo7ZWVhSk0kY0ZgamJ5Rl53YHNNXnlnVWYocT15VG83K2VrCnppIX16e1Y1OF96OEw1PTB4
VldLfHBrV2pzNU1pS0Y7K0BBVzxtO0ZKNXhNNiNrbGkpRkwtfkhMeG5+V0NPbCNyUwp6JGRgLTYm
TldRN3dJTVFyUilwYT07PFQ8fl9+eDdiMUxkX1pWcShXMGFlVX5XcEU2dTIpMCM/ODg/JTJmNmVW
OU4KeihWbDY9UH5VcSFrISt7ZjB3QEFSLWpmWWRlRGo9KD19TSgzI1dBZzZubT5LdVBNI2xsaUVN
YWUycDx5MSgwTkNwCnpRcmZSPz5Rb1d6end9cHM4KDsrbnFZOGd9X0ZHdWliMWVPWkpUbyhge0tN
TUVgTyo1UFhpR1A0c1B8ZUM1aGAmKwp6KzFmZnMySUZOYlEpPmFOMiFtMERPWG49KTwwcVdYUF5t
eVJOVT1GTCRQSkkoTG49dCY4ek87bl96QDlgUVJSPnEKenJZNEk2NmApU0w3ZXlpVk5Ab3pWPld1
VThzPkkmWVZndnJfc3IlV1VBMCV5cVk0N3dNNERVVXFzRkZCQGI9eCglCnpLbD4+X3l7PHQ0Qlpp
PyRuVTV8JG96dUgjRjxkRnJrcVVXdV9qYk8me3opPW5yZVZeJWxaQSotaiQ+bHlzTWMlTAp6VD9l
TFEzSns+PVYmLVElX3s4RWZDYE0lcmtpemdrb19tQnNyQSMwVjZRTkVqaWMpZ1hsdlFDKCR6OFQk
JGoxQGEKekVJTmdHKj4oelhNQW9Ld1YmRW0jWTxWRm0jWDc9QWUrQHkxVCNUQ3tONE0/QEFWQXMy
JXhUVD97Xk9UWWlYdT01Cnp0PnFzI0swfmZ0QVNMRHFiXlJ0clJqSWhDTmZWRCNmWFNiTWowcEwt
IVg/S1kmIVRKPmcqWU5EaFdfRlJLaVRwRQp6Q1AqRjhqXjlMeEJ2d0dSKjdMYzNVTy1VcUVQeilm
WjMzPzdVNHJ1LVJpIWx1YDFRX0J5ZkQwJW1aTU1zMEd4VXYKej8/ezx8JCpMVX5GV1h3WF9xdCgz
RDdjN3xKN0A1UThNNyhHaVRPN09jV21FP0kpYGJIOUNfVlFsNHpqTEFIU3smCnpBUDhtZXhNMD5p
eD42eUxhfDl2YFIhWkVyZG1DY3k1dTVtVkJ9OFBAQkchfW9EUyMlPFBBSFopQTJTIXtlS0gtMAp6
V2tZVXxiQEBSO0pNfnBGUTtFfiRwNDQqOz58WVR5aUIzU1c9O041M1kyfnp6OSFoWnhzKVdZeV5p
ViR8UUhnOVMKempYUjFKS3ZBNmNTVGppalZGS0NLJT5zeEJDRmVNeXQmNz58Und+WWNDV2BVdyY+
cnhPemF5ejBjd2dVMWE5bG1XCnp6T1R0M1FwZUpjWlpnSkYmPFgmfmQpRFdOS3BNTXp4P1hyWk9w
KyV3ayE8VCs2ZV5zVT9FKzE8WGM/ZCEkODBPKwp6c3xzK21CbTRDJnMwVmRaMDBqYWcleGheJih3
P2RhaEp1UzJ0ZCFzPSReOVA7Zmc/OHhAVCM8IWZTS3RHdkc9R1oKekNvZWgyaD5Je0g0WTQwI3Mr
c0lXKzw1QSQwQkxMS3UmR2ZDMEUrWER2aUZ6PEQzNTlnPktnXnRyemxpTmRYb21tCnprZz50T0Rq
MShBIz9jKTZQZlhJSztxYnJmNnhJVk1pcDNDQTlVVX47eEB7MXdzaFImfjcrN3NZUGBBXktPOVV5
Qwp6d21ERzh6SktFRUQ0cWJKKWRXZjRCT0xYIWZCLVVDN0k2YUUpLU1zbno3PztVNTsjPmQjP2xe
eUI7Q29IKVNKMn0KemZLcDhidEVVamgpcEJebmRyIXQjV2A+eitTYUBgIVExX3ljeTZwQFM1c0o8
Kzk5MXdYKW19WUgzU29Yckl+Kms/CnpVPFhJNWpWVUs1RD58aTRwcGolTGN6M3lvbTh1VT00Rnls
a2NHN2VKNlk2YU4+Z29lVD5lKjd2VktmUTwxYztwRAp6bChyZElZbWRyR3BzQCVeLUB8JClnWF5B
dVR7a2pSJT5nTipOaFdZZlliVWVQdHdpZE5ZQ0RraEUzVTZkPlEpcjAKekNAQiV2PF85UmNDXkBr
elckJjBCd3MyLWc1M3pGeEhmS0ljUHswX2UpQW8+aylOTjt3UzAhYUVGQkZFQFJWb21XCnpHKndp
dXF7TUxIajUjblZgTEY0TkhIa1J0QztvYjcwdUAzcnlpX2pvUkJrV25ZT0BDY2lnQ24rLUUoTTlX
dkNwYgp6KHx8eUF7O3gwbEU1SWJIb2Q2WkB4cCFiRVJ0NGBCS2BGWUpCYHV3dC0hKz94aTt1YyNL
dUpjd3NuO2dhRzFTJUwKelA9JD1Le0FUWUMyQkgjeTJ3R2hidkxha0hgLUozbV59TUpDQSZ7d2dM
U0oxS3pAdWNXPEB1Mzg5dlJ3QWk/TWsxCno3JDZzd2RFMU9Sb1lLfXE9X3MtU05ARHUwblZSaXpi
PkFLPzJxb3xNJD9pPjk3K28yUnl3WWh5SzZjeV55bXY+OQp6QTBSLSsyNmVnamh1e1FHe15gQVgr
SEFuamA/cz1nV1NFUjMmWSVUYHFCOEcyPTZGdFBwR29tM3VtV0N7dE8tYnMKend2dyZDM2UtSWpx
KEk2VGMyKXxrZXJXQChDY3ljYDNkSEpadm5mOD9kKWt6QFBNS18hcSV+ZW9Ebm9lK0JjQ2EkCnoj
UHE2VVpOTHdBWkQzT3xONGpQT1IyWWlOVHNDN0tAMEB1Jmd9OHp9MDxDfXtOc0JLQytvKyhVO3FY
KmxPV2pjKgp6WjdpRWhkSCFMP1RDJkZDWUt1YihXIz9HY2RuVThQUnd+e2ZRNSF9REQ2NDA3a2ZB
NClxMkhDMFhsUlBBPUt1dyQKeipEVH56WH0yTV8+e2AjYHhqa2VoaTNrS0pJPiYtXm1jTipQN0xu
Rn0kTHdVSEI7Qz1AWmtAXmNYa0BnWl5pKCoyCnpQfHJscnhJO0NXMUJjXj98Ri00SChlckU3QXNt
UnhUcnMxVVBhUyhRZyh3KiUoO2I2UUAtWXsrOW17VENWWHYhQAp6IXFvTT9rSm99Si1IcVc/PT9x
ZipWc0hvRitxc1N8bkBYQk9EcCs3SnVKQzdiUFVXKG0xPzEhRC04amwzNm53PF8Keio8PEpxR0NX
b3FwakNuPy13cj9KY2VMZ1plcj8tUkpkKW8teTl0UFd2VEBXYFJ9MjY5ezVTQlhqXm4xUzU/Riow
CnpBOH5yN257JV9yYTdUVXpxMTN4bUBXZjFUSHx1TVU2ZVNSJDtBMXxzPUBBQ3dHTkJrOylnUCMr
JEJPV2M8SW15egp6X1NzYj5tX0V9JVA1MzhnST1RbElLNUtIQERYR0pmZUVLUTF8NGQ8eyRnemoz
VDdqbnZnTTUwXkJOJnA1Vk8oPHgKenkoMlcxWiFLRUUrcSZrR2tJUj9fLSVNV1h6Y2I8XiZUUSVD
QmkkIShUWWZ1UjtzUjswYiM/cD5yVURJUFBoKFpPCnpmez1lNytRRkIkSzJBJEBhVWB6cEF9O3dE
Z1lma1FaeyRQQW9KaGV7YU1lWW1NI0VHK2ArfDNAWUA1d1RYUG0lbwp6YDVpbl85d09UU15acjtH
TWdidFAxbD5XJTVCNjsyaFY0KCNCMDtzNUZsaW85QHM2XjBlMGxFYXs2KzZfR1I4OUUKekJDSXJx
SEFxSWlQfUNUVUBjIS12VC1DWE5lO01BKzFFb0UqSEpJP0IwVXNMV1JHREV6elNxQmpxSWNZUSst
Yj5VCnoqbklNbzRUbXhpbSRgRHIwIzBlXjstKCE+YkFONihmaWF8d3ReNTlac1A1KUxofTA5fEk1
Rih0JUZiVHFyZHMmSAp6Jj9YKSg0PHZieDFgfEZzbTw2Y2VORyFwUl9ITj8oRXNycWJWcD5mPU1T
WFAjayszJV52bW5nIWNNSU9nbSokKyMKenRXPGBQeEkkYz03VjJSV1k5cnBFNm5zcEZPPnQlQ2Rf
RmFFMzdzfkAtdyhkWEJqdGdyKj42bDVfUEskdkQmMDJaCnpTSHJ1d3JnQUBqS0lhVGhafFAjZG1H
TjViSXB8eyljPCtuX3lzM1FfS2k8MkVwQUshS3pmIX4pTHN8Pyo0c1h8dQp6K0d0bWxpdSUhTT5u
Kyl0b1MmVl5hWHx+dVIpK2NVQEskIWtDMGZLYk95akZWY3k4ZCFoWU0zZHRWKlgxKmlnPUsKej9a
eVpBPGc2M3Y+ejxFQyRAX1RwYnB2c2t0UFN8WXRSLUM1SElGLW9ja3FraDlqcV9zQCFuJl41TFQ2
O19SKHI4CnphajtKKykkY1cxOyF6Xj9xZ0d+NHMrRkBeeD4/PmJnSlhqWE1lbiNIemteP24/NHFL
Y21XREk/Mmc8aExlMVAjZAp6UmF6diNwP3IxYyk3K2NlJV9uRF8ka0tFTkJSKT1pMH0mJGNEUWFT
ZHxFT21ubXZ6cUwkPklSTiZGfCpQO3ZtfjkKejF4aSg9c2NwYjghaTM+dUVraEEySVFCSmY0MkB4
U3MpWkI3YzIzUTd1Xj89di02VCZuZDcrJSsmWEhYX1J+YVRQCnp3aUBhK2xKRjt7O1N+VXFrIU9I
VDh9aSRjZWplWDZ6PGF2cGFiO0k4JEVJMitjJFh8MWt0QnxhYVoqd0FoVV5UXgp6WnRZPm5TSitl
QDtlfUY7Yj4kcX1xYXU2YkdJPHstaiteU0p1bmE7VkxNV0QyWXc1QmZ2d3tyc1FteW9jUyFVWXwK
ekV5aC14VU1NQF82MkJ8LV5JJmxnQ0gxc1EoKDg5UjJwXmAyMD5IazZRSllEdSFUO0hfaylJRm08
a0hTTHlzaUNNCno9QX5NUkBEI25QJmlQNnVfRXFIKFBFNUQ2R31EMXNDfkN9emleO2l8eXBKZShQ
b3k1THpCVk8+N0dyNDxPREtpXwp6Z0JNSy1TRXw/WFFlNUtFKGZ8KD9fY0d1cldVODs5RWBxTnll
c3sxb2p0NEw/ai0rXl5CUzxtaUJFSGtWZmk7OE0Kekk1KnFGJUM9YzcmOXV7UTE3Y041PldEbDxj
dUZvQW05QF9uaWxIWStHbX5eO0B+YytCc2E3OURwWndufCNOeHEyCnpMMVEqbTNPclVDO0Y8QztM
b09uMSV4SHJQKlUpIXZWKClITDBtM2tKZlVEfmp5KyYlKkFQfUp8Tkt3PzdlO2VNOwp6b3c9Uk40
X2k0aSk2SG91b2c1ISM+OWlAYjFnSzNPRzRFN35RQyMpa0hFVTczRishNVI3bERjQExxMXwjUkE2
bC0KeiZrTDB0SkU5VH1QYmh9MG5PXjM7Tj5yNktGaCY2dUZKND5gQkwkIylOLXBhKVAqVmhwJnsx
ezl3cDBxTkU5ZCM/CnpASyhCUCRlZElRXkhReEc3aTU/anEtaSQrODNfblBGeDdBX1FjcWJ1MXNe
bHlCS0VpbnlQX2dIO31XfiNHUSZRPwp6WHxsSTU2b1goVnY3aElwcEA0e3khdCYrSSVlNWEwcXh9
aWgmWVJvJl98Vnxjc1VxVE8mP00wLUF1IXI9RnZnRkQKelpPUFdGV1BWUm89WEZ6Y3w5I2FlajU+
cj51aXJ9STVaWXdsP3RZZUg4c2ImZWJhcig7d1JQTChXZ19BTDJ9bUA8CnoxVlB+RCZGJFJ8b0p3
UTYwUzg0UGFuPlg7PCQ+KH5hOCE+SGRuRj4/QDl6WWBoPiNJT1pHRVloRE52WitxRUFxTwp6QWgw
YHZBYUVvRCt9RVo2PEdsMGZGI1d0Pi1sailGPDM4T2R6PTtATlhxcV5KTX0oa1g0aXlhUEYhUCpx
NHlwPlUKeiYmKEB5dzZ7Tk10VSo7OVZSM0N6SW9LTmNrJSsyX3Y0KDdXK3dhSHoreUphJWw/UGFg
WHUqVDJSMW1BYClhK0RqCnpHRmhtcSs4fnZSN2NYQTtLPVB3Uj0zX14/c0gmWWVYYTRVODFfbjx2
WDhKbVVPJUF8JHVlUTZwYF5sfV9IIVpJXgp6YDNuMEIqb3NLcChiNGZVWVlvdF9FMHw0UUohLTk/
dEUyc0FScXViKSFqRHd8NTN1QjwjczQ9PGh0N0x2JDM4KSUKemA4OXBOeW12TkNoaT5zbmkrP20k
KV5PbVM4eHNWOXBFSVpUU04qJHBVc3lGMk9AQ2x8PDVibm1vSF9IWj9LYCU8CnpISThHJDd6RyRW
JDRlWj9eIUUxdFo4ezkpTlFlZkhjRHo+ISElKmZnU254TS05SypPbEtUKWA2UkZ3dHU3djleeQp6
eVo8fmZgX0NDb3JXSD1UK0dDRUhgUCs/flV3bWA1MythQm8tOSVvI2g9QFA9bCUtJEhXSE5aP3Na
SiRSU0lGS3gKelVkeTUwY2B9KWRvX3kqX1UjdzImMk1xWF5PWlpyMGo1fjRoKHdueiMtRkJfMiMh
UkV5ZmhHWE5BYDxrQG58dCV4CnpiPGJidHl8K3hUK1dUXkd6VzNnbiZ3VGJqZjQ7TWBiRGo0LXBj
eGlVQyVwR1E9PE11Vl92ejJ4X3l6QyVldmFRKgp6VVFQa0RrM1BCWHk2YzlQRW5qfGhUVSlrViVe
Jk1qK3FMSExOKGJ0a0JpcShtS0k2PH5BRys/a3RBX2dNZClhNVAKenlpKDVKMGBBOyUmaSYpKCl+
PnkhUjRoNFRqNSZuQVljZSZjX3Vna1I4R0Yqd0NEK3tsO1FpbUhEI01yaWdJN3hSCnpJdnt4UDtS
bjhkIXRvMH5tcmlHX19rSnt1KnJjSVFANFppX0dqYEYhPDNJbzRMbDFuUCNCViFqbURpejs8aUhw
Ywp6cEstPDtLRCUrX2hRQlRyaSYkZnZIcDliKUspXlpnWjY9ZHA7bGYzcWY4dlFwfEdNaDgjZlJ7
Pmhsfnt3d18/VGwKeipRe047X1MrKlBCV1YkZE1XaClXT2QqUUs+TlV0X3YqamdBbVIkRzExSFpr
Y3h8KH1QXl97T353YT0rKWFSMkBICnotTGhpRSolJFRuXmdKaEcwYEkqWj5kQmZNUi1FQDwxcnlB
ZUcyezZhRTYlOz57YD5Fe01POXpYPzJxTnVGODlXTwp6ejVWdnZAQjdRWXtQWGpBZCpeKy1DRFM2
X3RKUzJscVhVe3JxZSpre2ZoND08KXZJbUV2YEJDN3lsPnhkISskeU4Kel9TPGl9azdVayZNWUJK
YSpYcXEleiFfdEI+cyNOeGFfI2ZhLVooZm95c31hJENsN0AtNT8zRHdVTW83U3FPYXFXCnpNKypu
c3FwSkFUZCNgfkFna2hTX3U4dzxfRUlEYl91WVl+I1U1UV9RYUJ1KFJjczxnbmJ3UDFxbkJ3ZlMm
d0pPXwp6JjZ9PHQmZ0N3eVI0UyZMSCRYJWpBfWFlVUxzSlZUclomIzI8JXVlXz5NVXo1VkhqI2hY
VTh3KyY3MSF9QUEwQ18KekthSFhZNjJaVWIkbjA8a1YpTyFuUktVZC1VQWxiWiMmdVQ/NGkzR2VS
NFNid01YYDB4cTNXdyFsYmFGYiFBVWx5CnpoIzBLM3EqOCYpV1lTTXtiIz91MCFRdz9mez8pKFZA
bntye1RLVSZCPmkwan07YlQ4ZFI4QEtSeVJTTlYpMjgrMwp6PFp9NzUlSGA1WWFVMzElb1MpJm5a
Jmh1c0VzUkJrKmNlbD0qNmE7fSlYc0R8XklTKHFgeT16YEZNNFJybnR5cyQKekx+MHt2KWJidmRe
QiNeajhIY0dKcWlRT1duNk1+eyYzQ0BEQ2M5PEpANiFWVm0xWWlNNEJnJEs+K019JHtAQk9mCnpK
clY/Z191aD9mPGA1KT5vSHJpVUhKUW5yaSkoWCFFejxCYjduQlpfKzh9fmBSJmBTNSZVIW16UDNQ
fj5zR0Zubwpae3tpPUlkQEheXktxdnFKMDAyb3ZQREhMa1YxbUVCMihiVkYKCmxpdGVyYWwgMApI
Y21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvaWNvbnMvaGljb2xvci8yNTZ4MjU2L2Fw
cHMvZWNsaXBzZS5wbmcgYi9hcHAvcmVzL2ljb25zL2hpY29sb3IvMjU2eDI1Ni9hcHBzL2VjbGlw
c2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAuLmExMzVjNTRlMTQ5ZWFhOTBiNjEwYTY5YzhmOWJmNmRlYjA2YzBl
NjcKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDE1ODI1CnpjbVg5X1dtc0VIKCs9KHFNVEAoO3lG
PjkoK0AqTU40VWl4JDQjbkxJNmZmQFgjaTYqbnlJYzczeXgqVEJDKWJ8Ywp6Kl9uSDBYR2JENSlE
JHBLTmwqYSowRVV2SHRRRyhPMU57akRLdF9hcThNKiFiM0lLP3VEYWxHe2AoJk1VXyt9WF4Kel8/
RW5EJmsxPi03YEl1Q3EhNWxvd1hZMkdCZCFwd0lQI21GNjRmRSNCNjVkMTtpbW47QWQmJWRDYVFu
dnJHQEVACnpxZWJUbGxebnlSPFQ4c1ViY3wtSlBHQjJwVj1abUNeTHViRlRpPjhLU1QqX2V0I2Et
NzlDJmhkVXtKWnpXYXVybAp6O29OYUlafEVFfXZ+JVNuTioqX35WQExIKk1JeSpmOXd2TlBNRk1N
Kk90dXVxbS1oX2VBM2g+dzk8fiUrdUhGdXgKelB7dzEoNGNRbW8haUQ3VUBJM3I3bCZiMCRkJSRz
Vjx+Sj5ZNGdXZ29DK3lZNzN1JlV6ZTx5ZD8hO1ZYfWJad3B8CnpeTTZkTFBpekB5SlV7MV9TRmlC
SVNVSmt+UEUxKkk2RTkzcDw1Y1JgNihqIVpSVXNPMzZeJm96OCk7enRaeXJ1MAp6NEQkKE9EY09I
JUlQM2k5MHpwKTwrbD8waUN4JlI+LXNqZkp6MFFeY2x2fWpMc3wtcTYlWExeaj9KJUMjeH5AODkK
eipHRE9hRD44PHN4OUQhQ1MyOEJhbGAxazM1TFpVaEJPfkB3a2AzP2tiaEpwWCV1REJBelY/MWMl
VzF4eGk0eTRBCnpWez1+bTclRFh+PXloN25gM29tbCVVJig1JDU4O19pNj5CKysyU2pFdEwlYH5A
SDgyQ1R+e3RwMGxLQW8zd1MlZwp6I0tPIXJGNGZqbXhicComNEpgQHwzaVUrRCRqV35NQVA9d2Qq
aVVMbz1GOCpmQ3l9KCs2LV50TTJaSmUqayRLV0IKeiNCKjJ2UDB1fVBPdCRCRW1RKUp1UkgrQnZD
dVlgajV4Q095e0JBK24tS1MrdllhbT44PE8yXlhVSTNERzFXJVVWCno1NSsrQl9vWEVROW1VUUVJ
aUhqVnckdFlmKnpufFY8XyhOP1ZzcigrRCtoa19TMkp0dSlSe2N9TVlVYC1mclZVdgp6IXdhNCN1
fHppfk4qTWltOyZnVHZIKWhFRDkqZF9neEhTWk5AJj51Kl4welhvUU1SMSgqNn1qJXQ7a09NKVVp
c2sKenJ8ITd0TFJOe3ItO1FIWHlkNzV7S2VvMkVffnpgdCRaM1l3dkUjSTlzV0l7S0VBZ3pEQiRs
KWdJaVJjMmF2P2JKCnpuaUtzVC0jPEooXzRrPEdyanJuVUZLQnB3RS1gKGI0Sihfby0/NzF7OCQ8
cFlyOGtJVERxREwyVHpJS2t7Uyl9cwp6X1ZSR3JRZnRJflZCZiYzYnAyKENpe3sxQTdtX25DdVNr
UHshKTN0NG96RDduRllWTTVqTD8raGMwSUUzYz5WdEgKekFmY2w/SCM7OypMWChDOFlhZ2wqdURF
YVB7UWg+cnw4NE9XKGtUWEhYSEZnTWNOTnZTXzR9R3pIc21mam1AYjc0Cnp6bCg8T2ZpPjtuQnZH
Z0dgSzIwa0xoPTVFWCR+MWh6VW5SQWYqIS1uRGtwZEg7SGlVaiF8bHk3UDdJPlo9NngzRQp6VEJf
WUUjR3VTbExQV1JANm1eZT93K28mKFhsUThRYV8pSjNuYV4/XmUxQVJ3Sj8ocTU+fllpNWI2UTY5
cnNKansKeldedyZjNHx2QG5kXzUtZ2hRd3ZCRz98SlN2MkpKS1JXQHVZME0qXk12Zk9QZUolSz14
czhuYEgrJFdCZit1N1d3CnpvNV4+Mlc5NilQK2Y3XjI/JjA0WSlXKiZ9Y1BBM0J4M2xWUlM1d18p
UkkhJVIxfGtWaEBrNnJ9ZihJMy0hNVdeUAp6LWR9V2J7Izx8QmNwUW0/UjRBMGZlNUU4MiVzfU1p
Sl9nK2VQO3tRXmRQOXlteXc0WVh5XjZHPz81dlp1QX0oITIKeip8eDcjWGlCJGJgeT1yWkNsQj1O
ZVdwVlFQMkh9LS1kfip8JE5VYSktKntjPihZcGFVdmMwNHhGRillRzF6T0F3CnpBdzQ2eCU/cChg
K2BJZCRtczN2JiswXnFKdWRVc0VSdWtKKD98U1JJZlRVfE5RX3FjZ05DWHZmUDBvWWdvK2Qkbwp6
VzYyeUh1ZlJDKitlNGZDKTF5JW8hT0RpN3NFeWZIIz54aVEmRkFONVpZK3UwT1BlYWNrLWVyPnde
MjQwI2VSdmkKej1kNXA2I05GJCEpOU5OM0MhcDdaZyhsfDxGfV9HQGlEUkpYM3Z9STc2clFnbUdq
eWNZSzZma3x0flozPUl0a08pCno3MHJhQGVtOEtQaSNkWjlKUmpFR0ZMYj54bWlaPGxedyFjJmZU
QjQ4RjU0QTQlZEMzIUV8YmVxXlBNaiY/fml2Tgp6X2p4ciNIOFd2IU50bk96TEJKSyNqYU82aCpL
cyh8JUVrc15aPD1pRyZgdnImUEVCfVBqXz1LfU98e3MyITI1eTcKeiMmYnJAai01VkxubXdFYjdg
MU98JkYyaWAwKDElUzFjYEJTZzY5cUpaRjRzdGRAeG0oY1k3bjtUZyUlRkN4am09CnpCcD8lNW9l
I1IyX15LQF5EJUpeN0Z3NXxSOVk9UXlVQ3dLN0MhTUBneCMxS1hmcEdfVU4ofXxjXldYQTc7SU1o
SQp6KkhpJSRWQmJwIXJBemRNbm4lQSU1c2E7NmJpZklRYktwV042OFpCPFBmJWI8T3dLVz1aXnc/
Vm88RX19MjxCbikKej9GOTE3Q2VWSWxKVi1SayRfb2hUP0w1ZjcyeigyOXNDPkVaP2dxfitLZCQr
YVBzU0o0JiliYHNOc19sLV5sKV9qCnpIdiYjc1JlI19WaHFQTiZWQ0AkU2FDWWNoPiphIz9gcHE0
cnZyfm9TOShWOzV7VHdvNUZ1VHlpOzY5b0M7UXYrfQp6N2pQYHl6MjJ7P1BfYVFuUD5RJX0/N2h9
LStTUFItKTN5NUNpJmllelp9VEZTVzAjai1ZMFZQNV5xUzVBSWtNSUAKel9NR0Y3e3Awd2syeFlq
a1klaHpjK21tOzA7QnskdnA8dTFELTQ1RWJTazkzbzYqV0lIdGI0QiMhfFUjV191RG13CnotT3tD
Ykg5RENSYT13YiREbkBuTko8WClWYHxJNEBAMHszSWxVTVN8VFN+Xzc1ZTJPUVRUZzcmb20mfFc1
KkU+fQp6V0lkOUImNF90MDU3U3RJa0ZfeXomZDtfaitIUThmKWxoK2N0KUZreldeUmNnNiRtKDBo
ZGlwWUJkbl4xbUcxU3EKeiN0eW1+V14pS1YxZEV2WkspJjw5eVZBeDhpSUdvRU9YN35SbmJ2R2l3
PUp4X1hjaGdfKmJ4YzRiX25pIUVjdD5CCnplfndXZGMmNlplelV1amR6QH1rLTVENVooTDU4VSkr
dWR0bkJITn5ZaT84fTY5QSN8QyQmb1pVNy0+OHxjQTNOXwp6N3QrciNGTWp1TG1WI0I2UypeJCtr
VVp8LWtjIXFKV0tWZk8+fjhuLWBgS3JUbXchPTtJJmhkdXZ0ZVk3UUhxWkAKemg5S1hZJjJCU3NH
MDFUQjE1bEpGTGAhKURgVjZfeC1TRGFsQ3YlZXBGLW4qTFVROXZuIz9GZzFsQEgwVF96VzBnCnp1
YV81QlY/P09kK2wqYyFqZHp7TFladnx4QypUV0w8aDQqdGVwcC1IPm9KTUAlUiZtSzReZlo5OCQw
UEFaN1lsUAp6JGlCWFgjUURxMHkzdXxQM1cqJVU4VVhCbTZvOCFIMGxuX0JGQV9vP3tUcChKY3Rr
a29nJStBaEY2MXUhWiR6cVMKelJCXzEwdSpqb2ZjOygrdWkoQGp5SEpEUmg1MX50USpVeEopQztN
emlGbzt1OT50b0txVi01bSV5STxDeWEmKnllCnpBOTYxJEBjdVc5S2V8cnNgUT4/YF5DSjdnN2E7
PE1PaylHZDV9K25LVz1ZRTUtZSR5SjdAYWQrSHpyQ3grMFImTAp6Kyt5X2c/RllzTVp1fXQzdWFg
WVpzRjBzYmIwTSE4b3lLanw7WDZjb3IyYW1sYitgel52NmxDej5qNDkle2BYTk8KenVHcEkwRnNV
I05eUSllZFZnZjEzZCN1WChTNmZ7fUpjZ1EjKX11dms9ZG89VWZyVF5Bbnl4UWN1PUlRWW40KWZk
CnpobjBtS1UmelZ2OXJGbXpuKXYmeyl0RjlfXnFmNmtxd350V3UrMTRebDIoIVNDPzJaISU7bn4r
OXBjczcxP1lXdwp6WWIqYkFIWGd7TGRXaCNgZFAwYnBvWlJGbE5hRDVJZk4xVkk2ZjVWSFIzSV8q
VTB0bF4+RGEhZ0VKPGZKUCVWOUUKek42ME5ucl9yRll0UiFka204NkpJO05xWUxqfDNkZm1+Ymk0
V3dWZztYLTgxNDQtX31WdiFiYjckezR2PT1sKVBNCnp1fW42aXlkTF9USnB+WWRKNXB4PnxJaCEz
PktvdW09I2AqPUsraC1tdiNkZzFCaGowditfIUNKcVBiZ2Z0Z09Sewp6T3leRjA3fTRrOUs5MTRf
YCtWaFA+PSkkam9wZSZocU5NV3E8OC04WHV9ZlUmJn4rOTV2TTNhRXhWTl9oY31ANlAKejU2Km4z
KChvSk0maz4pVmgpbHZHVnROdGVhbE9ZQ0hnZ0lKZE5la0Mqam93azY/STF+TkB8P3Y3VWNCdEF7
IylVCnpBQXdWMEs2TTdZdFZFUzFBS1Rsb0p6aGZMPC1xOGBtYU9ifipWSzdlYDhgcTBtSUJWIT5j
I25lYXolSHAoMnJGNwp6Mj9gamNCJn5taTIxQ15zazlTSCg4eEpAKXZkTGk3Sm08LSgjNm1fYiM9
WlYoZlJDczwjJjwzRE5RO2dfPzspbWMKemp4QEBJKy03X3xzVEx6NF9FXl44ZDt5WiVGO1I+PDNX
c05FU1pYRXktJlk0eHVkbWA9bVNlZCZgcTcoP1ItTyQ7CnohdDhjT2JyJi05K3lGdkVzdkBsO3E2
N2J7NElAZFdXVzY+bSUzIT02e1V+PSNobVo0ZzQ5Y1gxKH1RYCooc3R2cgp6NGFVXkw7aFJ9OVMp
VnsqYSkzZlUxQllsWCM+IzFCVXopVCVKc1lNfT1Gd25FJUdtN3lvdHR9cDBEQHdOMzZfY2YKemBT
KHc8e2tuaCZZMjJRMnRFTHA+M0U9YGs+YyRWMj11JClwPDltbjQ9ZngjJGlCKG5YIXBrQ3U9WkFU
UGxgKyFkCno+VzF0Sns5YHsrZGkkfHdIakx3RjNLJEVGRHooYVZoP3JBfG1AIz1vampVWDNlK0M3
Pyt9fm5wUk8qeH1hR0NvRQp6RHR6KlpNTzA+QHF0LTUpRTdCQz5SeFkpb0NCajJmeGooWXJWTGJs
OGthc0JwdSEre1pfYC19YU82UGojbXhMXmkKekVROShUbVZ3TSZiVHBOSHVpMUszRm1RPmhCQ1FM
SSY7cENiPExrI1FiUGFwd21pfTktJGVAeTJnU249fSRTVGpeCnpTR0E1Y1hXM2BHUGFwSEUyPFh2
QVowYkROXjtIeXhsJnBBJlMlWi1VNDtWanVUREA2JFgrRnNUQktMNy1vQTZmUQp6Z0Y0MUFsVy1Y
cDE8enNLQjwoSH5xSXRqYHtXaGJ8Y1QwPVE+Xj1GZnNHSElHKmgleDAodkVDJWVqaGNicnE/SHEK
ejc7PVY+Y1hadDVCZyp5YXU2PChkRjBBdyRDRyplQ24mSUV6KDhiJTVSWWUtejVBRiNVbns1fn0h
PTlKNCRnQipsCnopQTl7c1RJKnlkYTdEdFIkdkRlI28yRH1+TlR1PTJxS2g+Y3IpSzk9KXg4REs0
a2l5NF9lUG9LJUYqWms/JFNvZAp6bzdXSDhYM0h9JF5UOWhLQGBPPCR5T01jVm58NnQjQzZTT2di
REcyZERReXl7cFlWRVE+S0BCV2w0ZU5gPz0lYEAKek4/VFlPSyhOVWt8MT5FWTZ7VGp9Y097MFZo
aSEhdFg/O2xnIXpSfmU9LXozeV45fHZBPHEwPEt7PjtxeW94TzJrCnpeamAlK08mKl9aOz1+QG9H
NyZscSV1ZUY+ODJKMmZ2akg1MWwpdjQ4dyYobEozT0YoWUIqcjQtVjZhd1kjdnxnJAp6NFE5UjR3
P1M7JTgyT092aCgyT1R4K2spZz42SH55d09jUj4yNHlzTE9rI0tEIT9ZWXJqRnZ7fUxoMWE4aHF1
Uk4KeiFtUWQzMFl+ZjQpTkVKJkFANH5CLU85ZEx2Q0hBdns8aXgrekxWX1ZSLVZ6Sns/SzJzSHha
dklRQ1RhUkRVIXM8CnpLaUtlZ3k7V1RGMDItPjctLWA/ZD1KTjdQbHRmJlNCUlgoZCRQSSE4XjFS
bnxgNiRRQFJGKCtgTEYoaz5WKHxTZgp6b1k0Zyt5NFVvKTtEbTQtcyQySiMhak5lYW9QNTNWJWBE
M351RikzMXZuYiFRREFWMnlPUCF5a15BVX09MT59WmQKenEob209JXB8JUYxNSRGJmVSNCMrb1VE
T0ckTytNWmk3UTdrTTF3YlJpeD90JFh8UHdyJjBTbXk5flcoVkJRIz07Cnp3Rnp1X15TUGAtZW9o
aDkmbWJBYS1qWG98aGxncXNrKztNQWwxUnlWNmQ4SFdLTiNqUnUjX1dXTyt+NVNGMkt7aAp6KiZu
VW1QOWApT2V3OVlAYV5PZ0FCYlU2eHBxZUFXeDtAKSRUZ2xsREd0OU5QKFZ6Jlk7ZWAyNERPPm1f
VmRCWmsKej51aWxBZjwmPHBqP14tVm5sI2koUldYbEdYfFRgS19PbyhFQ3QqX1EhVT4rKi1vcFoo
JWtGLTxMRytBWlhwbk14CnpKRXFUX3s9cnBqeHlpXyRPfEFsRTxsb3tGVnhOOFM8eHgqPHZZV2Eh
IT4xdmVnYDMxbV8wTUhycmItVjlQI01eWAp6dytAQ0c8flpSUHErM2kxM3khVCtlIyNAanszWSM0
YS0rbX1reXxaUHcxa0tsUnBKNzRhfDFDaUlgOzN7QTFtRFIKejNgIW1zPCZQJkZpXnxDaGdEQ0ZB
aGY/eyl5UiRfYSY3NCZEJEVJPmRjNUZqJC0zPUtyY3grYDZeMHtfSHE2TEJyCnohdig7RlZDdGk0
eSRJPzh6d0ZkKDR7aSNkR3RjKFotbCNtQ2xFPzFDZjROSzJLLVMkNUBjWmY9RWE8S08/YlVJbQp6
RT9uP2gzZWdFJj9XP0plMU9hYX1XaTN+SDFDOUpvRXxAQGomSkd7QXc2RD14e20zJFZ4RnhyJnlF
NF9qQUQjVU4KeiR8O2VWQjx8dG9SM3tUaz1oOVFoWnhwUXNLPStGc3tzJjcjSFM9MS1SKz9hZm88
PVl0Ml9GTG4mMlI/VEthRmxgCnpGdGVMPzMmU2tLSHV8fm1qPk1fcEBnbWh8O0g5YzlDfShkLTE5
K0BvN1UkSDlmaipsISR3TEoxZTtuV1RHPXVsUgp6cWdWTThpXm1xdiUrUkI+IVc8cTclNSZCeU4/
SG1sNFBfdXJubmdRfDNZLUN4cXdzTjskQ0MwbE5WYjQwPGRiUlMKejhITHFqVl9TYChIP0ZPIUU+
SntiPHNMbSgmbHs8MD9HODRiUXBTKXpqOXtVNW48N2VDS3A/cjAjRk8raHZiJllhCnpybTdrMDYo
WipWeXo9TEk5M2Q5fT1MRnFyaChLcUElTjRCaGkyemxjTGAwPnctNlNGN084OSU9eVZMOTNrQyV2
bgp6PjcwPzBVZ3U2Qk5QS310e3sqKS0lViVWcy1NJExiPj5PJCtWS31KWVhDZmc2JCNvKEpIeGt0
eUBvMSpMMWIxODEKemVOQWd7RF8rfnQxI0tONk5NNm5kMGJNUTBLeU9EWCFtbElEdnE+V3pyTjZr
PzcjQUc9UlRoYVEtbjBaVW5Nb2pTCnp2Y089ZmFBV2RHTCRyIXxNUmFtVVl9VEtGOUBZQSlQYV84
fFNrQUpfKSsrU0JYb2ZGaVJJelVJVXFEaXpOQFlYKAp6eFNLNXFSbFlWWjJEOzl0ZFRZMWM7SGVB
QVJnUmExJVV3aURBRk0/UlJPfXVgeGREQT83WFBqN14yYWBiRWBxa2EKenNPYDc3LXJ8RWw2QTl5
QVliTElTOV5TSUxSeGJedTMrPlEmIzgpTCROYSZtZnswTDRHPTVWYEJPWW1GKVp8Qn5xCnpuKzt0
UXdDTlhFMUQrfTBeJiQ2ajMrX3YjQ0pMJm9TMEI1KzZNOSp8c1QkSWM9R2NHVmMpMyU1Smh+eGV2
YnhUQAp6RVFIfGFmdDhKaGdjWUU0LWU8R2laJUpOK09+UjFUMmhFYE9eRyFJT1kma2dsdSN8TGU/
YGIwPHhwZXUkQTVyeEYKeiRjVXh2K3dUY25jUlJySEhHOXhtdUtSOVBieH1SVEIkTk1wZy1EbFVt
VkJSNm9XbilZMlRsK2p3JipDJS1sKWNtCno4MXlkVVk7I3Bhc0l9QXk9ZTwjPSpySDVFKUVhe1Jh
SkR7eShlKjRvTnF9VEt4Z1V7QF47OGxmWih7Yl9xPStWdwp6aEk3emFLd1BtTWhLeVJDPkE4VHAr
U3M0V3dCX3BJdT0mdTQqfDJmQDlFY3VhVk5yTzUkLVA9Kmk2I0khZXNRYyQKenY3Tk4pY3F+YUQ5
UT9pSV94KVphUl4hRGxENVIoOU1JMWdGeCtCa1RnOFE8TnQ/fkVvX2heJigqUVh5PUpLYHY3Cno9
eWF3JmV0b3BRYUJ0c0EtNig5KkRQfGs/eHVUIztYbV5+XnJFOzVac3VNd201PHdkQGYyOzdOJUcz
YFFeZFJFUQp6Jn4mZC1IcldBd0lWJWp1dmp7eWBOb24pYHdsXnBlQzwpUm9HP1VJZiU3dUUqNn1z
V3MqPzthQFoxOX17TkskI2MKejBlOD8lKUYhK0tvTW9jUz1TVnE/SGZxMGA1cUthSGxQYDlKa2Jk
aj5aYWp6VCVLOyZsaU43VCFzP3otPGo9UlhRCno0IzFTbSEtdnoxVklnRWN4VHgrN1RLI1Q9Y1h6
SWc4O0Y/fDlMejZqTzB2ITc0Rk5rUFEjJUNfek47anJmaTBWTAp6ZExuTj1hSDZhTz9uNSpxXjk4
cG5zLUZEIUF7UzwjVypZdjV7aXh+ayNqcDc9OVZ5QjVxY0Q3PDw3OHQ9dXNRUmQKemElYUBmMV9r
eElYUktEb0BvWjR5Q1dhWXF5X1VBKSp0SW0wWH4hVn0+bzZmPipQbzktc08lYmsqa1ZsSkYhdXAz
CnorTEE/QEJ0OE1ANCtiUGdISSM5ZCh4QzYmen5GNUhWUG9AYWBjejxRMWZgdUd1Y0omUk8yeUVL
UGJ2Q2V5I1ByKwp6eTNIeiFMXjJPPDsjUzktYXtaRFQ5VmN2Rlk/emRwPnxIfnJsfWYwPj5jX3JH
WntTXkcrcVA+ZUdid0JLPWpNN2QKenJMdXtuPGw3P0BEdW1FRXVvO2BqUWl5ZT5YSHY5QWBLSmpM
R19LP3ZES04+PW0wOHFOfEk0cSZRTX4jTD9tJGttCnpfK3pzM2spZGtLeE9+RUBTP0FOc0xTazA/
MzdKMExySTgmTll5RSt6TFVGbHRrWUAhYTtqRGp4MFlUdyVDMX1Wagp6c2VvdWYkWSExVG9BYDt2
QGpTT002T3FzcFpYckhKO0FXflEmI0huVWY4MVVFZHNiZE5LQzElWGEkUVMmcElTIWQKem81UHw0
Zk43LU5iVH1PPkFAWUZSK1EtVjVTdyZTc3NMVUVXITh5OVhGVl9FJTxEMW5PUDU1cGshejNwYmAm
LVZfCnpsbWFYTyM7TW9CRkJHTl9LOWUoUXcteEhzV0R+O1RBbjVXYDhhLXp+eXVWQ1cydmpgOyZX
Oy09NzJ3WHpLNzs0Xgp6VlZuVzlSQnRaJFMySj4+UGtvNyMjZF82cjQ5bEB1MzIybklfXz08TVlG
PGZVQk5eUWNrYlRBJjxzTjEyIWh5UkIKemo2OXNAQ0lxVG5AdFhtd1dGPWY2UDA2NyZZWUxSQ2hu
JHNSP182TShIMnVsSyVZb3BDSGYxc1M1U3VaQClIUGRBCnp5JDw/KCszUUZLVEM+Pn1IPUBJclhl
fUNzWkIlSl87YEBKcHtVSjVMc1ktRHhVT2R6PypCRmg9XyU0QzloQ3NrdQp6cVgmR1JydUtIKT1l
R1R1b0gtbEtTZWpkK0Q+eStVQy1kUDJldT1UZEhzQTxDO0NQcTUyQlhFdj8qWXc+KTlmUH4Kems2
WEpEPCErb3BUQENNOHRRPEc7Q15za2NgUHUwJXM9JU5NRT5TKy0/JGxnODEpfFctUyhVbmN7NGI8
OWgmX3JQCnozbzV5bkxBPEw4SU4rYUZaKClWUHNqTWJGY1NEdU1Mfn5Rb2tyWVpeaUY9O2l8MUg9
IUxySUpgbVR1V0JoTk5KKgp6VjgjfWtoeDY4ZSYxTUhjM0QoU2JzMW5idDtOTk13aHtic3klb200
VDlWd3VNT29jJklCZEpSPFQtZnd4cnhPc1QKel56TU82MzZ7UTMzNkBMKWNVRFVybUdeaUYpJipI
OGszJUtvKShVcHYoSEMzYHt7KFVEYFIhVz5mPkwrXjRBU3pYCno+dmhqNih2PnlyKi1SK04hUW5z
V1U8e1JJVWJfelgmN3Z2WkdQNEk4JT99SnQrYGtGSURJVU1rbkFCYnB2RnExbwp6UyFrPVhLIX1M
OXZJU0E0eCp1e2poVFVjMGNLem99S2JkNzBvXlBqPVZMQSVJVmRGTXxQRWJtNGtMeHE0c1VXPUEK
elA7fT8lPzdmUyYhQm9EYi0/RGBTR3NZU20tK2FxbzFFWFJqP1MkNj5LZSs4Qj5AWF5Mc3ViPlgx
ZjxVa3dmM1MqCnpFTTF7dkopRl4hSnw9QUZOYWNxUTtEfiUkPFBEMkBUbXYmRGpOTjRJd2VCJVlY
QXtyJUQ5QlU1REgkR3QwdzU/Qgp6cX4tPWtZfVd2M3REVz5mVCFvbUZtUjE0ez8tYVR4ZWlQNUp0
QUU9KnlPYiFET2ZMayh3JlUmdFFofCtjTGEtWmEKek8/dykmQSl5Wk9sTzElLUZhJnU/I3JSKSot
Pndxe1lkU0o1QE1EVm9OTTdFdTN3YVdFYlZWQWM0OVZ7K0l9UHY7CnokWjhydz18aEViYTR3VTx6
ZlBXIWk3bEo9KTlffjljTCQ/aVkwYk0zc2NvSyk/cnBIK1F+bnxYMmw0ZExjIXZQWgp6NShkMmhl
MnUxKm9mWTkwdnp+LV9SU0FxTTJMN1hBK3JJZzBQVlkwbkFXQ0VkZGkyfDkxfGdAI2hXPipNVHR1
Xl4KelZuPDdNIX1lZj1DNFdEYy1OaCsyN2clNHMlU15HQUM0RDl3YGBPI2BpKiZMdUd2Z2E/YmJD
SyZQKkhBfXZ+TXA7CnpDd2tDPjF7N1FNakBEfXwoeklQTSEyNSlCQSVyYz4+USRXRVVxNT9gMnYq
Knw4QCljdTVePzdHTGR3dHZGezZFQQp6MEJkc1VtQWdLaVNOXjgjZSU+fHhSSCZoTXZoUmE+KzBF
TWwhPCFNOUNFPzc0Iy1zRW9ROU1tUzlzSEIqcy1afTwKenxNTEtoYm4tWCE+dn49X3F1RlpNdnY7
ZEpkVk1yKU0pc18ocS1jSjAxPHpwS1IlaWRsZDZic3V0c1kyclFofjVnCnoqV0gzbDJHWEFvbWl3
MVYobnZuYnN1VkUmKUU/aTdDb2MzPSNzPzJ3d15MbzZyfjJVOVQjb1IyYzM/NkJuSFQ+ZAp6PTdB
VVdRfSROYHQxMSYpPm52TCN5IXs7VHZeS0QhVD1odU4+MjJSRyhrPH1TOTZ5XzRzWDc0K245QW5l
PFFISXQKemAjNk9MWSp2e2l3SUpuNTFeNWIlPG04ZXBKQUVLNVBRTzQmcDFOR0UmRlN9amNHUmRw
I1NZPl5jcDh6XlZ+UHE+Cnp2YWkoQWQzLUI+PC1GJHEhWV94dD1WKWRyeH1fYkdvI0FePlZoREpg
bis7NVZmWTE4MzlAQWp5NEg7MntvdWFaegp6K0UxVU1CcHxpQ1dPKHgldzlJX3UtNzRrLVBzOFRA
IzlMfG0tNjl4SlFARXx9MXdhaiZhVipEPTdAfGNIQlBYaH0KejVMS1c3ISVmI0Mwd05idHFIMjlw
YzJXRFFZUis+NWZoc1N+O0wycCZkZFpgYjE4a2gwPjJARyYjeXBeMmRFeXB8CnpKU2pEI2t4b2NR
Zjl+bUhOSmgrKDJ+KHEkc24yOWtKbEEqMmFycyNpZmFHYXRRNDdEQGE8cyFNT3JjNGhoVjErZAp6
I2dgc2tmWng0NWxXZkw9VXxLT0I7Q3J2SzElU0ErIyZRJXl7QU5IU3lHO35yRkFqVURxUjM7NHJ8
SkwqIzxtfmQKekhpOGtUSnAjMnFsND9xPTJfWVVnNnN6OSlWQ01kRVQyK3lWSXg0aW8kYTgmRVA9
YDlnUTMrU3U2bVF4RF5GbmBKCnp2cGtUJFpEWHl0SH1oVnxLe3JOOGB9UVVoOyE+WGp0bVplUHt1
THZZVkFwLTk/azhIdllhcWB7cXE+Qno5ZT98WAp6Ui1aMzJNbjVEKiRKZSM5MDtaeD0wKEMxXjxp
aHlTbzFmNDNIOUNIdGBxaXk0b3N4ND5rXm51VUstWVEpdnw8IWYKeko5Y2JQaiErVWAhdHdkbEZV
VzI/fEFRcW1nKn4qQmc4bXo3I2wtbSFtODleNj0hIXVJPzdeaExCeUhedkpIPi1DCnpFK1dXVjJf
cUA5TkhYK0BOQ3x2XikwUHhXME5BY1czSEQpfVl1NnB2VyRUZTBeY2MkeWsrSXgpaWQoT1ZkbkFw
VQp6UkBPdzhXKnpZYCF8WEplXnh6QG4xN31EZz9ic2I3Y1NtUzZkRmBxYUYrbExxTEskMG9SVjxD
Q2M4SyUya3t4eFIKek0zQig8dlU9dDYwMWBQQSUzKS1SaiE8aS1edz0oYTJCKmVHYD1BXktQeyQ2
cCowWTxMVWQ3JFFQNXNFPjZqQTZDCnpveER2VFc3KCk2cFE9YTlPUVFaQEU/QzlqJX1XQSVfSiFi
M2M5P2xRITRjKlhEY0o5eHU3eTcxcmQ4MDRqJmlLeQp6bSlfM1BkXlJXYys+Qi1DcGZ7fWpELXx1
aGklSiM3OzZIUjkoVnlYNlQtakw7eGBSRVU3eUJeKXVwWEk9Vz5PPXAKemRLWmBjRTJYV0hLXlZz
ZjBkbG42di1vOT5pfl5yKVphNVNmbUgze2l5dzk5NTI2LUwqPktWNmp7azdhMU82JX02CnpvLXBM
PGE3Q0YtPmF3I1dVfT5DKSFYXlc/aXpWSUhCZTttSEtkaWNEbilLP3NXYjNlXjcpYkBDPlhHJmFh
TTx2TAp6XyR2PDkkTWZfWTk+RDxzI2FpT3VkMm5pdUMlcTlqKitGOEdac3xtR158JndAaXZZP2M8
YlFeMm5oaGlJWDVYQnoKejcpPEY3a2tXbzh1Qyg/bihjYzNuXlFqbiVHWDFRNytoS0dvWD5HandU
YzxfRkJ3RUN4Xmg8YklQNyF+K25JN2JJCnojan5CdiYoaz5rU19OQVdmZE5STT5HR05AYkY1QkFr
eHprckFuMVpFPEtNNUNLJlZGfHdtNHZjNitAQmRkb1p0bwp6aVhoPy05fDdUd3cleU9AOEIwdCp2
TXckfnhPaks2TF5jPWN7M3UwTWFoeVg8V2RUb08mZUh7ZSl4LXVZTFhxSjEKeihGfj5oKFI1S2Fp
V2g/WF85MUdtKFA5VHQ0T2o3IWd6c2JeNCZAWG9BNm5IO1heWk9FRkdTOCtiI0c+cUR3P0leCnp3
JDg7fEA+aWtmPHcwQGB7XnhzU0xRanN0RyhjT2YhMShNZFZ9ZTBLZFNgNWpFPHt4diFHK28/Vy1F
UzY0MUteZQp6SXojYV8wP3N4TVMwUVZtPHRLdWo3JnMyYkFoalEkR0smUVZDSCFaJm1gMjlCTEF1
U1Q0RSRmKGtITkZme1FYJEwKenhXOSNsVyptY31mR05LaTVQKWQ1YWAwMmpefEU0JHBHZzY8SGdN
MmMkJSQ0fil6YSVmTkRmQUhUQH1kO0dZJXgqCnpxIXp3JW5Yez0qP0lLOEcoMVZoQiNPJV8wR1g8
TlMmNS15fmNWUzNjRE9kdCFJVGA9Kj97QTtldX0oQi1LRkNTMgp6TWQrWWImU0ZATnlKZW0+a2Vf
R3I+YmcreHMmPT5iN0B3QnVhdyo1R1ZFdD90NzxvXlk5NT5MfVUyZ0dUPWVEcVUKenZ6THNiMCZB
a0t6MExwKHgmaVJXNFBPbF9kcVpUfWg4K19CITleMnZAc2YpeTN0VFJMWEY7aH5RWHt5cE4wMHBW
CnpYdyVqQTY+c18kNW51KWAoK2d+fEF5d1FGbTRzQFdoamxsQWo/fnFCZnFLRj1TN0gzZyU4VnNI
eHp+MSRgcX4pPgp6P2hvfkQhYDF9az82ZzdgU3lBTnVsbnlkQFpOQDVYXks8TFIwS0BqSG83cEVF
VGxZO1FKeyZmNDBJWEkwKXs9N2sKejMhLTx0SztkVypjUUhOWDZZI24/WCoreUBUYDwtWEVuQi0l
OWckeGBYKnh7K29ScUYrcHltbXk0ZFokNmN2Vz92CnpmUWp+ekJhbTFMbFVhIXpzTTZTZDdacDQ3
WSRyTEpoPnFMUyskQXZVI0JEJGk+cTNwTShwfi1CYmZmSlg/cjUybAp6VDZLNTIjLXM+Q0t6ZFU9
eikmbD1wdGghdGtudXJrbXtCSGc5MHA8NXV8NTw9QDtkKkEhS2A4UldpSFQhdklKdi0KelBVUVhK
MThBcHp2bil6S2BDQGxHTnsja2ZRKnlSSWNLUkRQK1koWWlzVztzRE18YyRKLX1vQ0ZQaDxnaUJ0
MGc0CnpGeH0wZWQ5WUJLSWVrKkkoQzI0RHg4SH1qUlF7az0hZnJ8alBaMyFkO2hqTjVudzJDK1dk
VzJsdnRSe2Y7R143egp6JmF6NTRLfndlUFhaKjtyNyROYjZpTUV0JT4zQGY7eUxLZT8hUWFodVlO
UERkX2Nzen1yNGN6MWdXajhWPzNucTwKemlLbUFtS3gwd2AyMjRNayMjVFAkNHJqejdqNzw2dnJy
ansrdkJ6NFEyVDN9VlNyfUBldnByO0ZCUmZmVGNnVHBlCnowTF9yaj1vSmdWaGA/Oz4zVjNScEJZ
dTV8JnI9NG0/P2dfaTB5dWk2Vnl3UWRaeXM2dTFwaHN7WGImQVEhdm1NSwp6TCglQmBZeWIzY09D
M2wtI2pkcDh7cXZOdS1FWkJrRGptZVMqTD9uZkpaOD10UypBQko/RVNmNE9TJGh8PU5GeCsKekgh
ZWN4RCVhSEw4UWUtRFc0OV9SV1pHT1J7Ry0zZTA1UihYeyFEaThJe1pGSyVvTkQ9PVQ0fDJMKnxL
R0V0fk1PCnpPY1YpIyk2TUVweDYkYnJacHFFX05JJUMmWF4lQndvJCRnKVNXMGU9Mm0xQU1aVjJz
eGpNMDIhOGJjd3Fyej19Vwp6P0pSQ0c3Pl9OU2MydDZAaStwKjY0Vlk2WGdFWjJVaFpvKzNMayE8
N05wPn49byNBcEJBJntBS1ZUekhOZUxKfDwKei07TGYoI3drM0RvOTJ6ZT1EOVdOKyN6dUw7VEht
TnAlWk07KH42ViZsd21iKFdnaTNYZHZoKjkxK29CfU01Zzc8CnpOOV9Rbz9rd24/aHkmJXVYdF49
WEd9KVczTF9RNyYjND5+WEZeSWxSMjxRNm1wSGs4TzF3Vm5mZHNPaCV3dDgyfQp6RXFZS3s5cVQw
aTw3JitUX0FqY1VDaCpkeTlTejIhJV55YGVpeTlPYktxST1zakVhKjxeSDJhQUYtLUo4I01DJEcK
eiZnciZ2VjNebCo2PGsqSHR7OSRxS3s1OytIMlBwTj9USm55e3VTZDM+Qy1ZO0tVIU1UR3NRdFRD
Mjx5fURiK2goCno3cU4tTHlkSVUhODZaNmFUZWkmI3k2PzVySGpiOCMhQUNxfTMjM3tTdzhEcClB
QmZBPGgqNlVuVUQ1QSM/aWt0dwp6VG9TbkB4JVNfanhsdD0wdF8hI01FcFF+OUszKGF1I3hQUURG
MzU7SDhDKWNLcTtWPUNfbGo+amhrbE92UUBoV2EKellaezEyPSpkPTB3MURESSVqdiskJGMqYzUo
SEtKNzdQa3w3JjdLcVN3e1JfQVkjbCh0VE1UUXU0dU9ZP0xuI2E7CnplMEQ3dTc/c1A1c3YqZjVv
NWxabl9tfExCdDI0MWNMZFF7T2l0JTJiWX1YZSFpUSpXK3lsUyM4ciZoRjxDO0h6Nwp6SCsxKHUt
bVRXfW5MaWZfNklhZmJjNlY7OHBNUjFiaVJAPl5hUCMtd0dmNFMqbyNZZ0tNWVNLREFKblFSdG9v
enIKemohYSROQXk4dkEodXBAWHtmSSNAJH5PUDM4PnYmQHdWdCQocllLT249fXdjSTdJQmojKnY1
Yjc9UGh8WDt9NkhOCno0MVdPLT1vTWlNdDUhU2ZqLUNeYWNBRjRZYysrVyhNVG5wRXZUd2BqbWNK
SEt3PCg7TnpPczlmWUoqO2JZJURlMAp6Yj9UZXFlQ242TG89Q2pKJH4pfX5Zaj1obnE9bWpIZURH
b2FXLXI7e2g/fFB3aXIkNW5uNG9LR1QjUUFDWmVfJSYKekN8Z3dmcWhjLU8xeExFUCkpWCR5Wlpa
UVU0eGkpPjJGNyU/Rj0hPnNZc3lKXyt0bWhALVcyTG5CViRyJkxfKFM7Cno8aiZCWnskM0gqUVZ3
ZippOEh3SFBCOSpEK2IrTzNwOSRzNil+IUomKy0kczdsVFE5O0tYIVlebSQtMVpkeSMxcQp6VDA/
Sl5NMiROWG1UTmsrbFQ1Vy0tQH41fTQyJj9IcHxFR2chZHcqUXUrTj47anFDYnAkJkh9UWVAKUxC
THlPWHQKek14TUJMY0I4aEw8ajYyN09CYmxVb0hGdDlDS1EobDRmTnVZTnZufUlEaURaMnVEK2N7
SV8lYXs8KjIrYExhSnR1Cnp4LTxMPEh3M29edmg+cHFSTHdHYDgye3FkUTlKSEQ+fVBsWHtTJVh8
OERzZFBpUTl+KF9ydjs7SD5WSFdCOT19bAp6Q2Y9bzxeLW5DWnVHcS1CUCk1aCt3fX00Uyl6bipU
QX1fQWRJKXFOUVJ8S1Febmp8ZUZnYGY/MlEzVCVncDwzQ2oKel9fT143S1EkfVlwTyVZKnskMCg8
UE9ieWg0OzFrSyNrTj9ieXxMWVp0XyYyKndWMFdhQjVKXjRIQ284dkxkQClzCno3NDI/UWEmUGdq
RT9ZaFZTM09zODU8eXNBKUY9KFMoYjQ2VT55KF5pe09KNSt2SkgtSmRuM09PNjliVlYxaSZHYgp6
QU0jZzFVcC10JUxEIyk5akNBbWFeJTJBVStrXkA5emV3YWhoUkhsOFQ5O2g0U1dad29xdGxza2Rn
JD9AYGIhdTIKelQwWGNNdEApej1seSM2YHtBTHt4QFlDTj94OHdpfWp9I2I9bHo+KlRWKVp6XnNp
U2ZFLVAjN25SQEhjQkxKfUFPCnpJP2IxZip7MkN7P1FnaD13ZjN3XjxadUs8ZGslPjBzKHt0SkAl
YHZhR2BsfmlxflVSWVlfRDxgVihFcURzfG9MWgp6aCs2UyE9OWlSOFBkVTgrSDlzUDZWKmYhbHJy
ITtGPEc1NVhvWSE8dXNvLUFwYy1Wd0c7ajl1PUJYWGlkMzsmJX0KeiZibjI1NH17c0ZhPSg5bGBZ
dWtzTkh9bmFuflVlO2ArfmQ5Y1JgIS1VQzc+fGhUN2x6NXJNcSk0dFBhQDJ4ViEhCnpKbmQhT21X
bFl+PilZKUJBRjQxVk5nTUV8PGB2dmduYmRXSWoqPHg9MiNafWpuUy1KJmg0MT99VyFJISMhcTxB
VQp6UDxib3VsKGFxYkFueXMwYyZKZ0R7b1ZGa2MmSTY/QGxVPlooIWBUa1NmbHtCdWJiTkE9eDV1
ZkhzMSZMRV5Cd3MKekc8SDFQcU9mUWNgb04oMFYoSmU+WmFEd3BhKVoxbk1NQUdXcWFCbFIkPTIk
aCF4eFdNSExhOTE0TGcmJG5yTWwlCnp1RTtNLVlMVTN7VW95bThgdnQ7c1JQaDNycXV4Mk01TTkj
ckxlPW5VT05JTlBrJXkqTHtaKndAJSRsUElHbTkmUgp6e1Y4T3BkfE1qY05EMDA2JFpCI0JPIWJr
OFRCd0ZzcjQya1lMRXNrKTMhSTZgJHBmcnw+aXkpaShIVGA7OTBjbnsKekJiTXYmOS1FXz5hKzZu
dTthXkpLXn40ank8OD5VYXR3JmJnTWg5P3spak14ZEl5V2cjTHo7dk5ZcTRHITxTZFlCCnpDZ310
Z1RVSS1hPCMyKkBlKHtEPW04eFQtemZDVldJfDQ7KE84VHxAenY8UVJgVGNJQFdAZGZXTSFhMTBV
bzNRTgp6TUU9MGA7bz1ueEd4eDNTaUxEd2UyZ3g4TzVBcSl2YSRBIXJifEw4QDJyZm8kPiZUZjgj
SC00XjR5PEUxbVNKOGkKek01ITBlIXNFfUxPTHZFRUpKVnYyKGdlKXUhPCMkM3opbT0yUEtwZn16
a2I/cTdkMUwoTkoqPX1MezkyZW92UUd0CnpucjdUfU1KOStxbmFhdksrb2Z9ZzY2OU5tS3hBZ3U3
YXdPKVJicVlUcz9ZWUUzKj1WRGkjfVQzVTd+bWEjbDNRRwp6Oz41U04jOUVuYjxpbVlDMHRGM34l
bFB8QGx2WTYzXyFDcEpKeEo4IWJKY2dLUDMwUn11JHdAO0hFPFQ/cXEqV3cKeiZpWmgqKThuKml4
U0VgVD9AO15xWE5DQzBNO19hNzZLclo2aXlDfjdabE5iJUJSIyF0ckYyWiNxUzl0N1JBfHNOCno0
XyNlT0U+Tl5SK3NTb2k5NyVwZFdIS0lWYnN9dyVUWH5SdVlqdCkqQ01DSz5fSCg7NDQ/ZD5TSntW
O29ge1EyNAp6I2I3N1ZgVVlFTUFQSUpIPUg4JipfIWJCY2Y5dy1eQF5tR2Z7MSp3dld8c05RdElX
a2g2SC0mcWd6UmE8ckNoQH0Kej9DTXZRPjMpNXFONF5qOUpFQ3goOHNONSFaVD0pQGh2YzIpalot
NFJvOVJpeWB4JS1pdnY2RnRVIXtKJSRqKXBvCnpzbjJ8MUg1ekY3UFI9fWBtQ0RyO2d3b0dKT3sy
dD9FTUJ+OEE9eygwZ3NDPn09XjhOVXhAeCpVLVo4S3lzenEkMwp6WWxPZjZ1WitoU3FxSmY/aVhO
UzRgNS1KOXN1IXhyWVFXVTBAfXRofVZeO2N3I2gxb0olI1lZbjhVKDVHXjEpSmcKeiU7UjtNQHJJ
dXxNMiRIVEd7MEpYczx5RipYMGI0TWl7WjJCY2VtVW1DfDBpbFU5KXc7cShHZm8kfXg/NCpYOHNT
CnpyMiZiP3l4LTxUVXV1JUY9Km9GSEY3KkNkZkJkd0ZeVHBAKXplJnFFODFpYiZUQ3A7WDF9O2Ze
TD1zZ2sme1VlQQp6aVg1Tyk5enZHQUVRa3Zpe2ZGfUJUKml9Qk5eJn5DK0pzalBeTkwjMk5TPztP
dGZFczMrODlqeXBJPX0/KnRaRmIKektDVClyc1Qhe2lLWDt9PVpsUTdnNEQ1dXg/cUlkdmRDPjk9
ZEsxPmd1SWYkZjRuZylQXmktbEZHKmBNdVE9eH1rCnowV3Q5REZeYTtCO3E1ZU1TbFV1dDxyWiol
SVFBI2JRSW5SM2g8QGd7X05ZYGVIN2FEckpWK1Emc0tpSjd1Mlo8Wgp6MWBPTD9MYEUydGgjT3Fj
Tm13fFQkJSUrKm0tV1czV28zMFNTeyVHdTsqVWleIWBCOURNR2h9bil2RSg8Xyk9dSoKemxzfGpO
WnBgMWlERUpiSjZmZ0BwJV9MQHMmTyZYdVU5cWRaTWhXSDtgSWtxRjMmY1NGZjFgSXxMdkIobHV4
YHFsCnp3T2sqRmdeSztEdUxQRmtWfEd5aFFhRGtaajV3NTVvS1UmIXdAWUp2YW05QlV5Wj0zZ2NF
YFE0IUBOPyEtTF52Iwp6OzJLan4qU3tTdUg7N0RwfEl2WnF4ME93eWx6OUBoIypiaHdrNCR0aWBv
MDNucD40X2A9d35xSENwOEEmMnRCZlIKenlmVFp+PW5tPEtVKD48VkNGbkpSe011cDdiP3MzJDE9
SipCNzgheTZhcyMxPkFxMHxYTiYxZzs2d0Q3ZEY0a1p1CnpsQUFrJDJuWUNuIXt5LUdzUExKT3Aq
dntkM0R4ckJXKSpAbnJKOy0jMn5TPWxMMFhYJkdnKWI4V31hMEp5TlkhZwp6ZzJ4dWJ3S3lVQzEt
NiFkKl42MVpKYUg9QVdzZXJnMDB3cl8kPkRzfTd6aUp5QEAxQ21pQVJKJms3bGZCTV9NQXsKejE/
P3hlP0xVdmE4dztPfWwhMXdjYntlUzhuSiZKJWNaQUMlQng3ODx6eF4pPHR3ezQ/SXQzR2F4aVVp
elJjJS1LCnomUC1ofF9QeVhuMWdJJTVxbV8wRmVZMXh1cWIlfndxRyNIeFh+fTJeN2peYHRne3ol
STE/P19CRDw7T0xVe1BoUgp6dWhmKH55QDhxUmBod2tDXjgxZkUzRUA0fHt8Mi0/NkNrNVVKanY3
NSM9P0RBR29VNn51OU5iJlJudyFMNXVCfSkKemMkKjhNUnV2UEo9N24oe1BoUkVrcjFGPCRFeERl
MWZsITstVHB4ZiMqdVlgdFRNVTRuamsyWHYkKCpIKzN7bHdICnolISo+diE9YTF1ISolaCVwSTQq
ZEcoaDQoJGhvVWYoQ3NfN0xHS0Fzcks8fXY7JjNUfHE0JTVOVWQ9SyNtZD94NAp6aGNETyhFblU0
QVlxQEhlemN4QFheMFopVkp2eSVgQ09vRV9GVlRkYmg7cXNaZUp2KWpIJEU9KkxkXmpDSF5icjUK
ejdCeSh7az1kOSVZTD9jRitMNXBIUVFANTh2b35rIUdOM1RHVHpiQCZxaT05VzwrK1hTVi1OOFMm
a04rK0FIZ0k+CnpVUz1fSlJVJFg4Njk8X0pzQTg2aWtOdTItTj91SUgpbG4/ZT05dV9xLU4xbmR1
WDdyWUxeNDBHVnVvMjZiMG4qKAp6PGlLdTxHcXszI0h6fVckT00+RWo/fHhoRDFDcjNoZ3R2UjNJ
WFEjMSRSUkhrZzd0M15oMHNrRzhYTkBmYDY+cCYKemNTdE1JTlpKT0VffWB6bUUmVEcmOTw1UntR
YkchbihWVTBXSW5+TEZkSzZ6ajJjKWdKST89d3o+d2FCenpmJDNlCnpJYURjVUxAcSFmKVBAIz5P
aVpZaVErfl5qdjhAWV5wQyopUiFeODxTYzgjSUhhQHcpIT53c2R0eXpYUGdoJHF4cwp6XmR4WDlt
Pn1VTjRNckJLMn09d1ctRlBJcFo0SVdlNihVKkVuWkd+VW5wLWkwcXd5cjd0NnE/bCYxTGlKMylx
IS0KejYwPT5DNTAwJkslMlIjbG5ZcWtwRUw9bUM2RSojUT9RZXVWXk1HTXYlRUhXakUpbDJaOG1R
OyNpUjRTYV5JbV8tCnpESThwITY0WnsyUnZ0NShsM3o3bTkkemIzIT5gWER2Snp4cDhBTEdgYFA0
YERzWlVnbFVnbWN+d3RLI3NGajFUUQp6d3dlLTJSZnQrNTVTRXdQcFhRZXdBY2smYTdnKkQ1Njtf
QjA9Tmp8VEg1cDNCblFKbmVXOyU/YWRkam42QDVgPGIKemt8aXw7JDFBYjRCJEpiZT4pcjkodkA4
fnA0Uz1+NHBrTWJAWmsmalJRfjJ9RTc9OXRGXjhVUGV0TSpxTXVmWj5rCnpeNDh9VGchKUF6X051
ODllPmpJe0VWKnl0aVR5a2pHY2drc3JBVFo0VippI3UlPD1FX3c1ZWZkVEIhXiNWJiReNwp6Vk9t
YTsoeldUOWh1Iyl8akBqbWZwRENFXmJWQlcxSDNPe0ApcHF0amBGdz5sMjt1N0tqd0UyUT1QYktJ
T3NzX2MKekN2QXkxSktaaFBVMTMmQEE7WlolIXsxMzdeXjMteEUqbGtEJUFRUkFzMiowTUM+Z1hm
Pk8oNU9MKDRfVDU8RX51CnpIPncxcXYyJWImZ0Y1KERmcHVYK1NDQi1GOTFOMnVKUGlqZVppQ1Yw
JnkxTkF6TnMqJkIkeVhvVEh6Q3wzK2Q9UAp6IVRCdTdmWiVXTUtUfVAwSXdFfnRRYDlxWmZnKD4y
ZGEyO3w+NiFHQ2cpaWM1ayoqUio5RXNOWDhlPzk3RVVCUHIKendTd3dvKmY2c2dAOXJZJTlefF5j
YGwtLVQ7UFRZejJzcFlGKXl7LSUkQHxnQyQjNiN5UUdRdTdtVTliVlFnKE9gCnpick1OUjU/YCo8
KiRpKkhYYmwhd209azc2MT0yRm8lQWpmbWZjQGlnXipSKjdpRXFnNFYzfWwhYV9PYEchNk4mUgp6
NT8jT0RjNTg0ajA0UU9iSjhpNjAtbl5nVHo7RGYrS0VvQGExVEN6THZFdHNrYlRFMHk4MFJjSXQy
eU48aXdmNkwKemp0SXdCNk0zb15YPndmaFZAQ35ocmFIZUdxYSh9SFd0R142VjJ9eko2KHA3TSl7
RVVzeUBVJH5mSEN8MnRqXjhlCnp7TnlMVz8pclVsSE9BQyRTOXhAdnstOG5oZ0Z5MHZFaWxiclRp
MkNyYzI+O1VtX0FWfGl7ZWN6cnpLUi1nRmV3NQp6KHc+N2ZMalhvYF9yWEpiZml9dERnNmsmNUUr
JmxGYi1sTXEmUTcyO3VjciFHZzR2XmNfNkw8Nmh3VDM9JnBicjYKenlhcWhZcytxVlNxX0E7aERR
TXxARTUxXkttYmpQcFBeUz9MdkF2KUQ3K1VEa1g4TXc4MyZCZDExO21JLVZ5RkVMCnp7KkhFeist
dWcwVUh+b1UzPHdYMEh9NEtjSylYUE97Y01APUJ0YkA1PVVsbjdgPSRLNzwwblZCYD9kbG8mSVdU
Ywp6aXw0enZsJHlqe0oleFZUYHxCR2Q1fTElSk5xdHQ1KXhOKEAqeXlOVm1+PWZGMVNONFdHRi1A
T0FXfWlWKEZoYzsKelJuYHY9MWR5Q29HeU1pRTZNYiZLRWxMZHA5bUtCbEhUYlBMcWhJQGM8KVc3
NlBxYVImcklYK3NPajFOVlJxNng3CnojcUxpQ3ZBM0tpVCt9eC0mQl52fT5jV1pVRUpjUWcrY3xK
KGJGe3RJVWVKZDFvYVRsUVBiN3lReD0jd2R6aG53SAp6Y04pbVArSm05UiRUaUFMYiQpWVk2az9a
flp3dGtyQDgyKk5rJDc/IWwkcU4wWitTWUc9alZTayVwVSttYk0oVS0KemJlYjkoVCRoaCp7OGdF
KGdeJlgld0JhUmo0WGhSX2dsO0JtYSgoYVJ7d31+biVaRC0wKHZwWCZVJm89e0E4d151CnpXalg3
aGVqTGVWWmotdEJFV2Z8MCVQVDdgNkhoOTZMcClKYENROSFjYFBEP3U+TiVLLT5geGhQQnZMe01Z
R0pZQwp6UG1kZlgrSGFPQGE+WGU4QGkodT1hOVBiX0I/OSpYO14rJU9ZI3J9bE0zK0F8UHhBTzBW
a2hsJlR+cTdwTDNRRyYKem1yKHRrN29NQTVANm9yKHl8R2EpV3NhIUF2VHIhb2tnSmZCJT58eEUx
enpxSms1QE5OPTxnSyo7JW8tN2AkP1J9CnokYFc8bmM3d3RLVXNgIUBLdk9GWlNWRCE+TnMqPmtr
dTJoQ1lpcXt3dzVYVFI7USE8cDwra2tJdHcqWnFPX14/aAp6Rzd8eUNGXjZDbHJ3TmtPQ2NFIzVi
dVE+S0tUS1N3UW9DWSkqQHk3YkN6YyU1V24jJWwrPDhMY0Faem1OZGNxVkUKekNtOCErY3FnIVFB
KFJDbyNXQGxAdERuOF96ZlY3eWwtKXwmcHhMfTQ8NGQzK2xkQmVtRyVONXNga1dSaW11Xml2Cnpl
LXNVKVM+QTtnRCo5Mj95blQlfG1NS3Q4VUZCTnczdElHeThaSjIwP2hCPkgqbUt8fFN4WUE3MT8h
SVJxWX1MLQp6NjFAdlkqWHYqUF80alZMVCY4NFk5ZnZjI1ZEZEBjb3ZiPTFDI1VfX25+OWZ5OU4l
NytZJUdDP2BKZk9RRWBWSUUKekk7SDZRWXJ9aTEtT2okbHdxVDwmKEBxRlhvUTwkWGNzTkZJY1pJ
bWBULS0oMWQqP30jN0VZbH1FamhPV3gzanVoCnppY1otKkE/V0c9PFQ2JVVMQEVePmVxJDVpRD5e
RyN6e1dNMiFuU2h6b3h9ZnBFbGxmQGhnY3pfKiZXPEBKTSpjagp6WWQ9R2BEX3xzSEFtQXYpZF8j
VjlDKjI/YEpaJkl+QFdENz4reVY0WlIkakZ7MnlfMlRmJlRmK2N1Qkk+YEkkNTUKejszVXhOMVFj
ajluSW8xekA1Yz00OGsrcVo/akhNZWIxPWx3d1FjU0V4LVpiPmAkPjM7K19oZFQ4Rm8kenlWOz8t
Cno8Mj43WSYzOGZmPD5oN0NLcD9pQCFBQ1NLT3pffVdObDkxfnZgMj5tKzk+az9wO305anB3cW45
antGPi0ySlUkTgp6UVhSMC1AdiF6SEBiPm0qNXNsKj8xMEhmMDZtK09PSzA0QVF0bXhRO2xZa3Q+
TEZpKzUySndOKSstSU1+Z2pwb04Kem47JXduSnw5MTwxMUFHT3ZrTSM1XzQ4XiRfWVFGNmxSLSp5
TS19ZF5CXyNeO1JtTHdIZnpLNTBrZlB0QGVFZCU7Cno9fUU7anFQayR6LXRMYjM0Mk8tVSUjR0s1
WFlZJmtMYHstJWpaVUBoOVUqOVFmWCk3N3U0JmgxRnh2VntBP1VxRgp6cUpSMmQ2aCQhdUZKYnE5
VyhEWG4xb1pOcHRaVS1nbXE3USlpelVnRjhrKEYwaHdJXnRMNyhyOVRuOSRLeT40TVMKeitsN1B2
X0NqaEA0cHZ3NzltWFp6VyowITAjUjZ7PWIzXjI5K2dGc3hHNDIhRkVaOz9RSSZjb01wbkBnP3A0
TzA3CnpjUl93RV99XnIxdj0xMUZSRXsxaSg4eUg3YyVNYEB2QS0tMWlDPWs3aXIkPCRMPUU1JCtK
YzZ8aFl+ans4ZF5JIwp6dlhmY2otblNVVXVpX3N9eXdeTkFJMXhAPmsreUJ3cmlsfnFLSn1KWWBS
KUEmPmVyb3NmQjt7SDNId1VFP05uNFQKendzN2V6Y1FxQyNLUi1Xdmh4c2Y+aT1wJHwyO29lPyt2
bk58Jn1OQ3Q/R3pYLTgyciVyKDJARmpZU1o7dD9xbXBACnpXWVNmKHQoK0J1ZTtmJWFYO0M2enBv
WCN2XiQ4WT1JQWlaNFltUyU4aDBjNUx1SUxAMip4dW87ZztebmNVZXU3Ugp6YUYzNEhKPjVYdCor
RXMlPmNZYXQqR2h1UWhRMjFFOCh4NzRnWXNaWD9WSjYoQjs5T304UGhlZG0meH1NRSZIRi0KekNW
PmkwTTU0Pj9FPnZxMGN9WFBnSkZ6UGdja0BqaFB1MnslWnI1MUNaTmRhKlM/KTFJS0JEOEg/aiFv
ZnQhLV9GCnorNVhwTTZrUyg/MD4pa2tZaEJPJUx8NXZjaWIwXlUtQmxuaCR1UXd7SkgmSXJfK2h2
JiZmakd5YzBLaCY2ckhSUQp6NGZQYnl0RWdCYHBQWFc3YjtFcEZXbzMrOSlRMWlDZG0pP21yLSFj
aDRpSFB+Qz97TVlNREpfSkFOaDN2NHZLVTAKem1nKyhePShPaEhlNyltaytvREYxWSQlMi1OSUt1
WWNaejQhJlMtUjdSPmNoYz9DZ3h5PSs5PFZxUG9+IWBOcXEtCnpjUEd6UihoSlNaNlpKdHkrKiFy
PiYkOFVrMFZnNj17PHFVJTh5eVl7SVZfKXdFSU1fe3gzV21OOzFIQypGNUVvUwp6R29zM3A2bkli
QVIqcVFKKTtBSEJNU1dtdnpwSX5CZG1ucyU+KUxvN04hd3tIdUZyV19PbWwrT3FPRyFwYWNkI1YK
emVjZmVIWkBaaCUtVDMycSgmIU5PPEEpa1k+Wm91ZWIoVEEwayZ6IyVoLSNXc15+a0lkdVdUbWZi
JUM2JExuVFRkCnpgZ2RzKVZHJDd1e1pAfnFJTWRoZGhLO0EwKVhyTyVBfXpidSgrWnJ4a1J8NG5f
KlZlNUA2eTMoMS1PMmI7fHxeYQp6PiskO2ZNLUcrYFE4cWZ2JCZNVytMazI2SEBGWWt5ajBreXkt
eFNtPyhrblRaY3UyOHtyO0RTWEtGXz4oR1cqb2UKejZJbCpoYXFyJGQ4N0w/V14rN2smPzAkRnI4
VDVLcjRjWmc4UkFDeDxpYjEhcFErfnd3K0Q3cyhFZmF4cjVQUWg9CnplMjMhd0BmZUJSPVdASFY2
TE4heWgmV2xMR2d8SkA7SFE4dSpZNnRMZlFiX3A5X3wwelFyc3hjTXZFandSeVojJgp6WF49PTI4
JFElcmt3MjRvO3M3blB3WThOekwha05+c0tIXmY+IWRGQz9SMXxLeG9rZjYtI0wrZEJDemhoSH1l
ZFUKekdiTGFRSyMyQG56LWEkKzBEPkdtSExaRUFsc1Q+VnNXWVhyMz8re2lTd21ZdGwqa207VCop
NXZQTF5lZCFEIWh4Cno0VHcxYig8RXJaVDlLXz50QCFYI0FuWmBNQzshZVM0TXM7NntPZF9KIV5Z
aStRSTBQRW4rd1NLI1d+Yz0lS0M4NQp6bn0lMEZGPjFzT3U4SE9nMns9WnEqTVhPa3RrbDUqcEZa
RTYpT0I9cG5CJlZxbn0zWH1HaDNjcCNieT1oRSROVjkKejM0aTFwKT48am1lO3Y7dChIUTs4PDRR
SX1PVUp4cHlQTEQwYlR+QV9EeT1+K1RgUzBXbyM4SlBaJk9CO1k0cmdvCnotWG53YTBLUTlMK3lh
bXxFalp7e29FdjY/JHhVeTUlMFVWM2cjUTFBPXZubUZjUmx7VSE0SyN3MkdDWSpmUmRiPQpLWT9a
V0dAYyNrYmNgQlIkCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVz
L2ljb25zL2hpY29sb3IvNTEyeDUxMi9hcHBzL2VjbGlwc2UucG5nIGIvYXBwL3Jlcy9pY29ucy9o
aWNvbG9yLzUxMng1MTIvYXBwcy9lY2xpcHNlLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi5lZDY4ZDcxM2E4Mjc1
ZjRlY2ZhOTY2MTc0ODk0MWE5MGMwZjk0MGQ3CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAyMzg5
MAp6Y21YVjExeW9lZV9rWCh9LVFCVSZpWGV6fCQwQ1J6cHA7NH0tUUJgMkFlfHpKKHhISDtxKTR9
PGYqez1gQ0RQS2QKenxLYT1scFIpKHZkMmk7dm8xYzU8JmIlbXtgKVpeX09oZ2Ffaz18OERKJUF1
TXhQKElsYztNZVote0RnVEdHVi1uCnpRcXVGeSpxcmUoZjNqU1F4M2tLXj5OR0xCN258QTBzVkw2
KnhBQShlQkMoKkxtRkdMZitefUNGYihqWWwhTFFxIwp6P3NkSVNqLVBzTShtUDgqbD8xKURCJHdI
SlpSTkU3PWA2eXJpO05IekFsR2JRXiE/WXo/ISZWK25Zb2tyb0RKIzcKeiRqRzlLJGdyQ2phSXUj
RjFPSk5QdzsmMmlOX2BHSTIhWTVXYFVXWVlQPHBgKDVFI0h1ZmRmJWU+UngqV2FVYy1JCnppWDsj
VWdgJG84LT13Pk0jc2RULWo1dWshM3o0WFlPUztYVSZzJms0QHNuZ2tNbjE/VCZ3dnp9a0JpQU49
RlVGQwp6NzFAcV41MD54WTt3WlhfSypGUmxqNCpYKDNGanx6eVFPQE9BNkdsTTlHO3hyPkVPQ21E
KTlhT0JWRlRTZ3A5dHYKem10QzRje3N4N29Sdyo4Mkc4UmA/R0NfM3dJSTsrckZvYn47Unx5WU5x
SmY3JUNOdiNFcHs/Xzt4Yng/YmNMUzNLCnokNmRaWUB8VjVvR3F0dVc9d3VgR2N2IyRUPz5FNkFa
cGdRP1NDNEI5Um44RFE9OEQoJjtLRGQlQit0ZEx0NUpMbgp6TFhGNDAhfF5rbDQ/fXxvbDY/aWxi
cSRpT14+eXVPXn1+dmhJeUFJdDE8THlSd3JPTnFgbmgmWWRWLTlAMmQkLWIKeldLQ1ZEV1BUK0k0
dVlPbTYodCVAMHRfO2VMWHxTRjcxRV9LN2lRcHkjIzJ2JTtvU3xmNm1CdDN1OFlPOU5TfUIlCnpg
I150bGR8K1ZzY3JjMk82KzZoN2VXRUZtcXtLblNBLTx6T2d9Iz5US213aWMhT09AcGV5fSRrVyRp
QzAkb2JvRAp6Xms7ZzYxaEBQIWtffTJrK15ETF56K0AhOE90ZUIpa2ZgZUI2cTV7fl5ybEpoYUph
I1hNQkJqNlI7MH5WUjdwZioKemhPV31qJHhHez9jamZpcTRTRG8+MllZe30ldmdkWU1JPjFVMUhv
UC1qNio+YWEpZHRKRmY4JUJUdF4zP2VLK0RXCnopZ3N6K3JPSkp1Snd+dWVhOG5VfXZ2QXxLV0d2
MzNzV1YwN2VHKlpwKCE5ZzxnWUxFX0ZTVncxck0tQ2lzTUtIbQp6P0B2MHZIMkFITDM4OCZQS1Jw
V0s0cHFlTThIRCQ4OyRmejU7Z3NRJiU+fU16Sn5SKzhhZj5iT14zZkVmTn5oUVUKel9HOGVOWDRp
PE5MY2srM0UwUkIrZ0Z5SkxydHAmPVdrdiRSPT5sI2FYRFdzXy1Je090dmAmd2UpR3ZnYEwyV3BO
Cnp6UU54Rz9+eTxnUmA3WXF5bXxrdE9yZkF6LTlKeHM+R25UJFFTc3xeYWghQjwyKHw+M0E8MTQ8
bHhQTXJTfiRKMAp6JTs8Qk9rem07KSFTb0VhcWVfcEpwWGtIUmJRZmN3MUE8XktvSlp8WXE3LUcx
X0d2c21vM0hzVjJXO1RGdV5BdnwKekQ8Q2RLN2xvalQ7JFhBITx3MG5LNE8raEZ2a28xeDQoK3Be
biV9TCNkTXJMRmxuK2A/Rj8zY0hBJFpYdWd+UncxCnpRcU57bylTbnNeQUlxJTFgMjl4a05wJl9l
NXVQPy1nbVNwNldHcEkjR2JJd3F7S05YVHFkMnBwY2ZFRHgpYXpKZwp6aTk/c19eQnB4SShGQigq
OTEyX3MlNkROZjRsaStOZ2p7eH48dWBxSCY9enJFO058fH1WMzc8QjVmPkdpTX1Sen4KelphaEg8
XmxebCF6TVUrNldebHRAMXs9OGV3b3RhdGNYelE1Zn4mXzk0WnhtM2xFUUVkS1F5OUh2eHxSdz9u
Jkw+CnpVeTM9e1BwKEwwbUArMykjQWNKNGFgfX5JXjFRMzBkOXtwYUsqfmtjQk0pbzI7fn0lQERq
RyRGQnFkRFc9MGpvVgp6eGQ7cj96SV96bis7QUJGdS1iOSp4Z1V9eGk8Sm5Fa31PUT5aOS0mRzNy
aEZKaF8jQkI3Y0MzZisxfWxVMSt0eiQKemFnTzklJThrd2U3aUIlMF8mNjwxcShPXjVLXng0NXRj
fERiVnNvVXxMaDxvJmx1KEc1JTQycz5zNUE0KjJfMWN0CnpZWXtVfFpzK2YhbihNR1c8ZyFsWE15
RDs1IUdYYDlWQFo1eXRoJmk8PGQlY0hhaTl2NENUbm5lVFRQVG4oOTtCawp6QGBPR2ErXzI5T0Ux
VEc0Kkxvd2xGaCtpSExhcSZDQWMyY3dWQ0xrdnBgKlNyXiFBUj0rI2BQdkJ1eGhHOHU8PmoKejA7
TyZnNkE0XmpLWW4/aVVaNyN+WXhka0I4Xm9UfWcoJmhSZnFKK1FiIS09TllKQkhRZ1UhWT5MbVR5
RiV8Q18wCnorWlU5X1I4Z28kPTAxYC1PUD5aRWlYQVNgQ1ZyYXVjM0dMI0o4fnJ7PD5abDxKeT9o
MypwQyRKWWJqaF9lbTJ8dQp6eUxNX1gldXNnaTZlblheNFcoeXx0RUF8cUMwNns9MFlSIW9OPE1x
SXBNNHFCbnx6JkJlTT9OfENCR1EtMkokVSEKelVhOHxVWV5Ya3U0Pz4kT0hfd3JXO1YqQ15fI0tr
Q2IzNH5qVDNSRmhEbUghUm15UDctZkFrQF9xODZVOzgtZnI0CnpscCY7VzxvXkJRWHhoV2MjXjtE
OSRTa3s/RmJJVzg+OURWQVRsWmVTUy0yNVpZRXBtOVhPa1V4PW5Wenc0YX53Kgp6WHJOZj1QdClv
MGpzOHA5aSZPUyVYRTs/cyZEcmYyME1SdWxhRUIhdzx+XmxrM2JuRk5MJE4xSSt1NSp6STNoO1UK
enFHVSt0VnM7OSs+K2pKaT1SYUhQQyhtODlnfnRCeUFyTWZIMSE7fChiSXRUdDd1dDAtITZpIXA5
bUpkekx5JUpDCnpQN2RLZ3ZybjQjRlJyO1hBRktvZChQRW9SNlM3YUVCNWlTJUQ4UEZiSm5KU2BT
Wns0bFgzcXAxSnlET3hPV3c/YQp6RlM5QGJuVkZlIUcwbDViNHdGKztea0BHNUprQT9AaCY9NlFS
Z1ZgdzlQazQqSGxKUV9xM2g8PkoteStgPzw9fGAKenUkK3wtWGEldiR2Nz8hemtNZEA3RlBsdSte
e08wSVNTVHMyVWJkUUp4O0IqSkR5QDRLOWVfWENeZWRwTGR0Rn5DCnopP1J9c0YtS34xJX5yRHhM
ZH09dlg0JDEzYkVgdDBTfElVLTBPeFk4byFMfWxeJXxCNGF6QTJxO2l8MVNwQWhZSAp6Q3hXT2py
fXE/Ji1WO2tXUDVLNzdfI31qPlQldTZQZ3owXkYpbV94PUdIenw7KmdaN2I0X0E+N1EoK2BwVTx9
OTkKelIjc043ZT42TXF7aFhPO1Z6I3hsNl49O2xJOCNCUHVKSlBSNDNDY0htRT5OTWxWZ3tKcy0t
Z2ZYT04qTCpFKkV4Cno2UihaPiVtdzxLXlV5IXZ0Ki1hcHltWXJ3PDRhY242MiYySXRvPmE+b3Q0
YV9uKXZvI1lje0VNVSZlKkxEdnphbgp6YykkKVR4P0RCR04qej07VW1tRDUle0hsPW99VEl+bVBT
TklNa2pMKzBHVjk8ak07QkNvbypOaylhfHM5QXtUbXMKei0/S3BXVGVUWXtRcmcoRng3ZFJkfE1h
czkrNWxPNjFmbjs7X3olQnRXN1RJSGxqRkJTQ08kSj4+PEI7MCl9KThVCnp1JEk3OHJ8TGV4dEBZ
Syo+NnI8V3BESVVHbClDYTB0WXAzcDRndlMySHM5VEEhc2I3anlFYjZCbWk5bkQ4ckhITwp6JUlx
UylJRmYxX1NXe1IoTUhfYDhHOWthSkgtTyQ7R09NdmBgU0c+P3o2SiFIOyRkYyQkQzlIVDVKUilm
TyRWRHgKenZ3ajtoM1d1SXZRWj8hOWwkNWtkQmxjbXtDRV9BM3ZrZj00e0Mxaz82T0NgPWEzfXZW
Z3xhTzcmR3dwU0dCWHs0CnpKQGl+YmlrWm5ZYEQqcTN3Y05pTWhoYDR9TklUYS1USVczI1dVU0Ql
anZwYzk3dG9ffUhOcl4xVjlnKHRJU15FQwp6TH4/YmJkZF8mU0BKVW1eY1YlY3hkQ1plVGdBPFo7
SVU5N15IKyNQT1VhZH4xLWVMU2FEemEjdFRTYypPWH5mVnAKej15I1hJZypnbmUkI3BtdD9PPW43
d31DUHpnZjNUNCljbUZFTztgP3JeRkVgRT1AXihBZDNkb0dCWk9WZzNmT3V9Cnpte1RfKDdNUyNt
NEVvQks8QEBae0x1fUEjIWk8VERZNSN4WT43ITVzR2N5bSpoODQxV2tJVHtMN0RVbSQ5V0JwRAp6
cCN1R24yMzZEOHtXRz5kbzEzaEM3Z3d6NHktP3ZpZSU+ZlplIWtiTEFZZkFHREZBdW9JIXZaTW48
Z0VZS1JRYm4KemwzWUVYXlkten5USEhfaDRaakR9dm1uYngtciFZTEQhY2JuT3tsY0EpSjYzcnQ3
X1QhOVM4LUhyVyg4TWtfWERrCno3NStPJm5RcWVuKWdBPDh8QlI1Ji1hZnR8UlFzMH5JKUdqJWtC
SihXVXhUKmFYUF5CRkdyOThXJkdxSHJLdXx8bwp6dUdodDlaTHhXSmR6eU9wZ3FoVmFWNSRlaU5E
VmJYajkjZn10NWJ7RldnQ1AqZm44ViRASmJ8Q1QwdzRvSkBYVEIKenI7fWE1eGtmOGt3Q3p2S0dl
WVJLT300TjFeYk1pTFEtITgxKC07SyhoJjJfY091dDtPMiR7YGQraDtDcUsyKj9fCnpJfmN9PVVN
cjhgKHNYZXZoUiR1ZilYeDlkWFdMcUhSN2lfQjs2ZGNNfE1yeTllUFZ7fiYmUXJsKGZgQGxAUFg/
UAp6S2huTXgzaz9TP0ZBND5JQTZ2RTkyajswKi1ybW58RjVRbW9OSlZkXkJTVEswRmZ3UkYhVkpC
MTkpRWIpKEtNU1IKejlnUDRyYUliJVd8Nm8pNyNoLTFudnphakQmVTFgMTl5SWpwe2tgPExwIzlI
aCYqa0xyPkp2Ki1ERlo8OENAIypjCnp1Mj1KNCY4KiVJK31eQnkwPSomOXpuOGxMZklGPlVALW8/
TVlxc2k0X1Uwamdmc304WC11WlVKTWNBe1NILTRKbgp6bkBlQ0NCJGt4cEFqIyZfPDxnOXFzaV49
cWBaRz5NcDJwSkErMkdXYU4yXzc4PWdDey16KUt1ck49VmJDO29xSjgKekBCP08tZ00tdFdAdkUz
KChIYV88OGo0QWZlfmV2OSU/X3lMTlFWPHFMSmJQX09ZIUwhTDEtME9IbGRhd1k3azdPCnpoP2p+
aj5fenE0VGxGckF1dFRFbUJOan5CTXc0SGstRkN4NHpuUlJXM350R3g4ZW1ZOU1wYVopZGAqcHxl
MjRmKgp6KV8za1Uxb3NRcmRNLXheKiZYfkRpTXg/blQydUxSdFpQTFo8UHEmNShTSWtXRkgmdzhv
P0M4PWVtO09tUFctbz8KejwzVkdlPWp1O0JVUjw9XjhuaEtuKDd5NypoUCopfUpiMzw/eHVrWkIy
bTx0Nm4mNm18cFhsQGJaemJfMUhfazNECnpXI3hFKStVPDZaNHNzaENKJENjNFhLVDM3JTV6eThG
bVRsK0xIMlk7NSM2ayU+emwoNGR9RHp8Ull7bmxPencwaQp6eVAzNCpSbEAySTsxeWp5cjU5VTBF
KUEhRG4hVUZ0Ty1TJjtOQ2R4aDl4fGB8Z1JhY2hIfG40RE9JdEZnYUVqamIKentwRyNabSZVdDR0
RGRqZE9QcmpZVWpZZn40M3p3KjdaOzFhZH1kR05BXklkYVE1JHp3c0pPfVJXSzVkflBvPVZMCnoh
OEpaUjhhVnpKUCsjR093JD5WJmxeO3QmQHk3Q29IKnFpJkYmIUJqcWIycD41aHB3ZGd0VHoqQzFn
PGdYZ3x8UAp6O1BzRiQjdXlMdD1WUGh5YkFLZF9ebyNsbk49aSFCSHxwRld1MUx8UHNoRE9qRG9u
QWxvT1RLUEtQdV9zJlVJPG8Kem1yLUNASE1HNm1ScCsoUW9ibnh6eFB+ZGRCSm1oV2xoJno/MXFe
P1B4fDJeM3BeUl5LNno2YlhJZXJFSG47KzcxCnpuUEBuUEhzXlNnOXw0aiF6WUFiUHtQfnclY1N4
KyhfdUxwNG4oNzt5bGF5aEp7fUdLc05jczgjVUc0ekBxOUJWewp6TDJ1Vj5fZ3lwcGV6PiVYZlFC
MllKdit3Vz1sXzc2bFYyKXdMPj9MNSMxZ3ArNkQ0aiE9MFdxUjxlRWdgQSQrUGUKemIwQUlXLWEj
d34xTE44cSY3clpEbU0wOWIye0s0dU5jTDxfPXRZUFU0KjN5cWZNaUNrQXFwWnFRWHolP15WT0hq
CnpDaCRyfD0tWEY4ciskI2JeS183Zi18Mnl1PmN7Rkpha0dELU8kezlrTmhgKnkhSS19YXI+KjRv
Ml92fUpSOTdnbQp6MEp8JWNVZWNsdlBxK0lkMD1LIUxMcXxEaGFVOHtpdWJXZnleZWNzRUFrSFZF
aF8+O3NVUT1QK2lgTE5mZGtHZikKelNLSmFydzV5QD1iYSZwTWYhLSNsPDUzaHU1ZWIqPUV8PGJ2
NntSTWxJMjxxNkV2Iz1xbEJXS2JDbSF0IWlBNVYzCno9TzclQ3dkeldeU2plS1ZDcUlXKWpTczg3
azglPmpJRyZfS2UqeGMmM2x1JlZUcClMYnNZfUFtZTZ8XzhmQmtCaQp6QWI/aDZ3aWBTJjFlaHxE
KWgkYG4wbmZKVmlAVER+JUUkaipKc18kbTw1ZClnVzBxemw9QT5mMlVzNiQwRSpvJUQKendOXi1e
V2BxbTtCfjZUaiVyYGE7R1Q4YGtVb0YjQEE4QGstbXlZQDFNUlB6VEItayFxX3YzN1VyUFgtaUlH
Vk5GCnpPPXJCMnUrXlQ/VFJkb14qWEsxbWI0LVdHYXxZbnsoaTkqby1aTTNHN2wwZ2k2SkVKTlly
NisqKU4hY1d8TnBleQp6bVpXaDtQS35RdzE9b2ZPYFVYTitkZyoyTnc2QVF8VH5lU1NQdDNEJmhQ
PVVAa2RjcHVIbEJfY08qck50N2F2ezgKekw4dHgzQDMjVV9eWjlAJVh9UXQjLWF1KjRaRV82SE9q
aSNRYG0qSUgkSXJDOWJMQThBOW5XK2ZyXit2b21jcnk1Cnp1T00/V2Q9LXp5M2BpYTUpRFNFUGI5
SFJWaD1rIUJPLUhpPHtsM2FzeXgtbUhldTg9b1d2OStmNzFfMGYtO0JMSAp6di1ecG9FJiY7X29o
KSVoYlhkNUJtaDZ2VG5lWEo/aEJWYn4mQShJeWQwOEMwbzVVSDtrWnw/cHc3a3NBYE0qfmwKenBi
WH1aZXt+OSZPbyNtPGdNdC1wdHp8cF5Zak9+UDdzSnI1OyhLeSVpaThnR21BeiZfRXNYUUskWVJ1
Kj1ldF5OCnpTN30odyZOcGdwVXN+MH07Xk1TXjRgM1ZKYTJuTk0jRWs9Tyo8RislcSo2U1dlSUY4
VEpmSHFQTGBCJHRjQDwqcwp6UHxCU2ZMUU51IWNDcWt4dzItdDx3UlZhWDhUSlp3bExZdzY5MU9l
ay1jZHNETTYtVTxrbCs8XlE7RjJ6Wn4oZHMKejswaGptZEEpbXgwQ1M1ZUwyRGlrYFlAPDQ5PkM0
K0YkKElgWW5JNVFnempufjEqMVA8UklXTlBWZnA8MCQqNTtFCnp6dCZiaSM2dHVRcW8yeGU2Zlo4
WXtyQnVXbDg4cTJeSVZOdkp9RC0jX28jcGdpVW0xU3VRQ3NMVTUqZ0kmMm80aQp6dmhEVXkqYFlg
cEhQezFFPSl1JVZXP3l2TWU+bD5pc0heQXJzUUxaMT52JE53WURWP0l6YCVTeHtreXdVa3d8djEK
emxyM2ZAOH49TTRUcTx0I2dVK2JXK1VRZUhEUDlqamo4dl9BUUhMWW1pJEw8Vl59MjloUyh3JlBW
antKVUNGN3RrCnozdmpQO0BZazFRS14tXlBvTTF0bkE9c1FrV0RLOVA3cW9pams1MUJGRTx4c3o5
VHZ2MCMzRHNwQn1gPWpsVzc5SQp6YjFIRjNuIVJNXntoRXlYa3s9eTc3PkN9RHJPV04yOzE/R2NZ
eF9zfXJPbzYpWG9jczJmb29mdnN2SHlvd29hJkoKejRTb0Y9N0Vnczk3P1RRKkd9QXBwUTJOKnZ6
aDExUylHaHdPT1U9WkBHJSY3ezVNQyFlPkBUfWhDI1J3eyVNbj9XCno2a0IlaCZLcCZuQTl5TnpB
Q1lZVzhmNlM1IWNtQ1drZipsUmlIfGckNTImeGZrYGlUMCpPPkg3QEk1KGw/STJJdgp6MG5RQzNz
XmFqUDB6fD1lYno3IXEjbkNVbzwlaF4zcUw2NDN7am9kNCMpZU5+Pkx3PT44bmIqNiFDUm16SXkh
dTIKel5NdSk7KVAkSnJlZ0BKYnR5dCtrXjhSbTBoPUp5am5fVXt3N0xJemQzMG5mUU1jTmJMeTck
KyM7eihVKE9vVy1hCnpZcVlGfjhUd3Erc2FUUS0kJEFKUEVNSlVweilwQU9QXj56bFl2bTA4WX5s
WDBhNT1oJkVTO1MxQkw3fipYNmFEVwp6RD1UXjhVOTg+dkhvIzJTbmpNKWQjSFB9bWdpJn5AczF2
MCE9b09oNGA2ajJgVHYkPDxBQD8zIXo/I19EOD11QUMKejJEcT95dSlwZEpjdTNCQj5iMlM/TGoo
Z2tUcVBke0pSeE93YC0mYiopUDUxS1hvN3YpNDs1PnVFP25QWGpQNmYlCnpkWGJ9VDhqPFMjbiM5
RzFyZXJtVU0lQiVvOHEhX0NXND9TZEQ5RTdUUG0qVHJUb1hyRXFpSjJFKjtERz4taTF+QAp6Rm9N
PyFLfEJuPmJuKGd3QnBKJC1ZWlcxKj5KJUZ8QHtTfVkxNTlNT1ZvWnQtKz51fF4zRVR2JG85bzVY
TnUzTCsKem9lUFBiUT5vYnNpTDJQaXxKWFlgdCRoNTdpIXVhKSFTa1lIaTteJSg2cjUyQTZ6NUZu
RD1LfCl0KVUkTFYoTUJwCnptPTVqOGB9SnZEI3BMNFJWdCEyfjF2Wk8yKSNrdDZ4R2ApVj1KWSRO
V09oWFJTRi1aOUU4Pyk2dEMhamhvVD8wKgp6IWAzYzJ6TCpwRWF9ZGJBRz02Y1Q8YiU9QlR4aXZX
b1lCfV4lbUl2RHA2SFlVSXF4UW9jdTQ/JGxpdTV4PDR6O2AKeldXIzxBeH5yZDZNVlVKQTltWm5F
YVhBeipOfUEhcHpZVEZuQCg0SnFPd3l6SDxCTEJlKHZITmpCdFFoa0NIZjliCno1IWZqQ0kxVTJh
cVNFJT9ndyhlemRNJHNqJGcjelY8TnhVc0FBYStMLU5re0JAdiUxaG0pVzRBQ1ZBVW5pWDN+RAp6
VT1BZVRQRSN9V2NZbz0hQTdqQnMmc2lmPTJIMiFQSmJfPCZ3YlJ0PHJuRHpBam1UO284M3JsUmtQ
MClSKWJudWoKelRVIShyenRDJDk8dlE0bGYlK3hLZiFCNEJZJXBsVnp3d1F7NjtiP0tEUTB7THZI
WUhBWUs8THU/SlptMEQkUX5nCnpASUgzVD07cG53YjU2eXZUPUhxSXlsJnQ2MEQ5QikkKkFnanBR
aiFKV15UNyNKaD5IU1AtMyktPyh7MDUkVG5OeQp6N05teDdHIzxnKE1CS313WEtUYClDSzgrLURi
UGJRc0UmLXdXe1dFQndeeEFoTXE7U2o8Zm9IMnYqUnpVOXJXRmsKeipmNj1UT1ZAUComVF9tQ2x7
YT5raCtve0lEWnA9WEJ0S2U7RC1teFB1Zj1pa3RsfjZQJmZlS3E5VDY9YDNtO2VICnpOSlFhaUNn
SHhhMXVDfHFNKFJFcUBMfm1UYUEkKWNZUzY3VkZFP2BTeyUwcll3RHRUKXgtakY/LX1ePn5fS0l9
Xgp6RGpSPTtNK2I0PFB2TGhIOWtNQXM4NXhWP24tWDdJcEx0U3RvMjdnODkrRWheSz4yUF9CdUF+
b3lCPn5LJDdGS34KejJEfkRYd0tfN14kNklQcCZJU3VDQ3RBRiZtWFYmI2l6UXljbGVnMUE+WnYl
MVhqJmB6ZWwrfVpCbERsRmA/ZlFJCnpuMVc1bElgLXE0MzV1UENiKDFHTXMzfjRZdmVXJHdzQH5W
ZDR3M3dYczEjaDModStxVEV0Yk57aWBgSmxFeEZvdwp6SDh3YUBMeHx4fDdffEkwN300TFIrUXBK
a1l0aDtNUjVZJDN2X05VfFpga0F7Pn5sUm1nTGd4MD4paClTQkw/akYKekY2Q3dVNXx7WGU/MF9l
IT9qc2V3KkgwLV9qa3ZqZjtCbD56PXU5eEteKz1JSjE3NFpCWTVke3MqNnM4T2ErSXJWCnpleGpa
QWpUQT94N3IjeiViYlArNU9wUk8lYlkocSUzVlNyLSlpQmFYb1p4NUB4O2p+e0crSU9LIzBobG1p
aWo2cAp6NmxOa1JRfEVuaVNsJFdPe2goMU91YGh3S1d4ckV2ZF5+I0JXP2A1c3s+OThRSG95RjBD
N3xBbEQlIU1DXmx2QWUKenpVQ1dydHoxKjFpPXxVemBHUmQ/SjI2cThpVzVoV0t5dVkyXk91P3x2
Xm1rcXJ2eSs5ZnBBS3glOUdDZEN4ekxlCnpUO3goRE5sSTt6VmN6WSFNTns1TlBFKHtOMkopOU5J
VUQwbGY0YlBLS2VZamhEWn0hb0RlNk9Gc05jQUc2KHNyRwp6dF45QXpEUWNOR1F3bHMhTWJ3fjNo
KCpDcXkyPFR5OypGVHNXTGNQWFF1NzBVRyhxblE+JWUzXkVZTXRlJmF+Ty0KelVWISh+N18tNCok
S2ZWUEhfeDRqXyFrSlMrLUBNSnUqV3s2UGpIJDFQKnVpaFBwUmhldVBURnI4LWp6TlUzX2sxCnpB
bi0heD4oLTBXS15mc01yM3RvfChpal5iciZoVSoqQWBsNkFJeyFGMHBAOTBhfCtUaiN5RFo3KnN6
O1hORS0mSQp6MipFMW1qYzd1VGBuflpWXz9OcmNlNSZYKFJfQ0FWSldKTGAmdjFBYlpNbCFtdWNU
RlkpUUoxPit7Q1htKF9NUSsKejR8aj41YHhZIV9AQ1BNfnxLOW5CZkBxUCNyIT55O3RJOTA/PEQz
LVhQVE0xMXRka2Ataz9HWSs8YWg4JlNuOWxyCnpQSn1rP3kwcGd4VDlkTDgqI0N6MkNnai0+Ym1X
NkQ1eEM+YmwoV35DWkN5LTJVN1MmS0B4fGo3d3VwPUslXms5aAp6O3UoNDUjI2QhPmt8JHY8cjdQ
SGBRZmhfczlsP2dGcHsmeFI1MFNfO1gmVChXeXRoK1gzTXlKNE1YUyVmd3IhLXUKeitBWFgxNnt0
SllpWWNxQDxRMCsrbytQUFV2PT9yWEkkVW0rM3ZaZDh2OVptM3JETExSRGZXI24kV3gjVDI0UTNe
CnpxQyEoTTJCcUFAZ1pTXnxhbStYRDQhSTVHP0pzMFZsQ3slIXxIezlHV2Q1cWB3ODR9JVVBQH0q
Sk1+NHV5IU1tUAp6Y15pajBSclN+Vms3YTBeVWxjM0dlKmd8PiM5ZVl6e2UyVispN3d2M21HMyZt
eGNZNFI/Xn58JEdjVlAhSXpSa2oKenJfVGNedCtYZmR2KiswcFJnNFA5SjVGRXJUNGV0YmRZWSl8
I2REUShtISllP1RWT1FFYUc7YnBgK1AhKUp7aTIjCno+PnlyTHNsenY/JDJSMjJWJDhXfU9JK1J1
P1BabWo8LSQkWGR0UzFZNCk8cDUzd3stQEdsbEZqWHlTI1hVbl9iaQp6NEN5P1FiUTw9WjRqTSgm
Kmw2T3ZsVCNTPT1mPDxAeUpLdDgqel42Jl9PZyFiK0BuamE8fEleTlVpO2c9a3l5JHIKekFWU3Bq
R0ljdG1TUWdUcCNWJHlaPVgzd0ZFXlJVZUhvblp+Ukh5YHhIR2grX1RxbkQqM09rdmNWd15HMzhF
TWFFCnpyYERrN0hYUyM3RD9iWGxoJj8+ezw7ajhRTzRQOSQqUF4+QXNIcXdVISlQUXleQnprRDN1
azs4IU5xUl8we0BWUQp6YWlZcyRiP0JlTHspZigmWChkWSUleVY2dDR6SnomZl9rTUBBNXVvRG5U
d0A/O0xFLXdNT18wJTw+fDdoU1M7TCsKej99Kn5kZlpYKEV2ZmxmN3ZIbHF+Q31PVEE1QiNIVHNe
Q2NtNFhgSDZ8RklIVVNVek8rYDwlYG5RP2Uxc3lfbCRmCnomSEdpRDJUc3UlKDhnVjwzVEspaXg5
UFY8UGxXTTlgV2d5UClTZXxPN351eiYyQSY9e1U7ZjtoM35gdFh4RTJePwp6V1YldCUla3o9e0dA
bysza0ZKRFVUe1RRMFBMSndHOSZDKFZsLV5BR2sxdkNiQ0xZUDZQUFhBeGVlUzFPaEAwa2IKej40
fT5Ed2QmNzdffmNJSyFnS0dibF9LSkdXUWtyYHpMPkZ2cklPfTYxNSY4RVhqQ3liJWJ1ZSZPQClQ
fGV2P0RlCnpJcDJ3ck4wQFZ+ZTRjSnd7M0NPQGQ9ZTY1ZUE8dVIoUU92YG5MLV94dFljWX1NaWtO
ME9Ca1ooWUtNenlHYFA+egp6bnxuSypaJDNWWkZXLUxsRE1oaGsma1psZDRSUiR2d0JTRzJmN0kj
TntyYypzeUF8e2w+ZkMkQVFpRHcmKCF2I0cKek4kUjgwYWdwZnt3IWZkUj1qVS1wQSkzVXokZU5f
RndoVDV9XyY7I1leZnhlKnFjRSQhZzVSai0zc0pRR25DczhGCnpxbiNNOT89fDVIdzUlcmglRFc1
I05yZDltTV5yZyY+VC19UGdtTTRqXm1WPlRzPkA9YiFCMUZ8SVUkI3twY3YwQAp6MWtiaSFgYz4t
RChEQG1hdTVzO2VzZk84IXc2VklWMmVjMlZkYkhyeSNKSH17QVM7ZnpyVk13Ozk5dzlkd3FEWHoK
enh8KXFDc0orZWtSZ31ifVJCYjhJQEtmKj5JaHBhVGY3IW5+Zi05TUU8YzxIVzQyPzYrUl5tYXJ3
X2JfU1VYJndRCnpqM3B5UTY3UVI+QEl3NGRnPmcmfioqfDRxaFpGY0pwTjteSEdrQnQ1TmlaQXBj
emtwQU83a1poaUpOe0tqSz8pRwp6Pj92PTRAOGFnVXo3YjRCc3BOam9DMjlwMFMtM3x7LWw8aVk1
TW5wV05tMHpJR1VvN15IUE8lb19lKmc4KFByVV4KeiFlQVl4cC1AMjckNVkpTmpWKnFMJl8ydFIt
LV5BJm0mditIY2s/MmprVWhmMGtZfHh6UDUhajxvM3hKMVlsc1kpCno/KWBVdEA2N0o5ZEZtTUVk
QEBoIW9SKmhWc0c9ckc4NDQxQm43Y2QyRzkzOz84KjN1Nm43Vih6clRrU3Z0RTVrNwp6KzFwRiRE
XzdXWm9ieS0+eXQyWFc9Q2FVST5EMV9RbTI7a1AleXEpR2Z2MzBBaClzeDZaVUtDWGwjVUBxS2xX
dVIKemgtVzNYPm5CbFU4c0dYKnIxUUVvY3lnJEV3STc2YmJqZDsqMiE/REtgQ2YrXilDclpMQzgh
U1NkbWdNa0RBSyRJCno+Q0IydnVwSUJWNEdCQntsfmtgSipTTlZzMz11TiFSZzRVcjJnfmApc19r
cHJAfFBJenYxSDl1QHN4VHxGRiNTJQp6Jio2SmsjQHQ2eTZDYFpLaHl5TF8kMjFhPTMoMnh0YmpD
NmNvKigkYWR3PU48ejtwa2JvV0wqQV5iZmY0PEY1WDUKenk4QyhANn4hRnlIZUJDKWtgMEhmWHU7
Z1I3eU51fEBfVkE5VXRfflg5WnNgVyp5RUtTb3BPSFpFfUo8ejk2UyRvCnpodG9IbmFLQXFNNT9Z
am1PcERlKnokMUQoREhJPkk+Kz5PbjNTPTZPSCp7X0MtMlJ6bnBTU0JHd31XOypeZUdmfgp6QUdi
WnhFPGJ0TEBqI1JgN2xtcylreWE0fiE/PHM4NnlsPyRfQyRTfG5LfUQxQEZJSD5nI0FVYzk0YGx0
dnQraHkKeih5QGxHV24qfHw+aTNeVz5ifSQhQzRETUlsekFPZmZkTW5eR3hHNzg2JkNnTSN6dkxY
SmEpM1FGTFJOfSlyTFgjCnpgPkE1MnNnMyZycnB8TE89aH52OGxScChsY0pGRjhhfTVAbkxwZDNZ
bj88Yz1AelNoU1klY0IhWHVGJmZ3SSFYYAp6TDZHMktQb0xSeypLPn52ViY5O251VUM1Y087c0Yx
az1qcnwwdHw5cl56byp6P31BO0NQWEs0MTAqeF41WVdrbUQKeisrLWh4Xkk+Z316K0hzVWoweE0q
WiRMMDxnbmk7P0E8VCZkZkh2eSkhJDlgPT97KFZ9SD5JQE9JQm9NcD1uQTtpCnpndVUlVF9teTto
Yk08MzRteDw3KlkoejxTPG48YCFSMylCaDdeYjJhV1hTOVVTPU9jRThSMzJAaExIQk8xfHxKaAp6
RzNXcEFrRVo8O2BtbnBCYVd3Jih6Wnltfl4/TEslO2U+M3NGfjB6T0oraCF0b21TWSEpaHpLPWtA
bj1ySFQyclUKekdsfCV7XnRUUFgyLXM9PiFTKmhJelFwdHBMSDxgSUlZYj5ucnV2WkIxVFRkRjU5
Jj16Q3gzKHF0SUZxeUZBZzFGCnpXMzRrYXNsSH5mX0FeVW50TUo1eTxrKz82JHhuYHdKI3QxfWVt
cnVYUGhAUTM+MXo7PiZwO3FjbndtWj9eUlJxbAp6PGc9NWAqUSg5aFg5fDZEc2dhOSQ2NGBlWV97
MXBSc3spdXM7QUprXmN3JWEzZ3N1TW0oX00xdzg9Zz19dHVpc3UKeiE3SkdOU1lMbFE/V1dMWUhZ
RTFeVnJJNGN3eVl5SGpQa3dha2wyZipUYXJJVWx+YXtAZlZEK0xoRDtLJmVAZkdGCnp6MitNZXZ2
dGJrUWklOWxjIURHQ3tHPHhFYlo9ZkJeQCE3ZkExSzJofEhIdDBvdE84ZHBmdzJwNEZOUFNfUVZh
Xwp6dT1HQGZXRz85KWA2Yz9CeytZdWljQllEISt8bFVlIylCdys0YjhoUDk4QmgtM2A4YkclWGcm
JS0rRGt1ITheTCYKekU8Q2dxOCQwQ3hQN2JHR1M4fnxyZSNmSG9HOXRUbT8tUlkjMkZGX0xQRygj
OFo7ZWR9fDRrY0NMbVIhXmVQNWxlCnpxX2N3SE1iK2tQRDVCemJUYT48LWt3RDI2bTEldFFOeFMl
QF59Sk9wPGQ4JSZtUkoxUnNyekYtLVMtZDA7JTsyfgp6NiRHNDFxcmpsdnQ/TmdBeFhDTzNlWUUh
Jm9vdDx4KUJPJFp5bXZKU2xAKlFQRlhWUUF1ZUkxPVFoRWlMYzRETnUKeitVeXo1JWtNVXhSSTkx
Zjk1eCFkbzhGK0BxYGRvMCpOS3ZvcHNqSDN0JWx5OHpfKG5HWE56OzFuYEQ3ckpecyEyCnp2KiUo
YVVIYlJUbC1iRUdHP0VSYUp6dnl6KGB8d1hCPG1qWjU8RVZ5Uzt0OXo7QnBEPU92U08hJENacGBq
TlYwXgp6NiVfRj03OHxkTDZoI1V7MUJMR0NnMnhrb15ZUTc8P3Z8ZG81RllPaWlFWGRjSlYyYXNt
JXNSN2ZANFIzMHxnPnIKekV0JDZ5bHMtPntkIXshUnRrLXktZTI7V1BRMFhlSTReUz1fS3VvfCp2
KUFeUTNZTHo7MmkyPWpSUGZubT4qJSUqCnp8TXEpKjBOZTMyU31NajExPCo0bk1fYjNHZUNjJUU8
S15BYD9aX348dnA+fXlDajZBfElTUk9RKz02cVdMRSY/RAp6a2dyMFkqSzRhO2V9ZEVFVzdyVDU4
Sj08Ul5WZ0F+UDY4aDdHQztRM3txfFdIWUd5VD87czQ0dz5gYkZycCU7fnwKenpvcV5IVCF9VXdo
TFB7STZJb2hlaX5ze0hpZXVUSWNqdXo+cDMkWFB2RTlmQ3hkamIkUDBMIXFXTypHWGBgOEN8Cno9
UjEhRW5hRjtaWCZgISYzbW52NFg+eSp1Wj13LTRneF8+Zjh4fik8LUE4QGZ7PDEhd2F+ZUM/JVZL
YUJIOV9AfAp6TjtyeHRtR0d2US05TXslWG4tUD1XNF8/T2NYPmg4cEM1K15gYGt3RzY5Ujdpek9f
VUhlXlFaYEBNaHZBfDlwX30KekJASjhMYlc/Vjs/cENUNW1Ge2FFeT0lb0tiYWY9WHhBN28ycXty
TT5XQnVvb29aLTh7XklWK2o9UjNTZExjSUorCnp4Xk1IblErU3U5cGJXVDlSIU4jUEB5JHZlS2hD
fXR0Yk4hMHQyJXMxQk1NMVJxWlJoKSEmUHAqbW4tXmlDeytycwp6JGd1Nll4YWM7Tk1FfWUyNV5e
MUB2eSVGaDZ6TU01U3FzcXUmdjBGOC04Wk17aCl3JmlXX2UlQSlzO2V9ZC1GcFkKenA2YXFPTXh6
emRTK0s2TGNRYkJaaSVufUwzcChaRnIpUmxWIzZra21aY1BvWEQwYiVueVAmPERUQTkjM1dGTldu
CnpwNmh6Vy1OUThgenszIVVQbmpmZUlqQ3tJMHMoUFVWd1V4aER5aihidChvc19mcGw2KygjNyVM
aWVufERwUFp+YAp6N3lUJXohJjRuMUdRbkdCeik9aSlZJFFYcC0kOzVeVmBiS2R3Um5nZFVVSEdH
d1FiV1ZqXko7MihXe0diP31CdTQKek9Xc08qZTZ0R05DUjE0YUl+I0ZMKTNwQmpLIWwtO19lem02
Zn1pYDVldlVnJCZaaz9EVVhJazN7fTE7dWErQ1hvCnpTQUlCc0VLZVZYO0oxKXtWRDR1RDYpQzFf
VyEmPFZwSU1vc1BGTzQtKXc8RlFrKEw0Tm4oPGA0QmJmY0JKZjEwSQp6SyR1REt3MnZKRVBLPFhl
TlNjRytMRTV3YjhxeHlqVkM1R2Z6N292fnBxaz4xPEJofEVURVhQVlh5dVJfSUlqaFAKejF8Qz81
U209SSNjY3ItYnMoeW5uc3YlT0pRekR+NzNta01yISFocDNkeE1hbFl8RjJNdTx7e3VOKj5FIT1k
Z0w5Cnpzbkx9WmIrRnxgczJYbSR4WjFKIStUVXpOPH1vS3AyIV47elE+bWJAUyUkN05oSVB1cmZS
Qj12VUcqVjtEbS03TAp6NGJ0SV58Rypxfj1WUmJjVDAycW5uKUdHVTU/QS1NI0c5aExIT0xiMURn
JF8zWSU3MHRXVU84WjQ1cn15SlVPMnoKenNfMmNJN0d8IzwodC1XP0E8a2tsbWVHKT92fk07dzd1
dShVLVhofTMlWEBGbldRWnFsOCUmLUx4JUg1UEBZeC1wCnpoQWhYYXE7fiRPcVZiKy09QTJMTzh0
OT1UNypZX2QpR0c3JlleSCQ+Pm43PFFkT1ZhVkBKSVVRdWZmVlRecEc+Tgp6PT81aTdxYEdBKVFy
RG5zVkEoU3I4eGQkU1BXUmBoeyMlcURULTBSTThnbkpaTzIxPjhAUmQycFMkKDcxdV8jPHUKei1K
R2xZb3cwZTV1YjRaYj9vV1hFK3gzaTRCKGp6Zih+RTxuJFNDdG1oRGVPcHFxN2ZmRiVaR0pwbUBj
MVF0ckM2CnpDPnYqKWZIMEk/S0JOfSt2KnUpRFV7XzxjZjEzNiNpYnJpQlB0aHRFbVpTTlcxYWFU
aXd4e0w8I35rOXdxb20xJQp6PCo8TW1BTXpkMmIqK1JxeWAyOF5EZGNxPE8lNyMhNnAxUnIxdEYx
ezQlMS02UUc2PzE5YHdVPj9BPEk3X0gmNnoKenF7cFpiQzI3OGdQWVlRMj5WKUckWTluej4tZGde
Qj85d34tNX08M2h3eHM4Ymh4OCtYdFplPGBAViVfM1RIZ09sCnpTNGQ9bWFVZHFzK2JBKGZ6QGZ3
QU9JUmckdzhPOVI+YSU7QCszQVI9cUlWekNJO3xHJnU+ZGhPKmlNOGhTSUYwVgp6T1JHYmg9VFRx
R188aXNOPzU/d3VNNV5LTkpDRUY8Q2lDI1M/RkBrMylJfX02bV47cnMkRFdDTVAtamhxSz5lZVQK
ejJYNCp9ZmxwMiRxQn4hJGUqci1He3V+XzN7REwrbiYtcm8tTmBBe0Y4d1pLRlQ7OV5eRDg5Xk0o
WjdwWVJ2aHZvCnpCUzttLSEtKDctR1Jiel5BQV4wYCpqQ0VHenU/SHoxX3dlI0dYcnB2YE43bDAj
TW4zVXVEbjgpcGJLaUEoa3ZtTgp6Tn5RWn5Bdz08ZzNAaiVXTHxyUWYwaXkmT0khMU9jcGJAOEBF
SEk9QVA9ZSpfa01jSkYrP0pQUWIzdiRvPncwKlkKenF6Knt1aiY7NGduKDBnSHtWXnxkbF5oe0hG
KUNmWjF6eWFybHMjJDQ3JXhaaVpiJjVLe3EzdzkwTDJEXnpwN0tmCnpjd1NhTWp3KSlmdHNfJlNB
VHFoNWRhcUVadSEofCNPSHIzO3lDfVRSVCt7U0ZiZ0Z9e093alY3al9CQHVoKzxkQAp6MnE8MlIk
Z1IobG5YPDIqPyZEK25qSXI1fjR7fG87anZfVlN6X0BSV213I3gwYDxWO29II05CUE1CYU5LJTxu
I2YKemtrayowV3Z9IzlTN0txcW9wQHkqMFhyNTVjXjYzWk9lNXRza08rRjU0e1Z4OyheVW0mUHk/
ZzZHVzhXemp+XlBwCnpSMDEwTzh5KVdQZlI4ZVRqfEB1WTEtY1Z7LSY/aCtqMGF7KFRSZGdNITkr
Z0QrbVFBKCVKfksyNXdCQ21LRkxNfAp6ITFWd1ZwO2ZhWWY8SXVJSV9EcDcmUnxgRzBFMDlJJm02
OSt7aXFMVDw4IyNmeyh1QVg8U1A0bFZ7NCQqTEZSPHoKekpRUlo4ZzlMZ1gwbX5yfmVadHkoWENF
Skd7JjYqN2kzUmlEM3pBXmFtMVdqbUVsbWd8TSl0Q2UhSTUkIzVLcTRWCnopNGNlVGllS2ttbX47
P2lUQUktTmE5R1pfc198a0QlTVNvUSZrNXJwM2YoYEYqWnlPcz0xej5EMH0jTlVgYno5IQp6SCFB
Yj5yeDRRWjx9MGk1X2RuN1VhPTd3JURAK2lTYGZ3MCEhKz8zbylJbkwtb0JKUmk1Y2REKCVvQkJt
e3pyeD4KenxKc0U4PHBBdV9MbDBlRSRgcStYPj1sb1QjPUgrbCgtZmRAU0stZDgzR3R8RDk1OCRD
MW01Sm1uUSElTlNyYUAkCnpOYHY8OGB9aGJQeyFnQmxuXkpJe01mPSEtLTJKIVdYamJWfSEwMk9L
QzhRQHxHNkR9bldxNGJkUD8pKGQrWEUwWQp6bkk8aX1RbD9+I1pUSTc9NkNKJUUlYExfKm56fXAl
QHJQdXBGeSozNVFFPmpCTn1OJHBjTi11MlJrenRRZ2EpZXcKekVTVXtadiFUTTlaNCkzcHk5V215
TTVHdHxjcD4qYzByUWQ4RjZxckI/TFZ8MlI1SUJpSHQ5K1olQDd6NjU0dks9CnplO2oqezk3aSRn
UmsmNnwmekY7cGNAX3d2TDU9bEgmUFg8ZFl1PiFwLU5WK2dmPVI+NUh8dyZ5OEFofnoqKj5HQgp6
NDVUdEtjUntgcnk8RVNOa1ZaPnBYUWxhd3l4U0R1JWU9XjJDMiszeldqKlhRM3QpP1dZfismfFN+
MjNgKSM+WUUKelR3dWBxMjM1ZnhaLUojPEojYUNSemdsTFh8SzVMWmpqM1lmOU9ldz8kb3VEZD5I
NDQ5ZGdvZ01EbktCJkBJMHpDCno8XilAaFQ+bnVWMXtDa1p4JGBeOztadGAlRVhXdXZGODt9Q0tl
Qz1ZX2tzP3J8OHN7TCF2RXxqKzAyNVVtPGQ0Mgp6d3BgbCVLU1EkcHpuK159ZW0oe2ZDSCpSezN4
Xnt3bkUoZnl8MTBUSzFFY1FIJUdwYWYqRnZCdW9+SDJjd3whUT0KemZWWDJEWmlTZnVXZVNneXhm
eE93SyEpMlRPNGd3ZHRySnRsfDZRTC1TQmhFK1I+cisrYT5GZ3UwfThoc0tabWpRCnpXI0I4S3VG
dFB2ZXwtYiRKYEttbTIjQkpnMzw3bzNeIyRDUHw4QVp+d01zen5jQShkJFN1eWZFPUsrRz41YkA7
aAp6LU5reD9NZGAodHBUeUQ3bzUjeiZPN0JzNkM4KFFsb2dAWkchYE1McG12ekRjI0dxdyl7JG1s
Vk1ncylEX1ZsJGYKelFHbDU+SE58LW5sPW49I21HfCpJMzhhTlA3Sm00RE0oRzhTQWcwdG1FWG8r
LWQzUHYzYTx+alZkYj1gajRGVHZ3CnpASWtLeUstM1M9ayNlUGprU1AjYEM8YkJrT3dqdzdaRFlv
OVRIPzN7TUVnbzkmWU9NXnJUNz53YTM5Myg3dUFTcwp6U0YpX05EQ3MqSms9bEt4KEwmS0dRe2N1
ISQtKyRAUl8zLWRtallNeil9P1RCT184QnJycVg+b1V4QHdIMkBwZykKens1MDM1e0RlSTE7bHRE
ZTBGJSNtaFJ9OVBeQGV6RzRNWik2NHFkdGVeck5KdCZtQm03cDlEQmMrX3ZmNGFmJl5ACnpwWn5A
QWluTjImSCNPOCoyUE5pTHIlJFAtQmYqaFg2PENLQWI1bk90NjwzMGxOUSU1SmpXMTBMNi1ac1k7
JC1tPAp6MVZEenA7Z0c7NFEyYVhwJX5zR2dtMlYyUWRpSm1lSiNUeW41TnFEe3NLX3hAMTcpUjFN
SCtUOVNSfWJLZXdLPyYKelBEUztaISNubjtgciRKaVItYUZCZE1LZTdDMXAqMGNVXkpINmI9fFhE
RlFNVkxiODJtclUjeHRVMGg8fVJWTUtmCno9dVpGLVhUe3dHTE5JbDU1WHIqTDhQKXg4RzE9SWRG
KE5laSR7Mn1yPDxFdV9hezEwJVMtY0dzVl9CaW1RQUlSXwp6QT5IeWltY1JUSUI7aClEWDMwSXRH
cnBTd3BVZ01XZFFfNGVzbGlBTkdpRSEhYFQ4WH1QTlI7TztLeDJRZUJvQXUKenhJcUlvR0pmOD8y
VjZ3KEc1cVYpMEJPMTNeXlZKYWt4PXdiIV9MPFpIQ2p8VzBuVztlVn1uZzQxQF41SjhObEpGCnoy
YSlNfFhKK2oke1hHOzxMXzJtbGJsZFhucWQoaWR7QHtoey10QGUjYGlnbmNvZVM3S1B9Xjl+dTVW
eUkqPnpqKgp6dndLRHRAfSQzfih2NGF1I09AYFgpXz5VN2AlIyNQdW8hOHYjIXpsUTNoIWdEaXl2
fFRsfX1MO0JkJHMtd3NaRiUKelZJaj99eyo+SjZRfFV3Rj9ndD52WGphTUdkWUtOMzxmbj9qZWd7
eSk9PGd2NlNwcjlSdGZ3RiExNHtjM15PTS0rCnp0SGNtVV5HQyV7SHJmJEBnT1EjRDhDMyU4ek1k
TmMpSnUqe082NnAybkY/Zm08TmBwc2JURjJCK0wkcjFEMmFqTAp6XmdHcXVoeyhaJT9VTFZiMTtu
d2ZHQz9Jemx9RzxAPVBtTHY5PE1qRWZYTWh6ZUlgOTEjMFM+NjAwfChxVk52dHMKemlMQXpGUUFN
XjxBdVhUPT9DYDE1PzVQVmszPFMkbnRKMEdWfDJeYHlZWD9nZVBsUEZIZEE4MlhudlZObG0jK3Bx
CnplITAxIztNKlFYTzhzPUA5WTxhVEZBPHklM3dteENrOzlUXjt2Z3hxRDx3bStOc096KkBqY0l+
UDxvQ2VjYCRnKgp6SG82dk1ZS3d9SmgyX345ejwjTE5PXjNBSkZyfjt8aFUkd3tpS2NxMXQlPSN1
VjI9cj5PR3RTM2FhZXc0K0BvU3AKenZQWlI+S1doO0pEYnZkTlo4UCFiYWBWeDJeaj08a3NwJFFG
Z0FYVkBsLX1XR01YRWQwZU5heH4rcS1vYVhVQkllCnp6SCM+My0+Y0FFNWM4N2sta0xsY2o0WFBn
JiNafnpwZ0deQipaej9DMDBhLXdqP3RKbXZoSDw1ViNrV1k4Z3QpSgp6Z34xSTxURy1hOUE/NUsr
THJmTm0jTnx9UjxFcnBTalVqKU8pbUl0X1FQUmR3blRLYkx1SE5NcnlRPHBGR047QEAKeihZOFNX
OElRPXktMiljbilXNWYpb1R9KHxScmImQmBRKnFeUEkjIWtQUSZJezd7XktlU209MkcpSXBGUll2
QWIrCnoxPT9YTCpUNzA3X21BfUROVWZrQj1sNEdKJk8oV3VKa3NIU084MFZ2ZDI+TVctMGFwYjB3
XnFOd2ZrWFJBPT1ZZgp6NntWalQxNWpLdHVZaGQ3eFJFMzgqWEA0R0VeblMjV28raSteO1p3PUs+
I1Y4cnI+NyVvc3s+S083QkF0OUNma34Kenl9VERlbHxsbmt0ZWdsZzB0O0UxVVhWU0FfRStRa2Jp
Q3lGdF5uX2UkI0paWT1JOUB1eXk8ajE0K3s/aj1yfHlNCnpHQz0mQVBoP3thcEtzISVSIXA3YTNr
QjZMbkBmXkJGdHsyZzVgKHl0JmEmZ05YViZvKXRrdXhBYX5OWVdrbEpQTQp6KyU5cDxOVUhMV0xp
KXM0amFoaDJufU9+SDFaV0xSeTBYdWJBRmpNUkF2Yk9NQD5IYkw9PG1kaHc4KUJuQypqO2QKeitZ
VjxRMUpIVEI4YU56VUtibGFKKEZjNj1qPyVYU0w0MkRKa0hJT2RoYWMwKnhMMG0/R1V7O3YtUF95
Y0ZuQD43CnpLeEFibit1d3NneW9YVXw9RFgmMz0rUERQPFQ9VzhLZnJscStqM3VPWns0UyQwJVZA
bnBoa3o4VTxxdWEhVWJBbQp6cFoobEA8QmJZZk5MWVdnTUQpVUFrYy0yYHliWCstSCRBV0dmelA2
N3xBcj0jWn55YSZZWT5TNlNma19jV25RfDMKekxTMFlxek1FKzd5KlE2NGJRb0JseCprPTNXKiVM
dTFlITVmVn51RzRYa1luSW45fERmUSVgKlJDdWN6SUktcTZfCnpzNXpUX09CZyVmbG1hPE5qcmhF
RXQ9KmlDYm1CJXY8TzV6cE0xUWU7WEQ1bXheWmNJfj0kSF5SK25SKkZjeD88OQp6b2RUdmFpb3V6
KVUqcnNwQjNlaE87Ymg9WiZxbGdWRFMpckxGciZUPCp0T1pMTilVIy1OcCp5aGJwYFZHXnI/MEUK
emREQWAkJiNpTz4rK3UlamUyfGNNMk85OT58MmBERCQpME4lelk1bDhKejZqWUhhWTcxSi1DUW9f
SF5YSj9VQkFuCnpUbUlSbzFHQDhWUXRldSlfdDlKc0U9Mkg9aDs2ISZ0PTlmQl5pTTNeeCNocDc2
VWV1YldFZzF2PzttU1A2cWpqPwp6SClwTmAqY0ZZJiNlcW91S0gyYiVzLUVge09XOXRBJlVxK25R
VEhGa19iR1J2e0BKWmUlRCVCTHhsPjVocDV9YE4KemB3NTZQJn05KV9KTUppe1FWRW8kMmshb1pH
QHE7dWJ4KXRKbV5iZ2pQV1o4RlFhK19MaDh+ZT1NQHMkaExfLWR1CnpAI24oVm1YWkBCfEZfc1Bv
N3JzelA7P3hadSRmN01VMD5Fd1NvZ2pXRjMheSZNJmYqcSNTMF5MQDFEVUJZfmFINgp6dTBrMyZU
I1dxNnMqfVRAVkF0Vytve0hIV1FAT3B1RWspb2IlZVNtJHdpeDd5bD99aTxtRWY0NCE9bWpAIWtx
N30KemAqTzlacVN1eGZwZndCUztASkFCUUw9ajhHcihpcmteX15nPmRiRz1kJVNzMTxHK3FzNnha
VE9kcDF5UHApP0pOCnpPe2khJkB1MTFWKWlkdjxreFIxUTYoezZEd1ooMmtAeD4rST9AWFgqVHwj
PC1FbSp0O2F4RyQ1K0IjOFgxM2JEZgp6TDM4YipGNWluYnEmUTs7XyY2TVFURlJke1AzIVF9dSRK
RDNYKl9FQTRIZ2BqcVZte3xhWngyMFBpWDxofDlRUTEKenlqK3N0SzYhbytqMiheU2xAK35vbF9X
TGgyR3pHZ0Q8JnBtJCglOT9KIShlaTB8ZEVONSotY3A5fEg1eDJVeyk3CnohTko7O1FveGp7UGMr
NVAtVHhaRCFNIXgxZGYmIURQfTNyWG1sZG9wRjJTcE9vT3BJVlI1KSs7Xyo3M314fFhPaAp6PlpL
YWxjVytRTElLUTVXbl5PRHZJfTMpd1NCRzVoZClAOU5iNXRnXzwyTlBucTR8cEJDblNPWGVLPHsp
YmF1TE0KekVpem0hSnxVTldVcUNybXcwYnBSKE5fKH0rOSg1akNEfkhCO1FkMFp8RmxwV3Y8Pmxw
WFBRZX40cHojb19MO0hRCnpaMSZkbTgyeDY7JXZfQT45Y0Q/I1NEU1F6YWliR250RFRoelFyPmpi
KWVgeyohT1RvdVFpXnhMeGtgVTEwans9UQp6Pil2KXYxRUoyKCRGQzQhV0d2Wk9Pc0tmJFE9a15O
NmxkJTZHJHQ9OHNaO3VzVTVTKUJrNUtPUTxKdFpjVSgzYXAKeld6cGRvOyVKV0FmTyk2QjI8MVZz
aFZpK3E0bnQrViQkflRvKlpYfSkwYDwjJlpja0VlVHB5KzdtelZyVHwyMSV2CnpsUmxTSUk4VTZr
bWEpUiFodEJidilvNV8xWFdiZCVLUEBVTnArS0pjLVFwK0tONU0lRiRhM2FWIzQwYlF5WXtRLQp6
OCkoZTtuaTZgPjRgek10XzV1dnxCT199KlRHM2ZnJX1uP2NxSWY9Wip0VW9ELSU3LUZUUlhDTkcj
byl7eXFSI2QKemVQRE5EKXVtPnt3JDxtaWtEbkM0WUp8ZXNWdzl1NT9ObFByMisjV14ock1ZJShl
RVk8SHQxIWpDPnQwVHl3TXV1CnpJTTkzNTV3R2MqZUhfbzgmPCZqNUJgNCZ3RTVaeXI4fEN8REV4
UElONFZDbm1JXlZMP2JXNzEkeUpfIX03WllXWAp6Wkg5TUJKeFZTfSM9LVBjWXZVQX1eMjlUSG0h
T2B6Vz9LWHYoKzk1WW04SWtMWnZAUUF7KiZWPm5MNjhyeiopTDIKeiNAb3pZYGVVSSpSR1BPOG1r
X0lPRDZgTEx3WXJ2YU8kYXRMVENycTFkYXtMakFtJjZXYDJUYyR0flhGKFVLPkB4Cnp2S3xnZXA1
eHpzMXpAVjRKRj0kSWltdzBuJUBEbTZ2YWdiRUw0OWtLUXxEZiskMWQrIUgjTlRHUk96aypLYVh1
Mwp6cE5xJHJreXY+VDspb1ZERW8rYjBAOHdwYCFMUk0lJFI8IzE3cHoyYWNwa0xZO3hLc2dRdyta
UmBqYVIhKERTekgKelU9UjRabkJCemNYTG1YOVlLfXt9Qn5BLX1WS1VyfiF0V28lUFl1VWRZI3ZE
Rjd1KHE/cGdIX2pMVGxLKz1RWHZfCnpzIyQ+IVlzSmJjPiZFVUtxIWdGYlNSZVk+RHw8aC0hJH5s
clJlKHRaT15MZTNPXkJjeWlTNGA8fEdTUjlKc3RaUgp6I1VLPGVMdXxtRCFWYjE8bkRvY29KZjxT
WDhLeD89LUFtSDNeQ3dGbUgrREQ1Sj8ySDxoQGQlOSpVVnsyamBLV04KeiRpNUNrMz1gKXYkcVpR
fW5+U21OVVZicFN4VTlmQHd8e3dAaihxaHFEMkhjVD5GOSVRZCZ7UzNlKk4zUGtTRldMCnp0WFZU
SE4wXlR2PFEqWV8mVkpwfXRueFhyKWhnKEVKcCtXP2MmQDxgPElAeHw2SjxMSzVSRWp5Ji0+aE04
dmV0Xwp6X2pWOH4+T3tFNUlQOFkodE5HV2wmPmVBWGtiYjheJFkrQXhvdSpfUXVwMl5jOyFZQ2RC
Y1BUKmdgYiFXMz1AI2oKejhmZ31yNjwwY0A0ZmJ2TUFIeStXVSF7JEl2KjU9aG88RWRySUtkYVlo
OT0pYURXKHdYQlR9UlE8OFFeS0xQfEclCnokczA5VFBWNnQrKzFIPV9sJEBScnAoZVcoN2l2bmlv
Y01ed0UhVHRPZXpBU2F0TzlsKnhVNkl6OHpRcVhIaHpCSAp6MmU0a34mRChadHUlVXF+WDA9dmxF
UC03KEdNZ3t6UCs2aWc1OXhTMExDbzFwUmNoSHVUWEdsVjRhUVNEKjRndj8KenhAYXUlKlczdVRx
a0k8TkFRQDg+I1BpSER1aypGRmVwZG0jalVpdnJIWiRJNCYtT31LIUdyTV5zUi1VUVVlQ2ZVCnp3
VmJ1dEN3Q3lhV09HemFySkNCZHBzKnFheVEmP1hNdiZRRDZVbUliWSQtdFkkQ2I3JWBVZWwpNDhJ
SDFAT1oyVQp6TUl4Xz4+JGFfQ1NoeldCZVEheS1XT3VuIyh6NG53WXlnUGVGcCg4R3w0fUNPWCh8
Z3xWKUtmXmBLMVN8PkFCbEUKem9KfWB6Jmw7ZTdYI25yajsjd3g/YU5fKC1wQWsqYFMyMk19TmJ7
eE1PQ1dYVzxUQTNVWC1VcDhFYGJEZzBgakM7CnpXKiVqPTFiY1lMITkoLUtLZiVkZHB3UmlDdVhQ
O2FBWTEmYykjTXg7ZDxodGxXRnleRCU8Z21vcE9ecntgTihPJgp6JEcrVWBEcmx2fSomamQwJiVP
dF9XO3V2bk5feFlyQ3VaSilUQ2ckcCo1dDAoNWpUdFRLM1NqNGd5SF9TJmEtMk8KekdPdXNra01m
PkJnPnBqSF5yPzxkPEJ4WGs3cytnMklsQzZgalY9NFBhb2dmLUZZSDVhVUNeVSZUTSFKY19XSU59
Cnp5fGdobDxIb043I2p1fjw4UExSQXMyNj9OTEAhXyVCSHJTVUhFdkBPelNEQ0NpTkplSUc0WmVM
blJYLUdoK1JHUAp6Ty1fWChgNnBAYWlPfmh7U3ArLSU9MSlHZXpodipjSVFBKGNDQ3ZQT19GJXle
akR7Ym5IUmgoaHN5NjtNYXo1U2IKejYkYzNtQnhWTWZAdSglP28mTSFYRmlZc1lCcihIMGN2SjBt
UEB2eEJiUHsycWJlZ2MwWlBGWkRmQ1NuRWU+VlBiCnplJCFTdkQyOTZ5QU1FbElWZ0YxO0lyRF80
R24wa3IoKEtRa042YTxsXnYyWVpObns7dndgQilaYjl7MVZeKil0Kwp6I3FsaCtreFhyKFFQe2xu
e3F4PTNsflAtI0VZZk89S208WUZlK04mTjQkU0g2bUwtRlJNUkJUPFlCXyorJFojdXQKenZvUkt3
WV5zQUw5NkdsQHljRC1SLUJIV2M7RElFRXxGcmUhWXE+Xi1IX314eiR0cU53O0x8V196d3BVN1N0
ejJTCnpPI3J8ZXw1OU5NSFN0QSFHfnY2cUs+TyE3e0hJXzBPbn0xOT4tWXlGT0dvWl41ez99Qjc2
c2ZrUCg4UDY2NSs+Ugp6KGp2PXZKbzVzdGhlJU4mWFFsYUp7Q3YtVl45IWtvMWIxWCtRXnFVLUw9
NyRMRyQqd2pJSSsqV1p+SCMpbSRVeG4KemJtRGohQWl1Tm0jPHJ5TVhQVjdadHVPMmV8RDJ5djZi
VEY3ay0xLUYtLTckZjteKXU3TFF5bnBPU0NQIURXUStqCno2MXhfXkAtKGlaPmZJcileTzZBSyhL
fX51N0U3TXZzdnBkTzM2QHdiS2V1TX5ScWgwUmlAPEtxTXItWFYpKE80VAp6UF49dGB4QTxIMiN7
TDVnZ1g0VGpYd3JAaiomSmAjeXdMancpK1c7Z2lZTlF0TWEraHFNIzFTITxlazJpalg4a1UKejF6
QmFDPig4fGJCYz95QzNlUk8yYUM8ZWMkWlVHT2RHPio9WmM4eThvbDRkOXM/fXN8eHVQbEFAV1Q8
PHB3ayhnCnokfDg4VytpIUs4V1cmPCRsTXFnamRxdjRVV1NgWChLd0o2RSQlTWw1JnFoPlIzem5A
XkpSRyRgU2gjfkE/O0Y7JAp6T1IzV3JFMlNfYSVLZTJaUnwlU31JcWo/Y1k3SiNqTEZ4UllgeE48
YUF2fUQyTjQrM0s5Tlh4VVp2REFhYlZKRUQKeil4eClQRX05PEI4dEVfe1NWcDVCNSphRlpwVChr
N158S3xjRUlUYDIreEMpRXRGPCFNK3d0eTtKKUsqKy1kQ3JpCno5eD83TmUzV147SUMqTCgqfHMx
VXlgdTJeeExUPEtuMXVXSnMySDZQdUpfVj1NU1NWbjkzNVNFPHt4aD9KU15megp6YU8hUTNmQiMz
MWN+TUUwLWQrdTVHb1N3cFJLaCVrVyt9VnZHYXBfM3dXeDAlLUItVSkhUXZmfG59KiQ0RXh5SUQK
emApSkhJVzdXUEB0KD9QQCpuNj9jb1I1bHk3S3NleUZpKSQreVohbTU9MnR6SDtmVCsmUURFIWFj
eCo/YmhNTjdgCnpkOTY/ZTUrNTg/dzNNNF9YMT4/bmN6a0QqVGZsUHxqKkpKTUNrfSViSlRBVTlA
KndWS2VkbDc4NHhjSGhyQDBMeAp6PEluZl5CJSV6MFohOFl4ZytDSTFaRWNhPCRAVDtyP2tJfCVW
S05rWXdKcisoOXJ2PlhjJn1oKjdUVWhhQ1F5PTIKelJCOT1aMjBFUHtgcG1KQ18wfX1+I2YpTDJE
QlNIQWI+LWFDYWJIb35ANWVPcEpEcjNyIWFKaGdpcXJxJGBRQ2tXCnp0OGF5VSpzXzZjdEw9fDNu
KFBLJkZGQS1gO19kSyZhe3NPZSN3KUF8NH54X0IkZ1VecmtAVFVycFFMTXY4XyU8YQp6NT5IIXsz
OV97JTFxJTt3YzlIR1M0bUF5SFNoRn5+RSRHQmhBOVZoPDR9P1VWIVFsQHZIdzlCN0ZHUjE/ZyZy
P1oKemZhNDNYWXQ0VHFCTW9zZllidn57SUA0S0lDKGUoODhwP1RQSSVfdE1HWGV5cG15cmYpN2U9
ZkhPWU9Hb2NeUzhOCnpxR0NmTCFRLW5IUkY3VTVaJDQ+RF90JEtARCt1LUY5MWEhXzt9WCp8MShn
NE9pYSVJTjg+TipqREpDO0pqRjAkawp6Jk9mPUx1IUg2Rnhedl5jQE1FezxVTn1eQihGY1EmZUJ8
TCVye1JSSkQ5PjtFZEkqP2U9d0xLcTBsI0xzLXFWYTgKejcmenJ8P0ROQjVLVmdsM21kd1hPXjs1
I1ZsTHdGZnVhb29lcnV6Uk1gMXsoNVltYmIzJV8xQGkqJmB5XnBYfHNlCnpCVj1TfVRfWnc5QnIt
IXFYMl8wOUhyWnRGODc/MVdVKyhYOWArV2FgLSNQYyhiSS1aMntkflRqdWpndyNBN0dVIQp6fEVT
Y18pMiNpU1ZZfVY4azE+NlhnPnRFaF5JPiU1JDxEZFkpbj00KGtyMTE7cnhHZGtEN3tsOFgmRVBE
WXI3QVcKenclQTs1O24+OVUlS29QNXBpe1kzYGo8O3xUNSNqTDxsR21kNzFMTS1eTiNLc3M/diEx
SH1mSSNgdDZfKE1RITRnCnpLP2oobyFlQWwpMl5tRGhsJD4la2dabj02TE5jYDluU29OV2JFOCRz
QFJ8biVQVzFlXiFxfDdJQ3pyYGc+MWVoegp6UmpCeX5iTmVRVTJ3QWl3S21mbn0rYWkzR0pRRXoz
ZWhkVkpyeWhKMjAwLUJlNVIjWGBNfHxYXntFYXVnJCpUSHEKekw1KkRCMW9XYHE5Xll0Qi1LdUds
VzRYTGwkP1BRWFgjbEc+RTM2KWQrUHpCSnAybylReXdDNlU/SkMjIUN6WE5SCnopJmNIb2Awd0lZ
UE5ya0pWbTwxR0g9M0BqS1Y3TihpPDFSR3JGemRxRDVvOFI+Z09uQENBT2xSI0J0QV9HbmE8Ugp6
M30oQzFVTndNfEttfmtMYlhMPSZXcilOWl57JE4tI09fO31HYCZHSml9bnxPYjV6S0J1YnJ2c2dl
eVdfVmFvR3QKemg3YX0qMUkyXkU4V0whcnMrZEdHTD81UDRZXjl9U29Kakt6TCNxY3ZXVSRMP2hm
NXlveTRsPCV5ZSorN15pfjdKCnpXRmFDVlkqZnN8Rnh6RypMTWNRbS1qWGhINEhINkN1WEhELW5Y
TE1XWUxYP2tSWDFfeHVPK1deVyVCQXlwSTF3WQp6ZlQ2QXIwU34wd3lRb2Qrb2RZbzlqSEVHPSh+
aEZ6eE8zVWVNbF58WihQMEMpbiNyQkNSSDx5MVQmeFV1dTYlTHEKelBLb3Z8cHNZMWMjbGZZKiNf
cEtnOGBObXRHNXt9ZDMreD5xIT19c3E3PVVfOVIodktgbzgwN3BKRilVcnVqMHpxCnpPMjJ7dz52
NExqTVR8WXc8Wil5Y3B1Q1ZsUnFle2hBZWFUKVRTSihxRlRWSjNMdjxZTjszYVYyKWR7ZmJzbTJQ
awp6Rl40JXVGYD0mI3soKGMlc3V1fmdOcl4mSXYxPE5QeUVTT2FKcEoyP3RweX1MeXRtU0RqZm0z
REdfKnhoOFB+NmYKejYrTlcyU3dtZDY4Rjt3Xj9oTWJVaHY+MFdiNVJ9R1hETD8yJkV5NkxEVVNQ
MUI0MElGKHRfTTFmKjdRJHU1c1pfCnpiKj44YTxpQTFtVHI4WGA1Qz5WdnJLYjIkKF5wWmthUTRF
U3pAbihyMStmJVlPI304PV9tTnpzYSNTemNDbCMjfAp6diglRDtNN0V4PDhgKTRCcXoyRVhDK0hL
UjtPcGZhV0YjM35zbj1neVh3OW4hdjFhYTdUY3YodFE1JHlAP2NXWXAKejdLNmAzXnhfbVYxIVFe
XktKcHRnVUFCQlM5bW9Gc04kWD04MTZuMCYydTk5UFglUSskZmExNnVWaE95WWA9MUUkCnppT2RD
MjNhM0BwMzA9VzBtYDd+Uk07fWJad3NYSWZvIUF3Z3NDaEU1RjJhZ3BOV1YoYWdtan5vUmo3JHox
WXkmcAp6a1A8Y0JrRlRHa0JDbyZ5eWc1IXlXdndqeE82fDtSLWNvfmRiJG5XfmJ0QkJ0KG5keENY
Tyl5VWkxIWlHPSM7PUYKej1CdDcyQFVfVl80bD9Tbj8/Z34xeGN4PXV0K04zMHVAR3ZIZ2cqU1Ra
YE8+YWk8bUc9dWBVU19hfjB1fCEwN31FCnpGLVNgPEd0MXY2YHBRWThRcVFKXkRQX0Buc1pJaVFj
NnZoOG9VVE51Yjt6U2ZeZ0Q8NXs3WHd4ITRNZCFOdWctMwp6UypaSHpidXJkcld6eU8mZV55STNx
QH58N2R2I2hsWEAhO1goayR2N3p4cFM+UjB+U3dpIypUYTNwfHlKdzc7aW0KelJLXyhGIVNINXo5
aT5oJCtIVColPDFUKm5KJHVUTmw4fVNQbSNIdiUrUHc8ZGpebzhEVyF5Q0ZhSC1kck5WMjJoCnpZ
dXpab1lgSTZHZk8/elktVkpOQTZnaUNLMHlsOXQtd2NSM01NWnEmTS1hcnptUnAxbGhTPXMoZnxK
bktIeng8Mgp6eld1bzZNM2VLNih9Z141RnF9NlEmS21gbjNXeEtDQmdFa2Bwe0ZWKSskPHswRHFW
NEdxPiNiUWR4M2goSHpBYj8KelVARCFacUd0OXdMeCt1dDMwMUVZK2whYmtoXkVYWntkQ29eXmBV
SUhpcy0tTHZgPnxQJD17U3NVTDJOe3BxVFllCnpGX30jKms5TyZyVXlkdl9GLV5qZ0V5RE9BVlk2
Oy1DfUJgVWdySkU/PWRHaWpjezVvMSgmKER3V15DeklkPzspcwp6RE9Edl4kaTRMTEJTTVZjZns3
bG5TUSR6Q0l0UVh0MHE7ZWw/STl1PEVsfjspSUpPRWF4ZjJaNjhsIW4mMDNMU08KeiQ5dTl7WHtv
OV9wIXQ7O0s+YDFBb3kmQzNBQUxQbk0/LVAtQElfOUBPPWd2UXM+O2FjNGRoTXNWeUJjTztJZlYo
Cnp3YUJxNitZPlNMRTxZelNoYihiJFNxK0BXZWQkfCRQfFdCRWNLUlR5JmBwR3kwPkVffEleN14k
Kn4kfDBneDFHbwp6QW9gRGlQKDQ5K1oybFNYaG1VJiF7R19QZXJIKlFLU31eRFU3N0AmSU1GZTF6
QnRVRmhyKExHNlpKSlZvQnc7KVYKemIwJVp2UUl9YXVjbFlBJWZHSzgpSX5wMSVAYm5QXkdTcWJ1
XiNsJn1fN2VVRnBIPCMwQnwkSm4oZmpSJnhsZjc9Cno3YEIpMihjWExzTitJZXV0Nj1kRCZTeVAt
e1lrb0V5VUQwYyF+PTIpPF8/bFl3fHlyRUZSP3g5ZTE3UHlqOVpHbQp6dWJ+SGx1Nm5SNVQzN1dB
Iys7enxkazIyUTAyJWNmRzQqfSskO3wrdVk5UWooP3pKa25ZUEZiKVZ4fE8pTV9YIzsKelpKZyVT
JDFIUHJYdSpXXyVgMHcwVSM+azwkeTl8Iz9uV35uRnZxa3p8SlBJc14jbl8/UkI2VD1yWCEqQk1s
aG5HCnolTWNYKkhSWG4qKUZsdmFzbjJ9MWc0e09SaEpFUHg1N2tFYHZeWGoqRjNAWU1rdmdYaCU2
JWBBX1MwMT1xWCpWSAp6YmFMVEFzT1U1dUNNeGpMKjhQOX5mXmtsZnc4Q0QzYzBDI3VGZl56aDth
YVM2I1lFQWlrb1orKWUyPTYtV01ofDgKejB7VkVSPU5Dc21PZmp3QXdQZW0ocUk4VzlGUkgtekFl
S19fLVJTO1d7fSQ8b1B5NVdqMFVxcD9PaExpeVY/MkpWCnpUZXhFNHdTKFgyckh7NGUkV0IyPnI2
VSUzeygwMSljYiplU2puQlpha2ImOz0+bVdpIXY2K3JlS0ZHey0pSWo0Vwp6cXFgPmtFI0pRWnpg
N3ZiKF5fMXVAZl9uS3RRQFFnZVZlR1RKRE11NEl1Y31iQ2MmM2E4YSt5byoxTmtzXjVwXkgKekpA
KyQoY29QVWg8eGVnNyZOeClzOUUqVmRkdkZ2bjNWY1dDc0o3cX5TNzk5R3xLPH55Sn1mcSkjQENO
QGtgUmNNCnpTeHAmeFYrQiFyJFNzQVFSe2ZOQUlfIzEwdUZ7VWA3QGxOITE1JnxKWlB2fX1nRXV5
ZnpONH05UTFOP05Ma1ppUgp6bW90ZHwzSktRUmdrWCRUNSYmPiU/Qk4qXyVHTnsqMipCbyM+MCQj
V28kZGFQMEJgK0ZJOTtzRndoNlFWeyR4I3EKenBic3tPUl8+M2NDbmx3Tjg4IVVraChNKENCdm9g
PGgtamBfc21hQktVbW5jOT1nKTM9QzFLRmAoIW9VcHhKckJWCno+VW9RRWI8NHd0WC1QVWJoe0kr
ezI/fj8xU2w8ZCNAV0YrU3tXJjxIRmt2d08hQDxRdmIrUG55WVVFYkd7MkJpZgp6ZSZ+cks5UiFL
PnJycEJyJGU0Tn43fm5SYUJ0Uit4T1lkPH11YihNSz99WXIwcTlISDRDRERyN2EySG8+dDZOYSUK
emJBNmojUE4xdiMtRmgjez17aiZvbHd9cC1SdkxgTXt8ci0md3laR21pJjFeZGg8cGM5SmlpajdJ
e3ZJR0d3WGNJCnpQTUF7ejQ2cWo9TzJYO341cWIpOVFyKXU5eCEzfU5qfTMkKFQ0Mj52YD0jJlJ5
JGdLdV4kPDUoOT45I0FtJiVlbAp6NSp7NWp4RC1jP2tFZ3ooTjNVbVl7d2R2Vyk7RXFUOGVofms3
fkRZP2B8bkZDJXl7R1pZZkYqQk5fPTUmSCNRdHoKelUlOXBWZz9GZCVUcFlxb18tfm97WXdsUm97
TSRKPEl4P2IyOW1YYXIzbCNIJmp0RGs3SXg2WWs5SEliUT8+fTh5Cnp2KEd3VG92MnVvb0JkVml0
fVYmZCl3VHFwbzBHKXJUVmUtJGJDYlZVVG1MNVJ7THZsYypFMVNeK0JFVmQ1bThXNQp6KGx5d0VQ
Z0k/eyFKP18pdiQ2OWdSMHBUSHRxTyUxM3JkezZCMzZeMWB0P2clajwjeih6NzQxdkx6e0RUd3kq
d3YKellJWDg9JitzPHVyXk45R3dpJCZxKDJSQjJBRlZYYG0xT05hMFd9PlpGbDkzeDlNVihWKXwt
IXYxc041ZGdVOXlNCnpGK2cjbDU1OSoqUWFhVUBtRihUTV89eEROSzJZTVBQY3whaTNfQWZOVUMo
ZSpQZSpFfU8pTjt+dilucUgoTTRhfQp6Unt3bnApVDI5TWAxZztXQ0p7NTJvOHM4U2dFKj9XcHs5
QWhyWSt5TiVGND5WMSpIJj49Q0ZVa14rUnAjJUZLJHUKenlHJHhlcnN2R2leOUhqbF89bGIycjhy
I0spWEdxZUc+R1hRWXk/KDB4I3RWSmAmTzkoQGp3SXtJODhwe2hDKjRHCnpnZTNQYSprIXlqKk4p
RWljbHwtQGMtdk48VG00KVkjclpnUHY1cy18NmtjRjc4cyFzPzArLVMoYVBObD09b2E0KQp6MDhM
VzgkcjYrQVcqOHd7emM9SXVKS296KEtlK0AmTWhpRmtfJGV6ZHhueVlEV285TS1iclAjRjZNRjY3
KDE7dC0KejVTfTY2JE9KJSlIQzVqXjtxOC0/OVJONiphKn1YRldhMEpCWDk2UHUqaVJDMiREa2U8
NyF9Xyl7bT0pKml9aF53CnolUz9qRG5IQGBtUWs9bH1VKGV1K2E7PX00ZTUxelpIWEtHeUNrQE5U
dnB1djMqaDxfTVh3LTFsWWtlNzZNPDt2Ygp6Pz9YWVVlNz5AWCo5Zl4pVlY4I1VOcElMei08bXRx
OyR4cUZpfkBGLVRgME10I2shMXN7eHw1KXJHRCRPcnIkLXMKej5yVVJXMkVqa2IlPUtIbWY7ZjxW
ZHU4P1RPd3NjUUw+JWNmSitSQTNzPzxiMnZJcjBaX2N+MSpwa0ZlZTw/bXk8CnpDQG8wd2BPQnV5
K185MXl2c0omVV9Xa18pRjYkOGpsfndYLWNxRGZGSFYlWEZvfj1RMlcjak56bD5xRTdtPE8wJgp6
LW5hcGIqUnpWTFhUO1kqV0JKZnFVYVYkOVlxOW10eFpmRDRQOFlSR01LMSgyJGJVcHtlQGF7V1da
Q2lpcWYjI1EKemVfJEcleilIJTZIYmJSamc9fDJpVj93Z2RSIVpSKXF6biNwT3xBI201Sjd2Q1Em
bGVMbDhPcXR5U2YwIXFXNm5ECnoxYSo0KUxYJW5IcUotKHVpKXtweUB2PG43Kj4/VF95SUY+LXBU
bF5lK1lOd1JeVWI2e2tvJEI9SE55QUwhV157RAp6PzsrUEYwdk02MmAxTi1+WVl4NWc8P3dKT3dg
Smo4XzluZyZFV2ktOXgzXmI0NDA3JDZTaitJOWVGMnItOFBsaVcKemg5R0sle2h6bjBHdSYzNlN7
JUxEJSg8SFFXIzluVlJoeVRDX0YtY1dTcnR5K0NOe2R3YG1RfXdxN2UpRjtHK3RXCnpqMCV+NFRm
Z2pSU1ghVWcoNz5NaG5WfTg9cGI2aDFiNiZOI3Q3QGpucE5DKHxeNHwqNUxsRmxaPHs1KHcyZU9D
Ygp6azh4dzsxSUgwe2I8JClaeF89PWBMdEpEODh5Z3p+PDBKcHA8MT5gPGc8dmpQNyM+MGNGYn48
MktUOFVgRlhhMEQKejhVVyU2YUJ0bysjJnZ8Nm1MOCNYPFdFfDQtbFhxWj1xcW94Rit6fXtyKnNC
fU83P2l1UTVKREBmQk9vTXtpcFdkCno5elR8TGl8VVMma0lkRlFxYGU3c0ZQUlV8TXV+I2QpX3Yo
eCNrWGckPUs+Q240S2kjN3Y0MmJWUC1IV0pgIXI8IQp6K0EjfjdGPTctbnt6fEJyR2EhITlEOHNM
KWZ+TWM+X3QpZnVjOVM8Wkh8bEg1TTFWVWE2VlZifEgraDxRUzs0UlEKejZPKn5lcGVpKFlYWTg5
bzh5Zl8xeEd1JWFveTw/KVR7SFd+JFl7PjRMWD9PYUk5QkJvUFdpPmZuYGNgbVltY3ohCno1N0I0
PiNqayZ7UEUoWXdMMXdwU2VVQG5ZV2U+SjsqKSFQMTJraSQqdUh5LXNWMzl0Y0pqaX5hQlhfY0Jm
bjgqQgp6QXlebWkoOH5JKDR9fFQqREJPNWpHaUtwO3VuLSVvJjhpSDEwdFVqdShXdm43KEB3WEpF
WjQ1e3FxIXAlUkR4dUMKekskIX54YklET0tZMmQrUlM2O2VAcDBhWGlSdklDZ2NtbmA0MnZ8cDw5
YytIbiQ9aGdMPENxPi1GT3NqQTJCb3lVCnpTJjl4XjIqUkVIWGZaZD5EQURDSiE7M0FTMEItPEJO
NiZ5RG1Oai03ajwjPj4tVDdhUiN3OzltJT5gKGVGVm5CRgp6K2FDSUVPaURvYURoalRYMCoqcEco
KyVtaGVMKEIqUnU5LWk+STEocylNMn0zc2wpYC1GbjJNd3dqWG5OO3tUV1AKemJSOU1QSjhXIW89
QT0jZChldGlARl5lLSFDQDk8VXo4WEklMW15PkFtMzNVNV5fdFFObmk/THlsfi1OTyNDdzVuCnoq
RkV3T0Q2V0dydTREZktXYnRsbTNjUkA2UCZqdnV7e1Mja2U7c1UmLTN+aEdOan1mMXVSa2w9LWdl
Rn1Ga01kdAp6KjxKJkAwWj5YSHs1N1FpemhoJVItYH5uKFEyYVJIWF9MYlMjeUFCVjcmTDVSbSpN
QkdyZ21teVpmK2lMUSMmOUkKelg2aEJkcCM8VypgYHwmI1BOeDR9V0VRKiNXQVYxPD5+b0c4JGFX
OWZWN2cpSShSX040PURoUiFjWEBhVkZNQSlUCnp0cUdXcEAzV0p+JVV5fWkwZWY4P05hNnc1MmZe
Xzc4ZzlhPGIzSkdhLSNMV1RUS2NVJTdibUM1LShLfmNXT3VTUgp6IVIoXnRDTD1IdFZxIyVVXlU0
WjU8ITYjVFN6WmJ2X3t3VENnYm0oZmZpYWh5TXFiTmcjd0JLOXwwSyY+PjxyNHUKeiQpeilheGo/
RnR6eW5OTSV9bk40O0JpWUQrSD57Mm9paWFkcE5JS2BWRj9XUzUxPEZjIylPYGpaOUxuVW9rY2BP
CnpsWW9Xais3OyRLQmg/cyhNbkglPUo7Tzw2XnVoNUtCazN9TD9tPG1abGkhVHo4MmlPdVB3REtg
KmN4KGV8SyE2ewp6KTR2Vm47KT56fDRLKSs4K1l8KiNnfjk4ZjFqX21DVV81VE5UTW5XcWN2TlA2
Y1VYTVB8RXhZRWdCYEhJRm4wd0YKei12ITQ0Uj8oOSg8TX5+bWBHWGZvXmsjfDBHflMjKCljYkxF
Z3ZgSEI0bmRZZ3k1NTYjbktFaSRqTWdDIWoqaUNNCnojWmJUdjB0O3J8Rm5NeSVzTXxRX0VvYX41
KGx7KHJtKERwYUkoalpSfDA1N1Iwa28jay0jQ0o4ayNWanNzVzA0Mgp6bjROdGpPMXJRZjB2M3JA
PWp2dzY7WDB5cFpBU3NTcHRDSmB2aXhgb2BhX3RYXjRhKCklcmMlRld3Kk9uJGtjZWcKemBjTUg+
c3FeUT1VemgmVmZHM2JZOVFhPmclXlZyZ2NnZDEqbmJrdCQmUnJ+czJNOWtiOHBhaWxLcUMxcyZR
QXt4CnpqTGJiVEUwfXVrOHszPXZRLXMwTD9hUzBPTnFCZWIhMmBtKWltTX1INGtMdTxsVV9ufW1X
YjZJcmYlMXhNblokJQp6RnpEVmt8MiRxNU90KSotakVwP0pKcCV5SUApbDhPX0o0PjtVNHM9Y01U
VndAanVJXl97OHV1UCY3T0F8TElIZUIKelMxdzNIME13RVc+YVJ3aFZgQHRxX2E9THJFJHk5eSZg
MntHRmpgXzA3JXhDYShLaitgQGNSK2pGJjgqeT9wO2hZCnphR0IlTGBlWVEwdSZIQUxSKWdNK0RU
RGBrY09+byk1ZGB9TnFMSngqX2YrJip3IUNCPDkyfDVGNDkraV9oeDZvKQp6SjF2bURAR2MhSlJe
PkpZO0NHVGtZKjR6ek5qRjFCa3krVlp4R3RZJEUqZ3p8YkJfcG5vMTUjcFB6WG04YUhpXyYKek5X
M0RKYT0kI2RjN0QxTGZlZjRrdHtJRmhKSCsrfiR3enxIeGVCP3FUOGticlNreHxsXnhQYj9LdjI5
fjFebyNOCno7blpnMjBlZVAwYFVUZjw7SFpXSUl0TVNRUFN5cG04eUQ1V0NjdWtKaCg3cmJCcFE1
JGpWOFojQSlGUU5jWWFYYQp6STVhbUdXWE00c2U8eiN6TiR1aHgwLSFTYXp5Pm0rQl5VcmNpVkYl
aEQhRjQqYTgwRncyWmM4R3d0TTxAdSVzd0oKelJ5QmwxZnVZKTI/bStsJFNaRFFuS040ZnY0Wm91
bGNFYCNZIU5KdXtxZUttZXF5VCphSzZOd0JNYChxITMzcF99Cno9fCo4U04zOUk5ZE4mVWc1P343
JTBEQ2JDNEVyIW1wOzc2RHpYLUZlNmY/I0JIfX1GaVNVQFNYKFFPM3ZHd31NRQp6a19wVHFae3BQ
JCt8LVFzK197O0NoSzUyeTNwUlo7aS1aTEFsTl45fDNsUlNRSHQpdkM5VWp9Jil4R0Z7KXN7MXkK
ekpJTUVBS19xOTtLSEN1dDRMQFR2Rn5GWDkpdzNIR0tHUyt1eWYoNGx1ZG93fEAwTHV3KTJTN2R7
d2ZKWmc0KCp0CnpTPDlOZTFiVzdQaFRSdj05R1JII2VJZCNBVVFZNWxiJlJUJVp+UUJKVlgqMFFz
RHo2TDdMSnk4VkdkPmVycmtPZQp6MHljfjE9MUA7c3NCLVZYTS1yKGhweFZjKEh6fiQ8elZDMDdt
IWRCPSU0VEx9ST5LNThQcylyKFNZbExaO3lTPWIKeiRfNGN3dVEjbjEmKH0zQXslWlA2RlJrfn5g
QzBNTiFRKXR8WkdmU31fQXpjZkohTTwkMmFVc3VhN3lfT1F+XkJkCnpoVHJ6ZDNicj9gbnZMUG9P
V1RnNnZNYWtqVz5JYXtmWFcyZVBPXk1wUUB7PjM8cX5PREh7U3ojMmwmQklGO1FNdQp6JnxUKWcq
YyQyYiRQWTh4MUQ5SGtoZnNqQ2U1fGdwI3RpTjA1THFoU3EmN0F6Rio3LUBwRjNaTypHaU08YEBL
VzsKekdxJWxvKnY2enBobGR1RjlsdHtLIzNWUn1rQWclK3t8fj88XlFlb2tAR3szLVAwe1IxOUpK
czFXLVJFSyhZTHtuCnpjdlpfSnUjTGdPTD1HVTdBUVc9fnIyPmliYUs4V3Y+SWRETVgqMF8hI3x8
JlI/RU1hUWc0bUkmcyRjd29XWTwrQAp6ezNKKEU7Nl94PTIhOWs4TUw1Zz0wSFV2cFhAITBVTDMh
ZnFiQENuck87ViZQWipTXyshKzBWI05PZ2M5MENSXnYKemFxYUZQNnh1OEBAYHFQX2gqeTA+ak9D
TD1iWChRTEAxamB8Mm1Tcl9paGxYVz1NIzJXR3R0WD1yOy1XMUBeQUBrCnoyelVqbE9+UH1WSDNl
Y09aTUBHYTtxPilsS1B4VjdeMUpUP2NPNHgmY09LZTw/KCF7Nzl7U3toPilMbnElbkolPwp6QWV6
K0FoUUZtJWxtPW9fS1RsbWNiJEZHKHszP2ZmJntLKCMkVWV1T2pEVXJMPGNtJU1NRjJfWV42bUVA
PCNQd3UKenQwIykmOT1RWmV3TUhnUl85QF98JV4hVCRqM2tKVSRlPDw2aTt+fWFCbnB+d2c4K0l1
LVgtRW5kdnFFVnlnJU9JCnolYXVjempxIVloSlRCbXpfKF9UYGZaa2VObFNyYSV7PiNAMktKTFB3
OH55K0k7e1FSKEtqMjgyK29MU2kldnFpUwpQO301Q2QpbUFDRlY7UzspSEUoPUUKCmxpdGVyYWwg
MApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZS5wbmcgYi9h
cHAvcmVzL3N0ZWFtL2VjbGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLjg1ZWFiM2Q3OTMwMGZmZmYxNmVh
MTJkMzFlYTgwMWI2MWJiM2FlNWEKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDEyNTUzCnpjbWVI
dGlDNUZ0X1V7Kk0lZTUtQipJRnRGKUdKQzYyK0FOY1h8K25qNnc0SG1RNWhuJEJ0UXJkcU5QZiEw
dmhIcAp6PjZKbGJrfS1yU0M8O1A9Q15KYlFHOUB3dzJ2WjBOQDVLOUM+I2c8dmYlbiMxbSRrQUls
Sm5oWHBTP2Yodi1kZ3MKentDJm1GXjY9TStVcWNYZDgxZFYkXzdKb2A2TXwkYXtfeiN+VytTe3I0
Wkl6PV5fdlM4ZzU9dHpGUFlCSj1SVi1lCnpXOHMmc2hDNzclaDJ5U2NkPzZlVDJsRWRKI0NsKTk8
cUhlTnB0RzBGNmR+d0cyPVZKTGohYCpGPE1eRTEyKlRGaAp6UitmMnw1NlE7KU40MnRseyZVbW0k
flB7S0ZhOH0tIWZaVHd6YUVDOypWbmclbVclIVEmWlJmWGhsaWNaenUhX3UKendIXk5iJlApQ20p
ekJDUHB7dGlnPW81OyspJV8rYk9VdGIqPnJiOXdfMmE4N3RVSGcpRmN6THstdUI9JVRHYHQ2Cnpy
VUN1aDkyXn4lV1dXY2J2O1ZMR1oocEF7Mzt6NComJGNmaD0qYyh4anpHfXUzOytHJHwzaX5SNDU+
ZysyWUdlNgp6dilLM2JwWmZheDF5NVRvcmFLZEAzR1JlfGZXUUczT1J2QHd7RnpXOTMldnU7amcz
dE05RkZKUDV9N0FFVXp+PUoKeilgXkxVU3E2bTVlIVpFRzxOZi0yKm1IV0FUTUw2ZG5mPkdnaGko
MHptKWpDYlA4JF4zK2FwTDtYQW8hN3RhZGJLCnoqVkFQT15vJC0mdGE7VlQ5ViNkYGRvPEQ3OFdo
QXpKc2hsNV5FQjlkSUN3UEVIYHlYYmRyOD9UanNtPzVPKG0xYgp6bm5ObzRwdmApT183VXV4b09h
Q2N4bFY1Q3YqZk54Si1APWJEdmd1P3JHQj5GcXNIPWE0Y3dNYnBkfnN6PFo0RlkKeiFpZGtNJlVD
WnBMVCRSfmN7QmxxVz02O0txWnw7Ty1rTkVOaFl4M3Nud3t3Rm9nT2ZgZSZkPll5XnIoNHBpTTU1
Cnp0V2pSPmVeVzdvd007V2EjVnVxeiNjY3IlMFBeTDJFNDBfWnE4V1Ykaz4pM1BgTTBjKyRQcmlr
Mz1FMiZtS3gzOwp6JmVtKTIkM2AxY2MrMGMkPSpkUFdteGkjMjwrMTg+XmRfZG1weSRKQkdGa1Uz
dGhsbUwyVnc4fTB6dEtoRXA5XysKemhveGVGVnIxJFdSK3tzdSlRQGkqdXJzdzt7KSNgTFohTyhS
OVNPRjx3LT1SLSl9OS13aCpQN3ZaUVlFa2lNcz9XCno8ezBBeDhGXyhjSClEPXVYSmhCRXV4YHp+
aCFDemE9SGA1fnRacVpKZHcxIUdAMiU8ZHZJJUJoc1dZdDBOaSUoPgp6elRVdzM4eVBSMVohQDdx
TilrTGdNNnp+Q2h3KWBgVWl5S0UjQTl3djdWKmh0YzZmcW9jWUhpR1BUYWxBPSNOPVQKemFpWiY5
KExsd3hLfUh7YF9xOEJWdHt+YXYoTl5uQm56OHEqUmdIfWVec1R4Mz5sVGU/KCgrbl5sc18/V0Qo
PE5hCnp2dkFBd0BTdXYjPWc+Oyt6c3x+eGhQcCkhPyM4WXBkdGBxcDsxO3NTdnRObDYmP31RZUM1
UG1FdFYyQnw7LUBUdQp6PUw1Yj80QUhhQl4yXilCcnx1a1IlZnhrQHpeKis7d1ZZR1drR2ojJSU4
OzA8eldhRkowNmBeSHlwcnM4I15ZdU4KejkpdWk4aHB6YlVKOTdKNlg8ZTlgI3BXOGtPVndrMkh9
eT1+QXl+QjBldE5va2RfM1ptYUhEWm54V0l9X2R1dzwxCnolaUhJRUAhRUhtSkQ2JlAtPHNvYlRQ
cEdIOW12NG1rODF8VXFQITVAPH1CeCpQYEMqME1jZntZNllLTVBuKTtWZQp6LWYhVEVxVD9UUWpY
aClBUz1pVjkjaXp6dz00aCpac2ZJeVRoNHUme0hIVj9xWHMkfXo8QXh0ek41d2NvQUdkJk8Kekl7
dmdMUVN6ZXZFWXxOKTNjX3s8NTVlM1ktPz5DNXk/VyglQ2FyOTd7djlpJSsybypNbmJifmd7e1Zz
SFdRY1hjCnpOPF5uQj4wPTchaDZvTXVMQjFWK3loOUM5WHh9d2RubShJKnUoRnJpSXgjUXpIVDJO
Ull1XjxvYmd6K2BDdmBuSAp6JVZoN0VNa09jcGpfRVM4NVhadTRpfEZ5eHNhRHN1RCQofnZaWTdS
KmQmbW5kb2p7TnpFYXRfQkh0MjgyR1R5YnQKeiVjRjB0SzB7RCopTGFJfXZrWjUrb3ooSlIrcUJ7
QHB2YmhnRlRDPGdPR347ZThGNnRGPilvaEFlZio2YmUkPGIlCnpYQE0hNyZLaiFBcWRELU1qamZ0
OHRoTGxja3FPY1YweEJ2UTNPZG52U2FnQFF7ZmtRNUp6SEU2eVdhT0Y3KGQ4MAp6OEAwRmRCSXdn
biNhYVE+dyl7XjNMQT99M01TPDhfcU5XYnQheV5od3RzRk1sM2RPa009MFNfWlBwcSgxMyFsKnsK
enlIb1otRiZEaHt5K3FvQ0QoMDdadG5LdkJSO1VSNGs3N2YxbUtCbkojWjdZUz9VWTtHXnc2QzBA
aU05R0pnTXZtCnp5LW92T1hHWmYwT0xLbTZMOFhxXmFEdXZJUmg5Zzl3c0hpZmtPQUYtejUlMTAk
YGh5OFN7YF8mSm5NdDJBTnojZAp6SkIleW5BQXhfRGZ2WVg9UmYtY2AzX0FlSC1YO2dnTHY0Mmda
eEFsRmlrZVk9a31yOXU+a1FeLWF9fi17ODI/VzAKej9ySjZSUUorTHwyS2hEZzlsK0wwKVpvYkFq
RFFoJC1PaH45UFZHcHgtaDE1PyszPHVoVSh3ZSopeVZmSGdyY00tCnp5RmN9djMkJUhFND55bTtG
UEJrRWZ8eG15eDUtOFE2VU5fVm5ENV9AVWtaKU9vT05aRG53XjVLc05GZzZeQ1MkOwp6Tz5MZmdl
dVUoeGAhWSZjdWRlIWxaZEZLPFhYNlJXJS1WfFJ7bEhMbjllaVlkOGtgJUQ+Km5PSEZSRzwyKi18
Z00Kek54YUBwI2ZHZW9KN3ZwNXFjSCNtY2U5S3VqNkY/d1olWm1RNGw4QTdIWmxkWVB+b01HdWZC
amImdyFhdVNScExKCnpJX19wbz0hYzlwRWIzJW4kTV9YfTBDK0VZLStqNiNWTUFXPjJXKzZQU0w/
bSl4LVFBOG8pMjw2LUYwK3BKamF6YQp6P0M1VjJkOHgjND0+Um0hMGJ9eTJ5LShNMTNGPip+SHs0
KGdxYT50dVc0WUNVMz8jYldfUWdreTV7PE9BKWQ4S34KekY0YHtEdEg8ZlU5MXMkUUdSPTxoQCNu
UERLJER8QDFSVTE1JnllcXE0YWlNd3d4MTJkNThZMiNzfk02PGBKUldvCnpJOHJ4UGA2b15iM19F
ak1tSitUe1JYP05ZQFNDTyRveWM7fj1tPVA2JTtIfG9FJDNeQml1ViVmUiVlNzZ2TFJqYgp6JVlB
Mzt7c0FwbzFJe3FWdXY3aTx6MjY/WntFJUtoa3J4fSs8P2ZYOCZIcD8pNlBpcVBSJXQzQHEpaDNp
JV5jYXsKemtic0x7XnZYaHVHMnFlaE5YJFp5VGh4MkRUNj9GanQwJUl4YzBFcmoqRClUMTBZJHZE
aVlgb0BvWXFCSCg2Oy0rCnpvM3N4PVc9bnQmQkkkb1Nfe311Q1Y4TWlXY088KThxP2w1fUFFN0ct
UWkqRnhffk01QFdSeTUhaFBxRj1hOUI9dAp6TGdAQ3FsJlkmUWJ8OEJtcGpEfSM3Zkc3d19JMXtn
YDhXcHs7M2VINz1GUlM0U155QjN6JT14b3lmLXYtezlFWXgKenprdW1yQ0U5NmdeWCpCPj1VQCZj
R2Zpflc8SSMjeClRKGdqPjdibTZSPkgkPHFaYDA7QCtlcnphMV8rYCE7Z1RkCnpQZ1ExT2QhQzJr
SW93NDJPSypwfGp7USZ2MWNjY29tWDxRXiVKeGN5QXU4TiElQXtXT3o2JXl4NDloZjdAMiVUbAp6
I3I8I15yZGN3PjNzZiF0RURxRjtxYV9kSUVwRCpsem4jSldtSmJQWk1VfTVZeDZnclNLS3BgZnVm
Z2xoKFl4VlIKekx9SWgrJitKZGI3PDdLfHBVSXh2V3R5RUZQJFl2ejZfQiE3IV9Ke1VMdFpAflVM
VmZxOUlMVFJxJnQjYW5adTYlCnpgYGgpQm4jK2xGNDVeN3lSeXAtMilPSG9qe2xvN1hVSDt7STYh
QlJiSClvUHJWfSFOSWo7UGQ3NExhKXdKYUlZdgp6JjdUUFc7RzJxe2pVKEFpOTgmJSNebilKMiUq
a3RLe2g4MGh2ZWN8aUQyYHpsQVRLUm92NEB7VjVle0h0NU49MV4Kem04QnMwIUNFPyZZKi1hQipr
RDdOMSt7VjFMdHU/eDZBWTJ2SF5aezVzdkZVUHBSTS07dS07I08kQHhZQlpsfWAjCnp7Z3cyRzB8
aWU0MSYwVWs3M3ElKkNueyM3U3lkTyhDe3s9SUxFZWMjJGtpSjE9fHoyNSheb3RGRDMhOCk+NEsh
PQp6b2RkbEdmTVNtUXR9djlwMn5aM0t6QGIxWmY7Wnskdn5GNGZYWntxbEAmIVFCYj0jMWUjfD5h
OTEpKjJHX0NkKTwKenpeS3h5cURaTTVzX2piKGlYMzBgLUdiVU8pdWJYcD1zZ2RrMkNFVmlBdCto
a2A0dCUyPlhgQ2pPMUdve1J5VEFeCno0KkRUUXg9dXhIbX1YaTV3VzgwejhmeUNudG10TF5JMHJL
V1I/YnZBNjFZJSRSdjl8YEomNTt2THh4NlJwJmBXZwp6JT1maG5HeXU8Tz5FTE05cnEwPSRWSjs8
KHkwJWk0ZkpGfWxWdT1ocDVGdjhAPGReJmVGY01IKStlX3c3dmBVT1YKejI3dXpZTnl3QiV7JGMy
Y1lAazNwYkM4cHJgX3xYS0Q8e25QdGp6NlQ+MzchIzJJPllIJHtiMWZCZDFaYFd7fXEqCnpzWDxF
MUU3ZiFOaT1URClsOCYzbCokMGR0Sk9jZCVqUVUrXnFpTT4rO34+OEp1ZXhUbWNUeWFzazM5VkIr
e3BAVQp6Rm4rZCpuQlRBNGF6KzQ8e1hwdT10dlg2QCV2bWNDQk58ZEdmY1defj9mJV5DTlgzajJ3
UExXXkFBenhkWExHN0YKek9hVCN9Rn1+cXVFJDFJbChmMEAjUnw+IW4/ZTByc3FhIXMtMj59MTF1
WCQ3bHgmUXMrQDI5JVR2cSQqKUFlezBCCnpxT1N+YjBydE5GN0krPnEtVyphSz03UFgxcl5mNDZS
a1F8Ul9kIUdJSy1eRiQlVUw/VXFAYiRrSlJeZDxDe3VwRQp6RmQhS08/Jm5geWEpWmEta0xVJXNh
alNAKVcoMiM5dVk0PCZZPHpqOUdBcCZHIVEpTztgPnFXbylSSTAtNk9tXisKemA/MlRkNTIhajlu
Y01TSDhYWXVITzg+ME95ajlgdTxpcXctZ1ZRa3x3I2lKWF9fJl98JnA2UTc0WjZ6djNDfXVhCnpI
JH1kITBvPShGNFBuS15vZyN7VCNVYExyU3pzVTJBeTxfaTltNUs/S1MyNiVycUt4bjh7LTAjXy1k
NFhUN2Nmdwp6UmsxWWBYJE00RXdeRWlUYkFnPHxIbi1ATmI1NUMkVDZgfUF5VnFHbFVUYFVBb1Q3
IWVyYTg1XjstcW5Mc0BOdW4Kej5+UHd5ZUU5aXkmI04zJDYyKmllbUhvSEhVYHkoaWsqYiolOGBJ
a2xXTz5XNEVzdTNOZEUweSljfXUrUVhsMGxECnpyUHFqKmFLfWM1d1lxKyQ8XmIlRiUmYDNyYkg7
UkE2dXM+cWcldlZgS0ptKnBlfUVQKGYkQntgd3hPdUY9RSlDSQp6eSZsTWpoak5iQ0EzPiMjZG4l
OVhwSG9oZzFTSEZ9I3IrRERjZVFBbWt+bGA1ZlRqNG4rU1UtQis8TUVfdjhAZDMKelZhaytkSyNN
QkNmZ3lPVzFANWxqMDlveD49al42YUEzVUduYzVPaiVPUEZKMyZ9bUBYJENOQzhtVWJDUFZfOFZ2
CnpqY2YyUDBKenI8NCR0Yml0KU9ZdVB5RnFfLXcxYiVJUnRIOXtHNGVSIX1ZclgxMjZ1Z1QxejtT
b3BVYmlURXNuSAp6aXZHfnglPTM9RlRAMm5rRSZVRlNOfFc7RHlIMz4+KUEpOzlaO2wlUzI1PkJ5
QXRkQ2I3TGwxUmRiJXJgcU5Zdj0KeiRBPnBRVFFDKF5GajtHIU52Zj1MWjUoSnxPRnE2VUl2YHw/
Yil2NEBNLUZ2T1VtSXsmPjR7ZEBsS0d0TUglRV5xCnpQbyF3YTZIRjg3T0E3bT0td3c4ODVEUVA4
R0U7TjJ1OGxrcmtrUT02elBjZm1GSz4lOHJHa1R4RXoqekRgQ1Mhbgp6VztkN2sqQE8jOExGQVZW
dzY5TUBBLVRFUUh6Y2t1QkRoZ0Flbj5fM144KzY+Z2daPU1ZOVlacEApVGVpcElGO3EKeml9UEZJ
b1grREhKQGkpfXR2aH4md1p5c0JTO34wOTBvYkZneD1VdW4kIXYxb3Q0YDxFJVlXMENHOz1LdFk8
cHo9CnpAKm1rQjxAI0N7Q3hgYSM3TnhybHdmLXdEbW9Fb0JkckA4KnhjemZvMF8zJDxAQmMpe21B
PkQmKnc+SHJWSHpXSAp6TGcjLU5CcThiJmd8P2xJRk00Y3JFQik7fmBnS2k1IVlsZW50JGhLPmBg
Y3RkMVlHJjZpNHhOTjJVakRESFFLIU4Kel93T0wweHppb0NSeWgxd1R6SyR7aig1bncxT3Q3WlF3
ckN8cEVLKz5QfVJ0c2hIbC15YnpjaipgJjxwclh7VnFHCnpMPGEwRlY0MFlrdCllSTFmX3t3KHR0
T3FgdmNUQHIpNGpHUi0/SlJuKVprVTxLQWAlYWRoWHJIWW1TK0Z5Xmlfewp6cnZhbkQxdz1VdTMh
WXQkT1lZTnJ6aVdYP1lmTyFWO3RJITwoOWslMl9xMDAhJHpRYXx5d1J3Sno2LUQ9OyFJPl4KekY/
UkhheGwlQFI+WFlWS0JzcHVBO09eNFRgbl9kUnsrOFo2ZDk4N3tVR0hnOzFxeFR6RXBBeUZRYU55
WUtTKkNzCnpaczgoPXRwYkMrbGElMjI7O15odmxAWUtAU310JnpRI300fGRfMjM8VWBIa31sN1JJ
WGlIOyUlJlNQOXJ1NW9vawp6Wl99V2tAX15HVHd9V3wmJDYxNDxjMTNsTno3cCYqJHtqSj5LbUdt
N05fdz9qNFY/cW1feENqeUFAQ2JCI3tOR0kKemBHcH1aVE5sI1JwdjYtRjx0X2d2JWBfJn04T0ti
bSttcj9aMkMrRXpHeDlqeFNaX1hpdCpMTTAhWTIpcjI9LXVlCnpjPmpxSz9JOW0wQkM1NDxfVkot
QE4xMEo7PkVWP21VQjtfMj4jOVM+cDI9Ri1AZDE3UjRCKCQzdj9kfmlBMyZGTgp6V35YaUpIK0xl
KD9Lej1kYmxwQVRIYH14NztERCZFcj5UMX5ZeFQjfFVJaXE3KWgxJkRCNjdzR0pnfHFDV1RjNXoK
enRSRnYjTUZCQXUqfEl3VmBPQFhTIT9fRWtgZUYkPiEyUDAhdjQ0byl1dDZjbyREMEBgaTRwViVY
KmI9X2Y/X2cmCno4Uy14ZTVqNXE8JVNqPlIyNmBCRWk1SHdxOGBge1NRTTNIJmtZbCR+akp6bWJu
MyNlPSg0WUYzWCNmIWZWclRgcwp6U3hiMnEoOUJuRDFHbDl6dksoRldrKmFZV14jaWBSYkZoPzdA
QVpvMVVTYVhqbVhESnN1NVJMVz1GbkEjNmR1eVoKenNRNileXjNFYUQyNXo/N1I9Jjg/elkxREIz
RzdKLWtjTjx2c0s2e3s+ZiFpKGBxRFdqTmB1R0JSX1JoMChYcWBSCno+UVU9RG0jQkBPZD1vIWwm
cE53KTNedXBhTHQmflNMZFZjd3c2eXtWamA5TFBEaUQ/bEBzfTIhSFhZNENIaDtiSgp6TGI0bml5
fG13RFRmYTU4RTB4Kk57QUJoP1B2Rmg1TnhrT3NRZj5KMSl3SnI7eEJGZnUxMEgoOE8pSk4pXjxA
ZHsKelVDJTV6eVBaeiU5MUp4WD1EfjtJbkdzQFN6R208RjtsWV80P2xJJC0tUCp3LXpmVSNDbzt6
WX1KNzJLYjxJWVJwCnolMCFWdFImcEYjb21TXz8qQzR3R25IfVJ2XnJjXnpvKkYjej04JGx7QmNV
ZWozQkBHVE5BPGJSJmBqLVd4aUpPcgp6TS1CfFlUQD9yR1oxSitRR3RpZ3poNjlvaHY8KDB7ZE5O
LSRjenp+UyZIfjJCSVU3dXcjKGNXKU9QVz01Y2Y4Tz0KeiNFZDE8cFVEcDF6MUApKGZhUHhjPE5Y
QStgWGhzZjJgVmdqX05BNjNZNT1gRSs9K2VmaV9lTWo7ZWtSbW94dDFfCnppbW1DSDRUSEtTPHFS
YTc9MmtMT1JJYXBecUZzdFhrOHEhK2VHdkRTP0cpdSRnan07ekYqSDcwJFcqcFM0cHVOegp6PzVX
RXcjYWczU2FYV0d7TSg/SFAxRjcqITlrVUV7QUVUP2NKbSRMJHF9IU1eJHZgfFYjRVp5bzlJOGQy
czhqTlMKenlLTnR3cS0xIWlJNFBlcnckV1NTbjBKZjBhJTYmWVF0VD4tLSNqe1kzKEVpSnAqRCU3
XmhfZ18pTz40ZyhhbDhzCnorLTVZKz5TaVB5TSUpVyRvb1pQVTI2eF9MUG1IR0BDQWJlbzEtMXYy
bHJZWk9ZOHpNaFcwSGIwQUNhRnZQJSRAIwp6SEp5cDQ3SXtaM2YydDJTJl45V3FJQlFOMTVBeH47
PFFOYXM4RnNjLU5EVWF5P1hjfnp7UTY4JWcpUk9gdkFPKGEKekVuM3t4K1Z1NihIbzVXbUBjVyMw
clBESz9Je3dhYkdGK35yPUFHczktX0NqIWwzMHpiSDk9cTkrITt+RERhYm5vCnowS0NWdnRqYWh2
R3kyIVElKERkNjUjJXxic1g+fXJfRSkwbnZmYDdQSjU2Z2hKeUZCIUlDVDVacTRnR2JHWHNBYgp6
QChGUEZFKmRpTV5CWnFDP2dvZHwlIyhHP0Q+UFdlXzxxOUFIUXNMTjRxYWslUzFeciUzcVNsUylM
e2cyYW9xSCQKempgWkN3a2dLaTwxfXt3T29AXzI2Nl9sRGlzPXcxM28tU0ttJEllSzRidGczaTk3
WERfakZ4dCQxKDRLaTRJPXoyCnpPNmI3b3ItejVvSCVjVWtOdSUwKk8oX2pwPk1ueSNyKVp6OVcp
SlE2LWZNYVdKcHZ4d3lxSThVX2ZGTnUjRTU1YAp6bGVTfnU+K3lqOGJsTiVaXz8/VEQ8QzB5ekQo
PXNiTUo8QERXKlZFciUzR2pSKDdQcDcwJnxlOGtBZmYtSXxzVVoKeiF2YyhkUW1GMGVzY2tIfUZw
WWB2U1QxY34+JVklLVo4RHI0dTFOSVArMlglTjkpPm9ockExdDJzPWJ7ZXsxbmU3CnpeUll2QXY3
ZWk1WihKMi0lcEp5U28jPkBMaSpaT19rOV8wIzRxRGBjbDE0VzVwMXJOekBlJVI+KiVkcHJ0cE9N
WAp6VUlnfUdSUVFBRmBXZVpAcnI5WCNAZnxDQ2VrPUBuc1JQeWBjZVBMcnQ5YVZ5bXdeSm5weXc8
Tj5Jdz8kPE1LT3YKekUlODRsdVNmWCFeTXwjVG0pPz1AZ2xNS2ckNnRhZWtlWWgpaWg5TFFqY2Io
MWRRSTEzaS15a29VMn1JSjJoX1ZDCnpoKHUwVDE0fTJ5NlVOVEkmbUkhSHk5e3gxaHhXVVY4TkVq
KFFWdXspcHcjO2pmd2dybjhaPGFHPyZvdE1tQHNjJAp6STU9Q2k1KnRMNXF6LXNpNng2V3UlVitP
fHJeIzAxcFhqKSF5XyFFUDR8KUdqRlR5fjJVPTd7ZzU0UEw/WkI2YE4Kelpwc1dnI2VuOFA+cVdG
RysxZXd2MyUxbDBDdko/TGNJQntfSTNOMV5OZVg2c3E0N2RsNGZmcnVnbn5sZjh9K3BtCnpiUWtG
cWIrU1ZWKF8xJUVNNF9ORmt8TmVXU259YCs3Q01NRWUhaDY/a2V1QXxyV3JDXj0mRk1aNGkxaXM3
fXZxXwp6MzBxNzNmZkwoMWg2UG1vPnkka0ghYWBUUHltcGBNIUI4dENxb081V29vdEVAQHpfa3px
NXJMKGxYK35ReFVpRD0KenF0Zn0xY2lsJWRGJDFyJkczfCtsZWdqPEZydG1VPGh2SGMkO2AkNEJD
Z3NfKWxiKCVoKT1sTyo1S15iR3NFQkpOCnp0ckxTeGQxSmhwMXkzT3B3aUxzMiQ4bzA9I0lJbmdP
XiM8fmdFTHlSYEVrNF5KJTQtcFUhcWBVdnF0YFFoVVF2Kwp6ektDcz9FRkBXYmtRbE1eOUZrZ3Nh
enhiNSZRMnNnWiZKJihTd0hiYHFMNUNMbCpTNCpKdHFvQiohMyZKSiFGSHgKekglcVNkTDB5KGAk
JW9rR2daWjNVO3xXMjwpKG5GcXB4TDdnKlk7Rmw4VDJnVD5weUJLNiNqYkRMOVdpYkkoVW07CnpN
JT5vZ1E5NzE4IyRlQzckVjVkfnt7YzIwIWtKPT10Zlp2QVp6K3xZdzIrS3NDa0taVnF7cGZiZW9W
RGgzeE5VVgp6biteMmIza2FjMl9YU09gKTROaCFeQHgleHtPVW9eUkJScj5QOW90O1h6cE00Ukx4
fTJjNntTLT9Tfk8wQ1g/QT8Kekc0clZUKF9Oa0puWFZNVUU4M257enszMzYqeHY0PFU5eH57KnM0
TD9QI3xXaDNDOWxgJk9GIT95dyE0VlJMamtFCnopZyRiej1mdzZTRV4xfk0rV1MqQHk5fGFISEMo
UEZXSz13Uj0xcXwlPTQ2bHRENnh8ZF9IeWUyTjUwM0Q7bHlLMgp6X29tam9RTCRSNlVBbnFHRUY9
R0FYRWklZ1I4QyFecXF0ZTx5ZXdxZ1JMYjRtM0JwYFFjMVUrSVRyajdjQ25gPmsKekhSNmJlYVRx
Q3BiUjs5NUdqdmE/dH03KW5HM3BeYDg4d1M/YEJ0UmVuZmQmZ1lEIUIpMCVQdjZyRH5UcFdyRFB+
CnolTz82eG9hLXpvakBkJUNoPDZOSSg/IWNQQkU/ZXtMZUJnUDRtckxwYkUjUiYhP2w8cSo2SiNX
K053PWMoPT4kKQp6KTVnYEo/NnA3TzROO3puNmpXVnMwNmhWfF5Ie0N4JmpZPjJPTT9USjw5cU1O
Njh2YDdrMEQ0cCM5N1R9YWR6QHIKeipIUn4xQyNMUndkM3prM0F3MGl0KnUxPnFmQWkqVkw/VGhM
ZFF1Z0RwKkE+eE1SITstbHtaYDI0d3gqPCh6Nl89CnpsJDM7aDNMX0h0SmhCZiFkRDJyXnI8fEJS
VisyVmxyMT82Zm00YmhnWC0xOXM2byRmV0pyYEE2clFZfi07Wmk3Rwp6UTBOfk4jNE4zbVkwRnp2
bUw1MT5RdChMYSV7RU1LNVZ3ayFkOzVMcW0oNEdpSUNsUmI+Xnl+N1pWKTcwO0lUWkwKeipIN3Nq
aTttQHBwSyo0NDdLU1RnTVcmcC1LbzJxNUVxd0E0YiNqTnBtNCl5ODk/fiNMcF5FIVZ6WlRqcFFo
OD9UCnptZEM/cHskaTt7ZXxuYEF6NEVHZkh3SDMjMmBheHh4fV92K2VaWGFKbmF7fkRHXk9AMDBM
d15NT0EyQilKYmdMVgp6KEhNKytvU1FxK3ZSUXswQ347REtTVUJxcEV0bCRua3lpZUdKfGxIbDFP
SDBrQHlNbWRaP0BXNnJgST5iZ1JKSiMKejkySGd9OTVXRFo7I3pZPnMhPzlhZWxkR3sxa1E2LXI4
TSN3cy1qT1MlMVhEMzwpITs/Pkx3YSszVTIxWEoxeklrCno2fSNqUXFidTdRY2BZcm5vNEJ2e3hH
bHQ3OGxMWWQtP1RKb3NuWFIxZzNhQjs0dXdLWj81MH58eHlSNW1jWm48aQp6Mko2MD8xLU9KWF5a
WiMtX3dTYTxYPj85Qi1hPVN7PGVwUiZeVHpXOGpoPiF7XlgwI2xkRio/c0RMcEAhdCgwKEUKemtp
eWlTJjd7cXpva3ZkRk03PW48V0VkU0MtOU9RS081VVFAWGhnRWhqR1ptQFJOMl42WXA0Mjh6R20w
bng8MFhZCnpYQTJGV1YhU2NxZlNMU0tWUDtrKiN6aiNuZG85b1Jgd2JAdWBzVGokRSYjNFlUQHpL
X29rM2ZoOVhEQiktSjZVTAp6YW9FQDkwMWtDVmQ0T040MG8mVC1UYiM2MTNIIUNLYkY1VWQrUDtA
YzZ0Qn5rKTRUeEB6fkMrMVYmUit0eWNjYUQKejt0T0JsRG5DYlo1fWl9VXhebj0hYm5CPUteeTA+
M3VjMTFrJnR6ZFMpdkU5ZXZTIWI8KzZVM1BAPldMO0FxUVc0CnpTekJBe2kyb09xbWpzc1R2XnZm
dz5MNChxWXx5T1NKQH4/YF9zKF9Ve2k3Rj9tRkFVUjcjKUMrQ3tXcUZYeEpmXwp6Q2N1c2hfQUop
cnYoOTtRP0w0dF8qJVFyX1BEUmwzUU1efnRYaTgyJm5yUl5WS1lZbGx3KylWbyhTb0E+RGFBTS0K
emUobi02OHNGSHxxJGhlYk14QWZzKEM7ZF44NzxDTHRMSGA4eDklMmRlckJQZ3Jee1FqXiEmSm5C
a3VXaFNjfEBjCnpZcTVvWTQxcXhLKmtnfEgzQFlQbk5pKHdXPH08U3h5bDMoTzIpNEdyWko4P092
TFlLOWl8dW1iZz44N1I1QzdpJQp6NWFeTXM2VDZKZiFoWHQkb2pkNSsoLTt3bTYpRUhWMW5JcTVY
OHhHKHdLRFVeNV87QE5mQ35JNUpWTWxKXzNzb1MKejdqQlV2RktKSlI2Zzd5TGl4PlRQe0pySHB4
QGVFam5aMHhBIVBAKGFAPHBZa25naGoxIyh+Y0tNX0dFNWEhQUxjCnoqPVRRamxFXz98LWRtaXtV
a2NBWlZyT3dxRGV2LUBfTHA4OyhoYng2RmV7e3Mke15USGdiNyYhO0I4JCFiWUc3awp6ZjImen0p
MUApVXJGRXlTUXFLSmljZ31Cb1g5TGdZTkZ3Xit7TXtWRUF7elpfU0xrdzxEM0tFZGZuM0RkP2w4
bz4KelJmaipgK30hKiY9P2Y/WlJaPnp5d089e2Bje1FDKEhxKGA1bkVhRy04cmhmTG5fVXclTT1K
QVpYPUhqUTleMlUxCnpGck43c3VaUUxLKmtxcUtjY3B+JWJ+fGEtZ3dPUUBrMnVHZUwzdiFAZDxl
Ukc+I14kcGkjSjApN2FeTkU9dit4cAp6NThUaEFKfkZzPnEqYyhYOSElX2JZe3w+MSR4QmxjYzJp
cE9taCthTTI3QE5QeHxXZHpJeHFUSzVpPEwrQldZLTEKemM7PzwrTCN7K3ReQHEpXkx7Jm96cDFG
d0tXNGU9QllaSFYocXRHaFhzKlB5UGxFendHRSZuQmQ0NHNxYW9nWmVDCnpVZz8kPDc+OGV5V0JJ
OT9uS0l5ZXVYaklAXkw9Xzc+a3VTdFUkaz5sVz12RztjQWNoV0VLUnxEPiRPZG17d2REKAp6TD13
TlFzT1dUWVVLR2E4V2Ilem96S01CWllJUmt4d3t3THsrRmk7LVBUailEKCVGJF9eempzaXI7dmoq
ayhgaUsKeiZRV2slWD83RXBkS05zWklqSXgjIVROSEpaPEQzNzdLMEpEQV40VkpJNUAme0xGZVU4
RDsmQDBOK35MK3RXPnZGCnpqWismRFojRjcocW8pcT5APyQqWSRpfHc3ND0ydWpUSV5YJXFoa2Za
NmR6JnRRUFcmbXMyO1FrN1NxUk1SWUBzSAp6QE4pPUVkKyROUHlFVihtUTMpSEhtalhLVyNYdylx
dF57eylVayYmYThyOGRpbmczZ3oqTHJELWNQfjI+OUtoSG4KeiE2U2M+dFpRZlJQJjhwZ1lzMyZQ
KHJFWnFqYSt4V2B7dzUwaGB+JmV0QWJ5OSQzflZKLW0xQEpzbUUtZ3IkKWZ7CnorenZ7JlhrSSl9
KTcjZ2pvfEFlYys0S2FDTCZQfih5NkR2ZytnbkBQU3hncVZaTHQ8b2YpNGY9KlUweiYtSTtySwp6
VVN5NzBvOzNkU0IlWmBLbSNgYmNyWkt8bzNHenY8TzFpOXlUZEZJKyFDV2pSX34tVk05Z3JyKjNj
MHZuRU92RU4Kej5EQHpgc2AoMzVqSyFAdzh9fDg7VUo4ZWwpUiZ9T0tRdVR2XkpkIWFVRXtfPUxR
PFdjXzdUQExiVmlIMFVYZDsxCnpISGImfEVxMjwwQmQ1OHdEUiNZTXBhOVYhWTs/MEROMGN2JEA/
VTt6WHI3Ry0/UEVxUFVffDQlZn5JMGt6KEtxUQp6P19fSTBXTmpnIXY5TVUqK0Exaz9ZdGFRaj55
VyErOVFPSytSO0Q1UmZsQm4qUDhHZS1nYl8zVD90eztrYm1pPHQKeiMlLV9gNjd1JU9EJno3TFhk
bXo1QnwtKD9BK25RantJeWFfa243IzEjZl4rMmA7d1ZfaWBCPEw/N198THp6V2VOCnokO2QzZitx
YVU0d09JY14+PmpRdE1gbzdteEhpPnUtIWteJVY+Y2g8YjJSeVQ1eVctJUVLfHxAVF4zST1qbkom
Kgp6MnEoOE4hKmRNd3YqezNOQGYhMmAzPnB3OyNkWlIqJnM/NkomRU5lUGJDUn1sVX1DJG9sMEc7
Kj82I1VrOUdfJXgKeiQpMFo2Yms2UUBeUmczPkchIWBFdiV3NXJDQWBBSS1yY0xPLXhiaX12PFBE
SE1OeClUcH13SVp8QVBxbkk3aTJVCnpCejRrb3FXV3hjWlkqWWdVUypHJVItQkt5I3ghTEwrQWhq
M3pZTyloPW5YVUNRU21xRE5UOGVFcjBPbjZEUlphNQp6YlEoVjVIUFdtUXF5YWslP1NXIWpJeGNR
b3RVUlRRRmZsYjFaMTQkc043UVk0WVZ6QCRhOyZmRHYlNTJCNm1NSkQKeiQkTSM+YUNBTEg3NUN7
eDB7NzFeSjcqT31fQXNMWihlem5OVCs5R0o2OTJhOUglc0w+cFMtWXs0Pzx4Q0V3O1pLCno8NEdq
OD9qfXxpKXpfYV8kaXFxQTN4TXpHXjlING5mNj4pUzlNOC14RjAkM0pgKV9AZVVLZT1HO3kwUXsp
SX1KXwp6TnkwOE4lbXVaMilocVNjNGtmOSQoWEV3c0llSjV3RXA9aFNHe019Tj5lbERKSEomQEhR
SiFVaF4mfFBiWVc4KmoKem8helkjb1Y8dmZrZ2pFaSFyezEjPzdmMHVzY3t5REQ7Y0wwWHQkN0Bp
TkNuMipkV3IodTw3ej5TRHQ5JTQ/TjRTCnpOc3U9UT1PdHp7dDhXYjVmNGNRWkVwV0o7LXUjUj0r
YU5xPj89VEhOMnRAX3R7T2UkdyVHfmw/UzF2Iy1JeHE1YQp6MnlHIyRDKEIlMndsXm5qWnpyRkBZ
cnIzajlMM0cybUxOIXAhTktqeVhBc3JiciNzWlRZS1EkQFRLc0ltYGlva2cKemk0bUhDRVQ9UFI7
MzhKMGV8YjVRPT91I2QjRnI5TkRiMzVhIysjWFZEKUdhTCFaKncjME9+PjZsd2gkTyF3XzUrCnp0
Rk1weiNDdnQ7aihSUjs9TUdJbUx6O004QndWfnhWQG45Q1BkdkY/MTE2SHswKEwtaU9BRWJ9JUFK
cjIzNzN1JAp6RChQNmBrVnE5NSQ8NlEwWWsjNmw7QTVFUTZMKSFFTGhhSiVzWnQ3YyQlR1Q9djtK
QTVCPFkkfDs/XmgyVHhrfCMKenN8eSg9ckw2QmdUM1FHdlJaMSU+NFooJH5yckBMSE1NZFdjZyFh
emFfa2xZaW9ZQUdOem43Yk42PXNjN0FLY2RkCnpQfmhIP1JhbHlMV3RLM1IhTC1XTWVtTXFoaVVq
V2dUeUMlfnNINSQ9d0M8Ji0lODl7a25LaFBEWGpLMHlORFg7NAp6akx7bD9rY0VHSkJRdXBneVNe
cD11bVE8YCZ1ZDt7X2BIMl9SUVRSPEAwX3t7P24wNnxjbDVYZzhlRzI7S1hpK28KejZiUnMpWkwx
Sms7OX5qVXpPI2BheT5FYGpUZFE8KXdYP0NDUz9KbD82bEIqSGFYMD9AKjIxVUokY1Z2YF9Pa09L
CnpCUml2S2MkKS1NUSZhNGw+an1rPFhBMTMwNHZFTW00bjtvSkZgfTAmYUJaJClyJVBTe2AwMXAm
RClDME49eURRawp6YH4hN2tiKm1iKUc1P2ZEK3p8dn4jZk5GdT8oWGlBdF5DJVEoR2ReUnA3S2pj
Z3BUSSV1WTJ5QHlCRThBUUZVeVIKenkwXjZ8an4qZnFgR0BqPDFLZUY/bFNmS0NTJDR4TlNKeXgr
N01ycHlpa2dibXJNUSY3NVNWUnRKOWNoaUFgPjFiCnpFWDh2RUV4SWdMLTRDdCYrOFFMJnJjJnk3
I3dDaVNqZWpMbkQ2Rlc1UU58LWdGR2JvaD55Tjw9cnttfColWVN2Ngp6IzRmWWZ4Mzx2MjdyX2Ro
RTw1azQyWng0eUgoJTh4ajEjK09HX25TREhSdmlYPU5DOENARUBQYio0JGk7JEExdWIKejhyQUNW
SUJGQk5DKUsqMSo2PGNyVnAmRD9UQW94aFAzTlU/UmBqN21oaGBsMWdyVE9wSERMcXduWCVnK2ZA
PjFqCnpqWW1kQ2M8KF9xSHJYakx5SWo1YSpxNkYmTmIzVkpuUHA2SHA1KThpLVZjdUZLV2Ixeykz
ZDlpI2A8QHNNcmJ4VAp6OU9MRVp2VDJKPTQ3R3lgWW1ie1BKVyZzWkBCRFNMIyVwNGk5bHIyLS1N
cWQocz1lM0gqWCExZzhFKDY7dWpeUH4KenlXWi02TyhuTzNsVzQrbWYodzVLUClQPn0/TzFORHlG
TVBYTTtOUWNKOXlsWjJ5e2MoNEh1SEFycm9tYG04ZWd6CnpscUYtV3VjSlY9RDV8Tl5RfUVwMClq
ekxxRjteJGVRWFBwKDg0SUQ/ejM7SVJiP3h+KmdKeUJEcXlsMGE9Oz0zcwp6cnMreSomfWhUQ3sy
ZDA3RT8rNl5kTStZfW4+Z0xXJU41T25he2p4bDs9SVFRP0cjPCN3YlkhTCY2PjRnTCR+d0AKenJE
MnszOT1CYHlLIzZzcFlZTns2KmQqOVlZPDVzKVI7VVRaXypoV3I8KXMqa1J+Tjg1VUJ6NT1jI3ti
b21ER0E7Cno4emc/ck5ERUYlcn05bExBbDw5eS18QTExV1d7YDFERng/a2AtU3w8U2RBbTxjSkRr
fTF3Pnd0MUxOSmd8M0pUUAp6KXYxS3o7bElJUmBAUkhzSlRINWtWN3IyPyRyPWEpT3AkRmE4UnNi
fSZmMHFEdEB7KnpMMFg2QzVMZDBTdDlLY1UKemF2VkZJbUFCSDt6MTdPb1N0RyV0IWpkZjNwNCRY
dXJHZ1YwWlprU0pnPWU8RkYxdVJ5dWZYQW9hVUxKRWVseiU+CnpQbEY3YXM1VnY9NFhVckxEYlZ6
WnlaMkZ0LUY9RV5HYE4mUlQxRC1Be3peLW1uczk/M21rbi1eUWZIPFZtUjRGaQp6WV9rbiN5Rj1w
KTNAMmctVkIlJWYtRjNeKVJLN0pEYHxybGFNejxaTnB+YWpxSkdBTVA9UHZVa0dUSChHRXs8d1IK
enJAO1ZeY2pxXis0VmpqYGxxT0FoQmlLfkV0dDMqZFltUDJXJFN5TnpsRm5qNXdOI2hRYmMoej10
dThQeUVAfnE9CnpmOEc0T3RWLTtVI2t0e0RGY2JiQ1BrOF9lJWhiSnoqeSQjWTspZGZqWHF5MWVv
Y3hHYj1xMXY/O0ppaG9iKXdhOQp6REJDRmYrVHUtVlU+QGlfKG15XykzdlJgM04qKjttdWN8dVhQ
OzZyeDlQQUVLWGlYdSh5M1NIal94a0hVTDF9M1cKemE8fmdFPnwqIXErRnpvMlBgMStGezVgakAm
fDlTSys3RXhkYlJGezJ8SVpFWFpNbn5kSlY8QnxeY31kMTEzXzIqCnQwZHw3VyZuTnk8O3M1dUN8
QzszZzBLP1J0WV49cSFfQkZjfmg1JDRXOyojQzM2Jkprel8rTT8pJGhaSWkKCmxpdGVyYWwgMApI
Y21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9oZXJvLnBuZyBi
L2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9oZXJvLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi43ODdkNWJmMWMwM2I1
MmIxMzRjNTUxOWMyYmExOWIzZTJmNDUzOWQzCkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAyMDA5
Mgp6Y21lSWFoZ1h5NWAjKDxXVFh8Ym9UZFJsJlJBc21UbF9mS19SRlBkcEx9VWFEZzNKZzMhVSNs
Ym1BNGB3UH13OVoKejNiSHwjTnF9SGNjOEtndiY7Vmcza05fZTNjUnZzUGVhMVE4S2ozQDVyI1op
eTJjQ09lPDh7NVI+bUs7JVM2bE80CnoteUhsI01uLTByI2lkYGEkakhkdm02Nz97fEtIb2Radz8p
NU5DI2lyP182PzElZ0YzKmc4cUhnZl9tYyNla21Wdgp6O2QrUVkkfTBxT0d4KE1hMjd9U2AzR19w
SStgTXkzNkJYPjgjV0ZyOUJsRHctI1Y8Y3k0Yk5VMmtJMF9seHpoTzwKejJTO1NAOzg8KkZjV1pM
IVA7emxFQyVQbnsrfiV+T3pyWEMzbnxuSn4/bXFDVyt8ajA0eXVKS1hQMElRMnkkXmV+CnpYKWdR
YGVaS1c7eUBZX0IrWjNHaE9ONEtgPGYra1h0SS1iUF4rWV5nSzM+JT9sMmxZRTlIY1NMYXdYeXpA
akBvOAp6ajNoMEhxNEZHYDtxZVZlZlV3WX5JST0lJSYqcX57Qmo/K0BVdWB+SHt3eEVqM08+aVNl
fDJFPD5BQXxrKyY3PUAKekNqWm0kQU0/T2lfeS1qS2d1PyRfcTJSbHUxUipvP01OIWQ3KlBRQioo
NkhDfWBURE18SVImOTFEaSQ7SVluQCRQCnpjdGNFQm19VnVxRzl4e2BiK3l4KWQ9Y255UzlMRSRm
N2N4aDRHcko9RyhHZWBhSWsleyhmIzJ6Kn4qeVAjfTtIfAp6d1JLTFhPQyR9ZT4jTnkzMjh+TCs8
JlFuJCFDPVN9NCR5YF57TDxYcTYxKns2YW1YTXskMj51KVpEYH1lUy0wPGkKekFnN2NlMD0+Sj4/
PlIrbHZeSjJNNUhNTzktNygtI0N1dGJmX193KVo/NncoX2RqYDhSQENnYTRBJD5pck9QQVBmCnpp
SGdyR2VmdXF3VXRPQyF3PGEtMV9pN2dtOFlXd3c5bFkmWGMkc0ZNaStAQlVTYFQ8QGtLZ3RMUz5x
UyF1TlM/Jgp6d0ojSEZsRD5AMldNKmV+Q1Y4fDMmKDN4KThyfUpebVg1fkV1U009NCRPQj0qWiRq
amMhbH57NktXSlBseGNXQWYKekpMNko9XzZ+RD50TD99cG9pZnI3PzgrO31gIUJNbnpqfFl+YFIy
P09oMzRIVGMkSHExcFBwXlZfY3J7dmFySlJRCnohNkROIys0VjxUeE1NPz8pXntwKjtKZnpAPmwt
RT9QNFNTJj1kQFNNJkYhU3dkWTlnUWIpekpZT2c2SVVhYXczNAp6TypFfFhPMDRMbDJaOy0zYHcm
a3slb1p2R2RTYGEtK1YlUikpdzlsaF9GQUAtWT41fmxYZmpAJSYwVUl8MkxldzEKemExISMhP0pS
MVItdD1RdmEmWjRHdCZSWGtteiltMGZVWCpSZ2ExNnMyNUloe2U4bEdtcEM8fFY9WnVxXkE2MFpG
CnpKYjg4UTRCbz5kSHsjQzU5Vkt+I1JDRHUkPkNae0k1IWxzbXdGTlgmI00zXypaKjZPPFd9JWt5
PFZpd3czenZ5UAp6KVNxJElMJCVNdUReeH0+QDxJbERCTy1ZJFJiJDlYPD1BMjw3ZTBUaklhWUMw
enk4WlVLMSg1eGRReXZ8VmlZTlMKelRTMzxFQDEoeWFybChzbm1SRUVWbCZuMCRiPmJAP3lfI3NQ
V1QqIS1FNEMxRTgrVGE3ITlWVXZJQW9FI29WKl9sCnorMnkoUUgyQVZ7MFFUcDhpUV5fSDFoeUw/
TDtYc31WdCYkYFU5dkwyV3hBb0ttZSlISntiUXdoVnQmdzZfflZyVgp6bD93P3BUVn5sRlJ2U2Bq
RVFlekYmTH1vdGVLaEpZQjtxJiFaVWtSQ0ExQllfQ0wlaWdJNHxAWUgxdTZVRWNDK0cKenZxaGFF
alU0OWdMbCl4NlpYaDNHT18hRkMoQEoxUEFDWlBpRH5ZXn5fc257bENne0gwMUx5WnRvOVlgPnpm
JFo0CnpRJFk+OGVXOHFPbmlWLWYjbDVfQSg4SSVMKEl7SW12RX0kaF4oIWhDbXAkb0kqRzxYMTBA
M2g8ZGhsVFBtTHgyMgp6KX0mfVZCK0lFYCFUV242djI9I2FsPz5KIVh3bUM1YGNyQiNucml1MT09
RiMtNlFSQWV3YnUpbHReUGI7KVI0fj0Keis5Q2NkSX1+WlZ4KXBAVnRzXnA5V011QTRsI1RAYjYh
WTFIUE49MHZJdHhnNDZKTG5PZGReYF90Jkl6PiZAdHpaCnpLVVRTTE1hQXlQWmwqTHdASXYmdEdJ
M184XlF5REFFRXdZS19pIWp6PX5HMVdxRmkyYFIjYHBFcH0/V1lCS2JGOAp6d1k3WlNzfHMpMiFD
cX5IYHJfSkZNZX10Z0okaikqI0JhIzJFN083dW5JeUFRTXlBbX4qc3VgVERQNF9MPyg5IVAKejJB
eTVyZjRvYCEzaHA8fGVBRkpiSE5qdD5ge0l0XjFZQDxGZikqQjQrIVEtdmJQallie19ibll4bXQ3
N0dgQSNWCnp3QTdyXz91WDI8ZTRZSUEoJk1EPUtFZzxmMDQtfWJLMTAwSmJOZEpXOylGVlBWYjNe
VHtiS0I+Tm8zblRpeFcjcQp6VXFmezkzazE1ITMtdlI8PWtUQWdyRFAoJVM7Mm04X0VORz1MWlQ8
RExjUkFLUnVvWWlwX3dlQS1aU0EzWjkjVjIKelo7Qm4mPHMzWEowc1dWO3VuX2NfRk9uQ2NJMzcq
fmclZ0FCXlZaMmY+YGxwdG8rezg7U0kkSlBMfHFpczN5MUVCCnpYbXBXcEwodDsrUTc/JGdWSGs5
TWEkTS03UUNJPXxNe0tEKFg8KDE0I3A4QCZBYnQpcEE4JDNrI0B9biNPeTZTZgp6IVFVeyRPIW9y
IVVBJGJebmhVMHVEU19TaFJFN1UoeH4jS0krXz5pITw1P08zT1EwVyMmKnlvdm9OME9LODY1QGwK
eiZNS0FoN2JSO1J5ZVdPPGRpQX5OJTc3ZE4oRUZTWHIxKjcpPUExJCZDN0xKODUhNSFRSzVHY0lO
TiNTdUtFc09BCnpgU19eMlEpfCZnNXZQMj5HQERTclU9YDZRNm9HamdBMExIYVErJkRLUVdYKW93
dXw0dE18d0xGPENkOytlMTVHQAp6OEUzYyM8Yk0xbVZnKFolcmJoX2hEODxnTnBrQUBVWGtnT3ZC
UVIrRks2UHZ4VkEzZklUWm9AYVAhX2piP1VHKncKemBKWTRjT2ozV3Q5PGpqNztuOz82NXMwN2B4
eW1UZkZJajRrdkFQfldTU2ZHREYyRDhUJj93VF9VVEokcmllK2RfCnpLZkI1OVJZUjJZPVFXZGtJ
T2dNdmt8aHMlWEJpP3ElMWFAPnJmVjFJVEJpZUwyS1Y+X2k7Rz5UaFI8WWZHJnt6dwp6YTh5dEFM
ZUdKbSktaW8kK2NSZSk9aiRHOTJwNU1RaThodnl0dEt0SXN7KmAwU045O3VOcTJROGIpQl8zYVRg
WDsKelVGKU5Qd3kqT345IzBsak1ycmV3USFNSVo7STFFfFg7YlIjamh9NWhaRUg4WHVFMVRCZ2BZ
ZGhzNGFCaWkmWW5sCnohPENYKHokcygqNlowJEJwOS04ISl3eCswOSpZKnQqPT1RfSVXRkRhODs4
Szg8JVRmTHNQXnw+P3IxP3BJTDlvegp6dk1wTH0kKkVjI1klJG03I21tfVQrdjEhPml1akNueVJq
OE0pPDteb2JQJm9xKk47R29LS30jcVgrQioqcEJkNHcKeipYJj0pTj5OITgkNypCUHghaFc7PX1D
I0hrelYjNSshfkVqbEVuREM8MkRHIT1pQTIwZ1E2c3A8TyN4M1MtdE1GCnpITCpwcXBxRUNhJnsz
RE0mTFZNaGdfIUBvNDZBMElyI2BCQzc4MkFOUmBMNlkhMyR8aiUqMEI9JmJzeUh0QzZKUwp6JGZL
MSFMfjhUSWVYZUA7SnsqRn5kbkIzeVg3ITlOd2I9YD5CaHo2NGYkIUwoTTdJZERtfXg1OG1SRDN9
TkFoaiEKel4hSC1Ob1IwVFVwUnFmNFFYLWt5eUp0JFNmal9PJmIjNkU0UlU4T1F4bjB6JHRJdGZF
KmNoTH51N3o1N1lrWFhfCnpfQ2lxKkE3X1V8K3IyOzE/TSVZI092QzgoaXZvemBnMT5fcD5STj9t
R099U01wNUhjRHI8em1pbEdTSDsjb0U/Owp6ZVN2TyQ9OFBfYCQ3ekwhRz5PRFdoUSZ4ZlN8Z2Iy
eWdpSzZxTn1RSCh5KDQ8ano/TDl5e3xxcHRGUTM1VEhlX3gKelZaR0t0OUJ4YGRwYHVKOD9WYDNw
MitnI0dCa0RvbkdmUFEtMEp9OWRGZnpjbXcoamlRbj4reHNNTVlqLWRTKFY8Cnp1NlJURUQzPCoj
NG9MTlUzYnZtXlVoKSk8IXE/eld1R1BLQDxEUSZodXZAUEtqa0c+P0V7WklHTSlVfkxnc0F5Rwp6
cnBudEwlPTckS0F6WFVoe202ZjxGITVCbW87QT1ITkRQI2k7TTlSK0VuKjs8dj8remgjMVZPQDVn
aVRDPEM3KDEKenhXKkc0eUhaPzBqRFIkSGd9Zz8oTi18MkI4fTZLbHomKU9tWWdwcFN0KCFiVVpa
c3FGITtATWRBR0tlQSlsb0gjCnpvWmlLYzlqdz1AYn1xQWRVOGJMcik2dHAzJVJpOG5qYCY9PjVr
KzZRJiN4Rm81RiFzdEEjJThKNyQlM1crMylUKwp6I18lOE49WT10SjN3R3tPaU5FTkBqeU1mQ2d9
PUEhRihzPG1abUoyI18wQ0FvM2g0YStDT2RCZ0w7bUYwbm5MWH4Kenk/KSh3PyMock9TSCNtRkVf
a3R7Yj5mZFUhOVgoaSVIekgkNlohMTZ2I2F2PzRLanU2VykqckA0cjQpZ21yVUJ3Cnp2bD96TnVe
WndNe1ZQfEUrKE0+Tk5rXm4mUzZvdHljfHpAR2p+ditLYHdEQXdRPjY+TCpsbnIhUTF3Sm0qNUU0
Jgp6ZEJxITlLayVvVEZmKX09MXBuIURGaFMhdFUtb3xqLXpXUmoxMCRTRSRJSThJKz03NWU/PkJe
bHZiP0YzSj4kY0YKelpVMD13Nmt+eiVwWSZpZWYzd1BQb0pkejUzU0RjZlBmTVVnc2JBI29YXjte
NjlMfGxyeTVodDg3Wl4/alp1bDc4CnpGezgtOz12ZEYxbnlfbDJVJVdoKCZsYmgpcSo+U0F1Pl82
V1JwSTElP1A+Z1lKLT5kQ1Ymdk1Oa1ptUWhOdjIxeAp6OzwwTz0mP1NmVmZAYXJXWS0lKk14Myo0
cUcpam1yVUUkcWgjQiNRP2ctfV9RdHBZcGJUTGhNMCV7UCltQ1pYZGcKel9HbVBKYzhMSiQrbGxy
dzBFYyg/UztNfm1OXj9vTXl+Uzs8SW9uVFVsWjU0YkNVWldfLXIxMjRpRzBsdjxgJH5xCnppRCNt
OUtndm1RUEJsNyN2UyppYVRmVU8/Oz5pfWMlfnpYa0I9MCo9dHV8UlQxaGw5YD9uMkJ1T1kycm1f
dzd4Qwp6cDc7QHhyPmdzN15uTHlWS2E+JTNCVEkhTXs3X0cxWkBqbmB8OEZvO0BldyU4Nnsweip3
Tysweit8XyQmfERsLVkKenQ4LVJqU15tUlYoNHVpM1BKTEJ2TGFxN31zTnNncUNLZ0dec081d3dv
bjJNOGUrR0AqdEtyQldkMHRrak8kaXEtCnoqZVJjai00SVNMQ3k4M31tM19QYWZYNEJLalpeaVc8
e0U4UCEmfDRhdiZ9PnIkKVlkT05FPmtrWUNsTGdlYG9tZgp6YWpyZjNlKihIezVfSzZnKTN1YWBh
PnxxPE9HQ3xvK2h2TjlxMTUjMEgpWm5Zd1lqLUJJY1EpIVFMYERRQ2dkVXsKek09MCNaOD8kKmZN
alUqY0NpMUZDe0ZsVCNte3pnblp3SjFIOWteZT5fZF97ZjFAbDlPemhRNiReZXVsM3Z5ZXZjCnoh
aS1gQnc8Z1lSaUU8U0hmSEVXdlZWVDV+LV9uTXMmd3s1dkJBcHI7I0UrUCFLX0twOUBNPi13ZilT
cVkrI0VjLQp6c1Ywcz9Edj90JjtCNz1uU0lxYiRwWClXVXpYdlVARkt4RWkkUzRaNTRROCRBVW5y
SVU7KntBQjdZTWlDYFZGQWsKenZ1Y29VLSl4WF4hS1ZuckxRZytnPT4wVmwqeDc5e29PWHFqM21A
bnp7OGpCbFB2R2JBcntMfVI8OFZPUlJNcHBOCnp2RmtVY292YX0hTlA0dnN0Nio/SEtMeVhLQ1d1
Tnlyal5kT3JNV1NgI2xALU1MZnRYPXRPRWdgfEFmWUgrOHBDYgp6KE4qcFh0MT4qQHBrKldMV3Zp
NmkqO0p3Y2lHRk0hRVB9O0VnTkd3PHBULUh2WmN3Xnc/S2JaMUZAUnZieHpDbjQKemJ5U1AmYiRM
YkswdTw0MG9xN2oxXioqKjI/enxsPTFaZDdST1U2VkBBWlF8KUJDNmxlZz4zKXAmb0IpNGlXKi0j
Cno9STM1JWB8Uyg2Vnkqell3QV5xbFZMTiNMPU0maU17e3FAUUtCWHFmeUpUOSlkKF5vdlB6cz9Z
OHZ6YU9wNWMxdAp6LUNAVCkwV1FGNmtGbFF7RUJ9XlRiQE9kS0A1eztraW4jb1BZZ2xwWCNLMTBp
U1F0I0BvZWoqRjlkaTRDTnN4JVEKelNgME0kWj1zTEVKPn4xTWNnI3U7NFRUNEAkRylKRk1nOH4y
T0FiUGQ7QTNiMGVqaHM4bUV6MSkhcjd9Sk97Py1SCno/MWd9R09BUUxXUUBPUSlebyk8cWJQdyRt
ez1uP1llcGA2alhLO0NDSjx4QitvdWBoMW5OeUJuNml1RkxjUkBZUgp6cDx1IX44ekR+SihROTkj
M1A2O2wwJHpWQXswXzJuR1E2TnFaQndYcSVrflRjMm51R3hhPiFnKStVIVJSOzNpeVgKenA9VnE/
JHxJY1hBc3ZQflVEQHBQb14tPnpeeCNPPG4rPDFgaH5FfiZeQT49cktSfkt6Wj5sbUA3M0F6Jmta
cFFyCnpfbG97O1BWMXZ3alZ4SHhPJCpEOXkkdXIxPClFS1hqd2hSNk9zTXZVTGhpVzsyR159U2pP
R0JZTGZuNVM3TSN7TQp6a2Jad302MWRCfGtZbChuOEtgN3EpOE0rekQ0Skc+am5uLVFFWG8mSDls
dFR5KjdiTz95Kz9AeEVEUXtHX2VaN2oKekJZeShaeSomMDc2TVNteiVhaStIT2NeVmZNTlcwPW5r
bVJCOyEtP21BOHI/MntLS0oqa19jWDJILV49QzFpWW1+CnpzclYxRFRhPztYX1lLPDwmJSo0JD52
OTIlYWpVOCMtMGcwRnpqZDMwVENlbHFnKno0QUBKZ0xjcDE1flA1NU96SQp6KX5ARCV5P0s3RXok
PVBQO14lPGlkKTMtNDU2dlRVLTNfKypfYiM3QzJ7JkdvV2BSYD1PdHJAZ1ZWYyo0Y2JsKk8KelpZ
OXsoYnJLcXFXP093NVBCa1QpbGVzKGROWmlMMWk/amFsIW53UT93eGpDTSgwQ1UyNXlje0BLO1dg
TjRQeUYlCno/X3NVQj54RzM5OTBBPlJ7OytvSzJ+NklISHxPYENUe05oIVBZM0UmIyNlVTlMWHlH
N3Nyej1sUEAzIXt1O0luegp6O2ZNUGchSFklP09wdk1XPHBjR1F5Y3MzNWp7K29rO1pCNnYmKzMh
d1FuPShFOG5galpfak9NKUFIMkYteTsrXzcKelVPRiRZUm4oO18rMFBZTFRSUXY7cz40IXFVP341
cXkxZ3lVZiUlVFp2KDluUVlNVjRkPVoxaWVBMzM5LShPdVFxCnohbXZ9bSk5bTlIa147WHY7UCQl
JTJsUn1hdTclYk1SLWM+LXllZHhPPl5sal9xVTwldmQrQHZlYWBKREU2M3haawp6ZVRMNTNLWjQo
dWR1X1YhYm5oRmokWjdVcGBGYkppUnFqODdIfGBuKilsdU80Wm9oeGNXZHcyVT55dFFJJFRkSSUK
enspX1gwQDhScm88MlQ2NGpvKXxmazNTVSNJeGAwY0EkIVpYTT51XjJ6Kl96PD99QEprRT9fPT8p
TkpzTSt5Qz1UCnpGUGQ5PipSOFhpeyRPajlHa05SKD5lWW5xamRTQ1p6bTN6SHBGXzFoMG9AdSRa
Zj8kV0M8b3NURElrKTVhcjw5egp6MHNCWk02ZS0+VnhZREloYCVAK3lwfUotPXoqTl9OX3QzVl8k
TCMrT0FsdSMlR1l9ZTU8TmlNfUdyN15aRHIhRSQKekt3V3V0RVpKKCVZM3UpcHYrY1hCNkEyaVF2
NUV4eFJpM3R4MV82SH5qckwoRXFKXiRQRVd9MGtkYyU7fnkkUHZ4Cnp5TGhtcmw/X21KZDgqd00t
azc+TzRLRiFReT81enV6MU95cVozbTRneUo7KV8tfF4hZT4+dU5pMVJ8Jj1XWmxjcAp6NSV1Pz0r
dSVWVDtxbTghKypXR09NVTJqN0oqPXRQUjZ5aEoyd1NRNiV1UyRKMWF9QlpzN2VzR1R0QipyYF5m
T3MKej5zfFUxd1RpRmQoQXE1VHpCZjQ9aUglX3hlP2RLLUR3T1ArVFk5NjV4ZGRydV5ZP0hjN0RJ
cHpnZlY5cWs7YXUqCnpsfjxfTFloT1ZIYjtvKHdvWkdsWGNqYzZFYXk5Zy1tRVpTVSF7b2IoKnFz
ZSR1cDR5QDZrT2NNYlpsQ0c4KWxFUAp6YWVaWWckbSRWSlk8SkIkYFAmPmdJUyN8WShKfFNPbCQp
VihraHU/TUNyUSl5QURoVSQzOSlPPlc9eV5SQzBae3IKekxDTDZeRzZYYEFKcil3Z2dfRjFDPUlV
UCFxbG94KD5IITFnYzBgaFFFTz1COUZ4KXJYYEAwMSshclJSZSs4aCh2Cnp4YjYrMXNFTXdHT0wr
d25wOzdJMSp2SjJXaj45ZigrX1VjWXdvfF9UaV56NEVNTlFMKmZiajhybFJSI25icyUpTwp6cz9W
VWRNNFBWRTkoejF5ezclKUc5Ty0tLVRBMktMYVdnKiVJTml9cUslTTsyXkF5elJ0JiMpI3p7X0tZ
VmMqRnwKel5KZ2NyUTZrcktZZzxPY1VmKEZ0aU1vM0l5QXZ5d3lGckwjITtaU08rVnxtLWteJi1W
MDtHdUdBVW05IWMyKUlVCno8ekpTK3o2emc5MFlqYmgta2U5c0hLWENqWmVZUCtPSXQ9WVFKYT5P
LT9aZVNifVlXXzNQYDdRKFR1SWIxTzIwOAp6S2ZSIW1QUSsqY1ltfEBHXj8qY3AtT0pBQSR5OWVZ
akYrUz9PSTxgMjxNR1Z5WnZ5bn1idyo0O2dZJERSOUJxfn0Kem4kJl5ETi1MTmJoajhKZWB7djV9
R1khPExZPkBwbEo8dit+P15aM2MxazNzclFHYXxLVkFtZVVnO3JzVyVSdUx1Cno3WGImbyNTRGx9
USk0JWE0QjAkJmooKkV9JklyPDlxKyFkRndrRGpzIVpqYFUoOzhXdytWKm1TYnEySnhZKHFpZAp6
Jjc2eyZZPE1QZjY5Si1jVnZyTkgoPi1jLS08MFQxdUc3Rjw4I3QxNStLYElsWTQ+fmc9ST1SbVIt
JjFgdX4qSjUKenJffFJSOXM2THZ7UVBZRDMqdVpAQjJmRis4PDVAM3IqIVUlN2skM1JjVzdpUDAy
Vk9raytBTHlyRH1GTk5gaWohCnp3bVl+WXBANU84Rmw9P1kqPSpzcHlvRUskVzMkYk9uRC04STcy
bCpnMWZvbGZxUCoxSDFpeWYkVTdIb19GWG1xUAp6OVBlMHlNWCZfOz9kfEpJYnNTM0FrITdOKCh8
Oz5SRWJyR0A5Ujt9TD8/TkdTUTk4IUVlJGVWYWxwVjZCaz8pQGsKemNVUEFWR2smJnI4UiNlRWQk
KXwzMElFN2EyWWI/SGVQaVBoYzZ2aXtOPiFwfVZPTTw9Zm11MTNYe3ZScSo3cFJsCnpGelIkSEdq
Ryk3b0J3TEF2MX1Caj5+c2EjSDRzWnt3aEghOzxeazBAN0UoaE14UlpUJSRTcHdQPnc5Nks/U0lH
awp6QE0wfEglZGUxbWswKUN1PDQ5YW0ka2h7NjwlNmp8MGFzV1YyYGkoKlVYSkkyRjImbm4rcl4z
RSMoNyVEMGcyYlcKeiNGKWswVVlNcFQkKSRjSVpfe2swK2EzeiFMQ29VITVjY3ZCYFQ+Kjd2T3xi
Rmcyc3BzXmFuQWJVZj5sZ2t9JVdjCno/NVZiVzw2R3Y2dVgzfmRBek4jfVVhYX49OFJKZzI0TVlM
K1N3eDt4PFdKfTVIXilEQkRqPVFjdWspTXlPRWYrNwp6Sn1lUVN2T0V2UW81cEo2UHo5Rk4lMkh0
aHtgczt9QiYpfWEmZTk2dGU3Ri1jKE0+ckBfSElHRDJmcDJ1e2BqVyEKelZuSFIoYD14Ml5zfHw4
RnBEV2pKbUstVV9HU3hvUzRDRW59VighREAxWj1NOWhWRXJONT19XjJEKkZJZ0lTcW8lCnpFM0pC
aW9QQXBDPisqdWE+Tj9FdzdpXzVMaiV9YSFoelc/QCMhUUFqI1FPb3VxZTNPQkI7JTNsTkJZKm0p
bCE8Pgp6KCEwMEJFbG1iKlIzZ311N1lnSnFHPylneDgpclohd1NhfEV1LTJYRGVfK1dicFZFK01q
JElUYE0jQzwrOElgfXoKeklORD90eGtNQDx6S2w5ZVAjRGh8ZSVafG04bEt5QEF8dGJUN1hTPH5w
YVBNfmF+bzUxaCtSVm5tTS1mMHt0R0pVCnopczNzMU1ePm58MyREPnIjZTs0aU49cWVtMHEpTDlT
eFJrM2R5ZyhEJHBVKCghaEFSfk9FOEgtSDhXPnlTdmcyUgp6QmdURH5KNVZmPWZrfVZEJTxmJkBA
ezY7YiFkVDVWPilhJC0hZVJqTDlHS0VDNlpZOyFwfD17eFMqWDswZ345JHkKejQleDUkQ3ozUVBA
SmlnMy0qPSlQZHE+PjBkZC1PUWRQT1luKF4oVXgwJnVVcHhkNXhBQmJHZmBpYmtaVjRmMzdZCnpy
fnpicHFKS2tpIyE8ODZTSUpYUitxNjBwWmxKPHd3b3xNfTkhcDlmbzQ4WnEhZ3swX1k8KTI3RzJW
NWl3Vj56bgp6bnNub0xLVGdnMkM4fWIhRX1KU0k0Uiltb0kpOHs0d0xMUU5tUSg/aGR7VHB+K3hT
ZytSSFFNYmZobjtVU14td04KelZ4ZFpqWF5TVnVqNmE7Jk1hPkt8Vj5qMVRwIXx9akR2dzU/aSVv
bEg5c3cwRSFPXmpnayhna2RMUXx4WiFHemBnCnp0XzNxbFItSilkPSRiQ3RmOGNwcT1vKWk7aT0y
dnU1Py1sSVl+S2BzMkx5TF8+KmshQzNVNWxye1l0PGArMT8tIQp6bH00e0diZ3x2U29XbnhhXkA0
bHtsSCZ9OG9PXjNWeV9YOS0tPGhUJE9qY2FUPTBOMWhvdHhjKlV6JW5TcVVURk4KekM4Z1J6fDF3
MmIkfSE8MSFwNlpGM29ET2lNK3smdVFlKldPdHNQJXk1P3s2fDZOWGFlMEJLZUwkPE4ofmleYWRq
Cnpea1lzQFI+dGwtQj4tQztOREM/SiRrJlZ4ZVEwUXlXbyZZKng/dGQkdkoxYCEjTXRwPChPYEc8
Rm5ZIX02IWdDSwp6RkV+WVE2fDg+Rj1PN2M3Kyl7eSQxcDc/M0BiJEBvYHxkZWFYO2lhQnRxOz4p
bSkpPlJudiU0QTlAQ0J9OWBednUKenk4UUt+JD4hNXxWfXd9cyp2ZG1JbjlyXktDVDlIYzQhMERJ
WVBfMUFvenZvKndIYjNnbXNDbTAzVTZ9Sik2fEdtCnp5Vj8yM1dAbGcwV3R5RXlzUUs8TFljOzF4
ZkpTZGUzQChRRWJ+TzByQVN0aGxIam51IXp9NTZea21FcWs2TjwrZwp6UVN8PU5JRzI0SClWUGgw
SEBBaHtWKnYlKit0RCp0QkJQell1PldkTiUmRikxeXtgNTAjdnR2UC1mTl9+czI+cV4Kekw0eVQ2
UUkzeGVNPiY/el9ERW4mSFY1XzBxIUM+MlR6aEEoVztjWiFpcEk9O2JVTXM0MkgrbHEldVMmej5K
bHFaCno5JSF3KjQkT3hXQCUraDhUX0Z5SSRDR3MpQUNjYmp3QTxaalF4bH5GWjBQcDBkQzk7VXI2
dmw+Y01YLV5gN1BRIwp6PjFfK0xITDk+bTB9Z1lvTWkwWTBySmJKbWJmb34raDRMPkIkI3ExT15N
cGI5KFNGUDZzZXFPZ2d6YDgrSHQqcjYKenVfNzNQeHcqKHVSWjJmI3RKKzQ1JlBxT0kwIW5zPWxo
NWpXKz9AfHZ1KEhrI2JYdkpAVD54d3ZaNj9QfDRiOF9qCnpUdjVVNCMrPElUSkxJJEE1NX53Z2c4
ak9XPXFJYHpTKlJHe0t5U1lGaTFKWmg3QnhTYnAycGlid08oO0Y8TT1ecAp6LU9nKzI/LVJQUG89
djR0OS0wYWYpcThMKk5yRCZNb3hPcEh7eXNmJG1gU0tPSXtmUUcqVTVvaDhkZjVjPSheVUEKejxJ
eGVsbGp+VHQ9ejdBU2NWXlYjOyh3RCMwPE17WVc9Q15Fc1kqVkI/VjhmVTtkZSZ8PE4kQm97Um9I
andIRmpjCnpsazZxZWRnNUVtb25oZHViQHlzKl9NeTdkSDBsIyhNI2pwRitySTxzRWpXMSUwc00m
PGFsSzlqRGg3JTtpYjFGYAp6JlhtT0txZHthXzFsSlNnLXxWeEhMezdQSEdiOUJzaz04byk8SyV0
fEYxZ1g+eXNnJlQrITRpNkxTenp1e15uSDUKejMhdkheYXB+QTZAP2l0NmNtNT83LXVNSmA+USgk
MzlDanp4KkQ5TGtPMlZjRHAkZSVRNjE7cWg3RilqNklXfXluCnpxQWxyQVd8ckBLXnswYl9BJHo5
VGZrViRnQnJ2NS1fbTEjS0Eyc3A2NDheUi0wc0hMUilRZFJVbEhmX3xaWT5oKAp6WXgjKj5IX3JX
OUdRREpHbHgoVEcjfTBxVk92JlkwPE8jKEgrVD98WihaPTxWWWxUX3xhMUA9ZT1PeGhnUzl1NkgK
elgqVnEhMTJKVmV4Z3slWE1tZG1kKmwmNGo3fVYkZCsjTjBXWV40ciQ5d09VMy0mVGtIXll0KnR1
c3QmLV92TzV2CnprN1B7bz0/aEBmNmBkPFkpMjYhaFl5a2lwSDspU31yKW5mcmVzeF5uQzhULTRG
bzNsRCs3SkEobTNzYkM2VFNWSAp6Kz08U1BufiR+Pz0wcHJtWllBYkwlfF82cns2dldKNWxYYDtF
JjFqbmRQamsrSkZIfHRPPiEqYldhS3Rabl5qPWYKektveyMpQkV7UXU7PkI9KlgjSH53X2dTfUQ7
NVlTdWYlPF9NRnJIYyRHKE5DO3dGdjBlR0xQb2xIUEprIVcxZ2NrCnp6LSNWJnhVNW1GRHloXzBy
YzZDXz17NmJxYjBjYkkoOXwmVzIqR2VlcXhPTkBWWWgqQzAkYl9iWD1nKUgzUmNKfgp6eClrZ2xi
ezJQOTxiVXlDPCZyJHVFeFZmcz99dTZ6N0w2cH5zPkpoSG5qa0s3S1ExbU1hcXY9LVJgeVZ1b3BR
N3EKekQyKzExOXFRNSp0MChGXyt8QXR2T3JFfHhDeWFgVWwtX0ltalAoalpkQnQ2Zis2SzEmbyle
RnJscXtVc0NDQnV4CnpNTHo0WXRVa1dOPi00QythMT9vSG07ZXBkR0x4NFRXfExpMEomPlptOGJE
cEVTNGZfXnorbjQjeDI4NGtvPVNMPgp6eUwxMy1WQmcmaiVRYk08YWxNcSpxRkhDXlkhbjZMcUtR
VzQxVExtVlo/JlpTQT1YWTFCcTB1ZHFYUmNFNkZuNEAKenZSTm1CPF5CZUJ0d1hyajEjTiFyWE9t
JGd7cTlzSjBEe3whYU9sUip2Zm9USVltaG0kZHN3JTlNWHVwPm8tekclCnpeZTBOfklIaWY0QG0+
Yj9VOXFtV3c+USRRd15uczxiIVEkWj1HY2REJHs7cnBhPjZ6M0ZWeWVxZz5zQFZqUCEldAp6blJA
fko3UC0xMyhmdjI8OFNEKD89JXBsYmJIYT8+THFmOz5scU0+JXtRSEdCU0ElVk16cS0rRGI+K2c9
KWdtTloKeiQ8SGVvZk5Ic3hidGI7ZUx4VFZpZXxMUlQrMj1iKmt6Nn5CT097X2BZXkQ7OTdFQFFS
eV9YLT95QGxWQUJzUkVBCnphQWpHWWR9ZFEhVDM2YHA1cVA4YWo5R3VGOUNpWUVPdjF3RnZgUjYq
KihIJDBVP0lfJWBTKTR1R1puVFE/eUBPcQp6ZGZJOFFKTCVkN3g7Nz1PXiE4TGpNSn1IK2R2OG9Y
IVdqSl5FI0lRWXdQWXJmXjx1MGwmXnwxNWppITljWjZnOTwKekIoVmtjNmxkZSEqcUk8NXliVGJ0
OGF8JTgmZH0+OGFrV1J3Kzd8QDFiKz9PY1gwfEtgZjIyUVhhWHgxX2tsciFRCnpGejJxVjkzXjdE
VCVZJGx3R0RIdmtPLTFSKmBnRHthZVpmQVdseGZkd3tmZiVJNmVrTjZke3EtdkFyazt4TXUpOQp6
aUBtR0RXJHpNc0lHNDRpLW10U2B1IWo+ZEZWQUc1NXxsZ2kpZjFTS0hpa1ReUSkzfnReb0lvX1F0
Jk9CZCtETjUKej4kS3xAXjwxX1NqY00/S3sjanNjaVhiNXB0cUhnMUw/RzBQdHN5dGI8Y0J5S2FW
Rk59cmtrP0JXdShhOWVaRCl1CnoqbGNxYnlDbjV8YjJKLVZRXl96KSVKKnRNSk5gekN6UDB2Tylh
Iz5Va2BWMkwhTVJRN3JVJkdoPG0yPDFfMHIlagp6NE4yRHpAblolTkRtYXN7VzctI1RBMjxScUcr
TSROc0xLSTBlVVRocXRzN297OWM0QjAxQ0JydWdpRDU4RT44Xy0KelIyYmAtV1RJXjEhUTt4SSVw
Nm4zOzxGZG0zT3hOdilhNjEtSjZeais2UlJvXzBOfVBVPndIQDhad3dUdTNKTXRmCnpGU0daYT15
XkcjZX1aJjUyPHhLZDN2Iyg+KW0lP3FEYkRZTjRAeEFpcD5VQHhoWUJ2NTJ4cnRQTDUpVkUrRDxL
eAp6aDN1eDtPdCszKiV7eGVTbF49QzF4I2VNdyhIayhWQjw2eEMqU3dyZF5xdWBvM2gqWkVqS0x1
TTNhPjRyMHZpOzkKelRjX0ZSdCZ6Wk4qWHlBO21UfktPMjE8e348e1YtKnNgdjNAM1Q/LSQ5b307
SmlTZkUjWHdOe3lxaWUlWWBrNkQqCnpBMWNBQiUmWVgrKiQ3VHBrTUBQNVhtd1FYbXtVUHNzJkRk
PDF3LUcwKlUxZ084VmlOc0dFPjtBdkt0LWw9SDNJQwp6a29eMkIoRyU0JWBUVyVIYWZFYXdEaFBn
MF9UbiNLKT00OE04WUkkbm1UYEwtc1hAQm9tKWh4PjxONWFBK2khMEYKel5WXyQtN3ZEQDh8TXRo
UFlMVVhxdHdCRmt5cC1IMXNpfj02PVQoTW9ES1dQaUEzZFNAZUJZNipae0ZOfT4tcGRoCnotQW50
RXBNSU5Pb0QkJTVtUUdocnhfNCVLI3ZpSX0+V003fDJIcCs0Nyo7KTdzM14oY1BRXzRVTFdiV2NN
Uk56NQp6QDF3MkR6UVRuYzM4JSRWYU0lV0JaT0FsTWtzSFh5RClMMTBBTCo5S0VxYk0wczZoPnl7
YTshQFVSU3RpRCh+SGYKelN4REw7KmhNd2lDQ3FPcXllTH13aSUmWDs4JEkhP2JOSmx9T3FueCZJ
elIhV2U7RmZxMyYlWmV0KkQ/UUIwNj96CnpAIUAtKTt1NVBQNSpBPmotaWdlKWd7LXJvKGV8MDZx
WDFucFdWbXBkeWo1aUIoN2U4d2hDYUJCeCM3ME96SVd4VAp6P2t7WEJBZFBCN2FQTnJxPSgzQl9h
RnlCOzRHRzs5MjswMHViRiMxXiZvcUI2IXF0fGdlSnIrYiZHdnt5dmNnWlQKekR4b2N8Nj4lQ0xL
NjR0SzA5VEBBIWU3SEghOCtlPHtiOTdBZFJiMl8/VmtLWntvJUYtMXN1VT1HfkdiS0B6KG1vCnpY
QXcwNHl+LTJeJnwmIzhUOyt3XkVZZUcmNjZTe3k9NC1iKmxTfmQ/YWRmWmA1c2hFPHExRCs/R2Ur
TVVDSTtMewp6KiV6UTs2ZG50RE8te3AhSilHTF8mX0M2eHZgZkE+N3h7M0kqWS1aTi1ybkEhK09k
VUJlWVNvbygzJFdjWXYyfHUKenVSM0Z9QyVlV3tYal52QG52dyZqeVQhMXplcUglJWdEMEVGYGN2
aGszND1HS2opSzdmXjxneEYtQT5ockFjZE9rCnp1UE4+anJPdW9SYlJ9R1M1MyVid2UyKGQhKmpH
dFhsTzAlVnwzdCNla0NiPnIkfktPJD04KlBqblQyJn5EO1ZfYQp6PGI3R3JKeWo5Km5JbjMpZD0+
PTg8REBmSSZpYkFueDQxPlliViFJYCppZWZPaDQjO3lNQFQhMU9ZQTZfcX05Pz0Kem8zaT1MKW5a
b2FnbF9lbWdLSmppKXo9THFMeUh+Xy0yJD1NPkE8M15KO35JOXRJNj84T0ZsKGMtIX1BUSZRUC18
CnpPWTN6UFA2bUoqPkslcGFzbH5WYitVQlZ4SzhjN2R6PXVPb0BIfThmbkZudHMjdiMtfHBYR01n
PzlrJmtAUUZJfgp6XmFCaEs9O18hVyg1ZU9je1E3U3ctOWV3ey1APzJCcDNXYkpWO1ZmJntyU0h+
fDdTcVJPOD9qcHZjZjtHZnZ4YVEKenEtPmYmPUR+bEghKH1wQTdXfiRvVH02KSgtYTBScCUrVj5o
Zm51akQ/Xkh5SkgkSzcobFVPfXlHPGtRKyoqbFpaCnpTTGNWMStTdTZtX30pbSQraDxkN14jbURT
KHl4Q0ZTSXV0b3ZVRmswISg5cUJfQU9VV3Z7fmZpdDJ6YmBYLThVWAp6KT13IUtoXnU8RiE8USNa
KjBxb2xZZ1YwKjwtJWs1cD10RnoqM35NfU0tN0NYblZESmcpVCViRUg4MGhNWXxNO3sKektXSzI0
RUAtWXpSPyt0QVl+ODBVYVpnTGtJZH02blErfWZLLU1Gfk92OD9PTSQyaGRLcyg+Z0ZFTzE/VihQ
U09RCnopNUIoKmg3THtJZyV0SCRwUG1sfVJPOVNCQDtjTWNYIUZMUj58KEBPYmtCaDsrR0gjJSRm
SVQyJnIjWjlPQThWMgp6OGYwPUVWe1lhckxROGxheXpSR3M8LVk4bXcpZTclYkBuWmJeWSpXSD9U
WTVgWDt7K34mR2JKRDNrI1BAcXNBQjMKeko0UG9zMTllTHBENX1eI2V9K05XMiVxVzc4R1k/ez0t
Z2BLPmNTd1pCUUVWLWI1fil9IW8tVEgjKk0xKntEaEAoCnpeNUFZZHFyIyhrcnRUNFFkYXRyezZ1
WjhJS3BVajJ0bVRsSmk2fj16cUAqWFVIe1h1RVI5YUEwTTYrUERGa2hgTwp6d0M4QGVGa21jZGxk
dXdqZlJyTyl0NV50bFkpV3FuQExhaE5QTT0lZi1FODBHNkJzITBuZEd7PyhkXjtRSFhjUE4Keks2
Q35mLWNtIXhNUFVOVDt1Xz1pNEcqWEtOU255alNeV0ZedX5XUDl2b3A4dlJlT2M9a1k/V3p0ej84
cXdpMTA9CnphdWA4bylYUHw8bX04aVVRMTZ6N2lGKURHcjwrWUAhI2R4c0V7IzRGMnc0MWwrPWVI
cUtkaSZDT3labD8jVFZvegp6d2hjLWRlc2NwUSZNbXM3XntmJE4xQyQleU8lTVYjMHhtZmx4SHkh
SlVOP319al9tOXAjbEUmbW5ASz45Y2ZZUS0KeiYkbyRrOFUpcGxJfWU4QkhfSThjWHVZYG9UOUZA
ViZQWWNCOF9PTTRUKjBnKWY4O21IbWJGJlJqVjljO2tJXz5sCnpoP3NVV0NnNUpaR1U/QGxhJj9g
NGBXZHZCV0xqSEY+UitGemtENHh8QSlpXnVTejlKIXJePSo7YHFzcTVhY1BTaQp6SmBDSygyUmh+
aG8kYmFRJDlfP2ttQFh8WDxxUX4kVEFQU1Y+IVpRYmElSnR5cFBTSUA4UXlHO05vVndMZnVgI2kK
elclQEomTzU5dXJIVmJecTQ1N3RUYjNgV2FxMXJIS2IjX1lNXzEqWX11cjczQWZaMmlNMmRoemhn
N0p+XzEldG5KCnpqdSNSbVR1VjJXV3dsV2didD12O2BDRk9EQCtPOHJmMVMze3FMYC1RUlBFfl5u
WEBPMW9SQ049aC1sYF9lM2A0NQp6NkFMeUdvP25NXmApRlNvbDJYVWBWckFxZT9LaFZpY0JFPTdh
OH52cElHMThYMnQ+cF93TlkrV09ec0szeXVHMVkKenFKbUxhWXxCblhMIUpKOVhVUW9YbU5uK0BK
R0AjKjE8fkV1dXZ3VTlPe0A+cHpJSDZiVE9gWFdyOVVJSDh2T0xfCnpzPVNAK0pTfCNpQCR2Q1NF
PVVLNXt1Uz0/cFlGUm8lWWJ5eyFTI2ZIWnlVcG93WlJ1MEE3blJNdG5jMm5ZbkxMVAp6ajl3bFN5
QzcjO1VDdWE0aCpiPX0pTWR5bWJfQFdrUkdEP2ZQNFBwPGY/QzJ2I3ZVX1UkVSh7Vk8keFJLKWVJ
KHwKeiVWZ2dYN2RqTGY7dE5YKTMpP1hiezNZeDw1fFA0NEd8fihXNEp7a1YyMUVRPTV7QjZXejhn
QypxY29KJj56OzxECnpQYFpTTVZ6ejYhUlgyc01nfDdLNV44UlckcG1ue1JAdG1rZHA4WUU+U20y
WTdzY1FnXkIhIUcyViYrcWJhfU8xSQp6WWY8ISZnI25FOyhNTUl7bCRLX2pVflBkcnhqMzkqQjc4
ckZTZCl5UT5HZSpQVWVwZGVfdGxFfWJoa2xiaHxrZz0KeislQnFwOTZvWSo1YlZaR1I7JFZZVikp
X3RpeCtsajE4Y00weHFpJXIoYzBkSFlOe1Y1R091VW5xMD5LbHZeLWV+CnpjU1J4ekA5KWNjZkI2
SGc5bm13RHorU0VBbUt2ZXlWamdCTCtzPjVsKitwNlktR3hzKWlUPCkoSjthfHFUPFA2Ugp6Mj4l
V0dIXkgwVy1Sak1ZQ3IlR0lxWDd5I01PJH0tQHMmdVMzI2twYlJxe0FLXlB1dVVmUXhje240UH00
KUFYbDgKeiYpOFU5UT5lQ0EqSjJPZj9VM311R3NfbENLZFlrKSE0X3JYQ2lxJUpGVGl3TSR3XjZZ
ZXdQc2RVPiFkSSlwZSF9CnpwX2lnPSheWmg0byV9Z2c4OXpUUzdiQ20ySHFPbjlvQX5uKSkzeV8k
KitBbDJzX1h4WlFvbGpnMjFPbG10VEUpKwp6Xkl3XkFpOFFiN0ZCaSYmX301QnFec2teRDkyXjl6
Ykc8JGFUREpvTnNFWT1CWDNQZyYpQk1XRmRJMTNlPFBmflAKemNEe0ZXPWJTfHsyK211NXQoT2de
cnxnNWZoTTZKODVvN2dISmR4MGBBK3RAK0hRaXRqYiRISjJ6YXNCN2JvWE91CnpeUkI0PkVrPCpe
UG9QXkc3KCYlel9rckw+UXt9cztoVXBwWEdAVVp5R24lUGVSMmVlJjc2U2Nhdzt+WEVFUHxtZgp6
Jm5fcGtzQTJWXmJAdTVxaj90Z24wV0U2Kj9DQEtXKEpFO1QhWEMlZk9iQmQwJHBHV0pYTCpeTkpE
SEVpU3woNHUKeiR4VWMpTjtJeV5RWGk/dWB9d3ZuOGRQRkJzIWAmUEI/VXtAdmRXTytZTHp4MClI
eiolUzA1anJWR1MtQXJKUHdmCnp1PnY7VVdZI2I2I3hja2luJXY/Zjg1T1pNOXg8MiRRbCYpPVIo
LWtnLVdDaU9TXyZeZGBqPFFTcytsN1pUKyMqeAp6MjJ8UkJPRVF6cG01NS08KzdlZj9vPEBuNUBk
YFBESjJRUmBZemZPbW9xITdleTgkPWVkUm1rY2cyOERKaURVPlQKemkoSzxXTz1aT0dQWWJ+VjhR
JTNiNykkN2pOKWV2KDMtYyl8M1ZReVI/Q3BDNDtpREltJjgxXmxedD8zWWdqTVAoCnppe3ZLPDRO
ZjI9LVBPWjVzVGojZzJaPTNQZjJCXnVOaEw3ZjFUb3k9JmhSV182fm5HS2E3KTtwaXxHfGNFfjgq
Qgp6NWR8aitYPDBDMEgpc1JqbWQlN2krUHdDfkBXOGlCOVg4RGM4dzQ7aDQhOWxnYlg/amdSP21u
LShZNUp1Y0M9bTAKejlWKU12UWh7XkJ0KTN3PU9YPF9IMipKJWozUy1eYWwoJGxSYCRtIyF3N15w
Oz1GdVFxI0EoKUBfUENmQlZOamRXCnpLXkhiP1p0VmlMbT54aW0zRXF9Z2xkbjJCT3BvYz93aH5k
PFBoKnVNJkxQTXYmREo/I0lER2dRbylnamM3Qz5YcAp6ZCpQbjBwY1h8IWhnS0FGeDU/QCE2JD9L
PHpsSjswYSQkM3N2UCQ4PG5sNE5CZk19b0JFa2FYeVd5N3gqZkNBLTAKem5ETXNHYHUxNVIlWCVY
fE9Aa1k/bUNWakFldWAjbVpObXhgdmVgSHBMbkNXT2RyeVNVODZpM0V3KGdMZERKOFI2CnpvS1V3
IzI5OF55U3dmeT4qMFFSPCtXMkBlez9OMF9ONm5ZK2o1byhDcGcrY3p3Jm9fOSlMMER+Z2JiQzcj
UHNOdwp6Uig/I2E+K29edjtzZmx6cHp7JTxzXngrUThGd2EjezZeNWNZT2MzTjchbnYyNzNJfkhu
VXNpSyVyIyZYWW84NGUKelIxSnByKVZHTkVUPWU/fkRjc2p1eFpgYGVWb3JtNkh0SV9EcUs9NGAl
QExoKi1aQEZtRiUzTGY2ZDJkZCM5Xkd3CnpEX21xOTIwc2p1YiN6d1NXLXNTemdRYHdQTjVAa3ZT
Yz9lYmJCeGIxLXhvVm9oRzd6RzlwP3dqa1BucSghZ3JyQAp6emE2PFl8Nz9BSXo0ISs0RUxYMFIj
d0s5VG1Yd3JgcWFZfTZSKTYzRGwtSFhvej5oRyMhUEVjcVl0bXttYm5pPlgKeiVeNClIR2U7OC1C
IXc7dlBNYWdkRTd5ZHYlMzxOUWluIXE5RE9tKGpQZUN0bWNGNTdlO2FOcCleVkE8NjNEb0VKCnol
QilWYl4tT21Kdi1eYWMqfEM8SWg8ZHo5PGprdTUjTUFGJG02SU50PyglVj9YUkc1eShKfDR5OU4t
dDV7QXpWWQp6Z3NKJiUjRjRudlEqQnpmWHleUUJ2KUctfktlVENHUjcjejAyZExVcjNfP1kxMkNJ
YGRgRHxzXiU1azl5XkdSanoKelEwPHcpQGxTbFdxTXs7bj1ldH5WLSV5YWVqe0MyTFNEdH1OLXMk
YilvT1I5XzRWcDJ6dUdpKTBMKipwNDNtNTV9CnpCZmIwSEVTVGtsPkl8VXA5Un5FdXM5OVI/P3ZO
e3VRSj1xREFkMi1ke3VyRVZaSitgRmtDZH1zZVkyfHpxdkAlcwp6QGZvJTVIKDg/Ym9TZDErbTdV
JVZwSTNLSXBybjJNe29WbStebk1NZUtZYyhoPXVaQTxsbnBBQXlQTWxDIXRAdHIKenlJVWBOR148
KiRhYGJkfSRaMEhBTnVTdTtiLWVsUnM2RkAtUSlONThrR1Zgflg9I157ZyFqP0ZZcGdxQlk2V2NZ
CnpSdGNmRVhVcjRZV2hjLVBHMkJyeUN4cmtPOHBNWi1oO3hvRWVKYG5nO0N+dWVmJk8yQmJ4QkIz
TnJ6WkZaLSR1WAp6LUNLdEFYallFOysxQiopRTk/QDJrYCVGSGhIfF4rZytiKXZXcUpLYnt+MlJM
YipuVXVnYHZVUDdsK0xnTy1eN1cKekVTOEclKlVMWWQ/ZGcyaT9TYlVQPkBmPHp6SE5fRV9Tb2BZ
SEEqSXRReWZmI2V5a0dxbDJWcDEre15nJSQmd097CnpJcjxReTx4cHJ5bXd+dCMlaiQ1dil6K2hg
KXd2ZVNUVElrbDlYPmwpPDx3aFE2QV9SZi1RVjkyJjY8aTNgbk0zbgp6VWNJbjBEfUE+cGp1PnpK
RFo+eVE+NG5mUzB5KG0rIWR4KlcjckU3YHk3O3FoaEpvOzIha1VNOWR7PmxhajNlSHUKeiFNSms5
X358WiVMR1NhQHBYOCZiVz53JkdoeEllPyFwIXV8Pih7emdzaFZ4dVRNcDVXJWtidkwpcElYQz4x
NWItCnpRal5TfCUhWUktKDJVaHZvKXtTLUdCXmw2bUNhJWUjUnlUWCk+bWo2NEZJZEh3KiVqMFYk
WmdFSkFIaGhMbykmYwp6WTdKOCVpZVQ1PHpFQTVBbnB3dGlPdjQ+WmJMRXNgMT9ARGlhWTNrN1d7
Syo7S3Z+REQ/YVhOZnNXYGBSVEIwUkUKejtfJnhsbUN9blM7PFhhSWkpN0E1LSV9SyUmZ3pNOUVX
TUZ8cVJieHU5NV95end2dXVsN19TYUJAI29fOHtpVGdeCnojTUxEXnBwPUIpZ1R1Yj1XelZFaE5F
JklCZz9pJEtveiZRaDtGUzhCPUtxTXtvZkNFcT9fNjtOeHpYPDY7fWZ1Uwp6OVRjKzktMENCamRa
SXlTbWgoN0Bqb0A0T013bit1dHVSOzQ4NXhuMiY/Z3lnSVJBbFNhUG8+ekFOMmB7YzglXmIKelR6
Z2BDaFRVZW4haSYoQ2F0NGVtdUBQTSszLUpZb2dfZztPcUU7KjliPyYmd01FM3FeM3ZTP0tXQFZ3
NWJ8R3ZECno2VmJ1I2tKTGopWUtpcUd3RykhS0MtTWVydjQ9dWhQbG5XTG9tOy1VTUxWby1SeTVC
LXFQUU1LcW9iby12WERLOwp6Ki1Je2FnXiYtc3t0IT9FPm03SHsqKDc3VVhDI3gyPFRkczZeLVY0
SShpVnAjcTxkUWBMeHl7RXokTFktQyFYbygKej5yPlJ3cGNYQT4haSVOIyVhdlg8JUspMno8fGx7
N0UwI1daQit+amFkYW8yelZRdl5MSn5pdmZIUnBCNFlgaFBeCno3dURDQlI0UWtyTmFEcW4oaW93
dCNsYHFAWFA7VEJxTHVLS1IxYlZPaHYhN09YPzhLOzBJfE9UdkpsNmNLJUlLVAp6V1h+QEo0N01J
a3V1a3BfcFMtNzdqOXJSOVNhR1hIUihXSnlJOTMmV1ZMemgmOVlaUEViQ0AkTkFHR25HQ3JTbjwK
emB1aW9GQWdxVDVgVHhFUnFDMnxwVkxaNTBXbWJ2KVFxa2YpdXFZZSs+Q15xUTtTQDJiRDVCTUsm
N2FJeWdgSD5JCnpSazclT3lsPlJkQSRmfEptIzVPIUQxbyRveUt8T35ARWEle29eUmA4SXNvbFVa
bnJsfCNJKy1YNkJCcF5UbzhIIQp6eTwmdShgdEIlYW1mPyZqQVF4PzBNVTk8aEtsVX5YQ0BVKG0w
XjFaVjMpRnhCPWpkMFFlOTV8VWpVbSN0bWdJUCsKejx8fHghaTRXTmlzX0g7QVRMUTFeUnJ8TH5N
VD4kdXNjWUlhJDRhWE0yd2khbitkZXx7czcwSWMtcFEjVlNWKytWCnpfLVRqRjB+VldEUypFKG07
azBSPSsxe3NuNkhRRWE7QlAjZ3JrUTRpTkNmbzBmeHp2I1N6dCg+aS10eTR2V2wqKgp6R3lkbjIo
b3plbmp2NUI0PHhFTFFqX0wxJGs0bzZ2VmZZKU90Nz9SKDc+Rl8pUTlpTjB6Qk1qb0NtZUVXRDUw
RkoKejtHUHdSa3NFenxWTmBwMUFqe0NyNSZSdHZ0MEFoXmtwQkdNZWVqYUpwN1krQmRkKWNucS1D
JU80OFR6SDVfbDBFCnpZfG9ZNklQVG1ATGBxT0AlTTVUe1haaWl6VUhAcntfNUwhdm1zN3RHXlZG
JTVTRXJyPlI8aHgxYUglNktDKSR9Tgp6SVRTZmd6dU1jKDlMaHghakBPUjhxbFdxb21mOXJtOUJT
PyooSDVrIWBGe3xRcWhuKilXXyNwUUw3ZlFEN0AoeTYKenl5OHNKVkRhIXcxTmJYayFnIT1UVUBh
fjVZSUBMYy0mXnJVb3AkRDZ7VChlcEo0LV9udTJFcGVJQnowbFdNbCs4Cnp3TUJWaXJsTTlubFRj
RWxYbl80LXlMRk84QjRKbTAzR0F2UkJ4UXFXVDxgQSM/TGZgWCYrRHhGU0Aod0Z6Z0dIbQp6P25o
OD80M2BJKXdiYmxWKDRUM1R2cSNmYzNvTWR2JUlAaFBZYz1TZ2EyPHJ7cSEjNmZ3bVY/bWMteyRY
QEdWJDkKem5pZ0x2QFNOfFFHdklaaXVRPU9oV21KTUpHJW17RHBMZUJUPmdvTzY2RDtDR01lTG0k
JmQheXliRSsxfTVqJlhxCnpIOHB4NXFtSXVBbnElVlVNbkNDdTwrfHVCMUxkZ1MwK3BvVkZfK1Z5
TUc1TTAka0s9JWAmQkc8QUJ5fW5mOWQ0NAp6KCQ8JSVhYz8pfks5O3FIKjVtezNNfll8cWIwb1NZ
VzhYKX44Q1R6YFMqb1h2bFJgVzAkP2x+N2p1NHNGY3VXNGAKejZTPWpSKlhEXz1WYm11eypAZyoz
UkxzcllyeSFtVTF3a1Bvdj8hIzchUXR8bzQ4NmYobStHXjdPYXlsbGowOGhGCnpoakdpLWduSk9I
PHhkV3RJbUBHXlhRbT5JMyEqP2U/NSFiY3FeUlF3XlliTkFRTVUyUT88I0Y1SGtxbCk2Yl9mQAp6
ZHcqKVlYUnRFRnpebzZ7JXpaWGpaZmtjcWlEcVM+dFBfPD8rPiszJkNqZCZ1Pm1TQiFyRmgpV24x
TzhCVWZ9UlkKei1nY0x3VUIlYTBATXdZNFR6OVRIdEFTVW1JT14rSEJtTjhzY0hLSTtzd1A0SlVH
Nn1fN2VXXnFQLUhuJEIwPldOCnooPE5GJioybkBiSWFGYlFkN214ciRpQ0NMMCt9PmtlMzFKdiNr
TVBvOV57bVk7UThsYGFzSTswPXokMmdMKURvYwp6MT1TNmt5bE5zSndwPFEmOThiI2JHQzlWXjNS
TWtRdm1VXzxPQjcmaEUlQXE/emJAPzE3SmRlTU8yTTZhSlYhQEkKej00XiN8eiM0bVVPUmV+YWZZ
RiY2KGNxcWpFWXMqbkNkemFwMzdRIXE/fUd4SnNrYHJHMGwjKXhDU1FGa1JgKkEwCnpmRGVCbmx1
bTI+WTc2SWMyamJ+Pk9eS0otWnVReV9Qby1NTy0yI3p3bVRAbTVnYTRBZkNmPDxwWikrTih1SXhy
RQp6K1YjfUZLeUJONztBeVgmc2N3RmI9OzVpRCRlPmdjWmxfPDJHSH5YaVh+UHoxJClAUjQ5cUNY
aW41UnJAcS1lSH0KeihncGJpMXB2NnYmUTBfRSUzIWdMeTx4T2dLPU4yOWpyfSV+SSUxNnZ8MCRv
ez8rTyslclRtcFdYbkt7OTlJflc8CnppJE1kTCZqR1BsdmZlKjFGZil6fG4hN2ZkUHRDP2xDRWI0
bztNcnxreCMpZ0pEUjk1clF2YDA1NUV9ViYjQnx7Xgp6QjBtajVEYE4+bCk0Wlp5bn1+KlRgUiMq
SjZCSXQ9YSVuaENYakRfP093clVBZUBRS0FofjIwbENRYzlLeClJUX0KemgkMFZYdTt4JlRUPmIy
VjUhPDxPYSRmPypJQS1VLVc3VWdQcF5HIU5iOGJrJlM3S1J9Zn5uIVd5b0FLKW5CJX4hCnp5PHx0
V3w0e2oxVDFoeW9VLUBtXntLQ1Q3PVJ4T3ZlU0lzdm1OSlhvRGtDdzhlSj9RVjM3XkdMRW54U0Vu
bUotcwp6WjdtOERVYEJZVHZwU2NPbnJoPWpqMF48PGlFTShkcjRRTnZfbGVkcm9XeX07fEw2WW9L
Y3s3b0xIOz0pZ3Nrdy0Kcm5KOD85fE0hPk5AYilzJF81WGJHeSY/NVc8JVdkfVViVGhIVlI2Q3Nt
KHJpemZCKmpnbiU7JE8KCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9y
ZXMvc3RlYW0vZWNsaXBzZV9pY29uLnBuZyBiL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9pY29uLnBu
ZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwLi5hMTM1YzU0ZTE0OWVhYTkwYjYxMGE2OWM4ZjliZjZkZWIwNmMwZTY3CkdJ
VCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAxNTgyNQp6Y21YOV9XbXNFSCgrPShxTVRAKDt5Rj45KCtA
Kk1ONFVpeCQ0I25MSTZmZkBYI2k2Km55SWM3M3l4KlRCQylifGMKeipfbkgwWEdiRDUpRCRwS05s
KmEqMEVVdkh0UUcoTzFOe2pES3RfYXE4TSohYjNJSz91RGFsR3tgKCZNVV8rfVheCnpfP0VuRCZr
MT4tN2BJdUNxITVsb3dYWTJHQmQhcHdJUCNtRjY0ZkUjQjY1ZDE7aW1uO0FkJiVkQ2FRbnZyR0BF
QAp6cWViVGxsXm55UjxUOHNVYmN8LUpQR0IycFY9Wm1DXkx1YkZUaT44S1NUKl9ldCNhLTc5QyZo
ZFV7Slp6V2F1cmwKejtvTmFJWnxFRX12fiVTbk4qKl9+VkBMSCpNSXkqZjl3dk5QTUZNTSpPdHV1
cW0taF9lQTNoPnc5PH4lK3VIRnV4CnpQe3cxKDRjUW1vIWlEN1VASTNyN2wmYjAkZCUkc1Y8fko+
WTRnV2dvQyt5WTczdSZVemU8eWQ/ITtWWH1iWndwfAp6Xk02ZExQaXpAeUpVezFfU0ZpQklTVUpr
flBFMSpJNkU5M3A8NWNSYDYoaiFaUlVzTzM2XiZvejgpO3p0WnlydTAKejREJChPRGNPSCVJUDNp
OTB6cCk8K2w/MGlDeCZSPi1zamZKejBRXmNsdn1qTHN8LXE2JVhMXmo/SiVDI3h+QDg5CnoqR0RP
YUQ+ODxzeDlEIUNTMjhCYWxgMWszNUxaVWhCT35Ad2tgMz9rYmhKcFgldURCQXpWPzFjJVcxeHhp
NHk0QQp6Vns9fm03JURYfj15aDduYDNvbWwlVSYoNSQ1ODtfaTY+QisrMlNqRXRMJWB+QEg4MkNU
fnt0cDBsS0FvM3dTJWcKeiNLTyFyRjRmam14YnAqJjRKYEB8M2lVK0Qkald+TUFQPXdkKmlVTG89
RjgqZkN5fSgrNi1edE0yWkplKmskS1dCCnojQioydlAwdX1QT3QkQkVtUSlKdVJIK0J2Q3VZYGo1
eENPeXtCQStuLUtTK3ZZYW0+ODxPMl5YVUkzREcxVyVVVgp6NTUrK0Jfb1hFUTltVVFFSWlIalZ3
JHRZZip6bnxWPF8oTj9Wc3IoK0QraGtfUzJKdHUpUntjfU1ZVWAtZnJWVXYKeiF3YTQjdXx6aX5O
Kk1pbTsmZ1R2SCloRUQ5KmRfZ3hIU1pOQCY+dSpeMHpYb1FNUjEoKjZ9aiV0O2tPTSlVaXNrCnpy
fCE3dExSTntyLTtRSFh5ZDc1e0tlbzJFX356YHQkWjNZd3ZFI0k5c1dJe0tFQWd6REIkbClnSWlS
YzJhdj9iSgp6bmlLc1QtIzxKKF80azxHcmpyblVGS0Jwd0UtYChiNEooX28tPzcxezgkPHBZcjhr
SVREcURMMlR6SUtre1MpfXMKel9WUkdyUWZ0SX5WQmYmM2JwMihDaXt7MUE3bV9uQ3VTa1B7ISkz
dDRvekQ3bkZZVk01akw/K2hjMElFM2M+VnRICnpBZmNsP0gjOzsqTFgoQzhZYWdsKnVERWFQe1Fo
PnJ8ODRPVyhrVFhIWEhGZ01jTk52U180fUd6SHNtZmptQGI3NAp6emwoPE9maT47bkJ2R2dHYEsy
MGtMaD01RVgkfjFoelVuUkFmKiEtbkRrcGRIO0hpVWohfGx5N1A3ST5aPTZ4M0UKelRCX1lFI0d1
U2xMUFdSQDZtXmU/dytvJihYbFE4UWFfKUozbmFeP15lMUFSd0o/KHE1Pn5ZaTViNlE2OXJzSmp7
CnpXXncmYzR8dkBuZF81LWdoUXd2Qkc/fEpTdjJKSktSV0B1WTBNKl5NdmZPUGVKJUs9eHM4bmBI
KyRXQmYrdTdXdwp6bzVePjJXOTYpUCtmN14yPyYwNFkpVyomfWNQQTNCeDNsVlJTNXdfKVJJISVS
MXxrVmhAazZyfWYoSTMtITVXXlAKei1kfVdieyM8fEJjcFFtP1I0QTBmZTVFODIlc31NaUpfZytl
UDt7UV5kUDl5bXl3NFlYeV42Rz8/NXZadUF9KCEyCnoqfHg3I1hpQiRiYHk9clpDbEI9TmVXcFZR
UDJIfS0tZH4qfCROVWEpLSp7Yz4oWXBhVXZjMDR4RkYpZUcxek9Bdwp6QXc0NnglP3AoYCtgSWQk
bXMzdiYrMF5xSnVkVXNFUnVrSig/fFNSSWZUVXxOUV9xY2dOQ1h2ZlAwb1lnbytkJG8Kelc2MnlI
dWZSQyorZTRmQykxeSVvIU9EaTdzRXlmSCM+eGlRJkZBTjVaWSt1ME9QZWFjay1lcj53XjI0MCNl
UnZpCno9ZDVwNiNORiQhKTlOTjNDIXA3WmcobHw8Rn1fR0BpRFJKWDN2fUk3NnJRZ21HanljWUs2
Zmt8dH5aMz1JdGtPKQp6NzByYUBlbThLUGkjZFo5SlJqRUdGTGI+eG1pWjxsXnchYyZmVEI0OEY1
NEE0JWRDMyFFfGJlcV5QTWomP35pdk4Kel9qeHIjSDhXdiFOdG5PekxCSksjamFPNmgqS3MofCVF
a3NeWjw9aUcmYHZyJlBFQn1Qal89S31PfHtzMiEyNXk3CnojJmJyQGotNVZMbm13RWI3YDFPfCZG
MmlgMCgxJVMxY2BCU2c2OXFKWkY0c3RkQHhtKGNZN247VGclJUZDeGptPQp6QnA/JTVvZSNSMl9e
S0BeRCVKXjdGdzV8UjlZPVF5VUN3SzdDIU1AZ3gjMUtYZnBHX1VOKH18Y15XWEE3O0lNaEkKeipI
aSUkVkJicCFyQXpkTW5uJUElNXNhOzZiaWZJUWJLcFdONjhaQjxQZiViPE93S1c9Wl53P1ZvPEV9
fTI8Qm4pCno/RjkxN0NlVklsSlYtUmskX29oVD9MNWY3MnooMjlzQz5FWj9ncX4rS2QkK2FQc1NK
NCYpYmBzTnNfbC1ebClfagp6SHYmI3NSZSNfVmhxUE4mVkNAJFNhQ1ljaD4qYSM/YHBxNHJ2cn5v
UzkoVjs1e1R3bzVGdVR5aTs2OW9DO1F2K30KejdqUGB5ejIyez9QX2FRblA+USV9PzdofS0rU1BS
LSkzeTVDaSZpZXpafVRGU1cwI2otWTBWUDVecVM1QUlrTUlACnpfTUdGN3twMHdrMnhZamtZJWh6
YyttbTswO0J7JHZwPHUxRC00NUViU2s5M282KldJSHRiNEIjIXxVI1dfdURtdwp6LU97Q2JIOURD
UmE9d2IkRG5Abk5KPFgpVmB8STRAQDB7M0lsVU1TfFRTfl83NWUyT1FUVGc3Jm9tJnxXNSpFPn0K
eldJZDlCJjRfdDA1N1N0SWtGX3l6JmQ7X2orSFE4ZilsaCtjdClGa3pXXlJjZzYkbSgwaGRpcFlC
ZG5eMW1HMVNxCnojdHltfldeKUtWMWRFdlpLKSY8OXlWQXg4aUlHb0VPWDd+Um5idkdpdz1KeF9Y
Y2hnXypieGM0Yl9uaSFFY3Q+Qgp6ZX53V2RjJjZaZXpVdWpkekB9ay01RDVaKEw1OFUpK3VkdG5C
SE5+WWk/OH02OUEjfEMkJm9aVTctPjh8Y0EzTl8Kejd0K3IjRk1qdUxtViNCNlMqXiQra1VafC1r
YyFxSldLVmZPPn44bi1gYEtyVG13IT07SSZoZHV2dGVZN1FIcVpACnpoOUtYWSYyQlNzRzAxVEIx
NWxKRkxgISlEYFY2X3gtU0RhbEN2JWVwRi1uKkxVUTl2biM/RmcxbEBIMFRfelcwZwp6dWFfNUJW
Pz9PZCtsKmMhamR6e0xZWnZ8eEMqVFdMPGg0KnRlcHAtSD5vSk1AJVImbUs0XmZaOTgkMFBBWjdZ
bFAKeiRpQlhYI1FEcTB5M3V8UDNXKiVVOFVYQm02bzghSDBsbl9CRkFfbz97VHAoSmN0a2tvZyUr
QWhGNjF1IVokenFTCnpSQl8xMHUqam9mYzsoK3VpKEBqeUhKRFJoNTF+dFEqVXhKKUM7TXppRm87
dTk+dG9LcVYtNW0leUk8Q3lhJip5ZQp6QTk2MSRAY3VXOUtlfHJzYFE+P2BeQ0o3ZzdhOzxNT2sp
R2Q1fStuS1c9WUU1LWUkeUo3QGFkK0h6ckN4KzBSJkwKeisreV9nP0ZZc01adX10M3VhYFlac0Yw
c2JiME0hOG95S2p8O1g2Y29yMmFtbGIrYHpedjZsQ3o+ajQ5JXtgWE5PCnp1R3BJMEZzVSNOXlEp
ZWRWZ2YxM2QjdVgoUzZme31KY2dRIyl9dXZrPWRvPVVmclReQW55eFFjdT1JUVluNClmZAp6aG4w
bUtVJnpWdjlyRm16bil2JnspdEY5X15xZjZrcXd+dFd1KzE0XmwyKCFTQz8yWiElO25+KzlwY3M3
MT9ZV3cKelliKmJBSFhne0xkV2gjYGRQMGJwb1pSRmxOYUQ1SWZOMVZJNmY1VkhSM0lfKlUwdGxe
PkRhIWdFSjxmSlAlVjlFCnpONjBObnJfckZZdFIhZGttODZKSTtOcVlManwzZGZtfmJpNFd3Vmc7
WC04MTQ0LV99VnYhYmI3JHs0dj09bClQTQp6dX1uNml5ZExfVEpwfllkSjVweD58SWghMz5Lb3Vt
PSNgKj1LK2gtbXYjZGcxQmhqMHYrXyFDSnFQYmdmdGdPUnsKek95XkYwN300azlLOTE0X2ArVmhQ
Pj0pJGpvcGUmaHFOTVdxPDgtOFh1fWZVJiZ+Kzk1dk0zYUV4Vk5faGN9QDZQCno1NipuMygob0pN
Jms+KVZoKWx2R1Z0TnRlYWxPWUNIZ2dJSmROZWtDKmpvd2s2P0kxfk5AfD92N1VjQnRBeyMpVQp6
QUF3VjBLNk03WXRWRVMxQUtUbG9KemhmTDwtcThgbWFPYn4qVks3ZWA4YHEwbUlCViE+YyNuZWF6
JUhwKDJyRjcKejI/YGpjQiZ+bWkyMUNec2s5U0goOHhKQCl2ZExpN0ptPC0oIzZtX2IjPVpWKGZS
Q3M8IyY8M0ROUTtnXz87KW1jCnpqeEBASSstN198c1RMejRfRV5eOGQ7eVolRjtSPjwzV3NORVNa
WEV5LSZZNHh1ZG1gPW1TZWQmYHE3KD9SLU8kOwp6IXQ4Y09iciYtOSt5RnZFc3ZAbDtxNjdiezRJ
QGRXV1c2Pm0lMyE9NntVfj0jaG1aNGc0OWNYMSh9UWAqKHN0dnIKejRhVV5MO2hSfTlTKVZ7KmEp
M2ZVMUJZbFgjPiMxQlV6KVQlSnNZTX09RnduRSVHbTd5b3R0fXAwREB3TjM2X2NmCnpgUyh3PHtr
bmgmWTIyUTJ0RUxwPjNFPWBrPmMkVjI9dSQpcDw5bW40PWZ4IyRpQihuWCFwa0N1PVpBVFBsYCsh
ZAp6PlcxdEp7OWB7K2RpJHx3SGpMd0YzSyRFRkR6KGFWaD9yQXxtQCM9b2pqVVgzZStDNz8rfX5u
cFJPKnh9YUdDb0UKekR0eipaTU8wPkBxdC01KUU3QkM+UnhZKW9DQmoyZnhqKFlyVkxibDhrYXNC
cHUhK3taX2AtfWFPNlBqI214TF5pCnpFUTkoVG1Wd00mYlRwTkh1aTFLM0ZtUT5oQkNRTEkmO3BD
YjxMayNRYlBhcHdtaX05LSRlQHkyZ1NuPX0kU1RqXgp6U0dBNWNYVzNgR1BhcEhFMjxYdkFaMGJE
Tl47SHl4bCZwQSZTJVotVTQ7Vmp1VERANiRYK0ZzVEJLTDctb0E2ZlEKemdGNDFBbFctWHAxPHpz
S0I8KEh+cUl0amB7V2hifGNUMD1RPl49RmZzR0hJRypoJXgwKHZFQyVlamhjYnJxP0hxCno3Oz1W
PmNYWnQ1QmcqeWF1NjwoZEYwQXckQ0cqZUNuJklFeig4YiU1UlllLXo1QUYjVW57NX59IT05SjQk
Z0IqbAp6KUE5e3NUSSp5ZGE3RHRSJHZEZSNvMkR9fk5UdT0ycUtoPmNyKUs5PSl4OERLNGtpeTRf
ZVBvSyVGKlprPyRTb2QKem83V0g4WDNIfSReVDloS0BgTzwkeU9NY1ZufDZ0I0M2U09nYkRHMmRE
UXl5e3BZVkVRPktAQldsNGVOYD89JWBACnpOP1RZT0soTlVrfDE+RVk2e1RqfWNPezBWaGkhIXRY
PztsZyF6Un5lPS16M3leOXx2QTxxMDxLez47cXlveE8yawp6XmpgJStPJipfWjs9fkBvRzcmbHEl
dWVGPjgySjJmdmpINTFsKXY0OHcmKGxKM09GKFlCKnI0LVY2YXdZI3Z8ZyQKejRROVI0dz9TOyU4
Mk9PdmgoMk9UeCtrKWc+Nkh+eXdPY1I+MjR5c0xPayNLRCE/WVlyakZ2e31MaDFhOGhxdVJOCnoh
bVFkMzBZfmY0KU5FSiZBQDR+Qi1POWRMdkNIQXZ7PGl4K3pMVl9WUi1Wekp7P0syc0h4WnZJUUNU
YVJEVSFzPAp6S2lLZWd5O1dURjAyLT43LS1gP2Q9Sk43UGx0ZiZTQlJYKGQkUEkhOF4xUm58YDYk
UUBSRigrYExGKGs+Vih8U2YKem9ZNGcreTRVbyk7RG00LXMkMkojIWpOZWFvUDUzViVgRDN+dUYp
MzF2bmIhUURBVjJ5T1AheWteQVV9PTE+fVpkCnpxKG9tPSVwfCVGMTUkRiZlUjQjK29VRE9HJE8r
TVppN1E3a00xd2JSaXg/dCRYfFB3ciYwU215OX5XKFZCUSM9Owp6d0Z6dV9eU1BgLWVvaGg5Jm1i
QWEtalhvfGhsZ3Fzays7TUFsMVJ5VjZkOEhXS04jalJ1I19XV08rfjVTRjJLe2gKeiomblVtUDlg
KU9ldzlZQGFeT2dBQmJVNnhwcWVBV3g7QCkkVGdsbERHdDlOUChWeiZZO2VgMjRETz5tX1ZkQlpr
Cno+dWlsQWY8Jjxwaj9eLVZubCNpKFJXWGxHWHxUYEtfT28oRUN0Kl9RIVU+Kyotb3BaKCVrRi08
TEcrQVpYcG5NeAp6SkVxVF97PXJwanh5aV8kT3xBbEU8bG97RlZ4TjhTPHh4Kjx2WVdhISE+MXZl
Z2AzMW1fME1IcnJiLVY5UCNNXlgKencrQENHPH5aUlBxKzNpMTN5IVQrZSMjQGp7M1kjNGEtK219
a3l8WlB3MWtLbFJwSjc0YXwxQ2lJYDsze0ExbURSCnozYCFtczwmUCZGaV58Q2hnRENGQWhmP3sp
eVIkX2EmNzQmRCRFST5kYzVGaiQtMz1LcmN4K2A2XjB7X0hxNkxCcgp6IXYoO0ZWQ3RpNHkkST84
endGZCg0e2kjZEd0YyhaLWwjbUNsRT8xQ2Y0TksySy1TJDVAY1pmPUVhPEtPP2JVSW0KekU/bj9o
M2VnRSY/Vz9KZTFPYWF9V2kzfkgxQzlKb0V8QEBqJkpHe0F3NkQ9eHttMyRWeEZ4ciZ5RTRfakFE
I1VOCnokfDtlVkI8fHRvUjN7VGs9aDlRaFp4cFFzSz0rRnN7cyY3I0hTPTEtUis/YWZvPD1ZdDJf
RkxuJjJSP1RLYUZsYAp6RnRlTD8zJlNrS0h1fH5taj5NX3BAZ21ofDtIOWM5Q30oZC0xOStAbzdV
JEg5ZmoqbCEkd0xKMWU7bldURz11bFIKenFnVk04aV5tcXYlK1JCPiFXPHE3JTUmQnlOP0htbDRQ
X3Vybm5nUXwzWS1DeHF3c047JENDMGxOVmI0MDxkYlJTCno4SExxalZfU2AoSD9GTyFFPkp7Yjxz
TG0oJmx7PDA/Rzg0YlFwUyl6ajl7VTVuPDdlQ0twP3IwI0ZPK2h2YiZZYQp6cm03azA2KFoqVnl6
PUxJOTNkOX09TEZxcmgoS3FBJU40QmhpMnpsY0xgMD53LTZTRjdPODklPXlWTDkza0Mldm4Kej43
MD8wVWd1NkJOUEt9dHt7KiktJVYlVnMtTSRMYj4+TyQrVkt9SllYQ2ZnNiQjbyhKSHhrdHlAbzEq
TDFiMTgxCnplTkFne0RfK350MSNLTjZOTTZuZDBiTVEwS3lPRFghbWxJRHZxPld6ck42az83I0FH
PVJUaGFRLW4wWlVuTW9qUwp6dmNPPWZhQVdkR0wkciF8TVJhbVVZfVRLRjlAWUEpUGFfOHxTa0FK
XykrK1NCWG9mRmlSSXpVSVVxRGl6TkBZWCgKenhTSzVxUmxZVloyRDs5dGRUWTFjO0hlQUFSZ1Jh
MSVVd2lEQUZNP1JST311YHhkREE/N1hQajdeMmFgYkVgcWthCnpzT2A3Ny1yfEVsNkE5eUFZYkxJ
UzleU0lMUnhiXnUzKz5RJiM4KUwkTmEmbWZ7MEw0Rz01VmBCT1ltRilafEJ+cQp6bis7dFF3Q05Y
RTFEK30wXiYkNmozK192I0NKTCZvUzBCNSs2TTkqfHNUJEljPUdjR1ZjKTMlNUpofnhldmJ4VEAK
ekVRSHxhZnQ4SmhnY1lFNC1lPEdpWiVKTitPflIxVDJoRWBPXkchSU9ZJmtnbHUjfExlP2BiMDx4
cGV1JEE1cnhGCnokY1V4dit3VGNuY1JSckhIRzl4bXVLUjlQYnh9UlRCJE5NcGctRGxVbVZCUjZv
V24pWTJUbCtqdyYqQyUtbCljbQp6ODF5ZFVZOyNwYXNJfUF5PWU8Iz0qckg1RSlFYXtSYUpEe3ko
ZSo0b05xfVRLeGdVe0BeOzhsZlooe2JfcT0rVncKemhJN3phS3dQbU1oS3lSQz5BOFRwK1NzNFd3
Ql9wSXU9JnU0KnwyZkA5RWN1YVZOck81JC1QPSppNiNJIWVzUWMkCnp2N05OKWNxfmFEOVE/aUlf
eClaYVJeIURsRDVSKDlNSTFnRngrQmtUZzhRPE50P35Fb19oXiYoKlFYeT1KS2B2Nwp6PXlhdyZl
dG9wUWFCdHNBLTYoOSpEUHxrP3h1VCM7WG1efl5yRTs1WnN1TXdtNTx3ZEBmMjs3TiVHM2BRXmRS
RVEKeiZ+JmQtSHJXQXdJViVqdXZqe3lgTm9uKWB3bF5wZUM8KVJvRz9VSWYlN3VFKjZ9c1dzKj87
YUBaMTl9e05LJCNjCnowZTg/JSlGIStLb01vY1M9U1ZxP0hmcTBgNXFLYUhsUGA5SmtiZGo+WmFq
elQlSzsmbGlON1Qhcz96LTxqPVJYUQp6NCMxU20hLXZ6MVZJZ0VjeFR4KzdUSyNUPWNYeklnODtG
P3w5THo2ak8wdiE3NEZOa1BRIyVDX3pOO2pyZmkwVkwKemRMbk49YUg2YU8/bjUqcV45OHBucy1G
RCFBe1M8I1cqWXY1e2l4fmsjanA3PTlWeUI1cWNENzw8Nzh0PXVzUVJkCnphJWFAZjFfa3hJWFJL
RG9Ab1o0eUNXYVlxeV9VQSkqdEltMFh+IVZ9Pm82Zj4qUG85LXNPJWJrKmtWbEpGIXVwMwp6K0xB
P0BCdDhNQDQrYlBnSEkjOWQoeEM2Jnp+RjVIVlBvQGFgY3o8UTFmYHVHdWNKJlJPMnlFS1BidkNl
eSNQcisKenkzSHohTF4yTzw7I1M5LWF7WkRUOVZjdkZZP3pkcD58SH5ybH1mMD4+Y19yR1p7U15H
K3FQPmVHYndCSz1qTTdkCnpyTHV7bjxsNz9ARHVtRUV1bztgalFpeWU+WEh2OUFgS0pqTEdfSz92
REtOPj1tMDhxTnxJNHEmUU1+I0w/bSRrbQp6Xyt6czNrKWRrS3hPfkVAUz9BTnNMU2swPzM3SjBM
ckk4Jk5ZeUUrekxVRmx0a1lAIWE7akRqeDBZVHclQzF9VmoKenNlb3VmJFkhMVRvQWA7dkBqU09N
Nk9xc3BaWHJISjtBV35RJiNIblVmODFVRWRzYmROS0MxJVhhJFFTJnBJUyFkCnpvNVB8NGZONy1O
YlR9Tz5BQFlGUitRLVY1U3cmU3NzTFVFVyE4eTlYRlZfRSU8RDFuT1A1NXBrIXozcGJgJi1WXwp6
bG1hWE8jO01vQkZCR05fSzllKFF3LXhIc1dEfjtUQW41V2A4YS16fnl1VkNXMnZqYDsmVzstPTcy
d1h6Szc7NF4KelZWblc5UkJ0WiRTMko+PlBrbzcjI2RfNnI0OWxAdTMyMm5JX189PE1ZRjxmVUJO
XlFja2JUQSY8c04xMiFoeVJCCnpqNjlzQENJcVRuQHRYbXdXRj1mNlAwNjcmWVlMUkNobiRzUj9f
Nk0oSDJ1bEslWW9wQ0hmMXNTNVN1WkApSFBkQQp6eSQ8PygrM1FGS1RDPj59SD1ASXJYZX1Dc1pC
JUpfO2BASnB7VUo1THNZLUR4VU9kej8qQkZoPV8lNEM5aENza3UKenFYJkdScnVLSCk9ZUdUdW9I
LWxLU2VqZCtEPnkrVUMtZFAyZXU9VGRIc0E8QztDUHE1MkJYRXY/Kll3Pik5ZlB+CnprNlhKRDwh
K29wVEBDTTh0UTxHO0Nec2tjYFB1MCVzPSVOTUU+UystPyRsZzgxKXxXLVMoVW5jezRiPDloJl9y
UAp6M281eW5MQTxMOElOK2FGWigpVlBzak1iRmNTRHVNTH5+UW9rcllaXmlGPTtpfDFIPSFMcklK
YG1UdVdCaE5OSioKelY4I31raHg2OGUmMU1IYzNEKFNiczFuYnQ7Tk5Nd2h7YnN5JW9tNFQ5Vnd1
TU9vYyZJQmRKUjxULWZ3eHJ4T3NUCnpeek1PNjM2e1EzMzZATCljVURVcm1HXmlGKSYqSDhrMyVL
bykoVXB2KEhDM2B7eyhVRGBSIVc+Zj5MK140QVN6WAp6PnZoajYodj55ciotUitOIVFuc1dVPHtS
SVViX3pYJjd2dlpHUDRJOCU/fUp0K2BrRklESVVNa25BQmJwdkZxMW8KelMhaz1YSyF9TDl2SVNB
NHgqdXtqaFRVYzBjS3pvfUtiZDcwb15Qaj1WTEElSVZkRk18UEVibTRrTHhxNHNVVz1BCnpQO30/
JT83ZlMmIUJvRGItP0RgU0dzWVNtLSthcW8xRVhSaj9TJDY+S2UrOEI+QFheTHN1Yj5YMWY8VWt3
ZjNTKgp6RU0xe3ZKKUZeIUp8PUFGTmFjcVE7RH4lJDxQRDJAVG12JkRqTk40SXdlQiVZWEF7ciVE
OUJVNURIJEd0MHc1P0IKenF+LT1rWX1XdjN0RFc+ZlQhb21GbVIxNHs/LWFUeGVpUDVKdEFFPSp5
T2IhRE9mTGsodyZVJnRRaHwrY0xhLVphCnpPP3cpJkEpeVpPbE8xJS1GYSZ1PyNyUikqLT53cXtZ
ZFNKNUBNRFZvTk03RXUzd2FXRWJWVkFjNDlWeytJfVB2Owp6JFo4cnc9fGhFYmE0d1U8emZQVyFp
N2xKPSk5X345Y0wkP2lZMGJNM3Njb0spP3JwSCtRfm58WDJsNGRMYyF2UFoKejUoZDJoZTJ1MSpv
Zlk5MHZ6fi1fUlNBcU0yTDdYQStySWcwUFZZMG5BV0NFZGRpMnw5MXxnQCNoVz4qTVR0dV5eCnpW
bjw3TSF9ZWY9QzRXRGMtTmgrMjdnJTRzJVNeR0FDNEQ5d2BgTyNgaSomTHVHdmdhP2JiQ0smUCpI
QX12fk1wOwp6Q3drQz4xezdRTWpARH18KHpJUE0hMjUpQkElcmM+PlEkV0VVcTU/YDJ2Kip8OEAp
Y3U1Xj83R0xkd3R2Rns2RUEKejBCZHNVbUFnS2lTTl44I2UlPnx4UkgmaE12aFJhPiswRU1sITwh
TTlDRT83NCMtc0VvUTlNbVM5c0hCKnMtWn08Cnp8TUxLaGJuLVghPnZ+PV9xdUZaTXZ2O2RKZFZN
cilNKXNfKHEtY0owMTx6cEtSJWlkbGQ2YnN1dHNZMnJRaH41Zwp6KldIM2wyR1hBb21pdzFWKG52
bmJzdVZFJilFP2k3Q29jMz0jcz8yd3deTG82cn4yVTlUI29SMmMzPzZCbkhUPmQKej03QVVXUX0k
TmB0MTEmKT5udkwjeSF7O1R2XktEIVQ9aHVOPjIyUkcoazx9Uzk2eV80c1g3NCtuOUFuZTxRSEl0
CnpgIzZPTFkqdntpd0lKbjUxXjViJTxtOGVwSkFFSzVQUU80JnAxTkdFJkZTfWpjR1JkcCNTWT5e
Y3A4el5WflBxPgp6dmFpKEFkMy1CPjwtRiRxIVlfeHQ9Vilkcnh9X2JHbyNBXj5WaERKYG4rOzVW
ZlkxODM5QEFqeTRIOzJ7b3VhWnoKeitFMVVNQnB8aUNXTyh4JXc5SV91LTc0ay1QczhUQCM5THxt
LTY5eEpRQEV8fTF3YWomYVYqRD03QHxjSEJQWGh9Cno1TEtXNyElZiNDMHdOYnRxSDI5cGMyV0RR
WVIrPjVmaHNTfjtMMnAmZGRaYGIxOGtoMD4yQEcmI3lwXjJkRXlwfAp6SlNqRCNreG9jUWY5fm1I
TkpoKygyfihxJHNuMjlrSmxBKjJhcnMjaWZhR2F0UTQ3REBhPHMhTU9yYzRoaFYxK2QKeiNnYHNr
Zlp4NDVsV2ZMPVV8S09CO0NydksxJVNBKyMmUSV5e0FOSFN5Rzt+ckZBalVEcVIzOzRyfEpMKiM8
bX5kCnpIaThrVEpwIzJxbDQ/cT0yX1lVZzZzejkpVkNNZEVUMit5Vkl4NGlvJGE4JkVQPWA5Z1Ez
K1N1Nm1ReEReRm5gSgp6dnBrVCRaRFh5dEh9aFZ8S3tyTjhgfVFVaDshPlhqdG1aZVB7dUx2WVZB
cC05P2s4SHZZYXFge3FxPkJ6OWU/fFgKelItWjMyTW41RCokSmUjOTA7Wng9MChDMV48aWh5U28x
ZjQzSDlDSHRgcWl5NG9zeDQ+a15udVVLLVlRKXZ8PCFmCnpKOWNiUGohK1VgIXR3ZGxGVVcyP3xB
UXFtZyp+KkJnOG16NyNsLW0hbTg5XjY9ISF1ST83XmhMQnlIXnZKSD4tQwp6RStXV1YyX3FAOU5I
WCtATkN8dl4pMFB4VzBOQWNXM0hEKX1ZdTZwdlckVGUwXmNjJHlrK0l4KWlkKE9WZG5BcFUKelJA
T3c4Vyp6WWAhfFhKZV54ekBuMTd9RGc/YnNiN2NTbVM2ZEZgcWFGK2xMcUxLJDBvUlY8Q0NjOEsl
Mmt7eHhSCnpNM0IoPHZVPXQ2MDFgUEElMyktUmohPGktXnc9KGEyQiplR2A9QV5LUHskNnAqMFk8
TFVkNyRRUDVzRT42akE2Qwp6b3hEdlRXNygpNnBRPWE5T1FRWkBFP0M5aiV9V0ElX0ohYjNjOT9s
USE0YypYRGNKOXh1N3k3MXJkODA0aiZpS3kKem0pXzNQZF5SV2MrPkItQ3Bme31qRC18dWhpJUoj
Nzs2SFI5KFZ5WDZULWpMO3hgUkVVN3lCXil1cFhJPVc+Tz1wCnpkS1pgY0UyWFdIS15Wc2YwZGxu
NnYtbzk+aX5ecilaYTVTZm1IM3tpeXc5OTUyNi1MKj5LVjZqe2s3YTFPNiV9Ngp6by1wTDxhN0NG
LT5hdyNXVX0+QykhWF5XP2l6VklIQmU7bUhLZGljRG4pSz9zV2IzZV43KWJAQz5YRyZhYU08dkwK
el8kdjw5JE1mX1k5PkQ8cyNhaU91ZDJuaXVDJXE5aiorRjhHWnN8bUdefCZ3QGl2WT9jPGJRXjJu
aGhpSVg1WEJ6Cno3KTxGN2trV284dUMoP24oY2Mzbl5Ram4lR1gxUTcraEtHb1g+R2p3VGM8X0ZC
d0VDeF5oPGJJUDchfituSTdiSQp6I2p+QnYmKGs+a1NfTkFXZmROUk0+R0dOQGJGNUJBa3h6a3JB
bjFaRTxLTTVDSyZWRnx3bTR2YzYrQEJkZG9adG8KemlYaD8tOXw3VHd3JXlPQDhCMHQqdk13JH54
T2pLNkxeYz1jezN1ME1haHlYPFdkVG9PJmVIe2UpeC11WUxYcUoxCnooRn4+aChSNUthaVdoP1hf
OTFHbShQOVR0NE9qNyFnenNiXjQmQFhvQTZuSDtYXlpPRUZHUzgrYiNHPnFEdz9JXgp6dyQ4O3xA
PmlrZjx3MEBge154c1NMUWpzdEcoY09mITEoTWRWfWUwS2RTYDVqRTx7eHYhRytvP1ctRVM2NDFL
XmUKekl6I2FfMD9zeE1TMFFWbTx0S3VqNyZzMmJBaGpRJEdLJlFWQ0ghWiZtYDI5QkxBdVNUNEUk
ZihrSE5GZntRWCRMCnp4VzkjbFcqbWN9ZkdOS2k1UClkNWFgMDJqXnxFNCRwR2c2PEhnTTJjJCUk
NH4pemElZk5EZkFIVEB9ZDtHWSV4Kgp6cSF6dyVuWHs9Kj9JSzhHKDFWaEIjTyVfMEdYPE5TJjUt
eX5jVlMzY0RPZHQhSVRgPSo/e0E7ZXV9KEItS0ZDUzIKek1kK1liJlNGQE55SmVtPmtlX0dyPmJn
K3hzJj0+YjdAd0J1YXcqNUdWRXQ/dDc8b15ZOTU+TH1VMmdHVD1lRHFVCnp2ekxzYjAmQWtLejBM
cCh4JmlSVzRQT2xfZHFaVH1oOCtfQiE5XjJ2QHNmKXkzdFRSTFhGO2h+UVh7eXBOMDBwVgp6WHcl
akE2PnNfJDVudSlgKCtnfnxBeXdRRm00c0BXaGpsbEFqP35xQmZxS0Y9UzdIM2clOFZzSHh6fjEk
YHF+KT4Kej9ob35EIWAxfWs/Nmc3YFN5QU51bG55ZEBaTkA1WF5LPExSMEtAakhvN3BFRVRsWTtR
SnsmZjQwSVhJMCl7PTdrCnozIS08dEs7ZFcqY1FITlg2WSNuP1gqK3lAVGA8LVhFbkItJTlnJHhg
WCp4eytvUnFGK3B5bW15NGRaJDZjdlc/dgp6ZlFqfnpCYW0xTGxVYSF6c002U2Q3WnA0N1kkckxK
aD5xTFMrJEF2VSNCRCRpPnEzcE0ocH4tQmJmZkpYP3I1MmwKelQ2SzUyIy1zPkNLemRVPXopJmw9
cHRoIXRrbnVya217QkhnOTBwPDV1fDU8PUA7ZCpBIUtgOFJXaUhUIXZJSnYtCnpQVVFYSjE4QXB6
dm4pektgQ0BsR057I2tmUSp5UkljS1JEUCtZKFlpc1c7c0RNfGMkSi19b0NGUGg8Z2lCdDBnNAp6
Rnh9MGVkOVlCS0llaypJKEMyNER4OEh9alJRe2s9IWZyfGpQWjMhZDtoak41bncyQytXZFcybHZ0
UntmO0deN3oKeiZhejU0S353ZVBYWio7cjckTmI2aU1FdCU+M0BmO3lMS2U/IVFhaHVZTlBEZF9j
c3p9cjRjejFnV2o4Vj8zbnE8CnppS21BbUt4MHdgMjI0TWsjI1RQJDRyano3ajc8NnZycmp7K3ZC
ejRRMlQzfVZTcn1AZXZwcjtGQlJmZlRjZ1RwZQp6MExfcmo9b0pnVmhgPzs+M1YzUnBCWXU1fCZy
PTRtPz9nX2kweXVpNlZ5d1FkWnlzNnUxcGhze1hiJkFRIXZtTUsKekwoJUJgWXliM2NPQzNsLSNq
ZHA4e3F2TnUtRVpCa0RqbWVTKkw/bmZKWjg9dFMqQUJKP0VTZjRPUyRofD1ORngrCnpIIWVjeEQl
YUhMOFFlLURXNDlfUldaR09Se0ctM2UwNVIoWHshRGk4SXtaRkslb05EPT1UNHwyTCp8S0dFdH5N
Twp6T2NWKSMpNk1FcHg2JGJyWnBxRV9OSSVDJlheJUJ3byQkZylTVzBlPTJtMUFNWlYyc3hqTTAy
IThiY3dxcno9fVcKej9KUkNHNz5fTlNjMnQ2QGkrcCo2NFZZNlhnRVoyVWhabyszTGshPDdOcD5+
PW8jQXBCQSZ7QUtWVHpITmVMSnw8CnotO0xmKCN3azNEbzkyemU9RDlXTisjenVMO1RIbU5wJVpN
Oyh+NlYmbHdtYihXZ2kzWGR2aCo5MStvQn1NNWc3PAp6TjlfUW8/a3duP2h5JiV1WHRePVhHfSlX
M0xfUTcmIzQ+flhGXklsUjI8UTZtcEhrOE8xd1ZuZmRzT2gld3Q4Mn0KekVxWUt7OXFUMGk8NyYr
VF9BamNVQ2gqZHk5U3oyISVeeWBlaXk5T2JLcUk9c2pFYSo8XkgyYUFGLS1KOCNNQyRHCnomZ3Im
dlYzXmwqNjxrKkh0ezkkcUt7NTsrSDJQcE4/VEpueXt1U2QzPkMtWTtLVSFNVEdzUXRUQzI8eX1E
YitoKAp6N3FOLUx5ZElVITg2WjZhVGVpJiN5Nj81ckhqYjgjIUFDcX0zIzN7U3c4RHApQUJmQTxo
KjZVblVENUEjP2lrdHcKelRvU25AeCVTX2p4bHQ9MHRfISNNRXBRfjlLMyhhdSN4UFFERjM1O0g4
QyljS3E7Vj1DX2xqPmpoa2xPdlFAaFdhCnpZWnsxMj0qZD0wdzFEREklanYrJCRjKmM1KEhLSjc3
UGt8NyY3S3FTd3tSX0FZI2wodFRNVFF1NHVPWT9MbiNhOwp6ZTBEN3U3P3NQNXN2KmY1bzVsWm5f
bXxMQnQyNDFjTGRRe09pdCUyYll9WGUhaVEqVyt5bFMjOHImaEY8QztIejcKekgrMSh1LW1UV31u
TGlmXzZJYWZiYzZWOzhwTVIxYmlSQD5eYVAjLXdHZjRTKm8jWWdLTVlTS0RBSm5RUnRvb3pyCnpq
IWEkTkF5OHZBKHVwQFh7ZkkjQCR+T1AzOD52JkB3VnQkKHJZS09uPX13Y0k3SUJqIyp2NWI3PVBo
fFg7fTZITgp6NDFXTy09b01pTXQ1IVNmai1DXmFjQUY0WWMrK1coTVRucEV2VHdgam1jSkhLdzwo
O056T3M5ZllKKjtiWSVEZTAKemI/VGVxZUNuNkxvPUNqSiR+KX1+WWo9aG5xPW1qSGVER29hVy1y
O3toP3xQd2lyJDVubjRvS0dUI1FBQ1plXyUmCnpDfGd3ZnFoYy1PMXhMRVApKVgkeVpaWlFVNHhp
KT4yRjclP0Y9IT5zWXN5Sl8rdG1oQC1XMkxuQlYkciZMXyhTOwp6PGomQlp7JDNIKlFWd2YqaThI
d0hQQjkqRCtiK08zcDkkczYpfiFKJistJHM3bFRROTtLWCFZXm0kLTFaZHkjMXEKelQwP0peTTIk
TlhtVE5rK2xUNVctLUB+NX00MiY/SHB8RUdnIWR3KlF1K04+O2pxQ2JwJCZIfVFlQClMQkx5T1h0
CnpNeE1CTGNCOGhMPGo2MjdPQmJsVW9IRnQ5Q0tRKGw0Zk51WU52bn1JRGlEWjJ1RCtje0lfJWF7
PCoyK2BMYUp0dQp6eC08TDxIdzNvXnZoPnBxUkx3R2A4MntxZFE5SkhEPn1QbFh7UyVYfDhEc2RQ
aVE5fihfcnY7O0g+VkhXQjk9fWwKekNmPW88Xi1uQ1p1R3EtQlApNWgrd319NFMpem4qVEF9X0Fk
SSlxTlFSfEtRXm5qfGVGZ2BmPzJRM1QlZ3A8M0NqCnpfX09eN0tRJH1ZcE8lWSp7JDAoPFBPYnlo
NDsxa0sja04/Ynl8TFladF8mMip3VjBXYUI1Sl40SENvOHZMZEApcwp6NzQyP1FhJlBnakU/WWhW
UzNPczg1PHlzQSlGPShTKGI0NlU+eSheaXtPSjUrdkpILUpkbjNPTzY5YlZWMWkmR2IKekFNI2cx
VXAtdCVMRCMpOWpDQW1hXiUyQVUra15AOXpld2FoaFJIbDhUOTtoNFNXWndvcXRsc2tkZyQ/QGBi
IXUyCnpUMFhjTXRAKXo9bHkjNmB7QUx7eEBZQ04/eDh3aX1qfSNiPWx6PipUVilael5zaVNmRS1Q
IzduUkBIY0JMSn1BTwp6ST9iMWYqezJDez9RZ2g9d2Yzd148WnVLPGRrJT4wcyh7dEpAJWB2YUdg
bH5pcX5VUllZX0Q8YFYoRXFEc3xvTFoKemgrNlMhPTlpUjhQZFU4K0g5c1A2VipmIWxyciE7RjxH
NTVYb1khPHVzby1BcGMtVndHO2o5dT1CWFhpZDM7JiV9CnomYm4yNTR9e3NGYT0oOWxgWXVrc05I
fW5hbn5VZTtgK35kOWNSYCEtVUM3PnxoVDdsejVyTXEpNHRQYUAyeFYhIQp6Sm5kIU9tV2xZfj4p
WSlCQUY0MVZOZ01FfDxgdnZnbmJkV0lqKjx4PTIjWn1qblMtSiZoNDE/fVchSSEjIXE8QVUKelA8
Ym91bChhcWJBbnlzMGMmSmdEe29WRmtjJkk2P0BsVT5aKCFgVGtTZmx7QnViYk5BPXg1dWZIczEm
TEVeQndzCnpHPEgxUHFPZlFjYG9OKDBWKEplPlphRHdwYSlaMW5NTUFHV3FhQmxSJD0yJGgheHhX
TUhMYTkxNExnJiRuck1sJQp6dUU7TS1ZTFUze1VveW04YHZ0O3NSUGgzcnF1eDJNNU05I3JMZT1u
VU9OSU5QayV5Kkx7Wip3QCUkbFBJR205JlIKentWOE9wZHxNamNORDAwNiRaQiNCTyFiazhUQndG
c3I0MmtZTEVzaykzIUk2YCRwZnJ8Pml5KWkoSFRgOzkwY257CnpCYk12JjktRV8+YSs2bnU7YV5K
S15+NGp5PDg+VWF0dyZiZ01oOT97KWpNeGRJeVdnI0x6O3ZOWXE0RyE8U2RZQgp6Q2d9dGdUVUkt
YTwjMipAZSh7RD1tOHhULXpmQ1ZXSXw0OyhPOFR8QHp2PFFSYFRjSUBXQGRmV00hYTEwVW8zUU4K
ek1FPTBgO289bnhHeHgzU2lMRHdlMmd4OE81QXEpdmEkQSFyYnxMOEAycmZvJD4mVGY4I0gtNF40
eTxFMW1TSjhpCnpNNSEwZSFzRX1MT0x2RUVKSlZ2MihnZSl1ITwjJDN6KW09MlBLcGZ9emtiP3E3
ZDFMKE5KKj19THs5MmVvdlFHdAp6bnI3VH1NSjkrcW5hYXZLK29mfWc2NjlObUt4QWd1N2F3TylS
YnFZVHM/WVlFMyo9VkRpI31UM1U3fm1hI2wzUUcKejs+NVNOIzlFbmI8aW1ZQzB0RjN+JWxQfEBs
dlk2M18hQ3BKSnhKOCFiSmNnS1AzMFJ9dSR3QDtIRTxUP3FxKld3CnomaVpoKik4bippeFNFYFQ/
QDtecVhOQ0MwTTtfYTc2S3JaNml5Q343WmxOYiVCUiMhdHJGMlojcVM5dDdSQXxzTgp6NF8jZU9F
Pk5eUitzU29pOTclcGRXSEtJVmJzfXclVFh+UnVZanQpKkNNQ0s+X0goOzQ0P2Q+U0p7VjtvYHtR
MjQKeiNiNzdWYFVZRU1BUElKSD1IOCYqXyFiQmNmOXctXkBebUdmezEqd3ZXfHNOUXRJV2toNkgt
JnFnelJhPHJDaEB9Cno/Q012UT4zKTVxTjReajlKRUN4KDhzTjUhWlQ9KUBodmMyKWpaLTRSbzlS
aXlgeCUtaXZ2NkZ0VSF7SiUkailwbwp6c24yfDFINXpGN1BSPX1gbUNEcjtnd29HSk97MnQ/RU1C
fjhBPXsoMGdzQz59PV44TlV4QHgqVS1aOEt5c3pxJDMKellsT2Y2dVoraFNxcUpmP2lYTlM0YDUt
SjlzdSF4cllRV1UwQH10aH1WXjtjdyNoMW9KJSNZWW44VSg1R14xKUpnCnolO1I7TUBySXV8TTIk
SFRHezBKWHM8eUYqWDBiNE1pe1oyQmNlbVVtQ3wwaWxVOSl3O3EoR2ZvJH14PzQqWDhzUwp6cjIm
Yj95eC08VFV1dSVGPSpvRkhGNypDZGZCZHdGXlRwQCl6ZSZxRTgxaWImVENwO1gxfTtmXkw9c2dr
JntVZUEKemlYNU8pOXp2R0FFUWt2aXtmRn1CVCppfUJOXiZ+QytKc2pQXk5MIzJOUz87T3RmRXMz
Kzg5anlwST19Pyp0WkZiCnpLQ1QpcnNUIXtpS1g7fT1abFE3ZzRENXV4P3FJZHZkQz45PWRLMT5n
dUlmJGY0bmcpUF5pLWxGRypgTXVRPXh9awp6MFd0OURGXmE7QjtxNWVNU2xVdXQ8cloqJUlRQSNi
UUluUjNoPEBne19OWWBlSDdhRHJKVitRJnNLaUo3dTJaPFoKejFgT0w/TGBFMnRoI09xY05td3xU
JCUlKyptLVdXM1dvMzBTU3slR3U7KlVpXiFgQjlETUdofW4pdkUoPF8pPXUqCnpsc3xqTlpwYDFp
REVKYko2ZmdAcCVfTEBzJk8mWHVVOXFkWk1oV0g7YElrcUYzJmNTRmYxYEl8THZCKGx1eGBxbAp6
d09rKkZnXks7RHVMUEZrVnxHeWhRYURrWmo1dzU1b0tVJiF3QFlKdmFtOUJVeVo9M2djRWBRNCFA
Tj8hLUxediMKejsyS2p+KlN7U3VIOzdEcHxJdlpxeDBPd3lsejlAaCMqYmh3azQkdGlgbzAzbnA+
NF9gPXd+cUhDcDhBJjJ0QmZSCnp5ZlRafj1ubTxLVSg+PFZDRm5KUntNdXA3Yj9zMyQxPUoqQjc4
IXk2YXMjMT5BcTB8WE4mMWc7NndEN2RGNGtadQp6bEFBayQybllDbiF7eS1Hc1BMSk9wKnZ7ZDNE
eHJCVykqQG5ySjstIzJ+Uz1sTDBYWCZHZyliOFd9YTBKeU5ZIWcKemcyeHVid0t5VUMxLTYhZCpe
NjFaSmFIPUFXc2VyZzAwd3JfJD5Ec303emlKeUBAMUNtaUFSSiZrN2xmQk1fTUF7CnoxPz94ZT9M
VXZhOHc7T31sITF3Y2J7ZVM4bkomSiVjWkFDJUJ4Nzg8enheKTx0d3s0P0l0M0dheGlVaXpSYyUt
Swp6JlAtaHxfUHlYbjFnSSU1cW1fMEZlWTF4dXFiJX53cUcjSHhYfn0yXjdqXmB0Z3t6JUkxPz9f
QkQ8O09MVXtQaFIKenVoZih+eUA4cVJgaHdrQ144MWZFM0VANHx7fDItPzZDazVVSmp2NzUjPT9E
QUdvVTZ+dTlOYiZSbnchTDV1Qn0pCnpjJCo4TVJ1dlBKPTduKHtQaFJFa3IxRjwkRXhEZTFmbCE7
LVRweGYjKnVZYHRUTVU0bmprMlh2JCgqSCsze2x3SAp6JSEqPnYhPWExdSEqJWglcEk0KmRHKGg0
KCRob1VmKENzXzdMR0tBc3JLPH12OyYzVHxxNCU1TlVkPUsjbWQ/eDQKemhjRE8oRW5VNEFZcUBI
ZXpjeEBYXjBaKVZKdnklYENPb0VfRlZUZGJoO3FzWmVKdilqSCRFPSpMZF5qQ0heYnI1Cno3Qnko
e2s9ZDklWUw/Y0YrTDVwSFFRQDU4dm9+ayFHTjNUR1R6YkAmcWk9OVc8KytYU1YtTjhTJmtOKytB
SGdJPgp6VVM9X0pSVSRYODY5PF9Kc0E4NmlrTnUyLU4/dUlIKWxuP2U9OXVfcS1OMW5kdVg3cllM
XjQwR1Z1bzI2YjBuKigKejxpS3U8R3F7MyNIen1XJE9NPkVqP3x4aEQxQ3IzaGd0dlIzSVhRIzEk
UlJIa2c3dDNeaDBza0c4WE5AZmA2PnAmCnpjU3RNSU5aSk9FX31gem1FJlRHJjk8NVJ7UWJHIW4o
VlUwV0lufkxGZEs2emoyYylnSkk/PXd6PndhQnp6ZiQzZQp6SWFEY1VMQHEhZilQQCM+T2laWWlR
K35eanY4QFlecEMqKVIhXjg8U2M4I0lIYUB3KSE+d3NkdHl6WFBnaCRxeHMKel5keFg5bT59VU40
TXJCSzJ9PXdXLUZQSXBaNElXZTYoVSpFblpHflVucC1pMHF3eXI3dDZxP2wmMUxpSjMpcSEtCno2
MD0+QzUwMCZLJTJSI2xuWXFrcEVMPW1DNkUqI1E/UWV1Vl5NR012JUVIV2pFKWwyWjhtUTsjaVI0
U2FeSW1fLQp6REk4cCE2NFp7MlJ2dDUobDN6N205JHpiMyE+YFhEdkp6eHA4QUxHYGBQNGBEc1pV
Z2xVZ21jfnd0SyNzRmoxVFEKend3ZS0yUmZ0KzU1U0V3UHBYUWV3QWNrJmE3ZypENTY7X0IwPU5q
fFRINXAzQm5RSm5lVzslP2FkZGpuNkA1YDxiCnprfGl8OyQxQWI0QiRKYmU+KXI5KHZAOH5wNFM9
fjRwa01iQFprJmpSUX4yfUU3PTl0Rl44VVBldE0qcU11Zlo+awp6XjQ4fVRnISlBel9OdTg5ZT5q
SXtFVip5dGlUeWtqR2Nna3NyQVRaNFYqaSN1JTw9RV93NWVmZFRCIV4jViYkXjcKelZPbWE7KHpX
VDlodSMpfGpAam1mcERDRV5iVkJXMUgzT3tAKXBxdGpgRnc+bDI7dTdLandFMlE9UGJLSU9zc19j
CnpDdkF5MUpLWmhQVTEzJkBBO1paJSF7MTM3Xl4zLXhFKmxrRCVBUVJBczIqME1DPmdYZj5PKDVP
TCg0X1Q1PEV+dQp6SD53MXF2MiViJmdGNShEZnB1WCtTQ0ItRjkxTjJ1SlBpamVaaUNWMCZ5MU5B
ek5zKiZCJHlYb1RIekN8MytkPVAKeiFUQnU3ZlolV01LVH1QMEl3RX50UWA5cVpmZyg+MmRhMjt8
PjYhR0NnKWljNWsqKlIqOUVzTlg4ZT85N0VVQlByCnp3U3d3bypmNnNnQDlyWSU5XnxeY2BsLS1U
O1BUWXoyc3BZRil5ey0lJEB8Z0MkIzYjeVFHUXU3bVU5YlZRZyhPYAp6YnJNTlI1P2AqPCokaSpI
WGJsIXdtPWs3NjE9MkZvJUFqZm1mY0BpZ14qUio3aUVxZzRWM31sIWFfT2BHITZOJlIKejU/I09E
YzU4NGowNFFPYko4aTYwLW5eZ1R6O0RmK0tFb0BhMVRDekx2RXRza2JURTB5ODBSY0l0MnlOPGl3
ZjZMCnpqdEl3QjZNM29eWD53ZmhWQEN+aHJhSGVHcWEofUhXdEdeNlYyfXpKNihwN00pe0VVc3lA
VSR+ZkhDfDJ0al44ZQp6e055TFc/KXJVbEhPQUMkUzl4QHZ7LThuaGdGeTB2RWlsYnJUaTJDcmMy
PjtVbV9BVnxpe2VjenJ6S1ItZ0ZldzUKeih3PjdmTGpYb2BfclhKYmZpfXREZzZrJjVFKyZsRmIt
bE1xJlE3Mjt1Y3IhR2c0dl5jXzZMPDZod1QzPSZwYnI2Cnp5YXFoWXMrcVZTcV9BO2hEUU18QEU1
MV5LbWJqUHBQXlM/THZBdilENytVRGtYOE13ODMmQmQxMTttSS1WeUZFTAp6eypIRXorLXVnMFVI
fm9VMzx3WDBIfTRLY0spWFBPe2NNQD1CdGJANT1VbG43YD0kSzc8MG5WQmA/ZGxvJklXVGMKeml8
NHp2bCR5antKJXhWVGB8QkdkNX0xJUpOcXR0NSl4TihAKnl5TlZtfj1mRjFTTjRXR0YtQE9BV31p
VihGaGM7CnpSbmB2PTFkeUNvR3lNaUU2TWImS0VsTGRwOW1LQmxIVGJQTHFoSUBjPClXNzZQcWFS
JnJJWCtzT2oxTlZScTZ4Nwp6I3FMaUN2QTNLaVQrfXgtJkJedn0+Y1daVUVKY1FnK2N8SihiRnt0
SVVlSmQxb2FUbFFQYjd5UXg9I3dkemhud0gKemNOKW1QK0ptOVIkVGlBTGIkKVlZNms/Wn5ad3Rr
ckA4MipOayQ3PyFsJHFOMForU1lHPWpWU2slcFUrbWJNKFUtCnpiZWI5KFQkaGgqezhnRShnXiZY
JXdCYVJqNFhoUl9nbDtCbWEoKGFSe3d9fm4lWkQtMCh2cFgmVSZvPXtBOHdedQp6V2pYN2hlakxl
VlpqLXRCRVdmfDAlUFQ3YDZIaDk2THApSmBDUTkhY2BQRD91Pk4lSy0+YHhoUEJ2THtNWUdKWUMK
elBtZGZYK0hhT0BhPlhlOEBpKHU9YTlQYl9CPzkqWDteKyVPWSNyfWxNMytBfFB4QU8wVmtobCZU
fnE3cEwzUUcmCnptcih0azdvTUE1QDZvcih5fEdhKVdzYSFBdlRyIW9rZ0pmQiU+fHhFMXp6cUpr
NUBOTj08Z0sqOyVvLTdgJD9SfQp6JGBXPG5jN3d0S1VzYCFAS3ZPRlpTVkQhPk5zKj5ra3UyaENZ
aXF7d3c1WFRSO1EhPHA8K2trSXR3KlpxT19eP2gKekc3fHlDRl42Q2xyd05rT0NjRSM1YnVRPktL
VEtTd1FvQ1kpKkB5N2JDemMlNVduIyVsKzw4TGNBWnptTmRjcVZFCnpDbTghK2NxZyFRQShSQ28j
V0BsQHREbjhfemZWN3lsLSl8JnB4TH00PDRkMytsZEJlbUclTjVzYGtXUmltdV5pdgp6ZS1zVSlT
PkE7Z0QqOTI/eW5UJXxtTUt0OFVGQk53M3RJR3k4WkoyMD9oQj5IKm1LfHxTeFlBNzE/IUlScVl9
TC0KejYxQHZZKlh2KlBfNGpWTFQmODRZOWZ2YyNWRGRAY292Yj0xQyNVX19ufjlmeTlOJTcrWSVH
Qz9gSmZPUUVgVklFCnpJO0g2UVlyfWkxLU9qJGx3cVQ8JihAcUZYb1E8JFhjc05GSWNaSW1gVC0t
KDFkKj99IzdFWWx9RWpoT1d4M2p1aAp6aWNaLSpBP1dHPTxUNiVVTEBFXj5lcSQ1aUQ+XkcjentX
TTIhblNoem94fWZwRWxsZkBoZ2N6XyomVzxASk0qY2oKellkPUdgRF98c0hBbUF2KWRfI1Y5Qyoy
P2BKWiZJfkBXRDc+K3lWNFpSJGpGezJ5XzJUZiZUZitjdUJJPmBJJDU1Cno7M1V4TjFRY2o5bklv
MXpANWM9NDhrK3FaP2pITWViMT1sd3dRY1NFeC1aYj5gJD4zOytfaGRUOEZvJHp5Vjs/LQp6PDI+
N1kmMzhmZjw+aDdDS3A/aUAhQUNTS096X31XTmw5MX52YDI+bSs5Pms/cDt9OWpwd3FuOWp7Rj4t
MkpVJE4KelFYUjAtQHYhekhAYj5tKjVzbCo/MTBIZjA2bStPT0swNEFRdG14UTtsWWt0PkxGaSs1
Mkp3TikrLUlNfmdqcG9OCnpuOyV3bkp8OTE8MTFBR092a00jNV80OF4kX1lRRjZsUi0qeU0tfWRe
Ql8jXjtSbUx3SGZ6SzUwa2ZQdEBlRWQlOwp6PX1FO2pxUGskei10TGIzNDJPLVUlI0dLNVhZWSZr
TGB7LSVqWlVAaDlVKjlRZlgpNzd1NCZoMUZ4dlZ7QT9VcUYKenFKUjJkNmgkIXVGSmJxOVcoRFhu
MW9aTnB0WlUtZ21xN1EpaXpVZ0Y4ayhGMGh3SV50TDcocjlUbjkkS3k+NE1TCnorbDdQdl9DamhA
NHB2dzc5bVhaelcqMCEwI1I2ez1iM14yOStnRnN4RzQyIUZFWjs/UUkmY29NcG5AZz9wNE8wNwp6
Y1Jfd0VffV5yMXY9MTFGUkV7MWkoOHlIN2MlTWBAdkEtLTFpQz1rN2lyJDwkTD1FNSQrSmM2fGhZ
fmp7OGReSSMKenZYZmNqLW5TVVV1aV9zfXl3Xk5BSTF4QD5rK3lCd3JpbH5xS0p9SllgUilBJj5l
cm9zZkI7e0gzSHdVRT9ObjRUCnp3czdlemNRcUMjS1ItV3ZoeHNmPmk9cCR8MjtvZT8rdm5OfCZ9
TkN0P0d6WC04MnIlcigyQEZqWVNaO3Q/cW1wQAp6V1lTZih0KCtCdWU7ZiVhWDtDNnpwb1gjdl4k
OFk9SUFpWjRZbVMlOGgwYzVMdUlMQDIqeHVvO2c7Xm5jVWV1N1IKemFGMzRISj41WHQqK0VzJT5j
WWF0KkdodVFoUTIxRTgoeDc0Z1lzWlg/Vko2KEI7OU99OFBoZWRtJnh9TUUmSEYtCnpDVj5pME01
ND4/RT52cTBjfVhQZ0pGelBnY2tAamhQdTJ7JVpyNTFDWk5kYSpTPykxSUtCRDhIP2ohb2Z0IS1f
Rgp6KzVYcE02a1MoPzA+KWtrWWhCTyVMfDV2Y2liMF5VLUJsbmgkdVF3e0pIJklyXytodiYmZmpH
eWMwS2gmNnJIUlEKejRmUGJ5dEVnQmBwUFhXN2I7RXBGV28zKzkpUTFpQ2RtKT9tci0hY2g0aUhQ
fkM/e01ZTURKX0pBTmgzdjR2S1UwCnptZysoXj0oT2hIZTcpbWsrb0RGMVkkJTItTklLdVljWno0
ISZTLVI3Uj5jaGM/Q2d4eT0rOTxWcVBvfiFgTnFxLQp6Y1BHelIoaEpTWjZaSnR5Kyohcj4mJDhV
azBWZzY9ezxxVSU4eXlZe0lWXyl3RUlNX3t4M1dtTjsxSEMqRjVFb1MKekdvczNwNm5JYkFSKnFR
Sik7QUhCTVNXbXZ6cEl+QmRtbnMlPilMbzdOIXd7SHVGcldfT21sK09xT0chcGFjZCNWCnplY2Zl
SFpAWmglLVQzMnEoJiFOTzxBKWtZPlpvdWViKFRBMGsmeiMlaC0jV3NefmtJZHVXVG1mYiVDNiRM
blRUZAp6YGdkcylWRyQ3dXtaQH5xSU1kaGRoSztBMClYck8lQX16YnUoK1pyeGtSfDRuXypWZTVA
NnkzKDEtTzJiO3x8XmEKej4rJDtmTS1HK2BROHFmdiQmTVcrTGsyNkhARllreWowa3l5LXhTbT8o
a25UWmN1Mjh7cjtEU1hLRl8+KEdXKm9lCno2SWwqaGFxciRkODdMP1deKzdrJj8wJEZyOFQ1S3I0
Y1pnOFJBQ3g8aWIxIXBRK353dytEN3MoRWZheHI1UFFoPQp6ZTIzIXdAZmVCUj1XQEhWNkxOIXlo
JldsTEdnfEpAO0hROHUqWTZ0TGZRYl9wOV98MHpRcnN4Y012RWp3UnlaIyYKelhePT0yOCRRJXJr
dzI0bztzN25Qd1k4TnpMIWtOfnNLSF5mPiFkRkM/UjF8S3hva2Y2LSNMK2RCQ3poaEh9ZWRVCnpH
YkxhUUsjMkBuei1hJCswRD5HbUhMWkVBbHNUPlZzV1lYcjM/K3tpU3dtWXRsKmttO1QqKTV2UExe
ZWQhRCFoeAp6NFR3MWIoPEVyWlQ5S18+dEAhWCNBblpgTUM7IWVTNE1zOzZ7T2RfSiFeWWkrUUkw
UEVuK3dTSyNXfmM9JUtDODUKem59JTBGRj4xc091OEhPZzJ7PVpxKk1YT2t0a2w1KnBGWkU2KU9C
PXBuQiZWcW59M1h9R2gzY3AjYnk9aEUkTlY5CnozNGkxcCk+PGptZTt2O3QoSFE7ODw0UUl9T1VK
eHB5UExEMGJUfkFfRHk9fitUYFMwV28jOEpQWiZPQjtZNHJnbwp6LVhud2EwS1E5TCt5YW18RWpa
e3tvRXY2PyR4VXk1JTBVVjNnI1ExQT12bm1GY1Jse1UhNEsjdzJHQ1kqZlJkYj0KS1k/WldHQGMj
a2JjYEJSJAoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9zdGVh
bS9lY2xpcHNlX2xvZ28ucG5nIGIvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlX2xvZ28ucG5nCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAuLjM1ZGRhZjY5NzZhNzUyODRiOTMyZWUwNzIxZjFiYjMwZjU4ODE3NmEKR0lUIGJpbmFy
eSBwYXRjaApsaXRlcmFsIDEwMjA4CnpjbWVIdFgqZ1QkKlk4SDMobXV2Jil2UFY1Qz80fHx3NXE3
MD05IX1BbEE1TylJeV9WckhQQGBCQVM1KmVIS2xDfgp6RWsjN2tRJWo4emJFcUtSb3UyRHwmZ2Jf
IUFJfHlrLXEpNGZXYmI/THdTSEBALSYqKERKTnwqODQlMno9XjhmJWEKej5GTTR2MFJURSgwSEQh
aUkxQnl+RHtmWl5QVW9LSlNfYzNDR2x1JTE+NDg9fTApT05SKVYyeVZnfU1jWElRaEUqCnpBdDUx
PnAxJDR6RT4ySGVDODdUQXhmXlFTMEJ7QSt5S35EZEc+PHFGQC0lfXFiR20pTnI3Uks9Y1pUNnkj
N2hiTgp6MlgtO2Q/cn1DSyQle0g4dm12JXFNYEt9QT8/PiV6O3E1Z2VFdlJQcmI5MSYhM19NJntT
PjB9UE9kTTRjNHM7fjEKek5zRi1sXlJyaHUzP2poN2V8QD1TQVkpTEVwSmhJUSg5K1N2IU51am0w
MTVfTlgmc0BYJllJOSRTN15YRkNTSEA0CnpgYWs9I0d0fXVpP0skZG58STd2SV5vfkpASXttezJZ
N0dEbnVmMyZDcFlIdDZMTWpnYjlkS1kmKDg9WW1VTkxsYQp6Yj4wdll5TjYpTjshVjt6P0hfbSRz
Zz1mXiVaPG01MyEmJHI2TH47UCRHQE9PXzl8WmZSJH1fVGc4YVRtO1Z6VzcKejV8a2x9M3JwK09y
V25ocElaUWxfYGJObTtBKCs7KUp4SDVfRXlYeDBTaWEwbGt3bEdgcmNRY2dTZWpMPWYxPTRxCnom
c3QzfGhkPChzOWckKUpTWXRzYFlCcyVve1RrUDRUcHx5aDdScHowWmE5MVd4X0ozZSQ7PDE9OUMj
SX48NiV9fgp6Q1Nxc19jZmtqI1QqT0NgN2xWNFA/fWY2bHZBc0BDRmghP2RCcERINSkjK3dGQXYl
P0hXIUNDflBrMEA8ZkZofDYKeitJUEZSakdoMjdQJDN4XmxnbWNBbTRDemZhVzk9UD43JjJXaD8q
I3lVYV5MIUpxblEpRWs9YnxtcHZuY3ZmR3wqCnpCPEM+WCtCLU8oMUYlZT5XU152U1JoJnpHbTMl
c3VeOFBXZVdPNnU2KDchYjloXlNjPDRpQUVNSTg0QD8pNyNgIQp6XlJvam5sN2dUWT5VNm8pdU83
KTdqbnBqTFJzOGhpbEchSV9MN314Py1kPzJqMGZUVS0wfWYmWnlmT1NmMDNAOVEKejllZD9NWllo
dTM7ODZaJGA+Sk97ZW1rNHZCR0ZGcVViKHJYPyptZEtTUjFOcHp0SVlFOVJUSlM2NkMtJkQtbWYl
CnpjJlV6dkdPfnpwVW5AJHA7M1RaLXBrZHs2NFYpRENgTDZ1JEhqODhpNVh+UXE3bDB6dTd3bD1J
JkkyZWVwNTVxZQp6XnBXcGpAYTIwUUczdylKUXd7cnIlR2NiNFlKTjUjIyNiOCo4a0pXY3JoPior
bXNnVVlfSn4oNFhBYyNZI2oqSX0KensyPSlqWihAJilQMFFkSzh4NjMrWDZILX5jKH50amUobGh7
OW1nJT5Scj1JJXNuNkUjSV85NmYtVkw+ck0/P3s/CnpVO1prOUNNT2pOcE4/RXZ6Mnc9enhhbkFm
U3RIOW40X31MdEwza24zd21mPWNgVmxEPDBRUXU/cGYwKSpYUFI2UAp6Uk1gPSpFeGZaU28qNlJi
YDtGbFN5NCsrZVk4JGNSNGdWd00hZ0VkOTc8SXxkaT0oITR0PTRIcSVHUj82aHZ6UzUKei1qaXVT
NnlNMmBpbTwpWkhZNSVkdjBReCVlKDVLXzklPnlzKSlhJnBxPWJ5entZJVZDaHw5Kk4mVHtQT0hl
IylQCno4VmNmVzMpKigyPFpSRk5tQVNFKl9zYGdTelNUUm96c1UqTGl7JjZybHUhOSplZFNAV2Y/
TlpEOXpNYGFrPVUpQAp6TFhufUVYaS11Myh6ZD5fejYkVFJrNSoyS15JTCl6RkJ+JD9HWFBre2k1
aCtZYz1GV3NQUzt3MHBSZFd6QDFkUWcKenMwamBvSUxrI3NgNlU1WDlVdytNaypiQno+PntvPjBY
YlU0NCpTfGwqNXtIQk5AZXReUjQ/ak5rNCFqRjB3WE1wCnozVWxQMGJXQ05JUU0qLTFHNWF0M19E
WXt5dkF2bnM/UTdTNE1uWXw9bTtpa3NgQylhQXFrMjdhR0FBOU1rPyglPAp6TlBsJFdBIWtkI05W
Rk49JUtaPCo9bEAqbWxlVj5CKDh2Y3I4QWRHYHA+Sj1VSUxaMzZIdG0pVCEpeDBCdXAkcCkKeiE0
Uk18ZV87PjFfbU9ZaiEkM1BlM2hudUVXUHR8MiFkWjB6KjZ3Tk14Qn5UNndKc0lHJCp2U0JSJXxx
cV42RWZeCno3V207IVVGeT01U1dzMFBVckMoVGpva35TKiFXYWRlaDYwc2ZOKHoweWtFQFIwYHEo
WVdYclU4RlVnT3RlVV5hTgp6QFVzOWg0antZN3sxWV5vSzc1aCozajV3cWg+THRrOT5qay07LWRq
ckZNXk9lY35DeVImKFV+VChaUjJpVGc5PzYKenJ+TWEpNWp+KX0zSHF6JXlJTVZScGBSPj9xJEk8
KmBiXj91Tyg4ODFRJCY/VCl9NHZCSmcrbUkqe2A3O1ZYe2VfCnpiTnZIQDdubjkpVyh6RmNDJGoz
S3pTbjYpNz1RWTQzfVA2azF6d0YpODZ2MmttUCF0S1JVJjRURmVeNmdNMF40Twp6RjlFOWJVOzcw
YExTNn1DLWZ8R1hTP1lnK3srfWF2P3dZLUVKSyFscl9NfFhzQSZFMD9lLTFIRjdqLXQoLXxjZlUK
empaPlBtYn1SYHBGWigwNyRDYkNobUhUISVrVUF9MUpzaSlgamBidURORSVAM3kyQUx6PT5HNyMt
eG5oeE5zSmg1CnotT2U/QWNSSnVvSXUtaH0xS2pgSWA4OzNvWkZ5dyFvK09lRUQxdVlmcSFTX1dq
OSpROXF6ZjAqd2B5a3dWb0VlWQp6TVA0UU4tfVVlfTM2RTFzV3NHI19uOFF0d3VneFowMjUkMyFm
TGA/dHpaV34qSUVvJSVOZCkhanNGckxCWjB6e3oKelJ2JTZhZHtQOCt1STRMTShWJj5wQnRJYnhI
aV8mZHRePjtPaXo+cj5fd359aDU9JUpITW59MTg1KFZKaHUoenFGCnpeS2omMXVPPG1xN0lvWj5A
X2pgRXtIVU93e2x6WGdQTnJvMzteWCt1ODc1VGJ6KiNgXjIzNShJT3p7UzlHMzc9Mgp6UGM2Zjlz
YDxkSHUhOHdvbFl4Z2pqWi1kM05RPFA3JXFSaGtwR3d1d3NkRDNNaz40WHVsTlZ6eXRCKmxyVG14
fnYKelpTX1gqdyNrLW9od19VdnpeNVVRVzNJZ0hRcCYlekBieFlKIWpgb3ZGOTJNOTEtY2IwMmpM
OV53fmg/cyQ5M2pFCnpOTH5hWmg0bzdAaz9sTihQVT13YkFzXmBVRCUxPHdZPUk2VytXb1UzNyRu
ISp0Vz1iJEtYM2pHdTJySm1xTHltMQp6bW0/OTdUTU4zVzdYK3N7M18pYyl7d09uWSlDUyk3QTRh
QzZyMjBTd2E1M0FUI1kzQ3NBQ3l3QkdSNDE2bntsZlQKelIwal8qe1c7TH5RUGhLMUZaTFNJKDZ6
YXdoOEsqMHdeWXwtbT5SS1NtckcqNEpOI2lLUkpgWHVoPF4hSTlSMjJnCno9NlFGRFAtNDc2cWtv
JXZkOyZNa200LWloc0xgTyReQUtLaXIjTnh1V1dWIVc0Mj97NkI3eVoxXmQoaHlPWURQXgp6MFM+
UXNJcGFvYjNZMDIoJnwhWXBvQ0JAelpMZmAwbDZpRWFkanRQbE53V1N3cDUpZ0R6WHg5SHlHS3Ey
ZXJ9VEgKemgqZFFObDxPLU0rfEMrPVdTWW5pN0gqeGAoZzQlP1lXfntJcUdacX5zOFk9NTlJTXlC
bTA5Skk5JnZKV3I0Pm1fCno+djAlT0Q0dD09Xlo7VFc9enkydHZ+bj0jbH1vWllieT1DO2BeO2ZE
cmcmJFAmbXRMd3t3eV5acExIJCVvOE8obgp6eGNhNXh2OWZoUExQejs5PDI+Tj40QmJ6Mmg0RkRF
KCMqbCQ5MUhyZnU8QUBzdUcqKEI9UDxjNVpsO2wreWgpczMKeih4UTYleVU+IXltUktjfi1gb0Eh
JUdGbn5TfnktYHhERWdXdmoyJWVwMGRfb2lmPSRDYGlnekdhd29xeGIjNylyCnpHSXh6RzNmfVhk
Yk05b3JeYT9GNihJPUw/STFyaFVkR2U7cUdgOEB1PHMwdGlIZkc/PFM8ckEhemJlMHwxI3k0Pwp6
Izdsb3U1dGhjeGkoPXcxWmZScCtheVNiVkBsY18tc303ZU8lOSRMUFc3bXRfSkZVQ150dj9rJTw4
MWUrXzxWYiEKek1LWUsrQEJTZWxrLXdYUUtfblNuVFV7RWl4Umlwbz5OcGRwJmxJJSpwXmJTJF5A
VnFiNj9NOHtCPjd0bEQtWSEpCnp6SChONlBPMFRFOyt9TjczIzxCTWBvSHdQT0ZkNm8yK3xDN2Yl
IWVzXmBCVExqfSs8RSlvJmUwYjFmdXxGJm8odgp6NG1iZjszdSs4JDZgRVpsVXx0cytaZmVVZ2Rm
djZHXjZsa3gtN2JBRV43JHZPO19EZnJNYGVCWk1MPzZ+ND08ZXIKejR+RVBDWlU9cShycE9Ffnk0
MDxeJXYjMCRoVHIoKDdBMTk0ZnczJGIkYSRiQmp2QzxRdU9XJXkmWm11clZCQjQ4CnpiczgzXnlE
bVBsKzg4e31EbE9IQi1telVYVFI1PSMtKURESTk4IUBJaTZmdl5LZUVmclY3QWQqR1dKOHZuSDJS
cgp6UURhZj1VI359ZCVqcW5WWEBRa25SRzZmWll9b3cyI0xicz9NWGgtR2p6YkB0NzRyfHxsciEr
NElpN1BaQ1hNQmQKejJURH1VaWxhWns3eTtHK1VQQm1SJXpfMlBTWG4qX3hnVytZcntWVnl0S0Ba
cCN7IWxPO0M7eD1qcC12MyVxZClLCnpDNEtEbUJ0djJwYWErTCghVkliY25oczA5P3R3NzFkMT5v
WGFeWGR7djFXflhXXkMoMWBqMSFHOVd2ZFcpWTR+Ywp6TG9HNlg5fjkoOVJ1YW5uO1hPMH1GRmgj
YTkkTyFRI2x6PFFZWjwhfkRoV3VUYHtFN3BBSElmMCtFfFhscShwZXUKelVYTlVnZV89bEZKPDFk
R0BBPGNIMEliTjlUNGl2WjFQJDdFMChFO1QkNGV6cWFDYzJMcEpVOTM8JmxCJDg7c3tSCnplKUp0
e2NCJUxVZGlkbiNQflMrekZJaWZQPFRIU2hBIXk0THQraXV5aVJsYkBhYl8kQ2B2WSQhZ0x1N0Jt
eDx3WQp6SGE2RjdkezQzZ3UyT29uPDtHUTA1PjI1KSNjWWltMjE+RjVWaXZ4RitiZkpiOWYwaiY0
RE1OfWR8I2piPmpfQloKelRBMGQjJjApeHE7JVp2VVIjWDdxQlVrSVAkUnAyWVJTUXk3QTtzOWQ9
PXwmXjEzPX5sMUJxTzUtP0QrQzdUUipRCnpyQzFkVmwlRSZoelBBKVZTY3xXRjhpdntPdUxyfVdC
amF0RVJqYUFGZFU2NEJxVU85fiFpV25FYUZaSU0wLTAtcAp6Z3BfcXBaWkB1dlBXPXI9JSE0VFg4
aClfPlEtXkBXdUN4JUFyV3dTcmk7TnNaTU8jNnlZP2g8X0xBeVNSMX5+JHoKemZ0JUN9QlhIUn1X
UjA/M25adWJNSXUzR0lsJmBNN1J8NHNkYiUpcFNkITdwPSpBe3wmKk1ZOXdFVXR9eHhzfUQ3Cno4
ODdDU2I2aGZqPGBgJlAwQSZBfVMhamMjO2Vncz5VTX43OWBtRmF9Z19mcmtIP1o/TF5LV2V5QmB7
b05oa2tUJgp6XylFazRIdlQrZnNNNHpxNGpeQjtnSDlmITBQOEZ4eFlLb3VjNWYmPj1LWUlWZER2
X2JJei00Zys2eSpGdjd2MWIKej4xdmAzK3tvdzdNTSRUZFRncUwkKkg0MzxNTSZWNkdQanhedT54
RURwYWUwJkdTYGF0O0xxNlFSQWVaeGB+cGBSCno/P29yZlIqQih0UHtMSmYhZl5EMmszd1Eja0Vj
YW9QSGM8d2wodTZuKGlteTZZMz9lT2VGP3ktUXBJNC1RKXJkRQp6LTswOzgjOVZYQDtGVjZJamt+
JFFgdTJUfDBte2I0dmRXY0ltTmA5fncoJG80WWVndVpIS1Vwe2NRfihCSzF1RGEKeld9I3hIcj91
OXs8RmphNThofVdaIzt7Q2ZyYlhTU2Q4eU1xUCZDUEEoQH57NDhVTiRKKTVSMn1BYUNnelYyWE9K
CnpXJm58S0ZZU050dzR1WmwpYUNWMyl4cCF5dmVsWm8rdEArQmhHTzYzRDQhPSEzan43MklLVnM5
QGIwMzBuI3o1eAp6PjAwfXc2M3dgeUVKcEp+JG1GQ1FKV18mNVkrcz9XYkZCME5ibDE0TyQpcCVs
N0IhJC1ycm4mZV52Yk1KK34hMkUKeipmczY+ej1nTUY+cHU4WUAmJUJKMm94d1lhSFgyNnZ0O2hZ
ezhEayNTUCEjRFV5T1Q8LUtTe0pTS3V+eyg9PmBXCnpGdEZHZCQ5fGZePEo0KHxSeSYwX0pCMyM4
NTlofipBSl9NaDVSTEk4TUhIcCE+c1lBfjtVMjIyP0N4PEw5VDR+egp6TmFJUmc+P0xWfFBWLWpg
LXJQJj9jVC0oYlFmWmM4bTF8JlQqTm1IM1FseT1uSEd2SXNfbzlZUHEyQ1ZaMG9FMlUKejx+flg1
YCFAJWcqeVJ8OzZKYnwzbD1LJVdATUcxZSMwO0E7diQ3Vj1tNXlmO3okWTchNHZLNmF3WXRhJnQ3
dDJ5CnpvYTZxUGxzND19NypnOGQxZXIjenM7SkQrKjRFMnhvdFhYQzYjJDYqODxiQHdTVGZnTUBZ
O2doYih2Yyl0YCVwbgp6dkRJOUo9PzcwRmk2JE0jek5lI2JXUTY2S3xNRD89MjZLb3xXNzB1MmdC
eF52WUQqO1BAM3tWUUR2bW1MI0FZfFYKej58O0p9eXEkNzBFJHpSbTZgTW0jQmhOITRQeWNqPmxW
Oz4+bzdrPkc8KEpLJGtPWGw1TGUoRH0qWi0lekBfKmV6CnpHS0E5dWZiSSghYHFrJlZRWSpOUSNZ
TlpmTVUtVlMqfUpvK2hmcG9NPzdqNWVucF4yJShmcT1LblctKU9gRXl6Ywp6JDZDOUR0ZWVMQWBU
PCE8XjNJKE1gTnt8UF4+QmBiJE1FQipReyV5YWlobVUpKD1rNz5CS2pKbU9BQHYlZHdKZG4Kek57
NiR2diNRJDB3dyFxTTVwJklWYF51I3lNMDxnanRHZz45SDk9fnFeQm50I2whUTR5KHVpSit4dVc5
MzFNdlYkCnp1Znh9dXM7VXJjeExPbGE2VmxBKSg8YzMrKFVGbldpUkEqd1N7TXk1KD97KkpTd1lT
S2RxTVJeMXZPY1lwX1RlYQp6elQ/ZmUrelVldHZ5eSU0Q2p5NmA9TFl0JFkmXkpxYHpoP20rfXZ7
WXJ3JWBFdHt7QnZSWnJYMl5TPz5JVTd9TmoKem5FMksyQEYmQ2ljRil2JV9aV1YoX2RXUnkoLV8q
N1FreUdWdUl7JWxkR3FGdFZiZDVNemUxdGs5NVhkS1pTTT0xCno0bS0qeEJVUGhzITBMQ1NINWt2
KF9HYlRNZmtMNWwpTW0lP1lIZkJYXk9CTG8kYlhPSVR0PyZWM3FiQ1pySXozQQp6LSVGQXFSVl4p
SyE9fGpQdGVgYHk7OHkhJl59U2I7QUFldWEhK31gcztyZ1YhWDI/dWMyIXhybGJEaDZgX3NWZz0K
ejtQODV5SjMkZG1vfEY4YDFpR149QjB4eDM+PVZ7d2o/PkRmcWhEKGE3JkxXdUY1YU5AJi1nM2xo
d25nKl9fdmtECno+O3IwfGMxaV5GUSMtNlc+O3tpX3hybyEmTVAlflh2YSZNSW9sLXA/X3NxdSVR
XnRkYk8pIWQpdDg0ITBgcjZ1Qgp6NjhSa3Z2cTd6TnJGUXBaUGFrLUNkTiVQQV9OUlFJMl9eTFc7
aEhSdm9lIzluSzMkRGkkNHYlIz9Aakx4dTZBPEMKej95WD53Z1pzdUgxczJ0SWxeUG45PD4ySSpm
VnVZWTZPPVokd0RaZlRKJmVIVztwR0JURWlEJlYmeGF7dSVMMDlxCnplKExQZTR+UnRiWUlwRCkz
PShuUkxDUDUrUG5uKj1oRHo+TWVxM0ZWbnUkMmYkWkJ2VWpGdj80MTMhS3tyPD9eQwp6T3U0d1lU
Nlh0VWg0aUdfazVsPFdTM1Y9VmozZE0/NVAwazV5dlZrMGZebWo8TSN9LV5OSnlgP1J5cyQ7Yjwq
aVQKekFZRUQ0KUFLfH5aeEZycCNSK1dgSHF9XyFISD9lSSY7c0Y/czZ7cFkwTkcrQW5XZ1c1dzJX
QHZvUngmWT5aPERFCnpVQEIyTkl+Xip2WCg8SSE8QkBgYkdkPTxsP1gmIzNVPD5VQ09neWFSaFM/
Qz8pUHw+QkowJmVwUTlHZ1EqUDl9egp6JE1KI1ZrJCkkZ3BXP2BBe0BGclU0QSQ5U2M/YHROQ1Bh
VzhvVUNsY2tiKXtXVHk+X3l3YTwrPmpVcyZMYDdyVUEKeko2Rn4pd0lLPmFfUldfdnZrVXpCdWE1
dzlCSyZ0NWhLSE0qZ3cjSThFb1J2eCFVQzIoNTk8YT1gPm1UXmhkWUJQCnpVLTB5Z0JKMWZCRnN+
Sj9RQC16OTJnR3F8WEJXTGFNZ3UmUnJJdkZ0MlBaJGJ2TT91V2lmSF9SVjcxKDM5djtDZwp6Jn1G
SkJsKDBWYXF+SUYoeGEoUyNJMShRO1crekBybnlxXk57SkVnfCFEVGUxRUh5UFBhNVVScFI4VWFz
WnZAKGIKemBibGtZPjB5P2pKZ0tGaVJ2YWdEdk9AMEhwWEBCN21EY3k7X2BgSWdwWj1oQHMzLXRN
TV97Vk1fVDQ7dTVeck9wCno7JnxyYUdHYXpZRXEwMURCSjM8N0BpV3E+ZXtoM2I4NUtOY151bCts
LTk2YkN5fUt7VDJka3wkOS1EZDY/c21Ucgp6NWlxRTF3N1dFNTkmRkpsPG9TRStDJTV8M1d7JW5C
MmcmT0Q2JnRPbSR2VGlfb0tZNWt1cWJxWnBHST8mVDg+SFcKenJXTVlSNX5XdEZZTDM8bj96XzBT
cGpVT1RtVkVxWmpZNyV5JlVJKyVRfGorWHdmI1BKJH5zX25iTS19N0VHP35OCnpmb2tHI1dZNkFU
Pn5iTGt5IVBTV2cjQjl1Z08tVVFSVVc0bE4lVlctdCZyMFYtXnwwYUZ8NT5eYVBFWXZpQWhQQgp6
K1NxNj9AdT1YfXtLRH05OHxeeUw8bFZ5WFUqbEJEak5VJV9eRXYqOFVMJWdwblNrLT1ZYVFCV09u
KDhtQktQNG4KekFNbW5yKzhpI1ZDK2p8dCtWNTUkbnVFMWBAU3E0Kjctb3x5X2h7PjNTNUo/djhY
SGd+MHdUeS0/aHc3cHE9KTtsCnp7PHZTK0M4PXhwV25BUkhwaikoRnYqUiFYX1l8VmtKdyt1OE0+
SUJnO2RDP2xOUj5uZ2BLX3AqUUEkOXpCVmF2aQp6OEZyR0VRJnJKJXZTSVQ9ZE01VnZreWg9TWxF
NHBmPk1+TEU5NU5TYlVyfUN1LUllKH0tV0d7fHwxbl9jWjJQcUQKemU1WVBHV253dy0wSl9vbSgx
Y0tTcGctb1dwWEs/UEckdDtyVCF6XlB5WHAza2l6NiteYilYa1AoWXUpLTR7VT1pCno7d1FXeGJt
PjVVQlVzY3g9R0MpYiY8Q3dYVnxOPlVoQz9MTF9sLTEyPjIrc2FTMGBZRiNANSFBcWN3OXlZZEsh
Ugp6Kk0rPiskOVh7ayh1RmU4KHxKajR0cyVTPTE4OyVvZEIyJkgpO1dIWFV2a3M7WFc4VV9CKmhZ
YWUyN2VNXjJ1JDQKejRxQ2RubDtDaFVJajc/QFd3NTQjWEgmSDxhZy07VTVTXz9sN0xESXF1YTU0
JlEhfU9+Vn47Rm9HQDtaISVzYm9xCnpWM2VXcWlQPW91bVJzWno0a2B8VCp6WFJpKXo3R19oN2ZU
SFF0amk3NDdWSWpFZ1RUN2x4M0w4TFc4V18oWFRYbAp6MXJaJlcwUktzJXNrd2NicjkrckQzeHhj
XiVpQ0wzODhqdy07K21pZkJSbWNPY3JgR3dPdjVwNkRFRDtsbjs4VjUKemc0Yl84QGJqeDNhVXBT
b1UzQFRRI144cEJHamVqdVZgSS09QjErKX5APkxmUGo7TmhORUMjSF8hMH1IbDJwdV43CnpJfWJO
TiReeXMjZ0dXWXgzV1d5NmZYVm4/RV9vWktNNWJgaEF2ai1TR094bnpkaU1lJHozYHU/dFAlVil6
N2NlOQp6Jm9BVEtJbnU2R0lGbHAyU1RqM3w7PkN+UjRlfWFORGBOPnN1U1kjYTNYNnZYP34xQlJJ
Kjx9Y2xNV3hXMWYqPU0KekNSLStoanxPdG9PPG5GTDtXfj0xTmwtJWRUNzl6VldhTGxaZDwrbFNq
dH48UyZrKlZfMnVxRTFWO1BjX2Z7ZCphCnpAPFlnVyFvb3RVOEgkcj1pYEUmMEQ3JU9eP3EmUXZl
WjRkVDEjPmZ0aWkkXlF8RkxRbCZvSnhPazlVKUslZ2BESgp6JDs+P2g8SXluI0lSV0xGUGpeeiop
KEM7JCFZJjdeXnhjWCRmM1MpJXE3MUpGVGkkdFRtP04jZigzNTI5ZF49VUcKejBIb2A3OWVvWVFO
bmVEUHlWNjRYRmtTPHFDN0VSI0w/VFVFSFc8TjI1dStXJlVqenJ9MEhyQUUqNDk7cW8pS1RWCnol
YFU5aFhTd0ojKmEwQ243T0VlYUNHekQ5Zj5LKH0rMkp7SyFPVEMwSntCe2BSPGdFal5jbVNQN2s2
ISVsOF5kcwp6SDR+MXg5bDB8QjNuJGlTNk8taHhsJVJjV3BWVks9bGRRMnpnVlNBRnltJFhUP3Q3
KGRBbnVKZG5Ke2VSd1kqXjsKel9kVD1uOH5iKDdgUX4kRWU/cGQrcV5SZHFDYVZDRmByR1BxcEFo
UC1pTig/dDE3NXxTQUNNdGRgPmRxUkltaHE/CnpjdSNTMGFsX1Vta0d4I09objx9ISZ3Z155UEJg
U0E7bDBzeHkpXm1GMklaRTY2blpsPXlTKSorckdzX0N7RFJIMAp6NGF5ZTxMTkA3QktTaihAQF9w
WGgrYyVYSUIoJnxmLVF4NFBlPVJHZ2Q+UkV1YDM+TGc+aEFWakQ7M1I9Y1puXkMKeisqWW9jWTN9
ZWpKP0dOMThWZzY1ZFJrfFhNdCpjSz11ZjwtWEVAdn15Jnl6d29qYiUqenJIU1BTNS05WSU5aGBV
CnpVZUApaV8yWDdtKFYxI29fV29XbUxAV3FjO0BYdlNvcXlFNnpsN2ZWdyVqKyNmNFlAK3heaTRV
Rm1mIXI8UWVAZgp6RGwoPEB3aDYpZD9PJkZUUWtaYE4yUWRlZyNaXjEtPChudEU4Z2ArcjlDbmZV
UTR5eVFGT1NEY2p9KCUqeHBATDkKeiN7cWw0V1RRN3ojLWN8O0kkLVBIWjt8XjxqUktXK1E3aWUx
YS1oSFcxV3M0Mmk5diRDVDJyNFhMaVNvVXlpOH1eCnpCKktwcDJNUi05Y19XKGRpR0tTUXpPdD0+
SS0wbWlAcmRWZTJxezYzSHhBNn5ZPk1ZYHFvSHtMWXJLM0YpcCZ1Xgp6eSU7cUk9b0NkRSpGYWlZ
eEBTKVgwM2RPSFk2RntFNi0hZVFxcy15TTV3eHA7cyNCRjAhN0hOKWZ9Wkt7JjlWKH0KekQ/fGBn
fERObWB5MHN9OFdtTStzc15VRzZUe3JQS3dYYHd+Q01GP29vLWk5JFpfbGV8NSpnWDw1VmNfNSl6
IVdGCnppYF5ZSHdadzh9WiNHV0E8TE4qcygqWENoMGRpbWIjYVUrRCVpNHYjcH1PUTM0amh+ZVha
OCt6ckNPZUwhJkkzQgp6V2JPO2JDMVJzOXFvI2o7RlgkblI+Pn1INCM5YGlsZ3lqJElob2JSam0k
S0hPbXZ2SVhyPGBqOUxVUHxVNVE2fUYKenN6cTVnT0A4QCMlJl9qfEh7S0VKb3Q0OEd0LSU/TGY+
X19WdDFzeHEjbCVjXzZybHteKXRYbXw1Xlghb3s3dmQpCnphS3BsU0U7YDl6eDBtZHtue30oT3pX
cmV3Y1d6Ril0T15YJWNuS2IwNGw/ckoxTF9BPmp0KCZZeU5NfTZIUCZiZgp6TGotQGNpJSEhKHFt
JHtAV2BNU04rNCtPWmpxUFhrS3djUExWSm5mQmJneTB5anZ+QChMVkpYUjBqJDJmeXJNVXoKekpX
PDdPRXdFOykqfSojN2RRR2VSMkd+cmNjY1EpdlArMEsoXmt7aWItZ2o/Ml9eNGN7T2dCfGJPI0I3
a3owfDs+Cno7QGhkfEllQXN7c1RhekdNQnQ1eE1vZjAlMyRXM24/ZlMxdFRBSiRQenQ3TnlBSDRf
KCFrQ1lGZm8/aDNCSnJEKwp6d2RiMCFhJUlxTD9Abi1YdERVNFdaJktzbmlNbkgpeyVGKzZhQUFt
MmYldW5eI1FMJiNfMnoqc2dVPz17Y1hmNjkKek0pWmV3NEhya1psVWpUYGU0bFlSKU4yfl9fZk9W
Q2smUWxjPD89a0VtMzM5U2dfblUoK3wtS0JTPT9mSVpJcCpZCno0NVVwRiErZ1h7TDxxZFAmQ1Y8
T0M/IylUXm9mVihjM305O1dTRG05dU98JSFUXzJ8U2MwIS1gNyo3U1glPzQtdgp6PUpOdVBuNnoh
U3lxcCg9MDdFXjlCK1FxQjg2dU0mKlAkWWdaNzx0WlRNeFQ4TXQxeUtVP0Q5PFkmSnl0YT5sQVYK
eioweTFgYVZFb1otc0lZdWRjMmJZT3pXQVpyVU1jPTlCREp6Rjw3SUtfVH1WWEdWdnJEK3YmJEg9
WjVFR2BxbiRUCnohWF9CQktZZDdFN01KcHY+N0VUS1g5VVBIVkEyWSZKJF9FQ0xSNX1jYklIbUY/
VkpuV29yQldQQVE2YjVwdkxxbwp6P2goeFE2YjVEWnJrZ3JDOUpKX0pRdV5KfW9IJWI0cmxxRXI9
MWZpJk9AWXNsWSZZOVdyWn1kSHpiJU1WYnEkQioKekBnPFVEa3EtTENldHVJNm8yVHlhbkcmYkI0
UG1DSWtwI1k1Z3s/d2dhbm9RWFFMb2JVfDdhSiEpcFVUMFNVK0h5CnpnYFdzX1JuXnBfJkc9ZkhJ
SCF1S0M/fSsrcmU4eWpQNUI7QCU5cT9+dG4lVFl7fFcxOSl5MXVsO2ZTRzJTcXxrQQp6UTtvYXxr
NzxDTyVhXnQyR15OfSlXQnRidnF0QD08KH1zV0lDbGQrSkg9NFhSYE1GfT5mM317Oz1sOWtQWmZ0
V3YKej9oflEqKCtgJm0/RU97cGR3SmgtMSlpMzYzSkdfTGMjSVg7LSlobn5uY2FXdEduSW5lVGBI
VWtjM2FEeHsyMCtCCno8b1VxT3FQMGdIRWB+eVM2ck1qZ1NnI3ZiRkVtTyVBeGFTYFdAZX52Pl8m
U3tlYjlibih5TGU0cUcjRVlKYF4+VAp6ZGhiQz1pSWE2eFpFYkJhaCh5VmhCT1VOIzlOZUtgYClh
SihPO20lNGMlOHppPmhraVhxOVplTk9WOG9he3Yzc3sKenM8ViZ3SGF8cG1WeDZlJERuOW5CKlFI
PDs+X0M9MWpWaEU+SStgdkBwdHBPbkFDXzc9WHp8bzx7QlNtVyk0cl4lCnpkPF9pazxvJlkwUCs8
ZlA+UTFeXmNFQWlBT314N3ZYSn1+X2VGbVdpJVJqZ1pmKmdHeGZKOEo8cHo3JEcpcnR2Tgp6JlI1
VmVIYTUwdEpnI3ItJHhIZmkqfUw8T2ooJSNKSTw8eX1RaFRDT0F6O1crKWVMdnZqKTxHdFRwVipX
KWlOIUsKemRhQHReUnVMXjE9R29LSi08NnVXPChLbEgoVkRMR3lgJntIeTJUdzxUejVOUkhwOyQ0
PU1CemFZYFc7YGd3e29OCnp6TE0oaUh8LTwzTW5FLVImbUx7UDViUWA8RXJeVjBAWX5KZUV8Z1ZZ
Mj9qR1RtPX1ZN3IkS0p+dyZwQ0hnR0lNKAp6Um5Ofm1sTkpQeW84MGJhQk8zNSNUfEhnaTReTi12
TTZCYFpyTUAyKyNPX144P2tTMXgqbDdiaDVySThsWX57bSQKei1SU0Q+dGNuaGdtNHV2TCVaRyQ/
ajg7Mk5aNnJFeHcoUlAoWX59NkJKQzhwQj9SYFVEU1IwbHZYQTNJYGQ8X3ktCnpSY1hVc0dueUlE
VHlDWlpIPWxRYzN7ZD1gPnJWRko2eiFJSStjX1V3cC0lKm9TQVQzIV8oe0l2KVhaZjt5fjMjTgp6
azZ2RGN6fFJ4UXM4JUdic14jOGJKR3QxUitHZTUqZDlyYEI+R2dEPXgkKGVDQzRHMW1QcUs2dns8
JkBMWkFyK14Keis3QXIxT0ZiWEZpSzl6flJEKXp7RzxVU2BOKnM3WHdjSmVDQ1pXVmdWKn5laSN3
VEZiOyQkXm1nT0l1X2g0V0ZJCnpwNTcxRGEoT1goXyt5VDU8MyhAWjs0b2ZLI0FEVm9WM0hxWHl+
JjI0ZFdXelI2dnA4LUopbEgrb1JUN2ErfExMJgp6VUI/aj52UHU9cTlFXnY4dCFJNzszMTFnZ3hO
YyEhVjQoNkt0WXxySXthVnZoUyRnUzNXblJPUChVR2UxI19xTTAKeiQ8RlI+RzEwNVd7Sy0wdG0q
Xzd0b0tjeGsxZXRCeSZ1PUh4Iz8wSlE1R3Y5S3J2c3t+dVgwZGRvQzREJUlSNTgjCmpDQD5YKDxO
eGEmTC17R29eIWJ4SlErfkQ7UjlXQDM0ZXVhc0tZYWRRQjhKTEgKCmxpdGVyYWwgMApIY21WP2Qw
MDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZV9wLnBuZyBiL2FwcC9yZXMv
c3RlYW0vZWNsaXBzZV9wLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi4xMjE2MzhhYzEwMjcxMDBhMjI1ZTM4NzRj
Yjc3YTkwN2U3MjM5MzI0CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAxOTExNQp6Y21lSWFoZ1Za
dyZeSD51aVY4TUJzVlgyITZfTVVsNUNvKFhMSTxUdT8/Z0syQlBka0BwJTt9VmdvTkc9cGglTm0K
ejU7e21QMFV7Kj9MaTt3KWQrKXBNcEsjWj1wMHk7d2JJdmFGbzA7RnRwMWx0cndLU0EzKEs2RlFB
ZHBLYyZsUG5iCno1TlpQbWd5eEBmWFRYKCFIQkF9dGI+OCo0cCQ3eSkqTDNuaikjfiFpM1M3TURg
T0xzbSpUdSNZez9ncVYwKkF1fAp6P1ZLR3ZFTUt9PjMlYT01cm1vOHtMbTs7eER2RDNeLWxWTmch
Mk1aQz5CayNuZUo1Pn4xZ0R5QFk3MHgoQTdiQTMKemE8QURfRks0QHZfajYyd1U2Jkl4T3JFPjk9
MWlEQWY0LUA5VFQ8Zk9kOCgoa0V7RVQ1Tmc4ZnghTk52WG9HSm5XCnpnOV5EaVRBdE5XKS1qTHZl
ZFZZfVorNUsqYV4yaVJyak9oVj50UU5DMT9GYSV3I04+PjhsQkphZ1JpRmxLTDExRAp6S0xxfG07
NkRXWnpYKig8YTNvaUw4diR4KW07NzViVnhHSj1QaHhCKllfdChiWlJUQHZMaj5mfFk7NWFuRUxa
Y2oKel5VYmVIamBtdztId05XRHshXjxrdXxofXNoTnt5d29zZ3ZeV2hjYjdUaC1VZ0t1KDc/UWgm
T3BrKjVufktyK2h+Cno9O00kYFVWLX5pQUdgZUQ5bCFQVGpkJlkrJGhyRyhTVCFWQj1+TklzJUx1
T2JhcHpTSylgc0RSJWNwZj1AVHlVMQp6RGNvUnhWUXp2QW8xT2hTY0gtLUV1N3wmaEU8PlctY20x
RjZPKHtUJW5Icnt3YFlJfDRQOzVFMXFlZkJyRUlIYVoKelFDYHY+YllgZEUqRFVubzclSTRmR2pv
aFBiQVVVdTFBR2MoYl9tMV8rJFNCe2w9MiZ2Ujl9emoyPE5mbE11Yy07CnpyUkFPdHVWcXpMMTs0
Sm1fO25wRmNedyg9RGFvTEFfcXhobTI4fFltQEt5JVpVKVB0VCVDMFJodEBnKn0tYktIZQp6d3t7
dy1tdH5yfDNsVkdLR2t9Ql5PNUV0cC1ualAyP20kc0pTd2VlMkRNbExfWVl1JVQybFlNVkJ7U3Ze
dHw3LXAKentEeTcmYnNuPERHU0dJY3RSTTJRWVRwXm0zYXc7WmI4X2dMajIydDdiSFFiRmk/Sjsm
PnYpdGEzLW88M3ZiXiVfCno+VnxJakVYa0spZG1uMElRZlA3T15Kbj9iNzdzb25FSn1FUGNabFpa
RHBlcSU/b3lfenpqZWt7MyhCKCVhPTRwJAp6Y3tlWUU4QVNwR1I2ZjQtSXNZMXVlZ0UkSDZ6VGJr
VUhLZSZRYjhxM2RvJUBxRGY0YTtJUCVxYSslQGdlM04/TWQKemNWRX1pUlYoM3FCUktUVllYZ15a
YVhWZVYycitvJlFxKyEoKTAjYz45PWtMdGp7Zk4qVys/ZFE7SjI/Kjx0Q05SCnpFNXhVKDRuXjcq
NnpHezY9NF9UZUw+cTA5Wl9DUj1pWCQjSmV2VV5ieXZFLWdAY0o/QztXQGMmJGI5WGRjRG5xeAp6
UzVAUkNySUtvZHh8NkN7Nj5sSEBIWSFWM3BObktha2dAS0t3cy1DJnRWSjImMjB4UzVxR2w1NUEk
Mm5oezE2X2YKend0bFhNTz9OLV4wOzl1XmMpSjRuZ20xYWBac242bmBIRH41VE1gRTR5VmdgSXlg
USlMIT5AOF8rVzhSdXZncFlCCnpPXzc8cylIblFWaUEtfV4kbFVkaSh8PkxSSGtkRF8yVUpkQ1NN
TFpVSnlNXmc9NjB0YW89O3B8KFZ4LUVMUj9iTQp6fDZKLWojM08obWIkX25PS0FMNDR5XjNxdVMm
I3syZlA2QVAjUnlVOWtFaSV6a0FIU31Ib3R3QVZxfHV8c3RJPm8KelYrQmhAb01sR0pqREolIXd6
YW8qRj5xUmItQUNoQndla2FOSmF+RCV5TEFjalZEKy1XVj1CSjtiU28yVGkzSUdUCnpkRz81OURA
UTxMQ081WnFVSHRJYVhSREB7aDc7NUVJN0dHKzg9NWspOV85UHkqcWQjMmBGR0Q+JlVrQVRZfkJ2
Rgp6aDI8JG10PkMrWl8/MWUmcUphdnYkKihEb0h+S1dXNVVQKEotN2dgM01ubmw5M1hja0NkOU0x
RnpOYHU/XkxWR3YKekk/X1k2YWBPJSpffiZCX3M/JH5APHVAcy1JRn0oR2tEaTF2QTVXJndJREch
RU50JHE/e0dJMGdaZWU2TllHUShvCnpHUDJgRW5VWGFnV1NAMGhnZ20kYjI4QiRAeHhebXJyQm8z
Kj8rKitmQmxQLXBIdmhiQWhPZXJuWWZMOTRYN2dodwp6ZUhHOz1jNTA3YFR+Y1Q0JW4pWkZ2fV9A
I2h2TnNQZHlmdE0+eihWUypfZnEkVSR7SXIpVmNISlNHfEpqPk0jJUEKel4jbShZRTBUTTs9ZEFa
cUx1Rnh+Z1RTUmQ3SXVofDFvZWdERjllJXpvY05TbSsxKGZFY2s7PVhmO090Sj8kaCZACnoxUVpv
IXllMXxuJiN2cT4/UWNoc2diMVdjUE1fcVBra3gtMHNVN0VqLXhuZEY7cDJ0dkJEUVVQZXZje2Bx
VkNyUgp6IzlafkclWilCdG5QTnheTT1qRDUyZGN5aDJVR0EoS0IrOF9SWHxkWDdKK0x3NCojLW80
NmcyTiZBSH4kbk49WkYKenhPWVZGbH57KXJKfH5oNiYtfXRzQEphITg2U1VhREh4R25GWG9BelA3
Jk07S0g9Ry00RmJsKl5kWFh5Sl9YNl5mCnoyfDImTUNeZEB7PDhmP0t3UWVwWjYtc3tGTD5BYUcp
N1RLLU9TalV+a2hVfF83akFeZVh5bk5+XiFwK2dIMHVZSQp6dWBAWlFTVUo+UFA0JkxsSCFnVGRN
aTxIYkViamNGPWFeQXwlWWVPQyVVNzJgRWw5Qk5EYUhwcyh+TTx9PGdwdHgKekRkbnlpdFkkRz4/
Y3NfSFFgTSZKRyt7Q0kjPkZ3KlhsSj0+WHx3JVF2OHQqJFlhN1ZETjEpTnVjd2ExSzE8fHFuCnpo
Mlo9Tm0wS0RWRiFTZE14MG9aNkFxc21SPE5IZVphSzhtY25sZTdfVVZqV315QTdzQ0NDRFBKQjQ0
fDQkUTtuawp6K0slKFA/MDJ0bG0ocnl3UisqYSs2TT9kJlRmQG1XPl9xTl9Ob190NWhGbGl8TzxH
aUMlcUEtNCtfQUgwU2NoYjgKekJeO2dlWXd9RjwpYkwmSXRORWZkR3JWYVoydmNIKHtYdEhMYiVe
aXdyeSlMMUVVMjBXNCt7RHlkcjt6RndzcGtaCnp4JE1jP3VpeVUrTV5EXkM8elIjQUxmazU5dStL
T0c9RmVtTUBiT19FaDBfY2VuRygpeWVyJSk7eTsoSm9BSmRhbQp6QnhMM243akMxemM1TTh4dVF6
Kl9CQV8kM0Jue2MwYEhrMylMcHk5MjV6T19vJHh3bW9WbCVYRExTVUxvRW9XND4KekowZ21QZW50
cSFtc1JTTmFgREEjeV8pc3ItZUs9PTxhPGJOaFFqIUJqbS1+SD49Ty1+RSo+PEg9eDFQPnpZd0Qo
CnpsPSpxXzBfV3ZCbEhySD4paG8zM0R7Wm4wcWNQVzdhNjg+JTBaWXhUPHZIJkxnZG1Oc1ByPnR6
WExHeXo7Ni1tegp6NTRJTWN2bk5gcWQ8K1A/OSVTamFAXzZVa0ZXbEB8QDBEdnNNXkg5eDRZMF4r
eClnR0hQUD0hdUZOVj1IbXlubnQKekx7MSp5JTJRQV4zVWBedmBMJT0xa0JXfXFRJWs1WGR6bipU
d0VeOD1lKihGWWFnUDYlcnFiUiElRWJGMnlVRE4zCno/JkBwVWFkbnc1IXpvZCE/OUxoajk4OW8y
RTBkfVFOOyYmQDg4YGhrOHB4VDVNKFJ4cTh6MUMpLVJAZFN2OFZRbQp6ZypQZVY/TXNyY0E9fHtz
NVUzcGsxQ0JTLSFvYSQzYWQ2VD1gVDwhO2RPdytYYkdaNEYwSWwoP1hKeURpYUdAI2AKek5ebVN6
cjFaRGIpenpiODZTOzhOVjsoMT5WQEdRbkI+MiU0Z1U1N096Zkp4Q211MkxwUHpJbH07WVk2ZktF
Pks0Cno2eyo9KTQ9ZWlJKyR5a1RQO3Q1YXZuUWw+KCZRcHcjQXlINXFsVDFxTTh9K3xlPGY/cTZC
UWx6PENvMk5DcGwobAp6WWNubigrR2IqUm1CVU03SlV1M3MzVWMjS2FXSEdPN29JdmBldGgwdEQx
fWQxPHVNfEQrKFdENih3R0pfdGYtMHwKenVpaGhEMj5BWClofHU2aD5lNXhiO2V+QV5jVmIoPnh7
Mmk1ZDxXWFEtbUFMKVRpdE9qeFJyJT56S2RIeUk8fUQ+CnpDUkJ+ajYpbVU/d0BFJldnanRXb0h0
ZXBXPGlSc1VfT0Q5V2FGLUZ9czcyJVpscEgtMXJgSGFIZSk9KmAhU207bwp6ITFKNSRZWmpMKyVY
Kk9lPDdMcTt4UHxtXmFefmFtV0Fwc3hOdCk1QXo0MGRkMnFreTwyYXZgYXcpSk5ydDRveyUKemlf
NmlIWUlCQVU+Vy02OHp3b2tvaypFcE5IUSV1XmBoNE41ellpTkJrZ1JrM2ptMUdwYTxIa2lwcGJE
Nytjc14oCnp5REY7ZGxHKGZYSTNsQ1cpcGgoPj1LZWNvLSMxbWFBajRFNHIqQ1lweDBpVj85P1pN
PEJudkpzKntrVDNlbGFZJAp6V1VSfVFiXz9Uc1JYRUBldStFfTdQQklNKnIxV2hnXitpTG0weURW
NGNZfTQyeVh9KEJAbSVmcCZicTVhbXU9Rz0KeiFgND00enY+RjdrYk00NzNkXlIqQmdpZDJGcWAw
O15IMilPN15BSzIxd0RTQmlqRWUxMjZLNnl7Xmp0TDhAQ34pCnp6bX4hRzs3XyFGPFY4cl5veWxr
Q0Y4MTlFKGp1Rj5WcFYwST17eTRkVTswekhTc3lGZEppYC0oR0l1bURAfmd5agp6Mz1CVEA8eVVp
OypweGx9eitKKz57PDlhUTN6R0k2XygyeGFSSko1VDE9Zk1UZUxleUNCNFpQWSFnWW10OSpQOE0K
ekp4WHBuPzFjbXUmTkFAZFFsTHxqbW0heTAmaStPZXpXRS1zcTNETFlhZWdAPUBkJjZVSUxocko8
RUprJUohd1VSCno3RU9YX0RkbExXO216MFRhUEJ4dFNSKHQtbWtmK2FHJWNofW5FRkNuVzJyV1lH
R25PYm13MUs9aFM7dn41P1l5Vwp6Y18qMkE0ZjJXTzZ5dkFkbDh+IzF7PiNTbS1jbT5uNldPdDE3
fT9Qe2ItPDdjdklodnYmUSZee3ZSOGBJZ1UtUkUKeis7Q1NmNXc0KiFuRXg2PVBOS3RPVzt3NWdJ
fEFSQihWakReMnhvSXJJYkIlSU1MTmlKVDBsaEU5dz1vKG9OV2ZtCnpiOU16YkNjWSRlN1FXITkw
ZU80YHFST3BQdmgwVUxHa2tPSV90NGMreSVZSUc9JUN4UzlATFB+diFMWmFMRlRSewp6Y2FpYkE0
NnhHZDk8K34hWF5CRGkhWVJsX2Bjc1VxJSF5SXkqe09GbUdeSGBYXmBCfDdqdzh6P3NVU15mTHIk
a1gKentuJn5NR0IxYHt0RzUzYk59QmlMYX5JPSpTaUhHaTlJVShoZCEqeDBpK1AmOWlBc09zNUpw
UWtufTxnUGpLQEtKCnpMRTxCS2coV0hFekRJdkZZUkhJZ0lZYyhxO35eKCMyUiFsR0pAPVl6Pn1l
KHJRe2xHaVFtYlY/MmxLZ3F6Q3lKQQp6b2E2czxOPV87dUJSNV9Ab0FKeXw3JFdEYXdAWThhZmBW
bDc3MDNnQkFmdWJUS2g9YmsjfW9WOFFQczR+dVdHbFYKemtwSkhNZXNacn4yQTsxZkdnJl9LeUVI
cX4oTDlnbE9MdG49ZEJ+MFdiTm0qO2xKbGF6dC1xNChUQXxBUDFzcERoCnphc0xYKTVfMDtZPipC
JE1jfDlWQClpKyViIT9vT01Kb0hVfnZBeWRQQj19YGFCZWshb2xuc0lyOGx6cTdoR1ZgJgp6JFhJ
am01YUVKWURCZGNEc0wtaW8lNll7ME5BYW1wZElXLUNKVlB1MVByIWYoNDY4SkJRNGhaKExAJFBz
dmVaOEcKelQ/fVA/YVNuMXI8c0FSQD99STRWOz1neWUpRVh2aHAwSmc/dTJlbitpRnxPMWsjXkUr
SHJMTWtTdzs1dDN+JDJvCnpsfF5hJXFMbVYpdkYpa0ZtcD5DeWR8bzx6eiRPeTV7fmtHfGshY35X
UGVHSD55e3J+SDRJbE1VSCpPV1VpKmFKYQp6NilGaGw8JmdKcGNsd3FXdCoqbVIjPzBtUVhraksh
WUtZUDs+STxoR2pPXllnNDV7bll4Pj44IyFpUVNeb21XMVgKelM3RDUxQ1hlek5IeWxJNnZnVXIo
e3x1flhAI1BsTUh7NyRTK0Q7akVAZ2FiUj4/ZStyPyo5MFUzY3tsZFpla3QhCnpGWVpsYjNfZkxj
PEw+Q2spYGAhKlFpUG12K3t2dyghb2pGVnYtWlplRU44MXxBUX07a1BrJEl7aTVpdTRwYSFBPQp6
WDAhRTl8MD1LYWlvcmJ6YW1AXipIbjFia3ZsNyo4NUxhSXlucmlQX3BCRXxNWSppaTtqQWJtUHFN
fVQ2VWpjfEEKejFIX213P1RmcWE+S0VeOSh2RCE0WWd+VDxZNWE1OTtOSEVWbjlQQ35HcGVRQWkz
KVhQYXZZRkdifDZ+aHN+QmFiCnpYeSMwOTZSPHcmUGwhJTFpOThQfXJVS299e3VZaiNfb3pLdmMr
PHFoNVJxWCY5Q3cxQipifEV7N0FDVVpFNVNLRwp6VDlJNmA5JmdNbVRXS0p9PUshcEs7NUEtUG9D
MWhDekhTVV5UcUs9PWtiZ1RuND8zSXZvPkdFTVkqNyl5U2c5ME0KenU8SS1Icih+JjZMQSlPV0Yh
K203S1pBSzheaEcmM2ZCWFoxTlomNWp4LTV1YzBkckRHJj0oY0EzVkk5KU1xZjU0CnojJX0hM1FL
d0IlUUkqSD10TkVobVVGbVg5TDU5elZvRjEjSWNLKThkSiolMmZvfDZUMkR0WjNESDtoZVc/YEJu
KAp6YS1wNE48S3UycEwzVzs2e01jZENrSjZaVUVgczUqM296RUR5OUBkTjhHfHV1PiNRaG4qcG9y
VXlkTiFFWCtWT3AKelY5PChaJkA3UT96NzltQ3J+QmEoJFlhVm17JFpvel4oWGh5KWQ9cGozdHJ6
dTcoM2UyQVB+UlgjVEV7V2RWfEB7CnoqfXl4P09WVkxRNUopbihYc2kqWUFmayRUN3x5M01JeXNS
TjJncVliIVF3fmQtN3sob287ZXUjQnhqKTckQFQ3NAp6ZEhfNSheQFUyJnZVMWhyN05vVnxEQVMh
eygxK1dpQUxOIz9PIyhFUjRUY1lmdiN3d0F2aHFgZTFnbWUqR0NEZncKejgkd3I8JkgjJip4PE98
aHBhY24peTwkKnx6VyphVTU8cDV2X1Qpbyt1bmw/KzJeS2lIPj5LMXBMfmpFPjhONHgjCno8QVhl
MjBLKHthI2hPI1dTSj9ocFpiNGUqT0VQeWlDcVc+b2NaeDA0V0AmUE1LZi1ZM0JPOXE5N2VRRHdX
QGZ0QQp6RXJIPXo+NTZAaHcqe348e20tPjczN31PY1ZZNDY5NVVjM013Km9sRSk0bmJfOUR0Knxz
Vl9odG9JMXRtbXx4bksKel9oTUVSQCQ7a0F8RiRnSFgwJkRuakdLZ1BxZU1hPWB6SiModSR2I1Jk
NGRQT3N7Qyh2UCsjMjtxemJVWHVXOEx9Cnp8NCg9MHZtRnVgRjEzPGI7c3daSzxgWEZ6PWNULSMw
WiZzPzRGfVVibmE1ZitufSNHP2JRV0tLQiVqS3IjSTdhewp6PGRmdFBXNjBXQHYtUTVuQ25oUWdL
YTA7KWtXWTYzPF4jdG94fW1eTGJ6LS13T35HV2NMcVBqQ1kyQ00qcCkxMG0KenB6fCtNKEw+QXFT
fklfT1QoVXV7K25eXldZaTFaaVoqfXV1M3Z+aGpyQHd3RW9ESiooPktrNHYjeysydV5nNjc7Cnpw
THwwSDd9Zjlke0lgVDhUN18yTWcwOGJNb0psPz1EcDtuN0dvTCl0WmxDc2tWKTRXS1JSRUtIX1g3
YTxfLXhPQAp6MmNRSmJWaGQ/RXpJLWNwaV5uLWt1bW89Q285fjkxKkJ9O1AoZD9LbiZFOWhZZnUo
PVF6bV84YXEhXyRQKDlRKjkKek4wcTBIV0gta3owdUB+WUR6Y0F5RkF8TmFyemFpRjZuM0EzNm9h
JUtKbz1IPHdDeHR+MGh0aTZndTQ3Y2tMaWooCnpqTzEoWUh7ZHdBY0piZTlOfTw9bSRtK0U1Uig+
eWwlPmZ+RUlIeH5sY0xFKlIjT3FtazA3SHlBeGZtZHV0XmlEMgp6aXFxZ09QYWc2TiMzfnFBIVd2
OyZiKXBUM3EoK3EmTWwlN2pQMmRufWBAVHxQKklAeWZuZTB+THc7e0l6UE5iMSEKeilgIWRCOGA0
aG5Ze1BpWDAxfmA/Vno0eVJnVSZ5SjtVc3VeK2olQUEwZkRYbmNPVUpXa09NSURjayFXT0JUbC10
CnoxR1p6RkRyR0RoVXlhRFZUQlNWailfUjJQST5iVTZiblQjUHRHMSNQPlZ+VXc0PldZejI/YyN6
Sj9VY3tfaSpsewp6NDxTX2gwPGRfTmxQPiVlKHBTUDt7U3FJNzF3I0shc3JDcHYxSD9pRWJrY3or
TUB4SUw+SH5EdTNpeFBXYHhlWFcKemdYR1dnVUVeQ2MrUmxNaCRBcEJJWD5qLVNLNkBINk9iZFdC
byhReVIpVWc0fFZBNn4zSXZGN0tnZGs5MzZsJVVMCnpVP0JxYyhBcChxPkdPN2cxY0MxSGJqbllx
RjBYQHIzPXY9QCtzJFZTa2c7JEQ8fTxsY3NpY3pKM1o0MjE2YGRgVQp6ejZXVShgPTZeIzNla0xx
e21uPkEyR14zKiVtMFEyTjgtcVcwPVRSflRSa3EtQE9JKUtOYm1yI0F3S3xrMT5jflgKej1kJnx6
TlRZSTN1ZGFVX0w5JGwtRkVOaVMoQiFpeWQ7cyNFWDJ8alpxeTh4ZVZkMC1lQmY1KXs3X040ckpF
NmVkCnp0ZUZ+OyN0YXl+eFJnfXZkJGswMyNaPXhEUjlyR09pQEl7KjZYejVzTD13Yj5UWilNRD0r
fX51UEdDKWtuJmNTJQp6MnpRTFdGcFBJUWhFaTJOMTkzeWYrZSh2Jj93bDxrPig8JmBGTTM2X0pY
NjdVe3B2fXVTemI3IzwkMEM9e2BNfjwKem0jTU1IbGZkcWVyP1o9PFo8VDBDb0o2VTBNVSRRaWM0
bHxyTjIoTC1TaFVTNnZEVlgkSmEjMzFtKjJsQGVFUCZeCnpgfHRXfjA4Kkg3JVp0UV9WYGFMRjtY
VFgwJD4kenhmQjxeMHI8XyN9ZWgyZlYxPDRoKSNvKng2Smp9MGdWT1k2Uwp6Yjswa3t0dnR8d3l3
KTl6eSFibDF5R2YzLVFMVDA3SG9yUlVhOUdjQCZmQUgxX2ZFMnA/dHJzIVI/ezAjS31jT2QKej5N
ZkBzUnRtZGxobzQtakpGNldHK05We2R0QigjJk5YPUVSWTwoOyNEOzQ4PSgwQEEzeHF8Mkc5eT84
JkJvSl5wCnpMX3IhQDZgYHh1UyU4bHQkM3hBYlJGd0NAUzZwQFlyWSFYKkNOTTw1TEtyLXM9WmRD
NF9COXZ7TnpmU0slcG9xVgp6N0R2cXFgIzZ2bGBiSntQQD8/ZW88KEFqb1NIOVY5Rnxva1hfbkw3
PUl7SytPYnxKQkwyPVErcGtadDR9a0lnYD0Kekg7XkF8UC0mbTZpbCpuclEwfWI3azstYldwWCl7
U3VpPHtZKFg0TlVZPShrLVZ7fkw3ZjY8OGs9MGByMjZxZHE0Cno5Q1dyIWcjVz9NUEM7SW50XypA
RzlRKyp3O0AtZU8zbEFkdDMoJEMmVz5oS35HSVVRZEJ6MDgpeml0M089X25rNAp6WiMpdkhTT2dj
JVZHTytpT1c9PiVxPEU9SyslIXlLeW02R357eUwqVSloYFEoI3skZDstZ0RIWUcqalRSbXJ5SjYK
enNELTdpenI2OHA8cFp0IU9WZ0c5RjtzSkc7MVJPb1ItaEFZJmU3OHdfSkUqIW1Jcyt5ZGZNXlRq
bH5SfXdXMXk3Cno3PWhSd3t9fTNqQUdLQVhPaXh8e3tTb2k8R2JQNjBhXkB7ZE1JUyFrJDV3YjJu
eXVRJGRye1A+I3lDTVBzIyhGPgp6T0VCI01TPXd6M2d8Ul9xKzdWZVJHczFsSGhKTj13VWhWZkNT
eCZMaHB3bypOUEJIY3BsPXNEUm9ve15MUXpgSWYKelRHbDB7T3wkTDU8fiZ6YzVXY2R3a3d6NWtG
PHtSbmtfcTg5YzY5UWQtSTUhUSR4ZDhmYjh6TT1NKSNhdzloWmNXCnp6e2R+WGlnbFpedj0xQ0Y4
I0Y/dSM8NUNuNGk9QkMqPHB5ZVBvOWd2ZTBWS2t3O2s+NndMZFBMPHN+SXotdERvVQp6ek0rNFRo
cFRAUEpOKThTNjxlKDtWOGxHWEtfRmJ+WnBYSmhvOztRMkpmVVMmSDFyZzB8R2BiJCkma19KNjVY
YkwKekxuc2s7YiVCZSo3PmJGSm45Pmxge1UrT1JtX2sxKGh2WTdxPTleMjxzJkF6VldkcU1Ac0w2
Y2c7MjN4MCQ1NngkCnpiUGYkdXc2MXNse1BsUVU7Ryo3ZzxYMFdwRil4R0xlNmQ4ZztGbj5JKUVh
LXAhPlN5VkhTPDZ6blNha3pAVVpwUQp6YCVPdHghe25RN05VMTlHTTgrNj0+Pkdva29reThSYmRS
WXttTWtDY1VaV2dmYUh7T094K2dxIStmP01obikxODQKeiN4UkFzT3xHRlMyY0RxJFg+NTlzbFdp
WDxhZFpqYDtRfFgxNipSI2ZlOzVXUTMweylMUCFmdkotLWVfTT9sTmFHCnp3VFhwZ1MwU1RkPz5r
VilGTCYxPi1memxZZWMlWE0rI2p6OSFaTHJJWGFWfGVZS1RsbmQlUSYmQ2YjVnVtflp3PAp6KGJ4
TjBzaUBmRkVrNVZSWUdKPyQpP1o3aXpldmFsaGJaOWtITE15RnFKajFIdlR7dz1YaHd1bC0oR2FR
dHBJRFEKempjJGMtdURDdCteRWRFZGJAZUYyIUtKc1UlVE0+aG5WSGAhMGNsMXRuKTFvejJIYipo
I0BzV1ZIKXJYVkxRQ0JjCnp7T0QhN0sxUGlBeGltKHdKby02QSNgSS1tU1BJY1JqSVVsMSFOSS1+
cWNlcFBuX2xgX0hHWkg/Z2J+cTZfb3x3ewp6QnEtYD54XzB3ZlhhT1ooZSl7bnJ4ZTVaYjg5bkhI
PChlQX4/cUhgOVJzWUNGMUI/PmRMVWRpbSZWJUg9SGE8UWwKelk/TkgkYVFPeVQ7QEh9dWVTSHsy
PWBDa1R1P2J4bUJPe0UlUlB0QUtzYyVlMT1DcUxSKH1iaFIzNHtiS1l5U1V4Cno3OWYyKDxkRn1Y
MkRhIWA+NTZhNndGQmQhRTcmV305YjA7aFo5bitIQjBBOWpicChGPCp7M2huRTU9OD0tPEV4WQp6
Tk9PZ3FtJElBWVU2Km84Jmxpdyl4bURgMkNWY2JqZ25NK1VJNF57cCZjNk45dS0yKVNtK2orQD1g
ajk8aTZRcDUKeks0QU9CZ257STN3RT4jRSNkcmw1QShvPjJYVSZOMFpZdll8M1poIU5Dc1g1UnV3
cVkxblJ6KTs/fF4penxNUnRwCnpwPXheRGhLRlZNQWt4fmhsemJZKDZEdCtGQis8cHNpe3hxK1BA
fUowKTMkdz5GIWR3JiRfTEJoO0VSdWJgQ2VEJAp6RGxnMmdnbT9BTTc3enZMQnQ0KGxyU0ItIVJk
RHR2Vn0rPTFHfk4kJHpRPlhgUXR6JmtGUTJPRSZETzdeKEdJWiEKek1lQiM8ZmBiS2FsYj5fPGIm
cC05NmhVLWBPSiFmXlB8Nm8oPnwxeWNeeTc5TksrPjY/cWV2dmM4bGUrKE10citgCnpJYlgwRlBp
RjxQJEl3NlgtQVYje1h6ZUl6a19PKjNIIW5+NDdsalUwPCRTJj9MIXM9RyohUWNoKHJMQiVqJkUo
WQp6KkJRJlgqZHBJPUg+fitkdUc4TTIyR3hZT055dEh3d00oXyV7VWdJbyopMmlkdkhHZEp5NHB5
JXFrbU0oZndBSDAKel57O3BHYmNxNikrNHIkJCVaKEFFR3Vucj5QS2lKRD89Jjx+YWsydWwoIVE3
NnQ3YVBJPiMlM1FBWmQhfGB+X1h2CnokflYzY2o/eUQrRWF6YTkleWZnVmFCSVhrVzBKOyRjK2FU
bU5XPjBlKlhqbG5KfWtmYDhxYl9tbSspYCYydjU8cQp6MStOT3p1ISZlPDIzU0RIekBjQEBuJFM9
PGhCTXFTT2BSb35XcXhPd2g5TTMqRk5sYnpoJEs4V3MlQH4wcTVKaTgKemtCI21tRj9jWCVRSyk+
QFFudlA2cDx1O04zbG1aUkR9aEEjWlY/NVRSUyo2ITw5IWpld3xLTDBBc01OdS17YGZDCnopOSpr
VzRjQ3woYD9USiYwRXkjYGE/JFpHbTJWVX5SRnowWUI0R1RZNTc2cH1eNiV2dTR1SGo/bH1rNmg4
WiNLcgp6N0ktTylOWXcwYFRkTj1YOUMkMX5MMHxCUTxnZnRnKl5TQ0NkOFgrZmxNKWdKblBYNyhe
VDhjeHpLKyYhcUV+UT8KejhuZUx6Qy1+PWo3RVdGKlRyKGVuQmdYVVVuOUI/RD96QHl4ZDR1WSpW
UjN6KUkkYz0jRWR4Nmw0NWlYdGlxKihTCnoyaTJEbXRuVmV4QztXI2tAXlBrV0IxfTl7NkpQIW5h
VXx+Kjs2YCNKVSVfNk1MSmFMZT5Id3dqOCV8OHtYTGd7PQp6WGMkXiU/SmRnSE55eWh2aWdpJFIj
KUhqbmhCcXZmd0RUdSo8eTA3KWlLI095JjAxTCpZalNDenNXYyFTZXhuZ3cKel9WYjZwNj54P2hR
VDA3fmUqVSF1Zz1TRzMjb21nd3JKRUhOYjA+Mnp2Pz49QXkyJTtTPG55IUlIPklxYyNfKGo/Cnpt
MTJWaDhDRmp0IWNxR30kJnNrflJRNWRHI2wqO2RNZWBEVXhHM042ZHskWj1eaklFJXkjSnprSzVN
X1FvMyZ4VAp6Y14jZUlHeDU2OUEmeXtsUillQWE9IVA2X1FQdVIhMn1oR2wyTkhjT2dZUj5eTXo1
fi0jPWVvYlYxNmwtR2MwP0gKelNgPTlDY1UyUjE2XztvZlBjN1hGUXBAOGdeYzN4ZnJve3tIUntX
bmhWYU9POVEpX3B1dkdVYTJwdy1xZCZCKCRtCnpMTDdxS1ZYVVl3I3UwazItQ0E/aUZ9Xmo9TEFB
dmBqcHhtM0NPNGJ4JEVCdzl7ZmdWMnE1PmYlcGFSQmZlN1VlNgp6LXJBJHZ5UE9jOFVkX0NsKVYx
Kjt1KCRZYGthdmwzbj1eMn5najRwTytRc19MVk8jJldGPSpXTjRCQlUzYHs9I3MKenIxQU1PQVAp
OHl5dTVody1BLTZLJiNuN0BabFp0ZGc5d2hqNlV2cU9AOGpZfGU9NTNZNGFNVjhxaDh6WTtgdVNr
Cnp2anFhfElOflRBXilYWk9sTHgzV0A8NytgT28rYSQmKXJ1b1Z9fUowezE5JWt5YD9hNikjfTJu
LTc1dXleTF5hUwp6Uyl4UGNsZ0lDNUxHMSYkdSlMRkJiQHRVeUpmTnwxVjRpVSVoZXhqOWVLdnZu
YnpwM3ZzZ15lZSQzPD5vOFM4KTAKejZ3ZGRwKH1TZko9IURZX2I4WnFFZHQwVmMxRyZvNV5zZF5q
d18qVXQtPkFtQ04/WlN5M2lkSCROITN5bUEycV5MCnpDeU1tfG9mQjtwJVluVEdxR1AmT0A8YFFH
UGV2OEVGJjgwUWUoRTI3KiNSRXxwLXw/bmhrVWBIVHkycGchS2EwQgp6OE8laVUhbkhNSz9FZjRO
e2JSSjxrKClsKzsmbXpQUWRsPE50PWpCMmtwPChFU3crcW5iQmtsaE5DSjd5dU9qdWAKek5YV3wm
eit0aVdAWXM1Pjltak5yZG9UPSRuT1c5YE1rNXA3cmJMTiZqcVdwPDsmZHV5MHJOJj9DVkJTY013
KCR3Cnpie0pyTU8yRUZFQW9BMmpQTyEoLURaeGdFdCNra0NvUypESVpjSWQwUjcpTVhpU0x2WGUm
QSh8Zk9gWiFuRnxGYAp6LU8pVCpATGFTYFJOWWRTaT83Nnc5YFhCWEojZGJgYUV1YzdvKGZlSFNQ
RVUjMSNfaiQzYC1WfSYkdShnWHNYNTsKem1pc2Z1PXZSYFgmckV0SGFYLW0zai1iWEZUYGYkUW5u
cmxPZ353PDdTc1k5RnU8flVtVjNnXj95dGY3OS1OX0QrCnpMRX5+aStEcFhpKzQ1M2FFMGoyNHJE
Q3RITmIrcEdFc0p3fGVvMHVjS30zJkVCYHpZb3FSfjlaQFJAYU1lYSY9SQp6M3tOeWxSOTFrWndz
YHcxKH5UQVk+blFeaDZTUVZATjxNUnByakdPTSR9VU5vR3VgKHFfREsoJVA1JlJZenU3cyUKeiVZ
RlZxSWdGPFliazFUalJ+OXxxUjxBcilBfXZOTWpJdklmVztWSmlUVHBUUykzZTtha0shVFpoSHRv
TUVYWHw5CnpAZGdeMl59YWk2Z3VgVnMpdjs4MyR4fVpjVmIwQW4xRndFR1d7IzFwY1VSd0Y/M2lB
djg/SmdaNDlaYmh7Nkp4WQp6SD03UHVKNChPdElWZypBY0pjPyt0bHRwVHkld1MyfEkrO2F6TUkj
PHApXjdteT1wKUI4KnxzYFZpbDlXO350d30KeipFVnZRLX40P3BCZUQmZzQpfTVDNUI4WmpIO1J1
Mk9VKEJyQHc3THpQaEBsbDN7Jll9SUI3MlhqQjMmQ3RrUitjCnpDT1lPVlYzeDV2PkFuSmtnfTRh
O2B8ej5qQiFSR087ZiZ5MTJJT215ak5iSkxwST8jM0BIUD4la2k5XkMqIzNjUgp6aUI9O2pQUCZs
T2tydSNDQ3Q8UUdMa1VDbCElaiZKKWx6K2pXYVghJHkjcEFoU1p9QkVAQihoKE8oQmBwY20qJV4K
eiUpMzRqcUo3NE5mQzZiSENKQG9gZmBXJntFTihsfllOKTArYDs2NHZmNDZ6VzlAS25PPGo3Q1hF
dSlAcTs+RGJpCnpiRHB3SW5aNHBmMlk7PHh1SXRBK0cwSmwzey1hS1h1bD47TUtDXzBGPmNmPCFP
Wk1PTTRDTH4qbWRLeXNiemZSPQp6bkFlRiV7YSZCb19TOWtrTE5XSztoOEctIzhEQipYPU1rYWlD
VCNufCUyaUcoaXNlR2d7WVM1I1Upbz83Wk1rQ34KenR+YGtORnRfPiExN2FgfGF8Yz16cHxgd1Fm
THxNVXRAK3I/SWZ5czZhSkY4JkhPTiVxMTFnfTtTJDFtVG80XiU4Cno9JjlrO1ZCQGA0R0RKMXR2
clRFUGs2TEplMzNnZmQlKChiJUhUMUBabCZqaWErXkBoOW1xQkRDTzVfUip7dCl2Rwp6c1dxJjYm
bn5DKDYzPn01djdjWCNXKFE+R14yWGlVaEBQbjdXJG9VMTlsKG9JKD5uUGJTK3d4amFKRl52QWJK
ZisKelYoO3ZWWW9UKEZIeWdnP2BGPTJ3Ml9nLU8+OGI5fGphVW91QVZDSS0lRm04dmZicW02VUEo
aVQ3YytMZUh7T2heCnpIPmxHMDZ1MCtDRHlDaXE9P2lUbWVeNF4hZSRmIVohZlFxNSNWPyRqaF47
JlpmdjYwWC1nZWlfQF4lJD1ZVFAtOwp6fDJjVGprRVJ5JC1IaHBhM31SXmN3fi0wa2FkbSFjX2sq
YGUmakVOOT81MGQqMiV+fDRnMmJtJF9UZSFIYTRxVF4KenRrZjZvSipMVzIxN1VyNnZ0TFNgbXA0
fD88UHlhI0NZZGx5UWtKKH1jOWtnPGx8PnR8KzNVd05iSDVMTXNzSWoxCnpJME5ldnlwSjl6b2lX
O3JtYmJHYkhoZV89WG9oT3UkQGlNSkxETjtOU2ZxJiooWXkhZVlIcTEpTn5LQmhYP0B9VAp6VlZ9
LVlzMnd8U2VgZHdYZ1V5dHEzXjk2VGQ2NDItSCtpbSM/PjdueDBYdkhsUkc5LWdKfFVfQz1rWkl4
ZCVgS14KekJYPlk/UWt4SGhqdXBnQzRpcEgpKG1rdCp6WjUoUmpfcWkpJiUyKE9gTkM7bFE2NFNL
YE4+ejN2PTE7d1NGYm9sCnpjLW5ocEQqKUZwO2tldip8QjM7bVV1U0orOEZVQ2poaUp0JiNWaT4p
O30pb3tPbzQybDs5OGAmZ0cwOCQrUSs1Iwp6aFdpaiMwN3Y3ZV9gMl5XPnlQQ2w5cmFCeylae2da
YiZJYGU0dyE2dkhlSVY8SVMoRmY4bXFEUEY/MjlGR0dgd1IKejJAVjdZVWIwdmJfVHpGbXpqcDs+
M1kyKjFiJExlLVp4IShvKUFRfj9sbE81ZHFDOXUoQmc0RU47Szh5I2hFQjxFCnpGeStHc15NND5P
S3M5Km9NYWNsI3pEZzc3VHZSWTJocGR5S202YHh2I19MX2Y7T1ZQMzxILT9sK1ZQVmNMK1JCTwp6
KWV+ZFBtJWFrNExUY1QrMHlEbC1rZjVtOHdlaWo5c2BoKXRNcF9eaUxKUHtiN1E+clRDaHBgKHhA
czlqX1BWMHwKemttPUt6XztaakBQKSE2IWRtbyhhdXRGZmtFZFRTcnwzM2RpOzZEV1paJGJiTHtG
XnBwaWtMVj09dnUxcGQjeHVjCnpFMzM0U0I7IStSXkNJKDAlOEVTJFF7dWc9PVRTOHwmc2ZDa3pj
YEltQGc9e28qez1SIUB6fVhhOEZCcmk7JnI7UAp6c0xydWcwX2l1QXRjS3c0JnswLWFIWF9TVWtR
LTFhd1UzSWdve01DKEUlangyP0hKbFJZJWZYZTlhNTNEfE1BPnkKenlDTnpvWVFLbj91eT5SfVkq
O2Nlb3Q8fkwtcjx2QmpsT3FQY3dkQ3RtSCpeNWdINzJ9N1Z6VEA3eD1PJShJMktuCnpKfHRscUBR
ZHwtX2FaYXZPMjZ1Rz5ATypNYj5XNnluO2NmaElTKS12ViF9OWw0OUdgMlJpbDRmTGQhRXw7U0dD
ZQp6IVM4PmJzYExqUGslTHhAcnxMeSFlS2hBJVAoXiozTkJobnlJdiMzZTN1eXVSTSYjb3ZtbW5C
MXB2TzxNTWpaeUwKejVfNmpUI3ZvTUtkcHNWTE55alNqWTIhUTBFSEZwenMzZ1hJUWdUYlBXJiky
a0NqQz9zVEc/bmdGY2hsYSktbWVZCno9JXR+eit4WXRJVyozPns1fnUoXy1kPk1memhMMXl7T3NL
RGFHM249Wk00NXpqQChYY09naCpxJk16IXtLQDZKTwp6QztpR2l7PmwrfWUzbjs4c0haUSFOeHt1
Yz5qRCUxQVkwWWM3cDY/VkNtZT9qOVAwYlI8SVl1cXlONFcwaXt5alYKemE8SFhmbzh9Zk9ja3FN
V2RmTm1ORCgtIVNUQyghRUYlV0g5PWlOSjJIMSVsYHJHbDlBbHA+TGUwIT14TnspQUQ2Cnp4VVpn
PFpKNjxxLTUoYmp0I1BQSUYqY2d4K3E1NzJDTUEmNkBIby1iSEBeaUo2VzI3fDh8Nn1gT2BadEtI
MXBrPwp6RlZGTz05O0ApSEdWfFlmWjs2Tk0+KVc/UENhMXtRQStpU3IrbDNCMG40byVrKn5IXyZg
fGtvKmktSmdtKzZeYzEKejlVPGEpalZ9R2MoRyNiVShyMV5IPkcrdD5xWTZxQE1RbDJJemRub2I+
TzBNfUwhX3tWM204fH5rNSFgSU8kSUp2CnoqYzFYYUFiSF5Ba0wxcXAwQChKKUczVHhva01UZ2xU
SSgtZDBuOGkrXmxqKWdTdnZwRW5FWExyNy1feUomPUElQAp6dkpjcU4mRnFfTmsxTFpobWpqWTNX
JHFvPVlWT3V0PXglcntlPXRkZz5nd3tUKVh3ZmB1NHUtezZzRmdDcnwtRGcKemNCU1EkODtBPT5e
WDcqT0x6R1FlTCFrbHhQT2NOfGB8aktJeX1oMmZ0diR+fXVPV3coYDE+fmxNZW9QUj9SO0NPCnpP
cXdlQVVXQ3xgTHxpVVQ9OGorQCM4cGo5SFhRdGwoX0JkPjF9PmAxN1F8UV5gcCkkIWQkdXpxdUtX
bU5AN3pnaAp6Pmk2aTgmIVpwVGR9KmteKHlMY0JoSzRyfkNmP04mRH4zJD9APGQye1VhaXE9bHp2
I2Y9ZyheOWQjclNYYGhEVm4KemNtdF9PZnJZaVA3XkY7TVRPKm81OGlJKnhoO28tPnhkfT9VPURu
Kj83YiE+NnRfRD87ZnZJTnVgemVsNTVgYHlYCnozbCo3K0d7Xzlvd0M4MENYQzNjfF52SSYjJFQ8
NnBLeyZ3eW1FcEdVOXQodT1fWlJqUGkzaTxQeFJEV0xwQyFaUQp6KnpWTWd6azxLRHZzVFZ7V2ct
dj0kMCE8JFF5e3J1c280emcqbXRRYXVVeShfPD47QXgjMGxkTV5jPjJfQk9qUk0KejRkQyZrTEhs
V0NpX0RxbFBmbEc+aTlLfE08OXtSaDIxWjNjV1psKEI4d3skO3VkJmwyOCYqKG9NYEsleTA9Oz9i
Cnp5UzVBcmR5emU3RVVmO1J7X3s4KjhWXzQ0bHpiPHp5XiEwTHNeTTRjbktAJEh6MjFRSm9+U0xp
ZVd6ej9uc3VTNAp6O2Q3OHJhbypzWUtPdHY1VGI8ekYkeyRzcnt6aWB4ZDtLTyE/Nk56JW5XVE8t
QXYrdWpIOHxkJWhEPiZGdXM/SFgKeiViV1puSHtneVRXY2oyOVZqUzQjRjN8OUw/e2smQi13em8h
TiUhNkl2RDRIY21TKH4/SXxFemAhIzhPc0pqanwxCno9VDE/RTR3dzZzJnY7R1lFQTxadG9RfHtv
KXtqKDxkJWo+VzhkZCZGT3x8bjE5MH5ES1hHYX4xdShgO2ghYT5Vegp6Yz8+dWkmZ242QVBAbjN4
NnxBZTZyVjU4WUFGJEM3KzU4VUNoejVzVlhMZCEzXjhCIyVQbGRmNXY2dyZ0dUMpO0wKej9PU2hR
YSsmOTAjU24xJiFsMSpycGhKfVlfdV5OKkZeN1cjbiMoREtxNTwqeG9sNjJ6PFo8elVgYW5uUU4t
TGdGCno+ITNSKHYkQDFzeUNwcV5LY2QrZUllclZkczBMfmltZDJJTkk5PChTdWltaytyXihuMFRK
QmJGPG8lQEsoPzJhSQp6P1Iqe3plYyUwaHZ8SmdKY2V1K2tJc0JRJGBURytPbzFRK2VBdjRxI3Fm
cD1LaHt2MmEkMzZrUz0xbUFDeGIkdkQKekJvTGE4Y2MoMmlGMiFQP01mQytSU1B9REpXIzgqWnZ4
YCZALWtnbGJHSEZtMGd4eFozO2l5OFIqT0tQekVraG8+CnpgS2I3bVV9bGFvS2NveSU0bXNGJDl3
dkEwbWYmM3NpYnlQWUhINSFocmNHeTN6Nlg9d1V+YDhNe19GZTItdnBBWAp6c3d2R1Q2WnpuMnFN
NGd2T09YfSYmQ0FvYT9xQEA5ZmBpRSl3ZURwPD1OYjw+PSZ8VVQodEU5c3I0JDcyTH1hcCsKelZl
MENQb3QpTjJZbntxIT5sOWl0TU9mKF4pPCM4Kj5iIz1AZVMwKVQ/UGU0TV9QZEVvMCYwbVdzP1lG
aVJnPH16CnowWHFYTm5Ka1kzRkI9MyRlWGtHMUc3M0lsSjQlc0deYmsmTzMhJkwzRW1fN2FjIWlx
USEzaER4cHY8R35VSmc8Qwp6YFVvUE11anNxWjM1JGVuN3UqYjxlenlmb3ltUytwKXc7b05ffSQ+
eTxYMEp1Y2UpPiZVcn0oX2hHbGNpeSZeM3kKekZMaWJ2PlhVTmlhTkRlPU9rWXNsKlk3angjRHUy
NXI5c0VfbUkpRT5MZ0YwSFRWJnFgdTRNPmp0WTUjV2RjMyhQCnp3PjEoOz1NOSUmLVB9TEN0SzQq
Y2FCel5sWTx3Xit7YVAkX249QypoblJxWihnPyFHJXJERTl7amY8JjI9R15tdAp6Kkk9ZGc7NzBH
bkcwOElCVmBwVDl4aTZ0eFYpbWtCYHRxU196ISp0PGR1a0dFT1RRPmM8OUtwcGRqU2JXY0BCfH0K
enZWISpkKWRYP3gkajN6c29mI2cjX2EpT2NDVXpAWE5aV0NtMVB9KD5jYWtjJW1aangjQC1wNzJp
ZW5GM0VXMXd5CnotRXBvbSZmRlchXlYtO3EqZExQSjR4NiRDJDR3LUUpdHc3cmxAMXkpX0I8eDh2
dXk4bGIjK21PZEhTV049am81UAp6IVYxMjk4PGR9UGtLblFjMGd8K3Y2QCp0NFlBQ2VMXndYRHl1
V05hek1aRXAtU3FYPT9LbDs4YEoyI2BJMk5VMWMKemx7U0h8ZDhQUV98NGpZWnQjSSpJWEF5VHwt
clMtKUUwVWBATHw7IykyX1U0eFM4NW5+UFExTjVWQmZvPHlwbEtoCnpgUmw9TitFTmJQaFBCaFIx
V30qT3h1Z0JIUUxPUUMwNjloXmFGUyl9WHktfH5PaHBlMSVUKGBCIShMUW1DVmteRgp6Qz9gaGEx
XyRleGhme1NXLX42PjA/VExNSG14TD98RmRWQ04hOFExPVUqUDVBaXlLJVRFWGA0P2E5ci0hb2ZL
en0KekEmNTYldEIkI25temlQbThuWXt7bXdmal81XzUwMV5MTU4/dXc2WGtpRFE3UjYhMmtXKSgq
djdNIXUlWHpiU2tBCnpyTCg2Jl55UkBSXiY5ZHBkJmlfJVNIRDlfcWt1WUFDI05QKyVJcEQoJEJQ
X0MrQ3lkbT0tZH57PyleP050ZGZPYwp6TjRzWXlfUSg3eEpjY2w9OGd9JG1mdHpCNzhgSlZEbjtr
e0h7b0lSb29rX3haPDN+fFpFPXhoe2B5N1cwUmIqYnEKemkyMnY1a2VacGxkdkVjfTt4cmEjTnRP
Z3JrQSlYZGVaNm1BenZfSV5kTDkpT0hDcGJJPHhMIWtCV15oNjA3ZV9nCnplRX5oSmNIPFFrT3lF
fkRvdFRodntTeXEqb1dobkMmT1A9a2p+VChqN1hrP187Uk5xMUg5cStOUG1YKCVwPzwzOAp6elFF
KnctQGRzKj1TOFJ3Vn1DUVMqcHV7Ny1ObXB9NTN5WiRtSSV8ViZPNyM/M3NiTzdtc0V+ZTVZa2Zq
TFIrYlgKek1MJH1haHdAZH01Zi1rPW5LeUZ1elZHTkJpbkpTbTh0RHtadj1TQFZoQjNES0dJYFA2
KFV6NjYjQnVIdnBCQiRHCnpZMWhZXmEkN0B8YXhuUV52cVlmPSNUZVBXWVVYSXgxVEwmfnlOLUlz
MUNAcWE7JkdLbm9efk1lSnpIeH5hYEtCMAp6aENGZlNMT3h4LWxDPThxe1B9LSlwQVgtTygwOGda
eEVgeEB4cDF2U2J9Z2NRPkIzbTttITBRTUlEMW5xekJ8JSkKel9VVWYoYWgpblhyXyFkMVh0enJL
V09jVypMNVB9V0FvPUNpbGs8VWNpPTdjUTxRak8hZXI4O25PTk82RShkdiRgCnpYMjl8TmQ9ey1s
Nm8mOHk0VFZDSlduU3Zzam40ZFpvMjFhc0RjZklOQXhzZCVeclk+MVleXlMrdm59OVV3fXRuOQp6
QW12diprRDVaK1EkJWRpNjJeISVlQTIxI2cobG04OzwxfFZ1U3VoI0hNMUdnYnJhQGVXd3NoZ1Z6
UlI+a3pJe2MKelVVcWdQYWR8THdIPG9eSz80X0FkVz5ZJitgbzAzYTk5S21Kd3pSQjkoZ0JaZEEz
d2NTWUJNbmtPUS0qZnpmPTROCnpAQFRjVT43bT5CS1Ywb2k5KmI2XzZkYz01ISFlZX09MCgkejl1
enZDSUFsSitaVUFQekgpeClnKm5hS3F7Nn1sZQp6aDNUNEA/MUJRYFMqNTc8OTQ1MGdLbFctTipw
I2IhbTxPQTBUZCM+MjBrS199LV5JRExYcihzMGFGTnZAYVc/Tm8KeiRON1FXI2ZHRUJJdi0hJEA1
Qy1BZ1MlMGdOI2B3Rlo4emN+JTNqWDQ+OyV3SSRVV2VGRiVSTjlHUzNLeUt+b3I4CnoyRHNsYUx0
PllGV2ZlLXRtU1JIZzJRTW81RXpXM34kSFN1fT94LWFTYnNRKSY8eUtVMXpnc3pEejQ9UTtsOVlY
Twp6Wj9uTlghOzF4dmVOQENHUzlWKyEpTnJfIVFzLSpzRWs7fXxFJntXQCkpTChWbDk7Z2BsMEFo
PyRuM0ImTVpvRlUKejV0MGBjdG92cG9gbTA8VFVMO0ZNNCY8cUshfl9MZUd4R2JFMk9SN1FUWTYw
VUZ3S3BxcjxTXklXUXx9S1lYPDM9Cno1aFluSWNSeDExclRHTVled2lXR0BKPEdhYzUhKiQ9TCFQ
QF9OQFZne0toM1JTPCFZJnVBTyF+bkpGam10cV84Ywp6ZShje0gwYH1SKzxIPTxgNStacS17YFBu
bWxnek0lUEwwd2Exeyp3JmU0Sl95TE1VTDEmKDNqXyhsMVAmTF5mYnwKemkkbi08T21oK0RgI1Jw
VFJSbjdmaGp6QE9feCRSQnszcWhrKHBpX15xKWhUK1g0ezlDVlQpcl4jfk9MYURoS0NVCnohQiE1
eGFUWTA7ZnkhTH1WezRSJnRsdihqX3xaSmQkQTF9Tjt4WCRyIUxqPnJHMUpkJTw/TjszO3p3Sj9Z
PVBvYwp6NkpDQ1RePyR5bWt4TWtLbiN4JHByYmlBcEJ4aXIhOTRZbTNzSGRQaTJLcS13PD81QVYq
cH48TGRSU2Bkez9LPWIKejdgUUBHV25EQ0tVIT1zUnEkRDFwSnktcDV0eTtVOzN+T0tjZ3EyfEp7
ajZMM3JaTzJjPCNEJCRXfWFKNFJWUDVZCnp3P3EhflhETmdDY0gmaVpBNm90V1c4eUpEVnc+U3JO
bDh1SmlYYTNnMH1TVWlxZjtrZVBIajBrKXl6ajVpI1Rzcgp6dmtEKTRjbmFHYEd8QH1UJShnfiRu
VWJkXz1BRjdLRD1UR28rWjJqP24pOT5hRil8TzhJZWhmaXptd05CXyN5PCoKej0pR21BeXIhM3pt
eGtvPit8Qy0yUllybkUzYDR2T1FfOyFTPm1NSUtASmtsZ04mcT8+e2B1Xkp1QzhnRVRVS2tPCnpp
P3M5YSFBYD5tO3ooOEZ1b0JKfmk5MSs3amAoTTQ/MVc3ZENucVB2P08hdCYzc35ZNj07UzArOV9H
SCg8Myp9Ngp6M0tAPmkzLWVgQW9IRTkrKHBmQUBAS0pIVSR1ITUmP347cTFHRndxKlc+cmNZQkRe
WE9rTmNGKHQ+PWhTTnVoQHgKemV5Ylo4YE5mdTh2fChNSyk4Pn0tQV9QS3Y+KlZoTz8yQkA+eDJV
Sn55WHE7bE02PF5nQENGR3FqZkVLaDt8ZHdXCnorRz9gPGBEO2d+SmB9eWNCJTNuYjZsJU5sQlck
aUFYIUJqOSh+V19ianNkMHRoLV4wazk7MVFlOHRFVFM7PF9wRwp6K0V2VlBKYzt0O1U4Jl9fdjw0
cmFQPU93PS1TfXdJazlUTGhNdStoRDFRcipwQnZTQD9JWmBWM3d4JUZ+TFBaaCgKejhtS2pLd0M2
bEF7P1pTS1QhMkUySDNTN3Qpb1dDWkFNSjQqPU1VYEpgezViV2oxTW4oSUlNYmlDYllDJTxQZWlO
CnpRTVhJUzxpU2QpZ0djLTZHV1UoV3ZRb2RFajYkPW03WVMmQ2d1TkpuUEpIZnFrYT9xVkI3bDUr
KXlLbnFgOGB1IQp6UHtXWlZLKWxlYDFgMnsobnkzRSh1Yyt2TGxPPUk3IU1PKzVVbjtKbVZ+UCE4
JFNFazA1KWQkTGgzKlRaKFFNQXoKel8yWlQ/TGNje0VHVFM5Pih+QCZLNjB2d1NVbm1aQEE3bURA
eTtPWGR3Um04Y3QwYE41eElhZCQ9TnlgSCpXRCowCnpSa2BXQTFGSHgyTE5Cci1tVVg5d01VMnhJ
Xm1Xc0w1dFVjMjZUQ1lvY1kxdHxpQkBacmlvS2JrQllfamZfLTNoTwp6SkBAeURveTV2Z3JfQjhK
IUNYUDZfNEw9T05tYUpMemZVbzt7ejtJcHhDMnM+aiV+WUUrdXp5YklnMHR6QE8qVzsKekgySWlW
TyVjPmpIRzghNTkqU1hWNiUhWDxHKnltIzV5TEpFaklVTkV3O20lbjI0N3VySF95PiZ6Zj82SS0o
ZUZWCno3VDJRUUhrcShLeUgwdk5OJFJnQzk0cjEzdTx4P3xVNnczPXBrOzR3enhpSEdlcm1wPzNj
Z3xnVVJ6b0dKRXBNIQp6anFWejEqaFNLZjlnenM7LUlPU25RcD90RXp+REt+N04qUX5oUnA+PENg
fF9raHAte3IpeVhvUnZjO307MDZjPD0KelEjckVKd3AmXyRGPnIzeT1oZXV5cThseFojeGJkZnVF
OGloLXNDYjF2dT1zSyE5bCR0c349ekFuP0BWJmIqPXpJCnpYQkdCV3RYZ0UyZTVHaClZK1BuQGNv
ZiFAWEAtM1c+T3djWW14PXtqaGJ8UiUxUnYzcXh8NG5qbDZsKHU4OUteVgp6dDIjWEolZUl3OGsl
eVFKdmtHMW5fdWItWXduYFZMKEcqYnY5dzA0RnR+aiY1dih+e2R3ZUtCUClSS0VCVChPZFQKej1z
e1RiU1JXfn5ySVU5dyg4dkRXVStWc2k8TVNaV2thT1V+Y2tYe2JEVEpIVHs5VStlQEtAfUMtejRZ
VytWNEQlCnpwI1pvb2Qwb350K0hNcGQtPG9OSHU7ZnYxe31PZ190XkR7S29HbkBTUXIxQDZmdXg8
ISViYUJwIzttNWNfVDlUWAp6TWU2KV9EUVVeSiskIXV6aHJOOD0jODZ9Qj9vVTc3ZDVwKkI3bUBw
RyVqZXA4YHBlUHhaUFdhWGU5N3lrYjdANyYKeiM+VTE4Nz15YGFMTmkwfGB2P3YtNC1YSFU0MG01
Jit8RypVWUNjY2JiSyllezxHNnt3K3kjfXRQTyo4SzNJRVFpCnoocUclTiFvZDNhNnl4X3hqJl9j
bkMoPTZDdHxoPSYkcV4xay1JJDQ8Y0BMJWx2NE9qcVQ+d0JHQG5TKEBZVCMycgp6JTN6YDZYc1A3
VEYodDx+ZndAWC1BJSYkI3ktQi11dUJmfT0wWmAkS08hIypELTxNNVclTzNLe0s7Q1d2XyZCOU4K
ej0lKSRSIyowekZGYihqVFM0eyhtZVFfPEN0SnxWOGU9KUYtOW9Zc1VgR2IqfGZnPHklZ1R1eDhQ
YXRzRndFZys5CnpKWEk3IyRLcT9DQT9jPXMkVlJOZ0sxfWlwMm5nKThMKj17dlAkPlJLR2luMU1N
T2h4cGF8dmJsZT1nXn42WlVXYAp6ZW44fjc/PStqKUJNTj1jN0pUb3wrM3MjXzwkN3J2M1ZqPUJs
aml4OyZ0djkxdjE2M3ZQX3s4KjgkPXdVSSZoWUcKemNSRVAxKHJHSDhxaUVPV3EjTzVqV3FKSjND
b2Y+ODMtWGxAaDkqNCYhV1EybT0wTSlxeHgqJnkoY01gbEJ7TVYjCnopQnJvJFR1aGNGI3x+fG14
ZzJ6TC00eXFBKz9URjIxNTVuN25SXnt1KG9VSW03R3tDbDRKY19STys9blB4Xm9gcAp6RjlJbC1G
TFNwbjI1I2B1MGhtVXIlZjktMEVwZEo1UUJ7OGVmNTV7ak5fV3MpbFdvd3dNQUo3YWAjWXZSWXJv
YTIKemolbyl5RUleKm83NXxhZzRzYGxAM0o7al8jSHZzakVRUF5ebzd6UVBtUUx6aGpDez5zPCl6
UE5TaEZgZGtHV0c+CnpTakpvfilGV3lgeWlRPjlDUWhiPHZmMX4mSVI3WUxRaF89az1LXz8mMkBO
fD1sXm9LYD02REN9QDJGMSVodUdRSwp6d0opPj8qZn1eNXlkOTRONCtrMnw4X0xVOSlkek9nP0E4
YFlIeVZ2SSEyJFZ1b2d5SU5lfUE0STY4c2JGTklpWkQKelF2U35tel9EK3dxPzVaWkVUfHlZP31F
MXZYdShuSnt+cjRma3BDPj98MkFKWnFUajtEaE57SzZvXjBfI1JHdylsCkpWeEMmT3tYZk5+djZ9
ekAKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBhL2FwcC9yZXMvdmliZW1pcy5z
dmcgYi9hcHAvcmVzL3ZpYmVtaXMuc3ZnCmluZGV4IGMzZjNjODE5Li43MTE1YzMzNiAxMDA2NDQK
LS0tIGEvYXBwL3Jlcy92aWJlbWlzLnN2ZworKysgYi9hcHAvcmVzL3ZpYmVtaXMuc3ZnCkBAIC0x
LDE5ICsxLDcgQEAKLTw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rpbmc9IlVURi04IiBzdGFuZGFs
b25lPSJubyI/PgotPCEtLSBWaWJlbWlzIGJyYW5kIG1hcms6IGEgY3V0LWdlbSBkaWFtb25kIGNy
YWRsaW5nIGEgcGxheSB0cmlhbmdsZS4KLSAgICAgRHJhd24gZnJvbSB0aGUgZGVzaWduLWtpdCB0
b2tlbnMgKGRvY3MvZGVzaWduL3JlZGVzaWduL2xvZ28vUkVBRE1FLm1kKToKLSAgICAgZGlhbW9u
ZCBoYWxmLWRpYWdvbmFsIH4zNyUgb2YgdGhlIGJveCwgc3Ryb2tlIH43LjglIG9mIHRoZSBib3gs
IGZpbGxlZAotICAgICBwbGF5IHRyaWFuZ2xlIH4zMCUgdGFsbCBjZW50ZXJlZCBpbnNpZGUsIGFj
Y2VudCBncmFkaWVudAotICAgICAjNkFEREU3IC0+ICMyRkM2RDAuIFRoZSBzb2Z0IGdsb3cgaXMg
b21pdHRlZCBzbyB0aGUgbWFyayBzdGF5cyBjcmlzcCBhdAotICAgICB0aGUgc21hbGwgc2l6ZXMg
dGhpcyBTVkcgaXMgcmFzdGVyaXplZCBhdCAoU0RMIHN0cmVhbS13aW5kb3cgaWNvbikuIC0tPgot
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNTYg
MjU2IiB3aWR0aD0iMjU2IiBoZWlnaHQ9IjI1NiI+Ci0gIDxkZWZzPgotICAgIDxsaW5lYXJHcmFk
aWVudCBpZD0idmJBY2NlbnQiIHgxPSIwIiB5MT0iMCIgeDI9IjEiIHkyPSIxIj4KLSAgICAgIDxz
dG9wIG9mZnNldD0iMCIgc3RvcC1jb2xvcj0iIzZBRERFNyIvPgotICAgICAgPHN0b3Agb2Zmc2V0
PSIxIiBzdG9wLWNvbG9yPSIjMkZDNkQwIi8+Ci0gICAgPC9saW5lYXJHcmFkaWVudD4KLSAgPC9k
ZWZzPgotICA8cGF0aCBkPSJNIDEyOCAzMy4zIEwgMjIyLjcgMTI4IEwgMTI4IDIyMi43IEwgMzMu
MyAxMjggWiIgZmlsbD0ibm9uZSIKLSAgICAgICAgc3Ryb2tlPSJ1cmwoI3ZiQWNjZW50KSIgc3Ry
b2tlLXdpZHRoPSIyMCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIvPgotICA8cGF0aCBkPSJNIDEw
NyA5Mi42IEwgMTA3IDE2My40IEwgMTY4IDEyOCBaIiBmaWxsPSJ1cmwoI3ZiQWNjZW50KSIKLSAg
ICAgICAgc3Ryb2tlPSJ1cmwoI3ZiQWNjZW50KSIgc3Ryb2tlLXdpZHRoPSIxMiIgc3Ryb2tlLWxp
bmVqb2luPSJyb3VuZCIvPgorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmci
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
InJvdW5kIi8+CiA8L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXNvdXJjZXMucXJjIGIvYXBwL3Jl
c291cmNlcy5xcmMKaW5kZXggYjVkNGVlNzkuLmYzY2FlMGI0IDEwMDY0NAotLS0gYS9hcHAvcmVz
b3VyY2VzLnFyYworKysgYi9hcHAvcmVzb3VyY2VzLnFyYwpAQCAtMSwxMyArMSwyMCBAQAogPFJD
Qz4KICAgICA8cXJlc291cmNlIHByZWZpeD0iLyI+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMv
c3RlYW0vdmliZW1pc19wLnBuZyI+cmVzL3N0ZWFtL3ZpYmVtaXNfcC5wbmc8L2ZpbGU+Ci0gICAg
ICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pcy5wbmciPnJlcy9zdGVhbS92aWJlbWlz
LnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2hlcm8u
cG5nIj5yZXMvc3RlYW0vdmliZW1pc19oZXJvLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxp
YXM9InJlcy9zdGVhbS92aWJlbWlzX2xvZ28ucG5nIj5yZXMvc3RlYW0vdmliZW1pc19sb2dvLnBu
ZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2ljb24ucG5n
Ij5yZXMvc3RlYW0vdmliZW1pc19pY29uLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9
InJlcy92aWJlbWlzLW1hcmstNTEyLnBuZyI+cmVzL3ZpYmVtaXMtbWFyay01MTIucG5nPC9maWxl
PgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay0yNTYucG5nIj5yZXMvdmli
ZW1pcy1tYXJrLTI1Ni5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvdmliZW1p
cy1tYXJrLTEyOC5wbmciPnJlcy92aWJlbWlzLW1hcmstMTI4LnBuZzwvZmlsZT4KKyAgICAgICAg
PGZpbGU+cmVzL2NyaW1zb24tbmV0d29yay5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9j
cmltc29uLWJsdWV0b290aC5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9lY2xpcHNlLWNv
bnRyb2xzLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+cmVzL2VjbGlwc2UtaWNvbi5zdmc8L2Zp
bGU+CisgICAgICAgIDxmaWxlPnJlcy9lY2xpcHNlLXBvd2VyLnN2ZzwvZmlsZT4KKyAgICAgICAg
PGZpbGU+cmVzL2NyaW1zb24tYmF0dGVyeS5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9j
cmltc29uLWhvc3Quc3ZnPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3Zp
YmVtaXNfcC5wbmciPnJlcy9zdGVhbS9lY2xpcHNlX3AucG5nPC9maWxlPgorICAgICAgICA8Zmls
ZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXMucG5nIj5yZXMvc3RlYW0vZWNsaXBzZS5wbmc8L2Zp
bGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19oZXJvLnBuZyI+cmVz
L3N0ZWFtL2VjbGlwc2VfaGVyby5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMv
c3RlYW0vdmliZW1pc19sb2dvLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2VfbG9nby5wbmc8L2ZpbGU+
CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19pY29uLnBuZyI+cmVzL3N0
ZWFtL2VjbGlwc2VfaWNvbi5wbmc8L2ZpbGU+CisgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvdmli
ZW1pcy1tYXJrLTUxMi5wbmciPnJlcy9lY2xpcHNlLW1hcmstNTEyLnBuZzwvZmlsZT4KKyAgICAg
ICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstMjU2LnBuZyI+cmVzL2VjbGlwc2UtbWFy
ay0yNTYucG5nPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVtaXMtbWFyay0x
MjgucG5nIj5yZXMvZWNsaXBzZS1tYXJrLTEyOC5wbmc8L2ZpbGU+CiAgICAgICAgIDxmaWxlIGFs
aWFzPSJmb250cy9Tb3JhLnR0ZiI+Zm9udHMvU29yYS50dGY8L2ZpbGU+CiAgICAgICAgIDxmaWxl
IGFsaWFzPSJmb250cy9NYW5yb3BlLnR0ZiI+Zm9udHMvTWFucm9wZS50dGY8L2ZpbGU+CiAgICAg
ICAgIDxmaWxlPnJlcy9zb3VuZHMvbmF2X3RpY2sud2F2PC9maWxlPgpkaWZmIC0tZ2l0IGEvYXBw
L3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2VzLmNwcCBiL2FwcC9zZXR0aW5ncy9zdHJlYW1p
bmdwcmVmZXJlbmNlcy5jcHAKaW5kZXggZDY5YTkxMzEuLjYwMjJiMjUzIDEwMDY0NAotLS0gYS9h
cHAvc2V0dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuY3BwCisrKyBiL2FwcC9zZXR0aW5ncy9z
dHJlYW1pbmdwcmVmZXJlbmNlcy5jcHAKQEAgLTIyOSw3ICsyMjksNyBAQCB2b2lkIFN0cmVhbWlu
Z1ByZWZlcmVuY2VzOjpyZWxvYWQoKQogICAgIHNlZW5XZWxjb21lSGludCA9IHNldHRpbmdzLnZh
bHVlKFNFUl9TRUVOV0VMQ09NRUhJTlQsIGZhbHNlKS50b0Jvb2woKTsKICAgICBlbmFibGVIZHIg
PSBzZXR0aW5ncy52YWx1ZShTRVJfSERSLCBmYWxzZSkudG9Cb29sKCk7CiAgICAgdWlTaG93SGlu
dHMgPSBzZXR0aW5ncy52YWx1ZShTRVJfVUlfU0hPV0hJTlRTLCB0cnVlKS50b0Jvb2woKTsKLSAg
ICB1aUFjY2VudEluZGV4ID0gcUJvdW5kKDAsIHNldHRpbmdzLnZhbHVlKFNFUl9VSV9BQ0NFTlRJ
TkRFWCwgMCkudG9JbnQoKSwgMyk7CisgICAgdWlBY2NlbnRJbmRleCA9IHFCb3VuZCgwLCBzZXR0
aW5ncy52YWx1ZShTRVJfVUlfQUNDRU5USU5ERVgsIDQpLnRvSW50KCksIDE1KTsKICAgICB1aVNv
dW5kcyA9IHNldHRpbmdzLnZhbHVlKFNFUl9VSVNPVU5EUywgdHJ1ZSkudG9Cb29sKCk7CiAgICAg
ZGlzcGxheUhkckNhcGFiaWxpdHkgPSBzZXR0aW5ncy52YWx1ZShTRVJfRElTUExBWV9IRFJfQ0FQ
QUJJTElUWSwgdHJ1ZSkudG9Cb29sKCk7CiAgICAgaGRyVG9uZW1hcHBpbmcgPSBzZXR0aW5ncy52
YWx1ZShTRVJfSERSX1RPTkVNQVAsIGZhbHNlKS50b0Jvb2woKTsKZGlmZiAtLWdpdCBhL3BhY2th
Z2luZy9mbGF0cGFrL2lvLmdpdGh1Yi5uYXZ5YXMzMjEuVmliZW1pcy5kZXNrdG9wIGIvcGFja2Fn
aW5nL2ZsYXRwYWsvaW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AKaW5kZXggMDQ1
YWRiZTYuLmYxMmRhNWQ0IDEwMDY0NAotLS0gYS9wYWNrYWdpbmcvZmxhdHBhay9pby5naXRodWIu
bmF2eWFzMzIxLlZpYmVtaXMuZGVza3RvcAorKysgYi9wYWNrYWdpbmcvZmxhdHBhay9pby5naXRo
dWIubmF2eWFzMzIxLlZpYmVtaXMuZGVza3RvcApAQCAtMSw2ICsxLDYgQEAKIFtEZXNrdG9wIEVu
dHJ5XQogVHlwZT1BcHBsaWNhdGlvbgotTmFtZT1WaWJlbWlzCitOYW1lPUVjbGlwc2UKIEdlbmVy
aWNOYW1lPUdhbWUgU3RyZWFtaW5nIENsaWVudAogQ29tbWVudD1TdHJlYW0gZ2FtZXMgYW5kIGFw
cGxpY2F0aW9ucyBmcm9tIGEgU3Vuc2hpbmUgLyBBcG9sbG8gLyBWaWJlcG9sbG8gaG9zdAogRXhl
Yz12aWJlbWlzCg==
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
