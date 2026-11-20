{
  programs.vscode.profiles.default.userSettings."remote.SSH.remotePlatform" = {
    # These aliases share the same SSH destination. Declare both so Remote SSH
    # does not try to persist platform discovery into immutable user settings.
    macbook = "macOS";
    macbook-pro-m4 = "macOS";
  };
}
