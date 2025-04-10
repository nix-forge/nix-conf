{
  tree,
  pkgs,
  inputs,
  ...
}:
let
  darwinDir = tree.configs.home;
  sharedDir = tree.configs.shared;
  install = pkg: { environment.systemPackages = [ pkg ]; };
in
{
  system = "aarch64-darwin";
  nixpkgsArgs = {
    config = {
      allowUnfree = true;
    };
  };

  modules = with darwinDir; [
    # base.base

    (install pkgs.firefox)
    (install pkgs.vscode)
  ];
}
