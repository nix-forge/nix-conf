// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe() {
  return [...document.querySelectorAll(".digit")].map((e) => {
    const r = e.getBoundingClientRect();
    return { id: e.id, x: r.x, y: r.y, width: r.width, height: r.height };
  });
};
