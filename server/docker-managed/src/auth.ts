import { randomBytes, timingSafeEqual } from "node:crypto";

type Env = Record<string, string | undefined>;

/**
 * 校验 /api/domains 端点的 Bearer token。
 * 与 EnvironmentAuth（管理页登录会话）独立：客户端只持有一个常量 token，
 * 不持有管理页账号密码。token 从环境变量 MEILINK_DOMAIN_API_TOKEN 读取；
 * 未配置时端点禁用（hasToken=false，server.ts 返回 404）。
 * 用常量时间比较防时序攻击。
 */
export class DomainApiToken {
  private readonly expected: Buffer;
  readonly configured: boolean;

  constructor(env: Env = process.env) {
    const token = String(env.MEILINK_DOMAIN_API_TOKEN || "").trim();
    this.expected = Buffer.from(token);
    this.configured = token.length > 0;
  }

  /** 校验 Authorization: Bearer <token>。未配置 token 时恒为 false。 */
  valid(authorizationHeader = ""): boolean {
    if (!this.configured) return false;
    const supplied = Buffer.from(authorizationHeader.replace(/^Bearer\s+/i, "").trim());
    return supplied.length === this.expected.length && supplied.length > 0 && timingSafeEqual(supplied, this.expected);
  }
}

export class EnvironmentAuth {
  private readonly user: string;
  private readonly password: string;
  private readonly sessions = new Map<string, number>();

  constructor(env: Env = process.env) {
    this.user = String(env.MEILINK_ADMIN_USER || "");
    this.password = String(env.MEILINK_ADMIN_PASSWORD || "");
    if (!this.user) throw new Error("MEILINK_ADMIN_USER is required");
    if (!this.password) throw new Error("MEILINK_ADMIN_PASSWORD is required");
  }

  login(user: string, password: string) {
    const expected = Buffer.from(this.password);
    const supplied = Buffer.from(password);
    if (user !== this.user || supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return null;
    const token = randomBytes(32).toString("base64url");
    this.sessions.set(token, Date.now() + 86_400_000);
    return token;
  }

  valid(cookie = "") {
    const token = /(?:^|; )meilink_server_session=([^;]+)/.exec(cookie)?.[1];
    return !!token && (this.sessions.get(token) || 0) > Date.now();
  }

  logout(cookie = "") {
    const token = /(?:^|; )meilink_server_session=([^;]+)/.exec(cookie)?.[1];
    if (token) this.sessions.delete(token);
  }
}
