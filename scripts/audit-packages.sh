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

# Mirror Anaconda workaround: base Fedora 44 media has broken IGT 2.2.
# Prove the current updates package resolves independently.
dnf -y --refresh install igt-gpu-tools
rpm -q igt-gpu-tools
command -v intel_gpu_top >/dev/null

for codec in sbc aac; do
  test -s /usr/lib64/spa-0.2/bluez5/libspa-codec-bluez5-$codec.so
  echo "Bluetooth codec plugin verified: $codec"
done

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

# qmake configure-only feature probe: no compilation is performed here.
# This proves the pinned source trees actually select the accelerated Linux paths.
# shellcheck disable=SC1091
source "$ROOT/SOURCES.lock"

probe_qmake() {
  local name=$1 repo=$2 commit=$3 mode=$4
  local dir="/tmp/moonlight-os-qmake-$name"
  rm -rf "$dir"
  git clone -q "$repo" "$dir"
  git -C "$dir" checkout -q --detach "$commit"
  git -C "$dir" submodule update -q --init --recursive

  pushd "$dir" >/dev/null
  if [[ "$mode" == "embedded" ]]; then
    qmake6 "CONFIG+=embedded" moonlight-qt.pro > qmake-root.log 2>&1
    (cd app && qmake6 "CONFIG+=embedded" app.pro > ../qmake-app.log 2>&1)
  else
    qmake6 moonlight-qt.pro > qmake-root.log 2>&1
    (cd app && qmake6 app.pro > ../qmake-app.log 2>&1)
  fi

  cat qmake-root.log qmake-app.log > qmake-combined.log

  for msg in     "FFmpeg decoder selected"     "VAAPI renderer selected"     "VAAPI X11 support enabled"     "VAAPI DRM support enabled"     "DRM renderer selected"     "Vulkan support enabled via libplacebo"     "EGL renderer selected"; do
    if ! grep -Fq "$msg" qmake-combined.log; then
      echo "$name qmake did not select required feature: $msg" >&2
      cat qmake-combined.log >&2
      exit 1
    fi
  done

  if [[ "$mode" == "embedded" ]]; then
    grep -Fq "Embedded build" qmake-combined.log || {
      echo "$name qmake did not select EMBEDDED_BUILD" >&2
      cat qmake-combined.log >&2
      exit 1
    }
  fi

  if grep -Fq "VAAPI Wayland support enabled" qmake-combined.log; then
    echo "INFO: $name also detected Wayland support; runtime remains forced to X11."
  fi

  echo "$name qmake configure-only accelerated feature probe passed."
  popd >/dev/null
}

probe_qmake upstream "$MOONLIGHT_REPO" "$MOONLIGHT_COMMIT" normal
probe_qmake cocoos "$COCOOS_REPO" "$COCOOS_COMMIT" embedded

echo "All Fedora 44 package and pinned-source configure audits passed."
