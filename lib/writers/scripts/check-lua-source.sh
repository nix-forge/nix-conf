# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
# shellcheck disable=SC2154
LUA_SOURCE=@lib_escapeShellArg_src@ @lua_interpreter@ -e 'assert(loadfile(os.getenv("LUA_SOURCE")))'
@lib_getExe_pkgs_luaPackages_luacheck@ --no-config --std @lib_escapeShellArg_standard@ \
  @lib_optionalString_readGlobals_read_globals_lib_escapeShellA@ \
  -- @lib_escapeShellArg_src@
cp @lib_escapeShellArg_src@ "$out"
chmod 0444 "$out"
