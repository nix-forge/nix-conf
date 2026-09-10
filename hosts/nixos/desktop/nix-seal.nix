{
  config,
  lib,
  inputs,
  pkgs,
  utils,
  ...
}:
{
  imports = [ ../../shared/nix-seal.nix ];
  nixSeal = {
    secretDirectory = "hosts/nixos/desktop/local/secrets";
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./local/nix-seal/identity.pub);
    secrets.nix-token-github-com.shared = true;
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
      # Login may need the network even when network-online.target has no
      # wait provider. Do not delay the desktop while authenticating.
      "multi-user.target"
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
      Restart = "on-failure";
      RestartSec = "1min";
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
