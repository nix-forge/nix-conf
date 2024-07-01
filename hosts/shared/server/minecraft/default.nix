{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  port = 25565; # default port which allows you to connect without specifying a port
in
{
  imports = [ inputs.nix-minecraft.nixosModules.minecraft-servers ];
  nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
    servers = {
      vanillaPlus = import ./vanillaPlus.nix {
        inherit
          port
          pkgs
          lib
          config
          ;
      };
    };
  };
}
