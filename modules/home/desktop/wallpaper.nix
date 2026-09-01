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
      builtins.replaceStrings [ "@output@" "@path@" "@fitMode@" ] [ output (toString path) cfg.fitMode ] (
        builtins.readFile ./config/hyprpaper-wallpaper-entry.conf.in
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
  wallpaperDirectories = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-directories";
    src = ./scripts/wallpaper-directories.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [ pkgs.coreutils ];
      wallpaperDirectory = cfg.directory;
      stateDirectory = "${config.xdg.stateHome}/desktop-wallpaper";
    };
  };
  wallpaperNormalizer = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-normalize-sdr";
    src = ./scripts/wallpaper-normalize-sdr.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      runtimePath = lib.makeBinPath [
        pkgs.coreutils
        pkgs.imagemagick
      ];
      maxPixels = toString (7680 * 4320);
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
      normalizeSdr = lib.getExe' wallpaperNormalizer "desktop-wallpaper-normalize-sdr";
      keepOriginals = if cfg.sources.nasaSvs.keepOriginals then "1" else "0";
      queriesJson = lib.escapeShellArg (builtins.toJSON cfg.sources.nasaSvs.queries);
      rejectedTermsJson = lib.escapeShellArg (builtins.toJSON cfg.sources.nasaSvs.rejectedTerms);
    };
  };
  nasaImageLibraryFetcher = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-fetch-nasa-library";
    src = ./scripts/wallpaper-fetch-nasa-library.sh.in;
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
      maxFileSizeBytes = toString (cfg.sources.nasaImageLibrary.maxFileSizeMiB * 1024 * 1024);
      maxImages = toString cfg.sources.nasaImageLibrary.maxImages;
      maxCandidateRecords = toString cfg.sources.nasaImageLibrary.maxCandidateRecords;
      minYear = toString cfg.sources.nasaImageLibrary.minYear;
      minAspectRatioScaled = toString (
        builtins.floor (cfg.sources.nasaImageLibrary.minAspectRatio * 1000)
      );
      maxAspectRatioScaled = toString (
        builtins.floor (cfg.sources.nasaImageLibrary.maxAspectRatio * 1000)
      );
      normalizeSdr = lib.getExe' wallpaperNormalizer "desktop-wallpaper-normalize-sdr";
      keepOriginals = if cfg.sources.nasaImageLibrary.keepOriginals then "1" else "0";
      queriesJson = lib.escapeShellArg (builtins.toJSON cfg.sources.nasaImageLibrary.queries);
      rejectedTermsJson = lib.escapeShellArg (builtins.toJSON cfg.sources.nasaImageLibrary.rejectedTerms);
      requiredTitleTermsJson = lib.escapeShellArg (
        builtins.toJSON cfg.sources.nasaImageLibrary.requiredTitleTerms
      );
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
  wikimediaCommonsFetcher = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-fetch-wikimedia-commons";
    src = ./scripts/wallpaper-fetch-wikimedia-commons.sh.in;
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
      category = lib.escapeShellArg cfg.sources.wikimediaCommons.category;
      userAgent = lib.escapeShellArg cfg.sources.wikimediaCommons.userAgent;
      maxFileSizeBytes = toString (cfg.sources.wikimediaCommons.maxFileSizeMiB * 1024 * 1024);
      maxImages = toString cfg.sources.wikimediaCommons.maxImages;
    };
  };
  smithsonianFetcher = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-fetch-smithsonian";
    src = ./scripts/wallpaper-fetch-smithsonian.sh.in;
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
      maxFileSizeBytes = toString (cfg.sources.smithsonian.maxFileSizeMiB * 1024 * 1024);
      maxImages = toString cfg.sources.smithsonian.maxImages;
      maxCandidateRecords = toString cfg.sources.smithsonian.maxCandidateRecords;
      minAspectRatioScaled = toString (builtins.floor (cfg.sources.smithsonian.minAspectRatio * 1000));
      maxAspectRatioScaled = toString (builtins.floor (cfg.sources.smithsonian.maxAspectRatio * 1000));
      userAgent = lib.escapeShellArg cfg.sources.smithsonian.userAgent;
      queriesJson = lib.escapeShellArg (builtins.toJSON cfg.sources.smithsonian.queries);
      rejectedTermsJson = lib.escapeShellArg (builtins.toJSON cfg.sources.smithsonian.rejectedTerms);
      allowedObjectTypesJson = lib.escapeShellArg (
        builtins.toJSON cfg.sources.smithsonian.allowedObjectTypes
      );
      allowedUnitCodesJson = lib.escapeShellArg (
        builtins.toJSON cfg.sources.smithsonian.allowedUnitCodes
      );
    };
  };
  enabledFetcherUnits = lib.flatten [
    (lib.optional cfg.sources.nasaSvs.enable "desktop-wallpaper-fetch-nasa.service")
    (lib.optional cfg.sources.nasaImageLibrary.enable "desktop-wallpaper-fetch-nasa-library.service")
    (lib.optional cfg.sources.clevelandMuseum.enable "desktop-wallpaper-fetch-cma.service")
    (lib.optional cfg.sources.wikimediaCommons.enable "desktop-wallpaper-fetch-wikimedia-commons.service")
    (lib.optional cfg.sources.smithsonian.enable "desktop-wallpaper-fetch-smithsonian.service")
  ];
  wallpaperSeed = pkgs.replaceVarsWith {
    name = "desktop-wallpaper-seed";
    src = ./scripts/wallpaper-seed.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      systemctl = lib.getExe' pkgs.systemd "systemctl";
      runtimePath = lib.makeBinPath [ pkgs.coreutils ];
      sourceUnits = lib.concatStringsSep " " (map lib.escapeShellArg enabledFetcherUnits);
      initialFetches = toString cfg.sources.initialFetches;
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
      enable = lib.mkEnableOption "a daily, bounded, visual-only NASA Scientific Visualization Studio wallpaper fetch";

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
        default = 12;
        description = "Maximum NASA SVS visualization records inspected per fetch before giving up.";
      };

      maxFileSizeMiB = lib.mkOption {
        type = lib.types.ints.between 5 512;
        default = 150;
        description = "Maximum accepted NASA original-image size, in MiB. This accommodates high-quality 4K and lossless variants while keeping each download bounded.";
      };

      keepOriginals = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Keep a private original archive when an unsupported NASA still is converted to a displayable 16-bit PNG derivative.";
      };

      queries = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "aurora"
          "earthrise"
          "earth at night"
          "hubble"
          "nebula"
        ];
        description = ''
          NASA SVS search phrases eligible for automatic collection. The
          default intentionally favours astronomy and Earth imagery rather
          than SVS's full catalogue of data products.
        '';
      };

      rejectedTerms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "anomaly"
          "aerosol"
          "chart"
          "data"
          "diagram"
          "forecast"
          "graph"
          "infographic"
          "logo"
          "map"
          "model"
          "poster"
          "simulation"
          "timeline"
        ];
        description = "Case-insensitive NASA SVS title and keyword terms that disqualify a visualization.";
      };
    };

    sources.nasaImageLibrary = {
      enable = lib.mkEnableOption "a daily, curated photographic NASA Image and Video Library wallpaper fetch";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Systemd calendar expression for the low-frequency NASA Image and Video Library fetch.";
      };

      maxImages = lib.mkOption {
        type = lib.types.ints.between 1 120;
        default = 30;
        description = "Maximum NASA Image and Video Library images retained in the local private cache.";
      };

      maxCandidateRecords = lib.mkOption {
        type = lib.types.ints.between 1 120;
        default = 60;
        description = "Maximum Image Library records inspected per fetch before giving up.";
      };

      minYear = lib.mkOption {
        type = lib.types.ints.between 1958 2100;
        default = 2000;
        description = "Earliest NASA Image and Video Library creation year accepted automatically. The default avoids low-quality archival scans; lower it only when historic imagery is explicitly wanted.";
      };

      maxFileSizeMiB = lib.mkOption {
        type = lib.types.ints.between 5 512;
        default = 150;
        description = "Maximum accepted NASA original-image size, in MiB. This permits high-quality 4K originals while bounding one network download.";
      };

      minAspectRatio = lib.mkOption {
        type = lib.types.numbers.between 1.0 4.0;
        default = 1.4;
        description = "Minimum width-to-height ratio of the decoded original. Raise this to 1.6 for a 16:9-only collection.";
      };

      maxAspectRatio = lib.mkOption {
        type = lib.types.numbers.between 1.0 4.0;
        default = 2.4;
        description = "Maximum width-to-height ratio of the decoded original, preventing ultrawide images from entering a normal desktop collection.";
      };

      keepOriginals = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Keep a private original archive when an unsupported NASA still is converted to a displayable 16-bit PNG derivative.";
      };

      queries = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "Webb First Deep Field"
          "Webb Carina Nebula"
          "Hubble Pillars of Creation"
          "Hubble galaxy"
          "Hubble nebula"
        ];
        description = ''
          NASA Image and Video Library search phrases. The defaults focus on
          mission photography and telescope imagery; each accepted item must
          still be a native 4K-or-larger landscape image.
        '';
      };

      rejectedTerms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "3d model"
          "addresses"
          "animation"
          "apollo"
          "announcement"
          "archive"
          "artist concept"
          "artist's concept"
          "artwork"
          "briefing"
          "broadcast"
          "cartoon"
          "chart"
          "concept art"
          "conference"
          "diagram"
          "drawing"
          "educational"
          "emblem"
          "event"
          "graphic"
          "illustration"
          "infographic"
          "historical"
          "insignia"
          "logo"
          "map"
          "media"
          "media briefing"
          "meeting"
          "mission patch"
          "mosaic"
          "new visualization"
          "patch"
          "poster"
          "press"
          "photo credit"
          "podium"
          "portrait"
          "presenter"
          "presentation"
          "rendering"
          "schematic"
          "simulation"
          "solar system science"
          "speaks about"
          "speaks with"
          "shown on screen"
          "speaker"
          "speaking"
          "stage"
          "system science"
          "third party"
          "title card"
          "vintage"
          "visualization"
        ];
        description = "Case-insensitive Image Library title, description, and keyword terms that disqualify graphics, visualizations, and non-NASA material.";
      };

      requiredTitleTerms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "aurora"
          "deep field"
          "eclipse"
          "galaxy"
          "jupiter"
          "mars"
          "moon"
          "nebula"
          "planet"
          "pillars of creation"
          "saturn"
          "star"
        ];
        description = ''
          Case-insensitive subject terms that must occur in a NASA record's
          title. This positive admission rule avoids broad Image Library
          searches selecting press photographs of people. Change this list
          with queries when collecting a different subject area.
        '';
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
        type = lib.types.ints.between 5 512;
        default = 150;
        description = "Maximum accepted CMA original-image size, in MiB. This matches the other wallpaper sources so a source does not silently lower image quality.";
      };

      maxImages = lib.mkOption {
        type = lib.types.ints.between 1 120;
        default = 20;
        description = "Maximum CMA images retained in the local private cache.";
      };
    };

    sources.wikimediaCommons = {
      enable = lib.mkEnableOption "a daily, bounded Wikimedia Commons public-domain quality-landscape wallpaper fetch";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Systemd calendar expression for the low-frequency Wikimedia Commons fetch.";
      };

      category = lib.mkOption {
        type = lib.types.str;
        default = "Quality_images_of_landscapes";
        description = "Wikimedia Commons file category, without the Category: prefix. The default is the community-reviewed quality-landscapes category.";
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

    sources.smithsonian = {
      enable = lib.mkEnableOption "a daily, credential-backed Smithsonian Open Access 4K wallpaper fetch";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Systemd calendar expression for the low-frequency Smithsonian fetch.";
      };

      maxImages = lib.mkOption {
        type = lib.types.ints.between 1 120;
        default = 30;
        description = "Maximum Smithsonian images retained in the local private cache.";
      };

      maxCandidateRecords = lib.mkOption {
        type = lib.types.ints.between 1 200;
        default = 80;
        description = "Maximum Smithsonian CC0 high-resolution image candidates inspected per fetch.";
      };

      maxFileSizeMiB = lib.mkOption {
        type = lib.types.ints.between 5 512;
        default = 150;
        description = "Maximum accepted Smithsonian original-image size, in MiB. This permits high-quality 4K JPEG and TIFF originals while bounding one network download.";
      };

      minAspectRatio = lib.mkOption {
        type = lib.types.numbers.between 1.0 4.0;
        default = 1.4;
        description = "Minimum width-to-height ratio of the decoded original. Raise this to 1.6 for a 16:9-only collection.";
      };

      maxAspectRatio = lib.mkOption {
        type = lib.types.numbers.between 1.0 4.0;
        default = 2.4;
        description = "Maximum width-to-height ratio of the decoded original, preventing ultrawide images from entering a normal desktop collection.";
      };

      userAgent = lib.mkOption {
        type = lib.types.str;
        default = "nix-conf-wallpaper/1.0 (https://github.com/ianmh/nix-conf)";
        description = "Descriptive User-Agent sent to the Smithsonian API and image-delivery service.";
      };

      allowedObjectTypes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "Paintings"
          "Photographs"
        ];
        description = ''
          Smithsonian controlled object types admitted to the automatic
          collection. This conservative allow-list prevents high-resolution
          scans of books, ledgers, archival records, and scientific specimens
          from being mistaken for desktop art. Set it explicitly to broaden
          the source deliberately.
        '';
      };

      allowedUnitCodes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Optional Smithsonian unit-code allow-list. An empty list accepts the
          configured object types from every Smithsonian unit; use it to make
          a more narrowly curated collection when desired.
        '';
      };

      queries = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "landscape"
          "seascape"
          "national park"
          "waterfall"
          "forest"
          "botanical"
        ];
        description = ''
          Smithsonian Open Access search phrases. The source accepts only
          CC0 high-resolution landscape images and rejects documentation-like
          material, so these defaults favour visual art and nature rather than
          every collection image.
        '';
      };

      rejectedTerms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "advertisement"
          "account book"
          "album"
          "architectural drawing"
          "blueprint"
          "book"
          "botanical plate"
          "calendar"
          "catalog"
          "chart"
          "correspondence"
          "diagram"
          "document"
          "field book"
          "form"
          "graph"
          "handwritten"
          "label"
          "ledger"
          "letter"
          "manuscript"
          "map"
          "notebook"
          "page"
          "pattern"
          "plan"
          "plate"
          "proof"
          "register"
          "score"
          "sketch"
          "sketchbook"
          "specimen"
          "technical drawing"
          "study"
          "technical"
        ];
        description = "Case-insensitive structured Smithsonian metadata terms that disqualify documentation-like material.";
      };
    };

    sources.initialFetches = lib.mkOption {
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
            assertion = !cfg.sources.nasaSvs.enable || cfg.mode == "rotate";
            message = "desktop.wallpaper.sources.nasaSvs requires rotate mode so fetched images can be selected locally.";
          }
          {
            assertion = !cfg.sources.nasaImageLibrary.enable || cfg.mode == "rotate";
            message = "desktop.wallpaper.sources.nasaImageLibrary requires rotate mode so fetched images can be selected locally.";
          }
          {
            assertion =
              cfg.sources.nasaImageLibrary.minAspectRatio <= cfg.sources.nasaImageLibrary.maxAspectRatio;
            message = "desktop.wallpaper.sources.nasaImageLibrary.minAspectRatio must not exceed maxAspectRatio.";
          }
          {
            assertion = !cfg.sources.clevelandMuseum.enable || cfg.mode == "rotate";
            message = "desktop.wallpaper.sources.clevelandMuseum requires rotate mode so fetched images can be selected locally.";
          }
          {
            assertion = !cfg.sources.wikimediaCommons.enable || cfg.mode == "rotate";
            message = "desktop.wallpaper.sources.wikimediaCommons requires rotate mode so fetched images can be selected locally.";
          }
          {
            assertion = !cfg.sources.smithsonian.enable || cfg.mode == "rotate";
            message = "desktop.wallpaper.sources.smithsonian requires rotate mode so fetched images can be selected locally.";
          }
          {
            assertion = cfg.sources.smithsonian.minAspectRatio <= cfg.sources.smithsonian.maxAspectRatio;
            message = "desktop.wallpaper.sources.smithsonian.minAspectRatio must not exceed maxAspectRatio.";
          }
          {
            assertion = cfg.sources.smithsonian.allowedObjectTypes != [ ];
            message = "desktop.wallpaper.sources.smithsonian.allowedObjectTypes must contain at least one Smithsonian object type.";
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
          services.desktop-wallpaper-directories = {
            Unit = {
              Description = "Create private desktop wallpaper directories";
              Before = [ "desktop-wallpaper-rotate.service" ];
            };
            Service = {
              Type = "oneshot";
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
              ExecStart = "${lib.getExe' pkgs.awww "awww-daemon"} --quiet";
              Restart = "on-failure";
              RestartSec = 2;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

          services.desktop-wallpaper-rotate = {
            Unit = {
              Description = "Select the next local desktop wallpaper";
              After = [
                "awww.service"
                "desktop-wallpaper-directories.service"
              ];
              Wants = [ "awww.service" ];
              Requires = [ "desktop-wallpaper-directories.service" ];
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
                "desktop-wallpaper-directories.service"
              ];
              Wants = [ "awww.service" ];
              Requires = [ "desktop-wallpaper-directories.service" ];
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

        };
      })

      (lib.mkIf cfg.sources.nasaImageLibrary.enable {
        home.packages = [ nasaImageLibraryFetcher ];

        systemd.user = {
          services.desktop-wallpaper-fetch-nasa-library = {
            Unit = {
              Description = "Fetch one validated NASA Image and Video Library 4K wallpaper";
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
              ExecStart = lib.getExe' nasaImageLibraryFetcher "desktop-wallpaper-fetch-nasa-library";
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

          timers.desktop-wallpaper-fetch-nasa-library = {
            Unit.Description = "Fetch a new NASA Image and Video Library wallpaper at low frequency";
            Timer = {
              OnCalendar = cfg.sources.nasaImageLibrary.interval;
              RandomizedDelaySec = "2h";
              Persistent = true;
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
                "desktop-wallpaper-directories.service"
              ];
              Wants = [ "awww.service" ];
              Requires = [ "desktop-wallpaper-directories.service" ];
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

        };
      })

      (lib.mkIf cfg.sources.wikimediaCommons.enable {
        home.packages = [ wikimediaCommonsFetcher ];

        systemd.user = {
          services.desktop-wallpaper-fetch-wikimedia-commons = {
            Unit = {
              Description = "Fetch one validated Wikimedia Commons public-domain quality landscape wallpaper";
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
              OnCalendar = cfg.sources.wikimediaCommons.interval;
              RandomizedDelaySec = "2h";
              Persistent = true;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      })

      (lib.mkIf cfg.sources.smithsonian.enable {
        home.packages = [ smithsonianFetcher ];

        systemd.user = {
          services.desktop-wallpaper-fetch-smithsonian = {
            Unit = {
              Description = "Fetch one validated Smithsonian Open Access 4K wallpaper";
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
              ExecStart = lib.getExe' smithsonianFetcher "desktop-wallpaper-fetch-smithsonian";
              ExecStartPost = "${lib.getExe' pkgs.systemd "systemctl"} --user start --no-block desktop-wallpaper-rotate.service";
              TimeoutStartSec = "8min";
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

          timers.desktop-wallpaper-fetch-smithsonian = {
            Unit.Description = "Fetch a new Smithsonian Open Access wallpaper at low frequency";
            Timer = {
              OnCalendar = cfg.sources.smithsonian.interval;
              RandomizedDelaySec = "2h";
              Persistent = true;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      })

      (lib.mkIf (cfg.mode == "rotate" && enabledFetcherUnits != [ ] && cfg.sources.initialFetches > 0) {
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
              TimeoutStartSec = "15min";
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
