{
  targets.darwin.defaults."com.apple.SoftwareUpdate" = {
    AutomaticCheckEnabled = true;
    ScheduleFrequency = 1;
    AutomaticDownload = 1;
    CriticalUpdateInstall = 1;
    AutomaticallyInstallMacOSUpdates = true;
  };
}
