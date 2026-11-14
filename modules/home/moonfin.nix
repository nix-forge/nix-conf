{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.moonfin ];

  assertions = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    {
      assertion = config.targets.darwin.copyApps.enable;
      message = "Moonfin on macOS requires a copied app bundle for LaunchServices.";
    }
  ];
}
