{ inputs, lib, ... }: {
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
      python = pkgs.python3.withPackages (p: [
        p.fonttools
        p.uharfbuzz
        p.pillow
        p.selenium
      ]);
      core = map (r: r.package) (builtins.attrValues roles) ++ [
        pkgs.noto-fonts
        pkgs.noto-fonts-cjk-sans
        pkgs.noto-fonts-cjk-serif
      ];
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
      defaultRules = pkgs.runCommand "isolated-fontconfig-rules" { } ''
        mkdir -p "$out"
        for rule in ${pkgs.fontconfig.out}/etc/fonts/conf.d/*.conf; do
          name=$(basename "$rule")
          case "$name" in 50-user.conf|51-local.conf) continue ;; esac
          ln -s "$(readlink -f "$rule")" "$out/$name"
        done
      '';
      # Fontconfig 2.18 uses a URN for its DTD; libxslt's search path only
      # resolves filenames. Supply the local catalog so validation stays offline.
      fontconfigCatalog = pkgs.writeText "fontconfig-catalog.xml" ''
        <?xml version="1.0"?>
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
          <system systemId="urn:fontconfig:fonts.dtd" uri="${pkgs.fontconfig.out}/share/xml/fontconfig/fonts.dtd"/>
        </catalog>
      '';
      makeFontsConf =
        args:
        (pkgs.makeFontsConf args).overrideAttrs (old: {
          # The libxml setup hook resets XML_CATALOG_FILES during setup.
          buildCommand = ''
            export XML_CATALOG_FILES=${fontconfigCatalog}
          ''
          + old.buildCommand;
        });
      fontConfig = makeFontsConf {
        fontDirectories = map (p: "${p}/share/fonts") core;
        impureFontDirectories = [ ];
        includes = [
          defaultRules
          policy
        ];
      };
      personal = inputs.self.packages.${system};
      fontPkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          p:
          builtins.elem (lib.getName p) [
            "corefonts"
            "joypixels"
          ];
      };
      collection = catalog.select fontPkgs personal {
        designLibrary = "full";
        optionalEmoji.enable = true;
      };
      collectionConfig = makeFontsConf {
        fontDirectories = map (p: "${p}/share/fonts") collection;
        impureFontDirectories = [ ];
        includes = map (p: "${p}/etc/fonts/conf.d") collection ++ [
          defaultRules
          policy
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
        ];
      };
    in
    {
      checks = {
        font-selection =
          pkgs.runCommand "font-selection"
            {
              nativeBuildInputs = [
                python
                pkgs.fontconfig
              ];
              FONTCONFIG_FILE = fontConfig;
            }
            ''
              export XDG_CACHE_HOME="$TMPDIR/font-cache"
              mkdir -p "$out"
              python ${testSource}/tests/fonts/check_selection.py --providers ${providers} --output "$out/selection.json"
              python -m unittest discover -s ${testSource}/tests/fonts -p test_shaping.py
              python ${testSource}/tests/fonts/check_emoji_coverage.py --emoji-data ${emojiData}
            '';
        font-ownership =
          let
            desktop = inputs.self.nixosConfigurations.desktop.config;
            mac = inputs.self.darwinConfigurations.macbook-pro-m4.config;
            dh = desktop.home-manager.users.ianmh;
            mh = mac.home-manager.users.ianmh;
            shared = builtins.filter (
              p: builtins.any (q: toString q == toString p) mh.home.packages
            ) mac.fonts.packages;
          in
          assert shared == [ ];
          assert dh.typography.designLibrary == "full" && mh.typography.designLibrary == "full";
          assert dh.stylix.fonts.serif.package.pname == "literata";
          assert mh.stylix.fonts.serif.package.pname == "literata";
          assert dh.fonts.fontconfig.defaultFonts == desktop.fonts.fontconfig.defaultFonts;
          assert !(dh.xdg.dataFile ? "fonts/optional-emoji");
          assert !(mh.xdg.dataFile ? "fonts/optional-emoji");
          pkgs.runCommand "font-ownership" { } "touch $out";
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        font-browser =
          pkgs.runCommand "font-browser-rendering"
            {
              nativeBuildInputs = [
                python
                pkgs.fontconfig
                pkgs.geckodriver
              ];
              FONTCONFIG_FILE = fontConfig;
            }
            ''
              export XDG_CACHE_HOME="$TMPDIR/cache"
              export XDG_CONFIG_HOME="$TMPDIR/config"
              export XDG_DATA_HOME="$TMPDIR/data"
              mkdir -p "$out"
              for suite in digits multilingual; do
                python ${testSource}/tests/browsers/check_font_rendering.py --suite "$suite" --browser ${lib.getExe pkgs.firefox} --output "$out/$suite"
              done
            '';
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
            ''
              export XDG_CACHE_HOME="$TMPDIR/cache"
              export XDG_RUNTIME_DIR="$TMPDIR/runtime"
              export QT_QPA_PLATFORM=offscreen
              export QT_PLUGIN_PATH=${pkgs.qt6.qtbase}/lib/qt-6/plugins
              mkdir -p "$out" "$XDG_RUNTIME_DIR"
              chmod 700 "$XDG_RUNTIME_DIR"
              c++ -fPIC -std=c++17 ${../../tests/fonts/render_native.cpp} -o render $(pkg-config --cflags --libs Qt6Gui pangocairo)
              ./render "$out"
            '';
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
              pkgs.coreutils
            ];
            text = ''
              if [[ "$#" -lt 1 ]]; then
                echo "Usage: font-check OUTPUT-DIRECTORY [BROWSER-EXECUTABLE]" >&2
                exit 2
              fi
              ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                if [[ "$#" -ge 2 ]]; then
                  echo "Browser collection isolation uses Linux Fontconfig. On macOS, run tests/fonts/check_coretext.swift after activation." >&2
                  exit 2
                fi
              ''}
              output=$(realpath -m "$1")
              mkdir -p "$output"
              export FONTCONFIG_FILE=${collectionConfig}
              export XDG_CACHE_HOME
              XDG_CACHE_HOME=$(mktemp -d)
              trap 'rm -rf "$XDG_CACHE_HOME"' EXIT
              export XDG_CONFIG_HOME="$XDG_CACHE_HOME/config"
              export XDG_DATA_HOME="$XDG_CACHE_HOME/data"
              python ${testSource}/tests/fonts/check_selection.py --providers ${providers} --inventory --output "$output/selection.json"
              python ${testSource}/tests/fonts/check_emoji_coverage.py --emoji-data ${emojiData}
              ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
                cp ${config.checks.font-native}/*.png "$output/"
                python ${testSource}/tests/fonts/check_emoji_coverage.py --emoji-data ${emojiData} --font ${personal.apple-color-emoji}/share/fonts/truetype/apple-color-emoji/font.ttf
              ''}
              mkdir -p "$XDG_CACHE_HOME/fontconfig"
              du -sb "$XDG_CACHE_HOME/fontconfig" | cut -f1 > "$output/fontconfig-cache-bytes.txt"
              if [[ "$#" -ge 2 ]]; then
                browser=$(realpath "$2")
                for suite in digits multilingual; do
                  python ${testSource}/tests/browsers/check_font_rendering.py --suite "$suite" --browser "$browser" --output "$output/$suite"
                done
                python -m zipfile -e ${personal.mutant-standard-emoji.compiledFont.src} "$XDG_CACHE_HOME/artwork"
                python ${testSource}/tests/browsers/check_mutant_emoji.py --installed --font ${personal.mutant-standard-emoji}/share/fonts/truetype/MutantStandardEmoji.ttf --artwork "$XDG_CACHE_HOME/artwork/emoji" --browser "$browser" --output "$output/mutant"
                ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
                  python ${testSource}/tests/browsers/check_apple_emoji.py --font ${personal.apple-color-emoji}/share/fonts/truetype/apple-color-emoji/font.ttf --emoji-data ${emojiData} --browser "$browser" --output "$output/apple"
                ''}
              fi
            '';
          }
        );
      };
      devShells.fonts = pkgs.mkShellNoCC {
        packages = [
          python
          pkgs.fontconfig
          pkgs.geckodriver
        ];
      };
    };
}
