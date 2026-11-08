# Audiobook playback and EPUB/PDF/comic reading on the private media mount.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  names = [
    "homelab-books-audiobookshelf-admin-username"
    "homelab-books-audiobookshelf-admin-password"
    "homelab-books-audiobookshelf-reader-username"
    "homelab-books-audiobookshelf-reader-password"
    "homelab-books-komga-admin-username"
    "homelab-books-komga-admin-password"
    "homelab-books-komga-reader-username"
    "homelab-books-komga-reader-password"
  ];
  ready = lib.all (name: builtins.pathExists (../secrets + "/${name}.age")) names;
  secret = name: config.nixSeal.secrets."homelab-books-${name}".path;
  books = "${config.homelab.storage.libraryDir}/books";
  audiobooks = "${config.homelab.storage.libraryDir}/audiobooks";
  isolated = {
    IPAddressDeny = [ "any" ];
    IPAddressAllow = [
      "127.0.0.0/8"
      "::1/128"
    ];
    BindReadOnlyPaths = [
      "${pkgs.writeText "books-no-host-dns-resolv.conf" "nameserver 127.0.0.2\n"}:/etc/resolv.conf"
      "${pkgs.writeText "books-no-host-dns-nsswitch.conf" "hosts: files dns\n"}:/etc/nsswitch.conf"
    ];
    InaccessiblePaths = [
      "-/run/systemd/resolve/io.systemd.Resolve"
      "-/run/systemd/resolve/io.systemd.Resolve.Monitor"
      "-/run/nscd"
      "-/run/dbus/system_bus_socket"
      "-/var/run/dbus/system_bus_socket"
    ];
  };
  bootstrap = pkgs.writers.writePython3Bin "bootstrap-books" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./scripts/bootstrap_books.py);
