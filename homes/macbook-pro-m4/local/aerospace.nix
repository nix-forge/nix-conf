{ lib, ... }:
let
  external = "^PG32UCWM$";
  laptop = "^Built-in Retina Display$";
in
{
  programs.aerospace.settings = {
    # Match display names rather than positions or the macOS main display.
    # Closing the lid or unplugging the monitor falls back to the remaining
    # screen. Reconnecting restores the preferred assignments automatically.
    workspace-to-monitor-force-assignment =
      lib.genAttrs [ "1" "2" "3" "4" "5" ] (_: [
        external
        laptop
        "main"
      ])
      // lib.genAttrs [ "6" "7" "8" "9" ] (_: [
        laptop
        external
        "main"
      ]);

    # Focus the other screen without moving its workspace. The shared
    # Option+Shift+Tab binding can still move unassigned lettered workspaces.
    mode.main.binding.alt-ctrl-tab = "focus-monitor --wrap-around next";
  };
}
