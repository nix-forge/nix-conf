_: {
  reason = "Hyprland 0.56 omits the id of an inactive special workspace, which Hyprshell requires when reading monitor data.";
  upstream = "https://github.com/H3rmt/hyprshell/pull/525";
  removal = "The pinned Hyprshell release parses Hyprland's monitor data without this patch and the live Alt+Tab check passes.";
  reviewedRevision = "76edafffc68951a66b094806659ac4823e22c624";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprshell-empty-special-workspace.patch ];
    });
}
