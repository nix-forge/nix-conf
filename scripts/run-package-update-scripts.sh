#!/usr/bin/env bash
set -euo pipefail

FLAKE_ROOT="${FLAKE_ROOT:-.}"
HOST_SYSTEM="$(nix eval --impure --raw --expr 'builtins.currentSystem' 2>/dev/null || true)"
SYSTEM="${SYSTEM:-${HOST_SYSTEM:-x86_64-linux}}"

if [[ -n ${HOST_SYSTEM} && ${HOST_SYSTEM} != "${SYSTEM}" ]]; then
  echo "Host system ${HOST_SYSTEM} does not match requested system ${SYSTEM}." >&2
  echo "Set SYSTEM to the desired target if you are running on a different host." >&2
fi

if git config --local --get core.fsmonitor >/dev/null 2>&1; then
  git config --local --unset core.fsmonitor >/dev/null 2>&1 || git config --local core.fsmonitor false
fi

rm -f .git/fsmonitor--daemon.ipc 2>/dev/null || true

pushd "${FLAKE_ROOT}" >/dev/null

rm -f .git/fsmonitor--daemon.ipc 2>/dev/null || true

# Collect all attribute paths (including nested ones) under legacyPackages.${SYSTEM}
# that refer to derivations exposing passthru.updateScript. This ensures nested
# packages like vscode-extensions.copilot and vscode-extensions."copilot-chat"
# are picked up by CI. We use a here-doc to avoid shell quoting pitfalls.
packages=$(
  nix eval --raw ".#legacyPackages.${SYSTEM}" --apply "$(
    cat <<'NIX'
pkgs:
let
  isDrv = v: (v.type or null) == "derivation";
  hasUS = v: isDrv v && v ? passthru && v.passthru ? updateScript;
  needsQuote = s: builtins.match "^[a-zA-Z_][a-zA-Z0-9_']*$" s == null;
  q = "\""; # double quote character
  escape = s: builtins.replaceStrings ["\\" "\""] ["\\\\" "\\\""] s;
  fmt = s: if needsQuote s then q + (escape s) + q else s;
  recCollect = path: v:
    if isDrv v then
      if hasUS v then [ path ] else []
    else if builtins.isAttrs v then
      builtins.concatLists (
        builtins.map (
          n:
            let seg = fmt n; newPath = if path == "" then seg else path + "." + seg; in
            recCollect newPath (builtins.getAttr n v)
        ) (builtins.attrNames v)
      )
    else [];
  paths = recCollect "" pkgs;
in builtins.concatStringsSep "\n" paths
NIX
  )"
)

if [[ -z ${packages} ]]; then
  echo "No packages with passthru.updateScript for system ${SYSTEM}."
  popd >/dev/null
  exit 0
fi

while IFS= read -r pkg; do
  [[ -z ${pkg} ]] && continue
  echo "==> Running update script for ${pkg}"
  attr="legacyPackages.${SYSTEM}.${pkg}"
  nix run nixpkgs#nix-update -- --flake --system "${SYSTEM}" --use-update-script --version fixed --no-src "${attr}"
done <<<"${packages}"

popd >/dev/null
