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

VERSION="${1:-1.1.0}"
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
if bash "$ROOT_DIR/scripts/build/build-desktop.sh" --copy >/dev/null 2>&1; then
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
NATIVE_DMG="$RELEASE_DIR/meilink-${VERSION}-macos-native.dmg"

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

# Fallback: package the pre-built .app bundle (build/Meilink.app) if the fresh
# build was skipped or failed. This bundle already contains the icon + frpc.
# When Xcode isn't available, rebuild the Swift binary via SwiftPM and inject
# it into the pre-built .app so the DMG carries the latest Swift code.
if [ ! -f "$NATIVE_DMG" ]; then
    PREBUILT_APP="$ROOT_DIR/build/Meilink.app"
    if [ -d "$PREBUILT_APP" ]; then
        echo "  - rebuilding Swift binary via SwiftPM..."
        if swift build -c release >/dev/null 2>&1; then
            # Use --show-bin-path to find the release binary (SwiftPM puts it
            # under .build/<arch>-apple-macosx/release on newer toolchains).
            SWIFT_BIN_DIR="$(swift build -c release --show-bin-path 2>/dev/null)"
            if [ -f "$SWIFT_BIN_DIR/Meilink" ]; then
                cp "$SWIFT_BIN_DIR/Meilink" "$PREBUILT_APP/Contents/MacOS/Meilink"
                echo "  ✓ Swift binary rebuilt and injected"
            else
                echo "  ! Swift binary not found at $SWIFT_BIN_DIR; using existing binary"
            fi
        else
            echo "  ! swift build failed; using existing binary in pre-built bundle"
        fi
        echo "  - packaging pre-built $PREBUILT_APP into DMG..."
        # Bump the version in the prebuilt plist so it matches this release.
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
            "$PREBUILT_APP/Contents/Info.plist" 2>/dev/null || true
        make_dmg "$PREBUILT_APP" "$NATIVE_DMG"
        echo "  ✓ $(basename "$NATIVE_DMG") (pre-built bundle)"
    else
        echo "  ! No Meilink.app available (need Xcode or a pre-built bundle); skipping DMG."
    fi
fi
echo ""

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
rm -rf "$STAGE_DIR"

echo "=== Done. Release artifacts: ==="
ls -lh "$RELEASE_DIR"/meilink-*"$VERSION"* "$RELEASE_DIR"/*.dmg 2>/dev/null | sort -k 9 | awk '{print $9, $5}'
echo ""
echo "产物说明:"
echo "  *macos-native.dmg        macOS 原生客户端 (Swift .app bundle + 图标)"
echo "  *desktop-*darwin*.dmg    跨平台 Tauri 桌面客户端 (原生 GUI，与 Swift 端对齐)"
echo "  *setup*.tar.gz           服务端部署工具 (Linux)"
