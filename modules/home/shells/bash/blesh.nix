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
      (
        (import ../../../../lib/templates/text.nix) ./scripts/render-bash-integration.sh {
          lib_getExe_package = lib.getExe package;
          lib_escapeShellArgs_arguments = lib.escapeShellArgs arguments;
          inherit bash;
        }
      );

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

  render = import ../../../../lib/templates/text.nix;
  init =
    name: source:
    render (./scripts + "/${name}-init.sh.in") { source = lib.escapeShellArg (toString source); };
  bleshRc = pkgs.writeText "blesh-init.sh" (
    builtins.readFile ./scripts/blesh-rc.sh
    + lib.optionalString config.programs.fzf.enable (
      render ./scripts/configure-blesh-fzf.sh {
        config_programs_fzf_package = config.programs.fzf.package;
      }
    )
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
      (lib.mkOrder 50 (
        render ./scripts/blesh-init.sh.in {
          blesh = lib.escapeShellArg "${pkgs.blesh}/share/blesh/ble.sh";
          rcFile = lib.escapeShellArg (toString bleshRc);
        }
      ))

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
      (lib.mkOrder 3000 (builtins.readFile ./scripts/blesh-attach.sh))
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
