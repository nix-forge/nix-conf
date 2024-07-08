{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  mappedRegistry = lib.pipe inputs [
    (lib.filterAttrs (_: lib.types.isType "flake"))
    (builtins.mapAttrs (_: flake: { inherit flake; }))
    (flakes: flakes // { nixpkgs.flake = inputs.nixpkgs; })
  ];
in
{
  nix = {
    # Pin the registry to avoid downloading and evaluating a new nixpkgs version every time
    # this will add each flake input as a registry to make nix3 commands consistent with your flake
    # additionally we also set `registry.default`, which was added by nix-super
    registry = mappedRegistry // {
      default = mappedRegistry.nixpkgs;
    };

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well
    nixPath = lib.mapAttrsToList (key: _: "${key}=flake:${key}") config.nix.registry;

    # Disallow internal flake registry by setting it to an empty JSON file
    settings.flake-registry = pkgs.writeText "flakes-empty.json" (
      builtins.toJSON {
        flakes = [ ];
        version = 2;
      }
    );
  };
}
