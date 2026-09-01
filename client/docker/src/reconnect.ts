/**
 * 断连自动恢复控制器。
 *
 * 两级恢复阶梯：
 * 1. 重建连接：frpc 进程存活但未连上服务器时，按 reconnectInterval 周期探测
 *    （frpc 自身会在后台重连，这里只计数等待），连续失败
 *    maxReconnectAttempts 次后升级为重启；
 * 2. 重启 frpc：重启失败累计 maxRestartAttempts 次后放弃，状态置为 failed。
 *
 * 进程意外退出视为无法重建连接，直接进入重启。用户手动“断开”（stop）会停用
 * 控制器，之后不会自动拉起；只有意外断连/崩溃才触发恢复。
 *
 * 状态（currentState）：
 * - idle:         未启用（未连接或已手动断开）
 * - active:       已启用且连接健康
 * - reconnecting: 正在重连/重启（失败计数中）
 * - failed:       重启次数耗尽，停止自动恢复，等待手动“连接”
 */
export type ReconnectState = "idle" | "active" | "reconnecting" | "failed";

export interface ReconnectProbeResult {
  /** frpc 进程是否存活 */
  alive: boolean;
  /** 是否已连上服务器（登录成功） */
  connected: boolean;
}

export interface ReconnectControllerOptions {
  reconnectIntervalMs: number;
  maxReconnectAttempts: number;
  maxRestartAttempts: number;
  probe: () => ReconnectProbeResult;
  restart: () => Promise<boolean>;
  onLog?: (message: string, level?: "info" | "warning" | "error") => void;
  /** frpc 异常退出后延迟探测的防抖时长（默认 2000ms，测试可注入短值）。 */
  kickDelayMs?: number;
}

export class ReconnectController {
  private state: ReconnectState = "idle";
  private reconnectFailures = 0;
  private restartFailures = 0;
  private timer?: ReturnType<typeof setInterval>;
  private kickTimer?: ReturnType<typeof setTimeout>;
  private checking = false;
  private restartInFlight = false;
  private readonly options: ReconnectControllerOptions;

  constructor(options: ReconnectControllerOptions) { this.options = options; }

  currentState() { return this.state; }
  reconnectAttempts() { return this.reconnectFailures; }
  restartAttempts() { return this.restartFailures; }

  /** 启用周期探测。重复调用幂等。 */
  start() {
    if (this.timer) return;
    this.reconnectFailures = 0;
    this.restartFailures = 0;
    this.setState("active");
    this.timer = setInterval(() => void this.check(), this.options.reconnectIntervalMs);
    this.timer.unref?.();
  }

  /** 停用并重置（用户手动断开）。 */
  stop() {
    if (this.timer) { clearInterval(this.timer); this.timer = undefined; }
    if (this.kickTimer) { clearTimeout(this.kickTimer); this.kickTimer = undefined; }
    this.reconnectFailures = 0;
    this.restartFailures = 0;
    this.setState("idle");
  }

  /** frpc 异常退出时立即触发一次探测（带防抖），不必等下一个周期。 */
  kick() {
    if (this.kickTimer || !this.timer || this.checking || this.restartInFlight) return;
    this.kickTimer = setTimeout(() => {
      this.kickTimer = undefined;
      void this.check();
    }, this.options.kickDelayMs ?? 2_000);
    this.kickTimer.unref?.();
  }

  /** 执行一轮探测与可能的升级动作。可直接调用（测试用）。 */
  async check() {
    if (this.state === "idle") return;
    if (this.checking || this.restartInFlight) return;
    this.checking = true;
    try {
      const { alive, connected } = this.options.probe();
      if (connected) {
        this.reset();
        return;
      }
      // 已放弃（重启次数耗尽）：保留低频探测，连接自行恢复时自动解除"重连失败"，
      // 但不再自动重启 frpc，避免无限重启风暴。
      if (this.state === "failed") return;
      if (alive) {
        // 进程存活但未连上服务器：frpc 内部正在重试，这里只计数等待。
        this.reconnectFailures++;
        if (this.reconnectFailures < this.options.maxReconnectAttempts) {
          this.setState("reconnecting");
          this.options.onLog?.(`连接异常，第 ${this.reconnectFailures}/${this.options.maxReconnectAttempts} 次重连中`, "warning");
          return;
        }
        this.options.onLog?.(`连续 ${this.reconnectFailures} 次重连失败，升级为重启 frpc`, "warning");
        this.reconnectFailures = 0;
      }
      await this.restartFrpc();
    } finally {
      this.checking = false;
    }
  }

  private async restartFrpc() {
    this.restartInFlight = true;
    this.restartFailures++;
    this.setState("reconnecting");
    this.options.onLog?.(`第 ${this.restartFailures}/${this.options.maxRestartAttempts} 次重启 frpc`, "warning");
    let ok = false;
    try {
      ok = await this.options.restart();
    } catch (error) {
      this.options.onLog?.(`重启异常: ${error instanceof Error ? error.message : String(error)}`, "error");
    } finally {
      this.restartInFlight = false;
    }
    if (ok) {
      this.options.onLog?.("frpc 重启成功，连接已恢复", "info");
      this.reset();
      return;
    }
    if (this.restartFailures >= this.options.maxRestartAttempts) {
      this.setState("failed");
      // 保留周期探测（不清定时器）：连接自行恢复时由 check() 自动解除"重连失败"。
      this.options.onLog?.("自动重连已放弃：重启次数耗尽，请检查服务器；连接恢复后会自动解除", "error");
      return;
    }
    // 未耗尽：回到重建连接阶段，等下一个周期再决定是否再次重启。
    this.setState("reconnecting");
  }

  private reset() {
    if (this.state === "failed" || this.reconnectFailures > 0 || this.restartFailures > 0) this.options.onLog?.("连接已恢复", "info");
    this.reconnectFailures = 0;
    this.restartFailures = 0;
    this.setState("active");
  }

  private setState(state: ReconnectState) {
    if (this.state === state) return;
    this.state = state;
  }
}
