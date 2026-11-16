_: {
  reason = "Hyprland 0.56 omits the id of an inactive special workspace, which Hyprshell requires when reading monitor data.";
  upstream = "https://github.com/H3rmt/hyprshell/pull/525";
  removal = "The pinned Hyprshell release parses Hyprland's monitor data without this patch and the live Alt+Tab check passes.";
  # The candidate preserves monitor/workspace IPC fields and default focus dispatch.
  reviewedRevision = "a1d7a78b6c8e54ad72d401bfa8b85fdc89ee66a6";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprshell-empty-special-workspace.patch ];
    });
}
