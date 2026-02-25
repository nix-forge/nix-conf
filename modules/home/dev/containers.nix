{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  home.packages = [
    pkgs.docker
    pkgs.docker-compose
    pkgs.docker-buildx
  ]
  ++ lib.optionals isDarwin [ pkgs.container ];

  programs.docker-cli = {
    enable = true;
  };
  home.file."${config.programs.docker-cli.configDir}/cli-plugins/docker-buildx".source =
    "${pkgs.docker-buildx}/bin/docker-buildx";
  home.file."${config.programs.docker-cli.configDir}/cli-plugins/docker-compose".source =
    "${pkgs.docker-compose}/bin/docker-compose";

  programs.lazydocker = {
    enable = true;
  };

  services.colima = {
    enable = isDarwin;

    profiles.default = {
      isService = true;
      isActive = true;

      settings = {
        runtime = "docker";
        arch = "host";

        vmType = "vz";
        mountType = "virtiofs";

        cpu = 4;
        memory = 4;

        kubernetes.enabled = false;

        portForwarder = "ssh";
        autoActivate = false;
      };
    };
  };
}
