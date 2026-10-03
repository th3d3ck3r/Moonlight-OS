#!/usr/bin/env bash
set -euo pipefail
# Keep each client's bundled Qt/SDL libraries confined to its own child process.
unset LD_LIBRARY_PATH QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH
export QT_QPA_PLATFORM=xcb
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
BASE=${MOONLIGHT_FRONTEND_BASE:-/usr/local/libexec/moonlight-os}
case "${1:-}" in
  moonlight|cocoos|artemis|vibemis|pegasus) ;;
  *) echo 'usage: moonlight-launch {moonlight|cocoos|vibemis|artemis|pegasus}' >&2; exit 2 ;;
esac
# Fixture/frontends overrides intentionally bypass the installed root updater.
UPDATER=/usr/local/libexec/moonlight-os/eclipseos-update.py
if [[ -z ${MOONLIGHT_FRONTEND_BASE+x} && -x $UPDATER ]]; then
  if ! sudo -n "$UPDATER" launch-preflight >&2; then
    echo 'Update preflight failed. Use tty2 -> EclipseOS updates for recovery.' >&2
    exit 1
  fi
fi
case "${1:-}" in
  moonlight|cocoos) exec "$BASE/$1" "${@:2}" ;;
  artemis) exec "$BASE/frontends/artemis" "${@:2}" ;;
  vibemis)
    # Retain the tested full iHD driver on this Intel target.
    if [[ -f /usr/lib64/dri-nonfree/iHD_drv_video.so ]]; then
      export LIBVA_DRIVERS_PATH=/usr/lib64/dri-nonfree
    fi
    CURRENT=/usr/local/libexec/eclipseos/current/vibemis
    if [[ -z ${MOONLIGHT_FRONTEND_BASE+x} && -x $UPDATER && -x $CURRENT ]]; then
      # A failed trial exits before recovery; no live frontend files are replaced.
      if "$CURRENT" "${@:2}"; then
        exit 0
      else
        failure=$?
        sudo -n "$UPDATER" recover-boot >&2 || exit "$failure"
        echo 'Updated Eclipse exited with an error; starting the preserved baseline.' >&2
      fi
    fi
    exec "$BASE/frontends/vibemis/AppRun" "${@:2}"
    ;;
  pegasus) exec "$BASE/frontends/pegasus/pegasus-fe" "${@:2}" ;;
  *) echo 'usage: moonlight-launch {moonlight|cocoos|vibemis|artemis|pegasus}' >&2; exit 2 ;;
esac
