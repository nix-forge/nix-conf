{ lib, pkgs, ... }: {
  reason = "Azure CLI dependencies need hermetic, deterministic Darwin tests.";
  upstream = "https://github.com/NixOS/nixpkgs/tree/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs/by-name/az/azure-cli";
  removal = "The selected Azure CLI dependencies permit local networking where needed and their HTTPX2 timeout fixture has deterministic teardown on Darwin.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    let
      fixPython =
        _: previous:
        (lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          # sshtunnel's upstream tests bind and connect real loopback SSH sockets.
          # Like Paramiko's recipe, retain the sandbox and grant only local networking.
          # https://github.com/pahaz/sshtunnel/blob/0.4.0/tests/test_forwarder.py
          sshtunnel = previous.sshtunnel.overridePythonAttrs { __darwinAllowLocalNetworking = true; };
          # The Requests integration tests start a real loopback HTTP server.
          opentelemetry-instrumentation-requests =
            previous.opentelemetry-instrumentation-requests.overridePythonAttrs
              { __darwinAllowLocalNetworking = true; };
          # Keep the mock connection open until close() instead of racing a
          # 0.1-second receive timeout against EOF after a 0.2-second sleep.
          # https://github.com/pydantic/httpx2/blob/v2.13.1/tests/httpx2/websockets/test_api.py
          httpx2 = previous.httpx2.overridePythonAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./patches/httpx2-timeout-fixture.patch ];
          });
        });
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
