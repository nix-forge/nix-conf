# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables. Quoted fragments retain literal dollars.
# shellcheck disable=SC2016,SC2154
export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
NU_CHECK_FILE=@lib_escapeShellArg_src@ @lib_getExe_nushell@ --no-config-file --commands \
  'if not (nu-check --debug $env.NU_CHECK_FILE) { exit 1 }'
cp @lib_escapeShellArg_src@ "$out"
chmod 0444 "$out"
