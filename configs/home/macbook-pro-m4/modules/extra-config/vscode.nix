{ config, self, ... }:
{
  programs.vscode.profiles.default.userSettings = {
    "remote.SSH.serverInstallPath" =
      let
        inherit (self.secrets.users.${config.home.username}) values;
      in
      {
        inherit (values.vscode."remote.SSH.serverInstallPath") "perlmutter.nersc.gov";
      };
    "remote.SSH.maxReconnectionAttempts" = 2;
    "remote.SSH.useFlock" = false;
  };
}
