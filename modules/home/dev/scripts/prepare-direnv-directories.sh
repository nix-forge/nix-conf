# shellcheck shell=bash
# Sourced by Home Manager or the owning build phase.
run @lib_getExe_pkgs_coreutils_install@ -d -m 0700 \
  @lib_escapeShellArg_direnvCacheDirectory@ \
  @lib_escapeShellArg_direnvLayoutDirectory@
