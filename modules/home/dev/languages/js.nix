{ pkgs, ... }: {
  home.packages = with pkgs; [
    bun
    nodejs

    oxlint
    oxfmt

    playwright-test
    playwright-driver.browsers
  ];

  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = 1;
  };
}
