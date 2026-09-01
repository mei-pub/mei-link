import test from "node:test";
import assert from "node:assert/strict";
import { ReconnectController, type ReconnectControllerOptions } from "../src/reconnect.ts";

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

function makeController(overrides: Partial<ReconnectControllerOptions> = {}) {
  const calls = { probe: 0, restart: 0 };
  const logs: Array<{ message: string; level?: string }> = [];
  const { probe, restart, ...rest } = overrides;
  const controller = new ReconnectController({
    // 测试不靠周期定时器，全部手动 check() / kick()。
    reconnectIntervalMs: 60_000,
    maxReconnectAttempts: 3,
    maxRestartAttempts: 3,
    probe: () => { calls.probe++; return probe ? probe() : { alive: true, connected: true }; },
    restart: async () => { calls.restart++; return restart ? await restart() : true; },
    onLog: (message, level) => logs.push({ message, level }),
    kickDelayMs: 10,
    ...rest,
  });
  return { controller, calls, logs };
}

test("healthy connection stays active and never restarts", async () => {
  const { controller, calls } = makeController();
  controller.start();
  for (let i = 0; i < 5; i++) await controller.check();
  assert.equal(controller.currentState(), "active");
  assert.equal(calls.restart, 0);
  controller.stop();
});

test("reconnect failures escalate to a restart after maxReconnectAttempts", async () => {
  const { controller, calls } = makeController({
    maxReconnectAttempts: 3,
    probe: () => ({ alive: true, connected: false }),
    restart: async () => false,
  });
  controller.start();
  await controller.check();
  await controller.check();
  assert.equal(controller.currentState(), "reconnecting");
  assert.equal(controller.reconnectAttempts(), 2);
  assert.equal(calls.restart, 0);
  await controller.check(); // 第 3 次失败 → 升级为重启（重启失败，未耗尽）
  assert.equal(calls.restart, 1);
  assert.equal(controller.reconnectAttempts(), 0);
  assert.equal(controller.restartAttempts(), 1);
  assert.equal(controller.currentState(), "reconnecting");
  controller.stop();
});

test("a successful restart resets both counters", async () => {
  const { controller, calls } = makeController({
    maxReconnectAttempts: 2,
    probe: () => ({ alive: true, connected: false }),
  });
  controller.start();
  await controller.check(); // 第 1 次失败
  await controller.check(); // 第 2 次失败 → 重启成功
  assert.equal(calls.restart, 1);
  assert.equal(controller.currentState(), "active");
  assert.equal(controller.restartAttempts(), 0);
  assert.equal(controller.reconnectAttempts(), 0);
  controller.stop();
});

test("failed restarts give up after maxRestartAttempts", async () => {
  const { controller, calls } = makeController({
    maxReconnectAttempts: 2,
    maxRestartAttempts: 2,
    probe: () => ({ alive: true, connected: false }),
    restart: async () => false,
  });
  controller.start();
  for (let i = 0; i < 20 && controller.currentState() !== "failed"; i++) await controller.check();
  assert.equal(controller.currentState(), "failed");
  assert.equal(calls.restart, 2);
  assert.equal(controller.restartAttempts(), 2);
  // 放弃后不再自动重启
  await controller.check();
  assert.equal(calls.restart, 2);
  controller.stop();
});

test("after giving up, a self-recovered connection clears the failed state", async () => {
  let connected = false;
  const { controller, calls } = makeController({
    maxReconnectAttempts: 1,
    maxRestartAttempts: 1,
    probe: () => ({ alive: true, connected }),
    restart: async () => false,
  });
  controller.start();
  // 首次探测失败 → 重启 → 重启失败 → 放弃
  await controller.check();
  assert.equal(controller.currentState(), "failed");
  assert.equal(calls.restart, 1);
  // 连接自行恢复（如 frpc 重新登录成功）→ 下一次探测自动解除失败态
  connected = true;
  await controller.check();
  assert.equal(controller.currentState(), "active");
  assert.equal(controller.restartAttempts(), 0);
  controller.stop();
});

test("an exited process restarts immediately without counting reconnect failures", async () => {
  const { controller, calls } = makeController({
    probe: () => ({ alive: false, connected: false }),
  });
  controller.start();
  await controller.check();
  assert.equal(calls.restart, 1);
  assert.equal(controller.reconnectAttempts(), 0);
  assert.equal(controller.currentState(), "active"); // 重启成功
  controller.stop();
});

test("kick schedules an early check after an unexpected exit", async () => {
  const { controller, calls } = makeController({
    probe: () => ({ alive: false, connected: false }),
  });
  controller.start();
  controller.kick();
  await sleep(60);
  assert.equal(calls.restart, 1);
  controller.stop();
});

test("start is idempotent and a controller can be restarted after stop", async () => {
  const { controller, calls } = makeController();
  controller.start();
  controller.start(); // 幂等：不会重复启动周期定时器
  await controller.check();
  assert.equal(calls.probe, 1);
  controller.stop();
  assert.equal(controller.currentState(), "idle");
  controller.start();
  assert.equal(controller.currentState(), "active");
  controller.stop();
});

test("stop disarms the controller and check becomes a no-op", async () => {
  const { controller, calls } = makeController({
    probe: () => ({ alive: false, connected: false }),
  });
  controller.start();
  controller.stop();
  assert.equal(controller.currentState(), "idle");
  await controller.check();
  assert.equal(calls.restart, 0);
});
