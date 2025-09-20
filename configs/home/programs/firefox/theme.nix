profileName:
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  mozillaConfigPath = if isDarwin then "Library/Application Support/Mozilla" else ".mozilla";

  firefoxConfigPath =
    if isDarwin then "Library/Application Support/Firefox" else "${mozillaConfigPath}/firefox";

  profilesPath = if isDarwin then "${firefoxConfigPath}/Profiles" else firefoxConfigPath;
in
{
  # Copy Firefox-UI-Fix theme into the profile's chrome directory
  home.file."${profilesPath}/${profileName}/chrome" = {
    source = inputs.firefox-ui-fix;
    recursive = true;
  };

  programs.firefox.profiles.${profileName} = {
    settings = {
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      "layout.css.has-selector.enabled" = true;
    };

    # Firefox UI Fix User JS
    extraConfig = lib.mkBefore (
      lib.strings.concatLines [ (builtins.readFile "${inputs.firefox-ui-fix}/user.js") ]
    );
  };
}
