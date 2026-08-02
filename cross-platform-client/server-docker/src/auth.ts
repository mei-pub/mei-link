import { randomBytes, timingSafeEqual } from "node:crypto";

type Env = Record<string, string | undefined>;

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
