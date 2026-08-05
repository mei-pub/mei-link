# Cross-Platform Native Alignment Design

**Goal:** bring the Tauri/Go cross-platform client as close as practical to the accepted macOS native client for behavior, visual hierarchy, interaction, and data interoperability.

## Acceptance Scope

- macOS cross-platform desktop must share `~/Library/Application Support/Meilink` with the native Swift client.
- Existing native `config.json`, `tunnels.json`, and `settings.json` must load in the cross-platform UI.
- Cross-platform edits must remain readable by the native client.
- Sidecar startup must be discoverable by Tauri windows and must respect `settings.autoStart`.
- Enabled tunnels must restore on launch; tunnel create/update/delete/toggle must work through frpc Store API.
- macOS shell behavior must be menu-bar first: no Dock icon, tray icon style from settings, popover aligned to the tray icon and hidden on focus loss.
- Web UI screens should match the native app's information architecture, copy, icon intent, and state model, with minor Web/Tauri rendering differences accepted.

## Architecture

The Go service remains the source of truth for persistence, frpc config generation, frpc process control, Store API calls, and HTTP API. The Tauri shell owns macOS desktop behavior: sidecar process launch, API discovery, tray icon, Dock policy, popover placement, and WebView windows. The Web UI consumes only the local HTTP API plus small Tauri commands.

## Verification

Use a real macOS Tauri run to verify sidecar discovery, data loading, startup connection, tunnel operations, tray/popover behavior, and Dock absence. Keep automated coverage for stable compatibility rules in Go and Rust, then finish with `go test ./...`, `npm run build`, and `cargo test`.
