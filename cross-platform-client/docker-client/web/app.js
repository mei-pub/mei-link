const $ = selector => document.querySelector(selector);
let tunnels = [];
let serverConfig = {};
let configuredForm = false;
let polling = 0;
let toastTimer = 0;
const labels = { new: "新建", "wait start": "连接中", "start error": "启动失败", running: "运行中", "check failed": "检查失败", closed: "已关闭" };

const api = async (path, options = {}) => {
  const response = await fetch(path, { credentials: "include", ...options, headers: { "content-type": "application/json", ...(options.headers || {}) } });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || "请求失败");
  return payload;
};
const formValue = (form, name) => new FormData(form).get(name)?.toString().trim() || "";
const field = (form, name) => form.elements.namedItem(name);
const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
const setBusy = (button, busy) => { if (button) button.disabled = busy; };
function notify(message, error = false) { const toast = $("#toast"); toast.textContent = message; toast.className = `toast${error ? " error" : ""}`; clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.classList.add("hidden"), 3600); }
function statusKey(tunnel) { return tunnel.runtimeStatus || tunnel.status || "new"; }
function statusLabel(tunnel) { return labels[statusKey(tunnel)] || "新建"; }
function routeLine(tunnel) { if (!tunnel.route) return "等待远程地址分配"; return tunnel.route; }

async function load() {
  const [status, savedTunnels, events, config] = await Promise.all([api("/api/status"), api("/api/tunnels"), api("/api/events"), api("/api/server-config")]);
  tunnels = savedTunnels; serverConfig = config || {};
  renderStatus(status); renderTunnels(); renderEvents(events);
  if (!configuredForm) { fillConfig(serverConfig); configuredForm = true; }
}
function renderStatus(status) {
  $("#statusText").textContent = status.connected ? "已连接" : status.configured ? "未连接" : "未配置";
  $("#statusDot").className = `dot ${status.connected ? "ok" : status.configured ? "warn" : ""}`;
}
function renderEvents(events) { $("#events").textContent = events.length ? events.map(event => `[${new Date(event.timestamp).toLocaleString()}] ${event.message}`).join("\n") : "尚无日志"; }
function renderTunnels() {
  const target = $("#tunnelList");
  $("#tunnelSummary").textContent = `${tunnels.filter(tunnel => tunnel.enabled).length}/${tunnels.length} 个隧道启用`;
  if (!tunnels.length) { target.innerHTML = '<div class="empty">还没有隧道。添加 HTTP、HTTPS、TCP 或 UDP 隧道，把 NAS 服务发布到公网。</div>'; return; }
  const header = '<div class="tunnel-head"><span>名称</span><span>本地服务</span><span>外网访问</span><span>状态</span><span></span></div>';
  target.innerHTML = header + tunnels.map(tunnel => {
    const route = routeLine(tunnel); const routeHtml = (tunnel.type === "http" || tunnel.type === "https") && tunnel.route ? `<a href="${escapeHtml(route)}" target="_blank" rel="noreferrer">${escapeHtml(route)}</a>` : escapeHtml(route);
    const key = statusKey(tunnel).replaceAll(" ", "-");
    return `<div class="tunnel"><div><span class="tunnel-name">${escapeHtml(tunnel.name)}</span><span class="type">${escapeHtml(tunnel.type.toUpperCase())}</span></div><div class="tunnel-local">${escapeHtml(tunnel.localIP)}:${escapeHtml(tunnel.localPort)}</div><div><div class="tunnel-route">${routeHtml}</div>${tunnel.errorMessage ? `<div class="error">${escapeHtml(tunnel.errorMessage)}</div>` : ""}</div><div class="state ${key}">${escapeHtml(statusLabel(tunnel))}</div><div class="actions row-actions"><button class="button ghost icon-button" title="复制访问地址" aria-label="复制访问地址" data-copy="${escapeHtml(tunnel.id)}">⧉</button>${(tunnel.type === "http" || tunnel.type === "https") && tunnel.route ? `<a class="button ghost icon-button" title="打开访问地址" aria-label="打开访问地址" href="${escapeHtml(route)}" target="_blank" rel="noreferrer">↗</a>` : ""}<button class="button ghost icon-button" title="编辑隧道" aria-label="编辑隧道" data-edit="${escapeHtml(tunnel.id)}">✎</button><button class="button secondary" data-toggle="${escapeHtml(tunnel.id)}">${tunnel.enabled ? "停用" : "启用"}</button><button class="button danger icon-button" title="删除隧道" aria-label="删除隧道" data-delete="${escapeHtml(tunnel.id)}">×</button></div></div>`;
  }).join("");
}
function fillConfig(config) { if (!config) return; const form = $("#configForm"); for (const [name, value] of Object.entries(config)) { const field = form.elements.namedItem(name); if (field && value !== "") field.value = value; } }
function beginPolling() { clearInterval(polling); polling = setInterval(() => load().catch(() => {}), 3000); }
function formForTunnel(tunnel = {}) { const form = $("#tunnelForm"); form.reset(); field(form, "id").value = tunnel.id || ""; field(form, "name").value = tunnel.name || ""; field(form, "type").value = tunnel.type || "http"; field(form, "localIP").value = tunnel.localIP || "127.0.0.1"; field(form, "localPort").value = tunnel.localPort || ""; field(form, "subdomain").value = tunnel.subdomain || ""; field(form, "remotePort").value = tunnel.remotePort || ""; field(form, "customDomains").value = (tunnel.customDomains || []).join(", "); field(form, "httpUser").value = tunnel.httpUser || ""; field(form, "httpPassword").value = tunnel.httpPassword || ""; field(form, "hostHeaderRewrite").value = tunnel.hostHeaderRewrite || ""; field(form, "enabled").checked = tunnel.enabled !== false; typeFields(); }
function typeFields() { const webTunnel = ["http", "https"].includes(field($("#tunnelForm"), "type").value); $("#webTunnelFields").classList.toggle("hidden", !webTunnel); $("#portTunnelFields").classList.toggle("hidden", webTunnel); }
function openTunnelDialog(tunnel) { formForTunnel(tunnel); $("#tunnelDialogTitle").textContent = tunnel ? "编辑隧道" : "添加隧道"; $("#tunnelDialog").showModal(); field($("#tunnelForm"), "name").focus(); }
function closeTunnelDialog() { $("#tunnelDialog").close(); }
function tunnelPayload(form) { return { name: formValue(form, "name"), type: formValue(form, "type"), localIP: formValue(form, "localIP"), localPort: Number(formValue(form, "localPort")), subdomain: formValue(form, "subdomain"), remotePort: Number(formValue(form, "remotePort")) || undefined, customDomains: formValue(form, "customDomains").split(",").map(domain => domain.trim()).filter(Boolean), httpUser: formValue(form, "httpUser"), httpPassword: formValue(form, "httpPassword"), hostHeaderRewrite: formValue(form, "hostHeaderRewrite"), enabled: field(form, "enabled").checked }; }

