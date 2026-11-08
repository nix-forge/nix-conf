{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home-manager.users.${config.system.primaryUser};
  lifecycle = lib.getExe home.macos.applications.lifecyclePackage;
  user = lib.escapeShellArg config.system.primaryUser;
in
{
  # Nix owns deployment. This supported desktop policy is requirements TOML,
  # rather than the unrelated CLI check_for_update_on_startup preference.
  environment.etc."codex/requirements.toml".source =
    (pkgs.formats.toml { }).generate "codex-requirements.toml"
      { features.in_app_updates = false; };
  # Root and user Launch Services maintain separate metadata. Refresh the verified
  # canonical identity in that order after HM has finished installing apps.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    ${lifecycle} --mode refresh-system || exit 1
  '';
  # A new GUI process needs its own refresh. User status is a wakeup signal,
  # never privileged input: the helper queries live identities independently.
  launchd.daemons.macos-application-registry.serviceConfig = {
    ProgramArguments = [
      lifecycle
      "--mode"
      "refresh-system"
      "--if-changed"
    ];
    WatchPaths = [ "${home.xdg.stateHome}/macos-applications/lifecycle" ];
    RunAtLoad = true;
    # Retry transient launch/exec races through launchd. Successful checks sleep
    # until the next event; persistent failures are rate-limited and logged.
    KeepAlive.SuccessfulExit = false;
    ThrottleInterval = 30;
    StandardOutPath = "/var/log/macos-application-registry.log";
    StandardErrorPath = "/var/log/macos-application-registry-errors.log";
  };
  system.activationScripts.preActivation.text = lib.mkBefore ''
    /bin/launchctl asuser "$(/usr/bin/id -u ${user})" \
      /usr/bin/sudo --user=${user} -- ${lifecycle} --mode preflight || exit 1
  '';
}
