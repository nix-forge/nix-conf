{ inputs, myLib, ... }: {
  imports = [ inputs.nix-config-framework.flakeModules.default ];

  flake.lib = myLib // {
    packagesFor = platform: inputs.nixpkgs-personal.lib.packagesFor platform;
    nixosConfigurationFor =
      { name, buildSystem }:
      inputs.self.nixosConfigurations.${name}.extendModules {
        # Some vendor package sets stay native even for a non-native caller.
        # Keep the declared builder available to scoped emulation repairs.
        specialArgs = { inherit buildSystem; };
        modules = [ ({ lib, ... }: { nixpkgs.buildPlatform = lib.mkForce buildSystem; }) ];
      };
  };

  nixConfigFramework = {
    root = ../.;
    extraSpecialArgs = { inherit myLib; };
  };
}
