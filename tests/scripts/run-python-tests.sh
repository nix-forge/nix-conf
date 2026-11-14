# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
set -euo pipefail
work_directory="$TMPDIR/python-behavior-source"
mkdir "$work_directory"
cp -R @source@/. "$work_directory"
chmod -R u+w "$work_directory"
cd "$work_directory"
export HOME="$TMPDIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$HOME"
@prepare@
mkdir -p "$out"
python3 -m pytest -m @pkgs_lib_escapeShellArg_selection@ \
  --junitxml="$out/junit.xml" @pkgs_lib_escapeShellArgs_testPaths@
