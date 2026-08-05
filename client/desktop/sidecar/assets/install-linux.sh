#!/bin/bash
# Meilink Linux 安装脚本：把客户端安装到系统路径，配置桌面集成。
# 用法: sudo ./install.sh    或    ./install.sh (装到 ~/.local)
set -e

SYSTEM_INSTALL=0
[ "$(id -u)" = "0" ] && SYSTEM_INSTALL=1

if [ "$SYSTEM_INSTALL" = "1" ]; then
    BIN_DIR="/usr/local/bin"
    ICON_DIR="/usr/share/icons/hicolor/256x256/apps"
    APPS_DIR="/usr/share/applications"
else
    BIN_DIR="$HOME/.local/bin"
    ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
    APPS_DIR="$HOME/.local/share/applications"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Meilink 安装 ==="
echo "  安装模式: $([ "$SYSTEM_INSTALL" = "1" ] && echo "系统" || echo "用户")"
echo "  二进制:   $BIN_DIR"
echo "  图标:     $ICON_DIR"
echo "  启动器:   $APPS_DIR"
echo ""

mkdir -p "$BIN_DIR" "$ICON_DIR" "$APPS_DIR"

# 安装主程序
install -m 755 "$SCRIPT_DIR/meilink" "$BIN_DIR/meilink"
echo "  ✓ meilink → $BIN_DIR/meilink"

# 安装桌面启动辅助脚本
install -m 755 "$SCRIPT_DIR/meilink-webui" "$BIN_DIR/meilink-webui"
sed -i "s|^MEILINK_BIN=.*|MEILINK_BIN=\"$BIN_DIR/meilink\"|" "$BIN_DIR/meilink-webui" 2>/dev/null || \
    sed -i '' "s|^MEILINK_BIN=.*|MEILINK_BIN=\"$BIN_DIR/meilink\"|" "$BIN_DIR/meilink-webui"
echo "  ✓ meilink-webui → $BIN_DIR/meilink-webui"

# 安装图标
if [ -f "$SCRIPT_DIR/meilink.png" ]; then
    install -m 644 "$SCRIPT_DIR/meilink.png" "$ICON_DIR/meilink.png"
    echo "  ✓ meilink.png → $ICON_DIR/meilink.png"
    [ "$SYSTEM_INSTALL" = "1" ] && gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

# 安装 .desktop 启动器
install -m 644 "$SCRIPT_DIR/meilink.desktop" "$APPS_DIR/meilink.desktop"
echo "  ✓ meilink.desktop → $APPS_DIR/meilink.desktop"

echo ""
echo "=== 安装完成 ==="
echo ""
echo "现在你可以："
echo "  - 在应用菜单中找到 'Meilink'，点击启动（自动打开浏览器）"
echo "  - 命令行运行: meilink setup && meilink start"
echo "  - 注册系统服务: sudo meilink install-service"
echo ""
echo "首次使用请运行 meilink setup 配置服务器信息。"
