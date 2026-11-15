_: {
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      python = pkgs.python3.withPackages (ps: [
        ps.mkdocs
        ps.pygments
      ]);
      source = lib.fileset.toSource {
        root = ../.;
        fileset = lib.fileset.unions [
          ../site
          ../docs/README.md
          ../docs/guide
          ../docs/openssf-baseline.md
          ../docs/slsa.md
          ../docs/dependency-management.md
          ../docs/secret-management.md
          ../docs/assets/font-implementation/pango.png
          ../docs/assets/font-implementation/qt.png
          ../THREAT_MODEL.md
          ../templates/starter
        ];
      };
    in
    {
      packages.documentation = pkgs.runCommand "nix-conf-guide" { nativeBuildInputs = [ python ]; } (
        (import ../lib/templates/text.nix) ./scripts/nix-conf-guide.sh {
          inherit source;
          config_packages_feature_catalog = config.packages.feature-catalog;
          config_packages_feature_options = config.packages.feature-options;
        }
      );
      checks.documentation = config.packages.documentation;
      devShells.docs = pkgs.mkShellNoCC { packages = [ python ]; };
    };
}
