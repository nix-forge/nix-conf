{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.hardware.cpu.amd;
in
{
  options.hardware.cpu.amd = {
    enable = lib.mkEnableOption "Enable support for AMD CPUs.";
    iommu.enable = lib.mkEnableOption "Enable IOMMU support.";
    kvm = {
      enable = lib.mkEnableOption "Enable KVM support.";
      nestedVirtualization = lib.mkEnableOption "Enable nested virtualization.";
    };
  };

  imports = [ inputs.ucodenix.nixosModules.default ];

  config = lib.mkIf cfg.enable (
    let
      kver = config.boot.kernelPackages.kernel.version;
    in
    lib.mkMerge [
      { services.ucodenix.enable = true; }

      {
        hardware.enableRedistributableFirmware = lib.mkDefault true;
        hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      }

      # Virtualization
      # KVM support
      (lib.mkIf cfg.kvm.enable {
        boot.kernelParams = [ "kvm-amd" ];
        boot.extraModprobeConfig = lib.mkIf cfg.kvm.nestedVirtualization "options kvm_amd nested=1";
      })
      # IOMMU Support
      (lib.mkIf cfg.iommu.enable {
        boot.kernelParams = [
          "amd_iommu=on" # enable IOMMU support
          "iommu=pt" # prevent Linux from touching devices which cannot be passed through
        ];
      })

      # AMD PState
      {
        boot = lib.mkMerge [
          (lib.mkIf ((lib.versionAtLeast kver "5.17") && (lib.versionOlder kver "6.1")) {
            kernelParams = [ "initcall_blacklist=acpi_cpufreq_init" ];
            kernelModules = [ "amd-pstate" ];
          })
          (lib.mkIf ((lib.versionAtLeast kver "6.1") && (lib.versionOlder kver "6.3")) {
            kernelParams = [ "amd_pstate=passive" ];
          })
          (lib.mkIf (lib.versionAtLeast kver "6.3") { kernelParams = [ "amd_pstate=active" ]; })
        ];
      }

      # IGPU
      {
        boot = lib.mkIf (
          (lib.versionAtLeast config.boot.kernelPackages.kernel.version "6.2")
          && (lib.versionOlder config.boot.kernelPackages.kernel.version "6.6")
        ) { kernelParams = [ "amdgpu.sg_display=0" ]; };
      }

      # Enables the zenpower sensor in lieu of the k10temp sensor on Zen CPUs https://git.exozy.me/a/zenpower3
      # On Zen CPUs zenpower produces much more data entries
      {
        boot.blacklistedKernelModules = [ "k10temp" ];
        boot.extraModulePackages = [ config.boot.kernelPackages.zenpower ];
        boot.kernelModules = [ "zenpower" ];
      }
    ]
  );
}
