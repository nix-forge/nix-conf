# shellcheck shell=bash
# The SDK omits this private declaration while exporting its real primop symbols.
printf '%s  %s\n' '@sourceHeaderSHA256@' @sourceHeader@ |
  @sha256sum@ --check --status || exit $?
@install@ -Dm644 @sourceHeader@ src/nix/flake/flake-primops.hh
