_: {
  perSystem = { myLib, pkgs, ... }: {
    checks = {
      stylesheet-quality =
        let
          source = pkgs.lib.fileset.toSource {
            root = ../..;
            fileset = pkgs.lib.fileset.unions [
              ../../.stylelintrc.json
              (pkgs.lib.fileset.unions (
                map (pkgs.lib.fileset.fileFilter (file: file.hasExt "css")) [
                  ../../hosts
                  ../../homes
                  ../../modules
                  ../../site
                ]
              ))
            ];
          };
        in
        pkgs.runCommand "stylesheet-quality" { nativeBuildInputs = [ pkgs.stylelint ]; } (
          myLib.writers.renderBashText { inherit pkgs; } {
            name = "stylesheet-quality.sh";
            text = ''
              # shellcheck shell=bash
              # Nix builder/activation callers and rendered fragments provide external variables.
              # shellcheck disable=SC2154
              cd @source@ || exit
              stylelint --config .stylelintrc.json --max-warnings 0 '**/*.css'
              touch "$out"
            '';
          } { inherit source; }
        );

      swift-quality =
        let
          source = pkgs.lib.fileset.toSource {
            root = ../..;
            fileset = pkgs.lib.fileset.unions [
              ../../.swift-format
              (pkgs.lib.fileset.fileFilter (file: file.hasExt "swift") ../../modules)
            ];
          };
        in
        pkgs.runCommand "swift-quality" { nativeBuildInputs = [ pkgs.swift-format ]; } ''
          cd ${source}
          swift-format lint --configuration .swift-format --parallel --recursive --strict modules
          touch "$out"
        '';

      lua-quality =
        let
          source = pkgs.lib.fileset.toSource {
            root = ../..;
            fileset = pkgs.lib.fileset.unions [
              ../../.luacheckrc
              (pkgs.lib.fileset.fileFilter (file: file.hasExt "lua") ../../modules)
            ];
          };
        in
        pkgs.runCommand "lua-quality" { nativeBuildInputs = [ pkgs.luaPackages.luacheck ]; } ''
          cd ${source}
          luacheck --config .luacheckrc modules
          touch "$out"
        '';

    };
  };
}
