{ inputs, lib, ... }: {
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem = { myLib, pkgs, ... }: {
    treefmt = {
      # Preserve captured upstream source, logs, and checksums byte for byte.
      settings.global.excludes = [
        # Each submodule owns its formatting and source checks.
        "nix-config-framework/**"
        "nix-homelab/**"
        "nix-seal/**"
        "pkgs/**"
        "docs/assets/hyprland-upstream-local-20260907/**"
        "**/*.age"
      ];
      # Keep path-flake checks hermetic in linked worktrees.  treefmt creates a
      # fresh Git repository for its diff check and must not inherit the
      # worktree's external `.git` pointer.
      projectRoot = lib.mkForce (lib.cleanSource inputs.self.outPath);
      programs = {
        # YAML and GitHub Actions
        yamlfmt = {
          settings.formatter.max_line_length = 100;
          enable = true;
          priority = 100;
        };
        actionlint = {
          enable = true;
          priority = 200;
        };
        yamllint = {
          enable = true;
          priority = 300;
          settings = {
            extends = "default";
            rules = {
              # Repository YAML uses one document per file.
              document-start = "disable";
              # yamlfmt emits one space before inline comments.
              comments.min-spaces-from-content = 1;
              # GitHub Actions uses the YAML 1.2 key `on`.
              truthy.check-keys = false;
              line-length = {
                max = 160;
                level = "error";
              };
            };
          };
        };

        # Nix
        deadnix = {
          enable = true;
          priority = 100;
        };
        statix = {
          enable = true;
          priority = 200;
        };
        nixfmt = {
          enable = true;
          width = 100;
          strict = true;
          priority = 300;
        };
        nixf-diagnose = {
          package =
            (import ../../overlays/temporary {
              inherit inputs;
              pkgs = pkgs.buildPackages;
            }).apply
              "nixf-flake-builtins"
              pkgs.buildPackages.nixf-diagnose;
          enable = true;
          autoFix = false;
          priority = 400;
        };

        # Shell
        shfmt = {
          enable = true;
          indent_size = 2;
          simplify = true;
          priority = 100;
        };
        shellcheck = {
          enable = true;
          priority = 200;
        };

        # Lua
        stylua = {
          enable = true;
          settings = {
            column_width = 100;
            indent_type = "Spaces";
            indent_width = 2;
            line_endings = "Unix";
            quote_style = "AutoPreferDouble";
          };
        };

        # Other
        keep-sorted.enable = true;
        just.enable = true;
        taplo.enable = true;
        rustfmt.enable = true;
        rumdl-check.enable = true;
        typos = {
          enable = true;
          configFile = ".typos.toml";
        };
        prettier = {
          enable = true;
          excludes = [
            "*.md"
            "*.yaml"
            "*.yml"
          ];
          settings.proseWrap = "always";
        };
        stylua.includes = [ ".luacheckrc" ];
      };
      settings.formatter = {
        # Use the same Nixpkgs formatter as JavaScript checks and include Node's
        # explicit module extensions, which the upstream module omits.
        prettier = {
          command = lib.mkForce "${
            import ./javascript-tools.nix {
              inherit myLib;
              pkgs = pkgs.buildPackages;
            }
          }/bin/prettier";
          includes = [
            "*.mts"
            "*.cts"
          ];
        };
        nix-template = {
          command = "${
            myLib.writers.writeShellApplication { pkgs = pkgs.buildPackages; } {
              name = "format-nix-template";
              runtimeInputs = [
                pkgs.buildPackages.nixfmt
                pkgs.buildPackages.coreutils
              ];
              text = (''
                # shellcheck shell=bash
                # nixfmt formats stdin without restricting the source filename's extension.
                set -euo pipefail
                temporary=$(mktemp)
                trap 'rm -f "$temporary"' EXIT
                for source in "$@"; do
                  # --filename labels stdin; output goes to a distinct temporary file.
                  # shellcheck disable=SC2094
                  nixfmt --strict --width 100 --filename "$source" <"$source" >"$temporary"
                  cat "$temporary" >"$source"
                done
              '');
            }
          }/bin/format-nix-template";
          includes = [ "*.nix.in" ];
        };
        dart-format = {
          command = "${pkgs.buildPackages.dart}/bin/dart";
          options = [ "format" ];
          includes = [ "*.dart" ];
        };
        swift-format = {
          command = "${pkgs.buildPackages.swift-format}/bin/swift-format";
          options = [
            "format"
            "--in-place"
            "--configuration"
            ".swift-format"
          ];
          includes = [ "*.swift" ];
        };
        # Nu templates can contain Nix substitutions that are not valid Nu yet.
        nufmt = {
          command = "${pkgs.buildPackages.nufmt}/bin/nufmt";
          includes = [ "*.nu" ];
        };
        shfmt.includes = [ "*.sh.in" ];
        shellcheck.includes = [ "*.sh.in" ];
        # Spelling suggestions require review, especially for protocol names.
        typos.options = lib.mkForce [
          "--force-exclude"
          "--config"
          ".typos.toml"
        ];
      };
    };
  };
}
