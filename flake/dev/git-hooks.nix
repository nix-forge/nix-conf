{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    { config, pkgs, ... }:
    let
      pythonCompileAll = pkgs.replaceVarsWith {
        name = "python-compileall";
        src = ./scripts/python-compileall.sh;
        isExecutable = true;
        replacements = {
          bash = lib.getExe pkgs.bash;
          python = lib.getExe pkgs.python3;
        };
      };
    in
    {
      pre-commit = {
        check.enable = pkgs.stdenv.hostPlatform.isDarwin;
        settings = {
          # A path flake includes a linked worktree's `.git` pointer.  The check
          # creates its own isolated repository, so carrying that pointer into
          # the sandbox makes Git escape to a non-existent external gitdir.
          # Filter only standard VCS/generated metadata; all candidate source,
          # including untracked files, remains part of the exact path input.
          rootSrc = lib.mkForce (lib.cleanSource inputs.self.outPath);
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
              # Point at the repository configuration explicitly and keep this
              # validation read-only. Automatic Ruff fixes belong in an explicit
              # developer command, not a Nix-backed verification derivation.
              entry = "${lib.getExe pkgs.ruff} check --no-fix --config pyproject.toml .";
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ruff-format = {
              enable = true;
              name = "ruff format";
              entry = "${lib.getExe pkgs.ruff} format --check --config pyproject.toml .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff" ];
            };
            ty = {
              enable = true;
              name = "ty";
              package = pkgs.ty;
              # `--project .` forces discovery of this repository's [tool.ty]
              # table rather than relying on the caller's current environment.
              entry = "${lib.getExe pkgs.ty} check --project . --python ${lib.getExe pkgs.python3}";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff-format" ];
            };
            python-compile = {
              enable = true;
              name = "python compileall";
              entry = toString pythonCompileAll;
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ty" ];
            };
            local-control-rustfmt = {
              enable = true;
              name = "local-control rustfmt";
              entry = "cargo fmt --manifest-path homes/macbook-pro-m4/support/local-control/secure-files-rs/Cargo.toml --all -- --check";
              language = "system";
              extraPackages = [
                pkgs.cargo
                pkgs.rustfmt
              ];
              files = "^homes/macbook-pro-m4/support/local-control/secure-files-rs/.*\\.(rs|toml)$";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            local-control-rust-clippy = {
              enable = true;
              name = "local-control Clippy";
              # Cargo invoked outside the development shell cannot find
              # Darwin's libiconv. Keep the hook in the same toolchain and
              # linker environment developers use for local Rust checks.
              entry = "nix develop --command cargo clippy --manifest-path homes/macbook-pro-m4/support/local-control/secure-files-rs/Cargo.toml --all-targets -- -D warnings";
              language = "system";
              extraPackages = [
                pkgs.cargo
                pkgs.clippy
              ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "local-control-rustfmt" ];
            };
            local-control-rust-test = {
              enable = true;
              name = "local-control Rust tests";
              entry = "nix develop --command cargo test --manifest-path homes/macbook-pro-m4/support/local-control/secure-files-rs/Cargo.toml --all-targets";
              language = "system";
              extraPackages = [ pkgs.cargo ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "local-control-rust-clippy" ];
            };
            swift-format = {
              enable = true;
              name = "swift-format";
              entry = "${lib.getExe pkgs.swift-format} lint --strict";
              language = "system";
              extraPackages = [ pkgs.swift-format ];
              files = "^modules/home/macos/.*\\.swift$";
              after = [ "treefmt" ];
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
              excludes = [
                "^nix-seal/.*\\.rs$"
                "^homes/macbook-pro-m4/support/local-control/secure-files-rs/.*\\.rs$"
                # Each submodule owns and verifies its own hook configuration.
                "^nix-seal/"
                "^nix-config-framework/"
                "^pkgs/"
              ];
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