$("#loginForm").addEventListener("submit", async event => { event.preventDefault(); $("#loginError").textContent = ""; try { await api("/api/login", { method: "POST", body: JSON.stringify({ user: formValue(event.target, "user"), password: formValue(event.target, "password") }) }); $("#loginView").classList.add("hidden"); $("#appView").classList.remove("hidden"); await load(); beginPolling(); } catch (error) { $("#loginError").textContent = error.message; } });
$("#configForm").addEventListener("submit", async event => { event.preventDefault(); const button = event.submitter; setBusy(button, true); try { await api("/api/server-config", { method: "POST", body: JSON.stringify({ serverAddr: formValue(event.target, "serverAddr"), serverPort: Number(formValue(event.target, "serverPort")), authToken: formValue(event.target, "authToken"), subDomainHost: formValue(event.target, "subDomainHost"), tlsEnabled: event.target.tlsEnabled.checked, adminPort: Number(formValue(event.target, "adminPort")), adminUser: formValue(event.target, "adminUser"), adminPassword: formValue(event.target, "adminPassword") }) }); event.target.authToken.value = ""; event.target.adminPassword.value = ""; notify("服务器设置已保存"); await load(); } catch (error) { notify(error.message, true); } finally { setBusy(button, false); } });
$("#newTunnelButton").addEventListener("click", () => openTunnelDialog());
$("#closeTunnelDialog").addEventListener("click", closeTunnelDialog); $("#cancelTunnelButton").addEventListener("click", closeTunnelDialog); field($("#tunnelForm"), "type").addEventListener("change", typeFields);
$("#tunnelForm").addEventListener("submit", async event => { event.preventDefault(); const form = event.target; const button = $("#saveTunnelButton"); setBusy(button, true); try { const payload = tunnelPayload(form); const id = field(form, "id").value; await api(id ? `/api/tunnels/${encodeURIComponent(id)}` : "/api/tunnels", { method: id ? "PUT" : "POST", body: JSON.stringify(payload) }); closeTunnelDialog(); notify(id ? "隧道已更新" : "隧道已创建"); await load(); } catch (error) { notify(error.message, true); } finally { setBusy(button, false); } });
$("#tunnelList").addEventListener("click", async event => { const action = event.target.closest("[data-edit],[data-toggle],[data-delete],[data-copy]"); if (!action) return; const id = action.dataset.edit || action.dataset.toggle || action.dataset.delete || action.dataset.copy; const tunnel = tunnels.find(item => item.id === id); if (!tunnel) return; try { if (action.dataset.edit) return openTunnelDialog(tunnel); if (action.dataset.copy) { await navigator.clipboard.writeText(tunnel.route || ""); return notify(tunnel.route ? "访问地址已复制" : "尚无可复制的访问地址", !tunnel.route); } if (action.dataset.delete) { if (!confirm(`确定删除隧道“${tunnel.name}”吗？`)) return; await api(`/api/tunnels/${encodeURIComponent(tunnel.id)}`, { method: "DELETE" }); notify("隧道已删除"); } else { await api(`/api/tunnels/${encodeURIComponent(tunnel.id)}/toggle`, { method: "POST", body: JSON.stringify({ enabled: !tunnel.enabled }) }); notify(`隧道已${tunnel.enabled ? "停用" : "启用"}`); } await load(); } catch (error) { notify(error.message, true); } });
$("#startButton").addEventListener("click", async event => { setBusy(event.target, true); try { await api("/api/control/start", { method: "POST" }); await load(); } catch (error) { notify(error.message, true); } finally { setBusy(event.target, false); } });
$("#restartButton").addEventListener("click", async event => { setBusy(event.target, true); try { await api("/api/control/start", { method: "POST" }); notify("隧道管理器已重启"); await load(); } catch (error) { notify(error.message, true); } finally { setBusy(event.target, false); } });
$("#stopButton").addEventListener("click", async () => { try { await api("/api/control/stop", { method: "POST" }); await load(); } catch (error) { notify(error.message, true); } });
$("#refreshButton").addEventListener("click", () => load().catch(error => notify(error.message, true)));
$("#logoutButton").addEventListener("click", async () => { clearInterval(polling); await api("/api/logout", { method: "POST" }); location.reload(); });
