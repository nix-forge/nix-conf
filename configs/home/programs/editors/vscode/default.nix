profileName:
_:
{
  programs.vscode = {
    enable = true;
    mutableExtensionsDir = false;
    profiles.${profileName} = {
      enableExtensionUpdateCheck = false;
      enableUpdateCheck = false;
    };
  };
}
