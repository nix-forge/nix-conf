{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  defaultConfigDirDarwin = "${config.home.homeDirectory}/Library/Application Support/nushell";
  defaultConfigDirLinux = "${config.home.homeDirectory}/.config/nushell";
  defaultConfigDir = if pkgs.stdenv.isLinux then defaultConfigDirLinux else defaultConfigDirDarwin;
  xdgConfigDir = "${config.xdg.configHome}/nushell";
  symlinkConfig = config.xdg.enable && (xdgConfigDir != defaultConfigDir);
in
{
  # Symlink the XDG config directory to the default config directory if not the same
  # NOTE: this is due to NuShell nix only setting the XDG_CONFIG_DIR env var through bash and zsh shells
  home.file.${defaultConfigDir} = lib.mkIf symlinkConfig {
    source = config.lib.file.mkOutOfStoreSymlink xdgConfigDir;
  };

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

    extraEnv =
      let
        exportToNuEnv =
          vars:
          lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              n: v:
              let
                replaceVars =
                  varsIn: varsOut: v:
                  "$env.${n} = ${
                    if lib.typeOf v == "string" then
                      "\"${builtins.replaceStrings varsIn varsOut v}\""
                    else
                      builtins.toString v
                  }";
                replaceVarPresets =
                  v:
                  let
                    rightSideVarPreset = lib.concatStrings [
                      "$"
                      "{"
                      n
                      ":+:$"
                      n
                      "}"
                      "\""
                    ];
                  in
                  builtins.replaceStrings
                    [
                      rightSideVarPreset
                    ]
                    [
                      ''" + (do { let x = ($env.${n}? | default ""); if $x == "" { "" } else { ":" + $x } }) | split row (char esep) | uniq''
                    ]
                    v;
              in
              lib.pipe v [
                (replaceVars
                  [
                    "$HOME"
                    "$USER"
                  ]
                  [ config.home.username config.home.homeDirectory ]
                )
                replaceVarPresets
              ]
            ) vars
          );

        paths =
          [
            config.home.profileDirectory
          ]
          ++ lib.optionals (args ? darwinConfig) args.darwinConfig.environment.profiles
          ++ lib.optionals (args ? nixosConfig) args.nixosConfig.environment.profiles;

        binPaths = lib.pipe paths [
          (builtins.map (p: "${p}/bin"))
          (builtins.map (
            builtins.replaceStrings
              [ "$USER" "$HOME" "\${XDG_STATE_HOME}" ]
              [ config.home.username config.home.homeDirectory config.xdg.stateHome ]
          ))
        ];

        esepDirListToList = var: ''
          "${var}": {
            from_string: { |s| $s | split row (char esep) | path expand --no-symlink }
            to_string: { |v| $v | path expand --no-symlink | str join (char esep) }
          }
        '';
      in
      lib.mkBefore (
        ''
          ${exportToNuEnv config.home.sessionVariables}

          $env.ENV_CONVERSIONS = {
            ${esepDirListToList "TERMINFO_DIRS"}
            ${esepDirListToList "XDG_CONFIG_DIRS"}
            ${esepDirListToList "XDG_DATA_DIRS"}
            ${esepDirListToList "XCURSOR_PATH"}
          }
        ''
        + ''
          $env.PATH = $env.PATH | split row (char esep) | prepend [
            ${lib.concatStringsSep "\n" (
              (lib.optionals (args ? nixosConfig) [ "/run/wrappers/bin" ]) ++ config.home.sessionPath ++ binPaths
            )}
          ] | uniq
        ''
      );
  };
}
