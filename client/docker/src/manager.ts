import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { connect } from "node:net";
import { generateFrpcToml, type ServerConfig } from "./config.ts";
import { FrpcProcess } from "./frpc.ts";
import { ReconnectController } from "./reconnect.ts";
import { toProxyDefinition } from "./proxy.ts";
import { routeText } from "./display.ts";
import { mergeRuntimeStatus } from "./runtime-status.ts";
import { DataStore, type Tunnel } from "./store.ts";

export type TunnelInput = Omit<Tunnel, "id" | "status" | "runtimeStatus" | "remoteAddr" | "errorMessage" | "createdAt" | "updatedAt">;
const validPort = (value: number) => Number.isInteger(value) && value >= 1 && value <= 65535;
const clampInt = (value: number | undefined, min: number, max: number, fallback: number) => {
  if (typeof value !== "number" || !Number.isInteger(value)) return fallback;
  return Math.min(max, Math.max(min, value));
};

export class TunnelManager {
  private frpc: FrpcProcess;
  private events: Array<{ timestamp: string; message: string; level: string }> = [];
  private config: ServerConfig | null = null;
  private current: Tunnel[] = [];
  private store: DataStore;
  private reconnect: ReconnectController | null = null;
  /** 手动连接 / 自动重启过程中置位，避免旧 frpc 进程退出回调误触发恢复。 */
  private restarting = false;

  constructor(store: DataStore, frpcBin: string) { this.store = store; this.frpc = new FrpcProcess(frpcBin); }
  async load() { await this.store.init(); const config = await this.store.config(); this.config = config ? this.normalizedConfig(config) : null; this.current = await this.store.tunnels(); }
  status() {
    const reconnectState = this.reconnect?.currentState();
    return {
      configured: !!this.config,
      running: this.frpc.running(),
      connected: this.frpc.isConnected(),
      reconnecting: reconnectState === "reconnecting",
      reconnectFailed: reconnectState === "failed",
      pid: 0,
    };
  }
  logs() { return this.events; }
  clearLogs() { this.events = []; }
  tunnels() { return this.current.map(tunnel => ({ ...tunnel, route: routeText(tunnel, this.config || {}) })); }
  serverConfig() { return this.config ? { ...this.config, authToken: "", adminPassword: "" } : null; }

  async testConnection(addr: string, port: number) {
    if (!addr.trim() || !Number.isInteger(port) || port < 1 || port > 65535) return { ok: false, err: "服务器地址或端口无效" };
    try {
      await new Promise<void>((resolve, reject) => {
        const socket = connect({ host: addr.trim(), port });
        const timer = setTimeout(() => socket.destroy(new Error("连接超时")), 5_000);
        socket.once("connect", () => { clearTimeout(timer); socket.end(); resolve(); });
        socket.once("error", error => { clearTimeout(timer); reject(error); });
      });
      return { ok: true };
    } catch (error) {
      return { ok: false, err: error instanceof Error ? error.message : "连接失败" };
    }
  }

  private log(message: string, level = "info") { this.events.unshift({ timestamp: new Date().toISOString(), message, level }); this.events = this.events.slice(0, 100); }
  async saveConfig(input: ServerConfig) {
    const previous = this.config;
    const config = this.normalizedConfig({
      ...previous,
      ...input,
      authToken: input.authToken || previous?.authToken || "",
      adminPassword: input.adminPassword || previous?.adminPassword || "",
    } as ServerConfig);
    const wasArmed = !!this.reconnect;
    this.config = config;
    await this.store.saveConfig(config);
    await writeFile(join(this.store.dir, "frpc.toml"), generateFrpcToml(config, this.store.dir), { mode: 0o600 });
    // 重连参数可能已修改：已启用的 watchdog 用新参数重建。
    if (wasArmed) { this.reconnect.stop(); this.reconnect = null; this.armReconnect(); }
    this.log("服务器配置已保存");
  }

  async start() {
    if (!this.config) throw new Error("未配置服务器");
    this.log("正在启动隧道管理器...");
    this.restarting = true;
    try {
      await this.startFrpc();
      this.log("隧道管理器已连接");
    } finally {
      // 即使启动失败也启用 watchdog：frpc 可能仍在后台尝试登录，交给它接管恢复。
      this.restarting = false;
      this.armReconnect();
    }
  }

