{ config, ... }:
let
  runtimeFiles = (config.nixSeal.secrets or { }) // (config.nixSeal.templates or { });
  includeCornell =
    if builtins.hasAttr "cornell-net-id-ssh-config" runtimeFiles then
      { Include = runtimeFiles."cornell-net-id-ssh-config".path; }
    else
      { };
  gitIdentity = {
    User = "git";
    IdentitiesOnly = true;
    IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
  };
in
{
  # The desktop uses its GNOME Keyring-backed SSH agent. Agent integration is
  # personal, so it stays out of the shared client policy.
  programs.ssh.settings."*".AddKeysToAgent = "yes";

  programs.ssh.settings = {
    "macbook macbook-pro-m4" = {
      HostName = "Ian-MBP.local";
      HostKeyAlias = "macbook";
      User = "ianmh";
      IdentitiesOnly = true;
      IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      StrictHostKeyChecking = "yes";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };

    # Servers
    "ugclinux" = {
      HostName = "ugclinux.cs.cornell.edu";

      SetEnv = {
        TERM = "xterm-256color";
      };
    }
    // includeCornell;

    # NERSC
    # https://docs.nersc.gov/connect/vscode/
    "dtn*.nersc.gov perlmutter*.nersc.gov *.nersc.gov" = {
      IdentitiesOnly = true;
      IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      LogLevel = "QUIET";
      SetEnv = {
        TERM = "xterm-256color";
      };
    }
    // includeCornell;
    "nid??????" = {
      HostName = "%h";
      IdentitiesOnly = true;
      IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      LogLevel = "QUIET";
      # Compute-node names are dynamic, but TOFU still prevents a silently
      # changed host key from being accepted after the first connection.
      StrictHostKeyChecking = "accept-new";
      ProxyJump = "perlmutter.nersc.gov";
      SetEnv = {
        TERM = "xterm-256color";
      };
    }
    // includeCornell;

    # Git
    "github.com gist.github.com ssh.github.com" = gitIdentity;

    "github.coecis.cornell.edu" = gitIdentity // {
      HostName = "github.coecis.cornell.edu";
    };

    "gitlab.cs.cornell.edu" = gitIdentity // {
      HostName = "gitlab.cs.cornell.edu";
    };
  };
}
