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
        "use custom-completions/uv/uv-completions.nu *"
        "use custom-completions/typst/typst-completions.nu *"
        "use custom-completions/rg/rg-completions.nu *"
        "use custom-completions/pytest/pytest-completions.nu *"
        "use custom-completions/podman/podman-completions.nu *"
        "use custom-completions/docker/docker-completions.nu *"
        "use custom-completions/pre-commit/pre-commit-completions.nu *"
        "use custom-completions/npm/npm-completions.nu *"
        "use custom-completions/pnpm/pnpm-completions.nu *"
        "use custom-completions/mvn/mvn-completions.nu *"
        "use custom-completions/make/make-completions.nu *"
        "use custom-completions/just/just-completions.nu *"
      ]
      ++ lib.optionals config.programs.aerospace.enable [
        "use custom-completions/aerospace/aerospace-completions.nu *"
      ]
      ++ lib.optionals config.programs.bat.enable [ "use custom-completions/bat/bat-completions.nu *" ]
      ++ lib.optionals config.programs.gh.enable [ "use custom-completions/gh/gh-completions.nu *" ]
      ++ lib.optionals config.programs.git.enable [ "use custom-completions/git/git-completions.nu *" ]
      ++ lib.optionals config.programs.man.enable [ "use custom-completions/man/man-completions.nu *" ]
      ++ lib.optionals config.programs.zoxide.enable [
        "use custom-completions/zoxide/zoxide-completions.nu *"
      ]
      ++ lib.optionals config.programs.vscode.enable [
        "use custom-completions/vscode/vscode-completions.nu *"
      ]
    )
  );
}
