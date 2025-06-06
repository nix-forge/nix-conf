{
  lib,
  pkgs,
  config,
  ...
}:
{
  programs.nushell.extraConfig = lib.mkAfter (
    lib.concatStringsSep "\n" (
      [
        "const NU_LIB_DIRS = $NU_LIB_DIRS ++ ['${pkgs.nu_scripts}/share/nu_scripts']"

        "use custom-completions/curl/curl-completions.nu *"
        "use custom-completions/nix/nix-completions.nu *"
        "use custom-completions/ssh/ssh-completions.nu *"
        "use custom-completions/tar/tar-completions.nu *"
      ]
      ++ lib.optionals (pkgs.stdenv.isLinux) [ "use modules/nix/nix.nu *" ]
      ++ lib.optionals (config.programs.aerospace.enable) [
        "use custom-completions/aerospace/aerospace-completions.nu *"
      ]
      ++ lib.optionals (config.programs.bat.enable) [
        "use custom-completions/bat/bat-completions.nu *"
        "use aliases/bat/bat-aliases.nu *"
      ]
      ++ lib.optionals (config.programs.eza.enable) [
        # "use custom-completions/eza/eza-completions.nu *"
        # "use aliases/eza/eza-aliases.nu *"
      ]
      ++ lib.optionals (config.programs.gh.enable) [ "use custom-completions/gh/gh-completions.nu *" ]
      ++ lib.optionals (config.programs.git.enable) [
        "use custom-completions/git/git-completions.nu *"
        "use aliases/git/git-aliases.nu *"
      ]
      ++ lib.optionals (config.programs.man.enable) [ "use custom-completions/man/man-completions.nu *" ]
      ++ lib.optionals (config.programs.zoxide.enable) [
        "use custom-completions/zoxide/zoxide-completions.nu *"
      ]
      ++ lib.optionals (config.programs.vscode.enable) [
        "use custom-completions/vscode/vscode-completions.nu *"
      ]
    )
  );
}
