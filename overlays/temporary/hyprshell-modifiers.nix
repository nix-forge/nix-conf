_: {
  reason = "Modifier release can arrive before the switcher opens.";
  upstream = "https://github.com/H3rmt/hyprshell/pull/521";
  removal = "The pinned release passes the local Alt+Tab release and cancellation reproductions.";
  reviewedRevision = "1d060086d60cb76a40cf37109f979d88a5bd6396";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprshell-modifier-state.patch ];
      cargoTestFlags = [
        "--package"
        "hyprshell-windows-lib"
        "event_time_tests"
      ];
    });
}
