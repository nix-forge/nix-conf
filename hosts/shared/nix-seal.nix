{
  nixSeal = {
    sharedSecretDirectory = "modules/shared/secrets";

    secrets = {
      flakehub-login.source = "hosts/shared/secrets/flakehub-login.age";
      flakehub-password.source = "hosts/shared/secrets/flakehub-password.age";
    };
    templates = {
      flakehub-netrc = ''
        machine flakehub.com login {{nix-seal:flakehub-login}} password {{nix-seal:flakehub-password}}
        machine api.flakehub.com login {{nix-seal:flakehub-login}} password {{nix-seal:flakehub-password}}
        machine edge.cache.flakehub.com login {{nix-seal:flakehub-login}} password {{nix-seal:flakehub-password}}
        machine cache.flakehub.com login {{nix-seal:flakehub-login}} password {{nix-seal:flakehub-password}}
      '';
      nix-access-tokens = ''
        access-tokens = github.com={{nix-seal:nix-token-github-com}}
      '';
    };
  };
}
