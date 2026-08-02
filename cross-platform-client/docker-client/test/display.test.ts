import test from "node:test";
import assert from "node:assert/strict";
import { routeText } from "../src/display.ts";

test("routeText uses frpc remote address for an HTTP tunnel", () => {
  assert.equal(routeText({ type: "http", subdomain: "photo", remoteAddr: "photo.example.test" }, { subDomainHost: "example.test", serverAddr: "frp.example.test" }), "http://photo.example.test");
});

test("routeText derives an HTTPS tunnel route from the configured subdomain host", () => {
  assert.equal(routeText({ type: "https", subdomain: "photos.example.test" }, { subDomainHost: "example.test", serverAddr: "frp.example.test" }), "https://photos.example.test");
});
