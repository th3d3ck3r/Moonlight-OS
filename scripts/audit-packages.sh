#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KS="$ROOT/config/moonlight-os.ks"

if (( EUID != 0 )); then
  echo "audit-packages.sh must run as root in the disposable Fedora audit container" >&2
  exit 2
fi

dnf -y install pykickstart dnf5-plugins ca-certificates curl

dnf -y install   https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm   https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm

ksvalidator "$KS"

mapfile -t packages < <(
  awk '
    /^%packages/ { inpkgs=1; next }
    inpkgs && /^%end$/ { exit }
    inpkgs && NF && $1 !~ /^@/ && $1 !~ /^-/ { print $1 }
  ' "$KS"
)

missing=0
for pkg in "${packages[@]}"; do
  if ! dnf -q repoquery "$pkg" 2>/dev/null | grep -q .; then
    echo "MISSING PACKAGE: $pkg" >&2
    missing=1
  fi
done

if (( missing != 0 )); then
  exit 1
fi

echo "Fedora 44 Kickstart/package audit passed for ${#packages[@]} explicit packages."
