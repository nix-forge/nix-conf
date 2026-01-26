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

  configSecrets =
    secrets: setting: builtins.mapAttrs (_: settings: settings // setting) secrets;
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

  age =
    let
      cond = lib.hasAttr "XDG_RUNTIME_DIR" config.home.sessionVariables;
      XDG_RUNTIME_DIR =
        if cond then config.home.sessionVariables.XDG_RUNTIME_DIR else null;
    in
    {
      # add secrets to the user
      secrets = configSecrets inputs.nix-secrets.users.${user} userAccess;

      secretsDir = lib.mkIf cond "${XDG_RUNTIME_DIR}/agenix";
      secretsMountPoint = lib.mkIf cond "${XDG_RUNTIME_DIR}/agenix.d";
    };
}
