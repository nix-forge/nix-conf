_: {
  reason = "Subsurface teardown can dereference an expired parent.";
  upstream = "https://github.com/hyprwm/Hyprland";
  removal = "The pinned source handles parent-first teardown and passes the local subsurface reproduction.";
  reviewedRevision = "76edafffc68951a66b094806659ac4823e22c624";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      # Keep unrelated repository edits out of the native package source hash.
      patches = (old.patches or [ ]) ++ [
        (builtins.path {
          path = ./patches/hyprland-subsurface-parent-lifetime.patch;
          name = "hyprland-subsurface-parent-lifetime.patch";
        })
      ];
    });
}
