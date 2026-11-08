/**
 * Tokenize real language fixtures with the selected VS Code TextMate engine.
 * Usage: node check-syntax-colors.mts VSCODE_APP THEME_FILE [EXTRA_EXTENSIONS]
 * VSCODE_APP is resources/app; THEME_FILE must contain generated color values.
 * Include the configured Nix grammar in EXTRA_EXTENSIONS to exercise Nix too.
 */
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import type * as Textmate from "vscode-textmate";
import type * as Oniguruma from "vscode-oniguruma";

type JsonRecord = Record<string, unknown>;
type TokenRule = {
  scope?: string | string[];
  settings: { foreground?: string; fontStyle?: string };
};
type Theme = {
  colors: Record<string, string>;
  tokenColors: TokenRule[];
  semanticTokenColors: Record<string, string | { foreground?: string }>;
};
type GrammarContribution = {
  scopeName: string;
  path: string;
  language?: string;
  injectTo: string[];
};
type Probe = {
  line: number;
  text: string;
  role?: string;
  style?: number;
  workbenchRole?: string;
};
type Fixture = { language: string; source: string; probes: Probe[] };

function record(value: unknown): value is JsonRecord {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function stringMap(value: unknown): Record<string, string> {
  if (!record(value)) return {};
  return Object.fromEntries(
    Object.entries(value).filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    ),
  );
}

function contributions(value: unknown): GrammarContribution[] {
  if (
    !record(value) ||
    !record(value["contributes"]) ||
    !Array.isArray(value["contributes"]["grammars"])
  )
    return [];
  return value["contributes"]["grammars"].flatMap((entry: unknown) => {
    if (
      !record(entry) ||
      typeof entry["scopeName"] !== "string" ||
      typeof entry["path"] !== "string"
    )
      return [];
    const contribution: GrammarContribution = {
      scopeName: entry["scopeName"],
      path: entry["path"],
      injectTo: [],
    };
    if (typeof entry["language"] === "string")
      contribution.language = entry["language"];
    if (Array.isArray(entry["injectTo"]))
      contribution.injectTo = entry["injectTo"].filter(
        (scope): scope is string => typeof scope === "string",
      );
    return [contribution];
  });
}

assert.ok(
  process.argv[3],
  "Expected VS Code app directory and generated theme file",
);
assert.ok(process.argv[2]);
const app = resolve(process.argv[2]);
const require = createRequire(import.meta.url);
// The application bundles these exact APIs at runtime; npm supplies their declarations.
function textmateAPI(
  value: unknown,
): value is Pick<typeof Textmate, "Registry" | "parseRawGrammar" | "INITIAL"> {
  return (
    record(value) &&
    typeof value["Registry"] === "function" &&
    typeof value["parseRawGrammar"] === "function" &&
    record(value["INITIAL"])
  );
}
function onigurumaAPI(
  value: unknown,
): value is Pick<typeof Oniguruma, "loadWASM" | "OnigScanner" | "OnigString"> {
  return (
    record(value) &&
    typeof value["loadWASM"] === "function" &&
    typeof value["OnigScanner"] === "function" &&
    typeof value["OnigString"] === "function"
  );
}
const textmate: unknown = require(join(app, "node_modules/vscode-textmate"));
const oniguruma: unknown = require(join(app, "node_modules/vscode-oniguruma"));
assert.ok(textmateAPI(textmate), "Invalid VS Code TextMate API");
assert.ok(onigurumaAPI(oniguruma), "Invalid VS Code Oniguruma API");
await oniguruma.loadWASM(
  await readFile(join(app, "node_modules/vscode-oniguruma/release/onig.wasm")),
);

