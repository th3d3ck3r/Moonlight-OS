#!/usr/bin/env bash
# Saved profile changes never intentionally take down the working connection.
set -u
export LC_ALL=C
active_uuid() {
  nmcli -t --escape no -f UUID,TYPE connection show --active 2>/dev/null |
    awk -F: '$2=="802-11-wireless" {print $1; exit}'
}
profile_name() {
  nmcli -g connection.id connection show uuid "$1" 2>/dev/null | tr -d '\000-\037\177'
}
select_profile() {
  local active selected index
  active=$(active_uuid)
  if [[ -n $active ]]; then
    SELECTED_UUID=$active
  else
    mapfile -t profiles < <(nmcli -t --escape no -f UUID,TYPE connection show 2>/dev/null |
      awk -F: '$2=="802-11-wireless" {print $1}')
    if (( ${#profiles[@]} == 0 )); then
      echo 'No saved Wi-Fi profile. Use Connect / change Wi-Fi first.'
      return 1
    fi
    echo 'No active Wi-Fi. Choose a saved profile:'
    for index in "${!profiles[@]}"; do
      printf '  %d) %s\n' "$((index+1))" "$(profile_name "${profiles[index]}")"
    done
    read -r -p 'Profile number (Enter cancels): ' selected || return 1
    [[ $selected =~ ^[0-9]{1,3}$ ]] || return 1
    index=$((10#$selected-1))
    (( index >= 0 && index < ${#profiles[@]} )) || return 1
    SELECTED_UUID=${profiles[index]}
  fi
  [[ $SELECTED_UUID =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}
set_band() {
  local band=$1 description=$2
  select_profile || return 1
  if sudo -n nmcli --wait 10 connection modify uuid "$SELECTED_UUID" \
      802-11-wireless.band "$band" 802-11-wireless.bssid ''; then
    printf '%s saved for %s.\n' "$description" "$(profile_name "$SELECTED_UUID")"
    echo 'The current connection was left running. Applies on the next reconnect.'
    echo 'Use option 5 to reconnect now; it will ask for credentials if needed.'
  else
    echo 'Could not save the preference. No disconnect was requested.'
    return 1
  fi
}
main() {
  local active choice reply
  while true; do
    clear
    printf '\033[40m\033[31m'
    active=$(active_uuid)
    printf 'WI-FI\n=====\n\nActive: %s\n' "${active:+$(profile_name "$active")}"
    cat <<'MENU'

  1) Connect / change Wi-Fi
  2) 5 GHz ONLY (no 2.4 GHz fallback; optional)
  3) Automatic band / AP selection (recommended for combined 2.4/5 GHz)
  4) Show Wi-Fi status
  5) Reconnect saved Wi-Fi (asks for missing credentials)
  0) Back
MENU
    read -r -p 'Choose: ' choice || return 0
    case "$choice" in
      1) nmtui-connect ;;
      2)
        read -r -p 'Restrict this profile to 5 GHz on its next reconnect? Type yes: ' reply
        [[ $reply == yes ]] && set_band a '5 GHz only'
        read -r -p 'Press Enter...' _ ;;
      3) set_band '' 'Automatic band / AP selection'; read -r -p 'Press Enter...' _ ;;
      4) nmcli device wifi list; echo; iw dev 2>/dev/null || true; read -r -p 'Press Enter...' _ ;;
      5)
        if select_profile; then
          echo 'Reconnecting may briefly interrupt the network. Credentials are not put in command arguments.'
          if sudo -n nmcli --ask --wait 40 connection up uuid "$SELECTED_UUID"; then
            echo 'Wi-Fi connection activated.'
          else
            echo 'Reconnect failed or was cancelled. Use option 3 for automatic band selection, then option 1 to connect.'
          fi
        fi
        read -r -p 'Press Enter...' _ ;;
      0) return 0 ;;
    esac
  done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main; fi
