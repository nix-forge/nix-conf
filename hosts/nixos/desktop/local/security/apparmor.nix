{ pkgs, ... }:
let
  languageToolPackage = toString pkgs.languagetool;
  languageToolProfile = builtins.replaceStrings [ "@languageToolPackage@" ] [ languageToolPackage ] (
    builtins.readFile ./apparmor/languagetool.profile
  );
  telegrafPackage = toString pkgs.telegraf;
  smartmontoolsPackage = toString pkgs.smartmontools;
  telegrafProfile =
    builtins.replaceStrings
      [ "@telegrafPackage@" "@smartmontoolsPackage@" ]
      [ telegrafPackage smartmontoolsPackage ]
      (builtins.readFile ./apparmor/telegraf.profile);
in
{
  security.appArmorBaseline.enable = true;

  security.apparmor = {
    # LanguageTool processes document text received over its loopback-only
    # HTTP API.  This scoped user-service profile is a high-value, low-impact
    # pilot: it does not apply to LibreOffice or to unrelated Java programs.
    policies.languagetool = {
      profile = languageToolProfile;
      state = "complain";
    };

    # Telegraf exposes host inventory and reads several kernel, storage, and
    # firmware-facing interfaces.  Its listener is intentionally loopback
    # only, but the service is still a useful low-risk discovery target.  Keep
    # this separate from the generic module: its SMART wrapper and NVMe access
    # are properties of this physical desktop, not every NixOS host.
    policies.telegraf = {
      profile = telegrafProfile;
      state = "complain";
    };

  };
}
