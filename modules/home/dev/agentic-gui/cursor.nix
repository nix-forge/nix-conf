{ pkgs, lib, ... }: {
  imports = [ ../agentic-tui/agent-skills.nix ];
  programs.agent-skills.clients.cursor.enable = lib.mkDefault true;
  home.packages = with pkgs; [ code-cursor ];
}
