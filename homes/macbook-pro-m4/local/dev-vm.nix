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
  hostOnlyNetwork = "172.16.42.0/24";
  sshPort = 22;
  devVmResolver = ./dev_vm_host.py;

  # Resolve the only present host-only adapter at runtime. The VMX remains
  # outside the Nix store and only its validated adapter identity is retained.
  devVmHost = pkgs.writeShellApplication {
    name = "dev-vm-host";
    text = ''
      set -eu
      exec ${pkgs.python3}/bin/python3 ${devVmResolver} \
        --vmx ${lib.escapeShellArg cfg.vmxFile} \
        --leases ${lib.escapeShellArg cfg.leaseFile} \
        --lease-owner-uid 0 \
        --network ${lib.escapeShellArg hostOnlyNetwork}
    '';
  };

  devVmProxy = pkgs.writeShellApplication {
    name = "dev-vm-proxy";
    runtimeInputs = [ devVmHost ];
    text = ''
      set -eu
      if [ "$#" -ne 1 ] || [ "$1" != ${toString sshPort} ]; then
        printf 'dev-vm-proxy only permits the configured SSH port.\n' >&2
        exit 1
      fi
      # Keep address resolution and transport reachability separate. Python's
      # socket probe can report a spurious host-unreachable result on Darwin
      # after a VMware adapter reset even when the system TCP stack can connect.
      # The Darwin system netcat both performs the real reachability check and
      # becomes the SSH byte stream, so there is no check/use gap here.
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
      nc -vz -w 3 "$vm_host" ${toString sshPort}

      printf '\nMac control-host listeners:\n'
      lsof -nP -iTCP:5173 -iTCP:8788 -iTCP:8443 -sTCP:LISTEN || true

      printf '\nWindows development prerequisites:\n'
      ssh_arguments=()
      if [ -n "''${DEV_VM_SSH_CONFIG:-}" ]; then
        ssh_arguments=(-F "$DEV_VM_SSH_CONFIG")
      fi
      ssh "''${ssh_arguments[@]}" dev-vm '
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
    Port = sshPort;
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

    vmxFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Developer/Windows11_64-bit_Arm.vmwarevm/Windows11_64-bit_Arm.vmx";
      description = "Absolute path to the VMware VMX file used to discover the current host-only adapter identity.";
    };

    leaseFile = lib.mkOption {
      type = lib.types.str;
      default = "/private/var/db/vmware/vmnet-dhcpd-vmnet1.leases";
      description = "Absolute path to VMware Fusion's host-only DHCP lease database.";
    };

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
      {
        assertion = lib.hasPrefix "/" cfg.vmxFile;
        message = "services.devVm.vmxFile must be an absolute path.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.leaseFile;
        message = "services.devVm.leaseFile must be an absolute path.";
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
