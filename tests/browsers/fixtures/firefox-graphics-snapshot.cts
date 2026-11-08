// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(done: (value: unknown) => void) {
  return ChromeUtils.importESModule(
    "resource://gre/modules/Troubleshoot.sys.mjs",
  )
    .Troubleshoot.snapshot()
    .then((s) => done(s.graphics));
};
