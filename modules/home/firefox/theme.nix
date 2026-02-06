profileName:
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  inherit (lib.cust.firefox) toUserJS;

  # TODO: fix this by not hardcoding or switching to the new location since firefox 147
  mozillaConfigPath = if isDarwin then "Library/Application Support/Mozilla" else ".mozilla";

  firefoxConfigPath =
    if isDarwin then "Library/Application Support/Firefox" else "${mozillaConfigPath}/firefox";

  profilesPath = if isDarwin then "${firefoxConfigPath}/Profiles" else firefoxConfigPath;
in
{
  # Copy Firefox-UI-Fix theme into the profile's chrome directory
  home.file = {
    "${profilesPath}/${profileName}/chrome/icons" = {
      source = inputs.firefox-ui-fix + "/icons";
    };
    "${profilesPath}/${profileName}/chrome/css" = {
      source = inputs.firefox-ui-fix + "/css";
    };
    "${profilesPath}/${profileName}/chrome/userChrome.css" = {
      source = inputs.firefox-ui-fix + "/userChrome.css";
    };
    "${profilesPath}/${profileName}/chrome/userContent.css" = {
      source = inputs.firefox-ui-fix + "/userContent.css";
    };
  };

  programs.firefox.profiles.${profileName} = {
    # Firefox UI Fix User JS
    extraConfig = lib.mkBefore (
      lib.strings.concatLines [
        (builtins.readFile "${inputs.firefox-ui-fix}/user.js")
        (toUserJS {
          "browser.theme.native-theme" = false; # Disable native theme to use custom themes
        })
      ]
    );
  };
}
