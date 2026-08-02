{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
  credentialsPath = ../.nix-seal/public.nix;
  credentials = if builtins.pathExists credentialsPath then import credentialsPath else null;

  targetDefinitions = {
    "home/ianmh/desktop" = {
      kind = "homeManager";
      system = "x86_64-linux";
      username = "ianmh";
      configuration = "desktop";
      public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEolRZAKwwqDLSkgezpqNK4WYLjMsE1qp8f3k7nYMVgq";
    };
    "home/ianmh/macbook-pro-m4" = {
      kind = "homeManager";
      system = "aarch64-darwin";
      username = "ianmh";
      configuration = "macbook-pro-m4";
      public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
    };
    "host/nixos/desktop" = {
      kind = "nixOs";
      system = "x86_64-linux";
      configuration = "desktop";
      public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwSeiaY3PpNjPDaFA9bDPeFaLU5HYi0PrJKEEYIt3Vs";
    };
    "host/darwin/macbook-pro-m4" = {
      kind = "darwin";
      system = "aarch64-darwin";
      configuration = "macbook-pro-m4";
      public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
    };
  };

  homeTargets = [
    "home/ianmh/desktop"
    "home/ianmh/macbook-pro-m4"
  ];
  systemTargets = [
    "host/nixos/desktop"
    "host/darwin/macbook-pro-m4"
  ];
  allTargets = homeTargets ++ systemTargets;

  homeSecret = name: {
    source = "secrets/IanHollow/home/ianmh/${name}.age";
    consumers = homeTargets;
    delivery = "rekeyed";
    administrators = [
      "administrator"
      "recovery"
    ];
    approvalPolicy = "release";
    phase = "activation";
    runtime = {
      owner = "ianmh";
      # Linux Home Manager conventionally uses the user's private group.
      group = "ianmh";
      mode = "0400";
    };
    runtimeOverrides."home/ianmh/macbook-pro-m4" = {
      # macOS account groups use `staff`; a Home Manager activation cannot
      # change to an unrelated privileged group.
      owner = "ianmh";
      group = "staff";
      mode = "0400";
    };
    lifecycle = {
      contact = "Ian Hollow";
      classification = "private";
    };
  };

  secretDefinitions = {
    "ianhollow/nix-access-tokens/system" = {
      source = "secrets/IanHollow/nix-access-tokens.age";
      consumers = systemTargets;
      delivery = "rekeyed";
      administrators = [
        "administrator"
        "recovery"
      ];
      approvalPolicy = "release";
      phase = "activation";
      runtime = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      lifecycle = {
        contact = "Ian Hollow";
        classification = "private";
      };
    };
    "ianhollow/nix-access-tokens/home" = (homeSecret "nix-access-tokens") // {
      source = "secrets/IanHollow/home/ianmh/nix-access-tokens.age";
    };
    "ianhollow/home/ianmh/cornell-net-id-ssh-config" = homeSecret "cornell-net-id-ssh-config";
    "ianhollow/home/ianmh/git-allowedsigners" = homeSecret "git-allowedSigners";
    "ianhollow/home/ianmh/gitconfig-username" = homeSecret "gitconfig-userName";
    "ianhollow/home/ianmh/gitconfig-useremail" = homeSecret "gitconfig-userEmail";
    "ianhollow/home/ianmh/gitconfig-useremail-cornell" = homeSecret "gitconfig-userEmail-Cornell";
    "ianhollow/home/ianmh/gitconfig-useremail-github" = homeSecret "gitconfig-userEmail-GitHub";
    "ianhollow/home/ianmh/hf-token" = homeSecret "hf_token";
  };

  targetIdentityId = targetId: "target/${targetId}";
  planObjects = {
    identities = {
      administrator = {
        kind = "administrator";
        public = credentials.administratorRecipient;
      };
      recovery = {
        kind = "administrator";
        public = credentials.recoveryRecipient;
      };
      release = {
        kind = "signer";
        public = credentials.signerPublicKey;
      };
    }
    // lib.mapAttrs' (
      targetId: target:
      lib.nameValuePair (targetIdentityId targetId) {
        kind = "target";
        inherit (target) public;
      }
    ) targetDefinitions;
    groups.ianhollow.members = allTargets;
    targets = lib.mapAttrs (
      targetId: target:
      (builtins.removeAttrs target [ "public" ]) // { identity = targetIdentityId targetId; }
    ) targetDefinitions;
    secrets = secretDefinitions;
    approvalPolicies.release = {
      threshold = 1;
      signers = [ "release" ];
    };
  };

  selectedSecrets =
    targetId: lib.filterAttrs (_: secret: lib.elem targetId secret.consumers) secretDefinitions;

  artifactConfig =
    targetId: secretId:
    lib.attrByPath [ "artifacts" targetId secretId ] null (
      if credentials == null then { } else credentials
    );

  artifactFor =
    targetId: secretId:
    let
      configured = artifactConfig targetId secretId;
    in
    if configured == null then
      {
        artifact = null;
        sourceCiphertextHash = null;
        artifactGeneration = 1;
      }
    else
      let
        path = "${inputs.nix-seal-artifacts}/artifacts/${configured.cacheKey}";
      in
      {
        artifact = inputs.nix-seal.lib.artifactBundle {
          inherit path;
          target = targetId;
          secret = secretId;
        };
        inherit (configured) sourceCiphertextHash;
        inherit (configured) artifactGeneration;
      };

  targetIdFor =
    kind: target:
    if kind == "home" then
      "home/${target.username}/${target.folderName}"
    else
      "host/${kind}/${target.folderName}";

  identityFileFor =
    kind: target:
    if kind == "home" then
      "${target.homeDirectory}/.ssh/id_ed25519"
    else
      "/etc/ssh/ssh_host_ed25519_key";
in
{
  inherit credentialsPath secretDefinitions targetDefinitions;
  available = credentials != null;
  planObjects = if credentials == null then null else planObjects;
  planJson = if credentials == null then null else inputs.nix-seal.lib.mkPlan planObjects;

  forTarget =
    { kind, target }:
    let
      targetId = targetIdFor kind target;
    in
    {
      inherit targetId;
      enable = credentials != null && builtins.hasAttr targetId targetDefinitions;
      identityFile = identityFileFor kind target;
      planObjects = if credentials == null then null else planObjects;
      secrets = lib.mapAttrs (secretId: _: artifactFor targetId secretId) (selectedSecrets targetId);
    };
}
