#!/bin/bash
# Meilink macOS 启动脚本（.app 内 MacOS/Meilink 的入口）
# 启动 frpc 客户端（若未运行），并打开 Web 管理界面。
APP_DIR="$(dirname "$0")"
MEILINK_BIN="$APP_DIR/meilink-bin"
PORT="${MEILINK_PORT:-7400}"
URL="http://localhost:${PORT}"

# 若未运行，则在后台启动
if ! "$MEILINK_BIN" status 2>/dev/null | grep -q "running: true"; then
    nohup "$MEILINK_BIN" start >/dev/null 2>&1 &
    for i in $(seq 1 30); do
        if curl -sf "$URL/api/status" >/dev/null 2>&1; then break; fi
        sleep 0.5
    done
fi

# 打开浏览器
open "$URL"
