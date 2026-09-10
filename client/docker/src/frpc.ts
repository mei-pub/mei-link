import { spawn, type ChildProcess } from "node:child_process";
import { cleanFrpcLogLine, isFrpcConnectionFailure, isFrpcLoginSuccess } from "./frpc-log.ts";

/** spawn 失败（引擎缺失/无权限等）转成用户可读的中文提示，替代裸的 ENOENT 崩溃堆栈。 */
function spawnFailureText(bin: string, error: NodeJS.ErrnoException): string {
  if (error.code === "ENOENT") return `隧道引擎不存在：${bin}，请检查 MEILINK_FRPC_PATH 指向的路径`;
  if (error.code === "EACCES") return `隧道引擎无执行权限：${bin}`;
  return `启动隧道引擎 ${bin} 失败：${error.message}`;
}

export class FrpcProcess {
  private child?: ChildProcess;
  private connected = false;
  private readonly bin: string;

  constructor(bin: string) { this.bin = bin; }

  running() { return !!this.child && this.child.exitCode === null; }
  isConnected() { return this.running() && this.connected; }

  start(configPath: string, onLine: (line: string) => void, onExit: (code: number, reason?: string) => void) {
    this.stop();
    this.connected = false;
    this.child = spawn(this.bin, ["-c", configPath], { stdio: ["ignore", "pipe", "pipe"] });
    // spawn 失败只 emit 'error'（不 emit 'exit'），不处理会成为 unhandled error 崩掉整个服务。
    // 这里统一收敛到 onExit（带可读原因），交给 manager 的 watchdog 走重启/放弃阶梯。
    let settled = false;
    const settle = (code: number, reason?: string) => {
      if (settled) return;
      settled = true;
      this.connected = false;
      onExit(code, reason);
    };
    for (const stream of [this.child.stdout, this.child.stderr]) {
      let pending = "";
      stream?.on("data", data => {
        pending += String(data);
        const lines = pending.split(/\r?\n/);
        pending = lines.pop() || "";
        for (const rawLine of lines) {
          if (isFrpcLoginSuccess(rawLine)) this.connected = true;
          else if (isFrpcConnectionFailure(rawLine)) this.connected = false;
          const line = cleanFrpcLogLine(rawLine);
          if (line) onLine(line);
        }
      });
    }
    this.child.on("exit", code => settle(code ?? 1));
    this.child.on("error", error => {
      // spawn 失败时 exitCode 恒为 null，会让 running() 误报存活；清掉引用修正状态。
      this.child = undefined;
      settle(1, spawnFailureText(this.bin, error));
    });
  }

  stop() {
    this.connected = false;
    if (this.running()) this.child!.kill("SIGTERM");
  }
}
