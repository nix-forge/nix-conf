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
  colimaForward = pkgs.writeShellScript "karakeep-colima-forward" ''
    set -eu

    url=${lib.escapeShellArg localUrl}
    ssh_config="$HOME/.config/colima/_lima/colima/ssh.config"
    colima_bin=""

    if ${pkgs.curl}/bin/curl -fsSI --max-time 2 "$url" >/dev/null 2>&1; then
      exit 0
    fi

    for candidate in \
      "$HOME/.nix-profile/bin/colima" \
      "/etc/profiles/per-user/${config.home.username}/bin/colima" \
      "/run/current-system/sw/bin/colima"
    do
      if [ -x "$candidate" ]; then
        colima_bin="$candidate"
        break
      fi
    done

    if [ -z "$colima_bin" ] && command -v colima >/dev/null 2>&1; then
      colima_bin="$(command -v colima)"
    fi

    if [ ! -f "$ssh_config" ] || [ -z "$colima_bin" ]; then
      exit 0
    fi

    for _ in $(${pkgs.coreutils}/bin/seq 1 12); do
      if "$colima_bin" ssh -- ${pkgs.curl}/bin/curl -fsSI --max-time 2 ${lib.escapeShellArg "http://127.0.0.1:${toString cfg.port}"} >/dev/null 2>&1; then
        /usr/bin/ssh -F "$ssh_config" \
          -O forward \
          -L ${lib.escapeShellArg "127.0.0.1:${toString cfg.port}:127.0.0.1:${toString cfg.port}"} \
          -N -f lima-colima >/dev/null 2>&1 || true
        exit 0
      fi

      ${pkgs.coreutils}/bin/sleep 2
    done
  '';
  managedEnvironmentNames = [
    "BROWSER_WEB_URL"
    "DATA_DIR"
    "KARAKEEP_VERSION"
    "MEILI_ADDR"
    "MEILI_MASTER_KEY"
    "NEXTAUTH_SECRET"
    "NEXTAUTH_URL"
  ];

  extensionSetup = pkgs.writeShellApplication {
    name = "karakeep-extension-setup";
    runtimeInputs = lib.optionals isLinux [ pkgs.xdg-utils ];
    text = ''
      cat <<'EOF'
      Karakeep local server:
        ${localUrl}

      The Firefox and Zen Karakeep extension is force-installed by policy.
      Open the extension options, set the server address above, then sign in
      or paste an API key from Karakeep.

      The extension stores its settings in browser sync storage, so the API key
      is intentionally not managed from Nix.
      EOF

      if command -v open >/dev/null 2>&1; then
        open "${localUrl}" >/dev/null 2>&1 || true
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${localUrl}" >/dev/null 2>&1 || true
      fi
    '';
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

    xdg.configFile."karakeep/extension-setup.md".text = ''
      # Karakeep Browser Extension

      Local server URL: `${localUrl}`

      The Karakeep Firefox/Zen extension is installed by browser policy. Open
      the extension options, set the server address to the URL above, then sign
      in or paste an API key from Karakeep.

      The extension stores configuration in `chrome.storage.sync`; Karakeep does
      not currently expose Firefox managed-storage policy for this setting.
    '';

    home.activation.karakeepEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu

      mkdir -p ${lib.escapeShellArg configDir} ${lib.escapeShellArg cfg.dataDir}/data ${lib.escapeShellArg cfg.dataDir}/meilisearch
      mkdir -p ${lib.escapeShellArg config.xdg.stateHome}/karakeep
      chmod 700 ${lib.escapeShellArg cfg.dataDir}

      nextauth_secret=""
      meili_master_key=""

      if [ -f ${lib.escapeShellArg envFile} ]; then
        nextauth_secret="$(${pkgs.gnugrep}/bin/grep -E '^NEXTAUTH_SECRET=' ${lib.escapeShellArg envFile} | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gnused}/bin/sed 's/^NEXTAUTH_SECRET=//' || true)"
        meili_master_key="$(${pkgs.gnugrep}/bin/grep -E '^MEILI_MASTER_KEY=' ${lib.escapeShellArg envFile} | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gnused}/bin/sed 's/^MEILI_MASTER_KEY=//' || true)"
      fi

      if [ -z "$nextauth_secret" ]; then
        nextauth_secret="$(${pkgs.openssl}/bin/openssl rand -base64 36)"
      fi

      if [ -z "$meili_master_key" ]; then
        meili_master_key="$(${pkgs.openssl}/bin/openssl rand -base64 36)"
      fi

      umask 0077
      tmp_env="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg configDir}/.env.XXXXXX)"
      {
        printf '%s\n' '# Generated by Home Manager. Secrets are preserved across rebuilds.'
        printf '%s\n' ${lib.escapeShellArg envLines}
        printf 'NEXTAUTH_SECRET=%s\n' "$nextauth_secret"
        printf 'MEILI_MASTER_KEY=%s\n' "$meili_master_key"
      } > "$tmp_env"
      ${pkgs.coreutils}/bin/mv "$tmp_env" ${lib.escapeShellArg envFile}
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
      config = {
        Label = "dev.user.karakeep";
        ProgramArguments = [
          "${pkgs.writeShellScript "karakeep-launchd" ''
            set -eu

            export HOME=${lib.escapeShellArg config.home.homeDirectory}
            export DOCKER_HOST=unix://${lib.escapeShellArg colimaDockerSocket}

            for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
              if [ -S ${lib.escapeShellArg colimaDockerSocket} ]; then
                break
              fi
              ${pkgs.coreutils}/bin/sleep 2
            done

            ${dockerCompose} up -d
            ${colimaForward}
            trap '${dockerCompose} down' INT TERM EXIT
            while true; do
              ${pkgs.coreutils}/bin/sleep 3600
            done
          ''}"
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
