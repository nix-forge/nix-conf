import { javascriptSource } from "../typescript/source.mts";
/**
 * Render CodeLens with generated VS Code settings and check ordinary glyphs.
 * Usage: node tests/vscode/check-font-features.mts SETTINGS_JSON
 * Requires Linux, systemd --user, dbus-run-session, Node 24+, VS Code, and a graphical session
 * with the configured fonts.
 * Uses a disposable profile and extension; never opens the user's workspace.
 */
import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { pageEndpoint } from "./readiness.mts";
import { waitForDOM as observeDOM } from "./dom-readiness.mts";
import { startProbe } from "./probe-process.mts";

assert.ok(process.argv[2], "Pass a generated VS Code settings JSON file");
assert.equal(
  process.platform,
  "linux",
  "This probe requires Linux process scopes",
);
const settings: unknown = JSON.parse(await readFile(process.argv[2], "utf8"));
assert.ok(
  settings !== null && typeof settings === "object" && !Array.isArray(settings),
);
const root = await mkdtemp(join(tmpdir(), "vscode-font-features-"));
const profile = join(root, "profile");
const display = process.env["WAYLAND_DISPLAY"];
assert.ok(display, "The probe requires a Wayland display");
assert.ok(
  process.env["XDG_RUNTIME_DIR"],
  "The session runtime directory is required",
);
let stopProbe: (() => Promise<void>) | undefined;
let socket: WebSocket | undefined;
let sequence = 0;
type CdpMessage = { id?: number; result?: unknown; error?: unknown };
const pending = new Map<number, (message: CdpMessage) => void>();

