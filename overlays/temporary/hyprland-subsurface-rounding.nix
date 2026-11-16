_: {
  reason = "Native hover UI inherits a radius around each subsurface instead of the window geometry.";
  upstream = "https://github.com/hyprwm/Hyprland/discussions/12554";
  removal = "The pinned renderer preserves interior child shapes and passes the isolated surface-tree corner and overlap regression.";
  reviewedRevision = "a1d7a78b6c8e54ad72d401bfa8b85fdc89ee66a6";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprland-subsurface-rounding.patch ];
    });
}
