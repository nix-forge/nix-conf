// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(id: string) {
  const node = document.getElementById(id);
  if (!node) throw new Error("Required font fixture element missing");
  const range = document.createRange();
  range.selectNodeContents(node);
  const box = node.getBoundingClientRect();
  const style = getComputedStyle(node);
  return {
    width: box.width,
    height: box.height,
    textWidth: range.getBoundingClientRect().width,
    lineHeight: parseFloat(style.lineHeight),
    fontFamily: style.fontFamily,
    fontStyle: style.fontStyle,
    fontWeight: style.fontWeight,
    variation: style.fontVariationSettings,
  };
};
