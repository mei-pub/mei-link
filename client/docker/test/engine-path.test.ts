import test from "node:test";
import assert from "node:assert/strict";
import { resolveEnginePath } from "../src/server.ts";

// MEILINK_FRPC_PATH 已作废（v0.0.14）：NAS/旧教程曾把外部值覆盖成
// 不存在的 /usr/local/bin/frpc 导致 spawn ENOENT。环境变量必须彻底失效。
test("MEILINK_FRPC_PATH is retired: external values are ignored entirely", () => {
  process.env.MEILINK_FRPC_PATH = "/usr/local/bin/frpc";
  try {
    assert.equal(resolveEnginePath(), "/usr/local/bin/meilink-tunnel");
  } finally {
    delete process.env.MEILINK_FRPC_PATH;
  }
});

test("explicit override (test injection) still wins over the built-in path", () => {
  assert.equal(resolveEnginePath("/custom/engine"), "/custom/engine");
});

test("no env and no override resolves to the built-in engine", () => {
  delete process.env.MEILINK_FRPC_PATH;
  assert.equal(resolveEnginePath(), "/usr/local/bin/meilink-tunnel");
});
