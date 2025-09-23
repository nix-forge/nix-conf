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
  topNames = builtins.attrNames pkgs;
  topMatches = builtins.filter (n: hasUS (builtins.getAttr n pkgs)) topNames;
  nestedMatches = builtins.concatLists (
    builtins.map (
      n:
        let parent = builtins.getAttr n pkgs; in
        if (!isDrv parent) && builtins.isAttrs parent then
          let children = builtins.attrNames parent;
              hasUSAttr = v: v ? passthru && v.passthru ? updateScript;
              matches = builtins.filter (c: hasUSAttr (builtins.getAttr c parent)) children;
              # also scan one more level for grandchildren
              grandMatches = builtins.concatLists (
                builtins.map (
                  c:
                    let kid = builtins.getAttr c parent; in
                    if builtins.isAttrs kid && !isDrv kid then
                      let gchildren = builtins.attrNames kid;
                          gmatches = builtins.filter (g: hasUSAttr (builtins.getAttr g kid)) gchildren;
                      in builtins.map (g: n + "." + c + "." + g) gmatches
                    else []
                ) children
              );
          in (builtins.map (c: n + "." + c) matches) ++ grandMatches
        else []
    ) topNames
  );
in builtins.concatStringsSep "\n" (topMatches ++ nestedMatches)
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
  # Some evaluators may quote attribute names. Strip surrounding single/double quotes.
  pkg="${pkg%\"}"
  pkg="${pkg#\"}"
  pkg="${pkg%\'}"
  pkg="${pkg#\'}"
  echo "==> Running update script for ${pkg}"
  attr="legacyPackages.${SYSTEM}.${pkg}"
  nix run nixpkgs#nix-update -- --flake --system "${SYSTEM}" --use-update-script --version fixed --no-src "${attr}"
done <<<"${packages}"

popd >/dev/null
