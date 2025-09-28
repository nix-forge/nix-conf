#!/usr/bin/env bash
set -euo pipefail

flake_lock=${1:-flake.lock}

if [[ ! -f $flake_lock   ]]; then
	echo "Could not find flake lock file at '$flake_lock'" >&2
	exit 1
fi

mapfile -t lines < <(jq -r '
  .nodes as $nodes
  | (.nodes.root.inputs | keys | sort[]) as $name
  | ($nodes[$name] // {}) as $node
  | ($node.locked.type // "") as $type
  | (
      ($node.locked.url // $node.original.url // "")
    ) as $url
  | if ($type == "git") or ($url | test("^(ssh://|git@)"))
      then "exclude\t\($name)"
      else "include\t\($name)"
    end
' "$flake_lock")

public_inputs=()
private_inputs=()

for line in "${lines[@]}"; do
	IFS=$'\t' read -r category name <<< "$line"
	case "$category" in
		include)
			public_inputs+=("$name")
			;;
		exclude)
			private_inputs+=("$name")
			;;
		*)
			echo "Unexpected category '$category' for input '$name'" >&2
			exit 1
			;;
	esac
done

if ((${#public_inputs[@]} == 0)); then
	echo "No public inputs detected in $flake_lock" >&2
	exit 1
fi

echo "Including ${#public_inputs[@]} flake inputs:" >&2
for name in "${public_inputs[@]}"; do
	echo "  - $name" >&2
done

if ((${#private_inputs[@]} > 0)); then
	echo "Skipping ${#private_inputs[@]} private inputs:" >&2
	for name in "${private_inputs[@]}"; do
		echo "  - $name" >&2
	done
else
	echo "No private inputs detected." >&2
fi

if [[ -z ${GITHUB_OUTPUT:-}   ]]; then
	echo "GITHUB_OUTPUT is not set" >&2
	exit 1
fi

{
	echo "inputs<<EOF"
	printf '%s\n' "${public_inputs[@]}"
	echo "EOF"
} >> "$GITHUB_OUTPUT"

{
	echo "excluded<<EOF"
	printf '%s\n' "${private_inputs[@]}"
	echo "EOF"
} >> "$GITHUB_OUTPUT"
