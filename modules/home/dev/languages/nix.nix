{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nixfmt
    statix
    deadnix

    nixd

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
        "nixos"
        "darwin"
        "home-manager"

        "nixpkgs"

        "nur"
        "noogle"
      ];
    };
  };
}
