#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/SOURCES.lock"
OUT="$ROOT/out"
CACHE="$ROOT/.cache"
mkdir -p "$OUT" "$CACHE"
ISO="$CACHE/$FEDORA_ISO"

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

fdisk -l "$OUT/moonlight-os-mbp14-1.raw"
SIZE=$(stat -c %s "$OUT/moonlight-os-mbp14-1.raw")
MAX=$((14000 * 1024 * 1024))
if (( SIZE > MAX )); then
  echo "Image is too large for the conservative 16 GB USB development target: $SIZE bytes" >&2
  exit 1
fi

bash "$ROOT/scripts/inspect-image.sh" "$OUT/moonlight-os-mbp14-1.raw"
bash "$ROOT/scripts/test-ovmf.sh" "$OUT/moonlight-os-mbp14-1.raw"

xz -T0 -9e "$OUT/moonlight-os-mbp14-1.raw"
sha256sum "$OUT/moonlight-os-mbp14-1.raw.xz" > "$OUT/moonlight-os-mbp14-1.raw.xz.sha256"
