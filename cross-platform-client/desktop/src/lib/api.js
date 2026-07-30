// Meilink desktop shared API client.
// Uses @tauri-apps/api ES module imports (bundled by Vite).
//
// IMPORTANT: We intentionally do NOT use the `isTauri` constant from
// @tauri-apps/api/core. In Tauri v2 + Vite dev mode, that constant is
// evaluated at module load time, which can happen BEFORE Tauri injects
// window.__TAURI_INTERNALS__ into the webview. That makes isTauri === false
// even inside the real Tauri webview, which would route all invoke/listen
// calls through the reject-only fallback and leave the frontend permanently
// unable to reach the sidecar (every onReady() promise hangs forever).
//
// Instead we resolve invoke/listen at CALL TIME by checking for the Tauri
// internals at the moment of the call. This works both in the Tauri webview
// (where window.__TAURI_INTERNALS__ appears once Tauri is ready) and in a
// plain browser (where it stays absent and we cleanly reject).

import { invoke as tauriInvoke } from "@tauri-apps/api/core";
import { listen as tauriListen } from "@tauri-apps/api/event";
export { STATUS_LABELS, normalizeStatus, tunnelStatus, normalizeSubdomain, routeText, canOpen, overallStatus, esc } from "./display.js";

function hasTauriInternals() {
  return typeof window !== "undefined" && (
    "__TAURI_INTERNALS__" in window || "__TAURI__" in window
  );
}

// Resolve the invoke implementation at call time so we pick up Tauri's
// injection even if it happens after this module loads.
function _invoke(cmd, args) {
  if (hasTauriInternals()) {
    try { return tauriInvoke(cmd, args); } catch (e) { return Promise.reject(e); }
  }
  const fallback = window.__TAURI__?.core?.invoke;
  if (typeof fallback === "function") return fallback(cmd, args);
  return Promise.reject(new Error("Tauri API not available"));
}

function _listen(event, handler) {
  if (hasTauriInternals()) {
    try { return tauriListen(event, handler); } catch (e) { return Promise.reject(e); }
  }
  const fallback = window.__TAURI__?.event?.listen;
  if (typeof fallback === "function") return fallback(event, handler);
  return Promise.reject(new Error("Tauri API not available"));
}

let apiBase = "";
let readyCallbacks = [];
let ready = false;

// Try to get the API URL. Polls invoke("get_api_url") every 500ms until the
// sidecar is ready, and also listens for the sidecar-ready event.
async function initApi() {
  // Listen for the sidecar-ready event first (to avoid missing it).
  // It's fine if this rejects (e.g. in a plain browser); we also poll below.
  try {
    await _listen("sidecar-ready", (event) => {
      apiBase = event.payload;
      if (apiBase && !ready) {
        ready = true;
        if (typeof window !== "undefined") {
          window.__MEILINK_API_BASE__ = apiBase;
          window.__MEILINK_API_READY__ = true;
        }
        readyCallbacks.forEach((cb) => cb(apiBase));
      }
    });
  } catch (e) { /* not in tauri context */ }

  // Poll get_api_url until it returns a non-empty value. We retry for up to
  // 60s (120 * 500ms) so late sidecar startup is covered. Also checks
  // window.__MEILINK_API_BASE__ (injected by Rust via webview.eval) as a
  // belt-and-suspenders fallback for when Tauri internals aren't ready.
  for (let i = 0; i < 120; i++) {
    try {
      // Fallback 1: Rust injects this via webview.eval after sidecar ready.
      if (!apiBase && typeof window !== "undefined" && window.__MEILINK_API_BASE__) {
        apiBase = window.__MEILINK_API_BASE__;
      }
      if (!apiBase) {
        apiBase = await _invoke("get_api_url");
      }
      if (apiBase) {
        ready = true;
        if (typeof window !== "undefined") {
          window.__MEILINK_API_BASE__ = apiBase;
          window.__MEILINK_API_READY__ = true;
        }
        readyCallbacks.forEach((cb) => cb(apiBase));
        return;
      }
    } catch (e) {}
    await new Promise((r) => setTimeout(r, 500));
  }
}

initApi();

/** Returns a promise that resolves with the API base URL once the sidecar is up. */
export function onReady() {
  if (ready) return Promise.resolve(apiBase);
  return new Promise((resolve) => {
    readyCallbacks.push(resolve);
  });
}

