{
  config,
  lib,
  pkgs,
  myLib,
  osConfig,
  options,
  ...
}:
let
  state = "${config.xdg.stateHome}/google-drive";
  mount = "${config.home.homeDirectory}/Google Drive";
  password = config.nixSeal.secrets.google-drive-config-password.path;
  client = config.nixSeal.secrets.google-drive-oauth-client.path;
  policy = pkgs.writeText "google-drive-policy.json" (
    builtins.toJSON {
      stateDirectory = state;
      mountDirectory = mount;
      passwordFile = password;
      clientFile = client;
      runtimeDirectory = config.nixSeal.runtimeDirectory;
      rclone = lib.getExe pkgs.rclone;
      cat = lib.getExe' pkgs.coreutils "cat";
      systemctl = lib.getExe' pkgs.systemd "systemctl";
      notify = lib.getExe' pkgs.libnotify "notify-send";
    }
  );
  helper = pkgs.writers.writePython3Bin "google-drive-runtime" {
    libraries = [ (myLib.python.notificationProcess { inherit pkgs; }) ];
    flakeIgnore = [ "E501" ];
  } ./google_drive.py;
  command = pkgs.writeShellApplication {
    name = "google-drive";
    text = (import ../../../../lib/templates/text.nix) ./scripts/google-drive.sh {
      lib_getExe_helper = lib.getExe helper;
      inherit policy;
    };
  };
in
{
  assertions = [
    {
      assertion = osConfig.hardware.storage.encryptedRoot.enable;
      message = "Google Drive's plaintext VFS cache requires the desktop's encrypted storage.";
    }
    {
      assertion = config.nixSeal.runtimeStorage == "volatile-tmpfs-noswap";
      message = "Google Drive OAuth setup requires nix-seal's protected volatile runtime.";
    }
  ];

  nixSeal.secrets = [
    {
      google-drive-config-password.source = "homes/desktop/local/secrets/google-drive-config-password.age";
    }
    { google-drive-oauth-client.source = "homes/desktop/local/secrets/google-drive-oauth-client.age"; }
  ];

  home.packages = [
    pkgs.rclone
    command
  ];
  xdg.desktopEntries.google-drive-web = {
    name = "Google Drive on the web";
    comment = "Edit Google Docs, Sheets and Slides in the browser";
    exec = "${lib.getExe' pkgs.xdg-utils "xdg-open"} https://drive.google.com/";
    icon = "folder-remote";
    categories = [
      "Network"
      "Office"
    ];
    terminal = false;
  };
  home.activation.googleDriveDirectories = lib.hm.dag.entryBefore [ "syncDirectoryBookmarks" ] ''
    run ${lib.getExe command} init
  '';
  # The default bookmark list is an option default, so retain it explicitly.
  xdg.directoryBookmarks.entries = options.xdg.directoryBookmarks.entries.default ++ [
    {
      path = mount;
      label = "Google Drive";
    }
  ];

  systemd.user.services.google-drive = {
    Unit = {
      Description = "Google Drive cached filesystem";
      Documentation = [ "https://rclone.org/drive/" ];
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
      ConditionPathExists = [
        "${state}/rclone.conf"
        password
      ];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = "${lib.getExe command} mount";
      ExecStopPost = "${lib.getExe command} stopped";
      Restart = "on-failure";
      RestartSec = 30;
      TimeoutStartSec = 120;
      TimeoutStopSec = 120;
      KillSignal = "SIGTERM";
      KillMode = "mixed";
      UMask = "0077";
      LimitCORE = 0;
      # The FUSE helper needs its setuid wrapper; NoNewPrivileges and private
      # mount namespaces would prevent mounting in the desktop user's session.
      Environment = [ "PATH=/run/wrappers/bin:${lib.makeBinPath [ pkgs.fuse3 ]}" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
