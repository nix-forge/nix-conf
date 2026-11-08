# Desktop media policy. The application catalog is maintained by Prowlarr and
# Bazarr; this file selects only the reviewed providers we actually use.
{
  config,
  lib,

  ...
}:
let
  requiredSecrets = [
    "homelab-vpn-private-key"
    "homelab-qbittorrent-username"
    "homelab-qbittorrent-password"
    "homelab-qbittorrent-password-hash"
    "homelab-qbittorrent-api-key"
    "homelab-sonarr-api-key"
    "homelab-radarr-api-key"
    "homelab-lidarr-api-key"
    "homelab-prowlarr-api-key"
    "homelab-prowlarr-indexers"
    "homelab-indexer-proxy-username"
    "homelab-indexer-proxy-password"
    "homelab-bazarr-api-key"
    "homelab-subdl-api-key"
    "homelab-jellyfin-admin-username"
    "homelab-jellyfin-admin-password"
    "homelab-jellyfin-viewer-username"
    "homelab-jellyfin-viewer-password"
    "homelab-seerr-admin-email"
  ];
  # Keep an incomplete bootstrap from starting applications with absent keys.
  # All declarations live in homelab/secrets.nix so nix-seal still reports the
  # missing ciphertext in its bootstrap plan.
  secretsReady = lib.all (name: builtins.pathExists (../secrets + "/${name}.age")) requiredSecrets;
  secret = name: config.nixSeal.secrets."homelab-${name}".path;
  template = name: config.nixSeal.templates."homelab-${name}".path;
  api = name: secret "${name}-api-key";
  reference = path: { _secret = path; };
  vpnNamespace = config.services.vpnConfinement.namespaces.${config.homelab.vpn.namespace.name};
  flaresolverrEnabled = config.homelab.optional.apps.flaresolverr.enable;
  vpnService = name: {
    assertion =
      let
        unit = config.systemd.services.${name};
      in
      unit.vpn.enable
      && unit.vpn.namespace == config.homelab.vpn.namespace.name
      && unit.serviceConfig.NetworkNamespacePath == "/run/netns/${config.homelab.vpn.namespace.name}";
    message = "${name} must run in the homelab VPN namespace.";
  };
  qbit = config.homelab.apps.qbittorrent;
  arrPort = name: config.services.${name}.settings.server.port;
  arrBase =
    name:
    let
      raw = config.services.${name}.settings.server.urlbase or "";
    in
    if raw == "" || raw == "/" then "" else "/${lib.removeSuffix "/" (lib.removePrefix "/" raw)}";
  arrUrl = name: "http://127.0.0.1:${toString (arrPort name)}${arrBase name}";
  mediaPolicy =
    name:
    {
      recycleBin = "${config.homelab.storage.libraryDir}/.recycle/${name}";
      recycleBinCleanupDays = 30;
      downloadPropersAndRepacks = "doNotPrefer";
      deleteEmptyFolders = true;
      fileDate = "none";
      rescanAfterRefresh = "afterManual";
      setPermissionsLinux = false;
      skipFreeSpaceCheckWhenImporting = false;
      minimumFreeSpaceWhenImporting = 20480;
      copyUsingHardlinks = true;
      useScriptImport = false;
      importExtraFiles = false;
      enableMediaInfo = true;
    }
    // {
      sonarr = {
        autoUnmonitorPreviouslyDownloadedEpisodes = false;
        createEmptySeriesFolders = false;
        episodeTitleRequired = "bulkSeasonReleases";
      };
      radarr = {
        autoUnmonitorPreviouslyDownloadedMovies = false;
        createEmptyMovieFolders = false;
      };
      lidarr = {
        autoUnmonitorPreviouslyDownloadedTracks = false;
        createEmptyArtistFolders = false;
        watchLibraryForChanges = true;
        allowFingerprinting = "newFiles";
      };
    }
    .${name};
  namingPolicy = {
    sonarr = {
      renameEpisodes = true;
      replaceIllegalCharacters = true;
      standardEpisodeFormat = "{Series CleanTitleWithoutYear} {(Series Year)} - S{season:00}E{episode:00} - {Episode CleanTitle:90} {[Custom Formats]}{[Quality Full]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}";
      dailyEpisodeFormat = "{Series CleanTitleWithoutYear} {(Series Year)} - {Air-Date} - {Episode CleanTitle:90} {[Custom Formats]}{[Quality Full]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}";
      animeEpisodeFormat = "{Series CleanTitleWithoutYear} {(Series Year)} - S{season:00}E{episode:00} - {absolute:000} - {Episode CleanTitle:90} {[Custom Formats]}{[Quality Full]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{MediaInfo AudioLanguages}{[MediaInfo VideoDynamicRangeType]}[{Mediainfo VideoCodec }{MediaInfo VideoBitDepth}bit]{-Release Group}";
      seriesFolderFormat = "{Series CleanTitleWithoutYear} {(Series Year)}";
      seasonFolderFormat = "Season {season:00}";
      specialsFolderFormat = "Specials";
    };
    radarr = {
      renameMovies = true;
      replaceIllegalCharacters = true;
      standardMovieFormat = "{Movie CleanTitle} {(Release Year)} {edition-{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo 3D]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[Mediainfo VideoCodec]}{-Release Group}";
      movieFolderFormat = "{Movie CleanTitle} ({Release Year})";
    };
    lidarr = {
      renameTracks = true;
      replaceIllegalCharacters = true;
      standardTrackFormat = "{Album Title} ({Release Year})/{Artist Name} - {Album Title} - {track:00} - {Track Title}";
      multiDiscTrackFormat = "{Album Title} ({Release Year})/{Medium Format} {medium:00}/{Artist Name} - {Album Title} - {track:00} - {Track Title}";
      artistFolderFormat = "{Artist Name}";
    };
  };
  clientDeclarations = {
    qbittorrent = {
      type = "qbittorrent";
      name = "qBittorrent";
      host = qbit.bindAddress;
      port = qbit.webuiPort;
      usernameFile = secret "qbittorrent-username";
      passwordFile = secret "qbittorrent-password";
      manageCategories = true;
    };
  }
  // lib.optionalAttrs config.homelab.apps.sabnzbd.enable {
    sabnzbd = {
      type = "sabnzbd";
      name = "SABnzbd";
      host =
        if config.homelab.apps.sabnzbd.vpn.enable then
          config.homelab.vpn.namespace.bindAddress
        else
          "127.0.0.1";
      port = config.homelab.apps.sabnzbd.port;
      apiKeyFile = secret "sabnzbd-api-key";
      after = [ "sabnzbd.service" ];
    };
  }
  // lib.optionalAttrs config.homelab.apps.nzbget.enable {
    nzbget = {
      type = "nzbget";
      name = "NZBGet";
      host = config.homelab.apps.nzbget.bindAddress;
      port = config.homelab.apps.nzbget.controlPort;
      usernameFile = secret "nzbget-username";
      passwordFile = secret "nzbget-password";
      after = [ "nzbget.service" ];
    };
  };
  clientReferences =
    category:
    {
      qbittorrent = {
        inherit category;
        # Let the manager remove only imported, stopped, seed-complete jobs.
        # Keeping their hardlinks forever prevents old upgrades freeing space.
        removeCompletedDownloads = builtins.elem category [
          "radarr"
          "sonarr"
        ];
      };
    }
    // lib.optionalAttrs config.homelab.apps.sabnzbd.enable { sabnzbd = { inherit category; }; }
    // lib.optionalAttrs config.homelab.apps.nzbget.enable { nzbget = { inherit category; }; };
  manager = name: folder: {
    kind = name;
    url = arrUrl name;
    apiKeyFile = api name;
    installApiKey = true;
    mode = "managed";
    extraSettings.hostProxy.enabled = false;
    settings = {
      mediaManagement = mediaPolicy name;
      naming = namingPolicy.${name};
      downloadHandling = {
        enableCompletedDownloadHandling = true;
        autoRedownloadFailed = false;
        autoRedownloadFailedFromInteractiveSearch = false;
      };
    };
    rootFolders.main.path = "${config.homelab.storage.libraryDir}/${folder}";
    downloadClients = clientReferences name;
  };
