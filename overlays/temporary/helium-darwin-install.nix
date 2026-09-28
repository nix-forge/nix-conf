{ lib, ... }: {
  reason = "The Darwin installer copies the extracted Helium.app into another Helium.app directory.";
  upstream = "https://github.com/schembriaiden/helium-browser-nix-flake";
  removal = "The upstream Darwin package installs Helium.app at Applications/Helium.app and builds unmodified.";
  reviewedRevision = "b413a26c70bb354197e34fd2e493508cb8326576";
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
