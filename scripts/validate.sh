#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KS="$ROOT/config/moonlight-os.ks"
LOCK="$ROOT/SOURCES.lock"
BUILD="$ROOT/scripts/build-image.sh"

for file in "$ROOT"/scripts/*.sh; do
  bash -n "$file"
done

# Source pins
grep -q '^COCOOS_COMMIT=[0-9a-f]\{40\}$' "$LOCK"
grep -q '^MOONLIGHT_COMMIT=[0-9a-f]\{40\}$' "$LOCK"
grep -q '^AUDIO_COMMIT=[0-9a-f]\{40\}$' "$LOCK"

# Boot/disk layout
grep -q '^part /boot/efi --fstype=efi --size=512$' "$KS"
grep -q '^part /boot --fstype=ext4 --size=768$' "$KS"
grep -q '^part / --fstype=xfs --size=11000 --grow$' "$KS"
grep -q 'mem_sleep_default=s2idle pcie_port_pm=off' "$KS"
grep -q 'MAX=$((14000 \* 1024 \* 1024))' "$BUILD"

# MacBookPro14,1
grep -q 'MacBookPro14,1' "$KS"
grep -q '^libva-intel-media-driver$' "$KS"
grep -q '^libva-intel-driver$' "$KS"
grep -q '^libva-utils$' "$KS"
! grep -q '^intel-media-driver$' "$KS"
grep -q 'wifi.powersave=2' "$KS"
grep -q 'options brcmfmac roamoff=1' "$KS"
grep -q 'snd_hda_macbookpro' "$KS"

# Consistent FFmpeg stack
grep -q '^ffmpeg-libs$' "$KS"
grep -q '^ffmpeg-devel$' "$KS"
! grep -q '^libavcodec-freeworld$' "$KS"

# Input/GPU/power diagnostics
grep -q '^xorg-x11-drv-libinputgrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q '^libinput-utilsgrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q '^xinputgrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q '^mesa-demosgrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q '^vulkan-toolsgrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q '^igt-gpu-toolsgrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q '^brightnessctlgrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q '^upowergrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q '^thermaldgrep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
 "$KS"
grep -q 'vainfo --display drm --device /dev/dri/renderD128' "$KS"
grep -q 'modinfo applespi' "$KS"
grep -q 'thermald.service' "$KS"

# DualSense
grep -q '^joystick-support$' "$KS"
grep -q '^evtest$' "$KS"
grep -q 'hid_playstation' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: A2DP playback only
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'override.bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$ROOT/README.md"

# v0.1 must retain development/debug capability
grep -q '^git$' "$KS"
grep -q '^gcc$' "$KS"
grep -q '^dkms$' "$KS"
grep -q '^kernel-devel$' "$KS"
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

echo "Static validation passed."
