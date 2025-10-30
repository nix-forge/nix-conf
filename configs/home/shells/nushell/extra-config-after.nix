{ lib, config, ... }@args:
let
  paths =
    lib.concatLists [
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
    (lib.concatStringsSep "\n")
  ];
in
{
  programs.nushell.extraConfig = lib.mkAfter (
    # Emulate the nix PATH as best as possible
    ''
      $env.PATH = $env.PATH | split row (char esep) | prepend [
        ${binPaths}
      ]
    ''
    # The `path add` function from the Standard Library also provides
    # a convenience method for prepending to the path:
    + ''
      use std/util "path add"
      path add "~/.local/bin"
    ''
    # You can remove duplicate directories from the path using:
    + ''
      $env.PATH = ($env.PATH | uniq)
    ''
  );
}
