{
  profile ? "home-server",
}:
let
  stack = import ./stack-values.nix { inherit profile; };
in
{
  profile = stack.profile;

  timer = {
    onBootSec = "10m";
    onUnitActiveSec = "30m";
    randomizedDelaySec = "5m";
  };

  prowlarr = {
    url = "http://${stack.services.prowlarr.upstream}";
    prune = {
      applications = true;
      downloadClients = true;
      indexers = true;
    };

    applications = [
      {
        name = "Sonarr";
        implementationName = "Sonarr";
        service = "sonarr";
      }
      {
        name = "Radarr";
        implementationName = "Radarr";
        service = "radarr";
      }
      {
        name = "Lidarr";
        implementationName = "Lidarr";
        service = "lidarr";
      }
      {
        name = "Readarr";
        implementationName = "Readarr";
        service = "readarr";
      }
    ];

    # Add indexers declaratively; auth can be provided through env var names.
    # Example:
    # {
    #   name = "Nyaa";
    #   implementationName = "Nyaa";
    #   enableRss = true;
    #   enableAutomaticSearch = true;
    #   priority = 25;
    # }
    indexers = [ ];
  };

  arr = {
    sonarr = {
      name = "Sonarr";
      url = "http://${stack.services.sonarr.upstream}";
      host = "127.0.0.1";
      port = stack.services.sonarr.port;
      apiVersion = "v3";
      category = "Series";
      rootFolders = [ "${stack.stackRoot}/data/media/tv" ];
      mediaManagement = {
        renameEpisodes = true;
        createEmptySeriesFolders = false;
      };
    };
    radarr = {
      name = "Radarr";
      url = "http://${stack.services.radarr.upstream}";
      host = "127.0.0.1";
      port = stack.services.radarr.port;
      apiVersion = "v3";
      category = "Movies";
      rootFolders = [ "${stack.stackRoot}/data/media/movies" ];
      mediaManagement = {
        renameMovies = true;
      };
    };
    lidarr = {
      name = "Lidarr";
      url = "http://${stack.services.lidarr.upstream}";
      host = "127.0.0.1";
      port = stack.services.lidarr.port;
      apiVersion = "v1";
      category = "Music";
      rootFolders = [ "${stack.stackRoot}/data/media/music" ];
      mediaManagement = {
        renameTracks = true;
      };
    };
    readarr = {
      name = "Readarr";
      url = "http://${stack.services.readarr.upstream}";
      host = "127.0.0.1";
      port = stack.services.readarr.port;
      apiVersion = "v1";
      category = "Books";
      rootFolders = [ "${stack.stackRoot}/data/media/books/books" ];
      mediaManagement = {
        renameBooks = true;
      };
    };
  };

  downloadClients = {
    qbittorrent = {
      name = "qBittorrent";
      implementation = "QBittorrent";
      host = "127.0.0.1";
      port = stack.services.qbittorrent.webuiPort;
      useSsl = false;
      urlBase = "";
    };
    nzbget = {
      name = "NZBGet";
      implementation = "NZBGet";
      host = "127.0.0.1";
      port = stack.services.nzbget.controlPort;
      useSsl = false;
      urlBase = "";
      category = "Prowlarr";
    };
  };

  seerr = {
    url = "http://${stack.services.seerr.upstream}";
    jellyfin = {
      ip = "127.0.0.1";
      port = 8096;
      useSsl = false;
      urlBase = "";
      externalHostname = "https://jellyfin.${stack.baseDomain}";
      jellyfinForgotPasswordUrl = "https://jellyfin.${stack.baseDomain}/web/index.html#!/forgotpassword.html";
      enabledLibraries = [
        "Movies"
        "TV Shows"
      ];
    };

    sonarr = {
      name = "Sonarr";
      isDefault = true;
      is4k = false;
      activeDirectory = "${stack.stackRoot}/data/media/tv";
      syncEnabled = true;
      preventSearch = false;
    };

    radarr = {
      name = "Radarr";
      isDefault = true;
      is4k = false;
      activeDirectory = "${stack.stackRoot}/data/media/movies";
      syncEnabled = true;
      preventSearch = false;
    };
  };

  jellyfin = {
    url = "http://${stack.services.jellyfin.upstream}";
    libraries = [
      {
        name = "Movies";
        collectionType = "movies";
        paths = [ "${stack.stackRoot}/data/media/movies" ];
      }
      {
        name = "TV Shows";
        collectionType = "tvshows";
        paths = [ "${stack.stackRoot}/data/media/tv" ];
      }
      {
        name = "Music";
        collectionType = "music";
        paths = [ "${stack.stackRoot}/data/media/music" ];
      }
      {
        name = "Books";
        collectionType = "books";
        paths = [ "${stack.stackRoot}/data/media/books/books" ];
      }
    ];
  };
}
