{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDirectory = config.home.homeDirectory;
  # Shared Electron needs the supported launcher hint for native URL registration.
  desktopLauncher = pkgs.writeShellScript "t3code-desktop-launcher" ''
    export T3CODE_DESKTOP_LAUNCHER_PATH="$0"
    exec ${lib.getExe pkgs.t3code} "$@"
  '';
  # GUI-only metadata repairs must not restart an unchanged persistent backend.
  serverPackage = pkgs.t3code.serverPackage or pkgs.t3code;
  command = [
    "${serverPackage}/bin/t3"
    "serve"
    "--host"
    "127.0.0.1"
    "--port"
    "3773"
    "--base-dir"
    "${homeDirectory}/.t3"
  ];
  # Providers belong to the environment's host, including user-selected CLIs.
  # Neither launchd nor the systemd user manager runs a login shell for us.
  environment = {
    HOME = homeDirectory;
    PATH = lib.concatStringsSep ":" [
      (lib.makeBinPath [
        pkgs.git
        pkgs.openssh
      ])
      "${config.home.profileDirectory}/bin"
      "${homeDirectory}/.nix-profile/bin"
      "/etc/profiles/per-user/${config.home.username}/bin"
      "/run/current-system/sw/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];
  };
in
{
  home.packages = [ pkgs.t3code ];

  home.activation.t3codePreview = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
    lib.hm.dag.entryAfter [ "installPackages" ] ''
      nixProfileRemove t3code-preview
    ''
  );

  home.sessionVariables = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    T3CODE_DESKTOP_LAUNCHER_PATH = "${desktopLauncher}";
  };

  xdg.desktopEntries.t3code = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    name = "T3 Code";
    exec = "${desktopLauncher} %U";
    icon = "t3code";
    categories = [ "Development" ];
    mimeType = [ "x-scheme-handler/t3code" ];
    terminal = false;
    settings.StartupWMClass = "t3code";
  };

  xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    defaultApplications."x-scheme-handler/t3code" = [ "t3code.desktop" ];
  };

  # The desktop's local environment must be disabled through its settings API
  # before activation. It connects to this server and the other host through
  # saved authenticated routes; the app owns their encrypted connection catalog.
  systemd.user.services.t3code = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit = {
      Description = "T3 Code persistent local environment";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      ExecStart = lib.escapeShellArgs command;
      Environment = lib.mapAttrsToList (name: value: "${name}=${value}") environment;
      WorkingDirectory = homeDirectory;
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 90;
      # Upstream reserves 78 for a data directory already owned by a server.
      RestartPreventExitStatus = [ 78 ];
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };

  launchd.agents.t3code = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      Label = "com.t3tools.t3code.service";
      ProgramArguments = command;
      EnvironmentVariables = environment;
      WorkingDirectory = homeDirectory;
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 5;
      ExitTimeOut = 90;
      ProcessType = "Interactive";
      Umask = 63;
      StandardOutPath = "${homeDirectory}/Library/Logs/t3code-server.log";
      StandardErrorPath = "${homeDirectory}/Library/Logs/t3code-server.log";
    };
  };
}
