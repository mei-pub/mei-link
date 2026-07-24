#!/bin/bash
# =============================================================================
# Meilink unified release build script.
#
# Produces ALL release artifacts into ./release/:
#   1. Cross-platform Go client:
#      - Linux/Darwin: tar.gz with meilink + README
#      - Windows:      SINGLE meilink.exe with embedded icon
#   2. Server setup tool: linux amd64 + arm64 (tar.gz)
#   3. macOS native Swift app: DMG containing Meilink.app + Applications link
# =============================================================================
set -e

VERSION="${1:-1.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT_DIR/cross-platform-client"
RELEASE_DIR="$ROOT_DIR/release"
STAGE_DIR="$RELEASE_DIR/.staging"

mkdir -p "$RELEASE_DIR" "$STAGE_DIR"
rm -rf "${STAGE_DIR:?}"/*
echo "=== Meilink release build v$VERSION ==="
echo "Root:    $ROOT_DIR"
echo "Release: $RELEASE_DIR"
echo ""

# -----------------------------------------------------------------------------
# 0. Generate Windows icon resources (ICO -> resource_windows_amd64.syso).
#    The .syso lives next to the Go sources and is auto-linked for GOOS=windows.
# -----------------------------------------------------------------------------
echo ">>> Generating icon resources..."
cd "$ROOT_DIR"
if [ "$(uname)" = "Darwin" ]; then
    bash Scripts/gen-icons.sh || echo "  ! icon generation failed (Windows exe will have no icon)"
else
    echo "  ! icon generation requires macOS (sips); skipping. Windows exe will have no icon."
fi
echo ""

# -----------------------------------------------------------------------------
# 1. Cross-platform Go client
# -----------------------------------------------------------------------------
echo ">>> Building cross-platform Go client..."
cd "$CLIENT_DIR"

# Windows icon resources: keep .syso in the tree during the windows build,
# then remove it so it never gets committed.
WINDOWS_SYSO="$CLIENT_DIR/resource_windows_amd64.syso"
cleanup_icons() {
    rm -f "$WINDOWS_SYSO" "$CLIENT_DIR/app.ico" "$CLIENT_DIR/meilink.png"
}
trap cleanup_icons EXIT

# make_macos_app: 把 Go 编译的 meilink 二进制包装成标准 .app bundle。
#   $1 = meilink 二进制路径
#   $2 = 输出 .app 路径
# bundle 结构：
#   Meilink.app/Contents/Info.plist
#   Meilink.app/Contents/MacOS/Meilink        (启动脚本：启动 frpc + 打开浏览器)
#   Meilink.app/Contents/MacOS/meilink-bin    (真正的 Go 二进制)
#   Meilink.app/Contents/Resources/AppIcon.icns
make_macos_app() {
    local bin="$1" appdir="$2"
    local contents="$appdir/Contents"
    rm -rf "$appdir"
    mkdir -p "$contents/MacOS" "$contents/Resources"

    # 主可执行文件：启动脚本（双击 .app 时执行）
    cp "$CLIENT_DIR/assets/meilink-launcher-macos.sh" "$contents/MacOS/Meilink"
    chmod +x "$contents/MacOS/Meilink"
    # 真正的 Go 二进制
    cp "$bin" "$contents/MacOS/meilink-bin"
    chmod +x "$contents/MacOS/meilink-bin"
    # 图标
    cp "$ROOT_DIR/Meilink/Resources/AppIcon.icns" "$contents/Resources/AppIcon.icns"
    # Info.plist
    cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Meilink</string>
    <key>CFBundleDisplayName</key><string>Meilink</string>
    <key>CFBundleExecutable</key><string>Meilink</string>
    <key>CFBundleIdentifier</key><string>vip.rego.meilink.go</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
}

# make_dmg: 从一个 .app bundle 生成标准 DMG（含 Applications 快捷方式）。
#   $1 = .app 路径，$2 = 输出 .dmg 路径，$3 = 卷标名（可选，默认 Meilink）
make_dmg() {
    local app_path="$1" dmg_path="$2" volname="${3:-Meilink}"
    local staging="$STAGE_DIR/dmg-staging-$$"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp -R "$app_path" "$staging/"
    ln -s /Applications "$staging/Applications"
    rm -f "$dmg_path"
    hdiutil create -volname "$volname" -srcfolder "$staging" \
        -ov -fs HFS+ -format UDZO "$dmg_path" >/dev/null 2>&1
    rm -rf "$staging"
}

build_client() {
    local goos="$1" goarch="$2" outname="$3" ext="$4"
    echo "  - $goos/$goarch -> $outname"
    local stagedir="$STAGE_DIR/$outname"
    rm -rf "$stagedir"
    mkdir -p "$stagedir"

    local archive="$RELEASE_DIR/meilink-${VERSION}-${goos}-${goarch}${ext}"

    if [ "$goos" = "windows" ]; then
        # Single exe with embedded icon. The .syso (if generated) is
        # auto-linked by go build because it sits in the package directory.
        # Keep the default console subsystem (no -H windowsgui) so that CLI
        # subcommands (status/stop/setup) print output to the user's console.
        CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
            go build -ldflags "-s -w" -o "$stagedir/meilink.exe" .
        # Archive as a flat zip containing just meilink.exe.
        ( cd "$stagedir" && zip -qj "$archive" meilink.exe )
    elif [ "$goos" = "darwin" ]; then
        # macOS: 打包成标准 .app bundle + DMG（含 Applications 快捷方式），
        # 与原生客户端一致的拖拽安装体验。
        CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
            go build -ldflags "-s -w" -o "$stagedir/meilink" .
        chmod +x "$stagedir/meilink"
        local dmg="$RELEASE_DIR/meilink-${VERSION}-darwin-${goarch}.dmg"
        make_macos_app "$stagedir/meilink" "$stagedir/Meilink.app"
        make_dmg "$stagedir/Meilink.app" "$dmg"
    else
        # Linux: tar.gz（含桌面集成：图标、.desktop、安装脚本）
        CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
            go build -ldflags "-s -w" -o "$stagedir/meilink" .
        chmod +x "$stagedir/meilink"
        cp "$CLIENT_DIR/assets/USER_README.md" "$stagedir/README.md"
        if [ -f "$CLIENT_DIR/meilink.png" ]; then
            cp "$CLIENT_DIR/meilink.png" "$stagedir/meilink.png"
        fi
        cp "$CLIENT_DIR/assets/meilink.desktop" "$stagedir/meilink.desktop"
        cp "$CLIENT_DIR/assets/meilink-webui" "$stagedir/meilink-webui"
        cp "$CLIENT_DIR/assets/install-linux.sh" "$stagedir/install.sh"
        chmod +x "$stagedir/meilink-webui" "$stagedir/install.sh"
        tar -czf "$archive" -C "$STAGE_DIR" "$outname"
    fi
    rm -rf "$stagedir"
    echo "    -> $(basename "$archive")"
}

build_client linux   amd64 "meilink-${VERSION}-linux-amd64"   ".tar.gz"
build_client linux   arm64 "meilink-${VERSION}-linux-arm64"   ".tar.gz"
build_client darwin  amd64 "meilink-${VERSION}-darwin-amd64"  ".dmg"
build_client darwin  arm64 "meilink-${VERSION}-darwin-arm64"  ".dmg"
build_client windows amd64 "meilink-${VERSION}-windows-amd64" ".zip"
echo ""

# -----------------------------------------------------------------------------
# 2. Server setup tool (Linux only: amd64 + arm64)
# -----------------------------------------------------------------------------
echo ">>> Building server setup tool (Linux)..."
build_setup() {
    local goarch="$1"
    local outname="meilink-setup-${VERSION}-linux-${goarch}"
    echo "  - linux/$goarch -> $outname"
    local stagedir="$STAGE_DIR/$outname"
    rm -rf "$stagedir"
    mkdir -p "$stagedir"
    CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" \
        go build -ldflags "-s -w" -o "$stagedir/meilink-setup" ./cmd/meilink-setup
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
    tar -czf "$RELEASE_DIR/${outname}.tar.gz" -C "$STAGE_DIR" "$outname"
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
NATIVE_DMG="$RELEASE_DIR/meilink-${VERSION}-macOS-native.dmg"

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
if [ ! -f "$NATIVE_DMG" ]; then
    PREBUILT_APP="$ROOT_DIR/build/Meilink.app"
    if [ -d "$PREBUILT_APP" ]; then
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
cleanup_icons
rm -rf "$STAGE_DIR"

echo "=== Done. Release artifacts: ==="
ls -lh "$RELEASE_DIR"/meilink-*"$VERSION"* "$RELEASE_DIR"/*.dmg 2>/dev/null | sort -k 9 | awk '{print $9, $5}'
echo ""
echo "产物说明:"
echo "  *macOS-native.dmg   macOS 原生客户端 (Swift .app bundle + 图标)"
echo "  *darwin-*.dmg       macOS Go 跨平台客户端 (.app bundle + 图标)"
echo "  *windows*.zip       Windows 单 exe (嵌入图标)"
echo "  *linux*.tar.gz      Linux 跨平台客户端 (含桌面集成：图标/.desktop/install.sh)"
echo "  *setup*.tar.gz      服务端管理程序"
