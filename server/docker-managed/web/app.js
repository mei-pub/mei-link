const loginView = document.querySelector("#loginView");
const appView = document.querySelector("#appView");
const rows = document.querySelector("#domainRows");
const form = document.querySelector("#configForm");

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

function domains() {
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

// 提示特权端口（< 1024）。镜像已给 frps 设置 CAP_NET_BIND_SERVICE，host 模式下可正常绑定；
// bridge 模式下还需在 compose 映射对应端口。此处仅提示，不阻止保存。
function updatePortNotice() {
  const notice = document.querySelector("#portNotice");
  const low = ["bindPort", "vhostHTTPPort", "vhostHTTPSPort"]
    .filter((name) => Number(form[name].value) > 0 && Number(form[name].value) < 1024);
  if (!low.length) { notice.textContent = ""; return; }
  notice.style.color = "#b07b00";
  notice.textContent = `端口 ${low.join("、")} < 1024 为特权端口，依赖镜像内置的 CAP_NET_BIND_SERVICE（已构建版本自动满足）；bridge 模式下还需在 compose 映射对应端口。`;
}

async function refresh() {
  const [config, status, events] = await Promise.all([request("/api/config"), request("/api/status"), request("/api/events")]);
  form.bindPort.value = config.bindPort; form.vhostHTTPPort.value = config.vhostHTTPPort; form.vhostHTTPSPort.value = config.vhostHTTPSPort; form.authToken.value = config.authToken;
  rows.replaceChildren(); config.domains.forEach((item) => addDomain(item.domain, item.kind, item.enabled));
  document.querySelector("#frpsState").textContent = status.running ? "运行中" : status.configured ? "未运行" : "待配置";
  document.querySelector("#domainCount").textContent = String(status.domains.length);
  document.querySelector("#statusDot").className = `dot ${status.running ? "running" : ""}`;
  document.querySelector("#statusText").textContent = status.running ? `frps 正在运行（PID ${status.pid || "-"}）` : status.lastError || "frps 未运行";
  renderLogs(events);
  updatePortNotice();
}

document.querySelector("#loginForm").onsubmit = async (event) => { event.preventDefault(); try { await request("/api/login", { method: "POST", body: JSON.stringify({ user: document.querySelector("#user").value, password: document.querySelector("#password").value }) }); loginView.classList.add("hidden"); appView.classList.remove("hidden"); await refresh(); } catch (error) { document.querySelector("#loginError").textContent = error.message; } };
document.querySelector("#addDomain").onclick = () => addDomain();
["bindPort", "vhostHTTPPort", "vhostHTTPSPort"].forEach((name) => form[name].addEventListener("input", updatePortNotice));
form.onsubmit = async (event) => { event.preventDefault(); const notice = document.querySelector("#saveNotice"); try { await request("/api/config", { method: "POST", body: JSON.stringify({ bindPort: Number(form.bindPort.value), vhostHTTPPort: Number(form.vhostHTTPPort.value), vhostHTTPSPort: Number(form.vhostHTTPSPort.value), authToken: form.authToken.value, domains: domains() }) }); notice.style.color = "#1b9762"; notice.textContent = "已保存并重启 frps"; await refresh(); } catch (error) { notice.style.color = "#c33d4c"; notice.textContent = error.message; } };
document.querySelector("#restartFrps").onclick = async () => { await request("/api/control/restart", { method: "POST" }); await refresh(); };
document.querySelector("#refresh").onclick = refresh;
document.querySelector("#logout").onclick = async () => { await request("/api/logout", { method: "POST" }); location.reload(); };
