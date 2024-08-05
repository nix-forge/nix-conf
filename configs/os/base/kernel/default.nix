{ pkgs, ... }:
{
  # imports = [ ./config ];
  # boot.kernelPackages = pkgs.linuxPackagesFor (
  #   pkgs.linuxKernel.kernels.linux_xanmod_latest.override { ignoreConfigErrors = true; }
  # );
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_latest;
}
