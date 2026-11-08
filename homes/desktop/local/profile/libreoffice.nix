{
  programs.libreoffice = {
    enable = true;
    # The matching NixOS policy is declared in the desktop-local
    # AppArmor module; other hosts deliberately remain unconfined.
    languageTool.appArmorProfile = "nixos-languagetool";
  };
}
