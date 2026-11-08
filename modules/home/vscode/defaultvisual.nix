{ config, lib, ... }: {
  imports = [ ./default.nix ];
  home.sessionVariables.VISUAL = lib.mkDefault (
    if config.programs.vscode.package == null then "code" else lib.getExe config.programs.vscode.package
  );
}
