{
  tree,
  inputs,
  folderName,
  ...
}:
let
  install = pkg: { environment.systemPackages = [ pkg ]; };
in
{
  system = "aarch64-darwin";
  hostname = "Ian-MBP";

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
    };
  };

  modules = with (tree.darwin.${folderName} // tree.configs.darwin); [
    base.base
    base.nix-settings

    ./users.nix
  ];
}
