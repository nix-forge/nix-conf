{ config, lib, ... }:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  imports = [
    ./catalog.nix
    ./base/terminal.nix
    ./base/structured-data.nix
    ./base/security.nix
    ./base/performance.nix
  ];
  programs.vscode.profiles.default = {
    extensions = catalogExtensions (
      [
        "editorconfig.editorconfig"
        "usernamehw.errorlens"
        "streetsidesoftware.code-spell-checker"
        "ms-vscode-remote.remote-ssh"
      ]
      ++ lib.optionals config.programs.direnv.enable [ "mkhl.direnv" ]
    );
    userSettings = lib.mkMerge [
      {
        # popups are really annoying
        "editor.hover.delay" = 700;

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
        # formatting runs via explicit save keybindings, not implicit save hooks
        "editor.formatOnSave" = false;
        # format pasted code if the formatter supports a range
        "editor.formatOnPaste" = true;
        # Highlight bad ASCII characters
        "editor.unicodeHighlight.nonBasicASCII" = true;
        # insert a newline at the end of a file when saved
        "files.insertFinalNewline" = true;
        # trim whitespace trailing at the ends of lines on save
        "files.trimTrailingWhitespace" = true;
        # Let each selected theme opt into semantic highlighting. Carbon opts in
        # in its theme file, so lexical and semantic rules have the same owner.
        "editor.semanticHighlighting.enabled" = "configuredByTheme";

        ## VCS Behavior ##
        "git.enableSmartCommit" = false;
        "git.terminalAuthentication" = false;
        "git.openRepositoryInParentFolders" = "prompt";
        "git.autofetch" = true;
        "git.confirmSync" = true;

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

        # Debounce live diagnostics; delayMode is inactive when delay is zero.
        "errorLens.delay" = 500;
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
          "node_modules"
          "**/node_modules"
          "**/node_modules/**"
          "node_modules/**"
          ".git"
          "*.dll"
          "**/*.dll"
        ];

        # remove telemetry
        "redhat.telemetry.enabled" = false;
        "telemetry.telemetryLevel" = "off";
      }
      # Git
      (lib.mkIf (config.programs.git.enable && config.programs.git.signing.signByDefault == true) {
        "git.enableCommitSigning" = true;
      })
      (lib.mkIf (
        config.programs.git.enable
        && lib.hasAttr "pull" config.programs.git.settings
        && lib.hasAttr "rebase" config.programs.git.settings.pull
      ) { "git.rebaseWhenSync" = config.programs.git.settings.pull.rebase; })
      (lib.mkIf (
        config.programs.git.enable
        && lib.hasAttr "fetch" config.programs.git.settings
        && lib.hasAttr "prune" config.programs.git.settings.fetch
      ) { "git.pruneOnFetch" = config.programs.git.settings.fetch.prune; })

      (lib.mkIf config.programs.direnv.enable {
        "direnv.path.executable" = lib.getExe config.programs.direnv.package;
      })
    ];
  };
}
