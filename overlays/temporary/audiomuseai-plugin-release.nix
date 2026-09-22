{ pkgs, lib, ... }: {
  reason = "The selected Nixpkgs package predates AudioMuse-AI Navidrome plugin v10.";
  upstream = "https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/releases/tag/v10";
  removal = "Nixpkgs provides AudioMuse-AI Navidrome plugin v10 or later.";
  reviewedRevision = "44a91898084f46797b5fac650c7e8c9ac38c43d4";
  inputPath = [ "nixpkgs" ];
  packageName = "navidromePlugins.audiomuseai";
  affectedVersions = {
    from = "8";
    until = "10";
  };
  appliesTo = package: lib.versionOlder package.version "10";
  apply =
    package:
    package.overrideAttrs (
      _finalAttrs: _previousAttrs: {
        version = "10";
        src = pkgs.fetchFromGitHub {
          owner = "NeptuneHub";
          repo = "AudioMuse-AI-NV-plugin";
          tag = "v10";
          hash = "sha256-nsutpiatfjwg3cruzz8Np6xEFm78Ea64B2e3zmaZu40=";
        };
        vendorHash = "sha256-mXes+doBSa5kcfHp1cuzTz30wnyyPN7NLC0iOSL8FDo=";
      }
    );
}
