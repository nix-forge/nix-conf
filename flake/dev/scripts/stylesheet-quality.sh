# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cd @source@ || exit
stylelint --config .stylelintrc.json --max-warnings 0 '**/*.css'
touch "$out"
