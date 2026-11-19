_: {
  reason = "Native hover UI inherits a radius around each subsurface instead of the window geometry.";
  upstream = "https://github.com/hyprwm/Hyprland/discussions/12554";
  removal = "The pinned renderer preserves interior child shapes and passes the isolated surface-tree corner and overlap regression.";
  reviewedRevision = "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprland-subsurface-rounding.patch ];
    });
}
