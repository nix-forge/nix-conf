{
  config,
  lib,
  osConfig,
  myLib,
  pkgs,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
in
{
  home = {
    # Home Manager's backupCommand skips foreign symlinks. Preserve known
    # configuration conflicts before collision checking, including manually
    # installed store links, while leaving managed links and dry runs intact.
    activation.preserveConfigurationConflicts =
      lib.hm.dag.entryBefore [ "checkLinkTargets" ]
        (checkedShellText {
          name = "preserve-configuration-symlinks";
          text =
            myLib.templates.renderText
              {
                name = "preserve-configuration-symlinks.sh";
                text = ''
                  # shellcheck shell=bash
                  # shellcheck disable=SC2043 # Nix renders zero or more separately quoted paths.
                  for conflict in @configurationPaths@; do
                    if [[ -L $conflict && "$(readlink -- "$conflict")" != @builtins_storeDir@/*-home-manager-files/* ]]; then
                      run @osConfig_home_manager_backupCommand@ "$conflict"
                    fi
                  done
                '';
              }
              {
                configurationPaths = lib.escapeShellArgs (
                  map
                    (
                      file:
                      if lib.hasPrefix "/" file.target then file.target else "${config.home.homeDirectory}/${file.target}"
                    )
                    (
                      lib.attrValues (
                        lib.filterAttrs (
                          name: file:
                          file.enable
                          && (
                            lib.elem file.target (
                              map (target: lib.removePrefix "${config.home.homeDirectory}/" "${config.xdg.configHome}/${target}")
                                [
                                  "hypr/hyprland.lua"
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
              };
        });
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
