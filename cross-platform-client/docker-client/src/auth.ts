import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";

type Stored = { user: string; salt: string; hash: string };
export class AuthService {
  private sessions = new Map<string, number>();
  private dataDir: string;
  constructor(dataDir: string) { this.dataDir = dataDir; }
  private file() { return join(this.dataDir, "auth.json"); }
  async initialize(env = process.env) {
    await mkdir(this.dataDir, { recursive: true });
    try { await readFile(this.file()); return; } catch {}
    const password = env.MEILINK_ADMIN_PASSWORD;
    if (!password) throw new Error("MEILINK_ADMIN_PASSWORD is required on first start");
    const salt = randomBytes(16).toString("hex");
    const hash = scryptSync(password, salt, 32).toString("hex");
    await writeFile(this.file(), JSON.stringify({ user: env.MEILINK_ADMIN_USER || "admin", salt, hash }), { mode: 0o600 });
  }
  async login(user: string, password: string) {
    const stored: Stored = JSON.parse(await readFile(this.file(), "utf8"));
    const hash = scryptSync(password, stored.salt, 32);
    if (user !== stored.user || !timingSafeEqual(hash, Buffer.from(stored.hash, "hex"))) return null;
    const token = randomBytes(32).toString("base64url"); this.sessions.set(token, Date.now() + 86400000); return token;
  }
  valid(cookie = "") { const token = /(?:^|; )meilink_session=([^;]+)/.exec(cookie)?.[1]; return !!token && (this.sessions.get(token) || 0) > Date.now(); }
  logout(cookie = "") { const token = /(?:^|; )meilink_session=([^;]+)/.exec(cookie)?.[1]; if (token) this.sessions.delete(token); }
}
