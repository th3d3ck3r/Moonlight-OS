#!/usr/bin/env bash
# One-time manual enrollment on an existing USB. Do not run as part of preparation.
set -euo pipefail
[[ $EUID == 0 && $# == 1 ]] || { echo 'usage: sudo scripts/bootstrap-updater.sh /absolute/Ed25519-public.pem' >&2; exit 2; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KEY_FILE=$1
[[ $KEY_FILE == /* && -f $KEY_FILE && ! -L $KEY_FILE ]]
[[ $(uname -r) == 6.19.10-300.fc44.x86_64 && $(uname -m) == x86_64 ]]
grep -Fxq 'NAME="EclipseOS"' /etc/moonlight-os-release
grep -Fxq 'FEDORA="44"' /etc/moonlight-os-release
grep -Fxq 'TARGET="MacBookPro14,1"' /etc/moonlight-os-release
# Check exact shipped frontend foundation, rather than enrolling an arbitrary installation.
grep -Fxq 'VIBEMIS_COMMIT=c3032fc8ee56188a91c1f5a3a8aeae6cf36fb6de' /usr/local/libexec/moonlight-os/frontends/versions.conf
grep -Fxq 'VIBEMIS_PATCH_SHA256=c7b47a846f7c449b225a811d2a89fc3e98c5f4a0fe40945a27560456bf16cbbf' /usr/local/libexec/moonlight-os/frontends/versions.conf
openssl pkey -pubin -in "$KEY_FILE" -text -noout | grep -Fq ED25519
install -d -m 0755 /etc/eclipseos-update /usr/local/libexec/eclipseos
install -d -m 0700 /var/lib/eclipseos-updates
if [[ -f /etc/eclipseos-update/public.pem ]]; then
  cmp /etc/eclipseos-update/public.pem "$KEY_FILE"
fi
install -m 0644 "$KEY_FILE" /etc/eclipseos-update/public.pem
install -m 0644 "$ROOT/updates/base.json" /etc/eclipseos-update/base.json
install -m 0755 "$ROOT/scripts/eclipseos-update.py" /usr/local/libexec/moonlight-os/eclipseos-update.py
install -m 0644 "$ROOT/updates/eclipseos-update-recovery.service" /etc/systemd/system/eclipseos-update-recovery.service
if [[ ! -f /var/lib/eclipseos-updates/original-launcher ]]; then
  install -m 0700 /usr/local/bin/moonlight-launch /var/lib/eclipseos-updates/original-launcher
fi
install -m 0755 "$ROOT/scripts/frontend-launch.sh" /usr/local/bin/moonlight-launch
install -m 0755 "$ROOT/scripts/update-menu.sh" /usr/local/bin/eclipseos-updates
systemctl daemon-reload
systemctl enable eclipseos-update-recovery.service
/usr/local/libexec/moonlight-os/eclipseos-update.py status
