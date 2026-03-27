import type { Plugin, PluginInput } from "@opencode-ai/plugin";

const PLAN_EXIT_DEDUP_MS = 3000;
const recentPlanExitBySession = new Map<string, number>();

function quoteAppleScript(input: string): string {
  return `"${input.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

async function notify(
  shell: PluginInput["$"],
  title: string,
  body: string,
): Promise<void> {
  if (process.platform !== "darwin") {
    return;
  }

  const script = `display notification ${quoteAppleScript(body)} with title ${quoteAppleScript(title)}`;

  try {
    await shell`/usr/bin/osascript -e ${script}`.quiet();
  } catch {}
}

export const PlanModeNotifyPlugin: Plugin = async ({ $ }) => {
  return {
    "tool.execute.before": async (input) => {
      if (input.tool === "plan_exit") {
        recentPlanExitBySession.set(input.sessionID, Date.now());
        await notify(
          $,
          "OpenCode",
          "Plan ready to implement. Review and approve to switch to build mode.",
        );
        return;
      }

      if (input.tool !== "question") {
        return;
      }

      const lastPlanExit = recentPlanExitBySession.get(input.sessionID);
      if (typeof lastPlanExit === "number") {
        if (Date.now() - lastPlanExit <= PLAN_EXIT_DEDUP_MS) {
          return;
        }
        recentPlanExitBySession.delete(input.sessionID);
      }

      await notify($, "OpenCode", "Question waiting for your input.");
    },
  };
};

export default PlanModeNotifyPlugin;
