{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.services.actual;
  configDir = "${config.xdg.configHome}/actual";
  configFile = "${configDir}/config.json";
  stateDir = "${config.xdg.stateHome}/actual";
  serverFiles = "${cfg.dataDir}/server-files";
  userFiles = "${cfg.dataDir}/user-files";
  localUrl = "http://${cfg.hostname}:${toString cfg.port}";

  loopbackHosts = [
    "127.0.0.1"
    "localhost"
    "::1"
  ];

  actualConfig = cfg.extraSettings // {
    inherit (cfg) hostname port;
    inherit (cfg) dataDir;
    inherit serverFiles userFiles;
    loginMethod = "password";
    allowedLoginMethods = [ "password" ];
    trustedProxies = [
      "127.0.0.1/32"
      "::1/128"
    ];
    trustedAuthProxies = [ ];
  };

  generatedConfig = pkgs.writeText "actual-config.json" (builtins.toJSON actualConfig);

  actualOpen = pkgs.writeShellApplication {
    name = "actual-open";
    runtimeInputs = lib.optionals (!isDarwin) [ pkgs.xdg-utils ];
    text = ''
      url=${lib.escapeShellArg localUrl}

      if command -v open >/dev/null 2>&1; then
        open "$url" >/dev/null 2>&1
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1
      else
        printf '%s\n' "$url"
      fi
    '';
  };
in
{
  options.services.actual = {
    enable = lib.mkEnableOption "Actual Budget local server";

    package = lib.mkPackageOption pkgs "actual-server" { };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5006;
      description = "Local host port for the Actual Budget web UI and sync server.";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address Actual listens on. Keep this loopback-only unless a secure proxy or private tunnel is configured.";
    };

    allowNonLoopback = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow Actual to bind to a non-loopback address.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.xdg.userDirs.documents}/Actual";
      defaultText = lib.literalExpression ''"${config.xdg.userDirs.documents}/Actual"'';
      description = "Directory for Actual server state, account metadata, and budget sync files.";
    };

    openOnActivation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the local Actual URL after Home Manager activation.";
    };

    extraSettings = lib.mkOption {
      inherit ((pkgs.formats.json { })) type;
      default = { };
      description = ''
        Extra Actual server config.json settings. Do not put bank credentials or
        SimpleFIN setup tokens here; enter the one-time SimpleFIN setup token in
        the Actual UI. Actual end-to-end encryption protects budget data, but
        bank sync tokens are stored server-side and are not covered by it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin;
        message = "services.actual is currently implemented as a Darwin Home Manager launchd agent.";
      }
      {
        assertion = cfg.allowNonLoopback || builtins.elem cfg.hostname loopbackHosts;
        message = "services.actual.hostname must stay loopback-only unless services.actual.allowNonLoopback is enabled.";
      }
    ];

    home.packages = [
      cfg.package
      actualOpen
    ];

    home.activation.actualSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu

      umask 0077
      mkdir -p \
        ${lib.escapeShellArg configDir} \
        ${lib.escapeShellArg stateDir} \
        ${lib.escapeShellArg cfg.dataDir} \
        ${lib.escapeShellArg serverFiles} \
        ${lib.escapeShellArg userFiles}

      chmod 700 \
        ${lib.escapeShellArg configDir} \
        ${lib.escapeShellArg stateDir} \
        ${lib.escapeShellArg cfg.dataDir} \
        ${lib.escapeShellArg serverFiles} \
        ${lib.escapeShellArg userFiles}

      ${pkgs.coreutils}/bin/install -m 600 ${lib.escapeShellArg generatedConfig} ${lib.escapeShellArg configFile}
    '';

    home.activation.actualOpen = lib.mkIf cfg.openOnActivation (
      lib.hm.dag.entryAfter [ "actualSetup" ] ''
        ${actualOpen}/bin/actual-open >/dev/null 2>&1 || true
      ''
    );

    launchd.agents.actual = {
      enable = true;
      domain = lib.mkDefault "user";
      config = {
        Label = "dev.user.actual";
        ProgramArguments = [
          "${cfg.package}/bin/actual-server"
          "--config"
          configFile
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Background";
        StandardOutPath = "${stateDir}/launchd.out.log";
        StandardErrorPath = "${stateDir}/launchd.err.log";
        EnvironmentVariables = {
          NODE_ENV = "production";
        };
      };
    };
  };
}
