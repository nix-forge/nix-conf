{ config, pkgs, ... }: {
  home.packages = with pkgs; [
    bun
    nodejs

    oxlint
    oxfmt

    playwright-test
  ];

  home.sessionVariables = {
    # Keep browser binaries writable so each project can install the exact
    # Playwright revision pinned by its lockfile.
    PLAYWRIGHT_BROWSERS_PATH = "${config.xdg.cacheHome}/ms-playwright";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
  };
}
