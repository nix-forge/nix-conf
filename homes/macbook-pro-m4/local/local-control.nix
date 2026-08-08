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

  loadEnvironment = ''
    set -eu
    if [ ! -r ${lib.escapeShellArg environmentFile} ]; then
      printf 'Missing private service environment: %s\n' ${lib.escapeShellArg environmentFile} >&2
      exit 78
    fi
    set -a
    # shellcheck disable=SC1091
    . ${lib.escapeShellArg environmentFile}
    set +a
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
      ${loadEnvironment}
      until pg_isready -h 127.0.0.1 -p ${toString cfg.postgresPort}; do
        sleep 1
      done
      cd ${lib.escapeShellArg cfg.projectDirectory}
      uv run --locked alembic -c database/alembic.ini upgrade head
      exec uv run --locked prop-control-api
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
      ${loadEnvironment}
      until pg_isready -h 127.0.0.1 -p ${toString cfg.postgresPort}; do
        sleep 1
      done
      export OMP_NUM_THREADS=1
      export OPENBLAS_NUM_THREADS=1
      export MKL_NUM_THREADS=1
      export VECLIB_MAXIMUM_THREADS=1
      cd ${lib.escapeShellArg cfg.projectDirectory}
      exec uv run --locked prop-calculation-worker
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
      cd ${lib.escapeShellArg cfg.projectDirectory}
      if [ ! -d apps/dashboard/node_modules/.pnpm ]; then
        pnpm --dir apps/dashboard install --frozen-lockfile
      fi
      exec pnpm --dir apps/dashboard dev --host 127.0.0.1 --port ${toString cfg.frontendPort}
    '';
  };

  caddy = pkgs.writeShellApplication {
    name = "local-control-caddy";
    runtimeInputs = [ pkgs.caddy ];
    text = ''
      set -eu
      ${loadEnvironment}
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
      ${loadEnvironment}
      printf 'PostgreSQL: '
      pg_isready -h 127.0.0.1 -p ${toString cfg.postgresPort}
      printf '\nControl API: '
      curl --fail --silent http://127.0.0.1:${toString cfg.apiPort}/api/health/ready
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

    projectDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/Users/ianmh/Developer/personal/workspace-service";
      description = "Checked-out application repository used by the local services.";
    };

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
    ];

    home.packages = [
      restart
      status
    ];

    home.activation.localControlState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu
      umask 0077
      mkdir -p \
        ${lib.escapeShellArg stateDir} \
        ${lib.escapeShellArg postgresSocketDir} \
        ${lib.escapeShellArg pkiDir} \
        ${lib.escapeShellArg logDir}
      chmod 700 \
        ${lib.escapeShellArg stateDir} \
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
