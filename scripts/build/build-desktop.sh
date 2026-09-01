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
#   bash scripts/build-desktop.sh              # 构建当前平台
#   bash scripts/build-desktop.sh --copy       # 构建并复制产物到 release/
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

# shellcheck source=../lib/version.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/version.sh"

# 应用版本号：优先 VERSION 环境变量 > --copy 后的位置参数 > git tag（上次发布）> 0.0.0
# 解析逻辑见 scripts/lib/version.sh。build-desktop.sh 把版本号传给 Tauri（产物文件名）
# 和 release/ 复制命名。--copy 模式下版本号在第二个位置参数。
if [ "${1:-}" = "--copy" ]; then
    APP_VERSION="$(resolve_app_version "${2:-}")"
else
    APP_VERSION="$(resolve_app_version "${1:-}")"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIDECAR_DIR="$ROOT_DIR/client/desktop/sidecar"
DESKTOP_DIR="$ROOT_DIR/client/desktop"
COPY_TO_RELEASE=false

source "$ROOT_DIR/scripts/lib/frpc-archive.sh"

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
cd "$SIDECAR_DIR"
mkdir -p "$DESKTOP_DIR/src-tauri/binaries"
SIDECAR_NAME="meilink-${TRIPLE}"
[ "$GOOS" = "windows" ] && SIDECAR_NAME="${SIDECAR_NAME}.exe"
CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" \
    go build -ldflags "-s -w" -o "$DESKTOP_DIR/src-tauri/binaries/$SIDECAR_NAME" .
echo "  ✓ sidecar: $SIDECAR_NAME"
echo ""

# --- 1a. Download the matching frpc binary as a bundled application resource ---
# The desktop app passes this file to the Go sidecar explicitly via
# MEILINK_FRPC_BIN. It must be present in the installer so first-run setup
# and saving settings do not depend on an internet connection.
FRP_VERSION="${FRP_VERSION:-v0.70.0}"
FRPC_RESOURCE_DIR="$DESKTOP_DIR/src-tauri/resources"
FRPC_RESOURCE="$FRPC_RESOURCE_DIR/frpc.exe"
FRPC_ARCHIVE_EXT=".tar.gz"
[ "$GOOS" = "windows" ] && FRPC_ARCHIVE_EXT=".zip"
FRPC_ARCHIVE="frp_${FRP_VERSION#v}_${GOOS}_${GOARCH}${FRPC_ARCHIVE_EXT}"
FRPC_URL="https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRPC_ARCHIVE}"
FRPC_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$FRPC_TMP_DIR"' EXIT

echo ">>> Downloading bundled frpc ${FRP_VERSION}..."
mkdir -p "$FRPC_RESOURCE_DIR"
curl --fail --location --retry 3 "$FRPC_URL" -o "$FRPC_TMP_DIR/$FRPC_ARCHIVE"
if [ "$GOOS" = "windows" ]; then
    unzip -p "$FRPC_TMP_DIR/$FRPC_ARCHIVE" "*/frpc.exe" > "$FRPC_RESOURCE"
else
    extract_tar_member "$FRPC_TMP_DIR/$FRPC_ARCHIVE" "frpc" > "$FRPC_RESOURCE"
fi
chmod +x "$FRPC_RESOURCE"
echo "  frpc resource: $FRPC_RESOURCE"
echo ""

# --- 2. npm install + frontend build ---
echo ">>> Building frontend..."
cd "$DESKTOP_DIR"
[ -d node_modules ] || npm install
npx vite build
echo ""

# --- 3. Tauri build (Rust compile + bundle) ---
echo ">>> Building Tauri app (this may take a few minutes)..."
# On macOS, build the .app bundle only (no .dmg yet) so we can ad-hoc sign the
# .app before wrapping it into a DMG. Tauri's default `tauri build` produces a
# DMG from the unsigned .app and then cleans up the .app, leaving no chance to
# inject a signature. `--bundles app` is macOS-only; on Windows/Linux we run
# the default `tauri build` to produce the platform's installer format
# (.msi/.nsis on Windows, .deb/.AppImage on Linux) directly.
if [ "$GOOS" = "darwin" ]; then
    npx tauri build --bundles app
else
    npx tauri build
fi
echo ""

