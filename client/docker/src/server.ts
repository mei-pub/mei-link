import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { AuthService } from "./auth.ts";
import { DataStore } from "./store.ts";
import { TunnelManager } from "./manager.ts";

export type MeilinkServerOptions = {
  dataDir?: string;
  frpcBin?: string;
  adminUser?: string;
  adminPassword?: string;
  webDir?: string;
};

function json(response: ServerResponse, status: number, value: unknown) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(value));
}

async function body(request: IncomingMessage): Promise<Record<string, unknown>> {
  let raw = "";
  for await (const chunk of request) {
    raw += chunk;
    if (raw.length > 1024 * 1024) throw new Error("请求过大");
  }
  return JSON.parse(raw || "{}") as Record<string, unknown>;
}

async function sendFile(response: ServerResponse, webDir: string, file: string, type: string) {
  response.writeHead(200, { "content-type": type });
  response.end(await readFile(join(webDir, file)));
}

export async function createMeilinkServer(options: MeilinkServerOptions = {}): Promise<Server> {
  const dataDir = options.dataDir || process.env.MEILINK_DATA_DIR || "/data";
  const webDir = options.webDir || join(import.meta.dirname, "../web");
  const auth = new AuthService(dataDir);
  const manager = new TunnelManager(new DataStore(dataDir), options.frpcBin || process.env.MEILINK_FRPC_PATH || "/usr/local/bin/frpc");
  await auth.initialize({
    ...process.env,
    ...(options.adminUser ? { MEILINK_ADMIN_USER: options.adminUser } : {}),
    ...(options.adminPassword ? { MEILINK_ADMIN_PASSWORD: options.adminPassword } : {}),
  });
  await manager.load();

  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url || "/", "http://localhost");
      if (url.pathname === "/healthz") return json(response, 200, { ok: true });
      if (url.pathname === "/api/login" && request.method === "POST") {
        const input = await body(request);
        const token = await auth.login(String(input.user || ""), String(input.password || ""));
        if (!token) return json(response, 401, { error: "账号或密码错误" });
        response.setHeader("set-cookie", `meilink_session=${token}; HttpOnly; SameSite=Lax; Path=/`);
        return json(response, 200, { ok: true });
      }
      if (url.pathname === "/") return sendFile(response, webDir, "index.html", "text/html; charset=utf-8");
      if (url.pathname === "/app.js") return sendFile(response, webDir, "app.js", "text/javascript; charset=utf-8");
      if (url.pathname === "/api/logout" && request.method === "POST") {
        auth.logout(request.headers.cookie);
        response.setHeader("set-cookie", "meilink_session=; Max-Age=0; Path=/");
        return json(response, 200, { ok: true });
      }
      if (!auth.valid(request.headers.cookie)) return json(response, 401, { error: "请先登录" });
      if (url.pathname === "/api/status" && request.method === "GET") {
        await manager.refreshRuntime();
        return json(response, 200, manager.status());
      }
      if (url.pathname === "/api/events" && request.method === "GET") return json(response, 200, manager.logs());
      if (url.pathname === "/api/events" && request.method === "DELETE") {
        manager.clearLogs();
        return json(response, 200, { ok: true });
      }
      if (url.pathname === "/api/test-connection" && request.method === "POST") {
        const input = await body(request);
        return json(response, 200, await manager.testConnection(String(input.addr || ""), Number(input.port)));
      }
      if (url.pathname === "/api/tunnels" && request.method === "GET") {
        await manager.refreshRuntime();
        return json(response, 200, manager.tunnels());
      }
      if (url.pathname === "/api/tunnels" && request.method === "POST") return json(response, 201, await manager.createTunnel(await body(request)));
      // Kept for existing browser sessions during an upgrade. New UI uses single-tunnel routes below.
      if (url.pathname === "/api/tunnels" && request.method === "PUT") {
        await manager.saveTunnels(await body(request) as unknown as Awaited<ReturnType<typeof manager.tunnels>>);
        return json(response, 200, { ok: true });
      }
      const tunnelRoute = /^\/api\/tunnels\/([^/]+)(\/toggle)?$/.exec(url.pathname);
      if (tunnelRoute) {
        const id = decodeURIComponent(tunnelRoute[1]);
        if (tunnelRoute[2] === "/toggle" && request.method === "POST") {
          const input = await body(request);
          if (typeof input.enabled !== "boolean") throw new Error("enabled 必须是布尔值");
          return json(response, 200, await manager.toggleTunnel(id, input.enabled));
        }
        if (!tunnelRoute[2] && request.method === "PUT") return json(response, 200, await manager.updateTunnel(id, await body(request)));
        if (!tunnelRoute[2] && request.method === "DELETE") {
          await manager.deleteTunnel(id);
          return json(response, 200, { ok: true });
        }
      }
      if (url.pathname === "/api/server-config" && request.method === "GET") return json(response, 200, manager.serverConfig());
      if (url.pathname === "/api/server-config" && request.method === "POST") {
        await manager.saveConfig(await body(request) as never);
        return json(response, 201, { ok: true });
      }
      if (url.pathname === "/api/control/start" && request.method === "POST") {
        await manager.start();
        return json(response, 200, { ok: true });
      }
      if (url.pathname === "/api/control/stop" && request.method === "POST") {
        manager.stop();
        return json(response, 200, { ok: true });
      }
      return json(response, 404, { error: "not found" });
    } catch (error) {
      return json(response, 400, { error: error instanceof Error ? error.message : "请求失败" });
    }
  });
}

const isEntrypoint = process.argv[1] && new URL(`file://${process.argv[1].replace(/\\/g, "/")}`).href === import.meta.url;
if (isEntrypoint) {
  const port = Number(process.env.MEILINK_WEB_PORT || 17420);
  const server = await createMeilinkServer();
  server.listen(port, "0.0.0.0", () => console.log(`Meilink Web: ${port}`));
}
