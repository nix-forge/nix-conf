_: {
  reason = "Modifier release can arrive before the switcher opens.";
  upstream = "https://github.com/H3rmt/hyprshell";
  removal = "The pinned release passes the local Alt+Tab release and cancellation reproductions.";
  reviewedRevision = "8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe";
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
