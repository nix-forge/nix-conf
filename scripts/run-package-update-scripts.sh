#!/usr/bin/env bash
set -euo pipefail

FLAKE_ROOT="${FLAKE_ROOT:-.}"
HOST_SYSTEM="$(nix eval --impure --raw --expr 'builtins.currentSystem' 2>/dev/null || true)"
SYSTEM="${SYSTEM:-${HOST_SYSTEM:-x86_64-linux}}"

if [[ -n ${HOST_SYSTEM} && ${HOST_SYSTEM} != "${SYSTEM}" ]]; then
  echo "Host system ${HOST_SYSTEM} does not match requested system ${SYSTEM}." >&2
  echo "Set SYSTEM to the desired target if you are running on a different host." >&2
fi

packages=$(nix eval --raw "${FLAKE_ROOT}#legacyPackages.${SYSTEM}" --apply '
  pkgs:
  let
    names = builtins.attrNames pkgs;
    hasUpdateScript = name:
      let
        pkg = builtins.getAttr name pkgs;
      in
      pkg ? passthru && pkg.passthru ? updateScript;
    filtered = builtins.filter hasUpdateScript names;
  in
  builtins.concatStringsSep "\n" filtered
')

if [[ -z ${packages} ]]; then
  echo "No packages with passthru.updateScript for system ${SYSTEM}."
  exit 0
fi

while IFS= read -r pkg; do
  [[ -z ${pkg} ]] && continue
  echo "==> Running update script for ${pkg}"
  attr_path="legacyPackages.${SYSTEM}.\"${pkg}\".passthru.updateScript"
  nix run "${FLAKE_ROOT}#${attr_path}"
done <<<"${packages}"
