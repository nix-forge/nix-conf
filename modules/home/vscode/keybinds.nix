{
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

        mkWhen = clauses: lib.concatStringsSep " && " clauses;

        mkManualSaveBinding =
          when: sequence: [
            {
              key = "${modKey}+s";
              command = "-workbench.action.files.save";
              inherit when;
            }
            {
              key = "${modKey}+s";
              command = "runCommands";
              args = { commands = sequence; };
              inherit when;
            }
          ];

        whenText = mkWhen [
          "config.editor.autoSave != off"
          "!config.editor.formatOnSave"
          "editorHasDocumentFormattingProvider"
          "editorTextFocus"
          "!editorReadonly"
          "!inCompositeEditor"
          "!jupyter.isinteractiveornativeactive"
        ];

        whenNotebook = mkWhen [
          "config.editor.autoSave != off"
          "!config.editor.formatOnSave"
          "jupyter.isinteractiveornativeactive"
          "editorTextFocus"
          "!editorReadonly"
          "!inCompositeEditor"
        ];
      in
      lib.flatten [
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
