{ lib, ... }: {
  reason = "copyApps mutates running signed bundles in place and cannot exclude independently transacted applications.";
  upstream = "https://github.com/nix-community/home-manager/blob/master/modules/targets/darwin/copyapps.nix";
  removal = "Home Manager supports exclusions for applications managed by a verified, running-app-aware transaction.";
  reviewedRevision = "6750249c69969d09d952efaf3fab88a2bdac7ec6";
  inputPath = [ "home-manager" ];
  apply =
    upstream:
    let
      original = upstream + "/modules/targets/darwin/copyapps.nix";
      source = builtins.readFile original;
      needle = "--recursive";
      patched = builtins.toFile "copyapps-protected.nix" (
        assert lib.assertMsg (lib.hasInfix needle source)
          "Review Home Manager copyApps before applying protected exclusions";
        builtins.replaceStrings
          [ needle ]
          [
            ''
              --recursive
              ''${lib.concatMapStringsSep "\n" (bundle: "--exclude=" + lib.escapeShellArg ("/" + bundle)) config.macos.applications.protectedBundles}
            ''
          ]
          source
      );
    in
    {
      disabledModules = [ original ];
      imports = [ patched ];
    };
}
