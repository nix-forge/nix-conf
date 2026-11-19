_: {
  reason = "Modifier release can arrive before the switcher opens.";
  upstream = "https://github.com/H3rmt/hyprshell/pull/521";
  removal = "The pinned release passes the local Alt+Tab release and cancellation reproductions.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprshell-modifier-state.patch ];
    });
}
