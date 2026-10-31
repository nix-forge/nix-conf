{ lib, pkgs, ... }: {
  reason = "Azure CLI needs compatible Invoke and local networking for Darwin SSH tunnel tests.";
  upstream = "https://github.com/fabric/fabric/issues/2376";
  removal = "The selected Azure CLI dependencies supply compatible Fabric/Invoke and declare Darwin SSH test networking.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    let
      fixPython =
        _: previous:
        (
          {
            invoke = previous.invoke.overridePythonAttrs (_: {
              version = "2.2.1";
              src = pkgs.fetchPypi {
                pname = "invoke";
                version = "2.2.1";
                hash = "sha256-UVv0m0pIkyt5sCRZA0jaIvOcSULf+ZGtH7i4uuob5wc=";
              };
            });
          }
          // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
            # sshtunnel's upstream tests bind and connect real loopback SSH sockets.
            # Like Paramiko's recipe, retain the sandbox and grant only local networking.
            # https://github.com/pahaz/sshtunnel/blob/0.4.0/tests/test_forwarder.py
            sshtunnel = previous.sshtunnel.overridePythonAttrs { __darwinAllowLocalNetworking = true; };
          }
        );
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
                    overrides // { packageOverrides = lib.composeExtensions overrides.packageOverrides fixPython; }
                  );
              };
            }
          );
      });
    in
    repaired;
}
