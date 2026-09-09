{
  homeManager =
    { config, lib, ... }:
    let
      cfg = config.stylix.targets.ghostty;
    in
    {
      key = "nix-conf/stylix/ghostty/homeManager";
      _file = __curPos.file;
      options.stylix.targets.ghostty.custom.enable = lib.mkEnableOption "the desktop Ghostty styling" // {
        default = true;
      };
      config =
        lib.mkIf (config.stylix.enable && cfg.enable && cfg.custom.enable && config.programs.ghostty.enable)
          {
            programs.ghostty.settings = lib.mkMerge [
              (lib.mkIf cfg.fonts.enable {
                # Let Ghostty choose text/emoji presentation and the platform fallback,
                # including Apple Color Emoji on macOS. An explicit Noto emoji family
                # also shrinks nom's one-cell text stopwatch on Linux.
                font-family = lib.mkForce [ config.stylix.fonts.monospace.name ];

              })
              (lib.mkIf cfg.colors.enable {
                # Stylix uses base02 for selections, which is nearly black in Carbon
                # Neon. Use the accent with dark text to make selected ranges visible.
                selection-background = config.appearance.palette.accent;
                selection-foreground = config.appearance.palette.surface;

              })
            ];
          };
    };
}
