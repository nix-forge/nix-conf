{
  self,
  lib,
  inputs,
  myLib,
  ...
}:
let
  systems = import ./supported-systems.nix;
  features = [
    {
      name = "Supervised SSH forwards";
      optionReference = {
        kind = "home";
        path = "services.sshForwards";
      };
      source = "modules/home/services/ssh-forwards.nix";
      platforms = systems;
      dependencies = "Home Manager; provisioned SSH authentication and host keys";
      state = "Forward processes and private logs; endpoints remain target-owned";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "runtime-features.md";
    }
    {
      name = "Protected Jujutsu identity";
      optionReference = {
        kind = "home";
        path = "programs.jujutsu.runtimeIdentity";
      };
      source = "modules/home/dev/jj-identity.nix";
      platforms = systems;
      dependencies = "Home Manager; myLib; runtime credential producer or enabled Git";
      state = "Private runtime identity fragment; signing policy remains independent";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "runtime-features.md";
    }
    {
      name = "Rust editor support";
      optionReference = {
        kind = "home";
        path = "programs.vscode.rust";
      };
      source = "modules/home/vscode/languages/rust.nix";
      platforms = systems;
      dependencies = "Home Manager; nix4vscode input; project-owned Cargo toolchain";
      state = "Editor configuration; remote editor installation paths remain target-owned";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "runtime-features.md";
    }
    {
      name = "Activation safety";
      optionReference = {
        kind = "nixos";
        path = "system.activationSafety";
      };
      source = "modules/nixos/system/activation-safety.nix";
      platforms = lib.filter (lib.hasSuffix "-linux") systems;
      dependencies = "NixOS native pre-switch checks; nvd";
      state = "No persistent application state; intentional hostname migrations are explicit";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "runtime-features.md";
    }
    {
      name = "Runtime IWD profiles";
      optionReference = {
        kind = "nixos";
        path = "networking.wireless.iwd.runtimeProfiles";
      };
      source = "modules/nixos/network/iwd-profiles.nix";
      platforms = lib.filter (lib.hasSuffix "-linux") systems;
      dependencies = "NixOS; myLib; protected root-owned runtime credential files";
      state = "Mutable IWD profiles; SSIDs and credentials remain outside the store";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "runtime-features.md";
    }
    {
      name = "Adaptive I/O cost";
      optionReference = {
        kind = "nixos";
        path = "hardware.ioCost";
      };
      source = "modules/nixos/hardware/iocost.nix";
      platforms = lib.filter (lib.hasSuffix "-linux") systems;
      dependencies = "NixOS; cgroup v2 I/O cost kernel support; selected whole disks";
      state = "Kernel controller state; measured operator policies take precedence";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "runtime-features.md";
    }
    {
      name = "Graphical practice VM";
      source = "flake/public-demo/graphical-vm.nix";
      platforms = [ "x86_64-linux" ];
      interface = "packages.x86_64-linux.public-demo-vm";
      dependencies = "QEMU; Sway software rendering; disposable local console";
      state = "Practice disk remains separate from the host account";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "graphical-demo.md";
    }
    {
      name = "Validation and performance records";
      source = "scripts/workstation-evidence";
      platforms = systems;
      interface = "workstation-evidence CLI and validationManifest";
      dependencies = "Git; Nix for system validation; native host for platform-specific evidence";
      state = "Private local receipts and logs; reviewed summaries may be shared";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "validation.md";
    }
    {
      name = "Git defaults";
      source = "modules/home/dev/git.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; libsecret on Linux or Keychain on macOS for credential storage";
      state = "Repositories and credential-backend data remain user-owned";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "git.md";
    }
    {
      name = "File search";
      source = "modules/home/shells/fzf.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; shell integration module for keybindings";
      state = "No application database; searched files remain user-owned";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "file-search.md";
    }
    {
      name = "Shell prompt";
      source = "modules/home/shells/starship.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; shell integration";
      state = "No persistent application state required";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "prompt.md";
    }
    {
      name = "Secure Boot preparation";
      optionReference = {
        kind = "nixos";
        path = "security.secureBootLanzaboote";
      };
      source = "modules/nixos/boot/secure-boot.nix";
      platforms = [ "x86_64-linux" ];
      interface = "security.secureBootLanzaboote options";
      dependencies = "Lanzaboote flake input; UEFI; attended key enrollment and recovery";
      state = "Signing keys, ESP and recovery material require independent protection";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "update-and-recover.md";
    }
    {
      name = "Application recovery drills";
      optionReference = {
        kind = "nixos";
        path = "services.applicationRecovery";
      };
      source = "modules/nixos/services/application-recovery/default.nix";
      platforms = [ "x86_64-linux" ];
      interface = "services.applicationRecovery.applications options";
      dependencies = "Provisioned backup repository; application-specific export and semantic checks";
      state = "Exports, backup repositories and drill receipts; live recovery remains operator-owned";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "recovery-drills.md";
    }
    {
      name = "Service and backup health";
      source = "hosts/nixos/desktop/local/storage/health.nix";
      platforms = [ "x86_64-linux" ];
      interface = "hardware.storage.encryptedRoot.health options (desktop-local)";
      dependencies = "Desktop storage policy; operator-provided unattended notification command";
      state = "Freshness receipts and pending delivery state; notification acceptance is tested separately";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "recovery-drills.md";
    }
    {
      name = "Windows guest";
      optionReference = {
        kind = "nixos";
        path = "virtualisation.libvirtWorkstation";
        moduleSource = "modules/nixos/virtualisation/libvirt.nix";
      };
      source = "modules/nixos/virtualisation/windows-vm.nix";
      platforms = [ "x86_64-linux" ];
      interface = "virtualisation.libvirtWorkstation.windowsVm options";
      dependencies = "libvirtWorkstation module; myLib; KVM; user-supplied Windows media";
      state = "Disk, firmware variables and virtual TPM must be recovered together";
      validation = "Static checks and module setting validation; runtime acceptance is operator-owned";
      guide = "features.md";
    }
  ];
  documentedFeatures = builtins.filter (feature: feature ? optionReference) features;
  optionReferences = map (
    feature:
    feature.optionReference
    // {
      source = ../. + "/${feature.optionReference.moduleSource or feature.source}";
      path = lib.splitString "." feature.optionReference.path;
    }
  ) documentedFeatures;
  catalogSources = lib.unique (
    map (feature: feature.source) features
    ++ map (feature: feature.optionReference.moduleSource or feature.source) documentedFeatures
  );
  missingSources = builtins.filter (
    source: !builtins.pathExists (self.outPath + "/" + source)
  ) catalogSources;
  modulesFor =
    kind:
    map (reference: reference.source) (
      builtins.filter (reference: reference.kind == kind) optionReferences
    );
