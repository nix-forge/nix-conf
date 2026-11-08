import { javascriptSource } from "../typescript/source.mts";
/**
 * Check rendered interaction colors in an isolated VS Code window.
 * Requires Node 24+, a graphical session, and a built Carbon theme extension.
 * Usage: node tests/vscode/check-interaction-colors.mts EXTENSION_DIRECTORY [THEME]
 * Opens a disposable workspace with the supplied theme. VSCODE_SCHEMA_OUTPUT
 * exports its registered schemas through a temporary diagnostic extension.
 */
import assert from "node:assert/strict";
import {
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve as resolvePath } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { waitForDOM as observeDOM } from "./dom-readiness.mts";
import { startProbe } from "./probe-process.mts";
import { pageEndpoint, waitForFileValue } from "./readiness.mts";

assert.ok(
  process.argv[2],
  "Usage: node check-interaction-colors.mts EXTENSION_DIRECTORY [THEME]",
);
const extension = resolvePath(process.argv[2]);
const theme = process.argv[3] ?? "Carbon Neon OLED";
const schemaOutput = process.env["VSCODE_SCHEMA_OUTPUT"];
const root = await mkdtemp(join(tmpdir(), "vscode-interaction-colors-"));
let socket: WebSocket | undefined;
let stopProbe: (() => Promise<void>) | undefined;
let sequence = 0;
type CdpMessage = { id?: number; result?: unknown; error?: unknown };
type Rgb = [number, number, number];
const pending = new Map<number, (message: CdpMessage) => void>();
const failures: string[] = [];

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

async function key(name: string, keyCode: number): Promise<void> {
  for (const type of ["keyDown", "keyUp"]) {
    await call("Input.dispatchKeyEvent", {
      type,
      key: name,
      code: name,
      windowsVirtualKeyCode: keyCode,
    });
  }
  await sleep(150);
}

// Menus focus rows through mousemove, whereas lists use CSS :hover. Dispatch
// through the real menu listener even when the compositor focuses another app.
async function hoverMenu(selector: string): Promise<void> {
  await evaluate(`document.querySelector(${JSON.stringify(selector)}).dispatchEvent(
    new MouseEvent('mousemove', {bubbles: true, movementX: 1, movementY: 1}))`);
  await waitForDOM(selector, 1, "focused");
}

function parseRgba(css: string): [number, number, number, number] {
  const channels = css.match(/[\d.]+/g)?.map(Number);
  assert.ok(channels && channels.length >= 3, `Invalid CSS color: ${css}`);
  const [red, green, blue, alpha = 1] = channels;
  assert.ok(red !== undefined && green !== undefined && blue !== undefined);
  return [red, green, blue, alpha];
}

function composite(stack: string[]): Rgb {
  return stack.toReversed().reduce(
    (base: Rgb, css) => {
      const [r, g, b, a] = parseRgba(css);
      return [
        r * a + base[0] * (1 - a),
        g * a + base[1] * (1 - a),
        b * a + base[2] * (1 - a),
      ];
    },
    [0, 0, 0] as Rgb,
  );
}

function luminance(rgb: number[]): number {
  return rgb
    .slice(0, 3)
    .map((channel) => {
      const value = channel / 255;
      return value <= 0.04045
        ? value / 12.92
        : ((value + 0.055) / 1.055) ** 2.4;
    })
    .reduce(
      (sum, channel, index) =>
        sum + channel * ([0.2126, 0.7152, 0.0722][index] ?? 0),
      0,
    );
}