# --- 3a. macOS: ad-hoc sign the .app to avoid Gatekeeper "damaged" error ---
# Without code signing, macOS marks unsigned .app bundles downloaded from the
# internet as "damaged and can't be opened" (com.apple.quarantine + no signature).
# Ad-hoc signing (--sign -) doesn't give a Developer ID identity, but it makes
# the bundle structurally valid so Gatekeeper shows "unidentified developer"
# instead of "damaged" — users can then right-click → Open, or go to
# System Settings → Privacy & Security → "Open Anyway".
if [ "$GOOS" = "darwin" ]; then
    APP_PATH="$DESKTOP_DIR/src-tauri/target/release/bundle/macos/Meilink.app"
    if [ ! -d "$APP_PATH" ]; then
        APP_PATH="$DESKTOP_DIR/src-tauri/target/release/Meilink.app"
    fi
    if [ -d "$APP_PATH" ]; then
        # 有 Developer ID 证书时做正式签名；无证书保持 ad-hoc。
        # frpc.exe 保持系统 linker-signed（macOS 15+），不单独重签。
        CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')"
        if [ -n "$CODESIGN_IDENTITY" ]; then
            echo ">>> Signing $APP_PATH with $CODESIGN_IDENTITY ..."
            codesign --force --options runtime --sign "$CODESIGN_IDENTITY" "$APP_PATH" 2>&1 | tail -2
            if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
                echo "  ✓ Developer ID signed"
            else
                echo "  ! signature verification failed (continuing anyway)"
            fi
        else
            echo ">>> Ad-hoc signing $APP_PATH ..."
            codesign --force --deep --sign - "$APP_PATH" 2>&1 | tail -3
            if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
                echo "  ✓ ad-hoc signed"
            else
                echo "  ! ad-hoc signing verification failed (continuing anyway)"
            fi
        fi
        # 公证（可选）：有 NOTARIZATION_APPLE_ID/PASSWORD 时对签名后的 .app
        # 做 notarytool 公证 + staple，Gatekeeper 才不会拦首次打开。
        if [ -n "${NOTARIZATION_APPLE_ID:-}" ] && [ -n "${NOTARIZATION_APPLE_PASSWORD:-}" ]; then
            echo ">>> Notarizing $APP_PATH ..."
            ZIP="/tmp/meilink-notarize-$$.zip"
            ditto -c -k --keepParent "$APP_PATH" "$ZIP"
            xcrun notarytool submit "$ZIP" \
                --apple-id "$NOTARIZATION_APPLE_ID" \
                --password "$NOTARIZATION_APPLE_PASSWORD" \
                --team-id "${NOTARIZATION_TEAM_ID:-8KV7MAV54M}" \
                --wait
            xcrun stapler staple "$APP_PATH"
            rm -f "$ZIP"
            echo "  ✓ notarized + stapled"
        fi
        # Build the DMG ourselves from the signed .app.
        # 文件名用 APP_VERSION（不再写死 1.1.0），跟随 git tag 或传入的版本号。
        SIGNED_DMG="$DESKTOP_DIR/src-tauri/target/release/bundle/dmg/Meilink_${APP_VERSION}_aarch64.dmg"
        mkdir -p "$(dirname "$SIGNED_DMG")"
        STAGE="/tmp/meilink-dmg-stage-$"
        rm -rf "$STAGE" && mkdir -p "$STAGE"
        cp -R "$APP_PATH" "$STAGE/"
        ln -s /Applications "$STAGE/Applications"
        # Add a one-click fix script for the Gatekeeper "damaged / can't be
        # opened" error. Ad-hoc signing + quarantine still makes macOS block
        # the app on first launch; users can double-click this .command to run
        # `sudo xattr -cr` and clear the quarantine attribute. The filename is
        # intentionally Chinese so users immediately know what it does.
        cat > "$STAGE/修复签名-打不开点我.command" <<'COMMAND_EOF'
#!/bin/bash
# Meilink 签名修复脚本
# 解决「已损坏，无法打开」或「无法验证开发者」错误
# 双击此文件运行，输入开机密码即可

set -e
echo "============================================"
echo "  Meilink 签名修复工具"
echo "============================================"
echo ""
echo "此脚本会清除 Meilink.app 的 quarantine 属性，"
echo "解决 macOS 提示「已损坏，无法打开」的问题。"
echo ""

APP_PATH="/Applications/Meilink.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 未找到 $APP_PATH"
    echo "请先拖动 Meilink.app 到 Applications 文件夹安装。"
    echo ""
    read -p "按回车键退出..."
    exit 1
fi

echo "即将执行: sudo xattr -cr /Applications/Meilink.app"
echo "（需要输入开机密码，输入时不会显示字符，输完按回车）"
echo ""
sudo xattr -cr "$APP_PATH"
echo ""
echo "✅ 修复完成！现在可以打开 Meilink 了。"
echo ""
read -p "按回车键退出..."
COMMAND_EOF
        chmod +x "$STAGE/修复签名-打不开点我.command"
        rm -f "$SIGNED_DMG"
        hdiutil create -volname "Meilink Desktop" -srcfolder "$STAGE" \
            -ov -fs HFS+ -format UDZO "$SIGNED_DMG" >/dev/null 2>&1
        rm -rf "$STAGE"
        echo "  ✓ DMG built from signed .app: $(basename "$SIGNED_DMG")"
    else
        echo "  ! Meilink.app not found for ad-hoc signing"
    fi
fi
echo ""

# --- 4. Copy artifacts to release/ if requested ---
if [ "$COPY_TO_RELEASE" = true ]; then
    echo ">>> Copying artifacts to release/client/desktop/..."
    # APP_VERSION 已在脚本开头解析（环境变量 > 位置参数 > git tag）
    BUNDLE_DIR="$DESKTOP_DIR/src-tauri/target/release/bundle"
    RELEASE_DESKTOP_DIR="$ROOT_DIR/release/client/desktop"
    mkdir -p "$RELEASE_DESKTOP_DIR"

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
            out="$RELEASE_DESKTOP_DIR/meilink-desktop-${APP_VERSION}-${GOOS}-${GOARCH}${ext}"
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
