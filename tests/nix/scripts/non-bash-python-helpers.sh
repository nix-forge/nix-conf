# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export HOME="$TMPDIR/home"
mkdir -p "$HOME"
@lib_getExe_identity@ --help >/dev/null
CRX_PROGRAM=@lib_getExe_crx@ PREFERENCES_PROGRAM=@lib_getExe_preferences@ \
  python3 @check_python_helpers_py@
touch "$out"
