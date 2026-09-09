{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  guard = import ../../overlays/temporary/guard.nix { inherit lib; };
  fixture = {
    name = "fixture";
    reason = "Regression in the fixture package";
    upstream = "https://example.invalid/fixture";
    removal = "The fixed release is packaged";
    reviewedRevision = "reviewed";
    affectedVersions = {
      from = "1.2";
      until = "1.4";
    };
  };
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  accepts = version: succeeds (guard fixture "reviewed" { inherit version; });
  fixes = import ../../overlays/temporary { inherit pkgs inputs; };
  changed = import ../../overlays/temporary {
    inherit pkgs;
    inputs = inputs // {
      nixpkgs = inputs.nixpkgs // {
        rev = "unreviewed";
      };
    };
  };
  moduleFixes = import ../../overlays/temporary { inherit lib inputs; };
  changedStylix = import ../../overlays/temporary {
    inherit pkgs;
    inputs = inputs // {
      stylix = inputs.stylix // {
        rev = "unreviewed";
      };
    };
  };
  release = fixes.apply "prismlauncher-release" pkgs.prismlauncher-unwrapped;
  overlay = import ../../overlays { inherit inputs; };
  selected = pkgs.extend overlay;
  nhAt =
    version:
    pkgs.nh-unwrapped.overrideAttrs {
      inherit version;
      __intentionallyOverridingVersion = true;
    };
  nhFixed = nhAt "4.4.3";
  nhUpdated = import ../../overlays/temporary {
    pkgs = pkgs // {
      nh-unwrapped = nhFixed;
    };
    inputs = inputs // {
      nixpkgs = inputs.nixpkgs // {
        rev = "unreviewed";
      };
    };
  };
  # Exercise the public selection interface and its module consumers.
  packages = {
    prism = (import ../../modules/home/prismlauncher.nix { pkgs = selected; }).home.packages;
    claude = (import ../../modules/home/dev/agentic-tui/claude.nix { pkgs = selected; }).home.packages;
    deploy = [ selected.deploy-rs ];
    determinate = [ selected.nix ];
    nh = [ selected.nh ];
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    hyprshell = [ selected.hyprshell ];
    virt-manager = [ selected.virt-manager ];
    grimblast = [ selected.grimblast-region ];
    hyprland = [ selected.hyprland ];
    portal = [ selected.xdg-desktop-portal-hyprland ];
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin { actual = [ selected.actual-server ]; };
  derivations = lib.mapAttrs (_: map (p: p.drvPath)) packages;
in
assert accepts "1.2";
assert accepts "1.3.9";
assert !(accepts "1.1.9");
assert !(accepts "1.4");
assert !(accepts "2.0");
assert !(succeeds (guard fixture "unreviewed" { version = "1.3"; }));
assert !(succeeds (guard fixture "reviewed" { }));
assert !(succeeds (guard (fixture // { reason = ""; }) "reviewed" { version = "1.3"; }));
assert
  !(succeeds (
    guard (
      fixture
      // {
        affectedVersions = {
          from = "2";
          until = "1";
        };
      }
    ) "reviewed" { }
  ));
assert
  !(succeeds (
    guard (
      fixture
      // {
        affectedVersions = {
          from = "1";
        };
      }
    ) "reviewed" { }
  ));
assert succeeds (guard (fixture // { affectedVersions = null; }) "reviewed" { });
# The registry checks disabled fixes without depending on lazy module consumers.
assert !(succeeds changed.review);
assert !(succeeds changedStylix.review);
assert !(succeeds (changedStylix.apply "stylix-nvf" inputs.stylix));
assert succeeds (moduleFixes.apply "stylix-nvf" inputs.stylix);
# Platform decisions belong to the selection interface. Linux keeps the
# upstream Claude Code and deploy-rs derivations and their check settings.
assert
  pkgs.stdenv.hostPlatform.isDarwin || selected.claude-code.drvPath == pkgs.claude-code.drvPath;
assert
  pkgs.stdenv.hostPlatform.isDarwin
  ||
    selected.deploy-rs.drvPath
    == inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default.drvPath;
assert pkgs.stdenv.hostPlatform.isLinux || !(overlay selected pkgs ? hyprland);
assert pkgs.stdenv.hostPlatform.isDarwin || selected.nh.drvPath == pkgs.nh.drvPath;
# Later nh versions must bypass both the patch and this fix's revision review.
assert (fixes.apply "nh-darwin-home" (nhAt "4.4.2")).drvPath != (nhAt "4.4.2").drvPath;
assert builtins.all
  (version: (fixes.apply "nh-darwin-home" (nhAt version)).drvPath == (nhAt version).drvPath)
  [
    "4.4.3"
    "4.5.0"
    "5.0.0"
  ];
assert (changed.apply "nh-darwin-home" nhFixed).drvPath == nhFixed.drvPath;
assert !(succeeds (changed.apply "nh-darwin-home" (nhAt "4.4.2")).drvPath);
assert !(succeeds changed.review.nh-darwin-home);
assert succeeds nhUpdated.review.nh-darwin-home;
# A fix that changes the output version still checks the incoming version.
assert release.version == "11.1.0";
assert
  !(succeeds
    (fixes.apply "prismlauncher-release" (
      pkgs.prismlauncher-unwrapped.overrideAttrs {
        version = "11.1.0";
        __intentionallyOverridingVersion = true;
      }
    )).drvPath
  );
builtins.deepSeq fixes.review (
  builtins.deepSeq derivations {
    registry = fixes.review;
    inherit derivations;
  }
)
