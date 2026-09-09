/**
 * Validate a built theme with VS Code's own JSON language server and schemas.
 * Usage: node check_theme_schema.mjs VSCODE_APP SCHEMA_DIRECTORY EXTENSION
 * Export schemas with check_interaction_colors.mjs and VSCODE_SCHEMA_OUTPUT.
 * Deliberately invalid documents verify that validation is active.
 */
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

assert.ok(
  process.argv[4],
  "Expected VS Code app, schema and theme-extension directories",
);
const [app, schemas, extension] = process.argv
  .slice(2, 5)
  .map((value) => resolve(value));
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
const pending = new Map();
const diagnostics = new Map();
let expectedDocuments = 0;
let complete;
const completed = new Promise((resolve) => {
  complete = resolve;
});
function send(message) {
  const text = JSON.stringify(message);
  server.stdin.write(
    `Content-Length: ${Buffer.byteLength(text)}\r\n\r\n${text}`,
  );
}
function request(method, params) {
  const id = ++sequence;
  const result = new Promise((resolve, reject) =>
    pending.set(id, { resolve, reject }),
  );
  send({ jsonrpc: "2.0", id, method, params });
  return result;
}
function notify(method, params) {
  send({ jsonrpc: "2.0", method, params });
}
async function handle(message) {
  if (message.id !== undefined && message.method) {
    try {
      assert.equal(
        message.method,
        "vscode/content",
        `Unexpected server request: ${message.method}`,
      );
      const uri = new URL(
        Array.isArray(message.params) ? message.params[0] : message.params,
      );
      assert.equal(uri.protocol, "vscode:");
      assert.equal(uri.hostname, "schemas");
      let result;
      if (uri.pathname === "/theme-contributions") {
        // Validate the actual theme contribution schema without fetching
        // unrelated manifest schemas for tools and other extension APIs.
        const manifestSchema = JSON.parse(
          await readFile(join(schemas, "vscode-extensions.json"), "utf8"),
        );
        result = JSON.stringify({
          type: "object",
          properties: {
            themes: manifestSchema.properties.contributes.properties.themes,
          },
          required: ["themes"],
        });
      } else
        result = await readFile(
          join(schemas, encodeURIComponent(uri.pathname.slice(1)) + ".json"),
          "utf8",
        );
      send({ jsonrpc: "2.0", id: message.id, result });
    } catch (error) {
      send({
        jsonrpc: "2.0",
        id: message.id,
        error: { code: -32603, message: error.message },
      });
    }
  } else if (pending.has(message.id)) {
    const response = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) response.reject(message.error);
    else response.resolve(message.result);
  } else if (message.method === "textDocument/publishDiagnostics") {
    diagnostics.set(message.params.uri, message.params.diagnostics);
    if (diagnostics.size === expectedDocuments) complete();
  }
}
server.stderr.on("data", (data) => process.stderr.write(data));
server.stdout.on("data", (data) => {
  buffer = Buffer.concat([buffer, data]);
  while (true) {
    const boundary = buffer.indexOf("\r\n\r\n");
    if (boundary < 0) return;
    const size = Number(
      buffer
        .subarray(0, boundary)
        .toString()
        .match(/Content-Length: (\d+)/i)[1],
    );
    if (buffer.length < boundary + 4 + size) return;
    const message = JSON.parse(
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
  const actual = new Map();
  const manifestPath = join(extension, "package.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  actual.set(
    pathToFileURL(manifestPath).href,
    JSON.stringify({
      themes: manifest.contributes.themes,
      $schema: "vscode://schemas/theme-contributions",
    }),
  );
  async function addTheme(file, ancestors = []) {
    assert.ok(!ancestors.includes(file), `Theme include cycle: ${file}`);
    const text = await readFile(file, "utf8");
    const theme = JSON.parse(text);
    // The official semantic style schema tolerates unknown properties, but
    // the loader ignores them. Reject silent typos using its declared fields.
    const semanticSchema = JSON.parse(
      await readFile(join(schemas, "token-styling.json"), "utf8"),
    );
    const styles = semanticSchema.definitions.style.properties;
    for (const [selector, style] of Object.entries(
      theme.semanticTokenColors ?? {},
    )) {
      if (typeof style === "object")
        for (const field of Object.keys(style))
          assert.ok(
            Object.hasOwn(styles, field),
            `Unknown semantic style ${selector}.${field}`,
          );
    }

    if (theme.include)
      await addTheme(resolve(dirname(file), theme.include), [
        ...ancestors,
        file,
      ]);
    actual.set(pathToFileURL(file).href, text);
  }
  assert.ok(manifest.contributes.themes.length, "No contributed themes");
  for (const theme of manifest.contributes.themes)
    await addTheme(resolve(extension, theme.path));
  const canaries = [
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
  ].map(([value, message], index) => ({
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
  for (const [uri, text] of [
    ...actual,
    ...canaries.map(({ uri, text }) => [uri, text]),
  ])
    notify("textDocument/didOpen", {
      textDocument: { uri, languageId: "json", version: 1, text },
    });
  await completed;
  for (const canary of canaries)
    assert.ok(
      diagnostics
        .get(canary.uri)
        .some((diagnostic) => canary.message.test(diagnostic.message)),
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
      schemas: JSON.parse(await readFile(join(schemas, "version.json"), "utf8"))
        .version,
      documents: actual.size,
      rejectedCanaries: canaries.length,
      pass: true,
    }),
  );
} finally {
  clearTimeout(timeout);
  server.kill();
}
