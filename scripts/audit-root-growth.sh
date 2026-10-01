#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
dnf -y install util-linux xfsprogs cloud-utils-growpart gawk
work=$(mktemp -d)
loop=""
created_nodes=()
cleanup() {
  set +e
  mountpoint -q "$work/root" && umount "$work/root"
  [[ -n "$loop" ]] && losetup -d "$loop"
  for node in "${created_nodes[@]}"; do rm -f "$node"; done
  rm -f /var/lib/moonlight-os-root-grown
  rm -rf "$work"
}
trap cleanup EXIT
truncate -s 512M "$work/disk.raw"
sfdisk "$work/disk.raw" <<'GPT'
label: gpt
size=32M,type=U
size=32M,type=L
size=384M,type=L
GPT
loop=$(losetup --find --show --partscan "$work/disk.raw")
while read -r node kind; do
  [[ "$kind" == part ]] || continue
  if [[ ! -b "$node" ]]; then
    IFS=: read -r major minor < "/sys/class/block/$(basename "$node")/dev"
    mknod "$node" b "$major" "$minor"
    created_nodes+=("$node")
  fi
done < <(lsblk -lnpo NAME,TYPE "$loop")
root_device="${loop}p3"
esp_size=$(blockdev --getsize64 "${loop}p1")
boot_size=$(blockdev --getsize64 "${loop}p2")
part_before=$(blockdev --getsize64 "$root_device")
mkfs.xfs -f "$root_device"
mkdir -p "$work/root" "$work/bin"
mount "$root_device" "$work/root"
fs_before=$(df -B1 --output=size "$work/root" | tail -n1)
awk '/^cat > \/usr\/local\/sbin\/moonlight-os-grow-root /{body=1;next} body && /^GROW$/{exit} body{print}' "$ROOT/config/moonlight-os.ks" > "$work/grow-root"
test -s "$work/grow-root"
export AUDIT_ROOT_DEVICE="$root_device"
export AUDIT_ROOT_MOUNT="$work/root"
export AUDIT_XFS_GROWFS="$(command -v xfs_growfs)"
cat > "$work/bin/findmnt" <<'FINDMNT'
#!/usr/bin/env bash
printf '%s\n' "$AUDIT_ROOT_DEVICE"
FINDMNT
cat > "$work/bin/xfs_growfs" <<'XFS'
#!/usr/bin/env bash
exec "$AUDIT_XFS_GROWFS" "$AUDIT_ROOT_MOUNT"
XFS
cat > "$work/bin/udevadm" <<'UDEV'
#!/usr/bin/env bash
# The disposable container has no udev daemon. Check the kernel partition
# update and actual XFS resize independently below.
exit 0
UDEV
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
rm -f /var/lib/moonlight-os-root-grown
bash "$work/grow-root"
part_after=$(blockdev --getsize64 "$root_device")
fs_after=$(df -B1 --output=size "$work/root" | tail -n1)
(( part_after > part_before ))
(( fs_after > fs_before ))
[[ "$(blockdev --getsize64 "${loop}p1")" == "$esp_size" ]]
[[ "$(blockdev --getsize64 "${loop}p2")" == "$boot_size" ]]
test -f /var/lib/moonlight-os-root-grown
# A full disk must succeed through NOCHANGE rather than blocking the boot gate.
bash "$work/grow-root"
# A real growth failure must remain retryable and never create the marker.
cat > "$work/bin/growpart" <<'FAIL'
#!/usr/bin/env bash
echo "Injected growpart failure for retry audit" >&2
exit 2
FAIL
chmod +x "$work/bin/growpart"
rm -f /var/lib/moonlight-os-root-grown
if bash "$work/grow-root"; then
  echo "Growth failure was incorrectly accepted" >&2
  exit 1
fi
test ! -e /var/lib/moonlight-os-root-grown
echo "Root growth audit passed: GPT/XFS grew, EFI/boot unchanged, NOCHANGE accepted, failures retryable."
