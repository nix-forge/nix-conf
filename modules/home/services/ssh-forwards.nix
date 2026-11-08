{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  cfg = config.services.sshForwards;
  active = lib.filterAttrs (_: forward: forward.enable) cfg;
  listeners = map (
    forward:
    builtins.toJSON {
      inherit (forward) direction bindAddress bindPort;
      host = if forward.direction == "remote" then forward.host else "";
    }
  ) (lib.attrValues active);
  bracket = address: if lib.hasInfix ":" address then "[${address}]" else address;
  loopback =
    address:
    lib.elem address [
      "localhost"
      "::1"
    ]
    || builtins.match "127\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}" address != null;
  arguments =
    forward:
    [ (if forward.package == null then "/usr/bin/ssh" else lib.getExe' forward.package "ssh") ]
    ++ lib.optionals (forward.sshConfigFile != null) [
      "-F"
      forward.sshConfigFile
    ]
    ++ [
      "-N"
      "-T"
      "-o"
      "BatchMode=yes"
      "-o"
      "StrictHostKeyChecking=yes"
      "-o"
      "ExitOnForwardFailure=yes"
      "-o"
      "ControlMaster=no"
      "-o"
      "ControlPath=none"
      "-o"
      "ControlPersist=no"
      "-o"
      "ForkAfterAuthentication=no"
      "-o"
      "ConnectTimeout=${toString forward.connectTimeoutSeconds}"
      "-o"
      "ConnectionAttempts=1"
      "-o"
      "ServerAliveInterval=${toString forward.serverAliveInterval}"
      "-o"
      "ServerAliveCountMax=${toString forward.serverAliveCountMax}"
      (if forward.direction == "local" then "-L" else "-R")
      "${bracket forward.bindAddress}:${toString forward.bindPort}:${bracket forward.targetAddress}:${toString forward.targetPort}"
      forward.host
    ];
  logDirectory = name: "${config.xdg.stateHome}/ssh-forwards/${name}";
in
{
  key = "nix-conf/ssh-forwards/homeManager";
  options.services.sshForwards = lib.mkOption {
    default = { };
    description = "Supervised SSH forwards with strict host-key verification. SSH liveness does not establish backend readiness; remote bind behavior also depends on the server's GatewayPorts policy.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Run this forward.";
          };
          host = lib.mkOption {
            type = lib.types.nonEmptyStr;
            description = "SSH host alias, address or user@host target. Selected SSH configurations must not add unintended forwarding rules.";
          };
          direction = lib.mkOption {
            type = lib.types.enum [
              "local"
              "remote"
            ];
            default = "local";
            description = "Local listener or reverse listener on the remote SSH server.";
          };
          bindAddress = lib.mkOption {
            type = lib.types.strMatching "[A-Za-z0-9_.:%-]+";
            default = "127.0.0.1";
            description = "Listener address. Non-loopback listeners require explicit acknowledgment.";
          };
          bindPort = lib.mkOption {
            type = lib.types.ints.between 1 65535;
            description = "Listener TCP port.";
          };
          targetAddress = lib.mkOption {
            type = lib.types.strMatching "[A-Za-z0-9_.:%-]+";
            default = "127.0.0.1";
            description = "Destination address, resolved on the other side of the forward.";
          };
          targetPort = lib.mkOption {
            type = lib.types.ints.between 1 65535;
            description = "Destination TCP port.";
          };
          acknowledgeExposure = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Explicitly permit a listener address outside loopback.";
          };
          package = lib.mkOption {
            type = lib.types.nullOr lib.types.package;
            default = if isDarwin then null else pkgs.openssh;
            defaultText = lib.literalExpression "if pkgs.stdenv.hostPlatform.isDarwin then null else pkgs.openssh";
            description = "SSH client package. Null selects Apple's native client on macOS for Keychain integration.";
          };
          sshConfigFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional absolute SSH configuration path.";
          };
          connectTimeoutSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 5;
            description = "Connection establishment deadline.";
          };
          serverAliveInterval = lib.mkOption {
            type = lib.types.ints.positive;
            default = 30;
            description = "Seconds between SSH-level keepalives.";
          };
          serverAliveCountMax = lib.mkOption {
            type = lib.types.ints.positive;
            default = 3;
            description = "Unanswered keepalives before disconnecting.";
          };
          restartSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 10;
            description = "Service-manager retry delay after disconnects.";
          };
        };
      }
    );
  };
  config = lib.mkIf (active != { }) {
    assertions = [
      {
        assertion = builtins.length listeners == builtins.length (lib.unique listeners);
        message = "SSH forwards require distinct listener addresses and ports for each local or remote destination.";
      }
      {
        assertion = lib.all (
          forward:
          !lib.hasPrefix "-" forward.host && builtins.match "[^[:space:][:cntrl:]]+" forward.host != null
        ) (lib.attrValues active);
        message = "SSH forward host must be a single destination, not an option or command.";
      }
      {
        assertion = (isLinux && config.systemd.user.enable) || (isDarwin && config.launchd.enable);
        message = "SSH forwards require a systemd user manager on Linux or launchd on macOS.";
      }
      {
        assertion = lib.all (forward: forward.package != null || isDarwin) (lib.attrValues active);
        message = "SSH forwards on Linux require an SSH package.";
      }
      {
        assertion = lib.all (forward: loopback forward.bindAddress || forward.acknowledgeExposure) (
          lib.attrValues active
        );
        message = "SSH forwards outside loopback require acknowledgeExposure = true.";
      }
      {
        assertion = lib.all (
          forward: forward.sshConfigFile == null || lib.hasPrefix "/" forward.sshConfigFile
        ) (lib.attrValues active);
        message = "SSH forward sshConfigFile must be an absolute path.";
      }
      {
        assertion = lib.all (name: builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" name != null) (
          lib.attrNames active
        );
        message = "SSH forward identifiers must contain only letters, digits, underscores or hyphens.";
      }
    ];
    systemd.user.services = lib.mkIf isLinux (
      lib.mapAttrs (_: forward: {
        Unit = {
          Description = "Supervised SSH forward";
          After = [ "network-online.target" ];
        };
        Service = {
          ExecStart = (import ../../../lib/systemd/exec-args.nix) (arguments forward);
          Restart = "always";
          RestartSec = forward.restartSeconds;
          TimeoutStopSec = 5;
          UMask = "0077";
        };
        Install.WantedBy = [ "default.target" ];
      }) active
    );
    launchd.agents = lib.mkIf isDarwin (
      lib.mapAttrs (name: forward: {
        enable = true;
        config = {
          Label = "local.services.${name}";
          ProgramArguments = arguments forward;
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = forward.restartSeconds;
          ProcessType = "Background";
          UMask = 63;
          StandardOutPath = "${logDirectory name}/out.log";
          StandardErrorPath = "${logDirectory name}/err.log";
        };
      }) active
    );
    home.activation.sshForwardLogDirectories = lib.mkIf isDarwin (
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] (
        lib.concatMapStringsSep "\n" (name: ''
          run ${lib.getExe' pkgs.coreutils "mkdir"} -p -m 0700 -- ${lib.escapeShellArg (logDirectory name)}
          run ${lib.getExe' pkgs.coreutils "chmod"} 0700 -- ${lib.escapeShellArg (logDirectory name)}
        '') (lib.attrNames active)
      )
    );
  };
}
