{ pkgs }:
let
  render = import ../../lib/templates/text.nix;
  template = ./fixtures/text-rendering/template.txt;
  dependency = builtins.derivation {
    name = "unbuilt-text-rendering-fixture";
    system = pkgs.stdenv.hostPlatform.system;
    builder = "/nonexistent-text-rendering-fixture";
  };
  replacements = {
    value = "spaces '$`\\ and @dependency@";
    literal = null;
    path = ./fixtures/text-rendering/context.txt;
    inherit dependency;
  };
  output = render template replacements;
  force = expression: builtins.tryEval (builtins.deepSeq expression true);
  checks = [
    # Replacement contents are literal and repeated occurrences are substituted.
    (
      output
      == "${replacements.value}\n@literal@\n${replacements.path}\n${dependency}\n${replacements.value}\n"
    )
    (builtins.hasAttr (builtins.unsafeDiscardStringContext "${replacements.path}") (
      builtins.getContext output
    ))
    (builtins.hasAttr (builtins.unsafeDiscardStringContext dependency.drvPath) (
      builtins.getContext output
    ))
    (!(force (render template { })).success)
    (!(force (render template (replacements // { unused = "extra"; }))).success)
    (!(force (render template (replacements // { "bad-name" = "invalid"; }))).success)
  ];
in
assert pkgs.lib.all (value: value) checks;
pkgs.runCommand "text-rendering-regressions" { } (
  builtins.readFile ./scripts/text-rendering-check.sh
)
