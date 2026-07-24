// Meilink desktop shared API client.
// Uses @tauri-apps/api ES module imports (bundled by Vite).

import { invoke as tauriInvoke, isTauri } from "@tauri-apps/api/core";
import { listen as tauriListen } from "@tauri-apps/api/event";
export { STATUS_LABELS, normalizeStatus, tunnelStatus, normalizeSubdomain, routeText, canOpen, overallStatus, esc } from "./display.js";

// Fallback: use window.__TAURI__ if available
const _invoke = isTauri ? tauriInvoke : (window.__TAURI__?.core?.invoke || (() => Promise.reject(new Error("Tauri API not available"))));
const _listen = isTauri ? tauriListen : (window.__TAURI__?.event?.listen || (() => Promise.reject(new Error("Tauri API not available"))));

let apiBase = "";
let readyCallbacks = [];
let ready = false;

// Try to get the API URL. Polls invoke("get_api_url") every 500ms until the
// sidecar is ready, and also listens for the sidecar-ready event.
async function initApi() {
  // Listen for the sidecar-ready event first (to avoid missing it).
  _listen("sidecar-ready", (event) => {
    apiBase = event.payload;
    if (apiBase && !ready) {
      ready = true;
      readyCallbacks.forEach((cb) => cb(apiBase));
    }
  });

  // Poll get_api_url until it returns a non-empty value.
  for (let i = 0; i < 120; i++) {
    try {
      apiBase = await _invoke("get_api_url");
      if (apiBase) {
        ready = true;
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
  const ct = res.headers.get("content-type") || "";
  return ct.includes("json") ? res.json() : null;
}

export const api = {
  getStatus: () => req("/api/status"),
  getServerConfig: () => req("/api/server-config"),
  saveServerConfig: (cfg) => req("/api/server-config", { method: "POST", body: cfg }),
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
    settings: { url: "settings.html", title: "设置", width: 760, height: 640, minWidth: 600, minHeight: 600 },
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
