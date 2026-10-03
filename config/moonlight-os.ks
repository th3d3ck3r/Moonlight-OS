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
VERSION="0.1-dev"
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
                emit(items=items, status='Ready', done=True)
            except (EOFError, KeyboardInterrupt):
                break
            except (RuntimeError, ValueError, KeyError, subprocess.SubprocessError, pexpect.ExceptionPexpect) as error:
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
iVBORw0KGgoAAAANSUhEUgAABAAAAAKACAIAAACNH502AAEAAElEQVR42uz9+5NsWXbfh63H3vuc
zKq6j+65jQHIAUCRMky6ySEBkJLDlEIOhxzQDwoSDNsMWbJNyQqSCooIUQra/hP8oyP0N9gOhR0B
/mRHyGGbsCWTIAePIUYQ9CAIYADMdPd030dVZZ5z9l5r+Yd1TlZmVlbde7tv9/RjfeZGT1a+8+Sp
e79r7+/6LmTOEARBEARBEATBVwOKQxAEQRAEQRAEUQAEQRAEQRAEQRAFQBAEQRAEQRAEUQAEQRAE
QRAEQRAFQBAEQRAEQRAEUQAEQRAEQRAEQRAFQBAEQRAEQRAEUQAEQRAEQRAEQRAFQBAEQRAEQRAE
UQAEQRAEQRAEQRAFQBAEQRAEQRAEUQAEQRAEQRAEQRQAQRAEQRAEQRBEARAEQRAEQRAEQRQAQRAE
QRAEQRBEARAEQRAEQRAEQRQAQRAEQRAEQRBEARAEQRAEQRAEQRQAQRAEQRAEQRBEARAEQRAEQRAE
QRQAQRAEQRAEQRBEARAEQRAEQRAEQRQAQRAEQRAEQRAFQBAEQRAEQRAEUQAEQRAEQRAEQRAFQBAE
QRAEQRAEUQAEQRAEQRAEQRAFQBAEQRAEQRAEUQAEQRAEQRAEQRAFQBAEQRAEQRAEUQAEQRAEQRAE
QRAFQBAEQRAEQRAEUQAEQRAEQRAEQRAFQBAEQRAEQRBEARAEQRAEQRAEQRQAQRAEQRAEQRBEARAE
QRAEQRAEQRQAQRAEQRAEQRBEARAEQRAEQRAEQRQAQRAEQRAEQRBEARAEQRAEQRAEQRQAQRAEQRAE
QRBEARAEQRAEQRAEQRQAQRAEQRAEQRBEARAEQRAEQRAEUQAEwVeEf/VP/el/9U/96TgOQRAEQRBE
ARAEQRAEQRAEwVcCZM5xFIIgCIIgCILgK0LsAARBEARBEARBFABBEARBEARBEEQBEHw2/JWf/gt/
5af/QhyHIAiCIAiCIAqAIAiCIAiCIAg+PtEEHARBEARBEARfIWIHIAiCIAiCIAiiAAiCIAiCIAiC
IAqAIAiCIAiCIAiiAAiCIAiCIAiCIAqAIAiCIAiCIAiiAAiCIAiCIAiCIAqAIAiCIAiCIAiiAAiC
IAiCIAiCIAqAIAiCIAiCIAiiAAiCIAiCIAiCIAqAIHg1/vjXnvzxrz2J4xAEQRAEQRQAQRAEQRAE
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
FfzFe+Ovr3bu1End3rtv33sfvL/gp5927d59+vTp+vXqJSUlJSYmtmvT9qwePc7q0ePkSep/EKUY
+ycBABCZgwcPbt+xfdiQoe3atu3ft++y5cttn9awYcMLzj1PRA4dOrTgp4WTr7o6/F08/OCDRoS0
/8CBG2+55ZcVvxqPFhQUHD9xYsOmjW//650H77vvnjvvEpG42Ni3/va3YWNG79m7t5rsQtm3f39y
cnKduLjWaWmTr776vQ8+qNFn/7577jGi/6zs7D8+cP+MmTN1XTc/Z09u7p69excvWfLCX14+q0eP
u2+/Y/zYsfziVMIXr3evXmNGjVK3Z82Zc/3NN+XllZSWncjJOZGT89uuXStXrfrf119xLgD4owQI
5axnWpueaW04DrXDJ599pm5cPjFgAfHF48bVqVNHRD7/8kuXyx3+xs/u3eeu225XtzMPHhx3yQRz
hGRWUFj4zPPPP/P880bK8Y+/vVFNdmE4dOjQ1A//44me774nPj6+5p73Xj17PnTf/er2gczMcy68
4NvvvrNE/xar16y5/uabrph8zf4DB/jFqegv3rmjx6gbhUVFd9xztzn6BwASAABlMv27706fPm2O
8v1dMelydePTLz6PaON/vOsuh8PzJ+iue/+4e8+e4M9/7Y2/Lfhpobo9oF+/gf37V4ddmL3y+usq
FGvWrNlNN9xQc8/7fffco46b2+2+9Y7bw+9RM2vOnNff/Du/OBX9xUvzFtpt277t6LFjHHAAJACo
Yqv27l61dzfHoXbIy8ub9u23YqrzsWjXtm2/s88WkbXr14ffBVJE0tulnzN6tLo9e+7cufPnh/Oq
R554wrj9h5tvqfJdWBw5cuSf773rCftuv6N+/fo18aS3T083Bphn/vDD4qVU0EamEr54Tqfn3+6E
unU54ABIAACUs0+84/qXT5zo/+gV3tKgTz//LKLNjhoxwuhe8v7UqWG+avOWLcZUhOFDh8bExFTt
Lvy98eabOTk5IpKUmHjbLbfUxDM+Ythw47j9e8oUfgUiVQlfPKPOql3bdpFepwIAEgAAISxesmTf
/v0iMmLYsOTkZPNDmqZNvPRSESkuLv7iq8jmGhpRi8vlMoofwjFn3lx1IyEh4YyMjKrdhb/jJ068
+c+31e3bbr4lsXHjGnfGBw8cqG4UFRUt/XkZvwKRqoQv3uy5c43bH0+Zescf/qAa/wMACQCAcqDr
+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
tv8HWXxh4i+WI7EAAAAASUVORK5CYII=
APOLLO_BACKGROUND
base64 -d > /usr/share/plymouth/themes/crimson-apollo/apollo.png <<'APOLLO_APOLLO'
iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAACMElEQVR42u3bsU4UURQG4Ls3q7WF
DyDEwkqbRZutiAQTOhP1BazpIZYkhsrEglD4AlpYk5hY0SjbSGGIIcoDUFDRYkUjKLuDusz831fP
JjNz/3POnd3ZUgAAAAAAAAAAAAAAAACgXY72fpwkX39NX/xvX/eiQ1D1gGw1vfpLKSW5C9T0xT+V
GgIjwAhQ/cldoFr87BBUi58dAnsAewDVn9wFqsXPDoERYASo/uQuUC1+dgiMACNA9Sd3gWrxs0NQ
LX52COwB7AFUf3IXqBY/OwRGQLheF6p/2udw485Ma+9jv+0B2F99pYyNgOaOr1+Lvv5+Vy7kxeeP
jT63Olxs/Nm1+/M6AAKAEXC13Bs8+GfHfxl9EoA2eLf9Yazjlh4+GfvYp8MFIwABQAAQAGwC/7fD
l2/O/d7/YGd3aud0a+5uOZw7e143V573dAB0gL/pvKoaPV6e6q+BBzu7ZfD+dWt/DdQBbAIRAAQA
AUAAEAAEAAEgRGdfCJnk5Y0uvugRHYBJXttaGi527jUvIwABQABI2gM0/ZfOcenGP3x0ABrpJVzk
/tZ245dGbj8advoe9RMWf31z41Kf73IIjABPAar/T9Y3Ny41QgSgxYufEIJq8bNDYA/gMdAjX/Kj
YS8p7d8Hz8YOx+zobcS9MQI8BuYYt6pTql8HQAAEIMxF7T2p/esAZAbgd1WeVv06AAIgAKF+bfeJ
7V8HQAAIN8kPRDoAAAAAAAAAAAAAAAAAV8ZPnvcvsamkMCkAAAAASUVORK5CYII=
APOLLO_APOLLO
cat > /usr/share/plymouth/themes/crimson-apollo/crimson-apollo.plymouth <<'APOLLO_THEME'
[Plymouth Theme]
Name=Moonlight-OS Crimson Apollo
Description=Black and crimson lunar orbit with an Apollo-inspired spacecraft
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/crimson-apollo
ScriptFile=/usr/share/plymouth/themes/crimson-apollo/crimson-apollo.script
APOLLO_THEME
cat > /usr/share/plymouth/themes/crimson-apollo/crimson-apollo.script <<'APOLLO_SCRIPT'
# Moonlight-OS Crimson Apollo boot theme.
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
    ship.SetPosition(origin_x + (512 + 170 * Math.Cos(angle)) * scale - rotated[index].GetWidth() / 2,
                     origin_y + (248 + 170 * Math.Sin(angle)) * scale - rotated[index].GetHeight() / 2, 10);
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
VIBEMIS_PATCH_SHA256=5cdb6bf95843c21fe383793ee24153fea241a46545c19da4aafb09be3ba87672
FRONTENDS_LOCK
base64 -d > /usr/local/share/moonlight-os/vibemis-crimson.patch <<'VIBEMIS_PATCH_B64'
ZGlmZiAtLWdpdCBhL2FwcC9hcHAucHJvIGIvYXBwL2FwcC5wcm8KaW5kZXggYzE4ODZhNDguLmMx
MGVkOThkIDEwMDY0NAotLS0gYS9hcHAvYXBwLnBybworKysgYi9hcHAvYXBwLnBybwpAQCAtNjMx
LDMgKzYzMSwxNCBAQCBtYWN4IHsKICMgY291bnRzKSBvciB0aGUgc21hcnQtYnVpbGQgY2hlY2sg
c2tpcHMgdGhlIHJlbGVhc2UuCiBWRVJTSU9OID0gIiQkY2F0KHZlcnNpb24udHh0KSIKIERFRklO
RVMgKz0gVkVSU0lPTl9TVFI9XFxcIiQkY2F0KHZlcnNpb24udHh0KVxcXCIKKworIyBNb29ubGln
aHQtT1Mgb3B0aW9uYWwgbGF1bmNoZXIgc3RhdHVzIGFuZCBob3N0IHN0YXRzLgorU09VUkNFUyAr
PSBtb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcAorSEVBREVSUyArPSBtb29ubGlnaHRvcy9j
cmltc29uc3RhdHVzLmgKKworIyBDb21waWxlIHRoZSBhcHBsaWFuY2Utb3duZWQgdXBkYXRlciwg
bm90IHRoZSB1cHN0cmVhbSBmZWVkL0FwcEltYWdlIGluc3RhbGxlci4KK1NPVVJDRVMgLT0gYmFj
a2VuZC9hdXRvdXBkYXRlY2hlY2tlci5jcHAKK1NPVVJDRVMgKz0gbW9vbmxpZ2h0b3MvbWFuYWdl
ZHVwZGF0ZXMuY3BwCisKK1NPVVJDRVMgKz0gbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuY3Bw
CitIRUFERVJTICs9IG1vb25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmgKZGlmZiAtLWdpdCBhL2Fw
cC9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmggYi9hcHAvYmFja2VuZC9hdXRvdXBkYXRlY2hl
Y2tlci5oCmluZGV4IDVlYjk4Y2I4Li42OWJlNDFjYyAxMDA2NDQKLS0tIGEvYXBwL2JhY2tlbmQv
YXV0b3VwZGF0ZWNoZWNrZXIuaAorKysgYi9hcHAvYmFja2VuZC9hdXRvdXBkYXRlY2hlY2tlci5o
CkBAIC0yOSw2ICsyOSw5IEBAIGNsYXNzIEF1dG9VcGRhdGVDaGVja2VyIDogcHVibGljIFFPYmpl
Y3QKIHsKICAgICBRX09CSkVDVAogCisgICAgLy8gVGhpcyBjdXN0b21pemVkIGFwcGxpYW5jZSBp
cyB1cGRhdGVkIHdpdGggTW9vbmxpZ2h0LU9TLCBuZXZlciB1cHN0cmVhbSBBcHBJbWFnZXMuCisg
ICAgUV9QUk9QRVJUWShib29sIG9zTWFuYWdlZCBSRUFEIG9zTWFuYWdlZCBDT05TVEFOVCkKKwog
ICAgIC8vIEEgc3RyaWN0bHktbmV3ZXIgYnVpbGQgZXhpc3RzIG9uIHRoZSBjaGFubmVsIOKAlCBw
b3dlcnMgdGhlIHRvb2xiYXIgYmFubmVyLgogICAgIFFfUFJPUEVSVFkoYm9vbCB1cGRhdGVBdmFp
bGFibGUgUkVBRCB1cGRhdGVBdmFpbGFibGUgTk9USUZZIHN0YXRlQ2hhbmdlZCkKICAgICAvLyBU
aGUgY2hhbm5lbCdzIG5ld2VzdCBidWlsZCBkaWZmZXJzIGZyb20gdGhlIHJ1bm5pbmcgb25lICht
YXkgYmUgb2xkZXIg4oCUCkBAIC01MSw2ICs1NCw3IEBAIGNsYXNzIEF1dG9VcGRhdGVDaGVja2Vy
IDogcHVibGljIFFPYmplY3QKIAogcHVibGljOgogICAgIGV4cGxpY2l0IEF1dG9VcGRhdGVDaGVj
a2VyKFFPYmplY3QgKnBhcmVudCA9IG51bGxwdHIpOworICAgIGJvb2wgb3NNYW5hZ2VkKCkgY29u
c3QgeyByZXR1cm4gdHJ1ZTsgfQogCiAgICAgLy8gTGF1bmNoLXRpbWUgZW50cnkgcG9pbnQ6IHF1
aWV0IGNoZWNrIG5vdywgdGhlbiBhIHBlcmlvZGljIHJlLWNoZWNrIGV2ZXJ5CiAgICAgLy8gUkVD
SEVDS19JTlRFUlZBTF9NUyAoYSBsYXVuY2gtb25seSBjaGVjayBrZXB0IHVzZXJzIGJsaW5kIHRv
IGFueXRoaW5nCmRpZmYgLS1naXQgYS9hcHAvZ3VpL0FwcFZpZXcucW1sIGIvYXBwL2d1aS9BcHBW
aWV3LnFtbAppbmRleCA2M2Y2NDVkOC4uMzgzYWRiNzUgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvQXBw
Vmlldy5xbWwKKysrIGIvYXBwL2d1aS9BcHBWaWV3LnFtbApAQCAtMTEsNiArMTEsNyBAQCBpbXBv
cnQgQ29tcHV0ZXJNYW5hZ2VyIDEuMAogaW1wb3J0IFNkbEdhbWVwYWRLZXlOYXZpZ2F0aW9uIDEu
MAogCiBDZW50ZXJlZEdyaWRWaWV3IHsKKyAgICBwcm9wZXJ0eSB2YXIgY3JpbXNvbkhvc3Q6ICh7
fSkKICAgICBwcm9wZXJ0eSBpbnQgY29tcHV0ZXJJbmRleAogICAgIHByb3BlcnR5IEFwcE1vZGVs
IGFwcE1vZGVsIDogY3JlYXRlTW9kZWwoKQogICAgIHByb3BlcnR5IGJvb2wgYWN0aXZhdGVkCmRp
ZmYgLS1naXQgYS9hcHAvZ3VpL0F1dG9SZXNpemluZ0NvbWJvQm94LnFtbCBiL2FwcC9ndWkvQXV0
b1Jlc2l6aW5nQ29tYm9Cb3gucW1sCmluZGV4IDUzYWZjYWY4Li5mMTIzOTMyMCAxMDA2NDQKLS0t
IGEvYXBwL2d1aS9BdXRvUmVzaXppbmdDb21ib0JveC5xbWwKKysrIGIvYXBwL2d1aS9BdXRvUmVz
aXppbmdDb21ib0JveC5xbWwKQEAgLTEsNSArMSw2IEBACiBpbXBvcnQgUXRRdWljayAyLjkKIGlt
cG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCiAK
IGltcG9ydCBTZGxHYW1lcGFkS2V5TmF2aWdhdGlvbiAxLjAKIGltcG9ydCBTeXN0ZW1Qcm9wZXJ0
aWVzIDEuMApAQCAtOTIsNyArOTMsNyBAQCBDb21ib0JveCB7CiAgICAgICAgIC8vIE92ZXJyaWRl
IHRoZSBwb3B1cCBjb2xvciB0byBpbXByb3ZlIGNvbnRyYXN0IHdpdGggdGhlIG92ZXJyaWRkZW4K
ICAgICAgICAgLy8gTWF0ZXJpYWwgMiBiYWNrZ3JvdW5kIGNvbG9yIHNldCBpbiBtYWluLnFtbC4K
ICAgICAgICAgaWYgKFN5c3RlbVByb3BlcnRpZXMudXNlc01hdGVyaWFsM1RoZW1lKSB7Ci0gICAg
ICAgICAgICBwb3B1cC5iYWNrZ3JvdW5kLmNvbG9yID0gIiM0MjQyNDIiCisgICAgICAgICAgICBw
b3B1cC5iYWNrZ3JvdW5kLmNvbG9yID0gUXQuYmluZGluZyhmdW5jdGlvbigpIHsgcmV0dXJuIFZi
VG9rZW5zLmJnRWxldjIgfSkKICAgICAgICAgfQogICAgIH0KIApkaWZmIC0tZ2l0IGEvYXBwL2d1
aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbCBiL2FwcC9ndWkvQ3JpbXNvblN0YXR1c0RpYWxvZy5x
bWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLjY4NzBmOWMzCi0tLSAvZGV2
L251bGwKKysrIGIvYXBwL2d1aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbApAQCAtMCwwICsxLDkw
IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1w
b3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFs
IDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgQ3JpbXNvblN0YXR1cyAx
LjAKKworTmF2aWdhYmxlRGlhbG9nIHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9wZXJ0eSBzdHJp
bmcga2luZDogImhvc3QiCisgICAgd2lkdGg6IE1hdGgubWluKDYyMCwgcGFyZW50LndpZHRoIC0g
MzIpCisgICAgaGVpZ2h0OiBNYXRoLm1pbihraW5kID09PSAiaG9zdCIgPyA2NTAgOiAyODAsIHBh
cmVudC5oZWlnaHQgLSAzMikKKyAgICB0aXRsZToga2luZCA9PT0gImhvc3QiID8gcXNUcigiVmli
ZXBvbGxvIOKAoiBIb3N0IGhhcmR3YXJlIikgOiBraW5kID09PSAibmV0d29yayIgPyBxc1RyKCJO
ZXR3b3JrIHN0YXR1cyIpIDogcXNUcigiQmF0dGVyeSBzdGF0dXMiKQorICAgIHN0YW5kYXJkQnV0
dG9uczogRGlhbG9nLkNsb3NlCisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdF
bGV2CisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBiYWNrZ3JvdW5k
OiBSZWN0YW5nbGUgeyBjb2xvcjogVmJUb2tlbnMuYmdFbGV2OyByYWRpdXM6IFZiVG9rZW5zLnJh
ZGl1c0RpYWxvZzsgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2U7IGJvcmRlci53aWR0aDog
MSB9CisgICAgb25PcGVuZWQ6IHsKKyAgICAgICAgdXJsSW5wdXQudGV4dCA9IENyaW1zb25TdGF0
dXMuZW5kcG9pbnQKKyAgICAgICAgcGluSW5wdXQudGV4dCA9IENyaW1zb25TdGF0dXMuZmluZ2Vy
cHJpbnQKKyAgICAgICAgdG9rZW5JbnB1dC50ZXh0ID0gIiIKKyAgICAgICAgQ3JpbXNvblN0YXR1
cy5zZXRWaXNpYmxlKGtpbmQgPT09ICJob3N0IikKKyAgICB9CisgICAgb25DbG9zZWQ6IHsgQ3Jp
bXNvblN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsgdG9rZW5JbnB1dC50ZXh0ID0gIiI7IHN0YWNr
Vmlldy5mb3JjZUFjdGl2ZUZvY3VzKCkgfQorICAgIGZ1bmN0aW9uIG1ldHJpYyhrZXksIHN1ZmZp
eCkgeworICAgICAgICB2YXIgbiA9IENyaW1zb25TdGF0dXMuc3RhdHNba2V5XQorICAgICAgICBy
ZXR1cm4gbiA9PT0gdW5kZWZpbmVkID8gcXNUcigiTi9BIikgOiBOdW1iZXIobikudG9GaXhlZCgx
KSArIHN1ZmZpeAorICAgIH0KKyAgICBmdW5jdGlvbiBtZW1vcnkocHJlZml4KSB7CisgICAgICAg
IHZhciBzID0gQ3JpbXNvblN0YXR1cy5zdGF0cworICAgICAgICByZXR1cm4gc1twcmVmaXggKyAi
X3VzZWRfYnl0ZXMiXSA9PT0gdW5kZWZpbmVkIHx8ICFzW3ByZWZpeCArICJfdG90YWxfYnl0ZXMi
XSA/IHFzVHIoIk4vQSIpCisgICAgICAgICAgICAgOiAoc1twcmVmaXggKyAiX3VzZWRfYnl0ZXMi
XSAvIDEwNzM3NDE4MjQpLnRvRml4ZWQoMSkgKyAiIC8gIiArIChzW3ByZWZpeCArICJfdG90YWxf
Ynl0ZXMiXSAvIDEwNzM3NDE4MjQpLnRvRml4ZWQoMSkgKyAiIEdpQiIKKyAgICB9CisgICAgY29u
dGVudEl0ZW06IFNjcm9sbFZpZXcgeworICAgICAgICBjbGlwOiB0cnVlCisgICAgICAgIGNvbnRl
bnRXaWR0aDogYXZhaWxhYmxlV2lkdGgKKyAgICAgICAgQ29sdW1uTGF5b3V0IHsKKyAgICAgICAg
ICAgIHdpZHRoOiBwYW5lbC5hdmFpbGFibGVXaWR0aAorICAgICAgICAgICAgc3BhY2luZzogVmJU
b2tlbnMuc3BhY2UzCisgICAgICAgICAgICBMYWJlbCB7CisgICAgICAgICAgICAgICAgdmlzaWJs
ZTogcGFuZWwua2luZCAhPT0gImhvc3QiCisgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0
aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcAorICAgICAgICAgICAgICAgIHRleHQ6IHBhbmVs
LmtpbmQgPT09ICJuZXR3b3JrIiA/IChDcmltc29uU3RhdHVzLmxvY2FsLm5ldHdvcmsgKyAoQ3Jp
bXNvblN0YXR1cy5sb2NhbC53aWZpU2lnbmFsID49IDAgPyAiIOKAoiAiICsgQ3JpbXNvblN0YXR1
cy5sb2NhbC53aWZpU2lnbmFsICsgIiUgc2lnbmFsIiA6ICIiKSArICJcbiIgKyBxc1RyKCJBY3Rp
dmUgbGluayBzdGF0dXM7IGludGVybmV0IGFjY2VzcyBpcyBub3QgYXNzdW1lZC4iKSkKKyAgICAg
ICAgICAgICAgICAgICAgOiAoQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAw
ID8gQ3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCArICIlIOKAoiAiIDogIiIpICsg
Q3JpbXNvblN0YXR1cy5sb2NhbC5iYXR0ZXJ5U3RhdGUKKyAgICAgICAgICAgICAgICBjb2xvcjog
VmJUb2tlbnMudGV4dDsgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVCb2R5CisgICAgICAg
ICAgICB9CisgICAgICAgICAgICBMYWJlbCB7CisgICAgICAgICAgICAgICAgdmlzaWJsZTogcGFu
ZWwua2luZCA9PT0gImhvc3QiCisgICAgICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1
ZTsgd3JhcE1vZGU6IFRleHQuV3JhcAorICAgICAgICAgICAgICAgIHRleHQ6IENyaW1zb25TdGF0
dXMuc3RhdHVzCisgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLnRleHREaW0KKyAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgIFJlcGVhdGVyIHsKKyAgICAgICAgICAgICAgICBtb2RlbDog
cGFuZWwua2luZCA9PT0gImhvc3QiID8gWworICAgICAgICAgICAgICAgICAgICBbcXNUcigiQ1BV
IiksIHBhbmVsLm1ldHJpYygiY3B1X3BlcmNlbnQiLCAiJSIpLCBwYW5lbC5tZXRyaWMoImNwdV90
ZW1wX2MiLCAiIMKwQyIpXSwKKyAgICAgICAgICAgICAgICAgICAgW3FzVHIoIlJBTSIpLCBwYW5l
bC5tZW1vcnkoInJhbSIpLCBwYW5lbC5tZXRyaWMoInJhbV9wZXJjZW50IiwgIiUiKV0sCisgICAg
ICAgICAgICAgICAgICAgIFtxc1RyKCJHUFUiKSwgcGFuZWwubWV0cmljKCJncHVfcGVyY2VudCIs
ICIlIiksIHBhbmVsLm1ldHJpYygiZ3B1X3RlbXBfYyIsICIgwrBDIildLAorICAgICAgICAgICAg
ICAgICAgICBbcXNUcigiVlJBTSIpLCBwYW5lbC5tZW1vcnkoInZyYW0iKSwgcGFuZWwubWV0cmlj
KCJ2cmFtX3BlcmNlbnQiLCAiJSIpXSwKKyAgICAgICAgICAgICAgICAgICAgW3FzVHIoIkdQVSBl
bmNvZGVyIiksIHBhbmVsLm1ldHJpYygiZ3B1X2VuY29kZXJfcGVyY2VudCIsICIlIiksICIiXSwK
KyAgICAgICAgICAgICAgICAgICAgW3FzVHIoIkhvc3QgbmV0d29yayIpLCBwYW5lbC5tZXRyaWMo
Im5ldF9yeF9icHMiLCAiIEIvcyBSWCIpLCBwYW5lbC5tZXRyaWMoIm5ldF90eF9icHMiLCAiIEIv
cyBUWCIpXQorICAgICAgICAgICAgICAgIF0gOiBbXQorICAgICAgICAgICAgICAgIGRlbGVnYXRl
OiBSZWN0YW5nbGUgeworICAgICAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVl
OyBpbXBsaWNpdEhlaWdodDogNTgKKyAgICAgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5z
LmJnV2luZG93OyByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0NvbnRyb2wKKyAgICAgICAgICAgICAg
ICAgICAgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2U7IGJvcmRlci53aWR0aDogMQorICAg
ICAgICAgICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAgICAgICAgICAgYW5j
aG9ycy5maWxsOiBwYXJlbnQ7IGFuY2hvcnMubWFyZ2luczogMTIKKyAgICAgICAgICAgICAgICAg
ICAgICAgIExhYmVsIHsgdGV4dDogbW9kZWxEYXRhWzBdOyBjb2xvcjogVmJUb2tlbnMudGV4dERp
bTsgTGF5b3V0LnByZWZlcnJlZFdpZHRoOiAxMTUgfQorICAgICAgICAgICAgICAgICAgICAgICAg
TGFiZWwgeyB0ZXh0OiBtb2RlbERhdGFbMV07IGNvbG9yOiBWYlRva2Vucy50ZXh0OyBMYXlvdXQu
ZmlsbFdpZHRoOiB0cnVlIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDog
bW9kZWxEYXRhWzJdOyBjb2xvcjogVmJUb2tlbnMuYWNjZW50IH0KKyAgICAgICAgICAgICAgICAg
ICAgfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIEdyb3Vw
Qm94IHsKKyAgICAgICAgICAgICAgICB2aXNpYmxlOiBwYW5lbC5raW5kID09PSAiaG9zdCIKKyAg
ICAgICAgICAgICAgICB0aXRsZTogcXNUcigiQ29uZmlndXJlIGhvc3Qgc3RhdHMiKQorICAgICAg
ICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgICAgICBDb2x1bW5M
YXlvdXQgeworICAgICAgICAgICAgICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAorICAgICAg
ICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBU
ZXh0LldyYXA7IHRleHQ6IHFzVHIoIlNlbGVjdCBhIGhvc3QgZmlyc3QuIEVuYWJsZSByZWFsdGlt
ZSBzdGF0cyBpbiBWaWJlcG9sbG8gYW5kIGNyZWF0ZSBhIHJlYWQtb25seSB0b2tlbiBmb3IgR0VU
IC9hcGkvaG9zdC9zdGF0cy4gR2FtZVN0cmVhbSBwYWlyaW5nIGRvZXMgbm90IGdyYW50IHRoaXMg
YWNjZXNzLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICAgICAgICAg
IFRleHRGaWVsZCB7IGlkOiB1cmxJbnB1dDsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgcGxhY2Vo
b2xkZXJUZXh0OiBxc1RyKCJIVFRQUyBob3N0IFVSTCwgZS5nLiBodHRwczovLzE5Mi4xNjguMS4x
MDo0Nzk5MCIpOyBzZWxlY3RCeU1vdXNlOiB0cnVlIH0KKyAgICAgICAgICAgICAgICAgICAgVGV4
dEZpZWxkIHsgaWQ6IHRva2VuSW5wdXQ7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHBsYWNlaG9s
ZGVyVGV4dDogcXNUcigiUmVhZC1vbmx5IEFQSSB0b2tlbiAoYmxhbmsga2VlcHMgc2F2ZWQgdG9r
ZW4pIik7IGVjaG9Nb2RlOiBUZXh0SW5wdXQuUGFzc3dvcmQ7IHNlbGVjdEJ5TW91c2U6IHRydWUg
fQorICAgICAgICAgICAgICAgICAgICBUZXh0RmllbGQgeyBpZDogcGluSW5wdXQ7IExheW91dC5m
aWxsV2lkdGg6IHRydWU7IHBsYWNlaG9sZGVyVGV4dDogcXNUcigiU0hBLTI1NiBjZXJ0aWZpY2F0
ZSBmaW5nZXJwcmludCBmb3IgYSBzZWxmLXNpZ25lZCBob3N0Iik7IHNlbGVjdEJ5TW91c2U6IHRy
dWUgfQorICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7
IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIlZlcmlmeSBhIHNlbGYtc2lnbmVkIGNl
cnRpZmljYXRlJ3MgU0hBLTI1NiBmaW5nZXJwcmludCBvbiB0aGUgaG9zdCBiZWZvcmUgc2F2aW5n
IGl0LiBUb2tlbiBpcyBzdG9yZWQgcHJpdmF0ZWx5IG9uIHRoaXMgVVNCOyBpdCBpcyBub3QgZW5j
cnlwdGVkLiBVbnN1cHBvcnRlZCBvciBtaXNzaW5nIHNlbnNvcnMgc2hvdyBOL0EuIik7IGNvbG9y
OiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICAgICAgQnV0dG9uIHsgdGV4dDog
cXNUcigiU2F2ZSAmIGNvbm5lY3QiKTsgb25DbGlja2VkOiB7IGlmIChDcmltc29uU3RhdHVzLmNv
bmZpZ3VyZSh1cmxJbnB1dC50ZXh0LCB0b2tlbklucHV0LnRleHQsIHBpbklucHV0LnRleHQpKSB0
b2tlbklucHV0LnRleHQgPSAiIiB9IH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICB9
CisgICAgICAgIH0KKyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1BjVmlldy5xbWwgYi9h
cHAvZ3VpL1BjVmlldy5xbWwKaW5kZXggZjBlNzM5YTguLmY0ZDAxMmI4IDEwMDY0NAotLS0gYS9h
cHAvZ3VpL1BjVmlldy5xbWwKKysrIGIvYXBwL2d1aS9QY1ZpZXcucW1sCkBAIC00NDQsNyArNDQ0
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
CkBAIC01MzUsNyArNTM1LDcgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAgICAgICAgICAgICAg
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
ICAgIGVsc2UgewpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sIGIvYXBwL2d1
aS9TZXR0aW5nc1ZpZXcucW1sCmluZGV4IDQ5NGUzNWJhLi45ZDZkNWRhYiAxMDA2NDQKLS0tIGEv
YXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sCisrKyBiL2FwcC9ndWkvU2V0dGluZ3NWaWV3LnFtbApA
QCAtMzA1NSwxNCArMzA1NSwyNiBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgdGV4dFJv
bGU6ICJ0ZXh0IgogICAgICAgICAgICAgICAgICAgICBob3ZlckVuYWJsZWQ6IHRydWUKICAgICAg
ICAgICAgICAgICAgICAgbW9kZWw6IExpc3RNb2RlbCB7Ci0gICAgICAgICAgICAgICAgICAgICAg
ICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIlRlYWwgKGRlZmF1bHQpIikgfQorICAgICAgICAg
ICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJUZWFsIikgfQogICAgICAg
ICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJJbmRpZ28iKSB9CiAg
ICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIkdyZWVuIikg
fQogICAgICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJBbWJl
ciIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigi
Q3JpbXNvbiAoZGVmYXVsdCkiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVu
dCB7IHRleHQ6IHFzVHIoIlJlZCIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVt
ZW50IHsgdGV4dDogcXNUcigiT3JhbmdlIikgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGlz
dEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJHb2xkIikgfQorICAgICAgICAgICAgICAgICAgICAgICAg
TGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJMaW1lIikgfQorICAgICAgICAgICAgICAgICAgICAg
ICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJNaW50IikgfQorICAgICAgICAgICAgICAgICAg
ICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJDeWFuIikgfQorICAgICAgICAgICAgICAg
ICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJCbHVlIikgfQorICAgICAgICAgICAg
ICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJWaW9sZXQiKSB9CisgICAgICAg
ICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIlBpbmsiKSB9CisgICAg
ICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIlNpbHZlciIpIH0K
KyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiUm9zZSIp
IH0KICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICBDb21wb25lbnQu
b25Db21wbGV0ZWQ6IGN1cnJlbnRJbmRleCA9IFN0cmVhbWluZ1ByZWZlcmVuY2VzLnVpQWNjZW50
SW5kZXgKICAgICAgICAgICAgICAgICAgICAgb25BY3RpdmF0ZWQ6IFN0cmVhbWluZ1ByZWZlcmVu
Y2VzLnVpQWNjZW50SW5kZXggPSBjdXJyZW50SW5kZXgKLSAgICAgICAgICAgICAgICAgICAgVG9v
bFRpcC50ZXh0OiBxc1RyKCJUaGUgYWNjZW50IGNvbG9yIHVzZWQgYWNyb3NzIHRoZSByZWRlc2ln
bmVkIFVJLiIpCisgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiVGhlIGFj
Y2VudCBjb2xvciB1c2VkIHRocm91Z2hvdXQgVmliZW1pcy4iKQogICAgICAgICAgICAgICAgICAg
ICBUb29sVGlwLmRlbGF5OiAxMDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJs
ZTogaG92ZXJlZAogICAgICAgICAgICAgICAgIH0KQEAgLTM3MjQsNyArMzczNiw3IEBAIEl0ZW0g
ewogICAgICAgICAgICAgICAgIExhYmVsIHsKICAgICAgICAgICAgICAgICAgICAgd2lkdGg6IHBh
cmVudC53aWR0aAogICAgICAgICAgICAgICAgICAgICBpZDogdXBkYXRlQ2hhbm5lbFRpdGxlCi0g
ICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlNvZnR3YXJlIHVwZGF0ZXMiKQorICAgICAg
ICAgICAgICAgICAgICB0ZXh0OiBBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFnZWQgPyBxc1RyKCJN
b29ubGlnaHQtT1MgdXBkYXRlcyIpIDogcXNUcigiU29mdHdhcmUgdXBkYXRlcyIpCiAgICAgICAg
ICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlTGFiZWwKICAgICAgICAg
ICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRCb2R5CiAgICAgICAgICAgICAg
ICAgICAgIHdyYXBNb2RlOiBUZXh0LldyYXAKQEAgLTM3MzMsNiArMzc0NSw3IEBAIEl0ZW0gewog
CiAgICAgICAgICAgICAgICAgQXV0b1Jlc2l6aW5nQ29tYm9Cb3ggewogICAgICAgICAgICAgICAg
ICAgICBpZDogdXBkYXRlQ2hhbm5lbENvbWJvQm94CisgICAgICAgICAgICAgICAgICAgIHZpc2li
bGU6ICFBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFnZWQKICAgICAgICAgICAgICAgICAgICAgdGV4
dFJvbGU6ICJ0ZXh0IgogICAgICAgICAgICAgICAgICAgICBtb2RlbDogTGlzdE1vZGVsIHsKICAg
ICAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsTGlzdE1vZGVsCkBAIC0zNzg3
LDYgKzM4MDAsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgLy8gaW5zdGFsbCBpbiBm
bGlnaHQgYXQgYSB0aW1lKSwgc28gYnV0dG9ucyBzdGF5IGVuYWJsZWQuCiAgICAgICAgICAgICAg
ICAgICAgIEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAgICAgICAgICBpZDogY2hlY2tVcGRhdGVz
QnV0dG9uCisgICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiAhQXV0b1VwZGF0ZUNoZWNr
ZXIub3NNYW5hZ2VkCiAgICAgICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJDaGVjayBm
b3IgdXBkYXRlcyIpCiAgICAgICAgICAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsKICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICBBdXRvVXBkYXRlQ2hlY2tlci5jaGVja05vdygpCkBAIC0z
ODA0LDggKzM4MTgsOCBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgICAgICBCdXR0b24gewog
ICAgICAgICAgICAgICAgICAgICAgICAgaWQ6IHZpZXdSZWxlYXNlQnV0dG9uCi0gICAgICAgICAg
ICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWV3IHJlbGVhc2UiKQotICAgICAgICAgICAgICAg
ICAgICAgICAgdmlzaWJsZTogQXV0b1VwZGF0ZUNoZWNrZXIub2ZmZXJBdmFpbGFibGUKKyAgICAg
ICAgICAgICAgICAgICAgICAgIHRleHQ6IEF1dG9VcGRhdGVDaGVja2VyLm9zTWFuYWdlZCA/IHFz
VHIoIk1vb25saWdodC1PUyByZWxlYXNlcyIpIDogcXNUcigiVmlldyByZWxlYXNlIikKKyAgICAg
ICAgICAgICAgICAgICAgICAgIHZpc2libGU6IChBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFnZWQg
fHwgQXV0b1VwZGF0ZUNoZWNrZXIub2ZmZXJBdmFpbGFibGUpCiAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAmJiBBdXRvVXBkYXRlQ2hlY2tlci5yZWxlYXNlVXJsICE9PSAiIgogICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgJiYgU3lzdGVtUHJvcGVydGllcy5oYXNCcm93
c2VyCiAgICAgICAgICAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsKZGlmZiAtLWdpdCBhL2Fw
cC9ndWkvU3lzdGVtQ29ubmVjdGlvbnNEaWFsb2cucW1sIGIvYXBwL2d1aS9TeXN0ZW1Db25uZWN0
aW9uc0RpYWxvZy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLjI0ZjBl
MjUzCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9TeXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5x
bWwKQEAgLTAsMCArMSwxMDEgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2su
Q29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0IFF0UXVpY2su
Q29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9y
dCBTeXN0ZW1Db250cm9scyAxLjAKKworTmF2aWdhYmxlRGlhbG9nIHsKKyAgICBpZDogcGFuZWwK
KyAgICBwcm9wZXJ0eSBzdHJpbmcga2luZDogIndpZmkiCisgICAgcHJvcGVydHkgdmFyIHNlbGVj
dGVkOiAoe30pCisgICAgd2lkdGg6IE1hdGgubWluKDYyMCwgcGFyZW50LndpZHRoIC0gMzIpCisg
ICAgaGVpZ2h0OiBNYXRoLm1pbig1NjAsIHBhcmVudC5oZWlnaHQgLSAzMikKKyAgICB0aXRsZTog
a2luZCA9PT0gIndpZmkiID8gcXNUcigiV2ktRmkgbmV0d29ya3MiKSA6IHFzVHIoIkJsdWV0b290
aCBkZXZpY2VzIikKKyAgICBzdGFuZGFyZEJ1dHRvbnM6IERpYWxvZy5DbG9zZQorICAgIE1hdGVy
aWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFsLmFjY2VudDogVmJU
b2tlbnMuYWNjZW50CisgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xlIHsgY29sb3I6IFZiVG9rZW5z
LmJnRWxldjsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNEaWFsb2c7IGJvcmRlci5jb2xvcjogVmJU
b2tlbnMuc3Ryb2tlIH0KKyAgICBvbk9wZW5lZDogeyBzZWxlY3RlZCA9ICh7fSk7IFN5c3RlbUNv
bnRyb2xzLm9wZW4oa2luZCkgfQorICAgIG9uQ2xvc2VkOiB7IGNyZWRlbnRpYWwuY2xvc2UoKTsg
c2VjcmV0LnRleHQgPSAiIjsgZm9yZ2V0LmNsb3NlKCk7IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCkg
fQorICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQgeworICAgICAgICBzcGFjaW5nOiBWYlRv
a2Vucy5zcGFjZTMKKyAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgIExheW91dC5maWxs
V2lkdGg6IHRydWUKKyAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsg
d3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHRleHQ6IFN5
c3RlbUNvbnRyb2xzLnN0YXR1czsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0gfQorICAgICAgICAg
ICAgQnVzeUluZGljYXRvciB7IHJ1bm5pbmc6IFN5c3RlbUNvbnRyb2xzLmJ1c3k7IHZpc2libGU6
IHJ1bm5pbmc7IGltcGxpY2l0V2lkdGg6IDMyOyBpbXBsaWNpdEhlaWdodDogMzIgfQorICAgICAg
ICAgICAgQnV0dG9uIHsgdGV4dDogcXNUcigiU2NhbiIpOyBlbmFibGVkOiAhU3lzdGVtQ29udHJv
bHMuYnVzeTsgb25DbGlja2VkOiB7IHBhbmVsLnNlbGVjdGVkID0gKHt9KTsgU3lzdGVtQ29udHJv
bHMucmVxdWVzdChwYW5lbC5raW5kICsgIi1zY2FuIikgfSB9CisgICAgICAgIH0KKyAgICAgICAg
TGFiZWwgeworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRl
eHQuV3JhcDsgY29sb3I6IFZiVG9rZW5zLnRleHREaW0KKyAgICAgICAgICAgIHRleHQ6IHBhbmVs
LmtpbmQgPT09ICJ3aWZpIiA/IHFzVHIoIlNlbGVjdCBhIG5ldHdvcmssIHRoZW4gQ29ubmVjdC4g
QWR2YW5jZWQgb3IgaGlkZGVuIG5ldHdvcmtzIGFyZSBhdmFpbGFibGUgaW4gdGhlIGRpYWdub3N0
aWMgc2hlbGwuIikgOiBxc1RyKCJQdXQgeW91ciBjb250cm9sbGVyIG9yIGhlYWRwaG9uZXMgaW4g
cGFpcmluZyBtb2RlLCB0aGVuIFNjYW4uIFBhaXJpbmcgbWF5IHRha2UgdXAgdG8gYSBtaW51dGUu
IikKKyAgICAgICAgfQorICAgICAgICBMaXN0VmlldyB7CisgICAgICAgICAgICBpZDogZGV2aWNl
cworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgTGF5b3V0LmZpbGxIZWlnaHQ6
IHRydWUKKyAgICAgICAgICAgIGNsaXA6IHRydWU7IHNwYWNpbmc6IDQ7IG1vZGVsOiBTeXN0ZW1D
b250cm9scy5pdGVtcworICAgICAgICAgICAgU2Nyb2xsQmFyLnZlcnRpY2FsOiBTY3JvbGxCYXIg
e30KKyAgICAgICAgICAgIGRlbGVnYXRlOiBJdGVtRGVsZWdhdGUgeworICAgICAgICAgICAgICAg
IHdpZHRoOiBkZXZpY2VzLndpZHRoCisgICAgICAgICAgICAgICAgZW5hYmxlZDogIVN5c3RlbUNv
bnRyb2xzLmJ1c3kKKyAgICAgICAgICAgICAgICBoaWdobGlnaHRlZDogcGFuZWwuc2VsZWN0ZWQu
aWQgPT09IG1vZGVsRGF0YS5pZAorICAgICAgICAgICAgICAgIGNvbnRlbnRJdGVtOiBMYWJlbCB7
CisgICAgICAgICAgICAgICAgICAgIHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyBlbGlkZTog
VGV4dC5FbGlkZVJpZ2h0OyBjb2xvcjogVmJUb2tlbnMudGV4dAorICAgICAgICAgICAgICAgICAg
ICB0ZXh0OiBtb2RlbERhdGEubmFtZSArICIgwrcgIiArIG1vZGVsRGF0YS5kZXRhaWwgKyAobW9k
ZWxEYXRhLmNvbm5lY3RlZCA/ICIgwrcgIiArIHFzVHIoIkNvbm5lY3RlZCIpIDogIiIpCisgICAg
ICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBwYW5lbC5zZWxlY3Rl
ZCA9IG1vZGVsRGF0YTsgZGV2aWNlcy5jdXJyZW50SW5kZXggPSBpbmRleCB9CisgICAgICAgICAg
ICB9CisgICAgICAgIH0KKyAgICAgICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgIExheW91dC5m
aWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgIEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgdGV4
dDogcGFuZWwua2luZCA9PT0gIndpZmkiID8gcXNUcigiQ29ubmVjdCIpIDogcXNUcigiUGFpciAv
IENvbm5lY3QiKQorICAgICAgICAgICAgICAgIGVuYWJsZWQ6ICEhcGFuZWwuc2VsZWN0ZWQuaWQg
JiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3kKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IFN5c3Rl
bUNvbnRyb2xzLnJlcXVlc3QocGFuZWwua2luZCArICItY29ubmVjdCIsIHBhbmVsLnNlbGVjdGVk
LmlkKQorICAgICAgICAgICAgfQorICAgICAgICAgICAgQnV0dG9uIHsKKyAgICAgICAgICAgICAg
ICB0ZXh0OiBxc1RyKCJEaXNjb25uZWN0Iik7IGVuYWJsZWQ6ICEhcGFuZWwuc2VsZWN0ZWQuaWQg
JiYgcGFuZWwuc2VsZWN0ZWQuY29ubmVjdGVkICYmICFTeXN0ZW1Db250cm9scy5idXN5CisgICAg
ICAgICAgICAgICAgb25DbGlja2VkOiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KHBhbmVsLmtpbmQg
KyAiLWRpc2Nvbm5lY3QiLCBwYW5lbC5zZWxlY3RlZC5pZCkKKyAgICAgICAgICAgIH0KKyAgICAg
ICAgICAgIEJ1dHRvbiB7IHRleHQ6IHFzVHIoIkZvcmdldCIpOyB2aXNpYmxlOiBwYW5lbC5raW5k
ID09PSAiYnQiOyBlbmFibGVkOiAhIXBhbmVsLnNlbGVjdGVkLmlkICYmICFTeXN0ZW1Db250cm9s
cy5idXN5OyBvbkNsaWNrZWQ6IGZvcmdldC5vcGVuKCkgfQorICAgICAgICB9CisgICAgfQorICAg
IENvbm5lY3Rpb25zIHsKKyAgICAgICAgdGFyZ2V0OiBTeXN0ZW1Db250cm9scworICAgICAgICBv
bkNoYW5nZWQ6IHsKKyAgICAgICAgICAgIGlmIChTeXN0ZW1Db250cm9scy5wcm9tcHQubGVuZ3Ro
ID4gMCAmJiBwYW5lbC5vcGVuZWQgJiYgIWNyZWRlbnRpYWwub3BlbmVkKSBjcmVkZW50aWFsLm9w
ZW4oKQorICAgICAgICAgICAgaWYgKCFTeXN0ZW1Db250cm9scy5idXN5KSB7CisgICAgICAgICAg
ICAgICAgY3JlZGVudGlhbC5jbG9zZSgpOyBzZWNyZXQudGV4dCA9ICIiCisgICAgICAgICAgICAg
ICAgdmFyIGlkID0gcGFuZWwuc2VsZWN0ZWQuaWQKKyAgICAgICAgICAgICAgICBwYW5lbC5zZWxl
Y3RlZCA9ICh7fSkKKyAgICAgICAgICAgICAgICBmb3IgKHZhciBpID0gMDsgaSA8IFN5c3RlbUNv
bnRyb2xzLml0ZW1zLmxlbmd0aDsgaSsrKQorICAgICAgICAgICAgICAgICAgICBpZiAoU3lzdGVt
Q29udHJvbHMuaXRlbXNbaV0uaWQgPT09IGlkKSBwYW5lbC5zZWxlY3RlZCA9IFN5c3RlbUNvbnRy
b2xzLml0ZW1zW2ldCisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgTmF2aWdh
YmxlRGlhbG9nIHsKKyAgICAgICAgaWQ6IGNyZWRlbnRpYWwKKyAgICAgICAgdGl0bGU6IHFzVHIo
IkNvbm5lY3Rpb24gYXV0aGVudGljYXRpb24iKQorICAgICAgICB3aWR0aDogTWF0aC5taW4oNDgw
LCBwYW5lbC53aWR0aCkKKyAgICAgICAgY2xvc2VQb2xpY3k6IFBvcHVwLk5vQXV0b0Nsb3NlCisg
ICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLk9rIHwgRGlhbG9nLkNhbmNlbAorICAgICAg
ICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAgICAgb25PcGVuZWQ6
IHsgc2VjcmV0LnRleHQgPSAiIjsgc2VjcmV0LmZvcmNlQWN0aXZlRm9jdXMoKSB9CisgICAgICAg
IG9uQWNjZXB0ZWQ6IHsgU3lzdGVtQ29udHJvbHMuYW5zd2VyKHNlY3JldC50ZXh0KTsgc2VjcmV0
LnRleHQgPSAiIiB9CisgICAgICAgIG9uUmVqZWN0ZWQ6IHsgc2VjcmV0LnRleHQgPSAiIjsgU3lz
dGVtQ29udHJvbHMuY2xvc2UoKSB9CisgICAgICAgIGNvbnRlbnRJdGVtOiBDb2x1bW5MYXlvdXQg
eworICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB0ZXh0Rm9ybWF0
OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogU3lzdGVtQ29udHJv
bHMucHJvbXB0OyBjb2xvcjogVmJUb2tlbnMudGV4dCB9CisgICAgICAgICAgICBUZXh0RmllbGQg
eyBpZDogc2VjcmV0OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBlY2hvTW9kZTogVGV4dElucHV0
LlBhc3N3b3JkOyBtYXhpbXVtTGVuZ3RoOiA0MDk2OyBzZWxlY3RCeU1vdXNlOiB0cnVlOyBvbkFj
Y2VwdGVkOiBjcmVkZW50aWFsLmFjY2VwdCgpIH0KKyAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0
LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDogcXNUcigiRW50ZXIg
dGhlIHJlcXVlc3RlZCBwYXNzd29yZCBvciBQSU4uIEZvciBhIHllcy9ubyBjb25maXJtYXRpb24s
IHR5cGUgeWVzIG9yIG5vLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgIH0K
KyAgICB9CisgICAgTmF2aWdhYmxlRGlhbG9nIHsKKyAgICAgICAgaWQ6IGZvcmdldAorICAgICAg
ICB0aXRsZTogcXNUcigiRm9yZ2V0IEJsdWV0b290aCBkZXZpY2U/IikKKyAgICAgICAgd2lkdGg6
IE1hdGgubWluKDQ4MCwgcGFuZWwud2lkdGgpCisgICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlh
bG9nLlllcyB8IERpYWxvZy5ObworICAgICAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vu
cy5iZ0VsZXYKKyAgICAgICAgb25BY2NlcHRlZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiYnQt
Zm9yZ2V0IiwgcGFuZWwuc2VsZWN0ZWQuaWQsIHRydWUpCisgICAgICAgIGNvbnRlbnRJdGVtOiBM
YWJlbCB7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0
ZXh0OiBxc1RyKCJSZW1vdmUgdGhlIHNhdmVkIHBhaXJpbmcgZm9yICUxPyBZb3Ugd2lsbCBuZWVk
IHRvIHBhaXIgaXQgYWdhaW4uIikuYXJnKHBhbmVsLnNlbGVjdGVkLm5hbWUgfHwgIiIpOyBjb2xv
cjogVmJUb2tlbnMudGV4dCB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9UaGVtZS5x
bWwgYi9hcHAvZ3VpL1RoZW1lLnFtbAppbmRleCBmYjkxYzg1MC4uNTdjOWY4NDggMTAwNjQ0Ci0t
LSBhL2FwcC9ndWkvVGhlbWUucW1sCisrKyBiL2FwcC9ndWkvVGhlbWUucW1sCkBAIC0xMSwyMCAr
MTEsMjAgQEAgaW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCiBRdE9iamVjdCB7CiAgICAgLy8g
LS0tLSBDb2xvciAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50OiAgICAg
ICAgVmJUb2tlbnMuYWNjZW50ICAvLyBCTC0yMDc3OiBzaW5nbGUgc291cmNlIG9mIHRydXRoIChW
YlRva2VucyBicmFuZCBhY2NlbnQsIGRlZmF1bHQgIzAwQ0NDQykKLSAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2VkOiAiIzAwQTNBMyIKLSAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciBiYWNrZ3JvdW5kOiAgICAiIzMwMzAzMCIgIC8vIGFwcCByb290Ci0gICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3Igc3VyZmFjZTogICAgICAgIiMyRDJEMkQiICAvLyByYWlzZWQgc3Vy
ZmFjZXMgLyBvdmVybGF5cwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZhY2VBbHQ6
ICAgICIjNDI0MjQyIiAgLy8gcG9wdXBzIC8gY29tYm8gZHJvcGRvd25zCi0gICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3IgYm9yZGVyOiAgICAgICAgIiM0NDQ0NDQiCi0gICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3IgdGV4dFByaW1hcnk6ICAgIiNGRkZGRkYiCi0gICAgcmVhZG9ubHkgcHJvcGVy
dHkgY29sb3IgdGV4dFNlY29uZGFyeTogIiNDQ0NDQ0MiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkg
Y29sb3IgdGV4dFRlcnRpYXJ5OiAgIiNBQUFBQUEiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29s
b3IgdGV4dERpc2FibGVkOiAgIiM3Nzc3NzciCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
c3VjY2VzczogICAgICAgIiM0Q0FGNTAiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igd2Fy
bmluZzogICAgICAgIiNFMEEwMzAiICAvLyB0aGUgc2luZ2xlIGFtYmVyCi0gICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3IgZXJyb3I6ICAgICAgICAgIiNGNDQzMzYiCi0gICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3IgaW5mbzogICAgICAgICAgIiM4MEEwQzAiCi0gICAgcmVhZG9ubHkgcHJvcGVy
dHkgY29sb3Igc2NyaW06ICAgICAgICAgIiNEMDAwMDAwMCIKKyAgICByZWFkb25seSBwcm9wZXJ0
eSBjb2xvciBhY2NlbnRQcmVzc2VkOiBWYlRva2Vucy5hY2NlbnRQcmVzc2VkCisgICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3IgYmFja2dyb3VuZDogICAgVmJUb2tlbnMuYmdXaW5kb3cgIC8vIGFw
cCByb290CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3VyZmFjZTogICAgICAgVmJUb2tl
bnMuYmdFbGV2ICAvLyByYWlzZWQgc3VyZmFjZXMgLyBvdmVybGF5cworICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGNvbG9yIHN1cmZhY2VBbHQ6ICAgIFZiVG9rZW5zLmJnRWxldjIgIC8vIHBvcHVwcyAv
IGNvbWJvIGRyb3Bkb3ducworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJvcmRlcjogICAg
ICAgIFZiVG9rZW5zLnN0cm9rZQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRQcmlt
YXJ5OiAgIFZiVG9rZW5zLnRleHRQcmltYXJ5CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
dGV4dFNlY29uZGFyeTogVmJUb2tlbnMudGV4dFNlY29uZGFyeQorICAgIHJlYWRvbmx5IHByb3Bl
cnR5IGNvbG9yIHRleHRUZXJ0aWFyeTogIFZiVG9rZW5zLnRleHRUZXJ0aWFyeQorICAgIHJlYWRv
bmx5IHByb3BlcnR5IGNvbG9yIHRleHREaXNhYmxlZDogIFZiVG9rZW5zLnRleHREaXNhYmxlZAor
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1Y2Nlc3M6ICAgICAgIFZiVG9rZW5zLnN0YXR1
c1N1Y2Nlc3MKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB3YXJuaW5nOiAgICAgICBWYlRv
a2Vucy5zdGF0dXNXYXJuaW5nICAvLyB0aGUgc2luZ2xlIGFtYmVyCisgICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3IgZXJyb3I6ICAgICAgICAgVmJUb2tlbnMuc3RhdHVzRGFuZ2VyCisgICAgcmVh
ZG9ubHkgcHJvcGVydHkgY29sb3IgaW5mbzogICAgICAgICAgVmJUb2tlbnMuc3RhdHVzSW5mbwor
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHNjcmltOiAgICAgICAgIFZiVG9rZW5zLmRpYWxv
Z1NjcmltCiAKICAgICAvLyAtLS0tIFR5cG9ncmFwaHkgKHBvaW50U2l6ZTsgcGFpciB3aXRoIGJv
bGQgd2hlcmUgbm90ZWQgaW4gREVTSUdOX1NZU1RFTS5tZCkgLS0tLQogICAgIHJlYWRvbmx5IHBy
b3BlcnR5IGludCBmb250RGlzcGxheTogMjQgIC8vIG92ZXJsYXkvUXVpY2sgTWVudSB0aXRsZSAo
Ym9sZCkKZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJUb2tlbnMucW1sIGIvYXBwL2d1aS9WYlRva2Vu
cy5xbWwKaW5kZXggNTJhMzRkZTQuLjY4NjJmMmZkIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiVG9r
ZW5zLnFtbAorKysgYi9hcHAvZ3VpL1ZiVG9rZW5zLnFtbApAQCAtMTAsMzEgKzEwLDI5IEBAIFF0
T2JqZWN0IHsKICAgICBpZDogdAogCiAgICAgLy8gLS0tLSBDb2xvciAtLS0tCi0gICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3IgYmdBcHA6ICAgICAgICAiIzA4MDkwQiIgIC8vIG91dGVybW9zdCBh
cHAgYmcgYmVoaW5kIHRoZSByb3VuZGVkIHdpbmRvdwotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIGJnV2luZG93OiAgICAgIiMwRTEwMTMiICAvLyBtYWluIHNjcmVlbiBiYWNrZ3JvdW5kCi0g
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdFbGV2OiAgICAgICAiIzE1MTgxRCIgIC8vIGNh
cmRzLCBwYW5lbHMsIGRpYWxvZ3MsIHNpZGViYXIgcm93cwotICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIGJnRWxldjI6ICAgICAgIiMxQjFGMjYiICAvLyBmb2N1c2VkL3NlbGVjdGVkIHN1cmZh
Y2UgZmlsbCwgY2hpcHMKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0Zvb3RlcjogICAg
ICIjMEIwRDEwIiAgLy8gYm90dG9tIGdhbWVwYWQgaGludCBiYXIKKyAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBiZ0FwcDogICAgICAgICIjMDYwNjA3IiAgLy8gb3V0ZXJtb3N0IGFwcCBiZyBi
ZWhpbmQgdGhlIHJvdW5kZWQgd2luZG93CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdX
aW5kb3c6ICAgICAiIzBCMEIwRSIgIC8vIG1haW4gc2NyZWVuIGJhY2tncm91bmQKKyAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciBiZ0VsZXY6ICAgICAgICIjMTUxMTE1IiAgLy8gY2FyZHMsIHBh
bmVscywgZGlhbG9ncywgc2lkZWJhciByb3dzCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
YmdFbGV2MjogICAgICAiIzIxMTcxQyIgIC8vIGZvY3VzZWQvc2VsZWN0ZWQgc3VyZmFjZSBmaWxs
LCBjaGlwcworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRm9vdGVyOiAgICAgIiMwOTA4
MEIiICAvLyBib3R0b20gZ2FtZXBhZCBoaW50IGJhcgogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIHN0cm9rZTogICAgICAgUXQucmdiYSgxLCAxLCAxLCAwLjA4KSAgLy8gZGVmYXVsdCAxcHgg
Y2FyZCBib3JkZXIKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdHJva2VTb2Z0OiAgIFF0
LnJnYmEoMSwgMSwgMSwgMC4wNikgIC8vIGhlYWRlci9mb290ZXIgZGl2aWRlcnMKICAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0OiAgICAgICAgICIjRUNFRUYxIiAgLy8gcHJpbWFyeSB0
ZXh0CiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpbTogICAgICAiIzk4QTFBQiIg
IC8vIHNlY29uZGFyeSAvIGxhYmVsIHRleHQKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0
ZXh0TXV0ZTogICAgICIjQjlDMEM4IiAgLy8gdGVydGlhcnkgLyBpbmFjdGl2ZSBpdGVtIGxhYmVs
cwogCi0gICAgLy8gQWNjZW50IGlzIHN3YXBwYWJsZSDigJQgb25lIG9mIHRoZSA0IGN1cmF0ZWQg
dmFsdWVzLiBJbmRleCAwIGlzIHRoZSBWaWJlbWlzIGJyYW5kCi0gICAgLy8gdGVhbCAjMDBDQ0ND
IChCTC0yMDc3KTogdGhlIHNpbmdsZSBjYW5vbmljYWwgYWNjZW50IHRoYXQgVGhlbWUucW1sICsg
YWxsIGxpdGVyYWxzIG5vdwotICAgIC8vIHJlc29sdmUgdGhyb3VnaCwgYW5kIHRoZSBhbmNob3Ig
Zm9yIHRoZSBQMy4xNy9QMy4xOCBkZXNpZ24gd29yay4KLSAgICByZWFkb25seSBwcm9wZXJ0eSB2
YXIgYWNjZW50T3B0aW9uczogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1OTgiLCAiI0Yw
QTg2OCJdCisgICAgLy8gUHJlc2VydmUgbGVnYWN5IGluZGljZXMgMC4uMzsgYXBwZW5kIGNvbG9y
cyBhbmQgZGVmYXVsdCBuZXcgcHJlZmVyZW5jZXMgdG8gY3JpbXNvbi4KKyAgICByZWFkb25seSBw
cm9wZXJ0eSB2YXIgYWNjZW50T3B0aW9uczogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1
OTgiLCAiI0YwQTg2OCIsICIjREMzNjU4IiwgIiNGMjVENjQiLCAiI0Y1ODM0NyIsICIjRjFCQzQ1
IiwgIiNCN0RDNjMiLCAiIzYzQ0NBRSIsICIjNjNDNEVEIiwgIiM2QzlGRkYiLCAiI0FEODVGNSIs
ICIjRTk3NkJDIiwgIiNDQUQwREEiLCAiI0Q5OTVBQyJdCiAgICAgLy8gQm91bmQgdG8gdGhlIHNh
dmVkIHByZWZlcmVuY2UgKFNldHRpbmdzID4gYWNjZW50IHBpY2tlcik7IHBlcnNpc3RzIGFjcm9z
cyByZXN0YXJ0cy4KICAgICBwcm9wZXJ0eSBpbnQgYWNjZW50SW5kZXg6IFN0cmVhbWluZ1ByZWZl
cmVuY2VzLnVpQWNjZW50SW5kZXgKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnQ6
ICAgICAgIGFjY2VudE9wdGlvbnNbYWNjZW50SW5kZXhdCi0gICAgcmVhZG9ubHkgcHJvcGVydHkg
Y29sb3IgYWNjZW50SGk6ICAgICAiIzZBRERFNyIgIC8vIGFjY2VudCBncmFkaWVudCBsaWdodCBz
dG9wIC8gbGluayBob3ZlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudDogICAg
ICAgYWNjZW50T3B0aW9uc1tNYXRoLm1heCgwLCBNYXRoLm1pbihhY2NlbnRPcHRpb25zLmxlbmd0
aCAtIDEsIGFjY2VudEluZGV4KSldCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50
SGk6ICAgICBRdC5saWdodGVyKGFjY2VudCwgMS4xOCkgIC8vIGFjY2VudCBncmFkaWVudCBsaWdo
dCBzdG9wIC8gbGluayBob3ZlcgogCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3RhdHVz
T25saW5lOiAgIiMzRUQ1OTgiICAvLyBvbmxpbmUgZG90LCBSRVNVTUUgYmFkZ2UKICAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNPZmZsaW5lOiAiIzVBNjI2QyIgIC8vIG9mZmxpbmUg
ZG90IC8gZ3JleWVkIG1vbml0b3IKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNE
YW5nZXI6ICAiI0YyNkQ2RCIgIC8vIGRlc3RydWN0aXZlIChEZWxldGUgUEMpCiAKLSAgICByZWFk
b25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0T25BY2NlbnQ6ICIjMDgwOTBCIiAgLy8gdGV4dCBvbiBh
biBhY2NlbnQtZmlsbGVkIGJ1dHRvbgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRP
bkFjY2VudDogIiMwNjA2MDciICAvLyB0ZXh0IG9uIGFuIGFjY2VudC1maWxsZWQgYnV0dG9uCiAK
ICAgICAvLyAtLS0tIFR5cG9ncmFwaHkgKGZhbWlsaWVzICsgc2l6ZXM7IHdlaWdodHMgcGVyIHRo
ZSB0eXBlIHNjYWxlKSAtLS0tCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgc3RyaW5nIGZvbnREaXNw
bGF5OiAiU29yYSIgICAgIC8vIHRpdGxlcywgY2FyZCBuYW1lcywgd29yZG1hcmssIGFsbC1jYXBz
IGxhYmVscwpAQCAtMTE5LDcgKzExNyw3IEBAIFF0T2JqZWN0IHsKICAgICAvLyB0ZXh0T25BY2Nl
bnQgKCMwODA5MEIpIGlzIGRlZmluZWQgaW4gdGhlIGJhc2UgYmxvY2sgYWJvdmUg4oCUIHRleHQg
b24gYW4gYWNjZW50IGZpbGwuCiAKICAgICAvLyAtLS0tIEludGVyYWN0aXZlIHN0YXRlczogbm9y
bWFsIC8gaG92ZXIgLyBmb2N1cyAvIHByZXNzZWQgLyBkaXNhYmxlZCAtLS0tCi0gICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDogICAgICAiIzAwQTNBMyIgLy8gcHJlc3Nl
ZCBhY2NlbnRlZCBjb250cm9sIChtYXRjaGVzIGxlZ2FjeSBUaGVtZS5hY2NlbnRQcmVzc2VkKQor
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudFByZXNzZWQ6ICAgICAgUXQuZGFya2Vy
KGFjY2VudCwgMS4xOCkgLy8gcHJlc3NlZCBhY2NlbnRlZCBjb250cm9sIChtYXRjaGVzIGxlZ2Fj
eSBUaGVtZS5hY2NlbnRQcmVzc2VkKQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGludGVy
YWN0aXZlSG92ZXI6ICAgYmdFbGV2MiAgICAvLyByb3cgLyBsaXN0LWl0ZW0gLyBpY29uLWJ1dHRv
biBob3ZlciBmaWxsCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW50ZXJhY3RpdmVGb2N1
czogICBmb2N1c2VkRmlsbC8vIGZvY3VzZWQgZmlsbCAoPSBiZ0VsZXYyKSDigJQgcGFpciB3aXRo
IHRoZSBmb2N1cyByaW5nCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW50ZXJhY3RpdmVQ
cmVzc2VkOiBiZ0VsZXYgICAgIC8vIHByZXNzZWQgbmV1dHJhbCBmaWxsIChyZWNlZGVzIHVuZGVy
IHRoZSBwcmVzcykKZGlmZiAtLWdpdCBhL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5jcHAgYi9hcHAv
Z3VpL2NvbXB1dGVybW9kZWwuY3BwCmluZGV4IDYzYzcxMTU4Li4yZDQ4N2ZmNSAxMDA2NDQKLS0t
IGEvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmNwcAorKysgYi9hcHAvZ3VpL2NvbXB1dGVybW9kZWwu
Y3BwCkBAIC0xLDMgKzEsNCBAQAorI2luY2x1ZGUgPFFVcmw+CiAjaW5jbHVkZSAiY29tcHV0ZXJt
b2RlbC5oIgogI2luY2x1ZGUgImJhY2tlbmQvc2VydmVycGVybWlzc2lvbnMuaCIKICNpbmNsdWRl
ICJzZXR0aW5ncy92aWJlbWlzc2V0dGluZ3MuaCIKQEAgLTQyMCwzICs0MjEsMTMgQEAgdm9pZCBD
b21wdXRlck1vZGVsOjpoYW5kbGVDb21wdXRlclN0YXRlQ2hhbmdlZChOdkNvbXB1dGVyKiBjb21w
dXRlcikKIH0KIAogI2luY2x1ZGUgImNvbXB1dGVybW9kZWwubW9jIgorCitRVmFyaWFudE1hcCBD
b21wdXRlck1vZGVsOjpjcmltc29uSG9zdChpbnQgaW5kZXgpIGNvbnN0Cit7CisgICAgaWYgKGlu
ZGV4IDwgMCB8fCBpbmRleCA+PSBtX0NvbXB1dGVycy5jb3VudCgpKSByZXR1cm4ge307CisgICAg
YXV0byBjb21wdXRlciA9IG1fQ29tcHV0ZXJzW2luZGV4XTsKKyAgICBRUmVhZExvY2tlciBsb2Nr
KCZjb21wdXRlci0+bG9jayk7CisgICAgUVVybCB1cmw7IHVybC5zZXRTY2hlbWUoImh0dHBzIik7
IHVybC5zZXRIb3N0KGNvbXB1dGVyLT5hY3RpdmVBZGRyZXNzLmFkZHJlc3MoKSk7CisgICAgdXJs
LnNldFBvcnQoY29tcHV0ZXItPmFjdGl2ZUFkZHJlc3MucG9ydCgpID4gMCA/IGNvbXB1dGVyLT5h
Y3RpdmVBZGRyZXNzLnBvcnQoKSArIDEgOiA0Nzk5MCk7CisgICAgcmV0dXJuIHt7ImlkIiwgY29t
cHV0ZXItPnV1aWR9LCB7InVybCIsIHVybC50b1N0cmluZygpfX07Cit9CmRpZmYgLS1naXQgYS9h
cHAvZ3VpL2NvbXB1dGVybW9kZWwuaCBiL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5oCmluZGV4IDZl
Y2FlMzBkLi4yZWU3M2MxZCAxMDA2NDQKLS0tIGEvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmgKKysr
IGIvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmgKQEAgLTQzLDYgKzQzLDggQEAgcHVibGljOgogCiAg
ICAgdmlydHVhbCBRSGFzaDxpbnQsIFFCeXRlQXJyYXk+IHJvbGVOYW1lcygpIGNvbnN0IG92ZXJy
aWRlOwogCisgICAgUV9JTlZPS0FCTEUgUVZhcmlhbnRNYXAgY3JpbXNvbkhvc3QoaW50IGNvbXB1
dGVySW5kZXgpIGNvbnN0OworCiAgICAgUV9JTlZPS0FCTEUgdm9pZCBkZWxldGVDb21wdXRlcihp
bnQgY29tcHV0ZXJJbmRleCk7CiAKICAgICBRX0lOVk9LQUJMRSBRU3RyaW5nIGdlbmVyYXRlUGlu
U3RyaW5nKCk7CmRpZmYgLS1naXQgYS9hcHAvZ3VpL21haW4ucW1sIGIvYXBwL2d1aS9tYWluLnFt
bAppbmRleCA5YmNlNTEwNS4uY2U3YjI4ZDkgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvbWFpbi5xbWwK
KysrIGIvYXBwL2d1aS9tYWluLnFtbApAQCAtMTIsOCArMTIsMjQgQEAgaW1wb3J0IFN5c3RlbVBy
b3BlcnRpZXMgMS4wCiBpbXBvcnQgU2RsR2FtZXBhZEtleU5hdmlnYXRpb24gMS4wCiBpbXBvcnQg
VWlTb3VuZE1hbmFnZXIgMS4wCiBpbXBvcnQgVGhlbWUgMS4wCitpbXBvcnQgQ3JpbXNvblN0YXR1
cyAxLjAKIAogQXBwbGljYXRpb25XaW5kb3cgeworICAgIE1hdGVyaWFsLnRoZW1lOiBNYXRlcmlh
bC5EYXJrCisgICAgTWF0ZXJpYWwuYWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBNYXRlcmlh
bC5wcmltYXJ5OiBWYlRva2Vucy5iZ0VsZXYKKyAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRv
a2Vucy5iZ1dpbmRvdworICAgIE1hdGVyaWFsLmZvcmVncm91bmQ6IFZiVG9rZW5zLnRleHQKKyAg
ICBjb2xvcjogVmJUb2tlbnMuYmdBcHAKKyAgICBwYWxldHRlLndpbmRvdzogVmJUb2tlbnMuYmdX
aW5kb3cKKyAgICBwYWxldHRlLndpbmRvd1RleHQ6IFZiVG9rZW5zLnRleHQKKyAgICBwYWxldHRl
LmJhc2U6IFZiVG9rZW5zLmJnQXBwCisgICAgcGFsZXR0ZS5hbHRlcm5hdGVCYXNlOiBWYlRva2Vu
cy5iZ0VsZXYKKyAgICBwYWxldHRlLnRleHQ6IFZiVG9rZW5zLnRleHQKKyAgICBwYWxldHRlLmJ1
dHRvbjogVmJUb2tlbnMuYmdFbGV2CisgICAgcGFsZXR0ZS5idXR0b25UZXh0OiBWYlRva2Vucy50
ZXh0CisgICAgcGFsZXR0ZS5oaWdobGlnaHQ6IFZiVG9rZW5zLmFjY2VudAorICAgIHBhbGV0dGUu
aGlnaGxpZ2h0ZWRUZXh0OiBWYlRva2Vucy50ZXh0T25BY2NlbnQKICAgICBwcm9wZXJ0eSBib29s
IHBvbGxpbmdBY3RpdmU6IGZhbHNlCiAKICAgICAvLyBTZXQgYnkgU2V0dGluZ3NWaWV3IHRvIGZv
cmNlIHRoZSBiYWNrIG9wZXJhdGlvbiB0byBwb3AgYWxsCkBAIC00NiwxNCArNjIsMTMgQEAgQXBw
bGljYXRpb25XaW5kb3cgewogICAgICAgICAvLyBpbiBvcmRlciB0byBpbXByb3ZlIGNvbnRyYXN0
IGJldHdlZW4gR0ZFJ3MgcGxhY2Vob2xkZXIgYm94IGFydAogICAgICAgICAvLyBhbmQgdGhlIGJh
Y2tncm91bmQgb2YgdGhlIGFwcCBncmlkLgogICAgICAgICBpZiAoU3lzdGVtUHJvcGVydGllcy51
c2VzTWF0ZXJpYWwzVGhlbWUpIHsKLSAgICAgICAgICAgIE1hdGVyaWFsLmJhY2tncm91bmQgPSBU
aGVtZS5iYWNrZ3JvdW5kCisgICAgICAgICAgICAvLyBUaGVtZSByZW1haW5zIGEgbGl2ZSBiaW5k
aW5nIHRvIHRoZSBzaGFyZWQgcGFsZXR0ZS4KICAgICAgICAgfQogCiAgICAgICAgIC8vIEJyaWRn
ZSB0aGUgTWF0ZXJpYWwgc3R5bGUgdG8gdGhlIFZpYmVtaXMgZGVzaWduIHRva2VucyBzbyB0aGUK
ICAgICAgICAgLy8gTWF0ZXJpYWwtc3R5bGVkIHBhZ2VzIChDb21wdXRlcnMgZ3JpZCwgQXBwIGdy
aWQsIGRpYWxvZ3MpIHNoYXJlIHRoZSBzYW1lCiAgICAgICAgIC8vIGFjY2VudC9iYWNrZ3JvdW5k
IHN5c3RlbSBhcyB0aGUgdG9rZW4tbmF0aXZlIHBhZ2VzLiBTZWUgZG9jcy9ERVNJR05fU1lTVEVN
Lm1kLgotICAgICAgICBNYXRlcmlhbC50aGVtZSA9IE1hdGVyaWFsLkRhcmsKLSAgICAgICAgTWF0
ZXJpYWwuYWNjZW50ID0gVGhlbWUuYWNjZW50CisgICAgICAgIC8vIE1hdGVyaWFsIHRoZW1lL2Fj
Y2VudCBhcmUgYm91bmQgYXQgdGhlIHJvb3QsIGluY2x1ZGluZyBhZnRlciBjaGFuZ2VzLgogCiAg
ICAgICAgIFNkbEdhbWVwYWRLZXlOYXZpZ2F0aW9uLmVuYWJsZSgpCiAgICAgfQpAQCAtMjY3LDYg
KzI4Miw5IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgfQogICAgIH0KIAorICAgIENy
aW1zb25TdGF0dXNEaWFsb2cgeyBpZDogY3JpbXNvblBhbmVsIH0KKyAgICBTeXN0ZW1Db25uZWN0
aW9uc0RpYWxvZyB7IGlkOiBjb25uZWN0aW9uUGFuZWwgfQorCiAgICAgaGVhZGVyOiBUb29sQmFy
IHsKICAgICAgICAgaWQ6IHRvb2xCYXIKICAgICAgICAgLy8gUmVkZXNpZ246IEVWRVJZIHJlZGVz
aWduZWQgbGF1bmNoZXIgc2NyZWVuIChDb21wdXRlcnMsIEFwcCBncmlkLCBTZXR0aW5ncywgSGVs
cCkKQEAgLTMzOCw3ICszNTYsNyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgIC8vIFZJ
QkVNSVMgd29yZG1hcmsgKGRpYW1vbmQgKyB3b3JkbWFyayksIHNob3duIG9uIHRoZSBDb21wdXRl
cnMgc2NyZWVuIGluIHBsYWNlIG9mIGEgdGl0bGUsCiAgICAgICAgIC8vIG1hdGNoaW5nIHRoZSBk
ZXNpZ24gaGVhZGVyLiBMZWZ0LWFsaWduZWQgYXQgdGhlIEhUTUwncyA0MHB4IHBhZGRpbmcuCiAg
ICAgICAgIFJvdyB7Ci0gICAgICAgICAgICB2aXNpYmxlOiB0b29sQmFyLm9uUGNWaWV3CisgICAg
ICAgICAgICB2aXNpYmxlOiB0b29sQmFyLm9uUGNWaWV3ICYmIHRvb2xCYXIud2lkdGggPiA3NjAK
ICAgICAgICAgICAgIGFuY2hvcnMubGVmdDogcGFyZW50LmxlZnQKICAgICAgICAgICAgIGFuY2hv
cnMubGVmdE1hcmdpbjogNDAKICAgICAgICAgICAgIGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBh
cmVudC52ZXJ0aWNhbENlbnRlcgpAQCAtMzY1LDcgKzM4Myw3IEBAIEFwcGxpY2F0aW9uV2luZG93
IHsKICAgICAgICAgICAgIC8vIEhpZGRlbiBvbiBDb21wdXRlcnMgKHRoZSB3b3JkbWFyayBzdGFu
ZHMgaW4pIGFuZCBvbiB0aGUgQXBwIGdyaWQgKHdoaWNoIHNob3dzIGEKICAgICAgICAgICAgIC8v
IGxlZnQtYWxpZ25lZCBob3N0ICsgc3RhdHVzIGJsb2NrIGluc3RlYWQpLiBPbiBTZXR0aW5ncy9I
ZWxwIGl0IHNob3dzIHRoZSBzY3JlZW4gbmFtZTsKICAgICAgICAgICAgIC8vIHRoZSBzdHJlYW1p
bmcgc2VndWVzIGtlZXAgdGhlaXIgZGVmYXVsdCBvYmplY3ROYW1lIHRpdGxlLgotICAgICAgICAg
ICAgdmlzaWJsZTogIXRvb2xCYXIub25QY1ZpZXcgJiYgIXRvb2xCYXIub25BcHBWaWV3ICYmIHRv
b2xCYXIud2lkdGggPiA3MDAKKyAgICAgICAgICAgIHZpc2libGU6ICF0b29sQmFyLm9uUGNWaWV3
ICYmICF0b29sQmFyLm9uQXBwVmlldyAmJiB0b29sQmFyLndpZHRoID4gNzYwCiAgICAgICAgICAg
ICBhbmNob3JzLmZpbGw6IHBhcmVudAogICAgICAgICAgICAgdGV4dDogdG9vbEJhci5vblNldHRp
bmdzID8gcXNUcigiU2V0dGluZ3MiKQogICAgICAgICAgICAgICAgIDogdG9vbEJhci5vbkhlbHAg
PyBxc1RyKCJIZWxwIikKQEAgLTQ4Nyw2ICs1MDUsNTQgQEAgQXBwbGljYXRpb25XaW5kb3cgewog
ICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgIH0KIAorICAgICAgICAgICAgTmF2aWdhYmxl
VG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IG5ldHdvcmtTdGF0dXNCdXR0b24KKyAg
ICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZyIK
KyAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIldpLUZpIHNldHRpbmdzIikK
KyAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAg
ICBUb29sVGlwLnRleHQ6IHFzVHIoIk5ldHdvcms6ICUxIikuYXJnKENyaW1zb25TdGF0dXMubG9j
YWwubmV0d29yayB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIG9uQ2xp
Y2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9ICJ3aWZpIjsgY29ubmVjdGlvblBhbmVsLm9w
ZW4oKSB9CisgICAgICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1ZpZXcuY3Vy
cmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAgICAgICBS
ZWN0YW5nbGUgeworICAgICAgICAgICAgICAgICAgICBhbmNob3JzLnJpZ2h0OiBwYXJlbnQucmln
aHQ7IGFuY2hvcnMuYm90dG9tOiBwYXJlbnQuYm90dG9tOyBhbmNob3JzLm1hcmdpbnM6IDUKKyAg
ICAgICAgICAgICAgICAgICAgd2lkdGg6IDg7IGhlaWdodDogODsgcmFkaXVzOiA0CisgICAgICAg
ICAgICAgICAgICAgIGNvbG9yOiBDcmltc29uU3RhdHVzLmxvY2FsLmNvbm5lY3RlZCA/IFZiVG9r
ZW5zLnN0YXR1c09ubGluZSA6IFZiVG9rZW5zLnN0YXR1c09mZmxpbmUKKyAgICAgICAgICAgICAg
ICB9CisgICAgICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAg
ICAgICAgICAgICAgICBpZDogYmx1ZXRvb3RoU2V0dGluZ3NCdXR0b24KKyAgICAgICAgICAgICAg
ICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnIgorICAgICAgICAg
ICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiQmx1ZXRvb3RoIHNldHRpbmdzIikKKyAgICAg
ICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBUb29s
VGlwLnRleHQ6IHFzVHIoIlBhaXIgY29udHJvbGxlcnMgYW5kIGhlYWRwaG9uZXMiKQorICAgICAg
ICAgICAgICAgIG9uQ2xpY2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9ICJidCI7IGNvbm5l
Y3Rpb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDog
c3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAg
ICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAgICAg
ICAgICBpZDogYmF0dGVyeVN0YXR1c0J1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3VyY2U6
ICJxcmM6L3Jlcy9jcmltc29uLWJhdHRlcnkuc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2li
bGUubmFtZTogcXNUcigiQmF0dGVyeSBzdGF0dXMiKQorICAgICAgICAgICAgICAgIFRvb2xUaXAu
dmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogQ3JpbXNvblN0
YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAwID8gcXNUcigiQmF0dGVyeTogJTElIOKAoiAl
MiIpLmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50KS5hcmcoQ3JpbXNvblN0
YXR1cy5sb2NhbC5iYXR0ZXJ5U3RhdGUpIDogcXNUcigiQmF0dGVyeSB1bmF2YWlsYWJsZSIpCisg
ICAgICAgICAgICAgICAgb25DbGlja2VkOiB7IGNyaW1zb25QYW5lbC5raW5kID0gImJhdHRlcnki
OyBjcmltc29uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAgICAgICBLZXlzLm9uRG93blByZXNz
ZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQor
ICAgICAgICAgICAgfQorICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAgICAg
ICAgICAgICAgaWQ6IGhvc3RIYXJkd2FyZUJ1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3Vy
Y2U6ICJxcmM6L3Jlcy9jcmltc29uLWhvc3Quc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2li
bGUubmFtZTogcXNUcigiVmliZXBvbGxvIGhvc3QgaGFyZHdhcmUgc3RhdHMiKQorICAgICAgICAg
ICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAu
dGV4dDogcXNUcigiSG9zdCBDUFUsIFJBTSwgR1BVIGFuZCB0ZW1wZXJhdHVyZXMiKQorICAgICAg
ICAgICAgICAgIG9uQ2xpY2tlZDogeworICAgICAgICAgICAgICAgICAgICB2YXIgaXRlbSA9IHN0
YWNrVmlldy5jdXJyZW50SXRlbQorICAgICAgICAgICAgICAgICAgICB2YXIgaG9zdCA9IHRvb2xC
YXIub25BcHBWaWV3ID8gaXRlbS5jcmltc29uSG9zdAorICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICA6ICh0b29sQmFyLm9uUGNWaWV3ID8gaXRlbS5jb21wdXRlck1vZGVsLmNyaW1zb25Ib3N0
KGl0ZW0uY3VycmVudEluZGV4KSA6IHt9KQorICAgICAgICAgICAgICAgICAgICBDcmltc29uU3Rh
dHVzLnNlbGVjdEhvc3QoaG9zdC5pZCB8fCAiIiwgaG9zdC51cmwgfHwgIiIpCisgICAgICAgICAg
ICAgICAgICAgIGNyaW1zb25QYW5lbC5raW5kID0gImhvc3QiOyBjcmltc29uUGFuZWwub3Blbigp
CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3NlZDog
c3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisgICAg
ICAgICAgICB9CisKICAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24gewogICAgICAgICAg
ICAgICAgIGlkOiBkaXNjb3JkQnV0dG9uCiAgICAgICAgICAgICAgICAgdmlzaWJsZTogZmFsc2Ug
Ly8gVGVtcG9yYXJpbHkgZGlzYWJsZWQgZm9yIFZpYmVtaXMKZGlmZiAtLWdpdCBhL2FwcC9tb29u
bGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVz
LmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uZGFmY2EyZWUKLS0tIC9k
ZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5jcHAKQEAgLTAsMCAr
MSwyMjIgQEAKKyNpbmNsdWRlICJjcmltc29uc3RhdHVzLmgiCisjaW5jbHVkZSA8UURhdGVUaW1l
PgorI2luY2x1ZGUgPFFEaXI+CisjaW5jbHVkZSA8UUZpbGU+CisjaW5jbHVkZSA8UUpzb25Eb2N1
bWVudD4KKyNpbmNsdWRlIDxRSnNvbk9iamVjdD4KKyNpbmNsdWRlIDxRTmV0d29ya0ludGVyZmFj
ZT4KKyNpbmNsdWRlIDxRTmV0d29ya1JlcXVlc3Q+CisjaW5jbHVkZSA8UVNhdmVGaWxlPgorI2lu
Y2x1ZGUgPFFTc2xDZXJ0aWZpY2F0ZT4KKyNpbmNsdWRlIDxRU3NsRXJyb3I+CisjaW5jbHVkZSA8
UVN0YW5kYXJkUGF0aHM+CisjaW5jbHVkZSA8UUNyeXB0b2dyYXBoaWNIYXNoPgorI2luY2x1ZGUg
PFFVcmw+CisjaW5jbHVkZSA8Y21hdGg+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNsdWRl
IDxRQ29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUgPG1lbW9yeT4KKyNpbmNsdWRlIDxRUmVndWxh
ckV4cHJlc3Npb24+CisjaW5jbHVkZSA8UUZpbGVJbmZvPgorI2luY2x1ZGUgPFFTc2xDb25maWd1
cmF0aW9uPgorCituYW1lc3BhY2UgeworUVN0cmluZyByZWFkKGNvbnN0IFFTdHJpbmcmIHBhdGgp
IHsKKyAgICBRRmlsZSBmKHBhdGgpOyByZXR1cm4gZi5vcGVuKFFJT0RldmljZTo6UmVhZE9ubHkp
ID8gUVN0cmluZzo6ZnJvbVV0ZjgoZi5yZWFkQWxsKCkpLnRyaW1tZWQoKSA6IFFTdHJpbmcoKTsK
K30KK2NvbnN0IGF1dG8gdXNlck9ubHkgPSBRRmlsZURldmljZTo6UmVhZE93bmVyIHwgUUZpbGVE
ZXZpY2U6OldyaXRlT3duZXI7Cit9CitDcmltc29uU3RhdHVzOjpDcmltc29uU3RhdHVzKFFPYmpl
Y3QqIHBhcmVudCkgOiBRT2JqZWN0KHBhcmVudCkgeworICAgIGNvbm5lY3QoJm1fbG9jYWxUaW1l
ciwgJlFUaW1lcjo6dGltZW91dCwgdGhpcywgJkNyaW1zb25TdGF0dXM6OnJlZnJlc2hMb2NhbCk7
CisgICAgY29ubmVjdCgmbV9zdGF0c1RpbWVyLCAmUVRpbWVyOjp0aW1lb3V0LCB0aGlzLCAmQ3Jp
bXNvblN0YXR1czo6cmVmcmVzaCk7CisgICAgY29ubmVjdCgmbV93aWZpLCAmUVByb2Nlc3M6OmZp
bmlzaGVkLCB0aGlzLCBbdGhpc10oaW50IGV4aXQsIFFQcm9jZXNzOjpFeGl0U3RhdHVzKSB7Cisg
ICAgICAgIGlmIChleGl0ID09IDApIHsKKyAgICAgICAgICAgIGNvbnN0IGF1dG8gbGluZXMgPSBR
U3RyaW5nOjpmcm9tVXRmOChtX3dpZmkucmVhZEFsbFN0YW5kYXJkT3V0cHV0KCkpLnNwbGl0KCdc
bicpOworICAgICAgICAgICAgZm9yIChjb25zdCBhdXRvJiBsaW5lIDogbGluZXMpIHsKKyAgICAg
ICAgICAgICAgICBpZiAoIWxpbmUuc3RhcnRzV2l0aCgieWVzOiIpKSBjb250aW51ZTsKKyAgICAg
ICAgICAgICAgICBpbnQgc2VwYXJhdG9yID0gbGluZS5pbmRleE9mKCc6JywgNCk7IGJvb2wgb2sg
PSBmYWxzZTsKKyAgICAgICAgICAgICAgICBpbnQgc2lnbmFsID0gbGluZS5taWQoNCwgc2VwYXJh
dG9yIC0gNCkudG9JbnQoJm9rKTsKKyAgICAgICAgICAgICAgICBpZiAob2sgJiYgc2lnbmFsID49
IDAgJiYgc2lnbmFsIDw9IDEwMCkgbV9sb2NhbFsid2lmaVNpZ25hbCJdID0gc2lnbmFsOworICAg
ICAgICAgICAgICAgIGlmIChzZXBhcmF0b3IgPj0gMCkgbV9sb2NhbFsibmV0d29yayJdID0gdHIo
IldpLUZpOiAlMSIpLmFyZyhsaW5lLm1pZChzZXBhcmF0b3IgKyAxKSk7CisgICAgICAgICAgICAg
ICAgYnJlYWs7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBlbWl0IGxvY2FsQ2hhbmdlZCgp
OworICAgICAgICB9CisgICAgfSk7CisgICAgbV9sb2NhbFRpbWVyLnN0YXJ0KDEwMDAwKTsgbV9z
dGF0c1RpbWVyLnNldEludGVydmFsKDIwMDApOyByZWZyZXNoTG9jYWwoKTsKK30KK0NyaW1zb25T
dGF0dXM6On5Dcmltc29uU3RhdHVzKCkgeworICAgIG1fc3RhdHNUaW1lci5zdG9wKCk7IG1fbG9j
YWxUaW1lci5zdG9wKCk7IGNhbmNlbCgpOworICAgIGlmIChtX3dpZmkuc3RhdGUoKSAhPSBRUHJv
Y2Vzczo6Tm90UnVubmluZykgeyBtX3dpZmkua2lsbCgpOyBtX3dpZmkud2FpdEZvckZpbmlzaGVk
KDUwMCk7IH0KK30KK1FTdHJpbmcgQ3JpbXNvblN0YXR1czo6Y29uZmlnRmlsZSgpIGNvbnN0IHsK
KyAgICByZXR1cm4gUVN0YW5kYXJkUGF0aHM6OndyaXRhYmxlTG9jYXRpb24oUVN0YW5kYXJkUGF0
aHM6OkFwcENvbmZpZ0xvY2F0aW9uKSArICIvY3JpbXNvbi1ob3N0cy5qc29uIjsKK30KK1FTdHJp
bmcgQ3JpbXNvblN0YXR1czo6bm9ybWFsaXplZFBpbihRU3RyaW5nIHBpbikgeworICAgIHBpbi5y
ZW1vdmUoJzonKTsgcGluLnJlbW92ZSgnICcpOyByZXR1cm4gcGluLnRvTG93ZXIoKTsKK30KK2Jv
b2wgQ3JpbXNvblN0YXR1czo6dmFsaWRFbmRwb2ludChjb25zdCBRU3RyaW5nJiB2YWx1ZSkgewor
ICAgIFFVcmwgdSh2YWx1ZSwgUVVybDo6U3RyaWN0TW9kZSk7CisgICAgcmV0dXJuIHUuaXNWYWxp
ZCgpICYmIHUuc2NoZW1lKCkgPT0gImh0dHBzIiAmJiAhdS5ob3N0KCkuaXNFbXB0eSgpICYmCisg
ICAgICAgIHUudXNlckluZm8oKS5pc0VtcHR5KCkgJiYgdS5xdWVyeSgpLmlzRW1wdHkoKSAmJiB1
LmZyYWdtZW50KCkuaXNFbXB0eSgpICYmCisgICAgICAgICh1LnBhdGgoKS5pc0VtcHR5KCkgfHwg
dS5wYXRoKCkgPT0gIi8iKSAmJiB1LnBvcnQoNDc5OTApID4gMDsKK30KK3ZvaWQgQ3JpbXNvblN0
YXR1czo6Y2FuY2VsKCkgeworICAgIGlmIChtX3JlcGx5KSB7IGRpc2Nvbm5lY3QobV9yZXBseSwg
bnVsbHB0ciwgdGhpcywgbnVsbHB0cik7IG1fcmVwbHktPmFib3J0KCk7IG1fcmVwbHktPmRlbGV0
ZUxhdGVyKCk7IG1fcmVwbHkgPSBudWxscHRyOyB9Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OnNl
bGVjdEhvc3QoUVN0cmluZyBpZCwgUVN0cmluZyBzdWdnZXN0ZWRVcmwpIHsKKyAgICBpZiAoaWQg
PT0gbV9ob3N0KSByZXR1cm47CisgICAgY2FuY2VsKCk7IG1fbmV0d29yay5jbGVhckNvbm5lY3Rp
b25DYWNoZSgpOyBtX2hvc3QgPSBpZDsgbV90b2tlbi5jbGVhcigpOyBtX3Bpbi5jbGVhcigpOwor
ICAgIG1fZW5kcG9pbnQgPSB2YWxpZEVuZHBvaW50KHN1Z2dlc3RlZFVybCkgPyBzdWdnZXN0ZWRV
cmwgOiBRU3RyaW5nKCk7CisgICAgUUZpbGUgZihjb25maWdGaWxlKCkpOworICAgIGlmIChmLm9w
ZW4oUUlPRGV2aWNlOjpSZWFkT25seSkpIHsKKyAgICAgICAgYXV0byBjID0gUUpzb25Eb2N1bWVu
dDo6ZnJvbUpzb24oZi5yZWFkQWxsKCkpLm9iamVjdCgpLnZhbHVlKGlkKS50b09iamVjdCgpOwor
ICAgICAgICBpZiAodmFsaWRFbmRwb2ludChjLnZhbHVlKCJ1cmwiKS50b1N0cmluZygpKSkgewor
ICAgICAgICAgICAgbV9lbmRwb2ludCA9IGMudmFsdWUoInVybCIpLnRvU3RyaW5nKCk7IG1fdG9r
ZW4gPSBjLnZhbHVlKCJ0b2tlbiIpLnRvU3RyaW5nKCk7IG1fcGluID0gYy52YWx1ZSgicGluIiku
dG9TdHJpbmcoKTsKKyAgICAgICAgfQorICAgIH0KKyAgICBtX3N0YXRzLmNsZWFyKCk7IG1fc3Rh
dHVzID0gaWQuaXNFbXB0eSgpID8gdHIoIkNob29zZSBhIGhvc3QgdG8gdmlldyBoYXJkd2FyZSBz
dGF0cyIpIDogdHIoIkNvbmZpZ3VyZSBhIFZpYmVwb2xsbyByZWFkLW9ubHkgc3RhdHMgdG9rZW4i
KTsKKyAgICBlbWl0IGNvbmZpZ0NoYW5nZWQoKTsgZW1pdCBzdGF0c0NoYW5nZWQoKTsgaWYgKG1f
dmlzaWJsZSkgcmVmcmVzaCgpOworfQorYm9vbCBDcmltc29uU3RhdHVzOjpjb25maWd1cmUoUVN0
cmluZyB1cmwsIFFTdHJpbmcgdG9rZW4sIFFTdHJpbmcgcGluKSB7CisgICAgcGluID0gbm9ybWFs
aXplZFBpbihwaW4pOworICAgIGlmIChtX2hvc3QuaXNFbXB0eSgpIHx8ICF2YWxpZEVuZHBvaW50
KHVybCkgfHwgKCFwaW4uaXNFbXB0eSgpICYmCisgICAgICAgIChwaW4uc2l6ZSgpICE9IDY0IHx8
IHBpbi5jb250YWlucyhRUmVndWxhckV4cHJlc3Npb24oIlteMC05YS1mXSIpKSkpKSB7CisgICAg
ICAgIGZhaWwodHIoIlVzZSBhbiBIVFRQUyBob3N0IFVSTCBhbmQgYW4gb3B0aW9uYWwgNjQtZGln
aXQgU0hBLTI1NiBjZXJ0aWZpY2F0ZSBmaW5nZXJwcmludCIpKTsgcmV0dXJuIGZhbHNlOworICAg
IH0KKyAgICAvLyBBIGJsYW5rIHRva2VuIGtlZXBzIHRoZSBvbGQgdG9rZW4gb25seSBmb3IgdGhl
IHNhbWUgZW5kcG9pbnQuCisgICAgaWYgKHRva2VuLmlzRW1wdHkoKSAmJiBRVXJsKHVybCkgPT0g
UVVybChtX2VuZHBvaW50KSkgdG9rZW4gPSBtX3Rva2VuOworICAgIGlmICh0b2tlbi5pc0VtcHR5
KCkgfHwgdG9rZW4uY29udGFpbnMoJ1xyJykgfHwgdG9rZW4uY29udGFpbnMoJ1xuJykgfHwgdG9r
ZW4uc2l6ZSgpID4gNDA5NikgeworICAgICAgICBmYWlsKHRyKCJBIHJlYWQtb25seSBWaWJlcG9s
bG8gQVBJIHRva2VuIGlzIHJlcXVpcmVkIikpOyByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIFFG
aWxlIGYoY29uZmlnRmlsZSgpKTsgUUpzb25PYmplY3QgYWxsOworICAgIGlmIChmLm9wZW4oUUlP
RGV2aWNlOjpSZWFkT25seSkpIGFsbCA9IFFKc29uRG9jdW1lbnQ6OmZyb21Kc29uKGYucmVhZEFs
bCgpKS5vYmplY3QoKTsKKyAgICBhbGxbbV9ob3N0XSA9IFFKc29uT2JqZWN0e3sidXJsIiwgdXJs
fSwgeyJ0b2tlbiIsIHRva2VufSwgeyJwaW4iLCBwaW59fTsKKyAgICBRRGlyKCkubWtwYXRoKFFG
aWxlSW5mbyhjb25maWdGaWxlKCkpLmFic29sdXRlUGF0aCgpKTsKKyAgICBRU2F2ZUZpbGUgb3V0
KGNvbmZpZ0ZpbGUoKSk7CisgICAgaWYgKCFvdXQub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkg
fHwgIW91dC5zZXRQZXJtaXNzaW9ucyh1c2VyT25seSkgfHwKKyAgICAgICAgb3V0LndyaXRlKFFK
c29uRG9jdW1lbnQoYWxsKS50b0pzb24oKSkgPCAwIHx8ICFvdXQuY29tbWl0KCkpIHsKKyAgICAg
ICAgZmFpbCh0cigiQ291bGQgbm90IHNhdmUgaG9zdCBhY2Nlc3Mgc2V0dGluZ3MiKSk7IHJldHVy
biBmYWxzZTsKKyAgICB9CisgICAgY2FuY2VsKCk7IG1fbmV0d29yay5jbGVhckNvbm5lY3Rpb25D
YWNoZSgpOyBtX2VuZHBvaW50ID0gdXJsOyBtX3Rva2VuID0gdG9rZW47IG1fcGluID0gcGluOwor
ICAgIG1fc3RhdHNUaW1lci5zZXRJbnRlcnZhbCgyMDAwKTsKKyAgICBtX3N0YXRzLmNsZWFyKCk7
IG1fc3RhdHVzID0gdHIoIkNvbm5lY3RpbmcgdG8gaG9zdCBzdGF0c+KApiIpOworICAgIGVtaXQg
Y29uZmlnQ2hhbmdlZCgpOyBlbWl0IHN0YXRzQ2hhbmdlZCgpOyByZWZyZXNoKCk7IHJldHVybiB0
cnVlOworfQordm9pZCBDcmltc29uU3RhdHVzOjpzZXRWaXNpYmxlKGJvb2wgdmlzaWJsZSkgewor
ICAgIG1fdmlzaWJsZSA9IHZpc2libGU7CisgICAgaWYgKHZpc2libGUpIHsgcmVmcmVzaExvY2Fs
KCk7IG1fc3RhdHNUaW1lci5zdGFydCgpOyByZWZyZXNoKCk7IH0KKyAgICBlbHNlIHsgbV9zdGF0
c1RpbWVyLnN0b3AoKTsgY2FuY2VsKCk7IH0KK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6ZmFpbChR
U3RyaW5nIG1lc3NhZ2UpIHsKKyAgICBtX3N0YXRzLmNsZWFyKCk7IG1fc3RhdHVzID0gbWVzc2Fn
ZTsKKyAgICBtX3N0YXRzVGltZXIuc2V0SW50ZXJ2YWwocU1pbigzMDAwMCwgcU1heCg0MDAwLCBt
X3N0YXRzVGltZXIuaW50ZXJ2YWwoKSAqIDIpKSk7CisgICAgZW1pdCBzdGF0c0NoYW5nZWQoKTsK
K30KK1FWYXJpYW50TWFwIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoY29uc3QgUUJ5dGVBcnJh
eSYgYnl0ZXMsIFFTdHJpbmcqIGVycm9yKSB7CisgICAgaWYgKGJ5dGVzLnNpemUoKSA+IDY1NTM2
KSB7ICplcnJvciA9ICJPdmVyc2l6ZWQgaG9zdCBzdGF0cyByZXNwb25zZSI7IHJldHVybiB7fTsg
fQorICAgIFFKc29uUGFyc2VFcnJvciBlOyBhdXRvIGRvYyA9IFFKc29uRG9jdW1lbnQ6OmZyb21K
c29uKGJ5dGVzLCAmZSk7CisgICAgaWYgKGUuZXJyb3IgIT0gUUpzb25QYXJzZUVycm9yOjpOb0Vy
cm9yIHx8ICFkb2MuaXNPYmplY3QoKSkgeyAqZXJyb3IgPSAiSW52YWxpZCBob3N0IHN0YXRzIHJl
c3BvbnNlIjsgcmV0dXJuIHt9OyB9CisgICAgYXV0byBvYmogPSBkb2Mub2JqZWN0KCk7IFFWYXJp
YW50TWFwIHJlc3VsdDsKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBrZXlzID0geyJjcHVfcGVyY2Vu
dCIsImNwdV90ZW1wX2MiLCJyYW1fdXNlZF9ieXRlcyIsInJhbV90b3RhbF9ieXRlcyIsInJhbV9w
ZXJjZW50IiwKKyAgICAgICAgImdwdV9wZXJjZW50IiwiZ3B1X2VuY29kZXJfcGVyY2VudCIsImdw
dV90ZW1wX2MiLCJ2cmFtX3VzZWRfYnl0ZXMiLCJ2cmFtX3RvdGFsX2J5dGVzIiwidnJhbV9wZXJj
ZW50IiwibmV0X3J4X2JwcyIsIm5ldF90eF9icHMifTsKKyAgICBib29sIHJlY29nbml6ZWQgPSBm
YWxzZTsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIGtleSA6IGtleXMpIHsKKyAgICAgICAgYXV0byB2
ID0gb2JqLnZhbHVlKGtleSk7IHJlY29nbml6ZWQgfD0gb2JqLmNvbnRhaW5zKGtleSk7CisgICAg
ICAgIGRvdWJsZSBuID0gdi50b0RvdWJsZSgtMSk7CisgICAgICAgIGlmICghdi5pc0RvdWJsZSgp
IHx8ICFzdGQ6OmlzZmluaXRlKG4pIHx8IG4gPCAwIHx8IChrZXkuZW5kc1dpdGgoInBlcmNlbnQi
KSAmJiBuID4gMTAwKSkgY29udGludWU7CisgICAgICAgIHJlc3VsdFtrZXldID0gbjsKKyAgICB9
CisgICAgZm9yIChjb25zdCBhdXRvJiBwcmVmaXggOiB7UVN0cmluZygicmFtIiksIFFTdHJpbmco
InZyYW0iKX0pIHsKKyAgICAgICAgZG91YmxlIHRvdGFsID0gcmVzdWx0LnZhbHVlKHByZWZpeCAr
ICJfdG90YWxfYnl0ZXMiKS50b0RvdWJsZSgpOworICAgICAgICBpZiAodG90YWwgPD0gMCkgeyBy
ZXN1bHQucmVtb3ZlKHByZWZpeCArICJfcGVyY2VudCIpOyByZXN1bHQucmVtb3ZlKHByZWZpeCAr
ICJfdXNlZF9ieXRlcyIpOyB9CisgICAgICAgIGVsc2UgaWYgKHJlc3VsdC5jb250YWlucyhwcmVm
aXggKyAiX3VzZWRfYnl0ZXMiKSkgeworICAgICAgICAgICAgZG91YmxlIHVzZWQgPSBxTWluKHJl
c3VsdC52YWx1ZShwcmVmaXggKyAiX3VzZWRfYnl0ZXMiKS50b0RvdWJsZSgpLCB0b3RhbCk7Cisg
ICAgICAgICAgICByZXN1bHRbcHJlZml4ICsgIl91c2VkX2J5dGVzIl0gPSB1c2VkOyByZXN1bHRb
cHJlZml4ICsgIl9wZXJjZW50Il0gPSB1c2VkICogMTAwIC8gdG90YWw7CisgICAgICAgIH0KKyAg
ICB9CisgICAgaWYgKCFyZWNvZ25pemVkKSB7ICplcnJvciA9ICJIb3N0IGRvZXMgbm90IGV4cG9z
ZSB0aGUgZXhwZWN0ZWQgVmliZXBvbGxvIHN0YXRzIGZpZWxkcyI7IHJldHVybiB7fTsgfQorICAg
IGVycm9yLT5jbGVhcigpOyByZXR1cm4gcmVzdWx0OworfQordm9pZCBDcmltc29uU3RhdHVzOjpy
ZWZyZXNoKCkgeworICAgIGlmICghbV92aXNpYmxlIHx8IG1fcmVwbHkgfHwgIWNvbmZpZ3VyZWQo
KSkgcmV0dXJuOworICAgIFFVcmwgdXJsKG1fZW5kcG9pbnQpOyB1cmwuc2V0UGF0aCgiL2FwaS9o
b3N0L3N0YXRzIik7CisgICAgUU5ldHdvcmtSZXF1ZXN0IHJlcSh1cmwpOworICAgIHJlcS5zZXRB
dHRyaWJ1dGUoUU5ldHdvcmtSZXF1ZXN0OjpSZWRpcmVjdFBvbGljeUF0dHJpYnV0ZSwgUU5ldHdv
cmtSZXF1ZXN0OjpNYW51YWxSZWRpcmVjdFBvbGljeSk7CisgICAgcmVxLnNldFRyYW5zZmVyVGlt
ZW91dCgzMDAwKTsKKyAgICByZXEuc2V0UmF3SGVhZGVyKCJBdXRob3JpemF0aW9uIiwgIkJlYXJl
ciAiICsgbV90b2tlbi50b1V0ZjgoKSk7CisgICAgcmVxLnNldFJhd0hlYWRlcigiQWNjZXB0Iiwg
ImFwcGxpY2F0aW9uL2pzb24iKTsKKyAgICBhdXRvIHJlcGx5ID0gbV9uZXR3b3JrLmdldChyZXEp
OyByZXBseS0+c2V0UmVhZEJ1ZmZlclNpemUoNjU1MzYpOyBtX3JlcGx5ID0gcmVwbHk7CisgICAg
YXV0byBkYXRhID0gc3RkOjptYWtlX3NoYXJlZDxRQnl0ZUFycmF5PigpOworICAgIGF1dG8gaW52
YWxpZFBpbiA9IHN0ZDo6bWFrZV9zaGFyZWQ8Ym9vbD4oZmFsc2UpOworICAgIGF1dG8gb3ZlcnNp
emVkID0gc3RkOjptYWtlX3NoYXJlZDxib29sPihmYWxzZSk7CisgICAgYXV0byBjZXJ0TWF0Y2hl
cyA9IFt0aGlzLCByZXBseV0geworICAgICAgICByZXR1cm4gbm9ybWFsaXplZFBpbihRU3RyaW5n
Ojpmcm9tTGF0aW4xKHJlcGx5LT5zc2xDb25maWd1cmF0aW9uKCkucGVlckNlcnRpZmljYXRlKCku
ZGlnZXN0KFFDcnlwdG9ncmFwaGljSGFzaDo6U2hhMjU2KS50b0hleCgpKSkgPT0gbV9waW47Cisg
ICAgfTsKKyAgICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtSZXBseTo6ZW5jcnlwdGVkLCB0aGlz
LCBbdGhpcywgcmVwbHksIGNlcnRNYXRjaGVzLCBpbnZhbGlkUGluXSB7CisgICAgICAgIGlmICgh
bV9waW4uaXNFbXB0eSgpICYmICFjZXJ0TWF0Y2hlcygpKSB7ICppbnZhbGlkUGluID0gdHJ1ZTsg
cmVwbHktPmFib3J0KCk7IH0KKyAgICB9KTsKKyAgICBjb25uZWN0KHJlcGx5LCAmUU5ldHdvcmtS
ZXBseTo6c3NsRXJyb3JzLCB0aGlzLCBbdGhpcywgcmVwbHksIGNlcnRNYXRjaGVzXShjb25zdCBR
TGlzdDxRU3NsRXJyb3I+JiBlcnJvcnMpIHsKKyAgICAgICAgaWYgKG1fcGluLmlzRW1wdHkoKSB8
fCAhY2VydE1hdGNoZXMoKSkgcmV0dXJuOworICAgICAgICBmb3IgKGNvbnN0IGF1dG8mIGUgOiBl
cnJvcnMpIHsKKyAgICAgICAgICAgIGlmIChlLmVycm9yKCkgIT0gUVNzbEVycm9yOjpTZWxmU2ln
bmVkQ2VydGlmaWNhdGUgJiYgZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6U2VsZlNpZ25lZENlcnRp
ZmljYXRlSW5DaGFpbiAmJgorICAgICAgICAgICAgICAgIGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6
OkNlcnRpZmljYXRlVW50cnVzdGVkICYmIGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6Okhvc3ROYW1l
TWlzbWF0Y2gpIHJldHVybjsKKyAgICAgICAgfQorICAgICAgICByZXBseS0+aWdub3JlU3NsRXJy
b3JzKGVycm9ycyk7IC8vIE9ubHkgdGhpcyBleHBsaWNpdGx5IHBpbm5lZCBob3N0IGNlcnRpZmlj
YXRlLgorICAgIH0pOworICAgIGNvbm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5OjpyZWFkeVJl
YWQsIHRoaXMsIFtyZXBseSwgZGF0YSwgb3ZlcnNpemVkXSB7CisgICAgICAgIGlmICgqb3ZlcnNp
emVkIHx8IHJlcGx5LT5pc0ZpbmlzaGVkKCkpIHJldHVybjsKKyAgICAgICAgaWYgKGRhdGEtPnNp
emUoKSArIHJlcGx5LT5ieXRlc0F2YWlsYWJsZSgpID4gNjU1MzYpIHsgKm92ZXJzaXplZCA9IHRy
dWU7IHJlcGx5LT5hYm9ydCgpOyByZXR1cm47IH0KKyAgICAgICAgZGF0YS0+YXBwZW5kKHJlcGx5
LT5yZWFkQWxsKCkpOworICAgIH0pOworICAgIGNvbm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5
OjpmaW5pc2hlZCwgdGhpcywgW3RoaXMsIHJlcGx5LCBkYXRhLCBpbnZhbGlkUGluLCBvdmVyc2l6
ZWRdIHsKKyAgICAgICAgbV9yZXBseSA9IG51bGxwdHI7CisgICAgICAgIGludCBzdGF0dXMgPSBy
ZXBseS0+YXR0cmlidXRlKFFOZXR3b3JrUmVxdWVzdDo6SHR0cFN0YXR1c0NvZGVBdHRyaWJ1dGUp
LnRvSW50KCk7CisgICAgICAgIGlmICgqb3ZlcnNpemVkKSBmYWlsKHRyKCJIb3N0IHN0YXRzIHJl
c3BvbnNlIGV4Y2VlZGVkIHRoZSBzaXplIGxpbWl0IikpOworICAgICAgICBlbHNlIGlmICgqaW52
YWxpZFBpbikgZmFpbCh0cigiSG9zdCBjZXJ0aWZpY2F0ZSBjaGFuZ2VkOyB2ZXJpZnkgdGhlIHNh
dmVkIGZpbmdlcnByaW50IikpOworICAgICAgICBlbHNlIGlmIChzdGF0dXMgPT0gNDAxIHx8IHN0
YXR1cyA9PSA0MDMpIGZhaWwodHIoIkhvc3Qgc3RhdHMgYWNjZXNzIGRlbmllZDogY2hlY2sgdGhl
IHJlYWQtb25seSB0b2tlbiIpKTsKKyAgICAgICAgZWxzZSBpZiAoc3RhdHVzID09IDQwNCkgZmFp
bCh0cigiVGhpcyBob3N0IGRvZXMgbm90IHByb3ZpZGUgVmliZXBvbGxvIGhhcmR3YXJlIHN0YXRz
IikpOworICAgICAgICBlbHNlIGlmIChyZXBseS0+ZXJyb3IoKSA9PSBRTmV0d29ya1JlcGx5OjpT
c2xIYW5kc2hha2VGYWlsZWRFcnJvcikgZmFpbCh0cigiVmVyaWZ5IHRoZSBob3N0IGNlcnRpZmlj
YXRlIGZpbmdlcnByaW50IGluIENvbmZpZ3VyZSIpKTsKKyAgICAgICAgZWxzZSBpZiAocmVwbHkt
PmVycm9yKCkgIT0gUU5ldHdvcmtSZXBseTo6Tm9FcnJvciB8fCBzdGF0dXMgIT0gMjAwKSBmYWls
KHRyKCJIb3N0IHN0YXRzIHVuYXZhaWxhYmxlOiBjaGVjayBjb25uZWN0aW9uIGFuZCByZWFsdGlt
ZSBzdGF0cyBzZXR0aW5nIikpOworICAgICAgICBlbHNlIHsKKyAgICAgICAgICAgIGRhdGEtPmFw
cGVuZChyZXBseS0+cmVhZEFsbCgpKTsgUVN0cmluZyBlcnJvcjsKKyAgICAgICAgICAgIGF1dG8g
cGFyc2VkID0gcGFyc2VTdGF0cygqZGF0YSwgJmVycm9yKTsKKyAgICAgICAgICAgIGlmICghZXJy
b3IuaXNFbXB0eSgpKSBmYWlsKGVycm9yKTsKKyAgICAgICAgICAgIGVsc2UgeyBtX3N0YXRzVGlt
ZXIuc2V0SW50ZXJ2YWwoMjAwMCk7IG1fc3RhdHMgPSBwYXJzZWQ7IG1fc3RhdHVzID0gdHIoIkhP
U1Qg4oCiIHJlY2VpdmVkICUxIikuYXJnKFFEYXRlVGltZTo6Y3VycmVudERhdGVUaW1lKCkudG9T
dHJpbmcoImhoOm1tOnNzIikpOyBlbWl0IHN0YXRzQ2hhbmdlZCgpOyB9CisgICAgICAgIH0KKyAg
ICAgICAgcmVwbHktPmRlbGV0ZUxhdGVyKCk7CisgICAgfSk7CisgICAgLy8gQWJzb2x1dGUgcmVx
dWVzdCBib3VuZCBldmVuIGlmIGEgcGVlciBrZWVwcyBzZW5kaW5nIG9jY2FzaW9uYWwgYnl0ZXMu
CisgICAgUVRpbWVyOjpzaW5nbGVTaG90KDM1MDAsIHJlcGx5LCBbcmVwbHldIHsgaWYgKCFyZXBs
eS0+aXNGaW5pc2hlZCgpKSByZXBseS0+YWJvcnQoKTsgfSk7Cit9CitRVmFyaWFudE1hcCBDcmlt
c29uU3RhdHVzOjpyZWFkTG9jYWwoY29uc3QgUVN0cmluZyYgcm9vdCkgeworICAgIFFWYXJpYW50
TWFwIG91dDsgUVN0cmluZ0xpc3QgbmV0d29ya3M7CisgICAgZm9yIChjb25zdCBhdXRvJiBuYW1l
IDogUURpcihyb290ICsgIi9jbGFzcy9uZXQiKS5lbnRyeUxpc3QoUURpcjo6RGlycyB8IFFEaXI6
Ok5vRG90QW5kRG90RG90KSkgeworICAgICAgICBpZiAobmFtZSA9PSAibG8iIHx8IHJlYWQocm9v
dCArICIvY2xhc3MvbmV0LyIgKyBuYW1lICsgIi9vcGVyc3RhdGUiKSAhPSAidXAiKSBjb250aW51
ZTsKKyAgICAgICAgbmV0d29ya3MgPDwgbmFtZTsKKyAgICB9CisgICAgb3V0WyJjb25uZWN0ZWQi
XSA9ICFuZXR3b3Jrcy5pc0VtcHR5KCk7IG91dFsibmV0d29yayJdID0gbmV0d29ya3MuaXNFbXB0
eSgpID8gdHIoIk5vIGFjdGl2ZSBuZXR3b3JrIGxpbmsiKSA6IG5ldHdvcmtzLmpvaW4oIiwgIik7
CisgICAgLy8gTGluayBzdGF0dXMgaXMgaW50ZW50aW9uYWxseSBub3QgcHJlc2VudGVkIGFzIGlu
dGVybmV0IHJlYWNoYWJpbGl0eS4KKyAgICBvdXRbImJhdHRlcnlQZXJjZW50Il0gPSAtMTsgb3V0
WyJiYXR0ZXJ5U3RhdGUiXSA9IHRyKCJCYXR0ZXJ5IHVuYXZhaWxhYmxlIik7CisgICAgZm9yIChj
b25zdCBhdXRvJiBuYW1lIDogUURpcihyb290ICsgIi9jbGFzcy9wb3dlcl9zdXBwbHkiKS5lbnRy
eUxpc3QoUURpcjo6RGlycyB8IFFEaXI6Ok5vRG90QW5kRG90RG90KSkgeworICAgICAgICBjb25z
dCBhdXRvIGJhc2UgPSByb290ICsgIi9jbGFzcy9wb3dlcl9zdXBwbHkvIiArIG5hbWUgKyAiLyI7
CisgICAgICAgIGlmIChyZWFkKGJhc2UgKyAidHlwZSIpICE9ICJCYXR0ZXJ5IiB8fCByZWFkKGJh
c2UgKyAicHJlc2VudCIpID09ICIwIikgY29udGludWU7CisgICAgICAgIGJvb2wgb2s7IGludCBj
YXAgPSByZWFkKGJhc2UgKyAiY2FwYWNpdHkiKS50b0ludCgmb2spOworICAgICAgICBpZiAob2sg
JiYgY2FwID49IDAgJiYgY2FwIDw9IDEwMCkgb3V0WyJiYXR0ZXJ5UGVyY2VudCJdID0gY2FwOwor
ICAgICAgICBjb25zdCBhdXRvIHN0YXRlID0gcmVhZChiYXNlICsgInN0YXR1cyIpOyBvdXRbImJh
dHRlcnlTdGF0ZSJdID0gc3RhdGUuaXNFbXB0eSgpID8gdHIoIlVua25vd24iKSA6IHN0YXRlOyBi
cmVhazsKKyAgICB9CisgICAgcmV0dXJuIG91dDsKK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6cmVm
cmVzaExvY2FsKCkgeworICAgIG1fbG9jYWwgPSByZWFkTG9jYWwoKTsgbV9sb2NhbFsid2lmaVNp
Z25hbCJdID0gLTE7IGVtaXQgbG9jYWxDaGFuZ2VkKCk7CisgICAgaWYgKG1fd2lmaS5zdGF0ZSgp
ID09IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSB7CisgICAgICAgIG1fd2lmaS5zdGFydCgibm1jbGki
LCB7Ii10IiwgIi0tZXNjYXBlIiwgIm5vIiwgIi1mIiwgIkFDVElWRSxTSUdOQUwsU1NJRCIsICJk
ZXZpY2UiLCAid2lmaSIsICJsaXN0IiwgIi0tcmVzY2FuIiwgIm5vIn0pOworICAgICAgICBRVGlt
ZXI6OnNpbmdsZVNob3QoMjAwMCwgJm1fd2lmaSwgW3RoaXNdIHsgaWYgKG1fd2lmaS5zdGF0ZSgp
ICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSBtX3dpZmkua2lsbCgpOyB9KTsKKyAgICB9Cit9CisK
K3N0YXRpYyB2b2lkIHJlZ2lzdGVyQ3JpbXNvblN0YXR1cygpIHsKKyAgICBxbWxSZWdpc3RlclNp
bmdsZXRvblR5cGU8Q3JpbXNvblN0YXR1cz4oIkNyaW1zb25TdGF0dXMiLCAxLCAwLCAiQ3JpbXNv
blN0YXR1cyIsCisgICAgICAgIFtdKFFRbWxFbmdpbmUqLCBRSlNFbmdpbmUqKSAtPiBRT2JqZWN0
KiB7IHJldHVybiBuZXcgQ3JpbXNvblN0YXR1cygpOyB9KTsKK30KK1FfQ09SRUFQUF9TVEFSVFVQ
X0ZVTkNUSU9OKHJlZ2lzdGVyQ3JpbXNvblN0YXR1cykKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGln
aHRvcy9jcmltc29uc3RhdHVzLmggYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5oCm5l
dyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwLi4yZGFjMGQxYwotLS0gL2Rldi9udWxs
CisrKyBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmgKQEAgLTAsMCArMSw1MiBAQAor
I3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4K
KyNpbmNsdWRlIDxRVGltZXI+CisjaW5jbHVkZSA8UU5ldHdvcmtBY2Nlc3NNYW5hZ2VyPgorI2lu
Y2x1ZGUgPFFQb2ludGVyPgorI2luY2x1ZGUgPFFOZXR3b3JrUmVwbHk+CisjaW5jbHVkZSA8UVBy
b2Nlc3M+CisKKy8vIE9wdGlvbmFsIGxhdW5jaGVyIHN0YXR1cy4gTmV2ZXIgcGFydGljaXBhdGVz
IGluIHRoZSBzdHJlYW1pbmcvZGVjb2RlciBwYXRoLgorY2xhc3MgQ3JpbXNvblN0YXR1cyA6IHB1
YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAg
bG9jYWwgUkVBRCBsb2NhbCBOT1RJRlkgbG9jYWxDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVZh
cmlhbnRNYXAgc3RhdHMgUkVBRCBzdGF0cyBOT1RJRlkgc3RhdHNDaGFuZ2VkKQorICAgIFFfUFJP
UEVSVFkoUVN0cmluZyBzdGF0dXMgUkVBRCBzdGF0dXMgTk9USUZZIHN0YXRzQ2hhbmdlZCkKKyAg
ICBRX1BST1BFUlRZKFFTdHJpbmcgZW5kcG9pbnQgUkVBRCBlbmRwb2ludCBOT1RJRlkgY29uZmln
Q2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgZmluZ2VycHJpbnQgUkVBRCBmaW5nZXJw
cmludCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgY29uZmlndXJl
ZCBSRUFEIGNvbmZpZ3VyZWQgTk9USUZZIGNvbmZpZ0NoYW5nZWQpCitwdWJsaWM6CisgICAgZXhw
bGljaXQgQ3JpbXNvblN0YXR1cyhRT2JqZWN0KiBwYXJlbnQgPSBudWxscHRyKTsKKyAgICB+Q3Jp
bXNvblN0YXR1cygpIG92ZXJyaWRlOworICAgIFFWYXJpYW50TWFwIGxvY2FsKCkgY29uc3QgeyBy
ZXR1cm4gbV9sb2NhbDsgfQorICAgIFFWYXJpYW50TWFwIHN0YXRzKCkgY29uc3QgeyByZXR1cm4g
bV9zdGF0czsgfQorICAgIFFTdHJpbmcgc3RhdHVzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0dXM7
IH0KKyAgICBRU3RyaW5nIGVuZHBvaW50KCkgY29uc3QgeyByZXR1cm4gbV9lbmRwb2ludDsgfQor
ICAgIFFTdHJpbmcgZmluZ2VycHJpbnQoKSBjb25zdCB7IHJldHVybiBtX3BpbjsgfQorICAgIGJv
b2wgY29uZmlndXJlZCgpIGNvbnN0IHsgcmV0dXJuICFtX2VuZHBvaW50LmlzRW1wdHkoKSAmJiAh
bV90b2tlbi5pc0VtcHR5KCk7IH0KKyAgICBRX0lOVk9LQUJMRSB2b2lkIHNlbGVjdEhvc3QoUVN0
cmluZyBpZCwgUVN0cmluZyBzdWdnZXN0ZWRVcmwpOworICAgIFFfSU5WT0tBQkxFIGJvb2wgY29u
ZmlndXJlKFFTdHJpbmcgdXJsLCBRU3RyaW5nIHRva2VuLCBRU3RyaW5nIHBpbik7CisgICAgUV9J
TlZPS0FCTEUgdm9pZCBzZXRWaXNpYmxlKGJvb2wgdmlzaWJsZSk7CisgICAgUV9JTlZPS0FCTEUg
dm9pZCByZWZyZXNoKCk7CisgICAgc3RhdGljIFFWYXJpYW50TWFwIHBhcnNlU3RhdHMoY29uc3Qg
UUJ5dGVBcnJheSYgYnl0ZXMsIFFTdHJpbmcqIGVycm9yKTsKKyAgICBzdGF0aWMgYm9vbCB2YWxp
ZEVuZHBvaW50KGNvbnN0IFFTdHJpbmcmIHVybCk7CisgICAgc3RhdGljIFFTdHJpbmcgbm9ybWFs
aXplZFBpbihRU3RyaW5nIHBpbik7CisgICAgc3RhdGljIFFWYXJpYW50TWFwIHJlYWRMb2NhbChj
b25zdCBRU3RyaW5nJiBzeXNSb290ID0gIi9zeXMiKTsKK3NpZ25hbHM6CisgICAgdm9pZCBsb2Nh
bENoYW5nZWQoKTsKKyAgICB2b2lkIHN0YXRzQ2hhbmdlZCgpOworICAgIHZvaWQgY29uZmlnQ2hh
bmdlZCgpOworcHJpdmF0ZToKKyAgICB2b2lkIHJlZnJlc2hMb2NhbCgpOworICAgIHZvaWQgZmFp
bChRU3RyaW5nIG1lc3NhZ2UpOworICAgIHZvaWQgY2FuY2VsKCk7CisgICAgUVN0cmluZyBjb25m
aWdGaWxlKCkgY29uc3Q7CisgICAgUVN0cmluZyBtX2hvc3QsIG1fZW5kcG9pbnQsIG1fdG9rZW4s
IG1fcGluLCBtX3N0YXR1cyA9ICJDaG9vc2UgYSBob3N0IHRvIHZpZXcgaGFyZHdhcmUgc3RhdHMi
OworICAgIFFWYXJpYW50TWFwIG1fbG9jYWwsIG1fc3RhdHM7CisgICAgUVRpbWVyIG1fbG9jYWxU
aW1lciwgbV9zdGF0c1RpbWVyOworICAgIFFQcm9jZXNzIG1fd2lmaTsKKyAgICBRTmV0d29ya0Fj
Y2Vzc01hbmFnZXIgbV9uZXR3b3JrOworICAgIFFQb2ludGVyPFFOZXR3b3JrUmVwbHk+IG1fcmVw
bHk7CisgICAgYm9vbCBtX3Zpc2libGUgPSBmYWxzZTsKK307CmRpZmYgLS1naXQgYS9hcHAvbW9v
bmxpZ2h0b3MvbWFuYWdlZHVwZGF0ZXMuY3BwIGIvYXBwL21vb25saWdodG9zL21hbmFnZWR1cGRh
dGVzLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uYWExNTM3OWEKLS0t
IC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvbWFuYWdlZHVwZGF0ZXMuY3BwCkBAIC0w
LDAgKzEsMTMyIEBACisvLyBNb29ubGlnaHQtT1Mgb3ducyB0aGlzIGN1c3RvbWl6ZWQgbmF0aXZl
IGNsaWVudC4gTm8gZmVlZCByZXF1ZXN0cywgYXNzZXQKKy8vIGRvd25sb2Fkcywgc3dhcHMgb3Ig
cmVsYXVuY2hlcyBhcmUgY29tcGlsZWQgaW50byB0aGlzIHVwZGF0ZSBpbXBsZW1lbnRhdGlvbi4K
KyNpbmNsdWRlICIuLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgiCisjaW5jbHVkZSA8UUNv
cmVBcHBsaWNhdGlvbj4KKyNpbmNsdWRlIDxRSnNvbk9iamVjdD4KKworc3RhdGljIFFTdHJpbmcg
c3RyaXBCdWlsZE1ldGFkYXRhKGNvbnN0IFFTdHJpbmcmIHZlcnNpb24pCit7CisgICAgaW50IHBs
dXNJZHggPSB2ZXJzaW9uLmluZGV4T2YoJysnKTsKKyAgICByZXR1cm4gcGx1c0lkeCA+PSAwID8g
dmVyc2lvbi5sZWZ0KHBsdXNJZHgpIDogdmVyc2lvbjsKK30KKworc3RhdGljIGJvb2wgaXNOdW1l
cmljSWRlbnRpZmllcihjb25zdCBRU3RyaW5nJiBzKQoreworICAgIGlmIChzLmlzRW1wdHkoKSkg
eworICAgICAgICByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIGZvciAoY29uc3QgUUNoYXImIGMg
OiBzKSB7CisgICAgICAgIGlmICghYy5pc0RpZ2l0KCkpIHsKKyAgICAgICAgICAgIHJldHVybiBm
YWxzZTsKKyAgICAgICAgfQorICAgIH0KKyAgICByZXR1cm4gdHJ1ZTsKK30KKworaW50IEF1dG9V
cGRhdGVDaGVja2VyOjpjb21wYXJlU2VtYW50aWNWZXJzaW9ucyhjb25zdCBRU3RyaW5nJiB2MSwg
Y29uc3QgUVN0cmluZyYgdjIpCit7CisgICAgUVN0cmluZyBzMSA9IHN0cmlwQnVpbGRNZXRhZGF0
YSh2MSk7CisgICAgUVN0cmluZyBzMiA9IHN0cmlwQnVpbGRNZXRhZGF0YSh2Mik7CisKKyAgICBp
bnQgZGFzaDEgPSBzMS5pbmRleE9mKCctJyk7CisgICAgaW50IGRhc2gyID0gczIuaW5kZXhPZign
LScpOworICAgIFFTdHJpbmcgYmFzZTEgPSBkYXNoMSA+PSAwID8gczEubGVmdChkYXNoMSkgOiBz
MTsKKyAgICBRU3RyaW5nIGJhc2UyID0gZGFzaDIgPj0gMCA/IHMyLmxlZnQoZGFzaDIpIDogczI7
CisgICAgUVN0cmluZyBwcmUxID0gZGFzaDEgPj0gMCA/IHMxLm1pZChkYXNoMSArIDEpIDogUVN0
cmluZygpOworICAgIFFTdHJpbmcgcHJlMiA9IGRhc2gyID49IDAgPyBzMi5taWQoZGFzaDIgKyAx
KSA6IFFTdHJpbmcoKTsKKworICAgIC8vIE51bWVyaWMgYmFzZSB2ZXJzaW9ucyBjb21wYXJlIGZp
cnN0ICgwLjQuMC1iZXRhLjAwMSA+IDAuMy4wKQorICAgIGNvbnN0IFFTdHJpbmdMaXN0IGJhc2VQ
YXJ0czEgPSBiYXNlMS5zcGxpdCgnLicpOworICAgIGNvbnN0IFFTdHJpbmdMaXN0IGJhc2VQYXJ0
czIgPSBiYXNlMi5zcGxpdCgnLicpOworICAgIGZvciAoaW50IGkgPSAwOyBpIDwgcU1heChiYXNl
UGFydHMxLmNvdW50KCksIGJhc2VQYXJ0czIuY291bnQoKSk7IGkrKykgeworICAgICAgICBxbG9u
Z2xvbmcgYjEgPSBpIDwgYmFzZVBhcnRzMS5jb3VudCgpID8gYmFzZVBhcnRzMVtpXS50b0xvbmdM
b25nKCkgOiAwOworICAgICAgICBxbG9uZ2xvbmcgYjIgPSBpIDwgYmFzZVBhcnRzMi5jb3VudCgp
ID8gYmFzZVBhcnRzMltpXS50b0xvbmdMb25nKCkgOiAwOworICAgICAgICBpZiAoYjEgIT0gYjIp
IHsKKyAgICAgICAgICAgIHJldHVybiBiMSA8IGIyID8gLTEgOiAxOworICAgICAgICB9CisgICAg
fQorCisgICAgLy8gRXF1YWwgYmFzZTogYSByZWxlYXNlIHdpdGggbm8gcHJlcmVsZWFzZSBzdWZm
aXggb3V0cmFua3MgYW55IHByZXJlbGVhc2UKKyAgICBpZiAocHJlMS5pc0VtcHR5KCkgIT0gcHJl
Mi5pc0VtcHR5KCkpIHsKKyAgICAgICAgcmV0dXJuIHByZTEuaXNFbXB0eSgpID8gMSA6IC0xOwor
ICAgIH0KKyAgICBpZiAocHJlMS5pc0VtcHR5KCkpIHsKKyAgICAgICAgcmV0dXJuIDA7CisgICAg
fQorCisgICAgLy8gVHdvIHByZXJlbGVhc2VzOiBjb21wYXJlIGRvdC1zZXBhcmF0ZWQgaWRlbnRp
ZmllcnMgbGVmdCB0byByaWdodC4KKyAgICAvLyBOdW1lcmljIGlkZW50aWZpZXJzIGNvbXBhcmUg
bnVtZXJpY2FsbHkgKGxlYWRpbmcgemVyb3MgdG9sZXJhdGVkIOKAlCBvdXIKKyAgICAvLyBDSSB6
ZXJvLXBhZHMgY291bnRlcnMpLCBhbHBoYW51bWVyaWMgb25lcyBsZXhpY2FsbHkgaW4gQVNDSUkg
b3JkZXIsIGFuZAorICAgIC8vIG51bWVyaWMgYWx3YXlzIHJhbmtzIGJlbG93IGFscGhhbnVtZXJp
Yy4gVGhpcyBpcyB3aGF0IG9yZGVycworICAgIC8vICJhbHBoYSIgPCAiYmV0YSIgPCAicmMiIGF0
IGFuIGVxdWFsIGJhc2Ug4oCUIHRoZSBwcm9wZXJ0eSB0aGUgcHJldmlvdXMKKyAgICAvLyBpbXBs
ZW1lbnRhdGlvbiBsYWNrZWQgKGl0IHNraXBwZWQgdGhlIHdvcmRzIGFuZCBjb21wYXJlZCBvbmx5
IG51bWJlcnMsCisgICAgLy8gc28gMC4zLjAtYmV0YS4wMDggd3JvbmdseSBvdXRyYW5rZWQgMC4z
LjAtcmMuMDAyKS4KKyAgICBjb25zdCBRU3RyaW5nTGlzdCBpZHMxID0gcHJlMS5zcGxpdCgnLicp
OworICAgIGNvbnN0IFFTdHJpbmdMaXN0IGlkczIgPSBwcmUyLnNwbGl0KCcuJyk7CisgICAgZm9y
IChpbnQgaSA9IDA7IGkgPCBxTWF4KGlkczEuY291bnQoKSwgaWRzMi5jb3VudCgpKTsgaSsrKSB7
CisgICAgICAgIGlmIChpID49IGlkczEuY291bnQoKSkgeworICAgICAgICAgICAgLy8gRXF1YWwg
cHJlZml4LCBmZXdlciBmaWVsZHMgPSBsb3dlciBwcmVjZWRlbmNlICjCpzExLjQuNCkKKyAgICAg
ICAgICAgIHJldHVybiAtMTsKKyAgICAgICAgfQorICAgICAgICBpZiAoaSA+PSBpZHMyLmNvdW50
KCkpIHsKKyAgICAgICAgICAgIHJldHVybiAxOworICAgICAgICB9CisgICAgICAgIGJvb2wgbnVt
MSA9IGlzTnVtZXJpY0lkZW50aWZpZXIoaWRzMVtpXSk7CisgICAgICAgIGJvb2wgbnVtMiA9IGlz
TnVtZXJpY0lkZW50aWZpZXIoaWRzMltpXSk7CisgICAgICAgIGlmIChudW0xICYmIG51bTIpIHsK
KyAgICAgICAgICAgIHFsb25nbG9uZyBwMSA9IGlkczFbaV0udG9Mb25nTG9uZygpOworICAgICAg
ICAgICAgcWxvbmdsb25nIHAyID0gaWRzMltpXS50b0xvbmdMb25nKCk7CisgICAgICAgICAgICBp
ZiAocDEgIT0gcDIpIHsKKyAgICAgICAgICAgICAgICByZXR1cm4gcDEgPCBwMiA/IC0xIDogMTsK
KyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgICAgICBlbHNlIGlmIChudW0xICE9IG51bTIp
IHsKKyAgICAgICAgICAgIC8vIE51bWVyaWMgaWRlbnRpZmllcnMgcmFuayBiZWxvdyBhbHBoYW51
bWVyaWMgb25lcyAowqcxMS40LjMpCisgICAgICAgICAgICByZXR1cm4gbnVtMSA/IC0xIDogMTsK
KyAgICAgICAgfQorICAgICAgICBlbHNlIHsKKyAgICAgICAgICAgIGludCBjbXAgPSBRU3RyaW5n
Ojpjb21wYXJlKGlkczFbaV0sIGlkczJbaV0pOworICAgICAgICAgICAgaWYgKGNtcCAhPSAwKSB7
CisgICAgICAgICAgICAgICAgcmV0dXJuIGNtcCA8IDAgPyAtMSA6IDE7CisgICAgICAgICAgICB9
CisgICAgICAgIH0KKyAgICB9CisgICAgcmV0dXJuIDA7Cit9CisKK0F1dG9VcGRhdGVDaGVja2Vy
OjpBdXRvVXBkYXRlQ2hlY2tlcihRT2JqZWN0KiBwYXJlbnQpIDoKKyAgICBRT2JqZWN0KHBhcmVu
dCksIG1fQ2hlY2tJbkZsaWdodChmYWxzZSksIG1fQ2hlY2tJc01hbnVhbChmYWxzZSksCisgICAg
bV9VcGRhdGVBdmFpbGFibGUoZmFsc2UpLCBtX09mZmVyQXZhaWxhYmxlKGZhbHNlKSwgbV9JbnN0
YWxsaW5nKGZhbHNlKQoreworICAgIGNsZWFyT2ZmZXIoKTsKKyAgICBzZXRTdGF0dXModHIoIiUx
LiBVcGRhdGVzIGFyZSBtYW5hZ2VkIGJ5IE1vb25saWdodC1PUy4gR2V0IHRoZSBtYXRjaGluZyBP
UyBpbWFnZSBmcm9tICUyOyB1cHN0cmVhbSBWaWJlbWlzIHVwZGF0ZXMgYXJlIGRpc2FibGVkLiIp
LmFyZyhjdXJyZW50VmVyc2lvbigpLCBtX1JlbGVhc2VVcmwpKTsKK30KK1FTdHJpbmcgQXV0b1Vw
ZGF0ZUNoZWNrZXI6OmN1cnJlbnRWZXJzaW9uKCkgY29uc3QKK3sKKyAgICByZXR1cm4gdHIoIlZp
YmVtaXMgJTEgwrcgTW9vbmxpZ2h0LU9TIGN1c3RvbWl6ZWQiKS5hcmcoUUNvcmVBcHBsaWNhdGlv
bjo6YXBwbGljYXRpb25WZXJzaW9uKCkpOworfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6Y2xl
YXJPZmZlcigpCit7CisgICAgbV9VcGRhdGVBdmFpbGFibGUgPSBmYWxzZTsgbV9PZmZlckF2YWls
YWJsZSA9IGZhbHNlOworICAgIG1fT2ZmZXJWZXJzaW9uLmNsZWFyKCk7IG1fQXNzZXRVcmwuY2xl
YXIoKTsgbV9PZmZlclRpZXIgPSAtMTsKKyAgICBtX1JlbGVhc2VVcmwgPSBRU3RyaW5nTGl0ZXJh
bCgiaHR0cHM6Ly9naXRodWIuY29tL3RoM2QzY2szci9Nb29ubGlnaHQtT1MvcmVsZWFzZXMiKTsK
K30KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6OnNldFN0YXR1cyhjb25zdCBRU3RyaW5nJiBtZXNz
YWdlKQoreworICAgIGlmIChtX1N0YXR1c01lc3NhZ2UgIT0gbWVzc2FnZSkgeyBtX1N0YXR1c01l
c3NhZ2UgPSBtZXNzYWdlOyBlbWl0IHN0YXRlQ2hhbmdlZCgpOyB9Cit9Cit2b2lkIEF1dG9VcGRh
dGVDaGVja2VyOjpzdGFydCgpIHsgLyogTm8gdGltZXIgYW5kIG5vIGJhY2tncm91bmQgdXBkYXRl
IHJlcXVlc3RzLiAqLyB9Citib29sIEF1dG9VcGRhdGVDaGVja2VyOjpjYW5JbnN0YWxsVXBkYXRl
cygpIGNvbnN0IHsgcmV0dXJuIGZhbHNlOyB9Citib29sIEF1dG9VcGRhdGVDaGVja2VyOjpjYW5J
bnN0YWxsKCkgY29uc3QgeyByZXR1cm4gZmFsc2U7IH0KK3ZvaWQgQXV0b1VwZGF0ZUNoZWNrZXI6
OmNoYW5uZWxDaGFuZ2VkKCkgeyBjaGVja05vdygpOyB9Cit2b2lkIEF1dG9VcGRhdGVDaGVja2Vy
OjpjaGVja05vdygpCit7CisgICAgY2xlYXJPZmZlcigpOworICAgIHNldFN0YXR1cyh0cigiVXBk
YXRlcyBhcmUgbWFuYWdlZCBieSBNb29ubGlnaHQtT1MuIERvd25sb2FkIHRoZSBtYXRjaGluZyBP
UyBpbWFnZSBmcm9tICUxLiBUaGlzIGNsaWVudCBuZXZlciBpbnN0YWxscyB1cHN0cmVhbSBWaWJl
bWlzIHJlbGVhc2VzLiIpLmFyZyhtX1JlbGVhc2VVcmwpKTsKKyAgICBlbWl0IHN0YXRlQ2hhbmdl
ZCgpOyBlbWl0IGNoZWNrQ29tcGxldGVkKHRydWUsIGZhbHNlKTsKK30KK3ZvaWQgQXV0b1VwZGF0
ZUNoZWNrZXI6Omluc3RhbGwoKQoreworICAgIGNoZWNrTm93KCk7CisgICAgZW1pdCBpbnN0YWxs
RmFpbGVkKHRyKCJTdGFuZGFsb25lIFZpYmVtaXMgaW5zdGFsbGF0aW9uIGlzIGRpc2FibGVkIGlu
IE1vb25saWdodC1PUy4iKSwgbV9SZWxlYXNlVXJsKTsKK30KZGlmZiAtLWdpdCBhL2FwcC9tb29u
bGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAgYi9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJv
bHMuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwLi40N2VlYWZiOAotLS0g
L2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAKQEAgLTAs
MCArMSw4MiBAQAorI2luY2x1ZGUgInN5c3RlbWNvbnRyb2xzLmgiCisjaW5jbHVkZSA8UUNvcmVB
cHBsaWNhdGlvbj4KKyNpbmNsdWRlIDxRSnNvbkRvY3VtZW50PgorI2luY2x1ZGUgPFFKc29uT2Jq
ZWN0PgorI2luY2x1ZGUgPFFKc29uQXJyYXk+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNs
dWRlIDxRRmlsZUluZm8+CitTeXN0ZW1Db250cm9sczo6U3lzdGVtQ29udHJvbHMoUU9iamVjdCog
cGFyZW50KSA6IFFPYmplY3QocGFyZW50KSB7CisgICAgbV90aW1lb3V0LnNldFNpbmdsZVNob3Qo
dHJ1ZSk7CisgICAgY29ubmVjdCgmbV90aW1lb3V0LCAmUVRpbWVyOjp0aW1lb3V0LCB0aGlzLCBb
dGhpc10geyBmYWlsKHRyKCJPcGVyYXRpb24gdGltZWQgb3V0LiBSZXRyeSBvciB1c2UgdGhlIGRp
YWdub3N0aWMgc2hlbGwuIikpOyB9KTsKKyAgICBjb25uZWN0KCZtX3Byb2Nlc3MsICZRUHJvY2Vz
czo6c3RhcnRlZCwgdGhpcywgW3RoaXNdIHsgcmVxdWVzdChtX21vZGUgKyAiLWxpc3QiKTsgfSk7
CisgICAgY29ubmVjdCgmbV9wcm9jZXNzLCAmUVByb2Nlc3M6OnJlYWR5UmVhZFN0YW5kYXJkRXJy
b3IsIHRoaXMsIFt0aGlzXSB7IG1fcHJvY2Vzcy5yZWFkQWxsU3RhbmRhcmRFcnJvcigpOyB9KTsK
KyAgICBjb25uZWN0KCZtX3Byb2Nlc3MsICZRUHJvY2Vzczo6cmVhZHlSZWFkU3RhbmRhcmRPdXRw
dXQsIHRoaXMsIFt0aGlzXSB7CisgICAgICAgIG1fYnVmZmVyICs9IG1fcHJvY2Vzcy5yZWFkQWxs
U3RhbmRhcmRPdXRwdXQoKTsKKyAgICAgICAgaWYgKG1fYnVmZmVyLnNpemUoKSA+IDY1NTM2KSB7
IGZhaWwodHIoIkludmFsaWQgc3lzdGVtIHJlc3BvbnNlLiIpKTsgcmV0dXJuOyB9CisgICAgICAg
IHdoaWxlIChtX2J1ZmZlci5jb250YWlucygnXG4nKSkgeworICAgICAgICAgICAgaW50IGVuZCA9
IG1fYnVmZmVyLmluZGV4T2YoJ1xuJyk7CisgICAgICAgICAgICBRSnNvblBhcnNlRXJyb3IgZXJy
b3I7CisgICAgICAgICAgICBhdXRvIGRvY3VtZW50ID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24o
bV9idWZmZXIubGVmdChlbmQpLCAmZXJyb3IpOworICAgICAgICAgICAgbV9idWZmZXIucmVtb3Zl
KDAsIGVuZCArIDEpOworICAgICAgICAgICAgaWYgKGVycm9yLmVycm9yICE9IFFKc29uUGFyc2VF
cnJvcjo6Tm9FcnJvciB8fCAhZG9jdW1lbnQuaXNPYmplY3QoKSkgeyBmYWlsKHRyKCJJbnZhbGlk
IHN5c3RlbSByZXNwb25zZS4iKSk7IHJldHVybjsgfQorICAgICAgICAgICAgYXV0byB2YWx1ZSA9
IGRvY3VtZW50Lm9iamVjdCgpOworICAgICAgICAgICAgaWYgKHZhbHVlLmNvbnRhaW5zKCJwcm9t
cHQiKSkgeworICAgICAgICAgICAgICAgIG1fcHJvbXB0ID0gdmFsdWUudmFsdWUoInByb21wdCIp
LnRvU3RyaW5nKCkubGVmdCgxMDI0KTsKKyAgICAgICAgICAgICAgICBtX3RpbWVvdXQuc3RhcnQo
MTIwMDAwKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGlmICh2YWx1ZS52YWx1ZSgiZG9u
ZSIpLnRvQm9vbCgpKSB7CisgICAgICAgICAgICAgICAgbV90aW1lb3V0LnN0b3AoKTsgbV9idXN5
ID0gZmFsc2U7IG1fcHJvbXB0LmNsZWFyKCk7CisgICAgICAgICAgICAgICAgaWYgKHZhbHVlLmNv
bnRhaW5zKCJpdGVtcyIpKSB7CisgICAgICAgICAgICAgICAgICAgIGF1dG8gZW50cmllcyA9IHZh
bHVlLnZhbHVlKCJpdGVtcyIpLnRvQXJyYXkoKTsKKyAgICAgICAgICAgICAgICAgICAgaWYgKGVu
dHJpZXMuc2l6ZSgpID4gNjQpIHsgZmFpbCh0cigiSW52YWxpZCBkZXZpY2UgbGlzdC4iKSk7IHJl
dHVybjsgfQorICAgICAgICAgICAgICAgICAgICBtX2l0ZW1zID0gZW50cmllcy50b1ZhcmlhbnRM
aXN0KCk7CisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIG1fc3RhdHVzID0gdmFs
dWUuY29udGFpbnMoImVycm9yIikgPyB2YWx1ZS52YWx1ZSgiZXJyb3IiKS50b1N0cmluZygpLmxl
ZnQoMTAyNCkgOiB2YWx1ZS52YWx1ZSgic3RhdHVzIikudG9TdHJpbmcoKTsKKyAgICAgICAgICAg
IH0KKyAgICAgICAgICAgIGVtaXQgY2hhbmdlZCgpOworICAgICAgICB9CisgICAgfSk7CisgICAg
Y29ubmVjdCgmbV9wcm9jZXNzLCAmUVByb2Nlc3M6OmVycm9yT2NjdXJyZWQsIHRoaXMsIFt0aGlz
XShRUHJvY2Vzczo6UHJvY2Vzc0Vycm9yKSB7CisgICAgICAgIGlmICghbV9tb2RlLmlzRW1wdHko
KSkgZmFpbCh0cigiU3lzdGVtIGNvbnRyb2xzIGFyZSB1bmF2YWlsYWJsZS4gVXNlIHRoZSBkaWFn
bm9zdGljIHNoZWxsLiIpKTsKKyAgICB9KTsKKyAgICBjb25uZWN0KCZtX3Byb2Nlc3MsIFFPdmVy
bG9hZDxpbnQsUVByb2Nlc3M6OkV4aXRTdGF0dXM+OjpvZigmUVByb2Nlc3M6OmZpbmlzaGVkKSwg
dGhpcywgW3RoaXNdKGludCwgUVByb2Nlc3M6OkV4aXRTdGF0dXMpIHsKKyAgICAgICAgaWYgKCFt
X21vZGUuaXNFbXB0eSgpKSB7IG1fdGltZW91dC5zdG9wKCk7IG1fYnVzeSA9IGZhbHNlOyBtX3By
b21wdC5jbGVhcigpOyBtX3N0YXR1cyA9IHRyKCJTeXN0ZW0gaGVscGVyIHN0b3BwZWQuIENsb3Nl
IGFuZCByZW9wZW4gdGhpcyBwYW5lbC4iKTsgZW1pdCBjaGFuZ2VkKCk7IH0KKyAgICB9KTsKK30K
K1N5c3RlbUNvbnRyb2xzOjp+U3lzdGVtQ29udHJvbHMoKSB7IGNsb3NlKCk7IGlmICghbV9wcm9j
ZXNzLndhaXRGb3JGaW5pc2hlZCg1MDApKSB7IG1fcHJvY2Vzcy5raWxsKCk7IG1fcHJvY2Vzcy53
YWl0Rm9yRmluaXNoZWQoNTAwKTsgfSB9Cit2b2lkIFN5c3RlbUNvbnRyb2xzOjpzZW5kKGNvbnN0
IFFKc29uT2JqZWN0JiB2YWx1ZSkgeyBtX3Byb2Nlc3Mud3JpdGUoUUpzb25Eb2N1bWVudCh2YWx1
ZSkudG9Kc29uKFFKc29uRG9jdW1lbnQ6OkNvbXBhY3QpICsgJ1xuJyk7IH0KK3ZvaWQgU3lzdGVt
Q29udHJvbHM6Om9wZW4oUVN0cmluZyBtb2RlKSB7CisgICAgaWYgKG1vZGUgIT0gIndpZmkiICYm
IG1vZGUgIT0gImJ0IikgcmV0dXJuOworICAgIGNsb3NlKCk7CisgICAgaWYgKG1fcHJvY2Vzcy5z
dGF0ZSgpICE9IFFQcm9jZXNzOjpOb3RSdW5uaW5nKSB7IG1fcHJvY2Vzcy5raWxsKCk7IG1fcHJv
Y2Vzcy53YWl0Rm9yRmluaXNoZWQoNTAwKTsgfQorICAgIG1fbW9kZSA9IG1vZGU7IG1faXRlbXMu
Y2xlYXIoKTsgbV9idWZmZXIuY2xlYXIoKTsgbV9zdGF0dXMgPSB0cigiTG9hZGluZ+KApiIpOyBl
bWl0IGNoYW5nZWQoKTsKKyAgICBRU3RyaW5nIGhlbHBlciA9ICIvdXNyL2xvY2FsL2xpYmV4ZWMv
bW9vbmxpZ2h0LW9zL3N5c3RlbS1jb250cm9scy5weSI7CisjaWZkZWYgTU9PTkxJR0hUX0NPTlRS
T0xTX1RFU1QKKyAgICBoZWxwZXIgPSBxRW52aXJvbm1lbnRWYXJpYWJsZSgiTU9PTkxJR0hUX0NP
TlRST0xTX0ZJWFRVUkUiLCBoZWxwZXIpOworI2VuZGlmCisgICAgbV9wcm9jZXNzLnN0YXJ0KCJw
eXRob24zIiwge2hlbHBlcn0pOworfQordm9pZCBTeXN0ZW1Db250cm9sczo6cmVxdWVzdChRU3Ry
aW5nIGFjdGlvbiwgUVN0cmluZyBpZCwgYm9vbCBjb25maXJtKSB7CisgICAgaWYgKG1fYnVzeSB8
fCBtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vzczo6UnVubmluZyB8fCAhYWN0aW9uLnN0YXJ0
c1dpdGgobV9tb2RlICsgIi0iKSkgcmV0dXJuOworICAgIGNvbnN0IFFTdHJpbmdMaXN0IGFsbG93
ZWQgPSB7IndpZmktbGlzdCIsICJ3aWZpLXNjYW4iLCAid2lmaS1jb25uZWN0IiwgIndpZmktZGlz
Y29ubmVjdCIsICJidC1saXN0IiwgImJ0LXNjYW4iLCAiYnQtY29ubmVjdCIsICJidC1kaXNjb25u
ZWN0IiwgImJ0LWZvcmdldCJ9OworICAgIGlmICghYWxsb3dlZC5jb250YWlucyhhY3Rpb24pKSBy
ZXR1cm47CisgICAgbV9idXN5ID0gdHJ1ZTsgbV9wcm9tcHQuY2xlYXIoKTsgbV9zdGF0dXMgPSB0
cigiV29ya2luZ+KApiIpOyBtX3RpbWVvdXQuc3RhcnQoMTIwMDAwKTsKKyAgICBzZW5kKHt7ImFj
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
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwLi44ZWJlYzg0YQotLS0gL2Rldi9udWxsCisrKyBi
L2FwcC9tb29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5oCkBAIC0wLDAgKzEsMzUgQEAKKyNwcmFn
bWEgb25jZQorI2luY2x1ZGUgPFFPYmplY3Q+CisjaW5jbHVkZSA8UUpzb25PYmplY3Q+CisjaW5j
bHVkZSA8UVByb2Nlc3M+CisjaW5jbHVkZSA8UVRpbWVyPgorI2luY2x1ZGUgPFFWYXJpYW50TGlz
dD4KK2NsYXNzIFN5c3RlbUNvbnRyb2xzIDogcHVibGljIFFPYmplY3QgeworICAgIFFfT0JKRUNU
CisgICAgUV9QUk9QRVJUWShRVmFyaWFudExpc3QgaXRlbXMgUkVBRCBpdGVtcyBOT1RJRlkgY2hh
bmdlZCkKKyAgICBRX1BST1BFUlRZKFFTdHJpbmcgc3RhdHVzIFJFQUQgc3RhdHVzIE5PVElGWSBj
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBwcm9tcHQgUkVBRCBwcm9tcHQgTk9USUZZ
IGNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShib29sIGJ1c3kgUkVBRCBidXN5IE5PVElGWSBjaGFu
Z2VkKQorcHVibGljOgorICAgIGV4cGxpY2l0IFN5c3RlbUNvbnRyb2xzKFFPYmplY3QqIHBhcmVu
dCA9IG51bGxwdHIpOworICAgIH5TeXN0ZW1Db250cm9scygpOworICAgIFFWYXJpYW50TGlzdCBp
dGVtcygpIGNvbnN0IHsgcmV0dXJuIG1faXRlbXM7IH0KKyAgICBRU3RyaW5nIHN0YXR1cygpIGNv
bnN0IHsgcmV0dXJuIG1fc3RhdHVzOyB9CisgICAgUVN0cmluZyBwcm9tcHQoKSBjb25zdCB7IHJl
dHVybiBtX3Byb21wdDsgfQorICAgIGJvb2wgYnVzeSgpIGNvbnN0IHsgcmV0dXJuIG1fYnVzeTsg
fQorICAgIFFfSU5WT0tBQkxFIHZvaWQgb3BlbihRU3RyaW5nIG1vZGUpOworICAgIFFfSU5WT0tB
QkxFIHZvaWQgcmVxdWVzdChRU3RyaW5nIGFjdGlvbiwgUVN0cmluZyBpZCA9IFFTdHJpbmcoKSwg
Ym9vbCBjb25maXJtID0gZmFsc2UpOworICAgIFFfSU5WT0tBQkxFIHZvaWQgYW5zd2VyKFFTdHJp
bmcgdmFsdWUpOworICAgIFFfSU5WT0tBQkxFIHZvaWQgY2xvc2UoKTsKK3NpZ25hbHM6CisgICAg
dm9pZCBjaGFuZ2VkKCk7Citwcml2YXRlOgorICAgIHZvaWQgc2VuZChjb25zdCBRSnNvbk9iamVj
dCYgdmFsdWUpOworICAgIHZvaWQgZmFpbChRU3RyaW5nIG1lc3NhZ2UpOworICAgIFFQcm9jZXNz
IG1fcHJvY2VzczsKKyAgICBRVGltZXIgbV90aW1lb3V0OworICAgIFFCeXRlQXJyYXkgbV9idWZm
ZXI7CisgICAgUVZhcmlhbnRMaXN0IG1faXRlbXM7CisgICAgUVN0cmluZyBtX21vZGUsIG1fc3Rh
dHVzLCBtX3Byb21wdDsKKyAgICBib29sIG1fYnVzeSA9IGZhbHNlOworfTsKZGlmZiAtLWdpdCBh
L2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbCBiL2FwcC9tb29ubGlnaHRvcy90ZXN0
cy9IYXJuZXNzLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMC4uNDdlMjcx
NTIKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvSGFybmVzcy5xbWwK
QEAgLTAsMCArMSwxOSBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250
cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZp
YmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgU3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCitpbXBv
cnQgIi4uLy4uL2d1aSIKK0FwcGxpY2F0aW9uV2luZG93IHsKKyAgICBNYXRlcmlhbC50aGVtZTog
TWF0ZXJpYWwuRGFyaworICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAg
TWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdXaW5kb3cKKyAgICBNYXRlcmlhbC5mb3Jl
Z3JvdW5kOiBWYlRva2Vucy50ZXh0CisgICAgY29sb3I6IFZiVG9rZW5zLmJnQXBwCisgICAgd2lk
dGg6IDEyODA7IGhlaWdodDogODAwOyB2aXNpYmxlOiB0cnVlCisgICAgZnVuY3Rpb24gY2hvb3Nl
QWNjZW50KGkpIHsgU3RyZWFtaW5nUHJlZmVyZW5jZXMudWlBY2NlbnRJbmRleCA9IGkgfQorICAg
IEl0ZW0geyBpZDogc3RhY2tWaWV3IH0KKyAgICBRdE9iamVjdCB7IG9iamVjdE5hbWU6ICJ0ZXN0
U3RhdGUiOyBwcm9wZXJ0eSBjb2xvciBhY2NlbnQ6IFZiVG9rZW5zLmFjY2VudDsgcHJvcGVydHkg
Y29sb3IgcHJlc3NlZDogVmJUb2tlbnMuYWNjZW50UHJlc3NlZCB9CisgICAgQ3JpbXNvblN0YXR1
c0RpYWxvZyB7IG9iamVjdE5hbWU6ICJ0ZXN0UGFuZWwiIH0KKyAgICBTeXN0ZW1Db25uZWN0aW9u
c0RpYWxvZyB7IG9iamVjdE5hbWU6ICJjb25uZWN0aW9uc1BhbmVsIiB9Cit9CmRpZmYgLS1naXQg
YS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvUHJlZmVyZW5jZXMucW1sIGIvYXBwL21vb25saWdodG9z
L3Rlc3RzL1ByZWZlcmVuY2VzLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
MC4uZGZkYWYwMmMKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvUHJl
ZmVyZW5jZXMucW1sCkBAIC0wLDAgKzEsMyBAQAorcHJhZ21hIFNpbmdsZXRvbgoraW1wb3J0IFF0
UXVpY2sgMi45CitRdE9iamVjdCB7IHByb3BlcnR5IGludCB1aUFjY2VudEluZGV4OiA0OyBwcm9w
ZXJ0eSBib29sIHVpU2hvd0hpbnRzOiB0cnVlIH0KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRv
cy90ZXN0cy90ZXN0LWNyaW1zb24uY3BwIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3Jp
bXNvbi5jcHAKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAuLjUzYTlmNDRmCi0t
LSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAK
QEAgLTAsMCArMSwyMTUgQEAKKyNpbmNsdWRlIDxRdFRlc3Q+CisjaW5jbHVkZSA8UVRlbXBvcmFy
eURpcj4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFRbWxDb21wb25lbnQ+Cisj
aW5jbHVkZSA8UVFtbENvbnRleHQ+CisjaW5jbHVkZSA8UVF1aWNrU3R5bGU+CisjaW5jbHVkZSA8
UVF1aWNrV2luZG93PgorI2luY2x1ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFUY3BTZXJ2ZXI+Cisj
aW5jbHVkZSA8UVNzbFNvY2tldD4KKyNpbmNsdWRlIDxRU3NsS2V5PgorI2luY2x1ZGUgPFFTc2xD
ZXJ0aWZpY2F0ZT4KKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVkZSA8bWVt
b3J5PgorI2luY2x1ZGUgPFFTdGFuZGFyZFBhdGhzPgorI2luY2x1ZGUgPFFEaXI+CisjaW5jbHVk
ZSA8UUZpbGVJbmZvPgorI2luY2x1ZGUgIi4uL2NyaW1zb25zdGF0dXMuaCIKKyNpbmNsdWRlICIu
Li9zeXN0ZW1jb250cm9scy5oIgorI2luY2x1ZGUgIi4uLy4uL2JhY2tlbmQvYXV0b3VwZGF0ZWNo
ZWNrZXIuaCIKKworY2xhc3MgVGxzRml4dHVyZSA6IHB1YmxpYyBRVGNwU2VydmVyIHsKK3B1Ymxp
YzoKKyAgICBRQnl0ZUFycmF5IGJvZHkgPSBSIih7ImNwdV9wZXJjZW50IjozNy41LCJyYW1fdXNl
ZF9ieXRlcyI6NTAsInJhbV90b3RhbF9ieXRlcyI6MTAwfSkiOworICAgIGludCBjb2RlID0gMjAw
LCByZXF1ZXN0cyA9IDA7CisgICAgYm9vbCByZXNwb25kID0gdHJ1ZTsKKyAgICBRQnl0ZUFycmF5
IGF1dGhvcml6YXRpb247CisgICAgUVNzbENlcnRpZmljYXRlIGNlcnQ7CisgICAgUVNzbEtleSBr
ZXk7CisgICAgVGxzRml4dHVyZSgpIHsKKyAgICAgICAgUUZpbGUgYyhxRW52aXJvbm1lbnRWYXJp
YWJsZSgiQ1JJTVNPTl9URVNUX0NFUlQiKSk7IGMub3BlbihRSU9EZXZpY2U6OlJlYWRPbmx5KTsg
Y2VydCA9IFFTc2xDZXJ0aWZpY2F0ZShjLnJlYWRBbGwoKSk7CisgICAgICAgIFFGaWxlIGsocUVu
dmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fVEVTVF9LRVkiKSk7IGsub3BlbihRSU9EZXZpY2U6
OlJlYWRPbmx5KTsga2V5ID0gUVNzbEtleShrLnJlYWRBbGwoKSwgUVNzbDo6UnNhKTsKKyAgICAg
ICAgbGlzdGVuKFFIb3N0QWRkcmVzczo6TG9jYWxIb3N0KTsKKyAgICB9CisgICAgdm9pZCBpbmNv
bWluZ0Nvbm5lY3Rpb24ocWludHB0ciBkZXNjcmlwdG9yKSBvdmVycmlkZSB7CisgICAgICAgIGF1
dG8gc29ja2V0ID0gbmV3IFFTc2xTb2NrZXQodGhpcyk7CisgICAgICAgIHNvY2tldC0+c2V0TG9j
YWxDZXJ0aWZpY2F0ZShjZXJ0KTsgc29ja2V0LT5zZXRQcml2YXRlS2V5KGtleSk7IHNvY2tldC0+
c2V0UGVlclZlcmlmeU1vZGUoUVNzbFNvY2tldDo6VmVyaWZ5Tm9uZSk7CisgICAgICAgIHNvY2tl
dC0+c2V0U29ja2V0RGVzY3JpcHRvcihkZXNjcmlwdG9yKTsKKyAgICAgICAgYXV0byBpbnB1dCA9
IHN0ZDo6bWFrZV9zaGFyZWQ8UUJ5dGVBcnJheT4oKTsKKyAgICAgICAgY29ubmVjdChzb2NrZXQs
ICZRU3NsU29ja2V0OjpyZWFkeVJlYWQsIHRoaXMsIFt0aGlzLCBzb2NrZXQsIGlucHV0XSB7Cisg
ICAgICAgICAgICBpbnB1dC0+YXBwZW5kKHNvY2tldC0+cmVhZEFsbCgpKTsKKyAgICAgICAgICAg
IGlmICghaW5wdXQtPmNvbnRhaW5zKCJcclxuXHJcbiIpKSByZXR1cm47CisgICAgICAgICAgICAr
K3JlcXVlc3RzOyBhdXRob3JpemF0aW9uID0gKmlucHV0OworICAgICAgICAgICAgaWYgKHJlc3Bv
bmQpIHsKKyAgICAgICAgICAgICAgICBRQnl0ZUFycmF5IGhlYWRlciA9ICJIVFRQLzEuMSAiICsg
UUJ5dGVBcnJheTo6bnVtYmVyKGNvZGUpICsgIiBGaXh0dXJlXHJcbkNvbnRlbnQtVHlwZTogYXBw
bGljYXRpb24vanNvblxyXG5Db25uZWN0aW9uOiBjbG9zZVxyXG5Db250ZW50LUxlbmd0aDogIiAr
IFFCeXRlQXJyYXk6Om51bWJlcihib2R5LnNpemUoKSkgKyAiXHJcbiI7CisgICAgICAgICAgICAg
ICAgaWYgKGNvZGUgPT0gMzAyKSBoZWFkZXIgKz0gIkxvY2F0aW9uOiBodHRwczovLzEyNy4wLjAu
MjoxMjM0NS9cclxuIjsKKyAgICAgICAgICAgICAgICBzb2NrZXQtPndyaXRlKGhlYWRlciArICJc
clxuIiArIGJvZHkpOyBzb2NrZXQtPmRpc2Nvbm5lY3RGcm9tSG9zdCgpOworICAgICAgICAgICAg
fQorICAgICAgICAgICAgaW5wdXQtPmNsZWFyKCk7CisgICAgICAgIH0pOworICAgICAgICBjb25u
ZWN0KHNvY2tldCwgJlFTc2xTb2NrZXQ6OmRpc2Nvbm5lY3RlZCwgc29ja2V0LCAmUU9iamVjdDo6
ZGVsZXRlTGF0ZXIpOworICAgICAgICBzb2NrZXQtPnN0YXJ0U2VydmVyRW5jcnlwdGlvbigpOwor
ICAgIH0KK307CisKK2NsYXNzIENyaW1zb25UZXN0IDogcHVibGljIFFPYmplY3QgeworICAgIFFf
T0JKRUNUCitwcml2YXRlIHNsb3RzOgorICAgIHZvaWQgc3lzdGVtQ29udHJvbHNQcml2YXRlUGlw
ZSgpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciBkaXI7IFFWRVJJRlkoZGlyLmlzVmFsaWQoKSk7
CisgICAgICAgIFFGaWxlIHNjcmlwdChkaXIuZmlsZVBhdGgoImZpeHR1cmUucHkiKSk7IFFWRVJJ
Rlkoc2NyaXB0Lm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsKKyAgICAgICAgc2NyaXB0Lndy
aXRlKFIiUFkoaW1wb3J0IGpzb24sc3lzCitmb3IgbGluZSBpbiBzeXMuc3RkaW46CisgICAgdmFs
dWU9anNvbi5sb2FkcyhsaW5lKQorICAgIGFjdGlvbj12YWx1ZVsnYWN0aW9uJ10KKyAgICBpZiBh
Y3Rpb249PSd3aWZpLWNvbm5lY3QnOgorICAgICAgICBwcmludChqc29uLmR1bXBzKHsncHJvbXB0
JzonV2ktRmkgcGFzc3dvcmQnfSksZmx1c2g9VHJ1ZSkKKyAgICAgICAgcmVwbHk9anNvbi5sb2Fk
cyhzeXMuc3RkaW4ucmVhZGxpbmUoKSkKKyAgICAgICAgYXNzZXJ0IHJlcGx5PT17J2FjdGlvbic6
J2Fuc3dlcicsJ3ZhbHVlJzonc2VjcmV0LXZhbHVlJ30KKyAgICBwcmludChqc29uLmR1bXBzKHsn
aXRlbXMnOlt7J2lkJzond2xhbjAvQUE6QkI6Q0M6REQ6RUU6RkYnLCduYW1lJzonPGI+UGxhaW4g
U1NJRDwvYj4nLCdkZXRhaWwnOic4MCUgV1BBMicsJ2Nvbm5lY3RlZCc6YWN0aW9uPT0nd2lmaS1j
b25uZWN0J31dLCdzdGF0dXMnOidSZWFkeScsJ2RvbmUnOlRydWV9KSxmbHVzaD1UcnVlKQorKVBZ
Iik7IHNjcmlwdC5jbG9zZSgpOworICAgICAgICBxcHV0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNf
RklYVFVSRSIsIHNjcmlwdC5maWxlTmFtZSgpLnRvVXRmOCgpKTsKKyAgICAgICAgU3lzdGVtQ29u
dHJvbHMgY29udHJvbHM7IGNvbnRyb2xzLm9wZW4oIndpZmkiKTsKKyAgICAgICAgUVRSWV9DT01Q
QVJFKGNvbnRyb2xzLml0ZW1zKCkuc2l6ZSgpLCAxKTsgUVZFUklGWSghY29udHJvbHMuYnVzeSgp
KTsKKyAgICAgICAgY29udHJvbHMucmVxdWVzdCgiYnQtZm9yZ2V0IiwgImludmFsaWQiLCB0cnVl
KTsgUVZFUklGWSghY29udHJvbHMuYnVzeSgpKTsKKyAgICAgICAgY29udHJvbHMucmVxdWVzdCgi
d2lmaS1jb25uZWN0IiwgIndsYW4wL0FBOkJCOkNDOkREOkVFOkZGIik7CisgICAgICAgIFFUUllf
VkVSSUZZKCFjb250cm9scy5wcm9tcHQoKS5pc0VtcHR5KCkpOyBRVkVSSUZZKGNvbnRyb2xzLmJ1
c3koKSk7CisgICAgICAgIGNvbnRyb2xzLmFuc3dlcigic2VjcmV0LXZhbHVlIik7IFFUUllfVkVS
SUZZKCFjb250cm9scy5idXN5KCkpOworICAgICAgICBRVkVSSUZZKGNvbnRyb2xzLnByb21wdCgp
LmlzRW1wdHkoKSk7IFFDT01QQVJFKGNvbnRyb2xzLnN0YXR1cygpLCBRU3RyaW5nKCJSZWFkeSIp
KTsKKyAgICAgICAgUVZFUklGWShjb250cm9scy5pdGVtcygpLmZpcnN0KCkudG9NYXAoKS52YWx1
ZSgiY29ubmVjdGVkIikudG9Cb29sKCkpOworICAgICAgICBjb250cm9scy5jbG9zZSgpOyBRVkVS
SUZZKCFjb250cm9scy5idXN5KCkpOworICAgICAgICBxdW5zZXRlbnYoIk1PT05MSUdIVF9DT05U
Uk9MU19GSVhUVVJFIik7CisgICAgfQorICAgIHZvaWQgbWFuYWdlZFVwZGF0ZXJDYW5ub3RSZXBs
YWNlQ3VzdG9taXplZENsaWVudCgpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciBkaXI7IFFWRVJJ
RlkoZGlyLmlzVmFsaWQoKSk7CisgICAgICAgIGNvbnN0IFFTdHJpbmcgaW1hZ2UgPSBkaXIuZmls
ZVBhdGgoImN1c3RvbS5BcHBJbWFnZSIpOworICAgICAgICBRRmlsZSBmKGltYWdlKTsgUVZFUklG
WShmLm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTsgZi53cml0ZSgiY3VzdG9taXplZCBjbGll
bnQiKTsgZi5jbG9zZSgpOworICAgICAgICBjb25zdCBRQnl0ZUFycmF5IG9sZCA9IHFnZXRlbnYo
IkFQUElNQUdFIik7IGNvbnN0IGJvb2wgaGFkID0gcUVudmlyb25tZW50VmFyaWFibGVJc1NldCgi
QVBQSU1BR0UiKTsKKyAgICAgICAgcXB1dGVudigiQVBQSU1BR0UiLCBpbWFnZS50b1V0ZjgoKSk7
CisgICAgICAgIEF1dG9VcGRhdGVDaGVja2VyIGNoZWNrZXI7CisgICAgICAgIFFWRVJJRlkoY2hl
Y2tlci5vc01hbmFnZWQoKSk7IFFWRVJJRlkoIWNoZWNrZXIuY2FuSW5zdGFsbFVwZGF0ZXMoKSk7
CisgICAgICAgIFFTaWduYWxTcHkgY29tcGxldGVkKCZjaGVja2VyLCAmQXV0b1VwZGF0ZUNoZWNr
ZXI6OmNoZWNrQ29tcGxldGVkKTsKKyAgICAgICAgUVNpZ25hbFNweSBmYWlsZWQoJmNoZWNrZXIs
ICZBdXRvVXBkYXRlQ2hlY2tlcjo6aW5zdGFsbEZhaWxlZCk7CisgICAgICAgIGNoZWNrZXIuc3Rh
cnQoKTsgY2hlY2tlci5jaGVja05vdygpOyBjaGVja2VyLmNoYW5uZWxDaGFuZ2VkKCk7IGNoZWNr
ZXIuaW5zdGFsbCgpOworICAgICAgICBRQ09NUEFSRShjb21wbGV0ZWQuY291bnQoKSwgMyk7IFFD
T01QQVJFKGZhaWxlZC5jb3VudCgpLCAxKTsKKyAgICAgICAgUVZFUklGWSghY2hlY2tlci5jaGVj
a2luZygpKTsgUVZFUklGWSghY2hlY2tlci5pbnN0YWxsaW5nKCkpOworICAgICAgICBRVkVSSUZZ
KCFjaGVja2VyLmNhbkluc3RhbGwoKSk7IFFWRVJJRlkoIWNoZWNrZXIudXBkYXRlQXZhaWxhYmxl
KCkpOyBRVkVSSUZZKCFjaGVja2VyLm9mZmVyQXZhaWxhYmxlKCkpOworICAgICAgICBRQ09NUEFS
RShjaGVja2VyLnJlbGVhc2VVcmwoKSwgUVN0cmluZygiaHR0cHM6Ly9naXRodWIuY29tL3RoM2Qz
Y2szci9Nb29ubGlnaHQtT1MvcmVsZWFzZXMiKSk7CisgICAgICAgIFFWRVJJRlkoY2hlY2tlci5j
dXJyZW50VmVyc2lvbigpLmNvbnRhaW5zKCJNb29ubGlnaHQtT1MgY3VzdG9taXplZCIpKTsKKyAg
ICAgICAgUVZFUklGWShmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkpOyBRQ09NUEFSRShmLnJl
YWRBbGwoKSwgUUJ5dGVBcnJheSgiY3VzdG9taXplZCBjbGllbnQiKSk7IGYuY2xvc2UoKTsKKyAg
ICAgICAgUUNPTVBBUkUoUURpcihkaXIucGF0aCgpKS5lbnRyeUxpc3QoUURpcjo6RmlsZXMpLCBR
U3RyaW5nTGlzdHsiY3VzdG9tLkFwcEltYWdlIn0pOworICAgICAgICBpZiAoaGFkKSBxcHV0ZW52
KCJBUFBJTUFHRSIsIG9sZCk7IGVsc2UgcXVuc2V0ZW52KCJBUFBJTUFHRSIpOworICAgICAgICBR
Q09NUEFSRShBdXRvVXBkYXRlQ2hlY2tlcjo6Y29tcGFyZVNlbWFudGljVmVyc2lvbnMoIjAuNS4w
IiwgIjAuNC45IiksIDEpOworICAgIH0KKyAgICB2b2lkIGVuZHBvaW50VmFsaWRhdGlvbigpIHsK
KyAgICAgICAgUVZFUklGWShDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovLzE5
Mi4xNjguMS4xMDo0Nzk5MCIpKTsKKyAgICAgICAgUVZFUklGWShDcmltc29uU3RhdHVzOjp2YWxp
ZEVuZHBvaW50KCJodHRwczovL1tmZDAwOjoxXTo0Nzk5MC8iKSk7CisgICAgICAgIGZvciAoYXV0
byBiYWQgOiB7Imh0dHA6Ly9ob3N0IiwgImh0dHBzOi8vdXNlcjpzZWNyZXRAaG9zdCIsICJodHRw
czovL2hvc3QvYXBpIiwgImh0dHBzOi8vaG9zdC8/dG9rZW49c2VjcmV0IiwgImZpbGU6Ly8vZXRj
L3Bhc3N3ZCIsICJodHRwczovL2hvc3QvI2ZyYWdtZW50In0pCisgICAgICAgICAgICBRVkVSSUZZ
KCFDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KGJhZCkpOworICAgIH0KKyAgICB2b2lkIG1p
c3NpbmdBbmRJbnZhbGlkTWV0cmljcygpIHsKKyAgICAgICAgUVN0cmluZyBlcnJvcjsKKyAgICAg
ICAgUVZFUklGWShDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKCJub3QganNvbiIsICZlcnJvciku
aXNFbXB0eSgpKTsgUVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsKKyAgICAgICAgYXV0byBzID0g
Q3JpbXNvblN0YXR1czo6cGFyc2VTdGF0cyhSIih7ImNwdV9wZXJjZW50Ijo0Mi41LCJjcHVfdGVt
cF9jIjotMSwiZ3B1X3BlcmNlbnQiOm51bGwsInJhbV90b3RhbF9ieXRlcyI6MCwicmFtX3BlcmNl
bnQiOjAsInZyYW1fdG90YWxfYnl0ZXMiOjEwMCwidnJhbV91c2VkX2J5dGVzIjoxMjB9KSIsICZl
cnJvcik7CisgICAgICAgIFFWRVJJRlkoZXJyb3IuaXNFbXB0eSgpKTsgUUNPTVBBUkUocy52YWx1
ZSgiY3B1X3BlcmNlbnQiKS50b0RvdWJsZSgpLCA0Mi41KTsKKyAgICAgICAgUVZFUklGWSghcy5j
b250YWlucygiY3B1X3RlbXBfYyIpKTsgUVZFUklGWSghcy5jb250YWlucygiZ3B1X3BlcmNlbnQi
KSk7IFFWRVJJRlkoIXMuY29udGFpbnMoInJhbV9wZXJjZW50IikpOworICAgICAgICBRQ09NUEFS
RShzLnZhbHVlKCJ2cmFtX3BlcmNlbnQiKS50b0RvdWJsZSgpLCAxMDAuMCk7CisgICAgICAgIGF1
dG8gaW52YWxpZCA9IENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJjcHVfcGVyY2VudCI6
MTAxLCJncHVfcGVyY2VudCI6IjAifSkiLCAmZXJyb3IpOworICAgICAgICBRVkVSSUZZKGludmFs
aWQuaXNFbXB0eSgpKTsgUVZFUklGWShlcnJvci5pc0VtcHR5KCkpOworICAgICAgICBDcmltc29u
U3RhdHVzOjpwYXJzZVN0YXRzKFFCeXRlQXJyYXkoNjU1MzcsICdhJyksICZlcnJvcik7IFFWRVJJ
RlkoIWVycm9yLmlzRW1wdHkoKSk7CisgICAgICAgIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMo
UiIoeyJlcnJvciI6InVuc3VwcG9ydGVkIn0pIiwgJmVycm9yKTsgUVZFUklGWSghZXJyb3IuaXNF
bXB0eSgpKTsKKyAgICB9CisgICAgdm9pZCBsb2NhbEhhcmR3YXJlRml4dHVyZSgpIHsKKyAgICAg
ICAgUVRlbXBvcmFyeURpciB0ZW1wOyBRVkVSSUZZKHRlbXAuaXNWYWxpZCgpKTsKKyAgICAgICAg
YXV0byB3cml0ZSA9IFsmXShRU3RyaW5nIHAsIFFCeXRlQXJyYXkgdmFsdWUpIHsgUURpcigpLm1r
cGF0aChRRmlsZUluZm8odGVtcC5wYXRoKCkrcCkuYWJzb2x1dGVQYXRoKCkpOyBRRmlsZSBmKHRl
bXAucGF0aCgpK3ApOyBRVkVSSUZZKGYub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOyBmLndy
aXRlKHZhbHVlKTsgfTsKKyAgICAgICAgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC90
eXBlIiwgIkJhdHRlcnkiKTsgd3JpdGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9jYXBhY2l0
eSIsICI3MyIpOyB3cml0ZSgiL2NsYXNzL3Bvd2VyX3N1cHBseS9CQVQwL3N0YXR1cyIsICJDaGFy
Z2luZyIpOworICAgICAgICB3cml0ZSgiL2NsYXNzL25ldC93bGFuMC9vcGVyc3RhdGUiLCAidXAi
KTsgd3JpdGUoIi9jbGFzcy9uZXQvbG8vb3BlcnN0YXRlIiwgInVwIik7CisgICAgICAgIGF1dG8g
bG9jYWwgPSBDcmltc29uU3RhdHVzOjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpOyBRQ09NUEFSRShs
b2NhbC52YWx1ZSgiYmF0dGVyeVBlcmNlbnQiKS50b0ludCgpLCA3Myk7IFFDT01QQVJFKGxvY2Fs
LnZhbHVlKCJiYXR0ZXJ5U3RhdGUiKS50b1N0cmluZygpLCBRU3RyaW5nKCJDaGFyZ2luZyIpKTsK
KyAgICAgICAgUUNPTVBBUkUobG9jYWwudmFsdWUoIm5ldHdvcmsiKS50b1N0cmluZygpLCBRU3Ry
aW5nKCJ3bGFuMCIpKTsgUVZFUklGWShsb2NhbC52YWx1ZSgiY29ubmVjdGVkIikudG9Cb29sKCkp
OworICAgICAgICB3cml0ZSgiL2NsYXNzL3Bvd2VyX3N1cHBseS9CQVQwL2NhcGFjaXR5IiwgIjEw
MSIpOyBRQ09NUEFSRShDcmltc29uU3RhdHVzOjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpLnZhbHVl
KCJiYXR0ZXJ5UGVyY2VudCIpLnRvSW50KCksIC0xKTsKKyAgICB9CisgICAgdm9pZCBwcml2YXRl
U2V0dGluZ3NBbmROb0Nyb3NzSG9zdENyZWRlbnRpYWxzKCkgeworICAgICAgICBRU3RhbmRhcmRQ
YXRoczo6c2V0VGVzdE1vZGVFbmFibGVkKHRydWUpOworICAgICAgICBDcmltc29uU3RhdHVzIHN0
YXR1czsgc3RhdHVzLnNlbGVjdEhvc3QoInRlc3QtYSIsICJodHRwczovLzEyNy4wLjAuMTo0Nzk5
MCIpOworICAgICAgICBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4x
OjQ3OTkwIiwgImZpeHR1cmUtdG9rZW4iLCAiIikpOyBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmVk
KCkpOworICAgICAgICBhdXRvIHBhdGggPSBRU3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlv
bihRU3RhbmRhcmRQYXRoczo6QXBwQ29uZmlnTG9jYXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpz
b24iOworICAgICAgICBRVkVSSUZZKChRRmlsZTo6cGVybWlzc2lvbnMocGF0aCkgJiAoUUZpbGVE
ZXZpY2U6OlJlYWRHcm91cCB8IFFGaWxlRGV2aWNlOjpSZWFkT3RoZXIgfCBRRmlsZURldmljZTo6
V3JpdGVHcm91cCB8IFFGaWxlRGV2aWNlOjpXcml0ZU90aGVyKSkgPT0gMCk7CisgICAgICAgIHN0
YXR1cy5zZWxlY3RIb3N0KCJ0ZXN0LWIiLCAiaHR0cHM6Ly8xMjcuMC4wLjI6NDc5OTAiKTsgUVZF
UklGWSghc3RhdHVzLmNvbmZpZ3VyZWQoKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25m
aWd1cmUoImh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIiwgIiIsICIiKSk7CisgICAgICAgIFFWRVJJ
RlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIiwgImZpeHR1cmUt
dG9rZW4iLCAiaW52YWxpZC1waW4iKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1
cmUoImh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkwIiwgInRva2VuXG5pbmplY3Rpb24iLCAiIikpOwor
ICAgICAgICBRRmlsZTo6cmVtb3ZlKHBhdGgpOworICAgIH0KKyAgICB2b2lkIHRsc0F1dGhlbnRp
Y2F0aW9uQW5kVmlzaWJpbGl0eSgpIHsKKyAgICAgICAgVGxzRml4dHVyZSBzZXJ2ZXI7IFFWRVJJ
Rlkoc2VydmVyLmlzTGlzdGVuaW5nKCkpOyBRVkVSSUZZKCFzZXJ2ZXIuY2VydC5pc051bGwoKSk7
CisgICAgICAgIFFTdHJpbmcgdXJsID0gImh0dHBzOi8vMTI3LjAuMC4xOiIgKyBRU3RyaW5nOjpu
dW1iZXIoc2VydmVyLnNlcnZlclBvcnQoKSk7CisgICAgICAgIFFTdHJpbmcgcGluID0gUVN0cmlu
Zzo6ZnJvbUxhdGluMShzZXJ2ZXIuY2VydC5kaWdlc3QoUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEy
NTYpLnRvSGV4KCkpOworICAgICAgICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVj
dEhvc3QoImZpeHR1cmUtdGxzIiwgdXJsKTsKKyAgICAgICAgUVZFUklGWShzdGF0dXMuY29uZmln
dXJlKHVybCwgImZpeHR1cmUtb25seS10b2tlbiIsICIiKSk7IHN0YXR1cy5zZXRWaXNpYmxlKHRy
dWUpOworICAgICAgICBRVFJZX1ZFUklGWV9XSVRIX1RJTUVPVVQoc3RhdHVzLnN0YXR1cygpLmNv
bnRhaW5zKCJmaW5nZXJwcmludCIpLCA1MDAwKTsKKyAgICAgICAgUUNPTVBBUkUoc2VydmVyLnJl
cXVlc3RzLCAwKTsgLy8gbm8gY3JlZGVudGlhbHMgc2VudCBiZWZvcmUgdHJ1c3Rpbmcgc2VsZi1z
aWduZWQgVExTCisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJmaXh0dXJl
LW9ubHktdG9rZW4iLCBwaW4pKTsKKyAgICAgICAgUVRSWV9DT01QQVJFX1dJVEhfVElNRU9VVChz
dGF0dXMuc3RhdHMoKS52YWx1ZSgiY3B1X3BlcmNlbnQiKS50b0RvdWJsZSgpLCAzNy41LCA1MDAw
KTsKKyAgICAgICAgUVZFUklGWShzZXJ2ZXIuYXV0aG9yaXphdGlvbi5jb250YWlucygiQXV0aG9y
aXphdGlvbjogQmVhcmVyIGZpeHR1cmUtb25seS10b2tlbiIpKTsKKyAgICAgICAgUVZFUklGWShz
ZXJ2ZXIuYXV0aG9yaXphdGlvbi5zdGFydHNXaXRoKCJHRVQgL2FwaS9ob3N0L3N0YXRzICIpKTsK
KyAgICAgICAgc3RhdHVzLnNldFZpc2libGUoZmFsc2UpOyBpbnQgY291bnQgPSBzZXJ2ZXIucmVx
dWVzdHM7IFFUZXN0OjpxV2FpdCgyMTAwKTsgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCBjb3Vu
dCk7CisgICAgICAgIGZvciAoaW50IGNvZGUgOiB7NDAxLCA0MDMsIDQwNCwgMzAyfSkgeworICAg
ICAgICAgICAgc2VydmVyLmNvZGUgPSBjb2RlOyBpbnQgcHJpb3IgPSBzZXJ2ZXIucmVxdWVzdHM7
IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9U
SU1FT1VUKHNlcnZlci5yZXF1ZXN0cyA+IHByaW9yLCA1MDAwKTsKKyAgICAgICAgICAgIFFUUllf
VkVSSUZZX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOworICAg
ICAgICAgICAgc3RhdHVzLnNldFZpc2libGUoZmFsc2UpOworICAgICAgICB9CisgICAgICAgIHNl
cnZlci5jb2RlID0gMjAwOyBzZXJ2ZXIuYm9keSA9IFFCeXRlQXJyYXkoNzAwMDAsICdhJyk7IGlu
dCBwcmlvciA9IHNlcnZlci5yZXF1ZXN0czsgc3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAg
ICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9VVChzZXJ2ZXIucmVxdWVzdHMgPiBwcmlvciwgNTAw
MCk7CisgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0Vt
cHR5KCksIDUwMDApOyBzdGF0dXMuc2V0VmlzaWJsZShmYWxzZSk7CisgICAgICAgIFFWRVJJRlko
c3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJmaXh0dXJlLW9ubHktdG9rZW4iLCBRU3RyaW5nKDY0LCAn
MCcpKSk7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAgICBjb3VudCA9IHNlcnZlci5y
ZXF1ZXN0czsgUVRlc3Q6OnFXYWl0KDUwMCk7IFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywgY291
bnQpOyBRVkVSSUZZKHN0YXR1cy5zdGF0cygpLmlzRW1wdHkoKSk7CisgICAgICAgIHN0YXR1cy5z
ZXRWaXNpYmxlKGZhbHNlKTsKKyAgICB9CisgICAgdm9pZCBxbWxQYWxldHRlQW5kUGFuZWxzKCkg
eworICAgICAgICBRU3RyaW5nIHNvdXJjZSA9IHFFbnZpcm9ubWVudFZhcmlhYmxlKCJWSUJFTUlT
X1RFU1RfU09VUkNFIik7IFFWRVJJRlkoIXNvdXJjZS5pc0VtcHR5KCkpOworICAgICAgICBRUXVp
Y2tTdHlsZTo6c2V0U3R5bGUoIk1hdGVyaWFsIik7CisgICAgICAgIHFtbFJlZ2lzdGVyU2luZ2xl
dG9uVHlwZShRVXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSArICIvYXBwL21vb25saWdodG9zL3Rl
c3RzL1ByZWZlcmVuY2VzLnFtbCIpLCAiU3RyZWFtaW5nUHJlZmVyZW5jZXMiLCAxLCAwLCAiU3Ry
ZWFtaW5nUHJlZmVyZW5jZXMiKTsKKyAgICAgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlKFFV
cmw6OmZyb21Mb2NhbEZpbGUoc291cmNlICsgIi9hcHAvZ3VpL1ZiVG9rZW5zLnFtbCIpLCAiVmli
ZW1pcy5SZWRlc2lnbiIsIDEsIDAsICJWYlRva2VucyIpOworICAgICAgICBRUW1sRW5naW5lIGVu
Z2luZTsKKyAgICAgICAgUVFtbENvbXBvbmVudCBjb21wb25lbnQoJmVuZ2luZSwgUVVybDo6ZnJv
bUxvY2FsRmlsZShzb3VyY2UgKyAiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbCIp
KTsKKyAgICAgICAgUVNjb3BlZFBvaW50ZXI8UU9iamVjdD4gcm9vdChjb21wb25lbnQuY3JlYXRl
KCkpOyBRVkVSSUZZMihyb290LCBxUHJpbnRhYmxlKGNvbXBvbmVudC5lcnJvclN0cmluZygpKSk7
CisgICAgICAgIGF1dG8gcGFuZWwgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJ0ZXN0UGFu
ZWwiKTsgUVZFUklGWShwYW5lbCk7CisgICAgICAgIGF1dG8gc3RhdGUgPSByb290LT5maW5kQ2hp
bGQ8UU9iamVjdCo+KCJ0ZXN0U3RhdGUiKTsgUVZFUklGWShzdGF0ZSk7CisgICAgICAgIGZvciAo
aW50IGkgPSAwOyBpIDwgMTY7ICsraSkgeworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVj
dDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCAiY2hvb3NlQWNjZW50IiwgUV9BUkcoUVZhcmlh
bnQsIGkpKSk7CisgICAgICAgICAgICBRVkVSSUZZKHN0YXRlLT5wcm9wZXJ0eSgiYWNjZW50Iiku
dmFsdWU8UUNvbG9yPigpLmlzVmFsaWQoKSk7CisgICAgICAgICAgICBRVkVSSUZZKHN0YXRlLT5w
cm9wZXJ0eSgicHJlc3NlZCIpLnZhbHVlPFFDb2xvcj4oKS5pc1ZhbGlkKCkpOworICAgICAgICB9
CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwg
ImNob29zZUFjY2VudCIsIFFfQVJHKFFWYXJpYW50LCA0KSkpOworICAgICAgICBmb3IgKFFTdHJp
bmcga2luZCA6IHsibmV0d29yayIsICJiYXR0ZXJ5IiwgImhvc3QifSkgeworICAgICAgICAgICAg
UVZFUklGWShwYW5lbC0+c2V0UHJvcGVydHkoImtpbmQiLCBraW5kKSk7CisgICAgICAgICAgICBR
VkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QocGFuZWwsICJvcGVuIikpOyBRVGVzdDo6
cVdhaXQoMzAwKTsKKyAgICAgICAgICAgIFFWRVJJRlkocGFuZWwtPnByb3BlcnR5KCJ2aXNpYmxl
IikudG9Cb29sKCkpOworICAgICAgICAgICAgUVN0cmluZyBvdXQgPSBxRW52aXJvbm1lbnRWYXJp
YWJsZSgiQ1JJTVNPTl9TQ1JFRU5TSE9UUyIpOworICAgICAgICAgICAgaWYgKCFvdXQuaXNFbXB0
eSgpKSB7CisgICAgICAgICAgICAgICAgUURpcigpLm1rcGF0aChvdXQpOworICAgICAgICAgICAg
ICAgIGF1dG8gd2luZG93ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgp
KTsgUVZFUklGWSh3aW5kb3cpOworICAgICAgICAgICAgICAgIFFWRVJJRlkod2luZG93LT5ncmFi
V2luZG93KCkuc2F2ZShvdXQgKyAiLyIgKyBraW5kICsgIi5wbmciKSk7CisgICAgICAgICAgICB9
CisgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QocGFuZWwsICJj
bG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgIH0KKyAgICAgICAgYXV0byBjb25u
ZWN0aW9ucyA9IHJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oImNvbm5lY3Rpb25zUGFuZWwiKTsg
UVZFUklGWShjb25uZWN0aW9ucyk7CisgICAgICAgIGZvciAoUVN0cmluZyBraW5kIDogeyJ3aWZp
IiwgImJ0In0pIHsKKyAgICAgICAgICAgIHJvb3QtPnNldFByb3BlcnR5KCJ3aWR0aCIsIDEwMjQp
OyByb290LT5zZXRQcm9wZXJ0eSgiaGVpZ2h0IiwgNjQwKTsKKyAgICAgICAgICAgIFFWRVJJRlko
Y29ubmVjdGlvbnMtPnNldFByb3BlcnR5KCJraW5kIiwga2luZCkpOworICAgICAgICAgICAgUVZF
UklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGNvbm5lY3Rpb25zLCAib3BlbiIpKTsgUVRl
c3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICBRVkVSSUZZKGNvbm5lY3Rpb25zLT5wcm9wZXJ0
eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsKKyAgICAgICAgICAgIFFWRVJJRlkoY29ubmVjdGlvbnMt
PnByb3BlcnR5KCJ3aWR0aCIpLnRvSW50KCkgPD0gOTkyKTsKKyAgICAgICAgICAgIFFTdHJpbmcg
b3V0ID0gcUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fU0NSRUVOU0hPVFMiKTsKKyAgICAg
ICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgeworICAgICAgICAgICAgICAgIGF1dG8gd2luZG93
ID0gcW9iamVjdF9jYXN0PFFRdWlja1dpbmRvdyo+KHJvb3QuZGF0YSgpKTsgUVZFUklGWSh3aW5k
b3cpOworICAgICAgICAgICAgICAgIFFWRVJJRlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShv
dXQgKyAiLyIgKyBraW5kICsgIi1zZWxlY3Rvci5wbmciKSk7CisgICAgICAgICAgICB9CisgICAg
ICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY29ubmVjdGlvbnMsICJj
bG9zZSIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgIH0KKyAgICB9Cit9OworUVRFU1Rf
TUFJTihDcmltc29uVGVzdCkKKyNpbmNsdWRlICJ0ZXN0LWNyaW1zb24ubW9jIgpkaWZmIC0tZ2l0
IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5wcm8gYi9hcHAvbW9vbmxpZ2h0
b3MvdGVzdHMvdGVzdC1jcmltc29uLnBybwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAw
MDAwMC4uZTQzNzAwOTYKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMv
dGVzdC1jcmltc29uLnBybwpAQCAtMCwwICsxLDEyIEBACitRVCArPSBjb3JlIGd1aSBxdWljayBu
ZXR3b3JrIHF1aWNrY29udHJvbHMyIHRlc3RsaWIKK0NPTkZJRyArPSBjKysxNyB0ZXN0Y2FzZQor
VEFSR0VUID0gdGVzdC1jcmltc29uCitTT1VSQ0VTICs9IHRlc3QtY3JpbXNvbi5jcHAgLi4vY3Jp
bXNvbnN0YXR1cy5jcHAKK0hFQURFUlMgKz0gLi4vY3JpbXNvbnN0YXR1cy5oCisKK1NPVVJDRVMg
Kz0gLi4vbWFuYWdlZHVwZGF0ZXMuY3BwCitIRUFERVJTICs9IC4uLy4uL2JhY2tlbmQvYXV0b3Vw
ZGF0ZWNoZWNrZXIuaAorCitERUZJTkVTICs9IE1PT05MSUdIVF9DT05UUk9MU19URVNUCitTT1VS
Q0VTICs9IC4uL3N5c3RlbWNvbnRyb2xzLmNwcAorSEVBREVSUyArPSAuLi9zeXN0ZW1jb250cm9s
cy5oCmRpZmYgLS1naXQgYS9hcHAvcW1sLnFyYyBiL2FwcC9xbWwucXJjCmluZGV4IGEzYzExZGQ3
Li45NGIyMTE3NiAxMDA2NDQKLS0tIGEvYXBwL3FtbC5xcmMKKysrIGIvYXBwL3FtbC5xcmMKQEAg
LTE0LDYgKzE0LDggQEAKICAgICAgICAgPGZpbGU+Z3VpL1ZiSG9zdENhcmQucW1sPC9maWxlPgog
ICAgICAgICA8ZmlsZT5ndWkvVmJXZWxjb21lU2hlZXQucW1sPC9maWxlPgogICAgICAgICA8Zmls
ZT5ndWkvbWFpbi5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uU3RhdHVzRGlh
bG9nLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL1N5c3RlbUNvbm5lY3Rpb25zRGlhbG9n
LnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL1BjVmlldy5xbWw8L2ZpbGU+CiAgICAgICAg
IDxmaWxlPmd1aS9BcHBWaWV3LnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL1NldHRpbmdz
Vmlldy5xbWw8L2ZpbGU+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1zb24tYmF0dGVyeS5zdmcg
Yi9hcHAvcmVzL2NyaW1zb24tYmF0dGVyeS5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXgg
MDAwMDAwMDAuLjM3NTM1NjZhCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9jcmltc29uLWJh
dHRlcnkuc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIw
MDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCI+PGcgZmls
bD0ibm9uZSIgc3Ryb2tlPSIjRUNFRUYxIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVj
YXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cmVjdCB4PSIyIiB5PSI2IiB3aWR0
aD0iMTgiIGhlaWdodD0iMTIiIHJ4PSIyIi8+PHBhdGggZD0iTTIyIDEwdjRNNiAxMHY0TTEwIDEw
djRNMTQgMTB2NCIvPjwvZz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1ibHVl
dG9vdGguc3ZnIGIvYXBwL3Jlcy9jcmltc29uLWJsdWV0b290aC5zdmcKbmV3IGZpbGUgbW9kZSAx
MDA2NDQKaW5kZXggMDAwMDAwMDAuLmNlZjlhYjg2Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jl
cy9jcmltc29uLWJsdWV0b290aC5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDov
L3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAw
IDI0IDI0Ij48cGF0aCBkPSJNNyA3bDEwIDEwLTUgNFYzbDUgNEw3IDE3IiBmaWxsPSJub25lIiBz
dHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBz
dHJva2UtbGluZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1z
b24taG9zdC5zdmcgYi9hcHAvcmVzL2NyaW1zb24taG9zdC5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2
NDQKaW5kZXggMDAwMDAwMDAuLmQxZDU5YjBjCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9j
cmltc29uLWhvc3Quc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMu
b3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCI+
PGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRUNFRUYxIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tl
LWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cmVjdCB4PSIzIiB5PSIz
IiB3aWR0aD0iMTgiIGhlaWdodD0iMTQiIHJ4PSIyIi8+PHBhdGggZD0iTTggMjFoOE0xMiAxN3Y0
TTYgMTBoM2wyLTQgMyA4IDItNGgyIi8+PC9nPjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9j
cmltc29uLW5ldHdvcmsuc3ZnIGIvYXBwL3Jlcy9jcmltc29uLW5ldHdvcmsuc3ZnCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwLi5iMmExMDNhNgotLS0gL2Rldi9udWxsCisrKyBi
L2FwcC9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJo
dHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94
PSIwIDAgMjQgMjQiPjxnIGZpbGw9Im5vbmUiIHN0cm9rZT0iI0VDRUVGMSIgc3Ryb2tlLXdpZHRo
PSIxLjgiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBh
dGggZD0iTTMgOGExNCAxNCAwIDAgMSAxOCAwTTYgMTJhOSA5IDAgMCAxIDEyIDBNOSAxNmE0IDQg
MCAwIDEgNiAwIi8+PGNpcmNsZSBjeD0iMTIiIGN5PSIyMCIgcj0iMSIvPjwvZz48L3N2Zz4KZGlm
ZiAtLWdpdCBhL2FwcC9yZXNvdXJjZXMucXJjIGIvYXBwL3Jlc291cmNlcy5xcmMKaW5kZXggYjVk
NGVlNzkuLjhkNzY4OTZkIDEwMDY0NAotLS0gYS9hcHAvcmVzb3VyY2VzLnFyYworKysgYi9hcHAv
cmVzb3VyY2VzLnFyYwpAQCAtMSw1ICsxLDkgQEAKIDxSQ0M+CiAgICAgPHFyZXNvdXJjZSBwcmVm
aXg9Ii8iPgorICAgICAgICA8ZmlsZT5yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZzwvZmlsZT4KKyAg
ICAgICAgPGZpbGU+cmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZzwvZmlsZT4KKyAgICAgICAgPGZp
bGU+cmVzL2NyaW1zb24tYmF0dGVyeS5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9jcmlt
c29uLWhvc3Quc3ZnPC9maWxlPgogICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVt
aXNfcC5wbmciPnJlcy9zdGVhbS92aWJlbWlzX3AucG5nPC9maWxlPgogICAgICAgICA8ZmlsZSBh
bGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXMucG5nIj5yZXMvc3RlYW0vdmliZW1pcy5wbmc8L2ZpbGU+
CiAgICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19oZXJvLnBuZyI+cmVzL3N0
ZWFtL3ZpYmVtaXNfaGVyby5wbmc8L2ZpbGU+CmRpZmYgLS1naXQgYS9hcHAvc2V0dGluZ3Mvc3Ry
ZWFtaW5ncHJlZmVyZW5jZXMuY3BwIGIvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZlcmVuY2Vz
LmNwcAppbmRleCBkNjlhOTEzMS4uNjAyMmIyNTMgMTAwNjQ0Ci0tLSBhL2FwcC9zZXR0aW5ncy9z
dHJlYW1pbmdwcmVmZXJlbmNlcy5jcHAKKysrIGIvYXBwL3NldHRpbmdzL3N0cmVhbWluZ3ByZWZl
cmVuY2VzLmNwcApAQCAtMjI5LDcgKzIyOSw3IEBAIHZvaWQgU3RyZWFtaW5nUHJlZmVyZW5jZXM6
OnJlbG9hZCgpCiAgICAgc2VlbldlbGNvbWVIaW50ID0gc2V0dGluZ3MudmFsdWUoU0VSX1NFRU5X
RUxDT01FSElOVCwgZmFsc2UpLnRvQm9vbCgpOwogICAgIGVuYWJsZUhkciA9IHNldHRpbmdzLnZh
bHVlKFNFUl9IRFIsIGZhbHNlKS50b0Jvb2woKTsKICAgICB1aVNob3dIaW50cyA9IHNldHRpbmdz
LnZhbHVlKFNFUl9VSV9TSE9XSElOVFMsIHRydWUpLnRvQm9vbCgpOwotICAgIHVpQWNjZW50SW5k
ZXggPSBxQm91bmQoMCwgc2V0dGluZ3MudmFsdWUoU0VSX1VJX0FDQ0VOVElOREVYLCAwKS50b0lu
dCgpLCAzKTsKKyAgICB1aUFjY2VudEluZGV4ID0gcUJvdW5kKDAsIHNldHRpbmdzLnZhbHVlKFNF
Ul9VSV9BQ0NFTlRJTkRFWCwgNCkudG9JbnQoKSwgMTUpOwogICAgIHVpU291bmRzID0gc2V0dGlu
Z3MudmFsdWUoU0VSX1VJU09VTkRTLCB0cnVlKS50b0Jvb2woKTsKICAgICBkaXNwbGF5SGRyQ2Fw
YWJpbGl0eSA9IHNldHRpbmdzLnZhbHVlKFNFUl9ESVNQTEFZX0hEUl9DQVBBQklMSVRZLCB0cnVl
KS50b0Jvb2woKTsKICAgICBoZHJUb25lbWFwcGluZyA9IHNldHRpbmdzLnZhbHVlKFNFUl9IRFJf
VE9ORU1BUCwgZmFsc2UpLnRvQm9vbCgpOwo=
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
printf '  1) Vibemis\n  2) Artemis\n  3) Pegasus launcher\n  4) Moonlight\n  5) CocoOS\n'
printf 'Enter keeps %s; auto-start in 8 seconds.\nChoose: ' "$CLIENT"
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
