{
  config,
  lib,

  ...
}:
{
  # The application firewall remains permissive for signed Apple services so
  # HomeKit, AirPlay, and Continuity continue to work.  Explicit blocks below
  # prevent general-purpose command-line tools from becoming LAN listeners.
  networking.applicationFirewall = {
    enable = true;
    blockAllIncoming = false;
    allowSignedApp = false;
    allowSigned = true;
    enableStealthMode = true;
  };

  system.activationScripts.postActivation.text = lib.mkAfter (
    (import ../../../../lib/templates/text.nix) ./scripts/apply-firewall-policy.sh {
      lib_escapeShellArg_config_users_users_config_system_primaryU = lib.escapeShellArg "${
        config.users.users.${config.system.primaryUser}.home
      }/Public";
    }
  );
}
