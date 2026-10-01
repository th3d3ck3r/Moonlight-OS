#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "OVMF validation failed at line $LINENO: $BASH_COMMAND" >&2' ERR

command -v qemu-system-x86_64 >/dev/null
command -v qemu-img >/dev/null

CODE=""
VARS=""
# Fedora edk2-ovmf and Debian/Ubuntu ovmf use different firmware directories.
for dir in /usr/share/edk2/ovmf /usr/share/OVMF; do
  if [[ -f "$dir/OVMF_CODE.fd" && -f "$dir/OVMF_VARS.fd" ]]; then
    CODE="$dir/OVMF_CODE.fd"
    VARS="$dir/OVMF_VARS.fd"
    break
  fi
done
[[ -f "$CODE" ]]
[[ -f "$VARS" ]]
if [[ "${1:-}" == --check-tools ]]; then
  echo "OVMF tools available: $CODE, $VARS"
  exit 0
fi
RAW=${1:?usage: test-ovmf.sh <raw-image>|--check-tools}
[[ -f "$RAW" ]]

work=$(mktemp -d)
cleanup() {
  set +e
  [[ -n "${qemu_pid:-}" ]] && kill "$qemu_pid" 2>/dev/null || true
  wait "${qemu_pid:-}" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

cp "$VARS" "$work/OVMF_VARS.fd"
qemu-img create -q -f qcow2 -F raw -b "$(realpath "$RAW")" "$work/overlay.qcow2"

accel=tcg
cpu=max
if [[ -e /dev/kvm ]]; then
  accel=kvm
  cpu=host
fi

log="$(dirname "$(realpath "$RAW")")/ovmf-serial.log"
: > "$log"

qemu-system-x86_64   -machine "q35,accel=$accel"   -cpu "$cpu"   -m 2048   -smp 2   -drive "if=pflash,format=raw,readonly=on,file=$CODE"   -drive "if=pflash,format=raw,file=$work/OVMF_VARS.fd"   -drive "if=virtio,format=qcow2,file=$work/overlay.qcow2"   -display none   -serial "file:$log"   -monitor none   -net none   -no-reboot   >"$(dirname "$log")/ovmf-qemu.log" 2>&1 &
qemu_pid=$!

ok=0
for _ in $(seq 1 150); do
  if grep -q 'MOONLIGHT_OS_BOOT_OK' "$log"; then
    ok=1
    break
  fi
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [[ "$ok" -ne 1 ]]; then
  echo "OVMF boot test failed. Serial log follows:" >&2
  tail -n 250 "$log" >&2 || true
  exit 1
fi

echo "OVMF UEFI boot test passed."
