{ lib }:
let
  checkNixTokenPolicy = import ../../flake/deploy/nix-token-policy.nix { inherit lib; };
  after = {
    secrets.nix-token-github-com = {
      source = "modules/shared/secrets/nix-token-github-com.age";
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
    nixSeal:
    checkNixTokenPolicy {
      inherit nixSeal;
      owner = "root";
      group = "root";
    };
  field = "nix-token-github-com";
  failures = lib.runTests {
    testProtectedTemplate = {
      expr = accepts after;
      expected = true;
    };
    testTemplateOwnerMismatch = {
      expr = accepts (
        lib.recursiveUpdate after {
          templates.nix-access-tokens.owner = "unprivileged-fixture";
        }
      );
      expected = false;
    };
    testPublicSecret = {
      expr = accepts (lib.recursiveUpdate after { secrets.${field}.mode = "0644"; });
      expected = false;
    };
    testUnexpectedCiphertextSource = {
      expr = accepts (
        lib.recursiveUpdate after {
          secrets.${field}.source = "secrets/wrong-source.age";
        }
      );
      expected = false;
    };
    testMissingPlaceholderBinding = {
      expr = accepts (
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
