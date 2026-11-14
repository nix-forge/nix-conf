{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  homeDirectory = config.home.homeDirectory;
  cfg = config.programs.t3code;
  desktopEnabled = cfg.enable && cfg.package != null;
  codexEnabled = config.programs.codex.enable && config.programs.codex.package != null;
  claudeEnabled = config.programs.claude-code.enable && config.programs.claude-code.package != null;
  opencodeEnabled = config.programs.opencode.enable && config.programs.opencode.package != null;
  codexHome = config.programs.chatgpt.codexHome;
  claudePackage = config.programs.claude-code.finalPackage;
  providerPackages =
    lib.optional codexEnabled config.programs.codex.package
    ++ lib.optional claudeEnabled claudePackage
    ++ lib.optionals opencodeEnabled (
      [ config.programs.opencode.package ] ++ config.programs.opencode.extraPackages
    );
  # Shared Electron needs the supported launcher hint for native URL registration.
  desktopLauncher = pkgs.writeShellScript "t3code-desktop-launcher" ''
    export T3CODE_DESKTOP_LAUNCHER_PATH="$0"
    exec ${lib.getExe cfg.package} "$@"
  '';
  # GUI-only metadata repairs must not restart an unchanged persistent backend.
  serverPackage = (cfg.package.serverPackage or cfg.package).override {
    # Resolve providers from the configured client packages below. The official
    # wrapper otherwise puts a different Codex ahead of the service PATH.
    enableCodex = false;
    enableClaude = false;
    enableOpencode = false;
  };
  command = [
    "${serverPackage}/bin/t3"
    "serve"
  ]
  ++ cfg.server.extraArgs;
  serverArgs = [
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
    XDG_CONFIG_HOME = config.xdg.configHome;
    XDG_DATA_HOME = config.xdg.dataHome;
    XDG_STATE_HOME = config.xdg.stateHome;
    XDG_CACHE_HOME = config.xdg.cacheHome;
    PATH = lib.concatStringsSep ":" [
      (lib.makeBinPath (
        providerPackages
        ++ [
          pkgs.git
          pkgs.openssh
        ]
      ))
      "${config.home.profileDirectory}/bin"
      "${homeDirectory}/.nix-profile/bin"
      "/etc/profiles/per-user/${config.home.username}/bin"
      "/run/current-system/sw/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];
  }
  // lib.optionalAttrs codexEnabled { CODEX_HOME = codexHome; }
  // lib.optionalAttrs claudeEnabled { CLAUDE_CONFIG_DIR = config.programs.claude-code.configDir; }
  // lib.optionalAttrs opencodeEnabled (
    lib.filterAttrs (
      name: _:
      lib.elem name [
        "OPENCODE_CONFIG"
        "OPENCODE_TUI_CONFIG"
      ]
    ) config.home.sessionVariables
  );
  launchdWrapper = (myLib.writers.writeBashTemplate { inherit pkgs; }) {
    name = "t3code-launchd-environment";
    src = ./scripts/t3code-launchd-environment.sh.in;
    replacements = {
      bash = lib.getExe pkgs.bash;
      environmentFile = lib.escapeShellArg (toString cfg.server.environmentFile);
      serverCommand = lib.escapeShellArgs command;
    };
  };
in
{
  programs.t3code = {
    enable = lib.mkDefault true;
    package = lib.mkDefault pkgs.t3code;
    server = {
      enable = lib.mkDefault true;
      extraArgs = lib.mkDefault serverArgs;
    };
    # Use the upstream mutable merger, preserving unrelated instances, secrets,
    # model choices and connection state. Explicit homePath also fixes Codex
    # continuation identity on T3 0.1.6, before ambient CODEX_HOME was supported.
    userSettings.providerInstances =
      lib.optionalAttrs codexEnabled {
        codex = {
          driver = "codex";
          config = {
            binaryPath = lib.getExe config.programs.codex.package;
            homePath = codexHome;
          };
        };
      }
      // lib.optionalAttrs claudeEnabled {
        claudeAgent = {
          driver = "claudeAgent";
          config.binaryPath = lib.getExe claudePackage;
        };
      }
      // lib.optionalAttrs opencodeEnabled {
        opencode = {
          driver = "opencode";
          config.binaryPath = lib.getExe config.programs.opencode.package;
        };
      };
  };

  home.activation.t3codePreview = lib.mkIf (desktopEnabled && pkgs.stdenv.hostPlatform.isDarwin) (
    lib.hm.dag.entryAfter [ "installPackages" ] ''
      nixProfileRemove t3code-preview
    ''
  );

  home.sessionVariables = lib.mkIf (desktopEnabled && pkgs.stdenv.hostPlatform.isLinux) {
    T3CODE_DESKTOP_LAUNCHER_PATH = "${desktopLauncher}";
  };

  xdg.desktopEntries.t3code = lib.mkIf (desktopEnabled && pkgs.stdenv.hostPlatform.isLinux) {
    name = "T3 Code";
    exec = "${desktopLauncher} %U";
    icon = "t3code";
    categories = [ "Development" ];
    mimeType = [ "x-scheme-handler/t3code" ];
    terminal = false;
    settings.StartupWMClass = "t3code";
  };

  xdg.mimeApps = lib.mkIf (desktopEnabled && pkgs.stdenv.hostPlatform.isLinux) {
    enable = true;
    defaultApplications."x-scheme-handler/t3code" = [ "t3code.desktop" ];
  };

  # The desktop's local environment must be disabled through its settings API
  # before activation. It connects to this server and the other host through
  # saved authenticated routes; the app owns their encrypted connection catalog.
  systemd.user.services.t3code =
    lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && cfg.enable && cfg.server.enable)
      {
        Unit = {
          X-SwitchMethod = "keep-old";
          StartLimitIntervalSec = 300;
          StartLimitBurst = 5;
        };
        Service = {
          ExecStart = lib.mkForce (lib.escapeShellArgs command);
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") environment;
          WorkingDirectory = homeDirectory;
          TimeoutStopSec = 90;
          # Upstream reserves 78 for a data directory already owned by a server.
          RestartPreventExitStatus = [ 78 ];
          UMask = "0077";
        };
      };

  launchd.agents.t3code =
    lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && cfg.enable && cfg.server.enable)
      {
        config = {
          Label = "com.t3tools.t3code.service";
          ProgramArguments = lib.mkForce (
            if cfg.server.environmentFile == null then command else [ (lib.getExe launchdWrapper) ]
          );
          EnvironmentVariables = environment;
          WorkingDirectory = homeDirectory;
          ThrottleInterval = 5;
          ExitTimeOut = 90;
          ProcessType = lib.mkForce "Interactive";
          Umask = 63;
          StandardOutPath = "${homeDirectory}/Library/Logs/t3code-server.log";
          StandardErrorPath = "${homeDirectory}/Library/Logs/t3code-server.log";
        };
      };
}
