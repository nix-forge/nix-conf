{
  config,
  lib,
  osConfig,
  myLib,
  pkgs,
  ...
}:
let
  retirePreview = pkgs.writeText "retire-swap-preview.sh" (
    myLib.writers.checkedShellText { inherit pkgs; } {
      name = "retire-swap-preview";
      text = ''
        # shellcheck shell=bash
        # Sourced by activation, which supplies newGenPath and nixProfileRemove.
        (
          set -euo pipefail
          swap_preview_unit=''${1:?unit path required}
          swap_preview_relative=''${2:?generation-relative unit path required}
          if [[ -z ''${newGenPath:-} || $swap_preview_relative == /* ||
            $swap_preview_relative == ../* || $swap_preview_relative == */../* ]]; then
            exit 0
          fi
          swap_preview_expected="$newGenPath/home-files/$swap_preview_relative"
          # Keep the root if managed-link installation failed or an unexpected link won.
          if [[ -L $swap_preview_unit && -f $swap_preview_unit &&
            -f $swap_preview_expected &&
            $(readlink -f -- "$swap_preview_unit") == "$(readlink -f -- "$swap_preview_expected")" ]]; then
            nixProfileRemove workstation-swap-preview
          fi
        )
      '';
    }
  );
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  # A 14 GiB trial reclaimed active UI pages during tool/cache bursts despite
  # host headroom. The 16 GiB threshold leaves slack below the unchanged hard
  # ceiling. Shared containment limits do not reserve physical RAM.
  sampleSeconds = 30;
  accuracySeconds = 5;
  budget = {
    MemoryHigh = 16 * 1024 * 1024 * 1024;
    MemoryMax = 18 * 1024 * 1024 * 1024;
    # Cold application state exhausted smaller swap allowances while the host
    # still had free encrypted disk swap. Keep the RAM ceiling unchanged and
    # allow bounded spill instead of making those pages compete with builds.
    MemorySwapMax = 22 * 1024 * 1024 * 1024;
  };
  original = pkgs.chatgpt;
  supervisor =
    lib.getExe
      (import ../../../../flake/runtime-packages.nix { inherit pkgs; }).codexDesktopSupervisor;
  forwardEnvironment = (''
    # shellcheck shell=bash
    # Copy values inside systemd-run; only variable names appear in its argv.
    forward_environment() {
      local entry name
      environment=()
      while IFS= read -r -d ''' entry; do
        name=''${entry%%=*}
        # systemd accepts ordinary environment names, not exported Bash functions.
        if [[ ! $name =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]]; then continue; fi
        case "$name" in
        INVOCATION_ID | JOURNAL_STREAM | SYSTEMD_EXEC_PID | NOTIFY_SOCKET | WATCHDOG_* | LISTEN_* | RUNTIME_DIRECTORY | STATE_DIRECTORY | CACHE_DIRECTORY | LOGS_DIRECTORY | CONFIGURATION_DIRECTORY | CREDENTIALS_DIRECTORY | CODEX_LAUNCH_UNIT) continue ;;
        esac
        environment+=("--setenv=$name")
      done < <(env -0)
    }
  '');
  managedLaunch = writeShellApplication {
    name = "codex-desktop-launch";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = forwardEnvironment + ''
      forward_environment
      token=$(cat /proc/sys/kernel/random/uuid)
      # Preserve the chatgpt.desktop identity used by desktop portals.
      token=''${token//-/}
      unit="app-chatgpt@$token.service"
      exec systemd-run --user --wait --pipe --collect --quiet \
        --service-type=exec --expand-environment=no --slice=app-codex.slice \
        --unit="$unit" --property=OOMPolicy=continue --property="UMask=$(umask)" \
        --property=PartOf=graphical-session.target --property=After=graphical-session.target \
        --property="RuntimeDirectory=codex-launch-$token" \
        --property=RuntimeDirectoryMode=0700 \
        --property="ExecStopPost=${supervisor} cleanup" \
        --property=TimeoutStopSec=15s --working-directory="$PWD" \
        "''${environment[@]}" --setenv="CODEX_LAUNCH_UNIT=$unit" \
        -- ${supervisor} "$@"
    '';
  };
  launcher = writeShellApplication {
    name = "chatgpt";
    text = ''
      exec ${lib.getExe managedLaunch} ${lib.getExe original} "$@"
    '';
  };
  desktop = pkgs.symlinkJoin {
    name = "codex-desktop-budgeted";
    paths = [ original ];
    postBuild = ''
      rm "$out/bin/chatgpt" "$out/share/applications/chatgpt.desktop"
      ln -s ${lib.getExe launcher} "$out/bin/chatgpt"
      substitute ${original}/share/applications/chatgpt.desktop \
        "$out/share/applications/chatgpt.desktop" \
        --replace-fail 'Exec=chatgpt ' "Exec=$out/bin/chatgpt "
    '';
    meta.mainProgram = "chatgpt";
  };
  task = writeShellApplication {
    name = "codex-task";
    runtimeInputs = [ pkgs.systemd ];
    text =
      myLib.templates.renderText
        {
          name = "codex-task.sh";
          text = ''
            # shellcheck shell=bash
            exec @runtime@ "$@"
          '';
        }
        {
          runtime =
            lib.getExe' (import ../../../../flake/runtime-packages.nix { inherit pkgs; }).codexDesktopSupervisor
              "codex-task";
        };
  };
  monitor =
    lib.getExe
      (import ../../../../flake/runtime-packages.nix { inherit pkgs; }).codexPressureMonitor;
  uid = toString osConfig.users.users.${config.home.username}.uid;
  userManagerCgroup = "/sys/fs/cgroup/user.slice/user-${uid}.slice/user@${uid}.service";
  monitorConfig = (pkgs.formats.json { }).generate "codex-pressure.json" {
    cgroup = "${userManagerCgroup}/app.slice/app-codex.slice";
    systemPressure = "/proc/pressure/memory";
    state = "${config.xdg.stateHome}/codex-resources/pressure.json";
    database = "${config.xdg.stateHome}/codex-resources/pressure-history.sqlite";
    # Leave the two legacy 1 MiB JSONL files intact. New database plus rollback
    # journal stay within 30 MiB, for a combined maximum of 32 MiB.
    historyTotalBytes = 30 * 1024 * 1024;
    rawSeconds = 24 * 60 * 60;
    summarySeconds = 14 * 24 * 60 * 60;
    observedGroups = {
      zen = "${userManagerCgroup}/app.slice/app-zen.slice";
      t3-agents = "${userManagerCgroup}/app.slice/app-t3code.slice";
      t3-server = "${userManagerCgroup}/app.slice/t3code.service";
      virtual-machines = "/sys/fs/cgroup/machine.slice";
      desktop-portal = "${userManagerCgroup}/session.slice/xdg-desktop-portal.service";
      nix-daemon = "/sys/fs/cgroup/system.slice/nix-daemon.service";
    };
    observedPatterns.t3-desktop = {
      root = "${userManagerCgroup}/app.slice/app-graphical.slice";
      pattern = "app-Hyprland-*t3code*.scope";
    };
    notify = lib.getExe pkgs.libnotify;
    policy = {
      memoryHigh = budget.MemoryHigh;
      memoryMax = budget.MemoryMax;
      swapMax = budget.MemorySwapMax;
      pressurePercent = 5;
      nearLimitRatio = 0.9;
      samples = 2;
      cooldownSeconds = 15 * 60;
      maxSampleGapSeconds = 3 * (sampleSeconds + accuracySeconds);
    };
  };
in
{
  programs.chatgpt.package = desktop;
  home.packages = [
    task
    (writeShellApplication {
      name = "workstation-memory-history";
      text = ''
        exec ${monitor} ${monitorConfig} --history "$@"
      '';
    })
  ];

  # A scoped rollout can temporarily expose these two commands in the user's
  # Nix profile. Retire that bridge when the normal managed packages take over,
  # so it cannot pin an older desktop package after a later system upgrade.
  home.activation.codexResourcePreview = lib.hm.dag.entryAfter [ "installPackages" ] ''
    nixProfileRemove codex-resource-preview
  '';

  home.activation.workstationSwapPreview = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    source ${retirePreview} \
      ${lib.escapeShellArg "${config.xdg.configHome}/systemd/user/app-codex.slice"} \
      ${lib.escapeShellArg "${lib.removePrefix "${config.home.homeDirectory}/" config.xdg.configHome}/systemd/user/app-codex.slice"}
  '';

  systemd.user.slices.app-codex = {
    Unit.Description = "Shared Codex desktop and task resources";
    Slice = budget;
  };
  systemd.user.services.codex-pressure = {
    Unit = {
      Description = "Observe sustained desktop and Codex memory pressure";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${monitor} ${monitorConfig}";
      Slice = "background.slice";
      TimeoutStartSec = 20;
      UMask = "0077";
      NoNewPrivileges = true;
      MemoryMax = "96M";
      CPUWeight = 10;
      IOWeight = 10;
    };
  };
  systemd.user.timers.codex-pressure = {
    Unit = {
      Description = "Sample memory pressure without interrupting desktop work";
      PartOf = [ "graphical-session.target" ];
    };
    Timer = {
      OnActiveSec = "${toString sampleSeconds}s";
      OnUnitInactiveSec = "${toString sampleSeconds}s";
      AccuracySec = "${toString accuracySeconds}s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # An isolated build target: validates the launcher and generated policy without
  # rebuilding the desktop or restarting an active conversation.
  xdg.dataFile."codex-resources/policy".source = pkgs.linkFarm "codex-resource-policy" [
    {
      name = "launch";
      path = managedLaunch;
    }
    {
      name = "supervisor";
      path = supervisor;
    }
    {
      name = "task";
      path = task;
    }
    {
      name = "monitor";
      path = monitor;
    }
    {
      name = "monitor.json";
      path = monitorConfig;
    }
    {
      name = "slice";
      path = config.xdg.configFile."systemd/user/app-codex.slice".source;
    }
    {
      name = "service";
      path = config.xdg.configFile."systemd/user/codex-pressure.service".source;
    }
    {
      name = "timer";
      path = config.xdg.configFile."systemd/user/codex-pressure.timer".source;
    }
  ];
}
