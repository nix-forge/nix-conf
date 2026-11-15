/**
 * Validate a built theme with VS Code's own JSON language server and schemas.
 * Usage: node check-theme-schema.mts VSCODE_APP SCHEMA_DIRECTORY EXTENSION
 * Export schemas with check-interaction-colors.mts and VSCODE_SCHEMA_OUTPUT.
 * Deliberately invalid documents verify that validation is active.
 */
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve as resolvePath } from "node:path";
import { pathToFileURL } from "node:url";

type JsonRecord = Record<string, unknown>;
type Diagnostic = { message: string };

function record(value: unknown): value is JsonRecord {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function field(value: unknown, ...keys: string[]): unknown {
  let current = value;
  for (const key of keys) {
    assert.ok(record(current) && key in current, `Missing ${keys.join(".")}`);
    current = current[key];
  }
  return current;
}

function parseObject(text: string): JsonRecord {
  const value: unknown = JSON.parse(text);
  assert.ok(record(value), "Expected JSON object");
  return value;
}

assert.ok(
  process.argv[2] && process.argv[3] && process.argv[4],
  "Expected VS Code app, schema and theme-extension directories",
);
const app = resolvePath(process.argv[2]);
const schemas = resolvePath(process.argv[3]);
const extension = resolvePath(process.argv[4]);
const server = spawn(
  process.execPath,
  [
    join(
      app,
      "extensions/json-language-features/server/dist/node/jsonServerMain.js",
    ),
    "--stdio",
  ],
  { stdio: ["pipe", "pipe", "pipe"] },
);
let buffer = Buffer.alloc(0);
let sequence = 0;
const pending = new Map<
  number,
  { resolve(value: unknown): void; reject(reason: unknown): void }
>();
const diagnostics = new Map<string, Diagnostic[]>();
let expectedDocuments = 0;
let complete: () => void = () => {};
const completed = new Promise<void>((resolve) => {
  complete = resolve;
});
function send(message: JsonRecord): void {
  const text = JSON.stringify(message);
  assert.ok(server.stdin);
  server.stdin.write(
    `Content-Length: ${Buffer.byteLength(text)}\r\n\r\n${text}`,
  );
}
function request(method: string, params: JsonRecord): Promise<unknown> {
  const id = ++sequence;
  const result = new Promise<unknown>((resolve, reject) =>
    pending.set(id, { resolve, reject }),
  );
  send({ jsonrpc: "2.0", id, method, params });
  return result;
}
function notify(method: string, params: JsonRecord): void {
  send({ jsonrpc: "2.0", method, params });
}
async function handle(message: unknown): Promise<void> {
  assert.ok(record(message), "Invalid JSON language server message");
  if (message["id"] !== undefined && message["method"]) {
    assert.ok(
      typeof message["method"] === "string",
      "Invalid language server method",
    );
    try {
      assert.equal(
        message["method"],
        "vscode/content",
        `Unexpected server request: ${message["method"]}`,
      );
      const uriValue: unknown = Array.isArray(message["params"])
        ? message["params"][0]
        : message["params"];
      assert.ok(typeof uriValue === "string", "Expected schema URI");
      const uri = new URL(uriValue);
      assert.equal(uri.protocol, "vscode:");
      assert.equal(uri.hostname, "schemas");
      let result: string;
      if (uri.pathname === "/theme-contributions") {
        // Validate the actual theme contribution schema without fetching
        // unrelated manifest schemas for tools and other extension APIs.
        const manifestSchema = parseObject(
          await readFile(join(schemas, "vscode-extensions.json"), "utf8"),
        );
        result = JSON.stringify({
          type: "object",
          properties: {
            themes: field(
              manifestSchema,
              "properties",
              "contributes",
              "properties",
              "themes",
            ),
          },
          required: ["themes"],
        });
      } else
        result = await readFile(
          join(schemas, encodeURIComponent(uri.pathname.slice(1)) + ".json"),
          "utf8",
        );
      send({ jsonrpc: "2.0", id: message["id"], result });
    } catch (error) {
      send({
        jsonrpc: "2.0",
        id: message["id"],
        error: {
          code: -32603,
          message: error instanceof Error ? error.message : String(error),
        },
      });
    }
  } else if (typeof message["id"] === "number" && pending.has(message["id"])) {
    const response = pending.get(message["id"]);
    assert.ok(response);
    pending.delete(message["id"]);
    if (message["error"]) response.reject(message["error"]);
    else response.resolve(message["result"]);
  } else if (message["method"] === "textDocument/publishDiagnostics") {
    const uri = field(message["params"], "uri");
    const reported = field(message["params"], "diagnostics");
    assert.ok(typeof uri === "string" && Array.isArray(reported));
    const entries: Diagnostic[] = reported.map((entry: unknown) => {
      const text = field(entry, "message");
      assert.ok(typeof text === "string");
      return { message: text };
    });
    diagnostics.set(uri, entries);
    if (diagnostics.size === expectedDocuments) complete();
  }
}
assert.ok(server.stderr && server.stdout);
server.stderr.on("data", (data: Buffer) => process.stderr.write(data));
server.stdout.on("data", (data: Buffer) => {
  buffer = Buffer.concat([buffer, data]);
  while (true) {
    const boundary = buffer.indexOf("\r\n\r\n");
    if (boundary < 0) return;
    const header = buffer
      .subarray(0, boundary)
      .toString()
      .match(/Content-Length: (\d+)/i);
    assert.ok(header?.[1], "Missing LSP Content-Length");
    const size = Number(header[1]);
    if (buffer.length < boundary + 4 + size) return;
    const message: unknown = JSON.parse(
      buffer.subarray(boundary + 4, boundary + 4 + size).toString(),
    );
    buffer = buffer.subarray(boundary + 4 + size);
    handle(message).catch((error) => {
      console.error(error);
      process.exitCode = 1;
      server.kill();
    });
  }
});
const timeout = setTimeout(() => {
  console.error("JSON schema validation timed out");
  server.kill();
  process.exit(1);
}, 20000);
try {
  const actual = new Map<string, string>();
  const manifestPath = join(extension, "package.json");
  const manifest = parseObject(await readFile(manifestPath, "utf8"));
  const themes = field(manifest, "contributes", "themes");
  assert.ok(
    Array.isArray(themes) && themes.length > 0,
    "No contributed themes",
  );
  actual.set(
    pathToFileURL(manifestPath).href,
    JSON.stringify({
      themes,
      $schema: "vscode://schemas/theme-contributions",
    }),
  );
  async function addTheme(
    file: string,
    ancestors: string[] = [],
  ): Promise<void> {
    assert.ok(!ancestors.includes(file), `Theme include cycle: ${file}`);
    const text = await readFile(file, "utf8");
    const theme = parseObject(text);
    // The official semantic style schema tolerates unknown properties, but
    // the loader ignores them. Reject silent typos using its declared fields.
    const semanticSchema = parseObject(
      await readFile(join(schemas, "token-styling.json"), "utf8"),
    );
    const styles = field(semanticSchema, "definitions", "style", "properties");
    assert.ok(record(styles));
    const semanticColors = theme["semanticTokenColors"];
    for (const [selector, style] of Object.entries(
      record(semanticColors) ? semanticColors : {},
    )) {
      if (record(style))
        for (const styleField of Object.keys(style))
          assert.ok(
            Object.hasOwn(styles, styleField),
            `Unknown semantic style ${selector}.${styleField}`,
          );
    }

    if (typeof theme["include"] === "string")
      await addTheme(resolvePath(dirname(file), theme["include"]), [
        ...ancestors,
        file,
      ]);
    actual.set(pathToFileURL(file).href, text);
  }
  for (const theme of themes) {
    const themePath = field(theme, "path");
    assert.ok(typeof themePath === "string");
    await addTheme(resolvePath(extension, themePath));
  }
  const canaryFixtures: Array<[JsonRecord, RegExp]> = [
    [{ colors: { notARegisteredColor: "#ffffff" } }, /notARegisteredColor/],
    [
      {
        tokenColors: [
          { scope: "comment", settings: { background: "#000000" } },
        ],
      },
      /not supported/,
    ],
    [
      { colors: { "editor.selectionHighlightBackground": "#ffffff" } },
      /transparen/i,
    ],
    [
      { semanticTokenColors: { variable: { fontStyle: "blink" } } },
      /Font style/,
    ],
  ];
  const canaries = canaryFixtures.map(([value, message], index) => ({
    uri: `file:///theme-schema-canary-${index}.json`,
    text: JSON.stringify({ $schema: "vscode://schemas/color-theme", ...value }),
    message,
  }));
  expectedDocuments = actual.size + canaries.length;
  await request("initialize", {
    processId: process.pid,
    rootUri: null,
    capabilities: {},
    initializationOptions: {
      handledSchemaProtocols: ["vscode"],
      customCapabilities: { schemaContentRequest: true },
    },
  });
  notify("initialized", {});
  const documents: Array<[string, string]> = [
    ...actual,
    ...canaries.map(({ uri, text }): [string, string] => [uri, text]),
  ];
  for (const [uri, text] of documents)
    notify("textDocument/didOpen", {
      textDocument: { uri, languageId: "json", version: 1, text },
    });
  await completed;
  for (const canary of canaries)
    assert.ok(
      diagnostics
        .get(canary.uri)
        ?.some((diagnostic) => canary.message.test(diagnostic.message)),
      `Schema canary was not rejected: ${canary.uri}`,
    );
  for (const uri of actual.keys())
    assert.deepEqual(
      diagnostics.get(uri),
      [],
      `Invalid theme document: ${uri}`,
    );
  console.log(
    JSON.stringify({
      schemas: field(
        parseObject(await readFile(join(schemas, "version.json"), "utf8")),
        "version",
      ),
      documents: actual.size,
      rejectedCanaries: canaries.length,
      pass: true,
    }),
  );
} finally {
  clearTimeout(timeout);
  server.kill();
}
