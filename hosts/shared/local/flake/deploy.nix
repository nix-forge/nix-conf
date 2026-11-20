{ inputs, self, ... }:
let
  inherit (import ../network-topology.nix) raspberryPi;
  # The upstream Darwin activator embeds its own deploy-rs executable. Select
  # the host's guarded Darwin package fix there as well as in the home profile.
  deployDarwinPkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    overlays = [
      inputs.deploy-rs.overlays.default
      (_: prev: {
        deploy-rs = prev.deploy-rs // {
          deploy-rs = self.darwinConfigurations.macbook-pro-m4.pkgs.deploy-rs;
        };
      })
    ];
  };
  deployDarwinLib = deployDarwinPkgs.deploy-rs.lib;

in
{
  flake = {
    deploy.nodes.raspberry-pi = {
      hostname = raspberryPi.serverAddress;
      sshUser = "root";
      # Build the board's ARM derivations on desktop, admitting emulation
      # when needed. The Pi receives the finished outputs for activation.
      remoteBuild = false;
      # Copy the built closure directly. Destination substitution can pull
      # inputs from caches that the Pi intentionally does not trust.
      fastConnection = true;
      activationTimeout = 300;
      confirmTimeout = 120;
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.aarch64-linux.activate.nixos (
          self.lib.nixosConfigurationFor {
            name = "raspberry-pi";
            buildSystem = self.nixosConfigurations.desktop.pkgs.stdenv.hostPlatform.system;
          }
        );
      };
    };

    deploy.nodes.desktop = {
      hostname = "desktop";
      sshUser = "root";
      # Keep the full desktop closure off the Mac's native Linux builder.
      # deploy-rs evaluates locally, then asks the desktop to build and activate.
      remoteBuild = true;
      activationTimeout = 600;
      confirmTimeout = 120;

      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.desktop;
      };
    };

    deploy.nodes.macbook-pro-m4 = {
      hostname = "macbook";
      sshUser = "root";
      # The existing macbook alias supplies the desktop key and pinned host
      # key. sshUser selects root over that alias's ordinary user default.
      remoteBuild = true;
      activationTimeout = 600;
      # deploy-rs's confirmation watcher does not observe canary removal on
      # Darwin. Keep rollback on activation errors, without the timed watcher.
      magicRollback = false;

      profiles.system = {
        user = "root";
        path = deployDarwinLib.activate.darwin self.darwinConfigurations.macbook-pro-m4;
      };
    };
  };

  perSystem = { pkgs, ... }: {
    packages.deploy-rs = inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