async function call<T>(
  method: string,
  params: Record<string, unknown> = {},
  duration = 15000,
): Promise<T> {
  const id = ++sequence;
  const result = new Promise<T>((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} timed out`));
    }, duration);
    pending.set(id, (message) => {
      clearTimeout(timeout);
      if (message.error) reject(new Error(JSON.stringify(message.error)));
      else if (message.result === undefined)
        reject(new Error(`${method} returned no result`));
      // CDP method results are selected by the caller after the envelope check.
      // oxlint-disable-next-line typescript/no-unsafe-type-assertion
      else resolve(message.result as T);
    });
  });
  assert.ok(socket, "CDP socket is not connected");
  socket.send(JSON.stringify({ id, method, params }));
  return result;
}

async function evaluate<T>(expression: string): Promise<T> {
  const result = await call<{
    exceptionDetails?: unknown;
    result: { value: T };
  }>("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  assert.ok(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
  return result.result.value;
}

async function waitForDOM(
  selector: string,
  minimumCount = 1,
  parentClass: string | null = null,
): Promise<void> {
  assert.ok(socket, "CDP socket is not connected");
  await observeDOM(socket, call, selector, minimumCount, parentClass);
}

try {
  const extension = join(root, "extension");
  await mkdir(join(profile, "User"), { recursive: true });
  await mkdir(extension);
  await writeFile(
    join(profile, "User", "settings.json"),
    JSON.stringify({
      ...Object.fromEntries(
        Object.entries(settings).filter(([key]) => /font/i.test(key)),
      ),
      "workbench.startupEditor": "none",
      "security.workspace.trust.enabled": false,
      "editor.codeLens": true,
      "window.zoomLevel": 0,
      "window.restoreWindows": "none",
    }),
  );
  await writeFile(join(root, "example.js"), "const example = true;\n");
  await writeFile(
    join(extension, "package.json"),
    JSON.stringify({
      name: "font-features-probe",
      publisher: "local-test",
      version: "0.0.1",
      engines: { vscode: "^1.85.0" },
      activationEvents: ["*"],
      main: "extension.cjs",
    }),
  );
  await writeFile(
    join(extension, "extension.cjs"),
    javascriptSource(new URL("./font-probe.cts", import.meta.url)),
  );
  stopProbe = startProbe(root, [
    process.env["VSCODE_BINARY"] ?? "code",
    `--user-data-dir=${profile}`,
    `--extensions-dir=${join(root, "extensions")}`,
    `--extensionDevelopmentPath=${extension}`,
    "--remote-debugging-port=0",
    "--new-window",
    join(root, "example.js"),
  ]);
  const connectedSocket = new WebSocket(await pageEndpoint(profile));
  socket = connectedSocket;
  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("CDP connection timed out")),
      15000,
    );
    connectedSocket.addEventListener(
      "open",
      () => {
        clearTimeout(timeout);
        resolve();
      },
      { once: true },
    );
    connectedSocket.addEventListener(
      "error",
      () => {
        clearTimeout(timeout);
        reject(new Error("CDP connection failed"));
      },
      { once: true },
    );
  });
  connectedSocket.addEventListener("message", (event) => {
    if (typeof event.data !== "string") return;
    const message: unknown = JSON.parse(event.data);
    if (
      message === null ||
      typeof message !== "object" ||
      !("id" in message) ||
      typeof message.id !== "number"
    )
      return;
    const receiver = pending.get(message.id);
    if (!receiver) return;
    const envelope: CdpMessage = { id: message.id };
    if ("result" in message) envelope.result = message.result;
    if ("error" in message) envelope.error = message.error;
    receiver(envelope);
    pending.delete(message.id);
  });
  await call("Emulation.setDeviceMetricsOverride", {
    width: 1200,
    height: 800,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await call("Emulation.setFocusEmulationEnabled", { enabled: true });
  await waitForDOM(".codelens-decoration > span");
  await evaluate("document.fonts.ready.then(() => true)");
  await sleep(500);
  await call("DOM.enable");
  await call("CSS.enable");
  const document = await call<{ root: { nodeId: number } }>("DOM.getDocument");
  const { nodeId } = await call<{ nodeId: number }>("DOM.querySelector", {
    nodeId: document.root.nodeId,
    selector: ".codelens-decoration > span",
  });
  const { fonts } = await call<{ fonts: Array<{ familyName: string }> }>(
    "CSS.getPlatformFontsForNode",
    { nodeId },
  );
  assert.ok(fonts.length, "The CodeLens label must render with a real font");
  console.log(
    "CodeLens fonts:",
    fonts.map((font) => font.familyName).join(", "),
  );
  const clip = await evaluate<{
    x: number;
    y: number;
    width: number;
    height: number;
    scale: number;
  }>(`(() => {
    const label = document.querySelector('.codelens-decoration');
    label.style.animation = 'none';
    const rect = label.getBoundingClientRect();
    return {x: rect.x, y: rect.y, width: rect.width, height: rect.height, scale: 1};
  })()`);
  const capture = async () => {
    await evaluate(`new Promise(resolve => requestAnimationFrame(() =>
      requestAnimationFrame(() => resolve(true))))`);
    return (await call<{ data: string }>("Page.captureScreenshot", { clip }))
      .data;
  };
  const configured = await capture();
  await evaluate(
    "document.querySelector('.codelens-decoration').style.fontFeatureSettings = 'normal'",
  );
  const normal = await capture();
  assert.ok(
    configured === normal,
    "Ordinary CodeLens letters/digits must not become decorative glyphs through inherited editor font features",
  );
  // Retain coding ligatures while removing font-specific stylistic sets.
  const features = await evaluate<string>(
    "getComputedStyle(document.querySelector('.view-lines')).fontFeatureSettings",
  );
  assert.match(
    features,
    /"calt"(?: 1| on)?(?:,|$)/,
    "Coding ligatures remain enabled",
  );
  console.log(
    "PASS: CodeLens letters and digits match normal glyphs; coding ligatures remain enabled",
  );
} finally {
  try {
    if (socket?.readyState === WebSocket.OPEN) {
      const closingSocket = socket;
      const closed = new Promise<void>((resolve) =>
        closingSocket.addEventListener("close", () => resolve(), {
          once: true,
        }),
      );
      socket.send(JSON.stringify({ id: ++sequence, method: "Browser.close" }));
      await Promise.race([closed, sleep(2000)]);
      socket.close();
    }
  } finally {
    try {
      await stopProbe?.();
    } finally {
      await rm(root, {
        recursive: true,
        force: true,
        maxRetries: 10,
        retryDelay: 200,
      });
    }
  }
}
