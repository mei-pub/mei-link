# Meilink v1.1.0 Release Notes

## 版本信息

- **版本号**: 1.1.0
- **发布日期**: 2026-07-28
- **frp 版本**: v0.70.0

## 产物清单

| 产物 | 平台 | 说明 |
|---|---|---|
| `meilink-1.1.0-macOS-native.dmg` | macOS 13+ (arm64) | Swift 原生客户端（菜单栏常驻，特色版本） |
| `meilink-desktop-1.1.0-darwin-arm64.dmg` | macOS 13+ (arm64) | **跨平台 Tauri 桌面客户端（推荐）** |
| `meilink-desktop-1.1.0-windows-amd64.msi` | Windows 10+ | Tauri 桌面客户端 |
| `meilink-desktop-1.1.0-linux-amd64.deb` | Linux amd64 | Tauri 桌面客户端 |
| `meilink-desktop-1.1.0-linux-amd64.AppImage` | Linux amd64 | Tauri 桌面客户端（免安装） |
| `meilink-setup-1.1.0-linux-amd64.tar.gz` | Linux amd64 | 服务端部署工具 |
| `meilink-setup-1.1.0-linux-arm64.tar.gz` | Linux arm64 | 服务端部署工具 |

## macOS 安装说明（重要）

### 跨平台桌面客户端（`meilink-desktop-1.1.0-darwin-arm64.dmg`）

DMG 里的 .app 已做 **ad-hoc 签名**（`codesign --sign -`），但未经过 Apple Developer ID notarization。首次打开时 macOS 会提示「无法验证开发者」或「未识别开发者」——这是正常现象，不是"已损坏"。

**打开方法（任选其一）：**

1. **右键 → 打开**：在 Finder 里右键点击 `Meilink.app`，选「打开」，弹窗点「打开」即可。
2. **系统设置 → 隐私与安全性**：双击 .app 提示无法打开后，去「系统设置 → 隐私与安全性」，滚动到底部会看到「已阻止打开 Meilink」，点「仍要打开」。
3. **命令行清除 quarantine**（彻底）：
   ```bash
   sudo xattr -cr /Applications/Meilink.app
   ```

> 如果提示「已损坏，无法打开」，运行 `sudo xattr -cr /Applications/Meilink.app` 清除 quarantine 属性即可。

### Swift 原生客户端（`meilink-1.1.0-macOS-native.dmg`）

同样 ad-hoc 签名，打开方法同上。

## v1.1.0 变更摘要

### 跨平台 Tauri 桌面客户端（新增）

- ✅ 原生 GUI 窗口（Tauri v2 + Rust 壳 + Web 前端 + Go sidecar）
- ✅ 功能与 macOS 原生客户端对齐：隧道 CRUD、状态轮询、自动重连、远程探活、事件日志
- ✅ 三平台支持：macOS (.dmg) / Windows (.msi) / Linux (.deb + .AppImage)
- ✅ 菜单栏图标 + popover 面板
- ✅ 与 Swift 原生客户端共享 `~/Library/Application Support/Meilink` 配置目录

### Swift 原生客户端修复

- 🔴 修复 `Tunnel` 解码：跨平台 Go sidecar 写 tunnels.json 时不持久化运行期字段（status/errorMessage/remoteAddr），Swift Codable 默认合成解码因 `status` 缺失整个解码失败 → 主界面列表空。加自定义 `init(from decoder:)` 容错解码。
- 🔴 修复 `swift build` 预存语法错误（SettingsView.swift 多余 `}`、FrpcProcess.swift 嵌套 if 缺 `}`）。
- 🔴 修复 `TunnelManager` 并发闭包引用 `self?` 的并发安全错误（Swift 5.10 release 模式）。

### 构建系统

- ✅ `build-all.sh` 改为只构建 GUI 客户端 + 服务端工具（移除 Go CLI + Web UI 产物）
- ✅ `build-desktop.sh` 三平台安装器格式：macOS .dmg / Windows .msi / Linux .deb + .AppImage
- ✅ macOS .app ad-hoc 签名，避免 Gatekeeper "已损坏" 错误
- ✅ GitHub Actions CI 三平台并行构建 + 自动发布 Release

### SDD 软件设计文档 + Agent 规则体系

- ✅ 8 个 SDD 文档（docs/sdd/00-07）
- ✅ 7 个 Agent 规则文档（docs/agent-rules/）
- ✅ 根目录 AGENTS.md 入口 + 上下文管理规则
