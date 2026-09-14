{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  cfg = config.desktop.wallpaper;
  systemdUtils = import (pkgs.path + "/nixos/lib/utils.nix") {
    inherit lib pkgs;
    config = { };
  };
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  picturesDirectory = config.xdg.userDirs.pictures;

  catalog = builtins.fromJSON (builtins.readFile ./wallpaper-catalog.json);
  policyDefaults = pkgs.writeText "wallpaper-preferences.json" (
    builtins.toJSON {
      connections = lib.mapAttrs (_: connection: connection.enable) cfg.connections;
      inherit (cfg) categories personal;
    }
  );
  wallpaperPolicy = pkgs.writeShellApplication {
    name = "desktop-wallpaper-policy";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      python3 ${./scripts/wallpaper-policy.py} \
        --catalog ${./wallpaper-catalog.json} --config ${policyDefaults} \
        --preferences ${lib.escapeShellArg "${config.xdg.stateHome}/desktop-wallpaper/preferences.json"} "$@"
      case "''${1:-}" in
        connection|category|source|personal)
          ${lib.getExe' pkgs.systemd "systemctl"} --user start --no-block desktop-wallpaper-rotate.service || true
          ;;
      esac
    '';
  };
  # The small launcher follows the managed command file across activations.
  # Its interface stays stable while the policy and Nix defaults change.
  wallpaperSettings = pkgs.writeShellApplication {
    name = "desktop-wallpaper-settings";
    text = ''
      exec "''${XDG_CONFIG_HOME:-$HOME/.config}/desktop-wallpaper/policy-command" "$@"
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
  astronomyFetchers = lib.genAttrs [ "esaHubble" "esaWebb" ] (
    connection:
    let
      slug = if connection == "esaHubble" then "esa-hubble" else "esa-webb";
    in
    pkgs.writeShellApplication {
      name = "desktop-wallpaper-fetch-${slug}";
      runtimeInputs = [
        pkgs.python3
        pkgs.curl
        pkgs.imagemagick
      ];
      text = ''
        plan=$(mktemp)
        trap 'rm -f -- "$plan"' EXIT
        ${lib.getExe wallpaperPolicy} plan ${connection} > "$plan"
        # Configuration paths are escaped literals, including dollar signs.
        # shellcheck disable=SC2016
        python3 ${./scripts/wallpaper-fetch-d2d.py} \
          --connection ${connection} --plan "$plan" \
          --directory ${lib.escapeShellArg cfg.directory} \
          --state ${lib.escapeShellArg "${config.xdg.stateHome}/desktop-wallpaper"} \
          --width ${toString cfg.rotation.width} --height ${toString cfg.rotation.height} \
          --max-images ${toString cfg.connections.${connection}.maxImages} \
          --max-pages ${toString cfg.connections.${connection}.maxCandidatePages} \
          --max-downloads ${toString cfg.connections.${connection}.maxCandidateDownloads}
      '';
    }
  );
  # Install every reviewed connection so runtime switches also work when the
  # declarative default is off. An empty effective plan performs no network I/O.
  fetcherUnits = [
    "desktop-wallpaper-fetch-wikimedia-commons.service"
    "desktop-wallpaper-fetch-esa-hubble.service"
    "desktop-wallpaper-fetch-esa-webb.service"
  ];

  awwwOutputs = lib.concatStringsSep "," cfg.rotation.outputs;
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
  wallpaperChooser = writeBashTemplate {
    name = "desktop-wallpaper-next";
    src = ./scripts/wallpaper-next.sh.in;
    dir = "bin";
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [
        pkgs.awww
        pkgs.coreutils
        pkgs.findutils
        pkgs.imagemagick
      ];
      minWidth = toString cfg.rotation.width;
      minHeight = toString cfg.rotation.height;
      minAspectRatioScaled = toString (builtins.div (cfg.rotation.width * 990) cfg.rotation.height);
      maxAspectRatioScaled = toString (builtins.div (cfg.rotation.width * 1010) cfg.rotation.height);
      policyCommand = lib.getExe wallpaperPolicy;
      wallpaperDirectory = lib.escapeShellArg cfg.directory;
      stateDirectory = lib.escapeShellArg "${config.xdg.stateHome}/desktop-wallpaper";
      awwwOutputs = lib.optionalString (awwwOutputs != "") "--outputs ${lib.escapeShellArg awwwOutputs}";
      transition = cfg.rotation.transition;
      transitionDuration = toString cfg.rotation.transitionDuration;
      transitionFps = toString cfg.rotation.transitionFps;
    };
  };
  wallpaperImporter = pkgs.writeShellApplication {
    name = "desktop-wallpaper-add";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.file
    ];
    inheritPath = false;
    text = ''
      # Configuration values are literals, including dollar signs.
      # shellcheck disable=SC2016
      destination_directory=${lib.escapeShellArg cfg.directory}
    ''
    + builtins.readFile ./scripts/wallpaper-add.sh;
  };
  wallpaperDirectories = writeBashTemplate {
    name = "desktop-wallpaper-directories";
    src = ./scripts/wallpaper-directories.sh.in;
    dir = "bin";
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [ pkgs.coreutils ];
      wallpaperDirectory = lib.escapeShellArg cfg.directory;
      stateDirectory = lib.escapeShellArg "${config.xdg.stateHome}/desktop-wallpaper";
    };
  };
  wikimediaCommonsFetcher = writeBashTemplate {
    name = "desktop-wallpaper-fetch-wikimedia-commons";
    src = ./scripts/wallpaper-fetch-wikimedia-commons.sh.in;
    dir = "bin";
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.file
        pkgs.findutils
        pkgs.imagemagick
        pkgs.jq
        pkgs.util-linux
      ];
      wallpaperDirectory = lib.escapeShellArg cfg.directory;
      stateDirectory = lib.escapeShellArg "${config.xdg.stateHome}/desktop-wallpaper";
      qualityJson = lib.escapeShellArg (builtins.toJSON catalog.commonsQuality);
      categoriesJson = "\"$(${lib.getExe wallpaperPolicy} plan wikimediaCommons)\"";
      maxCandidatePages = toString cfg.connections.wikimediaCommons.maxCandidatePages;
      maxCandidateDownloads = toString cfg.connections.wikimediaCommons.maxCandidateDownloads;
      licensesJson = lib.escapeShellArg (builtins.toJSON cfg.connections.wikimediaCommons.licenses);
      targetWidth = toString cfg.rotation.width;
      targetHeight = toString cfg.rotation.height;
      userAgent = lib.escapeShellArg cfg.connections.wikimediaCommons.userAgent;
      maxFileSizeBytes = toString (cfg.connections.wikimediaCommons.maxFileSizeMiB * 1024 * 1024);
      maxImages = toString cfg.connections.wikimediaCommons.maxImages;
    };
  };
  wallpaperSeed = writeBashTemplate {
    name = "desktop-wallpaper-seed";
    src = ./scripts/wallpaper-seed.sh.in;
    dir = "bin";
    replacements = {
      bash = lib.getExe pkgs.bash;
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
      defaultText = lib.literalExpression ''"${config.xdg.userDirs.pictures}/Wallpapers"'';
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
    connections.esaHubble = astronomyOptions;
    connections.esaWebb = astronomyOptions;
    connections.wikimediaCommons = {
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
        default = "nix-conf-wallpaper/1.0 (https://github.com/ianmh/nix-conf)";
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
            assertion = config.xdg.userDirs.enable;
            message = "desktop.wallpaper requires xdg.userDirs for its predictable default collection path.";
          }
          {
            assertion = cfg.mode != "static" || cfg.outputs != { };
            message = "desktop.wallpaper static mode requires at least one output-to-image mapping.";
          }
          {
            assertion = cfg.mode != "rotate" || cfg.directory != "";
            message = "desktop.wallpaper rotate mode requires a local collection directory.";
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
                (hyprBind "SUPER + SHIFT + W" "${lib.getExe' pkgs.systemd "systemctl"} --user start desktop-wallpaper-rotate.service")
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
              ExecStart = lib.getExe' wallpaperDirectories "desktop-wallpaper-directories";
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
        home.packages = [ wikimediaCommonsFetcher ];

        systemd.user = {
          services.desktop-wallpaper-fetch-wikimedia-commons = {
            Unit = {
              Description = "Fetch one reviewed Wikimedia Commons wallpaper";
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
              ExecStart = lib.getExe' wikimediaCommonsFetcher "desktop-wallpaper-fetch-wikimedia-commons";
              ExecStartPost = "${lib.getExe' pkgs.systemd "systemctl"} --user start --no-block desktop-wallpaper-rotate.service";
              TimeoutStartSec = "5min";
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
          };

          timers.desktop-wallpaper-fetch-wikimedia-commons = {
            Unit.Description = "Fetch a new Wikimedia Commons wallpaper at low frequency";
            Timer = {
              OnCalendar = cfg.connections.wikimediaCommons.interval;
              RandomizedDelaySec = "2h";
              Persistent = true;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      })

      (lib.mkIf (cfg.mode == "rotate") {
        home.packages = [ astronomyFetchers.esaHubble ];

        systemd.user = {
          services.desktop-wallpaper-fetch-esa-hubble = {
            Unit = {
              Description = "Fetch one reviewed ESA/Hubble wallpaper";
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
              ExecStart = lib.getExe' astronomyFetchers.esaHubble "desktop-wallpaper-fetch-esa-hubble";
              ExecStartPost = "${lib.getExe' pkgs.systemd "systemctl"} --user start --no-block desktop-wallpaper-rotate.service";
              TimeoutStartSec = "5min";
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
          };

          timers.desktop-wallpaper-fetch-esa-hubble = {
            Unit.Description = "Fetch a new ESA/Hubble wallpaper at low frequency";
            Timer = {
              OnCalendar = cfg.connections.esaHubble.interval;
              RandomizedDelaySec = "2h";
              Persistent = true;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      })

      (lib.mkIf (cfg.mode == "rotate") {
        home.packages = [ astronomyFetchers.esaWebb ];

        systemd.user = {
          services.desktop-wallpaper-fetch-esa-webb = {
            Unit = {
              Description = "Fetch one reviewed ESA/Webb wallpaper";
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
              ExecStart = lib.getExe' astronomyFetchers.esaWebb "desktop-wallpaper-fetch-esa-webb";
              ExecStartPost = "${lib.getExe' pkgs.systemd "systemctl"} --user start --no-block desktop-wallpaper-rotate.service";
              TimeoutStartSec = "5min";
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
          };

          timers.desktop-wallpaper-fetch-esa-webb = {
            Unit.Description = "Fetch a new ESA/Webb wallpaper at low frequency";
            Timer = {
              OnCalendar = cfg.connections.esaWebb.interval;
              RandomizedDelaySec = "2h";
              Persistent = true;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
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
              TimeoutStartSec = "${toString (cfg.initialFetches * builtins.length fetcherUnits * 5 + 1)}min";
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
