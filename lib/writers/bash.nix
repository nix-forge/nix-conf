{ lib, ... }: {
  writeBashTemplate =
    { pkgs }:
    {
      name,
      src,
      replacements,
      dir ? null,
      runtimeInputs ? [ ],
      inheritPath ? true,
      shellcheckFlags ? [ ],
    }:
    let
      check = pkgs.writeShellApplication {
        name = "check-rendered-bash";
        text = (import ../templates/text.nix) ./scripts/check-rendered-bash.sh {
          syntaxCheck = pkgs.stdenv.shellDryRun;
          shellcheck = lib.getExe pkgs.shellcheck-minimal;
          shellcheckFlags = lib.escapeShellArgs shellcheckFlags;
        };
      };
      contextualReplacements = lib.mapAttrs (
        _: value: if builtins.isPath value then "${value}" else value
      ) replacements;
      runtimePath = lib.makeBinPath runtimeInputs;
      pathSetup =
        if inheritPath then
          lib.optionalString (runtimeInputs != [ ]) "export PATH=${lib.escapeShellArg runtimePath}:\"$PATH\""
        else
          "export PATH=${lib.escapeShellArg runtimePath}";
      rendered = pkgs.replaceVarsWith {
        name = "${name}-body";
        inherit src;
        replacements = contextualReplacements;
        # The writer supplies the interpreter. Keep standalone source files
        # usable, but remove their known Bash shebang after strict substitution.
        postInstall = (import ../templates/text.nix) ./scripts/install-bash-body.sh {
          bash = lib.getExe pkgs.bash;
          bashNonInteractive = lib.getExe pkgs.bashNonInteractive;
          inherit (pkgs) runtimeShell;
          pathSetup = lib.escapeShellArg pathSetup;
        };
      };
      options.check = lib.getExe check;
    in
    # Pass the derivation itself: interpolating it would turn its path into
    # literal program text. The writer reads it and checks the complete script.
    if dir == "bin" then
      pkgs.writers.writeBashBin name options rendered
    else
      pkgs.writers.writeBash (if dir == null then name else "/${dir}/${name}") options rendered;
}
