{ lib, ... }: {
  reason = "Xvfb resets between GTK test clients and races the next client.";
  upstream = "https://github.com/NixOS/nixpkgs";
  removal = "The upstream check keeps Xvfb alive between test clients.";
  reviewedRevision = "b1b875982b17dabde9b4a37f3e229e74913e6db3";
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
