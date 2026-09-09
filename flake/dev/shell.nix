{ lib, ... }: {
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.pre-commit.settings) enabledPackages package;
      shellHook = ''
        if ${lib.getExe' pkgs.git "git"} config --global --includes --get privacy.policyFile > /dev/null; then
          # prek refuses to install with a global hooksPath. Hide it only from
          # the installer subprocess, which writes the ordinary repository hooks.
          (
            export GIT_CONFIG_GLOBAL=/dev/null
            ${config.pre-commit.settings.shellHook}
          )
          # The global privacy hook forwards to these repository hooks. Remove
          # the installer's local override so it cannot bypass that guard.
          local_hooks="$(${lib.getExe' pkgs.git "git"} config --local --path --get core.hooksPath || true)"
          common_hooks="$(${lib.getExe' pkgs.git "git"} rev-parse --path-format=absolute --git-common-dir)/hooks"
          if test -n "$local_hooks" && test "$(${lib.getExe' pkgs.coreutils "realpath"} "$local_hooks")" = "$common_hooks"; then
            ${lib.getExe' pkgs.git "git"} config --local --unset-all core.hooksPath
          fi
          export PATH=${package}/bin:$PATH
        else
          ${config.pre-commit.settings.shellHook}
        fi
      '';
    in
    {
      # Hook validation needs the configured tools, not the interactive shell's
      # built seal CLI. Native secret-template checks exercise that binary.
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
