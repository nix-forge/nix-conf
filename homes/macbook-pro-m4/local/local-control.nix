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
  envFile = "${stateDir}/control.env";
  logDir = "${stateDir}/logs";

  caddyConfig = pkgs.writeText "local-control.Caddyfile" ''
    {
      admin off
      auto_https off
      servers {
        protocols h1 h2
        # The agent deliberately uses the fixed host-only IP address instead
        # of a DNS name. This is safe here because this listener has one mTLS
        # protected site only; there is no second virtual host to front.
        strict_sni_host insecure_off
      }
    }

    # This listener exists solely on VMware Fusion's host-only adapter. The
    # client certificate is required before a request can reach the API.
    https://${cfg.hostOnlyAddress}:${toString cfg.agentPort} {
      bind ${cfg.hostOnlyAddress}
      tls ${pkiDir}/server.crt ${pkiDir}/server.key {
        client_auth {
          trust_pool file ${pkiDir}/ca.crt
          mode require_and_verify
        }
      }
      reverse_proxy 127.0.0.1:${toString cfg.apiPort}
    }
  '';

  controlEnvironment = ''
    set -eu
    # The file is created by the Nix activation step with mode 0600. It holds
    # the database password and browser API token. Remote-client credentials
    # remain on the client machine.
    # shellcheck disable=SC1091
    . ${lib.escapeShellArg envFile}
    export LOCAL_CONTROL_DATABASE_URL LOCAL_CONTROL_AUTH_TOKEN
    # The coordinated deployer records an immutable release ID in this shared
    # environment file.  Both supervised processes must inherit it, otherwise
    # they fall back to separate editable-source fingerprints.
    export LOCAL_CONTROL_RELEASE_ID="''${LOCAL_CONTROL_RELEASE_ID:-}"
    export LOCAL_CONTROL_DB_ADMIN LOCAL_CONTROL_DB_USER LOCAL_CONTROL_DB_NAME
    export PGPASSWORD="$LOCAL_CONTROL_DB_PASSWORD"
  '';

  postgres = pkgs.writeShellApplication {
    name = "local-control-postgres";
    runtimeInputs = [ pkgs.postgresql_16 ];
    text = ''
      set -eu
      ${controlEnvironment}
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
      pkgs.postgresql_16
      pkgs.uv
    ];
    text = ''
      set -eu
      ${controlEnvironment}
      export UV_PROJECT_ENVIRONMENT=${lib.escapeShellArg "${stateDir}/venv"}
      export UV_CACHE_DIR=${lib.escapeShellArg "${stateDir}/uv-cache"}
      export LOCAL_CONTROL_BIND_HOST=127.0.0.1
      export LOCAL_CONTROL_PORT=${toString cfg.apiPort}
      export LOCAL_CONTROL_CORS_ORIGINS=http://127.0.0.1:${toString cfg.frontendPort}
      export LOCAL_CONTROL_ALLOW_ACTIONS=${lib.boolToString cfg.allowActions}
      export LOCAL_CONTROL_WORKER_COUNT=${toString cfg.workerCount}

      for identifier in "$LOCAL_CONTROL_DB_ADMIN" "$LOCAL_CONTROL_DB_USER" "$LOCAL_CONTROL_DB_NAME"; do
        case "$identifier" in
          "" | [0-9]* | *[!a-z0-9_]*)
            printf 'Invalid local database identifier.\n' >&2
            exit 64
            ;;
        esac
      done

      until pg_isready -h 127.0.0.1 -p ${toString cfg.postgresPort} -U "$LOCAL_CONTROL_DB_ADMIN"; do
        sleep 1
      done

      if ! psql -h 127.0.0.1 -p ${toString cfg.postgresPort} -U "$LOCAL_CONTROL_DB_ADMIN" -d postgres \
        -v app_user="$LOCAL_CONTROL_DB_USER" -tA <<'SQL' | grep -qx 1
      SELECT 1 FROM pg_roles WHERE rolname = :'app_user';
      SQL
      then
        # The password is generated as lowercase hexadecimal, so it is safe
        # to pass as a quoted psql variable.
        psql -h 127.0.0.1 -p ${toString cfg.postgresPort} -U "$LOCAL_CONTROL_DB_ADMIN" -d postgres \
          -v app_user="$LOCAL_CONTROL_DB_USER" \
          -v app_password="$LOCAL_CONTROL_APP_PASSWORD" <<'SQL'
        CREATE ROLE :"app_user"
          LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
          PASSWORD :'app_password';
      SQL
      fi

      if ! psql -h 127.0.0.1 -p ${toString cfg.postgresPort} -U "$LOCAL_CONTROL_DB_ADMIN" -d postgres \
        -v database_name="$LOCAL_CONTROL_DB_NAME" -tA <<'SQL' | grep -qx 1
      SELECT 1 FROM pg_database WHERE datname = :'database_name';
      SQL
      then
        createdb -h 127.0.0.1 -p ${toString cfg.postgresPort} \
          -U "$LOCAL_CONTROL_DB_ADMIN" \
          -O "$LOCAL_CONTROL_DB_USER" \
          "$LOCAL_CONTROL_DB_NAME"
      fi
      psql -h 127.0.0.1 -p ${toString cfg.postgresPort} -U "$LOCAL_CONTROL_DB_ADMIN" -d postgres \
        -v database_name="$LOCAL_CONTROL_DB_NAME" \
        -v app_user="$LOCAL_CONTROL_DB_USER" <<'SQL'
      ALTER DATABASE :"database_name" OWNER TO :"app_user";
      SQL
      psql -h 127.0.0.1 -p ${toString cfg.postgresPort} -U "$LOCAL_CONTROL_DB_ADMIN" \
        -d "$LOCAL_CONTROL_DB_NAME" \
        -v app_user="$LOCAL_CONTROL_DB_USER" <<'SQL'
      ALTER SCHEMA public OWNER TO :"app_user";
      SQL

      cd ${lib.escapeShellArg cfg.projectDirectory}
      uv run --locked alembic -c alembic.ini upgrade head
      exec uv run --locked local-control-api
    '';
  };

  worker = pkgs.writeShellApplication {
    name = "local-control-worker";
    runtimeInputs = [ pkgs.uv ];
    text = ''
      set -eu
      ${controlEnvironment}
      export UV_PROJECT_ENVIRONMENT=${lib.escapeShellArg "${stateDir}/venv"}
      export UV_CACHE_DIR=${lib.escapeShellArg "${stateDir}/uv-cache"}
      export LOCAL_CONTROL_RESERVED_CORES=${toString cfg.reservedCores}
      export OMP_NUM_THREADS=1
      export OPENBLAS_NUM_THREADS=1
      export MKL_NUM_THREADS=1
      export VECLIB_MAXIMUM_THREADS=1
      cd ${lib.escapeShellArg cfg.projectDirectory}
      exec uv run --locked local-control-worker
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
      if [ ! -d frontend/node_modules/.pnpm ]; then
        pnpm --dir frontend install --frozen-lockfile
      fi
      export VITE_CONTROL_API_URL=
      exec pnpm --dir frontend dev --host 127.0.0.1
    '';
  };

  caddy = pkgs.writeShellApplication {
    name = "local-control-caddy";
    runtimeInputs = [ pkgs.caddy ];
    text = ''
      set -eu
      exec caddy run --config ${lib.escapeShellArg caddyConfig} --adapter caddyfile
    '';
  };

  status = pkgs.writeShellApplication {
    name = "local-control-status";
    runtimeInputs = [
      pkgs.curl
      pkgs.postgresql_16
      pkgs.lsof
    ];
    text = ''
      set -eu
      ${controlEnvironment}
      export PGPASSWORD="$LOCAL_CONTROL_DB_PASSWORD"
      printf 'PostgreSQL: '
      pg_isready -h 127.0.0.1 -p ${toString cfg.postgresPort} -U "$LOCAL_CONTROL_DB_ADMIN"
      printf '\nControl API: '
      curl --fail --silent http://127.0.0.1:${toString cfg.apiPort}/v1/health
      printf '\n\nListeners:\n'
      lsof -nP -iTCP:${toString cfg.frontendPort} -iTCP:${toString cfg.apiPort} -iTCP:${toString cfg.agentPort} -sTCP:LISTEN || true
      printf '\nVM agent endpoint: https://${cfg.hostOnlyAddress}:${toString cfg.agentPort}\n'
    '';
  };

  restart = pkgs.writeShellApplication {
    name = "local-control-restart";
    text = ''
      set -eu
      domain="gui/$(id -u)"
      # The release fence fingerprints editable source at process startup.
      # Restart both readers together so neither can process jobs from a
      # different checkout state.
      launchctl kickstart -k "$domain/dev.ianmh.local-control-worker"
      launchctl kickstart -k "$domain/dev.ianmh.local-control-api"
    '';
  };
