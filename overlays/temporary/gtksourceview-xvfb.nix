{ lib, ... }: {
  reason = "Xvfb resets between GTK test clients and races the next client.";
  upstream = "https://github.com/NixOS/nixpkgs";
  removal = "The upstream check keeps Xvfb alive between test clients.";
  reviewedRevision = "4975466d324710c576dc11ad614684e6bd8cad8e";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      checkPhase =
        assert lib.assertMsg (lib.hasInfix "xvfb-run -s '" old.checkPhase)
          "gtksourceview-xvfb: upstream checkPhase changed; review the temporary fix";
        lib.replaceStrings [ "xvfb-run -s '" ] [ "xvfb-run -s '-noreset " ] old.checkPhase;
    });
}
