{ config, lib, ... }:
{
  security.polkit = {
    enable = true;

    # optionally, log all actions that can be recorded by polkit
    # if polkit debugging has been enabled
    debug = lib.mkDefault true;
    extraConfig = lib.mkIf config.security.polkit.debug ''
      /* Log authorization checks. */
      polkit.addRule(function(action, subject) {
        polkit.log("user " +  subject.user + " is attempting action " + action.id + " from PID " + subject.pid);
      });
    '';
  };
}
