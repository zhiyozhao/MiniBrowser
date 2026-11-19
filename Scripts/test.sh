#!/bin/bash
# 跑完整 Swift 测试，并验证用户真实偏好与测试 suite 均无泄漏。
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="$HOME/Library/Preferences/com.zhao.minibrowser.plist"
SUITE="MiniBrowserTests.$$"
DATA_DIRECTORY="$PWD/.local/test-data"

snapshot() {
    if [ -f "$TARGET" ]; then
        shasum -a 256 "$TARGET" | awk '{print $1}'
    else
        printf 'absent\n'
    fi
}

cleanup() {
    defaults delete "$SUITE" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$SUITE.plist"
    rm -rf "$DATA_DIRECTORY"
}
trap cleanup EXIT INT TERM

BEFORE=$(snapshot)
export MINIBROWSER_DEFAULTS_SUITE="$SUITE"
export MINIBROWSER_DATA_DIRECTORY="$DATA_DIRECTORY"
export MINIBROWSER_NONPERSISTENT=1
/usr/bin/python3 Scripts/test-tls-server-tests.py
set +e
if [ "$#" -gt 0 ]; then
    swift test "$@"
    STATUS=$?
else
    # NSApp window counts and performance must be measured in their own
    # process, without other suites creating windows or doing main-thread work.
    swift test --skip 'PopupTests|TabSwitchPerformanceTests'
    STATUS=$?
    if [ "$STATUS" -eq 0 ]; then
        swift test --skip-build --filter PopupTests
        STATUS=$?
    fi
    if [ "$STATUS" -eq 0 ]; then
        swift test --skip-build --filter TabSwitchPerformanceTests
        STATUS=$?
    fi
fi
set -e
AFTER=$(snapshot)
for attempt in {1..30}; do
    if ! pgrep -f '[M]iniBrowserTests-https' >/dev/null; then break; fi
    sleep 0.1
done
if pgrep -f '[M]iniBrowserTests-https' >/dev/null; then
    echo 'error: HTTPS fixture processes remained after tests' >&2
    exit 1
fi
if [ "$BEFORE" != "$AFTER" ]; then
    echo "error: $TARGET changed during make check" >&2
    exit 1
fi
LEFTOVERS=$(find "$HOME/Library/Preferences" -maxdepth 1 -type f -name 'MiniBrowserCoreTests.*.plist' -print)
if [ -n "$LEFTOVERS" ]; then
    echo "error: test preference files were not cleaned:" >&2
    printf '%s\n' "$LEFTOVERS" >&2
    exit 1
fi
if [ "$STATUS" -ne 0 ]; then
    exit "$STATUS"
fi
printf 'Preferences isolation verified; com.zhao.minibrowser.plist is byte-for-byte unchanged.\n'
