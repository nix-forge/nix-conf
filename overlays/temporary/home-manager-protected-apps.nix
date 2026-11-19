{ lib, ... }: {
  reason = "copyApps mutates running signed bundles in place and cannot exclude independently transacted applications.";
  upstream = "https://github.com/nix-community/home-manager/blob/master/modules/targets/darwin/copyapps.nix";
  removal = "Home Manager supports exclusions for applications managed by a verified, running-app-aware transaction.";
  # copyapps.nix is byte-identical to the previous reviewed input (SHA-256
  # 870e0ccbcd8180776b5268f84608292c4b00c4d563cda28a6d46cc3dbb686e98).
  reviewedRevision = "2b13c9cb3aa20653e6f8ee0b7f8331a53ea9b0a9";
  inputPath = [ "home-manager" ];
  apply =
    upstream:
    let
      original = upstream + "/modules/targets/darwin/copyapps.nix";
      source = builtins.readFile original;
      needle = "              rsyncFlags=(\n                --recursive\n";
      occurrences = lib.length (lib.splitString needle source) - 1;
      patched = builtins.toFile "copyapps-protected.nix" (
        if occurrences != 1 then
          throw "Review Home Manager copyApps before applying protected exclusions"
        else
          builtins.replaceStrings
            [ needle ]
            [
              (
                needle
                + "                "
                + ''
                  ''${lib.concatMapStringsSep "\n                " (bundle: "--exclude=" + lib.escapeShellArg ("/" + bundle)) (
                    lib.optionals (config.macos.applications.enable && config.macos.applications.manageAll) [ "*.app" ]
                    ++ lib.optionals config.macos.applications.enable config.macos.applications.protectedBundles
                  )}
                ''
              )
            ]
            source
      );
    in
    {
      disabledModules = [ original ];
      imports = [ patched ];
    };
}
