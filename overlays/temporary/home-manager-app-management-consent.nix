{ lib, ... }: {
  reason = "Activation resets App Management consent automatically instead of failing for a native user decision.";
  upstream = "https://github.com/nix-community/home-manager/blob/6750249c69969d09d952efaf3fab88a2bdac7ec6/modules/targets/darwin/copyapps.nix";
  removal = "Upstream App Management checks retain permission failures without resetting TCC and report the required native consent.";
  reviewedRevision = "6750249c69969d09d952efaf3fab88a2bdac7ec6";
  inputPath = [ "home-manager" ];
  apply =
    value:
    let
      original = value.upstream + "/modules/targets/darwin/copyapps.nix";
      source = builtins.readFile (builtins.head value.replacement.imports);
      resetBlock = "                # The TCC service required to modify notarised app bundles is `kTCCServiceSystemPolicyAppBundles`\n                # and we can reset it to ensure the user gets another prompt\n                run /usr/bin/tccutil reset SystemPolicyAppBundles > /dev/null\n";
      consentMessage = "                  printf >&2 'home-manager requires permission to update your apps, please accept the notification\\n'\n                  printf >&2 'and grant the permission for your terminal emulator in System Settings.\\n'\n";
      patched = builtins.toFile "home-manager-app-management-consent.nix" (
        assert lib.assertMsg (
          builtins.hashString "sha256" (builtins.readFile original)
          == "870e0ccbcd8180776b5268f84608292c4b00c4d563cda28a6d46cc3dbb686e98"
        ) "Review the exact upstream App Management module before applying the consent repair";
        assert lib.assertMsg (
          value.replacement.disabledModules == [ original ]
          && builtins.length value.replacement.imports == 1
          && lib.hasInfix "config.macos.applications.protectedBundles" source
        ) "Compose the consent repair with the single protected-copy module replacement";
        assert lib.assertMsg (
          builtins.length (lib.splitString resetBlock source) == 2
        ) "Expected exactly one upstream automatic TCC reset block";
        assert lib.assertMsg (
          builtins.length (lib.splitString consentMessage source) == 2
        ) "Expected exactly one upstream App Management consent message";
        builtins.replaceStrings
          [ resetBlock consentMessage ]
          [
            "                # App Management consent is user-owned; activation never resets TCC.\n"
            "                  printf >&2 'home-manager could not update your apps; App Management permissions were left unchanged.\\n'\n                  printf >&2 'In System Settings > Privacy & Security > App Management, grant access to the terminal running this command, then rerun it.\\n'\n"
          ]
          source
      );
    in
    value.replacement // { imports = [ patched ]; };
}
