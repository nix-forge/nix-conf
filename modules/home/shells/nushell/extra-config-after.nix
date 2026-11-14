{
  lib,
  config,
  osConfig ? null,
  ...
}:
let
  isDarwinHome = osConfig != null && osConfig ? launchd;
  isNixosHome = osConfig != null && osConfig ? systemd;
  paths =
    lib.concatLists [
      [ "${config.home.homeDirectory}/.local/bin" ]
      config.home.sessionPath
      [ "${config.home.profileDirectory}/bin" ]
    ]
    ++ lib.optionals isDarwinHome (lib.splitString ":" osConfig.environment.systemPath)
    ++ lib.optionals isNixosHome (
      lib.concatLists [
        [ "/run/wrappers/bin" ]
        (map (p: "${p}/bin") osConfig.environment.profiles)
      ]
    );

  binPaths = lib.pipe paths [
    (map (
      builtins.replaceStrings
        [ "$USER" "$HOME" "\${XDG_STATE_HOME}" ]
        [ config.home.username config.home.homeDirectory config.xdg.stateHome ]
    ))
    lib.unique
    (lib.hm.nushell.toNushell { })
  ];
in
{
  programs.nushell.extraConfig = lib.mkAfter (
    (import ../../../../lib/templates/text.nix) ./scripts/extra-config-after-config.nu.in {
      inherit binPaths;
    }
  );
}
