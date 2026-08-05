import assert from "node:assert/strict";
import { waitForApiReady } from "../src/lib/sidecar-ready.js";

const startedAt = Date.now();
await assert.rejects(
  waitForApiReady({
    getApiUrl: async () => "",
    attempts: 3,
    retryDelayMs: 5,
  }),
  /本地服务未能启动/,
);
assert.ok(
  Date.now() - startedAt < 200,
  "the readiness wait must be bounded rather than leaving UI actions pending forever",
);

console.log("sidecar-ready: unavailable sidecar fails within the configured retry budget");
