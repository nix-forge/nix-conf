_: {
  reason = "Mapped subsurface size can dereference a disposed surface resource.";
  upstream = "https://github.com/hyprwm/Hyprland";
  removal = "The unmodified size accessor handles disposed resources and passes mapped parent-first teardown, damage and shutdown checks.";
  reviewedRevision = "a1d7a78b6c8e54ad72d401bfa8b85fdc89ee66a6";
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
