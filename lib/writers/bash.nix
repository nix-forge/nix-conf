{ lib }:
let
  render =
    name: text: replacements:
    if replacements == null then
      text
    else
      (import ../templates/text.nix) { inherit name text; } replacements;
  checkPhase =
    pkgs:
    {
      format,
      shellcheckFlags,
      shell ? "bash",
    }:
    assert lib.elem shell [
      "bash"
      "sh"
    ];
    let
      tools = pkgs.buildPackages;
      shfmt = lib.getExe tools.shfmt;
      shellcheck = lib.getExe tools.shellcheck;
      dialect = if shell == "bash" then "bash" else "posix";
      syntaxCheck = if shell == "bash" then pkgs.stdenv.shellDryRun else "${lib.getExe tools.dash} -n";
    in
    ''
      ${syntaxCheck} "$target"
    ''
    + (
      if format then
        ''
          ${shfmt} -ln ${dialect} -i 2 -s "$target" > "$TMPDIR/formatted-bash"
          cat "$TMPDIR/formatted-bash" > "$target"
          ${syntaxCheck} "$target"
        ''
      else
        ''
          ${shfmt} -ln ${dialect} "$target" > /dev/null
        ''
    )
    + ''
      ${shellcheck} --norc --shell=${shell} --external-sources --check-sourced ${lib.escapeShellArgs shellcheckFlags} "$target"
    '';

  script =
    destination:
    { pkgs }:
    name: text:
    pkgs.writeTextFile {
      inherit name;
      destination = destination name;
      executable = true;
      text = ''
        #!${pkgs.runtimeShell}
        ${text}
      '';
      checkPhase = checkPhase pkgs {
        format = true;
        shellcheckFlags = [ ];
      };
    };
in
rec {
  writeShellScript = script (_: "");
  writeShellScriptBin = script (name: "/bin/${name}");

  writeShellApplication =
    { pkgs }:
    {
      excludeShellChecks ? [ ],
      extraShellCheckFlags ? [ ],
      replacements ? null,
      ...
    }@args:
    assert !(args ? checkPhase);
    pkgs.writeShellApplication (
      (removeAttrs args [ "replacements" ])
      // {
        text = render args.name args.text replacements;
        checkPhase = ''
          runHook preCheck
          ${checkPhase pkgs {
            format = true;
            shellcheckFlags =
              lib.optionals (excludeShellChecks != [ ]) [
                "--exclude"
                (lib.concatStringsSep "," excludeShellChecks)
              ]
              ++ extraShellCheckFlags;
          }}
          runHook postCheck
        '';
      }
    );

  # Run checks in a dependency of the consuming derivation. Keep the fragment
  # byte-for-byte in its original shell scope, without reading any build output.
  checkedShellText =
    { pkgs }:
    {
      name,
      text,
      shell ? "bash",
      replacements ? null,
      shellcheckFlags ? [ ],
    }:
    let
      rendered = render name text replacements;
      checked = pkgs.writeTextFile {
        name = "${name}-${shell}-check";
        text = rendered;
        checkPhase = checkPhase pkgs {
          format = false;
          inherit shell shellcheckFlags;
        };
      };
    in
    builtins.appendContext rendered (builtins.getContext "${checked}");

  renderBashText =
    args: template: replacements:
    checkedShellText args (template // { inherit replacements; });

  writeBashTemplate =
    { pkgs }:
    {
      name,
      src ? null,
      text ? null,
      replacements ? { },
      dir ? null,
      runtimeInputs ? [ ],
      inheritPath ? true,
      shellcheckFlags ? [ ],
    }:
    assert (src == null) != (text == null);
    let
      check = pkgs.buildPackages.writeShellScript "check-rendered-bash" ''
        set -e
        target=$1
        ${checkPhase pkgs {
          format = true;
          inherit shellcheckFlags;
        }}
      '';
      rendered = render name (if src == null then text else builtins.readFile src) replacements;
      firstLine = builtins.head (lib.splitString "\n" rendered);
      body =
        if !(lib.hasPrefix "#!" firstLine) then
          rendered
        else if
          lib.elem firstLine [
            "#!${lib.getExe pkgs.bash}"
            "#!${lib.getExe pkgs.bashNonInteractive}"
            "#!${pkgs.runtimeShell}"
            "#!/usr/bin/env bash"
            "#!/bin/bash"
          ]
        then
          if rendered == firstLine then "" else lib.removePrefix "${firstLine}\n" rendered
        else
          throw "${name}: expected a Bash shebang without interpreter arguments";
      runtimePath = lib.makeBinPath runtimeInputs;
      pathSetup =
        if inheritPath then
          lib.optionalString (runtimeInputs != [ ]) "export PATH=${lib.escapeShellArg runtimePath}:\"$PATH\""
        else
          "export PATH=${lib.escapeShellArg runtimePath}";
      # Passing a derivation keeps the executable metadata available without
      # forcing replacements that depend on the final module configuration.
      scriptBody =
        pkgs.runCommandLocal "${name}-body"
          {
            passAsFile = [ "scriptText" ];
            scriptText = lib.optionalString (pathSetup != "") (pathSetup + "\n") + body;
          }
          ''
            cp "$scriptTextPath" "$out"
          '';
      options.check = toString check;
    in
    if dir == "bin" then
      pkgs.writers.writeBashBin name options scriptBody
    else
      pkgs.writers.writeBash (if dir == null then name else "/${dir}/${name}") options scriptBody;
}
