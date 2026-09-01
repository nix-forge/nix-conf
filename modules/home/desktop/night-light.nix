{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.nightLight;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  options.desktop.nightLight = {
    enable = lib.mkEnableOption "Hyprsunset colour-temperature filtering";

    temperature = lib.mkOption {
      type = lib.types.ints.between 1000 6500;
      default = 4500;
      description = "Target night colour temperature in kelvin.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.nightLight is supported on Linux only.";
      }
    ];

    systemd.user.services.hyprsunset = {
      Unit = {
        Description = "Hyprsunset colour-temperature filter";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe pkgs.hyprsunset} --temperature ${toString cfg.temperature}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
