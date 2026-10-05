_: {
  reason = "Functional tests need networking and Crashpad Mach ports denied by the Darwin sandbox.";
  upstream = "https://github.com/DeterminateSystems/nix";
  removal = "The functional tests pass in the strict Darwin sandbox.";
  reviewedRevision = "8bb6b35147841a45b6dead93fc98339798d586f5";
  inputPath = [
    "determinate"
    "inputs"
    "nix"
  ];
  apply =
    package:
    package.overrideAttrs (_: {
      doCheck = false;
    });
}
