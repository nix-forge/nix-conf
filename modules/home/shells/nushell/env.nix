{
  lib,
  myLib,
  config,
  ...
}:
{
  programs.nushell.extraEnv = lib.mkBefore (
    myLib.shells.renderNuEnvironment {
      inherit (lib.hm.nushell) toNushell;
      inherit (config.home) homeDirectory username;
    } config.home.sessionVariables
  );
}
