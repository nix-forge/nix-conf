// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(done: (value: unknown) => void) {
  return Promise.all(
    (
      [
        ["Google Sans Flex", "400", "0123456789"],
        ["Google Symbols", "200", "animation"],
      ] as Array<[string, string, string]>
    ).map(async ([family, weight, text]) => {
      try {
        const faces = await document.fonts.load(
          `${weight} 64px "${family}"`,
          text,
        );
        const canvas = document.createElement("canvas");
        const ctx = canvas.getContext("2d");
        if (!ctx) throw new Error("Canvas 2D context unavailable");
        ctx.font = `${weight} 64px "${family}"`;
        const width = ctx.measureText(text).width;
        return {
          family,
          loaded: faces.length > 0,
          width,
          ligature: family !== "Google Symbols" || width <= 65,
        };
      } catch (error) {
        return { family, loaded: false, error: String(error) };
      }
    }),
  ).then(done);
};
