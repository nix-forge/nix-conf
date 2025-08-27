{
  lib,
  pkgs,
  config,
  ...
}:
{
  programs.ghostty = {
    enable = true;
    package = lib.mkIf (pkgs.stdenv.isDarwin) pkgs.ghostty-bin;

    settings = {
      background-blur-radius = 20;
      mouse-hide-while-typing = true;
      window-decoration = builtins.toString pkgs.stdenv.hostPlatform.isDarwin;
    }
    // lib.optionalAttrs (lib.hasAttr "SHELL" config.home.sessionVariables) (
      let
        shellPath = config.home.sessionVariables.SHELL;
        shellName = lib.last (lib.splitString "/" shellPath);
      in
      lib.optionalAttrs (shellName == "nu") {
        command = "${lib.getExe' pkgs.bashInteractive "bash"} --login -c '${shellPath} --login --interactive'";
      }
    );
  };
}
