{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  programs.vscode.enable = true;
  programs.vscode.package =
    let
      # TODO: This doesn't seem to work as expected for the fonts at least on Darwin
      fontPackages = with pkgs; [
        material-design-icons
        nerd-fonts.monaspace
        nerd-fonts.jetbrains-mono
      ];
      vscode = pkgs.vscode.overrideAttrs (oldAttrs: {
        buildInputs = oldAttrs.buildInputs ++ [ fontPackages ];
      });
    in
    vscode;

  programs.vscode.profiles.default.enableExtensionUpdateCheck = false;
  programs.vscode.profiles.default.enableUpdateCheck = false;
  programs.vscode.mutableExtensionsDir = false;

  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ./marketplace.nix { inherit inputs; };
    in
    (with extensions.preferPreRelease; [
      ## Appearances ##
      bottledlactose.darkbox

      pkief.material-icon-theme

      ## Intelligence ##
      github.copilot
      usernamehw.errorlens
      christian-kohler.path-intellisense
      streetsidesoftware.code-spell-checker

      ## Version Control ##
      # huizhou.githd
      # mhutchie.git-graph
      # phil294.git-log--graph
      github.vscode-github-actions

      ## Collaboration Features
      # ms-vsliveshare.vsliveshare

      ## Editor Extension ##
      ryuta46.multi-command
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
      ms-vsliveshare.vsliveshare
    ])
    ++ (with extensions.extraCompatible; [
      # This extension when using non VSCode Insiders requires release version
      github.copilot-chat
    ]);

  programs.vscode.profiles.default.userSettings = {
    ## Appearances ##

    # the most important setting
    "editor.fontFamily" = lib.mkForce (
      lib.concatMapStringsSep ", " (s: "'${s}'") [
        "Material Design Icons"
        "MonaspiceNe Nerd Font"
        "JetBrainsMono Nerd Font"
      ]
    );
    "editor.cursorSmoothCaretAnimation" = "explicit";
    "editor.cursorStyle" = "block";
    "editor.cursorBlinking" = "smooth";
    "editor.fontLigatures" =
      "'calt', 'liga', 'ss01', 'ss02', 'ss03', 'ss04', 'ss05', 'ss06', 'ss07', 'ss08', 'ss09'";

    # for some reason it is not the same as the editor
    "terminal.integrated.lineHeight" = 1.4;

    # popups are really annoying
    "editor.hover.delay" = 700;

    # colors
    "workbench.colorTheme" = lib.mkForce "Darkbox";
    # "workbench.colorCustomizations" = {
    #   "[Monokai Pro (Filter Spectrum)]" = {
    #     "editorInlayHint.foreground" = "#69676c";
    #     "editorInlayHint.background" = "#222222";
    #   };
    # };

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

    # top is the smallest other than hidden but you need to remember the shortcuts
    "workbench.activityBar.location" = "top";
    # put the sidebar on the right so that text doesn't jump
    "workbench.sideBar.location" = "right";
    # no delay when automatically hiding the sidebar or panels

    # AutoHide does not cancel the timer if the panel is re-selected,
    # rendering these settings (and the extension) completely useless.
    # "autoHide.sideBarDelay" = 30000; # seconds
    # "autoHide.panelDelay" = 30000; # seconds

    # show vcs changes and staged changes as a tree
    "scm.defaultViewMode" = "tree";

    ## Saving and Formatting ##

    # auto-save when the active editor loses focus
    "editor.formatOnSave" = true;
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

    # allow 6 more characters from default 50 in commit subject
    "git.inputValidationSubjectLength" = 56;

    "git.openRepositoryInParentFolders" = "always";
    "git.autofetch" = true;
    "git.confirmSync" = false;

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
    # "window.restoreWindows" = "none";
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
    # set the integrated terminal to use zsh
    "terminal.integrated.defaultProfile.linux" = "zsh";

    # github copilot
    "github.copilot.editor.enableAutoCompletions" = true;

    # remove telemetry
    "redhat.telemetry.enabled" = false;
    "telemetry.enableTelemetry" = false;
  };
}
