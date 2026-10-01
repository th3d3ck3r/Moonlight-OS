#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/SOURCES.lock"

KVER="6.19.10-300.fc44.x86_64"
WORK=/tmp/moonlight-os-audio-audit
rm -rf "$WORK"
mkdir -p "$WORK"

dnf -y install   git gcc make patch wget xz dkms   "kernel-devel-$KVER" kernel-headers

git clone -q "$AUDIO_REPO" "$WORK/snd_hda_macbookpro"
git -C "$WORK/snd_hda_macbookpro" checkout -q --detach "$AUDIO_COMMIT"

cd "$WORK/snd_hda_macbookpro"
chmod +x install.cirrus.driver.sh

# Prepare the extracted/patched HDA source tree exactly as the image does.
./install.cirrus.driver.sh -k "$KVER" --dkms

set +e
make -j2   KERNELRELEASE="$KVER"   CFLAGS_MODULE='-DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function -Wno-error -Wno-incompatible-pointer-types'   2>&1 | tee "$WORK/make.log"
rc=${PIPESTATUS[0]}
set -e

if (( rc != 0 )); then
  echo
  echo "===== CIRRUS BUILD FAILURE SUMMARY =====" >&2
  grep -nE 'error:|fatal error:|undefined|incompatible|too (few|many) arguments|no member named' "$WORK/make.log" | tail -n 200 >&2 || true
  exit "$rc"
fi

find build/hda -name 'snd-hda-codec-cs8409.ko*' -print -quit | grep -q .
echo "Cirrus audio module compile audit passed for $KVER."
