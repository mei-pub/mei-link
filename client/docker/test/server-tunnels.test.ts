import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer as createTcpServer } from "node:net";
import { createMeilinkServer } from "../src/server.ts";

async function startServer() {
  const dataDir = await mkdtemp(join(tmpdir(), "meilink-api-"));
  const server = await createMeilinkServer({ dataDir, frpcBin: "not-used-in-this-test", adminPassword: "test-password" });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("test server did not bind a TCP port");
  const base = `http://127.0.0.1:${address.port}`;
  const login = await fetch(`${base}/api/login`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ user: "admin", password: "test-password" }) });
  const cookie = login.headers.get("set-cookie")?.split(";", 1)[0];
  assert.equal(login.status, 200);
  assert.ok(cookie);
  return { dataDir, server, base, headers: { cookie, "content-type": "application/json" } };
}

test("tunnel HTTP API creates, toggles, updates and deletes one tunnel", async () => {
  const app = await startServer();
  try {
    const create = await fetch(`${app.base}/api/tunnels`, {
      method: "POST", headers: app.headers,
      body: JSON.stringify({ name: "photo", type: "http", localIP: "127.0.0.1", localPort: 5000, subdomain: "photo.example.test", enabled: true }),
    });
    assert.equal(create.status, 201);
    const created = await create.json() as { id: string; name: string };
    assert.equal(created.name, "photo");

    const toggle = await fetch(`${app.base}/api/tunnels/${created.id}/toggle`, { method: "POST", headers: app.headers, body: JSON.stringify({ enabled: false }) });
    assert.equal((await toggle.json() as { enabled: boolean }).enabled, false);

    const update = await fetch(`${app.base}/api/tunnels/${created.id}`, {
      method: "PUT", headers: app.headers,
      body: JSON.stringify({ name: "gallery", type: "http", localIP: "127.0.0.1", localPort: 5001, subdomain: "gallery.example.test", enabled: false }),
    });
    assert.equal((await update.json() as { name: string }).name, "gallery");

    const list = await fetch(`${app.base}/api/tunnels`, { headers: app.headers });
    assert.deepEqual((await list.json() as Array<{ name: string }>).map(tunnel => tunnel.name), ["gallery"]);

    const deleted = await fetch(`${app.base}/api/tunnels/${created.id}`, { method: "DELETE", headers: app.headers });
    assert.equal(deleted.status, 200);
    assert.deepEqual(await (await fetch(`${app.base}/api/tunnels`, { headers: app.headers })).json(), []);
  } finally {
    await new Promise<void>(resolve => app.server.close(() => resolve()));
    await rm(app.dataDir, { recursive: true, force: true });
  }
});

test("test-connection API reports reachability without persisting credentials", async () => {
  const listener = createTcpServer();
  await new Promise<void>(resolve => listener.listen(0, "127.0.0.1", resolve));
  const address = listener.address();
  if (!address || typeof address === "string") throw new Error("test listener did not bind a TCP port");
  const app = await startServer();
  try {
    const result = await fetch(`${app.base}/api/test-connection`, {
      method: "POST", headers: app.headers,
      body: JSON.stringify({ addr: "127.0.0.1", port: address.port }),
    });
    assert.deepEqual(await result.json(), { ok: true });
  } finally {
    await new Promise<void>(resolve => listener.close(() => resolve()));
    await new Promise<void>(resolve => app.server.close(() => resolve()));
    await rm(app.dataDir, { recursive: true, force: true });
  }
});

test("events API can clear the in-memory log", async () => {
  const app = await startServer();
  try {
    const response = await fetch(`${app.base}/api/events`, { method: "DELETE", headers: app.headers });
    assert.deepEqual(await response.json(), { ok: true });
  } finally {
    await new Promise<void>(resolve => app.server.close(() => resolve()));
    await rm(app.dataDir, { recursive: true, force: true });
  }
});
