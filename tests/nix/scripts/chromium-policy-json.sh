# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
test -n @lib_escapeShellArg_merged_config_environment_etc_helium_poli@
touch "$out"