  stop() {
    this.disarmReconnect();
    this.frpc.stop();
    this.log("隧道管理器已停止");
  }

  /** 有配置则自动连接并保持保活：容器/进程重启后无需手动点击即可恢复隧道。 */
  async autoStartIfConfigured() {
    if (!this.config) return;
    try {
      await this.start();
    } catch (error) {
      // start() 失败时 watchdog 已在 finally 中接管，会按重连设置持续探测/重启。
      this.log(`自动连接失败: ${error instanceof Error ? error.message : String(error)}`, "error");
    }
  }
  async saveTunnels(tunnels: Tunnel[]) { this.current = tunnels; await this.store.saveTunnels(tunnels); if (this.frpc.running()) await this.syncProxies(); }

  async createTunnel(input: TunnelInput): Promise<Tunnel> {
    const tunnel = this.normalizedTunnel(input);
    this.assertUniqueName(tunnel.name);
    await this.syncTunnel(tunnel);
    this.current.push(tunnel);
    await this.store.saveTunnels(this.current);
    this.log(`隧道 "${tunnel.name}" 已创建`);
    return { ...tunnel };
  }

  async updateTunnel(id: string, input: TunnelInput): Promise<Tunnel> {
    const index = this.current.findIndex(tunnel => tunnel.id === id);
    if (index < 0) throw new Error("隧道不存在");
    const previous = this.current[index];
    const tunnel = this.normalizedTunnel(input, previous);
    this.assertUniqueName(tunnel.name, id);
    // A disabled tunnel has already been removed from frpc Store API. Renaming it
    // must not fail merely because there is no old proxy to remove.
    if (this.frpc.running() && previous.enabled && previous.name !== tunnel.name) {
      try { await this.deleteProxy(previous.name); } catch (error) { this.log(`清理旧隧道 "${previous.name}" 失败: ${error instanceof Error ? error.message : "unknown"}`, "warning"); }
    }
    await this.syncTunnel(tunnel);
    this.current[index] = tunnel;
    await this.store.saveTunnels(this.current);
    this.log(`隧道 "${tunnel.name}" 已更新`);
    return { ...tunnel };
  }

  async deleteTunnel(id: string): Promise<void> {
    const index = this.current.findIndex(tunnel => tunnel.id === id);
    if (index < 0) throw new Error("隧道不存在");
    const [tunnel] = this.current.slice(index, index + 1);
    if (this.frpc.running() && tunnel.enabled) {
      try { await this.deleteProxy(tunnel.name); } catch (error) { this.log(`清理隧道 "${tunnel.name}" 失败: ${error instanceof Error ? error.message : "unknown"}`, "warning"); }
    }
    this.current.splice(index, 1);
    await this.store.saveTunnels(this.current);
    this.log(`隧道 "${tunnel.name}" 已删除`);
  }

  async toggleTunnel(id: string, enabled: boolean): Promise<Tunnel> {
    const index = this.current.findIndex(tunnel => tunnel.id === id);
    if (index < 0) throw new Error("隧道不存在");
    const previous = this.current[index];
    const tunnel = {
      ...previous,
      enabled,
      runtimeStatus: enabled ? "wait start" : "closed",
      errorMessage: "",
      remoteAddr: enabled ? previous.remoteAddr || "" : "",
      updatedAt: new Date().toISOString(),
    };
    if (this.frpc.running()) {
      if (enabled) await this.syncTunnel(tunnel);
      else {
        try { await this.deleteProxy(tunnel.name); } catch (error) { this.log(`禁用隧道 "${tunnel.name}" 时清理代理失败: ${error instanceof Error ? error.message : "unknown"}`, "warning"); }
      }
    }
    this.current[index] = tunnel;
    await this.store.saveTunnels(this.current);
    this.log(`隧道 "${tunnel.name}" 已${enabled ? "启用" : "禁用"}`);
    return { ...tunnel };
  }

