# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
python3 @scripts_generated_configs_check_py@ @osd_config_xdg_configFile_swayosd_config_toml_source@
touch "$out"
