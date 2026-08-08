{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.services.localControl;
  stateDir = "${config.xdg.stateHome}/local-control";
  postgresDir = "${stateDir}/postgres";
  postgresSocketDir = "${stateDir}/postgres-socket";
  pkiDir = "${stateDir}/pki";
  inherit (cfg) environmentFile;
  logDir = "${stateDir}/logs";

  requirePrivateSettings =
    names:
    lib.concatMapStringsSep "\n" (name: ''
      if [ -z "''${${name}:-}" ]; then
        printf 'Missing required private service setting: ${name}\n' >&2
        exit 78
      fi
    '') names;

  loadPrivateEnvironment = ''
    set -eu
    if [ ! -f ${lib.escapeShellArg environmentFile} ] || [ -L ${lib.escapeShellArg environmentFile} ]; then
      printf 'Missing private service environment: %s\n' ${lib.escapeShellArg environmentFile} >&2
      exit 78
    fi
    if [ ! -r ${lib.escapeShellArg environmentFile} ]; then
      printf 'Private service environment is not readable.\n' >&2
      exit 78
    fi
    if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' ${lib.escapeShellArg environmentFile} )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
      printf 'Private service environment must be owned by the current user.\n' >&2
      exit 78
    fi
    environment_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' ${lib.escapeShellArg environmentFile} )"
    if (( (8#$environment_mode & 0077) != 0 )); then
      printf 'Private service environment must not be readable by group or others.\n' >&2
      exit 78
    fi
    set -a
    # shellcheck disable=SC1091
    . ${lib.escapeShellArg environmentFile}
    set +a
  '';

  prepareDatabaseEnvironment = ''
    ${requirePrivateSettings [
      "LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE"
      "LOCAL_CONTROL_DATABASE_URL"
    ]}
    case "$LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE" in
      [A-Za-z_]* )
        case "$LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE" in
          *[!A-Za-z0-9_]* )
            printf 'The configured database environment variable name is invalid.\n' >&2
            exit 64
            ;;
        esac
        ;;
      * )
        printf 'The configured database environment variable name is invalid.\n' >&2
        exit 64
        ;;
    esac
    export "$LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE=$LOCAL_CONTROL_DATABASE_URL"
  '';

  waitForDatabase = ''
    attempt=0
    until ${pkgs.postgresql_18}/bin/pg_isready \
      -h 127.0.0.1 \
      -p ${toString cfg.postgresPort} >/dev/null 2>&1; do
      attempt=$((attempt + 1))
      if [ "$attempt" -ge 60 ]; then
        printf 'Timed out waiting for local PostgreSQL readiness.\n' >&2
        exit 75
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';

  runPrivateCommand = setting: ''
    ${requirePrivateSettings [ setting ]}
    ${pkgs.bash}/bin/bash -o errexit -o pipefail -c "''${${setting}}"
  '';

  execPrivateCommand = setting: ''
    ${requirePrivateSettings [ setting ]}
    exec ${pkgs.bash}/bin/bash -o errexit -o pipefail -c "''${${setting}}"
  '';

  caddyConfig = pkgs.writeText "local-control.Caddyfile" ''
    {
      admin off
      auto_https off
      servers {
        protocols h1 h2
        strict_sni_host insecure_off
      }
    }

    https://${cfg.hostOnlyAddress}:${toString cfg.agentPort} {
      bind ${cfg.hostOnlyAddress}
      tls ${pkiDir}/server.crt ${pkiDir}/server.key {
        client_auth {
          trust_pool file ${pkiDir}/ca.crt
          mode require_and_verify
        }
      }
      request_header -X-Client-Certificate-Fingerprint
      request_header -X-Agent-Proxy-Attestation
      reverse_proxy 127.0.0.1:${toString cfg.apiPort} {
        header_up X-Client-Certificate-Fingerprint {http.request.tls.client.fingerprint}
        header_up X-Agent-Proxy-Attestation {$SERVICE_PROXY_ATTESTATION}
      }
    }
  '';

  postgres = pkgs.writeShellApplication {
    name = "local-control-postgres";
    runtimeInputs = [ pkgs.postgresql_18 ];
    text = ''
      set -eu
      if [ ! -s ${lib.escapeShellArg "${postgresDir}/PG_VERSION"} ]; then
        printf 'Local PostgreSQL data directory is not initialized; run Home Manager activation first.\n' >&2
        exit 78
      fi
      postgres_major=""
      IFS= read -r postgres_major < ${lib.escapeShellArg "${postgresDir}/PG_VERSION"} || true
      if [ "$postgres_major" != 18 ]; then
        printf 'Local PostgreSQL data directory has an incompatible major version.\n' >&2
        exit 78
      fi
      mkdir -p ${lib.escapeShellArg postgresSocketDir}
      chmod 700 ${lib.escapeShellArg postgresSocketDir}
      exec postgres \
        -D ${lib.escapeShellArg postgresDir} \
        -h 127.0.0.1 \
        -k ${lib.escapeShellArg postgresSocketDir} \
        -p ${toString cfg.postgresPort}
    '';
  };

  api = pkgs.writeShellApplication {
    name = "local-control-api";
    runtimeInputs = [
      pkgs.postgresql_18
      pkgs.uv
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${prepareDatabaseEnvironment}
      ${requirePrivateSettings [ "LOCAL_CONTROL_PROJECT_DIRECTORY" ]}
      ${waitForDatabase}
      cd "$LOCAL_CONTROL_PROJECT_DIRECTORY"
      ${runPrivateCommand "LOCAL_CONTROL_SCHEMA_COMMAND"}
      ${execPrivateCommand "LOCAL_CONTROL_API_COMMAND"}
    '';
  };

  worker = pkgs.writeShellApplication {
    name = "local-control-worker";
    runtimeInputs = [
      pkgs.postgresql_18
      pkgs.uv
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${prepareDatabaseEnvironment}
      ${requirePrivateSettings [ "LOCAL_CONTROL_PROJECT_DIRECTORY" ]}
      ${waitForDatabase}
      export OMP_NUM_THREADS=1
      export OPENBLAS_NUM_THREADS=1
      export MKL_NUM_THREADS=1
      export VECLIB_MAXIMUM_THREADS=1
      cd "$LOCAL_CONTROL_PROJECT_DIRECTORY"
      ${execPrivateCommand "LOCAL_CONTROL_WORKER_COMMAND"}
    '';
  };

  frontend = pkgs.writeShellApplication {
    name = "local-control-frontend";
    runtimeInputs = [
      pkgs.nodejs_24
      pkgs.pnpm
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${requirePrivateSettings [ "LOCAL_CONTROL_PROJECT_DIRECTORY" ]}
      cd "$LOCAL_CONTROL_PROJECT_DIRECTORY"
      ${execPrivateCommand "LOCAL_CONTROL_FRONTEND_COMMAND"}
    '';
  };

  prepare = pkgs.writeShellApplication {
    name = "local-control-prepare";
    runtimeInputs = [
      pkgs.nodejs_24
      pkgs.pnpm
      pkgs.uv
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${prepareDatabaseEnvironment}
      ${requirePrivateSettings [ "LOCAL_CONTROL_PROJECT_DIRECTORY" ]}
      cd "$LOCAL_CONTROL_PROJECT_DIRECTORY"
      ${runPrivateCommand "LOCAL_CONTROL_PREPARE_COMMAND"}
    '';
  };

  caddy = pkgs.writeShellApplication {
    name = "local-control-caddy";
    runtimeInputs = [ pkgs.caddy ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${requirePrivateSettings [ "SERVICE_PROXY_ATTESTATION" ]}
      exec caddy run --config ${lib.escapeShellArg caddyConfig} --adapter caddyfile
    '';
  };

  status = pkgs.writeShellApplication {
    name = "local-control-status";
    runtimeInputs = [
      pkgs.curl
      pkgs.postgresql_18
      pkgs.lsof
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${prepareDatabaseEnvironment}
      ${requirePrivateSettings [ "LOCAL_CONTROL_READINESS_URL" ]}
      printf 'PostgreSQL: '
      pg_isready -h 127.0.0.1 -p ${toString cfg.postgresPort}
      printf '\nApplication: '
      curl --fail --silent --show-error "$LOCAL_CONTROL_READINESS_URL"
      printf '\n\nListeners:\n'
      lsof -nP \
        -iTCP:${toString cfg.frontendPort} \
        -iTCP:${toString cfg.apiPort} \
        -iTCP:${toString cfg.agentPort} \
        -sTCP:LISTEN || true
    '';
  };

  restart = pkgs.writeShellApplication {
    name = "local-control-restart";
    text = ''
      set -eu
      domain="gui/$(id -u)"
      launchctl kickstart -k "$domain/dev.ianmh.local-control-worker"
      launchctl kickstart -k "$domain/dev.ianmh.local-control-api"
    '';
  };
in
{
  options.services.localControl = {
    enable = lib.mkEnableOption "private local application stack";

    environmentFile = lib.mkOption {
      type = lib.types.path;
      default = "${config.xdg.stateHome}/local-control/environment";
      description = "Owner-readable environment file for the private local services.";
    };

    hostOnlyAddress = lib.mkOption {
      type = lib.types.str;
      default = "172.16.42.1";
      description = "Host-only network address used by the private agent edge.";
    };

    frontendPort = lib.mkOption {
      type = lib.types.port;
      default = 5173;
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8788;
    };

    agentPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
    };

    postgresPort = lib.mkOption {
      type = lib.types.port;
      default = 55433;
    };

    proxyEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the private host-only mTLS edge for desktop clients.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin;
        message = "services.localControl is implemented for the local macOS control host.";
      }
      {
        assertion = !(lib.hasPrefix "${builtins.storeDir}/" (toString cfg.environmentFile));
        message = "services.localControl.environmentFile must remain outside the Nix store.";
      }
      {
        assertion =
          builtins.length (
            lib.unique [
              cfg.frontendPort
              cfg.apiPort
              cfg.agentPort
              cfg.postgresPort
            ]
          ) == 4;
        message = "services.localControl requires distinct frontend, API, agent, and PostgreSQL ports.";
      }
    ];

    home.packages = [
      prepare
      restart
      status
    ];

    home.activation.localControlState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu
      umask 0077
      mkdir -p \
        ${lib.escapeShellArg stateDir} \
        ${lib.escapeShellArg postgresDir} \
        ${lib.escapeShellArg postgresSocketDir} \
        ${lib.escapeShellArg pkiDir} \
        ${lib.escapeShellArg logDir}
      chmod 700 \
        ${lib.escapeShellArg stateDir} \
        ${lib.escapeShellArg postgresDir} \
        ${lib.escapeShellArg postgresSocketDir} \
        ${lib.escapeShellArg pkiDir} \
        ${lib.escapeShellArg logDir}

      postgres_version_file=${lib.escapeShellArg "${postgresDir}/PG_VERSION"}
      if [ -e "$postgres_version_file" ] || [ -L "$postgres_version_file" ]; then
        if [ ! -f "$postgres_version_file" ] || [ -L "$postgres_version_file" ] || [ ! -s "$postgres_version_file" ]; then
          printf 'Refusing to use an invalid local PostgreSQL data directory.\n' >&2
          exit 1
        fi
        postgres_major=""
        IFS= read -r postgres_major < "$postgres_version_file" || true
        if [ "$postgres_major" != 18 ]; then
          printf 'Refusing to use a local PostgreSQL data directory with an incompatible major version.\n' >&2
          exit 1
        fi
      elif [ -n "$( ${pkgs.findutils}/bin/find ${lib.escapeShellArg postgresDir} -mindepth 1 -maxdepth 1 -print -quit )" ]; then
        printf 'Refusing to initialize a non-empty local PostgreSQL data directory.\n' >&2
        exit 1
      else
        ${pkgs.postgresql_18}/bin/initdb \
          --pgdata=${lib.escapeShellArg postgresDir} \
          --auth-local=trust \
          --auth-host=scram-sha-256 \
          --encoding=UTF8 \
          --no-locale
      fi

      if [ -e ${lib.escapeShellArg environmentFile} ] || [ -L ${lib.escapeShellArg environmentFile} ]; then
        if [ -L ${lib.escapeShellArg environmentFile} ] || [ ! -f ${lib.escapeShellArg environmentFile} ]; then
          printf 'Private service environment must be a regular file.\n' >&2
          exit 1
        fi
      else
        : > ${lib.escapeShellArg environmentFile}
      fi
      chmod 600 ${lib.escapeShellArg environmentFile}

      if [ ! -f ${lib.escapeShellArg "${pkiDir}/ca.crt"} ]; then
        ${pkgs.openssl}/bin/openssl req -x509 -new -nodes -sha256 -days 3650 \
          -newkey rsa:3072 \
          -keyout ${lib.escapeShellArg "${pkiDir}/ca.key"} \
          -out ${lib.escapeShellArg "${pkiDir}/ca.crt"} \
          -subj '/CN=Local Service CA' \
          -addext 'basicConstraints=critical,CA:TRUE' \
          -addext 'keyUsage=critical,keyCertSign,cRLSign'
        chmod 600 ${lib.escapeShellArg "${pkiDir}/ca.key"}
        chmod 644 ${lib.escapeShellArg "${pkiDir}/ca.crt"}
      fi

      if [ ! -f ${lib.escapeShellArg "${pkiDir}/server.crt"} ]; then
        certificate_extensions="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${stateDir}/server-ext.XXXXXX"})"
        cat > "$certificate_extensions" <<'EOF'
      basicConstraints=critical,CA:FALSE
      keyUsage=critical,digitalSignature,keyEncipherment
      extendedKeyUsage=serverAuth
      subjectAltName=IP:${cfg.hostOnlyAddress}
      EOF
        ${pkgs.openssl}/bin/openssl req -new -nodes -newkey rsa:3072 \
          -keyout ${lib.escapeShellArg "${pkiDir}/server.key"} \
          -out ${lib.escapeShellArg "${pkiDir}/server.csr"} \
          -subj '/CN=${cfg.hostOnlyAddress}'
        ${pkgs.openssl}/bin/openssl x509 -req -sha256 -days 825 \
          -in ${lib.escapeShellArg "${pkiDir}/server.csr"} \
          -CA ${lib.escapeShellArg "${pkiDir}/ca.crt"} \
          -CAkey ${lib.escapeShellArg "${pkiDir}/ca.key"} \
          -CAcreateserial \
          -out ${lib.escapeShellArg "${pkiDir}/server.crt"} \
          -extfile "$certificate_extensions"
        ${pkgs.coreutils}/bin/rm -f "$certificate_extensions"
        chmod 600 ${lib.escapeShellArg "${pkiDir}/server.key"}
        chmod 644 ${lib.escapeShellArg "${pkiDir}/server.crt"}
      fi

      if [ ! -f ${lib.escapeShellArg "${pkiDir}/desktop-client.pfx"} ]; then
        certificate_extensions="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${stateDir}/client-ext.XXXXXX"})"
        cat > "$certificate_extensions" <<'EOF'
      basicConstraints=critical,CA:FALSE
      keyUsage=critical,digitalSignature,keyEncipherment
      extendedKeyUsage=clientAuth
      EOF
        ${pkgs.openssl}/bin/openssl req -new -nodes -newkey rsa:3072 \
          -keyout ${lib.escapeShellArg "${pkiDir}/desktop-client.key"} \
          -out ${lib.escapeShellArg "${pkiDir}/desktop-client.csr"} \
          -subj '/CN=desktop-client'
        ${pkgs.openssl}/bin/openssl x509 -req -sha256 -days 825 \
          -in ${lib.escapeShellArg "${pkiDir}/desktop-client.csr"} \
          -CA ${lib.escapeShellArg "${pkiDir}/ca.crt"} \
          -CAkey ${lib.escapeShellArg "${pkiDir}/ca.key"} \
          -CAcreateserial \
          -out ${lib.escapeShellArg "${pkiDir}/desktop-client.crt"} \
          -extfile "$certificate_extensions"
        ${pkgs.openssl}/bin/openssl pkcs12 -export \
          -out ${lib.escapeShellArg "${pkiDir}/desktop-client.pfx"} \
          -inkey ${lib.escapeShellArg "${pkiDir}/desktop-client.key"} \
          -in ${lib.escapeShellArg "${pkiDir}/desktop-client.crt"} \
          -certfile ${lib.escapeShellArg "${pkiDir}/ca.crt"} \
          -passout pass:
        ${pkgs.coreutils}/bin/rm -f "$certificate_extensions"
        chmod 600 \
          ${lib.escapeShellArg "${pkiDir}/desktop-client.key"} \
          ${lib.escapeShellArg "${pkiDir}/desktop-client.pfx"}
        chmod 644 ${lib.escapeShellArg "${pkiDir}/desktop-client.crt"}
      fi
    '';

    launchd.agents.local-control-postgres = {
      enable = true;
      config = {
        Label = "dev.ianmh.local-control-postgres";
        ProgramArguments = [ "${postgres}/bin/local-control-postgres" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/postgres.out.log";
        StandardErrorPath = "${logDir}/postgres.err.log";
      };
    };

    launchd.agents.local-control-api = {
      enable = true;
      config = {
        Label = "dev.ianmh.local-control-api";
        ProgramArguments = [ "${api}/bin/local-control-api" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/api.out.log";
        StandardErrorPath = "${logDir}/api.err.log";
      };
    };

    launchd.agents.local-control-worker = {
      enable = true;
      config = {
        Label = "dev.ianmh.local-control-worker";
        ProgramArguments = [ "${worker}/bin/local-control-worker" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Interactive";
        StandardOutPath = "${logDir}/worker.out.log";
        StandardErrorPath = "${logDir}/worker.err.log";
      };
    };

    launchd.agents.local-control-frontend = {
      enable = true;
      config = {
        Label = "dev.ianmh.local-control-frontend";
        ProgramArguments = [ "${frontend}/bin/local-control-frontend" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/frontend.out.log";
        StandardErrorPath = "${logDir}/frontend.err.log";
      };
    };

    launchd.agents.local-control-caddy = lib.mkIf cfg.proxyEnable {
      enable = true;
      config = {
        Label = "dev.ianmh.local-control-caddy";
        ProgramArguments = [ "${caddy}/bin/local-control-caddy" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/caddy.out.log";
        StandardErrorPath = "${logDir}/caddy.err.log";
      };
    };
  };
}
