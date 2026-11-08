_: {
  reason = "nix-output-monitor rejects Determinate Nix named activities (type 10113) as invalid JSON events.";
  upstream = "https://github.com/DeterminateSystems/nix-src/blob/1ef903401b3426fbca74a692e158cca82d7c98ab/src/libutil/include/nix/util/logging.hh";
  removal = "The packaged monitor accepts named activity type 10113 without losing legacy activity parsing or malformed-input diagnostics.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "2.2.0";
    until = "2.2.1";
  };
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/nom-named-activities.patch
        ./patches/nom-named-activities-tests.patch
      ];
    });
}
