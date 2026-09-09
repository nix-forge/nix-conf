/**
 * Check rendered interaction colors in an isolated VS Code window.
 * Requires Node 22+, a graphical session, and a built Carbon theme extension.
 * Usage: node tests/vscode/check_interaction_colors.mjs EXTENSION_DIRECTORY [THEME]
 * Opens a disposable workspace with the supplied theme. VSCODE_SCHEMA_OUTPUT
 * exports its registered schemas through a temporary diagnostic extension.
 */
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

assert.ok(
  process.argv[2],
  "Usage: node check_interaction_colors.mjs EXTENSION_DIRECTORY [THEME]",
);
const extension = resolve(process.argv[2]);
const theme = process.argv[3] ?? "Carbon Neon OLED";
const root = await mkdtemp(join(tmpdir(), "vscode-interaction-colors-"));
let socket;
let sequence = 0;
const pending = new Map();
const failures = [];

async function call(method, params = {}) {
  const id = ++sequence;
  const result = new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error(`${method} timed out`)),
      15000,
    );
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
    const value = await callback();
    if (value) return value;
    await sleep(200);
  }
  throw new Error("VS Code did not become ready");
}

async function key(name, keyCode) {
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
async function hoverMenu(selector) {
  await evaluate(`document.querySelector(${JSON.stringify(selector)}).dispatchEvent(
    new MouseEvent('mousemove', {bubbles: true, movementX: 1, movementY: 1}))`);
  await waitFor(() =>
    evaluate(`document.querySelector(${JSON.stringify(selector)})
    .parentElement.classList.contains('focused')`),
  );
}

async function checkRow(name, selector, container) {
  const colors = await evaluate(`(() => {
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
  function composite(stack) {
    return stack.reverse().reduce(
      (base, css) => {
        const [r, g, b, a = 1] = css.match(/[\d.]+/g).map(Number);
        return [r, g, b].map((channel, i) => channel * a + base[i] * (1 - a));
      },
      [0, 0, 0],
    );
  }
  const row = composite(colors.row);
  const background = composite(colors.widget);
  // Require a visible fill difference, not just a tiny text-color change.
  // 20/255 separates a usable dark-theme highlight from near-identical fills.
  const difference = Math.max(
    ...row.map((c, i) => Math.abs(c - background[i])),
  );
  const pass = difference >= 20;
  console.log(JSON.stringify({ theme, name, row, background, pass }));
  if (process.env.VSCODE_CHECK_OUTPUT) {
    await mkdir(process.env.VSCODE_CHECK_OUTPUT, { recursive: true });
    const screenshot = await call("Page.captureScreenshot");
    await writeFile(
      join(process.env.VSCODE_CHECK_OUTPUT, `${theme}-${name}.png`),
      Buffer.from(screenshot.data, "base64"),
    );
  }
  if (!pass) failures.push(name);
}

// These pairs are consumed together by their widgets. Check the resolved
// values because registry aliases can change even when the theme JSON does not.
async function checkContrast(name, foreground, background, minimum) {
  const colors = await evaluate(`(() => {
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
  const parse = (css) => css.match(/[\d.]+/g).map(Number);
  const [fg, bg] = colors.map(parse);
  const painted = fg
    .slice(0, 3)
    .map((value, i) => value * (fg[3] ?? 1) + bg[i] * (1 - (fg[3] ?? 1)));
  const luminance = (rgb) =>
    rgb
      .slice(0, 3)
      .map((channel) => {
        const value = channel / 255;
        return value <= 0.04045
          ? value / 12.92
          : ((value + 0.055) / 1.055) ** 2.4;
      })
      .reduce(
        (sum, channel, index) =>
          sum + channel * [0.2126, 0.7152, 0.0722][index],
        0,
      );
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
  const schemaArguments = [];
  if (process.env.VSCODE_SCHEMA_OUTPUT) {
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
      `
      const vscode = require('vscode');
      const fs = require('node:fs/promises');
      const path = require('node:path');
      exports.activate = async () => {
        const output = ${JSON.stringify(resolve(process.env.VSCODE_SCHEMA_OUTPUT))};
        await fs.mkdir(output, {recursive: true});
        for (const name of ['color-theme', 'workbench-colors', 'textmate-colors', 'token-styling', 'vscode-extensions']) {
          const data = await vscode.workspace.fs.readFile(vscode.Uri.parse('vscode://schemas/' + name));
          await fs.writeFile(path.join(output, name + '.json'), data);
        }
        await fs.writeFile(path.join(output, 'version.json'), JSON.stringify({version: vscode.version}));
      };
    `,
    );
    schemaArguments.push(`--extensionDevelopmentPath=${probe}`);
  }
  const listener = createServer();
  await new Promise((resolve) => listener.listen(0, "127.0.0.1", resolve));
  const port = listener.address().port;
  await new Promise((resolve) => listener.close(resolve));
  execFileSync(
    process.env.VSCODE_BINARY ?? "code",
    [
      `--user-data-dir=${join(root, "profile")}`,
      `--extensions-dir=${join(root, "extensions")}`,
      ...schemaArguments,
      "--new-window",
      `--remote-debugging-port=${port}`,
      workspace,
      "--goto",
      `${join(workspace, "example.js")}:1:9`,
    ],
    { stdio: "ignore", timeout: 30000 },
  );
  const page = await waitFor(async () => {
    try {
      const pages = await (
        await fetch(`http://127.0.0.1:${port}/json/list`)
      ).json();
      return pages.find((page) => page.type === "page");
    } catch {
      return null;
    }
  });
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve) =>
    socket.addEventListener("open", resolve, { once: true }),
  );
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    }
  });
  await waitFor(() =>
    evaluate("!!document.querySelector('.monaco-workbench')"),
  );
  await sleep(4000);
  await call("Emulation.setFocusEmulationEnabled", { enabled: true });
  if (process.env.VSCODE_SCHEMA_OUTPUT) {
    await waitFor(async () => {
      try {
        return JSON.parse(
          await readFile(
            join(process.env.VSCODE_SCHEMA_OUTPUT, "version.json"),
            "utf8",
          ),
        ).version;
      } catch {
        return null;
      }
    });
  }

  assert.ok(
    await evaluate(`document.querySelector('.monaco-workbench').className
    .includes('carbon-neon-${theme.endsWith("OLED") ? "oled-" : ""}color-theme-json')`),
    "Carbon theme was not loaded",
  );

  if (process.env.VSCODE_SCHEMA_OUTPUT) {
    const schema = JSON.parse(
      await readFile(
        join(process.env.VSCODE_SCHEMA_OUTPUT, "workbench-colors.json"),
        "utf8",
      ),
    );
    const resolvedColors =
      await evaluate(`Object.fromEntries(${JSON.stringify(Object.keys(schema.properties))}.map(id => {
      const name = id.replaceAll('.', '-');
      return [name, getComputedStyle(document.querySelector('.monaco-workbench')).getPropertyValue('--vscode-' + name) || null];
    }))`);
    await writeFile(
      join(process.env.VSCODE_SCHEMA_OUTPUT, "resolved-colors.json"),
      JSON.stringify(resolvedColors),
    );
  }

  for (const [name, foreground, background, minimum] of [
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
  ])
    await checkContrast(name, foreground, background, minimum);

  await waitFor(() =>
    evaluate(
      "!!document.querySelector('.explorer-folders-view .monaco-list-row.selected')",
    ),
  );
  await checkRow(
    "inactive Explorer selection",
    ".explorer-folders-view .monaco-list-row.selected",
    ".explorer-folders-view",
  );

  const fileMenu = await evaluate(
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
  await waitFor(() => evaluate(`!!document.querySelector('${first}')`));
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
  await waitFor(() =>
    evaluate("document.querySelectorAll('.monaco-menu').length > 1"),
  );
  const child = ".monaco-submenu .action-item:not(.disabled) .action-menu-item";
  await hoverMenu(child);
  await checkRow("submenu hover", child, ".monaco-submenu .monaco-menu");
  await key("Escape", 27);
  await key("Escape", 27);
  await key("F6", 117);
  await waitFor(() =>
    evaluate(
      "!!document.querySelector('.quick-input-list .monaco-list-row.focused')",
    ),
  );
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
  await waitFor(() =>
    evaluate(
      "!!document.querySelector('.suggest-widget.visible .monaco-list-row.focused')",
    ),
  );
  await checkRow(
    "completion selection",
    ".suggest-widget.visible .monaco-list-row.focused",
    ".suggest-widget",
  );
  await key("Escape", 27);
  assert.deepEqual(failures, [], "Interaction backgrounds must remain visible");
} finally {
  if (socket?.readyState === WebSocket.OPEN) {
    const closed = new Promise((resolve) =>
      socket.addEventListener("close", resolve, { once: true }),
    );
    socket.send(JSON.stringify({ id: ++sequence, method: "Browser.close" }));
    await Promise.race([closed, sleep(2000)]);
    socket.close();
  }
  await rm(root, {
    recursive: true,
    force: true,
    maxRetries: 10,
    retryDelay: 200,
  });
}
