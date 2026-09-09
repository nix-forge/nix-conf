{
  homeManager =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      theme = (import ./theme.nix).render { inherit (config.appearance) theme; };
    in
    {
      key = "nix-conf/stylix/chromium/homeManager";
      _file = __curPos.file;
      options.stylix.targets.browser-suite.enable =
        config.lib.stylix.mkEnableTarget "browser suite Web Store themes" true;
      config = lib.optionalAttrs (options.programs ? browserSuite) (
        lib.mkIf (config.stylix.enable && config.stylix.targets.browser-suite.enable && theme != null) {
          programs.browserSuite.chromium.heliumExtensions = lib.mkOptionDefault { ${theme.name} = theme.id; };
        }
      );
    };
}
