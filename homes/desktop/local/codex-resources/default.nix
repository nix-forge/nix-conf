{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
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
  original = pkgs.chatgpt-latest.override { codex = pkgs.codex-latest; };
  supervisor = pkgs.writers.writePython3 "codex-desktop-supervisor" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./scripts/codex_launch.py;
  forwardEnvironment = builtins.readFile ./scripts/forward-environment.sh;
  managedLaunch = pkgs.writeShellApplication {
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
  launcher = pkgs.writeShellApplication {
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
  task = pkgs.writeShellApplication {
    name = "codex-task";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = forwardEnvironment + builtins.readFile ./scripts/codex-task.sh;
  };
  monitor = pkgs.writers.writePython3 "codex-pressure-monitor" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./scripts/codex_pressure.py;
  uid = toString osConfig.users.users.ianmh.uid;
  monitorConfig = (pkgs.formats.json { }).generate "codex-pressure.json" {
    cgroup = "/sys/fs/cgroup/user.slice/user-${uid}.slice/user@${uid}.service/app.slice/app-codex.slice";
    systemPressure = "/proc/pressure/memory";
    state = "${config.xdg.stateHome}/codex-resources/pressure.json";
    history = "${config.xdg.stateHome}/codex-resources/pressure-history.jsonl";
    # Append small records; rotate rather than rewriting the history per sample.
    historyMaxBytes = 1024 * 1024;
    observedGroups = {
      nix-daemon = "/sys/fs/cgroup/system.slice/nix-daemon.service";
      queued-work = "/sys/fs/cgroup/user.slice/user-${uid}.slice/user@${uid}.service/background.slice/background-workload.slice";
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
  programs.codex.context = lib.mkAfter (builtins.readFile ./lifecycle.md);
  home.packages = [ task ];

  # A scoped rollout can temporarily expose these two commands in the user's
  # Nix profile. Retire that bridge when the normal managed packages take over,
  # so it cannot pin an older desktop package after a later system upgrade.
  home.activation.codexResourcePreview = lib.hm.dag.entryAfter [ "installPackages" ] ''
    nixProfileRemove codex-resource-preview
  '';

  home.activation.workstationSwapPreview = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    source ${./scripts/retire-swap-preview.sh} \
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
