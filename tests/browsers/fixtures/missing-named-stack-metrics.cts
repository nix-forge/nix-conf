// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe() {
  const ids = [
    "reference",
    "fallback",
    "configured-sans",
    "youtube",
    "synthetic",
  ];
  return Object.fromEntries(
    ids.map((id) => {
      const node = document.getElementById(id);
      if (!node) throw new Error("Required font fixture element missing");
      const range = document.createRange();
      range.selectNodeContents(node);
      return [
        id,
        {
          width: range.getBoundingClientRect().width,
          family: getComputedStyle(node).fontFamily,
        },
      ];
    }),
  );
};
