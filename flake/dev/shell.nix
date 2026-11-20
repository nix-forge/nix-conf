{ lib, inputs, ... }: {
  perSystem =
    {
      config,
      myLib,
      pkgs,
      ...
    }:
    let
      inherit (config.pre-commit.settings) enabledPackages package shellHook;
      rustWorkspaces = import ./rust-workspaces.nix {
        inherit myLib;
        pkgs = pkgs.buildPackages;
      };
      workspace = import ../rust-workspace.nix { pkgs = pkgs.buildPackages; };
      preferShellCargoTools = ''
        # Cargo prepends its home bin directory when it is absent from PATH.
        export PATH="$PATH:''${CARGO_HOME:-$HOME/.cargo}/bin"
      '';
      # rust-analyzer may invoke Cargo through a Rustup proxy. Give the proxy
      # a complete Nix toolchain rather than the rustc-only sysroot.
      rustToolchain = pkgs.buildPackages.symlinkJoin {
        name = "nix-conf-rust-toolchain";
        paths = with pkgs.buildPackages; [
          cargo
          rustc
          rustfmt
          clippy
        ];
      };
      rustTooling = import ./rust-tooling.nix {
        inherit myLib;
        pkgs = pkgs.buildPackages;
        rustOverlay = inputs.rust-overlay;
        inherit (config.devShells) ciRust;
      };
      javascriptTools = import ./javascript-tools.nix {
        inherit myLib;
        pkgs = pkgs.buildPackages;
      };
    in
    {
      # Warm the exact compiler/lint toolchain used by the Rust gate.
      devShells.ciRust = pkgs.buildPackages.mkShell {
        shellHook = preferShellCargoTools;
        RUSTUP_TOOLCHAIN = "${rustToolchain}";
        buildInputs =
          workspace.buildInputs
          ++ lib.optionals pkgs.buildPackages.stdenv.hostPlatform.isDarwin [ pkgs.buildPackages.libiconv ];
        packages = with pkgs.buildPackages; [
          cargo
          cargo-deny
          cargo-nextest
          rust-analyzer
          rustc
          rustfmt
          clippy
          pkg-config
          semgrep
          rustWorkspaces
        ];
      };
      devShells.rustAnalysis = rustTooling.rustAnalysis;
      devShells.rustVerification = rustTooling.rustVerification;
      devShells.ci = pkgs.buildPackages.mkShellNoCC {
        inherit shellHook;
        packages = enabledPackages ++ [
          package
          pkgs.buildPackages.git
          pkgs.buildPackages.gitleaks
        ];
      };
      devShells.default = pkgs.buildPackages.mkShell {
        shellHook = shellHook + preferShellCargoTools;
        RUSTUP_TOOLCHAIN = "${rustToolchain}";
        inherit (workspace) buildInputs;
        LIBRARY_PATH = lib.optionalString pkgs.buildPackages.stdenv.hostPlatform.isDarwin "${pkgs.buildPackages.libiconv}/lib";
        NIX_LDFLAGS = lib.optionalString pkgs.buildPackages.stdenv.hostPlatform.isDarwin "-L${pkgs.buildPackages.libiconv}/lib";
        packages =
          enabledPackages
          ++ [
            package
            javascriptTools
            rustWorkspaces
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
            nix-unit
            pinact
            pkg-config
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
