const DEFAULT_ATTEMPTS = 60;
const DEFAULT_RETRY_DELAY_MS = 500;

/**
 * Resolves the sidecar API URL within a bounded retry budget.
 *
 * The sidecar may fail before it can publish its port, especially when a
 * platform-specific data directory differs from the desktop host. Rejecting
 * here lets callers restore their busy UI instead of waiting forever.
 */
export async function waitForApiReady({
  getApiUrl,
  getInjectedApiUrl = () => "",
  attempts = DEFAULT_ATTEMPTS,
  retryDelayMs = DEFAULT_RETRY_DELAY_MS,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
} = {}) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const injectedUrl = getInjectedApiUrl();
    if (injectedUrl) return injectedUrl;

    try {
      const apiUrl = await getApiUrl();
      if (apiUrl) return apiUrl;
    } catch (_) {
      // Tauri may not have injected its invoke bridge yet; retry below.
    }

    if (attempt < attempts - 1) await sleep(retryDelayMs);
  }

  throw new Error("本地服务未能启动，请退出 Meilink 后重试。");
}
