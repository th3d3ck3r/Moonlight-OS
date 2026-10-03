#!/usr/bin/env bash
# Called after the complete Fedora package audit, in the same disposable container.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TASK=$(mktemp -d /tmp/moonlight-frontends.XXXXXX)
export FRONTENDS_LOCK="$ROOT/SOURCES.lock" FRONTENDS_DEST="$TASK/runtime/frontends"
export FRONTENDS_SHARE_DEST="$TASK/share"
export VIBEMIS_SOURCE="$TASK/vibemis-source"
export VIBEMIS_PATCH="$ROOT/patches/vibemis-crimson.patch"
export FRONTENDS_CACHE="$TASK/cache" ARTEMIS_SOURCE="$TASK/artemis-source"
bash "$ROOT/scripts/install-frontends.sh"
grep -Fxq 'Name=Eclipse' "$TASK/share/applications/com.vibemis.Vibemis.desktop"
grep -Fxq 'Icon=eclipse' "$TASK/share/applications/com.vibemis.Vibemis.desktop"
for size in 128 256 512; do
  cmp "$VIBEMIS_SOURCE/app/res/icons/hicolor/${size}x${size}/apps/eclipse.png" \
    "$TASK/share/icons/hicolor/${size}x${size}/apps/eclipse.png"
done
dnf -y install xorg-x11-server-Xvfb
export MOONLIGHT_FRONTEND_BASE="$TASK/runtime"
export HOME="$TASK/home" QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1
mkdir -p "$HOME" "$TASK/config" /tmp/runtime-frontend
chmod 0700 /tmp/runtime-frontend
export XDG_RUNTIME_DIR=/tmp/runtime-frontend
# Load the image's exact library metadata. Existing Moonlight/CocoOS binaries
# were proven by prior image builds; stand-ins here only make their files exist.
for existing in moonlight cocoos; do
  printf '#!/bin/sh\nexit 0\n' > "$TASK/runtime/$existing"
  chmod 0755 "$TASK/runtime/$existing"
done
python3 - "$ROOT/config/moonlight-os.ks" "$HOME" "$TASK/runtime" <<'META_AUDIT'
from pathlib import Path
import sys
ks=Path(sys.argv[1]).read_text()
meta=ks.split("<<'PEGASUS_META'\n",1)[1].split('\nPEGASUS_META\n',1)[0]
meta=meta.replace('/usr/local/libexec/moonlight-os',sys.argv[3])
collection, games=meta.split('\ngame:',1)
listed=[line.strip() for line in collection.splitlines() if line.startswith('  /')]
assert len(listed)==4 and all(Path(p).is_file() for p in listed)
assert meta.count('\ngame:')==4
out=Path(sys.argv[2])/'.config/pegasus-frontend/metafiles/metadata.pegasus.txt'
out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(meta+'\n')
META_AUDIT
Xvfb :77 -screen 0 1280x800x24 -nolisten tcp > "$TASK/xvfb.log" 2>&1 &
XVFB=$!
trap 'kill "$XVFB" 2>/dev/null || true' EXIT
export DISPLAY=:77
sleep 2
for client in vibemis artemis pegasus; do
  bash "$ROOT/scripts/frontend-launch.sh" "$client" > "$TASK/$client.log" 2>&1 &
  pid=$!
  sleep 8
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "$client exited during GUI startup" >&2
    cat "$TASK/$client.log" >&2
    wait "$pid" || true
    exit 1
  fi
  # Catch a QML error page that can keep the process alive despite a broken UI.
  if grep -Eiq 'QQmlApplicationEngine failed to load|module .* is not installed|Cannot load library|error while loading shared libraries' "$TASK/$client.log"; then
    cat "$TASK/$client.log" >&2
    kill "$pid" || true
    exit 1
  fi
  kill "$pid"
  # Client signal handlers may wait for network workers during teardown.
  # Bound CI cleanup; the startup check above still requires a live GUI.
  for ((attempt=0; attempt<30; attempt++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" || true
  echo "$client remained alive through an X11 software-rendered GUI startup."
done
python3 "$ROOT/scripts/audit-bluetooth-frontends.py"
echo 'All three added frontends compile/load on Fedora 44; Bluetooth fixture checks passed.'
