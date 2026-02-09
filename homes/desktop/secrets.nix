{
  inputs,
  config,
  system,
  pkgs,
  ...
}@args:
let
  user = config.home.username;

  userAccess = {
    mode = "0500"; # read and execute only
  };

  configSecrets =
    secrets: setting: builtins.mapAttrs (_: settings: settings // setting) secrets;

  darwinNixEnabled = args ? darwinConfig && args.darwinConfig.nix.enable;
in
{
  # enable the secrets module
  imports = [ inputs.agenix.homeManagerModules.default ];

  # install agenix
  home.packages = [
    (inputs.agenix.packages.${system}.agenix.override (
      let
        nixPackage =
          if pkgs.stdenv.hostPlatform.isDarwin && darwinNixEnabled then
            args.darwinConfig.nix.package
          else
            inputs.determinate.inputs.nix.packages.${system}.default;
      in
      {
        nix = nixPackage;
      }
    ))
  ];

  age = {
    # add secrets to the user
    secrets = configSecrets inputs.nix-secrets.users.${user}.secrets userAccess;
  };
}
