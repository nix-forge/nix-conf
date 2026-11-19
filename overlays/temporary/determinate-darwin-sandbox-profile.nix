_: {
  reason = "Seatbelt folds the Darwin build input rules into a pattern table that exceeds its 65,535-byte limit on large closures.";
  upstream = "https://github.com/NixOS/nix/commit/f566910ee81fbb76d075712c761a6be1d733e1a8";
  removal = "Determinate Nix includes the upstream prefix bucketing fix and builds the Darwin Home Manager closure in the sandbox.";
  reviewedRevision = "f43bee4f45c2d42e7d1f4e37908ec5c7bb0fdba1";
  inputPath = [
    "determinate"
    "inputs"
    "nix"
  ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/determinate-darwin-sandbox-profile.patch ];
    });
}
