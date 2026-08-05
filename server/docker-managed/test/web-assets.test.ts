import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";

const webDir = join(import.meta.dirname, "../web");

test("management page exposes domain catalog and frps controls", async () => {
  const [html, app] = await Promise.all([
    readFile(join(webDir, "index.html"), "utf8"),
    readFile(join(webDir, "app.js"), "utf8"),
  ]);
  assert.match(html, /id="domainRows"/);
  assert.match(html, /id="addDomain"/);
  assert.match(html, /id="restartFrps"/);
  assert.match(app, /\/api\/config/);
  assert.match(app, /\/api\/control\/restart/);
});
