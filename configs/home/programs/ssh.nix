{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin;
  cmDir = "${config.home.homeDirectory}/.ssh/cm"; # short path for mux sockets
in
{
  programs.ssh = {
    enable = true;

    # Fast, reliable connections
    controlMaster = "auto";
    controlPersist = "10m";
    controlPath = "${cmDir}/%C"; # hashed path avoids 'too long' errors
    compression = true; # good on slow/latency links

    # Safety + convenience
    hashKnownHosts = true;
    addKeysToAgent = "yes";
    forwardAgent = lib.mkForce false; # only enable per-host when needed
    serverAliveInterval = 60;
    serverAliveCountMax = 3;

    extraConfig = ''
      # Prefer key auth and stop trying passwords (faster, fewer lockouts)
      PreferredAuthentications publickey
      IdentitiesOnly yes

      # Accept host key updates for hosts you already trust (key rotation)
      UpdateHostKeys yes

      # Small QoL
      TCPKeepAlive yes
      EscapeChar none
      VisualHostKey yes

      ${lib.optionalString isDarwin ''
        # macOS: allow Apple's ssh special flag without breaking upstream ssh
        IgnoreUnknown UseKeychain
        UseKeychain yes
      ''}
    '';

    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identitiesOnly = true;
      };

      "gist.github.com" = {
        hostname = "gist.github.com";
        user = "git";
        identitiesOnly = true;
      };

      # Local network: don’t waste CPU compressing
      "*.local" = {
        compression = false;
      };
    };
  };
}
