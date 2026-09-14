{ pkgs, lib, ... }: {
  reason = "Navidrome 0.64.0 fixes several security defects present in the selected Nixpkgs release.";
  upstream = "https://github.com/navidrome/navidrome/releases/tag/v0.64.0";
  removal = "Nixpkgs provides a non-broken Navidrome 0.64.0 or later.";
  reviewedRevision = "8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe";
  inputPath = [ "nixpkgs" ];
  packageName = "navidrome";
  affectedVersions = {
    from = "0.63.2";
    until = "0.64.0";
  };
  appliesTo = package: lib.versionOlder package.version "0.64.0" || (package.meta.broken or false);
  apply =
    package:
    (package.override { buildGoModule = pkgs.buildGo127Module; }).overrideAttrs (
      finalAttrs: _: {
        version = "0.64.0";
        src = pkgs.fetchFromGitHub {
          owner = "navidrome";
          repo = "navidrome";
          rev = "v${finalAttrs.version}";
          hash = "sha256-2GUAGuwVE3i49g/mGN3zd1J1y9jVhF0g4hKGceSQwD8=";
        };
        vendorHash = "sha256-1aKih0Xl5OfV4IO/2E0S31rHhRx356zl2QPM96jcFco=";
        npmDeps = pkgs.fetchNpmDeps {
          inherit (finalAttrs) src;
          sourceRoot = "${finalAttrs.src.name}/ui";
          hash = "sha256-uRF9cf6HZE0gyCvGTEZ520d2gMsxmccEYLJBgc47pMg=";
        };
      }
    );
}
