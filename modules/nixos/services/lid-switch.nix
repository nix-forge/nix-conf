{
  # despite being under logind, this has nothing to do with login
  # it's about power management
  services.logind = {
    settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "lock";
      HandlePowerKey = "suspend-then-hibernate";
      HibernateDelaySec = 3600;
    };
  };
}
