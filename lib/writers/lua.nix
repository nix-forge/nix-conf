{ lib, ... }: {
  # Plugins are loaded by their application and must not gain an interpreter
  # line, executable wrapper, or a build-time invocation of their entry point.
  checkLuaFile =
    { pkgs }:
    {
      name,
      src,
      lua,
      readGlobals ? [ ],
    }:
    let
      standard =
        if lua.isLuaJIT or false then
          "luajit"
        else
          "lua${lib.replaceStrings [ "." ] [ "" ] lua.luaversion}";
    in
    pkgs.runCommand name { } (
      (import ../templates/text.nix) ./scripts/check-lua-source.sh {
        lib_escapeShellArg_src = lib.escapeShellArg "${src}";
        lua_interpreter = lua.interpreter;
        lib_getExe_pkgs_luaPackages_luacheck = lib.getExe pkgs.luaPackages.luacheck;
        lib_escapeShellArg_standard = lib.escapeShellArg standard;
        lib_optionalString_readGlobals_read_globals_lib_escapeShellA = lib.optionalString (
          readGlobals != [ ]
        ) "--read-globals ${lib.escapeShellArgs readGlobals}";
      }
    );
}
