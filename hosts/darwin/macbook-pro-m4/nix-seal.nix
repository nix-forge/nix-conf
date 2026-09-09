{ config, lib, ... }: {
  imports = [ ../../shared/nix-seal.nix ];
  nixSeal = {
    secretDirectory = "hosts/darwin/macbook-pro-m4/local/secrets";
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./local/nix-seal/identity.pub);
    secrets.nix-token-github-com = { };
  };

  # The activation phase materializes the private token before this runs.
  # Nixd owns its generated netrc for Nix and the native builder.
  system.activationScripts.postActivation.text = lib.mkOrder 2000 ''
    /usr/local/bin/determinate-nixd auth login token \
      --token-file ${lib.escapeShellArg config.nixSeal.secrets."flakehub-password".path}
  '';
}