async function checkRow(
  name: string,
  selector: string,
  container: string,
): Promise<void> {
  const colors = await evaluate<{ row: string[]; widget: string[] }>(`(() => {
    const row = document.querySelector(${JSON.stringify(selector)});
    const widget = document.querySelector(${JSON.stringify(container)});
    if (!row || !widget) throw new Error('Missing row or widget');
    // Composite translucent row colors over the actual ancestor backgrounds.
    const stack = element => {
      const result = [];
      for (; element; element = element.parentElement)
        result.push(getComputedStyle(element).backgroundColor);
      return result;
    };
    return {row: stack(row), widget: stack(widget)};
  })()`);
  const row = composite(colors.row);
  const background = composite(colors.widget);
  // Require a visible fill difference, not just a tiny text-color change.
  // 20/255 separates a usable dark-theme highlight from near-identical fills.
  const difference = Math.max(
    ...row.map((channel, index) => Math.abs(channel - background[index]!)),
  );
  const pass = difference >= 20;
  console.log(JSON.stringify({ theme, name, row, background, pass }));
  if (process.env["VSCODE_CHECK_OUTPUT"]) {
    await mkdir(process.env["VSCODE_CHECK_OUTPUT"], { recursive: true });
    const screenshot = await call<{ data: string }>("Page.captureScreenshot");
    await writeFile(
      join(process.env["VSCODE_CHECK_OUTPUT"], `${theme}-${name}.png`),
      Buffer.from(screenshot.data, "base64"),
    );
  }
  if (!pass) failures.push(name);
}

// These pairs are consumed together by their widgets. Check the resolved
// values because registry aliases can change even when the theme JSON does not.
async function checkContrast(
  name: string,
  foreground: string,
  background: string,
  minimum: number,
): Promise<void> {
  const colors = await evaluate<[string, string]>(`(() => {
    const host = document.querySelector('.monaco-workbench');
    const sample = document.createElement('span');
    const fg = '--vscode-' + ${JSON.stringify(foreground)}.replaceAll('.', '-');
    const bg = '--vscode-' + ${JSON.stringify(background)}.replaceAll('.', '-');
    if (!getComputedStyle(host).getPropertyValue(fg) || !getComputedStyle(host).getPropertyValue(bg))
      throw new Error('Missing color for contrast check');
    sample.style.color = 'var(' + fg + ')';
    sample.style.backgroundColor = 'var(' + bg + ')';
    host.append(sample);
    const result = [getComputedStyle(sample).color, getComputedStyle(sample).backgroundColor];
    sample.remove();
    return result;
  })()`);
  const fg = parseRgba(colors[0]);
  const bg = parseRgba(colors[1]);
  const painted = fg
    .slice(0, 3)
    .map((value, i) => value * fg[3] + bg[i]! * (1 - fg[3]));
  const l1 = luminance(painted),
    l2 = luminance(bg);
  const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
  const pass = ratio >= minimum;
  console.log(
    JSON.stringify({
      theme,
      name,
      contrast: Number(ratio.toFixed(2)),
      minimum,
      pass,
    }),
  );
  if (!pass) failures.push(name);
}

