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
(( missing == 0 ))

echo "Package-name lookup passed for ${#packages[@]} explicit packages."

# This is an ephemeral CI container, not an OS image. Install the complete
# package set together to catch solver conflicts and missing dependencies.
dnf -y --setopt=install_weak_deps=False install "${packages[@]}"

# Probe the exact compile-time capabilities selected by the pinned Moonlight tree.
for pc in   openssl   sdl2   SDL2_ttf   libavcodec   libavutil   libswscale   libva   libva-x11   libva-drm   vdpau   libdrm   libplacebo   x11   egl   opus; do
  if ! pkg-config --exists "$pc"; then
    echo "MISSING PKG-CONFIG CAPABILITY: $pc" >&2
    exit 1
  fi
  echo "pkg-config OK: $pc $(pkg-config --modversion "$pc" 2>/dev/null || true)"
done

command -v qmake6 >/dev/null
command -v gcc >/dev/null
command -v g++ >/dev/null
command -v dkms >/dev/null
command -v vainfo >/dev/null
command -v glxinfo >/dev/null
command -v vulkaninfo >/dev/null
command -v intel_gpu_top >/dev/null

echo "Fedora 44 full package transaction and Moonlight build-capability audit passed."
