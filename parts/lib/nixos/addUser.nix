{
  username,
  description ? "",
  extraGroups ? [ ],
  initialPassword ? "password",
  isNormalUser ? true,
  homeManagerModules ? [ ],
}:
{ config, lib, ... }:
{
  users.users.${username} = {
    inherit
      description
      extraGroups
      initialPassword
      isNormalUser
      ;
  };
  home-manager.users.${username} = {
    imports = homeManagerModules;
    nix.package = lib.mkForce config.nix.package;
    home = {
      inherit username;
      stateVersion = lib.mkForce config.system.stateVersion;
      homeDirectory = lib.mkForce config.users.users.${username}.home;
    };
  };
}
