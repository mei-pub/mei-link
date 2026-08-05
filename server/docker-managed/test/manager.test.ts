import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { ServerManager } from "../src/manager.ts";

test("saves the domain catalog, renders frps TOML, and restarts frps", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "meilink-server-"));
  let restartCount = 0;
  const manager = new ServerManager({
    dataDir,
    environment: { MEILINK_FRPS_TOKEN: "initial-token" },
    controller: { status: () => ({ running: false }), restart: async () => { restartCount += 1; }, stop: async () => {} },
  });

  try {
    await manager.load();
    restartCount = 0;
    const saved = await manager.save({
      bindPort: 7000,
      vhostHTTPPort: 8080,
      vhostHTTPSPort: 8443,
      authToken: "updated-token",
      domains: [
        { domain: "tunnel.example.com", kind: "primary", enabled: true },
        { domain: "*.apps.example.com", kind: "wildcard", enabled: true },
      ],
    });

    assert.equal(saved.domains[1].domain, "*.apps.example.com");
    assert.equal(restartCount, 1);
    const toml = await readFile(join(dataDir, "frps.toml"), "utf8");
    assert.match(toml, /subDomainHost = "tunnel\.example\.com"/);
    assert.match(toml, /auth\.token = "updated-token"/);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});
