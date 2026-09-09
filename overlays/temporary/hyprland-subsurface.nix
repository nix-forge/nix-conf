_: {
  reason = "Subsurface teardown can dereference an expired parent.";
  upstream = "https://github.com/hyprwm/Hyprland";
  removal = "The pinned source handles parent-first teardown and passes the local subsurface reproduction.";
  reviewedRevision = "34eb03bd8da01024596c367fba66485a8c9b8ca7";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprland-subsurface-parent-lifetime.patch ];
    });
}
