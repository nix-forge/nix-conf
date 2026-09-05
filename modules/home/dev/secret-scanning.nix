{ pkgs, ... }: {
  home.packages = with pkgs; [
    gitleaks
    trufflehog
  ];
}
