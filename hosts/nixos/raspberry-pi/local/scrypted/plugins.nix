{ config, inputs, ... }:
let
  personal = inputs.nixpkgs-personal.packages.aarch64-linux;
  arlo = personal.scrypted-plugin-arlo;
  homekit = personal.scrypted-plugin-homekit;
in
{
  services.scrypted.plugins = [
    {
      name = "@scrypted/webrtc";
      version = "0.2.89";
      source = "npm";
    }
    {
      name = "@scrypted/snapshot";
      version = "0.2.68";
      source = "npm";
    }
    {
      name = "@scrypted/prebuffer-mixin";
      version = "0.10.70";
      source = "npm";
    }
    {
      name = "@scrypted/arlo";
      inherit (arlo) version;
      source = "local";
      path = "${arlo}/share/scrypted/plugins/@scrypted/arlo";
    }
    {
      name = "@scrypted/homekit";
      inherit (homekit) version;
      source = "local";
      path = "${homekit}/share/scrypted/plugins/@scrypted/homekit";
    }
  ];

  systemd.services.scrypted-plugins = {
    after = [ "nix-seal-activate.service" ];
    requires = [ "nix-seal-activate.service" ];
  };
  assertions = [
    {
      assertion = config.services.scrypted.enable;
      message = "Pinned Scrypted plugins require the Scrypted service.";
    }
  ];
}
