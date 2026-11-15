# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables. Quoted fragments retain literal dollars.
# shellcheck disable=SC2016,SC2154
test -f @nuParseOnly@
export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
@lib_getExe_pkgs_nushell@ --no-config-file --commands '
  use std/assert
  source @envFile@
  source @configFile@
  assert equal $env.LITERAL "quote\" slash\\ newline\n dollar$literal"
  assert equal $env.PREPEND "tail"
  assert equal $env.APPEND "head"
  assert ("/tmp/path with spaces" in $env.PATH)
  assert ("/tmp/quote\"and$sign" in $env.PATH)
'
PREPEND=prior APPEND=after @lib_getExe_pkgs_nushell@ --no-config-file --commands '
  use std/assert
  source @envFile@
  assert equal $env.PREPEND "prior:tail"
  assert equal $env.APPEND "head:after"
'
touch "$out"
