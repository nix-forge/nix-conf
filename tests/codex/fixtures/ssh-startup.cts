import type { NativeRequire } from "../../typescript/native-require.mts";
declare const require: NativeRequire;
const { app }: typeof import("electron") = require("electron");
const fs: typeof import("node:fs") = require("node:fs");
const path: typeof import("node:path") = require("node:path");
const cp: typeof import("node:child_process") = require("node:child_process");
const vm: typeof import("node:vm") = require("node:vm");
const bundle = process.env["CODEX_TEST_BUNDLE"];
const sshHost = process.env["CODEX_TEST_SSH_HOST"];
if (!bundle) throw new Error("CODEX_TEST_BUNDLE is required");
function checkSsh() {
  if (!bundle || !sshHost)
    throw new Error("SSH probe requires bundle and host");
  const main = fs
    .readdirSync(bundle)
    .filter((name) => /^main-.*\.js$/.test(name));
  if (main.length !== 1 || !main[0])
    throw new Error("Expected one main bundle");
  const source = fs.readFileSync(path.join(bundle, main[0]), "utf8");
  // Match the reviewed SSH option shape rather than unstable minifier names.
  const builders = [
    ...source.matchAll(
      /function ([$A-Z_a-z][$\w]*)\(([$A-Z_a-z][$\w]*)\)\{[^{}]*?(?<![$\w])([$A-Z_a-z][$\w]*)\.batchMode[\s\S]*?\}(?=function )/g,
    ),
  ];
  if (builders.length !== 1 || !builders[0] || builders[0][0].length > 4096)
    throw new Error("Review SSH argument builder extraction");
  const builder = builders[0];
  const configurationName = builder[3];
  if (!configurationName || !builder[1])
    throw new Error("Invalid SSH builder capture");
  const configurationPattern = new RegExp(
    "(?<![$\\w])" +
      RegExp.escape(configurationName) +
      "=(\\{batchMode:[^}]+\\})",
    "g",
  );
  const configurations = [...source.matchAll(configurationPattern)];
  if (configurations.length !== 1 || !configurations[0]?.[1])
    throw new Error("Review SSH argument builder configuration");
  const argumentBuilder = new vm.Script(
    "const " +
      configurationName +
      "=" +
      configurations[0][1] +
      ";" +
      builder[0] +
      ";" +
      builder[1] +
      "(5)",
    { filename: "captured-ssh-argument-builder.js" },
  );
  const args: unknown = argumentBuilder.runInNewContext(
    {},
    {
      timeout: 1000,
    },
  );
  if (
    !Array.isArray(args) ||
    !args.every((argument) => typeof argument === "string") ||
    !args.includes("BatchMode=yes") ||
    !args.includes("ConnectTimeout=5")
  )
    throw new Error("Review SSH argument builder result");
  const socket = path.join(app.getPath("userData"), "probe.sock");
  args.push(
    "-o",
    "ControlMaster=auto",
    "-o",
    "ControlPersist=2",
    "-o",
    "ControlPath=" + socket,
    sshHost,
    "printf SSH_COMPLETION_OK",
  );
  const started = Date.now();
  const ssh = cp.spawn("ssh", args, { stdio: ["ignore", "pipe", "pipe"] });
  let output = "";
  let masterAtExit = false;
  ssh.stdout.on("data", (data) => {
    output += data;
  });
  ssh.stderr.resume();
  ssh.on("exit", () => {
    masterAtExit = fs.existsSync(socket);
  });
  ssh.on("error", (error) => {
    console.error(error instanceof Error ? error.message : String(error));
    app.exit(1);
  });
  ssh.on("close", (code) => {
    const duration = Date.now() - started;
    const passed =
      code === 0 && output === "SSH_COMPLETION_OK" && !masterAtExit;
    console.log(
      "SSH_COMPLETION_RESULT " +
        JSON.stringify({
          exitCode: code,
          expectedOutput: output === "SSH_COMPLETION_OK",
          masterAtExit,
          durationMs: duration,
        }),
    );
    console.log(
      passed
        ? "PASS: fresh SSH command completion"
        : "FAIL: SSH completion contract (" + duration + "ms)",
    );
    app.exit(passed ? 0 : 1);
  });
}
const loader = fs
  .readdirSync(bundle)
  .filter((name) => /^(?:shell-env|startup-requirements)-.*\.js$/.test(name));
if (loader.length !== 1 || !loader[0])
  throw new Error("Expected one shell loader");
setTimeout(() => {
  console.error("FAIL: child completion timed out");
  app.exit(1);
}, 8000);
const shellLoader: unknown = require(path.join(bundle, loader[0]));
// The reviewed 26.1007 startup module exports the loader as o; older bundles
// export t from shell-env. Keep the runtime result and child assertions shared.
const entrypoint: unknown =
  shellLoader !== null && typeof shellLoader === "object"
    ? Reflect.get(
        shellLoader,
        loader[0].startsWith("startup-requirements-") ? "o" : "t",
      )
    : undefined;
const isShellEntrypoint = (value: unknown): value is () => unknown =>
  typeof value === "function";
if (!isShellEntrypoint(entrypoint))
  throw new Error("Invalid shell loader entrypoint");
const startShell = (): unknown => entrypoint();
Promise.resolve(startShell())
  .then((result) => {
    if (
      result === null ||
      typeof result !== "object" ||
      !("status" in result) ||
      result.status !== "loaded"
    )
      throw new Error("Shell hydration did not load");
    const child = cp.spawn("/bin/sh", ["-c", "printf CHILD_EXIT_OK"]);
    let output = "";
    child.stdout.on("data", (data) => {
      output += data;
    });
    child.on("error", (error) => {
      console.error(error.message);
      app.exit(1);
    });
    child.on("close", (code) => {
      const passed = code === 0 && output === "CHILD_EXIT_OK";
      console.log(
        passed
          ? "PASS: shell hydration and child completion"
          : "FAIL: child result",
      );
      if (passed && sshHost) checkSsh();
      else app.exit(passed ? 0 : 1);
    });
  })
  .catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    app.exit(1);
  });
