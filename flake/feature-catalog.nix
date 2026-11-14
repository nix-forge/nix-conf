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
      source = "modules/home/services/ssh-forwards.nix";
      platforms = systems;
      interface = "services.sshForwards";
      dependencies = "Home Manager; provisioned SSH authentication and host keys";
      state = "Forward processes and private logs; endpoints remain target-owned";
      validation = "local-feature-reuse";
      guide = "runtime-features.md";
    }
    {
      name = "Protected Jujutsu identity";
      source = "modules/home/dev/jj-identity.nix";
      platforms = systems;
      interface = "programs.jujutsu.runtimeIdentity";
      dependencies = "Home Manager; myLib; runtime credential producer or enabled Git";
      state = "Private runtime identity fragment; signing policy remains independent";
      validation = "local-feature-reuse; python-tests; non-bash-python-helpers";
      guide = "runtime-features.md";
    }
    {
      name = "Rust editor support";
      source = "modules/home/vscode/languages/rust.nix";
      platforms = systems;
      interface = "programs.vscode.rust";
      dependencies = "Home Manager; nix4vscode input; project-owned Cargo toolchain";
      state = "Editor configuration; remote editor installation paths remain target-owned";
      validation = "local-feature-reuse";
      guide = "runtime-features.md";
    }
    {
      name = "Activation safety";
      source = "modules/nixos/system/activation-safety.nix";
      platforms = lib.filter (lib.hasSuffix "-linux") systems;
      interface = "system.activationSafety";
      dependencies = "NixOS native pre-switch checks; nvd";
      state = "No persistent application state; intentional hostname migrations are explicit";
      validation = "local-feature-reuse; python-tests";
      guide = "runtime-features.md";
    }
    {
      name = "Runtime IWD profiles";
      source = "modules/nixos/network/iwd-profiles.nix";
      platforms = lib.filter (lib.hasSuffix "-linux") systems;
      interface = "networking.wireless.iwd.runtimeProfiles";
      dependencies = "NixOS; myLib; protected root-owned runtime credential files";
      state = "Mutable IWD profiles; SSIDs and credentials remain outside the store";
      validation = "local-feature-reuse; iwd-runtime-profiles; python-tests";
      guide = "runtime-features.md";
    }
    {
      name = "Adaptive I/O cost";
      source = "modules/nixos/hardware/iocost.nix";
      platforms = lib.filter (lib.hasSuffix "-linux") systems;
      interface = "hardware.ioCost";
      dependencies = "NixOS; cgroup v2 I/O cost kernel support; selected whole disks";
      state = "Kernel controller state; measured operator policies take precedence";
      validation = "local-feature-reuse; python-tests; x86 desktop-iocost VM";
      guide = "runtime-features.md";
    }
    {
      name = "Independent Home Manager starter";
      source = "templates/starter/flake.nix";
      platforms = systems;
      interface = "templates.starter";
      dependencies = "Nix; independent Nixpkgs and Home Manager 26.05 pins";
      state = "Generated configuration; activation must be explicitly chosen";
      validation = "Export extraction, native home/generated-config checks and x86 Linux console VM";
      guide = "first-configuration.md";
    }
    {
      name = "Apple silicon system example";
      source = "templates/darwin/flake.nix";
      platforms = [ "aarch64-darwin" ];
      interface = "templates.darwin";
      dependencies = "Native Apple silicon Mac; independent stable Nixpkgs and nix-darwin pins";
      state = "Build-only example; operating-system activation requires adaptation";
      validation = "Native system build and generated Zsh/plist check; no activation claim";
      guide = "darwin-example.md";
    }
    {
      name = "Graphical practice VM";
      source = "tests/public-guide/graphical-vm.nix";
      platforms = [ "x86_64-linux" ];
      interface = "packages.x86_64-linux.public-demo-vm";
      dependencies = "QEMU; Sway software rendering; disposable local console";
      state = "Practice disk remains separate from the host account";
      validation = "Graphical login, real terminal keybindings and generated Git behavior";
      guide = "graphical-demo.md";
    }
    {
      name = "Validation and performance records";
      source = "scripts/workstation_evidence.py";
      platforms = systems;
      interface = "workstation-evidence CLI and validationManifest";
      dependencies = "Git; Nix for system validation; native host for platform-specific evidence";
      state = "Private local receipts and logs; reviewed summaries may be shared";
      validation = "Source filtering, failed/skipped evidence, timeouts, process cleanup and comparison regressions";
      guide = "validation.md";
    }
    {
      name = "Git defaults";
      source = "modules/home/dev/git.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; libsecret on Linux or Keychain on macOS for credential storage";
      state = "Repositories and credential-backend data remain user-owned";
      validation = "public-guide-recipes; public consumer checks";
      guide = "git.md";
    }
    {
      name = "File search";
      source = "modules/home/shells/fzf.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; shell integration module for keybindings";
      state = "No application database; searched files remain user-owned";
      validation = "public-guide-recipes; public consumer checks";
      guide = "file-search.md";
    }
    {
      name = "Shell prompt";
      source = "modules/home/shells/starship.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; shell integration";
      state = "No persistent application state required";
      validation = "public-guide-recipes; public consumer checks";
      guide = "prompt.md";
    }
    {
      name = "Secure Boot preparation";
      source = "modules/nixos/boot/secure-boot.nix";
      platforms = [ "x86_64-linux" ];
      interface = "security.secureBootLanzaboote options";
      dependencies = "Lanzaboote flake input; UEFI; attended key enrollment and recovery";
      state = "Signing keys, ESP and recovery material require independent protection";
      validation = "Configuration contracts; physical enrollment and recovery remain operator checks";
      guide = "update-and-recover.md";
    }
    {
      name = "Application recovery drills";
      source = "modules/nixos/services/application-recovery/default.nix";
      platforms = [ "x86_64-linux" ];
      interface = "services.applicationRecovery.applications options";
      dependencies = "Provisioned backup repository; application-specific export and semantic checks";
      state = "Exports, backup repositories and drill receipts; live recovery remains operator-owned";
      validation = "Real SQLite/Restic fixture and NixOS lifecycle test; no live restore claimed";
      guide = "recovery-drills.md";
    }
    {
      name = "Service and backup health";
      source = "hosts/nixos/desktop/local/storage/health.nix";
      platforms = [ "x86_64-linux" ];
      interface = "hardware.storage.encryptedRoot.health options (desktop-local)";
      dependencies = "Desktop storage policy; operator-provided unattended notification command";
      state = "Freshness receipts and pending delivery state; notification acceptance is tested separately";
      validation = "Health collection, failed delivery retries and recovery transition fixtures";
      guide = "recovery-drills.md";
    }
    {
      name = "Windows guest";
      source = "modules/nixos/virtualisation/windows-vm.nix";
      platforms = [ "x86_64-linux" ];
      interface = "virtualisation.libvirtWorkstation.windowsVm options";
      dependencies = "libvirtWorkstation module; myLib; KVM; user-supplied Windows media";
      state = "Disk, firmware variables and virtual TPM must be recovered together";
      validation = "Domain XML and seed tests; installed Windows runtime requires the actual guest";
      guide = "features.md";
    }
  ];
  valid = lib.all (feature: builtins.pathExists (self.outPath + "/" + feature.source)) features;
