_: {
  reason = "Functional tests need networking and Crashpad Mach ports denied by the Darwin sandbox.";
  upstream = "https://github.com/DeterminateSystems/nix";
  removal = "The functional tests pass in the strict Darwin sandbox.";
  reviewedRevision = "3ed5caa3bbde51ab87977c8a80e27c6ed0ea8534";
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
