_: {
  reason = "Claude Code install checks request an unsandboxed Darwin build.";
  upstream = "https://github.com/NixOS/nixpkgs/tree/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/by-name/cl/claude-code";
  removal = "The unmodified Darwin derivation builds under the strict sandbox.";
  reviewedRevision = "0968519e14f7aa7d3e9b389682bd74d2b51c8ce8";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (_: {
      __noChroot = false;
      doInstallCheck = false;
    });
}
