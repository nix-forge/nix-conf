{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./default.nix ];
  home.sessionVariables.VISUAL = lib.mkDefault (
    # Darwin must use the copied application's managed launcher.
    if pkgs.stdenv.hostPlatform.isDarwin || config.programs.vscode.package == null then
      "code"
    else
      lib.getExe config.programs.vscode.package
  );
}
