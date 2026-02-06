profileName:
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions =
      let
        extensions = pkgs.callPackage ./marketplace.nix { inherit inputs; };
      in
      with extensions.release;
      [ ryuta46.multi-command ];

    keybindings =
      let
        modKey = if isDarwin then "cmd" else "ctrl";
        groups.formatOnManualSave =
          let
            when = lib.concatStringsSep " " [
              # manually saving should only format when auto-saving is enabled
              # in some form, and when the file doesn't already
              # get formatted on every save
              "config.editor.autoSave != off"
              "&& !config.editor.formatOnSave"
              # any other clauses match the default
              # ${modKey}+k ${modKey}+f manual format command
              "&& editorHasDocumentFormattingProvider"
              "&& editorTextFocus"
              "&& !editorReadonly"
              "&& !inCompositeEditor"
            ];
          in
          [
            # remove the default action for saving document
            {
              key = "${modKey}+s";
              command = "-workbench.action.files.save";
              inherit when;
            }
            # formatting behavior identical to the default ${modKey}+k ${modKey}+f
            # and the save as normal
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
        ### FORMAT DOCUMENT ON MANUAL SAVE ONLY ###
        groups.formatOnManualSave

        ### INSERT TAB CHARACTER ###
        {
          key = "${modKey}+k tab";
          command = "type";
          args = {
            text = "	";
          };
          when = "editorTextFocus && !editorReadonly";
        }

        ### FOCUS ON FILE EXPLORER SIDEBAR ###
        {
          key = "${modKey}+e";
          command = "-workbench.action.quickOpen";
        }
        {
          key = "${modKey}+e";
          command = "workbench.files.action.focusFilesExplorer";
        }

        ### STAGE/UNSTAGE SELECTED RANGES ###
        {
          # key = "${modKey}+k ${modKey}+alt+s",
          key = "${modKey}+alt+s";
          command = "git.stageSelectedRanges";
          when = "editorTextFocus && !operationInProgress && resourceScheme == 'file'";
        }
        {
          # key = "${modKey}+k ${modKey}+n",
          key = "${modKey}+alt+shift+s";
          command = "git.unstageSelectedRanges";
          when = "editorTextFocus && !operationInProgress && resourceScheme == 'file'";
        }
      ];
  };
}
