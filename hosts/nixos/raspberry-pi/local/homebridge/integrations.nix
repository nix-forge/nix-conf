{ config, inputs, ... }:
let
  personal = inputs.nixpkgs-personal.packages.aarch64-linux;
in
{
  nixSeal.secrets.homebridge-vesync-username = {
    phase = "services";
    restartUnits = [ "homebridge.service" ];
  };
  nixSeal.secrets.homebridge-vesync-password = {
    phase = "services";
    restartUnits = [ "homebridge.service" ];
  };

  services.homebridge.managedUi.vesync = {
    usernameFile = config.nixSeal.secrets.homebridge-vesync-username.path;
    passwordFile = config.nixSeal.secrets.homebridge-vesync-password.path;
  };
  services.homebridge.declarativePlugins = [
    personal.homebridge-lg-thinq-mp
    personal.homebridge-tsvesync
    personal.homebridge-blueair-purifier
    personal.homebridge-samsung-tizen
  ];
}
