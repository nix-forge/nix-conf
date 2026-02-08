{
  programs.vscode.profiles.default.userSettings = {
    "remote.SSH.serverInstallPath" = {
      "perlmutter.nersc.gov" = "$SCRATCH";
    };
    "remote.SSH.maxReconnectionAttempts" = 2;
    "remote.SSH.useFlock" = false;
  };
}
