// Pure display helpers aligned with Swift TunnelDisplay.

export const STATUS_LABELS = {
  new: "新建",
  wait_start: "连接中",
  start_error: "启动失败",
  running: "运行中",
  check_failed: "检查失败",
  closed: "已关闭",
};

export function normalizeStatus(status) {
  switch (status) {
    case "waitStart":
    case "wait start":
      return "wait_start";
    case "startError":
    case "start error":
      return "start_error";
    case "checkFailed":
    case "check failed":
      return "check_failed";
    case "new":
    case "running":
    case "closed":
    case "wait_start":
    case "start_error":
    case "check_failed":
      return status;
    default:
      return status || "new";
  }
}

export function tunnelStatus(tunnel) {
  return normalizeStatus(tunnel.runtimeStatus || tunnel.status || "new");
}

export function normalizeSubdomain(subdomain, baseHost) {
  const value = String(subdomain || "").trim();
  if (!value) return "";
  const base = String(baseHost || "").trim();
  if (!base) return value;
  const suffix = `.${base}`;
  if (value.endsWith(suffix)) {
    return value.slice(0, -suffix.length) || "";
  }
  return value;
}

export function routeText(tunnel, serverConfig) {
  const sc = serverConfig || {};
  const base = sc.subDomainHost || "";
  const normalized = normalizeSubdomain(tunnel.subdomain, base);
  const sub = normalized ? `${normalized}${base ? "." + base : ""}` : "";
  switch (tunnel.type) {
    case "http":
      if (tunnel.remoteAddr) return `http://${tunnel.remoteAddr}`;
      if (sub) return `http://${sub}`;
      return "未设置子域名";
    case "https":
      if (tunnel.remoteAddr) return `https://${tunnel.remoteAddr}`;
      if (sub) return `https://${sub}`;
      return "未设置子域名";
    case "tcp":
    case "udp":
      if (tunnel.remoteAddr) return tunnel.remoteAddr;
      if (tunnel.remotePort) return `${sc.serverAddr || "服务器"}:${tunnel.remotePort}`;
      return "等待分配远程端口";
    default:
      return "";
  }
}

export function canOpen(tunnel) {
  return tunnel.type === "http" || tunnel.type === "https";
}

export function overallStatus(status) {
  if (!status.configured) return { text: "未配置", dotClass: "stopped" };
  if (status.connected) return { text: "已连接", dotClass: "running" };
  if (status.reconnectFailed) return { text: "重连失败", dotClass: "error" };
  if (status.reconnecting || status.running) return { text: status.reconnecting ? "重连中" : "连接中", dotClass: "connecting" };
  return { text: "未连接", dotClass: "stopped" };
}

export function esc(s) {
  if (s == null) return "";
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
