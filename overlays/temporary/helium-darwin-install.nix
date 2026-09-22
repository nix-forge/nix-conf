{ lib, ... }: {
  reason = "The Darwin installer copies the extracted Helium.app into another Helium.app directory.";
  upstream = "https://github.com/schembriaiden/helium-browser-nix-flake";
  removal = "The upstream Darwin package installs Helium.app at Applications/Helium.app and builds unmodified.";
  reviewedRevision = "3e2ae244e94de0309b2c33c36a137722b87386e5";
  inputPath = [ "helium-browser-darwin" ];
  apply =
    package:
    package.overrideAttrs (old: {
      installPhase =
        let
          original = old.installPhase;
          brokenCopy = "cp -r . $out/Applications/Helium.app";
        in
        assert lib.hasInfix brokenCopy original;
        lib.replaceStrings [ brokenCopy ] [ ''cp -R Helium.app/. "$out/Applications/Helium.app/"'' ]
          original;
    });
}
