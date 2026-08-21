{
  # This profile intentionally installs app bundles as copies in the stable
  # user Applications directory (needed by LinearMouse and LaunchServices).
  # Home Manager's newer link-app default conflicts with that strategy.
  targets.darwin = {
    copyApps.enable = true;
    linkApps.enable = false;
  };
}
