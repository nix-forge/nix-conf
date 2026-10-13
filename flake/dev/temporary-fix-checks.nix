{ inputs, self, ... }: {
  perSystem =
    { pkgs, ... }:
    let
      hyprlandPackages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
      patchedHyprland =
        (import ../../overlays/temporary/hyprland-subsurface.nix { }).apply
          hyprlandPackages.hyprland;
      determinatePackage = import ../../tests/nix/determinate-module.nix { inherit pkgs inputs; };
      # Evaluation covers all supported platforms without building foreign
      # packages or moving the desktop closure to another builder.
      results = builtins.listToAttrs (
        map
          (system: {
            name = system;
            value = import ../../tests/nix/temporary-fixes.nix {
              inherit inputs;
              pkgs = import inputs.nixpkgs {
                inherit system;
                config.allowUnfree = true;
              };
            };
          })
          [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
          ]
      );
    in
    {
      checks = {
        temporary-package-fixes = builtins.deepSeq results (
          pkgs.runCommand "temporary-package-fixes" { } ''
            touch "$out"
          ''
        );
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        swift-hardening = import ../../tests/nix/swift-hardening.nix {
          pkgs = self.darwinConfigurations.macbook-pro-m4.pkgs;
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
        sentry-crashpad-lock = determinatePackage.tests.crashpad-lock;
        sentry-crashpad-lock-lifecycle =
          pkgs.runCommand "sentry-crashpad-lock-lifecycle"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.patch
                pkgs.python3
              ];
            }
            ''
              python3 ${../../overlays/temporary/tests/crashpad-lock-lifecycle.py} \
                ${determinatePackage.tests.crashpad-lock.src} \
                ${../../overlays/temporary/patches/apply-crashpad-lock.sh} \
                ${../../overlays/temporary/patches/sentry-crashpad-lock.patch}
              touch "$out"
            '';
      }
      // pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
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