  async refreshRuntime() {
    if (!this.config || !this.frpc.running()) {
      this.current = mergeRuntimeStatus(this.current, {});
      return this.current;
    }
    try {
      const status = await (await this.admin("/api/status")).json() as Record<string, Array<{ name: string; status?: string; remote_addr?: string; err?: string }>>;
      this.current = mergeRuntimeStatus(this.current, status);
    } catch {
      this.current = mergeRuntimeStatus(this.current, {});
    }
    return this.current;
  }

  private auth() { return `Basic ${Buffer.from(`${this.config!.adminUser}:${this.config!.adminPassword}`).toString("base64")}`; }
  private normalizedConfig(config: ServerConfig): ServerConfig {
    return {
      ...config,
      vhostHTTPPort: validPort(config.vhostHTTPPort) ? config.vhostHTTPPort : 8080,
      vhostHTTPSPort: validPort(config.vhostHTTPSPort) ? config.vhostHTTPSPort : 8443,
      reconnectInterval: clampInt(config.reconnectInterval, 3, 300, 10),
      maxReconnectAttempts: clampInt(config.maxReconnectAttempts, 1, 30, 3),
      maxRestartAttempts: clampInt(config.maxRestartAttempts, 1, 30, 3),
    };
  }

  private async startFrpc() {
    this.frpc.start(join(this.store.dir, "frpc.toml"),
      line => this.log(`frpc: ${line}`),
      code => {
        this.log(`frpc 进程已退出，状态码: ${code}`, "error");
        // 手动连接 / 自动重启过程中的退出由重启路径处理，不额外触发恢复。
        if (this.reconnect && !this.restarting) this.reconnect.kick();
      });
    await this.waitForAdmin();
    await this.waitForServerLogin();
    await this.syncProxies();
  }

  private armReconnect() {
    const config = this.config;
    if (!config) return;
    this.reconnect?.stop();
    this.reconnect = new ReconnectController({
      reconnectIntervalMs: (config.reconnectInterval ?? 10) * 1000,
      maxReconnectAttempts: config.maxReconnectAttempts ?? 3,
      maxRestartAttempts: config.maxRestartAttempts ?? 3,
      probe: () => ({ alive: this.frpc.running(), connected: this.frpc.isConnected() }),
      restart: async () => {
        this.restarting = true;
        try {
          await this.startFrpc();
          return true;
        } catch (error) {
          this.log(`frpc 重启失败: ${error instanceof Error ? error.message : String(error)}`, "error");
          return false;
        } finally {
          this.restarting = false;
        }
      },
      onLog: (message, level) => this.log(message, level),
    });
    this.reconnect.start();
  }

  private disarmReconnect() {
    this.reconnect?.stop();
    this.reconnect = null;
  }

