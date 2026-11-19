{
  config,
  inputs,
  lib,
  myLib,
  pkgs,
  utils,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  image = "/var/lib/actual-volume/actual.luks";
  mount = "/srv/actual";
  mapper = "actual-vault";
  actualOrigin = "https://actual.${config.homelab.operations.lanHttps.domain}";
  identityOrigin = "https://identity.${config.homelab.operations.lanHttps.domain}";
  backupDestinations = config.hardware.storage.encryptedRoot.backup.destinations;
  actualCli = inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.actual-cli;
  inherit ((import ../../../../../flake/runtime-packages.nix { inherit pkgs; })) actualProtocols;
  actualCommand = writeShellApplication {
    name = "actual";
    runtimeInputs = [ pkgs.util-linux ];
    text =
      myLib.templates.renderText
        {
          name = "cli.sh";
          text = ''
            # shellcheck shell=bash
            exec @actualCommand@ @arguments@ "$@"
          '';
        }
        {
          actualCommand = lib.escapeShellArg (lib.getExe' actualProtocols "actual-command");
          arguments = lib.escapeShellArgs [
            actualOrigin
            identityOrigin
            (lib.getExe' actualCli "actual-cli")
          ];
        };
  };
  actualVault = writeShellApplication {
    name = "actual-vault";
    runtimeInputs = with pkgs; [
      cryptsetup
      systemd
      util-linux
    ];
    text = myLib.templates.renderText {
      name = "actual-vault.sh";
      text = ''
        # shellcheck shell=bash
        exec @actualVault@ "$@"
      '';
    } { actualVault = lib.escapeShellArg (lib.getExe' actualProtocols "actual-vault"); };
  };
in
{
  # The desktop TPM opens the vault without an interactive prompt. The original
  # key slot remains available for attended recovery.
  services.actual = {
    enable = true;
    user = "actual";
    group = "actual";
    settings = {
      dataDir = "${mount}/server";
      loginMethod = "openid";
      allowedLoginMethods = [ "openid" ];
      enforceOpenId = true;
      userCreationMode = "manual";
      token_expiration = 86400;
      openId = {
        discoveryURL = "${identityOrigin}/realms/actual";
        client_id = "actual";
        client_secret._secret = "/run/credentials/actual.service/oidc-secret";
        server_hostname = actualOrigin;
      };
    };
  };
  users.users.actual = {
    isSystemUser = true;
    group = "actual";
  };
  users.groups.actual = { };

  nixSeal.secrets = {
    homelab-actual-username = {
      phase = "services";
      owner = "ianmh";
      group = "users";
    };
    homelab-actual-password = {
      phase = "services";
      owner = "ianmh";
      group = "users";
    };
    homelab-actual-oidc-secret = {
      phase = "services";
      owner = "actual";
      group = "actual";
    };
  };

  environment.systemPackages = [
    actualVault
    actualCommand
    actualCli
  ];
  system.build.actualCli = actualCli;
  system.build.actualVault = actualVault;
  fileSystems.${mount} = {
    device = "/dev/mapper/${mapper}";
    fsType = "ext4";
    options = [
      # Keep this mount outside local-fs.target; Actual starts it on demand.
      "x-systemd.wanted-by=actual.service"
      "x-systemd.requires=actual-vault-open.service"
      "nodev"
      "nosuid"
      "noexec"
    ];
  };

  systemd.services = lib.mkMerge [
    {
      homelab-actual-identity = {
        requires = [
          "keycloak.service"
          "nix-seal-activate.service"
        ];
        after = [
          "keycloak.service"
          "nix-seal-activate.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${
            lib.getExe' (import ../../../../../flake/runtime-packages.nix { inherit pkgs; }).actualProtocols
              "actual-identity"
          } http://127.0.0.1:${toString config.services.keycloak.settings.http-port} ${lib.escapeShellArg actualOrigin}";
          LoadCredential = [
            "admin:${config.nixSeal.secrets.homelab-identity-admin-env.path}"
            "username:${config.nixSeal.secrets.homelab-actual-username.path}"
            "password:${config.nixSeal.secrets.homelab-actual-password.path}"
            "client-secret:${config.nixSeal.secrets.homelab-actual-oidc-secret.path}"
          ];
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          IPAddressDeny = "any";
          IPAddressAllow = "127.0.0.0/8";
        };
      };
      actual-vault-open = {
        description = "Open Actual storage using the desktop TPM";
        path = with pkgs; [ cryptsetup ];
        script = checkedShellText {
          name = "actual-vault-open";
          text = (''
            # shellcheck shell=bash
            set -euo pipefail
            image=/var/lib/actual-volume/actual.luks
            mapper=actual-vault

            if cryptsetup status "$mapper" >/dev/null 2>&1; then
              exit 0
            fi

            # A missing or replaced image must fail closed. Initial provisioning is attended.
            if [ ! -f "$image" ] || [ -L "$image" ]; then
              echo "Actual vault image is missing or invalid: $image" >&2
              exit 1
            fi

            # The enrolled TPM2 token unlocks locally. Headless mode forbids a boot prompt.
            exec "$SYSTEMD_CRYPTSETUP" attach "$mapper" "$image" none \
              tpm2-device=auto,headless=yes,tries=1
          '');
        };
        environment.SYSTEMD_CRYPTSETUP = "${pkgs.systemd}/lib/systemd/systemd-cryptsetup";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "90s";
        };
      };
      actual-vault-ready = {
        requires = [
          "srv-actual.mount"
          "nix-seal-activate.service"
        ];
        after = [
          "srv-actual.mount"
          "nix-seal-activate.service"
        ];
        script = checkedShellText {
          name = "prepare-actual-runtime";
          text =
            myLib.templates.renderText
              {
                name = "prepare-runtime.sh";
                text = ''
                  # shellcheck shell=bash
                  test "$(@pkgs_util_linux@/bin/findmnt -rn -o SOURCE --target @mount@)" = /dev/mapper/@mapper@
                  chmod 0711 @mount@
                  install -d -m 0700 -o actual -g actual @mount@/server
                  install -d -m 0700 -o ianmh -g users @mount@/cli /run/nix-seal/actual-cli
                  install -m 0400 -o ianmh -g users "$CREDENTIALS_DIRECTORY/username" /run/nix-seal/actual-cli/username
                  install -m 0400 -o ianmh -g users "$CREDENTIALS_DIRECTORY/password" /run/nix-seal/actual-cli/password
                '';
              }
              {
                pkgs_util_linux = pkgs.util-linux;
                inherit mount;
                inherit mapper;
              };
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          LoadCredential = [
            "username:${config.nixSeal.secrets.homelab-actual-username.path}"
            "password:${config.nixSeal.secrets.homelab-actual-password.path}"
          ];
        };
      };
      actual = {
        # systemctl start must wait until the HTTP server can answer requests.
        serviceConfig.ExecStartPost = utils.escapeSystemdExecArgs [
          (lib.getExe pkgs.curl)
          "--silent"
          "--show-error"
          "--fail"
          "--retry"
          "30"
          "--retry-delay"
          "1"
          "--retry-connrefused"
          "--retry-max-time"
          "60"
          "--max-time"
          "2"
          "--output"
          "/dev/null"
          "http://127.0.0.1:${toString config.services.actual.settings.port}/health"
        ];
        serviceConfig.RestartSec = "5s";
        serviceConfig.LoadCredential = [
          "oidc-secret:${config.nixSeal.secrets.homelab-actual-oidc-secret.path}"
        ];
        # The image is provisioned separately with an attended recovery key.
        # Let the timer activate Actual only after that image exists.
        wantedBy = lib.mkForce [ ];
        requires = [
          "actual-vault-ready.service"
          "homelab-actual-identity.service"
          "srv-actual.mount"
        ];
        after = [
          "actual-vault-ready.service"
          "homelab-actual-identity.service"
          "srv-actual.mount"
        ];
        bindsTo = [ "srv-actual.mount" ];
        unitConfig = {
          RequiresMountsFor = mount;
          AssertPathIsMountPoint = mount;
        };
        preStart = lib.mkBefore (checkedShellText {
          name = "require-vault-mount";
          text =
            myLib.templates.renderText
              {
                name = "require-vault-mount.sh";
                text = ''
                  # shellcheck shell=bash
                  test "$(@pkgs_util_linux@/bin/findmnt -rn -o SOURCE --target @mount@)" = /dev/mapper/@mapper@
                  test -d @mount@/server
                '';
              }
              {
                pkgs_util_linux = pkgs.util-linux;
                inherit mount;
                inherit mapper;
              };
        });
      };
    }
    (lib.mapAttrs' (
      name: _:
      lib.nameValuePair "desktop-backup-cold-${name}" {
        preStart =
          lib.optionalString (config.hardware.storage.encryptedRoot.backup.coldUnits == [ ])
            (checkedShellText {
              name = "require-locked-backup";
              text =
                myLib.templates.renderText
                  {
                    name = "require-locked-backup.sh";
                    text = ''
                      # shellcheck shell=bash
                      test -f @image@
                      if @pkgs_cryptsetup@/bin/cryptsetup status @mapper@ >/dev/null 2>&1; then
                        echo "Lock the Actual volume before its cold backup" >&2
                        exit 1
                      fi
                    '';
                  }
                  {
                    inherit image;
                    pkgs_cryptsetup = pkgs.cryptsetup;
                    inherit mapper;
                  };
            });
      }
    ) backupDestinations)
  ];

  systemd.timers.actual = {
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionPathExists = image;
    timerConfig = {
      OnBootSec = "30s";
      OnCalendar = "minutely";
      Unit = "actual.service";
    };
  };

  assertions = [
    {
      assertion = config.services.actual.settings.dataDir == "${mount}/server";
      message = "Actual server state must remain inside the unlocked encrypted volume.";
    }
  ];

  # Native capture guards activation and unmounts the filesystem before copying
  # its ciphertext image. Legacy rescue-mode capture still requires locking it.
  hardware.storage.encryptedRoot.backup = {
    coldPaths = lib.mkAfter [ image ];
    coldUnits = lib.mkAfter [
      "actual.timer"
      "actual.service"
      "actual-vault-ready.service"
      "srv-actual.mount"
    ];
    coldUnmounts = [ mount ];
    exclude = lib.mkAfter [
      image
      mount
    ];
  };
}
