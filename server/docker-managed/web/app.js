const loginView = document.querySelector("#loginView");
const appView = document.querySelector("#appView");
const rows = document.querySelector("#domainRows");
const form = document.querySelector("#configForm");

// 当前 Tab 状态：决定隧道状态页是否轮询
let activeTab = "settings";
let tunnelPollTimer = null;

async function request(path, options = {}) {
  const response = await fetch(path, { headers: { "content-type": "application/json", ...(options.headers || {}) }, ...options });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || "请求失败");
  return payload;
}

function addDomain(domain = "", kind = "custom", enabled = true) {
  const row = document.createElement("div");
  row.className = "domain-row";
  const input = document.createElement("input"); input.className = "input"; input.value = domain; input.placeholder = kind === "wildcard" ? "*.apps.example.com" : "tunnel.example.com";
  const select = document.createElement("select"); select.innerHTML = '<option value="primary">主域名</option><option value="custom">额外域名</option><option value="wildcard">泛域名</option>'; select.value = kind;
  const checkbox = document.createElement("input"); checkbox.type = "checkbox"; checkbox.checked = enabled;
  const remove = document.createElement("button"); remove.type = "button"; remove.className = "button icon-button"; remove.textContent = "×"; remove.onclick = () => row.remove();
  row.append(input, select, checkbox, remove); rows.append(row);
}

function domainsFromForm() {
  return [...rows.children].map((row) => {
    const [input, select, checkbox] = row.children;
    return { domain: input.value, kind: select.value, enabled: checkbox.checked };
  }).filter((item) => item.domain.trim());
}

function renderLogs(events) {
  const box = document.querySelector("#events"); box.replaceChildren();
  if (!events.length) { box.textContent = "暂无日志"; return; }
  events.forEach((event) => { const line = document.createElement("div"); line.className = `log ${event.level || "info"}`; const time = document.createElement("time"); time.textContent = new Date(event.time).toLocaleString(); line.append(time, document.createTextNode(event.message)); box.append(line); });
}

function updatePortNotice() {
  const notice = document.querySelector("#portNotice");
  const low = ["bindPort", "vhostHTTPPort", "vhostHTTPSPort"]
    .filter((name) => Number(form[name].value) > 0 && Number(form[name].value) < 1024);
  if (!low.length) { notice.textContent = ""; return; }
  notice.style.color = "#b07b00";
  notice.textContent = `端口 ${low.join("、")} < 1024 为特权端口，依赖镜像内置的 CAP_NET_BIND_SERVICE（已构建版本自动满足），host 网络模式下保存即生效。`;
}

// 读取当前完整 config（系统设置 + 域名共用一份 server config）
let currentConfig = null;

async function refresh() {
  const [config, status, events] = await Promise.all([request("/api/config"), request("/api/status"), request("/api/events")]);
  currentConfig = config;
  form.bindPort.value = config.bindPort; form.vhostHTTPPort.value = config.vhostHTTPPort; form.vhostHTTPSPort.value = config.vhostHTTPSPort; form.authToken.value = config.authToken; form.serverAddr.value = config.serverAddr || "";
  rows.replaceChildren(); config.domains.forEach((item) => addDomain(item.domain, item.kind, item.enabled));
  document.querySelector("#frpsState").textContent = status.running ? "运行中" : status.configured ? "未运行" : "待配置";
  document.querySelector("#domainCount").textContent = String(status.domains.length);
  const dot = document.querySelector("#statusDot");
  dot.className = `dot ${status.running ? "running" : status.lastError ? "error" : ""}`;
  document.querySelector("#statusText").textContent = status.running ? `frps 正在运行（PID ${status.pid || "-"}）` : status.lastError || "frps 未运行";
  renderLogs(events);
  updatePortNotice();
}

// 隧道状态：拉 serverinfo + proxies
function fmtBytes(b) {
  if (typeof b !== "number") return "-"; if (b < 1024) return b + " B";
  const u = ["KB", "MB", "GB", "TB"]; let i = -1; do { b /= 1024; i++; } while (b >= 1024 && i < u.length - 1);
  return b.toFixed(1) + " " + u[i];
}

