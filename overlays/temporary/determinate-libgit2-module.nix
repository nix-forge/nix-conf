{ lib, ... }: {
  reason = "Determinate's NixOS module must receive its owning Nix input with the libgit2 cleanup repair.";
  upstream = "https://github.com/DeterminateSystems/determinate/blob/35e914102d4992b10bac4c12e94ec606d109633d/modules/nixos.nix";
  removal = "The unmodified owning libgit2 passes symlink cleanup regressions and complete native main and utility suites.";
  reviewedRevision = "558e026d9d3c78351170d8f8a797fa0fac541ccf";
  inputPath = [ "determinate" ];
  apply =
    determinate: _:
    let
      patchPackages =
        system: packages:
        let
          owningPkgs = import determinate.inputs.nix.inputs.nixpkgs {
            localSystem = { inherit system; };
            overlays = [ determinate.inputs.nix.overlays.internal ];
          };
          owningFixes = import ./default.nix {
            pkgs = owningPkgs;
            inputs = { inherit determinate; };
          };
          repairedLibgit2 = owningFixes.apply "determinate-libgit2-trailing-slash" owningPkgs.nixDependencies2.libgit2;
        in
        assert owningPkgs.nixComponents2.nix-everything.drvPath == packages.default.drvPath;
        packages // { default = packages.default.overrideScope (_: _: { libgit2 = repairedLibgit2; }); };
      moduleInputs = determinate.inputs // {
        self = determinate;
        nix = determinate.inputs.nix // {
          packages = lib.mapAttrs patchPackages determinate.inputs.nix.packages;
        };
      };
    in
    {
      # Retain module factory routing for the remaining libgit2 repair.
      # Reapply the upstream module factory with the repaired input. The module
      # remains the sole owner of nix.package and Determinate Nixd's --nix-bin.
      imports = [ (import (determinate + "/modules/nixos.nix") moduleInputs) ];
    };
}
