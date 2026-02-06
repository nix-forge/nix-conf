{ lib, self, ... }:
let
  inherit (lib) concatLists singleton;
  inherit (self) mkNixpkgsConfig;
in
{
  mkHost =
    {
      withSystem,
      inputs,
      self,
      builder,
      homeConfigs ? { },
      extraSpecialArgs ? { },
    }:
    { system, ... }@args:
    withSystem system (
      { inputs', self', ... }:
      let
        specialArgs = {
          inherit inputs' self';
          inherit inputs self;
          inherit system homeConfigs;
        }
        // extraSpecialArgs
        // (args.specialArgs or { });

        nixpkgsConfig = mkNixpkgsConfig {
          inherit system;
          nixpkgsArgs = args.nixpkgsArgs or { };
          nixpkgsSource = inputs.nixpkgs.outPath;
        };

        modules = concatLists [
          (singleton {
            networking.hostName = args.hostname or args.hostName or args.folderName;
          })
          (singleton nixpkgsConfig)
          (args.modules or [ ])
        ];

      in
      builder { inherit modules specialArgs; }
    );
}
