{ config, pkgs, ... }: {
  assertions = [
    {
      assertion =
        !(config.services.displayManager.noctalia-greeter.settings.auth.allow_empty_password or false);
      message = "The graphical greeter must require a nonempty password.";
    }
    {
      assertion = config.services.greetd.settings.default_session.user == "greeter";
      message = "The graphical greeter must run under the dedicated greeter account.";
    }
  ];
  services.displayManager.noctalia-greeter = {
    enable = true;
    package = pkgs.noctalia-greeter-personal;
  };
}
