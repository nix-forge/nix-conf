{
  config,
  lib,
  pkgs,
  ...
}:
let
  sshDir = "${config.home.homeDirectory}/.ssh";
  stateDir = "${config.xdg.stateHome}/libvirt-vms";
  keyFile = "${sshDir}/libvirt-dev";
  guestAddresses = {
    windows-runtime = "192.168.123.12";
  };

  keySetup = pkgs.replaceVarsWith {
    name = "libvirt-vm-key-setup";
    src = ./scripts/create-libvirt-vm-key.sh;
    isExecutable = true;
    replacements = {
      chmod = lib.getExe' pkgs.coreutils "chmod";
      keyFile = lib.escapeShellArg keyFile;
      mkdir = lib.getExe' pkgs.coreutils "mkdir";
      publicKeyFile = lib.escapeShellArg "${keyFile}.pub";
      sshDir = lib.escapeShellArg sshDir;
      sshKeygen = lib.getExe' pkgs.openssh "ssh-keygen";
      stateDir = lib.escapeShellArg stateDir;
    };
  };

  sshSettings = name: address: {
    HostName = address;
    HostKeyAlias = name;
    User = "vmadmin";
    Port = 22;
    IdentityFile = [ keyFile ];
    IdentitiesOnly = true;
    AddKeysToAgent = "no";
    ForwardAgent = false;
    ForwardX11 = false;
    BatchMode = true;
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PubkeyAuthentication = true;
    StrictHostKeyChecking = "yes";
    UpdateHostKeys = "no";
    ControlMaster = "no";
    ServerAliveInterval = 30;
    ServerAliveCountMax = 3;
  };
in
{
  home.activation.libvirtVmKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    source ${keySetup}
  '';

  programs.ssh.settings = lib.mapAttrs sshSettings guestAddresses;
}
