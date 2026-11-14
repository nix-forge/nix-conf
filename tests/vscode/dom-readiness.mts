/** Reinstall the native DOM observer only after a page execution-context change. */
import { domObserver } from "./readiness.mts";

type Call = (
  method: string,
  params: Record<string, unknown>,
  timeout: number,
) => Promise<unknown>;

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export async function waitForDOM(
  socket: EventTarget,
  call: Call,
  selector: string,
  minimumCount = 1,
  parentClass: string | null = null,
  timeout = 14000,
): Promise<void> {
  const deadline = performance.now() + timeout;
  let current: { id: number; uniqueId: string } | undefined;
  let generation = 0;
  let wake: (() => void) | undefined;
  let frameId: string | undefined;
  let failure: Error | undefined;
  const changed = (): void => {
    generation++;
    wake?.();
  };
  const received = (event: Event): void => {
    try {
      if (!(event instanceof MessageEvent) || typeof event.data !== "string")
        return;
      const envelope: unknown = JSON.parse(event.data);
      if (!record(envelope)) return;
      const params = record(envelope["params"]) ? envelope["params"] : {};
      if (envelope["method"] === "Runtime.executionContextCreated") {
        const context = params["context"];
        if (
          record(context) &&
          record(context["auxData"]) &&
          context["auxData"]["isDefault"] === true &&
          context["auxData"]["frameId"] === frameId &&
          typeof context["id"] === "number" &&
          typeof context["uniqueId"] === "string"
        ) {
          current = { id: context["id"], uniqueId: context["uniqueId"] };
          changed();
        }
      } else if (
        envelope["method"] === "Runtime.executionContextsCleared" ||
        (envelope["method"] === "Runtime.executionContextDestroyed" &&
          params["executionContextId"] === current?.id)
      ) {
        current = undefined;
        changed();
      }
    } catch (error) {
      failure = error instanceof Error ? error : new Error(String(error));
      changed();
    }
  };
  const closed = (): void => {
    failure = new Error("Page connection closed during DOM readiness");
    changed();
  };
  const remaining = (): number => {
    if (failure) throw failure;
    const budget = deadline - performance.now();
    if (budget <= 0) throw new Error("DOM readiness deadline expired");
    return budget;
  };
  const timer = setTimeout(() => {
    failure = new Error("DOM readiness deadline expired");
    changed();
  }, timeout);
  socket.addEventListener("message", received);
  socket.addEventListener("close", closed);
  socket.addEventListener("error", closed);
  try {
    const frames = await call("Page.getFrameTree", {}, remaining());
    if (
      !record(frames) ||
      !record(frames["frameTree"]) ||
      !record(frames["frameTree"]["frame"]) ||
      typeof frames["frameTree"]["frame"]["id"] !== "string"
    )
      throw new Error("No main frame for DOM readiness");
    frameId = frames["frameTree"]["frame"]["id"];
    // This disposable connection may have enabled Runtime in an earlier wait.
    // Disable first so enable reports the existing contexts to these listeners.
    await call("Runtime.disable", {}, remaining());
    await call("Runtime.enable", {}, remaining());
    while (true) {
      remaining();
      if (!current) {
        await new Promise<void>((resolve) => {
          wake = resolve;
        });
        wake = undefined;
        continue;
      }
      const previous = generation;
      const context = current;
      try {
        const result = await call(
          "Runtime.callFunctionOn",
          {
            uniqueContextId: context.uniqueId,
            functionDeclaration: domObserver,
            arguments: [selector, minimumCount, parentClass, remaining()].map(
              (value) => ({ value }),
            ),
            awaitPromise: true,
            returnByValue: true,
          },
          remaining(),
        );
        remaining();
        if (previous !== generation) continue;
        if (!record(result)) throw new Error("Invalid DOM observer response");
        if (result["exceptionDetails"])
          throw new Error(JSON.stringify(result["exceptionDetails"]));
        if (!record(result["result"]) || result["result"]["value"] !== true)
          throw new Error("DOM observer did not establish readiness");
        return;
      } catch (error) {
        remaining();
        // A new context notification authorizes a new observer. Other errors fail.
        if (previous === generation) throw error;
      }
    }
  } finally {
    clearTimeout(timer);
    socket.removeEventListener("message", received);
    socket.removeEventListener("close", closed);
    socket.removeEventListener("error", closed);
  }
}
