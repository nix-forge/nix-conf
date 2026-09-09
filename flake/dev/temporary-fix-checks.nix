{ inputs, ... }: {
  perSystem =
    { pkgs, ... }:
    let
      # Evaluation covers all supported platforms without building foreign
      # packages or moving the desktop closure to another builder.
      results = builtins.listToAttrs (
        map
          (system: {
            name = system;
            value = import ../../tests/nix/temporary-fixes.nix {
              inherit inputs;
              pkgs = import inputs.nixpkgs {
                inherit system;
                config.allowUnfree = true;
              };
            };
          })
          [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
          ]
      );
    in
    {
      checks.temporary-package-fixes = builtins.deepSeq results (
        pkgs.runCommand "temporary-package-fixes" { } ''
          touch "$out"
        ''
      );
    };
}
