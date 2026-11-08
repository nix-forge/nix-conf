/** Node's known built-ins and the disposable probe host APIs. */
type Modules = {
  "node:assert/strict": typeof import("node:assert/strict");
  "node:fs": typeof import("node:fs");
  "node:fs/promises": typeof import("node:fs/promises");
  "node:path": typeof import("node:path");
  "node:child_process": typeof import("node:child_process");
  "node:vm": typeof import("node:vm");
  electron: typeof import("electron");
  vscode: typeof import("vscode");
};
export interface NativeRequire {
  <Name extends keyof Modules>(name: Name): Modules[Name];
  (name: string): unknown;
}
