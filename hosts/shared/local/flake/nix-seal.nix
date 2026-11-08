{
  flake.nixSeal = {
    administrators.ianhollow = {
      identities = {
        administrator = {
          kind = "administrator";
          public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
        };
        recovery = {
          kind = "recovery";
          public = "age12h383letjnn5sag0799ssvfz94n83mwvcfcv87lkj379y0c65d0ss2t559";
        };
        release = {
          kind = "signer";
          public = "nix-seal-ed25519-v1:bGfuLIxQvDrT8IMpu931WWcILSKDrDmaCJ8oPFyT3X4=";
        };
        delegated-create = {
          kind = "authorizer";
          public = "nix-seal-ed25519-v1:Izzr/Ats9t9oXkXLl7+WotqnPeGdRhQdiR/i7Xlym2k=";
        };
      };
      approvalPolicies.release = {
        threshold = 1;
        signers = [ "release" ];
      };
      defaultApprovalPolicy = "release";
    };
  }
  // {
    defaultConfiguration = "nixosConfigurations.desktop";
  };
}
