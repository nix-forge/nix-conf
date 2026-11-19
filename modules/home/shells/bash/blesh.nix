{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  bash = lib.getExe config.programs.bash.package;

  # These generators only depend on pinned packages. Build their output once
  # instead of spawning every program during each interactive shell startup.
  mkBashInit =
    name: package: arguments:
    pkgs.runCommandLocal "${name}-bash-init"
      {
        nativeBuildInputs = [
          package
          config.programs.bash.package
        ];
      }
      (checkedShellText {
        name = "render-${name}-bash-integration";
        text =
          myLib.templates.renderText
            {
              name = "render-bash-integration.sh";
              text = ''
                # shellcheck shell=bash
                # Nix builder/activation callers and rendered fragments provide external variables.
                # shellcheck disable=SC2154
                export HOME="$TMPDIR/home"
                export XDG_CACHE_HOME="$HOME/.cache"
                export XDG_CONFIG_HOME="$HOME/.config"
                export XDG_DATA_HOME="$HOME/.local/share"
                export XDG_STATE_HOME="$HOME/.local/state"
                mkdir -p \
                  "$XDG_CACHE_HOME" \
                  "$XDG_CONFIG_HOME" \
                  "$XDG_DATA_HOME" \
                  "$XDG_STATE_HOME"

                @lib_getExe_package@ @lib_escapeShellArgs_arguments@ >"$out"
                @bash@ -n "$out"
              '';
            }
            {
              lib_getExe_package = lib.getExe package;
              lib_escapeShellArgs_arguments = lib.escapeShellArgs arguments;
              inherit bash;
            };
      });

  carapaceInit = mkBashInit "carapace" config.programs.carapace.package [
    "_carapace"
    "bash-ble"
  ];
  atuinInit = mkBashInit "atuin" config.programs.atuin.package [
    "init"
    "bash"
    "--disable-ai"
  ];
  starshipInit = mkBashInit "starship" config.programs.starship.package [
    "init"
    "bash"
    "--print-full-init"
  ];
  zoxideInit = mkBashInit "zoxide" config.programs.zoxide.package [
    "init"
    "bash"
  ];
  direnvInit = mkBashInit "direnv" config.programs.direnv.package [
    "hook"
    "bash"
  ];

  render = myLib.templates.renderText;
  init =
    name: source:
    checkedShellText {
      name = "${name}-init";
      text =
        if name == "carapace" then
          "ble-import -d ${lib.escapeShellArg (toString source)}\n"
        else
          ''
            # The pinned application owns the sourced integration.
            # shellcheck source=/dev/null
            ${
              lib.optionalString (name == "atuin") "ATUIN_NO_BUILTIN_PREEXEC=1 "
            }builtin source -- ${lib.escapeShellArg (toString source)}
          ''
          + lib.optionalString (name == "zoxide") "ble-import integration/zoxide\n";
    };
  bleshRc = pkgs.writeText "blesh-init.sh" (checkedShellText {
    name = "blesh-rc";
    text = (''
      # shellcheck shell=bash
      # Delay suggestions while normal input is being typed.
      bleopt complete_auto_delay=200
      # Starship already reports failures and command duration.
      bleopt exec_errexit_mark=
      bleopt exec_elapsed_mark=
      bleopt exec_exit_mark=
      bleopt prompt_eol_mark=
    '')
    + lib.optionalString config.programs.fzf.enable (
      render {
        name = "configure-blesh-fzf.sh";
        text = ''
          # shellcheck shell=bash
          # The normal fzf Bash loader is incompatible with ble.sh. Use the pinned
          # fzf scripts through ble.sh and defer their parse cost until the shell is
          # idle. Atuin owns Ctrl-R search in Emacs mode.
          _ble_contrib_fzf_base=@config_programs_fzf_package@/share/fzf
          ble-import -d integration/fzf-completion
          ble-import -d integration/fzf-key-bindings -C '
            # fzf installs Ctrl-R as a direct ble.sh widget. Replace it with an
            # editable Atuin widget so ble.sh exports and restores READLINE_LINE
            # and READLINE_POINT. enter_accept is disabled, so no accept-line
            # macro chain is required.
            if declare -F __atuin_history &>/dev/null; then
              ble-bind -m emacs -x C-r "__atuin_history --keymap-mode=emacs"
            fi
          '

          # Keep the normal ble.sh completion menu on Tab. Shift-Tab opens the fzf
          # selector when a large or descriptive candidate set benefits from it.
          ble-import -d integration/fzf-menu -C '
            bleopt integration_fzf_menu_enabled=
            ble-bind -m emacs -f S-TAB fzf-menu-complete
          '
        '';
      } { config_programs_fzf_package = config.programs.fzf.package; }
    );
  });
in
{
  home.packages = [ pkgs.blesh ];

  # Keep the user-visible XDG file while passing the immutable source directly
  # to ble.sh. A stale ~/.blerc cannot shadow the declarative configuration.
  xdg.configFile."blesh/init.sh".source = bleshRc;

  programs = {
    bash.initExtra = lib.mkMerge [
      # VS Code's Copilot-only shell returns at order 10. Every normal shell
      # reaches this early source before bash-completion at order 100.
      (lib.mkOrder 50 (checkedShellText {
        name = "blesh-init";
        text =
          render
            {
              name = "blesh-init.sh.in";
              text = ''
                # shellcheck shell=bash
                # The pinned application owns the sourced integration.
                # shellcheck source=/dev/null
                builtin source -- @blesh@ --attach=none --rcfile @rcFile@
              '';
            }
            {
              blesh = lib.escapeShellArg "${pkgs.blesh}/share/blesh/ble.sh";
              rcFile = lib.escapeShellArg (toString bleshRc);
            };
      }))

      # Carapace emits a large completion table. ble.sh can parse the static
      # result while idle without delaying the first prompt.
      (lib.mkIf config.programs.carapace.enable (lib.mkOrder 500 (init "carapace" carapaceInit)))

      # Atuin must see ble.sh before initialization. The temporary variable
      # prevents its generated fallback copy of bash-preexec from loading.
      (lib.mkIf config.programs.atuin.enable (lib.mkOrder 600 (init "atuin" atuinInit)))

      (lib.mkIf config.programs.starship.enable (lib.mkOrder 1700 (init "starship" starshipInit)))

      # Initialize zoxide before attachment, then let its ble.sh adapter advise
      # completion and directory-changing functions.
      (lib.mkIf config.programs.zoxide.enable (lib.mkOrder 1800 (init "zoxide" zoxideInit)))

      # direnv asks to run after other prompt-changing integrations.
      (lib.mkIf config.programs.direnv.enable (lib.mkOrder 1900 (init "direnv" direnvInit)))

      # Nothing that registers prompt, history, directory, or editing hooks may
      # appear after this attachment point.
      (lib.mkOrder 3000 (checkedShellText {
        name = "blesh-attach";
        text = ''
          [[ ! ''${BLE_VERSION-} ]] || ble-attach
        '';
      }))
    ];

    # This module owns Bash integration for ble-sensitive programs. Their
    # generic Home Manager fragments remain enabled for every other shell.
    atuin.enableBashIntegration = lib.mkIf config.programs.atuin.enable (lib.mkForce false);
    carapace.enableBashIntegration = lib.mkIf config.programs.carapace.enable (lib.mkForce false);
    direnv.enableBashIntegration = lib.mkIf config.programs.direnv.enable (lib.mkForce false);
    fzf.enableBashIntegration = lib.mkIf config.programs.fzf.enable (lib.mkForce false);
    starship.enableBashIntegration = lib.mkIf config.programs.starship.enable (lib.mkForce false);
    television.enableBashIntegration = lib.mkIf config.programs.television.enable (lib.mkForce false);
    zoxide.enableBashIntegration = lib.mkIf config.programs.zoxide.enable (lib.mkForce false);
  };
}
