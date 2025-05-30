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
  hostName = "Ian-MBP";

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
    };
  };

  modules = with (tree.hosts.${folderName} // tree.configs.darwin); [
    base.base
    base.nix-settings

    { system.primaryUser = "ianmh"; }
    { time.timeZone = "America/Los_Angeles"; }

    security.pam

    ./users.nix
  ];
}
