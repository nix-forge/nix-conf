import assert from "node:assert/strict";
import { javascriptSource } from "../typescript/source.mts";
import test from "node:test";
import { readdirSync } from "node:fs";
import vm from "node:vm";
function execute(name: string, args: unknown[], globals: object): unknown {
  const source = javascriptSource(
    new URL(`./fixtures/${name}.cts`, import.meta.url),
  );
  // Match the WebDriver adapter: raw JavaScript and positional browser arguments.
  return vm.runInNewContext(
    `(function () { const module = {exports: null}; ${source}\n return module.exports.apply(this, arguments); }).apply(null, inputs)`,
    { ...globals, inputs: args },
    { timeout: 1000 },
  );
}
await test("browser font probes fail clearly when a required DOM element is absent", () => {
  assert.throws(
    () =>
      execute("font-element-metrics", ["missing"], {
        document: { getElementById: () => null },
      }),
    /fixture element missing/,
  );
});
await test("browser canvas probes reject an unavailable drawing context", () => {
  assert.throws(
    () =>
      execute("mutant-emoji-canvas-metrics", [[], "fixture-font"], {
        document: { createElement: () => ({ getContext: () => null }) },
      }),
    /Canvas 2D context unavailable/,
  );
});
await test("font-load callbacks retain the positional WebDriver contract", async () => {
  const outcome = await new Promise<unknown>((resolve) => {
    execute("font-descriptor-load", ["sample", "400 40px Fixture", resolve], {
      document: { fonts: { load: async () => [{}], check: () => true } },
    });
  });
  assert.equal(
    JSON.stringify(outcome),
    JSON.stringify({ loaded: true, checked: true }),
  );
});

await test("every browser fixture emits a standalone WebDriver function", () => {
  const directory = new URL("./fixtures/", import.meta.url);
  for (const name of readdirSync(directory).filter((file) =>
    file.endsWith(".cts"),
  )) {
    const source = javascriptSource(new URL(name, directory));
    const exported: unknown = vm.runInNewContext(
      `const module = {exports: null}; ${source}\nmodule.exports`,
      {},
      { timeout: 1000 },
    );
    assert.equal(typeof exported, "function", name);
  }
});
