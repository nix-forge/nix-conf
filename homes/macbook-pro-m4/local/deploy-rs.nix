{ inputs, pkgs, ... }: {
  home.packages = [ inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
