{
  primaryUser ? "root",
}:
{
  inputs,
  system,
  ...
}:
let
  userAccess = {
    mode = "0500"; # read and execute only
    owner = primaryUser;
  };

  configSecrets = secrets: setting: builtins.mapAttrs (_: settings: settings // setting) secrets;
in
{
  # enable the secrets module
  imports = [ inputs.agenix.nixosModules.default ];

  # install agenix
  environment.defaultPackages = [ inputs.agenix.packages.${system}.agenix ];

  # add secrets to the system
  age.secrets =
    if primaryUser != "root" then
      configSecrets inputs.nix-secrets.shared userAccess
    else
      inputs.nix-secrets.shared;
}
