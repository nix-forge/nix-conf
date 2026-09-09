{ lib, ... }: {
  reason = "Determinate's NixOS module must receive its Nix input with the temporary Sentry report-lock repair.";
  upstream = "https://github.com/DeterminateSystems/determinate/blob/cb76ac22754f6b36c008a3c39477c174a146dd6b/modules/nixos.nix";
  removal = "Determinate's unmodified Nix input passes the Sentry report-lock checks; retire the module replacement in overlays/inputs.nix.";
  reviewedRevision = "cb76ac22754f6b36c008a3c39477c174a146dd6b";
  inputPath = [ "determinate" ];
  apply =
    determinate:
    { pkgs, ... }:
    let
      fixes = import ./default.nix {
        inherit pkgs lib;
        inputs = { inherit determinate; };
      };
      patchPackages =
        _: packages:
        let
          # Use Determinate's actual dependency, including its curl customization.
          sentry =
            (lib.findSingle (p: (p.pname or "") == "sentry-native")
              (throw "Determinate Nix no longer selects Sentry; review sentry-crashpad-lock")
              (throw "Determinate Nix selects multiple Sentry dependencies; review sentry-crashpad-lock")
              packages.nix-cli.buildInputs
            ).out;
          # Restore output selection so Nix gets both headers and runtime libraries.
          patchedSentry = (fixes.apply "sentry-crashpad-lock" sentry) // {
            outputSpecified = false;
          };
        in
        packages
        // {
          default =
            (packages.default.overrideScope (_: _: { sentry-native = patchedSentry; })).overrideAttrs
              (old: {
                passthru = (old.passthru or { }) // {
                  tests = (old.passthru.tests or { }) // {
                    crashpad-lock = patchedSentry.tests.crashpad-lock;
                    crashpad-lock-upstream = import ./tests/crashpad-lock.nix { inherit (pkgs) python3; } sentry;
                  };
                };
              });
        };
      moduleInputs = determinate.inputs // {
        self = determinate;
        nix = determinate.inputs.nix // {
          packages = lib.mapAttrs patchPackages determinate.inputs.nix.packages;
        };
      };
    in
    {
      # Reapply the upstream module factory with the repaired input. The module
      # remains the sole owner of nix.package and Determinate Nixd's --nix-bin.
      imports = [ (import (determinate + "/modules/nixos.nix") moduleInputs) ];
    };
}
