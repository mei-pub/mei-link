import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { AuthService } from "./auth.ts";
import { DataStore } from "./store.ts";
import { TunnelManager } from "./manager.ts";

const data = process.env.MEILINK_DATA_DIR || "/data";
const web = join(import.meta.dirname, "../web");
const port = Number(process.env.MEILINK_WEB_PORT || 17420);
const auth = new AuthService(data);
const manager = new TunnelManager(new DataStore(data), process.env.MEILINK_FRPC_PATH || "/usr/local/bin/frpc");
await auth.initialize();
await manager.load();

function json(response: ServerResponse, status: number, value: unknown) { response.writeHead(status, { "content-type": "application/json; charset=utf-8" }); response.end(JSON.stringify(value)); }
async function body(request: IncomingMessage) {
  let raw = "";
  for await (const chunk of request) { raw += chunk; if (raw.length > 1024 * 1024) throw new Error("请求过大"); }
  return JSON.parse(raw || "{}");
}
async function sendFile(response: ServerResponse, file: string, type: string) { response.writeHead(200, { "content-type": type }); response.end(await readFile(join(web, file))); }

createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", "http://localhost");
    if (url.pathname === "/healthz") return json(response, 200, { ok: true });
    if (url.pathname === "/api/login" && request.method === "POST") {
      const input = await body(request);
      const token = await auth.login(input.user, input.password);
      if (!token) return json(response, 401, { error: "账号或密码错误" });
      response.setHeader("set-cookie", `meilink_session=${token}; HttpOnly; SameSite=Lax; Path=/`);
      return json(response, 200, { ok: true });
    }
    if (url.pathname === "/") return sendFile(response, "index.html", "text/html; charset=utf-8");
    if (url.pathname === "/app.js") return sendFile(response, "app.js", "text/javascript; charset=utf-8");
    if (url.pathname === "/api/logout" && request.method === "POST") { auth.logout(request.headers.cookie); response.setHeader("set-cookie", "meilink_session=; Max-Age=0; Path=/"); return json(response, 200, { ok: true }); }
    if (!auth.valid(request.headers.cookie)) return json(response, 401, { error: "请先登录" });
    if (url.pathname === "/api/status" && request.method === "GET") { await manager.refreshRuntime(); return json(response, 200, manager.status()); }
    if (url.pathname === "/api/events" && request.method === "GET") return json(response, 200, manager.logs());
    if (url.pathname === "/api/tunnels" && request.method === "GET") { await manager.refreshRuntime(); return json(response, 200, manager.tunnels()); }
    if (url.pathname === "/api/tunnels" && request.method === "PUT") { await manager.saveTunnels(await body(request)); return json(response, 200, { ok: true }); }
    if (url.pathname === "/api/server-config" && request.method === "GET") return json(response, 200, manager.serverConfig());
    if (url.pathname === "/api/server-config" && request.method === "POST") { await manager.saveConfig(await body(request)); return json(response, 201, { ok: true }); }
    if (url.pathname === "/api/control/start" && request.method === "POST") { await manager.start(); return json(response, 200, { ok: true }); }
    if (url.pathname === "/api/control/stop" && request.method === "POST") { manager.stop(); return json(response, 200, { ok: true }); }
    return json(response, 404, { error: "not found" });
  } catch (error) {
    return json(response, 400, { error: error instanceof Error ? error.message : "请求失败" });
  }
}).listen(port, "0.0.0.0", () => console.log(`Meilink Web: ${port}`));
