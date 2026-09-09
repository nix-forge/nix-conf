let
  module =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      cfg = config.programs.chromiumPolicies;
      theme = (import ./theme.nix).render { inherit (config.appearance) theme; };
    in
    {
      key = "nix-conf/stylix/chromium/system";
      _file = __curPos.file;
      options.stylix.targets.chromium-policies.enable =
        config.lib.stylix.mkEnableTarget "managed Chromium Web Store themes" true;
      config = lib.optionalAttrs (options.programs ? chromiumPolicies) (
        lib.mkIf
          (
            config.stylix.enable
            && config.stylix.targets.chromium-policies.enable
            && cfg.enable
            && theme != null
          )
          {
            programs.chromiumPolicies = {
              heliumExtensions = lib.mkOptionDefault { ${theme.name} = theme.id; };
              targets.google-chrome.policies = {
                ExtensionInstallForcelist = [ "${theme.id};${cfg.extensionUpdateUrl}" ];
                ExtensionSettings.${theme.id} = {
                  installation_mode = "force_installed";
                  update_url = cfg.extensionUpdateUrl;
                };
              };
            };
          }
      );
    };
in
{
  nixos = module;
  darwin = module;
}
