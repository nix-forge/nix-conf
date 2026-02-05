{
  system.defaults = {
    finder = {
      # Change default view style to list view
      FXPreferredViewStyle = "Nlsv";

      # Search current folder by default
      FXDefaultSearchScope = "SCcf";

      # Remove trash items after 30 days
      FXRemoveOldTrashItems = true;

      # Show all filename extensions
      AppleShowAllExtensions = true;

      # Show status bar
      ShowStatusBar = true;

      # Show path bar
      ShowPathbar = true;

      # Show full path in finder title
      _FXShowPosixPathInTitle = true;

      # Show hidden files
      AppleShowAllFiles = true;

      # Disable warning when changing file extension
      FXEnableExtensionChangeWarning = false;

      # Allow quitting Finder via ⌘ + Q (also hides desktop icons)
      QuitMenuItem = true;

      # Disable icons on the desktop
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

      # Automatically open a new Finder window when a volume is mounted
      OpenWindowForNewRemovableDisk = true;

      # Allow text selection in Quick Look
      QLEnableTextSelection = true;

      # Disable the warning before emptying the Trash
      WarnOnEmptyTrash = false;

    };
  };
}
