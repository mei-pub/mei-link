import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { EnvironmentAuth, DomainApiToken } from "./auth.ts";
import { ServerManager, type FrpsController } from "./manager.ts";
import { dashboardConfig, type ServerConfig } from "./config.ts";

type ServerOptions = {
  dataDir?: string;
  webDir?: string;
  environment?: Record<string, string | undefined>;
  controller?: FrpsController;
};

function json(response: ServerResponse, status: number, value: unknown) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(value));
}

async function body(request: IncomingMessage): Promise<Record<string, unknown>> {
  let raw = "";
  for await (const chunk of request) {
    raw += chunk;
    if (raw.length > 1_048_576) throw new Error("请求过大");
  }
  return JSON.parse(raw || "{}") as Record<string, unknown>;
}

async function sendFile(response: ServerResponse, path: string, contentType: string) {
  response.writeHead(200, { "content-type": contentType, "cache-control": "no-store" });
  response.end(await readFile(path));
}

/// 代理请求 frps dashboard API。dashboard 只在容器内 127.0.0.1，外部访问不到，
/// 管理页通过本端点中转拉取 frps 的 proxy/serverinfo 数据。
/// 用 dashboardConfig() 的凭据做 Basic Auth。失败返回 null（端点转成降级响应）。
async function fetchFrpsDashboard(path: string): Promise<unknown | null> {
  const dash = dashboardConfig();
  const url = `http://${dash.addr}:${dash.port}${path}`;
  const auth = "Basic " + Buffer.from(`${dash.user}:${dash.password}`).toString("base64");
  try {
    const res = await fetch(url, { headers: { authorization: auth }, signal: AbortSignal.timeout(3000) });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

export async function createManagementServer(options: ServerOptions = {}): Promise<Server> {
  const environment = options.environment || process.env;
  const auth = new EnvironmentAuth(environment);
  const domainApiToken = new DomainApiToken(environment);
  const manager = new ServerManager({ dataDir: options.dataDir, environment, controller: options.controller });
  const webDir = options.webDir || join(import.meta.dirname, "../web");
  await manager.load();

  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url || "/", "http://localhost");
      if (url.pathname === "/healthz") return json(response, 200, { ok: true });
      // /api/domains：供客户端拉取域名目录（用于隧道编辑「选基域+填前缀」交互）。
      // 独立 Bearer token 认证（MEILINK_DOMAIN_API_TOKEN），不走管理页登录会话。
      // 未配置 token 时端点禁用（404），只返回 enabled 域名，不含敏感信息。
      if (url.pathname === "/api/domains" && request.method === "GET") {
        if (!domainApiToken.configured) return json(response, 404, { error: "域名目录接口未启用" });
        if (!domainApiToken.valid(request.headers.authorization || "")) return json(response, 401, { error: "token 无效" });
        const domains = manager.currentConfig().domains.filter((d) => d.enabled).map((d) => ({ domain: d.domain, kind: d.kind }));
        return json(response, 200, { domains });
      }
      // /api/bootstrap：客户端首次配置时一次性拉取所有启动信息（frps 地址/端口/token/
      // 子域名基域/域名目录）。复用 MEILINK_DOMAIN_API_TOKEN 认证，与 /api/domains 同 token。
      // 让客户端 SetupView 只需填「管理页地址 + token」两个字段。
      if (url.pathname === "/api/bootstrap" && request.method === "GET") {
        if (!domainApiToken.configured) return json(response, 404, { error: "启动信息接口未启用" });
        if (!domainApiToken.valid(request.headers.authorization || "")) return json(response, 401, { error: "token 无效" });
        const cfg = manager.currentConfig();
        const primary = cfg.domains.find((d) => d.kind === "primary" && d.enabled)?.domain || "";
        const domains = cfg.domains.filter((d) => d.enabled).map((d) => ({ domain: d.domain, kind: d.kind }));
        return json(response, 200, {
          serverAddr: cfg.serverAddr || "",
          serverPort: cfg.bindPort,
          authToken: cfg.authToken,
          subDomainHost: primary,
          domains,
        });
      }
      if (url.pathname === "/api/login" && request.method === "POST") {
        const input = await body(request);
        const token = auth.login(String(input.user || ""), String(input.password || ""));
        if (!token) return json(response, 401, { error: "账号或密码错误" });
        response.setHeader("set-cookie", `meilink_server_session=${token}; HttpOnly; SameSite=Lax; Path=/`);
        return json(response, 200, { ok: true });
      }
      if (url.pathname === "/" && request.method === "GET") return sendFile(response, join(webDir, "index.html"), "text/html; charset=utf-8");
      if (url.pathname === "/app.js" && request.method === "GET") return sendFile(response, join(webDir, "app.js"), "text/javascript; charset=utf-8");
      if (url.pathname === "/api/logout" && request.method === "POST") {
        auth.logout(request.headers.cookie);
        response.setHeader("set-cookie", "meilink_server_session=; Max-Age=0; Path=/");
        return json(response, 200, { ok: true });
      }
      if (!auth.valid(request.headers.cookie)) return json(response, 401, { error: "请先登录" });
      if (url.pathname === "/api/status" && request.method === "GET") return json(response, 200, manager.status());
      if (url.pathname === "/api/config" && request.method === "GET") return json(response, 200, manager.currentConfig());
      if (url.pathname === "/api/config" && request.method === "POST") return json(response, 200, await manager.save(await body(request) as unknown as ServerConfig));
      if (url.pathname === "/api/control/restart" && request.method === "POST") { await manager.restart(); return json(response, 200, { ok: true }); }
      if (url.pathname === "/api/control/stop" && request.method === "POST") { await manager.stop(); return json(response, 200, { ok: true }); }
      if (url.pathname === "/api/events" && request.method === "GET") return json(response, 200, manager.logs());
      // frps dashboard 代理：拉取 frps 的 serverinfo / proxies，供管理页「隧道状态」展示。
      // dashboard 未就绪或未启用时返回降级（{error, ...}），前端友好处理。
      if (url.pathname === "/api/frps/serverinfo" && request.method === "GET") {
        const data = await fetchFrpsDashboard("/api/serverinfo");
        return json(response, 200, data ?? { error: "dashboard 暂不可用", serverinfo: null });
      }
      if (url.pathname === "/api/frps/proxies" && request.method === "GET") {
        // 合并四种 proxy 类型的列表
        const types = ["tcp", "udp", "http", "https"];
        const results = await Promise.all(types.map(async (t) => [t, await fetchFrpsDashboard(`/api/proxy/${t}`)] as const));
        const merged: Record<string, unknown> = {};
        let anyOk = false;
        for (const [t, data] of results) {
          if (data && typeof data === "object") { merged[t] = data; anyOk = true; }
          else merged[t] = [];
        }
        return json(response, 200, anyOk ? { proxies: merged } : { error: "dashboard 暂不可用", proxies: {} });
      }
      return json(response, 404, { error: "not found" });
    } catch (error) {
      return json(response, 400, { error: error instanceof Error ? error.message : "请求失败" });
    }
  });
}

const isEntrypoint = process.argv[1] && new URL(`file://${process.argv[1].replace(/\\/g, "/")}`).href === import.meta.url;
if (isEntrypoint) {
  const port = Number(process.env.MEILINK_WEB_PORT || 17500);
  const server = await createManagementServer();
  server.listen(port, "0.0.0.0", () => console.log(`Meilink Server Management: ${port}`));
}
