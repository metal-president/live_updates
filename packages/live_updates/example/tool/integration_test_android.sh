#!/usr/bin/env bash
# Runs the integration test on an Android device/emulator, granting the
# notification permission as soon as the test app is installed.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-}"
ADB="${ADB:-adb}"
PKG=com.ttechapp.live_updates_example
(
  for _ in $(seq 1 600); do
    if $ADB ${DEVICE:+-s "$DEVICE"} shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null; then
      exit 0
    fi
    sleep 0.5
  done
) &
GRANTER=$!
trap 'kill $GRANTER 2>/dev/null || true' EXIT
flutter test integration_test ${DEVICE:+-d "$DEVICE"}
