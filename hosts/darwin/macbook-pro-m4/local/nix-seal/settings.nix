{
  config,
  lib,
  myLib,
  pkgs,

  ...
}:
{
  imports = [ ../../../../shared/local/nix-seal.nix ];
  nixSeal = {
    secretDirectory = "hosts/darwin/macbook-pro-m4/local/secrets";
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./identity.pub);
    secrets.nix-token-github-com = { };
    # Only this target can receive the financial vault key.
    secrets.homelab-actual-vault-key = { };
  };

  # The activation phase materializes the private token before this runs.
  # Nixd owns its generated netrc for Nix and the native builder.
  system.activationScripts.postActivation.text = lib.mkOrder 2000 (
    myLib.writers.renderBashText { inherit pkgs; }
      {
        name = "authenticate-flakehub.sh";
        text = ''
          # shellcheck shell=bash
          /usr/local/bin/determinate-nixd auth login token \
            --token-file @lib_escapeShellArg_config_nixSeal_secrets_flakehub_password_@
        '';
      }
      {
        lib_escapeShellArg_config_nixSeal_secrets_flakehub_password_ =
          lib.escapeShellArg
            config.nixSeal.secrets."flakehub-password".path;
      }
  );
}
