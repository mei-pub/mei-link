import test from "node:test";
import assert from "node:assert/strict";
import { toProxyDefinition } from "../src/proxy.ts";

test("toProxyDefinition emits the frpc Store API shape for HTTP tunnels", () => {
  assert.deepEqual(toProxyDefinition({
    id: "photo-id", name: "photo", type: "http", localIP: "127.0.0.1",
    localPort: 5000, subdomain: "photo.example.test", enabled: true,
  }, "example.test"), {
    name: "photo", type: "http",
    http: { localIP: "127.0.0.1", localPort: 5000, subdomain: "photo", locations: ["/"] },
  });
});

test("toProxyDefinition emits the frpc Store API shape for TCP tunnels", () => {
  assert.deepEqual(toProxyDefinition({
    id: "ssh-id", name: "ssh", type: "tcp", localIP: "192.168.1.10",
    localPort: 22, remotePort: 60022, enabled: true,
  }), {
    name: "ssh", type: "tcp",
    tcp: { localIP: "192.168.1.10", localPort: 22, remotePort: 60022 },
  });
});

test("toProxyDefinition preserves the native HTTP routing and authentication fields", () => {
  assert.deepEqual(toProxyDefinition({
    id: "photo-id", name: "photo", type: "http", localIP: "127.0.0.1", localPort: 5000,
    subdomain: "photo.example.test", customDomains: ["photos.example.test"],
    httpUser: "viewer", httpPassword: "secret", hostHeaderRewrite: "photos.internal", enabled: true,
  }, "example.test"), {
    name: "photo", type: "http",
    http: {
      localIP: "127.0.0.1", localPort: 5000, subdomain: "photo", customDomains: ["photos.example.test"],
      locations: ["/"], httpUser: "viewer", httpPassword: "secret", hostHeaderRewrite: "photos.internal",
    },
  });
});
