_: {
  reason = "Functional tests need networking and Crashpad Mach ports denied by the Darwin sandbox.";
  upstream = "https://github.com/DeterminateSystems/nix";
  removal = "The functional tests pass in the strict Darwin sandbox.";
  reviewedRevision = "6468ca430b298865100b753ec21687aba457a05c";
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
