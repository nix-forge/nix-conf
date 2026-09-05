{
  config,
  lib,
  pkgs,
  ...
}:
let
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
      ''
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

        ${lib.getExe package} ${lib.escapeShellArgs arguments} > "$out"
        ${bash} -n "$out"
      '';

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

  bleshRc = pkgs.writeText "blesh-init.sh" (
    ''
      # Delay suggestions long enough that normal typing never waits for a
      # completion scan. Atuin is added to ble.sh's suggestion sources later.
      bleopt complete_auto_delay=200

      # Starship already reports failures and command duration. Suppress the
      # duplicate ble.sh markers and keep multiline editing visually quiet.
      bleopt exec_errexit_mark=
      bleopt exec_elapsed_mark=
      bleopt exec_exit_mark=
      bleopt prompt_eol_mark=
    ''
    + lib.optionalString config.programs.fzf.enable ''

      # The normal fzf Bash loader is incompatible with ble.sh. Use the pinned
      # fzf scripts through ble.sh and defer their parse cost until the shell is
      # idle. Atuin owns search in Emacs and vi-insert modes; vi-normal keeps
      # its standard Ctrl-R redo binding.
      _ble_contrib_fzf_base=${config.programs.fzf.package}/share/fzf
      ble-import -d integration/fzf-completion
      ble-import -d integration/fzf-key-bindings -C '
        # fzf installs Ctrl-R as a direct ble.sh widget. Replace it with an
        # editable Atuin widget so ble.sh exports and restores READLINE_LINE
        # and READLINE_POINT. enter_accept is disabled, so no accept-line
        # macro chain is required. Preserve vi-normal Ctrl-R as redo.
        if declare -F __atuin_history &>/dev/null; then
          ble-bind -m emacs -x C-r "__atuin_history --keymap-mode=emacs"
          ble-bind -m vi_imap -x C-r "__atuin_history --keymap-mode=vim-insert"
        fi
        ble-bind -m vi_nmap -f C-r vi_nmap/redo
      '

      # Keep the normal ble.sh completion menu on Tab. Shift-Tab opens the fzf
      # selector when a large or descriptive candidate set benefits from it.
      ble-import -d integration/fzf-menu -C '
        bleopt integration_fzf_menu_enabled=
        ble-bind -m emacs -f S-TAB fzf-menu-complete
        ble-bind -m vi_imap -f S-TAB fzf-menu-complete
        ble-bind -m vi_nmap -f S-TAB fzf-menu-complete
      '
    ''
  );
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
      (lib.mkOrder 50 ''
        builtin source -- "${pkgs.blesh}/share/blesh/ble.sh" \
          --attach=none \
          --rcfile "${bleshRc}"
      '')

      # Carapace emits a large completion table. ble.sh can parse the static
      # result while idle without delaying the first prompt.
      (lib.mkIf config.programs.carapace.enable (
        lib.mkOrder 500 ''
          ble-import -d "${carapaceInit}"
        ''
      ))

      # Atuin must see ble.sh before initialization. The temporary variable
      # prevents its generated fallback copy of bash-preexec from loading.
      (lib.mkIf config.programs.atuin.enable (
        lib.mkOrder 600 ''
          ATUIN_NO_BUILTIN_PREEXEC=1 builtin source -- "${atuinInit}"
        ''
      ))

      (lib.mkIf config.programs.starship.enable (
        lib.mkOrder 1700 ''
          builtin source -- "${starshipInit}"
        ''
      ))

      # Initialize zoxide before attachment, then let its ble.sh adapter advise
      # completion and directory-changing functions.
      (lib.mkIf config.programs.zoxide.enable (
        lib.mkOrder 1800 ''
          builtin source -- "${zoxideInit}"
          ble-import integration/zoxide
        ''
      ))

      # direnv asks to run after other prompt-changing integrations.
      (lib.mkIf config.programs.direnv.enable (
        lib.mkOrder 1900 ''
          builtin source -- "${direnvInit}"
        ''
      ))

      # Nothing that registers prompt, history, directory, or editing hooks may
      # appear after this attachment point.
      (lib.mkOrder 3000 ''
        [[ ! ''${BLE_VERSION-} ]] || ble-attach
      '')
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
