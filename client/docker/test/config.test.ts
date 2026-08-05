import test from "node:test";
import assert from "node:assert/strict";
import { generateFrpcToml } from "../src/config.ts";

test("generateFrpcToml keeps Admin API local and escapes data paths", () => {
  const toml = generateFrpcToml({
    serverAddr: "frp.example.test",
    serverPort: 7000,
    authToken: "token",
    subDomainHost: "example.test",
    tlsEnabled: true,
    adminPort: 7400,
    adminUser: "admin",
    adminPassword: "admin",
  }, "C:\\data\\meilink");

  assert.match(toml, /webServer\.addr = "127\.0\.0\.1"/);
  assert.match(toml, /transport\.poolCount = 5/);
  assert.match(toml, /path = "C:\\\\data\\\\meilink\\\\store\.json"/);
});
