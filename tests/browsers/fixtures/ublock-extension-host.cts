// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function () {
  const extensions: unknown = JSON.parse(
    Services.prefs.getStringPref("extensions.webextensions.uuids"),
  );
  const id = "uBlock0@raymondhill.net";
  if (
    extensions === null ||
    typeof extensions !== "object" ||
    !(id in extensions) ||
    typeof extensions[id] !== "string"
  )
    throw new Error("uBlock extension host unavailable");
  return extensions[id];
};
