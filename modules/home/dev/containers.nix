{
  lib,
  myLib,
  pkgs,
  config,
  osConfig ? null,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  rootless = config.programs.docker-cli.rootless.enable;
  systemRootless =
    isLinux && osConfig != null && (osConfig.virtualisation.docker.rootless.enable or false);

  dockerUp = writeShellApplication {
    name = "docker-up";
    runtimeInputs = lib.optionals isDarwin [ pkgs.colima ];
    text =
      if isDarwin then
        (myLib.templates.renderText {
          name = "start-colima.sh";
          text = ''
            # shellcheck shell=bash
            exec @lib_getExe_pkgs_colima@ start
          '';
        } { lib_getExe_pkgs_colima = lib.getExe pkgs.colima; })
      else
        (myLib.templates.renderText {
          name = "start-docker-service.sh";
          text = ''
            # shellcheck shell=bash
            exec @lib_getExe_pkgs_systemd_systemctl@ --user start docker.service
          '';
        } { lib_getExe_pkgs_systemd_systemctl = lib.getExe' pkgs.systemd "systemctl"; });
  };

  dockerDown = writeShellApplication {
    name = "docker-down";
    runtimeInputs = [ pkgs.docker ] ++ lib.optionals isDarwin [ pkgs.colima ];
    text =
      if isDarwin then
        (myLib.templates.renderText {
          name = "stop-colima.sh";
          text = ''
            # shellcheck shell=bash
            exec @lib_getExe_pkgs_colima@ stop
          '';
        } { lib_getExe_pkgs_colima = lib.getExe pkgs.colima; })
      else
        (myLib.templates.renderText
          {
            name = "stop-docker-service.sh";
            text = ''
              # shellcheck shell=bash
              if @lib_getExe_pkgs_systemd_systemctl@ --user is-active --quiet docker.service; then
                mapfile -t container_ids < <(@lib_getExe_pkgs_docker@ container ls --quiet)
                if [ "''${#container_ids[@]}" -gt 0 ]; then
                  @lib_getExe_pkgs_docker@ container stop "''${container_ids[@]}"
                fi
                @lib_getExe_pkgs_systemd_systemctl@ --user stop docker.service
              else
                printf '%s\n' 'Docker is already stopped.'
              fi
            '';
          }
          {
            lib_getExe_pkgs_systemd_systemctl = lib.getExe' pkgs.systemd "systemctl";
            lib_getExe_pkgs_docker = lib.getExe pkgs.docker;
          }
        );
  };

  dockerStatus = writeShellApplication {
    name = "docker-status";
    runtimeInputs = lib.optionals isDarwin [ pkgs.colima ];
    text =
      if isDarwin then
        (myLib.templates.renderText {
          name = "show-colima-status.sh";
          text = ''
            # shellcheck shell=bash
            exec @lib_getExe_pkgs_colima@ status
          '';
        } { lib_getExe_pkgs_colima = lib.getExe pkgs.colima; })
      else
        ''
          ${lib.getExe' pkgs.systemd "systemctl"} --user status docker.service || true
        '';
  };

  dockerClean = writeShellApplication {
    name = "docker-clean";
    runtimeInputs = [ pkgs.docker ];
    text = myLib.templates.renderText {
      name = "docker-clean.sh";
      text = ''
        # shellcheck shell=bash
        case "''${1-}" in
        "")
          @lib_getExe_pkgs_docker@ system df
          printf '%s\n' 'Pass --images to prune unused images and build cache, or --volumes to include unused volumes.'
          ;;
        --images)
          exec @lib_getExe_pkgs_docker@ system prune --all --force
          ;;
        --volumes)
          exec @lib_getExe_pkgs_docker@ system prune --all --volumes --force
          ;;
        *)
          printf '%s\n' 'usage: docker-clean [--images|--volumes]' >&2
          exit 64
          ;;
        esac
      '';
    } { lib_getExe_pkgs_docker = lib.getExe pkgs.docker; };
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
