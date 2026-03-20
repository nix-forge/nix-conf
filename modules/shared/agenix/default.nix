{
  nixos =
    { inputs, secrets, ... }:
    {
      imports = [ inputs.agenix.nixosModules.default ];

      services.openssh.enable = true;

      age = { inherit secrets; };
    };

  darwin =
    { inputs, secrets, ... }:
    {
      imports = [ inputs.agenix.darwinModules.default ];

      age = { inherit secrets; };
    };

  homeManager =
    {
      inputs,
      lib,
      pkgs,
      config,
      secrets,
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
      imports = [ inputs.agenix.homeManagerModules.default ];

      age = {
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
