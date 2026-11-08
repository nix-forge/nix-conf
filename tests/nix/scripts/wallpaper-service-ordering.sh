# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p units/graphical-session.target.wants runtime
@lib_concatMapStringsSep_n_name_cp_orderingHome_config_xdg_co@
export XDG_RUNTIME_DIR="$PWD/runtime"
export SYSTEMD_UNIT_PATH="$PWD/units:@pkgs_systemd@/example/systemd/user"
systemd-analyze --user --man=no verify graphical-session.target >verification.log 2>&1 || {
  cat verification.log
  exit 1
}
if grep -E 'ordering cycle|deleted to break' verification.log; then
  exit 1
fi
touch "$out"