in
lib.mkIf secretsReady {
  # Preserve URLs stored before this deployment migrated from rootless Podman.
  networking.hosts."127.0.0.1" = [ "host.containers.internal" ];
  assertions = [
    {
      assertion =
        !config.services.jellyfin.hardwareAcceleration.enable
        && !config.services.jellyfin.forceEncodingConfig;
      message = "Desktop Jellyfin encoding is owned by the API reconciler; the native module must not write encoding.xml.";
    }
    {
      assertion =
        config.homelab.integrations.jellyfin.encoding.hardwareAccelerationType == "nvenc"
        && config.homelab.integrations.jellyfin.encoding.extraSettings.EnableHardwareEncoding
        &&
          lib.all (device: builtins.elem device config.systemd.services.jellyfin.serviceConfig.DeviceAllow)
            [
              "/dev/nvidia0 rw"
              "/dev/nvidiactl rw"
              "/dev/nvidia-uvm rw"
            ]
        && !config.systemd.services.jellyfin.serviceConfig.PrivateDevices;
      message = "Desktop Jellyfin NVENC requires GPU, control, and UVM device access plus enabled API encoding settings.";
    }
    {
      assertion =
        config.homelab.vpn.enable
        && vpnNamespace.enable
        && vpnNamespace.servicePolicy == "enforced"
        && vpnNamespace.dns.mode == "strict"
        && vpnNamespace.dns.servers != [ ]
        && !vpnNamespace.dns.allowHostResolverIPC
        && vpnNamespace.wireguard.endpointPinning.enable
        && !vpnNamespace.wireguard.allowHostnameEndpoints
        && builtins.elem vpnNamespace.ipv6.mode [
          "disable"
          "tunnel"
        ];
      message = "Media acquisition requires an enforced VPN namespace, tunnel DNS, a pinned IP endpoint, and no unprotected IPv6.";
    }
    {
      assertion =
        config.homelab.indexerProxy.enable
        && config.systemd.services.microsocks.vpn.enable
        && config.homelab.integrations.prowlarr.hostProxy == null
        && !config.homelab.integration.services.prowlarr.extraSettings.hostProxy.enabled
        && config.homelab.integrations.prowlarr.proxies.vpn.host == config.homelab.vpn.namespace.bindAddress
        && config.homelab.integrations.prowlarr.proxies.vpn.port == config.homelab.indexerProxy.port;
      message = "Prowlarr must use its tagged VPN proxy only for selected indexers.";
    }
    {
      assertion =
        !config.services.tinyproxy.enable
        && !config.homelab.integrations.seerr.extraNetworkSettings.proxy.enabled
        && lib.all (name: !config.homelab.integrations.servarr.${name}.extraSettings.hostProxy.enabled) [
          "sonarr"
          "radarr"
          "lidarr"
        ];
      message = "Direct media metadata access must not depend on global or unused challenge proxies.";
    }
    {
      assertion =
        !flaresolverrEnabled
        || config.homelab.integrations.prowlarr.privateIndexersFile != null
        || lib.any (indexer: indexer.enable && builtins.elem "browser-challenge" indexer.tags) (
          builtins.attrValues config.homelab.integrations.prowlarr.indexers
        );
      message = "FlareSolverr needs a reviewed private indexer document or a declared browser-challenge indexer.";
    }
    {
      assertion = lib.all (
        indexer:
        !indexer.enable
        || (
          builtins.elem "vpn" indexer.tags != builtins.elem "direct" indexer.tags
          && (!builtins.elem "browser-challenge" indexer.tags || builtins.elem "vpn" indexer.tags)
        )
      ) (builtins.attrValues config.homelab.integrations.prowlarr.indexers);
      message = "Each enabled Prowlarr indexer needs one explicit route tag; browser challenges must use the VPN route.";
    }
    {
      assertion =
        (config.services.qbittorrent.serverConfig.BitTorrent.Session.Interface or "")
        == config.homelab.vpn.interface.name
        &&
          (config.services.qbittorrent.serverConfig.BitTorrent.Session.InterfaceName or "")
          == config.homelab.vpn.interface.name
        && !config.services.qbittorrent.serverConfig.BitTorrent.Session.LSDEnabled
        && config.services.qbittorrent.serverConfig.BitTorrent.Session.GlobalMaxRatio == 0
        && config.services.qbittorrent.serverConfig.BitTorrent.Session.ShareLimitAction == 0
        && !config.services.qbittorrent.serverConfig.Network.PortForwardingEnabled;
      message = "qBittorrent must bind to WireGuard, stop at download completion, disable local peer discovery, and disable automatic port forwarding.";
    }
  ]
  ++ map vpnService [
    "qbittorrent"
    "slskd"
    "microsocks"
  ]
  ++ lib.optional flaresolverrEnabled (vpnService "flaresolverr");
  homelab = {
    profiles.media.enable = true;
    # This host chooses the routes; nix-homelab owns their systemd rules and
    # validates the effective policy after other modules contribute settings.
    networkPolicy = {
      directServices = [
        "bazarr"
        "sonarr"
        "radarr"
        "lidarr"
        "seerr"
      ];
      localOnlyServices = [ ];
    };
    apps = {
      lidarr.enable = true;
      # The desktop already runs Navidrome through music/discovery.nix with its
      # own library and bootstrap; keep that single instance.
    };
    optional.apps.unpackerr.enable = true;
    optional.apps.flaresolverr.enable = false;
    vpn.enable = true;
    indexerProxy = {
      enable = true;
      usernameFile = secret "indexer-proxy-username";
      passwordFile = secret "indexer-proxy-password";
    };
    apps.prowlarr.proxyOnly = true;
    operations = {
      enable = true;
      monitoring.health.firewallProtectedTcpPorts = [ 8096 ];
      pressure = {
        enable = true;
        clients.qbittorrent = {
          url = "http://${qbit.bindAddress}:${toString qbit.webuiPort}";
          credentialsFile = template "qbittorrent-login-json";
        };
      };
      monitoring.enable = true;
      dashboard.enable = true;
    };
    apps.qbittorrent = {
      credentialsFile = template "qbittorrent-webui-ini";
      apiKeyFile = secret "qbittorrent-api-key";
    };
    optional.quality = {
      enable = true;
      enable2160p = true;
      enableAnimeProfile = true;
      preferAnimeDualAudio = true;
      preferSubtitleLabeledReleases = true;
      sonarrApiKeyFile = api "sonarr";
      radarrApiKeyFile = api "radarr";
    };
    integrations = {
      downloadClients = clientDeclarations;
      servarr = {
        sonarr = manager "sonarr" "tv";
        radarr = manager "radarr" "movies";
        lidarr = lib.recursiveUpdate (manager "lidarr" "music") {
          # Setgid directories and service umasks own permissions. Import-time
          # chmod/chown fails on hardlinks owned by other download services.
          settings.mediaManagement = {
            setPermissionsLinux = false;
            importExtraFiles = true;
            extraFileExtensions = "lrc,elrc,ttml,yaml,yml,srt,txt";
            # Audio tagging must not modify hardlinked seeding downloads.
            copyUsingHardlinks = false;
          };
          settings.metadataProvider = {
            writeAudioTags = "newFiles";
            scrubAudioTags = false;
            embedCoverArt = false;
          };
          rootFolders.main.extraSettings = {
            name = "Music";
            defaultMetadataProfileId._lookup = {
              endpoint = "metadataprofile";
              name = "Standard";
            };
            defaultQualityProfileId._lookup = {
              endpoint = "qualityprofile";
              name = "Aurral High Quality";
            };
            defaultMonitorOption = "future";
            defaultNewItemMonitorOption = "none";
            defaultTags = [ ];
          };
        };
      };
      prowlarr = {
        url = arrUrl "prowlarr";
        apiKeyFile = api "prowlarr";
        privateIndexersFile = secret "prowlarr-indexers";
        installApiKey = true;
        mode = "managed";
        after = [ "microsocks.service" ] ++ lib.optionals flaresolverrEnabled [ "flaresolverr.service" ];
        applications = {
          sonarr = { };
          radarr = { };
          lidarr = { };
        };
        proxies =
          lib.optionalAttrs config.homelab.indexerProxy.enable {
            vpn = {
              type = "socks5";
              tags = [ "vpn" ];
              host = config.homelab.vpn.namespace.bindAddress;
              port = config.homelab.indexerProxy.port;
              usernameFile = config.homelab.indexerProxy.usernameFile;
              passwordFile = config.homelab.indexerProxy.passwordFile;
            };
          }
          // lib.optionalAttrs flaresolverrEnabled {
            browserChallenges = {
              type = "flaresolverr";
              tags = [ "browser-challenge" ];
              url = "http://${config.homelab.vpn.namespace.bindAddress}:${toString config.services.flaresolverr.port}";
              requestTimeout = 45;
            };
          };
        # Provider choices and their route tags live in the sealed runtime
        # document. The public proxy and route policy remain declarative.
      };
      jellyfin = {
        url = "http://127.0.0.1:8096";
        mode = "managed";
        administrator.usernameFile = secret "jellyfin-admin-username";
        administrator.passwordFile = secret "jellyfin-admin-password";
        # Multi-language releases can mark a dub as the default audio track.
        extraSettings.playback = {
          AudioLanguagePreference = "eng";
          PlayDefaultAudioTrack = false;
          # Upgrades can move English to another index; do not reuse stale indices.
          RememberAudioSelections = false;
        };
        subtitleLanguagePreference = "eng";
        subtitleMode = "Always";
        network = {
          knownProxies = [ "127.0.0.1" ];
          localNetworkAddresses = [ "127.0.0.1" ];
          # nginx admits these LAN and WireGuard clients; Jellyfin must also
          # classify them as local while remote access stays disabled.
          localNetworkSubnets = config.homelab.operations.lanHttps.allowedCIDRs;
          enableRemoteAccess = false;
          enableUPnP = false;
        };
        encoding = {
          threadCount = 2;
          enableThrottling = true;
          enableSegmentDeletion = true;
          segmentKeepSeconds = 180;
          hardwareAccelerationType = "nvenc";
          hardwareDecodingCodecs = [
            "h264"
            "hevc"
            "vp9"
            "av1"
          ];
          extraSettings = {
            EnableHardwareEncoding = true;
            # Convert HDR to SDR for clients that cannot display the source HDR.
            EnableTonemapping = true;
            EnableDecodingColorDepth10Hevc = true;
            AllowHevcEncoding = true;
            AllowAv1Encoding = true;
          };
        };
        libraries = {
          Music = {
            collectionType = "music";
            paths = [ "${config.homelab.storage.libraryDir}/music" ];
            enableRealtimeMonitor = true;
            extraOptions = {
              # Shared sidecars have one writer. Jellyfin keeps fetched data in its state.
              SaveLocalMetadata = false;
              SaveLyricsWithMedia = false;
            };
          };
          Movies = {
            collectionType = "movies";
            paths = [ "${config.homelab.storage.libraryDir}/movies" ];
            enableRealtimeMonitor = true;
          };
          Television = {
            collectionType = "tvshows";
            paths = [ "${config.homelab.storage.libraryDir}/tv" ];
            enableRealtimeMonitor = true;
          };
        };
        users.viewer = {
          nameFile = secret "jellyfin-viewer-username";
          passwordFile = secret "jellyfin-viewer-password";
          # This broad grant is explicit. The reusable default grants no library.
          enableAllFolders = true;
          # Browser clients may need audio conversion or video burn-in for
          # unsupported anime audio and styled subtitle formats.
          enableAudioPlaybackTranscoding = true;
          enableVideoPlaybackTranscoding = true;
        };
      };
      seerr = {
        url = "http://127.0.0.1:${toString config.services.seerr.port}";
        mode = "managed";
        after = [ "recyclarr.service" ];
        jellyfin = {
          emailFile = secret "seerr-admin-email";
          externalUrl = "https://jellyfin.${config.homelab.operations.lanHttps.domain}";
          libraries = [
            "Movies"
            "Television"
          ];
        };
        destinations = {
          movies = {
            manager = "radarr";
            rootFolder = "main";
            qualityProfile = "Homelab 2160p";
            isDefault = true;
          };
          television = {
            manager = "sonarr";
            rootFolder = "main";
            # Prefer 4K when available, retaining 1080p for other sources.
            # Anime has its own source/group ranking and 1080p ceiling.
            qualityProfile = "Homelab 2160p";
            extraSettings = {
              activeAnimeProfileName = "Homelab Anime";
              activeAnimeDirectory = "${config.homelab.storage.libraryDir}/tv";
            };
            isDefault = true;
          };
        };
        # New accounts still require review. Existing approved accounts are
        # reconciled by username without granting the permission to everyone.
        defaultPermissions = [ "request" ];
        allowAutomaticRequests = true;
        autoApproveUsers = [
          { _secret = secret "jellyfin-admin-username"; }
          { _secret = secret "jellyfin-viewer-username"; }
        ];
        quotas = {
          movie = {
            limit = 0;
            days = 7;
          };
          tv = {
            limit = 0;
            days = 7;
          };
        };
        extraNetworkSettings.proxy.enabled = false;
      };
    };
    integration = {
      enable = true;
      services = {
        prowlarr.extraSettings.hostProxy.enabled = false;
        bazarr = {
          url = "http://127.0.0.1:${toString config.services.bazarr.settings.general.port}";
          apiKeyFile = api "bazarr";
          installApiKey = true;
          mode = "managed";
          settings = {
            enabledLanguages = [
              "en"
              "ja"
            ];
            defaultProfiles = {
              series = "English";
              movies = "English";
            };
            seriesTypeProfiles.anime = "Anime English and Japanese";
            languageProfiles.English = {
              cutoff = 1;
              items = [
                {
                  id = 1;
                  language = "en";
                  hi = "False";
                  forced = "False";
                  audio_exclude = "False";
                  audio_only_include = "False";
                }
              ];
            };
            languageProfiles."Anime English and Japanese" = {
              tag = null;
              cutoff = null;
              originalFormat = true;
              items = [
                {
                  id = 1;
                  language = "en";
                  hi = "False";
                  forced = "False";
                  audio_exclude = "False";
                  audio_only_include = "False";
                }
                {
                  id = 2;
                  language = "ja";
                  hi = "False";
                  forced = "False";
                  audio_exclude = "False";
                  audio_only_include = "False";
                }
              ];
            };
            general = {
              use_sonarr = true;
              use_radarr = true;
              concurrent_jobs = 1;
              multithreading = false;
              wanted_search_frequency = 12;
              wanted_search_frequency_movie = 12;
              upgrade_frequency = 168;
              upgrade_manual = false;
              use_postprocessing = false;
              disable_all_providers_ssl_verify = false;
              enabled_providers = [
                "embeddedsubtitles"
                "subtitlecat"
                "subdl"
                "tsukihime"
                "yifysubtitles"
              ];
              use_embedded_subs = true;
            };
            sonarr = {
              ip = "127.0.0.1";
              port = arrPort "sonarr";
              base_url = arrBase "sonarr";
              apikey = reference (api "sonarr");
              only_monitored = true;
              series_sync = 15;
            };
            radarr = {
              ip = "127.0.0.1";
              port = arrPort "radarr";
              base_url = arrBase "radarr";
              apikey = reference (api "radarr");
              only_monitored = true;
              movies_sync = 15;
            };
          };
          extraSettings.subdl.api_key = reference (secret "subdl-api-key");
        };
      };
    };
  };
  services = {
    unpackerr.settings = {
      sonarr = [
        {
          url = arrUrl "sonarr";
          api_key = "filepath:/run/credentials/unpackerr.service/sonarr-api";
          paths = [ config.homelab.storage.downloadsDir ];
          protocols = "torrent";
          delete_orig = false;
        }
      ];
      radarr = [
        {
          url = arrUrl "radarr";
          api_key = "filepath:/run/credentials/unpackerr.service/radarr-api";
          paths = [ config.homelab.storage.downloadsDir ];
          protocols = "torrent";
          delete_orig = false;
        }
      ];
    };
  };
  # The HTTPS proxy forwards the public Host so qBittorrent can validate
  # browser Origin/Referer without trusting client-supplied forwarded headers.
  services.qbittorrent.serverConfig.Preferences.WebUI.ServerDomains =
    "qbittorrent.${config.homelab.operations.lanHttps.domain}";
  systemd.services.unpackerr.serviceConfig.LoadCredential = [
    "sonarr-api:${api "sonarr"}"
    "radarr-api:${api "radarr"}"
  ];
  # Bazarr's unit becomes active before its settings API finishes startup.
  # Reconcile again after a transient HTTP 500 without waiting for the timer.
  systemd.services.homelab-integrate-bazarr = {
    unitConfig = {
      StartLimitIntervalSec = "3min";
      StartLimitBurst = 5;
    };
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };
  # The reverse proxy serves household playback. Jellyfin's HTTP API remains
  # host-local for integrations and must not open its native ports broadly.
  services.jellyfin.openFirewall = false;
  # The API reconciler owns encoding.xml. Give its NVENC setting device access
  # without selecting the native module's competing encoding.xml writer.
  # CUDA also opens the control and unified-memory nodes; allowing only the
  # GPU node makes every hardware transcode fail with CUDA_ERROR_NO_DEVICE.
  systemd.services.jellyfin.serviceConfig.DeviceAllow = [
    "/dev/nvidia0 rw"
    "/dev/nvidiactl rw"
    "/dev/nvidia-uvm rw"
  ];
  # Jellyfin applies LocalNetworkAddresses to the HTTP listener only on a
  # restart. Force one restart when this bind policy enters the host unit.
  systemd.services.jellyfin.restartTriggers = [ "homelab-jellyfin-loopback-bind-v1" ];
  systemd.services.flaresolverr = lib.mkIf flaresolverrEnabled {
    vpn = {
      enable = true;
      namespace = config.homelab.vpn.namespace.name;
    };
    environment.HOST = lib.mkForce config.homelab.vpn.namespace.bindAddress;
    serviceConfig = {
      CapabilityBoundingSet = lib.mkForce "";
      AmbientCapabilities = lib.mkForce "";
      ProtectHome = lib.mkForce true;
      ProtectSystem = lib.mkForce "strict";
    };
  };
  homelab.vpn.namespace.hostIngressPorts.tcp = lib.optionals flaresolverrEnabled [
    config.services.flaresolverr.port
  ];
  services.qbittorrent.serverConfig.BitTorrent.Session = {
    GlobalMaxRatio = 0;
    ShareLimitAction = 0;
  };
  # The pressure timer can fire before boot has finished. Local downloader
  # startup must precede its first check; the client also waits for API readiness.
  systemd.services.homelab-storage-pressure = {
    wants = [ "qbittorrent.service" ];
    after = [ "qbittorrent.service" ];
  };
}
