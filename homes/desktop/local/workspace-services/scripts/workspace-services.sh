# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out/share/systemd/user"
@lib_concatStringsSep_n_lib_mapAttrsToList_name_file_ln_s_fil@
