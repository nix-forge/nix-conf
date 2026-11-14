import assert from "node:assert/strict";
import test from "node:test";
import { waitForDOM } from "./dom-readiness.mts";

function context(socket: EventTarget, uniqueId: string): void {
  socket.dispatchEvent(
    new MessageEvent("message", {
      data: JSON.stringify({
        method: "Runtime.executionContextCreated",
        params: {
          context: {
            id: uniqueId === "first" ? 1 : 2,
            uniqueId,
            auxData: { isDefault: true, frameId: "main" },
          },
        },
      }),
    }),
  );
}
const frames = { frameTree: { frame: { id: "main" } } };
const ready = { result: { type: "boolean", value: true } };

await test("navigation reinstalls only after a new context notification", async () => {
  const socket = new EventTarget();
  const observed: unknown[] = [];
  await waitForDOM(
    socket,
    (method, params) => {
      if (method === "Page.getFrameTree") return Promise.resolve(frames);
      if (method === "Runtime.enable") context(socket, "first");
      if (method === "Runtime.callFunctionOn") {
        observed.push(params["uniqueContextId"]);
        if (params["uniqueContextId"] === "first") {
          socket.dispatchEvent(
            new MessageEvent("message", {
              data: JSON.stringify({
                method: "Runtime.executionContextsCleared",
              }),
            }),
          );
          context(socket, "second");
          return Promise.reject(new Error("Execution context was destroyed"));
        }
        return Promise.resolve(ready);
      }
      return Promise.resolve({});
    },
    ".ready",
  );
  assert.deepEqual(observed, ["first", "second"]);
});

await test("a quiet page blocks without requesting repeated context snapshots", async () => {
  const socket = new EventTarget();
  const requested: string[] = [];
  await assert.rejects(
    waitForDOM(
      socket,
      (method) => {
        requested.push(method);
        return Promise.resolve(method === "Page.getFrameTree" ? frames : {});
      },
      ".ready",
      1,
      null,
      30,
    ),
    /deadline expired/,
  );
  assert.deepEqual(requested, [
    "Page.getFrameTree",
    "Runtime.disable",
    "Runtime.enable",
  ]);
});

await test("unrelated protocol failures are preserved without retries", async () => {
  const socket = new EventTarget();
  const failure = new Error("invalid selector request");
  let attempts = 0;
  await assert.rejects(
    waitForDOM(
      socket,
      (method) => {
        if (method === "Page.getFrameTree") return Promise.resolve(frames);
        if (method === "Runtime.enable") context(socket, "first");
        if (method === "Runtime.callFunctionOn") {
          attempts++;
          return Promise.reject(failure);
        }
        return Promise.resolve({});
      },
      ".ready",
    ),
    (error) => error === failure,
  );
  assert.equal(attempts, 1);
});
