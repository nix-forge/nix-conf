{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.greetd = {
    enable = true;
    settings =
      let
        # Define greetd-tui
        greetd_tui_exec = lib.getExe pkgs.greetd.tuigreet;
        sessions = config.services.displayManager.sessionData.desktops;
        sessionsPath = lib.strings.concatStringsSep ":" [
          "${sessions}/share/wayland-sessions"
          "${sessions}/share/xsessions"
        ];
        greetd_tui_args = lib.strings.concatStringsSep " " [
          "--time" # display the current date and time
          "--time-format '%I:%M %p | %a • %h | %F'" # custom strftime format for displaying date and time
          "--remember" # remember last logged-in username
          "--remember-user-session" # remember last selected session for each user
          "--asterisks" # display asterisks when a secret is typed
          "--sessions ${sessionsPath}" # colon-separated list of session paths
        ];
        greetd_tui_command = "${greetd_tui_exec} ${greetd_tui_args}";
      in
      {
        # Set the default session
        default_session = {
          command = greetd_tui_command;
          user = "greeter";
        };
      };
  };
}
