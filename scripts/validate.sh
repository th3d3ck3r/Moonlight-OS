#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KS="$ROOT/config/moonlight-os.ks"
LOCK="$ROOT/SOURCES.lock"
BUILD="$ROOT/scripts/build-image.sh"
README="$ROOT/README.md"
TEST_PLAN="$ROOT/docs/TEST_PLAN.md"
WORKFLOW="$ROOT/.github/workflows/build-image.yml"

for file in "$ROOT"/scripts/*.sh; do
  bash -n "$file"
done

post_tmp=$(mktemp)
trap 'rm -f "$post_tmp"' EXIT
awk '
  /^%post([[:space:]]|$)/ { in_post=1; next }
  in_post && /^%end$/ { exit }
  in_post { print }
' "$KS" > "$post_tmp"
[[ -s "$post_tmp" ]]
bash -n "$post_tmp"

# Build automation stays manual during v0.1 audit/testing.
grep -q '^  workflow_dispatch:$' "$WORKFLOW"
! grep -q '^  push:$' "$WORKFLOW"

# Source pins
grep -q '^FEDORA_RELEASE=44$' "$LOCK"
grep -q '^COCOOS_COMMIT=[0-9a-f]\{40\}$' "$LOCK"
grep -q '^MOONLIGHT_COMMIT=[0-9a-f]\{40\}$' "$LOCK"
grep -q '^AUDIO_COMMIT=[0-9a-f]\{40\}$' "$LOCK"
grep -q '^FEDORA_ISO_SHA256=[0-9a-f]\{64\}$' "$LOCK"

# Kickstart structure
[[ "$(grep -c '^%packages' "$KS")" -eq 1 ]]
[[ "$(grep -c '^%post' "$KS")" -eq 1 ]]
[[ "$(grep -c '^%end$' "$KS")" -eq 2 ]]
[[ "$(tail -n 1 "$KS")" == "%end" ]]
! grep -n '^%end$' "$KS" | tail -n +3 | grep -q .

# Boot and disk layout
grep -q '^part /boot/efi --fstype=efi --size=512$' "$KS"
grep -q '^part /boot --fstype=ext4 --size=768$' "$KS"
grep -q '^part / --fstype=xfs --size=11000 --grow$' "$KS"
grep -q 'rd.driver.pre=i915' "$KS"
grep -q 'mem_sleep_default=s2idle' "$KS"
grep -q 'pcie_port_pm=off' "$KS"
grep -q 'MAX=$((14000 \* 1024 \* 1024))' "$BUILD"
grep -q 'inspect-image.sh' "$BUILD"
grep -q 'test-ovmf.sh' "$BUILD"
grep -q 'console=ttyS0,115200n8' "$KS"
grep -q 'MOONLIGHT_OS_BOOT_OK' "$KS"

# Graphics / decode
for pkg in mesa-dri-drivers mesa-libGL mesa-libEGL mesa-libGL-devel mesa-libEGL-devel mesa-vulkan-drivers libdrm libva libva-utils libva-intel-driver libva-intel-media-driver mesa-demos glx-utils vulkan-tools igt-gpu-tools; do
  grep -qx "$pkg" "$KS"
done
! grep -qx 'intel-media-driver' "$KS"
grep -q 'vainfo --display drm --device /dev/dri/renderD128' "$KS"
grep -Fq "grep -q '/i915
grep -q 'OpenGL renderer string' "$KS"
grep -q 'llvmpipe|softpipe|software rasterizer' "$KS"
grep -q 'xrandr --query' "$KS"

# X11/input
for pkg in xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-xauth xorg-x11-drv-libinput libinput-utils xinput evtest; do
  grep -qx "$pkg" "$KS"
done
grep -q 'modinfo applespi' "$KS"
grep -q '/proc/bus/input/devices' "$KS"
grep -q 'xinput list' "$KS"
grep -q '40-moonlight-macbook-input.conf' "$KS"
grep -q 'ClickMethod" "clickfinger' "$KS"

# Network / Bluetooth
for pkg in NetworkManager NetworkManager-wifi NetworkManager-tui wpa_supplicant iw wireless-regdb bluez bluez-libs; do
  grep -qx "$pkg" "$KS"
done
grep -q 'wifi.powersave=2' "$KS"
grep -q 'options brcmfmac roamoff=1' "$KS"

# DualSense
for pkg in steam-devices joystick-support linuxconsoletools SDL2; do
  grep -qx "$pkg" "$KS"
done
grep -q 'hid_playstation' "$KS"
grep -q -- '--agent NoInputNoOutput --timeout 30 pair' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: playback-only A2DP.
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'monitor.bluez.seat-monitoring = disabled' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"
grep -q 'AirPods AAC codec plugin installed' "$KS"

# Audio
for pkg in pipewire pipewire-pulseaudio wireplumber alsa-utils dkms kernel-devel kernel-headers; do
  grep -qx "$pkg" "$KS"
done
grep -q 'snd_hda_macbookpro' "$KS"
grep -q 'dkms add -m snd_hda_macbookpro -v 1.0' "$KS"
grep -q 'dkms install -m snd_hda_macbookpro -v 1.0' "$KS"

# Power / thermal
for pkg in brightnessctl upower thermald; do
  grep -qx "$pkg" "$KS"
done
grep -q 'thermald.service' "$KS"
grep -q 'battery sysfs accessible' "$KS"
grep -q 'backlight sysfs accessible' "$KS"
grep -q 'modinfo xhci_pci' "$KS"
grep -q 'modinfo thunderbolt' "$KS"
grep -q 'internal NVMe controller visible' "$KS"

# Streaming/client build stack
for pkg in ffmpeg-libs ffmpeg-devel libplacebo libplacebo-devel libX11-devel qt6-qtbase-gui qt6-qtbase-devel qt6-qtdeclarative qt6-qtdeclarative-devel qt6-qtsvg qt6-qtsvg-devel qt6-qtwebsockets qt6-qtwebsockets-devel qt6-qtmultimedia qt6-qtmultimedia-devel; do
  grep -qx "$pkg" "$KS"
done
! grep -qx 'libavcodec-freeworld' "$KS"
grep -q 'CONFIG+=embedded' "$KS"
grep -q 'moonlight-os/cocoos' "$KS"
grep -q 'moonlight-os/moonlight' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$README"

# v0.1 retains debug/build tools.
for pkg in git gcc gcc-c++ make patch dkms kernel-devel kernel-headers; do
  grep -qx "$pkg" "$KS"
done
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

# Documentation must match v0.1 media size.
grep -q '16 GB' "$README"
grep -q '16 GB' "$TEST_PLAN"
! grep -q '8 GB-or-larger' "$README" "$TEST_PLAN"

# Defensive corruption checks.
! grep -Eq "grep -q '.*grep -q|Static validation passed.*\$KS" "$KS" "$ROOT/scripts/validate.sh"
grep -q '^echo "Static validation passed\."$' "$ROOT/scripts/validate.sh"

echo "Static validation passed."
" "$KS"
grep -q 'OpenGL renderer string' "$KS"
grep -q 'llvmpipe|softpipe|software rasterizer' "$KS"
grep -q 'xrandr --query' "$KS"

# X11/input
for pkg in xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-xauth xorg-x11-drv-libinput libinput-utils xinput evtest; do
  grep -qx "$pkg" "$KS"
done
grep -q 'modinfo applespi' "$KS"
grep -q '/proc/bus/input/devices' "$KS"
grep -q 'xinput list' "$KS"
grep -q '40-moonlight-macbook-input.conf' "$KS"
grep -q 'ClickMethod" "clickfinger' "$KS"

# Network / Bluetooth
for pkg in NetworkManager NetworkManager-wifi NetworkManager-tui wpa_supplicant iw wireless-regdb bluez bluez-libs; do
  grep -qx "$pkg" "$KS"
done
grep -q 'wifi.powersave=2' "$KS"
grep -q 'options brcmfmac roamoff=1' "$KS"

# DualSense
for pkg in steam-devices joystick-support linuxconsoletools SDL2; do
  grep -qx "$pkg" "$KS"
done
grep -q 'hid_playstation' "$KS"
grep -q -- '--agent NoInputNoOutput --timeout 30 pair' "$KS"
grep -q '52-disable-dualsense-audio.conf' "$KS"
grep -q 'device.bus = "usb"' "$KS"
grep -q 'device.vendor.id = 1356' "$KS"
grep -q 'device.product.id = 3302' "$KS"
grep -q 'device.disabled = true' "$KS"

# AirPods Pro 2: playback-only A2DP.
grep -q 'override.bluez5.roles = \[ a2dp_sink \]' "$KS"
grep -q 'override.bluez5.codecs = \[ sbc sbc_xq aac \]' "$KS"
grep -q 'bluez5.auto-connect = \[ a2dp_sink \]' "$KS"
grep -q 'monitor.bluez.seat-monitoring = disabled' "$KS"
grep -q 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
grep -q 'bluetooth.profile-preference = "latency"' "$KS"
grep -q 'airpods-mode low-latency' "$KS"
grep -q 'airpods-mode quality' "$KS"

# Audio
for pkg in pipewire pipewire-pulseaudio wireplumber alsa-utils dkms kernel-devel kernel-headers; do
  grep -qx "$pkg" "$KS"
done
grep -q 'snd_hda_macbookpro' "$KS"
grep -q 'dkms add -m snd_hda_macbookpro -v 1.0' "$KS"
grep -q 'dkms install -m snd_hda_macbookpro -v 1.0' "$KS"

# Power / thermal
for pkg in brightnessctl upower thermald; do
  grep -qx "$pkg" "$KS"
done
grep -q 'thermald.service' "$KS"
grep -q 'battery sysfs accessible' "$KS"
grep -q 'backlight sysfs accessible' "$KS"

# Streaming/client build stack
for pkg in ffmpeg-libs ffmpeg-devel libplacebo libplacebo-devel libX11-devel qt6-qtbase-gui qt6-qtbase-devel qt6-qtdeclarative qt6-qtdeclarative-devel qt6-qtsvg qt6-qtsvg-devel qt6-qtwebsockets qt6-qtwebsockets-devel qt6-qtmultimedia qt6-qtmultimedia-devel; do
  grep -qx "$pkg" "$KS"
done
! grep -qx 'libavcodec-freeworld' "$KS"
grep -q 'CONFIG+=embedded' "$KS"
grep -q 'moonlight-os/cocoos' "$KS"
grep -q 'moonlight-os/moonlight' "$KS"

# Appliance UX
grep -q 'moonlight-settings' "$KS"
grep -q 'moonlight-wifi' "$KS"
grep -q 'moonlight-bluetooth' "$KS"
grep -q 'dualsense-pair' "$KS"
grep -q 'airpods-pair' "$KS"
grep -q 'setterm --foreground red --background black' "$KS"
grep -q 'Ctrl+Alt+F2' "$README"

# v0.1 retains debug/build tools.
for pkg in git gcc gcc-c++ make patch dkms kernel-devel kernel-headers; do
  grep -qx "$pkg" "$KS"
done
grep -q 'v0.1 is intentionally a development/debug image' "$KS"

# Documentation must match v0.1 media size.
grep -q '16 GB' "$README"
grep -q '16 GB' "$TEST_PLAN"
! grep -q '8 GB-or-larger' "$README" "$TEST_PLAN"

# Defensive corruption checks.
! grep -Eq "grep -q '.*grep -q|Static validation passed.*\$KS" "$KS" "$ROOT/scripts/validate.sh"
grep -q '^echo "Static validation passed\."$' "$ROOT/scripts/validate.sh"

echo "Static validation passed."
