{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.services.devVm;
  sshDir = "${config.home.homeDirectory}/.ssh";
  keyFile = "${sshDir}/dev-vm";
  stateDir = "${config.xdg.stateHome}/dev-vm";

  # This is the MAC address of ethernet1, the VM's host-only adapter. VMware
  # gives this adapter a lease from the 172.16.42.0/24 network on this Mac.
  devVmHost = pkgs.writeShellApplication {
    name = "dev-vm-host";
    runtimeInputs = [ pkgs.gawk ];
    text = ''
      set -eu

      lease_file=/var/db/vmware/vmnet-dhcpd-vmnet1.leases
      vm_mac=00:0c:29:35:9f:d5

      if [ ! -r "$lease_file" ]; then
        printf 'Cannot read VMware host-only DHCP leases: %s\n' "$lease_file" >&2
        exit 1
      fi

      vm_host="$(${pkgs.gawk}/bin/awk -v mac="$vm_mac" '
        /^lease / { lease = $2 }
        $1 == "hardware" {
          address = tolower($3)
          sub(/;$/, "", address)
          if (address == mac) host = lease
        }
        END { print host }
      ' "$lease_file")"

      case "$vm_host" in
        172.16.42.*) printf '%s\n' "$vm_host" ;;
        *)
          printf 'No valid host-only lease found for the development VM (%s).\n' "$vm_mac" >&2
          exit 1
          ;;
      esac
    '';
  };

  devVmProxy = pkgs.writeShellApplication {
    name = "dev-vm-proxy";
    runtimeInputs = [ devVmHost ];
    text = ''
      set -eu
      # The Darwin system netcat works reliably with VMware Fusion's host-only
      # adapter.  The LibreSSL netcat packaged by Nix reports a spurious
      # host-unreachable error for this path after a VM adapter reset.
      # Do not pass `-w`: it also times out idle reads in a healthy SSH tunnel.
      exec /usr/bin/nc "$(dev-vm-host)" "$1"
    '';
  };

  devVmStatus = pkgs.writeShellApplication {
    name = "dev-vm-status";
    runtimeInputs = [
      devVmHost
      pkgs.netcat
      pkgs.lsof
      pkgs.openssh
    ];
    text = ''
      set -eu
      vm_host="$(dev-vm-host)"

      printf 'Host-only VM address: %s\n' "$vm_host"
      nc -vz -w 3 "$vm_host" 22

      printf '\nMac control-host listeners:\n'
      lsof -nP -iTCP:5173 -iTCP:8788 -iTCP:8443 -sTCP:LISTEN || true

      printf '\nWindows development prerequisites:\n'
      ssh dev-vm '
        set -eu
        for command_name in codex git dotnet pwsh; do
          command -v "$command_name" >/dev/null || {
            printf "Missing required command: %s\n" "$command_name" >&2
            exit 1
          }
          printf "%s: %s\n" "$command_name" "$(command -v "$command_name")"
        done
      '
    '';
  };

  devVmSshSettings = {
    HostName = "dev-vm";
    HostKeyAlias = "dev-vm";
    User = cfg.windowsUser;
    IdentityFile = keyFile;
    IdentitiesOnly = true;
    AddKeysToAgent = "no";
    BatchMode = true;
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PubkeyAuthentication = true;

    # Resolve the current VMware host-only DHCP lease at connection time.
    # The VM's NAT interface is deliberately never used for inbound access.
    ProxyCommand = "${devVmProxy}/bin/dev-vm-proxy %p";

    # Do not let the unattended launchd agent accept a host key. Add the
    # verified key once before the tunnel starts.
    StrictHostKeyChecking = "yes";
    UpdateHostKeys = "no";
    ControlMaster = "no";
    ServerAliveInterval = 30;
    ServerAliveCountMax = 3;
  };
in
{
  options.services.devVm = {
    enable = lib.mkEnableOption "host-only SSH access to the development VM";

    windowsUser = lib.mkOption {
      type = lib.types.str;
      default = config.home.username;
      description = "Windows account permitted to log in to the development VM through SSH.";
    };

  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin;
        message = "services.devVm is implemented for the VMware Fusion host on macOS.";
      }
    ];

    home.packages = [
      devVmHost
      devVmStatus
    ];

    home.activation.devVmKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu
      umask 0077
      mkdir -p ${lib.escapeShellArg sshDir} ${lib.escapeShellArg stateDir}
      chmod 700 ${lib.escapeShellArg sshDir} ${lib.escapeShellArg stateDir}

      if [ ! -f ${lib.escapeShellArg keyFile} ]; then
        ${pkgs.openssh}/bin/ssh-keygen \
          -t ed25519 \
          -a 100 \
          -N "" \
          -C 'dev-vm tunnel key' \
          -f ${lib.escapeShellArg keyFile}
      fi

      if [ ! -f ${lib.escapeShellArg "${keyFile}.pub"} ]; then
        ${pkgs.openssh}/bin/ssh-keygen -y -f ${lib.escapeShellArg keyFile} > ${lib.escapeShellArg "${keyFile}.pub"}
      fi

      chmod 600 ${lib.escapeShellArg keyFile}
      chmod 644 ${lib.escapeShellArg "${keyFile}.pub"}
    '';

    programs.ssh.settings = {
      # Use this plain SSH host in Codex and terminals. It deliberately does
      # not create a local port forward.
      dev-vm = devVmSshSettings;

    };
  };
}
