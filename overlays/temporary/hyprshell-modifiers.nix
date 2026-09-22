_: {
  reason = "Modifier release can arrive before the switcher opens.";
  upstream = "https://github.com/H3rmt/hyprshell";
  removal = "The pinned release passes the local Alt+Tab release and cancellation reproductions.";
  reviewedRevision = "44a91898084f46797b5fac650c7e8c9ac38c43d4";
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
