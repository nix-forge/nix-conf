profileName:
{
  ...
}:
{
  imports = [
    ./blocking.nix
    ./policies.nix
    (import ./extensions.nix profileName)
    (import ./user-js.nix profileName)
    (import ./search.nix profileName)
    (import ./theme.nix profileName)
  ];

  programs.firefox = {
    enable = true;

    # Set the language packs for firefox (be careful as unique configs can lead to fingerprinting)
    languagePacks = [ "en-US" ];

    profiles.${profileName} = {
      id = 0;
      isDefault = true;
      name = profileName;
    };
  };
}
