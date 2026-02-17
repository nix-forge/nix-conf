{
  imports = [
    ./blocking.nix
    ./extensions.nix
    ./language.nix
    ./policies.nix
    ./search.nix
    ./theme.nix
    ./user-js.nix
  ];

  programs.firefox = {
    enable = true;

    # Set the language packs for firefox (be careful as unique configs can lead to fingerprinting)
    languagePacks = [ "en-US" ];

    profiles.default = {
      id = 0;
      isDefault = true;
      name = "default";
    };
  };
}
