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
  # Make the Python source an explicit store dependency of the generated
  # wrapper rather than interpolating a context-free local path.
  devVmResolver = builtins.path {
    path = ./dev_vm_host.py;
    name = "dev-vm-host.py";
  };

  # Resolve the only present host-only adapter at runtime. The VMX remains
  # outside the Nix store and only its validated adapter identity is retained.
  devVmHost = pkgs.replaceVarsWith {
    name = "dev-vm-host";
    src = ./scripts/dev-vm-host.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      python = lib.getExe pkgs.python3;
      resolver = devVmResolver;
      vmxFile = lib.escapeShellArg cfg.vmxFile;
      leaseFile = lib.escapeShellArg cfg.leaseFile;
      hostOnlyNetwork = lib.escapeShellArg hostOnlyNetwork;
    };
  };

  devVmProxy = pkgs.replaceVarsWith {
    name = "dev-vm-proxy";
    src = ./scripts/dev-vm-proxy.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      devVmHost = lib.getExe' devVmHost "dev-vm-host";
      sshPort = toString sshPort;
    };
  };

  devVmStatus = pkgs.replaceVarsWith {
    name = "dev-vm-status";
    src = ./scripts/dev-vm-status.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      devVmHost = lib.getExe' devVmHost "dev-vm-host";
      netcat = lib.getExe pkgs.netcat;
      lsof = lib.getExe pkgs.lsof;
      ssh = lib.getExe pkgs.openssh;
      sshPort = toString sshPort;
    };
  };

  devVmKeySetup = pkgs.replaceVarsWith {
    name = "dev-vm-key-setup.sh";
    src = ./scripts/create-dev-vm-key.sh;
    replacements = {
      mkdir = lib.getExe' pkgs.coreutils "mkdir";
      chmod = lib.getExe' pkgs.coreutils "chmod";
      sshKeygen = lib.getExe' pkgs.openssh "ssh-keygen";
      sshDir = lib.escapeShellArg sshDir;
      stateDir = lib.escapeShellArg stateDir;
      keyFile = lib.escapeShellArg keyFile;
      publicKeyFile = lib.escapeShellArg "${keyFile}.pub";
    };
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
      source ${devVmKeySetup}
    '';

    programs.ssh.settings = {
      # Use this plain SSH host in Codex and terminals. It deliberately does
      # not create a local port forward.
      dev-vm = devVmSshSettings;

    };
  };
}
