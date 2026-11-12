{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  image = "/var/lib/actual-volume/actual.luks";
  mount = "/srv/actual";
  mapper = "actual-vault";
  actualOrigin = "https://actual.${config.homelab.operations.lanHttps.domain}";
  identityOrigin = "https://identity.${config.homelab.operations.lanHttps.domain}";
  backupDestinations = config.hardware.storage.encryptedRoot.backup.destinations;
  actualCli = inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.actual-cli;
  actualCommand = pkgs.writeShellApplication {
    name = "actual";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.python3
    ];
    text = (import ../../../../../lib/templates/text.nix) ./actual/scripts/cli.sh {
      lib_escapeShellArg_actualOrigin = lib.escapeShellArg actualOrigin;
      lib_escapeShellArg_identityOrigin = lib.escapeShellArg identityOrigin;
      scripts_actual_cli_login_py = ./actual/scripts/actual_cli_login.py;
      inherit actualCli;
    };
  };
  actualVault = pkgs.writeShellApplication {
    name = "actual-vault";
    runtimeInputs = with pkgs; [
      cryptsetup
      coreutils
      e2fsprogs
      systemd
      util-linux
    ];
    text = builtins.readFile ./actual/scripts/actual-vault.sh;
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
          ExecStart = "${pkgs.python3}/bin/python3 ${./actual/scripts/actual_identity.py} http://127.0.0.1:${toString config.services.keycloak.settings.http-port} ${lib.escapeShellArg actualOrigin}";
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
        script = builtins.readFile ./actual/scripts/actual-vault-open.sh;
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
        script = (import ../../../../../lib/templates/text.nix) ./actual/scripts/prepare-runtime.sh {
          pkgs_util_linux = pkgs.util-linux;
          inherit mount;
          inherit mapper;
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
        postStart = (import ../../../../../lib/templates/text.nix) ./actual/scripts/wait-for-health.sh {
          curl = lib.escapeShellArg (lib.getExe pkgs.curl);
          readinessArgs = lib.escapeShellArgs [
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
            "http://127.0.0.1:${toString config.services.actual.settings.port}/health"
          ];
        };
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
        preStart = lib.mkBefore (
          (import ../../../../../lib/templates/text.nix) ./actual/scripts/require-vault-mount.sh {
            pkgs_util_linux = pkgs.util-linux;
            inherit mount;
            inherit mapper;
          }
        );
      };
    }
    (lib.mapAttrs' (
      name: _:
      lib.nameValuePair "desktop-backup-cold-${name}" {
        preStart = lib.optionalString (config.hardware.storage.encryptedRoot.backup.coldUnits == [ ]) (
          (import ../../../../../lib/templates/text.nix) ./actual/scripts/require-locked-backup.sh {
            inherit image;
            pkgs_cryptsetup = pkgs.cryptsetup;
            inherit mapper;
          }
        );
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
