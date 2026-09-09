{
  nixSeal = {
    sharedSecretDirectory = "modules/shared/secrets";

    secrets = {
      flakehub-login.source = "hosts/shared/secrets/flakehub-login.age";
      flakehub-password.source = "hosts/shared/secrets/flakehub-password.age";
    };
    templates = {
      flakehub-netrc = ./templates/flakehub.netrc.template;
      nix-access-tokens = ../../modules/shared/templates/nix-access-tokens.conf.template;
    };
  };
}
