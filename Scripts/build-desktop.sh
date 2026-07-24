#!/bin/bash
# =============================================================================
# Meilink Tauri 桌面客户端构建脚本。
#
# 构建跨平台原生 GUI 客户端（Tauri v2 + Go sidecar + Web 前端）：
#   1. Go 交叉编译 sidecar 二进制（按 target-triple 命名）
#   2. npm install + vite build（前端）
#   3. npx tauri build（Rust 编译 + 打包 .app/.dmg/.msi/.deb）
#
# 用法:
#   bash Scripts/build-desktop.sh              # 构建当前平台
#   bash Scripts/build-desktop.sh --copy       # 构建并复制 DMG 到 release/
#
# 注意：Tauri 无法在同一主机上交叉编译所有平台。
#   macOS 主机 → 只能构建 macOS (.dmg/.app)
#   Linux 主机 → 只能构建 Linux (.deb/.AppImage)
#   Windows 主机 → 只能构建 Windows (.msi)
#   多平台发布请在对应平台的 CI runner 上执行。
# =============================================================================
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT_DIR/cross-platform-client"
DESKTOP_DIR="$CLIENT_DIR/desktop"
COPY_TO_RELEASE=false

[ "$1" = "--copy" ] && COPY_TO_RELEASE=true

# --- 确定 Go sidecar 的 target-triple 后缀 ---
GOOS="$(go env GOOS)"
GOARCH="$(go env GOARCH)"
case "$GOOS-$GOARCH" in
    darwin-arm64) TRIPLE="aarch64-apple-darwin" ;;
    darwin-amd64) TRIPLE="x86_64-apple-darwin" ;;
    linux-amd64)  TRIPLE="x86_64-unknown-linux-gnu" ;;
    linux-arm64)  TRIPLE="aarch64-unknown-linux-gnu" ;;
    windows-amd64) TRIPLE="x86_64-pc-windows-msvc" ;;
    *) echo "Unsupported platform: $GOOS-$GOARCH"; exit 1 ;;
esac

echo "=== Meilink Tauri Desktop Build ==="
echo "Platform: $GOOS/$GOARCH (target-triple: $TRIPLE)"
echo ""

# --- 1. Build Go sidecar binary ---
echo ">>> Building Go sidecar..."
cd "$CLIENT_DIR"
mkdir -p "$DESKTOP_DIR/src-tauri/binaries"
SIDECAR_NAME="meilink-${TRIPLE}"
[ "$GOOS" = "windows" ] && SIDECAR_NAME="${SIDECAR_NAME}.exe"
CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" \
    go build -ldflags "-s -w" -o "$DESKTOP_DIR/src-tauri/binaries/$SIDECAR_NAME" .
echo "  ✓ sidecar: $SIDECAR_NAME"
echo ""

# --- 2. npm install + frontend build ---
echo ">>> Building frontend..."
cd "$DESKTOP_DIR"
[ -d node_modules ] || npm install
npx vite build
echo ""

# --- 3. Tauri build (Rust compile + bundle) ---
echo ">>> Building Tauri app (this may take a few minutes)..."
npx tauri build
echo ""

# --- 4. Copy artifacts to release/ if requested ---
if [ "$COPY_TO_RELEASE" = true ]; then
    echo ">>> Copying artifacts to release/..."
    VERSION="1.1.0"
    BUNDLE_DIR="$DESKTOP_DIR/src-tauri/target/release/bundle"
    mkdir -p "$ROOT_DIR/release"

    # macOS
    if [ -d "$BUNDLE_DIR/dmg" ]; then
        for dmg in "$BUNDLE_DIR/dmg/"*.dmg; do
            [ -f "$dmg" ] || continue
            base="$(basename "$dmg")"
            # Rename to meilink-desktop-{version}-{platform}.dmg
            out="$ROOT_DIR/release/meilink-desktop-${VERSION}-$GOOS-$GOARCH.dmg"
            cp "$dmg" "$out"
            echo "  ✓ $out"
        done
    fi

    # Windows
    if [ -d "$BUNDLE_DIR/msi" ]; then
        for msi in "$BUNDLE_DIR/msi/"*.msi; do
            [ -f "$msi" ] || continue
            cp "$msi" "$ROOT_DIR/release/"
            echo "  ✓ release/$(basename "$msi")"
        done
    fi

    # Linux
    if [ -d "$BUNDLE_DIR/deb" ]; then
        for deb in "$BUNDLE_DIR/deb/"*.deb; do
            [ -f "$deb" ] || continue
            cp "$deb" "$ROOT_DIR/release/"
            echo "  ✓ release/$(basename "$deb")"
        done
    fi
    if [ -d "$BUNDLE_DIR/appimage" ]; then
        for appimage in "$BUNDLE_DIR/appimage/"*.AppImage; do
            [ -f "$appimage" ] || continue
            cp "$appimage" "$ROOT_DIR/release/"
            echo "  ✓ release/$(basename "$appimage")"
        done
    fi
fi

echo ""
echo "=== Done ==="
echo "Bundles at: $DESKTOP_DIR/src-tauri/target/release/bundle/"
