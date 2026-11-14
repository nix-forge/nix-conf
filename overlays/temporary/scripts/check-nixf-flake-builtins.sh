# shellcheck shell=bash
# The native package installation supplies its own output path.
# shellcheck disable=SC2154
for builtin in getFlake parseFlakeRef flakeRefToString; do
  printf 'builtins.%s\n' "$builtin" >flake-builtin.nix
  "$out/bin/nixf-diagnose" flake-builtin.nix
done
printf '%s\n' 'builtins.getFlakke' >unknown-builtin.nix
if "$out/bin/nixf-diagnose" unknown-builtin.nix >unknown-builtin.log 2>&1; then
  echo "nixf accepted an unknown builtin" >&2
  exit 1
fi
# The diagnostic quotes the builtin name with literal backticks.
# shellcheck disable=SC2016
@grep@ -F 'unknown builtin `getFlakke`' unknown-builtin.log
