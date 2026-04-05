{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bun

    playwright-driver
  ];

  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = pkgs.playwright.browsers;
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = 1;
  };
}
