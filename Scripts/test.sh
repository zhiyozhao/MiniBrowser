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
set +e
swift test "$@"
STATUS=$?
set -e
AFTER=$(snapshot)
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
