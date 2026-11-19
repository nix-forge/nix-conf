{ myLib, pkgs }:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  inherit (pkgs) lib;
  root = ../..;
  coverage = builtins.fromJSON (builtins.readFile ../../scripts/typescript/projects.json);
  base = builtins.fromJSON (builtins.readFile ../../tsconfig.json);
  sourceFile =
    file:
    lib.any file.hasExt [
      "js"
      "mjs"
      "cjs"
      "jsx"
      "ts"
      "mts"
      "cts"
      "tsx"
    ];
  maintained = map toString (
    lib.fileset.toList (
      lib.fileset.unions (
        map (scope: lib.fileset.fileFilter sourceFile (root + "/${scope}")) coverage.scopes
      )
    )
  );
  required = [
    "strict"
    "noUncheckedIndexedAccess"
    "exactOptionalPropertyTypes"
    "noImplicitReturns"
    "noUnusedLocals"
    "noUnusedParameters"
    "noImplicitOverride"
    "noFallthroughCasesInSwitch"
    "noUncheckedSideEffectImports"
    "forceConsistentCasingInFileNames"
    "noPropertyAccessFromIndexSignature"
  ];
  strictDefaults = [
    "noImplicitAny"
    "strictNullChecks"
    "strictFunctionTypes"
    "strictBindCallApply"
    "strictPropertyInitialization"
    "strictBuiltinIteratorReturn"
    "noImplicitThis"
    "useUnknownInCatchVariables"
    "alwaysStrict"
  ];
  disabled = [
    "skipLibCheck"
    "allowUnreachableCode"
    "allowUnusedLabels"
  ];
  projects = map (
    name:
    let
      path = root + "/${name}";
      project = builtins.fromJSON (builtins.readFile path);
      resolve = relative: builtins.toPath "${toString (dirOf path)}/${relative}";
      options = base.compilerOptions // (project.compilerOptions or { });
      explicit =
        value:
        builtins.isString value
        && !lib.any (token: lib.hasInfix token value) [
          "*"
          "?"
          "["
          "]"
        ];
      valid =
        resolve project.extends == toString ../../tsconfig.json
        && lib.all (flag: (options.${flag} or null) == true) required
        && lib.all (flag: (options.${flag} or null) != false) strictDefaults
        && lib.all (flag: (options.${flag} or null) == false) disabled
        && (!(options.allowJs or false) || (options.checkJs or false))
        && lib.all explicit project.include;
    in
    if valid then
      {
        inherit name;
        files = map resolve project.include;
      }
    else
      throw "Invalid compiler policy for ${name}: retain strict options and explicit source coverage."
  ) coverage.projects;
  covered = lib.concatMap (project: project.files) projects;
  missing = lib.filter (path: !lib.elem path covered) maintained;
  check = writeShellApplication {
    name = "javascript-check";
    runtimeInputs = [
      pkgs.typescript
      pkgs.nodejs-slim_24
      pkgs.oxlint
      pkgs.prettier
    ];
    text =
      if missing != [ ] then
        throw "Sources missing a compiler project: ${lib.concatStringsSep ", " (map (lib.removePrefix "${toString root}/") missing)}"
      else
        myLib.templates.renderText
          {
            name = "javascript-lint.sh.in";
            text = ''
              # shellcheck shell=bash
              set -euo pipefail

              prettier --check --no-error-on-unmatched-pattern "scripts/**/*.{js,mjs,cjs,jsx,ts,mts,cts,tsx}" "modules/**/*.{js,mjs,cjs,jsx,ts,mts,cts,tsx}" tsconfig.json .oxlintrc.json scripts/typescript/projects.json
              @projectChecks@
              oxlint --type-aware --deny-warnings --config .oxlintrc.json modules
            '';
          }
          {
            projectChecks = lib.concatMapStringsSep "\n" (
              project: "tsc --project ${lib.escapeShellArg project.name} --noEmit"
            ) projects;
          };
  };
in
pkgs.symlinkJoin {
  name = "repository-javascript-tools";
  paths = [
    check
    pkgs.typescript
    pkgs.nodejs-slim_24
    pkgs.oxlint
    pkgs.prettier
  ];
  meta.mainProgram = "javascript-check";
}
