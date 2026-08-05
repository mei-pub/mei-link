# Meilink 文档

本目录是 Meilink 的全部文档，按类型分组。

## 目录结构

```
docs/
├── sdd/        # 软件设计文档（SDD）—— 架构与契约的权威来源
├── rules/      # Agent 专题规则 —— 修改某类代码时的必读清单
├── guides/     # 操作手册 —— 部署、运维等面向操作的指南
└── archive/    # 历史归档 —— 已完成的对齐计划与设计稿（保留参考，不再维护）
```

## sdd/（软件设计文档，8 个文件）

| 文件 | 内容 |
|---|---|
| [00-overview.md](sdd/00-overview.md) | 项目定位、技术栈、目录结构、运行时入口、SDD 索引 |
| [01-requirements.md](sdd/01-requirements.md) | 用户需求、用户故事、非目标、典型场景、隐含需求 |
| [02-features.md](sdd/02-features.md) | 功能清单（F1-F10，每条含入口 + 实现位置 + 流程） |
| [03-architecture.md](sdd/03-architecture.md) | 运行时拓扑、启动序列、核心对象职责、状态机、自动恢复、并发模型 |
| [04-ui-design.md](sdd/04-ui-design.md) | 窗口规格、视觉语言、各窗口结构、菜单栏面板、状态文案、图标 |
| [05-data-contract.md](sdd/05-data-contract.md) | 持久化 schema、Keychain、frpc.toml 生成、Admin API 端点、端口契约 |
| [06-constraints.md](sdd/06-constraints.md) | 平台、安全、生命周期、并发、UI 不变量、跨平台兼容约束 |
| [07-build-release.md](sdd/07-build-release.md) | 构建矩阵、产物命名、版本号、CI 提示、发布检查清单 |

## rules/（Agent 专题规则，7 个文件）

每个规则文件结构：何时触发 → 涉及文件 → 必读不变量 → 同步修改清单 → 反例 → 验证步骤。

| 文件 | 何时触发 |
|---|---|
| [modifying-tunnel.md](rules/modifying-tunnel.md) | 修改 `Tunnel` / `TunnelType` / `ProxyDefinition` 结构或新增代理类型 |
| [modifying-status-polling.md](rules/modifying-status-polling.md) | 修改状态轮询 / 自动重连 / 探活 / 阈值 / frpc 退出回调 |
| [modifying-frpc-process.md](rules/modifying-frpc-process.md) | 修改 frpc 进程管理 / 二进制查找 / 停止策略 / 退出强杀 |
| [modifying-ui.md](rules/modifying-ui.md) | 修改任何 SwiftUI 视图 / 窗口尺寸 / 状态色 / 状态文案 / 生命周期行为 |
| [adding-menubar-icon.md](rules/adding-menubar-icon.md) | 新增第 6 种菜单栏图标风格 |
| [cross-platform-compat.md](rules/cross-platform-compat.md) | 修改跨平台客户端或涉及跨端共享契约 |
| [build-release.md](rules/build-release.md) | 构建、发布、改版本号、改图标、改构建脚本 |

## guides/（操作手册）

| 文件 | 内容 |
|---|---|
| [deploy-docker.md](guides/deploy-docker.md) | 服务端 Docker 部署完整手册（裸 frps + 一体镜像 + Nginx 反代 + TLS） |

## archive/（历史归档）

已完成的对齐实施计划与设计稿。**保留参考，不再维护**，路径引用可能已过时。

- `2026-07-24-cross-platform-native-alignment.md` — 跨平台原生对齐实施计划
- `2026-07-24-swift-to-tauri-alignment.md` — Swift 到 Tauri 对齐实施计划
- `2026-07-24-cross-platform-native-alignment-design.md` — 跨平台原生对齐设计
- `2026-08-02-docker-web-client-design.md` — Docker Web 客户端设计

---

## 入口推荐

- **Agent**（AI）：从 [`../AGENTS.md`](../AGENTS.md) 开始，它索引了本目录全部内容
- **新人**：先读 [sdd/00-overview.md](sdd/00-overview.md)
- **部署服务端**：读 [guides/deploy-docker.md](guides/deploy-docker.md)
- **改代码前**：查 [rules/](rules/) 是否有对应专题规则
