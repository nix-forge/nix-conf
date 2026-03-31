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
  services.homepage-dashboard = {
    enable = true;
    openFirewall = false;
    settings = {
      title = lib.mkDefault "Homepage";
      description = lib.mkDefault "Service dashboard";
      theme = lib.mkDefault "light";
      color = lib.mkDefault "slate";
      headerStyle = lib.mkDefault "boxedWidgets";
      iconStyle = lib.mkDefault "theme";
      target = lib.mkDefault "_self";
      fullWidth = lib.mkDefault true;
      maxGroupColumns = lib.mkDefault 6;
      useEqualHeights = lib.mkDefault true;
      disableCollapse = lib.mkDefault true;
      statusStyle = lib.mkDefault "dot";
      hideVersion = lib.mkDefault true;
      disableUpdateCheck = lib.mkDefault true;
      disableIndexing = lib.mkDefault true;
      quicklaunch = {
        searchDescriptions = lib.mkDefault true;
        hideInternetSearch = lib.mkDefault true;
        provider = lib.mkDefault "duckduckgo";
      };
    };
    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = {
            timeStyle = "short";
            dateStyle = "medium";
          };
        };
      }
    ];
  };

  environment.etc."homepage-dashboard/services.yaml".source = lib.mkForce (
    yamlFormat.generate "services.yaml" normalizedServices
  );
}