in
{
  flake.featureCatalog =
    assert valid;
    {
      schema = 1;
      inherit features;
    };
  perSystem =
    { pkgs, ... }:
    let
      documented = inputs.nixpkgs.lib.nixosSystem {
        system = pkgs.stdenv.hostPlatform.system;
        specialArgs = { inherit inputs myLib; };
        modules = [
          ../modules/nixos/system/activation-safety.nix
          ../modules/nixos/network/iwd-profiles.nix
          ../modules/nixos/hardware/iocost.nix
          ../modules/nixos/boot/secure-boot.nix
          ../modules/nixos/services/application-recovery
          ../modules/nixos/virtualisation/libvirt.nix
        ];
      };
      documentedHome = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs myLib; };
        modules = [
          ../modules/home/services/ssh-forwards.nix
          ../modules/home/dev/jj-identity.nix
          ../modules/home/vscode/languages/rust.nix
          {
            home = {
              username = "reference";
              homeDirectory = "/tmp/reference";
              stateVersion = "26.05";
            };
          }
        ];
      };
    in
    {
      packages.feature-catalog = pkgs.writeText "feature-catalog.json" (
        builtins.toJSON self.featureCatalog
      );
      packages.feature-options =
        (pkgs.nixosOptionsDoc {
          options = {
            system.activationSafety = documented.options.system.activationSafety;
            hardware.ioCost = documented.options.hardware.ioCost;
            networking.wireless.iwd.runtimeProfiles =
              documented.options.networking.wireless.iwd.runtimeProfiles;
            services.sshForwards = documentedHome.options.services.sshForwards;
            programs.jujutsu.runtimeIdentity = documentedHome.options.programs.jujutsu.runtimeIdentity;
            programs.vscode.rust = documentedHome.options.programs.vscode.rust;
            security.secureBootLanzaboote = documented.options.security.secureBootLanzaboote;
            services.applicationRecovery = documented.options.services.applicationRecovery;
            virtualisation.libvirtWorkstation = documented.options.virtualisation.libvirtWorkstation;
          };
          warningsAreErrors = true;
          transformOptions =
            option:
            option
            // {
              declarations = map (
                declaration:
                "https://github.com/nix-forge/nix-conf/blob/main/"
                + lib.removePrefix (toString self.outPath + "/") (toString declaration)
              ) option.declarations;
            };
        }).optionsJSON;
    };
}
