import assert from "node:assert/strict";
import test from "node:test";
import { normalizeDomains, renderFrpsToml } from "../src/config.ts";

test("normalizes primary, additional, and wildcard server domains", () => {
  const domains = normalizeDomains([
    { domain: "Tunnel.Example.com.", kind: "primary", enabled: true },
    { domain: "apps.example.com", kind: "custom", enabled: true },
    { domain: "*.Apps.Example.com", kind: "wildcard", enabled: true },
    { domain: "*.apps.example.com", kind: "wildcard", enabled: true },
  ]);

  assert.deepEqual(domains, [
    { domain: "tunnel.example.com", kind: "primary", enabled: true },
    { domain: "apps.example.com", kind: "custom", enabled: true },
    { domain: "*.apps.example.com", kind: "wildcard", enabled: true },
  ]);
});

test("renders one frps primary subdomain host while retaining the full domain catalog", () => {
  const config = {
    bindPort: 7000,
    vhostHTTPPort: 8080,
    vhostHTTPSPort: 8443,
    authToken: "server-token",
    domains: [
      { domain: "tunnel.example.com", kind: "primary" as const, enabled: true },
      { domain: "apps.example.com", kind: "custom" as const, enabled: true },
      { domain: "*.apps.example.com", kind: "wildcard" as const, enabled: true },
    ],
  };

  const toml = renderFrpsToml(config);
  assert.match(toml, /subDomainHost = "tunnel\.example\.com"/);
  assert.match(toml, /vhostHTTPPort = 8080/);
  assert.match(toml, /auth\.token = "server-token"/);
  assert.doesNotMatch(toml, /apps\.example\.com/);
});

test("rejects wildcard primary domains and malformed wildcard labels", () => {
  assert.throws(() => normalizeDomains([{ domain: "*.example.com", kind: "primary", enabled: true }]), /主域名/);
  assert.throws(() => normalizeDomains([{ domain: "api.*.example.com", kind: "wildcard", enabled: true }]), /泛域名/);
});

test("rejects custom domains that collide with the primary subdomain host", () => {
  assert.throws(() => normalizeDomains([
    { domain: "tunnel.example.com", kind: "primary", enabled: true },
    { domain: "*.tunnel.example.com", kind: "wildcard", enabled: true },
  ]), /主域名/);
});
