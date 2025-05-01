{ config, lib, ... }@args:
{
  programs.nushell = {
    enable = true;

    settings = {
      # Remove the welcome banner message
      show_banner = false;
    };

    extraEnv =
      let
        exportToNuEnv =
          vars: lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: ''$env.${n} = "${builtins.replaceStrings [ "$USER" "$HOME" ] [ config.home.username config.home.homeDirectory ] v}"'') vars);

        paths = [
          config.home.profileDirectory
        ] ++ lib.optionals (args ? darwinConfig) args.darwinConfig.environment.profiles
        ++ lib.optionals (args ? nixosConfig) args.nixosConfig.environment.profiles;

        binPaths = lib.pipe paths [
          (builtins.map (p: "${p}/bin"))
          (builtins.map (builtins.replaceStrings [ "$USER" "$HOME" ] [ config.home.username config.home.homeDirectory ]))
        ];
      in
      lib.mkBefore (
        ''
          ${exportToNuEnv config.home.sessionVariables}
        ''
        + ''
          $env.PATH = $env.PATH | split row (char esep) | prepend [
            ${lib.concatStringsSep " " (config.home.sessionPath ++ binPaths)}
          ] | uniq
        ''
      );
  };
}
