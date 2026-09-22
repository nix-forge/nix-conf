{ lib, ... }: {
  reason = "Privileged nh commands set an empty HOME on Darwin, creating Nix's cache in the working directory.";
  upstream = "https://github.com/nix-community/nh/pull/758";
  removal = "The pinned nh source sets an absolute root-owned HOME for elevated Darwin commands.";
  reviewedRevision = "44a91898084f46797b5fac650c7e8c9ac38c43d4";
  inputPath = [ "nixpkgs" ];
  packageName = "nh-unwrapped";
  # 4.4.2 is the latest reviewed release without PR #758. The next release
  # number is not yet announced; newer versions use the upstream package.
  appliesTo = package: !(lib.versionOlder "4.4.2" package.version);
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/nh-darwin-home.patch ];
    });
}