in
{
  flake.featureCatalog =
    assert lib.assertMsg (
      missingSources == [ ]
    ) "Feature catalog source paths do not exist: ${lib.concatStringsSep ", " missingSources}";
    {
      schema = 1;
      features = map (
        feature:
        removeAttrs feature [ "optionReference" ]
        // {
          interface = feature.interface or feature.optionReference.path;
        }
      ) features;
    };
  perSystem =
    { pkgs, ... }:
    let
      documented = {
        nixos = inputs.nixpkgs.lib.nixosSystem {
          system = pkgs.stdenv.hostPlatform.system;
          specialArgs = { inherit inputs myLib; };
          modules = modulesFor "nixos";
        };
        home = inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs myLib; };
          modules = modulesFor "home" ++ [
            {
              home = {
                username = "reference";
                homeDirectory = "/tmp/reference";
                stateVersion = "26.05";
              };
            }
          ];
        };
      };
      options = lib.foldl' lib.recursiveUpdate { } (
        map (
          reference:
          lib.setAttrByPath reference.path (
            lib.getAttrFromPath reference.path documented.${reference.kind}.options
          )
        ) optionReferences
      );
      optionDocs =
        linkedDeclarations:
        pkgs.nixosOptionsDoc {
          inherit options;
          warningsAreErrors = true;
          transformOptions =
            option:
            option
            // {
              declarations = map (
                declaration:
                let
                  name = lib.removePrefix (toString self.outPath + "/") (toString declaration);
                  url = "https://github.com/nix-forge/nix-conf/blob/main/" + name;
                in
                if linkedDeclarations then { inherit name url; } else url
              ) option.declarations;
            };
        };
    in
    {
      packages.feature-catalog = pkgs.writeText "feature-catalog.json" (
        builtins.toJSON self.featureCatalog
      );
      packages.feature-options = (optionDocs false).optionsJSON;
      packages.feature-options-markdown = (optionDocs true).optionsCommonMark;
    };
}
