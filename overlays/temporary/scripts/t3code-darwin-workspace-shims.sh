# shellcheck shell=bash
# pnpm's hook patches root node_modules. Cover generated workspace bins after
# the unchanged upstream preparation, which can regenerate executable shims.
while IFS= read -r -d "" directory; do
  patchShebangs "$directory"
done < <(find apps packages -type d -path '*/node_modules/.bin' -print0)
