# Compare observable module warnings and the preserved canonical theme.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  inherit (pkgs) lib;
  adapter = (import ../stylix-nvf.nix { inherit lib; }).apply flake.inputs.stylix;
  evaluate =
    repaired:
    flake.inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        flake.inputs.nvf.homeManagerModules.default
        flake.inputs.stylix.homeModules.stylix
        {
          home = {
            username = "probe";
            homeDirectory = "/home/probe";
            stateVersion = "26.05";
          };
          programs.nvf = {
            enable = true;
            settings.vim.statusline.lualine.enable = true;
          };
          stylix = {
            enable = true;
            autoEnable = false;
            targets.neovim = {
              enable = true;
              plugin = "base16";
            };
            base16Scheme = {
              scheme = "Probe";
              author = "Fixture";
              base00 = "181818";
              base01 = "282828";
              base02 = "383838";
              base03 = "585858";
              base04 = "b8b8b8";
              base05 = "d8d8d8";
              base06 = "e8e8e8";
              base07 = "f8f8f8";
              base08 = "ab4642";
              base09 = "dc9656";
              base0A = "f7ca88";
              base0B = "a1b56c";
              base0C = "86c1b9";
              base0D = "7cafc2";
              base0E = "ba8baf";
              base0F = "a16946";
            };
          };
        }
      ]
      ++ lib.optional repaired adapter;
    };
  upstream = (evaluate false).config;
  repaired = (evaluate true).config;
  renamedTheme = warning: lib.hasInfix "lualine.theme" warning && lib.hasInfix "renamed" warning;
in
assert lib.all (entry: entry.assertion) upstream.assertions;
assert lib.all (entry: entry.assertion) repaired.assertions;
assert lib.any renamedTheme upstream.warnings;
assert !(lib.any renamedTheme repaired.warnings);
assert upstream.programs.nvf.settings.vim.statusline.lualine.setupOpts.options.theme == "base16";
assert repaired.programs.nvf.settings.vim.statusline.lualine.setupOpts.options.theme == "base16";
{
  inherit (flake.inputs.stylix) rev;
  upstreamWarnings = upstream.warnings;
  repairedWarnings = repaired.warnings;
}
