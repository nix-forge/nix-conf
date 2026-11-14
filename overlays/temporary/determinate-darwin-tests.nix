{ lib, ... }: {
  reason = "The Sentry crashdump test needs Crashpad Mach ports denied by the Darwin sandbox.";
  upstream = "https://github.com/DeterminateSystems/nix";
  removal = "The Sentry crashdump case passes in the strict Darwin sandbox.";
  reviewedRevision = "f43bee4f45c2d42e7d1f4e37908ec5c7bb0fdba1";
  inputPath = [
    "determinate"
    "inputs"
    "nix"
  ];
  apply =
    package:
    let
      # stdenv consumes checkInputs into the effective build dependency graph.
      functional =
        lib.findSingle (check: lib.getName check == "nix-functional-tests")
          (throw "Determinate Nix has no functional gate; review the Darwin Sentry fix")
          (throw "Determinate Nix has multiple functional gates; review the Darwin Sentry fix")
          package.buildInputs;
    in
    assert package.doCheck;
    assert builtins.length package.buildInputs == 6;
    assert functional.doCheck;
    builtins.seq functional (
      package.override {
        nix-functional-tests = functional.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./patches/determinate-darwin-sentry-registration.patch ];
        });
      }
    );
}
