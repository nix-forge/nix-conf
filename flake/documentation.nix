{ self, ... }: {
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
      # Only declared public pages enter the site; research stays on GitHub.
      guideRoot = ../docs/guide;
      cell = lib.replaceStrings [ "|" "\n" ] [ "\\|" " " ];
      catalog = self.featureCatalog;
      inherit (catalog) features;
      featureTable =
        assert catalog.schema == 1;
        assert lib.length (lib.unique (map (feature: feature.name) features)) == lib.length features;
        lib.concatStringsSep "\n" (
          [
            "| Feature | Platforms and interface | Dependencies and state | Checks |"
            "| --- | --- | --- | --- |"
          ]
          ++ map (
            feature:
            "| [${cell feature.name}](${feature.guide}), [source](https://github.com/nix-forge/nix-conf/blob/main/${feature.source}) | ${cell (lib.concatStringsSep ", " feature.platforms)}. ${cell feature.interface} | ${cell feature.dependencies}. ${cell feature.state} | ${cell feature.validation} |"
          ) features
        )
        + "\n";
      # Split only tracked sources during evaluation. concatText consumes the
      # built option reference without importing a derivation into evaluation.
      insert =
        name: page: marker: reference:
        let
          parts = lib.splitString marker (builtins.readFile page);
        in
        assert lib.assertMsg (lib.length parts == 2) "${name}: expected exactly one reference marker";
        pkgs.concatText name [
          (pkgs.writeText "${name}-prefix" (lib.head parts))
          reference
          (pkgs.writeText "${name}-suffix" (lib.last parts))
        ];
      renderedFeatures =
        insert "features.md" ../docs/guide/features.md "<!-- generated-feature-catalog -->"
          (pkgs.writeText "feature-table.md" featureTable);
      renderedOptions =
        insert "options.md" ../docs/guide/options.md "<!-- generated-option-reference -->"
          config.packages.feature-options-markdown;
      codeStyles = pkgs.runCommand "guide-code.css" { nativeBuildInputs = [ python ]; } ''
        pygmentize -S friendly -f html -a .codehilite > "$out"
      '';
      staged = pkgs.linkFarm "guide-pages" (
        map
          (path: {
            name = "guide/" + lib.removePrefix (toString guideRoot + "/") (toString path);
            inherit path;
          })
          (
            builtins.filter (
              path:
              !(lib.elem (baseNameOf path) [
                "features.md"
                "options.md"
              ])
            ) (lib.filesystem.listFilesRecursive guideRoot)
          )
        ++ [
          {
            name = "guide/features.md";
            path = renderedFeatures;
          }
          {
            name = "guide/options.md";
            path = renderedOptions;
          }
          {
            name = "README.md";
            path = ../docs/README.md;
          }
          {
            name = "openssf-baseline.md";
            path = ../docs/openssf-baseline.md;
          }
          {
            name = "slsa.md";
            path = ../docs/slsa.md;
          }
          {
            name = "dependency-management.md";
            path = ../docs/dependency-management.md;
          }
          {
            name = "secret-management.md";
            path = ../docs/secret-management.md;
          }
          {
            name = "threat-model.md";
            path = ../THREAT_MODEL.md;
          }
          {
            name = "assets/font-implementation/pango.png";
            path = ../docs/assets/font-implementation/pango.png;
          }
          {
            name = "assets/font-implementation/qt.png";
            path = ../docs/assets/font-implementation/qt.png;
          }
          {
            name = "stylesheets/guide.css";
            path = ../site/guide.css;
          }
          {
            name = "stylesheets/code.css";
            path = codeStyles;
          }
        ]
      );
      mkdocsConfig = pkgs.writeText "mkdocs.yml" (
        lib.replaceStrings [ "docs_dir: ../docs" ] [ "docs_dir: ${builtins.toJSON (toString staged)}" ] (
          builtins.readFile ../site/mkdocs.yml
        )
      );
    in
    {
      packages.documentation = pkgs.runCommand "nix-conf-guide" { nativeBuildInputs = [ python ]; } ''
        mkdocs build --strict --config-file ${mkdocsConfig} --site-dir "$out"
        test -s "$out/index.html"
        test -s "$out/search/search_index.json"
      '';
      checks.documentation = config.packages.documentation;
      devShells.docs = pkgs.mkShellNoCC { packages = [ python ]; };
    };
}
