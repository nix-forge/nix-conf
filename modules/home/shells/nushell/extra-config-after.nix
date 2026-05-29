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
    ++ lib.optionals isDarwinHome (
      lib.splitString ":" osConfig.environment.systemPath
    )
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
    (lib.concatStringsSep "\n")
  ];
in
{
  programs.nushell.extraConfig =
    lib.mkAfter
      # Remove all nix binpaths from PATH, then apply them to the end of the list
      # This ensures nix paths don't appear multiple times and are consistently at the end
      ''
        let nix_paths = [
          ${binPaths}
        ]
        $env.PATH = ($env.PATH | split row (char esep) | where { |p| $p not-in $nix_paths } | append $nix_paths)
      '';
}
