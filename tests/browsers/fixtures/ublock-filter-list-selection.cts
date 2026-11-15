// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(
  lists: string[],
  done: (value: unknown) => void,
) {
  vAPI.messaging
    .send("dashboard", {
      what: "applyFilterListSelection",
      toImport: lists.join("\n"),
    })
    .then(() => vAPI.messaging.send("dashboard", { what: "reloadAllFilters" }))
    .then(() => browser.storage.local.get("selectedFilterLists"))
    .then(done, (error) => done({ error: String(error) }));
};
