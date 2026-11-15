{ inputs, lib, ... }: {
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.pre-commit.settings) enabledPackages package shellHook;
      probePython = import ./quality-python.nix { pkgs = pkgs.buildPackages; };
      javascriptTools = import ./javascript-tools.nix { pkgs = pkgs.buildPackages; };
    in
    {
      # Hook validation needs the configured tools, not the interactive shell's
      # built seal CLI. Native secret-template checks exercise that binary.
      devShells.tests = pkgs.buildPackages.mkShellNoCC {
        PYTEST_DISABLE_PLUGIN_AUTOLOAD = "1";
        NIX_TEST_NIXPKGS = inputs.nixpkgs.outPath;
        NIX_TEST_FRAMEWORK = inputs.nix-config-framework.outPath;
        packages = [
          (import ./test-python.nix { pkgs = pkgs.buildPackages; })
        ]
        ++ (with pkgs.buildPackages; [
          bash
          coreutils
          curl
          dbus
          file
          findutils
          imagemagick
          gawk
          git
          gnugrep
          jq
          just
          libxml2
          nix
          openssh
          perl
          restic
          util-linux
        ])
        ++ lib.optionals pkgs.buildPackages.stdenv.hostPlatform.isLinux [ pkgs.buildPackages.systemd ];
      };
      devShells.ci = pkgs.buildPackages.mkShellNoCC {
        inherit shellHook;
        packages = enabledPackages ++ [
          package
          pkgs.buildPackages.git
          pkgs.buildPackages.gitleaks
        ];
      };
      devShells.default = pkgs.buildPackages.mkShellNoCC {
        inherit shellHook;
        LIBRARY_PATH = lib.optionalString pkgs.buildPackages.stdenv.hostPlatform.isDarwin "${pkgs.buildPackages.libiconv}/lib";
        NIX_LDFLAGS = lib.optionalString pkgs.buildPackages.stdenv.hostPlatform.isDarwin "-L${pkgs.buildPackages.libiconv}/lib";
        packages =
          enabledPackages
          ++ [
            package
            probePython
            javascriptTools
          ]
          ++ (with pkgs.buildPackages; [
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
            nodejs_24
            pinact
            prek
            rumdl
            rust-analyzer
            rustc
            rustfmt
            shellcheck
            shfmt
            statix
            stylelint
            swift-format
            taplo
            treefmt
            typos
            yamlfmt
            yamllint
            zizmor
            config.packages.nix-seal
            bashInteractive
          ])
          ++ lib.optionals pkgs.buildPackages.stdenv.hostPlatform.isDarwin [ pkgs.buildPackages.libiconv ];
      };
    };
}
