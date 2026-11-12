{
  programs.vscode.profiles.default.userSettings = {
    # Generated trees are still visible and searchable with explicit overrides.
    # Avoid excluding build/dist globally: some projects keep source there.
    "files.watcherExclude" = {
      "**/.git/objects/**" = true;
      "**/.git/subtree-cache/**" = true;
      "**/node_modules/**" = true;
      "**/.venv/**" = true;
      "**/__pycache__/**" = true;
      "**/target/**" = true;
    };
  };
}
