{
  username,
  description ? "",
  extraGroups ? [ ],
  initialPassword ? "password",
  isNormalUser ? true,
  homeManagerModules ? [ ],
}:
{ config, ... }:
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
    home = {
      inherit username;
      stateVersion = config.system.stateVersion;
      homeDirectory = config.users.users.${username}.home;
    };
  };
}
