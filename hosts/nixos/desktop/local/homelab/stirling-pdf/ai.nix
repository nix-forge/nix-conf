{
  config,
  lib,
  pkgs,
  ...
}:
let
  model = "qwen3.5:9b-q4_K_M";
  modelForPdf = "stirling-qwen3.5:9b-q4km-24k";
  embeddingModel = "nomic-embed-text:latest";
  enginePort = 5001;
  chatProxyPort = 11435;
  engineAuthFile = "/var/lib/stirling-pdf-engine-auth/engine.env";
  modelFile = pkgs.writeText "stirling-qwen3.5-24k.Modelfile" ''
    FROM ${model}
    PARAMETER num_ctx 24576
  '';
  engine = pkgs.stirling-pdf-engine;
  chatProxy = pkgs.writers.writePython3Bin "stirling-ollama-chat-proxy" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./ollama_chat_proxy.py);
  createEngineAuth = pkgs.writeShellApplication {
    name = "stirling-pdf-engine-auth";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = (import ../../../../../../lib/templates/text.nix) ./scripts/stirling-pdf-engine-auth.sh {
      lib_escapeShellArg_engineAuthFile = lib.escapeShellArg engineAuthFile;
    };
  };
in
{
  # The engine uses no GPU. Ollama loads Qwen only for requests and releases
  # it one minute after the last call. Models are provisioned in an attended
  # maintenance session because the daemon has no outbound network access.
  services.ollama = {
    loadModels = lib.mkAfter [
      model
      embeddingModel
    ];
    environmentVariables.OLLAMA_KEEP_ALIVE = lib.mkForce "1m";
    # Stirling's prompts can exceed Ollama's 4K default. The derived Qwen
    # manifest uses the same 24K context, sized to fit this host's GPU.
    environmentVariables.OLLAMA_CONTEXT_LENGTH = lib.mkForce "24576";
    environmentVariables.OLLAMA_MAX_LOADED_MODELS = lib.mkForce "2";
  };
  # The upstream loader always asks the daemon to pull, even with cached
  # manifests; that contradicts the daemon's loopback-only network policy.
  # Keep the loader available for attended provisioning but out of boot.
  systemd.services.ollama-model-loader.wantedBy = lib.mkForce [ ];
  # Qwen plus the embedding model remain fully GPU-resident at 24K context.
  # The previous 8G cgroup ceiling was too close to observed Qwen memory use.
  systemd.services.ollama.serviceConfig = {
    MemoryMax = lib.mkForce "10G";
    LimitCORE = 0;
    IPAddressDeny = "any";
    IPAddressAllow = [
      "127.0.0.0/8"
      "::1/128"
    ];
  };

  services.stirling-pdf = {
    environmentFiles = lib.mkAfter [ engineAuthFile ];
    environment = {
      AIENGINE_ENABLED = true;
      AIENGINE_MODE = "SELF_HOSTED";
      AIENGINE_URL = "http://127.0.0.1:${toString enginePort}";
      AIENGINE_TIMEOUTSECONDS = 240;
      AIENGINE_MODELS_PROVIDER = "ollama";
      AIENGINE_MODELS_SMARTMODEL = modelForPdf;
      AIENGINE_MODELS_FASTMODEL = modelForPdf;
      AIENGINE_MODELS_SMARTMAXTOKENS = 4096;
      AIENGINE_MODELS_FASTMAXTOKENS = 2048;
      AIENGINE_MODELS_BASEURL = "http://127.0.0.1:${toString chatProxyPort}/v1";
      AIENGINE_RAG_EMBEDDINGPROVIDER = "ollama";
      AIENGINE_RAG_EMBEDDINGMODEL = embeddingModel;
      AIENGINE_RAG_EMBEDDINGBASEURL = "http://127.0.0.1:${toString config.services.ollama.port}/v1";
      AIENGINE_RAG_TOPK = 6;
      AIENGINE_RAG_MAXSEARCHES = 3;
      AIENGINE_LIMITS_MODELMAXCONCURRENCY = 1;
    };
  };

  users.groups.stirling-pdf-engine.gid = 909;
  users.users.stirling-pdf-engine = {
    isSystemUser = true;
    uid = 909;
    group = "stirling-pdf-engine";
    home = "/var/lib/stirling-pdf-engine";
    createHome = true;
    # Retire the rootless runtime user manager from the previous deployment.
    linger = false;
  };
  systemd.services = {
    stirling-ollama-chat-proxy = {
      description = "Local Ollama chat adapter for Stirling PDF";
      wantedBy = [ "multi-user.target" ];
      after = [ "ollama.service" ];
      requires = [ "ollama.service" ];
      serviceConfig = {
        ExecStart = lib.getExe chatProxy;
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 2;
        MemoryMax = "96M";
        LimitCORE = 0;
        TasksMax = 32;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
        ];
        IPAddressDeny = "any";
        IPAddressAllow = [ "127.0.0.0/8" ];
      };
    };
    stirling-pdf-engine-auth = {
      description = "Generate the private Stirling PDF engine authentication secret";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe createEngineAuth;
        User = "root";
        Group = "stirling-pdf-engine";
        StateDirectory = "stirling-pdf-engine-auth";
        StateDirectoryMode = "0750";
        UMask = "0027";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_UNIX" ];
      };
    };
    stirling-qwen-context = {
      description = "Set Qwen's context for Stirling PDF without copying model weights";
      wantedBy = [ "multi-user.target" ];
      wants = lib.mkForce [ ];
      after = [ "ollama.service" ];
      unitConfig.ConditionPathExists = "/var/lib/ollama/models/manifests/registry.ollama.ai/library/qwen3.5/9b-q4_K_M";
      requires = [ "ollama.service" ];
      environment.OLLAMA_HOST = "127.0.0.1:${toString config.services.ollama.port}";
      environment.HOME = "/var/lib/ollama";
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
        ExecStartPre = "${lib.getExe pkgs.curl} --fail --silent --show-error --output /dev/null --retry 20 --retry-delay 2 --retry-connrefused --retry-all-errors --connect-timeout 2 --max-time 3 http://127.0.0.1:${toString config.services.ollama.port}/api/version";
        ExecStart = "${lib.getExe config.services.ollama.package} create ${modelForPdf} -f ${modelFile}";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
        ];
      };
    };
    stirling-pdf-engine = {
      description = "Native Stirling PDF AI engine";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "stirling-pdf-engine-auth.service"
        "ollama.service"
      ];
      after = [
        "stirling-pdf-engine-auth.service"
        "ollama.service"
      ];
      environment = {
        STIRLING_ENGINE_REQUIRE_AUTH = "true";
        STIRLING_ENGINE_WORKERS = "1";
        STIRLING_ENGINE_PORT = toString enginePort;
        STIRLING_MODEL_MAX_CONCURRENCY = "1";
        # Safe local defaults also apply if the engine restarts before the
        # Java service has pushed its configuration again.
        STIRLING_SMART_MODEL = "openai-chat:${modelForPdf}";
        STIRLING_FAST_MODEL = "openai-chat:${modelForPdf}";
        STIRLING_SMART_MODEL_MAX_TOKENS = "4096";
        STIRLING_FAST_MODEL_MAX_TOKENS = "2048";
        STIRLING_RAG_EMBEDDING_MODEL = "ollama:${embeddingModel}";
        OPENAI_BASE_URL = "http://127.0.0.1:${toString chatProxyPort}/v1";
        OPENAI_API_KEY = "ollama";
        OLLAMA_BASE_URL = "http://127.0.0.1:${toString config.services.ollama.port}/v1";
        STIRLING_REQUIRE_USER_ID = "true";
        STIRLING_POSTHOG_ENABLED = "false";
        STIRLING_HTTP_DEBUG = "false";
        STIRLING_LOG_LEVEL = "ERROR";
        STIRLING_ENGINE_DATA_DIR = "/run/stirling-pdf-engine";
        STIRLING_DOCUMENTS_SQLITE_PATH = "/run/stirling-pdf-engine/rag.db";
        TMPDIR = "/run/stirling-pdf-engine";
        PYTHONDONTWRITEBYTECODE = "1";
      };
      serviceConfig = {
        Type = "exec";
        User = "stirling-pdf-engine";
        Group = "stirling-pdf-engine";
        EnvironmentFile = engineAuthFile;
        ExecStart = "${lib.getExe engine} --host 127.0.0.1 --port ${toString enginePort} --workers 1 --no-access-log --no-server-header";
        # Ordering includes ExecStartPost, so Java cannot push settings before
        # the Python API is ready.
        ExecStartPost = "${lib.getExe pkgs.curl} --fail --silent --show-error --output /dev/null --retry 60 --retry-delay 2 --retry-connrefused --retry-all-errors --connect-timeout 2 --max-time 3 http://127.0.0.1:${toString enginePort}/health";
        TimeoutStartSec = 180;
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = "/run/stirling-pdf-engine";
        # Extracted document text, vectors and pushed settings disappear when
        # the service stops. No document state enters disk backups.
        TemporaryFileSystem = "/run/stirling-pdf-engine:rw,nosuid,nodev,noexec,size=512m,mode=0700,uid=909,gid=909";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        Slice = "homelab-background.slice";
        CPUWeight = 25;
        IOWeight = 25;
        MemoryMax = "1G";
        CPUQuota = "150%";
        TasksMax = 128;
        IPAddressDeny = "any";
        IPAddressAllow = [
          "127.0.0.0/8"
          "::1/128"
        ];
        LimitCORE = 0;
      };
    };
    stirling-pdf = {
      # The Java app pushes model settings only during startup. Wait for the
      # engine's HTTP readiness check or it retains its provider defaults.
      after = [ "stirling-pdf-engine.service" ];
      wants = [
        "stirling-pdf-engine.service"
        "stirling-qwen-context.service"
        "stirling-ollama-chat-proxy.service"
      ];
      requires = [
        "stirling-pdf-engine-auth.service"
        "stirling-pdf-engine.service"
      ];
      serviceConfig = {
        Slice = "homelab-background.slice";
        CPUWeight = 50;
        IOWeight = 50;
      };
    };
  };

  assertions = [
    {
      assertion =
        config.services.ollama.enable
        && config.services.ollama.host == "127.0.0.1"
        && !config.services.ollama.openFirewall;
      message = "Stirling PDF AI requires Ollama to remain on loopback with no open firewall port.";
    }
  ];
}
