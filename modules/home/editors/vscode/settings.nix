profileName:
{
  lib,
  pkgs,
  config,
  ...
}@args:
let
  extensions = pkgs.callPackage ./marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions =
      with extensions.release;
      [
        ## Appearances ##
        pkief.material-icon-theme
        extensions.release.vira.vsc-vira-theme

        ## Intelligence ##
        usernamehw.errorlens
        christian-kohler.path-intellisense
        streetsidesoftware.code-spell-checker

        ## Version Control ##
        github.vscode-github-actions
        mhutchie.git-graph

        ## Collaboration Features
        ms-vsliveshare.vsliveshare

        ## Editor Extension ##
        sleistner.vscode-fileutils
        aaron-bond.better-comments
        kevinkyang.auto-comment-blocks

        ## Base Language Support ##
        redhat.vscode-yaml
        tamasfe.even-better-toml
        mechatroner.rainbow-csv
        janisdd.vscode-edit-csv
        tomoki1207.pdf
        nefrob.vscode-just-syntax

        # Extra
        ms-vscode-remote.remote-ssh
      ]
      # Direnv integration
      ++ lib.optionals config.programs.direnv.enable [ mkhl.direnv ];

    userSettings =
      let
        os = if pkgs.stdenv.hostPlatform.isLinux then "linux" else "osx";
      in
      lib.mkMerge [
        {
          ## Appearances ##
          "editor.cursorSmoothCaretAnimation" = "explicit";
          "editor.cursorStyle" = "block";
          "editor.cursorBlinking" = "smooth";
          "editor.fontLigatures" =
            "'calt', 'liga', 'ss01', 'ss02', 'ss03', 'ss04', 'ss05', 'ss06', 'ss07', 'ss08', 'ss09', 'ss10'";
          "terminal.integrated.fontLigatures.enabled" = true;
          "editor.fontVariations" = true;

          # popups are really annoying
          "editor.hover.delay" = 700;

          # colors
          "workbench.colorTheme" = lib.mkForce "Vira Carbon High Contrast";
          # icons
          "workbench.iconTheme" = "vira-icons-carbon";
          # "workbench.productIconTheme" = "viraUIIcons";

          # title
          "window.titleSeparator" = " - ";
          "window.title" = lib.concatMapStrings (s: "\${${s}}") [
            "rootName"
            "separator"
            "activeEditorMedium"
            "separator"
            "appName"
          ];

          # Set the window tile bar to use VScode custom title bar
          "window.titleBarStyle" = "custom";
          # hide the menu bar unless alt is pressed
          # "window.menuBarVisibility" = "toggle";
          # the minimap gets in the way
          "editor.minimap.enabled" = false;
          # scroll with an animation
          "editor.smoothScrolling" = true;
          "workbench.list.smoothScrolling" = true;
          "terminal.integrated.smoothScrolling" = true;
          # blink the cursor in terminal
          "terminal.integrated.cursorBlinking" = true;
          # line style cursor in terminal
          "terminal.integrated.cursorStyle" = "line";
          # fix fuzzy text in integrated terminal
          "terminal.integrated.gpuAcceleration" = "on";
          # Add editor inline suggestions
          "editor.inlineSuggest.enabled" = true;

          # top is the smallest other than hidden
          "workbench.activityBar.location" = "top";
          # put the sidebar on the right so that text doesn't jump
          "workbench.sideBar.location" = "right";
          # no delay when automatically hiding the sidebar or panels

          # show vcs changes and staged changes as a tree
          "scm.defaultViewMode" = "tree";

          ## Saving and Formatting ##

          # auto-save when the active editor loses focus
          "files.autoSave" = "onFocusChange";
          # format pasted code if the formatter supports a range
          "editor.formatOnPaste" = true;
          # if the plugin supports range formatting always use that
          "editor.formatOnSaveMode" = "modificationsIfAvailable";
          # Highlight bad ASCII characters
          "editor.unicodeHighlight.nonBasicASCII" = true;
          # insert a newline at the end of a file when saved
          "files.insertFinalNewline" = true;
          # trim whitespace trailing at the ends of lines on save
          "files.trimTrailingWhitespace" = true;
          # enable semantic highlighting
          "editor.semanticHighlighting.enabled" = true;

          "[yaml]" = {
            "editor.tabSize" = 2;
            "editor.defaultFormatter" = "redhat.vscode-yaml";
          };
          "yaml.format.printWidth" = 80;
          "yaml.format.proseWrap" = "always";
          "[json]" = {
            "editor.tabSize" = 2;
            "editor.defaultFormatter" = "vscode.json-language-features";
          };
          "[jsonc]" = {
            "editor.tabSize" = 2;
            "editor.defaultFormatter" = "vscode.json-language-features";
          };
          "[github-actions-workflow]" = {
            "editor.defaultFormatter" = "redhat.vscode-yaml";
          };
          "[toml]" = {
            "editor.tabSize" = 2;
            "editor.defaultFormatter" = "tamasfe.even-better-toml";
          };
          "evenBetterToml.formatter.allowedBlankLines" = 2;
          "evenBetterToml.formatter.columnWidth" = 80;
          "evenBetterToml.taplo.bundled" = false;
          "evenBetterToml.taplo.path" = lib.getExe pkgs.taplo;

          ## VCS Behavior ##
          "git.rebaseWhenSync" = config.programs.git.settings.pull.rebase;
          "git.pruneOnFetch" = config.programs.git.settings.fetch.prune;
          "git.enableSmartCommit" = false;
          "git.terminalAuthentication" = false;
          "git.openRepositoryInParentFolders" = "always";
          "git.autofetch" = true;
          "git.confirmSync" = false;
          "git.enableCommitSigning" = lib.mkIf (
            config.programs.git.enable && config.programs.git.signing.signByDefault
          ) true;
          "githubIssues.issueCompletions.enabled" = false;

          # prevent pollute history with whitespace changes
          "diffEditor.ignoreTrimWhitespace" = false;
          "diffEditor.renderSideBySide" = false;

          ## Navigation Behavior ##

          # scrolling in tab bar switches
          "workbench.editor.scrollToSwitchTabs" = true;
          # name of current scope sticks to top of editor pane
          "editor.stickyScroll.enabled" = true;
          # larger indent
          "workbench.tree.indent" = 16;

          ## Intelligence Features ##

          # show the errors shortly after saving
          "errorLens.onSaveTimeout" = 200;
          # space between EOL and error
          "errorLens.margin" = "1em";
          # do not show error messages on lines in merge conflict blocks
          "errorLens.enabledInMergeConflict" = false;
          # diagnostic levels to show, removed "info"
          "errorLens.enabledDiagnosticLevels" = [
            "error"
            "warning"
          ];
          # slower updates but less buggy
          "errorLens.delayMode" = "debounce";

          ## Miscellaneous ##

          # disable automatic update checking
          "update.mode" = "none";
          # don't re-open everything on start
          "window.restoreWindows" = "none";
          # don't show the welcome page
          "workbench.startupEditor" = "none";
          # unsaved files will be "untitled"
          "workbench.editor.untitled.labelFormat" = "name";
          # default hard and soft rulers
          "editor.rulers" = [
            80
            120
          ];
          # files can be recovered with undo
          "explorer.confirmDelete" = false;
          # remove recommendations for extensions
          "extensions.ignoreRecommendations" = true;
          # remove popup out moving files
          "explorer.confirmDragAndDrop" = false;

          # spell checker settings
          "cSpell.ignorePaths" = [
            "node_modules" # this will ignore anything the node_modules directory
            "**/node_modules" # the same for this one
            "**/node_modules/**" # the same for this one
            "node_modules/**" # Doesn't currently work due to how the current working directory is determined.
            "vscode-extension"
            ".git" # Ignore the .git directory
            "*.dll" # Ignore all .dll files.
            "**/*.dll" # Ignore all .dll files
          ];

          # SSH settings
          "remote.SSH.maxReconnectionAttempts" = 2;
          "remote.SSH.useFlock" = false;

          # remove telemetry
          "redhat.telemetry.enabled" = false;
          "telemetry.enableTelemetry" = false;
          "telemetry.feedback.enabled" = false;
          "telemetry.telemetryLevel" = "off";
          "terminal.integrated.localEchoEnabled" = "off";
        }

        # Terminal profiles (Copilot and integrated terminal)
        { "terminal.integrated.shellIntegration.enabled" = true; }
        (lib.mkIf (lib.hasAttr "SHELL" config.home.sessionVariables) (
          let
            shellPath = config.home.sessionVariables.SHELL;
            shellName = lib.last (lib.splitString "/" shellPath);

            # Define shell configurations for enabled shells
            shellConfigs = {
              bash = lib.mkIf config.programs.bash.enable {
                path = lib.getExe' pkgs.bashInteractive "bash";
                icon = "terminal-bash";
              };
              zsh = lib.mkIf config.programs.zsh.enable { path = lib.getExe' pkgs.zsh "zsh"; };
              fish = lib.mkIf config.programs.fish.enable { path = lib.getExe' pkgs.fish "fish"; };
              nu = lib.mkIf config.programs.nushell.enable {
                path = lib.getExe' pkgs.nushell "nu";
                icon = "chevron-right";
              };
            };

            # Filter to only enabled shells and remove mkIf markers
            enabledShells = lib.filterAttrs (_: v: v != { }) shellConfigs;
          in
          {
            # Define terminal profiles for all enabled shells
            "terminal.integrated.profiles.${os}" = lib.mapAttrs (
              _shellName: shellConfig:
              (
                shellConfig
                // {
                  overrideName = true;
                  args = [
                    "--login"
                    "-i"
                  ];
                }
              )
            ) enabledShells;

            # set the integrated terminal to use SHELL so make sure SHELL is set correctly
            "terminal.integrated.defaultProfile.${os}" = shellName;

            # set the default shell for automation tasks to a fully POSIX compliant shell
            "terminal.integrated.automationProfile.${os}" = {
              path = lib.getExe' pkgs.bashInteractive "sh";
              args = [
                "--login"
                "-i"
              ];
            };
          }
        ))
        {
          "chat.tools.terminal.terminalProfile.${os}" = {
            path = lib.getExe' pkgs.bashInteractive "bash";
            args = [
              "--login"
              "-i"
            ];
          };
        }

        # Direnv settings
        (lib.mkIf config.programs.direnv.enable {
          "direnv.path.executable" = lib.getExe config.programs.direnv.package;
        })

      ];
  };
}
