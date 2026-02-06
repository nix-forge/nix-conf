{
  homes,
  lib,
  myLib,
  ...
}:
{
  home-manager.users = lib.mkMerge [
    (myLib.configs.connectHome { config = homes.macbook-pro-m4; })
  ];
}
