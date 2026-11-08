// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(
  sample: string,
  privateUse: string,
  done: () => void,
) {
  return Promise.all([
    document.fonts.load('400 48px "SF Pro Local"', privateUse),
    document.fonts.load('400 32px "SF Pro"', sample),
    document.fonts.load('400 48px "SF Pro"', privateUse),
  ]).then(() => done());
};
