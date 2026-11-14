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
        ((import ../../../lib/templates/text.nix) ./scripts/start-colima.sh {
          lib_getExe_pkgs_colima = lib.getExe pkgs.colima;
        })
      else
        ((import ../../../lib/templates/text.nix) ./scripts/start-docker-service.sh {
          lib_getExe_pkgs_systemd_systemctl = lib.getExe' pkgs.systemd "systemctl";
        });
  };

  dockerDown = pkgs.writeShellApplication {
    name = "docker-down";
    runtimeInputs = [ pkgs.docker ] ++ lib.optionals isDarwin [ pkgs.colima ];
    text =
      if isDarwin then
        ((import ../../../lib/templates/text.nix) ./scripts/stop-colima.sh {
          lib_getExe_pkgs_colima = lib.getExe pkgs.colima;
        })
      else
        ((import ../../../lib/templates/text.nix) ./scripts/stop-docker-service.sh {
          lib_getExe_pkgs_systemd_systemctl = lib.getExe' pkgs.systemd "systemctl";
          lib_getExe_pkgs_docker = lib.getExe pkgs.docker;
        });
  };

  dockerStatus = pkgs.writeShellApplication {
    name = "docker-status";
    runtimeInputs = lib.optionals isDarwin [ pkgs.colima ];
    text =
      if isDarwin then
        ((import ../../../lib/templates/text.nix) ./scripts/show-colima-status.sh {
          lib_getExe_pkgs_colima = lib.getExe pkgs.colima;
        })
      else
        ''
          ${lib.getExe' pkgs.systemd "systemctl"} --user status docker.service || true
        '';
  };

  dockerClean = pkgs.writeShellApplication {
    name = "docker-clean";
    runtimeInputs = [ pkgs.docker ];
    text = (import ../../../lib/templates/text.nix) ./scripts/docker-clean.sh {
      lib_getExe_pkgs_docker = lib.getExe pkgs.docker;
    };
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
