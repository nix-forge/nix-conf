{ lib, pkgs, ... }: {
  reason = "OpenCode 2.2.5 pins one Bun dependency hash despite different normalized outputs on Linux and Darwin.";
  upstream = "https://github.com/NixOS/nixpkgs/commit/c399e1b7fb90789e3e032784ef8ad98ba9907169";
  removal = "The selected upstream recipe includes the platform-specific dependency hashes and passes native version and configuration-schema checks without this backport.";
  reviewedRevision = "1d060086d60cb76a40cf37109f979d88a5bd6396";
  inputPath = [ "nixpkgs" ];
  packageName = "opencode";
  affectedVersions = {
    from = "2.2.5";
    until = "2.2.6";
  };
  apply =
    package:
    assert lib.assertMsg (
      (package.src.hash or package.src.outputHash or null)
      == "sha256-/a1czcXi12KWPXcESqplNdOZcjEs8gWCMO7w4nQYLkw="
      && package.node_modules.outputHash == "sha256-xfOVcw1+waLVNhFDwzOtzxrUSQEogvn88YomydOlhwc="
    ) "opencode-dependency-hashes: upstream source or dependency recipe changed; review the backport";
    package.overrideAttrs (old: {
      node_modules = old.node_modules.overrideAttrs {
        outputHash =
          if pkgs.stdenv.hostPlatform.isLinux then
            "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA="
          else if pkgs.stdenv.hostPlatform.isDarwin then
            "sha256-dIveiaiPFGSItwLyeMuPDxTE9gpvvnlTCB/+nG24qCc="
          else
            throw "opencode-dependency-hashes: unsupported platform";
      };
    });
}
