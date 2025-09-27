#!/usr/bin/env bash
set -euo pipefail

FLAKE_ROOT="${FLAKE_ROOT:-.}"
HOST_SYSTEM="$(nix eval --impure --raw --expr 'builtins.currentSystem' 2>/dev/null || true)"
SYSTEM="${SYSTEM:-${HOST_SYSTEM:-x86_64-linux}}"
SUMMARY_FILE="${SUMMARY_FILE:-/tmp/update-packages-body.md}"

mkdir -p "$(dirname "${SUMMARY_FILE}")"

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

# Helper utilities for summarising the updates and retrieving metadata.
write_empty_summary() {
	cat <<EOF >"${SUMMARY_FILE}"
Automated update of packages with \`passthru.updateScript\`.

- System: \`${SYSTEM}\`

_No version changes detected. Please review the diff for further details._
EOF

	if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
		cat "${SUMMARY_FILE}" >>"${GITHUB_STEP_SUMMARY}"
	fi
}

get_pkg_info() {
	local attr="$1"
	if ! nix eval --raw ".#${attr}" --apply 'drv: let toStr = x: if x == null then "" else builtins.toString x; pname = if drv ? pname then drv.pname else if drv ? passthru && drv.passthru ? pname then drv.passthru.pname else if drv ? name then drv.name else ""; version = if drv ? version then drv.version else if drv ? passthru && drv.passthru ? version then drv.passthru.version else ""; in toStr pname + "\t" + toStr version' 2>/dev/null; then
		printf '\t'
	fi
}

fmt_version() {
	local value="$1"
	local backtick=$'`'
	if [[ -z ${value} ]]; then
		printf '_unknown_'
	else
		printf '%s%s%s' "${backtick}" "${value}" "${backtick}"
	fi
}

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

if [[ -z ${packages//[$'\n\r\t ']/} ]]; then
	echo "No packages with passthru.updateScript for system ${SYSTEM}."
	write_empty_summary
	popd >/dev/null
	exit 0
fi

declare -a package_list=()
while IFS= read -r pkg; do
	[[ -z ${pkg} ]] && continue
	pkg="${pkg%\"}"
	pkg="${pkg#\"}"
	pkg="${pkg%\'}"
	pkg="${pkg#\'}"
	package_list+=("${pkg}")
done <<<"${packages}"

if ((${#package_list[@]} == 0)); then
	echo "No packages with passthru.updateScript for system ${SYSTEM}."
	write_empty_summary
	popd >/dev/null
	exit 0
fi

declare -A pkg_names=()
declare -A pkg_before=()
declare -A pkg_after=()

for pkg in "${package_list[@]}"; do
	attr="legacyPackages.${SYSTEM}.${pkg}"
	info=$(get_pkg_info "${attr}")
	IFS=$'\t' read -r pname version <<<"${info}"
	[[ -n ${pname} ]] || pname="${pkg}"
	pkg_names["${pkg}"]="${pname}"
	pkg_before["${pkg}"]="${version}"
done

for pkg in "${package_list[@]}"; do
	echo "==> Running update script for ${pkg}"
	attr="legacyPackages.${SYSTEM}.${pkg}"
	nix build ".#${attr}.passthru.updateScriptPackage" --no-link --print-out-paths >/dev/null 2>&1 || true
	cmd_joined=$(nix eval --raw ".#${attr}.passthru.updateScript.command" --apply 'cmd: builtins.concatStringsSep "\t" cmd' 2>/dev/null || true)
	if [[ -z ${cmd_joined} ]]; then
		echo "No passthru.updateScript.command found for ${pkg}, skipping" >&2
		continue
	fi
	IFS=$'\t' read -r -a cmd_parts <<<"${cmd_joined}"
	echo "Running: ${cmd_parts[*]}"
	"${cmd_parts[@]}"
done

for pkg in "${package_list[@]}"; do
	attr="legacyPackages.${SYSTEM}.${pkg}"
	info=$(get_pkg_info "${attr}")
	IFS=$'\t' read -r pname version <<<"${info}"
	if [[ -n ${pname} ]]; then
		pkg_names["${pkg}"]="${pname}"
	fi
	pkg_after["${pkg}"]="${version}"
done

updated_packages=()
for pkg in "${package_list[@]}"; do
	before="${pkg_before["${pkg}"]:-}"
	after="${pkg_after["${pkg}"]:-}"
	if [[ ${before} != "${after}" ]]; then
		updated_packages+=("${pkg}")
	fi
done

{
	echo "Automated update of packages with $(passthru.updateScript)."
	echo
	echo "- System: \`${SYSTEM}\`"
	echo
	if ((${#updated_packages[@]} == 0)); then
		echo "_No version changes detected. Please review the diff for further details._"
	else
		echo "## Updated packages"
		echo
		echo "| Attribute | Package | From | To |"
		echo "| --- | --- | --- | --- |"
		for pkg in "${updated_packages[@]}"; do
			before="${pkg_before["${pkg}"]:-}"
			after="${pkg_after["${pkg}"]:-}"
			pname="${pkg_names["${pkg}"]:-${pkg}}"
			pname="${pname//|/\|}"
			before_fmt=$(fmt_version "${before}")
			after_fmt=$(fmt_version "${after}")
			printf "| \`%s\` | %s | %s | %s |\n" "${pkg}" "${pname}" "${before_fmt}" "${after_fmt}"
		done
	fi
} >"${SUMMARY_FILE}"

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
	cat "${SUMMARY_FILE}" >>"${GITHUB_STEP_SUMMARY}"
fi

popd >/dev/null
