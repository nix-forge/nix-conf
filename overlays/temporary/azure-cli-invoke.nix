{ lib, pkgs, ... }: {
  reason = "Azure CLI needs compatible Invoke and hermetic, deterministic Darwin dependency tests.";
  upstream = "https://github.com/fabric/fabric/issues/2376";
  removal = "The selected Azure CLI dependencies supply compatible Fabric/Invoke and hermetic, deterministic Darwin tests.";
  reviewedRevision = "1d060086d60cb76a40cf37109f979d88a5bd6396";
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
