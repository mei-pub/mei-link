import assert from "node:assert/strict";
import { normalizeStatus, normalizeSubdomain, routeText, tunnelStatus } from "../src/lib/display.js";

assert.equal(normalizeStatus("waitStart"), "wait_start");
assert.equal(normalizeStatus("startError"), "start_error");
assert.equal(normalizeStatus("checkFailed"), "check_failed");
assert.equal(tunnelStatus({ status: "waitStart" }), "wait_start");
assert.equal(tunnelStatus({ runtimeStatus: "running", status: "closed" }), "running");

assert.equal(normalizeSubdomain(" web.tunnel.example.test ", "tunnel.example.test"), "web");
assert.equal(normalizeSubdomain("tunnel.example.test", "tunnel.example.test"), "tunnel.example.test");
assert.equal(normalizeSubdomain("web", "tunnel.example.test"), "web");
assert.equal(normalizeSubdomain("   ", "tunnel.example.test"), "");

assert.equal(
  routeText({ type: "http", subdomain: "web.tunnel.example.test" }, { subDomainHost: "tunnel.example.test" }),
  "http://web.tunnel.example.test",
);
assert.equal(
  routeText({ type: "https", remoteAddr: "live.tunnel.example.test" }, { subDomainHost: "tunnel.example.test" }),
  "https://live.tunnel.example.test",
);
assert.equal(routeText({ type: "tcp", remotePort: 9000 }, {}), "服务器:9000");
assert.equal(routeText({ type: "udp" }, { serverAddr: "frp.example.test" }), "等待分配远程端口");

console.log("display-helpers: Swift-compatible display helpers verified");
