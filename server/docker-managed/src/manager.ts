import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { defaultServerConfig, normalizeServerConfig, renderFrpsToml, type ServerConfig } from "./config.ts";

export type FrpsStatus = { running: boolean; pid?: number; lastError?: string };

export interface FrpsController {
  restart(): Promise<void>;
  stop(): Promise<void>;
  status(): FrpsStatus;
}

export class ProcessFrpsController implements FrpsController {
  private child: ChildProcessWithoutNullStreams | null = null;
  private lastError = "";
  private readonly onLog: (message: string, level?: "info" | "error") => void;
  private readonly binary: string;
  private readonly configPath: string;

  constructor(binary: string, configPath: string, onLog?: (message: string, level?: "info" | "error") => void) {
    this.binary = binary;
    this.configPath = configPath;
    this.onLog = onLog || (() => {});
  }

  status(): FrpsStatus {
    return { running: !!this.child && !this.child.killed, pid: this.child?.pid, lastError: this.lastError || undefined };
  }

  async restart() {
    await this.stop();
    this.lastError = "";
    const child = spawn(this.binary, ["-c", this.configPath], { stdio: "pipe" });
    this.child = child;
    child.stdout.on("data", (data) => this.onLog(`frps: ${String(data).trim()}`));
    child.stderr.on("data", (data) => this.onLog(`frps: ${String(data).trim()}`, "error"));
    child.once("error", (error) => { this.lastError = error.message; this.onLog(`frps 启动失败: ${error.message}`, "error"); });
    child.once("exit", (code) => { if (code && code !== 0) { this.lastError = `frps 异常退出（状态码 ${code}）`; this.onLog(this.lastError, "error"); } this.child = null; });
    this.onLog("正在启动 frps");
  }

  async stop() {
    if (!this.child || this.child.killed) return;
    const child = this.child;
    this.child = null;
    child.kill("SIGTERM");
    await new Promise<void>((resolve) => child.once("exit", () => resolve()));
  }
}

export type ServerEvent = { time: string; level: "info" | "error"; message: string };

type ManagerOptions = {
  dataDir?: string;
  frpsBin?: string;
  environment?: Record<string, string | undefined>;
  controller?: FrpsController;
};

export class ServerManager {
  private readonly dataDir: string;
  private readonly configFile: string;
  private readonly frpsToml: string;
  private readonly environment: Record<string, string | undefined>;
  private readonly events: ServerEvent[] = [];
  private controller: FrpsController;
  private config: ServerConfig;

  constructor(options: ManagerOptions = {}) {
    this.dataDir = options.dataDir || process.env.MEILINK_DATA_DIR || "/data";
    this.configFile = join(this.dataDir, "server.json");
    this.frpsToml = join(this.dataDir, "frps.toml");
    this.environment = options.environment || process.env;
    this.config = defaultServerConfig(this.environment);
    this.controller = options.controller || new ProcessFrpsController(options.frpsBin || process.env.MEILINK_FRPS_PATH || "/usr/local/bin/frps", this.frpsToml, (message, level) => this.log(message, level));
  }

  private log(message: string, level: "info" | "error" = "info") {
    this.events.unshift({ time: new Date().toISOString(), level, message });
    this.events.splice(200);
  }

  private async write(name: string, value: string) {
    const destination = join(this.dataDir, name);
    const temporary = join(this.dataDir, `.${name}.tmp`);
    await writeFile(temporary, value, { mode: 0o600 });
    await rename(temporary, destination);
  }

  async load() {
    await mkdir(this.dataDir, { recursive: true });
    try { this.config = normalizeServerConfig(JSON.parse(await readFile(this.configFile, "utf8"))); } catch {
      if (this.config.authToken) await this.write("server.json", JSON.stringify(this.config, null, 2));
    }
    if (this.config.authToken) {
      await this.write("frps.toml", renderFrpsToml(this.config));
      await this.controller.restart();
    } else {
      this.log("尚未配置 FRP Token，请在管理页面保存服务器配置", "error");
    }
  }

  currentConfig() { return this.config; }
  status() { return { ...this.controller.status(), configured: !!this.config.authToken, domains: this.config.domains }; }
  logs() { return this.events; }

  async save(input: ServerConfig) {
    this.config = normalizeServerConfig(input);
    await this.write("server.json", JSON.stringify(this.config, null, 2));
    await this.write("frps.toml", renderFrpsToml(this.config));
    await this.controller.restart();
    this.log("服务器配置已保存并重启 frps");
    return this.config;
  }

  async restart() {
    if (!this.config.authToken) throw new Error("请先保存 FRP Token");
    await this.controller.restart();
  }

  async stop() { await this.controller.stop(); }
}
