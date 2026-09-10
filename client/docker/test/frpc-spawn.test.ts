import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FrpcProcess } from "../src/frpc.ts";

// spawn 失败（引擎路径不存在）只 emit 'error' 不 emit 'exit'：
// 不收敛的话会成为 unhandled error 崩掉整个 node 服务（容器无限重启循环）。
test("spawn failure converges to onExit with a readable reason instead of crashing", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "meilink-frpc-"));
  try {
    const configPath = join(dataDir, "frpc.toml");
    await writeFile(configPath, "serverAddr = \"127.0.0.1\"\n", { mode: 0o600 });
    const frpc = new FrpcProcess(join(dataDir, "definitely-missing-engine"));
    const exits: Array<{ code: number; reason?: string }> = [];
    const lines: string[] = [];
    await new Promise<void>(resolve => {
      frpc.start(configPath,
        line => lines.push(line),
        (code, reason) => { exits.push({ code, reason }); resolve(); });
    });
    assert.equal(exits.length, 1, "error 必须恰好收敛为一次 onExit，不能重复也不能遗漏");
    assert.equal(exits[0].code, 1);
    assert.match(exits[0].reason || "", /definitely-missing-engine/);
    assert.match(exits[0].reason || "", /不存在/);
    // spawn 失败时 exitCode 恒为 null，running() 不得误报存活
    assert.equal(frpc.running(), false);
    assert.equal(frpc.isConnected(), false);
    // 对已失败的 spawn 调 stop() 不应抛错或再次触发回调
    frpc.stop();
    assert.equal(exits.length, 1);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});
