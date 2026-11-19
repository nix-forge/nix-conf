{ lib }:
{
  suite,
  browser,
  profiles,
  configDirectory,
}:
let
  mkExtensionPolicies = import ./extension-policies.nix { inherit lib; };
  mkUblockPolicy = import ./ublock-policy.nix { inherit lib; };
  extensions = suite.extensions.shared // suite.extensions.${browser};
  defaultProfile = lib.findFirst (profile: profile.isDefault) null (lib.attrValues profiles);
  ublockPolicies = lib.optionalAttrs (extensions ? ublockOrigin) {
    "3rdparty".Extensions.${extensions.ublockOrigin.id} = mkUblockPolicy {
      inherit (suite.blocking) customFilterLists;
      inherit (suite.shared.ublock) defaultFilterLists settings;
    };
  };
in
{
  policies =
    suite.systemResolverPolicy
    // suite.geckoPolicies
    // {
      ExtensionSettings = mkExtensionPolicies extensions;
    }
    // ublockPolicies;
  reconcileInstallRegistry = lib.escapeShellArgs [
    (lib.getExe suite.shared.geckoInstallRegistry.reconciler)
    "--profiles-registry"
    "${configDirectory}/profiles.ini"
    "--install-registry"
    "${configDirectory}/installs.ini"
    "--default-profile"
    "Profiles/${defaultProfile.path}"
  ];
}
