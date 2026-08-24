{ config, lib, ... }: {
  nixSeal = {
    enable = true;
    administrator = "ianhollow";
    identityFile = "/etc/ssh/ssh_host_ed25519_key";
    artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
    repositoryRoot = ../../../.;
    identities = {
      target = {
        kind = "target";
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
      };
    };
    secrets."nix-access-tokens" = {
      owner = "root";
      group = "wheel";
      mode = "0400";
    };
    # This is a netrc fragment containing the FlakeHub machine entries. It is
    # encrypted in the repository and materialized only in nix-seal's runtime
    # storage, never in the Nix store.
    secrets."flakehub-netrc" = {
      owner = "root";
      group = "wheel";
      mode = "0400";
    };
  };

  # The nix-seal service phase creates the private netrc before this runs.
  # Hand the token to Nixd through stdin so its supported login mechanism
  # maintains the generated netrc used by both Nix and the native builder.
  system.activationScripts.postActivation.text = lib.mkOrder 2000 ''
    flakehubNetrc=${config.nixSeal.secrets."flakehub-netrc".path}
    flakehubToken=$(
      /usr/bin/awk '$1 == "machine" && $2 == "flakehub.com" && $5 == "password" { print $6; exit }' \
        "$flakehubNetrc"
    )
    test -n "$flakehubToken"
    printf '%s\n' "$flakehubToken" | /usr/local/bin/determinate-nixd auth login token --token-file /dev/stdin
    unset flakehubToken
  '';
}
