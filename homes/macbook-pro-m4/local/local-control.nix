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
  databaseDir = "${stateDir}/database";
  databaseSocketDir = "${stateDir}/database-socket";
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
  ]
  ++ lib.optionals cfg.proxyEnable [ "SERVICE_PROXY_ATTESTATION" ];

  localControlLibrary = import ../../../lib/local-control/postgres-cluster-validator.nix { };
  preparationProof = localControlLibrary.mkPreparationProof pkgs;
  privatePathGuard = localControlLibrary.mkPrivatePathGuard pkgs;
  secureFileSystem = localControlLibrary.mkSecureFileSystem pkgs;
  environmentSnapshot = localControlLibrary.mkEnvironmentSnapshot pkgs;
  sourceTreeSnapshot = localControlLibrary.mkSourceTreeSnapshot pkgs;

  launchConfigurationDigest = builtins.hashString "sha256" (
    builtins.toJSON {
      moduleSource = builtins.hashString "sha256" (builtins.readFile ./local-control.nix);
      safetyLibrarySource = builtins.hashString "sha256" (
        builtins.readFile ../../../lib/local-control/postgres-cluster-validator.nix
      );
      secureFileSystemSource = builtins.hashString "sha256" (
        builtins.readFile ../../../lib/local-control/secure-files.c
      );
      environmentFile = toString environmentFile;
      stateDirectory = stateDir;
      databaseDirectory = databaseDir;
      databaseSocketDirectory = databaseSocketDir;
      pkiDirectory = pkiDir;
      logDirectory = logDir;
      inherit preparationStamp;
      environmentSnapshot = "${environmentSnapshot}/bin/local-control-environment-snapshot";
      sourceTreeSnapshot = "${sourceTreeSnapshot}/bin/local-control-source-snapshot";
      runtimeStorePathIdentities = {
        bash = "${pkgs.bash}/bin/bash";
        proxy = "${pkgs.caddy}/bin/caddy";
        coreutils = "${pkgs.coreutils}/bin";
        curl = "${pkgs.curl}/bin/curl";
        git = "${pkgs.git}/bin/git";
        lsof = "${pkgs.lsof}/bin/lsof";
        node = "${pkgs.nodejs_24}/bin/node";
        openssl = "${pkgs.openssl}/bin/openssl";
        packageManager = "${pkgs.pnpm}/bin/pnpm";
        database = "${pkgs.postgresql_18}/bin/postgres";
        databaseControlData = "${pkgs.postgresql_18}/bin/pg_controldata";
        databaseReadiness = "${pkgs.postgresql_18}/bin/pg_isready";
        pythonRunner = "${pkgs.uv}/bin/uv";
        secureFileSystem = "${secureFileSystem}/bin/local-control-secure-files";
        validator = "${databaseClusterValidator}/bin/local-control-validate-database-cluster";
        pathGuard = "${privatePathGuard}/bin/local-control-private-path";
        proof = "${preparationProof}/bin/local-control-preparation-proof";
        serviceGate = "${serviceGate}/bin/local-control-service-gate";
        databaseLauncher = "${database}/bin/local-control-database";
        proxyLauncher = "${proxy}/bin/local-control-proxy";
        proxyConfiguration = toString proxyConfig;
        initdb = "${pkgs.postgresql_18}/bin/initdb";
      };
      inherit (cfg) bindAddress;
      inherit (cfg) webPort;
      inherit (cfg) apiPort;
      inherit (cfg) proxyPort;
      inherit (cfg) databasePort;
      inherit (cfg) proxyEnable;
    }
  );

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
    load_private_environment() {
      set -eu
      if [ -n "''${LOCAL_CONTROL_ENVIRONMENT_SNAPSHOT:-}" ]; then
        environment_source="$LOCAL_CONTROL_ENVIRONMENT_SNAPSHOT"
      else
        environment_source=${lib.escapeShellArg (toString environmentFile)}
      fi
      environment_snapshot="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${stateDir}/environment-snapshot.XXXXXX"})" || return 1
      if ! ${environmentSnapshot}/bin/local-control-environment-snapshot read \
        "$environment_source" \
        ${
          lib.escapeShellArg (if cfg.proxyEnable then "enabled" else "disabled")
        } > "$environment_snapshot"; then
        ${pkgs.coreutils}/bin/rm -f "$environment_snapshot"
        return 1
      fi
      environment_seen='|'
      for environment_name in ${lib.concatStringsSep " " privateServiceSettings}; do
        unset "$environment_name"
      done
      while IFS= read -r environment_line || [ -n "$environment_line" ]; do
        case "$environment_line" in
          ""|\#*)
            continue
            ;;
          *=*)
            environment_name="''${environment_line%%=*}"
            environment_value="''${environment_line#*=}"
            ;;
          *)
            printf 'The environment snapshot is not a NAME=VALUE file.\n' >&2
            return 1
            ;;
        esac
        case "$environment_name" in
          ${lib.concatStringsSep "|" privateServiceSettings})
            ;;
          *)
            printf 'The environment snapshot contains an unsupported setting.\n' >&2
            return 1
            ;;
        esac
        case "$environment_seen" in
          *"|$environment_name|"*)
            printf 'The environment snapshot contains a duplicate setting.\n' >&2
            return 1
            ;;
        esac
        environment_seen="''${environment_seen}''${environment_name}|"
        export "$environment_name=$environment_value"
      done < "$environment_snapshot"
      ${checkPrivateSettings privateServiceSettings}
      ${validateDatabaseEnvironment}
      validate_database_environment || return 1
    }
    load_private_environment || {
      printf 'The service environment is missing, unsafe, or invalid.\n' >&2
      exit 78
    }
  '';

  cleanupPrivateEnvironment = ''
    cleanup_private_environment() {
      if [ -n "''${environment_snapshot:-}" ]; then
        ${pkgs.coreutils}/bin/rm -f "$environment_snapshot"
        unset environment_snapshot
      fi
      unset LOCAL_CONTROL_ENVIRONMENT_SNAPSHOT
    }
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
      preparation_state="$(${preparationProof}/bin/local-control-preparation-proof compute \
        ${lib.escapeShellArg launchConfigurationDigest} \
        ${lib.escapeShellArg (if cfg.proxyEnable then "enabled" else "disabled")} \
        "$environment_snapshot")" || return 1
    }
  '';

  checkPreparationStamp = ''
    preparation_stamp_matches() {
      preparation_stamp_value="$(${secureFileSystem}/bin/local-control-secure-files read-file \
        ${lib.escapeShellArg preparationStamp} 600)" || return 1
      [ "$preparation_stamp_value" = "$preparation_state" ]
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

  waitForDatabase = ''
    attempt=0
    until ${pkgs.postgresql_18}/bin/pg_isready \
      -h 127.0.0.1 \
      -p ${toString cfg.databasePort} >/dev/null 2>&1; do
      attempt=$((attempt + 1))
      if [ "$attempt" -ge 60 ]; then
        printf 'Timed out waiting for database readiness.\n' >&2
        exit 75
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';

  databaseClusterValidator = localControlLibrary.mkDatabaseClusterValidator pkgs;

  serviceGate = localControlLibrary.mkPreparationGate pkgs;
  serviceGateArguments = [
    "${serviceGate}/bin/local-control-service-gate"
    (toString environmentFile)
    preparationStamp
    stateDir
    launchConfigurationDigest
    (if cfg.proxyEnable then "enabled" else "disabled")
  ];

  runPrivateCommand = setting: ''
    ${requirePrivateSettings [ setting ]}
    ${secureFileSystem}/bin/local-control-secure-files exec-source \
      "$LOCAL_CONTROL_PROJECT_DIRECTORY" \
      ${pkgs.bash}/bin/bash -o errexit -o pipefail -c "''${${setting}}"
  '';

  execPrivateCommand = setting: ''
    ${requirePrivateSettings [ setting ]}
    ${cleanupPrivateEnvironment}
    cleanup_private_environment
    exec ${secureFileSystem}/bin/local-control-secure-files exec-source \
      "$LOCAL_CONTROL_PROJECT_DIRECTORY" \
      ${pkgs.bash}/bin/bash -o errexit -o pipefail -c "''${${setting}}"
  '';

  proxyConfig = pkgs.writeText "local-control-proxy.conf" ''
    {
      admin off
      auto_https off
      servers {
        protocols h1 h2
        strict_sni_host insecure_off
      }
    }

      https://${cfg.bindAddress}:${toString cfg.proxyPort} {
        bind ${cfg.bindAddress}
        tls {$LOCAL_CONTROL_PROXY_CERT} {$LOCAL_CONTROL_PROXY_KEY} {
          client_auth {
          trust_pool file {$LOCAL_CONTROL_PROXY_CA}
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

  serverCertificateExtensions = pkgs.writeText "local-control-server-extensions" ''
    basicConstraints=critical,CA:FALSE
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=serverAuth
        subjectAltName=IP:${cfg.bindAddress}
  '';

  clientCertificateExtensions = pkgs.writeText "local-control-client-extensions" ''
    basicConstraints=critical,CA:FALSE
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=clientAuth
  '';

  database = pkgs.writeShellApplication {
    name = "local-control-database";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.postgresql_18
    ];
    text = ''
      set -eu
      if ! ${privatePathGuard}/bin/local-control-private-path validate-directory \
        ${lib.escapeShellArg databaseDir} \
        'Local database directory'; then
        exit 0
      fi
      if ! ${databaseClusterValidator}/bin/local-control-validate-database-cluster ${lib.escapeShellArg databaseDir}; then
        printf 'Local database directory is incomplete, unsafe, or corrupt.\n' >&2
        exit 0
      fi
      if ! ${privatePathGuard}/bin/local-control-private-path validate-directory \
        ${lib.escapeShellArg databaseSocketDir} \
        'Local database socket directory'; then
        exit 0
      fi
      exec ${secureFileSystem}/bin/local-control-secure-files exec-cluster-socket \
        ${lib.escapeShellArg databaseDir} 18 \
        ${lib.escapeShellArg databaseSocketDir} \
        ${pkgs.postgresql_18}/bin/postgres \
        -D . \
        -h 127.0.0.1 \
        -k @socket@ \
        -p ${toString cfg.databasePort}
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
      ${requirePrivateSettings privateServiceSettings}
      ${runPrivateCommand "LOCAL_CONTROL_PREPARE_COMMAND"}
      umask 077
      ${computePreparationState}
      compute_preparation_state
      printf '%s\n' "$preparation_state" | \
        ${secureFileSystem}/bin/local-control-secure-files atomic-write \
          ${lib.escapeShellArg preparationStamp} 600
      ${cleanupPrivateEnvironment}
      cleanup_private_environment
    '';
  };

  proxy = pkgs.writeShellApplication {
    name = "local-control-proxy";
    runtimeInputs = [
      pkgs.caddy
      pkgs.coreutils
    ];
    text = ''
      set -eu
      ${loadPrivateEnvironment}
      ${requirePrivateSettings [ "SERVICE_PROXY_ATTESTATION" ]}
      ${cleanupPrivateEnvironment}
      cleanup_private_environment
      exec ${secureFileSystem}/bin/local-control-secure-files exec-proxy \
        ${lib.escapeShellArg pkiDir} \
        ${pkgs.caddy}/bin/caddy \
        run --config ${lib.escapeShellArg proxyConfig} --adapter caddyfile
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
      printf 'Database: '
      pg_isready -h 127.0.0.1 -p ${toString cfg.databasePort}
      printf '\nService: '
      curl --fail --silent --show-error "$LOCAL_CONTROL_READINESS_URL"
      printf '\n\nListeners:\n'
      lsof -nP \
        -iTCP:${toString cfg.webPort} \
        -iTCP:${toString cfg.apiPort} \
        -iTCP:${toString cfg.proxyPort} \
        -sTCP:LISTEN || true
      ${cleanupPrivateEnvironment}
      cleanup_private_environment
    '';
  };

  restart = pkgs.writeShellApplication {
    name = "local-control-restart";
    text = ''
      set -eu
      domain="gui/$(id -u)"
      for service in worker api frontend proxy; do
        label="$domain/local.services.local-control-$service"
        if launchctl print "$label" >/dev/null 2>&1; then
          launchctl kickstart -k "$label"
        fi
      done
    '';
  };
in
{
  options.services.localControl = {
    enable = lib.mkEnableOption "private local services";

    environmentFile = lib.mkOption {
      type = lib.types.path;
      default = "${config.xdg.stateHome}/local-control/environment";
      description = "Owner-readable environment file for the private services.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "172.16.42.1";
      description = "Address used by the optional private listener.";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 5173;
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8788;
    };

    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
    };

    databasePort = lib.mkOption {
      type = lib.types.port;
      default = 55433;
    };

    proxyEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the optional authenticated listener for local clients.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin;
        message = "services.localControl requires a supported desktop host.";
      }
      {
        assertion = !(lib.hasPrefix "${builtins.storeDir}/" (toString cfg.environmentFile));
        message = "services.localControl.environmentFile must remain outside the Nix store.";
      }
      {
        assertion =
          builtins.length (
            lib.unique [
              cfg.webPort
              cfg.apiPort
              cfg.proxyPort
              cfg.databasePort
            ]
          ) == 4;
        message = "services.localControl requires distinct web, API, proxy, and database ports.";
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
      ${privatePathGuard}/bin/local-control-private-path ensure-directory \
        ${lib.escapeShellArg stateDir} \
        'Local service state directory'
      ${privatePathGuard}/bin/local-control-private-path ensure-directory \
        ${lib.escapeShellArg databaseDir} \
        'Local database directory'

      database_state="$(${secureFileSystem}/bin/local-control-secure-files cluster-state \
        ${lib.escapeShellArg databaseDir} 18)" || {
        printf 'Refusing an incomplete, unsafe, or incompatible database directory.\n' >&2
        exit 1
      }
      if [ "$database_state" = missing ]; then
        if ! ${secureFileSystem}/bin/local-control-secure-files initialize-cluster \
          ${lib.escapeShellArg databaseDir} \
          18 \
          ${pkgs.postgresql_18}/bin/initdb \
          --pgdata=. \
          --auth-local=trust \
          --auth-host=scram-sha-256 \
          --encoding=UTF8 \
          --no-locale; then
          printf 'Refusing to initialize an unsafe database directory.\n' >&2
          exit 1
        fi
      fi

      environment_file_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg (toString environmentFile)} 600)" || {
        printf 'Private service environment must be a safe regular file.\n' >&2
        exit 1
      }
      if [ "$environment_file_state" = missing ]; then
        printf 'Private service environment is not configured; services remain gated until it is created by the owner.\n' >&2
      fi

      ${privatePathGuard}/bin/local-control-private-path ensure-directory \
        ${lib.escapeShellArg databaseSocketDir} \
        'Local database socket directory'
      ${privatePathGuard}/bin/local-control-private-path ensure-directory \
        ${lib.escapeShellArg pkiDir} \
        'Local service PKI directory'
      ${privatePathGuard}/bin/local-control-private-path ensure-directory \
        ${lib.escapeShellArg logDir} \
        'Local service log directory'

      check_optional_generated_file() {
        if ! ${secureFileSystem}/bin/local-control-secure-files inspect-file "$1" "$2" >/dev/null; then
          printf 'Generated path is missing, unsafe, or has the wrong mode: %s\n' "$1" >&2
          exit 1
        fi
      }

      repair_log_file_mode() {
        if ! ${secureFileSystem}/bin/local-control-secure-files repair-file-mode "$1" "$2" >/dev/null; then
          printf 'Service log is missing, unsafe, or could not be made private: %s\n' "$1" >&2
          exit 1
        fi
      }

      ${lib.concatMapStringsSep "\n"
        ({ path, mode }: ''
          check_optional_generated_file \
            ${lib.escapeShellArg path} \
            ${lib.escapeShellArg mode}
        '')
        [
          {
            path = "${pkiDir}/ca.key";
            mode = "600";
          }
          {
            path = "${pkiDir}/ca.crt";
            mode = "644";
          }
          {
            path = "${pkiDir}/ca.srl";
            mode = "600";
          }
          {
            path = "${pkiDir}/server.key";
            mode = "600";
          }
          {
            path = "${pkiDir}/server.crt";
            mode = "644";
          }
          {
            path = "${pkiDir}/server.csr";
            mode = "600";
          }
          {
            path = "${pkiDir}/client.key";
            mode = "600";
          }
          {
            path = "${pkiDir}/client.crt";
            mode = "644";
          }
          {
            path = "${pkiDir}/client.csr";
            mode = "600";
          }
          {
            path = "${pkiDir}/client.pfx";
            mode = "600";
          }
        ]
      }
      ${lib.concatMapStringsSep "\n"
        (path: ''
          repair_log_file_mode \
            ${lib.escapeShellArg path} \
            600
        '')
        [
          "${logDir}/database.out.log"
          "${logDir}/database.err.log"
          "${logDir}/api.out.log"
          "${logDir}/api.err.log"
          "${logDir}/worker.out.log"
          "${logDir}/worker.err.log"
          "${logDir}/frontend.out.log"
          "${logDir}/frontend.err.log"
          "${logDir}/proxy.out.log"
          "${logDir}/proxy.err.log"
        ]
      }

      ca_certificate_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg "${pkiDir}/ca.crt"} 644)" || exit 1
      ca_key_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg "${pkiDir}/ca.key"} 600)" || exit 1
      if [ "$ca_certificate_state" = missing ] && [ "$ca_key_state" = missing ]; then
        ${secureFileSystem}/bin/local-control-secure-files exec-files \
          ${lib.escapeShellArg pkiDir} \
          ${pkgs.openssl}/bin/openssl \
          --create ca.key 600 \
          --create ca.crt 644 \
          -- \
          req -x509 -new -nodes -sha256 -days 3650 \
          -newkey rsa:3072 \
          -keyout @ca.key@ \
          -out @ca.crt@ \
          -subj '/CN=Local Service CA' \
          -addext 'basicConstraints=critical,CA:TRUE' \
          -addext 'keyUsage=critical,keyCertSign,cRLSign'
      elif [ "$ca_certificate_state" = missing ] || [ "$ca_key_state" = missing ]; then
        printf 'The local service CA is incomplete.\n' >&2
        exit 1
      fi

      ca_serial_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg "${pkiDir}/ca.srl"} 600)" || exit 1
      if [ "$ca_serial_state" = missing ]; then
        printf '01\n' | ${secureFileSystem}/bin/local-control-secure-files create-file \
          ${lib.escapeShellArg "${pkiDir}/ca.srl"} 600
      fi

      server_certificate_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg "${pkiDir}/server.crt"} 644)" || exit 1
      server_key_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg "${pkiDir}/server.key"} 600)" || exit 1
      if [ "$server_certificate_state" = missing ] && [ "$server_key_state" = missing ]; then
        ${secureFileSystem}/bin/local-control-secure-files exec-files \
          ${lib.escapeShellArg pkiDir} \
          ${pkgs.openssl}/bin/openssl \
          --create server.key 600 \
          --create server.csr 600 \
          -- \
          req -new -nodes -newkey rsa:3072 \
          -keyout @server.key@ \
          -out @server.csr@ \
          -subj '/CN=local-service'
        ${secureFileSystem}/bin/local-control-secure-files exec-files \
          ${lib.escapeShellArg pkiDir} \
          ${pkgs.openssl}/bin/openssl \
          --read ca.crt 644 \
          --read ca.key 600 \
          --update ca.srl 600 \
          --read server.csr 600 \
          --create server.crt 644 \
          -- \
          x509 -req -sha256 -days 825 \
          -in @server.csr@ \
          -CA @ca.crt@ \
          -CAkey @ca.key@ \
          -CAserial @ca.srl@ \
          -out @server.crt@ \
          -extfile ${lib.escapeShellArg serverCertificateExtensions}
      elif [ "$server_certificate_state" = missing ] || [ "$server_key_state" = missing ]; then
        printf 'The local service server identity is incomplete.\n' >&2
        exit 1
      fi

      client_bundle_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg "${pkiDir}/client.pfx"} 600)" || exit 1
      client_key_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg "${pkiDir}/client.key"} 600)" || exit 1
      client_certificate_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-file \
        ${lib.escapeShellArg "${pkiDir}/client.crt"} 644)" || exit 1
      if [ "$client_bundle_state" = missing ] \
        && [ "$client_key_state" = missing ] \
        && [ "$client_certificate_state" = missing ]; then
        ${secureFileSystem}/bin/local-control-secure-files exec-files \
          ${lib.escapeShellArg pkiDir} \
          ${pkgs.openssl}/bin/openssl \
          --create client.key 600 \
          --create client.csr 600 \
          -- \
          req -new -nodes -newkey rsa:3072 \
          -keyout @client.key@ \
          -out @client.csr@ \
          -subj '/CN=local-client'
        ${secureFileSystem}/bin/local-control-secure-files exec-files \
          ${lib.escapeShellArg pkiDir} \
          ${pkgs.openssl}/bin/openssl \
          --read ca.crt 644 \
          --read ca.key 600 \
          --update ca.srl 600 \
          --read client.csr 600 \
          --create client.crt 644 \
          -- \
          x509 -req -sha256 -days 825 \
          -in @client.csr@ \
          -CA @ca.crt@ \
          -CAkey @ca.key@ \
          -CAserial @ca.srl@ \
          -out @client.crt@ \
          -extfile ${lib.escapeShellArg clientCertificateExtensions}
        ${secureFileSystem}/bin/local-control-secure-files exec-files \
          ${lib.escapeShellArg pkiDir} \
          ${pkgs.openssl}/bin/openssl \
          --read ca.crt 644 \
          --read client.key 600 \
          --read client.crt 644 \
          --create client.pfx 600 \
          -- \
          pkcs12 -export \
          -out @client.pfx@ \
          -inkey @client.key@ \
          -in @client.crt@ \
          -certfile @ca.crt@ \
          -passout pass:
      elif [ "$client_bundle_state" = missing ] \
        || [ "$client_key_state" = missing ] \
        || [ "$client_certificate_state" = missing ]; then
        printf 'The local service client identity is incomplete.\n' >&2
        exit 1
      fi
    '';

    launchd.agents.local-control-database = {
      enable = true;
      config = {
        Label = "local.services.local-control-database";
        ProgramArguments = [ "${database}/bin/local-control-database" ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        ThrottleInterval = 10;
        Umask = 63;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/database.out.log";
        StandardErrorPath = "${logDir}/database.err.log";
      };
    };

    launchd.agents.local-control-api = {
      enable = true;
      config = {
        Label = "local.services.local-control-api";
        ProgramArguments = serviceGateArguments ++ [ "${api}/bin/local-control-api" ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        ThrottleInterval = 10;
        Umask = 63;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/api.out.log";
        StandardErrorPath = "${logDir}/api.err.log";
      };
    };

    launchd.agents.local-control-worker = {
      enable = true;
      config = {
        Label = "local.services.local-control-worker";
        ProgramArguments = serviceGateArguments ++ [ "${worker}/bin/local-control-worker" ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        ThrottleInterval = 10;
        Umask = 63;
        ProcessType = "Interactive";
        StandardOutPath = "${logDir}/worker.out.log";
        StandardErrorPath = "${logDir}/worker.err.log";
      };
    };

    launchd.agents.local-control-frontend = {
      enable = true;
      config = {
        Label = "local.services.local-control-frontend";
        ProgramArguments = serviceGateArguments ++ [ "${frontend}/bin/local-control-frontend" ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        ThrottleInterval = 10;
        Umask = 63;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/frontend.out.log";
        StandardErrorPath = "${logDir}/frontend.err.log";
      };
    };

    launchd.agents.local-control-proxy = lib.mkIf cfg.proxyEnable {
      enable = true;
      config = {
        Label = "local.services.local-control-proxy";
        ProgramArguments = serviceGateArguments ++ [ "${proxy}/bin/local-control-proxy" ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        ThrottleInterval = 10;
        Umask = 63;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/proxy.out.log";
        StandardErrorPath = "${logDir}/proxy.err.log";
      };
    };
  };
}
