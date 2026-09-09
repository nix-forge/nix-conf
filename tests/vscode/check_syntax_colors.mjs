/**
 * Tokenize real language fixtures with the selected VS Code TextMate engine.
 * Usage: node check_syntax_colors.mjs VSCODE_APP THEME_FILE [EXTRA_EXTENSIONS]
 * VSCODE_APP is resources/app; THEME_FILE must contain generated color values.
 * Include the configured Nix grammar in EXTRA_EXTENSIONS to exercise Nix too.
 */
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";

assert.ok(
  process.argv[3],
  "Expected VS Code app directory and generated theme file",
);
const app = resolve(process.argv[2]);
const require = createRequire(import.meta.url);
const textmate = require(join(app, "node_modules/vscode-textmate"));
const oniguruma = require(join(app, "node_modules/vscode-oniguruma"));
await oniguruma.loadWASM(
  await readFile(join(app, "node_modules/vscode-oniguruma/release/onig.wasm")),
);

async function loadTheme(file) {
  const child = JSON.parse(await readFile(file, "utf8"));
  const parent = child.include
    ? await loadTheme(resolve(dirname(file), child.include))
    : {};
  return {
    colors: { ...parent.colors, ...child.colors },
    tokenColors: [...(parent.tokenColors ?? []), ...(child.tokenColors ?? [])],
    semanticTokenColors: {
      ...parent.semanticTokenColors,
      ...child.semanticTokenColors,
    },
  };
}
const theme = await loadTheme(resolve(process.argv[3]));
const grammars = new Map();
const languages = new Map();
const injections = new Map();
for (const directory of [join(app, "extensions"), ...process.argv.slice(4)]) {
  for (const name of await readdir(directory, { withFileTypes: true })) {
    if (!name.isDirectory() && !name.isSymbolicLink()) continue;
    const folder = join(directory, name.name);
    let manifest;
    try {
      manifest = JSON.parse(
        await readFile(join(folder, "package.json"), "utf8"),
      );
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    for (const grammar of manifest.contributes?.grammars ?? []) {
      grammars.set(grammar.scopeName, resolve(folder, grammar.path));
      if (grammar.language) languages.set(grammar.language, grammar.scopeName);
      for (const scope of grammar.injectTo ?? [])
        injections.set(scope, [
          ...(injections.get(scope) ?? []),
          grammar.scopeName,
        ]);
    }
  }
}
const registry = new textmate.Registry({
  // Match VS Code's loader: defaults come from editor.foreground, and unscoped
  // theme rules are ignored. TextMate themes use settings, not tokenColors.
  theme: {
    settings: [
      { settings: { foreground: theme.colors["editor.foreground"] } },
      ...theme.tokenColors.filter((rule) => rule.scope),
    ],
  },
  onigLib: Promise.resolve({
    createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
    createOnigString: (text) => new oniguruma.OnigString(text),
  }),
  loadGrammar: async (scope) => {
    const file = grammars.get(scope);
    return file
      ? textmate.parseRawGrammar(await readFile(file, "utf8"), file)
      : null;
  },
  getInjections: (scope) => injections.get(scope) ?? [],
});

// Each fixture names a language construct and its intended semantic role.
// This checks grammar output, precedence and fallbacks, not literal scope lists.
const fixtures = [
  {
    language: "typescript",
    source:
      'interface Person { name: string; }\nconst person: Person = { name: "Ada" };\nperson.name + "!";\nconst pattern = /hello+/gi;',
    probes: [
      { line: 0, text: "Person", role: "interface" },
      { line: 0, text: "name", role: "property" },
      { line: 1, text: "Ada", role: "string" },
      { line: 2, text: "name", role: "property" },
      { line: 2, text: "+", role: "operator" },
      { line: 3, text: "hello", role: "regexp" },
    ],
  },
  {
    language: "python",
    source:
      '@dataclass\nclass Person:\n    age: int = 42\ndef greet(person: Person):\n    return "Hello " + person.name',
    probes: [
      { line: 0, text: "dataclass", role: "decorator" },
      { line: 1, text: "Person", role: "class" },
      { line: 2, text: "42", role: "number" },
      { line: 3, text: "greet", role: "function" },
      { line: 4, text: "+", role: "operator" },
      { line: 4, text: "name", role: "property" },
    ],
  },
  {
    language: "markdown",
    source:
      "# Heading\n**strong** and *emphasis* with `inline code`.\n```typescript\nconst count = 42;\n```",
    probes: [
      { line: 0, text: "Heading", style: 2 },
      { line: 1, text: "strong", style: 2 },
      { line: 1, text: "emphasis", style: 1 },
      { line: 1, text: "inline code", role: "string" },
      { line: 3, text: "42", role: "number" },
    ],
  },
  {
    language: "html",
    source: '<div class="card">Hello</div>',
    probes: [
      { line: 0, text: "class", role: "property" },
      { line: 0, text: "card", role: "string" },
    ],
  },
  {
    language: "css",
    source: ".card { color: #80cbc4; margin: 1rem; }",
    probes: [{ line: 0, text: "color", role: "property" }],
  },
  {
    language: "json",
    source: '{"name": "Ada", "age": 42}',
    probes: [
      { line: 0, text: "name", role: "property" },
      { line: 0, text: "Ada", role: "string" },
      { line: 0, text: "42", role: "number" },
    ],
  },
];
fixtures.push(
  {
    language: "diff",
    source: "+added\n-removed\n!changed",
    probes: [
      { line: 0, text: "added", workbenchRole: "editorGutter.addedBackground" },
      {
        line: 1,
        text: "removed",
        workbenchRole: "editorGutter.deletedBackground",
      },
      { line: 2, text: "changed", role: "decorator" },
    ],
  },
  {
    language: "cpp",
    source: "namespace Shapes { class Point {}; }",
    probes: [
      { line: 0, text: "Shapes", role: "namespace" },
      { line: 0, text: "Point", role: "class" },
    ],
  },
  {
    language: "java",
    source: 'class Person { String name = "Ada"; int age = 42; }',
    probes: [
      { line: 0, text: "Person", role: "class" },
      { line: 0, text: "Ada", role: "string" },
      { line: 0, text: "42", role: "number" },
    ],
  },
  {
    language: "shellscript",
    source: 'echo "hello"',
    probes: [
      { line: 0, text: "echo", role: "function" },
      { line: 0, text: "hello", role: "string" },
    ],
  },
  {
    language: "yaml",
    source: 'name: "Ada"\nage: 42',
    probes: [
      { line: 0, text: "name", role: "property" },
      { line: 0, text: "Ada", role: "string" },
      { line: 1, text: "42", role: "number" },
    ],
  },
  {
    language: "markdown",
    source: "**bold *both*** and ~~removed~~",
    probes: [
      { line: 0, text: "both", style: 3 },
      { line: 0, text: "removed", style: 8 },
    ],
  },
);
if (process.argv[4])
  fixtures.push({
    language: "nix",
    source: 'let count = 42; in "hello"',
    probes: [
      { line: 0, text: "42", role: "number" },
      { line: 0, text: "hello", role: "string" },
    ],
  });
let count = 0;
const failures = [];
for (const fixture of fixtures) {
  assert.ok(
    languages.has(fixture.language),
    `Missing ${fixture.language} grammar`,
  );
  const grammar = await registry.loadGrammar(languages.get(fixture.language));
  let state = textmate.INITIAL;
  for (const [lineNumber, line] of fixture.source.split("\n").entries()) {
    const result = grammar.tokenizeLine2(line, state);
    state = result.ruleStack;
    for (const probe of fixture.probes.filter(
      (probe) => probe.line === lineNumber,
    )) {
      const column = line.indexOf(probe.text);
      assert.ok(column >= 0, `Fixture text not found: ${probe.text}`);
      let metadata;
      for (let i = 0; i < result.tokens.length; i += 2)
        if (result.tokens[i] <= column) metadata = result.tokens[i + 1];
      // VS Code's encoded token metadata uses bits 15..23 for the foreground
      // index and 11..14 for italic/bold/underline/strikethrough style flags.
      const color = registry.getColorMap()[(metadata >>> 15) & 511];
      const style = (metadata >>> 11) & 15;
      const semantic = theme.semanticTokenColors[probe.role];
      const expected = probe.workbenchRole
        ? theme.colors[probe.workbenchRole].slice(0, 7)
        : typeof semantic === "string"
          ? semantic
          : semantic?.foreground;
      const pass = probe.style
        ? (style & probe.style) === probe.style
        : color.toLowerCase() === expected?.toLowerCase();
      count++;
      if (!pass)
        failures.push({
          language: fixture.language,
          text: probe.text,
          color,
          style,
          expected: probe.style ?? expected,
        });
    }
  }
}
console.log(
  JSON.stringify(
    {
      languages: new Set(fixtures.map((fixture) => fixture.language)).size,
      probes: count,
      failures,
    },
    null,
    2,
  ),
);
assert.deepEqual(
  failures,
  [],
  "Lexical highlighting must preserve language roles and Markdown emphasis",
);
registry.dispose();
