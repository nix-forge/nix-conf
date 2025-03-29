{ pkgs, ... }:
{
  home.packages = [ pkgs.nushell ];

  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      #
      thenuprojectcontributors.vscode-nushell-lang
    ];
}
