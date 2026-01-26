{
  inputs,
  config,
  system,
  ...
}:
let
  userAccess = {
    mode = "0500"; # read and execute only
    owner = config.system.primaryUser;
  };

  configSecrets =
    secrets: setting: builtins.mapAttrs (_: settings: settings // setting) secrets;
in
{
  # enable the secrets module
  imports = [ inputs.agenix.darwinModules.default ];

  # install agenix
  environment.defaultPackages = [ inputs.agenix.packages.${system}.agenix ];

  # add secrets to the system
  age.secrets = configSecrets inputs.nix-secrets.shared userAccess;
}
