import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const configPath = fileURLToPath(new URL("../src-tauri/tauri.conf.json", import.meta.url));
const config = JSON.parse(await readFile(configPath, "utf8"));

assert.equal(
  config.bundle.resources?.["resources/frpc.exe"],
  "frpc.exe",
  "the Windows installer must include frpc.exe in its resources directory",
);

console.log("frpc-bundle-config: Windows frpc resource is configured");
