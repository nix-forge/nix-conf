{
  self,
  config,
  lib,
  tree,
  ...
}: {
  imports =
    # import extra nixos modules
    [
      self.nixosModules.users
    ]
    # Set the mainUser
    ++ [{users.mainUser = "ianmh";}]
    # Add Users
    ++ (with lib.cust.nixos; let
      homeConfigs = tree.home.configs;
    in [
      (addUser {
        username = "ianmh";
        description = "Ian Holloway";
        groups = ["wheel" "audio" "video"];
        initialPassword = "password";
        homeModules = homeConfigs.desktop.modules {inherit tree;};
      })

      (addUser {
        username = "guest";
        description = "Guest User";
        groups = ["audio" "video"];
        initialPassword = "password";
      })
    ]);
}
