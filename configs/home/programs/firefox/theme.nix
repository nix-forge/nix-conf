profileName:
{
  inputs,
  lib,
  self,
  ...
}:
{
  imports = [ self.homeManagerModules.firefox-userchrome ];

  programs.firefox = {
    # Using custom module for profile UserChrome apply Firefox UI Fix
    # TODO: remove custom module and manually apply using home.files
    userChrome.profiles.${profileName} = {
      source = inputs.firefox-ui-fix;
      recursive = true;
    };

    # Firefox UI Fix User JS
    profiles.${profileName}.extraConfig = lib.mkBefore (
      lib.strings.concatLines [ (builtins.readFile "${inputs.firefox-ui-fix}/user.js") ]
    );
  };
}
