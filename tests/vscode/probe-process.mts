/** Keep a native supervisor alive until the caller closes its ownership pipe. */
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

export function startProbe(root: string, args: string[]): () => Promise<void> {
  const child = spawn(
    "python3",
    [
      fileURLToPath(new URL("./probe_process.py", import.meta.url)),
      root,
      ...args,
    ],
    {
      stdio: ["pipe", "inherit", "inherit"],
    },
  );
  const exited = new Promise<void>((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (code !== 0)
        reject(new Error(`Probe supervisor exited ${code ?? signal}`));
      else resolve();
    });
  });
  // The supervisor can close the lease before the caller completes startup.
  child.stdin.on("error", () => {});
  // Startup may fail while the caller is still observing its endpoint.
  void exited.catch(() => {});
  return async () => {
    child.stdin.end();
    await exited;
  };
}
