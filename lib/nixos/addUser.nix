{
  username,
  description ? "",
  extraGroups ? [ ],
  initialPassword ? "password",
  isNormalUser ? true,
  homeModules ? [ ],
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
    imports = homeModules;
    home = {
      inherit username;
      stateVersion = config.system.stateVersion;
      homeDirectory = config.users.users.${username}.home;
    };
  };
}
