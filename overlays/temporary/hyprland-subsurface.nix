_: {
  reason = "Subsurface teardown can dereference an expired parent.";
  upstream = "https://github.com/hyprwm/Hyprland";
  removal = "The pinned source handles parent-first teardown and passes the local subsurface reproduction.";
  reviewedRevision = "f05d73f35795ded80d7e1264a37e41b461625f9f";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprland-subsurface-parent-lifetime.patch ];
    });
}
