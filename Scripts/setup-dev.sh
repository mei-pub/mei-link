#!/bin/bash
set -e

echo "=== Meilink 开发环境设置 ==="

# 检查 Swift
if ! command -v swift &> /dev/null; then
    echo "错误: 未找到 Swift，请安装 Xcode"
    exit 1
fi

echo "Swift 版本: $(swift --version)"

# 下载 frpc
echo ""
echo "正在下载 frpc..."
bash Scripts/download-frpc.sh

# 构建项目
echo ""
echo "正在构建项目..."
swift build

echo ""
echo "=== 设置完成 ==="
echo ""
echo "下一步:"
echo "1. 使用 xcodegen 生成 Xcode 项目: xcodegen generate"
echo "2. 或直接在 Xcode 中打开 Package.swift"
echo "3. 首次运行需要配置 VPS 服务器信息"
