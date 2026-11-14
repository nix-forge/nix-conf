{ lib }:
let
  checkNixTokenPolicy = import ../../flake/deploy/nix-token-policy.nix { inherit lib; };
  after = {
    secrets.nix-token-github-com = {
      source = "hosts/nixos/desktop/local/secrets/nix-token-github-com.age";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    templates.nix-access-tokens = {
      owner = "root";
      group = "root";
      mode = "0400";
      placeholders.nix-token-github-com = {
        secret = "nix-token-github-com";
        encoding = "utf8";
      };
    };
  };
  accepts =
    expectedSource: nixSeal:
    checkNixTokenPolicy {
      inherit nixSeal expectedSource;
      owner = "root";
      group = "root";
    };
  hostSource = "hosts/nixos/desktop/local/secrets/nix-token-github-com.age";
  homeSource = "homes/shared/local/secrets/nix-token-github-com.age";
  home = lib.recursiveUpdate after { secrets.nix-token-github-com.source = homeSource; };
  field = "nix-token-github-com";
  failures = lib.runTests {
    testProtectedSecret = {
      expr = accepts hostSource {
        secrets.nix-access-tokens = {
          source = hostSource;
          owner = "root";
          group = "root";
          mode = "0400";
        };
        templates = { };
      };
      expected = true;
    };
    testProtectedTemplate = {
      expr = accepts hostSource after;
      expected = true;
    };
    testProtectedHomeTemplate = {
      expr = accepts homeSource home;
      expected = true;
    };
    testWrongScope = {
      expr = accepts hostSource home;
      expected = false;
    };
    testTemplateOwnerMismatch = {
      expr = accepts hostSource (
        lib.recursiveUpdate after { templates.nix-access-tokens.owner = "unprivileged-fixture"; }
      );
      expected = false;
    };
    testPublicSecret = {
      expr = accepts hostSource (lib.recursiveUpdate after { secrets.${field}.mode = "0644"; });
      expected = false;
    };
    testUnexpectedCiphertextSource = {
      expr = accepts hostSource (
        lib.recursiveUpdate after { secrets.${field}.source = "secrets/wrong-source.age"; }
      );
      expected = false;
    };
    testMissingPlaceholderBinding = {
      expr = accepts hostSource (
        after
        // {
          templates.nix-access-tokens = after.templates.nix-access-tokens // {
            placeholders = { };
          };
        }
      );
      expected = false;
    };
  };
in
if failures == [ ] then true else throw "Template policy failures: ${builtins.toJSON failures}"
