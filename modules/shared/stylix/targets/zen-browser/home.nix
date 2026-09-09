{
  homeManager = { config, lib, ... }: {
    key = "nix-conf/stylix/zen-browser/homeManager";
    _file = __curPos.file;
    config =
      lib.mkIf
        (
          config.stylix.enable
          && config.stylix.targets.zen-browser.enable
          && config.programs.zen-browser.enable
        )
        {
          stylix.targets.zen-browser = {
            profileNames = lib.mkDefault [ "default" ];
          };
        };
  };
}