/** Wait for sidecar before making the call. */
async function req(path, options) {
  if (!ready) await onReady();
  const res = await fetch(`${apiBase}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
    body: options && options.body ? JSON.stringify(options.body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || res.statusText);
  }
  // 204 No Content / 201 Created with empty body: don't try to parse JSON.
  // POST/PUT/DELETE typically return no body; parsing an empty body throws
  // "Unexpected end of JSON input" (or "string did not match the expected
  // pattern" in Tauri's webview), which masks the actual success.
  if (res.status === 204) return null;
  const ct = res.headers.get("content-type") || "";
  if (!ct.includes("json")) return null;
  const text = await res.text();
  if (!text) return null;
  return JSON.parse(text);
}

export const api = {
  getStatus: () => req("/api/status"),
  getServerConfig: () => req("/api/server-config"),
  saveServerConfig: (cfg) => req("/api/server-config", { method: "POST", body: cfg }),
  testConnection: (addr, port) => req("/api/test-connection", { method: "POST", body: { addr, port } }),
  getAutostart: () => req("/api/autostart"),
  setAutostart: (enabled) => req("/api/autostart", { method: "POST", body: { enabled } }),
  getTunnels: () => req("/api/tunnels"),
  addTunnel: (t) => req("/api/tunnels", { method: "POST", body: t }),
  updateTunnel: (t) => req("/api/tunnels", { method: "PUT", body: t }),
  deleteTunnel: (id) => req(`/api/tunnels?id=${encodeURIComponent(id)}`, { method: "DELETE" }),
  toggleTunnel: (id, enabled) => req(`/api/tunnels/${id}/toggle`, { method: "POST", body: { enabled } }),
  start: () => req("/api/control/start", { method: "POST" }),
  stop: () => req("/api/control/stop", { method: "POST" }),
  restart: () => req("/api/control/restart", { method: "POST" }),
  getEvents: () => req("/api/events"),
  clearEvents: () => req("/api/events", { method: "DELETE" }),
  getSettings: () => req("/api/settings"),
  saveSettings: (s) => req("/api/settings", { method: "POST", body: s }),
};

/** Open another window via the Rust command. */
export async function openWindow(name) {
  try {
    return await _invoke("open_window", { name });
  } catch (invokeError) {
    try {
      const { WebviewWindow } = await import("@tauri-apps/api/webviewWindow");
      const spec = windowSpec(name);
      if (!spec) throw new Error(`未知窗口: ${name}`);
      const existing = await WebviewWindow.getByLabel(name);
      if (existing) {
        await existing.show();
        await existing.setFocus();
        return;
      }
      const win = new WebviewWindow(name, spec);
      await new Promise((resolve, reject) => {
        const offCreated = win.once("tauri://created", () => {
          offCreated.then((off) => off()).catch(() => {});
          offError.then((off) => off()).catch(() => {});
          resolve();
        });
        const offError = win.once("tauri://error", (event) => {
          offCreated.then((off) => off()).catch(() => {});
          offError.then((off) => off()).catch(() => {});
          reject(new Error(String(event.payload || "窗口创建失败")));
        });
      });
      return;
    } catch (fallbackError) {
      const message = fallbackError?.message || invokeError?.message || String(fallbackError || invokeError);
      alert(`打开窗口失败: ${message}`);
      throw fallbackError;
    }
  }
}

function windowSpec(name) {
  const specs = {
    main: { url: "main.html", title: "Meilink", width: 1060, height: 820, minWidth: 980, minHeight: 740 },
    settings: { url: "settings.html", title: "设置", width: 760, height: 460 },
    setup: { url: "setup.html", title: "首次配置", width: 560, height: 640, resizable: false },
    "tunnel-edit": { url: "tunnel-edit.html", title: "隧道", width: 660, height: 440, minWidth: 600, minHeight: 380 },
    logs: { url: "logs.html", title: "日志", width: 820, height: 620, minWidth: 760, minHeight: 560 },
  };
  return specs[name];
}

/** Quit the entire app (stops frpc + sidecar). */
export function quitApp() {
  return _invoke("quit_app");
}

/** Update the tray icon style (appIcon/link/text). */
export function setTrayIconStyle(style) {
  return _invoke("set_tray_icon_style", { style });
}

/**
 * Resize a window to fit its content. Pass the window label and the measured
 * content height (document.body.scrollHeight or similar). The Rust side adds
 * the macOS title bar height and applies the new size.
 *
 * This mirrors Swift's `fixedSize(horizontal: false, vertical: true)` for
 * windows whose content height isn't known until runtime (settings, tunnel
 * edit, setup).
 */
export function fitWindowToContent(label, height) {
  return _invoke("fit_window_to_content", { label, height });
}

/**
 * Measure the real content height of a window and resize the window to fit.
 *
 * Tauri windows have `height: 100vh; overflow: hidden` in CSS so the page
 * never reports a scrollHeight larger than the viewport. To get the real
 * content height we temporarily relax the constraints, measure, then restore
 * them. The label defaults to the current window (from the URL).
 *
 * Call this after the page has rendered its content (e.g. in a
 * requestAnimationFrame after refresh()).
 */
export async function autoFitWindow(label) {
  // In a plain browser (dev), there's no Tauri to invoke — skip gracefully.
  if (!hasTauriInternals()) return;
  // Derive the window label from the URL (settings.html → "settings", etc.)
  const derived = label || window.location.pathname.replace(/\.html$/, "").replace(/^\//, "");
  const app = document.querySelector(".app") || document.body;
  const prevHeight = app.style.height;
  const prevOverflow = app.style.overflow;
  app.style.height = "auto";
  app.style.overflow = "visible";
  // Let the browser reflow with the relaxed constraints.
  await new Promise((r) => requestAnimationFrame(r));
  const contentHeight = Math.max(
    app.scrollHeight,
    app.getBoundingClientRect().height
  );
  app.style.height = prevHeight;
  app.style.overflow = prevOverflow;
  try {
    await fitWindowToContent(derived, contentHeight);
  } catch (e) { /* not in tauri context */ }
}

/** Hide the current window. */
export async function closeWindow() {
  try {
    const { getCurrentWindow } = await import("@tauri-apps/api/window");
    await getCurrentWindow().hide();
  } catch (e) {
    console.error("closeWindow failed:", e);
  }
}

/** Open a URL in the system's default browser. */
export async function openUrl(url) {
  try {
    const { open } = await import("@tauri-apps/plugin-shell");
    await open(url);
  } catch (e) {
    console.error("openUrl failed:", e);
  }
}

/** Copy text to clipboard. */
export async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
  } catch (e) {
    console.error("clipboard failed:", e);
  }
}
