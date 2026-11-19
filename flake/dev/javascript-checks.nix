_: {
  perSystem =
    {
      myLib,
      pkgs,
      lib,
      ...
    }:
    let
      checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
    in
    {
      checks = {
        javascript-quality =
          let
            sourceFile =
              file:
              builtins.elem file.name [
                "tsconfig.json"
                "package.json"
                ".oxlintrc.json"
              ]
              || builtins.any file.hasExt [
                "js"
                "mjs"
                "cjs"
                "jsx"
                "ts"
                "mts"
                "cts"
                "tsx"
              ];
            source = lib.fileset.toSource {
              root = ../..;
              fileset = lib.fileset.unions [
                ../../.editorconfig
                ../../.oxlintrc.json
                ../../tsconfig.json
                ../../scripts/typescript/projects.json
                (lib.fileset.fileFilter sourceFile ../../overlays)
                (lib.fileset.fileFilter sourceFile ../../modules)
                (lib.fileset.fileFilter sourceFile ../../lib)
                (lib.fileset.fileFilter sourceFile ../../flake)
                (lib.fileset.fileFilter sourceFile ../../scripts)
              ];
            };
          in
          pkgs.stdenvNoCC.mkDerivation {
            pname = "javascript-quality";
            version = "1";
            src = source;
            nativeBuildInputs = [ (import ./javascript-tools.nix { inherit myLib pkgs; }) ];
            dontConfigure = true;
            dontBuild = true;
            doCheck = true;
            # Directory notifications require this native service in Darwin's sandbox.
            sandboxProfile = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin (
              builtins.readFile ./fsevents.sb
            );
            checkPhase = checkedShellText {
              name = "check-javascript";
              text = ''
                runHook preCheck
                javascript-check
                runHook postCheck
              '';
            };
            installPhase = checkedShellText {
              name = "install-javascript-check-output";
              # stdenv sets out in the build environment.
              text = ''
                # shellcheck disable=SC2154
                mkdir -p "$out"
              '';
            };
          };
      };
    };
}
