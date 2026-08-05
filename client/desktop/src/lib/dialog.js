// Custom HTML modal dialogs for Tauri webview.
//
// Tauri v2 webview does NOT support the browser's native window.confirm() /
// window.alert() (the webview engine doesn't implement them and the CSP
// blocks them). Using them silently fails — confirm() returns false, alert()
// is a no-op — which makes buttons look stuck ("置灰") because the handler
// never completes.
//
// These helpers render an HTML overlay instead, which works in both the
// Tauri webview and a plain browser (for dev).

function ensureOverlayStyle() {
  if (document.getElementById("__dialog_style")) return;
  const style = document.createElement("style");
  style.id = "__dialog_style";
  style.textContent = `
    .__dialog-overlay {
      position: fixed; inset: 0; background: rgba(0,0,0,0.4);
      display: flex; align-items: center; justify-content: center;
      z-index: 2147483647;
      animation: __dialog-fade .15s ease-out;
    }
    @keyframes __dialog-fade { from { opacity: 0; } to { opacity: 1; } }
    .__dialog-card {
      background: #fff; border-radius: 10px;
      padding: 18px 22px; min-width: 320px; max-width: 440px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.18);
      animation: __dialog-pop .15s ease-out;
    }
    @keyframes __dialog-pop { from { transform: scale(.96); opacity: 0; } to { transform: scale(1); opacity: 1; } }
    .__dialog-title { font-size: 14px; font-weight: 600; color: #1d1d1f; margin-bottom: 8px; }
    .__dialog-body { font-size: 12px; color: #6e6e73; margin-bottom: 16px; line-height: 1.5; }
    .__dialog-actions { display: flex; gap: 8px; justify-content: flex-end; }
    .__dialog-btn {
      padding: 6px 14px; font-size: 12px; border-radius: 6px;
      border: 1px solid #d2d2d7; background: #fff; color: #1d1d1f;
      cursor: pointer; font-weight: 500;
    }
    .__dialog-btn:hover { background: #f5f5f7; }
    .__dialog-btn-primary {
      background: #0071e3; color: #fff; border-color: #0071e3;
    }
    .__dialog-btn-primary:hover { background: #0077ed; }
    .__dialog-btn-danger {
      background: #ff3b30; color: #fff; border-color: #ff3b30;
    }
    .__dialog-btn-danger:hover { background: #ff453a; }
  `;
  document.head.appendChild(style);
}

/**
 * Show a confirm dialog. Returns a Promise that resolves to true (confirm)
 * or false (cancel).
 *
 * @param {string} title - dialog title
 * @param {string} body - dialog body text (HTML allowed)
 * @param {object} [opts] - { confirmText, cancelText, danger }
 */
export function customConfirm(title, body, opts = {}) {
  const {
    confirmText = "确定",
    cancelText = "取消",
    danger = false,
  } = opts;
  return new Promise((resolve) => {
    ensureOverlayStyle();
    const overlay = document.createElement("div");
    overlay.className = "__dialog-overlay";
    const confirmClass = danger ? "__dialog-btn __dialog-btn-danger" : "__dialog-btn __dialog-btn-primary";
    overlay.innerHTML = `
      <div class="__dialog-card">
        <div class="__dialog-title">${title}</div>
        <div class="__dialog-body">${body}</div>
        <div class="__dialog-actions">
          <button class="__dialog-btn" data-action="cancel">${cancelText}</button>
          <button class="${confirmClass}" data-action="confirm">${confirmText}</button>
        </div>
      </div>`;
    overlay.querySelector('[data-action="confirm"]').onclick = () => { overlay.remove(); resolve(true); };
    overlay.querySelector('[data-action="cancel"]').onclick = () => { overlay.remove(); resolve(false); };
    // Append to documentElement (html root) so the overlay is never clipped
    // by a parent's overflow:hidden / height:100vh (e.g. .app in settings).
    document.documentElement.appendChild(overlay);
  });
}

/**
 * Show an alert dialog. Returns a Promise that resolves when dismissed.
 * @param {string} message - alert body (HTML allowed)
 */
export function customAlert(message) {
  return new Promise((resolve) => {
    ensureOverlayStyle();
    const overlay = document.createElement("div");
    overlay.className = "__dialog-overlay";
    overlay.innerHTML = `
      <div class="__dialog-card">
        <div class="__dialog-body">${message}</div>
        <div class="__dialog-actions">
          <button class="__dialog-btn __dialog-btn-primary" data-action="ok">确定</button>
        </div>
      </div>`;
    overlay.querySelector('[data-action="ok"]').onclick = () => { overlay.remove(); resolve(); };
    document.documentElement.appendChild(overlay);
  });
}
