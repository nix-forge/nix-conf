{ pkgs, ... }:
let
  azureCli = pkgs.azure-cli.withExtensions [ pkgs.azure-cli.extensions.azure-devops ];
in
{
  # The extension is built and pinned with the CLI. Do not let `az extension`
  # download a second, mutable copy into the user profile.
  home.packages = [ azureCli ];
}
