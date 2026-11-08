import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";
import test, { type TestContext } from "node:test";

function fixture(t: TestContext): string {
  const root = mkdtempSync(join(tmpdir(), "typescript-quality-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, "tests/typescript"), { recursive: true });
  mkdirSync(join(root, "modules"));
  writeFileSync(
    join(root, "tests/typescript/check-projects.mts"),
    readFileSync(new URL("./check-projects.mts", import.meta.url)),
  );
  writeFileSync(
    join(root, "tests/typescript/projects.json"),
    JSON.stringify({
      scopes: ["tests", "modules"],
      application: {},
      fixtures: {},
    }),
  );
  writeFileSync(
    join(root, "tsconfig.json"),
    readFileSync(new URL("../../tsconfig.json", import.meta.url)),
  );
  const modules = dirname(
    dirname(createRequire(import.meta.url).resolve("typescript/package.json")),
  );
  symlinkSync(modules, join(root, "node_modules"), "dir");
  return root;
}
function check(root: string) {
  return spawnSync(
    process.execPath,
    [join(root, "tests/typescript/check-projects.mts")],
    { cwd: root, encoding: "utf8" },
  );
}
void test("compiler gate checks valid covered sources", (t) => {
  const root = fixture(t);
  writeFileSync(
    join(root, "tests/valid.mts"),
    'export const label: string = "checked";',
  );
  const result = check(root);
  assert.equal(result.status, 0, result.stderr + result.stdout);
});
void test("compiler gate fails for a real type mismatch", (t) => {
  const root = fixture(t);
  writeFileSync(
    join(root, "tests/invalid.mts"),
    "export const label: string = 42;",
  );
  const result = check(root);
  assert.notEqual(result.status, 0);
  assert.match(
    result.stdout + result.stderr,
    /not assignable to type 'string'/,
  );
});
void test("coverage gate catches a maintained file outside compiler inputs", (t) => {
  const root = fixture(t);
  writeFileSync(
    join(root, "modules/uncovered.ts"),
    "export const uncovered = true;",
  );
  const result = check(root);
  assert.notEqual(result.status, 0);
  assert.match(
    result.stderr,
    /Sources missing a compiler project:.*\nmodules\/uncovered.ts/,
  );
});
void test("policy gate rejects weakening dependency declaration checks", (t) => {
  const root = fixture(t);
  const config = readFileSync(join(root, "tsconfig.json"), "utf8").replace(
    '"skipLibCheck": false',
    '"skipLibCheck": true',
  );
  writeFileSync(join(root, "tsconfig.json"), config);
  const result = check(root);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /must disable skipLibCheck/);
});

void test("policy gate rejects disabling a strict sub-option", (t) => {
  const root = fixture(t);
  const config = readFileSync(join(root, "tsconfig.json"), "utf8").replace(
    '"strict": true',
    '"strict": true, "noImplicitAny": false',
  );
  writeFileSync(join(root, "tsconfig.json"), config);
  const result = check(root);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /cannot override strict option noImplicitAny/);
});
