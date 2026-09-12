{
  inputs,
  lib,
  myLib,
  ...
}:
{
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    { config, pkgs, ... }:
    let
      checkPython = import ./quality-python.nix { inherit pkgs; };
      pythonCompileAll = myLib.writers.writeBashTemplate { inherit pkgs; } {
        name = "python-compileall";
        src = ./scripts/python-compileall.sh;
        replacements = {
          bash = lib.getExe pkgs.bash;
          python = lib.getExe pkgs.python3;
          mktemp = lib.getExe' pkgs.coreutils "mktemp";
          rm = lib.getExe' pkgs.coreutils "rm";
        };
      };
    in
    {
      pre-commit = {
        check.enable = true;
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
              # treefmt schedules its formatters; avoid many concurrent wrappers.
              require_serial = true;
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
            oxlint = {
              enable = true;
              name = "Oxlint";
              entry = "${lib.getExe pkgs.oxlint} --config .oxlintrc.json --deny-warnings tests";
              language = "system";
              files = "^(tests/.*\\.[cm]?[jt]sx?$|\\.oxlintrc\\.json)$";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ruff = {
              enable = true;
              # Run at the repository root and respect nested project configs.
              # Validation must not apply automatic fixes.
              entry = "${lib.getExe pkgs.ruff} check --no-fix .";
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ruff-format = {
              enable = true;
              name = "ruff format";
              entry = "${lib.getExe pkgs.ruff} format --check .";
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
              entry = "${lib.getExe pkgs.ty} check --project . --python ${lib.getExe checkPython}";
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
              entry = "cargo fmt --manifest-path homes/macbook-pro-m4/local/local-control/secure-files-rs/Cargo.toml --all -- --check";
              language = "system";
              extraPackages = [
                pkgs.cargo
                pkgs.rustfmt
              ];
              files = "^homes/macbook-pro-m4/local/local-control/secure-files-rs/.*\\.(rs|toml)$";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            local-control-rust-clippy = {
              enable = pkgs.stdenv.hostPlatform.isDarwin;
              name = "local-control Clippy";
              # Cargo invoked outside the development shell cannot find
              # Darwin's libiconv. Keep the hook in the same toolchain and
              # linker environment developers use for local Rust checks.
              entry = "nix develop --command cargo clippy --manifest-path homes/macbook-pro-m4/local/local-control/secure-files-rs/Cargo.toml --all-targets -- -D warnings";
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
              enable = pkgs.stdenv.hostPlatform.isDarwin;
              name = "local-control Rust tests";
              entry = "nix develop --command cargo test --manifest-path homes/macbook-pro-m4/local/local-control/secure-files-rs/Cargo.toml --all-targets";
              language = "system";
              extraPackages = [ pkgs.cargo ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "local-control-rust-clippy" ];
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
                "^homes/macbook-pro-m4/local/local-control/secure-files-rs/.*\\.rs$"
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
                "\\.age$"
                "^docs/assets/hyprland-upstream-local-20260907/"
                "^nix-config-framework/"
                "^nix-seal/"
                "^pkgs/"
              ];
            };
            typos = {
              enable = true;
              # The upstream hook's generated empty [default] table overrides configPath.
              entry = "${lib.getExe pkgs.typos} --config .typos.toml --force-exclude";
            };
            zizmor = {
              enable = true;
              args = [ "--persona=pedantic" ];
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
              # Use the Nix installation that supplies the daemon and its settings.
              # Injecting nixpkgs' CLI rejects Determinate's schemas/settings.
              entry = "nix flake check";
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
            };
          };
        };
      };
    };

}
