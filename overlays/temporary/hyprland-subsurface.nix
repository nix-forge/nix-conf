_: {
  reason = "Mapped subsurface size can dereference a disposed surface resource.";
  upstream = "https://github.com/hyprwm/Hyprland";
  removal = "The unmodified size accessor handles disposed resources and passes mapped parent-first teardown, damage and shutdown checks.";
  reviewedRevision = "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947";
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
