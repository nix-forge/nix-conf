{ lib, pkgs, ... }: {
  reason = "Azure CLI selects Fabric 3.2.3, which requires Invoke below version 3.";
  upstream = "https://github.com/fabric/fabric/issues/2376";
  removal = "The selected Azure CLI dependency set supplies a compatible Fabric and Invoke pair.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    let
      pinInvoke = _: previous: {
        invoke = previous.invoke.overridePythonAttrs (_: {
          version = "2.2.1";
          src = pkgs.fetchPypi {
            pname = "invoke";
            version = "2.2.1";
            hash = "sha256-UVv0m0pIkyt5sCRZA0jaIvOcSULf+ZGtH7i4uuob5wc=";
          };
        });
      };
      repaired = package.override (arguments: {
        # withExtensions closes over this argument; retain the repair there too.
        azure-cli = repaired;
        callPackage =
          path: args:
          # Compose at the interpreter call: callPackage wraps the returned
          # interpreter's override with the recipe's own arguments.
          arguments.callPackage path (
            args
            // lib.optionalAttrs (baseNameOf path == "python-packages.nix") {
              python3 = args.python3 // {
                override =
                  overrides:
                  args.python3.override (
                    overrides // { packageOverrides = lib.composeExtensions overrides.packageOverrides pinInvoke; }
                  );
              };
            }
          );
      });
    in
    repaired;
}
