#!/usr/bin/env bash
# Runs the integration test on an Android device/emulator, granting the
# notification permission as soon as the test app is installed.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-}"
ADB="${ADB:-adb}"
PKG=com.ttechapp.live_updates_example
# A launch that never reports the Dart VM service hangs flutter test
# forever, so each attempt gets ATTEMPT_SECONDS and there are three tries.
ATTEMPT_SECONDS="${ATTEMPT_SECONDS:-600}"
grant() {
  for _ in $(seq 1 600); do
    if $ADB ${DEVICE:+-s "$DEVICE"} shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
}
for attempt in 1 2 3; do
  grant &
  GRANTER=$!
  status=0
  perl -e 'alarm shift; exec @ARGV' "$ATTEMPT_SECONDS" \
    flutter test integration_test ${DEVICE:+-d "$DEVICE"} || status=$?
  kill "$GRANTER" 2>/dev/null || true
  [ "$status" -eq 0 ] && exit 0
  # Only a hang (killed by the alarm: 142) is retried; a failure is reported.
  [ "$status" -ne 142 ] && exit "$status"
  echo "Attempt $attempt timed out; retrying."
  $ADB ${DEVICE:+-s "$DEVICE"} uninstall "$PKG" >/dev/null 2>&1 || true
done
exit 1
