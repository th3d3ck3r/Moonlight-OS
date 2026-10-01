#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KS="$ROOT/config/moonlight-os.ks"
LOCK="$ROOT/SOURCES.lock"
BUILD="$ROOT/scripts/build-image.sh"
README="$ROOT/README.md"
TEST_PLAN="$ROOT/docs/TEST_PLAN.md"
WORKFLOW="$ROOT/.github/workflows/build-image.yml"
AUDIT_WORKFLOW="$ROOT/.github/workflows/audit.yml"

need_text() {
  local text=$1 file=$2
  grep -Fq -- "$text" "$file"
}

need_line() {
  local text=$1 file=$2
  grep -Fqx -- "$text" "$file"
}

need_pkg() {
  need_line "$1" "$KS"
}

for file in "$ROOT"/scripts/*.sh; do
  bash -n "$file"
done

# The embedded %post body must itself be valid Bash.
post_tmp=$(mktemp)
trap 'rm -f "$post_tmp"' EXIT
awk '
  /^%post([[:space:]]|$)/ { in_post=1; next }
  in_post && /^%end$/ { exit }
  in_post { print }
' "$KS" > "$post_tmp"
[[ -s "$post_tmp" ]]
bash -n "$post_tmp"

# Image builds are manual, with an explicit BUILD_ONCE file as a controlled one-shot trigger.
need_line "  workflow_dispatch:" "$WORKFLOW"
need_text ".github/BUILD_ONCE" "$WORKFLOW"
need_line "  workflow_dispatch:" "$AUDIT_WORKFLOW"
need_line "  push:" "$AUDIT_WORKFLOW"

# Source pins.
need_line "FEDORA_RELEASE=44" "$LOCK"
need_line "INSTALLER_KERNEL=6.19.10-300.fc44.x86_64" "$LOCK"
grep -Eq '^COCOOS_COMMIT=[0-9a-f]{40}$' "$LOCK"
grep -Eq '^MOONLIGHT_COMMIT=[0-9a-f]{40}$' "$LOCK"
grep -Eq '^AUDIO_COMMIT=[0-9a-f]{40}$' "$LOCK"
grep -Eq '^FEDORA_ISO_SHA256=[0-9a-f]{64}$' "$LOCK"

# Kickstart structure.
[[ "$(grep -c '^%packages' "$KS")" -eq 1 ]]
[[ "$(grep -c '^%post' "$KS")" -eq 1 ]]
[[ "$(grep -c '^%end$' "$KS")" -eq 2 ]]
[[ "$(tail -n 1 "$KS")" == "%end" ]]

# Disk/boot invariants.
need_line "part /boot/efi --fstype=efi --size=512" "$KS"
need_line "part /boot --fstype=ext4 --size=1024" "$KS"
need_line "part / --fstype=xfs --size=11000 --grow" "$KS"
need_text "rd.driver.pre=i915" "$KS"
need_text "mem_sleep_default=s2idle" "$KS"
need_text "pcie_port_pm=off" "$KS"
need_text "console=ttyS0,115200n8" "$KS"
need_text "MOONLIGHT_OS_BOOT_OK" "$KS"
need_text "Root partition expansion failed; will retry on next boot." "$KS"
need_text "Requires=moonlight-os-grow-root.service" "$KS"
need_text 'MAX=$((14000 * 1024 * 1024))' "$BUILD"
need_text "inspect-image.sh" "$BUILD"
need_text "test-ovmf.sh" "$BUILD"
need_text "--ram=4096" "$BUILD"
need_text "--vcpus=2" "$BUILD"

# Graphics / hardware decode / X11 acceleration.
for pkg in \
  mesa-dri-drivers mesa-libGL mesa-libEGL mesa-libGL-devel mesa-libEGL-devel \
  mesa-vulkan-drivers libdrm libva libva-utils libva-intel-driver \
  libva-intel-media-driver mesa-demos glx-utils vulkan-tools \
  libX11-devel; do
  need_pkg "$pkg"
done
! need_pkg "intel-media-driver"
need_text "vainfo --display drm --device /dev/dri/renderD128" "$KS"
need_text "readlink -f /sys/class/drm/card0/device/driver" "$KS"
need_text "OpenGL renderer string" "$KS"
need_text "llvmpipe|softpipe|software rasterizer" "$KS"
need_text "xrandr --query" "$KS"
need_text "dnf -y --refresh install igt-gpu-tools" "$KS"
need_text "command -v intel_gpu_top" "$KS"

# Keyboard / trackpad / mouse.
for pkg in \
  xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-xauth xorg-x11-drv-libinput \
  libinput-utils xinput evtest; do
  need_pkg "$pkg"
done
need_text "modinfo applespi" "$KS"
need_text "/proc/bus/input/devices" "$KS"
need_text "xinput list" "$KS"
need_text "40-moonlight-macbook-input.conf" "$KS"
need_text 'Option "ClickMethod" "clickfinger"' "$KS"

# Network / Bluetooth.
for pkg in \
  NetworkManager NetworkManager-wifi NetworkManager-tui wpa_supplicant iw \
  wireless-regdb bluez bluez-libs util-linux; do
  need_pkg "$pkg"
done
need_text "wifi.powersave=2" "$KS"
need_text "options brcmfmac roamoff=1" "$KS"

# DualSense.
for pkg in steam-devices joystick-support linuxconsoletools sdl2-compat; do
  need_pkg "$pkg"
done
need_text "hid_playstation" "$KS"
need_text "--agent NoInputNoOutput --timeout 30 pair" "$KS"
need_text "52-disable-dualsense-audio.conf" "$KS"
need_text 'device.bus = "usb"' "$KS"
need_text "device.vendor.id = 1356" "$KS"
need_text "device.product.id = 3302" "$KS"
need_text "device.disabled = true" "$KS"

# AirPods Pro 2: playback-only A2DP.
need_text "override.bluez5.roles = [ a2dp_sink ]" "$KS"
need_text "override.bluez5.codecs = [ sbc sbc_xq aac ]" "$KS"
need_text "bluez5.auto-connect = [ a2dp_sink ]" "$KS"
need_text "monitor.bluez.seat-monitoring = disabled" "$KS"
need_text 'bluetooth.autoswitch-to-headset-profile = false' "$KS"
need_text 'bluetooth.profile-preference = "latency"' "$KS"
need_text "airpods-mode low-latency" "$KS"
need_text "airpods-mode quality" "$KS"
need_text "AirPods AAC codec plugin installed" "$KS"

# Audio.
for pkg in openssl wget1-wget xz; do
  need_pkg "$pkg"
done
for pkg in pipewire pipewire-pulseaudio wireplumber alsa-utils dkms kernel-devel kernel-headers; do
  need_pkg "$pkg"
done
need_text "snd_hda_macbookpro" "$KS"
need_text 'PACKAGE_VERSION="1.0"' "$KS"
need_text 'BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus"' "$KS"
need_text 'PRE_BUILD="install.cirrus.driver.sh -k $kernelver --dkms"' "$KS"
need_text "Wno-incompatible-pointer-types" "$KS"
need_text "/usr/src/snd_hda_macbookpro-1.0/Makefile" "$KS"
need_text 'dkms add -m snd_hda_macbookpro -v 1.0' "$KS"
need_text 'dkms install -m snd_hda_macbookpro -v 1.0 -k "$KVER" --force --verbose' "$KS"
need_text "snd_hda_macbookpro DKMS make.log" "$KS"
need_text "/usr/src/snd_hda_macbookpro-1.0" "$KS"

# Power / USB-C / storage accessibility.
for pkg in brightnessctl upower thermald xfsprogs kmod; do
  need_pkg "$pkg"
done
need_text "thermald.service" "$KS"
need_text "battery sysfs accessible" "$KS"
need_text "backlight sysfs accessible" "$KS"
need_text "modinfo xhci_pci" "$KS"
need_text "modinfo thunderbolt" "$KS"
need_text "internal NVMe controller visible" "$KS"

# Moonlight/CocoOS build stack.
for pkg in \
  ffmpeg-libs ffmpeg-devel libplacebo libplacebo-devel openssl-devel \
  sdl2-compat-devel SDL2_ttf-devel libva-devel libvdpau-devel opus-devel \
  pulseaudio-libs-devel alsa-lib-devel libdrm-devel \
  qt6-qtbase-gui qt6-qtbase-devel qt6-qtdeclarative qt6-qtdeclarative-devel \
  qt6-qtsvg qt6-qtsvg-devel qt6-qtwebsockets qt6-qtwebsockets-devel \
  qt6-qtmultimedia qt6-qtmultimedia-devel; do
  need_pkg "$pkg"
done
! need_pkg "libavcodec-freeworld"
need_text 'qmake6 "CONFIG+=embedded" moonlight-qt.pro' "$KS"
need_text "make release -j2" "$KS"
need_text "make release" "$KS"
need_text "moonlight-os/cocoos" "$KS"
need_text "moonlight-os/moonlight" "$KS"

# Appliance UX.
need_text "moonlight-settings" "$KS"
need_text "moonlight-wifi" "$KS"
need_text "moonlight-bluetooth" "$KS"
need_text "dualsense-pair" "$KS"
need_text "airpods-pair" "$KS"
need_text "setterm --foreground red --background black" "$KS"
need_text "Ctrl+Alt+F2" "$README"

# v0.1 retains diagnostics and build tools.
for pkg in git gcc gcc-c++ make patch dkms kernel-devel kernel-headers; do
  need_pkg "$pkg"
done
need_text "v0.1 is intentionally a development/debug image" "$KS"

# OVMF/image gates.
need_text "EFI/BOOT/BOOTX64.EFI" "$ROOT/scripts/inspect-image.sh"
need_text "iHD_drv_video.so" "$ROOT/scripts/inspect-image.sh"
need_text "applespi.ko" "$ROOT/scripts/inspect-image.sh"
need_text "brcmfmac.ko" "$ROOT/scripts/inspect-image.sh"
need_text "hid-playstation.ko" "$ROOT/scripts/inspect-image.sh"
need_text "snd-hda-codec-cs8409.ko" "$ROOT/scripts/inspect-image.sh"
need_text "MOONLIGHT_OS_BOOT_OK" "$ROOT/scripts/test-ovmf.sh"
need_text "qcow2" "$ROOT/scripts/test-ovmf.sh"
need_text "OVMF_CODE.fd" "$ROOT/scripts/test-ovmf.sh"
need_text "ksvalidator" "$ROOT/scripts/audit-packages.sh"
need_text 'KVER="6.19.10-300.fc44.x86_64"' "$ROOT/scripts/audit-audio.sh"
need_text "kernel-modules-core" "$ROOT/scripts/audit-audio.sh"
need_text "Wno-incompatible-pointer-types" "$ROOT/scripts/audit-audio.sh"

# Documentation matches v0.1.
need_text "16 GB" "$README"
need_text "16 GB" "$TEST_PLAN"
! grep -Fq "8 GB-or-larger" "$README" "$TEST_PLAN"
need_text "Automated UEFI preflight" "$README"
need_text "Gate 0: automated image/UEFI preflight" "$TEST_PLAN"

echo "Static validation passed."
