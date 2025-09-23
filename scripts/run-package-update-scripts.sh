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

	# Evaluate the command array for passthru.updateScript.command and execute it directly.
	# We join elements with a tab in Nix and split here to preserve spaces within args.
	# First, build the update script package so the binary exists in the store (if provided).
	nix build ".#${attr}.passthru.updateScriptPackage" --no-link --print-out-paths >/dev/null 2>&1 || true

	cmd_joined=$(nix eval --raw ".#${attr}.passthru.updateScript.command" --apply 'cmd: builtins.concatStringsSep "\t" cmd' 2>/dev/null || true)
	if [[ -z ${cmd_joined} ]]; then
		echo "No passthru.updateScript.command found for ${pkg}, skipping" >&2
		continue
	fi
	IFS=$'\t' read -r -a cmd_parts <<<"${cmd_joined}"
	echo "Running: ${cmd_parts[*]}"
	"${cmd_parts[@]}"
done <<<"${packages}"

popd >/dev/null
