{
  inputs,
  lib,
  config,
  myLib,
  ...
}:
let
  inherit (myLib.firefox) toUserJS;

  profilePath = config.programs.firefox.profiles.default.path;
in
{
  # Copy Firefox-UI-Fix theme into the profile's chrome directory
  home.file = {
    "${profilePath}/chrome/icons" = {
      source = inputs.firefox-ui-fix + "/icons";
    };
    "${profilePath}/chrome/css" = {
      source = inputs.firefox-ui-fix + "/css";
    };
    "${profilePath}/chrome/userChrome.css" = {
      source = inputs.firefox-ui-fix + "/userChrome.css";
    };
    "${profilePath}/chrome/userContent.css" = {
      source = inputs.firefox-ui-fix + "/userContent.css";
    };
  };

  programs.firefox.profiles.default = {
    # Firefox UI Fix User JS
    extraConfig = lib.mkBefore (
      lib.strings.concatLines [
        (builtins.readFile "${inputs.firefox-ui-fix}/user.js")
        (toUserJS {
          "browser.theme.native-theme" = false; # Disable native theme to use custom theme
        })
      ]
    );
  };
}
