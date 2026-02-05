{ tree, folderName, ... }:
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

    # TODO: switch preferences to be apart of Home Manager as I believe it is supported
    preferences.accessibility
    preferences.animations
    preferences.applications
    preferences.dock
    preferences.file-management
    preferences.finder
    preferences.input
    preferences.keyboard
    preferences.misc
    preferences.safari
    preferences.software-update
    preferences.system
    preferences.ui

    security.pam
    security.firewall

    homebrew

    ./users.nix
  ];
}
