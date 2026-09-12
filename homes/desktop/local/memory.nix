{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  budget = osConfig.systemd.user.slices.background-workload.sliceConfig;
  waitForCgroup = pkgs.writeScript "wait-workstation-cgroup" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./wait-workstation-cgroup.py}
  '';
  runner = pkgs.writeShellApplication {
    name = "workstation-task";
    runtimeInputs = [
      pkgs.systemd
      pkgs.util-linux
      pkgs.coreutils
    ];
    text =
      builtins.replaceStrings
        [ "@memoryHigh@" "@memoryMax@" "@memorySwapMax@" "@waitForCgroup@" ]
        [
          (toString budget.MemoryHigh)
          (toString budget.MemoryMax)
          (toString budget.MemorySwapMax)
          (lib.escapeShellArg (toString waitForCgroup))
        ]
        (builtins.readFile ./workstation-task.sh);
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
