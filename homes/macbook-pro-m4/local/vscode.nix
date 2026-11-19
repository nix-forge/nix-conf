_: {
  programs.vscode.rust.denyWarnings = true;

  programs.vscode.profiles.default.userSettings = {
    "remote.SSH.serverInstallPath" = {
      "perlmutter.nersc.gov" = "/pscratch/sd/i/imh39";
      "perlmutter-agent" = "/pscratch/sd/i/imh39";
    };
    # Avoid discovery writing the peer platform into immutable user settings.
    "remote.SSH.remotePlatform".desktop = "linux";
    "remote.SSH.maxReconnectionAttempts" = 2;
    "remote.SSH.useFlock" = false;
  };
}
