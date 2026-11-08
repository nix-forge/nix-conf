{
  inputs,
  lib,
  myLib,
  ...
}:
{
  perSystem =
    {
      pkgs,
      system,
      config,
      ...
    }:
    let
      catalog = import ../../modules/shared/fonts/packages.nix { };
      roles = catalog.roles pkgs;
      personal = inputs.self.packages.${system};
      # Hosted checks exercise matching with original geometric fixtures. The
      # protocol-family names below do not contain any Apple font data.
      syntheticFonts =
        pkgs.runCommand "synthetic-font-fixtures"
          {
            nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools ])) ];
          }
          ''
            python ${../../tests/fonts/build_synthetic_fonts.py} "$out/share/fonts/truetype"
            install -Dm644 ${../../LICENSE} "$out/share/doc/synthetic-font-fixtures/LICENSE"
          '';
      privateUseProviders = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        personal.apple-fonts.assets.apple-asset-lucidagrande
      ];
      applePlatformProviders = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ personal.apple-fonts ];
      renderFontconfig = (import ../../modules/shared/fonts/fontconfig.nix).render;
      fontRules = renderFontconfig {
        inherit myLib pkgs;
        fonts = roles;
        fontPackages = core;
      };
      syntheticSans = "Synthetic Sans Role";
      syntheticSerif = "Synthetic Serif Role";
      syntheticMonospace = "Synthetic Monospace Role";
      syntheticRules = renderFontconfig {
        inherit myLib pkgs;
        fonts = roles // {
          sansSerif = roles.sansSerif // {
            name = syntheticSans;
          };
          serif = roles.serif // {
            name = syntheticSerif;
          };
          monospace = roles.monospace // {
            name = syntheticMonospace;
          };
        };
        fontPackages = core;
      };
      python = pkgs.python3.withPackages (p: [
        p.fonttools
        p.uharfbuzz
        p.pillow
        p.selenium
        p.watchdog
        (import ../../lib/python/notification-process/package.nix { inherit pkgs; })
      ]);
      core =
        map (r: r.package) (builtins.attrValues roles)
        ++ [
          pkgs.noto-fonts
          pkgs.noto-fonts-cjk-sans
          pkgs.noto-fonts-cjk-serif
          pkgs.roboto
          pkgs.dejavu_fonts
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ syntheticFonts ];
      families = {
        sans-serif = "sansSerif";
        serif = "serif";
        monospace = "monospace";
        emoji = "emoji";
      };
      providers = pkgs.writeText "font-providers.json" (
        builtins.toJSON (
          lib.mapAttrs (_: role: {
            families = [ roles.${role}.name ];
            package = toString roles.${role}.package;
          }) families
        )
      );
      policy = pkgs.writeText "font-policy.conf" ''
        <?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd"><fontconfig>
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (generic: role: ''
            <alias binding="same"><family>${generic}</family><prefer>
            ${lib.concatMapStrings (name: "<family>${name}</family>") (catalog.fallbacks roles).${role}}
            </prefer></alias>
          '') families
        )}
        </fontconfig>
      '';
      # Keep upstream matching and rendering rules while excluding host/user
      # includes, which would reintroduce the currently activated font profile.
      defaultRules = pkgs.runCommand "isolated-fontconfig-rules" { } (
        (import ../../lib/templates/text.nix) ./scripts/install-isolated-fontconfig-rules.sh {
          pkgs_fontconfig_out = pkgs.fontconfig.out;
        }
      );
      # Fontconfig 2.18 uses a URN for its DTD; libxslt's search path only
      # resolves filenames. Supply the local catalog so validation stays offline.
      fontconfigCatalog = pkgs.writeText "fontconfig-catalog.xml" (
        (import ../../lib/templates/text.nix) ./scripts/fonts-config.xml {
          pkgs_fontconfig_out = pkgs.fontconfig.out;
        }
      );
      makeFontsConf =
        args:
        (pkgs.makeFontsConf args).overrideAttrs (old: {
          # The libxml setup hook resets XML_CATALOG_FILES during setup.
          buildCommand =
            ((import ../../lib/templates/text.nix) ./scripts/set-fontconfig-xml-catalog.sh {
              inherit fontconfigCatalog;
            })
            + old.buildCommand;
        });
      fontConfig = makeFontsConf {
        fontDirectories = map (p: "${p}/share/fonts") core;
        impureFontDirectories = [ ];
        includes = [
          defaultRules
          fontRules.cssGenericAlias
          policy
          fontRules.privateUseFallback
        ];
      };
      fontPkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          p:
          builtins.elem (lib.getName p) [
            "corefonts"
            "joypixels"
          ];
      };
      collection =
        catalog.select fontPkgs personal {
          designLibrary = "full";
          optionalEmoji.enable = true;
          restrictedFonts.enable = true;
        }
        ++ privateUseProviders
        ++ applePlatformProviders;
      collectionFontRules = renderFontconfig {
        inherit myLib pkgs;
        fonts = roles;
        fontPackages = collection;
      };
      collectionConfig = makeFontsConf {
        fontDirectories = map (p: "${p}/share/fonts") collection;
        impureFontDirectories = [ ];
        includes = map (p: "${p}/etc/fonts/conf.d") collection ++ [
          defaultRules
          collectionFontRules.cssGenericAlias
          policy
          collectionFontRules.privateUseFallback
        ];
      };
      emojiData = pkgs.fetchurl {
        url = "https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt";
        hash = "sha256-HYqUT4jXlS9+98UWf+88Z5lbyuJFQ5SXECMbA6IBrNo=";
      };
      testSource = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../tests/fonts
          ../../tests/browsers
          ../../tests/waits.py
          ../../tests/typescript_sources.py
          ../../tests/typescript/source.mts
        ];
      };
    in
    {
      checks = {
        font-catalog-policy = import ../../tests/nix/font-catalog-policy.nix { pkgs = fontPkgs; };

        fontconfig-renderer =
          pkgs.runCommand "fontconfig-renderer" { nativeBuildInputs = [ pkgs.gnugrep ]; }
            (
              (import ./../../lib/templates/text.nix) ./scripts/font-generic-aliases.sh {
                sansSerifFamily = null;
                serifFamily = null;
                monospaceFamily = null;
                lib_escapeShellArg_syntheticSans = lib.escapeShellArg syntheticSans;
                syntheticRules_cssGenericAlias = syntheticRules.cssGenericAlias;
                lib_escapeShellArg_syntheticSerif = lib.escapeShellArg syntheticSerif;
                lib_escapeShellArg_syntheticMonospace = lib.escapeShellArg syntheticMonospace;
              }
            );
        font-selection =
          pkgs.runCommand "font-selection"
            {
              nativeBuildInputs = [
                python
                pkgs.fontconfig
              ];
              FONTCONFIG_FILE = fontConfig;
            }
            (
              (import ../../lib/templates/text.nix) ./scripts/font-selection.sh {
                inherit testSource;
                inherit providers;
                inherit emojiData;
              }
            );
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        font-browser =
          pkgs.runCommand "font-browser-rendering"
            {
              nativeBuildInputs = [
                python
                pkgs.fontconfig
                pkgs.geckodriver
                pkgs.nodejs_24
              ];
              FONTCONFIG_FILE = fontConfig;
            }
            (
              (import ../../lib/templates/text.nix) ./scripts/font-browser-rendering.sh {
                inherit testSource;
                lib_getExe_pkgs_firefox = lib.getExe pkgs.firefox;
                modules_home_browsers_shared_emoji_presentation_css = ../../modules/home/browsers/shared/emoji-presentation.css;
              }
            );
        font-native =
          pkgs.runCommand "font-native-rendering"
            {
              nativeBuildInputs = [
                pkgs.stdenv.cc
                pkgs.pkg-config
              ];
              buildInputs = [
                pkgs.qt6.qtbase
                pkgs.pango
              ];
              FONTCONFIG_FILE = fontConfig;
            }
            (
              (import ../../lib/templates/text.nix) ./scripts/font-native-rendering.sh {
                pkgs_qt6_qtbase = pkgs.qt6.qtbase;
                tests_fonts_render_native_cpp = ../../tests/fonts/render_native.cpp;
              }
            );
      };
      apps.font-check = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "font-check";
            runtimeInputs = [
              python
              pkgs.fontconfig
              pkgs.geckodriver
              pkgs.nodejs_24
              pkgs.coreutils
            ];
            text = (import ../../lib/templates/text.nix) ./scripts/font-check.sh {
              lib_optionalString_pkgs_stdenv_hostPlatform_isDarwin_if_ge_2 = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin (
                builtins.readFile ./scripts/reject-macos-browser-font-isolation.sh
              );
              inherit collectionConfig;
              inherit testSource;
              inherit providers;
              inherit emojiData;
              lib_optionalString_pkgs_stdenv_hostPlatform_isLinux_cp_confi =
                lib.optionalString pkgs.stdenv.hostPlatform.isLinux
                  (
                    (import ../../lib/templates/text.nix) ./scripts/collect-native-font-results.sh {
                      config_checks_font_native = config.checks.font-native;
                      inherit testSource;
                      inherit emojiData;
                      personal_apple_color_emoji = personal.apple-color-emoji;
                    }
                  );
              modules_home_browsers_shared_emoji_presentation_css = ../../modules/home/browsers/shared/emoji-presentation.css;
              personal_mutant_standard_emoji_compiledFont_src = personal.mutant-standard-emoji.compiledFont.src;
              personal_mutant_standard_emoji = personal.mutant-standard-emoji;
              lib_optionalString_pkgs_stdenv_hostPlatform_isLinux_python_t =
                lib.optionalString pkgs.stdenv.hostPlatform.isLinux
                  (
                    (import ../../lib/templates/text.nix) ./scripts/check-browser-apple-emoji.sh {
                      inherit testSource;
                      personal_apple_color_emoji = personal.apple-color-emoji;
                      inherit emojiData;
                    }
                  );
            };
          }
        );
      };
      devShells.fonts = pkgs.mkShellNoCC {
        PYTHONPATH = "${testSource}/tests";
        packages = [
          python
          pkgs.fontconfig
          pkgs.geckodriver
          pkgs.nodejs_24
        ];
      };
    };
}
