{ lib, pkgs, ... }:
let
  inherit (pkgs) nixf;
  nixExpr = lib.findSingle (input: lib.getName input == "nix-expr") null null nixf.buildInputs;
  nixFlake = pkgs.nixVersions.latest.libs.nix-flake;
  patch = builtins.path {
    path = ./patches/nixf-flake-builtins.patch;
    name = "nixf-flake-builtins.patch";
  };
  repairedNixf =
    assert lib.assertMsg (
      nixf.version == "2.9.3"
      &&
        (nixf.src.hash or nixf.src.outputHash or null)
        == "sha256-ud2XcAxUUYenNrGyrh4B9LrDcMZ6eJfPkL60lDcanDI="
    ) "Temporary upstream fix 'nixf-flake-builtins' needs review: frontend source changed.";
    assert lib.assertMsg (
      nixExpr != null && nixExpr.version == "2.35.3" && nixFlake.version == nixExpr.version
    ) "Temporary upstream fix 'nixf-flake-builtins' needs review: owning Nix libraries changed.";
    nixf.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ patch ];
      patchFlags = [
        "-p1"
        "--fuzz=0"
      ];
      buildInputs = old.buildInputs ++ [ nixFlake ];
      postPatch =
        (old.postPatch or "")
        + ((import ../../lib/templates/text.nix) ./scripts/prepare-nixf-flake-header.sh {
          sourceHeader = lib.escapeShellArg "${nixFlake.src}/src/libflake/include/nix/flake/flake-primops.hh";
          sourceHeaderSHA256 = "c97ba016d8e08f7168a750133c7e91726b1f85febd4a5fbe6fd504b122bfda1b";
          sha256sum = lib.getExe' pkgs.coreutils "sha256sum";
          install = lib.getExe' pkgs.coreutils "install";
        });
    });
in
{
  reason = "nixf's expression-only builtin table omits the supported flake primops and rejects valid getFlake calls.";
  upstream = "https://github.com/nix-community/nixd/issues/762";
  removal = "The unmodified nixf frontend registers the selected Nix flake primop metadata and passes the valid-flake and unknown-builtin install checks.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "0.1.4";
    until = "0.1.5";
  };
  apply =
    package:
    assert lib.assertMsg (
      (package.src.hash or package.src.outputHash or null)
      == "sha256-vHW2AnUxBuG9mlpMB0f9eK4M1VlJPm5YtwjXksx/uik="
    ) "Temporary upstream fix 'nixf-flake-builtins' needs review: diagnostic wrapper source changed.";
    (package.override { nixf = repairedNixf; }).overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        nixfFlakeFrontend = repairedNixf;
      };
      doInstallCheck = true;
      postInstallCheck =
        (old.postInstallCheck or "")
        + ((import ../../lib/templates/text.nix) ./scripts/check-nixf-flake-builtins.sh {
          grep = lib.getExe pkgs.gnugrep;
        });
    });
}
