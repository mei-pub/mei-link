import test from "node:test";
import assert from "node:assert/strict";
import { mergeRuntimeStatus } from "../src/runtime-status.ts";

test("mergeRuntimeStatus attaches frpc state and remote address to its tunnel", () => {
  const tunnels = [{ id: "photo", name: "photo", type: "http", localIP: "127.0.0.1", localPort: 5000, enabled: true }];
  const result = mergeRuntimeStatus(tunnels, { http: [{ name: "photo", status: "running", remote_addr: "photo.example.test", err: "" }] });
  assert.deepEqual(result, [{ ...tunnels[0], runtimeStatus: "running", remoteAddr: "photo.example.test", errorMessage: "" }]);
});

test("mergeRuntimeStatus marks disabled tunnels as closed without an frpc response", () => {
  const tunnel = { id: "ssh", name: "ssh", type: "tcp", localIP: "127.0.0.1", localPort: 22, enabled: false };
  assert.deepEqual(mergeRuntimeStatus([tunnel], {}), [{ ...tunnel, runtimeStatus: "closed", remoteAddr: "", errorMessage: "" }]);
});
