_: {
  reason = "Native hover UI inherits a radius around each subsurface instead of the window geometry.";
  upstream = "https://github.com/hyprwm/Hyprland/discussions/12554";
  removal = "The pinned renderer preserves interior child shapes and passes the isolated surface-tree corner and overlap regression.";
  reviewedRevision = "76edafffc68951a66b094806659ac4823e22c624";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprland-subsurface-rounding.patch ];
    });
}
