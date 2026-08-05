# Swift-to-Tauri Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Tauri cross-platform client reproduce the Swift macOS client behavior, visual structure, data compatibility, and lifecycle using `Meilink/` Swift source as the reference.

**Architecture:** Treat Swift files under `Meilink/` as the source of truth. Keep the Go sidecar responsible for shared config, frpc lifecycle, tunnel CRUD, and status polling; keep Tauri responsible for tray, windows, popover geometry, and HTML/CSS views.

**Tech Stack:** Swift source reference, Go sidecar, Tauri v2 Rust shell, Vite static frontend.

## Global Constraints

- Swift reference app is `Meilink/`, as configured by `project.yml`; do not use `/Applications/Meilink.app` as reference.
- macOS shared data directory is `~/Library/Application Support/Meilink`.
- Server config file is `config.json`; tunnel file is `tunnels.json`; settings file is `settings.json`.
- Native main window is `1060x820`; settings is `760x460`; setup is `560x640`; tunnel edit is `660x440`; logs is `820x620`; popover is `330x440`.
- Native app is menu-bar-first and must not show in Dock on macOS.
- Tests or measurable runtime checks must back each claimed alignment.

---

### Task 1: Rust Window and Popover Shell Alignment

**Files:**
- Modify: `cross-platform-client/desktop/src-tauri/src/lib.rs`
- Modify: `cross-platform-client/desktop/src-tauri/tauri.conf.json`

**Interfaces:**
- Produces: window specs matching Swift `AppWindowController`.
- Produces: popover placement matching Swift `StatusBarController.showPanel`.

- [ ] Add/adjust Rust unit tests for Swift window specs and popover `8px` vertical gap.
- [ ] Run `cargo test` and verify the new tests fail before production edits.
- [ ] Update Tauri window specs and config dimensions to match Swift.
- [ ] Update popover position helper to place the popover below tray with Swift gap semantics where possible.
- [ ] Run `cargo test` and verify pass.

### Task 2: Frontend Visual Structure Alignment

**Files:**
- Modify: `cross-platform-client/desktop/src/main.html`
- Modify: `cross-platform-client/desktop/src/popover.html`
- Modify: `cross-platform-client/desktop/src/settings.html`
- Modify: `cross-platform-client/desktop/src/tunnel-edit.html`
- Modify: `cross-platform-client/desktop/src/styles/app.css`

**Interfaces:**
- Consumes: existing `api`, `routeText`, `STATUS_LABELS`, and Tauri `open_window`.
- Produces: Swift-like header, status card, tunnel rows, footer, popover chrome, settings form, and tunnel form density.

- [ ] Add low-risk DOM/CSS checks where practical through build-time or Rust/Playwright visual verification.
- [ ] Rework popover HTML/CSS to include Swift arrow chrome, `330x440` outer frame, 14px body padding, 12px arrow, 16px content radius.
- [ ] Tighten settings and tunnel-edit layouts to fit Swift window heights.
- [ ] Keep main window columns and footer aligned with Swift `MainWindow` and `TunnelListRow`.
- [ ] Run `npm run build`.

### Task 3: Go Sidecar Lifecycle and Data Compatibility

**Files:**
- Modify: `cross-platform-client/internal/config/config.go`
- Modify: `cross-platform-client/internal/config/config_test.go`
- Modify: `cross-platform-client/internal/tunnel/manager.go`
- Modify: `cross-platform-client/internal/tunnel/manager_test.go`
- Modify: `cross-platform-client/internal/web/server.go`

**Interfaces:**
- Produces: Swift-compatible read/write for `config.json`, `tunnels.json`, `settings.json`.
- Produces: startup behavior equivalent to Swift `startIfNeeded() -> restart()`.

- [ ] Add failing tests for Swift `tunnels.json` status field persistence and server-config save starting behavior through API/manager boundary.
- [ ] Run focused Go tests and verify failures.
- [ ] Ensure runtime-only status does not pollute Swift `status` persistence unless intentionally compatible.
- [ ] Ensure save configuration path starts/restarts like Swift setup/settings flows where frontend requests it.
- [ ] Run `GOCACHE=/tmp/meilink-go-cache go test ./...`.

### Task 4: Installed-App Verification

**Files:**
- Generated: `cross-platform-client/desktop/src-tauri/target/release/bundle/macos/Meilink.app`
- Installed: `/Applications/Meilink Cross-Platform.app`

**Interfaces:**
- Consumes: final built Tauri app and shared Swift-compatible config directory.
- Produces: measured evidence for data, UI shell, Dock, startup, CRUD, and cleanup.

- [ ] Build sidecar with `GOCACHE=/tmp/meilink-go-cache go build -o desktop/src-tauri/binaries/meilink-aarch64-apple-darwin .`.
- [ ] Run `npm run tauri build`.
- [ ] Install to `/Applications/Meilink Cross-Platform.app`.
- [ ] Launch the installed app directly from its executable path.
- [ ] Verify sidecar API status, shared config/tunnel loading, Dock absence, window geometry, popover geometry where measurable, tunnel create/delete, and no config residue.
