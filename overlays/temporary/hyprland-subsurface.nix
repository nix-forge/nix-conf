_: {
  reason = "Subsurface teardown can dereference an expired parent.";
  upstream = "https://github.com/hyprwm/Hyprland";
  removal = "The pinned source handles parent-first teardown and passes the local subsurface reproduction.";
  reviewedRevision = "c6e668757d9ac136586e47e3bc07384e432b67f1";
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
