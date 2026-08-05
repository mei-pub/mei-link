import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createManagementServer } from "../src/server.ts";

test("protects server management and saves a wildcard domain catalog", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "meilink-server-api-"));
  const server = await createManagementServer({
    dataDir,
    environment: { MEILINK_ADMIN_USER: "ops", MEILINK_ADMIN_PASSWORD: "secret" },
    controller: { status: () => ({ running: true, pid: 1 }), restart: async () => {}, stop: async () => {} },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as { port: number }).port;
  const base = `http://127.0.0.1:${port}`;

  try {
    assert.equal((await fetch(`${base}/api/status`)).status, 401);
    const login = await fetch(`${base}/api/login`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ user: "ops", password: "secret" }) });
    const cookie = login.headers.get("set-cookie")!;
    assert.equal(login.status, 200);

    const save = await fetch(`${base}/api/config`, {
      method: "POST",
      headers: { "content-type": "application/json", cookie },
      body: JSON.stringify({ bindPort: 7000, vhostHTTPPort: 8080, vhostHTTPSPort: 8443, authToken: "token", domains: [{ domain: "tunnel.example.com", kind: "primary", enabled: true }, { domain: "*.apps.example.com", kind: "wildcard", enabled: true }] }),
    });
    assert.equal(save.status, 200);
    const status = await (await fetch(`${base}/api/status`, { headers: { cookie } })).json() as { domains: Array<{ domain: string }> };
    assert.equal(status.domains[1].domain, "*.apps.example.com");
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(dataDir, { recursive: true, force: true });
  }
});
