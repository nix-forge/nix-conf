_: {
  reason = "nix-output-monitor 2.2.0 builds large dependency graphs with quadratic root removal.";
  upstream = "https://github.com/maralorn/nix-output-monitor/pull/304";
  removal = "Upstream merges PR #304 and Nixpkgs packages a release containing it.";
  reviewedRevision = "b1b875982b17dabde9b4a37f3e229e74913e6db3";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "2.2.0";
    until = "2.2.1";
  };
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/nom-quadratic-build-plan.patch ];
    });
}
