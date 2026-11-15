let
  profile = import ./profile.nix;
  targets =
    inputs: class:
    (inputs.nix-config-framework.lib.mkSharedModuleSet {
      root = ./.;
      inherit class;
      args = { inherit inputs; };
    }).targets;
in
{
  nixos = { inputs, ... }: {
    imports = [
      profile.nixos
      (targets inputs "nixos")
    ];
  };
  darwin = { inputs, ... }: {
    imports = [
      profile.darwin
      (targets inputs "darwin")
    ];
  };
  homeManager = { inputs, ... }: {
    imports = [
      profile.homeManager
      (targets inputs "homeManager")
    ];
  };
}
