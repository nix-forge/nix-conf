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
    pkgs.runCommand name { } ''
      LUA_SOURCE=${lib.escapeShellArg "${src}"} ${lua.interpreter} -e 'assert(loadfile(os.getenv("LUA_SOURCE")))'
      ${lib.getExe pkgs.luaPackages.luacheck} --no-config --std ${lib.escapeShellArg standard} \
        ${lib.optionalString (readGlobals != [ ]) "--read-globals ${lib.escapeShellArgs readGlobals}"} \
        -- ${lib.escapeShellArg "${src}"}
      cp ${lib.escapeShellArg "${src}"} "$out"
      chmod 0444 "$out"
    '';
}
