{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  programs.vscode.profiles.default = {
    keybindings =
      let
        modKey = if isDarwin then "cmd" else "ctrl";
        macShortcuts = config.keyboard.macosShortcuts.enable or false;
        saveModifiers = [ modKey ] ++ lib.optional (macShortcuts && !isDarwin) "meta";
        native = key: command: when: { inherit key command when; };
        gui = "textInputFocus && !terminalFocus";
        editor = "editorTextFocus && !terminalFocus";
        # Keep native Ctrl bindings as an escape hatch. Meta is Linux Super.
        macBindings = lib.optionals (macShortcuts && !isDarwin) [
          (native "meta+c" "editor.action.clipboardCopyAction" gui)
          (native "meta+v" "editor.action.clipboardPasteAction" gui)
          (native "meta+x" "editor.action.clipboardCutAction" gui)
          (native "meta+a" "editor.action.selectAll" gui)
          (native "meta+z" "undo" gui)
          (native "meta+shift+z" "redo" gui)
          (native "meta+s" "workbench.action.files.save" "!terminalFocus")
          (native "meta+shift+s" "workbench.action.files.saveAs" "!terminalFocus")
          (native "meta+f" "actions.find" "!terminalFocus")
          (native "meta+shift+f" "workbench.action.findInFiles" "!terminalFocus")
          (native "meta+n" "workbench.action.files.newUntitledFile" "")
          (native "meta+o" "workbench.action.files.openFile" "")
          (native "meta+w" "workbench.action.closeActiveEditor" "!terminalFocus")
          (native "meta+shift+t" "workbench.action.reopenClosedEditor" "")
          (native "meta+p" "workbench.action.quickOpen" "")
          (native "meta+shift+p" "workbench.action.showCommands" "")
          (native "meta+t" "workbench.action.showAllSymbols" "!terminalFocus")
          (native "meta+b" "workbench.action.toggleSidebarVisibility" "")
          (native "meta+e" "workbench.files.action.focusFilesExplorer" "")
          (native "meta+," "workbench.action.openSettings" "")
          (native "meta+/" "editor.action.commentLine" editor)
          (native "meta+left" "cursorHome" editor)
          (native "meta+right" "cursorEnd" editor)
          (native "meta+up" "cursorTop" editor)
          (native "meta+down" "cursorBottom" editor)
          (native "meta+shift+left" "cursorHomeSelect" editor)
          (native "meta+shift+right" "cursorEndSelect" editor)
          (native "meta+shift+up" "cursorTopSelect" editor)
          (native "meta+shift+down" "cursorBottomSelect" editor)
          (native "alt+left" "cursorWordLeft" editor)
          (native "alt+right" "cursorWordRight" editor)
          (native "alt+shift+left" "cursorWordLeftSelect" editor)
          (native "alt+shift+right" "cursorWordRightSelect" editor)
          (native "alt+backspace" "deleteWordLeft" editor)
          (native "alt+delete" "deleteWordRight" editor)
          (native "meta+backspace" "deleteAllLeft" editor)
          (native "meta+c" "workbench.action.terminal.copySelection" "terminalFocus && terminalTextSelected")
          # Without a selection, consume Command+C instead of sending SIGINT.
          (native "meta+c" "workbench.action.terminal.clearSelection"
            "terminalFocus && !terminalTextSelected"
          )
          (native "meta+v" "workbench.action.terminal.paste" "terminalFocus")
          (native "meta+a" "workbench.action.terminal.selectAll" "terminalFocus")
          (native "meta+f" "workbench.action.terminal.focusFind" "terminalFocus")
          (native "meta+w" "workbench.action.terminal.kill" "terminalFocus")
        ];

        mkWhen = clauses: lib.concatStringsSep " && " clauses;

        mkManualSaveBinding =
          when: sequence:
          lib.concatMap (modifier: [
            {
              key = "${modifier}+s";
              command = "-workbench.action.files.save";
              inherit when;
            }
            {
              key = "${modifier}+s";
              command = "runCommands";
              args = {
                commands = sequence;
              };
              inherit when;
            }
          ]) saveModifiers;

        whenText = mkWhen [
          "config.files.autoSave != off"
          "!config.editor.formatOnSave"
          "editorHasDocumentFormattingProvider"
          "editorTextFocus"
          "!editorReadonly"
          "!inCompositeEditor"
          "!jupyter.isinteractiveornativeactive"
        ];

        whenNotebook = mkWhen [
          "config.files.autoSave != off"
          "!config.editor.formatOnSave"
          "jupyter.isinteractiveornativeactive"
          "editorTextFocus"
          "!editorReadonly"
          "!inCompositeEditor"
        ];
      in
      lib.flatten [
        macBindings
        (lib.optional (macShortcuts && !isDarwin) {
          key = "meta+k tab";
          command = "type";
          args.text = "\t";
          when = "editorTextFocus && !editorReadonly";
        })
        (mkManualSaveBinding whenText [
          "editor.action.formatDocument"
          "workbench.action.files.save"
        ])
        (mkManualSaveBinding whenNotebook [
          "notebook.format"
          "workbench.action.files.save"
        ])

        # Insert tab character
        {
          key = "${modKey}+k tab";
          command = "type";
          args = {
            text = "	";
          };
          when = "editorTextFocus && !editorReadonly";
        }

        # Focus file explorer
        {
          key = "${modKey}+e";
          command = "-workbench.action.quickOpen";
        }
        {
          key = "${modKey}+e";
          command = "workbench.files.action.focusFilesExplorer";
        }
      ];
  };
}
