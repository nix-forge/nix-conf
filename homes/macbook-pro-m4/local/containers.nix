{ config, ... }: {
  services.colima.enable = false;
  assertions = [
    {
      assertion = !config.services.colima.enable && !config.programs.docker-cli.enable;
      message = "This home profile uses native Nix packages, without Colima or Docker.";
    }
  ];
}
