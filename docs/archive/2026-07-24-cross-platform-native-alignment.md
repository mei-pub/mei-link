# Cross-Platform Native Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** complete macOS-native alignment for the Tauri/Go cross-platform client while preserving Windows/Linux portability.

**Architecture:** Go owns persistent config, frpc lifecycle, Store API operations, and local HTTP API. Tauri owns desktop shell behavior, sidecar discovery, tray, popover placement, and WebView windows. Web UI remains API-driven and shares status/copy conventions with the native Swift client.

**Tech Stack:** Go, frpc Store API, Tauri 2, Rust, Vite, HTML/CSS/ES modules.

## Global Constraints

- Do not modify accepted Swift native behavior unless a cross-platform interoperability bug requires a shared contract change.
- Do not discard existing user data in `~/Library/Application Support/Meilink`.
- Preserve Windows/Linux defaults under `~/.meilink`.
- Prefer small compatibility tests for persistent schema, sidecar paths, and popover geometry.

---

### Task 1: Real-Run Baseline

**Files:**
- Inspect: `cross-platform-client/desktop/src-tauri/src/lib.rs`
- Inspect: `cross-platform-client/internal/config/config.go`
- Inspect: `cross-platform-client/internal/tunnel/manager.go`
- Inspect: `cross-platform-client/desktop/src/*.html`

**Interfaces:**
- Consumes: existing native data under `~/Library/Application Support/Meilink`
- Produces: a checklist of concrete failing behaviors to fix

- [ ] Build and run the desktop app with `npm run tauri dev`.
- [ ] Confirm sidecar port discovery through `sidecar.port`.
- [ ] Query `/api/status`, `/api/server-config`, `/api/tunnels`, and `/api/settings`.
- [ ] Capture visible UI screenshots for main window and popover.
- [ ] Check whether Dock icon appears on macOS.

### Task 2: Persistence And Lifecycle Compatibility

**Files:**
- Modify: `cross-platform-client/internal/config/config.go`
- Modify: `cross-platform-client/internal/tunnel/manager.go`
- Modify: `cross-platform-client/cmd/meilink/main.go`
- Test: `cross-platform-client/internal/config/config_test.go`

**Interfaces:**
- Consumes: Swift camelCase JSON and Swift enum status strings
- Produces: Go API models compatible with both native and cross-platform clients

- [ ] Add or adjust failing tests for native data path, `showInDock`, `menuBarIconStyle`, and Swift status names.
- [ ] Implement the smallest compatibility changes.
- [ ] Run `go test ./...`.
- [ ] Real-run the desktop app and verify existing native tunnels appear.

### Task 3: macOS Shell Alignment

**Files:**
- Modify: `cross-platform-client/desktop/src-tauri/src/lib.rs`
- Modify: `cross-platform-client/desktop/src-tauri/tauri.conf.json`
- Test: `cross-platform-client/desktop/src-tauri/src/lib.rs`

**Interfaces:**
- Consumes: Tauri tray click `rect`, app settings from sidecar API
- Produces: Dock-free menu-bar app with correctly positioned popover

- [ ] Add or adjust Rust tests for macOS data path and popover centering math.
- [ ] Set macOS activation policy to accessory.
- [ ] Use tray event geometry for popover placement on macOS.
- [ ] Real-run and visually verify Dock absence and popover alignment.
- [ ] Run `cargo test`.

### Task 4: Visual And Interaction Alignment

**Files:**
- Modify: `cross-platform-client/desktop/src/main.html`
- Modify: `cross-platform-client/desktop/src/popover.html`
- Modify: `cross-platform-client/desktop/src/settings.html`
- Modify: `cross-platform-client/desktop/src/tunnel-edit.html`
- Modify: `cross-platform-client/desktop/src/styles/app.css`
- Modify: `cross-platform-client/desktop/src/public/icons/app-icon.png`

**Interfaces:**
- Consumes: existing native app layout and icon/copy conventions
- Produces: cross-platform screens that match native information hierarchy and state copy

- [ ] Compare main, popover, settings, edit, and logs screens against native Swift UI.
- [ ] Fix logo, button copy, status labels, empty states, and spacing where materially different.
- [ ] Use browser/WebView screenshots to catch overflow or awkward alignment.
- [ ] Run `npm run build`.

### Task 5: End-To-End Verification

**Files:**
- Inspect: `~/Library/Application Support/Meilink/config.json`
- Inspect: `~/Library/Application Support/Meilink/tunnels.json`
- Inspect: `~/Library/Application Support/Meilink/settings.json`
- Inspect: `~/Library/Application Support/Meilink/frpc.log`

**Interfaces:**
- Consumes: a configured Meilink server and local test tunnel
- Produces: a final verification report with remaining accepted platform differences

- [ ] Launch cross-platform desktop.
- [ ] Confirm configured server and existing tunnels load.
- [ ] Confirm auto-start behavior matches settings.
- [ ] Create a test tunnel, verify it is persisted, then delete it.
- [ ] Toggle an existing disabled tunnel only if it is safe to do so; otherwise verify the API path with a temporary tunnel.
- [ ] Run `go test ./...`, `npm run build`, and `cargo test`.
