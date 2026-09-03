#!/bin/bash
# =============================================================================
# Meilink unified release build script.
#
# Produces ALL release artifacts into ./release/:
#   1. Tauri cross-platform desktop GUI client:
#      - macOS: meilink-desktop-<version>-darwin-arm64.dmg (native .app bundle)
#      (Linux/Windows Tauri targets are built separately when cross-compilers
#       are configured; see scripts/build-desktop.sh)
#   2. Server setup tool: linux amd64 + arm64 (tar.gz)
#   3. macOS native Swift app: DMG containing Meilink.app + Applications link
# =============================================================================
set -e

# shellcheck source=../lib/version.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/version.sh"
VERSION="$(resolve_app_version "$1")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_DIR="$ROOT_DIR/client/desktop"
SERVER_SETUP_DIR="$ROOT_DIR/server/setup"
RELEASE_DIR="$ROOT_DIR/release"
RELEASE_SERVER_DIR="$RELEASE_DIR/server"
RELEASE_NATIVE_DIR="$RELEASE_DIR/client/macos-native"
STAGE_DIR="$RELEASE_DIR/.staging"

mkdir -p "$RELEASE_SERVER_DIR" "$RELEASE_NATIVE_DIR" "$STAGE_DIR"
rm -rf "${STAGE_DIR:?}"/*
echo "=== Meilink release build v$VERSION ==="
echo "Root:    $ROOT_DIR"
echo "Release: $RELEASE_DIR"
echo ""

# -----------------------------------------------------------------------------
# 1. Tauri cross-platform desktop GUI client
# -----------------------------------------------------------------------------
echo ">>> Building Tauri desktop client..."
cd "$DESKTOP_DIR"

# build-desktop.sh --copy builds frontend + Go sidecar + Rust shell and copies
# the platform-native installer (.dmg / .msi / .deb / .AppImage) to release/.
# Run this script on each target platform (or use the GitHub Actions matrix in
# .github/workflows/release.yml) to get all three platforms.
if bash "$ROOT_DIR/scripts/build/build-desktop.sh" --copy "$VERSION" >/dev/null 2>&1; then
    echo "  ✓ Tauri app built"
else
    echo "  ! Tauri build failed (see scripts/build/build-desktop.sh output)"
fi
echo ""

# make_dmg: used by the Swift native fallback below to package build/Meilink.app.
# Every macOS DMG includes a one-click fix script for Gatekeeper "damaged /
# can't be opened" errors — double-clicking the .command clears quarantine
# via `sudo xattr -cr`.
make_dmg() {
    local app_path="$1" dmg_path="$2" volname="${3:-Meilink}"
    local staging="$STAGE_DIR/dmg-staging-$"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp -R "$app_path" "$staging/"
    ln -s /Applications "$staging/Applications"
    # One-click fix for Gatekeeper "damaged" error. Filename is Chinese so
    # users immediately know what it does.
    cat > "$staging/修复签名-打不开点我.command" <<'COMMAND_EOF'
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
    chmod +x "$staging/修复签名-打不开点我.command"
    rm -f "$dmg_path"
    hdiutil create -volname "$volname" -srcfolder "$staging" \
        -ov -fs HFS+ -format UDZO "$dmg_path" >/dev/null 2>&1
    rm -rf "$staging"
}

# -----------------------------------------------------------------------------
# 2. Server setup tool (Linux only: amd64 + arm64)
# -----------------------------------------------------------------------------
echo ">>> Building server setup tool (Linux)..."
cd "$SERVER_SETUP_DIR"
build_setup() {
    local goarch="$1"
    local outname="meilink-setup-${VERSION}-linux-${goarch}"
    echo "  - linux/$goarch -> $outname"
    local stagedir="$STAGE_DIR/$outname"
    rm -rf "$stagedir"
    mkdir -p "$stagedir"
    CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" \
        go build -ldflags "-s -w" -o "$stagedir/meilink-setup" .
    cat > "$stagedir/README.txt" <<EOF
Meilink frps Server Setup v${VERSION}

Run with sudo:
    sudo ./meilink-setup            # interactive menu
    sudo ./meilink-setup setup      # first-time init
    sudo ./meilink-setup add        # add a domain+token profile
    sudo ./meilink-setup list
    sudo ./meilink-setup start|stop|restart|status [name]
    sudo ./meilink-setup upgrade

Each profile = one domain + one token + one isolated frps systemd service
(frps-<name>.service), auto-enabled and auto-restarted on boot.
EOF
    tar -czf "$RELEASE_SERVER_DIR/${outname}.tar.gz" -C "$STAGE_DIR" "$outname"
    rm -rf "$stagedir"
    echo "    -> ${outname}.tar.gz"
}

build_setup amd64
build_setup arm64
echo ""

# -----------------------------------------------------------------------------
# 3. macOS native Swift app -> DMG
# -----------------------------------------------------------------------------
echo ">>> Building macOS native app DMG..."
cd "$ROOT_DIR"
NATIVE_DMG="$RELEASE_NATIVE_DIR/meilink-${VERSION}-macos-native.dmg"

# Prefer building a fresh .app via Xcode if the full app is available.
xcodebuild_available() {
    if ! command -v xcodebuild >/dev/null 2>&1; then return 1; fi
    xcodebuild -version >/dev/null 2>&1
}

if xcodebuild_available; then
    if command -v xcodegen >/dev/null 2>&1; then
        rm -rf "$ROOT_DIR/Meilink.xcodeproj"
        echo "  - generating Xcode project..."
        xcodegen generate >/dev/null 2>&1 || echo "  ! xcodegen failed"
    fi
    if [ -d "$ROOT_DIR/Meilink.xcodeproj" ]; then
        echo "  - building Release configuration..."
        NATIVE_BUILD="$ROOT_DIR/build/native"
        rm -rf "$NATIVE_BUILD"
        if xcodebuild -project "$ROOT_DIR/Meilink.xcodeproj" \
                      -scheme Meilink -configuration Release \
                      -derivedDataPath "$NATIVE_BUILD" \
                      -destination 'generic/platform=macOS' \
                      build >/dev/null 2>&1; then
            APP_PATH="$(find "$NATIVE_BUILD" -name 'Meilink.app' -type d | head -1)"
            if [ -n "$APP_PATH" ]; then
                # Developer ID 签名（有证书时）。先签 meilink-tunnel（公证要求所有可执行
                # 是 Developer ID 签名 + 时间戳 + hardened runtime）；本机安全代理
                # 可能拦截新二进制写入，失败不阻塞。
                CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')"
                if [ -n "$CODESIGN_IDENTITY" ]; then
                    ENGINE_BIN="$APP_PATH/Contents/MacOS/meilink-tunnel"
                    if [ -f "$ENGINE_BIN" ]; then
                        codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$ENGINE_BIN" 2>/dev/null \
                            || echo "  ! meilink-tunnel signing failed (notarization may reject; continuing)"
                    fi
                    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH" && echo "  ✓ signed: $CODESIGN_IDENTITY"
                fi
                make_dmg "$APP_PATH" "$NATIVE_DMG"
                echo "  ✓ $(basename "$NATIVE_DMG") (fresh build)"
            else
                echo "  ! Meilink.app not found after build"
            fi
        else
            echo "  ! xcodebuild failed"
        fi
    fi
fi

# Fallback: build .app bundle from Swift binary + generated Info.plist
if [ ! -f "$NATIVE_DMG" ]; then
    echo "  - building .app bundle from Swift binary..."
    if swift build -c release >/dev/null 2>&1; then
        SWIFT_BIN_DIR="$(swift build -c release --show-bin-path 2>/dev/null)"
        if [ -f "$SWIFT_BIN_DIR/Meilink" ]; then
            APP_BUNDLE="$ROOT_DIR/build/Meilink.app"
            rm -rf "$APP_BUNDLE"
            mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
            cp "$SWIFT_BIN_DIR/Meilink" "$APP_BUNDLE/Contents/MacOS/Meilink"
            # Build meilink-tunnel into the bundle (replaces the old frpc download).
            if BUILT_PRODUCTS_DIR="$APP_BUNDLE/Contents" \
               bash "$ROOT_DIR/scripts/build/build-engine.sh" >/dev/null 2>&1; then
                :
            fi
            # Copy icons if available
            if [ -f "$ROOT_DIR/client/macos-native/Resources/AppIcon.icns" ]; then
                cp "$ROOT_DIR/client/macos-native/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
            fi
            # Generate Info.plist
            # NSAppTransportSecurity.NSAllowsArbitraryLoads=true is REQUIRED:
            # managementURL is typically http://host:port (plain HTTP). macOS ATS
            # blocks plain HTTP by default, which silently breaks /api/domains
            # fetch in TunnelEditView (shows "改为手动填写" with an ATS error).
            /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Meilink" \
              -c "Add :CFBundleIdentifier string pub.mei.meilink" \
              -c "Add :CFBundleName string Meilink" \
              -c "Add :CFBundleDisplayName string Meilink" \
              -c "Add :CFBundleVersion string 1.0" \
              -c "Add :CFBundleShortVersionString string $VERSION" \
              -c "Add :CFBundlePackageType string APPL" \
              -c "Add :LSMinimumSystemVersion string 13.0" \
              -c "Add :LSUIElement bool true" \
              -c "Add :NSAppTransportSecurity dict" \
              -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" \
              -c "Add :CFBundleIconFile string AppIcon" \
              "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
            # Developer ID 签名（有证书时）；先签 meilink-tunnel（公证要求），本机拦截则跳过
            CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')"
            if [ -n "$CODESIGN_IDENTITY" ]; then
                ENGINE_BIN="$APP_BUNDLE/Contents/MacOS/meilink-tunnel"
                if [ -f "$ENGINE_BIN" ]; then
                    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$ENGINE_BIN" 2>/dev/null \
                        || echo "  ! meilink-tunnel signing failed (notarization may reject; continuing)"
                fi
                codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
                echo "  ✓ signed: $CODESIGN_IDENTITY"
            fi
            echo "  ✓ .app bundle built from Swift binary"
            make_dmg "$APP_BUNDLE" "$NATIVE_DMG"
            echo "  ✓ $(basename "$NATIVE_DMG") (from Swift binary)"
        else
            echo "  ! Swift binary not found at $SWIFT_BIN_DIR; skipping DMG."
        fi
    else
        echo "  ! swift build failed; skipping DMG."
    fi
fi
echo ""

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
rm -rf "$STAGE_DIR"

echo "=== Done. Release artifacts: ==="
find "$RELEASE_NATIVE_DIR" "$ROOT_DIR/release/client/desktop" "$RELEASE_SERVER_DIR" \
    -type f -not -name '.gitkeep' 2>/dev/null \
    | sort | while read -r f; do
    size=$(ls -lh "$f" | awk '{print $5}')
    echo "  $f  ($size)"
done
echo ""
echo "产物说明:"
echo "  client/macos-native/    macOS 原生客户端 (Swift .app bundle + 图标)"
echo "  client/desktop/         跨平台 Tauri 桌面客户端 (原生 GUI，与 Swift 端对齐)"
echo "  server/                 服务端部署工具 (Linux)"
