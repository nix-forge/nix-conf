{ lib, ... }: {
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.pre-commit.settings) enabledPackages package shellHook;
    in
    {
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
