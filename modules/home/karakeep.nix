{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  cfg = config.services.karakeep;
  configDir = "${config.xdg.configHome}/karakeep";
  composeFile = "${configDir}/docker-compose.yml";
  envFile = "${configDir}/.env";
  localUrl = "http://localhost:${toString cfg.port}";
  colimaDockerSocket = "${config.home.homeDirectory}/.config/colima/default/docker.sock";

  generatedEnvironment = {
    KARAKEEP_VERSION = cfg.version;
    NEXTAUTH_URL = localUrl;
  }
  // cfg.extraEnvironment;

  envLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "${name}=${value}") generatedEnvironment
  );
  hostPortMapping =
    if isDarwin then "${toString cfg.port}:3000" else "127.0.0.1:${toString cfg.port}:3000";

  composeConfig = {
    services = {
      web = {
        image = "ghcr.io/karakeep-app/karakeep:\${KARAKEEP_VERSION:-release}";
        restart = "unless-stopped";
        volumes = [ "${cfg.dataDir}/data:/data" ];
        ports = [ hostPortMapping ];
        env_file = [ envFile ];
        environment = {
          MEILI_ADDR = "http://meilisearch:7700";
          BROWSER_WEB_URL = "http://chrome:9222";
          DATA_DIR = "/data";
        };
        depends_on = [
          "chrome"
          "meilisearch"
        ];
      };

      chrome = {
        image = "gcr.io/zenika-hub/alpine-chrome:124";
        restart = "unless-stopped";
        command = [
          "--no-sandbox"
          "--disable-gpu"
          "--disable-dev-shm-usage"
          "--remote-debugging-address=0.0.0.0"
          "--remote-debugging-port=9222"
          "--hide-scrollbars"
        ];
      };

      meilisearch = {
        image = "getmeili/meilisearch:v1.41.0";
        restart = "unless-stopped";
        env_file = [ envFile ];
        environment = {
          MEILI_NO_ANALYTICS = "true";
        };
        volumes = [ "${cfg.dataDir}/meilisearch:/meili_data" ];
      };
    };
  };

  dockerCompose = "${pkgs.docker-compose}/bin/docker-compose --project-directory ${configDir} -f ${composeFile}";
  colimaForward = pkgs.replaceVarsWith {
    name = "karakeep-colima-forward";
    src = ./scripts/karakeep-colima-forward.sh;
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      localUrl = lib.escapeShellArg localUrl;
      username = config.home.username;
      curl = lib.getExe pkgs.curl;
      seq = lib.getExe' pkgs.coreutils "seq";
      sleep = lib.getExe' pkgs.coreutils "sleep";
      loopbackUrl = lib.escapeShellArg "http://127.0.0.1:${toString cfg.port}";
      forwardAddress = lib.escapeShellArg "127.0.0.1:${toString cfg.port}:127.0.0.1:${toString cfg.port}";
    };
  };
  managedEnvironmentNames = [
    "BROWSER_WEB_URL"
    "DATA_DIR"
    "KARAKEEP_VERSION"
    "MEILI_ADDR"
    "MEILI_MASTER_KEY"
    "NEXTAUTH_SECRET"
    "NEXTAUTH_URL"
  ];

  extensionSetup = pkgs.replaceVarsWith {
    name = "karakeep-extension-setup";
    src = ./scripts/karakeep-extension-setup.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      inherit localUrl;
      openCommand = if isDarwin then "/usr/bin/open" else lib.getExe pkgs.xdg-utils;
    };
  };
in
{
  options.services.karakeep = {
    enable = lib.mkEnableOption "local Karakeep through Docker Compose";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5337;
      description = "Local host port for the Karakeep web UI.";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "release";
      description = "Karakeep container tag to run.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.xdg.dataHome}/karakeep";
      defaultText = lib.literalExpression ''"${config.xdg.dataHome}/karakeep"'';
      description = "Directory for Karakeep and Meilisearch persistent data.";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        DISABLE_SIGNUPS = "true";
        DISABLE_NEW_RELEASE_CHECK = "true";
      };
      description = "Additional environment variables written to Karakeep's .env file.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin || isLinux;
        message = "services.karakeep only supports Linux and Darwin Home Manager hosts.";
      }
      {
        assertion = lib.all (name: !(builtins.hasAttr name cfg.extraEnvironment)) managedEnvironmentNames;
        message = "services.karakeep.extraEnvironment cannot define managed Karakeep variables: ${lib.concatStringsSep ", " managedEnvironmentNames}.";
      }
    ];

    home.packages = [
      pkgs.docker
      pkgs.docker-compose
      extensionSetup
    ];

    xdg.configFile."karakeep/docker-compose.yml".text = builtins.toJSON composeConfig;

    xdg.configFile."karakeep/extension-setup.md".source = pkgs.replaceVarsWith {
      name = "karakeep-extension-setup.md";
      src = ./karakeep-extension-setup.md.in;
      replacements = { inherit localUrl; };
    };

    home.activation.karakeepEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.replaceVarsWith {
        name = "karakeep-env";
        src = ./scripts/karakeep-env.sh;
        isExecutable = true;
        replacements = {
          bash = lib.getExe pkgs.bash;
          mkdir = lib.getExe' pkgs.coreutils "mkdir";
          chmod = lib.getExe' pkgs.coreutils "chmod";
          grep = lib.getExe pkgs.gnugrep;
          head = lib.getExe' pkgs.coreutils "head";
          sed = lib.getExe pkgs.gnused;
          openssl = lib.getExe pkgs.openssl;
          mktemp = lib.getExe' pkgs.coreutils "mktemp";
          cat = lib.getExe' pkgs.coreutils "cat";
          mv = lib.getExe' pkgs.coreutils "mv";
          configDir = lib.escapeShellArg configDir;
          dataDir = lib.escapeShellArg cfg.dataDir;
          stateDir = lib.escapeShellArg "${config.xdg.stateHome}/karakeep";
          envFile = lib.escapeShellArg envFile;
          environmentDefaults = pkgs.writeText "karakeep-default-environment" envLines;
        };
      }}
    '';

    systemd.user.services.karakeep = lib.mkIf isLinux {
      Unit = {
        Description = "Karakeep local Docker Compose stack";
        After = [ "docker.service" ];
      };

      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = configDir;
        ExecStart = "${dockerCompose} up -d";
        ExecStop = "${dockerCompose} down";
      };

      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.karakeep = lib.mkIf isDarwin {
      enable = true;
      domain = lib.mkDefault "user";
      config = {
        Label = "dev.user.karakeep";
        ProgramArguments = [
          "${pkgs.replaceVarsWith {
            name = "karakeep-launchd";
            src = ./scripts/karakeep-launchd.sh;
            isExecutable = true;
            replacements = {
              bash = lib.getExe pkgs.bash;
              homeDirectory = lib.escapeShellArg config.home.homeDirectory;
              dockerSocket = lib.escapeShellArg colimaDockerSocket;
              seq = lib.getExe' pkgs.coreutils "seq";
              sleep = lib.getExe' pkgs.coreutils "sleep";
              inherit dockerCompose;
              inherit colimaForward;
            };
          }}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Background";
        StandardOutPath = "${config.xdg.stateHome}/karakeep/launchd.out.log";
        StandardErrorPath = "${config.xdg.stateHome}/karakeep/launchd.err.log";
      };
    };
  };
}
