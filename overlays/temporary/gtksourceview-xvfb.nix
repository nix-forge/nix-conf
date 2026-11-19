{ lib, ... }: {
  reason = "Xvfb resets between GTK test clients and races the next client.";
  upstream = "https://github.com/NixOS/nixpkgs/pull/566623";
  removal = "The upstream check keeps Xvfb alive between test clients.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      checkPhase =
        if !(lib.hasInfix "xvfb-run -s '" old.checkPhase) then
          throw "gtksourceview-xvfb: upstream checkPhase changed; review the temporary fix"
        else
          lib.replaceStrings [ "xvfb-run -s '" ] [ "xvfb-run -s '-noreset " ] old.checkPhase;
    });
}
