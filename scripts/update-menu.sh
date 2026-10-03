#!/usr/bin/env bash
set -u
HELPER=/usr/local/libexec/moonlight-os/eclipseos-update.py
if [[ ! -x $HELPER ]]; then
  echo 'Updater is not enrolled on this image. See docs/UPDATES.md for one-time bootstrap.'
  exit 1
fi
while true; do
  printf '\nEclipseOS updates (current kernel/base locked)\n'
  sudo -n "$HELPER" status
  printf '\n1) Check stable  2) Check testing  3) Stage stable  4) Stage testing\n5) Stage from USB/folder  6) Apply (close frontend first)\n7) Confirm tested trial  8) Roll back (close frontend first)\n9) Cancel pending update  0) Exit\nChoose: '
  read -r choice || exit 0
  case "$choice" in
    1) sudo -n "$HELPER" check stable ;;
    2) sudo -n "$HELPER" check testing ;;
    3) sudo -n "$HELPER" stage stable ;;
    4) sudo -n "$HELPER" stage testing ;;
    5) read -r -p 'Absolute package folder: ' folder; sudo -n "$HELPER" stage-offline "$folder" ;;
    6) sudo -n "$HELPER" apply ;;
    7) read -r -p 'Have frontend, Wi-Fi and Bluetooth passed your checks? Type KEEP: ' answer
       [[ $answer == KEEP ]] && sudo -n "$HELPER" confirm ;;
    8) sudo -n "$HELPER" rollback ;;
    9) sudo -n "$HELPER" cancel ;;
    0) exit 0 ;;
  esac
  read -r -p 'Press Enter...' _ || exit 0
done
