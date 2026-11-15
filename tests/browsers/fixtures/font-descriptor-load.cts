// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(
  text: string,
  descriptor: string,
  done: (value: { loaded: boolean; checked: boolean; error?: string }) => void,
) {
  document.fonts
    .load(descriptor, text)
    .then((faces) =>
      done({
        loaded: faces.length > 0,
        checked: document.fonts.check(descriptor, text),
      }),
    )
    .catch((error) =>
      done({ loaded: false, checked: false, error: String(error) }),
    );
};
