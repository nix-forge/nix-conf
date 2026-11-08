import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import vm from "node:vm";
import { javascriptSource } from "./source.mts";
await test("host probes emit CommonJS without runtime TypeScript or export boilerplate", () => {
  for (const path of [
    "../vscode/font-probe.cts",
    "../vscode/schema-probe.cts",
    "../codex/fixtures/ssh-startup.cts",
  ]) {
    const source = javascriptSource(new URL(path, import.meta.url));
    assert.doesNotThrow(() => new vm.Script(source), path);
  }
  assert.doesNotThrow(
    () =>
      new vm.Script(
        `(${javascriptSource(new URL("../vscode/wait-for-dom.ts", import.meta.url))})`,
      ),
  );
});
await test("Python's CLI adapter emits the same JavaScript as Node consumers", () => {
  const input = new URL("../vscode/font-probe.cts", import.meta.url);
  const result = spawnSync(
    process.execPath,
    [
      fileURLToPath(new URL("./source.mts", import.meta.url)),
      fileURLToPath(input),
    ],
    { encoding: "utf8", timeout: 5000 },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, javascriptSource(input));
});
