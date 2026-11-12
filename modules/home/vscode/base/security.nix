{
  programs.vscode.profiles.default.userSettings = {
    # Trust remains an explicit decision for each workspace; extensions are
    # executable code, so this complements the declarative extension allowlist.
    "security.workspace.trust.enabled" = true;
    "security.workspace.trust.startupPrompt" = "always";
    "security.workspace.trust.untrustedFiles" = "newWindow";
    "extensions.autoUpdate" = false;
    "extensions.autoCheckUpdates" = false;

  };
}
