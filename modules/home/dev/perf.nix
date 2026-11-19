{ lib, pkgs, ... }: {
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.perf ];
  # Sampling permissions remain with host security policy.
}
