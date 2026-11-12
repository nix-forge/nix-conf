{ pkgs, ... }: {
  reason = "Handy 0.9.6 changes its Mach-O rpath after signing and leaves the app resource seal invalid.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/by-name/ha/handy/package.nix";
  removal = "Unmodified Handy passes Apple's strict deep signature verification after packaging and launches with microphone permission.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "0.9.6";
    until = "0.9.7";
  };
  packageName = "handy";
  appliesTo = package: package.version == "0.9.6";
  apply =
    package:
    pkgs.runCommand "handy-${package.version}-sealed" {
      inherit (package) meta;
      passthru = (package.passthru or { }) // {
        inherit (package) version;
      };
      nativeBuildInputs = [ pkgs.rcodesign ];
      unsealed = package;
    } (builtins.readFile ./scripts/seal-handy.sh);
}
