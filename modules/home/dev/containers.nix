{
  lib,
  pkgs,
  config,
  osConfig ? null,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  rootless = config.programs.docker-cli.rootless.enable;
  systemRootless =
    isLinux && osConfig != null && (osConfig.virtualisation.docker.rootless.enable or false);

  dockerUp = pkgs.writeShellApplication {
    name = "docker-up";
    runtimeInputs = lib.optionals isDarwin [ pkgs.colima ];
    text =
      if isDarwin then
        ''
          exec ${lib.getExe pkgs.colima} start
        ''
      else
        ''
          exec ${lib.getExe' pkgs.systemd "systemctl"} --user start docker.service
        '';
  };

  dockerDown = pkgs.writeShellApplication {
    name = "docker-down";
    runtimeInputs = [ pkgs.docker ] ++ lib.optionals isDarwin [ pkgs.colima ];
    text =
      if isDarwin then
        ''
          exec ${lib.getExe pkgs.colima} stop
        ''
      else
        ''
          if ${lib.getExe' pkgs.systemd "systemctl"} --user is-active --quiet docker.service; then
            mapfile -t container_ids < <(${lib.getExe pkgs.docker} container ls --quiet)
            if [ "''${#container_ids[@]}" -gt 0 ]; then
              ${lib.getExe pkgs.docker} container stop "''${container_ids[@]}"
            fi
            ${lib.getExe' pkgs.systemd "systemctl"} --user stop docker.service
          else
            printf '%s\n' 'Docker is already stopped.'
          fi
        '';
  };

  dockerStatus = pkgs.writeShellApplication {
    name = "docker-status";
    runtimeInputs = lib.optionals isDarwin [ pkgs.colima ];
    text =
      if isDarwin then
        ''
          exec ${lib.getExe pkgs.colima} status
        ''
      else
        ''
          ${lib.getExe' pkgs.systemd "systemctl"} --user status docker.service || true
        '';
  };

  dockerClean = pkgs.writeShellApplication {
    name = "docker-clean";
    runtimeInputs = [ pkgs.docker ];
    text = ''
      case "''${1-}" in
        "")
          ${lib.getExe pkgs.docker} system df
          printf '%s\n' 'Pass --images to prune unused images and build cache, or --volumes to include unused volumes.'
          ;;
        --images)
          exec ${lib.getExe pkgs.docker} system prune --all --force
          ;;
        --volumes)
          exec ${lib.getExe pkgs.docker} system prune --all --volumes --force
          ;;
        *)
          printf '%s\n' 'usage: docker-clean [--images|--volumes]' >&2
          exit 64
          ;;
      esac
    '';
  };
in
{
  options.programs.docker-cli.rootless.enable = lib.mkOption {
    type = lib.types.bool;
    default = systemRootless;
    defaultText = lib.literalExpression "osConfig.virtualisation.docker.rootless.enable or false";
    description = ''
      Configure the rootless Docker context and user-service helpers. Enabled
      automatically for an attached NixOS rootless daemon. Standalone Linux
      profiles can opt in after provisioning their own docker.service.
    '';
  };

  config = {
    assertions = [
      {
        assertion = !rootless || (isLinux && config.home.uid != null);
        message = "programs.docker-cli.rootless.enable requires Linux and home.uid.";
      }
      {
        assertion = !rootless || osConfig == null || systemRootless;
        message = "programs.docker-cli.rootless.enable requires virtualisation.docker.rootless.enable on an attached NixOS host.";
      }
    ];

    home = {
      packages = [
        pkgs.docker
        pkgs.docker-compose
        pkgs.docker-buildx
        pkgs.cosign
        pkgs.dive
        pkgs.hadolint
        pkgs.skopeo
        pkgs.syft
        pkgs.trivy
        dockerClean
      ]
      ++ lib.optionals (isDarwin || rootless) [
        dockerUp
        dockerDown
        dockerStatus
      ];

      file."${config.programs.docker-cli.configDir}/cli-plugins/docker-buildx".source =
        "${pkgs.docker-buildx}/bin/docker-buildx";
      file."${config.programs.docker-cli.configDir}/cli-plugins/docker-compose".source =
        "${pkgs.docker-compose}/bin/docker-compose";

    };

    programs.docker-cli = {
      enable = true;
      # Use the XDG location now rather than carrying the pre-26.05 legacy
      # default of ~/.docker. Colima's runtime state is kept separately.
      configDir = "${config.xdg.configHome}/docker";
      settings = {
        detachKeys = "ctrl-@";
        psFormat = "table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}";
        imagesFormat = "table {{.Repository}}\\t{{.Tag}}\\t{{.ID}}\\t{{.Size}}";
      }
      // lib.optionalAttrs rootless { currentContext = "rootless"; };
      contexts = lib.optionalAttrs rootless {
        rootless = {
          Metadata.Description = "Rootless Docker in this user session";
          Endpoints.docker = {
            Host = "unix:///run/user/${toString config.home.uid}/docker.sock";
            SkipTLSVerify = false;
          };
        };
      };
    };

    programs.lazydocker.enable = true;
  };
}
