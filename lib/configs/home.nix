{ lib, ... }:
let
  inherit (lib) concatLists singleton;
in
{
  # Build a standalone Home Manager configuration
  #
  # Mirrors mkHost but produces a homeManagerConfiguration instead of a system.
  # Each home config directory should have a default.nix that returns:
  #   { system, username, homeDirectory, modules, stateVersion?, nixpkgsArgs?, extraSpecialArgs? }
  #
  # Type: { withSystem, inputs, self } -> HomeSpec -> HomeManagerConfiguration
  mkHome =
    {
      withSystem,
      inputs,
      self,
    }:
    {
      system,
      username,
      homeDirectory,
      uid,
      ...
    }@args:
    withSystem system (
      { inputs', self', ... }:
      let
        pkgs = import inputs.nixpkgs ({ inherit system; } // (args.nixpkgsArgs or { }));

        extraSpecialArgs = {
          inherit
            inputs'
            self'
            inputs
            self
            system
            ;
        }
        // (args.extraSpecialArgs or { });

        modules = concatLists [
          (singleton {
            home = {
              username = lib.mkForce username;
              homeDirectory = lib.mkForce homeDirectory;
              uid = lib.mkForce uid;
            };
            programs.home-manager.enable = true;
          })
          (args.modules or [ ])
        ];
      in
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs modules extraSpecialArgs;
      }
    );

  connectHome =
    {
      config,
      username ? config.username,
      homeDirectory ? config.homeDirectory,
      uid ? config.uid,
    }:
    {
      ${username} = {
        imports = config.modules;
        home = {
          username = lib.mkForce username;
          homeDirectory = lib.mkForce homeDirectory;
          uid = lib.mkForce uid;
        };
        programs.home-manager.enable = true;
      };
    };
}
