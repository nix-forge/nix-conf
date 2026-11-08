{ pkgs, home }:
pkgs.runCommand "starter-generated-config"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.python3
    ];
  }
  (
    (import ./lib/render-text.nix) ./scripts/starter-generated-config.sh {
      home_config_xdg_configFile_git_config_source = home.config.xdg.configFile."git/config".source;
      home_config_home_file_bashrc_source = home.config.home.file.".bashrc".source;
      scripts_generated_config_check_py = ./scripts/generated_config_check.py;
      home_config_home_file_home_config_xdg_configHome_starship_to =
        home.config.home.file."${home.config.xdg.configHome}/starship.toml".source;
    }
  )
