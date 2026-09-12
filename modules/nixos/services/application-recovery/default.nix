{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.applicationRecovery;
  commandOption =
    description:
    lib.mkOption {
      type = lib.types.lines;
      inherit description;
    };
  phases = [
    "export"
    "backup"
    "recover"
    "restore"
    "check"
  ];
  policyFor =
    name: application:
    pkgs.writeText "recovery-${name}.json" (
      builtins.toJSON (
        {
          inherit (application) units timeoutSeconds;
          stateDirectory = "/var/lib/application-recovery/${name}";
        }
        // lib.genAttrs phases (phase: [
          (lib.getExe (
            pkgs.writeShellApplication {
              name = "recovery-${name}-${phase}";
              runtimeInputs = application.packages;
              text = application.${phase};
            }
          ))
        ])
      )
    );
  serviceFor = name: application: action: {
    description = "Application ${name} ${action}";
    path = [ pkgs.systemd ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.python3} ${./runner.py} ${policyFor name application} ${action}";
      StateDirectory = "application-recovery/${name}";
      StateDirectoryMode = "0700";
      UMask = "0077";
      PrivateTmp = true;
      # Enough time for every bounded hook plus writer shutdown and restart.
      TimeoutStartSec = application.timeoutSeconds * (7 + 4 * builtins.length application.units);
      TimeoutStopSec = application.timeoutSeconds * (2 + builtins.length application.units);
      # SIGTERM reaches Python first, whose finally block resumes writers.
      KillMode = "mixed";
    }
    // lib.optionalAttrs (action == "drill") {
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "/var/lib/application-recovery/${name}" ];
      CapabilityBoundingSet = [ ];
      NoNewPrivileges = true;
      PrivateDevices = true;
      RestrictSUIDSGID = true;
    };
  };
in
{
  options.services.applicationRecovery.applications = lib.mkOption {
    default = { };
    description = "Application-owned backup exports and isolated recovery drills. Declaring a recipe does not provision backup storage or prove live recovery.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          units = lib.mkOption {
            type = lib.types.listOf (lib.types.strMatching "[a-zA-Z0-9@_.:-]+\\.service");
            default = [ ];
            description = "Writer services stopped during export and backup; only originally active units restart, including on failure. Include socket/timer activation guards in the owning application's configuration.";
          };
          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Tools used by the declared lifecycle hooks.";
          };
          timeoutSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 3600;
            description = "Maximum time for each lifecycle hook and writer control operation.";
          };
          export = commandOption "Export consistent application data into RECOVERY_EXPORT, with declared writers stopped.";
          backup = commandOption "Persist RECOVERY_EXPORT to a provisioned repository. Return failure unless backup completes. Use a stable application tag because scratch paths change.";
          recover = commandOption "Fetch one identified application backup into RECOVERY_EXPORT, failing if absent or ambiguous.";
          restore = commandOption "Restore the recovered export into RECOVERY_TARGET only. Never target live state; the directory is disposable.";
          check = commandOption "Verify application semantics in RECOVERY_TARGET and fail on mismatch. Successful execution records an isolated drill, never a live recovery claim.";
        };
      }
    );
  };
  config = lib.mkIf (cfg.applications != { }) {
    assertions = lib.mapAttrsToList (name: _: {
      assertion = builtins.match "[a-z][a-z0-9-]*" name != null;
      message = "Application recovery names must be lowercase service-safe identifiers.";
    }) cfg.applications;
    systemd.services = lib.listToAttrs (
      lib.concatLists (
        lib.mapAttrsToList (
          name: application:
          map
            (
              action:
              lib.nameValuePair "application-recovery-${name}-${action}" (serviceFor name application action)
            )
            [
              "backup"
              "drill"
            ]
        ) cfg.applications
      )
    );
  };
}
