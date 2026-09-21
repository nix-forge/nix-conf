_: {
  reason = "Modifier release can arrive before the switcher opens.";
  upstream = "https://github.com/H3rmt/hyprshell";
  removal = "The pinned release passes the local Alt+Tab release and cancellation reproductions.";
  reviewedRevision = "b1b875982b17dabde9b4a37f3e229e74913e6db3";
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
