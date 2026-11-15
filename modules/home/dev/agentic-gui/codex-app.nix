{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.programs.chatgpt;
  supported = lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.chatgpt;
  inherit (cfg) package;
  darwinCommand = package.meta.mainProgram or "chatgpt";
  bundle = cfg.darwinBundle;
in
{
  imports = [
    ../../macos/application-capabilities.nix
    ./codex/settings.nix
    ../../macos/applications.nix
  ];

  options.programs.chatgpt = {
    darwinBundle = lib.mkOption {
      type = lib.types.strMatching "[^/]+\\.app";
      default = "ChatGPT.app";
      description = "Stable canonical bundle directory name; vendor bundle contents and signatures are preserved.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.chatgpt;
      description = "Desktop package, including its launcher and desktop entry.";
    };
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.jq pkgs.ripgrep ]";
      description = ''
        Optional task tools installed alongside ChatGPT. Prefer project shells
        for project dependencies. Required sandbox and desktop helpers belong
        to the upstream package.
      '';
    };
  };

  config = lib.mkIf supported {
    macos.applicationCapabilities.apps.codex = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = lib.mkDefault supported;
      inherit bundle;
      bundleId = "com.openai.codex";
      teamId = "2DC432GLL2";
      features = {
        localServices = {
          enable = lib.mkDefault true;
          service = "local-network";
          reason = "Reach LAN services from GUI-origin tasks";
          source = "https://learn.chatgpt.com/docs/computer-use";
          instruction = "Run a bounded connection to the selected local service through the GUI command runner; an SSH-origin success is insufficient.";
        };
      };
    };

    macos.applications.protectedApps.codex = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      inherit bundle;
      bundleId = "com.openai.codex";
      teamId = "2DC432GLL2";
      source = "${package}/Applications/ChatGPT.app";
      previousBundles = lib.optional (bundle != "ChatGPT.app") "ChatGPT.app";
    };

    # Match the upstream spelling so buildEnv priorities also work on a
    # case-insensitive Nix volume; keep the conventional lowercase command.
    macos.applications.commands.${darwinCommand} = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      inherit bundle;
      aliases = lib.optional (darwinCommand != "chatgpt") "chatgpt";
    };
    programs.chatgpt.settings.desktop.git-worktree-root = lib.mkIf (config.programs.dev-worktree.enable
      or false
    ) (lib.mkDefault "${config.programs.dev-worktree.worktreeRoot}/codex");

    home.packages = [ package ] ++ cfg.extraPackages;

    programs.chatgpt.settings.shell_environment_policy.set.CODEX_DESKTOP_APP_PATH =
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/${bundle}";

    xdg.dataFile."applications/chatgpt.desktop" = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      # Replace old user-local launchers with the entry shipped by this package.
      source = "${package}/share/applications/chatgpt.desktop";
      force = true;
    };
  };
}
