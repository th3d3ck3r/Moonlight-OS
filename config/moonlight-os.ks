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
# Saved profile changes never intentionally take down the working connection.
set -u
export LC_ALL=C
active_uuid() {
  nmcli -t --escape no -f UUID,TYPE connection show --active 2>/dev/null |
    awk -F: '$2=="802-11-wireless" {print $1; exit}'
}
profile_name() {
  nmcli -g connection.id connection show uuid "$1" 2>/dev/null | tr -d '\000-\037\177'
}
select_profile() {
  local active selected index
  active=$(active_uuid)
  if [[ -n $active ]]; then
    SELECTED_UUID=$active
  else
    mapfile -t profiles < <(nmcli -t --escape no -f UUID,TYPE connection show 2>/dev/null |
      awk -F: '$2=="802-11-wireless" {print $1}')
    if (( ${#profiles[@]} == 0 )); then
      echo 'No saved Wi-Fi profile. Use Connect / change Wi-Fi first.'
      return 1
    fi
    echo 'No active Wi-Fi. Choose a saved profile:'
    for index in "${!profiles[@]}"; do
      printf '  %d) %s\n' "$((index+1))" "$(profile_name "${profiles[index]}")"
    done
    read -r -p 'Profile number (Enter cancels): ' selected || return 1
    [[ $selected =~ ^[0-9]{1,3}$ ]] || return 1
    index=$((10#$selected-1))
    (( index >= 0 && index < ${#profiles[@]} )) || return 1
    SELECTED_UUID=${profiles[index]}
  fi
  [[ $SELECTED_UUID =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}
set_band() {
  local band=$1 description=$2
  select_profile || return 1
  if sudo -n nmcli --wait 10 connection modify uuid "$SELECTED_UUID" \
      802-11-wireless.band "$band" 802-11-wireless.bssid ''; then
    printf '%s saved for %s.\n' "$description" "$(profile_name "$SELECTED_UUID")"
    echo 'The current connection was left running. Applies on the next reconnect.'
    echo 'Use option 5 to reconnect now; it will ask for credentials if needed.'
  else
    echo 'Could not save the preference. No disconnect was requested.'
    return 1
  fi
}
main() {
  local active choice reply
  while true; do
    clear
    printf '\033[40m\033[31m'
    active=$(active_uuid)
    printf 'WI-FI\n=====\n\nActive: %s\n' "${active:+$(profile_name "$active")}"
    cat <<'MENU'

  1) Connect / change Wi-Fi
  2) 5 GHz ONLY (no 2.4 GHz fallback; optional)
  3) Automatic band / AP selection (recommended for combined 2.4/5 GHz)
  4) Show Wi-Fi status
  5) Reconnect saved Wi-Fi (asks for missing credentials)
  0) Back
MENU
    read -r -p 'Choose: ' choice || return 0
    case "$choice" in
      1) nmtui-connect ;;
      2)
        read -r -p 'Restrict this profile to 5 GHz on its next reconnect? Type yes: ' reply
        [[ $reply == yes ]] && set_band a '5 GHz only'
        read -r -p 'Press Enter...' _ ;;
      3) set_band '' 'Automatic band / AP selection'; read -r -p 'Press Enter...' _ ;;
      4) nmcli device wifi list; echo; iw dev 2>/dev/null || true; read -r -p 'Press Enter...' _ ;;
      5)
        if select_profile; then
          echo 'Reconnecting may briefly interrupt the network. Credentials are not put in command arguments.'
          if sudo -n nmcli --ask --wait 40 connection up uuid "$SELECTED_UUID"; then
            echo 'Wi-Fi connection activated.'
          else
            echo 'Reconnect failed or was cancelled. Use option 3 for automatic band selection, then option 1 to connect.'
          fi
        fi
        read -r -p 'Press Enter...' _ ;;
      0) return 0 ;;
    esac
  done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main; fi
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
        if len(row) not in (6, 7):
            continue
        active, name, address, strength, security, device = row[:6]
        frequency = row[6] if len(row) == 7 else ''
        band = ''
        if frequency.isdecimal():
            mhz = int(frequency)
            band = '2.4 GHz' if 2400 <= mhz < 2500 else '5 GHz' if 4900 <= mhz < 5900 else '6 GHz' if 5900 <= mhz < 7126 else ''
        if not re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', address):
            continue
        if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.:-]{0,31}', device):
            continue
        identity = device + '/' + address.upper()
        if identity in seen or not name:
            continue
        seen.add(identity)
        result.append(dict(id=identity, name=name, address=address.upper(), device=device,
                           detail=f'{strength}% · {security or "Open"}' + (' · ' + band if band else ''), connected=active == '*'))
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
                                   'IN-USE,SSID,BSSID,SIGNAL,SECURITY,DEVICE,FREQ', 'device', 'wifi', 'list',
                                   '--rescan', 'yes' if scan else 'no']))
        return self.items

    def selected(self, value):
        return next((item for item in self.items if item['id'] == value), None)

    def wifi_connect(self, item):
        env = dict(os.environ, LC_ALL='C', LANG='C')
        self.wifi_child = pexpect.spawn('/usr/bin/sudo', ['-n', '/usr/bin/nmcli', '--ask', '--wait', '40', 'device', 'wifi', 'connect',
                                       item['address'], 'ifname', item['device']], env=env,
                                       encoding='utf-8', codec_errors='replace', echo=False, timeout=40)
        child = self.wifi_child
        try:
            prompts = 0
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                event = child.expect([r'(?i)password[^\r\n]*:', r'successfully activated', r'(?i)error:[^\r\n]*', pexpect.EOF, pexpect.TIMEOUT], timeout=min(40, max(1, deadline-time.monotonic())))
                if event == 0:
                    prompts += 1
                    if prompts > 3:
                        raise RuntimeError('Wi-Fi authentication failed. Recheck the saved network/password in tty2.')
                    child.sendline(answer('Wi-Fi password for ' + item['name']))
                elif event == 1:
                    child.expect(pexpect.EOF, timeout=5)
                    child.close()
                    if child.exitstatus != 0:
                        raise RuntimeError('Wi-Fi activation did not complete successfully.')
                    return
                elif event == 2:
                    raise RuntimeError('Wi-Fi activation failed. Check the saved band setting, password and adapter in tty2; no network was deliberately disconnected first.')
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
        # introspect=False means dbus-python cannot infer Properties.Set's ssv.
        # Explicitly wrap the Boolean in a variant, otherwise it sends ssb.
        props = self.interface(self.adapter, 'org.freedesktop.DBus.Properties')
        try:
            for key in ('Powered', 'Pairable'):
                props.Set('org.bluez.Adapter1', key, self.dbus.Boolean(True, variant_level=1), timeout=5)
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
                self.interface(adapter, 'org.bluez.Adapter1').RemoveDevice(self.dbus.ObjectPath(path), timeout=5)
            else:
                if action == 'connect':
                    self.interface(path, 'org.freedesktop.DBus.Properties').Set('org.bluez.Device1', 'Trusted', self.dbus.Boolean(True, variant_level=1), timeout=5)
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
  a) Audio mixer (save on exit)
  u) EclipseOS updates (enrollment required)
  s) Streaming tuning / renderer diagnostics

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
    a) moonlight-audio ;;
    s) eclipseos-streaming menu; read -r -p "Press Enter..." _ ;;
    u) eclipseos-updates; read -r -p "Press Enter..." _ ;;
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
VIBEMIS_PATCH_SHA256=3996a95cb132b302c74007585abf090f171f41841a81b1a8067009814ac5d238
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
M2Y2NDVkLi4xMzQ2YzdmIDEwMDY0NAotLS0gYS9hcHAvZ3VpL0FwcFZpZXcucW1sCisrKyBiL2Fw
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
aGUgZ2FtZXBhZCBlcXVpdmFsZW50IG9mIHRoZSBzdG9wIGJ1dHRvbiBvbiB0aGUKQEAgLTk4LDYg
KzEwOSw3IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgIC8vIEZpeGVkIGhlYWRlciAoZG9lcyBu
b3Qgc2Nyb2xsIHdpdGggdGhlIGdyaWQpLiBPcGFxdWUgYmcgc28gc2Nyb2xsZWQgdGlsZXMgcGFz
cyBiZWhpbmQgaXQuCiAgICAgSXRlbSB7CiAgICAgICAgIGlkOiBhcHBDaHJvbWVIZWFkZXIKKyAg
ICAgICAgb2JqZWN0TmFtZTogImNyaW1zb25HcmlkSGVhZGVyIgogICAgICAgICB6OiAxMAogICAg
ICAgICBhbmNob3JzLnRvcDogcGFyZW50LnRvcAogICAgICAgICBhbmNob3JzLmxlZnQ6IHBhcmVu
dC5sZWZ0CkBAIC0xMjEsMTMgKzEzMywxMyBAQCBDZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAg
Um93IHsKICAgICAgICAgICAgIGlkOiBhcHBzVGl0bGVSb3cKICAgICAgICAgICAgIGFuY2hvcnMu
dG9wOiBwYXJlbnQudG9wCi0gICAgICAgICAgICBhbmNob3JzLnRvcE1hcmdpbjogMzQKKyAgICAg
ICAgICAgIGFuY2hvcnMudG9wTWFyZ2luOiAxNgogICAgICAgICAgICAgYW5jaG9ycy5sZWZ0OiBw
YXJlbnQubGVmdAotICAgICAgICAgICAgYW5jaG9ycy5sZWZ0TWFyZ2luOiBWYlRva2Vucy5zY3Jl
ZW5QYWRYCisgICAgICAgICAgICBhbmNob3JzLmxlZnRNYXJnaW46IFZiVG9rZW5zLnNjcmVlblBh
ZFgrYXBwR3JpZC5yYWlsU3BhY2UrYXBwR3JpZC5ob3N0U3BhY2UKICAgICAgICAgICAgIHNwYWNp
bmc6IDE0CiAgICAgICAgICAgICBUZXh0IHsKICAgICAgICAgICAgICAgICBpZDogYXBwc1RpdGxl
Ci0gICAgICAgICAgICAgICAgdGV4dDogcXNUcigiQXBwcyIpCisgICAgICAgICAgICAgICAgdGV4
dDogcXNUcigiTGlicmFyeSIpCiAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5z
LmZvbnREaXNwbGF5CiAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZvbnQuQm9sZAogICAg
ICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy5zaXplU2NyZWVuVGl0bGUKQEAg
LTE0Myw2ICsxNTUsMzEgQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAgICAgIH0KICAgICB9CiAK
KworICAgIC8vIENyaW1zb24gR2xhc3MgZGFzaGJvYXJkIGNocm9tZSBsaXZlcyBpbiB0aGUgdmll
d3BvcnQsIG91dHNpZGUgY29udGVudEl0ZW0uCisgICAgQ3JpbXNvbkdsYXNzUmFpbCB7CisgICAg
ICAgIHBhcmVudDphcHBHcmlkCisgICAgICAgIHo6MTE7eDoxMjt5OjE2O3dpZHRoOjY0O2hlaWdo
dDpNYXRoLm1heCgyODAsYXBwR3JpZC5oZWlnaHQtMzItKGFwcEhpbnRCYXIudmlzaWJsZT9hcHBI
aW50QmFyLmhlaWdodDowKSkKKyAgICAgICAgdmlzaWJsZTphcHBHcmlkLnJhaWxTcGFjZT4wO2lu
TGlicmFyeTp0cnVlCisgICAgICAgIG9uSG9tZVJlcXVlc3RlZDogeyBpZihzdGFja1ZpZXcuZGVw
dGg+MSkgc3RhY2tWaWV3LnBvcChudWxsKTtlbHNlIGFwcEdyaWQuZm9yY2VBY3RpdmVGb2N1cygp
IH0KKyAgICAgICAgb25TZXR0aW5nc1JlcXVlc3RlZDogc2V0dGluZ3NCdXR0b24uY2xpY2tlZCgp
CisgICAgICAgIG9uQ29udHJvbHNSZXF1ZXN0ZWQ6IGVjbGlwc2VDZW50ZXJCdXR0b24uY2xpY2tl
ZCgpCisgICAgfQorICAgIENyaW1zb25Mb2NhbFBhbmVsIHsKKyAgICAgICAgcGFyZW50OmFwcEdy
aWQKKyAgICAgICAgejoxMTthbmNob3JzLnJpZ2h0OnBhcmVudC5yaWdodDthbmNob3JzLnJpZ2h0
TWFyZ2luOjE2O3k6MTY7d2lkdGg6TWF0aC5tYXgoMCxhcHBHcmlkLmxvY2FsU3BhY2UtMjgpCisg
ICAgICAgIGhlaWdodDpNYXRoLm1heCgyNDAsYXBwR3JpZC5oZWlnaHQtMzItKGFwcEhpbnRCYXIu
dmlzaWJsZT9hcHBIaW50QmFyLmhlaWdodDowKSk7dmlzaWJsZTphcHBHcmlkLmxvY2FsU3BhY2U+
MAorICAgICAgICBhY3RpdmU6dmlzaWJsZSAmJiBhcHBHcmlkLlN0YWNrVmlldy5zdGF0dXM9PT1T
dGFja1ZpZXcuQWN0aXZlCisgICAgICAgIG9uQ29udHJvbHNSZXF1ZXN0ZWQ6IGVjbGlwc2VDZW50
ZXJCdXR0b24uY2xpY2tlZCgpCisgICAgfQorICAgIENyaW1zb25Ib3N0UGFuZWwgeworICAgICAg
ICBwYXJlbnQ6YXBwR3JpZAorICAgICAgICB6OjExO3g6YXBwR3JpZC5yYWlsU3BhY2UrMTI7eTox
Njt3aWR0aDpNYXRoLm1heCgwLGFwcEdyaWQuaG9zdFNwYWNlLTI0KQorICAgICAgICBoZWlnaHQ6
TWF0aC5tYXgoMjQwLGFwcEdyaWQuaGVpZ2h0LTMyLShhcHBIaW50QmFyLnZpc2libGU/YXBwSGlu
dEJhci5oZWlnaHQ6MCkpO3Zpc2libGU6YXBwR3JpZC5ob3N0U3BhY2U+MAorICAgICAgICBob3N0
TmFtZTphcHBHcmlkLm9iamVjdE5hbWU7aG9zdFR5cGU6YXBwR3JpZC5ob3N0VHlwZTt0cmFuc3Bv
cnQ6YXBwR3JpZC5ob3N0VHJhbnNwb3J0O29ubGluZTphcHBHcmlkLmhvc3RPbmxpbmU7aG9zdDph
cHBHcmlkLmNyaW1zb25Ib3N0CisgICAgICAgIG9uSG9zdFJlcXVlc3RlZDogeyBDcmltc29uU3Rh
dHVzLnNlbGVjdEhvc3QoYXBwR3JpZC5jcmltc29uSG9zdC5pZHx8IiIsYXBwR3JpZC5jcmltc29u
SG9zdC51cmx8fCIiKTtjcmltc29uUGFuZWwua2luZD0iaG9zdCI7Y3JpbXNvblBhbmVsLm9wZW4o
KSB9CisgICAgfQorCiAgICAgLy8gUGVyc2lzdGVudCBnYW1lcGFkIGhpbnQgYmFyLCBmaXhlZCBh
dCB0aGUgYm90dG9tLiBHcmlkIGJvdHRvbU1hcmdpbiBjbGVhcnMgaXQuCiAgICAgVmJIaW50QmFy
IHsKICAgICAgICAgaWQ6IGFwcEhpbnRCYXIKQEAgLTIyNiw3ICsyNjMsOCBAQCBDZW50ZXJlZEdy
aWRWaWV3IHsKIAogICAgIGZ1bmN0aW9uIGNyZWF0ZU1vZGVsKCkKICAgICB7Ci0gICAgICAgIHZh
ciBtb2RlbCA9IFF0LmNyZWF0ZVFtbE9iamVjdCgnaW1wb3J0IEFwcE1vZGVsIDEuMDsgQXBwTW9k
ZWwge30nLCBwYXJlbnQsICcnKQorICAgICAgICB2YXIgbW9kZWwgPSBRdC5jcmVhdGVRbWxPYmpl
Y3QoJ2ltcG9ydCBDcmltc29uU3RhdHVzIDEuMAoraW1wb3J0IEFwcE1vZGVsIDEuMDsgQXBwTW9k
ZWwge30nLCBhcHBHcmlkLCAnJykKICAgICAgICAgbW9kZWwuaW5pdGlhbGl6ZShDb21wdXRlck1h
bmFnZXIsIGNvbXB1dGVySW5kZXgsIHNob3dIaWRkZW5HYW1lcykKICAgICAgICAgcmV0dXJuIG1v
ZGVsCiAgICAgfQpAQCAtMjY1LDMwICszMDMsMTggQEAgQ2VudGVyZWRHcmlkVmlldyB7CiAgICAg
ICAgICAgICBmb2N1c2VkOiBhcHBEZWxlZ2F0ZS5oaWdobGlnaHRlZAogCiAgICAgICAgICAgICBJ
bWFnZSB7Ci0gICAgICAgICAgICAgICAgcHJvcGVydHkgYm9vbCBpc1BsYWNlaG9sZGVyOiBmYWxz
ZQorICAgICAgICAgICAgICAgIHJlYWRvbmx5IHByb3BlcnR5IGJvb2wgaXNQbGFjZWhvbGRlcjog
c291cmNlLnRvU3RyaW5nKCkubGVuZ3RoID09PSAwIHx8IHN0YXR1cyA9PT0gSW1hZ2UuRXJyb3Ig
fHwKKyAgICAgICAgICAgICAgICAgICAgKCFtb2RlbC5pc0FwcENvbGxlY3RvckdhbWUgJiYKKyAg
ICAgICAgICAgICAgICAgICAgICgoc291cmNlU2l6ZS53aWR0aCA9PT0gMTMwICYmIHNvdXJjZVNp
emUuaGVpZ2h0ID09PSAxODApIHx8CisgICAgICAgICAgICAgICAgICAgICAgKHNvdXJjZVNpemUu
d2lkdGggPT09IDYyOCAmJiBzb3VyY2VTaXplLmhlaWdodCA9PT0gODg4KSB8fAorICAgICAgICAg
ICAgICAgICAgICAgIChzb3VyY2VTaXplLndpZHRoID09PSAyMDAgJiYgc291cmNlU2l6ZS5oZWln
aHQgPT09IDI2NikpKQogCiAgICAgICAgICAgICAgICAgaWQ6IGFwcEljb24KICAgICAgICAgICAg
ICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAogICAgICAgICAgICAgICAgIGFuY2hvcnMubWFyZ2lu
czogNQogICAgICAgICAgICAgICAgIHNvdXJjZTogbW9kZWwuYm94YXJ0Ci0KLSAgICAgICAgICAg
ICAgICBvblNvdXJjZVNpemVDaGFuZ2VkOiB7Ci0gICAgICAgICAgICAgICAgICAgIC8vIE5lYXJs
eSBhbGwgb2YgTnZpZGlhJ3Mgb2ZmaWNpYWwgYm94IGFydCBkb2VzIG5vdCBtYXRjaCB0aGUgZGlt
ZW5zaW9ucyBvZiBwbGFjZWhvbGRlcgotICAgICAgICAgICAgICAgICAgICAvLyBpbWFnZXMsIGhv
d2V2ZXIgdGhlIG9uZSBrbm93biBleGNlcHRpb24gaXMgT3ZlcmNvb2tlZC4gVGhlcmVmb3JlLCB3
ZSBvbmx5IGV4ZWN1dGUKLSAgICAgICAgICAgICAgICAgICAgLy8gdGhlIGltYWdlIHNpemUgY2hl
Y2tzIGlmIHRoaXMgaXMgbm90IGFuIGFwcCBjb2xsZWN0b3IgZ2FtZS4gV2Uga25vdyB0aGUgb2Zm
aWNpYWxseQotICAgICAgICAgICAgICAgICAgICAvLyBzdXBwb3J0ZWQgZ2FtZXMgYWxsIGhhdmUg
Ym94IGFydCwgc28gdGhpcyBjaGVjayBpcyBub3QgcmVxdWlyZWQuCi0gICAgICAgICAgICAgICAg
ICAgIGlmICghbW9kZWwuaXNBcHBDb2xsZWN0b3JHYW1lICYmCi0gICAgICAgICAgICAgICAgICAg
ICAgICAoKHNvdXJjZVNpemUud2lkdGggPT09IDEzMCAmJiBzb3VyY2VTaXplLmhlaWdodCA9PT0g
MTgwKSB8fCAvLyBHRkUgMi4wIHBsYWNlaG9sZGVyIGltYWdlCi0gICAgICAgICAgICAgICAgICAg
ICAgICAgKHNvdXJjZVNpemUud2lkdGggPT09IDYyOCAmJiBzb3VyY2VTaXplLmhlaWdodCA9PT0g
ODg4KSB8fCAvLyBHRkUgMy4wIHBsYWNlaG9sZGVyIGltYWdlCi0gICAgICAgICAgICAgICAgICAg
ICAgICAgKHNvdXJjZVNpemUud2lkdGggPT09IDIwMCAmJiBzb3VyY2VTaXplLmhlaWdodCA9PT0g
MjY2KSkpICAvLyBPdXIgbm9fYXBwX2ltYWdlLnBuZwotICAgICAgICAgICAgICAgICAgICB7Ci0g
ICAgICAgICAgICAgICAgICAgICAgICBpc1BsYWNlaG9sZGVyID0gdHJ1ZQotICAgICAgICAgICAg
ICAgICAgICB9Ci0gICAgICAgICAgICAgICAgICAgIGVsc2UKLSAgICAgICAgICAgICAgICAgICAg
ewotICAgICAgICAgICAgICAgICAgICAgICAgaXNQbGFjZWhvbGRlciA9IGZhbHNlCi0gICAgICAg
ICAgICAgICAgICAgIH0KLSAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgdmlzaWJs
ZTogIWlzUGxhY2Vob2xkZXIKKyAgICAgICAgICAgICAgICBmaWxsTW9kZTogSW1hZ2UuUHJlc2Vy
dmVBc3BlY3RDcm9wCiAKICAgICAgICAgICAgICAgICAvLyBEaXNwbGF5IGEgdG9vbHRpcCB3aXRo
IHRoZSBmdWxsIG5hbWUgaWYgaXQncyB0cnVuY2F0ZWQKICAgICAgICAgICAgICAgICBUb29sVGlw
LnRleHQ6IG1vZGVsLm5hbWUKQEAgLTI5Nyw2ICszMjMsMTUgQEAgQ2VudGVyZWRHcmlkVmlldyB7
CiAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiAoYXBwRGVsZWdhdGUuaG92ZXJlZCB8
fCBhcHBEZWxlZ2F0ZS5oaWdobGlnaHRlZCkgJiYgKCFhcHBOYW1lVGV4dCB8fCBhcHBOYW1lVGV4
dC50cnVuY2F0ZWQpCiAgICAgICAgICAgICB9CiAKKyAgICAgICAgICAgIEltYWdlIHsKKyAgICAg
ICAgICAgICAgICB2aXNpYmxlOiBhcHBJY29uLmlzUGxhY2Vob2xkZXIgJiYgIW1vZGVsLnJ1bm5p
bmcKKyAgICAgICAgICAgICAgICBhbmNob3JzLmhvcml6b250YWxDZW50ZXI6IHBhcmVudC5ob3Jp
em9udGFsQ2VudGVyCisgICAgICAgICAgICAgICAgeTogcGFyZW50LmhlaWdodCAqIDAuMjIKKyAg
ICAgICAgICAgICAgICB3aWR0aDogTWF0aC5taW4oNjQsIHBhcmVudC53aWR0aCAqIDAuMyk7IGhl
aWdodDogd2lkdGgKKyAgICAgICAgICAgICAgICBzb3VyY2U6ICJxcmM6L3Jlcy9lY2xpcHNlLWlj
b24uc3ZnIgorICAgICAgICAgICAgICAgIG9wYWNpdHk6IDAuODUKKyAgICAgICAgICAgIH0KKwog
ICAgICAgICAgICAgTG9hZGVyIHsKICAgICAgICAgICAgICAgICBhY3RpdmU6IG1vZGVsLnJ1bm5p
bmcKICAgICAgICAgICAgICAgICBhc3luY2hyb25vdXM6IHRydWUKQEAgLTM2NSw3ICs0MDAsNyBA
QCBDZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAgICAgICAgICAvLyBpbiB0aGUgdGltZSBpbiB3
aGljaCB0aGUgdGV4dCBsb2FkcyBmb3IgZWFjaCBnYW1lLgogCiAgICAgICAgICAgICAgICAgd2lk
dGg6IGFwcEljb24ud2lkdGgKLSAgICAgICAgICAgICAgICBoZWlnaHQ6IG1vZGVsLnJ1bm5pbmcg
PyAxNzUgOiBhcHBJY29uLmhlaWdodAorICAgICAgICAgICAgICAgIGhlaWdodDogbW9kZWwucnVu
bmluZyA/IE1hdGgubWluKDE0MCwgYXBwSWNvbi5oZWlnaHQgKiAwLjQ1KSA6IGFwcEljb24uaGVp
Z2h0ICogMC41NQogCiAgICAgICAgICAgICAgICAgYW5jaG9ycy5sZWZ0OiBhcHBJY29uLmxlZnQK
ICAgICAgICAgICAgICAgICBhbmNob3JzLnJpZ2h0OiBhcHBJY29uLnJpZ2h0CkBAIC0zNzQsNyAr
NDA5LDEwIEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgICAgICAgICAgICAgIHNvdXJjZUNvbXBv
bmVudDogTGFiZWwgewogICAgICAgICAgICAgICAgICAgICBpZDogYXBwTmFtZVRleHQKICAgICAg
ICAgICAgICAgICAgICAgdGV4dDogbW9kZWwubmFtZQotICAgICAgICAgICAgICAgICAgICBmb250
LnBvaW50U2l6ZTogMjIKKyAgICAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5z
LmZvbnREaXNwbGF5CisgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vu
cy50eXBlSGVhZGluZworICAgICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMudGV4dAor
ICAgICAgICAgICAgICAgICAgICB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dAogICAgICAgICAg
ICAgICAgICAgICBsZWZ0UGFkZGluZzogMjAKICAgICAgICAgICAgICAgICAgICAgcmlnaHRQYWRk
aW5nOiAyMAogICAgICAgICAgICAgICAgICAgICB2ZXJ0aWNhbEFsaWdubWVudDogVGV4dC5BbGln
blZDZW50ZXIKZGlmZiAtLWdpdCBhL2FwcC9ndWkvQXV0b1Jlc2l6aW5nQ29tYm9Cb3gucW1sIGIv
YXBwL2d1aS9BdXRvUmVzaXppbmdDb21ib0JveC5xbWwKaW5kZXggNTNhZmNhZi4uZjEyMzkzMiAx
MDA2NDQKLS0tIGEvYXBwL2d1aS9BdXRvUmVzaXppbmdDb21ib0JveC5xbWwKKysrIGIvYXBwL2d1
aS9BdXRvUmVzaXppbmdDb21ib0JveC5xbWwKQEAgLTEsNSArMSw2IEBACiBpbXBvcnQgUXRRdWlj
ayAyLjkKIGltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNp
Z24gMS4wCiAKIGltcG9ydCBTZGxHYW1lcGFkS2V5TmF2aWdhdGlvbiAxLjAKIGltcG9ydCBTeXN0
ZW1Qcm9wZXJ0aWVzIDEuMApAQCAtOTIsNyArOTMsNyBAQCBDb21ib0JveCB7CiAgICAgICAgIC8v
IE92ZXJyaWRlIHRoZSBwb3B1cCBjb2xvciB0byBpbXByb3ZlIGNvbnRyYXN0IHdpdGggdGhlIG92
ZXJyaWRkZW4KICAgICAgICAgLy8gTWF0ZXJpYWwgMiBiYWNrZ3JvdW5kIGNvbG9yIHNldCBpbiBt
YWluLnFtbC4KICAgICAgICAgaWYgKFN5c3RlbVByb3BlcnRpZXMudXNlc01hdGVyaWFsM1RoZW1l
KSB7Ci0gICAgICAgICAgICBwb3B1cC5iYWNrZ3JvdW5kLmNvbG9yID0gIiM0MjQyNDIiCisgICAg
ICAgICAgICBwb3B1cC5iYWNrZ3JvdW5kLmNvbG9yID0gUXQuYmluZGluZyhmdW5jdGlvbigpIHsg
cmV0dXJuIFZiVG9rZW5zLmJnRWxldjIgfSkKICAgICAgICAgfQogICAgIH0KIApkaWZmIC0tZ2l0
IGEvYXBwL2d1aS9Dcmltc29uQmFja2dyb3VuZFBpY2tlci5xbWwgYi9hcHAvZ3VpL0NyaW1zb25C
YWNrZ3JvdW5kUGlja2VyLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5h
ZTE1ZTA4Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9Dcmltc29uQmFja2dyb3VuZFBpY2tl
ci5xbWwKQEAgLTAsMCArMSwzMCBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWlj
ay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkxheW91dHMgMS4zCitpbXBvcnQgVmliZW1p
cy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBFY2xpcHNlUHJvZmlsZXMgMS4wCitOYXZpZ2FibGVEaWFs
b2cgeworICAgIGlkOnBpY2tlcgorICAgIHRpdGxlOnFzVHIoIkNyaW1zb24gR2xhc3MgYmFja2dy
b3VuZCIpCisgICAgd2lkdGg6TWF0aC5taW4oNjQwLHBhcmVudD9wYXJlbnQud2lkdGgtMzI6NjQw
KTtoZWlnaHQ6TWF0aC5taW4oNjAwLHBhcmVudD9wYXJlbnQuaGVpZ2h0LTMyOjYwMCkKKyAgICBz
dGFuZGFyZEJ1dHRvbnM6RGlhbG9nLkNsb3NlCisgICAgcHJvcGVydHkgdXJsIGZvbGRlcjpFY2xp
cHNlUHJvZmlsZXMuYmFja2dyb3VuZEZvbGRlcigpCisgICAgcHJvcGVydHkgdmFyIGZpbGVzOltd
CisgICAgcHJvcGVydHkgc3RyaW5nIGVycm9yOiIiCisgICAgb25PcGVuZWQ6IHtmaWxlcz1FY2xp
cHNlUHJvZmlsZXMuYmFja2dyb3VuZEZpbGVzKGZvbGRlcik7ZXJyb3I9IiJ9CisgICAgY29udGVu
dEl0ZW06Q29sdW1uTGF5b3V0IHsKKyAgICAgICAgc3BhY2luZzoxMgorICAgICAgICBMYWJlbCB7
IHRleHQ6cXNUcigiU2VsZWN0IGFuIGltYWdlLiBBIHJlc2l6ZWQgY29weSBpcyBzYXZlZCBzbyBy
ZW1vdmFibGUgbWVkaWEgY2FuIGJlIGRpc2Nvbm5lY3RlZC4iKTtMYXlvdXQuZmlsbFdpZHRoOnRy
dWU7d3JhcE1vZGU6VGV4dC5XcmFwO2NvbG9yOlZiVG9rZW5zLnRleHREaW07Zm9udC5waXhlbFNp
emU6VmJUb2tlbnMudHlwZUxhYmVsIH0KKyAgICAgICAgVGV4dEZpZWxkIHsgaWQ6cGF0aDtMYXlv
dXQuZmlsbFdpZHRoOnRydWU7dGV4dDpwaWNrZXIuZm9sZGVyLnRvU3RyaW5nKCk7cGxhY2Vob2xk
ZXJUZXh0OnFzVHIoIkZvbGRlciBwYXRoIG9yIGZpbGU6Ly8vIFVSTCIpO3NlbGVjdEJ5TW91c2U6
dHJ1ZTtjb2xvcjpWYlRva2Vucy50ZXh0O2ZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVMYWJl
bAorICAgICAgICAgICAgYmFja2dyb3VuZDpDcmltc29uR2xhc3NQYW5lbCB7cmFkaXVzOlZiVG9r
ZW5zLnJhZGl1c0NvbnRyb2x9CisgICAgICAgICAgICBvbkFjY2VwdGVkOntwaWNrZXIuZm9sZGVy
PXRleHQuaW5kZXhPZigiZmlsZToiKT09PTA/dGV4dDoiZmlsZTovLyIrdGV4dDtwaWNrZXIuZmls
ZXM9RWNsaXBzZVByb2ZpbGVzLmJhY2tncm91bmRGaWxlcyhwaWNrZXIuZm9sZGVyKX0KKyAgICAg
ICAgfQorICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHt0ZXh0OnFzVHIoIk9wZW4gZm9sZGVy
Iik7b25DbGlja2VkOntwaWNrZXIuZm9sZGVyPXBhdGgudGV4dC5pbmRleE9mKCJmaWxlOiIpPT09
MD9wYXRoLnRleHQ6ImZpbGU6Ly8iK3BhdGgudGV4dDtwaWNrZXIuZmlsZXM9RWNsaXBzZVByb2Zp
bGVzLmJhY2tncm91bmRGaWxlcyhwaWNrZXIuZm9sZGVyKX19CisgICAgICAgIExpc3RWaWV3IHsg
aWQ6bGlzdDtMYXlvdXQuZmlsbFdpZHRoOnRydWU7TGF5b3V0LmZpbGxIZWlnaHQ6dHJ1ZTtjbGlw
OnRydWU7bW9kZWw6cGlja2VyLmZpbGVzO3NwYWNpbmc6NjtrZXlOYXZpZ2F0aW9uRW5hYmxlZDp0
cnVlO2FjdGl2ZUZvY3VzT25UYWI6dHJ1ZQorICAgICAgICAgICAgZGVsZWdhdGU6RWNsaXBzZUFj
dGlvbkJ1dHRvbiB7d2lkdGg6bGlzdC53aWR0aDt0ZXh0Oihtb2RlbERhdGEuZGlyZWN0b3J5PyLi
lrggIjoiIikrbW9kZWxEYXRhLm5hbWUKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6e2lmKG1v
ZGVsRGF0YS5kaXJlY3Rvcnkpe3BpY2tlci5mb2xkZXI9bW9kZWxEYXRhLnVybDtwYXRoLnRleHQ9
cGlja2VyLmZvbGRlci50b1N0cmluZygpO3BpY2tlci5maWxlcz1FY2xpcHNlUHJvZmlsZXMuYmFj
a2dyb3VuZEZpbGVzKHBpY2tlci5mb2xkZXIpfWVsc2UgaWYoRWNsaXBzZVByb2ZpbGVzLmNob29z
ZUJhY2tncm91bmQobW9kZWxEYXRhLnVybCkpcGlja2VyLmNsb3NlKCk7ZWxzZSBwaWNrZXIuZXJy
b3I9cXNUcigiVW5hYmxlIHRvIHJlYWQgdGhpcyBpbWFnZS4gQ2hvb3NlIFBORywgSlBFRywgV2Vi
UCBvciBCTVAgdXAgdG8gMzIgTWlCLiIpfQorICAgICAgICAgICAgfQorICAgICAgICB9CisgICAg
ICAgIExhYmVsIHt0ZXh0OnBpY2tlci5lcnJvcjt2aXNpYmxlOnRleHQubGVuZ3RoPjA7Y29sb3I6
VmJUb2tlbnMuc3RhdHVzRGFuZ2VyO0xheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0
LldyYXA7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUxhYmVsfQorICAgIH0KK30KZGlmZiAt
LWdpdCBhL2FwcC9ndWkvQ3JpbXNvbkdsYXNzQmFja2Ryb3AucW1sIGIvYXBwL2d1aS9Dcmltc29u
R2xhc3NCYWNrZHJvcC5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uNmRj
M2ZmZgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvQ3JpbXNvbkdsYXNzQmFja2Ryb3AucW1s
CkBAIC0wLDAgKzEsMjEgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFZpYmVtaXMuUmVk
ZXNpZ24gMS4wCitpbXBvcnQgRWNsaXBzZVByb2ZpbGVzIDEuMAorUmVjdGFuZ2xlIHsKKyAgICBj
b2xvcjogVmJUb2tlbnMuYmdXaW5kb3cKKyAgICBjbGlwOiB0cnVlCisgICAgSW1hZ2UgeworICAg
ICAgICBpZDogd2FsbHBhcGVyO29iamVjdE5hbWU6ImNyaW1zb25XYWxscGFwZXIiO2FuY2hvcnMu
ZmlsbDpwYXJlbnQ7c291cmNlOkVjbGlwc2VQcm9maWxlcy5iYWNrZ3JvdW5kO2ZpbGxNb2RlOklt
YWdlLlByZXNlcnZlQXNwZWN0Q3JvcAorICAgICAgICBhc3luY2hyb25vdXM6dHJ1ZTtjYWNoZTpm
YWxzZTtzb3VyY2VTaXplLndpZHRoOjI1NjA7c291cmNlU2l6ZS5oZWlnaHQ6MjU2MAorICAgICAg
ICBDb25uZWN0aW9ucyB7IHRhcmdldDpFY2xpcHNlUHJvZmlsZXM7ZnVuY3Rpb24gb25CYWNrZ3Jv
dW5kQ2hhbmdlZCgpe3ZhciB1cmw9RWNsaXBzZVByb2ZpbGVzLmJhY2tncm91bmQ7d2FsbHBhcGVy
LnNvdXJjZT0iIjt3YWxscGFwZXIuc291cmNlPXVybH0gfQorICAgIH0KKyAgICBSZWN0YW5nbGUg
eyBhbmNob3JzLmZpbGw6cGFyZW50O2NvbG9yOlZiVG9rZW5zLmJnV2luZG93O29wYWNpdHk6TWF0
aC5tYXgoRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdD8wLjg6MCxFY2xpcHNlUHJvZmlsZXMu
YmFja2dyb3VuZERpbS8xMDApIH0KKyAgICBSZWN0YW5nbGUgeworICAgICAgICB3aWR0aDogTWF0
aC5taW4ocGFyZW50LndpZHRoKjAuNzIsODUwKTsgaGVpZ2h0OiB3aWR0aDsgcmFkaXVzOiB3aWR0
aC8yCisgICAgICAgIHg6IHBhcmVudC53aWR0aC13aWR0aCowLjYyOyB5OiAtaGVpZ2h0KjAuNTUK
KyAgICAgICAgY29sb3I6IFF0LnJnYmEoVmJUb2tlbnMuYWNjZW50LnIsVmJUb2tlbnMuYWNjZW50
LmcsVmJUb2tlbnMuYWNjZW50LmIsMC4wMzUpCisgICAgICAgIGJvcmRlci5jb2xvcjogUXQucmdi
YShWYlRva2Vucy5hY2NlbnQucixWYlRva2Vucy5hY2NlbnQuZyxWYlRva2Vucy5hY2NlbnQuYiww
LjE1KTsgYm9yZGVyLndpZHRoOiAyCisgICAgfQorICAgIFJlY3RhbmdsZSB7IGFuY2hvcnMuZmls
bDpwYXJlbnQ7IGdyYWRpZW50OkdyYWRpZW50IHsgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246MDtj
b2xvcjoiIzAwMDAwMDAwIiB9CisgICAgICAgIEdyYWRpZW50U3RvcCB7IHBvc2l0aW9uOjE7Y29s
b3I6VmJUb2tlbnMuYmdXaW5kb3cgfSB9IH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvQ3JpbXNv
bkdsYXNzUGFuZWwucW1sIGIvYXBwL2d1aS9Dcmltc29uR2xhc3NQYW5lbC5xbWwKbmV3IGZpbGUg
bW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uZTliMzMzYwotLS0gL2Rldi9udWxsCisrKyBiL2Fw
cC9ndWkvQ3JpbXNvbkdsYXNzUGFuZWwucW1sCkBAIC0wLDAgKzEsMTMgQEAKK2ltcG9ydCBRdFF1
aWNrIDIuOQoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitSZWN0YW5nbGUgeworICAgIGlk
OmdsYXNzCisgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDYXJkCisgICAgY29sb3I6IFZiVG9r
ZW5zLmJnRWxldgorICAgIGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlCisgICAgZ3JhZGll
bnQ6IEdyYWRpZW50IHsKKyAgICAgICAgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246IDA7IGNvbG9y
OiBRdC5yZ2JhKFF0LmxpZ2h0ZXIoZ2xhc3MuY29sb3IsMS4zNSkucixRdC5saWdodGVyKGdsYXNz
LmNvbG9yLDEuMzUpLmcsUXQubGlnaHRlcihnbGFzcy5jb2xvciwxLjM1KS5iLFZiVG9rZW5zLmds
YXNzT3BhY2l0eSkgfQorICAgICAgICBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjogMTsgY29sb3I6
IFF0LnJnYmEoZ2xhc3MuY29sb3IucixnbGFzcy5jb2xvci5nLGdsYXNzLmNvbG9yLmIsVmJUb2tl
bnMuZ2xhc3NPcGFjaXR5KSB9CisgICAgfQorICAgIFJlY3RhbmdsZSB7IGFuY2hvcnMudG9wOiBw
YXJlbnQudG9wOyBhbmNob3JzLnRvcE1hcmdpbjogMTsgYW5jaG9ycy5ob3Jpem9udGFsQ2VudGVy
OiBwYXJlbnQuaG9yaXpvbnRhbENlbnRlcjsgd2lkdGg6IE1hdGgubWF4KDAscGFyZW50LndpZHRo
LTIqcGFyZW50LnJhZGl1cyk7IGhlaWdodDogMTsgY29sb3I6IFZiVG9rZW5zLmdsYXNzRWRnZSB9
Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0NyaW1zb25HbGFzc1JhaWwucW1sIGIvYXBwL2d1aS9D
cmltc29uR2xhc3NSYWlsLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi5l
MWE0YzViCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9Dcmltc29uR2xhc3NSYWlsLnFtbApA
QCAtMCwwICsxLDIzIEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRy
b2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBWaWJlbWlzLlJlZGVz
aWduIDEuMAorQ3JpbXNvbkdsYXNzUGFuZWwgeworICAgIGlkOnJhaWwKKyAgICBwcm9wZXJ0eSBi
b29sIGluTGlicmFyeTpmYWxzZQorICAgIHNpZ25hbCBob21lUmVxdWVzdGVkKCkKKyAgICBzaWdu
YWwgc2V0dGluZ3NSZXF1ZXN0ZWQoKQorICAgIHNpZ25hbCBjb250cm9sc1JlcXVlc3RlZCgpCisg
ICAgQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgYW5jaG9ycy50b3A6cGFyZW50LnRvcDthbmNob3Jz
LmxlZnQ6cGFyZW50LmxlZnQ7YW5jaG9ycy5yaWdodDpwYXJlbnQucmlnaHQ7YW5jaG9ycy50b3BN
YXJnaW46MTA7YW5jaG9ycy5sZWZ0TWFyZ2luOjQ7YW5jaG9ycy5yaWdodE1hcmdpbjo0O3NwYWNp
bmc6MTIKKyAgICAgICAgSW1hZ2UgeyBzb3VyY2U6InFyYzovcmVzL2VjbGlwc2UtaWNvbi5zdmci
O0xheW91dC5hbGlnbm1lbnQ6UXQuQWxpZ25IQ2VudGVyO0xheW91dC5wcmVmZXJyZWRXaWR0aDoz
ODtMYXlvdXQucHJlZmVycmVkSGVpZ2h0OjM4IH0KKyAgICAgICAgUmVwZWF0ZXIgeworICAgICAg
ICAgICAgbW9kZWw6W3tsYWJlbDpxc1RyKCJIb21lIiksaWNvbjoicXJjOi9yZXMvY3JpbXNvbi1o
b3N0LnN2ZyIsYWN0aW9uOiJob21lIn0se2xhYmVsOnFzVHIoIkNvbnRyb2xzIiksaWNvbjoicXJj
Oi9yZXMvZWNsaXBzZS1jb250cm9scy5zdmciLGFjdGlvbjoiY29udHJvbHMifSx7bGFiZWw6cXNU
cigiU2V0dGluZ3MiKSxpY29uOiJxcmM6L3Jlcy9zZXR0aW5ncy5zdmciLGFjdGlvbjoic2V0dGlu
Z3MifV0KKyAgICAgICAgICAgIGRlbGVnYXRlOiBFY2xpcHNlQWN0aW9uQnV0dG9uIHsKKyAgICAg
ICAgICAgICAgICBvYmplY3ROYW1lOiJjcmltc29uUmFpbEJ1dHRvbiI7TGF5b3V0LmZpbGxXaWR0
aDp0cnVlO2ltcGxpY2l0V2lkdGg6NTY7aW1wbGljaXRIZWlnaHQ6NTY7dGV4dDoiIjtpY29uU291
cmNlOm1vZGVsRGF0YS5pY29uCisgICAgICAgICAgICAgICAgQWNjZXNzaWJsZS5uYW1lOm1vZGVs
RGF0YS5sYWJlbDtUb29sVGlwLnRleHQ6bW9kZWxEYXRhLmxhYmVsO1Rvb2xUaXAudmlzaWJsZTpo
b3ZlcmVkfHxhY3RpdmVGb2N1cworICAgICAgICAgICAgICAgIG9uQ2xpY2tlZDoge2lmKG1vZGVs
RGF0YS5hY3Rpb249PT0iaG9tZSIpcmFpbC5ob21lUmVxdWVzdGVkKCk7ZWxzZSBpZihtb2RlbERh
dGEuYWN0aW9uPT09ImNvbnRyb2xzIilyYWlsLmNvbnRyb2xzUmVxdWVzdGVkKCk7ZWxzZSByYWls
LnNldHRpbmdzUmVxdWVzdGVkKCl9CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9Cit9
CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0NyaW1zb25Ib3N0UGFuZWwucW1sIGIvYXBwL2d1aS9Dcmlt
c29uSG9zdFBhbmVsLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi4yNDYy
ZjEyCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9Dcmltc29uSG9zdFBhbmVsLnFtbApAQCAt
MCwwICsxLDMyIEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xz
IDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWdu
IDEuMAoraW1wb3J0IFN0cmVhbWluZ1ByZWZlcmVuY2VzIDEuMAorQ3JpbXNvbkdsYXNzUGFuZWwg
eworICAgIGlkOnBhbmVsCisgICAgcHJvcGVydHkgc3RyaW5nIGhvc3ROYW1lOiIiCisgICAgcHJv
cGVydHkgc3RyaW5nIGhvc3RUeXBlOiIiCisgICAgcHJvcGVydHkgc3RyaW5nIHRyYW5zcG9ydDoi
IgorICAgIHByb3BlcnR5IGJvb2wgb25saW5lOmZhbHNlCisgICAgcHJvcGVydHkgdmFyIGhvc3Q6
KHt9KQorICAgIHNpZ25hbCBob3N0UmVxdWVzdGVkKCkKKyAgICBTY3JvbGxWaWV3IHsKKyAgICAg
ICAgYW5jaG9ycy5maWxsOnBhcmVudDthbmNob3JzLm1hcmdpbnM6MTY7Y29udGVudFdpZHRoOmF2
YWlsYWJsZVdpZHRoO2NsaXA6dHJ1ZQorICAgICAgICBDb2x1bW5MYXlvdXQgeworICAgICAgICAg
ICAgd2lkdGg6cGFyZW50LndpZHRoO3NwYWNpbmc6MTYKKyAgICAgICAgICAgIEltYWdlIHsgc291
cmNlOiJxcmM6L3Jlcy9lY2xpcHNlLWljb24uc3ZnIjtMYXlvdXQucHJlZmVycmVkSGVpZ2h0OjY0
O0xheW91dC5wcmVmZXJyZWRXaWR0aDo2NDtMYXlvdXQuYWxpZ25tZW50OlF0LkFsaWduSENlbnRl
ciB9CisgICAgICAgICAgICBMYWJlbCB7IHRleHQ6cGFuZWwuaG9zdE5hbWU7Zm9udC5mYW1pbHk6
VmJUb2tlbnMuZm9udERpc3BsYXk7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUhlYWRpbmc7
Zm9udC5ib2xkOnRydWU7Y29sb3I6VmJUb2tlbnMudGV4dDtMYXlvdXQuZmlsbFdpZHRoOnRydWU7
d3JhcE1vZGU6VGV4dC5XcmFwO3RleHRGb3JtYXQ6VGV4dC5QbGFpblRleHQgfQorICAgICAgICAg
ICAgTGFiZWwgeyB0ZXh0OnBhbmVsLm9ubGluZT9xc1RyKCJDb25uZWN0ZWQgaG9zdCIpOnFzVHIo
Ikhvc3Qgb2ZmbGluZSIpO2NvbG9yOnBhbmVsLm9ubGluZT9WYlRva2Vucy5zdGF0dXNPbmxpbmU6
VmJUb2tlbnMudGV4dERpbTtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlTGFiZWw7TGF5b3V0
LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcCB9CisgICAgICAgICAgICBSZXBlYXRl
ciB7CisgICAgICAgICAgICAgICAgbW9kZWw6W3tsYWJlbDpxc1RyKCJIb3N0IHR5cGUiKSx2YWx1
ZTpwYW5lbC5ob3N0VHlwZXx8cXNUcigiQ29tcGF0aWJsZSBob3N0Iil9LHtsYWJlbDpxc1RyKCJD
b25uZWN0aW9uIiksdmFsdWU6cGFuZWwudHJhbnNwb3J0fHxxc1RyKCJDaGVja2luZyIpfSx7bGFi
ZWw6cXNUcigiUmVxdWVzdGVkIHJlc29sdXRpb24iKSx2YWx1ZTpTdHJlYW1pbmdQcmVmZXJlbmNl
cy53aWR0aCsiIMOXICIrU3RyZWFtaW5nUHJlZmVyZW5jZXMuaGVpZ2h0fSx7bGFiZWw6cXNUcigi
UmVxdWVzdGVkIGZyYW1lIHJhdGUiKSx2YWx1ZTpTdHJlYW1pbmdQcmVmZXJlbmNlcy5mcHMrIiBG
UFMifSx7bGFiZWw6cXNUcigiQml0cmF0ZSBsaW1pdCIpLHZhbHVlOihTdHJlYW1pbmdQcmVmZXJl
bmNlcy5iaXRyYXRlS2Jwcy8xMDAwKS50b0ZpeGVkKDEpKyIgTWJwcyJ9XQorICAgICAgICAgICAg
ICAgIGRlbGVnYXRlOkNvbHVtbkxheW91dCB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTtzcGFjaW5n
OjUKKyAgICAgICAgICAgICAgICAgICAgTGFiZWwge3RleHQ6bW9kZWxEYXRhLmxhYmVsO2ZvbnQu
cGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVDYXB0aW9uO2NvbG9yOlZiVG9rZW5zLnRleHREaW07TGF5
b3V0LmZpbGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcH0KKyAgICAgICAgICAgICAgICAg
ICAgTGFiZWwge3RleHQ6bW9kZWxEYXRhLnZhbHVlO2ZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5
cGVMYWJlbDtjb2xvcjpWYlRva2Vucy50ZXh0O0xheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9k
ZTpUZXh0LldyYXA7dGV4dEZvcm1hdDpUZXh0LlBsYWluVGV4dH0KKyAgICAgICAgICAgICAgICB9
CisgICAgICAgICAgICB9CisgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpx
c1RyKCJIb3N0IGRldGFpbHMiKTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7b25DbGlja2VkOnBhbmVs
Lmhvc3RSZXF1ZXN0ZWQoKSB9CisgICAgICAgICAgICBMYWJlbCB7IHRleHQ6cXNUcigiQ2hvb3Nl
IGFuIGFwcCB0byBzdHJlYW0uIEFjdHVhbCBuZWdvdGlhdGVkIHF1YWxpdHkgYXBwZWFycyBpbiBz
dHJlYW0gc3RhdGlzdGljcy4iKTtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQ2FwdGlvbjtj
b2xvcjpWYlRva2Vucy50ZXh0RGltO0xheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0
LldyYXAgfQorICAgICAgICB9CisgICAgfQorfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9Dcmltc29u
TG9jYWxQYW5lbC5xbWwgYi9hcHAvZ3VpL0NyaW1zb25Mb2NhbFBhbmVsLnFtbApuZXcgZmlsZSBt
b2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi41ZmQyZWQ5Ci0tLSAvZGV2L251bGwKKysrIGIvYXBw
L2d1aS9Dcmltc29uTG9jYWxQYW5lbC5xbWwKQEAgLTAsMCArMSwzNiBAQAoraW1wb3J0IFF0UXVp
Y2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9scyAyLjUKK2ltcG9ydCBRdFF1aWNrLkxheW91
dHMgMS4zCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAKK2ltcG9ydCBMb2NhbEhhcmR3YXJl
IDEuMAorQ3JpbXNvbkdsYXNzUGFuZWwgeworICAgIGlkOiBwYW5lbAorICAgIHByb3BlcnR5IGJv
b2wgYWN0aXZlOiBmYWxzZQorICAgIHNpZ25hbCBjb250cm9sc1JlcXVlc3RlZCgpCisgICAgb25B
Y3RpdmVDaGFuZ2VkOiBMb2NhbEhhcmR3YXJlLnNldENvbnN1bWVyQWN0aXZlKHBhbmVsLGFjdGl2
ZSkKKyAgICBDb21wb25lbnQub25Db21wbGV0ZWQ6IGlmKGFjdGl2ZSkgTG9jYWxIYXJkd2FyZS5z
ZXRDb25zdW1lckFjdGl2ZShwYW5lbCx0cnVlKQorICAgIENvbXBvbmVudC5vbkRlc3RydWN0aW9u
OiBpZihhY3RpdmUpIExvY2FsSGFyZHdhcmUuc2V0Q29uc3VtZXJBY3RpdmUocGFuZWwsZmFsc2Up
CisgICAgZnVuY3Rpb24gcmVhZGluZyhrZXksc3VmZml4KSB7IHZhciB2PUxvY2FsSGFyZHdhcmUu
cmVhZGluZ3Nba2V5XTtyZXR1cm4gdj09PXVuZGVmaW5lZD9xc1RyKCJVbmF2YWlsYWJsZSIpOk51
bWJlcih2KS50b0ZpeGVkKDEpKyhzdWZmaXh8fCIiKSB9CisgICAgU2Nyb2xsVmlldyB7CisgICAg
ICAgIGFuY2hvcnMuZmlsbDpwYXJlbnQ7YW5jaG9ycy5tYXJnaW5zOjE2O2NvbnRlbnRXaWR0aDph
dmFpbGFibGVXaWR0aDtjbGlwOnRydWUKKyAgICAgICAgQ29sdW1uTGF5b3V0IHsKKyAgICAgICAg
ICAgIHdpZHRoOnBhcmVudC53aWR0aDtzcGFjaW5nOjEyCisgICAgICAgICAgICBMYWJlbCB7IHRl
eHQ6cXNUcigiTG9jYWwgU3lzdGVtIik7Zm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udERpc3BsYXk7
Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7Zm9udC5ib2xkOnRydWU7Y29sb3I6VmJU
b2tlbnMudGV4dDtMYXlvdXQuZmlsbFdpZHRoOnRydWU7ZWxpZGU6VGV4dC5FbGlkZVJpZ2h0IH0K
KyAgICAgICAgICAgIExhYmVsIHsgdGV4dDpxc1RyKCJFY2xpcHNlT1MgY29uc29sZSIpO2ZvbnQu
cGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVDYXB0aW9uO2NvbG9yOlZiVG9rZW5zLnRleHREaW07TGF5
b3V0LmZpbGxXaWR0aDp0cnVlO2VsaWRlOlRleHQuRWxpZGVSaWdodCB9CisgICAgICAgICAgICBS
ZXBlYXRlciB7CisgICAgICAgICAgICAgICAgbW9kZWw6W3tsYWJlbDpxc1RyKCJDUFUiKSxrZXk6
ImNwdVBlcmNlbnQiLHN1ZmZpeDoiJSIsbWF4OjEwMH0se2xhYmVsOnFzVHIoIlJBTSIpLGtleToi
bWVtb3J5UGVyY2VudCIsc3VmZml4OiIlIixtYXg6MTAwfSx7bGFiZWw6cXNUcigiVGVtcGVyYXR1
cmUiKSxrZXk6InRlbXBlcmF0dXJlQyIsc3VmZml4OiIgwrBDIixtYXg6MTAwfSx7bGFiZWw6cXNU
cigiTmV0d29yayBkb3dubG9hZCIpLGtleToicmVjZWl2ZU1pQiIsc3VmZml4OiIgTWlCL3MiLG1h
eDowfV0KKyAgICAgICAgICAgICAgICBkZWxlZ2F0ZTpDcmltc29uR2xhc3NQYW5lbCB7CisgICAg
ICAgICAgICAgICAgICAgIG9iamVjdE5hbWU6ImNyaW1zb25NZXRyaWMiO0xheW91dC5maWxsV2lk
dGg6dHJ1ZTtpbXBsaWNpdEhlaWdodDpNYXRoLm1heCg5MixWYlRva2Vucy50eXBlQm9keSozKzI0
KQorICAgICAgICAgICAgICAgICAgICBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgICAgICAg
ICAgICAgYW5jaG9ycy5maWxsOnBhcmVudDthbmNob3JzLm1hcmdpbnM6MTI7c3BhY2luZzo1Cisg
ICAgICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6bW9kZWxEYXRhLmxhYmVsO2ZvbnQu
cGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVMYWJlbDtjb2xvcjpWYlRva2Vucy50ZXh0RGltO0xheW91
dC5maWxsV2lkdGg6dHJ1ZTtlbGlkZTpUZXh0LkVsaWRlUmlnaHQgfQorICAgICAgICAgICAgICAg
ICAgICAgICAgTGFiZWwgeyB0ZXh0OnBhbmVsLnJlYWRpbmcobW9kZWxEYXRhLmtleSxtb2RlbERh
dGEuc3VmZml4KTtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTtmb250LmJvbGQ6dHJ1
ZTtjb2xvcjpWYlRva2Vucy50ZXh0O0xheW91dC5maWxsV2lkdGg6dHJ1ZTtlbGlkZTpUZXh0LkVs
aWRlUmlnaHQgfQorICAgICAgICAgICAgICAgICAgICAgICAgQ3JpbXNvblNwYXJrbGluZSB7IExh
eW91dC5maWxsV2lkdGg6dHJ1ZTtMYXlvdXQucHJlZmVycmVkSGVpZ2h0OjI0O3NhbXBsZXM6TG9j
YWxIYXJkd2FyZS5oaXN0b3J5O21ldHJpYzptb2RlbERhdGEua2V5O2NlaWxpbmc6bW9kZWxEYXRh
Lm1heCB9CisgICAgICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAg
ICAgICB9CisgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpxc1RyKCJTeXN0
ZW0gQ29udHJvbHMiKTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7b25DbGlja2VkOnBhbmVsLmNvbnRy
b2xzUmVxdWVzdGVkKCkgfQorICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OnFzVHIoIkxvY2FsIHJl
YWRpbmdzIOKAoiBtaXNzaW5nIHNlbnNvcnMgc2hvdyBVbmF2YWlsYWJsZSIpO2ZvbnQucGl4ZWxT
aXplOlZiVG9rZW5zLnR5cGVDYXB0aW9uO2NvbG9yOlZiVG9rZW5zLnRleHREaW07TGF5b3V0LmZp
bGxXaWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcCB9CisgICAgICAgIH0KKyAgICB9Cit9CmRp
ZmYgLS1naXQgYS9hcHAvZ3VpL0NyaW1zb25TcGFya2xpbmUucW1sIGIvYXBwL2d1aS9Dcmltc29u
U3BhcmtsaW5lLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi40M2RkM2I0
Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9Dcmltc29uU3BhcmtsaW5lLnFtbApAQCAtMCww
ICsxLDI1IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEu
MAorQ2FudmFzIHsKKyAgICBpZDogZ3JhcGgKKyAgICBwcm9wZXJ0eSB2YXIgc2FtcGxlczogW10K
KyAgICBwcm9wZXJ0eSBzdHJpbmcgbWV0cmljOiAiY3B1UGVyY2VudCIKKyAgICBwcm9wZXJ0eSBy
ZWFsIGNlaWxpbmc6IDEwMAorICAgIHByb3BlcnR5IGNvbG9yIGxpbmVDb2xvcjogVmJUb2tlbnMu
YWNjZW50CisgICAgb25TYW1wbGVzQ2hhbmdlZDogcmVxdWVzdFBhaW50KCkKKyAgICBvbk1ldHJp
Y0NoYW5nZWQ6IHJlcXVlc3RQYWludCgpCisgICAgb25MaW5lQ29sb3JDaGFuZ2VkOiByZXF1ZXN0
UGFpbnQoKQorICAgIG9uV2lkdGhDaGFuZ2VkOiByZXF1ZXN0UGFpbnQoKQorICAgIG9uSGVpZ2h0
Q2hhbmdlZDogcmVxdWVzdFBhaW50KCkKKyAgICBvblBhaW50OiB7CisgICAgICAgIHZhciBjPWdl
dENvbnRleHQoIjJkIik7Yy5jbGVhclJlY3QoMCwwLHdpZHRoLGhlaWdodCkKKyAgICAgICAgdmFy
IGhpZ2g9Y2VpbGluZworICAgICAgICBpZihoaWdoPD0wKSB7IGhpZ2g9MTtmb3IodmFyIGo9MDtq
PHNhbXBsZXMubGVuZ3RoO2orKykgeyB2YXIgbj1zYW1wbGVzW2pdW21ldHJpY107aWYobiE9PXVu
ZGVmaW5lZCYmaXNGaW5pdGUobikpaGlnaD1NYXRoLm1heChoaWdoLG4pIH0gfQorICAgICAgICBj
LnN0cm9rZVN0eWxlPWxpbmVDb2xvcjtjLmxpbmVXaWR0aD0xLjU7Yy5iZWdpblBhdGgoKTt2YXIg
c3RhcnRlZD1mYWxzZQorICAgICAgICBmb3IodmFyIGk9MDtpPHNhbXBsZXMubGVuZ3RoO2krKykg
eyB2YXIgdj1zYW1wbGVzW2ldW21ldHJpY107aWYodj09PXVuZGVmaW5lZHx8IWlzRmluaXRlKHYp
KXtzdGFydGVkPWZhbHNlO2NvbnRpbnVlfQorICAgICAgICAgICAgdmFyIHg9Misod2lkdGgtNCkq
KDYwLXNhbXBsZXMubGVuZ3RoK2kpLzU5LHk9aGVpZ2h0LTItKGhlaWdodC00KSpNYXRoLm1heCgw
LE1hdGgubWluKGhpZ2gsdikpL2hpZ2gKKyAgICAgICAgICAgIGlmKCFzdGFydGVkKWMubW92ZVRv
KHgseSk7ZWxzZSBjLmxpbmVUbyh4LHkpO3N0YXJ0ZWQ9dHJ1ZQorICAgICAgICB9CisgICAgICAg
IGMuc3Ryb2tlKCkKKyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL0NyaW1zb25TdGF0dXNE
aWFsb2cucW1sIGIvYXBwL2d1aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbApuZXcgZmlsZSBtb2Rl
IDEwMDY0NAppbmRleCAwMDAwMDAwLi5hMWQ0NjcyCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1
aS9Dcmltc29uU3RhdHVzRGlhbG9nLnFtbApAQCAtMCwwICsxLDkwIEBACitpbXBvcnQgUXRRdWlj
ayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0
cyAxLjMKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVt
aXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgQ3JpbXNvblN0YXR1cyAxLjAKKworTmF2aWdhYmxlRGlh
bG9nIHsKKyAgICBpZDogcGFuZWwKKyAgICBwcm9wZXJ0eSBzdHJpbmcga2luZDogImhvc3QiCisg
ICAgd2lkdGg6IE1hdGgubWluKDYyMCwgcGFyZW50LndpZHRoIC0gMzIpCisgICAgaGVpZ2h0OiBN
YXRoLm1pbihraW5kID09PSAiaG9zdCIgPyA2NTAgOiAyODAsIHBhcmVudC5oZWlnaHQgLSAzMikK
KyAgICB0aXRsZToga2luZCA9PT0gImhvc3QiID8gcXNUcigiVmliZXBvbGxvIOKAoiBIb3N0IGhh
cmR3YXJlIikgOiBraW5kID09PSAibmV0d29yayIgPyBxc1RyKCJOZXR3b3JrIHN0YXR1cyIpIDog
cXNUcigiQmF0dGVyeSBzdGF0dXMiKQorICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLkNsb3Nl
CisgICAgTWF0ZXJpYWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwu
YWNjZW50OiBWYlRva2Vucy5hY2NlbnQKKyAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5l
bCB7IGNvbG9yOiBWYlRva2Vucy5iZ0VsZXY7IHJhZGl1czogVmJUb2tlbnMucmFkaXVzRGlhbG9n
OyBib3JkZXIuY29sb3I6IFZiVG9rZW5zLnN0cm9rZTsgYm9yZGVyLndpZHRoOiAxIH0KKyAgICBv
bk9wZW5lZDogeworICAgICAgICB1cmxJbnB1dC50ZXh0ID0gQ3JpbXNvblN0YXR1cy5lbmRwb2lu
dAorICAgICAgICBwaW5JbnB1dC50ZXh0ID0gQ3JpbXNvblN0YXR1cy5maW5nZXJwcmludAorICAg
ICAgICB0b2tlbklucHV0LnRleHQgPSAiIgorICAgICAgICBDcmltc29uU3RhdHVzLnNldFZpc2li
bGUoa2luZCA9PT0gImhvc3QiKQorICAgIH0KKyAgICBvbkNsb3NlZDogeyBDcmltc29uU3RhdHVz
LnNldFZpc2libGUoZmFsc2UpOyB0b2tlbklucHV0LnRleHQgPSAiIjsgc3RhY2tWaWV3LmZvcmNl
QWN0aXZlRm9jdXMoKSB9CisgICAgZnVuY3Rpb24gbWV0cmljKGtleSwgc3VmZml4KSB7CisgICAg
ICAgIHZhciBuID0gQ3JpbXNvblN0YXR1cy5zdGF0c1trZXldCisgICAgICAgIHJldHVybiBuID09
PSB1bmRlZmluZWQgPyBxc1RyKCJOL0EiKSA6IE51bWJlcihuKS50b0ZpeGVkKDEpICsgc3VmZml4
CisgICAgfQorICAgIGZ1bmN0aW9uIG1lbW9yeShwcmVmaXgpIHsKKyAgICAgICAgdmFyIHMgPSBD
cmltc29uU3RhdHVzLnN0YXRzCisgICAgICAgIHJldHVybiBzW3ByZWZpeCArICJfdXNlZF9ieXRl
cyJdID09PSB1bmRlZmluZWQgfHwgIXNbcHJlZml4ICsgIl90b3RhbF9ieXRlcyJdID8gcXNUcigi
Ti9BIikKKyAgICAgICAgICAgICA6IChzW3ByZWZpeCArICJfdXNlZF9ieXRlcyJdIC8gMTA3Mzc0
MTgyNCkudG9GaXhlZCgxKSArICIgLyAiICsgKHNbcHJlZml4ICsgIl90b3RhbF9ieXRlcyJdIC8g
MTA3Mzc0MTgyNCkudG9GaXhlZCgxKSArICIgR2lCIgorICAgIH0KKyAgICBjb250ZW50SXRlbTog
U2Nyb2xsVmlldyB7CisgICAgICAgIGNsaXA6IHRydWUKKyAgICAgICAgY29udGVudFdpZHRoOiBh
dmFpbGFibGVXaWR0aAorICAgICAgICBDb2x1bW5MYXlvdXQgeworICAgICAgICAgICAgd2lkdGg6
IHBhbmVsLmF2YWlsYWJsZVdpZHRoCisgICAgICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFj
ZTMKKyAgICAgICAgICAgIExhYmVsIHsKKyAgICAgICAgICAgICAgICB2aXNpYmxlOiBwYW5lbC5r
aW5kICE9PSAiaG9zdCIKKyAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3
cmFwTW9kZTogVGV4dC5XcmFwCisgICAgICAgICAgICAgICAgdGV4dDogcGFuZWwua2luZCA9PT0g
Im5ldHdvcmsiID8gKENyaW1zb25TdGF0dXMubG9jYWwubmV0d29yayArIChDcmltc29uU3RhdHVz
LmxvY2FsLndpZmlTaWduYWwgPj0gMCA/ICIg4oCiICIgKyBDcmltc29uU3RhdHVzLmxvY2FsLndp
ZmlTaWduYWwgKyAiJSBzaWduYWwiIDogIiIpICsgIlxuIiArIHFzVHIoIkFjdGl2ZSBsaW5rIHN0
YXR1czsgaW50ZXJuZXQgYWNjZXNzIGlzIG5vdCBhc3N1bWVkLiIpKQorICAgICAgICAgICAgICAg
ICAgICA6IChDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50ID49IDAgPyBDcmltc29u
U3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50ICsgIiUg4oCiICIgOiAiIikgKyBDcmltc29uU3Rh
dHVzLmxvY2FsLmJhdHRlcnlTdGF0ZQorICAgICAgICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy50
ZXh0OyBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUJvZHkKKyAgICAgICAgICAgIH0KKyAg
ICAgICAgICAgIExhYmVsIHsKKyAgICAgICAgICAgICAgICB2aXNpYmxlOiBwYW5lbC5raW5kID09
PSAiaG9zdCIKKyAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9k
ZTogVGV4dC5XcmFwCisgICAgICAgICAgICAgICAgdGV4dDogQ3JpbXNvblN0YXR1cy5zdGF0dXMK
KyAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMudGV4dERpbQorICAgICAgICAgICAgfQor
ICAgICAgICAgICAgUmVwZWF0ZXIgeworICAgICAgICAgICAgICAgIG1vZGVsOiBwYW5lbC5raW5k
ID09PSAiaG9zdCIgPyBbCisgICAgICAgICAgICAgICAgICAgIFtxc1RyKCJDUFUiKSwgcGFuZWwu
bWV0cmljKCJjcHVfcGVyY2VudCIsICIlIiksIHBhbmVsLm1ldHJpYygiY3B1X3RlbXBfYyIsICIg
wrBDIildLAorICAgICAgICAgICAgICAgICAgICBbcXNUcigiUkFNIiksIHBhbmVsLm1lbW9yeSgi
cmFtIiksIHBhbmVsLm1ldHJpYygicmFtX3BlcmNlbnQiLCAiJSIpXSwKKyAgICAgICAgICAgICAg
ICAgICAgW3FzVHIoIkdQVSIpLCBwYW5lbC5tZXRyaWMoImdwdV9wZXJjZW50IiwgIiUiKSwgcGFu
ZWwubWV0cmljKCJncHVfdGVtcF9jIiwgIiDCsEMiKV0sCisgICAgICAgICAgICAgICAgICAgIFtx
c1RyKCJWUkFNIiksIHBhbmVsLm1lbW9yeSgidnJhbSIpLCBwYW5lbC5tZXRyaWMoInZyYW1fcGVy
Y2VudCIsICIlIildLAorICAgICAgICAgICAgICAgICAgICBbcXNUcigiR1BVIGVuY29kZXIiKSwg
cGFuZWwubWV0cmljKCJncHVfZW5jb2Rlcl9wZXJjZW50IiwgIiUiKSwgIiJdLAorICAgICAgICAg
ICAgICAgICAgICBbcXNUcigiSG9zdCBuZXR3b3JrIiksIHBhbmVsLm1ldHJpYygibmV0X3J4X2Jw
cyIsICIgQi9zIFJYIiksIHBhbmVsLm1ldHJpYygibmV0X3R4X2JwcyIsICIgQi9zIFRYIildCisg
ICAgICAgICAgICAgICAgXSA6IFtdCisgICAgICAgICAgICAgICAgZGVsZWdhdGU6IFJlY3Rhbmds
ZSB7CisgICAgICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7IGltcGxpY2l0
SGVpZ2h0OiA1OAorICAgICAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYmdXaW5kb3c7
IHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ29udHJvbAorICAgICAgICAgICAgICAgICAgICBib3Jk
ZXIuY29sb3I6IFZiVG9rZW5zLnN0cm9rZTsgYm9yZGVyLndpZHRoOiAxCisgICAgICAgICAgICAg
ICAgICAgIFJvd0xheW91dCB7CisgICAgICAgICAgICAgICAgICAgICAgICBhbmNob3JzLmZpbGw6
IHBhcmVudDsgYW5jaG9ycy5tYXJnaW5zOiAxMgorICAgICAgICAgICAgICAgICAgICAgICAgTGFi
ZWwgeyB0ZXh0OiBtb2RlbERhdGFbMF07IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltOyBMYXlvdXQu
cHJlZmVycmVkV2lkdGg6IDExNSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMYWJlbCB7IHRl
eHQ6IG1vZGVsRGF0YVsxXTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IExheW91dC5maWxsV2lkdGg6
IHRydWUgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBtb2RlbERhdGFb
Ml07IGNvbG9yOiBWYlRva2Vucy5hY2NlbnQgfQorICAgICAgICAgICAgICAgICAgICB9CisgICAg
ICAgICAgICAgICAgfQorICAgICAgICAgICAgfQorICAgICAgICAgICAgR3JvdXBCb3ggeworICAg
ICAgICAgICAgICAgIHZpc2libGU6IHBhbmVsLmtpbmQgPT09ICJob3N0IgorICAgICAgICAgICAg
ICAgIHRpdGxlOiBxc1RyKCJDb25maWd1cmUgaG9zdCBzdGF0cyIpCisgICAgICAgICAgICAgICAg
TGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQorICAgICAgICAgICAgICAgIENvbHVtbkxheW91dCB7Cisg
ICAgICAgICAgICAgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50CisgICAgICAgICAgICAgICAg
ICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsg
dGV4dDogcXNUcigiU2VsZWN0IGEgaG9zdCBmaXJzdC4gRW5hYmxlIHJlYWx0aW1lIHN0YXRzIGlu
IFZpYmVwb2xsbyBhbmQgY3JlYXRlIGEgcmVhZC1vbmx5IHRva2VuIGZvciBHRVQgL2FwaS9ob3N0
L3N0YXRzLiBHYW1lU3RyZWFtIHBhaXJpbmcgZG9lcyBub3QgZ3JhbnQgdGhpcyBhY2Nlc3MuIik7
IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICAgICAgVGV4dEZpZWxk
IHsgaWQ6IHVybElucHV0OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBwbGFjZWhvbGRlclRleHQ6
IHFzVHIoIkhUVFBTIGhvc3QgVVJMLCBlLmcuIGh0dHBzOi8vMTkyLjE2OC4xLjEwOjQ3OTkwIik7
IHNlbGVjdEJ5TW91c2U6IHRydWUgfQorICAgICAgICAgICAgICAgICAgICBUZXh0RmllbGQgeyBp
ZDogdG9rZW5JbnB1dDsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgcGxhY2Vob2xkZXJUZXh0OiBx
c1RyKCJSZWFkLW9ubHkgQVBJIHRva2VuIChibGFuayBrZWVwcyBzYXZlZCB0b2tlbikiKTsgZWNo
b01vZGU6IFRleHRJbnB1dC5QYXNzd29yZDsgc2VsZWN0QnlNb3VzZTogdHJ1ZSB9CisgICAgICAg
ICAgICAgICAgICAgIFRleHRGaWVsZCB7IGlkOiBwaW5JbnB1dDsgTGF5b3V0LmZpbGxXaWR0aDog
dHJ1ZTsgcGxhY2Vob2xkZXJUZXh0OiBxc1RyKCJTSEEtMjU2IGNlcnRpZmljYXRlIGZpbmdlcnBy
aW50IGZvciBhIHNlbGYtc2lnbmVkIGhvc3QiKTsgc2VsZWN0QnlNb3VzZTogdHJ1ZSB9CisgICAg
ICAgICAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6
IFRleHQuV3JhcDsgdGV4dDogcXNUcigiVmVyaWZ5IGEgc2VsZi1zaWduZWQgY2VydGlmaWNhdGUn
cyBTSEEtMjU2IGZpbmdlcnByaW50IG9uIHRoZSBob3N0IGJlZm9yZSBzYXZpbmcgaXQuIFRva2Vu
IGlzIHN0b3JlZCBwcml2YXRlbHkgb24gdGhpcyBVU0I7IGl0IGlzIG5vdCBlbmNyeXB0ZWQuIFVu
c3VwcG9ydGVkIG9yIG1pc3Npbmcgc2Vuc29ycyBzaG93IE4vQS4iKTsgY29sb3I6IFZiVG9rZW5z
LnRleHREaW0gfQorICAgICAgICAgICAgICAgICAgICBCdXR0b24geyB0ZXh0OiBxc1RyKCJTYXZl
ICYgY29ubmVjdCIpOyBvbkNsaWNrZWQ6IHsgaWYgKENyaW1zb25TdGF0dXMuY29uZmlndXJlKHVy
bElucHV0LnRleHQsIHRva2VuSW5wdXQudGV4dCwgcGluSW5wdXQudGV4dCkpIHRva2VuSW5wdXQu
dGV4dCA9ICIiIH0gfQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgIH0KKyAgICAgICAg
fQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvRWNsaXBzZUFib3V0RGlhbG9nLnFtbCBi
L2FwcC9ndWkvRWNsaXBzZUFib3V0RGlhbG9nLnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwLi5mYmQwYTNmCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9FY2xpcHNlQWJv
dXREaWFsb2cucW1sCkBAIC0wLDAgKzEsMzQgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0
IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5MYXlvdXRzIDEuMworaW1wb3J0
IFF0UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAx
LjAKK05hdmlnYWJsZURpYWxvZyB7CisgICAgaWQ6IHBhbmVsCisgICAgcHJvcGVydHkgdmFyIGlu
Zm86ICh7fSkKKyAgICB3aWR0aDogTWF0aC5taW4oNTIwLHBhcmVudC53aWR0aC0zMikKKyAgICB0
aXRsZTogcXNUcigiQWJvdXQgRWNsaXBzZSIpCisgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cu
Q2xvc2UKKyAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICBNYXRl
cmlhbC5hY2NlbnQ6IFZiVG9rZW5zLmFjY2VudAorICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFz
c1BhbmVsIHsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNEaWFsb2c7IGNvbG9yOiBWYlRva2Vucy5i
Z0VsZXY7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlCisgICAgICAgIFJlY3RhbmdsZSB7
IGFuY2hvcnMuZmlsbDogcGFyZW50OyBjb2xvcjogInRyYW5zcGFyZW50IjsgZ3JhZGllbnQ6IEdy
YWRpZW50IHsgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246IDA7IGNvbG9yOiBRdC5yZ2JhKDEsMSwx
LDAuMDM1KSB9IEdyYWRpZW50U3RvcCB7IHBvc2l0aW9uOiAxOyBjb2xvcjogInRyYW5zcGFyZW50
IiB9IH0gfQorICAgIH0KKyAgICBjb250ZW50SXRlbTogQ29sdW1uTGF5b3V0IHsKKyAgICAgICAg
c3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCisgICAgICAgIEltYWdlIHsgc291cmNlOiAicXJjOi9y
ZXMvZWNsaXBzZS1pY29uLnN2ZyI7IHNvdXJjZVNpemUud2lkdGg6IDk2OyBzb3VyY2VTaXplLmhl
aWdodDogOTY7IExheW91dC5hbGlnbm1lbnQ6IFF0LkFsaWduSENlbnRlcjsgTGF5b3V0LnByZWZl
cnJlZFdpZHRoOiA5NjsgTGF5b3V0LnByZWZlcnJlZEhlaWdodDogOTYgfQorICAgICAgICBMYWJl
bCB7IHRleHQ6ICJFQ0xJUFNFIjsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQuZmFtaWx5OiBW
YlRva2Vucy5mb250RGlzcGxheTsgZm9udC5waXhlbFNpemU6IDI0OyBmb250LmxldHRlclNwYWNp
bmc6IDQ7IExheW91dC5hbGlnbm1lbnQ6IFF0LkFsaWduSENlbnRlciB9CisgICAgICAgIExhYmVs
IHsgdGV4dDogcXNUcigiTWFkZSBieSBUaDNEM2NrM3IiKTsgY29sb3I6IFZiVG9rZW5zLmFjY2Vu
dDsgTGF5b3V0LmFsaWdubWVudDogUXQuQWxpZ25IQ2VudGVyIH0KKyAgICAgICAgTGFiZWwgewor
ICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4dEZvcm1hdDogVGV4dC5QbGFp
blRleHQ7IHdyYXBNb2RlOiBUZXh0LldyYXA7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltCisgICAg
ICAgICAgICB0ZXh0OiBxc1RyKCJPUzogJTEgJTJcblRhcmdldDogJTNcbkZlZG9yYTogJTRcbktl
cm5lbDogJTVcbkVjbGlwc2UgZnJvbnRlbmQ6ICU2IOKAoiBjdXN0b21pemVkIikKKyAgICAgICAg
ICAgICAgICAuYXJnKChwYW5lbC5pbmZvLm9zIHx8IHt9KS5OQU1FIHx8ICJFY2xpcHNlT1MiKQor
ICAgICAgICAgICAgICAgIC5hcmcoKHBhbmVsLmluZm8ub3MgfHwge30pLlZFUlNJT04gfHwgcXNU
cigiVW5hdmFpbGFibGUiKSkKKyAgICAgICAgICAgICAgICAuYXJnKChwYW5lbC5pbmZvLm9zIHx8
IHt9KS5UQVJHRVQgfHwgcXNUcigiVW5hdmFpbGFibGUiKSkKKyAgICAgICAgICAgICAgICAuYXJn
KChwYW5lbC5pbmZvLm9zIHx8IHt9KS5GRURPUkEgfHwgcXNUcigiVW5hdmFpbGFibGUiKSkKKyAg
ICAgICAgICAgICAgICAuYXJnKHBhbmVsLmluZm8ua2VybmVsIHx8IHFzVHIoIlVuYXZhaWxhYmxl
IikpCisgICAgICAgICAgICAgICAgLmFyZyhRdC5hcHBsaWNhdGlvbi52ZXJzaW9uIHx8ICIwLjUu
MCIpCisgICAgICAgIH0KKyAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3
cmFwTW9kZTogVGV4dC5XcmFwOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbTsgdGV4dDogcXNUcigi
QSBsaWdodHdlaWdodCBFY2xpcHNlT1MgZnJvbnRlbmQuIEJhc2VkIG9uIFZpYmVtaXMgYW5kIE1v
b25saWdodDsgb3JpZ2luYWwgb3Blbi1zb3VyY2UgY3JlZGl0cyBhbmQgbGljZW5zZXMgcmVtYWlu
IGF2YWlsYWJsZSBpbiBTZXR0aW5ncy4gVXBkYXRlcyBhcmUgbWFuYWdlZCBieSBFY2xpcHNlT1Mu
IikgfQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvRWNsaXBzZUFjdGlvbkJ1dHRvbi5x
bWwgYi9hcHAvZ3VpL0VjbGlwc2VBY3Rpb25CdXR0b24ucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0
CmluZGV4IDAwMDAwMDAuLmE4M2VmMDEKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0VjbGlw
c2VBY3Rpb25CdXR0b24ucW1sCkBAIC0wLDAgKzEsMzYgQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQor
aW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAK
K2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLmltcGwgMi41CitCdXR0b24geworICAgIGlkOiBidXR0
b24KKyAgICB0b3BJbnNldDogMDsgYm90dG9tSW5zZXQ6IDA7IGxlZnRJbnNldDogMDsgcmlnaHRJ
bnNldDogMAorICAgIHByb3BlcnR5IHN0cmluZyBpY29uU291cmNlOiAiIgorICAgIGltcGxpY2l0
SGVpZ2h0OiBNYXRoLm1heCg0NCxjb250ZW50SXRlbS5pbXBsaWNpdEhlaWdodCArIDIwKQorICAg
IGltcGxpY2l0V2lkdGg6IE1hdGgubWF4KDEwMCwgY29udGVudEl0ZW0uaW1wbGljaXRXaWR0aCAr
IDI4KQorICAgIHBhZGRpbmc6IDEyCisgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRCb2R5
CisgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVMYWJlbAorICAgIEFjY2Vzc2libGUu
bmFtZTogdGV4dAorICAgIGFjdGl2ZUZvY3VzT25UYWI6IHRydWUKKyAgICBLZXlzLm9uUmV0dXJu
UHJlc3NlZDogaWYgKGVuYWJsZWQpIGNsaWNrZWQoKQorICAgIEtleXMub25FbnRlclByZXNzZWQ6
IGlmIChlbmFibGVkKSBjbGlja2VkKCkKKyAgICBLZXlzLm9uUmlnaHRQcmVzc2VkOiBuZXh0SXRl
bUluRm9jdXNDaGFpbih0cnVlKS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgIEtl
eXMub25MZWZ0UHJlc3NlZDogbmV4dEl0ZW1JbkZvY3VzQ2hhaW4oZmFsc2UpLmZvcmNlQWN0aXZl
Rm9jdXMoUXQuVGFiRm9jdXMpCisgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBuZXh0SXRlbUluRm9j
dXNDaGFpbih0cnVlKS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3VzKQorICAgIEtleXMub25V
cFByZXNzZWQ6IG5leHRJdGVtSW5Gb2N1c0NoYWluKGZhbHNlKS5mb3JjZUFjdGl2ZUZvY3VzKFF0
LlRhYkZvY3VzKQorICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsKKyAgICAgICAg
cmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDb250cm9sCisgICAgICAgIGNvbG9yOiBidXR0b24uZG93
biA/IFZiVG9rZW5zLmJnRWxldjIgOiBidXR0b24uaG92ZXJlZCA/IFZiVG9rZW5zLmJnRWxldjIg
OiBWYlRva2Vucy5iZ1dpbmRvdworICAgICAgICBib3JkZXIud2lkdGg6IGJ1dHRvbi5hY3RpdmVG
b2N1cyA/IDIgOiAxCisgICAgICAgIGJvcmRlci5jb2xvcjogYnV0dG9uLmFjdGl2ZUZvY3VzIHx8
IGJ1dHRvbi5ob3ZlcmVkID8gVmJUb2tlbnMuYWNjZW50IDogVmJUb2tlbnMuc3Ryb2tlCisgICAg
ICAgIG9wYWNpdHk6IGJ1dHRvbi5lbmFibGVkID8gMSA6IDAuNQorICAgIH0KKyAgICBjb250ZW50
SXRlbTogSXRlbSB7CisgICAgICAgIGltcGxpY2l0V2lkdGg6IGJ1dHRvbkxhYmVsLmltcGxpY2l0
V2lkdGggKyAoYnV0dG9uLmljb25Tb3VyY2UgIT09ICIiID8gMjggOiAwKQorICAgICAgICBpbXBs
aWNpdEhlaWdodDogTWF0aC5tYXgoYnV0dG9uTGFiZWwuaW1wbGljaXRIZWlnaHQsIGJ1dHRvbi5p
Y29uU291cmNlICE9PSAiIiA/IDIwIDogMCkKKyAgICAgICAgb3BhY2l0eTogYnV0dG9uLmVuYWJs
ZWQgPyAxIDogMC41CisgICAgICAgIEljb25JbWFnZSB7IGNvbG9yOiBWYlRva2Vucy5hY2NlbnQ7
IHZpc2libGU6IGJ1dHRvbi5pY29uU291cmNlICE9PSAiIjsgc291cmNlOiBidXR0b24uaWNvblNv
dXJjZTsgd2lkdGg6IHZpc2libGUgPyAyMCA6IDA7IGhlaWdodDogMjA7IHg6YnV0dG9uLnRleHQu
bGVuZ3RoPT09MD8ocGFyZW50LndpZHRoLXdpZHRoKS8yOjA7IGFuY2hvcnMudmVydGljYWxDZW50
ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlciB9CisgICAgICAgIExhYmVsIHsgaWQ6YnV0dG9uTGFi
ZWw7dGV4dDogYnV0dG9uLnRleHQ7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyBjb2xvcjog
VmJUb2tlbnMudGV4dDsgZm9udDogYnV0dG9uLmZvbnQ7eDpidXR0b24uaWNvblNvdXJjZSAhPT0g
IiIgPyAyOCA6IDA7d2lkdGg6TWF0aC5tYXgoMCxwYXJlbnQud2lkdGgteCk7ZWxpZGU6VGV4dC5F
bGlkZVJpZ2h0OyBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIg
fQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvRWNsaXBzZUNvbWJvQm94LnFtbCBiL2Fw
cC9ndWkvRWNsaXBzZUNvbWJvQm94LnFtbApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAw
MDAwLi5mNDc2ZGUxCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL2d1aS9FY2xpcHNlQ29tYm9Cb3gu
cW1sCkBAIC0wLDAgKzEsMjggQEAKK2ltcG9ydCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2su
Q29udHJvbHMgMi41CitpbXBvcnQgUXRRdWljay5Db250cm9scy5NYXRlcmlhbCAyLjIKK2ltcG9y
dCBWaWJlbWlzLlJlZGVzaWduIDEuMAorQ29tYm9Cb3ggeworICAgIGlkOiBjb250cm9sCisgICAg
dG9wSW5zZXQ6IDA7IGJvdHRvbUluc2V0OiAwOyBsZWZ0SW5zZXQ6IDA7IHJpZ2h0SW5zZXQ6IDAK
KyAgICBpbXBsaWNpdEhlaWdodDogTWF0aC5tYXgoNDQsIGZvbnQucGl4ZWxTaXplICsgMjQpCisg
ICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRCb2R5CisgICAgZm9udC5waXhlbFNpemU6IFZi
VG9rZW5zLnR5cGVMYWJlbAorICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50Cisg
ICAgbGVmdFBhZGRpbmc6IDEyOyByaWdodFBhZGRpbmc6IDM2CisgICAgYmFja2dyb3VuZDogQ3Jp
bXNvbkdsYXNzUGFuZWwgeyBjb2xvcjogVmJUb2tlbnMuYmdFbGV2OyByYWRpdXM6IFZiVG9rZW5z
LnJhZGl1c0NvbnRyb2w7IGJvcmRlci5jb2xvcjogY29udHJvbC5hY3RpdmVGb2N1cyA/IFZiVG9r
ZW5zLmFjY2VudCA6IFZiVG9rZW5zLnN0cm9rZTsgYm9yZGVyLndpZHRoOiBjb250cm9sLmFjdGl2
ZUZvY3VzID8gMiA6IDE7IG9wYWNpdHk6IGNvbnRyb2wuZW5hYmxlZCA/IDEgOiAuNSB9CisgICAg
Y29udGVudEl0ZW06IExhYmVsIHsgdGV4dDogY29udHJvbC5kaXNwbGF5VGV4dDsgdGV4dEZvcm1h
dDogVGV4dC5QbGFpblRleHQ7IGZvbnQ6IGNvbnRyb2wuZm9udDsgY29sb3I6IFZiVG9rZW5zLnRl
eHQ7IHZlcnRpY2FsQWxpZ25tZW50OiBUZXh0LkFsaWduVkNlbnRlcjsgZWxpZGU6IFRleHQuRWxp
ZGVSaWdodDsgb3BhY2l0eTogY29udHJvbC5lbmFibGVkID8gMSA6IC41IH0KKyAgICBkZWxlZ2F0
ZTogSXRlbURlbGVnYXRlIHsKKyAgICAgICAgd2lkdGg6IGNvbnRyb2wud2lkdGgKKyAgICAgICAg
aW1wbGljaXRIZWlnaHQ6IE1hdGgubWF4KDQ0LGNvbnRyb2wuZm9udC5waXhlbFNpemUrMjQpCisg
ICAgICAgIGhpZ2hsaWdodGVkOiBjb250cm9sLmhpZ2hsaWdodGVkSW5kZXggPT09IGluZGV4Cisg
ICAgICAgIGNvbnRlbnRJdGVtOiBMYWJlbCB7IHRleHQ6IGNvbnRyb2wudGV4dEF0KGluZGV4KTsg
dGV4dEZvcm1hdDpUZXh0LlBsYWluVGV4dDsgZm9udDpjb250cm9sLmZvbnQ7IGNvbG9yOlZiVG9r
ZW5zLnRleHQ7IGVsaWRlOlRleHQuRWxpZGVSaWdodCB9CisgICAgICAgIGJhY2tncm91bmQ6IENy
aW1zb25HbGFzc1BhbmVsIHsgY29sb3I6IHBhcmVudC5oaWdobGlnaHRlZCA/IFZiVG9rZW5zLmJn
RWxldjIgOiBWYlRva2Vucy5iZ0VsZXY7IHJhZGl1czpWYlRva2Vucy5yYWRpdXNDb250cm9sOyBi
b3JkZXIuY29sb3I6cGFyZW50LmhpZ2hsaWdodGVkP1ZiVG9rZW5zLmFjY2VudDoidHJhbnNwYXJl
bnQiIH0KKyAgICB9CisgICAgcG9wdXA6IFBvcHVwIHsKKyAgICAgICAgeTogY29udHJvbC5oZWln
aHQgKyA0OyB3aWR0aDpjb250cm9sLndpZHRoOyBwYWRkaW5nOjYKKyAgICAgICAgaW1wbGljaXRI
ZWlnaHQ6IE1hdGgubWluKGNvbnRlbnRJdGVtLmltcGxpY2l0SGVpZ2h0ICsgMTIsMzIwKQorICAg
ICAgICBiYWNrZ3JvdW5kOkNyaW1zb25HbGFzc1BhbmVsIHsgY29sb3I6VmJUb2tlbnMuYmdFbGV2
O3JhZGl1czpWYlRva2Vucy5yYWRpdXNDb250cm9sO2JvcmRlci5jb2xvcjpWYlRva2Vucy5zdHJv
a2UgfQorICAgICAgICBjb250ZW50SXRlbTpMaXN0VmlldyB7IGNsaXA6dHJ1ZTtpbXBsaWNpdEhl
aWdodDpjb250ZW50SGVpZ2h0O21vZGVsOmNvbnRyb2wucG9wdXAudmlzaWJsZT9jb250cm9sLmRl
bGVnYXRlTW9kZWw6bnVsbDtjdXJyZW50SW5kZXg6Y29udHJvbC5oaWdobGlnaHRlZEluZGV4O1Nj
cm9sbEluZGljYXRvci52ZXJ0aWNhbDpTY3JvbGxJbmRpY2F0b3Ige30gfQorICAgIH0KK30KZGlm
ZiAtLWdpdCBhL2FwcC9ndWkvRWNsaXBzZUNvbnRyb2xDZW50ZXIucW1sIGIvYXBwL2d1aS9FY2xp
cHNlQ29udHJvbENlbnRlci5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4u
ZTIzMmUxZQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9ndWkvRWNsaXBzZUNvbnRyb2xDZW50ZXIu
cW1sCkBAIC0wLDAgKzEsMTY0IEBACitpbXBvcnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNr
LkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVpY2suTGF5b3V0cyAxLjMKK2ltcG9ydCBRdFF1aWNr
LkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBv
cnQgU3lzdGVtQ29udHJvbHMgMS4wCitpbXBvcnQgQ3JpbXNvblN0YXR1cyAxLjAKK2ltcG9ydCBT
dHJlYW1pbmdQcmVmZXJlbmNlcyAxLjAKK2ltcG9ydCBFY2xpcHNlUHJvZmlsZXMgMS4wCisKK0Ry
YXdlciB7CisgICAgaWQ6IHBhbmVsCisgICAgZWRnZTogUXQuUmlnaHRFZGdlCisgICAgd2lkdGg6
IE1hdGgubWluKDU2MCwgcGFyZW50LndpZHRoIC0gMjQpCisgICAgaGVpZ2h0OiBwYXJlbnQuaGVp
Z2h0CisgICAgbW9kYWw6IHRydWUKKyAgICBPdmVybGF5Lm1vZGFsOiBSZWN0YW5nbGUge2NvbG9y
OlZiVG9rZW5zLnNoZWV0U2NyaW19CisgICAgZW50ZXI6IFRyYW5zaXRpb24geyBOdW1iZXJBbmlt
YXRpb24geyBwcm9wZXJ0eTogInBvc2l0aW9uIjsgZnJvbTogMDsgdG86IDE7IGR1cmF0aW9uOiBW
YlRva2Vucy5zaGVldEluTXMgfSB9CisgICAgZXhpdDogVHJhbnNpdGlvbiB7IE51bWJlckFuaW1h
dGlvbiB7IHByb3BlcnR5OiAicG9zaXRpb24iOyBmcm9tOiAxOyB0bzogMDsgZHVyYXRpb246IFZi
VG9rZW5zLnNoZWV0SW5NcyB9IH0KKyAgICBwcm9wZXJ0eSB2YXIgaG9zdDogKHt9KQorICAgIHBy
b3BlcnR5IGJvb2wgY2FuV2FrZTogZmFsc2UKKyAgICBwcm9wZXJ0eSBib29sIGNhbk1hbmFnZTog
ZmFsc2UKKyAgICBwcm9wZXJ0eSBzdHJpbmcgbmV4dFBhbmVsOiAiIgorICAgIHByb3BlcnR5IHN0
cmluZyBtZXNzYWdlOiAiIgorICAgIHByb3BlcnR5IHZhciBzYXZlZE5hbWVzOiBbXQorICAgIHBy
b3BlcnR5IHN0cmluZyBwb3dlckFjdGlvbjogIiIKKyAgICBzaWduYWwgbmF2aWdhdGVSZXF1ZXN0
ZWQoc3RyaW5nIGRlc3RpbmF0aW9uKQorICAgIHNpZ25hbCB3YWtlUmVxdWVzdGVkKCkKKyAgICBN
YXRlcmlhbC50aGVtZTogTWF0ZXJpYWwuRGFyaworICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZi
VG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAg
YmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgeyBjb2xvcjogVmJUb2tlbnMuYmdFbGV2OyBi
b3JkZXIuY29sb3I6IFZiVG9rZW5zLnN0cm9rZQorICAgICAgICBSZWN0YW5nbGUgeyBhbmNob3Jz
LmZpbGw6IHBhcmVudDsgY29sb3I6ICJ0cmFuc3BhcmVudCI7IGdyYWRpZW50OiBHcmFkaWVudCB7
IEdyYWRpZW50U3RvcCB7IHBvc2l0aW9uOiAwOyBjb2xvcjogUXQucmdiYSgxLDEsMSwwLjAzNSkg
fSBHcmFkaWVudFN0b3AgeyBwb3NpdGlvbjogMTsgY29sb3I6ICJ0cmFuc3BhcmVudCIgfSB9IH0K
KyAgICB9CisgICAgZnVuY3Rpb24gZGVmZXIoZGVzdGluYXRpb24pIHsgbmV4dFBhbmVsID0gZGVz
dGluYXRpb247IGNsb3NlKCkgfQorICAgIGZ1bmN0aW9uIGFwcGx5KHZhbHVlcykgeworICAgICAg
ICBpZiAoIXZhbHVlcy53aWR0aCkgeyBtZXNzYWdlID0gcXNUcigiU2F2ZSB0aGlzIHByb2ZpbGUg
Zmlyc3QuIik7IHJldHVybiB9CisgICAgICAgIFN0cmVhbWluZ1ByZWZlcmVuY2VzLndpZHRoID0g
dmFsdWVzLndpZHRoCisgICAgICAgIFN0cmVhbWluZ1ByZWZlcmVuY2VzLmhlaWdodCA9IHZhbHVl
cy5oZWlnaHQKKyAgICAgICAgU3RyZWFtaW5nUHJlZmVyZW5jZXMuZnBzID0gdmFsdWVzLmZwcwor
ICAgICAgICBTdHJlYW1pbmdQcmVmZXJlbmNlcy5iaXRyYXRlS2JwcyA9IHZhbHVlcy5iaXRyYXRl
S2JwcworICAgICAgICBTdHJlYW1pbmdQcmVmZXJlbmNlcy5zYXZlKCkKKyAgICAgICAgbWVzc2Fn
ZSA9IHFzVHIoIlByb2ZpbGUgYXBwbGllZCBmb3IgdGhlIG5leHQgc3RyZWFtLiIpCisgICAgfQor
ICAgIG9uT3BlbmVkOiB7IG1lc3NhZ2UgPSAiIjsgU3lzdGVtQ29udHJvbHMub3BlbigiY2VudGVy
Iik7IHByb2ZpbGVOYW1lLnRleHQgPSAiR2FtaW5nIjsgc2F2ZWROYW1lcyA9IEVjbGlwc2VQcm9m
aWxlcy5uYW1lcyhob3N0LmlkIHx8ICIiKSB9CisgICAgb25DbG9zZWQ6IHsKKyAgICAgICAgcG93
ZXJEaWFsb2cuY2xvc2UoKTsgU3lzdGVtQ29udHJvbHMuY2xvc2UoKTsgc3RhY2tWaWV3LmZvcmNl
QWN0aXZlRm9jdXMoKQorICAgICAgICBpZiAobmV4dFBhbmVsICE9PSAiIikgeyB2YXIgZGVzdGlu
YXRpb24gPSBuZXh0UGFuZWw7IG5leHRQYW5lbCA9ICIiOyBuYXZpZ2F0ZVJlcXVlc3RlZChkZXN0
aW5hdGlvbikgfQorICAgIH0KKyAgICBjb250ZW50SXRlbTogQ29sdW1uTGF5b3V0IHsKKyAgICAg
ICAgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGFuY2hvcnMubWFyZ2luczogMjA7IHNwYWNpbmc6IFZi
VG9rZW5zLnNwYWNlMworICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgTGF5b3V0LmZp
bGxXaWR0aDogdHJ1ZQorICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBxc1RyKCJFY2xpcHNlIOKA
oiBDb250cm9sIGNlbnRlciIpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5mYW1pbHk6IFZi
VG9rZW5zLmZvbnREaXNwbGF5OyBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUJvZHk7IExh
eW91dC5maWxsV2lkdGg6IHRydWUgfQorICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7
IHRleHQ6IHFzVHIoIkNsb3NlIik7IG9uQ2xpY2tlZDogcGFuZWwuY2xvc2UoKSB9CisgICAgICAg
IH0KKyAgICAgICAgU2Nyb2xsVmlldyB7CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0
cnVlOyBMYXlvdXQuZmlsbEhlaWdodDogdHJ1ZQorICAgICAgICAgICAgY2xpcDogdHJ1ZTsgY29u
dGVudFdpZHRoOiBhdmFpbGFibGVXaWR0aAorICAgICAgICAgICAgQ29sdW1uTGF5b3V0IHsKKyAg
ICAgICAgICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoOyBzcGFjaW5nOiBWYlRva2Vucy5zcGFj
ZTMKKyAgICAgICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHRleHRG
b3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0ZXh0OiBDcmltc29u
U3RhdHVzLmxvY2FsLm5ldHdvcmsgfHwgcXNUcigiTmV0d29yayB1bmF2YWlsYWJsZSIpOyBjb2xv
cjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmls
bFdpZHRoOiB0cnVlOyB0ZXh0OiBDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50ID49
IDAgPyBxc1RyKCJCYXR0ZXJ5ICUxJSDigKIgJTIiKS5hcmcoQ3JpbXNvblN0YXR1cy5sb2NhbC5i
YXR0ZXJ5UGVyY2VudCkuYXJnKENyaW1zb25TdGF0dXMubG9jYWwuYmF0dGVyeVN0YXRlKSA6IHFz
VHIoIkJhdHRlcnkgdW5hdmFpbGFibGUiKTsgY29sb3I6IFZiVG9rZW5zLnRleHREaW07IHdyYXBN
b2RlOiBUZXh0LldyYXAgfQorICAgICAgICAgICAgICAgIFJvd0xheW91dCB7CisgICAgICAgICAg
ICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJXaS1GaSIpOyBpY29u
U291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZyI7IG9uQ2xpY2tlZDogcGFuZWwu
ZGVmZXIoIndpZmkiKSB9CisgICAgICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24g
eyB0ZXh0OiBxc1RyKCJCbHVldG9vdGgiKTsgaWNvblNvdXJjZTogInFyYzovcmVzL2NyaW1zb24t
Ymx1ZXRvb3RoLnN2ZyI7IG9uQ2xpY2tlZDogcGFuZWwuZGVmZXIoImJ0IikgfQorICAgICAgICAg
ICAgICAgIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIkF1ZGlvIik7IGNv
bG9yOiBWYlRva2Vucy50ZXh0OyBmb250LmJvbGQ6IHRydWUgfQorICAgICAgICAgICAgICAgIFJv
d0xheW91dCB7CisgICAgICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAg
ICAgICAgICAgICAgICAgICAgU2xpZGVyIHsKKyAgICAgICAgICAgICAgICAgICAgICAgIGlkOiB2
b2x1bWVTbGlkZXIKKyAgICAgICAgICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRy
dWU7IGZyb206IDA7IHRvOiAxMDA7IHN0ZXBTaXplOiAxCisgICAgICAgICAgICAgICAgICAgICAg
ICB2YWx1ZTogU3lzdGVtQ29udHJvbHMuc3RhdGUudm9sdW1lID09PSB1bmRlZmluZWQgfHwgU3lz
dGVtQ29udHJvbHMuc3RhdGUudm9sdW1lID09PSBudWxsID8gMCA6IFN5c3RlbUNvbnRyb2xzLnN0
YXRlLnZvbHVtZQorICAgICAgICAgICAgICAgICAgICAgICAgZW5hYmxlZDogIVN5c3RlbUNvbnRy
b2xzLmJ1c3kgJiYgU3lzdGVtQ29udHJvbHMuc3RhdGUudm9sdW1lICE9PSB1bmRlZmluZWQgJiYg
U3lzdGVtQ29udHJvbHMuc3RhdGUudm9sdW1lICE9PSBudWxsCisgICAgICAgICAgICAgICAgICAg
ICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIlNwZWFrZXIgdm9sdW1lIikKKyAgICAgICAgICAg
ICAgICAgICAgICAgIG9uTW92ZWQ6IGlmICghcHJlc3NlZCAmJiBlbmFibGVkKSBTeXN0ZW1Db250
cm9scy5yZXF1ZXN0KCJjZW50ZXItdm9sdW1lIiwgU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSkK
KyAgICAgICAgICAgICAgICAgICAgICAgIG9uUHJlc3NlZENoYW5nZWQ6IGlmICghcHJlc3NlZCAm
JiBlbmFibGVkKSBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItdm9sdW1lIiwgU3RyaW5n
KE1hdGgucm91bmQodmFsdWUpKSkKKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAg
ICAgICAgICBMYWJlbCB7IGlkOiB2b2x1bWVSZWFkb3V0OyB0ZXh0OiBNYXRoLnJvdW5kKHZvbHVt
ZVNsaWRlci52YWx1ZSkrIiUiOyBjb2xvcjogVmJUb2tlbnMudGV4dCB9CisgICAgICAgICAgICAg
ICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBTeXN0ZW1Db250cm9scy5zdGF0ZS5t
dXRlZCA/IHFzVHIoIlVubXV0ZSIpIDogcXNUcigiTXV0ZSIpOyBlbmFibGVkOiAhU3lzdGVtQ29u
dHJvbHMuYnVzeSAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUgIT09IG51bGwgJiYgU3lz
dGVtQ29udHJvbHMuc3RhdGUudm9sdW1lICE9PSB1bmRlZmluZWQ7IG9uQ2xpY2tlZDogU3lzdGVt
Q29udHJvbHMucmVxdWVzdCgiY2VudGVyLW11dGUiKSB9CisgICAgICAgICAgICAgICAgfQorICAg
ICAgICAgICAgICAgIEVjbGlwc2VDb21ib0JveCB7CisgICAgICAgICAgICAgICAgICAgIExheW91
dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgICAgICAgICAgbW9kZWw6IFN5c3RlbUNvbnRy
b2xzLnN0YXRlLnNpbmtzIHx8IFtdOyB0ZXh0Um9sZTogIm5hbWUiCisgICAgICAgICAgICAgICAg
ICAgIGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5ICYmIGNvdW50ID4gMAorICAgICAgICAg
ICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIkF1ZGlvIG91dHB1dCIpCisgICAgICAg
ICAgICAgICAgICAgIGN1cnJlbnRJbmRleDogeyB2YXIgbGlzdCA9IFN5c3RlbUNvbnRyb2xzLnN0
YXRlLnNpbmtzIHx8IFtdOyBmb3IgKHZhciBpPTA7aTxsaXN0Lmxlbmd0aDtpKyspIGlmIChsaXN0
W2ldLmRlZmF1bHQpIHJldHVybiBpOyByZXR1cm4gLTEgfQorICAgICAgICAgICAgICAgICAgICBj
b250ZW50SXRlbTogTGFiZWwgeyB0ZXh0OiBwYXJlbnQuZGlzcGxheVRleHQ7IHRleHRGb3JtYXQ6
IFRleHQuUGxhaW5UZXh0OyBjb2xvcjogVmJUb2tlbnMudGV4dDsgdmVydGljYWxBbGlnbm1lbnQ6
IFRleHQuQWxpZ25WQ2VudGVyOyBlbGlkZTogVGV4dC5FbGlkZVJpZ2h0IH0KKyAgICAgICAgICAg
ICAgICAgICAgZGVsZWdhdGU6IEl0ZW1EZWxlZ2F0ZSB7IHdpZHRoOiBwYXJlbnQud2lkdGg7IGNv
bnRlbnRJdGVtOiBMYWJlbCB7IHRleHQ6IG1vZGVsRGF0YS5uYW1lOyB0ZXh0Rm9ybWF0OiBUZXh0
LlBsYWluVGV4dDsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGVsaWRlOiBUZXh0LkVsaWRlUmlnaHQg
fSB9CisgICAgICAgICAgICAgICAgICAgIG9uQWN0aXZhdGVkOiBTeXN0ZW1Db250cm9scy5yZXF1
ZXN0KCJjZW50ZXItb3V0cHV0IiwgbW9kZWxbaW5kZXhdLmlkKQorICAgICAgICAgICAgICAgIH0K
KyAgICAgICAgICAgICAgICBSZXBlYXRlciB7CisgICAgICAgICAgICAgICAgICAgIG1vZGVsOiBb
e2tpbmQ6InNjcmVlbiIsbGFiZWw6cXNUcigiU2NyZWVuIGJyaWdodG5lc3MiKX0se2tpbmQ6Imtl
eWJvYXJkIixsYWJlbDpxc1RyKCJLZXlib2FyZCBicmlnaHRuZXNzIil9XQorICAgICAgICAgICAg
ICAgICAgICBkZWxlZ2F0ZTogQ29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgICAg
IExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAgICAgICAgICAgICAgICAgICAgIHByb3BlcnR5
IHZhciBoYXJkd2FyZTogKFN5c3RlbUNvbnRyb2xzLnN0YXRlLmJyaWdodG5lc3MgfHwge30pW21v
ZGVsRGF0YS5raW5kXQorICAgICAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBtb2Rl
bERhdGEubGFiZWwgKyAoaGFyZHdhcmUgPyAiIOKAoiAiICsgaGFyZHdhcmUucGVyY2VudCArICIl
IiA6ICIg4oCiICIgKyBxc1RyKCJVbmF2YWlsYWJsZSIpKTsgY29sb3I6IFZiVG9rZW5zLnRleHQg
fQorICAgICAgICAgICAgICAgICAgICAgICAgU2xpZGVyIHsKKyAgICAgICAgICAgICAgICAgICAg
ICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBmcm9tOiBtb2RlbERhdGEua2luZCA9PT0g
InNjcmVlbiIgPyA1IDogMDsgdG86IDEwMDsgc3RlcFNpemU6IDEKKyAgICAgICAgICAgICAgICAg
ICAgICAgICAgICB2YWx1ZTogaGFyZHdhcmUgPyBoYXJkd2FyZS5wZXJjZW50IDogMDsgZW5hYmxl
ZDogISFoYXJkd2FyZSAmJiAhU3lzdGVtQ29udHJvbHMuYnVzeQorICAgICAgICAgICAgICAgICAg
ICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogbW9kZWxEYXRhLmxhYmVsCisgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgb25Nb3ZlZDogaWYgKCFwcmVzc2VkICYmIGVuYWJsZWQpIFN5c3RlbUNv
bnRyb2xzLnJlcXVlc3QoImNlbnRlci0iK21vZGVsRGF0YS5raW5kLCBTdHJpbmcoTWF0aC5yb3Vu
ZCh2YWx1ZSkpKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgIG9uUHJlc3NlZENoYW5nZWQ6
IGlmICghcHJlc3NlZCAmJiBlbmFibGVkKSBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXIt
Iittb2RlbERhdGEua2luZCwgU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSkKKyAgICAgICAgICAg
ICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIH0K
KyAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiUmVmcmVz
aCBjb250cm9scyIpOyBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiBT
eXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItbGlzdCIpIH0KKyAgICAgICAgICAgICAgICBM
YWJlbCB7IHRleHQ6IHFzVHIoIkhvc3QiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQuYm9s
ZDogdHJ1ZSB9CisgICAgICAgICAgICAgICAgTGFiZWwgeyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVl
OyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgd3JhcE1vZGU6IFRleHQuV3JhcDsgdGV4dDog
cGFuZWwuaG9zdC51cmwgfHwgcXNUcigiU2VsZWN0IGEgaG9zdCBpbiB0aGUgbGF1bmNoZXIuIik7
IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAgICAgICAgICAgICBSb3dMYXlvdXQgewor
ICAgICAgICAgICAgICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDogcXNUcigiSG9z
dCBzdGF0cyIpOyBlbmFibGVkOiAhIXBhbmVsLmhvc3QuaWQ7IGljb25Tb3VyY2U6ICJxcmM6L3Jl
cy9jcmltc29uLWhvc3Quc3ZnIjsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigiaG9zdCIpIH0KKyAg
ICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIldha2Ug
aG9zdCIpOyBlbmFibGVkOiAhIXBhbmVsLmhvc3QuaWQgJiYgcGFuZWwuY2FuV2FrZTsgb25DbGlj
a2VkOiB7IHBhbmVsLndha2VSZXF1ZXN0ZWQoKTsgcGFuZWwubWVzc2FnZSA9IHFzVHIoIldha2Ug
cmVxdWVzdCBzZW50OyB0aGUgaG9zdCBtdXN0IHN1cHBvcnQgV2FrZS1vbi1MQU4uIikgfSB9Cisg
ICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0
ZXh0OiBxc1RyKCJPcGVuIGhvc3QgbWFuYWdlbWVudCIpOyBlbmFibGVkOiAhIXBhbmVsLmhvc3Qu
dXJsICYmIHBhbmVsLmNhbk1hbmFnZTsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigibWFuYWdlbWVu
dCIpIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIlN0cmVhbSBwcm9maWxl
cyIpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAgICAgICAgICAg
ICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0LldyYXA7
IHRleHQ6IHBhbmVsLmhvc3QuaWQgPyBxc1RyKCJTYXZlZCBmb3IgdGhlIHNlbGVjdGVkIGhvc3Qu
IEFwcGx5IGJlZm9yZSBzdGFydGluZyBhIHN0cmVhbS4iKSA6IHFzVHIoIkdsb2JhbCBwcm9maWxl
cy4gQXBwbHkgYmVmb3JlIHN0YXJ0aW5nIGEgc3RyZWFtLiIpOyBjb2xvcjogVmJUb2tlbnMudGV4
dERpbSB9CisgICAgICAgICAgICAgICAgRWNsaXBzZUNvbWJvQm94IHsgTGF5b3V0LmZpbGxXaWR0
aDogdHJ1ZTsgbW9kZWw6IHBhbmVsLnNhdmVkTmFtZXM7IHZpc2libGU6IGNvdW50ID4gMDsgQWNj
ZXNzaWJsZS5uYW1lOiBxc1RyKCJTYXZlZCBwcm9maWxlcyIpOyBvbkFjdGl2YXRlZDogcHJvZmls
ZU5hbWUudGV4dCA9IG1vZGVsW2luZGV4XSB9CisgICAgICAgICAgICAgICAgVGV4dEZpZWxkIHsg
aWQ6IHByb2ZpbGVOYW1lOyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBtYXhpbXVtTGVuZ3RoOiA0
ODsgcGxhY2Vob2xkZXJUZXh0OiBxc1RyKCJQcm9maWxlIG5hbWUiKTsgQWNjZXNzaWJsZS5uYW1l
OiBxc1RyKCJQcm9maWxlIG5hbWUiKSB9CisgICAgICAgICAgICAgICAgUm93TGF5b3V0IHsKKyAg
ICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIlNhdmUg
Y3VycmVudCIpOyBvbkNsaWNrZWQ6IHsgcGFuZWwubWVzc2FnZSA9IEVjbGlwc2VQcm9maWxlcy5z
YXZlKHBhbmVsLmhvc3QuaWQgfHwgIiIsIHByb2ZpbGVOYW1lLnRleHQsIHt3aWR0aDpTdHJlYW1p
bmdQcmVmZXJlbmNlcy53aWR0aCxoZWlnaHQ6U3RyZWFtaW5nUHJlZmVyZW5jZXMuaGVpZ2h0LGZw
czpTdHJlYW1pbmdQcmVmZXJlbmNlcy5mcHMsYml0cmF0ZUticHM6U3RyZWFtaW5nUHJlZmVyZW5j
ZXMuYml0cmF0ZUticHN9KSA/IHFzVHIoIlByb2ZpbGUgc2F2ZWQuIikgOiBxc1RyKCJQcm9maWxl
IGNvdWxkIG5vdCBiZSBzYXZlZC4iKTsgcGFuZWwuc2F2ZWROYW1lcyA9IEVjbGlwc2VQcm9maWxl
cy5uYW1lcyhwYW5lbC5ob3N0LmlkIHx8ICIiKSB9IH0KKyAgICAgICAgICAgICAgICAgICAgRWNs
aXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIkFwcGx5IHNhdmVkIik7IG9uQ2xpY2tlZDog
cGFuZWwuYXBwbHkoRWNsaXBzZVByb2ZpbGVzLmxvYWQocGFuZWwuaG9zdC5pZCB8fCAiIiwgcHJv
ZmlsZU5hbWUudGV4dCkpIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgUm93
TGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6
IHFzVHIoIkRlc2t0b3AgcHJlc2V0Iik7IG9uQ2xpY2tlZDogcGFuZWwuYXBwbHkoe3dpZHRoOjEy
ODAsaGVpZ2h0OjgwMCxmcHM6NjAsYml0cmF0ZUticHM6MTUwMDB9KSB9CisgICAgICAgICAgICAg
ICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJMb3cgYmFuZHdpZHRoIik7
IG9uQ2xpY2tlZDogcGFuZWwuYXBwbHkoe3dpZHRoOjEyODAsaGVpZ2h0OjcyMCxmcHM6MzAsYml0
cmF0ZUticHM6NTAwMH0pIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAgICAgTGFi
ZWwgeyB0ZXh0OiBxc1RyKCJBcHBlYXJhbmNlICYgYWNjZXNzaWJpbGl0eSIpOyBjb2xvcjogVmJU
b2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAgICAgICAgICAgICAgICBFY2xpcHNlQ29t
Ym9Cb3ggeworICAgICAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBtb2Rl
bDogW3FzVHIoIlRleHQgMTAwJSIpLHFzVHIoIlRleHQgMTEwJSIpLHFzVHIoIlRleHQgMTI1JSIp
XQorICAgICAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIlRleHQgc2l6ZSIp
CisgICAgICAgICAgICAgICAgICAgIGN1cnJlbnRJbmRleDogRWNsaXBzZVByb2ZpbGVzLnRleHRT
Y2FsZSA9PT0gMTI1ID8gMiA6IEVjbGlwc2VQcm9maWxlcy50ZXh0U2NhbGUgPT09IDExMCA/IDEg
OiAwCisgICAgICAgICAgICAgICAgICAgIG9uQWN0aXZhdGVkOiBFY2xpcHNlUHJvZmlsZXMudGV4
dFNjYWxlID0gWzEwMCwxMTAsMTI1XVtpbmRleF0KKyAgICAgICAgICAgICAgICB9CisgICAgICAg
ICAgICAgICAgU3dpdGNoIHsgdGV4dDogcXNUcigiUmVkdWNlIG1vdGlvbiIpOyBjaGVja2VkOiBF
Y2xpcHNlUHJvZmlsZXMucmVkdWNlZE1vdGlvbjsgb25Ub2dnbGVkOiBFY2xpcHNlUHJvZmlsZXMu
cmVkdWNlZE1vdGlvbiA9IGNoZWNrZWQgfQorICAgICAgICAgICAgICAgIFN3aXRjaCB7IHRleHQ6
IHFzVHIoIkhpZ2hlciBjb250cmFzdCIpOyBjaGVja2VkOiBFY2xpcHNlUHJvZmlsZXMuaGlnaENv
bnRyYXN0OyBvblRvZ2dsZWQ6IEVjbGlwc2VQcm9maWxlcy5oaWdoQ29udHJhc3QgPSBjaGVja2Vk
IH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6IHFzVHIoIlRvb2xzICYgcmVjb3Zlcnki
KTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZvbnQuYm9sZDogdHJ1ZSB9CisgICAgICAgICAgICAg
ICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7
IHRleHQ6IHFzVHIoIkFsbCBzZXR0aW5ncyIpOyBpY29uU291cmNlOiAicXJjOi9yZXMvc2V0dGlu
Z3Muc3ZnIjsgb25DbGlja2VkOiBwYW5lbC5kZWZlcigic2V0dGluZ3MiKSB9CisgICAgICAgICAg
ICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJTdXBwb3J0IHJlcG9y
dCIpOyBlbmFibGVkOiAhU3lzdGVtQ29udHJvbHMuYnVzeTsgb25DbGlja2VkOiBTeXN0ZW1Db250
cm9scy5yZXF1ZXN0KCJjZW50ZXItcmVwb3J0IikgfQorICAgICAgICAgICAgICAgIH0KKyAgICAg
ICAgICAgICAgICBMYWJlbCB7IExheW91dC5maWxsV2lkdGg6IHRydWU7IHdyYXBNb2RlOiBUZXh0
LldyYXA7IHRleHQ6IHFzVHIoIlJlY292ZXJ5OiBDdHJsK0FsdCtGMiBvcGVucyB0aGUgZGlhZ25v
c3RpYyBjb25zb2xlLiBNYWMgYnJpZ2h0bmVzcywga2V5Ym9hcmQtbGlnaHQgYW5kIHZvbHVtZSBr
ZXlzIHJlbWFpbiBhdmFpbGFibGUuIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAgICAg
ICAgICAgICAgICBSb3dMYXlvdXQgeworICAgICAgICAgICAgICAgICAgICBSZXBlYXRlciB7Cisg
ICAgICAgICAgICAgICAgICAgICAgICBtb2RlbDogW3thY3Rpb246InJlYm9vdCIsbGFiZWw6cXNU
cigiUmVzdGFydCIpfSx7YWN0aW9uOiJwb3dlcm9mZiIsbGFiZWw6cXNUcigiU2h1dCBkb3duIil9
XQorICAgICAgICAgICAgICAgICAgICAgICAgZGVsZWdhdGU6IEVjbGlwc2VBY3Rpb25CdXR0b24g
eyB0ZXh0OiBtb2RlbERhdGEubGFiZWw7IGljb25Tb3VyY2U6ICJxcmM6L3Jlcy9lY2xpcHNlLXBv
d2VyLnN2ZyI7IGVuYWJsZWQ6ICFTeXN0ZW1Db250cm9scy5idXN5OyBvbkNsaWNrZWQ6IHsgcGFu
ZWwucG93ZXJBY3Rpb24gPSBtb2RlbERhdGEuYWN0aW9uOyBwb3dlckRpYWxvZy5vcGVuKCkgfSB9
CisgICAgICAgICAgICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAg
ICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6IHFzVHIoIkFib3V0IEVjbGlwc2UiKTsgZW5h
YmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogcGFuZWwuZGVmZXIoImFib3V0
IikgfQorICAgICAgICAgICAgICAgIExhYmVsIHsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgdGV4
dEZvcm1hdDogVGV4dC5QbGFpblRleHQ7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHBhbmVs
Lm1lc3NhZ2UgfHwgU3lzdGVtQ29udHJvbHMuc3RhdHVzOyBjb2xvcjogVmJUb2tlbnMudGV4dERp
bSB9CisgICAgICAgICAgICAgICAgQnVzeUluZGljYXRvciB7IHJ1bm5pbmc6IFN5c3RlbUNvbnRy
b2xzLmJ1c3k7IHZpc2libGU6IHJ1bm5pbmc7IExheW91dC5hbGlnbm1lbnQ6IFF0LkFsaWduSENl
bnRlciB9CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgTmF2aWdhYmxlRGlh
bG9nIHsKKyAgICAgICAgaWQ6IHBvd2VyRGlhbG9nCisgICAgICAgIHdpZHRoOiBNYXRoLm1pbig0
NDAsIHBhbmVsLndpZHRoIC0gMzIpCisgICAgICAgIHRpdGxlOiBwYW5lbC5wb3dlckFjdGlvbiA9
PT0gInJlYm9vdCIgPyBxc1RyKCJSZXN0YXJ0IEVjbGlwc2VPUz8iKSA6IHFzVHIoIlNodXQgZG93
biBFY2xpcHNlT1M/IikKKyAgICAgICAgc3RhbmRhcmRCdXR0b25zOiBEaWFsb2cuWWVzIHwgRGlh
bG9nLk5vCisgICAgICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnRWxldgorICAg
ICAgICBvbkFjY2VwdGVkOiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItIitwYW5lbC5w
b3dlckFjdGlvbiwiIix0cnVlKQorICAgICAgICBjb250ZW50SXRlbTogTGFiZWwgeyB0ZXh0OiBx
c1RyKCJUaGlzIGVuZHMgdGhlIGN1cnJlbnQgbG9jYWwgc2Vzc2lvbi4iKTsgY29sb3I6IFZiVG9r
ZW5zLnRleHQgfQorICAgIH0KK30KZGlmZiAtLWdpdCBhL2FwcC9ndWkvRWNsaXBzZUhhcmR3YXJl
TW9uaXRvci5xbWwgYi9hcHAvZ3VpL0VjbGlwc2VIYXJkd2FyZU1vbml0b3IucW1sCm5ldyBmaWxl
IG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmVkYmUxOTEKLS0tIC9kZXYvbnVsbAorKysgYi9h
cHAvZ3VpL0VjbGlwc2VIYXJkd2FyZU1vbml0b3IucW1sCkBAIC0wLDAgKzEsNzcgQEAKK2ltcG9y
dCBRdFF1aWNrIDIuOQoraW1wb3J0IFF0UXVpY2suQ29udHJvbHMgMi41CitpbXBvcnQgUXRRdWlj
ay5MYXlvdXRzIDEuMworaW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgTG9jYWxI
YXJkd2FyZSAxLjAKKworQ29sdW1uTGF5b3V0IHsKKyAgICBpZDogbW9uaXRvcgorICAgIG9iamVj
dE5hbWU6ImhhcmR3YXJlTW9uaXRvciIKKyAgICBwcm9wZXJ0eSBib29sIGFjdGl2ZTogZmFsc2UK
KyAgICBDb21wb25lbnQub25Db21wbGV0ZWQ6IGlmKGFjdGl2ZSkgTG9jYWxIYXJkd2FyZS5zZXRD
b25zdW1lckFjdGl2ZShtb25pdG9yLHRydWUpCisgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZQor
ICAgIG9uQWN0aXZlQ2hhbmdlZDogTG9jYWxIYXJkd2FyZS5zZXRDb25zdW1lckFjdGl2ZShtb25p
dG9yLGFjdGl2ZSkKKyAgICBDb21wb25lbnQub25EZXN0cnVjdGlvbjogTG9jYWxIYXJkd2FyZS5z
ZXRDb25zdW1lckFjdGl2ZShtb25pdG9yLGZhbHNlKQorICAgIGZ1bmN0aW9uIHJlYWRpbmcoa2V5
LCBzdWZmaXgsIGRpZ2l0cykgeyB2YXIgdj1Mb2NhbEhhcmR3YXJlLnJlYWRpbmdzW2tleV07IHJl
dHVybiB2ID09PSB1bmRlZmluZWQgPyBxc1RyKCJVbmF2YWlsYWJsZSIpIDogTnVtYmVyKHYpLnRv
Rml4ZWQoZGlnaXRzID09PSB1bmRlZmluZWQgPyAxIDogZGlnaXRzKSsoc3VmZml4IHx8ICIiKSB9
CisgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNp
emU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6IHFzVHIoIkxPQ0FMIE1BQyDigKIgSGFyZHdhcmUg
bW9uaXRvciIpOyBjb2xvcjogVmJUb2tlbnMudGV4dDsgZm9udC5ib2xkOiB0cnVlIH0KKyAgICBM
YWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRv
a2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3Jh
cDsgdGV4dDogcXNUcigiTG9jYWwgcmVhZGluZ3MgYXJlIGluZGVwZW5kZW50IG9mIHN0cmVhbSBh
bmQgaG9zdCBzdGF0aXN0aWNzLiBNaXNzaW5nIHNlbnNvcnMgc2hvdyBVbmF2YWlsYWJsZTsgZmly
c3QgQ1BVL25ldHdvcmsgcmF0ZXMgbmVlZCBhIHNlY29uZCBzYW1wbGUuIEludGVsIEdQVSBzaGFy
ZWQgbWVtb3J5IGlzIHN5c3RlbSBSQU0uIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0RGltIH0KKyAg
ICBHcmlkTGF5b3V0IHsKKyAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgY29sdW1uczog
d2lkdGggPj0gNjIwID8gMiA6IDE7IGNvbHVtblNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMzsgcm93
U3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCisgICAgICAgIFJlcGVhdGVyIHsKKyAgICAgICAgICAg
IG1vZGVsOiBbCisgICAgICAgICAgICAgICAge2xhYmVsOnFzVHIoIkNQVSIpLCBrZXk6ImNwdVBl
cmNlbnQiLHN1ZmZpeDoiJSJ9LCB7bGFiZWw6cXNUcigiQ1BVIGNsb2NrIiksa2V5OiJjcHVNSHoi
LHN1ZmZpeDoiIE1IeiJ9LAorICAgICAgICAgICAgICAgIHtsYWJlbDpxc1RyKCJNZW1vcnkgdXNl
ZCIpLGtleToibWVtb3J5VXNlZEdpQiIsc3VmZml4OiIgR2lCIn0se2xhYmVsOnFzVHIoIk1lbW9y
eSB0b3RhbCIpLGtleToibWVtb3J5VG90YWxHaUIiLHN1ZmZpeDoiIEdpQiJ9LAorICAgICAgICAg
ICAgICAgIHtsYWJlbDpxc1RyKCJDUFUgdGVtcGVyYXR1cmUiKSxrZXk6InRlbXBlcmF0dXJlQyIs
c3VmZml4OiIgwrBDIn0se2xhYmVsOnFzVHIoIkZhbiIpLGtleToiZmFuUlBNIixzdWZmaXg6IiBS
UE0ifSwKKyAgICAgICAgICAgICAgICB7bGFiZWw6cXNUcigiR1BVIGJ1c3kiKSxrZXk6ImdwdVBl
cmNlbnQiLHN1ZmZpeDoiJSJ9LHtsYWJlbDpxc1RyKCJFY2xpcHNlIHZpZGVvIGVuZ2luZSIpLGtl
eToidmlkZW9QZXJjZW50IixzdWZmaXg6IiUifSx7bGFiZWw6cXNUcigiU3dhcCB1c2VkIiksa2V5
OiJzd2FwVXNlZE1pQiIsc3VmZml4OiIgTWlCIn0sCisgICAgICAgICAgICAgICAge2xhYmVsOnFz
VHIoIk5ldHdvcmsgZG93bmxvYWQiKSxrZXk6InJlY2VpdmVNaUIiLHN1ZmZpeDoiIE1pQi9zIn0s
e2xhYmVsOnFzVHIoIk5ldHdvcmsgdXBsb2FkIiksa2V5OiJ0cmFuc21pdE1pQiIsc3VmZml4OiIg
TWlCL3MifSwKKyAgICAgICAgICAgICAgICB7bGFiZWw6cXNUcigiU3RvcmFnZSByZWFkcyIpLGtl
eToiZGlza1JlYWRNaUIiLHN1ZmZpeDoiIE1pQi9zIn0se2xhYmVsOnFzVHIoIlN0b3JhZ2Ugd3Jp
dGVzIiksa2V5OiJkaXNrV3JpdGVNaUIiLHN1ZmZpeDoiIE1pQi9zIn0sCisgICAgICAgICAgICAg
ICAge2xhYmVsOnFzVHIoIlVTQi9yb290IGZyZWUiKSxrZXk6InN0b3JhZ2VGcmVlR2lCIixzdWZm
aXg6IiBHaUIifSx7bGFiZWw6cXNUcigiQmF0dGVyeSIpLGtleToiYmF0dGVyeVBlcmNlbnQiLHN1
ZmZpeDoiJSJ9CisgICAgICAgICAgICBdCisgICAgICAgICAgICBkZWxlZ2F0ZTogQ3JpbXNvbkds
YXNzUGFuZWwgeworICAgICAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWU7IGltcGxp
Y2l0SGVpZ2h0OiA4NDsgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNDYXJkOyBjb2xvcjogVmJUb2tl
bnMuYmdFbGV2OyBib3JkZXIuY29sb3I6IFZiVG9rZW5zLnN0cm9rZQorICAgICAgICAgICAgICAg
IENvbHVtbiB7IGFuY2hvcnMuZmlsbDogcGFyZW50OyBhbmNob3JzLm1hcmdpbnM6IDEyOyBzcGFj
aW5nOiA2CisgICAgICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4dDogbW9kZWxEYXRhLmxhYmVs
OyBjb2xvcjogVmJUb2tlbnMudGV4dERpbTsgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVC
b2R5IH0KKyAgICAgICAgICAgICAgICAgICAgTGFiZWwgeyB0ZXh0OiBtb25pdG9yLnJlYWRpbmco
bW9kZWxEYXRhLmtleSxtb2RlbERhdGEuc3VmZml4KTsgY29sb3I6IFZiVG9rZW5zLnRleHQ7IGZv
bnQuYm9sZDogdHJ1ZTsgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVCb2R5IH0KKyAgICAg
ICAgICAgICAgICB9CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9CisgICAgTGFiZWwg
eyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMu
dHlwZUJvZHk7IHRleHQ6IHFzVHIoIlJlY2VudCBDUFUgYW5kIFJBTSB1c2FnZSDigKIgdXAgdG8g
NjAgc2FtcGxlcyIpOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgQ2FudmFzIHsKKyAg
ICAgICAgaWQ6IGdyYXBoOyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyBpbXBsaWNpdEhlaWdodDog
MTAwCisgICAgICAgIG9uUGFpbnQ6IHsKKyAgICAgICAgICAgIHZhciBjPWdldENvbnRleHQoIjJk
Iik7IGMuY2xlYXJSZWN0KDAsMCx3aWR0aCxoZWlnaHQpOyBjLmZpbGxTdHlsZT1WYlRva2Vucy5i
Z0VsZXY7IGMuZmlsbFJlY3QoMCwwLHdpZHRoLGhlaWdodCkKKyAgICAgICAgICAgIHZhciBrZXlz
PVsiY3B1UGVyY2VudCIsIm1lbW9yeVBlcmNlbnQiXSwgY29sb3JzPVtWYlRva2Vucy5hY2NlbnQs
VmJUb2tlbnMudGV4dERpbV0sIGg9TG9jYWxIYXJkd2FyZS5oaXN0b3J5CisgICAgICAgICAgICBm
b3IodmFyIGs9MDtrPGtleXMubGVuZ3RoO2srKykgeyBjLnN0cm9rZVN0eWxlPWNvbG9yc1trXTsg
Yy5saW5lV2lkdGg9MjsgYy5iZWdpblBhdGgoKTsgdmFyIHN0YXJ0ZWQ9ZmFsc2UKKyAgICAgICAg
ICAgICAgICBmb3IodmFyIGk9MDtpPGgubGVuZ3RoO2krKykgeyB2YXIgdj1oW2ldW2tleXNba11d
OyBpZih2PT09dW5kZWZpbmVkKSB7IHN0YXJ0ZWQ9ZmFsc2U7IGNvbnRpbnVlIH0KKyAgICAgICAg
ICAgICAgICAgICAgdmFyIHg9d2lkdGgqaS81OSwgeT1oZWlnaHQtNC0oaGVpZ2h0LTgpKk1hdGgu
bWF4KDAsTWF0aC5taW4oMTAwLHYpKS8xMDAKKyAgICAgICAgICAgICAgICAgICAgaWYoIXN0YXJ0
ZWQpIGMubW92ZVRvKHgseSk7IGVsc2UgYy5saW5lVG8oeCx5KTsgc3RhcnRlZD10cnVlIH0KKyAg
ICAgICAgICAgICAgICBjLnN0cm9rZSgpIH0KKyAgICAgICAgfQorICAgICAgICBDb25uZWN0aW9u
cyB7IHRhcmdldDogTG9jYWxIYXJkd2FyZTsgZnVuY3Rpb24gb25DaGFuZ2VkKCkgeyBncmFwaC5y
ZXF1ZXN0UGFpbnQoKSB9IH0KKyAgICAgICAgQ29ubmVjdGlvbnMgeyB0YXJnZXQ6IFZiVG9rZW5z
OyBmdW5jdGlvbiBvbkFjY2VudENoYW5nZWQoKSB7IGdyYXBoLnJlcXVlc3RQYWludCgpIH0gfQor
ICAgIH0KKyAgICBDaGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250
LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigiU2hvdyBsb2NhbCBoYXJk
d2FyZSBvdmVybGF5IGR1cmluZyBzdHJlYW1pbmciKTsgY2hlY2tlZDogTG9jYWxIYXJkd2FyZS5v
dmVybGF5OyBvblRvZ2dsZWQ6IExvY2FsSGFyZHdhcmUub3ZlcmxheT1jaGVja2VkIH0KKyAgICBD
aGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpW
YlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigiRGV0YWlsZWQgbG9jYWwgb3ZlcmxheSIpOyBj
aGVja2VkOiBMb2NhbEhhcmR3YXJlLmRldGFpbGVkOyBvblRvZ2dsZWQ6IExvY2FsSGFyZHdhcmUu
ZGV0YWlsZWQ9Y2hlY2tlZCB9CisgICAgQ2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vucy5m
b250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6IHFzVHIoIkRl
dGFpbGVkIHN0cmVhbSBzdGF0aXN0aWNzIik7IGNoZWNrZWQ6IExvY2FsSGFyZHdhcmUuc3RyZWFt
RGV0YWlsZWQ7IG9uVG9nZ2xlZDogTG9jYWxIYXJkd2FyZS5zdHJlYW1EZXRhaWxlZD1jaGVja2Vk
IH0KKyAgICBSb3dMYXlvdXQgeworICAgICAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5z
LmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDogcXNUcigi
TG9jYWwgb3ZlcmxheSBjb3JuZXIiKTsgY29sb3I6IFZiVG9rZW5zLnRleHQgfQorICAgICAgICBF
Y2xpcHNlQ29tYm9Cb3ggeyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7IG1vZGVsOltxc1RyKCJUb3Ag
bGVmdCIpLHFzVHIoIlRvcCByaWdodCIpLHFzVHIoIkJvdHRvbSBsZWZ0IikscXNUcigiQm90dG9t
IHJpZ2h0IildOyBjdXJyZW50SW5kZXg6TG9jYWxIYXJkd2FyZS5wb3NpdGlvbjsgb25BY3RpdmF0
ZWQ6TG9jYWxIYXJkd2FyZS5wb3NpdGlvbj1pbmRleCB9CisgICAgfQorICAgIExhYmVsIHsgZm9u
dC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVC
b2R5OyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7IHdyYXBNb2RlOlRleHQuV3JhcDsgdGV4dDpxc1Ry
KCJJZiBib3RoIG92ZXJsYXlzIHVzZSB0aGUgc2FtZSBjb3JuZXIsIExvY2FsIE1hYyBtb3ZlcyB0
byB0aGUgb3Bwb3NpdGUgaG9yaXpvbnRhbCBjb3JuZXIuIFN0cmVhbWluZyBzaG9ydGN1dHM6IEN0
cmwrQWx0K1NoaWZ0K1MgZm9yIHN0cmVhbSBzdGF0czsgQ3RybCtBbHQrU2hpZnQrSCBmb3IgbG9j
YWwgaGFyZHdhcmUuIFN0cmVhbSB0ZXh0IHNpemUgYW5kIGNvcm5lciByZW1haW4gaW4gVmlkZW8g
c2V0dGluZ3MuIik7IGNvbG9yOlZiVG9rZW5zLnRleHREaW0gfQorICAgIFJvd0xheW91dCB7Cisg
ICAgICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxT
aXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIlBhbmVsIG9wYWNpdHkiKTsgY29sb3I6
VmJUb2tlbnMudGV4dCB9CisgICAgICAgIFNsaWRlciB7IExheW91dC5maWxsV2lkdGg6dHJ1ZTsg
ZnJvbTo0MDt0bzoxMDA7c3RlcFNpemU6NTt2YWx1ZTpMb2NhbEhhcmR3YXJlLm9wYWNpdHk7IG9u
TW92ZWQ6TG9jYWxIYXJkd2FyZS5vcGFjaXR5PU1hdGgucm91bmQodmFsdWUpIH0KKyAgICB9Cisg
ICAgUm93TGF5b3V0IHsKKyAgICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250
Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiUmVmcmVz
aCBpbnRlcnZhbCIpO2NvbG9yOlZiVG9rZW5zLnRleHQgfQorICAgICAgICBFY2xpcHNlQ29tYm9C
b3ggeyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7IG1vZGVsOlsiMSBzZWNvbmQiLCIyIHNlY29uZHMi
LCI1IHNlY29uZHMiXTsgY3VycmVudEluZGV4OkxvY2FsSGFyZHdhcmUucmVmcmVzaFNlY29uZHM9
PT0xPzA6TG9jYWxIYXJkd2FyZS5yZWZyZXNoU2Vjb25kcz09PTU/MjoxOyBvbkFjdGl2YXRlZDpM
b2NhbEhhcmR3YXJlLnJlZnJlc2hTZWNvbmRzPVsxLDIsNV1baW5kZXhdIH0KKyAgICB9CisgICAg
RmxvdyB7CisgICAgICAgIExheW91dC5maWxsV2lkdGg6dHJ1ZQorICAgICAgICBSZXBlYXRlciB7
IG1vZGVsOlsiY3B1IiwibWVtb3J5IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3JrIiwiYmF0
dGVyeSIsInN0b3JhZ2UiXQorICAgICAgICAgICAgZGVsZWdhdGU6Q2hlY2tCb3ggeyBmb250LmZh
bWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7
IHRleHQ6bW9kZWxEYXRhOyBjaGVja2VkOkxvY2FsSGFyZHdhcmUuZmllbGRzLmluZGV4T2YobW9k
ZWxEYXRhKT49MDsgb25Ub2dnbGVkOnt2YXIgZj1Mb2NhbEhhcmR3YXJlLmZpZWxkcy5zbGljZSgp
O3ZhciBpPWYuaW5kZXhPZihtb2RlbERhdGEpO2lmKGNoZWNrZWQmJmk8MClmLnB1c2gobW9kZWxE
YXRhKTtpZighY2hlY2tlZCYmaT49MClmLnNwbGljZShpLDEpO0xvY2FsSGFyZHdhcmUuZmllbGRz
PWZ9IH0KKyAgICAgICAgfQorICAgIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5z
LmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxX
aWR0aDp0cnVlO3dyYXBNb2RlOlRleHQuV3JhcDt0ZXh0OnFzVHIoIkVjbGlwc2UgdmlkZW8tZW5n
aW5lIGFjdGl2aXR5IHVzZXMgdGhpcyBwcm9jZXNz4oCZcyBEUk0gY291bnRlcnMgd2hlbiBleHBv
c2VkLiBJdCBpcyBub3Qgd2hvbGUtc3lzdGVtIEdQVSBsb2FkLiBQZXItcHJvY2VzcyBHUFUgbWVt
b3J5IGlzIHVuYXZhaWxhYmxlLiBTdG9yYWdlIHJhdGVzIHJlZmxlY3QgdGhlIGFjdGl2ZSByb290
IGRldmljZSB3aGVuIGFjY2Vzc2libGUuIE5vIHByaXZpbGVnZWQgR1BVIHByb2ZpbGVyIHJ1bnMg
Y29udGludW91c2x5LiIpO2NvbG9yOlZiVG9rZW5zLnRleHREaW0gfQorfQpkaWZmIC0tZ2l0IGEv
YXBwL2d1aS9FY2xpcHNlU3lzdGVtU2V0dGluZ3MucW1sIGIvYXBwL2d1aS9FY2xpcHNlU3lzdGVt
U2V0dGluZ3MucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjVkMmJiYzkK
LS0tIC9kZXYvbnVsbAorKysgYi9hcHAvZ3VpL0VjbGlwc2VTeXN0ZW1TZXR0aW5ncy5xbWwKQEAg
LTAsMCArMSw4MyBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9s
cyAyLjUKK2ltcG9ydCBRdFF1aWNrLkxheW91dHMgMS4zCitpbXBvcnQgUXRRdWljay5Db250cm9s
cy5NYXRlcmlhbCAyLjIKK2ltcG9ydCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IFN5c3Rl
bUNvbnRyb2xzIDEuMAoraW1wb3J0IExvY2FsSGFyZHdhcmUgMS4wCisKK0NvbHVtbkxheW91dCB7
CisgICAgaWQ6IHN5c3RlbQorICAgIHByb3BlcnR5IGJvb2wgYWN0aXZlOiBmYWxzZQorICAgIHBy
b3BlcnR5IHN0cmluZyBwb3dlckFjdGlvbjogIiIKKyAgICBwcm9wZXJ0eSB2YXIgcG9pbnRlcjog
cG9pbnRlckNob2ljZS5jdXJyZW50SW5kZXggPj0gMCA/IChTeXN0ZW1Db250cm9scy5zdGF0ZS5w
b2ludGVycyB8fCBbXSlbcG9pbnRlckNob2ljZS5jdXJyZW50SW5kZXhdIHx8ICh7fSkgOiAoe30p
CisgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UzCisgICAgb25BY3RpdmVDaGFuZ2VkOiB7IGlm
KGFjdGl2ZSkgU3lzdGVtQ29udHJvbHMub3BlbigiY2VudGVyIik7IGVsc2UgU3lzdGVtQ29udHJv
bHMuY2xvc2UoKSB9CisgICAgQ29tcG9uZW50Lm9uRGVzdHJ1Y3Rpb246IHsgaWYoYWN0aXZlKSBT
eXN0ZW1Db250cm9scy5jbG9zZSgpIH0KKyAgICBmdW5jdGlvbiByZXF1ZXN0KGFjdGlvbix2YWx1
ZSkgeyBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KCJjZW50ZXItIithY3Rpb24sdmFsdWUgfHwgIiIp
IH0KKyAgICBmdW5jdGlvbiBzaG93Q29ubmVjdGlvbnMoa2luZCkgeyBTeXN0ZW1Db250cm9scy5j
bG9zZSgpOyBjb25uZWN0aW9ucy5raW5kPWtpbmQ7IGNvbm5lY3Rpb25zLm9wZW4oKSB9CisgICAg
TGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJU
b2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7
dGV4dDpxc1RyKCJFY2xpcHNlT1Mg4oCiIFN5c3RlbSBDb250cm9scyIpO2NvbG9yOlZiVG9rZW5z
LnRleHQ7Zm9udC5ib2xkOnRydWUgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMu
Zm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdp
ZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5XcmFwO3RleHQ6U3lzdGVtQ29udHJvbHMuc3RhdHVzO2Nv
bG9yOlZiVG9rZW5zLnRleHREaW07dGV4dEZvcm1hdDpUZXh0LlBsYWluVGV4dCB9CisgICAgQnVz
eUluZGljYXRvciB7IHJ1bm5pbmc6c3lzdGVtLmFjdGl2ZSAmJiBTeXN0ZW1Db250cm9scy5idXN5
O3Zpc2libGU6cnVubmluZztMYXlvdXQuYWxpZ25tZW50OlF0LkFsaWduSENlbnRlciB9CisgICAg
Um93TGF5b3V0IHsKKyAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDp0cnVlCisgICAgICAgIEVjbGlw
c2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIldpLUZpIG5ldHdvcmtzIik7aWNvblNvdXJjZToi
cXJjOi9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZyI7b25DbGlja2VkOnN5c3RlbS5zaG93Q29ubmVj
dGlvbnMoIndpZmkiKSB9CisgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIo
IkJsdWV0b290aCBkZXZpY2VzIik7aWNvblNvdXJjZToicXJjOi9yZXMvY3JpbXNvbi1ibHVldG9v
dGguc3ZnIjtvbkNsaWNrZWQ6c3lzdGVtLnNob3dDb25uZWN0aW9ucygiYnQiKSB9CisgICAgfQor
ICAgIFJvd0xheW91dCB7CisgICAgICAgIENoZWNrQm94IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMu
Zm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIldp
LUZpIHJhZGlvIik7Y2hlY2tlZDpTeXN0ZW1Db250cm9scy5zdGF0ZS53aWZpX2VuYWJsZWQ9PT10
cnVlO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3kgJiYgU3lzdGVtQ29udHJvbHMuc3RhdGUu
d2lmaV9lbmFibGVkIT09bnVsbCAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS53aWZpX2VuYWJsZWQh
PT11bmRlZmluZWQ7b25Ub2dnbGVkOnN5c3RlbS5yZXF1ZXN0KCJ3aWZpLXJhZGlvIixjaGVja2Vk
PyJvbiI6Im9mZiIpIH0KKyAgICAgICAgQ2hlY2tCb3ggeyBmb250LmZhbWlseTpWYlRva2Vucy5m
b250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IHRleHQ6cXNUcigiQmx1
ZXRvb3RoIHJhZGlvIik7Y2hlY2tlZDpTeXN0ZW1Db250cm9scy5zdGF0ZS5ibHVldG9vdGhfZW5h
YmxlZD09PXRydWU7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeSAmJiBTeXN0ZW1Db250cm9s
cy5zdGF0ZS5ibHVldG9vdGhfZW5hYmxlZCE9PW51bGwgJiYgU3lzdGVtQ29udHJvbHMuc3RhdGUu
Ymx1ZXRvb3RoX2VuYWJsZWQhPT11bmRlZmluZWQ7b25Ub2dnbGVkOnN5c3RlbS5yZXF1ZXN0KCJi
dC1yYWRpbyIsY2hlY2tlZD8ib24iOiJvZmYiKSB9CisgICAgfQorICAgIExhYmVsIHsgZm9udC5m
YW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5
OyB0ZXh0OnFzVHIoIkF1ZGlvIGFuZCBicmlnaHRuZXNzIik7Y29sb3I6VmJUb2tlbnMudGV4dDtm
b250LmJvbGQ6dHJ1ZSB9CisgICAgUm93TGF5b3V0IHsKKyAgICAgICAgTGF5b3V0LmZpbGxXaWR0
aDp0cnVlCisgICAgICAgIFNsaWRlciB7IGlkOnZvbHVtZTtMYXlvdXQuZmlsbFdpZHRoOnRydWU7
ZnJvbTowO3RvOjEwMDtzdGVwU2l6ZToxO3ZhbHVlOlN5c3RlbUNvbnRyb2xzLnN0YXRlLnZvbHVt
ZSB8fCAwO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3kgJiYgU3lzdGVtQ29udHJvbHMuc3Rh
dGUudm9sdW1lIT09bnVsbCAmJiBTeXN0ZW1Db250cm9scy5zdGF0ZS52b2x1bWUhPT11bmRlZmlu
ZWQ7QWNjZXNzaWJsZS5uYW1lOnFzVHIoIlNwZWFrZXIgdm9sdW1lIik7b25QcmVzc2VkQ2hhbmdl
ZDppZighcHJlc3NlZCYmZW5hYmxlZClzeXN0ZW0ucmVxdWVzdCgidm9sdW1lIixTdHJpbmcoTWF0
aC5yb3VuZCh2YWx1ZSkpKTtvbk1vdmVkOmlmKCFwcmVzc2VkJiZlbmFibGVkKXN5c3RlbS5yZXF1
ZXN0KCJ2b2x1bWUiLFN0cmluZyhNYXRoLnJvdW5kKHZhbHVlKSkpIH0KKyAgICAgICAgTGFiZWwg
eyBmb250LmZhbWlseTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMu
dHlwZUJvZHk7IHRleHQ6TWF0aC5yb3VuZCh2b2x1bWUudmFsdWUpKyIlIjtjb2xvcjpWYlRva2Vu
cy50ZXh0IH0KKyAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6U3lzdGVtQ29udHJv
bHMuc3RhdGUubXV0ZWQ/cXNUcigiVW5tdXRlIik6cXNUcigiTXV0ZSIpO2VuYWJsZWQ6dm9sdW1l
LmVuYWJsZWQ7b25DbGlja2VkOnN5c3RlbS5yZXF1ZXN0KCJtdXRlIikgfQorICAgIH0KKyAgICBF
Y2xpcHNlQ29tYm9Cb3ggeyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7bW9kZWw6U3lzdGVtQ29udHJv
bHMuc3RhdGUuc2lua3MgfHwgW107dGV4dFJvbGU6Im5hbWUiO2VuYWJsZWQ6IVN5c3RlbUNvbnRy
b2xzLmJ1c3kgJiYgY291bnQ+MDtBY2Nlc3NpYmxlLm5hbWU6cXNUcigiQXVkaW8gb3V0cHV0Iik7
Y3VycmVudEluZGV4Ont2YXIgYT1TeXN0ZW1Db250cm9scy5zdGF0ZS5zaW5rcyB8fCBbXTtmb3Io
dmFyIGk9MDtpPGEubGVuZ3RoO2krKylpZihhW2ldLmRlZmF1bHQpcmV0dXJuIGk7cmV0dXJuIC0x
fQorICAgICAgICBvbkFjdGl2YXRlZDpzeXN0ZW0ucmVxdWVzdCgib3V0cHV0Iixtb2RlbFtpbmRl
eF0uaWQpIH0KKyAgICBSb3dMYXlvdXQgeworICAgICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsg
dGV4dDpxc1RyKCJUZXN0IHNvdW5kIik7ZW5hYmxlZDp2b2x1bWUuZW5hYmxlZDtvbkNsaWNrZWQ6
c3lzdGVtLnJlcXVlc3QoInRlc3Qtc291bmQiKSB9CisgICAgICAgIEVjbGlwc2VDb21ib0JveCB7
IExheW91dC5maWxsV2lkdGg6dHJ1ZTsgbW9kZWw6W3FzVHIoIkFpclBvZHM6IExvdyBsYXRlbmN5
IikscXNUcigiQWlyUG9kczogUXVhbGl0eSIpXTtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5
O29uQWN0aXZhdGVkOnN5c3RlbS5yZXF1ZXN0KCJhaXJwb2RzIixpbmRleD09PTA/Imxvdy1sYXRl
bmN5IjoicXVhbGl0eSIpIH0KKyAgICB9CisgICAgUmVwZWF0ZXIgeworICAgICAgICBtb2RlbDpb
e2tpbmQ6InNjcmVlbiIsbGFiZWw6cXNUcigiU2NyZWVuIGJyaWdodG5lc3MiKX0se2tpbmQ6Imtl
eWJvYXJkIixsYWJlbDpxc1RyKCJLZXlib2FyZCBsaWdodGluZyIpfV0KKyAgICAgICAgZGVsZWdh
dGU6Q29sdW1uTGF5b3V0IHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6dHJ1ZQorICAg
ICAgICAgICAgcHJvcGVydHkgdmFyIGhhcmR3YXJlOihTeXN0ZW1Db250cm9scy5zdGF0ZS5icmln
aHRuZXNzIHx8IHt9KVttb2RlbERhdGEua2luZF0KKyAgICAgICAgICAgIExhYmVsIHsgZm9udC5m
YW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5
OyB0ZXh0Om1vZGVsRGF0YS5sYWJlbCsoaGFyZHdhcmU/IiDigKIgIitoYXJkd2FyZS5wZXJjZW50
KyIlIjoiIOKAoiAiK3FzVHIoIlVuYXZhaWxhYmxlIikpO2NvbG9yOlZiVG9rZW5zLnRleHQgfQor
ICAgICAgICAgICAgU2xpZGVyIHsgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO2Zyb206bW9kZWxEYXRh
LmtpbmQ9PT0ic2NyZWVuIj81OjA7dG86MTAwO3N0ZXBTaXplOjE7ZW5hYmxlZDohIWhhcmR3YXJl
JiYhU3lzdGVtQ29udHJvbHMuYnVzeTt2YWx1ZTpoYXJkd2FyZT9oYXJkd2FyZS5wZXJjZW50OjA7
QWNjZXNzaWJsZS5uYW1lOm1vZGVsRGF0YS5sYWJlbDtvblByZXNzZWRDaGFuZ2VkOmlmKCFwcmVz
c2VkJiZlbmFibGVkKXN5c3RlbS5yZXF1ZXN0KG1vZGVsRGF0YS5raW5kLFN0cmluZyhNYXRoLnJv
dW5kKHZhbHVlKSkpO29uTW92ZWQ6aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3Qo
bW9kZWxEYXRhLmtpbmQsU3RyaW5nKE1hdGgucm91bmQodmFsdWUpKSkgfQorICAgICAgICB9Cisg
ICAgfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4
ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIkRpc3BsYXkgYW5kIGlkbGUgYmxh
bmtpbmciKTtjb2xvcjpWYlRva2Vucy50ZXh0O2ZvbnQuYm9sZDp0cnVlIH0KKyAgICBFY2xpcHNl
Q29tYm9Cb3ggeyBpZDptb2RlQ2hvaWNlO0xheW91dC5maWxsV2lkdGg6dHJ1ZTttb2RlbDpTeXN0
ZW1Db250cm9scy5zdGF0ZS5kaXNwbGF5cyB8fCBbXTt0ZXh0Um9sZToibmFtZSI7ZW5hYmxlZDoh
U3lzdGVtQ29udHJvbHMuYnVzeSAmJiBjb3VudD4wO0FjY2Vzc2libGUubmFtZTpxc1RyKCJEaXNw
bGF5IHJlc29sdXRpb24gYW5kIHJlZnJlc2ggcmF0ZSIpO2N1cnJlbnRJbmRleDp7dmFyIGE9U3lz
dGVtQ29udHJvbHMuc3RhdGUuZGlzcGxheXMgfHwgW107Zm9yKHZhciBpPTA7aTxhLmxlbmd0aDtp
KyspaWYoYVtpXS5jdXJyZW50KXJldHVybiBpO3JldHVybiAtMX0gfQorICAgIEVjbGlwc2VBY3Rp
b25CdXR0b24geyB0ZXh0OnFzVHIoIkFwcGx5IGRpc3BsYXkgbW9kZSDigKIgMTUtc2Vjb25kIHJv
bGxiYWNrIik7ZW5hYmxlZDptb2RlQ2hvaWNlLmVuYWJsZWQmJm1vZGVDaG9pY2UuY3VycmVudElu
ZGV4Pj0wO29uQ2xpY2tlZDpzeXN0ZW0ucmVxdWVzdCgiZGlzcGxheSIsbW9kZUNob2ljZS5tb2Rl
bFttb2RlQ2hvaWNlLmN1cnJlbnRJbmRleF0uaWQpIH0KKyAgICBFY2xpcHNlQ29tYm9Cb3ggeyBM
YXlvdXQuZmlsbFdpZHRoOnRydWU7IG1vZGVsOltxc1RyKCJOZXZlciBibGFuayIpLHFzVHIoIkJs
YW5rIGFmdGVyIDUgbWludXRlcyIpLHFzVHIoIkJsYW5rIGFmdGVyIDEwIG1pbnV0ZXMiKSxxc1Ry
KCJCbGFuayBhZnRlciAzMCBtaW51dGVzIildO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3k7
b25BY3RpdmF0ZWQ6c3lzdGVtLnJlcXVlc3QoImlkbGUiLFsiMCIsIjMwMCIsIjYwMCIsIjE4MDAi
XVtpbmRleF0pIH0KKyAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBm
b250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dDpxc1RyKCJQb2ludGVyIGFuZCB0
cmFja3BhZCIpO2NvbG9yOlZiVG9rZW5zLnRleHQ7Zm9udC5ib2xkOnRydWUgfQorICAgIEVjbGlw
c2VDb21ib0JveCB7IGlkOnBvaW50ZXJDaG9pY2U7TGF5b3V0LmZpbGxXaWR0aDp0cnVlO21vZGVs
OlN5c3RlbUNvbnRyb2xzLnN0YXRlLnBvaW50ZXJzIHx8IFtdO3RleHRSb2xlOiJuYW1lIjtlbmFi
bGVkOmNvdW50PjAmJiFTeXN0ZW1Db250cm9scy5idXN5O0FjY2Vzc2libGUubmFtZTpxc1RyKCJQ
b2ludGVyIGRldmljZSIpIH0KKyAgICBTbGlkZXIgeyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7ZnJv
bTotMTt0bzoxO3N0ZXBTaXplOi4wNTt2YWx1ZTpzeXN0ZW0ucG9pbnRlci5zcGVlZCB8fCAwO2Vu
YWJsZWQ6c3lzdGVtLnBvaW50ZXIuc3BlZWQhPT11bmRlZmluZWQmJiFTeXN0ZW1Db250cm9scy5i
dXN5O0FjY2Vzc2libGUubmFtZTpxc1RyKCJQb2ludGVyIGFjY2VsZXJhdGlvbiBzcGVlZCIpO29u
UHJlc3NlZENoYW5nZWQ6aWYoIXByZXNzZWQmJmVuYWJsZWQpc3lzdGVtLnJlcXVlc3QoInBvaW50
ZXItc3BlZWQiLHN5c3RlbS5wb2ludGVyLmlkKyI6Iit2YWx1ZS50b0ZpeGVkKDIpKTtvbk1vdmVk
OmlmKCFwcmVzc2VkJiZlbmFibGVkKXN5c3RlbS5yZXF1ZXN0KCJwb2ludGVyLXNwZWVkIixzeXN0
ZW0ucG9pbnRlci5pZCsiOiIrdmFsdWUudG9GaXhlZCgyKSkgfQorICAgIENoZWNrQm94IHsgZm9u
dC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVC
b2R5OyB0ZXh0OnFzVHIoIk5hdHVyYWwgc2Nyb2xsaW5nIik7Y2hlY2tlZDpzeXN0ZW0ucG9pbnRl
ci5uYXR1cmFsPT09MTtlbmFibGVkOnN5c3RlbS5wb2ludGVyLm5hdHVyYWwhPT11bmRlZmluZWQm
JiFTeXN0ZW1Db250cm9scy5idXN5O29uVG9nZ2xlZDpzeXN0ZW0ucmVxdWVzdCgicG9pbnRlci1u
YXR1cmFsIixzeXN0ZW0ucG9pbnRlci5pZCsiOiIrKGNoZWNrZWQ/IjEiOiIwIikpIH0KKyAgICBD
aGVja0JveCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpW
YlRva2Vucy50eXBlQm9keTsgdGV4dDpxc1RyKCJUYXAgdG8gY2xpY2siKTtjaGVja2VkOnN5c3Rl
bS5wb2ludGVyLnRhcD09PTE7ZW5hYmxlZDpzeXN0ZW0ucG9pbnRlci50YXAhPT11bmRlZmluZWQm
JiFTeXN0ZW1Db250cm9scy5idXN5O29uVG9nZ2xlZDpzeXN0ZW0ucmVxdWVzdCgicG9pbnRlci10
YXAiLHN5c3RlbS5wb2ludGVyLmlkKyI6IisoY2hlY2tlZD8iMSI6IjAiKSkgfQorICAgIExhYmVs
IHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5z
LnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRoOnRydWU7d3JhcE1vZGU6VGV4dC5XcmFwO3RleHQ6
cXNUcigiUG9pbnRlciBhbmQgYmxhbmtpbmcgY2hhbmdlcyBjdXJyZW50bHkgYXBwbHkgdG8gdGhp
cyBYMTEgc2Vzc2lvbi4gVW5zdXBwb3J0ZWQgZGV2aWNlIGNvbnRyb2xzIGFyZSBkaXNhYmxlZC4g
RGlzcGxheSBjaGFuZ2VzIHJldmVydCB1bmxlc3MgY29uZmlybWVkLiIpO2NvbG9yOlZiVG9rZW5z
LnRleHREaW0gfQorICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZv
bnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyB0ZXh0OnFzVHIoIlJlY292ZXJ5IGFuZCBw
b3dlciIpO2NvbG9yOlZiVG9rZW5zLnRleHQ7Zm9udC5ib2xkOnRydWUgfQorICAgIEVjbGlwc2VD
b21ib0JveCB7IGlkOmZyb250ZW5kO21vZGVsOlsiRWNsaXBzZSIsIkFydGVtaXMiLCJQZWdhc3Vz
IiwiTW9vbmxpZ2h0IiwiQ29jb09TIl07QWNjZXNzaWJsZS5uYW1lOnFzVHIoIkZyb250ZW5kIGZv
ciBuZXh0IGJvb3QiKSB9CisgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiU2F2
ZSBmcm9udGVuZCBmb3IgbmV4dCBib290Iik7ZW5hYmxlZDohU3lzdGVtQ29udHJvbHMuYnVzeTtv
bkNsaWNrZWQ6c3lzdGVtLnJlcXVlc3QoImZyb250ZW5kIixbInZpYmVtaXMiLCJhcnRlbWlzIiwi
cGVnYXN1cyIsIm1vb25saWdodCIsImNvY29vcyJdW2Zyb250ZW5kLmN1cnJlbnRJbmRleF0pIH0K
KyAgICBGbG93IHsKKyAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDp0cnVlO3NwYWNpbmc6VmJUb2tl
bnMuc3BhY2UyCisgICAgICAgIFJlcGVhdGVyIHsgbW9kZWw6W3tuYW1lOnFzVHIoIlJlc3RhcnQg
ZnJvbnRlbmQiKSxhY3Rpb246InJlc3RhcnQtZnJvbnRlbmQifSx7bmFtZTpxc1RyKCJSZXN0YXJ0
IEVjbGlwc2VPUyIpLGFjdGlvbjoicmVib290In0se25hbWU6cXNUcigiU2h1dCBkb3duIiksYWN0
aW9uOiJwb3dlcm9mZiJ9XQorICAgICAgICAgICAgZGVsZWdhdGU6RWNsaXBzZUFjdGlvbkJ1dHRv
biB7IHRleHQ6bW9kZWxEYXRhLm5hbWU7aWNvblNvdXJjZToicXJjOi9yZXMvZWNsaXBzZS1wb3dl
ci5zdmciO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25DbGlja2VkOntzeXN0ZW0ucG93
ZXJBY3Rpb249bW9kZWxEYXRhLmFjdGlvbjtwb3dlci5vcGVuKCl9IH0KKyAgICAgICAgfQorICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsgdGV4dDpxc1RyKCJSZWRhY3RlZCBzdXBwb3J0IHJl
cG9ydCIpO2VuYWJsZWQ6IVN5c3RlbUNvbnRyb2xzLmJ1c3k7b25DbGlja2VkOnN5c3RlbS5yZXF1
ZXN0KCJyZXBvcnQiKSB9CisgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIo
IlJlZnJlc2ggY29udHJvbHMiKTtlbmFibGVkOiFTeXN0ZW1Db250cm9scy5idXN5O29uQ2xpY2tl
ZDpzeXN0ZW0ucmVxdWVzdCgibGlzdCIpIH0KKyAgICB9CisgICAgTGFiZWwgeyBmb250LmZhbWls
eTpWYlRva2Vucy5mb250Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExh
eW91dC5maWxsV2lkdGg6dHJ1ZTt3cmFwTW9kZTpUZXh0LldyYXA7dGV4dDpxc1RyKCJTdXNwZW5k
IGFuZCBsaWQgcHJlc2V0cyBhd2FpdCBwaHlzaWNhbCB2YWxpZGF0aW9uLiBSZWNvdmVyeSBjb25z
b2xlOiBDb250cm9sICsgT3B0aW9uICsgRjIgKEZuIGlmIG5lZWRlZCkuIik7Y29sb3I6VmJUb2tl
bnMudGV4dERpbSB9CisgICAgRWNsaXBzZUhhcmR3YXJlTW9uaXRvciB7IExheW91dC5maWxsV2lk
dGg6dHJ1ZTthY3RpdmU6c3lzdGVtLmFjdGl2ZSB9CisgICAgU3lzdGVtQ29ubmVjdGlvbnNEaWFs
b2cgeyBpZDpjb25uZWN0aW9ucztwYXJlbnQ6T3ZlcmxheS5vdmVybGF5O29uQ2xvc2VkOmlmKHN5
c3RlbS5hY3RpdmUpcmVzdW1lLnJlc3RhcnQoKSB9CisgICAgVGltZXIgeyBpZDpyZXN1bWU7aW50
ZXJ2YWw6NjAwO29uVHJpZ2dlcmVkOmlmKHN5c3RlbS5hY3RpdmUpU3lzdGVtQ29udHJvbHMub3Bl
bigiY2VudGVyIikgfQorICAgIE5hdmlnYWJsZURpYWxvZyB7IGlkOnBvd2VyO3BhcmVudDpPdmVy
bGF5Lm92ZXJsYXk7d2lkdGg6TWF0aC5taW4oNDQwLHBhcmVudC53aWR0aC0zMik7dGl0bGU6cXNU
cigiQ29uZmlybSBzeXN0ZW0gYWN0aW9uIik7c3RhbmRhcmRCdXR0b25zOkRpYWxvZy5ZZXN8RGlh
bG9nLk5vO2JhY2tncm91bmQ6UmVjdGFuZ2xle2NvbG9yOlZiVG9rZW5zLmJnRWxldjtyYWRpdXM6
VmJUb2tlbnMucmFkaXVzRGlhbG9nO2JvcmRlci5jb2xvcjpWYlRva2Vucy5zdHJva2V9CisgICAg
ICAgIG9uQWNjZXB0ZWQ6U3lzdGVtQ29udHJvbHMucmVxdWVzdCgiY2VudGVyLSIrc3lzdGVtLnBv
d2VyQWN0aW9uLCIiLHRydWUpO2NvbnRlbnRJdGVtOkxhYmVse3dyYXBNb2RlOlRleHQuV3JhcDt0
ZXh0OnFzVHIoIlByb2NlZWQgd2l0aCAlMT8gQWN0aXZlIHN0cmVhbWluZyB3aWxsIGVuZC4iKS5h
cmcoc3lzdGVtLnBvd2VyQWN0aW9uKTtjb2xvcjpWYlRva2Vucy50ZXh0fSB9CisgICAgTmF2aWdh
YmxlRGlhbG9nIHsgaWQ6Y29uZmlybWF0aW9uO3BhcmVudDpPdmVybGF5Lm92ZXJsYXk7d2lkdGg6
TWF0aC5taW4oNDgwLHBhcmVudC53aWR0aC0zMik7dGl0bGU6cXNUcigiS2VlcCBkaXNwbGF5IG1v
ZGU/Iik7c3RhbmRhcmRCdXR0b25zOkRpYWxvZy5ZZXN8RGlhbG9nLk5vO2Nsb3NlUG9saWN5OlBv
cHVwLk5vQXV0b0Nsb3NlO2JhY2tncm91bmQ6UmVjdGFuZ2xle2NvbG9yOlZiVG9rZW5zLmJnRWxl
djtyYWRpdXM6VmJUb2tlbnMucmFkaXVzRGlhbG9nO2JvcmRlci5jb2xvcjpWYlRva2Vucy5zdHJv
a2V9CisgICAgICAgIG9uQWNjZXB0ZWQ6U3lzdGVtQ29udHJvbHMuYW5zd2VyKCJ5ZXMiKTtvblJl
amVjdGVkOlN5c3RlbUNvbnRyb2xzLmFuc3dlcigibm8iKTtjb250ZW50SXRlbTpMYWJlbHt3cmFw
TW9kZTpUZXh0LldyYXA7dGV4dDpTeXN0ZW1Db250cm9scy5wcm9tcHQ7Y29sb3I6VmJUb2tlbnMu
dGV4dH0gfQorICAgIENvbm5lY3Rpb25zIHsgdGFyZ2V0OlN5c3RlbUNvbnRyb2xzO2Z1bmN0aW9u
IG9uQ2hhbmdlZCgpe2lmKHN5c3RlbS5hY3RpdmUmJlN5c3RlbUNvbnRyb2xzLnByb21wdC5sZW5n
dGg+MCYmIWNvbm5lY3Rpb25zLm9wZW5lZCljb25maXJtYXRpb24ub3BlbigpO2lmKCFTeXN0ZW1D
b250cm9scy5idXN5KWNvbmZpcm1hdGlvbi5jbG9zZSgpfSB9Cit9CmRpZmYgLS1naXQgYS9hcHAv
Z3VpL05hdmlnYWJsZURpYWxvZy5xbWwgYi9hcHAvZ3VpL05hdmlnYWJsZURpYWxvZy5xbWwKaW5k
ZXggNDM4NGQ1Yi4uYmQ5ZWRhNSAxMDA2NDQKLS0tIGEvYXBwL2d1aS9OYXZpZ2FibGVEaWFsb2cu
cW1sCisrKyBiL2FwcC9ndWkvTmF2aWdhYmxlRGlhbG9nLnFtbApAQCAtMSw3ICsxLDM1IEBACiBp
bXBvcnQgUXRRdWljayAyLjAKIGltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0
UXVpY2suQ29udHJvbHMuTWF0ZXJpYWwgMi4yCitpbXBvcnQgVmliZW1pcy5SZWRlc2lnbiAxLjAK
IAogRGlhbG9nIHsKKyAgICBpZDogZGlhbG9nCisgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZv
bnRCb2R5CisgICAgZm9udC5waXhlbFNpemU6IFZiVG9rZW5zLnR5cGVCb2R5CisgICAgTWF0ZXJp
YWwuYmFja2dyb3VuZDogVmJUb2tlbnMuYmdFbGV2CisgICAgTWF0ZXJpYWwuZm9yZWdyb3VuZDog
VmJUb2tlbnMudGV4dAorICAgIE1hdGVyaWFsLmFjY2VudDogVmJUb2tlbnMuYWNjZW50CisgICAg
T3ZlcmxheS5tb2RhbDogUmVjdGFuZ2xlIHtjb2xvcjpWYlRva2Vucy5kaWFsb2dTY3JpbX0KKyAg
ICBPdmVybGF5Lm1vZGVsZXNzOiBSZWN0YW5nbGUge2NvbG9yOlZiVG9rZW5zLmRpYWxvZ1Njcmlt
fQorICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsgcmFkaXVzOlZiVG9rZW5zLnJh
ZGl1c0RpYWxvZyB9CisgICAgaGVhZGVyOiBMYWJlbCB7CisgICAgICAgIHZpc2libGU6IGRpYWxv
Zy50aXRsZS5sZW5ndGggPiAwCisgICAgICAgIHRleHQ6IGRpYWxvZy50aXRsZTsgdGV4dEZvcm1h
dDogVGV4dC5QbGFpblRleHQ7IGNvbG9yOlZiVG9rZW5zLnRleHQKKyAgICAgICAgZm9udC5mYW1p
bHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OyBm
b250LmJvbGQ6dHJ1ZQorICAgICAgICBwYWRkaW5nOlZiVG9rZW5zLnNwYWNlNDsgZWxpZGU6VGV4
dC5FbGlkZVJpZ2h0CisgICAgfQorICAgIGZvb3RlcjogRGlhbG9nQnV0dG9uQm94IHsKKyAgICAg
ICAgYmFja2dyb3VuZDogSXRlbSB7fQorICAgICAgICB2aXNpYmxlOiBkaWFsb2cuc3RhbmRhcmRC
dXR0b25zICE9PSBEaWFsb2cuTm9CdXR0b24KKyAgICAgICAgc3RhbmRhcmRCdXR0b25zOiBkaWFs
b2cuc3RhbmRhcmRCdXR0b25zCisgICAgICAgIGltcGxpY2l0SGVpZ2h0OiB2aXNpYmxlID8gTWF0
aC5tYXgoNDQsVmJUb2tlbnMudHlwZUxhYmVsKzIwKSsyKlZiVG9rZW5zLnNwYWNlMyA6IDAKKyAg
ICAgICAgc3BhY2luZzogVmJUb2tlbnMuc3BhY2UyCisgICAgICAgIHBhZGRpbmc6IFZiVG9rZW5z
LnNwYWNlMworICAgICAgICBkZWxlZ2F0ZTogRWNsaXBzZUFjdGlvbkJ1dHRvbiB7fQorICAgICAg
ICBvbkFjY2VwdGVkOiBkaWFsb2cuYWNjZXB0KCkKKyAgICAgICAgb25SZWplY3RlZDogZGlhbG9n
LnJlamVjdCgpCisgICAgfQogICAgIG1vZGFsOiB0cnVlCiAgICAgYW5jaG9ycy5jZW50ZXJJbjog
T3ZlcmxheS5vdmVybGF5CiAKZGlmZiAtLWdpdCBhL2FwcC9ndWkvTmF2aWdhYmxlTWVudS5xbWwg
Yi9hcHAvZ3VpL05hdmlnYWJsZU1lbnUucW1sCmluZGV4IGE3YjIwZjAuLjUwNWYzOTYgMTAwNjQ0
Ci0tLSBhL2FwcC9ndWkvTmF2aWdhYmxlTWVudS5xbWwKKysrIGIvYXBwL2d1aS9OYXZpZ2FibGVN
ZW51LnFtbApAQCAtMSw4ICsxLDExIEBACiBpbXBvcnQgUXRRdWljayAyLjAKIGltcG9ydCBRdFF1
aWNrLkNvbnRyb2xzIDIuMgoraW1wb3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCiAKIE1lbnUgewog
ICAgIHByb3BlcnR5IHZhciBpbml0aWF0b3IKKyAgICBwYWRkaW5nOiBWYlRva2Vucy5zcGFjZTIK
KyAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7cmFkaXVzOlZiVG9rZW5zLnJhZGl1
c0NvbnRyb2x9CiAKICAgICBvbk9wZW5lZDogewogICAgICAgICAvLyBJZiB0aGUgaW5pdGlhdGlu
ZyBvYmplY3QgY3VycmVudGx5IGhhcyBrZXlib2FyZCBmb2N1cywKZGlmZiAtLWdpdCBhL2FwcC9n
dWkvTmF2aWdhYmxlVG9vbEJ1dHRvbi5xbWwgYi9hcHAvZ3VpL05hdmlnYWJsZVRvb2xCdXR0b24u
cW1sCmluZGV4IDViNjQ2NzEuLmE3OTk2MTggMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvTmF2aWdhYmxl
VG9vbEJ1dHRvbi5xbWwKKysrIGIvYXBwL2d1aS9OYXZpZ2FibGVUb29sQnV0dG9uLnFtbApAQCAt
MjcsNyArMjcsNyBAQCBUb29sQnV0dG9uIHsKICAgICBwYWRkaW5nOiAwCiAgICAgTGF5b3V0LmFs
aWdubWVudDogUXQuQWxpZ25WQ2VudGVyCiAKLSAgICBiYWNrZ3JvdW5kOiBSZWN0YW5nbGUgewor
ICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsKICAgICAgICAgcmFkaXVzOiBWYlRv
a2Vucy5yYWRpdXNJY29uQnV0dG9uCiAgICAgICAgIGNvbG9yOiBidG4uYWN0aXZlRm9jdXMgPyBW
YlRva2Vucy5mb2N1c2VkRmlsbCA6IChidG4uaG92ZXJlZCA/IFZiVG9rZW5zLmJnRWxldjIgOiBW
YlRva2Vucy5iZ0VsZXYpCiAgICAgICAgIGJvcmRlci53aWR0aDogMQpkaWZmIC0tZ2l0IGEvYXBw
L2d1aS9QY1ZpZXcucW1sIGIvYXBwL2d1aS9QY1ZpZXcucW1sCmluZGV4IGYwZTczOWEuLjZlYzI0
YzQgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvUGNWaWV3LnFtbAorKysgYi9hcHAvZ3VpL1BjVmlldy5x
bWwKQEAgLTQzLDcgKzQzLDE2IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgIC8vIGJhY2sgdG8g
bWluTWFyZ2luIChkZWZhdWx0IDEwcHgpIOKAlCBjYXJkcyBodWdnZWQgdGhlIHNjcmVlbiBlZGdl
LCBtaXNhbGlnbmVkIHdpdGggdGhlCiAgICAgLy8gNTZweCBoZWFkZXIgYW5kIHZpc3VhbGx5IGNs
aXBwaW5nIHRoZSBmb2N1cyByaW5nJ3Mgb3V0ZXIgZ2xvdy4gQWxpZ24gcGFydGlhbCByb3dzIHdp
dGgKICAgICAvLyB0aGUgcmVkZXNpZ24ncyBzY3JlZW4gcGFkZGluZyBpbnN0ZWFkLgorICAgIHJl
YWRvbmx5IHByb3BlcnR5IGJvb2wgZ2xhc3NXaWRlOiB3aWR0aCA+PSAxMjQwICYmIGhlaWdodCA+
PSA1NDAKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgcmFpbFNwYWNlOiB3aWR0aCA+PSA5MDAg
PyA4NCA6IDAKKyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgbG9jYWxTcGFjZTogZ2xhc3NXaWRl
ID8gTWF0aC5yb3VuZCgyNTIqVmJUb2tlbnMudGV4dFNjYWxlKSA6IDAKKyAgICByZWFkb25seSBw
cm9wZXJ0eSBpbnQgaG9zdFNwYWNlOiAwCiAgICAgbWluTWFyZ2luOiBWYlRva2Vucy5zY3JlZW5Q
YWRYCisgICAgYXZhaWxhYmxlV2lkdGg6IHdpZHRoIC0gcmFpbFNwYWNlIC0gbG9jYWxTcGFjZSAt
IGhvc3RTcGFjZSAtIDIqbWluTWFyZ2luCisgICAgb25SYWlsU3BhY2VDaGFuZ2VkOiB1cGRhdGVN
YXJnaW5zKCkKKyAgICBvbkxvY2FsU3BhY2VDaGFuZ2VkOiB1cGRhdGVNYXJnaW5zKCkKKyAgICBv
bkhvc3RTcGFjZUNoYW5nZWQ6IHVwZGF0ZU1hcmdpbnMoKQorICAgIGZ1bmN0aW9uIHVwZGF0ZU1h
cmdpbnMoKSB7IGxlZnRNYXJnaW49aG9yaXpvbnRhbE1hcmdpbityYWlsU3BhY2UraG9zdFNwYWNl
O3JpZ2h0TWFyZ2luPWhvcml6b250YWxNYXJnaW4rbG9jYWxTcGFjZSB9CiAgICAgLy8gVGhlICJB
ZGQgYSBjb21wdXRlciIgZ2hvc3QgY2FyZCBpcyBoYW5kLXBsYWNlZCBhdCB0aGUgaW5kZXg9PWNv
dW50IGNlbGwgKHNlZSB0aGUgZGVsZWdhdGUncwogICAgIC8vIHNpYmxpbmcgYmVsb3cpLiBHcmlk
Vmlldy5jb250ZW50SGVpZ2h0IG9ubHkgY291bnRzIHJlYWwgZGVsZWdhdGVzLCBzbyB3aGVuIHRo
ZSBsYXN0IHJvdyBpcyBGVUxMCiAgICAgLy8gKGNvdW50IGlzIGEgbXVsdGlwbGUgb2YgdGhlIGNv
bHVtbiBjb3VudCkgdGhlIGdob3N0IGNhcmQgc3RhcnRzIGEgYnJhbmQtbmV3IHZpcnR1YWwgcm93
IGF0CkBAIC01Miw3ICs2MSw3IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgIGJvdHRvbU1hcmdp
bjogKHBjSGludEJhci52aXNpYmxlID8gcGNIaW50QmFyLmhlaWdodCA6IDApICsgMTIKICAgICAg
ICAgICAgICAgICAgICsgKChjb3VudCA+IDAgJiYgKGNvdW50ICUgTWF0aC5tYXgoMSwgTWF0aC5m
bG9vcihpdGVtc1BlclJvdykpKSA9PT0gMCkgPyBjZWxsSGVpZ2h0IDogMCkKICAgICAvLyBSZWRl
c2lnbjogNDMwcHggcmljaCBob3N0IGNhcmRzIChnYXAgMzIpIGluIGEgY2VudGVyZWQgd3JhcHBp
bmcgcm93LgotICAgIGNlbGxXaWR0aDogNDYyOyBjZWxsSGVpZ2h0OiAyNzQ7CisgICAgY2VsbFdp
ZHRoOiAzOTI7IGNlbGxIZWlnaHQ6IDI2NjsKICAgICBvYmplY3ROYW1lOiBxc1RyKCJDb21wdXRl
cnMiKQogCiAgICAgLy8gRC1wYWQgc2VsZWN0aW9uIHN0YXRlIGZvciB0aGUgQWRkLWEtY29tcHV0
ZXIgZ2hvc3Qg4oCUIFdJVEhPVVQgZm9jdXMuIFRoZQpAQCAtMTAwLDI0ICsxMDksMjUgQEAgQ2Vu
dGVyZWRHcmlkVmlldyB7CiAgICAgLy8gU28gdGhpcyBpcyBqdXN0IHRoZSBib2R5IHNlY3Rpb24g
dGl0bGUgYmVsb3cgdGhlIHRvb2xiYXI7IHRoZXJlIGlzIG5vIGRvdWJsZSBoZWFkZXIuCiAgICAg
SXRlbSB7CiAgICAgICAgIGlkOiBwY0Nocm9tZUhlYWRlcgorICAgICAgICBvYmplY3ROYW1lOiAi
Y3JpbXNvbkdyaWRIZWFkZXIiCiAgICAgICAgIHo6IDEwCiAgICAgICAgIGFuY2hvcnMudG9wOiBw
YXJlbnQudG9wCiAgICAgICAgIGFuY2hvcnMubGVmdDogcGFyZW50LmxlZnQKICAgICAgICAgYW5j
aG9ycy5yaWdodDogcGFyZW50LnJpZ2h0CiAgICAgICAgIHZpc2libGU6IHRydWUKLSAgICAgICAg
aGVpZ2h0OiA3OAorICAgICAgICBoZWlnaHQ6IDY2CiAKICAgICAgICAgUmVjdGFuZ2xlIHsgYW5j
aG9ycy5maWxsOiBwYXJlbnQ7IGNvbG9yOiBWYlRva2Vucy5iZ1dpbmRvdyB9CiAKICAgICAgICAg
Um93IHsKICAgICAgICAgICAgIGFuY2hvcnMubGVmdDogcGFyZW50LmxlZnQKLSAgICAgICAgICAg
IGFuY2hvcnMubGVmdE1hcmdpbjogVmJUb2tlbnMuc2NyZWVuUGFkWAorICAgICAgICAgICAgYW5j
aG9ycy5sZWZ0TWFyZ2luOiBWYlRva2Vucy5zY3JlZW5QYWRYK3BjR3JpZC5yYWlsU3BhY2UrcGNH
cmlkLmhvc3RTcGFjZQogICAgICAgICAgICAgYW5jaG9ycy5ib3R0b206IHBhcmVudC5ib3R0b20K
ICAgICAgICAgICAgIGFuY2hvcnMuYm90dG9tTWFyZ2luOiA2CiAgICAgICAgICAgICBzcGFjaW5n
OiAxNAogICAgICAgICAgICAgVGV4dCB7CiAgICAgICAgICAgICAgICAgaWQ6IHNlY3Rpb25UaXRs
ZQotICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkNvbXB1dGVycyIpCisgICAgICAgICAgICAg
ICAgdGV4dDogcXNUcigiSG9zdHMiKQogICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRv
a2Vucy5mb250RGlzcGxheQogICAgICAgICAgICAgICAgIGZvbnQud2VpZ2h0OiBGb250LkJvbGQK
ICAgICAgICAgICAgICAgICBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMuc2l6ZVNjcmVlblRpdGxl
CkBAIC0xMzQsNiArMTQ0LDI0IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgICAgICB9CiAgICAg
fQogCisKKyAgICAvLyBDcmltc29uIEdsYXNzIGRhc2hib2FyZCBjaHJvbWUgbGl2ZXMgaW4gdGhl
IHZpZXdwb3J0LCBvdXRzaWRlIGNvbnRlbnRJdGVtLgorICAgIENyaW1zb25HbGFzc1JhaWwgewor
ICAgICAgICBwYXJlbnQ6cGNHcmlkCisgICAgICAgIHo6MTE7eDoxMjt5OjE2O3dpZHRoOjY0O2hl
aWdodDpNYXRoLm1heCgyODAscGNHcmlkLmhlaWdodC0zMi0ocGNIaW50QmFyLnZpc2libGU/cGNI
aW50QmFyLmhlaWdodDowKSkKKyAgICAgICAgdmlzaWJsZTpwY0dyaWQucmFpbFNwYWNlPjA7aW5M
aWJyYXJ5OmZhbHNlCisgICAgICAgIG9uSG9tZVJlcXVlc3RlZDogeyBpZihzdGFja1ZpZXcuZGVw
dGg+MSkgc3RhY2tWaWV3LnBvcChudWxsKTtlbHNlIHBjR3JpZC5mb3JjZUFjdGl2ZUZvY3VzKCkg
fQorICAgICAgICBvblNldHRpbmdzUmVxdWVzdGVkOiBzZXR0aW5nc0J1dHRvbi5jbGlja2VkKCkK
KyAgICAgICAgb25Db250cm9sc1JlcXVlc3RlZDogZWNsaXBzZUNlbnRlckJ1dHRvbi5jbGlja2Vk
KCkKKyAgICB9CisgICAgQ3JpbXNvbkxvY2FsUGFuZWwgeworICAgICAgICBwYXJlbnQ6cGNHcmlk
CisgICAgICAgIHo6MTE7YW5jaG9ycy5yaWdodDpwYXJlbnQucmlnaHQ7YW5jaG9ycy5yaWdodE1h
cmdpbjoxNjt5OjE2O3dpZHRoOk1hdGgubWF4KDAscGNHcmlkLmxvY2FsU3BhY2UtMjgpCisgICAg
ICAgIGhlaWdodDpNYXRoLm1heCgyNDAscGNHcmlkLmhlaWdodC0zMi0ocGNIaW50QmFyLnZpc2li
bGU/cGNIaW50QmFyLmhlaWdodDowKSk7dmlzaWJsZTpwY0dyaWQubG9jYWxTcGFjZT4wCisgICAg
ICAgIGFjdGl2ZTp2aXNpYmxlICYmIHBjR3JpZC5TdGFja1ZpZXcuc3RhdHVzPT09U3RhY2tWaWV3
LkFjdGl2ZQorICAgICAgICBvbkNvbnRyb2xzUmVxdWVzdGVkOiBlY2xpcHNlQ2VudGVyQnV0dG9u
LmNsaWNrZWQoKQorICAgIH0KKwogICAgIC8vIFBlcnNpc3RlbnQgZ2FtZXBhZCBoaW50IGJhciwg
Zml4ZWQgYXQgdGhlIGJvdHRvbS4gR3JpZCBib3R0b21NYXJnaW4gY2xlYXJzIGl0LgogICAgIFZi
SGludEJhciB7CiAgICAgICAgIGlkOiBwY0hpbnRCYXIKQEAgLTI2OSw3ICsyOTcsNyBAQCBDZW50
ZXJlZEdyaWRWaWV3IHsKIAogICAgIGZ1bmN0aW9uIGNyZWF0ZU1vZGVsKCkKICAgICB7Ci0gICAg
ICAgIHZhciBtb2RlbCA9IFF0LmNyZWF0ZVFtbE9iamVjdCgnaW1wb3J0IENvbXB1dGVyTW9kZWwg
MS4wOyBDb21wdXRlck1vZGVsIHt9JywgcGFyZW50LCAnJykKKyAgICAgICAgdmFyIG1vZGVsID0g
UXQuY3JlYXRlUW1sT2JqZWN0KCdpbXBvcnQgQ29tcHV0ZXJNb2RlbCAxLjA7IENvbXB1dGVyTW9k
ZWwge30nLCBwY0dyaWQsICcnKQogICAgICAgICBtb2RlbC5pbml0aWFsaXplKENvbXB1dGVyTWFu
YWdlcikKICAgICAgICAgbW9kZWwucGFpcmluZ0NvbXBsZXRlZC5jb25uZWN0KHBhaXJpbmdDb21w
bGV0ZSkKICAgICAgICAgbW9kZWwuY29ubmVjdGlvblRlc3RDb21wbGV0ZWQuY29ubmVjdCh0ZXN0
Q29ubmVjdGlvbkRpYWxvZy5jb25uZWN0aW9uVGVzdENvbXBsZXRlKQpAQCAtMzAxLDcgKzMyOSw3
IEBAIENlbnRlcmVkR3JpZFZpZXcgewogCiAgICAgZGVsZWdhdGU6IE5hdmlnYWJsZUl0ZW1EZWxl
Z2F0ZSB7CiAgICAgICAgIGlkOiBwY0RlbGVnYXRlCi0gICAgICAgIHdpZHRoOiA0MzA7IGhlaWdo
dDogMjQyOworICAgICAgICB3aWR0aDogcGNHcmlkLmNlbGxXaWR0aCAtIDIwOyBoZWlnaHQ6IDI0
MjsKICAgICAgICAgZ3JpZDogcGNHcmlkCiAKICAgICAgICAgLy8gVGhlIE1hdGVyaWFsIHN0eWxl
IHBhaW50cyBhbiBhbHdheXMtdmlzaWJsZQpAQCAtNDQ0LDcgKzQ3Miw3IEBAIENlbnRlcmVkR3Jp
ZFZpZXcgewogICAgICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogbW9kZWwub25saW5lICYm
IG1vZGVsLnBhaXJlZCwKICAgICAgICAgICAgICAgICAgICAgICAgIHRyaWdnZXI6IGZ1bmN0aW9u
KCkgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHZhciBjb21wb25lbnQgPSBRdC5jcmVh
dGVDb21wb25lbnQoIkFwcFZpZXcucW1sIikKLSAgICAgICAgICAgICAgICAgICAgICAgICAgICB2
YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVPYmplY3Qoc3RhY2tWaWV3LCB7ImNvbXB1dGVy
SW5kZXgiOiBpbmRleCwgIm9iamVjdE5hbWUiOiBtb2RlbC5uYW1lLCAic2hvd0hpZGRlbkdhbWVz
IjogdHJ1ZSwgImhvc3RPbmxpbmUiOiBtb2RlbC5vbmxpbmUsICJob3N0VHlwZSI6IG1vZGVsLmhv
c3RUeXBlLCAiaG9zdFRyYW5zcG9ydCI6IG1vZGVsLnRyYW5zcG9ydH0pCisgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgdmFyIGFwcFZpZXcgPSBjb21wb25lbnQuY3JlYXRlT2JqZWN0KHN0YWNr
VmlldywgeyJjb21wdXRlckluZGV4IjogaW5kZXgsICJjcmltc29uSG9zdCI6IGNvbXB1dGVyTW9k
ZWwuY3JpbXNvbkhvc3QoaW5kZXgpLCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUsICJzaG93SGlk
ZGVuR2FtZXMiOiB0cnVlLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhvc3RUeXBlIjog
bW9kZWwuaG9zdFR5cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0fSkKICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICBzdGFja1ZpZXcucHVzaChhcHBWaWV3KQogICAgICAgICAg
ICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICB9LApAQCAtNTM1LDcgKzU2Myw3
IEBAIENlbnRlcmVkR3JpZFZpZXcgewogICAgICAgICAgICAgICAgIGVsc2UgaWYgKG1vZGVsLnBh
aXJlZCkgewogICAgICAgICAgICAgICAgICAgICAvLyBnbyB0byBnYW1lIHZpZXcKICAgICAgICAg
ICAgICAgICAgICAgdmFyIGNvbXBvbmVudCA9IFF0LmNyZWF0ZUNvbXBvbmVudCgiQXBwVmlldy5x
bWwiKQotICAgICAgICAgICAgICAgICAgICB2YXIgYXBwVmlldyA9IGNvbXBvbmVudC5jcmVhdGVP
YmplY3Qoc3RhY2tWaWV3LCB7ImNvbXB1dGVySW5kZXgiOiBpbmRleCwgIm9iamVjdE5hbWUiOiBt
b2RlbC5uYW1lLCAiaG9zdE9ubGluZSI6IG1vZGVsLm9ubGluZSwgImhvc3RUeXBlIjogbW9kZWwu
aG9zdFR5cGUsICJob3N0VHJhbnNwb3J0IjogbW9kZWwudHJhbnNwb3J0fSkKKyAgICAgICAgICAg
ICAgICAgICAgdmFyIGFwcFZpZXcgPSBjb21wb25lbnQuY3JlYXRlT2JqZWN0KHN0YWNrVmlldywg
eyJjb21wdXRlckluZGV4IjogaW5kZXgsICJjcmltc29uSG9zdCI6IGNvbXB1dGVyTW9kZWwuY3Jp
bXNvbkhvc3QoaW5kZXgpLCAib2JqZWN0TmFtZSI6IG1vZGVsLm5hbWUsICJob3N0T25saW5lIjog
bW9kZWwub25saW5lLCAiaG9zdFR5cGUiOiBtb2RlbC5ob3N0VHlwZSwgImhvc3RUcmFuc3BvcnQi
OiBtb2RlbC50cmFuc3BvcnR9KQogICAgICAgICAgICAgICAgICAgICBzdGFja1ZpZXcucHVzaChh
cHBWaWV3KQogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICBlbHNlIHsKQEAgLTYx
Niw3ICs2NDQsNyBAQCBDZW50ZXJlZEdyaWRWaWV3IHsKICAgICAgICAgb25TZWxlY3RlZENoYW5n
ZWQ6IGFkZFBjRGFzaGVkQm9yZGVyLnJlcXVlc3RQYWludCgpCiAgICAgICAgIHg6IChwY0dyaWQu
Y291bnQgJSBjb2x1bW5zKSAqIHBjR3JpZC5jZWxsV2lkdGgKICAgICAgICAgeTogTWF0aC5mbG9v
cihwY0dyaWQuY291bnQgLyBjb2x1bW5zKSAqIHBjR3JpZC5jZWxsSGVpZ2h0Ci0gICAgICAgIHdp
ZHRoOiA0MzAKKyAgICAgICAgd2lkdGg6IHBjR3JpZC5jZWxsV2lkdGgtMjAKICAgICAgICAgaGVp
Z2h0OiAyNDIKICAgICAgICAgejogMgogCkBAIC02MjUsNyArNjUzLDcgQEAgQ2VudGVyZWRHcmlk
VmlldyB7CiAgICAgICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAogICAgICAgICAgICAgcmFk
aXVzOiAyMAogICAgICAgICAgICAgY29sb3I6IGFkZFBjQ2FyZFNsb3QuaGlnaGxpZ2h0ZWQgPyBW
YlRva2Vucy5iZ0VsZXYgOiAidHJhbnNwYXJlbnQiCi0gICAgICAgICAgICBCZWhhdmlvciBvbiBj
b2xvciB7IENvbG9yQW5pbWF0aW9uIHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAgICAgICAgIEJl
aGF2aW9yIG9uIGNvbG9yIHsgQ29sb3JBbmltYXRpb24geyBkdXJhdGlvbjogVmJUb2tlbnMubW90
aW9uRW5hYmxlZCA/IDEyMCA6IDAgfSB9CiAgICAgICAgIH0KIAogICAgICAgICBDYW52YXMgewpk
aWZmIC0tZ2l0IGEvYXBwL2d1aS9RdWlja01lbnUucW1sIGIvYXBwL2d1aS9RdWlja01lbnUucW1s
CmluZGV4IGIwMzNkMjYuLjg3MmZmZjkgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvUXVpY2tNZW51LnFt
bAorKysgYi9hcHAvZ3VpL1F1aWNrTWVudS5xbWwKQEAgLTIxLDYgKzIxLDEwIEBAIFJlY3Rhbmds
ZSB7CiAgICAgcmFkaXVzOiBWYlRva2Vucy5yYWRpdXNXaW5kb3cKICAgICBib3JkZXIuY29sb3I6
IFZiVG9rZW5zLmRpdmlkZXIKICAgICBib3JkZXIud2lkdGg6IDEKKyAgICBncmFkaWVudDogR3Jh
ZGllbnQgeworICAgICAgICBHcmFkaWVudFN0b3Age3Bvc2l0aW9uOjA7Y29sb3I6VmJUb2tlbnMu
Z2xhc3NUb3B9CisgICAgICAgIEdyYWRpZW50U3RvcCB7cG9zaXRpb246MTtjb2xvcjpWYlRva2Vu
cy5zdXJmYWNlUmFpc2VkfQorICAgIH0KICAgICB2aXNpYmxlOiB0cnVlICAvLyBBbHdheXMgdmlz
aWJsZSB3aGVuIGNyZWF0ZWQKICAgICBvcGFjaXR5OiAxLjAKICAgICAKQEAgLTM2LDcgKzQwLDcg
QEAgUmVjdGFuZ2xlIHsKICAgICAKICAgICAvLyBBbmltYXRpb24gZm9yIHNtb290aCBzaG93L2hp
ZGUKICAgICBCZWhhdmlvciBvbiBvcGFjaXR5IHsKLSAgICAgICAgTnVtYmVyQW5pbWF0aW9uIHsg
ZHVyYXRpb246IDIwMCB9CisgICAgICAgIE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRv
a2Vucy5tb3Rpb25FbmFibGVkID8gMjAwIDogMCB9CiAgICAgfQogICAgIAogICAgIC8vIEhhbmRs
ZSBrZXlib2FyZCBpbnB1dCBmb3IgbmF2aWdhdGlvbgpAQCAtMTM5LDcgKzE0Myw3IEBAIFJlY3Rh
bmdsZSB7CiAgICAgICAgICAgICAgICAgLy8gU2hlZXQtcm93IHJlY2lwZSDigJQgZm9jdXNlZEZp
bGwgc3VyZmFjZSArIGFjY2VudCBib3JkZXIgd2hlbgogICAgICAgICAgICAgICAgIC8vIGN1cnJl
bnQgKGZsYXQgdmFyaWFudDogdGhlIG91dGVyIGdsb3cgd291bGQgY2xpcCBpbnNpZGUgdGhpcyBz
Y3JvbGxpbmcKICAgICAgICAgICAgICAgICAvLyBjbGlwcGVkIGxpc3QsIHNvIHRoZSByaW5nIGlz
IGJvcmRlci1vbmx5IGhlcmUpLgotICAgICAgICAgICAgICAgIGJhY2tncm91bmQ6IFJlY3Rhbmds
ZSB7CisgICAgICAgICAgICAgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgewogICAg
ICAgICAgICAgICAgICAgICByYWRpdXM6IFZiVG9rZW5zLnJhZGl1c0NvbnRyb2wKICAgICAgICAg
ICAgICAgICAgICAgY29sb3I6IG1lbnVSb3cuZG93biA/IFF0LmRhcmtlcihWYlRva2Vucy5pbnRl
cmFjdGl2ZUZvY3VzLCAxLjE1KQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgIDogKG1lbnVSb3cuYWN0aXZlID8gVmJUb2tlbnMuaW50ZXJhY3RpdmVGb2N1cyA6ICJ0cmFu
c3BhcmVudCIpCkBAIC0yMjksNyArMjMzLDcgQEAgUmVjdGFuZ2xlIHsKICAgICAgICAgICAgICAg
ICBsZWZ0UGFkZGluZzogMTIKICAgICAgICAgICAgICAgICByaWdodFBhZGRpbmc6IDEyCiAgICAg
ICAgICAgICAgICAgLy8gVG9rZW4gZmllbGQg4oCUIHdpbmRvdy1kYXJrIHdlbGwgKyBhY2NlbnQg
Zm9jdXMgYm9yZGVyLgotICAgICAgICAgICAgICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7Cisg
ICAgICAgICAgICAgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgewogICAgICAgICAg
ICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuc3VyZmFjZUJhc2UKICAgICAgICAgICAgICAgICAg
ICAgYm9yZGVyLmNvbG9yOiBzZW5kVGV4dEZpZWxkLmFjdGl2ZUZvY3VzID8gVmJUb2tlbnMuYWNj
ZW50IDogVmJUb2tlbnMuZGl2aWRlcgogICAgICAgICAgICAgICAgICAgICBib3JkZXIud2lkdGg6
IFZiVG9rZW5zLmZvY3VzQm9yZGVyCkBAIC0zNzIsNyArMzc2LDcgQEAgUmVjdGFuZ2xlIHsKICAg
ICAgICAgb3BhY2l0eTogc2hvd1RvYXN0ID8gMS4wIDogMC4wCiAKICAgICAgICAgQmVoYXZpb3Ig
b24gb3BhY2l0eSB7Ci0gICAgICAgICAgICBOdW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjogMjAw
IH0KKyAgICAgICAgICAgIE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rp
b25FbmFibGVkID8gMjAwIDogMCB9CiAgICAgICAgIH0KIAogICAgICAgICBUZXh0IHsKQEAgLTQ0
OSw3ICs0NTMsNyBAQCBSZWN0YW5nbGUgewogICAgICAgICAgICAgdGV4dDogcXNUcigiUXVpdCBn
YW1lIikKICAgICAgICAgICAgIGljb246ICJwb3dlciIKICAgICAgICAgICAgIGFjdGlvbjogInF1
aXQiCi0gICAgICAgICAgICBkZXNjcmlwdGlvbjogcXNUcigiUXVpdCB0aGUgZ2FtZSBvbiB0aGUg
aG9zdCBhbmQgcmV0dXJuIHRvIFZpYmVtaXMiKQorICAgICAgICAgICAgZGVzY3JpcHRpb246IHFz
VHIoIlF1aXQgdGhlIGdhbWUgb24gdGhlIGhvc3QgYW5kIHJldHVybiB0byBFY2xpcHNlIikKICAg
ICAgICAgfQogICAgICAgICBMaXN0RWxlbWVudCB7CiAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJT
ZXJ2ZXIgY29tbWFuZHMiKQpAQCAtNzE0LDQgKzcxOCwzIEBAIFJlY3RhbmdsZSB7CiAgICAgICAg
IH0KICAgICB9CiB9Ci0KZGlmZiAtLWdpdCBhL2FwcC9ndWkvU2VydmVyQ29tbWFuZHMucW1sIGIv
YXBwL2d1aS9TZXJ2ZXJDb21tYW5kcy5xbWwKaW5kZXggYTBiYTQ3ZS4uOWNlODNkMCAxMDA2NDQK
LS0tIGEvYXBwL2d1aS9TZXJ2ZXJDb21tYW5kcy5xbWwKKysrIGIvYXBwL2d1aS9TZXJ2ZXJDb21t
YW5kcy5xbWwKQEAgLTE1NSw3ICsxNTUsNyBAQCBHcm91cEJveCB7CiAgICAgfQogCiAgICAgLy8g
Q29uZmlybWF0aW9uIGRpYWxvZwotICAgIERpYWxvZyB7CisgICAgTmF2aWdhYmxlRGlhbG9nIHsK
ICAgICAgICAgaWQ6IGNvbmZpcm1EaWFsb2cKICAgICAgICAgYW5jaG9ycy5jZW50ZXJJbjogcGFy
ZW50CiAgICAgICAgIHdpZHRoOiBNYXRoLm1pbig0MDAsIHBhcmVudC53aWR0aCAqIDAuOSkKQEAg
LTE2OCw3ICsxNjgsNyBAQCBHcm91cEJveCB7CiAgICAgICAgIHRpdGxlOiBxc1RyKCJDb25maXJt
IENvbW1hbmQiKQogICAgICAgICBtb2RhbDogdHJ1ZQogCi0gICAgICAgIGJhY2tncm91bmQ6IFJl
Y3RhbmdsZSB7CisgICAgICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsKICAgICAg
ICAgICAgIGNvbG9yOiBWYlRva2Vucy5zdXJmYWNlUmFpc2VkCiAgICAgICAgICAgICByYWRpdXM6
IFZiVG9rZW5zLnJhZGl1c0RpYWxvZwogICAgICAgICAgICAgYm9yZGVyLndpZHRoOiAxCkBAIC0y
MTYsNyArMjE2LDcgQEAgR3JvdXBCb3ggewogICAgIH0KIAogICAgIC8vIEN1c3RvbSBjb21tYW5k
IGRpYWxvZwotICAgIERpYWxvZyB7CisgICAgTmF2aWdhYmxlRGlhbG9nIHsKICAgICAgICAgaWQ6
IGN1c3RvbUNvbW1hbmREaWFsb2cKICAgICAgICAgYW5jaG9ycy5jZW50ZXJJbjogcGFyZW50CiAg
ICAgICAgIHdpZHRoOiBNYXRoLm1pbig0MDAsIHBhcmVudC53aWR0aCAqIDAuOSkKQEAgLTIyNSw3
ICsyMjUsNyBAQCBHcm91cEJveCB7CiAgICAgICAgIHRpdGxlOiBxc1RyKCJDdXN0b20gQ29tbWFu
ZCIpCiAgICAgICAgIG1vZGFsOiB0cnVlCiAKLSAgICAgICAgYmFja2dyb3VuZDogUmVjdGFuZ2xl
IHsKKyAgICAgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgewogICAgICAgICAgICAg
Y29sb3I6IFZiVG9rZW5zLnN1cmZhY2VSYWlzZWQKICAgICAgICAgICAgIHJhZGl1czogVmJUb2tl
bnMucmFkaXVzRGlhbG9nCiAgICAgICAgICAgICBib3JkZXIud2lkdGg6IDEKZGlmZiAtLWdpdCBh
L2FwcC9ndWkvU2V0dGluZ3NWaWV3LnFtbCBiL2FwcC9ndWkvU2V0dGluZ3NWaWV3LnFtbAppbmRl
eCA0OTRlMzViLi5lOTg5MTZiIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1NldHRpbmdzVmlldy5xbWwK
KysrIGIvYXBwL2d1aS9TZXR0aW5nc1ZpZXcucW1sCkBAIC0xMyw5ICsxMywxMSBAQCBpbXBvcnQg
QXV0b1VwZGF0ZUNoZWNrZXIgMS4wCiBpbXBvcnQgVWlTb3VuZE1hbmFnZXIgMS4wCiAKIGltcG9y
dCBWaWJlbWlzLlJlZGVzaWduIDEuMAoraW1wb3J0IEVjbGlwc2VQcm9maWxlcyAxLjAKIAogSXRl
bSB7CiAgICAgaWQ6IHNldHRpbmdzUGFnZQorICAgIENyaW1zb25CYWNrZ3JvdW5kUGlja2VyIHsg
aWQ6YmFja2dyb3VuZFBpY2tlciB9CiAgICAgb2JqZWN0TmFtZTogcXNUcigiU2V0dGluZ3MiKQog
CiAgICAgLy8gTEIvUkIgY2F0ZWdvcnkgZmxpcHMgY2hhbmdlIGBjYXRlZ29yeWAgd2l0aG91dCBt
b3ZpbmcgaXRlbSBmb2N1cywKQEAgLTY4LDcgKzcwLDcgQEAgSXRlbSB7CiAgICAgY29tcG9uZW50
IFZiU2V0dGluZ3NDYXJkOiBHcm91cEJveCB7CiAgICAgICAgIHBhZGRpbmc6IFZiVG9rZW5zLnNw
YWNlNQogICAgICAgICBsYWJlbDogSXRlbSB7fQotICAgICAgICBiYWNrZ3JvdW5kOiBSZWN0YW5n
bGUgeworICAgICAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgICAg
ICBjb2xvcjogVmJUb2tlbnMuYmdFbGV2CiAgICAgICAgICAgICByYWRpdXM6IFZiVG9rZW5zLnJh
ZGl1c0NhcmQKICAgICAgICAgICAgIGJvcmRlci53aWR0aDogMQpAQCAtMTYyLDE0ICsxNjQsMTQg
QEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgIGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBh
cmVudC52ZXJ0aWNhbENlbnRlcgogICAgICAgICAgICAgICAgICAgICB4OiB0b2dnbGVSb290LmNo
ZWNrZWQgPyBwYXJlbnQud2lkdGggLSB3aWR0aCAtIDQgOiA0CiAgICAgICAgICAgICAgICAgICAg
IGNvbG9yOiB0b2dnbGVSb290LmNoZWNrZWQgPyBWYlRva2Vucy50ZXh0T25BY2NlbnQgOiBWYlRv
a2Vucy50ZXh0RGltCi0gICAgICAgICAgICAgICAgICAgIEJlaGF2aW9yIG9uIHggeyBOdW1iZXJB
bmltYXRpb24geyBkdXJhdGlvbjogMTIwIH0gfQorICAgICAgICAgICAgICAgICAgICBCZWhhdmlv
ciBvbiB4IHsgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRpb246IFZiVG9rZW5zLm1vdGlvbkVuYWJs
ZWQgPyAxMjAgOiAwIH0gfQogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgIH0KICAgICAg
ICAgfQogICAgIH0KIAogICAgIC8vIEZ1bGwtYmxlZWQgd2luZG93IGJhY2tncm91bmQuCi0gICAg
UmVjdGFuZ2xlIHsgYW5jaG9ycy5maWxsOiBwYXJlbnQ7IGNvbG9yOiBWYlRva2Vucy5iZ1dpbmRv
dyB9CisgICAgQ3JpbXNvbkdsYXNzQmFja2Ryb3AgeyBhbmNob3JzLmZpbGw6IHBhcmVudCB9CiAK
ICAgICAvLyBTdGFja1ZpZXcgYXR0YWNoZWQgaGFuZGxlcnMgbXVzdCBzdGF5IG9uIHRoZSBwdXNo
ZWQgcGFnZSAodGhlIEl0ZW0gcm9vdCkuCiAgICAgU3RhY2tWaWV3Lm9uQWN0aXZhdGVkOiB7CkBA
IC0zNDYsMTIgKzM0OCwxMyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgeyBpY29uOiAi
Z2FtZXBhZCIsICAgbGFiZWw6IHFzVHIoIklucHV0ICYgZ2FtZXBhZCIpIH0sCiAgICAgICAgICAg
ICAgICAgICAgIHsgaWNvbjogInN0cmVhbWluZyIsIGxhYmVsOiBxc1RyKCJTdHJlYW1pbmciKSB9
LAogICAgICAgICAgICAgICAgICAgICB7IGljb246ICJhcHBzIiwgICAgICBsYWJlbDogcXNUcigi
QXBwICYgVUkiKSB9LAotICAgICAgICAgICAgICAgICAgICB7IGljb246ICJhZHZhbmNlZCIsICBs
YWJlbDogcXNUcigiQWR2YW5jZWQiKSB9CisgICAgICAgICAgICAgICAgICAgIHsgaWNvbjogImFk
dmFuY2VkIiwgIGxhYmVsOiBxc1RyKCJBZHZhbmNlZCIpIH0sCisgICAgICAgICAgICAgICAgICAg
IHsgaWNvbjogImFkdmFuY2VkIiwgbGFiZWw6IHFzVHIoIlN5c3RlbSBDb250cm9scyIpIH0KICAg
ICAgICAgICAgICAgICBdCiAgICAgICAgICAgICAgICAgZGVsZWdhdGU6IEJ1dHRvbiB7CiAgICAg
ICAgICAgICAgICAgICAgIGlkOiBjYXRCdXR0b24KICAgICAgICAgICAgICAgICAgICAgd2lkdGg6
IHNpZGViYXJDb2x1bW4ud2lkdGgKLSAgICAgICAgICAgICAgICAgICAgaGVpZ2h0OiA1OAorICAg
ICAgICAgICAgICAgICAgICBoZWlnaHQ6IE1hdGgubWluKDU4LE1hdGgubWF4KDQ0LChzaWRlYmFy
LmhlaWdodC02NC0oc2lkZWJhclJlcGVhdGVyLmNvdW50LTEpKlZiVG9rZW5zLnNwYWNlMikvc2lk
ZWJhclJlcGVhdGVyLmNvdW50KSkKICAgICAgICAgICAgICAgICAgICAgcGFkZGluZzogMAogICAg
ICAgICAgICAgICAgICAgICBsZWZ0UGFkZGluZzogVmJUb2tlbnMuc3BhY2U0CiAgICAgICAgICAg
ICAgICAgICAgIHJpZ2h0UGFkZGluZzogVmJUb2tlbnMuc3BhY2U0CkBAIC0zNzksNyArMzgyLDcg
QEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYm9yZGVyLndpZHRoOiAoY2F0
QnV0dG9uLnNlbGVjdGVkIHx8IGNhdEJ1dHRvbi5hY3RpdmVGb2N1cykgPyBWYlRva2Vucy5mb2N1
c0JvcmRlciA6IDEKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBib3JkZXIuY29sb3I6IChj
YXRCdXR0b24uc2VsZWN0ZWQgfHwgY2F0QnV0dG9uLmFjdGl2ZUZvY3VzKSA/IFZiVG9rZW5zLmFj
Y2VudCA6IFZiVG9rZW5zLnN0cm9rZQogICAgICAgICAgICAgICAgICAgICAgICAgICAgIGFudGlh
bGlhc2luZzogdHJ1ZQotICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJlaGF2aW9yIG9uIGNv
bG9yIHsgQ29sb3JBbmltYXRpb24geyBkdXJhdGlvbjogMTIwIH0gfQorICAgICAgICAgICAgICAg
ICAgICAgICAgICAgIEJlaGF2aW9yIG9uIGNvbG9yIHsgQ29sb3JBbmltYXRpb24geyBkdXJhdGlv
bjogVmJUb2tlbnMubW90aW9uRW5hYmxlZCA/IDEyMCA6IDAgfSB9CiAgICAgICAgICAgICAgICAg
ICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgIH0KIApAQCAtNTI0LDcgKzUyNyw3IEBAIEl0
ZW0gewogCiAgICAgICAgIE51bWJlckFuaW1hdGlvbiBvbiBjb250ZW50WSB7CiAgICAgICAgICAg
ICBpZDogYXV0b1Njcm9sbEFuaW1hdGlvbgotICAgICAgICAgICAgZHVyYXRpb246IDEwMAorICAg
ICAgICAgICAgZHVyYXRpb246IFZiVG9rZW5zLm1vdGlvbkVuYWJsZWQgPyAxMDAgOiAwCiAgICAg
ICAgIH0KIAogICAgICAgICBXaW5kb3cub25BY3RpdmVGb2N1c0l0ZW1DaGFuZ2VkOiB7CkBAIC01
NzEsNiArNTc0LDEyIEBAIEl0ZW0gewogICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLnRleHQK
ICAgICAgICAgfQogCisgICAgICAgIEVjbGlwc2VTeXN0ZW1TZXR0aW5ncyB7CisgICAgICAgICAg
ICB3aWR0aDogcGFyZW50LndpZHRoIC0gKHBhcmVudC5sZWZ0UGFkZGluZyArIHBhcmVudC5yaWdo
dFBhZGRpbmcpCisgICAgICAgICAgICB2aXNpYmxlOiBzZXR0aW5nc1BhZ2UuY2F0ZWdvcnkgPT09
IDYKKyAgICAgICAgICAgIGFjdGl2ZTogc2V0dGluZ3NQYWdlLnZpc2libGUgJiYgdmlzaWJsZQor
ICAgICAgICB9CisKICAgICAgICAgLy8gLS0tLSBMaXZlIHN0cmVhbSBzdW1tYXJ5IGxpbmUgKHJl
ZGVzaWduKSwgcmVsb2NhdGVkIGhlcmUgKHdhcyBpbnNpZGUgQmFzaWMKICAgICAgICAgLy8gU2V0
dGluZ3MpIHNvIGl0IHNpdHMgZGlyZWN0bHkgdW5kZXIgdGhlICJWaWRlbyIgdGl0bGUgbGlrZSB0
aGUgZGVzaWduLgogICAgICAgICAvLyBOdW1iZXJzIHJlbmRlciBpbiBhY2NlbnQ7IHRoZSByZXN0
IHN0YXlzIGRpbS4gQ29udGVudC9iaW5kaW5ncyB1bmNoYW5nZWQuCkBAIC02MDIsNyArNjExLDcg
QEAgSXRlbSB7CiAgICAgICAgICAgICB3aWR0aDogKHBhcmVudC53aWR0aCAtIChwYXJlbnQubGVm
dFBhZGRpbmcgKyBwYXJlbnQucmlnaHRQYWRkaW5nKSkKICAgICAgICAgICAgIHBhZGRpbmc6IFZi
VG9rZW5zLnNwYWNlNQogICAgICAgICAgICAgbGFiZWw6IEl0ZW0ge30KLSAgICAgICAgICAgIGJh
Y2tncm91bmQ6IFJlY3RhbmdsZSB7CisgICAgICAgICAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xh
c3NQYW5lbCB7CiAgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLmJnRWxldgogICAgICAg
ICAgICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ2FyZAogICAgICAgICAgICAgICAgIGJv
cmRlci53aWR0aDogMQpAQCAtNzU2LDcgKzc2NSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAg
ICAgICAgICAgLy8gdG93YXJkIHRoZSBjb250cm9sJ3MgaW1wbGljaXQgaGVpZ2h0LCBzbyB0aGUg
dmFsdWUgdGV4dCB1c2VkIHRvIHJlbmRlcgogICAgICAgICAgICAgICAgICAgICAgICAgLy8gcGFz
dCB0aGUgY2FyZCdzIGJvdHRvbSBlZGdlLiBTaXplIHRoZSBjYXJkIHRvIGNvbnRlbnQgKyBib3Ro
IG1hcmdpbnMuCiAgICAgICAgICAgICAgICAgICAgICAgICBpbXBsaWNpdEhlaWdodDogcmVzb2x1
dGlvbkNhcmRDb250ZW50LmltcGxpY2l0SGVpZ2h0ICsgNDgKLSAgICAgICAgICAgICAgICAgICAg
ICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7CisgICAgICAgICAgICAgICAgICAgICAgICBiYWNr
Z3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
Y29sb3I6IFZiVG9rZW5zLmJnRWxldgogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHJhZGl1
czogVmJUb2tlbnMucmFkaXVzQ2FyZAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIGJvcmRl
ci53aWR0aDogcmVzb2x1dGlvbkNvbWJvQm94LmFjdGl2ZUZvY3VzID8gVmJUb2tlbnMuZm9jdXNC
b3JkZXIgOiAxCkBAIC0xMTI1LDcgKzExMzQsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAg
ICAgICAgIC8vIFNhbWUgY29udGVudC1tYXJnaW4gc2l6aW5nIGZpeCBhcyB0aGUgUmVzb2x1dGlv
biBjYXJkIOKAlCBrZWVwcwogICAgICAgICAgICAgICAgICAgICAgICAgLy8gdGhlIGZyYW1lLXJh
dGUgdmFsdWUgdGV4dCBpbnNpZGUgdGhlIGNhcmQgYm91bmRzLgogICAgICAgICAgICAgICAgICAg
ICAgICAgaW1wbGljaXRIZWlnaHQ6IGZwc0NhcmRDb250ZW50LmltcGxpY2l0SGVpZ2h0ICsgNDgK
LSAgICAgICAgICAgICAgICAgICAgICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7CisgICAgICAg
ICAgICAgICAgICAgICAgICBiYWNrZ3JvdW5kOiBDcmltc29uR2xhc3NQYW5lbCB7CiAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLmJnRWxldgogICAgICAgICAgICAg
ICAgICAgICAgICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVzQ2FyZAogICAgICAgICAgICAg
ICAgICAgICAgICAgICAgIGJvcmRlci53aWR0aDogZnBzQ29tYm9Cb3guYWN0aXZlRm9jdXMgPyBW
YlRva2Vucy5mb2N1c0JvcmRlciA6IDEKQEAgLTE1MTMsNyArMTUyMiw3IEBAIEl0ZW0gewogICAg
ICAgICAgICAgICAgIH0KIAogICAgICAgICAgICAgICAgIC8vIC0tLS0gVmlkZW8gYml0cmF0ZSBj
YXJkIChyZWRlc2lnbikgLS0tLQotICAgICAgICAgICAgICAgIFJlY3RhbmdsZSB7CisgICAgICAg
ICAgICAgICAgQ3JpbXNvbkdsYXNzUGFuZWwgewogICAgICAgICAgICAgICAgICAgICB3aWR0aDog
cGFyZW50LndpZHRoCiAgICAgICAgICAgICAgICAgICAgIGhlaWdodDogYml0cmF0ZUNhcmRDb2x1
bW4uaW1wbGljaXRIZWlnaHQgKyA1MgogICAgICAgICAgICAgICAgICAgICByYWRpdXM6IFZiVG9r
ZW5zLnJhZGl1c0NhcmQKQEAgLTE2NzMsNyArMTY4Miw3IEBAIEl0ZW0gewogICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICBhbmNob3JzLnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGlj
YWxDZW50ZXIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgeDogYWRhcHRpdmVCaXRy
YXRlQ2hlY2suY2hlY2tlZCA/IHBhcmVudC53aWR0aCAtIHdpZHRoIC0gNCA6IDQKICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgY29sb3I6IGFkYXB0aXZlQml0cmF0ZUNoZWNrLmNoZWNr
ZWQgPyBWYlRva2Vucy50ZXh0T25BY2NlbnQgOiBWYlRva2Vucy50ZXh0RGltCi0gICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgIEJlaGF2aW9yIG9uIHggeyBOdW1iZXJBbmltYXRpb24geyBk
dXJhdGlvbjogMTIwIH0gfQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBCZWhhdmlv
ciBvbiB4IHsgTnVtYmVyQW5pbWF0aW9uIHsgZHVyYXRpb246IFZiVG9rZW5zLm1vdGlvbkVuYWJs
ZWQgPyAxMjAgOiAwIH0gfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAg
ICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgfQpAQCAtMTY4MSw3ICsxNjkw
LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAuZGVsYXk6IDEwMDAKICAg
ICAgICAgICAgICAgICAgICAgVG9vbFRpcC50aW1lb3V0OiA1MDAwCiAgICAgICAgICAgICAgICAg
ICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAotICAgICAgICAgICAgICAgICAgICBUb29sVGlw
LnRleHQ6IHFzVHIoIldoZW4gdGhlIG5ldHdvcmsgY2FuJ3Qgc3VzdGFpbiB0aGUgY29uZmlndXJl
ZCBiaXRyYXRlIGFuZCB0aGUgc3RyZWFtIGNvbGxhcHNlcywgVmliZW1pcyBhdXRvbWF0aWNhbGx5
IHJlY29ubmVjdHMgYXQgYSBsb3dlciBiaXRyYXRlIHVudGlsIHRoZSBzdHJlYW0gaXMgdXNhYmxl
LiBZb3VyIHNhdmVkIGJpdHJhdGUgc2V0dGluZyBpcyBuZXZlciBjaGFuZ2VkLiIpCisgICAgICAg
ICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiV2hlbiB0aGUgbmV0d29yayBjYW4ndCBz
dXN0YWluIHRoZSBjb25maWd1cmVkIGJpdHJhdGUgYW5kIHRoZSBzdHJlYW0gY29sbGFwc2VzLCBF
Y2xpcHNlIGF1dG9tYXRpY2FsbHkgcmVjb25uZWN0cyBhdCBhIGxvd2VyIGJpdHJhdGUgdW50aWwg
dGhlIHN0cmVhbSBpcyB1c2FibGUuIFlvdXIgc2F2ZWQgYml0cmF0ZSBzZXR0aW5nIGlzIG5ldmVy
IGNoYW5nZWQuIikKICAgICAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgICAgICAvLyBWaWJl
bWlzIChwZXJmIGd1aWRhbmNlKTogYWR2aXNlIHdoZW4gdGhlIGJpdHJhdGUgaXMgc2V0IHdlbGwg
YWJvdmUgdGhlIHJlY29tbWVuZGVkCkBAIC0xOTI5LDcgKzE5MzgsNyBAQCBJdGVtIHsKICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFyZW50
LnZlcnRpY2FsQ2VudGVyCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHg6IHZzeW5j
Q2hlY2suY2hlY2tlZCA/IHBhcmVudC53aWR0aCAtIHdpZHRoIC0gNCA6IDQKICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgY29sb3I6IHZzeW5jQ2hlY2suY2hlY2tlZCA/IFZiVG9rZW5z
LnRleHRPbkFjY2VudCA6IFZiVG9rZW5zLnRleHREaW0KLSAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgQmVoYXZpb3Igb24geCB7IE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiAxMjAg
fSB9CisgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJlaGF2aW9yIG9uIHggeyBOdW1i
ZXJBbmltYXRpb24geyBkdXJhdGlvbjogVmJUb2tlbnMubW90aW9uRW5hYmxlZCA/IDEyMCA6IDAg
fSB9CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICAg
ICAgfQogICAgICAgICAgICAgICAgICAgICB9CkBAIC0yMDI0LDcgKzIwMzMsNyBAQCBJdGVtIHsK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjog
cGFyZW50LnZlcnRpY2FsQ2VudGVyCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHg6
IGZyYW1lUGFjaW5nQ2hlY2suY2hlY2tlZCA/IHBhcmVudC53aWR0aCAtIHdpZHRoIC0gNCA6IDQK
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY29sb3I6IGZyYW1lUGFjaW5nQ2hlY2su
Y2hlY2tlZCA/IFZiVG9rZW5zLnRleHRPbkFjY2VudCA6IFZiVG9rZW5zLnRleHREaW0KLSAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgQmVoYXZpb3Igb24geCB7IE51bWJlckFuaW1hdGlv
biB7IGR1cmF0aW9uOiAxMjAgfSB9CisgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJl
aGF2aW9yIG9uIHggeyBOdW1iZXJBbmltYXRpb24geyBkdXJhdGlvbjogVmJUb2tlbnMubW90aW9u
RW5hYmxlZCA/IDEyMCA6IDAgfSB9CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAg
ICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICB9CkBAIC0yMDk2LDcg
KzIxMDUsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYW5jaG9y
cy52ZXJ0aWNhbENlbnRlcjogcGFyZW50LnZlcnRpY2FsQ2VudGVyCiAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgIHg6IHZyckNoZWNrLmNoZWNrZWQgPyBwYXJlbnQud2lkdGggLSB3aWR0
aCAtIDQgOiA0CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNvbG9yOiB2cnJDaGVj
ay5jaGVja2VkID8gVmJUb2tlbnMudGV4dE9uQWNjZW50IDogVmJUb2tlbnMudGV4dERpbQotICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICBCZWhhdmlvciBvbiB4IHsgTnVtYmVyQW5pbWF0
aW9uIHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
QmVoYXZpb3Igb24geCB7IE51bWJlckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rp
b25FbmFibGVkID8gMTIwIDogMCB9IH0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9CiAg
ICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgIH0KQEAgLTI0ODIs
NyArMjQ5MSw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLmRlbGF5OiAx
MDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGltZW91dDogNTAwMAogICAgICAgICAg
ICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKLSAgICAgICAgICAgICAgICAgICAg
VG9vbFRpcC50ZXh0OiBxc1RyKCJJZiBhIHN0cmVhbSBlbmRzIHVuZXhwZWN0ZWRseSAoYSBuZXR3
b3JrIGJsaXAgb3IgdGhlIGhvc3Qgd2FraW5nKSwgVmliZW1pcyB3aWxsIHRyeSB0byByZWNvbm5l
Y3QgYXV0b21hdGljYWxseS4iKQorICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFz
VHIoIklmIGEgc3RyZWFtIGVuZHMgdW5leHBlY3RlZGx5IChhIG5ldHdvcmsgYmxpcCBvciB0aGUg
aG9zdCB3YWtpbmcpLCBFY2xpcHNlIHdpbGwgdHJ5IHRvIHJlY29ubmVjdCBhdXRvbWF0aWNhbGx5
LiIpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgfQogICAgICAgICB9CkBAIC0yNTQ2
LDcgKzI1NTUsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5z
cGFjZTMKIAogICAgICAgICAgICAgICAgIFZiU2VjdGlvbkhlYWRlciB7Ci0gICAgICAgICAgICAg
ICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMgU3RyZWFtaW5nIEVuaGFuY2VtZW50cyIpCisgICAg
ICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkVjbGlwc2UgU3RyZWFtaW5nIEVuaGFuY2VtZW50
cyIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgTGFiZWwgewpAQCAtMjc3
Niw3ICsyNzg1LDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBWYlRvZ2dsZVJvdyB7CiAg
ICAgICAgICAgICAgICAgICAgIGlkOiBtdXRlT25Gb2N1c0xvc3NDaGVjawotICAgICAgICAgICAg
ICAgICAgICB0ZXh0OiBxc1RyKCJNdXRlIGF1ZGlvIHN0cmVhbSB3aGVuIFZpYmVtaXMgaXMgbm90
IHRoZSBhY3RpdmUgd2luZG93IikKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogcXNUcigiTXV0
ZSBhdWRpbyBzdHJlYW0gd2hlbiBFY2xpcHNlIGlzIG5vdCB0aGUgYWN0aXZlIHdpbmRvdyIpCiAg
ICAgICAgICAgICAgICAgICAgIHZpc2libGU6IFN5c3RlbVByb3BlcnRpZXMuaGFzRGVza3RvcEVu
dmlyb25tZW50CiAgICAgICAgICAgICAgICAgICAgIGNoZWNrZWQ6IFN0cmVhbWluZ1ByZWZlcmVu
Y2VzLm11dGVPbkZvY3VzTG9zcwogICAgICAgICAgICAgICAgICAgICBvbkNoZWNrZWRDaGFuZ2Vk
OiB7CkBAIC0yNzg2LDcgKzI3OTUsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9v
bFRpcC5kZWxheTogMTAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVvdXQ6IDUw
MDAKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCi0gICAgICAg
ICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiTXV0ZXMgVmliZW1pcydzIGF1ZGlvIHdo
ZW4geW91IEFsdCtUYWIgb3V0IG9mIHRoZSBzdHJlYW0gb3IgY2xpY2sgb24gYSBkaWZmZXJlbnQg
d2luZG93LiIpCisgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogcXNUcigiTXV0ZXMg
RWNsaXBzZSdzIGF1ZGlvIHdoZW4geW91IEFsdCtUYWIgb3V0IG9mIHRoZSBzdHJlYW0gb3IgY2xp
Y2sgb24gYSBkaWZmZXJlbnQgd2luZG93LiIpCiAgICAgICAgICAgICAgICAgfQogICAgICAgICAg
ICAgfQogICAgICAgICB9CkBAIC0yOTcxLDcgKzI5ODAsNyBAQCBJdGVtIHsKICAgICAgICAgICAg
ICAgICAgICAgICAgIGlmIChTdHJlYW1pbmdQcmVmZXJlbmNlcy5sYW5ndWFnZSAhPT0gbmV3X2xh
bmd1YWdlKSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgU3RyZWFtaW5nUHJlZmVyZW5j
ZXMubGFuZ3VhZ2UgPSBsYW5ndWFnZUxpc3RNb2RlbC5nZXQoY3VycmVudEluZGV4KS52YWwKICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICBpZiAoIVN0cmVhbWluZ1ByZWZlcmVuY2VzLnJldHJh
bnNsYXRlKCkpIHsKLSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5zaG93
KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQgVmliZW1pcyBmb3IgdGhpcyBjaGFuZ2UgdG8gdGFrZSBl
ZmZlY3QiKSwgNTAwMCkKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC5z
aG93KHFzVHIoIllvdSBtdXN0IHJlc3RhcnQgRWNsaXBzZSBmb3IgdGhpcyBjaGFuZ2UgdG8gdGFr
ZSBlZmZlY3QiKSwgNTAwMCkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgZWxzZSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgIC8vIEZvcmNlIHRoZSBiYWNrIG9wZXJhdGlvbiB0byBwb3AgYW55IEFwcFZpZXcgcGFnZXMg
dGhhdCBleGlzdC4KQEAgLTMwNDAsNiArMzA0OSwxMyBAQCBJdGVtIHsKICAgICAgICAgICAgICAg
ICAgICAgfQogICAgICAgICAgICAgICAgIH0KIAorICAgICAgICAgICAgICAgIExhYmVsIHsgdGV4
dDpxc1RyKCJDcmltc29uIEdsYXNzIOKAoiBCYWNrZ3JvdW5kIik7Zm9udC5waXhlbFNpemU6VmJU
b2tlbnMudHlwZUJvZHk7Y29sb3I6VmJUb2tlbnMudGV4dDtmb250LmJvbGQ6dHJ1ZSB9CisgICAg
ICAgICAgICAgICAgRmxvdyB7IHdpZHRoOnBhcmVudC53aWR0aDtzcGFjaW5nOjEyCisgICAgICAg
ICAgICAgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OnFzVHIoIkNob29zZSBiYWNr
Z3JvdW5kIik7b25DbGlja2VkOmJhY2tncm91bmRQaWNrZXIub3BlbigpIH0KKyAgICAgICAgICAg
ICAgICAgICAgRWNsaXBzZUFjdGlvbkJ1dHRvbiB7IHRleHQ6cXNUcigiUmVzZXQgYmFja2dyb3Vu
ZCIpO29uQ2xpY2tlZDpFY2xpcHNlUHJvZmlsZXMucmVzZXRCYWNrZ3JvdW5kKCkgfQorICAgICAg
ICAgICAgICAgIH0KKyAgICAgICAgICAgICAgICBMYWJlbCB7IHRleHQ6cXNUcigiQmFja2dyb3Vu
ZCBkaW1taW5nOiAlMSUiKS5hcmcoRWNsaXBzZVByb2ZpbGVzLmJhY2tncm91bmREaW0pO2ZvbnQu
cGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVMYWJlbDtjb2xvcjpWYlRva2Vucy50ZXh0IH0KKyAgICAg
ICAgICAgICAgICBTbGlkZXIgeyB3aWR0aDpwYXJlbnQud2lkdGg7ZnJvbTozMDt0bzo5MDtzdGVw
U2l6ZTo1O3ZhbHVlOkVjbGlwc2VQcm9maWxlcy5iYWNrZ3JvdW5kRGltO0FjY2Vzc2libGUubmFt
ZTpxc1RyKCJCYWNrZ3JvdW5kIGRpbW1pbmciKTtvbk1vdmVkOkVjbGlwc2VQcm9maWxlcy5iYWNr
Z3JvdW5kRGltPU1hdGgucm91bmQodmFsdWUpIH0KICAgICAgICAgICAgICAgICAvLyBCTC0yMjYz
IChTZXR0aW5ncyBJQSk6IHJlbG9jYXRlZCBmcm9tIHRoZSBHYW1lcGFkIGNhcmQgLQogICAgICAg
ICAgICAgICAgIC8vIGFwcC13aWRlIGFwcGVhcmFuY2UsIG5vdGhpbmcgZ2FtZXBhZC1zcGVjaWZp
Yy4KICAgICAgICAgICAgICAgICBMYWJlbCB7CkBAIC0zMDU1LDE0ICszMDcxLDI2IEBAIEl0ZW0g
ewogICAgICAgICAgICAgICAgICAgICB0ZXh0Um9sZTogInRleHQiCiAgICAgICAgICAgICAgICAg
ICAgIGhvdmVyRW5hYmxlZDogdHJ1ZQogICAgICAgICAgICAgICAgICAgICBtb2RlbDogTGlzdE1v
ZGVsIHsKLSAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigi
VGVhbCAoZGVmYXVsdCkiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7
IHRleHQ6IHFzVHIoIlRlYWwiKSB9CiAgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVu
dCB7IHRleHQ6IHFzVHIoIkluZGlnbyIpIH0KICAgICAgICAgICAgICAgICAgICAgICAgIExpc3RF
bGVtZW50IHsgdGV4dDogcXNUcigiR3JlZW4iKSB9CiAgICAgICAgICAgICAgICAgICAgICAgICBM
aXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIkFtYmVyIikgfQorICAgICAgICAgICAgICAgICAgICAg
ICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJDcmltc29uIChkZWZhdWx0KSIpIH0KKyAgICAg
ICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50IHsgdGV4dDogcXNUcigiUmVkIikgfQorICAg
ICAgICAgICAgICAgICAgICAgICAgTGlzdEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJPcmFuZ2UiKSB9
CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIkdvbGQi
KSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIoIkxp
bWUiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFzVHIo
Ik1pbnQiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6IHFz
VHIoIkN5YW4iKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRleHQ6
IHFzVHIoIkJsdWUiKSB9CisgICAgICAgICAgICAgICAgICAgICAgICBMaXN0RWxlbWVudCB7IHRl
eHQ6IHFzVHIoIlZpb2xldCIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVtZW50
IHsgdGV4dDogcXNUcigiUGluayIpIH0KKyAgICAgICAgICAgICAgICAgICAgICAgIExpc3RFbGVt
ZW50IHsgdGV4dDogcXNUcigiU2lsdmVyIikgfQorICAgICAgICAgICAgICAgICAgICAgICAgTGlz
dEVsZW1lbnQgeyB0ZXh0OiBxc1RyKCJSb3NlIikgfQogICAgICAgICAgICAgICAgICAgICB9CiAg
ICAgICAgICAgICAgICAgICAgIENvbXBvbmVudC5vbkNvbXBsZXRlZDogY3VycmVudEluZGV4ID0g
U3RyZWFtaW5nUHJlZmVyZW5jZXMudWlBY2NlbnRJbmRleAogICAgICAgICAgICAgICAgICAgICBv
bkFjdGl2YXRlZDogU3RyZWFtaW5nUHJlZmVyZW5jZXMudWlBY2NlbnRJbmRleCA9IGN1cnJlbnRJ
bmRleAotICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIlRoZSBhY2NlbnQg
Y29sb3IgdXNlZCBhY3Jvc3MgdGhlIHJlZGVzaWduZWQgVUkuIikKKyAgICAgICAgICAgICAgICAg
ICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJUaGUgYWNjZW50IGNvbG9yIHVzZWQgdGhyb3VnaG91dCBF
Y2xpcHNlLiIpCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAuZGVsYXk6IDEwMDAKICAgICAg
ICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3ZlcmVkCiAgICAgICAgICAgICAgICAg
fQpAQCAtMzE0Nyw3ICszMTc1LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgICAgICBU
b29sVGlwLmRlbGF5OiAxMDAwCiAgICAgICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRpbWVv
dXQ6IDUwMDAKICAgICAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJl
ZAotICAgICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJTYXZlIGFsbCBW
aWJlbWlzIHNldHRpbmdzIHRvIH4vdmliZW1pcy1zZXR0aW5ncy5pbmkgZm9yIGJhY2t1cCBvciB0
byBjb3B5IHRvIGFub3RoZXIgZGV2aWNlLiIpCisgICAgICAgICAgICAgICAgICAgICAgICBUb29s
VGlwLnRleHQ6IHFzVHIoIlNhdmUgYWxsIEVjbGlwc2Ugc2V0dGluZ3MgdG8gfi92aWJlbWlzLXNl
dHRpbmdzLmluaSBmb3IgYmFja3VwIG9yIHRvIGNvcHkgdG8gYW5vdGhlciBkZXZpY2UuIikKICAg
ICAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgICAgIEJ1dHRvbiB7CkBAIC0z
NDAyLDcgKzM0MzAsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50aW1l
b3V0OiAxMDAwMAogICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQK
ICAgICAgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJUaGlzIGVuYWJsZXMgdGhl
IGNhcHR1cmUgb2Ygc3lzdGVtLXdpZGUga2V5Ym9hcmQgc2hvcnRjdXRzIGxpa2UgQWx0K1RhYiB0
aGF0IHdvdWxkIG5vcm1hbGx5IGJlIGhhbmRsZWQgYnkgdGhlIGNsaWVudCBPUyB3aGlsZSBzdHJl
YW1pbmcuIikgKyAiXG5cbiIgKwotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHFz
VHIoIk5PVEU6IENlcnRhaW4ga2V5Ym9hcmQgc2hvcnRjdXRzIGxpa2UgQ3RybCtBbHQrRGVsIG9u
IFdpbmRvd3MgY2Fubm90IGJlIGludGVyY2VwdGVkIGJ5IGFueSBhcHBsaWNhdGlvbiwgaW5jbHVk
aW5nIFZpYmVtaXMuIikKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBxc1RyKCJO
T1RFOiBDZXJ0YWluIGtleWJvYXJkIHNob3J0Y3V0cyBsaWtlIEN0cmwrQWx0K0RlbCBvbiBXaW5k
b3dzIGNhbm5vdCBiZSBpbnRlcmNlcHRlZCBieSBhbnkgYXBwbGljYXRpb24sIGluY2x1ZGluZyBF
Y2xpcHNlLiIpCiAgICAgICAgICAgICAgICAgfQogCiAgICAgICAgICAgICAgICAgQXV0b1Jlc2l6
aW5nQ29tYm9Cb3ggewpAQCAtMzY0Myw3ICszNjcxLDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAg
ICAgICBWYlRvZ2dsZVJvdyB7CiAgICAgICAgICAgICAgICAgICAgIGlkOiBiYWNrZ3JvdW5kR2Ft
ZXBhZENoZWNrCi0gICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlByb2Nlc3MgZ2FtZXBh
ZCBpbnB1dCB3aGVuIFZpYmVtaXMgaXMgaW4gdGhlIGJhY2tncm91bmQiKQorICAgICAgICAgICAg
ICAgICAgICB0ZXh0OiBxc1RyKCJQcm9jZXNzIGdhbWVwYWQgaW5wdXQgd2hlbiBFY2xpcHNlIGlz
IGluIHRoZSBiYWNrZ3JvdW5kIikKICAgICAgICAgICAgICAgICAgICAgdmlzaWJsZTogU3lzdGVt
UHJvcGVydGllcy5oYXNEZXNrdG9wRW52aXJvbm1lbnQKICAgICAgICAgICAgICAgICAgICAgY2hl
Y2tlZDogU3RyZWFtaW5nUHJlZmVyZW5jZXMuYmFja2dyb3VuZEdhbWVwYWQKICAgICAgICAgICAg
ICAgICAgICAgb25DaGVja2VkQ2hhbmdlZDogewpAQCAtMzY1Myw3ICszNjgxLDcgQEAgSXRlbSB7
CiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAuZGVsYXk6IDEwMDAKICAgICAgICAgICAgICAg
ICAgICAgVG9vbFRpcC50aW1lb3V0OiA1MDAwCiAgICAgICAgICAgICAgICAgICAgIFRvb2xUaXAu
dmlzaWJsZTogaG92ZXJlZAotICAgICAgICAgICAgICAgICAgICBUb29sVGlwLnRleHQ6IHFzVHIo
IkFsbG93cyBWaWJlbWlzIHRvIGNhcHR1cmUgZ2FtZXBhZCBpbnB1dHMgZXZlbiBpZiBpdCdzIG5v
dCB0aGUgY3VycmVudCB3aW5kb3cgaW4gZm9jdXMiKQorICAgICAgICAgICAgICAgICAgICBUb29s
VGlwLnRleHQ6IHFzVHIoIkFsbG93cyBFY2xpcHNlIHRvIGNhcHR1cmUgZ2FtZXBhZCBpbnB1dHMg
ZXZlbiBpZiBpdCdzIG5vdCB0aGUgY3VycmVudCB3aW5kb3cgaW4gZm9jdXMiKQogICAgICAgICAg
ICAgICAgIH0KIAogICAgICAgICAgICAgICAgIFZiVG9nZ2xlUm93IHsKQEAgLTM3MjQsNyArMzc1
Miw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgIExhYmVsIHsKICAgICAgICAgICAgICAgICAg
ICAgd2lkdGg6IHBhcmVudC53aWR0aAogICAgICAgICAgICAgICAgICAgICBpZDogdXBkYXRlQ2hh
bm5lbFRpdGxlCi0gICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlNvZnR3YXJlIHVwZGF0
ZXMiKQorICAgICAgICAgICAgICAgICAgICB0ZXh0OiBBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFn
ZWQgPyBxc1RyKCJFY2xpcHNlT1MgdXBkYXRlcyIpIDogcXNUcigiU29mdHdhcmUgdXBkYXRlcyIp
CiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlTGFiZWwK
ICAgICAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRCb2R5CiAgICAg
ICAgICAgICAgICAgICAgIHdyYXBNb2RlOiBUZXh0LldyYXAKQEAgLTM3MzMsNiArMzc2MSw3IEBA
IEl0ZW0gewogCiAgICAgICAgICAgICAgICAgQXV0b1Jlc2l6aW5nQ29tYm9Cb3ggewogICAgICAg
ICAgICAgICAgICAgICBpZDogdXBkYXRlQ2hhbm5lbENvbWJvQm94CisgICAgICAgICAgICAgICAg
ICAgIHZpc2libGU6ICFBdXRvVXBkYXRlQ2hlY2tlci5vc01hbmFnZWQKICAgICAgICAgICAgICAg
ICAgICAgdGV4dFJvbGU6ICJ0ZXh0IgogICAgICAgICAgICAgICAgICAgICBtb2RlbDogTGlzdE1v
ZGVsIHsKICAgICAgICAgICAgICAgICAgICAgICAgIGlkOiB1cGRhdGVDaGFubmVsTGlzdE1vZGVs
CkBAIC0zNzg3LDYgKzM4MTYsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgLy8gaW5z
dGFsbCBpbiBmbGlnaHQgYXQgYSB0aW1lKSwgc28gYnV0dG9ucyBzdGF5IGVuYWJsZWQuCiAgICAg
ICAgICAgICAgICAgICAgIEJ1dHRvbiB7CiAgICAgICAgICAgICAgICAgICAgICAgICBpZDogY2hl
Y2tVcGRhdGVzQnV0dG9uCisgICAgICAgICAgICAgICAgICAgICAgICB2aXNpYmxlOiAhQXV0b1Vw
ZGF0ZUNoZWNrZXIub3NNYW5hZ2VkCiAgICAgICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1Ry
KCJDaGVjayBmb3IgdXBkYXRlcyIpCiAgICAgICAgICAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6
IHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBBdXRvVXBkYXRlQ2hlY2tlci5jaGVja05v
dygpCkBAIC0zODA0LDggKzM4MzQsOCBAQCBJdGVtIHsKIAogICAgICAgICAgICAgICAgICAgICBC
dXR0b24gewogICAgICAgICAgICAgICAgICAgICAgICAgaWQ6IHZpZXdSZWxlYXNlQnV0dG9uCi0g
ICAgICAgICAgICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJWaWV3IHJlbGVhc2UiKQotICAgICAg
ICAgICAgICAgICAgICAgICAgdmlzaWJsZTogQXV0b1VwZGF0ZUNoZWNrZXIub2ZmZXJBdmFpbGFi
bGUKKyAgICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IEF1dG9VcGRhdGVDaGVja2VyLm9zTWFu
YWdlZCA/IHFzVHIoIkVjbGlwc2VPUyByZWxlYXNlcyIpIDogcXNUcigiVmlldyByZWxlYXNlIikK
KyAgICAgICAgICAgICAgICAgICAgICAgIHZpc2libGU6IChBdXRvVXBkYXRlQ2hlY2tlci5vc01h
bmFnZWQgfHwgQXV0b1VwZGF0ZUNoZWNrZXIub2ZmZXJBdmFpbGFibGUpCiAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAmJiBBdXRvVXBkYXRlQ2hlY2tlci5yZWxlYXNlVXJsICE9PSAi
IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgJiYgU3lzdGVtUHJvcGVydGllcy5o
YXNCcm93c2VyCiAgICAgICAgICAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsKQEAgLTM4NDIs
NyArMzg3Miw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNw
YWNlMwogCiAgICAgICAgICAgICAgICAgVmJTZWN0aW9uSGVhZGVyIHsKLSAgICAgICAgICAgICAg
ICAgICAgdGV4dDogcXNUcigiVmliZW1pcyBGZWF0dXJlcyIpCisgICAgICAgICAgICAgICAgICAg
IHRleHQ6IHFzVHIoIkVjbGlwc2UgRmVhdHVyZXMiKQogICAgICAgICAgICAgICAgIH0KIAogICAg
ICAgICAgICAgICAgIENsaXBib2FyZFNldHRpbmdzIHsKQEAgLTM5NDcsNyArMzk3Nyw3IEBAIEl0
ZW0gewogICAgICAgICAgICAgICAgIFJlcGVhdGVyIHsKICAgICAgICAgICAgICAgICAgICAgd2lk
dGg6IHBhcmVudC53aWR0aAogICAgICAgICAgICAgICAgICAgICBtb2RlbDogWwotICAgICAgICAg
ICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJWaWJlbWlzIHZlcnNpb24iKSwgdjogU3lzdGVtUHJv
cGVydGllcy52ZXJzaW9uU3RyaW5nIH0sCisgICAgICAgICAgICAgICAgICAgICAgICB7IGs6IHFz
VHIoIkVjbGlwc2UgdmVyc2lvbiIpLCB2OiBTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcg
fSwKICAgICAgICAgICAgICAgICAgICAgICAgIHsgazogcXNUcigiQXJjaGl0ZWN0dXJlIiksICAg
IHY6IFN5c3RlbVByb3BlcnRpZXMuZnJpZW5kbHlOYXRpdmVBcmNoTmFtZSB9LAogICAgICAgICAg
ICAgICAgICAgICAgICAgeyBrOiBxc1RyKCJTdGVhbU9TIC8gZ2FtZXNjb3BlIiksIHY6IFN5c3Rl
bVByb3BlcnRpZXMuaXNTdGVhbURlY2sgPyBxc1RyKCJZZXMiKSA6IHFzVHIoIk5vIikgfSwKICAg
ICAgICAgICAgICAgICAgICAgICAgIHsgazogcXNUcigiRGlzcGxheSBzZXJ2ZXIiKSwgIHY6IFN5
c3RlbVByb3BlcnRpZXMuaXNSdW5uaW5nV2F5bGFuZCA/IChTeXN0ZW1Qcm9wZXJ0aWVzLmlzUnVu
bmluZ1hXYXlsYW5kID8gIlhXYXlsYW5kIiA6ICJXYXlsYW5kIikgOiAiWDExIiB9LApAQCAtNDAx
Myw3ICs0MDQzLDcgQEAgSXRlbSB7CiAKICAgICAgICAgICAgICAgICBMYWJlbCB7CiAgICAgICAg
ICAgICAgICAgICAgIHdpZHRoOiBwYXJlbnQud2lkdGgKLSAgICAgICAgICAgICAgICAgICAgdGV4
dDogcXNUcigiVmliZW1pcyAlMSIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLnZlcnNpb25TdHJpbmcp
CisgICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkVjbGlwc2UgJTEiKS5hcmcoU3lzdGVt
UHJvcGVydGllcy52ZXJzaW9uU3RyaW5nKQogICAgICAgICAgICAgICAgICAgICBmb250LnBpeGVs
U2l6ZTogVmJUb2tlbnMudHlwZUJvZHkKICAgICAgICAgICAgICAgICAgICAgZm9udC5ib2xkOiB0
cnVlCiAgICAgICAgICAgICAgICAgICAgIHdyYXBNb2RlOiBUZXh0LldyYXAKQEAgLTQwNTgsNyAr
NDA4OCw3IEBAIEl0ZW0gewogCiAgICAgICAgICAgICAgICAgTGFiZWwgewogICAgICAgICAgICAg
ICAgICAgICB3aWR0aDogcGFyZW50LndpZHRoCi0gICAgICAgICAgICAgICAgICAgIHRleHQ6IHFz
VHIoIlZpYmVtaXMgaXMgdGhlIExpbnV4L1N0ZWFtT1MgY2xpZW50IGZvciBBcG9sbG8gJiBTdW5z
aGluZSBob3N0cy4gVGhlc2Ugb3BlbiBpbiB5b3VyIGJyb3dzZXIuIikKKyAgICAgICAgICAgICAg
ICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBpcyB0aGUgTGludXgvU3RlYW1PUyBjbGllbnQgZm9y
IEFwb2xsbyAmIFN1bnNoaW5lIGhvc3RzLiBUaGVzZSBvcGVuIGluIHlvdXIgYnJvd3Nlci4iKQog
ICAgICAgICAgICAgICAgICAgICBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUNhcHRpb24K
ICAgICAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRCb2R5CiAgICAg
ICAgICAgICAgICAgICAgIHdyYXBNb2RlOiBUZXh0LldyYXAKQEAgLTQwNjYsNyArNDA5Niw3IEBA
IEl0ZW0gewogICAgICAgICAgICAgICAgIH0KIAogICAgICAgICAgICAgICAgIEJ1dHRvbiB7Ci0g
ICAgICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMgb24gR2l0SHViIikKKyAgICAg
ICAgICAgICAgICAgICAgdGV4dDogcXNUcigiRWNsaXBzZSBvbiBHaXRIdWIiKQogICAgICAgICAg
ICAgICAgICAgICBvbkNsaWNrZWQ6IFN5c3RlbVByb3BlcnRpZXMub3BlblVybCgiaHR0cHM6Ly9n
aXRodWIuY29tL25hdnlhczMyMS92aWJlbWlzIikKICAgICAgICAgICAgICAgICB9CiAgICAgICAg
ICAgICAgICAgQnV0dG9uIHsKZGlmZiAtLWdpdCBhL2FwcC9ndWkvU3lzdGVtQ29ubmVjdGlvbnNE
aWFsb2cucW1sIGIvYXBwL2d1aS9TeXN0ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWwKbmV3IGZpbGUg
bW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uZWM1YjU4YgotLS0gL2Rldi9udWxsCisrKyBiL2Fw
cC9ndWkvU3lzdGVtQ29ubmVjdGlvbnNEaWFsb2cucW1sCkBAIC0wLDAgKzEsMTE1IEBACitpbXBv
cnQgUXRRdWljayAyLjkKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzIDIuNQoraW1wb3J0IFF0UXVp
Y2suTGF5b3V0cyAxLjMKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1w
b3J0IFZpYmVtaXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgU3lzdGVtQ29udHJvbHMgMS4wCisKK05h
dmlnYWJsZURpYWxvZyB7CisgICAgaWQ6IHBhbmVsCisgICAgcHJvcGVydHkgc3RyaW5nIGtpbmQ6
ICJ3aWZpIgorICAgIHByb3BlcnR5IHZhciBzZWxlY3RlZDogKHt9KQorICAgIHdpZHRoOiBNYXRo
Lm1pbig2MjAsIHBhcmVudC53aWR0aCAtIDMyKQorICAgIGhlaWdodDogTWF0aC5taW4oNTYwLCBw
YXJlbnQuaGVpZ2h0IC0gMzIpCisgICAgdGl0bGU6IGtpbmQgPT09ICJ3aWZpIiA/IHFzVHIoIldp
LUZpIG5ldHdvcmtzIikgOiBxc1RyKCJCbHVldG9vdGggZGV2aWNlcyIpCisgICAgc3RhbmRhcmRC
dXR0b25zOiBEaWFsb2cuQ2xvc2UKKyAgICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5i
Z0VsZXYKKyAgICBNYXRlcmlhbC5hY2NlbnQ6IFZiVG9rZW5zLmFjY2VudAorICAgIGJhY2tncm91
bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsgY29sb3I6IFZiVG9rZW5zLmJnRWxldjsgcmFkaXVzOiBW
YlRva2Vucy5yYWRpdXNEaWFsb2c7IGJvcmRlci5jb2xvcjogVmJUb2tlbnMuc3Ryb2tlIH0KKyAg
ICBvbk9wZW5lZDogeyBzZWxlY3RlZCA9ICh7fSk7IFN5c3RlbUNvbnRyb2xzLm9wZW4oa2luZCkg
fQorICAgIG9uQ2xvc2VkOiB7IGNyZWRlbnRpYWwuY2xvc2UoKTsgc2VjcmV0LnRleHQgPSAiIjsg
Zm9yZ2V0LmNsb3NlKCk7IFN5c3RlbUNvbnRyb2xzLmNsb3NlKCkgfQorICAgIGNvbnRlbnRJdGVt
OiBDb2x1bW5MYXlvdXQgeworICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTMKKyAgICAg
ICAgUm93TGF5b3V0IHsKKyAgICAgICAgICAgIExheW91dC5maWxsV2lkdGg6IHRydWUKKyAgICAg
ICAgICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7IGZvbnQucGl4ZWxT
aXplOlZiVG9rZW5zLnR5cGVCb2R5OyBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlOyB3cmFwTW9kZTog
VGV4dC5XcmFwOyB0ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgdGV4dDogU3lzdGVtQ29udHJv
bHMuc3RhdHVzOyBjb2xvcjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgICAgICBCdXN5SW5k
aWNhdG9yIHsgcnVubmluZzogU3lzdGVtQ29udHJvbHMuYnVzeTsgdmlzaWJsZTogcnVubmluZzsg
aW1wbGljaXRXaWR0aDogMzI7IGltcGxpY2l0SGVpZ2h0OiAzMiB9CisgICAgICAgICAgICBFY2xp
cHNlQWN0aW9uQnV0dG9uIHsgaWQ6IHNjYW5CdXR0b247IHRleHQ6IHFzVHIoIlNjYW4iKTsgZW5h
YmxlZDogIVN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDogeyBwYW5lbC5zZWxlY3RlZCA9
ICh7fSk7IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QocGFuZWwua2luZCArICItc2NhbiIpIH0gfQor
ICAgICAgICB9CisgICAgICAgIEVjbGlwc2VBY3Rpb25CdXR0b24geyB0ZXh0OiBxc1RyKCJDYW5j
ZWwgb3BlcmF0aW9uIik7IHZpc2libGU6IFN5c3RlbUNvbnRyb2xzLmJ1c3k7IG9uQ2xpY2tlZDog
eyBTeXN0ZW1Db250cm9scy5jbG9zZSgpOyBwYW5lbC5zZWxlY3RlZD0oe30pOyByZW9wZW4ucmVz
dGFydCgpIH0gfQorICAgICAgICBUaW1lciB7IGlkOiByZW9wZW47IGludGVydmFsOiA2MDA7IG9u
VHJpZ2dlcmVkOiBpZihwYW5lbC5vcGVuZWQpIFN5c3RlbUNvbnRyb2xzLm9wZW4ocGFuZWwua2lu
ZCkgfQorICAgICAgICBUaW1lciB7IGludGVydmFsOjUwMDA7IHJlcGVhdDp0cnVlOyBydW5uaW5n
OnBhbmVsLm9wZW5lZCAmJiBwYW5lbC5raW5kPT09ImJ0IiAmJiAhU3lzdGVtQ29udHJvbHMuYnVz
eSAmJiAhY3JlZGVudGlhbC5vcGVuZWQ7IG9uVHJpZ2dlcmVkOlN5c3RlbUNvbnRyb2xzLnJlcXVl
c3QoImJ0LWxpc3QiKSB9CisgICAgICAgIExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9u
dEJvZHk7IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OworICAgICAgICAgICAgTGF5
b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1vZGU6IFRleHQuV3JhcDsgY29sb3I6IFZiVG9rZW5z
LnRleHREaW0KKyAgICAgICAgICAgIHRleHQ6IHBhbmVsLmtpbmQgPT09ICJ3aWZpIiA/IHFzVHIo
IlNlbGVjdCBhIG5ldHdvcmssIHRoZW4gQ29ubmVjdC4gQWR2YW5jZWQgb3IgaGlkZGVuIG5ldHdv
cmtzIGFyZSBhdmFpbGFibGUgaW4gdGhlIGRpYWdub3N0aWMgc2hlbGwuIikgOiBxc1RyKCJQdXQg
eW91ciBjb250cm9sbGVyIG9yIGhlYWRwaG9uZXMgaW4gcGFpcmluZyBtb2RlLCB0aGVuIFNjYW4u
IERldmljZXMgYXBwZWFyIGR1cmluZyBzY2FubmluZy4gU2F2ZWQgZGV2aWNlcyBhcmUgbGlzdGVk
IHdpdGhvdXQgc2Nhbm5pbmcuIikKKyAgICAgICAgfQorICAgICAgICBMaXN0VmlldyB7CisgICAg
ICAgICAgICBpZDogZGV2aWNlcworICAgICAgICAgICAgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsg
TGF5b3V0LmZpbGxIZWlnaHQ6IHRydWUKKyAgICAgICAgICAgIGNsaXA6IHRydWU7IHNwYWNpbmc6
IDQ7IG1vZGVsOiBTeXN0ZW1Db250cm9scy5pdGVtcworICAgICAgICAgICAgU2Nyb2xsQmFyLnZl
cnRpY2FsOiBTY3JvbGxCYXIge30KKyAgICAgICAgICAgIGRlbGVnYXRlOiBJdGVtRGVsZWdhdGUg
eworICAgICAgICAgICAgICAgIHdpZHRoOiBkZXZpY2VzLndpZHRoCisgICAgICAgICAgICAgICAg
aW1wbGljaXRIZWlnaHQ6IE1hdGgubWF4KDQ0LGNvbnRlbnRJdGVtLmltcGxpY2l0SGVpZ2h0KzI0
KQorICAgICAgICAgICAgICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7IGNvbG9yOnBhcmVudC5o
aWdobGlnaHRlZCB8fCBwYXJlbnQuaG92ZXJlZCA/IFZiVG9rZW5zLmJnRWxldjIgOiBWYlRva2Vu
cy5iZ0VsZXY7IHJhZGl1czpWYlRva2Vucy5yYWRpdXNDb250cm9sOyBib3JkZXIuY29sb3I6cGFy
ZW50LmFjdGl2ZUZvY3VzP1ZiVG9rZW5zLmFjY2VudDpWYlRva2Vucy5zdHJva2UgfQorICAgICAg
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
ICAgICAgY29udGVudEl0ZW06IExhYmVsIHsgZm9udC5mYW1pbHk6VmJUb2tlbnMuZm9udEJvZHk7
IGZvbnQucGl4ZWxTaXplOlZiVG9rZW5zLnR5cGVCb2R5OworICAgICAgICAgICAgICAgICAgICB0
ZXh0Rm9ybWF0OiBUZXh0LlBsYWluVGV4dDsgZWxpZGU6IFRleHQuRWxpZGVSaWdodDsgY29sb3I6
IFZiVG9rZW5zLnRleHQKKyAgICAgICAgICAgICAgICAgICAgdGV4dDogbW9kZWxEYXRhLm5hbWUg
KyAiIMK3ICIgKyBtb2RlbERhdGEuZGV0YWlsICsgKG1vZGVsRGF0YS5jb25uZWN0ZWQgPyAiIMK3
ICIgKyBxc1RyKCJDb25uZWN0ZWQiKSA6ICIiKQorICAgICAgICAgICAgICAgIH0KKyAgICAgICAg
ICAgICAgICBvbkNsaWNrZWQ6IHsgcGFuZWwuc2VsZWN0ZWQgPSBtb2RlbERhdGE7IGRldmljZXMu
Y3VycmVudEluZGV4ID0gaW5kZXggfQorICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgICAg
IFJvd0xheW91dCB7CisgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCisgICAgICAg
ICAgICBFY2xpcHNlQWN0aW9uQnV0dG9uIHsKKyAgICAgICAgICAgICAgICBpZDogY29ubmVjdEJ1
dHRvbgorICAgICAgICAgICAgICAgIHRleHQ6IHBhbmVsLmtpbmQgPT09ICJ3aWZpIiA/IHFzVHIo
IkNvbm5lY3QiKSA6IHFzVHIoIlBhaXIgLyBDb25uZWN0IikKKyAgICAgICAgICAgICAgICBlbmFi
bGVkOiAhIXBhbmVsLnNlbGVjdGVkLmlkICYmICFTeXN0ZW1Db250cm9scy5idXN5CisgICAgICAg
ICAgICAgICAgb25DbGlja2VkOiBTeXN0ZW1Db250cm9scy5yZXF1ZXN0KHBhbmVsLmtpbmQgKyAi
LWNvbm5lY3QiLCBwYW5lbC5zZWxlY3RlZC5pZCkKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAg
IEVjbGlwc2VBY3Rpb25CdXR0b24geworICAgICAgICAgICAgICAgIHRleHQ6IHFzVHIoIkRpc2Nv
bm5lY3QiKTsgZW5hYmxlZDogISFwYW5lbC5zZWxlY3RlZC5pZCAmJiBwYW5lbC5zZWxlY3RlZC5j
b25uZWN0ZWQgJiYgIVN5c3RlbUNvbnRyb2xzLmJ1c3kKKyAgICAgICAgICAgICAgICBvbkNsaWNr
ZWQ6IFN5c3RlbUNvbnRyb2xzLnJlcXVlc3QocGFuZWwua2luZCArICItZGlzY29ubmVjdCIsIHBh
bmVsLnNlbGVjdGVkLmlkKQorICAgICAgICAgICAgfQorICAgICAgICAgICAgRWNsaXBzZUFjdGlv
bkJ1dHRvbiB7IHRleHQ6IHFzVHIoIkZvcmdldCIpOyB2aXNpYmxlOiBwYW5lbC5raW5kID09PSAi
YnQiOyBlbmFibGVkOiAhIXBhbmVsLnNlbGVjdGVkLmlkICYmICFTeXN0ZW1Db250cm9scy5idXN5
OyBvbkNsaWNrZWQ6IGZvcmdldC5vcGVuKCkgfQorICAgICAgICB9CisgICAgfQorICAgIENvbm5l
Y3Rpb25zIHsKKyAgICAgICAgdGFyZ2V0OiBTeXN0ZW1Db250cm9scworICAgICAgICBmdW5jdGlv
biBvbkNoYW5nZWQoKSB7CisgICAgICAgICAgICBpZiAoU3lzdGVtQ29udHJvbHMucHJvbXB0Lmxl
bmd0aCA+IDAgJiYgcGFuZWwub3BlbmVkICYmICFjcmVkZW50aWFsLm9wZW5lZCkgY3JlZGVudGlh
bC5vcGVuKCkKKyAgICAgICAgICAgIGlmICghU3lzdGVtQ29udHJvbHMuYnVzeSkgeworICAgICAg
ICAgICAgICAgIGNyZWRlbnRpYWwuY2xvc2UoKTsgc2VjcmV0LnRleHQgPSAiIgorICAgICAgICAg
ICAgICAgIHZhciBpZCA9IHBhbmVsLnNlbGVjdGVkLmlkCisgICAgICAgICAgICAgICAgcGFuZWwu
c2VsZWN0ZWQgPSAoe30pCisgICAgICAgICAgICAgICAgZm9yICh2YXIgaSA9IDA7IGkgPCBTeXN0
ZW1Db250cm9scy5pdGVtcy5sZW5ndGg7IGkrKykKKyAgICAgICAgICAgICAgICAgICAgaWYgKFN5
c3RlbUNvbnRyb2xzLml0ZW1zW2ldLmlkID09PSBpZCkgcGFuZWwuc2VsZWN0ZWQgPSBTeXN0ZW1D
b250cm9scy5pdGVtc1tpXQorICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQorICAgIE5h
dmlnYWJsZURpYWxvZyB7CisgICAgICAgIGlkOiBjcmVkZW50aWFsCisgICAgICAgIG9iamVjdE5h
bWU6ICJjb25uZWN0aW9uQ3JlZGVudGlhbCIKKyAgICAgICAgdGl0bGU6IHFzVHIoIkNvbm5lY3Rp
b24gYXV0aGVudGljYXRpb24iKQorICAgICAgICB3aWR0aDogTWF0aC5taW4oNDgwLCBwYW5lbC53
aWR0aCkKKyAgICAgICAgY2xvc2VQb2xpY3k6IFBvcHVwLk5vQXV0b0Nsb3NlCisgICAgICAgIHN0
YW5kYXJkQnV0dG9uczogRGlhbG9nLk9rIHwgRGlhbG9nLkNhbmNlbAorICAgICAgICBNYXRlcmlh
bC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAgICAgb25PcGVuZWQ6IHsgc2VjcmV0
LnRleHQgPSAiIjsgc2VjcmV0LmZvcmNlQWN0aXZlRm9jdXMoKSB9CisgICAgICAgIG9uQWNjZXB0
ZWQ6IHsgU3lzdGVtQ29udHJvbHMuYW5zd2VyKHNlY3JldC50ZXh0KTsgc2VjcmV0LnRleHQgPSAi
IiB9CisgICAgICAgIG9uUmVqZWN0ZWQ6IHsgc2VjcmV0LnRleHQgPSAiIjsgU3lzdGVtQ29udHJv
bHMuY2xvc2UoKTsgcmVvcGVuLnJlc3RhcnQoKSB9CisgICAgICAgIGNvbnRlbnRJdGVtOiBDb2x1
bW5MYXlvdXQgeworICAgICAgICAgICAgTGFiZWwgeyBmb250LmZhbWlseTpWYlRva2Vucy5mb250
Qm9keTsgZm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHk7IExheW91dC5maWxsV2lkdGg6
IHRydWU7IHRleHRGb3JtYXQ6IFRleHQuUGxhaW5UZXh0OyB3cmFwTW9kZTogVGV4dC5XcmFwOyB0
ZXh0OiBTeXN0ZW1Db250cm9scy5wcm9tcHQ7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0KKyAgICAg
ICAgICAgIFRleHRGaWVsZCB7IGlkOiBzZWNyZXQ7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRC
b2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDog
dHJ1ZTsgZWNob01vZGU6IFRleHRJbnB1dC5QYXNzd29yZDsgbWF4aW11bUxlbmd0aDogNDA5Njsg
c2VsZWN0QnlNb3VzZTogdHJ1ZTsgb25BY2NlcHRlZDogY3JlZGVudGlhbC5hY2NlcHQoKSB9Cisg
ICAgICAgICAgICBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5zLmZvbnRCb2R5OyBmb250LnBp
eGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgTGF5b3V0LmZpbGxXaWR0aDogdHJ1ZTsgd3JhcE1v
ZGU6IFRleHQuV3JhcDsgdGV4dDogcXNUcigiRW50ZXIgdGhlIHJlcXVlc3RlZCBwYXNzd29yZCBv
ciBQSU4uIEZvciBhIHllcy9ubyBjb25maXJtYXRpb24sIHR5cGUgeWVzIG9yIG5vLiIpOyBjb2xv
cjogVmJUb2tlbnMudGV4dERpbSB9CisgICAgICAgIH0KKyAgICB9CisgICAgTmF2aWdhYmxlRGlh
bG9nIHsKKyAgICAgICAgaWQ6IGZvcmdldAorICAgICAgICBpbXBsaWNpdEhlaWdodDogY29udGVu
dEl0ZW0uY29udGVudEhlaWdodCArIGhlYWRlci5pbXBsaWNpdEhlaWdodCArIGZvb3Rlci5pbXBs
aWNpdEhlaWdodCArIHRvcFBhZGRpbmcgKyBib3R0b21QYWRkaW5nCisgICAgICAgIG9iamVjdE5h
bWU6ICJjb25uZWN0aW9uRm9yZ2V0IgorICAgICAgICB0aXRsZTogcXNUcigiRm9yZ2V0IEJsdWV0
b290aCBkZXZpY2U/IikKKyAgICAgICAgd2lkdGg6IE1hdGgubWluKDQ4MCwgcGFuZWwud2lkdGgp
CisgICAgICAgIHN0YW5kYXJkQnV0dG9uczogRGlhbG9nLlllcyB8IERpYWxvZy5ObworICAgICAg
ICBNYXRlcmlhbC5iYWNrZ3JvdW5kOiBWYlRva2Vucy5iZ0VsZXYKKyAgICAgICAgb25BY2NlcHRl
ZDogU3lzdGVtQ29udHJvbHMucmVxdWVzdCgiYnQtZm9yZ2V0IiwgcGFuZWwuc2VsZWN0ZWQuaWQs
IHRydWUpCisgICAgICAgIGNvbnRlbnRJdGVtOiBMYWJlbCB7IGZvbnQuZmFtaWx5OlZiVG9rZW5z
LmZvbnRCb2R5OyBmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlQm9keTsgdGV4dEZvcm1hdDog
VGV4dC5QbGFpblRleHQ7IHdyYXBNb2RlOiBUZXh0LldyYXA7IHRleHQ6IHFzVHIoIlJlbW92ZSB0
aGUgc2F2ZWQgcGFpcmluZyBmb3IgJTE/IFlvdSB3aWxsIG5lZWQgdG8gcGFpciBpdCBhZ2Fpbi4i
KS5hcmcocGFuZWwuc2VsZWN0ZWQubmFtZSB8fCAiIik7IGNvbG9yOiBWYlRva2Vucy50ZXh0IH0K
KyAgICB9Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1RoZW1lLnFtbCBiL2FwcC9ndWkvVGhlbWUu
cW1sCmluZGV4IGZiOTFjODUuLjU3YzlmODQgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVGhlbWUucW1s
CisrKyBiL2FwcC9ndWkvVGhlbWUucW1sCkBAIC0xMSwyMCArMTEsMjAgQEAgaW1wb3J0IFZpYmVt
aXMuUmVkZXNpZ24gMS4wCiBRdE9iamVjdCB7CiAgICAgLy8gLS0tLSBDb2xvciAtLS0tCiAgICAg
cmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50OiAgICAgICAgVmJUb2tlbnMuYWNjZW50ICAv
LyBCTC0yMDc3OiBzaW5nbGUgc291cmNlIG9mIHRydXRoIChWYlRva2VucyBicmFuZCBhY2NlbnQs
IGRlZmF1bHQgIzAwQ0NDQykKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVz
c2VkOiAiIzAwQTNBMyIKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiYWNrZ3JvdW5kOiAg
ICAiIzMwMzAzMCIgIC8vIGFwcCByb290Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Vy
ZmFjZTogICAgICAgIiMyRDJEMkQiICAvLyByYWlzZWQgc3VyZmFjZXMgLyBvdmVybGF5cwotICAg
IHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZhY2VBbHQ6ICAgICIjNDI0MjQyIiAgLy8gcG9w
dXBzIC8gY29tYm8gZHJvcGRvd25zCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYm9yZGVy
OiAgICAgICAgIiM0NDQ0NDQiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFByaW1h
cnk6ICAgIiNGRkZGRkYiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFNlY29uZGFy
eTogIiNDQ0NDQ0MiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFRlcnRpYXJ5OiAg
IiNBQUFBQUEiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERpc2FibGVkOiAgIiM3
Nzc3NzciCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3VjY2VzczogICAgICAgIiM0Q0FG
NTAiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igd2FybmluZzogICAgICAgIiNFMEEwMzAi
ICAvLyB0aGUgc2luZ2xlIGFtYmVyCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZXJyb3I6
ICAgICAgICAgIiNGNDQzMzYiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW5mbzogICAg
ICAgICAgIiM4MEEwQzAiCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc2NyaW06ICAgICAg
ICAgIiNEMDAwMDAwMCIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBhY2NlbnRQcmVzc2Vk
OiBWYlRva2Vucy5hY2NlbnRQcmVzc2VkCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmFj
a2dyb3VuZDogICAgVmJUb2tlbnMuYmdXaW5kb3cgIC8vIGFwcCByb290CisgICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3Igc3VyZmFjZTogICAgICAgVmJUb2tlbnMuYmdFbGV2ICAvLyByYWlzZWQg
c3VyZmFjZXMgLyBvdmVybGF5cworICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHN1cmZhY2VB
bHQ6ICAgIFZiVG9rZW5zLmJnRWxldjIgIC8vIHBvcHVwcyAvIGNvbWJvIGRyb3Bkb3ducworICAg
IHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJvcmRlcjogICAgICAgIFZiVG9rZW5zLnN0cm9rZQor
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRQcmltYXJ5OiAgIFZiVG9rZW5zLnRleHRQ
cmltYXJ5CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dFNlY29uZGFyeTogVmJUb2tl
bnMudGV4dFNlY29uZGFyeQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHRUZXJ0aWFy
eTogIFZiVG9rZW5zLnRleHRUZXJ0aWFyeQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRl
eHREaXNhYmxlZDogIFZiVG9rZW5zLnRleHREaXNhYmxlZAorICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIHN1Y2Nlc3M6ICAgICAgIFZiVG9rZW5zLnN0YXR1c1N1Y2Nlc3MKKyAgICByZWFkb25s
eSBwcm9wZXJ0eSBjb2xvciB3YXJuaW5nOiAgICAgICBWYlRva2Vucy5zdGF0dXNXYXJuaW5nICAv
LyB0aGUgc2luZ2xlIGFtYmVyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgZXJyb3I6ICAg
ICAgICAgVmJUb2tlbnMuc3RhdHVzRGFuZ2VyCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
aW5mbzogICAgICAgICAgVmJUb2tlbnMuc3RhdHVzSW5mbworICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIHNjcmltOiAgICAgICAgIFZiVG9rZW5zLmRpYWxvZ1NjcmltCiAKICAgICAvLyAtLS0t
IFR5cG9ncmFwaHkgKHBvaW50U2l6ZTsgcGFpciB3aXRoIGJvbGQgd2hlcmUgbm90ZWQgaW4gREVT
SUdOX1NZU1RFTS5tZCkgLS0tLQogICAgIHJlYWRvbmx5IHByb3BlcnR5IGludCBmb250RGlzcGxh
eTogMjQgIC8vIG92ZXJsYXkvUXVpY2sgTWVudSB0aXRsZSAoYm9sZCkKZGlmZiAtLWdpdCBhL2Fw
cC9ndWkvVmJDYXJkLnFtbCBiL2FwcC9ndWkvVmJDYXJkLnFtbAppbmRleCAzN2YyZTMyLi4xYzk3
MTBkIDEwMDY0NAotLS0gYS9hcHAvZ3VpL1ZiQ2FyZC5xbWwKKysrIGIvYXBwL2d1aS9WYkNhcmQu
cW1sCkBAIC0xOSwxNSArMTksMTkgQEAgSXRlbSB7CiAgICAgICAgIHJhZGl1czogY2FyZC5yYWRp
dXMKICAgICB9CiAKLSAgICBSZWN0YW5nbGUgeworICAgIENyaW1zb25HbGFzc1BhbmVsIHsKICAg
ICAgICAgaWQ6IHN1cmZhY2UKICAgICAgICAgYW5jaG9ycy5maWxsOiBwYXJlbnQKICAgICAgICAg
cmFkaXVzOiBjYXJkLnJhZGl1cwogICAgICAgICBjb2xvcjogY2FyZC5mb2N1c2VkID8gVmJUb2tl
bnMuZm9jdXNlZEZpbGwgOiBjYXJkLmJhc2VDb2xvcgorICAgICAgICBncmFkaWVudDogR3JhZGll
bnQgeworICAgICAgICAgICAgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246MDtjb2xvcjpjYXJkLmZv
Y3VzZWQgPyBWYlRva2Vucy5iZ0VsZXYyIDogVmJUb2tlbnMuZ2xhc3NUb3AgfQorICAgICAgICAg
ICAgR3JhZGllbnRTdG9wIHsgcG9zaXRpb246MTtjb2xvcjpjYXJkLmZvY3VzZWQgPyBWYlRva2Vu
cy5mb2N1c2VkRmlsbCA6IGNhcmQuYmFzZUNvbG9yIH0KKyAgICAgICAgfQogICAgICAgICBib3Jk
ZXIud2lkdGg6IDEKICAgICAgICAgYm9yZGVyLmNvbG9yOiBWYlRva2Vucy5zdHJva2UKICAgICAg
ICAgb3BhY2l0eTogY2FyZC5jb250ZW50T3BhY2l0eQotICAgICAgICBCZWhhdmlvciBvbiBjb2xv
ciB7IENvbG9yQW5pbWF0aW9uIHsgZHVyYXRpb246IDEyMCB9IH0KKyAgICAgICAgQmVoYXZpb3Ig
b24gY29sb3IgeyBDb2xvckFuaW1hdGlvbiB7IGR1cmF0aW9uOiBWYlRva2Vucy5tb3Rpb25FbmFi
bGVkID8gMTIwIDogMCB9IH0KICAgICB9CiAKICAgICBJdGVtIHsKZGlmZiAtLWdpdCBhL2FwcC9n
dWkvVmJIb3N0Q2FyZC5xbWwgYi9hcHAvZ3VpL1ZiSG9zdENhcmQucW1sCmluZGV4IDllMWZlN2Yu
LjlkYmE2YTYgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvVmJIb3N0Q2FyZC5xbWwKKysrIGIvYXBwL2d1
aS9WYkhvc3RDYXJkLnFtbApAQCAtMjksNyArMjksNyBAQCBJdGVtIHsKICAgICAgICAgcmFkaXVz
OiAyMAogICAgIH0KIAotICAgIFJlY3RhbmdsZSB7CisgICAgQ3JpbXNvbkdsYXNzUGFuZWwgewog
ICAgICAgICBpZDogc3VyZmFjZQogICAgICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAogICAgICAg
ICByYWRpdXM6IDIwCkBAIC00NSwyMCArNDUsMjAgQEAgSXRlbSB7CiAKICAgICAgICAgQ29sdW1u
TGF5b3V0IHsKICAgICAgICAgICAgIGFuY2hvcnMuZmlsbDogcGFyZW50Ci0gICAgICAgICAgICBh
bmNob3JzLm1hcmdpbnM6IDMyCisgICAgICAgICAgICBhbmNob3JzLm1hcmdpbnM6IDI0CiAgICAg
ICAgICAgICAvLyBSZXNlcnZlIHRoZSBib3R0b20gc3RyaXAgZm9yIHRoZSBhbmNob3JlZCBiYWRn
ZS9tZXRhIHJvdyBiZWxvdy4gVGhlIG9sZAogICAgICAgICAgICAgLy8gc2luZ2xlLWNvbHVtbiBm
bG93IG92ZXJmbG93ZWQgdGhlIGZpeGVkIDI0MnB4IGNhcmQgYnkgfjExcHggd2l0aCByZWFsIGRl
dmljZSBmb250cwogICAgICAgICAgICAgLy8gKDMyKzU4KzIwK25hbWUrNithY2Nlc3MrMjArYmFk
Z2UrMzIgPiAyNDIpLCBzaG92aW5nIHRoZSBiYWRnZSByb3cgb250byB0aGUgYm9yZGVyLgogICAg
ICAgICAgICAgYW5jaG9ycy5ib3R0b21NYXJnaW46IDY0Ci0gICAgICAgICAgICBzcGFjaW5nOiAy
MAorICAgICAgICAgICAgc3BhY2luZzogMTQKIAogICAgICAgICAgICAgLy8gLS0tLSBSb3cgMTog
bW9uaXRvciBvdXRsaW5lICsgc3RhdHVzIHBpbGwgLS0tLQogICAgICAgICAgICAgUm93TGF5b3V0
IHsKICAgICAgICAgICAgICAgICBMYXlvdXQuZmlsbFdpZHRoOiB0cnVlCiAgICAgICAgICAgICAg
ICAgLy8gTW9uaXRvcjogYW4gODLDlzU4IHJvdW5kZWQgcmVjdGFuZ2xlIGRyYXduIGFzIGEgNXB4
IG91dGxpbmUgKG5vIGZpbGwpLCBsaWtlIHRoZSBIVE1MLgogICAgICAgICAgICAgICAgIFJlY3Rh
bmdsZSB7Ci0gICAgICAgICAgICAgICAgICAgIExheW91dC5wcmVmZXJyZWRXaWR0aDogODIKLSAg
ICAgICAgICAgICAgICAgICAgTGF5b3V0LnByZWZlcnJlZEhlaWdodDogNTgKKyAgICAgICAgICAg
ICAgICAgICAgTGF5b3V0LnByZWZlcnJlZFdpZHRoOiA2NAorICAgICAgICAgICAgICAgICAgICBM
YXlvdXQucHJlZmVycmVkSGVpZ2h0OiA0OAogICAgICAgICAgICAgICAgICAgICByYWRpdXM6IDEw
CiAgICAgICAgICAgICAgICAgICAgIGNvbG9yOiAidHJhbnNwYXJlbnQiCiAgICAgICAgICAgICAg
ICAgICAgIGJvcmRlci53aWR0aDogNQpAQCAtODUsNyArODUsNyBAQCBJdGVtIHsKICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICBjb2xvcjogY2FyZC5vbmxpbmUgPyBWYlRva2Vucy5zdGF0dXNP
bmxpbmUKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiAo
Y2FyZC5zdGF0dXNVbmtub3duID8gVmJUb2tlbnMudGV4dERpbSA6ICIjNUE2MjZDIikKICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICBTZXF1ZW50aWFsQW5pbWF0aW9uIG9uIG9wYWNpdHkgewot
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBydW5uaW5nOiBjYXJkLm9ubGluZSB8fCBj
YXJkLnN0YXR1c1Vua25vd24KKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcnVubmlu
ZzogVmJUb2tlbnMubW90aW9uRW5hYmxlZCAmJiAoY2FyZC5vbmxpbmUgfHwgY2FyZC5zdGF0dXNV
bmtub3duKQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBsb29wczogQW5pbWF0aW9u
LkluZmluaXRlCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIE51bWJlckFuaW1hdGlv
biB7IGZyb206IDEuMDsgdG86IDAuNDU7IGR1cmF0aW9uOiBWYlRva2Vucy5vbmxpbmVQdWxzZU1z
IC8gMiB9CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIE51bWJlckFuaW1hdGlvbiB7
IGZyb206IDAuNDU7IHRvOiAxLjA7IGR1cmF0aW9uOiBWYlRva2Vucy5vbmxpbmVQdWxzZU1zIC8g
MiB9CkBAIC05Niw3ICs5Niw3IEBAIEl0ZW0gewogICAgICAgICAgICAgICAgICAgICAgICAgICAg
IHRleHQ6IGNhcmQub25saW5lID8gcXNUcigiT05MSU5FIikKICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICA6IChjYXJkLnN0YXR1c1Vua25vd24gPyBxc1RyKCJD
SEVDS0lORyIpIDogcXNUcigiT0ZGTElORSIpKQogICAgICAgICAgICAgICAgICAgICAgICAgICAg
IGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250Qm9keQotICAgICAgICAgICAgICAgICAgICAgICAg
ICAgIGZvbnQucGl4ZWxTaXplOiAxNAorICAgICAgICAgICAgICAgICAgICAgICAgICAgIGZvbnQu
cGl4ZWxTaXplOiBWYlRva2Vucy50eXBlTGFiZWwKICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICBmb250LndlaWdodDogRm9udC5Cb2xkCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZm9u
dC5sZXR0ZXJTcGFjaW5nOiAwLjcKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb2xvcjog
Y2FyZC5vbmxpbmUgPyBWYlRva2Vucy5zdGF0dXNPbmxpbmUgOiBWYlRva2Vucy50ZXh0RGltCkBA
IC0xMTQsNyArMTE0LDcgQEAgSXRlbSB7CiAgICAgICAgICAgICAgICAgICAgIHRleHQ6IGNhcmQu
aG9zdE5hbWUKICAgICAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZvbnRE
aXNwbGF5CiAgICAgICAgICAgICAgICAgICAgIGZvbnQud2VpZ2h0OiBGb250LkJvbGQKLSAgICAg
ICAgICAgICAgICAgICAgZm9udC5waXhlbFNpemU6IDI3CisgICAgICAgICAgICAgICAgICAgIGZv
bnQucGl4ZWxTaXplOiBWYlRva2Vucy50eXBlSGVhZGluZwogICAgICAgICAgICAgICAgICAgICBj
b2xvcjogY2FyZC5vbmxpbmUgPyBWYlRva2Vucy50ZXh0IDogVmJUb2tlbnMudGV4dE11dGUKICAg
ICAgICAgICAgICAgICAgICAgZWxpZGU6IFRleHQuRWxpZGVSaWdodAogICAgICAgICAgICAgICAg
IH0KQEAgLTEyMyw3ICsxMjMsNyBAQCBJdGVtIHsKICAgICAgICAgICAgICAgICAgICAgdGV4dDog
Y2FyZC5hY2Nlc3NUZXh0CiAgICAgICAgICAgICAgICAgICAgIHZpc2libGU6IGNhcmQuYWNjZXNz
VGV4dCAhPT0gIiIKICAgICAgICAgICAgICAgICAgICAgZm9udC5mYW1pbHk6IFZiVG9rZW5zLmZv
bnRCb2R5Ci0gICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiAxNworICAgICAgICAg
ICAgICAgICAgICBmb250LnBpeGVsU2l6ZTogVmJUb2tlbnMudHlwZUxhYmVsCiAgICAgICAgICAg
ICAgICAgICAgIGNvbG9yOiBWYlRva2Vucy50ZXh0RGltCiAgICAgICAgICAgICAgICAgICAgIGVs
aWRlOiBUZXh0LkVsaWRlUmlnaHQKICAgICAgICAgICAgICAgICB9CkBAIC0xMzksOCArMTM5LDgg
QEAgSXRlbSB7CiAgICAgICAgICAgICBhbmNob3JzLmxlZnQ6IHBhcmVudC5sZWZ0CiAgICAgICAg
ICAgICBhbmNob3JzLnJpZ2h0OiBwYXJlbnQucmlnaHQKICAgICAgICAgICAgIGFuY2hvcnMuYm90
dG9tOiBwYXJlbnQuYm90dG9tCi0gICAgICAgICAgICBhbmNob3JzLmxlZnRNYXJnaW46IDMyCi0g
ICAgICAgICAgICBhbmNob3JzLnJpZ2h0TWFyZ2luOiAzMgorICAgICAgICAgICAgYW5jaG9ycy5s
ZWZ0TWFyZ2luOiAyNAorICAgICAgICAgICAgYW5jaG9ycy5yaWdodE1hcmdpbjogMjQKICAgICAg
ICAgICAgIGFuY2hvcnMuYm90dG9tTWFyZ2luOiAyMgogICAgICAgICAgICAgc3BhY2luZzogMTAK
ICAgICAgICAgICAgIC8vIEhvc3QtdHlwZSBiYWRnZSAoYWNjZW50IG91dGxpbmUgZm9yIEFwb2xs
by1saW5lYWdlLCBuZXV0cmFsIGZvciBTdW5zaGluZSkuCkBAIC0xNTcsNyArMTU3LDcgQEAgSXRl
bSB7CiAgICAgICAgICAgICAgICAgICAgIGFuY2hvcnMuY2VudGVySW46IHBhcmVudAogICAgICAg
ICAgICAgICAgICAgICB0ZXh0OiBjYXJkLmhvc3RCYWRnZQogICAgICAgICAgICAgICAgICAgICBm
b250LmZhbWlseTogVmJUb2tlbnMuZm9udEJvZHkKLSAgICAgICAgICAgICAgICAgICAgZm9udC5w
aXhlbFNpemU6IDEzCisgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vu
cy50eXBlQ2FwdGlvbgogICAgICAgICAgICAgICAgICAgICBmb250LndlaWdodDogRm9udC5FeHRy
YUJvbGQKICAgICAgICAgICAgICAgICAgICAgZm9udC5sZXR0ZXJTcGFjaW5nOiAxLjIKICAgICAg
ICAgICAgICAgICAgICAgY29sb3I6IGNhcmQuYmFkZ2VBY2NlbnQgPyBWYlRva2Vucy5hY2NlbnQg
OiBWYlRva2Vucy50ZXh0RGltCmRpZmYgLS1naXQgYS9hcHAvZ3VpL1ZiSG9zdFNoZWV0LnFtbCBi
L2FwcC9ndWkvVmJIb3N0U2hlZXQucW1sCmluZGV4IGI0YTFhZjguLjU3ZmNiYjYgMTAwNjQ0Ci0t
LSBhL2FwcC9ndWkvVmJIb3N0U2hlZXQucW1sCisrKyBiL2FwcC9ndWkvVmJIb3N0U2hlZXQucW1s
CkBAIC03OCw3ICs3OCw3IEBAIFBvcHVwIHsKICAgICAgICAgfQogCiAgICAgICAgIC8vIC0tLS0g
UmlnaHQgcGFuZWwgLS0tLQotICAgICAgICBSZWN0YW5nbGUgeworICAgICAgICBDcmltc29uR2xh
c3NQYW5lbCB7CiAgICAgICAgICAgICBpZDogcGFuZWwKICAgICAgICAgICAgIHdpZHRoOiBNYXRo
Lm1pbig1NjAsIHJvb3Qud2lkdGggKiAwLjYyKQogICAgICAgICAgICAgaGVpZ2h0OiBwYXJlbnQu
aGVpZ2h0CmRpZmYgLS1naXQgYS9hcHAvZ3VpL1ZiU3RhdHVzUGlsbC5xbWwgYi9hcHAvZ3VpL1Zi
U3RhdHVzUGlsbC5xbWwKaW5kZXggODljNDc3MC4uYzcyOGYwNSAxMDA2NDQKLS0tIGEvYXBwL2d1
aS9WYlN0YXR1c1BpbGwucW1sCisrKyBiL2FwcC9ndWkvVmJTdGF0dXNQaWxsLnFtbApAQCAtMjQs
NyArMjQsNyBAQCBSZWN0YW5nbGUgewogICAgICAgICAgICAgY29sb3I6IHBpbGwub25saW5lID8g
VmJUb2tlbnMuc3RhdHVzT25saW5lIDogVmJUb2tlbnMuc3RhdHVzT2ZmbGluZQogICAgICAgICAg
ICAgLy8gUHVsc2Ugb25seSB3aGVuIG9ubGluZS4KICAgICAgICAgICAgIFNlcXVlbnRpYWxBbmlt
YXRpb24gb24gb3BhY2l0eSB7Ci0gICAgICAgICAgICAgICAgcnVubmluZzogcGlsbC5vbmxpbmUK
KyAgICAgICAgICAgICAgICBydW5uaW5nOiBwaWxsLm9ubGluZSAmJiBWYlRva2Vucy5tb3Rpb25F
bmFibGVkCiAgICAgICAgICAgICAgICAgbG9vcHM6IEFuaW1hdGlvbi5JbmZpbml0ZQogICAgICAg
ICAgICAgICAgIE51bWJlckFuaW1hdGlvbiB7IGZyb206IDEuMDsgdG86IDAuNDU7IGR1cmF0aW9u
OiBWYlRva2Vucy5vbmxpbmVQdWxzZU1zIC8gMjsgZWFzaW5nLnR5cGU6IEVhc2luZy5Jbk91dFNp
bmUgfQogICAgICAgICAgICAgICAgIE51bWJlckFuaW1hdGlvbiB7IGZyb206IDAuNDU7IHRvOiAx
LjA7IGR1cmF0aW9uOiBWYlRva2Vucy5vbmxpbmVQdWxzZU1zIC8gMjsgZWFzaW5nLnR5cGU6IEVh
c2luZy5Jbk91dFNpbmUgfQpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9WYlRva2Vucy5xbWwgYi9hcHAv
Z3VpL1ZiVG9rZW5zLnFtbAppbmRleCA1MmEzNGRlLi43Y2Q4OGQwIDEwMDY0NAotLS0gYS9hcHAv
Z3VpL1ZiVG9rZW5zLnFtbAorKysgYi9hcHAvZ3VpL1ZiVG9rZW5zLnFtbApAQCAtMSw1NyArMSw2
MyBAQAogcHJhZ21hIFNpbmdsZXRvbgogaW1wb3J0IFF0UXVpY2sgMi45CiBpbXBvcnQgU3RyZWFt
aW5nUHJlZmVyZW5jZXMgMS4wCitpbXBvcnQgRWNsaXBzZVByb2ZpbGVzIDEuMAogCi0vLyBWaWJl
bWlzIHJlZGVzaWduIGRlc2lnbiB0b2tlbnMuCisvLyBDcmltc29uIEdsYXNzIOKAlCBFY2xpcHNl
T1MgZnJvbnRlbmQgZGVzaWduIHRva2Vucy4KIC8vIERhcmsgdGhlbWUgb25seS4gQ2FudmFzIDE5
MjB4MTIwMCAoTGVnaW9uIEdvIFMpLAogLy8gc2NhbGVzIHRvIDEyODB4ODAwIChTdGVhbSBEZWNr
KSB2aWEgYW5jaG9ycy9MYXlvdXRzIOKAlCBuZXZlciBoYXJkLWNvZGUgY29vcmRpbmF0ZXMgYWdh
aW5zdCB0aGVzZS4KIC8vIFJlZ2lzdGVyZWQgYXMgYSBRTUwgc2luZ2xldG9uIGluIGFwcC9tYWlu
LmNwcDogcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlKHFyYzovZ3VpL1ZiVG9rZW5zLnFtbCkuCiBR
dE9iamVjdCB7CiAgICAgaWQ6IHQKIAorICAgIHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgdGV4dFNj
YWxlOiBFY2xpcHNlUHJvZmlsZXMudGV4dFNjYWxlIC8gMTAwCisgICAgcmVhZG9ubHkgcHJvcGVy
dHkgYm9vbCBtb3Rpb25FbmFibGVkOiAhRWNsaXBzZVByb2ZpbGVzLnJlZHVjZWRNb3Rpb24KKwog
ICAgIC8vIC0tLS0gQ29sb3IgLS0tLQotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnQXBw
OiAgICAgICAgIiMwODA5MEIiICAvLyBvdXRlcm1vc3QgYXBwIGJnIGJlaGluZCB0aGUgcm91bmRl
ZCB3aW5kb3cKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ1dpbmRvdzogICAgICIjMEUx
MDEzIiAgLy8gbWFpbiBzY3JlZW4gYmFja2dyb3VuZAotICAgIHJlYWRvbmx5IHByb3BlcnR5IGNv
bG9yIGJnRWxldjogICAgICAgIiMxNTE4MUQiICAvLyBjYXJkcywgcGFuZWxzLCBkaWFsb2dzLCBz
aWRlYmFyIHJvd3MKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBiZ0VsZXYyOiAgICAgICIj
MUIxRjI2IiAgLy8gZm9jdXNlZC9zZWxlY3RlZCBzdXJmYWNlIGZpbGwsIGNoaXBzCi0gICAgcmVh
ZG9ubHkgcHJvcGVydHkgY29sb3IgYmdGb290ZXI6ICAgICAiIzBCMEQxMCIgIC8vIGJvdHRvbSBn
YW1lcGFkIGhpbnQgYmFyCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Ryb2tlOiAgICAg
ICBRdC5yZ2JhKDEsIDEsIDEsIDAuMDgpICAvLyBkZWZhdWx0IDFweCBjYXJkIGJvcmRlcgorICAg
IHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnQXBwOiAgICAgICAgIiMwNjA2MDciICAvLyBvdXRl
cm1vc3QgYXBwIGJnIGJlaGluZCB0aGUgcm91bmRlZCB3aW5kb3cKKyAgICByZWFkb25seSBwcm9w
ZXJ0eSBjb2xvciBiZ1dpbmRvdzogICAgICIjMEIwQjBFIiAgLy8gbWFpbiBzY3JlZW4gYmFja2dy
b3VuZAorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGJnRWxldjogICAgICAgIiMxNTEzMTYi
ICAvLyBjYXJkcywgcGFuZWxzLCBkaWFsb2dzLCBzaWRlYmFyIHJvd3MKKyAgICByZWFkb25seSBw
cm9wZXJ0eSBjb2xvciBiZ0VsZXYyOiAgICAgICIjMjcxQjIyIiAgLy8gZm9jdXNlZC9zZWxlY3Rl
ZCBzdXJmYWNlIGZpbGwsIGNoaXBzCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYmdGb290
ZXI6ICAgICAiIzA5MDgwQiIgIC8vIGJvdHRvbSBnYW1lcGFkIGhpbnQgYmFyCisgICAgcmVhZG9u
bHkgcHJvcGVydHkgY29sb3Igc3Ryb2tlOiAgICAgICBRdC5yZ2JhKDEsIDEsIDEsIEVjbGlwc2VQ
cm9maWxlcy5oaWdoQ29udHJhc3QgPyAwLjI1IDogMC4wOCkgIC8vIGRlZmF1bHQgMXB4IGNhcmQg
Ym9yZGVyCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc3Ryb2tlU29mdDogICBRdC5yZ2Jh
KDEsIDEsIDEsIDAuMDYpICAvLyBoZWFkZXIvZm9vdGVyIGRpdmlkZXJzCiAgICAgcmVhZG9ubHkg
cHJvcGVydHkgY29sb3IgdGV4dDogICAgICAgICAiI0VDRUVGMSIgIC8vIHByaW1hcnkgdGV4dAot
ICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIHRleHREaW06ICAgICAgIiM5OEExQUIiICAvLyBz
ZWNvbmRhcnkgLyBsYWJlbCB0ZXh0CisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgdGV4dERp
bTogICAgICAoRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdCA/ICIjRDNENURDIiA6ICIjOThB
MUFCIikgIC8vIHNlY29uZGFyeSAvIGxhYmVsIHRleHQKICAgICByZWFkb25seSBwcm9wZXJ0eSBj
b2xvciB0ZXh0TXV0ZTogICAgICIjQjlDMEM4IiAgLy8gdGVydGlhcnkgLyBpbmFjdGl2ZSBpdGVt
IGxhYmVscwogCi0gICAgLy8gQWNjZW50IGlzIHN3YXBwYWJsZSDigJQgb25lIG9mIHRoZSA0IGN1
cmF0ZWQgdmFsdWVzLiBJbmRleCAwIGlzIHRoZSBWaWJlbWlzIGJyYW5kCi0gICAgLy8gdGVhbCAj
MDBDQ0NDIChCTC0yMDc3KTogdGhlIHNpbmdsZSBjYW5vbmljYWwgYWNjZW50IHRoYXQgVGhlbWUu
cW1sICsgYWxsIGxpdGVyYWxzIG5vdwotICAgIC8vIHJlc29sdmUgdGhyb3VnaCwgYW5kIHRoZSBh
bmNob3IgZm9yIHRoZSBQMy4xNy9QMy4xOCBkZXNpZ24gd29yay4KLSAgICByZWFkb25seSBwcm9w
ZXJ0eSB2YXIgYWNjZW50T3B0aW9uczogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4IiwgIiMzRUQ1OTgi
LCAiI0YwQTg2OCJdCisgICAgLy8gUHJlc2VydmUgbGVnYWN5IGluZGljZXMgMC4uMzsgYXBwZW5k
IGNvbG9ycyBhbmQgZGVmYXVsdCBuZXcgcHJlZmVyZW5jZXMgdG8gY3JpbXNvbi4KKyAgICByZWFk
b25seSBwcm9wZXJ0eSB2YXIgYWNjZW50T3B0aW9uczogIFsiIzAwQ0NDQyIsICIjN0M4Q0Y4Iiwg
IiMzRUQ1OTgiLCAiI0YwQTg2OCIsICIjREMzNjU4IiwgIiNGMjVENjQiLCAiI0Y1ODM0NyIsICIj
RjFCQzQ1IiwgIiNCN0RDNjMiLCAiIzYzQ0NBRSIsICIjNjNDNEVEIiwgIiM2QzlGRkYiLCAiI0FE
ODVGNSIsICIjRTk3NkJDIiwgIiNDQUQwREEiLCAiI0Q5OTVBQyJdCiAgICAgLy8gQm91bmQgdG8g
dGhlIHNhdmVkIHByZWZlcmVuY2UgKFNldHRpbmdzID4gYWNjZW50IHBpY2tlcik7IHBlcnNpc3Rz
IGFjcm9zcyByZXN0YXJ0cy4KICAgICBwcm9wZXJ0eSBpbnQgYWNjZW50SW5kZXg6IFN0cmVhbWlu
Z1ByZWZlcmVuY2VzLnVpQWNjZW50SW5kZXgKLSAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBh
Y2NlbnQ6ICAgICAgIGFjY2VudE9wdGlvbnNbYWNjZW50SW5kZXhdCi0gICAgcmVhZG9ubHkgcHJv
cGVydHkgY29sb3IgYWNjZW50SGk6ICAgICAiIzZBRERFNyIgIC8vIGFjY2VudCBncmFkaWVudCBs
aWdodCBzdG9wIC8gbGluayBob3ZlcgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2Vu
dDogICAgICAgYWNjZW50T3B0aW9uc1tNYXRoLm1heCgwLCBNYXRoLm1pbihhY2NlbnRPcHRpb25z
Lmxlbmd0aCAtIDEsIGFjY2VudEluZGV4KSldCisgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
YWNjZW50SGk6ICAgICBRdC5saWdodGVyKGFjY2VudCwgMS4xOCkgIC8vIGFjY2VudCBncmFkaWVu
dCBsaWdodCBzdG9wIC8gbGluayBob3ZlcgogCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
c3RhdHVzT25saW5lOiAgIiMzRUQ1OTgiICAvLyBvbmxpbmUgZG90LCBSRVNVTUUgYmFkZ2UKICAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBzdGF0dXNPZmZsaW5lOiAiIzVBNjI2QyIgIC8vIG9m
ZmxpbmUgZG90IC8gZ3JleWVkIG1vbml0b3IKICAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBz
dGF0dXNEYW5nZXI6ICAiI0YyNkQ2RCIgIC8vIGRlc3RydWN0aXZlIChEZWxldGUgUEMpCiAKLSAg
ICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciB0ZXh0T25BY2NlbnQ6ICIjMDgwOTBCIiAgLy8gdGV4
dCBvbiBhbiBhY2NlbnQtZmlsbGVkIGJ1dHRvbgorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9y
IHRleHRPbkFjY2VudDogIiMwNjA2MDciICAvLyB0ZXh0IG9uIGFuIGFjY2VudC1maWxsZWQgYnV0
dG9uCiAKKyAgICByZWFkb25seSBwcm9wZXJ0eSByZWFsIGdsYXNzT3BhY2l0eTogRWNsaXBzZVBy
b2ZpbGVzLmhpZ2hDb250cmFzdCA/IDEuMCA6IDAuOTIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBz
dHJpbmcgZGVzaWduTmFtZTogIkNyaW1zb24gR2xhc3MiCisgICAgcmVhZG9ubHkgcHJvcGVydHkg
Y29sb3IgZ2xhc3NUb3A6IEVjbGlwc2VQcm9maWxlcy5oaWdoQ29udHJhc3QgPyAiIzI1MjEyNiIg
OiAiIzIxMUQyMyIKKyAgICByZWFkb25seSBwcm9wZXJ0eSBjb2xvciBnbGFzc0VkZ2U6IFF0LnJn
YmEoMSwxLDEsRWNsaXBzZVByb2ZpbGVzLmhpZ2hDb250cmFzdCA/IDAuMzUgOiAwLjE2KQogICAg
IC8vIC0tLS0gVHlwb2dyYXBoeSAoZmFtaWxpZXMgKyBzaXplczsgd2VpZ2h0cyBwZXIgdGhlIHR5
cGUgc2NhbGUpIC0tLS0KICAgICByZWFkb25seSBwcm9wZXJ0eSBzdHJpbmcgZm9udERpc3BsYXk6
ICJTb3JhIiAgICAgLy8gdGl0bGVzLCBjYXJkIG5hbWVzLCB3b3JkbWFyaywgYWxsLWNhcHMgbGFi
ZWxzCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgc3RyaW5nIGZvbnRCb2R5OiAgICAiTWFucm9wZSIg
IC8vIGJvZHkgKyBVSSB0ZXh0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVTY3JlZW5U
aXRsZTogIDM0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVTZWN0aW9uVGl0bGU6IDI4
Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVDYXJkTmFtZTogICAgIDI3Ci0gICAgcmVh
ZG9ubHkgcHJvcGVydHkgaW50IHNpemVCb2R5OiAgICAgICAgIDE2Ci0gICAgcmVhZG9ubHkgcHJv
cGVydHkgaW50IHNpemVMYWJlbDogICAgICAgIDE0Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50
IHNpemVCYWRnZTogICAgICAgIDEzCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVXb3Jk
bWFyazogICAgIDIxCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVTY3JlZW5UaXRsZTog
IE1hdGgucm91bmQoMzQgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNp
emVTZWN0aW9uVGl0bGU6IE1hdGgucm91bmQoMjggKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkg
cHJvcGVydHkgaW50IHNpemVDYXJkTmFtZTogICAgIE1hdGgucm91bmQoMjcgKiB0ZXh0U2NhbGUp
CisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVCb2R5OiAgICAgICAgIE1hdGgucm91bmQo
MTYgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNpemVMYWJlbDogICAg
ICAgIE1hdGgucm91bmQoMTQgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50
IHNpemVCYWRnZTogICAgICAgIE1hdGgucm91bmQoMTMgKiB0ZXh0U2NhbGUpCisgICAgcmVhZG9u
bHkgcHJvcGVydHkgaW50IHNpemVXb3JkbWFyazogICAgIE1hdGgucm91bmQoMjEgKiB0ZXh0U2Nh
bGUpCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgcmVhbCB3b3JkbWFya1NwYWNpbmc6IDMuMAogICAg
IHJlYWRvbmx5IHByb3BlcnR5IHJlYWwgYmFkZ2VTcGFjaW5nOiAgICAxLjIKIAogICAgIC8vIC0t
LS0gUmFkaXVzIC0tLS0KICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgcmFkaXVzV2luZG93OiAg
ICAgMjAKLSAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgcmFkaXVzQ2FyZDogICAgICAgMTYKKyAg
ICByZWFkb25seSBwcm9wZXJ0eSBpbnQgcmFkaXVzQ2FyZDogICAgICAgMjAKICAgICByZWFkb25s
eSBwcm9wZXJ0eSBpbnQgcmFkaXVzRGlhbG9nOiAgICAgMjQKICAgICByZWFkb25seSBwcm9wZXJ0
eSBpbnQgcmFkaXVzQ29udHJvbDogICAgMTQKICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgcmFk
aXVzSWNvbkJ1dHRvbjogMTQKQEAgLTU5LDEyICs2NSwxMiBAQCBRdE9iamVjdCB7CiAgICAgcmVh
ZG9ubHkgcHJvcGVydHkgaW50IHJhZGl1c0JhZGdlOiAgICAgIDcKIAogICAgIC8vIC0tLS0gU3Bh
Y2luZyAtLS0tCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNjcmVlblBhZFg6IDU2Ci0gICAg
cmVhZG9ubHkgcHJvcGVydHkgaW50IHNjcmVlblBhZFk6IDUyCisgICAgcmVhZG9ubHkgcHJvcGVy
dHkgaW50IHNjcmVlblBhZFg6IDI0CisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHNjcmVlblBh
ZFk6IDI0CiAgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IGhlYWRlckg6ICAgIDg0CiAgICAgcmVh
ZG9ubHkgcHJvcGVydHkgaW50IGZvb3Rlckg6ICAgIDcyCi0gICAgcmVhZG9ubHkgcHJvcGVydHkg
aW50IGNhcmRHYXA6ICAgIDMyCi0gICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IHRpbGVHYXA6ICAg
IDM2CisgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IGNhcmRHYXA6ICAgIDIwCisgICAgcmVhZG9u
bHkgcHJvcGVydHkgaW50IHRpbGVHYXA6ICAgIDIwCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50
IGljb25CdXR0b246IDUyCiAKICAgICAvLyAtLS0tIEdhbWVwYWQgZXJnb25vbWljcyAtLS0tCkBA
IC04Myw3ICs4OSw3IEBAIFF0T2JqZWN0IHsKICAgICAvLyAtLS0tIE1vdGlvbiAobXMpIC0tLS0K
ICAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgb25saW5lUHVsc2VNczogMjQwMCAgIC8vIG9wYWNp
dHkgMSAtPiAwLjQ1IC0+IDEsIGluZmluaXRlCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgaW50IGNh
cmV0QmxpbmtNczogIDEwMDAgICAvLyBBZGQtUEMgaW5wdXQgY2FyZXQKLSAgICByZWFkb25seSBw
cm9wZXJ0eSBpbnQgc2hlZXRJbk1zOiAgICAgMjIwICAgIC8vIHNpZGUtc2hlZXQgc2xpZGUtaW4K
KyAgICByZWFkb25seSBwcm9wZXJ0eSBpbnQgc2hlZXRJbk1zOiAgICAgbW90aW9uRW5hYmxlZCA/
IDIyMCA6IDAgICAgLy8gc2lkZS1zaGVldCBzbGlkZS1pbgogICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIGRpYWxvZ1NjcmltOiBRdC5yZ2JhKDQvMjU1LCA1LzI1NSwgNy8yNTUsIDAuNzIpCiAg
ICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Igc2hlZXRTY3JpbTogIFF0LnJnYmEoNC8yNTUsIDUv
MjU1LCA3LzI1NSwgMC42MCkKIApAQCAtMTE5LDcgKzEyNSw3IEBAIFF0T2JqZWN0IHsKICAgICAv
LyB0ZXh0T25BY2NlbnQgKCMwODA5MEIpIGlzIGRlZmluZWQgaW4gdGhlIGJhc2UgYmxvY2sgYWJv
dmUg4oCUIHRleHQgb24gYW4gYWNjZW50IGZpbGwuCiAKICAgICAvLyAtLS0tIEludGVyYWN0aXZl
IHN0YXRlczogbm9ybWFsIC8gaG92ZXIgLyBmb2N1cyAvIHByZXNzZWQgLyBkaXNhYmxlZCAtLS0t
Ci0gICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgYWNjZW50UHJlc3NlZDogICAgICAiIzAwQTNB
MyIgLy8gcHJlc3NlZCBhY2NlbnRlZCBjb250cm9sIChtYXRjaGVzIGxlZ2FjeSBUaGVtZS5hY2Nl
bnRQcmVzc2VkKQorICAgIHJlYWRvbmx5IHByb3BlcnR5IGNvbG9yIGFjY2VudFByZXNzZWQ6ICAg
ICAgUXQuZGFya2VyKGFjY2VudCwgMS4xOCkgLy8gcHJlc3NlZCBhY2NlbnRlZCBjb250cm9sICht
YXRjaGVzIGxlZ2FjeSBUaGVtZS5hY2NlbnRQcmVzc2VkKQogICAgIHJlYWRvbmx5IHByb3BlcnR5
IGNvbG9yIGludGVyYWN0aXZlSG92ZXI6ICAgYmdFbGV2MiAgICAvLyByb3cgLyBsaXN0LWl0ZW0g
LyBpY29uLWJ1dHRvbiBob3ZlciBmaWxsCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3IgaW50
ZXJhY3RpdmVGb2N1czogICBmb2N1c2VkRmlsbC8vIGZvY3VzZWQgZmlsbCAoPSBiZ0VsZXYyKSDi
gJQgcGFpciB3aXRoIHRoZSBmb2N1cyByaW5nCiAgICAgcmVhZG9ubHkgcHJvcGVydHkgY29sb3Ig
aW50ZXJhY3RpdmVQcmVzc2VkOiBiZ0VsZXYgICAgIC8vIHByZXNzZWQgbmV1dHJhbCBmaWxsIChy
ZWNlZGVzIHVuZGVyIHRoZSBwcmVzcykKZGlmZiAtLWdpdCBhL2FwcC9ndWkvVmJXZWxjb21lU2hl
ZXQucW1sIGIvYXBwL2d1aS9WYldlbGNvbWVTaGVldC5xbWwKaW5kZXggMTczMTE5Yi4uYTE0ZWFl
NyAxMDA2NDQKLS0tIGEvYXBwL2d1aS9WYldlbGNvbWVTaGVldC5xbWwKKysrIGIvYXBwL2d1aS9W
YldlbGNvbWVTaGVldC5xbWwKQEAgLTI2LDcgKzI2LDcgQEAgTmF2aWdhYmxlRGlhbG9nIHsKICAg
ICAvLyBUb2tlbiBzY3JpbSBiZWhpbmQgdGhlIG1vZGFsIGNhcmQgKG1hdGNoZXMgdGhlIHJlZGVz
aWduIGRpYWxvZyBsYW5ndWFnZSkuCiAgICAgT3ZlcmxheS5tb2RhbDogUmVjdGFuZ2xlIHsgY29s
b3I6IFZiVG9rZW5zLmRpYWxvZ1NjcmltIH0KIAotICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7
CisgICAgYmFja2dyb3VuZDogQ3JpbXNvbkdsYXNzUGFuZWwgewogICAgICAgICBjb2xvcjogVmJU
b2tlbnMuYmdFbGV2CiAgICAgICAgIHJhZGl1czogVmJUb2tlbnMucmFkaXVzRGlhbG9nCiAgICAg
ICAgIGJvcmRlci53aWR0aDogMQpAQCAtMTA4LDE0ICsxMDgsMTMgQEAgTmF2aWdhYmxlRGlhbG9n
IHsKICAgICAgICAgICAgIHNwYWNpbmc6IFZiVG9rZW5zLnNwYWNlMiAgLy8gOAogICAgICAgICAg
ICAgUm93TGF5b3V0IHsKICAgICAgICAgICAgICAgICBzcGFjaW5nOiBWYlRva2Vucy5zcGFjZTIK
LSAgICAgICAgICAgICAgICBSZWN0YW5nbGUgewotICAgICAgICAgICAgICAgICAgICB3aWR0aDog
MTM7IGhlaWdodDogMTMKLSAgICAgICAgICAgICAgICAgICAgY29sb3I6IFZiVG9rZW5zLmFjY2Vu
dAotICAgICAgICAgICAgICAgICAgICByb3RhdGlvbjogNDUKKyAgICAgICAgICAgICAgICBJbWFn
ZSB7CisgICAgICAgICAgICAgICAgICAgIHNvdXJjZTogInFyYzovcmVzL2VjbGlwc2UtaWNvbi5z
dmciCisgICAgICAgICAgICAgICAgICAgIExheW91dC5wcmVmZXJyZWRXaWR0aDogMjg7IExheW91
dC5wcmVmZXJyZWRIZWlnaHQ6IDI4CiAgICAgICAgICAgICAgICAgICAgIExheW91dC5hbGlnbm1l
bnQ6IFF0LkFsaWduVkNlbnRlcgogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICBU
ZXh0IHsKLSAgICAgICAgICAgICAgICAgICAgdGV4dDogIlZJQkVNSVMiCisgICAgICAgICAgICAg
ICAgICAgIHRleHQ6ICJFQ0xJUFNFIgogICAgICAgICAgICAgICAgICAgICBmb250LmZhbWlseTog
VmJUb2tlbnMuZm9udERpc3BsYXkKICAgICAgICAgICAgICAgICAgICAgZm9udC53ZWlnaHQ6IEZv
bnQuRXh0cmFCb2xkCiAgICAgICAgICAgICAgICAgICAgIGZvbnQucGl4ZWxTaXplOiBWYlRva2Vu
cy5zaXplV29yZG1hcmsgICAgICAvLyAyMQpAQCAtMTI1LDcgKzEyNCw3IEBAIE5hdmlnYWJsZURp
YWxvZyB7CiAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgfQogICAgICAgICAgICAgVGV4
dCB7Ci0gICAgICAgICAgICAgICAgdGV4dDogcXNUcigiV2VsY29tZSB0byBWaWJlbWlzIikKKyAg
ICAgICAgICAgICAgICB0ZXh0OiBxc1RyKCJXZWxjb21lIHRvIEVjbGlwc2UiKQogICAgICAgICAg
ICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250RGlzcGxheQogICAgICAgICAgICAgICAg
IGZvbnQud2VpZ2h0OiBGb250LkJvbGQKICAgICAgICAgICAgICAgICBmb250LnBpeGVsU2l6ZTog
VmJUb2tlbnMudHlwZURpc3BsYXkgICAgICAgICAgIC8vIDM0CkBAIC0xOTUsNyArMTk0LDcgQEAg
TmF2aWdhYmxlRGlhbG9nIHsKICAgICAgICAgICAgIEluZm9Sb3cgewogICAgICAgICAgICAgICAg
IGdseXBoOiAiYXBwcyIKICAgICAgICAgICAgICAgICB0aXRsZTogcXNUcigiQWRkIHRvIFN0ZWFt
IikKLSAgICAgICAgICAgICAgICBzdWI6IHFzVHIoIk9uIFN0ZWFtIERlY2sgLyBTdGVhbU9TLCBh
ZGQgVmliZW1pcyB0byBTdGVhbSBmcm9tIERlc2t0b3AgTW9kZSBzbyBpdCBhcHBlYXJzIGluIEdh
bWUgTW9kZS4iKQorICAgICAgICAgICAgICAgIHN1YjogcXNUcigiT24gU3RlYW0gRGVjayAvIFN0
ZWFtT1MsIGFkZCBFY2xpcHNlIHRvIFN0ZWFtIGZyb20gRGVza3RvcCBNb2RlIHNvIGl0IGFwcGVh
cnMgaW4gR2FtZSBNb2RlLiIpCiAgICAgICAgICAgICB9CiAKICAgICAgICAgICAgIC8vIDMpIFNl
dHRpbmdzLgpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9jb21wdXRlcm1vZGVsLmNwcCBiL2FwcC9ndWkv
Y29tcHV0ZXJtb2RlbC5jcHAKaW5kZXggNjNjNzExNS4uMmQ0ODdmZiAxMDA2NDQKLS0tIGEvYXBw
L2d1aS9jb21wdXRlcm1vZGVsLmNwcAorKysgYi9hcHAvZ3VpL2NvbXB1dGVybW9kZWwuY3BwCkBA
IC0xLDMgKzEsNCBAQAorI2luY2x1ZGUgPFFVcmw+CiAjaW5jbHVkZSAiY29tcHV0ZXJtb2RlbC5o
IgogI2luY2x1ZGUgImJhY2tlbmQvc2VydmVycGVybWlzc2lvbnMuaCIKICNpbmNsdWRlICJzZXR0
aW5ncy92aWJlbWlzc2V0dGluZ3MuaCIKQEAgLTQyMCwzICs0MjEsMTMgQEAgdm9pZCBDb21wdXRl
ck1vZGVsOjpoYW5kbGVDb21wdXRlclN0YXRlQ2hhbmdlZChOdkNvbXB1dGVyKiBjb21wdXRlcikK
IH0KIAogI2luY2x1ZGUgImNvbXB1dGVybW9kZWwubW9jIgorCitRVmFyaWFudE1hcCBDb21wdXRl
ck1vZGVsOjpjcmltc29uSG9zdChpbnQgaW5kZXgpIGNvbnN0Cit7CisgICAgaWYgKGluZGV4IDwg
MCB8fCBpbmRleCA+PSBtX0NvbXB1dGVycy5jb3VudCgpKSByZXR1cm4ge307CisgICAgYXV0byBj
b21wdXRlciA9IG1fQ29tcHV0ZXJzW2luZGV4XTsKKyAgICBRUmVhZExvY2tlciBsb2NrKCZjb21w
dXRlci0+bG9jayk7CisgICAgUVVybCB1cmw7IHVybC5zZXRTY2hlbWUoImh0dHBzIik7IHVybC5z
ZXRIb3N0KGNvbXB1dGVyLT5hY3RpdmVBZGRyZXNzLmFkZHJlc3MoKSk7CisgICAgdXJsLnNldFBv
cnQoY29tcHV0ZXItPmFjdGl2ZUFkZHJlc3MucG9ydCgpID4gMCA/IGNvbXB1dGVyLT5hY3RpdmVB
ZGRyZXNzLnBvcnQoKSArIDEgOiA0Nzk5MCk7CisgICAgcmV0dXJuIHt7ImlkIiwgY29tcHV0ZXIt
PnV1aWR9LCB7InVybCIsIHVybC50b1N0cmluZygpfX07Cit9CmRpZmYgLS1naXQgYS9hcHAvZ3Vp
L2NvbXB1dGVybW9kZWwuaCBiL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5oCmluZGV4IDZlY2FlMzAu
LjJlZTczYzEgMTAwNjQ0Ci0tLSBhL2FwcC9ndWkvY29tcHV0ZXJtb2RlbC5oCisrKyBiL2FwcC9n
dWkvY29tcHV0ZXJtb2RlbC5oCkBAIC00Myw2ICs0Myw4IEBAIHB1YmxpYzoKIAogICAgIHZpcnR1
YWwgUUhhc2g8aW50LCBRQnl0ZUFycmF5PiByb2xlTmFtZXMoKSBjb25zdCBvdmVycmlkZTsKIAor
ICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50TWFwIGNyaW1zb25Ib3N0KGludCBjb21wdXRlckluZGV4
KSBjb25zdDsKKwogICAgIFFfSU5WT0tBQkxFIHZvaWQgZGVsZXRlQ29tcHV0ZXIoaW50IGNvbXB1
dGVySW5kZXgpOwogCiAgICAgUV9JTlZPS0FCTEUgUVN0cmluZyBnZW5lcmF0ZVBpblN0cmluZygp
OwpkaWZmIC0tZ2l0IGEvYXBwL2d1aS9tYWluLnFtbCBiL2FwcC9ndWkvbWFpbi5xbWwKaW5kZXgg
OWJjZTUxMC4uMTRmMzUwOCAxMDA2NDQKLS0tIGEvYXBwL2d1aS9tYWluLnFtbAorKysgYi9hcHAv
Z3VpL21haW4ucW1sCkBAIC0xMiw4ICsxMiwyNSBAQCBpbXBvcnQgU3lzdGVtUHJvcGVydGllcyAx
LjAKIGltcG9ydCBTZGxHYW1lcGFkS2V5TmF2aWdhdGlvbiAxLjAKIGltcG9ydCBVaVNvdW5kTWFu
YWdlciAxLjAKIGltcG9ydCBUaGVtZSAxLjAKK2ltcG9ydCBDcmltc29uU3RhdHVzIDEuMAoraW1w
b3J0IFN5c3RlbUNvbnRyb2xzIDEuMAogCiBBcHBsaWNhdGlvbldpbmRvdyB7CisgICAgTWF0ZXJp
YWwudGhlbWU6IE1hdGVyaWFsLkRhcmsKKyAgICBNYXRlcmlhbC5hY2NlbnQ6IFZiVG9rZW5zLmFj
Y2VudAorICAgIE1hdGVyaWFsLnByaW1hcnk6IFZiVG9rZW5zLmJnRWxldgorICAgIE1hdGVyaWFs
LmJhY2tncm91bmQ6IFZiVG9rZW5zLmJnV2luZG93CisgICAgTWF0ZXJpYWwuZm9yZWdyb3VuZDog
VmJUb2tlbnMudGV4dAorICAgIGNvbG9yOiBWYlRva2Vucy5iZ0FwcAorICAgIHBhbGV0dGUud2lu
ZG93OiBWYlRva2Vucy5iZ1dpbmRvdworICAgIHBhbGV0dGUud2luZG93VGV4dDogVmJUb2tlbnMu
dGV4dAorICAgIHBhbGV0dGUuYmFzZTogVmJUb2tlbnMuYmdBcHAKKyAgICBwYWxldHRlLmFsdGVy
bmF0ZUJhc2U6IFZiVG9rZW5zLmJnRWxldgorICAgIHBhbGV0dGUudGV4dDogVmJUb2tlbnMudGV4
dAorICAgIHBhbGV0dGUuYnV0dG9uOiBWYlRva2Vucy5iZ0VsZXYKKyAgICBwYWxldHRlLmJ1dHRv
blRleHQ6IFZiVG9rZW5zLnRleHQKKyAgICBwYWxldHRlLmhpZ2hsaWdodDogVmJUb2tlbnMuYWNj
ZW50CisgICAgcGFsZXR0ZS5oaWdobGlnaHRlZFRleHQ6IFZiVG9rZW5zLnRleHRPbkFjY2VudAog
ICAgIHByb3BlcnR5IGJvb2wgcG9sbGluZ0FjdGl2ZTogZmFsc2UKIAogICAgIC8vIFNldCBieSBT
ZXR0aW5nc1ZpZXcgdG8gZm9yY2UgdGhlIGJhY2sgb3BlcmF0aW9uIHRvIHBvcCBhbGwKQEAgLTQ2
LDE0ICs2MywxMyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgIC8vIGluIG9yZGVyIHRv
IGltcHJvdmUgY29udHJhc3QgYmV0d2VlbiBHRkUncyBwbGFjZWhvbGRlciBib3ggYXJ0CiAgICAg
ICAgIC8vIGFuZCB0aGUgYmFja2dyb3VuZCBvZiB0aGUgYXBwIGdyaWQuCiAgICAgICAgIGlmIChT
eXN0ZW1Qcm9wZXJ0aWVzLnVzZXNNYXRlcmlhbDNUaGVtZSkgewotICAgICAgICAgICAgTWF0ZXJp
YWwuYmFja2dyb3VuZCA9IFRoZW1lLmJhY2tncm91bmQKKyAgICAgICAgICAgIC8vIFRoZW1lIHJl
bWFpbnMgYSBsaXZlIGJpbmRpbmcgdG8gdGhlIHNoYXJlZCBwYWxldHRlLgogICAgICAgICB9CiAK
ICAgICAgICAgLy8gQnJpZGdlIHRoZSBNYXRlcmlhbCBzdHlsZSB0byB0aGUgVmliZW1pcyBkZXNp
Z24gdG9rZW5zIHNvIHRoZQogICAgICAgICAvLyBNYXRlcmlhbC1zdHlsZWQgcGFnZXMgKENvbXB1
dGVycyBncmlkLCBBcHAgZ3JpZCwgZGlhbG9ncykgc2hhcmUgdGhlIHNhbWUKICAgICAgICAgLy8g
YWNjZW50L2JhY2tncm91bmQgc3lzdGVtIGFzIHRoZSB0b2tlbi1uYXRpdmUgcGFnZXMuIFNlZSBk
b2NzL0RFU0lHTl9TWVNURU0ubWQuCi0gICAgICAgIE1hdGVyaWFsLnRoZW1lID0gTWF0ZXJpYWwu
RGFyawotICAgICAgICBNYXRlcmlhbC5hY2NlbnQgPSBUaGVtZS5hY2NlbnQKKyAgICAgICAgLy8g
TWF0ZXJpYWwgdGhlbWUvYWNjZW50IGFyZSBib3VuZCBhdCB0aGUgcm9vdCwgaW5jbHVkaW5nIGFm
dGVyIGNoYW5nZXMuCiAKICAgICAgICAgU2RsR2FtZXBhZEtleU5hdmlnYXRpb24uZW5hYmxlKCkK
ICAgICB9CkBAIC0xMjksNiArMTQ1LDggQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgICAgICB9
CiAgICAgfQogCisgICAgQ3JpbXNvbkdsYXNzQmFja2Ryb3AgeyBhbmNob3JzLmZpbGw6cGFyZW50
IH0KKwogICAgIFN0YWNrVmlldyB7CiAgICAgICAgIGlkOiBzdGFja1ZpZXcKICAgICAgICAgYW5j
aG9ycy5maWxsOiBwYXJlbnQKQEAgLTI2Nyw2ICsyODUsMjUgQEAgQXBwbGljYXRpb25XaW5kb3cg
ewogICAgICAgICB9CiAgICAgfQogCisgICAgQ3JpbXNvblN0YXR1c0RpYWxvZyB7IGlkOiBjcmlt
c29uUGFuZWwgfQorICAgIFN5c3RlbUNvbm5lY3Rpb25zRGlhbG9nIHsgaWQ6IGNvbm5lY3Rpb25Q
YW5lbCB9CisgICAgRWNsaXBzZUFib3V0RGlhbG9nIHsgaWQ6IGVjbGlwc2VBYm91dCB9CisgICAg
RWNsaXBzZUNvbnRyb2xDZW50ZXIgeworICAgICAgICBpZDogZWNsaXBzZUNlbnRlcgorICAgICAg
ICBjYW5NYW5hZ2U6IFN5c3RlbVByb3BlcnRpZXMuaGFzQnJvd3NlcgorICAgICAgICBjYW5XYWtl
OiB0b29sQmFyLm9uUGNWaWV3CisgICAgICAgIG9uV2FrZVJlcXVlc3RlZDogeworICAgICAgICAg
ICAgaWYgKHRvb2xCYXIub25QY1ZpZXcpIHN0YWNrVmlldy5jdXJyZW50SXRlbS5jb21wdXRlck1v
ZGVsLndha2VDb21wdXRlcihzdGFja1ZpZXcuY3VycmVudEl0ZW0uY3VycmVudEluZGV4KQorICAg
ICAgICB9CisgICAgICAgIG9uTmF2aWdhdGVSZXF1ZXN0ZWQ6IHsKKyAgICAgICAgICAgIGlmIChk
ZXN0aW5hdGlvbiA9PT0gIndpZmkiIHx8IGRlc3RpbmF0aW9uID09PSAiYnQiKSB7IGNvbm5lY3Rp
b25QYW5lbC5raW5kID0gZGVzdGluYXRpb247IGNvbm5lY3Rpb25QYW5lbC5vcGVuKCkgfQorICAg
ICAgICAgICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJzZXR0aW5ncyIpIG5hdmlnYXRlVG8o
InFyYzovZ3VpL1NldHRpbmdzVmlldy5xbWwiLCAiU2V0dGluZ3NWaWV3IikKKyAgICAgICAgICAg
IGVsc2UgaWYgKGRlc3RpbmF0aW9uID09PSAiaG9zdCIpIHsgQ3JpbXNvblN0YXR1cy5zZWxlY3RI
b3N0KGVjbGlwc2VDZW50ZXIuaG9zdC5pZCB8fCAiIiwgZWNsaXBzZUNlbnRlci5ob3N0LnVybCB8
fCAiIik7IGNyaW1zb25QYW5lbC5raW5kID0gImhvc3QiOyBjcmltc29uUGFuZWwub3BlbigpIH0K
KyAgICAgICAgICAgIGVsc2UgaWYgKGRlc3RpbmF0aW9uID09PSAiYWJvdXQiKSB7IGVjbGlwc2VB
Ym91dC5pbmZvID0gU3lzdGVtQ29udHJvbHMuc3RhdGU7IGVjbGlwc2VBYm91dC5vcGVuKCkgfQor
ICAgICAgICAgICAgZWxzZSBpZiAoZGVzdGluYXRpb24gPT09ICJtYW5hZ2VtZW50IiAmJiBTeXN0
ZW1Qcm9wZXJ0aWVzLmhhc0Jyb3dzZXIpIFN5c3RlbVByb3BlcnRpZXMub3BlblVybChlY2xpcHNl
Q2VudGVyLmhvc3QudXJsKQorICAgICAgICB9CisgICAgfQorCiAgICAgaGVhZGVyOiBUb29sQmFy
IHsKICAgICAgICAgaWQ6IHRvb2xCYXIKICAgICAgICAgLy8gUmVkZXNpZ246IEVWRVJZIHJlZGVz
aWduZWQgbGF1bmNoZXIgc2NyZWVuIChDb21wdXRlcnMsIEFwcCBncmlkLCBTZXR0aW5ncywgSGVs
cCkKQEAgLTMyNSw3ICszNjIsOCBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgIC8vIHJl
ZGVzaWduIHJhdGhlciB0aGFuIHRoZSBkZWZhdWx0IE1hdGVyaWFsIGluZGlnbywgd2hpY2ggcmVh
ZCBhcyBhbiAidWdseSBibHVlIiBoZWFkZXIKICAgICAgICAgLy8gY2xhc2hpbmcgd2l0aCB0aGUg
ZGFyayBVSSBiZWxvdyBpdC4gSGVpZ2h0IGlzIGNvbnN0YW50IG9uIHRoZSBob21lIHNjcmVlbnMg
KG5vIHJ1bnRpbWUKICAgICAgICAgLy8gZ2VvbWV0cnkgY2hhbmdlKSBzbyB0aGUgYmxhY2stc2Ny
ZWVuIGZpeCBpcyBwcmVzZXJ2ZWQuCi0gICAgICAgIGJhY2tncm91bmQ6IFJlY3RhbmdsZSB7Cisg
ICAgICAgIGJhY2tncm91bmQ6IENyaW1zb25HbGFzc1BhbmVsIHsKKyAgICAgICAgICAgIHJhZGl1
czowCiAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYmdXaW5kb3cKICAgICAgICAgICAgIFJl
Y3RhbmdsZSB7CiAgICAgICAgICAgICAgICAgYW5jaG9ycy5ib3R0b206IHBhcmVudC5ib3R0b20K
QEAgLTMzOCwyMCArMzc2LDE5IEBAIEFwcGxpY2F0aW9uV2luZG93IHsKICAgICAgICAgLy8gVklC
RU1JUyB3b3JkbWFyayAoZGlhbW9uZCArIHdvcmRtYXJrKSwgc2hvd24gb24gdGhlIENvbXB1dGVy
cyBzY3JlZW4gaW4gcGxhY2Ugb2YgYSB0aXRsZSwKICAgICAgICAgLy8gbWF0Y2hpbmcgdGhlIGRl
c2lnbiBoZWFkZXIuIExlZnQtYWxpZ25lZCBhdCB0aGUgSFRNTCdzIDQwcHggcGFkZGluZy4KICAg
ICAgICAgUm93IHsKLSAgICAgICAgICAgIHZpc2libGU6IHRvb2xCYXIub25QY1ZpZXcKKyAgICAg
ICAgICAgIHZpc2libGU6IHRvb2xCYXIub25QY1ZpZXcgJiYgdG9vbEJhci53aWR0aCA+IDgyMAog
ICAgICAgICAgICAgYW5jaG9ycy5sZWZ0OiBwYXJlbnQubGVmdAogICAgICAgICAgICAgYW5jaG9y
cy5sZWZ0TWFyZ2luOiA0MAogICAgICAgICAgICAgYW5jaG9ycy52ZXJ0aWNhbENlbnRlcjogcGFy
ZW50LnZlcnRpY2FsQ2VudGVyCiAgICAgICAgICAgICBzcGFjaW5nOiAxMQotICAgICAgICAgICAg
UmVjdGFuZ2xlIHsKKyAgICAgICAgICAgIEltYWdlIHsKICAgICAgICAgICAgICAgICBhbmNob3Jz
LnZlcnRpY2FsQ2VudGVyOiBwYXJlbnQudmVydGljYWxDZW50ZXIKLSAgICAgICAgICAgICAgICB3
aWR0aDogMTM7IGhlaWdodDogMTMKLSAgICAgICAgICAgICAgICBjb2xvcjogVmJUb2tlbnMuYWNj
ZW50Ci0gICAgICAgICAgICAgICAgcm90YXRpb246IDQ1CisgICAgICAgICAgICAgICAgd2lkdGg6
IDI4OyBoZWlnaHQ6IDI4CisgICAgICAgICAgICAgICAgc291cmNlOiAicXJjOi9yZXMvZWNsaXBz
ZS1pY29uLnN2ZyIKICAgICAgICAgICAgIH0KICAgICAgICAgICAgIFRleHQgewogICAgICAgICAg
ICAgICAgIGFuY2hvcnMudmVydGljYWxDZW50ZXI6IHBhcmVudC52ZXJ0aWNhbENlbnRlcgotICAg
ICAgICAgICAgICAgIHRleHQ6ICJWSUJFTUlTIgorICAgICAgICAgICAgICAgIHRleHQ6ICJFQ0xJ
UFNFIgogICAgICAgICAgICAgICAgIGZvbnQuZmFtaWx5OiBWYlRva2Vucy5mb250RGlzcGxheQog
ICAgICAgICAgICAgICAgIGZvbnQud2VpZ2h0OiBGb250LkV4dHJhQm9sZAogICAgICAgICAgICAg
ICAgIGZvbnQucGl4ZWxTaXplOiAyMQpAQCAtMzY1LDcgKzQwMiw3IEBAIEFwcGxpY2F0aW9uV2lu
ZG93IHsKICAgICAgICAgICAgIC8vIEhpZGRlbiBvbiBDb21wdXRlcnMgKHRoZSB3b3JkbWFyayBz
dGFuZHMgaW4pIGFuZCBvbiB0aGUgQXBwIGdyaWQgKHdoaWNoIHNob3dzIGEKICAgICAgICAgICAg
IC8vIGxlZnQtYWxpZ25lZCBob3N0ICsgc3RhdHVzIGJsb2NrIGluc3RlYWQpLiBPbiBTZXR0aW5n
cy9IZWxwIGl0IHNob3dzIHRoZSBzY3JlZW4gbmFtZTsKICAgICAgICAgICAgIC8vIHRoZSBzdHJl
YW1pbmcgc2VndWVzIGtlZXAgdGhlaXIgZGVmYXVsdCBvYmplY3ROYW1lIHRpdGxlLgotICAgICAg
ICAgICAgdmlzaWJsZTogIXRvb2xCYXIub25QY1ZpZXcgJiYgIXRvb2xCYXIub25BcHBWaWV3ICYm
IHRvb2xCYXIud2lkdGggPiA3MDAKKyAgICAgICAgICAgIHZpc2libGU6ICF0b29sQmFyLm9uUGNW
aWV3ICYmICF0b29sQmFyLm9uQXBwVmlldyAmJiB0b29sQmFyLndpZHRoID4gODIwCiAgICAgICAg
ICAgICBhbmNob3JzLmZpbGw6IHBhcmVudAogICAgICAgICAgICAgdGV4dDogdG9vbEJhci5vblNl
dHRpbmdzID8gcXNUcigiU2V0dGluZ3MiKQogICAgICAgICAgICAgICAgIDogdG9vbEJhci5vbkhl
bHAgPyBxc1RyKCJIZWxwIikKQEAgLTQ4Nyw2ICs1MjQsNTQgQEAgQXBwbGljYXRpb25XaW5kb3cg
ewogICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgIH0KIAorICAgICAgICAgICAgTmF2aWdh
YmxlVG9vbEJ1dHRvbiB7CisgICAgICAgICAgICAgICAgaWQ6IG5ldHdvcmtTdGF0dXNCdXR0b24K
KyAgICAgICAgICAgICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2
ZyIKKyAgICAgICAgICAgICAgICBBY2Nlc3NpYmxlLm5hbWU6IHFzVHIoIldpLUZpIHNldHRpbmdz
IikKKyAgICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAg
ICAgICBUb29sVGlwLnRleHQ6IHFzVHIoIk5ldHdvcms6ICUxIikuYXJnKENyaW1zb25TdGF0dXMu
bG9jYWwubmV0d29yayB8fCBxc1RyKCJVbmF2YWlsYWJsZSIpKQorICAgICAgICAgICAgICAgIG9u
Q2xpY2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9ICJ3aWZpIjsgY29ubmVjdGlvblBhbmVs
Lm9wZW4oKSB9CisgICAgICAgICAgICAgICAgS2V5cy5vbkRvd25QcmVzc2VkOiBzdGFja1ZpZXcu
Y3VycmVudEl0ZW0uZm9yY2VBY3RpdmVGb2N1cyhRdC5UYWJGb2N1cykKKyAgICAgICAgICAgICAg
ICBSZWN0YW5nbGUgeworICAgICAgICAgICAgICAgICAgICBhbmNob3JzLnJpZ2h0OiBwYXJlbnQu
cmlnaHQ7IGFuY2hvcnMuYm90dG9tOiBwYXJlbnQuYm90dG9tOyBhbmNob3JzLm1hcmdpbnM6IDUK
KyAgICAgICAgICAgICAgICAgICAgd2lkdGg6IDg7IGhlaWdodDogODsgcmFkaXVzOiA0CisgICAg
ICAgICAgICAgICAgICAgIGNvbG9yOiBDcmltc29uU3RhdHVzLmxvY2FsLmNvbm5lY3RlZCA/IFZi
VG9rZW5zLnN0YXR1c09ubGluZSA6IFZiVG9rZW5zLnN0YXR1c09mZmxpbmUKKyAgICAgICAgICAg
ICAgICB9CisgICAgICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsK
KyAgICAgICAgICAgICAgICBpZDogYmx1ZXRvb3RoU2V0dGluZ3NCdXR0b24KKyAgICAgICAgICAg
ICAgICBpY29uU291cmNlOiAicXJjOi9yZXMvY3JpbXNvbi1ibHVldG9vdGguc3ZnIgorICAgICAg
ICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiQmx1ZXRvb3RoIHNldHRpbmdzIikKKyAg
ICAgICAgICAgICAgICBUb29sVGlwLnZpc2libGU6IGhvdmVyZWQKKyAgICAgICAgICAgICAgICBU
b29sVGlwLnRleHQ6IHFzVHIoIlBhaXIgY29udHJvbGxlcnMgYW5kIGhlYWRwaG9uZXMiKQorICAg
ICAgICAgICAgICAgIG9uQ2xpY2tlZDogeyBjb25uZWN0aW9uUGFuZWwua2luZCA9ICJidCI7IGNv
bm5lY3Rpb25QYW5lbC5vcGVuKCkgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3Nl
ZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisg
ICAgICAgICAgICB9CisgICAgICAgICAgICBOYXZpZ2FibGVUb29sQnV0dG9uIHsKKyAgICAgICAg
ICAgICAgICBpZDogYmF0dGVyeVN0YXR1c0J1dHRvbgorICAgICAgICAgICAgICAgIGljb25Tb3Vy
Y2U6ICJxcmM6L3Jlcy9jcmltc29uLWJhdHRlcnkuc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vz
c2libGUubmFtZTogcXNUcigiQmF0dGVyeSBzdGF0dXMiKQorICAgICAgICAgICAgICAgIFRvb2xU
aXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xUaXAudGV4dDogQ3JpbXNv
blN0YXR1cy5sb2NhbC5iYXR0ZXJ5UGVyY2VudCA+PSAwID8gcXNUcigiQmF0dGVyeTogJTElIOKA
oiAlMiIpLmFyZyhDcmltc29uU3RhdHVzLmxvY2FsLmJhdHRlcnlQZXJjZW50KS5hcmcoQ3JpbXNv
blN0YXR1cy5sb2NhbC5iYXR0ZXJ5U3RhdGUpIDogcXNUcigiQmF0dGVyeSB1bmF2YWlsYWJsZSIp
CisgICAgICAgICAgICAgICAgb25DbGlja2VkOiB7IGNyaW1zb25QYW5lbC5raW5kID0gImJhdHRl
cnkiOyBjcmltc29uUGFuZWwub3BlbigpIH0KKyAgICAgICAgICAgICAgICBLZXlzLm9uRG93blBy
ZXNzZWQ6IHN0YWNrVmlldy5jdXJyZW50SXRlbS5mb3JjZUFjdGl2ZUZvY3VzKFF0LlRhYkZvY3Vz
KQorICAgICAgICAgICAgfQorICAgICAgICAgICAgTmF2aWdhYmxlVG9vbEJ1dHRvbiB7CisgICAg
ICAgICAgICAgICAgaWQ6IGhvc3RIYXJkd2FyZUJ1dHRvbgorICAgICAgICAgICAgICAgIGljb25T
b3VyY2U6ICJxcmM6L3Jlcy9jcmltc29uLWhvc3Quc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vz
c2libGUubmFtZTogcXNUcigiVmliZXBvbGxvIGhvc3QgaGFyZHdhcmUgc3RhdHMiKQorICAgICAg
ICAgICAgICAgIFRvb2xUaXAudmlzaWJsZTogaG92ZXJlZAorICAgICAgICAgICAgICAgIFRvb2xU
aXAudGV4dDogcXNUcigiSG9zdCBDUFUsIFJBTSwgR1BVIGFuZCB0ZW1wZXJhdHVyZXMiKQorICAg
ICAgICAgICAgICAgIG9uQ2xpY2tlZDogeworICAgICAgICAgICAgICAgICAgICB2YXIgaXRlbSA9
IHN0YWNrVmlldy5jdXJyZW50SXRlbQorICAgICAgICAgICAgICAgICAgICB2YXIgaG9zdCA9IHRv
b2xCYXIub25BcHBWaWV3ID8gaXRlbS5jcmltc29uSG9zdAorICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICA6ICh0b29sQmFyLm9uUGNWaWV3ID8gaXRlbS5jb21wdXRlck1vZGVsLmNyaW1zb25I
b3N0KGl0ZW0uY3VycmVudEluZGV4KSA6IHt9KQorICAgICAgICAgICAgICAgICAgICBDcmltc29u
U3RhdHVzLnNlbGVjdEhvc3QoaG9zdC5pZCB8fCAiIiwgaG9zdC51cmwgfHwgIiIpCisgICAgICAg
ICAgICAgICAgICAgIGNyaW1zb25QYW5lbC5raW5kID0gImhvc3QiOyBjcmltc29uUGFuZWwub3Bl
bigpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEtleXMub25Eb3duUHJlc3Nl
ZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQuVGFiRm9jdXMpCisg
ICAgICAgICAgICB9CisKICAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24gewogICAgICAg
ICAgICAgICAgIGlkOiBkaXNjb3JkQnV0dG9uCiAgICAgICAgICAgICAgICAgdmlzaWJsZTogZmFs
c2UgLy8gVGVtcG9yYXJpbHkgZGlzYWJsZWQgZm9yIFZpYmVtaXMKQEAgLTU2NCw3ICs2NDksNyBA
QCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgICAgICAgICAgICAgLy8gYW4gaW5zdGFsbCBmYWls
dXJlIGZhbGxzIGJhY2sgdG8gdGhlIHJlbGVhc2UgcGFnZSBvbiBpdHMgb3duLgogICAgICAgICAg
ICAgICAgIFRvb2xUaXAudGV4dDogQXV0b1VwZGF0ZUNoZWNrZXIuaW5zdGFsbGluZwogICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgPyBxc1RyKCJEb3dubG9hZGluZyB1cGRhdGXigKYiKQot
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBxc1RyKCJVcGRhdGUgYXZhaWxhYmxlIGZv
ciBWaWJlbWlzOiBWZXJzaW9uICUxIOKAlCB0YXAgdG8gaW5zdGFsbCIpLmFyZyhBdXRvVXBkYXRl
Q2hlY2tlci5hdmFpbGFibGVWZXJzaW9uKQorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
OiBxc1RyKCJVcGRhdGUgYXZhaWxhYmxlIGZvciBFY2xpcHNlOiBWZXJzaW9uICUxIOKAlCB0YXAg
dG8gaW5zdGFsbCIpLmFyZyhBdXRvVXBkYXRlQ2hlY2tlci5hdmFpbGFibGVWZXJzaW9uKQogCiAg
ICAgICAgICAgICAgICAgLy8gU3RyaWN0bHktbmV3ZXIgYnVpbGRzIG9ubHkgKGEgY2hhbm5lbC1z
d2l0Y2ggZG93bmdyYWRlIG9mZmVyCiAgICAgICAgICAgICAgICAgLy8gbGl2ZXMgaW4gU2V0dGlu
Z3MsIG5vdCBvbiB0aGUgdG9vbGJhcikuCkBAIC02NDYsNiArNzMxLDIxIEBAIEFwcGxpY2F0aW9u
V2luZG93IHsKICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICB9CiAKKyAgICAgICAgICAg
IE5hdmlnYWJsZVRvb2xCdXR0b24geworICAgICAgICAgICAgICAgIGlkOiBlY2xpcHNlQ2VudGVy
QnV0dG9uCisgICAgICAgICAgICAgICAgaWNvblNvdXJjZTogInFyYzovcmVzL2VjbGlwc2UtY29u
dHJvbHMuc3ZnIgorICAgICAgICAgICAgICAgIEFjY2Vzc2libGUubmFtZTogcXNUcigiRWNsaXBz
ZSBjb250cm9sIGNlbnRlciIpCisgICAgICAgICAgICAgICAgVG9vbFRpcC52aXNpYmxlOiBob3Zl
cmVkCisgICAgICAgICAgICAgICAgVG9vbFRpcC50ZXh0OiBxc1RyKCJDb250cm9sIGNlbnRlciDi
gKIgQ3RybCtTaGlmdCtDIikKKyAgICAgICAgICAgICAgICBvbkNsaWNrZWQ6IHsKKyAgICAgICAg
ICAgICAgICAgICAgdmFyIGl0ZW0gPSBzdGFja1ZpZXcuY3VycmVudEl0ZW0KKyAgICAgICAgICAg
ICAgICAgICAgZWNsaXBzZUNlbnRlci5ob3N0ID0gdG9vbEJhci5vbkFwcFZpZXcgPyBpdGVtLmNy
aW1zb25Ib3N0IDogKHRvb2xCYXIub25QY1ZpZXcgPyBpdGVtLmNvbXB1dGVyTW9kZWwuY3JpbXNv
bkhvc3QoaXRlbS5jdXJyZW50SW5kZXgpIDoge30pCisgICAgICAgICAgICAgICAgICAgIGVjbGlw
c2VDZW50ZXIub3BlbigpCisgICAgICAgICAgICAgICAgfQorICAgICAgICAgICAgICAgIEtleXMu
b25Eb3duUHJlc3NlZDogc3RhY2tWaWV3LmN1cnJlbnRJdGVtLmZvcmNlQWN0aXZlRm9jdXMoUXQu
VGFiRm9jdXMpCisgICAgICAgICAgICAgICAgU2hvcnRjdXQgeyBzZXF1ZW5jZTogIkN0cmwrU2hp
ZnQrQyI7IGVuYWJsZWQ6IHRvb2xCYXIub25QY1ZpZXcgfHwgdG9vbEJhci5vbkFwcFZpZXc7IG9u
QWN0aXZhdGVkOiBlY2xpcHNlQ2VudGVyQnV0dG9uLmNsaWNrZWQoKSB9CisgICAgICAgICAgICB9
CisKICAgICAgICAgICAgIE5hdmlnYWJsZVRvb2xCdXR0b24gewogICAgICAgICAgICAgICAgIGlk
OiBzZXR0aW5nc0J1dHRvbgogCkBAIC02NzMsNyArNzczLDcgQEAgQXBwbGljYXRpb25XaW5kb3cg
ewogCiAgICAgRXJyb3JNZXNzYWdlRGlhbG9nIHsKICAgICAgICAgaWQ6IG5vSHdEZWNvZGVyRGlh
bG9nCi0gICAgICAgIHRleHQ6IHFzVHIoIk5vIGZ1bmN0aW9uaW5nIGhhcmR3YXJlIGFjY2VsZXJh
dGVkIHZpZGVvIGRlY29kZXIgd2FzIGRldGVjdGVkIGJ5IFZpYmVtaXMuICIgKworICAgICAgICB0
ZXh0OiBxc1RyKCJObyBmdW5jdGlvbmluZyBoYXJkd2FyZSBhY2NlbGVyYXRlZCB2aWRlbyBkZWNv
ZGVyIHdhcyBkZXRlY3RlZCBieSBFY2xpcHNlLiAiICsKICAgICAgICAgICAgICAgICAgICAiWW91
ciBzdHJlYW1pbmcgcGVyZm9ybWFuY2UgbWF5IGJlIHNldmVyZWx5IGRlZ3JhZGVkIGluIHRoaXMg
Y29uZmlndXJhdGlvbi4iKQogICAgICAgICBoZWxwVGV4dDogcXNUcigiQ2xpY2sgdGhlIEhlbHAg
YnV0dG9uIGZvciBtb3JlIGluZm9ybWF0aW9uIG9uIHNvbHZpbmcgdGhpcyBwcm9ibGVtLiIpCiAg
ICAgICAgIGhlbHBVcmw6ICJodHRwczovL2dpdGh1Yi5jb20vbmF2eWFzMzIxL3ZpYmVtaXMiCkBA
IC02OTAsNyArNzkwLDcgQEAgQXBwbGljYXRpb25XaW5kb3cgewogICAgIE5hdmlnYWJsZU1lc3Nh
Z2VEaWFsb2cgewogICAgICAgICBpZDogd293NjREaWFsb2cKICAgICAgICAgc3RhbmRhcmRCdXR0
b25zOiBEaWFsb2cuT2sgfCBEaWFsb2cuQ2FuY2VsCi0gICAgICAgIHRleHQ6IHFzVHIoIlRoaXMg
dmVyc2lvbiBvZiBWaWJlbWlzIGlzbid0IG9wdGltaXplZCBmb3IgeW91ciBQQy4gUGxlYXNlIGRv
d25sb2FkIHRoZSAnJTEnIHZlcnNpb24gb2YgVmliZW1pcyBmb3IgdGhlIGJlc3Qgc3RyZWFtaW5n
IHBlcmZvcm1hbmNlLiIpLmFyZyhTeXN0ZW1Qcm9wZXJ0aWVzLmZyaWVuZGx5TmF0aXZlQXJjaE5h
bWUpCisgICAgICAgIHRleHQ6IHFzVHIoIlRoaXMgdmVyc2lvbiBvZiBFY2xpcHNlIGlzbid0IG9w
dGltaXplZCBmb3IgeW91ciBQQy4gUGxlYXNlIGRvd25sb2FkIHRoZSAnJTEnIHZlcnNpb24gb2Yg
RWNsaXBzZSBmb3IgdGhlIGJlc3Qgc3RyZWFtaW5nIHBlcmZvcm1hbmNlLiIpLmFyZyhTeXN0ZW1Q
cm9wZXJ0aWVzLmZyaWVuZGx5TmF0aXZlQXJjaE5hbWUpCiAgICAgICAgIG9uQWNjZXB0ZWQ6IHsK
ICAgICAgICAgICAgIFN5c3RlbVByb3BlcnRpZXMub3BlblVybCgiaHR0cHM6Ly9naXRodWIuY29t
L25hdnlhczMyMS92aWJlbWlzL3JlbGVhc2VzIik7CiAgICAgICAgIH0KQEAgLTY5OSw3ICs3OTks
NyBAQCBBcHBsaWNhdGlvbldpbmRvdyB7CiAgICAgRXJyb3JNZXNzYWdlRGlhbG9nIHsKICAgICAg
ICAgaWQ6IHVubWFwcGVkR2FtZXBhZERpYWxvZwogICAgICAgICBwcm9wZXJ0eSBzdHJpbmcgdW5t
YXBwZWRHYW1lcGFkcyA6ICIiCi0gICAgICAgIHRleHQ6IHFzVHIoIlZpYmVtaXMgZGV0ZWN0ZWQg
Z2FtZXBhZHMgd2l0aG91dCBhIG1hcHBpbmc6IikgKyAiXG4iICsgdW5tYXBwZWRHYW1lcGFkcwor
ICAgICAgICB0ZXh0OiBxc1RyKCJFY2xpcHNlIGRldGVjdGVkIGdhbWVwYWRzIHdpdGhvdXQgYSBt
YXBwaW5nOiIpICsgIlxuIiArIHVubWFwcGVkR2FtZXBhZHMKICAgICAgICAgaGVscFRleHRTZXBh
cmF0b3I6ICJcblxuIgogICAgICAgICBoZWxwVGV4dDogcXNUcigiQ2xpY2sgdGhlIEhlbHAgYnV0
dG9uIGZvciBpbmZvcm1hdGlvbiBvbiBob3cgdG8gbWFwIHlvdXIgZ2FtZXBhZHMuIikKICAgICAg
ICAgaGVscFVybDogImh0dHBzOi8vZ2l0aHViLmNvbS9uYXZ5YXMzMjEvdmliZW1pcyIKZGlmZiAt
LWdpdCBhL2FwcC9tYWluLmNwcCBiL2FwcC9tYWluLmNwcAppbmRleCAyOTIyMjc3Li4zZWM5NGRi
IDEwMDY0NAotLS0gYS9hcHAvbWFpbi5jcHAKKysrIGIvYXBwL21haW4uY3BwCkBAIC04NjksNiAr
ODY5LDcgQEAgaW50IG1haW4oaW50IGFyZ2MsIGNoYXIgKmFyZ3ZbXSkKICAgICB9DQogDQogICAg
IFFHdWlBcHBsaWNhdGlvbiBhcHAoYXJnYywgYXJndik7DQorICAgIFFHdWlBcHBsaWNhdGlvbjo6
c2V0QXBwbGljYXRpb25EaXNwbGF5TmFtZSgiRWNsaXBzZSIpOwogDQogICAgIC8vIFZpYmVtaXM6
IHRoZSBRdCBRdWljayBDb250cm9scyBNYXRlcmlhbCBzdHlsZSByZW5kZXJzIGJ1dHRvbiB0ZXh0
IGluIEFMTCBDQVBTIGJ5IGRlZmF1bHQNCiAgICAgLy8gKGUuZy4gdGhlIGJpdHJhdGUgIlVTRSBE
RUZBVUxUICgzMCBNQlBTKSIgYnV0dG9uKSwgd2hpY2ggbG9va3Mgb2ZmLiBGb3JjZSBtaXhlZCBj
YXNlIGZvciB0aGUNCmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbmdyYXBocy5o
IGIvYXBwL21vb25saWdodG9zL2NyaW1zb25ncmFwaHMuaApuZXcgZmlsZSBtb2RlIDEwMDY0NApp
bmRleCAwMDAwMDAwLi5jZGNjM2EwCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9z
L2NyaW1zb25ncmFwaHMuaApAQCAtMCwwICsxLDYzIEBACisjcHJhZ21hIG9uY2UKKyNpbmNsdWRl
IDxRTWFwPgorI2luY2x1ZGUgPFFWZWN0b3I+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CisjaW5j
bHVkZSA8UVJlZ3VsYXJFeHByZXNzaW9uPgorI2luY2x1ZGUgPFFQYWludGVyPgorI2luY2x1ZGUg
PFFQYWludGVyUGF0aD4KKyNpbmNsdWRlIDxRRm9udD4KKyNpbmNsdWRlIDxRdE1hdGg+CisjaW5j
bHVkZSA8bGltaXRzPgorI2luY2x1ZGUgIm92ZXJsYXlzdHlsZS5oIgorbmFtZXNwYWNlIENyaW1z
b25HcmFwaHMgewordXNpbmcgSGlzdG9yeT1RTWFwPFFTdHJpbmcsUVZlY3Rvcjxkb3VibGU+PjsK
K2lubGluZSBkb3VibGUgbWlzc2luZygpIHsgcmV0dXJuIHN0ZDo6bnVtZXJpY19saW1pdHM8ZG91
YmxlPjo6cXVpZXRfTmFOKCk7IH0KK2lubGluZSBRTWFwPFFTdHJpbmcsZG91YmxlPiB2YWx1ZXMo
Y29uc3QgUVN0cmluZyYgdGV4dCxib29sIGxvY2FsLGNvbnN0IFFWYXJpYW50TWFwJiBoYXJkd2Fy
ZSkgeworICAgIFFNYXA8UVN0cmluZyxkb3VibGU+IHJlc3VsdDsKKyAgICBhdXRvIHRha2U9WyZd
KGNvbnN0IFFTdHJpbmcmIGtleSxjb25zdCBRU3RyaW5nJiBzb3VyY2UpIHsKKyAgICAgICAgYm9v
bCBvaz1mYWxzZTsKKyAgICAgICAgY29uc3QgYXV0byB2YWx1ZT1oYXJkd2FyZS52YWx1ZShzb3Vy
Y2UpOworICAgICAgICBkb3VibGUgbnVtYmVyPXZhbHVlLnRvRG91YmxlKCZvayk7CisgICAgICAg
IHJlc3VsdFtrZXldPSF2YWx1ZS5pc051bGwoKSYmb2smJnFJc0Zpbml0ZShudW1iZXIpJiZudW1i
ZXI+PTA/bnVtYmVyOm1pc3NpbmcoKTsKKyAgICB9OworICAgIHRha2UoIkxvY2FsIENQVSIsImNw
dVBlcmNlbnQiKTt0YWtlKCJMb2NhbCBSQU0iLCJtZW1vcnlVc2VkR2lCIik7CisgICAgaWYobG9j
YWwpIHt0YWtlKCJUZW1wZXJhdHVyZSIsInRlbXBlcmF0dXJlQyIpO3Rha2UoIkRvd25sb2FkIiwi
cmVjZWl2ZU1pQiIpO30KKyAgICBlbHNlIHsKKyAgICAgICAgYXV0byBmcHM9UVJlZ3VsYXJFeHBy
ZXNzaW9uKCJSZW5kZXJpbmcgZnJhbWUgcmF0ZTogKFswLTldKyg/OlxcLlswLTldKyk/KSBGUFMi
KS5tYXRjaCh0ZXh0KTsKKyAgICAgICAgaWYoIWZwcy5oYXNNYXRjaCgpKSBmcHM9UVJlZ3VsYXJF
eHByZXNzaW9uKCJeKFswLTldKyg/OlxcLlswLTldKyk/KSBmcHMiLFFSZWd1bGFyRXhwcmVzc2lv
bjo6Q2FzZUluc2Vuc2l0aXZlT3B0aW9uKS5tYXRjaCh0ZXh0KTsKKyAgICAgICAgcmVzdWx0WyJG
UFMiXT1mcHMuaGFzTWF0Y2goKT9mcHMuY2FwdHVyZWQoMSkudG9Eb3VibGUoKTptaXNzaW5nKCk7
CisgICAgICAgIGF1dG8gbGF0ZW5jeT1RUmVndWxhckV4cHJlc3Npb24oIkF2ZXJhZ2UgbmV0d29y
ayBsYXRlbmN5OiAoWzAtOV0rKD86XFwuWzAtOV0rKT8pIikubWF0Y2godGV4dCk7CisgICAgICAg
IGlmKCFsYXRlbmN5Lmhhc01hdGNoKCkpIGxhdGVuY3k9UVJlZ3VsYXJFeHByZXNzaW9uKCJcXGJu
ZXQgKFswLTldKyg/OlxcLlswLTldKyk/KSBtcyIpLm1hdGNoKHRleHQpOworICAgICAgICByZXN1
bHRbIk5ldHdvcmsgbGF0ZW5jeSJdPWxhdGVuY3kuaGFzTWF0Y2goKT9sYXRlbmN5LmNhcHR1cmVk
KDEpLnRvRG91YmxlKCk6bWlzc2luZygpOworICAgIH0KKyAgICByZXR1cm4gcmVzdWx0OworfQor
aW5saW5lIHZvaWQgcHVzaChIaXN0b3J5JiBoaXN0b3J5LGNvbnN0IFFNYXA8UVN0cmluZyxkb3Vi
bGU+JiB2YWx1ZXMpIHsKKyAgICBmb3IoYXV0byBpPXZhbHVlcy5jYmVnaW4oKTtpIT12YWx1ZXMu
Y2VuZCgpOysraSkge2F1dG8mIHNlcmllcz1oaXN0b3J5W2kua2V5KCldO3Nlcmllcy5hcHBlbmQo
cUlzRmluaXRlKGkudmFsdWUoKSkmJmkudmFsdWUoKT49MD9pLnZhbHVlKCk6bWlzc2luZygpKTt3
aGlsZShzZXJpZXMuc2l6ZSgpPjYwKXNlcmllcy5yZW1vdmVGaXJzdCgpO30KK30KK2lubGluZSBR
U3RyaW5nTGlzdCBrZXlzKGJvb2wgbG9jYWwpIHtyZXR1cm4gbG9jYWw/UVN0cmluZ0xpc3R7Ikxv
Y2FsIENQVSIsIkxvY2FsIFJBTSIsIlRlbXBlcmF0dXJlIiwiRG93bmxvYWQifTpRU3RyaW5nTGlz
dHsiRlBTIiwiTmV0d29yayBsYXRlbmN5IiwiTG9jYWwgQ1BVIiwiTG9jYWwgUkFNIn07fQoraW5s
aW5lIHZvaWQgcGFpbnQoUUltYWdlJiBpbWFnZSxpbnQgdG9wLGludCBmb250U2l6ZSxpbnQgYWNj
ZW50SW5kZXgsY29uc3QgSGlzdG9yeSYgaGlzdG9yeSxib29sIGxvY2FsKSB7CisgICAgUVBhaW50
ZXIgcCgmaW1hZ2UpO3Auc2V0UmVuZGVySGludChRUGFpbnRlcjo6QW50aWFsaWFzaW5nKTtRRm9u
dCBmb250KCJEZWphVnUgU2FucyIpO2ZvbnQuc2V0UGl4ZWxTaXplKGZvbnRTaXplKTtwLnNldEZv
bnQoZm9udCk7CisgICAgY29uc3QgaW50IHJvd0hlaWdodD1mb250U2l6ZSsyMjtpbnQgcm93PTA7
CisgICAgZm9yKGNvbnN0IGF1dG8mIGtleTprZXlzKGxvY2FsKSkgeworICAgICAgICBjb25zdCBh
dXRvIHNlcmllcz1oaXN0b3J5LnZhbHVlKGtleSk7ZG91YmxlIGN1cnJlbnQ9c2VyaWVzLmlzRW1w
dHkoKT9taXNzaW5nKCk6c2VyaWVzLmxhc3QoKTsKKyAgICAgICAgUVN0cmluZyB1bml0PWtleT09
IkxvY2FsIENQVSI/IiUiOmtleT09IkxvY2FsIFJBTSI/IiBHaUIiOmtleT09IlRlbXBlcmF0dXJl
Ij8iIMKwQyI6a2V5PT0iRG93bmxvYWQiPyIgTWlCL3MiOmtleT09Ik5ldHdvcmsgbGF0ZW5jeSI/
IiBtcyI6IiI7CisgICAgICAgIFFTdHJpbmcgdmFsdWU9cUlzRmluaXRlKGN1cnJlbnQpP1FTdHJp
bmc6Om51bWJlcihjdXJyZW50LCdmJyxrZXk9PSJGUFMiPzA6MSkrdW5pdDpRU3RyaW5nKCJVbmF2
YWlsYWJsZSIpOworICAgICAgICBjb25zdCBpbnQgeT10b3Arcm93Kysqcm93SGVpZ2h0OworICAg
ICAgICBwLnNldFBlbihRQ29sb3IoIiM5OEExQUIiKSk7cC5kcmF3VGV4dChRUmVjdCgxNix5LGlt
YWdlLndpZHRoKCktMzIscm93SGVpZ2h0KSxRdDo6QWxpZ25WQ2VudGVyLGtleSk7CisgICAgICAg
IGNvbnN0IGludCBncmFwaFdpZHRoPTk2OworICAgICAgICBwLnNldFBlbihRQ29sb3IoIiNFQ0VF
RjEiKSk7cC5kcmF3VGV4dChRUmVjdCgxODUseSxpbWFnZS53aWR0aCgpLWdyYXBoV2lkdGgtMjE1
LHJvd0hlaWdodCksUXQ6OkFsaWduUmlnaHR8UXQ6OkFsaWduVkNlbnRlcix2YWx1ZSk7CisgICAg
ICAgIFFSZWN0RiBib3VuZHMoaW1hZ2Uud2lkdGgoKS1ncmFwaFdpZHRoLTE0LHkrNyxncmFwaFdp
ZHRoLHJvd0hlaWdodC0xNCk7CisgICAgICAgIGRvdWJsZSBoaWdoPWtleT09IkxvY2FsIENQVSI/
MTAwOjE7CisgICAgICAgIGlmKGtleSE9IkxvY2FsIENQVSIpZm9yKGRvdWJsZSBuOnNlcmllcylp
ZihxSXNGaW5pdGUobikpaGlnaD1xTWF4KGhpZ2gsbioxLjE1KTsKKyAgICAgICAgUVBhaW50ZXJQ
YXRoIHBhdGg7Ym9vbCBzdGFydGVkPWZhbHNlOworICAgICAgICBmb3IoaW50IGk9MDtpPHNlcmll
cy5zaXplKCk7aSsrKSB7ZG91YmxlIHY9c2VyaWVzW2ldO2lmKCFxSXNGaW5pdGUodikpe3N0YXJ0
ZWQ9ZmFsc2U7Y29udGludWU7fQorICAgICAgICAgICAgUVBvaW50RiBwb2ludChib3VuZHMubGVm
dCgpK2JvdW5kcy53aWR0aCgpKig2MC1zZXJpZXMuc2l6ZSgpK2kpLzU5LjAsYm91bmRzLmJvdHRv
bSgpLWJvdW5kcy5oZWlnaHQoKSpxQm91bmQoMC4wLHYvaGlnaCwxLjApKTsKKyAgICAgICAgICAg
IGlmKCFzdGFydGVkKXBhdGgubW92ZVRvKHBvaW50KTtlbHNlIHBhdGgubGluZVRvKHBvaW50KTtz
dGFydGVkPXRydWU7CisgICAgICAgIH0KKyAgICAgICAgcC5zZXRQZW4oUVBlbihFY2xpcHNlT3Zl
cmxheVN0eWxlOjphY2NlbnQoYWNjZW50SW5kZXgpLDEuNSkpO3AuZHJhd1BhdGgocGF0aCk7Cisg
ICAgICAgIGlmKHFJc0Zpbml0ZShjdXJyZW50KSkge3Auc2V0QnJ1c2goRWNsaXBzZU92ZXJsYXlT
dHlsZTo6YWNjZW50KGFjY2VudEluZGV4KSk7cC5kcmF3RWxsaXBzZShRUG9pbnRGKGJvdW5kcy5y
aWdodCgpLGJvdW5kcy5ib3R0b20oKS1ib3VuZHMuaGVpZ2h0KCkqcUJvdW5kKDAuMCxjdXJyZW50
L2hpZ2gsMS4wKSksMS41LDEuNSk7fQorICAgICAgICBwLnNldFBlbihRQ29sb3IoMjU1LDI1NSwy
NTUsMTQpKTtwLmRyYXdMaW5lKDE2LHkrcm93SGVpZ2h0LTEsaW1hZ2Uud2lkdGgoKS0xNix5K3Jv
d0hlaWdodC0xKTsKKyAgICB9Cit9Cit9CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvY3Jp
bXNvbnN0YXR1cy5jcHAgYi9hcHAvbW9vbmxpZ2h0b3MvY3JpbXNvbnN0YXR1cy5jcHAKbmV3IGZp
bGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uZGFmY2EyZQotLS0gL2Rldi9udWxsCisrKyBi
L2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmNwcApAQCAtMCwwICsxLDIyMiBAQAorI2lu
Y2x1ZGUgImNyaW1zb25zdGF0dXMuaCIKKyNpbmNsdWRlIDxRRGF0ZVRpbWU+CisjaW5jbHVkZSA8
UURpcj4KKyNpbmNsdWRlIDxRRmlsZT4KKyNpbmNsdWRlIDxRSnNvbkRvY3VtZW50PgorI2luY2x1
ZGUgPFFKc29uT2JqZWN0PgorI2luY2x1ZGUgPFFOZXR3b3JrSW50ZXJmYWNlPgorI2luY2x1ZGUg
PFFOZXR3b3JrUmVxdWVzdD4KKyNpbmNsdWRlIDxRU2F2ZUZpbGU+CisjaW5jbHVkZSA8UVNzbENl
cnRpZmljYXRlPgorI2luY2x1ZGUgPFFTc2xFcnJvcj4KKyNpbmNsdWRlIDxRU3RhbmRhcmRQYXRo
cz4KKyNpbmNsdWRlIDxRQ3J5cHRvZ3JhcGhpY0hhc2g+CisjaW5jbHVkZSA8UVVybD4KKyNpbmNs
dWRlIDxjbWF0aD4KKyNpbmNsdWRlIDxRUW1sRW5naW5lPgorI2luY2x1ZGUgPFFDb3JlQXBwbGlj
YXRpb24+CisjaW5jbHVkZSA8bWVtb3J5PgorI2luY2x1ZGUgPFFSZWd1bGFyRXhwcmVzc2lvbj4K
KyNpbmNsdWRlIDxRRmlsZUluZm8+CisjaW5jbHVkZSA8UVNzbENvbmZpZ3VyYXRpb24+CisKK25h
bWVzcGFjZSB7CitRU3RyaW5nIHJlYWQoY29uc3QgUVN0cmluZyYgcGF0aCkgeworICAgIFFGaWxl
IGYocGF0aCk7IHJldHVybiBmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkgPyBRU3RyaW5nOjpm
cm9tVXRmOChmLnJlYWRBbGwoKSkudHJpbW1lZCgpIDogUVN0cmluZygpOworfQorY29uc3QgYXV0
byB1c2VyT25seSA9IFFGaWxlRGV2aWNlOjpSZWFkT3duZXIgfCBRRmlsZURldmljZTo6V3JpdGVP
d25lcjsKK30KK0NyaW1zb25TdGF0dXM6OkNyaW1zb25TdGF0dXMoUU9iamVjdCogcGFyZW50KSA6
IFFPYmplY3QocGFyZW50KSB7CisgICAgY29ubmVjdCgmbV9sb2NhbFRpbWVyLCAmUVRpbWVyOjp0
aW1lb3V0LCB0aGlzLCAmQ3JpbXNvblN0YXR1czo6cmVmcmVzaExvY2FsKTsKKyAgICBjb25uZWN0
KCZtX3N0YXRzVGltZXIsICZRVGltZXI6OnRpbWVvdXQsIHRoaXMsICZDcmltc29uU3RhdHVzOjpy
ZWZyZXNoKTsKKyAgICBjb25uZWN0KCZtX3dpZmksICZRUHJvY2Vzczo6ZmluaXNoZWQsIHRoaXMs
IFt0aGlzXShpbnQgZXhpdCwgUVByb2Nlc3M6OkV4aXRTdGF0dXMpIHsKKyAgICAgICAgaWYgKGV4
aXQgPT0gMCkgeworICAgICAgICAgICAgY29uc3QgYXV0byBsaW5lcyA9IFFTdHJpbmc6OmZyb21V
dGY4KG1fd2lmaS5yZWFkQWxsU3RhbmRhcmRPdXRwdXQoKSkuc3BsaXQoJ1xuJyk7CisgICAgICAg
ICAgICBmb3IgKGNvbnN0IGF1dG8mIGxpbmUgOiBsaW5lcykgeworICAgICAgICAgICAgICAgIGlm
ICghbGluZS5zdGFydHNXaXRoKCJ5ZXM6IikpIGNvbnRpbnVlOworICAgICAgICAgICAgICAgIGlu
dCBzZXBhcmF0b3IgPSBsaW5lLmluZGV4T2YoJzonLCA0KTsgYm9vbCBvayA9IGZhbHNlOworICAg
ICAgICAgICAgICAgIGludCBzaWduYWwgPSBsaW5lLm1pZCg0LCBzZXBhcmF0b3IgLSA0KS50b0lu
dCgmb2spOworICAgICAgICAgICAgICAgIGlmIChvayAmJiBzaWduYWwgPj0gMCAmJiBzaWduYWwg
PD0gMTAwKSBtX2xvY2FsWyJ3aWZpU2lnbmFsIl0gPSBzaWduYWw7CisgICAgICAgICAgICAgICAg
aWYgKHNlcGFyYXRvciA+PSAwKSBtX2xvY2FsWyJuZXR3b3JrIl0gPSB0cigiV2ktRmk6ICUxIiku
YXJnKGxpbmUubWlkKHNlcGFyYXRvciArIDEpKTsKKyAgICAgICAgICAgICAgICBicmVhazsKKyAg
ICAgICAgICAgIH0KKyAgICAgICAgICAgIGVtaXQgbG9jYWxDaGFuZ2VkKCk7CisgICAgICAgIH0K
KyAgICB9KTsKKyAgICBtX2xvY2FsVGltZXIuc3RhcnQoMTAwMDApOyBtX3N0YXRzVGltZXIuc2V0
SW50ZXJ2YWwoMjAwMCk7IHJlZnJlc2hMb2NhbCgpOworfQorQ3JpbXNvblN0YXR1czo6fkNyaW1z
b25TdGF0dXMoKSB7CisgICAgbV9zdGF0c1RpbWVyLnN0b3AoKTsgbV9sb2NhbFRpbWVyLnN0b3Ao
KTsgY2FuY2VsKCk7CisgICAgaWYgKG1fd2lmaS5zdGF0ZSgpICE9IFFQcm9jZXNzOjpOb3RSdW5u
aW5nKSB7IG1fd2lmaS5raWxsKCk7IG1fd2lmaS53YWl0Rm9yRmluaXNoZWQoNTAwKTsgfQorfQor
UVN0cmluZyBDcmltc29uU3RhdHVzOjpjb25maWdGaWxlKCkgY29uc3QgeworICAgIHJldHVybiBR
U3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRhcmRQYXRoczo6QXBwQ29uZmln
TG9jYXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpzb24iOworfQorUVN0cmluZyBDcmltc29uU3Rh
dHVzOjpub3JtYWxpemVkUGluKFFTdHJpbmcgcGluKSB7CisgICAgcGluLnJlbW92ZSgnOicpOyBw
aW4ucmVtb3ZlKCcgJyk7IHJldHVybiBwaW4udG9Mb3dlcigpOworfQorYm9vbCBDcmltc29uU3Rh
dHVzOjp2YWxpZEVuZHBvaW50KGNvbnN0IFFTdHJpbmcmIHZhbHVlKSB7CisgICAgUVVybCB1KHZh
bHVlLCBRVXJsOjpTdHJpY3RNb2RlKTsKKyAgICByZXR1cm4gdS5pc1ZhbGlkKCkgJiYgdS5zY2hl
bWUoKSA9PSAiaHR0cHMiICYmICF1Lmhvc3QoKS5pc0VtcHR5KCkgJiYKKyAgICAgICAgdS51c2Vy
SW5mbygpLmlzRW1wdHkoKSAmJiB1LnF1ZXJ5KCkuaXNFbXB0eSgpICYmIHUuZnJhZ21lbnQoKS5p
c0VtcHR5KCkgJiYKKyAgICAgICAgKHUucGF0aCgpLmlzRW1wdHkoKSB8fCB1LnBhdGgoKSA9PSAi
LyIpICYmIHUucG9ydCg0Nzk5MCkgPiAwOworfQordm9pZCBDcmltc29uU3RhdHVzOjpjYW5jZWwo
KSB7CisgICAgaWYgKG1fcmVwbHkpIHsgZGlzY29ubmVjdChtX3JlcGx5LCBudWxscHRyLCB0aGlz
LCBudWxscHRyKTsgbV9yZXBseS0+YWJvcnQoKTsgbV9yZXBseS0+ZGVsZXRlTGF0ZXIoKTsgbV9y
ZXBseSA9IG51bGxwdHI7IH0KK30KK3ZvaWQgQ3JpbXNvblN0YXR1czo6c2VsZWN0SG9zdChRU3Ry
aW5nIGlkLCBRU3RyaW5nIHN1Z2dlc3RlZFVybCkgeworICAgIGlmIChpZCA9PSBtX2hvc3QpIHJl
dHVybjsKKyAgICBjYW5jZWwoKTsgbV9uZXR3b3JrLmNsZWFyQ29ubmVjdGlvbkNhY2hlKCk7IG1f
aG9zdCA9IGlkOyBtX3Rva2VuLmNsZWFyKCk7IG1fcGluLmNsZWFyKCk7CisgICAgbV9lbmRwb2lu
dCA9IHZhbGlkRW5kcG9pbnQoc3VnZ2VzdGVkVXJsKSA/IHN1Z2dlc3RlZFVybCA6IFFTdHJpbmco
KTsKKyAgICBRRmlsZSBmKGNvbmZpZ0ZpbGUoKSk7CisgICAgaWYgKGYub3BlbihRSU9EZXZpY2U6
OlJlYWRPbmx5KSkgeworICAgICAgICBhdXRvIGMgPSBRSnNvbkRvY3VtZW50Ojpmcm9tSnNvbihm
LnJlYWRBbGwoKSkub2JqZWN0KCkudmFsdWUoaWQpLnRvT2JqZWN0KCk7CisgICAgICAgIGlmICh2
YWxpZEVuZHBvaW50KGMudmFsdWUoInVybCIpLnRvU3RyaW5nKCkpKSB7CisgICAgICAgICAgICBt
X2VuZHBvaW50ID0gYy52YWx1ZSgidXJsIikudG9TdHJpbmcoKTsgbV90b2tlbiA9IGMudmFsdWUo
InRva2VuIikudG9TdHJpbmcoKTsgbV9waW4gPSBjLnZhbHVlKCJwaW4iKS50b1N0cmluZygpOwor
ICAgICAgICB9CisgICAgfQorICAgIG1fc3RhdHMuY2xlYXIoKTsgbV9zdGF0dXMgPSBpZC5pc0Vt
cHR5KCkgPyB0cigiQ2hvb3NlIGEgaG9zdCB0byB2aWV3IGhhcmR3YXJlIHN0YXRzIikgOiB0cigi
Q29uZmlndXJlIGEgVmliZXBvbGxvIHJlYWQtb25seSBzdGF0cyB0b2tlbiIpOworICAgIGVtaXQg
Y29uZmlnQ2hhbmdlZCgpOyBlbWl0IHN0YXRzQ2hhbmdlZCgpOyBpZiAobV92aXNpYmxlKSByZWZy
ZXNoKCk7Cit9Citib29sIENyaW1zb25TdGF0dXM6OmNvbmZpZ3VyZShRU3RyaW5nIHVybCwgUVN0
cmluZyB0b2tlbiwgUVN0cmluZyBwaW4pIHsKKyAgICBwaW4gPSBub3JtYWxpemVkUGluKHBpbik7
CisgICAgaWYgKG1faG9zdC5pc0VtcHR5KCkgfHwgIXZhbGlkRW5kcG9pbnQodXJsKSB8fCAoIXBp
bi5pc0VtcHR5KCkgJiYKKyAgICAgICAgKHBpbi5zaXplKCkgIT0gNjQgfHwgcGluLmNvbnRhaW5z
KFFSZWd1bGFyRXhwcmVzc2lvbigiW14wLTlhLWZdIikpKSkpIHsKKyAgICAgICAgZmFpbCh0cigi
VXNlIGFuIEhUVFBTIGhvc3QgVVJMIGFuZCBhbiBvcHRpb25hbCA2NC1kaWdpdCBTSEEtMjU2IGNl
cnRpZmljYXRlIGZpbmdlcnByaW50IikpOyByZXR1cm4gZmFsc2U7CisgICAgfQorICAgIC8vIEEg
YmxhbmsgdG9rZW4ga2VlcHMgdGhlIG9sZCB0b2tlbiBvbmx5IGZvciB0aGUgc2FtZSBlbmRwb2lu
dC4KKyAgICBpZiAodG9rZW4uaXNFbXB0eSgpICYmIFFVcmwodXJsKSA9PSBRVXJsKG1fZW5kcG9p
bnQpKSB0b2tlbiA9IG1fdG9rZW47CisgICAgaWYgKHRva2VuLmlzRW1wdHkoKSB8fCB0b2tlbi5j
b250YWlucygnXHInKSB8fCB0b2tlbi5jb250YWlucygnXG4nKSB8fCB0b2tlbi5zaXplKCkgPiA0
MDk2KSB7CisgICAgICAgIGZhaWwodHIoIkEgcmVhZC1vbmx5IFZpYmVwb2xsbyBBUEkgdG9rZW4g
aXMgcmVxdWlyZWQiKSk7IHJldHVybiBmYWxzZTsKKyAgICB9CisgICAgUUZpbGUgZihjb25maWdG
aWxlKCkpOyBRSnNvbk9iamVjdCBhbGw7CisgICAgaWYgKGYub3BlbihRSU9EZXZpY2U6OlJlYWRP
bmx5KSkgYWxsID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24oZi5yZWFkQWxsKCkpLm9iamVjdCgp
OworICAgIGFsbFttX2hvc3RdID0gUUpzb25PYmplY3R7eyJ1cmwiLCB1cmx9LCB7InRva2VuIiwg
dG9rZW59LCB7InBpbiIsIHBpbn19OworICAgIFFEaXIoKS5ta3BhdGgoUUZpbGVJbmZvKGNvbmZp
Z0ZpbGUoKSkuYWJzb2x1dGVQYXRoKCkpOworICAgIFFTYXZlRmlsZSBvdXQoY29uZmlnRmlsZSgp
KTsKKyAgICBpZiAoIW91dC5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSB8fCAhb3V0LnNldFBl
cm1pc3Npb25zKHVzZXJPbmx5KSB8fAorICAgICAgICBvdXQud3JpdGUoUUpzb25Eb2N1bWVudChh
bGwpLnRvSnNvbigpKSA8IDAgfHwgIW91dC5jb21taXQoKSkgeworICAgICAgICBmYWlsKHRyKCJD
b3VsZCBub3Qgc2F2ZSBob3N0IGFjY2VzcyBzZXR0aW5ncyIpKTsgcmV0dXJuIGZhbHNlOworICAg
IH0KKyAgICBjYW5jZWwoKTsgbV9uZXR3b3JrLmNsZWFyQ29ubmVjdGlvbkNhY2hlKCk7IG1fZW5k
cG9pbnQgPSB1cmw7IG1fdG9rZW4gPSB0b2tlbjsgbV9waW4gPSBwaW47CisgICAgbV9zdGF0c1Rp
bWVyLnNldEludGVydmFsKDIwMDApOworICAgIG1fc3RhdHMuY2xlYXIoKTsgbV9zdGF0dXMgPSB0
cigiQ29ubmVjdGluZyB0byBob3N0IHN0YXRz4oCmIik7CisgICAgZW1pdCBjb25maWdDaGFuZ2Vk
KCk7IGVtaXQgc3RhdHNDaGFuZ2VkKCk7IHJlZnJlc2goKTsgcmV0dXJuIHRydWU7Cit9Cit2b2lk
IENyaW1zb25TdGF0dXM6OnNldFZpc2libGUoYm9vbCB2aXNpYmxlKSB7CisgICAgbV92aXNpYmxl
ID0gdmlzaWJsZTsKKyAgICBpZiAodmlzaWJsZSkgeyByZWZyZXNoTG9jYWwoKTsgbV9zdGF0c1Rp
bWVyLnN0YXJ0KCk7IHJlZnJlc2goKTsgfQorICAgIGVsc2UgeyBtX3N0YXRzVGltZXIuc3RvcCgp
OyBjYW5jZWwoKTsgfQorfQordm9pZCBDcmltc29uU3RhdHVzOjpmYWlsKFFTdHJpbmcgbWVzc2Fn
ZSkgeworICAgIG1fc3RhdHMuY2xlYXIoKTsgbV9zdGF0dXMgPSBtZXNzYWdlOworICAgIG1fc3Rh
dHNUaW1lci5zZXRJbnRlcnZhbChxTWluKDMwMDAwLCBxTWF4KDQwMDAsIG1fc3RhdHNUaW1lci5p
bnRlcnZhbCgpICogMikpKTsKKyAgICBlbWl0IHN0YXRzQ2hhbmdlZCgpOworfQorUVZhcmlhbnRN
YXAgQ3JpbXNvblN0YXR1czo6cGFyc2VTdGF0cyhjb25zdCBRQnl0ZUFycmF5JiBieXRlcywgUVN0
cmluZyogZXJyb3IpIHsKKyAgICBpZiAoYnl0ZXMuc2l6ZSgpID4gNjU1MzYpIHsgKmVycm9yID0g
Ik92ZXJzaXplZCBob3N0IHN0YXRzIHJlc3BvbnNlIjsgcmV0dXJuIHt9OyB9CisgICAgUUpzb25Q
YXJzZUVycm9yIGU7IGF1dG8gZG9jID0gUUpzb25Eb2N1bWVudDo6ZnJvbUpzb24oYnl0ZXMsICZl
KTsKKyAgICBpZiAoZS5lcnJvciAhPSBRSnNvblBhcnNlRXJyb3I6Ok5vRXJyb3IgfHwgIWRvYy5p
c09iamVjdCgpKSB7ICplcnJvciA9ICJJbnZhbGlkIGhvc3Qgc3RhdHMgcmVzcG9uc2UiOyByZXR1
cm4ge307IH0KKyAgICBhdXRvIG9iaiA9IGRvYy5vYmplY3QoKTsgUVZhcmlhbnRNYXAgcmVzdWx0
OworICAgIGNvbnN0IFFTdHJpbmdMaXN0IGtleXMgPSB7ImNwdV9wZXJjZW50IiwiY3B1X3RlbXBf
YyIsInJhbV91c2VkX2J5dGVzIiwicmFtX3RvdGFsX2J5dGVzIiwicmFtX3BlcmNlbnQiLAorICAg
ICAgICAiZ3B1X3BlcmNlbnQiLCJncHVfZW5jb2Rlcl9wZXJjZW50IiwiZ3B1X3RlbXBfYyIsInZy
YW1fdXNlZF9ieXRlcyIsInZyYW1fdG90YWxfYnl0ZXMiLCJ2cmFtX3BlcmNlbnQiLCJuZXRfcnhf
YnBzIiwibmV0X3R4X2JwcyJ9OworICAgIGJvb2wgcmVjb2duaXplZCA9IGZhbHNlOworICAgIGZv
ciAoY29uc3QgYXV0byYga2V5IDoga2V5cykgeworICAgICAgICBhdXRvIHYgPSBvYmoudmFsdWUo
a2V5KTsgcmVjb2duaXplZCB8PSBvYmouY29udGFpbnMoa2V5KTsKKyAgICAgICAgZG91YmxlIG4g
PSB2LnRvRG91YmxlKC0xKTsKKyAgICAgICAgaWYgKCF2LmlzRG91YmxlKCkgfHwgIXN0ZDo6aXNm
aW5pdGUobikgfHwgbiA8IDAgfHwgKGtleS5lbmRzV2l0aCgicGVyY2VudCIpICYmIG4gPiAxMDAp
KSBjb250aW51ZTsKKyAgICAgICAgcmVzdWx0W2tleV0gPSBuOworICAgIH0KKyAgICBmb3IgKGNv
bnN0IGF1dG8mIHByZWZpeCA6IHtRU3RyaW5nKCJyYW0iKSwgUVN0cmluZygidnJhbSIpfSkgewor
ICAgICAgICBkb3VibGUgdG90YWwgPSByZXN1bHQudmFsdWUocHJlZml4ICsgIl90b3RhbF9ieXRl
cyIpLnRvRG91YmxlKCk7CisgICAgICAgIGlmICh0b3RhbCA8PSAwKSB7IHJlc3VsdC5yZW1vdmUo
cHJlZml4ICsgIl9wZXJjZW50Iik7IHJlc3VsdC5yZW1vdmUocHJlZml4ICsgIl91c2VkX2J5dGVz
Iik7IH0KKyAgICAgICAgZWxzZSBpZiAocmVzdWx0LmNvbnRhaW5zKHByZWZpeCArICJfdXNlZF9i
eXRlcyIpKSB7CisgICAgICAgICAgICBkb3VibGUgdXNlZCA9IHFNaW4ocmVzdWx0LnZhbHVlKHBy
ZWZpeCArICJfdXNlZF9ieXRlcyIpLnRvRG91YmxlKCksIHRvdGFsKTsKKyAgICAgICAgICAgIHJl
c3VsdFtwcmVmaXggKyAiX3VzZWRfYnl0ZXMiXSA9IHVzZWQ7IHJlc3VsdFtwcmVmaXggKyAiX3Bl
cmNlbnQiXSA9IHVzZWQgKiAxMDAgLyB0b3RhbDsKKyAgICAgICAgfQorICAgIH0KKyAgICBpZiAo
IXJlY29nbml6ZWQpIHsgKmVycm9yID0gIkhvc3QgZG9lcyBub3QgZXhwb3NlIHRoZSBleHBlY3Rl
ZCBWaWJlcG9sbG8gc3RhdHMgZmllbGRzIjsgcmV0dXJuIHt9OyB9CisgICAgZXJyb3ItPmNsZWFy
KCk7IHJldHVybiByZXN1bHQ7Cit9Cit2b2lkIENyaW1zb25TdGF0dXM6OnJlZnJlc2goKSB7Cisg
ICAgaWYgKCFtX3Zpc2libGUgfHwgbV9yZXBseSB8fCAhY29uZmlndXJlZCgpKSByZXR1cm47Cisg
ICAgUVVybCB1cmwobV9lbmRwb2ludCk7IHVybC5zZXRQYXRoKCIvYXBpL2hvc3Qvc3RhdHMiKTsK
KyAgICBRTmV0d29ya1JlcXVlc3QgcmVxKHVybCk7CisgICAgcmVxLnNldEF0dHJpYnV0ZShRTmV0
d29ya1JlcXVlc3Q6OlJlZGlyZWN0UG9saWN5QXR0cmlidXRlLCBRTmV0d29ya1JlcXVlc3Q6Ok1h
bnVhbFJlZGlyZWN0UG9saWN5KTsKKyAgICByZXEuc2V0VHJhbnNmZXJUaW1lb3V0KDMwMDApOwor
ICAgIHJlcS5zZXRSYXdIZWFkZXIoIkF1dGhvcml6YXRpb24iLCAiQmVhcmVyICIgKyBtX3Rva2Vu
LnRvVXRmOCgpKTsKKyAgICByZXEuc2V0UmF3SGVhZGVyKCJBY2NlcHQiLCAiYXBwbGljYXRpb24v
anNvbiIpOworICAgIGF1dG8gcmVwbHkgPSBtX25ldHdvcmsuZ2V0KHJlcSk7IHJlcGx5LT5zZXRS
ZWFkQnVmZmVyU2l6ZSg2NTUzNik7IG1fcmVwbHkgPSByZXBseTsKKyAgICBhdXRvIGRhdGEgPSBz
dGQ6Om1ha2Vfc2hhcmVkPFFCeXRlQXJyYXk+KCk7CisgICAgYXV0byBpbnZhbGlkUGluID0gc3Rk
OjptYWtlX3NoYXJlZDxib29sPihmYWxzZSk7CisgICAgYXV0byBvdmVyc2l6ZWQgPSBzdGQ6Om1h
a2Vfc2hhcmVkPGJvb2w+KGZhbHNlKTsKKyAgICBhdXRvIGNlcnRNYXRjaGVzID0gW3RoaXMsIHJl
cGx5XSB7CisgICAgICAgIHJldHVybiBub3JtYWxpemVkUGluKFFTdHJpbmc6OmZyb21MYXRpbjEo
cmVwbHktPnNzbENvbmZpZ3VyYXRpb24oKS5wZWVyQ2VydGlmaWNhdGUoKS5kaWdlc3QoUUNyeXB0
b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpKSA9PSBtX3BpbjsKKyAgICB9OworICAgIGNv
bm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5OjplbmNyeXB0ZWQsIHRoaXMsIFt0aGlzLCByZXBs
eSwgY2VydE1hdGNoZXMsIGludmFsaWRQaW5dIHsKKyAgICAgICAgaWYgKCFtX3Bpbi5pc0VtcHR5
KCkgJiYgIWNlcnRNYXRjaGVzKCkpIHsgKmludmFsaWRQaW4gPSB0cnVlOyByZXBseS0+YWJvcnQo
KTsgfQorICAgIH0pOworICAgIGNvbm5lY3QocmVwbHksICZRTmV0d29ya1JlcGx5Ojpzc2xFcnJv
cnMsIHRoaXMsIFt0aGlzLCByZXBseSwgY2VydE1hdGNoZXNdKGNvbnN0IFFMaXN0PFFTc2xFcnJv
cj4mIGVycm9ycykgeworICAgICAgICBpZiAobV9waW4uaXNFbXB0eSgpIHx8ICFjZXJ0TWF0Y2hl
cygpKSByZXR1cm47CisgICAgICAgIGZvciAoY29uc3QgYXV0byYgZSA6IGVycm9ycykgeworICAg
ICAgICAgICAgaWYgKGUuZXJyb3IoKSAhPSBRU3NsRXJyb3I6OlNlbGZTaWduZWRDZXJ0aWZpY2F0
ZSAmJiBlLmVycm9yKCkgIT0gUVNzbEVycm9yOjpTZWxmU2lnbmVkQ2VydGlmaWNhdGVJbkNoYWlu
ICYmCisgICAgICAgICAgICAgICAgZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6Q2VydGlmaWNhdGVV
bnRydXN0ZWQgJiYgZS5lcnJvcigpICE9IFFTc2xFcnJvcjo6SG9zdE5hbWVNaXNtYXRjaCkgcmV0
dXJuOworICAgICAgICB9CisgICAgICAgIHJlcGx5LT5pZ25vcmVTc2xFcnJvcnMoZXJyb3JzKTsg
Ly8gT25seSB0aGlzIGV4cGxpY2l0bHkgcGlubmVkIGhvc3QgY2VydGlmaWNhdGUuCisgICAgfSk7
CisgICAgY29ubmVjdChyZXBseSwgJlFOZXR3b3JrUmVwbHk6OnJlYWR5UmVhZCwgdGhpcywgW3Jl
cGx5LCBkYXRhLCBvdmVyc2l6ZWRdIHsKKyAgICAgICAgaWYgKCpvdmVyc2l6ZWQgfHwgcmVwbHkt
PmlzRmluaXNoZWQoKSkgcmV0dXJuOworICAgICAgICBpZiAoZGF0YS0+c2l6ZSgpICsgcmVwbHkt
PmJ5dGVzQXZhaWxhYmxlKCkgPiA2NTUzNikgeyAqb3ZlcnNpemVkID0gdHJ1ZTsgcmVwbHktPmFi
b3J0KCk7IHJldHVybjsgfQorICAgICAgICBkYXRhLT5hcHBlbmQocmVwbHktPnJlYWRBbGwoKSk7
CisgICAgfSk7CisgICAgY29ubmVjdChyZXBseSwgJlFOZXR3b3JrUmVwbHk6OmZpbmlzaGVkLCB0
aGlzLCBbdGhpcywgcmVwbHksIGRhdGEsIGludmFsaWRQaW4sIG92ZXJzaXplZF0geworICAgICAg
ICBtX3JlcGx5ID0gbnVsbHB0cjsKKyAgICAgICAgaW50IHN0YXR1cyA9IHJlcGx5LT5hdHRyaWJ1
dGUoUU5ldHdvcmtSZXF1ZXN0OjpIdHRwU3RhdHVzQ29kZUF0dHJpYnV0ZSkudG9JbnQoKTsKKyAg
ICAgICAgaWYgKCpvdmVyc2l6ZWQpIGZhaWwodHIoIkhvc3Qgc3RhdHMgcmVzcG9uc2UgZXhjZWVk
ZWQgdGhlIHNpemUgbGltaXQiKSk7CisgICAgICAgIGVsc2UgaWYgKCppbnZhbGlkUGluKSBmYWls
KHRyKCJIb3N0IGNlcnRpZmljYXRlIGNoYW5nZWQ7IHZlcmlmeSB0aGUgc2F2ZWQgZmluZ2VycHJp
bnQiKSk7CisgICAgICAgIGVsc2UgaWYgKHN0YXR1cyA9PSA0MDEgfHwgc3RhdHVzID09IDQwMykg
ZmFpbCh0cigiSG9zdCBzdGF0cyBhY2Nlc3MgZGVuaWVkOiBjaGVjayB0aGUgcmVhZC1vbmx5IHRv
a2VuIikpOworICAgICAgICBlbHNlIGlmIChzdGF0dXMgPT0gNDA0KSBmYWlsKHRyKCJUaGlzIGhv
c3QgZG9lcyBub3QgcHJvdmlkZSBWaWJlcG9sbG8gaGFyZHdhcmUgc3RhdHMiKSk7CisgICAgICAg
IGVsc2UgaWYgKHJlcGx5LT5lcnJvcigpID09IFFOZXR3b3JrUmVwbHk6OlNzbEhhbmRzaGFrZUZh
aWxlZEVycm9yKSBmYWlsKHRyKCJWZXJpZnkgdGhlIGhvc3QgY2VydGlmaWNhdGUgZmluZ2VycHJp
bnQgaW4gQ29uZmlndXJlIikpOworICAgICAgICBlbHNlIGlmIChyZXBseS0+ZXJyb3IoKSAhPSBR
TmV0d29ya1JlcGx5OjpOb0Vycm9yIHx8IHN0YXR1cyAhPSAyMDApIGZhaWwodHIoIkhvc3Qgc3Rh
dHMgdW5hdmFpbGFibGU6IGNoZWNrIGNvbm5lY3Rpb24gYW5kIHJlYWx0aW1lIHN0YXRzIHNldHRp
bmciKSk7CisgICAgICAgIGVsc2UgeworICAgICAgICAgICAgZGF0YS0+YXBwZW5kKHJlcGx5LT5y
ZWFkQWxsKCkpOyBRU3RyaW5nIGVycm9yOworICAgICAgICAgICAgYXV0byBwYXJzZWQgPSBwYXJz
ZVN0YXRzKCpkYXRhLCAmZXJyb3IpOworICAgICAgICAgICAgaWYgKCFlcnJvci5pc0VtcHR5KCkp
IGZhaWwoZXJyb3IpOworICAgICAgICAgICAgZWxzZSB7IG1fc3RhdHNUaW1lci5zZXRJbnRlcnZh
bCgyMDAwKTsgbV9zdGF0cyA9IHBhcnNlZDsgbV9zdGF0dXMgPSB0cigiSE9TVCDigKIgcmVjZWl2
ZWQgJTEiKS5hcmcoUURhdGVUaW1lOjpjdXJyZW50RGF0ZVRpbWUoKS50b1N0cmluZygiaGg6bW06
c3MiKSk7IGVtaXQgc3RhdHNDaGFuZ2VkKCk7IH0KKyAgICAgICAgfQorICAgICAgICByZXBseS0+
ZGVsZXRlTGF0ZXIoKTsKKyAgICB9KTsKKyAgICAvLyBBYnNvbHV0ZSByZXF1ZXN0IGJvdW5kIGV2
ZW4gaWYgYSBwZWVyIGtlZXBzIHNlbmRpbmcgb2NjYXNpb25hbCBieXRlcy4KKyAgICBRVGltZXI6
OnNpbmdsZVNob3QoMzUwMCwgcmVwbHksIFtyZXBseV0geyBpZiAoIXJlcGx5LT5pc0ZpbmlzaGVk
KCkpIHJlcGx5LT5hYm9ydCgpOyB9KTsKK30KK1FWYXJpYW50TWFwIENyaW1zb25TdGF0dXM6OnJl
YWRMb2NhbChjb25zdCBRU3RyaW5nJiByb290KSB7CisgICAgUVZhcmlhbnRNYXAgb3V0OyBRU3Ry
aW5nTGlzdCBuZXR3b3JrczsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIG5hbWUgOiBRRGlyKHJvb3Qg
KyAiL2NsYXNzL25ldCIpLmVudHJ5TGlzdChRRGlyOjpEaXJzIHwgUURpcjo6Tm9Eb3RBbmREb3RE
b3QpKSB7CisgICAgICAgIGlmIChuYW1lID09ICJsbyIgfHwgcmVhZChyb290ICsgIi9jbGFzcy9u
ZXQvIiArIG5hbWUgKyAiL29wZXJzdGF0ZSIpICE9ICJ1cCIpIGNvbnRpbnVlOworICAgICAgICBu
ZXR3b3JrcyA8PCBuYW1lOworICAgIH0KKyAgICBvdXRbImNvbm5lY3RlZCJdID0gIW5ldHdvcmtz
LmlzRW1wdHkoKTsgb3V0WyJuZXR3b3JrIl0gPSBuZXR3b3Jrcy5pc0VtcHR5KCkgPyB0cigiTm8g
YWN0aXZlIG5ldHdvcmsgbGluayIpIDogbmV0d29ya3Muam9pbigiLCAiKTsKKyAgICAvLyBMaW5r
IHN0YXR1cyBpcyBpbnRlbnRpb25hbGx5IG5vdCBwcmVzZW50ZWQgYXMgaW50ZXJuZXQgcmVhY2hh
YmlsaXR5LgorICAgIG91dFsiYmF0dGVyeVBlcmNlbnQiXSA9IC0xOyBvdXRbImJhdHRlcnlTdGF0
ZSJdID0gdHIoIkJhdHRlcnkgdW5hdmFpbGFibGUiKTsKKyAgICBmb3IgKGNvbnN0IGF1dG8mIG5h
bWUgOiBRRGlyKHJvb3QgKyAiL2NsYXNzL3Bvd2VyX3N1cHBseSIpLmVudHJ5TGlzdChRRGlyOjpE
aXJzIHwgUURpcjo6Tm9Eb3RBbmREb3REb3QpKSB7CisgICAgICAgIGNvbnN0IGF1dG8gYmFzZSA9
IHJvb3QgKyAiL2NsYXNzL3Bvd2VyX3N1cHBseS8iICsgbmFtZSArICIvIjsKKyAgICAgICAgaWYg
KHJlYWQoYmFzZSArICJ0eXBlIikgIT0gIkJhdHRlcnkiIHx8IHJlYWQoYmFzZSArICJwcmVzZW50
IikgPT0gIjAiKSBjb250aW51ZTsKKyAgICAgICAgYm9vbCBvazsgaW50IGNhcCA9IHJlYWQoYmFz
ZSArICJjYXBhY2l0eSIpLnRvSW50KCZvayk7CisgICAgICAgIGlmIChvayAmJiBjYXAgPj0gMCAm
JiBjYXAgPD0gMTAwKSBvdXRbImJhdHRlcnlQZXJjZW50Il0gPSBjYXA7CisgICAgICAgIGNvbnN0
IGF1dG8gc3RhdGUgPSByZWFkKGJhc2UgKyAic3RhdHVzIik7IG91dFsiYmF0dGVyeVN0YXRlIl0g
PSBzdGF0ZS5pc0VtcHR5KCkgPyB0cigiVW5rbm93biIpIDogc3RhdGU7IGJyZWFrOworICAgIH0K
KyAgICByZXR1cm4gb3V0OworfQordm9pZCBDcmltc29uU3RhdHVzOjpyZWZyZXNoTG9jYWwoKSB7
CisgICAgbV9sb2NhbCA9IHJlYWRMb2NhbCgpOyBtX2xvY2FsWyJ3aWZpU2lnbmFsIl0gPSAtMTsg
ZW1pdCBsb2NhbENoYW5nZWQoKTsKKyAgICBpZiAobV93aWZpLnN0YXRlKCkgPT0gUVByb2Nlc3M6
Ok5vdFJ1bm5pbmcpIHsKKyAgICAgICAgbV93aWZpLnN0YXJ0KCJubWNsaSIsIHsiLXQiLCAiLS1l
c2NhcGUiLCAibm8iLCAiLWYiLCAiQUNUSVZFLFNJR05BTCxTU0lEIiwgImRldmljZSIsICJ3aWZp
IiwgImxpc3QiLCAiLS1yZXNjYW4iLCAibm8ifSk7CisgICAgICAgIFFUaW1lcjo6c2luZ2xlU2hv
dCgyMDAwLCAmbV93aWZpLCBbdGhpc10geyBpZiAobV93aWZpLnN0YXRlKCkgIT0gUVByb2Nlc3M6
Ok5vdFJ1bm5pbmcpIG1fd2lmaS5raWxsKCk7IH0pOworICAgIH0KK30KKworc3RhdGljIHZvaWQg
cmVnaXN0ZXJDcmltc29uU3RhdHVzKCkgeworICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9uVHlwZTxD
cmltc29uU3RhdHVzPigiQ3JpbXNvblN0YXR1cyIsIDEsIDAsICJDcmltc29uU3RhdHVzIiwKKyAg
ICAgICAgW10oUVFtbEVuZ2luZSosIFFKU0VuZ2luZSopIC0+IFFPYmplY3QqIHsgcmV0dXJuIG5l
dyBDcmltc29uU3RhdHVzKCk7IH0pOworfQorUV9DT1JFQVBQX1NUQVJUVVBfRlVOQ1RJT04ocmVn
aXN0ZXJDcmltc29uU3RhdHVzKQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL2NyaW1zb25z
dGF0dXMuaCBiL2FwcC9tb29ubGlnaHRvcy9jcmltc29uc3RhdHVzLmgKbmV3IGZpbGUgbW9kZSAx
MDA2NDQKaW5kZXggMDAwMDAwMC4uMmRhYzBkMQotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29u
bGlnaHRvcy9jcmltc29uc3RhdHVzLmgKQEAgLTAsMCArMSw1MiBAQAorI3ByYWdtYSBvbmNlCisj
aW5jbHVkZSA8UU9iamVjdD4KKyNpbmNsdWRlIDxRVmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRVGlt
ZXI+CisjaW5jbHVkZSA8UU5ldHdvcmtBY2Nlc3NNYW5hZ2VyPgorI2luY2x1ZGUgPFFQb2ludGVy
PgorI2luY2x1ZGUgPFFOZXR3b3JrUmVwbHk+CisjaW5jbHVkZSA8UVByb2Nlc3M+CisKKy8vIE9w
dGlvbmFsIGxhdW5jaGVyIHN0YXR1cy4gTmV2ZXIgcGFydGljaXBhdGVzIGluIHRoZSBzdHJlYW1p
bmcvZGVjb2RlciBwYXRoLgorY2xhc3MgQ3JpbXNvblN0YXR1cyA6IHB1YmxpYyBRT2JqZWN0IHsK
KyAgICBRX09CSkVDVAorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgbG9jYWwgUkVBRCBsb2Nh
bCBOT1RJRlkgbG9jYWxDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRNYXAgc3RhdHMg
UkVBRCBzdGF0cyBOT1RJRlkgc3RhdHNDaGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoUVN0cmluZyBz
dGF0dXMgUkVBRCBzdGF0dXMgTk9USUZZIHN0YXRzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKFFT
dHJpbmcgZW5kcG9pbnQgUkVBRCBlbmRwb2ludCBOT1RJRlkgY29uZmlnQ2hhbmdlZCkKKyAgICBR
X1BST1BFUlRZKFFTdHJpbmcgZmluZ2VycHJpbnQgUkVBRCBmaW5nZXJwcmludCBOT1RJRlkgY29u
ZmlnQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgY29uZmlndXJlZCBSRUFEIGNvbmZpZ3Vy
ZWQgTk9USUZZIGNvbmZpZ0NoYW5nZWQpCitwdWJsaWM6CisgICAgZXhwbGljaXQgQ3JpbXNvblN0
YXR1cyhRT2JqZWN0KiBwYXJlbnQgPSBudWxscHRyKTsKKyAgICB+Q3JpbXNvblN0YXR1cygpIG92
ZXJyaWRlOworICAgIFFWYXJpYW50TWFwIGxvY2FsKCkgY29uc3QgeyByZXR1cm4gbV9sb2NhbDsg
fQorICAgIFFWYXJpYW50TWFwIHN0YXRzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0czsgfQorICAg
IFFTdHJpbmcgc3RhdHVzKCkgY29uc3QgeyByZXR1cm4gbV9zdGF0dXM7IH0KKyAgICBRU3RyaW5n
IGVuZHBvaW50KCkgY29uc3QgeyByZXR1cm4gbV9lbmRwb2ludDsgfQorICAgIFFTdHJpbmcgZmlu
Z2VycHJpbnQoKSBjb25zdCB7IHJldHVybiBtX3BpbjsgfQorICAgIGJvb2wgY29uZmlndXJlZCgp
IGNvbnN0IHsgcmV0dXJuICFtX2VuZHBvaW50LmlzRW1wdHkoKSAmJiAhbV90b2tlbi5pc0VtcHR5
KCk7IH0KKyAgICBRX0lOVk9LQUJMRSB2b2lkIHNlbGVjdEhvc3QoUVN0cmluZyBpZCwgUVN0cmlu
ZyBzdWdnZXN0ZWRVcmwpOworICAgIFFfSU5WT0tBQkxFIGJvb2wgY29uZmlndXJlKFFTdHJpbmcg
dXJsLCBRU3RyaW5nIHRva2VuLCBRU3RyaW5nIHBpbik7CisgICAgUV9JTlZPS0FCTEUgdm9pZCBz
ZXRWaXNpYmxlKGJvb2wgdmlzaWJsZSk7CisgICAgUV9JTlZPS0FCTEUgdm9pZCByZWZyZXNoKCk7
CisgICAgc3RhdGljIFFWYXJpYW50TWFwIHBhcnNlU3RhdHMoY29uc3QgUUJ5dGVBcnJheSYgYnl0
ZXMsIFFTdHJpbmcqIGVycm9yKTsKKyAgICBzdGF0aWMgYm9vbCB2YWxpZEVuZHBvaW50KGNvbnN0
IFFTdHJpbmcmIHVybCk7CisgICAgc3RhdGljIFFTdHJpbmcgbm9ybWFsaXplZFBpbihRU3RyaW5n
IHBpbik7CisgICAgc3RhdGljIFFWYXJpYW50TWFwIHJlYWRMb2NhbChjb25zdCBRU3RyaW5nJiBz
eXNSb290ID0gIi9zeXMiKTsKK3NpZ25hbHM6CisgICAgdm9pZCBsb2NhbENoYW5nZWQoKTsKKyAg
ICB2b2lkIHN0YXRzQ2hhbmdlZCgpOworICAgIHZvaWQgY29uZmlnQ2hhbmdlZCgpOworcHJpdmF0
ZToKKyAgICB2b2lkIHJlZnJlc2hMb2NhbCgpOworICAgIHZvaWQgZmFpbChRU3RyaW5nIG1lc3Nh
Z2UpOworICAgIHZvaWQgY2FuY2VsKCk7CisgICAgUVN0cmluZyBjb25maWdGaWxlKCkgY29uc3Q7
CisgICAgUVN0cmluZyBtX2hvc3QsIG1fZW5kcG9pbnQsIG1fdG9rZW4sIG1fcGluLCBtX3N0YXR1
cyA9ICJDaG9vc2UgYSBob3N0IHRvIHZpZXcgaGFyZHdhcmUgc3RhdHMiOworICAgIFFWYXJpYW50
TWFwIG1fbG9jYWwsIG1fc3RhdHM7CisgICAgUVRpbWVyIG1fbG9jYWxUaW1lciwgbV9zdGF0c1Rp
bWVyOworICAgIFFQcm9jZXNzIG1fd2lmaTsKKyAgICBRTmV0d29ya0FjY2Vzc01hbmFnZXIgbV9u
ZXR3b3JrOworICAgIFFQb2ludGVyPFFOZXR3b3JrUmVwbHk+IG1fcmVwbHk7CisgICAgYm9vbCBt
X3Zpc2libGUgPSBmYWxzZTsKK307CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBz
ZXByb2ZpbGVzLmNwcCBiL2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuY3BwCm5ldyBm
aWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjUxZDhlM2QKLS0tIC9kZXYvbnVsbAorKysg
Yi9hcHAvbW9vbmxpZ2h0b3MvZWNsaXBzZXByb2ZpbGVzLmNwcApAQCAtMCwwICsxLDgwIEBACisj
aW5jbHVkZSAiZWNsaXBzZXByb2ZpbGVzLmgiCisjaW5jbHVkZSA8UUNyeXB0b2dyYXBoaWNIYXNo
PgorI2luY2x1ZGUgPFFDb3JlQXBwbGljYXRpb24+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNp
bmNsdWRlIDxRSW1hZ2VSZWFkZXI+CisjaW5jbHVkZSA8UUltYWdlPgorI2luY2x1ZGUgPFFEaXI+
CisjaW5jbHVkZSA8UUZpbGVJbmZvPgorI2luY2x1ZGUgPFFTYXZlRmlsZT4KKyNpbmNsdWRlIDxR
U3RhbmRhcmRQYXRocz4KK1FTdHJpbmcgRWNsaXBzZVByb2ZpbGVzOjprZXkoUVN0cmluZyBob3N0
LCBRU3RyaW5nIG5hbWUpIHsKKyAgICByZXR1cm4gImVjbGlwc2UvcHJvZmlsZXMvIiArIFFTdHJp
bmc6OmZyb21MYXRpbjEoUUNyeXB0b2dyYXBoaWNIYXNoOjpoYXNoKGhvc3QudG9VdGY4KCksIFFD
cnlwdG9ncmFwaGljSGFzaDo6U2hhMjU2KS50b0hleCgpKSArICIvIiArIFFTdHJpbmc6OmZyb21M
YXRpbjEoUUNyeXB0b2dyYXBoaWNIYXNoOjpoYXNoKG5hbWUudHJpbW1lZCgpLnRvVXRmOCgpLCBR
Q3J5cHRvZ3JhcGhpY0hhc2g6OlNoYTI1NikudG9IZXgoKSk7Cit9Citib29sIEVjbGlwc2VQcm9m
aWxlczo6dmFsaWQoY29uc3QgUVZhcmlhbnRNYXAmIHZhbHVlcykgeworICAgIGNvbnN0IFFNYXA8
UVN0cmluZyxRUGFpcjxpbnQsaW50Pj4gcmFuZ2VzID0ge3sid2lkdGgiLHszMjAsNzY4MH19LCB7
ImhlaWdodCIsezIwMCw0MzIwfX0sIHsiZnBzIix7MSwyNDB9fSwgeyJiaXRyYXRlS2JwcyIsezUw
MCwxNTAwMDB9fX07CisgICAgaWYgKHZhbHVlcy5zaXplKCkgIT0gcmFuZ2VzLnNpemUoKSkgcmV0
dXJuIGZhbHNlOworICAgIGZvciAoYXV0byBpID0gcmFuZ2VzLmJlZ2luKCk7IGkgIT0gcmFuZ2Vz
LmVuZCgpOyArK2kpIHsKKyAgICAgICAgYm9vbCBvazsgYXV0byBuID0gdmFsdWVzLnZhbHVlKGku
a2V5KCkpLnRvSW50KCZvayk7CisgICAgICAgIGlmICghb2sgfHwgbiA8IGkudmFsdWUoKS5maXJz
dCB8fCBuID4gaS52YWx1ZSgpLnNlY29uZCkgcmV0dXJuIGZhbHNlOworICAgIH0KKyAgICByZXR1
cm4gdHJ1ZTsKK30KK2Jvb2wgRWNsaXBzZVByb2ZpbGVzOjpzYXZlKFFTdHJpbmcgaG9zdCwgUVN0
cmluZyBuYW1lLCBRVmFyaWFudE1hcCB2YWx1ZXMpIHsKKyAgICBuYW1lID0gbmFtZS50cmltbWVk
KCk7CisgICAgaWYgKGhvc3Quc2l6ZSgpID4gMjU2IHx8IG5hbWUuaXNFbXB0eSgpIHx8IG5hbWUu
c2l6ZSgpID4gNDggfHwgIXZhbGlkKHZhbHVlcykpIHJldHVybiBmYWxzZTsKKyAgICBpZiAoIW5h
bWVzKGhvc3QpLmNvbnRhaW5zKG5hbWUpICYmIG5hbWVzKGhvc3QpLnNpemUoKSA+PSAzMikgcmV0
dXJuIGZhbHNlOworICAgIFFTZXR0aW5ncyBzZXR0aW5nczsgc2V0dGluZ3Muc2V0VmFsdWUoa2V5
KGhvc3QsbmFtZSkrIi9uYW1lIixuYW1lKTsgc2V0dGluZ3Muc2V0VmFsdWUoa2V5KGhvc3QsbmFt
ZSkrIi92YWx1ZXMiLHZhbHVlcyk7IHNldHRpbmdzLnN5bmMoKTsKKyAgICByZXR1cm4gc2V0dGlu
Z3Muc3RhdHVzKCkgPT0gUVNldHRpbmdzOjpOb0Vycm9yOworfQorUVZhcmlhbnRNYXAgRWNsaXBz
ZVByb2ZpbGVzOjpsb2FkKFFTdHJpbmcgaG9zdCwgUVN0cmluZyBuYW1lKSB7CisgICAgUVNldHRp
bmdzIHNldHRpbmdzOyBhdXRvIHZhbHVlID0gc2V0dGluZ3MudmFsdWUoa2V5KGhvc3QsbmFtZSkr
Ii92YWx1ZXMiKS50b01hcCgpOworICAgIHJldHVybiB2YWxpZCh2YWx1ZSkgPyB2YWx1ZSA6IFFW
YXJpYW50TWFwKCk7Cit9Citib29sIEVjbGlwc2VQcm9maWxlczo6cmVtb3ZlKFFTdHJpbmcgaG9z
dCwgUVN0cmluZyBuYW1lLCBib29sIGNvbmZpcm1lZCkgeworICAgIGlmICghY29uZmlybWVkKSBy
ZXR1cm4gZmFsc2U7CisgICAgUVNldHRpbmdzIHNldHRpbmdzOyBzZXR0aW5ncy5yZW1vdmUoa2V5
KGhvc3QsbmFtZSkpOyBzZXR0aW5ncy5zeW5jKCk7IHJldHVybiBzZXR0aW5ncy5zdGF0dXMoKSA9
PSBRU2V0dGluZ3M6Ok5vRXJyb3I7Cit9CitRU3RyaW5nTGlzdCBFY2xpcHNlUHJvZmlsZXM6Om5h
bWVzKFFTdHJpbmcgaG9zdCkgeworICAgIFFTZXR0aW5ncyBzZXR0aW5nczsgc2V0dGluZ3MuYmVn
aW5Hcm91cChrZXkoaG9zdCwgIiIpLnNlY3Rpb24oJy8nLDAsLTIpKTsKKyAgICBRU3RyaW5nTGlz
dCByZXN1bHQ7CisgICAgZm9yIChjb25zdCBhdXRvJiBjaGlsZCA6IHNldHRpbmdzLmNoaWxkR3Jv
dXBzKCkpIHsgYXV0byBuYW1lID0gc2V0dGluZ3MudmFsdWUoY2hpbGQrIi9uYW1lIikudG9TdHJp
bmcoKTsgaWYgKCFuYW1lLmlzRW1wdHkoKSkgcmVzdWx0LmFwcGVuZChuYW1lKTsgfQorICAgIHJl
c3VsdC5zb3J0KCk7IHJldHVybiByZXN1bHQ7Cit9CitzdGF0aWMgdm9pZCByZWdpc3RlckVjbGlw
c2VQcm9maWxlcygpIHsKKyAgICBxbWxSZWdpc3RlclNpbmdsZXRvblR5cGU8RWNsaXBzZVByb2Zp
bGVzPigiRWNsaXBzZVByb2ZpbGVzIiwxLDAsIkVjbGlwc2VQcm9maWxlcyIsW10oUVFtbEVuZ2lu
ZSosUUpTRW5naW5lKikgLT4gUU9iamVjdCogeyByZXR1cm4gbmV3IEVjbGlwc2VQcm9maWxlcygp
OyB9KTsKK30KK1FfQ09SRUFQUF9TVEFSVFVQX0ZVTkNUSU9OKHJlZ2lzdGVyRWNsaXBzZVByb2Zp
bGVzKQorCitRVXJsIEVjbGlwc2VQcm9maWxlczo6YmFja2dyb3VuZEZvbGRlcigpIGNvbnN0IHsK
KyAgICBRU3RyaW5nIHBhdGg9UVN0YW5kYXJkUGF0aHM6OndyaXRhYmxlTG9jYXRpb24oUVN0YW5k
YXJkUGF0aHM6OlBpY3R1cmVzTG9jYXRpb24pOworICAgIHJldHVybiBRVXJsOjpmcm9tTG9jYWxG
aWxlKFFEaXIocGF0aCkuZXhpc3RzKCk/cGF0aDpRRGlyOjpob21lUGF0aCgpKTsKK30KK1FWYXJp
YW50TGlzdCBFY2xpcHNlUHJvZmlsZXM6OmJhY2tncm91bmRGaWxlcyhRVXJsIGRpcmVjdG9yeSkg
eworICAgIGlmKGRpcmVjdG9yeS5pc0VtcHR5KCkpIGRpcmVjdG9yeT1iYWNrZ3JvdW5kRm9sZGVy
KCk7CisgICAgaWYoIWRpcmVjdG9yeS5pc0xvY2FsRmlsZSgpKSByZXR1cm4ge307CisgICAgUURp
ciBkaXIoZGlyZWN0b3J5LnRvTG9jYWxGaWxlKCkpOyBpZighZGlyLmV4aXN0cygpKSByZXR1cm4g
e307CisgICAgUVZhcmlhbnRMaXN0IHJlc3VsdDsKKyAgICBpZighZGlyLmlzUm9vdCgpKSB7IFFE
aXIgdXA9ZGlyO3VwLmNkVXAoKTtyZXN1bHQuYXBwZW5kKFFWYXJpYW50TWFwe3sibmFtZSIsUVN0
cmluZygiLi4iKX0seyJ1cmwiLFFVcmw6OmZyb21Mb2NhbEZpbGUodXAuYWJzb2x1dGVQYXRoKCkp
fSx7ImRpcmVjdG9yeSIsdHJ1ZX19KTsgfQorICAgIGZvcihjb25zdCBRRmlsZUluZm8mIGZpbGU6
ZGlyLmVudHJ5SW5mb0xpc3QoUURpcjo6RGlyc3xRRGlyOjpGaWxlc3xRRGlyOjpOb0RvdEFuZERv
dERvdHxRRGlyOjpSZWFkYWJsZSxRRGlyOjpEaXJzRmlyc3R8UURpcjo6TmFtZSkpIHsKKyAgICAg
ICAgaWYocmVzdWx0LnNpemUoKT49NTEyKSBicmVhazsKKyAgICAgICAgaWYoIWZpbGUuaXNEaXIo
KSYmIVFTdHJpbmdMaXN0eyJwbmciLCJqcGciLCJqcGVnIiwid2VicCIsImJtcCJ9LmNvbnRhaW5z
KGZpbGUuc3VmZml4KCkudG9Mb3dlcigpKSkgY29udGludWU7CisgICAgICAgIHJlc3VsdC5hcHBl
bmQoUVZhcmlhbnRNYXB7eyJuYW1lIixmaWxlLmZpbGVOYW1lKCl9LHsidXJsIixRVXJsOjpmcm9t
TG9jYWxGaWxlKGZpbGUuYWJzb2x1dGVGaWxlUGF0aCgpKX0seyJkaXJlY3RvcnkiLGZpbGUuaXNE
aXIoKX19KTsKKyAgICB9CisgICAgcmV0dXJuIHJlc3VsdDsKK30KK2Jvb2wgRWNsaXBzZVByb2Zp
bGVzOjpjaG9vc2VCYWNrZ3JvdW5kKFFVcmwgc291cmNlKSB7CisgICAgaWYoIXNvdXJjZS5pc0xv
Y2FsRmlsZSgpKSByZXR1cm4gZmFsc2U7CisgICAgUUZpbGVJbmZvIGZpbGUoc291cmNlLnRvTG9j
YWxGaWxlKCkpOyBpZighZmlsZS5pc0ZpbGUoKXx8ZmlsZS5zaXplKCk+MzIqMTAyNCoxMDI0KSBy
ZXR1cm4gZmFsc2U7CisgICAgUUltYWdlUmVhZGVyIHJlYWRlcihmaWxlLmFic29sdXRlRmlsZVBh
dGgoKSk7cmVhZGVyLnNldEF1dG9UcmFuc2Zvcm0odHJ1ZSk7CisgICAgUVNpemUgc2l6ZT1yZWFk
ZXIuc2l6ZSgpO2lmKCFzaXplLmlzVmFsaWQoKXx8c2l6ZS53aWR0aCgpPjE2Mzg0fHxzaXplLmhl
aWdodCgpPjE2Mzg0fHxxaW50NjQoc2l6ZS53aWR0aCgpKSpzaXplLmhlaWdodCgpPjY0MDAwMDAw
KSByZXR1cm4gZmFsc2U7CisgICAgaWYoc2l6ZS53aWR0aCgpPjI1NjB8fHNpemUuaGVpZ2h0KCk+
MjU2MCkgcmVhZGVyLnNldFNjYWxlZFNpemUoc2l6ZS5zY2FsZWQoMjU2MCwyNTYwLFF0OjpLZWVw
QXNwZWN0UmF0aW8pKTsKKyAgICBRSW1hZ2UgaW1hZ2U9cmVhZGVyLnJlYWQoKTtpZihpbWFnZS5p
c051bGwoKSkgcmV0dXJuIGZhbHNlOworICAgIFFTdHJpbmcgZm9sZGVyPVFTdGFuZGFyZFBhdGhz
Ojp3cml0YWJsZUxvY2F0aW9uKFFTdGFuZGFyZFBhdGhzOjpBcHBEYXRhTG9jYXRpb24pKyIvYXBw
ZWFyYW5jZSI7CisgICAgaWYoIVFEaXIoKS5ta3BhdGgoZm9sZGVyKSkgcmV0dXJuIGZhbHNlOwor
ICAgIFFTdHJpbmcgcGF0aD1mb2xkZXIrIi9jcmltc29uLWdsYXNzLWJhY2tncm91bmQucG5nIjsK
KyAgICBRU2F2ZUZpbGUgb3V0cHV0KHBhdGgpO2lmKCFvdXRwdXQub3BlbihRSU9EZXZpY2U6Oldy
aXRlT25seSl8fCFpbWFnZS5zYXZlKCZvdXRwdXQsIlBORyIpfHwhb3V0cHV0LmNvbW1pdCgpKSBy
ZXR1cm4gZmFsc2U7CisgICAgUVNldHRpbmdzIHNldHRpbmdzO3NldHRpbmdzLnNldFZhbHVlKCJl
Y2xpcHNlL2JhY2tncm91bmRQYXRoIixwYXRoKTtzZXR0aW5ncy5zeW5jKCk7CisgICAgZW1pdCBi
YWNrZ3JvdW5kQ2hhbmdlZCgpO2VtaXQgYXBwZWFyYW5jZUNoYW5nZWQoKTtyZXR1cm4gc2V0dGlu
Z3Muc3RhdHVzKCk9PVFTZXR0aW5nczo6Tm9FcnJvcjsKK30KK3ZvaWQgRWNsaXBzZVByb2ZpbGVz
OjpyZXNldEJhY2tncm91bmQoKSB7IFFTZXR0aW5ncygpLnJlbW92ZSgiZWNsaXBzZS9iYWNrZ3Jv
dW5kUGF0aCIpO2VtaXQgYmFja2dyb3VuZENoYW5nZWQoKTtlbWl0IGFwcGVhcmFuY2VDaGFuZ2Vk
KCk7IH0KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuaCBiL2Fw
cC9tb29ubGlnaHRvcy9lY2xpcHNlcHJvZmlsZXMuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwLi42NzRmYjkwCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL2Vj
bGlwc2Vwcm9maWxlcy5oCkBAIC0wLDAgKzEsMzkgQEAKKyNwcmFnbWEgb25jZQorI2luY2x1ZGUg
PFFPYmplY3Q+CisjaW5jbHVkZSA8UVZhcmlhbnRNYXA+CisjaW5jbHVkZSA8UVNldHRpbmdzPgor
I2luY2x1ZGUgPFFVcmw+CisjaW5jbHVkZSA8UVZhcmlhbnRMaXN0PgorY2xhc3MgRWNsaXBzZVBy
b2ZpbGVzIDogcHVibGljIFFPYmplY3QgeworICAgIFFfT0JKRUNUCisgICAgUV9QUk9QRVJUWShp
bnQgdGV4dFNjYWxlIFJFQUQgdGV4dFNjYWxlIFdSSVRFIHNldFRleHRTY2FsZSBOT1RJRlkgYXBw
ZWFyYW5jZUNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShib29sIHJlZHVjZWRNb3Rpb24gUkVBRCBy
ZWR1Y2VkTW90aW9uIFdSSVRFIHNldFJlZHVjZWRNb3Rpb24gTk9USUZZIGFwcGVhcmFuY2VDaGFu
Z2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBoaWdoQ29udHJhc3QgUkVBRCBoaWdoQ29udHJhc3Qg
V1JJVEUgc2V0SGlnaENvbnRyYXN0IE5PVElGWSBhcHBlYXJhbmNlQ2hhbmdlZCkKKyAgICBRX1BS
T1BFUlRZKFFVcmwgYmFja2dyb3VuZCBSRUFEIGJhY2tncm91bmQgTk9USUZZIGJhY2tncm91bmRD
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoaW50IGJhY2tncm91bmREaW0gUkVBRCBiYWNrZ3JvdW5k
RGltIFdSSVRFIHNldEJhY2tncm91bmREaW0gTk9USUZZIGFwcGVhcmFuY2VDaGFuZ2VkKQorcHVi
bGljOgorICAgIGV4cGxpY2l0IEVjbGlwc2VQcm9maWxlcyhRT2JqZWN0KiBwYXJlbnQgPSBudWxs
cHRyKSA6IFFPYmplY3QocGFyZW50KSB7fQorICAgIGludCB0ZXh0U2NhbGUoKSBjb25zdCB7IHJl
dHVybiBxQm91bmQoMTAwLFFTZXR0aW5ncygpLnZhbHVlKCJlY2xpcHNlL3RleHRTY2FsZSIsMTAw
KS50b0ludCgpLDEyNSk7IH0KKyAgICBib29sIHJlZHVjZWRNb3Rpb24oKSBjb25zdCB7IHJldHVy
biBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9yZWR1Y2VkTW90aW9uIixmYWxzZSkudG9Cb29s
KCk7IH0KKyAgICBib29sIGhpZ2hDb250cmFzdCgpIGNvbnN0IHsgcmV0dXJuIFFTZXR0aW5ncygp
LnZhbHVlKCJlY2xpcHNlL2hpZ2hDb250cmFzdCIsZmFsc2UpLnRvQm9vbCgpOyB9CisgICAgdm9p
ZCBzZXRUZXh0U2NhbGUoaW50IHZhbHVlKSB7IFFTZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNl
L3RleHRTY2FsZSIscUJvdW5kKDEwMCx2YWx1ZSwxMjUpKTsgZW1pdCBhcHBlYXJhbmNlQ2hhbmdl
ZCgpOyB9CisgICAgdm9pZCBzZXRSZWR1Y2VkTW90aW9uKGJvb2wgdmFsdWUpIHsgUVNldHRpbmdz
KCkuc2V0VmFsdWUoImVjbGlwc2UvcmVkdWNlZE1vdGlvbiIsdmFsdWUpOyBlbWl0IGFwcGVhcmFu
Y2VDaGFuZ2VkKCk7IH0KKyAgICB2b2lkIHNldEhpZ2hDb250cmFzdChib29sIHZhbHVlKSB7IFFT
ZXR0aW5ncygpLnNldFZhbHVlKCJlY2xpcHNlL2hpZ2hDb250cmFzdCIsdmFsdWUpOyBlbWl0IGFw
cGVhcmFuY2VDaGFuZ2VkKCk7IH0KKyAgICBRVXJsIGJhY2tncm91bmQoKSBjb25zdCB7IFFTdHJp
bmcgcGF0aD1RU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9iYWNrZ3JvdW5kUGF0aCIpLnRvU3Ry
aW5nKCk7cmV0dXJuIHBhdGguaXNFbXB0eSgpP1FVcmwoKTpRVXJsOjpmcm9tTG9jYWxGaWxlKHBh
dGgpOyB9CisgICAgaW50IGJhY2tncm91bmREaW0oKSBjb25zdCB7IHJldHVybiBxQm91bmQoMzAs
UVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvYmFja2dyb3VuZERpbSIsNjUpLnRvSW50KCksOTAp
OyB9CisgICAgdm9pZCBzZXRCYWNrZ3JvdW5kRGltKGludCB2YWx1ZSkgeyBRU2V0dGluZ3MoKS5z
ZXRWYWx1ZSgiZWNsaXBzZS9iYWNrZ3JvdW5kRGltIixxQm91bmQoMzAsdmFsdWUsOTApKTsgZW1p
dCBhcHBlYXJhbmNlQ2hhbmdlZCgpOyB9CisgICAgUV9JTlZPS0FCTEUgYm9vbCBjaG9vc2VCYWNr
Z3JvdW5kKFFVcmwgc291cmNlKTsKKyAgICBRX0lOVk9LQUJMRSB2b2lkIHJlc2V0QmFja2dyb3Vu
ZCgpOworICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50TGlzdCBiYWNrZ3JvdW5kRmlsZXMoUVVybCBk
aXJlY3Rvcnk9UVVybCgpKTsKKyAgICBRX0lOVk9LQUJMRSBRVXJsIGJhY2tncm91bmRGb2xkZXIo
KSBjb25zdDsKKyAgICBRX0lOVk9LQUJMRSBib29sIHNhdmUoUVN0cmluZyBob3N0LCBRU3RyaW5n
IG5hbWUsIFFWYXJpYW50TWFwIHZhbHVlcyk7CisgICAgUV9JTlZPS0FCTEUgUVZhcmlhbnRNYXAg
bG9hZChRU3RyaW5nIGhvc3QsIFFTdHJpbmcgbmFtZSk7CisgICAgUV9JTlZPS0FCTEUgYm9vbCBy
ZW1vdmUoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUsIGJvb2wgY29uZmlybWVkKTsKKyAgICBR
X0lOVk9LQUJMRSBRU3RyaW5nTGlzdCBuYW1lcyhRU3RyaW5nIGhvc3QpOworICAgIHN0YXRpYyBi
b29sIHZhbGlkKGNvbnN0IFFWYXJpYW50TWFwJiB2YWx1ZXMpOworc2lnbmFsczoKKyAgICB2b2lk
IGFwcGVhcmFuY2VDaGFuZ2VkKCk7CisgICAgdm9pZCBiYWNrZ3JvdW5kQ2hhbmdlZCgpOworcHJp
dmF0ZToKKyAgICBzdGF0aWMgUVN0cmluZyBrZXkoUVN0cmluZyBob3N0LCBRU3RyaW5nIG5hbWUp
OworfTsKZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmNwcCBiL2Fw
cC9tb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJlLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRl
eCAwMDAwMDAwLi4xOWY4MThkCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL2xv
Y2FsaGFyZHdhcmUuY3BwCkBAIC0wLDAgKzEsMTM4IEBACisjaW5jbHVkZSAibG9jYWxoYXJkd2Fy
ZS5oIgorI2luY2x1ZGUgPFF0TWF0aD4KKyNpbmNsdWRlIDxRRmlsZT4KKyNpbmNsdWRlIDxRRGly
PgorI2luY2x1ZGUgPFFTZXQ+CisjaW5jbHVkZSA8UVN0b3JhZ2VJbmZvPgorI2luY2x1ZGUgPFFG
aWxlSW5mbz4KKyNpbmNsdWRlIDxRRWxhcHNlZFRpbWVyPgorI2luY2x1ZGUgPFFNdXRleD4KKyNp
bmNsdWRlIDxRTXV0ZXhMb2NrZXI+CisjaW5jbHVkZSA8UVFtbEVuZ2luZT4KKyNpbmNsdWRlIDxR
Q29yZUFwcGxpY2F0aW9uPgorI2luY2x1ZGUgPFFSZWd1bGFyRXhwcmVzc2lvbj4KKworc3RhdGlj
IFFTdHJpbmcgcmVhZChjb25zdCBRU3RyaW5nJiBwYXRoKSB7IFFGaWxlIGYocGF0aCk7IHJldHVy
biBmLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSkgPyBRU3RyaW5nOjpmcm9tVXRmOChmLnJlYWQo
MzI3NjgpKS50cmltbWVkKCkgOiBRU3RyaW5nKCk7IH0KK3N0YXRpYyBkb3VibGUgbnVtYmVyKGNv
bnN0IFFTdHJpbmcmIHBhdGgpIHsgYm9vbCBvazsgZG91YmxlIG49cmVhZChwYXRoKS50b0RvdWJs
ZSgmb2spOyByZXR1cm4gb2sgJiYgcUlzRmluaXRlKG4pID8gbiA6IC0xOyB9CitMb2NhbEhhcmR3
YXJlOjpMb2NhbEhhcmR3YXJlKFFPYmplY3QqIHBhcmVudCk6UU9iamVjdChwYXJlbnQpIHsgbV90
aW1lci5zZXRJbnRlcnZhbChyZWZyZXNoU2Vjb25kcygpKjEwMDApOyBjb25uZWN0KCZtX3RpbWVy
LCZRVGltZXI6OnRpbWVvdXQsdGhpcywmTG9jYWxIYXJkd2FyZTo6cmVmcmVzaCk7IH0KK3ZvaWQg
TG9jYWxIYXJkd2FyZTo6c2V0QWN0aXZlKGJvb2wgYWN0aXZlKSB7IG1fbGVnYWN5QWN0aXZlPWFj
dGl2ZTt1cGRhdGVTYW1wbGluZygpOyB9Cit2b2lkIExvY2FsSGFyZHdhcmU6OnVwZGF0ZVNhbXBs
aW5nKCkgeworICAgIGlmKCFtX2xlZ2FjeUFjdGl2ZSAmJiBtX2NvbnN1bWVycy5pc0VtcHR5KCkp
IG1fdGltZXIuc3RvcCgpOworICAgIGVsc2UgaWYoIW1fdGltZXIuaXNBY3RpdmUoKSkge3JlZnJl
c2goKTttX3RpbWVyLnN0YXJ0KCk7fQorfQordm9pZCBMb2NhbEhhcmR3YXJlOjpzZXRDb25zdW1l
ckFjdGl2ZShRT2JqZWN0KiBjb25zdW1lcixib29sIGFjdGl2ZSkgeworICAgIGlmKCFjb25zdW1l
cikgcmV0dXJuOworICAgIGlmKGFjdGl2ZSAmJiAhbV9jb25zdW1lcnMuY29udGFpbnMoY29uc3Vt
ZXIpKSB7CisgICAgICAgIG1fY29uc3VtZXJzLmluc2VydChjb25zdW1lcik7CisgICAgICAgIGlm
KCFtX2tub3duQ29uc3VtZXJzLmNvbnRhaW5zKGNvbnN1bWVyKSkgeworICAgICAgICAgICAgbV9r
bm93bkNvbnN1bWVycy5pbnNlcnQoY29uc3VtZXIpOworICAgICAgICAgICAgY29ubmVjdChjb25z
dW1lciwmUU9iamVjdDo6ZGVzdHJveWVkLHRoaXMsW3RoaXMsY29uc3VtZXJde21fa25vd25Db25z
dW1lcnMucmVtb3ZlKGNvbnN1bWVyKTttX2NvbnN1bWVycy5yZW1vdmUoY29uc3VtZXIpO3VwZGF0
ZVNhbXBsaW5nKCk7fSk7CisgICAgICAgIH0KKyAgICB9IGVsc2UgaWYoIWFjdGl2ZSkgbV9jb25z
dW1lcnMucmVtb3ZlKGNvbnN1bWVyKTsKKyAgICB1cGRhdGVTYW1wbGluZygpOworfQordm9pZCBM
b2NhbEhhcmR3YXJlOjpyZWZyZXNoKCkgeyBtX3JlYWRpbmdzPXNhbXBsZSgpOyBtX2hpc3Rvcnku
YXBwZW5kKG1fcmVhZGluZ3MpOyB3aGlsZShtX2hpc3Rvcnkuc2l6ZSgpPjYwKSBtX2hpc3Rvcnku
cmVtb3ZlRmlyc3QoKTsgZW1pdCBjaGFuZ2VkKCk7IH0KK3ZvaWQgTG9jYWxIYXJkd2FyZTo6c2V0
RmllbGRzKFFTdHJpbmdMaXN0IHYpIHsgUVN0cmluZ0xpc3QgY2xlYW47IGZvcihjb25zdCBRU3Ry
aW5nJiBrZXk6UVN0cmluZ0xpc3R7ImNwdSIsIm1lbW9yeSIsInRlbXBlcmF0dXJlIiwiZ3B1Iiwi
bmV0d29yayIsImJhdHRlcnkiLCJzdG9yYWdlIn0pIGlmKHYuY29udGFpbnMoa2V5KSkgY2xlYW4u
YXBwZW5kKGtleSk7IHNhdmUoImxvY2FsRmllbGRzIixjbGVhbik7IH0KKworUVZhcmlhbnRNYXAg
TG9jYWxIYXJkd2FyZTo6c2FtcGxlKGNvbnN0IFFTdHJpbmcmIHJvb3QpIHsKKyAgICAvLyBTaGFy
ZWQgY2FjaGU6IFNldHRpbmdzIGFuZCB0aGUgZGVjb2RlciByZXVzZSBvbmUgYm91bmRlZCwgcmVh
ZC1vbmx5IHNhbXBsZS4KKyAgICBzdGF0aWMgUU11dGV4IG11dGV4OyBRTXV0ZXhMb2NrZXIgbG9j
a2VyKCZtdXRleCk7CisgICAgc3RhdGljIFFFbGFwc2VkVGltZXIgY2xvY2s7IGlmKCFjbG9jay5p
c1ZhbGlkKCkpIGNsb2NrLnN0YXJ0KCk7CisgICAgc3RhdGljIFFNYXA8UVN0cmluZyxRVmFyaWFu
dE1hcD4gcHJldmlvdXMsIGNhY2hlZDsKKyAgICBzdGF0aWMgUU1hcDxRU3RyaW5nLHFpbnQ2ND4g
bGFzdDsKKyAgICBxaW50NjQgbm93PWNsb2NrLmVsYXBzZWQoKTsKKyAgICBpbnQgaW50ZXJ2YWw9
cUJvdW5kKDEsUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvaGFyZHdhcmVSZWZyZXNoIiwyKS50
b0ludCgpLDUpKjEwMDA7CisgICAgaWYoY2FjaGVkLmNvbnRhaW5zKHJvb3QpICYmIG5vdy1sYXN0
LnZhbHVlKHJvb3QpPGludGVydmFsKSByZXR1cm4gY2FjaGVkLnZhbHVlKHJvb3QpOworICAgIFFW
YXJpYW50TWFwIHJlc3VsdCwgY291bnRlcnM7CisgICAgYXV0byBvbGQ9cHJldmlvdXMudmFsdWUo
cm9vdCk7IGRvdWJsZSBzZWNvbmRzPShub3ctbGFzdC52YWx1ZShyb290KSkvMTAwMC4wOworICAg
IGF1dG8gc3RhdD1yZWFkKHJvb3QrIi9wcm9jL3N0YXQiKS5zZWN0aW9uKCdcbicsMCwwKS5zaW1w
bGlmaWVkKCkuc3BsaXQoJyAnKTsKKyAgICBpZihzdGF0LnNpemUoKT49OSAmJiBzdGF0WzBdPT0i
Y3B1IikgeworICAgICAgICBxdWludDY0IHRvdGFsPTA7IGZvcihpbnQgaT0xO2k8PTg7aSsrKSB0
b3RhbCs9c3RhdFtpXS50b1VMb25nTG9uZygpOworICAgICAgICBxdWludDY0IGlkbGU9c3RhdFs0
XS50b1VMb25nTG9uZygpK3N0YXRbNV0udG9VTG9uZ0xvbmcoKTsKKyAgICAgICAgY291bnRlcnNb
InRvdGFsIl09dG90YWw7IGNvdW50ZXJzWyJpZGxlIl09aWRsZTsKKyAgICAgICAgcXVpbnQ2NCBi
ZWZvcmU9b2xkLnZhbHVlKCJ0b3RhbCIpLnRvVUxvbmdMb25nKCk7CisgICAgICAgIGlmKG9sZC5j
b250YWlucygidG90YWwiKSAmJiB0b3RhbD5iZWZvcmUgJiYgaWRsZT49b2xkLnZhbHVlKCJpZGxl
IikudG9VTG9uZ0xvbmcoKSkgcmVzdWx0WyJjcHVQZXJjZW50Il09cUJvdW5kKDAuMCwxMDAuMCoo
MS4wLWRvdWJsZShpZGxlLW9sZFsiaWRsZSJdLnRvVUxvbmdMb25nKCkpL2RvdWJsZSh0b3RhbC1i
ZWZvcmUpKSwxMDAuMCk7CisgICAgfQorICAgIFFNYXA8UVN0cmluZyxxdWludDY0PiBtZW1vcnk7
CisgICAgZm9yKGNvbnN0IFFTdHJpbmcmIGxpbmU6cmVhZChyb290KyIvcHJvYy9tZW1pbmZvIiku
c3BsaXQoJ1xuJykpIHsgYXV0byBwYXJ0cz1saW5lLnNpbXBsaWZpZWQoKS5zcGxpdCgnICcpOyBp
ZihwYXJ0cy5zaXplKCk+PTIpIG1lbW9yeVtwYXJ0c1swXV09cGFydHNbMV0udG9VTG9uZ0xvbmco
KSoxMDI0OyB9CisgICAgcXVpbnQ2NCB0b3RhbD1tZW1vcnkudmFsdWUoIk1lbVRvdGFsOiIpLCBh
dmFpbGFibGU9bWVtb3J5LnZhbHVlKCJNZW1BdmFpbGFibGU6Iik7CisgICAgaWYodG90YWwgJiYg
YXZhaWxhYmxlPD10b3RhbCAmJiBtZW1vcnkuY29udGFpbnMoIk1lbUF2YWlsYWJsZToiKSkgeyBy
ZXN1bHRbIm1lbW9yeVVzZWRHaUIiXT1kb3VibGUodG90YWwtYXZhaWxhYmxlKS8oMTAyNCoxMDI0
KjEwMjQpOyByZXN1bHRbIm1lbW9yeVRvdGFsR2lCIl09ZG91YmxlKHRvdGFsKS8oMTAyNCoxMDI0
KjEwMjQpOyByZXN1bHRbIm1lbW9yeVBlcmNlbnQiXT0xMDAuMCoodG90YWwtYXZhaWxhYmxlKS90
b3RhbDsgfQorICAgIGlmKG1lbW9yeS5jb250YWlucygiU3dhcFRvdGFsOiIpKSByZXN1bHRbInN3
YXBVc2VkTWlCIl09ZG91YmxlKG1lbW9yeS52YWx1ZSgiU3dhcFRvdGFsOiIpLXFNaW4obWVtb3J5
LnZhbHVlKCJTd2FwVG90YWw6IiksbWVtb3J5LnZhbHVlKCJTd2FwRnJlZToiKSkpLygxMDI0KjEw
MjQpOworICAgIGRvdWJsZSBmcmVxdWVuY3k9bnVtYmVyKHJvb3QrIi9zeXMvZGV2aWNlcy9zeXN0
ZW0vY3B1L2NwdTAvY3B1ZnJlcS9zY2FsaW5nX2N1cl9mcmVxIik7IGlmKGZyZXF1ZW5jeT4wKSBy
ZXN1bHRbImNwdU1IeiJdPWZyZXF1ZW5jeS8xMDAwOworICAgIGRvdWJsZSB0ZW1wZXJhdHVyZT0t
MSwgZmFuPS0xOworICAgIFFEaXIgaHcocm9vdCsiL3N5cy9jbGFzcy9od21vbiIpOworICAgIGZv
cihjb25zdCBRU3RyaW5nJiBkZXZpY2U6aHcuZW50cnlMaXN0KFFEaXI6OkRpcnN8UURpcjo6Tm9E
b3RBbmREb3REb3QpKSB7CisgICAgICAgIFFEaXIgc2Vuc29ycyhody5maWxlUGF0aChkZXZpY2Up
KTsgUVN0cmluZyBuYW1lPXJlYWQoc2Vuc29ycy5maWxlUGF0aCgibmFtZSIpKTsKKyAgICAgICAg
Zm9yKGNvbnN0IFFTdHJpbmcmIGZpbGU6c2Vuc29ycy5lbnRyeUxpc3QoeyJ0ZW1wKl9pbnB1dCIs
ImZhbipfaW5wdXQifSxRRGlyOjpGaWxlcykpIHsKKyAgICAgICAgICAgIGRvdWJsZSB2YWx1ZT1u
dW1iZXIoc2Vuc29ycy5maWxlUGF0aChmaWxlKSk7CisgICAgICAgICAgICBpZihmaWxlLnN0YXJ0
c1dpdGgoInRlbXAiKSAmJiAobmFtZT09ImNvcmV0ZW1wIiB8fCBuYW1lPT0iazEwdGVtcCIpICYm
IHZhbHVlPj0wICYmIHZhbHVlPD0xNTAwMDApIHRlbXBlcmF0dXJlPXFNYXgodGVtcGVyYXR1cmUs
dmFsdWUvMTAwMCk7CisgICAgICAgICAgICBpZihmaWxlLnN0YXJ0c1dpdGgoImZhbiIpICYmIHZh
bHVlPj0wICYmIHZhbHVlPDMwMDAwKSBmYW49cU1heChmYW4sdmFsdWUpOworICAgICAgICB9Cisg
ICAgfQorICAgIGlmKHRlbXBlcmF0dXJlPj0wKSByZXN1bHRbInRlbXBlcmF0dXJlQyJdPXRlbXBl
cmF0dXJlOworICAgIGlmKGZhbj49MCkgcmVzdWx0WyJmYW5SUE0iXT1mYW47CisgICAgUURpciBk
cm0ocm9vdCsiL3N5cy9jbGFzcy9kcm0iKTsKKyAgICBmb3IoY29uc3QgUVN0cmluZyYgY2FyZDpk
cm0uZW50cnlMaXN0KHsiY2FyZFswLTldKiJ9LFFEaXI6OkRpcnN8UURpcjo6Tm9Eb3RBbmREb3RE
b3QpKSB7IGRvdWJsZSBidXN5PW51bWJlcihkcm0uZmlsZVBhdGgoY2FyZCsiL2RldmljZS9ncHVf
YnVzeV9wZXJjZW50IikpOyBpZihidXN5Pj0wICYmIGJ1c3k8PTEwMCkgeyByZXN1bHRbImdwdVBl
cmNlbnQiXT1idXN5OyBicmVhazsgfSB9CisgICAgLy8gRFJNIGZkaW5mbyBpcyB1bnByaXZpbGVn
ZWQsIHJlYWQtb25seSBhbmQgc2NvcGVkIHRvIHRoaXMgRWNsaXBzZSBwcm9jZXNzLgorICAgIC8v
IERlZHVwbGljYXRlIGRlc2NyaXB0b3JzIGJlbG9uZ2luZyB0byB0aGUgc2FtZSBEUk0gY2xpZW50
OyBuZXZlciBjYWxsIHRoaXMgc3lzdGVtLXdpZGUgR1BVIGxvYWQuCisgICAgcXVpbnQ2NCB2aWRl
bz0wOyBib29sIGhhc1ZpZGVvPWZhbHNlOyBRU2V0PFFTdHJpbmc+IGNsaWVudHM7CisgICAgUURp
ciBkZXNjcmlwdG9ycyhyb290KyIvcHJvYy9zZWxmL2ZkaW5mbyIpOworICAgIGludCBpbnNwZWN0
ZWQ9MDsKKyAgICBmb3IoY29uc3QgUVN0cmluZyYgZmlsZTpkZXNjcmlwdG9ycy5lbnRyeUxpc3Qo
UURpcjo6RmlsZXMpKSB7CisgICAgICAgIGlmKCsraW5zcGVjdGVkPjI1NikgYnJlYWs7CisgICAg
ICAgIFFTdHJpbmcgaW5mbz1yZWFkKGRlc2NyaXB0b3JzLmZpbGVQYXRoKGZpbGUpKTsKKyAgICAg
ICAgYXV0byBjbGllbnQ9UVJlZ3VsYXJFeHByZXNzaW9uKCJkcm0tY2xpZW50LWlkOlxccyooXFxk
KykiKS5tYXRjaChpbmZvKTsKKyAgICAgICAgaWYoIWNsaWVudC5oYXNNYXRjaCgpIHx8IGNsaWVu
dHMuY29udGFpbnMoY2xpZW50LmNhcHR1cmVkKDEpKSkgY29udGludWU7CisgICAgICAgIGNsaWVu
dHMuaW5zZXJ0KGNsaWVudC5jYXB0dXJlZCgxKSk7CisgICAgICAgIGF1dG8gZW5naW5lcz1RUmVn
dWxhckV4cHJlc3Npb24oImRybS1lbmdpbmUtdmlkZW8oPzpcXGQrKT86XFxzKihcXGQrKVxccytu
cyIpLmdsb2JhbE1hdGNoKGluZm8pOworICAgICAgICB3aGlsZShlbmdpbmVzLmhhc05leHQoKSkg
eyB2aWRlbys9ZW5naW5lcy5uZXh0KCkuY2FwdHVyZWQoMSkudG9VTG9uZ0xvbmcoKTsgaGFzVmlk
ZW89dHJ1ZTsgfQorICAgIH0KKyAgICBpZihoYXNWaWRlbykgeworICAgICAgICBjb3VudGVyc1si
dmlkZW8iXT12aWRlbzsKKyAgICAgICAgaWYob2xkLmNvbnRhaW5zKCJ2aWRlbyIpICYmIHNlY29u
ZHM+MCAmJiB2aWRlbz49b2xkLnZhbHVlKCJ2aWRlbyIpLnRvVUxvbmdMb25nKCkpIHJlc3VsdFsi
dmlkZW9QZXJjZW50Il09cUJvdW5kKDAuMCxkb3VibGUodmlkZW8tb2xkWyJ2aWRlbyJdLnRvVUxv
bmdMb25nKCkpL3NlY29uZHMvMTAwMDAwMDAuMCwxMDAuMCk7CisgICAgfQorICAgIFFTdHJpbmcg
bmljOworICAgIGZvcihjb25zdCBRU3RyaW5nJiBsaW5lOnJlYWQocm9vdCsiL3Byb2MvbmV0L3Jv
dXRlIikuc3BsaXQoJ1xuJykpIHsgYXV0byBwPWxpbmUuc2ltcGxpZmllZCgpLnNwbGl0KCcgJyk7
IGlmKHAuc2l6ZSgpPjMgJiYgcFsxXT09IjAwMDAwMDAwIikgeyBuaWM9cFswXTsgYnJlYWs7IH0g
fQorICAgIGZvcihjb25zdCBRU3RyaW5nJiBsaW5lOnJlYWQocm9vdCsiL3Byb2MvbmV0L2RldiIp
LnNwbGl0KCdcbicpKSB7CisgICAgICAgIGlmKGxpbmUuc2VjdGlvbignOicsMCwwKS50cmltbWVk
KCkhPW5pYyB8fCBuaWMuaXNFbXB0eSgpKSBjb250aW51ZTsKKyAgICAgICAgYXV0byBwPWxpbmUu
c2VjdGlvbignOicsMSkuc2ltcGxpZmllZCgpLnNwbGl0KCcgJyk7IGlmKHAuc2l6ZSgpPDE2KSBj
b250aW51ZTsKKyAgICAgICAgcXVpbnQ2NCByeD1wWzBdLnRvVUxvbmdMb25nKCksIHR4PXBbOF0u
dG9VTG9uZ0xvbmcoKTsgY291bnRlcnNbInJ4Il09cng7IGNvdW50ZXJzWyJ0eCJdPXR4OyBjb3Vu
dGVyc1sibmljIl09bmljOworICAgICAgICBpZihzZWNvbmRzPjAgJiYgb2xkLnZhbHVlKCJuaWMi
KS50b1N0cmluZygpPT1uaWMgJiYgcng+PW9sZC52YWx1ZSgicngiKS50b1VMb25nTG9uZygpICYm
IHR4Pj1vbGQudmFsdWUoInR4IikudG9VTG9uZ0xvbmcoKSkgeyByZXN1bHRbInJlY2VpdmVNaUIi
XT1kb3VibGUocngtb2xkWyJyeCJdLnRvVUxvbmdMb25nKCkpL3NlY29uZHMvKDEwMjQqMTAyNCk7
IHJlc3VsdFsidHJhbnNtaXRNaUIiXT1kb3VibGUodHgtb2xkWyJ0eCJdLnRvVUxvbmdMb25nKCkp
L3NlY29uZHMvKDEwMjQqMTAyNCk7IH0KKyAgICB9CisgICAgUURpciBwb3dlcihyb290KyIvc3lz
L2NsYXNzL3Bvd2VyX3N1cHBseSIpOworICAgIGZvcihjb25zdCBRU3RyaW5nJiBuYW1lOnBvd2Vy
LmVudHJ5TGlzdChRRGlyOjpEaXJzfFFEaXI6Ok5vRG90QW5kRG90RG90KSkgeworICAgICAgICBR
U3RyaW5nIHBhdGg9cG93ZXIuZmlsZVBhdGgobmFtZSk7IGlmKHJlYWQocGF0aCsiL3R5cGUiKSE9
IkJhdHRlcnkiKSBjb250aW51ZTsKKyAgICAgICAgZG91YmxlIHBlcmNlbnQ9bnVtYmVyKHBhdGgr
Ii9jYXBhY2l0eSIpOyBpZihwZXJjZW50Pj0wICYmIHBlcmNlbnQ8PTEwMCkgcmVzdWx0WyJiYXR0
ZXJ5UGVyY2VudCJdPXBlcmNlbnQ7CisgICAgICAgIHJlc3VsdFsiYmF0dGVyeVN0YXRlIl09cmVh
ZChwYXRoKyIvc3RhdHVzIikubGVmdCgzMik7IGRvdWJsZSB3YXR0cz1udW1iZXIocGF0aCsiL3Bv
d2VyX25vdyIpOyBpZih3YXR0cz49MCkgcmVzdWx0WyJiYXR0ZXJ5V2F0dHMiXT13YXR0cy8xMDAw
MDAwOyBicmVhazsKKyAgICB9CisgICAgaWYocm9vdC5pc0VtcHR5KCkpIHsgUVN0b3JhZ2VJbmZv
IGRpc2s9UVN0b3JhZ2VJbmZvOjpyb290KCk7IGlmKGRpc2suaXNWYWxpZCgpICYmIGRpc2suaXNS
ZWFkeSgpICYmIGRpc2suYnl0ZXNUb3RhbCgpPjApIHsgcmVzdWx0WyJzdG9yYWdlVG90YWxHaUIi
XT1kb3VibGUoZGlzay5ieXRlc1RvdGFsKCkpLygxMDI0KjEwMjQqMTAyNCk7IHJlc3VsdFsic3Rv
cmFnZUZyZWVHaUIiXT1kb3VibGUoZGlzay5ieXRlc0F2YWlsYWJsZSgpKS8oMTAyNCoxMDI0KjEw
MjQpOyB9IH0KKyAgICBpZihyb290LmlzRW1wdHkoKSkgeworICAgICAgICBRU3RyaW5nIGRldmlj
ZT1RRmlsZUluZm8oUVN0cmluZzo6ZnJvbVV0ZjgoUVN0b3JhZ2VJbmZvOjpyb290KCkuZGV2aWNl
KCkpKS5jYW5vbmljYWxGaWxlUGF0aCgpLnNlY3Rpb24oJy8nLC0xKTsKKyAgICAgICAgYXV0byBp
bz1yZWFkKCIvc3lzL2NsYXNzL2Jsb2NrLyIrZGV2aWNlKyIvc3RhdCIpLnNpbXBsaWZpZWQoKS5z
cGxpdCgnICcpOworICAgICAgICBpZighZGV2aWNlLmlzRW1wdHkoKSAmJiBpby5zaXplKCk+PTcp
IHsKKyAgICAgICAgICAgIHF1aW50NjQgcmVhZHM9aW9bMl0udG9VTG9uZ0xvbmcoKSx3cml0ZXM9
aW9bNl0udG9VTG9uZ0xvbmcoKTsKKyAgICAgICAgICAgIGNvdW50ZXJzWyJkaXNrIl09ZGV2aWNl
O2NvdW50ZXJzWyJyZWFkcyJdPXJlYWRzO2NvdW50ZXJzWyJ3cml0ZXMiXT13cml0ZXM7CisgICAg
ICAgICAgICBpZihzZWNvbmRzPjAgJiYgb2xkLnZhbHVlKCJkaXNrIikudG9TdHJpbmcoKT09ZGV2
aWNlICYmIHJlYWRzPj1vbGQudmFsdWUoInJlYWRzIikudG9VTG9uZ0xvbmcoKSAmJiB3cml0ZXM+
PW9sZC52YWx1ZSgid3JpdGVzIikudG9VTG9uZ0xvbmcoKSkgeworICAgICAgICAgICAgICAgIHJl
c3VsdFsiZGlza1JlYWRNaUIiXT1kb3VibGUocmVhZHMtb2xkWyJyZWFkcyJdLnRvVUxvbmdMb25n
KCkpKjUxMi9zZWNvbmRzLygxMDI0KjEwMjQpOworICAgICAgICAgICAgICAgIHJlc3VsdFsiZGlz
a1dyaXRlTWlCIl09ZG91YmxlKHdyaXRlcy1vbGRbIndyaXRlcyJdLnRvVUxvbmdMb25nKCkpKjUx
Mi9zZWNvbmRzLygxMDI0KjEwMjQpOworICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQor
ICAgIHByZXZpb3VzW3Jvb3RdPWNvdW50ZXJzOyBsYXN0W3Jvb3RdPW5vdzsgY2FjaGVkW3Jvb3Rd
PXJlc3VsdDsgcmV0dXJuIHJlc3VsdDsKK30KKworUVN0cmluZyBMb2NhbEhhcmR3YXJlOjpvdmVy
bGF5VGV4dCgpIHsKKyAgICBhdXRvIHI9c2FtcGxlKCk7IFFTZXR0aW5ncyBzOyBhdXRvIGZpZWxk
cz1zLnZhbHVlKCJlY2xpcHNlL2xvY2FsRmllbGRzIixRU3RyaW5nTGlzdHsiY3B1IiwibWVtb3J5
IiwidGVtcGVyYXR1cmUiLCJncHUiLCJuZXR3b3JrIiwiYmF0dGVyeSJ9KS50b1N0cmluZ0xpc3Qo
KTsgYm9vbCBkZXRhaWw9cy52YWx1ZSgiZWNsaXBzZS9sb2NhbERldGFpbGVkIixmYWxzZSkudG9C
b29sKCk7CisgICAgUVN0cmluZ0xpc3QgbGluZXN7IkVjbGlwc2VPUyB8IExPQ0FMIE1BQyJ9Owor
ICAgIGF1dG8gdmFsdWU9WyZyXShRU3RyaW5nIGtleSxRU3RyaW5nIHN1ZmZpeCxpbnQgcHJlY2lz
aW9uPTEpIHsgcmV0dXJuIHIuY29udGFpbnMoa2V5KSA/IFFTdHJpbmc6Om51bWJlcihyW2tleV0u
dG9Eb3VibGUoKSwnZicscHJlY2lzaW9uKStzdWZmaXggOiBRU3RyaW5nKCJVbmF2YWlsYWJsZSIp
OyB9OworICAgIGlmKGZpZWxkcy5jb250YWlucygiY3B1IikpIHsgbGluZXM8PCJDUFUgICIrdmFs
dWUoImNwdVBlcmNlbnQiLCIlIik7IGlmKGRldGFpbCkgbGluZXM8PCJDUFUgY2xvY2sgICIrdmFs
dWUoImNwdU1IeiIsIiBNSHoiLDApOyB9CisgICAgaWYoZmllbGRzLmNvbnRhaW5zKCJtZW1vcnki
KSkgeyBsaW5lczw8IlJBTSAgIit2YWx1ZSgibWVtb3J5VXNlZEdpQiIsIiBHaUIiKSsiIC8gIit2
YWx1ZSgibWVtb3J5VG90YWxHaUIiLCIgR2lCIik7IGlmKGRldGFpbCkgbGluZXM8PCJTd2FwICAi
K3ZhbHVlKCJzd2FwVXNlZE1pQiIsIiBNaUIiKTsgfQorICAgIGlmKGZpZWxkcy5jb250YWlucygi
dGVtcGVyYXR1cmUiKSkgeyBsaW5lczw8IkNQVSB0ZW1wZXJhdHVyZSAgIit2YWx1ZSgidGVtcGVy
YXR1cmVDIiwiIEMiKTsgaWYoZGV0YWlsKSBsaW5lczw8IkZhbiAgIit2YWx1ZSgiZmFuUlBNIiwi
IFJQTSIsMCk7IH0KKyAgICBpZihmaWVsZHMuY29udGFpbnMoImdwdSIpKSB7IGxpbmVzPDwiR1BV
IGJ1c3kgICIrdmFsdWUoImdwdVBlcmNlbnQiLCIlIik7IGxpbmVzPDwiRWNsaXBzZSB2aWRlbyBl
bmdpbmUgICIrdmFsdWUoInZpZGVvUGVyY2VudCIsIiUiKTsgfQorICAgIGlmKGZpZWxkcy5jb250
YWlucygibmV0d29yayIpKSBsaW5lczw8Ik5ldHdvcmsgIGRvd24gIit2YWx1ZSgicmVjZWl2ZU1p
QiIsIiBNaUIvcyIpKyIgfCB1cCAiK3ZhbHVlKCJ0cmFuc21pdE1pQiIsIiBNaUIvcyIpOworICAg
IGlmKGZpZWxkcy5jb250YWlucygiYmF0dGVyeSIpKSB7IGxpbmVzPDwiQmF0dGVyeSAgIit2YWx1
ZSgiYmF0dGVyeVBlcmNlbnQiLCIlIiwwKTsgaWYoZGV0YWlsKSBsaW5lczw8IkJhdHRlcnkgcG93
ZXIgICIrdmFsdWUoImJhdHRlcnlXYXR0cyIsIiBXIik7IH0KKyAgICBpZihmaWVsZHMuY29udGFp
bnMoInN0b3JhZ2UiKSkgeyBsaW5lczw8IlVTQi9yb290IGZyZWUgICIrdmFsdWUoInN0b3JhZ2VG
cmVlR2lCIiwiIEdpQiIpOyBpZihkZXRhaWwpIGxpbmVzPDwiUm9vdCBJL08gIHJlYWQgIit2YWx1
ZSgiZGlza1JlYWRNaUIiLCIgTWlCL3MiKSsiIHwgd3JpdGUgIit2YWx1ZSgiZGlza1dyaXRlTWlC
IiwiIE1pQi9zIik7IH0KKyAgICByZXR1cm4gbGluZXMuam9pbignXG4nKTsKK30KK3N0YXRpYyB2
b2lkIHJlZ2lzdGVyTG9jYWxIYXJkd2FyZSgpIHsgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlPExv
Y2FsSGFyZHdhcmU+KCJMb2NhbEhhcmR3YXJlIiwxLDAsIkxvY2FsSGFyZHdhcmUiLFtdKFFRbWxF
bmdpbmUqLFFKU0VuZ2luZSopLT5RT2JqZWN0KntyZXR1cm4gbmV3IExvY2FsSGFyZHdhcmUoKTt9
KTsgfQorUV9DT1JFQVBQX1NUQVJUVVBfRlVOQ1RJT04ocmVnaXN0ZXJMb2NhbEhhcmR3YXJlKQpk
aWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuaCBiL2FwcC9tb29ubGln
aHRvcy9sb2NhbGhhcmR3YXJlLmgKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4u
NmI2ZWFhNgotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9sb2NhbGhhcmR3YXJl
LmgKQEAgLTAsMCArMSw1NSBAQAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4KKyNp
bmNsdWRlIDxRVmFyaWFudE1hcD4KKyNpbmNsdWRlIDxRVmFyaWFudExpc3Q+CisjaW5jbHVkZSA8
UVRpbWVyPgorI2luY2x1ZGUgPFFTZXR0aW5ncz4KKyNpbmNsdWRlIDxRU2V0PgorCitjbGFzcyBM
b2NhbEhhcmR3YXJlIDogcHVibGljIFFPYmplY3QgeworICAgIFFfT0JKRUNUCisgICAgUV9QUk9Q
RVJUWShRVmFyaWFudE1hcCByZWFkaW5ncyBSRUFEIHJlYWRpbmdzIE5PVElGWSBjaGFuZ2VkKQor
ICAgIFFfUFJPUEVSVFkoUVZhcmlhbnRMaXN0IGhpc3RvcnkgUkVBRCBoaXN0b3J5IE5PVElGWSBj
aGFuZ2VkKQorICAgIFFfUFJPUEVSVFkoYm9vbCBvdmVybGF5IFJFQUQgb3ZlcmxheSBXUklURSBz
ZXRPdmVybGF5IE5PVElGWSBwcmVmZXJlbmNlc0NoYW5nZWQpCisgICAgUV9QUk9QRVJUWShib29s
IGRldGFpbGVkIFJFQUQgZGV0YWlsZWQgV1JJVEUgc2V0RGV0YWlsZWQgTk9USUZZIHByZWZlcmVu
Y2VzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGJvb2wgc3RyZWFtRGV0YWlsZWQgUkVBRCBzdHJl
YW1EZXRhaWxlZCBXUklURSBzZXRTdHJlYW1EZXRhaWxlZCBOT1RJRlkgcHJlZmVyZW5jZXNDaGFu
Z2VkKQorICAgIFFfUFJPUEVSVFkoaW50IHBvc2l0aW9uIFJFQUQgcG9zaXRpb24gV1JJVEUgc2V0
UG9zaXRpb24gTk9USUZZIHByZWZlcmVuY2VzQ2hhbmdlZCkKKyAgICBRX1BST1BFUlRZKGludCBv
cGFjaXR5IFJFQUQgb3BhY2l0eSBXUklURSBzZXRPcGFjaXR5IE5PVElGWSBwcmVmZXJlbmNlc0No
YW5nZWQpCisgICAgUV9QUk9QRVJUWShpbnQgcmVmcmVzaFNlY29uZHMgUkVBRCByZWZyZXNoU2Vj
b25kcyBXUklURSBzZXRSZWZyZXNoU2Vjb25kcyBOT1RJRlkgcHJlZmVyZW5jZXNDaGFuZ2VkKQor
ICAgIFFfUFJPUEVSVFkoUVN0cmluZ0xpc3QgZmllbGRzIFJFQUQgZmllbGRzIFdSSVRFIHNldEZp
ZWxkcyBOT1RJRlkgcHJlZmVyZW5jZXNDaGFuZ2VkKQorcHVibGljOgorICAgIGV4cGxpY2l0IExv
Y2FsSGFyZHdhcmUoUU9iamVjdCogcGFyZW50PW51bGxwdHIpOworICAgIFFWYXJpYW50TWFwIHJl
YWRpbmdzKCkgY29uc3QgeyByZXR1cm4gbV9yZWFkaW5nczsgfQorICAgIFFWYXJpYW50TGlzdCBo
aXN0b3J5KCkgY29uc3QgeyByZXR1cm4gbV9oaXN0b3J5OyB9CisgICAgYm9vbCBvdmVybGF5KCkg
Y29uc3QgeyByZXR1cm4gUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvbG9jYWxPdmVybGF5Iixm
YWxzZSkudG9Cb29sKCk7IH0KKyAgICBib29sIGRldGFpbGVkKCkgY29uc3QgeyByZXR1cm4gUVNl
dHRpbmdzKCkudmFsdWUoImVjbGlwc2UvbG9jYWxEZXRhaWxlZCIsZmFsc2UpLnRvQm9vbCgpOyB9
CisgICAgYm9vbCBzdHJlYW1EZXRhaWxlZCgpIGNvbnN0IHsgcmV0dXJuIFFTZXR0aW5ncygpLnZh
bHVlKCJlY2xpcHNlL3N0cmVhbURldGFpbGVkIixmYWxzZSkudG9Cb29sKCk7IH0KKyAgICBpbnQg
cG9zaXRpb24oKSBjb25zdCB7IHJldHVybiBxQm91bmQoMCxRU2V0dGluZ3MoKS52YWx1ZSgiZWNs
aXBzZS9sb2NhbFBvc2l0aW9uIiwxKS50b0ludCgpLDMpOyB9CisgICAgaW50IG9wYWNpdHkoKSBj
b25zdCB7IHJldHVybiBxQm91bmQoNDAsUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2Uvb3Zlcmxh
eU9wYWNpdHkiLDg1KS50b0ludCgpLDEwMCk7IH0KKyAgICBpbnQgcmVmcmVzaFNlY29uZHMoKSBj
b25zdCB7IHJldHVybiBxQm91bmQoMSxRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9oYXJkd2Fy
ZVJlZnJlc2giLDIpLnRvSW50KCksNSk7IH0KKyAgICBRU3RyaW5nTGlzdCBmaWVsZHMoKSBjb25z
dCB7IHJldHVybiBRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9sb2NhbEZpZWxkcyIsUVN0cmlu
Z0xpc3R7ImNwdSIsIm1lbW9yeSIsInRlbXBlcmF0dXJlIiwiZ3B1IiwibmV0d29yayIsImJhdHRl
cnkifSkudG9TdHJpbmdMaXN0KCk7IH0KKyAgICB2b2lkIHNldE92ZXJsYXkoYm9vbCB2KSB7IHNh
dmUoImxvY2FsT3ZlcmxheSIsdik7IH0KKyAgICB2b2lkIHNldERldGFpbGVkKGJvb2wgdikgeyBz
YXZlKCJsb2NhbERldGFpbGVkIix2KTsgfQorICAgIHZvaWQgc2V0U3RyZWFtRGV0YWlsZWQoYm9v
bCB2KSB7IHNhdmUoInN0cmVhbURldGFpbGVkIix2KTsgfQorICAgIHZvaWQgc2V0UG9zaXRpb24o
aW50IHYpIHsgc2F2ZSgibG9jYWxQb3NpdGlvbiIscUJvdW5kKDAsdiwzKSk7IH0KKyAgICB2b2lk
IHNldE9wYWNpdHkoaW50IHYpIHsgc2F2ZSgib3ZlcmxheU9wYWNpdHkiLHFCb3VuZCg0MCx2LDEw
MCkpOyB9CisgICAgdm9pZCBzZXRSZWZyZXNoU2Vjb25kcyhpbnQgdikgeyBzYXZlKCJoYXJkd2Fy
ZVJlZnJlc2giLHFCb3VuZCgxLHYsNSkpOyBtX3RpbWVyLnNldEludGVydmFsKHJlZnJlc2hTZWNv
bmRzKCkqMTAwMCk7IH0KKyAgICB2b2lkIHNldEZpZWxkcyhRU3RyaW5nTGlzdCB2KTsKKyAgICBR
X0lOVk9LQUJMRSB2b2lkIHNldEFjdGl2ZShib29sIGFjdGl2ZSk7CisgICAgUV9JTlZPS0FCTEUg
dm9pZCBzZXRDb25zdW1lckFjdGl2ZShRT2JqZWN0KiBjb25zdW1lcixib29sIGFjdGl2ZSk7Cisg
ICAgc3RhdGljIFFWYXJpYW50TWFwIHNhbXBsZShjb25zdCBRU3RyaW5nJiByb290PVFTdHJpbmco
KSk7CisgICAgc3RhdGljIFFTdHJpbmcgb3ZlcmxheVRleHQoKTsKK3NpZ25hbHM6CisgICAgdm9p
ZCBjaGFuZ2VkKCk7CisgICAgdm9pZCBwcmVmZXJlbmNlc0NoYW5nZWQoKTsKK3ByaXZhdGU6Cisg
ICAgdm9pZCByZWZyZXNoKCk7CisgICAgdm9pZCB1cGRhdGVTYW1wbGluZygpOworICAgIGJvb2wg
bV9sZWdhY3lBY3RpdmU9ZmFsc2U7CisgICAgdm9pZCBzYXZlKFFTdHJpbmcga2V5LCBRVmFyaWFu
dCB2YWx1ZSkgeyBRU2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS8iK2tleSx2YWx1ZSk7IGVt
aXQgcHJlZmVyZW5jZXNDaGFuZ2VkKCk7IH0KKyAgICBRU2V0PFFPYmplY3QqPiBtX2NvbnN1bWVy
czsKKyAgICBRU2V0PFFPYmplY3QqPiBtX2tub3duQ29uc3VtZXJzOworICAgIFFUaW1lciBtX3Rp
bWVyOworICAgIFFWYXJpYW50TWFwIG1fcmVhZGluZ3M7CisgICAgUVZhcmlhbnRMaXN0IG1faGlz
dG9yeTsKK307CmRpZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvbWFuYWdlZHVwZGF0ZXMuY3Bw
IGIvYXBwL21vb25saWdodG9zL21hbmFnZWR1cGRhdGVzLmNwcApuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwLi4yYmZjYmZkCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdo
dG9zL21hbmFnZWR1cGRhdGVzLmNwcApAQCAtMCwwICsxLDEzMiBAQAorLy8gRWNsaXBzZU9TIG93
bnMgdGhpcyBjdXN0b21pemVkIG5hdGl2ZSBjbGllbnQuIE5vIGZlZWQgcmVxdWVzdHMsIGFzc2V0
CisvLyBkb3dubG9hZHMsIHN3YXBzIG9yIHJlbGF1bmNoZXMgYXJlIGNvbXBpbGVkIGludG8gdGhp
cyB1cGRhdGUgaW1wbGVtZW50YXRpb24uCisjaW5jbHVkZSAiLi4vYmFja2VuZC9hdXRvdXBkYXRl
Y2hlY2tlci5oIgorI2luY2x1ZGUgPFFDb3JlQXBwbGljYXRpb24+CisjaW5jbHVkZSA8UUpzb25P
YmplY3Q+CisKK3N0YXRpYyBRU3RyaW5nIHN0cmlwQnVpbGRNZXRhZGF0YShjb25zdCBRU3RyaW5n
JiB2ZXJzaW9uKQoreworICAgIGludCBwbHVzSWR4ID0gdmVyc2lvbi5pbmRleE9mKCcrJyk7Cisg
ICAgcmV0dXJuIHBsdXNJZHggPj0gMCA/IHZlcnNpb24ubGVmdChwbHVzSWR4KSA6IHZlcnNpb247
Cit9CisKK3N0YXRpYyBib29sIGlzTnVtZXJpY0lkZW50aWZpZXIoY29uc3QgUVN0cmluZyYgcykK
K3sKKyAgICBpZiAocy5pc0VtcHR5KCkpIHsKKyAgICAgICAgcmV0dXJuIGZhbHNlOworICAgIH0K
KyAgICBmb3IgKGNvbnN0IFFDaGFyJiBjIDogcykgeworICAgICAgICBpZiAoIWMuaXNEaWdpdCgp
KSB7CisgICAgICAgICAgICByZXR1cm4gZmFsc2U7CisgICAgICAgIH0KKyAgICB9CisgICAgcmV0
dXJuIHRydWU7Cit9CisKK2ludCBBdXRvVXBkYXRlQ2hlY2tlcjo6Y29tcGFyZVNlbWFudGljVmVy
c2lvbnMoY29uc3QgUVN0cmluZyYgdjEsIGNvbnN0IFFTdHJpbmcmIHYyKQoreworICAgIFFTdHJp
bmcgczEgPSBzdHJpcEJ1aWxkTWV0YWRhdGEodjEpOworICAgIFFTdHJpbmcgczIgPSBzdHJpcEJ1
aWxkTWV0YWRhdGEodjIpOworCisgICAgaW50IGRhc2gxID0gczEuaW5kZXhPZignLScpOworICAg
IGludCBkYXNoMiA9IHMyLmluZGV4T2YoJy0nKTsKKyAgICBRU3RyaW5nIGJhc2UxID0gZGFzaDEg
Pj0gMCA/IHMxLmxlZnQoZGFzaDEpIDogczE7CisgICAgUVN0cmluZyBiYXNlMiA9IGRhc2gyID49
IDAgPyBzMi5sZWZ0KGRhc2gyKSA6IHMyOworICAgIFFTdHJpbmcgcHJlMSA9IGRhc2gxID49IDAg
PyBzMS5taWQoZGFzaDEgKyAxKSA6IFFTdHJpbmcoKTsKKyAgICBRU3RyaW5nIHByZTIgPSBkYXNo
MiA+PSAwID8gczIubWlkKGRhc2gyICsgMSkgOiBRU3RyaW5nKCk7CisKKyAgICAvLyBOdW1lcmlj
IGJhc2UgdmVyc2lvbnMgY29tcGFyZSBmaXJzdCAoMC40LjAtYmV0YS4wMDEgPiAwLjMuMCkKKyAg
ICBjb25zdCBRU3RyaW5nTGlzdCBiYXNlUGFydHMxID0gYmFzZTEuc3BsaXQoJy4nKTsKKyAgICBj
b25zdCBRU3RyaW5nTGlzdCBiYXNlUGFydHMyID0gYmFzZTIuc3BsaXQoJy4nKTsKKyAgICBmb3Ig
KGludCBpID0gMDsgaSA8IHFNYXgoYmFzZVBhcnRzMS5jb3VudCgpLCBiYXNlUGFydHMyLmNvdW50
KCkpOyBpKyspIHsKKyAgICAgICAgcWxvbmdsb25nIGIxID0gaSA8IGJhc2VQYXJ0czEuY291bnQo
KSA/IGJhc2VQYXJ0czFbaV0udG9Mb25nTG9uZygpIDogMDsKKyAgICAgICAgcWxvbmdsb25nIGIy
ID0gaSA8IGJhc2VQYXJ0czIuY291bnQoKSA/IGJhc2VQYXJ0czJbaV0udG9Mb25nTG9uZygpIDog
MDsKKyAgICAgICAgaWYgKGIxICE9IGIyKSB7CisgICAgICAgICAgICByZXR1cm4gYjEgPCBiMiA/
IC0xIDogMTsKKyAgICAgICAgfQorICAgIH0KKworICAgIC8vIEVxdWFsIGJhc2U6IGEgcmVsZWFz
ZSB3aXRoIG5vIHByZXJlbGVhc2Ugc3VmZml4IG91dHJhbmtzIGFueSBwcmVyZWxlYXNlCisgICAg
aWYgKHByZTEuaXNFbXB0eSgpICE9IHByZTIuaXNFbXB0eSgpKSB7CisgICAgICAgIHJldHVybiBw
cmUxLmlzRW1wdHkoKSA/IDEgOiAtMTsKKyAgICB9CisgICAgaWYgKHByZTEuaXNFbXB0eSgpKSB7
CisgICAgICAgIHJldHVybiAwOworICAgIH0KKworICAgIC8vIFR3byBwcmVyZWxlYXNlczogY29t
cGFyZSBkb3Qtc2VwYXJhdGVkIGlkZW50aWZpZXJzIGxlZnQgdG8gcmlnaHQuCisgICAgLy8gTnVt
ZXJpYyBpZGVudGlmaWVycyBjb21wYXJlIG51bWVyaWNhbGx5IChsZWFkaW5nIHplcm9zIHRvbGVy
YXRlZCDigJQgb3VyCisgICAgLy8gQ0kgemVyby1wYWRzIGNvdW50ZXJzKSwgYWxwaGFudW1lcmlj
IG9uZXMgbGV4aWNhbGx5IGluIEFTQ0lJIG9yZGVyLCBhbmQKKyAgICAvLyBudW1lcmljIGFsd2F5
cyByYW5rcyBiZWxvdyBhbHBoYW51bWVyaWMuIFRoaXMgaXMgd2hhdCBvcmRlcnMKKyAgICAvLyAi
YWxwaGEiIDwgImJldGEiIDwgInJjIiBhdCBhbiBlcXVhbCBiYXNlIOKAlCB0aGUgcHJvcGVydHkg
dGhlIHByZXZpb3VzCisgICAgLy8gaW1wbGVtZW50YXRpb24gbGFja2VkIChpdCBza2lwcGVkIHRo
ZSB3b3JkcyBhbmQgY29tcGFyZWQgb25seSBudW1iZXJzLAorICAgIC8vIHNvIDAuMy4wLWJldGEu
MDA4IHdyb25nbHkgb3V0cmFua2VkIDAuMy4wLXJjLjAwMikuCisgICAgY29uc3QgUVN0cmluZ0xp
c3QgaWRzMSA9IHByZTEuc3BsaXQoJy4nKTsKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBpZHMyID0g
cHJlMi5zcGxpdCgnLicpOworICAgIGZvciAoaW50IGkgPSAwOyBpIDwgcU1heChpZHMxLmNvdW50
KCksIGlkczIuY291bnQoKSk7IGkrKykgeworICAgICAgICBpZiAoaSA+PSBpZHMxLmNvdW50KCkp
IHsKKyAgICAgICAgICAgIC8vIEVxdWFsIHByZWZpeCwgZmV3ZXIgZmllbGRzID0gbG93ZXIgcHJl
Y2VkZW5jZSAowqcxMS40LjQpCisgICAgICAgICAgICByZXR1cm4gLTE7CisgICAgICAgIH0KKyAg
ICAgICAgaWYgKGkgPj0gaWRzMi5jb3VudCgpKSB7CisgICAgICAgICAgICByZXR1cm4gMTsKKyAg
ICAgICAgfQorICAgICAgICBib29sIG51bTEgPSBpc051bWVyaWNJZGVudGlmaWVyKGlkczFbaV0p
OworICAgICAgICBib29sIG51bTIgPSBpc051bWVyaWNJZGVudGlmaWVyKGlkczJbaV0pOworICAg
ICAgICBpZiAobnVtMSAmJiBudW0yKSB7CisgICAgICAgICAgICBxbG9uZ2xvbmcgcDEgPSBpZHMx
W2ldLnRvTG9uZ0xvbmcoKTsKKyAgICAgICAgICAgIHFsb25nbG9uZyBwMiA9IGlkczJbaV0udG9M
b25nTG9uZygpOworICAgICAgICAgICAgaWYgKHAxICE9IHAyKSB7CisgICAgICAgICAgICAgICAg
cmV0dXJuIHAxIDwgcDIgPyAtMSA6IDE7CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICAg
ICAgZWxzZSBpZiAobnVtMSAhPSBudW0yKSB7CisgICAgICAgICAgICAvLyBOdW1lcmljIGlkZW50
aWZpZXJzIHJhbmsgYmVsb3cgYWxwaGFudW1lcmljIG9uZXMgKMKnMTEuNC4zKQorICAgICAgICAg
ICAgcmV0dXJuIG51bTEgPyAtMSA6IDE7CisgICAgICAgIH0KKyAgICAgICAgZWxzZSB7CisgICAg
ICAgICAgICBpbnQgY21wID0gUVN0cmluZzo6Y29tcGFyZShpZHMxW2ldLCBpZHMyW2ldKTsKKyAg
ICAgICAgICAgIGlmIChjbXAgIT0gMCkgeworICAgICAgICAgICAgICAgIHJldHVybiBjbXAgPCAw
ID8gLTEgOiAxOworICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgfQorICAgIHJldHVybiAw
OworfQorCitBdXRvVXBkYXRlQ2hlY2tlcjo6QXV0b1VwZGF0ZUNoZWNrZXIoUU9iamVjdCogcGFy
ZW50KSA6CisgICAgUU9iamVjdChwYXJlbnQpLCBtX0NoZWNrSW5GbGlnaHQoZmFsc2UpLCBtX0No
ZWNrSXNNYW51YWwoZmFsc2UpLAorICAgIG1fVXBkYXRlQXZhaWxhYmxlKGZhbHNlKSwgbV9PZmZl
ckF2YWlsYWJsZShmYWxzZSksIG1fSW5zdGFsbGluZyhmYWxzZSkKK3sKKyAgICBjbGVhck9mZmVy
KCk7CisgICAgc2V0U3RhdHVzKHRyKCIlMS4gVXBkYXRlcyBhcmUgbWFuYWdlZCBieSBFY2xpcHNl
T1MuIEdldCB0aGUgbWF0Y2hpbmcgT1MgaW1hZ2UgZnJvbSAlMjsgdXBzdHJlYW0gVmliZW1pcyB1
cGRhdGVzIGFyZSBkaXNhYmxlZC4iKS5hcmcoY3VycmVudFZlcnNpb24oKSwgbV9SZWxlYXNlVXJs
KSk7Cit9CitRU3RyaW5nIEF1dG9VcGRhdGVDaGVja2VyOjpjdXJyZW50VmVyc2lvbigpIGNvbnN0
Cit7CisgICAgcmV0dXJuIHRyKCJFY2xpcHNlICUxIMK3IEVjbGlwc2VPUyBjdXN0b21pemVkIiku
YXJnKFFDb3JlQXBwbGljYXRpb246OmFwcGxpY2F0aW9uVmVyc2lvbigpKTsKK30KK3ZvaWQgQXV0
b1VwZGF0ZUNoZWNrZXI6OmNsZWFyT2ZmZXIoKQoreworICAgIG1fVXBkYXRlQXZhaWxhYmxlID0g
ZmFsc2U7IG1fT2ZmZXJBdmFpbGFibGUgPSBmYWxzZTsKKyAgICBtX09mZmVyVmVyc2lvbi5jbGVh
cigpOyBtX0Fzc2V0VXJsLmNsZWFyKCk7IG1fT2ZmZXJUaWVyID0gLTE7CisgICAgbV9SZWxlYXNl
VXJsID0gUVN0cmluZ0xpdGVyYWwoImh0dHBzOi8vZ2l0aHViLmNvbS90aDNkM2NrM3IvTW9vbmxp
Z2h0LU9TL3JlbGVhc2VzIik7Cit9Cit2b2lkIEF1dG9VcGRhdGVDaGVja2VyOjpzZXRTdGF0dXMo
Y29uc3QgUVN0cmluZyYgbWVzc2FnZSkKK3sKKyAgICBpZiAobV9TdGF0dXNNZXNzYWdlICE9IG1l
c3NhZ2UpIHsgbV9TdGF0dXNNZXNzYWdlID0gbWVzc2FnZTsgZW1pdCBzdGF0ZUNoYW5nZWQoKTsg
fQorfQordm9pZCBBdXRvVXBkYXRlQ2hlY2tlcjo6c3RhcnQoKSB7IC8qIE5vIHRpbWVyIGFuZCBu
byBiYWNrZ3JvdW5kIHVwZGF0ZSByZXF1ZXN0cy4gKi8gfQorYm9vbCBBdXRvVXBkYXRlQ2hlY2tl
cjo6Y2FuSW5zdGFsbFVwZGF0ZXMoKSBjb25zdCB7IHJldHVybiBmYWxzZTsgfQorYm9vbCBBdXRv
VXBkYXRlQ2hlY2tlcjo6Y2FuSW5zdGFsbCgpIGNvbnN0IHsgcmV0dXJuIGZhbHNlOyB9Cit2b2lk
IEF1dG9VcGRhdGVDaGVja2VyOjpjaGFubmVsQ2hhbmdlZCgpIHsgY2hlY2tOb3coKTsgfQordm9p
ZCBBdXRvVXBkYXRlQ2hlY2tlcjo6Y2hlY2tOb3coKQoreworICAgIGNsZWFyT2ZmZXIoKTsKKyAg
ICBzZXRTdGF0dXModHIoIlVwZGF0ZXMgYXJlIG1hbmFnZWQgYnkgRWNsaXBzZU9TLiBEb3dubG9h
ZCB0aGUgbWF0Y2hpbmcgT1MgaW1hZ2UgZnJvbSAlMS4gVGhpcyBjbGllbnQgbmV2ZXIgaW5zdGFs
bHMgdXBzdHJlYW0gVmliZW1pcyByZWxlYXNlcy4iKS5hcmcobV9SZWxlYXNlVXJsKSk7CisgICAg
ZW1pdCBzdGF0ZUNoYW5nZWQoKTsgZW1pdCBjaGVja0NvbXBsZXRlZCh0cnVlLCBmYWxzZSk7Cit9
Cit2b2lkIEF1dG9VcGRhdGVDaGVja2VyOjppbnN0YWxsKCkKK3sKKyAgICBjaGVja05vdygpOwor
ICAgIGVtaXQgaW5zdGFsbEZhaWxlZCh0cigiU3RhbmRhbG9uZSBWaWJlbWlzIGluc3RhbGxhdGlv
biBpcyBkaXNhYmxlZCBpbiBFY2xpcHNlT1MuIiksIG1fUmVsZWFzZVVybCk7Cit9CmRpZmYgLS1n
aXQgYS9hcHAvbW9vbmxpZ2h0b3Mvb3ZlcmxheXN0eWxlLmggYi9hcHAvbW9vbmxpZ2h0b3Mvb3Zl
cmxheXN0eWxlLmgKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uOTExYTVjMwot
LS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRvcy9vdmVybGF5c3R5bGUuaApAQCAtMCww
ICsxLDIyIEBACisjcHJhZ21hIG9uY2UKKyNpbmNsdWRlIDxRSW1hZ2U+CisjaW5jbHVkZSA8UVBh
aW50ZXI+CisjaW5jbHVkZSA8UUNvbG9yPgorI2luY2x1ZGUgPFFMaW5lYXJHcmFkaWVudD4KK25h
bWVzcGFjZSBFY2xpcHNlT3ZlcmxheVN0eWxlIHsKK2lubGluZSBRQ29sb3IgYWNjZW50KGludCBp
bmRleCkgeworICAgIGNvbnN0IGNoYXIqIGNvbG9yc1tdPXsiIzAwQ0NDQyIsIiM3QzhDRjgiLCIj
M0VENTk4IiwiI0YwQTg2OCIsIiNEQzM2NTgiLCIjRjI1RDY0IiwiI0Y1ODM0NyIsIiNGMUJDNDUi
LCIjQjdEQzYzIiwiIzYzQ0NBRSIsIiM2M0M0RUQiLCIjNkM5RkZGIiwiI0FEODVGNSIsIiNFOTc2
QkMiLCIjQ0FEMERBIiwiI0Q5OTVBQyJ9OworICAgIHJldHVybiBRQ29sb3IoY29sb3JzW3FCb3Vu
ZCgwLGluZGV4LDE1KV0pOworfQoraW5saW5lIFFJbWFnZSBwYW5lbChRU2l6ZSBzaXplLGludCBh
Y2NlbnRJbmRleCxpbnQgb3BhY2l0eSkgeworICAgIGlmKHNpemUud2lkdGgoKTwzMiB8fCBzaXpl
LmhlaWdodCgpPDMyIHx8IHNpemUud2lkdGgoKT4yMDQ4IHx8IHNpemUuaGVpZ2h0KCk+NDA5Nikg
cmV0dXJuIHt9OworICAgIFFJbWFnZSBpbWFnZShzaXplLFFJbWFnZTo6Rm9ybWF0X1JHQkE4ODg4
KTsgaW1hZ2UuZmlsbChRdDo6dHJhbnNwYXJlbnQpOworICAgIFFQYWludGVyIHBhaW50ZXIoJmlt
YWdlKTsgcGFpbnRlci5zZXRSZW5kZXJIaW50KFFQYWludGVyOjpBbnRpYWxpYXNpbmcpOworICAg
IFFDb2xvciBiZygiIzE1MTExNSIpOyBiZy5zZXRBbHBoYShxQm91bmQoNDAsb3BhY2l0eSwxMDAp
KjI1NS8xMDApOworICAgIFFMaW5lYXJHcmFkaWVudCBnbGFzcygwLDAsMCxzaXplLmhlaWdodCgp
KTtRQ29sb3Igc2hpbmUoIiMyOTI0MkIiKTtzaGluZS5zZXRBbHBoYShiZy5hbHBoYSgpKTtnbGFz
cy5zZXRDb2xvckF0KDAsc2hpbmUpO2dsYXNzLnNldENvbG9yQXQoMSxiZyk7CisgICAgcGFpbnRl
ci5zZXRCcnVzaChnbGFzcyk7IHBhaW50ZXIuc2V0UGVuKFFQZW4oUUNvbG9yKDI1NSwyNTUsMjU1
LDQ4KSwxKSk7CisgICAgcGFpbnRlci5kcmF3Um91bmRlZFJlY3QoUVJlY3RGKDEsMSxpbWFnZS53
aWR0aCgpLTIsaW1hZ2UuaGVpZ2h0KCktMiksMTgsMTgpOworICAgIHBhaW50ZXIuc2V0UGVuKFFQ
ZW4oYWNjZW50KGFjY2VudEluZGV4KSwzKSk7IHBhaW50ZXIuZHJhd0xpbmUoMTUsOCxpbWFnZS53
aWR0aCgpLTE1LDgpOworICAgIHJldHVybiBpbWFnZTsKK30KK30KZGlmZiAtLWdpdCBhL2FwcC9t
b29ubGlnaHRvcy9zeXN0ZW1jb250cm9scy5jcHAgYi9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29u
dHJvbHMuY3BwCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjNlZTNmZjkKLS0t
IC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMuY3BwCkBAIC0w
LDAgKzEsODIgQEAKKyNpbmNsdWRlICJzeXN0ZW1jb250cm9scy5oIgorI2luY2x1ZGUgPFFDb3Jl
QXBwbGljYXRpb24+CisjaW5jbHVkZSA8UUpzb25Eb2N1bWVudD4KKyNpbmNsdWRlIDxRSnNvbk9i
amVjdD4KKyNpbmNsdWRlIDxRSnNvbkFycmF5PgorI2luY2x1ZGUgPFFRbWxFbmdpbmU+CisjaW5j
bHVkZSA8UUZpbGVJbmZvPgorU3lzdGVtQ29udHJvbHM6OlN5c3RlbUNvbnRyb2xzKFFPYmplY3Qq
IHBhcmVudCkgOiBRT2JqZWN0KHBhcmVudCkgeworICAgIG1fdGltZW91dC5zZXRTaW5nbGVTaG90
KHRydWUpOworICAgIGNvbm5lY3QoJm1fdGltZW91dCwgJlFUaW1lcjo6dGltZW91dCwgdGhpcywg
W3RoaXNdIHsgZmFpbCh0cigiT3BlcmF0aW9uIHRpbWVkIG91dC4gUmV0cnkgb3IgdXNlIHRoZSBk
aWFnbm9zdGljIHNoZWxsLiIpKTsgfSk7CisgICAgY29ubmVjdCgmbV9wcm9jZXNzLCAmUVByb2Nl
c3M6OnN0YXJ0ZWQsIHRoaXMsIFt0aGlzXSB7IHJlcXVlc3QobV9tb2RlICsgIi1saXN0Iik7IH0p
OworICAgIGNvbm5lY3QoJm1fcHJvY2VzcywgJlFQcm9jZXNzOjpyZWFkeVJlYWRTdGFuZGFyZEVy
cm9yLCB0aGlzLCBbdGhpc10geyBtX3Byb2Nlc3MucmVhZEFsbFN0YW5kYXJkRXJyb3IoKTsgfSk7
CisgICAgY29ubmVjdCgmbV9wcm9jZXNzLCAmUVByb2Nlc3M6OnJlYWR5UmVhZFN0YW5kYXJkT3V0
cHV0LCB0aGlzLCBbdGhpc10geworICAgICAgICBtX2J1ZmZlciArPSBtX3Byb2Nlc3MucmVhZEFs
bFN0YW5kYXJkT3V0cHV0KCk7CisgICAgICAgIGlmIChtX2J1ZmZlci5zaXplKCkgPiA2NTUzNikg
eyBmYWlsKHRyKCJJbnZhbGlkIHN5c3RlbSByZXNwb25zZS4iKSk7IHJldHVybjsgfQorICAgICAg
ICB3aGlsZSAobV9idWZmZXIuY29udGFpbnMoJ1xuJykpIHsKKyAgICAgICAgICAgIGludCBlbmQg
PSBtX2J1ZmZlci5pbmRleE9mKCdcbicpOworICAgICAgICAgICAgUUpzb25QYXJzZUVycm9yIGVy
cm9yOworICAgICAgICAgICAgYXV0byBkb2N1bWVudCA9IFFKc29uRG9jdW1lbnQ6OmZyb21Kc29u
KG1fYnVmZmVyLmxlZnQoZW5kKSwgJmVycm9yKTsKKyAgICAgICAgICAgIG1fYnVmZmVyLnJlbW92
ZSgwLCBlbmQgKyAxKTsKKyAgICAgICAgICAgIGlmIChlcnJvci5lcnJvciAhPSBRSnNvblBhcnNl
RXJyb3I6Ok5vRXJyb3IgfHwgIWRvY3VtZW50LmlzT2JqZWN0KCkpIHsgZmFpbCh0cigiSW52YWxp
ZCBzeXN0ZW0gcmVzcG9uc2UuIikpOyByZXR1cm47IH0KKyAgICAgICAgICAgIGF1dG8gdmFsdWUg
PSBkb2N1bWVudC5vYmplY3QoKTsKKyAgICAgICAgICAgIGlmICh2YWx1ZS5jb250YWlucygicHJv
bXB0IikpIHsKKyAgICAgICAgICAgICAgICBtX3Byb21wdCA9IHZhbHVlLnZhbHVlKCJwcm9tcHQi
KS50b1N0cmluZygpLmxlZnQoMTAyNCk7CisgICAgICAgICAgICAgICAgbV90aW1lb3V0LnN0YXJ0
KDEyMDAwMCk7CisgICAgICAgICAgICB9CisgICAgICAgICAgICBpZiAodmFsdWUuY29udGFpbnMo
Iml0ZW1zIikpIHsKKyAgICAgICAgICAgICAgICBhdXRvIGVudHJpZXMgPSB2YWx1ZS52YWx1ZSgi
aXRlbXMiKS50b0FycmF5KCk7CisgICAgICAgICAgICAgICAgaWYgKGVudHJpZXMuc2l6ZSgpID4g
NjQpIHsgZmFpbCh0cigiSW52YWxpZCBkZXZpY2UgbGlzdC4iKSk7IHJldHVybjsgfQorICAgICAg
ICAgICAgICAgIG1faXRlbXMgPSBlbnRyaWVzLnRvVmFyaWFudExpc3QoKTsKKyAgICAgICAgICAg
IH0KKyAgICAgICAgICAgIGlmICh2YWx1ZS52YWx1ZSgic3RhdGUiKS5pc09iamVjdCgpKSBtX3N0
YXRlID0gdmFsdWUudmFsdWUoInN0YXRlIikudG9PYmplY3QoKS50b1ZhcmlhbnRNYXAoKTsKKyAg
ICAgICAgICAgIGlmKHZhbHVlLmNvbnRhaW5zKCJzdGF0dXMiKSkgbV9zdGF0dXM9dmFsdWUudmFs
dWUoInN0YXR1cyIpLnRvU3RyaW5nKCkubGVmdCgxMDI0KTsKKyAgICAgICAgICAgIGlmKHZhbHVl
LmNvbnRhaW5zKCJlcnJvciIpKSBtX3N0YXR1cz12YWx1ZS52YWx1ZSgiZXJyb3IiKS50b1N0cmlu
ZygpLmxlZnQoMTAyNCk7CisgICAgICAgICAgICBpZiAodmFsdWUudmFsdWUoImRvbmUiKS50b0Jv
b2woKSkgeyBtX3RpbWVvdXQuc3RvcCgpOyBtX2J1c3k9ZmFsc2U7IG1fcHJvbXB0LmNsZWFyKCk7
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
IG1vZGUgIT0gImJ0IiAmJiBtb2RlICE9ICJjZW50ZXIiKSByZXR1cm47CisgICAgY2xvc2UoKTsK
KyAgICBpZiAobV9wcm9jZXNzLnN0YXRlKCkgIT0gUVByb2Nlc3M6Ok5vdFJ1bm5pbmcpIHsgbV9w
cm9jZXNzLmtpbGwoKTsgbV9wcm9jZXNzLndhaXRGb3JGaW5pc2hlZCg1MDApOyB9CisgICAgbV9t
b2RlID0gbW9kZTsgbV9pdGVtcy5jbGVhcigpOyBtX3N0YXRlLmNsZWFyKCk7IG1fYnVmZmVyLmNs
ZWFyKCk7IG1fc3RhdHVzID0gdHIoIkxvYWRpbmfigKYiKTsgZW1pdCBjaGFuZ2VkKCk7CisgICAg
UVN0cmluZyBoZWxwZXIgPSAiL3Vzci9sb2NhbC9saWJleGVjL21vb25saWdodC1vcy9zeXN0ZW0t
Y29udHJvbHMucHkiOworI2lmZGVmIE1PT05MSUdIVF9DT05UUk9MU19URVNUCisgICAgaGVscGVy
ID0gcUVudmlyb25tZW50VmFyaWFibGUoIk1PT05MSUdIVF9DT05UUk9MU19GSVhUVVJFIiwgaGVs
cGVyKTsKKyNlbmRpZgorICAgIG1fcHJvY2Vzcy5zdGFydCgicHl0aG9uMyIsIHtoZWxwZXJ9KTsK
K30KK3ZvaWQgU3lzdGVtQ29udHJvbHM6OnJlcXVlc3QoUVN0cmluZyBhY3Rpb24sIFFTdHJpbmcg
aWQsIGJvb2wgY29uZmlybSkgeworICAgIGlmIChtX2J1c3kgfHwgbV9wcm9jZXNzLnN0YXRlKCkg
IT0gUVByb2Nlc3M6OlJ1bm5pbmcgfHwgIWFjdGlvbi5zdGFydHNXaXRoKG1fbW9kZSArICItIikp
IHJldHVybjsKKyAgICBjb25zdCBRU3RyaW5nTGlzdCBhbGxvd2VkID0geyJ3aWZpLWxpc3QiLCAi
d2lmaS1zY2FuIiwgIndpZmktY29ubmVjdCIsICJ3aWZpLWRpc2Nvbm5lY3QiLCAiYnQtbGlzdCIs
ICJidC1zY2FuIiwgImJ0LWNvbm5lY3QiLCAiYnQtZGlzY29ubmVjdCIsICJidC1mb3JnZXQiLCAi
Y2VudGVyLXdpZmktcmFkaW8iLCAiY2VudGVyLWJ0LXJhZGlvIiwgImNlbnRlci1haXJwb2RzIiwg
ImNlbnRlci10ZXN0LXNvdW5kIiwgImNlbnRlci1pZGxlIiwgImNlbnRlci1wb2ludGVyLXNwZWVk
IiwgImNlbnRlci1wb2ludGVyLW5hdHVyYWwiLCAiY2VudGVyLXBvaW50ZXItdGFwIiwgImNlbnRl
ci1kaXNwbGF5IiwgImNlbnRlci1mcm9udGVuZCIsICJjZW50ZXItcmVzdGFydC1mcm9udGVuZCIs
ICJjZW50ZXItbGlzdCIsICJjZW50ZXItdm9sdW1lIiwgImNlbnRlci1tdXRlIiwgImNlbnRlci1v
dXRwdXQiLCAiY2VudGVyLXNjcmVlbiIsICJjZW50ZXIta2V5Ym9hcmQiLCAiY2VudGVyLXJlYm9v
dCIsICJjZW50ZXItcG93ZXJvZmYiLCAiY2VudGVyLXN1c3BlbmQiLCAiY2VudGVyLXJlcG9ydCJ9
OworICAgIGlmICghYWxsb3dlZC5jb250YWlucyhhY3Rpb24pKSByZXR1cm47CisgICAgbV9idXN5
ID0gdHJ1ZTsgbV9wcm9tcHQuY2xlYXIoKTsgbV9zdGF0dXMgPSBhY3Rpb24uZW5kc1dpdGgoInNj
YW4iKSA/IHRyKCJTdGFydGluZyBzY2Fu4oCmIikgOiB0cigiV29ya2luZ+KApiIpOyBtX3RpbWVv
dXQuc3RhcnQoYWN0aW9uLmVuZHNXaXRoKCJzY2FuIikgPyAzMDAwMCA6IDEwMDAwMCk7CisgICAg
c2VuZCh7eyJhY3Rpb24iLCBhY3Rpb259LCB7ImlkIiwgaWR9LCB7ImNvbmZpcm0iLCBjb25maXJt
fX0pOyBlbWl0IGNoYW5nZWQoKTsKK30KK3ZvaWQgU3lzdGVtQ29udHJvbHM6OmFuc3dlcihRU3Ry
aW5nIHZhbHVlKSB7CisgICAgaWYgKCFtX2J1c3kgfHwgbV9wcm9tcHQuaXNFbXB0eSgpIHx8IHZh
bHVlLnNpemUoKSA+IDQwOTYgfHwgdmFsdWUuY29udGFpbnMoJ1xuJykgfHwgdmFsdWUuY29udGFp
bnMoJ1xyJykgfHwgdmFsdWUuY29udGFpbnMoUUNoYXIoMCkpKSByZXR1cm47CisgICAgc2VuZCh7
eyJhY3Rpb24iLCAiYW5zd2VyIn0sIHsidmFsdWUiLCB2YWx1ZX19KTsgbV9wcm9tcHQuY2xlYXIo
KTsgbV90aW1lb3V0LnN0YXJ0KDEyMDAwMCk7IGVtaXQgY2hhbmdlZCgpOworfQordm9pZCBTeXN0
ZW1Db250cm9sczo6Y2xvc2UoKSB7CisgICAgbV9tb2RlLmNsZWFyKCk7IG1fdGltZW91dC5zdG9w
KCk7IG1fYnVzeSA9IGZhbHNlOyBtX3Byb21wdC5jbGVhcigpOyBtX2J1ZmZlci5jbGVhcigpOwor
ICAgIGlmIChtX3Byb2Nlc3Muc3RhdGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgeworICAg
ICAgICBtX3Byb2Nlc3MudGVybWluYXRlKCk7CisgICAgICAgIFFUaW1lcjo6c2luZ2xlU2hvdCg0
MDAwLCB0aGlzLCBbdGhpc10geyBpZiAobV9tb2RlLmlzRW1wdHkoKSAmJiBtX3Byb2Nlc3Muc3Rh
dGUoKSAhPSBRUHJvY2Vzczo6Tm90UnVubmluZykgbV9wcm9jZXNzLmtpbGwoKTsgfSk7CisgICAg
fQorICAgIGVtaXQgY2hhbmdlZCgpOworfQordm9pZCBTeXN0ZW1Db250cm9sczo6ZmFpbChRU3Ry
aW5nIG1lc3NhZ2UpIHsgY2xvc2UoKTsgbV9zdGF0dXMgPSBtZXNzYWdlOyBlbWl0IGNoYW5nZWQo
KTsgfQorc3RhdGljIHZvaWQgcmVnaXN0ZXJTeXN0ZW1Db250cm9scygpIHsKKyAgICBxbWxSZWdp
c3RlclNpbmdsZXRvblR5cGU8U3lzdGVtQ29udHJvbHM+KCJTeXN0ZW1Db250cm9scyIsIDEsIDAs
ICJTeXN0ZW1Db250cm9scyIsIFtdKFFRbWxFbmdpbmUqLCBRSlNFbmdpbmUqKSAtPiBRT2JqZWN0
KiB7IHJldHVybiBuZXcgU3lzdGVtQ29udHJvbHMoKTsgfSk7Cit9CitRX0NPUkVBUFBfU1RBUlRV
UF9GVU5DVElPTihyZWdpc3RlclN5c3RlbUNvbnRyb2xzKQpkaWZmIC0tZ2l0IGEvYXBwL21vb25s
aWdodG9zL3N5c3RlbWNvbnRyb2xzLmggYi9hcHAvbW9vbmxpZ2h0b3Mvc3lzdGVtY29udHJvbHMu
aApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwLi4xOGU5ZGViCi0tLSAvZGV2L251
bGwKKysrIGIvYXBwL21vb25saWdodG9zL3N5c3RlbWNvbnRyb2xzLmgKQEAgLTAsMCArMSwzOSBA
QAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UU9iamVjdD4KKyNpbmNsdWRlIDxRSnNvbk9iamVj
dD4KKyNpbmNsdWRlIDxRUHJvY2Vzcz4KKyNpbmNsdWRlIDxRVGltZXI+CisjaW5jbHVkZSA8UVZh
cmlhbnRMaXN0PgorI2luY2x1ZGUgPFFWYXJpYW50TWFwPgorY2xhc3MgU3lzdGVtQ29udHJvbHMg
OiBwdWJsaWMgUU9iamVjdCB7CisgICAgUV9PQkpFQ1QKKyAgICBRX1BST1BFUlRZKFFWYXJpYW50
TWFwIHN0YXRlIFJFQUQgc3RhdGUgTk9USUZZIGNoYW5nZWQpCisgICAgUV9QUk9QRVJUWShRVmFy
aWFudExpc3QgaXRlbXMgUkVBRCBpdGVtcyBOT1RJRlkgY2hhbmdlZCkKKyAgICBRX1BST1BFUlRZ
KFFTdHJpbmcgc3RhdHVzIFJFQUQgc3RhdHVzIE5PVElGWSBjaGFuZ2VkKQorICAgIFFfUFJPUEVS
VFkoUVN0cmluZyBwcm9tcHQgUkVBRCBwcm9tcHQgTk9USUZZIGNoYW5nZWQpCisgICAgUV9QUk9Q
RVJUWShib29sIGJ1c3kgUkVBRCBidXN5IE5PVElGWSBjaGFuZ2VkKQorcHVibGljOgorICAgIGV4
cGxpY2l0IFN5c3RlbUNvbnRyb2xzKFFPYmplY3QqIHBhcmVudCA9IG51bGxwdHIpOworICAgIH5T
eXN0ZW1Db250cm9scygpOworICAgIFFWYXJpYW50TWFwIHN0YXRlKCkgY29uc3QgeyByZXR1cm4g
bV9zdGF0ZTsgfQorICAgIFFWYXJpYW50TGlzdCBpdGVtcygpIGNvbnN0IHsgcmV0dXJuIG1faXRl
bXM7IH0KKyAgICBRU3RyaW5nIHN0YXR1cygpIGNvbnN0IHsgcmV0dXJuIG1fc3RhdHVzOyB9Cisg
ICAgUVN0cmluZyBwcm9tcHQoKSBjb25zdCB7IHJldHVybiBtX3Byb21wdDsgfQorICAgIGJvb2wg
YnVzeSgpIGNvbnN0IHsgcmV0dXJuIG1fYnVzeTsgfQorICAgIFFfSU5WT0tBQkxFIHZvaWQgb3Bl
bihRU3RyaW5nIG1vZGUpOworICAgIFFfSU5WT0tBQkxFIHZvaWQgcmVxdWVzdChRU3RyaW5nIGFj
dGlvbiwgUVN0cmluZyBpZCA9IFFTdHJpbmcoKSwgYm9vbCBjb25maXJtID0gZmFsc2UpOworICAg
IFFfSU5WT0tBQkxFIHZvaWQgYW5zd2VyKFFTdHJpbmcgdmFsdWUpOworICAgIFFfSU5WT0tBQkxF
IHZvaWQgY2xvc2UoKTsKK3NpZ25hbHM6CisgICAgdm9pZCBjaGFuZ2VkKCk7Citwcml2YXRlOgor
ICAgIHZvaWQgc2VuZChjb25zdCBRSnNvbk9iamVjdCYgdmFsdWUpOworICAgIHZvaWQgZmFpbChR
U3RyaW5nIG1lc3NhZ2UpOworICAgIFFQcm9jZXNzIG1fcHJvY2VzczsKKyAgICBRVGltZXIgbV90
aW1lb3V0OworICAgIFFCeXRlQXJyYXkgbV9idWZmZXI7CisgICAgUVZhcmlhbnRMaXN0IG1faXRl
bXM7CisgICAgUVZhcmlhbnRNYXAgbV9zdGF0ZTsKKyAgICBRU3RyaW5nIG1fbW9kZSwgbV9zdGF0
dXMsIG1fcHJvbXB0OworICAgIGJvb2wgbV9idXN5ID0gZmFsc2U7Cit9OwpkaWZmIC0tZ2l0IGEv
YXBwL21vb25saWdodG9zL3Rlc3RzL0hhcm5lc3MucW1sIGIvYXBwL21vb25saWdodG9zL3Rlc3Rz
L0hhcm5lc3MucW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLmI3MTk3NjMK
LS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvSGFybmVzcy5xbWwKQEAg
LTAsMCArMSw2NCBAQAoraW1wb3J0IFF0UXVpY2sgMi45CitpbXBvcnQgUXRRdWljay5Db250cm9s
cyAyLjUKK2ltcG9ydCBRdFF1aWNrLkNvbnRyb2xzLk1hdGVyaWFsIDIuMgoraW1wb3J0IFZpYmVt
aXMuUmVkZXNpZ24gMS4wCitpbXBvcnQgU3RyZWFtaW5nUHJlZmVyZW5jZXMgMS4wCitpbXBvcnQg
RWNsaXBzZVByb2ZpbGVzIDEuMAoraW1wb3J0ICIuLi8uLi9ndWkiCitBcHBsaWNhdGlvbldpbmRv
dyB7CisgICAgTWF0ZXJpYWwudGhlbWU6IE1hdGVyaWFsLkRhcmsKKyAgICBNYXRlcmlhbC5hY2Nl
bnQ6IFZiVG9rZW5zLmFjY2VudAorICAgIE1hdGVyaWFsLmJhY2tncm91bmQ6IFZiVG9rZW5zLmJn
V2luZG93CisgICAgTWF0ZXJpYWwuZm9yZWdyb3VuZDogVmJUb2tlbnMudGV4dAorICAgIGNvbG9y
OiBWYlRva2Vucy5iZ0FwcAorICAgIHdpZHRoOiAxMjgwOyBoZWlnaHQ6IDgwMDsgdmlzaWJsZTog
dHJ1ZQorICAgIGZ1bmN0aW9uIGNob29zZVNjYWxlKHZhbHVlKSB7IEVjbGlwc2VQcm9maWxlcy50
ZXh0U2NhbGU9dmFsdWUgfQorICAgIGZ1bmN0aW9uIGNob29zZUFjY2VudChpKSB7IFN0cmVhbWlu
Z1ByZWZlcmVuY2VzLnVpQWNjZW50SW5kZXggPSBpIH0KKyAgICBmdW5jdGlvbiBjaG9vc2VBY2Nl
c3NpYmlsaXR5KGNvbnRyYXN0LG1vdGlvbikgeyBFY2xpcHNlUHJvZmlsZXMuaGlnaENvbnRyYXN0
PWNvbnRyYXN0O0VjbGlwc2VQcm9maWxlcy5yZWR1Y2VkTW90aW9uPW1vdGlvbiB9CisgICAgZnVu
Y3Rpb24gY2hvb3NlV2FsbHBhcGVyKHVybCkgeyByZXR1cm4gRWNsaXBzZVByb2ZpbGVzLmNob29z
ZUJhY2tncm91bmQodXJsKSB9CisgICAgZnVuY3Rpb24gcmVzZXRXYWxscGFwZXIoKSB7IEVjbGlw
c2VQcm9maWxlcy5yZXNldEJhY2tncm91bmQoKSB9CisgICAgZnVuY3Rpb24gY2hvb3NlRGltbWlu
Zyh2YWx1ZSkgeyBFY2xpcHNlUHJvZmlsZXMuYmFja2dyb3VuZERpbT12YWx1ZSB9CisgICAgQ3Jp
bXNvbkdsYXNzQmFja2Ryb3Age2FuY2hvcnMuZmlsbDpwYXJlbnR9CisgICAgQnV0dG9uIHtpZDpz
ZXR0aW5nc0J1dHRvbjt2aXNpYmxlOmZhbHNlfQorICAgIEJ1dHRvbiB7aWQ6ZWNsaXBzZUNlbnRl
ckJ1dHRvbjt2aXNpYmxlOmZhbHNlfQorICAgIFF0T2JqZWN0IHtpZDpjcmltc29uUGFuZWw7cHJv
cGVydHkgc3RyaW5nIGtpbmQ6IiI7ZnVuY3Rpb24gb3Blbigpe319CisgICAgUXRPYmplY3Qge2lk
OmFkZFBjRGlhbG9nO2Z1bmN0aW9uIG9wZW4oKXt9fQorICAgIFF0T2JqZWN0IHtpZDpxdWlja01l
bnVNYW5hZ2VyO3Byb3BlcnR5IHZhciBzZXJ2ZXJDb21tYW5kTWFuYWdlcjpudWxsO2Z1bmN0aW9u
IGhpZGUoKXt9IGZ1bmN0aW9uIGV4ZWN1dGVBY3Rpb24oYWN0aW9uKXt9IGZ1bmN0aW9uIHNldFRl
eHRJbnB1dEFjdGl2ZShhY3RpdmUpe30gfQorICAgIExvYWRlciB7b2JqZWN0TmFtZToicXVpY2tN
ZW51TG9hZGVyIjthY3RpdmU6ZmFsc2U7YW5jaG9ycy5jZW50ZXJJbjpwYXJlbnQ7c291cmNlQ29t
cG9uZW50OlF1aWNrTWVudSB7fX0KKyAgICBTdGFja1ZpZXcgeyBpZDpzdGFja1ZpZXc7b2JqZWN0
TmFtZToicHJvZHVjdGlvblN0YWNrIjthbmNob3JzLmZpbGw6cGFyZW50O3Zpc2libGU6ZmFsc2Ug
fQorICAgIGZ1bmN0aW9uIHNob3dQcm9kdWN0aW9uVmlldyh2aWV3KSB7CisgICAgICAgIHN0YWNr
Vmlldy52aXNpYmxlPXRydWU7c3RhY2tWaWV3LmNsZWFyKCkKKyAgICAgICAgdmFyIHByb3BzPXZp
ZXc9PT0iQXBwVmlldyI/e2NvbXB1dGVySW5kZXg6MCxvYmplY3ROYW1lOiJHYW1pbmcgUEMiLGhv
c3RUeXBlOiJWSUJFUE9MTE8iLGhvc3RUcmFuc3BvcnQ6IkxBTiIsaG9zdE9ubGluZTp0cnVlLHNo
b3dHYW1lczp0cnVlfTp7fQorICAgICAgICBzdGFja1ZpZXcucHVzaChRdC5yZXNvbHZlZFVybCgi
Li4vLi4vZ3VpLyIrdmlldysiLnFtbCIpLHByb3BzKQorICAgIH0KKyAgICBmdW5jdGlvbiBoaWRl
UHJvZHVjdGlvblZpZXcoKXtzdGFja1ZpZXcuY2xlYXIoKTtzdGFja1ZpZXcudmlzaWJsZT1mYWxz
ZX0KKyAgICBRdE9iamVjdCB7IG9iamVjdE5hbWU6ICJ0ZXN0U3RhdGUiOyBwcm9wZXJ0eSBjb2xv
ciBhY2NlbnQ6IFZiVG9rZW5zLmFjY2VudDsgcHJvcGVydHkgY29sb3IgcHJlc3NlZDogVmJUb2tl
bnMuYWNjZW50UHJlc3NlZCB9CisgICAgQ3JpbXNvblN0YXR1c0RpYWxvZyB7IG9iamVjdE5hbWU6
ICJ0ZXN0UGFuZWwiIH0KKyAgICBTeXN0ZW1Db25uZWN0aW9uc0RpYWxvZyB7IG9iamVjdE5hbWU6
ICJjb25uZWN0aW9uc1BhbmVsIiB9CisgICAgRWNsaXBzZUNvbnRyb2xDZW50ZXIgeyBvYmplY3RO
YW1lOiAiY29udHJvbENlbnRlciIgfQorICAgIFNjcm9sbFZpZXcgeyBpZDpzeXN0ZW1TY3JvbGw7
IG9iamVjdE5hbWU6InN5c3RlbVNjcm9sbCI7Y29udGVudFdpZHRoOmF2YWlsYWJsZVdpZHRoOyBh
bmNob3JzLmZpbGw6cGFyZW50OyBhbmNob3JzLm1hcmdpbnM6MjQ7IHZpc2libGU6c3lzdGVtUGFu
ZWwuYWN0aXZlCisgICAgICAgIEVjbGlwc2VTeXN0ZW1TZXR0aW5ncyB7IGlkOnN5c3RlbVBhbmVs
O29iamVjdE5hbWU6InN5c3RlbVNldHRpbmdzIjt3aWR0aDpzeXN0ZW1TY3JvbGwuYXZhaWxhYmxl
V2lkdGg7YWN0aXZlOmZhbHNlIH0KKyAgICB9CisgICAgQ3JpbXNvbkJhY2tncm91bmRQaWNrZXIg
e29iamVjdE5hbWU6ImdsYXNzQmFja2dyb3VuZFBpY2tlciJ9CisgICAgSXRlbSB7CisgICAgICAg
IGlkOmRhc2hib2FyZDtvYmplY3ROYW1lOiJnbGFzc0Rhc2hib2FyZCI7YW5jaG9ycy5maWxsOnBh
cmVudDt2aXNpYmxlOmZhbHNlCisgICAgICAgIENyaW1zb25HbGFzc0JhY2tkcm9wIHthbmNob3Jz
LmZpbGw6cGFyZW50fQorICAgICAgICBDcmltc29uR2xhc3NSYWlsIHt4OjE2O3k6MTY7d2lkdGg6
NjQ7aGVpZ2h0OnBhcmVudC5oZWlnaHQtMzJ9CisgICAgICAgIENyaW1zb25Ib3N0UGFuZWwge29i
amVjdE5hbWU6ImdsYXNzSG9zdCI7eDo5Njt5OjE2O3dpZHRoOnBhcmVudC53aWR0aD49MTU4MD8y
NjA6MDtoZWlnaHQ6cGFyZW50LmhlaWdodC0zMjt2aXNpYmxlOndpZHRoPjA7aG9zdE5hbWU6Ikdh
bWluZyBQQyI7aG9zdFR5cGU6IlZpYmVwb2xsbyI7dHJhbnNwb3J0OiJMQU4iO29ubGluZTp0cnVl
fQorICAgICAgICBDcmltc29uTG9jYWxQYW5lbCB7YWN0aXZlOmRhc2hib2FyZC52aXNpYmxlO3g6
cGFyZW50LndpZHRoLXdpZHRoLTE2O3k6MTY7d2lkdGg6TWF0aC5yb3VuZCgyNTIqVmJUb2tlbnMu
dGV4dFNjYWxlKTtoZWlnaHQ6cGFyZW50LmhlaWdodC0zMjt2aXNpYmxlOnBhcmVudC53aWR0aD49
MTI0MH0KKyAgICAgICAgQ29sdW1uIHsKKyAgICAgICAgICAgIHg6cGFyZW50LndpZHRoPj0xNTgw
PzM3NjoxMDQ7eToyNDt3aWR0aDpwYXJlbnQud2lkdGgteC0ocGFyZW50LndpZHRoPj0xMjQwP01h
dGgucm91bmQoMjUyKlZiVG9rZW5zLnRleHRTY2FsZSkrNDA6MjQpO3NwYWNpbmc6MTYKKyAgICAg
ICAgICAgIExhYmVsIHt0ZXh0OiJDcmltc29uIEdsYXNzIOKAoiBMaWJyYXJ5Ijtmb250LnBpeGVs
U2l6ZTpWYlRva2Vucy50eXBlVGl0bGU7Y29sb3I6VmJUb2tlbnMudGV4dH0KKyAgICAgICAgICAg
IExhYmVsIHt0ZXh0OiJVSSB2ZXJpZmljYXRpb24gZml4dHVyZSDigKIgaWxsdXN0cmF0aXZlIGhv
c3QgYW5kIGFwcCBkYXRhIjtmb250LnBpeGVsU2l6ZTpWYlRva2Vucy50eXBlTGFiZWw7Y29sb3I6
VmJUb2tlbnMudGV4dERpbTt3aWR0aDpwYXJlbnQud2lkdGg7d3JhcE1vZGU6VGV4dC5XcmFwfQor
ICAgICAgICAgICAgRmxvdyB7d2lkdGg6cGFyZW50LndpZHRoO3NwYWNpbmc6MTYKKyAgICAgICAg
ICAgICAgICBSZXBlYXRlciB7bW9kZWw6WyJEZXNrdG9wIiwiU3RlYW0gQmlnIFBpY3R1cmUiLCJH
YW1lIGxpYnJhcnkiLCJNZWRpYSJdCisgICAgICAgICAgICAgICAgICAgIGRlbGVnYXRlOlZiQ2Fy
ZCB7d2lkdGg6TWF0aC5tYXgoMTgwLE1hdGgubWluKDI1MCwocGFyZW50LndpZHRoLTMyKS8yKSk7
aGVpZ2h0OjIyMAorICAgICAgICAgICAgICAgICAgICAgICAgSW1hZ2Uge2FuY2hvcnMuY2VudGVy
SW46cGFyZW50O3dpZHRoOjY0O2hlaWdodDo2NDtzb3VyY2U6InFyYzovcmVzL2VjbGlwc2UtaWNv
bi5zdmcifQorICAgICAgICAgICAgICAgICAgICAgICAgTGFiZWwge2FuY2hvcnMuYm90dG9tOnBh
cmVudC5ib3R0b207YW5jaG9ycy5ib3R0b21NYXJnaW46MjA7YW5jaG9ycy5ob3Jpem9udGFsQ2Vu
dGVyOnBhcmVudC5ob3Jpem9udGFsQ2VudGVyO3RleHQ6bW9kZWxEYXRhO2NvbG9yOlZiVG9rZW5z
LnRleHQ7Zm9udC5waXhlbFNpemU6VmJUb2tlbnMudHlwZUJvZHl9CisgICAgICAgICAgICAgICAg
ICAgIH0KKyAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICB9CisgICAgICAgIH0KKyAgICB9
CisgICAgRWNsaXBzZUFib3V0RGlhbG9nIHsgb2JqZWN0TmFtZTogImFib3V0RWNsaXBzZSIgfQor
fQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL1ByZWZlcmVuY2VzLnFtbCBiL2Fw
cC9tb29ubGlnaHRvcy90ZXN0cy9QcmVmZXJlbmNlcy5xbWwKbmV3IGZpbGUgbW9kZSAxMDA2NDQK
aW5kZXggMDAwMDAwMC4uMDNhZGM2OAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9tb29ubGlnaHRv
cy90ZXN0cy9QcmVmZXJlbmNlcy5xbWwKQEAgLTAsMCArMSwzIEBACitwcmFnbWEgU2luZ2xldG9u
CitpbXBvcnQgUXRRdWljayAyLjkKK1F0T2JqZWN0IHsgcHJvcGVydHkgaW50IHVpQWNjZW50SW5k
ZXg6IDQ7IHByb3BlcnR5IGJvb2wgZW5hYmxlTWRuczp0cnVlOyBwcm9wZXJ0eSBib29sIHVpU2hv
d0hpbnRzOiB0cnVlOyBwcm9wZXJ0eSBpbnQgd2lkdGg6IDE5MjA7IHByb3BlcnR5IGludCBoZWln
aHQ6IDEwODA7IHByb3BlcnR5IGludCBmcHM6IDYwOyBwcm9wZXJ0eSBpbnQgYml0cmF0ZUticHM6
IDIwMDAwOyBmdW5jdGlvbiBzYXZlKCkge30gfQpkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9z
L3Rlc3RzL1VpU2VydmljZXMucW1sIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL1VpU2VydmljZXMu
cW1sCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjBjM2Y5NjQKLS0tIC9kZXYv
bnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvVWlTZXJ2aWNlcy5xbWwKQEAgLTAsMCAr
MSwxNyBAQAorcHJhZ21hIFNpbmdsZXRvbgoraW1wb3J0IFF0UXVpY2sgMi45CitRdE9iamVjdCB7
CisgICAgcHJvcGVydHkgYm9vbCBoYXNCcm93c2VyOiBmYWxzZQorICAgIHByb3BlcnR5IHN0cmlu
ZyB2ZXJzaW9uU3RyaW5nOiAiVUkgZml4dHVyZSIKKyAgICBzaWduYWwgb3RwU3RhZ2UxQ29tcGxl
dGVkKHN0cmluZyBwaW4sc3RyaW5nIGVycm9yKQorICAgIHNpZ25hbCBjb21wdXRlckFkZENvbXBs
ZXRlZChib29sIHN1Y2Nlc3MsYm9vbCBibG9ja2VkKQorICAgIGZ1bmN0aW9uIGdldENvbm5lY3Rl
ZEdhbWVwYWRzKCl7cmV0dXJuIDB9CisgICAgZnVuY3Rpb24gYWN0aXZhdGVkKCl7fQorICAgIGZ1
bmN0aW9uIGZvY3VzTW92ZWQoKXt9CisgICAgZnVuY3Rpb24gYmFjaygpe30KKyAgICBmdW5jdGlv
biBzdGFydFBvbGxpbmcoKXt9CisgICAgZnVuY3Rpb24gc3RvcFBvbGxpbmcoKXt9CisgICAgZnVu
Y3Rpb24gb3BlblVybCh1cmwpe30KKyAgICBmdW5jdGlvbiBoYXNQcm9maWxlKGhvc3QsYXBwKXty
ZXR1cm4gZmFsc2V9CisgICAgZnVuY3Rpb24gcHJvZmlsZVN1bW1hcnkoaG9zdCxhcHApe3JldHVy
biAiIn0KK30KZGlmZiAtLWdpdCBhL2FwcC9tb29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24u
Y3BwIGIvYXBwL21vb25saWdodG9zL3Rlc3RzL3Rlc3QtY3JpbXNvbi5jcHAKbmV3IGZpbGUgbW9k
ZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uNzUzZGM2MAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9t
b29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24uY3BwCkBAIC0wLDAgKzEsNTAxIEBACisjaW5j
bHVkZSA8UXRUZXN0PgorI2luY2x1ZGUgPFFUZW1wb3JhcnlEaXI+CisjaW5jbHVkZSA8UVFtbEVu
Z2luZT4KKyNpbmNsdWRlIDxRUW1sQ29tcG9uZW50PgorI2luY2x1ZGUgPFFRbWxDb250ZXh0Pgor
I2luY2x1ZGUgPFFRdWlja1N0eWxlPgorI2luY2x1ZGUgPFFRdWlja1dpbmRvdz4KKyNpbmNsdWRl
IDxRUXVpY2tJdGVtPgorI2luY2x1ZGUgPFFGaWxlPgorI2luY2x1ZGUgPFFJbWFnZVJlYWRlcj4K
KyNpbmNsdWRlIDxRVGNwU2VydmVyPgorI2luY2x1ZGUgPFFTc2xTb2NrZXQ+CisjaW5jbHVkZSA8
UVNzbEtleT4KKyNpbmNsdWRlIDxRU3NsQ2VydGlmaWNhdGU+CisjaW5jbHVkZSA8UUNyeXB0b2dy
YXBoaWNIYXNoPgorI2luY2x1ZGUgPG1lbW9yeT4KKyNpbmNsdWRlIDxRU3RhbmRhcmRQYXRocz4K
KyNpbmNsdWRlIDxRRGlyPgorI2luY2x1ZGUgPFFGaWxlSW5mbz4KKyNpbmNsdWRlIDxRTWV0YVBy
b3BlcnR5PgorI2luY2x1ZGUgIi4uL2NyaW1zb25zdGF0dXMuaCIKKyNpbmNsdWRlICIuLi9zeXN0
ZW1jb250cm9scy5oIgorI2luY2x1ZGUgIi4uL2VjbGlwc2Vwcm9maWxlcy5oIgorI2luY2x1ZGUg
Ii4uL2xvY2FsaGFyZHdhcmUuaCIKKyNpbmNsdWRlICIuLi9vdmVybGF5c3R5bGUuaCIKKyNpbmNs
dWRlICIuLi9jcmltc29uZ3JhcGhzLmgiCisjaW5jbHVkZSAidWltb2RlbHMuaCIKKyNpbmNsdWRl
ICIuLi8uLi9iYWNrZW5kL2F1dG91cGRhdGVjaGVja2VyLmgiCisKK2NsYXNzIFRsc0ZpeHR1cmUg
OiBwdWJsaWMgUVRjcFNlcnZlciB7CitwdWJsaWM6CisgICAgUUJ5dGVBcnJheSBib2R5ID0gUiIo
eyJjcHVfcGVyY2VudCI6MzcuNSwicmFtX3VzZWRfYnl0ZXMiOjUwLCJyYW1fdG90YWxfYnl0ZXMi
OjEwMH0pIjsKKyAgICBpbnQgY29kZSA9IDIwMCwgcmVxdWVzdHMgPSAwOworICAgIGJvb2wgcmVz
cG9uZCA9IHRydWU7CisgICAgUUJ5dGVBcnJheSBhdXRob3JpemF0aW9uOworICAgIFFTc2xDZXJ0
aWZpY2F0ZSBjZXJ0OworICAgIFFTc2xLZXkga2V5OworICAgIFRsc0ZpeHR1cmUoKSB7CisgICAg
ICAgIFFGaWxlIGMocUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fVEVTVF9DRVJUIikpOyBj
Lm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGNlcnQgPSBRU3NsQ2VydGlmaWNhdGUoYy5yZWFk
QWxsKCkpOworICAgICAgICBRRmlsZSBrKHFFbnZpcm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1RF
U1RfS0VZIikpOyBrLm9wZW4oUUlPRGV2aWNlOjpSZWFkT25seSk7IGtleSA9IFFTc2xLZXkoay5y
ZWFkQWxsKCksIFFTc2w6OlJzYSk7CisgICAgICAgIGxpc3RlbihRSG9zdEFkZHJlc3M6OkxvY2Fs
SG9zdCk7CisgICAgfQorICAgIHZvaWQgaW5jb21pbmdDb25uZWN0aW9uKHFpbnRwdHIgZGVzY3Jp
cHRvcikgb3ZlcnJpZGUgeworICAgICAgICBhdXRvIHNvY2tldCA9IG5ldyBRU3NsU29ja2V0KHRo
aXMpOworICAgICAgICBzb2NrZXQtPnNldExvY2FsQ2VydGlmaWNhdGUoY2VydCk7IHNvY2tldC0+
c2V0UHJpdmF0ZUtleShrZXkpOyBzb2NrZXQtPnNldFBlZXJWZXJpZnlNb2RlKFFTc2xTb2NrZXQ6
OlZlcmlmeU5vbmUpOworICAgICAgICBzb2NrZXQtPnNldFNvY2tldERlc2NyaXB0b3IoZGVzY3Jp
cHRvcik7CisgICAgICAgIGF1dG8gaW5wdXQgPSBzdGQ6Om1ha2Vfc2hhcmVkPFFCeXRlQXJyYXk+
KCk7CisgICAgICAgIGNvbm5lY3Qoc29ja2V0LCAmUVNzbFNvY2tldDo6cmVhZHlSZWFkLCB0aGlz
LCBbdGhpcywgc29ja2V0LCBpbnB1dF0geworICAgICAgICAgICAgaW5wdXQtPmFwcGVuZChzb2Nr
ZXQtPnJlYWRBbGwoKSk7CisgICAgICAgICAgICBpZiAoIWlucHV0LT5jb250YWlucygiXHJcblxy
XG4iKSkgcmV0dXJuOworICAgICAgICAgICAgKytyZXF1ZXN0czsgYXV0aG9yaXphdGlvbiA9ICpp
bnB1dDsKKyAgICAgICAgICAgIGlmIChyZXNwb25kKSB7CisgICAgICAgICAgICAgICAgUUJ5dGVB
cnJheSBoZWFkZXIgPSAiSFRUUC8xLjEgIiArIFFCeXRlQXJyYXk6Om51bWJlcihjb2RlKSArICIg
Rml4dHVyZVxyXG5Db250ZW50LVR5cGU6IGFwcGxpY2F0aW9uL2pzb25cclxuQ29ubmVjdGlvbjog
Y2xvc2VcclxuQ29udGVudC1MZW5ndGg6ICIgKyBRQnl0ZUFycmF5OjpudW1iZXIoYm9keS5zaXpl
KCkpICsgIlxyXG4iOworICAgICAgICAgICAgICAgIGlmIChjb2RlID09IDMwMikgaGVhZGVyICs9
ICJMb2NhdGlvbjogaHR0cHM6Ly8xMjcuMC4wLjI6MTIzNDUvXHJcbiI7CisgICAgICAgICAgICAg
ICAgc29ja2V0LT53cml0ZShoZWFkZXIgKyAiXHJcbiIgKyBib2R5KTsgc29ja2V0LT5kaXNjb25u
ZWN0RnJvbUhvc3QoKTsKKyAgICAgICAgICAgIH0KKyAgICAgICAgICAgIGlucHV0LT5jbGVhcigp
OworICAgICAgICB9KTsKKyAgICAgICAgY29ubmVjdChzb2NrZXQsICZRU3NsU29ja2V0OjpkaXNj
b25uZWN0ZWQsIHNvY2tldCwgJlFPYmplY3Q6OmRlbGV0ZUxhdGVyKTsKKyAgICAgICAgc29ja2V0
LT5zdGFydFNlcnZlckVuY3J5cHRpb24oKTsKKyAgICB9Cit9OworCitjbGFzcyBDcmltc29uVGVz
dCA6IHB1YmxpYyBRT2JqZWN0IHsKKyAgICBRX09CSkVDVAorcHJpdmF0ZSBzbG90czoKKyAgICB2
b2lkIGluaXRUZXN0Q2FzZSgpIHsKKyAgICAgICAgUUNvcmVBcHBsaWNhdGlvbjo6c2V0T3JnYW5p
emF0aW9uTmFtZSgiRWNsaXBzZU9TIFRlc3QiKTsKKyAgICAgICAgUUNvcmVBcHBsaWNhdGlvbjo6
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
KCJFY2xpcHNlT1MgY3VzdG9taXplZCIpKTsKKyAgICAgICAgUVZFUklGWShmLm9wZW4oUUlPRGV2
aWNlOjpSZWFkT25seSkpOyBRQ09NUEFSRShmLnJlYWRBbGwoKSwgUUJ5dGVBcnJheSgiY3VzdG9t
aXplZCBjbGllbnQiKSk7IGYuY2xvc2UoKTsKKyAgICAgICAgUUNPTVBBUkUoUURpcihkaXIucGF0
aCgpKS5lbnRyeUxpc3QoUURpcjo6RmlsZXMpLCBRU3RyaW5nTGlzdHsiY3VzdG9tLkFwcEltYWdl
In0pOworICAgICAgICBpZiAoaGFkKSBxcHV0ZW52KCJBUFBJTUFHRSIsIG9sZCk7IGVsc2UgcXVu
c2V0ZW52KCJBUFBJTUFHRSIpOworICAgICAgICBRQ09NUEFSRShBdXRvVXBkYXRlQ2hlY2tlcjo6
Y29tcGFyZVNlbWFudGljVmVyc2lvbnMoIjAuNS4wIiwgIjAuNC45IiksIDEpOworICAgIH0KKyAg
ICB2b2lkIGVuZHBvaW50VmFsaWRhdGlvbigpIHsKKyAgICAgICAgUVZFUklGWShDcmltc29uU3Rh
dHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovLzE5Mi4xNjguMS4xMDo0Nzk5MCIpKTsKKyAgICAg
ICAgUVZFUklGWShDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBvaW50KCJodHRwczovL1tmZDAwOjox
XTo0Nzk5MC8iKSk7CisgICAgICAgIGZvciAoYXV0byBiYWQgOiB7Imh0dHA6Ly9ob3N0IiwgImh0
dHBzOi8vdXNlcjpzZWNyZXRAaG9zdCIsICJodHRwczovL2hvc3QvYXBpIiwgImh0dHBzOi8vaG9z
dC8/dG9rZW49c2VjcmV0IiwgImZpbGU6Ly8vZXRjL3Bhc3N3ZCIsICJodHRwczovL2hvc3QvI2Zy
YWdtZW50In0pCisgICAgICAgICAgICBRVkVSSUZZKCFDcmltc29uU3RhdHVzOjp2YWxpZEVuZHBv
aW50KGJhZCkpOworICAgIH0KKyAgICB2b2lkIG1pc3NpbmdBbmRJbnZhbGlkTWV0cmljcygpIHsK
KyAgICAgICAgUVN0cmluZyBlcnJvcjsKKyAgICAgICAgUVZFUklGWShDcmltc29uU3RhdHVzOjpw
YXJzZVN0YXRzKCJub3QganNvbiIsICZlcnJvcikuaXNFbXB0eSgpKTsgUVZFUklGWSghZXJyb3Iu
aXNFbXB0eSgpKTsKKyAgICAgICAgYXV0byBzID0gQ3JpbXNvblN0YXR1czo6cGFyc2VTdGF0cyhS
Iih7ImNwdV9wZXJjZW50Ijo0Mi41LCJjcHVfdGVtcF9jIjotMSwiZ3B1X3BlcmNlbnQiOm51bGws
InJhbV90b3RhbF9ieXRlcyI6MCwicmFtX3BlcmNlbnQiOjAsInZyYW1fdG90YWxfYnl0ZXMiOjEw
MCwidnJhbV91c2VkX2J5dGVzIjoxMjB9KSIsICZlcnJvcik7CisgICAgICAgIFFWRVJJRlkoZXJy
b3IuaXNFbXB0eSgpKTsgUUNPTVBBUkUocy52YWx1ZSgiY3B1X3BlcmNlbnQiKS50b0RvdWJsZSgp
LCA0Mi41KTsKKyAgICAgICAgUVZFUklGWSghcy5jb250YWlucygiY3B1X3RlbXBfYyIpKTsgUVZF
UklGWSghcy5jb250YWlucygiZ3B1X3BlcmNlbnQiKSk7IFFWRVJJRlkoIXMuY29udGFpbnMoInJh
bV9wZXJjZW50IikpOworICAgICAgICBRQ09NUEFSRShzLnZhbHVlKCJ2cmFtX3BlcmNlbnQiKS50
b0RvdWJsZSgpLCAxMDAuMCk7CisgICAgICAgIGF1dG8gaW52YWxpZCA9IENyaW1zb25TdGF0dXM6
OnBhcnNlU3RhdHMoUiIoeyJjcHVfcGVyY2VudCI6MTAxLCJncHVfcGVyY2VudCI6IjAifSkiLCAm
ZXJyb3IpOworICAgICAgICBRVkVSSUZZKGludmFsaWQuaXNFbXB0eSgpKTsgUVZFUklGWShlcnJv
ci5pc0VtcHR5KCkpOworICAgICAgICBDcmltc29uU3RhdHVzOjpwYXJzZVN0YXRzKFFCeXRlQXJy
YXkoNjU1MzcsICdhJyksICZlcnJvcik7IFFWRVJJRlkoIWVycm9yLmlzRW1wdHkoKSk7CisgICAg
ICAgIENyaW1zb25TdGF0dXM6OnBhcnNlU3RhdHMoUiIoeyJlcnJvciI6InVuc3VwcG9ydGVkIn0p
IiwgJmVycm9yKTsgUVZFUklGWSghZXJyb3IuaXNFbXB0eSgpKTsKKyAgICB9CisgICAgdm9pZCBs
b2NhbEhhcmR3YXJlRml4dHVyZSgpIHsKKyAgICAgICAgUVRlbXBvcmFyeURpciB0ZW1wOyBRVkVS
SUZZKHRlbXAuaXNWYWxpZCgpKTsKKyAgICAgICAgYXV0byB3cml0ZSA9IFsmXShRU3RyaW5nIHAs
IFFCeXRlQXJyYXkgdmFsdWUpIHsgUURpcigpLm1rcGF0aChRRmlsZUluZm8odGVtcC5wYXRoKCkr
cCkuYWJzb2x1dGVQYXRoKCkpOyBRRmlsZSBmKHRlbXAucGF0aCgpK3ApOyBRVkVSSUZZKGYub3Bl
bihRSU9EZXZpY2U6OldyaXRlT25seSkpOyBmLndyaXRlKHZhbHVlKTsgfTsKKyAgICAgICAgd3Jp
dGUoIi9jbGFzcy9wb3dlcl9zdXBwbHkvQkFUMC90eXBlIiwgIkJhdHRlcnkiKTsgd3JpdGUoIi9j
bGFzcy9wb3dlcl9zdXBwbHkvQkFUMC9jYXBhY2l0eSIsICI3MyIpOyB3cml0ZSgiL2NsYXNzL3Bv
d2VyX3N1cHBseS9CQVQwL3N0YXR1cyIsICJDaGFyZ2luZyIpOworICAgICAgICB3cml0ZSgiL2Ns
YXNzL25ldC93bGFuMC9vcGVyc3RhdGUiLCAidXAiKTsgd3JpdGUoIi9jbGFzcy9uZXQvbG8vb3Bl
cnN0YXRlIiwgInVwIik7CisgICAgICAgIGF1dG8gbG9jYWwgPSBDcmltc29uU3RhdHVzOjpyZWFk
TG9jYWwodGVtcC5wYXRoKCkpOyBRQ09NUEFSRShsb2NhbC52YWx1ZSgiYmF0dGVyeVBlcmNlbnQi
KS50b0ludCgpLCA3Myk7IFFDT01QQVJFKGxvY2FsLnZhbHVlKCJiYXR0ZXJ5U3RhdGUiKS50b1N0
cmluZygpLCBRU3RyaW5nKCJDaGFyZ2luZyIpKTsKKyAgICAgICAgUUNPTVBBUkUobG9jYWwudmFs
dWUoIm5ldHdvcmsiKS50b1N0cmluZygpLCBRU3RyaW5nKCJ3bGFuMCIpKTsgUVZFUklGWShsb2Nh
bC52YWx1ZSgiY29ubmVjdGVkIikudG9Cb29sKCkpOworICAgICAgICB3cml0ZSgiL2NsYXNzL3Bv
d2VyX3N1cHBseS9CQVQwL2NhcGFjaXR5IiwgIjEwMSIpOyBRQ09NUEFSRShDcmltc29uU3RhdHVz
OjpyZWFkTG9jYWwodGVtcC5wYXRoKCkpLnZhbHVlKCJiYXR0ZXJ5UGVyY2VudCIpLnRvSW50KCks
IC0xKTsKKyAgICB9CisgICAgdm9pZCBwcml2YXRlU2V0dGluZ3NBbmROb0Nyb3NzSG9zdENyZWRl
bnRpYWxzKCkgeworICAgICAgICBRU3RhbmRhcmRQYXRoczo6c2V0VGVzdE1vZGVFbmFibGVkKHRy
dWUpOworICAgICAgICBDcmltc29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVjdEhvc3QoInRl
c3QtYSIsICJodHRwczovLzEyNy4wLjAuMTo0Nzk5MCIpOworICAgICAgICBRVkVSSUZZKHN0YXR1
cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4xOjQ3OTkwIiwgImZpeHR1cmUtdG9rZW4iLCAi
IikpOyBRVkVSSUZZKHN0YXR1cy5jb25maWd1cmVkKCkpOworICAgICAgICBhdXRvIHBhdGggPSBR
U3RhbmRhcmRQYXRoczo6d3JpdGFibGVMb2NhdGlvbihRU3RhbmRhcmRQYXRoczo6QXBwQ29uZmln
TG9jYXRpb24pICsgIi9jcmltc29uLWhvc3RzLmpzb24iOworICAgICAgICBRVkVSSUZZKChRRmls
ZTo6cGVybWlzc2lvbnMocGF0aCkgJiAoUUZpbGVEZXZpY2U6OlJlYWRHcm91cCB8IFFGaWxlRGV2
aWNlOjpSZWFkT3RoZXIgfCBRRmlsZURldmljZTo6V3JpdGVHcm91cCB8IFFGaWxlRGV2aWNlOjpX
cml0ZU90aGVyKSkgPT0gMCk7CisgICAgICAgIHN0YXR1cy5zZWxlY3RIb3N0KCJ0ZXN0LWIiLCAi
aHR0cHM6Ly8xMjcuMC4wLjI6NDc5OTAiKTsgUVZFUklGWSghc3RhdHVzLmNvbmZpZ3VyZWQoKSk7
CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4yOjQ3
OTkwIiwgIiIsICIiKSk7CisgICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBz
Oi8vMTI3LjAuMC4yOjQ3OTkwIiwgImZpeHR1cmUtdG9rZW4iLCAiaW52YWxpZC1waW4iKSk7Cisg
ICAgICAgIFFWRVJJRlkoIXN0YXR1cy5jb25maWd1cmUoImh0dHBzOi8vMTI3LjAuMC4yOjQ3OTkw
IiwgInRva2VuXG5pbmplY3Rpb24iLCAiIikpOworICAgICAgICBRRmlsZTo6cmVtb3ZlKHBhdGgp
OworICAgIH0KKyAgICB2b2lkIHRsc0F1dGhlbnRpY2F0aW9uQW5kVmlzaWJpbGl0eSgpIHsKKyAg
ICAgICAgVGxzRml4dHVyZSBzZXJ2ZXI7IFFWRVJJRlkoc2VydmVyLmlzTGlzdGVuaW5nKCkpOyBR
VkVSSUZZKCFzZXJ2ZXIuY2VydC5pc051bGwoKSk7CisgICAgICAgIFFTdHJpbmcgdXJsID0gImh0
dHBzOi8vMTI3LjAuMC4xOiIgKyBRU3RyaW5nOjpudW1iZXIoc2VydmVyLnNlcnZlclBvcnQoKSk7
CisgICAgICAgIFFTdHJpbmcgcGluID0gUVN0cmluZzo6ZnJvbUxhdGluMShzZXJ2ZXIuY2VydC5k
aWdlc3QoUUNyeXB0b2dyYXBoaWNIYXNoOjpTaGEyNTYpLnRvSGV4KCkpOworICAgICAgICBDcmlt
c29uU3RhdHVzIHN0YXR1czsgc3RhdHVzLnNlbGVjdEhvc3QoImZpeHR1cmUtdGxzIiwgdXJsKTsK
KyAgICAgICAgUVZFUklGWShzdGF0dXMuY29uZmlndXJlKHVybCwgImZpeHR1cmUtb25seS10b2tl
biIsICIiKSk7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOworICAgICAgICBRVFJZX1ZFUklGWV9X
SVRIX1RJTUVPVVQoc3RhdHVzLnN0YXR1cygpLmNvbnRhaW5zKCJmaW5nZXJwcmludCIpLCA1MDAw
KTsKKyAgICAgICAgUUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCAwKTsgLy8gbm8gY3JlZGVudGlh
bHMgc2VudCBiZWZvcmUgdHJ1c3Rpbmcgc2VsZi1zaWduZWQgVExTCisgICAgICAgIFFWRVJJRlko
c3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJmaXh0dXJlLW9ubHktdG9rZW4iLCBwaW4pKTsKKyAgICAg
ICAgUVRSWV9DT01QQVJFX1dJVEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS52YWx1ZSgiY3B1X3Bl
cmNlbnQiKS50b0RvdWJsZSgpLCAzNy41LCA1MDAwKTsKKyAgICAgICAgUVZFUklGWShzZXJ2ZXIu
YXV0aG9yaXphdGlvbi5jb250YWlucygiQXV0aG9yaXphdGlvbjogQmVhcmVyIGZpeHR1cmUtb25s
eS10b2tlbiIpKTsKKyAgICAgICAgUVZFUklGWShzZXJ2ZXIuYXV0aG9yaXphdGlvbi5zdGFydHNX
aXRoKCJHRVQgL2FwaS9ob3N0L3N0YXRzICIpKTsKKyAgICAgICAgc3RhdHVzLnNldFZpc2libGUo
ZmFsc2UpOyBpbnQgY291bnQgPSBzZXJ2ZXIucmVxdWVzdHM7IFFUZXN0OjpxV2FpdCgyMTAwKTsg
UUNPTVBBUkUoc2VydmVyLnJlcXVlc3RzLCBjb3VudCk7CisgICAgICAgIGZvciAoaW50IGNvZGUg
OiB7NDAxLCA0MDMsIDQwNCwgMzAyfSkgeworICAgICAgICAgICAgc2VydmVyLmNvZGUgPSBjb2Rl
OyBpbnQgcHJpb3IgPSBzZXJ2ZXIucmVxdWVzdHM7IHN0YXR1cy5zZXRWaXNpYmxlKHRydWUpOwor
ICAgICAgICAgICAgUVRSWV9WRVJJRllfV0lUSF9USU1FT1VUKHNlcnZlci5yZXF1ZXN0cyA+IHBy
aW9yLCA1MDAwKTsKKyAgICAgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9VVChzdGF0dXMu
c3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOworICAgICAgICAgICAgc3RhdHVzLnNldFZpc2libGUo
ZmFsc2UpOworICAgICAgICB9CisgICAgICAgIHNlcnZlci5jb2RlID0gMjAwOyBzZXJ2ZXIuYm9k
eSA9IFFCeXRlQXJyYXkoNzAwMDAsICdhJyk7IGludCBwcmlvciA9IHNlcnZlci5yZXF1ZXN0czsg
c3RhdHVzLnNldFZpc2libGUodHJ1ZSk7CisgICAgICAgIFFUUllfVkVSSUZZX1dJVEhfVElNRU9V
VChzZXJ2ZXIucmVxdWVzdHMgPiBwcmlvciwgNTAwMCk7CisgICAgICAgIFFUUllfVkVSSUZZX1dJ
VEhfVElNRU9VVChzdGF0dXMuc3RhdHMoKS5pc0VtcHR5KCksIDUwMDApOyBzdGF0dXMuc2V0Vmlz
aWJsZShmYWxzZSk7CisgICAgICAgIFFWRVJJRlkoc3RhdHVzLmNvbmZpZ3VyZSh1cmwsICJmaXh0
dXJlLW9ubHktdG9rZW4iLCBRU3RyaW5nKDY0LCAnMCcpKSk7IHN0YXR1cy5zZXRWaXNpYmxlKHRy
dWUpOworICAgICAgICBjb3VudCA9IHNlcnZlci5yZXF1ZXN0czsgUVRlc3Q6OnFXYWl0KDUwMCk7
IFFDT01QQVJFKHNlcnZlci5yZXF1ZXN0cywgY291bnQpOyBRVkVSSUZZKHN0YXR1cy5zdGF0cygp
LmlzRW1wdHkoKSk7CisgICAgICAgIHN0YXR1cy5zZXRWaXNpYmxlKGZhbHNlKTsKKyAgICB9Cisg
ICAgdm9pZCByb3VuZGVkT3ZlcmxheUFjY2VudHNBbmRPcGFjaXR5KCkgeworICAgICAgICBmb3Io
aW50IGFjY2VudD0wO2FjY2VudDwxNjsrK2FjY2VudCkgeworICAgICAgICAgICAgYXV0byBpbWFn
ZT1FY2xpcHNlT3ZlcmxheVN0eWxlOjpwYW5lbChRU2l6ZSg0MDAsMTgwKSxhY2NlbnQsODUpOyBR
VkVSSUZZKCFpbWFnZS5pc051bGwoKSk7CisgICAgICAgICAgICBRQ09NUEFSRShpbWFnZS5waXhl
bENvbG9yKDAsMCkuYWxwaGEoKSwwKTsKKyAgICAgICAgICAgIFFDT01QQVJFKGltYWdlLnBpeGVs
Q29sb3IoMjAwLDkwKS5hbHBoYSgpLDg1KjI1NS8xMDApOworICAgICAgICAgICAgUUNPTVBBUkUo
aW1hZ2UucGl4ZWxDb2xvcigyMDAsOCkucmdiKCksRWNsaXBzZU92ZXJsYXlTdHlsZTo6YWNjZW50
KGFjY2VudCkucmdiKCkpOworICAgICAgICB9CisgICAgICAgIFFWRVJJRlkoRWNsaXBzZU92ZXJs
YXlTdHlsZTo6cGFuZWwoUVNpemUoLTEsMTAwKSwwLDg1KS5pc051bGwoKSk7CisgICAgICAgIFFW
RVJJRlkoRWNsaXBzZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNpemUoNDA5NiwxMDApLDAsODUpLmlz
TnVsbCgpKTsKKyAgICB9CisgICAgdm9pZCBncmFwaFNhbXBsZXNQcmVzZXJ2ZU1pc3NpbmdBbmRX
aW5kb3coKSB7CisgICAgICAgIGF1dG8gdmFsdWVzPUNyaW1zb25HcmFwaHM6OnZhbHVlcygiVmlk
ZW8gc3RyZWFtOiAxOTIweDEwODAgMTIwLjAwIEZQU1xuUmVuZGVyaW5nIGZyYW1lIHJhdGU6IDU5
LjI1IEZQU1xuQXZlcmFnZSBuZXR3b3JrIGxhdGVuY3k6IDEyIG1zIixmYWxzZSx7eyJjcHVQZXJj
ZW50IiwyNS4wfSx7Im1lbW9yeVVzZWRHaUIiLDQuNX19KTsKKyAgICAgICAgUUNPTVBBUkUodmFs
dWVzWyJGUFMiXSw1OS4yNSk7UUNPTVBBUkUodmFsdWVzWyJOZXR3b3JrIGxhdGVuY3kiXSwxMi4w
KTtRQ09NUEFSRSh2YWx1ZXNbIkxvY2FsIENQVSJdLDI1LjApOworICAgICAgICBhdXRvIGNvbXBh
Y3Q9Q3JpbXNvbkdyYXBoczo6dmFsdWVzKCI2MCBmcHMgwrcgMTkyMHgxMDgwIEgyNjQgwrcgbmV0
IDcgbXMgwrcgZGVjIDIuMCBtcyIsZmFsc2Use30pOworICAgICAgICBRQ09NUEFSRShjb21wYWN0
WyJGUFMiXSw2MC4wKTtRQ09NUEFSRShjb21wYWN0WyJOZXR3b3JrIGxhdGVuY3kiXSw3LjApO1FW
RVJJRlkocUlzTmFOKGNvbXBhY3RbIkxvY2FsIFJBTSJdKSk7CisgICAgICAgIGF1dG8gdW5hdmFp
bGFibGU9Q3JpbXNvbkdyYXBoczo6dmFsdWVzKCJBdmVyYWdlIG5ldHdvcmsgbGF0ZW5jeTogTi9B
XG5WaWRlbyBzdHJlYW06IDE5MjB4MTA4MCAxMjAuMDAgRlBTIixmYWxzZSx7fSk7CisgICAgICAg
IFFWRVJJRlkocUlzTmFOKHVuYXZhaWxhYmxlWyJGUFMiXSkpO1FWRVJJRlkocUlzTmFOKHVuYXZh
aWxhYmxlWyJOZXR3b3JrIGxhdGVuY3kiXSkpOworICAgICAgICBhdXRvIGludmFsaWQ9Q3JpbXNv
bkdyYXBoczo6dmFsdWVzKCIiLHRydWUse3siY3B1UGVyY2VudCIsUVZhcmlhbnQoKX0seyJtZW1v
cnlVc2VkR2lCIiwiaW52YWxpZCJ9LHsidGVtcGVyYXR1cmVDIiwtMX0seyJyZWNlaXZlTWlCIiww
LjB9fSk7CisgICAgICAgIFFWRVJJRlkocUlzTmFOKGludmFsaWRbIkxvY2FsIENQVSJdKSk7UVZF
UklGWShxSXNOYU4oaW52YWxpZFsiTG9jYWwgUkFNIl0pKTtRVkVSSUZZKHFJc05hTihpbnZhbGlk
WyJUZW1wZXJhdHVyZSJdKSk7UUNPTVBBUkUoaW52YWxpZFsiRG93bmxvYWQiXSwwLjApOworICAg
ICAgICBDcmltc29uR3JhcGhzOjpIaXN0b3J5IGhpc3Rvcnk7Zm9yKGludCBpPTA7aTw4MDtpKysp
Q3JpbXNvbkdyYXBoczo6cHVzaChoaXN0b3J5LHZhbHVlcyk7CisgICAgICAgIFFDT01QQVJFKGhp
c3RvcnlbIkZQUyJdLnNpemUoKSw2MCk7Q3JpbXNvbkdyYXBoczo6cHVzaChoaXN0b3J5LHVuYXZh
aWxhYmxlKTtRVkVSSUZZKHFJc05hTihoaXN0b3J5WyJGUFMiXS5sYXN0KCkpKTsKKyAgICAgICAg
Zm9yKGludCBpPTA7aTw2MDtpKyspe3ZhbHVlc1siRlBTIl09NjArcVNpbihpKjAuNCkqMjt2YWx1
ZXNbIk5ldHdvcmsgbGF0ZW5jeSJdPTEyK3FTaW4oaSowLjMpKjM7dmFsdWVzWyJMb2NhbCBDUFUi
XT0yNStxU2luKGkqMC41KSoxMDt2YWx1ZXNbIkxvY2FsIFJBTSJdPTQuNStxU2luKGkqMC4yKSow
LjI7Q3JpbXNvbkdyYXBoczo6cHVzaChoaXN0b3J5LHZhbHVlcyk7fQorICAgICAgICBRSW1hZ2Ug
aW1hZ2U9RWNsaXBzZU92ZXJsYXlTdHlsZTo6cGFuZWwoUVNpemUoNDgwLDI1MCksNCw4NSk7Q3Jp
bXNvbkdyYXBoczo6cGFpbnQoaW1hZ2UsNDAsMTgsNCxoaXN0b3J5LGZhbHNlKTsKKyAgICAgICAg
e1FQYWludGVyIHBhaW50ZXIoJmltYWdlKTtwYWludGVyLnNldFBlbihRQ29sb3IoIiNFQ0VFRjEi
KSk7cGFpbnRlci5kcmF3VGV4dCgxNiwyOCwiRWNsaXBzZU9TIHwgU1RSRUFNIOKAlCBncmFwaCBm
aXh0dXJlIik7fQorICAgICAgICBRU3RyaW5nIG91dD1xRW52aXJvbm1lbnRWYXJpYWJsZSgiQ1JJ
TVNPTl9TQ1JFRU5TSE9UUyIpO2lmKCFvdXQuaXNFbXB0eSgpKXtRRGlyKCkubWtwYXRoKG91dCk7
UVZFUklGWShpbWFnZS5zYXZlKG91dCsiL2NyaW1zb24tZ2xhc3Mtb3ZlcmxheS5wbmciKSk7fQor
ICAgIH0KKyAgICB2b2lkIGJhY2tncm91bmRTZWxlY3Rpb25BbmRQZXJzaXN0ZW5jZSgpIHsKKyAg
ICAgICAgRWNsaXBzZVByb2ZpbGVzIHByb2ZpbGU7cHJvZmlsZS5yZXNldEJhY2tncm91bmQoKTtR
VGVtcG9yYXJ5RGlyIGZvbGRlcjtRVkVSSUZZKGZvbGRlci5pc1ZhbGlkKCkpOworICAgICAgICBR
SW1hZ2UgaW5wdXQoMzAwMCwxODAwLFFJbWFnZTo6Rm9ybWF0X1JHQjMyKTtpbnB1dC5maWxsKFFD
b2xvcigiIzc3MjIzMyIpKTtRU3RyaW5nIHNvdXJjZT1mb2xkZXIuZmlsZVBhdGgoIndhbGxwYXBl
ci5wbmciKTtRVkVSSUZZKGlucHV0LnNhdmUoc291cmNlKSk7CisgICAgICAgIFFWRVJJRlkoIXBy
b2ZpbGUuY2hvb3NlQmFja2dyb3VuZChRVXJsKCJodHRwczovL2V4YW1wbGUuY29tL3dhbGxwYXBl
ci5wbmciKSkpOworICAgICAgICBRVkVSSUZZKCFwcm9maWxlLmNob29zZUJhY2tncm91bmQoUVVy
bDo6ZnJvbUxvY2FsRmlsZShmb2xkZXIuZmlsZVBhdGgoIm1pc3NpbmcucG5nIikpKSk7CisgICAg
ICAgIFFGaWxlIGludmFsaWQoZm9sZGVyLmZpbGVQYXRoKCJpbnZhbGlkLnBuZyIpKTtRVkVSSUZZ
KGludmFsaWQub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpO2ludmFsaWQud3JpdGUoIm5vdCBh
biBpbWFnZSIpO2ludmFsaWQuY2xvc2UoKTsKKyAgICAgICAgUVZFUklGWSghcHJvZmlsZS5jaG9v
c2VCYWNrZ3JvdW5kKFFVcmw6OmZyb21Mb2NhbEZpbGUoaW52YWxpZC5maWxlTmFtZSgpKSkpOwor
ICAgICAgICBRRmlsZSBvdmVyc2l6ZWQoZm9sZGVyLmZpbGVQYXRoKCJvdmVyc2l6ZWQucG5nIikp
O1FWRVJJRlkob3ZlcnNpemVkLm9wZW4oUUlPRGV2aWNlOjpXcml0ZU9ubHkpKTtRVkVSSUZZKG92
ZXJzaXplZC5yZXNpemUoMzIqMTAyNCoxMDI0KzEpKTtvdmVyc2l6ZWQuY2xvc2UoKTsKKyAgICAg
ICAgUVZFUklGWSghcHJvZmlsZS5jaG9vc2VCYWNrZ3JvdW5kKFFVcmw6OmZyb21Mb2NhbEZpbGUo
b3ZlcnNpemVkLmZpbGVOYW1lKCkpKSk7CisgICAgICAgIFFWRVJJRlkocHJvZmlsZS5jaG9vc2VC
YWNrZ3JvdW5kKFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNlKSkpO1FWRVJJRlkocHJvZmlsZS5i
YWNrZ3JvdW5kKCkuaXNMb2NhbEZpbGUoKSk7CisgICAgICAgIFFTdHJpbmcgc2F2ZWQ9cHJvZmls
ZS5iYWNrZ3JvdW5kKCkudG9Mb2NhbEZpbGUoKTtRVkVSSUZZKHNhdmVkIT1zb3VyY2UpO1FWRVJJ
RlkoUUZpbGU6OnJlbW92ZShzb3VyY2UpKTtRVkVSSUZZKCFRSW1hZ2Uoc2F2ZWQpLmlzTnVsbCgp
KTtRVkVSSUZZKFFJbWFnZShzYXZlZCkud2lkdGgoKTw9MjU2MCk7CisgICAgICAgIEVjbGlwc2VQ
cm9maWxlcyByZWxvYWRlZDtRQ09NUEFSRShyZWxvYWRlZC5iYWNrZ3JvdW5kKCkscHJvZmlsZS5i
YWNrZ3JvdW5kKCkpO3JlbG9hZGVkLnNldEJhY2tncm91bmREaW0oMCk7UUNPTVBBUkUocmVsb2Fk
ZWQuYmFja2dyb3VuZERpbSgpLDMwKTtyZWxvYWRlZC5zZXRCYWNrZ3JvdW5kRGltKDk5OSk7UUNP
TVBBUkUocmVsb2FkZWQuYmFja2dyb3VuZERpbSgpLDkwKTsKKyAgICAgICAgUVZFUklGWSghcHJv
ZmlsZS5iYWNrZ3JvdW5kRmlsZXMoUVVybCgiaHR0cHM6Ly9leGFtcGxlLmNvbS8iKSkuc2l6ZSgp
KTtwcm9maWxlLnJlc2V0QmFja2dyb3VuZCgpO1FWRVJJRlkocHJvZmlsZS5iYWNrZ3JvdW5kKCku
aXNFbXB0eSgpKTtwcm9maWxlLnNldEJhY2tncm91bmREaW0oNjUpOworICAgIH0KKyAgICB2b2lk
IGhhcmR3YXJlVmlzaWJsZUNvbnN1bWVycygpIHsKKyAgICAgICAgTG9jYWxIYXJkd2FyZSBtb25p
dG9yO21vbml0b3Iuc2V0UmVmcmVzaFNlY29uZHMoMSk7UU9iamVjdCBmaXJzdCxzZWNvbmQ7UVNp
Z25hbFNweSBzYW1wbGVzKCZtb25pdG9yLCZMb2NhbEhhcmR3YXJlOjpjaGFuZ2VkKTsKKyAgICAg
ICAgbW9uaXRvci5zZXRDb25zdW1lckFjdGl2ZSgmZmlyc3QsdHJ1ZSk7UUNPTVBBUkUoc2FtcGxl
cy5jb3VudCgpLDEpOworICAgICAgICBtb25pdG9yLnNldENvbnN1bWVyQWN0aXZlKCZmaXJzdCx0
cnVlKTtRQ09NUEFSRShzYW1wbGVzLmNvdW50KCksMSk7CisgICAgICAgIG1vbml0b3Iuc2V0Q29u
c3VtZXJBY3RpdmUoJnNlY29uZCx0cnVlKTttb25pdG9yLnNldENvbnN1bWVyQWN0aXZlKCZmaXJz
dCxmYWxzZSk7CisgICAgICAgIG1vbml0b3Iuc2V0QWN0aXZlKHRydWUpO21vbml0b3Iuc2V0QWN0
aXZlKGZhbHNlKTsgLy8gbGVnYWN5IGNhbGxlciBtdXN0IG5vdCByZXZva2UgYW5vdGhlciB2aWV3
J3MgbGVhc2UKKyAgICAgICAgUVRlc3Q6OnFXYWl0KDIxMDApO1FWRVJJRlkoc2FtcGxlcy5jb3Vu
dCgpPj0yKTsKKyAgICAgICAgbW9uaXRvci5zZXRDb25zdW1lckFjdGl2ZSgmc2Vjb25kLGZhbHNl
KTtpbnQgY291bnQ9c2FtcGxlcy5jb3VudCgpO1FUZXN0OjpxV2FpdCgyMTAwKTtRQ09NUEFSRShz
YW1wbGVzLmNvdW50KCksY291bnQpOworICAgIH0KKyAgICB2b2lkIGxvY2FsSGFyZHdhcmVDb3Vu
dGVyc0FuZFNlbnNvcnMoKSB7CisgICAgICAgIFFUZW1wb3JhcnlEaXIgcm9vdDsgUVZFUklGWShy
b290LmlzVmFsaWQoKSk7CisgICAgICAgIGF1dG8gd3JpdGU9WyZdKGNvbnN0IFFTdHJpbmcmIHBh
dGgsY29uc3QgUUJ5dGVBcnJheSYgZGF0YSkgeyBRU3RyaW5nIGZ1bGw9cm9vdC5wYXRoKCkrcGF0
aDsgUURpcigpLm1rcGF0aChRRmlsZUluZm8oZnVsbCkuYWJzb2x1dGVQYXRoKCkpOyBRRmlsZSBm
aWxlKGZ1bGwpOyBRVkVSSUZZKGZpbGUub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOyBRQ09N
UEFSRShmaWxlLndyaXRlKGRhdGEpLHFpbnQ2NChkYXRhLnNpemUoKSkpOyB9OworICAgICAgICBR
U2V0dGluZ3MoKS5zZXRWYWx1ZSgiZWNsaXBzZS9oYXJkd2FyZVJlZnJlc2giLDEpOworICAgICAg
ICB3cml0ZSgiL3Byb2Mvc3RhdCIsImNwdSAxMDAgMCAxMDAgODAwIDAgMCAwIDBcbiIpOworICAg
ICAgICB3cml0ZSgiL3Byb2MvbWVtaW5mbyIsIk1lbVRvdGFsOiAxMDQ4NTc2IGtCXG5NZW1BdmFp
bGFibGU6IDI2MjE0NCBrQlxuU3dhcFRvdGFsOiAxMDI0IGtCXG5Td2FwRnJlZTogNTEyIGtCXG4i
KTsKKyAgICAgICAgd3JpdGUoIi9zeXMvY2xhc3MvaHdtb24vaHdtb24wL25hbWUiLCJjb3JldGVt
cCIpOyB3cml0ZSgiL3N5cy9jbGFzcy9od21vbi9od21vbjAvdGVtcDFfaW5wdXQiLCI2MjUwMCIp
OworICAgICAgICB3cml0ZSgiL3N5cy9jbGFzcy9od21vbi9od21vbjAvZmFuMV9pbnB1dCIsIjI0
MDAiKTsKKyAgICAgICAgd3JpdGUoIi9wcm9jL25ldC9yb3V0ZSIsIklmYWNlIERlc3RpbmF0aW9u
IEdhdGV3YXkgRmxhZ3NcbndsYW4wIDAwMDAwMDAwIDAxMDIwMzA0IDAwMDNcbiIpOworICAgICAg
ICB3cml0ZSgiL3Byb2MvbmV0L2RldiIsIndsYW4wOiAxMDAwIDAgMCAwIDAgMCAwIDAgMjAwMCAw
IDAgMCAwIDAgMCAwXG4iKTsKKyAgICAgICAgUUJ5dGVBcnJheSB2aWRlbz0iZHJtLWNsaWVudC1p
ZDogN1xuZHJtLWVuZ2luZS12aWRlbzogMTAwMDAwMDAwIG5zXG4iOworICAgICAgICB3cml0ZSgi
L3Byb2Mvc2VsZi9mZGluZm8vMSIsdmlkZW8pOyB3cml0ZSgiL3Byb2Mvc2VsZi9mZGluZm8vMiIs
dmlkZW8pOworICAgICAgICBhdXRvIGZpcnN0PUxvY2FsSGFyZHdhcmU6OnNhbXBsZShyb290LnBh
dGgoKSk7IFFWRVJJRlkoIWZpcnN0LmNvbnRhaW5zKCJjcHVQZXJjZW50IikpOyBRVkVSSUZZKCFm
aXJzdC5jb250YWlucygidmlkZW9QZXJjZW50IikpOworICAgICAgICBRQ09NUEFSRShmaXJzdFsi
bWVtb3J5UGVyY2VudCJdLnRvRG91YmxlKCksNzUuMCk7IFFDT01QQVJFKGZpcnN0WyJ0ZW1wZXJh
dHVyZUMiXS50b0RvdWJsZSgpLDYyLjUpOyBRQ09NUEFSRShmaXJzdFsiZmFuUlBNIl0udG9Eb3Vi
bGUoKSwyNDAwLjApOworICAgICAgICBRVGVzdDo6cVdhaXQoMTA1MCk7CisgICAgICAgIHdyaXRl
KCIvcHJvYy9zdGF0IiwiY3B1IDE1MCAwIDE1MCA5MDAgMCAwIDAgMFxuIik7CisgICAgICAgIHZp
ZGVvPSJkcm0tY2xpZW50LWlkOiA3XG5kcm0tZW5naW5lLXZpZGVvOiAyMDAwMDAwMDAgbnNcbiI7
CisgICAgICAgIHdyaXRlKCIvcHJvYy9zZWxmL2ZkaW5mby8xIix2aWRlbyk7IHdyaXRlKCIvcHJv
Yy9zZWxmL2ZkaW5mby8yIix2aWRlbyk7CisgICAgICAgIHdyaXRlKCIvcHJvYy9uZXQvZGV2Iiwi
d2xhbjA6IDEwNDk1NzYgMCAwIDAgMCAwIDAgMCA1MjYyODggMCAwIDAgMCAwIDAgMFxuIik7Cisg
ICAgICAgIGF1dG8gc2Vjb25kPUxvY2FsSGFyZHdhcmU6OnNhbXBsZShyb290LnBhdGgoKSk7IFFD
T01QQVJFKHNlY29uZFsiY3B1UGVyY2VudCJdLnRvRG91YmxlKCksNTAuMCk7CisgICAgICAgIFFW
RVJJRlkoc2Vjb25kWyJ2aWRlb1BlcmNlbnQiXS50b0RvdWJsZSgpPjUgJiYgc2Vjb25kWyJ2aWRl
b1BlcmNlbnQiXS50b0RvdWJsZSgpPDExKTsgLy8gZHVwbGljYXRlIGZkIG11c3Qgbm90IGRvdWJs
ZS1jb3VudAorICAgICAgICBRVkVSSUZZKHNlY29uZFsicmVjZWl2ZU1pQiJdLnRvRG91YmxlKCk+
LjUgJiYgc2Vjb25kWyJyZWNlaXZlTWlCIl0udG9Eb3VibGUoKTwxLjEpOworICAgICAgICBRVGVz
dDo6cVdhaXQoMTA1MCk7CisgICAgICAgIHdyaXRlKCIvcHJvYy9zdGF0IiwiY3B1IDEgMCAxIDEg
MCAwIDAgMFxuIik7IHdyaXRlKCIvcHJvYy9uZXQvZGV2Iiwid2xhbjA6IDEgMCAwIDAgMCAwIDAg
MCAxIDAgMCAwIDAgMCAwIDBcbiIpOworICAgICAgICBhdXRvIHJlc2V0PUxvY2FsSGFyZHdhcmU6
OnNhbXBsZShyb290LnBhdGgoKSk7IFFWRVJJRlkoIXJlc2V0LmNvbnRhaW5zKCJjcHVQZXJjZW50
IikpOyBRVkVSSUZZKCFyZXNldC5jb250YWlucygicmVjZWl2ZU1pQiIpKTsKKyAgICAgICAgUVNl
dHRpbmdzKCkuc2V0VmFsdWUoImVjbGlwc2UvaGFyZHdhcmVSZWZyZXNoIiwyKTsKKyAgICB9Cisg
ICAgdm9pZCBsb2NhbEhhcmR3YXJlVW5hdmFpbGFibGVBbmRCb3VuZHMoKSB7CisgICAgICAgIFFU
ZW1wb3JhcnlEaXIgcm9vdDsgUVZFUklGWShyb290LmlzVmFsaWQoKSk7CisgICAgICAgIGF1dG8g
ZW1wdHk9TG9jYWxIYXJkd2FyZTo6c2FtcGxlKHJvb3QucGF0aCgpKTsgUVZFUklGWShlbXB0eS5p
c0VtcHR5KCkpOworICAgICAgICBMb2NhbEhhcmR3YXJlIG1vbml0b3I7IG1vbml0b3Iuc2V0UG9z
aXRpb24oOTk5KTsgUUNPTVBBUkUobW9uaXRvci5wb3NpdGlvbigpLDMpOworICAgICAgICBtb25p
dG9yLnNldE9wYWNpdHkoLTUpOyBRQ09NUEFSRShtb25pdG9yLm9wYWNpdHkoKSw0MCk7CisgICAg
ICAgIG1vbml0b3Iuc2V0UmVmcmVzaFNlY29uZHMoOTk5KTsgUUNPTVBBUkUobW9uaXRvci5yZWZy
ZXNoU2Vjb25kcygpLDUpOworICAgICAgICBtb25pdG9yLnNldEZpZWxkcyh7ImNwdSIsInBhc3N3
b3JkIiwibWVtb3J5In0pOyBRQ09NUEFSRShtb25pdG9yLmZpZWxkcygpLFFTdHJpbmdMaXN0KHsi
Y3B1IiwibWVtb3J5In0pKTsKKyAgICAgICAgbW9uaXRvci5zZXRPdmVybGF5KGZhbHNlKTsgbW9u
aXRvci5zZXRSZWZyZXNoU2Vjb25kcygyKTsgbW9uaXRvci5zZXRPcGFjaXR5KDg1KTsKKyAgICB9
CisgICAgdm9pZCBzY2FuUHJvZ3Jlc3NCZWZvcmVDb21wbGV0aW9uKCkgeworICAgICAgICBRVGVt
cG9yYXJ5RGlyIGRpcjsgUUZpbGUgc2NyaXB0KGRpci5maWxlUGF0aCgic2Nhbi5weSIpKTsgUVZF
UklGWShzY3JpcHQub3BlbihRSU9EZXZpY2U6OldyaXRlT25seSkpOworICAgICAgICBzY3JpcHQu
d3JpdGUoUiJQWShpbXBvcnQganNvbixzeXMsdGltZQorZm9yIGxpbmUgaW4gc3lzLnN0ZGluOgor
ICAgIHJlcXVlc3Q9anNvbi5sb2FkcyhsaW5lKQorICAgIGlmIHJlcXVlc3RbJ2FjdGlvbiddPT0n
YnQtc2Nhbic6CisgICAgICAgIHByaW50KGpzb24uZHVtcHMoeydpdGVtcyc6W3snaWQnOidBQTpC
QjpDQzpERDpFRTpGRicsJ25hbWUnOidDb250cm9sbGVyJ31dLCdzdGF0dXMnOidTY2FubmluZyd9
KSxmbHVzaD1UcnVlKQorICAgICAgICB0aW1lLnNsZWVwKC41KQorICAgIHByaW50KGpzb24uZHVt
cHMoeydpdGVtcyc6W3snaWQnOidBQTpCQjpDQzpERDpFRTpGRicsJ25hbWUnOidDb250cm9sbGVy
J31dLCdzdGF0dXMnOidSZWFkeScsJ2RvbmUnOlRydWV9KSxmbHVzaD1UcnVlKQorKVBZIik7IHNj
cmlwdC5jbG9zZSgpOyBxcHV0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIsc2NyaXB0
LmZpbGVOYW1lKCkudG9VdGY4KCkpOworICAgICAgICBTeXN0ZW1Db250cm9scyBjOyBjLm9wZW4o
ImJ0Iik7IFFUUllfVkVSSUZZKCFjLmJ1c3koKSAmJiAhYy5pdGVtcygpLmlzRW1wdHkoKSk7Cisg
ICAgICAgIGMucmVxdWVzdCgiYnQtc2NhbiIpOyBRVFJZX0NPTVBBUkUoYy5zdGF0dXMoKSxRU3Ry
aW5nKCJTY2FubmluZyIpKTsgUVZFUklGWShjLmJ1c3koKSk7IFFDT01QQVJFKGMuaXRlbXMoKS5z
aXplKCksMSk7CisgICAgICAgIFFUUllfVkVSSUZZKCFjLmJ1c3koKSk7IGMuY2xvc2UoKTsgcXVu
c2V0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIpOworICAgIH0KKyAgICB2b2lkIGlj
b25SZXNvdXJjZXMoKSB7CisgICAgICAgIGZvciAoY29uc3QgUVN0cmluZyYgbmFtZSA6IHsiZWNs
aXBzZS1pY29uIiwgImVjbGlwc2UtY29udHJvbHMiLCAiZWNsaXBzZS1wb3dlciIsICJjcmltc29u
LW5ldHdvcmsiLCAiY3JpbXNvbi1ibHVldG9vdGgiLCAiY3JpbXNvbi1iYXR0ZXJ5IiwgImNyaW1z
b24taG9zdCIsICJzZXR0aW5ncyJ9KSB7CisgICAgICAgICAgICBjb25zdCBRU3RyaW5nIHBhdGgg
PSAiOi9yZXMvIiArIG5hbWUgKyAiLnN2ZyI7CisgICAgICAgICAgICBRVkVSSUZZMihRRmlsZTo6
ZXhpc3RzKHBhdGgpLCBxUHJpbnRhYmxlKHBhdGgpKTsKKyAgICAgICAgICAgIFFJbWFnZVJlYWRl
ciByZWFkZXIocGF0aCk7CisgICAgICAgICAgICBRVkVSSUZZMighcmVhZGVyLnJlYWQoKS5pc051
bGwoKSwgcVByaW50YWJsZShwYXRoICsgIjogIiArIHJlYWRlci5lcnJvclN0cmluZygpKSk7Cisg
ICAgICAgIH0KKyAgICB9CisgICAgdm9pZCBxbWxQYWxldHRlQW5kUGFuZWxzKCkgeworICAgICAg
ICBRU3RyaW5nIHNvdXJjZSA9IHFFbnZpcm9ubWVudFZhcmlhYmxlKCJWSUJFTUlTX1RFU1RfU09V
UkNFIik7IFFWRVJJRlkoIXNvdXJjZS5pc0VtcHR5KCkpOworICAgICAgICBRUXVpY2tTdHlsZTo6
c2V0U3R5bGUoIk1hdGVyaWFsIik7CisgICAgICAgIHFtbFJlZ2lzdGVyU2luZ2xldG9uVHlwZShR
VXJsOjpmcm9tTG9jYWxGaWxlKHNvdXJjZSArICIvYXBwL21vb25saWdodG9zL3Rlc3RzL1ByZWZl
cmVuY2VzLnFtbCIpLCAiU3RyZWFtaW5nUHJlZmVyZW5jZXMiLCAxLCAwLCAiU3RyZWFtaW5nUHJl
ZmVyZW5jZXMiKTsKKyAgICAgICAgcW1sUmVnaXN0ZXJTaW5nbGV0b25UeXBlKFFVcmw6OmZyb21M
b2NhbEZpbGUoc291cmNlICsgIi9hcHAvZ3VpL1ZiVG9rZW5zLnFtbCIpLCAiVmliZW1pcy5SZWRl
c2lnbiIsIDEsIDAsICJWYlRva2VucyIpOworICAgICAgICBRVGVtcG9yYXJ5RGlyIGNvbnRyb2xz
Rml4dHVyZTsgUVZFUklGWShjb250cm9sc0ZpeHR1cmUuaXNWYWxpZCgpKTsKKyAgICAgICAgUUZp
bGUgaGVscGVyKGNvbnRyb2xzRml4dHVyZS5maWxlUGF0aCgiaGVscGVyLnB5IikpOyBRVkVSSUZZ
KGhlbHBlci5vcGVuKFFJT0RldmljZTo6V3JpdGVPbmx5KSk7CisgICAgICAgIGhlbHBlci53cml0
ZShSIlBZKGltcG9ydCBqc29uLHN5cworZm9yIGxpbmUgaW4gc3lzLnN0ZGluOgorICAgIHZhbHVl
PWpzb24ubG9hZHMobGluZSkKKyAgICBwcmludChqc29uLmR1bXBzKHsnc3RhdGUnOnsndm9sdW1l
Jzo1MCwnbXV0ZWQnOkZhbHNlLCd3aWZpX2VuYWJsZWQnOlRydWUsJ2JsdWV0b290aF9lbmFibGVk
JzpUcnVlLCdkaXNwbGF5cyc6W3snaWQnOidlRFAtMXwxMDI0eDY0MHw2MCcsJ25hbWUnOidlRFAt
MSDCtyAxMDI0w5c2NDAgwrcgNjAgSHonLCdjdXJyZW50JzpUcnVlfV0sJ3BvaW50ZXJzJzpbeydp
ZCc6JzEyJywnbmFtZSc6J1RvdWNocGFkJywnc3BlZWQnOjAsJ25hdHVyYWwnOlRydWUsJ3RhcCc6
VHJ1ZX1dLCdzaW5rcyc6W3snaWQnOic0MicsJ25hbWUnOidTcGVha2VycycsJ2RlZmF1bHQnOlRy
dWV9LHsnaWQnOic1NycsJ25hbWUnOidBaXJQb2RzJywnZGVmYXVsdCc6RmFsc2V9XSwnYnJpZ2h0
bmVzcyc6eydzY3JlZW4nOnsnZGV2aWNlJzonaW50ZWxfYmFja2xpZ2h0JywncGVyY2VudCc6NjB9
LCdrZXlib2FyZCc6eydkZXZpY2UnOidzcGk6OmtiZF9iYWNrbGlnaHQnLCdwZXJjZW50JzozMH19
LCdvcyc6eydOQU1FJzonRWNsaXBzZU9TJywnVkVSU0lPTic6JzAuMy1kZXYnLCdUQVJHRVQnOidG
aXh0dXJlIGhhcmR3YXJlJywnRkVET1JBJzonNDQnfSwna2VybmVsJzonZml4dHVyZS1rZXJuZWwn
fSwnaXRlbXMnOlt7J2lkJzonZml4dHVyZScsJ25hbWUnOidGaXh0dXJlIGRldmljZScsJ2RldGFp
bCc6J0F2YWlsYWJsZScsJ2Nvbm5lY3RlZCc6VHJ1ZX1dLCdzdGF0dXMnOidSZWFkeScsJ2RvbmUn
OlRydWV9KSxmbHVzaD1UcnVlKQorKVBZIik7IGhlbHBlci5jbG9zZSgpOworICAgICAgICBxcHV0
ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIsaGVscGVyLmZpbGVOYW1lKCkudG9VdGY4
KCkpOworICAgICAgICBxbWxSZWdpc3RlclR5cGU8VWlDb21wdXRlck1vZGVsPigiQ29tcHV0ZXJN
b2RlbCIsMSwwLCJDb21wdXRlck1vZGVsIik7CisgICAgICAgIHFtbFJlZ2lzdGVyVHlwZTxVaUFw
cE1vZGVsPigiQXBwTW9kZWwiLDEsMCwiQXBwTW9kZWwiKTsKKyAgICAgICAgcW1sUmVnaXN0ZXJT
aW5nbGV0b25UeXBlKFFVcmw6OmZyb21Mb2NhbEZpbGUoc291cmNlKyIvYXBwL2d1aS9UaGVtZS5x
bWwiKSwiVGhlbWUiLDEsMCwiVGhlbWUiKTsKKyAgICAgICAgZm9yKGNvbnN0IFFTdHJpbmcmIG1v
ZHVsZTpRU3RyaW5nTGlzdHsiQ29tcHV0ZXJNYW5hZ2VyIiwiQXBwUHJvZmlsZU1hbmFnZXIiLCJT
eXN0ZW1Qcm9wZXJ0aWVzIiwiU2RsR2FtZXBhZEtleU5hdmlnYXRpb24iLCJVaVNvdW5kTWFuYWdl
ciIsIlNlcnZlckNvbW1hbmRNYW5hZ2VyIn0pCisgICAgICAgICAgICBxbWxSZWdpc3RlclNpbmds
ZXRvblR5cGUoUVVybDo6ZnJvbUxvY2FsRmlsZShzb3VyY2UrIi9hcHAvbW9vbmxpZ2h0b3MvdGVz
dHMvVWlTZXJ2aWNlcy5xbWwiKSxtb2R1bGUudG9VdGY4KCkuY29uc3REYXRhKCksMSwwLG1vZHVs
ZS50b1V0ZjgoKS5jb25zdERhdGEoKSk7CisgICAgICAgIFFRbWxFbmdpbmUgZW5naW5lOworICAg
ICAgICBRU2lnbmFsU3B5IHFtbFdhcm5pbmdzKCZlbmdpbmUsJlFRbWxFbmdpbmU6Ondhcm5pbmdz
KTsKKyAgICAgICAgUVFtbENvbXBvbmVudCBjb21wb25lbnQoJmVuZ2luZSwgUVVybDo6ZnJvbUxv
Y2FsRmlsZShzb3VyY2UgKyAiL2FwcC9tb29ubGlnaHRvcy90ZXN0cy9IYXJuZXNzLnFtbCIpKTsK
KyAgICAgICAgUVNjb3BlZFBvaW50ZXI8UU9iamVjdD4gcm9vdChjb21wb25lbnQuY3JlYXRlKCkp
OyBRVkVSSUZZMihyb290LCBxUHJpbnRhYmxlKGNvbXBvbmVudC5lcnJvclN0cmluZygpKSk7Cisg
ICAgICAgIGF1dG8gcGFuZWwgPSByb290LT5maW5kQ2hpbGQ8UU9iamVjdCo+KCJ0ZXN0UGFuZWwi
KTsgUVZFUklGWShwYW5lbCk7CisgICAgICAgIGF1dG8gc3RhdGUgPSByb290LT5maW5kQ2hpbGQ8
UU9iamVjdCo+KCJ0ZXN0U3RhdGUiKTsgUVZFUklGWShzdGF0ZSk7CisgICAgICAgIGZvciAoaW50
IGkgPSAwOyBpIDwgMTY7ICsraSkgeworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6
aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCAiY2hvb3NlQWNjZW50IiwgUV9BUkcoUVZhcmlhbnQs
IGkpKSk7CisgICAgICAgICAgICBRQ09NUEFSRShzdGF0ZS0+cHJvcGVydHkoImFjY2VudCIpLnZh
bHVlPFFDb2xvcj4oKS5yZ2IoKSxFY2xpcHNlT3ZlcmxheVN0eWxlOjphY2NlbnQoaSkucmdiKCkp
OworICAgICAgICAgICAgUVZFUklGWShzdGF0ZS0+cHJvcGVydHkoInByZXNzZWQiKS52YWx1ZTxR
Q29sb3I+KCkuaXNWYWxpZCgpKTsKKyAgICAgICAgfQorICAgICAgICBRVkVSSUZZKFFNZXRhT2Jq
ZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksICJjaG9vc2VBY2NlbnQiLCBRX0FSRyhRVmFy
aWFudCwgNCkpKTsKKyAgICAgICAgZm9yIChRU3RyaW5nIGtpbmQgOiB7Im5ldHdvcmsiLCAiYmF0
dGVyeSIsICJob3N0In0pIHsKKyAgICAgICAgICAgIFFWRVJJRlkocGFuZWwtPnNldFByb3BlcnR5
KCJraW5kIiwga2luZCkpOworICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tl
TWV0aG9kKHBhbmVsLCAib3BlbiIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICBR
VkVSSUZZKHBhbmVsLT5wcm9wZXJ0eSgidmlzaWJsZSIpLnRvQm9vbCgpKTsKKyAgICAgICAgICAg
IFFTdHJpbmcgb3V0ID0gcUVudmlyb25tZW50VmFyaWFibGUoIkNSSU1TT05fU0NSRUVOU0hPVFMi
KTsKKyAgICAgICAgICAgIGlmICghb3V0LmlzRW1wdHkoKSkgeworICAgICAgICAgICAgICAgIFFE
aXIoKS5ta3BhdGgob3V0KTsKKyAgICAgICAgICAgICAgICBhdXRvIHdpbmRvdyA9IHFvYmplY3Rf
Y2FzdDxRUXVpY2tXaW5kb3cqPihyb290LmRhdGEoKSk7IFFWRVJJRlkod2luZG93KTsKKyAgICAg
ICAgICAgICAgICBRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0ICsgIi8iICsg
a2luZCArICIucG5nIikpOworICAgICAgICAgICAgfQorICAgICAgICAgICAgUVZFUklGWShRTWV0
YU9iamVjdDo6aW52b2tlTWV0aG9kKHBhbmVsLCAiY2xvc2UiKSk7IFFUZXN0OjpxV2FpdCgzMDAp
OworICAgICAgICB9CisgICAgICAgIGF1dG8gY29ubmVjdGlvbnMgPSByb290LT5maW5kQ2hpbGQ8
UU9iamVjdCo+KCJjb25uZWN0aW9uc1BhbmVsIik7IFFWRVJJRlkoY29ubmVjdGlvbnMpOworICAg
ICAgICBmb3IgKFFTdHJpbmcga2luZCA6IHsid2lmaSIsICJidCJ9KSB7CisgICAgICAgICAgICBy
b290LT5zZXRQcm9wZXJ0eSgid2lkdGgiLCAxMDI0KTsgcm9vdC0+c2V0UHJvcGVydHkoImhlaWdo
dCIsIDY0MCk7CisgICAgICAgICAgICBRVkVSSUZZKGNvbm5lY3Rpb25zLT5zZXRQcm9wZXJ0eSgi
a2luZCIsIGtpbmQpKTsKKyAgICAgICAgICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1l
dGhvZChjb25uZWN0aW9ucywgIm9wZW4iKSk7IFFUZXN0OjpxV2FpdCgzMDApOworICAgICAgICAg
ICAgUVZFUklGWShjb25uZWN0aW9ucy0+cHJvcGVydHkoInZpc2libGUiKS50b0Jvb2woKSk7Cisg
ICAgICAgICAgICBRVkVSSUZZKGNvbm5lY3Rpb25zLT5wcm9wZXJ0eSgid2lkdGgiKS50b0ludCgp
IDw9IDk5Mik7CisgICAgICAgICAgICBRU3RyaW5nIG91dCA9IHFFbnZpcm9ubWVudFZhcmlhYmxl
KCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgICAgICBpZiAoIW91dC5pc0VtcHR5KCkp
IHsKKyAgICAgICAgICAgICAgICBhdXRvIHdpbmRvdyA9IHFvYmplY3RfY2FzdDxRUXVpY2tXaW5k
b3cqPihyb290LmRhdGEoKSk7IFFWRVJJRlkod2luZG93KTsKKyAgICAgICAgICAgICAgICBRVkVS
SUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0ICsgIi8iICsga2luZCArICItc2VsZWN0
b3IucG5nIikpOworICAgICAgICAgICAgfQorICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVj
dDo6aW52b2tlTWV0aG9kKGNvbm5lY3Rpb25zLCAiY2xvc2UiKSk7IFFUZXN0OjpxV2FpdCgzMDAp
OworICAgICAgICB9CisgICAgICAgIGF1dG8gY2xpY2tEaWFsb2dCdXR0b249W10oUU9iamVjdCog
ZGlhbG9nLGNvbnN0IFFTdHJpbmcmIHRleHQpIHsKKyAgICAgICAgICAgIGF1dG8gZm9vdGVyPWRp
YWxvZy0+cHJvcGVydHkoImZvb3RlciIpLnZhbHVlPFFPYmplY3QqPigpOyBpZighZm9vdGVyKSBy
ZXR1cm4gZmFsc2U7CisgICAgICAgICAgICBmb3IoYXV0byBjaGlsZDpmb290ZXItPmZpbmRDaGls
ZHJlbjxRT2JqZWN0Kj4oKSkgaWYoY2hpbGQtPnByb3BlcnR5KCJ0ZXh0IikudG9TdHJpbmcoKT09
dGV4dCAmJiBjaGlsZC0+bWV0YU9iamVjdCgpLT5pbmRleE9mU2lnbmFsKCJjbGlja2VkKCkiKT49
MCkgcmV0dXJuIFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY2hpbGQsImNsaWNrZWQiKTsKKyAg
ICAgICAgICAgIHJldHVybiBmYWxzZTsKKyAgICAgICAgfTsKKyAgICAgICAgUVZFUklGWShRTWV0
YU9iamVjdDo6aW52b2tlTWV0aG9kKGNvbm5lY3Rpb25zLCJvcGVuIikpOyBRVGVzdDo6cVdhaXQo
MzAwKTsKKyAgICAgICAgZm9yKGNvbnN0IFFTdHJpbmcmIG5hbWU6eyJjb25uZWN0aW9uQ3JlZGVu
dGlhbCIsImNvbm5lY3Rpb25Gb3JnZXQifSkgeworICAgICAgICAgICAgYXV0byBkaWFsb2c9cm9v
dC0+ZmluZENoaWxkPFFPYmplY3QqPihuYW1lKTsgUVZFUklGWShkaWFsb2cpOworICAgICAgICAg
ICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKGRpYWxvZywib3BlbiIpKTsgUVRl
c3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICBRVkVSSUZZKGRpYWxvZy0+cHJvcGVydHkoInZp
c2libGUiKS50b0Jvb2woKSk7CisgICAgICAgICAgICBRU3RyaW5nIGRlc3RpbmF0aW9uPXFFbnZp
cm9ubWVudFZhcmlhYmxlKCJDUklNU09OX1NDUkVFTlNIT1RTIik7CisgICAgICAgICAgICBpZigh
ZGVzdGluYXRpb24uaXNFbXB0eSgpKSBRVkVSSUZZKHFvYmplY3RfY2FzdDxRUXVpY2tXaW5kb3cq
Pihyb290LmRhdGEoKSktPmdyYWJXaW5kb3coKS5zYXZlKGRlc3RpbmF0aW9uKyIvIituYW1lKyIu
cG5nIikpOworICAgICAgICAgICAgUVZFUklGWShjbGlja0RpYWxvZ0J1dHRvbihkaWFsb2csbmFt
ZT09ImNvbm5lY3Rpb25DcmVkZW50aWFsIj8iQ2FuY2VsIjoiTm8iKSk7CisgICAgICAgICAgICBR
VGVzdDo6cVdhaXQoNDAwKTsgUVZFUklGWTIoIWRpYWxvZy0+cHJvcGVydHkoInZpc2libGUiKS50
b0Jvb2woKSxxUHJpbnRhYmxlKG5hbWUpKTsKKyAgICAgICAgfQorICAgICAgICBRVkVSSUZZKFFN
ZXRhT2JqZWN0OjppbnZva2VNZXRob2QoY29ubmVjdGlvbnMsImNsb3NlIikpOyBRVGVzdDo6cVdh
aXQoMjAwKTsKKyAgICAgICAgUVFtbENvbXBvbmVudCBhY3Rpb25Db21wb25lbnQoJmVuZ2luZSxR
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
OjpxV2FpdCgzMDApOworICAgICAgICBmb3IoY29uc3QgUVN0cmluZyYgdmlldzpRU3RyaW5nTGlz
dHsiUGNWaWV3IiwiQXBwVmlldyJ9KSB7CisgICAgICAgICAgICBmb3IoaW50IHNjYWxlOnsxMDAs
MTEwLDEyNX0pIHsKKyAgICAgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VN
ZXRob2Qocm9vdC5kYXRhKCksImNob29zZVNjYWxlIixRX0FSRyhRVmFyaWFudCxzY2FsZSkpKTsK
KyAgICAgICAgICAgICAgICBmb3IoUVNpemUgc2l6ZTp7UVNpemUoMTkyMCwxMDgwKSxRU2l6ZSgx
MjgwLDcyMCksUVNpemUoOTAwLDY0MCl9KSB7CisgICAgICAgICAgICAgICAgICAgIHJvb3QtPnNl
dFByb3BlcnR5KCJ3aWR0aCIsc2l6ZS53aWR0aCgpKTtyb290LT5zZXRQcm9wZXJ0eSgiaGVpZ2h0
IixzaXplLmhlaWdodCgpKTsKKyAgICAgICAgICAgICAgICAgICAgUVZFUklGWShRTWV0YU9iamVj
dDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJzaG93UHJvZHVjdGlvblZpZXciLFFfQVJHKFFW
YXJpYW50LHZpZXcpKSk7UVRlc3Q6OnFXYWl0KDMwMCk7CisgICAgICAgICAgICAgICAgICAgIGF1
dG8gc3RhY2s9cm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigicHJvZHVjdGlvblN0YWNrIik7UVZF
UklGWShzdGFjayk7YXV0byBpdGVtPXN0YWNrLT5wcm9wZXJ0eSgiY3VycmVudEl0ZW0iKS52YWx1
ZTxRT2JqZWN0Kj4oKTtRVkVSSUZZKGl0ZW0pOworICAgICAgICAgICAgICAgICAgICBRVkVSSUZZ
KGl0ZW0tPnByb3BlcnR5KCJhdmFpbGFibGVXaWR0aCIpLnRvRG91YmxlKCk+MzAwKTsKKyAgICAg
ICAgICAgICAgICAgICAgUUNPTVBBUkUoaXRlbS0+cHJvcGVydHkoImNvdW50IikudG9JbnQoKSx2
aWV3PT0iUGNWaWV3Ij8yOjYpOworICAgICAgICAgICAgICAgICAgICBhdXRvIGdyaWQ9cW9iamVj
dF9jYXN0PFFRdWlja0l0ZW0qPihpdGVtKTtRVkVSSUZZKGdyaWQpOworICAgICAgICAgICAgICAg
ICAgICBjb25zdCBkb3VibGUgaW5pdGlhbENvbnRlbnRZPWl0ZW0tPnByb3BlcnR5KCJjb250ZW50
WSIpLnRvRG91YmxlKCk7CisgICAgICAgICAgICAgICAgICAgIGF1dG8gY2hyb21lPWl0ZW0tPmZp
bmRDaGlsZDxRUXVpY2tJdGVtKj4oImNyaW1zb25HcmlkSGVhZGVyIik7UVZFUklGWShjaHJvbWUp
OworICAgICAgICAgICAgICAgICAgICBjb25zdCBpbnQgbGVmdD1pdGVtLT5wcm9wZXJ0eSgicmFp
bFNwYWNlIikudG9JbnQoKStpdGVtLT5wcm9wZXJ0eSgiaG9zdFNwYWNlIikudG9JbnQoKStpdGVt
LT5wcm9wZXJ0eSgibWluTWFyZ2luIikudG9JbnQoKTsKKyAgICAgICAgICAgICAgICAgICAgY29u
c3QgaW50IHJpZ2h0PXNpemUud2lkdGgoKS1pdGVtLT5wcm9wZXJ0eSgibG9jYWxTcGFjZSIpLnRv
SW50KCktaXRlbS0+cHJvcGVydHkoIm1pbk1hcmdpbiIpLnRvSW50KCk7CisgICAgICAgICAgICAg
ICAgICAgIGNvbnN0IFFSZWN0IGhlYWRlclJlZ2lvbihsZWZ0LDAscmlnaHQtbGVmdCxpbnQoY2hy
b21lLT5oZWlnaHQoKSkpOworICAgICAgICAgICAgICAgICAgICBjb25zdCBRSW1hZ2UgZml4ZWRI
ZWFkZXI9d2luZG93LT5ncmFiV2luZG93KCkuY29weShoZWFkZXJSZWdpb24pOworICAgICAgICAg
ICAgICAgICAgICBpdGVtLT5zZXRQcm9wZXJ0eSgiY29udGVudFkiLGluaXRpYWxDb250ZW50WStp
dGVtLT5wcm9wZXJ0eSgiY2VsbEhlaWdodCIpLnRvRG91YmxlKCkpO1FUZXN0OjpxV2FpdCgxMDAp
OworICAgICAgICAgICAgICAgICAgICBRQ09NUEFSRSh3aW5kb3ctPmdyYWJXaW5kb3coKS5jb3B5
KGhlYWRlclJlZ2lvbiksZml4ZWRIZWFkZXIpOyAvLyBzY3JvbGxlZCBjYXJkcyBjYW5ub3QgcGFp
bnQgdGhyb3VnaCB0aXRsZSBjaHJvbWUKKyAgICAgICAgICAgICAgICAgICAgaXRlbS0+c2V0UHJv
cGVydHkoImNvbnRlbnRZIixpbml0aWFsQ29udGVudFkpO1FUZXN0OjpxV2FpdCgzMCk7CisgICAg
ICAgICAgICAgICAgICAgIGdyaWQtPmZvcmNlQWN0aXZlRm9jdXMoKTtpdGVtLT5zZXRQcm9wZXJ0
eSgiY3VycmVudEluZGV4IiwwKTsKKyAgICAgICAgICAgICAgICAgICAgUVRlc3Q6OmtleUNsaWNr
KHdpbmRvdyxRdDo6S2V5X1JpZ2h0KTsKKyAgICAgICAgICAgICAgICAgICAgUVZFUklGWShpdGVt
LT5wcm9wZXJ0eSgiY3VycmVudEluZGV4IikudG9JbnQoKT4wKTsKKyAgICAgICAgICAgICAgICAg
ICAgZm9yKGF1dG8gYnV0dG9uOml0ZW0tPmZpbmRDaGlsZHJlbjxRUXVpY2tJdGVtKj4oImNyaW1z
b25SYWlsQnV0dG9uIikpIHsKKyAgICAgICAgICAgICAgICAgICAgICAgIFFWRVJJRlkoYnV0dG9u
LT53aWR0aCgpPj01Nik7YnV0dG9uLT5mb3JjZUFjdGl2ZUZvY3VzKCk7UVZFUklGWShidXR0b24t
Pmhhc0FjdGl2ZUZvY3VzKCkpOworICAgICAgICAgICAgICAgICAgICB9CisgICAgICAgICAgICAg
ICAgICAgIGdyaWQtPmZvcmNlQWN0aXZlRm9jdXMoKTtpdGVtLT5zZXRQcm9wZXJ0eSgiY3VycmVu
dEluZGV4IiwtMSk7CisgICAgICAgICAgICAgICAgICAgIGl0ZW0tPnNldFByb3BlcnR5KCJjb250
ZW50WSIsaW5pdGlhbENvbnRlbnRZKTtRVGVzdDo6cVdhaXQoMzApOworICAgICAgICAgICAgICAg
ICAgICBpZighb3V0LmlzRW1wdHkoKSlRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUo
b3V0KyIvY3JpbXNvbi1nbGFzcy0iK3ZpZXcrIi0iK1FTdHJpbmc6Om51bWJlcihzaXplLndpZHRo
KCkpKyItIitRU3RyaW5nOjpudW1iZXIoc2NhbGUpKyIucG5nIikpOworICAgICAgICAgICAgICAg
IH0KKyAgICAgICAgICAgIH0KKyAgICAgICAgfQorICAgICAgICByb290LT5zZXRQcm9wZXJ0eSgi
d2lkdGgiLDE5MjApO3Jvb3QtPnNldFByb3BlcnR5KCJoZWlnaHQiLDEwODApOworICAgICAgICBR
VkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCksInNob3dQcm9kdWN0
aW9uVmlldyIsUV9BUkcoUVZhcmlhbnQsUVN0cmluZygiQXBwVmlldyIpKSkpOworICAgICAgICBm
b3IoaW50IGFjY2VudD0wO2FjY2VudDwxNjthY2NlbnQrKykgeworICAgICAgICAgICAgUVZFUklG
WShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VBY2NlbnQiLFFf
QVJHKFFWYXJpYW50LGFjY2VudCkpKTtRVGVzdDo6cVdhaXQoMzApOworICAgICAgICAgICAgaWYo
IW91dC5pc0VtcHR5KCkpUVZFUklGWSh3aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZlKG91dCsiL2Ny
aW1zb24tZ2xhc3MtYWNjZW50LSIrUVN0cmluZzo6bnVtYmVyKGFjY2VudCkrIi5wbmciKSk7Cisg
ICAgICAgIH0KKyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3Qu
ZGF0YSgpLCJjaG9vc2VBY2Nlc3NpYmlsaXR5IixRX0FSRyhRVmFyaWFudCx0cnVlKSxRX0FSRyhR
VmFyaWFudCx0cnVlKSkpO1FUZXN0OjpxV2FpdCgxMDApOworICAgICAgICBpZighb3V0LmlzRW1w
dHkoKSlRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0KyIvY3JpbXNvbi1nbGFz
cy1oaWdoLWNvbnRyYXN0LnBuZyIpKTsKKyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52
b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VBY2Nlc3NpYmlsaXR5IixRX0FSRyhRVmFyaWFu
dCxmYWxzZSksUV9BUkcoUVZhcmlhbnQsZmFsc2UpKSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFP
YmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiY2hvb3NlQWNjZW50IixRX0FSRyhRVmFy
aWFudCw0KSkpOworICAgICAgICBRVGVtcG9yYXJ5RGlyIHdhbGxwYXBlckZvbGRlcjtRVkVSSUZZ
KHdhbGxwYXBlckZvbGRlci5pc1ZhbGlkKCkpOworICAgICAgICBRSW1hZ2Ugd2FsbHBhcGVyKDE5
MjAsMTA4MCxRSW1hZ2U6OkZvcm1hdF9SR0IzMik7CisgICAgICAgIHtRUGFpbnRlciBwYWludGVy
KCZ3YWxscGFwZXIpO1FMaW5lYXJHcmFkaWVudCBncmFkaWVudCgwLDAsMTkyMCwxMDgwKTtncmFk
aWVudC5zZXRDb2xvckF0KDAsUUNvbG9yKCIjMzIxMTIyIikpO2dyYWRpZW50LnNldENvbG9yQXQo
MSxRQ29sb3IoIiMxNTFENDIiKSk7cGFpbnRlci5maWxsUmVjdCh3YWxscGFwZXIucmVjdCgpLGdy
YWRpZW50KTtwYWludGVyLnNldFBlbihRUGVuKFFDb2xvcigiIzlEMzU1NSIpLDgpKTtwYWludGVy
LmRyYXdFbGxpcHNlKFFQb2ludEYoMTE1MCw1NTApLDU1MCw1NTApO30KKyAgICAgICAgUVN0cmlu
ZyB3YWxscGFwZXJQYXRoPXdhbGxwYXBlckZvbGRlci5maWxlUGF0aCgiZml4dHVyZS1iYWNrZ3Jv
dW5kLnBuZyIpO1FWRVJJRlkod2FsbHBhcGVyLnNhdmUod2FsbHBhcGVyUGF0aCkpOworICAgICAg
ICBRVmFyaWFudCBzZWxlY3RlZDtRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9v
dC5kYXRhKCksImNob29zZVdhbGxwYXBlciIsUV9SRVRVUk5fQVJHKFFWYXJpYW50LHNlbGVjdGVk
KSxRX0FSRyhRVmFyaWFudCxRVXJsOjpmcm9tTG9jYWxGaWxlKHdhbGxwYXBlclBhdGgpKSkpO1FW
RVJJRlkoc2VsZWN0ZWQudG9Cb29sKCkpOworICAgICAgICBRVGVzdDo6cVdhaXQoMjUwKTsKKyAg
ICAgICAgaWYoIW91dC5pc0VtcHR5KCkpUVZFUklGWSh3aW5kb3ctPmdyYWJXaW5kb3coKS5zYXZl
KG91dCsiL2NyaW1zb24tZ2xhc3Mtc2VsZWN0ZWQtYmFja2dyb3VuZC5wbmciKSk7CisgICAgICAg
IGNvbnN0IGF1dG8gd2FsbHBhcGVycz1yb290LT5maW5kQ2hpbGRyZW48UU9iamVjdCo+KCJjcmlt
c29uV2FsbHBhcGVyIik7UVZFUklGWSghd2FsbHBhcGVycy5pc0VtcHR5KCkpOworICAgICAgICBR
TGlzdDxzdGQ6OnNoYXJlZF9wdHI8UVNpZ25hbFNweT4+IGltYWdlQ2hhbmdlczsKKyAgICAgICAg
Zm9yKGF1dG8gd2FsbHBhcGVyOndhbGxwYXBlcnMpIHsKKyAgICAgICAgICAgIGF1dG8gcHJvcGVy
dHk9d2FsbHBhcGVyLT5tZXRhT2JqZWN0KCktPnByb3BlcnR5KHdhbGxwYXBlci0+bWV0YU9iamVj
dCgpLT5pbmRleE9mUHJvcGVydHkoInNvdXJjZSIpKTsKKyAgICAgICAgICAgIGF1dG8gc3B5PXN0
ZDo6bWFrZV9zaGFyZWQ8UVNpZ25hbFNweT4od2FsbHBhcGVyLHByb3BlcnR5Lm5vdGlmeVNpZ25h
bCgpKTtRVkVSSUZZKHNweS0+aXNWYWxpZCgpKTtpbWFnZUNoYW5nZXMuYXBwZW5kKHNweSk7Cisg
ICAgICAgIH0KKyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3Qu
ZGF0YSgpLCJjaG9vc2VEaW1taW5nIixRX0FSRyhRVmFyaWFudCw0NSkpKTsKKyAgICAgICAgUVZF
UklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VTY2FsZSIs
UV9BUkcoUVZhcmlhbnQsMTEwKSkpO1FUZXN0OjpxV2FpdCgxMDApOworICAgICAgICBmb3IoY29u
c3QgYXV0byYgc3B5OmltYWdlQ2hhbmdlcylRQ09NUEFSRShzcHktPmNvdW50KCksMCk7IC8vIGRp
bW1pbmcvdHlwZSBjaGFuZ2VzIG11c3Qgbm90IHJlbG9hZCB0aGUgaW1hZ2UKKyAgICAgICAgUVZF
UklGWShRTWV0YU9iamVjdDo6aW52b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VEaW1taW5n
IixRX0FSRyhRVmFyaWFudCw2NSkpKTsKKyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6aW52
b2tlTWV0aG9kKHJvb3QuZGF0YSgpLCJjaG9vc2VTY2FsZSIsUV9BUkcoUVZhcmlhbnQsMTI1KSkp
OworICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRob2Qocm9vdC5kYXRhKCks
InJlc2V0V2FsbHBhcGVyIikpOworICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VN
ZXRob2Qocm9vdC5kYXRhKCksImhpZGVQcm9kdWN0aW9uVmlldyIpKTsKKyAgICAgICAgYXV0byBx
dWlja01lbnU9cm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigicXVpY2tNZW51TG9hZGVyIik7UVZF
UklGWShxdWlja01lbnUpO3F1aWNrTWVudS0+c2V0UHJvcGVydHkoImFjdGl2ZSIsdHJ1ZSk7UVRl
c3Q6OnFXYWl0KDE1MCk7CisgICAgICAgIFFWRVJJRlkocXVpY2tNZW51LT5wcm9wZXJ0eSgiaXRl
bSIpLnZhbHVlPFFPYmplY3QqPigpKTsKKyAgICAgICAgUVRlc3Q6OmtleUNsaWNrKHdpbmRvdyxR
dDo6S2V5X0Rvd24pOworICAgICAgICBpZighb3V0LmlzRW1wdHkoKSlRVkVSSUZZKHdpbmRvdy0+
Z3JhYldpbmRvdygpLnNhdmUob3V0KyIvY3JpbXNvbi1nbGFzcy1xdWljay1tZW51LnBuZyIpKTsK
KyAgICAgICAgcXVpY2tNZW51LT5zZXRQcm9wZXJ0eSgiYWN0aXZlIixmYWxzZSk7CisgICAgICAg
IFFDT01QQVJFKHFtbFdhcm5pbmdzLmNvdW50KCksMCk7CisgICAgICAgIGF1dG8gZGFzaGJvYXJk
PXJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oImdsYXNzRGFzaGJvYXJkIik7UVZFUklGWShkYXNo
Ym9hcmQpOworICAgICAgICBmb3IoaW50IHNjYWxlOnsxMDAsMTEwLDEyNX0pIHsKKyAgICAgICAg
ICAgIFFWRVJJRlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiY2hvb3Nl
U2NhbGUiLFFfQVJHKFFWYXJpYW50LHNjYWxlKSkpOworICAgICAgICAgICAgZm9yKFFTaXplIHNp
emU6e1FTaXplKDE5MjAsMTA4MCksUVNpemUoMTI4MCw3MjApLFFTaXplKDkwMCw2NDApfSkgewor
ICAgICAgICAgICAgICAgIHJvb3QtPnNldFByb3BlcnR5KCJ3aWR0aCIsc2l6ZS53aWR0aCgpKTty
b290LT5zZXRQcm9wZXJ0eSgiaGVpZ2h0IixzaXplLmhlaWdodCgpKTtkYXNoYm9hcmQtPnNldFBy
b3BlcnR5KCJ2aXNpYmxlIix0cnVlKTtRVGVzdDo6cVdhaXQoMjUwKTsKKyAgICAgICAgICAgICAg
ICBpZighb3V0LmlzRW1wdHkoKSlRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0
KyIvY3JpbXNvbi1nbGFzcy1kYXNoYm9hcmQtIitRU3RyaW5nOjpudW1iZXIoc2l6ZS53aWR0aCgp
KSsiLSIrUVN0cmluZzo6bnVtYmVyKHNjYWxlKSsiLnBuZyIpKTsKKyAgICAgICAgICAgICAgICBh
dXRvIGNhcmRzPWRhc2hib2FyZC0+ZmluZENoaWxkcmVuPFFRdWlja0l0ZW0qPigiY3JpbXNvbk1l
dHJpYyIpO2ZvcihhdXRvIGNhcmQ6Y2FyZHMpUVZFUklGWShjYXJkLT53aWR0aCgpPjEwMCk7Cisg
ICAgICAgICAgICAgICAgYXV0byBob3N0PWRhc2hib2FyZC0+ZmluZENoaWxkPFFRdWlja0l0ZW0q
PigiZ2xhc3NIb3N0Iik7UVZFUklGWShob3N0KTtRVkVSSUZZKGhvc3QtPndpZHRoKCk+PTApOwor
ICAgICAgICAgICAgfQorICAgICAgICB9CisgICAgICAgIGRhc2hib2FyZC0+c2V0UHJvcGVydHko
InZpc2libGUiLGZhbHNlKTsKKyAgICAgICAgYXV0byBwaWNrZXI9cm9vdC0+ZmluZENoaWxkPFFP
YmplY3QqPigiZ2xhc3NCYWNrZ3JvdW5kUGlja2VyIik7UVZFUklGWShwaWNrZXIpO1FWRVJJRlko
UU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChwaWNrZXIsIm9wZW4iKSk7UVRlc3Q6OnFXYWl0KDE1
MCk7UVZFUklGWShwaWNrZXItPnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAg
ICBpZighb3V0LmlzRW1wdHkoKSlRVkVSSUZZKHdpbmRvdy0+Z3JhYldpbmRvdygpLnNhdmUob3V0
KyIvY3JpbXNvbi1nbGFzcy1iYWNrZ3JvdW5kLXBpY2tlci5wbmciKSk7CisgICAgICAgIFFWRVJJ
RlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChwaWNrZXIsImNsb3NlIikpOworICAgICAgICBh
dXRvIGFib3V0ID0gcm9vdC0+ZmluZENoaWxkPFFPYmplY3QqPigiYWJvdXRFY2xpcHNlIik7IFFW
RVJJRlkoYWJvdXQpOworICAgICAgICBhYm91dC0+c2V0UHJvcGVydHkoImluZm8iLCBRVmFyaWFu
dE1hcHt7Im9zIixRVmFyaWFudE1hcHt7Ik5BTUUiLCJFY2xpcHNlT1MifSx7IlZFUlNJT04iLCIw
LjMtZGV2In0seyJUQVJHRVQiLCJGaXh0dXJlIGhhcmR3YXJlIn0seyJGRURPUkEiLCI0NCJ9fX0s
eyJrZXJuZWwiLCJmaXh0dXJlLWtlcm5lbCJ9fSk7CisgICAgICAgIFFWRVJJRlkoUU1ldGFPYmpl
Y3Q6Omludm9rZU1ldGhvZChhYm91dCwib3BlbiIpKTsgUVRlc3Q6OnFXYWl0KDMwMCk7CisgICAg
ICAgIFFWRVJJRlkoYWJvdXQtPnByb3BlcnR5KCJ2aXNpYmxlIikudG9Cb29sKCkpOworICAgICAg
ICBpZiAoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlkod2luZG93LT5ncmFiV2luZG93KCkuc2F2ZShv
dXQrIi9lY2xpcHNlLWFib3V0LnBuZyIpKTsKKyAgICAgICAgUVZFUklGWShRTWV0YU9iamVjdDo6
aW52b2tlTWV0aG9kKGFib3V0LCJjbG9zZSIpKTsKKyAgICAgICAgYXV0byBzeXN0ZW09cm9vdC0+
ZmluZENoaWxkPFFPYmplY3QqPigic3lzdGVtU2V0dGluZ3MiKTsgUVZFUklGWShzeXN0ZW0pOwor
ICAgICAgICBmb3IoaW50IHNjYWxlOnsxMDAsMTEwLDEyNX0pIHsKKyAgICAgICAgICAgIFFWRVJJ
RlkoUU1ldGFPYmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiY2hvb3NlU2NhbGUiLFFf
QVJHKFFWYXJpYW50LHNjYWxlKSkpOworICAgICAgICAgICAgcm9vdC0+c2V0UHJvcGVydHkoIndp
ZHRoIiwxMDI0KTsgcm9vdC0+c2V0UHJvcGVydHkoImhlaWdodCIsNjQwKTsKKyAgICAgICAgICAg
IHN5c3RlbS0+c2V0UHJvcGVydHkoImFjdGl2ZSIsdHJ1ZSk7IFFUZXN0OjpxV2FpdCg0MDApOwor
ICAgICAgICAgICAgUVZFUklGWShzeXN0ZW0tPnByb3BlcnR5KCJ3aWR0aCIpLnRvSW50KCk8PTEw
MjQpOworICAgICAgICAgICAgaWYoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlkod2luZG93LT5ncmFi
V2luZG93KCkuc2F2ZShvdXQrIi9zeXN0ZW0tY29udHJvbHMtIitRU3RyaW5nOjpudW1iZXIoc2Nh
bGUpKyIucG5nIikpOworICAgICAgICAgICAgZm9yKGludCBhY2NlbnQ9MDthY2NlbnQ8MTY7YWNj
ZW50KyspIHsKKyAgICAgICAgICAgICAgICBRVkVSSUZZKFFNZXRhT2JqZWN0OjppbnZva2VNZXRo
b2Qocm9vdC5kYXRhKCksImNob29zZUFjY2VudCIsUV9BUkcoUVZhcmlhbnQsYWNjZW50KSkpOyBR
VGVzdDo6cVdhaXQoMTApOworICAgICAgICAgICAgICAgIFFWRVJJRlkoc3RhdGUtPnByb3BlcnR5
KCJhY2NlbnQiKS52YWx1ZTxRQ29sb3I+KCkuaXNWYWxpZCgpKTsKKyAgICAgICAgICAgIH0KKyAg
ICAgICAgICAgIGF1dG8gc2Nyb2xsPXJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4oInN5c3RlbVNj
cm9sbCIpOyBRVkVSSUZZKHNjcm9sbCk7CisgICAgICAgICAgICBhdXRvIGZsaWNrPXNjcm9sbC0+
cHJvcGVydHkoImNvbnRlbnRJdGVtIikudmFsdWU8UVF1aWNrSXRlbSo+KCk7IFFWRVJJRlkoZmxp
Y2spOworICAgICAgICAgICAgYXV0byBtb25pdG9yPXJvb3QtPmZpbmRDaGlsZDxRT2JqZWN0Kj4o
ImhhcmR3YXJlTW9uaXRvciIpOyBRVkVSSUZZKG1vbml0b3IpOworICAgICAgICAgICAgZmxpY2st
PnNldFByb3BlcnR5KCJjb250ZW50WSIsbW9uaXRvci0+cHJvcGVydHkoInkiKSk7IFFUZXN0Ojpx
V2FpdCgyMDApOworICAgICAgICAgICAgaWYoIW91dC5pc0VtcHR5KCkpIFFWRVJJRlkod2luZG93
LT5ncmFiV2luZG93KCkuc2F2ZShvdXQrIi9oYXJkd2FyZS1tb25pdG9yLSIrUVN0cmluZzo6bnVt
YmVyKHNjYWxlKSsiLnBuZyIpKTsKKyAgICAgICAgICAgIGZsaWNrLT5zZXRQcm9wZXJ0eSgiY29u
dGVudFkiLDApOworICAgICAgICAgICAgc3lzdGVtLT5zZXRQcm9wZXJ0eSgiYWN0aXZlIixmYWxz
ZSk7IFFUZXN0OjpxV2FpdCgxMDApOworICAgICAgICB9CisgICAgICAgIFFWRVJJRlkoUU1ldGFP
YmplY3Q6Omludm9rZU1ldGhvZChyb290LmRhdGEoKSwiY2hvb3NlU2NhbGUiLFFfQVJHKFFWYXJp
YW50LDEwMCkpKTsKKyAgICAgICAgUUNPTVBBUkUocW1sV2FybmluZ3MuY291bnQoKSwwKTsKKyAg
ICAgICAgcXVuc2V0ZW52KCJNT09OTElHSFRfQ09OVFJPTFNfRklYVFVSRSIpOworICAgIH0KK307
CitRVEVTVF9NQUlOKENyaW1zb25UZXN0KQorI2luY2x1ZGUgInRlc3QtY3JpbXNvbi5tb2MiCmRp
ZmYgLS1naXQgYS9hcHAvbW9vbmxpZ2h0b3MvdGVzdHMvdGVzdC1jcmltc29uLnBybyBiL2FwcC9t
b29ubGlnaHRvcy90ZXN0cy90ZXN0LWNyaW1zb24ucHJvCm5ldyBmaWxlIG1vZGUgMTAwNjQ0Cmlu
ZGV4IDAwMDAwMDAuLjkyNTdjMzYKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvbW9vbmxpZ2h0b3Mv
dGVzdHMvdGVzdC1jcmltc29uLnBybwpAQCAtMCwwICsxLDIzIEBACitRVCArPSBjb3JlIGd1aSBx
dWljayBuZXR3b3JrIHF1aWNrY29udHJvbHMyIHRlc3RsaWIgc3ZnCitDT05GSUcgKz0gYysrMTcg
dGVzdGNhc2UKK1RBUkdFVCA9IHRlc3QtY3JpbXNvbgorU09VUkNFUyArPSB0ZXN0LWNyaW1zb24u
Y3BwIC4uL2NyaW1zb25zdGF0dXMuY3BwCitIRUFERVJTICs9IC4uL2NyaW1zb25zdGF0dXMuaAor
CitTT1VSQ0VTICs9IC4uL21hbmFnZWR1cGRhdGVzLmNwcAorSEVBREVSUyArPSAuLi8uLi9iYWNr
ZW5kL2F1dG91cGRhdGVjaGVja2VyLmgKKworREVGSU5FUyArPSBNT09OTElHSFRfQ09OVFJPTFNf
VEVTVAorU09VUkNFUyArPSAuLi9zeXN0ZW1jb250cm9scy5jcHAKK0hFQURFUlMgKz0gLi4vc3lz
dGVtY29udHJvbHMuaAorCitTT1VSQ0VTICs9IC4uL2VjbGlwc2Vwcm9maWxlcy5jcHAKK0hFQURF
UlMgKz0gLi4vZWNsaXBzZXByb2ZpbGVzLmgKKworIyBNYXRjaCB0aGUgcHJvZHVjdGlvbiByZXNv
dXJjZSBidW5kbGUgc28gcmVuZGVyZWQgaWNvbnMgYXJlIGFjdHVhbGx5IHRlc3RlZC4KK1JFU09V
UkNFUyArPSAuLi8uLi9yZXNvdXJjZXMucXJjCisKK1NPVVJDRVMgKz0gLi4vbG9jYWxoYXJkd2Fy
ZS5jcHAKK0hFQURFUlMgKz0gLi4vbG9jYWxoYXJkd2FyZS5oCisKK0hFQURFUlMgKz0gdWltb2Rl
bHMuaApkaWZmIC0tZ2l0IGEvYXBwL21vb25saWdodG9zL3Rlc3RzL3VpbW9kZWxzLmggYi9hcHAv
bW9vbmxpZ2h0b3MvdGVzdHMvdWltb2RlbHMuaApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAw
MDAwMDAwLi5hMDAxZWI4Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL21vb25saWdodG9zL3Rlc3Rz
L3VpbW9kZWxzLmgKQEAgLTAsMCArMSw0MCBAQAorI3ByYWdtYSBvbmNlCisjaW5jbHVkZSA8UUFi
c3RyYWN0TGlzdE1vZGVsPgorI2luY2x1ZGUgPFFWYXJpYW50TWFwPgorY2xhc3MgVWlDb21wdXRl
ck1vZGVsIDogcHVibGljIFFBYnN0cmFjdExpc3RNb2RlbCB7CisgICAgUV9PQkpFQ1QKK3B1Ymxp
YzoKKyAgICBlbnVtIFJvbGVzIHtOYW1lUm9sZT1RdDo6VXNlclJvbGUsT25saW5lUm9sZSxQYWly
ZWRSb2xlLEJ1c3lSb2xlLFdha2VhYmxlUm9sZSxTdGF0dXNVbmtub3duUm9sZSxTZXJ2ZXJTdXBw
b3J0ZWRSb2xlLERldGFpbHNSb2xlLEFwb2xsb1ZlcnNpb25Sb2xlLElzQXBvbGxvU2VydmVyUm9s
ZSxQZXJtaXNzaW9uU3VtbWFyeVJvbGUsSG9zdFR5cGVSb2xlLFRyYW5zcG9ydFJvbGUsTGF0ZW5j
eVRleHRSb2xlLExhc3RTZWVuVGV4dFJvbGV9O1FfRU5VTShSb2xlcykKKyAgICBleHBsaWNpdCBV
aUNvbXB1dGVyTW9kZWwoUU9iamVjdCogcGFyZW50PW51bGxwdHIpOlFBYnN0cmFjdExpc3RNb2Rl
bChwYXJlbnQpe30KKyAgICBRX0lOVk9LQUJMRSB2b2lkIGluaXRpYWxpemUoUU9iamVjdCope30K
KyAgICBRX0lOVk9LQUJMRSBRVmFyaWFudE1hcCBjcmltc29uSG9zdChpbnQpIGNvbnN0IHtyZXR1
cm4ge3siaWQiLCJ1aS1maXh0dXJlIn0seyJ1cmwiLCJodHRwczovLzEyNy4wLjAuMTo0Nzk5MCJ9
fTt9CisgICAgaW50IHJvd0NvdW50KGNvbnN0IFFNb2RlbEluZGV4JiA9IFFNb2RlbEluZGV4KCkp
IGNvbnN0IG92ZXJyaWRle3JldHVybiAyO30KKyAgICBRSGFzaDxpbnQsUUJ5dGVBcnJheT4gcm9s
ZU5hbWVzKCljb25zdCBvdmVycmlkZSB7cmV0dXJuIHt7TmFtZVJvbGUsIm5hbWUifSx7T25saW5l
Um9sZSwib25saW5lIn0se1BhaXJlZFJvbGUsInBhaXJlZCJ9LHtCdXN5Um9sZSwiYnVzeSJ9LHtX
YWtlYWJsZVJvbGUsIndha2VhYmxlIn0se1N0YXR1c1Vua25vd25Sb2xlLCJzdGF0dXNVbmtub3du
In0se1NlcnZlclN1cHBvcnRlZFJvbGUsInNlcnZlclN1cHBvcnRlZCJ9LHtEZXRhaWxzUm9sZSwi
ZGV0YWlscyJ9LHtBcG9sbG9WZXJzaW9uUm9sZSwiYXBvbGxvVmVyc2lvbiJ9LHtJc0Fwb2xsb1Nl
cnZlclJvbGUsImlzQXBvbGxvU2VydmVyIn0se1Blcm1pc3Npb25TdW1tYXJ5Um9sZSwicGVybWlz
c2lvblN1bW1hcnkifSx7SG9zdFR5cGVSb2xlLCJob3N0VHlwZSJ9LHtUcmFuc3BvcnRSb2xlLCJ0
cmFuc3BvcnQifSx7TGF0ZW5jeVRleHRSb2xlLCJsYXRlbmN5VGV4dCJ9LHtMYXN0U2VlblRleHRS
b2xlLCJsYXN0U2VlblRleHQifX07fQorICAgIFFfSU5WT0tBQkxFIFFWYXJpYW50IGRhdGEoY29u
c3QgUU1vZGVsSW5kZXgmIGluZGV4LGludCByb2xlKSBjb25zdCBvdmVycmlkZSB7CisgICAgICAg
IGlmKHJvbGU9PU5hbWVSb2xlKXJldHVybiBpbmRleC5yb3coKT8iQmFja3VwIFBDIjoiR2FtaW5n
IFBDIjsKKyAgICAgICAgaWYocm9sZT09T25saW5lUm9sZXx8cm9sZT09UGFpcmVkUm9sZXx8cm9s
ZT09U2VydmVyU3VwcG9ydGVkUm9sZXx8cm9sZT09SXNBcG9sbG9TZXJ2ZXJSb2xlKXJldHVybiB0
cnVlOworICAgICAgICBpZihyb2xlPT1Ib3N0VHlwZVJvbGUpcmV0dXJuICJWSUJFUE9MTE8iO2lm
KHJvbGU9PVRyYW5zcG9ydFJvbGUpcmV0dXJuICJMQU4iOworICAgICAgICBpZihyb2xlPT1MYXRl
bmN5VGV4dFJvbGUpcmV0dXJuICI0IG1zIjtpZihyb2xlPT1QZXJtaXNzaW9uU3VtbWFyeVJvbGUp
cmV0dXJuICJGdWxsIGFjY2VzcyI7CisgICAgICAgIGlmKHJvbGU9PURldGFpbHNSb2xlKXJldHVy
biBRVmFyaWFudExpc3QoKTtpZihyb2xlPT1MYXN0U2VlblRleHRSb2xlfHxyb2xlPT1BcG9sbG9W
ZXJzaW9uUm9sZSlyZXR1cm4gUVN0cmluZygpO3JldHVybiBmYWxzZTsKKyAgICB9CitzaWduYWxz
OgorICAgIHZvaWQgb3RwU3RhZ2UxQ29tcGxldGVkKCk7CisgICAgdm9pZCBwYWlyaW5nQ29tcGxl
dGVkKFFWYXJpYW50IGVycm9yKTsKKyAgICB2b2lkIGNvbm5lY3Rpb25UZXN0Q29tcGxldGVkKGlu
dCByZXN1bHQpOworfTsKK2NsYXNzIFVpQXBwTW9kZWwgOiBwdWJsaWMgUUFic3RyYWN0TGlzdE1v
ZGVsIHsKKyAgICBRX09CSkVDVAorcHVibGljOgorICAgIGV4cGxpY2l0IFVpQXBwTW9kZWwoUU9i
amVjdCogcGFyZW50PW51bGxwdHIpOlFBYnN0cmFjdExpc3RNb2RlbChwYXJlbnQpe30KKyAgICBR
X0lOVk9LQUJMRSB2b2lkIGluaXRpYWxpemUoUU9iamVjdCosaW50LGJvb2wpe30KKyAgICBRX0lO
Vk9LQUJMRSBpbnQgZ2V0UnVubmluZ0FwcElkKCl7cmV0dXJuIDA7fQorICAgIFFfSU5WT0tBQkxF
IFFTdHJpbmcgZ2V0UnVubmluZ0FwcE5hbWUoKXtyZXR1cm4ge307fQorICAgIFFfSU5WT0tBQkxF
IGludCBnZXREaXJlY3RMYXVuY2hBcHBJbmRleCgpe3JldHVybiAtMTt9CisgICAgUV9JTlZPS0FC
TEUgUVN0cmluZyBnZXRDb21wdXRlclV1aWQoKXtyZXR1cm4gInVpLWZpeHR1cmUiO30KKyAgICBR
X0lOVk9LQUJMRSB2b2lkIHJlc3luY1J1bm5pbmdTdGF0ZSgpe30KKyAgICBpbnQgcm93Q291bnQo
Y29uc3QgUU1vZGVsSW5kZXgmID0gUU1vZGVsSW5kZXgoKSljb25zdCBvdmVycmlkZXtyZXR1cm4g
Njt9CisgICAgUUhhc2g8aW50LFFCeXRlQXJyYXk+IHJvbGVOYW1lcygpY29uc3Qgb3ZlcnJpZGV7
cmV0dXJuIHt7MjU2LCJuYW1lIn0sezI1NywicnVubmluZyJ9LHsyNTgsImJveGFydCJ9LHsyNTks
ImhpZGRlbiJ9LHsyNjAsImFwcGlkIn0sezI2MSwiZGlyZWN0TGF1bmNoIn0sezI2MiwiaXNBcHBD
b2xsZWN0b3JHYW1lIn19O30KKyAgICBRVmFyaWFudCBkYXRhKGNvbnN0IFFNb2RlbEluZGV4JiBp
bmRleCxpbnQgcm9sZSljb25zdCBvdmVycmlkZSB7aWYocm9sZT09MjU2KXJldHVybiBRU3RyaW5n
TGlzdHsiRGVza3RvcCIsIlN0ZWFtIEJpZyBQaWN0dXJlIiwiR2FtZSBsaWJyYXJ5IiwiTWVkaWEi
LCJCcm93c2VyIiwiVG9vbHMifS52YWx1ZShpbmRleC5yb3coKSk7aWYocm9sZT09MjU4KXJldHVy
biAicXJjOi9yZXMvbm9fYXBwX2ltYWdlLnBuZyI7aWYocm9sZT09MjYwKXJldHVybiBpbmRleC5y
b3coKSsxO3JldHVybiBmYWxzZTt9CitzaWduYWxzOgorICAgIHZvaWQgY29tcHV0ZXJMb3N0KCk7
Cit9OwpkaWZmIC0tZ2l0IGEvYXBwL3FtbC5xcmMgYi9hcHAvcW1sLnFyYwppbmRleCBhM2MxMWRk
Li40OGU5ZDU3IDEwMDY0NAotLS0gYS9hcHAvcW1sLnFyYworKysgYi9hcHAvcW1sLnFyYwpAQCAt
Miw2ICsyLDE0IEBACiAgICAgPHFyZXNvdXJjZSBwcmVmaXg9Ii8iPgogICAgICAgICA8ZmlsZT5n
dWkvVGhlbWUucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvVmJUb2tlbnMucW1sPC9maWxl
PgorICAgICAgICA8ZmlsZT5ndWkvQ3JpbXNvbkdsYXNzUGFuZWwucW1sPC9maWxlPgorICAgICAg
ICA8ZmlsZT5ndWkvQ3JpbXNvbkJhY2tncm91bmRQaWNrZXIucW1sPC9maWxlPgorICAgICAgICA8
ZmlsZT5ndWkvQ3JpbXNvbkdsYXNzQmFja2Ryb3AucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5n
dWkvQ3JpbXNvblNwYXJrbGluZS5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29u
TG9jYWxQYW5lbC5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9Dcmltc29uR2xhc3NSYWls
LnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0NyaW1zb25Ib3N0UGFuZWwucW1sPC9maWxl
PgorCiAgICAgICAgIDxmaWxlPmd1aS9WYkZvY3VzUmluZy5xbWw8L2ZpbGU+CiAgICAgICAgIDxm
aWxlPmd1aS9WYkRyb3BTaGFkb3cucW1sPC9maWxlPgogICAgICAgICA8ZmlsZT5ndWkvVmJIaW50
QmFyLnFtbDwvZmlsZT4KQEAgLTE0LDYgKzIyLDExIEBACiAgICAgICAgIDxmaWxlPmd1aS9WYkhv
c3RDYXJkLnFtbDwvZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL1ZiV2VsY29tZVNoZWV0LnFtbDwv
ZmlsZT4KICAgICAgICAgPGZpbGU+Z3VpL21haW4ucW1sPC9maWxlPgorICAgICAgICA8ZmlsZT5n
dWkvQ3JpbXNvblN0YXR1c0RpYWxvZy5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9TeXN0
ZW1Db25uZWN0aW9uc0RpYWxvZy5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9FY2xpcHNl
Q29udHJvbENlbnRlci5xbWw8L2ZpbGU+CisgICAgICAgIDxmaWxlPmd1aS9FY2xpcHNlQWN0aW9u
QnV0dG9uLnFtbDwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0VjbGlwc2VBYm91dERpYWxvZy5x
bWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9QY1ZpZXcucW1sPC9maWxlPgogICAgICAgICA8
ZmlsZT5ndWkvQXBwVmlldy5xbWw8L2ZpbGU+CiAgICAgICAgIDxmaWxlPmd1aS9TZXR0aW5nc1Zp
ZXcucW1sPC9maWxlPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9jcmltc29uLWJhdHRlcnkuc3ZnIGIv
YXBwL3Jlcy9jcmltc29uLWJhdHRlcnkuc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAw
MDAwMDAuLjM3NTM1NjYKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2NyaW1zb24tYmF0dGVy
eS5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9z
dmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48ZyBmaWxsPSJu
b25lIiBzdHJva2U9IiNFQ0VFRjEiIHN0cm9rZS13aWR0aD0iMS44IiBzdHJva2UtbGluZWNhcD0i
cm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxyZWN0IHg9IjIiIHk9IjYiIHdpZHRoPSIx
OCIgaGVpZ2h0PSIxMiIgcng9IjIiLz48cGF0aCBkPSJNMjIgMTB2NE02IDEwdjRNMTAgMTB2NE0x
NCAxMHY0Ii8+PC9nPjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9jcmltc29uLWJsdWV0b290
aC5zdmcgYi9hcHAvcmVzL2NyaW1zb24tYmx1ZXRvb3RoLnN2ZwpuZXcgZmlsZSBtb2RlIDEwMDY0
NAppbmRleCAwMDAwMDAwLi5jZWY5YWI4Ci0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9jcmlt
c29uLWJsdWV0b290aC5zdmcKQEAgLTAsMCArMSBAQAorPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53
My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0
Ij48cGF0aCBkPSJNNyA3bDEwIDEwLTUgNFYzbDUgNEw3IDE3IiBmaWxsPSJub25lIiBzdHJva2U9
IndoaXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2Ut
bGluZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2NyaW1zb24taG9z
dC5zdmcgYi9hcHAvcmVzL2NyaW1zb24taG9zdC5zdmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5k
ZXggMDAwMDAwMC4uZDFkNTliMAotLS0gL2Rldi9udWxsCisrKyBiL2FwcC9yZXMvY3JpbXNvbi1o
b3N0LnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAw
L3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQgMjQiPjxnIGZpbGw9
Im5vbmUiIHN0cm9rZT0iI0VDRUVGMSIgc3Ryb2tlLXdpZHRoPSIxLjgiIHN0cm9rZS1saW5lY2Fw
PSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHJlY3QgeD0iMyIgeT0iMyIgd2lkdGg9
IjE4IiBoZWlnaHQ9IjE0IiByeD0iMiIvPjxwYXRoIGQ9Ik04IDIxaDhNMTIgMTd2NE02IDEwaDNs
Mi00IDMgOCAyLTRoMiIvPjwvZz48L3N2Zz4KZGlmZiAtLWdpdCBhL2FwcC9yZXMvY3JpbXNvbi1u
ZXR3b3JrLnN2ZyBiL2FwcC9yZXMvY3JpbXNvbi1uZXR3b3JrLnN2ZwpuZXcgZmlsZSBtb2RlIDEw
MDY0NAppbmRleCAwMDAwMDAwLi5iMmExMDNhCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jlcy9j
cmltc29uLW5ldHdvcmsuc3ZnCkBAIC0wLDAgKzEgQEAKKzxzdmcgeG1sbnM9Imh0dHA6Ly93d3cu
dzMub3JnLzIwMDAvc3ZnIiB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAy
NCI+PGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRUNFRUYxIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ry
b2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMyA4
YTE0IDE0IDAgMCAxIDE4IDBNNiAxMmE5IDkgMCAwIDEgMTIgME05IDE2YTQgNCAwIDAgMSA2IDAi
Lz48Y2lyY2xlIGN4PSIxMiIgY3k9IjIwIiByPSIxIi8+PC9nPjwvc3ZnPgpkaWZmIC0tZ2l0IGEv
YXBwL3Jlcy9lY2xpcHNlLWNvbnRyb2xzLnN2ZyBiL2FwcC9yZXMvZWNsaXBzZS1jb250cm9scy5z
dmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMC4uNjUzZGJkOAotLS0gL2Rldi9u
dWxsCisrKyBiL2FwcC9yZXMvZWNsaXBzZS1jb250cm9scy5zdmcKQEAgLTAsMCArMSBAQAorPHN2
ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIy
NCIgdmlld0JveD0iMCAwIDI0IDI0Ij48cGF0aCBkPSJNNCA2aDE2TTQgMTJoMTZNNCAxOGgxNk04
IDN2Nk0xNiA5djZNMTAgMTV2NiIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdp
ZHRoPSIxLjgiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIv
Pjwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9lY2xpcHNlLWljb24uc3ZnIGIvYXBwL3Jlcy9l
Y2xpcHNlLWljb24uc3ZnCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAuLjcxMTVj
MzMKLS0tIC9kZXYvbnVsbAorKysgYi9hcHAvcmVzL2VjbGlwc2UtaWNvbi5zdmcKQEAgLTAsMCAr
MSw3IEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjUx
MiIgaGVpZ2h0PSI1MTIiIHZpZXdCb3g9IjAgMCA1MTIgNTEyIj4KKzxkZWZzPjxsaW5lYXJHcmFk
aWVudCBpZD0icmltIiB4MT0iMCIgeTE9IjAiIHgyPSIxIiB5Mj0iMSI+PHN0b3Agc3RvcC1jb2xv
cj0iI2ZmNzU4YiIvPjxzdG9wIG9mZnNldD0iLjQ4IiBzdG9wLWNvbG9yPSIjZGMzNjU4Ii8+PHN0
b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjNjMxNTJiIi8+PC9saW5lYXJHcmFkaWVudD48bGlu
ZWFyR3JhZGllbnQgaWQ9ImdsYXNzIiB4MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iMSI+PHN0b3Ag
c3RvcC1jb2xvcj0iIzIwMTUxYyIvPjxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzA4MDgw
YiIvPjwvbGluZWFyR3JhZGllbnQ+PC9kZWZzPgorPHJlY3QgeD0iMTIiIHk9IjEyIiB3aWR0aD0i
NDg4IiBoZWlnaHQ9IjQ4OCIgcng9IjExMCIgZmlsbD0idXJsKCNnbGFzcykiIHN0cm9rZT0iI2Zm
ZmZmZiIgc3Ryb2tlLW9wYWNpdHk9Ii4xMyIgc3Ryb2tlLXdpZHRoPSIyIi8+Cis8Y2lyY2xlIGN4
PSIyNTYiIGN5PSIyNTYiIHI9IjE0NCIgZmlsbD0idXJsKCNyaW0pIi8+Cis8Y2lyY2xlIGN4PSIy
NjgiIGN5PSIyNDkiIHI9IjEzNiIgZmlsbD0iIzA4MDgwYiIvPgorPHBhdGggZD0iTTE1MSAxNjJh
MTQzIDE0MyAwIDAgMSAxMzUtNDgiIGZpbGw9Im5vbmUiIHN0cm9rZT0iI2ZmZThlZSIgc3Ryb2tl
LW9wYWNpdHk9Ii41NSIgc3Ryb2tlLXdpZHRoPSIzIiBzdHJva2UtbGluZWNhcD0icm91bmQiLz4K
Kzwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9lY2xpcHNlLW1hcmstMTI4LnBuZyBiL2FwcC9y
ZXMvZWNsaXBzZS1tYXJrLTEyOC5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uMTUxMjFjMDRiZTdhNGNiOWZiNjVm
ZjA5OWQ3NDY3YjQ0NGM2ZTkwZApHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgNzA4Nwp6Y21WO2c4
JktxbFApPGg7M0t8TGswMDBlMU5KTFRxMDA0amgwMDRqcDFeQHM2ISMtaWwwMDB8eU5rbDxaYyUx
RT4KemQ2LTwpYj5NJkotZENAeHlMd2QlMl8mX0lncGs7Z0ZoKVJaZ2JqOEVqMkZPLT9IQzdkbjJo
bF44U245WT05NVYjCno2TXJVP2NycjZ5JG1pSTJhNkZGVUk1T2l2ajJGT1F2enZWcGxGK2BPbVVe
a2ArVE9lTyVwYjMrKW9MfERmViNSYAp6cyRZTXZLZEhPQS1tNz1jSkA9ZSomcGw3NUY5TStLYGAp
QzZCc1ZBRmhgMmVqWVNrKlVhXj1iWjJtbXdIN2NgQTkKeksoS1A8JTMjJjFSUitmRCNeTDMjend4
Uzd0SVVsei1lYGIkPzlZdWd4WShJblpAc2xgKlNjTHt4dzZMfD9zSEZQCnoocVdJQXk/QSF6Plpg
QkwrcldEN3tQPnB5dDUmVkBIe04qVDBsIz1YOTV3fiQ+Kzc/dFNGaVJ8JjZsZG1INk9VPAp6bHBX
aSl6SHhZSF96amhFZDEpTkc8RDdIZHM9Z0p+O0JjTSRoKElKM0YkSFZ3S29IbStWTEpWTU1geTwp
JElZR2gKeiZARGZfPHJ4dkZPJCpaMypKb0MqVWhOTGNYPHpSZlIwWno8WSFMQU5FM1A8ZSlBfXYl
OVVkQ0d2fEs4bT1BRTw3CnpkQXhkMXQhbF5YSj9qeVFSMFNlfTVyZWVgVzM1WVAob2VOQHcqVEFs
ejRMJGtQeWc+SGtIbTNlVCp1en4qS3h8JQp6Xnx1Q2FzWkAkZlI9KWpSVGVvZmZSNmR1I0lGMkg1
Jlk9bmp1QnlFdmBfNENNYkp7ZWdIYS0ra1JUVUh+MEBobEIKelI3JV8wK0l+NUE/JWUtJSQzMXRo
aUp9Tz0wOzg3cSkkKkRJUVBWc3ohc1ZBO3srNWt2Kk1CODlKYlhjPVFvKll0CnpNcSl1fiZkV0lH
d2tpOUFiSEZgSGxtWWVYSDgzS0NWTXRwP2ApP01YYyowbHlgRGckN0VBPmhyZVJlZ2stV3QzWAp6
WDt7R2g7MllvUXtAKnY+QD5sKSt5UlIjayU2UnFPN15CdFNIPD4ofl9nOypNTm9PKzVvT1I2MipN
SXopS2x8VigKektSR31XWk47emoyNGlgKDNKP0pDUnF3cCY1MXhQYXNxWUxBPCg5QFNSJTQ4KERm
b0toeSFSNT16O3R4QktZeis7CnpyKyltMHxHTjVLVVpvUGU4VT9ULTtAKkQyI1VJfGhlIzVzJDNk
Si0rRUZ3KkJlaE58NTckcz1Rd3AzMTd3Q0s5cQp6QEE8e3xSTWk1OUcjd25PMHQ4fHR6RyVlLXBX
RDI3JVQweDE1bz9VMklxRGspPWVAVHJFaUxyK19JfX00NThpVz0KemBhQEhLU0lvfD5XTXY+Q0By
NWZjX31zPSNue08lPGlfUkZNM1JiQ2xEOXZONDQ9Y3VLcDsmYUFIZ0VwZ2cpMSlqCnpvUVN4VXRi
OWY1ZHs3MUc+Kzc/M2I5ZWxRRD0pcmc+KmcmdGx9YVVOakc1SGJXUnVzNzctTE1TUkVvRTUtZzQ5
MQp6RlN6KV9jWE1+IypWbEpZRUImJHhQeiZgd2M9PVc1elBOdEYmQmJFVEgtK0V1aCV2PyVpJCVZ
MiE7OWJrO05ANEgKenlMJEMlY1E3VEdQPyhCfUFvQVZzZXopVXF7X0VFczl2bTF2TDV6NXMzcCYj
VXVpbCVrPyhYJVVgU0tVZXs+Vm9ACnpHT1ZaeXF2XztQQ1JCaHZ1cz00Jm9wWiluSH1CbEdeSUdS
ISk3emhCc0FfREQ0VVYwQT9CNzU1I0d7fF4tY1JUaAp6OXgkVCZ6XihATy1wayV8TEkzVk8qRzRY
T2glX0MoWD83ckRCTnd+PS1GdlI+ZCp8aEUyMyszK1FRSmZvel5FJEEKem1ZakMpLWFQfjdBdkQ5
aT41RF9MR2tTVntgYEZxaS1ZZz1KdFEoQjdwOVNjbiZqUzlQN2hVcD5kflcxQ01WckUoCnotZElJ
X0s5QFdIVF5DPF5EZDVMRGd5U3VNdkRXJWlQZE5HNDFPMG4xWT54Z1QwKjdMe1haR0NuXiFqSnM+
WU91LQp6dT56d09wanZ3NWBgKipIeXBTSnh2I004YCFhb3dRVU9rMDt7KHw+aUB4RW4ldWdWKE8t
dlJfY2VEMVFkenEpPGYKemp4UmR6VkBaRDJXY217dVZ9ZHp6antFQlVrM2FrKyN3LXwoXiNQbyEy
RSMrU2NSMSZlWDNUI2lWVnJYZT1rbzgrCnpxIWUjNzk1Z1Uke2BIeTxkfCt3MFR0MGQxQDB1SkQ3
PVV1QWJuP3wjVUErWCorQjlHUT96LXpQMUYmKF5fNyU+Iwp6THRhWDNHT2NqVnhuUyRvTylGclol
bmlXWmNpIztfRmByLVZvbnVTfD5KZiNBQVItdUo0dG1zSGNPKVNxPllaYUcKelVzdytOV0x8VWZ5
cz8mMnNsMyNBOWspcWtgZUpIPVJQZiN0I1N1fkxhTmdsLTcwVDJLN2JVNCQ5YUU4T1pHYWlDCnoy
LUVrQGkxU0xoUjZmYUFpKzlQIWdNajJDY15Bal88YkB+QVFQdHxMbjRURDg1V3FQe3A7RCRDTXxm
anNYPkZ5YQp6ci0jfHlHZFFOQmxnQDBHYlNneFE7OGR4Jm19MHJpTlU9ejZCK3Q7JEZoaiNScU5v
QjBxdnxxIVpLSjN2UTU0Tl8KemFjbzd6MHM5dHNab1QhXnRvTHpPRXQ1UHxTTlUzfmphdWcmYEg+
TVMtcUZfNCZlRFpUSU9se0RTdXVZUjNwPV88Cnp0MXlfKXYyQUY4WkcoSCttQ3YhYVR3b313UCpI
YHpsNVdpfnVjd1BzSjM4NkJjUTFHVGBZdXZ8I2ZzVENFaHpnRwp6VnBeZWlANEQ4a1M8PyNTVWAo
OTlZdSZDO293bE0oOH1XKz5SdCk4K0xjVWxlK3QkViNten5MRiVnKk1LZy1lKCgKekE9YEtDPGxn
Nj47YWxzVTxJIURQZDJ4N3ZUd0xiQnA8TWdXM0sobjxrUGcjMD1hNUorQV9UXmd2WDs7V1NkLSsp
CnpSSHV6MTJueT03Yj1+alJyS3VAXnE2b3NDJHt3cmU9PkhvVDBqI2tVcVk1TCVCSiphPz1JVEda
Z2IkdXw5P00kMAp6Q35leHhLaV9kRCpGVzxwX3dDLXNoJTE5d05UbW88bWUjUUNmS05ESGpIO1Js
emRHdWpEbFUjRiN9T2h6JTM5SmsKek1IbURhRzFFZDNIMkRobFJRRntueF9fb2B6dmFYUiNUckJH
SiRyfFRTYXxIUWVEO2Q+QHU2a3NhOW1ffj44WXBxCnpAPFg/QiVacEY1d1V8cHhkWUI/QjtpJWJH
KW51RjZBdXUpKXNCUEoqUUhmKEphZzI9Jj1eI1pXMnI7SXk2PTVSVAp6UE1jSigwTEVHZE1ASHlN
cn1AR2FTOD9xaHlvRVZNQ0hMc0ZlQzUlNWBSMFp2ZDh3NGcxfVU8Y1J6VUhweEkrfjkKenRHYj5z
bVNMbilyVzhlRlFYd3M9NUR7cjtNSHRKcFB5ajIyTklpbz9MJWllNnYtdDg9Uzk1eCo0VzhNK3pk
WmRZCnpII35obSZrVmpxNVFNYWFFczQzRjFmZnJha1NLJHE2ZT1ha2FZUXl1NjklYmlwIyUtRDBE
Jj4mRHJLQDV6SkIkYAp6YDApOEYzRCQwPXxIWUBkO3B5TTt0cnMyIzchYGI2QyY1cEloflUmUVRx
PS1CZz1FN0ZHQiQqNEsqbExSVnxmOUEKenZGdDYzYTdORTh6V0ZEQSR7OElxKGNlQUpWPXJ5ejt9
OEZ3TXxOJGNIUWZSKnJHZyllUlFHdDdxNilFaHcxcTdNCnojeCNmJDk0T29Vb2p+MXBPZmBZQT85
UyhTKld5JDcpfjd5QSt3TExzIU48OHtfZzRQKy1yTUxlNj09KH02OHB2dwp6e0NHciEqZ0oreEJW
QHhDIVhUTFBEUGJibkhzbG13dCkpTWc8S3hURDtwX2tMS1QmKms5bGBjfnsmRCt5SzY+d00KeklF
OEV+LUxTJjFBcVhER1NCaGxHa1p3U35weThIJHR1Z0ckNFJpZmo9a2EmZmYxM1FgJnl3QS1oZy1M
PTwzc25YCnowZmYtbng7YzVUbXM7UkJRZ3NqO1pJUCo9NmQqOCRKO2VlYUpNJGNGYGpieUZed2Bz
TV55Z1VmKHE9eVRvNytlawp6aSF9entWNThfejhMNT0weFZXS3xwa1dqczVNaUtGOytAQVc8bTtG
SjV4TTYja2xpKUZMLX5ITHhufldDT2wjclMKeiRkYC02Jk5XUTd3SU1RclIpcGE9OzxUPH5ffng3
YjFMZF9aVnEoVzBhZVV+V3BFNnUyKTAjPzg4PyUyZjZlVjlOCnooVmw2PVB+VXEhayEre2Ywd0BB
Ui1qZllkZURqPSg9fU0oMyNXQWc2bm0+S3VQTSNsbGlFTWFlMnA8eTEoME5DcAp6UXJmUj8+UW9X
enp3fXBzOCg7K25xWThnfV9GR3VpYjFlT1pKVG8oYHtLTU1FYE8qNVBYaUdQNHNQfGVDNWhgJisK
eisxZmZzMklGTmJRKT5hTjIhbTBET1huPSk8MHFXWFBebXlSTlU9RkwkUEpJKExuPXQmOHpPO25f
ekA5YFFSUj5xCnpyWTRJNjZgKVNMN2V5aVZOQG96Vj5XdVU4cz5JJllWZ3ZyX3NyJVdVQTAleXFZ
NDd3TTREVVVxc0ZGQkBiPXgoJQp6S2w+Pl95ezx0NEJaaT8kblU1fCRvenVII0Y8ZEZya3FVV3Vf
amJPJnt6KT1ucmVWXiVsWkEqLWokPmx5c01jJUwKelQ/ZUxRM0p7Pj1WJi1RJV97OEVmQ2BNJXJr
aXpna29fbUJzckEjMFY2UU5FamljKWdYbHZRQygkejhUJCRqMUBhCnpFSU5nRyo+KHpYTUFvS3dW
JkVtI1k8VkZtI1g3PUFlK0B5MVQjVEN7TjRNP0BBVkFzMiV4VFQ/e15PVFlpWHU9NQp6dD5xcyNL
MH5mdEFTTERxYl5SdHJSakloQ05mVkQjZlhTYk1qMHBMLSFYP0tZJiFUSj5nKllORGhXX0ZSS2lU
cEUKekNQKkY4al45THhCdndHUio3TGMzVU8tVXFFUHopZlozMz83VTRydS1SaSFsdWAxUV9CeWZE
MCVtWk1NczBHeFV2Cno/P3s8fCQqTFV+RldYd1hfcXQoM0Q3Yzd8SjdANVE4TTcoR2lUTzdPY1dt
RT9JKWBiSDlDX1ZRbDR6akxBSFN7Jgp6QVA4bWV4TTA+aXg+NnlMYXw5dmBSIVpFcmRtQ2N5NXU1
bVZCfThQQEJHIX1vRFMjJTxQQUhaKUEyUyF7ZUtILTAKeldrWVV8YkBAUjtKTX5wRlE7RX4kcDQ0
Kjs+fFlUeWlCM1NXPTtONTNZMn56ejkhaFp4cylXWXleaVYkfFFIZzlTCnpqWFIxSkt2QTZjU1Rq
aWpWRktDSyU+c3hCQ0ZlTXl0Jjc+fFJ3flljQ1dgVXcmPnJ4T3pheXowY3dnVTFhOWxtVwp6ek9U
dDNRcGVKY1paZ0pGJjxYJn5kKURXTktwTU16eD9YclpPcCsld2shPFQrNmVec1U/RSsxPFhjP2Qh
JDgwTysKenN8cyttQm00QyZzMFZkWjAwamFnJXhoXiYodz9kYWhKdVMydGQhcz0kXjlQO2ZnPzh4
QFQjPCFmU0t0R3ZHPUdaCnpDb2VoMmg+SXtINFk0MCNzK3NJVys8NUEkMEJMTEt1JkdmQzBFK1hE
dmlGejxEMzU5Zz5LZ150cnpsaU5kWG9tbQp6a2c+dE9EajEoQSM/Yyk2UGZYSUs7cWJyZjZ4SVZN
aXAzQ0E5VVV+O3hAezF3c2hSJn43KzdzWVBgQV5LTzlVeUMKendtREc4ekpLRUVENHFiSilkV2Y0
Qk9MWCFmQi1VQzdJNmFFKS1Nc256Nz87VTU7Iz5kIz9sXnlCO0NvSClTSjJ9CnpmS3A4YnRFVWpo
KXBCXm5kciF0I1dgPnorU2FAYCFRMV95Y3k2cEBTNXNKPCs5OTF3WCltfVlIM1NvWHJJfiprPwp6
VTxYSTVqVlVLNUQ+fGk0cHBqJUxjejN5b204dVU9NEZ5bGtjRzdlSjZZNmFOPmdvZVQ+ZSo3dlZL
ZlE8MWM7cEQKemwocmRJWW1kckdwc0AlXi1AfCQpZ1heQXVUe2tqUiU+Z04qTmhXWWZZYlVlUHR3
aWROWUNEa2hFM1U2ZD5RKXIwCnpDQEIldjxfOVJjQ15Aa3pXJCYwQndzMi1nNTN6RnhIZktJY1B7
MF9lKUFvPmspTk47d1MwIWFFRkJGRUBSVm9tVwp6Ryp3aXVxe01MSGo1I25WYExGNE5ISGtSdEM7
b2I3MHVAM3J5aV9qb1JCa1duWU9AQ2NpZ0NuKy1FKE05V3ZDcGIKeih8fHlBezt4MGxFNUliSG9k
NlpAeHAhYkVSdDRgQktgRllKQmB1d3QtISs/eGk7dWMjS3VKY3dzbjtnYUcxUyVMCnpQPSQ9S3tB
VFlDMkJII3kyd0doYnZMYWtIYC1KM21efU1KQ0Eme3dnTFNKMUt6QHVjVzxAdTM4OXZSd0FpP01r
MQp6NyQ2c3dkRTFPUm9ZS31xPV9zLVNOQER1MG5WUml6Yj5BSz8ycW98TSQ/aT45NytvMlJ5d1lo
eUs2Y3leeW12PjkKekEwUi0rMjZlZ2podXtRR3teYEFYK0hBbmpgP3M9Z1dTRVIzJlklVGBxQjhH
Mj02RnRQcEdvbTN1bVdDe3RPLWJzCnp3dncmQzNlLUlqcShJNlRjMil8a2VyV0AoQ2N5Y2AzZEhK
WnZuZjg/ZClrekBQTUtfIXElfmVvRG5vZStCY0NhJAp6I1BxNlVaTkx3QVpEM098TjRqUE9SMllp
TlRzQzdLQDBAdSZnfTh6fTA8Q317TnNCS0MrbysoVTtxWCpsT1dqYyoKelo3aUVoZEghTD9UQyZG
Q1lLdWIoVyM/R2NkblU4UFJ3fntmUTUhfURENjQwN2tmQTQpcTJIQzBYbFJQQT1LdXckCnoqRFR+
elh9Mk1fPntgI2B4amtlaGkza0tKST4mLV5tY04qUDdMbkZ9JEx3VUhCO0M9QFprQF5jWGtAZ1pe
aSgqMgp6UHxybHJ4STtDVzFCY14/fEYtNEgoZXJFN0FzbVJ4VHJzMVVQYVMoUWcodyolKDtiNlFA
LVl7Kzlte1RDVlh2IUAKeiFxb00/a0pvfUotSHFXPz0/cWYqVnNIb0YrcXNTfG5AWEJPRHArN0p1
SkM3YlBVVyhtMT8xIUQtOGpsMzZudzxfCnoqPDxKcUdDV29xcGpDbj8td3I/SmNlTGdaZXI/LVJK
ZClvLXk5dFBXdlRAV2BSfTI2OXs1U0JYal5uMVM1P0YqMAp6QTh+cjdueyVfcmE3VFV6cTEzeG1A
V2YxVEh8dU1VNmVTUiQ7QTF8cz1AQUN3R05CazspZ1AjKyRCT1djPElteXoKel9Tc2I+bV9FfSVQ
NTM4Z0k9UWxJSzVLSEBEWEdKZmVFS1ExfDRkPHskZ3pqM1Q3am52Z001MF5CTiZwNVZPKDx4Cnp5
KDJXMVohS0VFK3Ema0drSVI/Xy0lTVdYemNiPF4mVFElQ0JpJCEoVFlmdVI7c1I7MGIjP3A+clVE
SVBQaChaTwp6Zns9ZTcrUUZCJEsyQSRAYVVgenBBfTt3RGdZZmtRWnskUEFvSmhle2FNZVltTSNF
RytgK3wzQFlANXdUWFBtJW8KemA1aW5fOXdPVFNeWnI7R01nYnRQMWw+VyU1QjY7MmhWNCgjQjA7
czVGbGlvOUBzNl4wZTBsRWF7Nis2X0dSODlFCnpCQ0lycUhBcUlpUH1DVFVAYyEtdlQtQ1hOZTtN
QSsxRW9FKkhKST9CMFVzTFdSR0RFenpTcUJqcUljWVErLWI+VQp6Km5JTW80VG14aW0kYERyMCMw
ZV47LSghPmJBTjYoZmlhfHd0XjU5WnNQNSlMaH0wOXxJNUYodCVGYlRxcmRzJkgKeiY/WCkoNDx2
YngxYHxGc208NmNlTkchcFJfSE4/KEVzcnFiVnA+Zj1NU1hQI2srMyVedm1uZyFjTUlPZ20qJCsj
Cnp0VzxgUHhJJGM9N1YyUldZOXJwRTZuc3BGTz50JUNkX0ZhRTM3c35ALXcoZFhCanRncio+Nmw1
X1BLJHZEJjAyWgp6U0hydXdyZ0FAaktJYVRoWnxQI2RtR041YklwfHspYzwrbl95czNRX0tpPDJF
cEFLIUt6ZiF+KUxzfD8qNHNYfHUKeitHdG1saXUlIU0+bispdG9TJlZeYVh8fnVSKStjVUBLJCFr
QzBmS2JPeWpGVmN5OGQhaFlNM2R0VipYMSppZz1LCno/WnlaQTxnNjN2Pno8RUMkQF9UcGJwdnNr
dFBTfFl0Ui1DNUhJRi1vY2txa2g5anFfc0AhbiZeNUxUNjtfUihyOAp6YWo7SispJGNXMTshel4/
cWdHfjRzK0ZAXng+Pz5iZ0pYalhNZW4jSHprXj9uPzRxS2NtV0RJPzJnPGhMZTFQI2QKelJhenYj
cD9yMWMpNytjZSVfbkRfJGtLRU5CUik9aTB9JiRjRFFhU2R8RU9tbm12enFMJD5JUk4mRnwqUDt2
bX45CnoxeGkoPXNjcGI4IWkzPnVFa2hBMklRQkpmNDJAeFNzKVpCN2MyM1E3dV4/PXYtNlQmbmQ3
KyUrJlhIWF9SfmFUUAp6d2lAYStsSkY7eztTflVxayFPSFQ4fWkkY2VqZVg2ejxhdnBhYjtJOCRF
STIrYyRYfDFrdEJ8YWFaKndBaFVeVF4Kelp0WT5uU0orZUA7ZX1GO2I+JHF9cWF1NmJHSTx7LWor
XlNKdW5hO1ZMTVdEMll3NUJmdnd7cnNRbXlvY1MhVVl8CnpFeWgteFVNTUBfNjJCfC1eSSZsZ0NI
MXNRKCg4OVIycF5gMjA+SGs2UUpZRHUhVDtIX2spSUZtPGtIU0x5c2lDTQp6PUF+TVJARCNuUCZp
UDZ1X0VxSChQRTVENkd9RDFzQ35DfXppXjtpfHlwSmUoUG95NUx6QlZPPjdHcjQ8T0RLaV8KemdC
TUstU0V8P1hRZTVLRShmfCg/X2NHdXJXVTg7OUVgcU55ZXN7MW9qdDRMP2otK15eQlM8bWlCRUhr
VmZpOzhNCnpJNSpxRiVDPWM3Jjl1e1ExN2NONT5XRGw8Y3VGb0FtOUBfbmlsSFkrR21+XjtAfmMr
QnNhNzlEcFp3bnwjTnhxMgp6TDFRKm0zT3JVQztGPEM7TG9PbjEleEhyUCpVKSF2VigpSEwwbTNr
SmZVRH5qeSsmJSpBUH1KfE5Ldz83ZTtlTTsKem93PVJONF9pNGkpNkhvdW9nNSEjPjlpQGIxZ0sz
T0c0RTd+UUMjKWtIRVU3M0YrITVSN2xEY0BMcTF8I1JBNmwtCnoma0wwdEpFOVR9UGJofTBuT14z
O04+cjZLRmgmNnVGSjQ+YEJMJCMpTi1wYSlQKlZocCZ7MXs5d3AwcU5FOWQjPwp6QEsoQlAkZWRJ
UV5IUXhHN2k1P2pxLWkkKzgzX25QRng3QV9RY3FidTFzXmx5QktFaW55UF9nSDt9V34jR1EmUT8K
elh8bEk1Nm9YKFZ2N2hJcHBANHt5IXQmK0klZTVhMHF4fWloJllSbyZffFZ8Y3NVcVRPJj9NMC1B
dSFyPUZ2Z0ZECnpaT1BXRldQVlJvPVhGemN8OSNhZWo1PnI+dWlyfUk1Wll3bD90WWVIOHNiJmVi
YXIoO3dSUEwoV2dfQUwyfW1APAp6MVZQfkQmRiRSfG9Kd1E2MFM4NFBhbj5YOzwkPih+YTghPkhk
bkY+P0A5ellgaD4jSU9aR0VZaEROdlorcUVBcU8KekFoMGB2QWFFb0QrfUVaNjxHbDBmRiNXdD4t
bGopRjwzOE9kej07QE5YcXFeSk19KGtYNGl5YVBGIVAqcTR5cD5VCnomJihAeXc2e05NdFUqOzlW
UjNDeklvS05jayUrMl92NCg3Vyt3YUh6K3lKYSVsP1BhYFh1KlQyUjFtQWApYStEagp6R0ZobXEr
OH52UjdjWEE7Sz1Qd1I9M19eP3NIJlllWGE0VTgxX248dlg4Sm1VTyVBfCR1ZVE2cGBebH1fSCFa
SV4KemAzbjBCKm9zS3AoYjRmVVlZb3RfRTB8NFFKIS05P3RFMnNBUnF1YikhakR3fDUzdUI8I3M0
PTxodDdMdiQzOCklCnpgODlwTnltdk5DaGk+c25pKz9tJCleT21TOHhzVjlwRUlaVFNOKiRwVXN5
RjJPQENsfDw1Ym5tb0hfSFo/S2AlPAp6SEk4RyQ3ekckViQ0ZVo/XiFFMXRaOHs5KU5RZWZIY0R6
PiEhJSpmZ1NueE0tOUsqT2xLVClgNlJGd3R1N3Y5XnkKenlaPH5mYF9DQ29yV0g9VCtHQ0VIYFAr
P35Vd21gNTMrYUJvLTklbyNoPUBQPWwlLSRIV0hOWj9zWkokUlNJRkt4CnpVZHk1MGNgfSlkb195
Kl9VI3cyJjJNcVheT1pacjBqNX40aCh3bnojLUZCXzIjIVJFeWZoR1hOQWA8a0BufHQleAp6Yjxi
YnR5fCt4VCtXVF5HelczZ24md1RiamY0O01gYkRqNC1wY3hpVUMlcEdRPTxNdVZfdnoyeF95ekMl
ZXZhUSoKelVRUGtEazNQQlh5NmM5UEVuanxoVFUpa1YlXiZNaitxTEhMTihidGtCaXEobUtJNjx+
QUcrP2t0QV9nTWQpYTVQCnp5aSg1SjBgQTslJmkmKSgpfj55IVI0aDRUajUmbkFZY2UmY191Z2tS
OEdGKndDRCt7bDtRaW1IRCNNcmlnSTd4Ugp6SXZ7eFA7Um44ZCF0bzB+bXJpR19fa0p7dSpyY0lR
QDRaaV9HamBGITwzSW80TGwxblAjQlYham1EaXo7PGlIcGMKenBLLTw7S0QlK19oUUJUcmkmJGZ2
SHA5YilLKV5aZ1o2PWRwO2xmM3FmOHZRcHxHTWg4I2ZSez5obH57d3dfP1RsCnoqUXtOO19TKypQ
QldWJGRNV2gpV09kKlFLPk5VdF92KmpnQW1SJEcxMUhaa2N4fCh9UF5fe09+d2E9KylhUjJASAp6
LUxoaUUqJSRUbl5nSmhHMGBJKlo+ZEJmTVItRUA8MXJ5QWVHMns2YUU2JTs+e2A+RXtNTzl6WD8y
cU51Rjg5V08Keno1VnZ2QEI3UVl7UFhqQWQqXistQ0RTNl90SlMybHFYVXtycWUqa3tmaDQ9PCl2
SW1FdmBCQzd5bD54ZCErJHlOCnpfUzxpfWs3VWsmTVlCSmEqWHFxJXohX3RCPnMjTnhhXyNmYS1a
KGZveXN9YSRDbDdALTU/M0R3VU1vN1NxT2FxVwp6TSsqbnNxcEpBVGQjYH5BZ2toU191OHc8X0VJ
RGJfdVlZfiNVNVFfUWFCdShSY3M8Z25id1AxcW5Cd2ZTJndKT18KeiY2fTx0JmdDd3lSNFMmTEgk
WCVqQX1hZVVMc0pWVHJaJiMyPCV1ZV8+TVV6NVZIaiNoWFU4dysmNzEhfUFBMENfCnpLYUhYWTYy
WlViJG4wPGtWKU8hblJLVWQtVUFsYlojJnVUPzRpM0dlUjRTYndNWGAweHEzV3chbGJhRmIhQVVs
eQp6aCMwSzNxKjgmKVdZU017YiM/dTAhUXc/Zns/KShWQG57cntUS1UmQj5pMGp9O2JUOGRSOEBL
UnlSU05WKTI4KzMKejxafTc1JUhgNVlhVTMxJW9TKSZuWiZodXNFc1JCaypjZWw9KjZhO30pWHNE
fF5JUyhxYHk9emBGTTRScm50eXMkCnpMfjB7diliYnZkXkIjXmo4SGNHSnFpUU9XbjZNfnsmM0NA
RENjOTxKQDYhVlZtMVlpTTRCZyRLPitNfSR7QEJPZgp6SnJWP2dfdWg/ZjxgNSk+b0hyaVVISlFu
cmkpKFghRXo8QmI3bkJaXys4fX5gUiZgUzUmVSFtelAzUH4+c0dGbm8KWnt7aT1JZEBIXl5LcXZx
SjAwMm92UERITGtWMW1FQjIoYlZGCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQg
YS9hcHAvcmVzL2VjbGlwc2UtbWFyay0yNTYucG5nIGIvYXBwL3Jlcy9lY2xpcHNlLW1hcmstMjU2
LnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwLi5hMTM1YzU0ZTE0OWVhYTkwYjYxMGE2OWM4ZjliZjZkZWIwNmMwZTY3
CkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCAxNTgyNQp6Y21YOV9XbXNFSCgrPShxTVRAKDt5Rj45
KCtAKk1ONFVpeCQ0I25MSTZmZkBYI2k2Km55SWM3M3l4KlRCQylifGMKeipfbkgwWEdiRDUpRCRw
S05sKmEqMEVVdkh0UUcoTzFOe2pES3RfYXE4TSohYjNJSz91RGFsR3tgKCZNVV8rfVheCnpfP0Vu
RCZrMT4tN2BJdUNxITVsb3dYWTJHQmQhcHdJUCNtRjY0ZkUjQjY1ZDE7aW1uO0FkJiVkQ2FRbnZy
R0BFQAp6cWViVGxsXm55UjxUOHNVYmN8LUpQR0IycFY9Wm1DXkx1YkZUaT44S1NUKl9ldCNhLTc5
QyZoZFV7Slp6V2F1cmwKejtvTmFJWnxFRX12fiVTbk4qKl9+VkBMSCpNSXkqZjl3dk5QTUZNTSpP
dHV1cW0taF9lQTNoPnc5PH4lK3VIRnV4CnpQe3cxKDRjUW1vIWlEN1VASTNyN2wmYjAkZCUkc1Y8
fko+WTRnV2dvQyt5WTczdSZVemU8eWQ/ITtWWH1iWndwfAp6Xk02ZExQaXpAeUpVezFfU0ZpQklT
VUprflBFMSpJNkU5M3A8NWNSYDYoaiFaUlVzTzM2XiZvejgpO3p0WnlydTAKejREJChPRGNPSCVJ
UDNpOTB6cCk8K2w/MGlDeCZSPi1zamZKejBRXmNsdn1qTHN8LXE2JVhMXmo/SiVDI3h+QDg5Cnoq
R0RPYUQ+ODxzeDlEIUNTMjhCYWxgMWszNUxaVWhCT35Ad2tgMz9rYmhKcFgldURCQXpWPzFjJVcx
eHhpNHk0QQp6Vns9fm03JURYfj15aDduYDNvbWwlVSYoNSQ1ODtfaTY+QisrMlNqRXRMJWB+QEg4
MkNUfnt0cDBsS0FvM3dTJWcKeiNLTyFyRjRmam14YnAqJjRKYEB8M2lVK0Qkald+TUFQPXdkKmlV
TG89RjgqZkN5fSgrNi1edE0yWkplKmskS1dCCnojQioydlAwdX1QT3QkQkVtUSlKdVJIK0J2Q3VZ
YGo1eENPeXtCQStuLUtTK3ZZYW0+ODxPMl5YVUkzREcxVyVVVgp6NTUrK0Jfb1hFUTltVVFFSWlI
alZ3JHRZZip6bnxWPF8oTj9Wc3IoK0QraGtfUzJKdHUpUntjfU1ZVWAtZnJWVXYKeiF3YTQjdXx6
aX5OKk1pbTsmZ1R2SCloRUQ5KmRfZ3hIU1pOQCY+dSpeMHpYb1FNUjEoKjZ9aiV0O2tPTSlVaXNr
CnpyfCE3dExSTntyLTtRSFh5ZDc1e0tlbzJFX356YHQkWjNZd3ZFI0k5c1dJe0tFQWd6REIkbCln
SWlSYzJhdj9iSgp6bmlLc1QtIzxKKF80azxHcmpyblVGS0Jwd0UtYChiNEooX28tPzcxezgkPHBZ
cjhrSVREcURMMlR6SUtre1MpfXMKel9WUkdyUWZ0SX5WQmYmM2JwMihDaXt7MUE3bV9uQ3VTa1B7
ISkzdDRvekQ3bkZZVk01akw/K2hjMElFM2M+VnRICnpBZmNsP0gjOzsqTFgoQzhZYWdsKnVERWFQ
e1FoPnJ8ODRPVyhrVFhIWEhGZ01jTk52U180fUd6SHNtZmptQGI3NAp6emwoPE9maT47bkJ2R2dH
YEsyMGtMaD01RVgkfjFoelVuUkFmKiEtbkRrcGRIO0hpVWohfGx5N1A3ST5aPTZ4M0UKelRCX1lF
I0d1U2xMUFdSQDZtXmU/dytvJihYbFE4UWFfKUozbmFeP15lMUFSd0o/KHE1Pn5ZaTViNlE2OXJz
Smp7CnpXXncmYzR8dkBuZF81LWdoUXd2Qkc/fEpTdjJKSktSV0B1WTBNKl5NdmZPUGVKJUs9eHM4
bmBIKyRXQmYrdTdXdwp6bzVePjJXOTYpUCtmN14yPyYwNFkpVyomfWNQQTNCeDNsVlJTNXdfKVJJ
ISVSMXxrVmhAazZyfWYoSTMtITVXXlAKei1kfVdieyM8fEJjcFFtP1I0QTBmZTVFODIlc31NaUpf
ZytlUDt7UV5kUDl5bXl3NFlYeV42Rz8/NXZadUF9KCEyCnoqfHg3I1hpQiRiYHk9clpDbEI9TmVX
cFZRUDJIfS0tZH4qfCROVWEpLSp7Yz4oWXBhVXZjMDR4RkYpZUcxek9Bdwp6QXc0NnglP3AoYCtg
SWQkbXMzdiYrMF5xSnVkVXNFUnVrSig/fFNSSWZUVXxOUV9xY2dOQ1h2ZlAwb1lnbytkJG8Kelc2
MnlIdWZSQyorZTRmQykxeSVvIU9EaTdzRXlmSCM+eGlRJkZBTjVaWSt1ME9QZWFjay1lcj53XjI0
MCNlUnZpCno9ZDVwNiNORiQhKTlOTjNDIXA3WmcobHw8Rn1fR0BpRFJKWDN2fUk3NnJRZ21Hanlj
WUs2Zmt8dH5aMz1JdGtPKQp6NzByYUBlbThLUGkjZFo5SlJqRUdGTGI+eG1pWjxsXnchYyZmVEI0
OEY1NEE0JWRDMyFFfGJlcV5QTWomP35pdk4Kel9qeHIjSDhXdiFOdG5PekxCSksjamFPNmgqS3Mo
fCVFa3NeWjw9aUcmYHZyJlBFQn1Qal89S31PfHtzMiEyNXk3CnojJmJyQGotNVZMbm13RWI3YDFP
fCZGMmlgMCgxJVMxY2BCU2c2OXFKWkY0c3RkQHhtKGNZN247VGclJUZDeGptPQp6QnA/JTVvZSNS
Ml9eS0BeRCVKXjdGdzV8UjlZPVF5VUN3SzdDIU1AZ3gjMUtYZnBHX1VOKH18Y15XWEE3O0lNaEkK
eipIaSUkVkJicCFyQXpkTW5uJUElNXNhOzZiaWZJUWJLcFdONjhaQjxQZiViPE93S1c9Wl53P1Zv
PEV9fTI8Qm4pCno/RjkxN0NlVklsSlYtUmskX29oVD9MNWY3MnooMjlzQz5FWj9ncX4rS2QkK2FQ
c1NKNCYpYmBzTnNfbC1ebClfagp6SHYmI3NSZSNfVmhxUE4mVkNAJFNhQ1ljaD4qYSM/YHBxNHJ2
cn5vUzkoVjs1e1R3bzVGdVR5aTs2OW9DO1F2K30KejdqUGB5ejIyez9QX2FRblA+USV9PzdofS0r
U1BSLSkzeTVDaSZpZXpafVRGU1cwI2otWTBWUDVecVM1QUlrTUlACnpfTUdGN3twMHdrMnhZamtZ
JWh6YyttbTswO0J7JHZwPHUxRC00NUViU2s5M282KldJSHRiNEIjIXxVI1dfdURtdwp6LU97Q2JI
OURDUmE9d2IkRG5Abk5KPFgpVmB8STRAQDB7M0lsVU1TfFRTfl83NWUyT1FUVGc3Jm9tJnxXNSpF
Pn0KeldJZDlCJjRfdDA1N1N0SWtGX3l6JmQ7X2orSFE4ZilsaCtjdClGa3pXXlJjZzYkbSgwaGRp
cFlCZG5eMW1HMVNxCnojdHltfldeKUtWMWRFdlpLKSY8OXlWQXg4aUlHb0VPWDd+Um5idkdpdz1K
eF9YY2hnXypieGM0Yl9uaSFFY3Q+Qgp6ZX53V2RjJjZaZXpVdWpkekB9ay01RDVaKEw1OFUpK3Vk
dG5CSE5+WWk/OH02OUEjfEMkJm9aVTctPjh8Y0EzTl8Kejd0K3IjRk1qdUxtViNCNlMqXiQra1Va
fC1rYyFxSldLVmZPPn44bi1gYEtyVG13IT07SSZoZHV2dGVZN1FIcVpACnpoOUtYWSYyQlNzRzAx
VEIxNWxKRkxgISlEYFY2X3gtU0RhbEN2JWVwRi1uKkxVUTl2biM/RmcxbEBIMFRfelcwZwp6dWFf
NUJWPz9PZCtsKmMhamR6e0xZWnZ8eEMqVFdMPGg0KnRlcHAtSD5vSk1AJVImbUs0XmZaOTgkMFBB
WjdZbFAKeiRpQlhYI1FEcTB5M3V8UDNXKiVVOFVYQm02bzghSDBsbl9CRkFfbz97VHAoSmN0a2tv
ZyUrQWhGNjF1IVokenFTCnpSQl8xMHUqam9mYzsoK3VpKEBqeUhKRFJoNTF+dFEqVXhKKUM7TXpp
Rm87dTk+dG9LcVYtNW0leUk8Q3lhJip5ZQp6QTk2MSRAY3VXOUtlfHJzYFE+P2BeQ0o3ZzdhOzxN
T2spR2Q1fStuS1c9WUU1LWUkeUo3QGFkK0h6ckN4KzBSJkwKeisreV9nP0ZZc01adX10M3VhYFla
c0Ywc2JiME0hOG95S2p8O1g2Y29yMmFtbGIrYHpedjZsQ3o+ajQ5JXtgWE5PCnp1R3BJMEZzVSNO
XlEpZWRWZ2YxM2QjdVgoUzZme31KY2dRIyl9dXZrPWRvPVVmclReQW55eFFjdT1JUVluNClmZAp6
aG4wbUtVJnpWdjlyRm16bil2JnspdEY5X15xZjZrcXd+dFd1KzE0XmwyKCFTQz8yWiElO25+Kzlw
Y3M3MT9ZV3cKelliKmJBSFhne0xkV2gjYGRQMGJwb1pSRmxOYUQ1SWZOMVZJNmY1VkhSM0lfKlUw
dGxePkRhIWdFSjxmSlAlVjlFCnpONjBObnJfckZZdFIhZGttODZKSTtOcVlManwzZGZtfmJpNFd3
Vmc7WC04MTQ0LV99VnYhYmI3JHs0dj09bClQTQp6dX1uNml5ZExfVEpwfllkSjVweD58SWghMz5L
b3VtPSNgKj1LK2gtbXYjZGcxQmhqMHYrXyFDSnFQYmdmdGdPUnsKek95XkYwN300azlLOTE0X2Ar
VmhQPj0pJGpvcGUmaHFOTVdxPDgtOFh1fWZVJiZ+Kzk1dk0zYUV4Vk5faGN9QDZQCno1NipuMygo
b0pNJms+KVZoKWx2R1Z0TnRlYWxPWUNIZ2dJSmROZWtDKmpvd2s2P0kxfk5AfD92N1VjQnRBeyMp
VQp6QUF3VjBLNk03WXRWRVMxQUtUbG9KemhmTDwtcThgbWFPYn4qVks3ZWA4YHEwbUlCViE+YyNu
ZWF6JUhwKDJyRjcKejI/YGpjQiZ+bWkyMUNec2s5U0goOHhKQCl2ZExpN0ptPC0oIzZtX2IjPVpW
KGZSQ3M8IyY8M0ROUTtnXz87KW1jCnpqeEBASSstN198c1RMejRfRV5eOGQ7eVolRjtSPjwzV3NO
RVNaWEV5LSZZNHh1ZG1gPW1TZWQmYHE3KD9SLU8kOwp6IXQ4Y09iciYtOSt5RnZFc3ZAbDtxNjdi
ezRJQGRXV1c2Pm0lMyE9NntVfj0jaG1aNGc0OWNYMSh9UWAqKHN0dnIKejRhVV5MO2hSfTlTKVZ7
KmEpM2ZVMUJZbFgjPiMxQlV6KVQlSnNZTX09RnduRSVHbTd5b3R0fXAwREB3TjM2X2NmCnpgUyh3
PHtrbmgmWTIyUTJ0RUxwPjNFPWBrPmMkVjI9dSQpcDw5bW40PWZ4IyRpQihuWCFwa0N1PVpBVFBs
YCshZAp6PlcxdEp7OWB7K2RpJHx3SGpMd0YzSyRFRkR6KGFWaD9yQXxtQCM9b2pqVVgzZStDNz8r
fX5ucFJPKnh9YUdDb0UKekR0eipaTU8wPkBxdC01KUU3QkM+UnhZKW9DQmoyZnhqKFlyVkxibDhr
YXNCcHUhK3taX2AtfWFPNlBqI214TF5pCnpFUTkoVG1Wd00mYlRwTkh1aTFLM0ZtUT5oQkNRTEkm
O3BDYjxMayNRYlBhcHdtaX05LSRlQHkyZ1NuPX0kU1RqXgp6U0dBNWNYVzNgR1BhcEhFMjxYdkFa
MGJETl47SHl4bCZwQSZTJVotVTQ7Vmp1VERANiRYK0ZzVEJLTDctb0E2ZlEKemdGNDFBbFctWHAx
PHpzS0I8KEh+cUl0amB7V2hifGNUMD1RPl49RmZzR0hJRypoJXgwKHZFQyVlamhjYnJxP0hxCno3
Oz1WPmNYWnQ1QmcqeWF1NjwoZEYwQXckQ0cqZUNuJklFeig4YiU1UlllLXo1QUYjVW57NX59IT05
SjQkZ0IqbAp6KUE5e3NUSSp5ZGE3RHRSJHZEZSNvMkR9fk5UdT0ycUtoPmNyKUs5PSl4OERLNGtp
eTRfZVBvSyVGKlprPyRTb2QKem83V0g4WDNIfSReVDloS0BgTzwkeU9NY1ZufDZ0I0M2U09nYkRH
MmREUXl5e3BZVkVRPktAQldsNGVOYD89JWBACnpOP1RZT0soTlVrfDE+RVk2e1RqfWNPezBWaGkh
IXRYPztsZyF6Un5lPS16M3leOXx2QTxxMDxLez47cXlveE8yawp6XmpgJStPJipfWjs9fkBvRzcm
bHEldWVGPjgySjJmdmpINTFsKXY0OHcmKGxKM09GKFlCKnI0LVY2YXdZI3Z8ZyQKejRROVI0dz9T
OyU4Mk9PdmgoMk9UeCtrKWc+Nkh+eXdPY1I+MjR5c0xPayNLRCE/WVlyakZ2e31MaDFhOGhxdVJO
CnohbVFkMzBZfmY0KU5FSiZBQDR+Qi1POWRMdkNIQXZ7PGl4K3pMVl9WUi1Wekp7P0syc0h4WnZJ
UUNUYVJEVSFzPAp6S2lLZWd5O1dURjAyLT43LS1gP2Q9Sk43UGx0ZiZTQlJYKGQkUEkhOF4xUm58
YDYkUUBSRigrYExGKGs+Vih8U2YKem9ZNGcreTRVbyk7RG00LXMkMkojIWpOZWFvUDUzViVgRDN+
dUYpMzF2bmIhUURBVjJ5T1AheWteQVV9PTE+fVpkCnpxKG9tPSVwfCVGMTUkRiZlUjQjK29VRE9H
JE8rTVppN1E3a00xd2JSaXg/dCRYfFB3ciYwU215OX5XKFZCUSM9Owp6d0Z6dV9eU1BgLWVvaGg5
Jm1iQWEtalhvfGhsZ3Fzays7TUFsMVJ5VjZkOEhXS04jalJ1I19XV08rfjVTRjJLe2gKeiomblVt
UDlgKU9ldzlZQGFeT2dBQmJVNnhwcWVBV3g7QCkkVGdsbERHdDlOUChWeiZZO2VgMjRETz5tX1Zk
QlprCno+dWlsQWY8Jjxwaj9eLVZubCNpKFJXWGxHWHxUYEtfT28oRUN0Kl9RIVU+Kyotb3BaKCVr
Ri08TEcrQVpYcG5NeAp6SkVxVF97PXJwanh5aV8kT3xBbEU8bG97RlZ4TjhTPHh4Kjx2WVdhISE+
MXZlZ2AzMW1fME1IcnJiLVY5UCNNXlgKencrQENHPH5aUlBxKzNpMTN5IVQrZSMjQGp7M1kjNGEt
K219a3l8WlB3MWtLbFJwSjc0YXwxQ2lJYDsze0ExbURSCnozYCFtczwmUCZGaV58Q2hnRENGQWhm
P3speVIkX2EmNzQmRCRFST5kYzVGaiQtMz1LcmN4K2A2XjB7X0hxNkxCcgp6IXYoO0ZWQ3RpNHkk
ST84endGZCg0e2kjZEd0YyhaLWwjbUNsRT8xQ2Y0TksySy1TJDVAY1pmPUVhPEtPP2JVSW0KekU/
bj9oM2VnRSY/Vz9KZTFPYWF9V2kzfkgxQzlKb0V8QEBqJkpHe0F3NkQ9eHttMyRWeEZ4ciZ5RTRf
akFEI1VOCnokfDtlVkI8fHRvUjN7VGs9aDlRaFp4cFFzSz0rRnN7cyY3I0hTPTEtUis/YWZvPD1Z
dDJfRkxuJjJSP1RLYUZsYAp6RnRlTD8zJlNrS0h1fH5taj5NX3BAZ21ofDtIOWM5Q30oZC0xOStA
bzdVJEg5ZmoqbCEkd0xKMWU7bldURz11bFIKenFnVk04aV5tcXYlK1JCPiFXPHE3JTUmQnlOP0ht
bDRQX3Vybm5nUXwzWS1DeHF3c047JENDMGxOVmI0MDxkYlJTCno4SExxalZfU2AoSD9GTyFFPkp7
YjxzTG0oJmx7PDA/Rzg0YlFwUyl6ajl7VTVuPDdlQ0twP3IwI0ZPK2h2YiZZYQp6cm03azA2KFoq
Vnl6PUxJOTNkOX09TEZxcmgoS3FBJU40QmhpMnpsY0xgMD53LTZTRjdPODklPXlWTDkza0Mldm4K
ej43MD8wVWd1NkJOUEt9dHt7KiktJVYlVnMtTSRMYj4+TyQrVkt9SllYQ2ZnNiQjbyhKSHhrdHlA
bzEqTDFiMTgxCnplTkFne0RfK350MSNLTjZOTTZuZDBiTVEwS3lPRFghbWxJRHZxPld6ck42az83
I0FHPVJUaGFRLW4wWlVuTW9qUwp6dmNPPWZhQVdkR0wkciF8TVJhbVVZfVRLRjlAWUEpUGFfOHxT
a0FKXykrK1NCWG9mRmlSSXpVSVVxRGl6TkBZWCgKenhTSzVxUmxZVloyRDs5dGRUWTFjO0hlQUFS
Z1JhMSVVd2lEQUZNP1JST311YHhkREE/N1hQajdeMmFgYkVgcWthCnpzT2A3Ny1yfEVsNkE5eUFZ
YkxJUzleU0lMUnhiXnUzKz5RJiM4KUwkTmEmbWZ7MEw0Rz01VmBCT1ltRilafEJ+cQp6bis7dFF3
Q05YRTFEK30wXiYkNmozK192I0NKTCZvUzBCNSs2TTkqfHNUJEljPUdjR1ZjKTMlNUpofnhldmJ4
VEAKekVRSHxhZnQ4SmhnY1lFNC1lPEdpWiVKTitPflIxVDJoRWBPXkchSU9ZJmtnbHUjfExlP2Bi
MDx4cGV1JEE1cnhGCnokY1V4dit3VGNuY1JSckhIRzl4bXVLUjlQYnh9UlRCJE5NcGctRGxVbVZC
UjZvV24pWTJUbCtqdyYqQyUtbCljbQp6ODF5ZFVZOyNwYXNJfUF5PWU8Iz0qckg1RSlFYXtSYUpE
e3koZSo0b05xfVRLeGdVe0BeOzhsZlooe2JfcT0rVncKemhJN3phS3dQbU1oS3lSQz5BOFRwK1Nz
NFd3Ql9wSXU9JnU0KnwyZkA5RWN1YVZOck81JC1QPSppNiNJIWVzUWMkCnp2N05OKWNxfmFEOVE/
aUlfeClaYVJeIURsRDVSKDlNSTFnRngrQmtUZzhRPE50P35Fb19oXiYoKlFYeT1KS2B2Nwp6PXlh
dyZldG9wUWFCdHNBLTYoOSpEUHxrP3h1VCM7WG1efl5yRTs1WnN1TXdtNTx3ZEBmMjs3TiVHM2BR
XmRSRVEKeiZ+JmQtSHJXQXdJViVqdXZqe3lgTm9uKWB3bF5wZUM8KVJvRz9VSWYlN3VFKjZ9c1dz
Kj87YUBaMTl9e05LJCNjCnowZTg/JSlGIStLb01vY1M9U1ZxP0hmcTBgNXFLYUhsUGA5SmtiZGo+
WmFqelQlSzsmbGlON1Qhcz96LTxqPVJYUQp6NCMxU20hLXZ6MVZJZ0VjeFR4KzdUSyNUPWNYekln
ODtGP3w5THo2ak8wdiE3NEZOa1BRIyVDX3pOO2pyZmkwVkwKemRMbk49YUg2YU8/bjUqcV45OHBu
cy1GRCFBe1M8I1cqWXY1e2l4fmsjanA3PTlWeUI1cWNENzw8Nzh0PXVzUVJkCnphJWFAZjFfa3hJ
WFJLRG9Ab1o0eUNXYVlxeV9VQSkqdEltMFh+IVZ9Pm82Zj4qUG85LXNPJWJrKmtWbEpGIXVwMwp6
K0xBP0BCdDhNQDQrYlBnSEkjOWQoeEM2Jnp+RjVIVlBvQGFgY3o8UTFmYHVHdWNKJlJPMnlFS1Bi
dkNleSNQcisKenkzSHohTF4yTzw7I1M5LWF7WkRUOVZjdkZZP3pkcD58SH5ybH1mMD4+Y19yR1p7
U15HK3FQPmVHYndCSz1qTTdkCnpyTHV7bjxsNz9ARHVtRUV1bztgalFpeWU+WEh2OUFgS0pqTEdf
Sz92REtOPj1tMDhxTnxJNHEmUU1+I0w/bSRrbQp6Xyt6czNrKWRrS3hPfkVAUz9BTnNMU2swPzM3
SjBMckk4Jk5ZeUUrekxVRmx0a1lAIWE7akRqeDBZVHclQzF9VmoKenNlb3VmJFkhMVRvQWA7dkBq
U09NNk9xc3BaWHJISjtBV35RJiNIblVmODFVRWRzYmROS0MxJVhhJFFTJnBJUyFkCnpvNVB8NGZO
Ny1OYlR9Tz5BQFlGUitRLVY1U3cmU3NzTFVFVyE4eTlYRlZfRSU8RDFuT1A1NXBrIXozcGJgJi1W
Xwp6bG1hWE8jO01vQkZCR05fSzllKFF3LXhIc1dEfjtUQW41V2A4YS16fnl1VkNXMnZqYDsmVzst
PTcyd1h6Szc7NF4KelZWblc5UkJ0WiRTMko+PlBrbzcjI2RfNnI0OWxAdTMyMm5JX189PE1ZRjxm
VUJOXlFja2JUQSY8c04xMiFoeVJCCnpqNjlzQENJcVRuQHRYbXdXRj1mNlAwNjcmWVlMUkNobiRz
Uj9fNk0oSDJ1bEslWW9wQ0hmMXNTNVN1WkApSFBkQQp6eSQ8PygrM1FGS1RDPj59SD1ASXJYZX1D
c1pCJUpfO2BASnB7VUo1THNZLUR4VU9kej8qQkZoPV8lNEM5aENza3UKenFYJkdScnVLSCk9ZUdU
dW9ILWxLU2VqZCtEPnkrVUMtZFAyZXU9VGRIc0E8QztDUHE1MkJYRXY/Kll3Pik5ZlB+CnprNlhK
RDwhK29wVEBDTTh0UTxHO0Nec2tjYFB1MCVzPSVOTUU+UystPyRsZzgxKXxXLVMoVW5jezRiPDlo
Jl9yUAp6M281eW5MQTxMOElOK2FGWigpVlBzak1iRmNTRHVNTH5+UW9rcllaXmlGPTtpfDFIPSFM
cklKYG1UdVdCaE5OSioKelY4I31raHg2OGUmMU1IYzNEKFNiczFuYnQ7Tk5Nd2h7YnN5JW9tNFQ5
Vnd1TU9vYyZJQmRKUjxULWZ3eHJ4T3NUCnpeek1PNjM2e1EzMzZATCljVURVcm1HXmlGKSYqSDhr
MyVLbykoVXB2KEhDM2B7eyhVRGBSIVc+Zj5MK140QVN6WAp6PnZoajYodj55ciotUitOIVFuc1dV
PHtSSVViX3pYJjd2dlpHUDRJOCU/fUp0K2BrRklESVVNa25BQmJwdkZxMW8KelMhaz1YSyF9TDl2
SVNBNHgqdXtqaFRVYzBjS3pvfUtiZDcwb15Qaj1WTEElSVZkRk18UEVibTRrTHhxNHNVVz1BCnpQ
O30/JT83ZlMmIUJvRGItP0RgU0dzWVNtLSthcW8xRVhSaj9TJDY+S2UrOEI+QFheTHN1Yj5YMWY8
VWt3ZjNTKgp6RU0xe3ZKKUZeIUp8PUFGTmFjcVE7RH4lJDxQRDJAVG12JkRqTk40SXdlQiVZWEF7
ciVEOUJVNURIJEd0MHc1P0IKenF+LT1rWX1XdjN0RFc+ZlQhb21GbVIxNHs/LWFUeGVpUDVKdEFF
PSp5T2IhRE9mTGsodyZVJnRRaHwrY0xhLVphCnpPP3cpJkEpeVpPbE8xJS1GYSZ1PyNyUikqLT53
cXtZZFNKNUBNRFZvTk03RXUzd2FXRWJWVkFjNDlWeytJfVB2Owp6JFo4cnc9fGhFYmE0d1U8emZQ
VyFpN2xKPSk5X345Y0wkP2lZMGJNM3Njb0spP3JwSCtRfm58WDJsNGRMYyF2UFoKejUoZDJoZTJ1
MSpvZlk5MHZ6fi1fUlNBcU0yTDdYQStySWcwUFZZMG5BV0NFZGRpMnw5MXxnQCNoVz4qTVR0dV5e
CnpWbjw3TSF9ZWY9QzRXRGMtTmgrMjdnJTRzJVNeR0FDNEQ5d2BgTyNgaSomTHVHdmdhP2JiQ0sm
UCpIQX12fk1wOwp6Q3drQz4xezdRTWpARH18KHpJUE0hMjUpQkElcmM+PlEkV0VVcTU/YDJ2Kip8
OEApY3U1Xj83R0xkd3R2Rns2RUEKejBCZHNVbUFnS2lTTl44I2UlPnx4UkgmaE12aFJhPiswRU1s
ITwhTTlDRT83NCMtc0VvUTlNbVM5c0hCKnMtWn08Cnp8TUxLaGJuLVghPnZ+PV9xdUZaTXZ2O2RK
ZFZNcilNKXNfKHEtY0owMTx6cEtSJWlkbGQ2YnN1dHNZMnJRaH41Zwp6KldIM2wyR1hBb21pdzFW
KG52bmJzdVZFJilFP2k3Q29jMz0jcz8yd3deTG82cn4yVTlUI29SMmMzPzZCbkhUPmQKej03QVVX
UX0kTmB0MTEmKT5udkwjeSF7O1R2XktEIVQ9aHVOPjIyUkcoazx9Uzk2eV80c1g3NCtuOUFuZTxR
SEl0CnpgIzZPTFkqdntpd0lKbjUxXjViJTxtOGVwSkFFSzVQUU80JnAxTkdFJkZTfWpjR1JkcCNT
WT5eY3A4el5WflBxPgp6dmFpKEFkMy1CPjwtRiRxIVlfeHQ9Vilkcnh9X2JHbyNBXj5WaERKYG4r
OzVWZlkxODM5QEFqeTRIOzJ7b3VhWnoKeitFMVVNQnB8aUNXTyh4JXc5SV91LTc0ay1QczhUQCM5
THxtLTY5eEpRQEV8fTF3YWomYVYqRD03QHxjSEJQWGh9Cno1TEtXNyElZiNDMHdOYnRxSDI5cGMy
V0RRWVIrPjVmaHNTfjtMMnAmZGRaYGIxOGtoMD4yQEcmI3lwXjJkRXlwfAp6SlNqRCNreG9jUWY5
fm1ITkpoKygyfihxJHNuMjlrSmxBKjJhcnMjaWZhR2F0UTQ3REBhPHMhTU9yYzRoaFYxK2QKeiNn
YHNrZlp4NDVsV2ZMPVV8S09CO0NydksxJVNBKyMmUSV5e0FOSFN5Rzt+ckZBalVEcVIzOzRyfEpM
KiM8bX5kCnpIaThrVEpwIzJxbDQ/cT0yX1lVZzZzejkpVkNNZEVUMit5Vkl4NGlvJGE4JkVQPWA5
Z1EzK1N1Nm1ReEReRm5gSgp6dnBrVCRaRFh5dEh9aFZ8S3tyTjhgfVFVaDshPlhqdG1aZVB7dUx2
WVZBcC05P2s4SHZZYXFge3FxPkJ6OWU/fFgKelItWjMyTW41RCokSmUjOTA7Wng9MChDMV48aWh5
U28xZjQzSDlDSHRgcWl5NG9zeDQ+a15udVVLLVlRKXZ8PCFmCnpKOWNiUGohK1VgIXR3ZGxGVVcy
P3xBUXFtZyp+KkJnOG16NyNsLW0hbTg5XjY9ISF1ST83XmhMQnlIXnZKSD4tQwp6RStXV1YyX3FA
OU5IWCtATkN8dl4pMFB4VzBOQWNXM0hEKX1ZdTZwdlckVGUwXmNjJHlrK0l4KWlkKE9WZG5BcFUK
elJAT3c4Vyp6WWAhfFhKZV54ekBuMTd9RGc/YnNiN2NTbVM2ZEZgcWFGK2xMcUxLJDBvUlY8Q0Nj
OEslMmt7eHhSCnpNM0IoPHZVPXQ2MDFgUEElMyktUmohPGktXnc9KGEyQiplR2A9QV5LUHskNnAq
MFk8TFVkNyRRUDVzRT42akE2Qwp6b3hEdlRXNygpNnBRPWE5T1FRWkBFP0M5aiV9V0ElX0ohYjNj
OT9sUSE0YypYRGNKOXh1N3k3MXJkODA0aiZpS3kKem0pXzNQZF5SV2MrPkItQ3Bme31qRC18dWhp
JUojNzs2SFI5KFZ5WDZULWpMO3hgUkVVN3lCXil1cFhJPVc+Tz1wCnpkS1pgY0UyWFdIS15Wc2Yw
ZGxuNnYtbzk+aX5ecilaYTVTZm1IM3tpeXc5OTUyNi1MKj5LVjZqe2s3YTFPNiV9Ngp6by1wTDxh
N0NGLT5hdyNXVX0+QykhWF5XP2l6VklIQmU7bUhLZGljRG4pSz9zV2IzZV43KWJAQz5YRyZhYU08
dkwKel8kdjw5JE1mX1k5PkQ8cyNhaU91ZDJuaXVDJXE5aiorRjhHWnN8bUdefCZ3QGl2WT9jPGJR
XjJuaGhpSVg1WEJ6Cno3KTxGN2trV284dUMoP24oY2Mzbl5Ram4lR1gxUTcraEtHb1g+R2p3VGM8
X0ZCd0VDeF5oPGJJUDchfituSTdiSQp6I2p+QnYmKGs+a1NfTkFXZmROUk0+R0dOQGJGNUJBa3h6
a3JBbjFaRTxLTTVDSyZWRnx3bTR2YzYrQEJkZG9adG8KemlYaD8tOXw3VHd3JXlPQDhCMHQqdk13
JH54T2pLNkxeYz1jezN1ME1haHlYPFdkVG9PJmVIe2UpeC11WUxYcUoxCnooRn4+aChSNUthaVdo
P1hfOTFHbShQOVR0NE9qNyFnenNiXjQmQFhvQTZuSDtYXlpPRUZHUzgrYiNHPnFEdz9JXgp6dyQ4
O3xAPmlrZjx3MEBge154c1NMUWpzdEcoY09mITEoTWRWfWUwS2RTYDVqRTx7eHYhRytvP1ctRVM2
NDFLXmUKekl6I2FfMD9zeE1TMFFWbTx0S3VqNyZzMmJBaGpRJEdLJlFWQ0ghWiZtYDI5QkxBdVNU
NEUkZihrSE5GZntRWCRMCnp4VzkjbFcqbWN9ZkdOS2k1UClkNWFgMDJqXnxFNCRwR2c2PEhnTTJj
JCUkNH4pemElZk5EZkFIVEB9ZDtHWSV4Kgp6cSF6dyVuWHs9Kj9JSzhHKDFWaEIjTyVfMEdYPE5T
JjUteX5jVlMzY0RPZHQhSVRgPSo/e0E7ZXV9KEItS0ZDUzIKek1kK1liJlNGQE55SmVtPmtlX0dy
PmJnK3hzJj0+YjdAd0J1YXcqNUdWRXQ/dDc8b15ZOTU+TH1VMmdHVD1lRHFVCnp2ekxzYjAmQWtL
ejBMcCh4JmlSVzRQT2xfZHFaVH1oOCtfQiE5XjJ2QHNmKXkzdFRSTFhGO2h+UVh7eXBOMDBwVgp6
WHclakE2PnNfJDVudSlgKCtnfnxBeXdRRm00c0BXaGpsbEFqP35xQmZxS0Y9UzdIM2clOFZzSHh6
fjEkYHF+KT4Kej9ob35EIWAxfWs/Nmc3YFN5QU51bG55ZEBaTkA1WF5LPExSMEtAakhvN3BFRVRs
WTtRSnsmZjQwSVhJMCl7PTdrCnozIS08dEs7ZFcqY1FITlg2WSNuP1gqK3lAVGA8LVhFbkItJTln
JHhgWCp4eytvUnFGK3B5bW15NGRaJDZjdlc/dgp6ZlFqfnpCYW0xTGxVYSF6c002U2Q3WnA0N1kk
ckxKaD5xTFMrJEF2VSNCRCRpPnEzcE0ocH4tQmJmZkpYP3I1MmwKelQ2SzUyIy1zPkNLemRVPXop
Jmw9cHRoIXRrbnVya217QkhnOTBwPDV1fDU8PUA7ZCpBIUtgOFJXaUhUIXZJSnYtCnpQVVFYSjE4
QXB6dm4pektgQ0BsR057I2tmUSp5UkljS1JEUCtZKFlpc1c7c0RNfGMkSi19b0NGUGg8Z2lCdDBn
NAp6Rnh9MGVkOVlCS0llaypJKEMyNER4OEh9alJRe2s9IWZyfGpQWjMhZDtoak41bncyQytXZFcy
bHZ0UntmO0deN3oKeiZhejU0S353ZVBYWio7cjckTmI2aU1FdCU+M0BmO3lMS2U/IVFhaHVZTlBE
ZF9jc3p9cjRjejFnV2o4Vj8zbnE8CnppS21BbUt4MHdgMjI0TWsjI1RQJDRyano3ajc8NnZycmp7
K3ZCejRRMlQzfVZTcn1AZXZwcjtGQlJmZlRjZ1RwZQp6MExfcmo9b0pnVmhgPzs+M1YzUnBCWXU1
fCZyPTRtPz9nX2kweXVpNlZ5d1FkWnlzNnUxcGhze1hiJkFRIXZtTUsKekwoJUJgWXliM2NPQzNs
LSNqZHA4e3F2TnUtRVpCa0RqbWVTKkw/bmZKWjg9dFMqQUJKP0VTZjRPUyRofD1ORngrCnpIIWVj
eEQlYUhMOFFlLURXNDlfUldaR09Se0ctM2UwNVIoWHshRGk4SXtaRkslb05EPT1UNHwyTCp8S0dF
dH5NTwp6T2NWKSMpNk1FcHg2JGJyWnBxRV9OSSVDJlheJUJ3byQkZylTVzBlPTJtMUFNWlYyc3hq
TTAyIThiY3dxcno9fVcKej9KUkNHNz5fTlNjMnQ2QGkrcCo2NFZZNlhnRVoyVWhabyszTGshPDdO
cD5+PW8jQXBCQSZ7QUtWVHpITmVMSnw8CnotO0xmKCN3azNEbzkyemU9RDlXTisjenVMO1RIbU5w
JVpNOyh+NlYmbHdtYihXZ2kzWGR2aCo5MStvQn1NNWc3PAp6TjlfUW8/a3duP2h5JiV1WHRePVhH
fSlXM0xfUTcmIzQ+flhGXklsUjI8UTZtcEhrOE8xd1ZuZmRzT2gld3Q4Mn0KekVxWUt7OXFUMGk8
NyYrVF9BamNVQ2gqZHk5U3oyISVeeWBlaXk5T2JLcUk9c2pFYSo8XkgyYUFGLS1KOCNNQyRHCnom
Z3ImdlYzXmwqNjxrKkh0ezkkcUt7NTsrSDJQcE4/VEpueXt1U2QzPkMtWTtLVSFNVEdzUXRUQzI8
eX1EYitoKAp6N3FOLUx5ZElVITg2WjZhVGVpJiN5Nj81ckhqYjgjIUFDcX0zIzN7U3c4RHApQUJm
QTxoKjZVblVENUEjP2lrdHcKelRvU25AeCVTX2p4bHQ9MHRfISNNRXBRfjlLMyhhdSN4UFFERjM1
O0g4QyljS3E7Vj1DX2xqPmpoa2xPdlFAaFdhCnpZWnsxMj0qZD0wdzFEREklanYrJCRjKmM1KEhL
Sjc3UGt8NyY3S3FTd3tSX0FZI2wodFRNVFF1NHVPWT9MbiNhOwp6ZTBEN3U3P3NQNXN2KmY1bzVs
Wm5fbXxMQnQyNDFjTGRRe09pdCUyYll9WGUhaVEqVyt5bFMjOHImaEY8QztIejcKekgrMSh1LW1U
V31uTGlmXzZJYWZiYzZWOzhwTVIxYmlSQD5eYVAjLXdHZjRTKm8jWWdLTVlTS0RBSm5RUnRvb3py
CnpqIWEkTkF5OHZBKHVwQFh7ZkkjQCR+T1AzOD52JkB3VnQkKHJZS09uPX13Y0k3SUJqIyp2NWI3
PVBofFg7fTZITgp6NDFXTy09b01pTXQ1IVNmai1DXmFjQUY0WWMrK1coTVRucEV2VHdgam1jSkhL
dzwoO056T3M5ZllKKjtiWSVEZTAKemI/VGVxZUNuNkxvPUNqSiR+KX1+WWo9aG5xPW1qSGVER29h
Vy1yO3toP3xQd2lyJDVubjRvS0dUI1FBQ1plXyUmCnpDfGd3ZnFoYy1PMXhMRVApKVgkeVpaWlFV
NHhpKT4yRjclP0Y9IT5zWXN5Sl8rdG1oQC1XMkxuQlYkciZMXyhTOwp6PGomQlp7JDNIKlFWd2Yq
aThId0hQQjkqRCtiK08zcDkkczYpfiFKJistJHM3bFRROTtLWCFZXm0kLTFaZHkjMXEKelQwP0pe
TTIkTlhtVE5rK2xUNVctLUB+NX00MiY/SHB8RUdnIWR3KlF1K04+O2pxQ2JwJCZIfVFlQClMQkx5
T1h0CnpNeE1CTGNCOGhMPGo2MjdPQmJsVW9IRnQ5Q0tRKGw0Zk51WU52bn1JRGlEWjJ1RCtje0lf
JWF7PCoyK2BMYUp0dQp6eC08TDxIdzNvXnZoPnBxUkx3R2A4MntxZFE5SkhEPn1QbFh7UyVYfDhE
c2RQaVE5fihfcnY7O0g+VkhXQjk9fWwKekNmPW88Xi1uQ1p1R3EtQlApNWgrd319NFMpem4qVEF9
X0FkSSlxTlFSfEtRXm5qfGVGZ2BmPzJRM1QlZ3A8M0NqCnpfX09eN0tRJH1ZcE8lWSp7JDAoPFBP
YnloNDsxa0sja04/Ynl8TFladF8mMip3VjBXYUI1Sl40SENvOHZMZEApcwp6NzQyP1FhJlBnakU/
WWhWUzNPczg1PHlzQSlGPShTKGI0NlU+eSheaXtPSjUrdkpILUpkbjNPTzY5YlZWMWkmR2IKekFN
I2cxVXAtdCVMRCMpOWpDQW1hXiUyQVUra15AOXpld2FoaFJIbDhUOTtoNFNXWndvcXRsc2tkZyQ/
QGBiIXUyCnpUMFhjTXRAKXo9bHkjNmB7QUx7eEBZQ04/eDh3aX1qfSNiPWx6PipUVilael5zaVNm
RS1QIzduUkBIY0JMSn1BTwp6ST9iMWYqezJDez9RZ2g9d2Yzd148WnVLPGRrJT4wcyh7dEpAJWB2
YUdgbH5pcX5VUllZX0Q8YFYoRXFEc3xvTFoKemgrNlMhPTlpUjhQZFU4K0g5c1A2VipmIWxyciE7
RjxHNTVYb1khPHVzby1BcGMtVndHO2o5dT1CWFhpZDM7JiV9CnomYm4yNTR9e3NGYT0oOWxgWXVr
c05IfW5hbn5VZTtgK35kOWNSYCEtVUM3PnxoVDdsejVyTXEpNHRQYUAyeFYhIQp6Sm5kIU9tV2xZ
fj4pWSlCQUY0MVZOZ01FfDxgdnZnbmJkV0lqKjx4PTIjWn1qblMtSiZoNDE/fVchSSEjIXE8QVUK
elA8Ym91bChhcWJBbnlzMGMmSmdEe29WRmtjJkk2P0BsVT5aKCFgVGtTZmx7QnViYk5BPXg1dWZI
czEmTEVeQndzCnpHPEgxUHFPZlFjYG9OKDBWKEplPlphRHdwYSlaMW5NTUFHV3FhQmxSJD0yJGgh
eHhXTUhMYTkxNExnJiRuck1sJQp6dUU7TS1ZTFUze1VveW04YHZ0O3NSUGgzcnF1eDJNNU05I3JM
ZT1uVU9OSU5QayV5Kkx7Wip3QCUkbFBJR205JlIKentWOE9wZHxNamNORDAwNiRaQiNCTyFiazhU
QndGc3I0MmtZTEVzaykzIUk2YCRwZnJ8Pml5KWkoSFRgOzkwY257CnpCYk12JjktRV8+YSs2bnU7
YV5KS15+NGp5PDg+VWF0dyZiZ01oOT97KWpNeGRJeVdnI0x6O3ZOWXE0RyE8U2RZQgp6Q2d9dGdU
VUktYTwjMipAZSh7RD1tOHhULXpmQ1ZXSXw0OyhPOFR8QHp2PFFSYFRjSUBXQGRmV00hYTEwVW8z
UU4Kek1FPTBgO289bnhHeHgzU2lMRHdlMmd4OE81QXEpdmEkQSFyYnxMOEAycmZvJD4mVGY4I0gt
NF40eTxFMW1TSjhpCnpNNSEwZSFzRX1MT0x2RUVKSlZ2MihnZSl1ITwjJDN6KW09MlBLcGZ9emti
P3E3ZDFMKE5KKj19THs5MmVvdlFHdAp6bnI3VH1NSjkrcW5hYXZLK29mfWc2NjlObUt4QWd1N2F3
TylSYnFZVHM/WVlFMyo9VkRpI31UM1U3fm1hI2wzUUcKejs+NVNOIzlFbmI8aW1ZQzB0RjN+JWxQ
fEBsdlk2M18hQ3BKSnhKOCFiSmNnS1AzMFJ9dSR3QDtIRTxUP3FxKld3CnomaVpoKik4bippeFNF
YFQ/QDtecVhOQ0MwTTtfYTc2S3JaNml5Q343WmxOYiVCUiMhdHJGMlojcVM5dDdSQXxzTgp6NF8j
ZU9FPk5eUitzU29pOTclcGRXSEtJVmJzfXclVFh+UnVZanQpKkNNQ0s+X0goOzQ0P2Q+U0p7Vjtv
YHtRMjQKeiNiNzdWYFVZRU1BUElKSD1IOCYqXyFiQmNmOXctXkBebUdmezEqd3ZXfHNOUXRJV2to
NkgtJnFnelJhPHJDaEB9Cno/Q012UT4zKTVxTjReajlKRUN4KDhzTjUhWlQ9KUBodmMyKWpaLTRS
bzlSaXlgeCUtaXZ2NkZ0VSF7SiUkailwbwp6c24yfDFINXpGN1BSPX1gbUNEcjtnd29HSk97MnQ/
RU1CfjhBPXsoMGdzQz59PV44TlV4QHgqVS1aOEt5c3pxJDMKellsT2Y2dVoraFNxcUpmP2lYTlM0
YDUtSjlzdSF4cllRV1UwQH10aH1WXjtjdyNoMW9KJSNZWW44VSg1R14xKUpnCnolO1I7TUBySXV8
TTIkSFRHezBKWHM8eUYqWDBiNE1pe1oyQmNlbVVtQ3wwaWxVOSl3O3EoR2ZvJH14PzQqWDhzUwp6
cjImYj95eC08VFV1dSVGPSpvRkhGNypDZGZCZHdGXlRwQCl6ZSZxRTgxaWImVENwO1gxfTtmXkw9
c2drJntVZUEKemlYNU8pOXp2R0FFUWt2aXtmRn1CVCppfUJOXiZ+QytKc2pQXk5MIzJOUz87T3Rm
RXMzKzg5anlwST19Pyp0WkZiCnpLQ1QpcnNUIXtpS1g7fT1abFE3ZzRENXV4P3FJZHZkQz45PWRL
MT5ndUlmJGY0bmcpUF5pLWxGRypgTXVRPXh9awp6MFd0OURGXmE7QjtxNWVNU2xVdXQ8cloqJUlR
QSNiUUluUjNoPEBne19OWWBlSDdhRHJKVitRJnNLaUo3dTJaPFoKejFgT0w/TGBFMnRoI09xY05t
d3xUJCUlKyptLVdXM1dvMzBTU3slR3U7KlVpXiFgQjlETUdofW4pdkUoPF8pPXUqCnpsc3xqTlpw
YDFpREVKYko2ZmdAcCVfTEBzJk8mWHVVOXFkWk1oV0g7YElrcUYzJmNTRmYxYEl8THZCKGx1eGBx
bAp6d09rKkZnXks7RHVMUEZrVnxHeWhRYURrWmo1dzU1b0tVJiF3QFlKdmFtOUJVeVo9M2djRWBR
NCFATj8hLUxediMKejsyS2p+KlN7U3VIOzdEcHxJdlpxeDBPd3lsejlAaCMqYmh3azQkdGlgbzAz
bnA+NF9gPXd+cUhDcDhBJjJ0QmZSCnp5ZlRafj1ubTxLVSg+PFZDRm5KUntNdXA3Yj9zMyQxPUoq
Qjc4IXk2YXMjMT5BcTB8WE4mMWc7NndEN2RGNGtadQp6bEFBayQybllDbiF7eS1Hc1BMSk9wKnZ7
ZDNEeHJCVykqQG5ySjstIzJ+Uz1sTDBYWCZHZyliOFd9YTBKeU5ZIWcKemcyeHVid0t5VUMxLTYh
ZCpeNjFaSmFIPUFXc2VyZzAwd3JfJD5Ec303emlKeUBAMUNtaUFSSiZrN2xmQk1fTUF7CnoxPz94
ZT9MVXZhOHc7T31sITF3Y2J7ZVM4bkomSiVjWkFDJUJ4Nzg8enheKTx0d3s0P0l0M0dheGlVaXpS
YyUtSwp6JlAtaHxfUHlYbjFnSSU1cW1fMEZlWTF4dXFiJX53cUcjSHhYfn0yXjdqXmB0Z3t6JUkx
Pz9fQkQ8O09MVXtQaFIKenVoZih+eUA4cVJgaHdrQ144MWZFM0VANHx7fDItPzZDazVVSmp2NzUj
PT9EQUdvVTZ+dTlOYiZSbnchTDV1Qn0pCnpjJCo4TVJ1dlBKPTduKHtQaFJFa3IxRjwkRXhEZTFm
bCE7LVRweGYjKnVZYHRUTVU0bmprMlh2JCgqSCsze2x3SAp6JSEqPnYhPWExdSEqJWglcEk0KmRH
KGg0KCRob1VmKENzXzdMR0tBc3JLPH12OyYzVHxxNCU1TlVkPUsjbWQ/eDQKemhjRE8oRW5VNEFZ
cUBIZXpjeEBYXjBaKVZKdnklYENPb0VfRlZUZGJoO3FzWmVKdilqSCRFPSpMZF5qQ0heYnI1Cno3
Qnkoe2s9ZDklWUw/Y0YrTDVwSFFRQDU4dm9+ayFHTjNUR1R6YkAmcWk9OVc8KytYU1YtTjhTJmtO
KytBSGdJPgp6VVM9X0pSVSRYODY5PF9Kc0E4NmlrTnUyLU4/dUlIKWxuP2U9OXVfcS1OMW5kdVg3
cllMXjQwR1Z1bzI2YjBuKigKejxpS3U8R3F7MyNIen1XJE9NPkVqP3x4aEQxQ3IzaGd0dlIzSVhR
IzEkUlJIa2c3dDNeaDBza0c4WE5AZmA2PnAmCnpjU3RNSU5aSk9FX31gem1FJlRHJjk8NVJ7UWJH
IW4oVlUwV0lufkxGZEs2emoyYylnSkk/PXd6PndhQnp6ZiQzZQp6SWFEY1VMQHEhZilQQCM+T2la
WWlRK35eanY4QFlecEMqKVIhXjg8U2M4I0lIYUB3KSE+d3NkdHl6WFBnaCRxeHMKel5keFg5bT59
VU40TXJCSzJ9PXdXLUZQSXBaNElXZTYoVSpFblpHflVucC1pMHF3eXI3dDZxP2wmMUxpSjMpcSEt
Cno2MD0+QzUwMCZLJTJSI2xuWXFrcEVMPW1DNkUqI1E/UWV1Vl5NR012JUVIV2pFKWwyWjhtUTsj
aVI0U2FeSW1fLQp6REk4cCE2NFp7MlJ2dDUobDN6N205JHpiMyE+YFhEdkp6eHA4QUxHYGBQNGBE
c1pVZ2xVZ21jfnd0SyNzRmoxVFEKend3ZS0yUmZ0KzU1U0V3UHBYUWV3QWNrJmE3ZypENTY7X0Iw
PU5qfFRINXAzQm5RSm5lVzslP2FkZGpuNkA1YDxiCnprfGl8OyQxQWI0QiRKYmU+KXI5KHZAOH5w
NFM9fjRwa01iQFprJmpSUX4yfUU3PTl0Rl44VVBldE0qcU11Zlo+awp6XjQ4fVRnISlBel9OdTg5
ZT5qSXtFVip5dGlUeWtqR2Nna3NyQVRaNFYqaSN1JTw9RV93NWVmZFRCIV4jViYkXjcKelZPbWE7
KHpXVDlodSMpfGpAam1mcERDRV5iVkJXMUgzT3tAKXBxdGpgRnc+bDI7dTdLandFMlE9UGJLSU9z
c19jCnpDdkF5MUpLWmhQVTEzJkBBO1paJSF7MTM3Xl4zLXhFKmxrRCVBUVJBczIqME1DPmdYZj5P
KDVPTCg0X1Q1PEV+dQp6SD53MXF2MiViJmdGNShEZnB1WCtTQ0ItRjkxTjJ1SlBpamVaaUNWMCZ5
MU5Bek5zKiZCJHlYb1RIekN8MytkPVAKeiFUQnU3ZlolV01LVH1QMEl3RX50UWA5cVpmZyg+MmRh
Mjt8PjYhR0NnKWljNWsqKlIqOUVzTlg4ZT85N0VVQlByCnp3U3d3bypmNnNnQDlyWSU5XnxeY2Bs
LS1UO1BUWXoyc3BZRil5ey0lJEB8Z0MkIzYjeVFHUXU3bVU5YlZRZyhPYAp6YnJNTlI1P2AqPCok
aSpIWGJsIXdtPWs3NjE9MkZvJUFqZm1mY0BpZ14qUio3aUVxZzRWM31sIWFfT2BHITZOJlIKejU/
I09EYzU4NGowNFFPYko4aTYwLW5eZ1R6O0RmK0tFb0BhMVRDekx2RXRza2JURTB5ODBSY0l0MnlO
PGl3ZjZMCnpqdEl3QjZNM29eWD53ZmhWQEN+aHJhSGVHcWEofUhXdEdeNlYyfXpKNihwN00pe0VV
c3lAVSR+ZkhDfDJ0al44ZQp6e055TFc/KXJVbEhPQUMkUzl4QHZ7LThuaGdGeTB2RWlsYnJUaTJD
cmMyPjtVbV9BVnxpe2VjenJ6S1ItZ0ZldzUKeih3PjdmTGpYb2BfclhKYmZpfXREZzZrJjVFKyZs
RmItbE1xJlE3Mjt1Y3IhR2c0dl5jXzZMPDZod1QzPSZwYnI2Cnp5YXFoWXMrcVZTcV9BO2hEUU18
QEU1MV5LbWJqUHBQXlM/THZBdilENytVRGtYOE13ODMmQmQxMTttSS1WeUZFTAp6eypIRXorLXVn
MFVIfm9VMzx3WDBIfTRLY0spWFBPe2NNQD1CdGJANT1VbG43YD0kSzc8MG5WQmA/ZGxvJklXVGMK
eml8NHp2bCR5antKJXhWVGB8QkdkNX0xJUpOcXR0NSl4TihAKnl5TlZtfj1mRjFTTjRXR0YtQE9B
V31pVihGaGM7CnpSbmB2PTFkeUNvR3lNaUU2TWImS0VsTGRwOW1LQmxIVGJQTHFoSUBjPClXNzZQ
cWFSJnJJWCtzT2oxTlZScTZ4Nwp6I3FMaUN2QTNLaVQrfXgtJkJedn0+Y1daVUVKY1FnK2N8Sihi
Rnt0SVVlSmQxb2FUbFFQYjd5UXg9I3dkemhud0gKemNOKW1QK0ptOVIkVGlBTGIkKVlZNms/Wn5a
d3RrckA4MipOayQ3PyFsJHFOMForU1lHPWpWU2slcFUrbWJNKFUtCnpiZWI5KFQkaGgqezhnRShn
XiZYJXdCYVJqNFhoUl9nbDtCbWEoKGFSe3d9fm4lWkQtMCh2cFgmVSZvPXtBOHdedQp6V2pYN2hl
akxlVlpqLXRCRVdmfDAlUFQ3YDZIaDk2THApSmBDUTkhY2BQRD91Pk4lSy0+YHhoUEJ2THtNWUdK
WUMKelBtZGZYK0hhT0BhPlhlOEBpKHU9YTlQYl9CPzkqWDteKyVPWSNyfWxNMytBfFB4QU8wVmto
bCZUfnE3cEwzUUcmCnptcih0azdvTUE1QDZvcih5fEdhKVdzYSFBdlRyIW9rZ0pmQiU+fHhFMXp6
cUprNUBOTj08Z0sqOyVvLTdgJD9SfQp6JGBXPG5jN3d0S1VzYCFAS3ZPRlpTVkQhPk5zKj5ra3Uy
aENZaXF7d3c1WFRSO1EhPHA8K2trSXR3KlpxT19eP2gKekc3fHlDRl42Q2xyd05rT0NjRSM1YnVR
PktLVEtTd1FvQ1kpKkB5N2JDemMlNVduIyVsKzw4TGNBWnptTmRjcVZFCnpDbTghK2NxZyFRQShS
Q28jV0BsQHREbjhfemZWN3lsLSl8JnB4TH00PDRkMytsZEJlbUclTjVzYGtXUmltdV5pdgp6ZS1z
VSlTPkE7Z0QqOTI/eW5UJXxtTUt0OFVGQk53M3RJR3k4WkoyMD9oQj5IKm1LfHxTeFlBNzE/IUlS
cVl9TC0KejYxQHZZKlh2KlBfNGpWTFQmODRZOWZ2YyNWRGRAY292Yj0xQyNVX19ufjlmeTlOJTcr
WSVHQz9gSmZPUUVgVklFCnpJO0g2UVlyfWkxLU9qJGx3cVQ8JihAcUZYb1E8JFhjc05GSWNaSW1g
VC0tKDFkKj99IzdFWWx9RWpoT1d4M2p1aAp6aWNaLSpBP1dHPTxUNiVVTEBFXj5lcSQ1aUQ+Xkcj
entXTTIhblNoem94fWZwRWxsZkBoZ2N6XyomVzxASk0qY2oKellkPUdgRF98c0hBbUF2KWRfI1Y5
QyoyP2BKWiZJfkBXRDc+K3lWNFpSJGpGezJ5XzJUZiZUZitjdUJJPmBJJDU1Cno7M1V4TjFRY2o5
bklvMXpANWM9NDhrK3FaP2pITWViMT1sd3dRY1NFeC1aYj5gJD4zOytfaGRUOEZvJHp5Vjs/LQp6
PDI+N1kmMzhmZjw+aDdDS3A/aUAhQUNTS096X31XTmw5MX52YDI+bSs5Pms/cDt9OWpwd3FuOWp7
Rj4tMkpVJE4KelFYUjAtQHYhekhAYj5tKjVzbCo/MTBIZjA2bStPT0swNEFRdG14UTtsWWt0PkxG
aSs1Mkp3TikrLUlNfmdqcG9OCnpuOyV3bkp8OTE8MTFBR092a00jNV80OF4kX1lRRjZsUi0qeU0t
fWReQl8jXjtSbUx3SGZ6SzUwa2ZQdEBlRWQlOwp6PX1FO2pxUGskei10TGIzNDJPLVUlI0dLNVhZ
WSZrTGB7LSVqWlVAaDlVKjlRZlgpNzd1NCZoMUZ4dlZ7QT9VcUYKenFKUjJkNmgkIXVGSmJxOVco
RFhuMW9aTnB0WlUtZ21xN1EpaXpVZ0Y4ayhGMGh3SV50TDcocjlUbjkkS3k+NE1TCnorbDdQdl9D
amhANHB2dzc5bVhaelcqMCEwI1I2ez1iM14yOStnRnN4RzQyIUZFWjs/UUkmY29NcG5AZz9wNE8w
Nwp6Y1Jfd0VffV5yMXY9MTFGUkV7MWkoOHlIN2MlTWBAdkEtLTFpQz1rN2lyJDwkTD1FNSQrSmM2
fGhZfmp7OGReSSMKenZYZmNqLW5TVVV1aV9zfXl3Xk5BSTF4QD5rK3lCd3JpbH5xS0p9SllgUilB
Jj5lcm9zZkI7e0gzSHdVRT9ObjRUCnp3czdlemNRcUMjS1ItV3ZoeHNmPmk9cCR8MjtvZT8rdm5O
fCZ9TkN0P0d6WC04MnIlcigyQEZqWVNaO3Q/cW1wQAp6V1lTZih0KCtCdWU7ZiVhWDtDNnpwb1gj
dl4kOFk9SUFpWjRZbVMlOGgwYzVMdUlMQDIqeHVvO2c7Xm5jVWV1N1IKemFGMzRISj41WHQqK0Vz
JT5jWWF0KkdodVFoUTIxRTgoeDc0Z1lzWlg/Vko2KEI7OU99OFBoZWRtJnh9TUUmSEYtCnpDVj5p
ME01ND4/RT52cTBjfVhQZ0pGelBnY2tAamhQdTJ7JVpyNTFDWk5kYSpTPykxSUtCRDhIP2ohb2Z0
IS1fRgp6KzVYcE02a1MoPzA+KWtrWWhCTyVMfDV2Y2liMF5VLUJsbmgkdVF3e0pIJklyXytodiYm
ZmpHeWMwS2gmNnJIUlEKejRmUGJ5dEVnQmBwUFhXN2I7RXBGV28zKzkpUTFpQ2RtKT9tci0hY2g0
aUhQfkM/e01ZTURKX0pBTmgzdjR2S1UwCnptZysoXj0oT2hIZTcpbWsrb0RGMVkkJTItTklLdVlj
Wno0ISZTLVI3Uj5jaGM/Q2d4eT0rOTxWcVBvfiFgTnFxLQp6Y1BHelIoaEpTWjZaSnR5Kyohcj4m
JDhVazBWZzY9ezxxVSU4eXlZe0lWXyl3RUlNX3t4M1dtTjsxSEMqRjVFb1MKekdvczNwNm5JYkFS
KnFRSik7QUhCTVNXbXZ6cEl+QmRtbnMlPilMbzdOIXd7SHVGcldfT21sK09xT0chcGFjZCNWCnpl
Y2ZlSFpAWmglLVQzMnEoJiFOTzxBKWtZPlpvdWViKFRBMGsmeiMlaC0jV3NefmtJZHVXVG1mYiVD
NiRMblRUZAp6YGdkcylWRyQ3dXtaQH5xSU1kaGRoSztBMClYck8lQX16YnUoK1pyeGtSfDRuXypW
ZTVANnkzKDEtTzJiO3x8XmEKej4rJDtmTS1HK2BROHFmdiQmTVcrTGsyNkhARllreWowa3l5LXhT
bT8oa25UWmN1Mjh7cjtEU1hLRl8+KEdXKm9lCno2SWwqaGFxciRkODdMP1deKzdrJj8wJEZyOFQ1
S3I0Y1pnOFJBQ3g8aWIxIXBRK353dytEN3MoRWZheHI1UFFoPQp6ZTIzIXdAZmVCUj1XQEhWNkxO
IXloJldsTEdnfEpAO0hROHUqWTZ0TGZRYl9wOV98MHpRcnN4Y012RWp3UnlaIyYKelhePT0yOCRR
JXJrdzI0bztzN25Qd1k4TnpMIWtOfnNLSF5mPiFkRkM/UjF8S3hva2Y2LSNMK2RCQ3poaEh9ZWRV
CnpHYkxhUUsjMkBuei1hJCswRD5HbUhMWkVBbHNUPlZzV1lYcjM/K3tpU3dtWXRsKmttO1QqKTV2
UExeZWQhRCFoeAp6NFR3MWIoPEVyWlQ5S18+dEAhWCNBblpgTUM7IWVTNE1zOzZ7T2RfSiFeWWkr
UUkwUEVuK3dTSyNXfmM9JUtDODUKem59JTBGRj4xc091OEhPZzJ7PVpxKk1YT2t0a2w1KnBGWkU2
KU9CPXBuQiZWcW59M1h9R2gzY3AjYnk9aEUkTlY5CnozNGkxcCk+PGptZTt2O3QoSFE7ODw0UUl9
T1VKeHB5UExEMGJUfkFfRHk9fitUYFMwV28jOEpQWiZPQjtZNHJnbwp6LVhud2EwS1E5TCt5YW18
RWpae3tvRXY2PyR4VXk1JTBVVjNnI1ExQT12bm1GY1Jse1UhNEsjdzJHQ1kqZlJkYj0KS1k/WldH
QGMja2JjYEJSJAoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9l
Y2xpcHNlLW1hcmstNTEyLnBuZyBiL2FwcC9yZXMvZWNsaXBzZS1tYXJrLTUxMi5wbmcKbmV3IGZp
bGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMC4uZWQ2OGQ3MTNhODI3NWY0ZWNmYTk2NjE3NDg5NDFhOTBjMGY5NDBkNwpHSVQgYmluYXJ5
IHBhdGNoCmxpdGVyYWwgMjM4OTAKemNtWFYxMXlvZWVfa1gofS1RQlUmaVhlenwkMENSenBwOzR9
LVFCYDJBZXx6Sih4SEg7cSk0fTxmKns9YENEUEtkCnp8S2E9bHBSKSh2ZDJpO3ZvMWM1PCZiJW17
YClaXl9PaGdhX2s9fDhESiVBdU14UChJbGM7TWVaLXtEZ1RHR1Ytbgp6UXF1RnkqcXJlKGYzalNR
eDNrS14+TkdMQjdufEEwc1ZMNip4QUEoZUJDKCpMbUZHTGYrXn1DRmIoallsIUxRcSMKej9zZElT
ai1Qc00obVA4Kmw/MSlEQiR3SEpaUk5FNz1gNnlyaTtOSHpBbEdiUV4hP1l6PyEmVituWW9rcm9E
SiM3Cnokakc5SyRnckNqYUl1I0YxT0pOUHc7JjJpTl9gR0kyIVk1V2BVV1lZUDxwYCg1RSNIdWZk
ZiVlPlJ4KldhVWMtSQp6aVg7I1VnYCRvOC09dz5NI3NkVC1qNXVrITN6NFhZT1M7WFUmcyZrNEBz
bmdrTW4xP1Qmd3Z6fWtCaUFOPUZVRkMKejcxQHFeNTA+eFk7d1pYX0sqRlJsajQqWCgzRmp8enlR
T0BPQTZHbE05Rzt4cj5FT0NtRCk5YU9CVkZUU2dwOXR2CnptdEM0Y3tzeDdvUncqODJHOFJgP0dD
XzN3SUk7K3JGb2J+O1J8eVlOcUpmNyVDTnYjRXB7P187eGJ4P2JjTFMzSwp6JDZkWllAfFY1b0dx
dHVXPXd1YEdjdiMkVD8+RTZBWnBnUT9TQzRCOVJuOERRPThEKCY7S0RkJUIrdGRMdDVKTG4KekxY
RjQwIXxea2w0P318b2w2P2lsYnEkaU9ePnl1T159fnZoSXlBSXQxPEx5UndyT05xYG5oJllkVi05
QDJkJC1iCnpXS0NWRFdQVCtJNHVZT202KHQlQDB0XztlTFh8U0Y3MUVfSzdpUXB5IyMydiU7b1N8
ZjZtQnQzdThZTzlOU31CJQp6YCNedGxkfCtWc2NyYzJPNis2aDdlV0VGbXF7S25TQS08ek9nfSM+
VEttd2ljIU9PQHBleX0ka1ckaUMwJG9ib0QKel5rO2c2MWhAUCFrX30yayteRExeeitAIThPdGVC
KWtmYGVCNnE1e35ecmxKaGFKYSNYTUJCajZSOzB+VlI3cGYqCnpoT1d9aiR4R3s/Y2pmaXE0U0Rv
PjJZWXt9JXZnZFlNST4xVTFIb1AtajYqPmFhKWR0SkZmOCVCVHReMz9lSytEVwp6KWdzeityT0pK
dUp3fnVlYThuVX12dkF8S1dHdjMzc1dWMDdlRypacCghOWc8Z1lMRV9GU1Z3MXJNLUNpc01LSG0K
ej9AdjB2SDJBSEwzODgmUEtScFdLNHBxZU04SEQkODskZno1O2dzUSYlPn1Nekp+Uis4YWY+Yk9e
M2ZFZk5+aFFVCnpfRzhlTlg0aTxOTGNrKzNFMFJCK2dGeUpMcnRwJj1Xa3YkUj0+bCNhWERXc18t
SXtPdHZgJndlKUd2Z2BMMldwTgp6elFOeEc/fnk8Z1JgN1lxeW18a3RPcmZBei05SnhzPkduVCRR
U3N8XmFoIUI8Mih8PjNBPDE0PGx4UE1yU34kSjAKeiU7PEJPa3ptOykhU29FYXFlX3BKcFhrSFJi
UWZjdzFBPF5Lb0pafFlxNy1HMV9HdnNtbzNIc1YyVztURnVeQXZ8CnpEPENkSzdsb2pUOyRYQSE8
dzBuSzRPK2hGdmtvMXg0KCtwXm4lfUwjZE1yTEZsbitgP0Y/M2NIQSRaWHVnflJ3MQp6UXFOe28p
U25zXkFJcSUxYDI5eGtOcCZfZTV1UD8tZ21TcDZXR3BJI0diSXdxe0tOWFRxZDJwcGNmRUR4KWF6
SmcKemk5P3NfXkJweEkoRkIoKjkxMl9zJTZETmY0bGkrTmdqe3h+PHVgcUgmPXpyRTtOfHx9VjM3
PEI1Zj5HaU19Unp+CnpaYWhIPF5sXmwhek1VKzZXXmx0QDF7PThld290YXRjWHpRNWZ+Jl85NFp4
bTNsRVFFZEtReTlIdnh8Unc/biZMPgp6VXkzPXtQcChMMG1AKzMpI0FjSjRhYH1+SV4xUTMwZDl7
cGFLKn5rY0JNKW8yO359JUBEakckRkJxZERXPTBqb1YKenhkO3I/eklfem4rO0FCRnUtYjkqeGdV
fXhpPEpuRWt9T1E+WjktJkczcmhGSmhfI0JCN2NDM2YrMX1sVTErdHokCnphZ085JSU4a3dlN2lC
JTBfJjY8MXEoT141S154NDV0Y3xEYlZzb1V8TGg8byZsdShHNSU0MnM+czVBNCoyXzFjdAp6WVl7
VXxacytmIW4oTUdXPGchbFhNeUQ7NSFHWGA5VkBaNXl0aCZpPDxkJWNIYWk5djRDVG5uZVRUUFRu
KDk7QmsKekBgT0dhK18yOU9FMVRHNCpMb3dsRmgraUhMYXEmQ0FjMmN3VkNMa3ZwYCpTcl4hQVI9
KyNgUHZCdXhoRzh1PD5qCnowO08mZzZBNF5qS1luP2lVWjcjfll4ZGtCOF5vVH1nKCZoUmZxSitR
YiEtPU5ZSkJIUWdVIVk+TG1UeUYlfENfMAp6K1pVOV9SOGdvJD0wMWAtT1A+WkVpWEFTYENWcmF1
YzNHTCNKOH5yezw+Wmw8Snk/aDMqcEMkSlliamhfZW0yfHUKenlMTV9YJXVzZ2k2ZW5YXjRXKHl8
dEVBfHFDMDZ7PTBZUiFvTjxNcUlwTTRxQm58eiZCZU0/TnxDQkdRLTJKJFUhCnpVYTh8VVleWGt1
ND8+JE9IX3dyVztWKkNeXyNLa0NiMzR+alQzUkZoRG1IIVJteVA3LWZBa0BfcTg2VTs4LWZyNAp6
bHAmO1c8b15CUVh4aFdjI147RDkkU2t7P0ZiSVc4PjlEVkFUbFplU1MtMjVaWUVwbTlYT2tVeD1u
Vnp3NGF+dyoKelhyTmY9UHQpbzBqczhwOWkmT1MlWEU7P3MmRHJmMjBNUnVsYUVCIXc8fl5sazNi
bkZOTCROMUkrdTUqekkzaDtVCnpxR1UrdFZzOzkrPitqSmk9UmFIUEMobTg5Z350QnlBck1mSDEh
O3woYkl0VHQ3dXQwLSE2aSFwOW1KZHpMeSVKQwp6UDdkS2d2cm40I0ZScjtYQUZLb2QoUEVvUjZT
N2FFQjVpUyVEOFBGYkpuSlNgU1p7NGxYM3FwMUp5RE94T1d3P2EKekZTOUBiblZGZSFHMGw1YjR3
Ris7XmtARzVKa0E/QGgmPTZRUmdWYHc5UGs0KkhsSlFfcTNoPD5KLXkrYD88PXxgCnp1JCt8LVhh
JXYkdjc/IXprTWRAN0ZQbHUrXntPMElTU1RzMlViZFFKeDtCKkpEeUA0SzllX1hDXmVkcExkdEZ+
Qwp6KT9SfXNGLUt+MSV+ckR4TGR9PXZYNCQxM2JFYHQwU3xJVS0wT3hZOG8hTH1sXiV8QjRhekEy
cTtpfDFTcEFoWUgKekN4V09qcn1xPyYtVjtrV1A1Szc3XyN9aj5UJXU2UGd6MF5GKW1feD1HSHp8
OypnWjdiNF9BPjdRKCtgcFU8fTk5CnpSI3NON2U+Nk1xe2hYTztWeiN4bDZePTtsSTgjQlB1SkpQ
UjQzQ2NIbUU+Tk1sVmd7SnMtLWdmWE9OKkwqRSpFeAp6NlIoWj4lbXc8S15VeSF2dCotYXB5bVly
dzw0YWNuNjImMkl0bz5hPm90NGFfbil2byNZY3tFTVUmZSpMRHZ6YW4KemMpJClUeD9EQkdOKno9
O1VtbUQ1JXtIbD1vfVRJfm1QU05JTWtqTCswR1Y5PGpNO0JDb28qTmspYXxzOUF7VG1zCnotP0tw
V1RlVFl7UXJnKEZ4N2RSZHxNYXM5KzVsTzYxZm47O196JUJ0VzdUSUhsakZCU0NPJEo+PjxCOzAp
fSk4VQp6dSRJNzhyfExleHRAWUsqPjZyPFdwRElVR2wpQ2EwdFlwM3A0Z3ZTMkhzOVRBIXNiN2p5
RWI2Qm1pOW5EOHJISE8KeiVJcVMpSUZmMV9TV3tSKE1IX2A4RzlrYUpILU8kO0dPTXZgYFNHPj96
NkohSDskZGMkJEM5SFQ1SlIpZk8kVkR4Cnp2d2o7aDNXdUl2UVo/ITlsJDVrZEJsY217Q0VfQTN2
a2Y9NHtDMWs/Nk9DYD1hM312Vmd8YU83Jkd3cFNHQlh7NAp6SkBpfmJpa1puWWBEKnEzd2NOaU1o
aGA0fU5JVGEtVElXMyNXVVNEJWp2cGM5N3RvX31ITnJeMVY5Zyh0SVNeRUMKekx+P2JiZGRfJlNA
SlVtXmNWJWN4ZENaZVRnQTxaO0lVOTdeSCsjUE9VYWR+MS1lTFNhRHphI3RUU2MqT1h+ZlZwCno9
eSNYSWcqZ25lJCNwbXQ/Tz1uN3d9Q1B6Z2YzVDQpY21GRU87YD9yXkZFYEU9QF4oQWQzZG9HQlpP
VmczZk91fQp6bXtUXyg3TVMjbTRFb0JLPEBAWntMdX1BIyFpPFREWTUjeFk+NyE1c0djeW0qaDg0
MVdrSVR7TDdEVW0kOVdCcEQKenAjdUduMjM2RDh7V0c+ZG8xM2hDN2d3ejR5LT92aWUlPmZaZSFr
YkxBWWZBR0RGQXVvSSF2Wk1uPGdFWUtSUWJuCnpsM1lFWF5ZLXp+VEhIX2g0WmpEfXZtbmJ4LXIh
WUxEIWNibk97bGNBKUo2M3J0N19UITlTOC1IclcoOE1rX1hEawp6NzUrTyZuUXFlbilnQTw4fEJS
NSYtYWZ0fFJRczB+SSlHaiVrQkooV1V4VCphWFBeQkZHcjk4VyZHcUhyS3V8fG8KenVHaHQ5Wkx4
V0pkenlPcGdxaFZhVjUkZWlORFZiWGo5I2Z9dDVie0ZXZ0NQKmZuOFYkQEpifENUMHc0b0pAWFRC
CnpyO31hNXhrZjhrd0N6dktHZVlSS099NE4xXmJNaUxRLSE4MSgtO0soaCYyX2NPdXQ7TzIke2Bk
K2g7Q3FLMio/Xwp6SX5jfT1VTXI4YChzWGV2aFIkdWYpWHg5ZFhXTHFIUjdpX0I7NmRjTXxNcnk5
ZVBWe34mJlFybChmYEBsQFBYP1AKektobk14M2s/Uz9GQTQ+SUE2dkU5Mmo7MCotcm1ufEY1UW1v
TkpWZF5CU1RLMEZmd1JGIVZKQjE5KUViKShLTVNSCno5Z1A0cmFJYiVXfDZvKTcjaC0xbnZ6YWpE
JlUxYDE5eUlqcHtrYDxMcCM5SGgmKmtMcj5KdiotREZaPDhDQCMqYwp6dTI9SjQmOColSSt9XkJ5
MD0qJjl6bjhsTGZJRj5VQC1vP01ZcXNpNF9VMGpnZnN9OFgtdVpVSk1jQXtTSC00Sm4Kem5AZUND
QiRreHBBaiMmXzw8Zzlxc2lePXFgWkc+TXAycEpBKzJHV2FOMl83OD1nQ3steilLdXJOPVZiQztv
cUo4CnpAQj9PLWdNLXRXQHZFMygoSGFfPDhqNEFmZX5ldjklP195TE5RVjxxTEpiUF9PWSFMIUwx
LTBPSGxkYXdZN2s3Twp6aD9qfmo+X3pxNFRsRnJBdXRURW1CTmp+Qk13NEhrLUZDeDR6blJSVzN+
dEd4OGVtWTlNcGFaKWRgKnB8ZTI0ZioKeilfM2tVMW9zUXJkTS14XiomWH5EaU14P25UMnVMUnRa
UExaPFBxJjUoU0lrV0ZIJnc4bz9DOD1lbTtPbVBXLW8/Cno8M1ZHZT1qdTtCVVI8PV44bmhLbig3
eTcqaFAqKX1KYjM8P3h1a1pCMm08dDZuJjZtfHBYbEBiWnpiXzFIX2szRAp6VyN4RSkrVTw2WjRz
c2hDSiRDYzRYS1QzNyU1enk4Rm1UbCtMSDJZOzUjNmslPnpsKDRkfUR6fFJZe25sT3p3MGkKenlQ
MzQqUmxAMkk7MXlqeXI1OVUwRSlBIURuIVVGdE8tUyY7TkNkeGg5eHxgfGdSYWNoSHxuNERPSXRG
Z2FFampiCnp7cEcjWm0mVXQ0dERkamRPUHJqWVVqWWZ+NDN6dyo3WjsxYWR9ZEdOQV5JZGFRNSR6
d3NKT31SV0s1ZH5Qbz1WTAp6IThKWlI4YVZ6SlArI0dPdyQ+ViZsXjt0JkB5N0NvSCpxaSZGJiFC
anFiMnA+NWhwd2RndFR6KkMxZzxnWGd8fFAKejtQc0YkI3V5THQ9VlBoeWJBS2RfXm8jbG5OPWkh
Qkh8cEZXdTFMfFBzaERPakRvbkFsb09US1BLUHVfcyZVSTxvCnptci1DQEhNRzZtUnArKFFvYm54
enhQfmRkQkptaFdsaCZ6PzFxXj9QeHwyXjNwXlJeSzZ6NmJYSWVyRUhuOys3MQp6blBAblBIc15T
Zzl8NGohellBYlB7UH53JWNTeCsoX3VMcDRuKDc7eWxheWhKe31HS3NOY3M4I1VHNHpAcTlCVnsK
ekwydVY+X2d5cHBlej4lWGZRQjJZSnYrd1c9bF83NmxWMil3TD4/TDUjMWdwKzZENGohPTBXcVI8
ZUVnYEEkK1BlCnpiMEFJVy1hI3d+MUxOOHEmN3JaRG1NMDliMntLNHVOY0w8Xz10WVBVNCozeXFm
TWlDa0FxcFpxUVh6JT9eVk9Iagp6Q2gkcnw9LVhGOHIrJCNiXktfN2YtfDJ5dT5je0ZKYWtHRC1P
JHs5a05oYCp5IUktfWFyPio0bzJfdn1KUjk3Z20KejBKfCVjVWVjbHZQcStJZDA9SyFMTHF8RGhh
VTh7aXViV2Z5XmVjc0VBa0hWRWhfPjtzVVE9UCtpYExOZmRrR2YpCnpTS0phcnc1eUA9YmEmcE1m
IS0jbDw1M2h1NWViKj1FfDxidjZ7Uk1sSTI8cTZFdiM9cWxCV0tiQ20hdCFpQTVWMwp6PU83JUN3
ZHpXXlNqZUtWQ3FJVylqU3M4N2s4JT5qSUcmX0tlKnhjJjNsdSZWVHApTGJzWX1BbWU2fF84ZkJr
QmkKekFiP2g2d2lgUyYxZWh8RCloJGBuMG5mSlZpQFREfiVFJGoqSnNfJG08NWQpZ1cwcXpsPUE+
ZjJVczYkMEUqbyVECnp3Tl4tXldgcW07Qn42VGolcmBhO0dUOGBrVW9GI0BBOEBrLW15WUAxTVJQ
elRCLWshcV92MzdVclBYLWlJR1ZORgp6Tz1yQjJ1K15UP1RSZG9eKlhLMW1iNC1XR2F8WW57KGk5
Km8tWk0zRzdsMGdpNkpFSk5ZcjYrKilOIWNXfE5wZXkKem1aV2g7UEt+UXcxPW9mT2BVWE4rZGcq
Mk53NkFRfFR+ZVNTUHQzRCZoUD1VQGtkY3B1SGxCX2NPKnJOdDdhdns4CnpMOHR4M0AzI1VfXlo5
QCVYfVF0Iy1hdSo0WkVfNkhPamkjUWBtKklIJElyQzliTEE4QTluVytmcl4rdm9tY3J5NQp6dU9N
P1dkPS16eTNgaWE1KURTRVBiOUhSVmg9ayFCTy1IaTx7bDNhc3l4LW1IZXU4PW9XdjkrZjcxXzBm
LTtCTEgKenYtXnBvRSYmO19vaCklaGJYZDVCbWg2dlRuZVhKP2hCVmJ+JkEoSXlkMDhDMG81VUg7
a1p8P3B3N2tzQWBNKn5sCnpwYlh9WmV7fjkmT28jbTxnTXQtcHR6fHBeWWpPflA3c0pyNTsoS3kl
aWk4Z0dtQXomX0VzWFFLJFlSdSo9ZXReTgp6Uzd9KHcmTnBncFVzfjB9O15NU140YDNWSmEybk5N
I0VrPU8qPEYrJXEqNlNXZUlGOFRKZkhxUExgQiR0Y0A8KnMKelB8QlNmTFFOdSFjQ3FreHcyLXQ8
d1JWYVg4VEpad2xMWXc2OTFPZWstY2RzRE02LVU8a2wrPF5RO0Yyelp+KGRzCno7MGhqbWRBKW14
MENTNWVMMkRpa2BZQDw0OT5DNCtGJChJYFluSTVRZ3pqbn4xKjFQPFJJV05QVmZwPDAkKjU7RQp6
enQmYmkjNnR1UXFvMnhlNmZaOFl7ckJ1V2w4OHEyXklWTnZKfUQtI19vI3BnaVVtMVN1UUNzTFU1
KmdJJjJvNGkKenZoRFV5KmBZYHBIUHsxRT0pdSVWVz95dk1lPmw+aXNIXkFyc1FMWjE+diROd1lE
Vj9JemAlU3h7a3l3VWt3fHYxCnpscjNmQDh+PU00VHE8dCNnVStiVytVUWVIRFA5ampqOHZfQVFI
TFltaSRMPFZefTI5aFModyZQVmp7SlVDRjd0awp6M3ZqUDtAWWsxUUteLV5Qb00xdG5BPXNRa1dE
SzlQN3FvaWprNTFCRkU8eHN6OVR2djAjM0RzcEJ9YD1qbFc3OUkKemIxSEYzbiFSTV57aEV5WGt7
PXk3Nz5DfURyT1dOMjsxP0djWXhfc31yT282KVhvY3MyZm9vZnZzdkh5b3dvYSZKCno0U29GPTdF
Z3M5Nz9UUSpHfUFwcFEyTip2emgxMVMpR2h3T09VPVpARyUmN3s1TUMhZT5AVH1oQyNSd3slTW4/
Vwp6NmtCJWgmS3AmbkE5eU56QUNZWVc4ZjZTNSFjbUNXa2YqbFJpSHxnJDUyJnhma2BpVDAqTz5I
N0BJNShsP0kySXYKejBuUUMzc15halAwenw9ZWJ6NyFxI25DVW88JWheM3FMNjQze2pvZDQjKWVO
fj5Mdz0+OG5iKjYhQ1Jtekl5IXUyCnpeTXUpOylQJEpyZWdASmJ0eXQra144Um0waD1KeWpuX1V7
dzdMSXpkMzBuZlFNY05iTHk3JCsjO3ooVShPb1ctYQp6WXFZRn44VHdxK3NhVFEtJCRBSlBFTUpV
cHopcEFPUF4+emxZdm0wOFl+bFgwYTU9aCZFUztTMUJMN34qWDZhRFcKekQ9VF44VTk4PnZIbyMy
U25qTSlkI0hQfW1naSZ+QHMxdjAhPW9PaDRgNmoyYFR2JDw8QUA/MyF6PyNfRDg9dUFDCnoyRHE/
eXUpcGRKY3UzQkI+YjJTP0xqKGdrVHFQZHtKUnhPd2AtJmIqKVA1MUtYbzd2KTQ7NT51RT9uUFhq
UDZmJQp6ZFhifVQ4ajxTI24jOUcxcmVybVVNJUIlbzhxIV9DVzQ/U2REOUU3VFBtKlRyVG9YckVx
aUoyRSo7REc+LWkxfkAKekZvTT8hS3xCbj5ibihnd0JwSiQtWVpXMSo+SiVGfEB7U31ZMTU5TU9W
b1p0LSs+dXxeM0VUdiRvOW81WE51M0wrCnpvZVBQYlE+b2JzaUwyUGl8SlhZYHQkaDU3aSF1YSkh
U2tZSGk7XiUoNnI1MkE2ejVGbkQ9S3wpdClVJExWKE1CcAp6bT01ajhgfUp2RCNwTDRSVnQhMn4x
dlpPMikja3Q2eEdgKVY9SlkkTldPaFhSU0YtWjlFOD8pNnRDIWpob1Q/MCoKeiFgM2MyekwqcEVh
fWRiQUc9NmNUPGIlPUJUeGl2V29ZQn1eJW1JdkRwNkhZVUlxeFFvY3U0PyRsaXU1eDw0ejtgCnpX
VyM8QXh+cmQ2TVZVSkE5bVpuRWFYQXoqTn1BIXB6WVRGbkAoNEpxT3d5ekg8QkxCZSh2SE5qQnRR
aGtDSGY5Ygp6NSFmakNJMVUyYXFTRSU/Z3coZXpkTSRzaiRnI3pWPE54VXNBQWErTC1Oa3tCQHYl
MWhtKVc0QUNWQVVuaVgzfkQKelU9QWVUUEUjfVdjWW89IUE3akJzJnNpZj0ySDIhUEpiXzwmd2JS
dDxybkR6QWptVDtvODNybFJrUDApUilibnVqCnpUVSEocnp0QyQ5PHZRNGxmJSt4S2YhQjRCWSVw
bFZ6d3dRezY7Yj9LRFEwe0x2SFlIQVlLPEx1P0pabTBEJFF+Zwp6QElIM1Q9O3Bud2I1Nnl2VD1I
cUl5bCZ0NjBEOUIpJCpBZ2pwUWohSldeVDcjSmg+SFNQLTMpLT8oezA1JFRuTnkKejdObXg3RyM8
ZyhNQkt9d1hLVGApQ0s4Ky1EYlBiUXNFJi13V3tXRUJ3XnhBaE1xO1NqPGZvSDJ2KlJ6VTlyV0Zr
CnoqZjY9VE9WQFAqJlRfbUNse2E+a2grb3tJRFpwPVhCdEtlO0QtbXhQdWY9aWt0bH42UCZmZUtx
OVQ2PWAzbTtlSAp6TkpRYWlDZ0h4YTF1Q3xxTShSRXFATH5tVGFBJCljWVM2N1ZGRT9gU3slMHJZ
d0R0VCl4LWpGPy19Xj5+X0tJfV4KekRqUj07TStiNDxQdkxoSDlrTUFzODV4Vj9uLVg3SXBMdFN0
bzI3Zzg5K0VoXks+MlBfQnVBfm95Qj5+SyQ3Rkt+CnoyRH5EWHdLXzdeJDZJUHAmSVN1Q0N0QUYm
bVhWJiNpelF5Y2xlZzFBPlp2JTFYaiZgemVsK31aQmxEbEZgP2ZRSQp6bjFXNWxJYC1xNDM1dVBD
YigxR01zM340WXZlVyR3c0B+VmQ0dzN3WHMxI2gzKHUrcVRFdGJOe2lgYEpsRXhGb3cKekg4d2FA
THh8eHw3X3xJMDd9NExSK1FwSmtZdGg7TVI1WSQzdl9OVXxaYGtBez5+bFJtZ0xneDA+KWgpU0JM
P2pGCnpGNkN3VTV8e1hlPzBfZSE/anNldypIMC1famt2amY7Qmw+ej11OXhLXis9SUoxNzRaQlk1
ZHtzKjZzOE9hK0lyVgp6ZXhqWkFqVEE/eDdyI3olYmJQKzVPcFJPJWJZKHElM1ZTci0paUJhWG9a
eDVAeDtqfntHK0lPSyMwaGxtaWlqNnAKejZsTmtSUXxFbmlTbCRXT3toKDFPdWBod0tXeHJFdmRe
fiNCVz9gNXN7Pjk4UUhveUYwQzd8QWxEJSFNQ15sdkFlCnp6VUNXcnR6MSoxaT18VXpgR1JkP0oy
NnE4aVc1aFdLeXVZMl5PdT98dl5ta3FydnkrOWZwQUt4JTlHQ2RDeHpMZQp6VDt4KERObEk7elZj
elkhTU57NU5QRSh7TjJKKTlOSVVEMGxmNGJQS0tlWWpoRFp9IW9EZTZPRnNOY0FHNihzckcKenRe
OUF6RFFjTkdRd2xzIU1id34zaCgqQ3F5MjxUeTsqRlRzV0xjUFhRdTcwVUcocW5RPiVlM15FWU10
ZSZhfk8tCnpVViEofjdfLTQqJEtmVlBIX3g0al8ha0pTKy1ATUp1Kld7NlBqSCQxUCp1aWhQcFJo
ZXVQVEZyOC1qek5VM19rMQp6QW4tIXg+KC0wV0teZnNNcjN0b3woaWpeYnImaFUqKkFgbDZBSXsh
RjBwQDkwYXwrVGojeURaNypzejtYTkUtJkkKejIqRTFtamM3dVRgbn5aVl8/TnJjZTUmWChSX0NB
VkpXSkxgJnYxQWJaTWwhbXVjVEZZKVFKMT4re0NYbShfTVErCno0fGo+NWB4WSFfQENQTX58Szlu
QmZAcVAjciE+eTt0STkwPzxEMy1YUFRNMTF0ZGtgLWs/R1krPGFoOCZTbjlscgp6UEp9az95MHBn
eFQ5ZEw4KiNDejJDZ2otPmJtVzZENXhDPmJsKFd+Q1pDeS0yVTdTJktAeHxqN3d1cD1LJV5rOWgK
ejt1KDQ1IyNkIT5rfCR2PHI3UEhgUWZoX3M5bD9nRnB7JnhSNTBTXztYJlQoV3l0aCtYM015SjRN
WFMlZndyIS11CnorQVhYMTZ7dEpZaVljcUA8UTArK28rUFBVdj0/clhJJFVtKzN2WmQ4djlabTNy
RExMUkRmVyNuJFd4I1QyNFEzXgp6cUMhKE0yQnFBQGdaU158YW0rWEQ0IUk1Rz9KczBWbEN7JSF8
SHs5R1dkNXFgdzg0fSVVQUB9KkpNfjR1eSFNbVAKemNeaWowUnJTflZrN2EwXlVsYzNHZSpnfD4j
OWVZentlMlYrKTd3djNtRzMmbXhjWTRSP15+fCRHY1ZQIUl6UmtqCnpyX1RjXnQrWGZkdiorMHBS
ZzRQOUo1RkVyVDRldGJkWVkpfCNkRFEobSEpZT9UVk9RRWFHO2JwYCtQISlKe2kyIwp6Pj55ckxz
bHp2PyQyUjIyViQ4V31PSStSdT9QWm1qPC0kJFhkdFMxWTQpPHA1M3d7LUBHbGxGalh5UyNYVW5f
YmkKejRDeT9RYlE8PVo0ak0oJipsNk92bFQjUz09Zjw8QHlKS3Q4KnpeNiZfT2chYitAbmphPHxJ
Xk5VaTtnPWt5eSRyCnpBVlNwakdJY3RtU1FnVHAjViR5Wj1YM3dGRV5SVWVIb25aflJIeWB4SEdo
K19UcW5EKjNPa3ZjVndeRzM4RU1hRQp6cmBEazdIWFMjN0Q/YlhsaCY/Pns8O2o4UU80UDkkKlBe
PkFzSHF3VSEpUFF5XkJ6a0QzdWs7OCFOcVJfMHtAVlEKemFpWXMkYj9CZUx7KWYoJlgoZFklJXlW
NnQ0ekp6JmZfa01AQTV1b0RuVHdAPztMRS13TU9fMCU8Pnw3aFNTO0wrCno/fSp+ZGZaWChFdmZs
Zjd2SGxxfkN9T1RBNUIjSFRzXkNjbTRYYEg2fEZJSFVTVXpPK2A8JWBuUT9lMXN5X2wkZgp6JkhH
aUQyVHN1JSg4Z1Y8M1RLKWl4OVBWPFBsV005YFdneVApU2V8Tzd+dXomMkEmPXtVO2Y7aDN+YHRY
eEUyXj8KeldWJXQlJWt6PXtHQG8rM2tGSkRVVHtUUTBQTEp3RzkmQyhWbC1eQUdrMXZDYkNMWVA2
UFBYQXhlZVMxT2hAMGtiCno+NH0+RHdkJjc3X35jSUshZ0tHYmxfS0pHV1FrcmB6TD5GdnJJT302
MTUmOEVYakN5YiVidWUmT0ApUHxldj9EZQp6SXAyd3JOMEBWfmU0Y0p3ezNDT0BkPWU2NWVBPHVS
KFFPdmBuTC1feHRZY1l9TWlrTjBPQmtaKFlLTXp5R2BQPnoKem58bksqWiQzVlpGVy1MbERNaGhr
JmtabGQ0UlIkdndCU0cyZjdJI057cmMqc3lBfHtsPmZDJEFRaUR3JighdiNHCnpOJFI4MGFncGZ7
dyFmZFI9alUtcEEpM1V6JGVOX0Z3aFQ1fV8mOyNZXmZ4ZSpxY0UkIWc1UmotM3NKUUduQ3M4Rgp6
cW4jTTk/PXw1SHc1JXJoJURXNSNOcmQ5bU1ecmcmPlQtfVBnbU00al5tVj5Ucz5APWIhQjFGfElV
JCN7cGN2MEAKejFrYmkhYGM+LUQoREBtYXU1cztlc2ZPOCF3NlZJVjJlYzJWZGJIcnkjSkh9e0FT
O2Z6clZNdzs5OXc5ZHdxRFh6Cnp4fClxQ3NKK2VrUmd9Yn1SQmI4SUBLZio+SWhwYVRmNyFufmYt
OU1FPGM8SFc0Mj82K1JebWFyd19iX1NVWCZ3UQp6ajNweVE2N1FSPkBJdzRkZz5nJn4qKnw0cWha
RmNKcE47XkhHa0J0NU5pWkFwY3prcEFPN2taaGlKTntLaks/KUcKej4/dj00QDhhZ1V6N2I0QnNw
TmpvQzI5cDBTLTN8ey1sPGlZNU1ucFdObTB6SUdVbzdeSFBPJW9fZSpnOChQclVeCnohZUFZeHAt
QDI3JDVZKU5qVipxTCZfMnRSLS1eQSZtJnYrSGNrPzJqa1VoZjBrWXx4elA1IWo8bzN4SjFZbHNZ
KQp6PylgVXRANjdKOWRGbU1FZEBAaCFvUipoVnNHPXJHODQ0MUJuN2NkMkc5Mzs/OCozdTZuN1Yo
enJUa1N2dEU1azcKeisxcEYkRF83V1pvYnktPnl0MlhXPUNhVUk+RDFfUW0yO2tQJXlxKUdmdjMw
QWgpc3g2WlVLQ1hsI1VAcUtsV3VSCnpoLVczWD5uQmxVOHNHWCpyMVFFb2N5ZyRFd0k3NmJiamQ7
KjIhP0RLYENmK14pQ3JaTEM4IVNTZG1nTWtEQUskSQp6PkNCMnZ1cElCVjRHQkJ7bH5rYEoqU05W
czM9dU4hUmc0VXIyZ35gKXNfa3ByQHxQSXp2MUg5dUBzeFR8RkYjUyUKeiYqNkprI0B0Nnk2Q2Ba
S2h5eUxfJDIxYT0zKDJ4dGJqQzZjbyooJGFkdz1OPHo7cGtib1dMKkFeYmZmNDxGNVg1Cnp5OEMo
QDZ+IUZ5SGVCQylrYDBIZlh1O2dSN3lOdXxAX1ZBOVV0X35YOVpzYFcqeUVLU29wT0haRX1KPHo5
NlMkbwp6aHRvSG5hS0FxTTU/WWptT3BEZSp6JDFEKERIST5JPis+T24zUz02T0gqe19DLTJSem5w
U1NCR3d9VzsqXmVHZn4KekFHYlp4RTxidExAaiNSYDdsbXMpa3lhNH4hPzxzODZ5bD8kX0MkU3xu
S31EMUBGSUg+ZyNBVWM5NGBsdHZ0K2h5CnooeUBsR1duKnx8PmkzXlc+Yn0kIUM0RE1JbHpBT2Zm
ZE1uXkd4Rzc4NiZDZ00jenZMWEphKTNRRkxSTn0pckxYIwp6YD5BNTJzZzMmcnJwfExPPWh+djhs
UnAobGNKRkY4YX01QG5McGQzWW4/PGM9QHpTaFNZJWNCIVh1RiZmd0khWGAKekw2RzJLUG9MUnsq
Sz5+dlYmOTtudVVDNWNPO3NGMWs9anJ8MHR8OXJeem8qej99QTtDUFhLNDEwKnheNVlXa21ECnor
Ky1oeF5JPmd9eitIc1VqMHhNKlokTDA8Z25pOz9BPFQmZGZIdnkpISQ5YD0/eyhWfUg+SUBPSUJv
TXA9bkE7aQp6Z3VVJVRfbXk7aGJNPDM0bXg8NypZKHo8UzxuPGAhUjMpQmg3XmIyYVdYUzlVUz1P
Y0U4UjMyQGhMSEJPMXx8SmgKekczV3BBa0VaPDtgbW5wQmFXdyYoelp5bX5eP0xLJTtlPjNzRn4w
ek9KK2ghdG9tU1khKWh6Sz1rQG49ckhUMnJVCnpHbHwle150VFBYMi1zPT4hUypoSXpRcHRwTEg8
YElJWWI+bnJ1dlpCMVRUZEY1OSY9ekN4MyhxdElGcXlGQWcxRgp6VzM0a2FzbEh+Zl9BXlVudE1K
NXk8ays/NiR4bmB3SiN0MX1lbXJ1WFBoQFEzPjF6Oz4mcDtxY253bVo/XlJScWwKejxnPTVgKlEo
OWhYOXw2RHNnYTkkNjRgZVlfezFwUnN7KXVzO0FKa15jdyVhM2dzdU1tKF9NMXc4PWc9fXR1aXN1
CnohN0pHTlNZTGxRP1dXTFlIWUUxXlZySTRjd3lZeUhqUGt3YWtsMmYqVGFySVVsfmF7QGZWRCtM
aEQ7SyZlQGZHRgp6ejIrTWV2dnRia1FpJTlsYyFER0N7Rzx4RWJaPWZCXkAhN2ZBMUsyaHxISHQw
b3RPOGRwZncycDRGTlBTX1FWYV8KenU9R0BmV0c/OSlgNmM/QnsrWXVpY0JZRCErfGxVZSMpQncr
NGI4aFA5OEJoLTNgOGJHJVhnJiUtK0RrdSE4XkwmCnpFPENncTgkMEN4UDdiR0dTOH58cmUjZkhv
Rzl0VG0/LVJZIzJGRl9MUEcoIzhaO2VkfXw0a2NDTG1SIV5lUDVsZQp6cV9jd0hNYitrUEQ1Qnpi
VGE+PC1rd0QyNm0xJXRRTnhTJUBefUpPcDxkOCUmbVJKMVJzcnpGLS1TLWQwOyU7Mn4KejYkRzQx
cXJqbHZ0P05nQXhYQ08zZVlFISZvb3Q8eClCTyRaeW12SlNsQCpRUEZYVlFBdWVJMT1RaEVpTGM0
RE51CnorVXl6NSVrTVV4Ukk5MWY5NXghZG84RitAcWBkbzAqTkt2b3BzakgzdCVseTh6XyhuR1hO
ejsxbmBEN3JKXnMhMgp6diolKGFVSGJSVGwtYkVHRz9FUmFKenZ5eihgfHdYQjxtalo1PEVWeVM7
dDl6O0JwRD1PdlNPISRDWnBgak5WMF4KejYlX0Y9Nzh8ZEw2aCNVezFCTEdDZzJ4a29eWVE3PD92
fGRvNUZZT2lpRVhkY0pWMmFzbSVzUjdmQDRSMzB8Zz5yCnpFdCQ2eWxzLT57ZCF7IVJ0ay15LWUy
O1dQUTBYZUk0XlM9X0t1b3wqdilBXlEzWUx6OzJpMj1qUlBmbm0+KiUlKgp6fE1xKSowTmUzMlN9
TWoxMTwqNG5NX2IzR2VDYyVFPEteQWA/Wl9+PHZwPn15Q2o2QXxJU1JPUSs9NnFXTEUmP0QKemtn
cjBZKks0YTtlfWRFRVc3clQ1OEo9PFJeVmdBflA2OGg3R0M7UTN7cXxXSFlHeVQ/O3M0NHc+YGJG
cnAlO358Cnp6b3FeSFQhfVV3aExQe0k2SW9oZWl+c3tIaWV1VEljanV6PnAzJFhQdkU5ZkN4ZGpi
JFAwTCFxV08qR1hgYDhDfAp6PVIxIUVuYUY7WlgmYCEmM21udjRYPnkqdVo9dy00Z3hfPmY4eH4p
PC1BOEBmezwxIXdhfmVDPyVWS2FCSDlfQHwKek47cnh0bUdHdlEtOU17JVhuLVA9VzRfP09jWD5o
OHBDNSteYGBrd0c2OVI3aXpPX1VIZV5RWmBATWh2QXw5cF99CnpCQEo4TGJXP1Y7P3BDVDVtRnth
RXk9JW9LYmFmPVh4QTdvMnF7ck0+V0J1b29vWi04e15JVitqPVIzU2RMY0lKKwp6eF5NSG5RK1N1
OXBiV1Q5UiFOI1BAeSR2ZUtoQ310dGJOITB0MiVzMUJNTTFScVpSaCkhJlBwKm1uLV5pQ3srcnMK
eiRndTZZeGFjO05NRX1lMjVeXjFAdnklRmg2ek1NNVNxc3F1JnYwRjgtOFpNe2gpdyZpV19lJUEp
cztlfWQtRnBZCnpwNmFxT014enpkUytLNkxjUWJCWmklbn1MM3AoWkZyKVJsViM2a2ttWmNQb1hE
MGIlbnlQJjxEVEE5IzNXRk5Xbgp6cDZoelctTlE4YHp7MyFVUG5qZmVJakN7STBzKFBVVndVeGhE
eWooYnQob3NfZnBsNisoIzclTGllbnxEcFBafmAKejd5VCV6ISY0bjFHUW5HQnopPWkpWSRRWHAt
JDs1XlZgYktkd1JuZ2RVVUhHR3dRYldWal5KOzIoV3tHYj99QnU0CnpPV3NPKmU2dEdOQ1IxNGFJ
fiNGTCkzcEJqSyFsLTtfZXptNmZ9aWA1ZXZVZyQmWms/RFVYSWsze30xO3VhK0NYbwp6U0FJQnNF
S2VWWDtKMSl7VkQ0dUQ2KUMxX1chJjxWcElNb3NQRk80LSl3PEZRayhMNE5uKDxgNEJiZmNCSmYx
MEkKekskdURLdzJ2SkVQSzxYZU5TY0crTEU1d2I4cXh5alZDNUdmejdvdn5wcWs+MTxCaHxFVEVY
UFZYeXVSX0lJamhQCnoxfEM/NVNtPUkjY2NyLWJzKHlubnN2JU9KUXpEfjczbWtNciEhaHAzZHhN
YWxZfEYyTXU8e3t1Tio+RSE9ZGdMOQp6c25MfVpiK0Z8YHMyWG0keFoxSiErVFV6Tjx9b0twMiFe
O3pRPm1iQFMlJDdOaElQdXJmUkI9dlVHKlY7RG0tN0wKejRidElefEcqcX49VlJiY1QwMnFubilH
R1U1P0EtTSNHOWhMSE9MYjFEZyRfM1klNzB0V1VPOFo0NXJ9eUpVTzJ6CnpzXzJjSTdHfCM8KHQt
Vz9BPGtrbG1lRyk/dn5NO3c3dXUoVS1YaH0zJVhARm5XUVpxbDglJi1MeCVINVBAWXgtcAp6aEFo
WGFxO34kT3FWYistPUEyTE84dDk9VDcqWV9kKUdHNyZZXkgkPj5uNzxRZE9WYVZASklVUXVmZlZU
XnBHPk4Kej0/NWk3cWBHQSlRckRuc1ZBKFNyOHhkJFNQV1JgaHsjJXFEVC0wUk04Z25KWk8yMT44
QFJkMnBTJCg3MXVfIzx1CnotSkdsWW93MGU1dWI0WmI/b1dYRSt4M2k0QihqemYofkU8biRTQ3Rt
aERlT3BxcTdmZkYlWkdKcG1AYzFRdHJDNgp6Qz52KilmSDBJP0tCTn0rdip1KURVe188Y2YxMzYj
aWJyaUJQdGh0RW1aU05XMWFhVGl3eHtMPCN+azl3cW9tMSUKejwqPE1tQU16ZDJiKitScXlgMjhe
RGRjcTxPJTcjITZwMVJyMXRGMXs0JTEtNlFHNj8xOWB3VT4/QTxJN19IJjZ6Cnpxe3BaYkMyNzhn
UFlZUTI+VilHJFk5bno+LWRnXkI/OXd+LTV9PDNod3hzOGJoeDgrWHRaZTxgQFYlXzNUSGdPbAp6
UzRkPW1hVWRxcytiQShmekBmd0FPSVJnJHc4TzlSPmElO0ArM0FSPXFJVnpDSTt8RyZ1PmRoTypp
TThoU0lGMFYKek9SR2JoPVRUcUdfPGlzTj81P3d1TTVeS05KQ0VGPENpQyNTP0ZAazMpSX19Nm1e
O3JzJERXQ01QLWpocUs+ZWVUCnoyWDQqfWZscDIkcUJ+ISRlKnItR3t1fl8ze0RMK24mLXJvLU5g
QXtGOHdaS0ZUOzleXkQ4OV5NKFo3cFlSdmh2bwp6QlM7bS0hLSg3LUdSYnpeQUFeMGAqakNFR3p1
P0h6MV93ZSNHWHJwdmBON2wwI01uM1V1RG44KXBiS2lBKGt2bU4Kek5+UVp+QXc9PGczQGolV0x8
clFmMGl5Jk9JITFPY3BiQDhARUhJPUFQPWUqX2tNY0pGKz9KUFFiM3Ykbz53MCpZCnpxeip7dWom
OzRnbigwZ0h7Vl58ZGxeaHtIRilDZloxenlhcmxzIyQ0NyV4WmlaYiY1S3txM3c5MEwyRF56cDdL
Zgp6Y3dTYU1qdykpZnRzXyZTQVRxaDVkYXFFWnUhKHwjT0hyMzt5Q31UUlQre1NGYmdGfXtPd2pW
N2pfQkB1aCs8ZEAKejJxPDJSJGdSKGxuWDwyKj8mRCtuaklyNX40e3xvO2p2X1ZTel9AUldtdyN4
MGA8VjtvSCNOQlBNQmFOSyU8biNmCnpra2sqMFd2fSM5UzdLcXFvcEB5KjBYcjU1Y142M1pPZTV0
c2tPK0Y1NHtWeDsoXlVtJlB5P2c2R1c4V3pqfl5QcAp6UjAxME84eSlXUGZSOGVUanxAdVkxLWNW
ey0mP2grajBheyhUUmRnTSE5K2dEK21RQSglSn5LMjV3QkNtS0ZMTXwKeiExVndWcDtmYVlmPEl1
SUlfRHA3JlJ8YEcwRTA5SSZtNjkre2lxTFQ8OCMjZnsodUFYPFNQNGxWezQkKkxGUjx6CnpKUVJa
OGc5TGdYMG1+cn5lWnR5KFhDRUpHeyY2KjdpM1JpRDN6QV5hbTFXam1FbG1nfE0pdENlIUk1JCM1
S3E0Vgp6KTRjZVRpZUtrbW1+Oz9pVEFJLU5hOUdaX3NffGtEJU1Tb1EmazVycDNmKGBGKlp5T3M9
MXo+RDB9I05VYGJ6OSEKekghQWI+cng0UVo8fTBpNV9kbjdVYT03dyVEQCtpU2BmdzAhISs/M28p
SW5MLW9CSlJpNWNkRCglb0JCbXt6cng+Cnp8SnNFODxwQXVfTGwwZUUkYHErWD49bG9UIz1IK2wo
LWZkQFNLLWQ4M0d0fEQ5NTgkQzFtNUptblEhJU5TcmFAJAp6TmB2PDhgfWhiUHshZ0Jsbl5KSXtN
Zj0hLS0ySiFXWGpiVn0hMDJPS0M4UUB8RzZEfW5XcTRiZFA/KShkK1hFMFkKem5JPGl9UWw/fiNa
VEk3PTZDSiVFJWBMXypuen1wJUByUHVwRnkqMzVRRT5qQk59TiRwY04tdTJSa3p0UWdhKWV3CnpF
U1V7WnYhVE05WjQpM3B5OVdteU01R3R8Y3A+KmMwclFkOEY2cXJCP0xWfDJSNUlCaUh0OStaJUA3
ejY1NHZLPQp6ZTtqKns5N2kkZ1JrJjZ8JnpGO3BjQF93dkw1PWxIJlBYPGRZdT4hcC1OVitnZj1S
PjVIfHcmeThBaH56Kio+R0IKejQ1VHRLY1J7YHJ5PEVTTmtWWj5wWFFsYXd5eFNEdSVlPV4yQzIr
M3pXaipYUTN0KT9XWX4rJnxTfjIzYCkjPllFCnpUd3VgcTIzNWZ4Wi1KIzxKI2FDUnpnbExYfEs1
TFpqajNZZjlPZXc/JG91RGQ+SDQ0OWRnb2dNRG5LQiZASTB6Qwp6PF4pQGhUPm51VjF7Q2taeCRg
Xjs7WnRgJUVYV3V2Rjg7fUNLZUM9WV9rcz9yfDhze0whdkV8aiswMjVVbTxkNDIKendwYGwlS1NR
JHB6bitefWVtKHtmQ0gqUnszeF57d25FKGZ5fDEwVEsxRWNRSCVHcGFmKkZ2QnVvfkgyY3d8IVE9
CnpmVlgyRFppU2Z1V2VTZ3l4ZnhPd0shKTJUTzRnd2R0ckp0bHw2UUwtU0JoRStSPnIrK2E+Rmd1
MH04aHNLWm1qUQp6VyNCOEt1RnRQdmV8LWIkSmBLbW0yI0JKZzM8N28zXiMkQ1B8OEFafndNc3p+
Y0EoZCRTdXlmRT1LK0c+NWJAO2gKei1Oa3g/TWRgKHRwVHlEN281I3omTzdCczZDOChRbG9nQFpH
IWBNTHBtdnpEYyNHcXcpeyRtbFZNZ3MpRF9WbCRmCnpRR2w1PkhOfC1ubD1uPSNtR3wqSTM4YU5Q
N0ptNERNKEc4U0FnMHRtRVhvKy1kM1B2M2E8fmpWZGI9YGo0RlR2dwp6QElrS3lLLTNTPWsjZVBq
a1NQI2BDPGJCa093anc3WkRZbzlUSD8ze01FZ285JllPTV5yVDc+d2EzOTMoN3VBU3MKelNGKV9O
RENzKkprPWxLeChMJktHUXtjdSEkLSskQFJfMy1kbWpZTXopfT9UQk9fOEJycnFYPm9VeEB3SDJA
cGcpCnp7NTAzNXtEZUkxO2x0RGUwRiUjbWhSfTlQXkBlekc0TVopNjRxZHRlXnJOSnQmbUJtN3A5
REJjK192ZjRhZiZeQAp6cFp+QEFpbk4yJkgjTzgqMlBOaUxyJSRQLUJmKmhYNjxDS0FiNW5PdDY8
MzBsTlElNUpqVzEwTDYtWnNZOyQtbTwKejFWRHpwO2dHOzRRMmFYcCV+c0dnbTJWMlFkaUptZUoj
VHluNU5xRHtzS194QDE3KVIxTUgrVDlTUn1iS2V3Sz8mCnpQRFM7WiEjbm47YHIkSmlSLWFGQmRN
S2U3QzFwKjBjVV5KSDZiPXxYREZRTVZMYjgybXJVI3h0VTBoPH1SVk1LZgp6PXVaRi1YVHt3R0xO
SWw1NVhyKkw4UCl4OEcxPUlkRihOZWkkezJ9cjw8RXVfYXsxMCVTLWNHc1ZfQmltUUFJUl8KekE+
SHlpbWNSVElCO2gpRFgzMEl0R3JwU3dwVWdNV2RRXzRlc2xpQU5HaUUhIWBUOFh9UE5SO087S3gy
UWVCb0F1Cnp4SXFJb0dKZjg/MlY2dyhHNXFWKTBCTzEzXl5WSmFreD13YiFfTDxaSENqfFcwblc7
ZVZ9bmc0MUBeNUo4TmxKRgp6MmEpTXxYSitqJHtYRzs8TF8ybWxibGRYbnFkKGlke0B7aHstdEBl
I2BpZ25jb2VTN0tQfV45fnU1VnlJKj56aioKenZ3S0R0QH0kM34odjRhdSNPQGBYKV8+VTdgJSMj
UHVvITh2IyF6bFEzaCFnRGl5dnxUbH19TDtCZCRzLXdzWkYlCnpWSWo/fXsqPko2UXxVd0Y/Z3Q+
dlhqYU1HZFlLTjM8Zm4/amVne3kpPTxndjZTcHI5UnRmd0YhMTR7YzNeT00tKwp6dEhjbVVeR0Ml
e0hyZiRAZ09RI0Q4QzMlOHpNZE5jKUp1KntPNjZwMm5GP2ZtPE5gcHNiVEYyQitMJHIxRDJhakwK
el5nR3F1aHsoWiU/VUxWYjE7bndmR0M/SXpsfUc8QD1QbUx2OTxNakVmWE1oemVJYDkxIzBTPjYw
MHwocVZOdnRzCnppTEF6RlFBTV48QXVYVD0/Q2AxNT81UFZrMzxTJG50SjBHVnwyXmB5WVg/Z2VQ
bFBGSGRBODJYbnZWTmxtIytwcQp6ZSEwMSM7TSpRWE84cz1AOVk8YVRGQTx5JTN3bXhDazs5VF47
dmd4cUQ8d20rTnNPeipAamNJflA8b0NlY2AkZyoKekhvNnZNWUt3fUpoMl9+OXo8I0xOT14zQUpG
cn47fGhVJHd7aUtjcTF0JT0jdVYyPXI+T0d0UzNhYWV3NCtAb1NwCnp2UFpSPktXaDtKRGJ2ZE5a
OFAhYmFgVngyXmo9PGtzcCRRRmdBWFZAbC19V0dNWEVkMGVOYXh+K3Etb2FYVUJJZQp6ekgjPjMt
PmNBRTVjODdrLWtMbGNqNFhQZyYjWn56cGdHXkIqWno/QzAwYS13aj90Sm12aEg8NVYja1dZOGd0
KUoKemd+MUk8VEctYTlBPzVLK0xyZk5tI058fVI8RXJwU2pVailPKW1JdF9RUFJkd25US2JMdUhO
TXJ5UTxwRkdOO0BACnooWThTVzhJUT15LTIpY24pVzVmKW9UfSh8UnJiJkJgUSpxXlBJIyFrUFEm
SXs3e15LZVNtPTJHKUlwRlJZdkFiKwp6MT0/WEwqVDcwN19tQX1ETlVma0I9bDRHSiZPKFd1Smtz
SFNPODBWdmQyPk1XLTBhcGIwd15xTndma1hSQT09WWYKejZ7VmpUMTVqS3R1WWhkN3hSRTM4KlhA
NEdFXm5TI1dvK2krXjtadz1LPiNWOHJyPjclb3N7PktPN0JBdDlDZmt+Cnp5fVREZWx8bG5rdGVn
bGcwdDtFMVVYVlNBX0UrUWtiaUN5RnRebl9lJCNKWlk9STlAdXl5PGoxNCt7P2o9cnx5TQp6R0M9
JkFQaD97YXBLcyElUiFwN2Eza0I2TG5AZl5CRnR7Mmc1YCh5dCZhJmdOWFYmbyl0a3V4QWF+TllX
a2xKUE0KeislOXA8TlVITFdMaSlzNGphaGgybn1PfkgxWldMUnkwWHViQUZqTVJBdmJPTUA+SGJM
PTxtZGh3OClCbkMqajtkCnorWVY8UTFKSFRCOGFOelVLYmxhSihGYzY9aj8lWFNMNDJESmtISU9k
aGFjMCp4TDBtP0dVezt2LVBfeWNGbkA+Nwp6S3hBYm4rdXdzZ3lvWFV8PURYJjM9K1BEUDxUPVc4
S2ZybHErajN1T1p7NFMkMCVWQG5waGt6OFU8cXVhIVViQW0KenBaKGxAPEJiWWZOTFlXZ01EKVVB
a2MtMmB5YlgrLUgkQVdHZnpQNjd8QXI9I1p+eWEmWVk+UzZTZmtfY1duUXwzCnpMUzBZcXpNRSs3
eSpRNjRiUW9CbHgqaz0zVyolTHUxZSE1ZlZ+dUc0WGtZbkluOXxEZlElYCpSQ3VjeklJLXE2Xwp6
czV6VF9PQmclZmxtYTxOanJoRUV0PSppQ2JtQiV2PE81enBNMVFlO1hENW14XlpjSX49JEheUitu
UipGY3g/PDkKem9kVHZhaW91eilVKnJzcEIzZWhPO2JoPVomcWxnVkRTKXJMRnImVDwqdE9aTE4p
VSMtTnAqeWhicGBWR15yPzBFCnpkREFgJCYjaU8+Kyt1JWplMnxjTTJPOTk+fDJgREQkKTBOJXpZ
NWw4Sno2allIYVk3MUotQ1FvX0heWEo/VUJBbgp6VG1JUm8xR0A4VlF0ZXUpX3Q5SnNFPTJIPWg7
NiEmdD05ZkJeaU0zXngjaHA3NlVldWJXRWcxdj87bVNQNnFqaj8KekgpcE5gKmNGWSYjZXFvdUtI
MmIlcy1FYHtPVzl0QSZVcStuUVRIRmtfYkdSdntASlplJUQlQkx4bD41aHA1fWBOCnpgdzU2UCZ9
OSlfSk1KaXtRVkVvJDJrIW9aR0BxO3VieCl0Sm1eYmdqUFdaOEZRYStfTGg4fmU9TUBzJGhMXy1k
dQp6QCNuKFZtWFpAQnxGX3NQbzdyc3pQOz94WnUkZjdNVTA+RXdTb2dqV0YzIXkmTSZmKnEjUzBe
TEAxRFVCWX5hSDYKenUwazMmVCNXcTZzKn1UQFZBdFcrb3tISFdRQE9wdUVrKW9iJWVTbSR3aXg3
eWw/fWk8bUVmNDQhPW1qQCFrcTd9CnpgKk85WnFTdXhmcGZ3QlM7QEpBQlFMPWo4R3IoaXJrXl9e
Zz5kYkc9ZCVTczE8RytxczZ4WlRPZHAxeVBwKT9KTgp6T3tpISZAdTExVilpZHY8a3hSMVE2KHs2
RHdaKDJrQHg+K0k/QFhYKlR8IzwtRW0qdDtheEckNStCIzhYMTNiRGYKekwzOGIqRjVpbmJxJlE7
O18mNk1RVEZSZHtQMyFRfXUkSkQzWCpfRUE0SGdganFWbXt8YVp4MjBQaVg8aHw5UVExCnp5aitz
dEs2IW8rajIoXlNsQCt+b2xfV0xoMkd6R2dEPCZwbSQoJTk/SiEoZWkwfGRFTjUqLWNwOXxINXgy
VXspNwp6IU5KOztRb3hqe1BjKzVQLVR4WkQhTSF4MWRmJiFEUH0zclhtbGRvcEYyU3BPb09wSVZS
NSkrO18qNzN9eHxYT2gKej5aS2FsY1crUUxJS1E1V25eT0R2SX0zKXdTQkc1aGQpQDlOYjV0Z188
Mk5QbnE0fHBCQ25TT1hlSzx7KWJhdUxNCnpFaXptIUp8VU5XVXFDcm13MGJwUihOXyh9KzkoNWpD
RH5IQjtRZDBafEZscFd2PD5scFhQUWV+NHB6I29fTDtIUQp6WjEmZG04Mng2OyV2X0E+OWNEPyNT
RFNRemFpYkdudERUaHpRcj5qYillYHsqIU9Ub3VRaV54THhrYFUxMGp7PVEKej4pdil2MUVKMigk
RkM0IVdHdlpPT3NLZiRRPWteTjZsZCU2RyR0PThzWjt1c1U1UylCazVLT1E8SnRaY1UoM2FwCnpX
enBkbzslSldBZk8pNkIyPDFWc2hWaStxNG50K1YkJH5UbypaWH0pMGA8IyZaY2tFZVRweSs3bXpW
clR8MjEldgp6bFJsU0lJOFU2a21hKVIhaHRCYnYpbzVfMVhXYmQlS1BAVU5wK0tKYy1RcCtLTjVN
JUYkYTNhViM0MGJReVl7US0KejgpKGU7bmk2YD40YHpNdF81dXZ8Qk9ffSpURzNmZyV9bj9jcUlm
PVoqdFVvRC0lNy1GVFJYQ05HI28pe3lxUiNkCnplUERORCl1bT57dyQ8bWlrRG5DNFlKfGVzVnc5
dTU/TmxQcjIrI1deKHJNWSUoZUVZPEh0MSFqQz50MFR5d011dQp6SU05MzU1d0djKmVIX284Jjwm
ajVCYDQmd0U1WnlyOHxDfERFeFBJTjRWQ25tSV5WTD9iVzcxJHlKXyF9N1pZV1gKelpIOU1CSnhW
U30jPS1QY1l2VUF9XjI5VEhtIU9gelc/S1h2KCs5NVltOElrTFp2QFFBeyomVj5uTDY4cnoqKUwy
CnojQG96WWBlVUkqUkdQTzhta19JT0Q2YExMd1lydmFPJGF0TFRDcnExZGF7TGpBbSY2V2AyVGMk
dH5YRihVSz5AeAp6dkt8Z2VwNXh6czF6QFY0SkY9JElpbXcwbiVARG02dmFnYkVMNDlrS1F8RGYr
JDFkKyFII05UR1JPemsqS2FYdTMKenBOcSRya3l2PlQ7KW9WREVvK2IwQDh3cGAhTFJNJSRSPCMx
N3B6MmFjcGtMWTt4S3NnUXcrWlJgamFSIShEU3pICnpVPVI0Wm5CQnpjWExtWDlZS317fUJ+QS19
VktVcn4hdFdvJVBZdVVkWSN2REY3dShxP3BnSF9qTFRsSys9UVh2Xwp6cyMkPiFZc0piYz4mRVVL
cSFnRmJTUmVZPkR8PGgtISR+bHJSZSh0Wk9eTGUzT15CY3lpUzRgPHxHU1I5SnN0WlIKeiNVSzxl
THV8bUQhVmIxPG5Eb2NvSmY8U1g4S3g/PS1BbUgzXkN3Rm1IK0RENUo/Mkg8aEBkJTkqVVZ7Mmpg
S1dOCnokaTVDazM9YCl2JHFaUX1uflNtTlVWYnBTeFU5ZkB3fHt3QGoocWhxRDJIY1Q+RjklUWQm
e1MzZSpOM1BrU0ZXTAp6dFhWVEhOMF5UdjxRKllfJlZKcH10bnhYciloZyhFSnArVz9jJkA8YDxJ
QHh8Nko8TEs1UkVqeSYtPmhNOHZldF8Kel9qVjh+Pk97RTVJUDhZKHROR1dsJj5lQVhrYmI4XiRZ
K0F4b3UqX1F1cDJeYzshWUNkQmNQVCpnYGIhVzM9QCNqCno4Zmd9cjY8MGNANGZidk1BSHkrV1Uh
eyRJdio1PWhvPEVkcklLZGFZaDk9KWFEVyh3WEJUfVJRPDhRXktMUHxHJQp6JHMwOVRQVjZ0Kysx
SD1fbCRAUnJwKGVXKDdpdm5pb2NNXndFIVR0T2V6QVNhdE85bCp4VTZJejh6UXFYSGh6QkgKejJl
NGt+JkQoWnR1JVVxflgwPXZsRVAtNyhHTWd7elArNmlnNTl4UzBMQ28xcFJjaEh1VFhHbFY0YVFT
RCo0Z3Y/Cnp4QGF1JSpXM3VUcWtJPE5BUUA4PiNQaUhEdWsqRkZlcGRtI2pVaXZySFokSTQmLU99
SyFHck1ec1ItVVFVZUNmVQp6d1ZidXRDd0N5YVdPR3phckpDQmRwcypxYXlRJj9YTXYmUUQ2VW1J
YlkkLXRZJENiNyVgVWVsKTQ4SUgxQE9aMlUKek1JeF8+PiRhX0NTaHpXQmVRIXktV091biMoejRu
d1l5Z1BlRnAoOEd8NH1DT1gofGd8VilLZl5gSzFTfD5BQmxFCnpvSn1geiZsO2U3WCNucmo7I3d4
P2FOXygtcEFrKmBTMjJNfU5ie3hNT0NXWFc8VEEzVVgtVXA4RWBiRGcwYGpDOwp6Vyolaj0xYmNZ
TCE5KC1LS2YlZGRwd1JpQ3VYUDthQVkxJmMpI014O2Q8aHRsV0Z5XkQlPGdtb3BPXnJ7YE4oTyYK
eiRHK1VgRHJsdn0qJmpkMCYlT3RfVzt1dm5OX3hZckN1WkopVENnJHAqNXQwKDVqVHRUSzNTajRn
eUhfUyZhLTJPCnpHT3Vza2tNZj5CZz5wakhecj88ZDxCeFhrN3MrZzJJbEM2YGpWPTRQYW9nZi1G
WUg1YVVDXlUmVE0hSmNfV0lOfQp6eXxnaGw8SG9ONyNqdX48OFBMUkFzMjY/TkxAIV8lQkhyU1VI
RXZAT3pTRENDaU5KZUlHNFplTG5SWC1HaCtSR1AKek8tX1goYDZwQGFpT35oe1NwKy0lPTEpR2V6
aHYqY0lRQShjQ0N2UE9fRiV5XmpEe2JuSFJoKGhzeTY7TWF6NVNiCno2JGMzbUJ4Vk1mQHUoJT9v
Jk0hWEZpWXNZQnIoSDBjdkowbVBAdnhCYlB7MnFiZWdjMFpQRlpEZkNTbkVlPlZQYgp6ZSQhU3ZE
Mjk2eUFNRWxJVmdGMTtJckRfNEduMGtyKChLUWtONmE8bF52MllaTm57O3Z3YEIpWmI5ezFWXiop
dCsKeiNxbGgra3hYcihRUHtsbntxeD0zbH5QLSNFWWZPPUttPFlGZStOJk40JFNINm1MLUZSTVJC
VDxZQl8qKyRaI3V0Cnp2b1JLd1lec0FMOTZHbEB5Y0QtUi1CSFdjO0RJRUV8RnJlIVlxPl4tSF99
eHokdHFOdztMfFdfendwVTdTdHoyUwp6TyNyfGV8NTlOTUhTdEEhR352NnFLPk8hN3tISV8wT259
MTk+LVl5Rk9Hb1peNXs/fUI3NnNma1AoOFA2NjUrPlIKeihqdj12Sm81c3RoZSVOJlhRbGFKe0N2
LVZeOSFrbzFiMVgrUV5xVS1MPTckTEckKndqSUkrKldafkgjKW0kVXhuCnpibURqIUFpdU5tIzxy
eU1YUFY3WnR1TzJlfEQyeXY2YlRGN2stMS1GLS03JGY7Xil1N0xReW5wT1NDUCFEV1Eragp6NjF4
X15ALShpWj5mSXIpXk82QUsoS31+dTdFN012c3ZwZE8zNkB3YktldU1+UnFoMFJpQDxLcU1yLVhW
KShPNFQKelBePXRgeEE8SDIje0w1Z2dYNFRqWHdyQGoqJkpgI3l3TGp3KStXO2dpWU5RdE1hK2hx
TSMxUyE8ZWsyaWpYOGtVCnoxekJhQz4oOHxiQmM/eUMzZVJPMmFDPGVjJFpVR09kRz4qPVpjOHk4
b2w0ZDlzP31zfHh1UGxBQFdUPDxwd2soZwp6JHw4OFcraSFLOFdXJjwkbE1xZ2pkcXY0VVdTYFgo
S3dKNkUkJU1sNSZxaD5SM3puQF5KUkckYFNoI35BPztGOyQKek9SM1dyRTJTX2ElS2UyWlJ8JVN9
SXFqP2NZN0ojakxGeFJZYHhOPGFBdn1EMk40KzNLOU5YeFVadkRBYWJWSkVECnopeHgpUEV9OTxC
OHRFX3tTVnA1QjUqYUZacFQoazdefEt8Y0VJVGAyK3hDKUV0RjwhTSt3dHk7SilLKistZENyaQp6
OXg/N05lM1deO0lDKkwoKnxzMVV5YHUyXnhMVDxLbjF1V0pzMkg2UHVKX1Y9TVNTVm45MzVTRTx7
eGg/SlNeZnoKemFPIVEzZkIjMzFjfk1FMC1kK3U1R29Td3BSS2gla1crfVZ2R2FwXzN3V3gwJS1C
LVUpIVF2ZnxufSokNEV4eUlECnpgKUpISVc3V1BAdCg/UEAqbjY/Y29SNWx5N0tzZXlGaSkkK3la
IW01PTJ0ekg7ZlQrJlFERSFhY3gqP2JoTU43YAp6ZDk2P2U1KzU4P3czTTRfWDE+P25jemtEKlRm
bFB8aipKSk1Da30lYkpUQVU5QCp3VktlZGw3ODR4Y0hockAwTHgKejxJbmZeQiUlejBaIThZeGcr
Q0kxWkVjYTwkQFQ7cj9rSXwlVktOa1l3SnIrKDlydj5YYyZ9aCo3VFVoYUNReT0yCnpSQjk9WjIw
RVB7YHBtSkNfMH19fiNmKUwyREJTSEFiPi1hQ2FiSG9+QDVlT3BKRHIzciFhSmhnaXFycSRgUUNr
Vwp6dDhheVUqc182Y3RMPXwzbihQSyZGRkEtYDtfZEsmYXtzT2UjdylBfDR+eF9CJGdVXnJrQFRV
cnBRTE12OF8lPGEKejU+SCF7MzlfeyUxcSU7d2M5SEdTNG1BeUhTaEZ+fkUkR0JoQTlWaDw0fT9V
ViFRbEB2SHc5QjdGR1IxP2cmcj9aCnpmYTQzWFl0NFRxQk1vc2ZZYnZ+e0lANEtJQyhlKDg4cD9U
UEklX3RNR1hleXBteXJmKTdlPWZIT1lPR29jXlM4Tgp6cUdDZkwhUS1uSFJGN1U1WiQ0PkRfdCRL
QEQrdS1GOTFhIV87fVgqfDEoZzRPaWElSU44Pk4qakRKQztKakYwJGsKeiZPZj1MdSFINkZ4XnZe
Y0BNRXs8VU59XkIoRmNRJmVCfEwlcntSUkpEOT47RWRJKj9lPXdMS3EwbCNMcy1xVmE4Cno3Jnpy
fD9ETkI1S1ZnbDNtZHdYT147NSNWbEx3RmZ1YW9vZXJ1elJNYDF7KDVZbWJiMyVfMUBpKiZgeV5w
WHxzZQp6QlY9U31UX1p3OUJyLSFxWDJfMDlIclp0Rjg3PzFXVSsoWDlgK1dhYC0jUGMoYkktWjJ7
ZH5UanVqZ3cjQTdHVSEKenxFU2NfKTIjaVNWWX1WOGsxPjZYZz50RWheST4lNSQ8RGRZKW49NChr
cjExO3J4R2RrRDd7bDhYJkVQRFlyN0FXCnp3JUE7NTtuPjlVJUtvUDVwaXtZM2BqPDt8VDUjakw8
bEdtZDcxTE0tXk4jS3NzP3YhMUh9ZkkjYHQ2XyhNUSE0Zwp6Sz9qKG8hZUFsKTJebURobCQ+JWtn
Wm49NkxOY2A5blNvTldiRTgkc0BSfG4lUFcxZV4hcXw3SUN6cmBnPjFlaHoKelJqQnl+Yk5lUVUy
d0Fpd0ttZm59K2FpM0dKUUV6M2VoZFZKcnloSjIwMC1CZTVSI1hgTXx8WF57RWF1ZyQqVEhxCnpM
NSpEQjFvV2BxOV5ZdEItS3VHbFc0WExsJD9QUVhYI2xHPkUzNilkK1B6QkpwMm8pUXl3QzZVP0pD
IyFDelhOUgp6KSZjSG9gMHdJWVBOcmtKVm08MUdIPTNAaktWN04oaTwxUkdyRnpkcUQ1bzhSPmdP
bkBDQU9sUiNCdEFfR25hPFIKejN9KEMxVU53TXxLbX5rTGJYTD0mV3IpTlpeeyROLSNPXzt9R2Am
R0ppfW58T2I1ektCdWJydnNnZXlXX1Zhb0d0CnpoN2F9KjFJMl5FOFdMIXJzK2RHR0w/NVA0WV45
fVNvSmpLekwjcWN2V1UkTD9oZjV5b3k0bDwleWUqKzdeaX43Sgp6V0ZhQ1ZZKmZzfEZ4ekcqTE1j
UW0talhoSDRISDZDdVhIRC1uWExNV1lMWD9rUlgxX3h1TytXXlclQkF5cEkxd1kKemZUNkFyMFN+
MHd5UW9kK29kWW85akhFRz0ofmhGenhPM1VlTWxefFooUDBDKW4jckJDUkg8eTFUJnhVdXU2JUxx
CnpQS292fHBzWTFjI2xmWSojX3BLZzhgTm10RzV7fWQzK3g+cSE9fXNxNz1VXzlSKHZLYG84MDdw
SkYpVXJ1ajB6cQp6TzIye3c+djRMak1UfFl3PFopeWNwdUNWbFJxZXtoQWVhVClUU0oocUZUVkoz
THY8WU47M2FWMilke2Zic20yUGsKekZeNCV1RmA9JiN7KChjJXN1dX5nTnJeJkl2MTxOUHlFU09h
SnBKMj90cHl9THl0bVNEamZtM0RHXyp4aDhQfjZmCno2K05XMlN3bWQ2OEY7d14/aE1iVWh2PjBX
YjVSfUdYREw/MiZFeTZMRFVTUDFCNDBJRih0X00xZio3USR1NXNaXwp6Yio+OGE8aUExbVRyOFhg
NUM+VnZyS2IyJChecFprYVE0RVN6QG4ocjErZiVZTyN9OD1fbU56c2EjU3pjQ2wjI3wKenYoJUQ7
TTdFeDw4YCk0QnF6MkVYQytIS1I7T3BmYVdGIzN+c249Z3lYdzluIXYxYWE3VGN2KHRRNSR5QD9j
V1lwCno3SzZgM154X21WMSFRXl5LSnB0Z1VBQkJTOW1vRnNOJFg9ODE2bjAmMnU5OVBYJVErJGZh
MTZ1VmhPeVlgPTFFJAp6aU9kQzIzYTNAcDMwPVcwbWA3flJNO31iWndzWElmbyFBd2dzQ2hFNUYy
YWdwTldWKGFnbWp+b1JqNyR6MVl5JnAKemtQPGNCa0ZUR2tCQ28meXlnNSF5V3Z3anhPNnw7Ui1j
b35kYiRuV35idEJCdChuZHhDWE8peVVpMSFpRz0jOz1GCno9QnQ3MkBVX1ZfNGw/U24/P2d+MXhj
eD11dCtOMzB1QEd2SGdnKlNUWmBPPmFpPG1HPXVgVVNfYX4wdXwhMDd9RQp6Ri1TYDxHdDF2NmBw
UVk4UXFRSl5EUF9AbnNaSWlRYzZ2aDhvVVROdWI7elNmXmdEPDV7N1h3eCE0TWQhTnVnLTMKelMq
Wkh6YnVyZHJXenlPJmVeeUkzcUB+fDdkdiNobFhAITtYKGskdjd6eHBTPlIwflN3aSMqVGEzcHx5
Snc3O2ltCnpSS18oRiFTSDV6OWk+aCQrSFQqJTwxVCpuSiR1VE5sOH1TUG0jSHYlK1B3PGRqXm84
RFcheUNGYUgtZHJOVjIyaAp6WXV6Wm9ZYEk2R2ZPP3pZLVZKTkE2Z2lDSzB5bDl0LXdjUjNNTVpx
Jk0tYXJ6bVJwMWxoUz1zKGZ8Sm5LSHp4PDIKenpXdW82TTNlSzYofWdeNUZxfTZRJkttYG4zV3hL
Q0JnRWtgcHtGVikrJDx7MERxVjRHcT4jYlFkeDNoKEh6QWI/CnpVQEQhWnFHdDl3THgrdXQzMDFF
WStsIWJraF5FWFp7ZENvXl5gVUlIaXMtLUx2YD58UCQ9e1NzVUwyTntwcVRZZQp6Rl99IyprOU8m
clV5ZHZfRi1eamdFeURPQVZZNjstQ31CYFVnckpFPz1kR2lqY3s1bzEoJihEd1deQ3pJZD87KXMK
ekRPRHZeJGk0TExCU01WY2Z7N2xuU1EkekNJdFFYdDBxO2VsP0k5dTxFbH47KUlKT0VheGYyWjY4
bCFuJjAzTFNPCnokOXU5e1h7bzlfcCF0OztLPmAxQW95JkMzQUFMUG5NPy1QLUBJXzlATz1ndlFz
PjthYzRkaE1zVnlCY087SWZWKAp6d2FCcTYrWT5TTEU8WXpTaGIoYiRTcStAV2VkJHwkUHxXQkVj
S1JUeSZgcEd5MD5FX3xJXjdeJCp+JHwwZ3gxR28KekFvYERpUCg0OStaMmxTWGhtVSYhe0dfUGVy
SCpRS1N9XkRVNzdAJklNRmUxekJ0VUZocihMRzZaSkpWb0J3OylWCnpiMCVadlFJfWF1Y2xZQSVm
R0s4KUl+cDElQGJuUF5HU3FidV4jbCZ9XzdlVUZwSDwjMEJ8JEpuKGZqUiZ4bGY3PQp6N2BCKTIo
Y1hMc04rSWV1dDY9ZEQmU3lQLXtZa29FeVVEMGMhfj0yKTxfP2xZd3x5ckVGUj94OWUxN1B5ajla
R20KenVifkhsdTZuUjVUMzdXQSMrO3p8ZGsyMlEwMiVjZkc0Kn0rJDt8K3VZOVFqKD96SmtuWVBG
YilWeHxPKU1fWCM7CnpaSmclUyQxSFByWHUqV18lYDB3MFUjPms8JHk5fCM/bld+bkZ2cWt6fEpQ
SXNeI25fP1JCNlQ9clghKkJNbGhuRwp6JU1jWCpIUlhuKilGbHZhc24yfTFnNHtPUmhKRVB4NTdr
RWB2XlhqKkYzQFlNa3ZnWGglNiVgQV9TMDE9cVgqVkgKemJhTFRBc09VNXVDTXhqTCo4UDl+Zl5r
bGZ3OENEM2MwQyN1RmZeemg7YWFTNiNZRUFpa29aKyllMj02LVdNaHw4Cnowe1ZFUj1OQ3NtT2Zq
d0F3UGVtKHFJOFc5RlJILXpBZUtfXy1SUztXe30kPG9QeTVXajBVcXA/T2hMaXlWPzJKVgp6VGV4
RTR3UyhYMnJIezRlJFdCMj5yNlUlM3soMDEpY2IqZVNqbkJaYWtiJjs9Pm1XaSF2NityZUtGR3st
KUlqNFcKenFxYD5rRSNKUVp6YDd2YiheXzF1QGZfbkt0UUBRZ2VWZUdUSkRNdTRJdWN9YkNjJjNh
OGEreW8qMU5rc141cF5ICnpKQCskKGNvUFVoPHhlZzcmTngpczlFKlZkZHZGdm4zVmNXQ3NKN3F+
Uzc5OUd8Szx+eUp9ZnEpI0BDTkBrYFJjTQp6U3hwJnhWK0IhciRTc0FRUntmTkFJXyMxMHVGe1Vg
N0BsTiExNSZ8SlpQdn19Z0V1eWZ6TjR9OVExTj9OTGtaaVIKem1vdGR8M0pLUVJna1gkVDUmJj4l
P0JOKl8lR057KjIqQm8jPjAkI1dvJGRhUDBCYCtGSTk7c0Z3aDZRVnskeCNxCnpwYnN7T1JfPjNj
Q25sd044OCFVa2goTShDQnZvYDxoLWpgX3NtYUJLVW1uYzk9ZykzPUMxS0ZgKCFvVXB4SnJCVgp6
PlVvUUViPDR3dFgtUFViaHtJK3syP34/MVNsPGQjQFdGK1N7VyY8SEZrdndPIUA8UXZiK1BueVlV
RWJHezJCaWYKemUmfnJLOVIhSz5ycnBCciRlNE5+N35uUmFCdFIreE9ZZDx9dWIoTUs/fVlyMHE5
SEg0Q0REcjdhMkhvPnQ2TmElCnpiQTZqI1BOMXYjLUZoI3s9e2omb2x3fXAtUnZMYE17fHItJnd5
WkdtaSYxXmRoPHBjOUppaWo3SXt2SUdHd1hjSQp6UE1Be3o0NnFqPU8yWDt+NXFiKTlRcil1OXgh
M31Oan0zJChUNDI+dmA9IyZSeSRnS3VeJDw1KDk+OSNBbSYlZWwKejUqezVqeEQtYz9rRWd6KE4z
VW1Ze3dkdlcpO0VxVDhlaH5rN35EWT9gfG5GQyV5e0daWWZGKkJOXz01JkgjUXR6CnpVJTlwVmc/
RmQlVHBZcW9fLX5ve1l3bFJve00kSjxJeD9iMjltWGFyM2wjSCZqdERrN0l4NllrOUhJYlE/Pn04
eQp6dihHd1RvdjJ1b29CZFZpdH1WJmQpd1RxcG8wRylyVFZlLSRiQ2JWVVRtTDVSe0x2bGMqRTFT
XitCRVZkNW04VzUKeihseXdFUGdJP3shSj9fKXYkNjlnUjBwVEh0cU8lMTNyZHs2QjM2XjFgdD9n
JWo8I3ooejc0MXZMentEVHd5Knd2CnpZSVg4PSYrczx1cl5OOUd3aSQmcSgyUkIyQUZWWGBtMU9O
YTBXfT5aRmw5M3g5TVYoVil8LSF2MXNONWRnVTl5TQp6RitnI2w1NTkqKlFhYVVAbUYoVE1fPXhE
TksyWU1QUGN8IWkzX0FmTlVDKGUqUGUqRX1PKU47fnYpbnFIKE00YX0KelJ7d25wKVQyOU1gMWc7
V0NKezUybzhzOFNnRSo/V3B7OUFoclkreU4lRjQ+VjEqSCY+PUNGVWteK1JwIyVGSyR1Cnp5RyR4
ZXJzdkdpXjlIamxfPWxiMnI4ciNLKVhHcWVHPkdYUVl5PygweCN0VkpgJk85KEBqd0l7STg4cHto
Qyo0Rwp6Z2UzUGEqayF5aipOKUVpY2x8LUBjLXZOPFRtNClZI3JaZ1B2NXMtfDZrY0Y3OHMhcz8w
Ky1TKGFQTmw9PW9hNCkKejA4TFc4JHI2K0FXKjh3e3pjPUl1SktveihLZStAJk1oaUZrXyRlemR4
bnlZRFdvOU0tYnJQI0Y2TUY2NygxO3QtCno1U302NiRPSiUpSEM1al47cTgtPzlSTjYqYSp9WEZX
YTBKQlg5NlB1KmlSQzIkRGtlPDchfV8pe209KSppfWhedwp6JVM/akRuSEBgbVFrPWx9VShldSth
Oz19NGU1MXpaSFhLR3lDa0BOVHZwdXYzKmg8X01Ydy0xbFlrZTc2TTw7dmIKej8/WFlVZTc+QFgq
OWZeKVZWOCNVTnBJTHotPG10cTskeHFGaX5ARi1UYDBNdCNrITFze3h8NSlyR0QkT3JyJC1zCno+
clVSVzJFamtiJT1LSG1mO2Y8VmR1OD9UT3dzY1FMPiVjZkorUkEzcz88YjJ2SXIwWl9jfjEqcGtG
ZWU8P215PAp6Q0BvMHdgT0J1eStfOTF5dnNKJlVfV2tfKUY2JDhqbH53WC1jcURmRkhWJVhGb349
UTJXI2pOemw+cUU3bTxPMCYKei1uYXBiKlJ6VkxYVDtZKldCSmZxVWFWJDlZcTltdHhaZkQ0UDhZ
UkdNSzEoMiRiVXB7ZUBhe1dXWkNpaXFmIyNRCnplXyRHJXopSCU2SGJiUmpnPXwyaVY/d2dkUiFa
Uilxem4jcE98QSNtNUo3dkNRJmxlTGw4T3F0eVNmMCFxVzZuRAp6MWEqNClMWCVuSHFKLSh1aSl7
cHlAdjxuNyo+P1RfeUlGPi1wVGxeZStZTndSXlViNntrbyRCPUhOeUFMIVdee0QKej87K1BGMHZN
NjJgMU4tfllZeDVnPD93Sk93YEpqOF85bmcmRVdpLTl4M15iNDQwNyQ2U2orSTllRjJyLThQbGlX
CnpoOUdLJXtoem4wR3UmMzZTeyVMRCUoPEhRVyM5blZSaHlUQ19GLWNXU3J0eStDTntkd2BtUX13
cTdlKUY7Ryt0Vwp6ajAlfjRUZmdqUlNYIVVnKDc+TWhuVn04PXBiNmgxYjYmTiN0N0BqbnBOQyh8
XjR8KjVMbEZsWjx7NSh3MmVPQ2IKems4eHc7MUlIMHtiPCQpWnhfPT1gTHRKRDg4eWd6fjwwSnBw
PDE+YDxnPHZqUDcjPjBjRmJ+PDJLVDhVYEZYYTBECno4VVclNmFCdG8rIyZ2fDZtTDgjWDxXRXw0
LWxYcVo9cXFveEYren17cipzQn1PNz9pdVE1SkRAZkJPb017aXBXZAp6OXpUfExpfFVTJmtJZEZR
cWBlN3NGUFJVfE11fiNkKV92KHgja1hnJD1LPkNuNEtpIzd2NDJiVlAtSFdKYCFyPCEKeitBI343
Rj03LW57enxCckdhISE5RDhzTClmfk1jPl90KWZ1YzlTPFpIfGxINU0xVlVhNlZWYnxIK2g8UVM7
NFJRCno2Typ+ZXBlaShZWFk4OW84eWZfMXhHdSVhb3k8PylUe0hXfiRZez40TFg/T2FJOUJCb1BX
aT5mbmBjYG1ZbWN6IQp6NTdCND4jamsme1BFKFl3TDF3cFNlVUBuWVdlPko7KikhUDEya2kkKnVI
eS1zVjM5dGNKaml+YUJYX2NCZm44KkIKekF5Xm1pKDh+SSg0fXxUKkRCTzVqR2lLcDt1bi0lbyY4
aUgxMHRVanUoV3ZuNyhAd1hKRVo0NXtxcSFwJVJEeHVDCnpLJCF+eGJJRE9LWTJkK1JTNjtlQHAw
YVhpUnZJQ2djbW5gNDJ2fHA8OWMrSG4kPWhnTDxDcT4tRk9zakEyQm95VQp6UyY5eF4yKlJFSFhm
WmQ+REFEQ0ohOzNBUzBCLTxCTjYmeURtTmotN2o8Iz4+LVQ3YVIjdzs5bSU+YChlRlZuQkYKeith
Q0lFT2lEb2FEaGpUWDAqKnBHKCslbWhlTChCKlJ1OS1pPkkxKHMpTTJ9M3NsKWAtRm4yTXd3alhu
Tjt7VFdQCnpiUjlNUEo4VyFvPUE9I2QoZXRpQEZeZS0hQ0A5PFV6OFhJJTFteT5BbTMzVTVeX3RR
Tm5pP0x5bH4tTk8jQ3c1bgp6KkZFd09ENldHcnU0RGZLV2J0bG0zY1JANlAmanZ1e3tTI2tlO3NV
Ji0zfmhHTmp9ZjF1UmtsPS1nZUZ9RmtNZHQKeio8SiZAMFo+WEh7NTdRaXpoaCVSLWB+bihRMmFS
SFhfTGJTI3lBQlY3Jkw1Um0qTUJHcmdtbXlaZitpTFEjJjlJCnpYNmhCZHAjPFcqYGB8JiNQTng0
fVdFUSojV0FWMTw+fm9HOCRhVzlmVjdnKUkoUl9OND1EaFIhY1hAYVZGTUEpVAp6dHFHV3BAM1dK
fiVVeX1pMGVmOD9OYTZ3NTJmXl83OGc5YTxiM0pHYS0jTFdUVEtjVSU3Ym1DNS0oS35jV091U1IK
eiFSKF50Q0w9SHRWcSMlVV5VNFo1PCE2I1RTelpidl97d1RDZ2JtKGZmaWFoeU1xYk5nI3dCSzl8
MEsmPj48cjR1CnokKXopYXhqP0Z0enluTk0lfW5ONDtCaVlEK0g+ezJvaWlhZHBOSUtgVkY/V1M1
MTxGYyMpT2BqWjlMblVva2NgTwp6bFlvV2orNzskS0JoP3MoTW5IJT1KO088Nl51aDVLQmszfUw/
bTxtWmxpIVR6ODJpT3VQd0RLYCpjeChlfEshNnsKeik0dlZuOyk+enw0SykrOCtZfCojZ345OGYx
al9tQ1VfNVROVE1uV3Fjdk5QNmNVWE1QfEV4WUVnQmBISUZuMHdGCnotdiE0NFI/KDkoPE1+fm1g
R1hmb15rI3wwR35TIygpY2JMRWd2YEhCNG5kWWd5NTU2I25LRWkkak1nQyFqKmlDTQp6I1piVHYw
dDtyfEZuTXklc018UV9Fb2F+NShseyhybShEcGFJKGpaUnwwNTdSMGtvI2stI0NKOGsjVmpzc1cw
NDIKem40TnRqTzFyUWYwdjNyQD1qdnc2O1gweXBaQVNzU3B0Q0pgdml4YG9gYV90WF40YSgpJXJj
JUZXdypPbiRrY2VnCnpgY01IPnNxXlE9VXpoJlZmRzNiWTlRYT5nJV5WcmdjZ2QxKm5ia3QkJlJy
fnMyTTlrYjhwYWlsS3FDMXMmUUF7eAp6akxiYlRFMH11azh7Mz12US1zMEw/YVMwT05xQmViITJg
bSlpbU19SDRrTHU8bFVfbn1tV2I2SXJmJTF4TW5aJCUKekZ6RFZrfDIkcTVPdCkqLWpFcD9KSnAl
eUlAKWw4T19KND47VTRzPWNNVFZ3QGp1SV5fezh1dVAmN09BfExJSGVCCnpTMXczSDBNd0VXPmFS
d2hWYEB0cV9hPUxyRSR5OXkmYDJ7R0ZqYF8wNyV4Q2EoS2orYEBjUitqRiY4Knk/cDtoWQp6YUdC
JUxgZVlRMHUmSEFMUilnTStEVERga2NPfm8pNWRgfU5xTEp4Kl9mKyYqdyFDQjw5Mnw1RjQ5K2lf
aHg2bykKekoxdm1EQEdjIUpSXj5KWTtDR1RrWSo0enpOakYxQmt5K1ZaeEd0WSRFKmd6fGJCX3Bu
bzE1I3BQelhtOGFIaV8mCnpOVzNESmE9JCNkYzdEMUxmZWY0a3R7SUZoSkgrK34kd3p8SHhlQj9x
VDhrYnJTa3h8bF54UGI/S3YyOX4xXm8jTgp6O25aZzIwZWVQMGBVVGY8O0haV0lJdE1TUVBTeXBt
OHlENVdDY3VrSmgoN3JiQnBRNSRqVjhaI0EpRlFOY1lhWGEKekk1YW1HV1hNNHNlPHojek4kdWh4
MC0hU2F6eT5tK0JeVXJjaVZGJWhEIUY0KmE4MEZ3MlpjOEd3dE08QHUlc3dKCnpSeUJsMWZ1WSky
P20rbCRTWkRRbktONGZ2NFpvdWxjRWAjWSFOSnV7cWVLbWVxeVQqYUs2TndCTWAocSEzM3BffQp6
PXwqOFNOMzlJOWROJlVnNT9+NyUwRENiQzRFciFtcDs3NkR6WC1GZTZmPyNCSH19RmlTVUBTWChR
TzN2R3d9TUUKemtfcFRxWntwUCQrfC1RcytfeztDaEs1MnkzcFJaO2ktWkxBbE5eOXwzbFJTUUh0
KXZDOVVqfSYpeEdGeylzezF5CnpKSU1FQUtfcTk7S0hDdXQ0TEBUdkZ+Rlg5KXczSEdLR1MrdXlm
KDRsdWRvd3xAMEx1dykyUzdke3dmSlpnNCgqdAp6Uzw5TmUxYlc3UGhUUnY9OUdSSCNlSWQjQVVR
WTVsYiZSVCVaflFCSlZYKjBRc0R6Nkw3TEp5OFZHZD5lcnJrT2UKejB5Y34xPTFAO3NzQi1WWE0t
cihocHhWYyhIen4kPHpWQzA3bSFkQj0lNFRMfUk+SzU4UHMpcihTWWxMWjt5Uz1iCnokXzRjd3VR
I24xJih9M0F7JVpQNkZSa35+YEMwTU4hUSl0fFpHZlN9X0F6Y2ZKIU08JDJhVXN1YTd5X09Rfl5C
ZAp6aFRyemQzYnI/YG52TFBvT1dUZzZ2TWFralc+SWF7ZlhXMmVQT15NcFFAez4zPHF+T0RIe1N6
IzJsJkJJRjtRTXUKeiZ8VClnKmMkMmIkUFk4eDFEOUhraGZzakNlNXxncCN0aU4wNUxxaFNxJjdB
ekYqNy1AcEYzWk8qR2lNPGBAS1c7CnpHcSVsbyp2NnpwaGxkdUY5bHR7SyMzVlJ9a0FnJSt7fH4/
PF5RZW9rQEd7My1QMHtSMTlKSnMxVy1SRUsoWUx7bgp6Y3ZaX0p1I0xnT0w9R1U3QVFXPX5yMj5p
YmFLOFd2PklkRE1YKjBfISN8fCZSP0VNYVFnNG1JJnMkY3dvV1k8K0AKenszSihFOzZfeD0yITlr
OE1MNWc9MEhVdnBYQCEwVUwzIWZxYkBDbnJPO1YmUFoqU18rISswViNOT2djOTBDUl52CnphcWFG
UDZ4dThAQGBxUF9oKnkwPmpPQ0w9YlgoUUxAMWpgfDJtU3JfaWhsWFc9TSMyV0d0dFg9cjstVzFA
XkFAawp6MnpVamxPflB9VkgzZWNPWk1AR2E7cT4pbEtQeFY3XjFKVD9jTzR4JmNPS2U8Pyghezc5
e1N7aD4pTG5xJW5KJT8KekFleitBaFFGbSVsbT1vX0tUbG1jYiRGRyh7Mz9mZiZ7SygjJFVldU9q
RFVyTDxjbSVNTUYyX1leNm1FQDwjUHd1Cnp0MCMpJjk9UVpld01IZ1JfOUBffCVeIVQkajNrSlUk
ZTw8Nmk7fn1hQm5wfndnOCtJdS1YLUVuZHZxRVZ5ZyVPSQp6JWF1Y3pqcSFZaEpUQm16XyhfVGBm
WmtlTmxTcmElez4jQDJLSkxQdzh+eStJO3tRUihLajI4MitvTFNpJXZxaVMKUDt9NUNkKW1BQ0ZW
O1M7KUhFKD1FCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL2Vj
bGlwc2UtcG93ZXIuc3ZnIGIvYXBwL3Jlcy9lY2xpcHNlLXBvd2VyLnN2ZwpuZXcgZmlsZSBtb2Rl
IDEwMDY0NAppbmRleCAwMDAwMDAwLi5iNDFlNWZmCi0tLSAvZGV2L251bGwKKysrIGIvYXBwL3Jl
cy9lY2xpcHNlLXBvd2VyLnN2ZwpAQCAtMCwwICsxIEBACis8c3ZnIHhtbG5zPSJodHRwOi8vd3d3
LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgMjQg
MjQiPjxwYXRoIGQ9Ik0xMiAzdjhNNyA1YTggOCAwIDEgMCAxMCAwIiBmaWxsPSJub25lIiBzdHJv
a2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJv
a2UtbGluZWpvaW49InJvdW5kIi8+PC9zdmc+CmRpZmYgLS1naXQgYS9hcHAvcmVzL2ljb25zL2hp
Y29sb3IvMTI4eDEyOC9hcHBzL2VjbGlwc2UucG5nIGIvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzEy
OHgxMjgvYXBwcy9lY2xpcHNlLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwLi4xNTEyMWMwNGJlN2E0Y2I5ZmI2NWZm
MDk5ZDc0NjdiNDQ0YzZlOTBkCkdJVCBiaW5hcnkgcGF0Y2gKbGl0ZXJhbCA3MDg3CnpjbVY7Zzgm
S3FsUCk8aDszS3xMazAwMGUxTkpMVHEwMDRqaDAwNGpwMV5AczYhIy1pbDAwMHx5TmtsPFpjJTFF
Pgp6ZDYtPCliPk0mSi1kQ0B4eUx3ZCUyXyZfSWdwaztnRmgpUlpnYmo4RWoyRk8tP0hDN2RuMmhs
XjhTbjlZPTk1ViMKejZNclU/Y3JyNnkkbWlJMmE2RkZVSTVPaXZqMkZPUXZ6dlZwbEYrYE9tVV5r
YCtUT2VPJXBiMyspb0x8RGZWI1JgCnpzJFlNdktkSE9BLW03PWNKQD1lKiZwbDc1RjlNK0tgYClD
NkJzVkFGaGAyZWpZU2sqVWFePWJaMm1td0g3Y2BBOQp6SyhLUDwlMyMmMVJSK2ZEI15MMyN6d3hT
N3RJVWx6LWVgYiQ/OVl1Z3hZKEluWkBzbGAqU2NMe3h3Nkx8P3NIRlAKeihxV0lBeT9BIXo+WmBC
TCtyV0Q3e1A+cHl0NSZWQEh7TipUMGwjPVg5NXd+JD4rNz90U0ZpUnwmNmxkbUg2T1U8CnpscFdp
KXpIeFlIX3pqaEVkMSlORzxEN0hkcz1nSn47QmNNJGgoSUozRiRIVndLb0htK1ZMSlZNTWB5PCkk
SVlHaAp6JkBEZl88cnh2Rk8kKlozKkpvQypVaE5MY1g8elJmUjBaejxZIUxBTkUzUDxlKUF9diU5
VWRDR3Z8SzhtPUFFPDcKemRBeGQxdCFsXlhKP2p5UVIwU2V9NXJlZWBXMzVZUChvZU5AdypUQWx6
NEwka1B5Zz5Ia0htM2VUKnV6fipLeHwlCnpefHVDYXNaQCRmUj0palJUZW9mZlI2ZHUjSUYySDUm
WT1uanVCeUV2YF80Q01iSntlZ0hhLStrUlRVSH4wQGhsQgp6UjclXzArSX41QT8lZS0lJDMxdGhp
Sn1PPTA7ODdxKSQqRElRUFZzeiFzVkE7eys1a3YqTUI4OUpiWGM9UW8qWXQKek1xKXV+JmRXSUd3
a2k5QWJIRmBIbG1ZZVhIODNLQ1ZNdHA/YCk/TVhjKjBseWBEZyQ3RUE+aHJlUmVnay1XdDNYCnpY
O3tHaDsyWW9Re0Aqdj5APmwpK3lSUiNrJTZScU83XkJ0U0g8Pih+X2c7Kk1Ob08rNW9PUjYyKk1J
eilLbHxWKAp6S1JHfVdaTjt6ajI0aWAoM0o/SkNScXdwJjUxeFBhc3FZTEE8KDlAU1IlNDgoRGZv
S2h5IVI1PXo7dHhCS1l6KzsKenIrKW0wfEdONUtVWm9QZThVP1QtO0AqRDIjVUl8aGUjNXMkM2RK
LStFRncqQmVoTnw1NyRzPVF3cDMxN3dDSzlxCnpAQTx7fFJNaTU5RyN3bk8wdDh8dHpHJWUtcFdE
MjclVDB4MTVvP1UySXFEayk9ZUBUckVpTHIrX0l9fTQ1OGlXPQp6YGFASEtTSW98PldNdj5DQHI1
ZmNffXM9I257TyU8aV9SRk0zUmJDbEQ5dk40ND1jdUtwOyZhQUhnRXBnZykxKWoKem9RU3hVdGI5
ZjVkezcxRz4rNz8zYjllbFFEPSlyZz4qZyZ0bH1hVU5qRzVIYldSdXM3Ny1MTVNSRW9FNS1nNDkx
CnpGU3opX2NYTX4jKlZsSllFQiYkeFB6JmB3Yz09VzV6UE50RiZCYkVUSC0rRXVoJXY/JWkkJVky
ITs5Yms7TkA0SAp6eUwkQyVjUTdUR1A/KEJ9QW9BVnNleilVcXtfRUVzOXZtMXZMNXo1czNwJiNV
dWlsJWs/KFglVWBTS1Vlez5Wb0AKekdPVlp5cXZfO1BDUkJodnVzPTQmb3BaKW5IfUJsR15JR1Ih
KTd6aEJzQV9ERDRVVjBBP0I3NTUjR3t8Xi1jUlRoCno5eCRUJnpeKEBPLXBrJXxMSTNWTypHNFhP
aCVfQyhYPzdyREJOd349LUZ2Uj5kKnxoRTIzKzMrUVFKZm96XkUkQQp6bVlqQyktYVB+N0F2RDlp
PjVEX0xHa1NWe2BgRnFpLVlnPUp0UShCN3A5U2NuJmpTOVA3aFVwPmR+VzFDTVZyRSgKei1kSUlf
SzlAV0hUXkM8XkRkNUxEZ3lTdU12RFclaVBkTkc0MU8wbjFZPnhnVDAqN0x7WFpHQ25eIWpKcz5Z
T3UtCnp1Pnp3T3Bqdnc1YGAqKkh5cFNKeHYjTThgIWFvd1FVT2swO3sofD5pQHhFbiV1Z1YoTy12
Ul9jZUQxUWR6cSk8Zgp6anhSZHpWQFpEMldjbXt1Vn1kenpqe0VCVWszYWsrI3ctfCheI1BvITJF
IytTY1IxJmVYM1QjaVZWclhlPWtvOCsKenEhZSM3OTVnVSR7YEh5PGR8K3cwVHQwZDFAMHVKRDc9
VXVBYm4/fCNVQStYKitCOUdRP3otelAxRiYoXl83JT4jCnpMdGFYM0dPY2pWeG5TJG9PKUZyWiVu
aVdaY2kjO19GYHItVm9udVN8PkpmI0FBUi11SjR0bXNIY08pU3E+WVphRwp6VXN3K05XTHxVZnlz
PyYyc2wzI0E5aylxa2BlSkg9UlBmI3QjU3V+TGFOZ2wtNzBUMks3YlU0JDlhRThPWkdhaUMKejIt
RWtAaTFTTGhSNmZhQWkrOVAhZ01qMkNjXkFqXzxiQH5BUVB0fExuNFREODVXcVB7cDtEJENNfGZq
c1g+RnlhCnpyLSN8eUdkUU5CbGdAMEdiU2d4UTs4ZHgmbX0wcmlOVT16NkIrdDskRmhqI1JxTm9C
MHF2fHEhWktKM3ZRNTROXwp6YWNvN3owczl0c1pvVCFedG9Mek9FdDVQfFNOVTN+amF1ZyZgSD5N
Uy1xRl80JmVEWlRJT2x7RFN1dVlSM3A9XzwKenQxeV8pdjJBRjhaRyhIK21DdiFhVHdvfXdQKkhg
emw1V2l+dWN3UHNKMzg2QmNRMUdUYFl1dnwjZnNUQ0VoemdHCnpWcF5laUA0RDhrUzw/I1NVYCg5
OVl1JkM7b3dsTSg4fVcrPlJ0KTgrTGNVbGUrdCRWI216fkxGJWcqTUtnLWUoKAp6QT1gS0M8bGc2
PjthbHNVPEkhRFBkMng3dlR3TGJCcDxNZ1czSyhuPGtQZyMwPWE1SitBX1ReZ3ZYOztXU2QtKykK
elJIdXoxMm55PTdiPX5qUnJLdUBecTZvc0Mke3dyZT0+SG9UMGoja1VxWTVMJUJKKmE/PUlUR1pn
YiR1fDk/TSQwCnpDfmV4eEtpX2REKkZXPHBfd0Mtc2glMTl3TlRtbzxtZSNRQ2ZLTkRIakg7Umx6
ZEd1akRsVSNGI31PaHolMzlKawp6TUhtRGFHMUVkM0gyRGhsUlFGe254X19vYHp2YVhSI1RyQkdK
JHJ8VFNhfEhRZUQ7ZD5AdTZrc2E5bV9+PjhZcHEKekA8WD9CJVpwRjV3VXxweGRZQj9CO2klYkcp
bnVGNkF1dSkpc0JQSipRSGYoSmFnMj0mPV4jWlcycjtJeTY9NVJUCnpQTWNKKDBMRUdkTUBIeU1y
fUBHYVM4P3FoeW9FVk1DSExzRmVDNSU1YFIwWnZkOHc0ZzF9VTxjUnpVSHB4SSt+OQp6dEdiPnNt
U0xuKXJXOGVGUVh3cz01RHtyO01IdEpwUHlqMjJOSWlvP0wlaWU2di10OD1TOTV4KjRXOE0remRa
ZFkKekgjfmhtJmtWanE1UU1hYUVzNDNGMWZmcmFrU0skcTZlPWFrYVlReXU2OSViaXAjJS1EMEQm
PiZEcktANXpKQiRgCnpgMCk4RjNEJDA9fEhZQGQ7cHlNO3RyczIjNyFgYjZDJjVwSWh+VSZRVHE9
LUJnPUU3RkdCJCo0SypsTFJWfGY5QQp6dkZ0NjNhN05FOHpXRkRBJHs4SXEoY2VBSlY9cnl6O304
RndNfE4kY0hRZlIqckdnKWVSUUd0N3E2KUVodzFxN00KeiN4I2YkOTRPb1Vvan4xcE9mYFlBPzlT
KFMqV3kkNyl+N3lBK3dMTHMhTjw4e19nNFArLXJNTGU2PT0ofTY4cHZ3Cnp7Q0dyISpnSit4QlZA
eEMhWFRMUERQYmJuSHNsbXd0KSlNZzxLeFREO3Bfa0xLVCYqazlsYGN+eyZEK3lLNj53TQp6SUU4
RX4tTFMmMUFxWERHU0JobEdrWndTfnB5OEgkdHVnRyQ0Umlmaj1rYSZmZjEzUWAmeXdBLWhnLUw9
PDNzblgKejBmZi1ueDtjNVRtcztSQlFnc2o7WklQKj02ZCo4JEo7ZWVhSk0kY0ZgamJ5Rl53YHNN
XnlnVWYocT15VG83K2VrCnppIX16e1Y1OF96OEw1PTB4VldLfHBrV2pzNU1pS0Y7K0BBVzxtO0ZK
NXhNNiNrbGkpRkwtfkhMeG5+V0NPbCNyUwp6JGRgLTYmTldRN3dJTVFyUilwYT07PFQ8fl9+eDdi
MUxkX1pWcShXMGFlVX5XcEU2dTIpMCM/ODg/JTJmNmVWOU4KeihWbDY9UH5VcSFrISt7ZjB3QEFS
LWpmWWRlRGo9KD19TSgzI1dBZzZubT5LdVBNI2xsaUVNYWUycDx5MSgwTkNwCnpRcmZSPz5Rb1d6
end9cHM4KDsrbnFZOGd9X0ZHdWliMWVPWkpUbyhge0tNTUVgTyo1UFhpR1A0c1B8ZUM1aGAmKwp6
KzFmZnMySUZOYlEpPmFOMiFtMERPWG49KTwwcVdYUF5teVJOVT1GTCRQSkkoTG49dCY4ek87bl96
QDlgUVJSPnEKenJZNEk2NmApU0w3ZXlpVk5Ab3pWPld1VThzPkkmWVZndnJfc3IlV1VBMCV5cVk0
N3dNNERVVXFzRkZCQGI9eCglCnpLbD4+X3l7PHQ0QlppPyRuVTV8JG96dUgjRjxkRnJrcVVXdV9q
Yk8me3opPW5yZVZeJWxaQSotaiQ+bHlzTWMlTAp6VD9lTFEzSns+PVYmLVElX3s4RWZDYE0lcmtp
emdrb19tQnNyQSMwVjZRTkVqaWMpZ1hsdlFDKCR6OFQkJGoxQGEKekVJTmdHKj4oelhNQW9Ld1Ym
RW0jWTxWRm0jWDc9QWUrQHkxVCNUQ3tONE0/QEFWQXMyJXhUVD97Xk9UWWlYdT01Cnp0PnFzI0sw
fmZ0QVNMRHFiXlJ0clJqSWhDTmZWRCNmWFNiTWowcEwtIVg/S1kmIVRKPmcqWU5EaFdfRlJLaVRw
RQp6Q1AqRjhqXjlMeEJ2d0dSKjdMYzNVTy1VcUVQeilmWjMzPzdVNHJ1LVJpIWx1YDFRX0J5ZkQw
JW1aTU1zMEd4VXYKej8/ezx8JCpMVX5GV1h3WF9xdCgzRDdjN3xKN0A1UThNNyhHaVRPN09jV21F
P0kpYGJIOUNfVlFsNHpqTEFIU3smCnpBUDhtZXhNMD5peD42eUxhfDl2YFIhWkVyZG1DY3k1dTVt
VkJ9OFBAQkchfW9EUyMlPFBBSFopQTJTIXtlS0gtMAp6V2tZVXxiQEBSO0pNfnBGUTtFfiRwNDQq
Oz58WVR5aUIzU1c9O041M1kyfnp6OSFoWnhzKVdZeV5pViR8UUhnOVMKempYUjFKS3ZBNmNTVGpp
alZGS0NLJT5zeEJDRmVNeXQmNz58Und+WWNDV2BVdyY+cnhPemF5ejBjd2dVMWE5bG1XCnp6T1R0
M1FwZUpjWlpnSkYmPFgmfmQpRFdOS3BNTXp4P1hyWk9wKyV3ayE8VCs2ZV5zVT9FKzE8WGM/ZCEk
ODBPKwp6c3xzK21CbTRDJnMwVmRaMDBqYWcleGheJih3P2RhaEp1UzJ0ZCFzPSReOVA7Zmc/OHhA
VCM8IWZTS3RHdkc9R1oKekNvZWgyaD5Je0g0WTQwI3Mrc0lXKzw1QSQwQkxMS3UmR2ZDMEUrWER2
aUZ6PEQzNTlnPktnXnRyemxpTmRYb21tCnprZz50T0RqMShBIz9jKTZQZlhJSztxYnJmNnhJVk1p
cDNDQTlVVX47eEB7MXdzaFImfjcrN3NZUGBBXktPOVV5Qwp6d21ERzh6SktFRUQ0cWJKKWRXZjRC
T0xYIWZCLVVDN0k2YUUpLU1zbno3PztVNTsjPmQjP2xeeUI7Q29IKVNKMn0KemZLcDhidEVVamgp
cEJebmRyIXQjV2A+eitTYUBgIVExX3ljeTZwQFM1c0o8Kzk5MXdYKW19WUgzU29Yckl+Kms/CnpV
PFhJNWpWVUs1RD58aTRwcGolTGN6M3lvbTh1VT00Rnlsa2NHN2VKNlk2YU4+Z29lVD5lKjd2Vktm
UTwxYztwRAp6bChyZElZbWRyR3BzQCVeLUB8JClnWF5BdVR7a2pSJT5nTipOaFdZZlliVWVQdHdp
ZE5ZQ0RraEUzVTZkPlEpcjAKekNAQiV2PF85UmNDXkBrelckJjBCd3MyLWc1M3pGeEhmS0ljUHsw
X2UpQW8+aylOTjt3UzAhYUVGQkZFQFJWb21XCnpHKndpdXF7TUxIajUjblZgTEY0TkhIa1J0Qztv
YjcwdUAzcnlpX2pvUkJrV25ZT0BDY2lnQ24rLUUoTTlXdkNwYgp6KHx8eUF7O3gwbEU1SWJIb2Q2
WkB4cCFiRVJ0NGBCS2BGWUpCYHV3dC0hKz94aTt1YyNLdUpjd3NuO2dhRzFTJUwKelA9JD1Le0FU
WUMyQkgjeTJ3R2hidkxha0hgLUozbV59TUpDQSZ7d2dMU0oxS3pAdWNXPEB1Mzg5dlJ3QWk/TWsx
Cno3JDZzd2RFMU9Sb1lLfXE9X3MtU05ARHUwblZSaXpiPkFLPzJxb3xNJD9pPjk3K28yUnl3WWh5
SzZjeV55bXY+OQp6QTBSLSsyNmVnamh1e1FHe15gQVgrSEFuamA/cz1nV1NFUjMmWSVUYHFCOEcy
PTZGdFBwR29tM3VtV0N7dE8tYnMKend2dyZDM2UtSWpxKEk2VGMyKXxrZXJXQChDY3ljYDNkSEpa
dm5mOD9kKWt6QFBNS18hcSV+ZW9Ebm9lK0JjQ2EkCnojUHE2VVpOTHdBWkQzT3xONGpQT1IyWWlO
VHNDN0tAMEB1Jmd9OHp9MDxDfXtOc0JLQytvKyhVO3FYKmxPV2pjKgp6WjdpRWhkSCFMP1RDJkZD
WUt1YihXIz9HY2RuVThQUnd+e2ZRNSF9REQ2NDA3a2ZBNClxMkhDMFhsUlBBPUt1dyQKeipEVH56
WH0yTV8+e2AjYHhqa2VoaTNrS0pJPiYtXm1jTipQN0xuRn0kTHdVSEI7Qz1AWmtAXmNYa0BnWl5p
KCoyCnpQfHJscnhJO0NXMUJjXj98Ri00SChlckU3QXNtUnhUcnMxVVBhUyhRZyh3KiUoO2I2UUAt
WXsrOW17VENWWHYhQAp6IXFvTT9rSm99Si1IcVc/PT9xZipWc0hvRitxc1N8bkBYQk9EcCs3SnVK
QzdiUFVXKG0xPzEhRC04amwzNm53PF8Keio8PEpxR0NXb3FwakNuPy13cj9KY2VMZ1plcj8tUkpk
KW8teTl0UFd2VEBXYFJ9MjY5ezVTQlhqXm4xUzU/RiowCnpBOH5yN257JV9yYTdUVXpxMTN4bUBX
ZjFUSHx1TVU2ZVNSJDtBMXxzPUBBQ3dHTkJrOylnUCMrJEJPV2M8SW15egp6X1NzYj5tX0V9JVA1
MzhnST1RbElLNUtIQERYR0pmZUVLUTF8NGQ8eyRnemozVDdqbnZnTTUwXkJOJnA1Vk8oPHgKenko
MlcxWiFLRUUrcSZrR2tJUj9fLSVNV1h6Y2I8XiZUUSVDQmkkIShUWWZ1UjtzUjswYiM/cD5yVURJ
UFBoKFpPCnpmez1lNytRRkIkSzJBJEBhVWB6cEF9O3dEZ1lma1FaeyRQQW9KaGV7YU1lWW1NI0VH
K2ArfDNAWUA1d1RYUG0lbwp6YDVpbl85d09UU15acjtHTWdidFAxbD5XJTVCNjsyaFY0KCNCMDtz
NUZsaW85QHM2XjBlMGxFYXs2KzZfR1I4OUUKekJDSXJxSEFxSWlQfUNUVUBjIS12VC1DWE5lO01B
KzFFb0UqSEpJP0IwVXNMV1JHREV6elNxQmpxSWNZUSstYj5VCnoqbklNbzRUbXhpbSRgRHIwIzBl
XjstKCE+YkFONihmaWF8d3ReNTlac1A1KUxofTA5fEk1Rih0JUZiVHFyZHMmSAp6Jj9YKSg0PHZi
eDFgfEZzbTw2Y2VORyFwUl9ITj8oRXNycWJWcD5mPU1TWFAjayszJV52bW5nIWNNSU9nbSokKyMK
enRXPGBQeEkkYz03VjJSV1k5cnBFNm5zcEZPPnQlQ2RfRmFFMzdzfkAtdyhkWEJqdGdyKj42bDVf
UEskdkQmMDJaCnpTSHJ1d3JnQUBqS0lhVGhafFAjZG1HTjViSXB8eyljPCtuX3lzM1FfS2k8MkVw
QUshS3pmIX4pTHN8Pyo0c1h8dQp6K0d0bWxpdSUhTT5uKyl0b1MmVl5hWHx+dVIpK2NVQEskIWtD
MGZLYk95akZWY3k4ZCFoWU0zZHRWKlgxKmlnPUsKej9aeVpBPGc2M3Y+ejxFQyRAX1RwYnB2c2t0
UFN8WXRSLUM1SElGLW9ja3FraDlqcV9zQCFuJl41TFQ2O19SKHI4CnphajtKKykkY1cxOyF6Xj9x
Z0d+NHMrRkBeeD4/PmJnSlhqWE1lbiNIemteP24/NHFLY21XREk/Mmc8aExlMVAjZAp6UmF6diNw
P3IxYyk3K2NlJV9uRF8ka0tFTkJSKT1pMH0mJGNEUWFTZHxFT21ubXZ6cUwkPklSTiZGfCpQO3Zt
fjkKejF4aSg9c2NwYjghaTM+dUVraEEySVFCSmY0MkB4U3MpWkI3YzIzUTd1Xj89di02VCZuZDcr
JSsmWEhYX1J+YVRQCnp3aUBhK2xKRjt7O1N+VXFrIU9IVDh9aSRjZWplWDZ6PGF2cGFiO0k4JEVJ
MitjJFh8MWt0QnxhYVoqd0FoVV5UXgp6WnRZPm5TSitlQDtlfUY7Yj4kcX1xYXU2YkdJPHstaite
U0p1bmE7VkxNV0QyWXc1QmZ2d3tyc1FteW9jUyFVWXwKekV5aC14VU1NQF82MkJ8LV5JJmxnQ0gx
c1EoKDg5UjJwXmAyMD5IazZRSllEdSFUO0hfaylJRm08a0hTTHlzaUNNCno9QX5NUkBEI25QJmlQ
NnVfRXFIKFBFNUQ2R31EMXNDfkN9emleO2l8eXBKZShQb3k1THpCVk8+N0dyNDxPREtpXwp6Z0JN
Sy1TRXw/WFFlNUtFKGZ8KD9fY0d1cldVODs5RWBxTnllc3sxb2p0NEw/ai0rXl5CUzxtaUJFSGtW
Zmk7OE0Kekk1KnFGJUM9YzcmOXV7UTE3Y041PldEbDxjdUZvQW05QF9uaWxIWStHbX5eO0B+YytC
c2E3OURwWndufCNOeHEyCnpMMVEqbTNPclVDO0Y8QztMb09uMSV4SHJQKlUpIXZWKClITDBtM2tK
ZlVEfmp5KyYlKkFQfUp8Tkt3PzdlO2VNOwp6b3c9Uk40X2k0aSk2SG91b2c1ISM+OWlAYjFnSzNP
RzRFN35RQyMpa0hFVTczRishNVI3bERjQExxMXwjUkE2bC0KeiZrTDB0SkU5VH1QYmh9MG5PXjM7
Tj5yNktGaCY2dUZKND5gQkwkIylOLXBhKVAqVmhwJnsxezl3cDBxTkU5ZCM/CnpASyhCUCRlZElR
XkhReEc3aTU/anEtaSQrODNfblBGeDdBX1FjcWJ1MXNebHlCS0VpbnlQX2dIO31XfiNHUSZRPwp6
WHxsSTU2b1goVnY3aElwcEA0e3khdCYrSSVlNWEwcXh9aWgmWVJvJl98Vnxjc1VxVE8mP00wLUF1
IXI9RnZnRkQKelpPUFdGV1BWUm89WEZ6Y3w5I2FlajU+cj51aXJ9STVaWXdsP3RZZUg4c2ImZWJh
cig7d1JQTChXZ19BTDJ9bUA8CnoxVlB+RCZGJFJ8b0p3UTYwUzg0UGFuPlg7PCQ+KH5hOCE+SGRu
Rj4/QDl6WWBoPiNJT1pHRVloRE52WitxRUFxTwp6QWgwYHZBYUVvRCt9RVo2PEdsMGZGI1d0Pi1s
ailGPDM4T2R6PTtATlhxcV5KTX0oa1g0aXlhUEYhUCpxNHlwPlUKeiYmKEB5dzZ7Tk10VSo7OVZS
M0N6SW9LTmNrJSsyX3Y0KDdXK3dhSHoreUphJWw/UGFgWHUqVDJSMW1BYClhK0RqCnpHRmhtcSs4
fnZSN2NYQTtLPVB3Uj0zX14/c0gmWWVYYTRVODFfbjx2WDhKbVVPJUF8JHVlUTZwYF5sfV9IIVpJ
Xgp6YDNuMEIqb3NLcChiNGZVWVlvdF9FMHw0UUohLTk/dEUyc0FScXViKSFqRHd8NTN1QjwjczQ9
PGh0N0x2JDM4KSUKemA4OXBOeW12TkNoaT5zbmkrP20kKV5PbVM4eHNWOXBFSVpUU04qJHBVc3lG
Mk9AQ2x8PDVibm1vSF9IWj9LYCU8CnpISThHJDd6RyRWJDRlWj9eIUUxdFo4ezkpTlFlZkhjRHo+
ISElKmZnU254TS05SypPbEtUKWA2UkZ3dHU3djleeQp6eVo8fmZgX0NDb3JXSD1UK0dDRUhgUCs/
flV3bWA1MythQm8tOSVvI2g9QFA9bCUtJEhXSE5aP3NaSiRSU0lGS3gKelVkeTUwY2B9KWRvX3kq
X1UjdzImMk1xWF5PWlpyMGo1fjRoKHdueiMtRkJfMiMhUkV5ZmhHWE5BYDxrQG58dCV4CnpiPGJi
dHl8K3hUK1dUXkd6VzNnbiZ3VGJqZjQ7TWBiRGo0LXBjeGlVQyVwR1E9PE11Vl92ejJ4X3l6QyVl
dmFRKgp6VVFQa0RrM1BCWHk2YzlQRW5qfGhUVSlrViVeJk1qK3FMSExOKGJ0a0JpcShtS0k2PH5B
Rys/a3RBX2dNZClhNVAKenlpKDVKMGBBOyUmaSYpKCl+PnkhUjRoNFRqNSZuQVljZSZjX3Vna1I4
R0Yqd0NEK3tsO1FpbUhEI01yaWdJN3hSCnpJdnt4UDtSbjhkIXRvMH5tcmlHX19rSnt1KnJjSVFA
NFppX0dqYEYhPDNJbzRMbDFuUCNCViFqbURpejs8aUhwYwp6cEstPDtLRCUrX2hRQlRyaSYkZnZI
cDliKUspXlpnWjY9ZHA7bGYzcWY4dlFwfEdNaDgjZlJ7Pmhsfnt3d18/VGwKeipRe047X1MrKlBC
V1YkZE1XaClXT2QqUUs+TlV0X3YqamdBbVIkRzExSFprY3h8KH1QXl97T353YT0rKWFSMkBICnot
TGhpRSolJFRuXmdKaEcwYEkqWj5kQmZNUi1FQDwxcnlBZUcyezZhRTYlOz57YD5Fe01POXpYPzJx
TnVGODlXTwp6ejVWdnZAQjdRWXtQWGpBZCpeKy1DRFM2X3RKUzJscVhVe3JxZSpre2ZoND08KXZJ
bUV2YEJDN3lsPnhkISskeU4Kel9TPGl9azdVayZNWUJKYSpYcXEleiFfdEI+cyNOeGFfI2ZhLVoo
Zm95c31hJENsN0AtNT8zRHdVTW83U3FPYXFXCnpNKypuc3FwSkFUZCNgfkFna2hTX3U4dzxfRUlE
Yl91WVl+I1U1UV9RYUJ1KFJjczxnbmJ3UDFxbkJ3ZlMmd0pPXwp6JjZ9PHQmZ0N3eVI0UyZMSCRY
JWpBfWFlVUxzSlZUclomIzI8JXVlXz5NVXo1VkhqI2hYVTh3KyY3MSF9QUEwQ18KekthSFhZNjJa
VWIkbjA8a1YpTyFuUktVZC1VQWxiWiMmdVQ/NGkzR2VSNFNid01YYDB4cTNXdyFsYmFGYiFBVWx5
CnpoIzBLM3EqOCYpV1lTTXtiIz91MCFRdz9mez8pKFZAbntye1RLVSZCPmkwan07YlQ4ZFI4QEtS
eVJTTlYpMjgrMwp6PFp9NzUlSGA1WWFVMzElb1MpJm5aJmh1c0VzUkJrKmNlbD0qNmE7fSlYc0R8
XklTKHFgeT16YEZNNFJybnR5cyQKekx+MHt2KWJidmReQiNeajhIY0dKcWlRT1duNk1+eyYzQ0BE
Q2M5PEpANiFWVm0xWWlNNEJnJEs+K019JHtAQk9mCnpKclY/Z191aD9mPGA1KT5vSHJpVUhKUW5y
aSkoWCFFejxCYjduQlpfKzh9fmBSJmBTNSZVIW16UDNQfj5zR0Zubwpae3tpPUlkQEheXktxdnFK
MDAyb3ZQREhMa1YxbUVCMihiVkYKCmxpdGVyYWwgMApIY21WP2QwMDAwMQoKZGlmZiAtLWdpdCBh
L2FwcC9yZXMvaWNvbnMvaGljb2xvci8yNTZ4MjU2L2FwcHMvZWNsaXBzZS5wbmcgYi9hcHAvcmVz
L2ljb25zL2hpY29sb3IvMjU2eDI1Ni9hcHBzL2VjbGlwc2UucG5nCm5ldyBmaWxlIG1vZGUgMTAw
NjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmExMzVj
NTRlMTQ5ZWFhOTBiNjEwYTY5YzhmOWJmNmRlYjA2YzBlNjcKR0lUIGJpbmFyeSBwYXRjaApsaXRl
cmFsIDE1ODI1CnpjbVg5X1dtc0VIKCs9KHFNVEAoO3lGPjkoK0AqTU40VWl4JDQjbkxJNmZmQFgj
aTYqbnlJYzczeXgqVEJDKWJ8Ywp6Kl9uSDBYR2JENSlEJHBLTmwqYSowRVV2SHRRRyhPMU57akRL
dF9hcThNKiFiM0lLP3VEYWxHe2AoJk1VXyt9WF4Kel8/RW5EJmsxPi03YEl1Q3EhNWxvd1hZMkdC
ZCFwd0lQI21GNjRmRSNCNjVkMTtpbW47QWQmJWRDYVFudnJHQEVACnpxZWJUbGxebnlSPFQ4c1Vi
Y3wtSlBHQjJwVj1abUNeTHViRlRpPjhLU1QqX2V0I2EtNzlDJmhkVXtKWnpXYXVybAp6O29OYUla
fEVFfXZ+JVNuTioqX35WQExIKk1JeSpmOXd2TlBNRk1NKk90dXVxbS1oX2VBM2g+dzk8fiUrdUhG
dXgKelB7dzEoNGNRbW8haUQ3VUBJM3I3bCZiMCRkJSRzVjx+Sj5ZNGdXZ29DK3lZNzN1JlV6ZTx5
ZD8hO1ZYfWJad3B8CnpeTTZkTFBpekB5SlV7MV9TRmlCSVNVSmt+UEUxKkk2RTkzcDw1Y1JgNihq
IVpSVXNPMzZeJm96OCk7enRaeXJ1MAp6NEQkKE9EY09IJUlQM2k5MHpwKTwrbD8waUN4JlI+LXNq
Zkp6MFFeY2x2fWpMc3wtcTYlWExeaj9KJUMjeH5AODkKeipHRE9hRD44PHN4OUQhQ1MyOEJhbGAx
azM1TFpVaEJPfkB3a2AzP2tiaEpwWCV1REJBelY/MWMlVzF4eGk0eTRBCnpWez1+bTclRFh+PXlo
N25gM29tbCVVJig1JDU4O19pNj5CKysyU2pFdEwlYH5ASDgyQ1R+e3RwMGxLQW8zd1MlZwp6I0tP
IXJGNGZqbXhicComNEpgQHwzaVUrRCRqV35NQVA9d2QqaVVMbz1GOCpmQ3l9KCs2LV50TTJaSmUq
ayRLV0IKeiNCKjJ2UDB1fVBPdCRCRW1RKUp1UkgrQnZDdVlgajV4Q095e0JBK24tS1MrdllhbT44
PE8yXlhVSTNERzFXJVVWCno1NSsrQl9vWEVROW1VUUVJaUhqVnckdFlmKnpufFY8XyhOP1Zzcigr
RCtoa19TMkp0dSlSe2N9TVlVYC1mclZVdgp6IXdhNCN1fHppfk4qTWltOyZnVHZIKWhFRDkqZF9n
eEhTWk5AJj51Kl4welhvUU1SMSgqNn1qJXQ7a09NKVVpc2sKenJ8ITd0TFJOe3ItO1FIWHlkNzV7
S2VvMkVffnpgdCRaM1l3dkUjSTlzV0l7S0VBZ3pEQiRsKWdJaVJjMmF2P2JKCnpuaUtzVC0jPEoo
XzRrPEdyanJuVUZLQnB3RS1gKGI0Sihfby0/NzF7OCQ8cFlyOGtJVERxREwyVHpJS2t7Uyl9cwp6
X1ZSR3JRZnRJflZCZiYzYnAyKENpe3sxQTdtX25DdVNrUHshKTN0NG96RDduRllWTTVqTD8raGMw
SUUzYz5WdEgKekFmY2w/SCM7OypMWChDOFlhZ2wqdURFYVB7UWg+cnw4NE9XKGtUWEhYSEZnTWNO
TnZTXzR9R3pIc21mam1AYjc0Cnp6bCg8T2ZpPjtuQnZHZ0dgSzIwa0xoPTVFWCR+MWh6VW5SQWYq
IS1uRGtwZEg7SGlVaiF8bHk3UDdJPlo9NngzRQp6VEJfWUUjR3VTbExQV1JANm1eZT93K28mKFhs
UThRYV8pSjNuYV4/XmUxQVJ3Sj8ocTU+fllpNWI2UTY5cnNKansKeldedyZjNHx2QG5kXzUtZ2hR
d3ZCRz98SlN2MkpKS1JXQHVZME0qXk12Zk9QZUolSz14czhuYEgrJFdCZit1N1d3CnpvNV4+Mlc5
NilQK2Y3XjI/JjA0WSlXKiZ9Y1BBM0J4M2xWUlM1d18pUkkhJVIxfGtWaEBrNnJ9ZihJMy0hNVde
UAp6LWR9V2J7Izx8QmNwUW0/UjRBMGZlNUU4MiVzfU1pSl9nK2VQO3tRXmRQOXlteXc0WVh5XjZH
Pz81dlp1QX0oITIKeip8eDcjWGlCJGJgeT1yWkNsQj1OZVdwVlFQMkh9LS1kfip8JE5VYSktKntj
PihZcGFVdmMwNHhGRillRzF6T0F3CnpBdzQ2eCU/cChgK2BJZCRtczN2JiswXnFKdWRVc0VSdWtK
KD98U1JJZlRVfE5RX3FjZ05DWHZmUDBvWWdvK2Qkbwp6VzYyeUh1ZlJDKitlNGZDKTF5JW8hT0Rp
N3NFeWZIIz54aVEmRkFONVpZK3UwT1BlYWNrLWVyPndeMjQwI2VSdmkKej1kNXA2I05GJCEpOU5O
M0MhcDdaZyhsfDxGfV9HQGlEUkpYM3Z9STc2clFnbUdqeWNZSzZma3x0flozPUl0a08pCno3MHJh
QGVtOEtQaSNkWjlKUmpFR0ZMYj54bWlaPGxedyFjJmZUQjQ4RjU0QTQlZEMzIUV8YmVxXlBNaiY/
fml2Tgp6X2p4ciNIOFd2IU50bk96TEJKSyNqYU82aCpLcyh8JUVrc15aPD1pRyZgdnImUEVCfVBq
Xz1LfU98e3MyITI1eTcKeiMmYnJAai01VkxubXdFYjdgMU98JkYyaWAwKDElUzFjYEJTZzY5cUpa
RjRzdGRAeG0oY1k3bjtUZyUlRkN4am09CnpCcD8lNW9lI1IyX15LQF5EJUpeN0Z3NXxSOVk9UXlV
Q3dLN0MhTUBneCMxS1hmcEdfVU4ofXxjXldYQTc7SU1oSQp6KkhpJSRWQmJwIXJBemRNbm4lQSU1
c2E7NmJpZklRYktwV042OFpCPFBmJWI8T3dLVz1aXnc/Vm88RX19MjxCbikKej9GOTE3Q2VWSWxK
Vi1SayRfb2hUP0w1ZjcyeigyOXNDPkVaP2dxfitLZCQrYVBzU0o0JiliYHNOc19sLV5sKV9qCnpI
diYjc1JlI19WaHFQTiZWQ0AkU2FDWWNoPiphIz9gcHE0cnZyfm9TOShWOzV7VHdvNUZ1VHlpOzY5
b0M7UXYrfQp6N2pQYHl6MjJ7P1BfYVFuUD5RJX0/N2h9LStTUFItKTN5NUNpJmllelp9VEZTVzAj
ai1ZMFZQNV5xUzVBSWtNSUAKel9NR0Y3e3Awd2syeFlqa1klaHpjK21tOzA7QnskdnA8dTFELTQ1
RWJTazkzbzYqV0lIdGI0QiMhfFUjV191RG13CnotT3tDYkg5RENSYT13YiREbkBuTko8WClWYHxJ
NEBAMHszSWxVTVN8VFN+Xzc1ZTJPUVRUZzcmb20mfFc1KkU+fQp6V0lkOUImNF90MDU3U3RJa0Zf
eXomZDtfaitIUThmKWxoK2N0KUZreldeUmNnNiRtKDBoZGlwWUJkbl4xbUcxU3EKeiN0eW1+V14p
S1YxZEV2WkspJjw5eVZBeDhpSUdvRU9YN35SbmJ2R2l3PUp4X1hjaGdfKmJ4YzRiX25pIUVjdD5C
CnplfndXZGMmNlplelV1amR6QH1rLTVENVooTDU4VSkrdWR0bkJITn5ZaT84fTY5QSN8QyQmb1pV
Ny0+OHxjQTNOXwp6N3QrciNGTWp1TG1WI0I2UypeJCtrVVp8LWtjIXFKV0tWZk8+fjhuLWBgS3JU
bXchPTtJJmhkdXZ0ZVk3UUhxWkAKemg5S1hZJjJCU3NHMDFUQjE1bEpGTGAhKURgVjZfeC1TRGFs
Q3YlZXBGLW4qTFVROXZuIz9GZzFsQEgwVF96VzBnCnp1YV81QlY/P09kK2wqYyFqZHp7TFladnx4
QypUV0w8aDQqdGVwcC1IPm9KTUAlUiZtSzReZlo5OCQwUEFaN1lsUAp6JGlCWFgjUURxMHkzdXxQ
M1cqJVU4VVhCbTZvOCFIMGxuX0JGQV9vP3tUcChKY3Rra29nJStBaEY2MXUhWiR6cVMKelJCXzEw
dSpqb2ZjOygrdWkoQGp5SEpEUmg1MX50USpVeEopQztNemlGbzt1OT50b0txVi01bSV5STxDeWEm
KnllCnpBOTYxJEBjdVc5S2V8cnNgUT4/YF5DSjdnN2E7PE1PaylHZDV9K25LVz1ZRTUtZSR5SjdA
YWQrSHpyQ3grMFImTAp6Kyt5X2c/RllzTVp1fXQzdWFgWVpzRjBzYmIwTSE4b3lLanw7WDZjb3Iy
YW1sYitgel52NmxDej5qNDkle2BYTk8KenVHcEkwRnNVI05eUSllZFZnZjEzZCN1WChTNmZ7fUpj
Z1EjKX11dms9ZG89VWZyVF5Bbnl4UWN1PUlRWW40KWZkCnpobjBtS1UmelZ2OXJGbXpuKXYmeyl0
RjlfXnFmNmtxd350V3UrMTRebDIoIVNDPzJaISU7bn4rOXBjczcxP1lXdwp6WWIqYkFIWGd7TGRX
aCNgZFAwYnBvWlJGbE5hRDVJZk4xVkk2ZjVWSFIzSV8qVTB0bF4+RGEhZ0VKPGZKUCVWOUUKek42
ME5ucl9yRll0UiFka204NkpJO05xWUxqfDNkZm1+Ymk0V3dWZztYLTgxNDQtX31WdiFiYjckezR2
PT1sKVBNCnp1fW42aXlkTF9USnB+WWRKNXB4PnxJaCEzPktvdW09I2AqPUsraC1tdiNkZzFCaGow
ditfIUNKcVBiZ2Z0Z09Sewp6T3leRjA3fTRrOUs5MTRfYCtWaFA+PSkkam9wZSZocU5NV3E8OC04
WHV9ZlUmJn4rOTV2TTNhRXhWTl9oY31ANlAKejU2Km4zKChvSk0maz4pVmgpbHZHVnROdGVhbE9Z
Q0hnZ0lKZE5la0Mqam93azY/STF+TkB8P3Y3VWNCdEF7IylVCnpBQXdWMEs2TTdZdFZFUzFBS1Rs
b0p6aGZMPC1xOGBtYU9ifipWSzdlYDhgcTBtSUJWIT5jI25lYXolSHAoMnJGNwp6Mj9gamNCJn5t
aTIxQ15zazlTSCg4eEpAKXZkTGk3Sm08LSgjNm1fYiM9WlYoZlJDczwjJjwzRE5RO2dfPzspbWMK
emp4QEBJKy03X3xzVEx6NF9FXl44ZDt5WiVGO1I+PDNXc05FU1pYRXktJlk0eHVkbWA9bVNlZCZg
cTcoP1ItTyQ7CnohdDhjT2JyJi05K3lGdkVzdkBsO3E2N2J7NElAZFdXVzY+bSUzIT02e1V+PSNo
bVo0ZzQ5Y1gxKH1RYCooc3R2cgp6NGFVXkw7aFJ9OVMpVnsqYSkzZlUxQllsWCM+IzFCVXopVCVK
c1lNfT1Gd25FJUdtN3lvdHR9cDBEQHdOMzZfY2YKemBTKHc8e2tuaCZZMjJRMnRFTHA+M0U9YGs+
YyRWMj11JClwPDltbjQ9ZngjJGlCKG5YIXBrQ3U9WkFUUGxgKyFkCno+VzF0Sns5YHsrZGkkfHdI
akx3RjNLJEVGRHooYVZoP3JBfG1AIz1vampVWDNlK0M3Pyt9fm5wUk8qeH1hR0NvRQp6RHR6KlpN
TzA+QHF0LTUpRTdCQz5SeFkpb0NCajJmeGooWXJWTGJsOGthc0JwdSEre1pfYC19YU82UGojbXhM
XmkKekVROShUbVZ3TSZiVHBOSHVpMUszRm1RPmhCQ1FMSSY7cENiPExrI1FiUGFwd21pfTktJGVA
eTJnU249fSRTVGpeCnpTR0E1Y1hXM2BHUGFwSEUyPFh2QVowYkROXjtIeXhsJnBBJlMlWi1VNDtW
anVUREA2JFgrRnNUQktMNy1vQTZmUQp6Z0Y0MUFsVy1YcDE8enNLQjwoSH5xSXRqYHtXaGJ8Y1Qw
PVE+Xj1GZnNHSElHKmgleDAodkVDJWVqaGNicnE/SHEKejc7PVY+Y1hadDVCZyp5YXU2PChkRjBB
dyRDRyplQ24mSUV6KDhiJTVSWWUtejVBRiNVbns1fn0hPTlKNCRnQipsCnopQTl7c1RJKnlkYTdE
dFIkdkRlI28yRH1+TlR1PTJxS2g+Y3IpSzk9KXg4REs0a2l5NF9lUG9LJUYqWms/JFNvZAp6bzdX
SDhYM0h9JF5UOWhLQGBPPCR5T01jVm58NnQjQzZTT2diREcyZERReXl7cFlWRVE+S0BCV2w0ZU5g
Pz0lYEAKek4/VFlPSyhOVWt8MT5FWTZ7VGp9Y097MFZoaSEhdFg/O2xnIXpSfmU9LXozeV45fHZB
PHEwPEt7PjtxeW94TzJrCnpeamAlK08mKl9aOz1+QG9HNyZscSV1ZUY+ODJKMmZ2akg1MWwpdjQ4
dyYobEozT0YoWUIqcjQtVjZhd1kjdnxnJAp6NFE5UjR3P1M7JTgyT092aCgyT1R4K2spZz42SH55
d09jUj4yNHlzTE9rI0tEIT9ZWXJqRnZ7fUxoMWE4aHF1Uk4KeiFtUWQzMFl+ZjQpTkVKJkFANH5C
LU85ZEx2Q0hBdns8aXgrekxWX1ZSLVZ6Sns/SzJzSHhadklRQ1RhUkRVIXM8CnpLaUtlZ3k7V1RG
MDItPjctLWA/ZD1KTjdQbHRmJlNCUlgoZCRQSSE4XjFSbnxgNiRRQFJGKCtgTEYoaz5WKHxTZgp6
b1k0Zyt5NFVvKTtEbTQtcyQySiMhak5lYW9QNTNWJWBEM351RikzMXZuYiFRREFWMnlPUCF5a15B
VX09MT59WmQKenEob209JXB8JUYxNSRGJmVSNCMrb1VET0ckTytNWmk3UTdrTTF3YlJpeD90JFh8
UHdyJjBTbXk5flcoVkJRIz07Cnp3Rnp1X15TUGAtZW9oaDkmbWJBYS1qWG98aGxncXNrKztNQWwx
UnlWNmQ4SFdLTiNqUnUjX1dXTyt+NVNGMkt7aAp6KiZuVW1QOWApT2V3OVlAYV5PZ0FCYlU2eHBx
ZUFXeDtAKSRUZ2xsREd0OU5QKFZ6Jlk7ZWAyNERPPm1fVmRCWmsKej51aWxBZjwmPHBqP14tVm5s
I2koUldYbEdYfFRgS19PbyhFQ3QqX1EhVT4rKi1vcFooJWtGLTxMRytBWlhwbk14CnpKRXFUX3s9
cnBqeHlpXyRPfEFsRTxsb3tGVnhOOFM8eHgqPHZZV2EhIT4xdmVnYDMxbV8wTUhycmItVjlQI01e
WAp6dytAQ0c8flpSUHErM2kxM3khVCtlIyNAanszWSM0YS0rbX1reXxaUHcxa0tsUnBKNzRhfDFD
aUlgOzN7QTFtRFIKejNgIW1zPCZQJkZpXnxDaGdEQ0ZBaGY/eyl5UiRfYSY3NCZEJEVJPmRjNUZq
JC0zPUtyY3grYDZeMHtfSHE2TEJyCnohdig7RlZDdGk0eSRJPzh6d0ZkKDR7aSNkR3RjKFotbCNt
Q2xFPzFDZjROSzJLLVMkNUBjWmY9RWE8S08/YlVJbQp6RT9uP2gzZWdFJj9XP0plMU9hYX1XaTN+
SDFDOUpvRXxAQGomSkd7QXc2RD14e20zJFZ4RnhyJnlFNF9qQUQjVU4KeiR8O2VWQjx8dG9SM3tU
az1oOVFoWnhwUXNLPStGc3tzJjcjSFM9MS1SKz9hZm88PVl0Ml9GTG4mMlI/VEthRmxgCnpGdGVM
PzMmU2tLSHV8fm1qPk1fcEBnbWh8O0g5YzlDfShkLTE5K0BvN1UkSDlmaipsISR3TEoxZTtuV1RH
PXVsUgp6cWdWTThpXm1xdiUrUkI+IVc8cTclNSZCeU4/SG1sNFBfdXJubmdRfDNZLUN4cXdzTjsk
Q0MwbE5WYjQwPGRiUlMKejhITHFqVl9TYChIP0ZPIUU+SntiPHNMbSgmbHs8MD9HODRiUXBTKXpq
OXtVNW48N2VDS3A/cjAjRk8raHZiJllhCnpybTdrMDYoWipWeXo9TEk5M2Q5fT1MRnFyaChLcUEl
TjRCaGkyemxjTGAwPnctNlNGN084OSU9eVZMOTNrQyV2bgp6PjcwPzBVZ3U2Qk5QS310e3sqKS0l
ViVWcy1NJExiPj5PJCtWS31KWVhDZmc2JCNvKEpIeGt0eUBvMSpMMWIxODEKemVOQWd7RF8rfnQx
I0tONk5NNm5kMGJNUTBLeU9EWCFtbElEdnE+V3pyTjZrPzcjQUc9UlRoYVEtbjBaVW5Nb2pTCnp2
Y089ZmFBV2RHTCRyIXxNUmFtVVl9VEtGOUBZQSlQYV84fFNrQUpfKSsrU0JYb2ZGaVJJelVJVXFE
aXpOQFlYKAp6eFNLNXFSbFlWWjJEOzl0ZFRZMWM7SGVBQVJnUmExJVV3aURBRk0/UlJPfXVgeGRE
QT83WFBqN14yYWBiRWBxa2EKenNPYDc3LXJ8RWw2QTl5QVliTElTOV5TSUxSeGJedTMrPlEmIzgp
TCROYSZtZnswTDRHPTVWYEJPWW1GKVp8Qn5xCnpuKzt0UXdDTlhFMUQrfTBeJiQ2ajMrX3YjQ0pM
Jm9TMEI1KzZNOSp8c1QkSWM9R2NHVmMpMyU1Smh+eGV2YnhUQAp6RVFIfGFmdDhKaGdjWUU0LWU8
R2laJUpOK09+UjFUMmhFYE9eRyFJT1kma2dsdSN8TGU/YGIwPHhwZXUkQTVyeEYKeiRjVXh2K3dU
Y25jUlJySEhHOXhtdUtSOVBieH1SVEIkTk1wZy1EbFVtVkJSNm9XbilZMlRsK2p3JipDJS1sKWNt
Cno4MXlkVVk7I3Bhc0l9QXk9ZTwjPSpySDVFKUVhe1JhSkR7eShlKjRvTnF9VEt4Z1V7QF47OGxm
Wih7Yl9xPStWdwp6aEk3emFLd1BtTWhLeVJDPkE4VHArU3M0V3dCX3BJdT0mdTQqfDJmQDlFY3Vh
Vk5yTzUkLVA9Kmk2I0khZXNRYyQKenY3Tk4pY3F+YUQ5UT9pSV94KVphUl4hRGxENVIoOU1JMWdG
eCtCa1RnOFE8TnQ/fkVvX2heJigqUVh5PUpLYHY3Cno9eWF3JmV0b3BRYUJ0c0EtNig5KkRQfGs/
eHVUIztYbV5+XnJFOzVac3VNd201PHdkQGYyOzdOJUczYFFeZFJFUQp6Jn4mZC1IcldBd0lWJWp1
dmp7eWBOb24pYHdsXnBlQzwpUm9HP1VJZiU3dUUqNn1zV3MqPzthQFoxOX17TkskI2MKejBlOD8l
KUYhK0tvTW9jUz1TVnE/SGZxMGA1cUthSGxQYDlKa2Jkaj5aYWp6VCVLOyZsaU43VCFzP3otPGo9
UlhRCno0IzFTbSEtdnoxVklnRWN4VHgrN1RLI1Q9Y1h6SWc4O0Y/fDlMejZqTzB2ITc0Rk5rUFEj
JUNfek47anJmaTBWTAp6ZExuTj1hSDZhTz9uNSpxXjk4cG5zLUZEIUF7UzwjVypZdjV7aXh+ayNq
cDc9OVZ5QjVxY0Q3PDw3OHQ9dXNRUmQKemElYUBmMV9reElYUktEb0BvWjR5Q1dhWXF5X1VBKSp0
SW0wWH4hVn0+bzZmPipQbzktc08lYmsqa1ZsSkYhdXAzCnorTEE/QEJ0OE1ANCtiUGdISSM5ZCh4
QzYmen5GNUhWUG9AYWBjejxRMWZgdUd1Y0omUk8yeUVLUGJ2Q2V5I1ByKwp6eTNIeiFMXjJPPDsj
UzktYXtaRFQ5VmN2Rlk/emRwPnxIfnJsfWYwPj5jX3JHWntTXkcrcVA+ZUdid0JLPWpNN2QKenJM
dXtuPGw3P0BEdW1FRXVvO2BqUWl5ZT5YSHY5QWBLSmpMR19LP3ZES04+PW0wOHFOfEk0cSZRTX4j
TD9tJGttCnpfK3pzM2spZGtLeE9+RUBTP0FOc0xTazA/MzdKMExySTgmTll5RSt6TFVGbHRrWUAh
YTtqRGp4MFlUdyVDMX1Wagp6c2VvdWYkWSExVG9BYDt2QGpTT002T3FzcFpYckhKO0FXflEmI0hu
VWY4MVVFZHNiZE5LQzElWGEkUVMmcElTIWQKem81UHw0Zk43LU5iVH1PPkFAWUZSK1EtVjVTdyZT
c3NMVUVXITh5OVhGVl9FJTxEMW5PUDU1cGshejNwYmAmLVZfCnpsbWFYTyM7TW9CRkJHTl9LOWUo
UXcteEhzV0R+O1RBbjVXYDhhLXp+eXVWQ1cydmpgOyZXOy09NzJ3WHpLNzs0Xgp6VlZuVzlSQnRa
JFMySj4+UGtvNyMjZF82cjQ5bEB1MzIybklfXz08TVlGPGZVQk5eUWNrYlRBJjxzTjEyIWh5UkIK
emo2OXNAQ0lxVG5AdFhtd1dGPWY2UDA2NyZZWUxSQ2huJHNSP182TShIMnVsSyVZb3BDSGYxc1M1
U3VaQClIUGRBCnp5JDw/KCszUUZLVEM+Pn1IPUBJclhlfUNzWkIlSl87YEBKcHtVSjVMc1ktRHhV
T2R6PypCRmg9XyU0QzloQ3NrdQp6cVgmR1JydUtIKT1lR1R1b0gtbEtTZWpkK0Q+eStVQy1kUDJl
dT1UZEhzQTxDO0NQcTUyQlhFdj8qWXc+KTlmUH4Kems2WEpEPCErb3BUQENNOHRRPEc7Q15za2Ng
UHUwJXM9JU5NRT5TKy0/JGxnODEpfFctUyhVbmN7NGI8OWgmX3JQCnozbzV5bkxBPEw4SU4rYUZa
KClWUHNqTWJGY1NEdU1Mfn5Rb2tyWVpeaUY9O2l8MUg9IUxySUpgbVR1V0JoTk5KKgp6VjgjfWto
eDY4ZSYxTUhjM0QoU2JzMW5idDtOTk13aHtic3klb200VDlWd3VNT29jJklCZEpSPFQtZnd4cnhP
c1QKel56TU82MzZ7UTMzNkBMKWNVRFVybUdeaUYpJipIOGszJUtvKShVcHYoSEMzYHt7KFVEYFIh
Vz5mPkwrXjRBU3pYCno+dmhqNih2PnlyKi1SK04hUW5zV1U8e1JJVWJfelgmN3Z2WkdQNEk4JT99
SnQrYGtGSURJVU1rbkFCYnB2RnExbwp6UyFrPVhLIX1MOXZJU0E0eCp1e2poVFVjMGNLem99S2Jk
NzBvXlBqPVZMQSVJVmRGTXxQRWJtNGtMeHE0c1VXPUEKelA7fT8lPzdmUyYhQm9EYi0/RGBTR3NZ
U20tK2FxbzFFWFJqP1MkNj5LZSs4Qj5AWF5Mc3ViPlgxZjxVa3dmM1MqCnpFTTF7dkopRl4hSnw9
QUZOYWNxUTtEfiUkPFBEMkBUbXYmRGpOTjRJd2VCJVlYQXtyJUQ5QlU1REgkR3QwdzU/Qgp6cX4t
PWtZfVd2M3REVz5mVCFvbUZtUjE0ez8tYVR4ZWlQNUp0QUU9KnlPYiFET2ZMayh3JlUmdFFofCtj
TGEtWmEKek8/dykmQSl5Wk9sTzElLUZhJnU/I3JSKSotPndxe1lkU0o1QE1EVm9OTTdFdTN3YVdF
YlZWQWM0OVZ7K0l9UHY7CnokWjhydz18aEViYTR3VTx6ZlBXIWk3bEo9KTlffjljTCQ/aVkwYk0z
c2NvSyk/cnBIK1F+bnxYMmw0ZExjIXZQWgp6NShkMmhlMnUxKm9mWTkwdnp+LV9SU0FxTTJMN1hB
K3JJZzBQVlkwbkFXQ0VkZGkyfDkxfGdAI2hXPipNVHR1Xl4KelZuPDdNIX1lZj1DNFdEYy1OaCsy
N2clNHMlU15HQUM0RDl3YGBPI2BpKiZMdUd2Z2E/YmJDSyZQKkhBfXZ+TXA7CnpDd2tDPjF7N1FN
akBEfXwoeklQTSEyNSlCQSVyYz4+USRXRVVxNT9gMnYqKnw4QCljdTVePzdHTGR3dHZGezZFQQp6
MEJkc1VtQWdLaVNOXjgjZSU+fHhSSCZoTXZoUmE+KzBFTWwhPCFNOUNFPzc0Iy1zRW9ROU1tUzlz
SEIqcy1afTwKenxNTEtoYm4tWCE+dn49X3F1RlpNdnY7ZEpkVk1yKU0pc18ocS1jSjAxPHpwS1Il
aWRsZDZic3V0c1kyclFofjVnCnoqV0gzbDJHWEFvbWl3MVYobnZuYnN1VkUmKUU/aTdDb2MzPSNz
PzJ3d15MbzZyfjJVOVQjb1IyYzM/NkJuSFQ+ZAp6PTdBVVdRfSROYHQxMSYpPm52TCN5IXs7VHZe
S0QhVD1odU4+MjJSRyhrPH1TOTZ5XzRzWDc0K245QW5lPFFISXQKemAjNk9MWSp2e2l3SUpuNTFe
NWIlPG04ZXBKQUVLNVBRTzQmcDFOR0UmRlN9amNHUmRwI1NZPl5jcDh6XlZ+UHE+Cnp2YWkoQWQz
LUI+PC1GJHEhWV94dD1WKWRyeH1fYkdvI0FePlZoREpgbis7NVZmWTE4MzlAQWp5NEg7MntvdWFa
egp6K0UxVU1CcHxpQ1dPKHgldzlJX3UtNzRrLVBzOFRAIzlMfG0tNjl4SlFARXx9MXdhaiZhVipE
PTdAfGNIQlBYaH0KejVMS1c3ISVmI0Mwd05idHFIMjlwYzJXRFFZUis+NWZoc1N+O0wycCZkZFpg
YjE4a2gwPjJARyYjeXBeMmRFeXB8CnpKU2pEI2t4b2NRZjl+bUhOSmgrKDJ+KHEkc24yOWtKbEEq
MmFycyNpZmFHYXRRNDdEQGE8cyFNT3JjNGhoVjErZAp6I2dgc2tmWng0NWxXZkw9VXxLT0I7Q3J2
SzElU0ErIyZRJXl7QU5IU3lHO35yRkFqVURxUjM7NHJ8SkwqIzxtfmQKekhpOGtUSnAjMnFsND9x
PTJfWVVnNnN6OSlWQ01kRVQyK3lWSXg0aW8kYTgmRVA9YDlnUTMrU3U2bVF4RF5GbmBKCnp2cGtU
JFpEWHl0SH1oVnxLe3JOOGB9UVVoOyE+WGp0bVplUHt1THZZVkFwLTk/azhIdllhcWB7cXE+Qno5
ZT98WAp6Ui1aMzJNbjVEKiRKZSM5MDtaeD0wKEMxXjxpaHlTbzFmNDNIOUNIdGBxaXk0b3N4ND5r
Xm51VUstWVEpdnw8IWYKeko5Y2JQaiErVWAhdHdkbEZVVzI/fEFRcW1nKn4qQmc4bXo3I2wtbSFt
ODleNj0hIXVJPzdeaExCeUhedkpIPi1DCnpFK1dXVjJfcUA5TkhYK0BOQ3x2XikwUHhXME5BY1cz
SEQpfVl1NnB2VyRUZTBeY2MkeWsrSXgpaWQoT1ZkbkFwVQp6UkBPdzhXKnpZYCF8WEplXnh6QG4x
N31EZz9ic2I3Y1NtUzZkRmBxYUYrbExxTEskMG9SVjxDQ2M4SyUya3t4eFIKek0zQig8dlU9dDYw
MWBQQSUzKS1SaiE8aS1edz0oYTJCKmVHYD1BXktQeyQ2cCowWTxMVWQ3JFFQNXNFPjZqQTZDCnpv
eER2VFc3KCk2cFE9YTlPUVFaQEU/QzlqJX1XQSVfSiFiM2M5P2xRITRjKlhEY0o5eHU3eTcxcmQ4
MDRqJmlLeQp6bSlfM1BkXlJXYys+Qi1DcGZ7fWpELXx1aGklSiM3OzZIUjkoVnlYNlQtakw7eGBS
RVU3eUJeKXVwWEk9Vz5PPXAKemRLWmBjRTJYV0hLXlZzZjBkbG42di1vOT5pfl5yKVphNVNmbUgz
e2l5dzk5NTI2LUwqPktWNmp7azdhMU82JX02CnpvLXBMPGE3Q0YtPmF3I1dVfT5DKSFYXlc/aXpW
SUhCZTttSEtkaWNEbilLP3NXYjNlXjcpYkBDPlhHJmFhTTx2TAp6XyR2PDkkTWZfWTk+RDxzI2Fp
T3VkMm5pdUMlcTlqKitGOEdac3xtR158JndAaXZZP2M8YlFeMm5oaGlJWDVYQnoKejcpPEY3a2tX
bzh1Qyg/bihjYzNuXlFqbiVHWDFRNytoS0dvWD5HandUYzxfRkJ3RUN4Xmg8YklQNyF+K25JN2JJ
Cnojan5CdiYoaz5rU19OQVdmZE5STT5HR05AYkY1QkFreHprckFuMVpFPEtNNUNLJlZGfHdtNHZj
NitAQmRkb1p0bwp6aVhoPy05fDdUd3cleU9AOEIwdCp2TXckfnhPaks2TF5jPWN7M3UwTWFoeVg8
V2RUb08mZUh7ZSl4LXVZTFhxSjEKeihGfj5oKFI1S2FpV2g/WF85MUdtKFA5VHQ0T2o3IWd6c2Je
NCZAWG9BNm5IO1heWk9FRkdTOCtiI0c+cUR3P0leCnp3JDg7fEA+aWtmPHcwQGB7XnhzU0xRanN0
RyhjT2YhMShNZFZ9ZTBLZFNgNWpFPHt4diFHK28/Vy1FUzY0MUteZQp6SXojYV8wP3N4TVMwUVZt
PHRLdWo3JnMyYkFoalEkR0smUVZDSCFaJm1gMjlCTEF1U1Q0RSRmKGtITkZme1FYJEwKenhXOSNs
VyptY31mR05LaTVQKWQ1YWAwMmpefEU0JHBHZzY8SGdNMmMkJSQ0fil6YSVmTkRmQUhUQH1kO0dZ
JXgqCnpxIXp3JW5Yez0qP0lLOEcoMVZoQiNPJV8wR1g8TlMmNS15fmNWUzNjRE9kdCFJVGA9Kj97
QTtldX0oQi1LRkNTMgp6TWQrWWImU0ZATnlKZW0+a2VfR3I+YmcreHMmPT5iN0B3QnVhdyo1R1ZF
dD90NzxvXlk5NT5MfVUyZ0dUPWVEcVUKenZ6THNiMCZBa0t6MExwKHgmaVJXNFBPbF9kcVpUfWg4
K19CITleMnZAc2YpeTN0VFJMWEY7aH5RWHt5cE4wMHBWCnpYdyVqQTY+c18kNW51KWAoK2d+fEF5
d1FGbTRzQFdoamxsQWo/fnFCZnFLRj1TN0gzZyU4VnNIeHp+MSRgcX4pPgp6P2hvfkQhYDF9az82
ZzdgU3lBTnVsbnlkQFpOQDVYXks8TFIwS0BqSG83cEVFVGxZO1FKeyZmNDBJWEkwKXs9N2sKejMh
LTx0SztkVypjUUhOWDZZI24/WCoreUBUYDwtWEVuQi0lOWckeGBYKnh7K29ScUYrcHltbXk0ZFok
NmN2Vz92CnpmUWp+ekJhbTFMbFVhIXpzTTZTZDdacDQ3WSRyTEpoPnFMUyskQXZVI0JEJGk+cTNw
TShwfi1CYmZmSlg/cjUybAp6VDZLNTIjLXM+Q0t6ZFU9eikmbD1wdGghdGtudXJrbXtCSGc5MHA8
NXV8NTw9QDtkKkEhS2A4UldpSFQhdklKdi0KelBVUVhKMThBcHp2bil6S2BDQGxHTnsja2ZRKnlS
SWNLUkRQK1koWWlzVztzRE18YyRKLX1vQ0ZQaDxnaUJ0MGc0CnpGeH0wZWQ5WUJLSWVrKkkoQzI0
RHg4SH1qUlF7az0hZnJ8alBaMyFkO2hqTjVudzJDK1dkVzJsdnRSe2Y7R143egp6JmF6NTRLfndl
UFhaKjtyNyROYjZpTUV0JT4zQGY7eUxLZT8hUWFodVlOUERkX2Nzen1yNGN6MWdXajhWPzNucTwK
emlLbUFtS3gwd2AyMjRNayMjVFAkNHJqejdqNzw2dnJyansrdkJ6NFEyVDN9VlNyfUBldnByO0ZC
UmZmVGNnVHBlCnowTF9yaj1vSmdWaGA/Oz4zVjNScEJZdTV8JnI9NG0/P2dfaTB5dWk2Vnl3UWRa
eXM2dTFwaHN7WGImQVEhdm1NSwp6TCglQmBZeWIzY09DM2wtI2pkcDh7cXZOdS1FWkJrRGptZVMq
TD9uZkpaOD10UypBQko/RVNmNE9TJGh8PU5GeCsKekghZWN4RCVhSEw4UWUtRFc0OV9SV1pHT1J7
Ry0zZTA1UihYeyFEaThJe1pGSyVvTkQ9PVQ0fDJMKnxLR0V0fk1PCnpPY1YpIyk2TUVweDYkYnJa
cHFFX05JJUMmWF4lQndvJCRnKVNXMGU9Mm0xQU1aVjJzeGpNMDIhOGJjd3Fyej19Vwp6P0pSQ0c3
Pl9OU2MydDZAaStwKjY0Vlk2WGdFWjJVaFpvKzNMayE8N05wPn49byNBcEJBJntBS1ZUekhOZUxK
fDwKei07TGYoI3drM0RvOTJ6ZT1EOVdOKyN6dUw7VEhtTnAlWk07KH42ViZsd21iKFdnaTNYZHZo
KjkxK29CfU01Zzc8CnpOOV9Rbz9rd24/aHkmJXVYdF49WEd9KVczTF9RNyYjND5+WEZeSWxSMjxR
Nm1wSGs4TzF3Vm5mZHNPaCV3dDgyfQp6RXFZS3s5cVQwaTw3JitUX0FqY1VDaCpkeTlTejIhJV55
YGVpeTlPYktxST1zakVhKjxeSDJhQUYtLUo4I01DJEcKeiZnciZ2VjNebCo2PGsqSHR7OSRxS3s1
OytIMlBwTj9USm55e3VTZDM+Qy1ZO0tVIU1UR3NRdFRDMjx5fURiK2goCno3cU4tTHlkSVUhODZa
NmFUZWkmI3k2PzVySGpiOCMhQUNxfTMjM3tTdzhEcClBQmZBPGgqNlVuVUQ1QSM/aWt0dwp6VG9T
bkB4JVNfanhsdD0wdF8hI01FcFF+OUszKGF1I3hQUURGMzU7SDhDKWNLcTtWPUNfbGo+amhrbE92
UUBoV2EKellaezEyPSpkPTB3MURESSVqdiskJGMqYzUoSEtKNzdQa3w3JjdLcVN3e1JfQVkjbCh0
VE1UUXU0dU9ZP0xuI2E7CnplMEQ3dTc/c1A1c3YqZjVvNWxabl9tfExCdDI0MWNMZFF7T2l0JTJi
WX1YZSFpUSpXK3lsUyM4ciZoRjxDO0h6Nwp6SCsxKHUtbVRXfW5MaWZfNklhZmJjNlY7OHBNUjFi
aVJAPl5hUCMtd0dmNFMqbyNZZ0tNWVNLREFKblFSdG9venIKemohYSROQXk4dkEodXBAWHtmSSNA
JH5PUDM4PnYmQHdWdCQocllLT249fXdjSTdJQmojKnY1Yjc9UGh8WDt9NkhOCno0MVdPLT1vTWlN
dDUhU2ZqLUNeYWNBRjRZYysrVyhNVG5wRXZUd2BqbWNKSEt3PCg7TnpPczlmWUoqO2JZJURlMAp6
Yj9UZXFlQ242TG89Q2pKJH4pfX5Zaj1obnE9bWpIZURHb2FXLXI7e2g/fFB3aXIkNW5uNG9LR1Qj
UUFDWmVfJSYKekN8Z3dmcWhjLU8xeExFUCkpWCR5WlpaUVU0eGkpPjJGNyU/Rj0hPnNZc3lKXyt0
bWhALVcyTG5CViRyJkxfKFM7Cno8aiZCWnskM0gqUVZ3ZippOEh3SFBCOSpEK2IrTzNwOSRzNil+
IUomKy0kczdsVFE5O0tYIVlebSQtMVpkeSMxcQp6VDA/Sl5NMiROWG1UTmsrbFQ1Vy0tQH41fTQy
Jj9IcHxFR2chZHcqUXUrTj47anFDYnAkJkh9UWVAKUxCTHlPWHQKek14TUJMY0I4aEw8ajYyN09C
YmxVb0hGdDlDS1EobDRmTnVZTnZufUlEaURaMnVEK2N7SV8lYXs8KjIrYExhSnR1Cnp4LTxMPEh3
M29edmg+cHFSTHdHYDgye3FkUTlKSEQ+fVBsWHtTJVh8OERzZFBpUTl+KF9ydjs7SD5WSFdCOT19
bAp6Q2Y9bzxeLW5DWnVHcS1CUCk1aCt3fX00Uyl6bipUQX1fQWRJKXFOUVJ8S1Febmp8ZUZnYGY/
MlEzVCVncDwzQ2oKel9fT143S1EkfVlwTyVZKnskMCg8UE9ieWg0OzFrSyNrTj9ieXxMWVp0XyYy
KndWMFdhQjVKXjRIQ284dkxkQClzCno3NDI/UWEmUGdqRT9ZaFZTM09zODU8eXNBKUY9KFMoYjQ2
VT55KF5pe09KNSt2SkgtSmRuM09PNjliVlYxaSZHYgp6QU0jZzFVcC10JUxEIyk5akNBbWFeJTJB
VStrXkA5emV3YWhoUkhsOFQ5O2g0U1dad29xdGxza2RnJD9AYGIhdTIKelQwWGNNdEApej1seSM2
YHtBTHt4QFlDTj94OHdpfWp9I2I9bHo+KlRWKVp6XnNpU2ZFLVAjN25SQEhjQkxKfUFPCnpJP2Ix
Zip7MkN7P1FnaD13ZjN3XjxadUs8ZGslPjBzKHt0SkAlYHZhR2BsfmlxflVSWVlfRDxgVihFcURz
fG9MWgp6aCs2UyE9OWlSOFBkVTgrSDlzUDZWKmYhbHJyITtGPEc1NVhvWSE8dXNvLUFwYy1Wd0c7
ajl1PUJYWGlkMzsmJX0KeiZibjI1NH17c0ZhPSg5bGBZdWtzTkh9bmFuflVlO2ArfmQ5Y1JgIS1V
Qzc+fGhUN2x6NXJNcSk0dFBhQDJ4ViEhCnpKbmQhT21XbFl+PilZKUJBRjQxVk5nTUV8PGB2dmdu
YmRXSWoqPHg9MiNafWpuUy1KJmg0MT99VyFJISMhcTxBVQp6UDxib3VsKGFxYkFueXMwYyZKZ0R7
b1ZGa2MmSTY/QGxVPlooIWBUa1NmbHtCdWJiTkE9eDV1ZkhzMSZMRV5Cd3MKekc8SDFQcU9mUWNg
b04oMFYoSmU+WmFEd3BhKVoxbk1NQUdXcWFCbFIkPTIkaCF4eFdNSExhOTE0TGcmJG5yTWwlCnp1
RTtNLVlMVTN7VW95bThgdnQ7c1JQaDNycXV4Mk01TTkjckxlPW5VT05JTlBrJXkqTHtaKndAJSRs
UElHbTkmUgp6e1Y4T3BkfE1qY05EMDA2JFpCI0JPIWJrOFRCd0ZzcjQya1lMRXNrKTMhSTZgJHBm
cnw+aXkpaShIVGA7OTBjbnsKekJiTXYmOS1FXz5hKzZudTthXkpLXn40ank8OD5VYXR3JmJnTWg5
P3spak14ZEl5V2cjTHo7dk5ZcTRHITxTZFlCCnpDZ310Z1RVSS1hPCMyKkBlKHtEPW04eFQtemZD
VldJfDQ7KE84VHxAenY8UVJgVGNJQFdAZGZXTSFhMTBVbzNRTgp6TUU9MGA7bz1ueEd4eDNTaUxE
d2UyZ3g4TzVBcSl2YSRBIXJifEw4QDJyZm8kPiZUZjgjSC00XjR5PEUxbVNKOGkKek01ITBlIXNF
fUxPTHZFRUpKVnYyKGdlKXUhPCMkM3opbT0yUEtwZn16a2I/cTdkMUwoTkoqPX1MezkyZW92UUd0
CnpucjdUfU1KOStxbmFhdksrb2Z9ZzY2OU5tS3hBZ3U3YXdPKVJicVlUcz9ZWUUzKj1WRGkjfVQz
VTd+bWEjbDNRRwp6Oz41U04jOUVuYjxpbVlDMHRGM34lbFB8QGx2WTYzXyFDcEpKeEo4IWJKY2dL
UDMwUn11JHdAO0hFPFQ/cXEqV3cKeiZpWmgqKThuKml4U0VgVD9AO15xWE5DQzBNO19hNzZLclo2
aXlDfjdabE5iJUJSIyF0ckYyWiNxUzl0N1JBfHNOCno0XyNlT0U+Tl5SK3NTb2k5NyVwZFdIS0lW
YnN9dyVUWH5SdVlqdCkqQ01DSz5fSCg7NDQ/ZD5TSntWO29ge1EyNAp6I2I3N1ZgVVlFTUFQSUpI
PUg4JipfIWJCY2Y5dy1eQF5tR2Z7MSp3dld8c05RdElXa2g2SC0mcWd6UmE8ckNoQH0Kej9DTXZR
PjMpNXFONF5qOUpFQ3goOHNONSFaVD0pQGh2YzIpalotNFJvOVJpeWB4JS1pdnY2RnRVIXtKJSRq
KXBvCnpzbjJ8MUg1ekY3UFI9fWBtQ0RyO2d3b0dKT3sydD9FTUJ+OEE9eygwZ3NDPn09XjhOVXhA
eCpVLVo4S3lzenEkMwp6WWxPZjZ1WitoU3FxSmY/aVhOUzRgNS1KOXN1IXhyWVFXVTBAfXRofVZe
O2N3I2gxb0olI1lZbjhVKDVHXjEpSmcKeiU7UjtNQHJJdXxNMiRIVEd7MEpYczx5RipYMGI0TWl7
WjJCY2VtVW1DfDBpbFU5KXc7cShHZm8kfXg/NCpYOHNTCnpyMiZiP3l4LTxUVXV1JUY9Km9GSEY3
KkNkZkJkd0ZeVHBAKXplJnFFODFpYiZUQ3A7WDF9O2ZeTD1zZ2sme1VlQQp6aVg1Tyk5enZHQUVR
a3Zpe2ZGfUJUKml9Qk5eJn5DK0pzalBeTkwjMk5TPztPdGZFczMrODlqeXBJPX0/KnRaRmIKektD
VClyc1Qhe2lLWDt9PVpsUTdnNEQ1dXg/cUlkdmRDPjk9ZEsxPmd1SWYkZjRuZylQXmktbEZHKmBN
dVE9eH1rCnowV3Q5REZeYTtCO3E1ZU1TbFV1dDxyWiolSVFBI2JRSW5SM2g8QGd7X05ZYGVIN2FE
ckpWK1Emc0tpSjd1Mlo8Wgp6MWBPTD9MYEUydGgjT3FjTm13fFQkJSUrKm0tV1czV28zMFNTeyVH
dTsqVWleIWBCOURNR2h9bil2RSg8Xyk9dSoKemxzfGpOWnBgMWlERUpiSjZmZ0BwJV9MQHMmTyZY
dVU5cWRaTWhXSDtgSWtxRjMmY1NGZjFgSXxMdkIobHV4YHFsCnp3T2sqRmdeSztEdUxQRmtWfEd5
aFFhRGtaajV3NTVvS1UmIXdAWUp2YW05QlV5Wj0zZ2NFYFE0IUBOPyEtTF52Iwp6OzJLan4qU3tT
dUg7N0RwfEl2WnF4ME93eWx6OUBoIypiaHdrNCR0aWBvMDNucD40X2A9d35xSENwOEEmMnRCZlIK
enlmVFp+PW5tPEtVKD48VkNGbkpSe011cDdiP3MzJDE9SipCNzgheTZhcyMxPkFxMHxYTiYxZzs2
d0Q3ZEY0a1p1CnpsQUFrJDJuWUNuIXt5LUdzUExKT3AqdntkM0R4ckJXKSpAbnJKOy0jMn5TPWxM
MFhYJkdnKWI4V31hMEp5TlkhZwp6ZzJ4dWJ3S3lVQzEtNiFkKl42MVpKYUg9QVdzZXJnMDB3cl8k
PkRzfTd6aUp5QEAxQ21pQVJKJms3bGZCTV9NQXsKejE/P3hlP0xVdmE4dztPfWwhMXdjYntlUzhu
SiZKJWNaQUMlQng3ODx6eF4pPHR3ezQ/SXQzR2F4aVVpelJjJS1LCnomUC1ofF9QeVhuMWdJJTVx
bV8wRmVZMXh1cWIlfndxRyNIeFh+fTJeN2peYHRne3olSTE/P19CRDw7T0xVe1BoUgp6dWhmKH55
QDhxUmBod2tDXjgxZkUzRUA0fHt8Mi0/NkNrNVVKanY3NSM9P0RBR29VNn51OU5iJlJudyFMNXVC
fSkKemMkKjhNUnV2UEo9N24oe1BoUkVrcjFGPCRFeERlMWZsITstVHB4ZiMqdVlgdFRNVTRuamsy
WHYkKCpIKzN7bHdICnolISo+diE9YTF1ISolaCVwSTQqZEcoaDQoJGhvVWYoQ3NfN0xHS0Fzcks8
fXY7JjNUfHE0JTVOVWQ9SyNtZD94NAp6aGNETyhFblU0QVlxQEhlemN4QFheMFopVkp2eSVgQ09v
RV9GVlRkYmg7cXNaZUp2KWpIJEU9KkxkXmpDSF5icjUKejdCeSh7az1kOSVZTD9jRitMNXBIUVFA
NTh2b35rIUdOM1RHVHpiQCZxaT05VzwrK1hTVi1OOFMma04rK0FIZ0k+CnpVUz1fSlJVJFg4Njk8
X0pzQTg2aWtOdTItTj91SUgpbG4/ZT05dV9xLU4xbmR1WDdyWUxeNDBHVnVvMjZiMG4qKAp6PGlL
dTxHcXszI0h6fVckT00+RWo/fHhoRDFDcjNoZ3R2UjNJWFEjMSRSUkhrZzd0M15oMHNrRzhYTkBm
YDY+cCYKemNTdE1JTlpKT0VffWB6bUUmVEcmOTw1UntRYkchbihWVTBXSW5+TEZkSzZ6ajJjKWdK
ST89d3o+d2FCenpmJDNlCnpJYURjVUxAcSFmKVBAIz5PaVpZaVErfl5qdjhAWV5wQyopUiFeODxT
YzgjSUhhQHcpIT53c2R0eXpYUGdoJHF4cwp6XmR4WDltPn1VTjRNckJLMn09d1ctRlBJcFo0SVdl
NihVKkVuWkd+VW5wLWkwcXd5cjd0NnE/bCYxTGlKMylxIS0KejYwPT5DNTAwJkslMlIjbG5ZcWtw
RUw9bUM2RSojUT9RZXVWXk1HTXYlRUhXakUpbDJaOG1ROyNpUjRTYV5JbV8tCnpESThwITY0Wnsy
UnZ0NShsM3o3bTkkemIzIT5gWER2Snp4cDhBTEdgYFA0YERzWlVnbFVnbWN+d3RLI3NGajFUUQp6
d3dlLTJSZnQrNTVTRXdQcFhRZXdBY2smYTdnKkQ1NjtfQjA9Tmp8VEg1cDNCblFKbmVXOyU/YWRk
am42QDVgPGIKemt8aXw7JDFBYjRCJEpiZT4pcjkodkA4fnA0Uz1+NHBrTWJAWmsmalJRfjJ9RTc9
OXRGXjhVUGV0TSpxTXVmWj5rCnpeNDh9VGchKUF6X051ODllPmpJe0VWKnl0aVR5a2pHY2drc3JB
VFo0VippI3UlPD1FX3c1ZWZkVEIhXiNWJiReNwp6Vk9tYTsoeldUOWh1Iyl8akBqbWZwRENFXmJW
QlcxSDNPe0ApcHF0amBGdz5sMjt1N0tqd0UyUT1QYktJT3NzX2MKekN2QXkxSktaaFBVMTMmQEE7
WlolIXsxMzdeXjMteEUqbGtEJUFRUkFzMiowTUM+Z1hmPk8oNU9MKDRfVDU8RX51CnpIPncxcXYy
JWImZ0Y1KERmcHVYK1NDQi1GOTFOMnVKUGlqZVppQ1YwJnkxTkF6TnMqJkIkeVhvVEh6Q3wzK2Q9
UAp6IVRCdTdmWiVXTUtUfVAwSXdFfnRRYDlxWmZnKD4yZGEyO3w+NiFHQ2cpaWM1ayoqUio5RXNO
WDhlPzk3RVVCUHIKendTd3dvKmY2c2dAOXJZJTlefF5jYGwtLVQ7UFRZejJzcFlGKXl7LSUkQHxn
QyQjNiN5UUdRdTdtVTliVlFnKE9gCnpick1OUjU/YCo8KiRpKkhYYmwhd209azc2MT0yRm8lQWpm
bWZjQGlnXipSKjdpRXFnNFYzfWwhYV9PYEchNk4mUgp6NT8jT0RjNTg0ajA0UU9iSjhpNjAtbl5n
VHo7RGYrS0VvQGExVEN6THZFdHNrYlRFMHk4MFJjSXQyeU48aXdmNkwKemp0SXdCNk0zb15YPndm
aFZAQ35ocmFIZUdxYSh9SFd0R142VjJ9eko2KHA3TSl7RVVzeUBVJH5mSEN8MnRqXjhlCnp7TnlM
Vz8pclVsSE9BQyRTOXhAdnstOG5oZ0Z5MHZFaWxiclRpMkNyYzI+O1VtX0FWfGl7ZWN6cnpLUi1n
RmV3NQp6KHc+N2ZMalhvYF9yWEpiZml9dERnNmsmNUUrJmxGYi1sTXEmUTcyO3VjciFHZzR2XmNf
Nkw8Nmh3VDM9JnBicjYKenlhcWhZcytxVlNxX0E7aERRTXxARTUxXkttYmpQcFBeUz9MdkF2KUQ3
K1VEa1g4TXc4MyZCZDExO21JLVZ5RkVMCnp7KkhFeistdWcwVUh+b1UzPHdYMEh9NEtjSylYUE97
Y01APUJ0YkA1PVVsbjdgPSRLNzwwblZCYD9kbG8mSVdUYwp6aXw0enZsJHlqe0oleFZUYHxCR2Q1
fTElSk5xdHQ1KXhOKEAqeXlOVm1+PWZGMVNONFdHRi1AT0FXfWlWKEZoYzsKelJuYHY9MWR5Q29H
eU1pRTZNYiZLRWxMZHA5bUtCbEhUYlBMcWhJQGM8KVc3NlBxYVImcklYK3NPajFOVlJxNng3Cnoj
cUxpQ3ZBM0tpVCt9eC0mQl52fT5jV1pVRUpjUWcrY3xKKGJGe3RJVWVKZDFvYVRsUVBiN3lReD0j
d2R6aG53SAp6Y04pbVArSm05UiRUaUFMYiQpWVk2az9aflp3dGtyQDgyKk5rJDc/IWwkcU4wWitT
WUc9alZTayVwVSttYk0oVS0KemJlYjkoVCRoaCp7OGdFKGdeJlgld0JhUmo0WGhSX2dsO0JtYSgo
YVJ7d31+biVaRC0wKHZwWCZVJm89e0E4d151CnpXalg3aGVqTGVWWmotdEJFV2Z8MCVQVDdgNkho
OTZMcClKYENROSFjYFBEP3U+TiVLLT5geGhQQnZMe01ZR0pZQwp6UG1kZlgrSGFPQGE+WGU4QGko
dT1hOVBiX0I/OSpYO14rJU9ZI3J9bE0zK0F8UHhBTzBWa2hsJlR+cTdwTDNRRyYKem1yKHRrN29N
QTVANm9yKHl8R2EpV3NhIUF2VHIhb2tnSmZCJT58eEUxenpxSms1QE5OPTxnSyo7JW8tN2AkP1J9
CnokYFc8bmM3d3RLVXNgIUBLdk9GWlNWRCE+TnMqPmtrdTJoQ1lpcXt3dzVYVFI7USE8cDwra2tJ
dHcqWnFPX14/aAp6Rzd8eUNGXjZDbHJ3TmtPQ2NFIzVidVE+S0tUS1N3UW9DWSkqQHk3YkN6YyU1
V24jJWwrPDhMY0Faem1OZGNxVkUKekNtOCErY3FnIVFBKFJDbyNXQGxAdERuOF96ZlY3eWwtKXwm
cHhMfTQ8NGQzK2xkQmVtRyVONXNga1dSaW11Xml2CnplLXNVKVM+QTtnRCo5Mj95blQlfG1NS3Q4
VUZCTnczdElHeThaSjIwP2hCPkgqbUt8fFN4WUE3MT8hSVJxWX1MLQp6NjFAdlkqWHYqUF80alZM
VCY4NFk5ZnZjI1ZEZEBjb3ZiPTFDI1VfX25+OWZ5OU4lNytZJUdDP2BKZk9RRWBWSUUKekk7SDZR
WXJ9aTEtT2okbHdxVDwmKEBxRlhvUTwkWGNzTkZJY1pJbWBULS0oMWQqP30jN0VZbH1FamhPV3gz
anVoCnppY1otKkE/V0c9PFQ2JVVMQEVePmVxJDVpRD5eRyN6e1dNMiFuU2h6b3h9ZnBFbGxmQGhn
Y3pfKiZXPEBKTSpjagp6WWQ9R2BEX3xzSEFtQXYpZF8jVjlDKjI/YEpaJkl+QFdENz4reVY0WlIk
akZ7MnlfMlRmJlRmK2N1Qkk+YEkkNTUKejszVXhOMVFjajluSW8xekA1Yz00OGsrcVo/akhNZWIx
PWx3d1FjU0V4LVpiPmAkPjM7K19oZFQ4Rm8kenlWOz8tCno8Mj43WSYzOGZmPD5oN0NLcD9pQCFB
Q1NLT3pffVdObDkxfnZgMj5tKzk+az9wO305anB3cW45antGPi0ySlUkTgp6UVhSMC1AdiF6SEBi
Pm0qNXNsKj8xMEhmMDZtK09PSzA0QVF0bXhRO2xZa3Q+TEZpKzUySndOKSstSU1+Z2pwb04Kem47
JXduSnw5MTwxMUFHT3ZrTSM1XzQ4XiRfWVFGNmxSLSp5TS19ZF5CXyNeO1JtTHdIZnpLNTBrZlB0
QGVFZCU7Cno9fUU7anFQayR6LXRMYjM0Mk8tVSUjR0s1WFlZJmtMYHstJWpaVUBoOVUqOVFmWCk3
N3U0JmgxRnh2VntBP1VxRgp6cUpSMmQ2aCQhdUZKYnE5VyhEWG4xb1pOcHRaVS1nbXE3USlpelVn
RjhrKEYwaHdJXnRMNyhyOVRuOSRLeT40TVMKeitsN1B2X0NqaEA0cHZ3NzltWFp6VyowITAjUjZ7
PWIzXjI5K2dGc3hHNDIhRkVaOz9RSSZjb01wbkBnP3A0TzA3CnpjUl93RV99XnIxdj0xMUZSRXsx
aSg4eUg3YyVNYEB2QS0tMWlDPWs3aXIkPCRMPUU1JCtKYzZ8aFl+ans4ZF5JIwp6dlhmY2otblNV
VXVpX3N9eXdeTkFJMXhAPmsreUJ3cmlsfnFLSn1KWWBSKUEmPmVyb3NmQjt7SDNId1VFP05uNFQK
endzN2V6Y1FxQyNLUi1Xdmh4c2Y+aT1wJHwyO29lPyt2bk58Jn1OQ3Q/R3pYLTgyciVyKDJARmpZ
U1o7dD9xbXBACnpXWVNmKHQoK0J1ZTtmJWFYO0M2enBvWCN2XiQ4WT1JQWlaNFltUyU4aDBjNUx1
SUxAMip4dW87ZztebmNVZXU3Ugp6YUYzNEhKPjVYdCorRXMlPmNZYXQqR2h1UWhRMjFFOCh4NzRn
WXNaWD9WSjYoQjs5T304UGhlZG0meH1NRSZIRi0KekNWPmkwTTU0Pj9FPnZxMGN9WFBnSkZ6UGdj
a0BqaFB1MnslWnI1MUNaTmRhKlM/KTFJS0JEOEg/aiFvZnQhLV9GCnorNVhwTTZrUyg/MD4pa2tZ
aEJPJUx8NXZjaWIwXlUtQmxuaCR1UXd7SkgmSXJfK2h2JiZmakd5YzBLaCY2ckhSUQp6NGZQYnl0
RWdCYHBQWFc3YjtFcEZXbzMrOSlRMWlDZG0pP21yLSFjaDRpSFB+Qz97TVlNREpfSkFOaDN2NHZL
VTAKem1nKyhePShPaEhlNyltaytvREYxWSQlMi1OSUt1WWNaejQhJlMtUjdSPmNoYz9DZ3h5PSs5
PFZxUG9+IWBOcXEtCnpjUEd6UihoSlNaNlpKdHkrKiFyPiYkOFVrMFZnNj17PHFVJTh5eVl7SVZf
KXdFSU1fe3gzV21OOzFIQypGNUVvUwp6R29zM3A2bkliQVIqcVFKKTtBSEJNU1dtdnpwSX5CZG1u
cyU+KUxvN04hd3tIdUZyV19PbWwrT3FPRyFwYWNkI1YKemVjZmVIWkBaaCUtVDMycSgmIU5PPEEp
a1k+Wm91ZWIoVEEwayZ6IyVoLSNXc15+a0lkdVdUbWZiJUM2JExuVFRkCnpgZ2RzKVZHJDd1e1pA
fnFJTWRoZGhLO0EwKVhyTyVBfXpidSgrWnJ4a1J8NG5fKlZlNUA2eTMoMS1PMmI7fHxeYQp6Pisk
O2ZNLUcrYFE4cWZ2JCZNVytMazI2SEBGWWt5ajBreXkteFNtPyhrblRaY3UyOHtyO0RTWEtGXz4o
R1cqb2UKejZJbCpoYXFyJGQ4N0w/V14rN2smPzAkRnI4VDVLcjRjWmc4UkFDeDxpYjEhcFErfnd3
K0Q3cyhFZmF4cjVQUWg9CnplMjMhd0BmZUJSPVdASFY2TE4heWgmV2xMR2d8SkA7SFE4dSpZNnRM
ZlFiX3A5X3wwelFyc3hjTXZFandSeVojJgp6WF49PTI4JFElcmt3MjRvO3M3blB3WThOekwha05+
c0tIXmY+IWRGQz9SMXxLeG9rZjYtI0wrZEJDemhoSH1lZFUKekdiTGFRSyMyQG56LWEkKzBEPkdt
SExaRUFsc1Q+VnNXWVhyMz8re2lTd21ZdGwqa207VCopNXZQTF5lZCFEIWh4Cno0VHcxYig8RXJa
VDlLXz50QCFYI0FuWmBNQzshZVM0TXM7NntPZF9KIV5ZaStRSTBQRW4rd1NLI1d+Yz0lS0M4NQp6
bn0lMEZGPjFzT3U4SE9nMns9WnEqTVhPa3RrbDUqcEZaRTYpT0I9cG5CJlZxbn0zWH1HaDNjcCNi
eT1oRSROVjkKejM0aTFwKT48am1lO3Y7dChIUTs4PDRRSX1PVUp4cHlQTEQwYlR+QV9EeT1+K1Rg
UzBXbyM4SlBaJk9CO1k0cmdvCnotWG53YTBLUTlMK3lhbXxFalp7e29FdjY/JHhVeTUlMFVWM2cj
UTFBPXZubUZjUmx7VSE0SyN3MkdDWSpmUmRiPQpLWT9aV0dAYyNrYmNgQlIkCgpsaXRlcmFsIDAK
SGNtVj9kMDAwMDEKCmRpZmYgLS1naXQgYS9hcHAvcmVzL2ljb25zL2hpY29sb3IvNTEyeDUxMi9h
cHBzL2VjbGlwc2UucG5nIGIvYXBwL3Jlcy9pY29ucy9oaWNvbG9yLzUxMng1MTIvYXBwcy9lY2xp
cHNlLnBuZwpuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
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
dCBhL2FwcC9yZXMvc3RlYW0vZWNsaXBzZS5wbmcgYi9hcHAvcmVzL3N0ZWFtL2VjbGlwc2UucG5n
Cm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAuLjliMzIyZTllMDEzY2ExY2E2ZTQ5ZDA3NTY4Y2FmZGU1OTE3Y2QyYTgKR0lU
IGJpbmFyeSBwYXRjaApsaXRlcmFsIDExODQwCnpjbWVJWVhIPTh2N0I+N0tqKkpKOW5kMnk7bHlO
fGota1VVIWopUzJec25TdEkxZiZMdEFwfkBFYTdHMCpmVDFLSAp6M1BDYEsobjRyS1FJTWB3QXdY
MH1BfmxpI0ElckNGb2pLP0h7UWlGSFVHRitTdmE8NXplKWl0P0Y0dzs5XjRCPlIKemQlMXJjYFVl
Qy1hPEg/JXg8WmgyRShBJGNmND5WblMmdUpRMlZjOG0mVXp5dFhtNXcpQmg/bEM+QHMrJDc9UHdN
Cnp5aiUyQGM7djtuNUQxQXg+Vi11YEFjOE4oZ3k9PWJnJSskPkFBK0V0QT10MH5hPShzV28oe2Q/
aHMzWnl2IztTaQp6ZVBFVTB6V3VINWwhR2hvVFRLJmp3Xng0bnAwfSVVTzh2bnAqeDlJbT5JTUQk
YFBBOEcja1hEXkpvV08zJHpofiMKek8/cVlpUUUmZ3xwX09wS3o/NEdHZnh7N0ErSmR2Uypne3Il
OFF6anh1ekdMM2lgNkkyJmQ8LSttViUlZzhxYks2CnooIWopK20+PEFncHIxfCE/U1A8ai17MEh+
S19gI3dKTyY+OUB4TVIqQTlUcT1nJClHVkh7WWs+Oz8hRkwzJWgjdAp6Pn1kPzxtYG09MXQpe0oh
a3VmNVBndUxEPzV7Y3JNenErdDhzXmZXVW14Rj5ILSp1QmR4eFUqOCs2emxoUHRQKygKemNyeUYp
YjJfZEo0KlpeMTgrVXppdHVLRXBBMTNEPF9OPllvUSt+e30pWVRQK2I8bCFvPHY4cnBWeXh4ZDhM
fjNUCnpaUjRDditfUlRSdyQ1ITZpTE9PUDNfZmI4bml5JkBFb2l2Yi0hb2NTKUIzY3dyfDFCKms/
SEVAaEE1cHA0WWp3Swp6bTQ/Sis8V21qY1ItIWp9KVk3VkQrISgmaiVxK3dxQF5uNjAjKk8/YGdI
YnJNXm1WRHt1NUxsaUMycmREPCo3bXMKejhtKSRpQEhJbXNPUkdyY0xlcmRoK3ZKaihtJkhmMjNO
JVY3czdwUT8mTXUye2tOVXowaDRhSXsjI1F5RWE/Ym5XCnpYZzFWLTk5M0FRbTZgOzd2OytBc1F8
ZWx0e1QraEU8aWslYHY1SnplV2FKPyhGaWxMJGlrdE5yeC1fR2FIZUMkdQp6TD53I01nQXo4fUcq
eT4/UygkN3pqY0JyUjlafkp2P2QrX21nJlVeUmlgMl8/TUAjJVA2Jmd+WmdWN1NQSWtRYXQKemNN
JTdRYUkhOUYqTmozI0U5WUJgSiZ7dmI0eldyekkmNSVxcWwkN3hjI0Y+YGojM2kybFM+RGNvXlFO
XlYlfiNWCnpSUWgoeis/LVZ0Pll0NlhuWkBIey1uNUxZJVUhdURCeGE5Q19xLW9sX05HMm5eUmxW
NF9Od3dQcSluUHh7UWY7OAp6X19LWklyeUJgOUUjTDlFM04wb0kqN01KdURrQSNjY2xJa0wjYkEw
MFhzIy1VZFB3R1cqPCF5fnVhdnJ8a1hfbzAKekBKdn1xIy17UyFqK2t+IUAjWXk2dVQrMDw7K19r
dkpvVj8oK0dFNyVeKE9adUwyWW8lJnZiODBwelY0KVIpOzwxCnp4cU0jZyh9UTBPcSU0QmB1Sl4o
Q3BSQHpBJlM+QnQjSzhtOFI9Z2gtZG5+I3M5X3JnQDZENG9tcTtYWXk5fSRCZQp6UXp4SjlYZz5s
QStGYElsemBXVGB7K2JqMFBPKiZlWGwqPy1YdWVnXnJ9PkRjKk5+MExnVmczIW1AU0dQYFRDencK
emclY1BaUmQ0MzwmT1R1NDRyPXd4cGk4LUhfal5wR1FEZEM1a3g4fllIWmFtQmkjTjQjUFkwbzsx
S3BTMXZGfUR+Cno4UFVEUnN4YUFRTXp9RDM8OyhyQ0p5akRBVVpIVmlRX2JBKDhDeHNXK2Q9fWhv
Mj00OD5kRCN4V3ZVeFU5clZmdwp6JiYkX3U2VCN5YXloRCVMVT0kbEtoVn1TUHh8Tz5kb3pyOHZA
dW13aVhBcD1jOEpQK2pFJEFCPk0wTkkqWDE4azUKek0pdE9GUUc3aHp4R2VQUStzUXBNV0Z5NXg0
eUNUJHI+NjwxVU9Cc05YV3VhfHZeeH5FNlBRJnxVe2g9dip0a31ZCnorQihCSnN1fVckWHlyQ2pY
OXt5SWNqc2chWG1pV1Z7aih5NG17SH1RcG8yTj5KMERqUm5sMWpCeWsyQTF6bX1FWgp6aChlJXU7
aWpAMj1tVGAwejFlci1ffHhQJEg2JVNkdUdFelFsZSVIXlY9bTwwUGpnOSV2KSRiNGJ4cXhUekdz
SDIKemItTEc2Z0FzP2xkPlpaKmtoKDA3QFRIfGAhRk5PVmYlcVY1V28zRXlvZyZkdiVQTkU5NnQq
ejhNfjduMHhNT3hxCnpVYldQM2wlaC04OU9jIzJNNClwdHpKb1Q+QnJrK2xsTGkmXmxmdnx4KWBx
ZWRCOCsyWmhxN3I2QD9ESWZoSUdeQAp6c2stTTtUY0g7R0FKQ0hTJkU0JU8jLSt1RV55V0V2TH0j
dE9pJm9CQkFVWjs4eTBzJmd6bkM3dSo7Kjg3NlFxUzYKemcrRD5wdCR7Wk1afktVVVE1Sl5BODZ+
b1ZqeTw7Jjgma3J4U318YnN0QD5XaCp4P2p4VFhDXk93c2lwVEJxbk8oCnpIZ28kTWNBUy1hWl9z
JjVVPndzaU05X1h+dEF3TFlIdlo8ZnF5MWtlZ0xiQHRPUl4/czVSO0gkbkhwPGtAITtrbgp6dTRL
czBLbmRxS1h+dFkxN29MPDFkQE5+K0cyaW4yPW52UWQrWj1yU0RAJDBVXlJCM3QrNEhmS0NrUzhC
Q29lakQKenkjMXVhM3dNN3Vrb3VeeDVFMEl5Z3hjRGI1enNDVWAhcF90RnNqcik5dDNJQ3ZWYC14
ZihTKFpKQCg1Xy1xNk5oCnpWcn5mbkZAeWlFeWVfKTh5PUpzTEszPVhYZyM5VGYwSUA3emJIKDAx
cikoIzU3Yk17RURjPyp4PDdqSzxoPGVUKgp6Sj5PZEh0Mj90YnVIfCNtajtSRXpOcHB8cmxUYzdt
JXZ+TW1rMGozaDR2dUtKRDZnY1pRZDR6NWp2bTtvUXs8bCoKekk/OXhXSGs1RGZLNiZ2OXtPU1Bp
ME0lZ0t2fjs/WUZ9YWVsJkdyPkZDclImczFsYl8xZWtmSH13R3pEVXlPI2ZnCnopfkl3RyQ3UnlE
KW9FTFQzTnk4KmhlZjx5UC1kMjdSSjVoMiZvNiVTXj5rK2wpLVEkRVBwT1lRb2tJLVBhVlFPawp6
TCt2K1JmXzhrbnQhITZuJUM9ZGFTTDxaLTNAcjE8MXlQa2xAbGQtNnB1K1cyO1NRekFZdXlTWiNs
JUZHRyp0bXQKenVBYlVEPVFYYzw9PXNwP3xCamk3VW47am1jWWR+RkZDRWgoYDNPIz9HXktjV1Rt
ZHVEMlByZ2JfQjhnQWglO0JsCnpabUJKM1R2R1p2aHtwTihtZC07cmd3ODtIcWowPyg/JnheQkJX
a3Q9PnRMSjAqN2M/amQlV0UoYndkYXM9MzY3KQp6SWBYI3clKmN9O1hLTyVMRERxOVEtPjxPfitB
eDwkPTZJRF50STZ2eGEmc0c8amBCYStrVl8oaDkqMStLQVZDcXgKemJRMG1pMmBkR2FoTSY3dnpg
SW9RSyVaREkkLTVRKjAlPGlhVEY1UmQmN1NURyE2cnZkNDZRWmw/MXElJEtufGxCCnpieiF3fUR8
byhJQ2tYTSR3aW55dihaZkdMJmtnfkYwVnZ3OygyUnEpYWAoOD0pNGpENlFuTihhczJZSHRURDQ7
Pwp6MUZ8ZllSXztMNW1tMklgdWVOZ1EmS3N2Q0NFNkUmNz1leyprS1I5c2xhSEBzNXBAP1VFcXtU
fG9kRzNhU2d4REgKenNyVzxWWjwoQkZRPVl1dDkhTXoobT1QVEo+WV47LSZGeVlyMjZwPlhGPU88
UUpha1ktQCgtdG0tPDVkP2htNUE+CnozI0AzQnJZZXhaLXRWMkRqak5+cEY/IWI1VWl9JUg9TWRN
UW1nQUFYN2RvZ2ZuTnN7S0pVXl91aWpFMzNrTSlLZgp6d1dCcFFgT0hjfHYkdWhEblQ2PWheSCRP
S2Y1NmNNVEw0OyE7cHNCYXtlOGY9XlB8fWdtZEs2bUE3X25uPTltbyQKemlxRXF2RXN5PE0qPjRG
OEJpP3gqLWtWKFZKQy12dykkbWYxbjZuYW1hbGFTWnVXWUw0MjgjLSNvb2tobngpRk9DCnpWMUk9
TXl2UjcqP0BgdGkxJXI/VHA7SCQ0XkdeclpLc2V6KUYxeCYqdXteSklAWSYxKnNKLXpCYU9zRWhT
O1VoMQp6Ozs9VzNQTmk3JWkzVSZQU3R3YDxed2F4U0tWJk9EMSVBPENQWDxVYlclWEJ9Oz5vQDtD
c2s4RD9IcUAoTTVKZnoKekRKYU1xcHl+YXV4NFd3KFcxb1dgP0gjfXlZQTAkPzQhXzsmYjtxdV5U
MilCQUh2cWklbitmdkUtMSU5Zl4yPzVhCnooSyRxRXNQaXh8RnY+YWxzc2tjJmBkT0BaeGpJY3x0
SFJfNldIMUFVQ3F9cG9tKUxaTUBQYm1lZFFXQGd8THx7Owp6Jl4kVyUoSWd6V1dHJCFuWn0oPmNo
MFVmX1pIQz9OS3ZheEFlTFZfJmB5VGpxSSlDIUwxc0RodUtXTl94clB6YXYKel5pNE9kfDJxeWo0
bzNrR09HcERZOUZeRSRJeD49UjJ4bW9KNGMhVENEdkx2KV9OWS1AeFJEUH5HZzhgY3E1fWpICnoz
bXBJSikzK2d8U2Q7TmxPWG1hNyFEOWdBc3REc2BCfT1gbTYwYDJQJHReNz41TGJKTj9naUNEaGZN
WDUoXm4mfQp6UE9Adms+aXtaKCRYaENIb3M2cXNxVjdmQFZ2emo0VHhlO207cFBtT0MwNk4hTnRq
cTN5emVNXktZV3BtKiZPP08KekxlYTExZ3RtdHYxNngyYjZEdSl+XzBlfkdPUilUWE8wUlo4aVR7
KkhOU2ojITU9eWFuZ1JwU1pQQjVuPGt+ITZ7CnpeTjB+S0tfaVYkKmtCRDhTWElRdTlncmtpbTtC
Kmcqb1BxRDkxY1krIz84SFg2bi1DUUgzbkxMdFhpMHs0ZnBkQAp6NXdZQGdqVnB+KkElaXdhK35T
ZTt3MUxBPC0tS1pDbVM9JDdWQ2VaTitHdHhCZkNOaU5ASVdIPU9YMHhBbEJTK14KemBQe1NKeHxV
RE1ESk0/PEN0Wks3WV9oN1VyeV5OfEFIVCRufDJUamtEaENqYnszbU9sSUFERnJrdSQtNU02N2s/
CnpgaXFLdyZ+KVZgM1p8UFBoZ0FTeCZFZG9EZ3Y5d3tNd3RMcztGM0lGb0UmMnQ+YmFHZHlkO3tq
RVMpelZkbHRDWAp6K2UxTms7TGlJQ1dkRiNDQS1ZdyNBTTxtbkV0MHZ0QWxHQVNwNTBTdXpUP3Zh
NVYzPEU2eFZKTnh0YlIyPVpWRmUKekZNc09gJnBsVn5FcD1sLTs+cilCekdGKjNIZitKNndCYEVQ
IV9oLW9uNSZuWkJaMnIma2ZmPFNFc0RrKkMpXlN+Cno/UE9GaGhQMV9QSlNeQWJTSXhYNGwzYzRk
eks0X2AyXk5mYXNxX3F6WlI+ITR3RFFJK0chPmt6b305UTwxMkBTRAp6SCtFa1lJNkBsfHU2RTJU
JUJRfW9hakplLVUmdE5SeigwMFJjcFYhWl5GWiV9X1dsNElWOTU4Tkg5Y1JYejNnZ3kKej95aEJ0
O0g9Pi1RQXpjYG03WXY1JkErRG5tOSVqWFF1LU9GM3dFdGBrOShXOEFBUF5+UFZ9NUkwJCR5amBf
dDA1Cnp0LXMyJUBoWTxJQTMrMj1tbGg4ezNWcT0+UTI1ME5SKEstQnZ2QTAkX0U1MHZnV2FXKipB
JX4yTjxeS01oLXhTJQp6Uz1tazFCeFN9QEFgQmw+YjVwfl5GUClpPzkpMFBZSFNEZVU/NyFwQzRD
NHFrRU0haz9wOENDR0YxXn0qM2Z2bmUKendiaDEpV2RJQHZ2NE9eb28+cj57I15pPF4/Nj1IYmV8
dDsxRFF+V0IleWZsa2lNciR4bTdrdzNaOE5HT2VNOTtfCnpDPF92MT9VanxBJTR2YFNidDdZcEw3
aCMrTiQoTXBxckNNKlB4S3lXP0A4Y3wqMk05UWhWM1ZxWF9lV3lAaz1ONQp6XkkhZlAzTkppUXhI
ekhoWS0oeXJqRXgoVU9ZfW5qXnpZR0tqSGl8Q3pXM2l1NGVje30paXBofFEwJGlCVlJ0dioKejlC
OypEbVclQiMpUU9qciR6VWt2MV8tKmY5eG93IShBPSEqVzNiOyFRKjhXaiRAYmAhVFpNc1VhNjsk
cHY5O193CnpINHxUS0EhYD80TWJ8UUM2ZDU4b0M7cEVXMSNKZW54YEUycUJ9PzZGTz0pPFZ3SDAr
fl4xfHxZJGw/WWxSdSVIewp6WCgxKUstKFModVp6VzA4aWglY2phTChFZ0ppcV9FK0MyK0wpX0pG
JmMrQ2tPQEAjU3ppaCk0I1N8NmMqWSYwVXIKelUrY2Z7ck4kTEBZOzEoN0NSQDB+JWJrNUVkcmJB
PU93WU1UWWpxeHlOeVkkVUcpbkxlR3JVaCNeVTZ0XkA1WWJFCnpRV25wJDQ0dCNNSHp8UEN8QTlp
KVh+M2BiITw9O342flUyTz1vdXlHSHhGTzBAb3pXNzwpendoUiQqUylTQHFvVgp6by0oclB7dEFM
VUl4KEI/Vl5yRTtJR3p8KShiSzF7VmRDNmZzKjZBKmpCbnwlKiVjY1dra1U/JkFiJkk+PzltNUkK
ejtsMDBpRzcwa2N8QX1pWnZfLXdubU49PVR4JUg1bT5kKmwqNklQQkpHeFVyJiEqODA+Q1lqb1V6
djxYQmJyaWRUCnpSKlFPIWJjKiN4WjYzO0pUUChlNHh0Z0M3IVlpOWRhN0huKnpuaWIjIXt9TGRO
Jm9KIzEoQElLWWw9KCNSLVJNWQp6SCskYWEwXm0/ZiNjWE8/aEh7bmBfRig9RHRCUU9WS34mQ2Jh
JkBsJCpsPVB4PVQmJi0maH4lMyhYNEBmM2h5YHgKelolVyUkK1pad2kwRUZ9SHs2TX58Q0pVWk5G
Y25VRiZ5MEp3ZXdMNGBVQzhINWo7UkAhNksoRDB7Y3p+NTZCUmM5CnpnayUlfUUmUk9sSDN9WFA4
U0dNTWsmcWRpY1BEeHJeeXVnd2U3dzlJYkQlSkNecE5uZURZP3koNmxyN0JaPDtgPAp6WVN5S0d5
Y2x+Rnh+bX19ejE1NDgrNH5CN1lGQCsrZmg1X0NwS3YkfCZvZmEyamZXRF9INVEocF40X3ZJJXB0
JXUKekE/MSltejRzVWBrS0xyY2B8cWBBUHwtN1dlaDkxNjhwRy05ZGxvU2o+fVA5cTU/KXxvVER3
cmREWDh2MF4+dWdCCnooQ3ZCRGhpby1oLS1fPDBuPThxWWY/SkFmUlhiaX1OX01WPElae0RJZDQ2
czx2QmclSFdte059I0F5cSlJcUdDMgp6bklScCllI2QrQHF2ZjNYc1h9e24/bGxhLSReTDhENE9T
RVQqZ1A7aUBMXiVreHE1cilQZGBnfjhqQ24/JUI7MXcKeihkOGFhM3tYU3BmYj1NY3lkfS1RbFlu
R3lScmg9M2lgdERfdEI+ZHgpJTt3JG5DfVghTnFEUnVfXzUmXnN+KnEkCnotdiFZQE5pOFc8QzhZ
Q0hXZHtjVWFDOWwqdGt+PXA7Y34rJGV9cEo3ek0kIX5ZXj9PWE9FQDB1PSkpfDFOejhWQAp6X0Rm
XjxvUTlsdjllSD1PM0E5JVZna05+WUFyZlBZbnd6a0s8Q0tIX2ojMk1AdXU1dVI2cGhoeTVgO0ZS
VGk/JW0KejIwSj8hK1JUNSRUTldwNVRLU3AzQytMJCY0eTU1clFYazxVUnxUVlFAK1hzSFJfME82
SWRBbFNUPVMobXNfVmYxCnpXcUliazA8Uk1LaGQlWjApcFQ4eVhzJTx9bTFlTjV0akF2TEF6UF85
MXhfRyR3dT1EYXtLeTgoeWRgMSloVm91KQp6WH0jTlBVd3hgTT5hai1BKWI7NDc2U3d0NGpqOT85
Mmc1OU5HKShITzdweik5QkdAaFk7Yzc7S3t6MEpNZ1VjRD8Kel5NQHhpTipkZkpEO3UzczZ4PXtA
NE54UTc+PFZgNkNGRVE9OTEmakFpMUlBN2pyfWQkJjNKb3lrRWElOzNFPn5MCno1Pn5uS0MjM1g1
QXxzKmFPKiNNNSlVYWBETG84YEYmZztRbV9afmA5RnM3e2AhSn1kQ2g2bjRgbEZXSyhLSGxgRAp6
RGEmTmcxPndCPkcoKGhfRXlKbWJqSHBRcnZhaiNqYFJOQWApTXJnJF4+WH4pNCl9blpNKnFqZk14
fXRgJnM8XkEKenNOOzZhQTlMQX1mdFlpO0o1N3ErMyhCMUU1NmpGMyZteD9zend1ciFIZDlDPkhM
dTlqPEowP2JOMkRHJTBoMSlsCnpjfUVgPk9WPkM5aEgrakY9d2hnbV59Vnp4djBhYjB1TF8hVW1T
QGI4RlJ6XzZFXkVfLTdhRkxBSV8yaTR4aF85Iwp6JU91RkUkVDlNKCpEMG1WJWFISWtxO3lScHQ+
PzRjSzJHKDcySUQ/K3RaUDNtKTRCJHlldDFfQnIjM141cERAbjYKenJnVHRqWj5zU3E5S3BGQWg4
bFZrbWdoXnlKMX5BTWxlN0U2d1h0fWlNclU2cigzTSUkZDw3fDhtJmtMYD9CPHBZCnpeb0pOe2M5
LX48LU0rJH08PyFIU3xDI1pKaXptbyk4LSkkZW0pWF53X096LTtgQ0NmIzVvfWZna0ArPFpSPDBQ
Wgp6X1ZzMSNndWkwWEN9RlgtcjBjdlIpVHMoK1JIRz97WGlMaEF5JlBiWDVFYnM0YlNqcXJePVda
OHMzbzJHc0tNNCYKeldlU3o3UnZeUXBZdGArR1NnM2hYWS13LWkpYmxidSVlWEErYnFCKWMoaFU3
eFo/VkhzQF9IUjMpY14zWHxBc0crCnp0UmF6MWUofTxoUkZ2WEFQLXVjK055ODJGUXBLaEA+WSEo
TVB0Znd9cktpMjg9PiQxeG4rYzxqSUEhP0gldEg+UQp6Yz4mfE9pVjVqP3tebSNTaktrbUlufWA0
P2RhQT16NVgkZVpQdzRmUSZsUyFyXlMjSEB0fGd3KGZvQWNONFgpVTAKeiFIJU1zdD1JVGI+KD0q
O2Vjek1IKSN2cihpSUZldHsyOHk3amBQWThSfUMySTcpSjNQK3dGempyVE9ZR0gpc0YrCnpoeXxt
VT9naVptPnY/X15zWkpKcVJjfXQ4bU1rc0MkdXtDP2lzN1A2bXBJeTk+U3NYd2x4fTJQISlMUmNF
djtFRAp6ZztgcyF7a0hkZEtNT3JvNCZVcWBPfE5nVip+cmBEZkVWNzslOSRELWU7Q09BbjA7cWc9
T0Z1NnNVUkg/RlBaMEsKek9gVSF0YVRvTmk8YEVQVm9je3A0cyUwdUxjRWFgfSZLRXQyaH5TT0lY
VWxBU0NodmotOEl0TEVJY1MhX0BzSGtTCnpVMTdsYmhtREpnJW9gU1E2SztCfW05fExscTJXUlho
T2pFNWN0ZV4xMjB0RDtTSjU0fCZqO2EmaDtTKmUmfiohNgp6P0RGdTcod0NvV25efnJtazxAcytn
ZXh5eFhZfWNeKDJ8NjctdHlHIS1jRXhfJFZacENeTUlrVlpkaUYwb2ZKRmEKenQ8clooTmJ2cVpS
X29uNVFHNC00KkZ5KHJ1TWM/UmJrRm1xJmM1aVkxNTtfdHpSMjhNI3JwS1ReVylqWGUxaTVYCnor
bkw1Q0peM3EoPVRhTj9ZPWo2O0JGRSZgRSg/UUBwbC1jcGdMajx0MDZnako1Q0g3MzFpMjJKVnhH
SGkoVXotYgp6MD9OVyNidGRYKCMtNDJMY2BmPE5fOSVtQyM7YT9HbSpCe2RYR3RCPj9HfDkrMjBf
UHZiKmA1STJOOW4+MGFeLXYKemZee1lZSnFFLVA5QUJJUWYrNlQxe35xX2hLbUxEa055NFpLYllu
R29XKHF9X2B2WjRCak1pVVomTTJVWiNzYUFKCnpqKmdDbmh9QndkVTczeEl5OzkxckswZTFuKGYw
T19eYUJlUXFaQDYjMHVqenpUUztBWXF+Sl4mR2xqdEd2RG1yYwp6QjdTXllUR35jWnA/JVYjRCVH
XlV6TWxWOUtlZG9QZ1c9QHthTVErSFpUdEpQUkpoa3VRPT9aPmdTP3whPH4hRm0KekdNMmc0TCU7
SzdJYW1kJWRLbj9mPVNuflJxM0d0VFlaRmFKPCpXUCk0bzVjYGo/LWdLUG09MzEhdmMrb2dZVUVo
CnpTOT1VMlglaUU5YFdVXz0rRDBGYF5YUl9eMzxobndEYTxkKXZ6MzlXIXdydD8zO0M/SlBwSUct
V1Z3NWZANjdoMgp6bVJVSWNwe0FTOVomVEc2VSRwSlVZQT1edkJ3U01BcTJgYWBtflBATkY7LW5S
KTZ6Jk42YjJXREIwY3FkQTlrajcKelp1OE5pVWpxM0hVWSU/Q3c1VFJpMWhZP1ptQV8wUXZwUTZU
Rn00RSFVXiolVCooTX5RIzt3RiYzayQhQSMydCh7CnpPQVNLUGFiO3k/XmM0TGApJldNb1lNPjJ+
N2ZfcSVUKno0fiVScVRUZHp+fUQ+Zlh6Q2x+aTsjRzw1dlchUlZRbQp6dXMlVVdkM20+bnA3P3FJ
PUw9MzltVilMQF5TOHt+OT9AXyp7U0E/a2NfLT5rSDM7I1MweWVpNUYwVUZadSVoVz0KeldiaS13
Ul85cE1PO2lkKHhETFprUEVQak9lRUdCRzZKUChgTlZ5eUw2OyY3JXpQUH4yT0JNSTJAVkc/dDdR
QHVsCnooOX1ZOGUqZ003Pno8aFpfVzZhRSo4Y3VoTXFwPDYqc2J7dmRvI3o8cEAyYT9hOEJtNk5m
UXBXZDA9M21idyZmYQp6cVhLJEIwRG9KN2BYSyRWYEdGYnxTdipKdlRnM0t5OzxJfDwlYFI2eG9h
KVFCSnlWSC1EbjdAbjRQUiE8KEIhfUEKenZPV0ohdW1VJXF4Kmx4SEZOZlBNeWlERENaXnZxO2ko
RTJuSGE+MW9oX2BCIThJXiRwOE9xYVlEXkgyVVc5LWRnCnp2SVo8PUVsWldyQUkrYiYkSDMqUVF3
KyNjTnNjMDZ0QHo9LTNfSUlhOCs3V3p2VXdZU2VGYCZaZ0JHNUV1QitlTQp6aFIqRT1sanlkaGkh
IyleJEVtQzkkI2F9Y1FHbFFBcUA0TG9GM1h4dDVrJDBMRHltdl8jb00zZGtIVV5RaFl4dGUKemxR
Xz80ZzlUUmwjLVJmYVNjeFVkPip5dzRuX3lfMT9sdHVTZFo3UzctKHopYXlpSEZ8UEVQVVEhRlA1
a1V5SGlkCnpAKjZmOUZ4STBZMWlPYEw8em9ATHYyPm1zODZLfEdXQEJMUlYoYGsyOHlYSGxKST9L
QT0+KmBfRFdiR1ItVTZ+Zgp6PTNjcCpAMTFCUVp8IzI1XjVtVmR6NTRFSl9SJm9gPkZMZ2Jjcilt
RiVsMG0/YUUkeCNoZThPZ0F5VW1ZbHtaYzgKenpuaTBOS1d6X15fKF8oRjNzJVJ3c3BMST4/QCMo
KnF5OTR1TmpLZ3FnKG9oMzlvU0UmezZiMEB0d2V5QThDIXZZCnpJSlM1Xm05ZSEqPlJvb2t7bHFF
d2gmVylVWkxnZkxfVUVBOHd7e19nRWZOJWM2TSp3IyQmT0JyeW0wbndTIzZzKgp6bnZVQyN6QSZG
S1JLaGVkRjtSeSNMYH1QWHlmITtNO0JsRzd0UzZ6SVhWJWlwazReQXRMeVRTPWQkcGJ8WSE/XysK
ekNITWZpS3AyRyU7OUt9THkmUHQqbytEUHJ3P1c1Q3l0ZCVDTzM7b1FZfnxUalB0NVNsKn47dHVV
Yl9eT2g7NDdYCnotTUFzd1VKUTFYVVUqZ1c9U31BcTUySnB9K3BxMWw5SUtpeE40MHVlT0phVyNJ
ZSFqcDZXSCozazw/Sn5VeyV0JAp6UzFtJDl3Q1pxNVEqJCR5WHhGM3p3LWhXe2kmNlVUJkx7LXJl
I2NjJWhoPG5ZYkNuUSVoQTBVUDY+V35nPVQ1N04KenNBd0NPZShITWZkSHBrQXo7MFZHWGZ6K1NR
Jih+OWwtRmdLNlhPJjImPGpuJWhXMDdYLX1wZUk2PVk7QVFeWXF6CnpEOXE2RHh5bkY2Jm9pOUgx
T1pAP3J1al5+K1lJan1GTkUzV2pUJXg2V3hrZnhkKj5MKSFKMyR2RiRtR0FwKDtMUAp6SnFjSil7
JCZ2WlpXcHxnK3kmU09yPmJ0PmsjQk9eNFooQjQ8XmdxKSVecWEtN2w0OSR1N252bUtkS1Uxd0FH
YT0KekQlPFlXNVFoe2twfTk8RntfM2RSS3FnNVBZckNFWVg5Pyk3VDVlQDd7amB+X2hTdDRLKERD
MHJFPXhWVFRNKlN8CnozRkFtVzhYUnUrM0BkRikwRDNUV2w/JWhGRGQ7JT82d2xHdkAjITJtZl9R
ZTlveDwpPj98JUtBWX1fbHBmOyVlegp6UiE0cSkjR1BwSzVwKHowZT9vZ2IwNVBjOD4+am1LNDZ0
Qnx3fXAwPiREVTgxbGx3IVdsWlY/PkJLKlJ5VU9nQykKemZIVm9rQ25qTV9ZSFBKNG1tPnY5ST8o
ayFWRU81Pk1eMjZiN2peaiM0LWFRaT9FQ3NYPSZlUXkwV3FKVzs1ZUoqCnp4P3lnUEtFX2dZbjxu
cGhhY0g1eUNMKnl+JFJLZSttaGBUVCYxYSg4K1MrVk09PkEye2Y+LU1hNylQazttbEg+Ngp6cD8y
K3JLdDtibU1wNXw8SGNgZ04mbjxARTRZY3k2YWI3SzM5e2xaNHk4PUYhJCNOX2JVb3dsRiU+NWY3
bXVXQGAKekp0STBrQHZjbDJMdnZXbyNnNFNyTGdaKm8mUW5gKWQ4KXdPYzJobztJeGQpfE9hNHcz
aF5Wfis1bVFKM3dhI2dtCno9OU0pIVRMQkV7RD0pKzZQdCtuK3F5aWVRZDVjenkjOTxfIWMoYGFn
Szloenw+SXxFUmBgKH1ZKH5WWkpjNzlnagp6OHtLQEFoMzdxUVMqfVhPOzszdGtKUjVYa0EhaFkk
PUghKlBKdnNjemFqSUYlcFomI0doTUR+K1VTTypSc3xjTlAKeno+Yl5lOVh8dzxkQD83QXBjJUZD
YD1nbTBjKE0qPzhFUStycF5kOGxfT3kwQWRzUiZRLVhnPldxN3h5MW5icl84CnphaEtzdU9+S1Q2
OVdxfjdUdHZNMmQ8UV8hTTRuO3JtQmdpdzVBVGZHV2JmRFp5bk9YNCpyU24oYDRkeih4REUzOQp6
N2R5JDx8NWNZbHt5dmRjdFRIdyNFKVV5JCReNUg3Jm4mQGJmN3k7M3d8eEJwUHJQQkReIThyQnF3
Y0lAJU5yQ0wKemB2Ujc+YT4wbHc5MnB5OU8wKVJ8JCtPTSQ5dWtTRjJqZ3R0RD1PSFJWUmE7eFM0
YEV2SHEqNUBhej14dDM2QSt8Cnp1TTlZN2IkOWpgI0M3UEpHcG9AbGc1MWFnNEt2bUBWeGElTFkt
VWUoeDktRzs9XlNUWUd1QStKWVFhJllVZSlWMAp6PW1pP29MVHQhfi01TnhZbjd2LXIkQ0skMTw1
a1dTS2ZQb3NgbC03WExxMVRuVjc+bWw3UXZTMHZDO35uOWs0bmwKelJeUE8mciQtTVluMlV9RGlV
LUt4KyF3M3Y9MGx2RFdeZEJWRD1UfWAkdW9HWE5pczNTKSR6YlVWNkZsbjRpWXRCCnpaYHhxeGN8
aH5BQXxYZk5BOVF3ZlI4I1JjJXR7cWtwJEohMm4yPWIje2g3eGQ0JjEpQnhtcU0jcG1Pb0RNRmEp
RQp6P1d5T3E3cS0tdm0ybnVoJXpBI1EmTUIoZkU8alhsVTYoVGJiaSp8NHdwdUg2UDhaMFI5LTla
cmozYD10dTRFU0sKejB7QkA/bHlHYk5UYmJSIVRAUCghdnlkYCkwZ3Buazc8U2F2UVQ2VVZNUHA4
bjBgKFdXQ1pAZ1I7e0RwVmcocTJWCnpaZjtwdERRR1c9QXckRSVSQDsqcmd2OCRsPnt3R3lNUEBi
KDJnXnY+QiRwY357RHJMN2luKDUocmw2Rl5AezJpdAp6cHMlMXYtVFAodW5Lc14yKXl1TylYQmY3
cnNtVSl7XmNeYXV7fXo4alVvMEA+M2c8JC1Tb2hzcmBmQ1ROJEVqX2kKenJ0RHJ1QUt1VkxUM1h0
aGR7RyRPeitQQkwrNzQ4S21aVDV4cjlSej1wWlM4fCtMSkpEUDNYa0EwPFZDRihFPEdCCno9bDxl
ejtQIzV+bWs3V2UyfCZNVEdXQkojcmlLI1FGTXVieEJKayFmZWtZUWU2T2tnUyNWMiY7cHx9ekhq
Xip3Uwp6U1M0aU5PSF93eWk9TVdNVXlnWDI+Qlh0blpwKlZ1TVNCc1FAPW1tbl9HUUBVdjlCK1Im
ekFiM3RgfSsjOEJ2YjEKemxXMH4oPnp8aG9eYnYzJVZaR3pWMl8wcWF3eXhrKHopPHN3USFsdU5W
dmAoJm1DVSFDTD5sRGtCXy13YEl4TmR5CnpmcjB7S2NZPClVOGxQdE4lZ2tgaUdmfl8zMHRJb053
dkFmLWB3OUA8aHs3VVkremJHMyM9Vlh+ZUZgX0RZZHl1Ngp6KjEoaHY2Yns5I0JfdCo9KkdWYW44
Rm18dVEpbl45YV4rY1lPe0FjfkZMbzRwQ2xKQSFNI3xDa2F2Vl42UCV0dSYKemJiRzBvUmw3N0Vt
eGZMKTtFQ1ZUPWNZbW52JFZ5RjY7OUN2IXxmRWNpSkFsISFxfl5SSGZlY2JkdG9hQShGNDw5CnpR
NTAtNzI1clMocDhKIXtkT2RYcG15dnE/SnUrVDQpcX1FLTs0V3hlUSheUTVVR3U1OSo8Y209JSFo
flNtWklFWAp6eDReKW5LdERuNnNUdVlvU35PPGwkRzRKTWpKSkd8dUwpWkRVMUk3KVYrZXhpbDkh
SlErIX5zP3pTIV4wZVY9YjEKelhAfVRhPm5wVT45O2U1akNjK0N1Jm9Dc14pa3ZtRjs7LTB9PlN7
Q0NrbGxOYEZGRl9AMkpxUD9MaDJLTkspYChvCno3ZHlJR3VpVkJiZXxlJSpBOUhjUUgjckxBVmF4
V2ApKj5nSm9sXk9MNGdHekxlLUxSRkombGkwYz9rYCRCZmBSOQp6KnQmWU0wdzt5bTVTPTxBakhC
USkxflRlZ1hzR1otVHsxbT8hWjxXIWItM19oczctS2VWbSRqRCkoWGR6dkUhZFYKeihSeytWR3tn
WnJjVj57UHVBZH0ybmhBSm5gZUNkKEwwKV8lWm1Wd1ckSXl2JkthanVRZzJCbGdsOCVKMHc2UDEt
Cnp0LUt5I2BuM1pIWntnX1FSdk4rOEpwe2NxbGxONW1XVSp4RDA2I05CeFd7JVhHfHtBNEhMeCEo
Kzd1WEVkPnlQKAp6VT1lJCVEUkY3ZllsbCotPmh8MG57JTJGV2Z2RkRHNkBXcEVtYlpnRnBBbWF8
P1FRdzFZYTdlZnp3anhmV0o5dmUKenI0TDFQYUA9fGFzMkxxUkhSZ0tHTT49eGt3VkpWc053JG1e
TmhRX31zOS1oUVozZWdga01Gak82UD1SbS0mfW1DCnozaGxLMzM3LWQ0eGhXN18tLSVvLUhYN314
P2MhZCZIWmUxfkdNeSV1bmJoS143ckgoPCVLcmRRI1JGV1QqMmFpbAp6a0JwOW0yLURXKlNMVjlg
cT9qIVQ7dThgPXk4ViVKZVF4bDw3QiF8VmxtNz96en0oMjB2YmplYCQpI24wemBKQGkKejMmYVo2
djlJNSMhXkd8Rnhwb0BSUVVxQV83XzJ5ajx6YkNvWT1ubEhXSExFKUcrKEFSakxWI2c2STQ7WVBS
UzB7CnpLaC1BZGBlVGJaSz9uTUxBR204I2NzQipTMSkrLV9XOUBuSndedmg1YX01OWApS2IzPGQ2
aTsoMT5hOEQ0a21TZQp6MFhOJmBaaWRLVE11KnhIJHFtZjhlZWZPLUZDejwrVHlfMmo7Nz48PVJQ
MUQ2M0BqeUt4XylBMjskZ1dQYXFpOG0KeiVofkFZPSVfWn5uMGh5diR8TENEJkYjZTh7IX1ibV8p
VnN4dFgxI0M9TXVsSTdLTV5YVSo5JmFRMlMwT2RaSlcrCno7TFl4UmgrZUYzWk9VeGc4YytXNnN9
PmFNMTZReFZ6NVYyKURhdT9kclZEelpGRkNeXnBhMjtQQSl6e2dSakIrOAp6LWBhJTthaF5KVlZM
JHpCYllOZnI9ZH1XM3prWlQ4d3VENW8zdkIoZWghJj5NI2o4QlQ9aH1mbSl0MDNrN2BFVEgKejBq
I1hXeWZxJSVkY0Q1NSppYil0S3ZwRm9ANDt3PG10RlhHdzR5KmtGSzleQ3llRik9LXdefDxEYWpH
RXYxR3MoCno1NFhgak9neGtxRkxyVDs5MFR4UEV0e25zX1F6I3BXRG8qXkJiVUdxJXV9QVdOK1Nu
MCNHVFF6VjcwWEg2UjZHQwp6OUkmOClVfkpiWmdMX0NQV1REeEFtNnc8RVVuK2RyYVlPcG87TmE2
Jj5JVkFXellsNj9BY3E5JHlDQFJTbl5QPzsKekxoMio8SGNmLXVlbTVrfkkzbSYyIVIqQDlYNn5a
PCp2THBwIWVwSigpJSp2YCVGNlIhbXAoNHJNdWRrT01SZkxvCno3RzdGZ2lGbVZ8VmxFaSkycW83
PUl0Uzk8UnJiMUU0ZXVHemJhVF9uOEVUODllYmNPaTM8QG9OLWB5QCUxXmdwbAp6bUhLcnp5VWV3
RzR7NCp4aVY9ciR2WHx7OyNGPF4ydj5AYFBFQ3BMJlEoJX1AUCZvNkRDNEZQSHtvajEmSDhAKlEK
enN5U3hqe0JDIWJhKj5SdWpebFg4X19Mam1pcnY1TyNvflhGe29uUTJ8Nkw2SnxEP3JWI0x+Kj9H
RSRFT3AxJVY2ClA0OGhMMHs5MWh+PT1jOHZQbGUoLQoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpk
aWZmIC0tZ2l0IGEvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlX2hlcm8ucG5nIGIvYXBwL3Jlcy9zdGVh
bS9lY2xpcHNlX2hlcm8ucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmE1ZWQ4MGZjMTg0Njg3MTMyYWJkNjczNzFj
ZDc4MjEwNzcwZjFjYTUKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDE5NDA1CnpjbWVJYWhnKnxw
YCMoKFVRK2Nja1BpdkpUdElCZFBzX1lUNFFibEI+NG56I0FHTlA7cTBWMEdEdFdfUWRQPWY1Rwp6
TUw8QTZXQEhBNzAlMWs9M0lxaWJBZG1uZGdwZCY0PiVRc3hkJXhmUjs2MDlDYX52TUklZUJ0JklY
fnhsVUR1c0gKemBvK098fEpSNFZtWGVhJVoqJEAyJVRpTCgoTmE9aGB1fUAzXz19PXFRITRue2JM
V0NIUiFUfnkxXlZ8ejh8SVo0CnpfQGpLdHgkN1pVRmdfdTtVeFU0K2E1JFhLP0xhQFE9ZFg5WGJ1
aHVgNDM3Qz5EWEFaJVk8flhmPmZPeDZpU1chQgp6ZmgkOVpiOThkPUFFdzhZX09fRWtNQFg7eFJ8
ekVuWnxyfmNeWUBxRF8zTUdJbUZOZHZtM3lmPXVsS3lzcyEyVGEKekUmN05UUmZxak07WXxDTmhI
KE09Yn1PST9OPDxZc140JGRmOG9fYUVKdzd7SUszM2Y/cU9RMHxHKSFZejx3fn1xCnp3JUY7a3Zi
eWNVc0JWRSVRZyhMSlE2TWJ6Y154cXJDY0U8fSl4NyRqPXI0QWpGUEBjeFIwV0A3ZCVwTzc9anBs
SAp6emRVeEhxRGxYQntLcV5uN1hBVW5LY1ZwZHVUYnpeUWloUDN7LVVffXEtJDFuTk44QUlMNGxG
MFlnUz1zaD8pJl4KemYjMjJCbFdtRiUzKTg4QFI7SHo8d3kkO0IpdD83Q001YFp3PTxtOXRzaXxx
aj9Vc2xCLXlpT25ZVzhAelRlPnBwCnopLWtyVXc0Vk50c1MtKWsrV0swaVY0Qnc1P2Q+MFYpTl5g
VEtJZVBkJG9ycExUaWIjKz1FQGFLIXR8fTxsJks+ZAp6P0B6bVowfGUxaGZlMUFFcHg8K2Y/bD9L
SEoxJF9ubEYmS2kmIzJRanRNUjlMO0U9bWI+LSZhIykzVzJAKTxPcFEKelQkZTZ6c3Fzb2w3a3Zq
V2wzcmUkSHw5Jk12SGcwNSE9fEsqci15SE82PHdtKTx6XyNzdCtnOU0+ckxHOTAkSm5kCno/TylF
TChSIUQxPj1RblpHdClDT3lBbkx4ZzZIT1g3dFFZY0t4U1paMztjK15JcjJjNXlUM3hAazBHaz4x
Xj1PYQp6dD8rNl5EMzlxPGdHR25BUl9IbCM+JEo+XzAoPGdIdjs3eDItTV5yNXlNNDNmaSRuOG82
dXdMP0U9YktaNnsxWikKelkrUVhAU2cyQG1Eemowd2pZbDgzdSlhXkZHclJZfHNGNWoySFBLVChK
RkJDN2V0c1gjMGJQM1E8JkJkM2BnJHspCnpLNCo0Ji1ESzA2cHYwQ0BfYUw1cWRjZzlKNS1XQ1BL
dEZUZXt7NEJjdUFXOD5UK3d4KVdKPE95SChTaXQ9NW0pSgp6N0p6X0wtPF5hIWF4MEBkISpLU29Z
a2x5Ynd7QjtFbFNAe29WTChxIWM5WmBDJEtLcjxPKihxfXlXM0NXM1hJSzMKenQmaHNQOy0wPVZL
OSVrMW5IenAqPEJxYnROd1QkZC0wWWA+LTA7WT95QmNnUE9EciV0OUJiI2Bwa2JxdGAxRU5VCnpw
XmVBRlNUPiRROERjdF51P20mcClBPURvelRwdTlqPURLeXI4a2tVcDxNVnBQbHNOdllTajRvcHBj
Xncqbkx2Qgp6UFIlU3JSOGR9VUd9eShjczcrMTFJSzh+MEFFI3tWY34/S1N7TCN6Rl9SNDleVXs/
OUFUSD9rWGooUEE4dlQ9JHcKenh5eihPVjlGa151WUxxeV9LdnsqeXc2V35hU0RNUVg2flZXclN6
enVibW8/OXQtVVFhM15ucm1NK2lTdVRFYGF6CnomRD8jd1FtQSQ9al5AQkJsalRzfG1GWmEmKTM7
X1oxKUFnZEJhbnorfEdPRHs+M142eUwhMW9uXmptI2wpVEN8WAp6NUBLVCp3d0B7TzVeSEMlV0U1
Py1yaDAqVm1WNShSVHZtR3loajRUfGJpMS12dTw/JTdOWWVxc207MiFTb0BgJXoKenF1Wn1FQHw/
d0g0WXp8YFImUzlKRzFOYGBeVEpfSSYpYlY7blZYWmxqLVNgT3RZJmtgaSFwUUVxRnp1YTktWSgt
Cno5YDQ8aDVEQTwkQ0VmJGNxQlhrdD93KXZTbl8xNzMzXiR0U0c4KGk4NlVqSW9qZV5VSk1vVF9J
Ymo4bGo9TE5eWAp6WGhBNCREJlVFYm1lMHgqQk9LUGcwLUByNFJCRCUkKVNiIUZ2N24hI0p8UCU2
V0pVeVB2a3AxPXglT0N9YWlrVzEKekxVZnNkR2R9KVU/YzhORzxXbXtlY0dUdHpAdSRqbz0xQTk3
Nmp+WmdhciM/MGwmZyM9O3N0VDhwaDM1K2s+Z25DCnpTWnFWTz44cnNuNVdGbCQ2QSQ8Nm5LWnM4
dzx9cSV2bHMrK2xVVWVQJmBfb2U4OFNnP3BPalJ5aUt2TWsqdE5Zegp6UTBXPj5hU3VBWmVDVCtx
PTRJa2QreVkpIWdUTUxMci0zSSZpSk5ydFlHRTZ2ZCNmZDglKitASmUqTWp0a2FLbkMKenlIbmZ9
K3pIIyhzfnZ2c1gmM1dJZV9uVzsmXndTYm1iaShQTW91dG1GWkE4fFBQak8hJHojaC1XTlYmfThB
bjc9Cno1ODlrcVF2TVI2aT1RRlRPYFU2R3srMTw3OyU/WDEzUkBNZiUrRm1RPkJxJTthbXFGT2pV
JmIzPFp2QzV4Y2VTTAp6SUlfI1ZeTHxVcnhXVmRTUlM2aXM5MD8xLVYxQWFvNUkrJFIpaUFeQEZu
cXl8XnhjOFBHe1Fgd3s8PSFLYHdJVE4KenhLVDg2UGZUTm9lVmMrNyZ5NCMoVG5AdmE9YzV6NWkk
PnVEMnBANWBKP2UmSilvbVc5alJOdHJZNzRTJDd4PTtoCnokWDNSI0UxdHApRThKezlhTnFlJDRl
aHlMWHtpI31lU2ZHNEtoQm5RbTJFWjRkUVReJTxWNUIkaj5aLVV5ZmBSWQp6ZXJqNTA7UX5zbkdX
TldMPzx0cnVRZmJzWWZVT00zUVVJZms/SUZkbFB3VUpwYldzUWI+RDVoZ2xYX0I5czEyI0wKentX
X0NfKlo9VVN3QFlec3Arcj5xLVhiJW5rIT41XkVFMG90bjspd311ejd1SEBTP2g5MWJARzlQPEgh
UDFrTnAwCno/ZjMkSkshcz9eMlhhNkQ5S00xSjRsflRUeUhPZ3N1ITRFWDM4UjVVLXlEVE8+LVZ2
OV9ZakxnVmVoS19SRCFZYgp6YzE0bjIyS2dJZjEmSExFa3c8Tl48JW5GPDNRTm5OSG5+Yz9ffiM0
XyRYR29PQWdzSjtqYTt0cVRjdUk5V0JSdXsKekl1a0YzTWgkWFhrVDA5PytoX1RSZ0dBUWpeTzdZ
YE1wdjJUVUEmSiVZKSNMOEZ0a0EqJF95VHstIUNycVY0NlBGCnpeOWJCMVdZTV54YG5rVUV2KWJ1
S0Roe1ZrTT1VZnYqYnBzX0pROG0jeHdqK1FXVTJ5dXopKzdNJFZ0JSNRd0F2QQp6RjUtcm5PMyhV
dXBoSTU0JD5YSFdPMXokNklua3l1M0xnNF9LJTNGelprJT1LYXY8KnZVNGUmXk00dmojeTR4NnsK
ejdpJXMhJElCJXpmbTcpQjt8dDJVOX03X3luIUpwMmtIdV9qRjE1XkpuWGxpb3AkSGF6Vit6eFpg
ZTZVMSZOZlVxCnpEcih1NFl0IVp9ciozbiYmMDA/b0R9Qll6ZnJ0Xy1XdjZ1QD1ffHM+K3VNfiho
b1ApPHtWMWc5XldQeiM3QkRzJAp6JXJUPXpveCFEeUxeYnxhajJAMWclT2dpeG9SbkNZOERgMjdg
THh4Tmd6M0tyP3VLQXxoRHZgRWdxS1ghUHYkSUAKekg1dyVHd2BAcTh7al9jaDE5S0A3Q0VqVyst
eDl0bmlgMX5yKkJtIUU0R0Mlb3ROM21CQFZPS2daZ1FuKlUmRElxCnopcmRNJGdsZVYwR1AhbH5L
MkowQUFrbmczQEpLdVolPDRyYndMYnVgQmhfZ0dmJCFMKGMoLXQ/c00mNj1nUF56IQp6Uz81ZGJe
N3I5SntUUz0xJHdWNVRsdD9CSSRqLTwkMzF7X3RqQWcqNipNWUU8ZCZGR15NeSE7e2pmd2U0ZXk5
eXYKemBAQD1ANH5BbS1WUXhnYzJtT0o4TTEmek4hV2ZNNm4tSXdiZSotYnB3ZXBLM19va0l0QSQ3
UHhKJld2O0Y8XlN4CnomSD1zN1g0c3VOV2tCcTZVSjx3PkI1O3o/RXE2YSFHZyN9KTYmUl8tU0pr
UThWZzBDOCYkOTM8ekREakQxNFlMKgp6QD14UE1qazxANCM5MFpZOC1ze0k7JigjYE8/UUFKPk9v
UGBNYWZfUXc+PjU+QkVYbTJhQy1oI0s3aVN4a3t+fWQKeko8VzNkXkBpd0M0RUh9b0FsMzYzKm5X
PXJxIX1WYnM0YmwwbFY2N01QQk4jdD9ibUB1eCp4aDAjV3B9QU0hMHhWCnorPEc1Wmg0dWpKSm9o
ZXdPUndrOyFhUmteS1U1a3lMaiFAZWZmNTghNkcreSExdGk7VU5mZlkld0YxblR6QlUtfgp6QGdp
aW48YGIqUFFlcl5WWDVJTVpkVmJ5Mkk8digyKFhQcEc7XlRSX3JYYC0tSXdId15xdCg2T1piQlI2
cW1GYTEKeklfZWU/di1eY0ghO09hM3M1MU0hR05aSnQmYU55JCFTQC1kbVktZzQ7MkE2VGgyYFV4
SVQxJjtBIyU4SjFTVz9zCnp4b19fe01GfTRvPCVkbGg2ejwhdjdKSkBAOH4hOFU2eWJyTSN9c0Br
YTtBbUlMI0wlPzFvWGNMaT04b3BBJUJ3Mgp6UzBLK2E4ck5PdFV0UFE2WVdjQF49WHwmWHthRG8m
NylhSldgTWVpcDtAZEp2V1l6N1BrU1NidXM/Y2FUb0RJVzYKekdHKSltWHU4M1ErfUlqM3hfczVs
RW8yc3hhQ0NkaW02Kl9HOVlAfDdrcC1MbFU9Y1l0ZDdIaFRPSEl4VylyPCNhCnpPP0cqYTtQcG52
Y2Z5JCM5SjNPaTwzRjFVN0hJelpeUCFMNmB7YU9UVV51RkQ7dGhZc0VlTUc4WmJMTElFdHBBXgp6
b2YhUlYmITtOWlJ3UGpWcWFrZU91aCp1WENSMF5MTGl5Q2psc0Yxcl5FXitzTm00dURYZ3YxdkBA
Pkp0ejt0U0cKeiRIJi1DcmpxYzNRektfKSh6Y0Nwez9iZVZTTnZvaiY1bkhNQkl4OXk0a3k9WmY1
YzhTM0xBJGhYMEMmQW5ZTG5rCno1K2g8UUpDZ3FxVGNVVVhiaTRqeU4yOGVvPE9ZTHJ5YS0jbUJE
Z21sdiR9XlhnMzc4KUhQfDhsdjVYV30zKGUlKgp6NlJAJEFEX0U+PlpZYy1VeDA0O0cwMWwlTStR
R2o1TFQ1Pihxc0ApcW4mfklEUGwjT29SS05PdT8jfHU8TmFTbSMKekZ0PkRAbz02Z31gJXpBQVdt
Uk0yRDY7IWlzMEdUfj1URWw1ZVpKVn5CWUQ/fVh9OGEpJC0jPEM8anpIe2I5QjlICnpkVDtGKl51
IU80SlhPNlAyPXwyI3s0aSMkalNNeDQ9elVgP2NqTHZpKm5ma1NVTFM/U1QhRkJmTyFqZHQ7alBf
RQp6YDdnen5LeSE1XmhUfWdQMzNAYXl6XlNpX0QkO0V7ZmY7U3U+MCo9TWokZSpAK1NPQmE+biFO
eFE0TDRfKno+WVYKeko8OG9KSGQ0aG5XPHhaIW9GSHkxUTFSe2s5aCUxJUhjcigkbmsmSiFNekck
XiY5b0EwbGY8NzE/KUY+Wm1fczFwCnp7R0gqP0phTyRhZElzcEtNY2laMyVGdENBJHRxS2hDPUlt
JlprSC0xTDg8QkVPX2xtantRM0Q7U3kqNV5hak8tcwp6Q2dlT01NPTAjWjgqfTtnV348cHhibGs2
c3hCaWwjZ0s2Y3Z7JnJ2PD83JX50TE8lQFpEcCgmZnswKTwlVkM8WDYKekZiaW8xdnpiY2F5cVlK
LUNDWEkqMExzWEEyblB9TSMjO3x3Sl9CQzw9PVJMbWFRMnUqM0l5VlRYK2d+YFEhdkJ4CnplTEl1
aVpLLSooVDJ+XmNWSXRWVFo/OU1oJDM4VmBYTVBLTVR3bUpodjV7NkI9biV8VkYqXjVKMCpGKVU1
TF9WSwp6c18rfWFiWSNASFNHP00mQ2tBV2ZqRWNQY3FAbmd9Mi13LXdzTVFYSSNCPVclWVFpPFdj
clcxUmk5Yk49bmQ1TGsKeitnQ01gYi05Zmp2KDkhOTZlUnQ2QGxgT21wS0hPWllIWj9EKyozKnlz
M35yJnt9NyszNWtvejIqJXt2bGUwbTFXCno7ayt9KTw+SVRuN3EoXkQ0M29Cdmo2ZDdBZDBqMGYz
WHRmPjQjRmJYT2c0RXMwcnpSMmtqUX0yVTAyNHV6dDA0TQp6XzBCbjRgaSFiPnowYWk7Qk82ZGVR
QGFjZ0A5MkgoMDZjZ1AqYSo7MkhCMDhUeElvWkZHRT1MMCF2TTFWRksxeUcKejl1UE9ASVRocXly
ciFMX0V1U3hwVHZ+M3I3UGtrcUtZSSRCe2EtLTQkNjZZYXswa1A5Zj02OGsxR2dkNldMaVIjCnpk
ISlJWmRWOW80SG95Z1Y/USFJJT1FfWUyUl5NckQ2bnM4O05RcWMqbT47Pi1Kfl59Pm8pIWt2bzMx
OS1wUGgwQwp6Zmwxc2dEfER4Xip1UkJWZy02T2FNJjdZMVJVRWsrJSV5K0VraT4pY0NRMSVObzhW
KW97JSNLKT9AMl9sbCE7Zj0KeislMmpLJkstYiY7O2pMTm8+bmU3a2RnTUdtRW96RUM+KXd3SXBo
RUBuKl42dmMwK0B2eW9LJkB1eVcjMm9EJCo+Cnp5Jmg8IUYkTn5BKThTam1kOzcxSHJ+P3BYc0Ri
OD5NYytWbkNjenV9V1UyeiRFej5JcUFTanB4JU9RMUxkMXFYMAp6MDU5JWI4emIkIXN2eVU+dWtI
dm09PD8yPmNYYzw9ckg5OT1VVHZWJSFmITYjJjFWQnV6a15pSytmanZINkA+Q0YKeiUoUz44dnRv
Mzd3ZiN9OWJfVDVKailtcHY2K3hvO0ViTFJ0YWd6MTx4TjNoVzxlck9SYUN6VUVaVmxpbUpvenVo
CnpYMGBubHF+RzYlMVJuQSheLTtWKHIhZ2RSaXtPVHhENE54VGpubiVPWXw3YzMmWVJPKnlUPElU
RTFvM151ck0mIwp6SnN5P0hrMzlwWGB9MEBART9BNUlgUlJReXI8NShzQjNpdSRSdGo9VCM2Jk9K
YCYtNTVlfE14KDt6OHFlYjZBWj4KenorM3YxXjhXKDY7V2ZWVSpsOytKNm92JU5aI0gzIStnMjQ1
Wn1rSEZ0PXE/dWVhP1VlazhiJEREfHdESWN+OHBfCnp6JD94SFNAWFlJbz9rMlUhRUBfYFNzP2dj
dyllX0k+cXVSOWdEdzg4JWc2RFk4K21uZXpeV3p8ZEp7ITMlXlNkewp6JkRWZGstUTMtQzV9SzBj
UDw7emRINj1UWGQ3dVAheXZHIXEpQmY8cmBBcnZXTkE7MUJpNDVLJmljTGJ7cnBzT3AKemkwT3lF
Z3wqc2E3IzVvMjFuOTJvSk5+dCZGbkolQFM+SnpkKFdKVUQ2e3VTb1RpR0tHTmRfMEU5KHhRIVkw
XmBgCnpoVVpENjQtWW5qaFVRaDZBZEB9YjNeaFhYcmpeaD5ZYFRMNms2TWBoWShLZyMtSWQoSzB5
aWYzPUprPDtwZWVkfgp6ciNrdHFiVXxMWHhKTy1iaCRwSlA9PWQrRjRvbDkwcTVRQXY0cis9Yz4r
UHoqRjNWQXVJJVM1PDRGTGxgdGQ0X0QKeihkdShXVk9xWWsrfmVtRzA+QWopP0tqNiZGIUlTUDhR
TCR7ZXNuSk1ETCtaUCh2ezwwb1hNQkcxQXFISlBRS3xSCnooT0h4a0ZoJU04MFJIO01YVUJhJV9Q
XjRObkMxUmVVPkxHcTwjODZZY3hWP148SDJ8SXBudUlKJVViQElDeUJJPgp6WWsmcyk3WihFRyFQ
KTE9T359ZzQtKnoyfSlkflpIUztORFN5YD88RG94Y0VKZWUqQiQ8ZD5UK1VfRjEjVD0zcG8KenxG
ZmtaJU9nai1iIypXdmVBUi1nfExUOEBZUWdxRGFUQ2A2PVpXc1pKY2p4ZDN+TF95YiFSMlR0bjNh
KjByQj17Cnp4Qm1xZmFFXnFhWS1mN3tTR28tN2VOMlpWKVdBdiNuQ2tqKG9fYmRiYUVIREQkaUN1
KTh3dzRuQCVXI1puY0M9RAp6NlNwM24jJDB9UmpBVDNQe01HLTZ2cHE2KUBpe248djVHZzFzPU9R
XjRGZGl+OHR3Zl5jcEYybHd1bmdSTjVoYmsKeipANHRMRzhQPFpXZGMtUG4oNDVCNTJtN0w7VnF9
dUpEMSt9ZChAUm9CczhQK2o7KH0kI303SyNLZ3UlIUx7THIwCnp4e3NkfD1JPT4mITs/UEImTmRF
bVRPa3tWa0khWDF0Znxeaks+UDBxVFBncDxpPSleQ2NXI3orRD97OUpVM0NaZAp6NXFIPEZfWlVl
dSVEO3B8WXAxO1g3SThXdkdIVGxWR3ZASjNrITFoOyhrbGJwMXhQZGR6byZiQDd5QCsycGAlPkgK
eitMdkVlVWhlTGBfNjFaPmNiPFhHeHRtdVVFdkdgMXQ2QH5Ge0MzQz1DZl47ej9yUzt+eHpSOTxm
cn1mZCZLPkxUCnojPnVMZkgmKFdUdFJDKm5fMFhBQHpxSll7JDVBKnFJO1dadmE/YFhBdmtuckdr
YHlDPGBlZ2RBNVdEdjYjTUhaPQp6MzVNfTslNFhHKzVmRi04ZFBvb3RQVG0pSGNLO2VVQ0NnX3M1
Mmk3ME08d35rZzJ5KWxNaDhhd2YzdHlSc013aS0Kej5KLWw8X0hLeThFZXZJMTshQlZTJkIpaGJB
T0Y4T0VePXcocDR9aUNzZER7aXZGa0ZZSjRIVm4hcEhMK142KTxHCnpuQTdSMSQ7OWo7U2dlcWJK
Kkp6I1JZJW9GcG5pbGxDY204RCRxJD5XeSN5QVpQVH18JjNURTg5PG9rbzVAekBkQQp6Y2slP2Ar
Ky0kMz59dCY0SDZFNkNxZmo0el80K3BfUndgdmNoLUFXIUA/SU53ZT9lS25HSDRRe2h+T1kzKE1f
K2EKemRjTnxuaUAmX1FKRCYpcUdEaCNMQmpRPW52Z3RQPiFETElqIyZzfHxtWHpQSTxmMnxvSHVX
K3tyd3hTWnVTU09rCnokTFQtND0mbX52cjQ2antoVGhOejY1KHxwcjJXJkctZC0zbDJ8WDdMRVVU
cztHaUFPR0Z1YkJhaDUjTVQlKUBaQgp6VXJ1WSQxUjUpXjs5ZSphP35XZ3dGQj9vWihXdFVfQUVY
KEFVVjRBYFlMbXtuKnRqQWRqQ30md3dhPHkmRX47QEUKej5OQG96OzRwZT84bHV6V240S2ErSSR2
fHVzQkp4SyUtdnRDP1pEWT9rMmBzcFhIb2RmJmI+T0Jgc1hDKTZ6RkBBCnppaDtuSktDX00zQEZN
WnowaXU3IXhsZlgzYCF0WVdtbCNafig/Rnt8OTcrMEFjY3FEeGB+MyRCV1ZLRjliVFQmJQp6JGhs
PmVgZFZYUzl2cVRpbkNvfl5KMEJKZyljKWxMV1ZiVmtUP2I+dXBZOTFBbl5fOGcxKmA+aWtzajwp
NGRtWEUKenByNnBsIXomVUJuN0pFPHQkcl87RTRyND89MGhIdllxZ0FlPVF2O2ZiKmZfXnche3FZ
cXY1dnNHdzltMFE/ZFNSCno/TmhMZGo+KWtKbUhAdzE8VypgQ0Zgfns0Z3BVNThjaDs3P1VzcDlB
YUxNMD1MaSp4MVUyeSVkP1NDbklyN2FAZgp6QzVgcjBteVMtS3oyWSk3bXtXam04JCRyOUl4YFBA
KHRkcW88NUFAN2hEMXdVcUc1eHFSPCo+Zm9KX2FTKWd0P3oKenM0Yz8oN3trZ1JNfH1OJXhAI3wr
O1o+WTMxR0AlQihwcWhVSi03M0xZTXQhbFB6QiE5ekA3UndBbzJBQkZ3aFJZCnpvcXFwPDlgKlNi
JGhebCU3ZkhsQVVSfXU1Nld1Q0BsWWF1UHVyKDdeOz19JSYkT1NgUT99MlVpTUVxbnpwbkR2VQp6
YypDREt0RWdNLSo9fVhJPFBZX2BiPW55WWloJS0lU15PVHRVT3ZrQjkrNihBWG5BTHxJczg1Mkw2
bz4zYypWOSgKemwjViM5TUxqc05ZeVMwQlVnaldWWWktenpSVWF2SS1WfThSNTZvdjFhWipWKm5g
UDcqYGBvIyg/ITtoJi1fJjI/CnoqXnpmKUBjQC0/QD9wR2J1UWlYOU17P1JaWUFuRCVwSTNeZDRP
eFQ/LUdKNWljY0xiSERYUjc4SG1wWnIjZzZwSAp6Y2NrQ2l0UTRVQ3Y+P0NTc0RDNW0kdSpzPmtK
IXd4KDk+IUteMzt+JT8hKTIpP0NqfUE/eGo1dlBmRlM8MkxNPykKejR9LSVpLUEwcUZnU3k9N0B8
Izd+NFk9amNrKWglezRnPV5oMWM9P3tebDJsQV9YQyM0TWF0Y2h2YDZZNjcrKCNxCnptQ30kKVoh
Mm5kd1YxcTgzK0dPcUUwakNlV0QpZHNWajQyMzRKPyNgb3h5X2VKeDd8UHI3aDgrcFdtZDZobjtn
WAp6ZHl8KUArRn4yQVI5OH5fQztyREFnXjcmT0tZS1lycXdeYj1yS0VQPTFwcmVGc1g/VWorfTs4
a2ZAfShqV1FjcGQKentmdFI/ZEVASHBCVT1waG9HWVBRPjlFYFQobyN1N2ZDb3hCTHokfUR1ZXpp
eDRkfWZhPUVKZU05MFZUSSUzP1pqCnp2ZktmVW09OWQpI0JsME41UUF8e25mKytfI2tucH5qMUpX
PEgtUSRuNyQ3aFBPWnVoNS1hUml1WXBrTH4ke20tZAp6eHFyI0k1OSZSMHViYlFTaVFpdV5hQUdq
PiZRe09iSE03O2NsYForKFR7VTwkZk9+X1Q0T2tfXmFAbVdjV0w3dGAKelFHYUkrS2pmWW9AODkk
flAxVENAa35EK2d0PWtvTTB+MURibkJoRn5UdjcodiNHQE43dGpBdTFxbVN0O0lDTyZyCno4SGAt
IVoqVG5Pd181WFZzYXEtMmZaTSRfOV8maW4/RHtUTk9ucm52T1I0fSRLNTlWTFpUfFdWS0VqO1Ij
RkFWUQp6KiNjSSZZQDwkenFRPSVuTyp+fW8/QGtaMTs8aCVGV0JmPW5tOHk4YFltMHY3QmNTMzFJ
NjRrYSRIJG9gKHYlcVcKelY4SihvdTd5bEBQSkBZRERCbDM8S2xENSRsK1QqakM4dVZpb1VLZ1Z5
MyFKbTRHMXAhdERRQWglaDhteWA7fng/CnpHU01JcW1CKzhNZCQ/fDRzSVpXQSF5dy13KGkybkI+
T0g8JHxEezUmdy0kKyhoIXZONVlhc0h9ek1iTDBlX0NZWgp6NUVlPjdDOGdmUl8mayVkbCFYdmxo
RTBHdzdFVjQ1U3NURHo/MmEqN3Z+JFchdWw9KUtDMSlnWTkqfH1ea2xncV8KelRyQj1ZSDtVNHR0
a0NafSN7cFk/cEF1NW1TKWZBKmVRMFckVlVGO3dFKndmeWFVdEZZRj9PNko5X31US1Z3dHw3CnpW
RHo8ciE3MXZpJjl6U2p0THx9MlpwcHckbitGbFFnaHVzJjJrJHZvWDsqV14/R0lEKCU1Szt1JXQp
eDg9ejhJPQp6Q3AtYk9FYFBhV3ZWe31ASnRzeXByYyFZUV9vO21sVklgZENiVzdCKCZlbEw4b2Zs
djZuYnc5YiQmJG5zIVBLSWMKemc7XmJXWFlrUlQhTT01dVhoPWs7d00+dGxoSTBmIUJpYWNeajFw
OWcybWQtO20pfUVNITJKfjlZRWNwN0c/ZXZ9Cno7Pm9XU3prNCpuPDZaKGFadThAdlY8Qz9pSyoz
aiNqSUA7cWc3YXRZVXV7WlJqbHpMRXZKVj5QZXVhaFIqRVFnTwp6dXh0biNFKTxCZlp0SmhBI048
I1BaUTlqYWdMLURsNDZiKnN5fHZhciZKYWZreFA9ZVNNK0R7byt7MkskRFU/Tm4KeitII0MxUnlX
I19ePjh2KUlRNms3I0lmaSZOJm9URFpFcjg2T3FZRVBVTFYtZD9XfWRsNVQ4PG1od0AhaENBeSRa
Cnp1UD5GI21hYjhVUlReQGZaI1Ixdz1DJDRCbTdTXl96JlpFa3ZtPmRZN0s1NUpkODBhYmFkc3g0
RXp3ZUNCMWJ5Xgp6O2tkYUhuMVojbCR4JkJNe29YO0grRCp0SFgoMiQjP3N6aCg7a0YwcnVuaX19
YyZOK1A8MTAyYFEtWU5vRD48fSkKeiptUE5xWGJ8LXk4TDQ9aT9HTlYyRz11JG11K35wfUUyMm0j
Kz56MWh7ZlAyR1VLK0Q3b3wrPXFIP3YtQG5zKXFmCnpjZi1ER3NxZi0/QkU0RWxwKiVEYkI1dzN0
eSZ3cipeZ3lBM2lUPUpsYUFkfW50QihHez9tMFFNVSl4clVBVCtkcAp6bT5gN3JQcHdCeyNuPEQ4
KGRxYWp1bTQ/Tng1PXxvKENLV0FEXik5KT1ESEBmdHFPWXkwYT9JWChJNFFEelY/RW0Kemd2ZVpT
WkxGPXAtNUNZbVRLQX5kPDA+fSVOYjcjZU49c1d8eThTIWdpcF4/JVEtRTt0I2dsJkxMTnlhNUJF
PS1zCnpvTT0lZTdAJEY5VE1YOXxaQHhaZ0JaLSp0KmxrKUR5aX57VUpWY2JjOEMtSU1pclAmXlRS
VU1tJTlpUTFYVFIxOwp6ZDt3SXV2c0ZzfVNieE5YaGMzOWwkdT5VJC1GbSZnMzVWVEBiJClydmRg
Wn5NV35mNTR3al42VlFJeyo8aioxREoKekRXQGhWcmYydnJSRFYxPzkzbmYqNElEYFZrLSp3K3hw
ITFKey17T3hjX2VCQDQlcH01aiRYQ25aRTs/OHozcyYhCnpCVjlrUz54U18hQzlfTGJXfjdWaXZk
SFdVUj8wMyg1aHMrd1g7YklJJEQ3d2Z0YCtIaVBvKElGSnVpV2R6dXRzXgp6bnw2eWJJKjYlQFFA
Yis0bUAwd3dyaF54fk0/cmxxJS0hM1RvdkdaWkRYYDQ2RV55SDJwMW1JQzZlaTA9Kz9WcnQKeks5
KThrV1UjQFpEPmhlenJPb3NqSXNnRFI/XzN2TG9ULXM/MyMqPzVVVTBWIzd6TDEpPVlKPXB1UVVw
bVN7Tk5hCno9VDNIWXtgelFsUUM5ZnkpS3w2bl9fPVYjd2xFJnpkYHNvZyNJXiRLRispe2c+clB1
S1A/SD0+SX5sUWltMS1OPAp6R3R8VEpqO0VrNENTUXllaXF9ODJAc2ZKMjA+NXRqMylCeV8wVGFt
JEtAJnIzU0Jyc2VaM3xjLXZXNGNnUDRebVMKejA8VT1wO2olYChzLSk2TGcpO05kcjU3PnNZeTsw
NndsRURubnEjYDVPQDgyWiNCRkZJaHBZVmROMGV6QFZ4Jms9CnpkP0RCKT5AQEw1dkgkdFFsfXF5
QXZAQUx3SmBjVEVSNkxlSXRsQzxMcS17UClLU1g/ejcoYVg9S3tzPEcxKnQ7Tgp6MEhzbS1VQmB4
MHJSdkVCUFktTGlBO2NlbDhqSkF3aTB5bVNQbXcrJDdAc0hTQHc+dEMtfTZHNGY9SHN0e2M8Y2MK
eioqJlN9VilnTUFMNj5MY0lhUFBYKEh2OzlIZkRaQ24wO25WXi0hWUdUMGwzeVFHcW1iWmtwQGcr
biYtWUdaWGhICnpjajxkQGZFfDRabVRNXjVYfXklenJxZmA3R1EkSjhYeVVRP08mMUhaM2YqbnQy
eGxKJWtgUEN+QHUzXkkkdno2QQp6WXxjNjc7LU14QFR9NUlIVFRodCMye0NHQilTSylLS3lYVjU0
JkIlfT95RmY9amU4YlptVUdLaj8wVURzRHs2M18KekBsPzVrczYzZjkoTGRlJl9PJF5UamRwa0lD
I3cmeT9hSyRuOTlOTzMwJi1KTSk/Sit8PU5rOS1McGprR00qM2tNCnpeSW18a098SWM2VmVyUDRY
Pk9ZUF89U1l9KTtLMmVWTlUxJCNGcDtiSHtZXmZUQEFKdXtObHpTOF8wI05ZbEtVOQp6bEN2dX5m
Tkh0NmJ5aGFqUSMlSkJLNi1zZSsyPyFmQjZ2dWdPTkwpV091OTBXN1MrKEdjUj17MGNiQmo7VmF3
IUYKemp3e0ZaV1JpViNYK3NnKEd3PXJhbCt8RlZUOyF6dEYkcEktdDk9YEg2QiQ+KDF2VjFSPjNg
cUZDYUgxVmg/Z3d0CnpXQG52O2RsUm1gWFhzSkZOXml9P21GRWdxPWtDI3MhcCpTe1FWTU1QVHVZ
ZWdvRVArfXokOzspZTQyYHUrZVd5aAp6blp5Q3FRPno+ST0lPDQ4dithUzkpJHNNKV49WlN3SS1j
SG1TcUZRUSs7SG8pSiMqSmBAQ1V8JkhrN2dIUC1eR0kKenZeOV52cUZSZ2xlMHstQllkN3YlUTd1
Um9Xc0EtXlBWNCpmRUJnfUUoQj82XjtRQU84UTkxRlAmT09DWnomJTZvCnpVMkw9KGtHbyYmaTdJ
UFB6SmF1ej04bmVXe3lkZHxpQnN0YCh1YHdDc01HUzhFXlQmYj4zM3xpeD9wZGJOOW0kKwp6YD5n
OU8mME1aQ2piLXdsQG9DZX0hbWBkWC1ZKTBYeWNtU3FZZGdxSVFVeEpTV34tQll4IUlOc0BHPz9G
QElsfGIKelV+YUNwM289Mm96IzdYMXVjQFMmQ0tVTHpvfVBINiVsTH0/M25vdnN6RHxVNyN1NDJu
NE4/UUw1Q3ohPHRqNnUmCno5JkpnX2NkPk1uYTVXKyM/M211VSt5X25vNDl5cWUxSnZiIW50X05f
MG9nNnZYZFBvYV84bD5ZdlV5aUI7Jk4kYgp6R19CbSs1UnMwdGp8R25faXNATXYofkMoanRgJk91
bTF4Ul5seT5JMTVeQWR8RWRqdENxU2w0OXsrclZuUCEkd1QKejNxUX1AZHVyJXwhdXx5NWF2MFZ7
KkI5aCtpPm1wKWhFayY2aVE1P1FSdDwkV2I4KTJiSlZNME9zMDF8e3Q9bk57CnpuSTBsVHYhODlK
VShHKzw/SjdVK1JPMFB2aldabEZ0KnAlak9ZKGhDQn1PUGVMfTUwOW4+SE1qeSZ8QmRsfTg0Sgp6
NVo3dDtoV3Q5UCtWd14jai19bENsMGZNKCl0WGdYanA9ezxtX3BuOGF4WXIwQVVAVz4ya1JBUnM+
JmFJST49JmYKemVeJnsxV2o+fEhQS1UzQ18zNTJjI2NFPTU+Q1QxdSQtYm5jWSpYTERKV2BYZEhv
Rk1DJW9PJnI+XyhAREhGXmphCnpRYyFUMkZqKlp7QVdaKDJuM0ptOTRUOWZgeVpBRiRiOz1CaTJG
ZG4xJEduR0FAa1gkTChAMW8jdW5XNnpfVXlNPgp6LX40O2UrdnVhZUU0Nig0PDwmUCVXdFdTcCN+
JDtxSElDaXozJjNFaXpySW13SjVqUnQjTT9qcWA8MiU3LTlJUCkKenE0YnxHeTtQNnZ3TDZfPW16
LXc5cSs1UXhXT3F+SlJ9V0gqS3ZjI1BXdzhZMkc/UHlgO2U/R1g4TDBgdyFlNCpVCnpROTcrdEhm
T213alFmfCQrWkJPO0NGKU0mYlBaUUM1WiVONHY+ZUk/JTRUKFctQ3A9MW5lVGlZZGlDTD5KP3Q4
aAp6fDVlNkFJfjgqY21WVFVfdEUwKmFTJURYN0I7bVplVDUlVlQ8PEtpRSpmQFYjcHhAJE5oPk4x
UDRCc0xIZFF8akgKeihNRTl7ZjI1RDhlZGJEOThPYzN5YlZ+SmNLfHNKb0tVTiYqLTdKOSVzPUda
IW15P2NmP1BnYFJVTlJ9KVVTNkF6CnpJOChKRGl1c0ptQmJpVXVtfCR4VlN1dFpiYGgqIURLczxS
XiFudEFYKWUqdSVATDAxfEBNYGxuXjZxOW9KbFlWNgp6Y3FObk4yMld9WChlRyt2TjltKWA7bExj
Y3QmXmY8ZH1Ge2pgTCsyPzxeYmxkIyptUmxfKTA0eSlUez0qdmQre1IKenQydT5TeCtVNXcxNnlS
Tmh+Sl81eE93a1FGVUY9SzE5S301XkYxazc7cVZwSVY4UHRSX19nYDJ6TTNKZStsKiYxCno8Mk5k
UHdIQ1FHOVJZKnhhJnx5PHJgbk1hOUFmM0VWWUlMM2VjZTVJQyRrPzJNTVd8VDh9KmZhWF52KCFL
SWdgaAp6d1FpNFI8fUg8c1VZZSlKVjQhPVlZYEZHe2M1YHg/Jl4rS1BMZjw1S3g/TUs9QSFjfTtf
QSRMcU8qJjlLQHdPNnkKejREO2BOeXNxcyRHQDAoR2d6NylDMGxCOVdVUkxKOVIqfWZkS1ZiVzU7
Wm4qZWcyPy00ZCYweHYwcmFoJHY5LWRFCnp6MjZkWCpHYFBTc1lLWURqclVkTVlXdGJpRnNYNCUm
aSY9dTwwczg+UWZRI3lsQV4oSG4+N0VGWFgrP19gQVd0bwp6Z0hVO1RmI0kkcXpkbE1HYT8/QEo5
Y15KU0A5dnN0UUZ6ZmNHP2VyYnYteSVhe08rIUc5JSs1aUV8MjhUVUY/ZHgKenNFI19SYmJGIyE0
YHBnclFDKj4wVml4d1l3aTJOYlIpeX5HaTNANFg9PmBpYW4hX0BLcnw3ZCsxPyErLWZJb0JjCnpG
dygmRG5JciNTMlk0M2B3TGdINzB6R3tWLT91fGctQCRiK15tR2pOOFQ5bmF6YWFvWnBYZE1pWEZf
MHg9KEdSVwp6NVE0KSR1entAYlBvJShCXytSQVU4LVdLcVMxSDl6OE59TWhlRn49ZlJ4dlg2d3c9
dF5EMmZoeXNEIS1+cHRMNHEKencpa2VCaXA5fF9rLV5LdCFzR1YjM1ZsXkNqd2ZCckJhO0R2SFU5
KShiUW9WQ2glJHpLe2AhNTdEOHhSRylabnc9Cnp3fnBfb3dtSX0xT3hlRWVWN2F2Ul5zcz8laWVS
fFJKIUtSKG5afkJ6VCUqRFQ2UWJ8NWlOWEVheEJkTz9OU1JTZwp6YFArViZhVnxrcFlTWDVlczdx
WXd2PzB9RVM8RFVgckZlV2UraTBtRmF6alAoWWRqWS1SJn43aVQxaUpFbWVhWjQKemkyZ0BHTSlx
VkdCMkYxJGlYbzFoMStQNWF0OVNHTGtAXlA0Jn0xXjBVXldHfWVjRG5hcjBFZ2dIM1pUS15rPnRu
CnpMZlRmRjEkWHtvbiRnVSg2WDlrfjg4RjBpOUdxWEozb3FyS043Rnd8dWd8QSVIOW5+LTVBdnso
XnYxTFBud1FIagp6RClObj1tTkErNj0oMWpDaXlkWF9iVDxrblFlLTJTY1I1I2gqXnIwNkh9bW58
RXZxYzxkWiUqVCh8dkdnMnVEQzcKeiZDN2pyTnxrPG16VUBZdEtBdT1HQmopd2NxJURgcCFWeWky
WX45Rn15YHJrdCtBQFVFYU82VnpLMUV9WGMrVWwyCnpfRyleZkx4LVAoPjJXeSslOCUkdyFnKF5R
dGhqaUJ3ZTNMaW4pfj1kNmJZclNNeCskOT9RSElIKjZTWXxzflpqeQp6OWYtRCRTSStYSTFPPlI2
MkhoTzRINnNTMDB+P295JSpFfDNxZzkzS2B9Z3paNFNZaSE1Wj1EfF84R305dFI2QlEKekhNM0xx
PlpXRUZyJGgkbDQ0ZU40dXteYWFqbktBT0l7bjQyLU9UXilJZEl5MEhBcjZuKXYzQD56T1lTfVVg
KzdhCnpXYXtPSj84d1lXVlcoU3l1REZmV1BzVDd4NE5CYEpiPj5ZV3gzZ1YlVVlrUX0tRStPVVNv
KlckQ2FndjVZMmdUIQp6SG1+PkV4bCk2P3l8eH0wK2xjQU9XS31fTFphMmMwVSZvclF4MGdKX1p3
PytuU1lUV09UJD91WSUwZk9jOUUrVzEKenYkJURxdV5hfExGX1dMYEVMXnJFNyF4SlE8a187YU1N
LVk1Pn4xV3B5S3tTTWo9fjkhWUwxckZaY2FOdnVGfGxYCno2bER2JW42Sn5FdDBUQkwxPilSJkJJ
NipEdlFtUFh4diNQKjNKRDlkQGF3dVNpJTNPYj5KNkwtc3wkOVMjOzRGWgp6O3A8VnZod0FZPFJN
OXFQbXh6RD4wIWxZNk9pcUd0RGUyUGZ0dE5xWSRJTms/PntAKEN0R2U5TURUJDt0U3NSN3oKekUt
MGZ1d2V8NnU/TVR2blote3NGVjwpPV5JWExoNnpDNEBrTjZkY1IpVFV3ZkxtQno+MTQhY3xIaHB3
QENRO21PCno5cmxQcSFCOSErTE9SUCpLc04jfEp5UTtzMEFZVTFRfTJaUk0oKHwjVmswZ2RJYUtP
OHpRazZFb089PDttMVlvPwp6IUB7UUs9alBnOUUxKk1fUkUpZWsreyl6amVDJiNmYkEqLVIxYTtm
S3B+Pn16Qn5YP3wlZ01ySj18dFVQVXVQZU0Kek5LdkV5Xzd4QT9tVzVrZWpnIz4mekU7TUdLek96
UChIS2AmUkowSSp4Y1VDU0VOPilHd1A2RUpve0t8TiVgN145CnpeUCNpUitHaHREbmJfRF4qRGBZ
OGMtYD5JJCFuIV41aWA4c1NFaks7WD1ucm5xTFFmKHVyRUV4NCN1QzdUKzNLSgp6c0U8I35PcEcl
bEl0RUlJSkNuNz8qJjlxSXYkVmRieFR0NyNQP3c7dEF7dmZvekNZa19Bc31GaFJ8NzVGYWprekcK
emRTYGo2d3d8QWl4PjZYejM4Z3pWdHRZd2dzbEBgKigkWDNvdEtIa3tyJj5FeHhRSlUjc2ppV3xB
NTZCWWBzP0VgCnowT2YoTTAkQ058b2hXbCY+JVBQSyN8V2JKP3BhS29jP3hCSSlxa1NTVjZVOFok
RGlsK1Z6fnFYNlAoM25CX303ZAp6OGZlM3JZdzJSJjZ8MEhFVz1tcGg8PzVwKFREVSFzITBrRnpN
eEZXTXUhM30kcE5vfjFtNEs8QktqKysqZmltTHEKenZNPWdJaj1acjtHdFhuY0VpS2lfSnM7Wjwt
cnYqeGJUMncmRTEkYik9RUtVeWJDLXJQPDFIbjNiPjd+SkRCVUMlCnp1UCEoPjdPXjhLUUNxPSUj
cUw+JlpkKGZ0VGVfM2tIOG80TV5VTXRGcGtgU3wjY1pjUXFfPyYtWmdmQTIlTHFlbQp6dUMwNm9R
YmdafVUhVlVhSTwzK3R6cSZmS1k/fDRWRjxjXnlHTGtyK05HZkYlNWwrPWxpVDRKLTZVdkYtbyNN
JUwKemItS0Y9b2thVEZ6QzJyQVRnbiE9NU1Pb2pYPz50fm4qWiN8PjZMY1hFM1JBUCNRU3gxbj1a
akM+THkkfEZMPF98CnprKDNlR2JlbSQpbDVYR15FSjkrcUxuR1o4MHRvfHBeSDVxRCFxSWFubGBW
NG8+PzIzeStESyR+Y2VpVTlhT0NNYgp6UV9ia0NYKV5RXnBJYStgTUc3fEEqYWBseWNVenAyJGJk
ITw3b2ElfXFDfllfeVZxemhKdkM7WkJfZ1JOPSQhc2cKelJ1RitldW5eN0R5am5sVmQ5VW54QV8k
TkRLWT4/bTJeTikrZmVZRkNrdFBFRTI4ISRqIXJPK19hJGFUcVB1Yj99CnooMDx9PGY2aTd7V2x3
ZExlK0xrYGVgczxqKlJRJUprUDJ9IW8/RVokTHxqTlQhSGs5MVpYUiYqMV80IUFUKylmKAp6VztX
Si1FXiU2JE85dn1GYHcxZFk0PkQ2WEdwQTU5aG9vakEqX2hAe1M7Py1pI3poU0crdUopPS1Ndil5
biFyTl8KeklAbU1QQlJecXRrZmhBOGdASipncTVRX2lNeUdYdmBzUkRaNW5MLVUrdWMpaiEwbU56
TkpifXl1YDEzMEJ6cEJrCnpre1Y1e3ZBcTFMMXNgcT1gWThUKUMmMWE4VD0kJX54SHZXSHo/RlB2
WUhtRGRSO2xyQXorezhUa2BrcUg4cHJDJQp6WUozWD9nM1EkJkJVREg1N3dBOXdgSClgTCl0TiU2
TFNKNyRNNn4maHN0blpgb3owSTc7R1NjRlgmZUF8bER4KWkKejAmZV5JRjNjKXtaUjRGRTtNPVRg
Kzt9bjF4JnE5aU11cSU8WEVmQGxURX5nKzRffGUzb1B9fXtrcjg0V1hVVGFoCnpjUVpwZUZRczhk
VUFUfSFOZTNCZ0cxTVF4VXFaOW92Sz9Nb0coKTMtWWlYPT9BZWB9cSE4TGR6YkM7dC08WW5+Sgp6
OHd5ZEw9JmY3VnU5ZGhBbVhyZ0NndE9objtaMGo1ZXRJRzg5fjtFcFckbjckdzxqNEE0bGEwbmk5
RE8yOWA5dzwKent9ODBUQUF2QWtrUyN0eChkbjQrKVUtXkFQc0U4b2pNcEREUFNKNXEmbWFjI3Vz
NGR5a2cpViZodEFydnRZbTRHCnpoI3hLTVIkQSNzdFYjM0RJblU5TmhFdXp3VyFoZ1E8T2N0Pk4w
WF85IVE8bk1LbVMrRiNAZ0UyQjR8KV4tTEpkYwp6UTxpNDd5X3oqfnhXM1QpTj5rXyhkRUYxWE57
RVB1SG93MF9iSXYhYUlsc08yNk01R2lsR2NyZVZ7JElXMnpTWm4KemwrKkw2SGljem5HKnN6RVd5
OT1hT1ZSeWRaVElxe0lDP21tSlM9b28qPGYoRkx2SiR6WWxZQUVIJmd1alA5O0prCnpASmVKckxO
M0IjQyNJOUVXckk2Z0B6ayRwQkAoWDFOSik4VHZhVEhUelBpaj08dTNzOUhAbFR3dVJZcXxWYDs8
ewp6dnJwPT1CcXNPPEdqZTY2OSo7QHUjeHU1P0dKfVRYKTNEb19hKDRAKTxHbmtSeSpKUDR0cnEl
T0J0M1g/RDhJNTIKejh9RXNfVmFQSUxZJmtlc3ZZKm1KSV5VQEBmYSZpX3RffV9oJUdUQzNBYi04
cEg8YWxyUG1KcWN7LW9NQkdMbCs/CnpBfk9zNT84LVlVZV5waWFiQyNCcm9gTCEkXk8zYzNUOG9U
QXFHVUB7MDdVM2tGIUM4KV4kdVRMWTN1THA/SHh5Zgp6bGpeQS07RzFBRHNubUNXc1hobFFMNylG
Q0hYRGs2NmFtX2NvTGtsKDd7K0M+OEQrJFdgO19+aClQci0wPXZecCMKejM8ZWs/eH1yaHkqO2Vt
UGJNIT0kNXdaOFRFPnpXWDZtTTw1VXNGWG1FPDBQTigzRTF2Wjh+V2F7TFlXb2RGZW9XCnpoYjIr
JDlecD9CYEV8Vlg8UHx3KHJkcGo+QndaemlCMT5vcDBWNns/aWEoe31ESDU9QV5wRlVJXjs2NUVf
amVvbQp6YlBmJUBDVDxwTE1he2pfeTU4X2M0KksyczhUaHpmRHFgU2Vaa3orN2lOTT5hJFV8NU5p
WnE/X0RsMDQ3U1FCIU4KemoqaH5kbCpTYHZRTH5UMkgrdDE7KExEcWtsOHY9VzdFVX1tOXo1Smc+
QjEyPThYQGtZSzV6WD0qaiYlWk5LYTN2CnpvOGNTfDFeOGNfaiY2Tnc4NXlhUThGbWtmbktTVil6
c3Y9bGJWNE1RTVkxak47UGlTRGhtNUR5bWkxJnRvT2ojbQp6SUgxU05TSE88YkZrRGxqTlhmRmg3
TER2JjhfckpBOTRANlUpXnFHZzRHUll+Xk1nRCpFakEwfChmb0FIOUUwSSMKejFwUFF2PEJIJmBt
Rkw1WG1mO3MyRVFNODE1MVg3ZSEqUk0ye2YxYHAjeztRLXZ6PWpQbEN7SkZwVCpSMkF2MldXCnpL
empQVWd9TDY9bSlsWk9kKFQ0dVVqU2stbTV0Pzw3X3BMY0AhdDclcmlPIXFnVSlOOSRfPyotP0xT
YEEkUjJaMgp6NmpXcX1GVS1wdWRSO2Q/bktrO2M7Z25fbEclS3pDUFNrTWZvQHRGNGRTd3N3WkYh
OFFPfHApQXkwZyk/Rj8qO0MKek5nNWEhbjVqbCpDbWxxLVplT1ktKV4kcHZmPDs3QGNWZENwU1E9
fWxyPUVLZSsmaTQjcjstZXEtbj0lZlRXMT1ECnpMSjc3ekxEcTwjYypSK1E2a1BycyhtSyEmZWxR
dGpUTjV9PVZ4dUtMNEFhQz4qR2luVDVATWR4cnd3QUI4dFdmdQp6UnE3M09hWUUoZiMkfjI8R00x
VFo+fHgjRWlSREs2WDV+MXFCYzsoQ2dYZntISTY1WSZyRU9TU0dhbm5kVyNecXQKeldAUVkhWEs9
KytuXzV4Sl9kclNYKX5eKHIwN3NlNURoIzw2KXRJQzU1P0ZuYj1mdiVxYSpxZDU/IU81VF9MWnlf
CnpDKm5QaVRYZ2s9Xkc1UyRlSHM2KilMdWBMOGwqRC02am94PWY3I3Q+U2R7QDA9aSh6WGh7ZmlE
NCE4JDxTKigmKAp6IyU5SUM2a2RySXNAIX1fI0hUJlE+YkJEI0BPYWdKbHU1cWl3K35PJntUbFE0
K1k0ekpWKCFVfnpgJSkyT0Z+TnEKenVUTkV6YDNXUzAmKSpRQUczfnBCQDhTZEo+VT50TFdKNE5E
aTs2bkQ8PW9TKVJxJEh3OD1FUWglPCR6OyghNi0/CnpfQWReV3ZqYmg/RzhPTlVrRHB4R09Wb2FR
VDd5eUsre2YyMCl1KGF2dHRXT0MlI2xwb2RUbS01KTMwKVk+S05gbgp6S2I9T29gKWhLXl4oSkBk
bDE2R0J7ISFyYndnQ1VZOXVRfnNva0R3VVo1dlhHcSZIIUhvUSNRKkpRK24pT202WDUKejdWSjJC
P09xbmt6S3JQRThZYGE/bFZUMm4oPXpHWntvU21KQ3ZHV3RSdUE8K2FuOVlMamMtflcmVkt3Uldg
LWw7CnpQflJNQiR1PHhpRDBjR2hkZXVUd0djWHtLKVJ2VCVATmA9Zzl6fVlJP0E5WCZsZ1ZUaiEq
WTlHNXdZQDA1eEAzUQp6QGw7ZX5QaWpPJmsyKEotRDQkJHdJUzt3fmJ7cjVePkpmWkclYlAwOUY5
PkdTRnBPeXRzS3srZGB4VDdWK2F0ZykKemRKKmltZlVkUE9QXlV4TV8yTDdZaCFWUEA+RX1QfTVj
NHljVlhGaUZxamw8ZzU5eE5yNk45bWE8aUgqZislfXtxCnp4flUxXlV3Tm40Wj5ZcWM8UypmNClA
Mms8aHM1S0ItRlEmITs8QWRibyhQe3lhRyFsKTloSWFlS1ZXPGU2UzFYbQp6bipURGZhXys/azto
P0g0bXVvRXo1UkhafXl6YWdXVV5GM1lQNk8pbV9aX1dEPkJTRiF7UD9EYEhmbjEjRlNKd2QKelVD
cmdmbktzTVg8Mzx3Xnd5alQ8NkskLU82N30tNGxZM1JJWEJUTDBpQXc9QWRhcjJFa0NHan1tJkZh
ckA7O2RZCno8KUNSPG03RyFCTUQ2JH4+ISYkP1dTUVo3SzZFN0VHdHBOJV5YYmRlJkwqMShZd3ky
NE9ASE05JW9KZjR4PGtUcAp6SVVvcX5FKkUtcnlyZCNkR2NIKj5MPUxVfDl5RVEkMj9kYzRWTXk1
MSgqdUZVaCFKS1JuNnVSbjV1NU1rZkxIZ0oKeiFEdzlvRGxSOUl1SHNUcVUyVSplYFREYUlxPXwq
NnRVX2d7WHUyKH5eTztRfGNLZiZSKEhhNzlXSW0wdiYwdDZFCnotLTZ0JEckRnxaUW9KJFpLLUp+
KncqOV99JnI8QTdxRWRKWU11QTxjbiVCSXh0e2BWNkxNKm10OS1TOXo+Jk1ofgp6YDZEYUs+fiFH
YituMU5BRSU3PnwxJD9re0IhRm9gP092dyRge2hzSihgPD5ncCZfUjBiQnl1QFA9VyR5UFNqfH0K
elRkZHpRMzwjdllkMH5aSj59flZ2dUIjcGAkNkF3U20/I1hEP2Mrajw/TUtoVilraGBSMTQhS2Nf
I0E/bUtreUVnCnpOd1goSzV7RzI8cTgyflp0X0JkKG9RPH5MdmRlb0M8NGlUPXZNZG5fPXwoZCNN
bT52VDw5VHdmQiVvTERfSFZWJAp6bTROfGM8QipzbUV8SFJSJjxeeXM0fH5feVc8Ym02M0UyNV9M
QkskWDxmaSRAdTA2Q2dPUVRLLXVVbX51Q2Y7JGEKekF5PzFGPm95cGRROHhQMlkpfmtDKTdFYDFo
WmtXcThTTDModkREU0QocjBOeUdVdT1MMyZxMXQmKF96YCUxYlVOCnpSTFdqalJgekNIVTgmIS0o
aT5ASXR8RVR2Yms1ZXp1b0ZvPW5ZZi0+NlpVeyFlVURNVnRxeGdDPTNwcWpxRV85Qgp6eit+fDE8
V3B3JkRHakE7OEhTUXNuM3ZAOTFMM0R3eS1JSShhX0xJRUhZJlorMGlsWWk3bmMtKlpMY1hNcUJ+
dk8Kej0wciY/JFZndW9AfVRSIz9FZ19ULUNaZHZGNzk0X3A8MDF1I3B3c298QS1ecFJhKnMmeEp1
cTs2TkUoZjRTIXxWCnomRmtsdGdLdTM8ZGhKVHFOJFJORnJrOWtLX0l4fkkpJU9lSTU1T3E1Tjlo
JmdDZEl8WSohSmFiPUtCallwan43VAp6OVY0Kk52UlBld218d05FTiZYI0lAU0A0JHpWdjx2a2Yw
Mz5qY3x5ZztEMm8rNit6a3xTVnlvJmM1ZHxIVzN2a1kKenBuPDNIa3JhXjdRTW1FMnVyUXljJkNy
UCh5dEt4JGBKc2AzYVdaOyo5bC1efmZLPGZVb2xwUmVRcWtGO3pXRTVnCno2e2AqfUM8RzZAUGhz
fXYjcGhMNVNDaCNnQXhTbURLV2M8Sjl7Yig7NEQ9VzlgUkEkdUhwNCUrRTNnXjx4dUpzMQpmQFBF
O3pvUn1EU096dlYlVHVke2h4eT9DO3BHKGhye1B6QzxMRElzOwoKbGl0ZXJhbCAwCkhjbVY/ZDAw
MDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlX2ljb24ucG5nIGIvYXBwL3Jl
cy9zdGVhbS9lY2xpcHNlX2ljb24ucG5nCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAuLmExMzVjNTRlMTQ5ZWFhOTBiNjEw
YTY5YzhmOWJmNmRlYjA2YzBlNjcKR0lUIGJpbmFyeSBwYXRjaApsaXRlcmFsIDE1ODI1CnpjbVg5
X1dtc0VIKCs9KHFNVEAoO3lGPjkoK0AqTU40VWl4JDQjbkxJNmZmQFgjaTYqbnlJYzczeXgqVEJD
KWJ8Ywp6Kl9uSDBYR2JENSlEJHBLTmwqYSowRVV2SHRRRyhPMU57akRLdF9hcThNKiFiM0lLP3VE
YWxHe2AoJk1VXyt9WF4Kel8/RW5EJmsxPi03YEl1Q3EhNWxvd1hZMkdCZCFwd0lQI21GNjRmRSNC
NjVkMTtpbW47QWQmJWRDYVFudnJHQEVACnpxZWJUbGxebnlSPFQ4c1ViY3wtSlBHQjJwVj1abUNe
THViRlRpPjhLU1QqX2V0I2EtNzlDJmhkVXtKWnpXYXVybAp6O29OYUlafEVFfXZ+JVNuTioqX35W
QExIKk1JeSpmOXd2TlBNRk1NKk90dXVxbS1oX2VBM2g+dzk8fiUrdUhGdXgKelB7dzEoNGNRbW8h
aUQ3VUBJM3I3bCZiMCRkJSRzVjx+Sj5ZNGdXZ29DK3lZNzN1JlV6ZTx5ZD8hO1ZYfWJad3B8Cnpe
TTZkTFBpekB5SlV7MV9TRmlCSVNVSmt+UEUxKkk2RTkzcDw1Y1JgNihqIVpSVXNPMzZeJm96OCk7
enRaeXJ1MAp6NEQkKE9EY09IJUlQM2k5MHpwKTwrbD8waUN4JlI+LXNqZkp6MFFeY2x2fWpMc3wt
cTYlWExeaj9KJUMjeH5AODkKeipHRE9hRD44PHN4OUQhQ1MyOEJhbGAxazM1TFpVaEJPfkB3a2Az
P2tiaEpwWCV1REJBelY/MWMlVzF4eGk0eTRBCnpWez1+bTclRFh+PXloN25gM29tbCVVJig1JDU4
O19pNj5CKysyU2pFdEwlYH5ASDgyQ1R+e3RwMGxLQW8zd1MlZwp6I0tPIXJGNGZqbXhicComNEpg
QHwzaVUrRCRqV35NQVA9d2QqaVVMbz1GOCpmQ3l9KCs2LV50TTJaSmUqayRLV0IKeiNCKjJ2UDB1
fVBPdCRCRW1RKUp1UkgrQnZDdVlgajV4Q095e0JBK24tS1MrdllhbT44PE8yXlhVSTNERzFXJVVW
Cno1NSsrQl9vWEVROW1VUUVJaUhqVnckdFlmKnpufFY8XyhOP1ZzcigrRCtoa19TMkp0dSlSe2N9
TVlVYC1mclZVdgp6IXdhNCN1fHppfk4qTWltOyZnVHZIKWhFRDkqZF9neEhTWk5AJj51Kl4welhv
UU1SMSgqNn1qJXQ7a09NKVVpc2sKenJ8ITd0TFJOe3ItO1FIWHlkNzV7S2VvMkVffnpgdCRaM1l3
dkUjSTlzV0l7S0VBZ3pEQiRsKWdJaVJjMmF2P2JKCnpuaUtzVC0jPEooXzRrPEdyanJuVUZLQnB3
RS1gKGI0Sihfby0/NzF7OCQ8cFlyOGtJVERxREwyVHpJS2t7Uyl9cwp6X1ZSR3JRZnRJflZCZiYz
YnAyKENpe3sxQTdtX25DdVNrUHshKTN0NG96RDduRllWTTVqTD8raGMwSUUzYz5WdEgKekFmY2w/
SCM7OypMWChDOFlhZ2wqdURFYVB7UWg+cnw4NE9XKGtUWEhYSEZnTWNOTnZTXzR9R3pIc21mam1A
Yjc0Cnp6bCg8T2ZpPjtuQnZHZ0dgSzIwa0xoPTVFWCR+MWh6VW5SQWYqIS1uRGtwZEg7SGlVaiF8
bHk3UDdJPlo9NngzRQp6VEJfWUUjR3VTbExQV1JANm1eZT93K28mKFhsUThRYV8pSjNuYV4/XmUx
QVJ3Sj8ocTU+fllpNWI2UTY5cnNKansKeldedyZjNHx2QG5kXzUtZ2hRd3ZCRz98SlN2MkpKS1JX
QHVZME0qXk12Zk9QZUolSz14czhuYEgrJFdCZit1N1d3CnpvNV4+Mlc5NilQK2Y3XjI/JjA0WSlX
KiZ9Y1BBM0J4M2xWUlM1d18pUkkhJVIxfGtWaEBrNnJ9ZihJMy0hNVdeUAp6LWR9V2J7Izx8QmNw
UW0/UjRBMGZlNUU4MiVzfU1pSl9nK2VQO3tRXmRQOXlteXc0WVh5XjZHPz81dlp1QX0oITIKeip8
eDcjWGlCJGJgeT1yWkNsQj1OZVdwVlFQMkh9LS1kfip8JE5VYSktKntjPihZcGFVdmMwNHhGRill
RzF6T0F3CnpBdzQ2eCU/cChgK2BJZCRtczN2JiswXnFKdWRVc0VSdWtKKD98U1JJZlRVfE5RX3Fj
Z05DWHZmUDBvWWdvK2Qkbwp6VzYyeUh1ZlJDKitlNGZDKTF5JW8hT0RpN3NFeWZIIz54aVEmRkFO
NVpZK3UwT1BlYWNrLWVyPndeMjQwI2VSdmkKej1kNXA2I05GJCEpOU5OM0MhcDdaZyhsfDxGfV9H
QGlEUkpYM3Z9STc2clFnbUdqeWNZSzZma3x0flozPUl0a08pCno3MHJhQGVtOEtQaSNkWjlKUmpF
R0ZMYj54bWlaPGxedyFjJmZUQjQ4RjU0QTQlZEMzIUV8YmVxXlBNaiY/fml2Tgp6X2p4ciNIOFd2
IU50bk96TEJKSyNqYU82aCpLcyh8JUVrc15aPD1pRyZgdnImUEVCfVBqXz1LfU98e3MyITI1eTcK
eiMmYnJAai01VkxubXdFYjdgMU98JkYyaWAwKDElUzFjYEJTZzY5cUpaRjRzdGRAeG0oY1k3bjtU
ZyUlRkN4am09CnpCcD8lNW9lI1IyX15LQF5EJUpeN0Z3NXxSOVk9UXlVQ3dLN0MhTUBneCMxS1hm
cEdfVU4ofXxjXldYQTc7SU1oSQp6KkhpJSRWQmJwIXJBemRNbm4lQSU1c2E7NmJpZklRYktwV042
OFpCPFBmJWI8T3dLVz1aXnc/Vm88RX19MjxCbikKej9GOTE3Q2VWSWxKVi1SayRfb2hUP0w1Zjcy
eigyOXNDPkVaP2dxfitLZCQrYVBzU0o0JiliYHNOc19sLV5sKV9qCnpIdiYjc1JlI19WaHFQTiZW
Q0AkU2FDWWNoPiphIz9gcHE0cnZyfm9TOShWOzV7VHdvNUZ1VHlpOzY5b0M7UXYrfQp6N2pQYHl6
MjJ7P1BfYVFuUD5RJX0/N2h9LStTUFItKTN5NUNpJmllelp9VEZTVzAjai1ZMFZQNV5xUzVBSWtN
SUAKel9NR0Y3e3Awd2syeFlqa1klaHpjK21tOzA7QnskdnA8dTFELTQ1RWJTazkzbzYqV0lIdGI0
QiMhfFUjV191RG13CnotT3tDYkg5RENSYT13YiREbkBuTko8WClWYHxJNEBAMHszSWxVTVN8VFN+
Xzc1ZTJPUVRUZzcmb20mfFc1KkU+fQp6V0lkOUImNF90MDU3U3RJa0ZfeXomZDtfaitIUThmKWxo
K2N0KUZreldeUmNnNiRtKDBoZGlwWUJkbl4xbUcxU3EKeiN0eW1+V14pS1YxZEV2WkspJjw5eVZB
eDhpSUdvRU9YN35SbmJ2R2l3PUp4X1hjaGdfKmJ4YzRiX25pIUVjdD5CCnplfndXZGMmNlplelV1
amR6QH1rLTVENVooTDU4VSkrdWR0bkJITn5ZaT84fTY5QSN8QyQmb1pVNy0+OHxjQTNOXwp6N3Qr
ciNGTWp1TG1WI0I2UypeJCtrVVp8LWtjIXFKV0tWZk8+fjhuLWBgS3JUbXchPTtJJmhkdXZ0ZVk3
UUhxWkAKemg5S1hZJjJCU3NHMDFUQjE1bEpGTGAhKURgVjZfeC1TRGFsQ3YlZXBGLW4qTFVROXZu
Iz9GZzFsQEgwVF96VzBnCnp1YV81QlY/P09kK2wqYyFqZHp7TFladnx4QypUV0w8aDQqdGVwcC1I
Pm9KTUAlUiZtSzReZlo5OCQwUEFaN1lsUAp6JGlCWFgjUURxMHkzdXxQM1cqJVU4VVhCbTZvOCFI
MGxuX0JGQV9vP3tUcChKY3Rra29nJStBaEY2MXUhWiR6cVMKelJCXzEwdSpqb2ZjOygrdWkoQGp5
SEpEUmg1MX50USpVeEopQztNemlGbzt1OT50b0txVi01bSV5STxDeWEmKnllCnpBOTYxJEBjdVc5
S2V8cnNgUT4/YF5DSjdnN2E7PE1PaylHZDV9K25LVz1ZRTUtZSR5SjdAYWQrSHpyQ3grMFImTAp6
Kyt5X2c/RllzTVp1fXQzdWFgWVpzRjBzYmIwTSE4b3lLanw7WDZjb3IyYW1sYitgel52NmxDej5q
NDkle2BYTk8KenVHcEkwRnNVI05eUSllZFZnZjEzZCN1WChTNmZ7fUpjZ1EjKX11dms9ZG89VWZy
VF5Bbnl4UWN1PUlRWW40KWZkCnpobjBtS1UmelZ2OXJGbXpuKXYmeyl0RjlfXnFmNmtxd350V3Ur
MTRebDIoIVNDPzJaISU7bn4rOXBjczcxP1lXdwp6WWIqYkFIWGd7TGRXaCNgZFAwYnBvWlJGbE5h
RDVJZk4xVkk2ZjVWSFIzSV8qVTB0bF4+RGEhZ0VKPGZKUCVWOUUKek42ME5ucl9yRll0UiFka204
NkpJO05xWUxqfDNkZm1+Ymk0V3dWZztYLTgxNDQtX31WdiFiYjckezR2PT1sKVBNCnp1fW42aXlk
TF9USnB+WWRKNXB4PnxJaCEzPktvdW09I2AqPUsraC1tdiNkZzFCaGowditfIUNKcVBiZ2Z0Z09S
ewp6T3leRjA3fTRrOUs5MTRfYCtWaFA+PSkkam9wZSZocU5NV3E8OC04WHV9ZlUmJn4rOTV2TTNh
RXhWTl9oY31ANlAKejU2Km4zKChvSk0maz4pVmgpbHZHVnROdGVhbE9ZQ0hnZ0lKZE5la0Mqam93
azY/STF+TkB8P3Y3VWNCdEF7IylVCnpBQXdWMEs2TTdZdFZFUzFBS1Rsb0p6aGZMPC1xOGBtYU9i
fipWSzdlYDhgcTBtSUJWIT5jI25lYXolSHAoMnJGNwp6Mj9gamNCJn5taTIxQ15zazlTSCg4eEpA
KXZkTGk3Sm08LSgjNm1fYiM9WlYoZlJDczwjJjwzRE5RO2dfPzspbWMKemp4QEBJKy03X3xzVEx6
NF9FXl44ZDt5WiVGO1I+PDNXc05FU1pYRXktJlk0eHVkbWA9bVNlZCZgcTcoP1ItTyQ7CnohdDhj
T2JyJi05K3lGdkVzdkBsO3E2N2J7NElAZFdXVzY+bSUzIT02e1V+PSNobVo0ZzQ5Y1gxKH1RYCoo
c3R2cgp6NGFVXkw7aFJ9OVMpVnsqYSkzZlUxQllsWCM+IzFCVXopVCVKc1lNfT1Gd25FJUdtN3lv
dHR9cDBEQHdOMzZfY2YKemBTKHc8e2tuaCZZMjJRMnRFTHA+M0U9YGs+YyRWMj11JClwPDltbjQ9
ZngjJGlCKG5YIXBrQ3U9WkFUUGxgKyFkCno+VzF0Sns5YHsrZGkkfHdIakx3RjNLJEVGRHooYVZo
P3JBfG1AIz1vampVWDNlK0M3Pyt9fm5wUk8qeH1hR0NvRQp6RHR6KlpNTzA+QHF0LTUpRTdCQz5S
eFkpb0NCajJmeGooWXJWTGJsOGthc0JwdSEre1pfYC19YU82UGojbXhMXmkKekVROShUbVZ3TSZi
VHBOSHVpMUszRm1RPmhCQ1FMSSY7cENiPExrI1FiUGFwd21pfTktJGVAeTJnU249fSRTVGpeCnpT
R0E1Y1hXM2BHUGFwSEUyPFh2QVowYkROXjtIeXhsJnBBJlMlWi1VNDtWanVUREA2JFgrRnNUQktM
Ny1vQTZmUQp6Z0Y0MUFsVy1YcDE8enNLQjwoSH5xSXRqYHtXaGJ8Y1QwPVE+Xj1GZnNHSElHKmgl
eDAodkVDJWVqaGNicnE/SHEKejc7PVY+Y1hadDVCZyp5YXU2PChkRjBBdyRDRyplQ24mSUV6KDhi
JTVSWWUtejVBRiNVbns1fn0hPTlKNCRnQipsCnopQTl7c1RJKnlkYTdEdFIkdkRlI28yRH1+TlR1
PTJxS2g+Y3IpSzk9KXg4REs0a2l5NF9lUG9LJUYqWms/JFNvZAp6bzdXSDhYM0h9JF5UOWhLQGBP
PCR5T01jVm58NnQjQzZTT2diREcyZERReXl7cFlWRVE+S0BCV2w0ZU5gPz0lYEAKek4/VFlPSyhO
VWt8MT5FWTZ7VGp9Y097MFZoaSEhdFg/O2xnIXpSfmU9LXozeV45fHZBPHEwPEt7PjtxeW94TzJr
CnpeamAlK08mKl9aOz1+QG9HNyZscSV1ZUY+ODJKMmZ2akg1MWwpdjQ4dyYobEozT0YoWUIqcjQt
VjZhd1kjdnxnJAp6NFE5UjR3P1M7JTgyT092aCgyT1R4K2spZz42SH55d09jUj4yNHlzTE9rI0tE
IT9ZWXJqRnZ7fUxoMWE4aHF1Uk4KeiFtUWQzMFl+ZjQpTkVKJkFANH5CLU85ZEx2Q0hBdns8aXgr
ekxWX1ZSLVZ6Sns/SzJzSHhadklRQ1RhUkRVIXM8CnpLaUtlZ3k7V1RGMDItPjctLWA/ZD1KTjdQ
bHRmJlNCUlgoZCRQSSE4XjFSbnxgNiRRQFJGKCtgTEYoaz5WKHxTZgp6b1k0Zyt5NFVvKTtEbTQt
cyQySiMhak5lYW9QNTNWJWBEM351RikzMXZuYiFRREFWMnlPUCF5a15BVX09MT59WmQKenEob209
JXB8JUYxNSRGJmVSNCMrb1VET0ckTytNWmk3UTdrTTF3YlJpeD90JFh8UHdyJjBTbXk5flcoVkJR
Iz07Cnp3Rnp1X15TUGAtZW9oaDkmbWJBYS1qWG98aGxncXNrKztNQWwxUnlWNmQ4SFdLTiNqUnUj
X1dXTyt+NVNGMkt7aAp6KiZuVW1QOWApT2V3OVlAYV5PZ0FCYlU2eHBxZUFXeDtAKSRUZ2xsREd0
OU5QKFZ6Jlk7ZWAyNERPPm1fVmRCWmsKej51aWxBZjwmPHBqP14tVm5sI2koUldYbEdYfFRgS19P
byhFQ3QqX1EhVT4rKi1vcFooJWtGLTxMRytBWlhwbk14CnpKRXFUX3s9cnBqeHlpXyRPfEFsRTxs
b3tGVnhOOFM8eHgqPHZZV2EhIT4xdmVnYDMxbV8wTUhycmItVjlQI01eWAp6dytAQ0c8flpSUHEr
M2kxM3khVCtlIyNAanszWSM0YS0rbX1reXxaUHcxa0tsUnBKNzRhfDFDaUlgOzN7QTFtRFIKejNg
IW1zPCZQJkZpXnxDaGdEQ0ZBaGY/eyl5UiRfYSY3NCZEJEVJPmRjNUZqJC0zPUtyY3grYDZeMHtf
SHE2TEJyCnohdig7RlZDdGk0eSRJPzh6d0ZkKDR7aSNkR3RjKFotbCNtQ2xFPzFDZjROSzJLLVMk
NUBjWmY9RWE8S08/YlVJbQp6RT9uP2gzZWdFJj9XP0plMU9hYX1XaTN+SDFDOUpvRXxAQGomSkd7
QXc2RD14e20zJFZ4RnhyJnlFNF9qQUQjVU4KeiR8O2VWQjx8dG9SM3tUaz1oOVFoWnhwUXNLPStG
c3tzJjcjSFM9MS1SKz9hZm88PVl0Ml9GTG4mMlI/VEthRmxgCnpGdGVMPzMmU2tLSHV8fm1qPk1f
cEBnbWh8O0g5YzlDfShkLTE5K0BvN1UkSDlmaipsISR3TEoxZTtuV1RHPXVsUgp6cWdWTThpXm1x
diUrUkI+IVc8cTclNSZCeU4/SG1sNFBfdXJubmdRfDNZLUN4cXdzTjskQ0MwbE5WYjQwPGRiUlMK
ejhITHFqVl9TYChIP0ZPIUU+SntiPHNMbSgmbHs8MD9HODRiUXBTKXpqOXtVNW48N2VDS3A/cjAj
Rk8raHZiJllhCnpybTdrMDYoWipWeXo9TEk5M2Q5fT1MRnFyaChLcUElTjRCaGkyemxjTGAwPnct
NlNGN084OSU9eVZMOTNrQyV2bgp6PjcwPzBVZ3U2Qk5QS310e3sqKS0lViVWcy1NJExiPj5PJCtW
S31KWVhDZmc2JCNvKEpIeGt0eUBvMSpMMWIxODEKemVOQWd7RF8rfnQxI0tONk5NNm5kMGJNUTBL
eU9EWCFtbElEdnE+V3pyTjZrPzcjQUc9UlRoYVEtbjBaVW5Nb2pTCnp2Y089ZmFBV2RHTCRyIXxN
UmFtVVl9VEtGOUBZQSlQYV84fFNrQUpfKSsrU0JYb2ZGaVJJelVJVXFEaXpOQFlYKAp6eFNLNXFS
bFlWWjJEOzl0ZFRZMWM7SGVBQVJnUmExJVV3aURBRk0/UlJPfXVgeGREQT83WFBqN14yYWBiRWBx
a2EKenNPYDc3LXJ8RWw2QTl5QVliTElTOV5TSUxSeGJedTMrPlEmIzgpTCROYSZtZnswTDRHPTVW
YEJPWW1GKVp8Qn5xCnpuKzt0UXdDTlhFMUQrfTBeJiQ2ajMrX3YjQ0pMJm9TMEI1KzZNOSp8c1Qk
SWM9R2NHVmMpMyU1Smh+eGV2YnhUQAp6RVFIfGFmdDhKaGdjWUU0LWU8R2laJUpOK09+UjFUMmhF
YE9eRyFJT1kma2dsdSN8TGU/YGIwPHhwZXUkQTVyeEYKeiRjVXh2K3dUY25jUlJySEhHOXhtdUtS
OVBieH1SVEIkTk1wZy1EbFVtVkJSNm9XbilZMlRsK2p3JipDJS1sKWNtCno4MXlkVVk7I3Bhc0l9
QXk9ZTwjPSpySDVFKUVhe1JhSkR7eShlKjRvTnF9VEt4Z1V7QF47OGxmWih7Yl9xPStWdwp6aEk3
emFLd1BtTWhLeVJDPkE4VHArU3M0V3dCX3BJdT0mdTQqfDJmQDlFY3VhVk5yTzUkLVA9Kmk2I0kh
ZXNRYyQKenY3Tk4pY3F+YUQ5UT9pSV94KVphUl4hRGxENVIoOU1JMWdGeCtCa1RnOFE8TnQ/fkVv
X2heJigqUVh5PUpLYHY3Cno9eWF3JmV0b3BRYUJ0c0EtNig5KkRQfGs/eHVUIztYbV5+XnJFOzVa
c3VNd201PHdkQGYyOzdOJUczYFFeZFJFUQp6Jn4mZC1IcldBd0lWJWp1dmp7eWBOb24pYHdsXnBl
QzwpUm9HP1VJZiU3dUUqNn1zV3MqPzthQFoxOX17TkskI2MKejBlOD8lKUYhK0tvTW9jUz1TVnE/
SGZxMGA1cUthSGxQYDlKa2Jkaj5aYWp6VCVLOyZsaU43VCFzP3otPGo9UlhRCno0IzFTbSEtdnox
VklnRWN4VHgrN1RLI1Q9Y1h6SWc4O0Y/fDlMejZqTzB2ITc0Rk5rUFEjJUNfek47anJmaTBWTAp6
ZExuTj1hSDZhTz9uNSpxXjk4cG5zLUZEIUF7UzwjVypZdjV7aXh+ayNqcDc9OVZ5QjVxY0Q3PDw3
OHQ9dXNRUmQKemElYUBmMV9reElYUktEb0BvWjR5Q1dhWXF5X1VBKSp0SW0wWH4hVn0+bzZmPipQ
bzktc08lYmsqa1ZsSkYhdXAzCnorTEE/QEJ0OE1ANCtiUGdISSM5ZCh4QzYmen5GNUhWUG9AYWBj
ejxRMWZgdUd1Y0omUk8yeUVLUGJ2Q2V5I1ByKwp6eTNIeiFMXjJPPDsjUzktYXtaRFQ5VmN2Rlk/
emRwPnxIfnJsfWYwPj5jX3JHWntTXkcrcVA+ZUdid0JLPWpNN2QKenJMdXtuPGw3P0BEdW1FRXVv
O2BqUWl5ZT5YSHY5QWBLSmpMR19LP3ZES04+PW0wOHFOfEk0cSZRTX4jTD9tJGttCnpfK3pzM2sp
ZGtLeE9+RUBTP0FOc0xTazA/MzdKMExySTgmTll5RSt6TFVGbHRrWUAhYTtqRGp4MFlUdyVDMX1W
agp6c2VvdWYkWSExVG9BYDt2QGpTT002T3FzcFpYckhKO0FXflEmI0huVWY4MVVFZHNiZE5LQzEl
WGEkUVMmcElTIWQKem81UHw0Zk43LU5iVH1PPkFAWUZSK1EtVjVTdyZTc3NMVUVXITh5OVhGVl9F
JTxEMW5PUDU1cGshejNwYmAmLVZfCnpsbWFYTyM7TW9CRkJHTl9LOWUoUXcteEhzV0R+O1RBbjVX
YDhhLXp+eXVWQ1cydmpgOyZXOy09NzJ3WHpLNzs0Xgp6VlZuVzlSQnRaJFMySj4+UGtvNyMjZF82
cjQ5bEB1MzIybklfXz08TVlGPGZVQk5eUWNrYlRBJjxzTjEyIWh5UkIKemo2OXNAQ0lxVG5AdFht
d1dGPWY2UDA2NyZZWUxSQ2huJHNSP182TShIMnVsSyVZb3BDSGYxc1M1U3VaQClIUGRBCnp5JDw/
KCszUUZLVEM+Pn1IPUBJclhlfUNzWkIlSl87YEBKcHtVSjVMc1ktRHhVT2R6PypCRmg9XyU0Qzlo
Q3NrdQp6cVgmR1JydUtIKT1lR1R1b0gtbEtTZWpkK0Q+eStVQy1kUDJldT1UZEhzQTxDO0NQcTUy
QlhFdj8qWXc+KTlmUH4Kems2WEpEPCErb3BUQENNOHRRPEc7Q15za2NgUHUwJXM9JU5NRT5TKy0/
JGxnODEpfFctUyhVbmN7NGI8OWgmX3JQCnozbzV5bkxBPEw4SU4rYUZaKClWUHNqTWJGY1NEdU1M
fn5Rb2tyWVpeaUY9O2l8MUg9IUxySUpgbVR1V0JoTk5KKgp6VjgjfWtoeDY4ZSYxTUhjM0QoU2Jz
MW5idDtOTk13aHtic3klb200VDlWd3VNT29jJklCZEpSPFQtZnd4cnhPc1QKel56TU82MzZ7UTMz
NkBMKWNVRFVybUdeaUYpJipIOGszJUtvKShVcHYoSEMzYHt7KFVEYFIhVz5mPkwrXjRBU3pYCno+
dmhqNih2PnlyKi1SK04hUW5zV1U8e1JJVWJfelgmN3Z2WkdQNEk4JT99SnQrYGtGSURJVU1rbkFC
YnB2RnExbwp6UyFrPVhLIX1MOXZJU0E0eCp1e2poVFVjMGNLem99S2JkNzBvXlBqPVZMQSVJVmRG
TXxQRWJtNGtMeHE0c1VXPUEKelA7fT8lPzdmUyYhQm9EYi0/RGBTR3NZU20tK2FxbzFFWFJqP1Mk
Nj5LZSs4Qj5AWF5Mc3ViPlgxZjxVa3dmM1MqCnpFTTF7dkopRl4hSnw9QUZOYWNxUTtEfiUkPFBE
MkBUbXYmRGpOTjRJd2VCJVlYQXtyJUQ5QlU1REgkR3QwdzU/Qgp6cX4tPWtZfVd2M3REVz5mVCFv
bUZtUjE0ez8tYVR4ZWlQNUp0QUU9KnlPYiFET2ZMayh3JlUmdFFofCtjTGEtWmEKek8/dykmQSl5
Wk9sTzElLUZhJnU/I3JSKSotPndxe1lkU0o1QE1EVm9OTTdFdTN3YVdFYlZWQWM0OVZ7K0l9UHY7
CnokWjhydz18aEViYTR3VTx6ZlBXIWk3bEo9KTlffjljTCQ/aVkwYk0zc2NvSyk/cnBIK1F+bnxY
Mmw0ZExjIXZQWgp6NShkMmhlMnUxKm9mWTkwdnp+LV9SU0FxTTJMN1hBK3JJZzBQVlkwbkFXQ0Vk
ZGkyfDkxfGdAI2hXPipNVHR1Xl4KelZuPDdNIX1lZj1DNFdEYy1OaCsyN2clNHMlU15HQUM0RDl3
YGBPI2BpKiZMdUd2Z2E/YmJDSyZQKkhBfXZ+TXA7CnpDd2tDPjF7N1FNakBEfXwoeklQTSEyNSlC
QSVyYz4+USRXRVVxNT9gMnYqKnw4QCljdTVePzdHTGR3dHZGezZFQQp6MEJkc1VtQWdLaVNOXjgj
ZSU+fHhSSCZoTXZoUmE+KzBFTWwhPCFNOUNFPzc0Iy1zRW9ROU1tUzlzSEIqcy1afTwKenxNTEto
Ym4tWCE+dn49X3F1RlpNdnY7ZEpkVk1yKU0pc18ocS1jSjAxPHpwS1IlaWRsZDZic3V0c1kyclFo
fjVnCnoqV0gzbDJHWEFvbWl3MVYobnZuYnN1VkUmKUU/aTdDb2MzPSNzPzJ3d15MbzZyfjJVOVQj
b1IyYzM/NkJuSFQ+ZAp6PTdBVVdRfSROYHQxMSYpPm52TCN5IXs7VHZeS0QhVD1odU4+MjJSRyhr
PH1TOTZ5XzRzWDc0K245QW5lPFFISXQKemAjNk9MWSp2e2l3SUpuNTFeNWIlPG04ZXBKQUVLNVBR
TzQmcDFOR0UmRlN9amNHUmRwI1NZPl5jcDh6XlZ+UHE+Cnp2YWkoQWQzLUI+PC1GJHEhWV94dD1W
KWRyeH1fYkdvI0FePlZoREpgbis7NVZmWTE4MzlAQWp5NEg7MntvdWFaegp6K0UxVU1CcHxpQ1dP
KHgldzlJX3UtNzRrLVBzOFRAIzlMfG0tNjl4SlFARXx9MXdhaiZhVipEPTdAfGNIQlBYaH0KejVM
S1c3ISVmI0Mwd05idHFIMjlwYzJXRFFZUis+NWZoc1N+O0wycCZkZFpgYjE4a2gwPjJARyYjeXBe
MmRFeXB8CnpKU2pEI2t4b2NRZjl+bUhOSmgrKDJ+KHEkc24yOWtKbEEqMmFycyNpZmFHYXRRNDdE
QGE8cyFNT3JjNGhoVjErZAp6I2dgc2tmWng0NWxXZkw9VXxLT0I7Q3J2SzElU0ErIyZRJXl7QU5I
U3lHO35yRkFqVURxUjM7NHJ8SkwqIzxtfmQKekhpOGtUSnAjMnFsND9xPTJfWVVnNnN6OSlWQ01k
RVQyK3lWSXg0aW8kYTgmRVA9YDlnUTMrU3U2bVF4RF5GbmBKCnp2cGtUJFpEWHl0SH1oVnxLe3JO
OGB9UVVoOyE+WGp0bVplUHt1THZZVkFwLTk/azhIdllhcWB7cXE+Qno5ZT98WAp6Ui1aMzJNbjVE
KiRKZSM5MDtaeD0wKEMxXjxpaHlTbzFmNDNIOUNIdGBxaXk0b3N4ND5rXm51VUstWVEpdnw8IWYK
eko5Y2JQaiErVWAhdHdkbEZVVzI/fEFRcW1nKn4qQmc4bXo3I2wtbSFtODleNj0hIXVJPzdeaExC
eUhedkpIPi1DCnpFK1dXVjJfcUA5TkhYK0BOQ3x2XikwUHhXME5BY1czSEQpfVl1NnB2VyRUZTBe
Y2MkeWsrSXgpaWQoT1ZkbkFwVQp6UkBPdzhXKnpZYCF8WEplXnh6QG4xN31EZz9ic2I3Y1NtUzZk
RmBxYUYrbExxTEskMG9SVjxDQ2M4SyUya3t4eFIKek0zQig8dlU9dDYwMWBQQSUzKS1SaiE8aS1e
dz0oYTJCKmVHYD1BXktQeyQ2cCowWTxMVWQ3JFFQNXNFPjZqQTZDCnpveER2VFc3KCk2cFE9YTlP
UVFaQEU/QzlqJX1XQSVfSiFiM2M5P2xRITRjKlhEY0o5eHU3eTcxcmQ4MDRqJmlLeQp6bSlfM1Bk
XlJXYys+Qi1DcGZ7fWpELXx1aGklSiM3OzZIUjkoVnlYNlQtakw7eGBSRVU3eUJeKXVwWEk9Vz5P
PXAKemRLWmBjRTJYV0hLXlZzZjBkbG42di1vOT5pfl5yKVphNVNmbUgze2l5dzk5NTI2LUwqPktW
Nmp7azdhMU82JX02CnpvLXBMPGE3Q0YtPmF3I1dVfT5DKSFYXlc/aXpWSUhCZTttSEtkaWNEbilL
P3NXYjNlXjcpYkBDPlhHJmFhTTx2TAp6XyR2PDkkTWZfWTk+RDxzI2FpT3VkMm5pdUMlcTlqKitG
OEdac3xtR158JndAaXZZP2M8YlFeMm5oaGlJWDVYQnoKejcpPEY3a2tXbzh1Qyg/bihjYzNuXlFq
biVHWDFRNytoS0dvWD5HandUYzxfRkJ3RUN4Xmg8YklQNyF+K25JN2JJCnojan5CdiYoaz5rU19O
QVdmZE5STT5HR05AYkY1QkFreHprckFuMVpFPEtNNUNLJlZGfHdtNHZjNitAQmRkb1p0bwp6aVho
Py05fDdUd3cleU9AOEIwdCp2TXckfnhPaks2TF5jPWN7M3UwTWFoeVg8V2RUb08mZUh7ZSl4LXVZ
TFhxSjEKeihGfj5oKFI1S2FpV2g/WF85MUdtKFA5VHQ0T2o3IWd6c2JeNCZAWG9BNm5IO1heWk9F
RkdTOCtiI0c+cUR3P0leCnp3JDg7fEA+aWtmPHcwQGB7XnhzU0xRanN0RyhjT2YhMShNZFZ9ZTBL
ZFNgNWpFPHt4diFHK28/Vy1FUzY0MUteZQp6SXojYV8wP3N4TVMwUVZtPHRLdWo3JnMyYkFoalEk
R0smUVZDSCFaJm1gMjlCTEF1U1Q0RSRmKGtITkZme1FYJEwKenhXOSNsVyptY31mR05LaTVQKWQ1
YWAwMmpefEU0JHBHZzY8SGdNMmMkJSQ0fil6YSVmTkRmQUhUQH1kO0dZJXgqCnpxIXp3JW5Yez0q
P0lLOEcoMVZoQiNPJV8wR1g8TlMmNS15fmNWUzNjRE9kdCFJVGA9Kj97QTtldX0oQi1LRkNTMgp6
TWQrWWImU0ZATnlKZW0+a2VfR3I+YmcreHMmPT5iN0B3QnVhdyo1R1ZFdD90NzxvXlk5NT5MfVUy
Z0dUPWVEcVUKenZ6THNiMCZBa0t6MExwKHgmaVJXNFBPbF9kcVpUfWg4K19CITleMnZAc2YpeTN0
VFJMWEY7aH5RWHt5cE4wMHBWCnpYdyVqQTY+c18kNW51KWAoK2d+fEF5d1FGbTRzQFdoamxsQWo/
fnFCZnFLRj1TN0gzZyU4VnNIeHp+MSRgcX4pPgp6P2hvfkQhYDF9az82ZzdgU3lBTnVsbnlkQFpO
QDVYXks8TFIwS0BqSG83cEVFVGxZO1FKeyZmNDBJWEkwKXs9N2sKejMhLTx0SztkVypjUUhOWDZZ
I24/WCoreUBUYDwtWEVuQi0lOWckeGBYKnh7K29ScUYrcHltbXk0ZFokNmN2Vz92CnpmUWp+ekJh
bTFMbFVhIXpzTTZTZDdacDQ3WSRyTEpoPnFMUyskQXZVI0JEJGk+cTNwTShwfi1CYmZmSlg/cjUy
bAp6VDZLNTIjLXM+Q0t6ZFU9eikmbD1wdGghdGtudXJrbXtCSGc5MHA8NXV8NTw9QDtkKkEhS2A4
UldpSFQhdklKdi0KelBVUVhKMThBcHp2bil6S2BDQGxHTnsja2ZRKnlSSWNLUkRQK1koWWlzVztz
RE18YyRKLX1vQ0ZQaDxnaUJ0MGc0CnpGeH0wZWQ5WUJLSWVrKkkoQzI0RHg4SH1qUlF7az0hZnJ8
alBaMyFkO2hqTjVudzJDK1dkVzJsdnRSe2Y7R143egp6JmF6NTRLfndlUFhaKjtyNyROYjZpTUV0
JT4zQGY7eUxLZT8hUWFodVlOUERkX2Nzen1yNGN6MWdXajhWPzNucTwKemlLbUFtS3gwd2AyMjRN
ayMjVFAkNHJqejdqNzw2dnJyansrdkJ6NFEyVDN9VlNyfUBldnByO0ZCUmZmVGNnVHBlCnowTF9y
aj1vSmdWaGA/Oz4zVjNScEJZdTV8JnI9NG0/P2dfaTB5dWk2Vnl3UWRaeXM2dTFwaHN7WGImQVEh
dm1NSwp6TCglQmBZeWIzY09DM2wtI2pkcDh7cXZOdS1FWkJrRGptZVMqTD9uZkpaOD10UypBQko/
RVNmNE9TJGh8PU5GeCsKekghZWN4RCVhSEw4UWUtRFc0OV9SV1pHT1J7Ry0zZTA1UihYeyFEaThJ
e1pGSyVvTkQ9PVQ0fDJMKnxLR0V0fk1PCnpPY1YpIyk2TUVweDYkYnJacHFFX05JJUMmWF4lQndv
JCRnKVNXMGU9Mm0xQU1aVjJzeGpNMDIhOGJjd3Fyej19Vwp6P0pSQ0c3Pl9OU2MydDZAaStwKjY0
Vlk2WGdFWjJVaFpvKzNMayE8N05wPn49byNBcEJBJntBS1ZUekhOZUxKfDwKei07TGYoI3drM0Rv
OTJ6ZT1EOVdOKyN6dUw7VEhtTnAlWk07KH42ViZsd21iKFdnaTNYZHZoKjkxK29CfU01Zzc8CnpO
OV9Rbz9rd24/aHkmJXVYdF49WEd9KVczTF9RNyYjND5+WEZeSWxSMjxRNm1wSGs4TzF3Vm5mZHNP
aCV3dDgyfQp6RXFZS3s5cVQwaTw3JitUX0FqY1VDaCpkeTlTejIhJV55YGVpeTlPYktxST1zakVh
KjxeSDJhQUYtLUo4I01DJEcKeiZnciZ2VjNebCo2PGsqSHR7OSRxS3s1OytIMlBwTj9USm55e3VT
ZDM+Qy1ZO0tVIU1UR3NRdFRDMjx5fURiK2goCno3cU4tTHlkSVUhODZaNmFUZWkmI3k2PzVySGpi
OCMhQUNxfTMjM3tTdzhEcClBQmZBPGgqNlVuVUQ1QSM/aWt0dwp6VG9TbkB4JVNfanhsdD0wdF8h
I01FcFF+OUszKGF1I3hQUURGMzU7SDhDKWNLcTtWPUNfbGo+amhrbE92UUBoV2EKellaezEyPSpk
PTB3MURESSVqdiskJGMqYzUoSEtKNzdQa3w3JjdLcVN3e1JfQVkjbCh0VE1UUXU0dU9ZP0xuI2E7
CnplMEQ3dTc/c1A1c3YqZjVvNWxabl9tfExCdDI0MWNMZFF7T2l0JTJiWX1YZSFpUSpXK3lsUyM4
ciZoRjxDO0h6Nwp6SCsxKHUtbVRXfW5MaWZfNklhZmJjNlY7OHBNUjFiaVJAPl5hUCMtd0dmNFMq
byNZZ0tNWVNLREFKblFSdG9venIKemohYSROQXk4dkEodXBAWHtmSSNAJH5PUDM4PnYmQHdWdCQo
cllLT249fXdjSTdJQmojKnY1Yjc9UGh8WDt9NkhOCno0MVdPLT1vTWlNdDUhU2ZqLUNeYWNBRjRZ
YysrVyhNVG5wRXZUd2BqbWNKSEt3PCg7TnpPczlmWUoqO2JZJURlMAp6Yj9UZXFlQ242TG89Q2pK
JH4pfX5Zaj1obnE9bWpIZURHb2FXLXI7e2g/fFB3aXIkNW5uNG9LR1QjUUFDWmVfJSYKekN8Z3dm
cWhjLU8xeExFUCkpWCR5WlpaUVU0eGkpPjJGNyU/Rj0hPnNZc3lKXyt0bWhALVcyTG5CViRyJkxf
KFM7Cno8aiZCWnskM0gqUVZ3ZippOEh3SFBCOSpEK2IrTzNwOSRzNil+IUomKy0kczdsVFE5O0tY
IVlebSQtMVpkeSMxcQp6VDA/Sl5NMiROWG1UTmsrbFQ1Vy0tQH41fTQyJj9IcHxFR2chZHcqUXUr
Tj47anFDYnAkJkh9UWVAKUxCTHlPWHQKek14TUJMY0I4aEw8ajYyN09CYmxVb0hGdDlDS1EobDRm
TnVZTnZufUlEaURaMnVEK2N7SV8lYXs8KjIrYExhSnR1Cnp4LTxMPEh3M29edmg+cHFSTHdHYDgy
e3FkUTlKSEQ+fVBsWHtTJVh8OERzZFBpUTl+KF9ydjs7SD5WSFdCOT19bAp6Q2Y9bzxeLW5DWnVH
cS1CUCk1aCt3fX00Uyl6bipUQX1fQWRJKXFOUVJ8S1Febmp8ZUZnYGY/MlEzVCVncDwzQ2oKel9f
T143S1EkfVlwTyVZKnskMCg8UE9ieWg0OzFrSyNrTj9ieXxMWVp0XyYyKndWMFdhQjVKXjRIQ284
dkxkQClzCno3NDI/UWEmUGdqRT9ZaFZTM09zODU8eXNBKUY9KFMoYjQ2VT55KF5pe09KNSt2Skgt
SmRuM09PNjliVlYxaSZHYgp6QU0jZzFVcC10JUxEIyk5akNBbWFeJTJBVStrXkA5emV3YWhoUkhs
OFQ5O2g0U1dad29xdGxza2RnJD9AYGIhdTIKelQwWGNNdEApej1seSM2YHtBTHt4QFlDTj94OHdp
fWp9I2I9bHo+KlRWKVp6XnNpU2ZFLVAjN25SQEhjQkxKfUFPCnpJP2IxZip7MkN7P1FnaD13ZjN3
XjxadUs8ZGslPjBzKHt0SkAlYHZhR2BsfmlxflVSWVlfRDxgVihFcURzfG9MWgp6aCs2UyE9OWlS
OFBkVTgrSDlzUDZWKmYhbHJyITtGPEc1NVhvWSE8dXNvLUFwYy1Wd0c7ajl1PUJYWGlkMzsmJX0K
eiZibjI1NH17c0ZhPSg5bGBZdWtzTkh9bmFuflVlO2ArfmQ5Y1JgIS1VQzc+fGhUN2x6NXJNcSk0
dFBhQDJ4ViEhCnpKbmQhT21XbFl+PilZKUJBRjQxVk5nTUV8PGB2dmduYmRXSWoqPHg9MiNafWpu
Uy1KJmg0MT99VyFJISMhcTxBVQp6UDxib3VsKGFxYkFueXMwYyZKZ0R7b1ZGa2MmSTY/QGxVPloo
IWBUa1NmbHtCdWJiTkE9eDV1ZkhzMSZMRV5Cd3MKekc8SDFQcU9mUWNgb04oMFYoSmU+WmFEd3Bh
KVoxbk1NQUdXcWFCbFIkPTIkaCF4eFdNSExhOTE0TGcmJG5yTWwlCnp1RTtNLVlMVTN7VW95bThg
dnQ7c1JQaDNycXV4Mk01TTkjckxlPW5VT05JTlBrJXkqTHtaKndAJSRsUElHbTkmUgp6e1Y4T3Bk
fE1qY05EMDA2JFpCI0JPIWJrOFRCd0ZzcjQya1lMRXNrKTMhSTZgJHBmcnw+aXkpaShIVGA7OTBj
bnsKekJiTXYmOS1FXz5hKzZudTthXkpLXn40ank8OD5VYXR3JmJnTWg5P3spak14ZEl5V2cjTHo7
dk5ZcTRHITxTZFlCCnpDZ310Z1RVSS1hPCMyKkBlKHtEPW04eFQtemZDVldJfDQ7KE84VHxAenY8
UVJgVGNJQFdAZGZXTSFhMTBVbzNRTgp6TUU9MGA7bz1ueEd4eDNTaUxEd2UyZ3g4TzVBcSl2YSRB
IXJifEw4QDJyZm8kPiZUZjgjSC00XjR5PEUxbVNKOGkKek01ITBlIXNFfUxPTHZFRUpKVnYyKGdl
KXUhPCMkM3opbT0yUEtwZn16a2I/cTdkMUwoTkoqPX1MezkyZW92UUd0CnpucjdUfU1KOStxbmFh
dksrb2Z9ZzY2OU5tS3hBZ3U3YXdPKVJicVlUcz9ZWUUzKj1WRGkjfVQzVTd+bWEjbDNRRwp6Oz41
U04jOUVuYjxpbVlDMHRGM34lbFB8QGx2WTYzXyFDcEpKeEo4IWJKY2dLUDMwUn11JHdAO0hFPFQ/
cXEqV3cKeiZpWmgqKThuKml4U0VgVD9AO15xWE5DQzBNO19hNzZLclo2aXlDfjdabE5iJUJSIyF0
ckYyWiNxUzl0N1JBfHNOCno0XyNlT0U+Tl5SK3NTb2k5NyVwZFdIS0lWYnN9dyVUWH5SdVlqdCkq
Q01DSz5fSCg7NDQ/ZD5TSntWO29ge1EyNAp6I2I3N1ZgVVlFTUFQSUpIPUg4JipfIWJCY2Y5dy1e
QF5tR2Z7MSp3dld8c05RdElXa2g2SC0mcWd6UmE8ckNoQH0Kej9DTXZRPjMpNXFONF5qOUpFQ3go
OHNONSFaVD0pQGh2YzIpalotNFJvOVJpeWB4JS1pdnY2RnRVIXtKJSRqKXBvCnpzbjJ8MUg1ekY3
UFI9fWBtQ0RyO2d3b0dKT3sydD9FTUJ+OEE9eygwZ3NDPn09XjhOVXhAeCpVLVo4S3lzenEkMwp6
WWxPZjZ1WitoU3FxSmY/aVhOUzRgNS1KOXN1IXhyWVFXVTBAfXRofVZeO2N3I2gxb0olI1lZbjhV
KDVHXjEpSmcKeiU7UjtNQHJJdXxNMiRIVEd7MEpYczx5RipYMGI0TWl7WjJCY2VtVW1DfDBpbFU5
KXc7cShHZm8kfXg/NCpYOHNTCnpyMiZiP3l4LTxUVXV1JUY9Km9GSEY3KkNkZkJkd0ZeVHBAKXpl
JnFFODFpYiZUQ3A7WDF9O2ZeTD1zZ2sme1VlQQp6aVg1Tyk5enZHQUVRa3Zpe2ZGfUJUKml9Qk5e
Jn5DK0pzalBeTkwjMk5TPztPdGZFczMrODlqeXBJPX0/KnRaRmIKektDVClyc1Qhe2lLWDt9PVps
UTdnNEQ1dXg/cUlkdmRDPjk9ZEsxPmd1SWYkZjRuZylQXmktbEZHKmBNdVE9eH1rCnowV3Q5REZe
YTtCO3E1ZU1TbFV1dDxyWiolSVFBI2JRSW5SM2g8QGd7X05ZYGVIN2FEckpWK1Emc0tpSjd1Mlo8
Wgp6MWBPTD9MYEUydGgjT3FjTm13fFQkJSUrKm0tV1czV28zMFNTeyVHdTsqVWleIWBCOURNR2h9
bil2RSg8Xyk9dSoKemxzfGpOWnBgMWlERUpiSjZmZ0BwJV9MQHMmTyZYdVU5cWRaTWhXSDtgSWtx
RjMmY1NGZjFgSXxMdkIobHV4YHFsCnp3T2sqRmdeSztEdUxQRmtWfEd5aFFhRGtaajV3NTVvS1Um
IXdAWUp2YW05QlV5Wj0zZ2NFYFE0IUBOPyEtTF52Iwp6OzJLan4qU3tTdUg7N0RwfEl2WnF4ME93
eWx6OUBoIypiaHdrNCR0aWBvMDNucD40X2A9d35xSENwOEEmMnRCZlIKenlmVFp+PW5tPEtVKD48
VkNGbkpSe011cDdiP3MzJDE9SipCNzgheTZhcyMxPkFxMHxYTiYxZzs2d0Q3ZEY0a1p1CnpsQUFr
JDJuWUNuIXt5LUdzUExKT3AqdntkM0R4ckJXKSpAbnJKOy0jMn5TPWxMMFhYJkdnKWI4V31hMEp5
TlkhZwp6ZzJ4dWJ3S3lVQzEtNiFkKl42MVpKYUg9QVdzZXJnMDB3cl8kPkRzfTd6aUp5QEAxQ21p
QVJKJms3bGZCTV9NQXsKejE/P3hlP0xVdmE4dztPfWwhMXdjYntlUzhuSiZKJWNaQUMlQng3ODx6
eF4pPHR3ezQ/SXQzR2F4aVVpelJjJS1LCnomUC1ofF9QeVhuMWdJJTVxbV8wRmVZMXh1cWIlfndx
RyNIeFh+fTJeN2peYHRne3olSTE/P19CRDw7T0xVe1BoUgp6dWhmKH55QDhxUmBod2tDXjgxZkUz
RUA0fHt8Mi0/NkNrNVVKanY3NSM9P0RBR29VNn51OU5iJlJudyFMNXVCfSkKemMkKjhNUnV2UEo9
N24oe1BoUkVrcjFGPCRFeERlMWZsITstVHB4ZiMqdVlgdFRNVTRuamsyWHYkKCpIKzN7bHdICnol
ISo+diE9YTF1ISolaCVwSTQqZEcoaDQoJGhvVWYoQ3NfN0xHS0Fzcks8fXY7JjNUfHE0JTVOVWQ9
SyNtZD94NAp6aGNETyhFblU0QVlxQEhlemN4QFheMFopVkp2eSVgQ09vRV9GVlRkYmg7cXNaZUp2
KWpIJEU9KkxkXmpDSF5icjUKejdCeSh7az1kOSVZTD9jRitMNXBIUVFANTh2b35rIUdOM1RHVHpi
QCZxaT05VzwrK1hTVi1OOFMma04rK0FIZ0k+CnpVUz1fSlJVJFg4Njk8X0pzQTg2aWtOdTItTj91
SUgpbG4/ZT05dV9xLU4xbmR1WDdyWUxeNDBHVnVvMjZiMG4qKAp6PGlLdTxHcXszI0h6fVckT00+
RWo/fHhoRDFDcjNoZ3R2UjNJWFEjMSRSUkhrZzd0M15oMHNrRzhYTkBmYDY+cCYKemNTdE1JTlpK
T0VffWB6bUUmVEcmOTw1UntRYkchbihWVTBXSW5+TEZkSzZ6ajJjKWdKST89d3o+d2FCenpmJDNl
CnpJYURjVUxAcSFmKVBAIz5PaVpZaVErfl5qdjhAWV5wQyopUiFeODxTYzgjSUhhQHcpIT53c2R0
eXpYUGdoJHF4cwp6XmR4WDltPn1VTjRNckJLMn09d1ctRlBJcFo0SVdlNihVKkVuWkd+VW5wLWkw
cXd5cjd0NnE/bCYxTGlKMylxIS0KejYwPT5DNTAwJkslMlIjbG5ZcWtwRUw9bUM2RSojUT9RZXVW
Xk1HTXYlRUhXakUpbDJaOG1ROyNpUjRTYV5JbV8tCnpESThwITY0WnsyUnZ0NShsM3o3bTkkemIz
IT5gWER2Snp4cDhBTEdgYFA0YERzWlVnbFVnbWN+d3RLI3NGajFUUQp6d3dlLTJSZnQrNTVTRXdQ
cFhRZXdBY2smYTdnKkQ1NjtfQjA9Tmp8VEg1cDNCblFKbmVXOyU/YWRkam42QDVgPGIKemt8aXw7
JDFBYjRCJEpiZT4pcjkodkA4fnA0Uz1+NHBrTWJAWmsmalJRfjJ9RTc9OXRGXjhVUGV0TSpxTXVm
Wj5rCnpeNDh9VGchKUF6X051ODllPmpJe0VWKnl0aVR5a2pHY2drc3JBVFo0VippI3UlPD1FX3c1
ZWZkVEIhXiNWJiReNwp6Vk9tYTsoeldUOWh1Iyl8akBqbWZwRENFXmJWQlcxSDNPe0ApcHF0amBG
dz5sMjt1N0tqd0UyUT1QYktJT3NzX2MKekN2QXkxSktaaFBVMTMmQEE7WlolIXsxMzdeXjMteEUq
bGtEJUFRUkFzMiowTUM+Z1hmPk8oNU9MKDRfVDU8RX51CnpIPncxcXYyJWImZ0Y1KERmcHVYK1ND
Qi1GOTFOMnVKUGlqZVppQ1YwJnkxTkF6TnMqJkIkeVhvVEh6Q3wzK2Q9UAp6IVRCdTdmWiVXTUtU
fVAwSXdFfnRRYDlxWmZnKD4yZGEyO3w+NiFHQ2cpaWM1ayoqUio5RXNOWDhlPzk3RVVCUHIKendT
d3dvKmY2c2dAOXJZJTlefF5jYGwtLVQ7UFRZejJzcFlGKXl7LSUkQHxnQyQjNiN5UUdRdTdtVTli
VlFnKE9gCnpick1OUjU/YCo8KiRpKkhYYmwhd209azc2MT0yRm8lQWpmbWZjQGlnXipSKjdpRXFn
NFYzfWwhYV9PYEchNk4mUgp6NT8jT0RjNTg0ajA0UU9iSjhpNjAtbl5nVHo7RGYrS0VvQGExVEN6
THZFdHNrYlRFMHk4MFJjSXQyeU48aXdmNkwKemp0SXdCNk0zb15YPndmaFZAQ35ocmFIZUdxYSh9
SFd0R142VjJ9eko2KHA3TSl7RVVzeUBVJH5mSEN8MnRqXjhlCnp7TnlMVz8pclVsSE9BQyRTOXhA
dnstOG5oZ0Z5MHZFaWxiclRpMkNyYzI+O1VtX0FWfGl7ZWN6cnpLUi1nRmV3NQp6KHc+N2ZMalhv
YF9yWEpiZml9dERnNmsmNUUrJmxGYi1sTXEmUTcyO3VjciFHZzR2XmNfNkw8Nmh3VDM9JnBicjYK
enlhcWhZcytxVlNxX0E7aERRTXxARTUxXkttYmpQcFBeUz9MdkF2KUQ3K1VEa1g4TXc4MyZCZDEx
O21JLVZ5RkVMCnp7KkhFeistdWcwVUh+b1UzPHdYMEh9NEtjSylYUE97Y01APUJ0YkA1PVVsbjdg
PSRLNzwwblZCYD9kbG8mSVdUYwp6aXw0enZsJHlqe0oleFZUYHxCR2Q1fTElSk5xdHQ1KXhOKEAq
eXlOVm1+PWZGMVNONFdHRi1AT0FXfWlWKEZoYzsKelJuYHY9MWR5Q29HeU1pRTZNYiZLRWxMZHA5
bUtCbEhUYlBMcWhJQGM8KVc3NlBxYVImcklYK3NPajFOVlJxNng3CnojcUxpQ3ZBM0tpVCt9eC0m
Ql52fT5jV1pVRUpjUWcrY3xKKGJGe3RJVWVKZDFvYVRsUVBiN3lReD0jd2R6aG53SAp6Y04pbVAr
Sm05UiRUaUFMYiQpWVk2az9aflp3dGtyQDgyKk5rJDc/IWwkcU4wWitTWUc9alZTayVwVSttYk0o
VS0KemJlYjkoVCRoaCp7OGdFKGdeJlgld0JhUmo0WGhSX2dsO0JtYSgoYVJ7d31+biVaRC0wKHZw
WCZVJm89e0E4d151CnpXalg3aGVqTGVWWmotdEJFV2Z8MCVQVDdgNkhoOTZMcClKYENROSFjYFBE
P3U+TiVLLT5geGhQQnZMe01ZR0pZQwp6UG1kZlgrSGFPQGE+WGU4QGkodT1hOVBiX0I/OSpYO14r
JU9ZI3J9bE0zK0F8UHhBTzBWa2hsJlR+cTdwTDNRRyYKem1yKHRrN29NQTVANm9yKHl8R2EpV3Nh
IUF2VHIhb2tnSmZCJT58eEUxenpxSms1QE5OPTxnSyo7JW8tN2AkP1J9CnokYFc8bmM3d3RLVXNg
IUBLdk9GWlNWRCE+TnMqPmtrdTJoQ1lpcXt3dzVYVFI7USE8cDwra2tJdHcqWnFPX14/aAp6Rzd8
eUNGXjZDbHJ3TmtPQ2NFIzVidVE+S0tUS1N3UW9DWSkqQHk3YkN6YyU1V24jJWwrPDhMY0Faem1O
ZGNxVkUKekNtOCErY3FnIVFBKFJDbyNXQGxAdERuOF96ZlY3eWwtKXwmcHhMfTQ8NGQzK2xkQmVt
RyVONXNga1dSaW11Xml2CnplLXNVKVM+QTtnRCo5Mj95blQlfG1NS3Q4VUZCTnczdElHeThaSjIw
P2hCPkgqbUt8fFN4WUE3MT8hSVJxWX1MLQp6NjFAdlkqWHYqUF80alZMVCY4NFk5ZnZjI1ZEZEBj
b3ZiPTFDI1VfX25+OWZ5OU4lNytZJUdDP2BKZk9RRWBWSUUKekk7SDZRWXJ9aTEtT2okbHdxVDwm
KEBxRlhvUTwkWGNzTkZJY1pJbWBULS0oMWQqP30jN0VZbH1FamhPV3gzanVoCnppY1otKkE/V0c9
PFQ2JVVMQEVePmVxJDVpRD5eRyN6e1dNMiFuU2h6b3h9ZnBFbGxmQGhnY3pfKiZXPEBKTSpjagp6
WWQ9R2BEX3xzSEFtQXYpZF8jVjlDKjI/YEpaJkl+QFdENz4reVY0WlIkakZ7MnlfMlRmJlRmK2N1
Qkk+YEkkNTUKejszVXhOMVFjajluSW8xekA1Yz00OGsrcVo/akhNZWIxPWx3d1FjU0V4LVpiPmAk
PjM7K19oZFQ4Rm8kenlWOz8tCno8Mj43WSYzOGZmPD5oN0NLcD9pQCFBQ1NLT3pffVdObDkxfnZg
Mj5tKzk+az9wO305anB3cW45antGPi0ySlUkTgp6UVhSMC1AdiF6SEBiPm0qNXNsKj8xMEhmMDZt
K09PSzA0QVF0bXhRO2xZa3Q+TEZpKzUySndOKSstSU1+Z2pwb04Kem47JXduSnw5MTwxMUFHT3Zr
TSM1XzQ4XiRfWVFGNmxSLSp5TS19ZF5CXyNeO1JtTHdIZnpLNTBrZlB0QGVFZCU7Cno9fUU7anFQ
ayR6LXRMYjM0Mk8tVSUjR0s1WFlZJmtMYHstJWpaVUBoOVUqOVFmWCk3N3U0JmgxRnh2VntBP1Vx
Rgp6cUpSMmQ2aCQhdUZKYnE5VyhEWG4xb1pOcHRaVS1nbXE3USlpelVnRjhrKEYwaHdJXnRMNyhy
OVRuOSRLeT40TVMKeitsN1B2X0NqaEA0cHZ3NzltWFp6VyowITAjUjZ7PWIzXjI5K2dGc3hHNDIh
RkVaOz9RSSZjb01wbkBnP3A0TzA3CnpjUl93RV99XnIxdj0xMUZSRXsxaSg4eUg3YyVNYEB2QS0t
MWlDPWs3aXIkPCRMPUU1JCtKYzZ8aFl+ans4ZF5JIwp6dlhmY2otblNVVXVpX3N9eXdeTkFJMXhA
PmsreUJ3cmlsfnFLSn1KWWBSKUEmPmVyb3NmQjt7SDNId1VFP05uNFQKendzN2V6Y1FxQyNLUi1X
dmh4c2Y+aT1wJHwyO29lPyt2bk58Jn1OQ3Q/R3pYLTgyciVyKDJARmpZU1o7dD9xbXBACnpXWVNm
KHQoK0J1ZTtmJWFYO0M2enBvWCN2XiQ4WT1JQWlaNFltUyU4aDBjNUx1SUxAMip4dW87ZztebmNV
ZXU3Ugp6YUYzNEhKPjVYdCorRXMlPmNZYXQqR2h1UWhRMjFFOCh4NzRnWXNaWD9WSjYoQjs5T304
UGhlZG0meH1NRSZIRi0KekNWPmkwTTU0Pj9FPnZxMGN9WFBnSkZ6UGdja0BqaFB1MnslWnI1MUNa
TmRhKlM/KTFJS0JEOEg/aiFvZnQhLV9GCnorNVhwTTZrUyg/MD4pa2tZaEJPJUx8NXZjaWIwXlUt
QmxuaCR1UXd7SkgmSXJfK2h2JiZmakd5YzBLaCY2ckhSUQp6NGZQYnl0RWdCYHBQWFc3YjtFcEZX
bzMrOSlRMWlDZG0pP21yLSFjaDRpSFB+Qz97TVlNREpfSkFOaDN2NHZLVTAKem1nKyhePShPaEhl
NyltaytvREYxWSQlMi1OSUt1WWNaejQhJlMtUjdSPmNoYz9DZ3h5PSs5PFZxUG9+IWBOcXEtCnpj
UEd6UihoSlNaNlpKdHkrKiFyPiYkOFVrMFZnNj17PHFVJTh5eVl7SVZfKXdFSU1fe3gzV21OOzFI
QypGNUVvUwp6R29zM3A2bkliQVIqcVFKKTtBSEJNU1dtdnpwSX5CZG1ucyU+KUxvN04hd3tIdUZy
V19PbWwrT3FPRyFwYWNkI1YKemVjZmVIWkBaaCUtVDMycSgmIU5PPEEpa1k+Wm91ZWIoVEEwayZ6
IyVoLSNXc15+a0lkdVdUbWZiJUM2JExuVFRkCnpgZ2RzKVZHJDd1e1pAfnFJTWRoZGhLO0EwKVhy
TyVBfXpidSgrWnJ4a1J8NG5fKlZlNUA2eTMoMS1PMmI7fHxeYQp6PiskO2ZNLUcrYFE4cWZ2JCZN
VytMazI2SEBGWWt5ajBreXkteFNtPyhrblRaY3UyOHtyO0RTWEtGXz4oR1cqb2UKejZJbCpoYXFy
JGQ4N0w/V14rN2smPzAkRnI4VDVLcjRjWmc4UkFDeDxpYjEhcFErfnd3K0Q3cyhFZmF4cjVQUWg9
CnplMjMhd0BmZUJSPVdASFY2TE4heWgmV2xMR2d8SkA7SFE4dSpZNnRMZlFiX3A5X3wwelFyc3hj
TXZFandSeVojJgp6WF49PTI4JFElcmt3MjRvO3M3blB3WThOekwha05+c0tIXmY+IWRGQz9SMXxL
eG9rZjYtI0wrZEJDemhoSH1lZFUKekdiTGFRSyMyQG56LWEkKzBEPkdtSExaRUFsc1Q+VnNXWVhy
Mz8re2lTd21ZdGwqa207VCopNXZQTF5lZCFEIWh4Cno0VHcxYig8RXJaVDlLXz50QCFYI0FuWmBN
QzshZVM0TXM7NntPZF9KIV5ZaStRSTBQRW4rd1NLI1d+Yz0lS0M4NQp6bn0lMEZGPjFzT3U4SE9n
Mns9WnEqTVhPa3RrbDUqcEZaRTYpT0I9cG5CJlZxbn0zWH1HaDNjcCNieT1oRSROVjkKejM0aTFw
KT48am1lO3Y7dChIUTs4PDRRSX1PVUp4cHlQTEQwYlR+QV9EeT1+K1RgUzBXbyM4SlBaJk9CO1k0
cmdvCnotWG53YTBLUTlMK3lhbXxFalp7e29FdjY/JHhVeTUlMFVWM2cjUTFBPXZubUZjUmx7VSE0
SyN3MkdDWSpmUmRiPQpLWT9aV0dAYyNrYmNgQlIkCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRp
ZmYgLS1naXQgYS9hcHAvcmVzL3N0ZWFtL2VjbGlwc2VfbG9nby5wbmcgYi9hcHAvcmVzL3N0ZWFt
L2VjbGlwc2VfbG9nby5wbmcKbmV3IGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggMDAwMDAwMDAwMDAw
MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMC4uNTU4YzEwZDk4NGMwYThiZTg1ODRjMDg0OTlj
ZmIwZTA1N2Q2ZmFlNgpHSVQgYmluYXJ5IHBhdGNoCmxpdGVyYWwgOTU2MQp6Y21lSHRfZ0Itd3Yt
U3JPM25IazEoayp9cE5SezNkREZHPWAxcTdyRGdrQ2pOMyZsYzw2aXcoNWRJMEdwNmN0MVMKej19
byRITEtQJCszRlU3NS1oYmYhYV5MZndiOGAtNyE+NyM3Sn5RKm8+fSsxPz51UXsoV3V0ezQ9cXli
MHReb3Y1CnpZZUVvfSVCZDZKTmAmQ1ViVEZMdSlITCZmQW9eeT9BSnNSSGUweStfKW1RQy11YzMj
ZFotOS1yMH44UHRBbmZjOAp6X3AhNl9iUClGTmV2RHBNVjF1QTU1YlctNHFiRGhBNk9XJjg1RjJW
WEghaU1+QVZqSml3QWFyKjZpeGxmO2ApaXwKenghNWBMdXlhfmhjJkwhPzd+N3U4VHM+WERhZiZ4
UT8mWX0pcUMjUHhVcGspUis+TzhzZWIqXlI4Sm9KVEQyT09yCnpscmtTZCN3KDBZa3BIeXl0KkBA
P2JALVckcitxbTNzZ1AhYDNOKFlENWlIbGdAZFdMJCkwOGp3aiRmYio/QCNlaQp6MkdSM2lnJUlA
VVN7IUJnYm9VQXM3e1hxdTlIYWNwYDBPfWt4Yyt9SFFlZ08+ZkZueCp7YXBIbTNsfGJsRGE5PTwK
emNrMz1aXnA+SURtekd4KiFtaGMlSiZmVE5fJmI/IzRuRGBBbktKPDlCfnlaUDBoQHVTWDg3STwt
XzxoUFhrbkl8Cnopd2xPQlBjQXQ4cjdvdllITW52bV5oIVFHY2t6ekNLSWUzdFlzcW4wTWQzWUgx
N258VG16OENzaWgkQlc3eD96fgp6dCRBXn09SDwoMHA+cj5RZU8xITY/JWYtaGAjOUA2QnhkTmx3
ZEJReWpLfERMSFQ4e0FGRlFGNnAhKEtFalQjS3QKejN5VWhUJlpTIUJENURrbGlodDxvKTJGcXhi
JlJlMnQ1M3wmSVkwMV5zamchKi1kTkdeSWQlREtJdnNTNSFJZXUtCnp7T0leZT08Z2lgdUdvY0Mm
KHtsU29gdSg9SVNSJmlHRiRgTT1aZ3laWE9LZHFkXzt7PjNBUDgtJTB9fWdfX0V8Xwp6RGczZFAz
czQ1YklaWV54K2tieWEzfT4/LWl9RC1hWTxFNjshXmpOI0pJJm0hNVptXyRVJW1WeDY8cyt6PmBy
X1MKekxFOWA4YmVQZWR4dXhtZXhXP2YxaHRjZ3FhVVRPP3BXXzd2I3xNZi02Ul5Za29iMUxrWmsz
Mzg1RU9IWV43d2dsCno0dHM4US1gWFhzOztYTyUrUWUwcHtDY2ZVUEVKSVlZaWRaJSg/bTlFckpg
QGdwPGljZzshaS1JWT1ZZ0V6bXVqcQp6TzhQUT4rQHo2OFk7U3M4VlpOXyk7Tk1USFhoa1k4ZT9l
OEdhVTlDZl5FYGVVPmNQJnV5e1NrZHFKNmpLV3w+Qi0KelJYPW1pODtCTjU/PE5xczF+MkRsYjs1
fkpLeHV2dUdDZ1h+Q3JhZUlXSzMlO3l+OGltVmA8JWc3SkIwSzk0NDwlCnpkfGI5e3V4PVB6SzJI
VExUfXJWJTNDWGxBeT4oU1E+ZkNWdGAle2R6V1VOcmRBKTJuYSQ0NmRqQzktSkprVWcpVAp6M2JP
ciZnenZ+cGUjR0QwdXtrTU0rTXUjSz5LYyl3JiM1TT1OVThARnRfXzI7UjhZP2J1emM3QlBGK1FY
TU8jYWAKempjZWlsclVHUlNrQGhkRXN0VDs4ez8xS31qKmRUflh2eDcwc0d6MEpIYCReelh3M3A4
SD4qdXNKWFByVncyRFd5CnpYcjw4aVl2ZFdAWl8hcCVraz9DPFZfYEIkPkY8an10O3Y/cnZOb3Q9
OW0+WUZCYHs+PlpqbkQ+UlBQWCoxUCF4Twp6e2x9Qk4zVDFkTE9Eek0/NSUta1Q0fChEQzU+PVl3
K2NSQjRxXkAhYCtMejVIdjhTTDxfY2c5aXNjXjYqQ0tjM3AKentCMEVIZHdjKVVDTDhPZDJgcGtW
fDMtZ0p2YW10VmxeNil4e08oUSFiZCs2bU1OQ2JeSV48bj4zfUBiX2E9JW9zCnpOP1ErJXlaUDMy
dWo1YkBvVSkyfGlEWWUmRjEpJmBVUnYmXypNOCF0ZEwqNWo+diZPekB7e21ENHhrIVctY0tyKAp6
NmlyX2w7d3NeZmdjUUghR3YqY2ZPWk5HQFJWKGNibWtSbFJSVXF5eyZgcFk3RFN6aUhLZ2VCdTlR
UUBZNGNVQUIKenlaJXA2VS1ETGZRU1UrKExJSHdLOU19Q3c5VlgqQlRfJVBAJSEhSDlzZnpQX2tG
I01SJWBPLXQ4blMqWVokYzFACnpDQD9+bFNGPlMxQHpiamNkYG9YVFBUO2Alel8jY2NIU3xkM1k4
LVNXcUs9YlpGPVRYNCVqLUdebGc0TXkyUy0maQp6JUh1MWlwcz88THd9VCYjWj0mQUVgezs5Z2tL
LURfWHxiYzFpQDZ3fUZzZXZrMz5NP30zNTZFbF5qMG90RnVRZTwKeik+QGZPVm95UyEhVF4xJXlk
QERVS1dLVUxFUGF3ZShvSXc/YTk0UlphWU44RyEwPWEycX41WkIqfk99R0NwfFdzCno3IyZEN1Mx
YjRtSldKRlFXUHgqYnVFQGoxX2xEYmhHVTlaRSF8MEJrOzR9YUlUSSZ5MWFSV3kyYTxDMzVqfFF1
JAp6aWl2K34/NGhodFl6cGxlbG5rYSl0YVFlRklxQHdQZkBHTTBfdUlDeShsa3IoLVlWN1Jrbys1
cnp8XjtsUEQ0PUMKekZeYUxgSmZjNjBeMlg0cUJEQHcmX1AkKCZNXlp5cVhhTyZyPEVGanZQRXll
JFUrSj1qSU5icSFffk80P1RLe2V9CnolREpYK05jcHxXRT5GNlNiPGVNVUFfcVpQKUY5bCZXQGZV
KUVOMyo0N2dzMFNgekFzN291Z2QrXzREbitYdVhjMQp6I28wRGR5NUkqRUhVdzcpeTMwdD4/TmlG
PFdAaTRGKEhCKE0hb19WTTJsMU1NcztCdjZvVWoqPHM9MVoqKkpWRS0Kej1OT1E0VSUyLX1NIXw8
WUZvRjJDKkJZMWg8Mk1AUFohU1N1PzNBMTlFdnZgcyt7bE09JUEjT0I9RUQhKjFsUD9yCnojfHAk
VD0rbVgheiNJd2tMWFhSR08xeVpRXjxtb0NpUD09cElYPzwrLWktWXwrXno4PE9hb348N3ZKT28w
QzFGNQp6JmEzQzwxaWEjZzNBaX5NTTRocFAwUUNXZHYpKl5DPilZNUNVSzg0RSRnVWRjOHYjaEYx
MD9UJG9hUUhafDc3eGQKendTZnI1UzJZOVM7U31Ndit7anprVEkyMldkMEVRNUI+K3FwRDd4UEt3
KVRvZUJqUmUraVQkTG02T2Y3byNVKTx6CnolM3Q3N3Z6a0czZ0Y7fU4+KSYlRGd0eT4xOSV+dD1I
QlNLOVJmK309VWY7VEUla2Y9d3UzWXxSPlJCa3ZpUTtRYQp6K1UweVYzXi11d2ktWjZPJTI9ZSM/
R2d8MCZhc2N8QU1GS04tdWI4SGtpSUIqX3R6OzxkMXlRYk5aJU5gQExTXzgKekg+X1JMKD9XKDdm
X2cjMExBZ2tHX2JxcGBzOExGUyVSZ0lqfENgdzJNdXNMWjNSfktIMGVxKDtBcVomMXtfbHBICnpN
cW1xWXlyLStXJShkQHxJWTRtYXQ1VEYybjtjPmlpYG1pV1pfQU1vMU9henRuUyQoQnxIYE0jNT97
e0dZOWQ/bgp6PzlGN1k5P3M7YkxzOU0mMTtzKlRhPDswSXFQKi1gQjZQcEUpcCp5fStDTlopSyFU
dmVWdFpuPlF+XkdtRXZDRTgKekBPZ0M4RzlZZEs1Y25+Ymd0MG03OHZxbT8/XnZwd1JBVD1zdW9p
eyp2JkxzNG1aUTlRWmxRRUxJcWNXTXlqckBMCnpmZGEmVFcqMjBHJm9NKi08NklAd3JgVlhwdk00
V2NMczFCZDdJaCVFN29tNjUtKlU0P3dEUlBeZ1M+T1U4biNCMwp6ZVpCemxgNU5WSXN5Rk5jK154
TmglNTxGX0JHc09fenJRfXA3anBzNUtsJCZqJDYhKGJ5TX1tOVU3ZWJESW0pdWgKemRyT2NSdk9O
fXhyZEZaKmBPfjFaYjIwKmAjb0YkVGxhejstZylfRUY7WDhBYUpVPWFxS35RaVFCPzNOWEkwOCZa
CnprQkJ3MmR9Uj9UJUhSRUp1QHcwbDYjM2BSNnhJbVp2eih1OGlfNkBFdkM1X0xIanpeLXJLKD00
biMyTjN4V083KQp6cVMhKzVPNzhpPGY1QGVKSUVTXztafVEkTXMrSEpSY19UUVg3Q0x+QVpKWFVa
ZGVELUM2P3ZXU3Y5cjRSR3E2VmIKeiRqO29iXlZKQUNOYVpyY0RJPGFnOSQqcVhDI0QhLTUhKikq
SWBMQFUwJjxJMzhlUVZhKFBBIVlzMyglNWs2NVZpCnopUE5mWXRHTG1lP29jJDEtT1YmezU9UT1e
JVVRM3JeSDIqTFd2KEJnJVl2MTQ3PUJ4aHdiKSR0R3ArZVEtYFFeRgp6XnNYaTNhM3FxQFNjPDRg
fDNwUlBPc3lZUWo+KEFnKVZjYWtERWh1JHl9MktKdy13KVNHXyQpLWVvRjwzZztWZ14KendvPTdS
bUp9YFJuRGFFcD4xdVdNPmRARTtyQWQlLTxSN3hGeilXOXQhLStTYnVuPzdoSmlPTj4+Mmo2Xm5B
JUppCno9Z2BCRmliVE4pRFpNUT03MHk9WG5VaWg+KWQoZz9NVmFEWj5jKnQ4P1dIdUszRSZwMHs+
ezE4WFZIWj5eVHRNUAp6dlJsbWZVc01oKjhYTEJHe0Y4aEtOVHdyTzQ0U3lQIVlMcmYta2dgMkFr
Rj99T3FfY30qaWlrRF5kNmc4IVh4QjEKel4mZHFqS312VXEjYiZ8XlhFZ2FwS1lxc1BYcWJgbCo3
bVA1IylMPCshKl9WPkNZKGA7JGtJI2Ywc1F1NTY0WCRPCnpjd3wzO15sQXw3OVl9aEhIIT55O087
WD45QGN7aERMcF9nN2sraGFETGBAeFBhRC1tfWVPJDRpYDBIKCNLVWB+Ywp6bUY5fXtQKTBmPmpo
eGh5dDhkcndneGxKeHg1JmBLcntYZDkqTnJncDdiPEhWTUI7Z3pIU1p1eCtIVll2P3B6UDwKenZ3
ezw0S3o2NWlwM0tLdWhmLWI1RXxYXitqQUFpI2Y0MT9iVlhTTmZTcFVnTVJJTzV+PnF8ajNRJTl5
RWZ1RVQpCnpsaXVNbDVWJlZqVDxJYU5GUEc+RU5vKDRibjEldml5emEqUzl8SDsjJUMwQ1JyfHo0
KT5RKX1UKz4jJFJPemhmOQp6QUZ+R3RJSzlNam9yWExVRDBIQXZwUEF1NCo/NW4rYW1hblB0KjZs
d202VT4reHxFdm57Tj4jQGN9ZlVacV5ANHEKemE1eTJ7PEA4QyhDYSp9and7ZTRaUjhZKHtedFgz
RVdUfk5aazYleEdONFR+V3dFTmF4WXdka0RKJElJZHhUM2cxCnpPcH50bWgoWCE9STlaV0lxckxP
O2Q2QD5MKnRMd205bUdJYSkrc2FSMFNybTFvM0dlcnczZWt9YnxNV1FNNUw4WQp6VkttXj8wX1JA
anBfJUtEZWxVX0s9NFl6UURINzRCcE1IPWcqZCYkKUR1Vnp3ZClAcC03KmJXXmJFQFBjbWdTQUoK
ek1yMnxlOVRvTkslK1Rfdm5gIWtQd1FLJlZAZWVaPy08M1BPR3ZmVTE5NVUtSzhBKXZ0ZGpjdz42
dmtle1UpS2tNCnopeE4+SzRPKnspRnkzcHBEJiRmIWtTJUYzJG48KExqJTVZYnxDSWtscUdPdDRa
U3ojJlczKyFoSCVGakc4dzRxVwp6eChFVyk/K2MlbD5GZnx0dTsqWVVDIWI4dFk8Ozg+U31IaGJw
XzYjT3NAPncqdF4xMlBeaDJqaXklKVI3aT5ze08Kem19anBuZn4+Ki1MYjFuTC1LOC1eO3g3eUQ3
LSFfJD9CNyV4RDdISUY0TXQ1Q1hWM3ozWEJmdHJyJXVRK2BYUkkkCnpUTGIkIyhlcWtobXZkMW44
VTh7PE58KklHNnl5Y2k8PH1MTykzMCFXWjlMSWBheVhAOD16fmc+PUsyTkMmWGU/Zgp6NjRfMylF
cW5OKmI/bjlxPFJ0a2B4Z1lZTVJJXyN7KTlJRjhII21Ta0ZoaW9FMFFAbEY2ZTt8STxIaENDbHo2
UjUKelMkY01qWTNocHNyI2dDYWNOYGx3dXRTa1RnR21xai0pKEY9eGZ0WmVYI1glTT97d359Nl5Z
cWJle2l7R2FIKUM3CnpKZSkzczxgX2g7NClETXcmaWJ5OSNfeXZOTz90OXJNZ3REfDQmOEV3XiEz
eExyQ293R1VQeDYrN2stKFY2IUFnMAp6KG50SHx4ZDBjPW9eV3BXIV9sSzBMT0ktYUJ2JkxpeEZv
Iz5QQy0zcTBZSUopXzs/PCMwS000T2JxUVZeO3JORzUKel9XNCltaEkzO2EqTEpFMyNkfUgkQUs/
cCthVz4jOzM/aUJfM1Y5bEpyYF9rfTZhPjZebyVRYl5UQDZ+eXo5MHB0CnotT0w5SkZjO0VtSGsz
SWFtM3gzKEFWbiEmZW5WM1NoVCNXI2h8PH03e05ma2RCQmVSZ3ojQkt5Jmx8eUlhJC1GNwp6dWZw
OFhtY25STlZZRFVxQD85JExwKzktaT5ONFJfaGtSSWtzKE9YbXFlX1p8WTd2byNSUC1uKVRBQD1D
M2hHIUAKekMxdTRfck88MHB2cmIxbyhAfmp6UUlLNFYmc0ZZWEg+Rll+N3AoRHpybXg4RWxoQzth
SyhVfEJjbGclJm4hQSlaCno9RkI8USRgQUkqNnc+PVU4Q3hgJSlKVjZuJDRzKlNKTyZsMzBhUXRN
PEtAbHprPiEkfi08OTtQOF9Cdj1oZVVIWAp6byR1MlBNUWE2SHhvdEBuaTEjUjtRR3h6QC18UGMp
JlE+Zzcra2clQ3l5UmkjO28lPTZBVDZ1OFV1VmJKSUMtPz8KenA7UklUaj0yZENZbjx8JHMhWlI9
THJAUFIjZyswc2Y0YTgmQVFJQWwtQTdHU2N+RzZldEdjNmd4WGBLKmJYQWVmCnolYzVWRlBvMTJY
e15DTV4odW1RPylVdkh4QGVMP21YaDBCdyZ2cERESEQmeXkwIWxuRXskSWxjU1F2YyVDKjM2Nwp6
cUxVRCRzZF5ASWBGWktYb0BfVGI5S0pvP2woczwoJSl3eHN5RzluNTUpNT8qPDM2aDxCcWJIKkU7
dUc4Q0FuLU8KenphcnFoKlk8KXE2LVM0Y2RiOW1AUng1YTZwYDxfUU90aiQkI3FNWUJoWU93Rkc4
fkFGZ01jY1YqO2NOR2c7OTg4CnokPXFDbWE0aCtOYX08Wll0RFApbHRmQTJ6bDE5eVpSPEtYKWs4
c317PnxKNnFuajVyTjh2RnV7P15+NSVJdyYqbwp6eDtWS21eKWBCIWB9bUd2bDhIX2hyTmMjYDNW
WDN1LURqWEIzI25NWGt1dDw3Q0BQQDhOeTQoYkQ+UFNRdG1NRUsKeitaYzNNciNNO0Q+RGFGJEoo
KUFzNz5NcmNANWZEKVdQWkhPcHRLISF4YkBSNmEkPDQoJSkpWn4pWHt5VWslQ0xACnplbkBFUzt3
JD89Km9TZjlublFCZTw+aTdzSj5yc05RNC1lWl9VK3A+LU9gZWhndlAxS3lsLTRiN097KTkyU2Ex
VAp6Z1J2JlF5YjV4dEdGQGFkTzRLPEVnKz8+cm5fZStxY2o7eUtBVEJpb0J5U0FDXjN1ajwmOFZQ
KjdvZkJre2lMdUAKemorYGV9YDt2cCkrO24xaDljc3Bpem97N3JTeCt5KWtXI01XYEgkMHImNU1T
TWpxVTZqI0twQGNZYCMxUnAwRUVTCnpkNyN9LT84az09V3ZqNGhQNmxzUzJBNG5pJG4kO0xHdkJs
QVR4I2cjVVZCP3hrRF92ZTI3UjdrPXdVfVgxM3JERgp6PFJCdkM/fjlgKDk/Rys2ZS17fUExTzwo
P3dUcnhjZD9md2E2U315eXJPPz02cFRxZiZPQCtDKzxSZ0VwKHdick4KemFjRWwrKEJPJnAtX3Js
JDN5WEAjX1NROGFpJGgmOXhUOXhlO3dNIUcwU0B9aFduY1pWPF8halZPMml5cEI/NkQpCnp7OyVm
WHR3eFEwQnUxTVVzZDREcFc3cEtVRH4ldm5pQDBucl5eIWpDaEdnVXxDPklQM1JsRCFuKVF0SSEx
JFpSIwp6RyNvQ2g7NUt0VHhWQn4yIztYaGtPLWcjS3h5VkpXKFZSc3dKQ29fUy1CcTclcmBjU2No
N2VCWipPRCEwNWs9am4KenBgcFA2O0NXISgzZ294enB9JVU8LSg8ZktHUSUxOWJSQkg8dlh4cDdO
KU4wXj9Aa0U5dnx6QkkmMzt7KHhnRnIhCnowQEJpWSRuQW1zeX56QyhEVVhxQj1+S2YyJkJ2ZTx8
OH5kJiE9O1Z0IXBZanRSOCpSOXlWOG1Yb25YfnFXaigpYgp6KlU5fm5VZXhwYmVPMzNCJjA2Xjtg
czJxQXEhXihgenFsIzJWJns3JE9Kd0RmPz14MUdIQjVyUVImcWA1YTFaNlYKej5VcmsqKUg2RWNv
KWJpR3l5QWZ6Sjl1RytqUiNfUilQKUw4VnE8NT0yWnprSW8pczh0SmN1S2dqa3V5QHJkZVFwCnpz
NDYoZ3g2I1JLZGJ9PngrR0VeejNEYXowRn1ENVhqbVhtTGo/eH5waXRmR3sySVprSXArXj5QRWA9
NWshaVRyTgp6T1dOR1pPKW9qbXQ/cDBXdVhlTWphIyRHPio7aihYTD9TPlhOM30zJSV9TWdEI2ZP
c1k1Oyt8KWJxTlhmYnF8R00KejI5Xl8oTkAleD92NnxQR25JKDxPMCtzPTUobVpTVT5jWXkoP1h1
RT9zcjNCXkFJdl9XZTBEZ1BuVjZQWlM0eE1ZCnpocGswbTB7cn5GNzlMSFFPSUFVKihOWjJ0U3RC
N3EhJCh8T2RuZFVORG58aUYhNVdud2tqZk91YmRTUSF3cyF6SQp6T28keFF1TVlsWnZwZWt7P0Vt
X0dfb2NEbmYmSFp6ZDFBS3dgckUoYkZ7JCE/RHtEMTdQUmVkPlpuKlZgNn5EZSQKemU5UUdkLU5S
LVRrQmdpaGZGZ0F1fDJ+X2ZPOUYqVzVQeD9XUndsYFpyTmNnck4xd0AmNThLaCU4dmlMS0xfaDhT
CnopKDhsaUhwSFBDKGtFSVpjek5nRiM0dCg5JDtsMGprTE9ePXY/YFpVKWxmJjxoTEh+XjwmbDZA
b0MpTylxKW9rJAp6O18tMD45Vyl9dnVeV1lYQlpBWCh1aEZRUExmezI8UnRjTUQtRkVTZG12K20z
TkpEcTJDfGo3Z3NTUSYld2BneWwKektOOCs4cjs1SDJPcSlvWnI5YH4pZXU/I3RyRy1WZF5kdiZu
cW47U1N3Zjg1ekA7QW1iQXdFOVMhbzNrUTQwMlR6CnplS0ZgUmluKXd6JV9ET1JiIUNtRSg0OH5S
Uz1QP1oxemUjc1VhLUYzR3F4QkUjIVRUbmwlWSYxUFA0NUxQb01EPQp6KWFHa2ViZnF8S05fP35s
Yz1+ajR4YTQ/cF8mY3lBcHRQI1JtT0U9RVNMPVR0QmBZNj1aKjk+QlJ+VyU/aHdRX3wKei0zUWRq
amBgKD4jMH52aS1Men00RXJmO2JheE07WndFanMzP2UwZTY4aFVWWXZnRkl2YUt0PUAyQmlyMVp8
UHNWCnp1OXVkVGNldDZlekRIMkpjK2FJX3pkazU8YCFFdT5ObUB4dk9gTXFEZC0/TFhyTyUpd1pl
fmw2MlhAOWZTWiYoIwp6dVQkKTROUVUtNzRpI1hHITQ2WVNmQXA3YE9od1k9P017cDhyOU1JNztu
YFRsVHBRSSQhc1NAeU9jY3JtWWdKKHEKenRyT2pAKzE9Q2ZpcVN8V007fmNxWSZeS35HJDRWNGx2
QD82SyNFJTVgYFI3WUZxTXQ8KVhXUyk+fj9SQDtANXszCnpnZSlyRSMhUlpKc2AjYSlQMmFfJj1J
cmtXWXk4c0UoJUxTWCtRJHUoTCY9PnI0RVdCUmZfR0tZRzN5cEk1Y1BRcQp6TmJkODYlcVh1YDAm
YWY2Z0hVdVMpT2NAaVBpfUZ3Zj8raCptRiV5MEBTe0tWJkFBcGRZU2VzVVEjb015JEFgeCoKenF+
eWpOSztjZF5GSGZJej4ra3VRdjZ2UjklYj44STBvV1pzIVUkYSU5UmE2MCZDNkZvQT0yRnombjtR
fEQ2YTM4CnpfYHR4PWR9TyhTdjVBU2Y7IXMkOFR3S1EwN2JnWGttOTFyRT5zO0wyaks4TVFDTUc4
R0d0cnRVYXtYdEkxflQ7ewp6M2EkTVFHZDN1anp+X0pZO09KTT5QZ2tqVmB9ckhhdnhLMFZ2aXhR
clNVKzZVcjIqWncqLThZY3o8VGAlO21KMjcKemQzazRpaWoqejBqbmhqQXkmKVgqa3M7b1RtV1Vu
OUI1YF5xbUtVfnxkZipWdmVvSSN3enE9U0x3R29lISprbm5TCnpTaTN0dnpXfEZjdmI0ek42LTt0
RCRVU1JXdClyX29eeD5BSCVpWWFXbjdySkFEeSo3aEFpVDxiXzV7fGZYNlFNQQp6M05vUT0qdF9t
PU5MenR9NWBoVjtwKyZPcmx3cGFkJT1qWEM/SlZWLUJBN148OG5wanZ3QkReSz44QUJ7NyltQ2oK
ei11PHZPbilIT2doZ2tUIT0pZS1lIT49ZjA4OEUoTT9KYnZUamBPWmxhPzNYfipGd0ZIV0xePG1P
IT9QQHJjNlY+CnpDTlBFbG1iTT81ek9ubnhMN05ubS1yJT5lZWFtLWlsaDVUZHswd20/YUtsJld1
PFBWZVp3amNGX0E4by02XiM9Uwp6TjMjc1BGZ19qbWBfMlc8cShTUTQhWXVGWitoaUBtZitqbjMj
VUpkXiFgeVhie2dJQW97PHNzJk9nRVRsbyVJfHIKelIpT1RSaUVCVCh5dlFIJmJjVERyV1JleXV7
X3cpO1dNeSUjbE5keUI/fX1XPUArSmtoa3YwRWRvSzNeVWBrbkk4CnpGP2wmX2RBQlgyUjlVOytA
Pj48bVFlTyVeVHpsfUI+Kz0lZnJVQ0FePlladkFlI21MN3NZYiQoP2Z3YWJgQyk1Zwp6S2I+ZnY/
KiFsRilteDk5N3VRbn1pdzglKEEydkR6Q2lAMkxfeXtTdHk4OXlFRDRXUHxuN0hkIUFBMShJVmBT
XzwKeih1bCMjdzwjKz9Ebj1CKVJrezI0VVV+dDBOdSNkWThXIVJIYDMoNExHT3t3dWR8djxELVRH
Wkp4XiFCTlRkcFlwCnp1ZlFnYWN3MTY4PEhGMCFPQmhLYDhfbyl0PmZKUHE/VDxGSzdEMERqaHEy
dnFzVnImT1ZvT3tiJmtSLUNPLUt1dwp6bWNAPmhTckdgVnNidEVfPyliZWlAaD1ndy1Ea2o9U3BU
al5vZXR9UXpnb0N6Vm9FfT48alN5TCtNUiRhJjd6aDUKejJYWXVwWmhAeX5DUWt0X1J+PmtVKy18
WVlvRU0ldlMzd1FrNl5RfFQ3IUl+dS1qeCkkdjtAPms7SHdIPXIwMz0xCnpVM282TT1zWjY8aH1i
WFNsU3tYKlNudWFYR35xfmMyZj5IUmFAaytVVyhKMiNZdDhMNlZ0V15gNzd+c3ZIemNKYgp6bSV+
bDFtVi1LUihKUyZ6KWchSz88P3YpRDMpbX5KO0Y7MT9APGBkITd3ZD05bVomYHB0TkhIQCh9ZEst
ez1KWmkKejVzUjlReHxISVp6QHNuPjdlak9HXyZCbWZ5Mz98S3gpZHp0MUtXKWFPYlEyQWhGcio5
b0VxRElqekwrTTBFdjAhCnpYTVZofFpFfHlNPnhyUkgxJntNO2V5XjZNVz40VmRoQUY7ezhlM3hm
aTxxVjJoaj8+U085YlhNP1ZITXtEO0pHNwp6dSpUfCRoKEBfeFRPckgzaGo+QiUlYXlfSXs/JUpQ
ZT00N2hUeVN7b2MpNDw4Zl9Zd21MKmchUyZSMzJIYntOKCkKelcpPjhaNHZOYjBVQlJBPi1JZFNF
MmZETjAtdTg+bF4xMG1nYHE9ZWUkPyRRUGpPdTBLIXcyMXMrZD02O0Mhbnc7CnpOe2Z4NzVMK351
TVNXNTlaKyZIQDFrNH48UlctZmQrUm17NV9FY29FamJ0RD9GfGxyQXBxOURGUjZ0bzt1VX03QQp6
Q29mJmY2Nj1PRnVXLWomMV5AQVRZRWlHSHI9ODRXYERCcz9fcStaS1puZGMjci1odThFTTt4KWBt
eVl2YmtHZVIKek5zUkA0bVNfdHA9aC1BMzxQTyN+VT1VO0tNQj5qUV5oZDgkSShJQl5BTXtjfF9k
KUZnYFMkakhed0Bra2tpYUE8CnpEYjRBKSh5Vj4mLXM7dV4wfFRWRmA3VFlnNEdXQFp3eGJ3PWoq
bjcpM3FiNH4tWDZgOEhqPTU7WFopdHEhYGlQbQp6e09rRWArenxzcUwzN1BVUkxAaXo7IVk5JGdV
YWJZKWY9T2tvLSlOVkhlWFlWMjcpSn1Xfk9Qdz9+SztMTz40LWAKekY3QUVXckgjZCNRPHc5bW5f
ciY+ZU5wYjRlVmBNYTwrfHQoXm9COVV1RHZebVc+O0x1Km9lSHUrX0J+aipFMWZ4Cno5U1o9V3hX
ZSNNaTBWZkQoUGRAXiFLRDZhQkxgIzU9OylaX3tMay1eTEZxfEo3cU1uWDF1PHZ8NVdoX1JQYUJe
Jgp6I2I0Sl5GY0JPb0hWRCtmZ0NMSURfWHZsKmYrMlpBdWtfNU9HZVlNTVdTI0BKeGRGKHtrV1l1
T14rWittaDV6YmcKejBteVJMMk1xPn5KNXctOExsPzI7Yz1iJEFlS3BsTEprMzF8WldlKlc1V3w/
JXRUcClubXdBK05kKn1EdyM3b3ZDCno1dj50ajtWaW4hWmFBUCg3MWtiJnNfJCY/WVZRTUhrcT9h
WVN6ak55UDBFdD8tSzY8NTtDVjx4YFpYSW5GejA1WAp6aj07Nlh2Z1hDYSY8an5ONyRDUHhsZFgr
NWR1Jkt1KE5sZExyNDZHYE41QDtkNyR0VmN7fUBqX0Q3fHpeY3F3SEsKelNAJE8pO2U4Rz4rQHVn
bDRoZEJPPnN8aWh2blgpeGx2NXs4UWUmSHk4cEAqbDd7YmVHRGVqSkM9d092NG12dGlvCno8Rjlh
XzJrWUN2bHg3XitvJWcyRUo1I3ZmX1hRWlRkdk8/Q0JNYHwjTDNXdnI9Xj9vI14+Z0FkZ1NFKjlR
dlltZAp6ezhaRCVmTlhMSHcpQlZXUUhEY3hLO25qKzZIUDthR1F2OUl7N2BaP0QlPFE8KkpAQmJV
XmZ4cnB0P1V+TX57a2kKel4xJXotLXsoKHB6TFFeNUhLTHc+Jk0reXBDPDRtcyEhNio4SkdeNVo2
N1dgNSskTzMhaThERnBiLVJ9MFIqaUIlCnozRjBJYSNRPTd5YnR9PT16fjtQZUxLcX1jMFZka1Fs
MSFeLVJ3Pj5sITFEcW81MitSUm1vOFVnaXxeN3ItOXpkVwp6N004NGdyKGVUUWxvYkVDJEJWY3lJ
NTF4OT07Nn42Smk2dlRLUj8kIz9iJHZ5dip3VFFjQVRuTm98cSliZnI3aSMKekokWSZLMkRjKDsy
SS11UWohdzx7TUw3KUMwTGBiIXhqJWN4X3N1ckxja05pejdoUWJmVXA3eTNhYml6TEhXd0JhCnp0
b0hgNHFaYFVLIztPQiteQmMwc2QqSDxQbkh1PTU0OU0jKHtRalZreyUjMzJQJUNDdjEoWHc3UDwj
eXpSQD9yJgpwKThPQCpeWiE5TF4xb21Je0NfcyVwfGFpSFJoQjZ9eWVgRSRGZzR3fkMzaFlAfDFX
O1RaODg3PQoKbGl0ZXJhbCAwCkhjbVY/ZDAwMDAxCgpkaWZmIC0tZ2l0IGEvYXBwL3Jlcy9zdGVh
bS9lY2xpcHNlX3AucG5nIGIvYXBwL3Jlcy9zdGVhbS9lY2xpcHNlX3AucG5nCm5ldyBmaWxlIG1v
ZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAu
LjRkYmZkZGU3Njc0NWI3MTFkNjRhOGIzYjM0MzY3NGIwZGU5NTMxMzQKR0lUIGJpbmFyeSBwYXRj
aApsaXRlcmFsIDE4NDE0CnpjbWVJYWc8STZtN2VCZ3loPkMpVzAjWUtXa3xOI0dBPkVDMWNRKnpv
aHt6Jn52YEUqfG9yLWtWKGpXfj5FVlY0UAp6YTBrRD89UldzT3hjNUZFQTlzPTJfbmJMJTsmc2xQ
R3dVWitXIVhFb0N+aVJAa1VSMm5RdEEqMHR9WDxFX3h7RnAKekZjUD99QWBFYHFiZGwzQGhkX3Yw
dVU8R0UmYmJ5fkBSNWhLdTdgJVJtNTI4bUglb31Pdz5QYDNsZkFxNzh5OEQ8CnpYRSpEbDlicE94
Z2NjJCVeLTl3eGQyN30/ZkNgOyp4cmZucVI2fHYqSTQhLTZgbyVqREJLYWFrbHwrcz9zKHpraAp6
MV4yeVR2IT1TN1RTd05jayh9SXE0PGlHQ3RiXyNaNk5iQUhGVVpaIUNeMik2bFNzJFB6QFhxbGhN
c29tYHFMZGEKel9uRHQ0PyVibjN4RzN+OXchMyVoYkwkJFJKfXZ8akB9ZlYwN19leHtjYTBTTV9V
NkMkfDBNOUExcGJyMmUtaWtBCnpOP18qLUJjWW5oPT17UXAqT3BtcmApQjktZXYhKilwSmxZKUdS
SjxgQ2MxbGJ1WEFabjQhWmQxeTs8byolZlpyfgp6ND5DPGtMTHs5QXtvWmVFYnxoO2opJWImLU1v
KlVvbXgmMlkyKEZ8bFBVcD4+ay1Zb31ne1pzJkVsPGxWMXd7b2QKeldCdlU3R09vQmRTVTJqUmFZ
MkE0VCFTY0Y2MXdiTyN+e0M4QXB5MH1nUENkantUaUplJEB0UkcmUW8yTFRVI2tECnpuYG0lS1F+
bXRAcmByY0MqRnJMPUxgPz59Rj9TKGJaNzdXV1lzVnNfe2lkZGdLfHZ8bkdyc18/bU4hcyp6Z21a
cAp6cmRWT2Q3fmhjUVdRUDREbmY9NU55Z1F2M0l7NzltPVV1OFdeKnxwK0QoPS0zYGJjUWc8Pn1J
O3Q4JjN9ZCh0eUEKeiE5VT9ydVUrRk0pI1Q7bEhBKmNjVmwzMWJFRFkwcTRBWjR2JDI5UV4jcWA2
U3NCTjdQV2plK1AqIUh5aG8rR1pRCnpgUE1JN1BLVU4lQXh0WFliR3R+R1k+fURyaUsxNDhgNFEq
JiYtZTMmSCs1Pk88KzdaTFhabzgpTH1PdmxnXnpgKgp6eTRvdTlWaGJQZHJ5S0tCUm9nbEg3YVZ6
Mip7akdWOWVHcjRpYVNeOXw3XjYya3tLbjlkPHktVD0wO09JVWhyZVMKemN5WkFUOX1mb35pLVoz
VEMrPUZMbVlPbFZsIXF0M3MxUTFgcHtAPkYpSzxAOFk8dGYzT2p8N2B5YWpNe2pXbmJKCno5flZh
e2lDYUZGYFNvWitwMCRscnRJeWIzcX1DZDc/KGZhYGpzP3cyX05ON1dLUD9RWjMlfCVuMylPd3dU
MzBLcAp6bSElI207cX5DUSpOYHBYXnsldiZsI1EoTnMoJHQkSV57SCRfIVQjVzdXaXUqK2FYYD1E
d3kofGdHRUQwRTZ5JUkKelUoLWwwM247ZTg1UX0qZTkwZDckX2VzYztYRG48KFRROUJGN2skXigt
IyNrbTtaXjxWN3AmVW1nY14hNmI3ZjRMCnpqJnJjcF99UXFUWjU+fUlYWGlZVW5vM21VVV59YD10
KXhGV2xqfSpYdmBHOUk7PytqTzNTcmgjKTZSQ2M+TylpIwp6bEchaGVackkmYDx6XyNuJjJ6cmdx
KVdIWnV0JW9CaCMwMkB2bihXRm5lOHNvN2w8MDJWNCgmYjR4WSFGMkhlUjUKejlRWThvaCEkTHor
cypVRWcjRHJoQ199ZUFRc3E/bVVnLVQ9MF91SDVGVShXZFQ9fWx7UlpVZ0J6fEJ+Z3Y3PDw0CnpH
dTJkdmJAYkwpYHhsc1MmX2w+cTZXfWNKIT1xdT44IT1FOFB4Tm87TH5ZfHwpdll8Y3I1NGBSUD1k
czchWlZwdAp6e3lLSitDYzJJcjRyQkVHKWtyQDc+ZjlHSXZDJV5+cmhsSDRneTNxY1E7aUM3ODBM
R01jO3V+cVBJNVVrM1c5eXgKekxUWn5pWEYjTEVFeiQ0S2JRR2Fnbz5kIzteP2ItdT82aFl8d1VB
aEF2XnRDdFo4U3Z+NV9Mfms5NEFyTnBnXmQmCnpSKmYoRGw0PE4oTTA1fnNqT05jJHktJHE8YVNu
RUk3SSFxWV8rdGk1RDctaTBnfnNoQ1czYjZUUWxCaXxkVjJkQgp6c2o0e2FieX1XXjJ9YXc5Nlhq
NXdCMT8+O3ppcChqQ0d6OT1mP21EaGwwcVl8V0A+Z01GVWBURTtCdk5IbikoSVkKeml3R2s1JGBs
OXhaX3hxU01wfClqTDRVSEs1bmc+SjZiMjxBV0AkMXZMQXVAUSpuKlpGYGMyPSVgYj0tMCZOZXds
Cno8b0dJNUslUlBCQlFAMWY0d3Q7Ti1qbDk3U2dwMzVgQ2J9YFY9NGRYe3J4a2RYUWskOHp5K1dA
Y1hlUXlWJD43cQp6bW9zSmgjZyk5UCZPUStHbF5kKXJWTlNfQkRrbEVaaiowd15gSSR8OD1XUjww
VFZsQz9qdkNBU0c2REB+cTYpfX0KelAkTjN5amZMYVcoYVYtcmtQO0dIIWpjJks/RVljQ0lqXk1i
LW8kNkpeT0t8Nit9WCFSQV9ganEtdnlpUHs7SFpqCnpoYTItWnNMYm0mT0I3NUt0dk5iRE4rYGoh
UTJhYEJHYDcwWSNHU01eekJOVkFjVUZOWlplbCQ1NH4pOHVFKWF2RQp6ZTR3KkFtM2E3fXZnYzVK
PFgxIVFaSFNrUUROY3MyV3NIZVFHbUAhc3NnODFhfDRmflFQNFNiWVFpU3V8dmpTIWgKemtFTnk+
eVR+S3RKVEg4N3BzSEJvX281amc8bTtWbHFAMT9eMHRNUmkqUGQ+JXB8dG13X3dZN2o5ak8lQHJx
WlBwCnohP30rWXZ8dGFFbT0yZDU/R0lDdzNQdkFCSHRrOHtLLSV4PndtZnc9TXc0VFlWSG4lfStK
bHV7S0wmWWloV3o5OQp6WjNQPHNmV3o2aFNYTnVEbytxPXxzcmljOTM/N2JgYztlfjY8a1d0U1pq
UXdkR147PFoqfFZ5KGRycDkwQ1piVUAKeiEpb2dkTzs5ZjheTzI0O0l8Z1c3Ui0jYzxNQXQmNz0p
akQ+LUxBM2RjTHM5PkZWPWVGMzxIQDwhKyVFPFBad0hmCno3fSVaRSljNzNAOGU8UmEya2U0I1Vs
Tm54aU5CI1EzQXRESlhLNV5PJV9PVjNAa0NJZDE5NFBUYEU2bzRfYytXXgp6b2kwWkk8eH18WVBj
O3t3U094NEZxTTQ9M208N15GaClZUEdQTzJGLXEqNUdNJiV+an1BV01yVGRkMmNVK280WkoKenVa
UzlOYHAlYnZLSSk+PVReMUV2TnE9YDVyZ2t8cXklfUFLUEcmSWkmNVV4NnNHeGhPWG1EJU1eRiRI
SHpzX0EhCno9SC1pPFJkTypJRDlCYmNpe2Z4fTYmeGBSajYtaFRuQyRgWTs7bHsmRno7MTZ6UVct
X2tKRTUleWZLfSVXMHIteQp6SGVMRTNBaXluPSV3T0lYSkpBSUB5MDUoKFBJV3t8Z0p0SmR1UzJM
SlRYMURROUB1d210bSh9REpTOE9TUXJsOCMKeilBRSlwOWl6MUxeaClEfFM5dz0lO2BMblN2WldY
WDtYcXtXZ0g+P21fI0VMKWZvT3dlNkhjQXw4VXtzJEV1cVpnCnp1PGJtT050TEBnRGxgKiQoVCU0
JW8tKHlJUGEmVlZ1YVNQMGVIQVMkcnQ2WEFSSlRpNEpDTXZTSyY/S2s5PGEmSQp6U2NPdEBeZXtC
a0Q/MlBndm1CO0c2LVF1aDtJPyMxbmQxMVd1TXMyMTw3YVlEQjF3Q0FpY25zQmQrKkgoX0A0WEwK
ekZqZldfOGNONXkmWjNib1B5MTVZZTd9PUpJNW9qNDFtKWNZaGw3XlJWfUEoQXZYcmZLPHs4UGdp
KDx6blcyZT9ACnpZTEZqNHBxdDFwYks/XzxtZCEwNzt1SlNuWCo8fkFYK1AzVCsrdj98N31DbTA9
UGA4SVpFOEE8YFJRVGZQNUlnMwp6TUBKUSMpRXd1cHJ0N0I7VVR7SFptQjFSM3NBTWpLYFB5Qkk2
UzlIV2o2eH5zSHtwclFpOXt1SnU3cztxcnNsQDcKejROfWlpaD5wRDB1MiM3WVIqQEN1I0lncFNv
d0tZTTF5b1VHeV4+ZFZ5THs3emExeTFePlMhQi1eXj94LSYhOVp7CnowZnhybEtwcHx9cV5kRExr
X2c7ciRhM1JJV1J7Znxoa2whSlMxbTxQRF51dGNTNXFVMzJFPytmWjFeQTM8M1lrZwp6VFg0Jl56
RHlGTHZrb31vJmwtSCl1NCFOJXl4eTl+SWJLYStqdztZJUJTMFVLVUhwS1BrSnNSYTQxRU1vdWN3
fW4KelpEYnR1JE5UUzF4KmJPeyRiV001ZT11TGhRdSpyI0M2OGlXanNFO3hyWjx+XkdJKEM/R2tB
WDR7ZVhRP2J+VHc5Cno8Ny1WRlJuUkImQE5yR1pkUH1vPFdGVGB6R3hucm9scVBDOSRuXmdsS3Fy
UjZ0JE4zMi0zUXtXN21gRVc7cjkoTgp6JHl7KFJafGAtczBnP1B7eHUrT0JKamlGZDU9aVVDbnw5
JHEkNnN4MzE0KytoRWZXfT8pdmtTQUcqQWlCLUljNDYKemJxPjdudyVifm5lRzQlcTAybihjbCsl
bDdCIXFRfmMhd3BNPVFEeVJNJXNwT1Imc1FDVFoyXmtiSig7SkpsZDRuCnpLU08qUShzPkopa2tk
bG09LXJNR2hPMmhxSkx9cjlwZ2VTSjcoT3gyY1F+Sj0qVV9PaHRibWx7eFJmcmc8WCpNNQp6ZnJ4
QTApZVhVVSo7ODtCJCFBcGo2UFhgTSQhQ3g8OHYpbCh0Q0tqcHh1e1V+NC19VndRSjtgTWZfIzsz
aGBkWGwKekVmfW15WSFuY3lBUj97SyZCUz1XP0R2Wns/SSFsTk1JaUR0TjBTX2FEdE88PnNKSWBp
cTh0Q2QydEtERGU/WmRACnomKGw2Z3ZmU1goNUp+KU9lKGw0YEt6cjclNjxGTnNSSlZiI2UzKWUy
I15uNjcjTWpGfmZGKHBKMGIlRD8kempZdQp6e3IqSHY4M1BOPVZfamkyTG1we35JJjc5MGk0TWZu
Sm96MkkjZD0wTD4zYUxra3V6QX4jcE5CPSlUZU4+dUZRKnQKekVOMEsjWU43WkhUITxTYEFYaUJ5
ezhnSVI9SV5HZ150TCNMSytBMm4jdSpQellqPDQ4ezx7fDNWUXpOU3BKflImCnpSPCRZMFN0TDNH
SlVlNH0ofS1tY1pIUmMjVTByYnNmSX5yYiVsY1htUHZWcGZEYGk/d0MlU1Y4MHZ8dzN0JHtPeQp6
c1UrOVI1Zi0jUk97c3hxKUB6R3F3N3prQWhYP3Vhd2dvcUF5I2V7K15mK1BkKj0pQHpZSV9zQ19E
O3kxbWw7QlAKemQ0dHZUIyNAQGAzLWBTLUgtVF4zaFNjakQhI2FxQEA4dHFHNVBHfiZ7TSl+cCom
MUhRRGtfWGJ1Oz5rMllse2B7Cno9KDFrMUR7fiF9a1V4czBMa1VxN1luNGZAKD56JSZ0d0tFJF9p
ckxXRDFOZlVyO2RWUGdCdEdiOG9RYDRiWCNTUQp6OCg3ZlAwKXo7UzxLYW1+WmlHcCl3eFJxbSoq
TDMpZG5PPEFPRil0YWtvPElvZXR7Wm0rMDs3NGx7Q1pqez05MXoKekdMVX5EI0hfbVB3am81d0F5
akFmKGJja1JJM0JeZV9WeT00XzNzVlZ6dD0+QyY2fjFlK0xAJGI8VH10U1N1ZnxJCnpaa1ZKJSFh
V0c1K2RiVkRTR3hlNSolJFYyPzRDcmArLWZ0Y15LT2t1PyE1c2FwOUU5K09fSUlTNkA9JDE3UTQk
Ygp6QTNLXjk7SEFUcGApKSRXWWtfZFMpfkBqUU89cyVhYzQlMyU9MEE0UU9abTQhTisyMEcpTFhA
NiYzVVpMWCktJlUKelZJJGw/ciRCX1h0TTRsJDxYJl9PP3kyRG11UUYxdFhzdFRlRzE1RG1xMSpP
dUZCdUBGbnpTVmxjX1I1VlZmVUVmCnpDPkh0Q1h0clAtRzdSTjQkWlpLejk0UHp8cFZGRXBmezJ4
djJWUTVVaEJhRnxyRnNxNlJKeV9YcGtae2I7TlV0ZQp6b0Mwam1XWHJJKVV6ZEJEOXRpQ2JFK0lh
dWVRJCYoPWNtNTlwWCk8SzJKe0heclcrU00jTUkrU2lSJGpvX21zTF4KejgkbmtfTUwmbTJVYnNJ
I2cjUVZjdmktQWVGVlZtXykoaHdXSkI/VTFsWStFN2xgPjhMNSRNd3tAVGhHcEEwYm1ACnpANyYk
PzVmWTtJdXw/dW5xT3BFQDdDUUV1bGM2NHpXflRCNTBTUT19MXJYWkljKThqV15VQmIoIXxiJjZW
KjgpUwp6MUBHeFRtQ0goe24tdlpeOWVPREY4RWtaV3RgR1Vpe2YhIT1yUihaTClPVFR4cGxhc0l1
UUc7UldydSV2bHhvUj0KenN2YGRQNXd7U1V3eSRPaUcxbEw7NEc5XmNEXlliSilzN2xVLWJZcH1E
THtqb29laCsmdTBjTEtUX2U1S0AyRnZBCnp7WGhxTGMjTmEkTDt5KnEzSHxXKXpLNmV1eCNWVG5f
RDApU2B3Xisqd3E0SCEoMjgxZ2leUXYxd19YZVU4SmE5Zwp6b3dDZGhBe1U+IzVLYSZoWio/bj9X
SXYwb2Z3RSN4MjZxWXYycH1ae1V+M3JAT0dBdkZCd1BeJWMjWDREITteYFQKekZLezVkOy09fVFo
QStKJDArY2E3Y3FBaTFART9pdGNZOHF4WDwtNnRgbj1oJEx8TVVvMno9MCo3fWF5KzFBJE5pCnpI
UVlVQ3VWI2xrdHtXKER6fEI1bzhyejl9e1lVSlRYKiNXOz5QdDhaIU4xV0skR1RCailyJE5xP2F1
dVMobjE4Tgp6ejBYM0UjS3s4e2I7STVYZTdfNFpXZF9YdHduUEotU2h+UHFgeGZ5SE5YYks3IVlh
TmV5N150ZHhhMm9GO3c8SFgKej1rKSpqMjd3NFlES1lockE1OzFJRXklRDdUSUVyZDJRMmple3Zm
aVQhfERNQGhxV0JUdWdzO3pfeSs2NVQmPFM1CnpJYEpeam5Fdj0mXjFHV2o1SENzN1VrRGBqUlRQ
QCtPMyt6UkRRcDQ+Qm9JQE1Zb3JkMllHZEMmRjlFazxHbnhzJAp6Mzs4TXY3fnlzQ1FCYDFwVGdh
YkRxI3peTytfOyRrTXxuISVBeHxFR1pGP01wPENaRHZBJXlsTkFrZWVuVnE7fmkKekNGOUJ7S2tZ
eURAN1c7MDF0UVpsPz01XjNPRTNhX1dOTGFPNCpMV0xRWUJeanRJOEApYGBKaU04TFElJTFVTWJo
Cnp6UHpkLVNvOVFAYnlxQlBReWhNMlpBfFpYaHoyNWdjNjlZe3lqQipDI1p8YHRaYjIxY2VHTWB9
NXtmXmFOS3g0Tgp6NmdhR2xiMlF5MnBRQ1V2ZD47KGs/VUc/Y2ZPYWg4bUZedUc8M1BBJU9ARzFp
QmhQUXVYck8zY15UOFB1KkBqJSQKeityaVRoTGglZ30/Pl5QYTIzJEo9RT08ViolZnJYd3VJO1h0
QF4rdTMlMHopTW9CbFV1K1lUSmhFKmdYbyRYNVglCno5WmlEPT47NkMrQC1WPzB0ZEpKWXlTZ1A9
LUU/Vk9WNHReYHA/WWNlQWcxOGg9YTRzU0BYWnlkJXVKaFo2Q21TTwp6V1hvR05FdVIzcT1xckls
RmlwUDBoamRaX0h1NFglYWFtJFBQP0R+VjVjKGVAPmFgdjV1N0pLLWhacT9vZyFeaU4KemtSSCNp
Mjx9QSUqZityWHpscWJYTGRrQXxSSSltbWs5NDVSdURmYTFBKyt4MllgRHtWTTA1VWV1TUZqKHt3
X2FvCnpBWVlqUCVQJmhYJnN1QXNtVSo0TkdmIWs3a1lSRHRVdFlxPlliQUAlKEcqdW9hMGQpYFk8
ayU4eUlTVVAzX35FRAp6Y1lgQmFzOzsqNSt7P0YyajI2O1QxJSNvQG9qfFMpdyk5Kj9TfXpVUSYo
JGBXVlh0cXEwTGlYXkBJX3wwTUNTRGgKemtYRmFzPmxLRClIWUd7cGJxY2AwOz9+b2FtPHA5JVEx
Vnk8V1lecjt2diF3KWchSjloRWxIX34pOHJFMXwxbGlOCnooZ1NAaUpYYmh5NkgpXjU/eTZDZVhs
cDg5cy07Y2h8SXx3Z0J4TShjZW0oLTZHR3J0fUEofj9vTTZqKC1LJlh7JQp6emFNcElVMkAjSFNT
OylaY0pwc0sjVjBER1BGZ3NGRSQpQEw/cTFEfntHZFYxXiU/amF8S3FFJSt5Qk83IVhFMHQKejc/
cF49U0BeJChnZVU9KXZnakFTWDcmUCp2VnYoXlQ9NUFgJj9RLWNqWWgyekViQFoleD1oVVJhbn5V
aEF6PGIwCnomMjQzb1BFTjNVb1NibHlTJihjM1hIYDcmc3xRNH1rSklpZ2IzVEY0MjQyfCRCWmFu
I0ZtRmsrSmIrJVNoYXxkPwp6a1Y4UFYyeWJFWiZGfE1zM05RflpUVGZVSEZ3QT92akhpWjFVSzlj
Iz4qRlloaU0lM2ZPSUtvUWtXQEZ0b2VYdz0KenpnbCtXbyNpQW9ORXc2eFg/cVBGZCpySnkqUmZg
fFM5Kj58VmdKViFyZTxhWncqVT5jcnYrV0Itdk5NS2s/QHheCnpMVm9FdWdLPUZVLWVPc3VMLVp8
MzI/I3pfbWh3fUdTVjNZSUFZSH5XR0pJfSYtQmZIU2E5NXk5Z215TEc5VHhiaAp6ajxLY3lRfmYo
IWh7SzFMdz8jIXJlbERBNTwkIz8/bUpVbUlBaTYkYXJJbExTKnc4cCVVP0hTMU1ERTBQfDklQW8K
emE7MUN3YVFZfElIQHBFSVIoWUJuNFlGX1UwMF4mOCtyZTRPS05kKGtLWF9wKEAjZW94UVRgaH1U
WEBwfXUoWWgoCnpeO1FpKGhAYm8tZks3fkhQZFhUOHomQ1U8KCl7JkMwQEFWcHF9VHtfR3haUURU
dTFrPU11QVBnNHNLPH1EfmtgQQp6eENZfEx1Mz1COz0oeyg2O3V0cDtCVklIbC1HI1g1VSV+R3w1
a1ZMPWEyeE1oUGUmZ0FRVjFrUjJCM0pNalpvcDcKemwhTEQ4KnlWIXZzN2x2clpiKl45YXdxMTd4
YmpgeXIjRTZPQnpwOVQ/KzV7WFRSK3NYXih2dURURWVhSm9DKCRuCnphUmdEMUpYcDlhMmNAPl5J
KS1eTnRLVlZGTl43KUxGWXlGSzQkZjVEJHptNWVtX0U0LWh5ITxjTkxKUG9iO2IzbQp6aTAlYDlj
bjFSV3k4SXQ+ITFVR0RFYj5PVGhZYWtQRVpxJVR5cjg3djFadztzZ25WTnJMZVkyYHFBJVVmQ0xY
ISUKelUzUHsoKiVMNTJwfjJ+VjIxNEEqQjtwLVh7dHdSIyg4Z1lxOEN3eH5lNDghSyorOyN1Zk4w
M19nUjV3JkBDVGlmCnpKPV4tRlV7cTRFSXl4bUxPQ0lOSlNITXNLMVcpYGh6PH1AaS0hQj0ydHNn
O3RjbipEQHFNQEVyc2ZRITxiYTl2Vgp6KT9GfmFKaTk8SSQhYGlzM0BnZyg8YnwtcG0jR2dLRGYl
TUNKI1AqWGtPaCh4YWtHKU5hPHkjU248LSprQGYwa3MKelVeMitTJkNyaTNjc2ZySEB4NitXQjdR
I2NlazZPTjVgd05neTdPZz44fUwyJUdWVyliZXNUT0ZjQXZ1IU02UTEmCnoxRGE5U3EwODxfSXdK
b0JxTC0+KyhMcy0wSVg0QHBwd2lMeGhvJCNWWHo7RzgwUWo1Q1hNRTJsRl5JaXxLVSU/PQp6ZmVt
a25zJlIybkhSfkQkJHgoZTZhYDhFIUVuT2wxYG9uPGZDLWVafTU4bFNyIVI7aXghdGlBaDFmKkIm
elIyIV8Kejx2P1RhKXwzamQhO1V8OUxrO3FCZz1BXiVYXlk0JHdaR1h1ayhFTS1TayNNPDI5VVE1
WUl7JShaTy09UGVSJEl6CnokRWZJTy0wVn49TXoxKTZPUHs3ZSlROGNyYl5ne08wVioxKnlFR0hj
bFg4WT1qKE93WXV5I0tAeStsJi0kXkpXPAp6YzdaaF9LdSozdVBKY3psJTFufFpAfHkzNFEzQzY4
N2V2P0liVDgqJj1RUDdsYXEyc1l3XnopaHBVP1E7cWs3UCQKelg3OSRCOGY1ZFFMKDcjVjU5eU4k
aHA1fTE8KCUyNmI1PkBSJTlOWCpuZmhOTnJRTyYtO1EyTXl1ZEdNQmBKOzhZCnpOWERGNnEjbjt+
SyN4Yj97WWFXSS1eSTZyWjghbT83SUZfOVpCTmZsRldYMSlAUEpJbGNJWDBzaE8jdVlVUEw0LQp6
OHxlKUgkZj44OF52NkYwJC1VQDZIVDdALXdHdVMhdT97eElPQSpiJCM9YW8+cGBeTyFvJXZ8dU07
cUErQTsyWDQKemImeD5zU0khblp0aURkNXhlNz1VJHp6bGdpQEFzJXs/NSpSNy0jZTloa0VkaT09
WkNvS2VYVXBwTH0zOWohTntSCnp7OFRYZEdmT2JxMW9LKz5pYzRQLW1wVl4oK2pxdTxtM2M0UGx+
T2B+VUZHd2JaS0U4eDR8Z1NKWnc9QzBkUXh7Kgp6eDY5R1BeZjhlPFVtUzFlaVZKZGJOQWlTKmZa
WC0hKmBtRlZLfFVfIXI4VVU7VUJXeG93cXxPYWdkfSppLWNDT2gKenRSS1c3WWo7fDI+M3NAXyN7
MH5Gam5vQ1ZTLThQUyRnbG8kVGJ4QX4lNTd0d0lmVyV7QnJZeD8pRypLYyV1ey1nCnpvY2RFWitS
bkxXQk10SV43OTNfbVpNZjEwY0ojQkJVK0A1QUwjR1klakZAQ3xNNVY9TjwlTW4/MnBSaE1wR2Vo
Rwp6RH5ydDRudFdRfjckZykyaUFlSjMpREVkZ2ZSRTFuQEdnTTFsZHk+RWpZVzNRSj5PNlZjUjRA
QiQhbDZRNGZeLSYKejVLWCRrSiNncWpZKWskZmNzOEUqViM9SHFlajBvZEA5T1RNVCozdSpGPEQr
d1Y+fVk2RnEtO3R5KjlQfFk4TihPCno3cUAwVilpaFEzTS1BMEw4UkE+PiZYYHpMaSNuYColeEh6
SSRsYDN9T1NFQ0VCOW9xU0YmMTFgXmVGKVNfNTxvRAp6emR9b0F5STxtbGRWJDNubnxtOXd2MUEy
KlJ7RFJCaDZ0Rj87PjtUSThiaDxqOGpHZldXM1B2VGdneFgqald4PHsKemRxZD1pbSR2bSZMQ3tE
NTxMU3xSZF5aOEFZfXhDZGI2dEdWSX0hNDNMUjVCMlFzQFdjNFkqPE4hNkI5UW83XzR7Cnp5fExE
ZTB5WEsyZHBnKT9jR2tRaHZpQVBJLT1pKE4kSkZlTl4jTnRMJUpIRTFZdHRjMGJPJT4qKnsjME9x
I3R2KQp6I20wcSE2eE9wYVNsYyF4dDMmaD5VZjVLPVdfe1o4P1EyI3Vyb3poRklLQXJafEdvPUF0
N0lJbWZ5KD4tXlIoJlUKeis5ZWBUaXRfaWlafFdeX2slQFFzbkc1MEpSV19jJSpCKFVfVCZ6U1Jg
VWQ/QWF4NSZKWHNPeDVDOTdkZG4oc098Cno8Zm97JmhaSUdXdUkzbmxnM19Jdko7TnpOK0ROJkkl
bDBhKCNjdCNvIz5tYGkxSj9hWEZPaH57QiF8aytlKTVfVQp6JVgxaW1DKnpWfDEqbDtFdGNRZXdU
RU9ycTc0YXRBaH47N1ZlVkxfaGIpPnxYdmA3QmdATW59c2pUe2pFUG9wMkMKeklfJE84QCkoe3U+
NzZRXyhSZWJOcEhTWj58RypFYjUjcntCSV9YanBpVkFqVGh9JlpEKTNuOH1sNFM3K2QqPSNTCnpB
diZZVUdyRXZoJCFfYmJXcVhOQkViLXE/OCZCZVFCJlJ3VkFCQjdkUmZJNF4qY0E2MTw+PjhUPG1H
bkskQVN5QQp6YT0zQFFVUF98Ykp4OEpnR09EdGs2Xzw2YHshUElWOWowZSFmMHNiI2BxWjZPeUtW
N29hMl9UJS1teDJvNHBXU1EKenRoaj5mb3tsVXJuUDVkYGcpKj15MVpJRFMlXzRreVZZSkFTZ3Je
KTtAYEd7MWxyezVtZCFvbHo9UEpgfTtydnNXCnpuWXdLPXM8bVJTd1k1KGtTI1YoKXA0cndtN05H
fTJ5cV92Tmp7OS08cCtKaENfbGJxbHdvdiprYmQpOTxOdyFgOAp6cHo4aCFIUEthLS10QGFmKkwh
MjYoe05IeE1fJVUhKVBmMUZ7I1pwc1UpTH44S1UjJnVsZG5fLU45RyY5TkxgVXgKemNTe3lJdE5l
bkxJPGVRNXg8Nmd3YH5yaiRvVzFkOzdTKVJHUkJsV354Vmp6OTk8XiUlJFF7Xj94QmIjPSppI3El
CnopWEo1fChFe0dUSiN6THVKR2F9MjBxbWJPcnNCfExqZlZRO2hrWVJgUXhaQEI+LT9vI093e2hA
WHsjNCNfdSZebgp6ZjZ3SWNWIzJwUGBnNjBIc1RSVjdDaXEpVWBQSTZwWEs2bn1Ick1DMGQhUnd7
bF9temg5a2l3KFp6UWthbmFNbHkKemt5MkRaVVBtTVZJfTxUYHhJQFJyUnkyLU9QMTBZQ0RHWj00
JCFRQzx5WWlgPig4antOYFJISnpVfmM3YHt5bl9jCnpTRzc2PiN3KFpRLXBCe1clNjVQYzApTzIk
NlpjRSk2czBPWl56aUBYbyp+TUNiNVE1LTtvQjErJj9YRitnZExmcAp6RXl3PDhoWSV5cyVwb25A
YmN9QyghZ2dEbUJEJnpCRDQ4ZjZffUNiXmlhM2tFe3h8WU5CQUZqMVN2PntRLThuWFgKellGI2E7
eHtEZT1ffVdMfit0Z2l+MHNqY1YzWCElazExcEhoJnw2RWNKcDVESENraHB1eF9NZTZNYWIwIyo0
dGQ9Cnp4dGdmd1hAJDN7Rj9VPW1nLTB7antEe14oTU8qclRxZU48WkBVY0smK29gI0ZZQUB6cih2
USlrIVApRnBIR35WUAp6VnxFR3kqdkxoJGN4UWMtUUp+UD96MnVWMDJ+UztrekFkZnwqb0dDfHRq
eXl9ODJxYDI0RTFETSVEK3RTKmNnPiYKel5oe2k0TEZEZ3tPNG9qcWUza0VjYzlePX5tQUp0WUNu
P0FUWEhgNzQkMj8pJVRxdlJhM0p6JnNAJEFwJF9QcFE3CnpOMiFsbl5ISikmM3I8PFNnTTwkSUlv
fFh9JF9YY2JEODVifkJSUHk4Ti0/WD9gLStpMEkrTCRgT2s8Vit0JnF6WQp6RVF5USVYVzstfTsz
YThpakQxaFgjPSs4UmNUdDlPdGt9YGBMUih5NiMlMyheVnhxfGVeTFIyfTYqYD9kcF9rSDsKenYj
SG9fK3JhRnpnPF87YHtKM3N6YlhGPGFFNWE2UDJ0cCo0MGVSdFlIRkt9ZDswRWtsTik1JCVCSFB9
X3J0dW8tCnpvX1lhUjNxQWxmWVhvKjR3azZ0NTtSbytzQTFYNSl4XiZRTmU+eiVyUlFfPW5OUTM0
emAqVmFoNlQ1MDdHd21+Zgp6U0R4ZUE7N3oreHRaWT9ZVHg5SWpadzY9OEBwI19jRGJHVk16QzRy
WWJ9Zko1ZD11fDI/VSFRaXZ9LV5RRCl9P2cKemI8VF5wZVk8ZzFCSms2MzRBWVdkcmVgc1koYD12
b1ppWiVGUGV4QjxoZlFqOHorVkZZcEVaS3lnZDQkQTcjQnJHCnpTYHsha2BkcW5NUk9zbG5rK0du
Unk0UkIzdTFTOzlVZGVeWTIkOUgwbWpQT3FGdUZDNUBzfmNeTytARkNPWTs2Jgp6Si1wZ1QjZUAy
OV9Gcil0UD1+d1dWJjNMNlliMilWNmkmYkM+VXA+WDE3TChjU2YhcU51KX0jZykmY0BqeThDJXQK
elR9NiNEcWpFSUVXflNLdWRzZE5ZUHUoNiNDRXRYSEVventoQzZXQl8+OWBKTXpqaj54USlhT0hs
TEU9MlF7TXcrCnokRUJ0KWBZXzRpZ2VFUXtWX3xKQShEUTlmVm0+K1hWcVE5Uj5AZVA1d2VUe1Bx
Nk4qUCVxZ1NIOz9GX2AqNyk2Vgp6MTtCbUIlMjxvbVpISjJ1eXpINUUtVklRT1g5X2dBdjlaQipE
KmJuRlpaU3N9JW5zM0R0SVJwNzY+dyRsVWJUYU8KeitzeD8rJFhBY1E3VEdEbmJuNj5aVSlFOWoz
bXFtXmlSaDF3JnxRUmQtbD1aUTY5OVpyNj4zRCl1U1lyaUAmNmomCnpkIzE+N05IdFdwIV5DKFpr
MylZZTYjdWhvZDRUMlZjfT1hfD9zWWNgb3A7cVU0PnU1TGY8KHk0ZXdqSlg/fkpjPAp6Mz9neUkx
alRnT25wK3QrdUEhY2F7MkhoaHhpXitVZU9BRmkrUCZRWnhyJj1JQl9TaE9MUCtaazxuUmxEPXpe
eDQKekY2YiFpQlFsfDEoeSM4fER+MCg/a2FaMGVIMmM5cmB9QWdvXjJxS2xmJHBzQG5wNjRWK0wk
V2pmS204SVc3QkooCnpyPjE3PT5SS3NrJSV7amhsYUBLdEtETXslRW1MPT5EVnQldUU/UmhfYG1l
bFY9fH4zdGcjejFjJWA5YUB2OVc9Kgp6WXAhRG5wT0dwbDtTfmJFPnFTRmp6NXJmc3JqMkFfdntp
PFI5K0U1el9qIUtKLTE7OzJjWUlyK3l8UyFjdWc1PkoKenFOJj5HV343KmNAKmtBVDczakpMdHxU
SmFWNjgqSjw8N1JicG5sPzRSNHBDNkV0KTlAWlBhZUQ1ZUhxKlVXZWU/Cno5ZTdmZnlma3hEWTRK
Qn5qb2AmZU80b09RQ2JyVnY8LUIxK3c/d1BYaVE9dEp4OzxkVTUrZX1gJUwrVldnRiZMOAp6b2ZH
NHU4QHhWS2o3XyUzfE5RKV82QUZeOFN5ZlNHUjhlWXYkVXpOQmhDN3VgaHdMazd1NWB5M19DYHs+
cTVNPkIKem97c0l7ZXdnSTJ1OEtJd293JG9+ckQ4P2UtMG1kbiM0VFdrNm0wYW9WfnNaKXdVZ2I4
TGUjKk8yYnQzUUlrS3B7CnopSSFRYCVJbm07eShXZSE+bkNVUVBsezA2Z0g+fGpScXlMWjZVbmlC
Ryt5MjVlJGd0aWpjdGpgWT4wfVZYODZmWQp6QCpRYnBAZlZtT1hhKDt+Y0MhY2RxVWhVfXI9WlF0
JWJBcmNeKkJFUFVYSHMke35VaDMrMzhZTmUtWHJIWiMmcnYKek1TcHNjRGF0I354UE1GajlNO053
VmNndGFoZlEzKldBYD5rUzJYOGY5ck1HdmV4WkV+WmN9fFI2WnFCSjRpfVV3CnphZF9SYm5fcmBm
UX1iVjlTRC1TK2hTWDxNdmVrfUNRV1lFJiF4dUprUUczUWJaRkp5WjFNPjZidHBHUyhqeiUxdQp6
UE9DT2piN01hcnV7e0Y5MUtLSjBkM05EYTZKSk5MUVJ+Tm96IypFKCFJNGIxZHJuJXtDaCRZP0Nr
NiNWNiZqMUoKekJDYER6V2RhTnY3a0k5VkBJNnM8LTIwZUZxVU9uTGhFKGA3bikxMVQ8KGBmVHhi
K2dKSS0mNT9IbW05bV5LflFNCnotfDMrVEJmPjtFR2o1JElrQWpIfXdaUnAyZlEkMUI+SHZzdGRC
O1JoQDkrZj9EK3sxQG15ai1uSXM9fU01JCRwdgp6S1R1PjRBclFgISt+b0FCM0s3JSFPbV9OZWQ2
YDJHYihve1MtPTxzRkVFZHxgbmBzK3ModjYwcHhvekZRbSo4JUoKej5sbjlNOUQpPHo5THxGJHpt
VEp6LSMtPkNTQGoxUUdCUF5lQGtYeDlGPlV7fm5oTSN6eTdPU1dkKT5wX19aPlNzCnpKYSZCSmUt
NTVFLXB+MH5Namk7U2xFI1J2OUk4SiVvZ0ZXc1djTVpkIWRuJVdvQzI1ZHNXP3VLQV8oZ3FUREZa
JAp6V05+dElAVVppYGokWTVMKH5RVUU5e2U7MjxRIzkmdDsqYy1NVlEzRFVPNnJ3dSYjS0p4NT5L
fTEkM0JIUkd7WW4KemoxN1YmZENjZ1BPUWlPUERHJCM2eGJhWDRVPSZ7JmU1c1hGOV85a2g/Tlox
SiluWjFURWd+KTRzZmB8JkwjT1UtCno0QTs0WV5TJjIpVkNubzJhIShoYytfTDZqOH12aGNqbGtY
bSlAJiRePVU/QGFNTnhlOyFybmc5cGNxcVN0Qyo+dwp6PTQ2VFk3bzJLQkcoYzlLc0lCPylCdmhn
QSZOdXM/KXcqQUJLTmxkUnFeOVlOcmw+WVh0S2BUcTFsTD4/dUl+MHwKeikmfm1xbjd8KTNzZV9E
R0V2M1Z7cnZ9KGZDRyU4SyRgRmxYbHQoYE9KJl9ZV2U4P0FZNk4/PD83TyEqVkxhaXFHCnpVMnxx
VUtEWnF6dFlaNjFgRnNoWjNxSGsxZkJZJn5oTzxQNXpTY29ZSig/ZHZJNzM9K099fE8xTUB7RWtj
VUhZKQp6KylVQWM2WGtsTXdRYGlRZGNBOGh5MTwxaTQ8O29BIVZPNWkjPmkxKXppZik5PyUmJVpj
bWp6OXdOd0YoRXN1aCEKelpIPjY7MD1zSUo3NTM9MiVHSjJhKWUlTmNfJGY0VHtJanh7a1VLQm42
NTB+OHBUNV97ekNiZjlCMWBZelZxQ09TCnprczM/PG45RTNgV2x4dXslOVQxJk9lVmVuQH5xRmcj
XkgpUE8mdkojdmU0MDNJcUV0XkltNyFuRWd6KiNhVWMtIwp6KW17dl4tK05VWXp4b1gqPSlkPj5C
PURhRXsobUVaKXFWXl97S0BWYWNIZ2hAa3E5M31SRE5+IWNxZiVjX1VvYkUKek09IU5CakVXVyk/
QFFDWXNqUjU3VFdZXkVSVFdxZD9Ycis1cm80VDkqfl8wbksxTlB6IURYVmUwbyEwKWQ+Kyl5Cnom
e2Y5aj5FKUc7Snw3OVp0Z28rK2xWYj91U15EKCgoTXVXWUd8I0hgJncyNmxrNSEkVzwtKCg+KVpF
PTt5Pl9PRwp6dmF7KFFIRzg/YnM8UGA/MS19bih5KGRqKTYpWGUhdmEpO2ZSPVgpMnZiOGdSaTU2
e0srRDNKKipFYWo/bEFaUmgKemk2LXI+ITMlUm9Xa3R7NTd6Tkx3RGRzc1pHTihOfkpsMEQpOSo/
fGhLOC1eLT4hdTtyaj9vOyFTJkhtVVFxYVQ0CnptKn5mKj9SPTt7cEU7NytpQEhzOCMkfXhlYmFa
Jj9YUlVRdzlPQj4tb2l2WkFwR1dVI0lFfkVDVyspfWAqLWJ8Rgp6OUV1VChXI1NQS1NxUChlYmNg
fmhnTyp6cGdadGxWSTh9UllZQndHYXlOUjV2aVBAZWdhJTc8ZVhhYmtqKm8tVGwKeld9Tkp0T3pD
KURNeHpHU1lhd0FfbEo3JkowKFleRzJQME5rNHI3UHxtJW84SnByeGd5QUlnOE9BbWAlSDhpO0NN
CnohYElqTU9FJVNgaHskKD4tVjMjTFhZbCZVXkFqQGshc1hkUWctUHFTKlhHJGdIWnx6OU1NVzdA
TUxwVWRTK0JvQwp6VTVkLTM1dz4pO0thcnNBSUM/eCQld3Z6Wj9SKTBBSVduRVpBZ2BSR2ZlQVJG
eG11WkFIKHJrNkBPSyY2O21wQisKei01UHc+JmVrIW14VS08SCZYM0tvTHstUHdeK1Arfj1sSXJ6
S3tuQEZYPTBKe3VmfjJTRC1+aUd4b1VmaTZQd0EhCno7KX43YUVHI19rdEVAXjEhZ31oK3VnaGM/
RCtrWT9LT2dwUHpNT3MxZD9hR2hCd085RTB0O1A5NSVOYUgld05iRAp6UjVfP0UjazVBcXtMYXJX
OVBVa2NTIXB3NVg1X2NXaCEtdnpaciswXm55UFojezh+TDxZdWB+SyN2R3luUWdiU1EKeiVOM1Q+
aTQ8PU93RUspX2hmJjkkdjJHb2NGPjZ0YnQ+YXdUJUtLQHRxd3RReUhqWkdtYWQwMGxAUlRITl99
ZXAkCnpHQz5wM0JFNTNgdzl+QnxtRStQI2p5bTE+JVlKVnk0R2s3fkFqYXJUOyVLcSNsek9qfUJU
d3NyIzRKcUhUMjwpRQp6PDs0b2VLVDQmI1RYJnx9NEs5QXQ5Qi0mQkFEbm9NTURmezlqcGpXSDso
NFpXeklTc0xsWDRiQHJoeFA9LWhFPkYKemEqZX5kRm5acDF5ayViX18jfEBmcVE1JGc4LUEoPiVq
IXQ7Rl5vM317MTl9bz9wITlhYHRrNmJhOX1nQUkjP0FKCnpDJik3ZnczbVlOU15Kdm0tLV9ueis8
MStSc1dhfiYzUzNZJDtlVFV6aG08SEJKPWpYVFZMeUwteF9nfn5hfW5HUAp6Pkkqb0hPXmZNU2Zp
aTRRSD4tRkRvU1IyVChNdHZlQGx6cUZ5PVV7ckZQYTFtPSljKDVCTUsyY0VaVm5PaVAyS34KemtG
MHlDZTlwSEgyQTxKR1E+TlclU3FCJFBkQVRsPUBkWiZjP2dUSXQ3UXJfKkhrTEFFfDhSZiRuRDRl
OW5XZDJ0CnpfR193IXg7bkpUNzRqSzBub2E0KTRGa3RvbUpuNmlBfTduU3pSNmFINXBCXmxRd043
ZV5QMykxKTY+XiEoJWdAUAp6bXROdnJsPn1SNHUwUVZBRkV4fGE1NU1qQG5rZ1NrSypMd2ZPfXJ0
JXFTR2syPit8ZFUhfDkqZCVmZz5AWD92NTkKeiZxVXgzUSlnKyF7O2Q9cT97JXs3bkZgKyNUTlQo
Mi0mKEgjVWk1Z09RUFBwYSpaY3h8azFsQzRWejM9M01ZUW4jCnokRE83RnIjTShQKFpqakdAbWFy
ZHB9OHpFKEcldnohKG0xSjZRbHdGQkA0XmRzbD4hNW0jR1Imdjk+MDFxfmZSRwp6QFpKRzR1RzNX
SEZjTXRlOXgmIU5rXk1wP3k2cUp6e2BiMkdsY1g9djdqVX5mb25Zcyg2Z1JZYHJBfHpFQEF6eCMK
ekctNTcweGI3aEJ1bXZrZGFWIyk4S0U4UUc5SDNlcXtQIUpIZU8lbXN5Sz1sQEc0QTIlUW1qZ1Ra
RWFXUU9tKldMCno/PTB7N3tkK21YQlA3RnpkTHZOKiN0PiMlQWFLfDd4YmN4ajZPKGp1S0tMdE9y
Ki1CQ0Vsb3xFcXIlQyRqVzl8cgp6WkVmQz8zeXhySDBqI21jcHxjbyFfKT14X0d8NmRIcitIdENP
JVQ8PDd0cnY9QEV0YHYmdzR3aGBuMiVIcFFTcEMKeiFUamgyLXIzOGB3filfcnB1fVR0UH58aT5H
SH53TUlVTyNNJmA3QjJXXnBYK0Y5ZWh2P1ZHZEcpbGRecWQkR3xVCnpvc0IpKzxTUUtTdERZJldi
emVvY1EjdVhlTS1HZjkzJUlYJUp3RUZ3biUra0FAeSEteSNqfXFRVDwqUT1Gcj1VfQp6VmxmSFNE
dShMfFdJQVJIKnxldC12PCFrJSFrNDE/NUBuTlMzfXc0WGJ6PnY7YF50clRENXU5S0RHN1RNbFo/
eFkKekhqY3lUZDY5ZXp1N299TkI3PGgtTys7fWwhJTJXPlUkVEpXVDhjbE0tTX13X0d7cnZeTTJP
NSQ1ISZGUm1JMDVwCnpGJihRMFdfdGp6SEJjZVctQHhGTi1iKn1AcmR0Ui0yb0NlWlc9b1hza0xq
UmUpM0QzbUp3LSVCPzNfYDkyKjskYwp6NWZaS29mITJpKk00P18wa0c9TTAybDJVWEVWSSV1OXx7
WWJeSHtocXBWd0twYDklbypOaE5zcmM8dVZ2JDUkcEAKelR4Xml6UExAcCsrP1VpKmBDV09yQl4y
d283X0dBRzhEPj1QeSh4a1VqSzBgaU5BV24lTytxdjY7azdiWEkxKmt0CnplIUhkZm11Q3J0UWc1
JCY9KWtBbnEoTjdEP3goUXdKQj8zbVd+VjVFVjFXYHRVYEkkfnFPa0l7N0tXPWsoIyZhbwp6YzdJ
KV5lY0xHSyp1ckJoRkUwVytTamg8Um0/IVZJKm5zPyp4Nkc9fnVFPUw0RV83dWUwNkZwfldveVRV
ZTtJUzgKel5kKmNXSCFufWJzPHhJPGg+UTtaRGA7NG16TU1aRGNZWW90Q2tKaGhxUmU/NWZGYW1G
MkBDM2huUjVPKHlGM1VOCnpULXoheT1sUksmO0BiWW1PPnBGbDk/aXgjRTQ9SDJOZmp9eXpnPTw8
dSM9I3A0SWQ0aEtmIzJxdSZfNXZIMldTMAp6XkxZMnFYb3dETWNwemNiR2U0fl9fQ0xkJGNUT0Zt
WkgzWXImUGU9RF5LdntsNFYocDU2P1R+eXozUzA8RGdvOzgKelk+ZmA0dmwtMjJqI2FZUHpEb1l7
O1llNzZKbmBqZWBWOzUqO28rYXIwaiFPTCN6QnsyT35ueHIzZlFJWFlETVUzCnpURGlFMj1wSnk/
e1R7IWFsZUclPkg2cX13JiZoQSshPmhDalMyK2UoOypIPl5yd2ItaTMmMVclOF9MNWpofXckLQp6
JkA1OW13aig4Q0NePTV8X1M9Q2RxNF5RTUNhPmFEbGNOVWhyYUpaTVlHKW1MZ0N5dnVfZWRudDEy
SSRYYVI5KSYKemBgYV9UZiQyKkI+V2peYiQ1IVhRJmMyJWw7VTBVVkw2cDJzZ0NadHBjSXwxelMz
UGo/RkpxJmxPJCMkZzhVakFNCnpyYy1KMzM5cGZnQ01RM3U5T3BzJXNkcjZOVGJsYGRyLXFUdEky
WEtweTRUdjVUKFNFKSM2KlMrRk84TmMrd0I4ZAp6a0RvWTs5VjU2aTUtaiFicVRsQHJmajZFfjgy
T2BsYXN1YTgqJGgwVSZ6dj0kZW1nLXxHYnctMXtZMWg8PG0oXikKej9qNHpVKWppI2lEM1JqPTBg
eElTXnljTXhzfjlxRChgaiV0UGVZfHtKQkJfU3leYWRiQXFZblEwTz9SJT4kQn5KCnpGVlhYUF5J
fUstTXhKQTFiLVUrOysrSkd+OGN4a2BtYWJ6NUJyaHtlRXw5TzwldTE9MFpxbipwZVBjJXVZWCNa
Kgp6MGJzK2JGRU9oLTt1Z1QwPU1RZT48PmtwSUBqOCQwaTFfYnxxIXN+OHZwKmZSd0lkZlpaZmsx
OypJZXB6V0NANjwKejJEQUg7I3pzOUQ9SUw9ZT4yTGBsO0kwblFBSDR0ZjxoUHZeO2pRViZabzhB
ZnJjbHBjOztJaTw5e01LVmZ8TCFVCnpwbH4zY2dgTWorTmFHJW1yUnx5KjA1RUU5Wm5CYXFVVUk4
RjFUSlB3ZTdTUnYmRUwwe1ZXVXNTSTN2TmpjVHtCbAp6QkMqdT5yNihmNnl+NV5+Wis9bDh4SVc9
QmE8NTFpOWY1RzMrNntBajd5MUtjP0N+bDRiPmghNXM1PCg2b284bVAKenszYkFATHtJd3pQTFly
cCg5cWh3WnJ6e0U3flBSXklYezt8O0E9R1JPJT09cmNnclBvXkxibVNlT0t4UigtKT1vCnpwQ09u
Y3Z8T2QjTk9wZl8kTEV4YWs9NXdsaWM4UHo1IzxzMyppNn5gX01eRktGWjJpZk8hbFAyOD1lXkE1
PFh8JAp6ViNnJnM1NW5UamVrNj1xXnZgfkk+VF9QJUpiKmJuM3V0YmhlPUliQkg5cVVmUXRWemN1
SnlCfGg+fCZKTlJ2YGoKelIxQ3VHdm1DNkRzQn57ZSZoQD89NVF9Rj47QzN9QCtCK0x4JCtIZlFO
dF5UYVB3Y2FUVEcmaHZve3lufVF4T1ArCnp1bl57P1ZZSFVyaylSP0EraihUQGc3QyM5VG5FOWN6
UzM7UDtBOX19eWU0NElMPlRrPkJzcCFnKllAVDk3NVR6Ugp6JTw/YlUkNEpXSF59VFRTcVlka29e
T3BsJU5GSGs2dHZxSFpMLVI+aT82OC1xIU50K3pPWkVhbVo0fW95ano5a30Kekt8cz9AKjFzQUZn
MSFwYlgjc1hiTFdoR302USVTOExWe2RwenN8fW1DV21MP1YlVE5kTT0kK2VKMmp3SjhNPDt+Cno9
bnV2ZTtobzZAdElLfiNsellGKWNVWlRDO1BgSUQjbE4mYW53QE8kUmg7KjRLS3d3IWI/fE5Eaz9Z
X2A/IT42Vgp6YE4wSFBucVkyc3ZmZlJEd2NKd0ttOTNIZiZXUlZZTyE2PlIxOER1KU9qNHpEYXwo
bTRxaG52Zk9PPkFlWVM+ek8KejJoQzEoRmg9WjlPeUpHX3dgODchJiUlMyQ4bilhTms5Z2Rxc3ZN
X2JXQT1pbE1lYCNnPHJvdjEtR21pN1pgMHp3CnpANE88eEs3RWd1OH5jKm5yVkU5QEU2dmlmQmNJ
QXxIe0N5QTs4ekF3bXpzST5qPXpYWV5RIzAtcnZQfjRlJlgjJQp6VG55RTdwOGhtRyVqd0JKenNj
TlpjfSFHKi1rPXVlRlA4UXozKmRkd2xeKFl4TjReITlrVzxmWjlwbkROXnchaFcKeiNIO0MtP1At
fmxIY2ljOS1rSUFpUlJJVWwjUkRhbmFZYFktKkdHQGJmPilheE4+QzV9aFZ2eCN2SEpNRm5JZHhO
CnpTI09uUG1QYSZVeV5kelI9YWM+MF4mV0ElbjA5IysxWEt5VSNvdDA0JnkmWURwQ0dFd3FVSyRD
UkxWUn4lQ15LVAp6RSk5Sy1kPXUoVGplfFQhP2dhTCVhUmteRlM1LVM8PiZ9bD9GT2lYe0pFPVM4
YjgrTCM2UnR9S3IlQkVoPVIrTTkKenQ/aFNlbSk1K3xqbillVjkybzQoQEchSzhxbHE8PWwldD42
PXtVTnsqVnE+dWNhQW0qNSppOEt7TUxKbE8wKWo2Cno4eHVHXjlxVD41Wk9IMyh5aiFTU09CWEdN
d1AxU2U5bmRkOy0yd3tlRWlgUThpaXwoIUl2ezI1OUE0PTtMTFQ2egp6SXBQdmQ2IXFWcy0wdmtF
SUhIYE43Pmk+TklRczU3PXsrQkt1cFMjNz1ZYWEpPitVVl5saVR9T2dKRUVzKSp+VDUKejJqayNf
c0tQKUAlNTYkUClfNDtTK3RpZV5mSHszTWZfKmNaO3NzcyFYRit9eUcwYlpqRHNIcCorSWpzLXRf
KSUhCnpJe0QkTEl1JlQ5dyppVTxWYCt+PEZtI0MpMj9hfFo5VVpMLSYwb2c5clZATTdwXzJTOVZ8
eDBmYFA1O3J1JSUzQAp6JnVRTF8tfXBBO0prSVZVWG1gIX1TPGVkansqQCNQM0R6XylGbzBTRlQz
ZEc9QGpBQFpebFp2eCNLM3BweDVhR00KekAqMnJqYH0mP181Y085U0Nuc3lEcXs1VT9qQHs9VTI7
RVJ2X3U8KSpseXBiUVNPJjUqPz5GcUNzTlg+Yy1pMWM3CnozPiFoMGlGeC0zPyN3U1cxKFghbD1o
UW5GUENCZlBAZnI2Tkk1KXM3KT4xeWBuN0NTSTJkKnFQOTNwPT05Sk8heQp6YjdnNnJLcCtJPlNO
fGAtKi0rPkpaN0JYJDlHaWljYVhgPnQ5MENqVEBwaEIpcWhkYXYtTT5OUmwzfTt5MmVNT00KempY
TG5VcXA7O0smcUJ8KlBJcmVBeEVFQEF6a0FzY2k1LUBsd3xaWWJHcE8xVHJiRCtUSWR3KXB1M05g
dXp+SCh0Cnp1KEtvaj45ZHt0PWVaZnYoY05GRGd+fGZqQjFIUGpPWU9+Zj5NJVI2JnNYMTVkME4h
QjtDZH13eGUlKmY2TCs4MAp6T0FSSV5fNXxuT0hHQjA5cUlNNGMqTFYwaDMmc200RWdPYnhFWlZ2
c0NMSF8/XmokOXY5fF5NWCpUPmlAYnRIYWkKenNQPVd3Uj0pVXNTKH1vWW4lV3pEa2A+X0VKXkVS
fCUlZ2NfK3F+VlhKRzBDOCV8K3k3Z1FZdCgoPSU9TWwxPFFKCnpfYlk9dXM+PD40bkxCUDhAZlV6
XkpRYT5NJUhPI3Y9WTZjTHR6bklvIXBfWUglRXNVTV9eZS14djU2JTQ/SnZHUAp6bkgtdShFajRk
dj5hI0w3SWIzQyluajd1WERFQnpvP0BoVGhsWm0yQUN9Nzg/Y3NRK1opcWxsfiNeJFU1Q0A4bnQK
emB7fVQ/KUJTT3cpJjJhPihyfkdsUVdhXzxsX0JBdkM5d0FKeDhrdHgjUnVRPkptJkohZFkwQk9x
UHs8U0J4Uk84CnpGa3Z4Z0MrTT1aX2s2PDkzKXhrYjs8Sm55aytacGBrKVQqNnNgJHUkNWl5WHk1
MlJwdms8LTtaPn4jIzEqTk05Ygp6NTd4NUh3LVhQS29PJmkrbjdpJU9sMzdreUlWTHBrRXtST2k5
R2A9YDJUb0J5QjI3VylAelc/VktwIV5pVyk1OW0KejY+e28+NiZWfiVsTmx6bnVzNTtGbXdEUGRK
MmZya3IxfChgWDFyQ0QjWFBPeGJ6MjRVUTE3YHd6V0t8Yz1BM0hwCnp3WStCUjUjQExBdDxLPjE0
aEc8X1g3Tkpna0EzJGB4cyMlai1QPFB4dyFiOT1FYGU7bkNqflB6aT5XSzlYOT5QNgp6cDZ8KmNH
bHNJVCpIKWx6ajImJUh6alIpQkpMNVowPS19dDlGQEc4diYpI0w1KTckQWVldHw1I0N0c0dJS3xn
PUMKeigyU24teXM7WSFkLWQpSmJ4QkplcUdJfkQxPFUxam9DYHZRJGZuQDleKXhmVEJgPmhaNkdS
JFRgcj9GT3pWOWJ2CnpyMkcxPmEwYSVuIzdnQCFrc0xiXkF8Mz98eklyNVY8SEdDWm5OPzc0VStx
cHImUGh1VU8lKWUtV1VKKEBmfXQ1ZAp6OCo0JX1aMF5wWUhfSlJYUSZIP3ghWnhhNWNjQHxEa0I4
STVwIWNuTmU+MTNsO2ZodWs4VGdteW5+JndCPTFlKnEKeiYyQ288TWFlOWdRP3VEfFF8S0tXTyt7
RHNySlQpTy1yVE0pX3c5aT4lJDJRU0BzMnx4WEspfTkwQDYzbW48KVNqCnpPck9QZ0JWbnZaIVB0
LWlhMm89bStXU2xiNUBINTJ0UkxUN2EzTjJiTis2SmtvMj5zMHtVP2U0WX51Z1J1NWk+MApYYipO
TlNWUyt4bllMdi1LREAoeThPeUItcnNafnRUCgpsaXRlcmFsIDAKSGNtVj9kMDAwMDEKCmRpZmYg
LS1naXQgYS9hcHAvcmVzL3ZpYmVtaXMuc3ZnIGIvYXBwL3Jlcy92aWJlbWlzLnN2ZwppbmRleCBj
M2YzYzgxLi43MTE1YzMzIDEwMDY0NAotLS0gYS9hcHAvcmVzL3ZpYmVtaXMuc3ZnCisrKyBiL2Fw
cC9yZXMvdmliZW1pcy5zdmcKQEAgLTEsMTkgKzEsNyBAQAotPD94bWwgdmVyc2lvbj0iMS4wIiBl
bmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+Ci08IS0tIFZpYmVtaXMgYnJhbmQgbWFy
azogYSBjdXQtZ2VtIGRpYW1vbmQgY3JhZGxpbmcgYSBwbGF5IHRyaWFuZ2xlLgotICAgICBEcmF3
biBmcm9tIHRoZSBkZXNpZ24ta2l0IHRva2VucyAoZG9jcy9kZXNpZ24vcmVkZXNpZ24vbG9nby9S
RUFETUUubWQpOgotICAgICBkaWFtb25kIGhhbGYtZGlhZ29uYWwgfjM3JSBvZiB0aGUgYm94LCBz
dHJva2UgfjcuOCUgb2YgdGhlIGJveCwgZmlsbGVkCi0gICAgIHBsYXkgdHJpYW5nbGUgfjMwJSB0
YWxsIGNlbnRlcmVkIGluc2lkZSwgYWNjZW50IGdyYWRpZW50Ci0gICAgICM2QURERTcgLT4gIzJG
QzZEMC4gVGhlIHNvZnQgZ2xvdyBpcyBvbWl0dGVkIHNvIHRoZSBtYXJrIHN0YXlzIGNyaXNwIGF0
Ci0gICAgIHRoZSBzbWFsbCBzaXplcyB0aGlzIFNWRyBpcyByYXN0ZXJpemVkIGF0IChTREwgc3Ry
ZWFtLXdpbmRvdyBpY29uKS4gLS0+Ci08c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAw
L3N2ZyIgdmlld0JveD0iMCAwIDI1NiAyNTYiIHdpZHRoPSIyNTYiIGhlaWdodD0iMjU2Ij4KLSAg
PGRlZnM+Ci0gICAgPGxpbmVhckdyYWRpZW50IGlkPSJ2YkFjY2VudCIgeDE9IjAiIHkxPSIwIiB4
Mj0iMSIgeTI9IjEiPgotICAgICAgPHN0b3Agb2Zmc2V0PSIwIiBzdG9wLWNvbG9yPSIjNkFEREU3
Ii8+Ci0gICAgICA8c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiMyRkM2RDAiLz4KLSAgICA8
L2xpbmVhckdyYWRpZW50PgotICA8L2RlZnM+Ci0gIDxwYXRoIGQ9Ik0gMTI4IDMzLjMgTCAyMjIu
NyAxMjggTCAxMjggMjIyLjcgTCAzMy4zIDEyOCBaIiBmaWxsPSJub25lIgotICAgICAgICBzdHJv
a2U9InVybCgjdmJBY2NlbnQpIiBzdHJva2Utd2lkdGg9IjIwIiBzdHJva2UtbGluZWpvaW49InJv
dW5kIi8+Ci0gIDxwYXRoIGQ9Ik0gMTA3IDkyLjYgTCAxMDcgMTYzLjQgTCAxNjggMTI4IFoiIGZp
bGw9InVybCgjdmJBY2NlbnQpIgotICAgICAgICBzdHJva2U9InVybCgjdmJBY2NlbnQpIiBzdHJv
a2Utd2lkdGg9IjEyIiBzdHJva2UtbGluZWpvaW49InJvdW5kIi8+Cis8c3ZnIHhtbG5zPSJodHRw
Oi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjUxMiIgaGVpZ2h0PSI1MTIiIHZpZXdCb3g9
IjAgMCA1MTIgNTEyIj4KKzxkZWZzPjxsaW5lYXJHcmFkaWVudCBpZD0icmltIiB4MT0iMCIgeTE9
IjAiIHgyPSIxIiB5Mj0iMSI+PHN0b3Agc3RvcC1jb2xvcj0iI2ZmNzU4YiIvPjxzdG9wIG9mZnNl
dD0iLjQ4IiBzdG9wLWNvbG9yPSIjZGMzNjU4Ii8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9y
PSIjNjMxNTJiIi8+PC9saW5lYXJHcmFkaWVudD48bGluZWFyR3JhZGllbnQgaWQ9ImdsYXNzIiB4
MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iMSI+PHN0b3Agc3RvcC1jb2xvcj0iIzIwMTUxYyIvPjxz
dG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzA4MDgwYiIvPjwvbGluZWFyR3JhZGllbnQ+PC9k
ZWZzPgorPHJlY3QgeD0iMTIiIHk9IjEyIiB3aWR0aD0iNDg4IiBoZWlnaHQ9IjQ4OCIgcng9IjEx
MCIgZmlsbD0idXJsKCNnbGFzcykiIHN0cm9rZT0iI2ZmZmZmZiIgc3Ryb2tlLW9wYWNpdHk9Ii4x
MyIgc3Ryb2tlLXdpZHRoPSIyIi8+Cis8Y2lyY2xlIGN4PSIyNTYiIGN5PSIyNTYiIHI9IjE0NCIg
ZmlsbD0idXJsKCNyaW0pIi8+Cis8Y2lyY2xlIGN4PSIyNjgiIGN5PSIyNDkiIHI9IjEzNiIgZmls
bD0iIzA4MDgwYiIvPgorPHBhdGggZD0iTTE1MSAxNjJhMTQzIDE0MyAwIDAgMSAxMzUtNDgiIGZp
bGw9Im5vbmUiIHN0cm9rZT0iI2ZmZThlZSIgc3Ryb2tlLW9wYWNpdHk9Ii41NSIgc3Ryb2tlLXdp
ZHRoPSIzIiBzdHJva2UtbGluZWNhcD0icm91bmQiLz4KIDwvc3ZnPgpkaWZmIC0tZ2l0IGEvYXBw
L3Jlc291cmNlcy5xcmMgYi9hcHAvcmVzb3VyY2VzLnFyYwppbmRleCBiNWQ0ZWU3Li4wOGJkZjJi
IDEwMDY0NAotLS0gYS9hcHAvcmVzb3VyY2VzLnFyYworKysgYi9hcHAvcmVzb3VyY2VzLnFyYwpA
QCAtMSwxMyArMSwyMyBAQAogPFJDQz4KICAgICA8cXJlc291cmNlIHByZWZpeD0iLyI+Ci0gICAg
ICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pc19wLnBuZyI+cmVzL3N0ZWFtL3ZpYmVt
aXNfcC5wbmc8L2ZpbGU+Ci0gICAgICAgIDxmaWxlIGFsaWFzPSJyZXMvc3RlYW0vdmliZW1pcy5w
bmciPnJlcy9zdGVhbS92aWJlbWlzLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJl
cy9zdGVhbS92aWJlbWlzX2hlcm8ucG5nIj5yZXMvc3RlYW0vdmliZW1pc19oZXJvLnBuZzwvZmls
ZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzX2xvZ28ucG5nIj5yZXMv
c3RlYW0vdmliZW1pc19sb2dvLnBuZzwvZmlsZT4KLSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9z
dGVhbS92aWJlbWlzX2ljb24ucG5nIj5yZXMvc3RlYW0vdmliZW1pc19pY29uLnBuZzwvZmlsZT4K
LSAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmstNTEyLnBuZyI+cmVzL3ZpYmVt
aXMtbWFyay01MTIucG5nPC9maWxlPgotICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3ZpYmVtaXMt
bWFyay0yNTYucG5nIj5yZXMvdmliZW1pcy1tYXJrLTI1Ni5wbmc8L2ZpbGU+Ci0gICAgICAgIDxm
aWxlIGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTEyOC5wbmciPnJlcy92aWJlbWlzLW1hcmstMTI4
LnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGU+Z3VpL0VjbGlwc2VIYXJkd2FyZU1vbml0b3IucW1s
PC9maWxlPgorICAgICAgICA8ZmlsZT5ndWkvRWNsaXBzZVN5c3RlbVNldHRpbmdzLnFtbDwvZmls
ZT4KKyAgICAgICAgPGZpbGU+Z3VpL0VjbGlwc2VDb21ib0JveC5xbWw8L2ZpbGU+CisgICAgICAg
IDxmaWxlPnJlcy9jcmltc29uLW5ldHdvcmsuc3ZnPC9maWxlPgorICAgICAgICA8ZmlsZT5yZXMv
Y3JpbXNvbi1ibHVldG9vdGguc3ZnPC9maWxlPgorICAgICAgICA8ZmlsZT5yZXMvZWNsaXBzZS1j
b250cm9scy5zdmc8L2ZpbGU+CisgICAgICAgIDxmaWxlPnJlcy9lY2xpcHNlLWljb24uc3ZnPC9m
aWxlPgorICAgICAgICA8ZmlsZT5yZXMvZWNsaXBzZS1wb3dlci5zdmc8L2ZpbGU+CisgICAgICAg
IDxmaWxlPnJlcy9jcmltc29uLWJhdHRlcnkuc3ZnPC9maWxlPgorICAgICAgICA8ZmlsZT5yZXMv
Y3JpbXNvbi1ob3N0LnN2ZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy9zdGVhbS92
aWJlbWlzX3AucG5nIj5yZXMvc3RlYW0vZWNsaXBzZV9wLnBuZzwvZmlsZT4KKyAgICAgICAgPGZp
bGUgYWxpYXM9InJlcy9zdGVhbS92aWJlbWlzLnBuZyI+cmVzL3N0ZWFtL2VjbGlwc2UucG5nPC9m
aWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfaGVyby5wbmciPnJl
cy9zdGVhbS9lY2xpcHNlX2hlcm8ucG5nPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVz
L3N0ZWFtL3ZpYmVtaXNfbG9nby5wbmciPnJlcy9zdGVhbS9lY2xpcHNlX2xvZ28ucG5nPC9maWxl
PgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3N0ZWFtL3ZpYmVtaXNfaWNvbi5wbmciPnJlcy9z
dGVhbS9lY2xpcHNlX2ljb24ucG5nPC9maWxlPgorICAgICAgICA8ZmlsZSBhbGlhcz0icmVzL3Zp
YmVtaXMtbWFyay01MTIucG5nIj5yZXMvZWNsaXBzZS1tYXJrLTUxMi5wbmc8L2ZpbGU+CisgICAg
ICAgIDxmaWxlIGFsaWFzPSJyZXMvdmliZW1pcy1tYXJrLTI1Ni5wbmciPnJlcy9lY2xpcHNlLW1h
cmstMjU2LnBuZzwvZmlsZT4KKyAgICAgICAgPGZpbGUgYWxpYXM9InJlcy92aWJlbWlzLW1hcmst
MTI4LnBuZyI+cmVzL2VjbGlwc2UtbWFyay0xMjgucG5nPC9maWxlPgogICAgICAgICA8ZmlsZSBh
bGlhcz0iZm9udHMvU29yYS50dGYiPmZvbnRzL1NvcmEudHRmPC9maWxlPgogICAgICAgICA8Zmls
ZSBhbGlhcz0iZm9udHMvTWFucm9wZS50dGYiPmZvbnRzL01hbnJvcGUudHRmPC9maWxlPgogICAg
ICAgICA8ZmlsZT5yZXMvc291bmRzL25hdl90aWNrLndhdjwvZmlsZT4KZGlmZiAtLWdpdCBhL2Fw
cC9zZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5jcHAgYi9hcHAvc2V0dGluZ3Mvc3RyZWFt
aW5ncHJlZmVyZW5jZXMuY3BwCmluZGV4IGQ2OWE5MTMuLjYwMjJiMjUgMTAwNjQ0Ci0tLSBhL2Fw
cC9zZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNlcy5jcHAKKysrIGIvYXBwL3NldHRpbmdzL3N0
cmVhbWluZ3ByZWZlcmVuY2VzLmNwcApAQCAtMjI5LDcgKzIyOSw3IEBAIHZvaWQgU3RyZWFtaW5n
UHJlZmVyZW5jZXM6OnJlbG9hZCgpCiAgICAgc2VlbldlbGNvbWVIaW50ID0gc2V0dGluZ3MudmFs
dWUoU0VSX1NFRU5XRUxDT01FSElOVCwgZmFsc2UpLnRvQm9vbCgpOwogICAgIGVuYWJsZUhkciA9
IHNldHRpbmdzLnZhbHVlKFNFUl9IRFIsIGZhbHNlKS50b0Jvb2woKTsKICAgICB1aVNob3dIaW50
cyA9IHNldHRpbmdzLnZhbHVlKFNFUl9VSV9TSE9XSElOVFMsIHRydWUpLnRvQm9vbCgpOwotICAg
IHVpQWNjZW50SW5kZXggPSBxQm91bmQoMCwgc2V0dGluZ3MudmFsdWUoU0VSX1VJX0FDQ0VOVElO
REVYLCAwKS50b0ludCgpLCAzKTsKKyAgICB1aUFjY2VudEluZGV4ID0gcUJvdW5kKDAsIHNldHRp
bmdzLnZhbHVlKFNFUl9VSV9BQ0NFTlRJTkRFWCwgNCkudG9JbnQoKSwgMTUpOwogICAgIHVpU291
bmRzID0gc2V0dGluZ3MudmFsdWUoU0VSX1VJU09VTkRTLCB0cnVlKS50b0Jvb2woKTsKICAgICBk
aXNwbGF5SGRyQ2FwYWJpbGl0eSA9IHNldHRpbmdzLnZhbHVlKFNFUl9ESVNQTEFZX0hEUl9DQVBB
QklMSVRZLCB0cnVlKS50b0Jvb2woKTsKICAgICBoZHJUb25lbWFwcGluZyA9IHNldHRpbmdzLnZh
bHVlKFNFUl9IRFJfVE9ORU1BUCwgZmFsc2UpLnRvQm9vbCgpOwpkaWZmIC0tZ2l0IGEvYXBwL3N0
cmVhbWluZy9pbnB1dC9pbnB1dC5jcHAgYi9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmNwcApp
bmRleCAxMDUwNWVmLi4zZmFmODdmIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL2lucHV0L2lu
cHV0LmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmNwcApAQCAtODgsNiArODgs
MTAgQEAgU2RsSW5wdXRIYW5kbGVyOjpTZGxJbnB1dEhhbmRsZXIoU3RyZWFtaW5nUHJlZmVyZW5j
ZXMmIHByZWZzLCBpbnQgc3RyZWFtV2lkdGgsIGkKICAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5
Q29tYm9Ub2dnbGVTdGF0c092ZXJsYXldLmtleUNvZGUgPSBTRExLX3M7CiAgICAgbV9TcGVjaWFs
S2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlU3RhdHNPdmVybGF5XS5zY2FuQ29kZSA9IFNETF9TQ0FO
Q09ERV9TOwogICAgIG1fU3BlY2lhbEtleUNvbWJvc1tLZXlDb21ib1RvZ2dsZVN0YXRzT3Zlcmxh
eV0uZW5hYmxlZCA9IHRydWU7CisgICAgbV9TcGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xl
TG9jYWxIYXJkd2FyZV0ua2V5Q29tYm8gPSBLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmU7Cisg
ICAgbV9TcGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlTG9jYWxIYXJkd2FyZV0ua2V5Q29k
ZSA9IFNETEtfaDsKKyAgICBtX1NwZWNpYWxLZXlDb21ib3NbS2V5Q29tYm9Ub2dnbGVMb2NhbEhh
cmR3YXJlXS5zY2FuQ29kZSA9IFNETF9TQ0FOQ09ERV9IOworICAgIG1fU3BlY2lhbEtleUNvbWJv
c1tLZXlDb21ib1RvZ2dsZUxvY2FsSGFyZHdhcmVdLmVuYWJsZWQgPSB0cnVlOwogCiAgICAgbV9T
cGVjaWFsS2V5Q29tYm9zW0tleUNvbWJvVG9nZ2xlTW91c2VNb2RlXS5rZXlDb21ibyA9IEtleUNv
bWJvVG9nZ2xlTW91c2VNb2RlOwogICAgIG1fU3BlY2lhbEtleUNvbWJvc1tLZXlDb21ib1RvZ2ds
ZU1vdXNlTW9kZV0ua2V5Q29kZSA9IFNETEtfbTsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcv
aW5wdXQvaW5wdXQuaCBiL2FwcC9zdHJlYW1pbmcvaW5wdXQvaW5wdXQuaAppbmRleCBmODI4YzA0
Li43ZDViMWRhIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL2lucHV0L2lucHV0LmgKKysrIGIv
YXBwL3N0cmVhbWluZy9pbnB1dC9pbnB1dC5oCkBAIC0xODgsNiArMTg4LDcgQEAgcHJpdmF0ZToK
ICAgICAgICAgS2V5Q29tYm9VbmdyYWJJbnB1dCwKICAgICAgICAgS2V5Q29tYm9Ub2dnbGVGdWxs
U2NyZWVuLAogICAgICAgICBLZXlDb21ib1RvZ2dsZVN0YXRzT3ZlcmxheSwKKyAgICAgICAgS2V5
Q29tYm9Ub2dnbGVMb2NhbEhhcmR3YXJlLAogICAgICAgICBLZXlDb21ib1RvZ2dsZU1vdXNlTW9k
ZSwKICAgICAgICAgS2V5Q29tYm9Ub2dnbGVDdXJzb3JIaWRlLAogICAgICAgICBLZXlDb21ib1Rv
Z2dsZU1pbmltaXplLApkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy9pbnB1dC9rZXlib2FyZC5j
cHAgYi9hcHAvc3RyZWFtaW5nL2lucHV0L2tleWJvYXJkLmNwcAppbmRleCA5OTNlNTM0Li45NDI1
NjJlIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL2lucHV0L2tleWJvYXJkLmNwcAorKysgYi9h
cHAvc3RyZWFtaW5nL2lucHV0L2tleWJvYXJkLmNwcApAQCAtNTEsNiArNTEsMTEgQEAgdm9pZCBT
ZGxJbnB1dEhhbmRsZXI6OnBlcmZvcm1TcGVjaWFsS2V5Q29tYm8oS2V5Q29tYm8gY29tYm8pCiAg
ICAgICAgIHJhaXNlQWxsS2V5cygpOwogICAgICAgICBicmVhazsKIAorICAgIGNhc2UgS2V5Q29t
Ym9Ub2dnbGVMb2NhbEhhcmR3YXJlOgorICAgICAgICBTZXNzaW9uOjpnZXQoKS0+Z2V0T3Zlcmxh
eU1hbmFnZXIoKS5zZXRPdmVybGF5U3RhdGUoT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUs
CisgICAgICAgICAgICAgIVNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmlzT3Zl
cmxheUVuYWJsZWQoT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUpKTsKKyAgICAgICAgYnJl
YWs7CisKICAgICBjYXNlIEtleUNvbWJvVG9nZ2xlU3RhdHNPdmVybGF5OgogICAgICAgICBTRExf
TG9nSW5mbyhTRExfTE9HX0NBVEVHT1JZX0FQUExJQ0FUSU9OLAogICAgICAgICAgICAgICAgICAg
ICAiRGV0ZWN0ZWQgc3RhdHMgdG9nZ2xlIGNvbWJvIik7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFt
aW5nL3Nlc3Npb24uY3BwIGIvYXBwL3N0cmVhbWluZy9zZXNzaW9uLmNwcAppbmRleCA1OGZlYjk2
Li43OTFlZjRjIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3Nlc3Npb24uY3BwCisrKyBiL2Fw
cC9zdHJlYW1pbmcvc2Vzc2lvbi5jcHAKQEAgLTEsNCArMSw1IEBACiAjaW5jbHVkZSAic2Vzc2lv
bi5oIg0KKyNpbmNsdWRlIDxRU2V0dGluZ3M+DQogI2luY2x1ZGUgInNldHRpbmdzL3N0cmVhbWlu
Z3ByZWZlcmVuY2VzLmgiDQogI2luY2x1ZGUgInN0cmVhbWluZy9zdHJlYW11dGlscy5oIg0KICNp
bmNsdWRlICJzdHJlYW1pbmcvdnJycmF0ZXBvbGljeS5oIg0KQEAgLTI2NjksNiArMjY3MCw3IEBA
IHZvaWQgU2Vzc2lvbjo6ZXhlY0ludGVybmFsKCkKIA0KICAgICAvLyBUb2dnbGUgdGhlIHN0YXRz
IG92ZXJsYXkgaWYgcmVxdWVzdGVkIGJ5IHRoZSB1c2VyDQogICAgIG1fT3ZlcmxheU1hbmFnZXIu
c2V0T3ZlcmxheVN0YXRlKE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZywgbV9QcmVmZXJlbmNlcy0+c2hv
d1BlcmZvcm1hbmNlT3ZlcmxheSk7DQorICAgIG1fT3ZlcmxheU1hbmFnZXIuc2V0T3ZlcmxheVN0
YXRlKE92ZXJsYXk6Ok92ZXJsYXlMb2NhbEhhcmR3YXJlLCBRU2V0dGluZ3MoKS52YWx1ZSgiZWNs
aXBzZS9sb2NhbE92ZXJsYXkiLGZhbHNlKS50b0Jvb2woKSk7DQogDQogICAgIC8vIFZpYmVtaXM6
IG9wdC1pbiBvbi1zY3JlZW4gdG91Y2ggY29udHJvbHMgb3ZlcmxheSDigJQNCiAgICAgLy8gdGhy
ZWUgaWNvbi1vbmx5IGJ1dHRvbnMgKE1FTlUgb3BlbnMgdGhlIFF1aWNrIE1lbnUsIEtCRCByZXF1
ZXN0cyB0aGUgU3RlYW1PUw0KZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZGVjb2Rl
cnN0YXR1cy5oIGIvYXBwL3N0cmVhbWluZy92aWRlby9kZWNvZGVyc3RhdHVzLmgKaW5kZXggMTEx
YjgzYi4uYmRjY2JiZiAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWluZy92aWRlby9kZWNvZGVyc3Rh
dHVzLmgKKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9kZWNvZGVyc3RhdHVzLmgKQEAgLTE2Myw2
ICsxNjMsMTQgQEAgaW5saW5lIGludCBmb3JtYXRQYWNpbmdMaW5lKGNoYXIqIG91dHB1dCwgaW50
IGxlbmd0aCwKICAgICAgICAgICAgICAgICAgICAgKHByZXNlbnRNb2RlICE9IG51bGxwdHIgJiYg
cHJlc2VudE1vZGVbMF0gIT0gJ1wwJykgPyBwcmVzZW50TW9kZSA6ICJuL2EiKTsKIH0KIAorLy8g
QWN0dWFsIHByZXNlbnRhdGlvbiBmcm9udGVuZDsgZGlzdGluY3QgZnJvbSB0aGUgZGVjb2RlciBi
YWNrZW5kIGFib3ZlLgoraW5saW5lIGludCBmb3JtYXRQcmVzZW50YXRpb25MaW5lKGNoYXIqIG91
dHB1dCwgaW50IGxlbmd0aCwgY29uc3QgY2hhciogcmVuZGVyZXIpCit7CisgICAgcmV0dXJuIHNu
cHJpbnRmKG91dHB1dCwgbGVuZ3RoLCAiUmVuZGVyZXI6ICUuKnNcbiIsIE1heFJlbmRlcmVyQ2hh
cnMsCisgICAgICAgICAgICAgICAgICAgIHJlbmRlcmVyICE9IG51bGxwdHIgJiYgcmVuZGVyZXJb
MF0gIT0gJ1wwJyA/IHJlbmRlcmVyIDogInVua25vd24iKTsKK30KK2NvbnN0IGludCBNYXhQcmVz
ZW50YXRpb25MaW5lQ2hhcnMgPSAxMCArIE1heFJlbmRlcmVyQ2hhcnMgKyAxOworCiAvLyBXb3Jz
dC1jYXNlIHJlbmRlcmVkIGxlbmd0aCBvZiB0aGUgRklSU1QgbGluZSBvZiBmb3JtYXRMaW5lKCks
IGV4Y2x1ZGluZyB0aGUKIC8vIE5VTC4gVGhpcyBpcyB0aGUgbnVtYmVyIHRoYXQgaGFzIHRvIHN0
YXkgc21hbGwgZW5vdWdoIHRvIGZpdCBhIGhhbmRoZWxkCiAvLyBzY3JlZW47IHRoZSBidWZmZXIg
YnVkZ2V0IGJlbG93IGNhcmVzIGFib3V0IHRoZSB0b3RhbC4KZGlmZiAtLWdpdCBhL2FwcC9zdHJl
YW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9kM2QxMXZhLmNwcCBiL2FwcC9zdHJlYW1pbmcv
dmlkZW8vZmZtcGVnLXJlbmRlcmVycy9kM2QxMXZhLmNwcAppbmRleCAzODhlMzA3Li5mODUzMjM5
IDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvZDNkMTF2
YS5jcHAKKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2QzZDExdmEu
Y3BwCkBAIC05NjQsNyArOTY0LDcgQEAgdm9pZCBEM0QxMVZBUmVuZGVyZXI6Om5vdGlmeU92ZXJs
YXlVcGRhdGVkKE92ZXJsYXk6Ok92ZXJsYXlUeXBlIHR5cGUpCiAgICAgICAgIHJlbmRlclJlY3Qu
eCA9IDA7CiAgICAgICAgIHJlbmRlclJlY3QueSA9IDA7CiAgICAgfQotICAgIGVsc2UgaWYgKHR5
cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7CisgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVy
bGF5OjpPdmVybGF5RGVidWcgfHwgdHlwZSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJkd2Fy
ZSkgewogICAgICAgICAvLyBUb3AgbGVmdAogICAgICAgICByZW5kZXJSZWN0LnggPSAwOwogICAg
ICAgICByZW5kZXJSZWN0LnkgPSBtX0Rpc3BsYXlIZWlnaHQgLSBuZXdTdXJmYWNlLT5oOwpkaWZm
IC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2R4dmEyLmNwcCBi
L2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9keHZhMi5jcHAKaW5kZXggMzI2
MThkOC4uMDRiNWQxNyAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVu
ZGVyZXJzL2R4dmEyLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJl
cnMvZHh2YTIuY3BwCkBAIC04NjIsNyArODYyLDcgQEAgdm9pZCBEWFZBMlJlbmRlcmVyOjpub3Rp
ZnlPdmVybGF5VXBkYXRlZChPdmVybGF5OjpPdmVybGF5VHlwZSB0eXBlKQogICAgICAgICByZW5k
ZXJSZWN0LnggPSAwOwogICAgICAgICByZW5kZXJSZWN0LnkgPSBtX0Rpc3BsYXlIZWlnaHQgLSBu
ZXdTdXJmYWNlLT5oOwogICAgIH0KLSAgICBlbHNlIGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJs
YXlEZWJ1ZykgeworICAgIGVsc2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8
IHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHsKICAgICAgICAgLy8gVG9w
IGxlZnQKICAgICAgICAgcmVuZGVyUmVjdC54ID0gMDsKICAgICAgICAgcmVuZGVyUmVjdC55ID0g
MDsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9lZ2x2
aWQuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL2VnbHZpZC5jcHAK
aW5kZXggOTU4N2EzNS4uMjA2ODBkOCAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWluZy92aWRlby9m
Zm1wZWctcmVuZGVyZXJzL2VnbHZpZC5jcHAKKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1w
ZWctcmVuZGVyZXJzL2VnbHZpZC5jcHAKQEAgLTIzNCwxMCArMjM0LDEwIEBAIHZvaWQgRUdMUmVu
ZGVyZXI6OnJlbmRlck92ZXJsYXkoT3ZlcmxheTo6T3ZlcmxheVR5cGUgdHlwZSwgaW50IHZpZXdw
b3J0V2lkdGgsIGluCiAgICAgICAgICAgICBvdmVybGF5UmVjdC54ID0gMDsKICAgICAgICAgICAg
IG92ZXJsYXlSZWN0LnkgPSAwOwogICAgICAgICB9Ci0gICAgICAgIGVsc2UgaWYgKHR5cGUgPT0g
T3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7CisgICAgICAgIGVsc2UgaWYgKHR5cGUgPT0gT3Zlcmxh
eTo6T3ZlcmxheURlYnVnIHx8IHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUp
IHsKICAgICAgICAgICAgIC8vIFZpYmVtaXM6IHVzZXItY29uZmlndXJhYmxlIGNvcm5lci4gTkI6
IE9wZW5HTCBvcmlnaW4gaXMgbG93ZXItbGVmdCwKICAgICAgICAgICAgIC8vIHNvICJ0b3AiIGlz
IHRoZSBoaWdoLVkgZWRnZSBoZXJlLgotICAgICAgICAgICAgaW50IGFuY2hvciA9IFNlc3Npb246
OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmdldERlYnVnT3ZlcmxheUFuY2hvcigpOworICAg
ICAgICAgICAgaW50IGFuY2hvciA9IFNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigp
LmdldE92ZXJsYXlBbmNob3IodHlwZSk7CiAgICAgICAgICAgICBib29sIHJpZ2h0ID0gKGFuY2hv
ciA9PSAxIHx8IGFuY2hvciA9PSAzKTsgIC8vIFRSIG9yIEJSCiAgICAgICAgICAgICBib29sIGJv
dHRvbSA9IChhbmNob3IgPT0gMiB8fCBhbmNob3IgPT0gMyk7IC8vIEJMIG9yIEJSCiAgICAgICAg
ICAgICBvdmVybGF5UmVjdC54ID0gcmlnaHQgPyAodmlld3BvcnRXaWR0aCAtIG5ld1N1cmZhY2Ut
PncpIDogMDsKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVy
cy9wbHZrLmNwcCBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9wbHZrLmNw
cAppbmRleCBiYzE2ZmYyLi5iYWMxODViIDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVv
L2ZmbXBlZy1yZW5kZXJlcnMvcGx2ay5jcHAKKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1w
ZWctcmVuZGVyZXJzL3BsdmsuY3BwCkBAIC0xMzgyLDEwICsxMzgyLDEwIEBAIHZvaWQgUGxWa1Jl
bmRlcmVyOjpyZW5kZXJGcmFtZShBVkZyYW1lICpmcmFtZSkKICAgICAgICAgICAgICAgICBvdmVy
bGF5UGFydHNbaV0uZHN0LngwID0gMDsNCiAgICAgICAgICAgICAgICAgb3ZlcmxheVBhcnRzW2ld
LmRzdC55MCA9IFNETF9tYXgoMCwgdGFyZ2V0RnJhbWUuY3JvcC55MSAtIG92ZXJsYXlQYXJ0c1tp
XS5zcmMueTEpOw0KICAgICAgICAgICAgIH0NCi0gICAgICAgICAgICBlbHNlIGlmIChpID09IE92
ZXJsYXk6Ok92ZXJsYXlEZWJ1Zykgew0KLSAgICAgICAgICAgICAgICAvLyBUb3AgbGVmdA0KLSAg
ICAgICAgICAgICAgICBvdmVybGF5UGFydHNbaV0uZHN0LngwID0gMDsNCi0gICAgICAgICAgICAg
ICAgb3ZlcmxheVBhcnRzW2ldLmRzdC55MCA9IDA7DQorICAgICAgICAgICAgZWxzZSBpZiAoaSA9
PSBPdmVybGF5OjpPdmVybGF5RGVidWcgfHwgaSA9PSBPdmVybGF5OjpPdmVybGF5TG9jYWxIYXJk
d2FyZSkgew0KKyAgICAgICAgICAgICAgICBpbnQgYW5jaG9yPVNlc3Npb246OmdldCgpLT5nZXRP
dmVybGF5TWFuYWdlcigpLmdldE92ZXJsYXlBbmNob3Ioc3RhdGljX2Nhc3Q8T3ZlcmxheTo6T3Zl
cmxheVR5cGU+KGkpKTsNCisgICAgICAgICAgICAgICAgb3ZlcmxheVBhcnRzW2ldLmRzdC54MD0o
YW5jaG9yPT0xIHx8IGFuY2hvcj09MykgPyBTRExfbWF4KDAsdGFyZ2V0RnJhbWUuY3JvcC54MS1v
dmVybGF5UGFydHNbaV0uc3JjLngxKSA6IDA7DQorICAgICAgICAgICAgICAgIG92ZXJsYXlQYXJ0
c1tpXS5kc3QueTA9KGFuY2hvcj09MiB8fCBhbmNob3I9PTMpID8gU0RMX21heCgwLHRhcmdldEZy
YW1lLmNyb3AueTEtb3ZlcmxheVBhcnRzW2ldLnNyYy55MSkgOiAwOw0KICAgICAgICAgICAgIH0N
CiAgICAgICAgICAgICBlbHNlIGlmIChpID09IE92ZXJsYXk6Ok92ZXJsYXlUb3VjaEJ1dHRvbk1l
bnUgfHwgaSA9PSBPdmVybGF5OjpPdmVybGF5VG91Y2hCdXR0b25LYmQgfHwNCiAgICAgICAgICAg
ICAgICAgICAgICBpID09IE92ZXJsYXk6Ok92ZXJsYXlUb3VjaEJ1dHRvblRvdWNoTW9kZSkgew0K
ZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy9zZGx2aWQu
Y3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3NkbHZpZC5jcHAKaW5k
ZXggNTY3YmYxOS4uZjEzMjVlZCAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1w
ZWctcmVuZGVyZXJzL3NkbHZpZC5jcHAKKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWct
cmVuZGVyZXJzL3NkbHZpZC5jcHAKQEAgLTI0MSwxMSArMjQxLDExIEBAIHZvaWQgU2RsUmVuZGVy
ZXI6OnJlbmRlck92ZXJsYXkoT3ZlcmxheTo6T3ZlcmxheVR5cGUgdHlwZSkKICAgICAgICAgICAg
ICAgICBtX092ZXJsYXlSZWN0c1t0eXBlXS54ID0gMDsKICAgICAgICAgICAgICAgICBtX092ZXJs
YXlSZWN0c1t0eXBlXS55ID0gdmlld3BvcnRSZWN0LmggLSBuZXdTdXJmYWNlLT5oOwogICAgICAg
ICAgICAgfQotICAgICAgICAgICAgZWxzZSBpZiAodHlwZSA9PSBPdmVybGF5OjpPdmVybGF5RGVi
dWcpIHsKKyAgICAgICAgICAgIGVsc2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVn
IHx8IHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHsKICAgICAgICAgICAg
ICAgICAvLyBWaWJlbWlzOiB1c2VyLWNvbmZpZ3VyYWJsZSBjb3JuZXIgKFNETCBvcmlnaW4gaXMg
dXBwZXItbGVmdCkuCiAgICAgICAgICAgICAgICAgU0RMX1JlY3Qgdmlld3BvcnRSZWN0OwogICAg
ICAgICAgICAgICAgIFNETF9SZW5kZXJHZXRWaWV3cG9ydChtX1JlbmRlcmVyLCAmdmlld3BvcnRS
ZWN0KTsKLSAgICAgICAgICAgICAgICBpbnQgYW5jaG9yID0gU2Vzc2lvbjo6Z2V0KCktPmdldE92
ZXJsYXlNYW5hZ2VyKCkuZ2V0RGVidWdPdmVybGF5QW5jaG9yKCk7CisgICAgICAgICAgICAgICAg
aW50IGFuY2hvciA9IFNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmdldE92ZXJs
YXlBbmNob3IodHlwZSk7CiAgICAgICAgICAgICAgICAgYm9vbCByaWdodCA9IChhbmNob3IgPT0g
MSB8fCBhbmNob3IgPT0gMyk7ICAvLyBUUiBvciBCUgogICAgICAgICAgICAgICAgIGJvb2wgYm90
dG9tID0gKGFuY2hvciA9PSAyIHx8IGFuY2hvciA9PSAzKTsgLy8gQkwgb3IgQlIKICAgICAgICAg
ICAgICAgICBtX092ZXJsYXlSZWN0c1t0eXBlXS54ID0gcmlnaHQgPyAodmlld3BvcnRSZWN0Lncg
LSBuZXdTdXJmYWNlLT53KSA6IDA7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2Zm
bXBlZy1yZW5kZXJlcnMvdmFhcGkuY3BwIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWctcmVu
ZGVyZXJzL3ZhYXBpLmNwcAppbmRleCBhYjY1ZTBiLi4yODQzZmQ2IDEwMDY0NAotLS0gYS9hcHAv
c3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdmFhcGkuY3BwCisrKyBiL2FwcC9zdHJl
YW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVycy92YWFwaS5jcHAKQEAgLTc0MSw5ICs3NDEsOSBA
QCB2b2lkIFZBQVBJUmVuZGVyZXI6Om5vdGlmeU92ZXJsYXlVcGRhdGVkKE92ZXJsYXk6Ok92ZXJs
YXlUeXBlIHR5cGUpCiAgICAgICAgICAgICBvdmVybGF5UmVjdC54ID0gMDsKICAgICAgICAgICAg
IG92ZXJsYXlSZWN0LnkgPSAtbmV3U3VyZmFjZS0+aDsKICAgICAgICAgfQotICAgICAgICBlbHNl
IGlmICh0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZykgeworICAgICAgICBlbHNlIGlmICh0
eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZyB8fCB0eXBlID09IE92ZXJsYXk6Ok92ZXJsYXlM
b2NhbEhhcmR3YXJlKSB7CiAgICAgICAgICAgICAvLyBWaWJlbWlzOiB1c2VyLWNvbmZpZ3VyYWJs
ZSBjb3JuZXIgKHVwcGVyLWxlZnQgb3JpZ2luKS4KLSAgICAgICAgICAgIGludCBhbmNob3IgPSBT
ZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1hbmFnZXIoKS5nZXREZWJ1Z092ZXJsYXlBbmNob3Io
KTsKKyAgICAgICAgICAgIGludCBhbmNob3IgPSBTZXNzaW9uOjpnZXQoKS0+Z2V0T3ZlcmxheU1h
bmFnZXIoKS5nZXRPdmVybGF5QW5jaG9yKHR5cGUpOwogICAgICAgICAgICAgYm9vbCByaWdodCA9
IChhbmNob3IgPT0gMSB8fCBhbmNob3IgPT0gMyk7ICAvLyBUUiBvciBCUgogICAgICAgICAgICAg
Ym9vbCBib3R0b20gPSAoYW5jaG9yID09IDIgfHwgYW5jaG9yID09IDMpOyAvLyBCTCBvciBCUgog
ICAgICAgICAgICAgb3ZlcmxheVJlY3QueCA9IHJpZ2h0ID8gKG1fRGlzcGxheVdpZHRoIC0gbmV3
U3VyZmFjZS0+dykgOiAwOwpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWct
cmVuZGVyZXJzL3ZkcGF1LmNwcCBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLXJlbmRlcmVy
cy92ZHBhdS5jcHAKaW5kZXggMmY5ZTBjMy4uOTA2YWNjYyAxMDA2NDQKLS0tIGEvYXBwL3N0cmVh
bWluZy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3ZkcGF1LmNwcAorKysgYi9hcHAvc3RyZWFtaW5n
L3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdmRwYXUuY3BwCkBAIC00MzYsOSArNDM2LDkgQEAgdm9p
ZCBWRFBBVVJlbmRlcmVyOjpub3RpZnlPdmVybGF5VXBkYXRlZChPdmVybGF5OjpPdmVybGF5VHlw
ZSB0eXBlKQogICAgICAgICAgICAgb3ZlcmxheVJlY3QueDAgPSAwOwogICAgICAgICAgICAgb3Zl
cmxheVJlY3QueTAgPSBtX0Rpc3BsYXlIZWlnaHQgLSBuZXdTdXJmYWNlLT5oOwogICAgICAgICB9
Ci0gICAgICAgIGVsc2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnKSB7CisgICAg
ICAgIGVsc2UgaWYgKHR5cGUgPT0gT3ZlcmxheTo6T3ZlcmxheURlYnVnIHx8IHR5cGUgPT0gT3Zl
cmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmUpIHsKICAgICAgICAgICAgIC8vIFZpYmVtaXM6IHVz
ZXItY29uZmlndXJhYmxlIGNvcm5lciAodXBwZXItbGVmdCBvcmlnaW4pLgotICAgICAgICAgICAg
aW50IGFuY2hvciA9IFNlc3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLmdldERlYnVn
T3ZlcmxheUFuY2hvcigpOworICAgICAgICAgICAgaW50IGFuY2hvciA9IFNlc3Npb246OmdldCgp
LT5nZXRPdmVybGF5TWFuYWdlcigpLmdldE92ZXJsYXlBbmNob3IodHlwZSk7CiAgICAgICAgICAg
ICBib29sIHJpZ2h0ID0gKGFuY2hvciA9PSAxIHx8IGFuY2hvciA9PSAzKTsgIC8vIFRSIG9yIEJS
CiAgICAgICAgICAgICBib29sIGJvdHRvbSA9IChhbmNob3IgPT0gMiB8fCBhbmNob3IgPT0gMyk7
IC8vIEJMIG9yIEJSCiAgICAgICAgICAgICBvdmVybGF5UmVjdC54MCA9IHJpZ2h0ID8gKG1fRGlz
cGxheVdpZHRoIC0gbmV3U3VyZmFjZS0+dykgOiAwOwpkaWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWlu
Zy92aWRlby9mZm1wZWctcmVuZGVyZXJzL3Z0X2F2c2FtcGxlbGF5ZXIubW0gYi9hcHAvc3RyZWFt
aW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdnRfYXZzYW1wbGVsYXllci5tbQppbmRleCBiZDU1
MjgxLi4xM2Q4OGM2IDEwMDY0NAotLS0gYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5k
ZXJlcnMvdnRfYXZzYW1wbGVsYXllci5tbQorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBl
Zy1yZW5kZXJlcnMvdnRfYXZzYW1wbGVsYXllci5tbQpAQCAtNDk2LDYgKzQ5Niw3IEBAIHB1Ymxp
YzoKICAgICAgICAgICAgIFttX092ZXJsYXlUZXh0RmllbGRzW3R5cGVdIHNldFNlbGVjdGFibGU6
Tk9dOwogCiAgICAgICAgICAgICBzd2l0Y2ggKHR5cGUpIHsKKyAgICAgICAgICAgIGNhc2UgT3Zl
cmxheTo6T3ZlcmxheUxvY2FsSGFyZHdhcmU6CiAgICAgICAgICAgICBjYXNlIE92ZXJsYXk6Ok92
ZXJsYXlEZWJ1ZzoKICAgICAgICAgICAgICAgICBbbV9PdmVybGF5VGV4dEZpZWxkc1t0eXBlXSBz
ZXRBbGlnbm1lbnQ6TlNUZXh0QWxpZ25tZW50TGVmdF07CiAgICAgICAgICAgICAgICAgYnJlYWs7
CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdnRfbWV0
YWwubW0gYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2ZmbXBlZy1yZW5kZXJlcnMvdnRfbWV0YWwubW0K
aW5kZXggNzliMTY1ZC4uMzM0ZWVmZiAxMDA2NDQKLS0tIGEvYXBwL3N0cmVhbWluZy92aWRlby9m
Zm1wZWctcmVuZGVyZXJzL3Z0X21ldGFsLm1tCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZt
cGVnLXJlbmRlcmVycy92dF9tZXRhbC5tbQpAQCAtNjAwLDcgKzYwMCw3IEBAIHB1YmxpYzoKICAg
ICAgICAgICAgICAgICAgICAgcmVuZGVyUmVjdC54ID0gMDsKICAgICAgICAgICAgICAgICAgICAg
cmVuZGVyUmVjdC55ID0gMDsKICAgICAgICAgICAgICAgICB9Ci0gICAgICAgICAgICAgICAgZWxz
ZSBpZiAoaSA9PSBPdmVybGF5OjpPdmVybGF5RGVidWcpIHsKKyAgICAgICAgICAgICAgICBlbHNl
IGlmIChpID09IE92ZXJsYXk6Ok92ZXJsYXlEZWJ1ZyB8fCBpID09IE92ZXJsYXk6Ok92ZXJsYXlM
b2NhbEhhcmR3YXJlKSB7CiAgICAgICAgICAgICAgICAgICAgIC8vIFRvcCBsZWZ0CiAgICAgICAg
ICAgICAgICAgICAgIHJlbmRlclJlY3QueCA9IDA7CiAgICAgICAgICAgICAgICAgICAgIHJlbmRl
clJlY3QueSA9IG1fTGFzdERyYXdhYmxlSGVpZ2h0IC0gb3ZlcmxheVRleHR1cmUuaGVpZ2h0Owpk
aWZmIC0tZ2l0IGEvYXBwL3N0cmVhbWluZy92aWRlby9mZm1wZWcuY3BwIGIvYXBwL3N0cmVhbWlu
Zy92aWRlby9mZm1wZWcuY3BwCmluZGV4IDJhYzFhNmUuLjk5NjFhMTIgMTAwNjQ0Ci0tLSBhL2Fw
cC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLmNwcAorKysgYi9hcHAvc3RyZWFtaW5nL3ZpZGVvL2Zm
bXBlZy5jcHAKQEAgLTEsNSArMSw2IEBACiAjaW5jbHVkZSA8TGltZWxpZ2h0Lmg+CiAjaW5jbHVk
ZSAiZmZtcGVnLmgiCisjaW5jbHVkZSAibW9vbmxpZ2h0b3MvbG9jYWxoYXJkd2FyZS5oIgogI2lu
Y2x1ZGUgInN0cmVhbWluZy9zZXNzaW9uLmgiCiAjaW5jbHVkZSAiYmFja2VuZC9zeXN0ZW1wcm9w
ZXJ0aWVzLmgiCiAjaW5jbHVkZSAic2V0dGluZ3Mvc3RyZWFtaW5ncHJlZmVyZW5jZXMuaCIKQEAg
LTg5Nyw2ICs4OTgsNyBAQCB2b2lkIEZGbXBlZ1ZpZGVvRGVjb2Rlcjo6Y2FjaGVEZWNvZGVySWRl
bnRpdHkoKQogICAgIH0KIAogICAgIGlmIChtX0Zyb250ZW5kUmVuZGVyZXIgIT0gbnVsbHB0cikg
eworICAgICAgICBtX1ByZXNlbnRhdGlvblJlbmRlcmVyTmFtZSA9IFFCeXRlQXJyYXkobV9Gcm9u
dGVuZFJlbmRlcmVyLT5nZXRSZW5kZXJlck5hbWUoKSk7CiAgICAgICAgIGNvbnN0IGNoYXIqIHBy
ZXNlbnRNb2RlID0gbV9Gcm9udGVuZFJlbmRlcmVyLT5nZXRQcmVzZW50YXRpb25Nb2RlTmFtZSgp
OwogICAgICAgICBpZiAocHJlc2VudE1vZGUgIT0gbnVsbHB0cikgewogICAgICAgICAgICAgbV9Q
cmVzZW50TW9kZU5hbWUgPSBRQnl0ZUFycmF5KHByZXNlbnRNb2RlKTsKQEAgLTEyOTgsNiArMTMw
MCwxNiBAQCB2b2lkIEZGbXBlZ1ZpZGVvRGVjb2Rlcjo6c3RyaW5naWZ5VmlkZW9TdGF0cyhWSURF
T19TVEFUUyYgc3RhdHMsIGNoYXIqIG91dHB1dCwgaQogCiAgICAgb2Zmc2V0ICs9IHJldDsKIAor
ICAgIC8vIFRoZSBkZWNvZGVyJ3MgInZpYSIgbGFiZWwgbmFtZXMgdGhlIGJhY2tlbmQsIG5vdCB3
aG8gZHJhd3MgdGhlIGZyYW1lLgorICAgIC8vIEV4cG9zZSB0aGUgY2FjaGVkIHByZXNlbnRhdGlv
biBmcm9udGVuZCBmb3IgRUdML1ZBQVBJL1Z1bGthbiBjb21wYXJpc29ucy4KKyAgICByZXQgPSBE
ZWNvZGVyU3RhdHVzOjpmb3JtYXRQcmVzZW50YXRpb25MaW5lKCZvdXRwdXRbb2Zmc2V0XSwgbGVu
Z3RoIC0gb2Zmc2V0LAorICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgbV9QcmVzZW50YXRpb25SZW5kZXJlck5hbWUuY29uc3REYXRhKCkpOworICAgIGlmIChy
ZXQgPCAwIHx8IHJldCA+PSBsZW5ndGggLSBvZmZzZXQpIHsKKyAgICAgICAgU0RMX2Fzc2VydChm
YWxzZSk7CisgICAgICAgIHJldHVybjsKKyAgICB9CisgICAgb2Zmc2V0ICs9IHJldDsKKwogICAg
IGlmIChzdGF0cy5mcmFtZXNXaXRoSG9zdFByb2Nlc3NpbmdMYXRlbmN5ID4gMCkgewogICAgICAg
ICByZXQgPSBzbnByaW50Zigmb3V0cHV0W29mZnNldF0sCiAgICAgICAgICAgICAgICAgICAgICAg
IGxlbmd0aCAtIG9mZnNldCwKQEAgLTI0NDAsNiArMjQ1MiwxMSBAQCBpbnQgRkZtcGVnVmlkZW9E
ZWNvZGVyOjpzdWJtaXREZWNvZGVVbml0KFBERUNPREVfVU5JVCBkdSkKICAgICAgICAgICAgIFNl
c3Npb246OmdldCgpLT5nZXRPdmVybGF5TWFuYWdlcigpLnNldE92ZXJsYXlUZXh0VXBkYXRlZChP
dmVybGF5OjpPdmVybGF5RGVidWcpOwogICAgICAgICB9CiAKKyAgICAgICAgaWYoU2Vzc2lvbjo6
Z2V0KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkuaXNPdmVybGF5RW5hYmxlZChPdmVybGF5OjpPdmVy
bGF5TG9jYWxIYXJkd2FyZSkpIHsKKyAgICAgICAgICAgIFFCeXRlQXJyYXkgdGV4dD1Mb2NhbEhh
cmR3YXJlOjpvdmVybGF5VGV4dCgpLnRvVXRmOCgpOworICAgICAgICAgICAgU2Vzc2lvbjo6Z2V0
KCktPmdldE92ZXJsYXlNYW5hZ2VyKCkudXBkYXRlT3ZlcmxheVRleHQoT3ZlcmxheTo6T3Zlcmxh
eUxvY2FsSGFyZHdhcmUsdGV4dC5jb25zdERhdGEoKSk7CisgICAgICAgIH0KKwogICAgICAgICAv
LyBBY2N1bXVsYXRlIHRoZXNlIHZhbHVlcyBpbnRvIHRoZSBnbG9iYWwgc3RhdHMKICAgICAgICAg
YWRkVmlkZW9TdGF0cyhtX0FjdGl2ZVduZFZpZGVvU3RhdHMsIG1fR2xvYmFsVmlkZW9TdGF0cyk7
CiAKZGlmZiAtLWdpdCBhL2FwcC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLmggYi9hcHAvc3RyZWFt
aW5nL3ZpZGVvL2ZmbXBlZy5oCmluZGV4IDllYmNlNDIuLjM0OGVkZTMgMTAwNjQ0Ci0tLSBhL2Fw
cC9zdHJlYW1pbmcvdmlkZW8vZmZtcGVnLmgKKysrIGIvYXBwL3N0cmVhbWluZy92aWRlby9mZm1w
ZWcuaApAQCAtMTMwLDYgKzEzMCw3IEBAIHByaXZhdGU6CiAgICAgLy8gdGhlIGxpZmUgb2YgdGhl
IGRlY29kZXIuCiAgICAgUUJ5dGVBcnJheSBtX1BhY2luZ01vZGVOYW1lOwogICAgIFFCeXRlQXJy
YXkgbV9QcmVzZW50TW9kZU5hbWU7CisgICAgUUJ5dGVBcnJheSBtX1ByZXNlbnRhdGlvblJlbmRl
cmVyTmFtZTsKIAogICAgIFBhY2VyKiBtX1BhY2VyOwogICAgIFBhY2VyVGVsZW1ldHJ5U25hcHNo
b3QgbV9MYXN0UGFjZXJUZWxlbWV0cnk7CmRpZmYgLS1naXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVv
L292ZXJsYXltYW5hZ2VyLmNwcCBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vb3ZlcmxheW1hbmFnZXIu
Y3BwCmluZGV4IDkyZTZjNmQuLjFhYTA4NGIgMTAwNjQ0Ci0tLSBhL2FwcC9zdHJlYW1pbmcvdmlk
ZW8vb3ZlcmxheW1hbmFnZXIuY3BwCisrKyBiL2FwcC9zdHJlYW1pbmcvdmlkZW8vb3ZlcmxheW1h
bmFnZXIuY3BwCkBAIC0xLDYgKzEsMTIgQEAKICNpbmNsdWRlICJvdmVybGF5bWFuYWdlci5oIgog
I2luY2x1ZGUgInBhdGguaCIKICNpbmNsdWRlICJzZXR0aW5ncy9zdHJlYW1pbmdwcmVmZXJlbmNl
cy5oIgorI2luY2x1ZGUgIm1vb25saWdodG9zL2xvY2FsaGFyZHdhcmUuaCIKKyNpbmNsdWRlICJt
b29ubGlnaHRvcy9vdmVybGF5c3R5bGUuaCIKKyNpbmNsdWRlIDxRU2V0dGluZ3M+CisjaW5jbHVk
ZSA8UUltYWdlPgorI2luY2x1ZGUgPFFQYWludGVyPgorI2luY2x1ZGUgPFFDb2xvcj4KIAogdXNp
bmcgbmFtZXNwYWNlIE92ZXJsYXk7CiAKQEAgLTksNiArMTUsMTMgQEAgaW50IE92ZXJsYXlNYW5h
Z2VyOjpnZXREZWJ1Z092ZXJsYXlBbmNob3IoKQogICAgIHJldHVybiBzdGF0aWNfY2FzdDxpbnQ+
KFN0cmVhbWluZ1ByZWZlcmVuY2VzOjpnZXQoKS0+cGVyZk92ZXJsYXlQb3NpdGlvbik7CiB9CiAK
K2ludCBPdmVybGF5TWFuYWdlcjo6Z2V0T3ZlcmxheUFuY2hvcihPdmVybGF5VHlwZSB0eXBlKSB7
CisgICAgaW50IHN0cmVhbT1nZXREZWJ1Z092ZXJsYXlBbmNob3IoKTsKKyAgICBpZih0eXBlIT1P
dmVybGF5TG9jYWxIYXJkd2FyZSkgcmV0dXJuIHN0cmVhbTsKKyAgICBpbnQgbG9jYWw9cUJvdW5k
KDAsUVNldHRpbmdzKCkudmFsdWUoImVjbGlwc2UvbG9jYWxQb3NpdGlvbiIsMSkudG9JbnQoKSwz
KTsKKyAgICByZXR1cm4gaXNPdmVybGF5RW5hYmxlZChPdmVybGF5RGVidWcpICYmIGxvY2FsPT1z
dHJlYW0gPyAobG9jYWwgXiAxKSA6IGxvY2FsOworfQorCiBPdmVybGF5TWFuYWdlcjo6T3Zlcmxh
eU1hbmFnZXIoKSA6CiAgICAgbV9SZW5kZXJlcihudWxscHRyKSwKICAgICBtX0ZvbnREYXRhKFBh
dGg6OnJlYWREYXRhRmlsZSgiTW9kZVNldmVuLnR0ZiIpKQpAQCAtMzIsOCArNDUsMTAgQEAgT3Zl
cmxheU1hbmFnZXI6Ok92ZXJsYXlNYW5hZ2VyKCkgOgogICAgICAgICBicmVhazsKICAgICB9CiAK
LSAgICBtX092ZXJsYXlzW092ZXJsYXlUeXBlOjpPdmVybGF5RGVidWddLmNvbG9yID0gezB4RDAs
IDB4RDAsIDB4MDAsIDB4RkZ9OworICAgIG1fT3ZlcmxheXNbT3ZlcmxheVR5cGU6Ok92ZXJsYXlE
ZWJ1Z10uY29sb3IgPSB7MHhFQywgMHhFRSwgMHhGMSwgMHhGRn07CiAgICAgbV9PdmVybGF5c1tP
dmVybGF5VHlwZTo6T3ZlcmxheURlYnVnXS5mb250U2l6ZSA9IGRlYnVnRm9udFNpemU7CisgICAg
bV9PdmVybGF5c1tPdmVybGF5TG9jYWxIYXJkd2FyZV0uY29sb3IgPSB7MHhFQywweEVFLDB4RjEs
MHhGRn07CisgICAgbV9PdmVybGF5c1tPdmVybGF5TG9jYWxIYXJkd2FyZV0uZm9udFNpemUgPSBk
ZWJ1Z0ZvbnRTaXplOwogCiAgICAgbV9PdmVybGF5c1tPdmVybGF5VHlwZTo6T3ZlcmxheVN0YXR1
c1VwZGF0ZV0uY29sb3IgPSB7MHhDQywgMHgwMCwgMHgwMCwgMHhGRn07CiAgICAgbV9PdmVybGF5
c1tPdmVybGF5VHlwZTo6T3ZlcmxheVN0YXR1c1VwZGF0ZV0uZm9udFNpemUgPSAzNjsKQEAgLTEy
Niw2ICsxNDEsMTQgQEAgU0RMX1N1cmZhY2UqIE92ZXJsYXlNYW5hZ2VyOjpnZXRVcGRhdGVkT3Zl
cmxheVN1cmZhY2UoT3ZlcmxheVR5cGUgdHlwZSkKIAogdm9pZCBPdmVybGF5TWFuYWdlcjo6c2V0
T3ZlcmxheVRleHRVcGRhdGVkKE92ZXJsYXlUeXBlIHR5cGUpCiB7CisgICAgaWYobV9PdmVybGF5
c1t0eXBlXS5lbmFibGVkICYmICh0eXBlPT1PdmVybGF5RGVidWcgfHwgdHlwZT09T3ZlcmxheUxv
Y2FsSGFyZHdhcmUpKSB7CisgICAgICAgIC8vIFNhbXBsaW5nIG1heSB0b3VjaCBzbG93IHN5c2Zz
IHNlbnNvcnMgYW5kIFVTQi1iYWNrZWQgZmlsZXN5c3RlbSBzdGF0cy4KKyAgICAgICAgLy8gRG8g
aXQgYmVmb3JlIHRoZSBoaXN0b3J5IGxvY2s6IHRoZSByZW5kZXIgdGhyZWFkIG11c3QgYmUgYWJs
ZSB0byBjb3B5CisgICAgICAgIC8vIGl0cyBsYXN0IGdyYXBoIHNuYXBzaG90IHdpdGhvdXQgd2Fp
dGluZyBmb3IgdGhvc2UgcmVhZHMgdG8gZmluaXNoLgorICAgICAgICBjb25zdCBhdXRvIHZhbHVl
cz1Dcmltc29uR3JhcGhzOjp2YWx1ZXMoUVN0cmluZzo6ZnJvbVV0ZjgobV9PdmVybGF5c1t0eXBl
XS50ZXh0KSx0eXBlPT1PdmVybGF5TG9jYWxIYXJkd2FyZSxMb2NhbEhhcmR3YXJlOjpzYW1wbGUo
KSk7CisgICAgICAgIFFNdXRleExvY2tlciBncmFwaExvY2soJm1fR3JhcGhMb2NrKTsKKyAgICAg
ICAgQ3JpbXNvbkdyYXBoczo6cHVzaChtX0dyYXBoSGlzdG9yeVt0eXBlXSx2YWx1ZXMpOworICAg
IH0KICAgICAvLyBPbmx5IHVwZGF0ZSB0aGUgb3ZlcmxheSBzdGF0ZSBpZiBpdCdzIGVuYWJsZWQu
IElmIGl0J3Mgbm90IGVuYWJsZWQsCiAgICAgLy8gdGhlIHJlbmRlcmVyIGhhcyBhbHJlYWR5IGJl
ZW4gbm90aWZpZWQgYnkgc2V0T3ZlcmxheVN0YXRlKCkuCiAgICAgaWYgKG1fT3ZlcmxheXNbdHlw
ZV0uZW5hYmxlZCkgewpAQCAtMTQzLDYgKzE2Niw3IEBAIHZvaWQgT3ZlcmxheU1hbmFnZXI6OnNl
dE92ZXJsYXlTdGF0ZShPdmVybGF5VHlwZSB0eXBlLCBib29sIGVuYWJsZWQpCiAgICAgICAgIGlm
ICghZW5hYmxlZCkgewogICAgICAgICAgICAgLy8gU2V0IHRoZSB0ZXh0IHRvIGVtcHR5IHN0cmlu
ZyBvbiBkaXNhYmxlCiAgICAgICAgICAgICBtX092ZXJsYXlzW3R5cGVdLnRleHRbMF0gPSAwOwor
ICAgICAgICAgICAgeyBRTXV0ZXhMb2NrZXIgZ3JhcGhMb2NrKCZtX0dyYXBoTG9jayk7bV9HcmFw
aEhpc3RvcnlbdHlwZV0uY2xlYXIoKTsgfQogICAgICAgICB9CiAKICAgICAgICAgbm90aWZ5T3Zl
cmxheVVwZGF0ZWQodHlwZSk7CkBAIC0zNjgsMTEgKzM5MiwyNyBAQCB2b2lkIE92ZXJsYXlNYW5h
Z2VyOjpub3RpZnlPdmVybGF5VXBkYXRlZChPdmVybGF5VHlwZSB0eXBlKQogICAgIH0KIAogICAg
IGlmIChtX092ZXJsYXlzW3R5cGVdLmVuYWJsZWQpIHsKLSAgICAgICAgLy8gVGhlIF9XcmFwcGVk
IHZhcmlhbnQgaXMgcmVxdWlyZWQgZm9yIGxpbmUgYnJlYWtzIHRvIHdvcmsKLSAgICAgICAgU0RM
X1N1cmZhY2UqIHN1cmZhY2UgPSBUVEZfUmVuZGVyVGV4dF9CbGVuZGVkX1dyYXBwZWQobV9PdmVy
bGF5c1t0eXBlXS5mb250LAotICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICBtX092ZXJsYXlzW3R5cGVdLnRleHQsCi0gICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIG1fT3Zl
cmxheXNbdHlwZV0uY29sb3IsCi0gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgIDEwMjQpOworICAgICAgICBRQnl0ZUFycmF5IHRleHQo
bV9PdmVybGF5c1t0eXBlXS50ZXh0KTsKKyAgICAgICAgY29uc3QgYm9vbCBjYXJkPXR5cGU9PU92
ZXJsYXlEZWJ1ZyB8fCB0eXBlPT1PdmVybGF5TG9jYWxIYXJkd2FyZTsKKyAgICAgICAgY29uc3Qg
Ym9vbCBkZXRhaWxlZD1RU2V0dGluZ3MoKS52YWx1ZSh0eXBlPT1PdmVybGF5RGVidWc/ImVjbGlw
c2Uvc3RyZWFtRGV0YWlsZWQiOiJlY2xpcHNlL2xvY2FsRGV0YWlsZWQiLGZhbHNlKS50b0Jvb2wo
KTsKKyAgICAgICAgaWYoY2FyZCAmJiAhZGV0YWlsZWQpIHRleHQ9KHR5cGU9PU92ZXJsYXlEZWJ1
Zz8iRWNsaXBzZU9TIHwgU1RSRUFNIjoiRWNsaXBzZU9TIHwgTE9DQUwiKTsKKyAgICAgICAgZWxz
ZSBpZih0eXBlPT1PdmVybGF5RGVidWcpIHRleHQucHJlcGVuZCgiRWNsaXBzZU9TIHwgU1RSRUFN
XG4iKTsKKyAgICAgICAgU0RMX1N1cmZhY2UqIHN1cmZhY2U9VFRGX1JlbmRlclVURjhfQmxlbmRl
ZF9XcmFwcGVkKG1fT3ZlcmxheXNbdHlwZV0uZm9udCx0ZXh0LmNvbnN0RGF0YSgpLG1fT3Zlcmxh
eXNbdHlwZV0uY29sb3IsY2FyZD80ODA6MTAyNCk7CisgICAgICAgIGlmKGNhcmQgJiYgc3VyZmFj
ZSkgeworICAgICAgICAgICAgaW50IGZvbnRTaXplPW1fT3ZlcmxheXNbdHlwZV0uZm9udFNpemU7
CisgICAgICAgICAgICBpbnQgZ3JhcGhIZWlnaHQ9NCooZm9udFNpemUrMjIpKzEyOworICAgICAg
ICAgICAgaW50IHdpZHRoPXFNYXgoc3VyZmFjZS0+dyszMiw0ODApOworICAgICAgICAgICAgUUlt
YWdlIGltYWdlPUVjbGlwc2VPdmVybGF5U3R5bGU6OnBhbmVsKFFTaXplKHdpZHRoLHN1cmZhY2Ut
PmgrMzIrZ3JhcGhIZWlnaHQpLFN0cmVhbWluZ1ByZWZlcmVuY2VzOjpnZXQoKS0+dWlBY2NlbnRJ
bmRleCxRU2V0dGluZ3MoKS52YWx1ZSgiZWNsaXBzZS9vdmVybGF5T3BhY2l0eSIsODUpLnRvSW50
KCkpOworICAgICAgICAgICAgQ3JpbXNvbkdyYXBoczo6SGlzdG9yeSBoaXN0b3J5OworICAgICAg
ICAgICAgeyBRTXV0ZXhMb2NrZXIgZ3JhcGhMb2NrKCZtX0dyYXBoTG9jayk7aGlzdG9yeT1tX0dy
YXBoSGlzdG9yeVt0eXBlXTsgfQorICAgICAgICAgICAgaWYoIWltYWdlLmlzTnVsbCgpKSBDcmlt
c29uR3JhcGhzOjpwYWludChpbWFnZSxzdXJmYWNlLT5oKzI0LHFNaW4oZm9udFNpemUsMjApLFN0
cmVhbWluZ1ByZWZlcmVuY2VzOjpnZXQoKS0+dWlBY2NlbnRJbmRleCxoaXN0b3J5LHR5cGU9PU92
ZXJsYXlMb2NhbEhhcmR3YXJlKTsKKyAgICAgICAgICAgIFNETF9TdXJmYWNlKiBwYW5lbD1pbWFn
ZS5pc051bGwoKT9udWxscHRyOlNETF9DcmVhdGVSR0JTdXJmYWNlV2l0aEZvcm1hdCgwLGltYWdl
LndpZHRoKCksaW1hZ2UuaGVpZ2h0KCksMzIsU0RMX1BJWEVMRk9STUFUX1JHQkEzMik7CisgICAg
ICAgICAgICBpZihwYW5lbCkgeworICAgICAgICAgICAgICAgIGZvcihpbnQgcm93PTA7cm93PGlt
YWdlLmhlaWdodCgpOysrcm93KSBtZW1jcHkoc3RhdGljX2Nhc3Q8Y2hhcio+KHBhbmVsLT5waXhl
bHMpK3JvdypwYW5lbC0+cGl0Y2gsaW1hZ2UuY29uc3RTY2FuTGluZShyb3cpLGltYWdlLndpZHRo
KCkqNCk7CisgICAgICAgICAgICAgICAgU0RMX1JlY3QgZGVzdD17MTYsMTYsc3VyZmFjZS0+dyxz
dXJmYWNlLT5ofTtTRExfQmxpdFN1cmZhY2Uoc3VyZmFjZSxudWxscHRyLHBhbmVsLCZkZXN0KTsK
KyAgICAgICAgICAgICAgICBTRExfRnJlZVN1cmZhY2Uoc3VyZmFjZSk7c3VyZmFjZT1wYW5lbDsK
KyAgICAgICAgICAgIH0KKyAgICAgICAgfQogCiAgICAgICAgIFNETF9BdG9taWNTZXRQdHIoKHZv
aWQqKikmbV9PdmVybGF5c1t0eXBlXS5zdXJmYWNlLCBzdXJmYWNlKTsKICAgICB9CmRpZmYgLS1n
aXQgYS9hcHAvc3RyZWFtaW5nL3ZpZGVvL292ZXJsYXltYW5hZ2VyLmggYi9hcHAvc3RyZWFtaW5n
L3ZpZGVvL292ZXJsYXltYW5hZ2VyLmgKaW5kZXggZTE5ZmMwYy4uNDExMmExZCAxMDA2NDQKLS0t
IGEvYXBwL3N0cmVhbWluZy92aWRlby9vdmVybGF5bWFuYWdlci5oCisrKyBiL2FwcC9zdHJlYW1p
bmcvdmlkZW8vb3ZlcmxheW1hbmFnZXIuaApAQCAtMiw2ICsyLDcgQEAKIAogI2luY2x1ZGUgPFFT
dHJpbmc+CiAjaW5jbHVkZSA8UU11dGV4PgorI2luY2x1ZGUgIm1vb25saWdodG9zL2NyaW1zb25n
cmFwaHMuaCIKIAogI2luY2x1ZGUgIlNETF9jb21wYXQuaCIKICNpbmNsdWRlIDxTRExfdHRmLmg+
CkBAIC0xMCw2ICsxMSw3IEBAIG5hbWVzcGFjZSBPdmVybGF5IHsKIAogZW51bSBPdmVybGF5VHlw
ZSB7CiAgICAgT3ZlcmxheURlYnVnLAorICAgIE92ZXJsYXlMb2NhbEhhcmR3YXJlLAogICAgIE92
ZXJsYXlTdGF0dXNVcGRhdGUsCiAgICAgT3ZlcmxheVNlcnZlckNvbW1hbmRzLAogICAgIE92ZXJs
YXlRdWlja01lbnUsCkBAIC03MCw2ICs3Miw3IEBAIHB1YmxpYzoKICAgICAvLyBwcmVmZXJlbmNl
LiBSZXR1cm5zIFN0cmVhbWluZ1ByZWZlcmVuY2VzOjpQZXJmT3ZlcmxheVBvc2l0aW9uIGFzIGFu
IGludAogICAgIC8vICgwPVRMLCAxPVRSLCAyPUJMLCAzPUJSKS4gUmVuZGVyZXJzIG1hcCB0aGlz
IHRvIHRoZWlyIG93biBjb29yZGluYXRlIHNwYWNlLgogICAgIGludCBnZXREZWJ1Z092ZXJsYXlB
bmNob3IoKTsKKyAgICBpbnQgZ2V0T3ZlcmxheUFuY2hvcihPdmVybGF5VHlwZSB0eXBlKTsKIAog
ICAgIHZvaWQgc2V0T3ZlcmxheVJlbmRlcmVyKElPdmVybGF5UmVuZGVyZXIqIHJlbmRlcmVyKTsK
IApAQCAtMTE3LDYgKzEyMCw4IEBAIHByaXZhdGU6CiAgICAgSU92ZXJsYXlSZW5kZXJlciogbV9S
ZW5kZXJlcjsKICAgICBRTXV0ZXggbV9SZW5kZXJlckxvY2s7ICAgLy8gZ3VhcmRzIG1fUmVuZGVy
ZXIgc3dhcCB2cyBjcm9zcy10aHJlYWQgbm90aWZ5CiAgICAgUUJ5dGVBcnJheSBtX0ZvbnREYXRh
OworICAgIFFNdXRleCBtX0dyYXBoTG9jazsKKyAgICBDcmltc29uR3JhcGhzOjpIaXN0b3J5IG1f
R3JhcGhIaXN0b3J5W092ZXJsYXlNYXhdOwogfTsKIAogfQpkaWZmIC0tZ2l0IGEvcGFja2FnaW5n
L2ZsYXRwYWsvaW8uZ2l0aHViLm5hdnlhczMyMS5WaWJlbWlzLmRlc2t0b3AgYi9wYWNrYWdpbmcv
ZmxhdHBhay9pby5naXRodWIubmF2eWFzMzIxLlZpYmVtaXMuZGVza3RvcAppbmRleCAwNDVhZGJl
Li5mMTJkYTVkIDEwMDY0NAotLS0gYS9wYWNrYWdpbmcvZmxhdHBhay9pby5naXRodWIubmF2eWFz
MzIxLlZpYmVtaXMuZGVza3RvcAorKysgYi9wYWNrYWdpbmcvZmxhdHBhay9pby5naXRodWIubmF2
eWFzMzIxLlZpYmVtaXMuZGVza3RvcApAQCAtMSw2ICsxLDYgQEAKIFtEZXNrdG9wIEVudHJ5XQog
VHlwZT1BcHBsaWNhdGlvbgotTmFtZT1WaWJlbWlzCitOYW1lPUVjbGlwc2UKIEdlbmVyaWNOYW1l
PUdhbWUgU3RyZWFtaW5nIENsaWVudAogQ29tbWVudD1TdHJlYW0gZ2FtZXMgYW5kIGFwcGxpY2F0
aW9ucyBmcm9tIGEgU3Vuc2hpbmUgLyBBcG9sbG8gLyBWaWJlcG9sbG8gaG9zdAogRXhlYz12aWJl
bWlzCmRpZmYgLS1naXQgYS90ZXN0cy9vdmVybGF5L3RzdF9kZWNvZGVyc3RhdHVzLmNwcCBiL3Rl
c3RzL292ZXJsYXkvdHN0X2RlY29kZXJzdGF0dXMuY3BwCmluZGV4IGI0ZDc2ODIuLjUwYjA3MGMg
MTAwNjQ0Ci0tLSBhL3Rlc3RzL292ZXJsYXkvdHN0X2RlY29kZXJzdGF0dXMuY3BwCisrKyBiL3Rl
c3RzL292ZXJsYXkvdHN0X2RlY29kZXJzdGF0dXMuY3BwCkBAIC0zOCw2ICszOCwzMCBAQCBwcml2
YXRlOgogICAgIH0KIAogcHJpdmF0ZSBzbG90czoKKyAgICB2b2lkIHByZXNlbnRhdGlvblJlbmRl
cmVySXNTZXBhcmF0ZUZyb21EZWNvZGVyQmFja2VuZCgpCisgICAgeworICAgICAgICBjaGFyIGJ1
ZlsxMjhdOworICAgICAgICBEZWNvZGVyU3RhdHVzOjpmb3JtYXRQcmVzZW50YXRpb25MaW5lKGJ1
Ziwgc2l6ZW9mKGJ1ZiksICJFR0wiKTsKKyAgICAgICAgUUNPTVBBUkUoUUJ5dGVBcnJheShidWYp
LCBRQnl0ZUFycmF5KCJSZW5kZXJlcjogRUdMXG4iKSk7CisgICAgICAgIFFWRVJJRlkoIVFCeXRl
QXJyYXkoYnVmKS5jb250YWlucygiVkFBUEkiKSk7CisgICAgfQorICAgIHZvaWQgbWlzc2luZ1By
ZXNlbnRhdGlvblJlbmRlcmVySXNVbmtub3duKCkKKyAgICB7CisgICAgICAgIGNoYXIgYnVmWzEy
OF07CisgICAgICAgIERlY29kZXJTdGF0dXM6OmZvcm1hdFByZXNlbnRhdGlvbkxpbmUoYnVmLCBz
aXplb2YoYnVmKSwgbnVsbHB0cik7CisgICAgICAgIFFDT01QQVJFKFFCeXRlQXJyYXkoYnVmKSwg
UUJ5dGVBcnJheSgiUmVuZGVyZXI6IHVua25vd25cbiIpKTsKKyAgICB9CisgICAgdm9pZCBwcmVz
ZW50YXRpb25SZW5kZXJlcklzQm91bmRlZEFuZFRlcm1pbmF0ZXNUaW55QnVmZmVycygpCisgICAg
eworICAgICAgICBRQnl0ZUFycmF5IGxvbmdOYW1lKDEwMDAsICdYJyk7CisgICAgICAgIGNoYXIg
YnVmWzEyOF07CisgICAgICAgIGludCByZXQ9RGVjb2RlclN0YXR1czo6Zm9ybWF0UHJlc2VudGF0
aW9uTGluZShidWYsIHNpemVvZihidWYpLCBsb25nTmFtZS5jb25zdERhdGEoKSk7CisgICAgICAg
IFFDT01QQVJFKHJldCwgRGVjb2RlclN0YXR1czo6TWF4UHJlc2VudGF0aW9uTGluZUNoYXJzKTsK
KyAgICAgICAgY2hhciB0aW55WzJdPXsnWScsJ1knfTsKKyAgICAgICAgcmV0PURlY29kZXJTdGF0
dXM6OmZvcm1hdFByZXNlbnRhdGlvbkxpbmUodGlueSwgc2l6ZW9mKHRpbnkpLCAiRUdMIik7Cisg
ICAgICAgIFFWRVJJRlkocmV0PjEpOworICAgICAgICBRQ09NUEFSRSh0aW55WzFdLCBjaGFyKDAp
KTsKKyAgICB9CiAgICAgLy8gLS0tLSBUaGUgcmVhc29uIHRoZSBsaW5lIGV4aXN0cyAtLS0tLS0t
LS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KIAogICAgIC8vIFRoZSBleGFjdCBCTC0yNDA4
IHNoYXBlOiBhIEdhbGxpdW0gVkFBUEkgYmFja2VuZCB3aG9zZSBSRkkgY2FwYWJpbGl0eSB3YXMK
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

# Fixed-base updater: disabled until owner provisions an Ed25519 public key.
install -d -m 0755 /etc/eclipseos-update /usr/local/libexec/eclipseos
install -d -m 0700 /var/lib/eclipseos-updates
cat > /usr/local/libexec/moonlight-os/eclipseos-update.py <<'ECLIPSE_UPDATER'
#!/usr/bin/python3
"""Signed, fixed-base updates. No package-supplied commands or arbitrary destinations."""
import argparse
import contextlib
import fcntl
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import urllib.parse

BASE_ID = 'eclipseos-f44-mbp14-1-v1'
KERNEL = '6.19.10-300.fc44.x86_64'
HELPER = '/usr/local/libexec/moonlight-os/eclipseos-update.py'
STATE = '/var/lib/eclipseos-updates'
RELEASES = '/usr/local/libexec/eclipseos/releases'
KEY = '/etc/eclipseos-update/public.pem'
MAX_ARCHIVE = 256 * 1024 * 1024
MAX_EXPANDED = 384 * 1024 * 1024
TARGETS = {
    'frontend': (None, 0o755, None),
    'system-controls': ('/usr/local/libexec/moonlight-os/system-controls.py', 0o755, None),
    'control-center': ('/usr/local/libexec/moonlight-os/control-center.py', 0o755, None),
    'bluetooth-menu': ('/usr/local/bin/moonlight-bluetooth', 0o755, None),
    'streaming-tune': ('/usr/local/bin/eclipseos-streaming', 0o755, None),
    'wifi-menu': ('/usr/local/bin/moonlight-wifi', 0o755, None),
    'wifi-config': ('/etc/NetworkManager/conf.d/99-moonlight-wifi.conf', 0o644, 'NetworkManager.service'),
    'bluetooth-config': ('/etc/bluetooth/main.conf', 0o644, 'bluetooth.service'),
}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key')
        result[key] = value
    return result

def decode(data):
    return json.loads(data, object_pairs_hook=unique_object)

def atomic(path, data, mode=0o600):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.update-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            os.fchmod(out.fileno(), mode)
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
        sync_dir(path.parent)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)

def read_regular(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        import stat
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > limit:
            raise ValueError('Invalid or oversized file')
        with os.fdopen(fd, 'rb', closefd=False) as src:
            data = src.read(limit + 1)
        if len(data) > limit:
            raise ValueError('Oversized file')
        return data
    finally:
        os.close(fd)

def manifest_validate(m):
    if set(m) != {'schema', 'base', 'id', 'sequence', 'channel', 'source', 'notes', 'files', 'archive'}:
        raise ValueError('Unsupported manifest fields')
    if m['schema'] != 1 or m['base'] != BASE_ID:
        raise ValueError('Update targets a different base OS')
    if not isinstance(m['id'], str) or not re.fullmatch(r'[a-z0-9][a-z0-9.-]{0,63}', m['id']):
        raise ValueError('Invalid update ID')
    if type(m['sequence']) is not int or m['sequence'] < 1 or m['channel'] not in ('stable', 'testing'):
        raise ValueError('Invalid update channel or sequence')
    if not isinstance(m['source'], str) or not re.fullmatch(r'[0-9a-f]{40}', m['source']):
        raise ValueError('Missing source commit')
    if not isinstance(m['notes'], str) or len(m['notes']) > 4096:
        raise ValueError('Invalid release notes')
    if not isinstance(m['files'], list) or not 1 <= len(m['files']) <= len(TARGETS):
        raise ValueError('Invalid file count')
    seen = set()
    for item in m['files']:
        if set(item) != {'target', 'sha256', 'size', 'before_sha256'}:
            raise ValueError('Invalid file fields')
        name = item['target']
        if name not in TARGETS or name in seen:
            raise ValueError('Unsupported or duplicate target')
        seen.add(name)
        if not isinstance(item['sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', item['sha256']):
            raise ValueError('Invalid file checksum')
        if type(item['size']) is not int or not 0 < item['size'] <= MAX_EXPANDED:
            raise ValueError('Invalid file size')
        before = item['before_sha256']
        if name == 'frontend':
            if before is not None:
                raise ValueError('Frontend baseline must be null')
        elif not isinstance(before, str) or not re.fullmatch(r'[0-9a-f]{64}', before):
            raise ValueError('System files require a matching baseline checksum')
    archive = m['archive']
    if set(archive) != {'sha256', 'size', 'url'} or not re.fullmatch(r'[0-9a-f]{64}', archive['sha256']):
        raise ValueError('Invalid archive checksum')
    if type(archive['size']) is not int or not 0 < archive['size'] <= MAX_ARCHIVE:
        raise ValueError('Invalid archive size')
    if sum(i['size'] for i in m['files']) > MAX_EXPANDED:
        raise ValueError('Expanded package too large')
    validate_url(archive['url'], initial=True)
    return m

def validate_url(url, initial=False):
    p = urllib.parse.urlsplit(url)
    hosts = {'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}
    if p.scheme != 'https' or p.hostname not in hosts or p.username or p.password or p.port not in (None, 443):
        raise ValueError('Untrusted download destination')
    if initial and (p.hostname != 'github.com' or not p.path.startswith('/th3d3ck3r/Moonlight-OS/releases/download/') or p.query or p.fragment or '..' in p.path):
        raise ValueError('Package must be published by Moonlight-OS')

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)

def download(url, limit):
    validate_url(url, initial=True)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), SafeRedirect())
    with opener.open(url, timeout=30) as response:
        started = time.monotonic()
        chunks, received = [], 0
        while received <= limit:
            if time.monotonic() - started > 600:
                raise ValueError('Download deadline exceeded')
            chunk = response.read(min(65536, limit + 1 - received))
            if not chunk:
                break
            chunks.append(chunk)
            received += len(chunk)
        data = b''.join(chunks)
    if len(data) > limit:
        raise ValueError('Download exceeds limit')
    return data

class FrontendBusy(ValueError):
    pass

class Updater:
    # root/runner injection is only a Python test API, never a CLI option/environment variable.
    def __init__(self, root=Path('/'), runner=None):
        self.root = Path(root)
        self.runner = runner or self.run
        self.state_dir = self.path(STATE)
        self.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.state_dir, 0o700)

    def path(self, path):
        return self.root / path.lstrip('/')

    @staticmethod
    def run(args):
        return subprocess.run(args, check=True, capture_output=True, timeout=60,
                              env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C'}).stdout

    @contextlib.contextmanager
    def lock(self):
        with open(self.state_dir / 'lock', 'a') as fd:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield

    def load(self):
        p = self.state_dir / 'state.json'
        return decode(read_regular(p, 65536)) if p.exists() else {'accepted': {}, 'active': None, 'pending': None, 'trial': False, 'rollback_requested': False}

    def save(self, state):
        atomic(self.state_dir / 'state.json', json.dumps(state).encode())

    def compatible(self):
        receipt = decode(read_regular(self.path('/etc/eclipseos-update/base.json'), 4096))
        if receipt != {'base': BASE_ID, 'kernel': KERNEL, 'arch': 'x86_64'}:
            raise ValueError('Unsupported base receipt')
        if self.root == Path('/') and (os.uname().release != KERNEL or os.uname().machine != 'x86_64'):
            raise ValueError('Kernel/base differs; use a separately validated OS release')

    def verify(self, raw, signature):
        if len(raw) > 65536 or len(signature) != 64:
            raise ValueError('Invalid signed manifest size')
        key = self.path(KEY)
        if not key.is_file():
            raise ValueError('Updates disabled: trusted public key has not been provisioned')
        with tempfile.TemporaryDirectory(dir=self.state_dir) as td:
            m, s = Path(td) / 'manifest', Path(td) / 'signature'
            m.write_bytes(raw)
            s.write_bytes(signature)
            self.runner(['/usr/bin/openssl', 'pkeyutl', '-verify', '-rawin', '-pubin', '-inkey', str(key), '-in', str(m), '-sigfile', str(s)])
        return manifest_validate(decode(raw))

    def offer(self, channel):
        self.compatible()
        if not self.path(KEY).is_file():
            raise ValueError('Updates disabled: trusted public key has not been provisioned')
        url = 'https://github.com/th3d3ck3r/Moonlight-OS/releases/download/eclipseos-updates-' + channel + '/'
        raw = download(url + 'manifest.json', 65536)
        signature = download(url + 'manifest.sig', 64)
        manifest = self.verify(raw, signature)
        if manifest['channel'] != channel:
            raise ValueError('Feed channel mismatch')
        return raw, signature, manifest

    def baseline(self):
        self.compatible()
        return {'base': BASE_ID, 'kernel': KERNEL, 'files': {name: digest(read_regular(self.path(path), MAX_EXPANDED)) for name, (path, _, _) in TARGETS.items() if path}}

    def stage(self, raw, signature, bundle):
        self.compatible()
        m = self.verify(raw, signature)
        state = self.load()
        if state['trial'] or state['pending'] or (self.state_dir / 'journal.json').exists():
            raise ValueError('Confirm, roll back or cancel the pending update first')
        if m['sequence'] <= state['accepted'].get(m['channel'], 0):
            raise ValueError('Old or already accepted update sequence')
        if len(bundle) != m['archive']['size'] or digest(bundle) != m['archive']['sha256']:
            raise ValueError('Archive checksum/size mismatch')
        if shutil.disk_usage(self.state_dir).free < 2 * MAX_EXPANDED:
            raise ValueError('Need at least 768 MiB free for staging and recovery')
        destination = self.state_dir / 'packages' / m['id']
        if destination.exists():
            raise ValueError('Update ID already staged; use a new unique ID')
        destination.parent.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent) as td:
            folder = Path(td)
            wanted = {i['target']: i for i in m['files']}
            found = set()
            with gzip.GzipFile(fileobj=io.BytesIO(bundle)) as compressed:
                expanded = compressed.read(MAX_EXPANDED + 1024 * 1024 + 1)
            if len(expanded) > MAX_EXPANDED + 1024 * 1024:
                raise ValueError('Archive expansion exceeds limit')
            with tarfile.open(fileobj=io.BytesIO(expanded), mode='r:') as archive:
                for member in archive:
                    if member.name not in wanted or member.name in found or not member.isfile() or member.sparse or member.pax_headers or member.size != wanted[member.name]['size']:
                        raise ValueError('Archive has extra, duplicate, linked or malformed entries')
                    # No extract()/extractall(): archive paths, ownership and permissions are never trusted.
                    data = archive.extractfile(member).read(member.size + 1)
                    if len(data) != member.size or digest(data) != wanted[member.name]['sha256']:
                        raise ValueError('Payload checksum mismatch')
                    atomic(folder / member.name, data)
                    found.add(member.name)
            if found != set(wanted):
                raise ValueError('Missing payload')
            atomic(folder / 'manifest.json', raw)
            atomic(folder / 'manifest.sig', signature)
            os.rename(folder, destination)
            sync_dir(destination.parent)
            # TemporaryDirectory tolerates the renamed directory at cleanup.
        state['pending'] = m['id']
        self.save(state)
        return {'message': 'Verified and staged. End the frontend, then relaunch. Wi-Fi/Bluetooth configuration changes can interrupt connectivity.', 'id': m['id'], 'notes': m['notes']}

    def idle(self):
        if self.root != Path('/'):
            return
        names = {'vibemis', 'moonlight', 'cocoos', 'artemis', 'pegasus-fe', 'Moonlight', 'CocoOS', 'Artemis', 'Eclipse'}
        for proc in Path('/proc').glob('[0-9]*/exe'):
            try:
                executable = os.readlink(proc).removesuffix(' (deleted)')
                if Path(executable).name in names or executable.startswith(('/usr/local/libexec/moonlight-os/', '/usr/local/libexec/eclipseos/releases/')):
                    raise FrontendBusy('Close all frontends/streams before applying or rolling back')
            except (FileNotFoundError, ProcessLookupError):
                pass

    def validate_payload(self, name, data, staged):
        if name in ('system-controls', 'control-center', 'bluetooth-menu', 'streaming-tune'):
            compile(data, name, 'exec')
        elif name == 'wifi-menu':
            self.runner(['/usr/bin/bash', '-n', str(staged)])
        elif name.endswith('-config'):
            import configparser
            parser = configparser.ConfigParser(interpolation=None, strict=True)
            parser.read_string(data.decode())
            allowed = {'wifi-config': {'connection': {'wifi.powersave'}}, 'bluetooth-config': {'General': {'AutoEnable'}}}[name]
            # Vendor BlueZ baseline can contain comments; update payload is deliberately narrow.
            if set(parser.sections()) != set(allowed) or parser.defaults():
                raise ValueError('Configuration sections outside permitted scope')
            for section in allowed:
                if set(parser[section]) != {k.lower() for k in allowed[section]}:
                    raise ValueError('Configuration options outside permitted scope')
            if name == 'wifi-config' and parser['connection']['wifi.powersave'] not in ('2', '3'):
                raise ValueError('Invalid Wi-Fi powersave setting')
            if name == 'bluetooth-config' and parser['General']['AutoEnable'].lower() not in ('true', 'false'):
                raise ValueError('Invalid Bluetooth setting')
        elif name == 'frontend':
            if len(data) < 20 or data[:6] != b'\x7fELF\x02\x01' or data[18:20] != b'\x3e\x00':
                raise ValueError('Frontend must be a native x86_64 ELF executable')
            if self.root == Path('/'):
                os.chmod(staged, 0o755)
                output = self.runner(['/usr/bin/ldd', str(staged)])
                if b'not found' in output:
                    raise ValueError('Missing frontend dependency; full base update required')

    def switch(self, update_id):
        link = self.path('/usr/local/libexec/eclipseos/current')
        link.parent.mkdir(parents=True, exist_ok=True)
        if update_id is None:
            link.unlink(missing_ok=True)
        else:
            temporary = link.with_name('.current-next')
            temporary.unlink(missing_ok=True)
            temporary.symlink_to('releases/' + update_id)
            os.replace(temporary, link)
        sync_dir(link.parent)

    def restart(self, services, boot=False):
        if boot:
            return
        for service in services:
            self.runner(['/usr/bin/systemctl', 'restart', service])

    def rollback(self, boot=False):
        journal_path = self.state_dir / 'journal.json'
        if not journal_path.exists():
            return
        journal = decode(read_regular(journal_path, 65536))
        state = self.load()
        if state.get('confirmed') == journal['id'] and not journal.get('force'):
            journal_path.unlink()
            sync_dir(self.state_dir)
            return
        for item in journal['backups']:
            name = item['target']
            path, _, _ = TARGETS[name]
            data = read_regular(self.state_dir / 'backup' / name, MAX_EXPANDED)
            if digest(data) != item['sha256']:
                raise ValueError('Recovery backup checksum mismatch; use tty2/manual recovery')
            atomic(self.path(path), data, item['mode'])
        self.switch(journal['previous'])
        self.restart(journal['services'], boot)
        state.pop('confirmed', None)
        state.update(active=journal['previous'], trial=False, rollback_requested=False, pending=None)
        self.save(state)
        journal_path.unlink()
        sync_dir(self.state_dir)

    def preflight(self):
        try:
            return self.apply()
        except FrontendBusy:
            return {'message': 'Update deferred: an existing frontend is running. Close all clients to activate/recover on the next launch.'}

    def apply(self):
        state = self.load()
        if not (state['trial'] or state['rollback_requested'] or state['pending'] or (self.state_dir / 'journal.json').exists()):
            return {'message': 'No pending update.'}
        self.idle()
        if state['trial'] or state['rollback_requested'] or (self.state_dir / 'journal.json').exists():
            self.rollback()
            return {'message': 'Previous update restored. Recovery did not need networking.'}
        if not state['pending']:
            return {'message': 'No pending update.'}
        self.compatible()
        folder = self.state_dir / 'packages' / state['pending']
        m = self.verify(read_regular(folder / 'manifest.json', 65536), read_regular(folder / 'manifest.sig', 64))
        if m['id'] != state['pending'] or m['sequence'] <= state['accepted'].get(m['channel'], 0):
            raise ValueError('Pending update identity/sequence mismatch')
        backup = self.state_dir / 'backup'
        backups, services, payloads, originals = [], [], {}, {}
        for item in m['files']:
            name = item['target']
            path, mode, service = TARGETS[name]
            data = read_regular(folder / name, MAX_EXPANDED)
            if len(data) != item['size'] or digest(data) != item['sha256']:
                raise ValueError('Staged payload changed')
            self.validate_payload(name, data, folder / name)
            payloads[name] = data
            if path:
                target = self.path(path)
                previous = read_regular(target, MAX_EXPANDED)
                if digest(previous) != item['before_sha256']:
                    raise ValueError('Local configuration/helper differs from package baseline: ' + name)
                originals[name] = previous
                backups.append({'target': name, 'sha256': digest(previous), 'mode': target.stat().st_mode & 0o777})
                if service and service not in services:
                    try:
                        self.runner(['/usr/bin/systemctl', 'is-active', '--quiet', service])
                        services.append(service)
                    except subprocess.CalledProcessError:
                        pass
        required = sum(map(len, originals.values())) + len(payloads.get('frontend', b'')) + 16 * 1024 * 1024
        if shutil.disk_usage(self.state_dir).free < required:
            raise ValueError('Insufficient space for recovery snapshot')
        (self.state_dir / 'confirmed-journal.json').unlink(missing_ok=True)
        if backup.exists():
            shutil.rmtree(backup)
        backup.mkdir(mode=0o700)
        for name, previous in originals.items():
            atomic(backup / name, previous)
        if 'frontend' in payloads:
            releases = self.path(RELEASES)
            releases.mkdir(parents=True, exist_ok=True, mode=0o755)
            os.chmod(releases, 0o755)
            slot = releases / m['id']
            slot.mkdir(parents=True, exist_ok=True, mode=0o755)
            os.chmod(slot, 0o755)
            atomic(slot / 'vibemis', payloads['frontend'], 0o755)
            sync_dir(slot.parent)
        journal = {'id': m['id'], 'previous': state['active'], 'backups': backups, 'services': services}
        atomic(self.state_dir / 'journal.json', json.dumps(journal).encode())
        try:
            for name, data in payloads.items():
                path, mode, _ = TARGETS[name]
                if path:
                    atomic(self.path(path), data, mode)
            if 'frontend' in payloads:
                self.switch(m['id'])
            self.restart(services)
            state.update(active=m['id'] if 'frontend' in payloads else state['active'], pending=None, trial=True, trial_id=m['id'])
            self.save(state)
        except Exception:
            self.rollback()
            raise
        return {'message': 'Trial active. Test the frontend, Wi-Fi and Bluetooth, then confirm from tty2. Next launch/boot rolls back an unconfirmed trial.', 'id': m['id']}

    def confirm(self):
        state = self.load()
        if not state['trial'] or state['rollback_requested']:
            raise ValueError('No confirmable trial')
        folder = self.state_dir / 'packages' / state['trial_id']
        m = self.verify(read_regular(folder / 'manifest.json', 65536), read_regular(folder / 'manifest.sig', 64))
        atomic(self.state_dir / 'confirmed-journal.json', read_regular(self.state_dir / 'journal.json', 65536))
        state['accepted'][m['channel']] = m['sequence']
        state.update(trial=False, confirmed=m['id'])
        self.save(state)  # Durable confirmation precedes journal removal.
        (self.state_dir / 'journal.json').unlink()
        sync_dir(self.state_dir)
        return {'message': 'Update confirmed. Explicit rollback remains available until the next update.'}

    def explicit_rollback(self):
        self.idle()
        state = self.load()
        if not (self.state_dir / 'journal.json').exists():
            recovery = self.state_dir / 'confirmed-journal.json'
            if not state.get('confirmed') or not recovery.exists():
                raise ValueError('No rollback snapshot available')
            journal = decode(read_regular(recovery, 65536))
            journal['force'] = True
            atomic(self.state_dir / 'journal.json', json.dumps(journal).encode())
            state.pop('confirmed', None)
            self.save(state)
        self.rollback()
        return {'message': 'Update rolled back'}

    def status(self):
        state = self.load()
        return dict(state, provisioned=self.path(KEY).is_file(), base=BASE_ID, kernel=KERNEL,
                    message='Stage only while using Eclipse; apply/rollback after closing all frontends. Confirm each trial from tty2.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['status', 'baseline', 'check', 'stage', 'stage-offline', 'apply', 'launch-preflight', 'recover-boot', 'confirm', 'rollback', 'cancel'])
    parser.add_argument('argument', nargs='?')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run through sudo; installed updater and state must be root-owned')
    updater = Updater()
    with updater.lock():
        if args.command in ('status', 'baseline'):
            result = updater.status() if args.command == 'status' else updater.baseline()
        elif args.command in ('check', 'stage'):
            if args.argument not in ('stable', 'testing'):
                raise ValueError('Choose stable or testing')
            raw, sig, m = updater.offer(args.argument)
            result = {'id': m['id'], 'notes': m['notes'], 'channel': m['channel']}
            if args.command == 'stage':
                result = updater.stage(raw, sig, download(m['archive']['url'], m['archive']['size']))
        elif args.command == 'stage-offline':
            if not args.argument or not Path(args.argument).is_absolute():
                raise ValueError('Use an absolute package-directory path')
            directory = Path(args.argument)
            result = updater.stage(read_regular(directory / 'manifest.json', 65536), read_regular(directory / 'manifest.sig', 64), read_regular(directory / 'payload.tar.gz', MAX_ARCHIVE))
        elif args.command == 'launch-preflight':
            result = updater.preflight()
        elif args.command == 'apply':
            result = updater.apply()
        elif args.command == 'recover-boot':
            updater.idle()
            updater.rollback(boot=True)
            result = {'message': 'Boot recovery complete'}
        elif args.command == 'confirm':
            result = updater.confirm()
        elif args.command == 'rollback':
            result = updater.explicit_rollback()
        else:
            state = updater.load()
            state['pending'] = None
            updater.save(state)
            result = {'message': 'Pending update cancelled'}
        print(json.dumps(result))

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'error': str(error)[:512]}))
        sys.exit(1)
ECLIPSE_UPDATER
cat > /usr/local/bin/eclipseos-streaming <<'STREAMING_TUNE'
#!/usr/bin/python3
"""Reversible Eclipse presets and bounded, read-only Mac streaming diagnostics."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

PROFILES = {
    'balanced': {'width':'1920','height':'1080','fps':'60','bitrate':'20000','videocfg':'2','videodec':'1','yuv444':'false','hdr':'false','enablevrr':'false','framepacing':'false','vsync':'true','showperfoverlay':'false'},
    'latency': {'width':'1920','height':'1080','fps':'60','bitrate':'20000','videocfg':'2','videodec':'1','yuv444':'false','hdr':'false','enablevrr':'false','framepacing':'false','vsync':'false','showperfoverlay':'false'},
    'vulkan-test': {'rendererbackend':'1'},
    'opengl-test': {'rendererbackend':'2'},
    'auto-renderer': {'rendererbackend':'0'},
}

def atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd,tmp=tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as out:
            os.fchmod(out.fileno(),0o600);out.write(data);out.flush();os.fsync(out.fileno())
        os.replace(tmp,path)
        fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def read(path):
    try:return Path(path).read_text(errors='replace')[:32768].strip()
    except OSError:return None

def settings_parse(text):
    general=False;result={}
    for line in text.splitlines():
        if line.strip().startswith('['):general=line.strip()=='[General]'
        elif general and '=' in line and not line.lstrip().startswith(('#',';')):
            key,value=line.split('=',1);key=key.strip()
            if key in result:raise ValueError('Duplicate General setting; use Eclipse settings to resolve it')
            result[key]=value.strip()
    return result

def settings_edit(text, changes):
    lines=text.splitlines(keepends=True);output=[];general=False;seen=set();has_general=False
    def finish():
        for key,value in changes.items():
            if key not in seen and value is not None:
                if output and not output[-1].endswith('\n'):output[-1]+='\n'
                output.append(key+'='+value+'\n');seen.add(key)
    for line in lines:
        if line.strip().startswith('['):
            if general:finish()
            general=line.strip()=='[General]';has_general |= general
        if general and '=' in line and not line.lstrip().startswith(('#',';')):
            key=line.split('=',1)[0].strip()
            if key in changes:
                seen.add(key)
                if changes[key] is not None:output.append(key+'='+changes[key]+'\n')
                continue
        output.append(line)
    if general:finish()
    if not has_general:
        prefix=['[General]\n']+[k+'='+v+'\n' for k,v in changes.items() if v is not None]
        output=prefix+output
    return ''.join(output)

def idle():
    for directory in Path('/proc').glob('[0-9]*'):
        try:
            if directory.stat().st_uid!=os.getuid():continue
            executable=os.readlink(directory/'exe').removesuffix(' (deleted)')
            if Path(executable).name.lower() in ('vibemis','eclipse'):
                raise ValueError('Close Eclipse before changing its saved settings. Diagnostics can run while streaming.')
        except (FileNotFoundError,ProcessLookupError):pass

def tune(config, state_dir, mode):
    idle()
    if config.is_symlink():raise ValueError('Refusing a symlinked settings file')
    text=config.read_text() if config.exists() else ''
    if len(text)>1024*1024:raise ValueError('Settings file too large')
    current=settings_parse(text)
    receipt_path=state_dir/'preset.json'
    receipt=json.loads(receipt_path.read_text()) if receipt_path.exists() else {'before':{},'applied':{}}
    if receipt.get('pending'):
        pending=receipt['pending']
        matches=lambda values:all(current.get(key)==value for key,value in values.items())
        if matches(pending['new']):
            if pending['restore']:
                receipt_path.unlink()
                return {'message':'Interrupted restore completed.'}
            receipt['applied'].update(pending['new'])
        elif not matches(pending['old']):
            raise ValueError('Settings differ from both sides of an interrupted preset. Resolve them in Eclipse.')
        receipt.pop('pending')
        atomic(receipt_path,json.dumps(receipt).encode())
    # Protect changes made in Eclipse since this tool last wrote the owned keys.
    for key,value in receipt['applied'].items():
        if current.get(key)!=value:raise ValueError('Settings changed since tuning: '+key+'. Resolve in Eclipse rather than overwrite them.')
    if mode=='restore':
        if not receipt['applied']:raise ValueError('No preset snapshot to restore')
        receipt['pending']={'old':{k:current.get(k) for k in receipt['before']},'new':receipt['before'],'restore':True}
        atomic(receipt_path,json.dumps(receipt).encode())
        atomic(config,settings_edit(text,receipt['before']).encode())
        receipt_path.unlink()
        return {'message':'Previous streaming settings restored; unrelated settings preserved.'}
    changes=PROFILES[mode]
    for key in changes:
        if key not in receipt['before']:receipt['before'][key]=current.get(key)
    receipt['pending']={'old':{k:current.get(k) for k in changes},'new':changes,'restore':False}
    # Keep a recoverable snapshot before updating QSettings. No full-file replacement on restore.
    atomic(receipt_path,json.dumps(receipt).encode())
    atomic(config,settings_edit(text,changes).encode())
    receipt['applied'].update(changes);receipt.pop('pending')
    atomic(receipt_path,json.dumps(receipt).encode())
    return {'message':'Preset saved for next launch. Test on the Mac; this is not a measured performance result.','profile':mode,'values':changes}

def number(path):
    try:return int(read(path))
    except (TypeError,ValueError):return None

def snapshot(root=Path('/')):
    result={'cpus':{},'temperatures_c':{},'thermal_throttle_counts':{},'gpu':{},'power':{},'cpu_ticks':None,'core_ticks':{}}
    for path in sorted((root/'sys/devices/system/cpu').glob('cpu[0-9]*')):
        frequency={key:read(path/'cpufreq'/key) for key in ('scaling_driver','scaling_governor','scaling_cur_freq','scaling_min_freq','scaling_max_freq','energy_performance_preference')}
        if any(v is not None for v in frequency.values()):result['cpus'][path.name]=frequency
        for key in ('core_throttle_count','package_throttle_count'):
            value=number(path/'thermal_throttle'/key)
            if value is not None:result['thermal_throttle_counts'][path.name+'/'+key]=value
    for hw in (root/'sys/class/hwmon').glob('hwmon*'):
        name=read(hw/'name') or hw.name
        for sensor in hw.glob('temp*_input'):
            value=number(sensor)
            if value is not None and 0<=value<=150000:result['temperatures_c'][name+'/'+sensor.name]=value/1000
    for card in (root/'sys/class/drm').glob('card[0-9]*'):
        if '-' in card.name:continue
        values={key:read(card/key) for key in ('gt_cur_freq_mhz','gt_act_freq_mhz','gt_min_freq_mhz','gt_max_freq_mhz')}
        values.update({key:read(card/'device'/key) for key in ('vendor','device','gpu_busy_percent')})
        for gt in (card/'gt').glob('gt*'):
            for key in ('rps_act_freq_mhz','rps_cur_freq_mhz','rps_min_freq_mhz','rps_max_freq_mhz'):
                values[gt.name+'/'+key]=read(gt/key)
        result['gpu'][card.name]=values
    for device in (root/'sys/class/power_supply').glob('*'):
        result['power'][device.name]={key:read(device/key) for key in ('type','online','status','capacity','power_now')}
    text=read(root/'proc/stat')
    if text:
        fields=text.splitlines()[0].split()
        if len(fields)>=9 and fields[0]=='cpu':
            ticks=[int(x) for x in fields[1:9]]
            result['cpu_ticks']={'total':sum(ticks),'idle':ticks[3]+ticks[4]}
    if text:
        for line in text.splitlines():
            p=line.split()
            if len(p)>=9 and re.fullmatch(r'cpu[0-9]+',p[0]):
                ticks=[int(x) for x in p[1:9]]
                result['core_ticks'][p[0]]={'total':sum(ticks),'idle':ticks[3]+ticks[4]}
    memory=read(root/'proc/meminfo') or ''
    result['memory_kib']={line.split(':',1)[0]:int(line.split()[1]) for line in memory.splitlines() if line.split(':',1)[0] in ('MemAvailable','SwapTotal','SwapFree','Dirty','Writeback')}
    result['loadavg']=read(root/'proc/loadavg')
    return result

def command(args):
    try:
        env=dict(os.environ,LC_ALL='C',LANG='C',DISPLAY=os.environ.get('DISPLAY',':0'))
        if Path('/usr/lib64/dri-nonfree/iHD_drv_video.so').is_file():env['LIBVA_DRIVERS_PATH']='/usr/lib64/dri-nonfree'
        completed=subprocess.run(args,env=env,text=True,capture_output=True,timeout=8)
        return completed.returncode,(completed.stdout+completed.stderr)[:65536]
    except (OSError,subprocess.SubprocessError):return None,'Unavailable'

def assess(samples):
    findings=[]
    if not samples:return ['No samples; hardware/power status unknown.']
    first,last=samples[0],samples[-1]
    deltas={key:last['thermal_throttle_counts'][key]-value for key,value in first['thermal_throttle_counts'].items() if key in last['thermal_throttle_counts'] and last['thermal_throttle_counts'][key]>=value}
    if any(value>0 for value in deltas.values()):findings.append('CPU thermal throttle counters increased during capture.')
    if not deltas:findings.append('Thermal throttle counters unavailable; throttling has not been ruled out.')
    hottest=max((v for sample in samples for v in sample['temperatures_c'].values()),default=None)
    if hottest is not None and hottest>=90:findings.append('At least one sensor reached 90 C; inspect temperature/frequency trends, not temperature alone.')
    if any(p.get('type')=='Battery' and p.get('status')=='Discharging' for s in samples for p in s['power'].values()):findings.append('Battery discharging observed; compare the same stream on a working charger.')
    if not any(p.get('online')=='1' for s in samples for p in s['power'].values()):findings.append('No online external power source reported; charging/input power is unconfirmed.')
    if not findings:findings.append('No throttle-counter increase or hot-sensor warning observed in this interval. This does not certify hardware health or exclude transient power/driver limits.')
    return findings

def diagnose(seconds, root=Path('/'), sleeper=time.sleep, sampler=snapshot):
    samples=[]
    for index in range(seconds//2+1):
        sample=sampler(root);sample['elapsed_seconds']=index*2
        if samples and sample['cpu_ticks'] and samples[-1]['cpu_ticks']:
            old,new=samples[-1]['cpu_ticks'],sample['cpu_ticks'];delta=new['total']-old['total']
            if delta>0:sample['cpu_percent']=round(100*(1-(new['idle']-old['idle'])/delta),2)
        if samples:
            sample['core_cpu_percent']={}
            for core,new in sample.get('core_ticks',{}).items():
                old=samples[-1].get('core_ticks',{}).get(core)
                if old and new['total']>old['total']:
                    sample['core_cpu_percent'][core]=round(100*(1-(new['idle']-old['idle'])/(new['total']-old['total'])),2)
        samples.append(sample)
        if index<seconds//2:sleeper(2)
    report={'schema':1,'kernel':os.uname().release,'architecture':os.uname().machine,'seconds':seconds,'samples':samples,'findings':assess(samples)}
    code,display=command(['xrandr','--current'])
    report['active_display_modes']=[line.strip() for line in display.splitlines() if '*' in line and re.search(r'\d+\.\d+\*',line)] if code==0 else 'Unavailable'
    code,gl=command(['glxinfo','-B'])
    report['graphics']={key:line.split(':',1)[1].strip() for key in ('OpenGL vendor string','OpenGL renderer string','OpenGL version string') for line in gl.splitlines() if line.startswith(key+':')} if code==0 else {'status':'Unavailable'}
    if re.search(r'llvmpipe|softpipe',gl,re.I):report['findings'].append('Software OpenGL renderer detected; hardware rendering is not established.')
    render_nodes=sorted((root/'dev/dri').glob('renderD*'))
    if render_nodes:
        code,va=command(['vainfo','--display','drm','--device',str(render_nodes[0])])
        report['video_capabilities']=[line.strip() for line in va.splitlines() if ('Driver version' in line or 'VAProfile' in line)] if code==0 else 'Unavailable'
    else:report['video_capabilities']='No accessible render node'
    code,wifi=command(['nmcli','-t','-f','IN-USE,FREQ,CHAN,SIGNAL,SECURITY','device','wifi','list','--rescan','no'])
    report['active_wifi_radio']=[line for line in wifi.splitlines() if line.startswith('*:')][:8] if code==0 else 'Unavailable'
    report['services']={service:command(['systemctl','is-active',service])[1].strip()[:64] for service in ('thermald.service','power-profiles-daemon.service','tuned.service')}
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=[*PROFILES,'restore','status','diagnose','menu'])
    parser.add_argument('--seconds',type=int,default=30,help='Even number from 2 to 120; sample while a stream is running')
    args=parser.parse_args()
    if os.geteuid()==0:parser.error('Run as moonlight, without sudo; presets belong to that user')
    if args.mode=='menu':
        choices={'1':'status','2':'balanced','3':'latency','4':'opengl-test','5':'vulkan-test','6':'auto-renderer','7':'restore','8':'diagnose'}
        print('Eclipse streaming tuning\nPresets save 1080p60 HEVC hardware decode at 20 Mbps; previous settings can be restored.\nLowest latency may tear. Renderer tests change only the renderer preference.\nClose Eclipse before changing saved settings; diagnostics run during a stream.\n1) Status  2) Balanced  3) Lowest latency  4) OpenGL test\n5) Vulkan test  6) Auto renderer  7) Restore  8) 30-second diagnostic  0) Exit')
        choice=input('Choose: ').strip()
        if choice not in choices:return
        args.mode=choices[choice]
    config=Path.home()/'.config/Vibemis Project/Vibemis.conf'
    folder=Path.home()/'.local/state/eclipseos/streaming'
    folder.mkdir(parents=True,exist_ok=True,mode=0o700)
    with open(folder/'lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if args.mode=='diagnose':
            if not 2<=args.seconds<=120 or args.seconds%2:parser.error('--seconds must be even and between 2 and 120')
            result=diagnose(args.seconds)
            target=folder/'diagnostics.json';atomic(target,json.dumps(result,indent=2).encode())
            result={'report':str(target),'findings':result['findings']}
        elif args.mode=='status':
            saved=settings_parse(config.read_text()) if config.exists() else {}
            keys=set().union(*(p.keys() for p in PROFILES.values()))
            result={'settings':{key:saved.get(key,'default') for key in sorted(keys)},'restore_available':(folder/'preset.json').exists()}
        else:result=tune(config,folder,args.mode)
        print(json.dumps(result))

if __name__=='__main__':
    try:main()
    except (KeyboardInterrupt, EOFError):
        print('Cancelled.');raise SystemExit(130)
    except Exception as error:
        print(json.dumps({'error':str(error)[:512]}));raise SystemExit(1)
STREAMING_TUNE
chmod 0755 /usr/local/bin/eclipseos-streaming
cat > /usr/local/bin/eclipseos-updates <<'ECLIPSE_UPDATE_MENU'
#!/usr/bin/env bash
set -u
HELPER=/usr/local/libexec/moonlight-os/eclipseos-update.py
if [[ ! -x $HELPER ]]; then
  echo 'Updater is not enrolled on this image. See docs/UPDATES.md for one-time bootstrap.'
  exit 1
fi
while true; do
  printf '\nEclipseOS updates (current kernel/base locked)\n'
  sudo -n "$HELPER" status
  printf '\n1) Check stable  2) Check testing  3) Stage stable  4) Stage testing\n5) Stage from USB/folder  6) Apply (close frontend first)\n7) Confirm tested trial  8) Roll back (close frontend first)\n9) Cancel pending update  0) Exit\nChoose: '
  read -r choice || exit 0
  case "$choice" in
    1) sudo -n "$HELPER" check stable ;;
    2) sudo -n "$HELPER" check testing ;;
    3) sudo -n "$HELPER" stage stable ;;
    4) sudo -n "$HELPER" stage testing ;;
    5) read -r -p 'Absolute package folder: ' folder; sudo -n "$HELPER" stage-offline "$folder" ;;
    6) sudo -n "$HELPER" apply ;;
    7) read -r -p 'Have frontend, Wi-Fi and Bluetooth passed your checks? Type KEEP: ' answer
       [[ $answer == KEEP ]] && sudo -n "$HELPER" confirm ;;
    8) sudo -n "$HELPER" rollback ;;
    9) sudo -n "$HELPER" cancel ;;
    0) exit 0 ;;
  esac
  read -r -p 'Press Enter...' _ || exit 0
done
ECLIPSE_UPDATE_MENU
cat > /etc/eclipseos-update/base.json <<'ECLIPSE_UPDATE_BASE'
{"base":"eclipseos-f44-mbp14-1-v1","kernel":"6.19.10-300.fc44.x86_64","arch":"x86_64"}
ECLIPSE_UPDATE_BASE
cat > /etc/systemd/system/eclipseos-update-recovery.service <<'ECLIPSE_UPDATE_RECOVERY'
[Unit]
Description=Recover an unconfirmed EclipseOS update offline
After=local-fs.target
Before=NetworkManager.service bluetooth.service getty@tty1.service

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/moonlight-os/eclipseos-update.py recover-boot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
ECLIPSE_UPDATE_RECOVERY
chmod 0755 /usr/local/libexec/moonlight-os/eclipseos-update.py /usr/local/bin/eclipseos-updates
systemctl enable eclipseos-update-recovery.service

cat > /usr/local/bin/moonlight-launch <<'FRONTENDS_LAUNCH'
#!/usr/bin/env bash
set -euo pipefail
# Keep each client's bundled Qt/SDL libraries confined to its own child process.
unset LD_LIBRARY_PATH QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH
export QT_QPA_PLATFORM=xcb
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
BASE=${MOONLIGHT_FRONTEND_BASE:-/usr/local/libexec/moonlight-os}
case "${1:-}" in
  moonlight|cocoos|artemis|vibemis|pegasus) ;;
  *) echo 'usage: moonlight-launch {moonlight|cocoos|vibemis|artemis|pegasus}' >&2; exit 2 ;;
esac
# Fixture/frontends overrides intentionally bypass the installed root updater.
UPDATER=/usr/local/libexec/moonlight-os/eclipseos-update.py
if [[ -z ${MOONLIGHT_FRONTEND_BASE+x} && -x $UPDATER ]]; then
  if ! sudo -n "$UPDATER" launch-preflight >&2; then
    echo 'Update preflight failed. Use tty2 -> EclipseOS updates for recovery.' >&2
    exit 1
  fi
fi
case "${1:-}" in
  moonlight|cocoos) exec "$BASE/$1" "${@:2}" ;;
  artemis) exec "$BASE/frontends/artemis" "${@:2}" ;;
  vibemis)
    # Retain the tested full iHD driver on this Intel target.
    if [[ -f /usr/lib64/dri-nonfree/iHD_drv_video.so ]]; then
      export LIBVA_DRIVERS_PATH=/usr/lib64/dri-nonfree
    fi
    CURRENT=/usr/local/libexec/eclipseos/current/vibemis
    if [[ -z ${MOONLIGHT_FRONTEND_BASE+x} && -x $UPDATER && -x $CURRENT ]]; then
      # A failed trial exits before recovery; no live frontend files are replaced.
      if "$CURRENT" "${@:2}"; then
        exit 0
      else
        failure=$?
        sudo -n "$UPDATER" recover-boot >&2 || exit "$failure"
        echo 'Updated Eclipse exited with an error; starting the preserved baseline.' >&2
      fi
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
