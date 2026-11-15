// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(
  samples: Array<{ text: string; width: number; encoding: string }>,
  family: string,
) {
  const ctx = document.createElement("canvas").getContext("2d");
  if (!ctx) throw new Error("Canvas 2D context unavailable");
  ctx.font = "48px " + JSON.stringify(family);
  const failures = samples.flatMap((s) => {
    const actual = ctx.measureText(s.text).width;
    return Math.abs(actual - s.width) > 0.1 ? [{ ...s, actual }] : [];
  });
  const custom = document.querySelector("#custom");
  if (!custom) throw new Error("Custom emoji fixture missing");
  custom.textContent = [
    "1f44d-fe0f-101650-101613",
    "1f3f3-fe0f-200d-26a7",
    "1f3f3-200d-1f308",
    "101698",
    "101691",
  ]
    .map((name) => {
      const sample = samples.find((s) => s.encoding === name);
      if (!sample) throw new Error(`Missing emoji sample: ${name}`);
      return sample.text;
    })
    .join(" ");
  return { total: samples.length, failures };
};
