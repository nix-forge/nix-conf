_: {
  reason = "Rejected session-lock acquisition must dispose of GL resources before exit callbacks release the context.";
  upstream = "https://github.com/hyprwm/hyprlock";
  removal = "The selected upstream passes the rejected-lock GL lifetime witness and the complete authentication lifecycle without this repair.";
  reviewedRevision = "73969a083e28f5c58428c7239f7b44c32e5fe996";
  inputPath = [ "hyprlock" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprlock-graphics-cleanup.patch ];
    });
}
