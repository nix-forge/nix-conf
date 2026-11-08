{
  inputs,
  config,
  lib,
  ...
}:
let
  host = config.nixConfigFramework.inventory.hosts.nixos.raspberry-pi;
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
  perSystem = { pkgs, ... }: {
    packages.raspberry-pi-provision =
      inputs.nixos-anywhere.packages.${pkgs.stdenv.hostPlatform.system}.default;
    packages.raspberry-pi-deploy = inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
