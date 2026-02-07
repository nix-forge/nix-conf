{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [ "ryuta46.multi-command" ];

    keybindings =
      let
        modKey = if isDarwin then "cmd" else "ctrl";
        formatOnManualSave =
          let
            when = lib.concatStringsSep " && " [
              "config.editor.autoSave != off"
              "!config.editor.formatOnSave"
              "editorHasDocumentFormattingProvider"
              "editorTextFocus"
              "!editorReadonly"
              "!inCompositeEditor"
            ];
          in
          [
            {
              key = "${modKey}+s";
              command = "-workbench.action.files.save";
              inherit when;
            }
            {
              key = "${modKey}+s";
              command = "extension.multiCommand.execute";
              args = {
                sequence = [
                  "editor.action.formatDocument"
                  "workbench.action.files.save"
                ];
              };
              inherit when;
            }
          ];
      in
      lib.flatten [
        # format on manual save
        formatOnManualSave

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
