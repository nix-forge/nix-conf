_: {
  reason = "nix-output-monitor 2.2.0 builds large dependency graphs with quadratic root removal.";
  upstream = "https://github.com/maralorn/nix-output-monitor/pull/304";
  removal = "Upstream merges PR #304 and Nixpkgs packages a release containing it.";
  reviewedRevision = "4975466d324710c576dc11ad614684e6bd8cad8e";
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
