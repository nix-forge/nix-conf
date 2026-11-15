// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(
  done: (value: boolean | string) => void,
) {
  const font = new FontFace("AppleTest", 'local("AppleColorEmoji")');
  font
    .load()
    .then((f) => {
      document.fonts.add(f);
      done(true);
    })
    .catch((e) => done(String(e)));
};
