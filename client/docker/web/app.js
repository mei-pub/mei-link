const $ = selector => document.querySelector(selector);
const icons = {
  tunnel: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 17h16M7 4v16m10-16v16"/></svg>',
  settings: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-2.15 2.15-.06-.06a1.7 1.7 0 0 0-1.88-.34 1.7 1.7 0 0 0-1.04 1.56v.09h-3.04v-.09A1.7 1.7 0 0 0 10.59 18.7a1.7 1.7 0 0 0-1.88.34l-.06.06-2.15-2.15.06-.06A1.7 1.7 0 0 0 6.9 15a1.7 1.7 0 0 0-1.56-1.04h-.09v-3.04h.09A1.7 1.7 0 0 0 6.9 9.88 1.7 1.7 0 0 0 6.56 8l-.06-.06 2.15-2.15.06.06a1.7 1.7 0 0 0 1.88.34 1.7 1.7 0 0 0 1.04-1.56v-.09h3.04v.09a1.7 1.7 0 0 0 1.04 1.56 1.7 1.7 0 0 0 1.88-.34l.06-.06 2.15 2.15-.06.06a1.7 1.7 0 0 0-.34 1.88 1.7 1.7 0 0 0 1.56 1.04h.09v3.04h-.09A1.7 1.7 0 0 0 19.4 15Z"/></svg>',
  logs: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4h14v16H5zM8 8h8M8 12h8M8 16h5"/></svg>',
  plus: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
  copy: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="9" width="10" height="11" rx="1"/><path d="M15 9V5H5v11h4"/></svg>',
  open: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14 5h5v5M19 5l-9 9M19 13v5a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/></svg>',
  edit: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m4 20 4.3-1 10.1-10.1a2.1 2.1 0 0 0-3-3L5.3 16 4 20Z"/><path d="m13.8 7.4 3 3"/></svg>',
  trash: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13M10 11v5m4-5v5"/></svg>',
  close: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg>',
  empty: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14M7 8h10M9 16h6"/><circle cx="5" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
};
let tunnels = [];
let events = [];
let serverConfig = {};
let configuredForm = false;
let polling = 0;
let toastTimer = 0;
let activeView = "tunnels";
const labels = { new: "新建", "wait start": "连接中", "start error": "启动失败", running: "运行中", "check failed": "检查失败", closed: "已关闭" };

