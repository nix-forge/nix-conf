let
  mainIdentityPath = ../../../secrets/master-identities/main.pub;
  mainPubkey = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile mainIdentityPath);

  # Optional per-host master identity that lives outside the
  # repository. Keep this as a string path (not a Nix path literal) so private
  # keys are never copied into the Nix store.
  agenixRekeyBaseConfig =
    {
      sshPubKey,
      masterIdentityPath ? null,
      lib,
    }:
    let
      # Security guardrails:
      # - Must be a plain string, not a Nix path literal (which would copy into the store)
      # - Must be absolute and not inside /nix/store
      validatedMasterIdentityPath =
        if masterIdentityPath == null then
          null
        else if !builtins.isString masterIdentityPath then
          throw "masterIdentityPath must be a string path not a Nix path literal."
        else if builtins.substring 0 1 masterIdentityPath != "/" then
          throw "masterIdentityPath must be an absolute path."
        else if builtins.match "^/nix/store/.*" masterIdentityPath != null then
          throw "masterIdentityPath must not point into /nix/store."
        else
          masterIdentityPath;
    in
    {
      storageMode = "local";
      hostPubkey = sshPubKey;
      masterIdentities = lib.mkIf (validatedMasterIdentityPath != null) [
        {
          identity = validatedMasterIdentityPath;
          pubkey = mainPubkey;
        }
      ];
    };
in
{
  nixos =
    {
      inputs,
      lib,
      sshPubKey,
      masterIdentityPath ? null,
      secrets,
      configName,
      ...
    }:
    {
      imports = [
        inputs.agenix.nixosModules.default
        inputs.agenix-rekey.nixosModules.default
      ];

      services.openssh.enable = true;

      age = {
        rekey = (agenixRekeyBaseConfig { inherit sshPubKey masterIdentityPath lib; }) // {
          localStorageDir = ../../../secrets/rekeyed + "/nixos-${configName}";
        };
        inherit secrets;
      };
    };

  darwin =
    {
      inputs,
      sshPubKey,
      masterIdentityPath ? null,
      secrets,
      configName,
      lib,
      ...
    }:
    {
      imports = [
        inputs.agenix.darwinModules.default
        inputs.agenix-rekey.darwinModules.default
      ];

      age = {
        rekey = (agenixRekeyBaseConfig { inherit sshPubKey masterIdentityPath lib; }) // {
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
        rekey = (agenixRekeyBaseConfig { inherit sshPubKey masterIdentityPath lib; }) // {
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
