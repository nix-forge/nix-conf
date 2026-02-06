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
      homes ? { },
      extraSpecialArgs ? { },
    }:
    { system, ... }@args:
    withSystem system (
      { inputs', self', ... }:
      let
        specialArgs = {
          inherit inputs' self';
          inherit inputs self;
          inherit system homes;
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
