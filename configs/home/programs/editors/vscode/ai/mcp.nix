profileName: _: {
  programs.vscode.profiles.${profileName}.userMcp = {
    "servers" = {
      # User OAuth through VSCode to connect to GitHub
      "github/github-mcp-server" = {
        "type" = "http";
        "url" = "https://api.githubcopilot.com/mcp/";
      };
    };
  };
}
