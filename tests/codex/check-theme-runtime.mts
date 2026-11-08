/**
 * Check a disposable Codex window with its own validators, CSS and Shiki worker.
 * Usage: node check-theme-runtime.mts CDP_URL EXTRACTED_ASSETS SETTINGS_JSON
 * Start a separate app with CODEX_HOME and CODEX_ELECTRON_USER_DATA_PATH pointing
 * at private temporary directories, plus --user-data-dir and --remote-debugging-port.
 * CODEX_THEME_COLORS_ONLY=1 skips controls unavailable at the sign-in screen.
 * Never point this at a working session. No messages or menu actions are submitted.
 */
import { javascriptSource } from "../typescript/source.mts";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

type JsonRecord = Record<string, unknown>;
type CdpMessage = { id?: number; result?: unknown; error?: unknown };
type Evaluation<T> = { exceptionDetails?: unknown; result: { value: T } };

function record(value: unknown): value is JsonRecord {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

const [endpoint, assets, configPath] = process.argv.slice(2);
assert.ok(
  endpoint && assets && configPath,
  "Expected CDP URL, extracted assets and generated settings",
);
const colorsOnly = process.env["CODEX_THEME_COLORS_ONLY"] === "1";
const parsedConfig: unknown = JSON.parse(await readFile(configPath, "utf8"));
assert.ok(record(parsedConfig) && record(parsedConfig["desktop"]));
const config = parsedConfig["desktop"];
assert.equal(
  config["appearanceDarkCodeThemeId"],
  "codex",
  "This fixture checks the selected Codex syntax preset",
);
const files = await readdir(assets);
const initial = files.find((name) => /^app-initial-.*\.js$/.test(name));
assert.ok(initial, "Missing initial application bundle");
const source = await readFile(join(assets, initial), "utf8");
function exported(name: string): string {
  const entry = source
    .slice(source.lastIndexOf("export{"))
    .split(",")
    .find((candidate) =>
      candidate.replace(/^export\{/, "").startsWith(`${name} as `),
    );
  assert.ok(
    entry,
    `Missing app export for ${name}; review this build's adapter`,
  );
  const exportedName = entry.split(" as ")[1];
  assert.ok(exportedName, `Malformed app export for ${name}`);
  return exportedName.replace(/[};].*$/, "");
}
const settingsMatch = source.match(
  /([\w$]+)=\{theme:[\w$]+\(\{agentAccess:`read-write`,default:`system`,description:`Preferred app appearance mode`/,
);
const applyMatch = source.match(
  /function ([\w$]+)\(e,t,n,r,i=!0\)\{e\.classList\.toggle\(`electron-dark`/,
);
const settingsName = settingsMatch?.[1];
const applyName = applyMatch?.[1];
assert.ok(settingsName && applyName, "Missing theme adapter symbols");
const pages: unknown = await (
  await fetch(`${endpoint}/json/list`, { signal: AbortSignal.timeout(15000) })
).json();
assert.ok(Array.isArray(pages), "Expected CDP page list");
const page: unknown = pages.find(
  (candidate: unknown) =>
    record(candidate) &&
    candidate["type"] === "page" &&
    candidate["url"] === "app://-/index.html",
);
assert.ok(
  record(page) && typeof page["webSocketDebuggerUrl"] === "string",
  "Expected isolated Codex application window",
);
const socket = new WebSocket(page["webSocketDebuggerUrl"]);
await new Promise<void>((resolve, reject) => {
  const timeout = setTimeout(
    () => finish(new Error("CDP WebSocket connection timed out")),
    15000,
  );
  const opened = () => finish();
  const failed = () => finish(new Error("CDP WebSocket connection failed"));
  function finish(error?: Error): void {
    clearTimeout(timeout);
    socket.removeEventListener("open", opened);
    socket.removeEventListener("error", failed);
    socket.removeEventListener("close", failed);
    if (error) {
      socket.close();
      reject(error);
    } else resolve();
  }
  socket.addEventListener("open", opened, { once: true });
  socket.addEventListener("error", failed, { once: true });
  socket.addEventListener("close", failed, { once: true });
});
let sequence = 0;
const pending = new Map<number, (message: CdpMessage) => void>();
socket.addEventListener("message", (event) => {
  if (typeof event.data !== "string") return;
  const message: unknown = JSON.parse(event.data);
  if (!record(message) || typeof message["id"] !== "number") return;
  const receiver = pending.get(message["id"]);
  if (!receiver) return;
  receiver(message);
  pending.delete(message["id"]);
});
function call<T>(method: string, params: JsonRecord = {}): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const id = ++sequence;
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(Error(`${method} timed out`));
    }, 30000);
    pending.set(id, (message: CdpMessage) => {
      clearTimeout(timeout);
      if (message.error) reject(Error(JSON.stringify(message.error)));
      else if (message.result === undefined)
        reject(Error(`${method} returned no result`));
      // CDP method results are selected by the caller after the envelope check.
      // oxlint-disable-next-line typescript/no-unsafe-type-assertion
      else resolve(message.result as T);
    });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
async function evaluate<T>(expression: string): Promise<T> {
  const response = await call<Evaluation<T>>("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  assert.ok(
    !response.exceptionDetails,
    JSON.stringify(response.exceptionDetails),
  );
  return response.result.value;
}
const rendererSource = javascriptSource(
  new URL("./theme-audit-renderer.ts", import.meta.url),
);
function render(
  action: Parameters<typeof codexThemeRenderer>[0],
  options: Parameters<typeof codexThemeRenderer>[1] = {},
): string {
  return `${rendererSource}\ncodexThemeRenderer(${JSON.stringify(action)}, ${JSON.stringify(options)})`;
}
const failures: string[] = [];
try {
  const schema = await evaluate<{
    errors: string[];
    rejected: number;
    colors: JsonRecord;
    checked: number;
    derivedColors: number;
  }>(
    render("schema", {
      initial,
      settingsExport: exported(settingsName),
      applyExport: exported(applyName),
      wanted: config,
    }),
  );
  assert.deepEqual(schema.errors, []);
  assert.equal(schema.rejected, 3);
  const { colors, ...schemaSummary } = schema;
  console.log(JSON.stringify({ schema: schemaSummary }));
  if (process.env["CODEX_THEME_COLOR_OUTPUT"]) {
    const { writeFile } = await import("node:fs/promises");
    await writeFile(
      process.env["CODEX_THEME_COLOR_OUTPUT"],
      JSON.stringify(colors, null, 2),
    );
  }

  const contrast = await evaluate<
    Array<{ name: string; ratio: number; pass: boolean }>
  >(
    render("contrast", {
      labels: colorsOnly
        ? []
        : ["File", "Edit", "View", "Help", "Choose project"],
    }),
  );
  for (const result of contrast) {
    console.log(JSON.stringify(result));
    if (!result.pass) failures.push(result.name);
  }

  // Force CSS states on a real control so compositor focus cannot hide :hover.
  // This verifies its shipped styles; it does not test pointer event delivery.
  if (!colorsOnly) {
    await call("DOM.enable");
    await call("CSS.enable");
    const { root } = await call<{ root: { nodeId: number } }>(
      "DOM.getDocument",
    );
    const { nodeId } = await call<{ nodeId: number }>("DOM.querySelector", {
      nodeId: root.nodeId,
      selector: 'button[role="menuitem"]',
    });
    const before = await evaluate<string>(
      "getComputedStyle(document.querySelector('button[role=menuitem]')).backgroundColor",
    );
    for (const state of ["hover", "focus-visible"]) {
      await call("CSS.forcePseudoState", {
        nodeId,
        forcedPseudoClasses: [state],
      });
      const after = await evaluate<string>(
        "getComputedStyle(document.querySelector('button[role=menuitem]')).backgroundColor",
      );
      assert.notEqual(before, after, `${state} must change the control fill`);
      console.log(JSON.stringify({ state, before, after, pass: true }));
    }
    await call("CSS.forcePseudoState", { nodeId, forcedPseudoClasses: [] });
  }

  // Exercise the app's actual rich-Markdown style extension in CodeMirror.
  // The fixture supplies tags directly; Markdown parsing is tested separately
  // by the source-highlighting worker below.
  const richModule = files.find((name) =>
    /^file-editor-theme-.*\.js$/.test(name),
  );
  assert.ok(richModule, "Missing rich Markdown theme bundle");
  const rich = await evaluate<Record<string, boolean>>(
    render("rich", { richModule }),
  );
  assert.ok(
    Object.values(rich).every(Boolean),
    "Rich Markdown must preserve text semantics",
  );
  console.log(JSON.stringify({ richMarkdown: rich }));

  const languageFixtures: Array<[string, string, string]> = [
    [
      "typescript",
      "example.ts",
      "// comment\ninterface Person { name: string; }\nconst pattern = /hello+/gi;\nconst count = 42;",
    ],
    [
      "javascript",
      "example.js",
      '// comment\nfunction greet(name) { return "Hello " + name; }',
    ],
    [
      "python",
      "example.py",
      '# comment\n@dataclass\nclass Person:\n    age: int = 42\n    name = "Ada"',
    ],
    ["nix", "example.nix", '# comment\nlet count = 42; in "hello"'],
    ["json", "example.json", '{"name": "Ada", "age": 42}'],
    ["yaml", "example.yaml", '# comment\nname: "Ada"\nage: 42'],
    ["html", "example.html", '<div class="card">Hello</div>'],
    ["css", "example.css", ".card { color: #80cbc4; margin: 1rem; }"],
    ["cpp", "example.cpp", "// comment\nnamespace Shapes { class Point {}; }"],
    [
      "java",
      "example.java",
      '// comment\nclass Person { String name = "Ada"; int age = 42; }',
    ],
    ["shellscript", "example.sh", '# comment\necho "hello"'],
    [
      "markdown",
      "example.md",
      "# Heading\n**bold** and *italic* with `code` and [link](https://example.org).",
    ],
  ];
  const modules: Record<string, string> = {};
  for (const [language] of languageFixtures) {
    const candidates = files.filter(
      (name) => name.startsWith(`${language}-`) && name.endsWith(".js"),
    );
    for (const file of candidates) {
      if ((await readFile(join(assets, file), "utf8")).includes("as default")) {
        modules[language] = file;
        break;
      }
    }
    assert.ok(modules[language], `Missing bundled grammar for ${language}`);
  }
  const themeModule = files.find((name) => /^codex-dark-.*\.js$/.test(name));
  assert.ok(themeModule, "Missing Codex dark theme bundle");
  let workerModule;
  for (const name of files.filter((candidate) =>
    /^worker-.*\.js$/.test(candidate),
  )) {
    const workerSource = await readFile(join(assets, name), "utf8");
    if (
      workerSource.includes("preferredHighlighter") &&
      workerSource.includes("`shiki-js`")
    ) {
      workerModule = name;
      break;
    }
  }
  assert.ok(
    workerModule,
    "Missing native Shiki worker; review this build's adapter",
  );
  const syntax = await evaluate<
    Array<{
      language: string;
      pass: boolean;
      boldDifferentiated?: boolean;
      italic?: boolean;
    }>
  >(
    render("syntax", {
      themeModule,
      modules,
      workerModule,
      fixtures: languageFixtures,
    }),
  );
  for (const result of syntax) {
    console.log(JSON.stringify(result));
    if (
      !result.pass ||
      result.boldDifferentiated === false ||
      result.italic === false
    )
      failures.push(result.language);
  }
  assert.deepEqual(
    failures,
    [],
    "Theme must retain readable controls and syntax",
  );
} finally {
  await evaluate(render("cleanup")).catch(() => {});
  socket.close();
}