in
{
  options.homelab.desktopBooks.enable = lib.mkOption {
    type = lib.types.bool;
    default = ready;
    description = "Enable private book services after their sealed credentials exist.";
  };
  options.homelab.desktopBooks.komgaScanInterval = lib.mkOption {
    type = lib.types.enum [
      "DISABLED"
      "HOURLY"
      "EVERY_6H"
      "EVERY_12H"
      "DAILY"
      "WEEKLY"
    ];
    default = "HOURLY";
    description = "How often Komga scans the shared ebook and comic library for files added outside Komga.";
  };

  config = lib.mkMerge [
    {
      nixSeal.secrets = lib.genAttrs names (_: {
        phase = "services";
        restartUnits = [
          "homelab-integrate-audiobookshelf.service"
          "homelab-books-bootstrap.service"
        ];
      });
    }
    (lib.mkIf config.homelab.desktopBooks.enable {
      assertions = [
        {
          assertion =
            config.services.audiobookshelf.host == "127.0.0.1"
            && config.services.komga.settings.server.address == "127.0.0.1"
            && !config.services.audiobookshelf.openFirewall
            && !config.services.komga.openFirewall
            && config.homelab.integration.enable;
          message = "Book services must bind loopback and keep their native HTTP ports closed.";
        }
        {
          assertion =
            lib.all
              (
                name:
                let
                  policy = config.systemd.services.${name}.serviceConfig;
                in
                policy.IPAddressDeny == [ "any" ]
                && lib.all (path: builtins.elem path policy.BindReadOnlyPaths) isolated.BindReadOnlyPaths
                && lib.all (path: builtins.elem path policy.InaccessiblePaths) isolated.InaccessiblePaths
              )
              [
                "audiobookshelf"
                "komga"
                "homelab-books-bootstrap"
              ];
          message = "Book services must block public IP and host DNS paths.";
        }
        {
          assertion =
            builtins.elem config.homelab.storage.libraryDir config.systemd.services.komga.serviceConfig.BindReadOnlyPaths
            && config.services.komga.group == config.homelab.storage.group
            && builtins.elem books config.systemd.services.komga.unitConfig.RequiresMountsFor;
          message = "Komga must read the mounted library through the shared media group.";
        }
      ];

      homelab.apps.audiobookshelf.enable = true;
      homelab.optional.apps.komga.enable = true;
      # The operations inventory covers application databases. The desktop's
      # existing Restic job also needs the media files for a usable restore.
      hardware.storage.encryptedRoot.backup.paths = [
        books
        audiobooks
      ];
      homelab.integration.services.audiobookshelf = {
        url = "http://127.0.0.1:${toString config.services.audiobookshelf.port}";
        mode = "managed";
        settings = {
          login = {
            username = {
              _secret = secret "audiobookshelf-admin-username";
            };
            password = {
              _secret = secret "audiobookshelf-admin-password";
            };
          };
          libraries.Audiobooks = {
            folders = [ { fullPath = audiobooks; } ];
            mediaType = "book";
            icon = "audiobooks";
          };
          users.reader = {
            username = {
              _secret = secret "audiobookshelf-reader-username";
            };
            password = {
              _secret = secret "audiobookshelf-reader-password";
            };
            type = "user";
            isActive = true;
            permissions = {
              download = true;
              upload = false;
              update = false;
              delete = false;
              accessAllLibraries = true;
              accessAllTags = true;
            };
          };
        };
      };

      # AudioMuse already owns port 8000 on the desktop.
      services.audiobookshelf.port = 13378;
      services.audiobookshelf.openFirewall = false;
      services.komga.openFirewall = false;
      systemd.tmpfiles.settings."10-komga".${config.services.komga.stateDir}.d.mode = "0700";
      systemd.services.audiobookshelf.serviceConfig = isolated // {
        StateDirectoryMode = "0700";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        MemoryMax = "2G";
        TasksMax = 128;
      };
      systemd.services.komga = {
        after = [ "homelab-storage.service" ];
        requires = [ "homelab-storage.service" ];
        unitConfig.RequiresMountsFor = config.homelab.storage.requiredMounts ++ [ books ];
        serviceConfig = isolated // {
          StateDirectoryMode = "0700";
          BindReadOnlyPaths = isolated.BindReadOnlyPaths ++ [ config.homelab.storage.libraryDir ];
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectHome = true;
          ProtectSystem = lib.mkForce "strict";
          PrivateTmp = true;
          PrivateDevices = true;
          MemoryMax = "3G";
          TasksMax = 128;
        };
      };

      systemd.services.homelab-books-bootstrap = {
        description = "Claim Komga and prepare private book accounts";
        wantedBy = [
          "multi-user.target"
          "komga.service"
          "audiobookshelf.service"
        ];
        bindsTo = [
          "komga.service"
          "audiobookshelf.service"
        ];
        partOf = [ "homelab-integrate-audiobookshelf.service" ];
        after = [
          "komga.service"
          "audiobookshelf.service"
          "homelab-integrate-audiobookshelf.service"
          "nix-seal-activate.service"
        ];
        requires = [
          "komga.service"
          "audiobookshelf.service"
          "homelab-integrate-audiobookshelf.service"
          "nix-seal-activate.service"
        ];
        unitConfig.RequiresMountsFor = config.homelab.storage.requiredMounts ++ [ books ];
        serviceConfig = isolated // {
          Type = "oneshot";
          ExecStart = "${bootstrap}/bin/bootstrap-books ${toString config.services.komga.settings.server.port} ${toString config.services.audiobookshelf.port} ${lib.escapeShellArg books} ${lib.escapeShellArg config.homelab.desktopBooks.komgaScanInterval}";
          LoadCredential = [
            "komga-admin-username:${secret "komga-admin-username"}"
            "komga-admin-password:${secret "komga-admin-password"}"
            "komga-reader-username:${secret "komga-reader-username"}"
            "komga-reader-password:${secret "komga-reader-password"}"
          ];
          RuntimeDirectory = "homelab-books";
          RuntimeDirectoryMode = "0755";
          RemainAfterExit = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          MemoryMax = "96M";
          TasksMax = 16;
          TimeoutStartSec = "3min";
          Restart = "on-failure";
          RestartSec = "30s";
        };
      };

      homelab.operations.lanHttps.sites = {
        audiobookshelf = {
          upstream = "http://127.0.0.1:${toString config.services.audiobookshelf.port}";
          streaming = true;
        };
        komga = {
          upstream = "http://127.0.0.1:${toString config.services.komga.settings.server.port}";
          streaming = true;
        };
      };
      # The first account on either service can claim an empty database. Keep
      # both HTTPS sites closed until the local integration has completed.
      services.nginx.virtualHosts."audiobookshelf.${config.homelab.operations.lanHttps.domain}".locations."/".extraConfig =
        lib.mkAfter ''
          access_log off;
          if (!-f /run/homelab-books/ready) { return 503; }
        '';
      services.nginx.virtualHosts."komga.${config.homelab.operations.lanHttps.domain}".locations."/".extraConfig =
        lib.mkAfter ''
          access_log off;
          if (!-f /run/homelab-books/ready) { return 503; }
        '';
    })
    (lib.mkIf config.homelab.desktopBooks.enable {
      systemd.services =
        lib.genAttrs
          (map (name: "restic-backups-desktop-${name}") (
            builtins.attrNames config.hardware.storage.encryptedRoot.backup.destinations
          ))
          (_: {
            unitConfig.RequiresMountsFor = config.homelab.storage.requiredMounts;
          });
    })
  ];
}
