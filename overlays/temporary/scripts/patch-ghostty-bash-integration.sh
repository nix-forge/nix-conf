# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out"
cp -r @package_shell_integration@/bash "$out/bash"
chmod -R u+w "$out"
patch --directory "$out" --fuzz=0 -p3 <@patches_ghostty_bash_ble_prompt_patch@
bash -n "$out/bash/ghostty.bash"
