{
  tree,
  inputs,
  ...
}:
let
  install = pkg: { environment.systemPackages = [ pkg ]; };
in
{
  system = "aarch64-darwin";
  nixpkgsArgs = {
    config = {
      allowUnfree = true;
    };
  };

  modules = with tree.configs.darwin; [
    base.base

    ({ pkgs, ... }: install pkgs.firefox)
    ({ pkgs, ... }: install pkgs.vscode)
  ];
}
