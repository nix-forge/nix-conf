// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};

module.exports = function (
  family: string,
  done: (value: number | string) => void,
) {
  document.fonts
    .load("48px " + JSON.stringify(family), "😀")
    .then((fonts) => done(fonts.length))
    .catch((error) => done(String(error)));
};
