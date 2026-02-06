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
    { system, ... }@args:
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
              username = lib.mkForce args.username;
              homeDirectory = lib.mkForce args.homeDirectory;
            }
            // lib.optionalAttrs (args ? uid) { uid = args.uid; };
            programs.home-manager.enable = true;
          })
          (args.modules or [ ])
        ];
      in
      inputs.home-manager.lib.homeManagerConfiguration { inherit pkgs modules extraSpecialArgs; }
    );

  # Connect a standalone home configuration to a NixOS or Darwin system
  #
  # Takes a home configuration spec (as returned by a home config's default.nix)
  # and returns a NixOS/Darwin module that wires it into home-manager.users.<username>.
  #
  # This allows the same module list to be shared between standalone
  # homeConfigurations and system-integrated (NixOS/Darwin) configurations.
  #
  # Type: HomeSpec -> NixOS/DarwinModule
  #
  # Example:
  #   # In configs/nixos/desktop/default.nix:
  #   { modules, homeModules, connectHome, ... }:
  #   let
  #     homeSpec = import ../../home/desktop/default.nix { modules = homeModules; };
  #   in
  #   {
  #     system = "x86_64-linux";
  #     modules = with modules; [
  #       base-base
  #       (connectHome homeSpec)
  #     ];
  #   }
  connectHome =
    homeSpec:
    { ... }:
    {
      home-manager.users.${homeSpec.username} = {
        imports = homeSpec.modules or [ ];
        home = {
          username = lib.mkForce homeSpec.username;
          homeDirectory = lib.mkForce homeSpec.homeDirectory;
        };
      };
    };
}
