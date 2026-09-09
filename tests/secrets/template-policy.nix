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
in
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
