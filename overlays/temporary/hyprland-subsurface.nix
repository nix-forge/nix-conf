_: {
  reason = "Subsurface teardown can dereference an expired parent.";
  upstream = "https://github.com/hyprwm/Hyprland";
  removal = "The pinned source handles parent-first teardown and passes the local subsurface reproduction.";
  reviewedRevision = "663b29b846e4bad17cfa29941f6d2fbb6b61f139";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprland-subsurface-parent-lifetime.patch ];
    });
}
