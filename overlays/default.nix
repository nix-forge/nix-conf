{ inputs }:
inputs.nixpkgs.lib.composeManyExtensions [
  (import ./permanent/personal.nix { inherit inputs; })
  (import ./permanent/determinate.nix { inherit inputs; })
  (
    _final: prev:
    import ./packages.nix {
      inherit inputs;
      pkgs = prev;
    }
  )
]
