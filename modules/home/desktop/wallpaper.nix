{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  macShortcuts = config.keyboard.macosShortcuts.enable or false;
  desktopMod = if macShortcuts then "CTRL + ALT" else "SUPER";
  inherit ((import ../../../flake/runtime-packages.nix { inherit pkgs; })) wallpaperTools;
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  cfg = config.desktop.wallpaper;
  systemdUtils = import (pkgs.path + "/nixos/lib/utils.nix") {
    inherit lib pkgs;
    config = { };
  };
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  picturesDirectory =
    if config.xdg.userDirs.pictures != null then
      config.xdg.userDirs.pictures
    else
      "${config.home.homeDirectory}/Pictures";

  catalog = builtins.fromJSON (builtins.readFile ./wallpaper-catalog.json);
  policyDefaults = pkgs.writeText "wallpaper-preferences.json" (
    builtins.toJSON {
      connections = lib.mapAttrs (_: connection: connection.enable) cfg.connections;
      inherit (cfg) categories personal;
    }
  );
  wallpaperPolicy = writeShellApplication {
    name = "desktop-wallpaper-policy";
    text = ''
      ${lib.getExe' wallpaperTools "wallpaper-policy"} \
        --catalog ${./wallpaper-catalog.json} --config ${policyDefaults} \
        --preferences ${lib.escapeShellArg "${config.xdg.stateHome}/desktop-wallpaper/preferences.json"} "$@"
      case "''${1:-}" in
      connection | category | source | personal)
        ${lib.getExe' pkgs.systemd "systemctl"} --user start --no-block desktop-wallpaper-rotate.service || true
        ;;
      esac
    '';
  };
  # The small launcher follows the managed command file across activations.
  # Its interface stays stable while the policy and Nix defaults change.
  wallpaperSettings = writeShellApplication {
    name = "desktop-wallpaper-settings";
    text = ''
      # The configured, shell-quoted path can contain literal dollar signs.
      # shellcheck disable=SC2016
      exec ${lib.escapeShellArg "${config.xdg.configHome}/desktop-wallpaper/policy-command"} "$@"
    '';
  };
  sourceOverrides = lib.mapAttrs (
    _: _:
    lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Override this connection in this category; null inherits its parent. A globally disabled connection remains unavailable.";
    }
  ) catalog.connections;
  categoryOptions =
    leaves:
    {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include this category in downloads and rotation. Disabling a parent also disables all its subcategories.";
      };
      connections = sourceOverrides;
    }
    // lib.optionalAttrs (leaves != { }) {
      subcategories = lib.mapAttrs (_: _: categoryOptions { }) leaves;
    };
  astronomyOptions = {
    enable = lib.mkEnableOption "curated ESA observation wallpapers";
    interval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Calendar expression for bounded discovery, including newly published observations.";
    };
    maxCandidatePages = lib.mkOption {
      type = lib.types.ints.between 1 3;
      default = 1;
      description = "Maximum feed pages inspected per run; progress persists between runs.";
    };
    maxCandidateDownloads = lib.mkOption {
      type = lib.types.ints.between 1 3;
      default = 3;
      description = "Maximum original-image attempts per run; at most one wallpaper is installed.";
    };
    maxImages = lib.mkOption {
      type = lib.types.ints.between 1 120;
      default = 20;
      description = "Maximum retained wallpapers for this connection.";
    };
  };
  astronomyFetcher =
    name: connection:
    writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.curl
        pkgs.imagemagick
      ];
      text =
        myLib.templates.renderText
          {
            name = "fetch-wallpaper-collection.sh";
            text = ''
              # shellcheck shell=bash
              plan=$(mktemp)
              trap 'rm -f -- "$plan"' EXIT
              @lib_getExe_wallpaperPolicy@ plan @connection@ >"$plan"
              # Configuration paths are escaped literals, including dollar signs.
              # shellcheck disable=SC2016
              @fetchExecutable@ \
                --connection @connection@ --plan "$plan" \
                --directory @lib_escapeShellArg_cfg_directory@ \
                --state @lib_escapeShellArg_config_xdg_stateHome_desktop_wallpaper@ \
                --width @toString_cfg_rotation_width@ --height @toString_cfg_rotation_height@ \
                --max-images @toString_cfg_connections_connection_maxImages@ \
                --max-pages @toString_cfg_connections_connection_maxCandidatePages@ \
                --max-downloads @toString_cfg_connections_connection_maxCandidateDownloads@
            '';
          }
          {
            lib_getExe_wallpaperPolicy = lib.getExe wallpaperPolicy;
            inherit connection;
            fetchExecutable = lib.getExe' wallpaperTools "wallpaper-fetch-d2d";
            lib_escapeShellArg_cfg_directory = lib.escapeShellArg cfg.directory;
            lib_escapeShellArg_config_xdg_stateHome_desktop_wallpaper = lib.escapeShellArg "${config.xdg.stateHome}/desktop-wallpaper";
            toString_cfg_rotation_width = toString cfg.rotation.width;
            toString_cfg_rotation_height = toString cfg.rotation.height;
            toString_cfg_connections_connection_maxImages = toString cfg.connections.${connection}.maxImages;
            toString_cfg_connections_connection_maxCandidatePages =
              toString
                cfg.connections.${connection}.maxCandidatePages;
            toString_cfg_connections_connection_maxCandidateDownloads =
              toString
                cfg.connections.${connection}.maxCandidateDownloads;
          };
    };

  awwwOutputs = lib.concatStringsSep "," cfg.rotation.outputs;
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
  wallpaperChooser = writeBashTemplate {
    name = "desktop-wallpaper-next";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      export PATH="@runtimePath@"
      exec @executable@ @policy@ "$@"
    '';
    dir = "bin";
    replacements = {
      runtimePath = lib.makeBinPath [
        pkgs.awww
        pkgs.imagemagick
      ];
      executable = lib.getExe' wallpaperTools "wallpaper-next";
      policy = pkgs.writeText "wallpaper-rotation-policy.json" (
        builtins.toJSON {
          inherit (cfg) directory;
          state = "${config.xdg.stateHome}/desktop-wallpaper";
          policyCommand = lib.getExe wallpaperPolicy;
          width = cfg.rotation.width;
          height = cfg.rotation.height;
          minAspectRatioScaled = builtins.div (cfg.rotation.width * 990) cfg.rotation.height;
          maxAspectRatioScaled = builtins.div (cfg.rotation.width * 1010) cfg.rotation.height;
          outputs = awwwOutputs;
          transition = cfg.rotation.transition;
          transitionDuration = toString cfg.rotation.transitionDuration;
          transitionFps = toString cfg.rotation.transitionFps;
        }
      );
    };
  };

  wallpaperImporter = writeShellApplication {
    name = "desktop-wallpaper-add";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.file
    ];
    inheritPath = false;
    text = ''
      exec ${lib.getExe' wallpaperTools "wallpaper-add"} ${lib.escapeShellArg cfg.directory} "$@"
    '';
  };
  wikimediaCommonsFetcher =
    name: connection:
    writeBashTemplate {
      inherit name;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        export PATH="@runtimePath@"
        exec @executable@ @policy@ "$@"
      '';
      dir = "bin";
      replacements = {
        runtimePath = lib.makeBinPath [
          pkgs.curl
          pkgs.file
          pkgs.imagemagick
        ];
        executable = lib.getExe' wallpaperTools "wallpaper-fetch-commons";
        policy = pkgs.writeText "wallpaper-commons-policy.json" (
          builtins.toJSON {
            inherit (cfg) directory;
            state = "${config.xdg.stateHome}/desktop-wallpaper";
            policyCommand = lib.getExe wallpaperPolicy;
            quality = catalog.commonsQuality;
            maxCandidatePages = cfg.connections.${connection}.maxCandidatePages;
            maxCandidateDownloads = cfg.connections.${connection}.maxCandidateDownloads;
            licenses = cfg.connections.${connection}.licenses;
            width = cfg.rotation.width;
            height = cfg.rotation.height;
            userAgent = cfg.connections.${connection}.userAgent;
            maxFileSizeBytes = cfg.connections.${connection}.maxFileSizeMiB * 1024 * 1024;
            maxImages = cfg.connections.${connection}.maxImages;
          }
        );
      };
    };

  wikimediaCommonsOptions = {
    enable = lib.mkEnableOption "a daily, bounded Wikimedia Commons photography wallpaper fetch";

    maxCandidatePages = lib.mkOption {
      type = lib.types.ints.between 1 10;
      default = 3;
      description = "Maximum sequential category pages scanned per fetch. Continuation is saved between runs so rejected or cached files cannot trap discovery on the first page.";
    };

    maxCandidateDownloads = lib.mkOption {
      type = lib.types.ints.between 1 5;
      default = 3;
      description = "Maximum original-image download attempts per fetch; at most one accepted wallpaper is installed.";
    };

    licenses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "CC0"
        "Public domain"
        "Public Domain"
      ];
      description = "Exact accepted Commons LicenseShortName values. Attribution, licence URL and source metadata are retained beside each cropped derivative.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd calendar expression for the low-frequency Wikimedia Commons fetch.";
    };

    userAgent = lib.mkOption {
      type = lib.types.str;
      default = "nix-conf-wallpaper/1.0 (https://github.com/nix-forge/nix-conf)";
      description = "Descriptive User-Agent sent to the Wikimedia API.";
    };

    maxFileSizeMiB = lib.mkOption {
      type = lib.types.ints.between 5 512;
      default = 150;
      description = "Maximum accepted Commons original-image size, in MiB. This matches the other wallpaper sources so a source does not silently lower image quality.";
    };

    maxImages = lib.mkOption {
      type = lib.types.ints.between 1 120;
      default = 30;
      description = "Maximum Commons images retained in the local private cache.";
    };
  };

  # Install every reviewed connection so runtime switches also work when the
  # declarative default is off. An empty effective plan performs no network I/O.
  # Keep the source order for serial seeding.
  fetchers =
    map
      (
        source:
        let
          name = "desktop-wallpaper-fetch-${source.slug}";
        in
        source
        // {
          inherit name;
          package = source.build name source.connection;
        }
      )
      [
        {
          connection = "wikimediaCommons";
          slug = "wikimedia-commons";
          label = "Wikimedia Commons";
          build = wikimediaCommonsFetcher;
          options = wikimediaCommonsOptions;
        }
        {
          connection = "esaHubble";
          slug = "esa-hubble";
          label = "ESA/Hubble";
          build = astronomyFetcher;
          options = astronomyOptions;
        }
        {
          connection = "esaWebb";
          slug = "esa-webb";
          label = "ESA/Webb";
          build = astronomyFetcher;
          options = astronomyOptions;
        }
      ];
  fetcherUnits = map (fetcher: "${fetcher.name}.service") fetchers;
  fetcherTimeoutMinutes = 5;

  wallpaperSeed = writeBashTemplate {
    name = "desktop-wallpaper-seed";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      export PATH="@runtimePath@"

      # Run each source serially. The source services retain their individual
      # sandbox, network policy, image validation, and cache limits.
      source_units=(@sourceUnits@)
      for source_unit in "''${source_units[@]}"; do
        for _ in $(seq 1 @initialFetches@); do
          # A source can legitimately reject an oversized or non-wallpaper asset.
          # Continue seeding the other source libraries in that case.
          @systemctl@ --user start "$source_unit" || true
        done
      done
    '';
    dir = "bin";
    replacements = {
      systemctl = lib.getExe' pkgs.systemd "systemctl";
      runtimePath = lib.makeBinPath [ pkgs.coreutils ];
      sourceUnits = lib.concatStringsSep " " (map lib.escapeShellArg fetcherUnits);
      initialFetches = toString cfg.initialFetches;
    };
  };
