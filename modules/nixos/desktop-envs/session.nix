{ config, lib, ... }: {
  # GTK file searches synchronously activate LocalSearch, whose unit requires
  # XDG_SESSION_CLASS=user. Fill missing login metadata in UWSM's session
  # environment, for every compositor, without overriding a class supplied by
  # PAM or applying graphical-session metadata to SSH and system services.
  # UWSM exports this variable to activation environments and cleans it up on
  # logout. Native desktop session managers retain their own environment setup.
  environment.etc = lib.mkIf config.programs.uwsm.enable {
    "xdg/uwsm/env.d/10-session-class".text = builtins.readFile ./scripts/set-session-class.sh;
  };
}
