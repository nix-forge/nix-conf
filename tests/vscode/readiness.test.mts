import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { waitForFileValue } from "./readiness.mts";

await test("retains a write during the initial snapshot", async () => {
  const directory = await mkdtemp(join(tmpdir(), "cdp-ready-"));
  const marker = join(directory, "ready");
  let initial = true;
  try {
    const value = await waitForFileValue(directory, async () => {
      if (initial) {
        initial = false;
        await writeFile(marker, "ready");
        return null;
      }
      return readFile(marker, "utf8");
    });
    assert.equal(value, "ready");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

await test("quiet directories take one snapshot and block to the deadline", async () => {
  // A newly created directory can itself generate a delayed FSEvents event.
  // Observe this existing, unchanged source directory for the idle assertion.
  const directory = fileURLToPath(new URL(".", import.meta.url));
  let snapshots = 0;
  await assert.rejects(
    waitForFileValue(
      directory,
      () => {
        snapshots++;
        return Promise.resolve(null);
      },
      30,
    ),
    { name: "TimeoutError" },
  );
  assert.equal(snapshots, 1);
});

await test("snapshot failures are retained and release the watcher", async () => {
  const directory = await mkdtemp(join(tmpdir(), "cdp-error-"));
  const failure = new Error("read failed");
  try {
    await assert.rejects(
      waitForFileValue(directory, () => Promise.reject(failure)),
      (error) => error === failure,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
