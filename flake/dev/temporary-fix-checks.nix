{ configurationInputs, self, ... }: {
  perSystem =
    { pkgs, configurationPkgs, ... }:
    let
      inputs = configurationInputs;
      hyprlandPackages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
      patchedHyprland =
        (import ../../overlays/temporary/hyprland-subsurface.nix { }).apply
          hyprlandPackages.hyprland;
      # Keep upstream gtests confined to native VM check packages.
      roundingHyprland =
        (configurationPkgs.extend (import ../../overlays { inherit inputs; })).hyprland.override
          { withTests = true; };
      roundingBaseline =
        (
          (import ../../overlays/temporary {
            inherit inputs;
            pkgs = configurationPkgs;
          }).apply
            "hyprland-subsurface"
            hyprlandPackages.hyprland
        ).override
          { withTests = true; };
      determinatePackage = import ../../tests/nix/determinate-module.nix {
        pkgs = configurationPkgs;
        inherit inputs;
      };
      sentryPackage = import ../../tests/nix/sentry/package.nix {
        inherit inputs;
        system = pkgs.stdenv.hostPlatform.system;
      };
      # Evaluation covers all supported platforms without building foreign
      # packages or moving the desktop closure to another builder.
      results = builtins.listToAttrs (
        map (system: {
          name = system;
          value = import ../../tests/nix/temporary-fixes.nix {
            inherit inputs;
            pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          };
        }) (import ../supported-systems.nix)
      );
    in
    {
      checks = {
        darwin-app-management-consent = import ../../tests/nix/app-management-consent.nix {
          inherit pkgs inputs;
        };
        azure-cli-invoke = import ../../tests/nix/azure-cli.nix { inherit pkgs inputs; };
        temporary-package-fixes = builtins.deepSeq results (
          pkgs.runCommand "temporary-package-fixes" { } (
            builtins.readFile ./scripts/complete-temporary-fix-check.sh
          )
        );
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        swift-hardening = import ../../tests/nix/swift-hardening.nix {
          pkgs = configurationPkgs.extend (import ../../overlays { inherit inputs; });
        };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        # Keep native compiler compatibility coverage after retiring the override.
        hyprland-portal-build =
          # NixOS owns the configured desktop portal; Home Manager delegates it.
          assert
            self.nixosConfigurations.desktop.config.home-manager.users.ianmh.wayland.windowManager.hyprland.finalPortalPackage
            == null;
          assert
            self.nixosConfigurations.desktop.config.programs.hyprland.portalPackage.drvPath
            == inputs.hyprland.packages.x86_64-linux.xdg-desktop-portal-hyprland.drvPath;
          assert hyprlandPackages.xdg-desktop-portal-hyprland.stdenv.cc.isGNU;
          hyprlandPackages.xdg-desktop-portal-hyprland;
        hyprland-subsurface-rounding = import ../../tests/hyprland/subsurface-rounding-vm.nix {
          inherit pkgs;
          hyprland =
            assert roundingHyprland.withTests;
            roundingHyprland;
        };
        hyprland-subsurface-rounding-baseline = import ../../tests/hyprland/subsurface-rounding-vm.nix {
          inherit pkgs;
          expectFailure = true;
          hyprland =
            assert roundingBaseline.withTests;
            roundingBaseline;
        };
        sentry-crashpad-lock = builtins.seq determinatePackage (
          (import ../../tests/nix/sentry/crashpad-lock.nix { inherit (pkgs) python3; }) sentryPackage
        );
      }
      // pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        jellyfin-plugin-compatibility = import ../../tests/nix/jellyfin-plugins.nix {
          inherit pkgs;
          desktop = self.nixosConfigurations.desktop;
          introChecker = ../../pkgs/pkgs/by-name/je/jellyfin-plugin-intro-skipper/check_jellyfin_plugin.py;
        };
        hyprland-parent-display = import ../../tests/hyprland/subsurface-parent-lifetime-vm.nix {
          inherit pkgs;
          unpatched = hyprlandPackages.hyprland;
          patched = hyprlandPackages.hyprland;
          parentOnly = true;
        };
        hyprland-subsurface-lifetime = import ../../tests/hyprland/subsurface-parent-lifetime-vm.nix {
          inherit pkgs;
          unpatched = hyprlandPackages.hyprland;
          patched = patchedHyprland;
        };
      };
    };
}
