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

  # These helpers are implementation details of the MacBook control host, not
  # reusable repository library API. They live next to this profile while this
  # file remains the automatically imported Home Manager module.
  localControlLibrary = import ../support/local-control/runtime-helpers.nix { };
  databaseClusterValidator = localControlLibrary.mkDatabaseClusterValidator pkgs;
  privatePathGuard = localControlLibrary.mkPrivatePathGuard pkgs;
  secureFileSystem = localControlLibrary.mkSecureFileSystem pkgs;

  proxyConfig = pkgs.replaceVarsWith {
    name = "local-control-proxy.conf";
    src = ../support/local-control/config/proxy.Caddyfile.in;
    replacements = {
      bindAddresses =
        if cfg.bindAddress == "127.0.0.1" then cfg.bindAddress else "127.0.0.1 ${cfg.bindAddress}";
      inherit (cfg) dashboardDirectory privateHostname;
      inherit (cfg) webPort apiPort proxyPort;
    };
  };

  serverCertificateExtensions = pkgs.replaceVarsWith {
    name = "local-control-server-extensions";
    src = ../support/local-control/config/server-extensions.conf.in;
    replacements = { inherit (cfg) privateHostname bindAddress; };
  };

  clientCertificateExtensions = pkgs.replaceVarsWith {
    name = "local-control-client-extensions";
    src = ../support/local-control/config/client-extensions.conf;
    replacements = { };
  };

  localControlState = pkgs.replaceVarsWith {
    name = "local-control-initialize-state.sh";
    src = ../support/local-control/scripts/initialize-state.sh;
    replacements = {
      privatePathGuard = lib.getExe' privatePathGuard "local-control-private-path";
      secureFileSystem = lib.getExe' secureFileSystem "local-control-secure-files";
      initdb = lib.getExe' pkgs.postgresql_18 "initdb";
      openssl = lib.getExe pkgs.openssl;
      serverCertificateExtensions = lib.escapeShellArg serverCertificateExtensions;
      clientCertificateExtensions = lib.escapeShellArg clientCertificateExtensions;
    };
  };

  database = pkgs.replaceVarsWith {
    name = "local-control-database";
    src = ../support/local-control/scripts/database.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      privatePathGuard = lib.getExe' privatePathGuard "local-control-private-path";
      databaseClusterValidator = lib.getExe' databaseClusterValidator "local-control-validate-database-cluster";
      secureFileSystem = lib.getExe' secureFileSystem "local-control-secure-files";
      databaseDir = lib.escapeShellArg databaseDir;
      databaseSocketDir = lib.escapeShellArg databaseSocketDir;
      postgres = lib.getExe' pkgs.postgresql_18 "postgres";
      databasePort = toString cfg.databasePort;
    };
  };

  proxy = pkgs.replaceVarsWith {
    name = "local-control-proxy";
    src = ../support/local-control/scripts/proxy.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      secureFileSystem = lib.getExe' secureFileSystem "local-control-secure-files";
      environmentFile = lib.escapeShellArg environmentFile;
      pkiDir = lib.escapeShellArg pkiDir;
      caddy = lib.getExe pkgs.caddy;
      proxyConfig = lib.escapeShellArg proxyConfig;
    };
  };

  status = pkgs.replaceVarsWith {
    name = "local-control-status";
    src = ../support/local-control/scripts/status.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      pgIsReady = lib.getExe' pkgs.postgresql_18 "pg_isready";
      curl = lib.getExe pkgs.curl;
      lsof = lib.getExe pkgs.lsof;
      databasePort = toString cfg.databasePort;
      apiPort = toString cfg.apiPort;
      webPort = toString cfg.webPort;
      proxyPort = toString cfg.proxyPort;
    };
  };

  restart = pkgs.replaceVarsWith {
    name = "local-control-restart";
    src = ../support/local-control/scripts/restart.sh;
    dir = "bin";
    isExecutable = true;
    replacements.bash = lib.getExe pkgs.bash;
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

    privateHostname = lib.mkOption {
      type = lib.types.str;
      default = "agent-control.service.internal";
      description = "Private DNS name used for the VMware agent mTLS edge and TLS SNI.";
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
        assertion = cfg.privateHostname == "agent-control.service.internal";
        message = "services.localControl.privateHostname must remain the fixed private mTLS hostname.";
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
      export LOCAL_CONTROL_STATE_DIR=${lib.escapeShellArg stateDir}
      export LOCAL_CONTROL_DASHBOARD_DIR=${lib.escapeShellArg cfg.dashboardDirectory}
      export LOCAL_CONTROL_DATABASE_DIR=${lib.escapeShellArg databaseDir}
      export LOCAL_CONTROL_DATABASE_SOCKET_DIR=${lib.escapeShellArg databaseSocketDir}
      export LOCAL_CONTROL_PKI_DIR=${lib.escapeShellArg pkiDir}
      export LOCAL_CONTROL_LOG_DIR=${lib.escapeShellArg logDir}
      export LOCAL_CONTROL_ENVIRONMENT_FILE=${lib.escapeShellArg environmentFile}
      source ${localControlState}
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
