{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem = { config, pkgs, ... }: {
    pre-commit = {
      check.enable = pkgs.stdenv.hostPlatform.isDarwin;
      settings = {
        package = pkgs.prek;
        hooks = {
          treefmt = {
            enable = true;
            name = "treefmt";
            pass_filenames = true;
            entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
          };
          pinact = {
            enable = true;
            name = "pinact";
            entry = "${lib.getExe pkgs.pinact} run --fix=false --no-api";
            language = "system";
            files = "^\\.github/workflows/.*\\.ya?ml$";
            after = [ "treefmt" ];
          };
          ruff = {
            enable = true;
            entry = "${lib.getExe pkgs.ruff} check .";
            always_run = true;
            pass_filenames = false;
            after = [ "treefmt" ];
          };
          ty = {
            enable = true;
            name = "ty";
            package = pkgs.ty;
            entry = "${lib.getExe pkgs.ty} check";
            language = "system";
            always_run = true;
            pass_filenames = false;
            after = [ "ruff" ];
          };
          python-compile = {
            enable = true;
            name = "python compileall";
            entry = "${lib.getExe pkgs.python3} -m compileall -q scripts";
            language = "system";
            always_run = true;
            pass_filenames = false;
            after = [ "ty" ];
          };

          end-of-file-fixer = {
            enable = true;
            after = [ "treefmt" ];
            excludes = [ "^secrets/.*\\.age$" ];
          };
          trim-trailing-whitespace = {
            enable = true;
            after = [ "treefmt" ];
            excludes = [ "^secrets/.*\\.age$" ];
          };
          mixed-line-endings = {
            enable = true;
            args = [ "--fix=lf" ];
            after = [ "treefmt" ];
            excludes = [ "^secrets/.*\\.age$" ];
          };

          check-merge-conflicts.enable = true;
          check-symlinks.enable = true;

          detect-private-keys.enable = true;

          check-case-conflicts.enable = true;
          check-added-large-files.enable = true;
          check-executables-have-shebangs.enable = true;
          check-shebang-scripts-are-executable = {
            enable = true;
            # Rust inner attributes start with `#![` and are not script shebangs.
            excludes = [ "^nix-seal/.*\\.rs$" ];
          };
          fix-byte-order-marker.enable = true;

          editorconfig-checker = {
            enable = true;
            excludes = [
              "^secrets/.*\\.age$"
              "^\\.gitmodules$"
              "^nix-config-framework/"
              "^nix-seal/"
              "^pkgs/"
            ];
          };
          typos = {
            enable = true;
            settings.configPath = ".typos.toml";
          };
          zizmor = {
            enable = true;
            args = [
              "--persona=pedantic"
              "--min-severity=medium"
            ];
          };
          gitleaks = {
            enable = true;
            name = "Gitleaks";
            entry = "${lib.getExe pkgs.gitleaks} git --pre-commit --staged --redact --no-banner";
            language = "system";
            always_run = true;
            pass_filenames = false;
          };

          check-json.enable = true;
          check-toml.enable = true;
          check-yaml.enable = true;

          flake-checker.enable = true;

          nix-flake-check = {
            enable = true;
            name = "nix flake check (local system)";
            entry = "${lib.getExe pkgs.nix} flake check";
            always_run = true;
            pass_filenames = false;
            stages = [ "pre-push" ];
          };
        };
      };
    };
  };

}
