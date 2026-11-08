# shellcheck shell=bash
# shellcheck disable=SC2043 # Nix renders zero or more separately quoted paths.
for conflict in @configurationPaths@; do
  if [[ -L $conflict && "$(readlink -- "$conflict")" != @builtins_storeDir@/*-home-manager-files/* ]]; then
    run @osConfig_home_manager_backupCommand@ "$conflict"
  fi
done
