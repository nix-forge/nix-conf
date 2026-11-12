{ lib, pkgs, ... }:
let
  repairPatch = builtins.path {
    path = ./patches/hyprshell-full-workspace-identity.patch;
    name = "hyprshell-full-workspace-identity.patch";
  };
in
{
  reason = "Hyprland's current workspace and client schema requires complete named and special workspace identity when collecting and dispatching switcher selections.";
  upstream = "https://github.com/H3rmt/hyprshell/blob/v4.10.8/dep-crates/hyprland-rs/src/data/regular.rs";
  removal = "The unmodified Hyprshell release preserves numbered, named and special workspace identity, rejects unsupported selectors before IPC, and passes the parser, dispatch, wire-contract and live modifier/identity regressions.";
  reviewedRevision = "f389f008228d51fa48bdd69a4c9e2b91f24bb2da";
  inputPath = [ "hyprland" ];
  affectedVersions = {
    from = "4.10.8";
    until = "4.10.9";
  };
  apply =
    package:
    assert lib.assertMsg (
      (package.src.hash or package.src.outputHash or null)
      == "sha256-GXegc0W2xiRuSCjMpVc5mmKP5YFCYn87M/POTalISCA="
    ) "Temporary upstream fix 'hyprshell-workspace-identity' needs review: source changed.";
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ repairPatch ];
      doCheck = true;
      postCheck =
        (old.postCheck or "")
        + ((import ../../lib/templates/text.nix) ./scripts/check-hyprshell-workspace-identity.sh {
          rustTarget = pkgs.stdenv.hostPlatform.rust.rustcTarget;
        });
    });
}
