// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(cases: Record<string, string>) {
  const metrics = Object.fromEntries(
    Object.keys(cases).map((id) => {
      const node = document.getElementById(id);
      if (!node) throw new Error("Required font fixture element missing");
      const range = document.createRange();
      range.selectNodeContents(node);
      return [
        id,
        {
          width: node.getBoundingClientRect().width,
          textWidth: range.getBoundingClientRect().width,
        },
      ];
    }),
  );
  return {
    metrics,
    configuredSansAvailable: document.fonts.check(
      `400 32px ${cases["configured-sans"]}`,
    ),
  };
};
