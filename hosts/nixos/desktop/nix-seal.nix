{
  config,
  inputs,
  myLib,
  pkgs,
  utils,
  ...
}:
{
  nixSeal = {
    enable = true;
    administrator = "ianhollow";
    secretDirectory = "hosts/shared/secrets/desktop";
    sharedSecretDirectory = "modules/shared/secrets";
    identityFile = "/etc/ssh/ssh_host_ed25519_key";
    artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
    repositoryRoot = ../../../.;
    identities = {
      target = {
        kind = "target";
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwSeiaY3PpNjPDaFA9bDPeFaLU5HYi0PrJKEEYIt3Vs";
      };
    };
    # The root Nix daemon and the desktop profile intentionally consume the
    # same canonical token set, each delivered in a separately encrypted
    # target artifact and materialized under its own runtime root.
    inherit
      (myLib.secrets.mkTemplates {
        inventoryFiles = [
          ../../../homes/shared/local/config/secret-templates/inventory.json
          ../../shared/secret-templates/inventory.json
        ];
        repositoryRoot = ../../../.;
        scope = "ianhollow/hosts/nixos/desktop";
        secrets."nix-access-tokens" = {
          source = "secrets/ianhollow/users/ianmh/nix-access-tokens.age";
          owner = "root";
          group = "root";
          mode = "0400";
        };
        secrets."flakehub-netrc" = {
          # Both hosts reuse the same two canonical FlakeHub credentials.
          source = "secrets/ianhollow/hosts/darwin/macbook-pro-m4/flakehub-netrc.age";
          owner = "root";
          group = "root";
          mode = "0400";
        };
      })
      secrets
      templates
      ;
  };

  # Authentication is also available with a free account. Nixd owns its
  # generated netrc; this does not enable a paid cache or a subscription.
  systemd.services.flakehub-login = {
    description = "Authenticate Determinate Nix with the sealed FlakeHub token";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [
      "nix-seal-activate.service"
      "nix-daemon.service"
    ];
    after = [
      "network-online.target"
      "nix-seal-activate.service"
      "nix-daemon.service"
    ];
    restartTriggers = [ config.nixSeal.planFile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
      TimeoutStartSec = 60;
      ExecStart = utils.escapeSystemdExecArgs [
        "${inputs.determinate.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/determinate-nixd"
        "auth"
        "login"
        "token"
        "--token-file"
        config.nixSeal.secrets."flakehub-password".path
      ];
    };
  };
}
