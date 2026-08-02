import test from "node:test";
import assert from "node:assert/strict";
import { cleanFrpcLogLine, isFrpcLoginSuccess } from "../src/frpc-log.ts";

test("cleanFrpcLogLine removes terminal control codes from frpc output", () => {
  assert.equal(
    cleanFrpcLogLine("\u001b[0m\u001b[1;34m2026-08-02 [I] [client/service.go:328] login to server success"),
    "2026-08-02 [I] [client/service.go:328] login to server success",
  );
});

test("cleanFrpcLogLine omits noisy local Admin API request logs", () => {
  assert.equal(cleanFrpcLogLine("2026-08-02 [I] [http/middleware.go:35] http request: [/api/status]"), null);
});

test("isFrpcLoginSuccess identifies the server login event", () => {
  assert.equal(isFrpcLoginSuccess("2026-08-02 [I] [client/service.go:328] login to server success, get run id [abc]"), true);
  assert.equal(isFrpcLoginSuccess("2026-08-02 [I] [client/service.go:308] try to connect to server..."), false);
});
