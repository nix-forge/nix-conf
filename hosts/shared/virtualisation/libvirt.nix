{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
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
  services.udev.extraRules = ''
    # Supporting VFIO
    SUBSYSTEM=="vfio", OWNER="root", GROUP="kvm"
  '';

  # enable virt-manager
  programs.virt-manager.enable = true;
}
