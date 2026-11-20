{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    {
      config,
      myLib,
      pkgs,
      ...
    }:
    let
      javascriptTools = import ./javascript-tools.nix {
        inherit myLib;
        pkgs = pkgs.buildPackages;
      };
      stylesheetLint = myLib.writers.writeShellApplication { pkgs = pkgs.buildPackages; } {
        name = "stylesheet-lint";
        runtimeInputs = [
          pkgs.buildPackages.git
          pkgs.buildPackages.stylelint
        ];
        text = ''
          mapfile -d "" -t stylesheets < <(git ls-files -z -- '*.css')
          if ((''${#stylesheets[@]} > 0)); then
            stylelint --config .stylelintrc.json --max-warnings 0 "''${stylesheets[@]}"
          fi
        '';
      };
    in
    {
      pre-commit = {
        check.enable = true;
        settings = {
          excludes = [
            "^nix-config-framework/"
            "^nix-homelab/"
            "^nix-seal/"
            "^pkgs/"
          ];
          # A path flake includes a linked worktree's `.git` pointer.  The check
          # creates its own isolated repository, so carrying that pointer into
          # the sandbox makes Git escape to a non-existent external gitdir.
          # Filter only standard VCS/generated metadata; all candidate source,
          # including untracked files, remains part of the exact path input.
          rootSrc = lib.mkForce (lib.cleanSource inputs.self.outPath);
          package = pkgs.buildPackages.prek;
          hooks = {
            treefmt = {
              enable = true;
              name = "treefmt";
              # treefmt schedules its formatters; avoid many concurrent wrappers.
              require_serial = true;
              pass_filenames = true;
              entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
            };
            pinact = {
              enable = true;
              name = "pinact";
              entry = "${lib.getExe pkgs.buildPackages.pinact} run --fix=false --no-api";
              language = "system";
              files = "^\\.github/workflows/.*\\.ya?ml$";
              after = [ "treefmt" ];
            };
            oxlint = {
              enable = true;
              name = "TypeScript and Oxlint";
              entry = lib.getExe javascriptTools;
              language = "system";
              files = "(\\.[cm]?[jt]sx?$|(^|/)(tsconfig|projects|\\.oxlintrc|package(-lock)?)\\.json$)";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            stylelint = {
              enable = true;
              name = "Stylelint";
              entry = lib.getExe stylesheetLint;
              language = "system";
              extraPackages = [ stylesheetLint ];
              files = "(^\\.stylelintrc\\.json$|\\.css$)";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            swift-format = {
              enable = true;
              name = "Swift format lint";
              entry = "${lib.getExe pkgs.buildPackages.swift-format} lint --configuration .swift-format --parallel --recursive --strict modules";
              language = "system";
              extraPackages = [ pkgs.buildPackages.swift-format ];
              files = "(^\\.swift-format$|\\.swift$)";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            luacheck = {
              enable = true;
              name = "Lua analysis";
              entry = "${lib.getExe pkgs.buildPackages.luaPackages.luacheck} --config .luacheckrc modules";
              language = "system";
              files = "(^\\.luacheckrc$|\\.lua$)";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            end-of-file-fixer = {
              enable = true;
              after = [ "treefmt" ];
              excludes = [
                "\\.age$"
                "^docs/assets/hyprland-upstream-local-20260907/"
              ];
            };
            trim-trailing-whitespace = {
              enable = true;
              after = [ "treefmt" ];
              # Unified diff context includes significant trailing spaces.
              excludes = [
                "\\.age$"
                "^docs/assets/hyprland-upstream-local-20260907/"
                "\\.patch$"
              ];
            };
            mixed-line-endings = {
              enable = true;
              args = [ "--fix=lf" ];
              after = [ "treefmt" ];
              excludes = [
                "\\.age$"
                "^docs/assets/hyprland-upstream-local-20260907/"
              ];
            };

            check-merge-conflicts.enable = true;
            check-symlinks.enable = true;

            detect-private-keys.enable = true;

            check-case-conflicts.enable = true;
            check-added-large-files = {
              enable = true;
              # The before screenshot is 1.1 MB and documents the rendering defect.
              excludes = [ "^docs/assets/zen-webfonts/before\\.png$" ];
            };
            check-executables-have-shebangs.enable = true;
            check-shebang-scripts-are-executable = {
              enable = true;
              # Rust inner attributes start with `#![` and are not script shebangs.
              excludes = [
                # Interpreter placeholders are resolved before execution.
                ".*\\.(sh|py)\\.in$"
                ".*\\.rs$"
                # The framework and package catalog own their hook configuration.
                "^nix-config-framework/"
                "^pkgs/"
              ];
            };
            fix-byte-order-marker.enable = true;

            editorconfig-checker = {
              enable = true;
              excludes = [
                "\\.age$"
                "^docs/assets/hyprland-upstream-local-20260907/"
                "^nix-config-framework/"
                "^pkgs/"
              ];
            };
            typos = {
              enable = true;
              # The upstream hook's generated empty [default] table overrides configPath.
              entry = "${lib.getExe pkgs.buildPackages.typos} --config .typos.toml --force-exclude";
            };
            zizmor = {
              enable = true;
              args = [ "--persona=pedantic" ];
            };
            gitleaks = {
              enable = true;
              name = "Gitleaks";
              entry = "${lib.getExe pkgs.buildPackages.gitleaks} git --pre-commit --staged --redact --no-banner";
              # The complete entry owns its arguments; do not append hook defaults.
              args = [ ];
              language = "system";
              always_run = true;
              pass_filenames = false;
            };

            check-json.enable = true;
            check-toml.enable = true;
            check-yaml.enable = true;

            flake-checker.enable = true;

          };
        };
      };
    };

}
