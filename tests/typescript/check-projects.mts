// Discover compiler projects and reject maintained source outside their coverage.
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function strings(value: unknown): value is string[] {
  return (
    Array.isArray(value) &&
    value.every((item: unknown) => typeof item === "string")
  );
}
const root = process.cwd();
const manifest: unknown = JSON.parse(
  readFileSync(new URL("./projects.json", import.meta.url), "utf8"),
);
if (
  !record(manifest) ||
  !strings(manifest["scopes"]) ||
  !record(manifest["fixtures"]) ||
  !record(manifest["application"])
)
  throw new Error("Invalid TypeScript coverage manifest");
const ignored = new Set(["node_modules", "dist", "build", ".git", ".scratch"]);
function walk(directory: string): string[] {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = join(directory, entry.name);
    if (entry.isDirectory()) return ignored.has(entry.name) ? [] : walk(file);
    return entry.isFile() ? [file] : [];
  });
}
const files = manifest["scopes"].flatMap((scope) => walk(resolve(root, scope)));
const projects = [
  resolve(root, "tsconfig.json"),
  ...files.filter((file) => file.endsWith("/tsconfig.json")),
];
const compiler = join(
  dirname(createRequire(import.meta.url).resolve("typescript/package.json")),
  "bin/tsc",
);
const required = [
  "strict",
  "noUncheckedIndexedAccess",
  "exactOptionalPropertyTypes",
  "noImplicitReturns",
  "noUnusedLocals",
  "noUnusedParameters",
  "noImplicitOverride",
  "noFallthroughCasesInSwitch",
  "noUncheckedSideEffectImports",
  "forceConsistentCasingInFileNames",
  "noPropertyAccessFromIndexSignature",
];
const strictDefaults = [
  "noImplicitAny",
  "strictNullChecks",
  "strictFunctionTypes",
  "strictBindCallApply",
  "strictPropertyInitialization",
  "strictBuiltinIteratorReturn",
  "noImplicitThis",
  "useUnknownInCatchVariables",
  "alwaysStrict",
];
const covered = new Set<string>();
for (const project of new Set(projects)) {
  const config: unknown = JSON.parse(
    execFileSync(
      process.execPath,
      [compiler, "--project", project, "--showConfig"],
      { encoding: "utf8" },
    ),
  );
  if (
    !record(config) ||
    !record(config["compilerOptions"]) ||
    !strings(config["files"])
  )
    throw new Error(`Invalid compiler configuration: ${project}`);
  const options = config["compilerOptions"];
  for (const flag of strictDefaults)
    if (options[flag] === false)
      throw new Error(`${project} cannot override strict option ${flag}`);
  for (const flag of required)
    if (options[flag] !== true)
      throw new Error(`${relative(root, project)} must enable ${flag}`);
  for (const flag of [
    "skipLibCheck",
    "allowUnreachableCode",
    "allowUnusedLabels",
  ])
    if (options[flag] !== false)
      throw new Error(`${relative(root, project)} must disable ${flag}`);
  if (options["allowJs"] === true && options["checkJs"] !== true)
    throw new Error(`${project} must check JavaScript`);
  for (const file of config["files"])
    covered.add(resolve(dirname(project), file));
  execFileSync(process.execPath, [compiler, "--project", project, "--noEmit"], {
    stdio: "inherit",
  });
  console.log(`Checked ${relative(root, project)}`);
}
for (const [configPath, mapping] of Object.entries(manifest["application"])) {
  // These sources compile inside their owning fetched application with its locked dependencies.
  const config: unknown = JSON.parse(
    readFileSync(resolve(root, configPath), "utf8"),
  );
  if (!record(config) || !strings(config["files"]) || !record(mapping))
    throw new Error(`Invalid application mapping: ${configPath}`);
  const options = config["compilerOptions"];
  if (!record(options))
    throw new Error(`Missing application compiler options: ${configPath}`);
  for (const flag of required)
    if (options[flag] !== true)
      throw new Error(`${configPath} must enable ${flag}`);
  for (const flag of [
    "skipLibCheck",
    "allowUnreachableCode",
    "allowUnusedLabels",
  ])
    if (options[flag] !== false)
      throw new Error(`${configPath} must disable ${flag}`);
  for (const flag of strictDefaults)
    if (options[flag] === false)
      throw new Error(`${configPath} cannot override strict option ${flag}`);
  for (const [source, destination] of Object.entries(mapping)) {
    if (
      typeof destination !== "string" ||
      !config["files"].includes(destination)
    )
      throw new Error(`Uncovered application source: ${source}`);
    covered.add(resolve(root, source));
  }
  console.log(`Application build checks ${configPath}`);
}
for (const [fixture, reason] of Object.entries(manifest["fixtures"])) {
  if (typeof reason !== "string" || !reason.trim())
    throw new Error(`Missing fixture rationale: ${fixture}`);
  const file = resolve(root, fixture);
  if (!files.includes(file))
    throw new Error(`Missing loader fixture: ${fixture}`);
  execFileSync(process.execPath, ["--check", file], { stdio: "inherit" });
  covered.add(file);
}
const missing = files.filter(
  (file) => /\.(?:[cm]?[jt]sx?)$/.test(file) && !covered.has(file),
);
if (missing.length)
  throw new Error(
    `Sources missing a compiler project:\n${missing.map((file) => relative(root, file)).join("\n")}`,
  );
// Ensure this module's own location is representable by the compiler coverage check.
if (!covered.has(fileURLToPath(import.meta.url)))
  throw new Error("Coverage checker is itself unchecked");
