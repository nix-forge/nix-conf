// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(
  samples: Array<{ language: string; text: string; families: string[] }>,
) {
  return samples.map(({ language, text, families }) => {
    function render(font: string) {
      const canvas = document.createElement("canvas");
      canvas.width = 160;
      canvas.height = 120;
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      if (!ctx) throw new Error("Canvas 2D context unavailable");
      ctx.font = "48px " + font;
      ctx.fillText(text, 20, 80);
      const data = ctx.getImageData(0, 0, 160, 120).data;
      const ink = [];
      for (let i = 3; i < data.length; i += 4) ink.push(data[i] ?? 0);
      return { canvas, ink };
    }
    const generic = render("sans-serif");
    let best = null;
    for (const family of families) {
      const reference = render(JSON.stringify(family));
      const different = generic.ink.filter(
        (p, i) => Math.abs(p - (reference.ink[i] ?? 0)) > 20,
      ).length;
      if (!best || different < best.different)
        best = { family, reference, different };
      if (different === 0) break;
    }
    const label = document.createElement("p");
    label.textContent =
      language + ": " + (best?.family || "no installed coverage");
    document.body.append(label, generic.canvas);
    if (best) document.body.append(best.reference.canvas);
    return {
      language,
      matched_family: best?.family || null,
      different_pixels: best?.different ?? null,
      reference_ink: best?.reference.ink.filter((p) => p > 20).length || 0,
      candidate_families: families,
    };
  });
};
