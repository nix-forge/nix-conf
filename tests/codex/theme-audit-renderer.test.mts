import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { javascriptSource } from "../typescript/source.mts";

const source = javascriptSource(
  new URL("./theme-audit-renderer.ts", import.meta.url),
);
interface FixtureElement {
  color: string;
  backgroundColor: string;
  parentElement: FixtureElement | null;
}

await test("emitted contrast adapter measures opaque and alpha-composited text and restores page state", async () => {
  const pixels: Record<string, [number, number, number, number]> = {
    black: [0, 0, 0, 255],
    white: [255, 255, 255, 255],
    transparent: [0, 0, 0, 0],
    halfWhite: [255, 255, 255, 128],
  };
  const canvasContext = {
    fillStyle: "black",
    clearRect() {},
    fillRect() {},
    getImageData() {
      const data = pixels[this.fillStyle];
      assert.ok(data, `Unexpected fixture color: ${this.fillStyle}`);
      return { data: new Uint8ClampedArray(data) };
    },
  };
  let removed = false;
  let restoredStyle: string | undefined;
  const originalClass = "fixture-dark";
  const page = {
    className: "modified-dark",
    removeAttribute(name: string) {
      assert.equal(name, "style");
      restoredStyle = undefined;
    },
    setAttribute(name: string, value: string) {
      assert.equal(name, "style");
      restoredStyle = value;
    },
  };
  const sandbox = {
    window: {
      codexThemeAudit: {
        classes: originalClass,
        style: "original-style" as string | null,
      },
    },
    document: {
      documentElement: page,
      createElement(tag: string) {
        if (tag === "canvas")
          return { width: 0, height: 0, getContext: () => canvasContext };
        assert.equal(tag, "span");
        return {
          style: { color: "", backgroundColor: "" },
          color: "white",
          backgroundColor: "black",
          parentElement: null,
          textContent: "",
          remove() {
            removed = true;
          },
        };
      },
      body: { append() {} },
    },
    getComputedStyle(element: FixtureElement) {
      return { color: element.color, backgroundColor: element.backgroundColor };
    },
    probe: {
      color: "white",
      backgroundColor: "black",
      parentElement: null,
    } as FixtureElement,
  };
  const context = vm.createContext(sandbox);
  vm.runInContext(source, context);
  const response: unknown = await vm.runInContext(
    'codexThemeRenderer("contrast", {labels: []})',
    context,
  );
  assert.equal(
    JSON.stringify(response),
    JSON.stringify([{ name: "elevated description", ratio: 21, pass: true }]),
  );
  assert.equal(removed, true, "temporary contrast sample must be removed");
  function measure(probe: FixtureElement): unknown {
    sandbox.probe = probe;
    const result: unknown = vm.runInContext(
      "window.codexThemeAudit.measure(probe)",
      context,
    );
    return result;
  }
  assert.equal(
    measure({ color: "black", backgroundColor: "black", parentElement: null }),
    1,
  );
  const half = measure({
    color: "halfWhite",
    backgroundColor: "black",
    parentElement: null,
  });
  assert.equal(typeof half, "number");
  assert.equal(Number(half).toFixed(2), "5.32");
  assert.equal(
    measure({
      color: "black",
      backgroundColor: "transparent",
      parentElement: {
        color: "black",
        backgroundColor: "white",
        parentElement: null,
      },
    }),
    21,
  );
  await vm.runInContext('codexThemeRenderer("cleanup", {})', context);
  assert.equal(page.className, originalClass);
  assert.equal(restoredStyle, "original-style");
  assert.equal("codexThemeAudit" in sandbox.window, false);
  sandbox.window.codexThemeAudit = { classes: originalClass, style: null };
  await vm.runInContext('codexThemeRenderer("cleanup", {})', context);
  assert.equal(restoredStyle, undefined);
});
