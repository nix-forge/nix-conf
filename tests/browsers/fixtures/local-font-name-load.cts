// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(
  text: string,
  done: (value: unknown) => void,
) {
  return Promise.all(
    [
      document.fonts.load("400 40px LocalFull", text),
      document.fonts.load("400 40px LocalPostScript", text),
    ].map((promise) => promise.catch(() => [])),
  ).then((faces) =>
    done({
      full: (faces[0]?.length ?? 0) > 0,
      postscript: (faces[1]?.length ?? 0) > 0,
      fullChecked: document.fonts.check("400 40px LocalFull", text),
      postscriptChecked: document.fonts.check("400 40px LocalPostScript", text),
    }),
  );
};
