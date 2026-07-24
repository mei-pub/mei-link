import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = new URL("../src/", import.meta.url);

const checks = [
  ["main.html", "connBtn", "连接"],
  ["main.html", "restartBtn", "重启"],
  ["main.html", "settingsBtn", "设置"],
  ["main.html", "addBtn", "添加隧道"],
  ["main.html", "logsBtn", "查看日志"],
  ["main.html", "clearLogBtn", "清空日志"],
  ["popover.html", "playBtn", "连接"],
  ["popover.html", "btnMain", "主窗口"],
  ["popover.html", "btnLogs", "日志"],
  ["popover.html", "btnSettings", "设置"],
  ["popover.html", "btnRestart", "重启"],
  ["popover.html", "btnQuit", "退出"],
  ["settings.html", "saveBtn", "保存"],
  ["settings.html", "saveRestartBtn", "保存并重启"],
  ["settings.html", "closeBtn", "关闭"],
  ["tunnel-edit.html", "saveBtn", "创建"],
  ["tunnel-edit.html", "cancelBtn", "取消"],
];

let failures = 0;

for (const [file, id, label] of checks) {
  const html = readFileSync(join(root.pathname, file), "utf8");
  const pattern = new RegExp(`<button[^>]*id=["']${id}["'][^>]*>`, "s");
  const match = html.match(pattern);
  if (!match) {
    console.error(`${file}: missing button #${id}`);
    failures++;
    continue;
  }
  const tag = match[0];
  if (!tag.includes(`aria-label="${label}"`) && !tag.includes(`title="${label}"`)) {
    console.error(`${file}: button #${id} missing accessible label "${label}"`);
    failures++;
  }
}

if (failures > 0) {
  process.exit(1);
}

console.log(`accessibility-check: ${checks.length} button labels verified`);
