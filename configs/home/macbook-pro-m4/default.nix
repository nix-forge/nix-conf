{ modules, ... }:
{
  system = "aarch64-darwin";
  username = "ianmh";
  homeDirectory = "/Users/ianmh";
  uid = 501;

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    ## Base
    meta
    determinate
    nix-settings
    cache
  ];
}
