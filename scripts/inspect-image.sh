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

test -x "$work/root/usr/local/libexec/moonlight-os/system-controls.py"
test -x "$work/root/usr/local/libexec/moonlight-os/control-center.py"
grep -Fq 'center-volume' "$work/root/usr/local/libexec/moonlight-os/control-center.py"
grep -Fq 'VERSION="0.3-dev"' "$work/root/etc/moonlight-os-release"
for helper in system-controls.py control-center.py; do
  cmp "$ROOT/scripts/$helper" "$work/root/usr/local/libexec/moonlight-os/$helper"
done
cmp "$ROOT/scripts/bluetooth-menu.py" "$work/root/usr/local/bin/moonlight-bluetooth"
cmp "$ROOT/scripts/install-frontends.sh" "$work/root/usr/local/share/moonlight-os/install-frontends.sh"
cmp "$ROOT/patches/vibemis-crimson.patch" "$work/root/usr/local/share/moonlight-os/vibemis-crimson.patch"
grep -Fxq 'Name=Eclipse' "$work/root/usr/local/share/applications/com.vibemis.Vibemis.desktop"
grep -Fxq 'Icon=eclipse' "$work/root/usr/local/share/applications/com.vibemis.Vibemis.desktop"
grep -Fxq 'Exec=/usr/local/bin/moonlight-launch vibemis' "$work/root/usr/local/share/applications/com.vibemis.Vibemis.desktop"
python3 - "$work/root" <<'ICON_CHECK'
from pathlib import Path
import struct, sys
root = Path(sys.argv[1])
for size in (128, 256, 512):
    data = (root / f'usr/local/share/icons/hicolor/{size}x{size}/apps/eclipse.png').read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR'
    assert struct.unpack('>II', data[16:24]) == (size, size)
ICON_CHECK
grep -Fxq 'game: Eclipse' "$work/root/home/moonlight/.config/pegasus-frontend/metafiles/metadata.pegasus.txt"
test -f "$work/root/boot/efi/EFI/BOOT/BOOTX64.EFI"
test -d "$work/root/boot/efi/EFI/fedora"
test -s "$work/root/boot/vmlinuz-$INSTALLER_KERNEL"
test -s "$work/root/boot/initramfs-$INSTALLER_KERNEL.img"
# Future animation-enabled images must contain both the selected theme and its
# exact initramfs copy. The existing published image predates this source change.
for asset in background.png apollo.png crimson-apollo.script crimson-apollo.plymouth; do
  test -s "$work/root/usr/share/plymouth/themes/crimson-apollo/$asset"
done
test -s "$work/root/usr/lib64/plymouth/script.so"
grep -Eq '^[[:space:]]*Theme=crimson-apollo[[:space:]]*$' "$work/root/etc/plymouth/plymouthd.conf"
# Run from the disposable build host: lsinitrd needs writable temporary files
# and /dev/null, while the release image stays mounted strictly read-only.
TMPDIR="$work" lsinitrd "$work/root/boot/initramfs-$INSTALLER_KERNEL.img" > "$work/initramfs-list"
for asset in background.png apollo.png crimson-apollo.script crimson-apollo.plymouth; do
  grep -Fq "usr/share/plymouth/themes/crimson-apollo/$asset" "$work/initramfs-list"
done
grep -Fq 'plymouth/script.so' "$work/initramfs-list"
grep -Eq 'plymouth/label-(pango|freetype)\.so' "$work/initramfs-list"
grep -Fq 'usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf' "$work/initramfs-list"
test -x "$work/root/usr/local/libexec/moonlight-os/cocoos"
test -x "$work/root/usr/local/libexec/moonlight-os/moonlight"
for payload in frontends/artemis frontends/vibemis/AppRun frontends/vibemis/usr/bin/vibemis frontends/pegasus/pegasus-fe; do
  test -x "$work/root/usr/local/libexec/moonlight-os/$payload"
done
for helper in moonlight-launch moonlight-frontend-select moonlight-bluetooth; do
  test -x "$work/root/usr/local/bin/$helper"
done
cmp "$ROOT/SOURCES.lock" "$work/root/usr/local/share/moonlight-os/FRONTENDS.lock"
grep -Fqx "VIBEMIS_PATCH_SHA256=$VIBEMIS_PATCH_SHA256" "$work/root/usr/local/libexec/moonlight-os/frontends/versions.conf"
grep -Fq "VIBEMIS_COMMIT=$VIBEMIS_COMMIT" "$work/root/usr/local/libexec/moonlight-os/frontends/versions.conf"
grep -Fq "ARTEMIS_COMMIT=$ARTEMIS_COMMIT" "$work/root/usr/local/libexec/moonlight-os/frontends/versions.conf"
chroot "$work/root" python3 -c 'import pexpect, dbus; paths=["/usr/local/bin/moonlight-bluetooth","/usr/local/libexec/moonlight-os/system-controls.py","/usr/local/libexec/moonlight-os/control-center.py"]; [compile(open(path).read(),path,"exec") for path in paths]'
test -f "$work/root/home/moonlight/.config/pegasus-frontend/metafiles/metadata.pegasus.txt"
test -x "$work/root/usr/local/bin/moonlight-os-verify"
test -x "$work/root/usr/local/bin/moonlight-settings"
test -x "$work/root/usr/local/bin/airpods-mode"
test -x "$work/root/usr/local/bin/dualsense-check"
test -f "$work/root/etc/moonlight-os-release"
grep -Fxq 'NAME="EclipseOS"' "$work/root/etc/moonlight-os-release"
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
test -x "$work/root/usr/local/bin/moonlight-audio"
test -f "$work/root/etc/profile.d/moonlight-rows.sh"
test -f "$work/root/etc/systemd/system/moonlight-audio-restore.service"
test -L "$work/root/etc/systemd/system/multi-user.target.wants/moonlight-audio-restore.service"
test -f "$work/root/home/moonlight/.config/openbox/rc.xml"
test -x "$work/root/usr/local/bin/moonlight-media-keys"
test -L "$work/root/etc/systemd/system/multi-user.target.wants/moonlight-media-keys.service"
grep -Rq 'spi::kbd_backlight' "$work/root/etc/udev/rules.d"

# Require the hardware-specific runtime payload, not merely package metadata.
test -f "$work/root/usr/lib64/dri-nonfree/iHD_drv_video.so"
for codec in sbc aac; do
  test -s "$work/root/usr/lib64/spa-0.2/bluez5/libspa-codec-bluez5-$codec.so"
  echo "Installed Bluetooth codec plugin verified: $codec"
done
# Resolve executable symlinks inside the guest, not against the build host.
chroot "$work/root" /bin/bash -ec '
  export PATH=/usr/sbin:/usr/bin:/sbin:/bin
  missing=0
  for tool do
    command -v "$tool" || { echo "Required installed tool missing: $tool" >&2; missing=1; }
  done
  exit "$missing"
' bash Xorg openbox xprop python3 libinput xinput evtest nmcli nmtui-connect bluetoothctl \
  pipewire wireplumber wpctl intel_gpu_top vainfo glxinfo growpart xfs_growfs \
  gcc git dkms modinfo brightnessctl alsamixer alsactl speaker-test xrandr xset systemd-run
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
