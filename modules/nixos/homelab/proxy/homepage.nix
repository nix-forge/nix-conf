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
        "Home & Security" = {
          style = "row";
          columns = 2;
          icon = "vaultwarden.png";
        };
        Operations = {
          style = "row";
          columns = 3;
          icon = "mdi-server-outline";
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
    services = [
      {
        Media = [
          {
            Jellyfin = {
              icon = "jellyfin.png";
              href = "/jellyfin/";
              description = "Stream the main library with the Tailscale cert in front.";
            };
          }
          {
            Jellyseerr = {
              icon = "seerr.png";
              href = "/jellyseerr/";
              description = "Requests and discovery, proxied through the single tailnet origin.";
            };
          }
        ];
      }
      {
        Automation = [
          {
            Sonarr = {
              icon = "sonarr.png";
              href = "/sonarr/";
              description = "Series intake and release automation.";
            };
          }
          {
            Radarr = {
              icon = "radarr.png";
              href = "/radarr/";
              description = "Movie collection and upgrade flow.";
            };
          }
          {
            Lidarr = {
              icon = "lidarr.png";
              href = "/lidarr/";
              description = "Music acquisition and metadata cleanup.";
            };
          }
          {
            Readarr = {
              icon = "readarr.png";
              href = "/readarr/";
              description = "Books and audiobooks pipeline.";
            };
          }
          {
            Bazarr = {
              icon = "bazarr.png";
              href = "/bazarr/";
              description = "Subtitle fetching for the existing media stack.";
            };
          }
          {
            Prowlarr = {
              icon = "prowlarr.png";
              href = "/prowlarr/";
              description = "Indexer management behind localhost-only services.";
            };
          }
        ];
      }
      {
        Downloads = [
          {
            qBittorrent = {
              icon = "qbittorrent.png";
              href = "/qbittorrent/";
              description = "Torrent client pinned to Mullvad with reverse-proxy support enabled.";
            };
          }
          {
            NZBGet = {
              icon = "nzbget.png";
              href = "/nzbget/";
              description = "Usenet queue and unpacking path, still loopback-only.";
            };
          }
        ];
      }
      {
        "Home & Security" = [
          {
            Frigate = {
              icon = "frigate.png";
              href = "/frigate/";
              description = "Cameras, review, and event browsing from the same origin.";
            };
          }
          {
            Vaultwarden = {
              icon = "vaultwarden.png";
              href = "/vaultwarden/";
              description = "Password vault administration and client access over Tailscale.";
            };
          }
        ];
      }
    ];
    bookmarks = [
      {
        Operations = [
          {
            Tailscale = [
              {
                abbr = "TS";
                href = "https://login.tailscale.com/admin/machines";
              }
            ];
          }
          {
            Repository = [
              {
                abbr = "GH";
                href = "https://github.com/ianmh/nix-conf-server";
              }
            ];
          }
          {
            NixOS = [
              {
                abbr = "NX";
                href = "https://search.nixos.org/options";
              }
            ];
          }
        ];
      }
    ];
    customCSS = ''
      body {
        background:
          radial-gradient(circle at top left, rgba(214, 137, 86, 0.26), transparent 32%),
          radial-gradient(circle at bottom right, rgba(102, 62, 32, 0.14), transparent 28%),
          linear-gradient(135deg, #f7f1e6 0%, #eadfcb 100%) !important;
      }

      main {
        max-width: min(1500px, calc(100vw - 32px));
      }

      .service,
      .bookmark,
      .information-widget {
        border-radius: 22px !important;
        border: 1px solid rgba(104, 77, 48, 0.14) !important;
        box-shadow: 0 18px 60px rgba(62, 38, 16, 0.08) !important;
      }

      .service {
        backdrop-filter: blur(16px);
      }

      .service-name,
      .bookmark-name,
      .information-widget .label {
        letter-spacing: -0.02em;
      }

      .service-description {
        color: rgba(76, 58, 42, 0.82) !important;
        line-height: 1.5;
      }

      [data-name="Media"] h2,
      [data-name="Automation"] h2,
      [data-name="Downloads"] h2,
      [data-name="Home & Security"] h2,
      [data-name="Operations"] h2 {
        font-weight: 700;
      }
    '';
  };
}
