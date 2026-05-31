{ modules, ... }:
# let
#   darwinOpenSslTestOverlay = final: prev: {
#     openssl = prev.openssl.overrideAttrs (old: {
#       postPatch =
#         (old.postPatch or "")
#         + final.lib.optionalString final.stdenv.hostPlatform.isDarwin ''
#           rm -f test/recipes/70-test_sslmessages.t
#         '';
#     });
#   };
# in
{
  system = "aarch64-darwin";
  # darwinSdkVersion = "15.5";
  # darwinMinVersion = "15.4";
  hostName = "Ian-MBP";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
    groups = [ "IanHollow" ];
  };

  nixpkgsArgs = {
    # overlays = [ darwinOpenSslTestOverlay ];
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    { system.primaryUser = "ianmh"; }

    ## Base
    meta
    determinate
    nix-settings
    registry
    cache
    agenix

    ## Users
    home-manager
    users

    security
    stylix
    fonts
  ];
}
