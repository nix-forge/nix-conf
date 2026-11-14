{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.dev-worktree;
  policy = pkgs.writeText "dev-worktree.json" (
    builtins.toJSON {
      inherit (cfg) developerRoot worktreeRoot stateDirectory;
      inherit (config.programs.git.maintenance) repositories;
    }
  );
  implementation = pkgs.writers.writePython3Bin "dev-worktree-internal" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./scripts/dev_worktree.py;
  command = pkgs.writeShellApplication {
    name = "dev-worktree";
    runtimeInputs = [ config.programs.git.package ];
    text = (import ../../../lib/templates/text.nix) ./scripts/dev-worktree.sh {
      lib_escapeShellArg_lib_getExe_config_programs_git_package = lib.escapeShellArg (
        lib.getExe config.programs.git.package
      );
      lib_getExe_implementation = lib.getExe implementation;
      inherit policy;
    };
  };
  instructions = ''
    Keep durable Git clones under ${cfg.developerRoot}. Open one repository or
    task checkout at a time. Use `dev-worktree new REPOSITORY TASK --base REF`
    for manually managed tasks; it prints the absolute checkout path and uses an
    independent clone when the requested base contains submodules.
    Run terminal agents with `dev-worktree run PATH -- COMMAND` to protect the
    checkout while the session runs. Manual task checkouts live under
    ${cfg.worktreeRoot}/manual. Codex and other desktop apps own their managed
    worktrees and cleanup. Never create task checkouts beside durable clones or
    place manual checkouts in an app's managed folder. For repositories with
    submodules, initialize the new clone following the repository's setup
    instructions. Preserve local changes and
    unpublished commits. Cleanup requires explicit task completion; use
    `dev-worktree doctor` to inspect first. Do not delete worktrees by age.
  ''
  + cfg.extraInstructions;
  report = pkgs.writeShellApplication {
    name = "dev-worktree-report";
    runtimeInputs = [
      pkgs.coreutils
      command
    ];
    text = (import ../../../lib/templates/text.nix) ./scripts/dev-worktree-report.sh {
      lib_escapeShellArg_cfg_stateDirectory = lib.escapeShellArg cfg.stateDirectory;
      lib_escapeShellArg_cfg_stateDirectory_report_XXXXXXXX = lib.escapeShellArg "${cfg.stateDirectory}/.report-XXXXXXXX";
      lib_escapeShellArg_cfg_stateDirectory_inventory_json = lib.escapeShellArg "${cfg.stateDirectory}/inventory.json";
    };
  };
  retireBootstrap = pkgs.writeShellApplication {
    name = "retire-dev-worktree-bootstrap";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      config.nix.package
    ];
    text = (import ../../../lib/templates/text.nix) ./scripts/retire-dev-worktree-bootstrap.sh {
      lib_escapeShellArg_cfg_stateDirectory_bootstrap_profile_json = lib.escapeShellArg "${cfg.stateDirectory}/bootstrap-profile.json";
      lib_escapeShellArg_config_home_homeDirectory_nix_profile = lib.escapeShellArg "${config.home.homeDirectory}/.nix-profile";
    };
  };
  runtimeManifest = pkgs.writeText "dev-worktree-runtime.json" (
    builtins.toJSON {
      inherit (cfg) developerRoot worktreeRoot stateDirectory;
      contexts =
        map
          (name: {
            source = config.home.file.${name}.source;
            target = config.home.file.${name}.target;
          })
          (
            lib.filter (name: builtins.match ".*(AGENTS|CLAUDE)\\.md" name != null) (
              lib.attrNames config.home.file
            )
          );
      units = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        lib.genAttrs [
          "git-maintenance@.service"
          "dev-worktree-report.service"
          "dev-worktree-report.timer"
        ] (name: config.xdg.configFile."systemd/user/${name}".source)
      );
    }
  );
  runtimeBundle = pkgs.linkFarm "dev-worktree-runtime" [
    {
      name = "command";
      path = command;
    }
    {
      name = "manifest.json";
      path = runtimeManifest;
    }
    {
      name = "retire-bootstrap";
      path = retireBootstrap;
    }
  ];
