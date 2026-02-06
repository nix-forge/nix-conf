{
  homeEntries,
  lib,
  myLib,
  ...
}:
{
  home-manager.users = lib.mkMerge [
    (myLib.configs.connectHome { homeEntry = homeEntries."ianmh@macbook-pro-m4"; })
  ];
}