in
{
  options.services.localControl = {
    enable = lib.mkEnableOption "private local application stack";

    allowActions = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Permit the API to queue operator-reviewed external actions.";
    };

    projectDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/Users/ianmh/Developer/personal/local-control";
      description = "Checked-out application repository used by the local services.";
    };

    hostOnlyAddress = lib.mkOption {
      type = lib.types.str;
      default = "172.16.42.1";
      description = "Mac address on the VMware Fusion host-only network.";
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
      default = 5432;
    };

    reservedCores = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
      description = "Logical CPU cores reserved from background calculations.";
    };

    workerCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Worker processes available for independent dashboard calculations.";
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

      if [ ! -s ${lib.escapeShellArg envFile} ]; then
        db_password="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
        app_password="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
        api_token="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
        {
          printf 'LOCAL_CONTROL_DB_PASSWORD=%s\n' "$db_password"
          printf 'LOCAL_CONTROL_APP_PASSWORD=%s\n' "$app_password"
          printf 'LOCAL_CONTROL_DB_ADMIN=local_control\n'
          printf 'LOCAL_CONTROL_DB_USER=local_control_app\n'
          printf 'LOCAL_CONTROL_DB_NAME=local_control\n'
          printf 'LOCAL_CONTROL_DATABASE_URL=postgresql://local_control_app:%s@127.0.0.1:${toString cfg.postgresPort}/local_control\n' "$app_password"
          printf 'LOCAL_CONTROL_AUTH_TOKEN=%s\n' "$api_token"
        } > ${lib.escapeShellArg envFile}
        chmod 600 ${lib.escapeShellArg envFile}
      fi

      # The first version of this local setup used the initdb bootstrap role
      # directly. Upgrade existing state in place to the least-privileged app
      # role without rotating the browser token or database data.
      if ! ${pkgs.gnugrep}/bin/grep -q '^LOCAL_CONTROL_APP_PASSWORD=' ${lib.escapeShellArg envFile}; then
        app_password="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
        {
          printf 'LOCAL_CONTROL_APP_PASSWORD=%s\n' "$app_password"
          printf 'LOCAL_CONTROL_DATABASE_URL=postgresql://local_control_app:%s@127.0.0.1:${toString cfg.postgresPort}/local_control\n' "$app_password"
        } >> ${lib.escapeShellArg envFile}
      fi

      if [ ! -f ${lib.escapeShellArg "${postgresDir}/PG_VERSION"} ]; then
        password_file="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${stateDir}/postgres-password.XXXXXX"})"
        . ${lib.escapeShellArg envFile}
        printf '%s' "$LOCAL_CONTROL_DB_PASSWORD" > "$password_file"
              chmod 600 "$password_file"
              ${pkgs.postgresql_16}/bin/initdb \
                -D ${lib.escapeShellArg postgresDir} \
                -U "$LOCAL_CONTROL_DB_ADMIN" \
          --pwfile="$password_file" \
          --auth-local=scram-sha-256 \
          --auth-host=scram-sha-256
        ${pkgs.coreutils}/bin/rm -f "$password_file"
            fi

            if [ ! -f ${lib.escapeShellArg "${pkiDir}/ca.crt"} ]; then
              ${pkgs.openssl}/bin/openssl req -x509 -new -nodes -sha256 -days 3650 \
                -newkey rsa:3072 \
                -keyout ${lib.escapeShellArg "${pkiDir}/ca.key"} \
                -out ${lib.escapeShellArg "${pkiDir}/ca.crt"} \
                -subj '/CN=Local Control CA' \
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

      if [ ! -f ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.pfx"} ]; then
        certificate_extensions="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${stateDir}/agent-ext.XXXXXX"})"
        cat > "$certificate_extensions" <<'EOF'
      basicConstraints=critical,CA:FALSE
      keyUsage=critical,digitalSignature,keyEncipherment
      extendedKeyUsage=clientAuth
      EOF
              ${pkgs.openssl}/bin/openssl req -new -nodes -newkey rsa:3072 \
                -keyout ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.key"} \
                -out ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.csr"} \
                -subj '/CN=dev-vm-agent'
              ${pkgs.openssl}/bin/openssl x509 -req -sha256 -days 825 \
                -in ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.csr"} \
                -CA ${lib.escapeShellArg "${pkiDir}/ca.crt"} \
                -CAkey ${lib.escapeShellArg "${pkiDir}/ca.key"} \
                -CAcreateserial \
                -out ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.crt"} \
                -extfile "$certificate_extensions"
              ${pkgs.openssl}/bin/openssl pkcs12 -export \
                -out ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.pfx"} \
                -inkey ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.key"} \
                -in ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.crt"} \
          -certfile ${lib.escapeShellArg "${pkiDir}/ca.crt"} \
          -passout pass:
        ${pkgs.coreutils}/bin/rm -f "$certificate_extensions"
              chmod 600 ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.key"} ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.pfx"}
              chmod 644 ${lib.escapeShellArg "${pkiDir}/dev-vm-agent.crt"}
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
        # Operator-started calculations should receive the CPU share needed to
        # complete promptly. Keep the API and frontend backgrounded; only the
        # dedicated compute worker is interactive.
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

    launchd.agents.local-control-caddy = {
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
