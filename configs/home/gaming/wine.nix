{
  pkgs,
  config,
  inputs,
  ...
}:
{
  home.packages = [
    # (pkgs.wineWowPackages.unstableFull.override { waylandSupport = true; })
    (inputs.nix-gaming.packages.${pkgs.system}.wine-tkg.override (old: {
      supportFlags = old.supportFlags // {
        waylandSupport = true; # Causes a cache miss so a build is needed
      };
    }))
    pkgs.winetricks
  ];

  home.sessionVariables = {
    WINEARCH = "win64";
    WINEPREFIX = "${config.xdg.dataHome}/wine";
  };
}
