import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const [api, main, editor, rust] = await Promise.all([
  readFile(new URL("../src/lib/api.js", import.meta.url), "utf8"),
  readFile(new URL("../src/main.html", import.meta.url), "utf8"),
  readFile(new URL("../src/tunnel-edit.html", import.meta.url), "utf8"),
  readFile(new URL("../src-tauri/src/lib.rs", import.meta.url), "utf8"),
]);

assert.match(api, /openWindow\(name, \{ tunnelId = null \} = \{\}\)/, "openWindow must accept the tunnel ID explicitly");
assert.match(main, /openWindow\("tunnel-edit", \{ tunnelId: id \}\)/, "the edit action must pass its tunnel ID to the new window");
assert.doesNotMatch(main, /sessionStorage\.setItem\("editTunnelId"/, "sessionStorage is isolated per Tauri webview and cannot pass edit state");
assert.doesNotMatch(editor, /sessionStorage\.getItem\("editTunnelId"/, "the edit window must not read another webview's sessionStorage");
assert.match(editor, /takeTunnelEditId\(\)/, "the edit window must read the pending ID from the Tauri process");
assert.match(rust, /fn open_window\(\s*app: AppHandle,\s*name: String,\s*tunnel_id: Option<String>,\s*state: State<TunnelEditState>,/s, "Rust must receive the edit ID");
assert.match(rust, /fn take_tunnel_edit_id/, "Rust must expose the pending edit ID to the edit window");

console.log("tunnel-edit-window-state: edit context is transferred through the Tauri process");
