# Host policy for the reusable Nix Home Lab BookOrbit service. The shared
# module owns runtime confinement and source reconciliation; this host owns
# credentials, media paths, HTTPS admission, and backups.
{ config, lib, ... }:
let
  cfg = config.homelab.desktopBookDiscovery;
  storage = config.homelab.storage;
  vpn = config.homelab.vpn.namespace;
  secretNames = [
    "postgres-password"
    "jwt-secret"
    "setup-token"
    "request-key"
    "podcast-key"
    "admin-username"
    "admin-email"
    "admin-password"
  ];
  ready = lib.all (
    name: builtins.pathExists (../secrets + "/homelab-bookorbit-${name}.age")
  ) secretNames;
  secret = name: config.nixSeal.secrets."homelab-bookorbit-${name}".path;
in
{
  options.homelab.desktopBookDiscovery = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.homelab.desktopBooks.enable && ready;
      description = "Enable private BookOrbit discovery and approved-request fulfillment.";
    };
    shared = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Admit approved LAN and WireGuard clients to the HTTPS site.";
    };
  };

  config = lib.mkMerge [
    {
      homelab.desktopBookDiscovery.shared = true;
      nixSeal.secrets = lib.genAttrs (map (name: "homelab-bookorbit-${name}") secretNames) (_: {
        phase = "services";
      });
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.homelab.desktopBooks.enable && config.homelab.operations.lanHttps.enable;
          message = "BookOrbit requires the prepared book libraries and private HTTPS gateway.";
        }
      ];

      homelab.apps.bookorbit = {
        enable = true;
        native = true;
        databaseMajor = 18;
        uid = 910;
        gid = 910;
        port = 13006;
        https.allowedCIDRs =
          if cfg.shared then
            null
          else
            [
              "127.0.0.0/8"
              "${builtins.elemAt config.homelab.operations.lanHttps.listenAddresses 1}/32"
            ];
        credentials = lib.genAttrs secretNames secret;
        secretReadyUnit = "nix-seal-activate.service";
        readerReadyUnit = "homelab-books-bootstrap.service";
        storage = {
          inherit (storage)
            rootDir
            libraryDir
            group
            requiredMounts
            ;
          mediaDirs = [
            "${storage.libraryDir}/audiobooks"
            "${storage.libraryDir}/books"
          ];
          readyUnit = "homelab-storage.service";
        };
        prowlarr = {
          port = config.services.prowlarr.settings.server.port;
          apiKeyFile = config.nixSeal.secrets.homelab-prowlarr-api-key.path;
          readyUnit = "homelab-integrate-prowlarr.service";
          vpnTag = builtins.head config.homelab.integrations.prowlarr.proxies.vpn.tags;
          proxyName = config.homelab.integrations.prowlarr.proxies.vpn.name;
          proxyHost = vpn.bindAddress;
          proxyPort = config.homelab.indexerProxy.port;
        };
        acquisition = {
          enable = true;
          downloadDir = "${storage.downloadsDir}/torrents/bookorbit/downloads";
          dockDir = "${storage.downloadsDir}/torrents/bookorbit/dock";
          writableMediaDirs = [
            "${storage.libraryDir}/audiobooks"
            "${storage.libraryDir}/books"
          ];
          usernameFile = config.nixSeal.secrets.homelab-qbittorrent-username.path;
          passwordFile = config.nixSeal.secrets.homelab-qbittorrent-password.path;
          destinations = {
            audiobook = "Audiobooks";
            ebook = "Books and comics";
          };
        };
        libraries = [
          {
            name = "Audiobooks";
            icon = "Headphones";
            folder = "/books/audiobooks";
            formats = [
              "m4b"
              "mp3"
              "m4a"
              "opus"
              "ogg"
              "flac"
            ];
            organizationMode = "book_per_folder";
          }
          {
            name = "Books and comics";
            icon = "BookOpen";
            folder = "/books/books";
            formats = [
              "epub"
              "pdf"
              "cbz"
              "cbr"
              "cb7"
            ];
            organizationMode = "book_per_file";
          }
        ];
      };

      homelab.apps.qbittorrent.configuration.categories.bookorbit.savePath =
        config.homelab.apps.bookorbit.acquisition.downloadDir;

      hardware.storage.encryptedRoot.backup.paths = [
        config.homelab.apps.bookorbit.stateDir
        config.homelab.apps.bookorbit.acquisition.dockDir
      ];
    })
  ];
}
