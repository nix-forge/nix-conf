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
      ((import ./bash.nix { inherit (pkgs) lib; }).renderBashText { inherit pkgs; })
        {
          name = "check-lua-source.sh";
          text = ''
            # shellcheck shell=bash
            # Variables and functions are supplied by the owning activation or build phase.
            # shellcheck disable=SC2154
            LUA_SOURCE=@lib_escapeShellArg_src@ @lua_interpreter@ -e 'local chunk, err = loadfile(os.getenv("LUA_SOURCE")); if not chunk then io.stderr:write(err, "\n"); os.exit(1) end'
            @lib_getExe_pkgs_luaPackages_luacheck@ --no-config --std @lib_escapeShellArg_standard@ \
              @lib_optionalString_readGlobals_read_globals_lib_escapeShellA@ \
              -- @lib_escapeShellArg_src@
            cp @lib_escapeShellArg_src@ "$out"
            chmod 0444 "$out"
          '';
        }
        {
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
