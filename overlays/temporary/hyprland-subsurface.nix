_: {
  reason = "Subsurface teardown can dereference an expired parent.";
  upstream = "https://github.com/hyprwm/Hyprland";
  removal = "The pinned source handles parent-first teardown and passes the local subsurface reproduction.";
  reviewedRevision = "9dc5398d14a090b4d2e69380ad22d2410ba10090";
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
