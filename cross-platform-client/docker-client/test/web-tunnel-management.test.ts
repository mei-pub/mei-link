import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const web = join(import.meta.dirname, "../web");

test("web UI provides an accessible tunnel edit dialog and per-tunnel actions", async () => {
  const [html, script] = await Promise.all([
    readFile(join(web, "index.html"), "utf8"),
    readFile(join(web, "app.js"), "utf8"),
  ]);
  assert.match(html, /<dialog id="tunnelDialog"/);
  assert.match(html, /id="tunnelForm"/);
  assert.match(html, /aria-label="编辑隧道"/);
  assert.match(script, /data-edit=/);
  assert.match(script, /data-toggle=/);
  assert.match(script, /navigator\.clipboard\.writeText/);
  assert.match(script, /\/api\/tunnels\/\$\{encodeURIComponent\(tunnel\.id\)\}\/toggle/);
  assert.match(script, /const field = \(form, name\) => form\.elements\.namedItem\(name\)/);
});
