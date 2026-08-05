#!/bin/bash
# =============================================================================
# Meilink 图标资源生成脚本。
#
# 从 Meilink/Resources/AppIcon.png (1254×1254) 派生各平台图标资源：
#   - Windows: app.ico → resource_windows_amd64.syso (go build 自动链接，嵌入 exe)
#   - macOS:   AppIcon.icns 直接复用 Meilink/Resources/AppIcon.icns (已存在)
#
# 仅依赖 macOS 系统自带工具: sips (裁剪 PNG) + python3 (拼装 ICO) + rsrc。
# 输出到 $OUT_DIR (默认 cross-platform-client/)，供 build-all.sh 调用。
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_PNG="${SRC_PNG:-$ROOT_DIR/Meilink/Resources/AppIcon.png}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/cross-platform-client}"

if [ ! -f "$SRC_PNG" ]; then
    echo "gen-icons: 源图标不存在: $SRC_PNG" >&2
    exit 1
fi

command -v sips >/dev/null 2>&1 || { echo "gen-icons: 需要 sips (仅 macOS)" >&2; exit 1; }

# rsrc 用于把 .ico 编译成 Windows 资源对象 (.syso)。若未安装则自动 go install。
RSRC="$(go env GOPATH)/bin/rsrc"
if ! command -v "$RSRC" >/dev/null 2>&1; then
    RSRC="$(command -v rsrc || true)"
fi
if [ -z "$RSRC" ] || [ ! -x "$RSRC" ]; then
    echo "gen-icons: 安装 rsrc (Windows 资源编译器)..."
    go install github.com/akavel/rsrc@latest
    RSRC="$(go env GOPATH)/bin/rsrc"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "gen-icons: 源图标 $SRC_PNG"
echo "gen-icons: 生成 Windows ICO..."

# Windows 图标所需的标准尺寸（含 256）。
SIZES=(16 24 32 48 64 128 256)
for sz in "${SIZES[@]}"; do
    sips -z "$sz" "$sz" "$SRC_PNG" --out "$WORK/${sz}.png" >/dev/null 2>&1
done

# 用纯 python3 拼装 ICO（ICONDIR + ICONDIRENTRY + PNG 数据），无需 Pillow。
python3 "$SCRIPT_DIR/_pack_ico.py" "$WORK" "${SIZES[@]}" "$OUT_DIR/app.ico"

echo "gen-icons: 编译 Windows 资源对象 resource_windows_amd64.syso..."
"$RSRC" -ico "$OUT_DIR/app.ico" -arch amd64 -o "$OUT_DIR/resource_windows_amd64.syso"

# Linux 桌面图标（256×256 PNG，供 .desktop 启动器使用）
echo "gen-icons: 生成 Linux 桌面图标..."
cp "$WORK/256.png" "$OUT_DIR/meilink.png"

echo "gen-icons: ✓ 完成"
echo "  - $OUT_DIR/app.ico"
echo "  - $OUT_DIR/meilink.png (Linux 桌面图标 256×256)"
echo "  - $OUT_DIR/resource_windows_amd64.syso (go build GOOS=windows 自动链接)"
