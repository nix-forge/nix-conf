{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
{
  imports = [
    ./copilot.nix
    (import ./keybinds.nix "default")
  ];

  home.packages = [
    pkgs.nerd-fonts.monaspace
  ];

  programs.vscode = {
    enable = true;
    profiles.default.enableExtensionUpdateCheck = false;
    profiles.default.enableUpdateCheck = false;
    mutableExtensionsDir = false;

    profiles.default.extensions =
      let
        extensions = pkgs.callPackage ./marketplace.nix { inherit inputs; };
      in
      (with extensions.preferPreRelease; [
        ## Appearances ##
        bottledlactose.darkbox
        pkief.material-icon-theme

        ## Intelligence ##
        usernamehw.errorlens
        christian-kohler.path-intellisense
        streetsidesoftware.code-spell-checker

        ## Version Control ##
        # huizhou.githd
        # mhutchie.git-graph
        # phil294.git-log--graph
        github.vscode-github-actions

        ## Collaboration Features
        ms-vsliveshare.vsliveshare

        ## Editor Extension ##
        sleistner.vscode-fileutils
        aaron-bond.better-comments
        kevinkyang.auto-comment-blocks
        esbenp.prettier-vscode

        # Environment
        mkhl.direnv

        ## Basic Config Languages ##
        kdl-org.kdl
        redhat.vscode-yaml
        tamasfe.even-better-toml
        mechatroner.rainbow-csv
        janisdd.vscode-edit-csv
        tomoki1207.pdf

        # Extra
        ms-vscode-remote.remote-ssh
      ]);

    profiles.default.userSettings = lib.mkMerge [
      {
        ## Appearances ##

        "editor.fontFamily" = lib.mkForce (
          lib.concatMapStringsSep ", " (s: "'${s}'") [
            "Material Design Icons"
            "MonaspiceNe Nerd Font"
          ]
        );
        "editor.cursorSmoothCaretAnimation" = "explicit";
        "editor.cursorStyle" = "block";
        "editor.cursorBlinking" = "smooth";
        "editor.fontLigatures" = true;
        "editor.fontVariations" = true;

        # for some reason it is not the same as the editor
        "terminal.integrated.lineHeight" = 1.4;

        # popups are really annoying
        "editor.hover.delay" = 700;

        # colors
        "workbench.colorTheme" = lib.mkForce "Darkbox";

        # icons
        "workbench.iconTheme" = "material-icon-theme";
        "material-icon-theme.folders.theme" = "classic";

        # title
        "window.titleSeparator" = " - ";
        "window.title" = lib.concatMapStrings (s: "\${${s}}") [
          "rootName"
          "separator"
          "activeEditorMedium"
          "separator"
          "appName"
        ];

        # scale the ui down
        # "window.zoomLevel" = -1;
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
        # insert a newline at the end of a file when saved
        "files.insertFinalNewline" = true;
        # trim whitespace trailing at the ends of lines on save
        "files.trimTrailingWhitespace" = true;
        # enable semantic highlighting
        "editor.semanticHighlighting.enabled" = true;

        "[yaml]" = {
          "editor.tabSize" = 2;
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };

        ## VCS Behavior ##
        "git.openRepositoryInParentFolders" = "always";
        "git.autofetch" = true;
        "git.confirmSync" = false;
        "git.path" =
          lib.mkIf (config.programs.git.enable) "/etc/profiles/per-user/${config.home.username}/bin/git";

        # prevent pollute history with whitespace changes
        "diffEditor.ignoreTrimWhitespace" = false;

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

        # remove telemetry
        "redhat.telemetry.enabled" = false;
        "telemetry.enableTelemetry" = false;
        "telemetry.feedback.enabled" = false;
        "telemetry.telemetryLevel" = "off";
        "terminal.integrated.localEchoEnabled" = "off";
      }
      (
        let
          shellPath = config.home.sessionVariables.SHELL;
          shellName = lib.last (lib.splitString "/" shellPath);
        in
        {
          # Define extra shells

          "terminal.integrated.profiles.${if pkgs.stdenv.isLinux then "linux" else "osx"}" =
            { }
            // lib.optionalAttrs config.programs.nushell.enable {
              ${shellName} = {
                "path" = "${shellPath}";
                "args" = [ "-l" ];
                "icon" =
                  if shellName == "bash" then
                    "terminal-bash"
                  else if shellName == "nu" then
                    "chevron-right"
                  else
                    "terminal";
              };
            };

          # set the integrated terminal to use SHELL so make sure SHELL is set correctly
          "terminal.integrated.defaultProfile.${if pkgs.stdenv.isLinux then "linux" else "osx"}" = shellName;
        }
      )
    ];
  };
}
