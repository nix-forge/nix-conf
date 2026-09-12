_: {
  perSystem = { pkgs, lib, ... }: {
    checks.javascript-quality =
      let
        source = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.unions [
            ../../.oxlintrc.json
            (lib.fileset.fileFilter (
              file:
              builtins.any file.hasExt [
                "js"
                "mjs"
                "cjs"
                "jsx"
                "ts"
                "tsx"
              ]
            ) ../../tests)
          ];
        };
      in
      pkgs.runCommand "javascript-quality" { nativeBuildInputs = [ pkgs.oxlint ]; } ''
        cd ${source}
        oxlint --config .oxlintrc.json --deny-warnings tests
        touch "$out"
      '';
  };
}
