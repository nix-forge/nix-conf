{ inputs, lib, ... }: {
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.pre-commit.settings) enabledPackages package shellHook;
    in
    {
      # Hook validation needs the configured tools, not the interactive shell's
      # built seal CLI. Native secret-template checks exercise that binary.
      devShells.tests = pkgs.mkShellNoCC {
        PYTEST_DISABLE_PLUGIN_AUTOLOAD = "1";
        NIX_TEST_NIXPKGS = inputs.nixpkgs.outPath;
        NIX_TEST_FRAMEWORK = inputs.nix-config-framework.outPath;
        packages = [
          (import ./test-python.nix { inherit pkgs; })
        ]
        ++ (with pkgs; [
          bash
          coreutils
          gawk
          git
          gnugrep
          jq
          libxml2
          nix
          openssh
          perl
          restic
        ]);
      };
      devShells.ci = pkgs.mkShellNoCC {
        inherit shellHook;
        packages = enabledPackages ++ [
          package
          pkgs.git
          pkgs.gitleaks
        ];
      };
      devShells.default = pkgs.mkShellNoCC {
        inherit shellHook;
        LIBRARY_PATH = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "${pkgs.libiconv}/lib";
        NIX_LDFLAGS = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "-L${pkgs.libiconv}/lib";
        packages =
          enabledPackages
          ++ [ package ]
          ++ (with pkgs; [
            actionlint
            cargo
            cargo-audit
            cargo-deny
            clippy
            deadnix
            direnv
            editorconfig-checker
            gitleaks
            keep-sorted
            just
            nh
            nixd
            nixf-diagnose
            nixfmt
            pinact
            prettier
            prek
            rumdl
            rust-analyzer
            rustc
            rustfmt
            shellcheck
            shfmt
            statix
            taplo
            treefmt
            typos
            yamlfmt
            yamllint
            zizmor
            config.packages.nix-seal
            bashInteractive
          ])
          ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ];
      };
    };
}
