const $ = selector => document.querySelector(selector);
let tunnels = [];
const api = async (path, options = {}) => {
  const response = await fetch(path, { credentials: "include", ...options, headers: { "content-type": "application/json", ...(options.headers || {}) } });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || "请求失败");
  return payload;
};
const formValue = (form, name) => new FormData(form).get(name)?.toString().trim() || "";
const setBusy = (button, busy) => { button.disabled = busy; };

async function load() {
  const [status, savedTunnels, events, config] = await Promise.all([api("/api/status"), api("/api/tunnels"), api("/api/events"), api("/api/server-config")]);
  tunnels = savedTunnels; renderStatus(status); renderTunnels(); renderEvents(events); fillConfig(config);
}
function renderStatus(status) { $("#statusText").textContent = status.connected ? "已连接" : status.configured ? "未连接" : "未配置"; $("#statusDot").className = `dot ${status.connected ? "ok" : status.configured ? "warn" : ""}`; }
function renderEvents(events) { $("#events").textContent = events.length ? events.map(event => `[${new Date(event.timestamp).toLocaleString()}] ${event.message}`).join("\n") : "尚无日志"; }
function renderTunnels() { const target = $("#tunnelList"); if (!tunnels.length) { target.innerHTML = '<div class="empty">尚未创建隧道。</div>'; return; } target.innerHTML = tunnels.map(tunnel => `<div class="tunnel"><div><span class="tunnel-name">${escapeHtml(tunnel.name)}</span><span class="pill">${tunnel.type.toUpperCase()}</span><div class="muted">${escapeHtml(tunnel.localIP)}:${tunnel.localPort}${tunnel.subdomain ? ` · ${escapeHtml(tunnel.subdomain)}` : ""}${tunnel.remotePort ? ` · :${tunnel.remotePort}` : ""}</div></div><button class="button danger" data-delete="${escapeHtml(tunnel.id)}">删除</button></div>`).join(""); }
function fillConfig(config) { if (!config) return; const form = $("#configForm"); for (const [name, value] of Object.entries(config)) { const field = form.elements.namedItem(name); if (field && value !== "") field.value = value; } }
function escapeHtml(value) { return String(value).replace(/[&<>'"]/g, char => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", "'":"&#39;", '"':"&quot;" })[char]); }

$("#loginForm").addEventListener("submit", async event => { event.preventDefault(); $("#loginError").textContent = ""; try { await api("/api/login", { method: "POST", body: JSON.stringify({ user: formValue(event.target, "user"), password: formValue(event.target, "password") }) }); $("#loginView").classList.add("hidden"); $("#appView").classList.remove("hidden"); await load(); } catch (error) { $("#loginError").textContent = error.message; } });
$("#configForm").addEventListener("submit", async event => { event.preventDefault(); const button = event.submitter; setBusy(button, true); try { await api("/api/server-config", { method: "POST", body: JSON.stringify({ serverAddr: formValue(event.target,"serverAddr"), serverPort: Number(formValue(event.target,"serverPort")), authToken: formValue(event.target,"authToken"), subDomainHost: formValue(event.target,"subDomainHost"), tlsEnabled: event.target.tlsEnabled.checked, adminPort: Number(formValue(event.target,"adminPort")), adminUser: formValue(event.target,"adminUser"), adminPassword: formValue(event.target,"adminPassword") }) }); event.target.authToken.value = ""; event.target.adminPassword.value = ""; await load(); } catch (error) { alert(error.message); } finally { setBusy(button, false); } });
$("#tunnelForm").addEventListener("submit", async event => { event.preventDefault(); const form = event.target; const tunnel = { id: crypto.randomUUID(), name: formValue(form,"name"), type: formValue(form,"type"), localIP: formValue(form,"localIP"), localPort: Number(formValue(form,"localPort")), subdomain: formValue(form,"subdomain"), remotePort: Number(formValue(form,"remotePort")) || undefined, enabled: true }; try { if (tunnels.some(item => item.name === tunnel.name)) throw new Error("隧道名称已存在"); await api("/api/tunnels", { method: "PUT", body: JSON.stringify([...tunnels, tunnel]) }); form.reset(); form.localIP.value = "127.0.0.1"; await load(); } catch (error) { alert(error.message); } });
$("#tunnelList").addEventListener("click", async event => { const id = event.target.dataset.delete; if (!id) return; tunnels = tunnels.filter(tunnel => tunnel.id !== id); await api("/api/tunnels", { method: "PUT", body: JSON.stringify(tunnels) }); await load(); });
$("#startButton").addEventListener("click", async event => { setBusy(event.target, true); try { await api("/api/control/start", { method: "POST" }); await load(); } catch (error) { alert(error.message); } finally { setBusy(event.target, false); } });
$("#stopButton").addEventListener("click", async () => { await api("/api/control/stop", { method: "POST" }); await load(); });
$("#logoutButton").addEventListener("click", async () => { await api("/api/logout", { method: "POST" }); location.reload(); });
