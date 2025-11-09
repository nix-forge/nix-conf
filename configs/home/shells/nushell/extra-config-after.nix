{ lib, config, ... }@args:
let
  paths =
    lib.concatLists [
      [ "${config.home.homeDirectory}/.local/bin" ]
      config.home.sessionPath
      [ "${config.home.profileDirectory}/bin" ]
    ]
    ++ lib.optionals (args ? darwinConfig) (
      lib.splitString ":" args.darwinConfig.environment.systemPath
    )
    ++ lib.optionals (args ? nixosConfig) (
      lib.concatLists [
        [ "/run/wrappers/bin" ]
        (builtins.map (p: "${p}/bin") args.nixosConfig.environment.profiles)
      ]
    );

  binPaths = lib.pipe paths [
    (builtins.map (
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
      # Emulate the nix PATH as best as possible
      # Also remove duplicate paths that other programs may apply
      ''
        $env.PATH = $env.PATH | split row (char esep) | append [
          ${binPaths}
        ] | uniq
      '';
}
