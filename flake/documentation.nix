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
          ../docs/assets/font-implementation/pango.png
          ../docs/assets/font-implementation/qt.png
          ../templates/starter
        ];
      };
    in
    {
      packages.documentation = pkgs.runCommand "nix-conf-guide" { nativeBuildInputs = [ python ]; } ''
        python ${source}/site/build.py --source ${source} --output "$out" \
          --catalog ${config.packages.feature-catalog} \
          --options ${config.packages.feature-options}/share/doc/nixos/options.json
        test -s "$out/index.html"
        test -s "$out/search/search_index.json"
      '';
      checks.documentation = config.packages.documentation;
      devShells.docs = pkgs.mkShellNoCC { packages = [ python ]; };
    };
}
