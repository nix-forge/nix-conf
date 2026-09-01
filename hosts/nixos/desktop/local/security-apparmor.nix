{ config, pkgs, ... }:
let
  # These are evaluated values, not literals copied from the current Nix
  # store.  A Sunshine or generated-applications update therefore produces a
  # matching new policy at the same time as the new system generation.
  sunshinePackage = toString config.services.sunshine.package;
  sunshineAppsFile = config.services.sunshine.settings.file_apps;
  sunshineStateDir = "${config.users.users.ianmh.home}/.config/sunshine";
  sunshineProfile =
    builtins.replaceStrings
      [ "@sunshinePackage@" "@sunshineAppsFile@" "@sunshineStateDir@" ]
      [ sunshinePackage sunshineAppsFile sunshineStateDir ]
      (builtins.readFile ./apparmor/sunshine.profile);
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
    # First policy-engineering pilot.  Sunshine is the locally exposed remote
    # desktop service, so it is more valuable to observe than an arbitrary GUI
    # application.  Keep it in complain mode until normal Moonlight sessions
    # have exercised its Wayland, PipeWire, NVIDIA, input, and application
    # launch paths.  `complain` allows those accesses while recording the
    # rules an eventual enforce policy must deliberately justify.
    #
    # The policy lives beside this host configuration because its attachment,
    # credentials, devices, and eventual filesystem/network allowance are
    # desktop-specific.  It must not be generalized to every NixOS machine.
    policies.sunshine = {
      profile = sunshineProfile;
      state = "complain";
    };

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
