{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.wallpaper;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  picturesDirectory = config.xdg.userDirs.pictures;

  renderedStaticWallpapers = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      output: path:
      builtins.readFile (
        pkgs.replaceVarsWith {
          name = "hyprpaper-wallpaper-entry";
          src = ./config/hyprpaper-wallpaper-entry.conf.in;
          replacements = {
            inherit output;
            path = toString path;
            inherit (cfg) fitMode;
          };
        }
      )
    ) cfg.outputs
  );

  awwwOutputs = lib.concatStringsSep "," cfg.rotation.outputs;
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
  wallpaperChooser = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-next";
    src = ./scripts/wallpaper-next.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [
        pkgs.awww
        pkgs.coreutils
        pkgs.findutils
      ];
      wallpaperDirectory = cfg.directory;
      stateDirectory = "${config.xdg.stateHome}/desktop-wallpaper";
      awwwOutputs = lib.optionalString (awwwOutputs != "") "--outputs ${lib.escapeShellArg awwwOutputs}";
      transition = cfg.rotation.transition;
      transitionDuration = toString cfg.rotation.transitionDuration;
      transitionFps = toString cfg.rotation.transitionFps;
    };
  };
  wallpaperImporter = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-add";
    src = ./scripts/wallpaper-add.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [
        pkgs.coreutils
        pkgs.file
      ];
      wallpaperDirectory = cfg.directory;
    };
  };
  nasaSvsFetcher = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-fetch-nasa";
    src = ./scripts/wallpaper-fetch-nasa.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.file
        pkgs.findutils
        pkgs.imagemagick
        pkgs.jq
      ];
      wallpaperDirectory = cfg.directory;
      stateDirectory = "${config.xdg.stateHome}/desktop-wallpaper";
      maxFileSizeBytes = toString (cfg.sources.nasaSvs.maxFileSizeMiB * 1024 * 1024);
      maxImages = toString cfg.sources.nasaSvs.maxImages;
      maxCandidatePages = toString cfg.sources.nasaSvs.maxCandidatePages;
    };
  };
  cmaFetcher = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-fetch-cma";
    src = ./scripts/wallpaper-fetch-cma.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.file
        pkgs.findutils
        pkgs.imagemagick
        pkgs.jq
      ];
      wallpaperDirectory = cfg.directory;
      stateDirectory = "${config.xdg.stateHome}/desktop-wallpaper";
      maxFileSizeBytes = toString (cfg.sources.clevelandMuseum.maxFileSizeMiB * 1024 * 1024);
      maxImages = toString cfg.sources.clevelandMuseum.maxImages;
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

    sources.nasaSvs = {
      enable = lib.mkEnableOption "a daily, bounded NASA Scientific Visualization Studio wallpaper fetch";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Systemd calendar expression for the low-frequency NASA SVS fetch.";
      };

      maxImages = lib.mkOption {
        type = lib.types.ints.between 1 120;
        default = 30;
        description = "Maximum NASA SVS images retained in the local private cache.";
      };

      maxCandidatePages = lib.mkOption {
        type = lib.types.ints.between 1 20;
        default = 5;
        description = "Maximum NASA SVS records inspected per fetch before giving up.";
      };

      maxFileSizeMiB = lib.mkOption {
        type = lib.types.ints.between 5 100;
        default = 35;
        description = "Maximum accepted source-image size, in MiB.";
      };
    };

    sources.clevelandMuseum = {
      enable = lib.mkEnableOption "a daily CC0 Cleveland Museum of Art 4K wallpaper fetch";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Systemd calendar expression for the low-frequency CMA fetch.";
      };

      maxFileSizeMiB = lib.mkOption {
        type = lib.types.ints.between 5 100;
        default = 60;
        description = "Maximum accepted CMA original-image size, in MiB.";
      };

      maxImages = lib.mkOption {
        type = lib.types.ints.between 1 120;
        default = 20;
        description = "Maximum CMA images retained in the local private cache.";
      };
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
            assertion = !cfg.sources.nasaSvs.enable || cfg.mode == "rotate";
            message = "desktop.wallpaper.sources.nasaSvs requires rotate mode so fetched images can be selected locally.";
          }
          {
            assertion = !cfg.sources.clevelandMuseum.enable || cfg.mode == "rotate";
            message = "desktop.wallpaper.sources.clevelandMuseum requires rotate mode so fetched images can be selected locally.";
          }
        ];

        home.packages = [
          wallpaperChooser
          wallpaperImporter
        ];
      }

      (lib.mkIf (cfg.mode == "static") {
        xdg.configFile."hypr/hyprpaper.conf".source = pkgs.replaceVarsWith {
          name = "hyprpaper-config";
          src = ./config/hyprpaper.conf.in;
          replacements.wallpapers = renderedStaticWallpapers;
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
                (hyprBind "SUPER + SHIFT + W" (lib.getExe' wallpaperChooser "desktop-wallpaper-next"))
              ]
            );

        systemd.user = {
          services.awww = {
            Unit = {
              Description = "Awww Wayland wallpaper daemon";
              PartOf = [ "graphical-session.target" ];
              After = [ "graphical-session.target" ];
            };
            Service = {
              ExecStart = "${lib.getExe' pkgs.awww "awww-daemon"} --quiet";
              Restart = "on-failure";
              RestartSec = 2;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

          services.desktop-wallpaper-rotate = {
            Unit = {
              Description = "Select the next local desktop wallpaper";
              After = [ "awww.service" ];
              Wants = [ "awww.service" ];
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

      (lib.mkIf cfg.sources.nasaSvs.enable {
        home.packages = [ nasaSvsFetcher ];

        systemd.user = {
          services.desktop-wallpaper-fetch-nasa = {
            Unit = {
              Description = "Fetch one validated NASA SVS 4K wallpaper";
              After = [
                "network-online.target"
                "awww.service"
              ];
              Wants = [ "awww.service" ];
            };
            Service = {
              Type = "oneshot";
              ExecStart = lib.getExe' nasaSvsFetcher "desktop-wallpaper-fetch-nasa";
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

          timers.desktop-wallpaper-fetch-nasa = {
            Unit.Description = "Fetch a new NASA SVS wallpaper at low frequency";
            Timer = {
              OnCalendar = cfg.sources.nasaSvs.interval;
              RandomizedDelaySec = "2h";
              Persistent = true;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

          timers.desktop-wallpaper-fetch-nasa-bootstrap = {
            Unit.Description = "Fetch the initial NASA SVS wallpaper for a new session";
            Timer = {
              OnActiveSec = "15s";
              Unit = "desktop-wallpaper-fetch-nasa.service";
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      })

      (lib.mkIf cfg.sources.clevelandMuseum.enable {
        home.packages = [ cmaFetcher ];

        systemd.user = {
          services.desktop-wallpaper-fetch-cma = {
            Unit = {
              Description = "Fetch one validated Cleveland Museum of Art 4K wallpaper";
              After = [
                "network-online.target"
                "awww.service"
              ];
              Wants = [ "awww.service" ];
            };
            Service = {
              Type = "oneshot";
              ExecStart = lib.getExe' cmaFetcher "desktop-wallpaper-fetch-cma";
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

          timers.desktop-wallpaper-fetch-cma = {
            Unit.Description = "Fetch a new Cleveland Museum of Art wallpaper at low frequency";
            Timer = {
              OnCalendar = cfg.sources.clevelandMuseum.interval;
              RandomizedDelaySec = "2h";
              Persistent = true;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

          timers.desktop-wallpaper-fetch-cma-bootstrap = {
            Unit.Description = "Fetch the initial Cleveland Museum of Art wallpaper for a new session";
            Timer = {
              OnActiveSec = "15s";
              Unit = "desktop-wallpaper-fetch-cma.service";
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
            ExecStart = lib.concatStringsSep " " [
              (lib.getExe pkgs.mpvpaper)
              (lib.optionalString cfg.video.pauseWhenHidden "--auto-pause FULL")
              "--mpv-options"
              (lib.escapeShellArg "no-config no-audio loop hwdec=auto-safe profile=fast")
              (lib.escapeShellArg cfg.video.output)
              (lib.escapeShellArg cfg.video.path)
            ];
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ]
  );
}
