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
      allowUnfreePredicate = _: true;
      allowVariants = true;
      allowBroken = false;
      # allowAliases = false;
    };
  };

  modules = with (tree.hosts.${folderName} // tree.configs.darwin); [
    base.base
    base.nix-settings
    ./cache.nix
    ./secrets.nix

    { system.primaryUser = "ianmh"; }
    # { time.timeZone = "America/New_York"; }

    preferences.finder
    preferences.dock
    preferences.animations
    preferences.misc

    security.pam
    security.firewall

    homebrew

    ./users.nix
  ];
}
