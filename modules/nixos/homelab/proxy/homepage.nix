{
  services.homepage-dashboard = {
    enable = true;
    openFirewall = false;
    settings = {
      title = "Home Server";
      description = "Tailnet control room for media, automation, downloads, and ops.";
      theme = "light";
      color = "amber";
      headerStyle = "boxedWidgets";
      iconStyle = "theme";
      target = "_self";
      fullWidth = true;
      maxGroupColumns = 6;
      useEqualHeights = true;
      disableCollapse = true;
      statusStyle = "dot";
      hideVersion = true;
      disableUpdateCheck = true;
      disableIndexing = true;
      quicklaunch = {
        searchDescriptions = true;
        hideInternetSearch = true;
        provider = "duckduckgo";
      };
      layout = {
        Media = {
          style = "row";
          columns = 2;
          icon = "jellyfin.png";
        };
        Automation = {
          style = "row";
          columns = 3;
          icon = "prowlarr.png";
        };
        Downloads = {
          style = "row";
          columns = 2;
          icon = "qbittorrent.png";
        };
        Apps = {
          style = "row";
          columns = 2;
          icon = "vaultwarden.png";
        };
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
}
