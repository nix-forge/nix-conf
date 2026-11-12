# Exercise package selection without fetching restricted font payloads.
{ pkgs }:
let
  inherit (pkgs) lib;
  catalog = import ../../modules/shared/fonts/packages.nix { };
  personal = {
    twemoji-color-font-optional = "twemoji-fixture";
    google-fonts-design = "design-fixture";
    mplus-outline-fonts-compatible = "mplus-fixture";
    firefox-emoji = "firefox-fixture";
    emojione-legacy = "emojione-fixture";
    mutant-standard-emoji = "mutant-fixture";
    ttf-ms-win11-auto = "windows-evaluation-fixture";
    apple-color-emoji = "apple-emoji-fixture";
  };
  configuration =
    extra:
    (lib.evalModules {
      modules = [
        ../../modules/shared/fonts/options.nix
        extra
      ];
    }).config.typography;
  default = configuration { };
  alternate = configuration { typography.optionalEmoji.enable = true; };
  restricted = configuration { typography.restrictedFonts.enable = true; };
  all = configuration {
    typography.optionalEmoji.enable = true;
    typography.restrictedFonts.enable = true;
  };
  names = policy: map toString (catalog.select pkgs personal policy);
  # Missing restricted attributes must remain unevaluated under default policy.
  withoutRestricted = builtins.removeAttrs personal [
    "ttf-ms-win11-auto"
    "apple-color-emoji"
  ];
  safe = map toString (catalog.select pkgs withoutRestricted alternate);
  darwin =
    extra:
    (lib.evalModules {
      specialArgs = {
        system = "test-darwin";
        self.packages.test-darwin.apple-fonts.assets = lib.genAttrs [
          "apple-asset-brill-italic"
          "apple-asset-brill-roman"
          "apple-asset-canela-regular"
          "apple-asset-caneladeck-regular"
          "apple-asset-canelatext-regular"
          "apple-asset-domainedisplay-regular"
          "apple-asset-foundersgrotesk-regular"
          "apple-asset-foundersgroteskcond-reg"
          "apple-asset-foundersgrotesktext-regular"
          "apple-asset-graphik-regular"
          "apple-asset-graphikcompact-regular"
          "apple-asset-produkt-regular"
          "apple-asset-proximanova-regular"
          "apple-asset-publicoheadline-roman"
          "apple-asset-publicotext-roman"
          "apple-asset-spotmono-regular"
        ] (name: name);
      };
      modules = [
        (import ../../modules/shared/fonts/default.nix).darwin
        { options.fonts.packages = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
        extra
      ];
    }).config.fonts.packages;
in
assert !default.restrictedFonts.enable;
assert !(builtins.elem personal.ttf-ms-win11-auto (names default));
assert !(builtins.elem personal.apple-color-emoji (names alternate));
assert builtins.elem personal.firefox-emoji safe;
assert builtins.elem personal.ttf-ms-win11-auto (names restricted);
assert !(builtins.elem personal.apple-color-emoji (names restricted));
assert (builtins.elem personal.apple-color-emoji (names all)) == pkgs.stdenv.hostPlatform.isLinux;
assert darwin { } == [ ];
assert
  builtins.length (darwin {
    typography.restrictedFonts.enable = true;
  }) == 16;
pkgs.runCommand "font-catalog-policy" { } "touch $out"
