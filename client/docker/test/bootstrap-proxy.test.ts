import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer as createHttpServer } from "node:http";
import { createMeilinkServer } from "../src/server.ts";

// 模拟服务端管理页（MEILINK_DOMAIN_API_TOKEN = "secret-token"）
async function startMockServer() {
  const server = createHttpServer((request, response) => {
    const url = new URL(request.url || "/", "http://localhost");
    const auth = request.headers.authorization || "";
    const ok = auth === "Bearer secret-token";
    if (url.pathname === "/api/bootstrap") {
      if (!ok) {
        response.writeHead(401, { "content-type": "application/json" });
        return response.end(JSON.stringify({ error: "token 无效" }));
      }
      response.writeHead(200, { "content-type": "application/json" });
      return response.end(JSON.stringify({
        serverAddr: "aicun.cc",
        serverPort: 7758,
        authToken: "frp-token",
        subDomainHost: "tunnel.example.com",
        domains: [{ domain: "tunnel.example.com", kind: "primary" }, { domain: "*.apps.example.com", kind: "wildcard" }],
      }));
    }
    if (url.pathname === "/api/domains") {
      if (!ok) {
        response.writeHead(401, { "content-type": "application/json" });
        return response.end(JSON.stringify({ error: "token 无效" }));
      }
      response.writeHead(200, { "content-type": "application/json" });
      return response.end(JSON.stringify({ domains: [{ domain: "tunnel.example.com", kind: "primary" }, { domain: "*.apps.example.com", kind: "wildcard" }] }));
    }
    response.writeHead(404, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: "not found" }));
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("mock server did not bind");
  return { server, base: `http://127.0.0.1:${address.port}` };
}

async function startApp() {
  const dataDir = await mkdtemp(join(tmpdir(), "meilink-bootstrap-"));
  const server = await createMeilinkServer({ dataDir, frpcBin: "not-used-in-this-test", adminPassword: "test-password" });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("test server did not bind");
  const base = `http://127.0.0.1:${address.port}`;
  const login = await fetch(`${base}/api/login`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ user: "admin", password: "test-password" }) });
  const cookie = login.headers.get("set-cookie")?.split(";", 1)[0];
  assert.equal(login.status, 200);
  return { dataDir, server, base, headers: { cookie, "content-type": "application/json" } };
}

test("bootstrap proxy forwards server info and prefill fields", async () => {
  const mock = await startMockServer();
  const app = await startApp();
  try {
    // 配置管理页地址 + token，触发保存
    const save = await fetch(`${app.base}/api/server-config`, {
      method: "POST", headers: app.headers,
      body: JSON.stringify({
        serverAddr: "", serverPort: 7000, authToken: "", subDomainHost: "",
        tlsEnabled: true, adminPort: 7400, adminUser: "admin", adminPassword: "pw",
        vhostHTTPPort: 8080, vhostHTTPSPort: 8443,
        managementURL: mock.base, domainAPIToken: "secret-token",
      }),
    });
    assert.equal(save.status, 201);

    // 通过 docker 客户端代理端点拉取 bootstrap
    const res = await fetch(`${app.base}/api/bootstrap`, { headers: app.headers });
    assert.equal(res.status, 200);
    const info = await res.json() as { serverAddr: string; serverPort: number; authToken: string; subDomainHost: string; domains: Array<{ domain: string; kind: string }> };
    assert.equal(info.serverAddr, "aicun.cc");
    assert.equal(info.serverPort, 7758);
    assert.equal(info.authToken, "frp-token");
    assert.equal(info.subDomainHost, "tunnel.example.com");
    assert.equal(info.domains.length, 2);

    // 域名目录代理同样可用
    const domains = await (await fetch(`${app.base}/api/domains`, { headers: app.headers })).json() as { domains: Array<{ domain: string }> };
    assert.deepEqual(domains.domains.map(d => d.domain), ["tunnel.example.com", "*.apps.example.com"]);
  } finally {
    await new Promise<void>(resolve => app.server.close(() => resolve()));
    await new Promise<void>(resolve => mock.server.close(() => resolve()));
    await rm(app.dataDir, { recursive: true, force: true });
  }
});

test("bootstrap proxy returns a clear error before any config is saved", async () => {
  const app = await startApp();
  try {
    const res = await fetch(`${app.base}/api/bootstrap`, { headers: app.headers });
    assert.equal(res.status, 200);
    const info = await res.json() as { error?: string };
    assert.match(info.error || "", /未配置/);
  } finally {
    await new Promise<void>(resolve => app.server.close(() => resolve()));
    await rm(app.dataDir, { recursive: true, force: true });
  }
});

test("bootstrap proxy surfaces token errors instead of falling back silently", async () => {
  const mock = await startMockServer();
  const app = await startApp();
  try {
    const save = await fetch(`${app.base}/api/server-config`, {
      method: "POST", headers: app.headers,
      body: JSON.stringify({
        serverAddr: "", serverPort: 7000, authToken: "", subDomainHost: "",
        tlsEnabled: true, adminPort: 7400, adminUser: "admin", adminPassword: "pw",
        vhostHTTPPort: 8080, vhostHTTPSPort: 8443,
        managementURL: mock.base, domainAPIToken: "wrong-token",
      }),
    });
    assert.equal(save.status, 201);

    const res = await fetch(`${app.base}/api/bootstrap`, { headers: app.headers });
    assert.equal(res.status, 200);
    const info = await res.json() as { error?: string };
    assert.match(info.error || "", /token 错误|token/);
  } finally {
    await new Promise<void>(resolve => app.server.close(() => resolve()));
    await new Promise<void>(resolve => mock.server.close(() => resolve()));
    await rm(app.dataDir, { recursive: true, force: true });
  }
});
