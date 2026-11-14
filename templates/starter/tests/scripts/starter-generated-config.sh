# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
set -euo pipefail
export HOME="$TMPDIR/empty-home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
config=@home_config_xdg_configFile_git_config_source@
test "$(git config --file "$config" init.defaultBranch)" = main
test "$(git config --file "$config" pull.ff)" = only
test "$(git config --file "$config" alias.st)" = 'status --short --branch'
test -z "$(git config --file "$config" user.email || true)"
grep -F "gs='git status --short --branch'" @home_config_home_file_bashrc_source@
python3 @scripts_generated_config_check_py@ @home_config_home_file_home_config_xdg_configHome_starship_to@
touch "$out"
