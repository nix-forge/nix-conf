{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
let
  pkgsNur =
    (import inputs.nixpkgs {
      inherit (pkgs) system;
      overlays = [ inputs.nur.overlays.default ];
    }).nur;
in
{
  programs.ghostty = {
    enable = true;
    package = lib.mkIf (pkgs.stdenv.isDarwin) pkgsNur.repos.DimitarNestorov.ghostty;

    settings =
      {
        background-blur-radius = 20;
        mouse-hide-while-typing = true;
        window-decoration = true;
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
