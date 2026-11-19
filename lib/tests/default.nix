{ lib }:
let
  myLib = import ../. { inherit lib; };
  inherit (myLib.systemd) execArgs;
  inherit (myLib.dir) collectBySuffix;
  inherit (myLib.desktop) resolveHyprlandPackage;
  inherit (myLib.templates) renderText;
  template = ./fixtures/text-rendering/template.txt;
  replacements = {
    value = "spaces '$`\\ and @dependency@";
    literal = null;
    path = ./fixtures/text-rendering/context.txt;
    dependency = "dependency";
  };
  rendered = renderText template replacements;
in
{
  rendering = {
    testLiteralReplacement = {
      expr = rendered;
      expected = "${replacements.value}\n@literal@\n${replacements.path}\ndependency\n${replacements.value}\n";
    };
    testInlineReplacement = {
      expr = renderText {
        name = "inline-script";
        text = "printf '%s' @argument@";
      } { argument = lib.escapeShellArg "a b"; };
      expected = "printf '%s' 'a b'";
    };
    testPathContext = {
      expr = builtins.hasAttr (builtins.unsafeDiscardStringContext "${replacements.path}") (
        builtins.getContext rendered
      );
      expected = true;
    };
    testMissingReplacement = {
      expr = renderText template { };
      expectedError.type = "ThrownError";
      expectedError.msg = "renderText: missing replacements.*";
    };
    testUnusedReplacement = {
      expr = renderText template (replacements // { unused = "extra"; });
      expectedError.type = "ThrownError";
      expectedError.msg = "renderText: unused replacements.*";
    };
    testInvalidName = {
      expr = renderText template (replacements // { "bad-name" = "invalid"; });
      expectedError.type = "ThrownError";
      expectedError.msg = "renderText: invalid placeholder name";
    };
  };
  systemdArgs = {
    testEmpty = {
      expr = execArgs [ ];
      expected = "";
    };
    testEscaping = {
      expr = execArgs [
        "a b"
        "$HOME"
        "%u"
        "\"quoted\""
        ""
        "a\\b"
      ];
      expected = ''"a b" "$$HOME" "%%u" "\"quoted\"" "" "a\\b"'';
    };
  };
  directory = {
    testRecursiveCollection = {
      expr = collectBySuffix "file" ".txt" "items" ./fixtures/collection;
      expected = {
        items.first.file = ./fixtures/collection/first.txt;
        nested.items.second.file = ./fixtures/collection/nested/second.txt;
      };
    };
    testNoMatches = {
      expr = collectBySuffix "file" ".missing" "items" ./fixtures/collection;
      expected = {
        nested = { };
      };
    };
  };
  hyprland = {
    testHomeSelection = {
      expr = resolveHyprlandPackage {
        config.wayland.windowManager.hyprland.package = "home";
        osConfig.programs.hyprland = {
          enable = true;
          package = "system";
        };
        pkgs.hyprland = "fallback";
      };
      expected = "home";
    };
    testSystemFallback = {
      expr = resolveHyprlandPackage {
        config.wayland.windowManager.hyprland.package = null;
        osConfig.programs.hyprland = {
          enable = true;
          package = "system";
        };
        pkgs.hyprland = "fallback";
      };
      expected = "system";
    };
    testPackageFallback = {
      expr = resolveHyprlandPackage {
        config.wayland.windowManager.hyprland.package = null;
        pkgs.hyprland = "fallback";
      };
      expected = "fallback";
    };
  };
}
