profileName:
{ pkgs, lib, ... }:
{
  programs.vscode.profiles.${profileName}.userMcp = {
    "servers" = {
      # User OAuth through VSCode to connect to GitHub
      "github/github-mcp-server" = {
        "type" = "http";
        "url" = "https://api.githubcopilot.com/mcp/";
      };
      # Serena MCP server
      "oraios/serena" = {
        "type" = "stdio";
        "command" = lib.getExe' pkgs.uv "uvx";
        "args" = [
          "--from"
          "git+https://github.com/oraios/serena"
          "serena"
          "start-mcp-server"
          "--context"
          "ide-assistant"
        ];
      };
    };
  };
}
