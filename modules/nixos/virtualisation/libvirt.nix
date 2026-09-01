{ pkgs, ... }: {
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # additional kernel modules that may be needed by libvirt
  boot.kernelModules = [ "vfio-pci" ];

  # Trust bridge network interface(s)
  networking.firewall.trustedInterfaces = [
    "virbr0"
    "br0"
  ];

  # For passthrough with VFI
  services.udev.extraRules = builtins.readFile ./50-vfio.rules;

  # enable virt-manager
  programs.virt-manager.enable = true;
}
