{
  config,
  lib,
  pkgs,
  ...
}:
let
  identityReady =
    builtins.pathExists ../secrets/homelab-identity-realm.age
    && builtins.pathExists ../secrets/homelab-identity-admin-env.age;
  wardrowbeReady = builtins.pathExists ../secrets/homelab-wardrowbe-env.age;
  domain = config.homelab.operations.lanHttps.domain;
  wardrobeUrl = "https://wardrobe.${domain}";
  identityUrl = "https://identity.${domain}";
  realm = config.services.keycloak.bootstrapRealm.name;
in
{
  # Password-first identity; encrypted imports are used only on first startup.
  # Retain the old Pocket ID state and encrypted key for recovery.
  services.keycloak = lib.mkIf identityReady {
    enable = true;
    settings.hostname = identityUrl;
    bootstrapRealm = {
      enable = true;
      file = config.nixSeal.secrets.homelab-identity-realm.path;
      environmentFile = config.nixSeal.secrets.homelab-identity-admin-env.path;
    };
  };
  networking.hosts."127.0.0.1" = lib.mkIf identityReady [ "identity.${domain}" ];

  services.wardrowbe = lib.mkIf (identityReady && wardrowbeReady) {
    enable = true;
    publicUrl = wardrobeUrl;
    environmentFile = config.nixSeal.secrets.homelab-wardrowbe-env.path;
    oidc = {
      issuerUrl = "${identityUrl}/realms/${realm}";
      tokenEndpointAuthMethod = "client_secret_basic";
      endSessionUrl = "${identityUrl}/realms/${realm}/protocol/openid-connect/logout";
    };
    ai = {
      enable = true;
      provider = "ollama";
      visionModel = "gemma3:4b";
      textModel = "gemma3:4b";
      codex = {
        enable = true;
      };
      concurrency = 1;
      timeout = 300;
    };
    extraEnvironment = {
      AI_REASONING_EFFORT = "none";
      MAX_IMAGE_MEGAPIXELS = "32";
      MAX_UPLOAD_SIZE_MB = "20";
      BG_REMOVAL_PROVIDER = "rembg";
      BG_REMOVAL_MODEL = "u2net";
      GEOCODING_USER_AGENT = "Wardrowbe/${
        config.services.wardrowbe.backendPackage.version or "unknown"
      } (+${wardrobeUrl})";
    };
  };

  services.ollama = lib.mkIf (identityReady && wardrowbeReady) {
    enable = true;
    package = pkgs.ollama-cuda;
    loadModels = [ "llama3.2:3b" ];
    host = "127.0.0.1";
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "5m";
      OLLAMA_NUM_PARALLEL = "1";
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
  };

  # Keep interactive desktop work responsive while image inference and the
  # local model process background wardrobe jobs.
  systemd.services = lib.mkIf (identityReady && wardrowbeReady) {
    wardrowbe-worker.serviceConfig = {
      Slice = "homelab-background.slice";
      CPUWeight = 25;
      IOWeight = 25;
      Nice = 5;
    };
    wardrowbe-image-worker.serviceConfig = {
      Slice = "homelab-background.slice";
      CPUWeight = 25;
      IOWeight = 25;
      Nice = 5;
    };
    ollama.serviceConfig = {
      Slice = "homelab-background.slice";
      CPUWeight = 50;
      IOWeight = 25;
      MemoryMax = "8G";
    };
    # The upstream model loader already retries failures with exponential
    # systemd backoff; its API and registry failures must not hold boot open.
  };

  # The daily file job captures the logical database export. SQLite WAL and
  # uploaded images go through the attended cold copy after services stop.
  hardware.storage.encryptedRoot.backup = {
    coldPaths = lib.mkAfter (
      lib.optional (config.systemd.services.pocket-id.enable or false) "/var/lib/pocket-id"
      ++ lib.optionals (identityReady && wardrowbeReady) [
        "/var/lib/wardrowbe"
        "/var/lib/redis-wardrowbe"
      ]
    );
    coldUnits = lib.mkAfter (
      lib.optional (config.systemd.services.pocket-id.enable or false) "pocket-id.service"
      ++ lib.optionals (identityReady && wardrowbeReady) [
        "wardrowbe-backup.timer"
        "wardrowbe-backup.service"
        "wardrowbe-frontend.service"
        "wardrowbe-backend.service"
        "wardrowbe-worker.service"
        "wardrowbe-image-worker.service"
        "wardrowbe-codex.service"
        "wardrowbe-migrate.service"
        "redis-wardrowbe.service"
      ]
    );
    exclude = lib.mkAfter (
      lib.optional (config.systemd.services.pocket-id.enable or false) "/var/lib/pocket-id"
      ++ lib.optionals (identityReady && wardrowbeReady) [
        "/var/lib/wardrowbe"
        "/var/lib/redis-wardrowbe"
      ]
    );
  };

  assertions = lib.optional (identityReady && wardrowbeReady) {
    assertion =
      config.services.keycloak.enable
      && config.services.wardrowbe.enable
      && config.services.ollama.enable;
    message = "Wardrowbe desktop deployment requires local OIDC and AI services.";
  };
}
