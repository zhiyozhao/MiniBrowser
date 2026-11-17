#!/bin/bash
# 截取 README / 官网用的 MiniBrowser 窗口原图（Retina 2x）。
#
# - 只启动仓库内 MiniBrowser.app 的独立副本：独立 defaults suite + 数据目录。
# - 只按窗口 ID 截图，不截屏幕区域，也不接触其他 app 的窗口。
# - 页面是本地起的示例页 Scripts/demo/page.html。
# - 真实偏好 com.zhao.minibrowser.plist 前后比较 SHA-256，结束时清理副本和 suite。
#
# 依赖：peekaboo（需要辅助功能和屏幕录制权限）、python3。
# 输出：.local/demo/raw/<light|dark>-<zh|en>-<宽度>.png
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK="$ROOT/.local/demo"
RAW="$WORK/raw"
APP="$ROOT/MiniBrowser.app/Contents/MacOS/MiniBrowser"
PLIST="$HOME/Library/Preferences/com.zhao.minibrowser.plist"
SUITE=MiniBrowser.Demo
PORT=${DEMO_PORT:-8765}
FAKE_URL="tide.example"
# 宽度（pt）:高度（pt）
SIZES=("320:500" "420:420" "300:420" "228:420")

[[ -x "$APP" ]] || { echo "error: 先运行 Scripts/build-app.sh" >&2; exit 1; }
HASH_BEFORE=$(shasum -a 256 "$PLIST" | awk '{print $1}')
COPY_PID="" SERVER_PID=""

cleanup() {
    [[ -n "$COPY_PID" ]] && kill "$COPY_PID" 2>/dev/null || true
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
    wait 2>/dev/null || true
    defaults delete "$SUITE" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$SUITE.plist"
    rm -rf "$WORK/data" "$WORK/site"
    local after
    after=$(shasum -a 256 "$PLIST" | awk '{print $1}')
    if [[ "$HASH_BEFORE" != "$after" ]]; then
        echo "error: $PLIST 在截图期间发生了变化" >&2
        exit 1
    fi
    echo "plist sha256 unchanged: $after"
}
trap cleanup EXIT INT TERM

mkdir -p "$WORK/site" "$RAW"
cp "$ROOT/Scripts/demo/page.html" "$WORK/site/"
swiftc -O "$ROOT/Scripts/demo/windows.swift" -o "$WORK/windows" 2>/dev/null
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/site" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!

snapshot() { peekaboo see --mode window --window-id "$WID" --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["snapshot_id"])'; }
address_field() {
    peekaboo see --mode window --window-id "$WID" --json | python3 -c '
import json, sys
d = json.load(sys.stdin)["data"]
def walk(n):
    if isinstance(n, dict):
        yield n
        for v in n.values(): yield from walk(v)
    elif isinstance(n, list):
        for i in n: yield from walk(i)
field = next(e for e in walk(d) if e.get("role") == "textField" and e.get("id"))
print(d["snapshot_id"], field["id"])'
}

for theme in light dark; do
  for lang in zh en; do
    # 每种组合都重新启动副本：新窗口的地址栏自带焦点，可以直接输入
    args=(-defaultsSuite "$SUITE" -dataDirectory "$WORK/data")
    if [[ "$theme" == light ]]; then
        args+=(-NSRequiresAquaSystemAppearance YES)
    else
        args+=(-AppleInterfaceStyle Dark)
    fi
    "$APP" "${args[@]}" >"$WORK/copy.log" 2>&1 &
    COPY_PID=$!
    sleep 3
    WID=$("$WORK/windows" "$COPY_PID" | awk 'NR==1{print $1}')
    [[ -n "$WID" ]] || { echo "error: 副本窗口未出现" >&2; exit 1; }

    peekaboo type "http://127.0.0.1:$PORT/page.html?lang=$lang" --snapshot "$(snapshot)" --clear >/dev/null
    peekaboo press Return --pid "$COPY_PID" --window-id "$WID" >/dev/null
    sleep 2
    grep -q "GET /page.html?lang=$lang" "$WORK/server.log" || { echo "error: 示例页未加载" >&2; exit 1; }
    for size in "${SIZES[@]}"; do
        w=${size%%:*} h=${size##*:}
        peekaboo window set-bounds --pid "$COPY_PID" --window-id "$WID" \
            --x 700 --y 160 --width "$w" --height "$h" >/dev/null
        sleep 1
        # 只聚焦副本自己的窗口；地址栏显示示例域名，再按 Tab 把焦点移到网页，去掉地址栏光标
        peekaboo window focus --pid "$COPY_PID" --window-id "$WID" >/dev/null
        read -r snap field < <(address_field)
        peekaboo set-value "$FAKE_URL" --on "$field" --snapshot "$snap" >/dev/null
        peekaboo press Tab --pid "$COPY_PID" --window-id "$WID" >/dev/null 2>&1 || true
        sleep 0.6
        peekaboo see --mode window --window-id "$WID" --retina --no-elements \
            --path "$RAW/$theme-$lang-$w.png" --json >/dev/null
        echo "captured $theme-$lang-$w.png"
    done
    kill "$COPY_PID"; wait "$COPY_PID" 2>/dev/null || true; COPY_PID=""
    defaults delete "$SUITE" >/dev/null 2>&1 || true
    rm -rf "$WORK/data"
    sleep 1
  done
done
