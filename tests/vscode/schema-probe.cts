declare const exports: { activate?: () => unknown };
import type { NativeRequire } from "../typescript/native-require.mts";
declare const require: NativeRequire;
const vscode: typeof import("vscode") = require("vscode");
const fs: typeof import("node:fs/promises") = require("node:fs/promises");
const path: typeof import("node:path") = require("node:path");
const configuration: unknown = JSON.parse(
  require("node:fs").readFileSync(path.join(__dirname, "output.json"), "utf8"),
);
if (
  configuration === null ||
  typeof configuration !== "object" ||
  !("output" in configuration) ||
  typeof configuration.output !== "string"
)
  throw new Error("Schema probe requires an output directory");
const output = configuration.output;
exports.activate = async () => {
  await fs.mkdir(output, { recursive: true });
  for (const name of [
    "color-theme",
    "workbench-colors",
    "textmate-colors",
    "token-styling",
    "vscode-extensions",
  ]) {
    const data = await vscode.workspace.fs.readFile(
      vscode.Uri.parse("vscode://schemas/" + name),
    );
    await fs.writeFile(path.join(output, name + ".json"), data);
  }
  await fs.writeFile(
    path.join(output, "version.json"),
    JSON.stringify({ version: vscode.version }),
  );
};
