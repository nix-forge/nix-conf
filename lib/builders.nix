{ lib, ... }:
let
  inherit (lib.lists) singleton concatLists;

  mkHost =
    {
      withSystem,
      system,
      folderName,
      inputs,
      lib,
      ...
    }@args:
    withSystem system (
      { inputs', self', ... }:
      let
        homeManager = inputs.home-manager;
        overlays = args.overlays or [ ];

        # Lib for Home Manager
        libHome = lib.extend (
          self: _super: { hm = import "${homeManager}/modules/lib" { lib = self; }; }
        );

        # SpecialArgs
        baseArgs = {
          inherit inputs' self';
          inherit inputs system;
          self = args.self or { };
          tree = args.tree or { };
        }
        // (args.specialArgs or { });

        nixosSpecialArgs = baseArgs // {
          inherit lib;
        };

        homeSpecialArgs = baseArgs // {
          lib = lib // libHome;
        };

        # Define the home-manager modules
        nixosHomeManager = [
          # Import the home-manager NixOS Modules
          homeManager.nixosModules.home-manager
          # General NixOS home-manager config
          (
            { config, ... }:
            let
              nixosConfig = config;
            in
            {
              home-manager = {
                # tell home-manager to be as verbose as possible
                verbose = true;

                # use the system configuration’s pkgs argument
                # this ensures parity between nixos' pkgs and hm's pkgs
                useGlobalPkgs = true;

                # enable the usage user packages through
                # the users.users.<name>.packages option
                useUserPackages = true;

                # move existing files to the .hm.old suffix rather than failing
                # with a very long error message about it
                backupFileExtension = "hm.old";

                # extra specialArgs passed to Home Manager
                # for reference, the config argument in nixos can be accessed
                # in home-manager through osConfig without us passing it
                extraSpecialArgs = homeSpecialArgs // {
                  inherit nixosConfig;
                };
              };
            }
          )
        ];

        # Default Custom Options Modules
        defaultCustomOptions = [
          {
            # Add a option which can be used to find all normal users if setup properly
            options.users = {
              normalUsers = lib.mkOption {
                # type set
                type = lib.types.listOf lib.types.attrs;
                default = [ ];
              };
            };
          }
        ];
      in
      lib.nixosSystem {
        # specialArgs
        specialArgs = nixosSpecialArgs;

        # Modules
        modules = concatLists [
          (singleton {
            networking.hostName = args.hostname or args.hostName or folderName;
            nixpkgs = {
              overlays = overlays ++ [ (import "${homeManager}/overlay.nix") ];
              hostPlatform = { inherit system; };
              flake.source = inputs.nixpkgs.outPath;
            }
            // (args.nixpkgsArgs or { });
          })

          # if host needs additional modules, append them
          # NOTE: withTreeModules shouldn't cause issues if tree modules aren't used
          (lib.cust.withTreeModules (args.modules or [ ]))

          # Home Manager modules
          nixosHomeManager

          # Add custom options that are required for all hosts
          defaultCustomOptions
        ];
      }
    );

  mkDarwin =
    {
      withSystem,
      system,
      inputs,
      folderName,
      lib,
      ...
    }@args:
    withSystem system (
      { inputs', self', ... }:
      let
        nixDarwin = inputs.nix-darwin;
        homeManager = inputs.home-manager;

        # Lib for Home Manager
        libHome = lib.extend (
          self: _super: { hm = import "${homeManager}/modules/lib" { lib = self; }; }
        );

        # SpecialArgs
        baseArgs = {
          inherit inputs' self';
          inherit inputs system;
          self = args.self or { };
          tree = args.tree or { };
        }
        // (args.specialArgs or { });

        darwinSpecialArgs = baseArgs // {
          inherit lib;
        };

        homeSpecialArgs = baseArgs // {
          lib = lib // libHome;
        };

        # Define the home-manager modules
        darwinHomeManager = [
          # Import the home-manager darwinModules Modules
          homeManager.darwinModules.home-manager
          # General darwin home-manager config
          (
            { config, ... }:
            let
              darwinConfig = config;
            in
            {
              home-manager = {
                # tell home-manager to be as verbose as possible
                verbose = true;

                # use the system configuration’s pkgs argument
                # this ensures parity between nixos' pkgs and hm's pkgs
                useGlobalPkgs = true;

                # enable the usage user packages through
                # the users.users.<name>.packages option
                useUserPackages = true;

                # move existing files to the .hm.old suffix rather than failing
                # with a very long error message about it
                backupFileExtension = "hm.old";

                # extra specialArgs passed to Home Manager
                # for reference, the config argument in nixos can be accessed
                # in home-manager through osConfig without us passing it
                extraSpecialArgs = homeSpecialArgs // {
                  inherit darwinConfig;
                };
              };
            }
          )
        ];
      in
      nixDarwin.lib.darwinSystem {
        specialArgs = darwinSpecialArgs;

        modules = concatLists [
          # Base Config
          (singleton {
            networking.hostName = args.hostname or args.hostName or folderName;
            nixpkgs = {
              hostPlatform = { inherit system; };
              flake.source = inputs.nixpkgs.outPath;
            }
            // (args.nixpkgsArgs or { });
          })

          # if host needs additional modules, append them
          # NOTE: withTreeModules shouldn't cause issues if tree modules aren't used
          (lib.cust.withTreeModules (args.modules or [ ]))

          # Home Manager modules
          darwinHomeManager

          # Determinate Nix
          [
            { nix.enable = false; }
            inputs.determinate.darwinModules.default
          ]
        ];
      }
    );
in
{
  inherit mkHost mkDarwin;
}
