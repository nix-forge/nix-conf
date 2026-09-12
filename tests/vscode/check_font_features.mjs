/**
 * Render CodeLens with generated VS Code settings and check ordinary glyphs.
 * Usage: node tests/vscode/check_font_features.mjs SETTINGS_JSON
 * Requires Linux, systemd --user, dbus-run-session, Node 22+, VS Code, and a graphical session
 * with the configured fonts.
 * Uses a disposable profile and extension; never opens the user's workspace.
 */
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

assert.ok(process.argv[2], "Pass a generated VS Code settings JSON file");
assert.equal(
  process.platform,
  "linux",
  "This probe requires Linux process scopes",
);
const settings = JSON.parse(await readFile(process.argv[2], "utf8"));
const root = await mkdtemp(join(tmpdir(), "vscode-font-features-"));
const profile = join(root, "profile");
const runtime = join(root, "runtime");
const display = process.env.WAYLAND_DISPLAY;
assert.ok(display, "The probe requires a Wayland display");
assert.ok(
  process.env.XDG_RUNTIME_DIR,
  "The session runtime directory is required",
);
const waylandDisplay = isAbsolute(display)
  ? display
  : join(process.env.XDG_RUNTIME_DIR, display);
const unit = `${root.split("/").at(-1)}.scope`;
let launcher;
let launchError;
let socket;
let sequence = 0;
const pending = new Map();

async function call(method, params = {}) {
  const id = ++sequence;
  const result = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} timed out`));
    }, 15000);
    pending.set(id, (message) => {
      clearTimeout(timeout);
      if (message.error) reject(new Error(JSON.stringify(message.error)));
      else resolve(message.result);
    });
  });
  socket.send(JSON.stringify({ id, method, params }));
  return result;
}

async function evaluate(expression) {
  const result = await call("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  assert.ok(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
  return result.result.value;
}

async function waitFor(callback) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (launchError) throw launchError;
    const value = await callback();
    if (value) return value;
    await sleep(200);
  }
  throw new Error("VS Code font probe did not become ready");
}

try {
  await mkdir(runtime, { mode: 0o700 });
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
    `const vscode = require('vscode');
    exports.activate = () => vscode.languages.registerCodeLensProvider(
      {scheme: 'file'}, {provideCodeLenses: () => [new vscode.CodeLens(
        new vscode.Range(0, 0, 0, 0), {
          title: 'GitHub Issue Template - YAML 0123456789', command: ''
        })]});`,
  );
  const listener = createServer();
  await new Promise((resolve) => listener.listen(0, "127.0.0.1", resolve));
  const port = listener.address().port;
  await new Promise((resolve) => listener.close(resolve));
  launcher = spawn(
    "systemd-run",
    [
      "--user",
      "--scope",
      "--quiet",
      "--collect",
      "--expand-environment=no",
      `--unit=${unit}`,
      "--property=RuntimeMaxSec=90s",
      "--property=TimeoutStopSec=5s",
      "--",
      // Isolate both bus and runtime. A private bus with the desktop runtime
      // can start a second document portal that unmounts the real portal.
      // Keep the real Wayland socket available through its absolute path.
      "env",
      `XDG_RUNTIME_DIR=${runtime}`,
      `WAYLAND_DISPLAY=${waylandDisplay}`,
      "dbus-run-session",
      "--",
      process.env.VSCODE_BINARY ?? "code",
      "--wait",
      `--user-data-dir=${profile}`,
      `--extensions-dir=${join(root, "extensions")}`,
      `--extensionDevelopmentPath=${extension}`,
      `--remote-debugging-port=${port}`,
      "--new-window",
      join(root, "example.js"),
    ],
    { stdio: "ignore" },
  );
  launcher.on("error", (error) => {
    launchError = error;
  });
  launcher.on("exit", (code) => {
    if (code) launchError = new Error(`VS Code scope launcher exited ${code}`);
  });
  const page = await waitFor(async () => {
    try {
      const pages = await (
        await fetch(`http://127.0.0.1:${port}/json/list`, {
          signal: AbortSignal.timeout(1000),
        })
      ).json();
      return pages.find((page) => page.type === "page");
    } catch {
      return null;
    }
  });
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("CDP connection timed out")),
      15000,
    );
    socket.addEventListener(
      "open",
      () => {
        clearTimeout(timeout);
        resolve();
      },
      { once: true },
    );
    socket.addEventListener(
      "error",
      () => {
        clearTimeout(timeout);
        reject(new Error("CDP connection failed"));
      },
      { once: true },
    );
  });
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    }
  });
  await call("Emulation.setDeviceMetricsOverride", {
    width: 1200,
    height: 800,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await call("Emulation.setFocusEmulationEnabled", { enabled: true });
  await waitFor(() =>
    evaluate("!!document.querySelector('.codelens-decoration > span')"),
  );
  await evaluate("document.fonts.ready.then(() => true)");
  await sleep(500);
  await call("DOM.enable");
  await call("CSS.enable");
  const document = await call("DOM.getDocument");
  const { nodeId } = await call("DOM.querySelector", {
    nodeId: document.root.nodeId,
    selector: ".codelens-decoration > span",
  });
  const { fonts } = await call("CSS.getPlatformFontsForNode", { nodeId });
  assert.ok(fonts.length, "The CodeLens label must render with a real font");
  console.log(
    "CodeLens fonts:",
    fonts.map((font) => font.familyName).join(", "),
  );
  const clip = await evaluate(`(() => {
    const label = document.querySelector('.codelens-decoration');
    label.style.animation = 'none';
    const rect = label.getBoundingClientRect();
    return {x: rect.x, y: rect.y, width: rect.width, height: rect.height, scale: 1};
  })()`);
  const capture = async () => {
    await evaluate(`new Promise(resolve => requestAnimationFrame(() =>
      requestAnimationFrame(() => resolve(true))))`);
    return (await call("Page.captureScreenshot", { clip })).data;
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
  const features = await evaluate(
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
  if (socket?.readyState === WebSocket.OPEN) {
    const closed = new Promise((resolve) =>
      socket.addEventListener("close", resolve, { once: true }),
    );
    socket.send(JSON.stringify({ id: ++sequence, method: "Browser.close" }));
    await Promise.race([closed, sleep(2000)]);
    socket.close();
  }
  // The private bus prevents Electron from moving to a shared app scope.
  // Stop the owned scope to reap Crashpad/dconf even after early main exit.
  try {
    if (launcher) {
      const owned = [unit];
      // An unsuccessful launcher may already have been collected by systemd.
      spawnSync("systemctl", ["--user", "stop", ...owned], {
        stdio: "ignore",
        timeout: 15000,
      });
      for (const scope of owned) {
        const state = spawnSync("systemctl", ["--user", "is-active", scope], {
          encoding: "utf8",
          timeout: 5000,
        });
        assert.ok(
          ["inactive", "failed", "unknown"].includes(state.stdout?.trim()),
          `Probe scope did not stop: ${scope}`,
        );
      }
    }
  } finally {
    await rm(root, {
      recursive: true,
      force: true,
      maxRetries: 10,
      retryDelay: 200,
    });
  }
}
