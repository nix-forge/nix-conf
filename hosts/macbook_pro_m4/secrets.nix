{
  inputs,
  pkgs,
  ...
}:
let

  rootAccess = {
    mode = "0500"; # read and execute only
    owner = "root";
  };

  configSecrets = secrets: setting: builtins.mapAttrs (_: settings: settings // setting) secrets;
in
{
  # enable the secrets module
  imports = [ inputs.agenix.nixosModules.default ];

  # install agenix
  environment.defaultPackages = [
    inputs.agenix.packages.${pkgs.system}.agenix
  ];

  # add secrets to the system
  age.secrets = configSecrets inputs.nix-secrets.shared rootAccess;
}
