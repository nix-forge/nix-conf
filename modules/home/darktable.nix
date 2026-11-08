{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  # Do not inherit a host-wide CUDA setting here. Darktable's GPU path brings
  # a very large CUDA/OpenCV closure into every Home Manager generation; CPU
  # rendering remains fully functional, while a GPU build can be a deliberate
  # host-specific override when it is worth that tradeoff.
  cpuPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config = {
      allowUnfree = true;
      cudaSupport = false;
    };
  };
  inherit (cpuPkgs) darktable;

  darktableApp = pkgs.darktable-app-personal.override { inherit darktable; };
in
{
  home.packages = [ darktable ] ++ lib.optionals isDarwin [ darktableApp ];
}
