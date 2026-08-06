#!/usr/bin/env bash

# Meilink 应用版本号解析（共享逻辑）。
#
# 优先级（从高到低）：
#   1. 显式环境变量 VERSION（如 VERSION=1.2.0 bash build-all.sh）
#   2. 位置参数（如 bash build-all.sh 1.2.0）
#   3. git 最近的 v* tag（如 v1.1.0 → 1.1.0），代表「上次发布的版本」
#   4. 兜底 0.0.0（仅当不在 git 仓库 / 无 tag 时，避免空值）
#
# 用法（在构建脚本里）：
#   source "$(dirname "$0")/../lib/version.sh"
#   VERSION="$(resolve_app_version "$@")"
#
# 注：本函数只处理「应用版本号」（如 1.1.0），与 frp 版本（v0.70.0）无关。
# git tag 用 --sort=-v:refname 做语义版本排序，避免 legacy tag（0.0.3 等）
# 因字典序排在 v* tag 前面而误选。只认 v 开头的 tag。

# 从 git 读最近的应用版本号（去掉 v 前缀）。无 tag 时返回空。
_last_version_from_git() {
    local tag
    tag="$(git tag --list 'v*' --sort=-v:refname 2>/dev/null | head -1)"
    if [ -n "$tag" ]; then
        echo "${tag#v}"
    fi
}

# 解析应用版本号。参数 $1 是调用方传入的位置参数（可为空）。
# 优先 VERSION 环境变量 > $1 位置参数 > git tag > 0.0.0。
resolve_app_version() {
    local positional="${1:-}"
    if [ -n "${VERSION:-}" ]; then
        echo "$VERSION"
    elif [ -n "$positional" ]; then
        echo "$positional"
    else
        local last
        last="$(_last_version_from_git)"
        echo "${last:-0.0.0}"
    fi
}
