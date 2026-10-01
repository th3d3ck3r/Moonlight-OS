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
created_nodes=()
cleanup() {
  set +e
  mountpoint -q "$work/root/boot/efi" && umount "$work/root/boot/efi"
  mountpoint -q "$work/root/boot" && umount "$work/root/boot"
  mountpoint -q "$work/root" && umount "$work/root"
  for node in "${created_nodes[@]}"; do rm -f "$node"; done
  [[ -n "$loop" ]] && losetup -d "$loop"
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/root"
loop=$(losetup --read-only --find --show --partscan "$RAW")
sleep 1
[[ "$(blkid -p -s PTTYPE -o value "$loop")" == gpt ]]

# Containers have sysfs partition information but often no udev database or
# partition device nodes. Probe the block devices directly instead of relying
# on lsblk's udev-backed FSTYPE column.
esp=""; boot=""; root=""
while read -r node kind; do
  [[ "$kind" == part ]] || continue
  if [[ ! -b "$node" ]]; then
    IFS=: read -r major minor < "/sys/class/block/$(basename "$node")/dev"
    mknod "$node" b "$major" "$minor"
    created_nodes+=("$node")
  fi
  fs=$(blkid -p -s TYPE -o value "$node")
  printf 'Image partition: %s (%s)\n' "$node" "$fs"
  case "$fs" in
    vfat) [[ -z "$esp" ]] && esp="$node" ;;
    ext4) [[ -z "$boot" ]] && boot="$node" ;;
    xfs) [[ -z "$root" ]] && root="$node" ;;
  esac
done < <(lsblk -lnpo NAME,TYPE "$loop")

[[ -b "$esp" ]]
[[ -b "$boot" ]]
[[ -b "$root" ]]

mount -o ro,norecovery "$root" "$work/root"
test -d "$work/root/boot"
mount -o ro,noload "$boot" "$work/root/boot"
test -d "$work/root/boot/efi"
mount -o ro "$esp" "$work/root/boot/efi"

test -f "$work/root/boot/efi/EFI/BOOT/BOOTX64.EFI"
test -d "$work/root/boot/efi/EFI/fedora"
test -s "$work/root/boot/vmlinuz-$INSTALLER_KERNEL"
test -s "$work/root/boot/initramfs-$INSTALLER_KERNEL.img"
test -x "$work/root/usr/local/libexec/moonlight-os/cocoos"
test -x "$work/root/usr/local/libexec/moonlight-os/moonlight"
test -x "$work/root/usr/local/bin/moonlight-os-verify"
test -x "$work/root/usr/local/bin/moonlight-settings"
test -x "$work/root/usr/local/bin/airpods-mode"
test -x "$work/root/usr/local/bin/dualsense-check"
test -f "$work/root/etc/moonlight-os-release"
test -f "$work/root/etc/systemd/system/moonlight-os-boot-marker.service"
test -f "$work/root/etc/systemd/system/moonlight-os-grow-root.service"
test -L "$work/root/etc/systemd/system/multi-user.target.wants/moonlight-os-boot-marker.service"
test -L "$work/root/etc/systemd/system/multi-user.target.wants/moonlight-os-grow-root.service"
test -f "$work/root/home/moonlight/.bash_profile"
test -f "$work/root/etc/X11/xorg.conf.d/40-moonlight-macbook-input.conf"
test -f "$work/root/etc/NetworkManager/conf.d/99-moonlight-wifi.conf"
test -f "$work/root/etc/modprobe.d/brcmfmac-moonlight.conf"
test -f "$work/root/home/moonlight/.config/wireplumber/wireplumber.conf.d/51-moonlight-airpods.conf"
test -f "$work/root/home/moonlight/.config/wireplumber/wireplumber.conf.d/52-disable-dualsense-audio.conf"

# Require the hardware-specific runtime payload, not merely package metadata.
test -f "$work/root/usr/lib64/dri/iHD_drv_video.so"
# Resolve executable symlinks inside the guest, not against the build host.
chroot "$work/root" /bin/bash -ec '
  export PATH=/usr/sbin:/usr/bin:/sbin:/bin
  missing=0
  for tool do
    command -v "$tool" || { echo "Required installed tool missing: $tool" >&2; missing=1; }
  done
  exit "$missing"
' bash Xorg libinput xinput evtest nmcli nmtui-connect bluetoothctl \
  pipewire wireplumber wpctl intel_gpu_top vainfo glxinfo growpart xfs_growfs \
  gcc git dkms modinfo
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'i915.ko*' -print -quit | grep -q .
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'applespi.ko*' -print -quit | grep -q .
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'brcmfmac.ko*' -print -quit | grep -q .
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'hid-playstation.ko*' -print -quit | grep -q .
find "$work/root/usr/lib/modules/$INSTALLER_KERNEL" -name 'snd-hda-codec-cs8409.ko*' -print -quit | grep -q .

grep -Rqs 'console=ttyS0,115200n8' "$work/root/boot" || {
  echo "Serial-console kernel argument not found under /boot" >&2
  exit 1
}

# Keep a kernel/initramfs copy for a diagnostic-only boot if the UEFI gate fails.
diag_dir="$(dirname "$(realpath "$RAW")")"
cp "$work/root/boot/vmlinuz-$INSTALLER_KERNEL" "$diag_dir/diagnostic-kernel"
cp "$work/root/boot/initramfs-$INSTALLER_KERNEL.img" "$diag_dir/diagnostic-initrd"
blkid -p -s UUID -o value "$root" > "$diag_dir/diagnostic-root-uuid"
chroot "$work/root" /usr/bin/lsblk --version

echo "Disk image inspection passed."