async function loadTheme(file: string): Promise<Theme> {
  const child: unknown = JSON.parse(await readFile(file, "utf8"));
  assert.ok(record(child), `Invalid theme JSON: ${file}`);
  const parent =
    typeof child["include"] === "string"
      ? await loadTheme(resolve(dirname(file), child["include"]))
      : ({
          colors: {},
          tokenColors: [],
          semanticTokenColors: {},
        } satisfies Theme);
  const tokenColors = Array.isArray(child["tokenColors"])
    ? child["tokenColors"].filter(
        (rule): rule is TokenRule => record(rule) && record(rule["settings"]),
      )
    : [];
  const semanticTokenColors: Theme["semanticTokenColors"] = {
    ...parent.semanticTokenColors,
  };
  if (record(child["semanticTokenColors"])) {
    for (const [name, value] of Object.entries(child["semanticTokenColors"])) {
      if (typeof value === "string") semanticTokenColors[name] = value;
      else if (record(value) && typeof value["foreground"] === "string")
        semanticTokenColors[name] = { foreground: value["foreground"] };
    }
  }
  return {
    colors: { ...parent.colors, ...stringMap(child["colors"]) },
    tokenColors: [...parent.tokenColors, ...tokenColors],
    semanticTokenColors,
  };
}
const theme = await loadTheme(resolve(process.argv[3]));
const editorForeground = theme.colors["editor.foreground"];
assert.ok(editorForeground, "Theme has no editor foreground");
const grammars = new Map<string, string>();
const languages = new Map<string, string>();
const injections = new Map<string, string[]>();
for (const directory of [join(app, "extensions"), ...process.argv.slice(4)]) {
  for (const name of await readdir(directory, { withFileTypes: true })) {
    if (!name.isDirectory() && !name.isSymbolicLink()) continue;
    const folder = join(directory, name.name);
    let manifest: unknown;
    try {
      manifest = JSON.parse(
        await readFile(join(folder, "package.json"), "utf8"),
      );
    } catch (error) {
      if (error instanceof Error && "code" in error && error.code === "ENOENT")
        continue;
      throw error;
    }
    for (const grammar of contributions(manifest)) {
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
      { settings: { foreground: editorForeground } },
      ...theme.tokenColors.filter((rule) => rule.scope),
    ],
  },
  onigLib: Promise.resolve({
    createOnigScanner: (patterns: string[]) =>
      new oniguruma.OnigScanner(patterns),
    createOnigString: (text: string) => new oniguruma.OnigString(text),
  }),
  loadGrammar: async (scope: string) => {
    const file = grammars.get(scope);
    return file
      ? textmate.parseRawGrammar(await readFile(file, "utf8"), file)
      : null;
  },
  getInjections: (scope: string) => injections.get(scope) ?? [],
});

// Each fixture names a language construct and its intended semantic role.
// This checks grammar output, precedence and fallbacks, not literal scope lists.
const fixtures: Fixture[] = [
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
const failures: Array<{
  language: string;
  text: string;
  color: string;
  style: number;
  expected: string | number | undefined;
}> = [];
for (const fixture of fixtures) {
  assert.ok(
    languages.has(fixture.language),
    `Missing ${fixture.language} grammar`,
  );
  const scope = languages.get(fixture.language);
  assert.ok(scope, `Missing ${fixture.language} scope`);
  const grammar = await registry.loadGrammar(scope);
  assert.ok(grammar, `Could not load ${fixture.language} grammar`);
  let state = textmate.INITIAL;
  for (const [lineNumber, line] of fixture.source.split("\n").entries()) {
    const result = grammar.tokenizeLine2(line, state);
    state = result.ruleStack;
    for (const probe of fixture.probes.filter(
      (candidate) => candidate.line === lineNumber,
    )) {
      const column = line.indexOf(probe.text);
      assert.ok(column >= 0, `Fixture text not found: ${probe.text}`);
      let metadata: number | undefined;
      for (let i = 0; i < result.tokens.length; i += 2) {
        const start = result.tokens[i];
        if (start !== undefined && start <= column)
          metadata = result.tokens[i + 1];
      }
      assert.ok(
        metadata !== undefined,
        `Missing token metadata for ${probe.text}`,
      );
      // VS Code's encoded token metadata uses bits 15..23 for the foreground
      // index and 11..14 for italic/bold/underline/strikethrough style flags.
      const color = registry.getColorMap()[(metadata >>> 15) & 511];
      assert.ok(color, `Missing color for ${probe.text}`);
      const style = (metadata >>> 11) & 15;
      const semantic = probe.role
        ? theme.semanticTokenColors[probe.role]
        : undefined;
      const expected = probe.workbenchRole
        ? theme.colors[probe.workbenchRole]?.slice(0, 7)
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
