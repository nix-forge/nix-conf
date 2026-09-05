{ lib, ... }:
let
  mkPolicy =
    {
      slug,
      installationMode,
      privateBrowsing,
      defaultArea,
    }:
    {
      installation_mode = installationMode;
      updates_disabled = false;
      default_area = defaultArea;
    }
    // lib.optionalAttrs (installationMode != "allowed") {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
    }
    // lib.optionalAttrs privateBrowsing { private_browsing = true; };

  mkPolicies =
    extensions:
    {
      "*".installation_mode = "blocked";
    }
    // lib.mapAttrs' (
      _name: extension:
      lib.nameValuePair extension.id (mkPolicy {
        inherit (extension) slug privateBrowsing defaultArea;
        installationMode =
          if extension.mode == "required" then
            "force_installed"
          else if extension.mode == "allowed" then
            "allowed"
          else
            "normal_installed";
      })
    ) extensions;
in
{
  extensions = { inherit mkPolicies; };
}
