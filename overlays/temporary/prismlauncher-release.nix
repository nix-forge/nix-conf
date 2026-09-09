{ pkgs, ... }: {
  reason = "The selected Nixpkgs package predates the locally selected PrismLauncher 11.1.0 release.";
  upstream = "https://github.com/PrismLauncher/PrismLauncher/releases/tag/11.1.0";
  removal = "Nixpkgs provides PrismLauncher 11.1.0 or later.";
  reviewedRevision = "c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "11.0.3";
    until = "11.1.0";
  };
  apply =
    package:
    package.overrideAttrs (_: {
      version = "11.1.0";
      src = pkgs.fetchFromGitHub {
        owner = "PrismLauncher";
        repo = "PrismLauncher";
        tag = "11.1.0";
        hash = "sha256-bt2ofUj4PXWKNmdACMpXtbVWdNz1aBOUTrPnOsM7NCA=";
      };
    });
}
