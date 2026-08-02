import assert from "node:assert/strict";
import test from "node:test";
import { EnvironmentAuth } from "../src/auth.ts";

test("uses Docker environment credentials for each management login", () => {
  const auth = new EnvironmentAuth({ MEILINK_ADMIN_USER: "ops", MEILINK_ADMIN_PASSWORD: "secret" });
  assert.equal(auth.login("ops", "wrong"), null);
  const token = auth.login("ops", "secret");
  assert.ok(token);
  assert.equal(auth.valid(`meilink_server_session=${token}`), true);
  auth.logout(`meilink_server_session=${token}`);
  assert.equal(auth.valid(`meilink_server_session=${token}`), false);
});

test("fails closed without explicit Docker environment credentials", () => {
  assert.throws(() => new EnvironmentAuth({}), /MEILINK_ADMIN_USER/);
});
