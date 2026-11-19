{
  inputs,
  config,
  lib,
  ...
}:
let
  host = config.nixConfigFramework.inventory.hosts.nixos.raspberry-pi;
  vendorCache = {
    url = "https://nixos-raspberrypi.cachix.org";
    key = "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=";
  };
  # The board-specific constructor intentionally preserves its native ARM
  # package set and does not attach the inventory's Home Manager profile.
  piSystem = inputs.nixpkgs.lib.nixosSystem {
    inherit (host) system;
    specialArgs = config.nixConfigFramework.extraSpecialArgs // {
      inherit inputs;
      inherit (inputs) nixos-raspberrypi;
    };
    modules = [
      { networking.hostName = host.hostName; }
    ]
    ++ inputs.nix-config-framework.lib.targetModules host;
  };
  installer = inputs.nixos-raspberrypi.nixosConfigurations.rpi4-installer.extendModules {
    modules = [
      ({ lib, ... }: {
        networking.hostName = "raspberry-pi-installer";
        users.users.root.openssh.authorizedKeys.keys = [
          (builtins.readFile ../../../nixos/raspberry-pi/local/keys/desktop.pub)
          (builtins.readFile ../../../nixos/raspberry-pi/local/keys/macbook.pub)
        ];
        services.openssh.settings = {
          PasswordAuthentication = lib.mkForce false;
          KbdInteractiveAuthentication = lib.mkForce false;
          PermitRootLogin = lib.mkForce "prohibit-password";
        };
      })
    ];
  };
in
{
  flake.nixosConfigurations.raspberry-pi = lib.mkForce piSystem;
  flake.packages.aarch64-linux.raspberry-pi-installer = installer.config.system.build.sdImage;
  perSystem = { myLib, pkgs, ... }: {
    packages.raspberry-pi-provision =
      inputs.nixos-anywhere.packages.${pkgs.stdenv.hostPlatform.system}.default;
    packages.raspberry-pi-operation = myLib.writers.writeShellApplication { inherit pkgs; } {
      name = "raspberry-pi-operation";
      text = ''
        mode="''${1:?expected build or deploy}"
        flake_root="''${2:?expected flake path}"

        case "$mode" in
        build) activation=(--dry-activate) ;;
        deploy) activation=() ;;
        *)
          echo "expected build or deploy, got: $mode" >&2
          exit 2
          ;;
        esac

        if [[ "$(hostname -s)" != desktop ]]; then
          echo "Build the Pi system on desktop, where the AArch64 builder is configured." >&2
          exit 1
        fi

        # Admit ARM emulation only for this Pi invocation, preserving existing platforms.
        # Keep the vendor cache available to deploy-rs's child Nix commands before
        # the updated desktop cache policy has been activated.
        export NIX_CONFIG="''${NIX_CONFIG:-}
        extra-extra-platforms = aarch64-linux
        extra-substituters = ${vendorCache.url}
        extra-trusted-public-keys = ${vendorCache.key}"

        kernel="$(nix eval --raw --accept-flake-config \
          "$flake_root#nixosConfigurations.raspberry-pi.config.boot.kernelPackages.kernel.outPath")"

        # Check the remote cache even when the path is already local, then copy its
        # signed output if needed. A cache miss must stop before the ARM build begins.
        nix path-info --store ${vendorCache.url} "$kernel" >/dev/null
        nix copy --from ${vendorCache.url} \
          --extra-trusted-public-keys \
          '${vendorCache.key}' \
          "$kernel"

        # The repository's focused checks and dry activation cover this target. The
        # default deploy-rs preflight evaluates unrelated desktop and Darwin checks.
        nix run --accept-flake-config "$flake_root#raspberry-pi-deploy" -- \
          --skip-checks "''${activation[@]}" "$flake_root#raspberry-pi"
      '';
    };
    packages.raspberry-pi-deploy = inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