try {
  const user = join(root, "profile", "User");
  const workspace = join(root, "workspace");
  await mkdir(user, { recursive: true });
  await mkdir(workspace);
  await mkdir(join(root, "extensions"));
  await symlink(extension, join(root, "extensions", "carbon-neon-theme"));
  await writeFile(join(workspace, "example.js"), "console.\n");
  await writeFile(
    join(user, "settings.json"),
    JSON.stringify({
      "workbench.colorTheme": theme,
      "workbench.startupEditor": "none",
      "workbench.welcomePage.experimentalOnboarding": false,
      "window.restoreWindows": "none",
      "window.titleBarStyle": "custom",
      "window.menuBarVisibility": "visible",
      "security.workspace.trust.enabled": false,
      "telemetry.telemetryLevel": "off",
      "update.mode": "none",
      "extensions.autoUpdate": false,
      "editor.quickSuggestions": false,
    }),
  );
  await writeFile(
    join(user, "keybindings.json"),
    JSON.stringify([
      { key: "f6", command: "workbench.action.showCommands" },
      { key: "f7", command: "editor.action.triggerSuggest" },
    ]),
  );
  const schemaArguments: string[] = [];
  if (schemaOutput) {
    await mkdir(schemaOutput, { recursive: true });
    const probe = join(root, "schema-probe");
    await mkdir(probe);
    await writeFile(
      join(probe, "package.json"),
      JSON.stringify({
        name: "theme-schema-probe",
        publisher: "local-test",
        version: "0.0.1",
        engines: { vscode: "^1.85.0" },
        activationEvents: ["onStartupFinished"],
        main: "./extension.cjs",
      }),
    );
    await writeFile(
      join(probe, "extension.cjs"),
      javascriptSource(new URL("./schema-probe.cts", import.meta.url)),
    );
    await writeFile(
      join(probe, "output.json"),
      JSON.stringify({ output: resolvePath(schemaOutput) }),
    );
    schemaArguments.push(`--extensionDevelopmentPath=${probe}`);
  }
  stopProbe = startProbe(root, [
    process.env["VSCODE_BINARY"] ?? "code",
    `--user-data-dir=${join(root, "profile")}`,
    `--extensions-dir=${join(root, "extensions")}`,
    ...schemaArguments,
    "--new-window",
    "--remote-debugging-port=0",
    workspace,
    "--goto",
    `${join(workspace, "example.js")}:1:9`,
  ]);
  const connectedSocket = new WebSocket(
    await pageEndpoint(join(root, "profile")),
  );
  socket = connectedSocket;
  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(
      () => finish(new Error("CDP WebSocket connection timed out")),
      15000,
    );
    const opened = () => finish();
    const failed = () => finish(new Error("CDP WebSocket connection failed"));
    function finish(error?: Error): void {
      clearTimeout(timeout);
      connectedSocket.removeEventListener("open", opened);
      connectedSocket.removeEventListener("error", failed);
      connectedSocket.removeEventListener("close", failed);
      if (error) {
        connectedSocket.close();
        reject(error);
      } else resolve();
    }
    connectedSocket.addEventListener("open", opened, { once: true });
    connectedSocket.addEventListener("error", failed, { once: true });
    connectedSocket.addEventListener("close", failed, { once: true });
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
  await waitForDOM(".monaco-workbench");
  await sleep(4000);
  await call("Emulation.setFocusEmulationEnabled", { enabled: true });
  if (schemaOutput) {
    await waitForFileValue(schemaOutput, async () => {
      try {
        const version: unknown = JSON.parse(
          await readFile(join(schemaOutput, "version.json"), "utf8"),
        );
        return version !== null &&
          typeof version === "object" &&
          "version" in version &&
          typeof version.version === "string"
          ? version.version
          : null;
      } catch (error) {
        if (
          error instanceof SyntaxError ||
          (error instanceof Error && "code" in error && error.code === "ENOENT")
        )
          return null;
        throw error;
      }
    });
  }

  assert.ok(
    await evaluate<boolean>(`document.querySelector('.monaco-workbench').className
    .includes('carbon-neon-${theme.endsWith("OLED") ? "oled-" : ""}color-theme-json')`),
    "Carbon theme was not loaded",
  );

  if (schemaOutput) {
    const schema: unknown = JSON.parse(
      await readFile(join(schemaOutput, "workbench-colors.json"), "utf8"),
    );
    assert.ok(
      schema !== null &&
        typeof schema === "object" &&
        "properties" in schema &&
        schema.properties !== null &&
        typeof schema.properties === "object",
    );
    const resolvedColors = await evaluate<
      Record<string, string | null>
    >(`Object.fromEntries(${JSON.stringify(Object.keys(schema.properties))}.map(id => {
      const name = id.replaceAll('.', '-');
      return [name, getComputedStyle(document.querySelector('.monaco-workbench')).getPropertyValue('--vscode-' + name) || null];
    }))`);
    await writeFile(
      join(schemaOutput, "resolved-colors.json"),
      JSON.stringify(resolvedColors),
    );
  }

  const contrastCases: Array<[string, string, string, number]> = [
    [
      "SCM hover label",
      "scmGraph.historyItemHoverDefaultLabelForeground",
      "scmGraph.historyItemHoverDefaultLabelBackground",
      4.5,
    ],
    [
      "popup description",
      "descriptionForeground",
      "editorWidget.background",
      4.5,
    ],
    [
      "selected description",
      "descriptionForeground",
      "list.activeSelectionBackground",
      4.5,
    ],
    [
      "input placeholder",
      "input.placeholderForeground",
      "input.background",
      4.5,
    ],
    [
      "running port indicator",
      "ports.iconRunningProcessForeground",
      "sideBar.background",
      3,
    ],
    [
      "terminal command guide",
      "terminalCommandGuide.foreground",
      "terminal.background",
      3,
    ],
    [
      "comment range",
      "editorGutter.commentRangeForeground",
      "editor.background",
      3,
    ],
    [
      "comment overview",
      "editorOverviewRuler.commentForeground",
      "editor.background",
      3,
    ],
    [
      "draft comment overview",
      "editorOverviewRuler.commentDraftForeground",
      "editor.background",
      3,
    ],
    [
      "unresolved comment overview",
      "editorOverviewRuler.commentUnresolvedForeground",
      "editor.background",
      3,
    ],
  ];
  for (const [name, foreground, background, minimum] of contrastCases)
    await checkContrast(name, foreground, background, minimum);

  await waitForDOM(".explorer-folders-view .monaco-list-row.selected");
  await checkRow(
    "inactive Explorer selection",
    ".explorer-folders-view .monaco-list-row.selected",
    ".explorer-folders-view",
  );

  const fileMenu = await evaluate<{
    x: number;
    y: number;
    width: number;
    height: number;
  }>(
    "document.querySelector('.menubar-menu-button[aria-label=File]').getBoundingClientRect().toJSON()",
  );
  for (const type of ["mousePressed", "mouseReleased"]) {
    await call("Input.dispatchMouseEvent", {
      type,
      x: fileMenu.x + fileMenu.width / 2,
      y: fileMenu.y + fileMenu.height / 2,
      button: "left",
      clickCount: 1,
    });
  }
  const first = ".monaco-menu .action-item:not(.disabled) .action-menu-item";
  await waitForDOM(first);
  await hoverMenu(first);
  await checkRow("menu hover", first, ".monaco-menu > .monaco-action-bar");
  // The widget is the menu's scrollable parent, not its transparent action bar.
  // checkRow walks ancestors, so both resolve to the same painted menu surface.
  await key("ArrowDown", 40);
  await checkRow(
    "menu keyboard focus",
    ".monaco-menu .action-item.focused .action-menu-item",
    ".monaco-menu",
  );
  const submenu = ".monaco-menu .monaco-submenu-item";
  await hoverMenu(submenu);
  await key("ArrowRight", 39);
  await waitForDOM(".monaco-menu", 2);
  const child = ".monaco-submenu .action-item:not(.disabled) .action-menu-item";
  await hoverMenu(child);
  await checkRow("submenu hover", child, ".monaco-submenu .monaco-menu");
  await key("Escape", 27);
  await key("Escape", 27);
  await key("F6", 117);
  await waitForDOM(".quick-input-list .monaco-list-row.focused");
  await checkRow(
    "command palette selection",
    ".quick-input-list .monaco-list-row.focused",
    ".quick-input-widget",
  );
  await key("Escape", 27);
  await evaluate(
    "document.querySelector('.monaco-editor textarea, .monaco-editor .native-edit-context').focus()",
  );
  await key("F7", 118);
  await waitForDOM(".suggest-widget.visible .monaco-list-row.focused");
  await checkRow(
    "completion selection",
    ".suggest-widget.visible .monaco-list-row.focused",
    ".suggest-widget",
  );
  await key("Escape", 27);
  assert.deepEqual(failures, [], "Interaction backgrounds must remain visible");
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
