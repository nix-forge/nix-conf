{ pkgs, ... }: {
  home.packages = [
    # pkgs.bitwarden-desktop # issues with electron eol
    pkgs.bitwarden-cli
  ];
}
