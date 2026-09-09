{
  homeManager =
    { config, lib, ... }:
    let
      cfg = config.stylix.targets.firefox;
    in
    {
      key = "nix-conf/stylix/firefox/homeManager";
      _file = __curPos.file;
      config = lib.mkIf (config.stylix.enable && cfg.enable && config.programs.firefox.enable) {
        stylix.targets.firefox = {
          profileNames = lib.mkDefault [ "default" ];
          colorTheme.enable = lib.mkDefault true;
        };
        # Firefox Color is managed extension data for each themed profile.
        programs.firefox.profiles = lib.genAttrs cfg.profileNames (_: {
          extensions.force = lib.mkDefault true;
        });
      };
    };
}
