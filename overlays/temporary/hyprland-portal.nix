_: {
  reason = "The pinned portal has compiler-specific flags, an unused counter, and an invalid cast.";
  upstream = "https://github.com/hyprwm/xdg-desktop-portal-hyprland";
  removal = "The portal selected by the Hyprland input builds with GCC without these changes.";
  reviewedRevision = "ba31964ee42b56bcb0d3b78a64ead5d8a1c3c6f6";
  inputPath = [
    "hyprland"
    "inputs"
    "xdph"
  ];
  apply =
    package:
    package.overrideAttrs (old: {
      # Keep unrelated repository edits out of the native package source hash.
      patches = (old.patches or [ ]) ++ [
        (builtins.path {
          path = ./patches/hyprland-portal-compiler-warnings.patch;
          name = "hyprland-portal-compiler-warnings.patch";
        })
      ];
    });
}