  private async admin(path: string, init: RequestInit = {}) {
    const response = await fetch(`http://127.0.0.1:${this.config!.adminPort}${path}`, { ...init, signal: AbortSignal.timeout(3_000), headers: { Authorization: this.auth(), "content-type": "application/json", ...(init.headers || {}) } });
    if (!response.ok) throw new Error(`frpc Admin API ${init.method || "GET"} ${path} failed: ${response.status}`);
    return response;
  }
  private async waitForAdmin() {
    let lastError: unknown;
    for (let attempt = 0; attempt < 30; attempt++) {
      try { if ((await fetch(`http://127.0.0.1:${this.config!.adminPort}/healthz`)).ok) return; } catch (error) { lastError = error; }
      await new Promise(resolve => setTimeout(resolve, 250));
    }
    throw new Error(`Admin API 未就绪: ${lastError instanceof Error ? lastError.message : "timeout"}`);
  }
  private async waitForServerLogin() {
    const startedAt = Date.now();
    while (Date.now() - startedAt < 5_000) {
      if (this.frpc.isConnected()) return;
      if (!this.frpc.running()) throw new Error("frpc exited before logging into the server");
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error("frpc did not log in to the server within 5 seconds");
  }

  private async syncProxies() {
    const listed = await (await this.admin("/api/store/proxies")).json() as { proxies?: Array<{ name: string }> };
    const existing = new Set((listed.proxies || []).map(proxy => proxy.name));
    for (const tunnel of this.current.filter(tunnel => tunnel.enabled)) {
      const update = existing.has(tunnel.name);
      await this.admin(update ? `/api/store/proxies/${encodeURIComponent(tunnel.name)}` : "/api/store/proxies", { method: update ? "PUT" : "POST", body: JSON.stringify(toProxyDefinition(tunnel, this.config!.subDomainHost)) });
      existing.delete(tunnel.name);
    }
    for (const name of existing) await this.admin(`/api/store/proxies/${encodeURIComponent(name)}`, { method: "DELETE" });
  }

  private normalizedTunnel(input: TunnelInput, previous?: Tunnel): Tunnel {
    const name = input.name.trim();
    if (!name) throw new Error("隧道名称不能为空");
    if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(name)) throw new Error("隧道名称仅支持字母、数字、点、下划线和连字符");
    if (!Number.isInteger(input.localPort) || input.localPort < 1 || input.localPort > 65535) throw new Error("本地端口必须在 1 到 65535 之间");
    if ((input.type === "tcp" || input.type === "udp") && input.remotePort !== undefined && (!Number.isInteger(input.remotePort) || input.remotePort < 1 || input.remotePort > 65535)) throw new Error("远程端口必须在 1 到 65535 之间");
    const customDomains = input.customDomains?.map(domain => domain.trim()).filter(Boolean) || [];
    this.assertCustomDomains(input.type, customDomains);
    const now = new Date().toISOString();
    return {
      ...input,
      id: previous?.id || crypto.randomUUID(),
      name,
      localIP: input.localIP.trim() || "127.0.0.1",
      subdomain: input.subdomain?.trim() || undefined,
      remotePort: input.remotePort || undefined,
      customDomains,
      httpUser: input.httpUser?.trim() || undefined,
      // The edit dialog intentionally does not reveal saved credentials. A blank value therefore means
      // "leave unchanged", matching the server-config password fields.
      httpPassword: input.httpPassword || previous?.httpPassword || undefined,
      hostHeaderRewrite: input.hostHeaderRewrite?.trim() || undefined,
      enabled: input.enabled !== false,
      runtimeStatus: input.enabled === false ? "closed" : previous?.runtimeStatus || "new",
      remoteAddr: previous?.remoteAddr || "",
      errorMessage: "",
      createdAt: previous?.createdAt || now,
      updatedAt: now,
    };
  }

  private assertUniqueName(name: string, exceptId?: string) {
    if (this.current.some(tunnel => tunnel.name === name && tunnel.id !== exceptId)) throw new Error("隧道名称已存在");
  }

  private assertCustomDomains(type: Tunnel["type"], domains: string[]) {
    for (const domain of domains) {
      if (!domain.includes("*")) continue;
      if (type !== "http" && type !== "https") throw new Error("泛域名仅支持 HTTP 或 HTTPS 隧道");
      if (!/^\*\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/.test(domain)) throw new Error("泛域名格式应为 *.example.com");
      const root = this.config?.subDomainHost.trim().toLowerCase();
      const suffix = domain.slice(2).toLowerCase();
      if (root && (suffix === root || suffix.endsWith(`.${root}`))) throw new Error(`泛域名 ${domain} 不能属于子域名根域 ${root}；请改用独立域名，或在 frps 中移除该子域名根域`);
    }
  }

  private async syncTunnel(tunnel: Tunnel) {
    if (!this.frpc.running() || !tunnel.enabled) return;
    const listed = await (await this.admin("/api/store/proxies")).json() as { proxies?: Array<{ name: string }> };
    const exists = (listed.proxies || []).some(proxy => proxy.name === tunnel.name);
    await this.admin(exists ? `/api/store/proxies/${encodeURIComponent(tunnel.name)}` : "/api/store/proxies", {
      method: exists ? "PUT" : "POST", body: JSON.stringify(toProxyDefinition(tunnel, this.config!.subDomainHost)),
    });
  }

  private async deleteProxy(name: string) {
    await this.admin(`/api/store/proxies/${encodeURIComponent(name)}`, { method: "DELETE" });
  }
}
