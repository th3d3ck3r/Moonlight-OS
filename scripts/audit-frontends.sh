#!/usr/bin/env bash
# Called after the complete Fedora package audit, in the same disposable container.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TASK=$(mktemp -d /tmp/moonlight-frontends.XXXXXX)
export FRONTENDS_LOCK="$ROOT/SOURCES.lock" FRONTENDS_DEST="$TASK/runtime/frontends"
export VIBEMIS_SOURCE="$TASK/vibemis-source"
export FRONTENDS_CACHE="$TASK/cache" ARTEMIS_SOURCE="$TASK/artemis-source"
bash "$ROOT/scripts/install-frontends.sh"
dnf -y install xorg-x11-server-Xvfb
export MOONLIGHT_FRONTEND_BASE="$TASK/runtime"
export HOME="$TASK/home" QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1
mkdir -p "$HOME" "$TASK/config" /tmp/runtime-frontend
chmod 0700 /tmp/runtime-frontend
export XDG_RUNTIME_DIR=/tmp/runtime-frontend
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
  wait "$pid" || true
  echo "$client remained alive through an X11 software-rendered GUI startup."
done
python3 "$ROOT/scripts/audit-bluetooth-frontends.py"
echo 'All three added frontends compile/load on Fedora 44; Bluetooth fixture checks passed.'