async function refreshTunnelStatus() {
  // serverinfo
  try {
    const si = await request("/api/frps/serverinfo");
    const grid = document.querySelector("#serverInfoGrid");
    if (si.error || !si.serverinfo) {
      grid.innerHTML = `<div class="info-item"><span>仪表盘</span><span style="color:#bd3b48">${si.error || "不可用"}</span></div>`;
    } else {
      const d = si.serverinfo;
      const items = [
        ["frp 版本", d.version || "-"],
        ["运行时长", d.totalTrafficIn !== undefined ? "运行中" : "-"],
        ["客户端数", String(d.clientCounts ?? 0)],
        ["代理总数", Object.values(d.proxyTypeCount || {}).reduce((a, b) => a + b, 0)],
        ["入站流量", fmtBytes(d.totalTrafficIn)],
        ["出站流量", fmtBytes(d.totalTrafficOut)],
      ];
      grid.innerHTML = items.map(([k, v]) => `<div class="info-item"><span>${k}</span><span>${v}</span></div>`).join("");
    }
  } catch (e) { /* ignore */ }

  // proxies
  try {
    const pr = await request("/api/frps/proxies");
    const box = document.querySelector("#proxyList");
    if (pr.error) { box.innerHTML = `<div class="empty">${pr.error}</div>`; return; }
    const sections = [];
    for (const [type, data] of Object.entries(pr.proxies || {})) {
      const list = (data && data.proxies) || [];
      if (!list.length) continue;
      const rowsHtml = list.map((p) => {
        const status = p.status || "new";
        const badge = status === "running" ? `<span class="badge running">running</span>` : `<span class="badge new">${status}</span>`;
        const remote = p.remoteAddr || (p.customDomains && p.customDomains.join(",")) || p.subdomain || "-";
        return `<tr><td>${p.name || "-"}</td><td>${type}</td><td>${remote}</td><td>${badge}</td></tr>`;
      }).join("");
      sections.push(`<div class="proxy-section"><h4>${type.toUpperCase()}（${list.length}）</h4><table class="proxy-table"><thead><tr><th>名称</th><th>类型</th><th>远程地址</th><th>状态</th></tr></thead><tbody>${rowsHtml}</tbody></table></div>`);
    }
    box.innerHTML = sections.length ? sections.join("") : `<div class="empty">暂无已连接的代理</div>`;
  } catch (e) { /* ignore */ }
}

// Tab 切换
function switchTab(name) {
  activeTab = name;
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t.dataset.tab === name));
  document.querySelectorAll(".tabpane").forEach((p) => p.classList.toggle("active", p.id === `pane-${name}`));
  // 隧道状态页：开启 5s 轮询；离开则停止
  if (tunnelPollTimer) { clearInterval(tunnelPollTimer); tunnelPollTimer = null; }
  if (name === "tunnels") { refreshTunnelStatus(); tunnelPollTimer = setInterval(refreshTunnelStatus, 5000); }
}

document.querySelectorAll(".tab").forEach((t) => t.addEventListener("click", () => switchTab(t.dataset.tab)));

// 登录
document.querySelector("#loginForm").onsubmit = async (event) => { event.preventDefault(); try { await request("/api/login", { method: "POST", body: JSON.stringify({ user: document.querySelector("#user").value, password: document.querySelector("#password").value }) }); loginView.classList.add("hidden"); appView.classList.remove("hidden"); await refresh(); } catch (error) { document.querySelector("#loginError").textContent = error.message; } };
document.querySelector("#addDomain").onclick = () => addDomain();

// 系统设置保存（端口 + token）
form.onsubmit = async (event) => { event.preventDefault(); const notice = document.querySelector("#saveNotice"); try { await request("/api/config", { method: "POST", body: JSON.stringify({ bindPort: Number(form.bindPort.value), vhostHTTPPort: Number(form.vhostHTTPPort.value), vhostHTTPSPort: Number(form.vhostHTTPSPort.value), authToken: form.authToken.value, serverAddr: form.serverAddr.value.trim(), domains: currentConfig?.domains || [] }) }); notice.style.color = "#1b9762"; notice.textContent = "已保存并重启 frps"; await refresh(); } catch (error) { notice.style.color = "#c33d4c"; notice.textContent = error.message; } };

// 域名保存（独立按钮，保留端口/token 不变）
document.querySelector("#saveDomainsBtn").onclick = async (event) => { event.preventDefault(); const notice = document.querySelector("#domainSaveNotice"); try { await request("/api/config", { method: "POST", body: JSON.stringify({ bindPort: Number(form.bindPort.value), vhostHTTPPort: Number(form.vhostHTTPPort.value), vhostHTTPSPort: Number(form.vhostHTTPSPort.value), authToken: form.authToken.value, serverAddr: form.serverAddr.value.trim(), domains: domainsFromForm() }) }); notice.style.color = "#1b9762"; notice.textContent = "已保存并重启 frps"; await refresh(); } catch (error) { notice.style.color = "#c33d4c"; notice.textContent = error.message; } };

["bindPort", "vhostHTTPPort", "vhostHTTPSPort"].forEach((name) => form[name].addEventListener("input", updatePortNotice));
document.querySelector("#restartFrps").onclick = async () => { await request("/api/control/restart", { method: "POST" }); await refresh(); };
document.querySelector("#refresh").onclick = refresh;
document.querySelector("#logout").onclick = async () => { await request("/api/logout", { method: "POST" }); location.reload(); };
