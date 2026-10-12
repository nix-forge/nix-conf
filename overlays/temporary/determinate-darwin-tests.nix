{ lib, ... }: {
  reason = "The Sentry crashdump test needs Crashpad Mach ports denied by the Darwin sandbox.";
  upstream = "https://github.com/DeterminateSystems/nix";
  removal = "The Sentry crashdump case passes in the strict Darwin sandbox.";
  reviewedRevision = "8bb6b35147841a45b6dead93fc98339798d586f5";
  inputPath = [
    "determinate"
    "inputs"
    "nix"
  ];
  apply =
    package:
    let
      functional =
        lib.findSingle (check: lib.getName check == "nix-functional-tests")
          (throw "Determinate Nix has no functional gate; review the Darwin Sentry fix")
          (throw "Determinate Nix has multiple functional gates; review the Darwin Sentry fix")
          package.checkInputs;
    in
    assert package.doCheck;
    builtins.seq functional (
      package.override {
        nix-functional-tests = functional.overrideAttrs (old: {
          mesonCheckFlags = (old.mesonCheckFlags or [ ]) ++ [
            "--exclude"
            "sentry"
          ];
        });
      }
    );
}
