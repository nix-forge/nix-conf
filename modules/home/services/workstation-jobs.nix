{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cfg = config.services.workstationJobs;
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
  hostNixSettings =
    if osConfig != null && (osConfig.determinateNix.enable or false) then
      osConfig.determinateNix.customSettings
    else if osConfig != null then
      osConfig.nix.settings
    else
      config.nix.settings;
  state = "${config.xdg.stateHome}/workstation-jobs";
  socket = "${state}/pueue.socket";
  pueueConfig = (pkgs.formats.yaml { }).generate "workstation-pueue.yml" {
    shared = {
      pueue_directory = "${state}/pueue";
      unix_socket_path = socket;
    };
    daemon.default_parallel_tasks = 1;
  };
  package = import ./workstation-jobs-assets/package.nix {
    inherit pkgs;
    inherit (cfg) nixPackage;
    settings = {
      stateDirectory = state;
      inherit (cfg)
        reserveMiB
        admissionHealthySeconds
        admissionPressureLimit
        growthHealthySeconds
        growthStepMiB
        compilerCores
        nixSettings
        profiles
        workstationTask
        ;
      inherit pueueConfig;
    };
  };
  # The daemon is deliberately not restarted by an update. Drain, inspect, then
  # restart explicitly; Pueue recovery pauses queued work and never replays it.
  daemon = [
    (lib.getExe' package "workstation-job")
    "serve"
  ];
  instructions = builtins.readFile ./workstation-jobs-assets/agents.md;
in
{
  key = "nix-conf/workstation-jobs/homeManager";
  options.services.workstationJobs = {
    enable = lib.mkEnableOption "durable, private host-local finite job queue";
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
      description = "Exact queue client package for scoped deployment.";
    };
    nixPackage = lib.mkOption {
      type = lib.types.package;
      default =
        # Determinate disables nix-darwin's Nix module, whose package option
        # throws when read. Our overlay supplies the repaired Determinate CLI.
        if isDarwin && osConfig != null && (osConfig.determinateNix.enable or false) then
          pkgs.nix
        else if osConfig != null && osConfig ? nix.package then
          osConfig.nix.package
        else if config.nix.package != null then
          config.nix.package
        else
          pkgs.nix;
      description = "The host-selected Nix implementation; preserve its CLI/features inside queue jobs.";
    };
    compilerCores = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = cfg.nixSettings.cores or 1;
      description = "Compiler worker default for newly queued jobs; explicit caller settings remain authoritative.";
    };
    nixSettings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.int lib.types.str);
      default = lib.filterAttrs (
        name: _:
        lib.elem name [
          "cores"
          "max-jobs"
          "eval-cores"
        ]
      ) hostNixSettings;
      description = "Host-selected Nix concurrency defaults frozen into new job recipes; explicit caller values take precedence.";
    };
    reserveMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3072;
      description = "Host headroom required in addition to the job budget on native backends.";
    };
    admissionHealthySeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1;
      description = "Healthy capacity interval before native admission.";
    };
    admissionPressureLimit = lib.mkOption {
      type = lib.types.ints.between 6 100;
      default = 50;
      description = "Full memory PSI avg10 admission ceiling; growth reopens five points below.";
    };
    growthHealthySeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Healthy demand interval before native upward growth.";
    };
    growthStepMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 256;
      description = "Largest native memory grant increase per interval.";
    };
    workstationTask = lib.mkOption {
      type = lib.types.str;
      default = "workstation-task";
      description = "Desktop executor. Use the host-owned package's immutable executable path.";
    };
    profiles = lib.mkOption {
      default.bounded = { };
      description = "Reviewed finite workload profiles. Each Pueue group has one worker; the backend owns aggregate enforcement.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }: {
            options = {
              backend = lib.mkOption {
                type = lib.types.enum [
                  "desktop"
                  "systemd"
                  "darwin"
                ];
                default = if isDarwin then "darwin" else "systemd";
                description = "Native execution/containment backend.";
              };
              executionMode = lib.mkOption {
                type = lib.types.enum [
                  "bounded"
                  "host-bounded"
                  "feedback"
                  "daemon"
                ];
                default =
                  if
                    lib.elem name [
                      "feedback"
                      "daemon"
                    ]
                  then
                    name
                  else
                    "bounded";
                description = "Desktop executor mode, independent of the queue group's name.";
              };
              allowDaemon = lib.mkOption {
                type = lib.types.bool;
                default =
                  config.backend == "darwin" || (config.backend == "desktop" && config.executionMode == "daemon");
                description = "Whether this execution path permits shared Nix daemon requests; daemon RAM is separately accounted.";
              };
              memoryMiB = lib.mkOption {
                type = lib.types.ints.positive;
                default = 2048;
                description = "Default requested memory.";
              };
              minimumMiB = lib.mkOption {
                type = lib.types.ints.positive;
                default = 256;
                description = "Smallest reviewed memory request.";
              };
              maximumMiB = lib.mkOption {
                type = lib.types.ints.positive;
                default = 4096;
                description = "Largest reviewed memory request.";
              };
              maximumSeconds = lib.mkOption {
                type = lib.types.ints.positive;
                default = 1800;
                description = "Maximum finite execution deadline, including executor admission wait.";
              };
            };
          }
        )
      );
    };
    aggregateMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = "Generic Linux worker slice hard cap; desktop uses its existing workload slice.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (
          p:
          p.allowDaemon == (p.backend == "darwin" || (p.backend == "desktop" && p.executionMode == "daemon"))
        ) (lib.attrValues cfg.profiles);
        message = "Queue daemon capability must match the native executor's actual isolation.";
      }
      {
        assertion =
          lib.versionAtLeast pkgs.pueue.version "4.0.4" && lib.versionOlder pkgs.pueue.version "5";
        message = "Pueue state/protocol upgrades require a reviewed drained migration before using major version 5.";
      }
      {
        assertion =
          cfg.profiles != { }
          && lib.all (
            p:
            p.minimumMiB <= p.memoryMiB && p.memoryMiB <= p.maximumMiB && ((p.backend == "darwin") == isDarwin)
          ) (lib.attrValues cfg.profiles);
        message = "Job profiles must fit the host OS and declared memory range.";
      }
      {
        assertion =
          !(lib.any (p: p.backend == "systemd") (lib.attrValues cfg.profiles))
          || (
            builtins.length (lib.attrNames cfg.profiles) == 1
            && lib.all (p: p.maximumMiB <= cfg.aggregateMiB) (lib.attrValues cfg.profiles)
          );
        message = "Generic Linux workers require one serial group whose largest job fits the aggregate cap.";
      }
      {
        assertion = isLinux || isDarwin;
        message = "workstationJobs requires systemd Linux or macOS launchd.";
      }
      {
        assertion = !isDarwin || builtins.length (lib.attrNames cfg.profiles) == 1;
        message = "Native macOS uses one serial group; multiple groups would overadvertise its capacity.";
      }
      {
        assertion = lib.all (
          name:
          builtins.match "[a-z][a-z0-9-]*" name != null
          && !lib.elem name [
            "default"
            "auto"
          ]
        ) (lib.attrNames cfg.profiles);
        message = "Queue group names must be safe non-default identifiers.";
      }
    ];
    home.packages = [ package ];
    home.activation.workstationJobPreview = lib.hm.dag.entryAfter [ "installPackages" ] ''
      nixProfileRemove workstation-jobs-preview
      nixProfileRemove workstation-job-context-preview
    '';
    xdg.configFile."workstation-jobs/config.json".source = package.configuration;
    xdg.configFile."workstation-jobs/pueue.yml".source = pueueConfig;
    systemd.user.slices.workstation-jobs-workload =
      lib.mkIf (isLinux && lib.any (profile: profile.backend == "systemd") (lib.attrValues cfg.profiles))
        {
          Unit.Description = "Finite queued worker aggregate";
          Slice = {
            MemoryHigh = "${toString (cfg.aggregateMiB * 3 / 4)}M";
            MemoryMax = "${toString cfg.aggregateMiB}M";
            MemorySwapMax = "0";
            CPUWeight = 25;
            IOWeight = 25;
          };
        };
    systemd.user.services.workstation-jobs = lib.mkIf isLinux {
      Unit = {
        Description = "Private durable finite job queue (inspect recovery with workstation-job doctor)";
        X-SwitchMethod = "keep-old";
      };
      Service = {
        ExecStart = (import ../../../lib/systemd/exec-args.nix) daemon;
        Type = "notify";
        NotifyAccess = "main";
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStopSec = 15;
        KillMode = "control-group";
        UMask = "0077";
        MemoryMax = "256M";
      };
      Install.WantedBy = [ "default.target" ];
    };
    launchd.agents.workstation-jobs = lib.mkIf isDarwin {
      enable = true;
      config = {
        Label = "org.nix-community.home.workstation-jobs";
        ProgramArguments = daemon;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Background";
        UMask = 63;
        StandardOutPath = "${state}/daemon.out.log";
        StandardErrorPath = "${state}/daemon.err.log";
      };
    };
    home.activation.workstationJobsDrain = lib.mkIf isDarwin (
      lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        run ${lib.getExe' package "workstation-job"} activation-check
      ''
    );
    home.activation.workstationJobsReady = lib.mkIf isDarwin (
      lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
        run ${lib.getExe' package "workstation-job"} activation-finish
      ''
    );
    home.activation.workstationJobDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe' pkgs.coreutils "mkdir"} -p -m 0700 ${lib.escapeShellArg state}
    '';
    programs.codex.context = lib.mkIf (config.programs.codex.enable or false) (
      lib.mkAfter instructions
    );
    programs.claude-code.context = lib.mkIf (config.programs.claude-code.enable or false) (
      lib.mkAfter instructions
    );
    programs.opencode.context = lib.mkIf (config.programs.opencode.enable or false) (
      lib.mkAfter instructions
    );
  };
}
