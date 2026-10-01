#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/SOURCES.lock"
OUT="$ROOT/out"
CACHE="$ROOT/.cache"
mkdir -p "$OUT" "$CACHE"
MODE=${1:-build}
[[ "$MODE" == build || "$MODE" == --validate-only ]] || { echo 'usage: build-image.sh [--validate-only]' >&2; exit 2; }
ISO="$CACHE/$FEDORA_ISO"

if [[ "$MODE" == build ]]; then
if [[ ! -f "$ISO" ]]; then
  curl -L --fail --retry 5 --retry-delay 3 -o "$ISO" "$FEDORA_ISO_URL"
fi
printf '%s  %s\n' "$FEDORA_ISO_SHA256" "$ISO" | sha256sum -c -

rm -rf "$OUT/lmc" "$OUT/moonlight-os-mbp14-1.raw" "$OUT/moonlight-os-mbp14-1.raw.xz"*

LMC_ARGS=(
  --make-disk
  --virt-uefi
  --iso="$ISO"
  --ks="$ROOT/config/moonlight-os.ks"
  --image-name=moonlight-os-mbp14-1.raw
  --resultdir="$OUT/lmc"
  --project="Moonlight-OS"
  --releasever=44
  --volid="MOONLIGHT_OS"
  --ram=4096
  --vcpus=2
)
if [[ ! -e /dev/kvm ]]; then
  LMC_ARGS+=(--no-kvm)
fi

if (( EUID == 0 )); then
  livemedia-creator "${LMC_ARGS[@]}"
else
  sudo livemedia-creator "${LMC_ARGS[@]}"
fi
RAW=$(find "$OUT/lmc" -maxdepth 2 -type f -name 'moonlight-os-mbp14-1.raw' -print -quit)
[[ -n "$RAW" && -f "$RAW" ]]
mv "$RAW" "$OUT/moonlight-os-mbp14-1.raw"
cd "$ROOT"
sha256sum SOURCES.lock config/moonlight-os.ks > "$OUT/build-inputs.sha256"
else
  cd "$ROOT"
  sha256sum -c "$OUT/build-inputs.sha256"
  test -f "$OUT/moonlight-os-mbp14-1.raw"
fi

fdisk -l "$OUT/moonlight-os-mbp14-1.raw"
SIZE=$(stat -c %s "$OUT/moonlight-os-mbp14-1.raw")
MAX=$((14000 * 1024 * 1024))
if (( SIZE > MAX )); then
  echo "Image is too large for the conservative 16 GB USB development target: $SIZE bytes" >&2
  exit 1
fi

bash "$ROOT/scripts/inspect-image.sh" "$OUT/moonlight-os-mbp14-1.raw"
bash "$ROOT/scripts/test-ovmf.sh" "$OUT/moonlight-os-mbp14-1.raw"

# Read-only inspection and the qcow2 boot overlay leave recovered raw data unchanged.
# Retain its verified archive instead of recompressing the same image.
if [[ "$MODE" != --validate-only || ! -f "$OUT/moonlight-os-mbp14-1.raw.xz" ]]; then
  xz -T0 -9e "$OUT/moonlight-os-mbp14-1.raw"
fi
(cd "$OUT" && sha256sum moonlight-os-mbp14-1.raw.xz > moonlight-os-mbp14-1.raw.xz.sha256)
