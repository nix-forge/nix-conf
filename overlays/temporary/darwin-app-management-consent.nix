{ lib, ... }: {
  reason = "Activation resets App Management consent automatically instead of failing for a native user decision.";
  upstream = "https://github.com/nix-darwin/nix-darwin/blob/bb0b90dbd54e207100de72b5dcbe3188c98a4b69/modules/system/applications.nix";
  removal = "Upstream App Management checks retain permission failures without resetting TCC and report the required native consent.";
  reviewedRevision = "ff0e21a414d4547183396da1b44a66f2577b65e9";
  inputPath = [ "nix-darwin" ];
  apply =
    upstream:
    let
      original = upstream + "/modules/system/applications.nix";
      source = builtins.readFile original;
      resetBlock = "          # The TCC service required to modify notarised app bundles is `kTCCServiceSystemPolicyAppBundles`\n          # and we can reset it to ensure the user gets another prompt\n          tccutil reset SystemPolicyAppBundles > /dev/null\n";
      consentMessage = "            printf >&2 '`darwin-rebuild` requires permission to update your apps, please accept the notification\\n'\n            printf >&2 'and grant the permission for your terminal emulator in System Settings.\\n'\n";
      patched = builtins.toFile "darwin-app-management-consent.nix" (
        assert lib.assertMsg (
          builtins.hashString "sha256" (builtins.readFile original)
          == "89d23112a2a2ed3a29137d1aefc5ad8f81de2942bbbe91faf66c24792d7b5b6e"
        ) "Review the exact upstream App Management module before applying the consent repair";

        assert lib.assertMsg (
          builtins.length (lib.splitString resetBlock source) == 2
        ) "Expected exactly one upstream automatic TCC reset block";
        assert lib.assertMsg (
          builtins.length (lib.splitString consentMessage source) == 2
        ) "Expected exactly one upstream App Management consent message";
        builtins.replaceStrings
          [ resetBlock consentMessage ]
          [
            "          # App Management consent is user-owned; activation never resets TCC.\n"
            "            printf >&2 '`darwin-rebuild` could not update your apps; App Management permissions were left unchanged.\\n'\n            printf >&2 'In System Settings > Privacy & Security > App Management, grant access to the terminal running this command, then rerun it.\\n'\n"
          ]
          source
      );
    in
    {
      disabledModules = [ original ];
      imports = [ patched ];
    };
}
