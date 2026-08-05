import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { EnvironmentAuth } from "./auth.ts";
import { ServerManager, type FrpsController } from "./manager.ts";
import type { ServerConfig } from "./config.ts";

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

export async function createManagementServer(options: ServerOptions = {}): Promise<Server> {
  const environment = options.environment || process.env;
  const auth = new EnvironmentAuth(environment);
  const manager = new ServerManager({ dataDir: options.dataDir, environment, controller: options.controller });
  const webDir = options.webDir || join(import.meta.dirname, "../web");
  await manager.load();

  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url || "/", "http://localhost");
      if (url.pathname === "/healthz") return json(response, 200, { ok: true });
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
