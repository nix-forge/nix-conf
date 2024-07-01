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
    (x: x // { nixpkgs.flake = inputs.nixpkgs; })
  ];
in
{
  nix = {
    # Pin the registry to avoid downloading and evaluating a new nixpkgs version every time
    # this will add each flake input as a registry to make nix3 commands consistent with your flake
    # additionally we also set `registry.default`, which was added by nix-super
    registry =
      mappedRegistry
      // lib.optionalAttrs (config.nix.package == inputs.nix-super.packages.${pkgs.system}.default) {
        default = mappedRegistry.nixpkgs;
      };

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well
    nixPath = lib.mapAttrsToList (key: _: "${key}=flake:${key}") config.nix.registry;
  };
}
