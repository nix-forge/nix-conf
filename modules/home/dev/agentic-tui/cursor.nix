{ pkgs, lib, ... }: {
  imports = [ ./agent-skills.nix ];
  programs.agent-skills.clients.cursor.enable = lib.mkDefault true;
  home.packages = with pkgs; [ cursor-cli ];
}