for (const target of document.querySelectorAll("[data-icon]")) target.innerHTML = icons[target.dataset.icon] || "";
const api = async (path, options = {}) => {
  const response = await fetch(path, { credentials: "include", ...options, headers: { "content-type": "application/json", ...(options.headers || {}) } });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || "请求失败");
  return payload;
};
const field = (form, name) => form.elements.namedItem(name);
const formValue = (form, name) => new FormData(form).get(name)?.toString().trim() || "";
const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
const icon = name => icons[name] || "";
const setBusy = (button, busy) => { if (button) button.disabled = busy; };
function notify(message, error = false) { const toast = $("#toast"); toast.textContent = message; toast.className = `toast${error ? " error" : ""}`; clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.classList.add("hidden"), 3600); }
function statusKey(tunnel) { return tunnel.runtimeStatus || tunnel.status || "new"; }
function statusLabel(tunnel) { return labels[statusKey(tunnel)] || "新建"; }
function routeLine(tunnel) { return tunnel.route || "等待服务端分配访问地址"; }
function safeRoute(tunnel) { return /^https?:\/\//i.test(tunnel.route || "") && !tunnel.route.includes("*") ? tunnel.route : ""; }
function setSwitch(control, checked) { control.setAttribute("aria-checked", String(checked)); const input = field(control.closest("form") || document, control.dataset.switch); if (input) input.checked = checked; }
function bindSwitches(root = document) { root.querySelectorAll("[data-switch]").forEach(control => control.addEventListener("click", () => setSwitch(control, control.getAttribute("aria-checked") !== "true"))); }
bindSwitches();

async function load() {
  const [status, savedTunnels, savedEvents, config] = await Promise.all([api("/api/status"), api("/api/tunnels"), api("/api/events"), api("/api/server-config")]);
  tunnels = savedTunnels; events = savedEvents; serverConfig = config || {};
  renderStatus(status); renderTunnels(); renderEvents();
  if (!configuredForm) { fillConfig(serverConfig); configuredForm = true; }
}
function renderStatus(status) {
  $("#statusText").textContent = status.connected ? "已连接" : status.running ? "连接中" : status.configured ? "未连接" : "未配置";
  $("#statusDot").className = `dot ${status.connected ? "ok" : status.running || status.configured ? "warn" : ""}`;
}
function renderTunnels() {
  const target = $("#tunnelList");
  const enabled = tunnels.filter(tunnel => tunnel.enabled).length;
  const running = tunnels.filter(tunnel => statusKey(tunnel) === "running").length;
  $("#tunnelSummary").textContent = `${enabled} / ${tunnels.length} 个隧道已启用`;
  $("#allTunnelCount").textContent = tunnels.length;
  $("#enabledTunnelCount").textContent = enabled;
  $("#runningTunnelCount").textContent = running;
  if (!tunnels.length) { target.innerHTML = `<div class="empty">${icon("empty")}<div>还没有隧道</div><div class="muted" style="margin-top:5px">添加 HTTP、HTTPS、TCP 或 UDP 隧道，将 NAS 服务发布到公网。</div></div>`; return; }
  const header = '<div class="tunnel-head"><span>名称</span><span>本地服务</span><span>外网访问</span><span>状态</span><span></span></div>';
  target.innerHTML = header + tunnels.map(tunnel => {
    const key = statusKey(tunnel).replaceAll(" ", "-");
    const route = safeRoute(tunnel);
    const routeHtml = route ? `<a href="${escapeHtml(route)}" target="_blank" rel="noreferrer">${escapeHtml(route)}</a>` : escapeHtml(routeLine(tunnel));
    const opened = route ? `<a class="button ghost icon-button" title="打开访问地址" aria-label="打开访问地址" href="${escapeHtml(route)}" target="_blank" rel="noreferrer">${icon("open")}</a>` : "";
    return `<div class="tunnel-row"><div><span class="tunnel-name">${escapeHtml(tunnel.name)}</span><span class="type-badge">${escapeHtml(tunnel.type.toUpperCase())}</span></div><div class="service">${escapeHtml(tunnel.localIP)}:${escapeHtml(tunnel.localPort)}</div><div><div class="route">${routeHtml}</div>${tunnel.errorMessage ? `<div class="error">${escapeHtml(tunnel.errorMessage)}</div>` : ""}</div><div class="state ${key}"><i></i>${escapeHtml(statusLabel(tunnel))}</div><div class="actions row-actions"><button class="switch-control" type="button" role="switch" aria-checked="${tunnel.enabled ? "true" : "false"}" aria-label="${escapeHtml(tunnel.name)} ${tunnel.enabled ? "已启用，点击停用" : "已停用，点击启用"}" data-toggle="${escapeHtml(tunnel.id)}"><span></span></button><button class="button ghost icon-button" title="复制访问地址" aria-label="复制访问地址" data-copy="${escapeHtml(tunnel.id)}">${icon("copy")}</button>${opened}<button class="button ghost icon-button" title="编辑隧道" aria-label="编辑隧道" data-edit="${escapeHtml(tunnel.id)}">${icon("edit")}</button><button class="button danger icon-button" title="删除隧道" aria-label="删除隧道" data-delete="${escapeHtml(tunnel.id)}">${icon("trash")}</button></div></div>`;
  }).join("");
}
function formatLogs() { return events.map(event => `[${new Date(event.timestamp).toLocaleString()}] [${String(event.level || "info").toUpperCase()}] ${event.message}`).join("\n"); }
function renderEvents() {
  $("#logCount").textContent = `${events.length} 条记录`;
  const target = $("#events");
  if (!events.length) { target.innerHTML = '<div class="log-empty">尚无运行日志</div>'; return; }
  target.innerHTML = events.map(event => `<div class="log-entry ${escapeHtml(event.level || "info")}"><span class="log-time">${escapeHtml(new Date(event.timestamp).toLocaleString())}</span><span class="log-level">${escapeHtml(String(event.level || "info").toUpperCase())}</span><span class="log-message">${escapeHtml(event.message)}</span></div>`).join("");
}
function fillConfig(config) {
  if (!config) return;
  const form = $("#configForm");
  for (const [name, value] of Object.entries(config)) { const input = field(form, name); if (input && value !== "") input.value = value; }
  const tls = field(form, "tlsEnabled");
  const control = form.querySelector('[data-switch="tlsEnabled"]');
  if (tls && control) setSwitch(control, tls.checked);
}
function beginPolling() { clearInterval(polling); polling = setInterval(() => load().catch(() => {}), 3000); }
function setView(view) {
  activeView = view;
  document.querySelectorAll("[data-view]").forEach(item => item.classList.toggle("active", item.dataset.view === view));
  document.querySelectorAll("[data-panel]").forEach(panel => panel.classList.toggle("hidden", panel.dataset.panel !== view));
}
function formForTunnel(tunnel = {}) {
  const form = $("#tunnelForm"); form.reset();
  field(form, "id").value = tunnel.id || "";
  field(form, "name").value = tunnel.name || "";
  const selectedType = tunnel.type || "http"; field(form, "type").value = selectedType;
  field(form, "localIP").value = tunnel.localIP || "127.0.0.1"; field(form, "localPort").value = tunnel.localPort || "";
  field(form, "subdomain").value = tunnel.subdomain || ""; field(form, "remotePort").value = tunnel.remotePort || "";
  field(form, "customDomains").value = (tunnel.customDomains || []).join(", "); field(form, "httpUser").value = tunnel.httpUser || "";
  field(form, "httpPassword").value = ""; field(form, "hostHeaderRewrite").value = tunnel.hostHeaderRewrite || "";
  const enabled = tunnel.enabled !== false; field(form, "enabled").checked = enabled; setSwitch(form.querySelector('[data-switch="enabled"]'), enabled); typeFields();
}
function typeFields() { const webTunnel = ["http", "https"].includes(formValue($("#tunnelForm"), "type")); $("#webTunnelFields").classList.toggle("hidden", !webTunnel); $("#portTunnelFields").classList.toggle("hidden", webTunnel); }
function openTunnelDialog(tunnel) { formForTunnel(tunnel); $("#tunnelDialogTitle").textContent = tunnel ? "编辑隧道" : "添加隧道"; $("#tunnelDialog").showModal(); field($("#tunnelForm"), "name").focus(); loadDomainDirectory(tunnel); }
function closeTunnelDialog() { $("#tunnelDialog").close(); }

// 域名目录拉取（选基域+填前缀模式）。与原生端/Tauri 端逻辑一致。
let domainEntries = [];
let useDirectory = false;
let editingTunnelForDomain = null;

async function loadDomainDirectory(tunnel) {
  editingTunnelForDomain = tunnel || null;
  domainEntries = []; useDirectory = false;
  $("#directoryGroup").classList.add("hidden");
  $("#manualDomainFields").classList.remove("hidden");
  $("#fallbackNotice").classList.add("hidden");
  const isHttp = ["http", "https"].includes(tunnel?.type || "http");
  if (!isHttp) return;
  try {
    const res = await api("/api/domains");
    if (res.domains && res.domains.length) {
      domainEntries = res.domains;
      renderDomainSection();
    } else if (res.error) {
      $("#fallbackNotice").textContent = res.error + "，改为手动填写";
      $("#fallbackNotice").classList.remove("hidden");
    }
  } catch (e) { /* 静默 fallback */ }
}

function renderDomainSection() {
  if (!domainEntries.length) { useDirectory = false; return; }
  useDirectory = true;
  $("#directoryGroup").classList.remove("hidden");
  $("#manualDomainFields").classList.add("hidden");
  const sel = $("#baseDomain");
  sel.innerHTML = domainEntries.map(d => `<option value="${d.domain}">${d.domain}（${d.kind === "wildcard" ? "泛域名" : "主域名"}）</option>`).join("");
  // 编辑已有隧道时回填
  if (editingTunnelForDomain) {
    const sub = editingTunnelForDomain.subdomain;
    const customs = editingTunnelForDomain.customDomains || [];
    if (sub) { const p = domainEntries.find(d => d.kind !== "wildcard"); if (p) { sel.value = p.domain; $("#domainPrefix").value = sub; } }
    else if (customs.length) { const host = customs[0]; for (const d of domainEntries) { if (d.kind === "wildcard") { const h = d.domain.slice(2); if (host.endsWith("." + h)) { sel.value = d.domain; $("#domainPrefix").value = host.slice(0, -(h.length + 1)); break; } } } }
  }
  updateDomainPreview();
  sel.onchange = updateDomainPreview;
  $("#domainPrefix").oninput = updateDomainPreview;
}

function updateDomainPreview() {
  const sel = $("#baseDomain"); const domain = sel.value; const prefix = $("#domainPrefix").value.trim();
  const host = domain.startsWith("*.") ? domain.slice(2) : domain;
  const full = prefix ? `${prefix}.${host}` : host;
  const type = formValue($("#tunnelForm"), "type");
  $("#domainPreview").textContent = `访问地址：${type === "https" ? "https" : "http"}://${full}`;
}

function tunnelPayload(form) {
  const type = formValue(form, "type");
  let subdomain = formValue(form, "subdomain");
  let customDomains = formValue(form, "customDomains").split(",").map(d => d.trim()).filter(Boolean);
  // directory 模式：按所选基域类型算出 subdomain 或 customDomains
  if (useDirectory && ["http", "https"].includes(type)) {
    const sel = $("#baseDomain"); const entry = domainEntries.find(d => d.domain === sel.value);
    const prefix = $("#domainPrefix").value.trim();
    if (entry) {
      if (entry.kind === "wildcard") { subdomain = ""; customDomains = [prefix ? `${prefix}.${entry.domain.slice(2)}` : entry.domain.slice(2)]; }
      else { subdomain = prefix; customDomains = []; }
    }
  }
  return { name: formValue(form, "name"), type, localIP: formValue(form, "localIP"), localPort: Number(formValue(form, "localPort")), subdomain, remotePort: Number(formValue(form, "remotePort")) || undefined, customDomains, httpUser: formValue(form, "httpUser"), httpPassword: formValue(form, "httpPassword"), hostHeaderRewrite: formValue(form, "hostHeaderRewrite"), enabled: field(form, "enabled").checked };
}
async function saveConfig(connectAfterSave = false) {
  const form = $("#configForm");
  await api("/api/server-config", { method: "POST", body: JSON.stringify({ serverAddr: formValue(form, "serverAddr"), serverPort: Number(formValue(form, "serverPort")), authToken: formValue(form, "authToken"), subDomainHost: formValue(form, "subDomainHost"), tlsEnabled: field(form, "tlsEnabled").checked, adminPort: Number(formValue(form, "adminPort")), adminUser: formValue(form, "adminUser"), adminPassword: formValue(form, "adminPassword"), vhostHTTPPort: Number(formValue(form, "vhostHTTPPort")), vhostHTTPSPort: Number(formValue(form, "vhostHTTPSPort")), managementURL: formValue(form, "managementURL"), domainAPIToken: formValue(form, "domainAPIToken") }) });
  field(form, "authToken").value = ""; field(form, "adminPassword").value = "";
  if (connectAfterSave) await api("/api/control/start", { method: "POST" });
  notify(connectAfterSave ? "设置已保存，正在连接" : "服务器设置已保存"); await load();
}
async function copyText(value, success) { if (!value) throw new Error("没有可复制的内容"); if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(value); else { const area = document.createElement("textarea"); area.value = value; document.body.append(area); area.select(); document.execCommand("copy"); area.remove(); } notify(success); }

$("#loginForm").addEventListener("submit", async event => { event.preventDefault(); $("#loginError").textContent = ""; try { await api("/api/login", { method: "POST", body: JSON.stringify({ user: formValue(event.target, "user"), password: formValue(event.target, "password") }) }); $("#loginView").classList.add("hidden"); $("#appView").classList.remove("hidden"); await load(); beginPolling(); } catch (error) { $("#loginError").textContent = error.message; } });
document.querySelectorAll("[data-view]").forEach(item => item.addEventListener("click", () => setView(item.dataset.view)));
$("#configForm").addEventListener("submit", async event => { event.preventDefault(); const button = event.submitter; setBusy(button, true); try { await saveConfig(); } catch (error) { notify(error.message, true); } finally { setBusy(button, false); } });
$("#saveAndConnectButton").addEventListener("click", async event => { setBusy(event.currentTarget, true); try { await saveConfig(true); } catch (error) { notify(error.message, true); } finally { setBusy(event.currentTarget, false); } });
$("#fetchBootstrapButton").addEventListener("click", async event => {
  const result = $("#bootstrapResult"); setBusy(event.currentTarget, true);
  result.textContent = "正在拉取配置…"; result.className = "test-result";
  try {
    const info = await api("/api/bootstrap");
    if (!info || info.error) throw new Error((info && info.error) || "拉取失败");
    const form = $("#configForm");
    if (info.serverAddr) field(form, "serverAddr").value = info.serverAddr;
    if (info.serverPort) field(form, "serverPort").value = info.serverPort;
    if (info.authToken) field(form, "authToken").value = info.authToken;
    if (info.subDomainHost) field(form, "subDomainHost").value = info.subDomainHost;
    result.textContent = `已拉取：${info.serverAddr || "未设置"}:${info.serverPort}，子域名根域 ${info.subDomainHost || "未设置"}`;
    result.className = "test-result ok";
  } catch (error) { result.textContent = `拉取失败：${error.message}`; result.className = "test-result error"; }
  finally { setBusy(event.currentTarget, false); }
});
$("#testConnectionButton").addEventListener("click", async event => { const result = $("#connectionTestResult"); setBusy(event.currentTarget, true); result.textContent = "正在测试连接…"; result.className = "test-result"; try { const form = $("#configForm"); const outcome = await api("/api/test-connection", { method: "POST", body: JSON.stringify({ addr: formValue(form, "serverAddr"), port: Number(formValue(form, "serverPort")) }) }); result.textContent = outcome.ok ? "服务器端口可连接" : `连接失败：${outcome.err || "未知错误"}`; result.className = `test-result ${outcome.ok ? "ok" : "error"}`; } catch (error) { result.textContent = `测试失败：${error.message}`; result.className = "test-result error"; } finally { setBusy(event.currentTarget, false); } });
$("#newTunnelButton").addEventListener("click", () => openTunnelDialog()); $("#closeTunnelDialog").addEventListener("click", closeTunnelDialog); $("#cancelTunnelButton").addEventListener("click", closeTunnelDialog);
document.querySelectorAll('input[name="type"]').forEach(input => input.addEventListener("change", typeFields));
$("#tunnelForm").addEventListener("submit", async event => { event.preventDefault(); const form = event.target; const button = $("#saveTunnelButton"); setBusy(button, true); try { const payload = tunnelPayload(form); const id = field(form, "id").value; await api(id ? `/api/tunnels/${encodeURIComponent(id)}` : "/api/tunnels", { method: id ? "PUT" : "POST", body: JSON.stringify(payload) }); closeTunnelDialog(); notify(id ? "隧道已更新" : "隧道已创建"); await load(); } catch (error) { notify(error.message, true); } finally { setBusy(button, false); } });
$("#tunnelList").addEventListener("click", async event => { const action = event.target.closest("[data-edit],[data-toggle],[data-delete],[data-copy]"); if (!action) return; const id = action.dataset.edit || action.dataset.toggle || action.dataset.delete || action.dataset.copy; const tunnel = tunnels.find(item => item.id === id); if (!tunnel) return; try { if (action.dataset.edit) return openTunnelDialog(tunnel); if (action.dataset.copy) return copyText(tunnel.route || "", "访问地址已复制"); if (action.dataset.delete) { if (!confirm(`确定删除隧道“${tunnel.name}”吗？`)) return; await api(`/api/tunnels/${encodeURIComponent(tunnel.id)}`, { method: "DELETE" }); notify("隧道已删除"); } else { await api(`/api/tunnels/${encodeURIComponent(tunnel.id)}/toggle`, { method: "POST", body: JSON.stringify({ enabled: !tunnel.enabled }) }); notify(`隧道已${tunnel.enabled ? "停用" : "启用"}`); } await load(); } catch (error) { notify(error.message, true); } });
$("#startButton").addEventListener("click", async event => { setBusy(event.currentTarget, true); try { await api("/api/control/start", { method: "POST" }); await load(); } catch (error) { notify(error.message, true); } finally { setBusy(event.currentTarget, false); } });
$("#restartButton").addEventListener("click", async event => { setBusy(event.currentTarget, true); try { await api("/api/control/start", { method: "POST" }); notify("隧道管理器已重启"); await load(); } catch (error) { notify(error.message, true); } finally { setBusy(event.currentTarget, false); } });
$("#stopButton").addEventListener("click", async event => { setBusy(event.currentTarget, true); try { await api("/api/control/stop", { method: "POST" }); await load(); } catch (error) { notify(error.message, true); } finally { setBusy(event.currentTarget, false); } });
$("#refreshButton").addEventListener("click", () => load().catch(error => notify(error.message, true)));
$("#copyLogsButton").addEventListener("click", () => copyText(formatLogs(), "运行日志已复制").catch(error => notify(error.message, true)));
$("#exportLogsButton").addEventListener("click", () => { const blob = new Blob([formatLogs() || "尚无运行日志\n"], { type: "text/plain;charset=utf-8" }); const link = document.createElement("a"); link.href = URL.createObjectURL(blob); link.download = `meilink-log-${new Date().toISOString().replace(/[:.]/g, "-")}.txt`; link.click(); URL.revokeObjectURL(link.href); });
$("#clearLogsButton").addEventListener("click", async () => { if (!events.length || !confirm("确定清空当前运行日志吗？")) return; try { await api("/api/events", { method: "DELETE" }); notify("运行日志已清空"); await load(); } catch (error) { notify(error.message, true); } });
$("#logoutButton").addEventListener("click", async () => { clearInterval(polling); await api("/api/logout", { method: "POST" }); location.reload(); });
