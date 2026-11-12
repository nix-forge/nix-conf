{ inputs, self, ... }: {
  perSystem =
    { pkgs, ... }:
    let
      checkPython = import ./quality-python.nix { inherit pkgs; };
      # Test the sources produced by the real Nix declarations, including
      # public-value substitution. No source-template inventory is maintained.
      secretTemplateSources =
        (builtins.head (builtins.attrValues self.nixosConfigurations.desktop.config.home-manager.users))
        .nixSeal.templates
        // {
          inherit (self.nixosConfigurations.desktop.config.nixSeal.templates) flakehub-netrc;
        };
    in
    {
      checks = {
        workstation-policy = import ../../tests/nix/workstation-policy.nix { inherit pkgs; };
        nix-credential-loading = import ../../tests/nix/nix-credential-loading.nix {
          inherit pkgs inputs;
          # Exercise the desktop's selected client; avoid building a different
          # upstream Nix merely to inspect its configuration parser.
          nix =
            if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
              self.nixosConfigurations.desktop.config.nix.package
            else
              pkgs.nix;
        };
        # Validate the selected release artifacts without building a host closure.
        zen-beta-artifact = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta-unwrapped;

        secret-templates =
          assert import ../../tests/secrets/template-policy.nix { inherit (pkgs) lib; };
          (import ../../tests/python-check.nix { inherit pkgs; }) {
            name = "secret-template-tests";
            files = [
              ../../tests/secrets
              ../../homes/macbook-pro-m4/local/nix-seal
            ];
            testPaths = [ "tests/secrets/test_public_templates.py" ];
            selection = "nix_integration";
            nativeBuildInputs = [
              pkgs.git
              inputs.nix-seal.packages.${pkgs.stdenv.hostPlatform.system}.default
            ];
            prepare = (import ../../lib/templates/text.nix) ./scripts/compile-secret-test-templates.sh {
              pkgs_lib_concatStringsSep_n_pkgs_lib_mapAttrsToList_name_tem = pkgs.lib.concatStringsSep "\n" (
                pkgs.lib.mapAttrsToList (
                  name: template:
                  pkgs.lib.escapeShellArgs [
                    "cp"
                    (toString template.renderedSource)
                    "compiled-templates/${name}.template"
                  ]
                ) secretTemplateSources
              );
            };
          };

        python-quality =
          pkgs.runCommand "python-quality"
            {
              nativeBuildInputs = [
                checkPython
                pkgs.ruff
                pkgs.ty
              ];
            }
            (
              (import ../../lib/templates/text.nix) ./scripts/python-quality.sh {
                inputs_self_outPath = inputs.self.outPath;
                inherit checkPython;
              }
            );

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
                    ../../tests
                  ]
                ))
              ];
            };
          in
          pkgs.runCommand "stylesheet-quality" { nativeBuildInputs = [ pkgs.stylelint ]; } (
            (import ../../lib/templates/text.nix) ./scripts/stylesheet-quality.sh { inherit source; }
          );

        swift-quality =
          let
            source = pkgs.lib.fileset.toSource {
              root = ../..;
              fileset = pkgs.lib.fileset.unions [
                ../../.swift-format
                (pkgs.lib.fileset.fileFilter (file: file.hasExt "swift") ../../modules)
                (pkgs.lib.fileset.fileFilter (file: file.hasExt "swift") ../../tests)
              ];
            };
          in
          pkgs.runCommand "swift-quality" { nativeBuildInputs = [ pkgs.swift-format ]; } ''
            cd ${source}
            swift-format lint --configuration .swift-format --parallel --recursive --strict modules tests
            touch "$out"
          '';

        lua-quality =
          let
            source = pkgs.lib.fileset.toSource {
              root = ../..;
              fileset = pkgs.lib.fileset.unions [
                ../../.luacheckrc
                (pkgs.lib.fileset.fileFilter (file: file.hasExt "lua") ../../modules)
                (pkgs.lib.fileset.fileFilter (file: file.hasExt "lua") ../../tests)
              ];
            };
          in
          pkgs.runCommand "lua-quality" { nativeBuildInputs = [ pkgs.luaPackages.luacheck ]; } ''
            cd ${source}
            luacheck --config .luacheckrc modules tests
            touch "$out"
          '';

        # Detect a canary even inside paths with narrowly scoped exceptions.
        gitleaks-policy =
          pkgs.runCommand "gitleaks-policy"
            {
              nativeBuildInputs = [
                pkgs.gitleaks
                pkgs.git
              ];
            }
            (
              (import ../../lib/templates/text.nix) ./scripts/gitleaks-policy.sh {
                tests_privacy_check_publication_policy_sh = ../../tests/privacy/check-publication-policy.sh;
                gitleaks_toml = ../../.gitleaks.toml;
                github_scripts_scan_publication_sh = ../../.github/scripts/scan-publication.sh;
                pkgs_gitleaks_toml = ../../pkgs/.gitleaks.toml;
                nix_seal_gitleaks_toml = ../../nix-seal/.gitleaks.toml;
                nix_homelab_gitleaks_toml = ../../nix-homelab/.gitleaks.toml;
                nix_config_framework_gitleaks_toml = ../../nix-config-framework/.gitleaks.toml;
              }
            );

      }
      // pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        # Other Moonfin platforms consume a binary package, not this Dart source.
        dart-quality =
          let
            moonfin = inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.moonfin;
          in
          pkgs.runCommand "dart-quality" { nativeBuildInputs = [ pkgs.python3 ]; } (
            (import ../../lib/templates/text.nix) ./scripts/dart-quality.sh {
              source = moonfin.src;
              checker = ../../overlays/temporary/tests/moonfin_caption_background.py;
              fixture = ../../overlays/temporary/tests/moonfin-caption-background.dart;
              analysisOptions = ../../overlays/temporary/tests/analysis_options.yaml;
              dart = pkgs.lib.getExe pkgs.flutter347.dart;
            }
          );

        book-discovery = import ../../tests/nix/homelab/book-discovery.nix {
          inherit pkgs;
          desktop = self.nixosConfigurations.desktop;
        };
        homelab-actual-https = import ../../tests/nix/homelab/actual-https.nix {
          inherit pkgs;
          desktop = self.nixosConfigurations.desktop;
        };
        homelab-vpn-policy = import ../../tests/nix/homelab/vpn-policy.nix {
          inherit pkgs;
          desktop = self.nixosConfigurations.desktop;
        };
        clamav-memory-policy =
          let
            daemonConfig = self.nixosConfigurations.desktop.config.environment.etc."clamav/clamd.conf".source;
          in
          pkgs.runCommand "clamav-memory-policy" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
            grep -Eq '^[[:space:]]*ConcurrentDatabaseReload[[:space:]]+false[[:space:]]*$' ${daemonConfig}
            touch "$out"
          '';
        clamav-directories = import ../../tests/nix/clamav/directories.nix { inherit pkgs; };
        clamav-runtime = import ../../tests/nix/clamav/runtime.nix { inherit pkgs; };
        clamav-special-files = import ../../tests/nix/clamav/special-files.nix { inherit pkgs; };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        rift-home-manager = import (inputs.nixpkgs-personal + "/modules/home/tests/rift.nix") {
          inherit pkgs;
          homeManager = inputs.home-manager;
        };
        # Exercise the same package selected by the configured local service.
        actual-runtime = import ../../tests/nix/actual-runtime.nix {
          inherit pkgs;
          actualPackage =
            self.darwinConfigurations.macbook-pro-m4.config.home-manager.users.ianmh.services.actual.package;
        };
        macos-home-dry-run =
          let
            fakeDockutil = pkgs.writeShellScriptBin "dockutil" (builtins.readFile ./scripts/dockutil.sh);
            fakeFinderFavorites = pkgs.writeShellScriptBin "finder-favorites" (
              builtins.readFile ./scripts/finder-favorites.sh
            );
            dryRunHome = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ../../modules/home/macos
                {
                  home = {
                    username = "check-user";
                    homeDirectory = "/Users/check-user";
                    stateVersion = "25.05";
                  };
                  macos.dockItems = {
                    enable = true;
                    mode = "authoritative";
                    package = fakeDockutil;
                    persistentApps = [ { app = "/Applications/Missing Test.app"; } ];
                  };
                  macos.finderFavorites = {
                    enable = true;
                    mode = "reconcile";
                    allowDeprecatedBackend = true;
                    package = fakeFinderFavorites;
                    entries = [
                      {
                        id = "dry-run";
                        label = "Dry Run";
                        path = "/Users/check-user/Dry Run";
                        onMissing = "createDirectory";
                      }
                    ];
                  };
                }
              ];
            };
            dockActivation = pkgs.writeText "macos-dock-dry-run" dryRunHome.config.home.activation.syncDockItems.data;
            finderActivation = pkgs.writeText "macos-finder-favorites-dry-run" dryRunHome.config.home.activation.syncFinderFavorites.data;
            finderConfiguration = dryRunHome.config.xdg.configFile."finder-favorites/config.json".source;
          in
          pkgs.runCommand "macos-home-dry-run"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.gnugrep
              ];
            }
            (
              (import ../../lib/templates/text.nix) ./scripts/macos-home-dry-run.sh {
                inherit dockActivation;
                inherit finderActivation;
                inherit finderConfiguration;
              }
            );
      };
    };
}
