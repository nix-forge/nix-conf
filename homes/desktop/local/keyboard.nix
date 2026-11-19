{ config, lib, ... }: {
  keyboard.macosShortcuts.enable = true;
  # Match Rift's numbered and named workspace destinations. Space IDs differ
  # internally (Rift is zero-based); the physical shortcuts and labels agree.
  # Disabling the scheme also restores the old workspace keys, avoiding clashes
  # with the shell's original Super-based shortcuts.
  desktop.workflow = lib.mkIf config.keyboard.macosShortcuts.enable {
    workspaceCount = 9;
    namedWorkspaces = builtins.listToAttrs (
      lib.imap0
        (index: key: {
          name = key;
          value = toString (index + 10);
        })
        [
          "B"
          "C"
          "D"
          "M"
          "N"
          "P"
          "T"
          "E"
          "A"
          "S"
          "Z"
        ]
    );
  };
}
