#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/SOURCES.lock"

KVER="6.19.10-300.fc44.x86_64"
WORK=/tmp/moonlight-os-audio-audit
rm -rf "$WORK"
mkdir -p "$WORK"

dnf -y install \
  git gcc make patch wget xz openssl dkms \
  "kernel-devel-$KVER" kernel-headers

git clone -q "$AUDIO_REPO" "$WORK/snd_hda_macbookpro"
git -C "$WORK/snd_hda_macbookpro" checkout -q --detach "$AUDIO_COMMIT"

mkdir -p /usr/src/snd_hda_macbookpro-1.0
cp -a "$WORK/snd_hda_macbookpro/." /usr/src/snd_hda_macbookpro-1.0/
chmod +x /usr/src/snd_hda_macbookpro-1.0/install.cirrus.driver.sh

cat > /usr/src/snd_hda_macbookpro-1.0/dkms.conf <<'DKMSCONF'
PACKAGE_NAME="snd_hda_macbookpro"
PACKAGE_VERSION="1.0"
PRE_BUILD="install.cirrus.driver.sh -k $kernelver --dkms"
MAKE="make KERNELRELEASE=${kernelver} KBUILD_EXTRA_CFLAGS='-DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function -Wno-error -Wno-incompatible-pointer-types'"
BUILT_MODULE_NAME[0]="snd-hda-codec-cs8409"
BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus"
DEST_MODULE_LOCATION[0]="/updates/codecs/cirrus"
AUTOINSTALL="yes"
DKMSCONF

dkms remove -m snd_hda_macbookpro -v 1.0 --all 2>/dev/null || true
dkms add -m snd_hda_macbookpro -v 1.0

set +e
dkms install -m snd_hda_macbookpro -v 1.0 -k "$KVER" --force --verbose
rc=$?
set -e

if (( rc != 0 )); then
  echo "===== CIRRUS DKMS FAILURE =====" >&2
  cat /var/lib/dkms/snd_hda_macbookpro/1.0/build/make.log >&2 2>/dev/null || true
  exit "$rc"
fi

find /lib/modules/"$KVER" -name 'snd-hda-codec-cs8409.ko*' -print -quit | grep -q .
echo "Cirrus audio DKMS audit passed for $KVER."
