// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe() {
  const ids = [
    "stack",
    "named-stack",
    "web",
    "fallback",
    "system-ui",
    "sans-serif",
    "private-stack",
    "private-system",
    "private-reference",
  ];
  return {
    widths: Object.fromEntries(
      ids.map((id) => [
        id,
        document.getElementById(id)?.getBoundingClientRect().width,
      ]),
    ),
    fontFaces: [...document.fonts].map((face) => ({
      family: face.family,
      status: face.status,
    })),
    webFontLoaded: [...document.fonts].some(
      (face) =>
        ["SF Pro", '"SF Pro"'].includes(face.family) &&
        face.status === "loaded",
    ),
  };
};
