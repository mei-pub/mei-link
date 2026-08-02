import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { generateFrpcToml, type ServerConfig } from "./config.ts";
import { FrpcProcess } from "./frpc.ts";
import { toProxyDefinition } from "./proxy.ts";
import { routeText } from "./display.ts";
import { mergeRuntimeStatus } from "./runtime-status.ts";
import { DataStore, type Tunnel } from "./store.ts";

export class TunnelManager {
  private frpc: FrpcProcess;
  private events: Array<{ timestamp: string; message: string; level: string }> = [];
  private config: ServerConfig | null = null;
  private current: Tunnel[] = [];
  private store: DataStore;

  constructor(store: DataStore, frpcBin: string) { this.store = store; this.frpc = new FrpcProcess(frpcBin); }
  async load() { await this.store.init(); this.config = await this.store.config(); this.current = await this.store.tunnels(); }
  status() { return { configured: !!this.config, running: this.frpc.running(), connected: this.frpc.running(), pid: 0 }; }
  logs() { return this.events; }
  tunnels() { return this.current.map(tunnel => ({ ...tunnel, route: routeText(tunnel, this.config || {}) })); }
  serverConfig() { return this.config ? { ...this.config, authToken: "", adminPassword: "" } : null; }

  private log(message: string, level = "info") { this.events.unshift({ timestamp: new Date().toISOString(), message, level }); this.events = this.events.slice(0, 100); }
  async saveConfig(input: ServerConfig) {
    const previous = this.config;
    const config = {
      ...previous,
      ...input,
      authToken: input.authToken || previous?.authToken || "",
      adminPassword: input.adminPassword || previous?.adminPassword || "",
    } as ServerConfig;
    this.config = config;
    await this.store.saveConfig(config);
    await writeFile(join(this.store.dir, "frpc.toml"), generateFrpcToml(config, this.store.dir), { mode: 0o600 });
    this.log("服务器配置已保存");
  }

  async start() {
    if (!this.config) throw new Error("未配置服务器");
    this.log("正在启动隧道管理器...");
    this.frpc.start(join(this.store.dir, "frpc.toml"), line => this.log(`frpc: ${line}`), code => this.log(`frpc 进程已退出，状态码: ${code}`, "error"));
    await this.waitForAdmin();
    await this.syncProxies();
    this.log("隧道管理器已连接");
  }

  stop() { this.frpc.stop(); this.log("隧道管理器已停止"); }
  async saveTunnels(tunnels: Tunnel[]) { this.current = tunnels; await this.store.saveTunnels(tunnels); if (this.frpc.running()) await this.syncProxies(); }

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
}
