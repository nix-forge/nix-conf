declare const exports: { activate?: () => unknown };
import type { NativeRequire } from "../typescript/native-require.mts";
declare const require: NativeRequire;
const vscode: typeof import("vscode") = require("vscode");
exports.activate = () =>
  vscode.languages.registerCodeLensProvider(
    { scheme: "file" },
    {
      provideCodeLenses: () => [
        new vscode.CodeLens(new vscode.Range(0, 0, 0, 0), {
          title: "GitHub Issue Template - YAML 0123456789",
          command: "",
        }),
      ],
    },
  );
