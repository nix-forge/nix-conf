{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  cfg = config.programs.dev-worktree;
  policy = pkgs.writeText "dev-worktree.json" (
    builtins.toJSON {
      inherit (cfg) developerRoot worktreeRoot stateDirectory;
      inherit (config.programs.git.maintenance) repositories;
    }
  );
  implementation = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).devWorktree;
  command = writeShellApplication {
    name = "dev-worktree";
    runtimeInputs = [ config.programs.git.package ];
    text =
      myLib.templates.renderText
        {
          name = "dev-worktree.sh";
          text = ''
            # shellcheck shell=bash
            export DEV_WORKTREE_GIT=@lib_escapeShellArg_lib_getExe_config_programs_git_package@
            exec @lib_getExe_implementation@ --config @policy@ "$@"
          '';
        }
        {
          lib_escapeShellArg_lib_getExe_config_programs_git_package = lib.escapeShellArg (
            lib.getExe config.programs.git.package
          );
          lib_getExe_implementation = lib.getExe implementation;
          inherit policy;
        };
  };
  reportCommand = [
    (lib.getExe command)
    "report"
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
    worktreeMount = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional Linux mount point required to prepare checkout directories.";
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
      {
        assertion =
          cfg.worktreeMount == null
          || (pkgs.stdenv.hostPlatform.isLinux && lib.hasPrefix "${cfg.worktreeMount}/" cfg.worktreeRoot);
        message = "A worktree mount requires a Linux checkout root below the mount point.";
      }
    ];
    home.packages = [ command ];
    xdg.configFile."dev-worktree/config.json".source = policy;
    # Home Manager creates XDG directories unconditionally. Mounted worktrees
    # use the guarded activation below and still export the path to applications.
    xdg.userDirs.extraConfig.WORKTREES = lib.mkIf (cfg.worktreeMount == null) cfg.worktreeRoot;
    home.sessionVariables.XDG_WORKTREES_DIR = lib.mkIf (cfg.worktreeMount != null) cfg.worktreeRoot;
    home.activation.createWorktreeDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      myLib.writers.checkedShellText { inherit pkgs; } {
        name = "prepare-worktree-directories";
        text = ''
          run ${lib.getExe' pkgs.coreutils "mkdir"} -p -- ${lib.escapeShellArg cfg.developerRoot}
          ${lib.optionalString (cfg.worktreeMount != null) ''
            if ${lib.getExe' pkgs.util-linux "mountpoint"} -q -- ${lib.escapeShellArg cfg.worktreeMount}; then
          ''}
          run ${lib.getExe' pkgs.coreutils "mkdir"} -p -- ${
            lib.escapeShellArgs (
              map (name: "${cfg.worktreeRoot}/${name}") [
                "manual"
                "codex"
                "claude"
                "opencode"
                "t3"
              ]
            )
          }
          ${lib.optionalString (cfg.worktreeMount != null) "fi"}
          run ${lib.getExe' pkgs.coreutils "mkdir"} -p -m 700 -- ${lib.escapeShellArg cfg.stateDirectory}
        '';
      }
    );
    # Home Manager owns the schedule. Refresh discovery for every run, rather
    # than registering each transient checkout or starting Git's own scheduler.
    systemd.user.services."git-maintenance@" =
      lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && config.programs.git.maintenance.enable)
        {
          Service.ExecStart = lib.mkForce (
            lib.escapeShellArgs [
              "${command}/bin/dev-worktree"
              "maintain"
              "--schedule=%i"
            ]
          );
          Service.Slice = "background.slice";
          Service.Nice = 10;
          Service.IOSchedulingClass = "idle";
          Service.Environment = [ "GIT_TERMINAL_PROMPT=0" ];
        };
    systemd.user.services.dev-worktree-report = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit.Description = "Inventory Git task checkouts without deleting work";
      Service = {
        Type = "oneshot";
        ExecStart = lib.escapeShellArgs reportCommand;
        Slice = "background.slice";
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
            ProgramArguments = reportCommand;
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
