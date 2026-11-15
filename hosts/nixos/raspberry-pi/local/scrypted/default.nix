{ config, inputs, ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../../../shared/local/network.json);
  personal = inputs.nixpkgs-personal;
in
{
  services.scrypted = {
    enable = true;
    package = personal.packages.aarch64-linux.scrypted-server;
    nodePackage = personal.legacyPackages.aarch64-linux.nodejs_24;
    listenAddress = network.raspberryPiServerAddress;
    uiUsernameFile = config.nixSeal.secrets.scrypted-ui-username.path;
    uiPasswordFile = config.nixSeal.secrets.scrypted-ui-password.path;
  };

  systemd.services.scrypted = {
    after = [ "nix-seal-activate.service" ];
    requires = [ "nix-seal-activate.service" ];
    serviceConfig = {
      MemoryHigh = "1024M";
      MemoryMax = "1280M";
    };
  };
}
