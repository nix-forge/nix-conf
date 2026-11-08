{ pkgs }:
pkgs.buildNpmPackage {
  pname = "repository-javascript-tools";
  version = "1";
  src = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../package.json
      ../../package-lock.json
    ];
  };
  nodejs = pkgs.nodejs_24;
  npmDepsHash = "sha256-mL/LnV2s4iD5fR8tgmgEgbpTpmu6Gjt4vK4uLvbT810=";
  dontNpmBuild = true;
  dontNpmInstall = true;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  installPhase = (import ../../lib/templates/text.nix) ./scripts/javascript-tools-install.sh.in {
    node = pkgs.lib.getExe pkgs.nodejs_24;
  };
  meta.mainProgram = "oxlint";
}
