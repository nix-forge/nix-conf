# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
python3 @scripts_check_ironbar_py@ @serviceHome_config_xdg_configFile_ironbar_config_toml_source@
touch "$out"
