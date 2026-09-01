{
  nixos = { lib, ... }: {
    # This module owns portable daemon policy only. Hosts retain ownership of
    # reachability, listener addresses and ports, allowed accounts, and root
    # access because those choices depend on each machine's recovery path.
    services.openssh = {
      enable = true;
      openFirewall = lib.mkDefault false;

      # Keep SSH ready for administration. Socket activation is a good fit
      # for disposable servers, but it makes a host's management path less
      # predictable for little saving on an always-on machine.
      startWhenNeeded = lib.mkDefault false;

      settings = {
        # Keys are the only interactive authentication method. PAM still
        # creates sessions and applies account policy without re-enabling
        # password authentication.
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitEmptyPasswords = false;
        PubkeyAuthentication = true;
        AuthenticationMethods = "publickey";
        UsePAM = true;

        # Keep remote GUI access and agent forwarding opt-in at the host.
        # Local and loopback-only port forwarding remain available for
        # ordinary SSH workflows such as ProxyJump and development tunnels.
        X11Forwarding = false;
        AllowAgentForwarding = false;
        GatewayPorts = "no";
        PermitTunnel = "no";
        PermitUserEnvironment = false;

        # The maintained NixOS algorithm defaults track supported OpenSSH
        # releases, including its hybrid post-quantum key exchange. Do not
        # freeze ciphers, MACs, or KEX lists in this module.

        Compression = false;
        TCPKeepAlive = false;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 3;

        # Bound pre-authentication work. Per-source penalties remain at
        # OpenSSH's current default and complement these admission limits.
        LoginGraceTime = 30;
        MaxAuthTries = 4;
        MaxStartups = "10:30:60";
        UseDns = false;
        StreamLocalBindUnlink = true;
        LogLevel = "VERBOSE";
      };
    };
  };

  homeManager =
    { config, lib, ... }:
    let
      controlPathDir = "${config.home.homeDirectory}/.ssh/cm";
    in
    {
      programs.ssh = {
        enable = true;
        # Home Manager writes the entire user configuration. This avoids
        # inheriting a distribution-wide config whose ordering may weaken a
        # host-specific rule declared in a local profile.
        enableDefaultConfig = false;

        settings = {
          "*.local" = {
            Compression = false;
            ConnectTimeout = "3";
          };

          # These forges use a fixed SSH account. Identities belong in local
          # profile rules, so users can choose the key they want to present.
          "github.com gist.github.com gitlab.com codeberg.org".User = "git";

          "*" = {
            ForwardAgent = false;
            ForwardX11 = false;
            Compression = false;

            ServerAliveInterval = 60;
            ServerAliveCountMax = 3;
            TCPKeepAlive = "no";
            ConnectTimeout = "10";
            ConnectionAttempts = "2";

            HashKnownHosts = true;
            StrictHostKeyChecking = "accept-new";
            UpdateHostKeys = "yes";

            # Reuse authenticated connections without exposing a predictable
            # socket name. The parent is mode 0700 and stale sockets are safe
            # to replace during a later connection.
            ControlMaster = "auto";
            ControlPath = "${controlPathDir}/%C";
            ControlPersist = "10m";
            StreamLocalBindUnlink = "yes";

            # A requested forward must be established before SSH starts the
            # remote command. This prevents quietly running a command without
            # the tunnel it depends on.
            ExitOnForwardFailure = "yes";
          };
        };
      };

      home.activation.sshControlPathDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "${controlPathDir}"
        chmod 700 "${controlPathDir}"
      '';
    };

  # nix-darwin has no declarative sshd module. macOS Remote Login remains an
  # explicit host decision, while each attached Home Manager profile gets the
  # portable client policy above. Deliberately avoid replacing Apple's ssh
  # binary so UseKeychain continues to work.
  darwin = _: { };
}
