_: {
  reason = "Native hover UI inherits a radius around each subsurface instead of the window geometry.";
  upstream = "https://github.com/hyprwm/Hyprland/discussions/12554";
  removal = "The pinned renderer preserves interior child shapes and passes the isolated surface-tree corner and overlap regression.";
  reviewedRevision = "f389f008228d51fa48bdd69a4c9e2b91f24bb2da";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprland-subsurface-rounding.patch ];
    });
}
