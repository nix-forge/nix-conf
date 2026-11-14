# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export HOME="$TMPDIR"
pytest -q -o addopts= @check_special_files_py@
touch "$out"
