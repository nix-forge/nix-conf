// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};

function canvasMeasure(family: string, value: string, weight: string = "400") {
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Canvas 2D context unavailable");
  context.font = `${weight} 40px ${family}`;
  const metrics = context.measureText(value);
  const padding = 8;
  const left = Math.max(0, metrics.actualBoundingBoxLeft);
  const right = Math.max(metrics.width, metrics.actualBoundingBoxRight);
  canvas.width = Math.ceil(left + right + padding * 2);
  canvas.height = Math.ceil(
    metrics.actualBoundingBoxAscent +
      metrics.actualBoundingBoxDescent +
      padding * 2,
  );
  context.font = `${weight} 40px ${family}`;
  context.textBaseline = "alphabetic";
  context.fillStyle = "#000";
  context.fillText(
    value,
    padding + left,
    padding + metrics.actualBoundingBoxAscent,
  );
  const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
  let ink = 0;
  for (let index = 3; index < pixels.length; index += 4)
    if ((pixels[index] ?? 0) > 8) ink += 1;
  return {
    ink,
    canvasWidth: canvas.width,
    canvasHeight: canvas.height,
    width: metrics.width,
    ascent: metrics.actualBoundingBoxAscent,
    descent: metrics.actualBoundingBoxDescent,
  };
}

module.exports = function browserProbe(
  text: string,
  monoFamily: string,
  done: (value: unknown) => void,
) {
  const faces: Array<[string, string]> = [
    ["regular", "400 40px FaceFixture"],
    ["bold", "700 40px FaceFixture"],
    ["italic", "italic 400 40px FaceFixture"],
    ["variable", "400 40px VariableFixture"],
    ["emoji", "400 48px emoji"],
  ];
  return Promise.all(
    faces.map(([, descriptor]) =>
      document.fonts
        .load(descriptor, descriptor.includes("emoji") ? "👩‍💻" : text)
        .catch(() => []),
    ),
  ).then((loaded) => {
    const emojiCases = {
      text: "☕︎",
      presentation: "☕️",
      keycap: "1️⃣",
      flag: "🇨🇦",
      skin: "👍🏽",
      zwj: "👩‍💻",
    };
    const emoji = Object.fromEntries(
      Object.entries(emojiCases).map(([name, value]) => {
        const canvas = document.createElement("canvas");
        canvas.width = 256;
        canvas.height = 80;
        const context = canvas.getContext("2d", { willReadFrequently: true });
        if (!context) throw new Error("Canvas 2D context unavailable");
        context.font = "48px emoji";
        context.fillText(value, 8, 60);
        const pixels = context.getImageData(0, 0, 256, 80).data;
        let ink = 0;
        for (let index = 3; index < pixels.length; index += 4)
          if ((pixels[index] ?? 0) > 8) ink += 1;
        const clusters = [
          ...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(
            value,
          ),
        ].length;
        return [
          name,
          { ink, clusters, width: context.measureText(value).width },
        ];
      }),
    );
    const ids = [
      "regular",
      "bold",
      "italic",
      "missing",
      "variable-low",
      "variable-high",
      "role-sans",
      "role-serif",
      "role-mono",
      "wrap",
      "generic-system",
      "generic-sans",
      "generic-ui-sans",
      "generic-ui-serif",
      "generic-ui-mono",
      "generic-ui-rounded",
    ];
    done({
      loaded: Object.fromEntries(
        faces.map(([name], index) => [name, (loaded[index]?.length ?? 0) > 0]),
      ),
      checked: Object.fromEntries(
        faces.map(([name, descriptor]) => [
          name,
          document.fonts.check(descriptor, text),
        ]),
      ),
      metrics: Object.fromEntries(
        ids.map((id) => {
          const node = document.getElementById(id);
          if (!node) throw new Error(`Missing fixture element: ${id}`);
          return [
            id,
            {
              width: node.getBoundingClientRect().width,
              height: node.getBoundingClientRect().height,
              lineHeight: parseFloat(getComputedStyle(node).lineHeight),
              fontStyle: getComputedStyle(node).fontStyle,
              fontWeight: getComputedStyle(node).fontWeight,
              variation: getComputedStyle(node).fontVariationSettings,
            },
          ];
        }),
      ),
      variableCanvas: {
        low: canvasMeasure("VariableFixture", text, "100"),
        high: canvasMeasure("VariableFixture", text, "900"),
      },
      monoCanvas: {
        lower: canvasMeasure(monoFamily, "iiiiii"),
        upper: canvasMeasure(monoFamily, "WWWWWW"),
      },
      emoji,
    });
  });
};
