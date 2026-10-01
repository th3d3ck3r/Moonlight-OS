#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Image inspection failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/SOURCES.lock"

RAW=${1:?usage: inspect-image.sh <raw-image>}
[[ -f "$RAW" ]]

work=$(mktemp -d)
loop=""
cleanup() {
  set +e
  mountpoint -q "$work/root/boot/efi" && umount "$work/root/boot/efi"
  mountpoint -q "$work/root/boot" && umount "$work/root/boot"
  mountpoint -q "$work/root" && umount "$work/root"
  [[ -n "$loop" ]] && losetup -d "$loop"
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/root"
loop=$(losetup --read-only --find --show --partscan "$RAW")
sleep 1
lsblk -o NAME,TYPE,FSTYPE,PARTTYPE "$loop"

esp=$(lsblk -lnpo NAME,FSTYPE "$loop" | awk '$2=="vfat"{print $1; exit}')
boot=$(lsblk -lnpo NAME,FSTYPE "$loop" | awk '$2=="ext4"{print $1; exit}')
root=$(lsblk -lnpo NAME,FSTYPE "$loop" | awk '$2=="xfs"{print $1; exit}')

[[ -b "$esp" ]]
[[ -b "$boot" ]]
[[ -b "$root" ]]

mount -o ro,norecovery "$root" "$work/root"
mkdir -p "$work/root/boot" "$work/root/boot/efi"
mount -o ro,noload "$boot" "$work/root/boot"
mount -o ro "$esp" "$work/root/boot/efi"

test -f "$work/root/boot/efi/EFI/BOOT/BOOTX64.EFI"
test -d "$work/root/boot/efi/EFI/fedora"
test -x "$work/root/usr/local/libexec/moonlight-os/cocoos"
test -x "$work/root/usr/local/libexec/moonlight-os/moonlight"
test -x "$work/root/usr/local/bin/moonlight-os-verify"
test -x "$work/root/usr/local/bin/moonlight-settings"
test -x "$work/root/usr/local/bin/airpods-mode"
test -x "$work/root/usr/local/bin/dualsense-check"
test -f "$work/root/etc/moonlight-os-release"
test -f "$work/root/etc/systemd/system/moonlight-os-boot-marker.service"
test -f "$work/root/home/moonlight/.config/wireplumber/wireplumber.conf.d/51-moonlight-airpods.conf"
test -f "$work/root/home/moonlight/.config/wireplumber/wireplumber.conf.d/52-disable-dualsense-audio.conf"

# Require the hardware-specific runtime payload, not merely package metadata.
test -f "$work/root/usr/lib64/dri/iHD_drv_video.so"
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'i915.ko*' -print -quit | grep -q .
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'applespi.ko*' -print -quit | grep -q .
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'brcmfmac.ko*' -print -quit | grep -q .
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'hid-playstation.ko*' -print -quit | grep -q .
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'snd-hda-codec-cs8409.ko*' -print -quit | grep -q .

grep -Rqs 'console=ttyS0,115200n8' "$work/root/boot" || {
  echo "Serial-console kernel argument not found under /boot" >&2
  exit 1
}

echo "Disk image inspection passed."
