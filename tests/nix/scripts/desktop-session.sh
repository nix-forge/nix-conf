# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables. Quoted fragments retain literal dollars.
# shellcheck disable=SC2016,SC2154
set -eu
session_file=@pkgs_writeText_uwsm_session_class_sessionText@
# Exercise the generated shell code with absent, empty, ordinary and
# non-user classes. An existing greeter/background class must survive.
for initial in unset empty user greeter background; do
  expected="$initial"
  case "$initial" in
  unset | empty) expected=user ;;
  esac
  result=$(@pkgs_coreutils@/bin/env -i @pkgs_runtimeShell@ -c '
    case "$1" in
      unset) unset XDG_SESSION_CLASS ;;
      empty) export XDG_SESSION_CLASS="" ;;
      *) export XDG_SESSION_CLASS="$1" ;;
    esac
    . "$2"
    printf "%s" "$XDG_SESSION_CLASS"
  ' session-check "$initial" "$session_file")
  test "$result" = "$expected"
done
touch "$out"
