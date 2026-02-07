{
  inputs,
  config,
  lib,
  ...
}:
let
  user = config.home.username;

  userAccess = {
    mode = "0500"; # read and execute only
  };

  configSecrets = secrets: setting: builtins.mapAttrs (_: settings: settings // setting) secrets;
in
{
  # enable the secrets module
  imports = [ inputs.agenix.homeManagerModules.default ];

  # install agenix
  # home.packages = [
  #   (inputs.agenix.packages.${system}.agenix.override (
  #     let
  #       nixPackage =
  #         if pkgs.stdenv.hostPlatform.isDarwin && darwinNixEnabled then
  #           args.darwinConfig.nix.package
  #         else
  #           inputs.determinate.inputs.nix.packages.${system}.default;
  #     in
  #     {
  #       nix = nixPackage;
  #     }
  #   ))
  # ];

  age = {
    secrets = lib.mkMerge [
      (configSecrets inputs.nix-secrets.users.${user}.secrets userAccess)
      (configSecrets inputs.nix-secrets.shared.secrets userAccess)
    ];
    secretsDir = "${config.xdg.userDirs.extraConfig.RUNTIME}/agenix";
    secretsMountPoint = "${config.xdg.userDirs.extraConfig.RUNTIME}/agenix.d";
  };

}
