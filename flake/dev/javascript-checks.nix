{ inputs, ... }: {
  perSystem = { pkgs, lib, ... }: {
    checks = {
      javascript-quality =
        let
          metabrainzExtension =
            inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.metabrainz-spicetify-extension;
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
              ../../package.json
              ../../package-lock.json
              ../../tsconfig.json
              ../../tests/typescript/projects.json
              (lib.fileset.fileFilter sourceFile ../../overlays)
              (lib.fileset.fileFilter sourceFile ../../tests)
              (lib.fileset.fileFilter sourceFile ../../modules)
              (lib.fileset.fileFilter sourceFile ../../lib)
              (lib.fileset.fileFilter sourceFile ../../flake)
              (lib.fileset.fileFilter sourceFile ../../scripts)
            ];
          };
        in
        pkgs.buildNpmPackage {
          pname = "javascript-quality";
          version = "1";
          src = source;
          nodejs = pkgs.nodejs_24;
          inherit (import ./javascript-tools.nix { inherit pkgs; }) npmDeps;
          dontNpmBuild = true;
          dontNpmInstall = true;
          doCheck = true;
          # Directory notifications require this native service in Darwin's sandbox.
          sandboxProfile = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin (
            builtins.readFile ./fsevents.sb
          );
          checkPhase = (import ../../lib/templates/text.nix) ./scripts/check-javascript.sh {
            inherit metabrainzExtension;
          };
          installPhase = builtins.readFile ./scripts/install-javascript-check-output.sh;
        };
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      # Exercise the account reconciler against the Scrypted package selected
      # by this flake. Package updates must pass this check before deployment.
      scrypted-auth-compat =
        let
          scrypted = inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.scrypted-server;
          serverRoot = "${scrypted}/lib/node_modules/@scrypted/server";
          scryptedScripts =
            inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.homelab-iot-scripts;
        in
        pkgs.runCommand "scrypted-auth-compat" { } (
          (import ../../lib/templates/text.nix) ./scripts/scrypted-auth-compat.sh {
            inherit scryptedScripts;
            inherit scrypted;
            inherit serverRoot;
          }
        );
    };
  };
}
