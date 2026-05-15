{ pkgs, ... }:
let
  claudeCode =
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.claude-code.overrideAttrs (_: {
        __noChroot = false;
        doInstallCheck = false;
      })
    else
      pkgs.claude-code;
in
{
  home.packages = [ claudeCode ];
}
