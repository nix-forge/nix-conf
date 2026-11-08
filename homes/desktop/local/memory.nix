{
  config,
  lib,
  myLib,
  osConfig,
  pkgs,
  ...
}:
let
  budget = osConfig.systemd.user.slices.background-workload.sliceConfig;
  policy = osConfig.workstation.workloads;
  codexSkillPath = "${config.xdg.configHome}/codex/skills/reverse-engineer-anything";
  # The selected Codex module retains the slash after removing homeDirectory.
  codexSkillTarget = lib.removePrefix config.home.homeDirectory codexSkillPath;
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  waitForCgroup = pkgs.writers.writePython3 "wait-workstation-cgroup" {
    # Ruff owns line wrapping; retain the writer's other Flake8 checks.
    flakeIgnore = [ "E501" ];
  } ./wait_workstation_cgroup.py;
  taskEvents = pkgs.writers.writePython3 "workstation-task-events" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./workstation_task_events.py;
  memoryController = pkgs.writers.writePython3 "workstation-memory" {
    libraries = [ pkgs.python3Packages.dbus-next ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../../../modules/home/services/workstation-jobs-assets/workstation_memory.py;
  runner = writeBashTemplate {
    name = "workstation-task";
    src = ./workstation-task.sh;
    dir = "bin";
    runtimeInputs = [
      pkgs.systemd
      pkgs.util-linux
      pkgs.coreutils
      pkgs.gawk
    ];
    replacements = {
      # Leave room for the separate daemon budget and its configured reserve.
      # A smaller admission snapshot still allowed a global OOM during builds.
      # This is conservative admission, not a physical memory reservation.
      memoryController = lib.escapeShellArg (toString memoryController);
      admissionSeconds = toString policy.admission.maximumSeconds;
      admissionHealthySeconds = toString policy.admission.healthySeconds;
      admissionPressureLimit = toString policy.admission.pressureLimit;
      growthHealthySeconds = toString policy.admission.growthHealthySeconds;
      growthStepMiB = toString policy.admission.growthStepMiB;
      bulkMemoryAvailable = toString ((policy.daemon.memoryMiB + policy.daemon.reserveMiB) * 1024 * 1024);
      boundedReserve = toString (policy.bounded.reserveMiB * 1024 * 1024);
      boundedMemoryMinGiB = toString (policy.bounded.minimumMiB / 1024);
      boundedMemoryMaxGiB = toString (policy.bounded.maximumMiB / 1024);
      boundedHighPercent = toString policy.bounded.highPercent;
      boundedRuntimeSeconds = toString policy.bounded.maximumSeconds;
      feedbackReserve = toString (policy.feedback.reserveMiB * 1024 * 1024);
      feedbackRuntimeSeconds = toString policy.feedback.maximumSeconds;
      bubblewrap = lib.escapeShellArg (lib.getExe pkgs.bubblewrap);
      taskEvents = lib.escapeShellArg (toString taskEvents);
      bulkLock = lib.escapeShellArg "/run/workstation-workloads/bulk.lock";
      # Measured feedback jobs stalled near 1 GiB despite a 2 GiB hard budget.
      # Allow their working set to grow while retaining a reclaim margin.
      feedbackMemoryHigh = toString (policy.feedback.highMiB * 1024 * 1024);
      feedbackMemoryMax = toString (policy.feedback.memoryMiB * 1024 * 1024);
      feedbackSwapMax = toString (policy.feedback.swapMiB * 1024 * 1024);
      memoryHigh = toString budget.MemoryHigh;
      memoryMax = toString budget.MemoryMax;
      memorySwapMax = toString budget.MemorySwapMax;
      waitForCgroup = lib.escapeShellArg (toString waitForCgroup);
    };
  };
in
{
  # Expose the exact package without searching the complete application list.
  lib.workstationTask = runner;

  home = {
    packages = [ runner ];

    activation.workstationTaskPreview = lib.hm.dag.entryAfter [ "installPackages" ] ''
      nixProfileRemove workstation-policy-preview
      nixProfileRemove workstation-task-preview
      nixProfileRemove workstation-task
    '';

    # Home Manager's backupCommand skips foreign symlinks. Preserve known
    # configuration conflicts before collision checking, including manually
    # installed store links, while leaving managed links and dry runs intact.
    activation.preserveConfigurationConflicts = lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
      (import ../../../lib/templates/text.nix) ./scripts/preserve-configuration-symlinks.sh {
        configurationPaths = lib.escapeShellArgs (
          map
            (
              file:
              if file.target == codexSkillTarget then
                codexSkillPath
              else if lib.hasPrefix "/" file.target then
                file.target
              else
                "${config.home.homeDirectory}/${file.target}"
            )
            (
              lib.attrValues (
                lib.filterAttrs (
                  name: file:
                  file.enable
                  && (
                    file.target == codexSkillTarget
                    || lib.elem file.target (
                      map (target: lib.removePrefix "${config.home.homeDirectory}/" "${config.xdg.configHome}/${target}")
                        [
                          "hypr/hyprland.lua"
                          "codex/skills/reverse-engineer-anything"
                          "opencode/opencode.json"
                          # Retire foreign preview links only after preserving
                          # them, before Home Manager installs the managed units.
                          "systemd/user/app-codex.slice"
                          "systemd/user/codex-pressure.service"
                        ]
                    )
                    || lib.hasSuffix "/User/settings.json" name
                    ||
                      builtins.match ".*/User/profiles/[^/]+/settings[.]json" (builtins.unsafeDiscardStringContext name)
                      != null
                  )
                ) config.home.file
              )
            )
        );
        builtins_storeDir = builtins.storeDir;
        osConfig_home_manager_backupCommand = osConfig.home-manager.backupCommand;
      }
    );
  };

  xdg.configFile = {
    # The shell is essential to the session, not an ordinary application.
    "systemd/user/noctalia.service.d/60-memory.conf".text = ''
      [Service]
      Slice=session.slice
      MemoryLow=256M
    '';

    # Hyprlock normally inherits hypridle's cgroup. Put idle/lock handling in
    # the protected session slice, including when no lock window exists yet.
    "systemd/user/hypridle.service.d/60-memory.conf".text = ''
      [Service]
      Slice=session.slice
      MemoryLow=128M
    '';
  };
}
