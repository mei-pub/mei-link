import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TunnelManager } from "../src/manager.ts";
import { DataStore } from "../src/store.ts";

async function managerForTest() {
  const dir = await mkdtemp(join(tmpdir(), "meilink-tunnels-"));
  const manager = new TunnelManager(new DataStore(dir), "not-used-in-this-test");
  await manager.load();
  return { dir, manager };
}

const photo = {
  name: "photo", type: "http" as const, localIP: "127.0.0.1", localPort: 5000,
  subdomain: "photo.example.test", customDomains: ["photos.example.test"],
  httpUser: "viewer", httpPassword: "secret", hostHeaderRewrite: "photos.internal",
  enabled: true,
};

test("TunnelManager creates, updates and persists one tunnel at a time", async () => {
  const { dir, manager } = await managerForTest();
  try {
    const created = await manager.createTunnel(photo);
    assert.match(created.id, /^[0-9a-f-]{36}$/);
    assert.equal(created.runtimeStatus, "new");
    assert.equal(manager.tunnels()[0].subdomain, "photo.example.test");

    const updated = await manager.updateTunnel(created.id, { ...photo, name: "gallery", localPort: 5001 });
    assert.equal(updated.name, "gallery");
    assert.equal(manager.tunnels()[0].localPort, 5001);

    const afterReload = new TunnelManager(new DataStore(dir), "not-used-in-this-test");
    await afterReload.load();
    assert.equal(afterReload.tunnels()[0].name, "gallery");
    assert.equal(afterReload.tunnels()[0].customDomains?.[0], "photos.example.test");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("TunnelManager changes only the selected tunnel enabled state and deletes it", async () => {
  const { dir, manager } = await managerForTest();
  try {
    const first = await manager.createTunnel(photo);
    const second = await manager.createTunnel({ ...photo, name: "ssh", type: "tcp", subdomain: undefined, localPort: 22, remotePort: 60022 });
    const disabled = await manager.toggleTunnel(first.id, false);
    assert.equal(disabled.enabled, false);
    assert.equal(disabled.runtimeStatus, "closed");
    assert.equal(manager.tunnels().find(tunnel => tunnel.id === second.id)?.enabled, true);

    await manager.deleteTunnel(second.id);
    assert.deepEqual(manager.tunnels().map(tunnel => tunnel.name), ["photo"]);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("TunnelManager rejects duplicate tunnel names and invalid local ports", async () => {
  const { dir, manager } = await managerForTest();
  try {
    await manager.createTunnel(photo);
    await assert.rejects(() => manager.createTunnel({ ...photo, name: "photo" }), /名称已存在/);
    await assert.rejects(() => manager.createTunnel({ ...photo, name: "broken", localPort: 0 }), /本地端口/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("TunnelManager preserves an HTTP password when an edit leaves it blank", async () => {
  const { dir, manager } = await managerForTest();
  try {
    const created = await manager.createTunnel(photo);
    const updated = await manager.updateTunnel(created.id, { ...photo, localPort: 5001, httpPassword: "" });
    assert.equal(updated.httpPassword, "secret");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("TunnelManager rejects a wildcard custom domain under the configured subdomain root", async () => {
  const { dir, manager } = await managerForTest();
  try {
    await manager.saveConfig({
      serverAddr: "frp.example.test", serverPort: 7000, authToken: "token", subDomainHost: "example.test",
      tlsEnabled: true, adminPort: 7400, adminUser: "admin", adminPassword: "password", vhostHTTPPort: 8080, vhostHTTPSPort: 8443,
    });
    await assert.rejects(() => manager.createTunnel({ ...photo, customDomains: ["*.example.test"] }), /泛域名/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("TunnelManager applies auto-reconnect defaults and clamps out-of-range values", async () => {
  const { dir, manager } = await managerForTest();
  try {
    await manager.saveConfig({
      serverAddr: "frp.example.test", serverPort: 7000, authToken: "token", subDomainHost: "example.test",
      tlsEnabled: true, adminPort: 7400, adminUser: "admin", adminPassword: "password", vhostHTTPPort: 8080, vhostHTTPSPort: 8443,
    });
    const defaults = manager.serverConfig()!;
    assert.equal(defaults.reconnectInterval, 10);
    assert.equal(defaults.maxReconnectAttempts, 3);
    assert.equal(defaults.maxRestartAttempts, 3);

    await manager.saveConfig({
      serverAddr: "frp.example.test", serverPort: 7000, authToken: "token", subDomainHost: "example.test",
      tlsEnabled: true, adminPort: 7400, adminUser: "admin", adminPassword: "password", vhostHTTPPort: 8080, vhostHTTPSPort: 8443,
      reconnectInterval: 1, maxReconnectAttempts: 0, maxRestartAttempts: 99,
    });
    const clamped = manager.serverConfig()!;
    assert.equal(clamped.reconnectInterval, 3);
    assert.equal(clamped.maxReconnectAttempts, 1);
    assert.equal(clamped.maxRestartAttempts, 30);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
