{
  system.defaults = {
    NSGlobalDomain = {
      # Show all filename extensions
      AppleShowAllExtensions = true;
    };

    finder = {
      # Change default view style to list view
      FXPreferredViewStyle = "Nlsv";

      # Search current folder by default
      FXDefaultSearchScope = "SCcf";

      # Remove trash items after 30 days
      FXRemoveOldTrashItems = true;

      # Show status bar
      ShowStatusBar = true;

      # Show path bar
      ShowPathbar = true;

      # show full path in finder title
      _FXShowPosixPathInTitle = true;

      # show hidden files
      AppleShowAllFiles = true;

      # disable warning when changing file extension
      FXEnableExtensionChangeWarning = false;

      # hide the quit button on finder
      QuitMenuItem = true;

      # disable icons on the desktop
      CreateDesktop = false;
    };

    CustomUserPreferences."com.apple.finder" = {
      SidebarDevicesSectionDisclosedState = true;
      SidebarPlacesSectionDisclosedState = true;
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = true;
      ShowMountedServersOnDesktop = true;
      ShowRemovableMediaOnDesktop = true;
      _FXSortFoldersFirst = true;
    };
  };
}
