{ pkgs, config, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  home.packages = [
    pkgs.docker
    pkgs.docker-compose
    pkgs.docker-buildx
  ];

  programs.docker-cli.enable = true;

  home.file."${config.programs.docker-cli.configDir}/cli-plugins/docker-buildx".source =
    "${pkgs.docker-buildx}/bin/docker-buildx";
  home.file."${config.programs.docker-cli.configDir}/cli-plugins/docker-compose".source =
    "${pkgs.docker-compose}/bin/docker-compose";

  programs.lazydocker.enable = true;

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
        memory = 8;
        disk = 100;

        mounts = [
          {
            location = "${config.xdg.userDirs.documents}/Karakeep";
            writable = true;
          }
        ];

        kubernetes.enabled = false;

        portForwarder = "ssh";
      };
    };
  };
}
