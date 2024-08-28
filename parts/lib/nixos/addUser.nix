{
  username,
  homeDirectory ? "/home/${username}",
  description ? "",
  extraGroups ? [ ],
  initialPassword ? "password",
  isNormalUser ? true,
  homeManagerModules ? [ ],
}:
{ config, lib, ... }:
{
  config = {
    assertions = [
      {
        assertion = config.users ? normalUsers;
        message = "Import custom users module to use normalUsers list";
      }
    ];

    # Add user to custom normalUsers list
    users.normalUsers = [
      {
        inherit username;
        home = homeDirectory;
      }
    ];

    users.users.${username} = {
      inherit
        description
        extraGroups
        initialPassword
        isNormalUser
        ;
      home = lib.mkForce homeDirectory;
    };
    home-manager.users.${username} = {
      imports = homeManagerModules;

      # Use the same nix package as nixos
      nix.package = lib.mkForce config.nix.package;

      # Allow HM to manage itself when in standalone mode.
      # This makes the home-manager command available to users.
      programs.home-manager.enable = true;

      # Disable home-manager man-pages to save space
      manual = {
        manpages.enable = false;
        html.enable = false;
        json.enable = false;
      };

      # Set default settings based on the nixos settings
      home = {
        username = lib.mkForce username;
        stateVersion = lib.mkForce config.system.stateVersion;
        homeDirectory = lib.mkForce homeDirectory;
      };
    };
  };
}
