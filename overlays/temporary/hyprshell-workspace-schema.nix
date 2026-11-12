_: {
  reason = "Hyprland 0.56 omits the id of an inactive special workspace, which Hyprshell requires when reading monitor data.";
  upstream = "https://github.com/H3rmt/hyprshell/pull/525";
  removal = "The pinned Hyprshell release parses Hyprland's monitor data without this patch and the live Alt+Tab check passes.";
  reviewedRevision = "f389f008228d51fa48bdd69a4c9e2b91f24bb2da";
  inputPath = [ "hyprland" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprshell-empty-special-workspace.patch ];
    });
}
