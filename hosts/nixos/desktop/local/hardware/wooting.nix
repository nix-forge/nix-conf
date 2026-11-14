{ pkgs, ... }:
let
  # Native schema 15 export of the restored ANSI typing profile. Keep the
  # requested RGB channel values; device readback can round LED channels.
  profile = builtins.fromJSON (builtins.readFile ./wooting-typing.json);
  exports = pkgs.linkFarm "wooting-80he-profiles" [
    {
      name = "01-typing.json";
      path = pkgs.writeText "wooting-typing.json" (builtins.toJSON profile + "\n");
    }
  ];
in
{
  # Activation installs the export; Wootility owns deliberate onboard writes.
  environment.etc."wooting/profiles".source = exports;
  system.build.wootingProfiles = exports;
}
