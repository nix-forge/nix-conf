import { javascriptSource } from "../typescript/source.mts";
/** Native filesystem and CDP lifecycle observers for disposable GUI probes. */
import assert from "node:assert/strict";
import { watch } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export async function waitForFileValue<T>(
  directory: string,
  snapshot: () => Promise<T | null>,
  timeout = 20000,
): Promise<T> {
  const deadline = performance.now() + timeout;
  let generation = 0;
  let wake: (() => void) | undefined;
  let failure: unknown;
  const watcher = watch(directory, { recursive: true }, () => {
    generation++;
    wake?.();
  });
  watcher.on("error", (error: Error) => {
    failure = error;
    wake?.();
  });
  const signal = AbortSignal.timeout(timeout);
  const cancelled = (): void => wake?.();
  signal.addEventListener("abort", cancelled, { once: true });
  try {
    while (true) {
      signal.throwIfAborted();
      if (performance.now() >= deadline)
        throw new DOMException(
          "File readiness deadline expired",
          "TimeoutError",
        );
      if (failure) throw failure;
      const previous = generation;
      const value = await snapshot();
      signal.throwIfAborted();
      if (performance.now() >= deadline)
        throw new DOMException(
          "File readiness deadline expired",
          "TimeoutError",
        );
      if (failure) throw failure;
      if (value !== null) return value;
      if (previous !== generation) continue;
      await new Promise<void>((resolve) => {
        wake = resolve;
      });
      wake = undefined;
    }
  } finally {
    watcher.close();
    signal.removeEventListener("abort", cancelled);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export async function pageEndpoint(profile: string): Promise<string> {
  const deadline = performance.now() + 20000;
  const active = await waitForFileValue(profile, async () => {
    try {
      const lines = (
        await readFile(join(profile, "DevToolsActivePort"), "utf8")
      )
        .trim()
        .split("\n");
      const [port, path] = lines;
      return port &&
        /^\d+$/.test(port) &&
        path?.startsWith("/devtools/browser/")
        ? { port, path }
        : null;
    } catch (error) {
      if (isRecord(error) && error["code"] === "ENOENT") return null;
      throw error;
    }
  });
  const browser = new WebSocket(`ws://127.0.0.1:${active.port}${active.path}`);
  try {
    const id = await new Promise<string>((resolve, reject) => {
      const timeout = setTimeout(
        () => finish(new Error("CDP page target did not appear")),
        Math.max(0, deadline - performance.now()),
      );
      let settled = false;
      const finish = (error: Error | null, target?: string): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        browser.removeEventListener("open", opened);
        browser.removeEventListener("message", message);
        browser.removeEventListener("error", failed);
        browser.removeEventListener("close", failed);
        if (error) reject(error);
        else {
          assert.ok(target);
          resolve(target);
        }
      };
      const failed = (): void =>
        finish(
          new Error("CDP browser connection closed before target discovery"),
        );
      const candidate = (value: unknown): void => {
        if (performance.now() >= deadline) {
          finish(new Error("CDP discovery deadline expired"));
          return;
        }
        if (
          isRecord(value) &&
          value["type"] === "page" &&
          typeof value["targetId"] === "string"
        )
          finish(null, value["targetId"]);
      };
      const message = (event: MessageEvent): void => {
        try {
          assert.ok(typeof event.data === "string");
          const value: unknown = JSON.parse(event.data);
          if (!isRecord(value)) return;
          if (value["error"]) {
            finish(new Error(JSON.stringify(value["error"])));
            return;
          }
          if (isRecord(value["params"]))
            candidate(value["params"]["targetInfo"]);
          if (
            isRecord(value["result"]) &&
            Array.isArray(value["result"]["targetInfos"])
          ) {
            for (const target of value["result"]["targetInfos"])
              candidate(target);
          }
        } catch (error) {
          finish(error instanceof Error ? error : new Error(String(error)));
        }
      };
      browser.addEventListener("error", failed, { once: true });
      browser.addEventListener("close", failed, { once: true });
      browser.addEventListener("message", message);
      function opened(): void {
        browser.send(
          JSON.stringify({
            id: 1,
            method: "Target.setDiscoverTargets",
            params: { discover: true },
          }),
        );
        browser.send(JSON.stringify({ id: 2, method: "Target.getTargets" }));
      }
      browser.addEventListener("open", opened, { once: true });
    });
    return `ws://127.0.0.1:${active.port}/devtools/page/${id}`;
  } finally {
    browser.close();
  }
}

export const domObserver = javascriptSource(
  new URL("./wait-for-dom.ts", import.meta.url),
);