in
{
  options.desktop.wallpaper = {
    enable = lib.mkEnableOption "a local, Wayland-native wallpaper experience";

    mode = lib.mkOption {
      type = lib.types.enum [
        "static"
        "rotate"
        "video"
      ];
      default = "rotate";
      description = ''
        static uses Hyprpaper, rotate uses awww with a timed local collection,
        and video uses mpvpaper. Only one renderer is started at a time.
      '';
    };

    outputs = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        { DP-1 = ./wallpaper.png; }
      '';
      description = "Static-mode image paths keyed by Hyprland output name.";
    };

    directory = lib.mkOption {
      type = lib.types.str;
      default = "${picturesDirectory}/Wallpapers";
      defaultText = "The configured XDG Pictures directory, falling back to ~/Pictures, plus /Wallpapers.";
      example = "/mnt/media/wallpapers";
      description = ''
        Local rotating-wallpaper collection. Populate it with 4K SDR PNG,
        JPEG, WebP, AVIF, or GIF files; no network downloader runs in the
        background.
      '';
    };

    fitMode = lib.mkOption {
      type = lib.types.enum [
        "contain"
        "cover"
        "tile"
        "fill"
      ];
      default = "cover";
      description = "How Hyprpaper scales static images.";
    };

    rotation = {
      width = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3840;
        description = "Minimum wallpaper width and downloaded derivative width. Rotation accepts only images within one percent of the configured width-to-height ratio.";
      };

      height = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2160;
        description = "Minimum wallpaper height and downloaded derivative height.";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "30min";
        example = "1h";
        description = "Systemd duration between wallpaper changes.";
      };

      outputs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "DP-1"
          "HDMI-A-1"
        ];
        description = "Outputs changed together; an empty list changes every output.";
      };

      transition = lib.mkOption {
        type = lib.types.enum [
          "none"
          "simple"
          "fade"
          "left"
          "right"
          "top"
          "bottom"
          "wipe"
          "wave"
          "grow"
          "center"
          "any"
          "outer"
          "random"
        ];
        default = "fade";
        description = "The awww transition used only at change time.";
      };

      transitionDuration = lib.mkOption {
        type = lib.types.numbers.between 0.1 10.0;
        default = 0.8;
        description = "Duration, in seconds, of the non-static awww transition.";
      };

      transitionFps = lib.mkOption {
        type = lib.types.ints.between 1 120;
        default = 30;
        description = "Frame rate cap for the brief wallpaper transition.";
      };
    };

    video = {
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/alice/Videos/ambient-4k.webm";
        description = "Local video file for video mode. Remote URLs are intentionally unsupported.";
      };

      output = lib.mkOption {
        type = lib.types.str;
        default = "ALL";
        description = "mpvpaper output selector, such as ALL or DP-1.";
      };

      pauseWhenHidden = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Ask mpvpaper to pause when a fullscreen window hides the background.";
      };
    };

    categories = lib.mapAttrs (_: category: categoryOptions category.subcategories) catalog.categories;
    personal = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include manually imported images without a source connection, subject to the display geometry checks.";
    };
    connections = builtins.listToAttrs (
      map (fetcher: lib.nameValuePair fetcher.connection fetcher.options) fetchers
    );

    initialFetches = lib.mkOption {
      type = lib.types.ints.between 0 8;
      default = 2;
      description = ''
        Number of serial fetch attempts per enabled source when the graphical
        session starts. This seeds a usable local rotation library without an
        unbounded bulk download. Set to 0 to disable session seeding.
      '';
    };

  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = isLinux;
            message = "desktop.wallpaper is supported on Linux only.";
          }
          {
            assertion = cfg.mode != "static" || cfg.outputs != { };
            message = "desktop.wallpaper static mode requires at least one output-to-image mapping.";
          }
          {
            assertion = lib.hasPrefix "/" cfg.directory;
            message = "desktop.wallpaper.directory must be an absolute path.";
          }
          {
            assertion = cfg.mode != "video" || cfg.video.path != null;
            message = "desktop.wallpaper video mode requires desktop.wallpaper.video.path.";
          }
          {
            assertion =
              !(lib.any (connection: connection.enable) (lib.attrValues cfg.connections)) || cfg.mode == "rotate";
            message = "Wallpaper connections require rotate mode.";
          }
        ];

        xdg.configFile."desktop-wallpaper/policy-command".source = lib.getExe wallpaperPolicy;
        home.packages = [
          wallpaperChooser
          wallpaperImporter
          wallpaperSettings
        ];
      }

      (lib.mkIf (cfg.mode == "static") {
        xdg.configFile."hypr/hyprpaper.conf".text = lib.hm.generators.toHyprconf {
          importantPrefixes = [
            "splash"
            "ipc"
          ];
          attrs = {
            splash = false;
            ipc = "on";
            wallpaper = lib.mapAttrsToList (output: path: {
              monitor = output;
              path = toString path;
              fit_mode = cfg.fitMode;
            }) cfg.outputs;
          };
        };

        systemd.user.services.hyprpaper = {
          Unit = {
            Description = "Hyprpaper static wallpaper service";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe pkgs.hyprpaper;
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })

      (lib.mkIf (cfg.mode == "rotate") {
        wayland.windowManager.hyprland.settings.bind =
          lib.mkIf config.wayland.windowManager.hyprland.enable
            (
              lib.mkAfter [
                (hyprBind "${desktopMod} + SHIFT + W" "${lib.getExe' pkgs.systemd "systemctl"} --user start desktop-wallpaper-rotate.service")
              ]
            );

        systemd.user = {
          services.desktop-wallpaper-directories = {
            Unit = {
              Description = "Create private desktop wallpaper directories";
              PartOf = [ "graphical-session.target" ];
              Before = [ "desktop-wallpaper-rotate.service" ];
            };
            Service = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = systemdUtils.escapeSystemdExecArgs [
                (lib.getExe' pkgs.coreutils "install")
                "-d"
                "-m"
                "0700"
                "--"
                cfg.directory
                "${config.xdg.stateHome}/desktop-wallpaper"
              ];
              UMask = "0077";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

          services.awww = {
            Unit = {
              Description = "Awww Wayland wallpaper daemon";
              PartOf = [ "graphical-session.target" ];
              After = [ "graphical-session.target" ];
            };
            Service = {
              # The daemon sends READY=1 after creating its IPC listener.
              Type = "notify";
              ExecStart = "${lib.getExe' pkgs.awww "awww-daemon"} --quiet";
              # The daemon invokes the client by name to restore cached images.
              Environment = [ "PATH=${lib.makeBinPath [ pkgs.awww ]}" ];
              TimeoutStartSec = 30;
              Restart = "on-failure";
              RestartSec = 2;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

          services.desktop-wallpaper-rotate = {
            Unit = {
              Description = "Select the next local desktop wallpaper";
              # Preference changes are explicit requests, not a restart loop.
              StartLimitIntervalSec = 0;
              PartOf = [ "graphical-session.target" ];
              After = [
                # The renderer starts after the session target. Without this
                # edge, the target implicitly orders itself after rotation
                # and creates a cycle through awww.service.
                "graphical-session.target"
                "awww.service"
                "desktop-wallpaper-directories.service"
              ];
              Requires = [
                "awww.service"
                "desktop-wallpaper-directories.service"
              ];
            };
            Service = {
              Type = "oneshot";
              ExecStart = lib.getExe' wallpaperChooser "desktop-wallpaper-next";
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

          timers.desktop-wallpaper-rotate = {
            Unit.Description = "Rotate the local desktop wallpaper";
            Timer = {
              OnUnitActiveSec = cfg.rotation.interval;
              Persistent = false;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      })

      (lib.mkIf (cfg.mode == "rotate") {
        home.packages = map (fetcher: fetcher.package) fetchers;

        systemd.user = {
          services = builtins.listToAttrs (
            map (
              fetcher:
              lib.nameValuePair fetcher.name {
                Unit = {
                  Description = "Fetch one reviewed ${fetcher.label} wallpaper";
                  After = [
                    "network-online.target"
                    "awww.service"
                    "desktop-wallpaper-directories.service"
                  ];
                  Wants = [ "awww.service" ];
                  Requires = [ "desktop-wallpaper-directories.service" ];
                };
                Service = {
                  Type = "oneshot";
                  ExecStart = lib.getExe' fetcher.package fetcher.name;
                  TimeoutStartSec = "${toString fetcherTimeoutMinutes}min";
                  UMask = "0077";
                  NoNewPrivileges = true;
                  PrivateTmp = true;
                  ProtectHome = "read-only";
                  ProtectSystem = "strict";
                  ReadWritePaths = [
                    cfg.directory
                    "${config.xdg.stateHome}/desktop-wallpaper"
                  ];
                  RestrictAddressFamilies = [
                    "AF_UNIX"
                    "AF_INET"
                    "AF_INET6"
                  ];
                };
              }
            ) fetchers
          );

          timers = builtins.listToAttrs (
            map (
              fetcher:
              lib.nameValuePair fetcher.name {
                Unit.Description = "Fetch a new ${fetcher.label} wallpaper at low frequency";
                Timer = {
                  OnCalendar = cfg.connections.${fetcher.connection}.interval;
                  RandomizedDelaySec = "2h";
                  Persistent = true;
                };
                Install.WantedBy = [ "graphical-session.target" ];
              }
            ) fetchers
          );
        };
      })

      (lib.mkIf (cfg.mode == "rotate" && fetcherUnits != [ ] && cfg.initialFetches > 0) {
        systemd.user = {
          services.desktop-wallpaper-seed = {
            Unit = {
              Description = "Seed the local desktop wallpaper library";
              After = [
                "network-online.target"
                "desktop-wallpaper-directories.service"
              ];
              Requires = [ "desktop-wallpaper-directories.service" ];
            };
            Service = {
              Type = "oneshot";
              ExecStart = lib.getExe' wallpaperSeed "desktop-wallpaper-seed";
              TimeoutStartSec = "${
                toString (cfg.initialFetches * builtins.length fetcherUnits * fetcherTimeoutMinutes + 1)
              }min";
              UMask = "0077";
            };
          };

          timers.desktop-wallpaper-seed = {
            Unit.Description = "Seed desktop wallpapers after graphical-session startup";
            Timer = {
              OnActiveSec = "15s";
              Unit = "desktop-wallpaper-seed.service";
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      })

      (lib.mkIf (cfg.mode == "video") {
        systemd.user.services.mpvpaper = {
          Unit = {
            Description = "mpvpaper animated wallpaper service";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = systemdUtils.escapeSystemdExecArgs (
              [ (lib.getExe pkgs.mpvpaper) ]
              ++ lib.optionals cfg.video.pauseWhenHidden [
                "--auto-pause"
                "FULL"
              ]
              ++ [
                "--mpv-options"
                "no-config no-audio loop hwdec=auto-safe profile=fast"
                cfg.video.output
                cfg.video.path
              ]
            );
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ]
  );
}
