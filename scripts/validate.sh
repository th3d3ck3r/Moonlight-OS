#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KS="$ROOT/config/moonlight-os.ks"
LOCK="$ROOT/SOURCES.lock"
BUILD="$ROOT/scripts/build-image.sh"
README="$ROOT/README.md"

for file in "$ROOT"/scripts/*.sh; do
  bash -n "$file"
done

# Source pins
grep -q '^COCOOS_COMMIT=[0-9a-f]\{40\}$' "$LOCK"
grep -q '^MOONLIGHT_COMMIT=[0-9a-f]\{40\}$' "$LOCK"
grep -q '^AUDIO_COMMIT=[0-9a-f]\{40\}$' "$LOCK"

# Boot and disk layout
grep -q '^part /boot/efi --fstype=efi --size=512$' "$KS"
grep -q '^part /boot --fstype=ext4 --size=768$' "$KS"
grep -q '^part / --fstype=xfs --size=11000 --grow$' "$KS"
grep -q 'mem_sleep_default=s2idle pcie_port_pm=off' "$KS"
grep -q 'MAX=$((14000 \* 1024 \* 1024))' "$BUILD"

# MacBookPro14,1 graphics / decode
grep -q 'MacBookPro14,1' "$KS"
grep -q '^mesa-dri-drivers$' "$KS"
grep -q '^mesa-libGL$' "$KS"
grep -q '^mesa-libEGL$' "$KS"
grep -q '^mesa-vulkan-drivers$' "$KS"
grep -q '^libdrm$' "$KS"
grep -q '^libva$' "$KS"
grep -q '^libva-utils$' "$KS"
grep -q '^libva-intel-driver$' "$KS"
grep -q '^libva-intel-media-driver$' "$KS"
! grep -q '^intel-media-driver$' "$KS"
grep -q '^mesa-demos$' "$KS"
grep -q '^glx-utils$' "$KS"
grep -q '^vulkan-tools$' "$KS"
grep -q '^igt-gpu-tools$' "$KS"
grep -q 'vainfo --display drm --device /dev/dri/renderD128' "$KS"
grep -q "grep -q '/i915\$'" "$KS"

# X11 keyboard / trackpad / mouse
grep -q '^xorg-x11-server-Xorg$' "$KS"
grep -q '^xorg-x11-xinit$' "$KS"
grep -q '^xorg-x11-drv-libinput$' "$KS"
grep -q '^libinput-utils$' "$KS"
grep -q '^xinput$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'modinfo applespi' "$KS"
grep -q '/proc/bus/input/devices' "$KS"
grep -q 'OpenGL renderer string' "$KS"
grep -q 'xrandr --query' "$KS"
grep -q 'xinput list' "$KS"

# Network
grep -q '^NetworkManager$' "$KS"
grep -q '^NetworkManager-wifi$' "$KS"
grep -q '^wpa_supplicant$' "$KS"
grep -q 'wifi.powersave=2' "$KS"
grep -q 'options brcmfmac roamoff=1' "$KS"

# Bluetooth / controller
grep -q '^bluez$' "$KS"
grep -q '^steam-devices$' "$KS"
grep -q '^joystick-support$' "$KS"
grep -q '^linuxconsoletools$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2 playback-only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Audio
grep -q '^pipewire$' "$KS"
grep -q '^pipewire-pulseaudio$' "$KS"
grep -q '^wireplumber$' "$KS"
grep -q 'snd_hda_macbookpro' "$KS"
grep -q 'dkms add -m snd_hda_macbookpro -v 1.0' "$KS"
grep -q 'dkms install -m snd_hda_macbookpro -v 1.0' "$KS"

# Power / thermal / accessibility
grep -q '^brightnessctl$' "$KS"
grep -q '^upower$' "$KS"
grep -q '^thermald$' "$KS"
grep -q 'thermald.service' "$KS"
grep -q 'battery sysfs accessible' "$KS"
grep -q 'backlight sysfs accessible' "$KS"

# Streaming stack
grep -q '^ffmpeg-libs$' "$KS"
grep -q '^ffmpeg-devel$' "$KS"
! grep -q '^libavcodec-freeworld$' "$KS"
grep -q 'CONFIG+=embedded' "$KS"
grep -q 'moonlight-os/cocoos' "$KS"
grep -q 'moonlight-os/moonlight' "$KS"

# Appliance UI / recovery
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$README"

# v0.1 intentionally retains debug/build tools
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^gcc-c++$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q '^kernel-headers$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

# Kickstart structure: exactly one %packages section and one %post section.
[[ "$(grep -c '^%packages' "$KS")" -eq 1 ]]
[[ "$(grep -c '^%post' "$KS")" -eq 1 ]]
[[ "$(grep -c '^%end! grep -Eq "grep -q '.*grep -q|Static validation passed.*\$KS" "$KS" "$ROOT/scripts/validate.sh"
grep -q '^echo "Static validation passed\."$' "$ROOT/scripts/validate.sh"

echo "Static validation passed."
 "$KS")" -eq 2 ]]

# Guard against accidental text-replacement corruption.
! grep -Eq "grep -q '.*grep -q|Static validation passed.*\$KS" "$KS" "$ROOT/scripts/validate.sh"
grep -q '^echo "Static validation passed\."$' "$ROOT/scripts/validate.sh"

echo "Static validation passed."
