{ config, lib, ... }:
let
  includeCornell =
    if lib.hasAttrByPath [ "nixSeal" "secrets" "cornell-net-id-ssh-config" ] config then
      { Include = config.nixSeal.secrets."cornell-net-id-ssh-config".path; }
    else
      { };
in
{
  # UseKeychain is Apple's extension. Ignore it if a Nix-provided OpenSSH
  # client is selected, while the system client uses the macOS Keychain.
  programs.ssh.extraOptionOverrides.IgnoreUnknown = "UseKeychain";
  programs.ssh.settings."*" = {
    AddKeysToAgent = "yes";
    UseKeychain = "yes";
  };

  programs.ssh.settings = {
    desktop = {
      HostName = "192.168.10.178";
      HostKeyAlias = "desktop";
      User = "ianmh";
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };

    "github.coecis.cornell.edu gitlab.cs.cornell.edu" = {
      User = "git";
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };

    ugclinux = {
      HostName = "ugclinux.cs.cornell.edu";
      SetEnv = {
        TERM = "xterm-256color";
      };

    }
    // includeCornell;

    "dtn*.nersc.gov perlmutter*.nersc.gov *.nersc.gov" = {
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      SetEnv = {
        TERM = "xterm-256color";
      };

      LogLevel = "QUIET";
    }
    // includeCornell;

    "perlmutter-agent" = {
      HostName = "perlmutter.nersc.gov";
      User = null;
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      ForwardAgent = true;

      SetEnv = {
        TERM = "xterm-256color";
      };
      LogLevel = "QUIET";
    }
    // includeCornell;

    "nid??????" = {
      HostName = "%h";
      ProxyJump = "perlmutter.nersc.gov";

      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      SetEnv = {
        TERM = "xterm-256color";
      };

      UserKnownHostsFile = "${config.home.homeDirectory}/.ssh/known_hosts_nersc_compute";

      LogLevel = "QUIET";
      StrictHostKeyChecking = "accept-new";

      UpdateHostKeys = "no";
    }
    // includeCornell;

    "github.com gist.github.com gitlab.com codeberg.org" = {
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };
}
