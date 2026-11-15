# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
set -euo pipefail
zsh -n "$zshrc"
grep -F "alias gs='git status --short --branch'" "$zshrc"
python3 @scripts_generated_config_check_py@ "$plist"
touch "$out"
