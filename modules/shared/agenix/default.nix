let
  # Committed public key for the primary master identity.
  mainIdentityPath = ../../../secrets/master-identities/main.pub;
  mainPubkey = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile mainIdentityPath);
  # Committed list of additional operator/team pubkeys that should also be able
  # to decrypt source secrets on their own machines.
  teamPubkeysPath = ../../../secrets/master-identities/team-pubkeys.nix;
  teamPubkeys = import teamPubkeysPath;

  # Optional per-host passphrase-protected identity that lives outside the
  # repository. Keep this as a string path (not a Nix path literal) so private
  # keys are never copied into the Nix store.
  agenixRekeyBaseConfig =
    {
      sshPubKey,
      masterIdentityPath ? null,
    }:
    {
      storageMode = "local";
      hostPubkey = sshPubKey;
      extraEncryptionPubkeys = teamPubkeys;
      masterIdentities = [
        (
          if masterIdentityPath != null then
            {
              identity = masterIdentityPath;
              pubkey = mainPubkey;
            }
          else
            # Public-only fallback keeps evaluation stable on non-admin hosts.
            mainIdentityPath
        )
      ];
    };
in
{
  nixos =
    {
      inputs,
      lib,
      pkgs,
      config,
      sshPubKey,
      masterIdentityPath ? null,
      secrets,
      configName,
      ...
    }:
    let
      parsedSshPubKey = builtins.match "([^ ]+) ([^ ]+).*" sshPubKey;
      expectedHostKeyType =
        if parsedSshPubKey == null then
          throw "Invalid sshPubKey for nixos host '${configName}': expected '<type> <base64> [comment]'"
        else
          builtins.elemAt parsedSshPubKey 0;
      expectedHostKeyBody = builtins.elemAt parsedSshPubKey 1;

      ed25519HostKey = lib.findFirst (
        hostKey: hostKey.type == "ed25519"
      ) null config.services.openssh.hostKeys;
      hostKeyPath =
        if ed25519HostKey != null then ed25519HostKey.path else "/etc/ssh/ssh_host_ed25519_key";
      hostKeyPubPath = "${hostKeyPath}.pub";

      preflightScript = pkgs.replaceVarsWith {
        name = "agenix-check-host-key";
        src = ./check-host-key.sh;
        dir = "bin";
        isExecutable = true;
        replacements = {
          inherit expectedHostKeyType expectedHostKeyBody hostKeyPubPath;
          hostName = configName;
          installGuidePath = "docs/nixos-install-preseeded-host-key.md";
        };
      };
      preflightCommand = "${lib.getExe' preflightScript "agenix-check-host-key"}";

      sysusersEnabled =
        (config.systemd.sysusers.enable or false) || (config.services.userborn.enable or false);
    in
    {
      imports = [
        inputs.agenix.nixosModules.default
        inputs.agenix-rekey.nixosModules.default
      ];

      services.openssh.enable = true;

      age = {
        rekey = (agenixRekeyBaseConfig { inherit sshPubKey masterIdentityPath; }) // {
          localStorageDir = ../../../secrets/rekeyed + "/nixos-${configName}";
        };
        inherit secrets;
      };

      system.activationScripts = lib.mkIf (secrets != { } && !sysusersEnabled) {
        agenixHostKeyPreflight = {
          text = preflightCommand;
          deps = [ "specialfs" ];
        };
        agenixNewGeneration.deps = [ "agenixHostKeyPreflight" ];
      };

      systemd.services.agenix-host-key-preflight = lib.mkIf (secrets != { } && sysusersEnabled) {
        wantedBy = [ "sysinit.target" ];
        before = [ "agenix-install-secrets.service" ];
        after = [ "systemd-sysusers.service" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = preflightCommand;
          RemainAfterExit = true;
        };
      };
    };

  darwin =
    {
      inputs,
      sshPubKey,
      masterIdentityPath ? null,
      secrets,
      configName,
      ...
    }:
    {
      imports = [
        inputs.agenix.darwinModules.default
        inputs.agenix-rekey.darwinModules.default
      ];

      age = {
        rekey = (agenixRekeyBaseConfig { inherit sshPubKey masterIdentityPath; }) // {
          localStorageDir = ../../../secrets/rekeyed + "/darwin-${configName}";
        };
        inherit secrets;
      };
    };

  homeManager =
    {
      inputs,
      lib,
      pkgs,
      config,
      sshPubKey,
      masterIdentityPath ? null,
      secrets,
      configName,
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
        rekey =
          (agenixRekeyBaseConfig {
            inherit sshPubKey;
            inherit masterIdentityPath;
          })
          // {
            localStorageDir =
              ../../../secrets/rekeyed + "/${builtins.replaceStrings [ "@" ] [ "-" ] configName}";
          };
        inherit secrets;
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
