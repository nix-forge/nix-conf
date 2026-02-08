let
  # Optional local-only decrypt identities (ignored by git on purpose).
  # Typical software-key setup:
  #   [ "/Users/<user>/.config/agenix/master.agekey" ]
  bootstrapIdentitiesPath = ../../../secrets/master-identities/bootstrap-local.nix;
  # Committed public key for the primary master identity.
  mainIdentityPath = ../../../secrets/master-identities/main.pub;
  mainPubkey = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile mainIdentityPath);

  bootstrapIdentities =
    if builtins.pathExists bootstrapIdentitiesPath then import bootstrapIdentitiesPath else [ ];

  primaryMasterIdentity =
    identity:
    if builtins.isAttrs identity then
      identity // { pubkey = identity.pubkey or mainPubkey; }
    else
      {
        inherit identity;
        pubkey = mainPubkey;
      };

  # If a local bootstrap identity exists, use it for decryption and bind it to
  # the committed master pubkey for encryption.
  # Otherwise, fall back to the split-identity path in mainIdentityPath.
  masterIdentities =
    if bootstrapIdentities != [ ] then
      [ (primaryMasterIdentity (builtins.head bootstrapIdentities)) ]
      ++ (builtins.tail bootstrapIdentities)
    else
      [ mainIdentityPath ];

  agenixRekeyBaseConfig = sshPubKey: {
    storageMode = "local";
    hostPubkey = sshPubKey;
    inherit masterIdentities;
  };
in
{
  nixos =
    {
      inputs,
      sshPubKey,
      configName,
      lib,
      self,
      ...
    }:
    {
      imports = [
        inputs.agenix.nixosModules.default
        inputs.agenix-rekey.nixosModules.default
      ];

      age = {
        rekey = (agenixRekeyBaseConfig sshPubKey) // {
          localStorageDir = ../../../secrets/rekeyed + "/nixos-${configName}";
        };
        secrets = lib.mkMerge (
          [ self.secrets.shared.secrets ]
          ++ lib.optionals (self.secrets.systems ? nixos && self.secrets.systems.nixos ? configName) [
            self.secrets.systems.nixos.${configName}.secrets
          ]
        );
      };
    };
  darwin =
    {
      inputs,
      sshPubKey,
      configName,
      lib,
      self,
      ...
    }:
    {
      imports = [
        inputs.agenix.darwinModules.default
        inputs.agenix-rekey.nixosModules.default
      ];

      age = {
        rekey = (agenixRekeyBaseConfig sshPubKey) // {
          localStorageDir = ../../../secrets/rekeyed + "/darwin-${configName}";
        };
        secrets = lib.mkMerge (
          [ self.secrets.shared.secrets ]
          ++ lib.optionals (self.secrets.systems ? darwin && self.secrets.systems.darwin ? configName) [
            self.secrets.systems.darwin.${configName}.secrets
          ]
        );
      };
    };

  homeManager =
    {
      inputs,
      lib,
      pkgs,
      config,
      sshPubKey,
      configName,
      self,
      ...
    }:
    let

      inherit (pkgs.stdenv.hostPlatform) isDarwin;
      xdgRuntimeDir =
        let
          uid = toString config.home.uid;
        in
        if isDarwin then "/private/tmp/xdg-runtime-${uid}" else "/run/user/${uid}";
      ensureDarwinRuntimeApp = pkgs.replaceVarsWith {
        name = "hm-ensure-xdg-runtime-dir";
        src = ./ensure-xdg-runtime-dir.sh;
        dir = "bin";
        isExecutable = true;
        replacements = {
          inherit xdgRuntimeDir;
          inherit (config.home) username;
        };
      };
    in
    {
      imports = [
        inputs.agenix.homeManagerModules.default
        inputs.agenix-rekey.homeManagerModules.default
      ];

      age = {
        rekey = (agenixRekeyBaseConfig sshPubKey) // {
          localStorageDir =
            ../../../secrets/rekeyed + "/${builtins.replaceStrings [ "@" ] [ "-" ] configName}";
        };
        secrets = lib.mkMerge (
          [ self.secrets.shared.secrets ]
          ++ lib.optionals (self.secrets.users ? ${config.home.username}) [
            self.secrets.users.${config.home.username}.secrets
          ]
        );
        secretsDir = "${config.xdg.userDirs.extraConfig.RUNTIME}/agenix";
        secretsMountPoint = "${config.xdg.userDirs.extraConfig.RUNTIME}/agenix.d";
      };

      xdg = {
        enable = true;
        userDirs = {
          enable = true;
          createDirectories = true;
          extraConfig = {
            RUNTIME = xdgRuntimeDir;
          };
        };
      };
      home.activation.ensureXdgRuntimeDir = lib.mkIf isDarwin (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${lib.getExe' ensureDarwinRuntimeApp "hm-ensure-xdg-runtime-dir"}
        ''
      );
      launchd.agents.ensure-xdg-runtime-dir = {
        enable = true;
        config = {
          Label = "dev.user.hm-ensure-xdg-runtime-dir";
          ProgramArguments = [ (lib.getExe' ensureDarwinRuntimeApp "hm-ensure-xdg-runtime-dir") ];
          RunAtLoad = true;
          KeepAlive = false;
          ProcessType = "Background";
        };
      };
    };
}
