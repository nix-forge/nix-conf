#!/usr/bin/env bash
# Exercise transport and exported names outside a Nix build sandbox.
set -euo pipefail
if [[ $# -gt 2 ]]; then
  echo 'usage: check-consumers.sh [CANDIDATE_FLAKE] [SYSTEM]' >&2
  exit 2
fi
if [[ $# -gt 0 ]]; then
  candidate=$1
else
  repo=$(git rev-parse --show-toplevel)
  candidate="git+file://$repo?submodules=1"
fi
native_system=$(nix eval --impure --raw --expr builtins.currentSystem)
system=${2:-$native_system}
if [[ "$system" != "$native_system" ]]; then
  echo "consumer checks require native $system, current host is $native_system" >&2
  exit 2
fi
case "$system" in
x86_64-linux | aarch64-linux | aarch64-darwin) ;;
*)
  echo "unsupported public consumer system: $system" >&2
  exit 2
  ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Resolve all fixtures and pins from one immutable fetched candidate. A dirty
# Git candidate includes tracked working content, not unrelated untracked files.
# Determinate's lazy trees intentionally omit metadata.path. Force a store
# snapshot here because every later consumer must read the same source bytes.
metadata=$(nix flake metadata --no-update-lock-file --option lazy-trees false --json "$candidate")
source_path=$(jq -er '.path' <<<"$metadata")
printf 'Testing public consumers from %s on %s\n' "$source_path" "$system"
export PUBLIC_GUIDE_CANDIDATE="path:$source_path"
inputs=$(nix eval --impure --json --expr '
  let candidate = builtins.getFlake (builtins.getEnv "PUBLIC_GUIDE_CANDIDATE");
  in { nixpkgs = candidate.inputs.nixpkgs.outPath; homeManager = candidate.inputs.home-manager.outPath; }
')
nixpkgs_path=$(jq -er '.nixpkgs' <<<"$inputs")
home_manager_path=$(jq -er '.homeManager' <<<"$inputs")
# Use the already captured store source for every subsequent candidate access.
# This also prevents an editor changing the checkout halfway through a run.
candidate="path:$source_path"
for template in starter darwin; do
  mkdir "$work/$template"
  (cd "$work/$template" && nix flake init --template "$candidate#$template")
  diff -qr "$source_path/templates/$template" "$work/$template"
done
nix build --no-link --no-update-lock-file --max-jobs 1 --cores 2 \
  "$work/starter#checks.$system.home" \
  "$work/starter#checks.$system.generated-config"
if [[ "$system" == x86_64-linux ]]; then
  nix build --no-link --no-update-lock-file --max-jobs 1 --cores 2 \
    "$work/starter#checks.$system.vm-runtime"
fi
if [[ "$system" == aarch64-darwin ]]; then
  nix build --no-link --no-update-lock-file --max-jobs 1 --cores 2 \
    "$work/darwin#checks.$system.system" \
    "$work/darwin#checks.$system.generated-config"
else
  # Evaluate assertions and the system derivation; Linux is not a native build.
  nix eval --raw --no-update-lock-file "$work/darwin#darwinConfigurations.example.system.drvPath"
fi
for interface in source typed; do
  mkdir "$work/$interface"
  cp "$source_path/tests/public-guide/$interface-consumer/flake.nix" "$work/$interface/flake.nix"
  cp "$source_path/tests/public-guide/recipes.nix" "$work/$interface/recipes.nix"
  if [[ "$interface" == source ]]; then
    overrides=(--override-input nix-conf-source "$candidate"
      --override-input nixpkgs "path:$nixpkgs_path"
      --override-input home-manager "path:$home_manager_path")
  else
    overrides=(--override-input nix-conf "$candidate")
  fi
  nix build --no-link --no-write-lock-file --max-jobs 1 --cores 2 \
    "${overrides[@]}" "$work/$interface#checks.$system.recipes"
done
