{
  config,
  lib,
  pkgs,
  ...
}:
let
  yamlFormat = pkgs.formats.yaml { };

  normalizedServices =
    let
      raw = config.services.homepage-dashboard.services;
    in
    if builtins.isList raw then
      raw
    else if builtins.isAttrs raw then
      lib.mapAttrsToList (group: entries: { "${group}" = entries; }) raw
    else
      [ ];
in
{
  config = {
    services.homepage-dashboard = {
      openFirewall = lib.mkDefault false;
      settings = {
        target = lib.mkDefault "_self";
        quicklaunch = {
          searchDescriptions = lib.mkDefault true;
          hideInternetSearch = lib.mkDefault true;
          provider = lib.mkDefault "duckduckgo";
        };
      };
      widgets = lib.mkDefault [ ];
    };

    environment.etc."homepage-dashboard/services.yaml".source =
      lib.mkIf config.services.homepage-dashboard.enable (
        lib.mkForce (yamlFormat.generate "services.yaml" normalizedServices)
      );
  };
}
