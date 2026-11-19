_: {
  reason = "Rejected session-lock acquisition must dispose of GL resources before exit callbacks release the context.";
  upstream = "https://github.com/hyprwm/hyprlock";
  removal = "The selected upstream passes the rejected-lock GL lifetime witness and the complete authentication lifecycle without this repair.";
  reviewedRevision = "5e57c4b451d36db0d5a830b08c55891ab7c9c5ae";
  inputPath = [ "hyprlock" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hyprlock-graphics-cleanup.patch ];
    });
}
