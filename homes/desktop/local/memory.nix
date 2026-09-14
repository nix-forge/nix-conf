{
  lib,
  myLib,
  osConfig,
  pkgs,
  ...
}:
let
  budget = osConfig.systemd.user.slices.background-workload.sliceConfig;
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  waitForCgroup = pkgs.writers.writePython3 "wait-workstation-cgroup" {
    # Ruff owns line wrapping; retain the writer's other Flake8 checks.
    flakeIgnore = [ "E501" ];
  } ./wait-workstation-cgroup.py;
  runner = writeBashTemplate {
    name = "workstation-task";
    src = ./workstation-task.sh;
    dir = "bin";
    runtimeInputs = [
      pkgs.systemd
      pkgs.util-linux
      pkgs.coreutils
    ];
    replacements = {
      memoryHigh = toString budget.MemoryHigh;
      memoryMax = toString budget.MemoryMax;
      memorySwapMax = toString budget.MemorySwapMax;
      waitForCgroup = lib.escapeShellArg (toString waitForCgroup);
    };
  };
in
{
  home = {
    packages = [ runner ];

    # Home Manager's backupCommand skips foreign symlinks. Preserve known
    # configuration conflicts before collision checking, including manually
    # installed store links, while leaving managed links and dry runs intact.
    activation.preserveConfigurationConflicts = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      for relative_path in .config/hypr/hyprland.lua .config/Code/User/settings.json; do
        conflict="$HOME/$relative_path"
        if [[ -L "$conflict" && "$(readlink -- "$conflict")" != ${builtins.storeDir}/*-home-manager-files/* ]]; then
          run ${osConfig.home-manager.backupCommand} "$conflict"
        fi
      done
    '';
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
