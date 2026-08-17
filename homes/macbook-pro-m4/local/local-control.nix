{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.services.localControl;
  stateDir = cfg.stateDirectory;
  databaseDir = "${stateDir}/database";
  databaseSocketDir = "${stateDir}/database-socket";
  pkiDir = "${stateDir}/pki";
  logDir = "${stateDir}/logs";
  inherit (cfg) environmentFile;

  localControlLibrary = import ../../../lib/local-control/postgres-cluster-validator.nix { };
  databaseClusterValidator = localControlLibrary.mkDatabaseClusterValidator pkgs;
  privatePathGuard = localControlLibrary.mkPrivatePathGuard pkgs;
  secureFileSystem = localControlLibrary.mkSecureFileSystem pkgs;

  proxyConfig = pkgs.writeText "local-control-proxy.conf" (
    (import ../../../lib/local-control/proxy-config.nix { }).mkProxyConfig {
      inherit (cfg) bindAddress;
      inherit (cfg) dashboardDirectory;
      inherit (cfg) webPort apiPort proxyPort;
    }
  );

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
    runtimeInputs = [ pkgs.postgresql_18 ];
    text = ''
      set -eu
      if ! ${privatePathGuard}/bin/local-control-private-path validate-directory \
        ${lib.escapeShellArg databaseDir} \
        'Local database directory'; then
        exit 0
      fi
      if ! ${databaseClusterValidator}/bin/local-control-validate-database-cluster \
        ${lib.escapeShellArg databaseDir}; then
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

  proxy = pkgs.writeShellApplication {
    name = "local-control-proxy";
    runtimeInputs = [ pkgs.caddy ];
    text = ''
      set -eu
      environment_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-generation-file \
        ${lib.escapeShellArg environmentFile} 600)" || {
        printf 'Control-plane environment is unsafe; private proxy remains stopped.\n' >&2
        exit 0
      }
      if [ "$environment_state" = missing ]; then
        printf 'Control-plane environment is absent; private proxy remains stopped.\n' >&2
        exit 0
      fi
      exec ${secureFileSystem}/bin/local-control-secure-files exec-proxy \
        ${lib.escapeShellArg pkiDir} \
        ${lib.escapeShellArg environmentFile} \
        ${pkgs.caddy}/bin/caddy \
        run --config ${lib.escapeShellArg proxyConfig} --adapter caddyfile
    '';
  };

  status = pkgs.writeShellApplication {
    name = "local-control-status";
    runtimeInputs = [
      pkgs.curl
      pkgs.lsof
      pkgs.postgresql_18
    ];
    text = ''
      set -eu
      printf 'Database: '
      pg_isready -h 127.0.0.1 -p ${toString cfg.databasePort}
      printf '\nAPI: '
      curl --fail --silent --show-error \
        http://127.0.0.1:${toString cfg.apiPort}/api/health/ready
      printf '\nDashboard: '
      curl --fail --silent --show-error --output /dev/null \
        http://127.0.0.1:${toString cfg.webPort}/
      printf 'ready\n\nListeners:\n'
      lsof -nP \
        -iTCP:${toString cfg.webPort} \
        -iTCP:${toString cfg.apiPort} \
        -iTCP:${toString cfg.proxyPort} \
        -iTCP:${toString cfg.databasePort} \
        -sTCP:LISTEN || true
    '';
  };

  restart = pkgs.writeShellApplication {
    name = "local-control-restart";
    text = ''
      set -eu
      domain="gui/$(id -u)"
      for service in database proxy; do
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
    enable = lib.mkEnableOption "immutable local control-plane infrastructure";

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/local-control";
      description = "Canonical owner-only database, release, PKI, and log state root.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/local-control/environment";
      description = "Owner-only production application and proxy environment file.";
    };

    dashboardDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/local-control/dashboard-current";
      description = "Atomic immutable dashboard release pointer served by the loopback proxy.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "172.16.42.1";
      description = "VMware host-only address for the authenticated agent edge.";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 5173;
      description = "Loopback dashboard and browser API origin.";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8788;
      description = "Loopback immutable control API listener.";
    };

    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Authenticated VMware host-only agent edge.";
    };

    databasePort = lib.mkOption {
      type = lib.types.port;
      default = 55433;
      description = "Loopback PostgreSQL listener.";
    };

    proxyEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the immutable dashboard and authenticated agent reverse proxy.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin;
        message = "services.localControl requires the supported VMware Fusion macOS host.";
      }
      {
        assertion =
          lib.hasPrefix "/" stateDir
          && lib.hasPrefix "/" environmentFile
          && lib.hasPrefix "/" cfg.dashboardDirectory;
        message = "services.localControl state, environment, and dashboard paths must be absolute runtime strings.";
      }
      {
        assertion =
          !(lib.hasPrefix "${builtins.storeDir}/" stateDir)
          && !(lib.hasPrefix "${builtins.storeDir}/" environmentFile);
        message = "services.localControl state and secrets must remain outside the Nix store.";
      }
      {
        assertion = builtins.match "^[A-Za-z0-9/._-]+$" stateDir != null;
        message = "services.localControl.stateDirectory contains unsupported characters.";
      }
      {
        assertion = cfg.bindAddress == "172.16.42.1";
        message = "services.localControl.bindAddress must remain on the VMware host-only boundary.";
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
      restart
      status
    ];

    home.activation.localControlState = lib.hm.dag.entryAfter [ "nixSealServices" ] ''
      set -eu
      umask 0077
      ${privatePathGuard}/bin/local-control-private-path ensure-directory \
        ${lib.escapeShellArg stateDir} \
        'Local control-plane state directory'

      if [ ! -e ${lib.escapeShellArg cfg.dashboardDirectory} ] \
        && [ ! -L ${lib.escapeShellArg cfg.dashboardDirectory} ]; then
        ln -s current/dashboard ${lib.escapeShellArg cfg.dashboardDirectory}
      elif [ ! -L ${lib.escapeShellArg cfg.dashboardDirectory} ]; then
        printf 'Dashboard deployment pointer must be a symbolic link.\n' >&2
        exit 1
      fi
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

      environment_file_state="$(${secureFileSystem}/bin/local-control-secure-files inspect-generation-file \
        ${lib.escapeShellArg environmentFile} 600)" || {
        printf 'Production environment must be a safe owner-only regular file.\n' >&2
        exit 1
      }
      if [ "$environment_file_state" = missing ]; then
        printf 'Production environment is not configured; application and proxy remain stopped.\n' >&2
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
        if ! ${secureFileSystem}/bin/local-control-secure-files repair-file-mode "$1" 600 >/dev/null; then
          printf 'Service log is unsafe or could not be made private: %s\n' "$1" >&2
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
          repair_log_file_mode ${lib.escapeShellArg path}
        '')
        [
          "${logDir}/database.out.log"
          "${logDir}/database.err.log"
          "${logDir}/proxy.out.log"
          "${logDir}/proxy.err.log"
          "${logDir}/control-api.log"
          "${logDir}/control-api.error.log"
          "${logDir}/calculation-worker.log"
          "${logDir}/calculation-worker.error.log"
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
          PathState.${environmentFile} = true;
        };
        ThrottleInterval = 10;
        Umask = 63;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/database.out.log";
        StandardErrorPath = "${logDir}/database.err.log";
      };
    };

    launchd.agents.local-control-proxy = lib.mkIf cfg.proxyEnable {
      enable = true;
      config = {
        Label = "local.services.local-control-proxy";
        ProgramArguments = [ "${proxy}/bin/local-control-proxy" ];
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
