{
  self,
  system,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.programs.chatgpt;
  supported = builtins.hasAttr "openai-codex-desktop" self.packages.${system};
in
{
  options.programs.chatgpt = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.jq pkgs.ripgrep ]";
      description = ''
        Optional task tools. On Linux these are fallback commands on ChatGPT's
        PATH, not global user commands. On macOS they are installed alongside
        the unchanged signed application. Prefer project shells for project
        dependencies. Required sandbox and desktop helpers belong to the package.
      '';
    };
  };

  config = lib.mkIf supported {
    home.packages = [
      (self.packages.${system}.openai-codex-desktop.override {
        inherit (cfg) extraPackages;
      })
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin cfg.extraPackages;
  };
}
