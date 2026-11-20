{ pkgs, ... }: {
  home.packages = with pkgs; [
    file
    unzip
    zip
    xxd
  ];
}
