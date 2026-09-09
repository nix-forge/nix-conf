{
  config,
  lib,
  myLib,
  ...
}:
{
  nixSeal = {
    enable = true;
    administrator = "ianhollow";
    secretDirectory = "hosts/shared/secrets/macbook-pro-m4";
    sharedSecretDirectory = "modules/shared/secrets";
    identityFile = "/etc/ssh/ssh_host_ed25519_key";
    artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
    repositoryRoot = ../../../.;
    identities = {
      target = {
        kind = "target";
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
      };
    };
    inherit
      (myLib.secrets.mkTemplates {
        inventoryFiles = [ ../../shared/secret-templates/inventory.json ];
        repositoryRoot = ../../../.;
        scope = "ianhollow/hosts/darwin/macbook-pro-m4";
        secrets."nix-access-tokens" = {
          owner = "root";
          group = "wheel";
          mode = "0400";
        };
        # Public machine entries reuse one shared encrypted login and password.
        # The complete netrc is rendered only in private runtime storage.
        secrets."flakehub-netrc" = {
          owner = "root";
          group = "wheel";
          mode = "0400";
        };
      })
      secrets
      templates
      ;
  };

  # The activation phase materializes the private token before this runs.
  # Nixd owns its generated netrc for Nix and the native builder.
  system.activationScripts.postActivation.text = lib.mkOrder 2000 ''
    /usr/local/bin/determinate-nixd auth login token \
      --token-file ${lib.escapeShellArg config.nixSeal.secrets."flakehub-password".path}
  '';
}
