{ lib }:
let
  myLib = import ../../lib { inherit lib; };
  apply =
    repositoryRoot:
    myLib.secrets.mkTemplates {
      inherit repositoryRoot;
      inventoryFiles = [ ../../homes/shared/local/config/secret-templates/inventory.json ];
      scope = "ianhollow/hosts/nixos/desktop";
      secrets."nix-access-tokens" = {
        source = "secrets/ianhollow/users/ianmh/nix-access-tokens.age";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  before = apply ./fixtures/unmigrated;
  after = apply ./fixtures/migrated;
  accepts =
    nixSeal:
    myLib.secrets.checkNixTokenPolicy {
      inherit nixSeal;
      owner = "root";
      group = "root";
    };
  field = "nix-token-github-com";
in
assert !(builtins.tryEval (builtins.deepSeq before true)).success;
assert after.templates ? nix-access-tokens;
assert !(after.secrets ? nix-access-tokens);
assert after.secrets.${field}.owner == "root";
assert after.secrets.${field}.mode == "0400";
assert accepts after;
assert
  !(accepts (
    after
    // {
      templates."nix-access-tokens" = after.templates."nix-access-tokens" // {
        owner = "unprivileged-fixture";
      };
    }
  ));

assert
  !(accepts (
    after
    // {
      secrets = after.secrets // {
        ${field} = after.secrets.${field} // {
          mode = "0644";
        };
      };
    }
  ));
assert
  !(accepts (
    after
    // {
      secrets = after.secrets // {
        ${field} = after.secrets.${field} // {
          source = "secrets/wrong-source.age";
        };
      };
    }
  ));
assert
  !(accepts (
    after
    // {
      templates."nix-access-tokens" = after.templates."nix-access-tokens" // {
        placeholders = { };
      };
    }
  ));
true
