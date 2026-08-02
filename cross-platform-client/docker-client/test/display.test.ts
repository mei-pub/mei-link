import test from "node:test";
import assert from "node:assert/strict";
import { routeText } from "../src/display.ts";

test("routeText uses the default frps HTTP vhost port for an HTTP tunnel", () => {
  assert.equal(routeText({ type: "http", subdomain: "photo", remoteAddr: "photo.example.test" }, { subDomainHost: "example.test", serverAddr: "frp.example.test" }), "http://photo.example.test:8080");
});

test("routeText uses the default frps HTTPS vhost port for an HTTPS tunnel", () => {
  assert.equal(routeText({ type: "https", subdomain: "photos.example.test" }, { subDomainHost: "example.test", serverAddr: "frp.example.test" }), "https://photos.example.test:8443");
});

test("routeText keeps a complete frpc public URL instead of prefixing it twice", () => {
  assert.equal(routeText({ type: "http", remoteAddr: "https://photo.example.test" }, { subDomainHost: "example.test" }), "https://photo.example.test");
});

test("routeText includes the configured frps HTTP vhost port", () => {
  assert.equal(routeText({ type: "http", subdomain: "photo" }, { subDomainHost: "example.test", vhostHTTPPort: 8080 }), "http://photo.example.test:8080");
});

test("routeText includes the configured frps HTTPS vhost port but omits standard port 443", () => {
  assert.equal(routeText({ type: "https", subdomain: "photo" }, { subDomainHost: "example.test", vhostHTTPSPort: 8443 }), "https://photo.example.test:8443");
  assert.equal(routeText({ type: "https", subdomain: "photo" }, { subDomainHost: "example.test", vhostHTTPSPort: 443 }), "https://photo.example.test");
});
