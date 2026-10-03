#!/usr/bin/env bash
# Focused Qt tests only; no OS image build and no live host credentials.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/SOURCES.lock"
TASK=$(mktemp -d)
trap 'rm -rf "$TASK"' EXIT
if [[ -n ${VIBEMIS_TEST_SOURCE:-} ]]; then
  SRC=$VIBEMIS_TEST_SOURCE
else
  git clone --no-checkout "$VIBEMIS_REPO" "$TASK/source"
  SRC=$TASK/source
  git -C "$SRC" checkout --detach "$VIBEMIS_COMMIT"
  git -C "$SRC" apply "$ROOT/patches/vibemis-crimson.patch"
fi
# The production resource bundle embeds this pinned controller database.
# Fetch only that submodule; the focused Qt tests need no streaming libraries.
git -C "$SRC" submodule update --init --depth 1 app/SDL_GameControllerDB
export VIBEMIS_TEST_SOURCE=$SRC
export HOME=$TASK/home
mkdir -p "$HOME"
export CRIMSON_TEST_CERT=$TASK/cert.pem CRIMSON_TEST_KEY=$TASK/key.pem
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost -keyout "$CRIMSON_TEST_KEY" -out "$CRIMSON_TEST_CERT" 2>/dev/null
mkdir "$TASK/build"
cd "$TASK/build"
qmake6 "$SRC/app/moonlightos/tests/test-crimson.pro"
make -j2
QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a ./test-crimson

# Compile/run the exact patched overlay identity and buffer-budget contracts.
# Keep this inside the required native audit, rather than relying on an older binary.
mkdir "$TASK/decoderstatus"
cd "$TASK/decoderstatus"
qmake6 "$SRC/tests/overlay/decoderstatus.pro"
make -j2
./tst_decoderstatus
