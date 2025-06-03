{
  config,
  ...
}:
{
  imports = [
    ./config-dir-fix.nix
    ./env.nix
  ];

  # Enable Bash to all launching of Nushell with bash in other programs
  programs.bash.enable = true;

  programs.nushell = {
    enable = true;

    # DOCS: https://github.com/nushell/nushell/tree/main/crates/nu-utils/src/doc_config.nu
    settings = {
      # Remove the welcome banner message
      show_banner = false;

      ls = {
        use_ls_colors = true;
      };

      rm = {
        always_trash = false;
      };

      edit_mode = "vi";

      buffer_editor = ""; # If Unset it will use the EDITOR env var to determine the editor

      cursor_shape = {
        emacs = "block";
        vi_insert = "block";
        vi_normal = "underscore";
      };

      completions = {
        algorithm = "prefix";
        case_sensitive = false;
        quick = true;
        partial = true;
        use_ls_colors = true;

        external = {
          enable = true;
          max_results = 100;
          completer = null;
        };
      };

      use_kitty_protocol = config.programs.kitty.enable;

      shell_integration = {
        osc2 = true;
        osc7 = true;
        osc8 = true;
        osc133 = true;
        osc633 = config.programs.vscode.enable;
        reset_application_mode = true;
      };

      bracketed_paste = true;

      use_ansi_coloring = true;

      error_style = "fancy";

      table = {
        mode = "rounded";
        index_mode = "always";
        show_empty = true;
        padding = {
          left = 1;
          right = 1;
        };
        trim = {
          methodology = "wrapping";
          wrapping_try_keep_words = true;
        };
        header_on_separator = false;
      };
    };
  };
}
