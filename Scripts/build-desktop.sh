#!/bin/bash
# =============================================================================
# Meilink Tauri 桌面客户端构建脚本。
#
# 构建跨平台原生 GUI 客户端（Tauri v2 + Go sidecar + Web 前端）：
#   1. Go 交叉编译 sidecar 二进制（按 target-triple 命名）
#   2. npm install + vite build（前端）
#   3. npx tauri build（Rust 编译 + 打包 .dmg/.msi/.deb/.AppImage）
#
# 用法:
#   bash Scripts/build-desktop.sh              # 构建当前平台
#   bash Scripts/build-desktop.sh --copy       # 构建并复制产物到 release/
#
# 平台产出格式（由 tauri.conf.json bundle.targets 控制）:
#   macOS   → .dmg（拖拽安装）
#   Windows → .msi（NSIS 安装器）
#   Linux   → .deb + .AppImage
#
# 注意：Tauri 无法在同一主机上交叉编译所有平台（Rust 交叉编译需要对应
#   平台的 linker + sysroot）。多平台发布请在对应平台的 CI runner 上执行
#   （见 .github/workflows/release.yml）。
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

    copy_bundle() {
        # $1 = bundle subdir name (dmg/msi/nsis/deb/appimage)
        # $2 = file extension (.dmg/.msi/.deb/.AppImage)
        local kind="$1" ext="$2"
        local dir="$BUNDLE_DIR/$kind"
        [ -d "$dir" ] || return 0
        for f in "$dir/"*"$ext"; do
            [ -f "$f" ] || continue
            local base out
            base="$(basename "$f")"
            out="$ROOT_DIR/release/meilink-desktop-${VERSION}-${GOOS}-${GOARCH}${ext}"
            cp "$f" "$out"
            echo "  ✓ $out"
        done
    }

    # macOS → .dmg
    [ "$GOOS" = "darwin" ] && copy_bundle dmg ".dmg"
    # Windows → .msi (NSIS installer)
    [ "$GOOS" = "windows" ] && copy_bundle msi ".msi"
    [ "$GOOS" = "windows" ] && copy_bundle nsis ".exe"
    # Linux → .deb + .AppImage
    [ "$GOOS" = "linux" ] && copy_bundle deb ".deb"
    [ "$GOOS" = "linux" ] && copy_bundle appimage ".AppImage"
fi

echo ""
echo "=== Done ==="
echo "Bundles at: $DESKTOP_DIR/src-tauri/target/release/bundle/"
