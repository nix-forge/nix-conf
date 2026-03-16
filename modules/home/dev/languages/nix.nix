{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    nixfmt
    statix
    deadnix

    nixpkgs-reviewFull
  ];

  programs.television.enable = true;

  programs.nix-search-tv = {
    enable = true;
    enableTelevisionIntegration = true;

    settings = {
      update_interval = "24h";
      enable_waiting_message = true;
      indexes = [
        "nixpkgs"
        "home-manager"
        "nur"
        "noogle"
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ "nixos" ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ "darwin" ];
    };
  };
}
