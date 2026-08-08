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
  preparationStamp = "${stateDir}/preparation-stamp";

  privateServiceSettings = [
    "LOCAL_CONTROL_PROJECT_DIRECTORY"
    "LOCAL_CONTROL_DATABASE_URL"
    "LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE"
    "LOCAL_CONTROL_SCHEMA_COMMAND"
    "LOCAL_CONTROL_API_COMMAND"
    "LOCAL_CONTROL_WORKER_COMMAND"
    "LOCAL_CONTROL_FRONTEND_COMMAND"
    "LOCAL_CONTROL_PREPARE_COMMAND"
    "LOCAL_CONTROL_PREPARATION_INPUT"
    "LOCAL_CONTROL_READINESS_URL"
    "SERVICE_PROXY_ATTESTATION"
  ];

  requirePrivateSettings =
    names:
    lib.concatMapStringsSep "\n" (name: ''
      if [ -z "''${${name}:-}" ]; then
        printf 'Missing required private service setting: ${name}\n' >&2
        exit 78
      fi
    '') names;

  checkPrivateSettings =
    names:
    lib.concatMapStringsSep "\n" (name: ''
      if [ -z "''${${name}:-}" ]; then
        return 1
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

  validateDatabaseEnvironment = ''
    validate_database_environment() {
      case "''${LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE:-}" in
        [A-Za-z_]* )
          case "$LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE" in
            *[!A-Za-z0-9_]* )
              return 1
              ;;
          esac
          ;;
        * )
          return 1
          ;;
      esac
    }
  '';

  prepareDatabaseEnvironment = ''
    ${requirePrivateSettings [
      "LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE"
      "LOCAL_CONTROL_DATABASE_URL"
    ]}
    ${validateDatabaseEnvironment}
    if ! validate_database_environment; then
      printf 'The configured database environment variable name is invalid.\n' >&2
      exit 64
    fi
    export "$LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE=$LOCAL_CONTROL_DATABASE_URL"
  '';

  computePreparationState = ''
    compute_preparation_state() {
      preparation_project_directory="$(cd "$LOCAL_CONTROL_PROJECT_DIRECTORY" 2>/dev/null && pwd -P)" || return 1
      [ -d "$preparation_project_directory" ] || return 1

      preparation_revision="unversioned"
      preparation_files_digest="unversioned"
      if git -C "$preparation_project_directory" rev-parse --show-toplevel >/dev/null 2>&1; then
        preparation_revision="$(git -C "$preparation_project_directory" rev-parse --verify HEAD 2>/dev/null)" || return 1
        preparation_files_digest="$(
          git -C "$preparation_project_directory" ls-files -co --exclude-standard -z |
            while IFS= read -r -d "" preparation_file; do
              preparation_path="$preparation_project_directory/$preparation_file"
              if [ -f "$preparation_path" ] && [ ! -L "$preparation_path" ]; then
                printf '%s\0' "$preparation_file"
                sha256sum "$preparation_path"
              fi
            done |
            sha256sum |
            cut -d ' ' -f 1
        )" || return 1
      fi

      preparation_command_digest="$(printf '%s' "$LOCAL_CONTROL_PREPARE_COMMAND" | sha256sum | cut -d ' ' -f 1)" || return 1
      preparation_state="$(
        printf '%s\0%s\0%s\0%s\0%s' \
          "$preparation_project_directory" \
          "$LOCAL_CONTROL_PREPARATION_INPUT" \
          "$preparation_revision" \
          "$preparation_files_digest" \
          "$preparation_command_digest" |
          sha256sum |
          cut -d ' ' -f 1
      )" || return 1
    }
  '';

  checkPreparationStamp = ''
    preparation_stamp_matches() {
      if [ -L ${lib.escapeShellArg preparationStamp} ] || [ ! -f ${lib.escapeShellArg preparationStamp} ]; then
        return 1
      fi
      if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' ${lib.escapeShellArg preparationStamp} )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
        return 1
      fi
      preparation_stamp_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' ${lib.escapeShellArg preparationStamp} )"
      if (( (8#$preparation_stamp_mode & 0077) != 0 )); then
        return 1
      fi
      if [ "$(wc -l < ${lib.escapeShellArg preparationStamp} | tr -d ' ')" != 1 ]; then
        return 1
      fi
      [ "$(tr -d '\n' < ${lib.escapeShellArg preparationStamp})" = "$preparation_state" ]
    }
  '';

  requirePreparation = ''
    ${requirePrivateSettings [
      "LOCAL_CONTROL_PROJECT_DIRECTORY"
      "LOCAL_CONTROL_PREPARE_COMMAND"
      "LOCAL_CONTROL_PREPARATION_INPUT"
    ]}
    ${computePreparationState}
    ${checkPreparationStamp}
    if ! compute_preparation_state || ! preparation_stamp_matches; then
      printf 'Local services require a successful owner-run local-control-prepare for the current checkout and inputs.\n' >&2
      exit 78
    fi
  '';

  privateEnvironmentReady = ''
    private_environment_ready() {
      if [ ! -f ${lib.escapeShellArg environmentFile} ] || [ -L ${lib.escapeShellArg environmentFile} ]; then
        return 1
      fi
      if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' ${lib.escapeShellArg environmentFile} )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
        return 1
      fi
      private_environment_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' ${lib.escapeShellArg environmentFile} )"
      if (( (8#$private_environment_mode & 0077) != 0 )); then
        return 1
      fi
      set -a
      # shellcheck disable=SC1091
      . ${lib.escapeShellArg environmentFile}
      set +a
      ${checkPrivateSettings privateServiceSettings}
      ${validateDatabaseEnvironment}
      validate_database_environment || return 1
    }
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

  validatePostgresCluster = ''
    validate_postgres_cluster() {
      postgres_data_dir="$1"
      if [ -L "$postgres_data_dir" ] || [ ! -d "$postgres_data_dir" ]; then
        return 1
      fi
      if [ "$( stat -c '%u' "$postgres_data_dir" )" != "$( id -u )" ]; then
        return 1
      fi
      postgres_dir_mode="$( stat -c '%a' "$postgres_data_dir" )"
      if (( (8#$postgres_dir_mode & 0077) != 0 )); then
        return 1
      fi
      for postgres_control_file in PG_VERSION postgresql.conf pg_hba.conf pg_ident.conf; do
        postgres_control_path="$postgres_data_dir/$postgres_control_file"
        if [ -L "$postgres_control_path" ] || [ ! -f "$postgres_control_path" ]; then
          return 1
        fi
        if [ "$( stat -c '%u' "$postgres_control_path" )" != "$( id -u )" ]; then
          return 1
        fi
        postgres_control_mode="$( stat -c '%a' "$postgres_control_path" )"
        if (( (8#$postgres_control_mode & 0077) != 0 )); then
          return 1
        fi
      done
      for postgres_control_dir in base global pg_wal; do
        postgres_control_path="$postgres_data_dir/$postgres_control_dir"
        if [ -L "$postgres_control_path" ] || [ ! -d "$postgres_control_path" ]; then
          return 1
        fi
        if [ "$( stat -c '%u' "$postgres_control_path" )" != "$( id -u )" ]; then
          return 1
        fi
        postgres_control_mode="$( stat -c '%a' "$postgres_control_path" )"
        if (( (8#$postgres_control_mode & 0077) != 0 )); then
          return 1
        fi
      done
      postgres_major=""
      IFS= read -r postgres_major < "$postgres_data_dir/PG_VERSION" || true
      [ "$postgres_major" = 18 ] || return 1
      pg_controldata "$postgres_data_dir" >/dev/null 2>&1
    }
  '';

  serviceGate = pkgs.writeShellApplication {
    name = "local-control-service-gate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      set -eu
      if [ "$#" -lt 1 ]; then
        printf 'A service command is required.\n' >&2
        exit 64
      fi
      ${privateEnvironmentReady}
      if ! private_environment_ready; then
        printf 'Private service environment or preparation proof is not ready; run local-control-prepare after configuring it.\n' >&2
        exit 0
      fi
      ${computePreparationState}
      ${checkPreparationStamp}
      if ! compute_preparation_state || ! preparation_stamp_matches; then
        printf 'Local service preparation is stale; run local-control-prepare before starting services.\n' >&2
        exit 0
      fi
      exec "$@"
    '';
  };

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
    runtimeInputs = [
      pkgs.coreutils
      pkgs.postgresql_18
    ];
    text = ''
      set -eu
      ${validatePostgresCluster}
      if ! validate_postgres_cluster ${lib.escapeShellArg postgresDir}; then
        printf 'Local PostgreSQL data directory is incomplete, unsafe, or corrupt.\n' >&2
        exit 0
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
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${prepareDatabaseEnvironment}
      ${requirePrivateSettings [ "LOCAL_CONTROL_PROJECT_DIRECTORY" ]}
      ${requirePreparation}
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
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${prepareDatabaseEnvironment}
      ${requirePrivateSettings [ "LOCAL_CONTROL_PROJECT_DIRECTORY" ]}
      ${requirePreparation}
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
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${requirePrivateSettings [ "LOCAL_CONTROL_PROJECT_DIRECTORY" ]}
      ${requirePreparation}
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
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${prepareDatabaseEnvironment}
      ${requirePrivateSettings [
        "LOCAL_CONTROL_PROJECT_DIRECTORY"
        "LOCAL_CONTROL_PREPARE_COMMAND"
        "LOCAL_CONTROL_PREPARATION_INPUT"
      ]}
      cd "$LOCAL_CONTROL_PROJECT_DIRECTORY"
      ${runPrivateCommand "LOCAL_CONTROL_PREPARE_COMMAND"}
      umask 077
      if [ -L ${lib.escapeShellArg preparationStamp} ] || [ -e ${lib.escapeShellArg preparationStamp} ] && [ ! -f ${lib.escapeShellArg preparationStamp} ]; then
        printf 'Preparation proof path must be a regular file.\n' >&2
        exit 1
      fi
      ${computePreparationState}
      preparation_stamp_tmp="$(mktemp ${lib.escapeShellArg "${preparationStamp}.XXXXXX"})"
      printf '%s\n' "$preparation_state" > "$preparation_stamp_tmp"
      chmod 600 "$preparation_stamp_tmp"
      mv -f "$preparation_stamp_tmp" ${lib.escapeShellArg preparationStamp}
    '';
  };

  caddy = pkgs.writeShellApplication {
    name = "local-control-caddy";
    runtimeInputs = [
      pkgs.caddy
      pkgs.coreutils
    ];
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
      pkgs.coreutils
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
      for service in worker api frontend caddy; do
        label="$domain/dev.ianmh.local-control-$service"
        if launchctl print "$label" >/dev/null 2>&1; then
          launchctl kickstart -k "$label"
        fi
      done
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
      state_dir_preexisting=false
      if [ -L ${lib.escapeShellArg stateDir} ] || [ -e ${lib.escapeShellArg stateDir} ] && [ ! -d ${lib.escapeShellArg stateDir} ]; then
        printf 'Local service state directory must be a real directory.\n' >&2
        exit 1
      fi
      if [ -d ${lib.escapeShellArg stateDir} ]; then
        state_dir_preexisting=true
      fi
      mkdir -p ${lib.escapeShellArg stateDir}
      if [ "$state_dir_preexisting" = true ]; then
        if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' ${lib.escapeShellArg stateDir} )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
          printf 'Local service state directory must be owned by the current user.\n' >&2
          exit 1
        fi
        state_dir_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' ${lib.escapeShellArg stateDir} )"
        if (( (8#$state_dir_mode & 0077) != 0 )); then
          printf 'Local service state directory must not be accessible to group or others.\n' >&2
          exit 1
        fi
      fi
      chmod 700 ${lib.escapeShellArg stateDir}

      postgres_dir_preexisting=false
      if [ -L ${lib.escapeShellArg postgresDir} ] || [ -e ${lib.escapeShellArg postgresDir} ] && [ ! -d ${lib.escapeShellArg postgresDir} ]; then
        printf 'Refusing a symlinked or non-directory PostgreSQL data path.\n' >&2
        exit 1
      fi
      if [ -d ${lib.escapeShellArg postgresDir} ]; then
        postgres_dir_preexisting=true
      else
        mkdir ${lib.escapeShellArg postgresDir}
      fi
      if [ "$postgres_dir_preexisting" = true ]; then
        if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' ${lib.escapeShellArg postgresDir} )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
          printf 'Refusing a PostgreSQL data directory not owned by the current user.\n' >&2
          exit 1
        fi
        postgres_dir_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' ${lib.escapeShellArg postgresDir} )"
        if (( (8#$postgres_dir_mode & 0077) != 0 )); then
          printf 'Refusing a PostgreSQL data directory accessible to group or others.\n' >&2
          exit 1
        fi
      fi
      chmod 700 ${lib.escapeShellArg postgresDir}

      postgres_version_file=${lib.escapeShellArg "${postgresDir}/PG_VERSION"}
      if [ -L "$postgres_version_file" ] || [ -e "$postgres_version_file" ] && [ ! -f "$postgres_version_file" ]; then
        printf 'Refusing an invalid PostgreSQL cluster marker.\n' >&2
        exit 1
      fi
      if [ -f "$postgres_version_file" ]; then
        ${validatePostgresCluster}
        if ! validate_postgres_cluster ${lib.escapeShellArg postgresDir}; then
          printf 'Refusing an incomplete, unsafe, or corrupt PostgreSQL data directory.\n' >&2
          exit 1
        fi
      elif [ -n "$( ${pkgs.findutils}/bin/find ${lib.escapeShellArg postgresDir} -mindepth 1 -maxdepth 1 -print -quit )" ]; then
        printf 'Refusing to initialize a non-empty PostgreSQL data directory without a valid cluster marker.\n' >&2
        exit 1
      else
        ${pkgs.postgresql_18}/bin/initdb \
          --pgdata=${lib.escapeShellArg postgresDir} \
          --auth-local=trust \
          --auth-host=scram-sha-256 \
          --encoding=UTF8 \
          --no-locale
        ${validatePostgresCluster}
        if ! validate_postgres_cluster ${lib.escapeShellArg postgresDir}; then
          printf 'PostgreSQL initialization did not produce a valid cluster.\n' >&2
          exit 1
        fi
      fi

      if [ -e ${lib.escapeShellArg environmentFile} ] || [ -L ${lib.escapeShellArg environmentFile} ]; then
        if [ -L ${lib.escapeShellArg environmentFile} ] || [ ! -f ${lib.escapeShellArg environmentFile} ]; then
          printf 'Private service environment must be a regular file.\n' >&2
          exit 1
        fi
        if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' ${lib.escapeShellArg environmentFile} )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
          printf 'Private service environment must be owned by the current user.\n' >&2
          exit 1
        fi
        environment_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' ${lib.escapeShellArg environmentFile} )"
        if (( (8#$environment_mode & 0077) != 0 )); then
          printf 'Private service environment must not be readable by group or others.\n' >&2
          exit 1
        fi
      else
        printf 'Private service environment is not configured; services remain gated until it is created by the owner.\n' >&2
      fi

      mkdir -p \
        ${lib.escapeShellArg postgresSocketDir} \
        ${lib.escapeShellArg pkiDir} \
        ${lib.escapeShellArg logDir}
      chmod 700 \
        ${lib.escapeShellArg postgresSocketDir} \
        ${lib.escapeShellArg pkiDir} \
        ${lib.escapeShellArg logDir}

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
        KeepAlive = {
          SuccessfulExit = false;
        };
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
        ProgramArguments = [
          "${serviceGate}/bin/local-control-service-gate"
          "${api}/bin/local-control-api"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
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
        ProgramArguments = [
          "${serviceGate}/bin/local-control-service-gate"
          "${worker}/bin/local-control-worker"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
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
        ProgramArguments = [
          "${serviceGate}/bin/local-control-service-gate"
          "${frontend}/bin/local-control-frontend"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
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
        ProgramArguments = [
          "${serviceGate}/bin/local-control-service-gate"
          "${caddy}/bin/local-control-caddy"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        ThrottleInterval = 10;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/caddy.out.log";
        StandardErrorPath = "${logDir}/caddy.err.log";
      };
    };
  };
}