in
{
  options.programs.dev-worktree = {
    enable = lib.mkEnableOption "organized manual Git worktrees" // {
      default = true;
    };
    developerRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Developer";
      description = "Visible root for durable Git clones.";
    };
    worktreeRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Worktrees";
      description = "Task checkout root, with separate manual and app-owned children.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/dev-worktree";
      description = "Private ownership records, session leases, and inventory reports.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = command;
      description = "Packaged dev-worktree command.";
    };
    instructions = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      default = instructions;
      description = "Shared checkout policy for client-owned global instructions.";
    };
    extraInstructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional checkout instructions for local build and workload policy.";
    };
    workloadPrefix = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Command prefix for scheduled maintenance and inventory, such as workstation-task.";
    };
    runtimeBundle = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = runtimeBundle;
      description = "Scoped runtime artifacts for applying this feature without a full system activation.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.programs.git.enable;
        message = "dev-worktree requires programs.git.enable.";
      }
      {
        assertion =
          lib.all (path: lib.hasPrefix "/" path) [
            cfg.developerRoot
            cfg.worktreeRoot
            cfg.stateDirectory
          ]
          && cfg.developerRoot != cfg.worktreeRoot
          && !(lib.hasPrefix "${cfg.developerRoot}/" cfg.worktreeRoot)
          && !(lib.hasPrefix "${cfg.worktreeRoot}/" cfg.developerRoot);
        message = "Developer, Worktrees, and state paths must be absolute; the checkout roots must be separate.";
      }
    ];
    home.packages = [ command ];
    xdg.configFile."dev-worktree/config.json".source = policy;
    xdg.userDirs.extraConfig.WORKTREES = cfg.worktreeRoot;
    home.activation.createWorktreeDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      (import ../../../lib/templates/text.nix) ./scripts/prepare-worktree-directories.sh {
        lib_getExe_pkgs_coreutils_mkdir = lib.getExe' pkgs.coreutils "mkdir";
        lib_escapeShellArg_cfg_developerRoot = lib.escapeShellArg cfg.developerRoot;
        lib_escapeShellArg_cfg_worktreeRoot_manual = lib.escapeShellArg "${cfg.worktreeRoot}/manual";
        lib_escapeShellArg_cfg_worktreeRoot_codex = lib.escapeShellArg "${cfg.worktreeRoot}/codex";
        lib_escapeShellArg_cfg_worktreeRoot_claude = lib.escapeShellArg "${cfg.worktreeRoot}/claude";
        lib_escapeShellArg_cfg_stateDirectory = lib.escapeShellArg cfg.stateDirectory;
      }
    );
    # A scoped bootstrap can make the command usable before a system switch.
    # Remove only that exact profile entry once the declarative package is active.
    home.activation.retireDevWorktreeBootstrap = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${lib.getExe retireBootstrap}
    '';

    # Home Manager owns the schedule. Refresh discovery for every run, rather
    # than registering each transient checkout or starting Git's own scheduler.
    systemd.user.services."git-maintenance@" =
      lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && config.programs.git.maintenance.enable)
        {
          Service.ExecStart = lib.mkForce (
            lib.escapeShellArgs (
              cfg.workloadPrefix
              ++ [
                "${command}/bin/dev-worktree"
                "maintain"
                "--schedule=%i"
              ]
            )
          );
          Service.Slice = "background-workload.slice";
          Service.Nice = 10;
          Service.IOSchedulingClass = "idle";
          Service.Environment = [ "GIT_TERMINAL_PROMPT=0" ];
        };
    systemd.user.services.dev-worktree-report = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit.Description = "Inventory Git task checkouts without deleting work";
      Service = {
        Type = "oneshot";
        ExecStart = lib.escapeShellArgs (cfg.workloadPrefix ++ [ (lib.getExe report) ]);
        Slice = "background-workload.slice";
        UMask = "0077";
      };
    };
    systemd.user.timers.dev-worktree-report = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit.Description = "Review Git task checkout inventory weekly";
      Timer = {
        OnCalendar = "Sun *-*-* 10:00:00";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
    launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.optionalAttrs config.programs.git.maintenance.enable (
        lib.genAttrs [ "git-maintenance-hourly" "git-maintenance-daily" "git-maintenance-weekly" ] (name: {
          config.ProgramArguments = lib.mkForce [
            "${command}/bin/dev-worktree"
            "maintain"
            "--schedule=${lib.removePrefix "git-maintenance-" name}"
          ];
        })
      )
      // {
        dev-worktree-report = {
          enable = true;
          config = {
            ProgramArguments = [ (lib.getExe report) ];
            StartCalendarInterval = [
              {
                Weekday = 0;
                Hour = 10;
                Minute = 0;
              }
            ];
          };
        };
      }
    );
  };
}
